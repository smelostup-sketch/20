extends SceneTree
## Q.7.34.PreOmega_Sky.4.1.1 (этапы 01–02 плана света) — приёмка нового
## контракта освещения. Запуск:
##   godot --headless --path <проект> --script q_tools/test_light_v1.gd
## Разделы:
##  1) AtmosphereLightingProfile: дефолты класса по плану §4.1; проектный
##     .tres — явные данные (стартовые tint §4.5, mu, ambient);
##  2) AtmosphereLightingState: контейнер (поля, RefCounted, ноль логики);
##  3) AtmosphereLightingComponent: событийный контракт — publish() ровно
##     один сигнал; state = данные узла Sun × профиль; push_error без ссылок;
##     _process/polling ОТСУТСТВУЮТ (план §4.3, v2 §3.3);
##  4) SkyLightController — владелец изменения Sun: mutator'ы Sun вызывают
##     publish событийно; Moon (заглушка) и ambient — НЕ вызывают;
##  5) AtmosphereShaderBindingComponent: пишет только существующие uniform'ы;
##     пустое имя = no-op; гейт bind_veil_palette; end-to-end цепочка
##     «ручка → узел Sun → компонент → сигнал → материал» без ручного publish;
##  6) Сборка сцен: SkyTest.tscn и Основная_сцена.tscn несут
##     SkyEnvironment/{AtmosphereLightingComponent, SkyGradientBinding,
##     CirrusVeilBinding} + ссылку atmosphere у SkyLightController;
##  7) Пресеты: 10 .tres грузятся без поля light, валидатор 0 ошибок;
##     СТАРЫЙ .tres с light: проверено на 4.7 — загрузка ПАДАЕТ громко
##     (мёртвый ext_resource скрипта), ремонт — migrate_remove_light.gd
##     до загрузки; после миграции грузится, поля целы;
##  8) Граница удаления (добро 30.10 п.4): SkyLightProfile.gd удалён,
##     apply_light/поля light в коде нет, вкладка «Свет сцены» СОХРАНЕНА
##     (приказ 31.10 п.3), Moon помечен заглушкой;
##  9) Дымовой прогон SkyTest.tscn: instantiation всей цепочки, старт-публикация
##     state (направление = углы стартового пресета), atmosphere/binding'и
##     назначены, панель — 7 вкладок с «Свет сцены» на индексе 3.
## Узлы тестируются в кадре 1 (_process-паттерн sim_core.gd): в _init/_initialize
## root ещё не в дереве, global_transform недействителен (урок 4.7).

var fails := 0
var frame := 0

var world: Node3D
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env_res: Environment


