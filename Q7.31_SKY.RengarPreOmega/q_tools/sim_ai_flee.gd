extends SceneTree
## sim_ai_flee (Фаза B4, adr_ai_phase_b.md §B4 ревизия 17.10.2026) —
## детерминированные проверки самосохранения: FLEE → HIDE (куст, стелс) →
## выход «когда игрока нет рядом» (БЕЗ таймеров — дист. проверка; вердикт
## заказчика «таймеры — зло в нашей игре») → GUARD (охранять манекен) →
## реарм FLEE при приближении угрозы; legacy (выключено) — без самосохранения;
## «уверенность в победе»: раненый, но УВЕРЕННЫЙ дерётся (нейтральный опыт
## Memory); потеря уверенности (атаки блокируют) → бежит.
## Q7.25: F3 — на посту ПАТРУЛИРУЕТ (вердикт «патрулировать рядом», фикс
## «зависает и стоит»); F7/F8 — ИСПУГ ОТ ЗАСАДЫ: урон от невидимого атакующего
## при здоровом hp → FLEE от источника удара; урон от видимого → без испуга.
## Q7.26: F9 — «вытолкнули из куста»: HIDE при утрате стелса НЕ стоит пассивно
## (наблюдение заказчика, −1 балл) — угроза видна и близко → снова FLEE (прочь
## от игрока, не обратно в куст — полуплоское правило); игрок ушёл → GUARD.
##
## Протокол изоляции (паттерн sim_ai_duel/sim_ai_bush): frame-1 — instantiate,
## манекен и враг заглушены; frame-3 — сим-профиль, расстановка, включение
## мозга/shell/intent. hp врага меняется ПОКЕМ переменной (health.set("hp", X))
## вместо take_dmg — без нокбэка/сигналов (прецедент поков: sim_ai_duel);
## Memory: persistence_enabled=false + reset (user:// не трогаем), записи
## record_enemy_attack_* — прямые вызовы (прецедент: _pick_direction).
## Фиксированный сид: brain.rng.seed = 20261017 (в B4 роллов нет — сид для
## единообразия стендов; детерминизм полный).
## Лог: res://q_tools/sim_ai_flee_out.txt

const SEED := 20261017

var frame := 0
var log_f: FileAccess = null
var enemy: CharacterBody3D = null
var player: CharacterBody3D = null
var dummy: Node3D = null
var brain: Node = null
var ecc: Node = null
var eshell: Node = null
var health: Node = null
var memory: Node = null
var prof: Resource = null

var passed := 0
var failed := 0
var stage := "PRE"
var stage_t0 := 0.0


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
	log_f = FileAccess.open("res://q_tools/sim_ai_flee_out.txt", FileAccess.WRITE)
	log_f.store_line("SIM_AI_FLEE (B4: самосохранение — FLEE/HIDE/GUARD, уверенность через Memory)")


func _make_profile() -> Resource:
	var p = AIBrainProfile.new()
	p.self_preservation_enabled = true
	p.flee_hp_threshold = 0.4
	p.flee_confidence_threshold = 0.4
	p.confidence_hp_weight = 1.0     # F1–F5: уверенность = чистый hp (изоляция движения)
	p.confidence_record_weight = 0.0
	p.flee_threat_range = 8.0
	p.flee_exit_distance = 12.0
	p.flee_speed_scale = 1.3
	p.guard_patrol_radius = 2.5
	p.guard_group = "dummy_enemy"
	p.guard_post_enabled = false       # пост «по умолчанию» tested в sim_ai_bush S10
	p.fear_on_ambush_damage = false    # включается в F7
	p.bush_search_enabled = false    # изоляция от B3 (поиск tested в sim_ai_bush)
	p.attack_interval_min = 0.0
	p.attack_interval_max = 0.0
	p.block_chance = 0.0
	p.post_stun_retreat_time = 0.0
	p.pattern_length = 1
	return p


