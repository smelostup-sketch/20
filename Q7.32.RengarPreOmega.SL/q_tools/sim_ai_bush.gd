extends SceneTree
## sim_ai_bush (Фаза B3, adr_ai_phase_b.md §B3) — детерминированные проверки
## поиска потерянного игрока. Фиксированный сид: brain.rng.seed = 20261016.
##
## Сценарий (S1–S8):
##   S1 игрок виден → CHASE (обычные решения, поиск не мешает);
##   S2 игрок ВХОДИТ В КУСТ (реальный Area3D-вход; fallback-нормализация
##      set_stealthed по прецеденту sim_leap — с обязательной отметкой в логе)
##      → perception: player_visible=false, last_seen ≈ точка входа (ЧЕСТНО:
##      последняя ВИДИМАЯ позиция) → мозг: INVESTIGATE, куст привязан,
##      скорость направлена к last_seen;
##   S3 прибыл → SEARCH: орбита вокруг куста — накопленный угол ≥ 1.0 рад
##      за 2.5 с, радиус сходится к patrol_radius ± 1.0 (замер ORBIT_GAIN);
##   S4 слепой удар (chance=1.0, interval=0.3, range=3.2 < орбиты — форсит
##      ПОДХОД к краю): фаза BLIND_STRIKE → attack_performed ПОКА ИГРОК В
##      СТРЕЛСЕ (vel≈0 — «атакующий стоит», фейсинг на центр куста dot>0.7,
##      dir валиден) → awaiting_outcome → исход → возврат в SEARCH;
##      дисциплина: intents_rejected == 0 (решение ждёт исход);
##   S5 search-дедлайн (poke _search_until — прецедент sim_ai_duel) → IDLE, фаза "";
##   S6 игрок ВЫХОДИТ из куста → player_visible=true, поиск окончен,
##      обычные решения (CHASE/STOPPED);
##   S7 legacy: bush_search_enabled=false → потерял → IDLE (без поиска);
##   S8 сид-роллы ручек: ambush_chance=1.0 → AMBUSH_WAIT (holding, фейсинг на
##      куст); ambush_chance=0.0 → SEARCH; детерминизм _pick_blind_direction
##      (тот же сид → то же направление; прецедент: _pick_direction в sim_ai_duel);
##   S9 (Q7.23) вход в куст У УГЛА бокса: привязка по «точка-до-объёма» (старый
##      круговой тест от центра ломался на углах: 4.62 > 3.65) → куст привязан,
##      центр орбиты = центр куста, радиус ≥ r_куста+0.5 («за основу берётся
##      территория куста» — вердикт заказчика 17.10.2026);
##   S9b честный фейсинг: IDLE при скрытом игроке → intent.has_yaw=false
##      (корпус не следит за невидимым игроком сквозь карту);
##   S10 (Q7.25) пост по умолчанию: guard_post_enabled → после поиска GUARD
##      у манекена + ОРБИТАЛЬНЫЙ ПАТРУЛЬ рядом (угол ≥0.5 рад, радиус ∈
##      [1.5, 5.0], в движении |v|>0.5 — фикс «зависает и стоит»).
##
## Протокол изоляции (паттерн sim_ai_duel): frame-1 — instantiate, манекен и
## враг ЗАГЛУШЕНЫ (включая мозг — чтобы Дуэлянт сцены не ударил игрока на
## спавне до расстановки); frame-3 — сим-профиль, сид, расстановка, включение
## мозга/shell/intent. Perception жив с frame-1 (копит «видел игрока» — нужно
## для честного lost-перехода). Роулы основного потока на chance 0.0/1.0 —
## исход не зависит от значений rng (детерминизм без хрупкости).
## Лог: res://q_tools/sim_ai_bush_out.txt

const SEED := 20261016

var frame := 0
var log_f: FileAccess = null
var enemy: CharacterBody3D = null
var player: CharacterBody3D = null
var brain: Node = null
var ecc: Node = null
var perception: Node = null
var pshell: Node = null
var probe: Node = null
var prof: Resource = null
var dummy: Node3D = null

