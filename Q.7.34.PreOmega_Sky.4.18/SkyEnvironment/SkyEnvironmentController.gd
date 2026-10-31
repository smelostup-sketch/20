extends Node
class_name SkyEnvironmentController
## Q7.33 — ЕДИНСТВЕННЫЙ писатель ShaderMaterial неба (п. 9/12.2 ТЗ).
## Знает: материал, углы, пресет. НЕ знает NodePath на свет — сцена и свет
## делегируются в SkyLightController (экспорт light_controller).

@export var sky_material: ShaderMaterial
@export var light_controller: SkyLightController
## Этап 03 (план света §3/§5): компонент нового контракта освещения.
## Этот контроллер — единственный писатель градиента (apply_palette), поэтому
## он же поставляет компоненту живую палитру света пресета (col_light3/2/1 —
## строка «Окружение» palletes.html: единые данные для среды и зон вуали).
## null = сцена без нового света (apply_palette просто не публикует среду).
@export var atmosphere: AtmosphereLightingComponent
## 4.1.7 (инструкция заказчика): владелец долей цветов градиента —
## SkyGradientWeightsComponent (единственный писатель sky_color_weights).
## Контроллер ПОСТАВЛЯЕТ ему доли из данных пресета (q1..q4 → четыре доли);
## null = сцена без компонента (доли остаются данными материала).
@export var gradient_weights: SkyGradientWeightsComponent
## Пресет старта сцены (применяется в _ready; дефолт сборки — Preset_09 = K4).
@export var initial_preset: SkyPreset

## 4.1.1: export'ы sun_energy/moon_energy УДАЛЕНЫ — цвет/энергия SunLight живут
## ДАННЫМИ на самом узле DirectionalLight3D (единственный источник, план §4.3:
## AtmosphereLightingComponent читает узел). Дублирующий fallback в _ready,
## переписывающий энергию узла из контроллера, убран вместе с ними.

var sun_azimuth: float = 180.0
var sun_elevation: float = 0.5
var moon_azimuth: float = 0.0
var moon_elevation: float = 50.0

var sun_enabled: bool = true
var moon_enabled: bool = true

# --- Q7.34 (S7): radiance на драге ---
# Radiance cubemap (process_mode = INCREMENTAL в сцене) добирается кадрами: на время
# правок ручек переключаем на REALTIME, после QUIET_FRAMES кадров покоя возвращаем
# INCREMENTAL — отражения/ambient не «догоняют» ползунки.
# Q7.34.PreOmega_Sky3.2.2: покадровая запись sk_streak_right удалена вместе с
# uniform'ом (вариант Б-мир) — больше ничто не инвалидирует кубмап каждый кадр.
var _dirty_frames: int = 1000000
var _sky: Sky = null

const QUIET_FRAMES := 30

# --- ВУАЛЬ (Sky3.2.7, S10): 3D-шумы компонента SkyVeil.gdshaderinc ---
# Персистенция ImageTexture3D через ResourceSaver в Godot 4.7 сломана (спайк B1,
# см. шапку CloudTextureLoader.gd) → текстуры поставляются сырыми .bin (R8-вокселы)
# и собираются ОДИН РАЗ здесь, в _ready(). Milliseconds один раз, не каждый кадр.
const VEIL_NOISE_PW := "res://SkyEnvironment/noise_pw_128.bin"
const VEIL_NOISE_WORLEY := "res://SkyEnvironment/noise_worley_32.bin"
const VeilTextureLoader := preload("res://SkyEnvironment/CloudTextureLoader.gd")


func _ready() -> void:
	_load_veil_noise()
	if initial_preset != null:
		apply_preset(initial_preset)
		apply_veil(initial_preset)	# Sky3.2.14: вуаль стартового пресета — один раз при старте
	else:
		_apply_all()
	_sky = _find_sky()


