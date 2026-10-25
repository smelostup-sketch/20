extends SceneTree
## Сим врага (Q7.16, п.8A): НАСТОЯЩИЙ бой вместо «лезвия в 3 см».
## Прежняя версия держала игрока ПОД землёй на дистанции 3.03 м при гейте атаки
## 3.00 м — враг никогда не атаковал, и SUMMARY started=0 измерял совпадение
## зазора, а не логику. Теперь оба на земле в открытом углу: враг доходит до
## stop_distance (1.5) и реально атакует запиненного почти-бессмертного игрока
## (hp 10000, чтобы смерть не перезагрузила сцену).
## Проверяется контракт единого ядра (Q…_2):
##   1) started > 0 — враг реально атакует;
##   2) performed == started — каждое намерение доходит до исполнения;
##   3) restarts_lt1s == 0 — нет перезапусков-подмен атаки;
##   4) clip-подмен Attack->другой Attack нет;
##   5) урон врагу во время атаки (frame 500) не ломает контракт (п.3);
##   6) удары врага ДОСТАЮТ игрока (hp < 10000) — полная цепочка: намерение ->
##      ядро -> хитбокс -> урон (включая единую конвенцию фейсинга Q7.15);
##   7) бой остаётся на месте: финальный dist ∈ [1.0, 3.5].
## Лог: res://q_tools/sim_enemy_out.txt (ST каждые 20 кадров + EVT + PASS/FAIL + SUMMARY).

const PLAYER_POS := Vector3(12.0, 1.0, 8.0)
const ENEMY_POS := Vector3(12.0, 1.0, 10.5)
const DMG_FRAME := 500
const END_FRAME := 1500

var frame := 0
var enemy: CharacterBody3D = null
var player: CharacterBody3D = null
var log_f: FileAccess = null
var t0 := 0
var n_started := 0
var n_performed := 0
var last_performed_ms := -99999
var restarts := 0
var last_clip := ""
var clip_swaps := 0
var passed := 0
var failed := 0
var php0 := 0.0
var brain: Node = null


func check(check_name: String, cond: bool) -> void:
	if cond:
		passed += 1
		log_f.store_line("PASS " + check_name)
	else:
		failed += 1
		log_f.store_line("FAIL " + check_name)


func _initialize() -> void:
	log_f = FileAccess.open("res://q_tools/sim_enemy_out.txt", FileAccess.WRITE)


func _on_started(dir: String, _leap: bool) -> void:
	n_started += 1
	log_f.store_line("EVT t=%.2f attack_started dir=%s" % [(Time.get_ticks_msec() - t0) / 1000.0, dir])


func _on_performed(dir: String, _leap: bool) -> void:
	n_performed += 1
	var now := Time.get_ticks_msec()
	if now - last_performed_ms < 1000:
		restarts += 1
		log_f.store_line("EVT t=%.2f RESTART (<1s after prev perform) dir=%s" % [(Time.get_ticks_msec() - t0) / 1000.0, dir])
	last_performed_ms = now
	log_f.store_line("EVT t=%.2f attack_performed dir=%s" % [(Time.get_ticks_msec() - t0) / 1000.0, dir])


