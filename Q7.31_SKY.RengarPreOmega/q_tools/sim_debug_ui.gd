extends SceneTree
## sim_debug_ui (Q7.30) — стенд отладочной панели неба SkyDebugUI.
## headless видит логику UI (dummy RS: Control живёт, раскладка не рендерится):
##   1) контроллер резолвится из NodePath-экспорта в Сцене_неба и в Основной_сцене;
##   2) панель скрыта по умолчанию; клавиша 0 (InputEventKey напрямую)
##      показывает/скрывает;
##   3) кнопки фаз запускают плавный переход в нужную фазу; чекбокс «мгновенно» —
##      set_phase_instant;
##   4) слайдеры покрытия/ветра толкают контроллер (событийно, без таймеров);
##   5) внешняя правка контроллера догоняется слайдерами (sync из _process);
##   6) чекбоксы авто/качества управляют контроллером и профилем качества;
##   7) битый путь контроллера = warning + живая нога без панели (без падений);
##   8) родословная фикса Q7.29: node-typed экспорт НЕ используется
##      (статически: в tscn обеих сцен controller_path, а не controller);
##   9) Q7.31 (фикс «мышь привязана к персонажу»): открытие панели отпускает
##      захват мыши (CAPTURED→VISIBLE), закрытие возвращает сохранённый режим;
##      в Сцене_неба закрытие не захватывает мышь; битый UI режим не трогает.
## Лог: res://q_tools/sim_ui_out.txt

var frame := 0
var log_f: FileAccess = null
var passed := 0
var failed := 0
var sky_ui: Node = null
var sky_ctl: Node = null
var main_ui: Node = null


func check(check_name: String, cond: bool) -> void:
	if cond:
		passed += 1
		log_f.store_line("PASS " + check_name)
	else:
		failed += 1
		log_f.store_line("FAIL " + check_name)


func key0() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_0
	ev.physical_keycode = KEY_0
	ev.pressed = true
	ev.echo = false
	return ev


func panel_of(ui: Node) -> Control:
	return ui._panel as Control


func buttons_of(ui: Node) -> Array:
	var out: Array = []
	if ui._panel == null:
		return out
	var vbox := ui._panel.get_child(0) as VBoxContainer
	var phase_row := vbox.get_child(2) as HBoxContainer
	for c in phase_row.get_children():
		if c is Button and not (c is CheckBox):  # CheckBox — наследник Button!
			out.append(c)
	return out


func _init() -> void:
	log_f = FileAccess.open("res://q_tools/sim_ui_out.txt", FileAccess.WRITE)


func _finalize() -> void:
	log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
	log_f.close()


func _process(delta: float) -> bool:
	frame += 1
	match frame:
		3:
			stage_scene()
		4:
			stage_keys()
		5:
			stage_buttons()
		6:
			stage_sliders()
		7:
			stage_sync_and_checks()
		8:
			stage_mouse()
		9:
			stage_broken_and_static()
		10:
			_finalize()
			quit(0 if failed == 0 else 1)
	return false


