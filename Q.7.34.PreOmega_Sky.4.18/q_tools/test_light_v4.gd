extends SceneTree
## Q.7.34.PreOmega_Sky.4.1.4 (приказ 31.10 п.3) — приёмка интеграции ручек
## нового света В КОНЕЦ вкладки «Свет сцены» (все 7 вкладок сохранены intact).
## Запуск: godot --headless --path <проект> --script q_tools/test_light_v4.gd
## Разделы:
##  1) Сцена: панель → controller.atmosphere → профиль (.tres, сбрасываемый);
##  2) Float-ручки: поле профиля → publish() → материал (событийно, 1 публикация
##     на изменение; hc_sun_energy = energy × direct_multiplier);
##  3) Ручки палитры (4.1.6): ЖИВОЕ трио владельца → hc_palette_* И
##     hc_ambient_zenith байт-в-байт, точечная замена зоны, профиль не тронут;
##  4) Переключение пресета (дефект заказчика №1): палитра вуали и среда
##     СЛЕДУЮТ пресету (col_light3/2/1); живая ручка > данные пресета;
##     повторное применение возвращает данные пресета;
##  5) Сброс: все 10 полей профиля → данные .tres с диска (байт-в-байт),
##     материал назад; живая палитра fallback'ом НЕ подменяется (4.1.6);
##  6) Анти-дрейф исходников: ручки в конце «Свет сцены», без Color-литералов и
##     _set_param в секции (свет пишет только binding), 7 вкладок intact,
##     «Отладка» индекс 6, ноль polling;
##  7) fix.4.1.7: _sync_ui на материале БЕЗ sky_transition_width (NULL) —
##     краш «Nonexistent 'float' constructor» устранён, фолбэк = дефолт шейдера.
## Узлы — в кадре 1 (_process-паттерн sim_core.gd): в _init root ещё не в дереве.

var fails := 0
var frame := 0

var world: Node3D
var inst: Node
var panel: Node
var comp: AtmosphereLightingComponent
var mat: ShaderMaterial
var sun_node: DirectionalLight3D
var emits := [0]


