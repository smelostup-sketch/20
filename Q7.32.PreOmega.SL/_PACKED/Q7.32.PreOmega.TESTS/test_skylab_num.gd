extends SceneTree
## test_skylab_num.gd — saмотест параллельного зеркала SkyLabMirror (SKYLAB v0.5).
## Headless, без GPU. Проверяет инварианты нового слоя освещения skylab_clouds.gdshader:
##  R1 стоповость рамп (u=0..4 даёт точно стопы sk_ramp0..4);
##  R2 монотонность светлоты рамп по u (анти-инверсия зон);
##  R3 фон: зенит = sk_zenith, надир = sk_horizon (маски солнца на этих лучах нулевые);
##  R4 E_ill ∈ [0,1] и scatter ≥ 0 наprobe-точках слоя; rim = 0 при t_light = 1 и при dot(V,L) ≤ 0;
##  R5 crisp_alpha: 0 на a_raw ≤ lo, 1 на a_raw ≥ hi, 0.5 в середине (lo/hi симметричны);
##  R6 зеркало читает те жеUniforms, что шейдер (ramp at u=2 == sk_ramp2).
## Запуск: godot --headless --path <проект> --script res://Q7.32_SKYprav_3.1/_selftest/test_skylab_num.gd

const MAT_PATH := "res://Q7.32_SKYprav_3.1/skylab_clouds_material.tres"
const MIRROR := preload("res://Q7.32_SKYprav_3.1/SkyLabMirror.gd")
const BENCH := preload("res://Q7.32_SKYprav_3.1/CloudsTestBench.gd")

var fails := 0
var passes := 0