## S10: шумы вуали — один раз при старте. При отсутствии .bin загрузчик сам
## даёт push_error и подставляет заглушку 8³ (сцена остаётся работоспособной);
## на кадр с гейтом hc_enabled = false текстуры не влияют (выборок нет).
func _load_veil_noise() -> void:
	if sky_material == null:
		return
	var pw: ImageTexture3D = VeilTextureLoader.load_texture(VEIL_NOISE_PW, 128)
	var worley: ImageTexture3D = VeilTextureLoader.load_texture(VEIL_NOISE_WORLEY, 32)
	sky_material.set_shader_parameter("noise_pw", pw if pw != null else VeilTextureLoader.placeholder_texture())
	sky_material.set_shader_parameter("noise_worley", worley if worley != null else VeilTextureLoader.placeholder_texture())


## Q7.34 (S7): Sky берём из WorldEnvironment сцены (экспорт не плодим: сцена одна).
func _find_sky() -> Sky:
	var root := get_tree().current_scene
	if root == null:
		return null
	for node in root.find_children("", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		if env != null and env.sky != null:
			return env.sky
	return null


## Q7.34.PreOmega_Sky3.2.2: экранный базис стрика (_update_streak_basis) удалён —
## базис теперь МИРОВОЙ и считается в шейдере (вариант Б-мир), камера не участвует.

## Q7.34 (S7): на время правок — radiance REALTIME (без задержки доборки), после
## QUIET_FRAMES кадров покоя — штатный INCREMENTAL (цена кадра как в сцене).
func _tick_sky_mode() -> void:
	if _sky == null:
		return
	if _dirty_frames < QUIET_FRAMES:
		_dirty_frames += 1
		if _sky.process_mode != Sky.PROCESS_MODE_REALTIME:
			_sky.process_mode = Sky.PROCESS_MODE_REALTIME
	elif _sky.process_mode != Sky.PROCESS_MODE_INCREMENTAL:
		_sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL


func _mark_dirty() -> void:
	_dirty_frames = 0


func _process(_delta: float) -> void:
	if sky_material == null:
		return
	_tick_sky_mode()


## ОДИН _direction(azimuth, elevation) на шейдер и на свет (п. 12.2):
## тело функции — в SkyLightController.direction_from_angles (static),
## разъезд «солнце на небе» / «откуда тени» исключён.
func _direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
	return SkyLightController.direction_from_angles(azimuth_deg, elevation_deg)


func _apply_all() -> void:
	if sky_material == null:
		push_warning("SkyEnvironmentController: sky_material is not assigned.")
		return
	_mark_dirty()

	var sun_dir: Vector3 = _direction(sun_azimuth, sun_elevation)
	var moon_dir: Vector3 = _direction(moon_azimuth, moon_elevation)

	# имена uniform'ов — B (sk_sun_dir/sk_moon_dir), шаг D.3
	sky_material.set_shader_parameter("sk_sun_dir", sun_dir)
	sky_material.set_shader_parameter("sk_moon_dir", moon_dir)
	sky_material.set_shader_parameter("sun_enabled", sun_enabled)
	sky_material.set_shader_parameter("moon_enabled", moon_enabled)

	if light_controller != null:
		light_controller.set_sun_angles(sun_azimuth, sun_elevation)
		light_controller.set_moon_angles(moon_azimuth, moon_elevation)
		light_controller.set_sun_enabled(sun_enabled)
		light_controller.set_moon_enabled(moon_enabled)


func set_sun_angles(azimuth: float, elevation: float) -> void:
	sun_azimuth = wrapf(azimuth, 0.0, 360.0)
	sun_elevation = clampf(elevation, -90.0, 90.0)	# полные 180°, клампов B нет
	_apply_all()


func set_moon_angles(azimuth: float, elevation: float) -> void:
	moon_azimuth = wrapf(azimuth, 0.0, 360.0)
	moon_elevation = clampf(elevation, -90.0, 90.0)
	_apply_all()


func set_sun_enabled(enabled: bool) -> void:
	sun_enabled = enabled
	_apply_all()


func set_moon_enabled(enabled: bool) -> void:
	moon_enabled = enabled
	_apply_all()


## Рампа и купол: четыре стопа (Sky3.2.4, palletes.html) + форма (данные
## пресета → материал). Порядок записи sk_c1…sk_c4 = шаги HTML.
## 4.1.6: цвет ореола из пресета УДАЛЁН — выводится шейдером из стопа sk_c4
## (правило S3 × sk_halo_hdr_gain), независимых данных цвета ореола нет.
## 4.1.7: доли цветов — данные владельца SkyGradientWeightsComponent
## (q1..q4 пресета → четыре доли → sky_color_weights); uniform'ы sk_q*/sk_sharp
## удалены вместе со старой моделью окон.
func apply_palette(preset: SkyPreset) -> void:
	if preset == null or sky_material == null:
		return
	_mark_dirty()
	sky_material.set_shader_parameter("sk_c1", preset.col_sky1)
	sky_material.set_shader_parameter("sk_c2", preset.col_sky2)
	sky_material.set_shader_parameter("sk_c3", preset.col_sky3)
	sky_material.set_shader_parameter("sk_c4", preset.col_sky4)
	# 4.1.7 (инструкция заказчика): доли четырёх цветов — из кумулятивных границ
	# q1..q4 пресета (w1=q1, w2=q2−q1, w3=q3−q2, w4=q4−q3, сумма = q4; шейдер
	# нормирует). Писатель sky_color_weights ОДИН — компонент-владелец.
	if gradient_weights != null:
		gradient_weights.set_weights(Vector4(preset.q1, preset.q2 - preset.q1,
			preset.q3 - preset.q2, preset.q4 - preset.q3) * 100.0)
	sky_material.set_shader_parameter("sk_arc_stretch", preset.arc_stretch)
	sky_material.set_shader_parameter("sk_breathe", preset.breathe)	# COLORS6: «дыхание» купола
	sky_material.set_shader_parameter("sk_squeeze", preset.squeeze)	# COLORS7: компенсация складки
	sky_material.set_shader_parameter("sk_dither", 1.0 if preset.dither else 0.0)
	sky_material.set_shader_parameter("star_intensity", preset.star_intensity)
	# Q7.34 (COLORS5): режим тонмапа — материал и Environment переключаются вместе
	sky_material.set_shader_parameter("sk_tonemap", 1 if preset.tonemap_linear else 0)
	if light_controller != null:
		light_controller.set_tonemap_linear(preset.tonemap_linear)
	# Этап 03 (план света §3, v2 §2.1/§3.2): Sky Gradient — источник окружающей
	# цветовой среды. Цвета «Окружения» пресета (palletes.html: L3 «даль» =
	# зенит, L1 «у солнца/горизонта» = горизонт) И угловая палитра вуали
	# (anti-solar = L3, transition = L2, solar = L1 — старая рампа была ровно
	# этими данными, 4.1.6) публикуются в новом контракте — ЕДИНАЯ палитра для
	# всех потребителей, без второй независимой копии (план §7.2, v2 §5.2) и без
	# чтения отрисованного Sky (§7.4).
	if atmosphere != null:
		atmosphere.set_environment_palette(preset.col_light3, preset.col_light2, preset.col_light1)


## Солнце и луна: диск, ореолы, стрик, кратеры (данные пресета → материал).
func apply_sources(preset: SkyPreset) -> void:
	if preset == null or sky_material == null:
		return
	_mark_dirty()
	sky_material.set_shader_parameter("sun_disk_color", preset.sun_disc_color)
	sky_material.set_shader_parameter("sun_size_deg", preset.sun_size_deg)
	sky_material.set_shader_parameter("sun_core_int", preset.sun_core_int)
	sky_material.set_shader_parameter("sk_glow_int", preset.glow_int)
	sky_material.set_shader_parameter("sk_glow_exp", preset.glow_exp)
	sky_material.set_shader_parameter("sun_g1_int", preset.g1_int)
	sky_material.set_shader_parameter("sun_g2_int", preset.g2_int)
	sky_material.set_shader_parameter("streak_int", preset.streak_int)
	sky_material.set_shader_parameter("sk_streak_gate_lo", preset.streak_gate_lo)
	sky_material.set_shader_parameter("sk_streak_gate_hi", preset.streak_gate_hi)
	# Q7.34.PreOmega_Sky3.2.2 (Б-мир): полууглы бокса стрика — данные пресета
	sky_material.set_shader_parameter("sk_streak_half_w_deg", preset.streak_half_w_deg)
	sky_material.set_shader_parameter("sk_streak_half_h_deg", preset.streak_half_h_deg)
	sky_material.set_shader_parameter("moon_color", preset.moon_color)
	sky_material.set_shader_parameter("moon_size", preset.moon_size)
	sky_material.set_shader_parameter("moon_detail_int", preset.moon_detail_int)
	sky_material.set_shader_parameter("moon_glow_int", preset.moon_glow_int)
	sky_material.set_shader_parameter("moon_glow_exp", preset.moon_glow_exp)


## Вуаль (Sky3.2.8, S11): данные профиля → материал, ТРЕТИЙ блок рядом с
## apply_palette/apply_sources (писатель материала один, п. 9).
## preset.veil == null → пишем ТОЛЬКО гейт off: остальные hc_* не трогаем, кадр
## побитово прежний (приёмка «выключение — побитово назад»).
## Освещение вуали контроллером НЕ пишется (4.1.3, этап 04): контракт хоста
## cloud_light_* удалён; uniform'ы освещения модуля (hc_sun_*, hc_ambient_*,
## hc_palette_*) событийно пишет CirrusVeilBinding из AtmosphereLightingState
## (единственный писатель параметров освещения). Панель «Вуаль» правит
## художественные hc_*-коэффициенты (гейт/альбедо/gain/самозатенение).
func apply_veil(preset: SkyPreset) -> void:
	if preset == null or sky_material == null:
		return
	_mark_dirty()
	var v: SkyVeilProfile = preset.veil
	if v == null:
		sky_material.set_shader_parameter("hc_enabled", false)
		return
	sky_material.set_shader_parameter("hc_enabled", v.veil_enabled)
	sky_material.set_shader_parameter("DS_hc_alpha_scale", v.veil_amount)
	sky_material.set_shader_parameter("hc_color", v.veil_color)
	sky_material.set_shader_parameter("hc_light_gain", v.veil_light_gain)
	sky_material.set_shader_parameter("hc_ambient_gain", v.veil_ambient_gain)
	sky_material.set_shader_parameter("hc_coverage", v.veil_coverage)
	sky_material.set_shader_parameter("hc_tau_per_km", v.veil_tau_per_km)
	sky_material.set_shader_parameter("hc_use_shadowing", v.veil_use_shadowing)
	# 4.1.3 (этап 04): освещение вуали вне apply_veil — контракт модуля
	# hc_sun_*/hc_ambient_*/hc_palette_* пишет CirrusVeilBinding из состояния
	# освещения (событийно). apply_veil — только данные профиля вуали (8 uniform'ов).


## Пресет целиком: палитра + источники + вуаль (4.1.1: свет сцены из пресета
## УДАЛЁН — apply_light(preset.light) убран вместе с полем light; цвет/энергия
## SunLight — данные узла, состояние освещения публикует SkyLightController).
func apply_preset(preset: SkyPreset) -> void:
	if preset == null:
		return
	sun_azimuth = wrapf(preset.sun_azimuth, 0.0, 360.0)
	sun_elevation = clampf(preset.sun_elevation, -90.0, 90.0)
	moon_azimuth = wrapf(preset.moon_azimuth, 0.0, 360.0)
	moon_elevation = clampf(preset.moon_elevation, -90.0, 90.0)
	sun_enabled = preset.sun_enabled
	moon_enabled = preset.moon_enabled
	apply_palette(preset)
	apply_sources(preset)
	# Sky3.2.14 (задача 3 заказчика): выбор пресета НЕ сбрасывает живые настройки
	# вуали — apply_veil здесь удалён. Состояние вуали при старте сцены применяет
	# _ready() один раз; сброс — одна кнопка «Сброс вуали» в панели.
	_apply_all()


# --- единственный вход панели для живых ручек (п. 9: панель пишет только
# --- через методы контроллеров; писатель материала при этом остаётся один) ---

func set_shader_param(param: StringName, value: Variant) -> void:
	if sky_material != null:
		sky_material.set_shader_parameter(param, value)
		_mark_dirty()


func get_shader_param(param: StringName) -> Variant:
	if sky_material == null:
		return null
	return sky_material.get_shader_parameter(param)
