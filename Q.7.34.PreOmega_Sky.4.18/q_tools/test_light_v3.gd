extends SceneTree
## Q.7.34.PreOmega_Sky.4.1.3 (этап 04 плана света) — приёмка «Cirrus Veil:
## единая угловая палитра, контракт освещения в модуле, без дублирования».
## Запуск: godot --headless --path <проект> --script q_tools/test_light_v3.gd
## Разделы:
##  1) Контракт хоста: cloud_light_*/cloud_ambient_* УДАЛЕНЫ (v2 §3.2 — никакого
##     дублирования данных освещения); sk_sun_dir — единственное направление;
##     объём контракта 87 (4.1.7: −sk_q1..q4 −sk_sharp +sky_color_weights
##     +sky_transition_width);
##  2) Модуль: ЕДИНАЯ угловая палитра hc_angular_palette (структура плана §4.5:
##     mu = dot(normalize, normalize), mu_range ≥ 0.001, middle 0.05..0.95, две
##     ветви плавного перехода); старая рампа veil_ramp_* слита (отсутствует);
##     ldir = sk_sun_dir сохранён (H1); shadow_t умножается РОВНО один раз
##     (v2 §6.2); самозатенение — отключаемый блок (v2 §6.3); палитра/свет НЕ
##     входят в плотность/оптику (v2 §5.2);
##  3) Дефолты модуля — байт-данные: hc_ambient_zenith = col_light3 старого
##     контракта (вуаль не ослеплена до первой публикации), палитра = план §4.1;
##  4) Binding (runtime): имена → материал, байт-в-байт из состояния; приоритет
##     живой палитры над fallback профиля (4.1.6: трио «Окружение» питает И
##     ambient, И палитру зон); направление binding НЕ пишет (второй писатель
##     геометрии запрещён, решение 30.10 п.5);
##  5) Цепочка сцены: SkyTest.tscn + apply_preset → hc_ambient_zenith ==
##     preset.col_light3 байт-в-байт, палитра зон == preset.col_light3/2/1
##     (4.1.6: единая строка «Окружение», вуаль следует пресету), mu/float ==
##     .tres профиля, hc_sun_color/energy == узел Sun × direct_multiplier;
##  6) Сцены: CirrusVeilBinding — 10 имён заполнены (обе сцены),
##     sun_direction_uniform отсутствует, SkyGradientBinding инертен;
##  7) Профиль .tres: tint = стартовые значения плана §4.5, mu/position/
##     multiplier — данные.
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
		print("TEST_LIGHT_V3: " + ("PASS" if fails == 0 else "FAIL (%d)" % fails))
		quit(0 if fails == 0 else 1)
		return true
	return false


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	sun = DirectionalLight3D.new()
	world.add_child(sun)

	_section_1_host_contract()
	_section_2_module_sources()
	_section_3_module_defaults()
	_section_4_binding_runtime()
	_section_5_scene_chain()
	_section_6_scene_sources()
	_section_7_profile_data()


func _active(src: String) -> String:
	var out := ""
	for ln in src.split("\n"):
		var i := ln.find("//")
		out += (ln if i < 0 else ln.substr(0, i)) + "\n"
	return out


# ============ 1. Контракт хоста ============

func _section_1_host_contract() -> void:
	print("=== 1. Хост: cloud_* удалены, sk_sun_dir единственное направление, объём 87 ===")
	var sh: Shader = load("res://SkyEnvironment/SkyEnvironment.gdshader")
	var names := []
	for u in sh.get_shader_uniform_list():
		names.append(String(u["name"]))
	for gone: String in ["cloud_light_color", "cloud_light_strength",
			"cloud_ambient_sky_color", "cloud_ambient_energy", "cloud_light_direction"]:
		if gone in names:
			_fail("хост: контрактный uniform %s не удалён (этап 04)" % gone)
	if not ("sk_sun_dir" in names):
		_fail("хост: sk_sun_dir пропал (направление света вуали, H1)")
	# 4.1.7: старые ручки градиента удалены, новые — в контракте
	for gone: String in ["sk_q1", "sk_q2", "sk_q3", "sk_q4", "sk_sharp"]:
		if gone in names:
			_fail("хост: uniform %s не удалён (4.1.7 — доли у владельца-компонента)" % gone)
	for need: String in ["sky_color_weights", "sky_transition_width"]:
		if not (need in names):
			_fail("хост: нет uniform %s (4.1.7)" % need)
	if names.size() != 87:
		_fail("объём контракта = %d, ожидалось 87 (4.1.7: −5 старые ручки рампы, +2 доли/мягкость)" % names.size())
	var host_active := _active(FileAccess.get_file_as_string(
		"res://SkyEnvironment/SkyEnvironment.gdshader"))
	if "cloud_light" in host_active or "cloud_ambient" in host_active:
		_fail("хост: активный код всё ещё ссылается на cloud_*")
	print("  OK: cloud_* нет (хост+активный код), sk_sun_dir на месте, uniform'ов %d" % names.size())


