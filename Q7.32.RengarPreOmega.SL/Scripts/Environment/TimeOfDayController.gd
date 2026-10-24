extends Node
class_name TimeOfDayController
## Контроллер времени суток омега-неба (Q7.29). НЕЗАВИСИМ от геймплея: ни одной
## ссылки на боевые/движенческие компоненты; живёт в сцене рядом с WorldEnvironment.
##
## Фазы (без ДНЯ, промт §7): SUNSET → TWILIGHT → NIGHT. Два режима хода:
##   - автопрогресс: фаза живёт dwell-время (sunset_duration/twilight_duration/
##     night_duration; 0 = бесконечно), затем плавный переход в следующую;
##     loop_enabled замыкает ночь на закат;
##   - внешний: transition_to()/set_phase_instant() от любой системы.
##
## Переходы: ОДИН активный переход, стартует ОТ ТЕКУЩИХ значений (снепшот
## current), easing smoothstep; повторный transition_to перезапускает от
## текущего состояния — гонок твинов нет (промт §7). Длительность 0 = мгновенно.
##
## Движение облаков: контроллер накапливает смещения НА CPU (float GDScript =
## double — без дрейфа точности за длинные сессии) по delta → независимо от
## частоты кадров; в шейдер уходят cloud_offset_large/detail (промт §5).
##
## Radiance: Sky.process_mode = INCREMENTAL ставится на ресурсе неба (обновление
## cubemap-освещения растянуто по кадрам — дёшево для медленных изменений;
## REALTIME не форсируем, промт §5). Ограничение: отражения/ambient от неба
## отстают от видимого неба на время инкрементального обновления — для минутных
## переходов незаметно (документировано в отчёте).
enum Phase { SUNSET, TWILIGHT, NIGHT }

signal phase_changed(phase: int)
signal transition_started(from_phase: int, to_phase: int)

@export var sky: Sky
## Ссылка на свет — NodePath-экспорт (проектный паттерн: рукописный tscn не
## резолвит node-typed экспорты; BushGrassComponent.player_path — тот же подход).
@export var light_path: NodePath
@export var environment: Environment
@export var profile_sunset: SkyPhaseProfile
@export var profile_twilight: SkyPhaseProfile
@export var profile_night: SkyPhaseProfile
@export var quality: SkyQualityProfile
## Dwell-времена фаз (сек): 0 = фаза не кончается сама (ночь по умолчанию).
@export_range(0.0, 3600.0, 1.0) var sunset_duration := 300.0
@export_range(0.0, 3600.0, 1.0) var twilight_duration := 180.0
@export_range(0.0, 3600.0, 1.0) var night_duration := 0.0
## Длительность_crossfade между фазами (сек); 0 = мгновенное переключение.
@export_range(0.0, 600.0, 0.5) var transition_duration := 20.0
@export var loop_enabled := false
@export var auto_progress := true

var current: SkyPhaseProfile = null
var _from: SkyPhaseProfile = null
var _phase: int = Phase.SUNSET
var _target_phase: int = Phase.SUNSET
var _transitioning := false
var _t := 0.0
var _dur := 0.0
var _dwell := 0.0
var _offset_large := Vector2.ZERO
var _offset_detail := Vector2.ZERO
var _wind_mul := 1.0
var _mat: ShaderMaterial = null
var _ready_ok := false


var light: DirectionalLight3D = null


func _ready() -> void:
	if light_path != NodePath():
		light = get_node_or_null(light_path) as DirectionalLight3D
	_ready_ok = _validate_refs()
	if not _ready_ok:
		return
	_mat = sky.sky_material as ShaderMaterial
	current = profile_sunset.duplicate() as SkyPhaseProfile
	_from = profile_sunset.duplicate() as SkyPhaseProfile
	_apply()


## Безопасная инициализация: отсутствующие ссылки = предупреждение и no-op,
## без падений (промт §7 «safe initialization and recovery»).
func _validate_refs() -> bool:
	var ok := true
	if sky == null or not (sky.sky_material is ShaderMaterial):
		push_warning("TimeOfDayController: sky/материал не назначены — контроллер отключён")
		ok = false
	if profile_sunset == null or profile_twilight == null or profile_night == null:
		push_warning("TimeOfDayController: не все профили фаз назначены — контроллер отключён")
		ok = false
	if light == null:
		push_warning("TimeOfDayController: DirectionalLight3D не назначен — свет не синхронизируется")
	if environment == null:
		push_warning("TimeOfDayController: Environment не назначен — ambient не синхронизируется")
	if quality == null:
		push_warning("TimeOfDayController: SkyQualityProfile не назначен — качество по умолчанию 1.0")
	return ok


# === ПУБЛИЧНЫЙ API ===
func get_phase() -> int:
	return _phase


func is_transitioning() -> bool:
	return _transitioning


## Целевая фаза активного перехода (для отладочной панели и стендов Q7.30).
func get_target_phase() -> int:
	return _target_phase


## Текущий множитель ветра (панель читает и пишет через debug_set_wind_multiplier).
func get_wind_multiplier() -> float:
	return _wind_mul


## Мгновенная установка фазы (без crossfade).
func set_phase_instant(p: int) -> void:
	if not _ready_ok:
		return
	_phase = p
	_target_phase = p
	_transitioning = false
	_dwell = 0.0
	current.copy_from(_profile_of(p))
	_apply()
	phase_changed.emit(_phase)


