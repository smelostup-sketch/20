extends SceneTree
## Q7.14 приёмочный сим: смена аватара («тест курицы», ADR критерий 3).
## Runtime-подмена CreatureProfile игрока на куриный профиль и проверка:
##   1) скорость ходьбы = профильная (2.5), а не ренгаровская (6.0);
##   2) dash (double-tap W) ОТКАЗАН: is_dashing не поднимается, скорость < 3.5;
##   3) dodge (W+Q) ОТКАЗАН: is_dodging не поднимается;
##   4) прыжок = профильный jump_force (5.0) + нормальное приземление;
##   5) стелс в кусте НЕ включается (can_stealth=false);
##   6) возврат профиля Ренгара: dash снова работает (смена = данные, не код);
##   7) базовое settles: пол/скорость в покое.
## Изоляция — единый протокол: контроллеры+MovementShell+AIIntent врага/манекена
## глушатся на frame-1, игрок телепортируется на открытый угол (12, 1, 12).
## Лог: res://q_tools/sim_chicken_out.txt

const SPAWN_OPEN := Vector3(12.0, 1.0, 12.0)
const BUSH_CENTER := Vector3(0.0, 1.0, -5.0)

var frame := 0
var log_f: FileAccess = null
var probe: Node = null


class ChickenProbe:
	extends Node
	var log_f: FileAccess
	var player: CharacterBody3D
	var shell: Node
	var profile_rengar: Resource
	var profile_chicken: Resource
	var tick := 0
	var passed := 0
	var failed := 0
	var done := false
	# измерения фаз
	var walk_speeds: Array[float] = []
	var dash_max_speed := 0.0
	var dash_ever_active := false
	var dodge_max_speed := 0.0
	var dodge_ever_active := false
	var jump_vy_seen := 0.0
	var landed_after_jump := false
	var dash2_ever_active := false
	var dash2_max_speed := 0.0

	func _physics_process(_delta: float) -> void:
		tick += 1
		var hspeed := Vector2(player.velocity.x, player.velocity.z).length()

		# --- расписание (инжект ввода видит провайдер на СЛЕДУЮЩЕМ тике) ---
		if tick == 60:
			shell.profile = profile_chicken
			_key(KEY_W, true)
		elif tick == 150:
			_key(KEY_W, false)
		elif tick == 170:
			_key(KEY_W, true)   # double-tap: press..release..press в окне 0.25 с
		elif tick == 173:
			_key(KEY_W, false)
		elif tick == 176:
			_key(KEY_W, true)
		elif tick == 179:
			_key(KEY_W, false)
		elif tick == 200:
			_key(KEY_W, true)   # база для dodge
		elif tick == 202:
			_key(KEY_Q, true)   # dodge_left модификатор
		elif tick == 204:
			_key(KEY_Q, false)
		elif tick == 208:
			_key(KEY_W, false)
		elif tick == 240:
			_key(KEY_SPACE, true)
		elif tick == 242:
			_key(KEY_SPACE, false)
		elif tick == 330:
			player.global_position = BUSH_CENTER # вход в куст на «курином» профиле
		elif tick == 360:
			shell.profile = profile_rengar
			player.global_position = SPAWN_OPEN
		elif tick == 370:
			_key(KEY_W, true)   # double-tap на ренгаровском профиле
		elif tick == 373:
			_key(KEY_W, false)
		elif tick == 376:
			_key(KEY_W, true)
		elif tick == 380:
			_key(KEY_W, false)
		elif tick == 410:
			done = true

		# --- измерения ---
		if 120 <= tick and tick <= 148:
			walk_speeds.append(hspeed)
		if 176 <= tick and tick <= 198:
			dash_max_speed = maxf(dash_max_speed, hspeed)
			if shell.is_dashing:
				dash_ever_active = true
		if 202 <= tick and tick <= 230:
			dodge_max_speed = maxf(dodge_max_speed, hspeed)
			if shell.is_dodging:
				dodge_ever_active = true
		if 241 <= tick and tick <= 244:
			jump_vy_seen = maxf(jump_vy_seen, player.velocity.y)
		if tick > 250 and player.is_on_floor() and absf(player.velocity.y) < 0.5:
			landed_after_jump = true
		if 376 <= tick and tick <= 400:
			dash2_max_speed = maxf(dash2_max_speed, hspeed)
			if shell.is_dashing:
				dash2_ever_active = true

		# --- проверки по фазам ---
		if tick == 59:
			_check("settle: на полу, скорость ~0", player.is_on_floor() and hspeed < 0.05)
		elif tick == 149:
			var avg := 0.0
			for v in walk_speeds:
				avg += v
			avg /= maxf(walk_speeds.size(), 1.0)
			_check("куриная ходьба: средняя скорость 2.5±0.15 (получено %.3f)" % avg,
				absf(avg - 2.5) <= 0.15)
		elif tick == 199:
			_check("куриный dash ОТКАЗАН (is_dashing ни разу, max speed %.2f < 3.5)" % dash_max_speed,
				not dash_ever_active and dash_max_speed < 3.5)
		elif tick == 231:
			_check("куриный dodge ОТКАЗАН (is_dodging ни разу, max speed %.2f < 3.0)" % dodge_max_speed,
				not dodge_ever_active and dodge_max_speed < 3.0)
		elif tick == 245:
			_check("куриный прыжок: vy ≈ 5.0 (получено %.2f)" % jump_vy_seen,
				jump_vy_seen > 4.3 and jump_vy_seen < 5.6)
		elif tick == 320:
			_check("после прыжка приземлился", landed_after_jump)
		elif tick == 350:
			_check("куриный стелс в кусте НЕ включился (can_stealth=false)",
				shell.is_stealthed == false)
		elif tick == 400:
			_check("профиль Ренгара возвращён: dash работает (is_dashing=%s, max speed %.1f)" % [dash2_ever_active, dash2_max_speed],
				dash2_ever_active and dash2_max_speed > 10.0)

		if done:
			log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
			log_f.close()

	func _check(name: String, cond: bool) -> void:
		if cond:
			passed += 1
			log_f.store_line("PASS " + name)
		else:
			failed += 1
			log_f.store_line("FAIL " + name)

	func _key(k: Key, pressed: bool) -> void:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = pressed
		ev.echo = false
		Input.parse_input_event(ev)


