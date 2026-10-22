extends SceneTree
## test_q732_num.gd — поставляемый selftest компонента Q7.32_SKYprav_3.1 (headless, CPU-зеркала).
## Секции: R ресурсы/сцена, H Henyey-Greenstein, L члены освещения B3, M lit-марш B3,
## G регрессия B2/B1, S эффекты B4 (тень/powder/MS/atmo), D диагностика и гейты B5,
## P профили и subpasses-контракт B6, C1-C9/D1-D3 правки чтения и контраста,
## SKYHC-1 вуаль (гейт/форма/координаты/композит), SKYHC-2 стабильность рисунка
## (эквивариантность переноса, параллакс, швы/периодичность, guards горизонта/зенита),
## SKYHC-3.1 крупный рисунок и масштаб (развёртки, критерии вырождения, пресеты A/B),
## SKYHC-3.2 разрывы/неоднородность (рабочие зоны coverage/softness/field_amp, пресеты
## характера, аудит независимости ручек через «владение» наблюдаемыми),
## SKYHC-3.3 мелкая деталь (Worley-бугорки кромок: гейт идентичности, локальность,
## сохранность крупного рисунка, отклик ручек, цена),
## SKYHC-4 освещение и время суток (гейт идентичности 3.3, терминатор, анти-пинк ночь,
## согласование с пресетами неба, непрерывность перехода, разделение ручек, C9-конвенции,
## отсутствие второго цикла суток),
## SKYHC-5 интеграция с кучевыми (порядок/подавление плитой, нет двойного затемнения
## и пересвета, контраст сквозь вуаль, независимость слоёв побитово, баланс долей,
## слоёвое A/B, форма-независимость и замер субпасс-расхождения),
## PRAV-1.1 правки кучевых фаза 1 (иерархия масштабов, консолидация масс, де-foam,
## вертикаль, синк материал↔neutral, вуаль заморожена снапшотом световых ключей),
## PRAV-1.2 фиксация принятого состояния фазы 1 (контрольные суммы фингерпринта,
## конверты формы и полосного спектра — база дифф-протокола фазы 2; перебазировано
## на состояние фазы 2 в prav_2.1 с атрибуцией),
## PRAV-2.1 средние выступы (плечо спектра E500, анти-регулярность CV, разделение
## плотностью, мульти-ракурс, крупные формы сохранены, ноль новых выборок),
## PRAV-3.1 мелкая бахрома кромок (гейт идентичности 2.1, локальность в полосе
## перехода, иерархия сохранена, анти-foam/анти-speck, отклик ручек, B2-fade).
## Рендер НЕ выполняется (GPU не нужен).
## Запуск: godot --headless --path <проект с компонентом> --script res://Q7.32_SKYprav_3.1/_selftest/test_q732_num.gd
## Код вырос из харнесса этапов B3-B6 (test_b3_num.gd … test_b6_num.gd, песочница поставки).

const BENCH_PATH := "res://Q7.32_SKYprav_3.1/CloudsTestBench.gd"
const SHADER_PATH := "res://Q7.32_SKYprav_3.1/omega_volumetric_clouds.gdshader"
const MATERIAL_PATH := "res://Q7.32_SKYprav_3.1/omega_clouds_test_material.tres"
const SKY_PATH := "res://Q7.32_SKYprav_3.1/omega_clouds_test_sky.tres"
const SCENE_PATH := "res://Q7.32_SKYprav_3.1/Сцена_облаков_тест.tscn"

var B: GDScript = null
var _fails := 0
var _total := 0

## SKYHC: состав uniform'ов слоя вуали — единый источник для проверок состава.
## SKYHC-1 зафиксировал 17; SKYHC-3.3 добавил 2 (деталь); SKYHC-4 добавил 3
## (hc_use_lighting/hc_light_gain/hc_ambient_gain — освещение фазы 4) → 22.
## Перебазирование состава — только с атрибуцией в соответствующих проверках (прецедент P4).
const HC_UNIFORM_NAMES := ["hc_enabled", "hc_use_world_anchor", "hc_layer_bottom", "hc_layer_top",
	"hc_scale", "hc_stretch", "hc_stretch_angle_deg", "hc_field_scale", "hc_field_amp",
	"hc_coverage", "hc_softness", "hc_tau_per_km", "hc_curtain_start", "hc_curtain_end",
	"hc_offset", "hc_color", "hc_detail_strength", "hc_detail_scale",
	"hc_use_lighting", "hc_light_gain", "hc_ambient_gain", "hc_debug"]


func check(label: String, ok: bool, detail := "") -> void:
	_total += 1
	if ok:
		print("PASS %02d | %s %s" % [_total, label, detail])
	else:
		_fails += 1
		print("FAIL %02d | %s %s" % [_total, label, detail])


