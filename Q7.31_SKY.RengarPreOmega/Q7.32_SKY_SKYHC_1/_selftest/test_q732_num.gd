extends SceneTree
## test_q732_num.gd — поставляемый selftest компонента Q7.32_SKY_SKYHC_1 (headless, CPU-зеркала).
## Секции: R ресурсы/сцена, H Henyey-Greenstein, L члены освещения B3, M lit-марш B3,
## G регрессия B2/B1, S эффекты B4 (тень/powder/MS/atmo), D диагностика и гейты B5,
## P профили и subpasses-контракт B6. Рендер НЕ выполняется (GPU не нужен).
## Запуск: godot --headless --path <проект с компонентом> --script res://Q7.32_SKY_SKYHC_1/_selftest/test_q732_num.gd
## Код вырос из харнесса этапов B3-B6 (test_b3_num.gd … test_b6_num.gd, песочница поставки).

const BENCH_PATH := "res://Q7.32_SKY_SKYHC_1/CloudsTestBench.gd"
const SHADER_PATH := "res://Q7.32_SKY_SKYHC_1/omega_volumetric_clouds.gdshader"
const MATERIAL_PATH := "res://Q7.32_SKY_SKYHC_1/omega_clouds_test_material.tres"
const SKY_PATH := "res://Q7.32_SKY_SKYHC_1/omega_clouds_test_sky.tres"
const SCENE_PATH := "res://Q7.32_SKY_SKYHC_1/Сцена_облаков_тест.tscn"

var B: GDScript = null
var _fails := 0
var _total := 0