func _fail(msg: String) -> void:
	fails += 1
	printerr("  FAIL: " + msg)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_run()
		print("TEST_LIGHT_V1: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
		quit(0 if fails == 0 else 1)
		return true
	return false


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	sun = DirectionalLight3D.new()
	world.add_child(sun)
	moon = DirectionalLight3D.new()
	world.add_child(moon)
	env_res = Environment.new()

	_section_1_profile()
	_section_2_state()
	var comp := _section_3_component()
	_section_4_controller_triggers(comp)
	_section_5_binding(comp)
	_section_6_scenes()
	_section_7_presets()
	_section_8_removal_boundary()
	_section_9_scene_smoke()


# ============ 1. Profile ============

func _section_1_profile() -> void:
	print("=== 1. AtmosphereLightingProfile: дефолты §4.1 + данные .tres §4.5 ===")
	var p := AtmosphereLightingProfile.new()
	var want_defaults := {
		"anti_solar_color": Color(0.42, 0.48, 0.68),
		"transition_color": Color(0.78, 0.76, 0.82),
		"solar_color": Color(1.0, 0.83, 0.65),
		"anti_solar_mu": -0.35, "solar_mu": 0.75, "transition_position": 0.5,
		"direct_multiplier": 1.0,
		"ambient_zenith_color": Color(0.12, 0.19, 0.38),
		"ambient_horizon_color": Color(0.38, 0.40, 0.48),
		"ambient_strength": 1.0,
	}
	for k: String in want_defaults:
		if p.get(k) != want_defaults[k]:
			_fail("дефолт %s = %s, ожидался %s" % [k, str(p.get(k)), str(want_defaults[k])])
	var t: Resource = load("res://SkyEnvironment/Profiles/AtmosphereLightingProfile.tres")
	if t == null:
		_fail("профильный .tres не загрузился")
		return
	var want_tres := {
		"anti_solar_color": Color(0.78, 0.86, 1.0),
		"transition_color": Color(1.0, 0.94, 0.86),
		"solar_color": Color(1.0, 0.78, 0.56),
		"anti_solar_mu": -0.35, "solar_mu": 0.75, "transition_position": 0.5,
		"direct_multiplier": 1.0, "ambient_strength": 1.0,
	}
	for k: String in want_tres:
		if t.get(k) != want_tres[k]:
			_fail(".tres %s = %s, ожидалось %s" % [k, str(t.get(k)), str(want_tres[k])])


# ============ 2. State ============

func _section_2_state() -> void:
	print("=== 2. AtmosphereLightingState: контейнер без логики ===")
	var s := AtmosphereLightingState.new()
	if not (s is RefCounted):
		_fail("state не RefCounted")
	if s.sun_direction != Vector3.UP or s.sun_color != Color.WHITE or s.sun_energy != 1.0:
		_fail("дефолты state сбиты")
	var src := FileAccess.get_file_as_string("res://SkyEnvironment/Scripts/AtmosphereLightingState.gd")
	if src.contains("\nfunc ") or src.contains("\nstatic func "):
		_fail("state содержит функции — контейнер не должен ничего считать (план §4.2)")


# ============ 3. Component ============

func _section_3_component() -> AtmosphereLightingComponent:
	print("=== 3. AtmosphereLightingComponent: событийный контракт ===")
	var src := FileAccess.get_file_as_string("res://SkyEnvironment/Scripts/AtmosphereLightingComponent.gd")
	for bad: String in ["func _process", "func _physics_process", "set_process"]:
		if src.contains(bad):
			_fail("компонент содержит %s — polling запрещён (план §4.3)" % bad)

	# 3a. publish() без ссылок: push_error, без сигнала, state null (узел вне
	# дерева — _ready не вызван). Далее в выводе ожидаются два push_error.
	var comp_bad := AtmosphereLightingComponent.new()
	var emits_bad := [0]
	comp_bad.lighting_changed.connect(func(_s: AtmosphereLightingState) -> void:
		emits_bad[0] += 1)
	print("  (ожидаемые push_error: Sun/Profile not assigned)")
	comp_bad.publish()
	comp_bad.sun_light = sun
	comp_bad.publish()
	if emits_bad[0] != 0 or comp_bad.get_current_state() != null:
		_fail("publish без профиля: сигнал/state не должны возникать")
	comp_bad.free()

	# 3b. _ready публикует ровно один раз; state = узел × профиль
	var comp := AtmosphereLightingComponent.new()
	comp.sun_light = sun
	var prof := AtmosphereLightingProfile.new()
	prof.direct_multiplier = 2.0
	comp.profile = prof
	var emits := [0]
	var last := [null]
	comp.lighting_changed.connect(func(s: AtmosphereLightingState) -> void:
		emits[0] += 1
		last[0] = s)
	world.add_child(comp)	# _ready → publish
	if emits[0] != 1:
		_fail("_ready: ожидался ровно 1 publish, получено %d" % emits[0])
	var st: AtmosphereLightingState = last[0]
	if st == null:
		_fail("_ready не опубликовал state")
		return comp
	var expect_dir: Vector3 = sun.global_basis.orthonormalized().z.normalized()
	if st.sun_direction.distance_to(expect_dir) > 1e-6:
		_fail("sun_direction != basis.z узла Sun")
	if st.sun_energy != sun.light_energy * 2.0:
		_fail("sun_energy != light_energy × direct_multiplier")
	if st.anti_solar_color != prof.anti_solar_color or st.solar_mu != prof.solar_mu:
		_fail("палитра/mu state != данные профиля")
	comp.set_meta("emits", emits)
	comp.set_meta("last", last)
	comp.set_meta("prof", prof)
	return comp


# ============ 4. Триггеры владельца Sun ============

func _section_4_controller_triggers(comp: AtmosphereLightingComponent) -> void:
	print("=== 4. SkyLightController: событийная публикация от mutator'ов Sun ===")
	if not comp.has_meta("emits"):
		_fail("секция 3 не оставила счётчики — проверка триггеров невозможна")
		return
	var emits: Array = comp.get_meta("emits")
	var last: Array = comp.get_meta("last")
	var prof: AtmosphereLightingProfile = comp.get_meta("prof")
	var lc := SkyLightController.new()
	lc.sun_light = sun
	lc.moon_light = moon
	lc.environment = env_res
	lc.atmosphere = comp
	world.add_child(lc)
	var n0: int = emits[0]

	for elev: float in [-45.0, 0.5, 42.0, 89.9]:
		for azim: float in [0.0, 123.0, 270.0]:
			lc.set_sun_angles(azim, elev)
			if emits[0] != n0 + 1:
				_fail("set_sun_angles(%f,%f): publish не событийный (%d → %d)" % [azim, elev, n0, emits[0]])
			var st: AtmosphereLightingState = last[0]
			var expect: Vector3 = SkyLightController.direction_from_angles(azim, elev)
			if st.sun_direction.distance_to(expect) > 1e-5:
				_fail("state.sun_direction != direction_from_angles (az=%f el=%f)" % [azim, elev])
			if st.sun_direction.distance_to(sun.global_basis.orthonormalized().z.normalized()) > 1e-6:
				_fail("state.sun_direction != basis.z узла (az=%f el=%f)" % [azim, elev])
			n0 = emits[0]

	lc.set_key_light_color(Color(1.0, 0.5, 0.25))
	if emits[0] != n0 + 1 or (last[0] as AtmosphereLightingState).sun_color != Color(1.0, 0.5, 0.25):
		_fail("set_key_light_color: publish/цвет не прошли")
	n0 = emits[0]
	lc.set_key_light_energy(3.5)
	if emits[0] != n0 + 1 or (last[0] as AtmosphereLightingState).sun_energy != 3.5 * prof.direct_multiplier:
		_fail("set_key_light_energy: publish/энергия (×multiplier) не прошли")
	n0 = emits[0]

	# Moon — временная заглушка: в новый контракт НЕ публикуется; ambient — тоже.
	lc.set_moon_angles(33.0, 55.0)
	lc.set_moon_light_color(Color(0.4, 0.5, 0.8))
	lc.set_moon_light_energy(0.2)
	lc.set_ambient_energy(0.7)
	lc.set_sun_enabled(false)
	lc.set_sun_enabled(true)
	if emits[0] != n0:
		_fail("Moon/ambient/enabled изменили счётчик publish (%d → %d): публикация только от Sun" % [n0, emits[0]])


# ============ 5. Binding ============

func _section_5_binding(comp: AtmosphereLightingComponent) -> void:
	print("=== 5. Binding: имена-данные, только существующие, событийно ===")
	var bsrc := FileAccess.get_file_as_string("res://SkyEnvironment/Scripts/AtmosphereShaderBindingComponent.gd")
	for bad: String in ["func _process", "func _physics_process", "set_process"]:
		if bsrc.contains(bad):
			_fail("binding содержит %s — polling запрещён (v2 §3.3)" % bad)

	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded;
uniform vec3 t_dir;
uniform vec3 t_col;
uniform float t_energy;
uniform vec3 t_pal_anti;
uniform vec3 t_amb_zen;
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var b := AtmosphereShaderBindingComponent.new()
	b.lighting_source = comp
	b.target_material = mat
	b.sun_direction_uniform = &"t_dir"
	b.sun_color_uniform = &"t_col"
	b.sun_energy_uniform = &"t_energy"
	b.ambient_zenith_uniform = &"t_amb_zen"
	b.anti_solar_uniform = &"t_pal_anti"
	b.anti_solar_mu_uniform = &"t_nonexistent"	# такого uniform нет — must skip
	world.add_child(b)	# _ready: кэш + connect + первичный apply

	var st: AtmosphereLightingState = comp.get_current_state()
	if st == null:
		_fail("нет state для binding-проверок")
		return
	if mat.get_shader_parameter("t_dir") == null:
		_fail("t_dir не записан при _ready")
	else:
		var got: Vector3 = mat.get_shader_parameter("t_dir")
		if got.distance_to(st.sun_direction) > 1e-6:
			_fail("t_dir != state.sun_direction")
	if mat.get_shader_parameter("t_energy") != st.sun_energy:
		_fail("t_energy != state.sun_energy")
	if mat.get_shader_parameter("t_pal_anti") != null:
		_fail("палитра написана при bind_veil_palette=false")
	if mat.get_shader_parameter("t_nonexistent") != null:
		_fail("запись в несуществующий uniform")

	# гейт палитры включён → следующая публикация пишет палитру
	b.bind_veil_palette = true
	comp.publish()
	var prof: AtmosphereLightingProfile = comp.get_meta("prof")
	if mat.get_shader_parameter("t_pal_anti") != prof.anti_solar_color:
		_fail("bind_veil_palette=true: t_pal_anti != anti_solar_color профиля")

	# end-to-end: живая ручка → узел Sun → publish → сигнал → материал
	# (БЕЗ ручного comp.publish() — событийность всей цепочки)
	var light_ctrl := SkyLightController.new()
	light_ctrl.sun_light = sun
	light_ctrl.atmosphere = comp
	world.add_child(light_ctrl)
	light_ctrl.set_key_light_energy(1.25)
	if mat.get_shader_parameter("t_energy") != 1.25 * prof.direct_multiplier:
		_fail("end-to-end: t_energy не обновился через цепочку сигнала (%s)" % str(mat.get_shader_parameter("t_energy")))
	light_ctrl.free()
	b.free()


# ============ 6. Сборка сцен ============

func _section_6_scenes() -> void:
	print("=== 6. Сцены: SkyEnvironment/{component, 2 binding} + atmosphere ===")
	for path: String in ["res://SkyEnvironment/SkyTest.tscn", "res://Основная_сцена.tscn"]:
		var src := FileAccess.get_file_as_string(path)
		if src == "":
			_fail("%s не прочитался" % path)
			continue
		for needle: String in [
			'[node name="SkyEnvironment" type="Node"',
			'[node name="AtmosphereLightingComponent" type="Node" parent="SkyEnvironment"',
			'[node name="SkyGradientBinding" type="Node" parent="SkyEnvironment"',
			'[node name="CirrusVeilBinding" type="Node" parent="SkyEnvironment"',
			'SkyEnvironment/Scripts/AtmosphereLightingComponent.gd',
			'SkyEnvironment/Scripts/AtmosphereShaderBindingComponent.gd',
			'SkyEnvironment/Profiles/AtmosphereLightingProfile.tres',
			'atmosphere = NodePath("../SkyEnvironment/AtmosphereLightingComponent")',
		]:
			if not src.contains(needle):
				_fail("%s: нет «%s»" % [path, needle])


# ============ 7. Пресеты ============

func _section_7_presets() -> void:
	print("=== 7. Пресеты без light; старый формат: громкое падение, ремонт — миграция ===")
	var ValidatorScript: GDScript = load("res://SkyEnvironment/SkyPresetValidator.gd")
	for i in range(1, 11):
		var path := "res://SkyEnvironment/SkyPreset/Preset_%02d.tres" % i
		var p: Resource = load(path)
		if p == null:
			_fail("%s не загрузился" % path)
			continue
		if p.get("light") != null:
			_fail("%s: поле light живо" % path)
		var res: Dictionary = ValidatorScript.validate(p)
		if not (res["errors"] as Array).is_empty():
			_fail("%s: ошибки валидатора %s" % [path, str(res["errors"])])
		if FileAccess.get_file_as_string(path).contains("SkyLightProfile"):
			_fail("%s: следы SkyLightProfile в тексте" % path)

	# СТАРЫЙ формат (light + мёртвый ext_resource скрипта). ПРОВЕРЕНО эмпирически
	# на 4.7 (4.1.1): загрузка ПАДАЕТ («referenced non-existent resource») —
	# допущение доки состояния «ResourceLoader игнорирует неизвестные свойства»
	# для случая ОТСУТСТВУЮЩЕГО СКРИПТА не работает. Предписанный ремонт —
	# q_tools/migrate_remove_light.gd до загрузки (README/CHANGELOG поставки).
	# Тест фиксирует: (а) падение громкое, не тихое; (б) после миграции файл
	# грузится, данные пресета целы. В выводе ожидаются ERROR движка — норма.
	var old_path := "user://old_format_preset.tres"
	var f := FileAccess.open(old_path, FileAccess.WRITE)
	f.store_string("""[gd_resource type="Resource" script_class="SkyPreset" format=3]

[ext_resource type="Script" path="res://SkyEnvironment/SkyPreset.gd" id="1_s"]
[ext_resource type="Script" path="res://SkyEnvironment/SkyLightProfile.gd" id="2_l"]

[sub_resource type="Resource" id="light_x"]
script = ExtResource("2_l")
key_color = Color(1, 0.5, 0.32, 1)

[resource]
script = ExtResource("1_s")
preset_name = "старый формат с light"
breathe = 0.9
light = SubResource("light_x")
""")
	f.close()
	print("  (ожидаемые ERROR движка: мёртвый ext_resource — проверяем громкость падения)")
	var old: Resource = load(old_path)
	if old != null:
		_fail("старый .tres с мёртвым скриптом неожиданно загрузился — задокументировать поведение")

	# (б) тот же файл после миграции (light-блок удалён) — грузится, поля целы
	var mig_path := "user://migrated_preset.tres"
	var f2 := FileAccess.open(mig_path, FileAccess.WRITE)
	f2.store_string("""[gd_resource type="Resource" script_class="SkyPreset" format=3]

[ext_resource type="Script" path="res://SkyEnvironment/SkyPreset.gd" id="1_s"]

[resource]
script = ExtResource("1_s")
preset_name = "старый формат с light"
breathe = 0.9
""")
	f2.close()
	var mig: Resource = load(mig_path)
	if mig == null:
		_fail("мигрированный .tres не загрузился")
	elif mig.get("preset_name") != "старый формат с light" or mig.get("breathe") != 0.9:
		_fail("мигрированный .tres: поля пресета повреждены")
	elif mig.get("light") != null:
		_fail("мигрированный .tres: свойство light живо")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mig_path))


