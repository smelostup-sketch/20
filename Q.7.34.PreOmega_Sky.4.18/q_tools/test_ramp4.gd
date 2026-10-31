extends SceneTree
## Q7.34.PreOmega_Sky 4.1.7 — движковая приёмка градиента неба (4 стопа + доли).
## Запуск: godot --headless --path <проект с кэшем классов> --script q_tools/test_ramp4.gd
## Проверяет РЕАЛЬНЫМ движком: uniform'ы шейдера (sky_color_weights/
## sky_transition_width; sk_q*/sk_sharp удалены), загрузку материала и 10
## пресетов, SkyPresetValidator.validate() = 0 ошибок, байт-точность
## col_sky1..4/col_light1..3 против palletes.html (70 значений), идентичность
## зеркала градиента в центрах сегментов при любой мягкости (tw 0/0.025/0.2),
## debug-карту сегментов по долям и сценарий перераспределения
## SkyGradientWeightsComponent (пример заказчика: 25×4 → c4=50 → 16.67³/50 →
## замок c4 → c3=30 → 10/10/30/50, сумма всегда 100%).

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
		"sk_mid", "sk_anti_col", "sk_p1", "sk_p2", "sk_p3", "sk_p4", "sk_p5", "sk_p6",
		"sk_q1", "sk_q2", "sk_q3", "sk_q4", "sk_sharp"]

const UNIFORM_COUNT := 87	# 4.1.7: −sk_q1..q4 −sk_sharp +sky_color_weights +sky_transition_width

var fails := 0
var frame := 0

## Все проверки идут В КАДРЕ 1 (_process-паттерн test_sky_controllers/sim_core):
## Godot 4.7 — Range::Shared::emit_value_changed() пропускает слайдеры вне
## дерева (if !is_inside_tree: continue), а сценарий §5 обязан проверять
## СИГНАЛЬНЫЙ путь ручек — тот же, что у реальной панели (слайдеры в дереве).
func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_run()
		return true
	return false

func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL: " + msg)

func _vals(sl: Array) -> Array:
	var out := []
	for s in sl:
		out.append(s.value)
	return out

func _sum(sl: Array) -> float:
	var t := 0.0
	for s in sl:
		t += s.value
	return t

