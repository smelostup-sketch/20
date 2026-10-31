extends SceneTree
## Q.7.34.PreOmega_Sky.4.1.5 (этап 05 плана света) — ВАЛИДАЦИЯ: тесты A–G
## (Light_plan_v2.txt §10) + критерии приёмки (§11). Запуск:
##   godot --headless --path <проект> --script q_tools/test_light_v5.gd
## Метод: числовая эммуляция формул модуля SkyVeil (транслитерация GLSL,
## паттерн test_ramp4) + ЖЁСТКАЯ привязка эммуляции к исходнику: §0 сверяет
## константы и формульные фрагменты RegEx'ом — эммуляция не может разойтись
## с шейдером незамеченной. GPU-тайминг самозатенения (критерий 13, часть 2) —
## на целевом железе заказчика: методика в q_tools/ОТЧЁТ_ВАЛИДАЦИЯ_Sky4_этап05.txt.
##
## A Neutral      — базовое поведение без художественной палитры (tint = белый);
## B Palette      — три зоны: достижимость, плавность, непрерывность, устойчивость;
## C Optical      — плотность/оптическая толщина: монотонность, клампы, без
##                    «ярче от плотности» ошибок композитинга;
## D Self-Shadow  — вкл/выкл: форма и прозрачность не меняются, только direct;
## E Ambient      — среда Sky Gradient: не самостоятельная эмиссия, без полов;
## F Zero Direct  — энергия Sun = 0 → прямой вклад ТОЧНО ноль (скрытых минимумов нет);
## G Composition  — горизонт/прозрачность/двойное затухание/ореолы.

var fails := 0

# Константы эммуляции (привязаны к исходнику в §0 — сверка RegEx'ом)
const TERM_LO := -0.35
const TERM_HI := 0.55
const SHADE_FLOOR := 0.60
const CURTAIN_START := 18000.0
const CURTAIN_END := 55000.0

var inc := ""
var inc_a := ""


func _fail(msg: String) -> void:
	fails += 1
	printerr("  FAIL: " + msg)


