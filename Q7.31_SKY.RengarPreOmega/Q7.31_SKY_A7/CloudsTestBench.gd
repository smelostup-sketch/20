extends Node
## CloudsTestBench — диагностический стенд компонента Q7.31_SKY_A7 (этапы A3-A7).
## Автономен: не зависит от игровых систем проекта; удаление узла Bench из сцены
## ничего не ломает (небо продолжает рендериться шейдером).
##
## Управление при ЗАПУЩЕННОЙ сцене (F6):
##   ПРАВАЯ кнопка мыши (зажать и вести) — вращение камеры (yaw/pitch), как в редакторе
##   Стрелки Влево/Вправо/Вверх/Вниз — то же вращение с клавиатуры
##   1 / 2 / 3 / 0 — геометрические режимы A3: маска / дальность входа / длина пути / чистое небо
##   4 — A4-предпросмотр (средняя плотность)
##   5 — A5-объёмный марш Beer-Lambert (режим по умолчанию)
##   6 — A6-визуализация пропускания T (белый = прозрачно, чёрный = плотное облако)
##   H — напечатать в Output: интервал [t_near, t_far], mean_density и transmittance
## В 3D-вьюпорте РЕДАКТОРА (без F6) стенд не работает — там крутите штатным orbit-режимом
## редактора; для проверки неба запускайте сцену.
##
## Зеркала шейдерных функций (для численных проверок без рендера):
##   compute_interval()     — зеркало layer_interval() (A3);
##   compute_density()      — зеркало cloud_density() (A4);
##   compute_mean_density() — зеркало предпросмотра режима 4 (A4);
##   compute_march()        — зеркало режима 5 (A5): Beer-Lambert с аналитическим
##                             затуханием в сегменте, лимитом длины и early-exit.
## Точность: GDScript float64 против GLSL float32 — структурное совпадение ~1e-3;
## инвариант сохранения энергии (scattered + transmittance = 1 при albedo=1) в зеркале
## выполняется телескопически. При изменении логики шейдера зеркала обновлять синхронно.

const EPS := 1e-6
const DEFAULT_BOTTOM := 1500.0
const DEFAULT_TOP := 3500.0
const PITCH_LIMIT_DEG := 89.0

@export var camera_path: NodePath = ^"../Camera3D"
@export var env_path: NodePath = ^"../WorldEnvironment"
@export var pitch_speed_deg := 40.0			# скорость клавишного наклона, °/с
@export var yaw_speed_deg := 60.0			# скорость клавишного поворота, °/с
@export var mouse_sensitivity_deg := 0.15	# чувствительность мыши, °/пиксель

var _cam: Camera3D = null
var _mat: ShaderMaterial = null


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
	print("[Bench] ПКМ-drag — камера | стрелки — то же | 0-6 — режимы (5=объём, 6=пропускание T) | H — луч")


## === ЗЕРКАЛА ШЕЙДЕРНЫХ ФУНКЦИЙ ===

## Зеркало layer_interval(). Возвращает {"hit": bool, "t_near": float, "t_far": float}.
static func compute_interval(dir: Vector3, bottom: float, top: float) -> Dictionary:
	var d := dir.normalized()
	if absf(d.y) <= EPS:
		return {"hit": false, "t_near": 0.0, "t_far": 0.0}
	var t1 := bottom / d.y
	var t2 := top / d.y
	var t_near := maxf(minf(t1, t2), 0.0)
	var t_far := maxf(t1, t2)
	return {"hit": t_far > t_near, "t_near": t_near, "t_far": t_far}


## Зеркало ihash3()/hash13i() — целочисленный хэш (uint32-арифметика в int64 с маской).
## Побитово точен: умножения < 2^63, маска 0xFFFFFFFF после каждой операции = wrap mod 2^32.
static func _ihash3(ix: int, iy: int, iz: int) -> int:
	var qx: int = (ix + 32768) & 0xFFFFFFFF
	var qy: int = (iy + 32768) & 0xFFFFFFFF
	var qz: int = (iz + 32768) & 0xFFFFFFFF
	var h: int = (qx * 374761393 + qy * 668265263 + qz * 2147483647) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return h


static func _hash13i(ix: int, iy: int, iz: int) -> float:
	return float(_ihash3(ix, iy, iz)) / 4294967295.0


## Зеркало value_noise() — трилинейная интерполяция хэшей углов ячейки.
static func _value_noise(p: Vector3) -> float:
	var fl := p.floor()
	var ix := int(fl.x)
	var iy := int(fl.y)
	var iz := int(fl.z)
	var f := p - fl
	var u := f * f * (Vector3(3.0, 3.0, 3.0) - 2.0 * f)
	var c000 := _hash13i(ix, iy, iz)
	var c100 := _hash13i(ix + 1, iy, iz)
	var c010 := _hash13i(ix, iy + 1, iz)
	var c110 := _hash13i(ix + 1, iy + 1, iz)
	var c001 := _hash13i(ix, iy, iz + 1)
	var c101 := _hash13i(ix + 1, iy, iz + 1)
	var c011 := _hash13i(ix, iy + 1, iz + 1)
	var c111 := _hash13i(ix + 1, iy + 1, iz + 1)
	return lerpf(
		lerpf(lerpf(c000, c100, u.x), lerpf(c010, c110, u.x), u.y),
		lerpf(lerpf(c001, c101, u.x), lerpf(c011, c111, u.x), u.y),
		u.z)