# ============ 2. Модуль: единая угловая палитра ============

func _section_2_module_sources() -> void:
	print("=== 2. Модуль: hc_angular_palette (план §4.5), рампа слита, shadow_t один раз ===")
	var inc := FileAccess.get_file_as_string("res://SkyEnvironment/SkyVeil.gdshaderinc")
	var a := _active(inc)
	# структура функции — план §4.5
	for frag: String in ["vec3 hc_angular_palette(vec3 view_dir, vec3 sun_dir)",
			"dot(normalize(view_dir), normalize(sun_dir))",
			"hc_palette_solar_mu - hc_palette_anti_solar_mu",
			"hc_angular_palette(dir, ldir)"]:
		if not (frag in a):
			_fail("модуль: нет фрагмента палитры «%s»" % frag)
	if a.count("DS_sstep(0.0, middle, t)") != 1 or a.count("DS_sstep(middle, 1.0, t)") != 1:
		_fail("модуль: две ветви плавного перехода палитры не на месте")
	# старая рампа слита в палитру
	for gone: String in ["veil_light_ramp_color", "veil_ramp_", "cloud_light_", "cloud_ambient_"]:
		if gone in a:
			_fail("модуль: активный код всё ещё содержит %s (рампа должна быть слита)" % gone)
	# H1: направление — sk_sun_dir, единый источник
	if not ("vec3 ldir = sk_sun_dir;" in a):
		_fail("модуль: ldir = sk_sun_dir пропал (H1, единый источник направления)")
	# v2 §6.2: shadow_t умножается ровно один раз (двойное затенение запрещено)
	if a.count("* shadow_t") != 1:
		_fail("модуль: shadow_t входит в формулу %d раз (должно быть ровно 1)" % a.count("* shadow_t"))
	# v2 §6.3: самозатенение — отдельный отключаемый блок
	if a.count("? DS_veil_shadow_transmittance") != 1 or not ("hc_use_shadowing" in a):
		_fail("модуль: самозатенение не отключаемым блоком (hc_use_shadowing)")
	# формулы плана §4.5 / v2 §4: albedo × (direct + ambient)
	for frag: String in ["hc_sun_color", "palette_tint", "* hc_light_gain",
			"hc_ambient_zenith * (hc_ambient_strength * hc_ambient_gain)",
			"hc_color * (direct + ambient)"]:
		if not (frag in a):
			_fail("модуль: нет фрагмента формулы освещения «%s»" % frag)
	# v2 §5.2: палитра/свет НЕ влияют на плотность и оптическую толщину
	var i_d := a.find("float d    = DS_veil_density(p, c);")
	var i_l := a.find("vec3 ldir = sk_sun_dir;")
	if i_d < 0 or i_l < 0 or i_l <= i_d:
		_fail("модуль: структура композита изменилась — не локализовать блок плотности")
	else:
		var density_block := a.substr(i_d, i_l - i_d)
		for frag: String in ["hc_palette", "hc_sun_", "hc_ambient_"]:
			if frag in density_block:
				_fail("модуль: %s входит в блок плотности/оптики (v2 §5.2 запрещает)" % frag)
	print("  OK: палитра по mu (план §4.5), рампа/cloud_* слиты, ldir=sk_sun_dir, shadow_t ×1,")
	print("      самозатенение отключаемо, albedo×(direct+ambient), плотность не тронута светом")


# ============ 3. Дефолты модуля — байт-данные ============

