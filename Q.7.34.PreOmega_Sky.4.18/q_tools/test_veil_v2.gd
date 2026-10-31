extends SceneTree
## Q7.34.PreOmega_Sky3.2.8 (S11, V2) — приёмка данных вуали: профиль-компонент,
## apply_veil, сохранение/загрузка кругом через валидатор, структура панели.
## Запуск: godot --headless --path <проект> --script q_tools/test_veil_v2.gd
## Разделы:
##  1) SkyVeilProfile: 8 export-полей, дефолты (enabled=false, shadowing=false);
##  2) старые пресеты: 10 .tres грузятся, veil == null, валидатор 0 ошибок;
##  3) apply_veil на реальном ShaderMaterial: null → только гейт off; профиль →
##     8 uniform'ов + свет от солнца; выключение → гейт назад (побитово off);
##  4) круг: ResourceSaver → .tres → load → поля равны, валидатор 0 ошибок;
##  5) структура: панель (вкладка «Вуаль», порядок, индекс «Отладки» 6),
##     контроллер (apply_veil вызывается из apply_preset).
## 4.1.1: присвоения p.light убраны — поле light и правило 4 валидатора удалены
## (граница 30.10 п.4); вкладка «Свет сцены» панели сохранена (приказ 31.10 п.3).

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)

