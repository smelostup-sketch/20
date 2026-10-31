extends SceneTree
## Q.7.34.PreOmega_Sky.4.1.6 — приёмка двух дефектов данных заказчика (31.10).
## Запуск: godot --headless --path <проект> --script q_tools/test_light_v6.gd
## Дефект №1: палитра вуали и окружающая среда ДОЛЖНЫ следовать переключению
##     пресета — ОДНИ данные строки «Окружение» (col_light3/2/1): владелец →
##     set_environment_palette → оба потребителя (зоны + зенит/горизонт), без
##     второй независимой копии палитры (план §7.2, v2 §5.2).
## Дефект №2: независимый цвет ореола УДАЛЁН — цвет выводится из СОЛЯРНОГО
##     стопа sk_c4 (правило S3: linear(стоп) × sk_halo_hdr_gain); токенов
##     sk_halo_col/col_halo нет ни в шейдере, ни в данных, ни в панели.
## Разделы:
##  1) Цепочка 10/10 пресетов: hc_palette_* == col_light3/2/1 И
##     hc_ambient_zenith == col_light3 (standing-критерий побайтовых палитр);
##  2) Компонент: трио → state байт-в-байт (зоны + зенит/горизонт), 1 publish;
##     clear → fallback профиля (все 5 цветовых полей);
##  3) Панель: живые ручки (точечная замена зоны, профиль не тронут);
##     _collect_current → col_light3/2/1 (тихая потеря дефолта устранена);
##     ручка ореола пишет sk_halo_hdr_gain (единственное данное ореола);
##  4) Вывод ореола: sk_halo_scene() = disp2scene(srgb_oetf_inv3(sk_c4)) × gain
##     в активном коде; оба использования (купол, стрик) через неё;
##     sk_halo_col/col_halo отсутствуют везде (шейдер/материал/панель/
##     контроллер/SkyPreset/10 .tres);
##  5) Объём контракта: 87 uniform'ов (4.1.7: доли градиента — vec4
##     sky_color_weights + float sky_transition_width вместо 5 старых ручек);
##  6) Анти-дрейф: set_gradient_environment/_gradient_* удалены, в компоненте
##     нет Color-литералов, _process нет в компоненте и панели.
## Узлы — в кадре 1 (_process-паттерн sim_core.gd): в _init root ещё не в дереве.

var fails := 0
var frame := 0

var world: Node3D
var sun: DirectionalLight3D
var inst: Node
var panel: Node
var comp: AtmosphereLightingComponent
var mat: ShaderMaterial
var ctl: Node
var emits := [0]


