extends SceneTree
## Q.7.34.PreOmega_Sky.4.1.2 (этап 03 плана света) — приёмка «Sky Gradient + Sun:
## согласованные направление/цвет из одного источника». Запуск:
##   godot --headless --path <проект> --script q_tools/test_light_v2.gd
## Разделы:
##  1) Компонент: set_environment_palette/clear (4.1.6) — событийные; ОДНО
##     трио «Окружение» питает ambient (зенит = L3, горизонт = L1) И палитру
##     зон вуали байт-в-байт; fallback = данные профиля (план §7.2, v2 §5.2);
##  2) Цепочка контроллера: apply_preset → apply_palette поставляет строку
##     «Окружение» пресета (col_light3/2/1 → трио + зенит/горизонт); направление ОДНО:
##     sk_sun_dir материала == state.sun_direction == basis.z узла Sun (≤1e-5);
##     sun_color state == light_color узла; диск солнца = арт-данные пресета
##     (sun_disk_color побайтово, standing-критерий палитр palletes.html);
##  3) apply_palette безопасна без atmosphere (null);
##  4) Binding инертен: пустые имена uniform'ов → материал не меняется
##     (вуаль/градиент не ослеплены до этапа 04);
##  5) Сцены: у SkyEnvironmentController ссылка atmosphere (обе сцены);
##  6) Anti-drift исходников: событийность (нет _process), поставка из данных
##     пресета (нет цветовых литералов в компоненте/контроллере).
## Узлы — в кадре 1 (_process-паттерн sim_core.gd): в _init root ещё не в дереве.

var fails := 0
var frame := 0

var world: Node3D
var sun: DirectionalLight3D