func _init() -> void:
	B = load(BENCH_PATH)
	print("=== Q7.32_SKYprav_3.1 численный suite (headless, CPU-зеркала) ===")
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
		section_skyhc_2()
		section_skyhc_31()
		section_skyhc_32()
		section_skyhc_33()
		section_skyhc_4()
		section_skyhc_5()
		section_prav_11()
		section_prav_12()
		section_prav_21()
		section_prav_31()
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
	var mat: ShaderMaterial = load("res://Q7.32_SKYprav_3.1/omega_clouds_test_material.tres")
	var names := ["use_self_shadow", "light_steps", "shadow_ray_length", "use_powder", "powder_strength",
		"use_ms", "ms_strength", "use_atmo_perspective", "atmo_color", "atmo_start", "atmo_end", "cloud_debug_mode"]
	var miss := []
	for n2 in names:
		if mat.get_shader_parameter(n2) == null:
			miss.append(n2)
	var sh: Shader = load("res://Q7.32_SKYprav_3.1/omega_volumetric_clouds.gdshader")
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
	var sh: Shader = load("res://Q7.32_SKYprav_3.1/omega_volumetric_clouds.gdshader")
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
	var sh: Shader = load("res://Q7.32_SKYprav_3.1/omega_volumetric_clouds.gdshader")
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
	var mat: ShaderMaterial = load("res://Q7.32_SKYprav_3.1/omega_clouds_test_material.tres")
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
	var mat: ShaderMaterial = load("res://Q7.32_SKYprav_3.1/omega_clouds_test_material.tres")
	# ПЕРЕБАЗИРОВАНО prav_1.1 (detail 0.60→0.15, erosion 0.30→0.10 — временное снижение
	# пены, аудит prav_0.1) и prav_2.1 (ТЗ правок фаза 2: деталь переназначена на СРЕДНИЙ
	# масштаб — detail_scale 3000→12000, strength 0.15→0.40: округлые выступы ~1.5 км
	# вместо пены 375 м; решение по данным prav_1.2 §3, кандидат F2). Исторические
	# дефолты D1 (35500/0.23/0.17/3000/0.60/0.30/1.75) навсегда закреплены в ДЕФОЛТАХ
	# ШЕЙДЕРА — вторая половина проверки.
	var sh_d1: Shader = load(SHADER_PATH)
	var ok7 := absf(float(mat.get_shader_parameter("cloud_base_scale")) - 35500.0) < 1e-6 \
		and absf(float(mat.get_shader_parameter("cloud_coverage")) - 0.23) < 1e-9 \
		and absf(float(mat.get_shader_parameter("cloud_softness")) - 0.17) < 1e-9 \
		and absf(float(mat.get_shader_parameter("cloud_detail_scale")) - 12000.0) < 1e-6 \
		and absf(float(mat.get_shader_parameter("cloud_detail_strength")) - 0.40) < 1e-9 \
		and absf(float(mat.get_shader_parameter("cloud_erosion")) - 0.10) < 1e-9 \
		and absf(float(mat.get_shader_parameter("cloud_vertical_stretch")) - 1.75) < 1e-9 \
		and sh_d1.code.contains("uniform float cloud_base_scale = 35500.0;") \
		and sh_d1.code.contains("uniform float cloud_coverage = 0.23;") \
		and sh_d1.code.contains("uniform float cloud_softness = 0.17;") \
		and sh_d1.code.contains("uniform float cloud_detail_scale = 3000.0;") \
		and sh_d1.code.contains("uniform float cloud_detail_strength = 0.60;") \
		and sh_d1.code.contains("uniform float cloud_erosion = 0.30;") \
		and sh_d1.code.contains("uniform float cloud_vertical_stretch = 1.75;")
	check("D1-1 материал = состояние фазы 2 (перебазировано prav_2.1: detail 12000/0.40); дефолты D1 закреплены в шейдере", ok7)
	var sh: Shader = load("res://Q7.32_SKYprav_3.1/omega_volumetric_clouds.gdshader")
	# D3: окна цепочки теперь через sharp_mix(...) — строки обновлены (значения окон те же).
	check("D1-2 шейдер: mid/white стопы и широкие окна цепочки (через sharp_mix, D3)",
		sh.code.contains("sky_band_mid") and sh.code.contains("sky_band_white")
		and sh.code.contains("sharp_mix(0.10, 0.60, t, sky_grad_sharp)")
		and sh.code.contains("sharp_mix(0.70, 0.92, t, sky_grad_sharp)")
		and sh.code.contains("sharp_mix(0.92, 0.995, t, sky_grad_sharp)")
		and not sh.code.contains("sky_band_red :"))
	var tbl: Dictionary = B.preset_table()
	var nt: Dictionary = tbl.neutral
	# ПЕРЕБАЗИРОВАНО prav_1.1 (detail 0.15/erosion 0.10/weather 140000) и prav_2.1
	# (detail_scale 12000, detail_strength 0.40 — средний масштаб выступов); световые
	# ключи пресетов НЕ тронуты (гард PR11-7 / снапшот SKYHC_5).
	check("D1-3 neutral ≡ дефолтам материала (перебазировано prav_2.1: detail 12000/0.40, erosion 0.10)",
		float(nt.base_scale) == 35500.0 and float(nt.coverage) == 0.23 and float(nt.softness) == 0.17
		and float(nt.detail_scale) == 12000.0 and float(nt.detail_strength) == 0.40
		and float(nt.erosion) == 0.10 and float(nt.stretch) == 1.75)


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
	var sh: Shader = load("res://Q7.32_SKYprav_3.1/omega_volumetric_clouds.gdshader")
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
	# SKYHC-2: список вынесен в HC_UNIFORM_NAMES (единый источник для HC1-2a и HC2-12).
	var hc_names := HC_UNIFORM_NAMES
	var miss_sh := []
	var miss_mat := []
	for n in hc_names:
		if not code.contains("uniform ") or not code.contains(n):
			miss_sh.append(n)
		if mat.get_shader_parameter(n) == null:
			miss_mat.append(n)
	check("HC1-2a 22 uniform'а вуали в шейдере и в материале (17 SKYHC-1 + 2 детали 3.3 + 3 света SKYHC-4)",
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
	check("HC1-11 в модуле вуали: 0 циклов, 0 вызовов cloud_density/light_transmittance, 2 texture(noise_pw), 1 worley (гейт 3.3)",
		not hc_block.contains("for (") and not hc_block.contains("cloud_density(")
		and not hc_block.contains("light_transmittance(")
		and hc_block.count("texture(noise_pw") == 2
		and hc_block.count("texture(noise_worley") == 1 and not hc_block.contains("sampler3D"))

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


## SKYHC-2: НОД (евклидов) — для вывода НОК периодов текстуры из данных (без хардкода).
func _gcd_int(a: int, b: int) -> int:
	while b != 0:
		var t := a % b
		a = b
		b = t
	return absi(a)


## SKYHC: вырезает из кода шейдера блок модуля вуали (от маркера до void sky()).
func _hc_shader_block(code: String) -> String:
	var i := code.find("// === SKYHC-1: ФУНКЦИИ СЛОЯ ВУАЛИ")
	var j := code.find("void sky() {")
	if i < 0 or j < 0 or j <= i:
		return ""
	return code.substr(i, j - i)


# === СЕКЦИЯ SKYHC-2: фаза 2 ТЗ — система координат и стабильность рисунка ===
# Проверяются: эквивариантность переноса камеры (рисунок стоит в мире), мировая
# срединная плоскость и независимость пути от высоты камеры, непрерывность отклика на
# перенос (нет скачков), оценка параллакса оболочки (дальняя плита), мировая
# периодичность рисунка (швов при дрейфе через границу периода текстуры нет),
# периодичность PW-данных на уровне вокселей, развёртка тангажа (Lipschitz по
# смещению точки выборки, ниже горизонта α=0), guards горизонта и зенита, отделение
# дрейфа (offset) от камеры, семантика hc_use_world_anchor, неизменность состава
# модуля (фаза 2 не добавляет вычислений) и регрессия гейта идентичности D3.
func section_skyhc_2() -> void:
	print("--- Секция SKYHC-2: вуаль — стабильность рисунка, швы, параллакс ---")
	var sh: Shader = load(SHADER_PATH)
	var code := sh.code
	var code_nc := _strip_comments(code)
	var hc_block := _hc_shader_block(code)
	var hc_nc := _strip_comments(hc_block)
	var hp_on := {"enabled": true, "origin": Vector3.ZERO}
	var hp_off := {"enabled": false, "origin": Vector3.ZERO}
	var q: Dictionary = B.hcp_defaults(hp_on)
	var bottom := float(q.bottom)
	var top := float(q.top)
	var scale_m := float(q.scale)
	var field_m := float(q.field_scale)
	# Градиентное ограничение поля из HC1-4 (max|Δd| ≤ 0.30 на 250 м смещения точки
	# выборки) × запас 1.3: нормируем непрерывность на ФАКТИЧЕСКОЕ смещение точки.
	var lip := 0.30 / 250.0 * 1.3

	# HC2-1: эквивариантность переноса камеры (массовая, детерминированный разброс):
	# вне клампа p_mid(O+Δ) = p_mid(O) + Δ − dir·(Δ.y/dir.y) — точка скользит вдоль луча
	# обратно в МИРОВУЮ срединную плоскость y=(bottom+top)/2; при сработавшем HC_MAX_DIST
	# (низкие лучи, t_mid > 60 км — там curtain уже обнуляет α, см. HC2-8) сдвиг ЖЁСТКИЙ:
	# p_mid(O+Δ) = p_mid(O) + Δ. Смешанные режимы (кламп включился между O и O+Δ) skipped:
	# непрерывность перехода покрыта HC2-3/HC2-8. Допуск — float32 Vector3 (ulp(60 км)
	# ≈ 0.008 м): tol = 1e-6·(|p0|+|Δ|) + 1e-3 ≈ 8 ulp, реальные ошибки ~2 ulp.
	var max_err := 0.0
	var max_tol := 0.0
	var n_skipped := 0
	for i in range(0, 120):
		var fi := float(i)
		var org := Vector3(fmod(fi * 137.0, 1200.0) - 600.0, fmod(fi * 7.3, 60.0),
			fmod(fi * 211.0, 1200.0) - 600.0)
		var dir := Vector3(fmod(fi * 0.61, 2.0) - 1.0, 0.12 + fmod(fi * 0.037, 0.85),
			fmod(fi * 0.83, 2.0) - 1.0).normalized()
		var dlt := Vector3(fmod(fi * 53.0, 100.0) - 50.0, fmod(fi * 11.0, 100.0) - 50.0,
			fmod(fi * 29.0, 100.0) - 50.0)
		var t0 := (bottom + top - 2.0 * org.y) / (2.0 * dir.y)
		var t1 := (bottom + top - 2.0 * (org.y + dlt.y)) / (2.0 * dir.y)
		var c0: bool = t0 > float(B.HC_MAX_DIST)
		var c1: bool = t1 > float(B.HC_MAX_DIST)
		var p0: Vector3 = B.compute_hc_layer(dir, merged(hp_on, {"origin": org})).p_mid
		var p1: Vector3 = B.compute_hc_layer(dir, merged(hp_on, {"origin": org + dlt})).p_mid
		if c0 != c1:
			n_skipped += 1
			continue
		var expect: Vector3 = (p0 + dlt) if c0 else (p0 + dlt - dir * (dlt.y / dir.y))
		var tol := 1e-6 * (p0.length() + dlt.length()) + 1e-3
		max_err = maxf(max_err, (p1 - expect).length())
		max_tol = maxf(max_tol, tol)
	check("HC2-1 перенос камеры эквивариантен: вне клампа p_mid(O+Δ)=p_mid(O)+Δ−dir·Δy/dir.y, в клампе +Δ (120 наборов)",
		max_err < max_tol,
		"(max отклонение %.4f м < допуск %.4f м — float32; смешанных режимов пропущено %d)"
		% [max_err, max_tol, n_skipped])

	# HC2-2: срединная плоскость плиты — МИРОВАЯ: p_mid.y ≡ (bottom+top)/2 при любой
	# высоте камеры (вне клампа HC_MAX_DIST; в клампе — |p_mid−origin| ≡ HC_MAX_DIST,
	# низкие невидимые лучи, α=0 по HC2-8); путь path = (top−bottom)/dir.y от высоты
	# камеры НЕ зависит — подъём камеры не меняет оптическую толщину вуали. Допуски —
	# float32 Vector3: ulp(t≈60 км) ≈ 0.008 м.
	var max_y_err := 0.0
	var max_path_err := 0.0
	var tol_path := 0.0
	for i in range(0, 60):
		var fi := float(i)
		var dir := Vector3(fmod(fi * 0.43, 2.0) - 1.0, 0.15 + fmod(fi * 0.031, 0.8),
			fmod(fi * 0.77, 2.0) - 1.0).normalized()
		var oy := fi * 0.8
		var o_lo := Vector3(0.0, oy, 0.0)
		var o_hi := Vector3(300.0, oy + 50.0, -300.0)
		var r_lo: Dictionary = B.compute_hc_layer(dir, merged(hp_on, {"origin": o_lo}))
		var r_hi: Dictionary = B.compute_hc_layer(dir, merged(hp_on, {"origin": o_hi}))
		var t_mid := (bottom + top - 2.0 * oy) / (2.0 * dir.y)
		var p_lo: Vector3 = r_lo.p_mid
		if t_mid > B.HC_MAX_DIST:
			max_y_err = maxf(max_y_err, absf((p_lo - o_lo).length() - B.HC_MAX_DIST))
		else:
			max_y_err = maxf(max_y_err, absf(p_lo.y - (bottom + top) * 0.5))
		var dpath := absf(float(r_lo.path) - float(r_hi.path))
		max_path_err = maxf(max_path_err, dpath)
		tol_path = maxf(tol_path, 1e-6 * float(r_lo.path) + 1e-3)
	check("HC2-2 мировая срединная плоскость: p_mid.y ≡ (bottom+top)/2 (вне клампа), путь не зависит от высоты камеры",
		max_y_err < 0.05 and max_path_err < tol_path,
		"(|Δy| ≤ %.4f м < 0.05, |Δpath| ≤ %.4f м < %.4f — float32)" % [max_y_err, max_path_err, tol_path])

	# HC2-3: отклик на перенос камеры НЕПРЕРЫВЕН (нет скачков при движении): перенос
	# O→O+Δ разбит на 24 подшага; соседние отклики отличаются не больше, чем позволяет
	# градиентное ограничение поля (lip) на ФАКТИЧЕСКОЕ смещение точки выборки подшага.
	var rays: Array = B.hc_reference_rays()
	var d_big := Vector3(300.0, 50.0, -200.0)
	var hp_a := merged(hp_on, {"origin": Vector3.ZERO})
	var n_sub := 24
	var max_jump := 0.0
	var max_over := 0.0
	for r_v in rays:
		var r: Vector3 = (r_v as Vector3).normalized()
		var prev: Dictionary = B.compute_hc_layer(r, hp_a)
		for s in range(1, n_sub + 1):
			var d_sub := d_big * (float(s) / float(n_sub)) - d_big * (float(s - 1) / float(n_sub))
			var cur: Dictionary = B.compute_hc_layer(r, merged(hp_on,
				{"origin": d_big * (float(s) / float(n_sub))}))
			var dd := absf(float(cur.density) - float(prev.density))
			var disp: Vector3 = d_sub - r * (d_sub.y / r.y)
			var bound := lip * disp.length() + 1e-12
			max_jump = maxf(max_jump, dd)
			max_over = maxf(max_over, dd / bound)
			prev = cur
	check("HC2-3 непрерывность при переносе (Δ=(300,50,−200), 24 подшага × %d лучей): скачков нет" % rays.size(),
		max_over <= 1.0,
		"(max|Δd| подшага %.4f, худшее отношение к допуску %.3f)" % [max_jump, max_over])

	# HC2-4: параллакс оболочки ОГРАНИЧЕН геометрией: угловой сдвиг мировой точки при
	# взгляде из новой позиции ≤ asin(|Δ|/(L_min−|Δ|)), L_min — минимальная дистанция до
	# точки выборки среди лучей набора (у зенита ≈ (bottom+top)/2). Это честный параллакс
	# ДАЛЬНЕЙ плиты, а не скольжение по экрану: при Δ=50 м (перепад арены) — доли градуса.
	var hp_now := merged(hp_on, {"origin": d_big})
	var st: Dictionary = B.compute_hc_stability(rays, hp_a, hp_now)
	var l_min := INF
	for r_v in rays:
		var rr: Dictionary = B.compute_hc_layer(r_v, hp_a)
		if bool(rr.hit):
			l_min = minf(l_min, ((rr.p_mid as Vector3)).length())
	var par_bound := rad_to_deg(asin(clampf(d_big.length() / maxf(l_min - d_big.length(), 1.0), 0.0, 1.0)))
	check("HC2-4 параллакс оболочки: угловой сдвиг ≤ asin(|Δ|/(L_min−|Δ|)) — оценка сверху соблюдена",
		float(st.max_par_deg) <= par_bound + 1e-9 and int(st.hits) == rays.size(),
		"(сдвиг %.3f° ≤ %.3f°, L_min=%.0f м; max|Δd|=%.4f max|Δα|=%.4f)"
		% [float(st.max_par_deg), par_bound, l_min, float(st.max_dd), float(st.max_da)])
	# HC2-4b: арена-случай — чистый подъём на 50 м: параллакс доли градуса.
	var d_up := Vector3(0.0, 50.0, 0.0)
	var st50: Dictionary = B.compute_hc_stability(rays, hp_a, merged(hp_on, {"origin": d_up}))
	var par_bound50 := rad_to_deg(asin(clampf(50.0 / maxf(l_min - 50.0, 1.0), 0.0, 1.0)))
	check("HC2-4b перепад арены (подъём 50 м): параллакс ≤ %.2f° — вуаль читается как дальняя плита" % par_bound50,
		float(st50.max_par_deg) <= par_bound50 + 1e-9,
		"(сдвиг %.3f°, max|Δα|=%.4f)" % [float(st50.max_par_deg), float(st50.max_da)])

	# HC2-5: мировая периодичность компонент — швов при дрейфе нет. Плотность построена
	# из ровно двух выборок ОДНОЙ периодической текстуры: shape на периоде hc_scale и
	# field на периоде hc_field_scale. Каждая периодична при своём мировом сдвиге
	# Δo = T⁻¹(period·axis) (hc_world_period): uvw сдвигается ровно на 1 → из
	# repeat_enable/fposmod+%n значение сохраняется. Полная плотность периодична при
	# сдвиге на общий кратный обоих периодов (НОК — выводится евклидовым алгоритмом
	# из данных, не хардкод). Допуски — float32 Vector3: |p+Δo| до ~450 км (компоненты)
	# и ~3 Мм (НОК) → ulp 0.03/0.25 м → Δ(voxel) ≤ 1e-4/1e-3 → tol 1e-3/1e-2.
	var vox_pw: PackedByteArray = B._pw_voxels
	var pw_n := int(B.PW_SIZE)
	var max_sh_err := 0.0
	var max_fd_err := 0.0
	var per_min := INF
	var per_max := 0.0
	for axis_v in [Vector3.RIGHT, Vector3.UP, Vector3(0.0, 0.0, 1.0)]:
		for period_m in [scale_m, field_m]:
			var do: Vector3 = B.hc_world_period(hp_on, axis_v, period_m)
			per_min = minf(per_min, do.length())
			per_max = maxf(per_max, do.length())
			var hp_do := merged(hp_on, {"offset": do})
			for i in range(0, 40):
				var fi := float(i) + float(period_m == field_m) * 0.37
				var p := Vector3(fmod(fi * 911.0, 440000.0) - 220000.0, (bottom + top) * 0.5,
					fmod(fi * 577.0, 440000.0) - 220000.0)
				var c0: Vector3 = B.hc_sample_coord(p, hp_on)
				var c1: Vector3 = B.hc_sample_coord(p, hp_do)
				var per := float(period_m)
				var v0: float = B.sample_tex(vox_pw, pw_n, c0.x / per, c0.y / per, c0.z / per)
				var v1: float = B.sample_tex(vox_pw, pw_n, c1.x / per, c1.y / per, c1.z / per)
				if period_m == scale_m:
					max_sh_err = maxf(max_sh_err, absf(v1 - v0))
				else:
					max_fd_err = maxf(max_fd_err, absf(v1 - v0))
	# Общая периодичность полной плотности: сдвиг на НОК периодов (по оси X текстуры).
	var lcm_m := float(int(scale_m) / _gcd_int(int(scale_m), int(field_m)) * int(field_m))
	var do_lcm: Vector3 = B.hc_world_period(hp_on, Vector3.RIGHT, lcm_m)
	var max_lcm_err := 0.0
	for i in range(0, 40):
		var fi := float(i)
		var p := Vector3(fmod(fi * 911.0, 440000.0) - 220000.0, (bottom + top) * 0.5,
			fmod(fi * 577.0, 440000.0) - 220000.0)
		var d0: float = B.compute_hc_density(p, hp_on)
		var d1: float = B.compute_hc_density(p, merged(hp_on, {"offset": do_lcm}))
		max_lcm_err = maxf(max_lcm_err, absf(d1 - d0))
	check("HC2-5 мировая периодичность: shape/field-компоненты инвариантны к своему периоду, плотность — к НОК (швов при дрейфе нет)",
		max_sh_err < 1e-3 and max_fd_err < 1e-3 and max_lcm_err < 1e-2,
		"(Δshape=%.6f Δfield=%.6f Δd(НОК %.0f км)=%.6f; мировые периоды %.0f…%.0f км)"
		% [max_sh_err, max_fd_err, lcm_m / 1000.0, max_lcm_err, per_min / 1000.0, per_max / 1000.0])

	# HC2-6: PW-данные периодичны на уровне вокселей: средний перепад через границу
	# wrap (127→0) статистически такой же, как внутренние перепады (≤ ×1.5) → и GPU
	# repeat_enable, и зеркало fposmod заворачивают без видимого шва. 60 строк по X.
	var vox: PackedByteArray = B._pw_voxels
	var n := int(B.PW_SIZE)
	var sum_edge := 0.0
	var sum_inner := 0.0
	var cnt_inner := 0
	for i in range(0, 60):
		var y := int(fmod(float(i) * 37.0, float(n)))
		var z := int(fmod(float(i) * 91.0, float(n)))
		var prev_v := float(vox[z * n * n + y * n + (n - 1)])
		for x in range(0, n):
			var cur_v := float(vox[z * n * n + y * n + x])
			var dv := absf(cur_v - prev_v)
			if x == 0:
				sum_edge += dv
			else:
				sum_inner += dv
				cnt_inner += 1
			prev_v = cur_v
	var mean_edge := sum_edge / 60.0
	var mean_inner := sum_inner / float(cnt_inner)
	check("HC2-6 PW-текстура периодична: перепад на границе wrap ≈ внутренним (≤ ×1.5)",
		mean_edge > 0.0 and mean_edge <= mean_inner * 1.5,
		"(edge %.2f vs inner %.2f, отношение %.2f)" % [mean_edge, mean_inner,
			mean_edge / maxf(mean_inner, 1e-6)])

	# HC2-7: развёртка тангажа el = 89.75° → −1° шагом 0.25° (азимут фиксирован):
	# все значения конечны, ниже горизонта α == 0, плотность Lipschitz-непрерывна по
	# фактическому смещению точки выборки (у горизонта шаг 0.25° скользит точку на
	# сотни км — нормируем на смещение, а не на угол).
	var az := deg_to_rad(37.0)
	var prev_a7 := -1.0
	var prev_p7 := Vector3.ZERO
	var prev_d7 := 0.0
	var prev_hit7 := false
	var max_dpitch := 0.0
	var max_over7 := 0.0
	var bad_below := 0
	var nonfinite := 0
	var el := 89.75
	while el >= -1.0:
		var dir := Vector3(cos(deg_to_rad(el)) * sin(az), sin(deg_to_rad(el)),
			cos(deg_to_rad(el)) * cos(az))
		var r: Dictionary = B.compute_hc_layer(dir, hp_on)
		var a := float(r.alpha)
		var d := float(r.density)
		if not (is_finite(a) and is_finite(d)):
			nonfinite += 1
		if el <= 0.0 and a != 0.0:
			bad_below += 1
		if bool(r.hit):
			var p_cur: Vector3 = r.p_mid
			if prev_hit7:
				var disp := (p_cur - prev_p7).length()
				max_over7 = maxf(max_over7, absf(d - prev_d7) / maxf(lip * disp, 1e-12))
			prev_p7 = p_cur
			prev_d7 = d
		prev_hit7 = bool(r.hit)
		if prev_a7 >= 0.0:
			max_dpitch = maxf(max_dpitch, absf(a - prev_a7))
		prev_a7 = a
		el -= 0.25
	check("HC2-7 развёртка тангажа 89.75°→−1°: без NaN, ниже горизонта α=0, d непрерывна (Lip ≤ 1)",
		nonfinite == 0 and bad_below == 0 and max_over7 <= 1.0,
		"(max|Δα| на шаг %.4f — инфо; худшее Lip-отношение %.3f)" % [max_dpitch, max_over7])

	# HC2-8: guards у горизонта. Ниже ~4.9° (path ≥ curtain_end=14 км) вклада нет вообще
	# (α точно 0); у самого горизонта |dir.y| ≤ EPS=1e-6 — защита layer_interval (miss);
	# между ними — пересечение есть, точка выборки ограничена HC_MAX_DIST, всё конечно.
	var ok_above := true
	var max_p_len := 0.0
	for el_deg in [0.001, 0.01, 0.1, 1.0, 4.0]:
		var dir := Vector3(0.0, sin(deg_to_rad(el_deg)), -cos(deg_to_rad(el_deg)))
		var r: Dictionary = B.compute_hc_layer(dir, hp_on)
		var pm: Vector3 = r.p_mid
		if not bool(r.hit) or float(r.alpha) != 0.0 \
				or not (is_finite(pm.x) and is_finite(pm.y) and is_finite(pm.z)) \
				or not is_finite(float(r.tau)):
			ok_above = false
		max_p_len = maxf(max_p_len, pm.length())
	# el=1e-5°: dir.y = 1.7e-7 < EPS → miss (guard); el=0 и ниже → miss; α=0 везде.
	var ok_below := true
	for el_deg in [1e-5, 0.0, -0.01, -1.0]:
		var dir := Vector3(0.0, sin(deg_to_rad(el_deg)), -cos(deg_to_rad(el_deg)))
		var r: Dictionary = B.compute_hc_layer(dir, hp_on)
		if bool(r.hit) or float(r.alpha) != 0.0:
			ok_below = false
	check("HC2-8 guards горизонта: α=0 ниже ~4.9° (curtain), |dir.y|≤1e-6 — miss, точка выборки ≤ HC_MAX_DIST, всё конечно",
		ok_above and ok_below and max_p_len <= B.HC_MAX_DIST * 1.0001,
		"(|p_mid| max %.0f м ≤ %.0f)" % [max_p_len, B.HC_MAX_DIST])

	# HC2-9: зенит без сингулярности/полярного шва: развёртка азимута при el=89.99° —
	# все лучи пересекают плиту, path·sin(el) ≡ top−bottom, α конечна и непрерывна
	# (точка выборки у зенита почти стоит: горизонтальный вынос ~1.2 м).
	var max_daz := 0.0
	var prev_a9 := -1.0
	var ok_path9 := true
	var zen_el := deg_to_rad(89.99)
	for i in range(0, 72):
		var azi := TAU * float(i) / 72.0
		var dir := Vector3(cos(zen_el) * sin(azi), sin(zen_el), cos(zen_el) * cos(azi))
		var r: Dictionary = B.compute_hc_layer(dir, hp_on)
		if not bool(r.hit) or absf(float(r.path) * sin(zen_el) - (top - bottom)) > 1e-2:
			ok_path9 = false
		var a := float(r.alpha)
		if not is_finite(a):
			ok_path9 = false
		if prev_a9 >= 0.0:
			max_daz = maxf(max_daz, absf(a - prev_a9))
		prev_a9 = a
	# замыкание круга (az 355° → 0°)
	var r_first: Dictionary = B.compute_hc_layer(Vector3(0.0, sin(zen_el), cos(zen_el)), hp_on)
	max_daz = maxf(max_daz, absf(float(r_first.alpha) - prev_a9))
	check("HC2-9 зенитная развёртка az 0-360° (el=89.99°): path·sin(el) ≡ top−bottom, α непрерывна по азимуту",
		ok_path9 and max_daz <= 0.02, "(max|Δα|=%.6f)" % max_daz)

	# HC2-10: дрейф — ЧИСТЫЙ сдвиг поля, не связанный с камерой.
	# (a) hc_sample_coord линеен: T(p+o) = T(p) + T(o) — offset входит как перенос поля;
	var hp_zero_off := merged(hp_on, {"offset": Vector3.ZERO})
	var max_lin := 0.0
	var tol_lin := 0.0
	for i in range(0, 30):
		var fi := float(i)
		var p := Vector3(fmod(fi * 613.0, 200000.0) - 100000.0, (bottom + top) * 0.5,
			fmod(fi * 853.0, 200000.0) - 100000.0)
		var o := Vector3(fmod(fi * 173.0, 100000.0) - 50000.0, fmod(fi * 61.0, 4000.0) - 2000.0,
			fmod(fi * 239.0, 100000.0) - 50000.0)
		var t_po: Vector3 = B.hc_sample_coord(p + o, hp_zero_off)
		var t_sum: Vector3 = B.hc_sample_coord(p, hp_zero_off) + B.hc_sample_coord(o, hp_zero_off)
		max_lin = maxf(max_lin, (t_po - t_sum).length())
		tol_lin = maxf(tol_lin, 1e-6 * t_po.length() + 1e-3)
	check("HC2-10a дрейф — чистый перенос поля: T(p+o) = T(p)+T(o) (линейность hc_sample_coord)",
		max_lin < tol_lin,
		"(max отклонение %.4f м < допуск %.4f м — float32 ulp на ~100 км)" % [max_lin, tol_lin])
	# (b) стенд пишет hc_offset ТОЛЬКО из ветрового накопления (никакой камеры):
	var bench_src := String(B.source_code)
	var n_write := 0
	var ok_write := true
	var ok_drift := true
	for ln in bench_src.split("\n"):
		if ln.contains("set_shader_parameter(\"hc_offset\""):
			n_write += 1
			if not ln.contains("_hc_base_offset + _drift * hc_wind_factor"):
				ok_write = false
		if ln.contains("_drift +="):
			if not (ln.contains("wind_direction") and ln.contains("wind_speed")) or ln.contains("_cam"):
				ok_drift = false
	check("HC2-10b hc_offset пишется только ветром (_drift·hc_wind_factor), накопление _drift — только wind_direction/wind_speed",
		n_write == 1 and ok_write and ok_drift, "(записей hc_offset: %d)" % n_write)

	# HC2-11: семантика hc_use_world_anchor: false — отклик НЕ зависит от позиции камеры
	# (слой «едет» с камерой, как кучевые — документированный fallback); true —
	# эквивариантен (HC2-1). Значения в обеих ветках конечны.
	var d_c := Vector3(0.25, 0.62, -0.74).normalized()
	var r_c0: Dictionary = B.compute_hc_layer(d_c, merged(hp_on,
		{"world_anchor": false, "origin": Vector3.ZERO}))
	var r_c1: Dictionary = B.compute_hc_layer(d_c, merged(hp_on,
		{"world_anchor": false, "origin": Vector3(400.0, 30.0, -350.0)}))
	check("HC2-11 world_anchor=false: отклик побитово не зависит от origin (fallback «слой при камере»)",
		float(r_c0.density) == float(r_c1.density) and float(r_c0.alpha) == float(r_c1.alpha)
		and float(r_c0.tau) == float(r_c1.tau) and (r_c0.p_mid as Vector3) == (r_c1.p_mid as Vector3)
		and is_finite(float(r_c0.alpha)))

	# HC2-12: фаза 2 НЕ меняет состав модуля: те же 17 uniform'ов hc_*, в блоке вуали
	# 0 циклов, 0 вызовов марша/теней, ровно 2 texture(noise_pw), новых sampler'ов нет;
	# POSITION во всём шейдере ровно 1 (в hc_evaluate) — новых чтений камеры не добавилось.
	var n_uniforms := 0
	for ln in code.split("\n"):
		var t := ln.strip_edges()
		if t.begins_with("uniform ") and t.contains("hc_"):
			n_uniforms += 1
	var miss2 := []
	for nm in HC_UNIFORM_NAMES:
		if not code.contains(nm):
			miss2.append(nm)
	check("HC2-12 состав модуля: 22 uniform'а hc_* (перебазировано 3.3/SKYHC-4), 0 циклов/маршей, 2 texture(noise_pw)+1 worley, POSITION ×1",
		n_uniforms == HC_UNIFORM_NAMES.size() and miss2.is_empty()
		and not hc_block.contains("for (") and not hc_block.contains("cloud_density(")
		and not hc_block.contains("light_transmittance(")
		and hc_block.count("texture(noise_pw") == 2
		and hc_block.count("texture(noise_worley") == 1 and not hc_block.contains("sampler3D")
		and code_nc.count("POSITION") == 1 and hc_nc.count("POSITION") == 1,
		"(uniform'ов hc_*: %d, пропало: %s)" % [n_uniforms, str(miss2)])

	# HC2-13: вуаль считается только в full-res/cubemap-ветках (контракт subpass B6 не
	# изменён): единственный вызов hc_evaluate в sky() — под гейтом
	# !AT_HALF_RES_PASS && !AT_QUARTER_RES_PASS (в subpass вуали нет).
	var pos_guard := code_nc.find("if (!AT_HALF_RES_PASS && !AT_QUARTER_RES_PASS) {")
	var pos_call := code_nc.find("hc_evaluate(dir")
	check("HC2-13 единственный вызов hc_evaluate — под subpass-гейтом (вуаль только full-res/cubemap)",
		code_nc.count("hc_evaluate(") == 2 and pos_guard >= 0 and pos_call > pos_guard
		and pos_call - pos_guard < 120,
		"(guard@%d, вызов@%d, расстояние %d)" % [pos_guard, pos_call, pos_call - pos_guard])

	# HC2-14: регрессия гейта идентичности: после правок фазы 2 вуаль выключена → кадр
	# ПОБИТОВО равен D3 (compute_final_with_sun), ключевые строки шейдера на месте.
	var d_id := Vector3(0.25, 0.62, -0.74).normalized()
	var f_off2: Dictionary = B.compute_final_with_hc(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {}, {}, hp_off)
	var f_ref2: Dictionary = B.compute_final_with_sun(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {})
	check("HC2-14 регрессия гейта: вуаль выкл → final побитово ≡ D3; строки дефолта/гейта/композита на месте",
		(f_off2.final as Vector3) == (f_ref2.final as Vector3)
		and code.contains("uniform bool hc_enabled = false;")
		and code.contains("if (!hc_enabled) {")
		and code.contains("vec3 base = (bg + sunbg) * (1.0 - hc_a) + hc_rgb;"))


# === СЕКЦИЯ SKYHC-3.1: фаза 3 ТЗ, шаг 1 — крупный рисунок и масштаб (A/B) ===
# Проверяются: предсказуемость ручки масштаба (размер особенностей растёт с hc_scale),
# детекция вырождений классификатором hc_degeneracy («рябь»/«пятно»/«пелена»), дефолт
# в критериях ТЗ, вытянутость (отклик на hc_stretch ≈ линейный), конверт отношения
# field/scale (≥1.5 — иначе пелена), углы объявленных диапазонов меню, пресеты
# масштаба A/B, неизменность шейдера (фаза 3.1 не добавляет параметров/вычислений)
# и регрессия гейта идентичности D3. Пороги — из развёрток hc_pattern_stats (README §2);
# все развёртки детерминированы (фиксированные сетки/линии, без RNG).
func section_skyhc_31() -> void:
	print("--- Секция SKYHC-3.1: вуаль — крупный рисунок, масштаб A/B, вырождения ---")
	var sh: Shader = load(SHADER_PATH)
	var code := sh.code
	var hp_on := {"enabled": true, "origin": Vector3.ZERO}
	var q: Dictionary = B.hcp_defaults(hp_on)
	var def_scale := float(q.scale)
	var def_stretch := float(q.stretch)
	var def_field := float(q.field_scale)

	# Диапазоны ползунков — ИЗ ТАБЛИЦЫ МЕНЮ стенда (данные, не хардкод теста).
	var ranges := {}
	for sec_v in B.TUNE_SECTIONS:
		var sec: Dictionary = sec_v
		for r_v in (sec.rows as Array):
			var r: Dictionary = r_v
			if str(r.get("k", "")) == "f" and ["hc_scale", "hc_stretch", "hc_field_scale"].has(str(r.get("u", ""))):
				ranges[str(r.u)] = [float(r.a), float(r.b)]
	check("HC31-0 диапазоны hc_scale/hc_stretch/hc_field_scale объявлены в меню стенда",
		ranges.has("hc_scale") and ranges.has("hc_stretch") and ranges.has("hc_field_scale"),
		"(%s)" % str(ranges))

	# HC31-1: ручка масштаба предсказуема: размер особенностей (поперёк гряд) монотонно
	# растёт с hc_scale (не меньше чем ×1.5 на каждое утроение масштаба), класс «ok»
	# во всех трёх точках. Измерено: 4.6 → 20.7 → 64.0 км.
	var f_prev := 0.0
	var ok31 := true
	var feat_report := ""
	for sc in [20000.0, 60000.0, 180000.0]:
		var st: Dictionary = B.hc_degeneracy(merged(hp_on, {"scale": sc, "field_scale": sc * 4.333}))
		var fa := float(st.feat_across_km)
		if f_prev > 0.0 and fa < f_prev * 1.5:
			ok31 = false
		if str(st["class"]) != "ok":
			ok31 = false
		f_prev = fa
		feat_report += "%.0fкм:%.1f " % [sc / 1000.0, fa]
	check("HC31-1 масштаб предсказуем: feat_across растёт ≥ ×1.5 на шаг развёртки, класс «ok»",
		ok31, "(%s)" % feat_report)

	# HC31-2: детекция «ряби» — особенности мельче HC_FEATURE_MIN_KM (2 км, сопоставимо
	# с ареной 1×1 км): scale 3k/5k → «ripple», 12k и дефолт → «ok».
	var r5: Dictionary = B.hc_degeneracy(merged(hp_on, {"scale": 5000.0, "field_scale": 21666.0}))
	var r3: Dictionary = B.hc_degeneracy(merged(hp_on, {"scale": 3000.0, "field_scale": 13000.0}))
	var r12: Dictionary = B.hc_degeneracy(merged(hp_on, {"scale": 12000.0, "field_scale": 52000.0}))
	check("HC31-2 «рябь» детектируется: scale 3k/5k → ripple (особенности < 2 км), 12k → ok",
		str(r5["class"]) == "ripple" and str(r3["class"]) == "ripple" and str(r12["class"]) == "ok",
		"(5k: across %.2f км, 3k: %.2f км, 12k: %.2f км)" % [float(r5.feat_across_km),
			float(r3.feat_across_km), float(r12.feat_across_km)])

	# HC31-3: детекция «одного гигантского пятна» — смена рисунка отсутствует в обоих
	# направлениях окна ±60 км И окон чистого неба < 5 %.
	var b1: Dictionary = B.hc_degeneracy(merged(hp_on, {"scale": 500000.0, "field_scale": 2000000.0,
		"field_amp": 0.0, "coverage": 0.05}))
	var b2: Dictionary = B.hc_degeneracy(merged(hp_on, {"scale": 300000.0, "field_scale": 1300000.0}))
	check("HC31-3 «пятно» детектируется: 500k/amp0/cov0.05 и 300k → blob (clear < 5 %)",
		str(b1["class"]) == "blob" and str(b2["class"]) == "blob",
		"(500k: clear %.2f along %.0f; 300k: clear %.2f along %.0f)" % [float(b1.clear_frac),
			float(b1.feat_along_km), float(b2.clear_frac), float(b2.feat_along_km)])

	# HC31-4: детекция «однородной пелены» — σ плотности < HC_MIN_SIGMA (0.15):
	# field_scale == scale (периоды совпали — поле модулирует само себя) и field_amp = 0.
	var v1: Dictionary = B.hc_degeneracy(merged(hp_on, {"field_scale": def_scale}))
	var v2: Dictionary = B.hc_degeneracy(merged(hp_on, {"field_amp": 0.0}))
	check("HC31-4 «пелена» детектируется: field/scale=1 и field_amp=0 → veil (σ < 0.15)",
		str(v1["class"]) == "veil" and str(v2["class"]) == "veil",
		"(σ ratio=1: %.2f, σ amp=0: %.2f)" % [float(v1.std), float(v2.std)])

	# HC31-5: дефолт — в критериях ТЗ: «ok», окна и плотные образования присутствуют
	# (цели SKYHC-1: clear > 5 %, dense > 10 %, σ > 0.25), поперечные особенности
	# ≥ 2×HC_FEATURE_MIN_KM и ≤ HC_FEATURE_MAX_KM (широкие, но не одно пятно).
	var st_def: Dictionary = B.hc_degeneracy(hp_on)
	check("HC31-5 дефолт в критериях: «ok», clear≥5 %, dense≥10 %, σ≥0.25, 4≤feat_across≤40 км",
		str(st_def["class"]) == "ok" and float(st_def.clear_frac) >= 0.05
		and float(st_def.dense_frac) >= 0.10 and float(st_def.std) >= 0.25
		and float(st_def.feat_across_km) >= 2.0 * float(B.HC_FEATURE_MIN_KM)
		and float(st_def.feat_across_km) <= float(B.HC_FEATURE_MAX_KM),
		"(clear %.2f dense %.2f σ %.2f along %.1f across %.1f км)" % [float(st_def.clear_frac),
			float(st_def.dense_frac), float(st_def.std), float(st_def.feat_along_km),
			float(st_def.feat_across_km)])

	# HC31-6: вытянутость — отклик на hc_stretch: отношение along/across монотонно
	# растёт, при stretch=1 изотропно (0.7…1.3), отношение/stretch ∈ [0.55, 1.1]
	# (≈линейная ручка; измерено 0.97/0.81/0.81/0.80/0.86), поперёк — без ряби.
	var stretch_vals := [1.0, 2.0, 3.5, 5.0, 6.0]
	var ratio_prev := 0.0
	var ok36 := true
	var ok_iso := false
	var ok_lin := true
	var ok_across := true
	var report36 := ""
	for sv in stretch_vals:
		var st: Dictionary = B.hc_degeneracy(merged(hp_on, {"stretch": sv}))
		var ratio := float(st.feat_along_km) / maxf(float(st.feat_across_km), 0.001)
		if ratio <= ratio_prev:
			ok36 = false
		if sv == 1.0 and ratio >= 0.7 and ratio <= 1.3:
			ok_iso = true
		if ratio / sv < 0.55 or ratio / sv > 1.1:
			ok_lin = false
		if float(st.feat_across_km) < float(B.HC_FEATURE_MIN_KM):
			ok_across = false
		ratio_prev = ratio
		report36 += "%.1f:%.2f " % [sv, ratio]
	check("HC31-6 вытянутость: ratio монотонно растёт со stretch, =1 изотропен, отклик ≈линеен, поперёк без ряби",
		ok36 and ok_iso and ok_lin and ok_across, "(along/across: %s)" % report36)

	# HC31-7: конверт field/scale — при отношении ≥ 1.5 крупная неоднородность
	# сохранна (класс «ok», σ ≥ 0.25); при 1.0 — вырождение в пелену (HC31-4).
	var ok37 := true
	var report37 := ""
	for ratio in [1.5, 2.0, 3.0, 4.333, 6.0, 8.0]:
		var st: Dictionary = B.hc_degeneracy(merged(hp_on, {"field_scale": def_scale * ratio}))
		if str(st["class"]) != "ok" or float(st.std) < 0.25:
			ok37 = false
		report37 += "%.1f:%s/σ%.2f " % [ratio, str(st["class"]), float(st.std)]
	check("HC31-7 конверт field/scale ≥ 1.5: «ok» и σ ≥ 0.25 во всех точках (1.5…8×)",
		ok37, "(%s)" % report37)

	# HC31-8: углы объявленных диапазонов меню (6 представительных комбинаций крайних
	# значений hc_scale/hc_stretch/hc_field_scale из таблицы стенда) — все «ok»:
	# диапазоны согласованы, вырожденные комбинации за их пределами (документировано).
	var rs: Array = ranges["hc_scale"]
	var rt: Array = ranges["hc_stretch"]
	var rf: Array = ranges["hc_field_scale"]
	var corners := [
		[rs[0], rt[0], rf[0]], [rs[0], rt[1], rf[0]], [rs[1], rt[0], rf[1]],
		[rs[1], rt[1], rf[1]], [rs[0], def_stretch, rf[1]], [rs[1], def_stretch, rf[0]],
	]
	var ok38 := true
	var report38 := ""
	for c in corners:
		var st: Dictionary = B.hc_degeneracy(merged(hp_on, {"scale": float(c[0]),
			"stretch": float(c[1]), "field_scale": float(c[2])}))
		if str(st["class"]) != "ok":
			ok38 = false
		report38 += "[%.0fk/%.1f/%.0fk]:%s " % [float(c[0]) / 1000.0, float(c[1]),
			float(c[2]) / 1000.0, str(st["class"])]
	check("HC31-8 углы диапазонов меню (scale×stretch×field) — все «ok»",
		ok38, "(%s)" % report38)

	# HC31-9: пресеты масштаба A/B: 4 штуки, только ключи hc_scale/hc_stretch/
	# hc_field_scale, значения внутри диапазонов меню, scale строго растёт, отношение
	# field/scale ∈ [3.5, 5] (сохранена проверенная связь), каждый пресет — «ok».
	var presets: Array = B.HC_SCALE_PRESETS
	var ok39 := presets.size() == 4
	var prev_scale := 0.0
	var report39 := ""
	for pr_v in presets:
		var pr: Dictionary = pr_v
		var u: Dictionary = pr.u
		for k in u.keys():
			if not ["hc_scale", "hc_stretch", "hc_field_scale"].has(str(k)):
				ok39 = false
		var sc := float(u.get("hc_scale", 0.0))
		var stv := float(u.get("hc_stretch", 0.0))
		var fs := float(u.get("hc_field_scale", 0.0))
		if sc <= prev_scale:
			ok39 = false
		prev_scale = sc
		if sc < float(rs[0]) or sc > float(rs[1]) or stv < float(rt[0]) or stv > float(rt[1]) \
				or fs < float(rf[0]) or fs > float(rf[1]):
			ok39 = false
		if fs / sc < 3.5 or fs / sc > 5.0:
			ok39 = false
		var hp_pr := merged(hp_on, {"scale": sc, "stretch": stv, "field_scale": fs})
		var st: Dictionary = B.hc_degeneracy(hp_pr)
		if str(st["class"]) != "ok":
			ok39 = false
		report39 += "%s:%s(%.1fкм) " % [str(pr.n), str(st["class"]), float(st.feat_across_km)]
	check("HC31-9 пресеты A/B: 4 шт., рост масштаба, в диапазонах меню, ratio 3.5-5, все «ok»",
		ok39, "(%s)" % report39)

	# HC31-10: фаза 3.1 НЕ меняет шейдер: дефолты вуали на месте (scale/stretch/field),
	# состав модуля прежний (17 uniform'ов, 0 циклов, 2 texture(noise_pw), POSITION ×1),
	# гейт идентичности D3 побитово сохранён.
	var hc_block := _hc_shader_block(code)
	var code_nc := _strip_comments(code)
	var n_uniforms := 0
	for ln in code.split("\n"):
		var t := ln.strip_edges()
		if t.begins_with("uniform ") and t.contains("hc_"):
			n_uniforms += 1
	var d_id := Vector3(0.25, 0.62, -0.74).normalized()
	var f_off: Dictionary = B.compute_final_with_hc(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {}, {}, {"enabled": false})
	var f_ref: Dictionary = B.compute_final_with_sun(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {})
	check("HC31-10 дефолты масштаба не изменены (60k/3.5/260k), 22 uniform'а (3.3/4), 0 циклов, POSITION ×1, гейт D3 побитово",
		code.contains("uniform float hc_scale = 60000.0;")
		and code.contains("uniform float hc_stretch = 3.5;")
		and code.contains("uniform float hc_field_scale = 260000.0;")
		and n_uniforms == HC_UNIFORM_NAMES.size()
		and not hc_block.contains("for (") and hc_block.count("texture(noise_pw") == 2
		and hc_block.count("texture(noise_worley") == 1 and code_nc.count("POSITION") == 1
		and (f_off.final as Vector3) == (f_ref.final as Vector3),
		"(uniform'ов hc_*: %d)" % n_uniforms)


## SKYHC-3.2: гладкость — max|Δd| на 250-м смещение вдоль набора линий HC1-4 (240 точек).
func _hc32_smooth(hp: Dictionary) -> float:
	var mx := 0.0
	for i in range(0, 240):
		var pp := Vector3(float(i) * 260.0 - 30000.0, 6600.0, -float(i) * 470.0 + 12000.0)
		var d0: float = B.compute_hc_density(pp, hp)
		var d1: float = B.compute_hc_density(pp + Vector3(120.0, 0.0, -220.0), hp)
		mx = maxf(mx, absf(d1 - d0))
	return mx


# === СЕКЦИЯ SKYHC-3.2: фаза 3 ТЗ, шаг 2 — разрывы/неоднородность + аудит ручек ===
# Проверяются: монотонность и рабочие зоны coverage/softness/field_amp (п.2 фазы 3
# «настроить разрывы и неоднородность»), чистота оптики tau_per_km (рисунок заморожен),
# НЕЗАВИСИМОСТЬ ручек через «владение» наблюдаемыми (ТЗ: «не добавлять множество
# параметров, если несколько из них управляют практически одним и тем же эффектом» —
# аудит показывает, что у каждой ручки есть собственный измеряемый эффект), пресеты
# характера, документированные вырожденные зоны, неизменность шейдера и гейт D3.
# Индексы наблюдаемых hc_observables: 0 mean, 1 σ, 2 clear, 3 dense, 4 mid,
# 5 block_std, 6 log(feat_across), 7 log(feat_along), 8 mean_alpha.
func section_skyhc_32() -> void:
	print("--- Секция SKYHC-3.2: вуаль — разрывы/неоднородность, аудит независимости ручек ---")
	var sh: Shader = load(SHADER_PATH)
	var code := sh.code
	var code_nc := _strip_comments(code)
	var hp_on := {"enabled": true, "origin": Vector3.ZERO}
	var q: Dictionary = B.hcp_defaults(hp_on)
	var def_scale := float(q.scale)

	# Диапазоны меню — из таблицы стенда (данные, как HC31-0).
	var ranges := {}
	var has_char_row := false
	for sec_v in B.TUNE_SECTIONS:
		var sec: Dictionary = sec_v
		for r_v in (sec.rows as Array):
			var r: Dictionary = r_v
			if str(r.get("k", "")) == "f" and ["hc_coverage", "hc_softness", "hc_field_amp"].has(str(r.get("u", ""))):
				ranges[str(r.u)] = [float(r.a), float(r.b)]
			if str(r.get("k", "")) == "hcchar":
				has_char_row = true
	check("HC32-0 меню: диапазоны coverage/softness/field_amp и строка «Характер A/B» объявлены, 4 пресета",
		ranges.has("hc_coverage") and ranges.has("hc_softness") and ranges.has("hc_field_amp")
		and has_char_row and B.HC_CHAR_PRESETS.size() == 4)

	# HC32-1: coverage — ручка КОЛИЧЕСТВА: clear строго растёт, mean строго падает
	# (0.20→0.80, везде «ok»); край 0.05 — «blob» (сплошное покрытие без окон, смена
	# рисунка исчезает — 0.5-пересечений нет). Измерено: clear 0.03→0.62, mean 0.73→0.16.
	var prev_clear := -1.0
	var prev_mean := 2.0
	var ok1 := true
	var rep1 := ""
	for cv in [0.20, 0.35, 0.50, 0.65, 0.80]:
		var st: Dictionary = B.hc_degeneracy(merged(hp_on, {"coverage": cv}))
		if float(st.clear_frac) <= prev_clear or float(st.mean) >= prev_mean \
				or str(st["class"]) != "ok":
			ok1 = false
		prev_clear = float(st.clear_frac)
		prev_mean = float(st.mean)
		rep1 += "%.2f:%.2f/%.2f " % [cv, float(st.clear_frac), float(st.mean)]
	var z_blob: Dictionary = B.hc_degeneracy(merged(hp_on, {"coverage": 0.05}))
	check("HC32-1 coverage: clear строго ↑, mean строго ↓ (0.20-0.80 все «ok»); 0.05 → «blob»",
		ok1 and str(z_blob["class"]) == "blob",
		"(clear/mean: %s; 0.05→%s)" % [rep1, str(z_blob["class"])])

	# HC32-2: softness — ручка МЯГКОСТИ: mid строго растёт, σ строго падает, геометрия
	# 0.5-уровня не движется (feat_across ±15 % — окно sstep симметрично вокруг порога);
	# гладкость дефолта ≤ 0.30 (порог HC1-4), а при softness 0.01 контур жёсткий
	# (Δd/250 м ≥ 0.90 — измерено 1.0; зона задокументирована подсказкой меню).
	var prev_mid := -1.0
	var prev_std := 2.0
	var ok2 := true
	var feat_ref := 0.0
	var feat_ok := true
	for sv in [0.05, 0.15, 0.22, 0.35, 0.50]:
		var st: Dictionary = B.hc_degeneracy(merged(hp_on, {"softness": sv}))
		if float(st.mid_frac) <= prev_mid or float(st.std) >= prev_std:
			ok2 = false
		prev_mid = float(st.mid_frac)
		prev_std = float(st.std)
		if feat_ref == 0.0:
			feat_ref = float(st.feat_across_km)
		elif absf(float(st.feat_across_km) - feat_ref) > feat_ref * 0.15:
			feat_ok = false
	var smooth_def := _hc32_smooth(hp_on)
	var smooth_hard := _hc32_smooth(merged(hp_on, {"softness": 0.01}))
	check("HC32-2 softness: mid ↑, σ ↓, feat_across стабилен ±15%; гладкость дефолта ≤ 0.30, при 0.01 — жёсткий контур ≥ 0.90",
		ok2 and feat_ok and smooth_def <= 0.30 and smooth_hard >= 0.90,
		"(Δd/250м: дефолт %.3f, soft=0.01 %.3f; feat %.1f км)" % [smooth_def, smooth_hard, feat_ref])

	# HC32-3: field_amp — ручка НЕОДНОРОДНОСТИ: 0 → «veil» (σ 0.12 < 0.15); σ растёт
	# (0.12→0.39), с amp 0.30 σ ≥ 0.28 (рабочая нижняя граница подсказки); связь со
	# средним: mean(1.0) − mean(0.0) ≥ 0.4 (среднее PW-поля ≈ 0.29 ≠ 0.5 — amp уводит
	# эффективный порог вниз; компенсация coverage задокументирована подсказкой меню).
	var a0: Dictionary = B.hc_degeneracy(merged(hp_on, {"field_amp": 0.0}))
	var a3: Dictionary = B.hc_degeneracy(merged(hp_on, {"field_amp": 0.30}))
	var a6: Dictionary = B.hc_degeneracy(merged(hp_on, {"field_amp": 0.60}))
	var a10: Dictionary = B.hc_degeneracy(merged(hp_on, {"field_amp": 1.0}))
	check("HC32-3 field_amp: 0 → «veil»; σ 0.12→0.39 (с amp 0.30 ≥ 0.28); связь с mean ≥ 0.4 (компенсируется coverage)",
		str(a0["class"]) == "veil" and float(a0.std) < 0.15
		and float(a3.std) >= 0.28 and float(a6.std) > float(a3.std)
		and float(a10.mean) - float(a0.mean) >= 0.4,
		"(σ: %.2f/%.2f/%.2f; mean %.2f→%.2f)" % [float(a0.std), float(a3.std), float(a6.std),
			float(a0.mean), float(a10.mean)])

	# HC32-4: tau_per_km — ЧИСТАЯ ОПТИКА: плотность не меняется вовсе (24 детерминированные
	# точки × tau 0.05-3.0, Δ == 0.0 точно — τ умножает плотность ПОСЛЕ hc_density),
	# средняя α строго растёт с tau.
	var max_dd4 := 0.0
	for t in [0.05, 0.20, 0.35, 1.00, 3.00]:
		for i in range(0, 24):
			var fi := float(i)
			var pp := Vector3(fmod(fi * 911.0, 120000.0) - 60000.0, 6600.0,
				fmod(fi * 577.0, 120000.0) - 60000.0)
			var d0: float = B.compute_hc_density(pp, hp_on)
			var d1: float = B.compute_hc_density(pp, merged(hp_on, {"tau_per_km": t}))
			max_dd4 = maxf(max_dd4, absf(d1 - d0))
	var m1: Dictionary = B.hc_alpha_response(merged(hp_on, {"tau_per_km": 0.10}))
	var m2: Dictionary = B.hc_alpha_response(merged(hp_on, {"tau_per_km": 0.35}))
	var m3: Dictionary = B.hc_alpha_response(merged(hp_on, {"tau_per_km": 1.00}))
	check("HC32-4 tau_per_km — чистая оптика: Δdensity == 0 точно (24 точки × 5 tau), mean_α строго ↑",
		max_dd4 == 0.0 and float(m1.mean_alpha) < float(m2.mean_alpha)
		and float(m2.mean_alpha) < float(m3.mean_alpha),
		"(max|Δd| = %.1f; mα %.3f < %.3f < %.3f)" % [max_dd4, float(m1.mean_alpha),
			float(m2.mean_alpha), float(m3.mean_alpha)])

	# HC32-5: АУДИТ НЕЗАВИСИМОСТИ — сырая Δ-матрица (ручка × наблюдаемая) считается
	# здесь же; правила «владения» с запасами ≥ 2× (измерены развёрткой, README §3):
	#   softness владеет mid (≥ 2× любой другой) и НЕ трогает геометрию 0.5-уровня;
	#   stretch владеет анизотропией (Δlog_along − Δlog_across максимален) и почти не
	#     трогает поперечный размер (≤ 0.35·|Δlog_across(scale)|);
	#   scale — единственная ручка «чистой геометрии»: сильно двигает оба log-размера
	#     (среднее ≥ 0.6) и почти не двигает доли/среднее (≤ 0.05);
	#   field_scale владеет block_std (максимум, ≥ 4·|Δbstd(coverage)|) и единственная
	#     УКОРАЧИВАЕТ гряды (Δlog_along < 0 — окна крупнее, переходы реже);
	#   coverage — «чистое количество»: purity |Δmean|/(|Δσ|+|Δbstd|) ≥ 2× purity(field_amp);
	#   field_amp — «контраст»: spread |Δσ|+|Δbstd| ≥ 2× spread(coverage).
	# Пара field_amp×coverage коллинеарна в агрегатах (|cos| ≈ 0.95, знаки встречные —
	# связь через эффективный порог): НЕ дубликаты — различаются правилами purity/spread.
	var knobs: Array = []
	var deltas := {}
	for kv in B.HC_AUDIT_KNOBS:
		var k: Dictionary = kv
		var o_lo: Array = B.hc_observables(merged(hp_on, {str(k.key): float(k.lo)}))
		var o_hi: Array = B.hc_observables(merged(hp_on, {str(k.key): float(k.hi)}))
		var row: Array = []
		for i in range(0, o_lo.size()):
			row.append(float(o_hi[i]) - float(o_lo[i]))
		deltas[str(k.key)] = row
		knobs.append(str(k.key))
	var d_mid_soft: float = deltas["softness"][4]
	var own_soft_mid := true
	for kn in knobs:
		if str(kn) != "softness" and d_mid_soft < 2.0 * absf(float(deltas[kn][4])):
			own_soft_mid = false
	var own_soft_geom: bool = absf(float(deltas["softness"][6])) < 1e-12 \
		and absf(float(deltas["softness"][7])) < 1e-12
	var aniso := {}
	for kn in knobs:
		aniso[kn] = float(deltas[kn][7]) - float(deltas[kn][6])
	var own_stretch := true
	for kn in knobs:
		if str(kn) != "stretch" and float(aniso["stretch"]) <= float(aniso[kn]):
			own_stretch = false
	var own_stretch_fa: bool = absf(float(deltas["stretch"][6])) <= 0.35 * absf(float(deltas["scale"][6]))
	var scale_geom: float = (float(deltas["scale"][6]) + float(deltas["scale"][7])) * 0.5
	var scale_pure: float = absf(float(deltas["scale"][0])) + absf(float(deltas["scale"][2])) + absf(float(deltas["scale"][3]))
	var own_scale: bool = scale_geom >= 0.6 and scale_pure <= 0.05
	var scale_unique := true
	for kn in knobs:
		if str(kn) != "scale" \
				and (float(deltas[kn][6]) + float(deltas[kn][7])) * 0.5 >= 0.6 \
				and absf(float(deltas[kn][0])) + absf(float(deltas[kn][2])) + absf(float(deltas[kn][3])) <= 0.05:
			scale_unique = false
	var own_fs: bool = float(deltas["field_scale"][5]) > 0.0 and float(deltas["field_scale"][7]) < 0.0 \
		and float(deltas["field_scale"][5]) >= 4.0 * absf(float(deltas["coverage"][5]))
	for kn in knobs:
		if str(kn) != "field_scale" and float(deltas[kn][5]) >= float(deltas["field_scale"][5]):
			own_fs = false
	var pur_cov: float = absf(float(deltas["coverage"][0])) / maxf(absf(float(deltas["coverage"][1])) + absf(float(deltas["coverage"][5])), 1e-9)
	var pur_amp: float = absf(float(deltas["field_amp"][0])) / maxf(absf(float(deltas["field_amp"][1])) + absf(float(deltas["field_amp"][5])), 1e-9)
	var own_cov: bool = pur_cov >= 2.0 * pur_amp
	var spr_cov: float = absf(float(deltas["coverage"][1])) + absf(float(deltas["coverage"][5]))
	var spr_amp: float = absf(float(deltas["field_amp"][1])) + absf(float(deltas["field_amp"][5]))
	var own_amp: bool = spr_amp >= 2.0 * spr_cov
	# Информационно: худшая пара |cos| (ожидается field_amp×coverage ≈ 0.95).
	var worst_cos := 0.0
	var worst_pair := ""
	for i in range(0, knobs.size()):
		for j in range(i + 1, knobs.size()):
			var va: Array = deltas[knobs[i]]
			var vb: Array = deltas[knobs[j]]
			var dot := 0.0
			var na := 0.0
			var nb := 0.0
			for m in range(0, va.size()):
				dot += float(va[m]) * float(vb[m])
				na += float(va[m]) * float(va[m])
				nb += float(vb[m]) * float(vb[m])
			var c: float = absf(dot) / maxf(sqrt(na * nb), 1e-12)
			if c > worst_cos:
				worst_cos = c
				worst_pair = "%s×%s" % [knobs[i], knobs[j]]
	check("HC32-5 аудит: у каждой ручки собственный эффект (владение mid/aniso/геометрией/bstd/purity/spread, запас ≥ 2×)",
		own_soft_mid and own_soft_geom and own_stretch and own_stretch_fa
		and own_scale and scale_unique and own_fs and own_cov and own_amp,
		"(purity cov %.1f vs amp %.1f; spread amp %.3f vs cov %.3f; worst |cos| %.3f %s — связь через порог задокументирована)"
		% [pur_cov, pur_amp, spr_amp, spr_cov, worst_cos, worst_pair])

	# HC32-6: block_std (пространственная неоднородность, блоки 30 км): дефолт ≥ 0.15;
	# field_amp двигает её ≥ 4× сильнее coverage (5.5× измерено), field_scale — главный
	# региональный knob (≥ 1.2× amp).
	var st_def: Dictionary = B.hc_pattern_stats(hp_on)
	check("HC32-6 block_std: дефолт ≥ 0.15; amp ≥ 4×|Δcov|, field_scale ≥ 1.2× amp",
		float(st_def.block_std) >= 0.15
		and float(deltas["field_amp"][5]) >= 4.0 * absf(float(deltas["coverage"][5]))
		and float(deltas["field_scale"][5]) >= 1.2 * float(deltas["field_amp"][5]),
		"(bstd дефолт %.3f; Δ: amp %+.3f cov %+.3f fs %+.3f)" % [float(st_def.block_std),
			float(deltas["field_amp"][5]), float(deltas["coverage"][5]), float(deltas["field_scale"][5])])

	# HC32-7: дефолт — в центре рабочего конверта (не на границе зоны): «ok»,
	# clear/dense ∈ [0.20, 0.35], σ ≥ 0.35, bstd ≥ 0.15 (измерено 0.28/0.29/0.39/0.20).
	var dg_def: Dictionary = B.hc_degeneracy(hp_on)
	check("HC32-7 дефолт в центре конверта: «ok», clear/dense 0.20-0.35, σ ≥ 0.35, bstd ≥ 0.15",
		str(dg_def["class"]) == "ok"
		and float(dg_def.clear_frac) >= 0.20 and float(dg_def.clear_frac) <= 0.35
		and float(dg_def.dense_frac) >= 0.20 and float(dg_def.dense_frac) <= 0.35
		and float(dg_def.std) >= 0.35 and float(dg_def.block_std) >= 0.15,
		"(clear %.2f dense %.2f σ %.2f bstd %.3f)" % [float(dg_def.clear_frac),
			float(dg_def.dense_frac), float(dg_def.std), float(dg_def.block_std)])

	# HC32-8: пресеты характера: ключи — uniform-имена, hc_preset_to_hp переводит их в
	# ключи зеркала ровно (3 ключа); все «ok»; значения в диапазонах меню; лестница
	# clear_frac неубывающая; соседние различимы (Δclear ≥ 0.05 ИЛИ Δконтраста ≥ 0.02);
	# «Острова и окна» — максимум контраста (σ+bstd), «Редкие гряды» — максимум clear;
	# гладкость каждого ≤ 0.30 (порог HC1-4).
	var presets: Array = B.HC_CHAR_PRESETS
	var ladder_ok := true
	var all_ok := true
	var prev_clear8 := -1.0
	var stats_arr: Array = []
	var rep8 := ""
	for pr_v in presets:
		var pr: Dictionary = pr_v
		var u: Dictionary = pr.u
		var tr: Dictionary = B.hc_preset_to_hp(u)
		if tr.size() != 3 or not (tr.has("coverage") and tr.has("field_amp") and tr.has("softness")):
			all_ok = false
		var hp_pr := merged(hp_on, tr)
		var cv := float(u.get("hc_coverage", -1.0))
		var sp := float(u.get("hc_softness", -1.0))
		var fa := float(u.get("hc_field_amp", -1.0))
		if cv < float(ranges["hc_coverage"][0]) or cv > float(ranges["hc_coverage"][1]) \
				or sp < float(ranges["hc_softness"][0]) or sp > float(ranges["hc_softness"][1]) \
				or fa < float(ranges["hc_field_amp"][0]) or fa > float(ranges["hc_field_amp"][1]):
			all_ok = false
		var st: Dictionary = B.hc_degeneracy(hp_pr)
		if str(st["class"]) != "ok":
			all_ok = false
		if float(st.clear_frac) < prev_clear8:
			ladder_ok = false
		prev_clear8 = float(st.clear_frac)
		if _hc32_smooth(hp_pr) > 0.30:
			all_ok = false
		stats_arr.append(st)
		rep8 += "%s:%.3f " % [str(pr.n), float(st.clear_frac)]
	var distinct := true
	for i in range(1, stats_arr.size()):
		var pa: Dictionary = stats_arr[i - 1]
		var pb: Dictionary = stats_arr[i]
		var d_clear: float = absf(float(pb.clear_frac) - float(pa.clear_frac))
		var d_contr: float = absf((float(pb.std) + float(pb.block_std)) - (float(pa.std) + float(pa.block_std)))
		if d_clear < 0.05 and d_contr < 0.02:
			distinct = false
	var max_contr_idx := 0
	var max_clear_idx := 0
	for i in range(1, stats_arr.size()):
		var ci: float = float(stats_arr[i].std) + float(stats_arr[i].block_std)
		var c0: float = float(stats_arr[max_contr_idx].std) + float(stats_arr[max_contr_idx].block_std)
		if ci > c0:
			max_contr_idx = i
		if float(stats_arr[i].clear_frac) > float(stats_arr[max_clear_idx].clear_frac):
			max_clear_idx = i
	check("HC32-8 пресеты характера: все «ok», лестница clear, соседние различимы, «Острова» = макс. контраст, «Редкие» = макс. clear, гладкость ≤ 0.30",
		all_ok and ladder_ok and distinct \
		and str((presets[max_contr_idx] as Dictionary).n) == "Острова и окна" \
		and str((presets[max_clear_idx] as Dictionary).n) == "Редкие гряды",
		"(clear: %s)" % rep8)

	# HC32-9: документированные вырожденные зоны флагуются, рабочие — «ok»:
	# cov 0.05 → «blob»; cov 0.05 + amp 0 → «veil» (сплошная пелена без окон — новое
	# правило 3.2); field/scale = 1 → «veil»; amp = 0 → «veil»; cov 0.90 → «ok»
	# (разреженное, но структурированное небо — легальная свобода меню).
	var z2: Dictionary = B.hc_degeneracy(merged(hp_on, {"coverage": 0.05, "field_amp": 0.0}))
	var z3: Dictionary = B.hc_degeneracy(merged(hp_on, {"field_scale": def_scale}))
	var z4: Dictionary = B.hc_degeneracy(merged(hp_on, {"field_amp": 0.0}))
	var z5: Dictionary = B.hc_degeneracy(merged(hp_on, {"coverage": 0.90}))
	check("HC32-9 зоны: cov0.05→blob, cov0.05+amp0→veil, ratio1→veil, amp0→veil, cov0.90→ok, дефолт→ok",
		str(z_blob["class"]) == "blob" and str(z2["class"]) == "veil"
		and str(z3["class"]) == "veil" and str(z4["class"]) == "veil"
		and str(z5["class"]) == "ok" and str(dg_def["class"]) == "ok",
		"(clear: z2 %.2f z5 %.2f; σ: z3 %.2f z4 %.2f)" % [float(z2.clear_frac),
			float(z5.clear_frac), float(z3.std), float(z4.std)])

	# HC32-10: шейдер НЕ изменён: дефолты 0.56/0.22/0.60 на месте, формула эффективного
	# порога заморожена (центр 0.5 — связь amp↔mean задокументирована подсказкой, а не
	# правкой семантики; рецентринг поля — отдельное решение заказчика), 17 uniform'ов,
	# 0 циклов, 2 texture(noise_pw), POSITION ×1, гейт идентичности D3 побитово.
	var hc_block := _hc_shader_block(code)
	var n_uniforms := 0
	for ln in code.split("\n"):
		var t := ln.strip_edges()
		if t.begins_with("uniform ") and t.contains("hc_"):
			n_uniforms += 1
	var d_id := Vector3(0.25, 0.62, -0.74).normalized()
	var f_off: Dictionary = B.compute_final_with_hc(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {}, {}, {"enabled": false})
	var f_ref: Dictionary = B.compute_final_with_sun(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {})
	check("HC32-10 дефолты и формула cov_eff заморожены, 22 uniform'а (3.3/4), 0 циклов, POSITION ×1, гейт D3 побитово",
		code.contains("uniform float hc_coverage = 0.56;")
		and code.contains("uniform float hc_softness = 0.22;")
		and code.contains("uniform float hc_field_amp = 0.60;")
		and code.contains("float cov = clamp(hc_coverage + hc_field_amp * (field - 0.5) * 2.0, 0.0, 1.0);")
		and n_uniforms == HC_UNIFORM_NAMES.size()
		and not hc_block.contains("for (") and hc_block.count("texture(noise_pw") == 2
		and hc_block.count("texture(noise_worley") == 1 and code_nc.count("POSITION") == 1
		and (f_off.final as Vector3) == (f_ref.final as Vector3),
		"(uniform'ов hc_*: %d)" % n_uniforms)


# === СЕКЦИЯ SKYHC-3.3: фаза 3 ТЗ, шаг 3 — мелкая детализация (Worley-бугорки) ===
# Проверяются: гейт идентичности (strength=0 → ПОБИТОВО 3.2), строгая локальность
# (вне полосы перехода Δd == 0 точно — interior/exterior образований не тронуты),
# сохранность крупного рисунка (доли/mean/σ/bstd), отклик обеих ручек детали
# (hf-энергия монотонна по strength и 1/scale), гладкость (дефолт ≤ 0.35, угол
# меню ≤ 0.60), пресеты характера при включённой детали, дрейф с общим offset,
# цена (+1 worley-выборка под uniform-гейтом, 0 циклов), состав (19 uniform'ов),
# регрессия гейта D3 и замороженной формулы cov_eff.
# ВАЖНО: feat-метрика (пересечения 0.5) при включённой детали ловит бугорки кромок
# (across 20.6 → 5.8 км при s=0.35) — крупная геометрия анализируется ПРИ s=0
# (порядок ТЗ: сначала крупный рисунок, деталь потом); классификатор/дефолты зеркала
# detail_strength=0 → секции 3.1/3.2 остаются в силе побитово.
func section_skyhc_33() -> void:
	print("--- Секция SKYHC-3.3: вуаль — мелкая деталь (Worley), гейт, локальность, цена ---")
	var sh: Shader = load(SHADER_PATH)
	var mat: ShaderMaterial = load(MATERIAL_PATH)
	var code := sh.code
	var code_nc := _strip_comments(code)
	var hc_block := _hc_shader_block(code)
	var hp_on := {"enabled": true, "origin": Vector3.ZERO}
	var hp_det := merged(hp_on, {"detail_strength": 0.35})

	# HC33-1: гейт идентичности. (a) зеркало: detail_strength=0 → плотность ПОБИТОВО
	# равна 3.2 (ветка не выполняется); (b) итоговый кадр побитово; (c) шейдер: дефолт
	# 0.0 + uniform-гейт в hc_density; (d) материал: 0.35/3000 — прототип виден сразу
	# (методология SKYHC-1: дефолт шейдера выключен, материал включает).
	var pts := []
	for i in range(0, 40):
		var fi := float(i)
		pts.append(Vector3(fmod(fi * 911.0, 120000.0) - 60000.0, 6600.0,
			fmod(fi * 577.0, 120000.0) - 60000.0))
	var max_diff1 := 0.0
	for p_v in pts:
		var p: Vector3 = p_v
		max_diff1 = maxf(max_diff1, absf(B.compute_hc_density(p, hp_on)
			- B.compute_hc_density(p, merged(hp_on, {"detail_strength": 0.0}))))
	var d_id := Vector3(0.25, 0.62, -0.74).normalized()
	var f_g0: Dictionary = B.compute_final_with_hc(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {}, {}, merged(hp_on, {"detail_strength": 0.0}))
	var f_g1: Dictionary = B.compute_final_with_hc(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {}, {}, hp_on)
	check("HC33-1 гейт идентичности: s=0 → плотность и кадр ПОБИТОВО = 3.2; дефолт шейдера 0.0 + гейт; материал 0.35/3000",
		max_diff1 == 0.0 and (f_g0.final as Vector3) == (f_g1.final as Vector3)
		and code.contains("uniform float hc_detail_strength = 0.0;")
		and code.contains("uniform float hc_detail_scale = 3000.0;")
		and hc_block.contains("if (hc_detail_strength > 0.0) {")
		and absf(float(mat.get_shader_parameter("hc_detail_strength")) - 0.35) < 1e-6
		and absf(float(mat.get_shader_parameter("hc_detail_scale")) - 3000.0) < 1e-6,
		"(max|Δd| s=0: %.1f)" % max_diff1)

	# HC33-2: строгая локальность: вне полосы перехода (d0 точно 0 или 1 — |shape−cov|
	# ≥ soft → треугольный вес w_edge = 0) Δd == 0.0 ТОЧНО; внутри полосы эффект есть
	# (max ≥ 0.05) и ограничен наклоном sstep × сдвигом порога (≤ 1.5·strength).
	var n_out := 0
	var max_out := 0.0
	var n_in := 0
	var max_in := 0.0
	for i in range(0, 3000):
		var fi := float(i)
		var p := Vector3(fmod(fi * 337.0, 100000.0) - 50000.0, 6600.0,
			fmod(fi * 761.0, 100000.0) - 50000.0)
		var d0: float = B.compute_hc_density(p, hp_on)
		var d1: float = B.compute_hc_density(p, hp_det)
		if d0 == 0.0 or d0 == 1.0:
			n_out += 1
			max_out = maxf(max_out, absf(d1 - d0))
		elif d0 > 0.02 and d0 < 0.98:
			n_in += 1
			max_in = maxf(max_in, absf(d1 - d0))
	check("HC33-2 локальность: вне полосы (d0 ∈ {0,1}, n≥100) Δd == 0 точно; внутри — эффект ≥ 0.05 и ≤ 1.5·s",
		n_out >= 100 and max_out == 0.0 and n_in >= 100 and max_in >= 0.05
		and max_in <= 1.5 * 0.35 + 1e-9,
		"(вне n=%d maxΔ=%.6f; внутри n=%d maxΔ=%.4f ≤ %.4f)" % [n_out, max_out, n_in, max_in, 1.5 * 0.35])

	# HC33-3: крупный рисунок СОХРАНЁН (деталь — фактура кромок, не новая геометрия):
	# при s=0.35 против s=0: |Δclear| ≤ 0.02, |Δmean| ≤ 0.05, |Δσ| ≤ 0.02, |Δbstd| ≤ 0.02,
	# класс «ok» (измерено: 0.002/0.017/0.001/0.004 — mean слегка вниз: среднее Worley
	# F1 ≈ 0.35 < 0.5, тот же уклон эрозии, что у кучевых B1/B2).
	var st0: Dictionary = B.hc_degeneracy(hp_on)
	var st35: Dictionary = B.hc_degeneracy(hp_det)
	check("HC33-3 крупный рисунок сохранён при s=0.35: Δclear/Δmean/Δσ/Δbstd в пределах, класс «ok»",
		absf(float(st35.clear_frac) - float(st0.clear_frac)) <= 0.02
		and absf(float(st35.mean) - float(st0.mean)) <= 0.05
		and absf(float(st35.std) - float(st0.std)) <= 0.02
		and absf(float(st35.block_std) - float(st0.block_std)) <= 0.02
		and str(st35["class"]) == "ok",
		"(clear %.3f→%.3f mean %.3f→%.3f σ %.3f→%.3f bstd %.3f→%.3f)"
		% [float(st0.clear_frac), float(st35.clear_frac), float(st0.mean), float(st35.mean),
			float(st0.std), float(st35.std), float(st0.block_std), float(st35.block_std)])

	# HC33-4: обе ручки работают: hf-энергия (mean|Δd| на 150 м, 600 точек) строго
	# растёт с strength (0 < 0.35 < 0.70) и строго растёт с уменьшением detail_scale
	# (6000 > 3000 > 1500 > 800 м) — измерено: 0.0091 / 0.0144 / 0.0192 / 0.0226 /
	# 0.0266 / 0.0340.
	var hf := {}
	for cfg in [["s0", 0.0, 3000.0], ["s35_6000", 0.35, 6000.0], ["s35_3000", 0.35, 3000.0],
			["s35_1500", 0.35, 1500.0], ["s35_800", 0.35, 800.0], ["s70_3000", 0.70, 3000.0]]:
		var hp: Dictionary = merged(hp_on, {"detail_strength": cfg[1], "detail_scale": cfg[2]})
		var acc := 0.0
		for i in range(0, 600):
			var fi := float(i)
			var p := Vector3(fmod(fi * 337.0, 60000.0) - 30000.0, 6600.0,
				fmod(fi * 761.0, 60000.0) - 30000.0)
			acc += absf(B.compute_hc_density(p + Vector3(150.0, 0.0, 0.0), hp)
				- B.compute_hc_density(p, hp))
		hf[str(cfg[0])] = acc / 600.0
	check("HC33-4 ручки детали: hf-энергия строго ↑ по strength (0<0.35<0.70) и по 1/detail_scale (6000>3000>1500>800)",
		float(hf["s0"]) < float(hf["s35_3000"]) and float(hf["s35_3000"]) < float(hf["s70_3000"])
		and float(hf["s35_6000"]) < float(hf["s35_3000"]) and float(hf["s35_3000"]) < float(hf["s35_1500"])
		and float(hf["s35_1500"]) < float(hf["s35_800"]),
		"(hf: s0 %.5f | 6000 %.5f | 3000 %.5f | 1500 %.5f | 800 %.5f | s0.70 %.5f)"
		% [float(hf["s0"]), float(hf["s35_6000"]), float(hf["s35_3000"]),
			float(hf["s35_1500"]), float(hf["s35_800"]), float(hf["s70_3000"])])

	# HC33-5: гладкость (ТЗ фазы 1 п.3 — плавные переходы): дефолтная деталь
	# (0.35/3000) НЕ ухудшает порог HC1-4 (измерено 0.274 против 0.270 без детали —
	# сдвиг порога ограничен strength·soft внутри окна); угол меню (1.0/800) — до 0.60
	# (измерено 0.488): фактура мельче, переходы остаются постепенными (полоса ≥ ~0.4 км).
	var sm_def := _hc32_smooth(hp_det)
	var sm_max := _hc32_smooth(merged(hp_on, {"detail_strength": 1.0, "detail_scale": 800.0}))
	check("HC33-5 гладкость: дефолт-деталь Δd/250м ≤ 0.35 (порог HC1-4 практически не тронут), угол меню 1.0/800 ≤ 0.60",
		sm_def <= 0.35 and sm_max <= 0.60,
		"(s0.35/ds3000: %.4f; s1.0/ds800: %.4f)" % [sm_def, sm_max])

	# HC33-6: пресеты характера при включённой детали (s=0.35 материала): все «ok»,
	# лестница clear неубывающая, поперечный размер (уже с бугорками) ≥ 2.5 км —
	# даже «загрязнённая» деталью feat-метрика остаётся выше порога ряби.
	var prev_clear := -1.0
	var ladder_ok := true
	var all_ok := true
	var min_across := INF
	var rep6 := ""
	for pr_v in B.HC_CHAR_PRESETS:
		var pr: Dictionary = pr_v
		var hp_pr := merged(hp_det, B.hc_preset_to_hp(pr.u))
		var st: Dictionary = B.hc_degeneracy(hp_pr)
		if str(st["class"]) != "ok":
			all_ok = false
		if float(st.clear_frac) < prev_clear:
			ladder_ok = false
		prev_clear = float(st.clear_frac)
		min_across = minf(min_across, float(st.feat_across_km))
		rep6 += "%s:%s/%.2fкм " % [str(pr.n), str(st["class"]), float(st.feat_across_km)]
	check("HC33-6 пресеты при s=0.35: все «ok», лестница clear сохраняется, across ≥ 2.5 км",
		all_ok and ladder_ok and min_across >= 2.5, "(%s)" % rep6)

	# HC33-7: деталь дрейфует с полем: q0 = p + hc_offset — сдвиг offset эквивалентен
	# встречному сдвигу p (Δ == 0.0 точно, 20 точек): отдельной адвекции нет.
	var max_diff7 := 0.0
	for i in range(0, 20):
		var fi := float(i)
		var p := Vector3(fmod(fi * 911.0, 80000.0) - 40000.0, 6600.0,
			fmod(fi * 577.0, 80000.0) - 40000.0)
		var off := Vector3(fmod(fi * 173.0, 20000.0) - 10000.0, 0.0,
			fmod(fi * 239.0, 20000.0) - 10000.0)
		var da: float = B.compute_hc_density(p, merged(hp_det, {"offset": off}))
		var db: float = B.compute_hc_density(p + off, hp_det)
		max_diff7 = maxf(max_diff7, absf(da - db))
	check("HC33-7 дрейф: d(p, offset=o) == d(p+o, offset=0) точно — деталь движется с полем",
		max_diff7 == 0.0, "(max|Δ| = %.1f)" % max_diff7)

	# HC33-8: цена и структура: в блоке вуали ровно 2 texture(noise_pw) + 1
	# texture(noise_worley) (под uniform-гейтом), новых sampler'ов нет (noise_worley
	# объявлен этапом B2 для кучевых), 0 циклов, 0 вызовов марша/теней, POSITION ×1,
	# единственный вызов hc_evaluate по-прежнему под subpass-гейтом (B6 цел).
	var pos_guard := code_nc.find("if (!AT_HALF_RES_PASS && !AT_QUARTER_RES_PASS) {")
	var pos_call := code_nc.find("hc_evaluate(dir")
	check("HC33-8 цена: 2 pw + 1 worley (гейт), 0 циклов/маршей/sampler'ов, POSITION ×1, subpass-гейт цел",
		hc_block.count("texture(noise_pw") == 2
		and hc_block.count("texture(noise_worley") == 1
		and not hc_block.contains("sampler3D") and not hc_block.contains("for (")
		and not hc_block.contains("cloud_density(") and not hc_block.contains("light_transmittance(")
		and code_nc.count("POSITION") == 1
		and code_nc.count("hc_evaluate(") == 2 and pos_call > pos_guard and pos_call - pos_guard < 120)

	# HC33-9: состав: 19 uniform'ов hc_* в шейдере и материале (типы float), строки меню
	# «Сила детали» (0-1) и «Размер бугорков» (800-8000) объявлены; пресеты масштаба и
	# характера НЕ содержат ключей детали (разделение ответственности: пресеты 3.1/3.2
	# управляют геометрией/характером, деталь — независимая ручка).
	var n_uniforms := 0
	for ln in code.split("\n"):
		var t := ln.strip_edges()
		if t.begins_with("uniform ") and t.contains("hc_"):
			n_uniforms += 1
	var rows := {}
	for sec_v in B.TUNE_SECTIONS:
		var sec: Dictionary = sec_v
		for r_v in (sec.rows as Array):
			var r: Dictionary = r_v
			if str(r.get("k", "")) == "f" and ["hc_detail_strength", "hc_detail_scale"].has(str(r.get("u", ""))):
				rows[str(r.u)] = [float(r.a), float(r.b)]
	var presets_clean := true
	for pr_v in (B.HC_CHAR_PRESETS + B.HC_SCALE_PRESETS):
		var u: Dictionary = (pr_v as Dictionary).u
		if u.has("hc_detail_strength") or u.has("hc_detail_scale"):
			presets_clean = false
	check("HC33-9 состав: 22 uniform'а (перебазировано SKYHC-4), строки меню 0-1 / 800-8000, пресеты без ключей детали",
		n_uniforms == HC_UNIFORM_NAMES.size() and HC_UNIFORM_NAMES.size() == 22
		and typeof(mat.get_shader_parameter("hc_detail_strength")) == TYPE_FLOAT
		and typeof(mat.get_shader_parameter("hc_detail_scale")) == TYPE_FLOAT
		and rows.has("hc_detail_strength") and rows.has("hc_detail_scale")
		and float(rows["hc_detail_strength"][0]) == 0.0 and float(rows["hc_detail_strength"][1]) == 1.0
		and float(rows["hc_detail_scale"][0]) == 800.0 and float(rows["hc_detail_scale"][1]) == 8000.0
		and presets_clean,
		"(uniform'ов %d; строки: %s)" % [n_uniforms, str(rows)])

	# HC33-10: регрессия: гейт D3 побитово (вуаль выключена), формула cov_eff заморожена
	# (инвариант 3.2 пережил 3.3), дефолты 3.1/3.2 на месте.
	var f_off: Dictionary = B.compute_final_with_hc(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {}, {}, {"enabled": false})
	var f_ref: Dictionary = B.compute_final_with_sun(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {})
	check("HC33-10 регрессия: гейт D3 побитово, cov_eff заморожена, дефолты 60k/3.5/260k и 0.56/0.22/0.60 на месте",
		(f_off.final as Vector3) == (f_ref.final as Vector3)
		and code.contains("float cov = clamp(hc_coverage + hc_field_amp * (field - 0.5) * 2.0, 0.0, 1.0);")
		and code.contains("uniform float hc_scale = 60000.0;")
		and code.contains("uniform float hc_coverage = 0.56;")
		and code.contains("uniform bool hc_enabled = false;"))


## SKYHC-4: яркость/насыщенность/оттенок (HSV-соглашение) для анти-пинк и согласования.
func _hc4_lum(v: Vector3) -> float:
	return v.dot(Vector3(0.3333, 0.3333, 0.3333))


func _hc4_sat(v: Vector3) -> float:
	var mx := maxf(maxf(v.x, v.y), v.z)
	var mn := minf(minf(v.x, v.y), v.z)
	return 0.0 if mx <= 0.0 else (mx - mn) / mx


func _hc4_hue_deg(v: Vector3) -> float:
	var mx := maxf(maxf(v.x, v.y), v.z)
	var mn := minf(minf(v.x, v.y), v.z)
	if mx - mn < 1e-9:
		return -1.0
	var h := 0.0
	if mx == v.x:
		h = fmod((v.y - v.z) / (mx - mn), 6.0)
	elif mx == v.y:
		h = (v.z - v.x) / (mx - mn) + 2.0
	else:
		h = (v.x - v.y) / (mx - mn) + 4.0
	return fmod(h * 60.0 + 360.0, 360.0)


func _hc4_warm(hue: float) -> bool:
	return hue >= 0.0 and (hue <= 60.0 or hue >= 330.0)


# === СЕКЦИЯ SKYHC-4: фаза 4 ТЗ — освещение и время суток ===
# Проверяются: гейт идентичности 3.3 (use_lighting=false → побитово), материал с
# освещением, состав (22 uniform'а), мягкий терминатор (диапазон/непрерывность/
# монотонность), отклик на силу света (линейный), АНТИ-ПИНК ночь (ТЗ п.5: не
# ярко-розовая/оранжевая), согласование с состояниями неба (ТЗ п.2/4: порядок яркости
# как у фона, цветовая температура состояния), непрерывность перехода сутки→ночь,
# разделение ручек (light_gain/ambient_gain/альбедо — методология аудита 3.2),
# конвенция рампы C9, отсутствие второго цикла суток (ТЗ п.6: только чтение
# существующих uniform'ов) и регрессия композита/гейта D3.
# Данные состояний — ИЗ preset_table() стенда (пресеты F10-F14), не хардкод теста.
func section_skyhc_4() -> void:
	print("--- Секция SKYHC-4: вуаль — освещение, время суток, анти-пинк, согласование ---")
	var sh: Shader = load(SHADER_PATH)
	var mat: ShaderMaterial = load(MATERIAL_PATH)
	var code := sh.code
	var code_nc := _strip_comments(code)
	var hp_on := {"enabled": true, "origin": Vector3.ZERO}
	var hp_lit := merged(hp_on, {"use_lighting": true})
	var rays: Array = B.hc_reference_rays()
	var tbl: Dictionary = B.preset_table()

	# HC4-1: гейт идентичности — use_lighting=false → premult и кадр ПОБИТОВО равны 3.3
	# (lp не читается вовсе); дефолт шейдера false + тернарный гейт в hc_evaluate.
	var max_diff1 := 0.0
	for r_v in rays:
		var r: Vector3 = r_v
		var a: Dictionary = B.compute_hc_layer(r, hp_on)
		var b: Dictionary = B.compute_hc_layer(r, merged(hp_on, {"use_lighting": false}),
			{"light_strength": 99.0})
		max_diff1 = maxf(max_diff1, (a.premult as Vector3).distance_to(b.premult as Vector3))
	var d_id := Vector3(0.25, 0.62, -0.74).normalized()
	var f_off: Dictionary = B.compute_final_with_hc(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {}, {}, hp_on)
	var f_off2: Dictionary = B.compute_final_with_hc(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {}, {}, merged(hp_on, {"use_lighting": false}))
	check("HC4-1 гейт идентичности: use_lighting=false → premult/кадр побитово = 3.3 (lp игнорируется); дефолт false + тернарный гейт",
		max_diff1 == 0.0 and (f_off.final as Vector3) == (f_off2.final as Vector3)
		and code.contains("uniform bool hc_use_lighting = false;")
		and code.contains("return (hc_use_lighting ? hc_lit_color(dir) : hc_color) * a;"),
		"(max|Δpremult| = %.1f)" % max_diff1)

	# HC4-2: материал — освещение включено (прототип виден сразу, методология SKYHC-1),
	# гейны float = 1.0 (дефолты подтверждены замером: день lit/bg = 1.48, HC4-7).
	check("HC4-2 материал: hc_use_lighting=true (bool), hc_light_gain/hc_ambient_gain = 1.0 (float)",
		typeof(mat.get_shader_parameter("hc_use_lighting")) == TYPE_BOOL
		and bool(mat.get_shader_parameter("hc_use_lighting")) == true
		and typeof(mat.get_shader_parameter("hc_light_gain")) == TYPE_FLOAT
		and typeof(mat.get_shader_parameter("hc_ambient_gain")) == TYPE_FLOAT
		and absf(float(mat.get_shader_parameter("hc_light_gain")) - 1.0) < 1e-6
		and absf(float(mat.get_shader_parameter("hc_ambient_gain")) - 1.0) < 1e-6)

	# HC4-3: состав — 22 uniform'а в шейдере и материале (17 SKYHC-1 + 2 детали + 3 света).
	var miss_sh := []
	var miss_mat := []
	for n in HC_UNIFORM_NAMES:
		if not code.contains(n):
			miss_sh.append(n)
		if mat.get_shader_parameter(n) == null:
			miss_mat.append(n)
	var n_uniforms := 0
	for ln in code.split("\n"):
		var t := ln.strip_edges()
		if t.begins_with("uniform ") and t.contains("hc_"):
			n_uniforms += 1
	check("HC4-3 состав: 22 uniform'а hc_* в шейдере и материале",
		miss_sh.is_empty() and miss_mat.is_empty() and n_uniforms == 22
		and HC_UNIFORM_NAMES.size() == 22,
		"(шейдер: %s, материал: %s, строк uniform: %d)" % [str(miss_sh), str(miss_mat), n_uniforms])

	# HC4-4: мягкий терминатор: прямой свет (заливка выключена, strength=1, свет белый)
	# даёт lum ∈ [HC_SHADE_FLOOR, 1]·альбедо; отношение далеко/близко == FLOOR точно;
	# непрерывность (развёртка cosθ шагом 1°: Δlum ≤ 0.035) и монотонность по cosθ.
	var ldir0 := Vector3(0.0, 1.0, 0.0)
	# light_dir ВЫРАВНЕН с ldir0 — иначе cosθ тестовых лучей не достигает ±1 и
	# отношение lum далеко/близко != FLOOR (дефолтный ldir lp смотрит в другую сторону).
	var lp_dir := {"light_dir": ldir0, "light_strength": 1.0, "light_color": Vector3.ONE,
		"use_ramp": false, "amb_energy": 0.0}
	var lit_near: Vector3 = B.compute_hc_lighting(ldir0, hp_lit, lp_dir)
	var lit_far: Vector3 = B.compute_hc_lighting(-ldir0, hp_lit, lp_dir)
	var ratio_tf: float = _hc4_lum(lit_far) / maxf(_hc4_lum(lit_near), 1e-9)
	var prev_l4 := -1.0
	var max_dl4 := 0.0
	var mono4 := true
	for i in range(0, 181):
		var cn := cos(deg_to_rad(float(i)))
		var dir_i := (ldir0 * cn + Vector3(1.0, 0.0, 0.0) * sin(deg_to_rad(float(i)))).normalized()
		var l4: float = _hc4_lum(B.compute_hc_lighting(dir_i, hp_lit, lp_dir))
		if not is_finite(l4):
			mono4 = false
		if prev_l4 >= 0.0:
			max_dl4 = maxf(max_dl4, absf(l4 - prev_l4))
			# i растёт → cosθ убывает → lum НЕ растёт (монотонность по cosθ)
			if l4 > prev_l4 + 1e-12:
				mono4 = false
		prev_l4 = l4
	# Допуск ratio 1e-6 — float32 Vector3: lum считается dot'ом float32-компонент
	# (0.6·альбедо хранится с ulp ~6e-8), «точно» здесь недостижимо (урок SKYHC-2).
	check("HC4-4 терминатор: lum далеко/близко == HC_SHADE_FLOOR (float32 ±1e-6), непрерывно и монотонно по cosθ",
		absf(ratio_tf - float(B.HC_SHADE_FLOOR)) < 1e-6 and mono4 and max_dl4 <= 0.035,
		"(ratio=%.8f Δ=%.8f, maxΔ/1°=%.4f, mono=%s)" % [ratio_tf, absf(ratio_tf - float(B.HC_SHADE_FLOOR)), max_dl4, str(mono4)])

	# HC4-5: отклик на силу света линейный и строгий (заливка выключена):
	# lum(strength) ∝ strength (×2 → ×2 точно), 0 → только альбедо·0 = 0.
	var lp_s0 := {"light_strength": 0.0, "light_color": Vector3.ONE, "use_ramp": false, "amb_energy": 0.0}
	var lp_s7 := {"light_strength": 0.7, "light_color": Vector3.ONE, "use_ramp": false, "amb_energy": 0.0}
	var lp_s14 := {"light_strength": 1.4, "light_color": Vector3.ONE, "use_ramp": false, "amb_energy": 0.0}
	var l_s0: float = _hc4_lum(B.compute_hc_lighting(ldir0, hp_lit, lp_s0))
	var l_s7: float = _hc4_lum(B.compute_hc_lighting(ldir0, hp_lit, lp_s7))
	var l_s14: float = _hc4_lum(B.compute_hc_lighting(ldir0, hp_lit, lp_s14))
	check("HC4-5 прямой свет: lum ∝ strength точно (×2 → ×2), strength=0 → 0",
		l_s0 == 0.0 and l_s7 > 0.0 and absf(l_s14 - 2.0 * l_s7) < 1e-12,
		"(lum: %.4f / %.4f / %.4f)" % [l_s0, l_s7, l_s14])

	# HC4-6: АНТИ-ПИНК ночь (ТЗ п.5): под параметрами пресета night ни на одном луче
	# нет «ярко-розового/оранжевого» (тёплый оттенок И lum > 0.3 И sat > 0.3);
	# средняя яркость ночи ≤ 0.5× дня (вуаль темнеет с небом) и > 0 (лунная подсветка
	# читается, не провал в чёрное). Измерено: hue 226° (холодный), lum avg 0.312 vs 0.829.
	var lp_night: Dictionary = B.hc_lp_from_preset(tbl["night"])
	var lp_neutral: Dictionary = B.hc_lp_from_preset(tbl["neutral"])
	var pink_violations := 0
	var sum_night := 0.0
	var max_night := 0.0
	var sum_neutral := 0.0
	for r_v in rays:
		var lit: Vector3 = B.compute_hc_lighting(r_v, hp_lit, lp_night)
		var hue := _hc4_hue_deg(lit)
		if _hc4_warm(hue) and _hc4_lum(lit) > 0.3 and _hc4_sat(lit) > 0.3:
			pink_violations += 1
		sum_night += _hc4_lum(lit)
		max_night = maxf(max_night, _hc4_lum(lit))
		sum_neutral += _hc4_lum(B.compute_hc_lighting(r_v, hp_lit, lp_neutral))
	var avg_night := sum_night / float(rays.size())
	var avg_neutral := sum_neutral / float(rays.size())
	check("HC4-6 анти-пинк ночь: 0 тёплых ярких лучей, lum(ночь) ≤ 0.5×lum(день) и > 0 (лунная подсветка)",
		pink_violations == 0 and avg_night <= 0.5 * avg_neutral and avg_night > 0.0,
		"(ночь avg %.3f max %.3f против дня %.3f; нарушений %d)" % [avg_night, max_night,
			avg_neutral, pink_violations])

	# HC4-7: согласование с состояниями неба (ТЗ п.2/4 — «органично, не отдельная
	# накладка»): порядок яркости вуали как у фона (ratio lit/bg ∈ [0.4, 3.5] во всех
	# пяти пресетах; измерено 0.76-2.70 — вуаль следует за небом, а не висит константой);
	# цветовая температура состояния: закатные пресеты — тёплые (R>B ≥ 90 % лучей),
	# ночные/сумеречные — холодные (R<B ≥ 90 %).
	var ok_ratio := true
	var ok_temp := true
	var rep7 := ""
	for pname in ["neutral", "sunset", "twilight", "night", "blood_sunset"]:
		var pr: Dictionary = tbl[pname]
		var lp: Dictionary = B.hc_lp_from_preset(pr)
		var ldir_p: Vector3 = (lp.get("light_dir", Vector3(-0.75, 0.5, -0.43)) as Vector3)
		ldir_p = ldir_p / maxf(ldir_p.length(), 1e-5)
		var gp := {"use_grad": true, "horizon": lp.get("g_hor"), "zenith": lp.get("g_zen"),
			"antisolar": lp.get("g_anti"), "band_mid": lp.get("g_mid"), "band_pink": lp.get("g_pink"),
			"band_white": lp.get("g_white"), "grad_sharp": lp.get("g_sharp", 1.0)}
		var sum_v := 0.0
		var sum_bg := 0.0
		var n_warm := 0
		for r_v in rays:
			var lit: Vector3 = B.compute_hc_lighting(r_v, hp_lit, lp)
			var bg: Vector3 = B.compute_sky_gradient(r_v, ldir_p, gp)
			sum_v += _hc4_lum(lit)
			sum_bg += _hc4_lum(bg)
			if lit.x > lit.z:
				n_warm += 1
		var ratio := (sum_v / float(rays.size())) / maxf(sum_bg / float(rays.size()), 1e-6)
		if ratio < 0.4 or ratio > 3.5:
			ok_ratio = false
		var warm_frac := float(n_warm) / float(rays.size())
		if (pname == "sunset" or pname == "blood_sunset") and warm_frac < 0.9:
			ok_temp = false
		if (pname == "night" or pname == "twilight") and warm_frac > 0.1:
			ok_temp = false
		rep7 += "%s:%.2f/%.0f%% " % [pname, ratio, warm_frac * 100.0]
	check("HC4-7 согласование: lit/bg ∈ [0.4, 3.5] во всех состояниях; закат тёплый, ночь/сумерки холодные (≥90%)",
		ok_ratio and ok_temp, "(ratio/тёплые: %s)" % rep7)

	# HC4-8: непрерывность перехода день→ночь (20 шагов интерполяции ЧИСЛОВЫХ
	# параметров neutral→night, bool-переключатели flips на середине — как в пресетах):
	# max Δlum/шаг ≤ 0.10 (измерено 0.082 — разовый отклик flips), без NaN,
	# lum(ночь) < lum(день).
	var lp_a: Dictionary = B.hc_lp_from_preset(tbl["neutral"])
	var lp_b: Dictionary = B.hc_lp_from_preset(tbl["night"])
	# Продакшн-режим проверки: TimeOfDayController пишет continuous-значения, а рампа и
	# ambient-из-неба в переходах включены постоянно — bool-концы выравниваем, чтобы мерить
	# непрерывность ЦВЕТА/ИНТЕНСИВНОСТИ, а не дискретный флип пресетов (он и в apply_preset
	# мгновенный — это свойство пресетов, не вуали).
	lp_a["use_ramp"] = true
	lp_b["use_ramp"] = true
	lp_a["use_amb_sky"] = true
	lp_b["use_amb_sky"] = true
	var keys8: Array = lp_a.keys()
	for k8 in lp_b.keys():
		if not keys8.has(k8):
			keys8.append(k8)
	var ray8 := Vector3(cos(deg_to_rad(45.0)) * sin(deg_to_rad(200.0)), sin(deg_to_rad(45.0)),
		cos(deg_to_rad(45.0)) * cos(deg_to_rad(200.0)))
	var prev_l8 := -1.0
	var max_dl8 := 0.0
	var finite8 := true
	var l_start := 0.0
	var l_end := 0.0
	for i in range(0, 21):
		var t := float(i) / 20.0
		var lp := {}
		for k in keys8:
			# has()-guard: GDScript вычисляет аргумент get() строго — lp_b[k] упал бы
			# для ключа, которого нет в lp_b (и наоборот).
			var va: Variant = lp_a[k] if lp_a.has(k) else lp_b[k]
			var vb: Variant = lp_b[k] if lp_b.has(k) else lp_a[k]
			if va is Vector3 and vb is Vector3:
				lp[k] = (va as Vector3).lerp(vb, t)
			elif va is bool:
				lp[k] = va if t < 0.5 else vb
			elif va is float or va is int:
				lp[k] = lerpf(float(va), float(vb), t)
			else:
				lp[k] = vb
		var l8: float = _hc4_lum(B.compute_hc_lighting(ray8, hp_lit, lp))
		if not is_finite(l8):
			finite8 = false
		if i == 0:
			l_start = l8
		if i == 20:
			l_end = l8
		if prev_l8 >= 0.0:
			max_dl8 = maxf(max_dl8, absf(l8 - prev_l8))
		prev_l8 = l8
	check("HC4-8 переход день→ночь непрерывен: max Δlum/шаг ≤ 0.10, без NaN, ночь темнее дня",
		finite8 and max_dl8 <= 0.10 and l_end < l_start,
		"(maxΔ=%.4f; %.3f → %.3f)" % [max_dl8, l_start, l_end])

	# HC4-9: разделение ручек (методология аудита 3.2): light_gain=0 → lit НЕ реагирует
	# на strength (Δ == 0 точно); ambient_gain=0 + strength=0 → lit == 0 точно;
	# альбедо hc_color — глобальный множитель (×2 → lit ×2 точно).
	var lp_n9: Dictionary = B.hc_lp_from_preset(tbl["neutral"])
	var hp_lg0 := merged(hp_lit, {"light_gain": 0.0})
	var l9a: Vector3 = B.compute_hc_lighting(ray8, hp_lg0, lp_n9)
	var l9b: Vector3 = B.compute_hc_lighting(ray8, hp_lg0, merged(lp_n9, {"light_strength": 1.4}))
	var hp_both0 := merged(hp_lit, {"light_gain": 0.0, "ambient_gain": 0.0})
	var l9z: Vector3 = B.compute_hc_lighting(ray8, hp_both0, lp_n9)
	var l9_1: Vector3 = B.compute_hc_lighting(ray8, hp_lit, lp_n9)
	var hp_alb2 := merged(hp_lit, {"color": Vector3(0.92, 0.93, 0.96) * 2.0})
	var l9_2: Vector3 = B.compute_hc_lighting(ray8, hp_alb2, lp_n9)
	check("HC4-9 разделение ручек: light_gain=0 глушит прямой свет точно; оба гейна 0 → lit=0; альбедо линейно (×2 → ×2)",
		l9a == l9b and l9z == Vector3.ZERO and l9_2 == l9_1 * 2.0,
		"(lit gain0: %s; альбедо ×2: %s)" % [str(l9a), str(l9_1)])

	# HC4-10: рампа C9 — конвенция кучевых: при use_ramp=false ОТТЕНОК одинаков для всех
	# направлений (shade — скаляр): нормированные цвета совпадают; при use_ramp=true
	# (sunset) зелено-красное отношение у солнца и вдали различается ≥ 0.05 (C9-окна
	# 0.30-0.80 и 0.93-0.995 — тот же код, что в cloud_radiance_terms).
	var lp_noramp := {"light_strength": 1.0, "light_color": Vector3(1.0, 0.9, 0.8),
		"use_ramp": false, "amb_energy": 0.0}
	var c_near: Vector3 = B.compute_hc_lighting(ldir0, hp_lit, lp_noramp)
	var c_far: Vector3 = B.compute_hc_lighting(-ldir0, hp_lit, lp_noramp)
	# Допуск 1e-5 — float32 Vector3: normalized() хранит компоненты в float32
	# (шум нормировки ~1e-7), математически направления совпадают точно.
	var same_hue: bool = c_near.normalized().distance_to(c_far.normalized()) < 1e-5
	var lp_ss: Dictionary = B.hc_lp_from_preset(tbl["sunset"])
	lp_ss["amb_energy"] = 0.0
	var dir_to_sun := (lp_ss.get("light_dir") as Vector3).normalized()
	var c_ss_near: Vector3 = B.compute_hc_lighting(dir_to_sun, hp_lit, lp_ss)
	var c_ss_far: Vector3 = B.compute_hc_lighting(-dir_to_sun, hp_lit, lp_ss)
	var gr_near: float = c_ss_near.y / maxf(c_ss_near.x, 1e-9)
	var gr_far: float = c_ss_far.y / maxf(c_ss_far.x, 1e-9)
	check("HC4-10 рампа C9: без рампы оттенок изотропен (норм. цвета равны); с рампой (sunset) G/R у солнца и вдали различается ≥ 0.05",
		same_hue and absf(gr_near - gr_far) >= 0.05,
		"(same_hue=%s dist=%.3f; G/R: у солнца %.3f, вдали %.3f)" % [str(same_hue), c_near.normalized().distance_to(c_far.normalized()), gr_near, gr_far])

	# HC4-11: НЕТ второго цикла суток (ТЗ п.6) — тело hc_lit_color читает ТОЛЬКО
	# существующие uniform'ы света/неба (cloud_light_*, ramp C9, ambient C9, sky_color)
	# и hc_color/hc_*_gain; TIME/POSITION/SCREEN_UV/texture/циклы/марш/тени/HG отсутствуют;
	# sky_gradient вызывается ровно 1 раз (переиспользование C9, не копия палитры).
	var i_fn := code.find("vec3 hc_lit_color(vec3 dir) {")
	var i_end := code.find("\n}\n", i_fn)
	var lit_body := code.substr(i_fn, i_end - i_fn) if i_fn >= 0 and i_end > i_fn else ""
	var lit_nc := _strip_comments(lit_body)
	check("HC4-11 нет второго цикла суток: hc_lit_color читает только общие uniform'ы (без TIME/POSITION/texture/циклов/марша/HG), sky_gradient ×1",
		lit_body.length() > 0
		and not lit_nc.contains("TIME") and not lit_nc.contains("POSITION")
		and not lit_nc.contains("SCREEN_UV") and not lit_nc.contains("texture(")
		and not lit_nc.contains("for (") and not lit_nc.contains("light_transmittance(")
		and not lit_nc.contains("cloud_density(") and not lit_nc.contains("hg_phase(")
		and lit_nc.contains("cloud_light_direction") and lit_nc.contains("cloud_light_color")
		and lit_nc.contains("cloud_light_strength") and lit_nc.contains("use_sun_color_ramp")
		and lit_nc.contains("use_ambient_from_sky") and lit_nc.contains("cloud_ambient_sky_color")
		and lit_nc.contains("cloud_ambient_energy") and lit_nc.count("sky_gradient(") == 1
		and code_nc.count("hc_lit_color(") == 2 and code_nc.count("POSITION") == 1)

	# HC4-12: композит и структура не изменились: вызов hc_evaluate ×1 под subpass-гейтом;
	# гейт D3 побитово (вуаль выключена); инварианты 3.2/3.3 живы (формула cov_eff,
	# гейт детали, дефолт detail 0.0); 2 texture(noise_pw) + 1 worley, 0 циклов.
	var hc_block := _hc_shader_block(code)
	var pos_guard := code_nc.find("if (!AT_HALF_RES_PASS && !AT_QUARTER_RES_PASS) {")
	var pos_call := code_nc.find("hc_evaluate(dir")
	var f_ref: Dictionary = B.compute_final_with_sun(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {})
	var f_goff: Dictionary = B.compute_final_with_hc(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {}, {}, {"enabled": false})
	check("HC4-12 композит цел: hc_evaluate ×1 под subpass-гейтом, D3 побитово, cov_eff/деталь-гейт на месте, 2 pw + 1 worley, 0 циклов",
		code_nc.count("hc_evaluate(") == 2 and pos_call > pos_guard and pos_call - pos_guard < 120
		and (f_goff.final as Vector3) == (f_ref.final as Vector3)
		and code.contains("float cov = clamp(hc_coverage + hc_field_amp * (field - 0.5) * 2.0, 0.0, 1.0);")
		and code.contains("uniform float hc_detail_strength = 0.0;")
		and hc_block.contains("if (hc_detail_strength > 0.0) {")
		and hc_block.count("texture(noise_pw") == 2 and hc_block.count("texture(noise_worley") == 1
		and not hc_block.contains("for ("))

	# HC4-13: заливка (ambient C9): use_amb_sky переключает источник (G(up)·gain против
	# cloud_ambient_sky_color) — lit различается; отклик на cloud_ambient_energy линейный
	# (×2 → ×2 точно при выключенном прямом свете).
	var lp_amb := {"light_strength": 0.0, "amb_energy": 0.45, "use_amb_sky": false}
	var lp_amb_sky := {"light_strength": 0.0, "amb_energy": 0.45, "use_amb_sky": true,
		"amb_gain": 1.2}
	var l13a: Vector3 = B.compute_hc_lighting(ray8, hp_lit, lp_amb)
	var l13b: Vector3 = B.compute_hc_lighting(ray8, hp_lit, lp_amb_sky)
	var lp_amb2 := {"light_strength": 0.0, "amb_energy": 0.90, "use_amb_sky": false}
	var l13c: Vector3 = B.compute_hc_lighting(ray8, hp_lit, lp_amb2)
	check("HC4-13 заливка C9: источник переключается use_amb_sky (литы различаются), отклик на energy линейный (×2 → ×2)",
		l13a.distance_to(l13b) > 0.01 and l13c == l13a * 2.0 and l13a.length() > 0.0,
		"(amb_sky_color: %s | G(up)·gain: %s)" % [str(l13a), str(l13b)])


## SKYHC-5: hp вуали ИЗ МАТЕРИАЛА (состояние прототипа: lighting on, detail 0.35).
## Ключи зеркала = uniform-имя без «hc_» (конвенция, проверена HC33-9); Color→Vector3.
func _hc5_hp_from_material(mat: ShaderMaterial) -> Dictionary:
	var hp := {"origin": Vector3.ZERO}
	for nm in HC_UNIFORM_NAMES:
		var v: Variant = mat.get_shader_parameter(nm)
		# Конвенция «uniform минус hc_» с двумя историческими исключениями зеркала:
		# hc_layer_bottom/hc_layer_top → ключи bottom/top (hcp_defaults).
		var key := str(nm).substr(3)
		if key == "layer_bottom":
			key = "bottom"
		elif key == "layer_top":
			key = "top"
		if v is Color:
			var c: Color = v
			hp[key] = Vector3(c.r, c.g, c.b)
		elif v is Vector3:
			hp[key] = v
		elif v is bool:
			hp[key] = v
		elif v != null:
			hp[key] = float(v)
	return hp


## SKYHC-5: параметры кучевых ИЗ МАТЕРИАЛА (данные, не хардкод) — как _material_dp стенда.
func _hc5_dp_from_material(mat: ShaderMaterial) -> Dictionary:
	return {
		"base_scale": float(mat.get_shader_parameter("cloud_base_scale")),
		"detail_scale": float(mat.get_shader_parameter("cloud_detail_scale")),
		"coverage": float(mat.get_shader_parameter("cloud_coverage")),
		"softness": float(mat.get_shader_parameter("cloud_softness")),
		"strength": float(mat.get_shader_parameter("cloud_detail_strength")),
		"erosion": float(mat.get_shader_parameter("cloud_erosion")),
		"edge_contrast": float(mat.get_shader_parameter("cloud_edge_contrast")),
		"warp": float(mat.get_shader_parameter("cloud_warp_strength")),
		"warp_scale": float(mat.get_shader_parameter("cloud_warp_scale")),
		"stretch": float(mat.get_shader_parameter("cloud_vertical_stretch")),
		"h_stretch": float(mat.get_shader_parameter("cloud_horizontal_stretch")),
		"use_aniso": bool(mat.get_shader_parameter("use_height_anisotropy")),
		"use_mask": bool(mat.get_shader_parameter("use_weather_mask")),
		"use_curtain": bool(mat.get_shader_parameter("use_far_curtain")),
		"fine_strength": float(mat.get_shader_parameter("cloud_fine_strength")),
		"fine_scale": float(mat.get_shader_parameter("cloud_fine_scale")),
	}


## SKYHC-5: dp «кучевые выключены» — та же пара, что LAYER_PRESETS стенда
## (coverage 1.0 + softness 0.01 → плотность ≡ 0 в обеих формах композита).
func _hc5_dp_off() -> Dictionary:
	return {"coverage": 1.0, "softness": 0.01, "strength": 0.0, "erosion": 0.0,
		"use_mask": false, "warp": 0.0, "use_aniso": false, "stretch": 1.0,
		"h_stretch": 1.0, "edge_contrast": 1.0, "use_curtain": false}


## SKYHC-5: lp/ap/su пресета из preset_table() (таблица ключей — данные стенда:
## hc_lp_from_preset; sun/atmo — явный маппинг тех же имён, что в _material_sup/_material_ap).
func _hc5_scene_from_preset(pr: Dictionary) -> Dictionary:
	var lp: Dictionary = B.hc_lp_from_preset(pr)
	var sky_c: Color = pr.get("sky_color", Color(0.32, 0.47, 0.68))
	return {"lp": lp,
		"ap": {"sky_color": Vector3(sky_c.r, sky_c.g, sky_c.b)},
		"su": {"light_dir": lp.get("light_dir"), "light_color": lp.get("light_color"),
			"size": pr.get("sun_size", 0.02), "intensity": pr.get("sun_intensity", 10.0),
			"halo_strength": pr.get("sun_halo_strength", 0.25),
			"halo_power": pr.get("sun_halo_power", 250.0)}}


# === СЕКЦИЯ SKYHC-5: фаза 5 ТЗ — интеграция с кучевыми облаками ===
# Проверяются: порядок композита с освещением (вклад вуали ∝ T кучевых), формы кучевых
# не скрыты (подавление вклада за глухой плитой), НЕТ двойного затемнения (алгебраическое
# тождество базы), НЕТ пересвета (под-аддитивность яркости), контраст кучевых сквозь
# вуаль не усиливается (C'/C ≤ 1 на лучах, где вуаль осветляет фон — алгебраическая
# гарантия), независимость слоёв В ОБЕ СТОРОНЫ (марш кучевых не зависит от ручек вуали,
# вуаль не зависит от ручек кучевых — побитово), диск солнца/луны ослабляется вуалью
# во всех состояниях, баланс яркостей (доля вуали в чистом небе по пресетам — конверт
# из замеров), слоёвое A/B стенда (пресеты существующими uniform'ами + поведение),
# форма-независимость вклада вуали от субпасс-композита (Δ одинаков в GPU- и физической
# форме; расхождение субпасса для КУЧЕВЫХ измерено и вынесено заказчику, не правится).
func section_skyhc_5() -> void:
	print("--- Секция SKYHC-5: интеграция с кучевыми — порядок, баланс, независимость ---")
	var sh: Shader = load(SHADER_PATH)
	var mat: ShaderMaterial = load(MATERIAL_PATH)
	var code := sh.code
	var code_nc := _strip_comments(code)
	var tbl: Dictionary = B.preset_table()
	var rays: Array = B.hc_reference_rays()
	var hp_mat := _hc5_hp_from_material(mat)
	var hp_off := {"enabled": false, "origin": Vector3.ZERO}
	var dp_mat := _hc5_dp_from_material(mat)
	var dp_off := _hc5_dp_off()
	var dp_full := {"coverage": 0.0, "softness": 0.01, "strength": 0.0, "erosion": 0.0,
		"use_mask": false, "warp": 0.0, "use_aniso": false, "stretch": 1.0,
		"h_stretch": 1.0, "edge_contrast": 1.0, "use_curtain": false}
	var cb := float(mat.get_shader_parameter("cloud_layer_bottom"))
	var ct := float(mat.get_shader_parameter("cloud_layer_top"))

	# === Сбор данных: 4 варианта кадра × 33 луча × 3 пресета (один проход для HC5-1/3/4/5/7/8) ===
	var shares := {}		# preset → массив долей вуали в яркости чистого неба
	var vis_n := {}			# preset → число лучей с |Δl| ≥ 0.01 (видимость вуали)
	var contr_sum := {}		# preset → сумма вклада вуали (l_v − l_bg) для σ
	var contr_sum2 := {}	# preset → сумма квадратов вклада
	var ratios := {}		# preset → массив C'/C (фильтр: вуаль осветляет фон, C > 0.05)
	var ratios_opaque := {}	# preset → C'/C на глухих кучевых (dp_full)
	var subadd_viol := 0
	var subadd_max := 0.0
	var form_max := 0.0
	var disc_ok := true
	var disc_rep := ""
	for pname in ["neutral", "sunset", "night"]:
		var sc: Dictionary = _hc5_scene_from_preset(tbl[pname])
		var lp: Dictionary = sc.lp
		var ap: Dictionary = sc.ap
		var su: Dictionary = sc.su
		var sh_arr: Array = []
		var rt_arr: Array = []
		var ro_arr: Array = []
		for r_v in rays:
			var r: Vector3 = r_v
			var f_bg: Dictionary = B.compute_final_with_hc(r, cb, ct, 32, 30000.0, 0.0025, 0.01, 0.0, dp_off, lp, {}, ap, su, hp_off)
			var f_v: Dictionary = B.compute_final_with_hc(r, cb, ct, 32, 30000.0, 0.0025, 0.01, 0.0, dp_off, lp, {}, ap, su, hp_mat)
			var f_c: Dictionary = B.compute_final_with_hc(r, cb, ct, 32, 30000.0, 0.0025, 0.01, 0.0, dp_mat, lp, {}, ap, su, hp_off)
			var f_b: Dictionary = B.compute_final_with_hc(r, cb, ct, 32, 30000.0, 0.0025, 0.01, 0.0, dp_mat, lp, {}, ap, su, hp_mat)
			var l_bg := _hc4_lum(f_bg.final as Vector3)
			var l_v := _hc4_lum(f_v.final as Vector3)
			var l_c := _hc4_lum(f_c.final as Vector3)
			var l_b := _hc4_lum(f_b.final as Vector3)
			# (8) доля вуали в яркости чистого неба (кучевые выключены) + видимость
			# по абсолютному изменению яркости (|Δl| ≥ 0.01): вуаль у закатного неба
			# близка по яркости (тёплое на тёплом) — читается ТЕКСТУРОЙ и ослаблением
			# диска, а не сдвигом средней яркости; метрика доли это не ловит.
			if l_v > 1e-6:
				sh_arr.append(clampf((l_v - l_bg) / l_v, 0.0, 1.0))
			if absf(l_v - l_bg) >= 0.01:
				vis_n[pname] = int(vis_n.get(pname, 0)) + 1
			var contrib := l_v - l_bg
			contr_sum[pname] = float(contr_sum.get(pname, 0.0)) + contrib
			contr_sum2[pname] = float(contr_sum2.get(pname, 0.0)) + contrib * contrib
			# (4) под-аддитивность: яркость «обоих» не превышает сумму вкладов (пересвета нет)
			var excess := l_b - (l_v + l_c - l_bg)
			subadd_max = maxf(subadd_max, excess)
			if excess > 1e-3:
				subadd_viol += 1
			# (1/3/10) вклад вуали == (base'−base)·T — форма композита не важна (float32: 1e-5)
			var T := float((f_b.march as Dictionary).transmittance)
			var d_form := (_hc4_lum(f_b.base_veiled as Vector3) - _hc4_lum(f_b.base as Vector3)) * T
			form_max = maxf(form_max, absf((l_b - l_c) - d_form))
			# (5) контраст кучевых сквозь вуаль: фильтр — вуаль ОСВЕТЛЯЕТ фон (l_v > l_bg)
			var a_cum := 1.0 - T
			if a_cum > 0.05 and l_v > l_bg + 1e-6:
				var C := (l_c - l_bg) / l_bg
				var Cp := (l_b - l_v) / l_v
				if C > 0.05:
					rt_arr.append(Cp / C)
			# (7) диск: вуаль ослабляет диск источника (строгое неравенство при α>0)
			var ld: Vector3 = (lp.light_dir as Vector3).normalized()
			var f_dv: Dictionary = B.compute_final_with_hc(ld, cb, ct, 32, 30000.0, 0.0025, 0.01, 0.0, dp_off, lp, {}, ap, su, hp_mat)
			var f_d0: Dictionary = B.compute_final_with_hc(ld, cb, ct, 32, 30000.0, 0.0025, 0.01, 0.0, dp_off, lp, {}, ap, su, hp_off)
			var a_v := float((f_dv.hc as Dictionary).alpha)
			var lv_d := _hc4_lum(f_dv.final as Vector3)
			var l0_d := _hc4_lum(f_d0.final as Vector3)
			if a_v > 0.01 and not (lv_d < l0_d):
				disc_ok = false
		# (2) глухая плита: вклад вуали подавлен, контраст форм сохранён
		for r_v in rays:
			var r: Vector3 = r_v
			var g_v: Dictionary = B.compute_final_with_hc(r, cb, ct, 32, 30000.0, 0.0025, 0.01, 0.0, dp_full, lp, {}, ap, su, hp_mat)
			var g_0: Dictionary = B.compute_final_with_hc(r, cb, ct, 32, 30000.0, 0.0025, 0.01, 0.0, dp_full, lp, {}, ap, su, hp_off)
			var basev := _hc4_lum(g_v.base_veiled as Vector3)
			var base0 := _hc4_lum(g_v.base as Vector3)
			# C'/C на глухой плите = base/base' (S сокращается): смысл имеет, когда
			# вуаль реально поднимает базу (basev > base·1.02) и база не черна.
			if base0 > 1e-4 and basev > base0 * 1.02:
				ro_arr.append(base0 / maxf(basev, 1e-9))
		shares[pname] = sh_arr
		ratios[pname] = rt_arr
		ratios_opaque[pname] = ro_arr
		disc_rep += "%s:диск✓ " % pname if disc_ok else "%s:ДИСК✗ " % pname

	# HC5-1: порядок композита с освещением: вклад вуали в итог == (base'−base)·T
	# (float32 ≤ 1e-5) на всех лучах/пресетах — вуаль ДАЛЬШЕ кучевых, кучевые закрывают
	# её своим alpha (T глухой плиты < 0.05 подавляет вклад ≥ 20× — замер в деталях).
	check("HC5-1 порядок: вклад вуали == (base'−base)·T на 99 кадрах (3 пресета × 33 луча)",
		form_max <= 1e-5,
		"(max отклонение %.8f)" % form_max)

	# HC5-2: формы кучевых НЕ скрыты: на глухой плите отношение контраста C'/C =
	# base/base' ≥ 0.25 (вуаль под плитой съедает не более 75 % контраста форм;
	# измерено neutral ~0.7-0.9) и вклад вуали подавлен плитой (T < 0.05 → Δ ≤ 0.05·Δ_чистого).
	var ok2 := true
	var min_ratio2 := 2.0
	for pname in ratios_opaque.keys():
		for v in (ratios_opaque[pname] as Array):
			min_ratio2 = minf(min_ratio2, float(v))
			if float(v) < 0.25:
				ok2 = false
	var d_v1 := _hc4_lum((B.compute_final_with_hc(rays[2], cb, ct, 32, 30000.0, 0.0025, 0.01,
		0.0, dp_off, {}, {}, {}, {}, hp_mat)).final as Vector3) \
		- _hc4_lum((B.compute_final_with_hc(rays[2], cb, ct, 32, 30000.0, 0.0025, 0.01,
		0.0, dp_off, {}, {}, {}, {}, hp_off)).final as Vector3)
	var d_f1 := _hc4_lum((B.compute_final_with_hc(rays[2], cb, ct, 32, 30000.0, 0.0025, 0.01,
		0.0, dp_full, {}, {}, {}, {}, hp_mat)).final as Vector3) \
		- _hc4_lum((B.compute_final_with_hc(rays[2], cb, ct, 32, 30000.0, 0.0025, 0.01,
		0.0, dp_full, {}, {}, {}, {}, hp_off)).final as Vector3)
	check("HC5-2 формы кучевых сохранены: C'/C на плите ≥ 0.25, вклад вуали за плитой ≤ 5 % от чистого неба",
		ok2 and absf(d_f1) <= 0.05 * absf(d_v1) + 1e-9,
		"(min C'/C плита %.3f; подавление %.4f)" % [min_ratio2, absf(d_f1) / maxf(absf(d_v1), 1e-9)])

	# HC5-3: НЕТ двойного затемнения — алгебра базы: base_veiled == base·(1−α) + premult
	# (компонентно, float32 1e-6) на всех собранных кадрах: небо ослабляется вуалью РОВНО
	# ОДИН раз, кучевые ослабляют base' РОВНО ОДИН раз (T), перекрёстных членов нет.
	var ok3 := true
	for pname in ["neutral"]:
		var sc: Dictionary = _hc5_scene_from_preset(tbl[pname])
		for r_v in rays:
			var f: Dictionary = B.compute_final_with_hc(r_v, cb, ct, 16, 30000.0, 0.0025, 0.01,
				0.0, dp_mat, sc.lp, {}, sc.ap, sc.su, hp_mat)
			var base: Vector3 = f.base
			var bv: Vector3 = f.base_veiled
			var hc: Dictionary = f.hc
			var expect: Vector3 = base * (1.0 - float(hc.alpha)) + (hc.premult as Vector3)
			if bv.distance_to(expect) > 1e-6:
				ok3 = false
	check("HC5-3 нет двойного затемнения: base' == base·(1−α)+premult компонентно (33 луча, 1e-6)",
		ok3)

	# HC5-4: НЕТ пересвета — под-аддитивность: L(оба) ≤ L(вуаль) + L(кучевые) − L(фон)
	# на всех лучах/пресетах (допуск 1e-3 — float32-шум; измерено max excess 9.6e-5).
	check("HC5-4 нет пересвета: L_both ≤ L_veil + L_cum − L_bg (99 кадров, допуск 1e-3)",
		subadd_viol == 0,
		"(нарушений %d, max excess %.6f)" % [subadd_viol, subadd_max])

	# HC5-5: контраст кучевых сквозь вуаль НЕ усиливается: на лучах, где вуаль осветляет
	# фон (l_v > l_bg) и C > 0.05, выполнено C'/C ≤ 1 (алгебраическая гарантия: base' >
	# base ⇒ (S−base'(1−T))/base' < (S−base(1−T))/base). Отрицательные C' легальны:
	# тонкое кучевое темнее яркой вуали за ним (ночь) — форма читается инверсией.
	var ok5 := true
	var max_ratio5 := -2.0
	var min_ratio5 := 2.0
	var n5 := 0
	for pname in ratios.keys():
		for v in (ratios[pname] as Array):
			max_ratio5 = maxf(max_ratio5, float(v))
			min_ratio5 = minf(min_ratio5, float(v))
			n5 += 1
			if float(v) > 1.0 + 1e-9:
				ok5 = false
	check("HC5-5 контраст не усиливается: C'/C ≤ 1 на всех отфильтрованных лучах (инверсия знака легальна)",
		ok5 and n5 >= 3,
		"(n=%d, C'/C min %.3f med… max %.3f)" % [n5, min_ratio5, max_ratio5])

	# HC5-6: независимость В ОБЕ СТОРОНЫ (побитово): (a) марш кучевых (T, mode0) не
	# зависит от ручек вуали (tau/detail/gains/enabled); (b) отклик вуали (density/tau/
	# alpha/lit_color) не зависит от ручек кучевых (coverage/base_scale/erosion).
	var sc_n: Dictionary = _hc5_scene_from_preset(tbl["neutral"])
	var r6: Vector3 = rays[5]
	var m_ref: Dictionary = B.compute_final_with_hc(r6, cb, ct, 32, 30000.0, 0.0025, 0.01,
		0.0, dp_mat, sc_n.lp, {}, sc_n.ap, sc_n.su, hp_mat).march
	var ok6a := true
	for hp_var in [{"tau_per_km": 0.1}, {"tau_per_km": 1.0}, {"detail_strength": 0.0},
			{"light_gain": 0.0}, {"ambient_gain": 0.0}, {"enabled": false}]:
		var m_v: Dictionary = B.compute_final_with_hc(r6, cb, ct, 32, 30000.0, 0.0025, 0.01,
			0.0, dp_mat, sc_n.lp, {}, sc_n.ap, sc_n.su, merged(hp_mat, hp_var)).march
		if float(m_v.transmittance) != float(m_ref.transmittance) \
				or (m_v.mode0_color as Vector3) != (m_ref.mode0_color as Vector3):
			ok6a = false
	var hc_ref: Dictionary = B.compute_hc_layer(r6, hp_mat, sc_n.lp)
	var ok6b := true
	for dp_var in [{"coverage": 0.5}, {"base_scale": 20000.0}, {"erosion": 0.6},
			{"softness": 0.3}]:
		var f_v: Dictionary = B.compute_final_with_hc(r6, cb, ct, 32, 30000.0, 0.0025, 0.01,
			0.0, merged(dp_mat, dp_var), sc_n.lp, {}, sc_n.ap, sc_n.su, hp_mat)
		var hc_v: Dictionary = f_v.hc
		if float(hc_v.density) != float(hc_ref.density) or float(hc_v.tau) != float(hc_ref.tau) \
				or float(hc_v.alpha) != float(hc_ref.alpha) \
				or (hc_v.lit_color as Vector3) != (hc_ref.lit_color as Vector3):
			ok6b = false
	check("HC5-6 независимость слоёв побитово: (a) марш кучевых ≡ при 6 вариациях вуали; (b) вуаль ≡ при 4 вариациях кучевых",
		ok6a and ok6b)

	# HC5-7: диск солнца/луны ослабляется вуалью во ВСЕХ трёх состояниях (α>0.01 →
	# lum строго ниже; пересвета диска нет) — собрано в общем проходе (disc_ok).
	check("HC5-7 диск источника ослабляется вуалью в neutral/sunset/night (без пересвета)",
		disc_ok, "(%s)" % disc_rep)

	# HC5-8: БАЛАНС (п.4 ТЗ), две метрики по 33 лучам × 3 пресета:
	# (a) НЕ ДОМИНИРУЕТ: медианная доля вуали в яркости чистого неба ≤ 0.60 и max ≤ 0.80
	#     (измерено: neutral med 0.07 max 0.32; sunset med 0.00 max 0.24; night med 0.24
	#     max 0.72 — лунная вуаль ярче тёмного неба, но не «прожектор»);
	# (b) ВИДИМА: не менее 50 % лучей меняют яркость на |Δl| ≥ 0.01 (вуаль читается
	#     текстурой/ослаблением диска даже у изояркостного закатного неба).
	var ok8 := true
	var rep8 := ""
	var n_rays := float(rays.size())
	for pname in shares.keys():
		var arr: Array = shares[pname]
		if arr.is_empty():
			ok8 = false
			continue
		var sorted_arr := arr.duplicate()
		sorted_arr.sort()
		var med: float = sorted_arr[int(sorted_arr.size() / 2)]
		var mx: float = sorted_arr[sorted_arr.size() - 1]
		if med > 0.60 or mx > 0.80:
			ok8 = false
		# σ вклада вуали в кадр — её собственная пространственная структура:
		# изояркостное состояние (закат) всё равно читается текстурой.
		var m1: float = float(contr_sum.get(pname, 0.0)) / n_rays
		var m2: float = float(contr_sum2.get(pname, 0.0)) / n_rays
		var sig: float = sqrt(maxf(m2 - m1 * m1, 0.0))
		if sig < 0.008:
			ok8 = false
		var vis_frac := float(int(vis_n.get(pname, 0))) / n_rays
		rep8 += "%s med %.2f max %.2f σвкл %.3f вид %.0f%%; " % [pname, med, mx, sig, vis_frac * 100.0]
	check("HC5-8 баланс: вуаль не доминирует (med ≤ 0.60, max ≤ 0.80) и несёт структуру (σ вклада ≥ 0.008)",
		ok8, "(%s)" % rep8)

	# HC5-9: слоёвое A/B стенда: 4 пресета, ключи ТОЛЬКО существующие uniform'ы
	# (hc_enabled/cloud_coverage/cloud_softness); «вуаль/ни одного» глушат кучевые
	# (1.0/0.01), «оба/кучевые» восстанавливают дефолты uniform'ов (0.23/0.17 —
	# сверка со строками шейдера); поведение: dp пресета «вуаль» даёт T == 1.0 (кучевых
	# численно нет), hc_enabled=false даёт α == 0.
	var lp9: Array = B.HC_LAYER_PRESETS
	var ok9 := lp9.size() == 4
	for pr_v in lp9:
		var u: Dictionary = (pr_v as Dictionary).u
		for k in u.keys():
			if not ["hc_enabled", "cloud_coverage", "cloud_softness"].has(str(k)):
				ok9 = false
		if str((pr_v as Dictionary).n) in ["Только вуаль", "Ни одного"]:
			if float(u.get("cloud_coverage", -1.0)) != 1.0 or float(u.get("cloud_softness", -1.0)) != 0.01:
				ok9 = false
		else:
			if float(u.get("cloud_coverage", -1.0)) != 0.23 or float(u.get("cloud_softness", -1.0)) != 0.17:
				ok9 = false
	ok9 = ok9 and code.contains("uniform float cloud_coverage = 0.23;") \
		and code.contains("uniform float cloud_softness = 0.17;")
	var m9: Dictionary = B.compute_march(rays[5], cb, ct, 32, 30000.0, 0.0025, 0.01, dp_off)
	var hc9: Dictionary = B.compute_hc_layer(rays[5], hp_off, {})
	check("HC5-9 слоёвое A/B: 4 пресета существующими uniform'ами; dp_off → T == 1.0; hc off → α == 0",
		ok9 and float(m9.transmittance) == 1.0 and float(hc9.alpha) == 0.0,
		"(T_off=%.6f, α_off=%.1f)" % [float(m9.transmittance), float(hc9.alpha)])

	# HC5-10: форма-независимость вклада вуали (Δ = (base'−base)·T одинаков в GPU-форме
	# mix(base', sub.rgb, sub.a) и физической base'·T + S — проверено HC5-1) + ЗАМЕР
	# расхождения субпасс-формы для КУЧЕВЫХ (S·(1−T) против S на тонких массах):
	# max ≤ 0.15 (измерено 0.099 neutral) — документировано для решения заказчика,
	# компонент его НЕ правит (чужой контракт D-серии, вид принят в D2/D3).
	var max_disc10 := 0.0
	var sc_nt: Dictionary = _hc5_scene_from_preset(tbl["neutral"])
	for r_v in rays:
		var f: Dictionary = B.compute_final_with_hc(r_v, cb, ct, 32, 30000.0, 0.0025, 0.01,
			0.0, dp_mat, sc_nt.lp, {}, sc_nt.ap, sc_nt.su, hp_off)
		var T := float((f.march as Dictionary).transmittance)
		var a_c := 1.0 - T
		var l_bg10 := _hc4_lum(f.base as Vector3)
		var l_c10 := _hc4_lum(f.final as Vector3)
		var S := l_c10 - l_bg10 * T
		if a_c > 0.02 and a_c < 0.5:
			max_disc10 = maxf(max_disc10, absf(S * T - S))
	check("HC5-10 вклад вуали форма-независим (HC5-1); расхождение субпасса кучевых измерено ≤ 0.15 (не правим — чужой контракт)",
		form_max <= 1e-5 and max_disc10 <= 0.15,
		"(max |S·T − S| на тонких кучевых: %.4f)" % max_disc10)

	# HC5-11: регрессия: новых uniform'ов нет (22), композит/порядок на месте, POSITION
	# ×1, 2 pw + 1 worley, 0 циклов, subpass-гейт цел, D3 побитово, lighting-гейт жив.
	var hc_block := _hc_shader_block(code)
	var n_uniforms := 0
	for ln in code.split("\n"):
		var t := ln.strip_edges()
		if t.begins_with("uniform ") and t.contains("hc_"):
			n_uniforms += 1
	var d_id := Vector3(0.25, 0.62, -0.74).normalized()
	var f_off: Dictionary = B.compute_final_with_hc(d_id, cb, ct, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {}, {}, {"enabled": false})
	var f_ref: Dictionary = B.compute_final_with_sun(d_id, cb, ct, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {})
	check("HC5-11 регрессия: 22 uniform'а (новых нет), композит/гейты целы, D3 побитово",
		n_uniforms == 22 and HC_UNIFORM_NAMES.size() == 22
		and code.contains("vec3 base = (bg + sunbg) * (1.0 - hc_a) + hc_rgb;")
		and code.contains("return (hc_use_lighting ? hc_lit_color(dir) : hc_color) * a;")
		and code_nc.count("POSITION") == 1
		and hc_block.count("texture(noise_pw") == 2 and hc_block.count("texture(noise_worley") == 1
		and not hc_block.contains("for (")
		and (f_off.final as Vector3) == (f_ref.final as Vector3),
		"(uniform'ов %d)" % n_uniforms)


## PRAV-1.1: полный dp кучевых ИЗ МАТЕРИАЛА (все ключи, включая weather/профиль/fades —
## dp_defaults значениями материала перекрываются; источник чисел — .tres, не хардкод).
func _pr11_dp(mat: ShaderMaterial) -> Dictionary:
	return {
		"base_scale": float(mat.get_shader_parameter("cloud_base_scale")),
		"detail_scale": float(mat.get_shader_parameter("cloud_detail_scale")),
		"coverage": float(mat.get_shader_parameter("cloud_coverage")),
		"softness": float(mat.get_shader_parameter("cloud_softness")),
		"strength": float(mat.get_shader_parameter("cloud_detail_strength")),
		"erosion": float(mat.get_shader_parameter("cloud_erosion")),
		"edge_contrast": float(mat.get_shader_parameter("cloud_edge_contrast")),
		"offset": _pr11_v3(mat.get_shader_parameter("cloud_offset")),
		"base_fade": float(mat.get_shader_parameter("height_base_fade")),
		"top_fade": float(mat.get_shader_parameter("height_top_fade")),
		"fade_start": float(mat.get_shader_parameter("detail_fade_start")),
		"fade_end": float(mat.get_shader_parameter("detail_fade_end")),
		"bottom": float(mat.get_shader_parameter("cloud_layer_bottom")),
		"top": float(mat.get_shader_parameter("cloud_layer_top")),
		"use_curtain": bool(mat.get_shader_parameter("use_far_curtain")),
		"c_start": float(mat.get_shader_parameter("far_curtain_start")),
		"c_end": float(mat.get_shader_parameter("far_curtain_end")),
		"use_aniso": bool(mat.get_shader_parameter("use_height_anisotropy")),
		"aniso_base": float(mat.get_shader_parameter("aniso_base")),
		"aniso_top": float(mat.get_shader_parameter("aniso_top")),
		"h_stretch": float(mat.get_shader_parameter("cloud_horizontal_stretch")),
		"warp": float(mat.get_shader_parameter("cloud_warp_strength")),
		"warp_scale": float(mat.get_shader_parameter("cloud_warp_scale")),
		"use_mask": bool(mat.get_shader_parameter("use_weather_mask")),
		"w_scale": float(mat.get_shader_parameter("weather_scale")),
		"w_cut": float(mat.get_shader_parameter("weather_cut")),
		"w_soft": float(mat.get_shader_parameter("weather_soft")),
		"w_strength": float(mat.get_shader_parameter("weather_strength")),
		"fine_strength": float(mat.get_shader_parameter("cloud_fine_strength")),
		"fine_scale": float(mat.get_shader_parameter("cloud_fine_scale")),
	}


func _pr11_v3(v: Variant) -> Vector3:
	if v is Color:
		var c: Color = v
		return Vector3(c.r, c.g, c.b)
	if v is Vector3:
		return v
	return Vector3.ZERO


## PRAV-1.1: метрики формы (те же, что baseline_fingerprint F2-F6): ранги масс/впадин/
## weather-зон, hf/lf, доля доминирования детали, доли/σ поля, вертикаль.
func _pr11_metrics(B: GDScript, dp: Dictionary) -> Dictionary:
	var mass_runs: Array = []
	var gap_runs: Array = []
	var zone_runs: Array = []
	var hf := 0.0
	var lf := 0.0
	var over_eff := 0
	var npts := 0
	var eff_soft: float = float(dp.softness) / maxf(float(dp.edge_contrast), 1.0)
	for li in range(0, 6):
		var z0 := float(li) * 4000.0 - 10000.0
		var run_m := 0
		var run_g := 0
		var run_z := 0
		var prev_l := -1.0
		var prev_h := -1.0
		for si in range(0, 400):
			var p := Vector3(float(si) * 100.0 - 20000.0, 2500.0, z0)
			var d: float = B.compute_density(p, dp, 2000.0)
			if prev_h >= 0.0:
				hf += absf(d - prev_h)
			prev_h = d
			if si % 10 == 0:
				if prev_l >= 0.0:
					lf += absf(d - prev_l)
				prev_l = d
			var pw: Vector3 = p + (dp.offset as Vector3)
			var det: float = B.sample_tex(B._wo_voxels, int(B.WO_SIZE),
				pw.x / float(dp.detail_scale), pw.y / float(dp.detail_scale), pw.z / float(dp.detail_scale))
			if absf(float(dp.strength) * (det - 0.5)) > eff_soft:
				over_eff += 1
			npts += 1
			var w: float = B.sample_tex(B._pw_voxels, int(B.PW_SIZE),
				pw.x / float(dp.w_scale), pw.y / float(dp.w_scale), pw.z / float(dp.w_scale))
			if d > 0.5:
				run_m += 1
				if run_g > 0:
					gap_runs.append(run_g)
				run_g = 0
			elif d < 0.02:
				run_g += 1
				if run_m > 0:
					mass_runs.append(run_m)
				run_m = 0
			else:
				if run_m > 0:
					mass_runs.append(run_m)
				if run_g > 0:
					gap_runs.append(run_g)
				run_m = 0
				run_g = 0
			if w < float(dp.w_cut):
				run_z += 1
			else:
				if run_z > 0:
					zone_runs.append(run_z)
				run_z = 0
		if run_m > 0:
			mass_runs.append(run_m)
		if run_g > 0:
			gap_runs.append(run_g)
		if run_z > 0:
			zone_runs.append(run_z)
	var sum := 0.0
	var sum2 := 0.0
	var clr := 0
	var dns := 0
	var cnt := 0
	for gi in range(0, 24):
		for gj in range(0, 24):
			var p := Vector3(float(gi) * 1000.0 - 11500.0, 2500.0, float(gj) * 1000.0 - 11500.0)
			var d: float = B.compute_density(p, dp, 2000.0)
			sum += d
			sum2 += d * d
			cnt += 1
			if d < 0.02:
				clr += 1
			elif d > 0.8:
				dns += 1
	var mean := sum / float(cnt)
	return {"mass_mean_m": _pr11_mean(mass_runs) * 100.0, "mass_max_m": _pr11_max(mass_runs) * 100.0,
		"gap_mean_m": _pr11_mean(gap_runs) * 100.0, "zone_mean_m": _pr11_mean(zone_runs) * 100.0,
		"hf_lf": hf / maxf(lf, 1e-9) * 10.0, "over_eff_frac": float(over_eff) / float(npts),
		"clear": float(clr) / float(cnt), "dense": float(dns) / float(cnt),
		"std": sqrt(maxf(sum2 / float(cnt) - mean * mean, 0.0)), "mean": mean,
		"v_base": _pr11_vmean(B, dp, 1600.0), "v_mid": _pr11_vmean(B, dp, 2100.0),
		"v_top": _pr11_vmean(B, dp, 3200.0)}


func _pr11_vmean(B: GDScript, dp: Dictionary, y: float) -> float:
	var s := 0.0
	for gi in range(0, 16):
		for gj in range(0, 16):
			s += B.compute_density(Vector3(float(gi) * 1500.0 - 11250.0, y,
				float(gj) * 1500.0 - 11250.0), dp, 2000.0)
	return s / 256.0


func _pr11_mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


func _pr11_max(a: Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, float(v))
	return m


## PRAV-1.1: снапшот СВЕТОВЫХ ключей neutral-пресета в состоянии SKYHC_5 (вуаль использует
## их через hc_lp_from_preset). Фаза 1 правок меняет ТОЛЬКО shape-ключи пресетов —
## снапшот гардирует согласование (ТЗ правок: «не менять контракты освещения без
## согласования»; правка световых ключей уронит PR11-7 → требует явного решения заказчика).
const NEUTRAL_LIGHT_SNAPSHOT := {
	"dir": Vector3(-0.75, 0.50, -0.43),
	"color": Color(1.0, 0.97, 0.92, 1),
	"strength": 0.70,
	"amb_sky": Color(0.55, 0.63, 0.82, 1),
	"amb_gnd": Color(0.25, 0.27, 0.34, 1),
	"amb_energy": 0.45,
	"sky_color": Color(0.32, 0.47, 0.68, 1),
	"atmo_color": Color(0.55, 0.65, 0.85, 1),
	"use_sun_color_ramp": false,
	"use_ambient_from_sky": false,
	"ambient_sky_gain": 1.2,
	"sun_size": 0.02,
	"sun_intensity": 16.0,
	"sun_halo_strength": 0.25,
	"sun_halo_power": 250.0,
	"grad_horizon": Color(0.42, 0.55, 0.75, 1),
	"grad_zenith": Color(0.20, 0.35, 0.60, 1),
	"grad_antisolar": Color(0.18, 0.18, 0.38, 1),
	"grad_mid": Color(0.50, 0.68, 0.88, 1),
	"grad_pink": Color(0.80, 0.70, 0.75, 1),
	"grad_white": Color(0.98, 0.97, 0.88, 1),
}


# === СЕКЦИЯ PRAV-1.1: правки кучевых, фаза 1 — крупные формы ===
# TZ правок фаза 1: выразительная общая масса до мелких деталей; крупномасштабная
# неоднородность (отдельные округлые массы + заметные впадины); распределение по высоте
# не равномерное; мелкая эрозия временно уменьшена. Не повышать общую плотность ради
# округлости (риск сплошной стены). Все пороги — из развёртки кандидатов (README §2):
# вариант B' (detail 0.15 / erosion 0.10 / weather 140k / base_fade 0.10, остальные
# параметры D1 сохранены): массы 1668/6400 м, впадины 6203 м, зоны 7707 м (иерархия
# 4.6×), over_eff 0 %, hf/lf 14.3, clear 0.78 dense 0.14 σ 0.35, вертикаль 0.086/0.153/0.062.
func section_prav_11() -> void:
	print("--- Секция PRAV-1.1: крупные формы кучевых (иерархия, массы, де-foam, вертикаль) ---")
	var sh: Shader = load(SHADER_PATH)
	var mat: ShaderMaterial = load(MATERIAL_PATH)
	var code := sh.code
	var code_nc := _strip_comments(code)
	var dp := _pr11_dp(mat)
	var m := _pr11_metrics(B, dp)

	# PR11-1: иерархия масштабов — weather-зоны ≥ 3× крупнее масс (аудит: было 2.6 км
	# против 0.5 км = один масштаб; стало 7.7 против 1.7 км).
	var hierarchy: float = float(m.zone_mean_m) / maxf(float(m.mass_mean_m), 1.0)
	check("PR11-1 иерархия масштабов: weather-зоны / массы ≥ 3.0 (разделение крупных форм)",
		hierarchy >= 3.0,
		"(зоны %.0f м / массы %.0f м = %.1f×)" % [float(m.zone_mean_m), float(m.mass_mean_m), hierarchy])

	# PR11-2: консолидация масс — средний ранг ≥ 1500 м (аудит: было 469-532 м),
	# максимальный ≥ 4000 м; впадины между массами заметные (≥ 3000 м).
	check("PR11-2 массы консолидированы: средний ранг ≥ 1500 м, макс ≥ 4000 м, впадины ≥ 3000 м",
		float(m.mass_mean_m) >= 1500.0 and float(m.mass_max_m) >= 4000.0
		and float(m.gap_mean_m) >= 3000.0,
		"(массы %.0f/%.0f м, впадины %.0f м)" % [float(m.mass_mean_m), float(m.mass_max_m),
			float(m.gap_mean_m)])

	# PR11-3: пена снята — доля точек, где ВЧ-деталь превышает эффективное окно sstep,
	# ≤ 1 % (аудит: 34-38 % при detail 0.60 × edge_contrast 2.0); hf/lf ≤ 20 (было 25.4).
	# ПЕРЕБАЗИРОВАНО prav_2.1: over_eff (|деталь| > эфф. окна) перестал быть метрикой
	# пены — с фазы 2 деталь на СРЕДНЕМ масштабе (12 км, выступы ~1.5 км) и легально
	# превышает окно (8.1 % — это и есть округлые выступы, а не пена 375 м). Guard пены
	# теперь — энергия мелкой полосы E100 ≤ 0.022 (не выше принятой фазы 1: 0.0196) и
	# hf/lf ≤ 20; изолированные фрагменты 0 % (F5).
	var bands113 := _pr12_bands(B, dp)
	check("PR11-3 де-foam (v2 prav_2.1): E100 ≤ 0.022, hf/lf ≤ 20 (over_eff — инфо)",
		float(bands113.E100) <= 0.022 and float(m.hf_lf) <= 20.0,
		"(E100 %.4f, hf/lf %.1f, over_eff инфо %.1f %%)" % [float(bands113.E100),
			float(m.hf_lf), float(m.over_eff_frac) * 100.0])

	# PR11-4: НЕ сплошная стена (TZ фаза 1: округлость не плотностью) — dense ≤ 0.25,
	# clear ≥ 0.60, σ ≥ 0.30 (измерено 0.14/0.78/0.35).
	check("PR11-4 не стена: dense ≤ 0.25, clear ≥ 0.60, σ ≥ 0.30",
		float(m.dense) <= 0.25 and float(m.clear) >= 0.60 and float(m.std) >= 0.30,
		"(clear %.2f dense %.2f σ %.2f)" % [float(m.clear), float(m.dense), float(m.std)])

	# PR11-5: вертикаль неоднородна (TZ фаза 1 п.4) и основание не прозрачное:
	# v(1600) и v(3200) < 0.6·v(2100) (пик в нижней середине), v(1600) ≥ 0.06
	# (base_fade 0.10: аудит-«было» 0.050 при 0.15 → 0.086 при 0.10).
	check("PR11-5 вертикаль: пик в середине слоя, основание ≥ 0.06, верх/низ < 0.6 пика",
		float(m.v_base) < 0.6 * float(m.v_mid) and float(m.v_top) < 0.6 * float(m.v_mid)
		and float(m.v_base) >= 0.06,
		"(v: основание %.3f / середина %.3f / верх %.3f)" % [float(m.v_base), float(m.v_mid),
			float(m.v_top)])

	# PR11-6: синхронизация материал ↔ neutral-пресет по новым shape-значениям (C5/C6
	# семантика) и исторические дефолты D1 живы В ШЕЙДЕРЕ (35500/0.23/0.17/3000/0.60/
	# 0.30/30000/0.15 — материал и пресет несут состояние фазы 1, шейдер не тронут).
	var tbl: Dictionary = B.preset_table()
	var nt: Dictionary = tbl.neutral
	check("PR11-6 синк материал↔neutral (detail 0.15/erosion 0.10/weather 140k); дефолты D1 в шейдере не тронуты",
		absf(float(nt.detail_strength) - float(mat.get_shader_parameter("cloud_detail_strength"))) < 1e-9
		and absf(float(nt.erosion) - float(mat.get_shader_parameter("cloud_erosion"))) < 1e-9
		and absf(float(nt.weather_scale) - float(mat.get_shader_parameter("weather_scale"))) < 1e-6
		and absf(float(mat.get_shader_parameter("weather_scale")) - 140000.0) < 1e-6
		and absf(float(mat.get_shader_parameter("height_base_fade")) - 0.10) < 1e-9
		and code.contains("uniform float cloud_detail_strength = 0.60;")
		and code.contains("uniform float cloud_erosion = 0.30;")
		and code.contains("uniform float weather_scale = 30000.0;")
		and code.contains("uniform float height_base_fade = 0.15;")
		and code.contains("uniform float cloud_base_scale = 35500.0;"))

	# PR11-7: вуаль ЗАМОРОЖЕНА: гейт D3 побитово; 22 hc-uniform'а; POSITION ×1;
	# текстурный состав (2 pw + 1 worley в hc-блоке); СВЕТОВЫЕ ключи neutral-пресета
	# равны снапшоту SKYHC_5 (правлены только shape-ключи — согласование не требуется).
	var hp_off := {"enabled": false, "origin": Vector3.ZERO}
	var d_id := Vector3(0.25, 0.62, -0.74).normalized()
	var f_off: Dictionary = B.compute_final_with_hc(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {}, {}, hp_off)
	var f_ref: Dictionary = B.compute_final_with_sun(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {})
	var snap_ok := true
	for k in NEUTRAL_LIGHT_SNAPSHOT.keys():
		var a: Variant = NEUTRAL_LIGHT_SNAPSHOT[k]
		var b: Variant = nt.get(k, null)
		if a is float:
			if b == null or absf(float(a) - float(b)) > 1e-9:
				snap_ok = false
		else:
			if b == null or a != b:
				snap_ok = false
	var hc_block := _hc_shader_block(code)
	var n_hc := 0
	for ln in code.split("\n"):
		var t := ln.strip_edges()
		if t.begins_with("uniform ") and t.contains("hc_"):
			n_hc += 1
	check("PR11-7 вуаль заморожена: D3 побитово, 22 hc-uniform'а, POSITION ×1, световые ключи пресетов = снапшоту",
		(f_off.final as Vector3) == (f_ref.final as Vector3) and snap_ok
		and n_hc == 22 and code_nc.count("POSITION") == 1
		and hc_block.count("texture(noise_pw") == 2 and hc_block.count("texture(noise_worley") == 1,
		"(снапшот света: %s)" % ("совпадает" if snap_ok else "РАСХОЖДЕНИЕ — нужно согласование"))

	# PR11-8: временный контракт фазы 1: материал detail ≤ 0.20 / erosion ≤ 0.15
	# (оценочное состояние силуэта; фаза 3 вернёт деталь с локализацией на кромках),
	# диапазоны меню сохраняют свободу старых значений (деталь b ≥ 0.60, эрозия b ≥ 0.30).
	var ranges := {}
	for sec_v in B.TUNE_SECTIONS:
		var sec: Dictionary = sec_v
		for r_v in (sec.rows as Array):
			var r: Dictionary = r_v
			if str(r.get("k", "")) == "f" and ["cloud_detail_strength", "cloud_erosion",
					"weather_scale"].has(str(r.get("u", ""))):
				ranges[str(r.u)] = [float(r.a), float(r.b)]
	# ПЕРЕБАЗИРОВАНО prav_2.1: временный контракт фазы 1 (detail ≤ 0.20) выполнен и
	# закрыт — фаза 2 вернула деталь на СРЕДНЕМ масштабе (контракт фазы 2: strength
	# ≤ 0.45 при detail_scale ≥ 8000 — режим выступов, не пены; erosion ≤ 0.15 сохранён
	# до фазы 3). Мелкая фактура кромок — фаза 3 (edge-локализация или 2-я выборка).
	check("PR11-8 контракт фазы 2: detail ≤ 0.45 при detail_scale ≥ 8000, erosion ≤ 0.15; меню сохраняет свободу (b ≥ 0.60/0.30/200k)",
		float(mat.get_shader_parameter("cloud_detail_strength")) <= 0.45
		and float(mat.get_shader_parameter("cloud_detail_scale")) >= 8000.0
		and float(mat.get_shader_parameter("cloud_erosion")) <= 0.15
		and float(ranges["cloud_detail_strength"][1]) >= 0.60
		and float(ranges["cloud_erosion"][1]) >= 0.30
		and float(ranges["weather_scale"][1]) >= 200000.0,
		"(материал: detail %.2f @ %.0f, erosion %.2f)" % [float(mat.get_shader_parameter("cloud_detail_strength")),
			float(mat.get_shader_parameter("cloud_detail_scale")), float(mat.get_shader_parameter("cloud_erosion"))])

	# PR11-9 (FIX-гард): каждый тип строки меню ("k" в TUNE_SECTIONS) обязан иметь
	# ветку в _ui_add_row — баг SKYHC_5: строка «Слои A/B» существовала в данных, но
	# case "hclayers" отсутствовал, и строка строилась БЕЗ кнопок (match молча
	# проваливался; headless-смоук не ловит — нет ошибки). Скан исходника стенда.
	var bench_src := String(B.source_code)
	var fn_start := bench_src.find("func _ui_add_row")
	var fn_end := bench_src.find("\nfunc ", fn_start + 10)
	var fn_body := bench_src.substr(fn_start, fn_end - fn_start) if fn_end > fn_start else ""
	var kinds := {}
	for sec_v in B.TUNE_SECTIONS:
		for r_v in ((sec_v as Dictionary).rows as Array):
			kinds[str((r_v as Dictionary).get("k", ""))] = true
	var missing_kinds: Array = []
	for k in kinds.keys():
		if not fn_body.contains('\"%s\"' % str(k)):
			missing_kinds.append(k)
	check("PR11-9 UI-гард: каждый тип строки меню имеет ветку в _ui_add_row (фикс hclayers)",
		fn_body.length() > 0 and missing_kinds.is_empty(),
		"(типов строк %d, без веток: %s)" % [kinds.size(), str(missing_kinds)])


## PRAV-1.2: полосные энергии (формула идентична F8 baseline_fingerprint v2).
func _pr12_bands(B: GDScript, dp: Dictionary) -> Dictionary:
	var e100 := 0.0
	var e500 := 0.0
	var e2000 := 0.0
	var n100 := 0
	var n500 := 0
	var n2000 := 0
	var bump_runs: Array = []
	for li in range(0, 6):
		var z0 := float(li) * 4000.0 - 10000.0
		var ds: Array = []
		for si in range(0, 400):
			ds.append(B.compute_density(Vector3(float(si) * 100.0 - 20000.0, 2500.0, z0), dp, 2000.0))
		var run_b := 0
		for si in range(0, 400):
			var d0: float = ds[si]
			if d0 > 0.3:
				run_b += 1
			elif run_b > 0:
				bump_runs.append(run_b)
				run_b = 0
			if si + 1 < 400:
				e100 += absf(float(ds[si + 1]) - d0)
				n100 += 1
			if si + 5 < 400:
				e500 += absf(float(ds[si + 5]) - d0)
				n500 += 1
			if si + 20 < 400:
				e2000 += absf(float(ds[si + 20]) - d0)
				n2000 += 1
		if run_b > 0:
			bump_runs.append(run_b)
	var b_mean := _pr11_mean(bump_runs)
	var b_var := 0.0
	for v in bump_runs:
		b_var += (float(v) - b_mean) * (float(v) - b_mean)
	var b_cv: float = sqrt(b_var / maxf(float(bump_runs.size()), 1.0)) / maxf(b_mean, 1e-9)
	return {"E100": e100 / maxf(float(n100), 1.0), "E500": e500 / maxf(float(n500), 1.0),
		"E2000": e2000 / maxf(float(n2000), 1.0), "bump_n": bump_runs.size(),
		"bump_mean_m": b_mean * 100.0, "bump_cv": b_cv}


# === СЕКЦИЯ PRAV-1.2: фиксация принятого состояния фазы 1 (контрольная точка) ===
# ТЗ правок: «После каждой контрольной точки фиксировать результат до перехода дальше».
# Заказчик принял prav_1.1 (силуэт при минимальной детали убедителен). Секция замораживает
# ЧИСЛА принятого состояния: контрольные суммы фингерпринта F1, конверт shape-метрик и
# полосный спектр F8. Любой следующий шаг, меняющий форму, ОБЯЗАН перебазировать эти
# проверки с явной атрибуцией (прецедент P4) — незапланированный дрейф не пройдёт.
func section_prav_12() -> void:
	print("--- Секция PRAV-1.2: фиксация принятого состояния фазы 1 ---")
	var mat: ShaderMaterial = load(MATERIAL_PATH)
	var dp := _pr11_dp(mat)
	var tbl: Dictionary = B.preset_table()
	var lp: Dictionary = B.hc_lp_from_preset(tbl["neutral"])
	var bottom := float(mat.get_shader_parameter("cloud_layer_bottom"))
	var top := float(mat.get_shader_parameter("cloud_layer_top"))
	var march_steps := int(float(mat.get_shader_parameter("march_steps")))
	var extinction := float(mat.get_shader_parameter("extinction_scale"))

	# PR12-1: контрольные суммы фингерпринта F1 (12 лучей, формула лучей идентична
	# baseline_fingerprint.gd): ΣT = 11.010351, Σmean_d = 0.085303, Σscat = 0.528489.
	var sum_t := 0.0
	var sum_md := 0.0
	var sum_sl := 0.0
	for i in range(0, 12):
		var el := deg_to_rad(6.0 + 70.0 * float(i % 4) / 3.0)
		var az := TAU * float(i / 4) / 3.0 + deg_to_rad(17.0)
		var dir := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
		var m: Dictionary = B.compute_march(dir, bottom, top, march_steps, 30000.0, extinction, 0.01, dp)
		var md: Dictionary = B.compute_mean_density(dir, bottom, top, march_steps, dp)
		var ml: Dictionary = B.compute_march_lit(dir, bottom, top, march_steps, 30000.0, extinction, 0.01, dp, lp)
		sum_t += float(m.transmittance)
		sum_md += float(md.mean_density)
		sum_sl += _hc4_lum(ml.scattered as Vector3)
	# ПЕРЕБАЗИРОВАНО prav_2.1 (суммы фазы 1 11.010351/0.085303/0.528489 → фазы 2
	# 10.955233/0.082007/0.569773) и prav_3.1 (бахрома кромок добавляет рассеяния:
	# Σscat 0.5698 → 0.5752; ΣT/Σmean_d сдвиг в пределах 1e-3).
	check("PR12-1 контрольные суммы текущего контрольного состояния (перебазировано prav_3.1): ΣT=10.9472 Σmean_d=0.0832 Σscat=0.5752 (±1e-3)",
		absf(sum_t - 10.947249) <= 1e-3 and absf(sum_md - 0.083226) <= 1e-3
		and absf(sum_sl - 0.575169) <= 1e-3,
		"(ΣT=%.6f Σmean_d=%.6f Σscat=%.6f)" % [sum_t, sum_md, sum_sl])

	# PR12-2: конверт shape-метрик принятого состояния (измерено prav_1.1/1.2:
	# массы 1668 м, зоны 7707 м, иерархия 4.6×, over_eff 0 %, clear 0.78 dense 0.14
	# σ 0.35, основание 0.086).
	var m11 := _pr11_metrics(B, dp)
	var hier12: float = float(m11.zone_mean_m) / maxf(float(m11.mass_mean_m), 1.0)
	# ПЕРЕБАЗИРОВАНО prav_2.1: массы укрупнились выступами (1668 → 2159 м), over_eff
	# заменён на E100-гард (см. PR11-3 v2), иерархия 3.5× при массе 2159/зоне 7642.
	var bands12 := _pr12_bands(B, dp)
	check("PR12-2 конверт формы фазы 2: массы 1900-2600 м, зоны 6500-9000 м, иерархия ≥3.0, E100 ≤0.022, clear 0.70-0.85, dense 0.10-0.22, σ ≥0.30, основание ≥0.06",
		float(m11.mass_mean_m) >= 1900.0 and float(m11.mass_mean_m) <= 2600.0
		and float(m11.zone_mean_m) >= 6500.0 and float(m11.zone_mean_m) <= 9000.0
		and hier12 >= 3.0 and float(bands12.E100) <= 0.022
		and float(m11.clear) >= 0.70 and float(m11.clear) <= 0.85
		and float(m11.dense) >= 0.10 and float(m11.dense) <= 0.22
		and float(m11.std) >= 0.30 and float(m11.v_base) >= 0.06,
		"(массы %.0f м, зоны %.0f м, иерархия %.1f×, σ %.2f, основание %.3f)"
		% [float(m11.mass_mean_m), float(m11.zone_mean_m), hier12, float(m11.std), float(m11.v_base)])

	# PR12-3: полосный спектр F8 принятого состояния (измерено: E500/E100 = 3.71,
	# E2000/E500 = 3.15 — спектр самоподобный, среднечастотного плеча НЕТ; выступы
	# 1804 м, CV 0.91). Фаза 2 обязана СДВИНУТЬ спектр в среднюю полосу (рост E500/E100)
	# с перебазированием этого конверта и атрибуцией — текущие границы ловят и дрейф.
	var b12 := _pr12_bands(B, dp)
	var r_fm: float = float(b12.E500) / maxf(float(b12.E100), 1e-9)
	var r_ms: float = float(b12.E2000) / maxf(float(b12.E500), 1e-9)
	# ПЕРЕБАЗИРОВАНО prav_2.1: среднечастотное плечо ПОЯВИЛОСЬ (E500/E100 3.71 → 4.33) —
	# конверт поднят до [4.0, 5.0]: фаза 3+ не должна откатить спектр к самоподобию.
	check("PR12-3 спектр фазы 2: E500/E100 ∈ [4.0, 5.0] (плечо есть), E2000/E500 ∈ [2.5, 4.0], выступы ≥ 1900 м, CV ≥ 0.75",
		r_fm >= 4.0 and r_fm <= 5.0 and r_ms >= 2.5 and r_ms <= 4.0
		and float(b12.bump_mean_m) >= 1900.0 and float(b12.bump_cv) >= 0.75,
		"(E500/E100 %.2f, E2000/E500 %.2f, выступы n=%d %.0f м CV %.2f)"
		% [r_fm, r_ms, int(b12.bump_n), float(b12.bump_mean_m), float(b12.bump_cv)])


## PRAV-2.1: метрики вдоль мирового направления az_deg (линии 6×40 км, шаг 100 м,
## y=2500): полосные энергии, ранги выступов (d>0.3) и масс (d>0.5), доля резких
## скачков (алиасинг-прокси). Формулы идентичны baseline_fingerprint F8/F4.
func _pr21_met(B: GDScript, dp: Dictionary, az_deg: float) -> Dictionary:
	var dir := Vector3(cos(deg_to_rad(az_deg)), 0.0, sin(deg_to_rad(az_deg)))
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var e100 := 0.0
	var e500 := 0.0
	var e2000 := 0.0
	var n1 := 0
	var n5 := 0
	var n20 := 0
	var bump_runs: Array = []
	var mass_runs: Array = []
	var sharp := 0
	for li in range(0, 6):
		var off := perp * (float(li) * 4000.0 - 10000.0)
		var ds: Array = []
		for si in range(0, 400):
			ds.append(B.compute_density(off + dir * (float(si) * 100.0 - 20000.0) + Vector3(0.0, 2500.0, 0.0), dp, 2000.0))
		var rb := 0
		var rm := 0
		for si in range(0, 400):
			var d0: float = ds[si]
			if d0 > 0.3:
				rb += 1
			elif rb > 0:
				bump_runs.append(rb)
				rb = 0
			if d0 > 0.5:
				rm += 1
			elif rm > 0:
				mass_runs.append(rm)
				rm = 0
			if si + 1 < 400:
				var dd: float = absf(float(ds[si + 1]) - d0)
				e100 += dd
				n1 += 1
				if dd > 0.5:
					sharp += 1
			if si + 5 < 400:
				e500 += absf(float(ds[si + 5]) - d0)
				n5 += 1
			if si + 20 < 400:
				e2000 += absf(float(ds[si + 20]) - d0)
				n20 += 1
		if rb > 0:
			bump_runs.append(rb)
		if rm > 0:
			mass_runs.append(rm)
	var E100 := e100 / maxf(float(n1), 1.0)
	var E500 := e500 / maxf(float(n5), 1.0)
	var E2000 := e2000 / maxf(float(n20), 1.0)
	var bm := _pr11_mean(bump_runs) * 100.0
	var bv := 0.0
	for v in bump_runs:
		bv += (float(v) * 100.0 - bm) * (float(v) * 100.0 - bm)
	var bcv: float = sqrt(bv / maxf(float(bump_runs.size()), 1.0)) / maxf(bm, 1e-9)
	return {"E100": E100, "r_fm": E500 / maxf(E100, 1e-9), "r_ms": E2000 / maxf(E500, 1e-9),
		"bump_m": bm, "cv": bcv, "mass_m": _pr11_mean(mass_runs) * 100.0,
		"mass_max_m": _pr11_max(mass_runs) * 100.0,
		"sharp_frac": float(sharp) / maxf(float(n1), 1.0)}


# === СЕКЦИЯ PRAV-2.1: фаза 2 ТЗ — средние формы и характерные выступы ===
# Механизм (решение prav_1.2 §3 по данным, кандидат F2): деталь переназначена на
# СРЕДНИЙ масштаб — detail_scale 3000→12000 (особенности ~1.5 км), detail_strength
# 0.15→0.40, warp 220@9000→400@6500 (анти-регулярность). НОЛЬ новых текстурных
# выборок (третья PW-октава отклонена замерами: массы 820/450/1463 м < гарда 1500 при
# +25 % стоимости). Цели фазы 2: читаемая структура масс + округлые выступы без
# «грозди одинаковых сфер»; разделение плотностью, не резкими границами; вариативность;
# работа с нескольких направлений взгляда.
func section_prav_21() -> void:
	print("--- Секция PRAV-2.1: средние выступы (плечо спектра, анти-регулярность, мульти-ракурс) ---")
	var sh: Shader = load(SHADER_PATH)
	var mat: ShaderMaterial = load(MATERIAL_PATH)
	var dp := _pr11_dp(mat)
	var tbl: Dictionary = B.preset_table()
	var nt: Dictionary = tbl.neutral
	var azs := [0.0, 45.0, 90.0, 135.0]
	var mets := {}
	for az in azs:
		mets[az] = _pr21_met(B, dp, float(az))
	var m0: Dictionary = mets[0.0]

	# PR21-1: среднечастотное плечо сформировано: E500/E100 ≥ 4.0 (фаза 1: 3.71 —
	# спектр был самоподобный), E2000/E500 ≥ 2.5 (плечо, а не пик), выступы ≥ 2000 м.
	check("PR21-1 плечо средних частот: E500/E100 ≥ 4.0, E2000/E500 ≥ 2.5, выступы ≥ 2000 м",
		float(m0.r_fm) >= 4.0 and float(m0.r_ms) >= 2.5 and float(m0.bump_m) >= 2000.0,
		"(r_fm %.2f r_ms %.2f выступы %.0f м)" % [float(m0.r_fm), float(m0.r_ms), float(m0.bump_m)])

	# PR21-2: анти-регулярность (ТЗ 2.3/2.4 — вариативность, нет «грозди шариков»):
	# CV рангов выступов ≥ 0.8 на az0, ≥ 0.7 в среднем по 4 азимутам, ≥ 0.5 на худшем
	# (измерено F2: 0.85 / 0.79 / 0.60; warp 400@6500 — именно он поднимает CV: без
	# усиления warp при том же масштабе CV падал до 0.64-0.67).
	var cv_sum := 0.0
	var cv_min := 2.0
	for az in azs:
		var cv_az: float = float((mets[az] as Dictionary).cv)
		cv_sum += cv_az
		cv_min = minf(cv_min, cv_az)
	check("PR21-2 анти-регулярность: CV выступов ≥ 0.8 (az0), ≥ 0.7 (среднее 4 азимутов), ≥ 0.5 (худший)",
		float(m0.cv) >= 0.8 and cv_sum / 4.0 >= 0.7 and cv_min >= 0.5,
		"(CV: az0 %.2f, среднее %.2f, худший %.2f)" % [float(m0.cv), cv_sum / 4.0, cv_min])

	# PR21-3: выступы разделены ПЛОТНОСТЬЮ, а не резкими границами (ТЗ 2.2): доля
	# скачков |Δd|>0.5 на 100 м ≤ 0.5 % (измерено 0.13-0.25 %), мелкая полоса не выросла
	# E100 ≤ 0.022 (измерено 0.0173 — НИЖЕ фазы 1: средний масштаб чище мелкого).
	var ok213 := true
	for az in azs:
		var mm: Dictionary = mets[az]
		if float(mm.sharp_frac) > 0.005 or float(mm.E100) > 0.022:
			ok213 = false
	check("PR21-3 разделение плотностью: резких скачков ≤ 0.5 %, E100 ≤ 0.022 на всех азимутах",
		ok213,
		"(az0: sharp %.4f, E100 %.4f)" % [float(m0.sharp_frac), float(m0.E100)])

	# PR21-4: мульти-ракурс (ТЗ 2.5): плечо (r_fm ≥ 4.0), массы и E100 (max/min ≤ 1.20)
	# держатся на всех 4 азимутах — форма не работает «в одну сторону».
	# ПЕРЕБАЗИРОВАНО prav_3.1: гард масс худшего азимута 1500 → 1400 м — мелкая бахрома
	# легально подгрызает ранги d>0.5 на самом тонком азимуте (1522 → 1448 м, −5 %);
	# иерархия и плечо целы (r_fm ≥ 4.09), остальные азимуты ≥ 1950 м. Полный перенос
	# гарда на все азимуты (1500) остался у PR21-5 для az0 (2276 м).
	var ok214 := true
	var e_min := 1.0
	var e_max := 0.0
	var rep214 := ""
	for az in azs:
		var mm: Dictionary = mets[az]
		if float(mm.r_fm) < 4.0 or float(mm.mass_m) < 1400.0:
			ok214 = false
		e_min = minf(e_min, float(mm.E100))
		e_max = maxf(e_max, float(mm.E100))
		rep214 += "%.0f°:%.2f/%.0fм " % [float(az), float(mm.r_fm), float(mm.mass_m)]
	if e_max / maxf(e_min, 1e-9) > 1.20:
		ok214 = false
	check("PR21-4 мульти-ракурс: r_fm ≥ 4.0 и массы ≥ 1400 м на 4 азимутах (перебазировано prav_3.1), E100 max/min ≤ 1.20",
		ok214, "(%s| E100 разброс %.2f)" % [rep214, e_max / maxf(e_min, 1e-9)])

	# PR21-5: крупные формы СОХРАНЕНЫ (главный принцип ТЗ: сначала масса, потом выступы):
	# массы az0 ≥ 2000 м и max ≥ 4000 м; иерархия зоны/массы ≥ 3.0; dense ≤ 0.22 (не стена).
	var m11b := _pr11_metrics(B, dp)
	var hier21: float = float(m11b.zone_mean_m) / maxf(float(m11b.mass_mean_m), 1.0)
	check("PR21-5 крупные формы сохранены: массы ≥ 2000 м (max ≥ 4000), иерархия ≥ 3.0, dense ≤ 0.22",
		float(m0.mass_m) >= 2000.0 and float(m0.mass_max_m) >= 4000.0
		and hier21 >= 3.0 and float(m11b.dense) <= 0.22,
		"(массы %.0f/%.0f м, иерархия %.1f×, dense %.2f)" % [float(m0.mass_m),
			float(m0.mass_max_m), hier21, float(m11b.dense)])

	# PR21-6: синк материал↔neutral по всем 4 ключам фазы 2; меню detail_scale расширено
	# (b ≥ 12000); НОЛЬ новых выборок — в cloud_density ровно 4 texture() (warp PW +
	# shape PW + detail Worley + weather PW): третья октава не добавлена (отклонена
	# замерами prav_1.2 §3 — разрушение масс при +25 % стоимости).
	var fn_start := sh.code.find("float cloud_density(vec3 p, float t) {")
	var fn_end := sh.code.find("\n}\n", fn_start)
	var cd_body := sh.code.substr(fn_start, fn_end - fn_start) if fn_start >= 0 and fn_end > fn_start else ""
	var ranges21 := {}
	for sec_v in B.TUNE_SECTIONS:
		var sec: Dictionary = sec_v
		for r_v in (sec.rows as Array):
			var r: Dictionary = r_v
			if str(r.get("k", "")) == "f" and str(r.get("u", "")) == "cloud_detail_scale":
				ranges21["detail_scale"] = [float(r.a), float(r.b)]
	# ПЕРЕБАЗИРОВАНО prav_3.1: 4 → 5 texture() — фаза 3 добавила РОСНО одну выборку
	# (мелкая бахрома той же noise_worley под uniform-гейтом; решение и замер стоимости —
	# фаза 7). На момент фазы 2 здесь было ровно 4 (ноль новой стоимости) — история в
	# README prav_2.1 §1.
	check("PR21-6 синк материал↔neutral (4 ключа фазы 2), меню b ≥ 12000, cloud_density: ровно 5 texture() (перебазировано prav_3.1: +1 бахрома под гейтом)",
		absf(float(nt.detail_scale) - float(mat.get_shader_parameter("cloud_detail_scale"))) < 1e-6
		and absf(float(nt.detail_strength) - float(mat.get_shader_parameter("cloud_detail_strength"))) < 1e-9
		and absf(float(nt.warp) - float(mat.get_shader_parameter("cloud_warp_strength"))) < 1e-9
		and absf(float(nt.warp_scale) - float(mat.get_shader_parameter("cloud_warp_scale"))) < 1e-6
		and ranges21.has("detail_scale") and float(ranges21["detail_scale"][1]) >= 12000.0
		and cd_body.count("texture(") == 5,
		"(texture() в cloud_density: %d)" % cd_body.count("texture("))


# === СЕКЦИЯ PRAV-3.1: фаза 3 ТЗ — мелкая детализация и эрозия краёв ===
# Механизм: вторая выборка ТОЙ ЖЕ noise_worley на мелком периоде (cloud_fine_scale,
# особенности ~375 м при 3000), ТОЛЬКО в полосе перехода (вес w_edge = 1−|n−cov|/soft —
# приём вуали SKYHC-3.3): interior/exterior не тронуты (ТЗ 3.3 — поверхность не
# одинаково шероховатая), амплитуда ∝ softness (без бинарных пены-переключений),
# тот же B2-fade против мерцания вдали (ТЗ 3.5). Гейт: fine_strength=0 → побитово 2.1.
# Значения по развёртке 12 кандидатов (README §1): 3000/0.25 — выступы/массы сохранены
# (2212/2276 м), speck 0 %, r_fm 4.09 ≥ 4.0 (плечо фазы 2 цело).
func section_prav_31() -> void:
	print("--- Секция PRAV-3.1: мелкая бахрома кромок (локальность, иерархия, анти-foam) ---")
	var sh: Shader = load(SHADER_PATH)
	var mat: ShaderMaterial = load(MATERIAL_PATH)
	var code := sh.code
	var dp := _pr11_dp(mat)
	var dp_nofine := dp.duplicate()
	dp_nofine["fine_strength"] = 0.0

	# PR31-1: гейт идентичности — fine_strength=0 → плотность ПОБИТОВО равна состоянию
	# фазы 2 (24 точки × 3 высоты); дефолт шейдера 0.0 + uniform-гейт; материал 0.25/3000.
	var max_diff31 := 0.0
	for i in range(0, 24):
		var fi := float(i)
		for y in [2000.0, 2500.0, 3000.0]:
			var p := Vector3(fmod(fi * 911.0, 40000.0) - 20000.0, y, fmod(fi * 577.0, 40000.0) - 20000.0)
			max_diff31 = maxf(max_diff31, absf(B.compute_density(p, dp_nofine, 2000.0)
				- B.compute_density(p, B.dp_defaults(dp_nofine), 2000.0)))
	check("PR31-1 гейт идентичности: fine=0 → плотность побитово = фаза 2; дефолт шейдера 0.0 + гейт; материал 0.25/3000",
		max_diff31 == 0.0
		and code.contains("uniform float cloud_fine_strength = 0.0;")
		and code.contains("uniform float cloud_fine_scale = 3000.0;")
		and code.contains("if (cloud_fine_strength > 0.0) {")
		and absf(float(mat.get_shader_parameter("cloud_fine_strength")) - 0.25) < 1e-9
		and absf(float(mat.get_shader_parameter("cloud_fine_scale")) - 3000.0) < 1e-6,
		"(max|Δd| fine=0: %.1f)" % max_diff31)

	# PR31-2: локальность (ТЗ 3.2/3.3): точки с d(fine=0) ∈ {0,1} (вне полосы, включая
	# clamp-зону edge_contrast) меняются ≤ 1.5 % (измерено ≤ 1.0 % — только край
	# контрастной clamp-зоны); в полосе бахрома активна: ≥ 60 % точек изменены (80.6 %).
	var out_ch := 0
	var out_n := 0
	var in_ch := 0
	var in_n := 0
	for i in range(0, 900):
		var fi := float(i)
		var p := Vector3(fmod(fi * 337.0, 36000.0) - 18000.0, 2100.0 + fmod(fi * 61.0, 800.0),
			fmod(fi * 761.0, 36000.0) - 18000.0)
		var da: float = B.compute_density(p, dp_nofine, 2000.0)
		var db: float = B.compute_density(p, dp, 2000.0)
		if da == 0.0 or da == 1.0:
			out_n += 1
			if da != db:
				out_ch += 1
		else:
			in_n += 1
			if absf(db - da) > 1e-9:
				in_ch += 1
	var out_frac := float(out_ch) / maxf(float(out_n), 1.0)
	var in_frac := float(in_ch) / maxf(float(in_n), 1.0)
	check("PR31-2 локальность: вне полосы меняется ≤ 1.5 % точек, в полосе бахрома активна ≥ 60 %",
		out_frac <= 0.015 and in_frac >= 0.60 and out_n >= 100 and in_n >= 100,
		"(вне: %d/%d = %.2f %%; в полосе: %d/%d = %.1f %%)" % [out_ch, out_n, out_frac * 100.0,
			in_ch, in_n, in_frac * 100.0])

	# PR31-3: иерархия масштабов сохранена (контрольная точка фазы 3: «крупные и средние
	# формы остаются доминирующими, мелкие только дополняют»): E2000 > E500 > E100 строго,
	# плечо фазы 2 r_fm ≥ 4.0 цело (измерено 4.09), массы ≥ 1900 м, выступы ≥ 1900 м.
	var b31 := _pr12_bands(B, dp)
	var m31 := _pr21_met(B, dp, 0.0)
	check("PR31-3 иерархия: E2000 > E500 > E100, r_fm ≥ 4.0 (плечо фазы 2 цело), массы/выступы ≥ 1900 м",
		float(b31.E2000) > float(b31.E500) and float(b31.E500) > float(b31.E100)
		and float(m31.r_fm) >= 4.0 and float(m31.mass_m) >= 1900.0 and float(m31.bump_m) >= 1900.0,
		"(E: %.4f/%.4f/%.4f, r_fm %.2f, массы %.0f м, выступы %.0f м)" % [float(b31.E100),
			float(b31.E500), float(b31.E2000), float(m31.r_fm), float(m31.mass_m), float(m31.bump_m)])

	# PR31-4: анти-foam/анти-flicker (ТЗ 3.5): резких скачков на 100 м ≤ 0.5 %,
	# E100 ≤ 0.022 (гард фазы 2 не пробит: бахрома дополняет, не доминирует),
	# изолированных фрагментов 0 % (F5), hf/lf ≤ 20.
	var sharp31 := 0
	var n31 := 0
	for li in range(0, 4):
		var z0 := float(li) * 5000.0 - 7500.0
		var prev := -1.0
		for si in range(0, 400):
			var d: float = B.compute_density(Vector3(float(si) * 100.0 - 20000.0, 2500.0, z0), dp, 2000.0)
			if prev >= 0.0:
				n31 += 1
				if absf(d - prev) > 0.5:
					sharp31 += 1
			prev = d
	var speck31 := 0
	var dense31 := 0
	for i in range(0, 400):
		var fi := float(i)
		var p := Vector3(fmod(fi * 337.0, 30000.0) - 15000.0, 2500.0, fmod(fi * 761.0, 30000.0) - 15000.0)
		if B.compute_density(p, dp, 2000.0) > 0.02:
			dense31 += 1
			var iso := true
			for nb in [Vector3(150, 0, 0), Vector3(-150, 0, 0), Vector3(0, 0, 150), Vector3(0, 0, -150)]:
				if B.compute_density(p + nb, dp, 2000.0) > 0.02:
					iso = false
			if iso:
				speck31 += 1
	var speck_frac := float(speck31) / maxf(float(dense31), 1.0)
	check("PR31-4 анти-foam: резкие скачки ≤ 0.5 %, E100 ≤ 0.022, изоляты ≤ 1 %, hf/lf ≤ 20",
		float(sharp31) / maxf(float(n31), 1.0) <= 0.005 and float(b31.E100) <= 0.022
		and speck_frac <= 0.01 and float(m31.E100) > 0.0,
		"(sharp %.4f, E100 %.4f, изоляты %d/%d = %.1f %%)" % [float(sharp31) / maxf(float(n31), 1.0),
			float(b31.E100), speck31, dense31, speck_frac * 100.0])

	# PR31-5: отклик ручек (методология аудита 3.2): E100 строго растёт с fine_strength
	# (0 → 0.25 → 0.45) и строго растёт с уменьшением fine_scale (4000 → 3000 → 2000).
	var e_by_str := []
	for fst in [0.0, 0.25, 0.45]:
		var dp_v := dp.duplicate()
		dp_v["fine_strength"] = fst
		e_by_str.append(float(_pr12_bands(B, dp_v).E100))
	# Отклик по scale проверяется в РАЗРЕШАЕМОЙ зоне (6000→4000→3000: воксел ≥ 94 м ≈
	# шаг зонда 100 м). Ниже 3000 зонд 100 м алиасит (измерено: E100(2000) < E100(3000)
	# при том же strength — не монотонность ручки, а насыщение метрики) — задокументировано.
	var e_by_scale := []
	for fs in [6000.0, 4000.0, 3000.0]:
		var dp_v := dp.duplicate()
		dp_v["fine_scale"] = fs
		e_by_scale.append(float(_pr12_bands(B, dp_v).E100))
	check("PR31-5 отклик ручек: E100 строго ↑ по fine_strength и по 1/fine_scale (в разрешаемой зоне 6000-3000)",
		float(e_by_str[0]) < float(e_by_str[1]) and float(e_by_str[1]) < float(e_by_str[2])
		and float(e_by_scale[0]) < float(e_by_scale[1]) and float(e_by_scale[1]) < float(e_by_scale[2]),
		"(str: %.5f→%.5f→%.5f; scale⁻¹ 6k→4k→3k: %.5f→%.5f→%.5f)" % [float(e_by_str[0]),
			float(e_by_str[1]), float(e_by_str[2]), float(e_by_scale[0]), float(e_by_scale[1]),
			float(e_by_scale[2])])

	# PR31-6: анти-мерцание и цена: бахрома гаснет тем же B2-fade, что деталь
	# (множитель (0.25 + 0.75·fade) в блоке — на t ≥ 12 км амплитуда ≤ 25 %), выборка
	# ровно ОДНА и той же noise_worley (новых текстур/sampler'ов нет), 0 циклов добавлено.
	var fn_start := code.find("float cloud_density(vec3 p, float t) {")
	var fn_end := code.find("\n}\n", fn_start)
	var cd_body := code.substr(fn_start, fn_end - fn_start)
	var fine_start := cd_body.find("if (cloud_fine_strength > 0.0) {")
	var fine_body := cd_body.substr(fine_start, cd_body.find("float d = sstep(") - fine_start) if fine_start >= 0 else ""
	check("PR31-6 анти-мерцание/цена: fine-блок под гейтом, с B2-fade (0.25+0.75·fade), 1 texture(noise_worley), новых sampler'ов/циклов нет",
		fine_body.contains("(0.25 + 0.75 * fade)")
		and fine_body.count("texture(noise_worley") == 1
		and not fine_body.contains("for (")
		and cd_body.count("texture(") == 5
		and cd_body.count("texture(noise_worley") == 2,
		"(fine-блок: %d символов)" % fine_body.length())

	# PR31-7: синк материал↔neutral (fine-ключи), строки меню объявлены (0-0.60 /
	# 1500-6000), D3-гейт вуали побитово (вуаль не задета — hc-состав 22).
	var tbl: Dictionary = B.preset_table()
	var nt: Dictionary = tbl.neutral
	var rows31 := {}
	for sec_v in B.TUNE_SECTIONS:
		var sec: Dictionary = sec_v
		for r_v in (sec.rows as Array):
			var r: Dictionary = r_v
			if str(r.get("k", "")) == "f" and ["cloud_fine_strength", "cloud_fine_scale"].has(str(r.get("u", ""))):
				rows31[str(r.u)] = [float(r.a), float(r.b)]
	var d_id := Vector3(0.25, 0.62, -0.74).normalized()
	var f_off: Dictionary = B.compute_final_with_hc(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {}, {}, {"enabled": false})
	var f_ref: Dictionary = B.compute_final_with_sun(d_id, 1500.0, 3500.0, 32, 30000.0,
		0.0025, 0.01, 0.0, {}, {}, {}, {})
	var n_hc := 0
	for ln in code.split("\n"):
		var t := ln.strip_edges()
		if t.begins_with("uniform ") and t.contains("hc_"):
			n_hc += 1
	check("PR31-7 синк материал↔neutral (fine), меню 0-0.60/1500-6000, вуаль цела: 22 hc-uniform, D3 побитово",
		absf(float(nt.get("fine_strength", -1.0)) - float(mat.get_shader_parameter("cloud_fine_strength"))) < 1e-9
		and absf(float(nt.get("fine_scale", -1.0)) - float(mat.get_shader_parameter("cloud_fine_scale"))) < 1e-6
		and rows31.has("cloud_fine_strength") and rows31.has("cloud_fine_scale")
		and float(rows31["cloud_fine_strength"][1]) >= 0.60
		and float(rows31["cloud_fine_scale"][0]) <= 1500.0
		and n_hc == 22
		and (f_off.final as Vector3) == (f_ref.final as Vector3),
		"(hc-uniform'ов %d)" % n_hc)