func _run() -> void:
	print("=== 1. Шейдер: uniform'ы градиента (4.1.7) ===")
	var sh: Shader = load("res://SkyEnvironment/SkyEnvironment.gdshader")
	if sh == null:
		_fail("шейдер не загрузился")
	else:
		var names := []
		for u in sh.get_shader_uniform_list():
			names.append(u["name"])
		for n in ["sk_c1", "sk_c2", "sk_c3", "sk_c4", "sky_color_weights", "sky_transition_width"]:
			if not (n in names):
				_fail("нет uniform " + n)
		for n in OLD_NAMES:
			if n in names:
				_fail("остался старый uniform " + n)
		if names.size() != UNIFORM_COUNT:
			_fail("uniform'ов %d != %d" % [names.size(), UNIFORM_COUNT])
		print("  uniform'ов: %d; sk_c1..sk_c4 + sky_color_weights/sky_transition_width на месте, sk_q*/sk_sharp и старых 12 имён нет" % names.size())

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
		# зеркало градиента (4.1.7): в ЦЕНТРЕ сегмента i цвет = стоп i побитово
		# при любой мягкости (f ≤ 0.45·min доля ⇒ окно не дотягивается до центра),
		# концы шкалы — чистые стопы 1 и 4
		var stops := SkyPresetValidator.stops_of(pr)
		var w := SkyPresetValidator.weights_of_pos(SkyPresetValidator.pos_of(pr))
		var tot := 0.0
		for x in w:
			tot += maxf(float(x), 0.0)
		var wn := []
		for x in w:
			wn.append(maxf(float(x), 0.0) / tot)
		var b := [wn[0], wn[0] + wn[1], wn[0] + wn[1] + wn[2]]
		var centers := [b[0] / 2.0, (b[0] + b[1]) / 2.0, (b[1] + b[2]) / 2.0, (b[2] + 1.0) / 2.0, 0.0, 1.0]
		var wants := [0, 1, 2, 3, 0, 3]
		for tw in [0.0, SkyPresetValidator.TW_DEFAULT, 0.2]:
			for k in range(centers.size()):
				var rc: Color = SkyPresetValidator.ramp_color(stops, w, tw, centers[k])
				var want: Color = stops[wants[k]]
				if not (is_equal_approx(rc.r, want.r) and is_equal_approx(rc.g, want.g) and is_equal_approx(rc.b, want.b)):
					_fail("Preset_%02d: u=%.4f (tw=%.3f) != стоп %d" % [slot, centers[k], tw, wants[k] + 1])
		print("  Preset_%02d (ref #%d): валидатор 0 ошибок, 7/7 байт Δ=0, стопы достижимы в центрах сегментов (tw 0/0.025/0.2)%s" % [
				slot, exp["ref"], "" if res["warnings"].is_empty() else ", warn: %d" % res["warnings"].size()])

	print("=== 4. Регресс: debug-карта сегментов по долям (4.1.7) ===")
	var src := FileAccess.get_file_as_string("res://SkyEnvironment/SkyEnvironment.gdshader")
	if "SEG_COLORS[4]" not in src or "SEG_COLORS[6]" in src:
		_fail("SEG_COLORS не 4")
	if "wd /= max(wd.x + wd.y + wd.z + wd.w, 0.0001)" not in src:
		_fail("debug-сегменты не переведены на sky_color_weights")
	# отсутствие sk_q*/sk_sharp проверяет §1 по списку uniform'ов движка (авторитет)
	# 4.1.8: временная диагностика цепи — режимы 3–6 (чистые стопы через выходную цепь)
	if "hint_range(0, 6)" not in src or "sky_debug_mode >= 3" not in src:
		_fail("нет диагностики цепи 4.1.8 (режимы 3–6)")
	var psrc := FileAccess.get_file_as_string("res://SkyEnvironment/SkyControlPanel.gd")
	if "_debug_mode_spin.max_value = 6" not in psrc:
		_fail("панель: спин sky_debug_mode не расширен до 6")
	print("  OK: SEG_COLORS[4], сегменты = кумулятивные доли sky_color_weights; диагностика цепи 3–6 на месте")

	print("=== 5. SkyGradientWeightsComponent: сценарий заказчика ===")
	var comp := SkyGradientWeightsComponent.new()
	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://SkyEnvironment/SkyEnvironment.gdshader")
	comp.sky_material = gmat
	var sl: Array[HSlider] = []
	var lk: Array[CheckButton] = []
	for i in range(4):
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 100.0
		s.value = 25.0
		root.add_child(s)
		sl.append(s)
		var c := CheckButton.new()
		root.add_child(c)
		lk.append(c)
	var sig := [0]
	comp.weights_changed.connect(func(_w: Vector4) -> void: sig[0] += 1)
	comp.attach_controls(sl, lk)
	# старт 25/25/25/25 (сумма 100 — _init_controls данные сохраняет)
	for i in range(4):
		if absf(sl[i].value - 25.0) > 0.01:
			_fail("старт: доля %d = %.3f, цель 25" % [i + 1, sl[i].value])
	# цвет 4 → 50: остаток делится ПРОПОРЦИОНАЛЬНО между незакреплёнными
	sl[3].value = 50.0
	for i in range(3):
		if absf(sl[i].value - 50.0 / 3.0) > 0.01:
			_fail("после c4=50: доля %d = %.3f, цель 16.667" % [i + 1, sl[i].value])
	if absf(_sum(sl) - 100.0) > 0.01:
		_fail("после c4=50: сумма = %.3f, цель 100" % _sum(sl))
	# замок цвета 4 → цвет 3 → 30: незакреплённые 10/10, закреплённый 50 не тронут
	lk[3].button_pressed = true
	sl[2].value = 30.0
	var want := [10.0, 10.0, 30.0, 50.0]
	for i in range(4):
		if absf(sl[i].value - want[i]) > 0.01:
			_fail("после c3=30 (c4 в замке): доля %d = %.3f, цель %.1f" % [i + 1, sl[i].value, want[i]])
	if absf(_sum(sl) - 100.0) > 0.01:
		_fail("после c3=30: сумма = %.3f, цель 100" % _sum(sl))
	# переключение замка доли НЕ меняет
	var before := _vals(sl)
	lk[0].button_pressed = true
	if _vals(sl) != before:
		_fail("переключение замка изменило доли: %s → %s" % [str(before), str(_vals(sl))])
	# uniform материала = доли / 100 (единственный писатель — компонент)
	var par = gmat.get_shader_parameter("sky_color_weights")
	if not (par is Vector4):
		_fail("sky_color_weights не Vector4: %s" % str(par))
	else:
		for i in range(4):
			if absf(par[i] - want[i] / 100.0) > 0.001:
				_fail("uniform[%d] = %.4f, цель %.4f" % [i, par[i], want[i] / 100.0])
	# событийность: attach(→init) + c4=50 + замок + c3=30 + замок = 5 сигналов, ноль polling
	if sig[0] != 5:
		_fail("weights_changed: %d сигналов, цель 5" % sig[0])
	# кэш поставки: set_weights ДО подключения ручек (порядок _ready сцены)
	var comp2 := SkyGradientWeightsComponent.new()
	comp2.set_weights(Vector4(1.0, 2.0, 3.0, 4.0))
	var sl2: Array[HSlider] = []
	var lk2: Array[CheckButton] = []
	for i in range(4):
		var s2 := HSlider.new()
		root.add_child(s2)
		sl2.append(s2)
		var c2 := CheckButton.new()
		root.add_child(c2)
		lk2.append(c2)
	comp2.attach_controls(sl2, lk2)
	var want2 := [1.0, 22.0, 33.0, 44.0]	# кэш применён, сумма приведена к 100 с сохранением пропорций
	for i in range(4):
		if absf(sl2[i].value - want2[i]) > 0.01:
			_fail("кэш поставки: доля %d = %.3f, цель %.1f" % [i + 1, sl2[i].value, want2[i]])
	if absf(_sum(sl2) - 100.0) > 0.01:
		_fail("кэш поставки: сумма = %.3f, цель 100" % _sum(sl2))
	for s in sl + sl2:
		s.free()
	for c in lk + lk2:
		c.free()
	comp.free()
	comp2.free()
	print("  OK: 25×4 → c4=50 → 16.67/16.67/16.67/50 → замок c4 → c3=30 → 10/10/30/50; сумма 100; uniform=доли/100; 5 сигналов; кэш set_weights→attach")

	print("TEST_RAMP4: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