func _fail(msg: String) -> void:
	fails += 1
	printerr("  FAIL: " + msg)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_run()
		print("TEST_LIGHT_V2: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
		quit(0 if fails == 0 else 1)
		return true
	return false


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	sun = DirectionalLight3D.new()
	world.add_child(sun)

	_section_1_component_env()
	_section_2_controller_chain()
	_section_4_binding_inert()
	_section_5_scenes()
	_section_6_sources()


func _make_profile() -> AtmosphereLightingProfile:
	var prof := AtmosphereLightingProfile.new()
	# fallback-цвета профиля — заведомо отличимые от данных пресета
	prof.ambient_zenith_color = Color(0.1, 0.2, 0.3)
	prof.ambient_horizon_color = Color(0.4, 0.5, 0.6)
	return prof


func _make_component(prof: AtmosphereLightingProfile) -> AtmosphereLightingComponent:
	var comp := AtmosphereLightingComponent.new()
	comp.sun_light = sun
	comp.profile = prof
	world.add_child(comp)	# _ready → publish (fallback-среда)
	return comp


# ============ 1. Компонент: градиентная среда ============

func _section_1_component_env() -> void:
	print("=== 1. set_environment_palette/clear: событийно, байт-в-байт, fallback ===")
	var prof := _make_profile()
	var comp := _make_component(prof)
	var emits := [0]
	var last: Array = [null]
	comp.lighting_changed.connect(func(s: AtmosphereLightingState) -> void:
		emits[0] += 1
		last[0] = s)

	var st0: AtmosphereLightingState = comp.get_current_state()
	if st0 == null or st0.ambient_zenith_color != prof.ambient_zenith_color \
			or st0.ambient_horizon_color != prof.ambient_horizon_color \
			or st0.anti_solar_color != prof.anti_solar_color \
			or st0.transition_color != prof.transition_color \
			or st0.solar_color != prof.solar_color:
		_fail("без живых данных палитра/ambient != fallback профиля")

	comp.set_environment_palette(Color(0.11, 0.22, 0.33), Color(0.7, 0.71, 0.72), Color(0.44, 0.55, 0.66))
	if emits[0] != 1:
		_fail("set_environment_palette не событийна (publish %d)" % emits[0])
	var st1: AtmosphereLightingState = last[0]
	if st1 == null or st1.anti_solar_color != Color(0.11, 0.22, 0.33) \
			or st1.transition_color != Color(0.7, 0.71, 0.72) \
			or st1.solar_color != Color(0.44, 0.55, 0.66):
		_fail("палитра зон != поставленное трио (байт-в-байт)")
	if st1 == null or st1.ambient_zenith_color != Color(0.11, 0.22, 0.33) \
			or st1.ambient_horizon_color != Color(0.44, 0.55, 0.66):
		_fail("ambient != то же трио (зенит = L3, горизонт = L1) — единые данные (4.1.6)")

	comp.clear_environment_palette()
	if emits[0] != 2:
		_fail("clear_environment_palette не событийна")
	var st2: AtmosphereLightingState = last[0]
	if st2 == null or st2.ambient_zenith_color != prof.ambient_zenith_color \
			or st2.anti_solar_color != prof.anti_solar_color \
			or st2.solar_color != prof.solar_color:
		_fail("clear не вернул fallback профиля (палитра + ambient)")
	comp.free()


# ============ 2. Цепочка контроллера ============

func _section_2_controller_chain() -> void:
	print("=== 2. apply_preset: среда из пресета, направление/цвет из одного источника ===")
	var prof := _make_profile()
	var comp := _make_component(prof)
	var lc := SkyLightController.new()
	lc.sun_light = sun
	lc.atmosphere = comp
	world.add_child(lc)

	var sh: Shader = load("res://SkyEnvironment/SkyEnvironment.gdshader")
	if sh == null:
		_fail("шейдер не загрузился")
		return
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var p09: Resource = load("res://SkyEnvironment/SkyPreset/Preset_09.tres")
	if p09 == null:
		_fail("Preset_09 не загрузился")
		return
	var ctl := SkyEnvironmentController.new()	# ВНЕ дерева: _ready не зовём, apply вручную
	ctl.sky_material = mat
	ctl.light_controller = lc
	ctl.atmosphere = comp
	ctl.apply_preset(p09)

	# среда — данные пресета (palletes.html «Окружение»), байт-в-байт
	var st: AtmosphereLightingState = comp.get_current_state()
	if st == null:
		_fail("state не опубликован после apply_preset")
		return
	if st.ambient_zenith_color != p09.get("col_light3"):
		_fail("zenith != col_light3 пресета (%s vs %s)" % [str(st.ambient_zenith_color), str(p09.get("col_light3"))])
	if st.ambient_horizon_color != p09.get("col_light1"):
		_fail("horizon != col_light1 пресета")
	if st.ambient_strength != prof.ambient_strength:
		_fail("ambient_strength != данные профиля")
	# 4.1.6: палитра зон вуали — ТО ЖЕ трио «Окружение» (единые данные, без копии)
	if st.anti_solar_color != p09.get("col_light3") \
			or st.transition_color != p09.get("col_light2") \
			or st.solar_color != p09.get("col_light1"):
		_fail("палитра зон вуали != col_light3/2/1 пресета (4.1.6: единая строка «Окружение»)")

	# направление — ОДИН источник: материал == state == узел Sun
	var expect_dir: Vector3 = SkyLightController.direction_from_angles(
		float(p09.get("sun_azimuth")), float(p09.get("sun_elevation")))
	var mat_dir: Vector3 = mat.get_shader_parameter("sk_sun_dir")
	var basis_dir: Vector3 = sun.global_basis.orthonormalized().z.normalized()
	if mat_dir.distance_to(expect_dir) > 1e-5:
		_fail("sk_sun_dir материала != direction_from_angles пресета")
	if st.sun_direction.distance_to(mat_dir) > 1e-5:
		_fail("state.sun_direction != sk_sun_dir материала")
	if basis_dir.distance_to(mat_dir) > 1e-5:
		_fail("basis.z узла Sun != sk_sun_dir материала")

	# цвет/энергия света — узел Sun (единственный источник)
	if st.sun_color != sun.light_color:
		_fail("state.sun_color != light_color узла")
	if st.sun_energy != sun.light_energy * prof.direct_multiplier:
		_fail("state.sun_energy != energy узла × direct_multiplier")

	# диск солнца — АРТ-ДАННЫЕ пресета (standing: палитры palletes.html байт-в-байт);
	# зафиксированное решение этапа 03: диск не перекрашивается light_color.
	if mat.get_shader_parameter("sun_disk_color") != p09.get("sun_disc_color"):
		_fail("sun_disk_color != sun_disc_color пресета (арт-данные)")

	# 3) apply_palette без atmosphere — безопасна (null-guard)
	var ctl2 := SkyEnvironmentController.new()
	ctl2.sky_material = mat
	ctl2.light_controller = lc
	ctl2.atmosphere = null
	ctl2.apply_palette(p09)	# не должно падать
	if mat.get_shader_parameter("sk_c1") != p09.get("col_sky1"):
		_fail("apply_palette без atmosphere сломала запись градиента")
	ctl.free()
	ctl2.free()
	comp.free()
	lc.free()


# ============ 4. Binding инертен при пустых именах ============

func _section_4_binding_inert() -> void:
	print("=== 4. Binding с пустыми именами не пишет материал (вуаль не ослеплена) ===")
	var prof := _make_profile()
	var comp := _make_component(prof)
	var sh: Shader = load("res://SkyEnvironment/SkyEnvironment.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var b := AtmosphereShaderBindingComponent.new()
	b.lighting_source = comp
	b.target_material = mat
	b.bind_veil_palette = true	# имена uniform'ов пустые (дефолт) — писать нечего
	world.add_child(b)
	comp.set_environment_palette(Color(0.9, 0.1, 0.1), Color(0.5, 0.5, 0.5), Color(0.1, 0.9, 0.1))
	# 4.1.3: контракт освещения вуали — uniform'ы модуля (этап 04)
	for uni: String in ["hc_sun_color", "hc_sun_energy",
			"hc_ambient_zenith", "hc_ambient_strength",
			"hc_palette_anti_solar", "hc_palette_transition", "hc_palette_solar",
			"hc_palette_anti_solar_mu", "hc_palette_solar_mu",
			"hc_palette_transition_position"]:
		if mat.get_shader_parameter(uni) != null:
			_fail("binding записал %s при пустом имени" % uni)
	b.free()
	comp.free()


# ============ 5. Сцены ============

func _section_5_scenes() -> void:
	print("=== 5. Сцены: atmosphere у SkyEnvironmentController ===")
	for path: String in ["res://SkyEnvironment/SkyTest.tscn", "res://Основная_сцена.tscn"]:
		var src := FileAccess.get_file_as_string(path)
		if src == "":
			_fail("%s не прочитался" % path)
			continue
		if not src.contains('atmosphere = NodePath("../SkyEnvironment/AtmosphereLightingComponent")'):
			_fail("%s: у SkyEnvironmentController нет ссылки atmosphere" % path)
		# 4.1.7: в node_paths контроллера добавлен gradient_weights (владелец долей)
		if not src.contains('node_paths=PackedStringArray("light_controller", "atmosphere", "gradient_weights")'):
			_fail("%s: atmosphere/gradient_weights не объявлены в node_paths контроллера" % path)


# ============ 6. Anti-drift исходников ============

func _section_6_sources() -> void:
	print("=== 6. Исходники: событийность, данные вместо хардкода ===")
	var comp_src := FileAccess.get_file_as_string(
		"res://SkyEnvironment/Scripts/AtmosphereLightingComponent.gd")
	for fn: String in ["func set_environment_palette", "func clear_environment_palette",
			"_has_environment_palette"]:
		if not comp_src.contains(fn):
			_fail("компонент: нет %s" % fn)
	if comp_src.contains("func _process"):
		_fail("компонент: появился _process (polling запрещён)")
	if comp_src.contains("Color("):
		_fail("компонент: цветовые литералы — среда должна быть данными (план §7.2)")
	var ctl_src := FileAccess.get_file_as_string(
		"res://SkyEnvironment/SkyEnvironmentController.gd")
	if not ctl_src.contains("@export var atmosphere: AtmosphereLightingComponent"):
		_fail("контроллер: нет export atmosphere")
	if not ctl_src.contains("atmosphere.set_environment_palette(preset.col_light3, preset.col_light2, preset.col_light1)"):
		_fail("контроллер: apply_palette не поставляет трио «Окружение» пресета (L3/L2/L1, 4.1.6)")
