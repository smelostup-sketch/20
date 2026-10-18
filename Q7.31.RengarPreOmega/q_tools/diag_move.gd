extends SceneTree
## Q-диагностика (проблема: боковое скольжение/дрожь при старте и остановке).
## Живой сим основной сцены: физический зонд внутри PlayerBody логирует каждый
## физический тик: позицию/скорость тела, yaw тела и камеры, глобальную позицию
## Hips, смещение VisualModel, текущий клип. Сценарий — env DIAG_SCENARIO:
##   STRAIGHT     — W на тиках 91..180 (стоп-кран), мышь не трогаем
##   IDLE         — без ввода (контроль стоя)
##   MOUSE_OFFSET — W на 91..229 + поворот yaw камеры на +35° на тике 140
## Лог: res://q_tools/diag_move_out.txt (колонки парсятся diag_move_parse.py)

const SPAWN_OPEN := Vector3(12.0, 1.0, 12.0)

var frame := 0
var log_f: FileAccess = null
var scenario := "STRAIGHT"
var probe: Node = null


class MoveProbe:
	extends Node
	var log_f: FileAccess
	var player: CharacterBody3D
	var cam: Node
	var model: Node3D
	var anim_p: AnimationPlayer
	var skel: Skeleton3D
	var scenario := "STRAIGHT"
	var tick := 0
	var last_anim: StringName = &"<none>"
	var hips_bone := -1
	var end_tick := 320
	var done := false

	func _physics_process(_delta: float) -> void:
		tick += 1
		# --- ввод по расписанию (инжект в Input singleton) ---
		if scenario == "STRAIGHT":
			if tick == 91:
				_key(KEY_W, true)
			elif tick == 181:
				_key(KEY_W, false)
		elif scenario == "MOUSE_OFFSET":
			if tick == 91:
				_key(KEY_W, true)
			elif tick == 140 and cam != null:
				cam.set("yaw", float(cam.get("yaw")) + deg_to_rad(35.0))
				log_f.store_line("T=%03d EVENT cam_yaw+=35deg" % tick)
			elif tick == 230:
				_key(KEY_W, false)

		# --- телеметрия ---
		var gp: Vector3 = player.global_position
		var vel: Vector3 = player.velocity
		var ry := rad_to_deg(player.rotation.y)
		var cy := rad_to_deg(float(cam.get("yaw"))) if cam != null else 0.0
		var hips := Vector3(NAN, NAN, NAN)
		if skel != null and hips_bone >= 0:
			hips = (skel.global_transform * skel.get_bone_global_pose(hips_bone)).origin
		var mo := Vector3.ZERO
		if model != null:
			mo = model.global_position - gp
		var anim: StringName = anim_p.current_animation if anim_p != null else &"?"
		var apos := anim_p.current_animation_position if anim_p != null else 0.0
		log_f.store_line(
			"T=%03d pos=%.4f,%.4f,%.4f vel=%.3f,%.3f,%.3f rotY=%.3f camYaw=%.3f " % [tick, gp.x, gp.y, gp.z, vel.x, vel.y, vel.z, ry, cy]
			+ "hips=%.4f,%.4f,%.4f modelOff=%.4f,%.4f,%.4f anim=%s apos=%.3f floor=%d" % [
				hips.x, hips.y, hips.z, mo.x, mo.y, mo.z, String(anim), apos,
				1 if player.is_on_floor() else 0])
		if anim != last_anim:
			log_f.store_line("T=%03d EVENT anim_switch %s -> %s (speed_h=%.3f)" % [
				tick, last_anim, anim, Vector2(vel.x, vel.z).length()])
			last_anim = anim
		if tick >= end_tick:
			done = true

	func _key(k: Key, pressed: bool) -> void:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = pressed
		ev.echo = false
		Input.parse_input_event(ev)
		log_f.store_line("T=%03d EVENT key %s %s" % [tick, "W" if k == KEY_W else str(k), "PRESS" if pressed else "RELEASE"])


func _initialize() -> void:
	var env := OS.get_environment("DIAG_SCENARIO")
	if env != "":
		scenario = env
	log_f = FileAccess.open("res://q_tools/diag_move_out.txt", FileAccess.WRITE)
	log_f.store_line("DIAG_MOVE scenario=%s" % scenario)


func _setup_scene() -> void:
	# Единый протокол изоляции (паттерн sim_core): instantiate + глушение
	# врага/манекена + телепорт игрока на открытое место в ОДНОМ блоке frame-1.
	var scn := load("res://Основная_сцена.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	var player := inst.get_node_or_null("PLayerCharacterBody3D") as CharacterBody3D
	if player == null:
		log_f.store_line("DIAG_MOVE FAIL player node")
		log_f.close()
		quit(1)
	for n in [inst.get_node_or_null("EnemyCharacterBody3D"), inst.get_node_or_null("DummyMannequin")]:
		if n != null:
			(n as Node).set_physics_process(false)
			(n as Node).set_process(false)
			for child_name in ["MovementShell", "AIIntentComponent", "AIBrainComponent"]:
				var mn: Node = (n as Node).get_node_or_null(child_name)
				if mn != null:
					mn.set_physics_process(false)
	# Телепорт на открытый угол полигона (земля 40x40, враг/куст/манекен у центра)
	player.global_position = SPAWN_OPEN
	player.velocity = Vector3.ZERO

	probe = MoveProbe.new()
	probe.name = "QMoveProbe"
	probe.log_f = log_f
	probe.player = player
	probe.scenario = scenario
	probe.cam = inst.get_node_or_null("Camera3D")
	probe.model = player.get_node_or_null("VisualModel") as Node3D
	probe.anim_p = player.get_node_or_null("VisualModel/AnimationPlayer") as AnimationPlayer
	if probe.model != null:
		probe.skel = probe.model.get_node_or_null("Skeleton3D") as Skeleton3D
	if probe.skel != null:
		probe.hips_bone = probe.skel.find_bone("mixamorig_Hips")
		if probe.hips_bone < 0 and probe.skel.get_bone_count() > 0:
			probe.hips_bone = 0
			log_f.store_line("WARN hips bone name fallback to bone0=%s" % probe.skel.get_bone_name(0))
	# Зонд — ПОСЛЕДНИЙ ребёнок тела: его _physics_process видит состояние
	# уже ПОСЛЕ move_and_slide() и locomotion-переключений текущего тика.
	player.add_child(probe)
	log_f.store_line("SETUP ok hips_bone=%d cam=%s anim_p=%s" % [probe.hips_bone, probe.cam != null, probe.anim_p != null])


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_setup_scene()
	elif frame > 3 and probe != null and probe.done:
		log_f.store_line("DIAG_MOVE END scenario=%s ticks=%d" % [scenario, probe.tick])
		log_f.close()
		quit(0)
		return true
	elif frame > 4000:
		log_f.store_line("DIAG_MOVE TIMEOUT")
		log_f.close()
		quit(1)
		return true
	return false
