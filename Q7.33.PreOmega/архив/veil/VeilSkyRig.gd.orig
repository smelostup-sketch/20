extends Node
## VeilSkyRig — минимальная обвязка неба Q7.32.PreOmega.SL (шаг 1, 2026-10-25).
##
## Заменяет упакованные CloudsTestBench.gd/SkyLabPanel.gd (_PACKED/Q7.32.PreOmega.BENCH/)
## в объёме, нужном для визуальной проверки состава «вуаль + градиент неба + свет»:
##   1. ОДИН РАЗ при старте собирает 3D-шумы из сырых .bin и пишет их в sky-материал
##      (через CloudTextureLoader.gd — персистенция ImageTexture3D через ResourceSaver
##      в Godot 4.7 сломана, спайк B1; стенд делал так же);
##   2. каждый кадр синхронизирует cloud_light_direction из DirectionalLight3D
##      (конвенция бенча sync_sun_from_light: basis.z = НА источник, свет светит
##      вдоль -Z; epsilon-гейт 0.0005). sk_sun_dir (НАСТОЯЩЕЕ солнце для градиента и
##      небесных тел) пишет панель VeilSkyPanel — ночью свет смотрит С ЛУНЫ, поэтому
##      синк sk_sun_dir из света сломал бы купол (фикс 27.10.26);
##   3. опциональный CPU-дрейф поля вуали: hc_offset = база + накопленный дрейф ×
##      hc_wind_factor (конвенция бенча; TIME в шейдере не используется, накопление
##      на CPU без дрейфа точности).
## Ожидаемые соседи по сцене (пути — экспорты): ../WorldEnvironment, ../DirectionalLight3D.

@export var env_path: NodePath = ^"../WorldEnvironment"
@export var sun_light_path: NodePath = ^"../DirectionalLight3D"
@export var sync_sun_from_light := true		# писать cloud_light_direction/sk_sun_dir из света
@export var wind_direction := Vector3(1.0, 0.0, 0.3)	# направление дрейфа поля (нормализуется)
@export var wind_speed := 0.0				# м/с; 0 = статичное поле (детерминированный кадр)
@export var hc_wind_factor := 0.6			# доля того же ветра для вуали (конвенция бенча)

const PW_PATH := "res://Assets/sky/noise_pw_128.bin"
const WO_PATH := "res://Assets/sky/noise_worley_32.bin"
const PW_SIZE := 128
const WO_SIZE := 32
const LOADER_PATH := "res://Assets/sky/CloudTextureLoader.gd"

var _mat: ShaderMaterial = null
var _light: DirectionalLight3D = null
var _hc_base_offset := Vector3.ZERO
var _drift := Vector3.ZERO


func _ready() -> void:
	var we := get_node_or_null(env_path) as WorldEnvironment
	if we != null and we.environment != null and we.environment.sky != null:
		_mat = we.environment.sky.sky_material as ShaderMaterial
	if _mat == null:
		push_error("[VeilSkyRig] sky-материал (ShaderMaterial) не найден по пути %s" % str(env_path))
	_light = get_node_or_null(sun_light_path) as DirectionalLight3D
	if sync_sun_from_light and _light == null:
		push_warning("[VeilSkyRig] DirectionalLight3D не найден — направление солнца остаётся из материала")
	if _mat == null:
		return
	# Шумы: .bin → ImageTexture3D один раз (тот же путь, что стенд; loader — статические функции)
	var loader = load(LOADER_PATH)
	var t0 := Time.get_ticks_msec()
	var pw_tex: ImageTexture3D = loader.load_texture(PW_PATH, PW_SIZE)
	var wo_tex: ImageTexture3D = loader.load_texture(WO_PATH, WO_SIZE)
	if pw_tex == null:
		pw_tex = loader.placeholder_texture()	# сцена остаётся видимой (push_error был в лоадере)
	if wo_tex == null:
		wo_tex = loader.placeholder_texture()
	_mat.set_shader_parameter("noise_pw", pw_tex)
	_mat.set_shader_parameter("noise_worley", wo_tex)
	_hc_base_offset = _param_vec3("hc_offset", Vector3.ZERO)
	print("[VeilSkyRig] шум pw=%d³ wo=%d³ собран за %d мс | источник света: %s | ветер: %.0f м/с" % [
		PW_SIZE, WO_SIZE, Time.get_ticks_msec() - t0,
		"синк из DirectionalLight3D" if (sync_sun_from_light and _light != null) else "из материала",
		wind_speed])


func _process(delta: float) -> void:
	if _mat == null:
		return
	# CPU-дрейф поля вуали от ветра (как бенч: накопление на CPU, TIME в шейдере нет)
	if wind_speed != 0.0:
		_drift += wind_direction.normalized() * wind_speed * delta
		_mat.set_shader_parameter("hc_offset", _hc_base_offset + _drift * hc_wind_factor)
	# B3: синк направления ИСТОЧНИКА СВЕТА с DirectionalLight3D (basis.z = НА источник).
	# ФИКС 27.10.26 («вместо луны соляр на антисоляре»): sk_sun_dir из света НЕ пишем —
	# ночью игровой ключ светит с лунного (антисолярного) направления, и синк уводил
	# НАСТОЯЩЕЕ солнце на место луны: купол разворачивался не туда, диск солнца вставал
	# на антисоляр, луна гасла. sk_sun_dir владеет панель (_set_sun, настоящее солнце);
	# cloud_light_direction = куда смотрит свет (днём солнце, ночью луна) — для вуали.
	if sync_sun_from_light and _light != null:
		var to_sun := _light.global_transform.basis.z.normalized()
		_write_dir("cloud_light_direction", to_sun)


## Запись направления с epsilon-гейтом (конвенция бенча/TimeOfDayController:
## одинаковое значение повторно не пишем — radiance не дёргается).
func _write_dir(param_name: String, to_sun: Vector3) -> void:
	var old: Variant = _mat.get_shader_parameter(param_name)
	if old == null or (to_sun - _to_vec3(old)).length() > 0.0005:
		_mat.set_shader_parameter(param_name, to_sun)


## База дрейфа вуали (пишет панель VeilSkyPanel, слайдеры «Сдвиг поля X/Y/Z»):
## новое базовое смещение + немедленная запись с учётом накопленного дрейфа
## (конвенция бенча: hc_offset = база + дрейф × hc_wind_factor).
func set_hc_base_offset(v: Vector3) -> void:
	_hc_base_offset = v
	if _mat != null:
		_mat.set_shader_parameter("hc_offset", _hc_base_offset + _drift * hc_wind_factor)


func get_hc_base_offset() -> Vector3:
	return _hc_base_offset


## source_color-uniform'ы приходят Color, простые vec3 — Vector3 (баг-конвенция B3-C2 бенча).
func _param_vec3(param_name: String, fallback: Vector3) -> Vector3:
	var v: Variant = _mat.get_shader_parameter(param_name)
	if v == null:
		return fallback
	return _to_vec3(v)


func _to_vec3(v: Variant) -> Vector3:
	if v is Color:
		var c: Color = v
		return Vector3(c.r, c.g, c.b)
	return Vector3(v.x, v.y, v.z)
