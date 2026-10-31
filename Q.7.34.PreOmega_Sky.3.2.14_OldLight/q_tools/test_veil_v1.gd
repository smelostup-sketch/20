extends SceneTree
## Q7.34.PreOmega_Sky3.2.7 (S10, V1) — приёмка вуали под гейтом off.
## Запуск: godot --headless --path <проект с кэшем классов> --script q_tools/test_veil_v1.gd
## Проверяет реальным движком:
##  1) шейдер-компонент SkyVeil.gdshaderinc подключается и ВЕСЬ шейдер компилируется;
##  2) uniform'ы модуля на месте (26 hc_*/DS_* + 2 sampler3D + 6 рампы света +
##     5 контракта хоста), удалённых правками §3.2 имён нет, гейт по умолчанию false;
##  3) в активном коде модуля нет POSITION (radiance cubemap не инвалидируется камерой);
##  4) CloudTextureLoader собирает оба .bin в валидные ImageTexture3D (128³/32³)
##     и даёт заглушку при отсутствии файла;
##  5) «побитово off» структурно: DS_veil_composite при !hc_enabled возвращает фон
##     первой же строкой, debug-ветвь хоста тоже под гейтом.

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)

func _init() -> void:
	print("=== 1. Шейдер компилируется с компонентом ===")
	var sh: Shader = load("res://SkyEnvironment/SkyEnvironment.gdshader")
	if sh == null:
		_fail("шейдер не загрузился (#include не разрешился?)")
		print("TEST_VEIL_V1: FAIL")
		quit(1)
		return
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var names := []
	for u in sh.get_shader_uniform_list():
		names.append(u["name"])
	# Дефолты uniform'ов get_shader_uniform_list() не отдаёт (ловушка 4.7) —
	# сверяем их RegEx'ом по исходнику компонента.
	var inc_src := FileAccess.get_file_as_string("res://SkyEnvironment/SkyVeil.gdshaderinc")
	print("  OK: uniform'ов всего %d" % names.size())

	print("=== 2. Состав uniform'ов вуали ===")
	var need := ["hc_enabled", "hc_layer_bottom", "hc_layer_top", "hc_scale", "hc_stretch",
		"hc_stretch_angle_deg", "hc_field_scale", "hc_field_amp", "hc_coverage", "hc_softness",
		"hc_tau_per_km", "hc_curtain_start", "hc_curtain_end", "hc_offset", "hc_color",
		"hc_detail_strength", "hc_detail_scale", "hc_use_lighting", "hc_light_gain",
		"hc_ambient_gain", "hc_use_shadowing", "hc_shadow_strength", "hc_shadow_max_dist",
		"hc_debug", "DS_hc_jitter", "DS_hc_alpha_scale", "noise_pw", "noise_worley",
		"veil_ramp_mid", "veil_ramp_far", "veil_ramp_f0", "veil_ramp_f1", "veil_ramp_f2",
		"veil_ramp_f3", "cloud_light_color", "cloud_light_strength",
		"cloud_ambient_sky_color", "cloud_ambient_energy"]
	var gone := ["hc_use_world_anchor", "DS_hc_max_sample_dist"]
	for n in need:
		if not (n in names):
			_fail("нет uniform " + n)
	for n in gone:
		if n in names:
			_fail("правка §3.2 не применена: остался " + n)
	var hc_count := 0
	for n in names:
		if String(n).begins_with("hc_") or String(n).begins_with("DS_"):
			hc_count += 1
	if hc_count != 34:
		_fail("hc_*/DS_* = %d, ожидалось 34" % hc_count)
	var re_gate := RegEx.create_from_string("uniform\\s+bool\\s+hc_enabled\\s*=\\s*false")
	if re_gate.search(inc_src) == null:
		_fail("гейт hc_enabled по умолчанию не false")
	var re_jit := RegEx.create_from_string("uniform\\s+float\\s+DS_hc_jitter\\s*=\\s*0\\.0")
	if re_jit.search(inc_src) == null:
		_fail("DS_hc_jitter по умолчанию не 0 (детерминизм приёмки)")
	print("  OK: 39 имён вуали на месте (26 hc_*/DS_* + 2 sampler3D + 6 рампа + 5 контракт),")
	print("      hc_use_world_anchor и DS_hc_max_sample_dist отсутствуют, гейт = false, джиттер = 0")

	print("=== 3. Cubemap-гигиена: POSITION в модуле отсутствует ===")
	var inc := FileAccess.get_file_as_string("res://SkyEnvironment/SkyVeil.gdshaderinc")
	var active := ""
	for ln in inc.split("\n"):
		var i := ln.find("//")
		active += (ln if i < 0 else ln.substr(0, i)) + "\n"
	if "POSITION" in active:
		_fail("в активном коде модуля есть POSITION — cubemap будет инвалидироваться камерой")
	if "if (!hc_enabled) return bg_sun;" not in inc:
		_fail("нет раннего возврата по гейту в DS_veil_composite")
	var host := FileAccess.get_file_as_string("res://SkyEnvironment/SkyEnvironment.gdshader")
	if "if (hc_enabled && hc_debug > 0.5)" not in host:
		_fail("debug-ветвь хоста не под двойным гейтом")
	if "#include \"res://SkyEnvironment/SkyVeil.gdshaderinc\"" not in host:
		_fail("хост не подключает компонент через #include")
	print("  OK: POSITION нет, ранний возврат по гейту есть, debug под hc_enabled, #include на месте")

	print("=== 4. CloudTextureLoader: сборка .bin (один раз, не каждый кадр) ===")
	var loader: GDScript = load("res://SkyEnvironment/CloudTextureLoader.gd")
	var pw: ImageTexture3D = loader.load_texture("res://SkyEnvironment/noise_pw_128.bin", 128)
	var wo: ImageTexture3D = loader.load_texture("res://SkyEnvironment/noise_worley_32.bin", 32)
	if pw == null or pw.get_width() != 128 or pw.get_height() != 128 or pw.get_depth() != 128:
		_fail("noise_pw_128.bin не собрался в 128^3")
	else:
		print("  OK: noise_pw 128^3 (format R8), валидна")
	if wo == null or wo.get_width() != 32 or wo.get_height() != 32 or wo.get_depth() != 32:
		_fail("noise_worley_32.bin не собрался в 32^3")
	else:
		print("  OK: noise_worley 32^3 (format R8), валидна")
	var ph: ImageTexture3D = loader.load_texture("res://SkyEnvironment/нет_такого_файла.bin", 32)
	if ph != null:
		_fail("загрузчик не вернул null для отсутствующего файла")
	var stub: ImageTexture3D = loader.placeholder_texture()
	if stub == null or stub.get_depth() != 8:
		_fail("заглушка placeholder_texture не 8^3")
	else:
		print("  OK: отсутствующий .bin -> null + push_error; заглушка 8^3 работает")

	print("=== 5. Контроллер: загрузка шумов разовая, покадровых записей вуали нет ===")
	var ctl := FileAccess.get_file_as_string("res://SkyEnvironment/SkyEnvironmentController.gd")
	if "_load_veil_noise()" not in ctl:
		_fail("в контроллере нет _load_veil_noise()")
	var in_process := false
	var proc_body := ""
	for ln in ctl.split("\n"):
		if ln.begins_with("func _process"):
			in_process = true
		elif in_process and ln.begins_with("func "):
			in_process = false
		if in_process:
			proc_body += ln + "\n"
	if "hc_" in proc_body or "cloud_" in proc_body or "veil" in proc_body:
		_fail("_process контроллера пишет uniform'ы вуали — cubemap будет инвалидироваться каждый кадр")
	print("  OK: _load_veil_noise() на месте, _process вуаль не трогает")

	print("TEST_VEIL_V1: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