func _setup() -> void:
	var scn := load("res://Основная_сцена.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	enemy = inst.get_node_or_null("EnemyCharacterBody3D") as CharacterBody3D
	player = inst.get_node_or_null("PLayerCharacterBody3D") as CharacterBody3D
	if enemy == null or player == null:
		log_f.store_line("SIMENEMY FAIL nodes")
		log_f.close()
		quit(1)
	# Куст убираем (стелс не должен выключать бой), манекен глушим (протокол).
	var bush := inst.get_node_or_null("Bush")
	if bush != null:
		bush.global_position = Vector3(100.0, 0.0, 100.0)
	var dummy := inst.get_node_or_null("DummyMannequin")
	if dummy != null:
		(dummy as Node).set_physics_process(false)
		(dummy as Node).set_process(false)
		for child_name in ["MovementShell", "AIIntentComponent", "AIBrainComponent"]:
			var mn: Node = (dummy as Node).get_node_or_null(child_name)
			if mn != null:
				mn.set_physics_process(false)
	# Игрок: запинен, почти бессмертен. ВРАГ ЖИВ: контроллер + shell + intent.
	var phc := player.get_node("HealthComponent")
	phc.set("max_hp", 100000.0)
	phc.set("hp", 100000.0)
	php0 = float(phc.get("hp"))
	brain = enemy.get_node_or_null("AIBrainComponent")
	var cc := enemy.get_node("CombatComponent")
	cc.attack_started.connect(_on_started)
	cc.attack_performed.connect(_on_performed)
	t0 = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_setup()
	if frame == 2:
		# Открытый угол полигона (земля 40x40): оба на землю, dist = 2.5.
		player.global_position = PLAYER_POS
		player.velocity = Vector3.ZERO
		enemy.global_position = ENEMY_POS
		enemy.velocity = Vector3.ZERO
	if frame < 2:
		return false
	# Пин игрока: измеряем врага, а не дрейф от нокбэков.
	player.global_position = PLAYER_POS
	player.velocity = Vector3.ZERO

	var cc := enemy.get_node("CombatComponent")
	var vp := enemy.get_node("EnemyVisual/AnimationPlayer") as AnimationPlayer
	if frame == DMG_FRAME:
		if enemy.has_method("take_dmg"):
			enemy.take_dmg(5.0, player.global_position)
			log_f.store_line("EVT t=%.2f DAMAGE_TO_ENEMY (clip=%s state=%s started=%d)" % [
				(Time.get_ticks_msec() - t0) / 1000.0, str(vp.current_animation),
				str(cc.get("ai_state")), n_started])
	if frame > 2 and frame % 20 == 0 and frame <= END_FRAME:
		var clip := str(vp.current_animation)
		if clip.begins_with("Attack") and last_clip.begins_with("Attack") and clip != last_clip:
			clip_swaps += 1
			log_f.store_line("EVT t=%.2f CLIP_SWAP %s -> %s" % [(Time.get_ticks_msec() - t0) / 1000.0, last_clip, clip])
		last_clip = clip
		var util := enemy.get_node("EnemyUtilityAIComponent")
		var stc := player.get_node("MovementShell")
		log_f.store_line("ST t=%.2f state=%-8s can_atk=%d clip=%-11s pos=%.2f dist=%.2f stealth=%d dec=%s op=%d" % [
			(Time.get_ticks_msec() - t0) / 1000.0, str(cc.get("ai_state")),
			1 if cc.get("can_attack") else 0, clip, vp.current_animation_position,
			enemy.global_position.distance_to(player.global_position),
			1 if stc.get("is_stealthed") else 0, str(util.get_decision_name()),
			1 if util.is_operational() else 0])
	if frame == END_FRAME:
		var phc := player.get_node("HealthComponent")
		var php := float(phc.get("hp"))
		var dist := enemy.global_position.distance_to(player.global_position)
		check("враг реально атакует: started=%d > 0" % n_started, n_started > 0)
		check("каждое намерение исполнено: performed(%d) == started(%d)" % [n_performed, n_started], n_performed == n_started)
		check("перезапусков-подмен <1с нет: %d == 0" % restarts, restarts == 0)
		# Clip-переходы Attack->другой Attack легальны МЕЖДУ последовательными
		# атаками (не больше performed-1); настоящие подмены ловят проверки
		# performed==started и restarts<1s (перезапуск свинга = второй perform).
		check("clip-подмены в пределах легальных переходов: %d <= %d" % [clip_swaps, max(n_performed - 1, 0)],
			clip_swaps <= max(n_performed - 1, 0))
		check("удары врага достают игрока: hp %.0f < %.0f" % [php, php0], php < php0)
		check("бой на месте: финальный dist %.2f ∈ [1.0, 3.5]" % dist, dist >= 1.0 and dist <= 3.5)
		if brain != null:
			check("Фаза A: мозг ЖДЁТ ИСХОДЫ — intents_sent(%d)==started(%d), отказов ядром %d==0" % [
				brain.intents_sent, n_started, brain.intents_rejected],
				brain.intents_sent == n_started and brain.intents_rejected == 0)
			check("Фаза A: каждая атака закрыта исходом — outcomes(%d) >= started-1(%d)" % [
				brain.outcomes_received, n_started - 1],
				brain.outcomes_received >= n_started - 1)
		log_f.store_line("SUMMARY started=%d performed=%d restarts_lt1s=%d clip_swaps=%d passed=%d failed=%d" % [
			n_started, n_performed, restarts, clip_swaps, passed, failed])
		log_f.close()
		quit(0 if failed == 0 else 1)
		return true
	if frame > END_FRAME + 200:
		log_f.store_line("TIMEOUT")
		log_f.close()
		quit(1)
		return true
	return false
