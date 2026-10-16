extends SceneTree
## Q7.16 п.7A — приёмка боевых кнопок через Input Map.
## Инжект СЫРЫХ мышиных событий (Input.parse_input_event) проходит весь живой
## путь: событие -> Player3d._input -> экшены "attack"/"block" -> AttackInput/
## CombatComponent. Проверяется:
##   1) экшены зарегистрированы (attack=ЛКМ/1, block=ПКМ/2);
##   2) ПКМ press -> is_block_input_held=true (request_block пройден);
##   3) ПКМ release -> is_block_input_held=false;
##   4) ПКМ hold + mouse motion -> block_mouse_acc копит дельту (поток жестов
##      жив — это же канал для будущих финтов);
##   5) ЛКМ press -> AttackInput WAITING_DIRECTION;
##   6) ЛКМ release до жеста -> IDLE (cancel released_before_direction).
## Лог: res://q_tools/sim_mouse_out.txt

var frame := 0
var log_f: FileAccess = null
var player: CharacterBody3D = null
var aic: Node = null
var pcc: Node = null
var passed := 0
var failed := 0


func check(check_name: String, cond: bool) -> void:
	if cond:
		passed += 1
		log_f.store_line("PASS " + check_name)
	else:
		failed += 1
		log_f.store_line("FAIL " + check_name)


func _initialize() -> void:
	log_f = FileAccess.open("res://q_tools/sim_mouse_out.txt", FileAccess.WRITE)


func _setup_scene() -> void:
	var scn := load("res://Основная_сцена.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	player = inst.get_node_or_null("PLayerCharacterBody3D") as CharacterBody3D
	if player == null:
		log_f.store_line("MOUSESIM FAIL nodes")
		log_f.close()
		quit(1)
	aic = player.get_node("AttackInputComponent")
	pcc = player.get_node("CombatComponent")
	for n in [inst.get_node_or_null("EnemyCharacterBody3D"), inst.get_node_or_null("DummyMannequin")]:
		if n != null:
			(n as Node).set_physics_process(false)
			(n as Node).set_process(false)
			for child_name in ["MovementShell", "AIIntentComponent", "AIBrainComponent"]:
				var mn: Node = (n as Node).get_node_or_null(child_name)
				if mn != null:
					mn.set_physics_process(false)
	player.global_position = Vector3(12.0, 1.0, 12.0)
	player.velocity = Vector3.ZERO


func _mouse_button(index: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = index
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _mouse_motion(rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	Input.parse_input_event(ev)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_setup_scene()
	elif frame == 4:
		# 1. Реестр экшенов.
		var atk_events := InputMap.action_get_events("attack") if InputMap.has_action("attack") else []
		var blk_events := InputMap.action_get_events("block") if InputMap.has_action("block") else []
		var atk_btn := -1
		var blk_btn := -1
		for e in atk_events:
			if e is InputEventMouseButton:
				atk_btn = e.button_index
		for e in blk_events:
			if e is InputEventMouseButton:
				blk_btn = e.button_index
		check("экшен attack = ЛКМ (button_index=1), получено %d" % atk_btn, atk_btn == MOUSE_BUTTON_LEFT)
		check("экшен block = ПКМ (button_index=2), получено %d" % blk_btn, blk_btn == MOUSE_BUTTON_RIGHT)
	elif frame == 6:
		_mouse_button(MOUSE_BUTTON_RIGHT, true)
	elif frame == 8:
		check("ПКМ press -> is_block_input_held", pcc.is_block_input_held == true)
		_mouse_motion(Vector2(10.0, 0.0))
	elif frame == 10:
		check("motion во время блока копится в block_mouse_acc (канал жестов/финтов жив)",
			absf(pcc.block_mouse_acc.x - 10.0) < 0.001)
		_mouse_button(MOUSE_BUTTON_RIGHT, false)
	elif frame == 12:
		check("ПКМ release -> held=false", pcc.is_block_input_held == false)
		_mouse_button(MOUSE_BUTTON_LEFT, true)
	elif frame == 14:
		check("ЛКМ press -> WAITING_DIRECTION", aic.get_state_name() == "WAITING_DIRECTION")
		_mouse_button(MOUSE_BUTTON_LEFT, false)
	elif frame == 16:
		check("ЛКМ release до жеста -> IDLE", aic.get_state_name() == "IDLE")
	elif frame == 20:
		log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
		log_f.close()
		quit(0 if failed == 0 else 1)
		return true
	elif frame > 400:
		log_f.store_line("TIMEOUT")
		log_f.close()
		quit(1)
		return true
	return false
