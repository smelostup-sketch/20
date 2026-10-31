extends Node
class_name SkyLightController
## Q7.33 — ЕДИНСТВЕННЫЙ писатель света сцены (п. 9/12.1 ТЗ):
## DirectionalLight3D (SunLight, MoonLight) и WorldEnvironment.environment.
## Параметров шейдера не касается вообще (адрес записи «материал» принадлежит
## SkyEnvironmentController). Знает узлы сцены, углы и живые ручки панели.
##
## Q.7.34.PreOmega_Sky.4.1.1 (граница удаления, добро заказчика 30.10 п.4):
## - apply_light + SkyLightProfile УДАЛЕНЫ: пресет свет не несёт;
## - вкладка «Свет сцены» ПАНЕЛИ СОХРАНЕНА (приказ заказчика 31.10 п.3) как
##   ЖИВЫЕ ручки узлов SunLight/MoonLight/Environment — с пресетами не связана;
## - geometрия Sun/Moon (углы → basis, enabled) и tonemap — СОХРАНЕНЫ (добро п.4);
## - НОВое: этот контроллер — владелец трансформации/параметров Sun, поэтому
##   после каждого изменения Sun он событийно вызывает atmosphere.publish()
##   (план света §4.3: «publish() вызывается владельцем изменения Sun»,
##   без polling и _process).

## Новый контракт освещения (этап 02 плана): компонент читает SunLight и
## публикует AtmosphereLightingState. Ссылка назначается в сцене; null =
## компонент не собран (свет живёт по-старому, publish не вызывается).
@export var atmosphere: AtmosphereLightingComponent

@export var sun_light: DirectionalLight3D
## MoonLight — ВРЕМЕННАЯ ЗАГЛУШКА до интеграции Moon (единственное исключение
## §2 плана света, решение заказчика 30.10 п.3). Фиктивное лунное освещение
## не наращивать: узел и диск луны сохранены, в новый контракт НЕ входят.
@export var moon_light: DirectionalLight3D
@export var environment: Environment

var sun_azimuth: float = 180.0
var sun_elevation: float = 0.5
var moon_azimuth: float = 0.0
var moon_elevation: float = 50.0


func _ready() -> void:
	# Q7.34 (S2): FREEZE цепи вывода. Round-trip неба и все палитры откалиброваны
	# под Filmic (tonemap_mode = 2, цепи A: байт = srgb_encode(filmic(linear))).
	# Q7.34 (COLORS5): Filmic и Linear — ОБА поддерживаются шейдером (sk_tonemap,
	# disp2scene/scene2disp): байт-точность палитры на стопах держится в обоих.
	# Режим переключается из пресета (tonemap_linear) / чекбокса панели. Любой
	# ТРЕТИЙ режим (Reinhardt/ACES/AgX) по-прежнему ломает палитры — предупреждаем.
	if environment != null:
		var m: int = environment.tonemap_mode
		if m != Environment.TONE_MAPPER_FILMIC and m != Environment.TONE_MAPPER_LINEAR:
			push_warning("Q7.34: Environment.tonemap_mode = %d — поддерживаются только TONE_MAPPER_FILMIC (2) и TONE_MAPPER_LINEAR (0). Палитры неба съедут." % m)


## Q7.34 (COLORS5): переключатель тонмапа Filmic/Linear. Пишется ВМЕСТЕ с
## uniform sk_tonemap материала (SkyEnvironmentController.apply_palette) —
## пара «движок ↔ шейдер» обязана совпадать, иначе round-trip разъезжается.
func set_tonemap_linear(linear: bool) -> void:
	if environment == null:
		return
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR if linear else Environment.TONE_MAPPER_FILMIC


