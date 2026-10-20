extends Node
## CloudsTestBench — диагностический стенд компонента Q7.32_SKY_B2 (фаза B, этап B1).
## Автономен: не зависит от игровых систем проекта; удаление узла Bench из сцены
## оставляет небо работающим (текстуры в этом случае должен назначать внешний риг —
## см. README «Назначение текстур без стенда»).
##
## Управление при ЗАПУЩЕННОЙ сцене (F6):
##   ПРАВАЯ кнопка мыши (зажать и вести) — вращение камеры (yaw/pitch), как в редакторе
##   Стрелки Влево/Вправо/Вверх/Вниз — то же вращение с клавиатуры
##   1 / 2 / 3 / 0 — геометрические режимы A3: маска / дальность входа / длина пути / чистое небо
##   4 — предпросмотр (средняя плотность × gain)
##   5 — объёмный марш Beer-Lambert (режим по умолчанию)
##   6 — визуализация пропускания T (белый = прозрачно, чёрный = плотно)
##   H — напечатать в Output: интервал [t_near, t_far], mean_density, T, шаги, early-exit
## В 3D-вьюпорте РЕДАКТОРА (без F6) стенд не работает — там крутите штатным orbit-режимом
## редактора; для проверки неба запускайте сцену.
##
## B1-ОБЯЗАННОСТИ стенда:
##   - один раз при старте собрать 3D-текстуры из .bin (CloudTextureLoader) и назначить
##     их в материал (персистенция ImageTexture3D в 4.7 сломана — см. loader);
##   - CPU-дрейф поля от ветра (wind_direction/wind_speed → cloud_offset, как v31:
##     без TIME в шейдере, cubemap не дёргается; speed=0 → поле статично/детерминировано);
##   - зеркала шейдерных функций для численных проверок без рендера:
##     compute_interval (A3), compute_density (B1: трилинейная выборка тех же .bin
##     с GPU-соглашением тексель-центров (i+0.5)/n), compute_mean_density (A4),
##     compute_march (A5). Точность: GDScript float64 vs GLSL float32 — совпадение
##     до ~1e-3 (структурные/статистические проверки).

const EPS := 1e-6
const PW_SIZE := 128
const WO_SIZE := 32
const PW_PATH := "res://Q7.32_SKY_B2/noise_pw_128.bin"
const WO_PATH := "res://Q7.32_SKY_B2/noise_worley_32.bin"
const PITCH_LIMIT_DEG := 89.0

@export var camera_path: NodePath = ^"../Camera3D"
@export var env_path: NodePath = ^"../WorldEnvironment"
@export var pitch_speed_deg := 40.0			# скорость клавишного наклона, °/с
@export var yaw_speed_deg := 60.0			# скорость клавишного поворота, °/с
@export var mouse_sensitivity_deg := 0.15	# чувствительность мыши, °/пиксель
@export var wind_direction := Vector3(1.0, 0.0, 0.3)	# направление дрейфа поля (нормализуется)
@export var wind_speed := 0.0					# м/с; 0 = статичное поле (детерминированные тесты)

var _cam: Camera3D = null
var _mat: ShaderMaterial = null
var _base_offset := Vector3.ZERO
var _drift := Vector3.ZERO

## CPU-копии вокселей для зеркала (загружаются один раз).
static var _pw_voxels := PackedByteArray()
static var _conv := "minus05"   # отладочная конвенция тексель-центров
static var _flips := 0          # отладочная маска инверсий осей (bit0=x, bit1=y, bit2=z)
static var _wo_voxels := PackedByteArray()


func _ready() -> void:
	_cam = get_node_or_null(camera_path) as Camera3D
	var we := get_node_or_null(env_path) as WorldEnvironment
	if _cam == null or we == null:
		push_warning("CloudsTestBench: Camera3D/WorldEnvironment не найдены — стенд отключён")
		return
	var sky_res: Sky = we.environment.sky
	if sky_res != null and sky_res.sky_material is ShaderMaterial:
		_mat = sky_res.sky_material
	else:
		push_warning("CloudsTestBench: Sky/ShaderMaterial не найдены — режимы не переключаются")
		return
	_assign_textures()
	_base_offset = _param_vec3("cloud_offset", Vector3.ZERO)
	print("[Bench] ПКМ-drag — камера | стрелки — то же | 0-6 — режимы (5=объём, 6=T) | H — луч | wind_speed=", wind_speed)