func stage_scene() -> void:
	var sky: Node = (load("res://Сцена_неба.tscn") as PackedScene).instantiate()
	root.add_child(sky)
	sky_ui = sky.get_node_or_null("SkyDebugUI")
	check("sky: узел SkyDebugUI есть", sky_ui != null)
	if sky_ui == null:
		return
	sky_ctl = sky.get_node_or_null("TimeOfDayController")
	check("sky: controller резолвлен из NodePath", sky_ui.controller != null and sky_ui.controller == sky_ctl)
	check("sky: панель скрыта по умолчанию", panel_of(sky_ui) != null and not panel_of(sky_ui).visible)

	var main: Node = (load("res://Основная_сцена.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main_ui = main.get_node_or_null("SkyDebugUI")
	check("main: узел SkyDebugUI есть", main_ui != null)
	if main_ui != null:
		var mctl := main.get_node_or_null("TimeOfDayController")
		check("main: controller резолвлен из NodePath", main_ui.controller != null and main_ui.controller == mctl)
		check("main: панель скрыта по умолчанию", panel_of(main_ui) != null and not panel_of(main_ui).visible)


func stage_keys() -> void:
	if sky_ui == null:
		return
	sky_ui._unhandled_input(key0())
	check("key0: панель показана", panel_of(sky_ui).visible)
	sky_ui._unhandled_input(key0())
	check("key0: панель скрыта повторно", not panel_of(sky_ui).visible)
	sky_ui._unhandled_input(key0())
	check("key0: показана снова для дальнейших этапов", panel_of(sky_ui).visible)


func stage_buttons() -> void:
	if sky_ui == null:
		return
	var btns := buttons_of(sky_ui)
	check("buttons: три кнопки фаз", btns.size() == 3)
	if btns.size() != 3:
		return
	(btns[1] as Button).pressed.emit()
	check("buttons: TWILIGHT запустил переход", sky_ctl.is_transitioning() and sky_ctl.get_target_phase() == 1)
	(btns[0] as Button).pressed.emit()
	check("buttons: перезапуск с текущих значений ( всё ещё transitioning, цель SUNSET)", sky_ctl.is_transitioning() and sky_ctl.get_target_phase() == 0)
	sky_ui._instant_check.button_pressed = true
	(btns[2] as Button).pressed.emit()
	check("buttons: «мгновенно» = set_phase_instant(NIGHT)", (not sky_ctl.is_transitioning()) and sky_ctl.get_phase() == 2)
	sky_ui._instant_check.button_pressed = false


func stage_sliders() -> void:
	if sky_ui == null:
		return
	sky_ui._cov_slider.value = 0.7
	check("slider: покрытие 0.70 дошло до контроллера", absf(sky_ctl.current.cloud_coverage - 0.7) < 0.001)
	sky_ui._wind_slider.value = 2.5
	check("slider: ветер x2.50 дошёл до контроллера", absf(sky_ctl.get_wind_multiplier() - 2.5) < 0.001)
	check("slider: подписи значений обновлены", sky_ui._cov_value.text == "0.70" and sky_ui._wind_value.text == "2.50")


func stage_sync_and_checks() -> void:
	if sky_ui == null:
		return
	# внешняя правка мимо панели (например, будущий хоткей или код) — слайдеры догонят на следующем кадре
	sky_ctl.debug_set_coverage(0.3)
	sky_ctl.debug_set_wind_multiplier(1.25)
	# догон произойдёт в _process следующего кадра — проверяем на кадре 7 после кадра 6
	check("sync: покрытие догонится на след. кадре (пре-условие)", absf(sky_ui._cov_slider.value - 0.7) < 0.001)


func stage_mouse() -> void:
	# Q7.31: в Основной_сцене мышь захвачена ThirdPersonCamera. Headless-
	# DisplayServer режим мыши игнорирует (замер: set CAPTURED → get 0), поэтому
	# в панель инжектируется фейковый режим (словарь — по ссылке, лямбды его
	# разделяют) и проверяется сама логика: открыть = сохранить режим и
	# освободить мышь, закрыть = вернуть сохранённый режим.
	if main_ui == null or sky_ui == null:
		return
	var st := {"mode": Input.MOUSE_MODE_CAPTURED, "log": []}
	main_ui.mouse_get_mode = func() -> int: return st["mode"]
	main_ui.mouse_set_mode = func(m: int) -> void:
		st["mode"] = m
		st["log"].append(m)
	main_ui._unhandled_input(key0())
	check("mouse: панель Основной_сцены открыта", panel_of(main_ui).visible)
	check("mouse: при открытии захват отпущен (VISIBLE)", int(st["mode"]) == Input.MOUSE_MODE_VISIBLE)
	check("mouse: режим до открытия сохранён (CAPTURED)", main_ui._saved_mouse_mode == Input.MOUSE_MODE_CAPTURED)
	main_ui._unhandled_input(key0())
	check("mouse: панель Основной_сцены закрыта", not panel_of(main_ui).visible)
	check("mouse: при закрытии захват возвращён (CAPTURED)", int(st["mode"]) == Input.MOUSE_MODE_CAPTURED)
	check("mouse: ровно две записи режима (отпустил/вернул)", st["log"] == [Input.MOUSE_MODE_VISIBLE, Input.MOUSE_MODE_CAPTURED])
	# Сцена_неба: мышь изначально свободна — закрытие панели НЕ должно её захватывать.
	# Панель сейчас открыта (stage_keys), _saved_mouse_mode у неё = VISIBLE.
	var st2 := {"mode": Input.MOUSE_MODE_VISIBLE}
	sky_ui.mouse_get_mode = func() -> int: return st2["mode"]
	sky_ui.mouse_set_mode = func(m: int) -> void: st2["mode"] = m
	sky_ui._unhandled_input(key0())
	check("mouse: закрытие в Сцене_неба вернуло VISIBLE (без захвата)", (not panel_of(sky_ui).visible) and int(st2["mode"]) == Input.MOUSE_MODE_VISIBLE)
	sky_ui._unhandled_input(key0())
	check("mouse: повторное открытие в Сцене_неба — снова VISIBLE", panel_of(sky_ui).visible and int(st2["mode"]) == Input.MOUSE_MODE_VISIBLE)
	sky_ui._unhandled_input(key0())


func stage_broken_and_static() -> void:
	if sky_ui != null:
		check("sync: слайдер догнал внешнюю правку покрытия", absf(sky_ui._cov_slider.value - 0.3) < 0.001)
		check("sync: слайдер догнал внешнюю правку ветра", absf(sky_ui._wind_slider.value - 1.25) < 0.001)
		# чекбоксы
		sky_ui._auto_check.button_pressed = true
		sky_ui._auto_check.toggled.emit(true)
		check("check: автопрогресс включён", sky_ctl.auto_progress)
		sky_ui._auto_check.toggled.emit(false)
		check("check: автопрогресс выключен", not sky_ctl.auto_progress)
		sky_ui._quality_check.toggled.emit(false)
		check("check: качество -> Performance", sky_ctl.quality.quality_detail < 0.5)
		sky_ui._quality_check.toggled.emit(true)
		check("check: качество -> Quality", sky_ctl.quality.quality_detail > 0.5)
	# битый путь: warning + нога жива, панели нет, ключ 0 не роняет и мышь не трогает
	var st3 := {"log": []}
	var broken: Node = (load("res://Scripts/Environment/SkyDebugUI.gd") as GDScript).new()
	broken.name = "BrokenUI"
	broken.mouse_get_mode = func() -> int: return Input.MOUSE_MODE_CAPTURED
	broken.mouse_set_mode = func(m: int) -> void: st3["log"].append(m)
	root.add_child(broken)
	broken._unhandled_input(key0())
	check("broken: пустой путь = null controller, без падения", broken.controller == null and broken._panel == null)
	check("broken: ключ 0 без панели не трогает режим мыши", st3["log"].is_empty())
	# статическая родословная фикса: в tscn обеих сцен — controller_path (NodePath), не node-typed controller
	var a := FileAccess.get_file_as_string("res://Сцена_неба.tscn")
	var b := FileAccess.get_file_as_string("res://Основная_сцена.tscn")
	check("static: Сцена_неба использует controller_path", a.contains("controller_path = NodePath"))
	check("static: Основная_сцена использует controller_path", b.contains("controller_path = NodePath"))
	check("static: node-typed присваивания controller= в tscn исчезли", (not a.contains("\ncontroller = ")) and (not b.contains("\ncontroller = ")))