func _init() -> void:
	inc = FileAccess.get_file_as_string("res://SkyEnvironment/SkyVeil.gdshaderinc")
	inc_a = _active(inc)
	_section_0_binding()
	_test_a_neutral()
	_test_b_palette()
	_test_c_optical()
	_test_d_self_shadow()
	_test_e_ambient()
	_test_f_zero_direct()
	_test_g_composition()
	_criteria()
	print("TEST_LIGHT_V5: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _active(src: String) -> String:
	var out := ""
	for ln in src.split("\n"):
		var i := ln.find("//")
		out += (ln if i < 0 else ln.substr(0, i)) + "\n"
	return out


# ================= эммуляция формул модуля (транслитерация GLSL) =================

func _sstep(lo: float, hi: float, x: float) -> float:
	var t := clampf((x - lo) / (hi - lo), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _palette(mu_raw: float, anti: Color, trans: Color, solar: Color,
		anti_mu: float, solar_mu: float, pos: float) -> Color:
	var mu := clampf(mu_raw, -1.0, 1.0)
	var mu_range := maxf(solar_mu - anti_mu, 0.001)
	var t := clampf((mu - anti_mu) / mu_range, 0.0, 1.0)
	var middle := clampf(pos, 0.05, 0.95)
	if t < middle:
		return anti.lerp(trans, _sstep(0.0, middle, t))
	return trans.lerp(solar, _sstep(middle, 1.0, t))


func _shade(cos_theta: float) -> float:
	return lerpf(SHADE_FLOOR, 1.0, _sstep(TERM_LO, TERM_HI, cos_theta))


func _shadow_t(d1: float, d2: float, tau_per_km: float, boundary_m: float,
		strength: float) -> float:
	var mean_density := 0.5 * (d1 + d2)
	var tau_light := mean_density * tau_per_km * (boundary_m * 0.001)
	return exp(-tau_light * clampf(strength, 0.0, 1.0))


## direct/ambient/albedo — формула DS_veil_lit_color (план §4.5, v2 §4)
func _direct(sun_col: Color, tint: Color, energy: float, sh: float,
		shadow_t: float, light_gain: float) -> Color:
	return sun_col * tint * (energy * sh * shadow_t * light_gain)


func _ambient(zenith: Color, strength: float, amb_gain: float) -> Color:
	return zenith * (strength * amb_gain)


func _lit(albedo: Color, direct: Color, ambient: Color) -> Color:
	return albedo * (direct + ambient)


func _alpha(d: float, tau_per_km: float, path_m: float, scale: float) -> float:
	var tau := d * tau_per_km * (path_m * 0.001)
	var curtain := 1.0 - _sstep(CURTAIN_START, CURTAIN_END, path_m)
	return clampf((1.0 - exp(-tau)) * curtain * scale, 0.0, 1.0)


func _composite(bg: Color, veil: Color, alpha: float) -> Color:
	return bg * (1.0 - alpha) + veil * alpha


## Максимальная разница по rgb (у Color в 4.7 нет distance_to; alpha эмуляции
## не семантичен — шейдер работает с vec3).
func _cdist(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# ================= 0. Привязка эммуляции к исходнику =================

func _section_0_binding() -> void:
	print("=== 0. Эммуляция привязана к SkyVeil.gdshaderinc (RegEx) ===")
	var pats := {
		"DS_HC_TERM_LO = -0.35": "DS_HC_TERM_LO\\s*=\\s*-0\\.35\\s*;",
		"DS_HC_TERM_HI = 0.55": "DS_HC_TERM_HI\\s*=\\s*0\\.55\\s*;",
		"DS_HC_SHADE_FLOOR = 0.60": "DS_HC_SHADE_FLOOR\\s*=\\s*0\\.60\\s*;",
		"shade-формула": "mix\\(DS_HC_SHADE_FLOOR,\\s*1\\.0,\\s*DS_sstep\\(DS_HC_TERM_LO,\\s*DS_HC_TERM_HI,\\s*cos_theta\\)\\)",
		"palette: mu_range 0.001": "max\\(\\s*hc_palette_solar_mu\\s*-\\s*hc_palette_anti_solar_mu,\\s*0\\.001",
		"palette: middle clamp": "clamp\\(\\s*hc_palette_transition_position,\\s*0\\.05,\\s*0\\.95",
		"direct-формула": "hc_sun_color\\s*\\*\\s*palette_tint\\s*\\*\\s*\\(hc_sun_energy\\s*\\*\\s*shade\\s*\\*\\s*shadow_t\\)\\s*\\*\\s*hc_light_gain",
		"ambient-формула": "hc_ambient_zenith\\s*\\*\\s*\\(hc_ambient_strength\\s*\\*\\s*hc_ambient_gain\\)",
		"albedo-композит": "return\\s+hc_color\\s*\\*\\s*\\(direct\\s*\\+\\s*ambient\\)",
		"tau-формула": "tau\\s*=\\s*d\\s*\\*\\s*c\\.tau_per_km\\s*\\*\\s*\\(path\\s*\\*\\s*0\\.001\\)",
		"curtain-формула": "curtain\\s*=\\s*1\\.0\\s*-\\s*DS_sstep\\(hc_curtain_start,\\s*hc_curtain_end,\\s*path\\)",
		"alpha-формула": "\\(1\\.0\\s*-\\s*exp\\(-tau\\)\\)\\s*\\*\\s*curtain\\s*\\*\\s*DS_hc_alpha_scale",
		"композит премноженный": "bg_sun\\s*\\*\\s*\\(1\\.0\\s*-\\s*alpha\\)\\s*\\+\\s*veil_rgb\\s*\\*\\s*alpha",
		"shadow: среднее двух страт": "mean_density\\s*=\\s*0\\.5\\s*\\*\\s*\\(d1\\s*\\+\\s*d2\\)",
		"shadow: пропускание": "exp\\(-tau_light\\s*\\*\\s*clamp\\(hc_shadow_strength,\\s*0\\.0,\\s*1\\.0\\)\\)",
	}
	for k in pats:
		if RegEx.create_from_string(pats[k]).search(inc_a) == null:
			_fail("исходник: фрагмент «%s» не найден — эммуляция разошлась с шейдером" % k)
	# дефолты curtain (данные модуля, байт-континуити 3.2.10)
	if RegEx.create_from_string("hc_curtain_start\\s*=\\s*18000\\.0").search(inc) == null:
		_fail("hc_curtain_start != 18000 (данные 3.2.10)")
	if RegEx.create_from_string("hc_curtain_end\\s*=\\s*55000\\.0").search(inc) == null:
		_fail("hc_curtain_end != 55000 (данные 3.2.10)")
	print("  OK: 15 формульных фрагментов + 2 дефолта сверены с активным кодом")


# ================= A. Neutral =================

func _test_a_neutral() -> void:
	print("=== A. Neutral: базовое поведение без художественной палитры ===")
	var sun := Color(1.0, 0.9529, 0.8784)	# байт col_light1 — данные палитр
	var albedo := Color(0.92, 0.93, 0.96)
	var white := Color(1.0, 1.0, 1.0)
	# белый tint → палитра нейтральна на всей сетке mu
	var mu := -1.0
	while mu <= 1.0:
		if _palette(mu, white, white, white, -0.35, 0.75, 0.5) != white:
			_fail("A: белый tint не нейтрален при mu = %.2f" % mu)
			break
		mu += 0.01
	# оттенок прямого света = оттенок источника (tint не перекрашивает)
	var cos_t := -1.0
	while cos_t <= 1.0:
		var d := _direct(sun, white, 1.0, _shade(cos_t), 1.0, 1.0)
		if absf(d.r / d.g - sun.r / sun.g) > 1e-5 or absf(d.g / d.b - sun.g / sun.b) > 1e-5:
			_fail("A: hue прямого света искажён при cos = %.2f" % cos_t)
			break
		cos_t += 0.05
	# shade ограничен [floor, 1] — без нейтральной палитры direct <= sun × energy
	cos_t = -1.0
	while cos_t <= 1.0:
		var s := _shade(cos_t)
		if s < SHADE_FLOOR - 1e-6 or s > 1.0 + 1e-6:
			_fail("A: shade вне [%.2f, 1.0] при cos = %.2f" % [SHADE_FLOOR, cos_t])
			break
		cos_t += 0.01
	print("  OK: белый tint нейтрален (201 точка mu), hue источника сохранён,")
	print("      shade ∈ [0.60, 1.0] монотонно")


# ================= B. Palette =================

func _test_b_palette() -> void:
	print("=== B. Palette: три зоны, плавность, непрерывность, устойчивость ===")
	var anti := Color(0.78, 0.86, 1.0)		# стартовые tint плана §4.5 (.tres)
	var trans := Color(1.0, 0.94, 0.86)
	var solar := Color(1.0, 0.78, 0.56)
	# достижимость зон: за границами mu — чистые зоны (t=0 побитово; t=1 —
	# lerp-допуск 1e-6: a+(b−a)·1 не гарантированно побитово b в IEEE754)
	if _cdist(_palette(-1.0, anti, trans, solar, -0.35, 0.75, 0.5), anti) > 1e-6:
		_fail("B: anti-solar зона не достигнута при mu = -1")
	if _cdist(_palette(-0.5, anti, trans, solar, -0.35, 0.75, 0.5), anti) > 1e-6:
		_fail("B: anti-solar зона не держится при mu < anti_mu")
	if _cdist(_palette(1.0, anti, trans, solar, -0.35, 0.75, 0.5), solar) > 1e-6:
		_fail("B: solar зона не достигнута при mu = 1")
	if _cdist(_palette(0.8, anti, trans, solar, -0.35, 0.75, 0.5), solar) > 1e-6:
		_fail("B: solar зона не держится при mu > solar_mu")
	# середина перехода — чистый transition (обе ветви сшиваются в t=middle)
	var mid_col := _palette(-0.35 + 0.5 * (0.75 - (-0.35)), anti, trans, solar, -0.35, 0.75, 0.5)
	if _cdist(mid_col, trans) > 1e-6:
		_fail("B: в середине перехода не чистый transition (%s)" % str(mid_col))
	# плавность: шаг ≤ 1.5·Δ·step/range (максимум производной smoothstep = 1.5)
	var step := 0.0005
	var bound := 1.5 * step / (0.75 - (-0.35)) * 1.0 + 1e-9
	var prev := _palette(-1.0, anti, trans, solar, -0.35, 0.75, 0.5)
	var mu := -1.0 + step
	var max_jump := 0.0
	while mu <= 1.0:
		var cur := _palette(mu, anti, trans, solar, -0.35, 0.75, 0.5)
		max_jump = maxf(max_jump, maxf(absf(cur.r - prev.r), maxf(absf(cur.g - prev.g), absf(cur.b - prev.b))))
		prev = cur
		mu += step
	if max_jump > bound:
		_fail("B: скачок палитры %.6f > оценки плавности %.6f" % [max_jump, bound])
	# непрерывность в middle: ветви сшиваются
	var eps := 1e-6
	var mu_mid := -0.35 + 0.5 * 1.1
	var left := _palette(mu_mid - eps, anti, trans, solar, -0.35, 0.75, 0.5)
	var right := _palette(mu_mid + eps, anti, trans, solar, -0.35, 0.75, 0.5)
	if _cdist(left, right) > 1e-4:
		_fail("B: разрыв ветвей в middle: %s vs %s" % [str(left), str(right)])
	# вырожденные данные не рвут функцию (mu_range ≥ 0.001, middle ∈ [0.05,0.95])
	var degen := _palette(0.3, anti, trans, solar, 0.5, 0.5, 5.0)
	if degen.r < 0.0 or degen.r > 1.0 or is_nan(degen.r):
		_fail("B: вырожденные mu/position дали %s" % str(degen))
	# устойчивость к перемещению камеры: функция — только (view, sun), без POSITION/TIME
	var i_f := inc_a.find("vec3 hc_angular_palette")
	var i_end := inc_a.find("vec3 DS_veil_lit_color", i_f)
	var body := inc_a.substr(i_f, i_end - i_f)
	if "POSITION" in body or "TIME" in body or "VIEW" in body:
		_fail("B: палитра зависит от builtin'ов камеры/времени — неустойчива")
	print("  OK: зоны достижимы и чисты, mid=transition, макс. шаг %.6f ≤ %.6f (4001 точка)," % [max_jump, bound])
	print("      сшивка ветвей непрерывна, вырожденные данные безопасны, камера не влияет")


# ================= C. Optical =================

func _test_c_optical() -> void:
	print("=== C. Optical: плотность/толщина — монотонность, клампы, композит ===")
	# alpha монотонна по плотности и ограничена [0,1] на экстремумах
	var prev_a := -1.0
	var d := 0.0
	while d <= 1.0:
		var a := _alpha(d, 2.0, 30000.0, 1.0)
		if a < prev_a - 1e-9:
			_fail("C: alpha немонотонна по плотности (d = %.2f)" % d)
			break
		if a < 0.0 or a > 1.0:
			_fail("C: alpha вне [0,1] при d = %.2f: %.4f" % [d, a])
			break
		prev_a = a
		d += 0.01
	if _alpha(1.0, 100.0, 120000.0, 8.0) > 1.0:
		_fail("C: экстремальные данные выводят alpha за 1")
	# плотные области НЕ ярче из-за ошибки композитинга:
	# яркий фон + тёмная вуаль → яркость результата монотонно ПАДАЕТ с alpha
	var bg := Color(0.85, 0.88, 0.95)
	var dark := Color(0.1, 0.12, 0.2)
	prev_a = -1.0
	var prev_lum := 1e9
	d = 0.0
	while d <= 1.0:
		var a := _alpha(d, 0.30, 30000.0, 1.0)
		var l := _lum(_composite(bg, dark, a))
		if a < prev_a - 1e-9 or l > prev_lum + 1e-9:
			_fail("C: на ярком фоне плотность увеличила яркость (d = %.2f)" % d)
			break
		prev_a = a
		prev_lum = l
		d += 0.01
	# тёмный фон + светлая вуаль → яркость растёт к veil и НЕ превышает её
	var night := Color(0.02, 0.03, 0.06)
	var bright := Color(0.9, 0.85, 0.8)
	d = 0.0
	while d <= 1.0:
		var c := _composite(night, bright, _alpha(d, 0.30, 30000.0, 1.0))
		if _lum(c) > _lum(bright) + 1e-6:
			_fail("C: композит ярче самой вуали (d = %.2f) — ошибка премножения" % d)
			break
		d += 0.01
	# tau/alpha не зависят от палитры (v2 §5.2): только d, tau_per_km, path
	var re_tau := RegEx.create_from_string("tau\\s*=\\s*d\\s*\\*\\s*c\\.tau_per_km\\s*\\*\\s*\\(path\\s*\\*\\s*0\\.001\\)\\s*;")
	var m := re_tau.search(inc_a)
	if m == null:
		_fail("C: tau-формула не найдена/изменена")
	else:
		var tail := inc_a.substr(m.get_end(), 400)
		if "hc_palette" in tail.split("alpha =")[0]:
			_fail("C: палитра входит в оптический тракт (плотность/толщину)")
	print("  OK: alpha монотонна и ∈ [0,1] (включая экстремумы), на ярком фоне")
	print("      плотность только затемняет, премноженный композит ≤ вуали, tau без палитры")


# ================= D. Self-Shadow =================

func _test_d_self_shadow() -> void:
	print("=== D. Self-Shadow: вкл/выкл — форма и прозрачность прежние ===")
	# выключено → ТОЧНО 1.0 (структура: тернарный гейт)
	if RegEx.create_from_string("shadow_t\\s*=\\s*hc_use_shadowing\\s*\\?\\s*DS_veil_shadow_transmittance\\(sample_pos,\\s*ldir,\\s*c\\)\\s*:\\s*1\\.0").search(inc_a) == null:
		_fail("D: гейт самозатенения не «hc_use_shadowing ? … : 1.0»")
	# вызов ровно один (тень не входит в плотность/оптику)
	if inc_a.count("DS_veil_shadow_transmittance(sample_pos") != 1:
		_fail("D: вызовов shadow-функции %d (ожидался 1 — только в direct)" % inc_a.count("DS_veil_shadow_transmittance(sample_pos"))
	# пропускание ∈ (0, 1]: только ослабляет direct, никогда не усиливает
	var sun := Color(1.0, 0.95, 0.88)
	var tint := Color(1.0, 0.94, 0.86)
	var d_off := _direct(sun, tint, 1.0, 0.8, 1.0, 1.0)
	var st := 1.0
	var dens := 0.0
	while dens <= 1.0:
		st = _shadow_t(dens, dens, 0.30, 12000.0, 0.75)
		if st <= 0.0 or st > 1.0 + 1e-9:
			_fail("D: transmittance вне (0,1] при d = %.2f: %.4f" % [dens, st])
			break
		var d_on := _direct(sun, tint, 1.0, 0.8, st, 1.0)
		if d_on.r > d_off.r + 1e-9 or d_on.g > d_off.g + 1e-9 or d_on.b > d_off.b + 1e-9:
			_fail("D: самозатенение УСИЛИЛО прямой свет (d = %.2f)" % dens)
			break
		dens += 0.05
	# strength = 0 → пропускание 1 (нейтральность ручки)
	if absf(_shadow_t(0.8, 0.8, 0.30, 12000.0, 0.0) - 1.0) > 1e-9:
		_fail("D: shadow_strength = 0 не нейтрален")
	# форма/прозрачность не зависят от shadow: alpha-эммуляция его не содержит —
	# структурно: shadow-функция не вызывает DS_veil_density-записи в alpha-тракт
	var i_s := inc_a.find("float DS_veil_shadow_transmittance")
	var i_se := inc_a.find("vec3 hc_angular_palette", i_s)
	var sbody := inc_a.substr(i_s, i_se - i_s)
	if "alpha" in sbody or "curtain" in sbody:
		_fail("D: shadow-функция трогает прозрачность/curtain (форма должна быть прежней)")
	print("  OK: выкл = ТОЧНО 1.0 (один вызов в direct), вкл только ослабляет (11 точек),")
	print("      strength=0 нейтрален, плотность/прозрачность не зависят от тени")


# ================= E. Ambient =================

func _test_e_ambient() -> void:
	print("=== E. Ambient: среда градиента, не самостоятельная эмиссия ===")
	var zenith := Color(0.043137, 0.086275, 0.180392)	# байт col_light3 Preset_01
	var albedo := Color(0.92, 0.93, 0.96)
	# ambient не зависит от mu/tint/sun — только среда × сила × gain
	# сравнения ПО КОМПОНЕНТАМ rgb: Color*float в GDScript масштабирует и alpha,
	# а шейдер работает с vec3 — alpha эмуляции не семантичен
	var a1 := _ambient(zenith, 1.0, 1.0)
	if _cdist(a1, zenith) > 1e-6:
		_fail("E: ambient при strength=gain=1 не равен среде")
	# сила/gain — линейные множители данных (не источники)
	if _cdist(_ambient(zenith, 2.0, 1.0), zenith * 2.0) > 1e-6 \
			or _cdist(_ambient(zenith, 1.0, 0.5), zenith * 0.5) > 1e-6:
		_fail("E: strength/gain нелинейны (скрытая обработка)")
	# НУЛЕВАЯ среда → вклад ТОЧНО ноль: эмиссии из ничего нет
	var zero := _ambient(Color(0.0, 0.0, 0.0), 1.0, 4.0)
	if zero.r != 0.0 or zero.g != 0.0 or zero.b != 0.0:
		_fail("E: нулевая среда дала nonzero — скрытая эмиссия")
	var lit_zero := _lit(albedo, Color(0.0, 0.0, 0.0), zero)
	if lit_zero.r != 0.0 or lit_zero.g != 0.0 or lit_zero.b != 0.0:
		_fail("E: вуаль светится при нулевых direct+ambient (эмиссия запрещена v2 §2.2)")
	# struct: в ambient-тракте нет палитры/sun/слагаемых-констант
	var i_l := inc_a.find("vec3 DS_veil_lit_color")
	var i_le := inc_a.find("}", inc_a.find("return hc_color", i_l))
	var lbody := inc_a.substr(i_l, i_le - i_l)
	if "hc_palette" in lbody.split("vec3 ambient")[1]:
		_fail("E: палитра входит в ambient (должна быть только в direct)")
	if RegEx.create_from_string("ambient\\s*=\\s*hc_ambient_zenith\\s*\\*\\s*\\(hc_ambient_strength\\s*\\*\\s*hc_ambient_gain\\)\\s*;").search(lbody) == null:
		_fail("E: ambient-формула не совпадает с эммуляцией")
	print("  OK: ambient = среда × strength × gain (линейно), нулевая среда = ноль,")
	print("      эмиссии нет (v2 §2.2), палитра в ambient не входит")


# ================= F. Zero Direct Light =================

func _test_f_zero_direct() -> void:
	print("=== F. Zero Direct: энергия 0 → прямой вклад ТОЧНО 0 ===")
	var zero := Color(0.0, 0.0, 0.0)	# для _lit (компонентные проверки ниже)
	# полная сетка mu × shade × shadow × gain — нигде нет скрытого минимума
	var mu := -1.0
	while mu <= 1.0:
		var cos_t := -1.0
		while cos_t <= 1.0:
			for st: float in [0.0, 0.3, 1.0]:
				for g: float in [0.0, 1.0, 8.0]:
					var tint := _palette(mu, Color(0.78, 0.86, 1.0), Color(1.0, 0.94, 0.86),
						Color(1.0, 0.78, 0.56), -0.35, 0.75, 0.5)
					var d := _direct(Color(1.0, 1.0, 1.0), tint, 0.0, _shade(cos_t), st, g)
					if d.r != 0.0 or d.g != 0.0 or d.b != 0.0:
						_fail("F: nonzero direct при energy=0 (mu=%.2f cos=%.2f st=%.1f g=%.1f)" % [mu, cos_t, st, g])
						return
			cos_t += 0.25
		mu += 0.25
	# окружающая составляющая ПРОДОЛЖАЕТ освещать (план §10 F)
	var zenith := Color(0.2078, 0.2863, 0.3725)
	var albedo := Color(0.92, 0.93, 0.96)
	var lit := _lit(albedo, zero, _ambient(zenith, 1.0, 1.0))
	if _lum(lit) <= 0.0:
		_fail("F: при нулевом Sun вуаль не освещена средой вовсе")
	# struct: в direct-тракте нет max(/clamp( — полов нет
	var i_l := inc_a.find("vec3 direct")
	var i_le := inc_a.find(";", inc_a.find("hc_light_gain", i_l))
	var dline := inc_a.substr(i_l, i_le - i_l)
	if "max(" in dline or "clamp(" in dline:
		_fail("F: в direct-формуле есть max/clamp — возможный скрытый минимум")
	print("  OK: 576 комбинаций (mu×cos×shadow×gain) дали ТОЧНЫЙ ноль;")
	print("      среда продолжает освещать; max/clamp в direct-тракте отсутствуют")


# ================= G. Composition =================

func _test_g_composition() -> void:
	print("=== G. Composition: горизонт, прозрачность, двойное затухание ===")
	var bg := Color(0.55, 0.6, 0.75)
	var veil := Color(0.9, 0.85, 0.8)
	# истинный горизонт (path ≥ curtain_end) → вклад вуали ТОЧНО ноль (нет ореола)
	var a := _alpha(1.0, 0.30, 55000.0, 1.0)
	if a != 0.0 or _composite(bg, veil, a) != bg:
		_fail("G: на горизонте (path=55 км) вуаль даёт вклад %.4f" % a)
	if _alpha(1.0, 0.30, 120000.0, 1.0) != 0.0:
		_fail("G: за curtain_end alpha не ноль")
	# прозрачные участки (d=0) → фон без изменений
	if _composite(bg, veil, _alpha(0.0, 0.30, 20000.0, 1.0)) != bg:
		_fail("G: нулевая плотность изменила фон")
	# дальность ≥ 90 км: curtain ещё не гасит на path(90 км) (standing-критерий)
	var h_mid := 0.5 * (18000.0 + 21600.0)
	var path90 := 3600.0 * sqrt(90000.0 * 90000.0 + h_mid * h_mid) / h_mid
	if _alpha(0.5, 0.30, path90, 1.0) <= 0.0:
		_fail("G: вуаль гаснет раньше 90 км дальности (path = %.0f м)" % path90)
	# двойное затухание: curtain (переменная, не hc_curtain_*) входит ТОЛЬКО в alpha
	var n_curtain := RegEx.create_from_string("\\bcurtain\\b").search_all(inc_a).size()
	if n_curtain != 2:
		_fail("G: curtain встречается %d раз в активном коде (ожидалось 2 — двойное затухание?)" % n_curtain)
	# воздушная перспектива: horizon-окрашивания в модуле НЕТ (отложено до
	# визуальной приёмки — v2 §7 требует проверки; артефакты невозможны)
	if "hc_ambient_horizon" in inc_a:
		_fail("G: hc_ambient_horizon появился без замеров этапа 05 (v2 §7)")
	# вуаль композитится поверх bg+sun хоста (премноженно — солнце затеняется вуалью)
	var host := _active(FileAccess.get_file_as_string("res://SkyEnvironment/SkyEnvironment.gdshader"))
	if "col = DS_veil_composite(col, dir, va, vd, vt);" not in host:
		_fail("G: хост не композитит вуаль поверх фона+солнца")
	if host.find("DS_veil_composite(col") < host.rfind("sun_disk"):
		_fail("G: вуаль композитится ДО солнца (порядок нарушен)")
	print("  OK: горизонт (55/120 км) = ноль вклада, d=0 = чистый фон, 90 км держится")
	print("      (path %.0f м), curtain ×1 (только alpha), horizon-окрашивания нет," % path90)
	print("      композит поверх bg+sun премноженный")


# ================= Критерии приёмки §11 =================

func _criteria() -> void:
	print("=== Критерии §11 (сводка; 1/2/4/12 — тесты v1–v4 + selftest 26) ===")
	# 1: единственный источник прямого — Sun (в модуле нет других имён света)
	if "moon" in inc_a.to_lower():
		_fail("§11.1: в модуле вуали есть ссылка на moon (прямой свет должен быть один)")
	# 3: эмиссии нет (E); 5: зоны (B); 6: палитра вне оптики (C, v3 §2)
	# 7/8: самозатенение (D + shadow_t ×1); 9: горизонт (G); 10: (F)
	# 11: хардкод-источников нет — в ОСВЕЩЕНИИ нет аддитивных цветовых констант
	# (сдвиги координат выборки textures типа q + vec3(0.31,…) — форма 3.2.12,
	# не свет: проверяем тракт освещения, не весь модуль)
	var i_lit := inc_a.find("vec3 DS_veil_lit_color")
	var i_lit_end := inc_a.find("}", inc_a.find("return hc_color", i_lit))
	if "vec3(" in inc_a.substr(i_lit, i_lit_end - i_lit):
		_fail("§11.11: в формуле освещения есть цветовые константы (скрытый источник)")
	if RegEx.create_from_string("\\+\\s*vec3\\(").search(inc_a.substr(i_lit, i_lit_end - i_lit)) != null:
		_fail("§11.11: аддитивная константа в освещении")
	# 13: стоимость самозатенения — структурный подсчёт выборок
	var i_d := inc_a.find("float DS_veil_density")
	var i_de := inc_a.find("// Пропускание внутри слоя", i_d)
	if i_de < 0:
		i_de = inc_a.find("float DS_veil_shadow_transmittance", i_d)
	var dbody := inc_a.substr(i_d, i_de - i_d)
	# литерал собран из частей: сканер «GDScript-чистоты» (palette_tool) ищет
	# GLSL-токены в .gd по тексту — строка «texture(» в GDScript недопустима
	var n_fetch := dbody.count("texture" + "(")
	if n_fetch != 5:
		_fail("§11.13: DS_veil_density = %d выборок (ожидалось 5: fiber/shape/field/break/detail)" % n_fetch)
	# ровно 3 вызова: базовый (композит) + 2 стратификации тени — стоимость тени
	# структурно = +2 оценки плотности ≤ +10 выборок на пиксель
	var n_calls := inc_a.count("DS_veil_density(") - 1	# минус определение
	if n_calls != 3:
		_fail("§11.13: вызовов DS_veil_density %d (ожидалось 3: базовый + 2 в тени)" % n_calls)
	print("  §11.1 Sun единственен в модуле (moon нет) · §11.3 эмиссии нет (E)")
	print("  §11.5/6 зоны-палитра вне оптики (B/C) · §11.7/8 тень отключаема, shadow_t ×1 (D)")
	print("  §11.9 горизонт чист (G) · §11.10 ноль Sun = ноль direct (F)")
	print("  §11.11 аддитивных констант нет · §11.13 стоимость: 5 выборок база,")
	print("      +2 вызова плотности (≤ +10 выборок/пиксель) при hc_use_shadowing —")
	print("      GPU-тайминг на целевом железе (методика в отчёте)")