func check(cond: bool, name: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		printerr("[SkyLabTest] FAIL: %s" % name)


func _init() -> void:
	var mat: ShaderMaterial = load(MAT_PATH)
	if mat == null:
		printerr("[SkyLabTest] FAIL: материал не загрузился")
		quit(1)
		return
	var stops: Array = [
		MIRROR.pv(mat, "sk_ramp0"), MIRROR.pv(mat, "sk_ramp1"),
		MIRROR.pv(mat, "sk_ramp2"), MIRROR.pv(mat, "sk_ramp3"),
		MIRROR.pv(mat, "sk_ramp4")]

	# R1: стоповость
	for i in range(5):
		var c: Vector3 = MIRROR.ramp_color(float(i), stops)
		check(c.distance_to(stops[i] as Vector3) < 1e-5, "R1 ramp stop %d" % i)
	# R2: монотонность светлоты
	var lum_prev := -1.0
	for k in range(17):
		var c: Vector3 = MIRROR.ramp_color(float(k) * 0.25, stops)
		var lum := c.dot(Vector3(0.2126, 0.7152, 0.0722))
		check(lum >= lum_prev - 1e-6, "R2 monotone u=%.2f" % (float(k) * 0.25))
		lum_prev = lum
	# R3: фон
	var zen: Vector3 = MIRROR.skylab_gradient(Vector3(0, 1, 0), mat)
	var sd0: Vector3 = MIRROR.pv(mat, "sk_sun_dir", Vector3(0, 0, -1)).normalized()
	var low0 := 1.0 - MIRROR.sstep(0.0, 20.0, sd0.y)
	var dimf := 1.0 - MIRROR.pf(mat, "sk_low_dim", 0.25) * low0
	var zen_mid: Vector3 = MIRROR.pv(mat, "sk_zenith") * MIRROR.pf(mat, "sk_zen_lift", 2.0)
	# зенит: hmask=0 → base=zen_mid, затем dim
	var zen_exp: Vector3 = zen_mid * dimf
	check(zen.distance_to(zen_exp) < 1e-5, "R3 zenith = zen_mid*dim (средняя точка полюсов)")
	var nadir: Vector3 = MIRROR.skylab_gradient(Vector3(0, -1, 0), mat)
	var nadir_exp: Vector3 = zen_mid.lerp(MIRROR.pv(mat, "sk_below_col", Vector3(0.030, 0.011, 0.018)),
			MIRROR.sstep(0.0, -0.18, -1.0) * MIRROR.pf(mat, "sk_below_int", 0.55)) * dimf
	check(nadir.distance_to(nadir_exp) < 1e-5, "R3 nadir = below-mix*dim")
	# R4: инварианты terms на probe-точках
	var dp: Dictionary = BENCH.dp_defaults({})
	dp["bottom"] = mat.get_shader_parameter("cloud_layer_bottom")
	dp["top"] = mat.get_shader_parameter("cloud_layer_top")
	var probes := [Vector3(0, 2500, 0), Vector3(1200, 1800, -3000), Vector3(-2500, 3200, 1500)]
	for p in probes:
		var r: Dictionary = MIRROR.skylab_terms(p, Vector3(0, 0, -1), dp, mat)
		check(r.E >= 0.0 and r.E <= 1.0, "R4 E range %s" % str(p))
		check(r.scatter >= 0.0, "R4 scatter >= 0 %s" % str(p))
		check(r.rim >= 0.0, "R4 rim >= 0 %s" % str(p))
	var lit_dir: Vector3 = (mat.get_shader_parameter("cloud_light_direction") as Vector3).normalized()
	var r_back: Dictionary = MIRROR.skylab_terms(Vector3(0, 2500, 0), -lit_dir, dp, mat)
	check(r_back.rim < 1e-6, "R4 rim=0 при dot(V,L)<=0")
	# R5: crisp
	var lo: float = MIRROR.pf(mat, "sk_alpha_lo", 0.10)
	var hi: float = MIRROR.pf(mat, "sk_alpha_hi", 0.90)
	check(MIRROR.crisp_alpha(0.0, mat) < 1e-6, "R5 crisp(0)=0")
	check(absf(MIRROR.crisp_alpha(1.0, mat) - 1.0) < 1e-6, "R5 crisp(1)=1")
	check(absf(MIRROR.crisp_alpha((lo + hi) * 0.5, mat) - 0.5) < 1e-6, "R5 crisp(mid)=0.5")
	# R6: wiring uniforms
	var c2: Vector3 = MIRROR.ramp_color(2.0, stops)
	check(c2.distance_to(MIRROR.pv(mat, "sk_ramp2")) < 1e-5, "R6 ramp(u=2)==sk_ramp2")

	# R7 (v0.5.1): порядок темноты купола при низком солнце: антисоляр < зенит < солнечный горизонт
	var lum_w := Vector3(0.2126, 0.7152, 0.0722)
	var anti_dir: Vector3 = -sd0
	var l_anti := MIRROR.skylab_gradient(anti_dir, mat).dot(lum_w)
	var l_zen := MIRROR.skylab_gradient(Vector3(0, 1, 0), mat).dot(lum_w)
	var l_sol := MIRROR.skylab_gradient(Vector3(0.0, 0.06, -0.998), mat).dot(lum_w)
	check(l_anti < l_zen, "R7 антисоляр темнее зенита (anti=%.4f zen=%.4f)" % [l_anti, l_zen])
	check(l_zen < l_sol, "R7 зенит темнее солнечного горизонта (zen=%.4f sol=%.4f)" % [l_zen, l_sol])
	print("[SkyLabTest] R7 luminances: anti=%.4f zenith=%.4f solar_horizon=%.4f" % [l_anti, l_zen, l_sol])
	# R8 (v0.5.2): доля светлого купола монотонно растёт с высотой солнца
	var fracs: Array = []
	for elev in [0.0, 20.0, 45.0, 70.0]:
		var e := deg_to_rad(elev)
		var sdE := Vector3(0.0, sin(e), -cos(e))
		mat.set_shader_parameter("sk_sun_dir", sdE)
		var l_a := MIRROR.skylab_gradient(-sdE, mat).dot(lum_w)
		var l_s := MIRROR.skylab_gradient(sdE, mat).dot(lum_w)
		var thr := lerpf(l_a, l_s, 0.35)
		var cnt := 0
		var tot := 0
		for ia in range(12):
			for ie in [10.0, 35.0, 65.0]:
				var az := deg_to_rad(float(ia) * 30.0)
				var el := deg_to_rad(ie)
				var ddir := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
				tot += 1
				if MIRROR.skylab_gradient(ddir, mat).dot(lum_w) > thr:
					cnt += 1
		fracs.append(float(cnt) / float(tot))
	mat.set_shader_parameter("sk_sun_dir", sd0)
	check(fracs[0] <= fracs[1] and fracs[1] <= fracs[2] and fracs[2] <= fracs[3],
			"R8 доля светлого купола растёт с высотой солнца (%s)" % str(fracs))
	print("[SkyLabTest] R8 lit-fraction by sun elev [0,20,45,70]: %s" % str(fracs))
	# R9 (v0.5.3): таблица адаптивных шагов марша (march_steps=48, cheap=false)
	var exp_steps := [48, 68, 96, 186, 192]
	var angs := [0.0, 45.0, 60.0, 75.0, 89.0]
	var ok9 := true
	for i in range(5):
		var dy := cos(deg_to_rad(angs[i]))
		var st := MIRROR.march_steps_for(dy, false, 48.0)
		if st != exp_steps[i]:
			ok9 = false
			printerr("[SkyLabTest] R9 mismatch angle %.0f: %d != %d" % [angs[i], st, exp_steps[i]])
	check(ok9, "R9 адаптивные шаги = таблице заказчика [48,68,96,186,192]")
	check(MIRROR.march_steps_for(0.0, true, 48.0) == 32, "R9 cheap-ветка без адаптации = 32")
	print("[SkyLabTest] PASS=%d FAIL=%d" % [passes, fails])
	quit(1 if fails > 0 else 0)
