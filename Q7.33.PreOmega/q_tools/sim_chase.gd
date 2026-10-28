extends SceneTree
## Q7.14 rev.2 — приёмочный сим ПОГОНИ ВРАГА (регнресс-контроль инверсии
## направления CHASE: враг убегал от игрока из-за конвенции «вперёд = −Z»
## в input-space при вражеском yaw=atan2(x,z), где +Z корпуса смотрит на игрока).
## Геометрия чистая: оба на земле, открытый угол полигона, куст далеко.
## Проверки:
##   1) враг СБЛИЖАЕТСЯ (dist падает от 7.5 минимум на 5 м);
##   2) направление скорости — НА игрока (dot > 0.9 почти все тики погони);
##   3) враг НЕ убегает (dist ни разу не вырос выше стартового + 0.1);
##   4) остановка у stop_distance: dist ∈ [1.2, 2.3], move_state == STOPPED;
##   5) фейсинг: +Z корпуса врага смотрит на игрока (dot > 0.9);
##   6) враг не проскакивает сквозь игрока (min dist ≥ 1.1).
## Лог: res://q_tools/sim_chase_out.txt

const ENEMY_SPAWN := Vector3(12.0, 1.0, 12.0)
const PLAYER_POS := Vector3(12.0, 1.0, 4.5)

var frame := 0
var log_f: FileAccess = null
var probe: Node = null


class ChaseProbe:
	extends Node
	var log_f: FileAccess
	var enemy: CharacterBody3D
	var enemy_brain: Node
	var player: CharacterBody3D
	var tick := 0
	var done := false
	var passed := 0
	var failed := 0
	var initial_dist := 0.0
	var min_dist := 999.0
	var max_dist := 0.0
	var align_ok := 0
	var align_total := 0

	func _physics_process(_delta: float) -> void:
		tick += 1
		var to_player := player.global_position - enemy.global_position
		to_player.y = 0.0
		var dist := to_player.length()
		if tick == 5:
			initial_dist = dist
		if tick > 5:
			min_dist = minf(min_dist, dist)
			max_dist = maxf(max_dist, dist)
		# направление скорости vs направление на игрока (только когда движется)
		var vel_h := Vector2(enemy.velocity.x, enemy.velocity.z)
		if tick > 5 and tick < 150 and vel_h.length() > 0.5 and dist > 0.05:
			align_total += 1
			var dot := vel_h.normalized().dot(Vector2(to_player.x, to_player.z).normalized())
			if dot > 0.9:
				align_ok += 1
		if tick % 20 == 0 and tick <= 160:
			log_f.store_line("T=%03d dist=%.3f vel=%.2f move_state=%s rotY=%.1f" % [
				tick, dist, vel_h.length(), str(enemy_brain.get("move_state")), rad_to_deg(enemy.rotation.y)])
		if tick == 60:
			_check("сближение: dist упал с %.2f до %.2f (≥2 м за 60 тиков)" % [initial_dist, dist],
				dist < initial_dist - 2.0)
		if tick == 150:
			_check("остановка у stop_distance: dist=%.2f ∈ [1.2, 2.3]" % dist, dist >= 1.2 and dist <= 2.3)
			_check("move_state == STOPPED (получено %s)" % str(enemy_brain.get("move_state")),
				str(enemy_brain.get("move_state")) == "STOPPED")
			var ratio := float(align_ok) / maxf(float(align_total), 1.0)
			_check("скорость направлена НА игрока: %.0f%% тиков (dot>0.9)" % (ratio * 100.0), ratio >= 0.9)
			_check("враг НЕ убегал: max dist %.2f ≤ старт %.2f + 0.1" % [max_dist, initial_dist],
				max_dist <= initial_dist + 0.1)
			_check("не проскочил сквозь игрока: min dist %.2f ≥ 1.1" % min_dist, min_dist >= 1.1)
			var fwd := -enemy.global_transform.basis.z # единая конвенция Q7.15: −Z к цели
			var flat := to_player.normalized()
			_check("фейсинг: -Z корпуса на игрока (dot=%.2f)" % fwd.dot(flat), fwd.dot(flat) > 0.9)
		if tick == 155:
			done = true
			log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
			log_f.close()

	func _check(cname: String, cond: bool) -> void:
		if cond:
			passed += 1
			log_f.store_line("PASS " + cname)
		else:
			failed += 1
			log_f.store_line("FAIL " + cname)


func _initialize() -> void:
	log_f = FileAccess.open("res://q_tools/sim_chase_out.txt", FileAccess.WRITE)
	log_f.store_line("SIM_CHASE (погоня врага, ревизия направления CHASE)")


func _setup_scene() -> void:
	var scn := load("res://Основная_сцена.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	var player := inst.get_node_or_null("PLayerCharacterBody3D") as CharacterBody3D
	var enemy := inst.get_node_or_null("EnemyCharacterBody3D") as CharacterBody3D
	var dummy := inst.get_node_or_null("DummyMannequin") as Node
	if player == null or enemy == null:
		log_f.store_line("CHASE FAIL nodes")
		log_f.close()
		quit(1)
	# Манекен глушим (протокол изоляции), враг ЖИВ: контроллер + shell + intent.
	if dummy != null:
		(dummy as Node).set_physics_process(false)
		(dummy as Node).set_process(false)
		var dshell: Node = (dummy as Node).get_node_or_null("MovementShell")
		if dshell != null:
			dshell.set_physics_process(false)
	# Чистая геометрия: оба на землю в открытый угол (куст в (0,·,−5) далеко).
	enemy.global_position = ENEMY_SPAWN
	enemy.velocity = Vector3.ZERO
	player.global_position = PLAYER_POS
	player.velocity = Vector3.ZERO

	probe = ChaseProbe.new()
	probe.name = "QChaseProbe"
	probe.log_f = log_f
	probe.enemy = enemy
	probe.enemy_brain = enemy.get_node("AIBrainComponent")
	probe.player = player
	enemy.add_child(probe) # последний ребёнок врага — видит состояние после shell-тика
	log_f.store_line("SETUP ok enemy=%s player=%s" % [enemy != null, player != null])


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