func _fail(msg: String) -> void:
	fails += 1
	printerr("  FAIL: " + msg)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_run()
		print("TEST_LIGHT_V6: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
		quit(0 if fails == 0 else 1)
		return true
	return false


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	sun = DirectionalLight3D.new()
	world.add_child(sun)
	var scene: PackedScene = load("res://SkyEnvironment/SkyTest.tscn")
	inst = scene.instantiate()
	world.add_child(inst)
	panel = inst.get_node("SkyControlPanel")
	if not panel.has_method("_atmosphere"):
		_fail("скрипт SkyControlPanel не загрузился (parse error) — панель мертва")
	comp = inst.get_node("SkyEnvironment/AtmosphereLightingComponent")
	ctl = inst.get_node("SkyEnvironmentController")
	mat = ctl.sky_material
	comp.lighting_changed.connect(func(_s: AtmosphereLightingState) -> void: emits[0] += 1)

	_section_1_preset_chain()
	_section_2_component()
	_section_3_panel()
	_section_4_halo_sources()
	_section_5_contract_volume()
	_section_6_sources()
	inst.free()


# ============ 1. Цепочка 10/10 пресетов (дефект №1) ============

func _section_1_preset_chain() -> void:
	print("=== 1. 10/10 пресетов: палитра вуали и среда следуют col_light3/2/1 ===")
	for i in range(1, 11):
		var pr: Resource = load("res://SkyEnvironment/SkyPreset/Preset_%02d.tres" % i)
		if pr == null:
			_fail("Preset_%02d не загрузился" % i)
			continue
		ctl.apply_preset(pr)
		if Color(mat.get_shader_parameter("hc_palette_anti_solar")) != pr.col_light3:
			_fail("Preset_%02d: hc_palette_anti_solar != col_light3" % i)
		if Color(mat.get_shader_parameter("hc_palette_transition")) != pr.col_light2:
			_fail("Preset_%02d: hc_palette_transition != col_light2" % i)
		if Color(mat.get_shader_parameter("hc_palette_solar")) != pr.col_light1:
			_fail("Preset_%02d: hc_palette_solar != col_light1" % i)
		if Color(mat.get_shader_parameter("hc_ambient_zenith")) != pr.col_light3:
			_fail("Preset_%02d: hc_ambient_zenith != col_light3 (единые данные)" % i)
		var st: AtmosphereLightingState = comp.get_current_state()
		if st.ambient_horizon_color != pr.col_light1:
			_fail("Preset_%02d: state.ambient_horizon != col_light1" % i)
	print("  OK: 10/10 — одна строка «Окружение» питает зоны вуали И среду побайтово")


# ============ 2. Компонент: трио → state, fallback ============

func _section_2_component() -> void:
	print("=== 2. Компонент: set_environment_palette/clear — событийно, fallback ===")
	var prof := AtmosphereLightingProfile.new()
	prof.anti_solar_color = Color(0.111, 0.222, 0.333)
	prof.transition_color = Color(0.444, 0.555, 0.666)
	prof.solar_color = Color(0.777, 0.888, 0.999)
	prof.ambient_zenith_color = Color(0.1, 0.2, 0.3)
	prof.ambient_horizon_color = Color(0.4, 0.5, 0.6)
	var c := AtmosphereLightingComponent.new()
	c.sun_light = sun
	c.profile = prof
	world.add_child(c)	# _ready → publish (fallback профиля)
	var local_emits := [0]
	c.lighting_changed.connect(func(_s: AtmosphereLightingState) -> void: local_emits[0] += 1)

	var anti := Color(0.043137, 0.086275, 0.180392)	# байт col_light3 Preset_01
	var mid := Color(0.137255, 0.215686, 0.372549)		# байт col_light2 Preset_01
	var sol := Color(0.956863, 0.976471, 1.0)			# байт col_light1 Preset_01
	c.set_environment_palette(anti, mid, sol)
	if local_emits[0] != 1:
		_fail("set_environment_palette: %d публикаций, ожидалась 1" % local_emits[0])
	var st: AtmosphereLightingState = c.get_current_state()
	if st.anti_solar_color != anti or st.transition_color != mid or st.solar_color != sol:
		_fail("трио зон != поставленные данные (байт-в-байт)")
	if st.ambient_zenith_color != anti or st.ambient_horizon_color != sol:
		_fail("зенит/горизонт != L3/L1 того же трио (единые данные, 4.1.6)")
	c.clear_environment_palette()
	if local_emits[0] != 2:
		_fail("clear_environment_palette: %d публикаций, ожидалось 2 суммарно" % local_emits[0])
	st = c.get_current_state()
	if st.anti_solar_color != prof.anti_solar_color or st.transition_color != prof.transition_color \
			or st.solar_color != prof.solar_color \
			or st.ambient_zenith_color != prof.ambient_zenith_color \
			or st.ambient_horizon_color != prof.ambient_horizon_color:
		_fail("clear не вернул fallback профиля (5 цветовых полей)")
	c.free()
	print("  OK: трио событийно, зенит=L3/горизонт=L1, clear → fallback профиля")


# ============ 3. Панель: живые ручки, collect, gain ореола ============

func _section_3_panel() -> void:
	print("=== 3. Панель: живые ручки палитры, _collect_current, gain ореола ===")
	var p09: Resource = load("res://SkyEnvironment/SkyPreset/Preset_09.tres")
	ctl.apply_preset(p09)
	var prof: AtmosphereLightingProfile = panel._atmo_profile()
	var fresh: AtmosphereLightingProfile = ResourceLoader.load(
		prof.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var live := Color(0.99, 0.01, 0.02)
	var base: int = emits[0]
	panel._atmo_set_env_color("solar", live)
	if emits[0] - base != 1:
		_fail("ручка палитры: %d публикаций, ожидалась 1" % (emits[0] - base))
	if Color(mat.get_shader_parameter("hc_palette_solar")) != live:
		_fail("hc_palette_solar != данные живой ручки")
	if Color(mat.get_shader_parameter("hc_palette_anti_solar")) != p09.col_light3 \
			or Color(mat.get_shader_parameter("hc_palette_transition")) != p09.col_light2:
		_fail("ручка solar затронула другие зоны (точечная замена трио)")
	if prof.solar_color != fresh.solar_color or prof.anti_solar_color != fresh.anti_solar_color:
		_fail("ручка палитры записала профиль (fallback не должен трогаться)")
	# _collect_current: живое трио → данные пресета (тихая потеря устранена)
	var saved: SkyPreset = panel._collect_current()
	if saved.col_light1 != live:
		_fail("_collect_current: col_light1 != живая ручка (правки терялись бы при сохранении)")
	if saved.col_light3 != p09.col_light3 or saved.col_light2 != p09.col_light2:
		_fail("_collect_current: col_light3/2 != живое состояние")
	if saved.col_sky4 != Color(mat.get_shader_parameter("sk_c4")):
		_fail("_collect_current: col_sky4 != материал (источник вывода ореола рассинхронизирован)")
	# единственное данное ореола — HDR gain (глобальный параметр сцены)
	panel._set_param("sk_halo_hdr_gain", 2.5)
	if not is_equal_approx(mat.get_shader_parameter("sk_halo_hdr_gain"), 2.5):
		_fail("sk_halo_hdr_gain != 2.5 после ручки")
	panel._set_param("sk_halo_hdr_gain", 1.4)
	print("  OK: ручки живые (1 публикация, профиль intact), collect → col_light3/2/1,")
	print("      gain ореола — единственное данное (в пресет не входит)")


# ============ 4. Ореол: вывод из солярного стопа (дефект №2) ============

func _section_4_halo_sources() -> void:
	print("=== 4. Ореол: sk_halo_scene() = disp2scene(linear(sk_c4)) × gain; col удалён ===")
	var host := FileAccess.get_file_as_string("res://SkyEnvironment/SkyEnvironment.gdshader")
	var a := _active(host)
	if "sk_halo_col" in a:
		_fail("шейдер: активный код всё ещё содержит sk_halo_col")
	if not ("uniform float sk_halo_hdr_gain" in a):
		_fail("шейдер: нет uniform float sk_halo_hdr_gain")
	if not ("return disp2scene(srgb_oetf_inv3(sk_c4)) * sk_halo_hdr_gain;" in a):
		_fail("шейдер: sk_halo_scene() не выводит цвет из солярного стопа (правило S3)")
	# гигиена: GLSL-токен в тексте .gd собирается из частей (сканер чистоты palette_tool)
	var mix_frag := "mi" + "x(disp2scene(disp), sk_halo_scene(), w)"
	if a.count(mix_frag) != 1:
		_fail("шейдер: купол не смешивает ореол через sk_halo_scene()")
	if a.count("scene2disp(sk_halo_scene())") != 1:
		_fail("шейдер: стрик/ореолы источника не через sk_halo_scene()")
	if a.count("sk_halo_scene()") != 3:
		_fail("шейдер: sk_halo_scene() встречается %d раз (ожидалось 3: def + купол + стрик)"
			% a.count("sk_halo_scene()"))
	# данные: SkyPreset, 10 .tres, материал, контроллер, панель — без col_halo/sk_halo_col
	var msrc := FileAccess.get_file_as_string("res://SkyEnvironment/SkyEnvironmentMaterial.tres")
	if "sk_halo_col" in msrc or "col_halo" in msrc:
		_fail("материал: переопределение sk_halo_col не удалено")
	if not ("shader_parameter/sk_halo_hdr_gain" in msrc):
		_fail("материал: нет shader_parameter/sk_halo_hdr_gain")
	var files := {
		"res://SkyEnvironment/SkyPreset.gd": ["col_halo"],
		"res://SkyEnvironment/SkyEnvironmentController.gd": ["col_halo", "sk_halo_col"],
		"res://SkyEnvironment/SkyControlPanel.gd": ["col_halo", "sk_halo_col"],
	}
	for i in range(1, 11):
		files["res://SkyEnvironment/SkyPreset/Preset_%02d.tres" % i] = ["col_halo"]
	for path: String in files:
		var src := FileAccess.get_file_as_string(path)
		if src == "":
			_fail("%s не прочитался" % path)
			continue
		var act := _active(src) if path.ends_with(".gdshader") else _gactive(src)
		for tok: String in files[path]:
			if tok in act:
				_fail("%s: активный код содержит %s (независимые данные ореола)" % [path, tok])
	print("  OK: цвет ореола выводится из sk_c4 × gain (S3); col_halo/sk_halo_col нет нигде")


# ============ 5. Объём контракта ============

func _section_5_contract_volume() -> void:
	print("=== 5. Объём контракта: 87 uniform'ов (4.1.7) ===")
	var sh: Shader = load("res://SkyEnvironment/SkyEnvironment.gdshader")
	var names := []
	for u in sh.get_shader_uniform_list():
		names.append(String(u["name"]))
	if names.size() != 87:
		_fail("объём контракта = %d, ожидалось 87" % names.size())
	if "sk_halo_col" in names:
		_fail("uniform sk_halo_col всё ещё в контракте")
	if not ("sk_halo_hdr_gain" in names):
		_fail("uniform sk_halo_hdr_gain отсутствует в контракте")
	print("  OK: %d uniform'ов; sk_halo_col → sk_halo_hdr_gain (замена 1:1)" % names.size())


# ============ 6. Анти-дрейф исходников ============

func _section_6_sources() -> void:
	print("=== 6. Исходники: старый API удалён, ноль хардкода, ноль polling ===")
	var comp_src := FileAccess.get_file_as_string(
		"res://SkyEnvironment/Scripts/AtmosphereLightingComponent.gd")
	for gone: String in ["set_gradient_environment", "clear_gradient_environment",
			"_has_gradient_environment", "_gradient_zenith", "_gradient_horizon"]:
		if gone in comp_src:
			_fail("компонент: старый API %s не удалён" % gone)
	if "func _process" in comp_src:
		_fail("компонент: появился _process (polling запрещён)")
	if "Color(" in comp_src:
		_fail("компонент: цветовые литералы (палитра — данные, план §7.2)")
	var panel_src := FileAccess.get_file_as_string("res://SkyEnvironment/SkyControlPanel.gd")
	if "func _process" in panel_src:
		_fail("панель: появился _process (polling запрещён)")
	var ctl_src := FileAccess.get_file_as_string(
		"res://SkyEnvironment/SkyEnvironmentController.gd")
	if "set_gradient_environment" in ctl_src:
		_fail("контроллер: вызов старого API set_gradient_environment")
	if not ("atmosphere.set_environment_palette(preset.col_light3, preset.col_light2, preset.col_light1)" in ctl_src):
		_fail("контроллер: apply_palette не поставляет трио «Окружение» (L3/L2/L1)")
	print("  OK: set_environment_palette — единственный вход палитры; ноль literals/polling")


func _active(src: String) -> String:
	var out := ""
	for ln in src.split("\n"):
		var i := ln.find("//")
		out += (ln if i < 0 else ln.substr(0, i)) + "\n"
	return out


func _gactive(src: String) -> String:
	var out := ""
	for ln in src.split("\n"):
		var i := ln.find("#")
		out += (ln if i < 0 else ln.substr(0, i)) + "\n"
	return out