var passed := 0
var failed := 0
var stage := "PRE"   # инертная до frame-3 (иначе t от stage_t0=0 сработала бы раньше расстановки)
var stage_t0 := 0.0
var attack_count := 0
var stealthed_at_attack := false
var vel_at_attack := 0.0
var facing_dot_at_attack := 0.0
var blind_dir_at_attack := ""
var outcomes_at_s4 := 0
var stealth_entry_natural := true
var stealth_exit_natural := true
var _pending_stealth := 0   # 0 — нет, 1 — ждём вход в стелс, -1 — ждём выход
var _pending_t0 := 0.0
var _s5_poked := false


class OrbitProbe:
	extends Node
	## Накопитель угла орбиты вокруг центра (физические тики — честная мера
	## «кружит», а не «стоял в двух точках»).
	var active := false
	var center := Vector3.ZERO
	var swept := 0.0
	var last_r := 0.0
	var _prev_angle := 0.0
	var _has_prev := false

	func reset() -> void:
		active = true
		swept = 0.0
		last_r = 0.0
		_has_prev = false

	func _physics_process(_delta: float) -> void:
		if not active:
			return
		var e := get_parent() as CharacterBody3D
		if e == null:
			return
		var rel := e.global_position - center
		rel.y = 0.0
		last_r = rel.length()
		if last_r < 0.01:
			return
		var ang := atan2(rel.z, rel.x)
		if _has_prev:
			var da := ang - _prev_angle
			while da > PI:
				da -= TAU
			while da < -PI:
				da += TAU
			swept += absf(da)
		_prev_angle = ang
		_has_prev = true


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
	log_f = FileAccess.open("res://q_tools/sim_ai_bush_out.txt", FileAccess.WRITE)
	log_f.store_line("SIM_AI_BUSH (B3: поиск потерянного игрока — куст, орбита, слепой удар)")


func _make_search_profile() -> Resource:
	var p = AIBrainProfile.new()
	p.bush_search_enabled = true
	p.investigate_arrive_radius = 1.5
	p.ambush_chance = 0.0          # основной поток: всегда SEARCH (ролл S8 отдельно)
	p.ambush_wait_time = 2.0
	p.patrol_radius = 4.0
	p.search_time = 15.0           # естественный таймаут вне окон; S5 — poke дедлайна
	p.blind_strike_chance = 0.0    # включается в S4
	p.blind_strike_interval = 0.3
	p.blind_strike_range = 3.2     # < радиуса орбиты 4.0 — форсит подход к краю (S4)
	p.search_speed_scale = 1.0
	p.attack_interval_min = 0.0    # ритм-паузы выключены (темп стенда)
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
	if enemy == null or player == null:
		log_f.store_line("BUSH FAIL nodes")
		log_f.close()
		quit(1)
	dummy = inst.get_node_or_null("DummyMannequin") as Node3D
	ecc = enemy.get_node("CombatComponent")
	brain = enemy.get_node("AIBrainComponent")
	perception = enemy.get_node("EnemyPerceptionComponent")
	pshell = player.get_node("MovementShell")
	# Протокол изоляции: манекен и враг глушатся до расстановки (мозг врага —
	# тоже: профиль сцены Дуэлянт (поиск включён) — до спавна-боя не дойдёт,
	# но гарантируем нулевой фон намерений).
	var dummy := inst.get_node_or_null("DummyMannequin")
	for n in [dummy, enemy]:
		if n != null:
			(n as Node).set_physics_process(false)
			(n as Node).set_process(false)
			for child_name in ["MovementShell", "AIIntentComponent", "AIBrainComponent"]:
				var mn: Node = (n as Node).get_node_or_null(child_name)
				if mn != null:
					mn.set_physics_process(false)
	# Perception врага остаётся ЖИВ (копит видимость игрока на спавне —
	# _ever_visible нужен для честного lost-перехода после телепортов).
	ecc.attack_performed.connect(_on_enemy_attack_performed)
	probe = OrbitProbe.new()
	probe.name = "QBushProbe"
	enemy.add_child(probe)
	log_f.store_line("SETUP ok enemy=%s player=%s bush_in_group=%d" % [
		enemy != null, player != null, enemy.get_tree().get_nodes_in_group("bush").size()])


func _unmute_enemy() -> void:
	enemy.set_physics_process(false)  # контроллер (лейблы) — оставляем выключенным
	for child_name in ["MovementShell", "AIIntentComponent", "AIBrainComponent"]:
		var mn: Node = enemy.get_node_or_null(child_name)
		if mn != null:
			mn.set_physics_process(true)