## Ленивая загрузка CPU-копий вокселей (для зеркала в headless-тестах и в рантайме).
static func ensure_voxels() -> bool:
	if _pw_voxels.is_empty() or _wo_voxels.is_empty():
		var loader = load("res://Q7.32_SKY_B2/CloudTextureLoader.gd")
		_pw_voxels = loader.load_voxels(PW_PATH, PW_SIZE)
		_wo_voxels = loader.load_voxels(WO_PATH, WO_SIZE)
	return not _pw_voxels.is_empty() and not _wo_voxels.is_empty()


## Сборка и назначение 3D-текстур (один раз при старте).
func _assign_textures() -> void:
	var t0 := Time.get_ticks_msec()
	var loader_script = load("res://Q7.32_SKY_B2/CloudTextureLoader.gd")
	var pw_tex: ImageTexture3D = loader_script.load_texture(PW_PATH, PW_SIZE)
	var wo_tex: ImageTexture3D = loader_script.load_texture(WO_PATH, WO_SIZE)
	if pw_tex == null:
		push_error("CloudsTestBench: PW-текстура не собрана — использую заглушку (небо будет ровным)")
		pw_tex = loader_script.placeholder_texture()
	if wo_tex == null:
		push_error("CloudsTestBench: Worley-текстура не собрана — использую заглушку")
		wo_tex = loader_script.placeholder_texture()
	_mat.set_shader_parameter("noise_pw", pw_tex)
	_mat.set_shader_parameter("noise_worley", wo_tex)
	# CPU-копии для зеркала
	ensure_voxels()
	print("[Bench] текстуры собраны из .bin за %d мс (pw=%d³ wo=%d³)" % [Time.get_ticks_msec() - t0, PW_SIZE, WO_SIZE])


## === ЗЕРКАЛА ШЕЙДЕРНЫХ ФУНКЦИЙ ===

## Зеркало layer_interval() (A3).
static func compute_interval(dir: Vector3, bottom: float, top: float) -> Dictionary:
	var d := dir.normalized()
	if absf(d.y) <= EPS:
		return {"hit": false, "t_near": 0.0, "t_far": 0.0}
	var t1 := bottom / d.y
	var t2 := top / d.y
	var t_near := maxf(minf(t1, t2), 0.0)
	var t_far := maxf(t1, t2)
	return {"hit": t_far > t_near, "t_near": t_near, "t_far": t_far}


## Трилинейная выборка из воксельного массива в GPU-соглашении:
## u — нормированные координаты (периоды), repeat-wrap, центры текселей (i+0.5)/n.
static func sample_tex(data: PackedByteArray, n: int, ux: float, uy: float, uz: float) -> float:
	if data.is_empty():
		return 0.0
	var fn := float(n)
	var shift := 0.5
	if _conv == "none":
		shift = 0.0
	elif _conv == "plus05":
		shift = -0.5
	if _flips & 1:
		ux = -ux
	if _flips & 2:
		uy = -uy
	if _flips & 4:
		uz = -uz
	var x := fposmod(ux * fn - shift, fn)
	var y := fposmod(uy * fn - shift, fn)
	var z := fposmod(uz * fn - shift, fn)
	var x0 := int(floorf(x))
	var y0 := int(floorf(y))
	var z0 := int(floorf(z))
	var fx := x - float(x0)
	var fy := y - float(y0)
	var fz := z - float(z0)
	var x1: int = (x0 + 1) % n
	var y1: int = (y0 + 1) % n
	var z1: int = (z0 + 1) % n
	var nn := n * n
	var c000 := float(data[z0 * nn + y0 * n + x0]) * (1.0 / 255.0)
	var c100 := float(data[z0 * nn + y0 * n + x1]) * (1.0 / 255.0)
	var c010 := float(data[z0 * nn + y1 * n + x0]) * (1.0 / 255.0)
	var c110 := float(data[z0 * nn + y1 * n + x1]) * (1.0 / 255.0)
	var c001 := float(data[z1 * nn + y0 * n + x0]) * (1.0 / 255.0)
	var c101 := float(data[z1 * nn + y0 * n + x1]) * (1.0 / 255.0)
	var c011 := float(data[z1 * nn + y1 * n + x0]) * (1.0 / 255.0)
	var c111 := float(data[z1 * nn + y1 * n + x1]) * (1.0 / 255.0)
	return lerpf(
		lerpf(lerpf(c000, c100, fx), lerpf(c010, c110, fx), fy),
		lerpf(lerpf(c001, c101, fx), lerpf(c011, c111, fx), fy),
		fz)


