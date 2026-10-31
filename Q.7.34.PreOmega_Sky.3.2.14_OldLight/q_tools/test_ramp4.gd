extends SceneTree
## Q7.34.PreOmega_Sky3.2.4 — движковая приёмка рампы 4 стопа (palletes.html).
## Запуск: godot --headless --path <проект с кэшем классов> --script q_tools/test_ramp4.gd
## Проверяет РЕАЛЬНЫМ движком: uniform'ы шейдера, загрузку материала и 10 пресетов,
## SkyPresetValidator.validate() = 0 ошибок, байт-точность col_sky1..4/col_light1..3
## против palletes.html (ожидаемые байты вшиты генератором из HTML, 70 значений),
## идентичность зеркала рампы на стопах.

# slot -> {ref, sky: шаги 1..4 (RGB-байты palletes.html), env: L1..L3}
const EXPECT := {
	1: {"ref": 1, "sky": [[7, 17, 48], [22, 54, 122], [53, 96, 172], [207, 228, 255]], "env": [[244, 249, 255], [35, 55, 95], [11, 22, 46]]},
	2: {"ref": 2, "sky": [[4, 16, 34], [43, 117, 181], [140, 196, 232], [255, 243, 214]], "env": [[255, 243, 224], [232, 176, 160], [53, 73, 95]]},
	3: {"ref": 3, "sky": [[14, 8, 40], [42, 32, 96], [90, 68, 148], [200, 152, 216]], "env": [[246, 205, 232], [138, 112, 172], [64, 52, 94]]},
	4: {"ref": 4, "sky": [[2, 4, 26], [0, 80, 200], [0, 191, 255], [232, 168, 240]], "env": [[208, 152, 240], [106, 74, 160], [14, 22, 56]]},
	5: {"ref": 5, "sky": [[6, 10, 32], [48, 184, 224], [154, 106, 208], [244, 156, 203]], "env": [[244, 144, 192], [122, 68, 176], [36, 18, 72]]},
	8: {"ref": 6, "sky": [[93, 143, 200], [140, 134, 190], [216, 138, 158], [255, 208, 112]], "env": [[255, 190, 102], [232, 112, 106], [86, 73, 126]]},
	9: {"ref": 7, "sky": [[140, 154, 216], [196, 168, 216], [255, 212, 158], [255, 240, 200]], "env": [[255, 220, 168], [242, 168, 184], [122, 104, 152]]},
	7: {"ref": 8, "sky": [[102, 114, 126], [232, 85, 72], [242, 86, 106], [255, 243, 184]], "env": [[255, 221, 144], [217, 88, 74], [36, 64, 74]]},
	6: {"ref": 9, "sky": [[32, 38, 58], [122, 40, 50], [224, 72, 56], [255, 242, 216]], "env": [[244, 152, 136], [196, 56, 56], [48, 20, 28]]},
	10: {"ref": 10, "sky": [[28, 78, 128], [74, 138, 184], [168, 208, 216], [245, 224, 176]], "env": [[246, 184, 148], [255, 243, 228], [128, 137, 172]]},
}

const OLD_NAMES := ["sk_glow_col", "sk_horizon", "sk_band_col", "sk_band2_col",
		"sk_mid", "sk_anti_col", "sk_p1", "sk_p2", "sk_p3", "sk_p4", "sk_p5", "sk_p6"]

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)

func _init() -> void:
	print("=== 1. Шейдер: uniform'ы рампы ===")
	var sh: Shader = load("res://SkyEnvironment/SkyEnvironment.gdshader")
	if sh == null:
		_fail("шейдер не загрузился")
	else:
		var names := []
		for u in sh.get_shader_uniform_list():
			names.append(u["name"])
		for n in ["sk_c1", "sk_c2", "sk_c3", "sk_c4", "sk_q1", "sk_q2", "sk_q3", "sk_q4"]:
			if not (n in names):
				_fail("нет uniform " + n)
		for n in OLD_NAMES:
			if n in names:
				_fail("остался старый uniform " + n)
		print("  uniform'ов: %d; sk_c1..sk_c4 + sk_q1..sk_q4 на месте, старых 12 имён нет" % names.size())

	print("=== 2. Материал загружается ===")
	var mat: ShaderMaterial = load("res://SkyEnvironment/SkyEnvironmentMaterial.tres")
	if mat == null or mat.shader == null:
		_fail("материал/шейдер материала не загрузился")
	else:
		print("  OK: SkyEnvironmentMaterial.tres, shader = %s" % mat.shader.resource_path.get_file())

	print("=== 3. Пресеты: загрузка, валидатор, байты, зеркало ===")
	for slot in range(1, 11):
		var path := "res://SkyEnvironment/SkyPreset/Preset_%02d.tres" % slot
		var pr = load(path)
		if pr == null:
			_fail(path + ": не загрузился")
			continue
		var res: Dictionary = SkyPresetValidator.validate(pr)
		if res["errors"].size() > 0:
			_fail(path + ": ошибки валидатора: " + "; ".join(res["errors"]))
		var exp: Dictionary = EXPECT[slot]
		# байт-точность: col_sky1..4 = шаги 1..4 HTML, col_light1..3 = окружение
		for i in range(4):
			var c: Color = pr.get("col_sky%d" % (i + 1))
			var got := [int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0))]
			if got != exp["sky"][i]:
				_fail("Preset_%02d col_sky%d = %s, цель %s" % [slot, i + 1, str(got), str(exp["sky"][i])])
		for i in range(3):
			var c: Color = pr.get("col_light%d" % (i + 1))
			var got := [int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0))]
			if got != exp["env"][i]:
				_fail("Preset_%02d col_light%d = %s, цель %s" % [slot, i + 1, str(got), str(exp["env"][i])])
		# зеркало рампы: в позиции q_{i+1} цвет = стоп i+1 побитово (окно прижато вправо)
		var stops := SkyPresetValidator.stops_of(pr)
		var pos := SkyPresetValidator.pos_of(pr)
		for i in range(1, 4):
			var rc: Color = SkyPresetValidator.ramp_color(stops, pos, pr.sharp, pos[i])
			var want: Color = stops[i]
			if not (is_equal_approx(rc.r, want.r) and is_equal_approx(rc.g, want.g) and is_equal_approx(rc.b, want.b)):
				_fail("Preset_%02d: рампа в q%d != стоп %d" % [slot, i + 1, i + 1])
		print("  Preset_%02d (ref #%d): валидатор 0 ошибок, 7/7 байт Δ=0, зеркало идентично%s" % [
				slot, exp["ref"], "" if res["warnings"].is_empty() else ", warn: %d" % res["warnings"].size()])

	print("=== 4. Регресс: 4 сегмента debug-карты (структурно) ===")
	var src := FileAccess.get_file_as_string("res://SkyEnvironment/SkyEnvironment.gdshader")
	if "SEG_COLORS[4]" not in src or "SEG_COLORS[6]" in src:
		_fail("SEG_COLORS не 4")
	else:
		print("  OK: SEG_COLORS[4], порогов 3 (sk_q1..sk_q3)")

	print("TEST_RAMP4: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