func _initialize() -> void:
	log_f = FileAccess.open("res://q_tools/sim_chicken_out.txt", FileAccess.WRITE)
	log_f.store_line("SIM_CHICKEN (тест смены аватара, ADR Q7.14)")


func _setup_scene() -> void:
	var scn := load("res://Основная_сцена.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	var player := inst.get_node_or_null("PLayerCharacterBody3D") as CharacterBody3D
	if player == null:
		log_f.store_line("CHICKEN FAIL: нет игрока")
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
	player.global_position = SPAWN_OPEN
	player.velocity = Vector3.ZERO

	probe = ChickenProbe.new()
	probe.name = "QChickenProbe"
	probe.log_f = log_f
	probe.player = player
	probe.shell = player.get_node("MovementShell")
	probe.profile_rengar = load("res://profiles/RengarProfile.tres")
	probe.profile_chicken = load("res://profiles/ChickenProfile.tres")
	player.add_child(probe) # последний ребёнок — видит состояние после shell-тика
	log_f.store_line("SETUP ok shell=%s chicken=%s" % [probe.shell != null, probe.profile_chicken != null])


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_setup_scene()
	elif frame > 3 and probe != null and probe.done:
		quit(0 if probe.failed == 0 else 1)
		return true
	elif frame > 6000:
		log_f.store_line("TIMEOUT")
		log_f.close()
		quit(1)
		return true
	return false