## Параметры плотности одним словарём (значения по умолчанию = дефолты материала).
static func dp_defaults(dp: Dictionary) -> Dictionary:
	var out := {
		"base_scale": 16000.0,
		"detail_scale": 1200.0,
		"coverage": 0.42,
		"softness": 0.12,
		"strength": 0.18,
		"offset": Vector3.ZERO,
		"base_fade": 0.15,
		"top_fade": 0.35,
		"erosion": 0.40,
		"stretch": 2.5,
		"fade_start": 4000.0,
		"fade_end": 12000.0,
		"bottom": 1500.0,
		"top": 3500.0,
	}
	for k in dp.keys():
		out[k] = dp[k]
	return out


## Зеркало cloud_density() (B1): PW-форма + Worley-выступы + высотный профиль.
static func compute_density(pos: Vector3, dp: Dictionary = {}, t: float = 0.0) -> float:
	var q := dp_defaults(dp)
	var off: Vector3 = q.offset
	var pw := pos + off
	var shape := sample_tex(_pw_voxels, PW_SIZE, pw.x / q.base_scale, pw.y / (q.base_scale * q.stretch), pw.z / q.base_scale)
	var detail := sample_tex(_wo_voxels, WO_SIZE, pw.x / q.detail_scale, pw.y / q.detail_scale, pw.z / q.detail_scale)
	var fade: float = 1.0 - smoothstep(q.fade_start, q.fade_end, t)
	var ero: float = q.erosion * fade
	var str: float = q.strength * (0.25 + 0.75 * fade)
	var n: float = shape - ero * (1.0 - detail) * (1.0 - shape) + str * (detail - 0.5)
	var d := smoothstep(q.coverage - q.softness, q.coverage + q.softness, n)
	var thickness: float = maxf(q.top - q.bottom, 1e-4)
	var hgt := clampf((pos.y - q.bottom) / thickness, 0.0, 1.0)
	var profile := smoothstep(0.0, q.base_fade, hgt) * (1.0 - smoothstep(1.0 - q.top_fade, 1.0, hgt))
	return d * profile


## Зеркало предпросмотра режима 4.
static func compute_mean_density(dir: Vector3, bottom: float, top: float, steps := 32, dp: Dictionary = {}) -> Dictionary:
	var iv := compute_interval(dir, bottom, top)
	if not iv.hit:
		return {"hit": false, "mean_density": 0.0}
	var q := dp_defaults(dp)
	q.bottom = bottom
	q.top = top
	var n := clampi(steps, 4, 128)
	var seg: float = (iv.t_far - iv.t_near) / float(n)
	var acc := 0.0
	var d := dir.normalized()
	for i in range(n):
		var t: float = iv.t_near + (float(i) + 0.5) * seg
		acc += compute_density(d * t, q, t)
	return {"hit": true, "mean_density": acc / float(n)}


## Зеркало режима 5 (A5): Beer-Lambert марш. Инвариант: scattered + T = 1 (albedo=1).
static func compute_march(dir: Vector3, bottom: float, top: float, steps := 64,
		max_len := 30000.0, extinction := 0.0025, early_exit := 0.01, dp: Dictionary = {}) -> Dictionary:
	var iv := compute_interval(dir, bottom, top)
	if not iv.hit:
		return {"hit": false, "transmittance": 1.0, "scattered": 0.0,
			"steps_used": 0, "t_end": 0.0, "early_exited": false}
	var q := dp_defaults(dp)
	q.bottom = bottom
	q.top = top
	var n := clampi(steps, 8, 256)
	var t_end: float = minf(float(iv.t_far), float(iv.t_near) + max_len)
	var seg: float = (t_end - float(iv.t_near)) / float(n)
	var tr := 1.0
	var sc := 0.0
	var used := 0
	var exited := false
	var d := dir.normalized()
	if seg > 0.0:
		for i in range(n):
			var t: float = float(iv.t_near) + (float(i) + 0.5) * seg
			var dens := compute_density(d * t, q, t)
			var step_tr := exp(-dens * extinction * seg)
			sc += tr * (1.0 - step_tr)
			tr *= step_tr
			used += 1
			if tr < early_exit:
				exited = true
				break
	return {"hit": true, "transmittance": tr, "scattered": sc,
		"steps_used": used, "t_end": t_end, "early_exited": exited}


## === ИНТЕРАКЦИЯ ===