# ============ 8. Граница удаления ============

func _section_8_removal_boundary() -> void:
	print("=== 8. Граница удаления: SkyLightProfile/apply_light ушли, панель и Moon-заглушка на месте ===")
	if FileAccess.file_exists("res://SkyEnvironment/SkyLightProfile.gd"):
		_fail("SkyLightProfile.gd не удалён")
	var preset_src := FileAccess.get_file_as_string("res://SkyEnvironment/SkyPreset.gd")
	if preset_src.contains("@export var light"):
		_fail("SkyPreset.gd: поле light живо")
	var lctrl_src := FileAccess.get_file_as_string("res://SkyEnvironment/SkyLightController.gd")
	if lctrl_src.contains("func apply_light"):
		_fail("SkyLightController.gd: apply_light жив")
	if not lctrl_src.contains("func _publish_atmosphere"):
		_fail("SkyLightController.gd: нет триггера _publish_atmosphere")
	if lctrl_src.count("\n\t_publish_atmosphere()") != 3:
		_fail("SkyLightController.gd: ожидалось 3 вызова _publish_atmosphere() (углы/цвет/энергия Sun), найдено %d" % lctrl_src.count("\n\t_publish_atmosphere()"))
	if not lctrl_src.contains("ВРЕМЕННАЯ ЗАГЛУШКА"):
		_fail("SkyLightController.gd: Moon не помечен временной заглушкой (решение 30.10 п.3)")
	var ectrl_src := FileAccess.get_file_as_string("res://SkyEnvironment/SkyEnvironmentController.gd")
	if ectrl_src.contains("\n\t\tlight_controller.apply_light(preset.light)"):
		_fail("SkyEnvironmentController.gd: вызов apply_light жив")
	if ectrl_src.contains("@export_range(0.0, 4.0, 0.05) var sun_energy"):
		_fail("SkyEnvironmentController.gd: export sun_energy жив")
	var panel_src := FileAccess.get_file_as_string("res://SkyEnvironment/SkyControlPanel.gd")
	if panel_src.contains("SkyLightProfile.new()"):
		_fail("SkyControlPanel.gd: сборка light-профиля жива")
	if not panel_src.contains('_tab_box("Свет сцены")'):
		_fail("SkyControlPanel.gd: вкладка «Свет сцены» удалена — приказ 31.10 п.3 требует СОХРАНИТЬ")
	if not panel_src.contains("_key_col") or not panel_src.contains("_ambient_slider"):
		_fail("SkyControlPanel.gd: живые ручки вкладки «Свет сцены» повреждены")