## Зеркало fbm() — 4 октавы, лакунарность 2.03.
static func _fbm(p: Vector3) -> float:
	var sum := 0.0
	var amp := 0.5
	var total_amp := 0.0
	var q := p
	for _o in range(4):
		sum += amp * _value_noise(q)
		total_amp += amp
		q *= 2.03
		amp *= 0.5
	return sum / total_amp


## Зеркало cloud_density() (A7): форма + выступы + высотный профиль.
## Высоты от плоскости камеры; layer_bottom/top задают слой для профиля.
static func compute_density(pos: Vector3, freq := 0.0004, coverage := 0.5, softness := 0.1, offset := Vector3.ZERO,
		detail_freq := 0.0016, detail_strength := 0.18, base_fade := 0.15, top_fade := 0.35,
		layer_bottom := 1500.0, layer_top := 3500.0) -> float:
	var shape := _fbm(pos * freq + offset)
	var detail := _fbm(pos * detail_freq + offset)
	var n := shape + detail_strength * (detail - 0.5)
	var d := smoothstep(coverage - softness, coverage + softness, n)
	var thickness := maxf(layer_top - layer_bottom, 1e-4)
	var hgt := clampf((pos.y - layer_bottom) / thickness, 0.0, 1.0)
	var profile := smoothstep(0.0, base_fade, hgt) * (1.0 - smoothstep(1.0 - top_fade, 1.0, hgt))
	return d * profile


## Зеркало предпросмотра режима 4: {"hit", "mean_density"}.
static func compute_mean_density(dir: Vector3, bottom: float, top: float, steps := 32,
		freq := 0.0004, coverage := 0.5, softness := 0.1, offset := Vector3.ZERO,
		detail_freq := 0.0016, detail_strength := 0.18, base_fade := 0.15, top_fade := 0.35) -> Dictionary:
	var iv := compute_interval(dir, bottom, top)
	if not iv.hit:
		return {"hit": false, "mean_density": 0.0}
	var n := clampi(steps, 4, 128)
	var seg: float = (iv.t_far - iv.t_near) / float(n)
	var acc := 0.0
	var d := dir.normalized()
	for i in range(n):
		var t: float = iv.t_near + (float(i) + 0.5) * seg
		acc += compute_density(d * t, freq, coverage, softness, offset,
			detail_freq, detail_strength, base_fade, top_fade, bottom, top)
	return {"hit": true, "mean_density": acc / float(n)}


## Зеркало режима 5 (A5): Beer-Lambert марш с аналитическим затуханием в сегменте.
## Возвращает: hit, transmittance, scattered (при albedo=1), steps_used, t_end, early_exited.
## Инвариант: scattered + transmittance == 1 (телескопическая сумма), даже при early-exit.
static func compute_march(dir: Vector3, bottom: float, top: float, steps := 64,
		max_len := 30000.0, extinction := 0.0025, early_exit := 0.01,
		freq := 0.0004, coverage := 0.5, softness := 0.1, offset := Vector3.ZERO,
		detail_freq := 0.0016, detail_strength := 0.18, base_fade := 0.15, top_fade := 0.35) -> Dictionary:
	var iv := compute_interval(dir, bottom, top)
	if not iv.hit:
		return {"hit": false, "transmittance": 1.0, "scattered": 0.0,
			"steps_used": 0, "t_end": 0.0, "early_exited": false}
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
			var dens := compute_density(d * t, freq, coverage, softness, offset,
				detail_freq, detail_strength, base_fade, top_fade, bottom, top)
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
	# Мышь: вращение камеры при зажатой правой кнопке (то же ощущение, что орбита в редакторе).
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


## Общий вход вращения: yaw/pitch в градусах (pitch клампится ±89°).
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
	var bottom := _param_float("cloud_layer_bottom", DEFAULT_BOTTOM)
	var top := _param_float("cloud_layer_top", DEFAULT_TOP)
	var freq := _param_float("density_frequency", 0.0004)
	var cov := _param_float("density_coverage", 0.5)
	var soft := _param_float("density_softness", 0.1)
	var r := compute_interval(dir, bottom, top)
	var pitch := rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))
	if r.hit:
		var md := compute_mean_density(dir, bottom, top, int(_param_float("preview_steps", 32.0)), freq, cov, soft,
			_param_vec3("density_offset", Vector3.ZERO),
			_param_float("detail_frequency", 0.0016), _param_float("detail_strength", 0.18),
			_param_float("height_base_fade", 0.15), _param_float("height_top_fade", 0.35))
		var mc := compute_march(dir, bottom, top, int(_param_float("march_steps", 64.0)),
			_param_float("max_ray_length", 30000.0), _param_float("extinction_scale", 0.0025),
			_param_float("early_exit_transmittance", 0.01), freq, cov, soft,
			_param_vec3("density_offset", Vector3.ZERO),
			_param_float("detail_frequency", 0.0016), _param_float("detail_strength", 0.18),
			_param_float("height_base_fade", 0.15), _param_float("height_top_fade", 0.35))
		print("[Bench] pitch=%.1f° dir.y=%.5f → HIT t=[%.1f, %.1f] mean_d=%.3f T=%.4f шагов=%d%s"
			% [pitch, dir.y, r.t_near, r.t_far, md.mean_density, mc.transmittance, mc.steps_used,
				" (early-exit)" if mc.early_exited else ""])
	else:
		print("[Bench] pitch=%.1f° dir.y=%.5f → MISS (пересечения со слоем нет)" % [pitch, dir.y])


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