## Плавный переход; duration_override < 0 = использовать transition_duration.
## Перезапуск во время перехода стартует от ТЕКУЩИХ значений (снепшот current).
func transition_to(p: int, duration_override := -1.0) -> void:
	if not _ready_ok:
		return
	var d := transition_duration if duration_override < 0.0 else duration_override
	if d <= 0.0:
		set_phase_instant(p)
		return
	_from = current.duplicate() as SkyPhaseProfile
	_target_phase = p
	_dur = d
	_t = 0.0
	_transitioning = true
	transition_started.emit(_phase, p)


func start_auto() -> void:
	auto_progress = true


func stop_auto() -> void:
	auto_progress = false


# === ОТЛАДКА (использует тест-сцена Сцена_неба; в геймплее не вызывается) ===
func debug_set_coverage(v: float) -> void:
	if _ready_ok:
		current.cloud_coverage = clampf(v, 0.0, 0.95)
		_apply()


func debug_set_wind_multiplier(v: float) -> void:
	_wind_mul = clampf(v, 0.0, 10.0)


# === ВНУТРЕННЕЕ ===
func _profile_of(p: int) -> SkyPhaseProfile:
	match p:
		Phase.SUNSET:
			return profile_sunset
		Phase.TWILIGHT:
			return profile_twilight
		_:
			return profile_night


func _dwell_of(p: int) -> float:
	match p:
		Phase.SUNSET:
			return sunset_duration
		Phase.TWILIGHT:
			return twilight_duration
		_:
			return night_duration


func _next_phase(p: int) -> int:
	match p:
		Phase.SUNSET:
			return Phase.TWILIGHT
		Phase.TWILIGHT:
			return Phase.NIGHT
		_:
			return Phase.SUNSET if loop_enabled else -1


func _process(delta: float) -> void:
	if not _ready_ok:
		return
	# Смещения облаков: CPU-накопление по delta (независимо от fps, без дрейфа).
	var wl := current.wind_large_dir
	if wl.length() > 0.001:
		_offset_large += wl.normalized() * current.wind_large_speed * _wind_mul * delta
	var wd := current.wind_detail_dir
	if wd.length() > 0.001:
		_offset_detail += wd.normalized() * current.wind_detail_speed * _wind_mul * delta
	if _transitioning:
		_t += delta
		var k := clampf(_t / maxf(_dur, 0.0001), 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)  # smoothstep-easing перехода
		current.interpolate(_from, _profile_of(_target_phase), e)
		if k >= 1.0:
			# Коммит: точный снап в целевой профиль (lerp(…,1.0) даёт float-шум;
			# снап исключает накопление микросмещений в цепочке переходов).
			current.copy_from(_profile_of(_target_phase))
			_transitioning = false
			_phase = _target_phase
			_dwell = 0.0
			phase_changed.emit(_phase)
	elif auto_progress:
		_dwell += delta
		var d := _dwell_of(_phase)
		if d > 0.0 and _dwell >= d:
			var nxt := _next_phase(_phase)
			if nxt >= 0:
				transition_to(nxt)
	_apply()


## Запись текущего состояния в материал/свет/среду с epsilon-гейтом:
## неизменившиеся значения не перезаписываются (промт §7).
func _apply() -> void:
	_setf("sunset_amount", current.sunset_amount)
	_setf("night_amount", current.night_amount)
	_setf("horizon_haze_strength", current.horizon_haze_strength)
	_setc("horizon_haze_color", current.horizon_haze_color)
	_setf("cloud_coverage", current.cloud_coverage)
	_setf("cloud_density", current.cloud_density)
	_setf("cloud_opacity", current.cloud_opacity)
	_setf("cloud_large_scale", current.cloud_large_scale)
	_setf("cloud_detail_scale", current.cloud_detail_scale)
	_setf("cloud_detail_strength", current.cloud_detail_strength)
	_setv2("cloud_offset_large", _offset_large)
	_setv2("cloud_offset_detail", _offset_detail)
	_setv3("cloud_light_direction", current.cloud_light_direction)
	_setc("cloud_light_color", current.cloud_light_color)
	_setc("cloud_dark_color", current.cloud_dark_color)
	_setf("cloud_light_strength", current.cloud_light_strength)
	_setv3("moon_direction", current.moon_direction)
	_setf("moon_size", current.moon_size)
	_setf("moon_intensity", current.moon_intensity)
	_setf("moon_halo_strength", current.moon_halo_strength)
	_setc("moon_color", current.moon_color)
	_setf("star_intensity", current.star_intensity)
	_setf("star_visibility", current.star_visibility)
	_setf("quality_detail", quality.quality_detail if quality != null else 1.0)
	if light != null:
		light.light_color = current.light_color
		light.light_energy = current.light_energy
		light.rotation_degrees = current.light_euler_deg
	if environment != null:
		environment.ambient_light_energy = current.ambient_energy


func _setf(uniform_name: String, value: float) -> void:
	var old: Variant = _mat.get_shader_parameter(uniform_name)
	if old == null or absf(float(old) - value) > 0.0005:
		_mat.set_shader_parameter(uniform_name, value)


func _setc(uniform_name: String, value: Color) -> void:
	var old: Variant = _mat.get_shader_parameter(uniform_name)
	if old == null or Color(old) != value:
		_mat.set_shader_parameter(uniform_name, value)


func _setv2(uniform_name: String, value: Vector2) -> void:
	_mat.set_shader_parameter(uniform_name, value)


func _setv3(uniform_name: String, value: Vector3) -> void:
	var old: Variant = _mat.get_shader_parameter(uniform_name)
	if old == null or (old as Vector3).distance_to(value) > 0.0005:
		_mat.set_shader_parameter(uniform_name, value)