func _unhandled_input(event: InputEvent) -> void:
	if _mat == null or _cam == null:
		return
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		_rotate_camera(-event.relative.x * mouse_sensitivity_deg, -event.relative.y * mouse_sensitivity_deg)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_0:
				_set_mode(0.0)
			KEY_1:
				_set_mode(1.0)
			KEY_2:
				_set_mode(2.0)
			KEY_3:
				_set_mode(3.0)
			KEY_4:
				_set_mode(4.0)
			KEY_5:
				_set_mode(5.0)
			KEY_6:
				_set_mode(6.0)
			KEY_H:
				_print_center_ray()


func _rotate_camera(yaw_delta_deg: float, pitch_delta_deg: float) -> void:
	if _cam == null:
		return
	var rd := _cam.rotation_degrees
	rd.y += yaw_delta_deg
	rd.x = clampf(rd.x + pitch_delta_deg, -PITCH_LIMIT_DEG, PITCH_LIMIT_DEG)
	_cam.rotation_degrees = rd


func _set_mode(m: float) -> void:
	_mat.set_shader_parameter("debug_mode", m)
	print("[Bench] debug_mode = ", int(m))


func _print_center_ray() -> void:
	if _mat == null or _cam == null:
		return
	var dir := -_cam.global_transform.basis.z
	var bottom := _param_float("cloud_layer_bottom", 1500.0)
	var top := _param_float("cloud_layer_top", 3500.0)
	var dp := _material_dp(bottom, top)
	var r := compute_interval(dir, bottom, top)
	var pitch := rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))
	if r.hit:
		var md := compute_mean_density(dir, bottom, top, int(_param_float("preview_steps", 32.0)), dp)
		var mc := compute_march(dir, bottom, top, int(_param_float("march_steps", 64.0)),
			_param_float("max_ray_length", 30000.0), _param_float("extinction_scale", 0.0025),
			_param_float("early_exit_transmittance", 0.01), dp)
		print("[Bench] pitch=%.1f° dir.y=%.5f → HIT t=[%.1f, %.1f] mean_d=%.3f T=%.4f шагов=%d%s drift=(%.0f,%.0f,%.0f)"
			% [pitch, dir.y, r.t_near, r.t_far, md.mean_density, mc.transmittance, mc.steps_used,
				" (early-exit)" if mc.early_exited else "", _drift.x, _drift.y, _drift.z])
	else:
		print("[Bench] pitch=%.1f° dir.y=%.5f → MISS (пересечения со слоем нет)" % [pitch, dir.y])


## Параметры плотности из материала (для H-печати и зеркальных расчётов в рантайме).
func _material_dp(bottom: float, top: float) -> Dictionary:
	return {
		"base_scale": _param_float("cloud_base_scale", 16000.0),
		"detail_scale": _param_float("cloud_detail_scale", 1200.0),
		"coverage": _param_float("cloud_coverage", 0.50),
		"softness": _param_float("cloud_softness", 0.12),
		"strength": _param_float("cloud_detail_strength", 0.18),
		"offset": _param_vec3("cloud_offset", Vector3.ZERO),
		"base_fade": _param_float("height_base_fade", 0.15),
		"top_fade": _param_float("height_top_fade", 0.35),
		"erosion": _param_float("cloud_erosion", 0.40),
		"stretch": _param_float("cloud_vertical_stretch", 2.5),
		"fade_start": _param_float("detail_fade_start", 4000.0),
		"fade_end": _param_float("detail_fade_end", 12000.0),
		"bottom": bottom,
		"top": top,
	}


func _param_float(param_name: String, fallback: float) -> float:
	var v: Variant = _mat.get_shader_parameter(param_name)
	return float(v) if v != null else fallback


func _param_vec3(param_name: String, fallback: Vector3) -> Vector3:
	var v: Variant = _mat.get_shader_parameter(param_name)
	if v == null:
		return fallback
	return Vector3(v.x, v.y, v.z)


func _process(delta: float) -> void:
	if _cam == null:
		return
	# CPU-дрейф поля от ветра (как v31: накопление на CPU, TIME в шейдере не используется)
	if wind_speed != 0.0 and _mat != null:
		_drift += wind_direction.normalized() * wind_speed * delta
		_mat.set_shader_parameter("cloud_offset", _base_offset + _drift)
	var pitch := 0.0
	var yaw := 0.0
	if Input.is_physical_key_pressed(KEY_UP):
		pitch += 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		pitch -= 1.0
	if Input.is_physical_key_pressed(KEY_LEFT):
		yaw += 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		yaw -= 1.0
	if pitch != 0.0 or yaw != 0.0:
		_rotate_camera(yaw * yaw_speed_deg * delta, pitch * pitch_speed_deg * delta)