func _setup_scene() -> void:
	var scn := load("res://Основная_сцена.tscn") as PackedScene
	var inst := scn.instantiate()
	root.add_child(inst)
	enemy = inst.get_node_or_null("EnemyCharacterBody3D") as CharacterBody3D
	player = inst.get_node_or_null("PLayerCharacterBody3D") as CharacterBody3D
	dummy = inst.get_node_or_null("DummyMannequin") as Node3D
	if enemy == null or player == null or dummy == null:
		log_f.store_line("FLEE FAIL nodes")
		log_f.close()
		quit(1)
	brain = enemy.get_node("AIBrainComponent")
	ecc = enemy.get_node("CombatComponent")
	eshell = enemy.get_node("MovementShell")
	health = enemy.get_node("HealthComponent")
	memory = enemy.get_node("EnemyMemoryComponent")
	memory.set("persistence_enabled", false)  # user:// не трогаем
	memory.call("reset_memory")
	# Протокол изоляции: манекен и враг глушатся до расстановки.
	for n in [dummy, enemy]:
		if n != null:
			(n as Node).set_physics_process(false)
			(n as Node).set_process(false)
			for child_name in ["MovementShell", "AIIntentComponent", "AIBrainComponent"]:
				var mn: Node = (n as Node).get_node_or_null(child_name)
				if mn != null:
					mn.set_physics_process(false)
	log_f.store_line("SETUP ok enemy=%s player=%s dummy=%s bush=%d" % [
		enemy != null, player != null, dummy != null,
		enemy.get_tree().get_nodes_in_group("bush").size()])


func _unmute_enemy() -> void:
	for child_name in ["MovementShell", "AIIntentComponent", "AIBrainComponent"]:
		var mn: Node = enemy.get_node_or_null(child_name)
		if mn != null:
			mn.set_physics_process(true)


func _tp_enemy(pos: Vector3) -> void:
	enemy.global_position = pos
	enemy.velocity = Vector3.ZERO