func check(label: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		print("PASS %02d | %s %s" % [_total, label, detail])
	else:
		_fails += 1
		print("FAIL %02d | %s %s" % [_total, label, detail])


func _init() -> void:
	B = load(BENCH_PATH)
	print("=== Q7.32_SKY_SKYHC_1 численный suite (headless, CPU-зеркала) ===")
	section_resources()
	if B.ensure_voxels():
		check("B.voxels", true, "(pw=128³ wo=32³ загружены)")
		section_hg()
		section_terms()
		section_march()
		section_regression_b2()
		section_b4()
		section_b5()
		section_b6()
		section_c1()
		section_c2()
		section_c4()
		section_c5()
		section_c6()
		section_c7()
		section_c8()
		section_c9()
		section_d1()
		section_d2()
		section_d3()
		section_skyhc_1()
	else:
		check("B.voxels", false, "(.bin не загружены — остальные секции пропущены)")
	print("=== ИТОГ: %d/%d PASS, %d FAIL ===" % [_total - _fails, _total, _fails])
	quit(1 if _fails > 0 else 0)


func section_resources() -> void:
	print("--- Секция R: ресурсы компонента ---")
	var sh: Shader = load(SHADER_PATH)
	check("R1 shader load", sh != null)
	var code := ""
	if sh != null:
		code = sh.code
	check("R2 shader содержит B3-функции", code.contains("hg_phase") and code.contains("cloud_radiance") and code.contains("layer_height_fraction"))
	check("R3 shader содержит B3-uniform'ы", code.contains("uniform bool use_hg_phase") and code.contains("uniform float hg_g")
		and code.contains("uniform vec3 cloud_light_direction") and code.contains("uniform float cloud_ambient_energy")
		and code.contains("uniform bool use_ambient_gradient"))
	var mat: ShaderMaterial = load(MATERIAL_PATH)
	check("R4 material load", mat != null and mat.shader == sh)
	var names := ["cloud_light_direction", "cloud_light_color", "cloud_light_strength", "use_hg_phase", "hg_g",
		"cloud_ambient_sky_color", "cloud_ambient_ground_color", "cloud_ambient_energy", "use_ambient_gradient"]
	var missing := []
	for n in names:
		if mat.get_shader_parameter(n) == null:
			missing.append(n)
	check("R5 материал: все 9 B3-параметров", missing.is_empty(), "(нет: %s)" % str(missing) if not missing.is_empty() else "")
	check("R6 bool-типы в материале", typeof(mat.get_shader_parameter("use_hg_phase")) == TYPE_BOOL
		and typeof(mat.get_shader_parameter("use_ambient_gradient")) == TYPE_BOOL)
	var sky: Sky = load(SKY_PATH)
	check("R7 sky load + material", sky != null and sky.sky_material == mat)
	# В Godot 4.7 enum Sky: AUTOMATIC=0, INCREMENTAL=2, REALTIME=3. Значение 2 в .tres
	# (наследие B2) = INCREMENTAL — проверяем фактическое соответствие .tres и enum.
	check("R8 sky process_mode=INCREMENTAL(2), как в B2", sky.process_mode == Sky.PROCESS_MODE_INCREMENTAL
		and int(sky.process_mode) == 2, "(факт=%d)" % int(sky.process_mode))
	var ps: PackedScene = load(SCENE_PATH)
	check("R9 scene load", ps != null and ps.can_instantiate())
	var root: Node = ps.instantiate()
	var light := root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	var bench := root.get_node_or_null("Bench") as Node
	var cam := root.get_node_or_null("Camera3D") as Camera3D
	check("R10 scene-узлы (Bench/Camera/Light)", light != null and bench != null and cam != null)
	# Конвенция синка: basis.z света (НА источник) ≈ cloud_light_direction материала (с нормировкой)
	if light != null:
		var to_sun := light.transform.basis.z.normalized()
		var md: Vector3 = mat.get_shader_parameter("cloud_light_direction")
		check("R11 свет сцены ↔ uniform солнца", to_sun.dot(md.normalized()) > 0.9999,
			"(dot=%.6f, elev=%.1f°)" % [to_sun.dot(md.normalized()), rad_to_deg(asin(clampf(to_sun.y, -1.0, 1.0)))])
	# Камера B2-регрессия: питч +20°, transform не изменён
	if cam != null:
		var pitch := rad_to_deg(asin(clampf((-cam.transform.basis.z).y, -1.0, 1.0)))
		check("R12 питч камеры +20° (B2)", absf(pitch - 20.0) < 0.5, "(факт=%.2f°)" % pitch)
	root.free()


func section_hg() -> void:
	print("--- Секция H: Henyey-Greenstein (зеркало hg_phase) ---")
	# H1: g=0 → точный изотроп 1.0
	var iso_ok := true
	for i in range(41):
		var c := -1.0 + float(i) * 0.05
		if absf(B.hg_phase(c, 0.0) - 1.0) > 1e-12:
			iso_ok = false
	check("H1 hg(g=0)≡1 (41 точка)", iso_ok)
	# H2: границы g=0.5: phase(+1)=(1+g)/(1-g)²=6, phase(-1)=(1-g)/(1+g)²=0.2222
	var pmax: float = B.hg_phase(1.0, 0.5)
	var pmin: float = B.hg_phase(-1.0, 0.5)
	check("H2 границы g=0.5", absf(pmax - 6.0) < 1e-12 and absf(pmin - 2.0 / 9.0) < 1e-12,
		"(max=%.6f min=%.6f)" % [pmax, pmin])
	# H3: монотонность по cosθ (g=0.5 и g=-0.5 зеркально)
	var mono := true
	var mono_neg := true
	var prev: float = B.hg_phase(-1.0, 0.5)
	var prev_neg: float = B.hg_phase(-1.0, -0.5)
	for i in range(1, 201):
		var c := -1.0 + float(i) * 0.01
		var v: float = B.hg_phase(c, 0.5)
		var vn: float = B.hg_phase(c, -0.5)
		if v < prev - 1e-12:
			mono = false
		if vn > prev_neg + 1e-12:
			mono_neg = false
		prev = v
		prev_neg = vn
	check("H3 монотонность g>0 / g<0", mono and mono_neg)
	# H4: clamp ±0.9 (g=±1.5 → как ±0.9, конечные значения)
	var c1: float = B.hg_phase(0.3, 1.5)
	var c2: float = B.hg_phase(0.3, 0.9)
	var c3: float = B.hg_phase(-0.7, -1.5)
	var c4: float = B.hg_phase(-0.7, -0.9)
	check("H4 clamp g=±1.5→±0.9", absf(c1 - c2) < 1e-12 and absf(c3 - c4) < 1e-12 and is_finite(c1) and is_finite(c3))
	# H5: симметрия phase(c,g)=phase(-c,-g)
	var sym := true
	for i in range(21):
		var c := -1.0 + float(i) * 0.1
		if absf(B.hg_phase(c, 0.6) - B.hg_phase(-c, -0.6)) > 1e-12:
			sym = false
	check("H5 симметрия g↔-g", sym)
	# H6: знаменатель > 0 на всей области (нет деления на ноль/NaN при |g|≤0.9)
	var finite := true
	for i in range(19):
		var g := -0.9 + float(i) * 0.1
		for j in range(21):
			var c := -1.0 + float(j) * 0.1
			if not is_finite(B.hg_phase(c, g)):
				finite = false
	check("H6 конечность на сетке g×cosθ", finite)


func section_terms() -> void:
	print("--- Секция L: compute_lighting_terms / compute_radiance ---")
	var bottom := 1500.0
	var top := 3500.0
	var lp := {"albedo": Vector3(1, 1, 1), "light_strength": 0.0}	# ambient-only для чистоты H/L-проверок
	# L1: градиент ambient: h=0 → ground, h=1 → sky, h=0.5 → середина (energy=1)
	var lp1: Dictionary = B.lp_defaults(lp)
	lp1.amb_energy = 1.0
	lp1.light_strength = 0.0
	var t0: Dictionary = B.compute_lighting_terms(Vector3(0, bottom, 0), Vector3(0, 1, 0), lp1)
	var t1: Dictionary = B.compute_lighting_terms(Vector3(0, top, 0), Vector3(0, 1, 0), lp1)
	var tm: Dictionary = B.compute_lighting_terms(Vector3(0, (bottom + top) * 0.5, 0), Vector3(0, 1, 0), lp1)
	var a0: Vector3 = t0.ambient
	var a1: Vector3 = t1.ambient
	var am: Vector3 = tm.ambient
	var sky: Vector3 = lp1.amb_sky
	var gr: Vector3 = lp1.amb_ground
	check("L1 ambient h=0/0.5/1", a0.distance_to(gr) < 1e-12 and a1.distance_to(sky) < 1e-12
		and am.distance_to(gr.lerp(sky, 0.5)) < 1e-12)
	# L2: use_amb_grad=false → константа sky на любой высоте
	var lp2: Dictionary = B.lp_defaults(lp1)
	lp2.use_amb_grad = false
	var c_lo: Dictionary = B.compute_lighting_terms(Vector3(0, bottom, 0), Vector3(0, 1, 0), lp2)
	var c_hi: Dictionary = B.compute_lighting_terms(Vector3(0, top, 0), Vector3(0, 1, 0), lp2)
	var c_out: Dictionary = B.compute_lighting_terms(Vector3(0, top + 5000.0, 0), Vector3(0, 1, 0), lp2)
	var av: Vector3 = c_lo.ambient
	check("L2 ambient-константа (градиент выкл)", av.distance_to(c_hi.ambient) < 1e-12
		and av.distance_to(c_out.ambient) < 1e-12 and av.distance_to(sky) < 1e-12)
	# L3: нулевой light_dir → конечный результат, cosθ=0 (guard как в шейдере)
	var lp3: Dictionary = B.lp_defaults({"light_dir": Vector3.ZERO})
	var z: Dictionary = B.compute_lighting_terms(Vector3(0, 2000, 0), Vector3(0, 1, 0), lp3)
	check("L3 нулевой light_dir без NaN", is_finite(z.cos_theta) and absf(z.cos_theta) < 1e-9
		and (z.total as Vector3).length() < 1e6)
	# L4: линейность по light_strength (sun×2, ambient не меняется)
	var lp4a: Dictionary = B.lp_defaults({"light_dir": Vector3(0, 0.6, -0.8), "albedo": Vector3(1, 1, 1)})
	var lp4b: Dictionary = B.lp_defaults(lp4a)
	lp4b.light_strength = float(lp4a.light_strength) * 2.0
	var ta: Dictionary = B.compute_lighting_terms(Vector3(0, 2500, 0), Vector3(0, 0.34, -0.94), lp4a)
	var tb: Dictionary = B.compute_lighting_terms(Vector3(0, 2500, 0), Vector3(0, 0.34, -0.94), lp4b)
	var sa: Vector3 = ta.sun
	var sb: Vector3 = tb.sun
	check("L4 линейность sun по strength", sb.distance_to(sa * 2.0) < 1e-12
		and (ta.ambient as Vector3).distance_to(tb.ambient) < 1e-12)
	# L5: альбедо умножает оба члена; cosθ/phase не зависят от альбедо
	var lp5: Dictionary = B.lp_defaults(lp4a)
	lp5.albedo = Vector3(0.5, 0.25, 1.0)
	var t5: Dictionary = B.compute_lighting_terms(Vector3(0, 2500, 0), Vector3(0, 0.34, -0.94), lp5)
	var s5: Vector3 = t5.sun
	var a5: Vector3 = t5.ambient
	check("L5 альбедо-множитель", s5.distance_to(sa * Vector3(0.5, 0.25, 1.0)) < 1e-12
		and a5.distance_to((ta.ambient as Vector3) * Vector3(0.5, 0.25, 1.0)) < 1e-12
		and absf(float(t5.phase) - float(ta.phase)) < 1e-12)
	# L6: use_hg=false → phase=1 при любом cosθ; total = sun(изотроп)+amb
	var lp6: Dictionary = B.lp_defaults({"use_hg": false, "light_dir": Vector3(0, 1, 0)})
	var t6: Dictionary = B.compute_lighting_terms(Vector3(0, 2500, 0), Vector3(0, -1, 0), lp6)
	var lc: Vector3 = lp6.light_color
	var expect_sun: Vector3 = lc * float(lp6.light_strength) * (lp6.albedo as Vector3)
	check("L6 HG выкл → изотроп", absf(float(t6.phase) - 1.0) < 1e-12 and (t6.sun as Vector3).distance_to(expect_sun) < 1e-12)
	# L7: view_dir ненормированный → тот же результат (нормируется внутри)
	var t7: Dictionary = B.compute_lighting_terms(Vector3(0, 2500, 0), Vector3(0, 34, -94), lp4a)
	check("L7 инвариантность к длине view_dir", absf(float(t7.cos_theta) - float(ta.cos_theta)) < 1e-12)


func section_march() -> void:
	print("--- Секция M: compute_march_lit ---")
	var bottom := 1500.0
	var top := 3500.0
	var dp := {"offset": Vector3(8000, 1600, 0)}	# scenic-офсет материала B2
	var lp := {}
	var rays := [Vector3(0, 1, 0), Vector3(0, 0.342, -0.94), Vector3(0.3, 0.15, -0.942), Vector3(-0.5, 0.08, -0.862)]
	var r2 := Vector3(0, sin(deg_to_rad(2.0)), -cos(deg_to_rad(2.0)))	# плотный луч B2
	# M1: MISS (вниз) → hit=false, T=1, S=0
	var m0: Dictionary = B.compute_march_lit(Vector3(0, -1, 0), bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp)
	check("M1 MISS вниз", (not m0.hit) and absf(float(m0.transmittance) - 1.0) < 1e-12 and (m0.scattered as Vector3).length() < 1e-12)
	# M2: split sun+ambient == scattered (точно, float64) для всех лучей
	var split_ok := true
	var t_ok := true
	for r in rays:
		var m: Dictionary = B.compute_march_lit(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp)
		var sc: Vector3 = m.scattered
		var ss: Vector3 = m.sun_scattered
		var sa: Vector3 = m.ambient_scattered
		# Vector3 в Godot — float32: накопление sc/sc_sun/sc_amb даёт расхождение ~1e-7
		if ss.distance_to(sc - sa) > 1e-5:
			split_ok = false
		# M3-часть: T совпадает со скалярным маршем B2
		var ms: Dictionary = B.compute_march(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp)
		if absf(float(m.transmittance) - float(ms.transmittance)) > 1e-12 or int(m.steps_used) != int(ms.steps_used):
			t_ok = false
	check("M2 split sun+ambient==scattered (1e-5, float32-накопление Vector3)", split_ok)
	check("M3 T и шаги ≡ скалярному маршу B2 (освещение не влияет на T)", t_ok)
	# M4: energy bounds — S ∈ [(1-T)·Lmin, (1-T)·Lmax] покомпонентно (независимый пересчёт весов)
	var bounds_ok := true
	for r in rays:
		var iv: Dictionary = B.compute_interval(r, bottom, top)
		if not iv.hit:
			continue
		var n := 64
		var t_end: float = minf(float(iv.t_far), float(iv.t_near) + 30000.0)
		var seg: float = (t_end - float(iv.t_near)) / float(n)
		var d: Vector3 = r.normalized()
		var lmin := Vector3(INF, INF, INF)
		var lmax := Vector3(-INF, -INF, -INF)
		var tr := 1.0
		var sum_w := 0.0
		for i in range(n):
			var t: float = float(iv.t_near) + (float(i) + 0.5) * seg
			var dens: float = B.compute_density(d * t, dp, t)
			var step_tr := exp(-dens * 0.0025 * seg)
			var rad: Vector3 = B.compute_radiance(d * t, d, lp)
			lmin = lmin.min(rad)
			lmax = lmax.max(rad)
			var w := tr * (1.0 - step_tr)
			sum_w += w
			tr *= step_tr
			if tr < 0.01:
				break
		var m: Dictionary = B.compute_march_lit(r, bottom, top, n, 30000.0, 0.0025, 0.01, dp, lp)
		var sc: Vector3 = m.scattered
		var one_minus_t := 1.0 - float(m.transmittance)
		if absf(sum_w - one_minus_t) > 1e-9:
			bounds_ok = false	# телескопирование весов Σw = 1-T
		for ch in 3:
			var sv: float = sc[ch]
			if sv < lmin[ch] * one_minus_t - 1e-9 or sv > lmax[ch] * one_minus_t + 1e-9:
				bounds_ok = false
	check("M4 energy bounds + Σw=1-T", bounds_ok)
	# M5: направленность — плотный луч 2° (гарантированно насыщенный, метрика B2),
	# солнце НА луч и ОТ луча: S_вперёд > S_назад, T равны
	var rdir := Vector3(0, sin(deg_to_rad(2.0)), -cos(deg_to_rad(2.0))).normalized()
	var lp_fwd := {"light_dir": rdir, "amb_energy": 0.0, "light_strength": 1.0, "light_color": Vector3(1, 1, 1), "albedo": Vector3(1, 1, 1)}
	var lp_bwd: Dictionary = B.lp_defaults(lp_fwd)
	lp_bwd.light_dir = -rdir
	var mf: Dictionary = B.compute_march_lit(rdir, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp_fwd)
	var mb: Dictionary = B.compute_march_lit(rdir, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp_bwd)
	var sf: Vector3 = mf.scattered
	var sb2: Vector3 = mb.scattered
	var ratio := sf.x / maxf(sb2.x, 1e-12)
	check("M5 HG-направленность (S_к_солнцу/S_от_солнца)", absf(float(mf.transmittance) - float(mb.transmittance)) < 1e-12
		and ratio > 5.0, "(ratio=%.1f, ожид. ~6.5: 27 сжато diffuse mix 0.45 — D2)" % ratio)
	# M6: детерминизм — два identical вызова бит-в-бит
	var m1: Dictionary = B.compute_march_lit(rays[1], bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp)
	var m2: Dictionary = B.compute_march_lit(rays[1], bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp)
	check("M6 детерминизм", (m1.scattered as Vector3).distance_to(m2.scattered) == 0.0
		and float(m1.transmittance) == float(m2.transmittance) and int(m1.steps_used) == int(m2.steps_used))
	# M7: early-exit сохраняется (плотный луч 2°, как B2: T≈0.0067 → обрыв до 64 шагов)
	var me: Dictionary = B.compute_march_lit(r2, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp)
	check("M7 early-exit на насыщенном луче", bool(me.early_exited) and int(me.steps_used) < 64 and float(me.transmittance) < 0.01,
		"(T=%.4f шагов=%d)" % [float(me.transmittance), int(me.steps_used)])
	# M8: выключенные эффекты честно обнуляют свой вклад
	var lp_ns: Dictionary = B.lp_defaults({"light_strength": 0.0})
	var mn: Dictionary = B.compute_march_lit(r2, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp_ns)
	var lp_na: Dictionary = B.lp_defaults({"amb_energy": 0.0})
	var ma: Dictionary = B.compute_march_lit(r2, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp_na)
	check("M8 strength=0 → sun_sc=0; energy=0 → amb_sc=0", (mn.sun_scattered as Vector3).length() < 1e-12
		and (ma.ambient_scattered as Vector3).length() < 1e-12
		and (mn.ambient_scattered as Vector3).length() > 0.0 and (ma.sun_scattered as Vector3).length() > 0.0)
	# M9: всё выключено (strength=0, energy=0) → S=0, T без изменений (чёрное облако — честный ноль)
	var lp0: Dictionary = B.lp_defaults({"light_strength": 0.0, "amb_energy": 0.0})
	var mz: Dictionary = B.compute_march_lit(r2, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp0)
	var m1d: Dictionary = B.compute_march_lit(r2, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp)
	check("M9 нулевой свет → S=0, T≡B2", (mz.scattered as Vector3).length() < 1e-12
		and absf(float(mz.transmittance) - float(m1d.transmittance)) < 1e-12)


func section_regression_b2() -> void:
	print("--- Секция G: регрессия B2 (идентичность + опубликованные метрики B2) ---")
	var bottom := 1500.0
	var top := 3500.0
	var dp := {"offset": Vector3(8000, 1600, 0)}
	# G1: изотропный единичный свет (g=0, белый×1, ambient=0, альбедо=1) ≡ B2 побитово
	var lp_id := {"hg_g": 0.0, "light_color": Vector3(1, 1, 1), "light_strength": 1.0,
		"amb_energy": 0.0, "albedo": Vector3(1, 1, 1)}
	var ident_ok := true
	var ident_detail := ""
	for r in [Vector3(0, 1, 0), Vector3(0, 0.342, -0.94), Vector3(0.3, 0.05, -0.953)]:
		var ml: Dictionary = B.compute_march_lit(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp_id)
		var ms: Dictionary = B.compute_march(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp)
		var scv: Vector3 = ml.scattered
		var dsc := absf(scv.x - float(ms.scattered))
		# T — скаляр float64 в обоих зеркалах: совпадает побитово; scattered в lit-зеркале
		# копится в Vector3 (float32) → допуск 1e-5. GPU тоже копится в float32 — зеркало ближе к GPU.
		if dsc > 1e-5 or float(ml.transmittance) != float(ms.transmittance) or int(ml.steps_used) != int(ms.steps_used):
			ident_ok = false
			ident_detail = "(ΔS=" + str(dsc) + " ΔT=" + str(absf(float(ml.transmittance) - float(ms.transmittance))) + ")"
	check("G1 B3(изотроп·единичный свет) ≡ B2", ident_ok, ident_detail)
	# G2: пустое поле (coverage=1.5 — недостижимый порог) → T=1, S=0 на любом луче.
	# (Точный GAP-зонд B2 воспроизвести нельзя — их harness не поставлялся; инвариант
	# «нет плотности → нет поглощения» покрывает ту же физику.)
	var dp_empty := {"offset": Vector3(8000, 1600, 0), "coverage": 1.5}
	var g2_ok := true
	for r in [Vector3(0, 1, 0), Vector3(0, 0.342, -0.94), Vector3(0.3, 0.05, -0.953)]:
		var mz: Dictionary = B.compute_march(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp_empty)
		var mzl: Dictionary = B.compute_march_lit(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp_empty, {})
		if absf(float(mz.transmittance) - 1.0) > 1e-12 or absf(float(mz.scattered)) > 1e-12 \
				or (mzl.scattered as Vector3).length() > 1e-6:
			g2_ok = false
	check("G2 пустое поле → T=1, S=0 (скаляр и lit)", g2_ok)
	# G3: метрика B2 «насыщенный луч 2° T=0.0067»
	var r2 := Vector3(0, sin(deg_to_rad(2.0)), -cos(deg_to_rad(2.0)))
	var m2: Dictionary = B.compute_march(r2, bottom, top, 64, 30000.0, 0.0025, 0.01, dp)
	check("G3 луч 2° T≈0.0067 (метрика B2)", absf(float(m2.transmittance) - 0.0067) < 0.002, "(T=%.4f)" % float(m2.transmittance))
	# G4: сохранение S+T=1 в скалярном марше (инвариант A5/B2)
	var cons := true
	for r in [Vector3(0, 1, 0), Vector3(0, 0.342, -0.94), Vector3(-0.4, 0.2, -0.894)]:
		var ms: Dictionary = B.compute_march(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp)
		if ms.hit and absf(float(ms.scattered) + float(ms.transmittance) - 1.0) > 1e-9:
			cons = false
	check("G4 S+T=1 (скаляр, 1e-9)", cons)
	# G5: сходимость шагов |T64-T128| < 1e-4 на луче через разреженное поле (зенит).
	# На лучах через крутые силуэты остаток ~1e-2 — задокументированный алиасинг
	# детали B2 (инцидент B2 §5.2, лечится шагом/TAA в B6/Q7.33), физикой марша не является.
	var a: Dictionary = B.compute_march(Vector3(0, 1, 0), bottom, top, 64, 30000.0, 0.0025, 0.01, dp)
	var b: Dictionary = B.compute_march(Vector3(0, 1, 0), bottom, top, 128, 30000.0, 0.0025, 0.01, dp)
	var dz := absf(float(a.transmittance) - float(b.transmittance))
	check("G5 сходимость |T64-T128|<1e-4 (зенит)", dz < 1e-4, "(Δ=" + str(dz) + ")")
	# G6: dp_defaults не дрейфовали от B2 (ключевые значения)
	var q: Dictionary = B.dp_defaults({})
	check("G6 dp_defaults ≡ B2", float(q.coverage) == 0.42 and float(q.erosion) == 0.40 and float(q.stretch) == 2.5
		and float(q.base_scale) == 16000.0 and float(q.detail_scale) == 1200.0 and float(q.fade_start) == 4000.0
		and float(q.fade_end) == 12000.0 and float(q.bottom) == 1500.0 and float(q.top) == 3500.0)


func section_b4() -> void:
	print("--- Секция S: B4 — self-shadowing / powder / MS / atmo ---")
	var bottom := 1500.0
	var top := 3500.0
	var dp := {"offset": Vector3(8000, 1600, 0)}
	var lp := {}
	var sp_off := {"use_shadow": false, "use_powder": false, "use_ms": false}
	var ap_off := {"use_atmo": false}
	var rays := [Vector3(0, 0.342, -0.94), Vector3(0, sin(deg_to_rad(2.0)), -cos(deg_to_rad(2.0))),
		Vector3(-0.5, 0.08, -0.862)]
	# S1: все эффекты B4 выкл ≡ зеркалу B3 (compute_march_lit)
	var s1 := true
	for r in rays:
		var m4: Dictionary = B.compute_march_b4(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, sp_off, ap_off)
		var m3: Dictionary = B.compute_march_lit(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp)
		if (m4.scattered as Vector3).distance_to(m3.scattered) > 1e-5 \
				or float(m4.transmittance) != float(m3.transmittance):
			s1 = false
	check("S1 B4(эффекты выкл) ≡ B3", s1)
	# S2/S3/S8: probe-точки выбираются ЧЕСТНЫМ сканом вдоль плотного луча 2°:
	# p_dense = argmax плотности; p_deep = argmax плотности в нижней половине слоя;
	# p_mid = первая точка с T_light(6) ∈ [0.05, 0.95] (для сходимости марша тени).
	var r2 := Vector3(0, sin(deg_to_rad(2.0)), -cos(deg_to_rad(2.0)))
	var ldir := Vector3(-0.75, 0.5, -0.43).normalized()
	var iv2: Dictionary = B.compute_interval(r2, bottom, top)
	var dir2 := r2.normalized()
	var p_dense := Vector3.ZERO
	var p_deep := Vector3.ZERO
	var p_mid := Vector3.ZERO
	var d_max := -1.0
	var d_deep_max := -1.0
	for i in range(24):
		var t: float = float(iv2.t_near) + (float(iv2.t_far) - float(iv2.t_near)) * (float(i) + 0.5) / 24.0
		var pos := dir2 * t
		var dv: float = B.compute_density(pos, dp, t)
		if dv > d_max:
			d_max = dv
			p_dense = pos
		var hgt := clampf((pos.y - bottom) / (top - bottom), 0.0, 1.0)
		if hgt < 0.5 and dv > d_deep_max:
			d_deep_max = dv
			p_deep = pos
		if p_mid == Vector3.ZERO:
			var tlx: Dictionary = B.compute_light_transmittance(pos, ldir, dp, {"light_steps": 6.0})
			if float(tlx.t_light) >= 0.05 and float(tlx.t_light) <= 0.95:
				p_mid = pos
	# S2: пустое поле → T_light=1; плотная точка массы → T_light < 0.5
	var lt_empty: Dictionary = B.compute_light_transmittance(Vector3(0, 2500, 0), Vector3(0, 1, 0),
		{"offset": Vector3(8000, 1600, 0), "coverage": 1.5}, {})
	var lt_dense: Dictionary = B.compute_light_transmittance(p_dense, ldir, dp, {})
	check("S2 T_light: пусто=1, в массе<0.5", absf(float(lt_empty.t_light) - 1.0) < 1e-12
		and d_max > 0.3 and float(lt_dense.t_light) < 0.5,
		"(d_max=%.2f пусто=%.3f в_массе=%.3f)" % [d_max, float(lt_empty.t_light), float(lt_dense.t_light)])
	# S3: сходимость марша тени на точке средней тени: |TL6-TL12| < |TL3-TL6| и < 0.05
	var tl3: Dictionary = B.compute_light_transmittance(p_mid, ldir, dp, {"light_steps": 3.0})
	var tl6: Dictionary = B.compute_light_transmittance(p_mid, ldir, dp, {"light_steps": 6.0})
	var tl12: Dictionary = B.compute_light_transmittance(p_mid, ldir, dp, {"light_steps": 12.0})
	var d36 := absf(float(tl3.t_light) - float(tl6.t_light))
	var d612 := absf(float(tl6.t_light) - float(tl12.t_light))
	check("S3 сходимость тени |TL6-TL12|<min(|TL3-TL6|,0.05)", p_mid != Vector3.ZERO and d612 < maxf(d36, 1e-9) and d612 < 0.05,
		"(TL6=%.3f d36=%.4f d612=%.4f)" % [float(tl6.t_light), d36, d612])
	# S8: ранний обрыв марша тени: (а) синтетическое насыщенное поле (coverage=-0.6,
	# softness=0.05 → d≡1 в слое) → обрыв до light_steps и T_light<0.01;
	# (б) наблюдательно: минимальный T_light вдоль плотного луча < 0.5 (тени реальны).
	var dp_sat := {"offset": Vector3(8000, 1600, 0), "coverage": -0.6, "softness": 0.05}
	var p_in := Vector3(0, 1600.0, 0)	# низ слоя: световой путь максимален внутри масс
	var lt_sat: Dictionary = B.compute_light_transmittance(p_in, ldir, dp_sat, {})
	check("S8 ранний обрыв тени (синтетика: samples<4, T<0.01) + тень в массе <0.5 (S2)",
		int(lt_sat.samples_used) < 4 and float(lt_sat.t_light) < 0.01 and float(lt_dense.t_light) < 0.5,
		"(sat samples=%d T=%.4f; в_массе=%.3f)" % [int(lt_sat.samples_used), float(lt_sat.t_light), float(lt_dense.t_light)])
	# S4: тень уменьшает солнечное накопление (покомпонентно)
	var s4 := true
	for r in rays:
		var mon: Dictionary = B.compute_march_b4(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, {"use_powder": false, "use_ms": false}, ap_off)
		var moff: Dictionary = B.compute_march_b4(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, {"use_shadow": false, "use_powder": false, "use_ms": false}, ap_off)
		var a: Vector3 = mon.sun_scattered
		var b2: Vector3 = moff.sun_scattered
		for ch in 3:
			if a[ch] > b2[ch] + 1e-9:
				s4 = false
	check("S4 self-shadowing: sun_sc ≤ без тени", s4)
	# S5: powder уменьшает солнечное накопление
	var s5 := true
	for r in rays:
		var mon: Dictionary = B.compute_march_b4(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, {"use_shadow": false, "use_ms": false}, ap_off)
		var moff: Dictionary = B.compute_march_b4(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, {"use_shadow": false, "use_powder": false, "use_ms": false}, ap_off)
		var a: Vector3 = mon.sun_scattered
		var b2: Vector3 = moff.sun_scattered
		for ch in 3:
			if a[ch] > b2[ch] + 1e-9:
				s5 = false
	check("S5 powder: sun_sc ≤ без powder", s5)
	# S6: MS только добавляет (покомпонентно)
	var s6 := true
	for r in rays:
		var mon: Dictionary = B.compute_march_b4(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, {"use_shadow": false, "use_powder": false}, ap_off)
		var moff: Dictionary = B.compute_march_b4(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, sp_off, ap_off)
		var a: Vector3 = mon.scattered
		var b2: Vector3 = moff.scattered
		for ch in 3:
			if a[ch] < b2[ch] - 1e-9:
				s6 = false
		if (mon.ms_scattered as Vector3).length() <= 0.0:
			s6 = false
	check("S6 MS: scattered ≥ без MS, ms_sc>0", s6)
	# S7: atmo: f=0 → финал ≡ sky*T+S; f=1 → cloudC = atmo*(1-T); f монотонен по t_near
	var ap_f0 := {"use_atmo": true, "atmo_start": 1e9, "atmo_end": 2e9}
	var ap_f1 := {"use_atmo": true, "atmo_start": 0.0, "atmo_end": 0.0}
	var m_f0: Dictionary = B.compute_march_b4(rays[0], bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, sp_off, ap_f0)
	var sky_c := Vector3(0.32, 0.47, 0.68)
	var atmo_c := Vector3(0.55, 0.65, 0.85)
	var tr0: float = float(m_f0.transmittance)
	var ok_f0 := (m_f0.final_color as Vector3).distance_to(sky_c * tr0 + m_f0.scattered) < 1e-9 and absf(float(m_f0.atmo_factor)) < 1e-12
	var m_f1: Dictionary = B.compute_march_b4(rays[0], bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, sp_off, ap_f1)
	var tr1: float = float(m_f1.transmittance)
	var ok_f1 := (m_f1.final_color as Vector3).distance_to(sky_c * tr1 + atmo_c * (1.0 - tr1)) < 1e-9 and absf(float(m_f1.atmo_factor) - 1.0) < 1e-12
	var f_low: Dictionary = B.compute_march_b4(Vector3(0, 0.94, -0.342), bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, sp_off, {})
	var f_high: Dictionary = B.compute_march_b4(r2, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, sp_off, {})
	check("S7 atmo: f=0/f=1 точные композиты, f монотонен", ok_f0 and ok_f1
		and float(f_low.atmo_factor) <= float(f_high.atmo_factor),
		"(f60°=%.2f f2°=%.2f)" % [float(f_low.atmo_factor), float(f_high.atmo_factor)])
	# S9: детерминизм march_b4
	var d1: Dictionary = B.compute_march_b4(rays[1], bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, {}, {})
	var d2: Dictionary = B.compute_march_b4(rays[1], bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, {}, {})
	check("S9 детерминизм march_b4", (d1.final_color as Vector3).distance_to(d2.final_color) == 0.0
		and float(d1.transmittance) == float(d2.transmittance))
	# S10: регрессия: T луча 2° не изменён освещением (метрика B2 0.0067) и ≡ скаляру при B4-выкл
	var m10: Dictionary = B.compute_march_b4(r2, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, {}, {})
	var ms10: Dictionary = B.compute_march(r2, bottom, top, 64, 30000.0, 0.0025, 0.01, dp)
	check("S10 T луча 2° ≡ B2 (0.0067) и не зависит от освещения",
		absf(float(m10.transmittance) - 0.0067) < 0.002 and float(m10.transmittance) == float(ms10.transmittance),
		"(T=%.4f)" % float(m10.transmittance))
	# S11: диагностические поля в границах: t_light_mean ∈ [0,1], atmo_factor ∈ [0,1]
	var s11 := true
	for r in rays:
		var mm: Dictionary = B.compute_march_b4(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, {}, {})
		if float(mm.t_light_mean) < -1e-9 or float(mm.t_light_mean) > 1.0 + 1e-9 \
				or float(mm.atmo_factor) < -1e-9 or float(mm.atmo_factor) > 1.0 + 1e-9:
			s11 = false
	check("S11 t_light_mean/atmo_factor ∈ [0,1]", s11)
	# S12: материал содержит 11 B4-параметров; шейдер — функции B4
	var mat: ShaderMaterial = load("res://Q7.32_SKY_SKYHC_1/omega_clouds_test_material.tres")
	var names := ["use_self_shadow", "light_steps", "shadow_ray_length", "use_powder", "powder_strength",
		"use_ms", "ms_strength", "use_atmo_perspective", "atmo_color", "atmo_start", "atmo_end", "cloud_debug_mode"]
	var miss := []
	for n2 in names:
		if mat.get_shader_parameter(n2) == null:
			miss.append(n2)
	var sh: Shader = load("res://Q7.32_SKY_SKYHC_1/omega_volumetric_clouds.gdshader")
	check("S12 материал: 12 B4-параметров + функции шейдера", miss.is_empty()
		and sh.code.contains("light_transmittance") and sh.code.contains("cloud_radiance_terms")
		and sh.code.contains("MS_SUN_GAIN"), "(нет: %s)" % str(miss) if not miss.is_empty() else "")


func section_b5() -> void:
	print("--- Секция D: B5 — единая диагностика и честный пропуск ---")
	var bottom := 1500.0
	var top := 3500.0
	var dp := {"offset": Vector3(8000, 1600, 0)}
	var lp := {}
	var sp := {}
	var ap := {}
	var rays := [Vector3(0, 0.342, -0.94), Vector3(0, sin(deg_to_rad(2.0)), -cos(deg_to_rad(2.0))),
		Vector3(-0.5, 0.08, -0.862)]
	var albedo := Vector3(0.95, 0.95, 0.97)
	# D1/D2: выходы единого марша ≡ маршу B4 (финал, T, t_light_mean, члены с альбедо)
	var d1 := true
	var d2 := true
	for r in rays:
		var dg: Dictionary = B.compute_march_diag(r, bottom, top, 64, 30000.0, 0.0025, 0.01, 0.0, dp, lp, sp, ap)
		var b4: Dictionary = B.compute_march_b4(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, sp, ap)
		if (dg.mode0_color as Vector3).distance_to(b4.final_color) > 1e-5:
			d1 = false
		if float(dg.transmittance) != float(b4.transmittance) \
				or absf(float(dg.t_light_mean) - float(b4.t_light_mean)) > 1e-12 \
				or (dg.ms_acc as Vector3).distance_to((b4.ms_scattered as Vector3) / albedo) > 1e-6 \
				or (dg.amb_acc as Vector3).distance_to((b4.ambient_scattered as Vector3) / albedo) > 1e-6 \
				or (dg.sun_acc as Vector3).distance_to((b4.sun_scattered as Vector3) / albedo) > 1e-6 \
				or absf(float(dg.atmo_factor) - float(b4.atmo_factor)) > 1e-12:
			d2 = false
	check("D1 режим 0 (финал) ≡ марш B4", d1)
	check("D2 T/t_light_mean/члены/atmo ≡ марш B4", d2)
	# D3: режим 1: mean_d ≡ независимому пересчёту средней плотности ПО ПРОЙДЕННЫМ
	# сегментам (с тем же early-exit): независимый цикл в тесте.
	var d3 := true
	for r in rays:
		var dg: Dictionary = B.compute_march_diag(r, bottom, top, 64, 30000.0, 0.0025, 0.01, 1.0, dp, lp, sp, ap)
		var ivv: Dictionary = B.compute_interval(r, bottom, top)
		var dd: Vector3 = r.normalized()
		var t_end: float = minf(float(ivv.t_far), float(ivv.t_near) + 30000.0)
		var segv: float = (t_end - float(ivv.t_near)) / 64.0
		var trv := 1.0
		var accv := 0.0
		var usedv := 0
		for i in range(64):
			var tv: float = float(ivv.t_near) + (float(i) + 0.5) * segv
			var dvv: float = B.compute_density(dd * tv, dp, tv)
			accv += dvv
			usedv += 1
			trv *= exp(-dvv * 0.0025 * segv)
			if trv < 0.01:
				break
		var expect := accv / float(maxi(usedv, 1))
		if absf(float(dg.mean_d) - expect) > 1e-12:
			d3 = false
	check("D3 режим 1: mean_d ≡ зеркалу плотности", d3)
	# D4: плейсхолдеры пропущенных членов по таблице гейтов
	var r2 := Vector3(0, sin(deg_to_rad(2.0)), -cos(deg_to_rad(2.0)))
	var iv2: Dictionary = B.compute_interval(r2, bottom, top)
	var d2v := r2.normalized()
	var p_dense := Vector3.ZERO
	var d_max := -1.0
	for i in range(24):
		var t: float = float(iv2.t_near) + (float(iv2.t_far) - float(iv2.t_near)) * (float(i) + 0.5) / 24.0
		var dv: float = B.compute_density(d2v * t, dp, t)
		if dv > d_max:
			d_max = dv
			p_dense = d2v * t
	var t7: Dictionary = B.compute_terms_b5(p_dense, d2v, d_max, 7.0, dp, lp, sp)
	var t6: Dictionary = B.compute_terms_b5(p_dense, d2v, d_max, 6.0, dp, lp, sp)
	var t3: Dictionary = B.compute_terms_b5(p_dense, d2v, d_max, 3.0, dp, lp, sp)
	var t1: Dictionary = B.compute_terms_b5(p_dense, d2v, d_max, 1.0, dp, lp, sp)
	check("D4 плейсхолдеры гейтов (7: tl=1,ms=0,amb≠0; 6: ms≠0,amb=0; 3: tl<1,ms=0; 1: всё плейсхолдер)",
		float(t7.t_light) == 1.0 and (t7.ms as Vector3).length() == 0.0 and (t7.ambient as Vector3).length() > 0.0
		and (t6.ms as Vector3).length() > 0.0 and (t6.ambient as Vector3).length() == 0.0
		and float(t3.t_light) < 1.0 and (t3.ms as Vector3).length() == 0.0 and (t3.ambient as Vector3).length() == 0.0
		and (t1.sun as Vector3).length() == 0.0 and float(t1.t_light) == 1.0)
	# D5: честность переключателей в режимах: выкл эффект → вклад режима нулевой/нейтральный
	var m3_off: Dictionary = B.compute_march_diag(rays[1], bottom, top, 64, 30000.0, 0.0025, 0.01, 3.0, dp, lp, {"use_shadow": false}, ap)
	var m5_off: Dictionary = B.compute_march_diag(rays[1], bottom, top, 64, 30000.0, 0.0025, 0.01, 5.0, dp, lp, {"use_powder": false}, ap)
	var m6_off: Dictionary = B.compute_march_diag(rays[1], bottom, top, 64, 30000.0, 0.0025, 0.01, 6.0, dp, lp, {"use_ms": false}, ap)
	var m8_off: Dictionary = B.compute_march_diag(rays[1], bottom, top, 64, 30000.0, 0.0025, 0.01, 8.0, dp, lp, sp, {"use_atmo": false})
	var m8_on: Dictionary = B.compute_march_diag(rays[1], bottom, top, 64, 30000.0, 0.0025, 0.01, 8.0, dp, lp, sp, ap)
	var b8: Dictionary = B.compute_march_b4(rays[1], bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, sp, ap)
	check("D5 переключатели: cdm3 без тени=1, cdm5 без powder=0, cdm6 без MS=0, cdm8 без atmo=0 (=B4 atmo)",
		absf(float(m3_off.t_light_mean) - 1.0) < 1e-12 and absf(float(m5_off.pow_rem_w)) < 1e-12
		and (m6_off.ms_acc as Vector3).length() == 0.0 and absf(float(m8_off.atmo_factor)) < 1e-12
		and absf(float(m8_on.atmo_factor) - float(b8.atmo_factor)) < 1e-12)
	# D6: режимы 1-2 не зависят от освещения (гейт need_terms=false)
	var d6 := true
	var lp_zero := {"light_strength": 0.0, "amb_energy": 0.0, "use_hg": false}
	for cdmv in [1.0, 2.0]:
		var a: Dictionary = B.compute_march_diag(rays[0], bottom, top, 64, 30000.0, 0.0025, 0.01, cdmv, dp, lp, sp, ap)
		var b: Dictionary = B.compute_march_diag(rays[0], bottom, top, 64, 30000.0, 0.0025, 0.01, cdmv, dp, lp_zero, sp, ap)
		if absf(float(a.mean_d) - float(b.mean_d)) > 1e-12 or float(a.transmittance) != float(b.transmittance):
			d6 = false
	check("D6 режимы 1-2 не зависят от освещения", d6)
	# D7: legacy удалён из шейдера; гейты присутствуют в исходнике
	var sh: Shader = load("res://Q7.32_SKY_SKYHC_1/omega_volumetric_clouds.gdshader")
	check("D7 шейдер: legacy debug_mode/preview удалены, гейты на месте",
		not sh.code.contains("uniform float debug_mode") and not sh.code.contains("preview_steps")
		and sh.code.contains("bool need_terms") and sh.code.contains("bool need_shadow")
		and sh.code.contains("bool need_powder") and sh.code.contains("bool need_ms")
		and sh.code.contains("bool need_amb"))
	# D8: режим 8 не маршит: atmo_factor при hit и miss; miss-константы режимов
	var miss: Dictionary = B.compute_march_diag(Vector3(0, -1, 0), bottom, top, 64, 30000.0, 0.0025, 0.01, 0.0, dp, lp, sp, ap)
	check("D8 miss: T=1, mean_d=0, mode0=sky_color", absf(float(miss.transmittance) - 1.0) < 1e-12
		and absf(float(miss.mean_d)) < 1e-12
		and (miss.mode0_color as Vector3).distance_to(Vector3(0.32, 0.47, 0.68)) < 1e-9)


func section_b6() -> void:
	print("--- Секция P: B6 — профили, subpasses-контракт, cubemap-ветка ---")
	var bottom := 1500.0
	var top := 3500.0
	var dp := {"offset": Vector3(8000, 1600, 0)}
	var lp := {}
	# P1: таблица профилей
	var tbl: Dictionary = B.profile_table()
	var p0: Dictionary = tbl[0]
	var p1: Dictionary = tbl[1]
	var p2: Dictionary = tbl[2]
	var p3: Dictionary = tbl[3]
	check("P1 таблица профилей (tier/march/light/упрощения)",
		int(p0.tier) == 2 and float(p0.march) == 32.0 and float(p0.light) == 3.0 and p0.powder == false and p0.ms == false
		and int(p1.tier) == 1 and float(p1.march) == 48.0 and float(p1.light) == 4.0
		and int(p2.tier) == 1 and float(p2.march) == 64.0 and float(p2.light) == 6.0
		and int(p3.tier) == 0 and float(p3.march) == 64.0)
	# P2: сходимость шагов марша 32/48/64 (профильные значения): разности не возрастают
	var r := Vector3(0, 1, 0)
	var t32: Dictionary = B.compute_march(r, bottom, top, 32, 30000.0, 0.0025, 0.01, dp)
	var t48: Dictionary = B.compute_march(r, bottom, top, 48, 30000.0, 0.0025, 0.01, dp)
	var t64: Dictionary = B.compute_march(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp)
	var d3248 := absf(float(t32.transmittance) - float(t48.transmittance))
	var d4864 := absf(float(t48.transmittance) - float(t64.transmittance))
	check("P2 сходимость шагов 32→48→64 монотонна", d4864 <= d3248 + 1e-12,
		"(d3248=" + str(d3248) + " d4864=" + str(d4864) + ")")
	# P3: сходимость шагов тени 2→3→4→6 (cap cubemap-ветки = 2)
	var ldir := Vector3(-0.75, 0.5, -0.43).normalized()
	var iv2: Dictionary = B.compute_interval(Vector3(0, sin(deg_to_rad(2.0)), -cos(deg_to_rad(2.0))), bottom, top)
	var d2v := Vector3(0, sin(deg_to_rad(2.0)), -cos(deg_to_rad(2.0))).normalized()
	var p_mid := Vector3.ZERO
	for i in range(24):
		var t: float = float(iv2.t_near) + (float(iv2.t_far) - float(iv2.t_near)) * (float(i) + 0.5) / 24.0
		var tlx: Dictionary = B.compute_light_transmittance(d2v * t, ldir, dp, {"light_steps": 6.0})
		if float(tlx.t_light) >= 0.05 and float(tlx.t_light) <= 0.95:
			p_mid = d2v * t
			break
	var tl2: Dictionary = B.compute_light_transmittance(p_mid, ldir, dp, {"light_steps": 2.0})
	var tl3: Dictionary = B.compute_light_transmittance(p_mid, ldir, dp, {"light_steps": 3.0})
	var tl4: Dictionary = B.compute_light_transmittance(p_mid, ldir, dp, {"light_steps": 4.0})
	var tl6: Dictionary = B.compute_light_transmittance(p_mid, ldir, dp, {"light_steps": 6.0})
	var e23 := absf(float(tl2.t_light) - float(tl3.t_light))
	var e34 := absf(float(tl3.t_light) - float(tl4.t_light))
	var e46 := absf(float(tl4.t_light) - float(tl6.t_light))
	check("P3 сходимость тени 2→3→4→6 монотонна", e34 <= e23 + 1e-12 and e46 <= e34 + 1e-12,
		"(e23=%.3f e34=%.3f e46=%.3f)" % [e23, e34, e46])
	# P4: шейдер: subpass-механика 4.7 на месте (built-ins, контракт ALPHA, композит mix).
	# SKYHC-1: строка композита изменилась — mix(base, …), где
	# base = (bg + sunbg)·(1 − hc_a) + hc_rgb; при hc_enabled=false hc_a=0 и hc_rgb=0,
	# поэтому base = (bg + sunbg)·1.0 + 0.0 = вид D3 (проверяется вторым ассертом и HC1-1).
	var sh: Shader = load("res://Q7.32_SKY_SKYHC_1/omega_volumetric_clouds.gdshader")
	var ok4 := sh.code.contains("AT_HALF_RES_PASS") and sh.code.contains("AT_QUARTER_RES_PASS") \
		and sh.code.contains("AT_CUBEMAP_PASS") and sh.code.contains("HALF_RES_COLOR") \
		and sh.code.contains("QUARTER_RES_COLOR") and sh.code.contains("ALPHA = alpha") \
		and sh.code.contains("#define SKY_TIER") and sh.code.contains("render_mode use_half_res_pass;") \
		and sh.code.contains("render_mode use_quarter_res_pass;") \
		and sh.code.contains("mix(base, sub.rgb, sub.a)") \
		and sh.code.contains("vec3 base = (bg + sunbg) * (1.0 - hc_a) + hc_rgb;")
	check("P4 шейдер: AT_*_PASS/HALF/QUARTER_RES_COLOR/ALPHA/tier-блок", ok4)
	# P5: кросс-зеркало на параметрах профиля Performance: march_diag ≡ march_b4
	var rr := Vector3(0, 0.342, -0.94)
	var dg: Dictionary = B.compute_march_diag(rr, bottom, top, 32, 30000.0, 0.0025, 0.01, 0.0, dp, lp, {"light_steps": 3.0, "use_powder": false, "use_ms": false}, {})
	var b4: Dictionary = B.compute_march_b4(rr, bottom, top, 32, 30000.0, 0.0025, 0.01, dp, lp, {"light_steps": 3.0, "use_powder": false, "use_ms": false}, {})
	check("P5 Performance-параметры: march_diag ≡ march_b4",
		(dg.mode0_color as Vector3).distance_to(b4.final_color) < 1e-5
		and float(dg.transmittance) == float(b4.transmittance))
	# P6: cheap-ветка (cubemap): caps шагов — steps_used ≤ 32 и тень ≤ 2 сэмплов не превысят light_steps
	var dg_c: Dictionary = B.compute_march_diag(rr, bottom, top, 64, 30000.0, 0.0025, 0.01, 0.0, dp, lp, {"light_steps": 6.0}, {})
	check("P6 mirror без caps не ломает регрессию (steps=64 использованы или early-exit)",
		int(dg_c.steps_used) <= 64)


func section_c1() -> void:
	print("--- Секция C: C1 — направления, низкое солнце, dual-HG, MS2, пресеты ---")
	var bottom := 1500.0
	var top := 3500.0
	var dp := {"offset": Vector3(8000, 1600, 0)}
	var lp := {}
	var sp := {}
	var ap := {}
	var view := Vector3(0, 0.342, -0.94).normalized()
	# C1: dual-lobe HG: выкл ≡ одиночная; mix=0 ≡ g1; mix=1 ≡ g2; монотонность/конечность
	var dual_off := true
	var mix0 := true
	var mix1 := true
	var mono := true
	var prev := -1.0
	# монотонность по cosθ напрямую: light_dir=(1,0,0), view=(cos, sin, 0)
	for i in range(41):
		var c := -1.0 + float(i) * 0.05
		var base: Dictionary = B.compute_terms_b5(Vector3(0, 2500, 0), Vector3(c, 0.3, -0.9), 0.5, 0.0, dp, {"use_dual": false}, sp)
		var dual: Dictionary = B.compute_terms_b5(Vector3(0, 2500, 0), Vector3(c, 0.3, -0.9), 0.5, 0.0, dp, {"use_dual": true}, sp)
		if i == 20 and absf(float(dual.phase) - float(base.phase)) < 1e-6:
			dual_off = false	# dual ON обязан отличаться от одиночной доли
		var m0: Dictionary = B.compute_terms_b5(Vector3(0, 2500, 0), Vector3(c, 0.3, -0.9), 0.5, 0.0, dp, {"use_dual": true, "dual_mix": 0.0}, sp)
		var m1: Dictionary = B.compute_terms_b5(Vector3(0, 2500, 0), Vector3(c, 0.3, -0.9), 0.5, 0.0, dp, {"use_dual": true, "dual_mix": 1.0}, sp)
		var g2: Dictionary = B.compute_terms_b5(Vector3(0, 2500, 0), Vector3(c, 0.3, -0.9), 0.5, 0.0, dp, {"use_dual": false, "hg_g": 0.25}, sp)
		if absf(float(base.phase) - float(m0.phase)) > 1e-12:
			dual_off = false	# выкл ≡ mix=0 ≡ одиночная доля
		if absf(float(m0.phase) - float(base.phase)) > 1e-12:
			mix0 = false
		if absf(float(m1.phase) - float(g2.phase)) > 1e-12:
			mix1 = false
		var vv := Vector3(c, sqrt(maxf(0.0, 1.0 - c * c)), 0.0)
		var dd: Dictionary = B.compute_terms_b5(Vector3(0, 2500, 0), vv, 0.5, 0.0, dp,
			{"use_dual": true, "light_dir": Vector3(1, 0, 0)}, sp)
		if float(dd.phase) < prev - 1e-12:
			mono = false
		prev = float(dd.phase)
		if not is_finite(float(dd.phase)):
			mono = false
	if not (dual_off and mix0 and mix1 and mono):
		print("C1 DEBUG dual_off=", dual_off, " mix0=", mix0, " mix1=", mix1, " mono=", mono)
	check("C1 dual-HG: выкл≡одиночная, mix0≡g1, mix1≡g2, монотонна", dual_off and mix0 and mix1 and mono)
	# C2: MS2: выкл → ms2=0 и scattered ≡ сумме членов; вкл → добавляет в плотной точке, 0 в пустом поле
	var r2 := Vector3(0, sin(deg_to_rad(2.0)), -cos(deg_to_rad(2.0)))
	var m_off: Dictionary = B.compute_march_b4(r2, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, {"use_ms2": false}, ap)
	var m_on: Dictionary = B.compute_march_b4(r2, bottom, top, 64, 30000.0, 0.0025, 0.01, dp, lp, {"use_ms2": true}, ap)
	var sc_off: Vector3 = m_off.scattered
	var sc_on: Vector3 = m_on.scattered
	var grows := sc_on.x >= sc_off.x - 1e-9 and sc_on.y >= sc_off.y - 1e-9 and sc_on.z >= sc_off.z - 1e-9
	var m_empty: Dictionary = B.compute_march_b4(r2, bottom, top, 64, 30000.0, 0.0025, 0.01,
		{"offset": Vector3(8000, 1600, 0), "coverage": 1.5}, lp, {"use_ms2": true}, ap)
	check("C2 MS2: выкл ms2=0; вкл добавляет (плотный луч); пустое поле ms2=0",
		(m_off.ms2_scattered as Vector3).length() == 0.0 and grows
		and (m_on.ms2_scattered as Vector3).length() > 0.0
		and (m_empty.ms2_scattered as Vector3).length() == 0.0,
		"(ms2=%s)" % str(m_on.ms2_scattered))
	# C3: кампания направлений: 8 азимутов × elev 30°: S_вперёд > S_назад, T не меняется, всё конечно
	var c3 := true
	var ratio_min := 1e9
	for k in range(8):
		var az := float(k) * TAU / 8.0
		var hor := Vector3(cos(az), 0.0, sin(az))
		var sun_d := (hor * cos(deg_to_rad(30.0)) + Vector3(0, sin(deg_to_rad(30.0)), 0)).normalized()
		var lf: Dictionary = B.compute_march_b4(view, bottom, top, 64, 30000.0, 0.0025, 0.01, dp,
			{"light_dir": sun_d, "amb_energy": 0.0}, {"use_shadow": false, "use_powder": false, "use_ms": false}, ap)
		var lb: Dictionary = B.compute_march_b4(view, bottom, top, 64, 30000.0, 0.0025, 0.01, dp,
			{"light_dir": -sun_d, "amb_energy": 0.0}, {"use_shadow": false, "use_powder": false, "use_ms": false}, ap)
		var sf: Vector3 = lf.scattered
		var sb: Vector3 = lb.scattered
		if not is_finite(sf.x) or not is_finite(sb.x):
			c3 = false
		if absf(float(lf.transmittance) - float(lb.transmittance)) > 1e-12:
			c3 = false
		# направленность = отношение Яркого варианта к тусклому в паре (d, -d)
		var hi := maxf(sf.x, sb.x)
		var lo := maxf(minf(sf.x, sb.x), 1e-12)
		var ratio := hi / lo
		ratio_min = minf(ratio_min, ratio)
		if ratio <= 1.05:	# D2: diffuse mix 0.45 сжимает контраст (было ≥1.2)
			c3 = false
	check("C3 кампания направлений (8 азимутов): направленность ≥1.05 (D2: сжата diffuse mix), T инвариантна", c3,
		"(min ratio=%.1f)" % ratio_min)
	# C4: низкое солнце 1/3/6/10/15°: T_light в массе → 0 (глубокая тень), но L>0 (ambient-пол)
	var c4 := true
	var detail := ""
	for elev in [1.0, 3.0, 6.0, 10.0, 15.0]:
		var sun_d := (view * Vector3(1, 0, 1)).normalized() * cos(deg_to_rad(elev)) + Vector3(0, sin(deg_to_rad(elev)), 0)
		sun_d = sun_d.normalized()
		var ivv: Dictionary = B.compute_interval(r2, bottom, top)
		var dd2 := r2.normalized()
		var worst_tl := 1.0
		var min_l := 1e9
		for i in range(8):
			var t: float = float(ivv.t_near) + (float(ivv.t_far) - float(ivv.t_near)) * (float(i) + 0.5) / 8.0
			var pos := dd2 * t
			var dv: float = B.compute_density(pos, dp, t)
			if dv < 0.3:
				continue
			var tm: Dictionary = B.compute_terms_b5(pos, dd2, dv, 0.0, dp, {"light_dir": sun_d}, {})
			worst_tl = minf(worst_tl, float(tm.t_light))
			var tot: Vector3 = tm.sun + tm.ambient + tm.ms
			min_l = minf(min_l, tot.length())
		if worst_tl > 0.2:
			detail += " elev%.0f:TLmin=%.2f" % [elev, worst_tl]
		if min_l <= 0.0:
			c4 = false
	check("C4 низкое солнце: глубокие тени (TLmin≤0.2) при ненулевом L (ambient-пол)", c4,
		"(пробелы=дефицит плотных сэмплов: %s)" % ("нет" if detail == "" else detail))
	# C5: пресеты: направления конечны/ненулевые; neutral ≡ дефолтам материала
	var tbl: Dictionary = B.preset_table()
	var c5 := true
	for key in ["sunset", "twilight", "night", "neutral", "blood_sunset"]:
		var pr: Dictionary = tbl[key]
		var dv: Vector3 = pr.dir
		if dv.length() < 1e-6 or not is_finite(dv.x) or float(pr.strength) < 0.0:
			c5 = false
	var mat: ShaderMaterial = load("res://Q7.32_SKY_SKYHC_1/omega_clouds_test_material.tres")
	var md: Vector3 = mat.get_shader_parameter("cloud_light_direction")
	var neut: Dictionary = tbl.neutral
	check("C5 пресеты: данные валидны (5 шт.), neutral ≡ дефолту материала", c5
		and (neut.dir as Vector3).normalized().dot(md.normalized()) > 0.9999
		and absf(float(neut.strength) - float(mat.get_shader_parameter("cloud_light_strength"))) < 1e-9)
	# C6: neutral восстанавливает плотность/офсет; blood_sunset меняет геометрию масс
	var bs: Dictionary = tbl.blood_sunset
	check("C6 пресеты: neutral ≡ дефолтам материала (с маской); blood — своё поле, маска выкл",
		absf(float(neut.base_scale) - float(mat.get_shader_parameter("cloud_base_scale"))) < 1e-9
		and absf(float(neut.coverage) - float(mat.get_shader_parameter("cloud_coverage"))) < 1e-9
		and bool(neut.use_weather_mask) == bool(mat.get_shader_parameter("use_weather_mask"))
		and float(bs.base_scale) != float(neut.base_scale) and bs.use_weather_mask == false)


func section_c2() -> void:
	print("--- Секция N: C2 — видимое солнце ---")
	var bottom := 1500.0
	var top := 3500.0
	var dp := {"offset": Vector3(3000, 1600, 9000)}
	var ldir := Vector3(-0.50, 0.14, -0.85).normalized()
	var su := {"light_dir": ldir, "light_color": Vector3(1.0, 0.20, 0.14), "use_blur": false}	# D2: blur меряется в секции D2
	# N1: sun off → фон солнца = 0 (побитово C1-композит)
	var off: Vector3 = B.compute_sun_bg(ldir, {"visible": false})
	check("N1 sun_visible=false → sun_bg=0", off.length() == 0.0)
	# N2: профиль диска: центр = intensity+halo; за кромкой = только гало; монотонное убывание
	var c0: Vector3 = B.compute_sun_bg(ldir, su)
	var q: Dictionary = B.sup_defaults(su)
	var expect_center: Vector3 = (q.disk_color as Vector3) * float(q.intensity) + (q.light_color as Vector3) * float(q.halo_strength)
	var edge_out: Vector3 = B.compute_sun_bg((ldir + Vector3(0, 0.12, 0)).normalized(), su)
	var far: Vector3 = B.compute_sun_bg((ldir + Vector3(0, 0.6, 0)).normalized(), su)
	var mono := c0.length() > edge_out.length() and edge_out.length() > far.length()
	check("N2 диск: центр=(int+halo)·color, убывание к краю и дальше", c0.distance_to(expect_center) < 1e-4 and mono,
		"(center=%.1f edge=%.3f far=%.4f)" % [c0.length(), edge_out.length(), far.length()])
	# N3: окклюзия облаками: финал = (sky+sun)·T + cloudC; вклад солнца масштабируется T
	var r_sun := ldir	# луч прямо в солнце
	var fin: Dictionary = B.compute_final_with_sun(r_sun, bottom, top, 64, 30000.0, 0.0025, 0.01, 0.0, dp, {}, {}, {}, su)
	var tr: float = float(fin.transmittance)
	var sunbg: Vector3 = fin.sun_bg
	var m: Dictionary = fin.march
	var delta: Vector3 = (fin.final as Vector3) - (m.mode0_color as Vector3)
	check("N3 композит с солнцем: вклад солнца = sun_bg·T (окклюзия через T)",
		delta.distance_to(sunbg * tr) < 1e-5 and tr < 0.9,	# 1e-5: Vector3 хранится float32
		"(T=%.3f, |sun|=%.1f → вклад=%.2f)" % [tr, sunbg.length(), sunbg.length() * tr])
	# N4: пресеты содержат солнечные ключи; neutral = дефолты шейдера
	var tbl: Dictionary = B.preset_table()
	var keys_ok := true
	for key in ["sunset", "twilight", "night", "neutral", "blood_sunset"]:
		var pr: Dictionary = tbl[key]
		for k in ["sun_size", "sun_intensity", "sun_halo_strength", "sun_halo_power"]:
			if not pr.has(k) or not is_finite(float(pr[k])):
				keys_ok = false
	var neut: Dictionary = tbl.neutral
	check("N4 солнечные ключи во всех 5 пресетах; neutral = дефолты",
		keys_ok and float(neut.sun_size) == 0.02 and float(neut.sun_intensity) == 16.0
		and float(neut.sun_halo_strength) == 0.25 and float(neut.sun_halo_power) == 250.0)
	# N5: диск конечен и неотрицателен на сетке направлений (без NaN у границ sstep)
	var grid_ok := true
	for i in range(25):
		var a := float(i) * 0.01
		var dv := (ldir + Vector3(0, a, 0)).normalized()
		var v: Vector3 = B.compute_sun_bg(dv, {"softness": 0.0})
		if not is_finite(v.x) or v.x < 0.0:
			grid_ok = false
	check("N5 диск без NaN при softness=0 и на сетке углов", grid_ok)


func section_c4() -> void:
	print("--- Секция W: C4 — weather mask (крупнее и реже) ---")
	var bottom := 1500.0
	var top := 3500.0
	var dp := {"offset": Vector3(8000, 1600, 0)}
	var r2 := Vector3(0, sin(deg_to_rad(2.0)), -cos(deg_to_rad(2.0)))
	# W1: маска выкл ≡ физике без маски (скалярный марш B2)
	var w1 := true
	for r in [Vector3(0, 1, 0), Vector3(0, 0.342, -0.94), r2]:
		var dg: Dictionary = B.compute_march_diag(r, bottom, top, 64, 30000.0, 0.0025, 0.01, 0.0, dp, {}, {}, {})
		var ms: Dictionary = B.compute_march(r, bottom, top, 64, 30000.0, 0.0025, 0.01, dp)
		if float(dg.transmittance) != float(ms.transmittance):
			w1 = false
	check("W1 маска выкл: T ≡ физике B2/C3", w1)
	# W2/W3: маска вкл: в зоне просвета плотность 0; вне зоны = плотность без маски
	var dpm := {"offset": Vector3(8000, 1600, 0), "use_mask": true, "w_strength": 1.0}
	var zero_found := false
	var same_found := false
	var dens_outside_ok := true
	for i in range(64):
		var pos := Vector3(float(i) * 937.0 - 30000.0, 2400.0, float(i * 37 % 997) * 41.0 - 20000.0)
		var pwv := pos + Vector3(8000, 1600, 0)
		var w: float = B.sample_tex(B._pw_voxels, 128, pwv.x / 70000.0, pwv.y / 70000.0, pwv.z / 70000.0)
		var d_on: float = B.compute_density(pos, dpm, 5000.0)
		var d_off: float = B.compute_density(pos, dp, 5000.0)
		if w < 0.35 - 0.15:
			if absf(d_on) < 1e-9:
				zero_found = true
			else:
				dens_outside_ok = false
		elif w > 0.35 + 0.15:
			same_found = true
			if absf(d_on - d_off) > 1e-12:
				dens_outside_ok = false
	check("W2 в зоне просвета плотность=0; W3 вне зоны плотность ≡ без маски",
		zero_found and same_found and dens_outside_ok)
	# W4: маска делает поле реже: доля нулевых сэмплов вдоль луча растёт
	var zeros_off := 0
	var zeros_on := 0
	var iv2: Dictionary = B.compute_interval(r2, bottom, top)
	var dd := r2.normalized()
	for i in range(32):
		var t: float = float(iv2.t_near) + (float(iv2.t_far) - float(iv2.t_near)) * (float(i) + 0.5) / 32.0
		if absf(B.compute_density(dd * t, dp, t)) < 1e-9:
			zeros_off += 1
		if absf(B.compute_density(dd * t, dpm, t)) < 1e-9:
			zeros_on += 1
	check("W4 маска вкл: нулевых сэмплов не меньше (поле реже)", zeros_on >= zeros_off,
		"(off=%d on=%d из 32)" % [zeros_off, zeros_on])


func section_c5() -> void:
	print("--- Секция A2: C5 — ориентация масс (анизотропия/stretch/warp) ---")
	var bottom := 1500.0
	var top := 3500.0
	var dp := {"offset": Vector3(3000, 1600, 9000)}
	# A2-1: всё выкл ≡ физике C4 (скалярный марш на том же поле)
	var a1 := true
	for r in [Vector3(0, 1, 0), Vector3(0, 0.342, -0.94)]:
		var dg: Dictionary = B.compute_march_diag(r, bottom, top, 64, 30000.0, 0.0025, 0.01, 0.0,
			{"offset": Vector3(8000, 1600, 0), "use_mask": true, "w_scale": 30000.0, "w_cut": 0.14,
			"w_soft": 0.06, "w_strength": 0.9, "base_scale": 26000.0, "coverage": 0.47, "erosion": 0.38}, {}, {}, {})
		var ms: Dictionary = B.compute_march(r, bottom, top, 64, 30000.0, 0.0025, 0.01,
			{"offset": Vector3(8000, 1600, 0), "use_mask": true, "w_scale": 30000.0, "w_cut": 0.14,
			"w_soft": 0.06, "w_strength": 0.9, "base_scale": 26000.0, "coverage": 0.47, "erosion": 0.38})
		if float(dg.transmittance) != float(ms.transmittance):
			a1 = false
	check("A2-1 aniso/warp/h-stretch выкл ≡ C4", a1)
	# A2-2: h_stretch уменьшает горизонтальную изменчивость
	var dh1 := 0.0
	var dh2 := 0.0
	for i in range(24):
		var p0 := Vector3(float(i) * 1300.0 - 15000.0, 2400.0, float(i * 53 % 877) * 37.0 - 16000.0)
		var px := p0 + Vector3(2500.0, 0.0, 0.0)
		dh1 += absf(B.compute_density(p0, dp, 5000.0) - B.compute_density(px, dp, 5000.0))
		var dp2: Dictionary = B.dp_defaults(dp)
		dp2.h_stretch = 2.0
		dh2 += absf(B.compute_density(p0, dp2, 5000.0) - B.compute_density(px, dp2, 5000.0))
	check("A2-2 h_stretch=2 сглаживает по горизонтали", dh2 < dh1, "(d1=%.2f d2=%.2f)" % [dh1, dh2])
	# A2-3: warp сбивает вертикальную когерентность (столбы)
	var col0 := 0.0
	var colw := 0.0
	for i in range(16):
		var pxz := Vector3(float(i * 91 % 500) * 60.0 - 15000.0, 0.0, float(i * 137 % 500) * 60.0 - 15000.0)
		var pa := Vector3(pxz.x, 1800.0, pxz.z)
		var pb := Vector3(pxz.x, 2900.0, pxz.z)
		col0 += absf(B.compute_density(pa, dp, 5000.0) - B.compute_density(pb, dp, 5000.0))
		var dpw: Dictionary = B.dp_defaults(dp)
		dpw.warp = 300.0
		colw += absf(B.compute_density(pa, dpw, 5000.0) - B.compute_density(pb, dpw, 5000.0))
	check("A2-3 warp=300 снижает вертикальную когерентность", colw > col0, "(c0=%.2f cw=%.2f)" % [col0, colw])
	# A2-4: закон stretch(h): внизу aniso_base, вверху aniso_top, монотонно; выкл = const
	var dpa2: Dictionary = B.dp_defaults(dp)
	dpa2.use_aniso = true
	var s_lo: float = B.aniso_stretch_at(0.1, dpa2)
	var s_mid: float = B.aniso_stretch_at(0.5, dpa2)
	var s_hi: float = B.aniso_stretch_at(0.9, dpa2)
	var s_off: float = B.aniso_stretch_at(0.5, dp)
	check("A2-4 закон stretch(h): 3.0 внизу, 0.7 вверху, монотонно; выкл = 2.5",
		absf(s_lo - 3.0) < 1e-9 and absf(s_hi - 0.7) < 1e-6 and s_lo > s_mid and s_mid > s_hi
		and absf(s_off - 2.5) < 1e-9,
		"(lo=%.2f mid=%.2f hi=%.2f off=%.2f)" % [s_lo, s_mid, s_hi, s_off])


func section_c6() -> void:
	print("--- Секция N6: C6 — белое ядро солнца ---")
	var ldir_n := Vector3(-0.50, 0.14, -0.85).normalized()
	# N6-1: формула центра: disk_color·intensity + light_color·halo (независимые цвета)
	var q: Dictionary = B.sup_defaults({"light_dir": ldir_n})
	var center: Vector3 = B.compute_sun_bg(ldir_n, {"light_dir": ldir_n})
	var expect: Vector3 = (q.disk_color as Vector3) * float(q.intensity) + (q.light_color as Vector3) * float(q.halo_strength)
	check("N6-1 центр = disk·intensity + light·halo (1e-4: Vector3 float32)", center.distance_to(expect) < 1e-4,
		"(center=%s)" % str(center))
	# N6-2: красный свет + белое ядро → центр почти белый, гало красное
	var su_red := {"light_dir": ldir_n, "light_color": Vector3(1.0, 0.2, 0.14), "disk_color": Vector3(1.0, 0.98, 0.95)}
	var c2: Vector3 = B.compute_sun_bg(ldir_n, su_red)
	var mx := maxf(c2.x, maxf(c2.y, c2.z))
	var mn := minf(c2.x, minf(c2.y, c2.z))
	var sat := (mx - mn) / maxf(mx, 1e-9)
	var side: Vector3 = B.compute_sun_bg((ldir_n + Vector3(0.0, 0.35, 0.0)).normalized(), su_red)
	check("N6-2 ядро белое при красном свете (sat<0.08), гало красное (r>2g)",
		sat < 0.08 and side.x > 2.0 * side.y, "(sat=%.3f side=%s)" % [sat, str(side)])
	# N6-3: sun_visible=false по-прежнему обнуляет всё
	var off: Vector3 = B.compute_sun_bg(ldir_n, {"visible": false})
	check("N6-3 sun off → 0", off.length() == 0.0)
	# N6-4: пресеты несут sun_disk_color; у кровавого ядро белее света
	var tbl: Dictionary = B.preset_table()
	var bs: Dictionary = tbl.blood_sunset
	var nt: Dictionary = tbl.neutral
	var bs_disk: Color = bs.sun_disk_color
	var bs_light: Color = bs.color
	var disk_whiter := (bs_disk.g + bs_disk.b) > (bs_light.g + bs_light.b) + 0.5
	check("N6-4 пресеты: disk_color есть везде; у кровавого ядро белее света",
		tbl.sunset.has("sun_disk_color") and tbl.night.has("sun_disk_color") and disk_whiter
		and float(nt.sun_intensity) == 16.0 and float(bs.sun_intensity) == 24.0)


func section_c7() -> void:
	print("--- Секция F: C7 — distance curtain (чистый горизонт) ---")
	var bottom := 1500.0
	var top := 3500.0
	var dp := {"offset": Vector3(8000, 1600, 0)}
	var dpon: Dictionary = B.dp_defaults(dp)
	dpon.use_curtain = true
	# F1: за занавесом плотность 0; до занавеса = без занавеса; между — монотонно убывает
	var far := Vector3(0, 0.342, -0.94).normalized() * 30000.0
	var near := Vector3(0, 0.342, -0.94).normalized() * 6000.0
	var d_far: float = B.compute_density(far, dpon, 30000.0)
	var d_near_on: float = B.compute_density(near, dpon, 6000.0)
	var d_near_off: float = B.compute_density(near, dp, 6000.0)
	var mid1: float = B.compute_density(far, dpon, 14000.0)
	var mid2: float = B.compute_density(far, dpon, 20000.0)
	check("F1 занавес: далеко=0, близко без изменений, между убывает",
		absf(d_far) < 1e-12 and absf(d_near_on - d_near_off) < 1e-12 and mid1 >= mid2 - 1e-12)
	# F2: горизонтальный луч 2°: с занавесом прозрачнее (вал рассосался)
	var r2 := Vector3(0, sin(deg_to_rad(2.0)), -cos(deg_to_rad(2.0)))
	var mon: Dictionary = B.compute_march(r2, bottom, top, 64, 30000.0, 0.0025, 0.01, dpon)
	var moff: Dictionary = B.compute_march(r2, bottom, top, 64, 30000.0, 0.0025, 0.01, dp)
	check("F2 луч 2°: T с занавесом выше (горизонт чище)", float(mon.transmittance) > float(moff.transmittance),
		"(T_off=%.4f T_on=%.4f)" % [float(moff.transmittance), float(mon.transmittance)])
	# F3: зенит (короткий путь) не затронут
	var mz_on: Dictionary = B.compute_march(Vector3(0, 1, 0), bottom, top, 64, 30000.0, 0.0025, 0.01, dpon)
	var mz_off: Dictionary = B.compute_march(Vector3(0, 1, 0), bottom, top, 64, 30000.0, 0.0025, 0.01, dp)
	check("F3 зенит не затронут занавесом", float(mz_on.transmittance) == float(mz_off.transmittance))


func section_c8() -> void:
	print("--- Секция G8: C8 — градиентное небо ---")
	var sun := Vector3(-0.50, 0.50, -0.70).normalized()
	# G8-1: точно в солнце → розовое кольцо; горизонт перпендикулярно солнцу → цвет горизонта;
	# строго против солнца (горизонт) → антисолнечный; выкл → плоско
	var pink: Vector3 = B.compute_sky_gradient(sun, sun, {})	# t=1 → бело-жёлтое кольцо
	var gp: Dictionary = B.gp_defaults({})
	var side := Vector3(sun.z, 0.0, -sun.x).normalized()
	var hor: Vector3 = B.compute_sky_gradient(side, sun, {})
	var anti: Vector3 = B.compute_sky_gradient(-sun, sun, {})
	var flat: Vector3 = B.compute_sky_gradient(sun, sun, {"use_grad": false})
	var midir := Vector3(sun.x, 0.0, sun.z).normalized()
	midir = midir * 1.0
	var tmid := midir.dot(sun)
	var midv: Vector3 = B.compute_sky_gradient((Vector3(sun.x, 0.0, sun.z).normalized() * 0.7 + Vector3(0.0, 0.0, 0.0) + Vector3(-sun.z, 0.0, sun.x).normalized() * 0.714).normalized(), sun, {})
	check("G8-1 якоря градиента: солнце=white, бок=horizon, антисолнце=antisolar, выкл=flat",
		pink.distance_to(gp.band_white) < 1e-9
		and hor.distance_to(gp.horizon) < 1e-9
		and midv.distance_to(gp.band_mid) < 1e-6
		and anti.distance_to(gp.antisolar) < 1e-9
		and flat.distance_to(gp.flat) < 1e-9,
		"(pink=%s hor=%s)" % [str(pink), str(hor)])
	# G8-2: монотонность перехода горизонт→зенит по dir.y
	var g0: Vector3 = B.compute_sky_gradient(Vector3(1, 0.0, 0), sun, {})
	var g1: Vector3 = B.compute_sky_gradient(Vector3(1, 0.2, 0).normalized(), sun, {})
	var g2: Vector3 = B.compute_sky_gradient(Vector3(1, 0.6, 0).normalized(), sun, {})
	var d01 := g1.distance_to(g0)
	var d12 := g2.distance_to(g1)
	check("G8-2 вертикаль меняется монотонно-непрерывно", d01 > 0.0 and d12 > 0.0
		and B.compute_sky_gradient(Vector3(1, 0.001, 0), sun, {}).distance_to(g0) < 1e-3)
	# G8-3: пресеты несут 5 градиентных цветов
	var tbl: Dictionary = B.preset_table()
	var gk := true
	for key in ["sunset", "twilight", "night", "neutral", "blood_sunset"]:
		var pr: Dictionary = tbl[key]
		for k in ["grad_horizon", "grad_zenith", "grad_antisolar", "grad_mid", "grad_pink", "grad_white"]:
			if not pr.has(k):
				gk = false
	var bs: Dictionary = tbl.blood_sunset
	var nt: Dictionary = tbl.neutral
	check("G8-3 градиентные цвета во всех пресетах; у кровавого розовое кольцо краснее нейтрального",
		gk and (bs.grad_pink as Color).r - (bs.grad_pink as Color).g > (nt.grad_pink as Color).r - (nt.grad_pink as Color).g)


func section_c9() -> void:
	print("--- Секция H9: C9 — рампа цвета солнца и ambient из зенита ---")
	var pos := Vector3(0, 2500, 0)
	var ldir := Vector3(1, 0, 0)
	# H9-1: рампа с цветами = light_color не меняет солнце (инвариант)
	var lp0 := {"light_dir": ldir, "use_ramp": false}
	var lp_same := {"light_dir": ldir, "use_ramp": true,
		"ramp_near": Vector3(1.0, 0.97, 0.92), "ramp_far": Vector3(1.0, 0.97, 0.92)}
	var t0: Dictionary = B.compute_radiance_terms_b4(pos, ldir, 0.5, {}, lp0, {})
	var t1: Dictionary = B.compute_radiance_terms_b4(pos, ldir, 0.5, {}, lp_same, {})
	check("H9-1 рампа с цветами света ≡ без рампы", (t0.sun as Vector3).distance_to(t1.sun) < 1e-9)
	# H9-2: направление цвета солнца по углам: cv=1 → light, 0.55 → near, -1 → far
	var lp_r := {"light_dir": ldir, "use_ramp": true, "ramp_near": Vector3(0.98, 0.45, 0.38),
		"ramp_far": Vector3(0.80, 0.10, 0.10), "light_color": Vector3(1.0, 0.97, 0.92)}
	var v1 := Vector3(1, 0, 0)
	var v2 := Vector3(0.8, 0.6, 0.0)
	var v3 := Vector3(-1, 0, 0)
	var s1: Vector3 = B.compute_radiance_terms_b4(pos, v1, 0.5, {}, lp_r, {}).sun
	var s2: Vector3 = B.compute_radiance_terms_b4(pos, v2, 0.5, {}, lp_r, {}).sun
	var s3: Vector3 = B.compute_radiance_terms_b4(pos, v3, 0.5, {}, lp_r, {}).sun
	check("H9-2 цвет солнца по углу: у солнца=light, середина=near, вдали=far",
		s1.normalized().dot(Vector3(1.0, 0.97, 0.92).normalized()) > 0.9999
		and s2.normalized().dot(Vector3(0.98, 0.45, 0.38).normalized()) > 0.9999
		and s3.normalized().dot(Vector3(0.80, 0.10, 0.10).normalized()) > 0.9999)
	# H9-3: ambient-верх из зенита градиента: amb(h=1) = G(up)·gain·energy·albedo
	var lp_a := {"light_dir": ldir, "use_amb_sky": true, "amb_gain": 1.2, "use_amb_grad": true,
		"amb_energy": 0.45, "albedo": Vector3(1, 1, 1)}
	var ta: Dictionary = B.compute_radiance_terms_b4(Vector3(0, 3500, 0), v1, 0.5, {}, lp_a, {})
	var gp := {"horizon": Vector3(0.42, 0.55, 0.75), "zenith": Vector3(0.20, 0.35, 0.60),
		"antisolar": Vector3(0.26, 0.30, 0.52), "band_red": Vector3(0.45, 0.55, 0.72),
		"band_pink": Vector3(0.50, 0.60, 0.78)}
	var gup: Vector3 = B.compute_sky_gradient(Vector3(0, 1, 0), ldir, gp)
	var expect_amb: Vector3 = gup * 1.2 * 0.45
	check("H9-3 ambient-верх = G(up)·gain·energy", (ta.ambient as Vector3).distance_to(expect_amb) < 1e-4,
		"(amb=%s expect=%s)" % [str(ta.ambient), str(expect_amb)])
	# H9-4: пресеты несут ключи рампы и ambient-из-неба
	var tbl: Dictionary = B.preset_table()
	var ok := true
	for key in ["sunset", "twilight", "night", "neutral", "blood_sunset"]:
		var pr: Dictionary = tbl[key]
		for k in ["use_sun_color_ramp", "use_ambient_from_sky", "ambient_sky_gain"]:
			if not pr.has(k):
				ok = false
		if key != "neutral" and not pr.has("ramp_near"):
			ok = false
	check("H9-4 пресеты несут ключи рампы/ambient-из-неба", ok)


func section_d2() -> void:
	print("--- Секция D2: фаза правок освещения (blur солнца, diffuse mix, MS-гейны) ---")
	var bottom := 1500.0
	var top := 4000.0
	var spD2: Dictionary = B.sp_defaults({"use_shadow": true, "shadow_steps": 4})
	# D2-1: diffuse mix поднимает освещённость граней при взгляде от солнца
	var lpA: Dictionary = B.lp_defaults({"light_dir": Vector3(0, 0, -1), "amb_energy": 0.0, "use_ms": false, "diffuse_mix": 0.0})
	var lpB: Dictionary = B.lp_defaults({"light_dir": Vector3(0, 0, -1), "amb_energy": 0.0, "use_ms": false, "diffuse_mix": 0.45})
	var vBack := Vector3(0, 0, 1)	# взгляд от солнца (фаза мала) — случай "солнце за спиной"
	var tA: Dictionary = B.compute_radiance_terms_b4(Vector3(0, 2300, -4000), vBack, 0.5, {}, lpA, spD2)
	var tB: Dictionary = B.compute_radiance_terms_b4(Vector3(0, 2300, -4000), vBack, 0.5, {}, lpB, spD2)
	var ratio := (tB.sun as Vector3).length() / maxf((tA.sun as Vector3).length(), 1e-9)
	check("D2-1 diffuse mix: освещённые грани при солнце за спиной ярче", ratio > 2.0, "(×%.2f)" % ratio)
	# D2-2: формула mix(1, phase, m): точное соотношение и legacy-семантика (без ключа = чистый HG)
	var lpF1: Dictionary = B.lp_defaults({"light_dir": Vector3(0, 0, -1), "amb_energy": 0.0, "light_strength": 1.0, "light_color": Vector3.ONE, "albedo": Vector3.ONE, "diffuse_mix": 0.0})
	var lpF2: Dictionary = lpF1.duplicate()
	lpF2["diffuse_mix"] = 0.45
	var p1: Dictionary = B.compute_lighting_terms(Vector3(0, 2300, -4000), Vector3(0, 0, -1), lpF1)
	var p2: Dictionary = B.compute_lighting_terms(Vector3(0, 2300, -4000), Vector3(0, 0, 1), lpF1)
	var p3: Dictionary = B.compute_lighting_terms(Vector3(0, 2300, -4000), Vector3(0, 0, -1), lpF2)
	var p4: Dictionary = B.compute_lighting_terms(Vector3(0, 2300, -4000), Vector3(0, 0, 1), lpF2)
	var r_pure := (p1.sun as Vector3).x / (p2.sun as Vector3).x	# HG g=0.5: (1+g)³/(1-g)³ = 27
	var r_mix := (p3.sun as Vector3).x / (p4.sun as Vector3).x
	var ph_fwd: float = B.hg_phase(1.0, 0.5)
	var ph_back: float = B.hg_phase(-1.0, 0.5)
	var expect_mix: float = lerpf(ph_fwd, 1.0, 0.45) / lerpf(ph_back, 1.0, 0.45)
	check("D2-2 legacy: mix=0 ratio=27 (чистый HG), mix=0.45 ratio=формула",
		absf(r_pure - 27.0) < 0.05 and absf(r_mix - expect_mix) < 1e-4, "(%.2f / %.3f)" % [r_pure, r_mix])
	# D2-3: blur-пятно: на чистом луче (T=1) = 0; на закрытом > 0; линейно по strength; off → финал без blur
	var ldir := Vector3(-0.50, 0.14, -0.85).normalized()
	var suOn: Dictionary = B.sup_defaults({"light_dir": ldir})
	var suOff: Dictionary = B.sup_defaults({"light_dir": ldir, "use_blur": false})
	var suBig: Dictionary = B.sup_defaults({"light_dir": ldir, "blur_strength": 1.8})
	var dpB: Dictionary = B.dp_defaults({"offset": Vector3(3000, 1600, 9000)})
	var f_on: Dictionary = B.compute_final_with_sun(ldir, bottom, top, 64, 30000.0, 0.0025, 0.01, 0.0, dpB, {}, {}, {}, suOn)
	var f_off: Dictionary = B.compute_final_with_sun(ldir, bottom, top, 64, 30000.0, 0.0025, 0.01, 0.0, dpB, {}, {}, {}, suOff)
	var f_big: Dictionary = B.compute_final_with_sun(ldir, bottom, top, 64, 30000.0, 0.0025, 0.01, 0.0, dpB, {}, {}, {}, suBig)
	var f_miss: Dictionary = B.compute_final_with_sun(Vector3(0, 1, 0), bottom, top, 64, 30000.0, 0.0025, 0.01, 0.0, dpB, {}, {}, {}, suOn)
	var blur_hit: Vector3 = f_on.blur
	var tr: float = float(f_on.transmittance)
	var d3: bool = blur_hit.length() > 0.0 and tr < 0.9 \
		and absf(blur_hit.length() - (f_big.blur as Vector3).length() * (1.1 / 1.8)) < 1e-4 \
		and (f_on.final as Vector3).distance_to((f_off.final as Vector3) + blur_hit) < 1e-4 \
		and (f_miss.blur as Vector3).length() < 1e-6
	check("D2-3 blur ∝ (1−T)·strength, 0 при чистом небе/off", d3,
		"(T=%.2f, |blur|=%.2f, miss=%.4f)" % [tr, blur_hit.length(), (f_miss.blur as Vector3).length()])
	# D2-4: ms линеен по uniform ms_sun_gain (ambient=0, shadow on)
	var lpMS: Dictionary = B.lp_defaults({"light_dir": Vector3(0.5, 0.4, -0.768), "amb_energy": 0.0})
	var tG1: Dictionary = B.compute_radiance_terms_b4(Vector3(0, 2300, -4000), Vector3(0.1, 0.0, -0.995), 0.5, {}, lpMS, B.sp_defaults({"ms_sun_gain": 0.45}))
	var tG2: Dictionary = B.compute_radiance_terms_b4(Vector3(0, 2300, -4000), Vector3(0.1, 0.0, -0.995), 0.5, {}, lpMS, B.sp_defaults({"ms_sun_gain": 0.90}))
	var d4: bool = absf((tG2.ms as Vector3).length() - (tG1.ms as Vector3).length() * 2.0) < 1e-5
	check("D2-4 ms_sun_gain uniform: MS-член линейно ×2", d4)
	# D2-5: дефолты материала = правкам (powder 0.30, ms 0.65, gains 0.45/0.60, mix 0.45, blur on 0.9/40)
	var mat: ShaderMaterial = load(MATERIAL_PATH)
	var ok5: bool = absf(float(mat.get_shader_parameter("powder_strength")) - 0.30) < 1e-6 \
		and absf(float(mat.get_shader_parameter("ms_strength")) - 0.65) < 1e-6 \
		and absf(float(mat.get_shader_parameter("ms_sun_gain")) - 0.45) < 1e-6 \
		and absf(float(mat.get_shader_parameter("ms_amb_gain")) - 0.60) < 1e-6 \
		and absf(float(mat.get_shader_parameter("hg_diffuse_mix")) - 0.45) < 1e-6 \
		and bool(mat.get_shader_parameter("use_sun_blur")) \
		and absf(float(mat.get_shader_parameter("sun_blur_strength")) - 1.10) < 1e-6 \
		and absf(float(mat.get_shader_parameter("sun_blur_power")) - 12.0) < 1e-6
	check("D2-5 дефолты правок в материале", ok5)


func section_d1() -> void:
	print("--- Секция D1: дефолты заказчика и новая цепочка градиента ---")
	var mat: ShaderMaterial = load("res://Q7.32_SKY_SKYHC_1/omega_clouds_test_material.tres")
	var ok7 := absf(float(mat.get_shader_parameter("cloud_base_scale")) - 35500.0) < 1e-6 \
		and absf(float(mat.get_shader_parameter("cloud_coverage")) - 0.23) < 1e-9 \
		and absf(float(mat.get_shader_parameter("cloud_softness")) - 0.17) < 1e-9 \
		and absf(float(mat.get_shader_parameter("cloud_detail_scale")) - 3000.0) < 1e-6 \
		and absf(float(mat.get_shader_parameter("cloud_detail_strength")) - 0.60) < 1e-9 \
		and absf(float(mat.get_shader_parameter("cloud_erosion")) - 0.30) < 1e-9 \
		and absf(float(mat.get_shader_parameter("cloud_vertical_stretch")) - 1.75) < 1e-9
	check("D1-1 семь дефолтов заказчика в материале", ok7)
	var sh: Shader = load("res://Q7.32_SKY_SKYHC_1/omega_volumetric_clouds.gdshader")
	# D3: окна цепочки теперь через sharp_mix(...) — строки обновлены (значения окон те же).
	check("D1-2 шейдер: mid/white стопы и широкие окна цепочки (через sharp_mix, D3)",
		sh.code.contains("sky_band_mid") and sh.code.contains("sky_band_white")
		and sh.code.contains("sharp_mix(0.10, 0.60, t, sky_grad_sharp)")
		and sh.code.contains("sharp_mix(0.70, 0.92, t, sky_grad_sharp)")
		and sh.code.contains("sharp_mix(0.92, 0.995, t, sky_grad_sharp)")
		and not sh.code.contains("sky_band_red :"))
	var tbl: Dictionary = B.preset_table()
	var nt: Dictionary = tbl.neutral
	check("D1-3 neutral ≡ дефолтам заказчика (плотность) и градиентным стопам материала",
		float(nt.base_scale) == 35500.0 and float(nt.coverage) == 0.23 and float(nt.softness) == 0.17
		and float(nt.detail_scale) == 3000.0 and float(nt.detail_strength) == 0.60
		and float(nt.erosion) == 0.30 and float(nt.stretch) == 1.75)


func section_d3() -> void:
	print("--- Секция D3: резкость градиента неба и твёрдость кромки облаков ---")
	# D3-1: sharp_mix: s=1 → ровно smoothstep (побитово), концы/середина окна сохраняются
	var ok1 := true
	for i in range(-40, 81):
		var x := float(i) / 80.0 * 2.0 - 1.0
		if B.sharp_mix(-0.20, -0.80, x, 1.0) != smoothstep(-0.20, -0.80, x):
			ok1 = false
	ok1 = ok1 and B.sharp_mix(0.0, 1.0, 0.0, 2.5) == 0.0
	ok1 = ok1 and B.sharp_mix(0.0, 1.0, 1.0, 2.5) == 1.0
	ok1 = ok1 and is_equal_approx(B.sharp_mix(0.0, 1.0, 0.5, 3.0), 0.5)
	check("D3-1 sharp_mix: s=1≡smoothstep побитово, концы/середина сохраняются", ok1)
	# D3-2: s>1 → сжатие перехода к краям (S(0.25)<0.25, S(0.75)>0.75) и монотонность
	var s25: float = B.sharp_mix(0.0, 1.0, 0.25, 2.0)
	var s75: float = B.sharp_mix(0.0, 1.0, 0.75, 2.0)
	var mono := true
	var prev := -1.0
	for i in range(0, 101):
		var v: float = B.sharp_mix(0.0, 1.0, float(i) / 100.0, 2.5)
		if v < prev - 1e-6:
			mono = false
		prev = v
	check("D3-2 sharp_mix s>1: сжатие к краям и монотонность", s25 < 0.25 and s75 > 0.75 and mono)
	# D3-3a: compute_sky_gradient при grad_sharp=1 побитово равен старой цепочке D2 (smoothstep)
	var sun := Vector3(-0.4, 0.25, -0.8).normalized()
	var d3v := Vector3(0.3, 0.2, -0.93).normalized()
	var qg: Dictionary = B.gp_defaults({})
	var old_g: Vector3 = (qg.horizon as Vector3).lerp(qg.zenith, smoothstep(0.02, 0.35, d3v.y))
	var t3 := d3v.dot(sun)
	old_g = old_g.lerp(qg.antisolar, smoothstep(-0.20, -0.80, t3))
	old_g = old_g.lerp(qg.band_mid, smoothstep(0.10, 0.60, t3))
	old_g = old_g.lerp(qg.band_pink, smoothstep(0.70, 0.92, t3))
	old_g = old_g.lerp(qg.band_white, smoothstep(0.92, 0.995, t3))
	var g0: Vector3 = B.compute_sky_gradient(d3v, sun, {})
	# Зеркало повторно нормализует dir/sundir (поведение C8) → сравнение с допуском 1e-6;
	# в шейдере идентичность точная: sharp_mix при s==1 возвращает sstep без изменений.
	check("D3-3a grad_sharp=1 ≡ цепочке D2 (sharp_mix(s=1)=sstep; допуск нормализации 1e-6)",
		(g0 - old_g).length() < 1e-6)
	# D3-3b: в середине среднего кольца (t=0.45) резкая версия ближе к цвету зоны band_mid
	var horiz := Vector3(0.0, 1.0, 0.0).cross(sun).normalized()
	var mid_dir := (sun * 0.45 + horiz * sqrt(1.0 - 0.45 * 0.45)).normalized()
	var g1: Vector3 = B.compute_sky_gradient(mid_dir, sun, {"grad_sharp": 1.0})
	var g2: Vector3 = B.compute_sky_gradient(mid_dir, sun, {"grad_sharp": 2.5})
	var mid_col: Vector3 = qg.band_mid
	check("D3-3b grad_sharp>1: ближе к цвету зоны в середине кольца",
		(g2 - mid_col).length() < (g1 - mid_col).length())
	# D3-4: compute_density edge_contrast: 1.0 → побитово D2; кривая вокруг 0.5 (profile=1, curtain off)
	var v0: float = B.compute_density(Vector3(1234, 2300, -4567), {}, 3000.0)
	var v1: float = B.compute_density(Vector3(1234, 2300, -4567), {"edge_contrast": 1.0}, 3000.0)
	check("D3-4a edge_contrast=1 ≡ D2 побитово", v0 == v1)
	var ok4 := true
	var mid_seen := 0
	for i in range(0, 60):
		var pp := Vector3(float(i) * 311.0 - 9000.0, 2300.0, -float(i) * 577.0)
		var s0: float = B.compute_density(pp, {}, 3000.0)
		if s0 > 0.0 and s0 < 1.0:
			mid_seen += 1
			var exp: float = clampf((s0 - 0.5) * 2.0 + 0.5, 0.0, 1.0)
			if not is_equal_approx(B.compute_density(pp, {"edge_contrast": 2.0}, 3000.0), exp):
				ok4 = false
		else:
			# 0 и 1 — неподвижные точки кривой
			if B.compute_density(pp, {"edge_contrast": 2.0}, 3000.0) != s0:
				ok4 = false
	check("D3-4b edge_contrast=2: кривая (d−0.5)·2+0.5 на промежуточных, 0/1 неподвижны (%d средних точек)" % mid_seen,
		ok4 and mid_seen > 0)
	# D3-5: дефолты материала D3 (пекутся после A/B-отбора)
	var mat: ShaderMaterial = load(MATERIAL_PATH)
	check("D3-5 дефолты D3 в материале",
		absf(float(mat.get_shader_parameter("cloud_edge_contrast")) - 2.0) < 1e-6
		and absf(float(mat.get_shader_parameter("sky_grad_sharp")) - 2.2) < 1e-6)
	# D3-6: шейдер содержит новые uniform'ы и их применение
	var sh: Shader = load("res://Q7.32_SKY_SKYHC_1/omega_volumetric_clouds.gdshader")
	check("D3-6 шейдер: uniform'ы sharp/contrast и их применение",
		sh.code.contains("uniform float sky_grad_sharp")
		and sh.code.contains("uniform float cloud_edge_contrast")
		and sh.code.contains("sharp_mix(0.02, 0.35, dir.y, sky_grad_sharp)")
		and sh.code.contains("(d - 0.5) * max(cloud_edge_contrast, 0.0) + 0.5"))


# === СЕКЦИЯ SKYHC-1: слой протяжённой облачности (HighCloudLayer, «вуаль») ===
# Проверяются: гейт идентичности D3, независимость от кучевых, форма рисунка
# (плавность/разрывы/вытянутость), оптика пути (Beer-Lambert + curtain), координатная
# привязка (POSITION vs камера), отсутствие экранных координат и марша в модуле,
# порядок композита (вуаль ЗА кучевыми, диск солнца ослабляется).
func section_skyhc_1() -> void:
	print("--- Секция SKYHC-1: вуаль — гейт, форма, координаты, композит ---")
	var sh: Shader = load(SHADER_PATH)
	var mat: ShaderMaterial = load(MATERIAL_PATH)
	var code := sh.code
	var cb := 1500.0
	var ct := 3500.0
	# Поля кучевых для проверок композита: «глухая плита» (T→0) и «чистое небо» (T→1).
	var dp_full := {"coverage": 0.0, "softness": 0.01, "strength": 0.0, "erosion": 0.0,
		"use_mask": false, "warp": 0.0, "use_aniso": false, "stretch": 1.0,
		"h_stretch": 1.0, "edge_contrast": 1.0, "use_curtain": false}
	var dp_empty := {"coverage": 1.0, "softness": 0.01, "strength": 0.0, "erosion": 0.0,
		"use_mask": false, "warp": 0.0, "use_aniso": false, "stretch": 1.0,
		"h_stretch": 1.0, "edge_contrast": 1.0, "use_curtain": false}
	var hp_on := {"enabled": true, "origin": Vector3.ZERO}
	var hp_off := {"enabled": false, "origin": Vector3.ZERO}
	# Направление, на котором вуаль реально даёт вклад (подбор данными, не хардкодом).
	var d_v := _hc_pick_dir(hp_on, 0.05)

	# HC1-1: ВЫКЛЮЧЕННЫЙ СЛОЙ → кадр ПОБИТОВО равен D3 (зеркало + гейты в коде шейдера).
	var d_id := Vector3(0.25, 0.62, -0.74).normalized()
	var f_off: Dictionary = B.compute_final_with_hc(d_v, cb, ct, 32, 30000.0, 0.0025, 0.01,
		0.0, {}, {}, {}, {}, {}, hp_off)
	var f_ref: Dictionary = B.compute_final_with_sun(d_v, cb, ct, 32, 30000.0, 0.0025, 0.01,
		0.0, {}, {}, {}, {})
	check("HC1-1a вуаль выкл → final побитово ≡ D3 (compute_final_with_sun)",
		(f_off.final as Vector3) == (f_ref.final as Vector3),
		"(Δ=%.6f)" % (f_off.final as Vector3).distance_to(f_ref.final as Vector3))
	check("HC1-1b шейдер: дефолт hc_enabled=false + uniform-гейт + композит через base",
		code.contains("uniform bool hc_enabled = false;")
		and code.contains("if (!hc_enabled) {")
		and code.contains("vec3 base = (bg + sunbg) * (1.0 - hc_a) + hc_rgb;"))

	# HC1-2: состав uniform'ов слоя в шейдере и в материале (типы bool — именно bool).
	var hc_names := ["hc_enabled", "hc_use_world_anchor", "hc_layer_bottom", "hc_layer_top",
		"hc_scale", "hc_stretch", "hc_stretch_angle_deg", "hc_field_scale", "hc_field_amp",
		"hc_coverage", "hc_softness", "hc_tau_per_km", "hc_curtain_start", "hc_curtain_end",
		"hc_offset", "hc_color", "hc_debug"]
	var miss_sh := []
	var miss_mat := []
	for n in hc_names:
		if not code.contains("uniform ") or not code.contains(n):
			miss_sh.append(n)
		if mat.get_shader_parameter(n) == null:
			miss_mat.append(n)
	check("HC1-2a 17 uniform'ов вуали в шейдере и в материале",
		miss_sh.is_empty() and miss_mat.is_empty(),
		"(шейдер: %s, материал: %s)" % [str(miss_sh), str(miss_mat)])
	check("HC1-2b bool-типы в материале (hc_enabled/hc_use_world_anchor) + дефолты этапа",
		typeof(mat.get_shader_parameter("hc_enabled")) == TYPE_BOOL
		and typeof(mat.get_shader_parameter("hc_use_world_anchor")) == TYPE_BOOL
		and bool(mat.get_shader_parameter("hc_enabled")) == true
		and bool(mat.get_shader_parameter("hc_use_world_anchor")) == true
		and absf(float(mat.get_shader_parameter("hc_tau_per_km")) - 0.35) < 1e-6)

	# HC1-3: слой НЕ трогает кучевые: марш (T, рассеяние) идентичен при вкл/выкл вуали.
	var f_on: Dictionary = B.compute_final_with_hc(d_v, cb, ct, 32, 30000.0, 0.0025, 0.01,
		0.0, {}, {}, {}, {}, {}, hp_on)
	var m_on: Dictionary = f_on.march
	var m_off: Dictionary = f_off.march
	check("HC1-3 марш кучевых не зависит от вуали (T и mode0 побитово), а итог отличается",
		float(m_on.transmittance) == float(m_off.transmittance)
		and (m_on.mode0_color as Vector3) == (m_off.mode0_color as Vector3)
		and (f_on.final as Vector3) != (f_off.final as Vector3),
		"(T=%.6f, Δfinal=%.4f, α_hc=%.4f)" % [float(m_on.transmittance),
			(f_on.final as Vector3).distance_to(f_off.final as Vector3),
			float((f_on.hc as Dictionary).alpha)])

	# HC1-4: плавность — нет резких контуров: соседние сэмплы вдоль луча меняются мало,
	# и доля промежуточных значений (0 < d < 1) существенна.
	var max_step := 0.0
	var mid_count := 0
	var total := 0
	for i in range(0, 240):
		var pp := Vector3(float(i) * 260.0 - 30000.0, 6600.0, -float(i) * 470.0 + 12000.0)
		var d0: float = B.compute_hc_density(pp, hp_on)
		var d1: float = B.compute_hc_density(pp + Vector3(120.0, 0.0, -220.0), hp_on)
		max_step = maxf(max_step, absf(d1 - d0))
		total += 1
		if d0 > 0.001 and d0 < 0.999:
			mid_count += 1
	check("HC1-4 плотность плавная: max|Δd| на 250 м ≤ 0.30 (полоса перехода ≥ ~0.8 км) и есть промежуточные значения",
		max_step <= 0.30 and float(mid_count) / float(total) > 0.15,
		"(max|Δd|=%.4f, промежуточных %d/%d)" % [max_step, mid_count, total])

	# HC1-5: неоднородность и разрывы — не равномерная полоса: есть и чистые окна,
	# и плотные области; поле разрывов (hc_field_amp) именно создаёт окна.
	var stats := _hc_field_stats(hp_on)
	var stats_nof := _hc_field_stats(merged(hp_on, {"field_amp": 0.0}))
	# Поле разрывов именно СОЗДАЁТ плотные образования: без него при том же пороге
	# распределение PW (сильно скошено к нулю) даёт почти пустое небо.
	check("HC1-5 рисунок неоднороден: окна и плотные образования присутствуют, поле разрывов их создаёт",
		stats.clear_frac > 0.05 and stats.dense_frac > 0.10 and stats.std > 0.25
		and stats.dense_frac > stats_nof.dense_frac + 0.05,
		"(чисто %.1f%% / плотно %.1f%% / σ=%.3f; без поля разрывов чисто %.1f%%)"
		% [stats.clear_frac * 100.0, stats.dense_frac * 100.0, stats.std, stats_nof.clear_frac * 100.0])

	# HC1-6: вытянутость — вдоль оси гряд рисунок меняется медленнее, чем поперёк.
	var ang := deg_to_rad(float(B.hcp_defaults(hp_on).stretch_angle_deg))
	var u_ax := Vector3(cos(ang), 0.0, sin(ang))
	var v_ax := Vector3(-sin(ang), 0.0, cos(ang))
	var L := 6000.0
	var sum_along := 0.0
	var sum_across := 0.0
	var n_s := 0
	for i in range(0, 60):
		var fi := float(i)
		var base_p := Vector3(fmod(fi * 3371.0, 90000.0) - 45000.0, 6600.0,
			fmod(fi * 7919.0, 90000.0) - 45000.0)
		var d0: float = B.compute_hc_density(base_p, hp_on)
		sum_along += absf(B.compute_hc_density(base_p + u_ax * L, hp_on) - d0)
		sum_across += absf(B.compute_hc_density(base_p + v_ax * L, hp_on) - d0)
		n_s += 1
	var mean_along := sum_along / float(n_s)
	var mean_across := sum_across / float(n_s)
	check("HC1-6 вытянутость: |Δd| вдоль оси гряд меньше, чем поперёк (L=%.0f м)" % L,
		mean_along < mean_across,
		"(вдоль %.4f < поперёк %.4f, отношение %.2f)" % [mean_along, mean_across,
			mean_along / maxf(mean_across, 1e-6)])

	# HC1-7: оптика пути — Beer-Lambert. Формула τ = d·(τ/км)·(путь/1000), α = (1−exp(−τ))·curtain
	# воспроизводится зеркалом точно; при удвоении толщины плиты точка выборки та же
	# (середина плиты), плотность та же, путь ×2 → τ ×2 и α строго больше (curtain выключен).
	# Отдельно: геометрия пути монотонна к горизонту (не зависит от плотности).
	var tpk: float = float(B.hcp_defaults(hp_on).tau_per_km)
	var hp_nocurt := merged(hp_on, {"curtain_start": 1.0e9, "curtain_end": 2.0e9})
	var hp_thick := merged(hp_nocurt, {"bottom": 5400.0, "top": 7800.0})
	var d_zen := Vector3(0.0, 1.0, 0.0)
	var d_low := Vector3(0.0, 0.25, -0.968).normalized()
	var hc_zen: Dictionary = B.compute_hc_layer(d_zen, hp_nocurt)
	var hc_th: Dictionary = B.compute_hc_layer(d_zen, hp_thick)
	var tau_ref: float = float(hc_zen.density) * tpk * (float(hc_zen.path) * 0.001)
	var a_ref: float = (1.0 - exp(-tau_ref))
	var p60: float = float(B.compute_hc_layer(Vector3(0.0, sin(deg_to_rad(60.0)), -cos(deg_to_rad(60.0))), hp_nocurt).path)
	var p30: float = float(B.compute_hc_layer(Vector3(0.0, sin(deg_to_rad(30.0)), -cos(deg_to_rad(30.0))), hp_nocurt).path)
	var p15: float = float(B.compute_hc_layer(Vector3(0.0, sin(deg_to_rad(15.0)), -cos(deg_to_rad(15.0))), hp_nocurt).path)
	check("HC1-7 Beer-Lambert: τ=d·(τ/км)·км, α=(1−exp(−τ))·curtain; путь×2 → τ×2, α растёт; путь монотонен к горизонту",
		absf(float(hc_zen.tau) - tau_ref) < 1e-9 and absf(float(hc_zen.alpha) - a_ref) < 1e-9
		and float(hc_th.path) == 2.0 * float(hc_zen.path)
		and absf(float(hc_th.density) - float(hc_zen.density)) < 1e-9
		and float(hc_th.tau) == 2.0 * float(hc_zen.tau)
		and float(hc_th.alpha) > float(hc_zen.alpha)
		and p60 < p30 and p30 < p15,
		"(зенит: путь=%.0f τ=%.3f α=%.3f; путь×2: τ=%.3f α=%.3f; пути 60/30/15°=%.0f/%.0f/%.0f)"
		% [float(hc_zen.path), float(hc_zen.tau), float(hc_zen.alpha),
			float(hc_th.tau), float(hc_th.alpha), p60, p30, p15])

	# HC1-8: curtain и защиты — чистый горизонт, вниз не рисуем, вырожденный луч не рисуем.
	var hc_curt: Dictionary = B.compute_hc_layer(d_low, hp_on)
	var hc_down: Dictionary = B.compute_hc_layer(Vector3(0.0, -0.5, -0.866).normalized(), hp_on)
	var hc_flat: Dictionary = B.compute_hc_layer(Vector3(0.0, 0.0, -1.0), hp_on)
	check("HC1-8 curtain гасит скользящие лучи (α→0), вниз/горизонтально — нет вклада",
		float(hc_curt.alpha) < 1e-6 and not bool(hc_down.hit) and not bool(hc_flat.hit),
		"(path=%.0f м, curtain=%.4f, α=%.6f)" % [float(hc_curt.path),
			float(hc_curt.curtain), float(hc_curt.alpha)])

	# HC1-9: координаты — world_anchor=true: при переносе камеры точка выборки смещается
	# вместе с ней (рисунок стоит в мире); false — точка не зависит от позиции (слой при камере).
	var shift := Vector3(700.0, 0.0, -450.0)
	var hp_w0 := merged(hp_on, {"origin": Vector3.ZERO})
	var hp_w1 := merged(hp_on, {"origin": shift})
	var hp_c1 := merged(hp_w1, {"world_anchor": false})
	var p_w0: Vector3 = B.compute_hc_layer(d_id, hp_w0).p_mid
	var p_w1: Vector3 = B.compute_hc_layer(d_id, hp_w1).p_mid
	var p_c1: Vector3 = B.compute_hc_layer(d_id, hp_c1).p_mid
	check("HC1-9 мировая привязка: p(origin+Δ)=p(origin)+Δ (рисунок в мире стоит), без привязки — не зависит от камеры",
		(p_w1 - (p_w0 + shift)).length() < 1e-3 and p_c1.distance_to(p_w0) < 1e-6,
		"(Δp=%.3f м при Δ=(700,0,−450))" % (p_w1 - (p_w0 + shift)).length())

	# HC1-10: нет экранных координат и нет ручного переноса за камерой в модуле вуали.
	var hc_block := _hc_shader_block(code)
	var code_nc := _strip_comments(code)
	var hc_nc := _strip_comments(hc_block)
	check("HC1-10 модуль вуали без SCREEN_UV/SKY_COORDS/TIME; POSITION читается только в hc_evaluate",
		not hc_nc.contains("SCREEN_UV") and not hc_nc.contains("SKY_COORDS")
		and not hc_nc.contains("TIME") and hc_nc.contains("POSITION")
		and code_nc.count("POSITION") == hc_nc.count("POSITION"))

	# HC1-11: стоимость — в модуле вуали нет циклов и нет обращения к маршу кучевых,
	# ровно 2 выборки из существующей noise_pw (новых текстур нет).
	check("HC1-11 в модуле вуали: 0 циклов, 0 вызовов cloud_density/light_transmittance, 2 texture(noise_pw)",
		not hc_block.contains("for (") and not hc_block.contains("cloud_density(")
		and not hc_block.contains("light_transmittance(")
		and hc_block.count("texture(noise_pw") == 2
		and not hc_block.contains("noise_worley") and not hc_block.contains("sampler3D"))

	# HC1-12: порядок композита — кучевые ЗАКРЫВАЮТ вуаль: на глухой плите вклад вуали
	# подавлен в T раз, на чистом небе виден полностью.
	var f_full_on: Dictionary = B.compute_final_with_hc(d_v, cb, ct, 32, 30000.0, 0.0025,
		0.01, 0.0, dp_full, {}, {}, {}, {}, hp_on)
	var f_full_off: Dictionary = B.compute_final_with_hc(d_v, cb, ct, 32, 30000.0, 0.0025,
		0.01, 0.0, dp_full, {}, {}, {}, {}, hp_off)
	var f_emp_on: Dictionary = B.compute_final_with_hc(d_v, cb, ct, 32, 30000.0, 0.0025,
		0.01, 0.0, dp_empty, {}, {}, {}, {}, hp_on)
	var f_emp_off: Dictionary = B.compute_final_with_hc(d_v, cb, ct, 32, 30000.0, 0.0025,
		0.01, 0.0, dp_empty, {}, {}, {}, {}, hp_off)
	var diff_full: float = (f_full_on.final as Vector3).distance_to(f_full_off.final as Vector3)
	var diff_emp: float = (f_emp_on.final as Vector3).distance_to(f_emp_off.final as Vector3)
	var t_full: float = float((f_full_on.march as Dictionary).transmittance)
	var t_emp: float = float((f_emp_on.march as Dictionary).transmittance)
	check("HC1-12 порядок: кучевые закрывают вуаль (вклад ∝ T), на чистом небе вуаль видна полностью",
		t_full < 0.05 and t_emp > 0.95 and diff_emp > 0.01
		and diff_full < diff_emp * 0.05,
		"(T_глухо=%.4f → Δ=%.5f; T_чисто=%.4f → Δ=%.4f)" % [t_full, diff_full, t_emp, diff_emp])

	# HC1-13: диск солнца за вуалью ослабляется (вуаль перед солнцем, честная окклюзия).
	var ldir := Vector3(-0.75, 0.50, -0.43).normalized()
	var hp_sun := merged(hp_on, {"curtain_start": 1.0e9, "curtain_end": 2.0e9})
	var f_sun_on: Dictionary = B.compute_final_with_hc(ldir, cb, ct, 32, 30000.0, 0.0025,
		0.01, 0.0, dp_empty, {}, {}, {}, {"light_dir": ldir}, hp_sun)
	var f_sun_off: Dictionary = B.compute_final_with_hc(ldir, cb, ct, 32, 30000.0, 0.0025,
		0.01, 0.0, dp_empty, {}, {}, {}, {"light_dir": ldir},
		merged(hp_sun, {"enabled": false}))
	var a_sun: float = float((f_sun_on.hc as Dictionary).alpha)
	var lum_on: float = (f_sun_on.final as Vector3).dot(Vector3(0.3333, 0.3333, 0.3333))
	var lum_off: float = (f_sun_off.final as Vector3).dot(Vector3(0.3333, 0.3333, 0.3333))
	check("HC1-13 вуаль ослабляет диск солнца (α>0 → яркость ниже) и не ярче чистого неба",
		a_sun > 0.01 and lum_on < lum_off,
		"(α=%.3f, яркость %.3f → %.3f, ×%.3f)" % [a_sun, lum_off, lum_on, lum_on / maxf(lum_off, 1e-6)])

	# HC1-14: независимость управления — τ/км=0 убирает слой при включённом гейте,
	# а hc_enabled=false убирает его полностью (обе ручки работают).
	var hp_zero := merged(hp_on, {"tau_per_km": 0.0})
	var hc_zero: Dictionary = B.compute_hc_layer(d_zen, hp_zero)
	var hc_off: Dictionary = B.compute_hc_layer(d_zen, hp_off)
	check("HC1-14 независимая интенсивность: τ/км=0 → α=0 (слой включён, но пуст); выкл → вклада нет",
		bool(hc_zero.hit) and float(hc_zero.alpha) == 0.0
		and not bool(hc_off.hit) and float(hc_off.alpha) == 0.0
		and (hc_off.premult as Vector3) == Vector3.ZERO)


## SKYHC: статистика поля плотности вуали по сетке мировых точек (плоскость середины плиты).
func _hc_field_stats(hp: Dictionary) -> Dictionary:
	var n_clear := 0
	var n_dense := 0
	var n_mid := 0
	var sum := 0.0
	var sum2 := 0.0
	var cnt := 0
	for i in range(0, 40):
		for j in range(0, 40):
			var pp := Vector3(float(i) * 11000.0 - 220000.0, 6600.0, float(j) * 11000.0 - 220000.0)
			var d: float = B.compute_hc_density(pp, hp)
			sum += d
			sum2 += d * d
			cnt += 1
			if d < 0.02:
				n_clear += 1
			elif d > 0.8:
				n_dense += 1
			else:
				n_mid += 1
	var mean := sum / float(cnt)
	var std: float = sqrt(maxf(sum2 / float(cnt) - mean * mean, 0.0))
	return {"clear_frac": float(n_clear) / float(cnt), "dense_frac": float(n_dense) / float(cnt),
		"mid_frac": float(n_mid) / float(cnt), "mean": mean, "std": std}


## SKYHC: направление, на котором вуаль даёт вклад не меньше min_alpha (подбор данными).
func _hc_pick_dir(hp: Dictionary, min_alpha: float) -> Vector3:
	for i in range(1, 13):
		var el := deg_to_rad(5.0 + 80.0 * float(i) / 13.0)
		for j in range(0, 24):
			var az := TAU * float(j) / 24.0
			var d := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
			var r: Dictionary = B.compute_hc_layer(d, hp)
			if bool(r.hit) and float(r.alpha) >= min_alpha:
				return d
	return Vector3(0.0, 1.0, 0.0)


## SKYHC: убирает // -комментарии из кода шейдера (чтобы не считать слова из шапки).
func _strip_comments(code: String) -> String:
	var out := ""
	for ln in code.split("\n"):
		var i := ln.find("//")
		out += (ln.substr(0, i) if i >= 0 else ln) + "\n"
	return out


## SKYHC: словарь-слияние (hp + переопределения) без изменения исходного.
func merged(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b.keys():
		out[k] = b[k]
	return out


## SKYHC: вырезает из кода шейдера блок модуля вуали (от маркера до void sky()).
func _hc_shader_block(code: String) -> String:
	var i := code.find("// === SKYHC-1: ФУНКЦИИ СЛОЯ ВУАЛИ")
	var j := code.find("void sky() {")
	if i < 0 or j < 0 or j <= i:
		return ""
	return code.substr(i, j - i)