func _section_3_module_defaults() -> void:
	print("=== 3. Дефолты модуля: ambient = col_light3 (не ослеплена), палитра = план §4.1 ===")
	var inc := FileAccess.get_file_as_string("res://SkyEnvironment/SkyVeil.gdshaderinc")
	var want := {
		"hc_sun_color": "vec3(1.0)",
		"hc_sun_energy": "1.0",
		# байт-значение старого контрактного дефолта cloud_ambient_sky_color (col_light3)
		"hc_ambient_zenith": "vec3(0.2078, 0.2863, 0.3725)",
		"hc_ambient_strength": "1.0",
		"hc_palette_anti_solar": "vec3(0.42, 0.48, 0.68)",
		"hc_palette_transition": "vec3(0.78, 0.76, 0.82)",
		"hc_palette_solar": "vec3(1.0, 0.83, 0.65)",
		"hc_palette_anti_solar_mu": "-0.35",
		"hc_palette_solar_mu": "0.75",
		"hc_palette_transition_position": "0.5",
	}
	for k in want:
		var suffix := String(want[k]) + ";"
		var found := false
		for ln: String in inc.split("\n"):
			# строка объявления uniform'а детерминирована: имя + дефолт в конце
			if ln.begins_with("uniform") and (k in ln) and ln.rstrip(" \t").ends_with(suffix):
				found = true
				break
		if not found:
			_fail("дефолт %s != %s (байт-континуити/план §4.1)" % [k, str(want[k])])
	print("  OK: 10 дефолтов контракта освещения — данные плана и байт-континуити")


# ============ 4. Binding (runtime) ============

func _section_4_binding_runtime() -> void:
	print("=== 4. Binding: имена → материал байт-в-байт, приоритет среды, без направления ===")
	var prof := AtmosphereLightingProfile.new()
	prof.anti_solar_color = Color(0.111, 0.222, 0.333)
	prof.transition_color = Color(0.444, 0.555, 0.666)
	prof.solar_color = Color(0.777, 0.888, 0.999)
	prof.anti_solar_mu = -0.5
	prof.solar_mu = 0.6
	prof.transition_position = 0.42
	prof.direct_multiplier = 2.0
	prof.ambient_strength = 1.5
	prof.ambient_zenith_color = Color(0.1, 0.2, 0.3)
	prof.ambient_horizon_color = Color(0.4, 0.5, 0.6)
	sun.light_color = Color(0.9, 0.8, 0.7)
	sun.light_energy = 1.25
	var comp := AtmosphereLightingComponent.new()
	comp.sun_light = sun
	comp.profile = prof
	world.add_child(comp)	# _ready → publish (fallback-среда профиля)
	var emits := [0]
	comp.lighting_changed.connect(func(_s: AtmosphereLightingState) -> void: emits[0] += 1)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://SkyEnvironment/SkyEnvironment.gdshader")
	var b := AtmosphereShaderBindingComponent.new()
	b.lighting_source = comp
	b.target_material = mat
	b.bind_veil_palette = true
	b.sun_color_uniform = &"hc_sun_color"
	b.sun_energy_uniform = &"hc_sun_energy"
	b.ambient_zenith_uniform = &"hc_ambient_zenith"
	b.ambient_strength_uniform = &"hc_ambient_strength"
	b.anti_solar_uniform = &"hc_palette_anti_solar"
	b.transition_uniform = &"hc_palette_transition"
	b.solar_uniform = &"hc_palette_solar"
	b.anti_solar_mu_uniform = &"hc_palette_anti_solar_mu"
	b.solar_mu_uniform = &"hc_palette_solar_mu"
	b.transition_position_uniform = &"hc_palette_transition_position"
	world.add_child(b)	# _ready: кэш uniform'ов + первичное применение состояния

	# первичное состояние: fallback-среда профиля, tint/му — данные профиля
	if Color(mat.get_shader_parameter("hc_palette_anti_solar")) != prof.anti_solar_color:
		_fail("hc_palette_anti_solar != данные профиля (байт-в-байт)")
	if Color(mat.get_shader_parameter("hc_palette_transition")) != prof.transition_color:
		_fail("hc_palette_transition != данные профиля")
	if Color(mat.get_shader_parameter("hc_palette_solar")) != prof.solar_color:
		_fail("hc_palette_solar != данные профиля")
	if Color(mat.get_shader_parameter("hc_ambient_zenith")) != prof.ambient_zenith_color:
		_fail("hc_ambient_zenith != fallback профиля до поставки среды градиента")
	if not is_equal_approx(mat.get_shader_parameter("hc_palette_anti_solar_mu"), prof.anti_solar_mu):
		_fail("hc_palette_anti_solar_mu != данные профиля")
	if not is_equal_approx(mat.get_shader_parameter("hc_palette_solar_mu"), prof.solar_mu):
		_fail("hc_palette_solar_mu != данные профиля")
	if not is_equal_approx(mat.get_shader_parameter("hc_palette_transition_position"), prof.transition_position):
		_fail("hc_palette_transition_position != данные профиля")
	if Color(mat.get_shader_parameter("hc_sun_color")) != sun.light_color:
		_fail("hc_sun_color != light_color узла Sun")
	if not is_equal_approx(mat.get_shader_parameter("hc_sun_energy"), 2.5):
		_fail("hc_sun_energy != energy × direct_multiplier (1.25 × 2.0)")
	if not is_equal_approx(mat.get_shader_parameter("hc_ambient_strength"), prof.ambient_strength):
		_fail("hc_ambient_strength != данные профиля")
	# направление binding НЕ пишет: второй писатель sk_sun_dir запрещён (30.10 п.5)
	if mat.get_shader_parameter("sk_sun_dir") != null:
		_fail("binding записал sk_sun_dir — второй писатель геометрии запрещён")
	# горизонта среды в контракте вуали нет (воздушная перспектива — этап 05)
	if mat.get_shader_parameter("hc_ambient_horizon") != null:
		_fail("hc_ambient_horizon не должен существовать до этапа 05")

	# поставка живой палитры (этап 03 + 4.1.6) → приоритет над fallback профиля,
	# событийно; ОДНО трио питает и ambient, и палитру зон (без второй копии)
	var zen := Color(0.043137, 0.086275, 0.180392)	# байт-данные col_light3 Preset_01
	var mid := Color(0.137255, 0.215686, 0.372549)	# байт-данные col_light2 Preset_01
	var hor := Color(0.956863, 0.976471, 1.0)		# байт-данные col_light1 Preset_01
	comp.set_environment_palette(zen, mid, hor)
	if Color(mat.get_shader_parameter("hc_ambient_zenith")) != zen:
		_fail("hc_ambient_zenith != живая палитра L3 (приоритет над профилем)")
	if Color(mat.get_shader_parameter("hc_palette_anti_solar")) != zen \
			or Color(mat.get_shader_parameter("hc_palette_transition")) != mid \
			or Color(mat.get_shader_parameter("hc_palette_solar")) != hor:
		_fail("палитра зон != живое трио L3/L2/L1 (4.1.6: единые данные, байт-в-байт)")
	if emits[0] != 1:
		_fail("set_environment_palette: публикаций %d, ожидалась 1 (событийность)" % emits[0])
	b.free()
	comp.free()
	print("  OK: 10 uniform'ов записаны байт-в-байт из состояния; живая палитра > fallback;")
	print("      одно трио → ambient + зоны; sk_sun_dir binding не трогает; 1 событие")