func _tp_player(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO


func _mode() -> String:
	return str(brain.call("get_survival_mode"))


func _move_state() -> String:
	return str(brain.get("move_state"))


func _enemy_stealthed() -> bool:
	return bool(eshell.get("is_stealthed"))


func _speed() -> float:
	return Vector2(enemy.velocity.x, enemy.velocity.z).length()


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_setup_scene()
		return false
	if frame == 3:
		prof = _make_profile()
		brain.profile = prof
		brain.rng.seed = SEED
		# Расстановка: враг между игроком и кустом (куст в полуплоске «от игрока»);
		# манекен (-3.5, 1, 5) — пост охраны; куст (0.07, ·, −5.19) — укрытие.
		_tp_enemy(Vector3(0.0, 1.0, 2.0))
		_tp_player(Vector3(0.0, 1.0, 6.0))
		health.set("hp", 100.0)
		_unmute_enemy()
		stage = "F1"
		stage_t0 = _now()
		return false
	var t := _now() - stage_t0

	match stage:
		"F1":
			if t < 0.05:
				health.set("hp", 30.0)   # ratio 0.3 < 0.4 → «сильно ранен», угроза видна (4 м)
			if _mode() == "FLEE" and _move_state() == "FLEE":
				check("F1 триггер: ранен + угроза видна → FLEE", true)
				stage = "F1v"
				stage_t0 = _now()
			elif t > 1.0:
				check("F1 триггер FLEE за 1с (mode=%s state=%s hp=%.0f)" % [_mode(), _move_state(), float(health.get("hp"))], false)
				stage = "ENDFAIL"
		"F1v":
			if t >= 0.5:
				check("F1 move_state=FLEE (получено %s)" % _move_state(), _move_state() == "FLEE")
				check("F1 скорость бегства |v|=%.2f > 3.3 (scale 1.3 × 3.0)" % _speed(), _speed() > 3.3)
				var away := (enemy.global_position - player.global_position)
				away.y = 0.0
				var v := Vector3(enemy.velocity.x, 0.0, enemy.velocity.z)
				var dot := 0.0
				if away.length() > 0.05 and v.length() > 0.05:
					dot = v.normalized().dot(away.normalized())
				check("F1 бежит ОТ игрока / к кусту (dot=%.2f > 0.6)" % dot, dot > 0.6)
				stage = "F2"
				stage_t0 = _now()
		"F2":
			# Враг добегает до куста → Area3D-стелс (ЕСТЕСТВЕННЫЙ) → HIDE.
			if _enemy_stealthed() and _mode() == "HIDE":
				check("F2 в кусте: is_stealthed=true (естественный Area3D-вход)", true)
				check("F2 режим HIDE (move_state=%s)" % _move_state(), _move_state() == "HIDE")
				stage = "F2v"
				stage_t0 = _now()
			elif t > 6.0:
				check("F2 HIDE за 6с (stealth=%s mode=%s dist_до_куста=%.1f)" % [
					str(_enemy_stealthed()), _mode(),
					enemy.global_position.distance_to(Vector3(0.073, 1.0, -5.187))], false)
				stage = "ENDFAIL"
		"F2v":
			if t >= 0.3:
				check("F2 затаился: |v|=%.2f < 0.3 (snap_stop)" % _speed(), _speed() < 0.3)
				stage = "F3"
				stage_t0 = _now()
		"F3":
			if t < 0.05:
				_tp_player(Vector3(0.0, 1.0, 18.0))   # dist ≈ 20 > 12 — «игрока нет рядом»
			# БЕЗ ТАЙМЕРОВ: выход мгновенный по факту дистанции (≤0.3 с = ~18 тиков).
			if _mode() == "GUARD" and not _enemy_stealthed():
				check("F3 выход без таймера: игрока нет рядом (20 м > 12) → GUARD за %.2f с" % t, t <= 0.3)
				check("F3 стелс снят при выходе (is_stealthed=false)", true)
				stage = "F3w"
				stage_t0 = _now()
			elif t > 1.0:
				check("F3 выход в GUARD за 1с (mode=%s stealth=%s)" % [_mode(), str(_enemy_stealthed())], false)
				stage = "ENDFAIL"
		"F3w":
			# Q7.25 (вердикт «патрулировать рядом»): на посту НЕ стоит — ходит
			# орбитой guard_patrol_radius. Условия вместе (урок границ тиков).
			if bool(brain.call("is_guard_at_post")) and _speed() > 0.5 \
					and enemy.global_position.distance_to(dummy.global_position) <= 4.0:
				check("F3 дошёл до поста: dist=%.2f ≤ 4.0 (патруль 2.5 + допуск)" %
					enemy.global_position.distance_to(dummy.global_position), true)
				check("F3 охраняет: move_state=%s, at_post=true" % _move_state(),
					_move_state() == "GUARD")
				check("F3 ПАТРУЛИРУЕТ, не стоит (фикс «зависает»): |v|=%.2f > 0.5" % _speed(),
					_speed() > 0.5)
				stage = "F4"
				stage_t0 = _now()
			elif t > 8.0:
				check("F3 дошёл до манекена за 8с (dist=%.1f mode=%s at_post=%s)" % [
					enemy.global_position.distance_to(dummy.global_position), _mode(),
					str(brain.call("is_guard_at_post"))], false)
				stage = "ENDFAIL"
		"F4":
			if t < 0.05:
				# Угроза подходит к посту (видима, ~2 м ≤ 8) — реарм самосохранения.
				_tp_player(Vector3(-1.5, 1.0, 5.5))
			if _mode() == "FLEE":
				check("F4 реарм: игрок подошёл к посту → снова FLEE", true)
				stage = "F4v"
				stage_t0 = _now()
			elif t > 1.0:
				check("F4 реарм FLEE за 1с (mode=%s)" % _mode(), false)
				stage = "ENDFAIL"
		"F4v":
			if t >= 0.4:
				check("F4 убегает: |v|=%.2f > 1.0" % _speed(), _speed() > 1.0)
				# F5: legacy — самосохранение ВЫКЛЮЧЕНО (раненый дерётся до конца).
				var p5: Resource = prof.duplicate(true)
				p5.self_preservation_enabled = false
				brain.profile = p5
				health.set("hp", 100.0)
				_tp_enemy(Vector3(12.0, 1.0, 12.0))
				_tp_player(Vector3(12.0, 1.0, 15.0))
				stage = "F5"
				stage_t0 = _now()
		"F5":
			if t < 0.05:
				health.set("hp", 30.0)   # ранен, угроза видна (3 м) — но выключено
			if t >= 0.7:
				check("F5 legacy (выключено): режим пуст (получено '%s')" % _mode(), _mode() == "")
				check("F5 legacy: move_state=%s — обычное решение, не FLEE/HIDE/GUARD" % _move_state(),
					not ["FLEE", "HIDE", "GUARD"].has(_move_state()))
				# F6a: уверенность от Memory: ранен, но НЕЙТРАЛЬНЫЙ опыт → уверен (0.5 ≥ 0.4) → дерётся.
				var p6: Resource = prof.duplicate(true)
				p6.self_preservation_enabled = true
				p6.confidence_hp_weight = 0.0
				p6.confidence_record_weight = 1.0
				brain.profile = p6
				memory.call("reset_memory")
				health.set("hp", 30.0)
				stage = "F6a"
				stage_t0 = _now()
		"F6a":
			if t >= 0.7:
				var conf: float = float(brain.call("_confidence"))
				check("F6a уверенность (нейтральный опыт) = %.2f ≈ 0.5" % conf, conf >= 0.45 and conf <= 0.55)
				check("F6a ранен, но УВЕРЕН → дерётся: режим '%s' пуст" % _mode(), _mode() == "")
				# F6b: игрок блокирует всё (6 из 6 UP) → уверенность падает → бежит.
				for i in 6:
					memory.call("record_enemy_attack_started", "UP")
					memory.call("record_enemy_attack_blocked", "UP")
				stage = "F6b"
				stage_t0 = _now()
		"F6b":
			if _mode() == "FLEE":
				var conf2: float = float(brain.call("_confidence"))
				check("F6b опыт Memory: всё блокируют → уверенность %.2f < 0.4 → FLEE" % conf2, conf2 < 0.4)
				# F7 (Q7.25): ИСПУГ ОТ ЗАСАДЫ — урон от НЕВИДИМОГО атакующего при
				# ЗДОРОВОМ hp → FLEE от источника удара (вердикт заказчика:
				# «не должно быть так, что я бью врага, а он бездействует»).
				brain.set("_survival_mode", "")   # сброс режима (poke — изоляция F7)
				var p7: Resource = prof.duplicate(true)
				p7.fear_on_ambush_damage = true
				p7.confidence_hp_weight = 1.0    # здоров → уверен: сработает ТОЛЬКО испуг
				p7.confidence_record_weight = 0.0
				brain.profile = p7
				health.set("hp", 100.0)
				_tp_enemy(Vector3(0.0, 1.0, 2.0))
				_tp_player(Vector3(0.0, 1.0, -5.0))   # в куст → естественный стелс
				stage = "F7set"
				stage_t0 = _now()
			elif t > 1.5:
				check("F6b FLEE после потери уверенности за 1.5с (mode=%s conf=%.2f)" % [
					_mode(), float(brain.call("_confidence"))], false)
				stage = "ENDFAIL"
		"F7set":
			if bool(player.get_node("MovementShell").get("is_stealthed")) or t > 0.6:
				if not bool(player.get_node("MovementShell").get("is_stealthed")):
					player.get_node("MovementShell").set_stealthed(true)
					log_f.store_line("НОРМАЛИЗАЦИЯ F7: стелс игрока установлен стендом")
				health.call("take_dmg", 5.0, player.global_position)  # урон «из засады»
				stage = "F7poll"
				stage_t0 = _now()
		"F7poll":
			if _mode() == "FLEE" and _move_state() == "FLEE":
				check("F7 испуг: урон от НЕВИДИМОГО при hp=95/100 → FLEE (mode=%s)" % _mode(), true)
				stage = "F7v"
				stage_t0 = _now()
			elif t > 0.6:
				check("F7 испуг → FLEE за 0.6с (mode=%s state=%s)" % [_mode(), _move_state()], false)
				stage = "ENDFAIL"
		"F7v":
			# Ждём окончания recovery собственной атаки (F6a мог атаковать):
			# «атакующий стоит» — единая семантика, испуг-бегство стартует после.
			if _speed() > 2.0:
				# Источник удара (0,·,−5) позади → бежит прочь (+Z); куст ПЕРЕД
				# источником — полуплоское правило НЕ ведёт в куст (dot < 0).
				var v := Vector3(enemy.velocity.x, 0.0, enemy.velocity.z)
				var dot := 0.0
				if v.length() > 0.3:
					dot = v.normalized().dot(Vector3(0.0, 0.0, 1.0))
				check("F7 бежит ОТ источника удара (+Z): dot=%.2f > 0.5, |v|=%.2f" % [dot, _speed()],
					dot > 0.5 and _speed() > 2.0)
				stage = "F7hold"
				stage_t0 = _now()
			elif t > 4.0:
				check("F7 бегство стартовало за 4с (|v|=%.2f rec=%s)" % [
					_speed(), str(ecc.get("is_recovery"))], false)
				stage = "ENDFAIL"
		"F7hold":
			if t >= 0.6:
				check("F7 испуг держит бегство при ЗДОРОВОМ hp (без таймеров): mode=%s" % _mode(),
					_mode() == "FLEE")
				# F8: атакующий СТАЛ ВИДИМ — испуг снимается, здоровый враг в бою.
				stage = "F8a"
				stage_t0 = _now()
		"F8a":
			# Видимость должна УСТАНОВИТЬСЯ до урона (perception тикает между
			# кадрами — урон в тот же кадр прочёл бы устаревшую невидимость).
			if t < 0.05:
				player.get_node("MovementShell").set_stealthed(false)
				_tp_player(Vector3(0.0, 1.0, 9.0))
			if t >= 0.4:
				check("F8 атакующий стал видим → испуг снят, здоров → mode='' (получено '%s')" % _mode(),
					_mode() == "")
				health.call("take_dmg", 5.0, player.global_position)  # урон от ВИДИМОГО
				stage = "F8b"
				stage_t0 = _now()
		"F8b":
			if t >= 0.5:
				check("F8 урон от ВИДИМОГО: испуга нет (mode='%s')" % _mode(), _mode() == "")
				check("F8 move_state=%s — обычные решения, не FLEE/HIDE/GUARD" % _move_state(),
					not ["FLEE", "HIDE", "GUARD"].has(_move_state()))
				# F9 (Q7.26): «вытолкнули из куста» — враг НЕ стоит пассивно.
				# Снова загоняем в HIDE (hp 30 < 0.4, угроза видна), затем
				# телепорт наружу с ПРОТИВОПОЛОЖНОЙ от игрока стороны (иначе
				# полуплоское правило сразу вернуло бы его в куст).
				health.set("hp", 30.0)
				_tp_enemy(Vector3(0.0, 1.0, 2.0))
				_tp_player(Vector3(0.0, 1.0, 6.0))
				stage = "F9hide"
				stage_t0 = _now()
		"F9hide":
			if _mode() == "HIDE" and _enemy_stealthed():
				stage = "F9push"
				stage_t0 = _now()
			elif t > 6.0:
				check("F9 повторно вошёл в HIDE за 6с (mode=%s stealth=%s)" % [
					_mode(), str(_enemy_stealthed())], false)
				stage = "ENDFAIL"
		"F9push":
			# «Выталкивание»: враг наружу (северная сторона, z=-1.0 — вне бокса
			# куста z≤-2.187), игрок — южнее куста (0,·,-8.5), виден (7.5 м ≤ 8).
			if t < 0.05:
				_tp_enemy(Vector3(0.0, 1.0, -1.0))
				_tp_player(Vector3(0.0, 1.0, -8.5))
			if not _enemy_stealthed() or t > 0.6:
				if _enemy_stealthed():
					eshell.set_stealthed(false)
					log_f.store_line("НОРМАЛИЗАЦИЯ F9: стелс снят стендом (body_exited не сработал за 0.6с)")
				stage = "F9react"
				stage_t0 = _now()
		"F9react":
			if _mode() == "FLEE":
				check("F9 вытолкнут из куста: НЕ стоит пассивно — стелс утрачен → снова FLEE", true)
				stage = "F9v"
				stage_t0 = _now()
			elif _mode() != "HIDE" and t > 0.2:
				# Вышел из HIDE в другое (GUARD) — тоже не пассивен, но ждали FLEE
				# (угроза видна в 7.5 м ≤ flee_threat_range 8.0).
				check("F9 после выталкивания FLEE (получено mode=%s)" % _mode(), false)
				stage = "ENDFAIL"
			elif t > 2.0:
				check("F9 реакция на утрату стелса за 2с (mode=%s stealth=%s)" % [
					_mode(), str(_enemy_stealthed())], false)
				stage = "ENDFAIL"
		"F9v":
			if t >= 0.5:
				var v := Vector3(enemy.velocity.x, 0.0, enemy.velocity.z)
				var dot := 0.0
				if v.length() > 0.3:
					dot = v.normalized().dot(Vector3(0.0, 0.0, 1.0))  # прочь от игрока = +Z
				check("F9 бежит прочь от игрока, не обратно в куст: dot=%.2f > 0.5, |v|=%.2f > 2" % [dot, _speed()],
					dot > 0.5 and _speed() > 2.0)
				check("F9 стелс утрачен окончательно: is_stealthed=%s" % str(_enemy_stealthed()),
					not _enemy_stealthed())
				_tp_player(Vector3(0.0, 1.0, 18.0))   # игрок уходит далеко (>12)
				stage = "F9b"
				stage_t0 = _now()
		"F9b":
			if _mode() == "GUARD":
				check("F9 игрок ушёл далеко → FLEE→GUARD (к посту)", true)
				check("F9 дисциплина ядра за весь прогон: intents_rejected=%d == 0" %
					int(brain.get("intents_rejected")), int(brain.get("intents_rejected")) == 0)
				log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
				log_f.close()
				quit(0 if failed == 0 else 1)
				return true
			elif t > 3.0:
				check("F9 GUARD после ухода игрока за 3с (mode=%s)" % _mode(), false)
				stage = "ENDFAIL"
	if stage == "ENDFAIL":
		log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
		log_f.close()
		quit(1)
		return true
	if frame > 6000:
		log_f.store_line("TIMEOUT stage=%s mode=%s state=%s" % [stage, _mode(), _move_state()])
		log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
		log_f.close()
		quit(1)
		return true
	return false