func _on_enemy_attack_performed(direction: String, _is_leap: bool) -> void:
	attack_count += 1
	blind_dir_at_attack = direction
	stealthed_at_attack = bool(pshell.get("is_stealthed"))
	vel_at_attack = Vector2(enemy.velocity.x, enemy.velocity.z).length()
	var c: Vector3 = brain.get("_bush_center")
	var to_bush := c - enemy.global_position
	to_bush.y = 0.0
	var fwd := -enemy.global_transform.basis.z
	fwd.y = 0.0
	facing_dot_at_attack = 0.0
	if to_bush.length() > 0.01 and fwd.length() > 0.01:
		facing_dot_at_attack = fwd.normalized().dot(to_bush.normalized())


func _tp_player(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO


func _tp_enemy(pos: Vector3) -> void:
	enemy.global_position = pos
	enemy.velocity = Vector3.ZERO


## Ожидание стелс-перехода (реальный вход/выход Area3D); fallback-нормализация
## по прецеденту sim_leap — с отметкой в логе (стенд честен о способе).
func _request_stealth(value: bool) -> void:
	_pending_stealth = 1 if value else -1
	_pending_t0 = _now()


func _stealth_ready() -> bool:
	## true, когда ожидаемый стелс-факт достигнут (или нормализован).
	var current := bool(pshell.get("is_stealthed"))
	if _pending_stealth == 1 and current:
		_pending_stealth = 0
		return true
	if _pending_stealth == -1 and not current:
		_pending_stealth = 0
		return true
	if _pending_stealth != 0 and _now() - _pending_t0 > 0.6:
		pshell.set_stealthed(_pending_stealth == 1)
		if _pending_stealth == 1:
			stealth_entry_natural = false
			log_f.store_line("НОРМАЛИЗАЦИЯ стелс-входа: set_stealthed(true) (Area3D не сработал за 0.6с)")
		else:
			stealth_exit_natural = false
			log_f.store_line("НОРМАЛИЗАЦИЯ стелс-выхода: set_stealthed(false)")
		_pending_stealth = 0
		return true
	return _pending_stealth == 0


func _phase() -> String:
	return str(brain.call("get_search_phase"))


func _move_state() -> String:
	return str(brain.get("move_state"))


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_setup_scene()
		return false
	if frame == 3:
		# Расстановка S1 + сим-профиль + сид; враг включается.
		prof = _make_search_profile()
		brain.profile = prof
		brain.rng.seed = SEED
		_tp_enemy(Vector3(12.0, 1.0, 16.0))
		_tp_player(Vector3(12.0, 1.0, 12.0))
		_unmute_enemy()
		stage = "S1"
		stage_t0 = _now()
		return false
	var t := _now() - stage_t0

	match stage:
		"S1":
			if t >= 0.6:
				check("S1 игрок виден (perception.player_visible)", bool(perception.get("player_visible")))
				check("S1 move_state=CHASE (получено %s)" % _move_state(), _move_state() == "CHASE")
				# S2: расстановка у куста; игрок виден в точке входа (0, 1, -2).
				_tp_enemy(Vector3(0.0, 1.0, 1.5))
				_tp_player(Vector3(0.0, 1.0, -1.8))
				stage = "S2vis"
				stage_t0 = _now()
		"S2vis":
			if t >= 0.35:
				var ls: Vector3 = perception.get("last_seen_position")
				var flat_diff := Vector2(ls.x - 0.0, ls.z - (-1.8)).length()
				check("S2 last_seen = точка входа (0,-1.8): отклонение %.3f ≤ 0.15" % flat_diff, flat_diff <= 0.15)
				_tp_player(Vector3(0.0, 1.0, -5.0))   # в куст (центр)
				_request_stealth(true)
				stage = "S2in"
				stage_t0 = _now()
		"S2in":
			if _stealth_ready():
				stage = "S2lost"
				stage_t0 = _now()
		"S2lost":
			# Ждём INVESTIGATE и разгон (скорость > 1 м/с) — замер направления честный.
			# Фаза и move_state сверяются ВМЕСТЕ: сигнал lost приходит из perception
			# (узел позже мозга) — move_state догоняет фазу на следующем тике (норма).
			if _phase() == "INVESTIGATE" and _move_state() == "INVESTIGATE" \
					and enemy.velocity.length() > 1.0:
				check("S2 стелс: player_visible=false", not bool(perception.get("player_visible")))
				check("S2 move_state=INVESTIGATE (получено %s)" % _move_state(), _move_state() == "INVESTIGATE")
				check("S2 куст привязан к last_seen (get_linked_bush != null)", brain.call("get_linked_bush") != null)
				var ls2: Vector3 = perception.get("last_seen_position")
				var to_ls := ls2 - enemy.global_position
				to_ls.y = 0.0
				var v := Vector3(enemy.velocity.x, 0.0, enemy.velocity.z)
				var dot := 0.0
				if to_ls.length() > 0.05 and v.length() > 0.05:
					dot = v.normalized().dot(to_ls.normalized())
				check("S2 скорость направлена к last_seen (dot=%.2f)" % dot, dot > 0.7)
				stage = "S3poll"
				stage_t0 = _now()
			elif t > 2.0:
				check("S2 INVESTIGATE за 2с (фаза=%s, v=%.2f)" % [_phase(), enemy.velocity.length()], false)
				stage = "ENDFAIL"
		"S3poll":
			if _phase() == "SEARCH":
				var c: Vector3 = brain.get("_bush_center")
				probe.center = c
				probe.reset()
				stage = "S3obs"
				stage_t0 = _now()
			elif t > 4.0:
				check("S3 переход в SEARCH за 4с (фаза=%s)" % _phase(), false)
				stage = "ENDFAIL"
		"S3obs":
			if t >= 2.5:
				probe.active = false
				check("S3 орбита: накопленный угол %.2f рад ≥ 1.0 за 2.5с" % probe.swept, probe.swept >= 1.0)
				check("S3 радиус орбиты %.2f ∈ [3.0, 5.0] (patrol 4.0 ± 1.0)" % probe.last_r,
					probe.last_r >= 3.0 and probe.last_r <= 5.0)
				check("S3 move_state=SEARCH (получено %s)" % _move_state(), _move_state() == "SEARCH")
				stage = "S4setup"
				stage_t0 = _now()
		"S4setup":
			prof.blind_strike_chance = 1.0
			brain.set("_next_blind_roll", _now())   # форс ролла (poke — прецедент sim_ai_duel)
			outcomes_at_s4 = int(brain.get("outcomes_received"))
			stage = "S4poll"
			stage_t0 = _now()
		"S4poll":
			if _phase() == "BLIND_STRIKE" and _move_state() == "BLIND_STRIKE":
				check("S4 фаза BLIND_STRIKE (move_state=%s)" % _move_state(), _move_state() == "BLIND_STRIKE")
				stage = "S4attack"
				stage_t0 = _now()
			elif t > 2.5:
				check("S4 BLIND_STRIKE за 2.5с (фаза=%s)" % _phase(), false)
				stage = "ENDFAIL"
		"S4attack":
			if attack_count > 0:
				check("S4 удар состоялся (attack_performed, dir=%s)" % blind_dir_at_attack,
					["UP", "LEFT", "RIGHT"].has(blind_dir_at_attack))
				check("S4 игрок в это время СКРЫТ (is_stealthed=%s)" % str(stealthed_at_attack), stealthed_at_attack)
				check("S4 атакующий стоит: |v|=%.2f < 0.6" % vel_at_attack, vel_at_attack < 0.6)
				check("S4 фейсинг на центр куста (dot=%.2f > 0.7)" % facing_dot_at_attack, facing_dot_at_attack > 0.7)
				check("S4 решение ждёт исход: awaiting_outcome=true", bool(brain.get("awaiting_outcome")))
				check("S4 отказов ядра нет: intents_rejected=%d == 0" % int(brain.get("intents_rejected")),
					int(brain.get("intents_rejected")) == 0)
				stage = "S4outcome"
				stage_t0 = _now()
			elif t > 5.0:
				check("S4 удар вслепую за 5с (attack_count=%d)" % attack_count, false)
				stage = "ENDFAIL"
		"S4outcome":
			if _phase() == "SEARCH" and not bool(brain.get("awaiting_outcome")):
				check("S4 исход получен → возврат в SEARCH (outcomes +%d)" % (
					int(brain.get("outcomes_received")) - outcomes_at_s4),
					int(brain.get("outcomes_received")) > outcomes_at_s4)
				stage = "S5"
				stage_t0 = _now()
			elif t > 6.0:
				check("S4 исход слепого удара за 6с (фаза=%s awaiting=%s)" % [
					_phase(), str(brain.get("awaiting_outcome"))], false)
				stage = "ENDFAIL"
		"S5":
			if not _s5_poked:
				_s5_poked = true
				prof.blind_strike_chance = 0.0   # второй удар не должен мешать таймауту
				brain.set("_search_until", _now() + 0.3)   # poke дедлайна (прецедент sim_ai_duel)
				stage_t0 = _now()
			if _now() - stage_t0 >= 0.7:
				check("S5 таймаут поиска → move_state=IDLE (получено %s)" % _move_state(), _move_state() == "IDLE")
				check("S5 фаза поиска пуста (получено '%s')" % _phase(), _phase() == "")
				# S6: игрок выходит из куста в поле зрения; враг отводится для дистанции.
				_tp_enemy(Vector3(0.0, 1.0, 0.5))
				_tp_player(Vector3(0.0, 1.0, -1.8))       # вне бокса куста: зазор 0.199 м (z > -2.187 + 0.188 полкорпуса)
				_request_stealth(false)
				stage = "S6out"
				stage_t0 = _now()
		"S6out":
			if _stealth_ready():
				stage = "S6check"
				stage_t0 = _now()
		"S6check":
			if t >= 0.35:
				check("S6 игрок снова виден (player_visible)", bool(perception.get("player_visible")))
				check("S6 поиск окончен: фаза '' (получено '%s')" % _phase(), _phase() == "")
				check("S6 обычные решения: move_state=%s ∈ {CHASE, STOPPED}" % _move_state(),
					_move_state() == "CHASE" or _move_state() == "STOPPED")
				# S7: legacy — поиск выключен. Враг отводится: за окно стелс-входа
				# (до 0.6с нормализации) он не должен дойти до игрока и начать бой.
				var prof2: Resource = prof.duplicate(true)
				prof2.bush_search_enabled = false
				brain.profile = prof2
				_tp_enemy(Vector3(0.0, 1.0, 0.5))
				_tp_player(Vector3(0.0, 1.0, -5.0))       # снова в куст
				_request_stealth(true)
				stage = "S7in"
				stage_t0 = _now()
		"S7in":
			if _stealth_ready():
				stage = "S7check"
				stage_t0 = _now()
		"S7check":
			# Поллинг: если враг успел начать атаку ДО стелса (видимое окно),
			# legacy-порядок recovery→STOPED легитимен — ждём окончания recovery.
			if _move_state() == "IDLE" or t > 3.5:
				check("S7 legacy (поиск выключен): move_state=IDLE (получено %s)" % _move_state(),
					_move_state() == "IDLE")
				check("S7 legacy: фаза поиска пуста ('%s')" % _phase(), _phase() == "")
				# S8a: ambush_chance=1.0 → после прибытия AMBUSH_WAIT.
				var prof3: Resource = prof.duplicate(true)
				prof3.bush_search_enabled = true
				prof3.ambush_chance = 1.0
				prof3.blind_strike_chance = 0.0
				brain.profile = prof3
				brain.rng.seed = SEED
				_tp_enemy(Vector3(0.0, 1.0, 4.0))
				_tp_player(Vector3(0.0, 1.0, -1.8))
				_request_stealth(false)
				stage = "S8a_exit"
				stage_t0 = _now()
		"S8a_exit":
			if _stealth_ready():
				stage = "S8a_vis"
				stage_t0 = _now()
		"S8a_vis":
			# Видимое окно ≥0.35с ОБЯЗАТЕЛЬНО после выхода: perception должен
			# увидеть игрока и обновить last_seen — иначе lost-перехода не будет.
			if t >= 0.35:
				_tp_player(Vector3(0.0, 1.0, -5.0))       # в куст → lost → INVESTIGATE
				_request_stealth(true)
				stage = "S8a_in"
				stage_t0 = _now()
		"S8a_in":
			if _stealth_ready():
				stage = "S8a_poll"
				stage_t0 = _now()
		"S8a_poll":
			if _phase() == "AMBUSH_WAIT":
				check("S8 ambush_chance=1.0 → фаза AMBUSH_WAIT", true)
				stage = "S8a_face"
				stage_t0 = _now()
			elif t > 5.0:
				check("S8 AMBUSH_WAIT за 5с (фаза=%s)" % _phase(), false)
				stage = "ENDFAIL"
		"S8a_face":
			if t >= 0.4:
				check("S8 move_state=AMBUSH_WAIT (получено %s)" % _move_state(), _move_state() == "AMBUSH_WAIT")
				check("S8 is_search_holding() (стоит у края)", bool(brain.call("is_search_holding")))
				var c: Vector3 = brain.get("_bush_center")
				var to_bush := c - enemy.global_position
				to_bush.y = 0.0
				var fwd := -enemy.global_transform.basis.z
				fwd.y = 0.0
				var dot := 0.0
				if to_bush.length() > 0.01:
					dot = fwd.normalized().dot(to_bush.normalized())
				check("S8 засада: фейсинг на куст (dot=%.2f > 0.7)" % dot, dot > 0.7)
				# S8b: ambush_chance=0.0 → после прибытия SEARCH (тот же сид).
				var p4: Resource = prof.duplicate(true)
				p4.ambush_chance = 0.0
				p4.blind_strike_chance = 0.0
				brain.profile = p4
				brain.rng.seed = SEED
				_tp_enemy(Vector3(0.0, 1.0, 4.0))
				_tp_player(Vector3(0.0, 1.0, -1.8))
				_request_stealth(false)
				stage = "S8b_exit"
				stage_t0 = _now()
		"S8b_exit":
			if _stealth_ready():
				stage = "S8b_vis"
				stage_t0 = _now()
		"S8b_vis":
			if t >= 0.35:
				_tp_player(Vector3(0.0, 1.0, -5.0))
				_request_stealth(true)
				stage = "S8b_in"
				stage_t0 = _now()
		"S8b_in":
			if _stealth_ready():
				stage = "S8b_poll"
				stage_t0 = _now()
		"S8b_poll":
			if _phase() == "SEARCH":
				check("S8 ambush_chance=0.0 → фаза SEARCH (не засада)", true)
				check("S8 move_state=SEARCH (получено %s)" % _move_state(), _move_state() == "SEARCH")
				# S9 (Q7.23): привязка куста у УГЛА бокса — регресс кругового теста
				# (угол: dist до ЦЕНТРА 4.62 > 3.65 → старая привязка ломалась,
				# орбита выпадала в last_seen — наблюдение заказчика 17.10.2026).
				_tp_enemy(Vector3(2.0, 1.0, -6.0))
				_tp_player(Vector3(3.3, 1.0, -8.5))   # вне бокса у угла (зазор 0.125 м по z)
				_request_stealth(false)
				stage = "S9_exit"
				stage_t0 = _now()
			elif t > 5.0:
				check("S8 SEARCH за 5с (фаза=%s)" % _phase(), false)
				stage = "ENDFAIL"
		"S9_exit":
			if _stealth_ready():
				stage = "S9_vis"
				stage_t0 = _now()
		"S9_vis":
			if t >= 0.35:
				_tp_player(Vector3(2.9, 1.0, -8.0))   # в куст у самого угла
				_request_stealth(true)
				stage = "S9_in"
				stage_t0 = _now()
		"S9_in":
			if _stealth_ready():
				stage = "S9_poll"
				stage_t0 = _now()
		"S9_poll":
			if _phase() == "SEARCH" and _move_state() == "SEARCH":
				check("S9 угол куста: куст привязан (get_linked_bush != null)", brain.call("get_linked_bush") != null)
				var oc: Vector3 = brain.call("get_orbit_center")
				var bc: Vector3 = brain.get("_bush_center")
				var cdiff := Vector2(oc.x - bc.x, oc.z - bc.z).length()
				check("S9 центр орбиты = ЦЕНТР КУСТА (откл. %.3f ≤ 0.05), не точка пропажи" % cdiff, cdiff <= 0.05)
				var orad: float = brain.call("get_orbit_radius")
				check("S9 радиус орбиты от территории куста: %.2f ≥ 3.5 (r_куста+0.5)" % orad, orad >= 3.5)
				brain.set("_search_until", _now() + 0.3)   # poke → быстрый IDLE для S9b
				stage = "S9b"
				stage_t0 = _now()
			elif t > 4.0:
				check("S9 SEARCH у угла за 4с (фаза=%s state=%s)" % [_phase(), _move_state()], false)
				stage = "ENDFAIL"
		"S9b":
			if t >= 0.7:
				check("S9b после таймаута: move_state=IDLE (получено %s)" % _move_state(), _move_state() == "IDLE")
				# ЧЕСТНЫЙ ФЕЙСИНГ (Q7.23, наблюдение заказчика «всегда поворачивается
				# лицом к персонажу, даже когда не видит его»): игрок скрыт — намерение
				# НЕ несёт yaw (корпус сохраняет последний поворот, не следит сквозь карту).
				var ai := enemy.get_node("AIIntentComponent")
				var it = ai.call("get_intent")
				check("S9b невидимый игрок: has_yaw=false (фейсинг не следит за игроком)", it.get("has_yaw") == false)
				check("S9b IDLE: snap_stop=true (стоит)", it.get("snap_stop") == true)
				# S10 (Q7.25): ПОСТ ПО УМОЛЧАНИЮ — вердикт «должен по умолчанию
				# идти охранять манекен — патрулировать рядом» (фикс «зависает
				# и стоит после патрулирования»): игрок всё ещё скрыт, поиск
				# окончен → GUARD у манекена с орбитальным патрулём.
				# Профиль — СВОЙ (мозг сейчас на p4 из S8b; паттерн S7/S8).
				var p5g: Resource = prof.duplicate(true)
				p5g.guard_post_enabled = true
				brain.profile = p5g
				_tp_enemy(Vector3(0.0, 1.0, 3.0))
				stage = "S10poll"
				stage_t0 = _now()
		"S10poll":
			if _move_state() == "GUARD" and _phase() == "":
				check("S10 пост по умолчанию: потерян+поиск окончен → GUARD (манекен)", true)
				probe.center = dummy.global_position
				probe.reset()
				stage = "S10obs"
				stage_t0 = _now()
			elif t > 1.5:
				check("S10 GUARD за 1.5с (state=%s phase=%s)" % [_move_state(), _phase()], false)
				stage = "S10fin"
		"S10obs":
			if t >= 2.5:
				probe.active = false
				check("S10 патрулирует у поста: угол %.2f рад ≥ 0.5 за 2.5с" % probe.swept, probe.swept >= 0.5)
				var dpost := enemy.global_position.distance_to(dummy.global_position)
				check("S10 радиус патруля %.2f ∈ [1.5, 5.0] (guard_patrol 2.5 + сходимость)" % dpost,
					dpost >= 1.5 and dpost <= 5.0)
				var vh := Vector2(enemy.velocity.x, enemy.velocity.z).length()
				check("S10 В ДВИЖЕНИИ («не зависает»): |v|=%.2f > 0.5" % vh, vh > 0.5)
				stage = "S10fin"
		"S10fin":
			# S8c: детерминизм направления слепого удара (сид).
			brain.rng.seed = 4242
			var d1: String = str(brain.call("_pick_blind_direction"))
			brain.rng.seed = 4242
			var d2: String = str(brain.call("_pick_blind_direction"))
			check("S8c детерминизм: сид 4242 → %s == %s" % [d1, d2], d1 == d2)
			check("S8c направление валидно: %s ∈ {UP, LEFT, RIGHT}" % d1,
				["UP", "LEFT", "RIGHT"].has(d1))
			log_f.store_line("INFO стелс-вход естественный (Area3D): %s | выход: %s" % [
				str(stealth_entry_natural), str(stealth_exit_natural)])
			log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
			log_f.close()
			quit(0 if failed == 0 else 1)
			return true
	if stage == "ENDFAIL":
		log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
		log_f.close()
		quit(1)
		return true
	if frame > 12000:
		log_f.store_line("TIMEOUT stage=%s phase=%s move_state=%s" % [stage, _phase(), _move_state()])
		log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
		log_f.close()
		quit(1)
		return true
	return false