# ============ 5. Цепочка сцены ============

func _section_5_scene_chain() -> void:
	print("=== 5. SkyTest.tscn: apply_preset → вуаль из состояния (байт-в-байт) ===")
	var scene: PackedScene = load("res://SkyEnvironment/SkyTest.tscn")
	var inst := scene.instantiate()
	world.add_child(inst)
	var ctl: Node = inst.get_node("SkyEnvironmentController")
	var p09: Resource = load("res://SkyEnvironment/SkyPreset/Preset_09.tres")
	ctl.apply_preset(p09)
	var mat: ShaderMaterial = ctl.sky_material
	var prof: Resource = load("res://SkyEnvironment/Profiles/AtmosphereLightingProfile.tres")
	# окружающая среда — окружение пресета (этап 03 → binding), байт-в-байт
	if Color(mat.get_shader_parameter("hc_ambient_zenith")) != p09.col_light3:
		_fail("hc_ambient_zenith != Preset_09.col_light3 (зенит среды, байт-в-байт)")
	# палитра вуали (4.1.6) — ЖИВАЯ строка «Окружение» пресета, не fallback профиля
	if Color(mat.get_shader_parameter("hc_palette_anti_solar")) != p09.col_light3:
		_fail("hc_palette_anti_solar != Preset_09.col_light3 (4.1.6: вуаль следует пресету)")
	if Color(mat.get_shader_parameter("hc_palette_transition")) != p09.col_light2:
		_fail("hc_palette_transition != Preset_09.col_light2")
	if Color(mat.get_shader_parameter("hc_palette_solar")) != p09.col_light1:
		_fail("hc_palette_solar != Preset_09.col_light1")
	# углы/форма/сила — по-прежнему данные .tres профиля
	if not is_equal_approx(mat.get_shader_parameter("hc_palette_anti_solar_mu"), prof.anti_solar_mu) \
			or not is_equal_approx(mat.get_shader_parameter("hc_palette_solar_mu"), prof.solar_mu):
		_fail("mu зон != данные .tres профиля")
	# прямой свет — узел Sun (единственный автор), энергия с direct_multiplier
	var sun_node: DirectionalLight3D = inst.get_node("SunLight")
	if Color(mat.get_shader_parameter("hc_sun_color")) != sun_node.light_color:
		_fail("hc_sun_color != light_color SunLight сцены")
	if not is_equal_approx(mat.get_shader_parameter("hc_sun_energy"),
			sun_node.light_energy * prof.direct_multiplier):
		_fail("hc_sun_energy != energy × direct_multiplier")
	# геометрия солнца — один писатель (контроллер): sk_sun_dir совпадает с state
	var comp: Node = inst.get_node("SkyEnvironment/AtmosphereLightingComponent")
	var state: AtmosphereLightingState = comp.get_current_state()
	var sk_dir: Vector3 = mat.get_shader_parameter("sk_sun_dir")
	if sk_dir.distance_to(state.sun_direction) > 1e-5:
		_fail("sk_sun_dir материала != state.sun_direction (единый источник направления)")
	inst.free()
	print("  OK: пресет→state→binding→материал: среда=L3, палитра=L3/L2/L1 пресета (4.1.6),")
	print("      mu/float=.tres профиля, солнце=узел Sun")