## ОДИН расчёт направления на источник — на шейдер и на свет (п. 12.2 ТЗ:
## «солнце на небе» и «откуда тени» не могут разъехаться). Статическая:
## SkyEnvironmentController вызывает её же.
static func direction_from_angles(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az: float = deg_to_rad(azimuth_deg)
	var el: float = deg_to_rad(elevation_deg)
	return Vector3(
		sin(az) * cos(el),
		sin(el),
		-cos(az) * cos(el)
	).normalized()


func set_sun_angles(azimuth: float, elevation: float) -> void:
	sun_azimuth = wrapf(azimuth, 0.0, 360.0)
	sun_elevation = clampf(elevation, -90.0, 90.0)	# полные 180°
	_orient(sun_light, direction_from_angles(sun_azimuth, sun_elevation))
	_publish_atmosphere()


## MoonLight — временная заглушка (см. шапку): в новый контракт освещения
## НЕ публикуется (состояние атмосферы читает только Sun).
func set_moon_angles(azimuth: float, elevation: float) -> void:
	moon_azimuth = wrapf(azimuth, 0.0, 360.0)
	moon_elevation = clampf(elevation, -90.0, 90.0)
	_orient(moon_light, direction_from_angles(moon_azimuth, moon_elevation))


func set_sun_enabled(enabled: bool) -> void:
	if sun_light != null:
		sun_light.visible = enabled


func set_moon_enabled(enabled: bool) -> void:
	if moon_light != null:
		moon_light.visible = enabled


## 4.1.1: apply_light(profile) УДАЛЁН вместе с SkyLightProfile и полем
## light пресета (граница удаления, добро заказчика 30.10 п.4).


# --- живые ручки панели, вкладка «Свет сцены» (приказ 31.10 п.3: вкладка
# --- СОХРАНЕНА; пишет напрямую в узлы, с пресетами не связана). Изменение
# --- параметров Sun событийно публикуется в новый контракт освещения. ---

func set_key_light_color(color: Color) -> void:
	if sun_light != null:
		sun_light.light_color = color
	_publish_atmosphere()


func set_key_light_energy(value: float) -> void:
	if sun_light != null:
		sun_light.light_energy = value
	_publish_atmosphere()


func set_moon_light_color(color: Color) -> void:
	if moon_light != null:
		moon_light.light_color = color


func set_moon_light_energy(value: float) -> void:
	if moon_light != null:
		moon_light.light_energy = value


func set_ambient_energy(value: float) -> void:
	if environment != null:
		environment.ambient_light_energy = value


## 4.1.1 (этап 02 плана света): событийная публикация состояния освещения.
## Вызывается ТОЛЬКО из mutator'ов Sun (углы/цвет/энергия) — единственный
## владелец изменения Sun публикует состояние (план §4.3). atmosphere == null
## (компонент не собран в сцене) — тихо пропускаем: свет живёт по-старому.
func _publish_atmosphere() -> void:
	if atmosphere != null:
		atmosphere.publish()


# --- чтение для синхронизации живых ручек вкладки «Свет сцены» (4.1.1: пресет
# --- свет НЕ несёт и НЕ сохраняет — панель читает узлы только для отображения) ---

func get_key_light_color() -> Color:
	return sun_light.light_color if sun_light != null else Color.WHITE


func get_key_light_energy() -> float:
	return sun_light.light_energy if sun_light != null else 0.0


func get_moon_light_color() -> Color:
	return moon_light.light_color if moon_light != null else Color.WHITE


func get_moon_light_energy() -> float:
	return moon_light.light_energy if moon_light != null else 0.0


func get_ambient_energy() -> float:
	return environment.ambient_light_energy if environment != null else 1.0


func _orient(light: DirectionalLight3D, direction: Vector3) -> void:
	if light == null:
		return
	# ЗНАК ОРИЕНТАЦИИ (п. 12.3 ТЗ, шаг D2). Direction указывает от наблюдателя
	# НА источник. Basis.looking_at(target) направляет -Z базиса на target;
	# DirectionalLight3D излучает вдоль -Z. target = -direction → -Z смотрит ОТ
	# источника (лучи идут в сцену), basis.z == direction — конвенция sk_sun_dir
	# проекта B и критерий приёмки 18.5 (basis.z совпадает с _direction до 1e-5).
	# Статический анализ показал: минус в формуле A ВЕРЕН ( «правка» из ТЗ 12.3
	# развернула бы свет на 180° — тени падали бы от противоположной стороны).
	# По мере риска таблицы 20 «если совпадает — строку не трогаем» формула A
	# сохранена; прогон headless-теста: q_tools/test_sky_controllers.gd.
	var ray_direction: Vector3 = -direction.normalized()
	var up: Vector3 = Vector3.UP
	# защита от полюса (диапазон высот до ±90°): при |dot| > 0.98 базис вырождается
	if absf(ray_direction.dot(up)) > 0.98:
		up = Vector3.FORWARD
	light.global_basis = Basis.looking_at(ray_direction, up)
