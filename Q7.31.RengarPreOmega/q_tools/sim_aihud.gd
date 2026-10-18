extends SceneTree
## Q7.18 — приёмка экранного журнала ИИ (AIDebugLogPanel):
##   1) панель существует и скрыта по умолчанию;
##   2) тильда (KEY_QUOTELEFT) через событийный конвейер (_unhandled_input)
##      переключает видимость туда-обратно;
##   3) после включения панель находит врага (группа "enemy") и в статусе есть
##      строки РЕАЛЬНО работающего ИИ: «мозг: состояние=», «UtilityAI: ВЫКЛЮЧЕН»;
##   4) живой бой наполняет ленту: «Решение движения» и «Намерение атаки»
##      (враг на спавне в 0.87 м от игрока — сразу STOPPED и атакует);
##   5) счётчики мозга согласованы с лентой (intents_sent >= 1).
## Лог: res://q_tools/sim_aihud_out.txt

var frame := 0
var log_f: FileAccess = null
var panel: Node = null
var enemy: CharacterBody3D = null
var brain: Node = null
var passed := 0
var failed := 0
var checked_stage := 0


func check(check_name: String, cond: bool) -> void:
	if cond:
		passed += 1
		log_f.store_line("PASS " + check_name)
	else:
		failed += 1
		log_f.store_line("FAIL " + check_name)


func _initialize() -> void:
	log_f = FileAccess.open("res://q_tools/sim_aihud_out.txt", FileAccess.WRITE)


func _tilde(pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_QUOTELEFT
	ev.physical_keycode = KEY_QUOTELEFT
	ev.pressed = pressed
	ev.echo = false
	Input.parse_input_event(ev)


func _setup_scene() -> void:
	var scn := load("res://Основная_сцена.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	panel = inst.get_node_or_null("AIDebugLog")
	enemy = inst.get_node_or_null("EnemyCharacterBody3D") as CharacterBody3D
	if panel == null or enemy == null:
		log_f.store_line("AIHUD FAIL nodes")
		log_f.close()
		quit(1)
	brain = enemy.get_node_or_null("AIBrainComponent")
	# Манекен глушим (протокол); враг ЖИВ — он наполняет ленту реальными событиями.
	var dummy := inst.get_node_or_null("DummyMannequin")
	if dummy != null:
		(dummy as Node).set_physics_process(false)
		(dummy as Node).set_process(false)
		for child_name in ["MovementShell", "AIIntentComponent", "AIBrainComponent"]:
			var mn: Node = (dummy as Node).get_node_or_null(child_name)
			if mn != null:
				mn.set_physics_process(false)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_setup_scene()
	elif frame == 4:
		check("панель существует и скрыта по умолчанию",
			panel != null and panel.get("panel_visible") == false)
		_tilde(true)
	elif frame == 6:
		_tilde(false) # отпускаем (камера тоже видит тильду — free look, безвредно)
	elif frame == 10:
		check("тильда включила панель (событийный конвейер _unhandled_input)",
			panel.get("panel_visible") == true)
		var status: String = panel.get("_status_label").text
		check("панель нашла врага и показывает мозг", status.contains("Враг:") and status.contains("мозг: состояние="))
		check("спящий UtilityAI помечен ВЫКЛЮЧЕН (больше никаких замороженных весов)",
			status.contains("UtilityAI: ВЫКЛЮЧЕН"))
	elif frame == 400:
		# ~6.5 с wall-clock: враг к этому времени решил и атаковал.
		var joined := "\n".join(panel.get("_lines"))
		check("лента: есть «Решение движения»", joined.contains("Решение движения"))
		check("лента: есть «Намерение атаки»", joined.contains("Намерение атаки"))
		check("мозг реально подавал намерения: intents_sent=%d >= 1" % int(brain.get("intents_sent")),
			int(brain.get("intents_sent")) >= 1)
		_tilde(true)  # второе нажатие — выключение (доставка на следующем кадре)
	elif frame == 402:
		check("второе нажатие тильды выключило панель", panel.get("panel_visible") == false)
		log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
		log_f.close()
		quit(0 if failed == 0 else 1)
		return true
	elif frame > 2000:
		log_f.store_line("TIMEOUT")
		log_f.close()
		quit(1)
		return true
	return false