# ============ 9. Дымовой прогон сцены ============

func _section_9_scene_smoke() -> void:
	print("=== 9. SkyTest.tscn: instantiation, старт-публикация, панель (7 вкладок) ===")
	var packed: PackedScene = load("res://SkyEnvironment/SkyTest.tscn")
	if packed == null:
		_fail("SkyTest.tscn не загрузилась")
		return
	var scene: Node = packed.instantiate()
	if scene == null:
		_fail("SkyTest.tscn не инстанцировалась")
		return
	root.add_child(scene)	# _ready всей цепочки: контроллер → свет → компонент → binding'и → панель
	var comp: AtmosphereLightingComponent = scene.get_node_or_null(
		"SkyEnvironment/AtmosphereLightingComponent") as AtmosphereLightingComponent
	if comp == null:
		_fail("в сцене нет SkyEnvironment/AtmosphereLightingComponent")
	else:
		var st: AtmosphereLightingState = comp.get_current_state()
		if st == null:
			_fail("после старта сцены state не опубликован (_ready-цепочка разорвана)")
		else:
			var p09: Resource = load("res://SkyEnvironment/SkyPreset/Preset_09.tres")
			var expect: Vector3 = SkyLightController.direction_from_angles(
				float(p09.get("sun_azimuth")), float(p09.get("sun_elevation")))
			if st.sun_direction.distance_to(expect) > 1e-5:
				_fail("state.sun_direction != углы стартового пресета (%s vs %s)" % [str(st.sun_direction), str(expect)])
			# энергия/multiplier проверяются в секциях 3–4 (единственный источник — узел Sun)
	var lc: SkyLightController = scene.get_node_or_null("SkyLightController") as SkyLightController
	if lc == null or lc.atmosphere == null:
		_fail("SkyLightController.atmosphere не назначен в сцене")
	if scene.get_node_or_null("SkyEnvironment/SkyGradientBinding") == null \
			or scene.get_node_or_null("SkyEnvironment/CirrusVeilBinding") == null:
		_fail("в сцене нет обоих binding-узлов (план §5)")
	var panel: CanvasLayer = scene.get_node_or_null("SkyControlPanel") as CanvasLayer
	if panel == null:
		_fail("панель не найдена")
	else:
		var tabs: TabContainer = panel.get("_tabs")
		if tabs == null:
			_fail("панель: _tabs не построен")
		elif tabs.get_tab_count() != 7 or tabs.get_tab_title(3) != "Свет сцены":
			_fail("панель: ожидалось 7 вкладок и «Свет сцены» = индекс 3 (приказ 31.10 п.3), получено %d/%s"
				% [tabs.get_tab_count(), tabs.get_tab_title(3) if tabs.get_tab_count() > 3 else "—"])
	scene.free()
