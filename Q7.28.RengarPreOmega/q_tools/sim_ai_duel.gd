extends SceneTree
## sim_ai_duel (Фаза B1+B2, adr_ai_phase_b.md) — детерминированные проверки
## паттернов, ритма, реактивного блока и отхода после стана.
##
## B1 (T1–T5, чистая логика, враг заглушён и отведён — бой не нужен):
##   T1 серии: pattern_length=3, switch_chance=1.0 → каждые 3 выбора одинаковы,
##      смены происходят; T2 тот же сид → та же последовательность (детерминизм);
##   T3 switch_chance=0.0 → направление не меняется; T4 ритм: кулдаун 0.4 с
##      взводится и истекает; T5 legacy: interval=0 → кулдауна нет.
## B2 (R1–R4, живой мозг + ядро; shell заглушён — враг СТОИТ на дистанции 3 м,
##     движение не мешает измерениям):
##   R1 блок с бюджетом: block_chance=1.0, reaction=200мс, guess=1.0 → сразу
##      после атаки игрока (attack_performed = честный сенсор) блока НЕТ
##      (бюджет), к 0.35 с блок АКТИВЕН и dir = BLOCK_RESPONSE[атака];
##   R2 block_chance=0 → блока нет вовсе (legacy);
##   R3 отход после стана: apply_stun(0.3), post_stun_retreat_time=0.8 →
##      после конца стана move_state=RETREAT, направление «от игрока»,
##      по истечении окна — снова CHASE;
##   R4 legacy: post_stun_retreat_time=0 → после стана БЕЗ принудительного
##      отхода (сразу обычные решения).
## Вызовы «приватных» _pick_direction/_schedule_next_attack — по прецеденту
## sim_telegraph (прямой вызов внутренних методов под контролем стенда).
## Лог: res://q_tools/sim_ai_duel_out.txt

var frame := 0
var log_f: FileAccess = null
var enemy: CharacterBody3D = null
var player: CharacterBody3D = null
var brain: Node = null
var ecc: Node = null
var pcc: Node = null
var passed := 0
var failed := 0
var seq_a: Array = []
var stage := "T"          # T -> R1a -> R1b -> R1c -> R2 -> R3 -> R4 -> END
var stage_t0 := 0.0
var done := false


func check(check_name: String, cond: bool) -> void:
	if cond:
		passed += 1
		log_f.store_line("PASS " + check_name)
	else:
		failed += 1
		log_f.store_line("FAIL " + check_name)


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


func _initialize() -> void:
	log_f = FileAccess.open("res://q_tools/sim_ai_duel_out.txt", FileAccess.WRITE)
	log_f.store_line("SIM_AI_DUEL (B1: паттерны+ритм; B2: блок с бюджетом, отход после стана)")