func _fail(msg: String) -> void:
	fails += 1
	printerr("  FAIL: " + msg)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_run()
		print("TEST_LIGHT_V4: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
		quit(0 if fails == 0 else 1)
		return true
	return false


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var scene: PackedScene = load("res://SkyEnvironment/SkyTest.tscn")
	inst = scene.instantiate()
	world.add_child(inst)
	panel = inst.get_node("SkyControlPanel")
	if not panel.has_method("_atmosphere"):
		_fail("скрипт SkyControlPanel не загрузился (parse error) — панель мертва")
	comp = inst.get_node("SkyEnvironment/AtmosphereLightingComponent")
	mat = inst.get_node("SkyEnvironmentController").sky_material
	sun_node = inst.get_node("SunLight")
	comp.lighting_changed.connect(func(_s: AtmosphereLightingState) -> void: emits[0] += 1)

	_section_1_wiring()
	_section_2_float_handles()
	_section_3_color_handles()
	_section_4_preset_switch()
	_section_5_reset()
	_section_6_sources()
	_section_7_sync_ui_nullsafe()
	inst.free()


# ============ 1. Проводка ============

func _section_1_wiring() -> void:
	print("=== 1. Панель → atmosphere → профиль (.tres) ===")
	if panel == null:
		_fail("SkyControlPanel не найден в SkyTest.tscn")
	if panel._atmosphere() == null:
		_fail("panel._atmosphere() == null (controller.atmosphere не разрешён)")
	var p: AtmosphereLightingProfile = panel._atmo_profile()
	if p == null:
		_fail("panel._atmo_profile() == null")
	elif p.resource_path.is_empty():
		_fail("профиль без resource_path — сброс к .tres невозможен")
	for f: String in panel.ATMO_FIELDS:
		if p != null and not (f in p):
			_fail("ATMO_FIELDS: поле %s отсутствует в профиле" % f)
	if panel.ATMO_FIELDS.size() != 10:
		_fail("ATMO_FIELDS = %d полей, ожидалось 10" % panel.ATMO_FIELDS.size())
	print("  OK: проводка есть, профиль .tres, ATMO_FIELDS = 10 полей контракта")


# ============ 2. Float-ручки ============

func _section_2_float_handles() -> void:
	print("=== 2. Float-ручки: профиль → publish → материал (событийно) ===")
	var p: AtmosphereLightingProfile = panel._atmo_profile()
	var base: int = emits[0]
	panel._atmo_set_float("direct_multiplier", 2.0)
	if not is_equal_approx(p.direct_multiplier, 2.0):
		_fail("direct_multiplier не записан в профиль")
	if emits[0] - base != 1:
		_fail("publish: %d событий на одно изменение (ожидалось 1)" % (emits[0] - base))
	var want_e: float = sun_node.light_energy * 2.0
	if not is_equal_approx(mat.get_shader_parameter("hc_sun_energy"), want_e):
		_fail("hc_sun_energy != energy × direct_multiplier")
	base = emits[0]
	panel._atmo_set_float("anti_solar_mu", -0.5)
	panel._atmo_set_float("solar_mu", 0.6)
	panel._atmo_set_float("transition_position", 0.42)
	panel._atmo_set_float("ambient_strength", 1.5)
	if emits[0] - base != 4:
		_fail("4 изменения: %d событий (ожидалось 4, polling/пакетирование)" % (emits[0] - base))
	if not is_equal_approx(mat.get_shader_parameter("hc_palette_anti_solar_mu"), -0.5):
		_fail("hc_palette_anti_solar_mu != -0.5")
	if not is_equal_approx(mat.get_shader_parameter("hc_palette_solar_mu"), 0.6):
		_fail("hc_palette_solar_mu != 0.6")
	if not is_equal_approx(mat.get_shader_parameter("hc_palette_transition_position"), 0.42):
		_fail("hc_palette_transition_position != 0.42")
	if not is_equal_approx(mat.get_shader_parameter("hc_ambient_strength"), 1.5):
		_fail("hc_ambient_strength != 1.5")
	print("  OK: 5 изменений → 5 публикаций; материал обновлён из состояния")


# ============ 3. Ручки палитры (4.1.6: живое трио владельца) ============

func _section_3_color_handles() -> void:
	print("=== 3. Ручки палитры: живое трио байт-в-байт, профиль не тронут ===")
	var p: AtmosphereLightingProfile = panel._atmo_profile()
	var fresh: AtmosphereLightingProfile = ResourceLoader.load(
		p.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var p09: Resource = load("res://SkyEnvironment/SkyPreset/Preset_09.tres")
	var anti := Color(0.1, 0.2, 0.3)
	var base: int = emits[0]
	panel._atmo_set_env_color("anti_solar", anti)
	if emits[0] - base != 1:
		_fail("ручка палитры: %d публикаций, ожидалась 1 (событийность)" % (emits[0] - base))
	if Color(mat.get_shader_parameter("hc_palette_anti_solar")) != anti:
		_fail("hc_palette_anti_solar != данные ручки")
	# замена точечная: остальные зоны сохраняют данные стартового пресета
	if Color(mat.get_shader_parameter("hc_palette_transition")) != p09.col_light2 \
			or Color(mat.get_shader_parameter("hc_palette_solar")) != p09.col_light1:
		_fail("ручка затронула другие зоны (замена трио должна быть точечной)")
	# зенит среды — ТЕ ЖЕ данные (единый источник, план §7.2)
	if Color(mat.get_shader_parameter("hc_ambient_zenith")) != anti:
		_fail("hc_ambient_zenith != то же L3 (единые данные среды и зон)")
	panel._atmo_set_env_color("transition", Color(0.4, 0.5, 0.6))
	panel._atmo_set_env_color("solar", Color(0.7, 0.8, 0.9))
	if Color(mat.get_shader_parameter("hc_palette_transition")) != Color(0.4, 0.5, 0.6) \
			or Color(mat.get_shader_parameter("hc_palette_solar")) != Color(0.7, 0.8, 0.9):
		_fail("transition/solar != данные ручек")
	# горизонт среды в контракте вуали нет (этап 05) — проверяем состояние
	var st: AtmosphereLightingState = comp.get_current_state()
	if st.ambient_horizon_color != Color(0.7, 0.8, 0.9):
		_fail("state.ambient_horizon != solar-данные ручки (зенит/горизонт = L3/L1)")
	# fallback-профиль НЕ тронут (ручка пишет живое состояние владельца)
	if p.anti_solar_color != fresh.anti_solar_color or p.transition_color != fresh.transition_color \
			or p.solar_color != fresh.solar_color:
		_fail("ручка палитры записала профиль (должна писать живые данные владельца)")
	print("  OK: живое трио → материал побайтово (зоны + зенит), точечно, профиль intact")


# ============ 4. Переключение пресета (дефект заказчика №1 устранён) ============

func _section_4_preset_switch() -> void:
	print("=== 4. Смена пресета: палитра вуали и среда следуют пресету ===")
	var ctl: Node = inst.get_node("SkyEnvironmentController")
	var p01: Resource = load("res://SkyEnvironment/SkyPreset/Preset_01.tres")
	var p09: Resource = load("res://SkyEnvironment/SkyPreset/Preset_09.tres")
	ctl.apply_preset(p01)
	if Color(mat.get_shader_parameter("hc_palette_anti_solar")) != p01.col_light3 \
			or Color(mat.get_shader_parameter("hc_palette_transition")) != p01.col_light2 \
			or Color(mat.get_shader_parameter("hc_palette_solar")) != p01.col_light1:
		_fail("Preset_01: палитра вуали не следует col_light3/2/1 (данные заморожены)")
	if Color(mat.get_shader_parameter("hc_ambient_zenith")) != p01.col_light3:
		_fail("Preset_01: зенит среды != col_light3")
	ctl.apply_preset(p09)
	if Color(mat.get_shader_parameter("hc_palette_anti_solar")) != p09.col_light3 \
			or Color(mat.get_shader_parameter("hc_palette_solar")) != p09.col_light1:
		_fail("Preset_09: палитра не сменилась при переключении пресета (дефект №1)")
	# живая ручка приоритетнее данных пресета; повторное применение возвращает их
	panel._atmo_set_env_color("transition", Color(0.99, 0.01, 0.02))
	if Color(mat.get_shader_parameter("hc_palette_transition")) != Color(0.99, 0.01, 0.02):
		_fail("живая ручка не перебивает палитру пресета")
	ctl.apply_preset(p09)
	if Color(mat.get_shader_parameter("hc_palette_transition")) != p09.col_light2:
		_fail("apply_preset не вернул палитру к данным пресета")
	# сила среды — всегда из профиля (живых данных у неё нет)
	if not is_equal_approx(mat.get_shader_parameter("hc_ambient_strength"), 1.5):
		_fail("hc_ambient_strength != данные профиля")
	# к §5: живая зона, заведомо отличная от fallback .tres
	panel._atmo_set_env_color("anti_solar", Color(0.123, 0.456, 0.789))
	print("  OK: переключение visibly меняет палитру/среду; ручка > пресет;")
	print("      повторный apply_preset возвращает данные пресета; сила — из профиля")


# ============ 5. Сброс к .tres ============

func _section_5_reset() -> void:
	print("=== 5. Сброс: 10 полей профиля → .tres, живая палитра не тронута ===")
	var p: AtmosphereLightingProfile = panel._atmo_profile()
	# остаточные изменения уже внесены §2–§4; добавим контрольное
	panel._atmo_set_float("direct_multiplier", 3.5)
	var fresh: AtmosphereLightingProfile = ResourceLoader.load(
		p.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var base: int = emits[0]
	panel._atmo_reset()
	if emits[0] - base != 1:
		_fail("сброс: %d публикаций (ожидалась 1)" % (emits[0] - base))
	for f: String in panel.ATMO_FIELDS:
		if p.get(f) != fresh.get(f):
			_fail("после сброса %s != данные .tres" % f)
	# 4.1.6: сброс касается ТОЛЬКО профиля — живая палитра владельца не подменяется
	var st: AtmosphereLightingState = comp.get_current_state()
	if Color(mat.get_shader_parameter("hc_palette_anti_solar")) != st.anti_solar_color \
			or Color(mat.get_shader_parameter("hc_palette_anti_solar")) != Color(0.123, 0.456, 0.789):
		_fail("после сброса материал != живое трио (сброс подменил палитру fallback'ом)")
	if Color(mat.get_shader_parameter("hc_palette_anti_solar")) == fresh.anti_solar_color:
		_fail("сброс подменил живую палитру fallback'ом профиля")
	if not is_equal_approx(mat.get_shader_parameter("hc_sun_energy"),
			sun_node.light_energy * fresh.direct_multiplier):
		_fail("hc_sun_energy != energy × multiplier из .tres после сброса")
	print("  OK: сброс = .tres профиля (10/10 полей), живая палитра сохранена,")
	print("      материал синхронен, 1 публикация")


# ============ 6. Анти-дрейф исходников ============

func _section_6_sources() -> void:
	print("=== 6. Исходники: ручки в конце вкладки, 7 вкладок intact, ноль polling ===")
	var src := FileAccess.get_file_as_string("res://SkyEnvironment/SkyControlPanel.gd")
	# ручки нового света — В КОНЦЕ «Свет сцены» (приказ 31.10 п.3), не новая вкладка
	var i_light := src.find("func _build_light_tab")
	var i_veil := src.find("func _build_veil_tab")
	var i_call := src.find("_build_atmosphere_handles(box)")
	if i_light < 0 or i_veil < 0 or not (i_light < i_call and i_call < i_veil):
		_fail("секция нового света не в конце _build_light_tab")
	if src.find("_tab_box(\"Новый свет\")") >= 0 or src.find("_tab_box(\"Атмосфера\")") >= 0:
		_fail("создана новая вкладка — приказ: все 7 вкладок intact, ручки в конце «Свет сцены»")
	# 7 вкладок сохранены
	for tab: String in ["Градиент", "Источник", "Купол", "Свет сцены", "Погода", "Пресеты", "Отладка"]:
		if not ("_tab_box(\"%s\")" % tab) in src:
			_fail("вкладка «%s» не intact" % tab)
	if "_tabs.current_tab = 6" not in src:
		_fail("индекс «Отладки» сдвинут (должен остаться 6)")
	# секция ручек: без цветовых литералов и без прямой записи материала
	var i_b := src.find("func _build_atmosphere_handles")
	var i_e := src.find("func _sync_atmo")
	var seg := src.substr(i_b, i_e - i_b)
	if "Color(" in seg:
		_fail("секция ручек содержит Color-литералы (данные — профиль/.tres)")
	if "_set_param(" in seg:
		_fail("секция ручек пишет материал напрямую (свет пишет только binding)")
	# 4.1.6: палитра — живые данные владельца; мёртвые fallback-пикеры удалены;
	# _collect_current собирает живое трио в данные пресета
	if "func _atmo_set_env_color" not in src:
		_fail("нет живой ручки палитры _atmo_set_env_color (4.1.6)")
	if "func _atmo_set_color" in src:
		_fail("_atmo_set_color не удалён — цвета палитры больше не данные профиля (4.1.6)")
	if "_atmo_amb_zen" in src or "_atmo_amb_hor" in src:
		_fail("мёртвые fallback-пикеры ambient не удалены (4.1.6: цвета среды = палитра)")
	if "p.col_light3 = st.anti_solar_color" not in src:
		_fail("_collect_current не собирает живую палитру в col_light3/2/1 (4.1.6)")
	# событийность: публикация, не polling
	if "func _process" in src:
		_fail("панель: появился _process (polling запрещён)")
	if ".publish()" not in src:
		_fail("панель не вызывает publish() (событийный контракт)")
	# старая документация рампы обновлена (этап 04)
	if "3-цветной рампы" in src:
		_fail("тултип вуали всё ещё описывает старую рампу (этап 04: угловая палитра)")
	print("  OK: ручки в конце «Свет сцены», 7 вкладок intact, «Отладка»=6,")
	print("      без литералов/прямой записи материала, publish() событийный")


# ============ 7. fix.4.1.7: открытие панели на старом материале (NULL-параметр) ============

func _section_7_sync_ui_nullsafe() -> void:
	print("=== 7. fix.4.1.7: _sync_ui при sky_transition_width = NULL (старый материал) ===")
	# РЕПРО краша заказчика (SkyControlPanel.gd:1261, _toggle_panel → _sync_ui):
	# SkyEnvironmentMaterial.tres не содержит uniform 4.1.7 — материал его никогда
	# не получал, get_shader_parameter() = NULL (дефолты шейдера не хранятся),
	# float(null) = «Nonexistent 'float' constructor».
	if mat.get_shader_parameter("sky_transition_width") != null:
		print("  примечание: параметр уже записан материалу — проверка фолбэка всё равно ниже")
	if not panel.has_method("_src_get"):
		_fail("нет _src_get (NULL-безопасный фолбэк fix.4.1.7)")
		return
	var sl: HSlider = panel._src_sliders["sky_transition_width"]
	sl.set_value_no_signal(0.1)	# сторожил БЕЗ записи в материал (иначе параметр перестанет быть NULL)
	panel._sync_ui()	# до fix: краш на первом же проходе цикла _src_sliders
	if absf(sl.value - 0.025) > 0.0001:
		_fail("_sync_ui: слайдер sky_transition_width = %.4f, цель 0.025 (дефолт шейдера; краш/нет фолбэка?)" % sl.value)
	elif absf(float(panel._src_get("sky_transition_width")) - 0.025) > 0.0001:
		_fail("_src_get фолбэк != дефолт шейдера")
	else:
		print("  OK: _sync_ui прошёл без краша; NULL → дефолт шейдера 0.025; сторожил 0.1 заменён")