# ============ 6. Сцены: имена binding'ов ============

func _section_6_scene_sources() -> void:
	print("=== 6. Сцены: CirrusVeilBinding заполнен, направления нет, градиент инертен ===")
	var want := ["sun_color_uniform = &\"hc_sun_color\"",
		"sun_energy_uniform = &\"hc_sun_energy\"",
		"ambient_zenith_uniform = &\"hc_ambient_zenith\"",
		"ambient_strength_uniform = &\"hc_ambient_strength\"",
		"anti_solar_uniform = &\"hc_palette_anti_solar\"",
		"transition_uniform = &\"hc_palette_transition\"",
		"solar_uniform = &\"hc_palette_solar\"",
		"anti_solar_mu_uniform = &\"hc_palette_anti_solar_mu\"",
		"solar_mu_uniform = &\"hc_palette_solar_mu\"",
		"transition_position_uniform = &\"hc_palette_transition_position\""]
	for path: String in ["res://SkyEnvironment/SkyTest.tscn", "res://Основная_сцена.tscn"]:
		var s := FileAccess.get_file_as_string(path)
		for line: String in want:
			if s.count(line) != 1:
				_fail("%s: «%s» встречается %d раз (ожидалось 1)" % [path, line, s.count(line)])
		if "sun_direction_uniform" in s:
			_fail("%s: sun_direction_uniform заполнен — второй писатель направления запрещён" % path)
		# SkyGradientBinding остаётся инертным (палитру градиента пишет контроллер)
		var i_g := s.find("[node name=\"SkyGradientBinding\"")
		var i_next := s.find("[node ", i_g + 10)
		var block := s.substr(i_g, (i_next if i_next > 0 else s.length()) - i_g)
		if "_uniform = &\"" in block:
			_fail("%s: SkyGradientBinding получил имена — градиент пишет контроллер" % path)
	print("  OK: 10 имён в CirrusVeilBinding обеих сцен; направление/градиент не дублируются")


# ============ 7. Профиль .tres — данные плана ============

func _section_7_profile_data() -> void:
	print("=== 7. Профиль .tres: tint §4.5, mu/position/multiplier — данные ===")
	var t := FileAccess.get_file_as_string(
		"res://SkyEnvironment/Profiles/AtmosphereLightingProfile.tres")
	var want := {
		"anti_solar_color = Color(0.78, 0.86, 1, 1)": "tint anti-solar §4.5",
		"transition_color = Color(1, 0.94, 0.86, 1)": "tint transition §4.5",
		"solar_color = Color(1, 0.78, 0.56, 1)": "tint solar §4.5",
		"anti_solar_mu = -0.35": "mu anti-solar",
		"solar_mu = 0.75": "mu solar",
		"transition_position = 0.5": "transition position",
		"direct_multiplier = 1.0": "direct multiplier",
	}
	for k in want:
		if not (k in t):
			_fail(".tres: нет «%s» (%s)" % [k, want[k]])
	print("  OK: .tres профиля — стартовые tint плана §4.5 + угловые данные")