func _setup_scene() -> void:
	var scn := load("res://Основная_сцена.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	enemy = inst.get_node_or_null("EnemyCharacterBody3D") as CharacterBody3D
	player = inst.get_node_or_null("PLayerCharacterBody3D") as CharacterBody3D
	if enemy == null or player == null:
		log_f.store_line("DUEL FAIL nodes")
		log_f.close()
		quit(1)
	ecc = enemy.get_node("CombatComponent")
	pcc = player.get_node("CombatComponent")
	brain = enemy.get_node("AIBrainComponent")
	# Протокол: манекен глушим; врага глушим и отводим (T1–T5 — чистая логика).
	var dummy := inst.get_node_or_null("DummyMannequin")
	for n in [dummy, enemy]:
		if n != null:
			(n as Node).set_physics_process(false)
			(n as Node).set_process(false)
			for child_name in ["MovementShell", "AIIntentComponent", "AIBrainComponent"]:
				var mn: Node = (n as Node).get_node_or_null(child_name)
				if mn != null:
					mn.set_physics_process(false)
	enemy.global_position = Vector3(18.0, 1.0, 18.0)


func _make_profile(length: int, switch_chance: float, lo: float, hi: float) -> Resource:
	var prof = AIBrainProfile.new()
	prof.pattern_length = length
	prof.pattern_switch_chance = switch_chance
	prof.attack_interval_min = lo
	prof.attack_interval_max = hi
	return prof


func _reset_pattern() -> void:
	brain.set("_pattern_dir", "")
	brain.set("_pattern_left", 0)


func _pick_n(n: int) -> Array:
	var out := []
	for i in n:
		out.append(brain.call("_pick_direction"))
	return out


## B2-настройка: враг жив (мозг+ядро), без движения (shell заглушён), в 3 м от игрока.
func _enter_b2() -> void:
	enemy.global_position = player.global_position + Vector3(0.0, 0.0, 3.0)
	enemy.velocity = Vector3.ZERO
	enemy.set_physics_process(true)   # контроллер (только UI) — безвредно
	brain.set_physics_process(true)   # мозг жив
	# MovementShell и AIIntent остаются ЗАГЛУШЕНЫ: враг стоит на месте.


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_setup_scene()
	elif frame == 3:
		# ===== B1: T1–T3 (мгновенно) =====
		brain.profile = _make_profile(3, 1.0, 0.0, 0.0)
		brain.rng.seed = 12345
		_reset_pattern()
		seq_a = _pick_n(30)
		log_f.store_line("T1 последовательность: " + str(seq_a))
		var groups_ok := true
		for g in range(0, 30, 3):
			if not (seq_a[g] == seq_a[g + 1] and seq_a[g + 1] == seq_a[g + 2]):
				groups_ok = false
		check("T1 серии: каждые 3 подряд одинаковы (pattern_length=3)", groups_ok)
		var distinct := {}
		for g in range(0, 30, 3):
			distinct[seq_a[g]] = true
		check("T1 смены происходят: различных серий-направлений %d >= 2" % distinct.size(), distinct.size() >= 2)
		brain.rng.seed = 12345
		_reset_pattern()
		check("T2 воспроизводимость: сид 12345 → идентичная последовательность", seq_a == _pick_n(30))
		brain.profile = _make_profile(2, 0.0, 0.0, 0.0)
		brain.rng.seed = 777
		_reset_pattern()
		var seq_c := _pick_n(30)
		var all_same := true
		for d in seq_c:
			if d != seq_c[0]:
				all_same = false
		check("T3 switch_chance=0: все 30 выборов = %s" % str(seq_c[0]), all_same)
		# T4 — взводим ритм
		brain.profile = _make_profile(1, 1.0, 0.4, 0.4)
		brain.set("_next_attack_time", 0.0)
		brain.call("_schedule_next_attack")
		var cd: float = brain.call("get_attack_cooldown_left")
		check("T4 ритм: кулдаун после исхода ≈0.4с (получено %.3f)" % cd, cd > 0.3 and cd <= 0.45)
		stage = "T4wait"
		stage_t0 = _now()
	elif stage == "T4wait" and _now() - stage_t0 >= 0.65:
		check("T4 ритм: через ~0.65с кулдаун истёк", brain.call("get_attack_cooldown_left") == 0.0)
		brain.profile = _make_profile(1, 1.0, 0.0, 0.0)
		brain.set("_next_attack_time", 0.0)
		brain.call("_schedule_next_attack")
		check("T5 legacy: interval=0 → кулдаун 0 (бей сразу)", brain.call("get_attack_cooldown_left") == 0.0)
		# ===== переход к B2 =====
		_enter_b2()
		var p := _make_profile(1, 1.0, 0.0, 0.0)
		p.block_chance = 1.0
		p.reaction_ms = 200
		p.block_dir_guess_chance = 1.0
		brain.profile = p
		brain.rng.seed = 42
		stage = "R1setup"
		stage_t0 = _now()
	elif stage == "R1setup" and _now() - stage_t0 >= 0.3:
		# мозгу дали несколько тиков; атакуем игроком — perception увидит старт анимации
		pcc.perform_directional_attack("RIGHT", false)
		stage = "R1early"
		stage_t0 = _now()
	elif stage == "R1early" and _now() - stage_t0 >= 0.10:
		check("R1 бюджет реакции: через 0.10с блока ещё НЕТ (reaction_ms=200)",
			ecc.enemy_block_active == false)
		stage = "R1late"
	elif stage == "R1late" and _now() - stage_t0 >= 0.35:
		check("R1 блок активен к 0.35с (enemy_block_active=%s)" % str(ecc.enemy_block_active),
			ecc.enemy_block_active == true)
		check("R1 направление угадано: dir=%s (BLOCK_RESPONSE[RIGHT]=LEFT)" % str(ecc.enemy_block_dir),
			str(ecc.enemy_block_dir) == "LEFT")
		ecc.deactivate_enemy_block()
		stage = "R2setup"
		stage_t0 = _now()
	elif stage == "R2setup" and _now() - stage_t0 >= 0.2:
		var p2 := _make_profile(1, 1.0, 0.0, 0.0)
		p2.block_chance = 0.0
		brain.profile = p2
		pcc.cancel_attack("sim_reset")
		pcc.perform_directional_attack("LEFT", false)
		stage = "R2check"
		stage_t0 = _now()
	elif stage == "R2check" and _now() - stage_t0 >= 0.5:
		check("R2 block_chance=0: блока нет вовсе (enemy_block_active=%s)" % str(ecc.enemy_block_active),
			ecc.enemy_block_active == false)
		pcc.cancel_attack("sim_reset")
		# ===== R3: отход после стана =====
		var p3 := _make_profile(1, 1.0, 0.0, 0.0)
		p3.post_stun_retreat_time = 0.8
		brain.profile = p3
		enemy.global_position = player.global_position + Vector3(0.0, 0.0, 3.0)
		ecc.apply_stun(0.3)
		stage = "R3stun"
		stage_t0 = _now()
	elif stage == "R3stun" and _now() - stage_t0 >= 0.5:
		check("R3 после стана move_state=RETREAT (получено %s)" % str(brain.get("move_state")),
			str(brain.get("move_state")) == "RETREAT")
		var away := (enemy.global_position - player.global_position)
		away.y = 0.0
		var rd: Vector3 = brain.call("get_retreat_direction")
		check("R3 направление отхода — ОТ игрока (dot=%.2f)" % rd.dot(away.normalized()),
			rd.dot(away.normalized()) > 0.9)
		stage = "R3after"
	elif stage == "R3after" and _now() - stage_t0 >= 1.4:
		check("R3 окно отхода истекло → снова CHASE (получено %s)" % str(brain.get("move_state")),
			str(brain.get("move_state")) == "CHASE")
		# ===== R4: legacy без отхода =====
		var p4 := _make_profile(1, 1.0, 0.0, 0.0)
		p4.post_stun_retreat_time = 0.0
		brain.profile = p4
		ecc.apply_stun(0.3)
		stage = "R4"
		stage_t0 = _now()
	elif stage == "R4" and _now() - stage_t0 >= 0.55:
		var ms := str(brain.get("move_state"))
		check("R4 legacy (post_stun=0): после стана не RETREAT (получено %s)" % ms, ms != "RETREAT")
		log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
		log_f.close()
		done = true
		quit(0 if failed == 0 else 1)
		return true
	if frame > 3000:
		log_f.store_line("TIMEOUT stage=%s" % stage)
		log_f.close()
		quit(1)
		return true
	return false
