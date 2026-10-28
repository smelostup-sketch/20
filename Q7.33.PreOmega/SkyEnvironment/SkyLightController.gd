extends Node
class_name SkyLightController
## Q7.33 — ЕДИНСТВЕННЫЙ писатель света сцены (п. 9/12.1 ТЗ):
## DirectionalLight3D (SunLight, MoonLight) и WorldEnvironment.environment.
## Параметров шейдера не касается вообще (адрес записи «материал» принадлежит
## SkyEnvironmentController). Знает узлы сцены, углы и SkyLightProfile.

@export var sun_light: DirectionalLight3D
@export var moon_light: DirectionalLight3D
@export var environment: Environment

var sun_azimuth: float = 180.0
var sun_elevation: float = 0.5
var moon_azimuth: float = 0.0
var moon_elevation: float = 50.0


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


func apply_light(profile: SkyLightProfile) -> void:
	if profile == null:
		return
	set_key_light_color(profile.key_color)
	set_key_light_energy(profile.key_energy)
	set_moon_light_color(profile.moon_light_color)
	set_moon_light_energy(profile.moon_light_energy)
	set_ambient_energy(profile.ambient_energy)


# --- ручки панели, вкладка «Свет сцены» (п. 13.1) ---

func set_key_light_color(color: Color) -> void:
	if sun_light != null:
		sun_light.light_color = color


func set_key_light_energy(value: float) -> void:
	if sun_light != null:
		sun_light.light_energy = value


func set_moon_light_color(color: Color) -> void:
	if moon_light != null:
		moon_light.light_color = color


func set_moon_light_energy(value: float) -> void:
	if moon_light != null:
		moon_light.light_energy = value


func set_ambient_energy(value: float) -> void:
	if environment != null:
		environment.ambient_light_energy = value


# --- чтение для сборки пресета из текущего состояния (панель, шаг F.6):
# --- панель читает свет только через контроллер, напрямую к узлам не лезет ---

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