func _init() -> void:
	var ProfileScript: GDScript = load("res://SkyEnvironment/SkyVeilProfile.gd")
	var PresetScript: GDScript = load("res://SkyEnvironment/SkyPreset.gd")
	var CtrlScript: GDScript = load("res://SkyEnvironment/SkyEnvironmentController.gd")
	var ValidatorScript: GDScript = load("res://SkyEnvironment/SkyPresetValidator.gd")
	var LightCtrlScript: GDScript = load("res://SkyEnvironment/SkyLightController.gd")

	print("=== 1. SkyVeilProfile: 8 полей, дефолты ===")
	var v: Resource = ProfileScript.new()
	var props := []
	for pr in v.get_property_list():
		if pr["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and not pr["name"].begins_with("_"):
			props.append(pr["name"])
	if props.size() != 8:
		_fail("ожидалось 8 export-полей, найдено %d: %s" % [props.size(), str(props)])
	var want := {"veil_enabled": false, "veil_amount": 1.0,
		"veil_color": Color(0.92, 0.93, 0.96), "veil_light_gain": 1.0,
		"veil_ambient_gain": 1.0, "veil_coverage": 0.52, "veil_tau_per_km": 0.30,
		"veil_use_shadowing": false}
	for k in want:
		if v.get(k) != want[k]:
			_fail("дефолт %s = %s, ожидалось %s" % [k, str(v.get(k)), str(want[k])])
	print("  OK: поля %s" % str(props))

	print("=== 2. Пресеты: вуаль включена ДАННЫМИ (приказ 0.2), валидатор 0 ошибок ===")
	var presets := []
	for i in range(1, 11):
		var p: Resource = load("res://SkyEnvironment/SkyPreset/Preset_%02d.tres" % i)
		if p == null:
			_fail("Preset_%02d не загрузился" % i)
			continue
		if p.veil == null or p.veil.veil_enabled != true:
			_fail("Preset_%02d: вуаль должна быть включена данными пресета (veil_enabled = true)" % i)
		var res: Dictionary = ValidatorScript.validate(p)
		if not res["errors"].is_empty():
			_fail("Preset_%02d: ошибки валидатора %s" % [i, str(res["errors"])])
		presets.append(p)
	print("  OK: 10 пресетов, veil_enabled = true (данные .tres), 0 ошибок")

	print("=== 3. apply_veil на реальном материале ===")
	var sh: Shader = load("res://SkyEnvironment/SkyEnvironment.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var ctl: Node = CtrlScript.new()
	ctl.sky_material = mat
	# 3a. preset без профиля → только гейт off, кадр побитово прежний
	var p_null: Resource = PresetScript.new()
	ctl.apply_veil(p_null)
	if mat.get_shader_parameter("hc_enabled") != false:
		_fail("veil == null: hc_enabled должен быть false")
	# 3b. включённый профиль → 8 uniform'ов + свет от солнца
	var pv: Resource = ProfileScript.new()
	pv.veil_enabled = true
	pv.veil_amount = 0.7
	pv.veil_color = Color(0.5, 0.6, 0.7)
	pv.veil_light_gain = 1.5
	pv.veil_ambient_gain = 0.5
	pv.veil_coverage = 0.4
	pv.veil_tau_per_km = 0.5
	pv.veil_use_shadowing = true
	var p_on: Resource = PresetScript.new()
	p_on.veil = pv
	ctl.sun_azimuth = 123.0
	ctl.sun_elevation = 42.0
	ctl.apply_veil(p_on)
	var pairs := {"hc_enabled": true, "DS_hc_alpha_scale": 0.7, "hc_light_gain": 1.5,
		"hc_ambient_gain": 0.5, "hc_coverage": 0.4, "hc_tau_per_km": 0.5,
		"hc_use_shadowing": true}
	for k in pairs:
		var got: Variant = mat.get_shader_parameter(k)
		if typeof(got) == TYPE_FLOAT and typeof(pairs[k]) == TYPE_FLOAT:
			if not is_equal_approx(got, pairs[k]):
				_fail("%s = %s, ожидалось %s" % [k, str(got), str(pairs[k])])
		elif got != pairs[k]:
			_fail("%s = %s, ожидалось %s" % [k, str(got), str(pairs[k])])
	if Color(mat.get_shader_parameter("hc_color")) != Color(0.5, 0.6, 0.7):
		_fail("hc_color не совпал с veil_color")
	# Sky3.2.14 (H1): ЗАГЛУШКИ cloud_light_direction нет вообще — uniform удалён
	# из хоста; направление света вуали = sk_sun_dir (геометрия солнца)
	var uni_names := []
	for u in sh.get_shader_uniform_list():
		uni_names.append(u["name"])
	if "cloud_light_direction" in uni_names:
		_fail("H1: заглушка cloud_light_direction всё ещё в хосте")
	if mat.get_shader_parameter("cloud_light_color") != null:
		_fail("откат: apply_veil пишет cloud_light_color (освещение отложено)")
	# 3c. выключение → гейт назад (приёмка «побитово назад»)
	pv.veil_enabled = false
	ctl.apply_veil(p_on)
	if mat.get_shader_parameter("hc_enabled") != false:
		_fail("выключение: hc_enabled должен вернуться в false")
	# 3d. Sky3.2.14 (задача 3): выбор пресета НЕ сбрасывает вуаль — apply_preset
	# не пишет hc_* вовсе; состояние вуали при старте применяет _ready() один раз
	pv.veil_enabled = true
	var before_en = mat.get_shader_parameter("hc_enabled")
	var before_amt = mat.get_shader_parameter("DS_hc_alpha_scale")
	ctl.apply_preset(p_on)
	if mat.get_shader_parameter("hc_enabled") != before_en or mat.get_shader_parameter("DS_hc_alpha_scale") != before_amt:
		_fail("задача 3: apply_preset изменил uniform'ы вуали (сброс при выборе пресета)")
	var ctl_src3 := FileAccess.get_file_as_string("res://SkyEnvironment/SkyEnvironmentController.gd")
	var i_ap3 := ctl_src3.find("func apply_preset")
	var i_end3 := ctl_src3.find("func set_shader_param")
	if "apply_veil(" in ctl_src3.substr(i_ap3, i_end3 - i_ap3):
		_fail("задача 3: apply_preset всё ещё вызывает apply_veil")
	var i_ready3 := ctl_src3.find("func _ready")
	if "apply_veil(initial_preset)" not in ctl_src3.substr(i_ready3, i_ap3 - i_ready3):
		_fail("Sky3.2.14: _ready не применяет вуаль стартового пресета один раз")
	ctl.free()
	print("  OK: null → off; 8 uniform'ов + свет от солнца; off назад; apply_preset")

	print("=== 4. Сохранение/загрузка кругом через валидатор ===")
	var rt_path := "user://test_veil_rt.tres"
	var err := ResourceSaver.save(p_on, rt_path)
	if err != OK:
		_fail("ResourceSaver.save: %s" % error_string(err))
	else:
		var txt := FileAccess.get_file_as_string(rt_path)
		if "SkyVeilProfile" not in txt:
			_fail("в .tres нет sub-resource SkyVeilProfile")
		var p2: Resource = load(rt_path)
		if p2 == null or p2.veil == null:
			_fail("загрузка круга: preset/veil == null")
		else:
			var eq := true
			for k in ["veil_enabled", "veil_amount", "veil_color", "veil_light_gain",
					"veil_ambient_gain", "veil_coverage", "veil_tau_per_km", "veil_use_shadowing"]:
				if p2.veil.get(k) != pv.get(k):
					eq = false
					_fail("круг: поле %s = %s, ожидалось %s" % [k, str(p2.veil.get(k)), str(pv.get(k))])
			var res2: Dictionary = ValidatorScript.validate(p2)
			if not res2["errors"].is_empty():
				_fail("круг: ошибки валидатора %s" % str(res2["errors"]))
			if eq:
				print("  OK: .tres круг (save → load → 8 полей равны, 0 ошибок)")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(rt_path))

	print("=== 5. Структура панели и контроллера (по исходникам) ===")
	var panel := FileAccess.get_file_as_string("res://SkyEnvironment/SkyControlPanel.gd")
	var i_light := panel.find("_build_light_tab()")
	var i_veil := panel.find("_build_veil_tab()")
	var i_presets := panel.find("_build_presets_tab()")
	if i_veil < 0 or not (i_light < i_veil and i_veil < i_presets):
		_fail("вкладка «Вуаль» не между «Свет сцены» и «Пресеты»")
	if "Вуаль" not in panel or "_veil_on" not in panel:
		_fail("в панели нет контролов вкладки «Вуаль»")
	if "_tabs.current_tab = 6" not in panel:
		_fail("индекс «Отладки» в _save_current не сдвинут на 6")
	if "p.veil = vp" not in panel:
		_fail("_collect_current не собирает профиль вуали")
	if "_veil_on.set_pressed_no_signal" not in panel:
		_fail("_sync_ui не синхронизирует вкладку «Вуаль»")
	if "_veil_reset" not in panel or "Сброс вуали" not in panel:
		_fail("нет единственной кнопки сброса вуали (задача 3)")
	if "REFS_DIR" not in panel or "_save_ref" not in panel or "_load_ref" not in panel or "_refresh_refs" not in panel:
		_fail("нет именованного списка пресетов-референсов (задача 1)")
	var ctrl_src := FileAccess.get_file_as_string("res://SkyEnvironment/SkyEnvironmentController.gd")
	# Sky3.2.14 (задача 3): apply_preset вуаль НЕ вызывает; старт — из _ready один раз
	var i_ap5 := ctrl_src.find("func apply_preset")
	var i_end5 := ctrl_src.find("func set_shader_param")
	if "apply_veil(" in ctrl_src.substr(i_ap5, i_end5 - i_ap5):
		_fail("задача 3: apply_preset сбрасывает вуаль (вызывает apply_veil)")
	if "apply_veil(initial_preset)" not in ctrl_src:
		_fail("Sky3.2.14: _ready не применяет вуаль стартового пресета")
	# панель пишет вуаль ТОЛЬКО через _set_param (писатель материала один)
	var direct_writes := 0
	for m in RegEx.create_from_string("sky_material\\.set_shader_parameter\\(\"(hc_|DS_hc|cloud_light|veil_ramp)").search_all(panel):
		direct_writes += 1
	if direct_writes > 0:
		_fail("панель напрямую пишет uniform'ы вуали мимо контроллера: %d" % direct_writes)
	print("  OK: вкладка на месте, порядок, индекс 6, collect/sync, писатель один")

	print("=== 7. Sky3.2.10: дальность 90+ км и форма (образец Q7.32) ===")
	# curtain гасит длину пути В ПЛИТЕ: path(D) = толщина/sin(elev), sin = h/sqrt(D^2+h^2).
	# D = 90 км (требование заказчика) -> path ~ 16.4 км: curtain_start обязан быть >=,
	# иначе вуаль умирает раньше 90 км («диск над головой» из бага 3.2.8).
	var inc7 := FileAccess.get_file_as_string("res://SkyEnvironment/SkyVeil.gdshaderinc")
	var rx_f := func(name: String) -> float:
		var m := RegEx.create_from_string("uniform\\s+float\\s+%s\\s*=\\s*([0-9.eE+-]+)" % name).search(inc7)
		return float(m.get_string(1)) if m else -1.0
	var cs: float = rx_f.call("hc_curtain_start")
	var ce: float = rx_f.call("hc_curtain_end")
	var h_mid := 0.5 * (18000.0 + 21600.0)
	var d90 := 90000.0
	var path90 := (21600.0 - 18000.0) * sqrt(d90 * d90 + h_mid * h_mid) / h_mid
	if cs < path90:
		_fail("curtain_start = %.0f < path(90 км) = %.0f — вуаль умрёт раньше 90 км" % [cs, path90])
	if ce < 50000.0 or ce <= cs:
		_fail("curtain_end = %.0f: сход у истинного горизонта (~55 км path) нарушен" % ce)
	# Sky3.2.11 (вариант A): потолка сэмпля НЕТ — точка всегда внутри плиты,
	# иначе характер уйдёт с горизонтальной плиты на «вертикальную стену»
	if "DS_HC_MAX_SAMPLE_DIST" in inc7 or "min(t_mid" in inc7:
		_fail("потолок сэмпла вернулся: сэмпл обязан лежать в плите на любой дальности")
	if not is_equal_approx(rx_f.call("hc_layer_bottom"), 18000.0) or not is_equal_approx(rx_f.call("hc_layer_top"), 21600.0):
		_fail("плита не поднята ×3: ожидалось 18000/21600")
	if RegEx.create_from_string("uniform\\s+bool\\s+hc_wind_enabled\\s*=\\s*false").search(inc7) == null:
		_fail("hc_wind_enabled: дефолт должен быть false (детерминизм/побитово off)")
	if RegEx.create_from_string("if \\(hc_wind_enabled\\)[\\s\\S]{0,120}TIME \\* hc_wind_speed").search(inc7) == null:
		_fail("TIME-адвекция ветра не под гейтом hc_wind_enabled")
	var host7 := FileAccess.get_file_as_string("res://SkyEnvironment/SkyEnvironment.gdshader")
	var i_sky := host7.find("void sky()")
	var i_stars := host7.rfind("star_intensity")
	var i_veilc := host7.find("DS_veil_composite(col")
	if i_sky < 0 or i_stars < i_sky or i_veilc < 0 or i_veilc < i_stars:
		_fail("вуаль НЕ спереди: композит вуали должен идти после солнца/луны/звёзд в sky()")
	if not is_equal_approx(rx_f.call("hc_detail_strength"), 0.45):
		_fail("detail_strength != 0.45 (перистая кромка, образцы 233/234)")
	if not is_equal_approx(rx_f.call("hc_softness"), 0.30):
		_fail("softness != 0.30 (образцы 233/234)")
	if not is_equal_approx(rx_f.call("hc_stretch"), 3.2):
		_fail("stretch != 3.2 (перистые гряды, образцы 233/234)")
	if rx_f.call("hc_break_amount") <= 0.0 or rx_f.call("hc_break_scale") <= 0.0:
		_fail("разрывы покрытия не включены дефолтом (приказ п.2)")
	if rx_f.call("hc_fiber_amp") <= 0.0 or rx_f.call("hc_fiber_scale") <= 0.0:
		_fail("второй масштаб волокон не включён дефолтом (приказ п.4)")
	if RegEx.create_from_string("TIME \\* hc_wind_speed \\* hc_wind_timelapse").search(inc7) == null:
		_fail("дрейф ветра без таймлапса: при 60 км плите реальная скорость невидима")
	var ctrl7 := FileAccess.get_file_as_string("res://SkyEnvironment/SkyEnvironmentController.gd")
	var i_av := ctrl7.find("func apply_veil")
	var i_end := ctrl7.find("func apply_preset")
	var av_body := ctrl7.substr(i_av, i_end - i_av)
	if RegEx.create_from_string("set_shader_parameter\\(\"cloud_light").search(av_body):
		_fail("apply_veil всё ещё ПИШЕТ cloud_light_* (освещение должно быть отложено)")
	print("  OK: дальность 90+ км; без потолка; плита ×3; форма п.1-5 (stretch 1.8, soft 0.40, detail 0.50, разрывы, волокна); ветер с таймлапсом; вуаль спереди светил")

	print("=== 6. Hotfix 3.2.9: null-uniform сценарий заказчика ===")
	# Воспроизведение краша _sync_ui: материал без записанных hc_* (пресет veil=null),
	# ShaderMaterial.get_shader_parameter → null; панель обязана читать через фолбэк.
	var PanelScript: GDScript = load("res://SkyEnvironment/SkyControlPanel.gd")
	var mat2 := ShaderMaterial.new()
	mat2.shader = sh
	var ctl2: Node = CtrlScript.new()
	ctl2.sky_material = mat2
	ctl2.apply_preset(presets[0])	# Sky3.2.14: выбор пресета вуаль НЕ трогает
	ctl2.apply_veil(presets[0])	# стартовый путь _ready: вуаль стартового пресета один раз
	var pnl: CanvasLayer = PanelScript.new()
	pnl.controller = ctl2
	if mat2.get_shader_parameter("hc_scale") != null:
		_fail("сценарий не воспроизведён: hc_scale не null")
	if pnl._veil_get("hc_scale") != 60000.0:
		_fail("_veil_get(hc_scale) = %s, ожидалось 60000.0" % str(pnl._veil_get("hc_scale")))
	if pnl._veil_get("hc_enabled") != true:
		_fail("_veil_get(hc_enabled) должен быть true (пресет несёт включённую вуаль)")
	ctl2.set_shader_param("hc_scale", 77000.0)
	if pnl._veil_get("hc_scale") != 77000.0:
		_fail("_veil_get не вернул записанное значение 77000")
	# collect читает состояние пресета через материал (круг панель->пресет)
	var pc: Resource = pnl._collect_current()
	if pc == null or pc.veil == null:
		_fail("_collect_current не собрал пресет/вуаль")
	else:
		for k in ["veil_enabled", "veil_amount", "veil_color", "veil_light_gain",
				"veil_ambient_gain", "veil_coverage", "veil_tau_per_km", "veil_use_shadowing"]:
			if pc.veil.get(k) != presets[0].veil.get(k):
				_fail("collect: %s = %s, ожидалось из пресета %s" % [k, str(pc.veil.get(k)), str(presets[0].veil.get(k))])
	# фолбэк на НЕзаписанных: ручной пресет без вуали → только гейт off, остальное дефолты
	var ctl3: Node = CtrlScript.new()
	ctl3.sky_material = mat2
	var p_null6: Resource = PresetScript.new()
	ctl3.apply_veil(p_null6)
	var pnl3: CanvasLayer = PanelScript.new()
	pnl3.controller = ctl3
	var pc3: Resource = pnl3._collect_current()
	if pc3 == null or pc3.veil == null:
		_fail("collect-фолбэк не собрал вуаль")
	else:
		var dflt: Resource = ProfileScript.new()
		for k in ["veil_enabled", "veil_amount", "veil_color", "veil_light_gain",
				"veil_ambient_gain", "veil_coverage", "veil_tau_per_km", "veil_use_shadowing"]:
			if pc3.veil.get(k) != dflt.get(k):
				_fail("collect-фолбэк: %s = %s, ожидался дефолт %s" % [k, str(pc3.veil.get(k)), str(dflt.get(k))])
	pnl3.free()
	ctl3.free()
	# anti-drift: VEIL_DEFAULTS побитово = дефолтам SkyVeil.gdshaderinc
	var inc_src := FileAccess.get_file_as_string("res://SkyEnvironment/SkyVeil.gdshaderinc")
	var drift := 0
	for uni in pnl.VEIL_DEFAULTS:
		var want_v: Variant = pnl.VEIL_DEFAULTS[uni]
		var rx: RegEx
		var got: Variant = null
		if want_v is Color:
			rx = RegEx.create_from_string("uniform\\s+vec3\\s+%s\\s*:[^=]*=\\s*vec3\\(([^)]*)\\)" % uni)
			var m := rx.search(inc_src)
			if m:
				var parts := m.get_string(1).split(",")
				got = Color(float(parts[0]), float(parts[1]), float(parts[2]))
		elif want_v is bool:
			rx = RegEx.create_from_string("uniform\\s+bool\\s+%s\\s*=\\s*(true|false)" % uni)
			var m := rx.search(inc_src)
			if m:
				got = m.get_string(1) == "true"
		else:
			rx = RegEx.create_from_string("uniform\\s+float\\s+%s\\s*=\\s*([0-9.eE+-]+)" % uni)
			var m := rx.search(inc_src)
			if m:
				got = float(m.get_string(1))
		if got == null:
			drift += 1
			_fail("VEIL_DEFAULTS: %s не найден в исходнике компонента" % uni)
		elif got != want_v:
			drift += 1
			_fail("VEIL_DEFAULTS дрейф: %s = %s, в шейдере %s" % [uni, str(want_v), str(got)])
	var nkeys: int = pnl.VEIL_DEFAULTS.size()
	pnl.free()
	ctl2.free()
	print("  OK: null-фолбэк, записанное значение, collect без краша, VEIL_DEFAULTS = шейдер (%d ключей)" % nkeys)

	print("=== 8. Sky3.2.14: дыхание неба max во всех пресетах (данные) ===")
	for i in range(1, 11):
		var t8 := FileAccess.get_file_as_string("res://SkyEnvironment/SkyPreset/Preset_%02d.tres" % i)
		if "breathe = 0.9" not in t8:
			_fail("Preset_%02d: дыхание не максимально (нет breathe = 0.9)" % i)
	print("  OK: 10/10 пресетов несут breathe = 0.9 явной строкой")

	print("TEST_VEIL_V2: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
