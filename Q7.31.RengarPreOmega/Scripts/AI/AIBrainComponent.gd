extends Node
class_name AIBrainComponent
## Мозг решений врага (Q7.17, Фаза A) — событийный скелет концепции ИИ заказчика.
##
## ГЛАВНЫЙ ПРИНЦИП (концепция §1): решение ЖДЁТ СВОЙ ИСХОД. Намерение атаки
## подаётся в единое ядро (perform_directional_attack) только когда предыдущий
## цикл ЗАКРЫТ сигналом ядра (attack_finished / attack_cancelled), а не
## накладывается таймером поверх. Гарды ядра (recovery/lock/блок) остаются
## последней инстанцией, но в штатном режиме мозг в занятое ядро не стучится
## (контракт Q…_4: ноль отказного спама).
##
## Фаза A сохраняет legacy-поведение 1:1 (преследование + случайные атаки;
## маппинг UtilityAI когда включён; враг не блокирует): меняются СТРУКТУРА
## (исходы вместо попыток-каждый-тик) и честность сенсоров, не геймплей.
## Фаза B наполняет поведение: паттерны (profile.pattern_length > 1), блок с
## бюджетом (block_chance), отход после стана, агрессия — по наработкам заказчика.
##
## Соседи (экспорты-пути): CombatComponent (ядро, исходы), EnemyUtilityAIComponent
## (замороженный материал: маппинг решений, когда enabled), EnemyPerceptionComponent
## (честные сенсоры). Движение: move_state читает AIIntentComponent (тот же
## исполнитель MovementShell, что у игрока — единообразие).

signal decision_changed(move_state: String)
signal attack_decided(direction: String)

const LOG_TAG := "ИИ"
const DIRECTIONS := ["UP", "LEFT", "RIGHT"]

@export var profile: AIBrainProfile
@export var combat_path: NodePath = NodePath("../CombatComponent")
@export var utility_path: NodePath = NodePath("../EnemyUtilityAIComponent")
@export var perception_path: NodePath = NodePath("../EnemyPerceptionComponent")
## B4: здоровье (триггер «сильно ранен») и память (статистика для «уверенности
## в победе» — честная оценка: доля попаданий/блоков МОИХ атак).
@export var health_path: NodePath = NodePath("../HealthComponent")
@export var memory_path: NodePath = NodePath("../EnemyMemoryComponent")
@export_range(0.5, 30.0, 0.5) var detection_range := 8.0   # legacy EnemyController
@export_range(0.5, 10.0, 0.1) var stop_distance := 1.5     # legacy EnemyController
@export_range(0.5, 10.0, 0.1) var attack_range := 3.0      # legacy гейт dist <= 3.0
## Сид RNG: 0 = рандомизация при старте; фиксированный = воспроизводимость
## (детерминированные бенчи, концепция §4; legacy randi_range был невоспроизводим).
@export var random_seed := 0

var owner_body: CharacterBody3D = null
var combat: CombatComponent = null
var utility: Node = null
var perception: Node = null
var health: Node = null
var memory: Node = null
var rng := RandomNumberGenerator.new()

## Намерение движения (контракт Q…_2: читает AIIntentComponent; значения legacy).
var move_state := "IDLE"

# === B4: самосохранение (adr §B4, ревизия вердиктами 17.10.2026) ===
# Режимы: "" (не активно) | FLEE (бегство к кусту/от игрока) | HIDE (затаился
# в кусте, стелс) | GUARD (охраняет пост у манекена — «Пусть охраняет манекен»).
# БЕЗ ТАЙМЕРОВ (дизайн-принцип заказчика «таймеры — зло»): переходы — только
# дистанционные проверки и факты (стелс, hp, уверенность).
var _survival_mode := ""
var _survival_bush: Area3D = null       # ближайший куст (цель бегства; видимый террейн — честно)
var _survival_bush_center := Vector3.ZERO
var _guard_target := Vector3.ZERO       # пост охраны (ближайший узел guard_group)
var _guard_valid := false               # пост найден (нет манекена → fallback IDLE)
# Испуг от засады (Q7.25): урон от НЕВИДИМОГО атакующего — бегство от источника
# удара независимо от hp/уверенности. Снимается: атакующий стал виден ИЛИ
# дистанция выхода достигнута (без таймеров — событийность и дистанции).
var _fear_active := false
var _fear_source := Vector3.ZERO

# Движок паттернов (концепция §L2): pattern_length=1 → чистый рандом (legacy);
# 2-3 → серии повторов; pattern_switch_chance — «редкость смены» между сериями.
var _pattern_dir := ""
var _pattern_left := 0
# Ритм дуэли (B1, концепция §L4): момент, раньше которого следующее намерение
# атаки не подаётся (0 = не ждать; legacy). Взводится по получении исхода.
var _next_attack_time := 0.0

# === B2: блок с бюджетом реакции и отход после стана ===
# Замысел блока: взводится ЧЕСТНЫМ сенсором (perception.player_attack_observed =
# старт АНИМАЦИИ игрока), срабатывает не раньше reaction_ms (бюджет реакции),
# направление — угадывание через BLOCK_RESPONSE с вероятностью guess.
var _block_planned := false
var _block_planned_at := 0.0
var _block_observed_dir := "UP"
var _block_is_reactive := false   # блок активирован реактивно (живёт до истечения enemy_block_duration в ядре)
# Отход после стана: момент, до которого решение движения = RETREAT.
var _post_stun_until := 0.0

# === B3: поиск потерянного игрока (куст) — adr_ai_phase_b.md §B3 ===
# Фазы: "" (не ищет) | INVESTIGATE | SEARCH | AMBUSH_WAIT | BLIND_STRIKE.
# Вход — событием perception.player_lost (честный сенсор: последняя ВИДИМАЯ
# точка); выход — player_regained или search_time истёк → IDLE (adr §B3).
# Движение — те же AIIntent/MovementShell (орбита = касательный вектор).
var _search_phase := ""
var _search_target := Vector3.ZERO      # INVESTIGATE: куда идти; BLIND_STRIKE: край куста
var _orbit_center := Vector3.ZERO       # SEARCH: центр орбиты (куст или last_seen)
var _search_until := 0.0                # дедлайн SEARCH
var _ambush_until := 0.0                # дедлайн AMBUSH_WAIT
var _next_blind_roll := 0.0             # момент следующего ролла слепого удара
var _bush: Area3D = null                # связанный куст (ближайший к last_seen)
var _bush_center := Vector3.ZERO        # центр куста (замер по CollisionShape3D)
var _bush_radius := 0.0                 # горизонтальная полуэкстента куста (замер)
var _blind_holding := false             # BLIND_STRIKE: дошёл до края, бьёт/ждёт гейты
var _blind_return_phase := ""           # куда вернуться после исхода слепого удара
## Допуск привязки куста к last_seen (м). Родословная (замеры сцены): полкорпуса
## игрока 0.5 (BoxShape3D_xh4up size.x 0.996826 / 2) + пробег за 1 тик 6.0 м/с
## / 60 Гц = 0.1 (RengarProfile.speed; last_seen фиксируется на тик раньше
## исчезновения) → 0.6, округлено до 0.65.
const BUSH_LINK_MARGIN := 0.65

# Счётчики ожидания исхода — приёмка Фазы A (sim_enemy):
# intents_sent == attacks_started, intents_rejected == 0, outcomes >= started-1.
var awaiting_outcome := false
var intents_sent := 0
var intents_rejected := 0
var outcomes_received := 0


func _ready() -> void:
	owner_body = get_parent() as CharacterBody3D
	if owner_body == null:
		push_error("AIBrainComponent должен быть потомком CharacterBody3D")
		return
	combat = get_node_or_null(combat_path) as CombatComponent
	if combat == null:
		push_error("AIBrainComponent: не найден CombatComponent")
		return
	utility = get_node_or_null(utility_path)
	perception = get_node_or_null(perception_path)
	health = get_node_or_null(health_path)
	memory = get_node_or_null(memory_path)
	add_to_group("ai_brain") # точка применения настройки «Профиль ИИ» (SettingsService)
	if random_seed != 0:
		rng.seed = random_seed
	else:
		rng.randomize()
	if profile == null:
		profile = AIBrainProfile.new()
		push_warning("AIBrainComponent: профиль не назначен — использую AIBrainProfile по умолчанию (legacy-поведение)")
	# Подписки на ИСХОДЫ ядра — основа скелета «решение ждёт исход».
	combat.attack_finished.connect(_on_attack_finished)
	combat.attack_cancelled.connect(_on_attack_cancelled)
	combat.stun_started.connect(_on_stun_started)
	# Q7.25: факт урона с источником — для испуга от засады (невидимый атакующий).
	if health != null and health.has_signal("damaged"):
		health.damaged.connect(_on_damaged)
	# B2: честный сенсор атаки игрока (старт анимации) — для блока с бюджетом реакции.
	if perception != null and perception.has_signal("player_attack_observed"):
		perception.player_attack_observed.connect(_on_player_attack_observed)
	# B3: события видимости — вход/выход из поиска (решение ждёт исход: потеря/
	# обнаружение игрока — факты сенсора, а не опрос каждый тик).
	if perception != null and perception.has_signal("player_lost"):
		perception.player_lost.connect(_on_player_lost)
		perception.player_regained.connect(_on_player_regained)


func _physics_process(delta: float) -> void:
	if owner_body == null or combat == null:
		return
	_update_move_state(delta)
	_tick_block_reaction()
	_maybe_attack()


## Направление отступления для AIIntent: utility (когда жив) или fallback
## «прямо от игрока» (B2: отход после стана работает и без UtilityAI).
func get_retreat_direction() -> Vector3:
	if _utility_active():
		var d: Vector3 = utility.get_retreat_direction()
		if d.length_squared() > 0.0001:
			return d
	if owner_body == null:
		return Vector3.ZERO
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and is_instance_valid(player):
		var away := owner_body.global_position - player.global_position
		away.y = 0.0
		if away.length() > 0.01:
			return away.normalized()
	return Vector3.ZERO


## Остаток принудительного отхода после стана (публично для панели/стендов).
func get_post_stun_left() -> float:
	return maxf(0.0, _post_stun_until - _now())


# === РЕШЕНИЯ ДВИЖЕНИЯ (legacy-правила 1:1, владелец — мозг) ===
func _update_move_state(delta: float) -> void:
	# Приоритетные состояния: стан/лок/блок — решения заморожены
	# (legacy early-return ветки контроллера; snap_stop движения — в AIIntent).
	if combat.stun_timer > 0.0 or combat.ai_state == "STUNNED" or combat.is_input_locked:
		return
	if combat.enemy_block_active:
		# Реактивный блок (B2) живёт до истечения enemy_block_duration в ядре;
		# legacy-правило «деактивировать, если Utility не хочет» — только для
		# utility-активированного блока.
		if _block_is_reactive:
			return
		if not _utility_wants_block():
			combat.deactivate_enemy_block()
		return
	_block_is_reactive = false

	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not is_instance_valid(player):
		return # цели нет — решения не обновляем (движение при этом живёт в shell)

	var dist := owner_body.global_position.distance_to(player.global_position)
	var player_is_stealthed := false
	var pshell := player.get_node_or_null("MovementShell")
	if pshell != null:
		player_is_stealthed = bool(pshell.get("is_stealthed"))
	# B3: когда поиск включён, единый источник видимости — perception
	# (vision_range = detection_range = 8.0, родословная одна; см. техдолг
	# унификации в комментарии perception.vision_range). Выключен — legacy 1:1.
	var lost := dist > detection_range or player_is_stealthed
	if profile.bush_search_enabled and perception != null and "player_visible" in perception:
		lost = not bool(perception.get("player_visible"))

	# B4: самосохранение оценивается ПЕРЕД остальными решениями (сильно раненый
	# и не уверенный в победе спасается первым; приоритет ниже только у.freeze-
	# состояний стана/лока/блока выше). "" = не активно — обычные решения.
	var survival_state := ""
	if profile.self_preservation_enabled or _survival_mode != "":
		survival_state = _update_survival()

	var new_state := move_state
	if survival_state != "":
		new_state = survival_state
	elif _post_stun_until > 0.0 and _now() < _post_stun_until:
		# B2 (концепция §L2): после стана — отход, а не немедленное продолжение боя.
		new_state = "RETREAT"
	elif lost and (profile.bush_search_enabled or profile.guard_post_enabled):
		# B3: состояния поиска владеют движением (включая собственный удар —
		# слепой; его мах остаётся в фазе BLIND_STRIKE со snap_stop — та же
		# семантика «атакующий стоит», что у STOPPED, но без потери фазы).
		# Q7.25: поиск окончен/не включён → ПОСТ (вердикт: «по умолчанию идти
		# охранять манекен — патрулировать рядом»), иначе legacy IDLE.
		new_state = _update_lost()
	elif combat.is_recovery:
		# Атакующий стоит: новое решение не накладывается на незавершённое действие.
		new_state = "STOPPED"
	elif combat.ai_state != "STUNNED":
		if lost:
			new_state = "IDLE"
		elif _utility_active():
			match utility.update(delta):
				EnemyUtilityAIComponent.Decision.APPROACH:
					new_state = "CHASE"
				EnemyUtilityAIComponent.Decision.HOLD, EnemyUtilityAIComponent.Decision.ATTACK:
					new_state = "STOPPED"
				EnemyUtilityAIComponent.Decision.RETREAT:
					new_state = "RETREAT"
		else:
			# Базовая логика без ИИ: преследование и случайные атаки (legacy).
			new_state = "CHASE" if dist > stop_distance else "STOPPED"

	if new_state != move_state:
		move_state = new_state
		decision_changed.emit(move_state)
		GameLog.verbose(LOG_TAG, "РЕШЕНИЕ_ДВИЖЕНИЯ | move_state=%s | dist=%.2f" % [move_state, dist])


# === РЕШЕНИЯ АТАКИ (ждут исходы, не таймеры) ===
func _maybe_attack() -> void:
	if move_state != "STOPPED":
		return
	if _utility_wants_block():
		combat.activate_enemy_block(utility.get_recommended_block_direction())
		return
	if awaiting_outcome:
		return # РЕШЕНИЕ ЖДЁТ СВОЙ ИСХОД — ядро ещё не закрыло прошлый цикл
	if get_attack_cooldown_left() > 0.0:
		return # ритм дуэли (B1): пауза между циклами атаки
	if combat.is_recovery or combat.is_input_locked or combat.is_block_active:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not is_instance_valid(player):
		return
	if owner_body.global_position.distance_to(player.global_position) > attack_range:
		return
	var pshell := player.get_node_or_null("MovementShell")
	if pshell != null and bool(pshell.get("is_leaping")):
		return # по летящей цели не бьём (legacy-гейт)
	if _utility_active() and not utility.wants_attack():
		return

	var dir := _pick_direction()
	intents_sent += 1
	if combat.perform_directional_attack(dir, false):
		awaiting_outcome = true
		attack_decided.emit(dir)
		GameLog.verbose(LOG_TAG, "НАМЕРЕНИЕ_АТАКИ | dir=%s | ожидание исхода" % dir)
	else:
		intents_rejected += 1
		GameLog.verbose(LOG_TAG, "НАМЕРЕНИЕ_ОТКЛОНЕНО_ЯДРОМ | dir=%s (в штатном режиме должно быть редко)" % dir)


func _pick_direction() -> String:
	# Приоритет — рекомендация UtilityAI (legacy); иначе движок паттернов:
	# pattern_length=1 → чистый рандом (legacy), >1 → читаемые серии (Фаза B).
	if _utility_active():
		var rec: String = utility.get_recommended_attack_direction()
		if rec != "":
			return rec
	if _pattern_left > 0 and _pattern_dir != "":
		_pattern_left -= 1
		return _pattern_dir
	# Серия исчерпана. «Редкая смена» (концепция §L2): с вероятностью
	# pattern_switch_chance берём НОВОЕ направление, иначе держим прежнее
	# ещё на одну серию — игрок читает привычку и наказывает повтор.
	if _pattern_dir != "" and rng.randf() >= profile.pattern_switch_chance:
		_pattern_left = maxi(profile.pattern_length, 1) - 1
		GameLog.verbose(LOG_TAG, "ПАТТЕРН | серия продлена: %s" % _pattern_dir)
		return _pattern_dir
	_pattern_dir = DIRECTIONS[rng.randi_range(0, DIRECTIONS.size() - 1)]
	_pattern_left = maxi(profile.pattern_length, 1) - 1
	return _pattern_dir


# === ИСХОДЫ ЯДРА (подписки) ===
func _on_attack_finished() -> void:
	if awaiting_outcome:
		awaiting_outcome = false
		outcomes_received += 1
		_schedule_next_attack()
		_on_blind_strike_outcome()
		GameLog.verbose(LOG_TAG, "ИСХОД_ПОЛУЧЕН | attack_finished — решение разблокировано")


func _on_attack_cancelled(reason: String) -> void:
	if awaiting_outcome:
		awaiting_outcome = false
		outcomes_received += 1
		_schedule_next_attack()
		_on_blind_strike_outcome()
		GameLog.verbose(LOG_TAG, "ИСХОД_ПОЛУЧЕН | attack_cancelled reason=%s" % reason)


func _on_stun_started(duration: float) -> void:
	GameLog.verbose(LOG_TAG, "ИСХОД_ПОЛУЧЕН | stun_started duration=%.2f" % duration)
	# B2 (концепция §L2): после стана — отход. Окно отсчитывается от КОНЦА стана
	# (во время стана решения и так заморожены). 0.0 = legacy (без отхода).
	if profile.post_stun_retreat_time > 0.0:
		_post_stun_until = _now() + duration + profile.post_stun_retreat_time
		GameLog.verbose(LOG_TAG, "ОТХОД_ЗАПЛАНИРОВАН | %.2f с после конца стана" % profile.post_stun_retreat_time)


# === B2: РЕАКТИВНЫЙ БЛОК (бюджет реакции + вероятности из профиля) ===
func _on_player_attack_observed(direction: String) -> void:
	if profile.block_chance <= 0.0:
		return # legacy: враг не блокирует
	if _block_planned or combat.enemy_block_active:
		return
	if rng.randf() >= profile.block_chance:
		GameLog.verbose(LOG_TAG, "БЛОК_НЕ_СТАЛ | шанс=%.2f не выпал" % profile.block_chance)
		return
	_block_planned = true
	_block_planned_at = _now() + float(profile.reaction_ms) * 0.001
	_block_observed_dir = direction
	GameLog.verbose(LOG_TAG, "БЛОК_ЗАМЫСЕЛ | увидел атаку dir=%s, бюджет %.2f с" % [
		direction, float(profile.reaction_ms) * 0.001])


func _tick_block_reaction() -> void:
	if not _block_planned:
		return
	if _now() < _block_planned_at:
		return # бюджет реакции ещё не истёк — ЧЕСТНАЯ задержка
	_block_planned = false
	# Условия активации: ядро свободно, не в стане/локе, цель в зоне видимости.
	if combat.stun_timer > 0.0 or combat.is_input_locked \
			or combat.enemy_block_active or combat.is_recovery:
		GameLog.verbose(LOG_TAG, "БЛОК_ПРОПУЩЕН | ядро занято")
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not is_instance_valid(player):
		return
	if owner_body.global_position.distance_to(player.global_position) > detection_range:
		return # «не увидел» — вне зоны обнаружения
	var dir := _guess_block_direction()
	_block_is_reactive = true
	combat.activate_enemy_block(dir)
	GameLog.compact(LOG_TAG, "БЛОК_ВРАГА | dir=%s | бюджет=%.2f с" % [dir, float(profile.reaction_ms) * 0.001])


func _guess_block_direction() -> String:
	# Честное угадывание: с вероятностью block_dir_guess_chance зеркалим
	# НАБЛЮДАННУЮ атаку (BLOCK_RESPONSE — единый источник, тот же что у
	# телеграфа Q7.9), иначе случайное направление.
	if rng.randf() < profile.block_dir_guess_chance:
		return CombatComponent.BLOCK_RESPONSE.get(_block_observed_dir, "UP")
	return DIRECTIONS[rng.randi_range(0, DIRECTIONS.size() - 1)]


# === Q7.25: ПОСТ ПО УМОЛЧАНИЮ (вердикт «охранять манекен — патрулировать рядом») ===
## Игрок потерян: активен поиск — поиск; иначе пост (данные: guard_group) или IDLE.
func _update_lost() -> String:
	if profile.bush_search_enabled and _search_phase != "":
		return _update_search()
	return _fallback_when_lost()


func _fallback_when_lost() -> String:
	if profile.guard_post_enabled:
		return _update_guard()
	return "IDLE"


## Охрана поста: точка — из данных сцены (ближайший узел guard_group), движение —
## «дойти и патрулировать рядом» (орбита guard_patrol_radius — тот же стееринг,
## что у орбиты поиска B3; единообразие). Нет поста → IDLE (fallback, не хардкод).
func _update_guard() -> String:
	_guard_target = _find_guard_point()
	if not _guard_valid:
		return "IDLE"
	return "GUARD"


## На посту ли (для AIIntent: дошёл → орбита, иначе — идти к посту). Допуск =
## patrol_radius + investigate_arrive_radius (родословная: 1.5 — legacy
## stop_distance, «достаточно близко»).
func is_guard_at_post() -> bool:
	return _guard_valid and owner_body.global_position.distance_to(_guard_target) \
		<= profile.guard_patrol_radius + profile.investigate_arrive_radius


func get_guard_center() -> Vector3:
	return _guard_target


func get_guard_radius() -> float:
	return profile.guard_patrol_radius


# === B3: ПОИСК ПОТЕРЯННОГО ИГРОКА (adr_ai_phase_b.md §B3) ===
## Вход — событие perception.player_lost с последней ВИДИМОЙ позицией (честно:
## враг видел, куда игрок вошёл; текущую позицию сквозь куст не читает).
func _on_player_lost(last_position: Vector3) -> void:
	if not profile.bush_search_enabled:
		return # legacy: потерял → IDLE (ветка _update_move_state)
	_search_target = last_position
	_orbit_center = last_position
	_link_bush(last_position)
	_search_phase = "INVESTIGATE"
	_blind_holding = false
	_next_blind_roll = _now() + profile.blind_strike_interval
	GameLog.compact(LOG_TAG, "ПОИСК_НАЧАТ | иду к (%.1f, %.1f) | куст=%s" % [
		last_position.x, last_position.z, "да" if _bush != null else "нет"])


## Выход — игрок снова видим (adr §B3: «игрок снова видим -> обычные решения»).
func _on_player_regained() -> void:
	if _search_phase == "":
		return
	_end_search("ИГРОК_ВИДИМ")


func _end_search(reason: String) -> void:
	_search_phase = ""
	_blind_holding = false
	_blind_return_phase = ""
	_bush = null
	GameLog.compact(LOG_TAG, "ПОИСК_ОКОНЧЕН | причина=%s" % reason)


## Сердечник поиска: вызывается из _update_move_state каждый физический тик,
## пока игрок потерян и поиск включён. Возвращает move_state.
func _update_search() -> String:
	if _search_phase == "":
		return "IDLE" # поиск окончен по таймауту — стоим (legacy-семантика)
	match _search_phase:
		"INVESTIGATE":
			var d := owner_body.global_position.distance_to(_search_target)
			if d <= profile.investigate_arrive_radius:
				_on_investigate_arrived()
		"AMBUSH_WAIT":
			if _now() >= _ambush_until:
				_enter_search_orbit()
		"SEARCH":
			if _now() >= _search_until:
				# adr §B3: search_time истёк -> IDLE; Q7.25 (вердикт «по умолчанию
				# охранять манекен — патрулировать рядом»): истёк -> ПОСТ (данные),
				# поста нет/выключен -> IDLE (legacy).
				_end_search("ТАЙМАУТ")
				return _fallback_when_lost()
		"BLIND_STRIKE":
			# Разделение тиков: сначала фиксация у края (holding → AIIntent даст
			# snap_stop в ЭТОМ тике), удар — СЛЕДУЮЩИМ тиком, когда тело уже
			# стоит («атакующий стоит» — единая семантика с STOPPED; замер
			# sim_ai_bush S4: |v| < 0.6 в момент attack_performed).
			if not _blind_holding:
				if _bush != null and owner_body.global_position.distance_to(_bush_center) <= profile.blind_strike_range:
					_blind_holding = true
					GameLog.verbose(LOG_TAG, "СЛЕПОЙ_УДАР_ПОЗИЦИЯ | у края куста, изготовка")
			elif not awaiting_outcome and _core_free_for_attack():
				_send_blind_strike()
	# Роллы слепого удара — только в «ждущих» фазах (SEARCH/AMBUSH_WAIT).
	if _search_phase == "SEARCH" or _search_phase == "AMBUSH_WAIT":
		if _now() >= _next_blind_roll:
			_next_blind_roll = _now() + profile.blind_strike_interval
			if _bush != null and rng.randf() < profile.blind_strike_chance:
				_begin_blind_strike()
	return _search_phase


## Прибыл к последней видимой точке: засада у края куста (ролл ambush_chance,
## видение заказчика «или станет патрулировать вокруг куста, ожидая игрока»)
## либо сразу патруль-орбита.
func _on_investigate_arrived() -> void:
	if _bush != null and rng.randf() < profile.ambush_chance:
		_search_phase = "AMBUSH_WAIT"
		_ambush_until = _now() + profile.ambush_wait_time
		GameLog.compact(LOG_TAG, "ПОИСК_ФАЗА | AMBUSH_WAIT — засада у края куста %.1f с" % profile.ambush_wait_time)
	else:
		_enter_search_orbit()


func _enter_search_orbit() -> void:
	_search_phase = "SEARCH"
	_search_until = _now() + profile.search_time
	# Центр орбиты: куст, если он связан с last_seen (видение «патрулирует
	# ВОКРУГ КУСТА»; adr §B3 формулировал «вокруг last_seen» — last_seen и есть
	# край куста, но орбита вокруг ЦЕНТРА не заводит врага в куст; расхождение
	# задокументировано в changes.md Q7.21). Иначе — вокруг last_seen.
	_orbit_center = _bush_center if _bush != null else _search_target
	GameLog.compact(LOG_TAG, "ПОИСК_ФАЗА | SEARCH — орбита r=%.1f вокруг (%.1f, %.1f), %.1f с" % [
		profile.patrol_radius, _orbit_center.x, _orbit_center.z, profile.search_time])


## Привязка куста: ближайший куст группы "bush" (тот же источник, что у
## StealthComponent), чей центр в пределах radius + BUSH_LINK_MARGIN от
## last_seen. Кусты — видимый террейн: знать их позицию честно.
func _link_bush(last_position: Vector3) -> void:
	var found := _find_nearest_bush(last_position, BUSH_LINK_MARGIN)
	_bush = found.get("bush")
	_bush_center = found.get("center", Vector3.ZERO)
	_bush_radius = found.get("radius", 0.0)


## Общий замер кустов (B3-привязка к last_seen и B4-цель бегства — один
## источник): ближайший куст группы "bush", расстояние до ОБЪЁМА формы которого
## <= max_distance. Центр — глобальная позиция CollisionShape3D (в сцене куста
## форма смещена относительно Area3D). Возврат: {bush, center, radius, dist} | {}.
func _find_nearest_bush(from_position: Vector3, max_distance: float) -> Dictionary:
	var best := {}
	var best_d := INF
	for node in get_tree().get_nodes_in_group("bush"):
		var bush := node as Area3D
		if bush == null:
			continue
		var center := bush.global_position
		var cs := _find_collision_shape(bush)
		if cs != null:
			center = cs.global_position
		var radius := _measure_bush_radius(bush)
		var d := _distance_to_bush_volume(from_position, center, cs, radius)
		if d <= max_distance and d < best_d:
			best_d = d
			best = {"bush": bush, "center": center, "radius": radius, "dist": d}
	return best


## Q7.23 (наблюдение заказчика 17.10.2026: «патрулирует вокруг места пропажи,
## а не куста — за основу должна браться территория куста»): прежний тест
## привязки был КРУГОВЫМ от центра — для БОКСА куста угловые зоны (~31% каждой
## грани, расчёт по замерам: порог 3.65 < полудиагонали 4.24) не связывались,
## и орбита выпадала в last_seen. Теперь — честное расстояние «точка до ОБЪЁМА
## формы» (бокс: clamp по полуосям; сфера: len−r; 0 внутри).
func _distance_to_bush_volume(point: Vector3, center: Vector3, cs: CollisionShape3D, fallback_radius: float) -> float:
	var flat := Vector2(point.x - center.x, point.z - center.z)
	if cs != null and cs.shape != null:
		var scale_h := cs.global_transform.basis.get_scale().x
		if cs.shape is BoxShape3D:
			var half: Vector3 = (cs.shape as BoxShape3D).size * 0.5 * scale_h
			var dx := maxf(0.0, absf(flat.x) - half.x)
			var dz := maxf(0.0, absf(flat.y) - half.z)
			return sqrt(dx * dx + dz * dz)
		if cs.shape is SphereShape3D:
			return maxf(0.0, flat.length() - (cs.shape as SphereShape3D).radius * scale_h)
	# Произвольная форма — консервативный круг радиусом fallback_radius.
	return maxf(0.0, flat.length() - fallback_radius)


func _find_collision_shape(bush: Area3D) -> CollisionShape3D:
	for child in bush.get_children():
		if child is CollisionShape3D:
			return child
	return null


## Замер куста «с линейкой»: горизонтальная полуэкстента формы (данные сцены,
## не константа кода). Box → max(size.x, size.z)/2; Sphere → radius;
## fallback 1.5 = половина дефолтного patrol_radius без куста (консервативно).
func _measure_bush_radius(bush: Area3D) -> float:
	var cs := _find_collision_shape(bush)
	if cs != null and cs.shape != null:
		var scale_h := cs.global_transform.basis.get_scale().x
		if cs.shape is BoxShape3D:
			var size: Vector3 = (cs.shape as BoxShape3D).size
			return maxf(size.x, size.z) * 0.5 * scale_h
		if cs.shape is SphereShape3D:
			return (cs.shape as SphereShape3D).radius * scale_h
	return 1.5


func _begin_blind_strike() -> void:
	_blind_return_phase = _search_phase
	_search_phase = "BLIND_STRIKE"
	_blind_holding = false
	# Цель подхода — край куста со стороны врага; если уже в blind_strike_range,
	# фаза сразу зафиксирует holding на следующем тике _update_search.
	var to_enemy := owner_body.global_position - _bush_center
	to_enemy.y = 0.0
	if to_enemy.length() < 0.05:
		to_enemy = -owner_body.global_transform.basis.z # вырождение — берём форвард
	_search_target = _bush_center + to_enemy.normalized() * _bush_radius
	GameLog.compact(LOG_TAG, "ПОИСК_ФАЗА | BLIND_STRIKE — замысел удара по кусту")


## Удар «в куст»: обычная атака ядром (тот же perform_directional_attack —
## единообразие; телеграф/хитбокс/анимация работают штатно). Направление
## ВСЛЕПУЮ — рандом через сидированный RNG (информации о игроке нет).
## ВНИМАНИЕ (ОТКРЫТЫЙ ВОПРОС 5 adr §5): попадает ли по скрытому игроку —
## решает ядро как обычно (стелс неуязвимость не даёт); ручка появится
## после вердикта заказчика.
func _send_blind_strike() -> void:
	var dir := _pick_blind_direction()
	intents_sent += 1
	if combat.perform_directional_attack(dir, false):
		awaiting_outcome = true
		attack_decided.emit(dir)
		GameLog.compact(LOG_TAG, "СЛЕПОЙ_УДАР | dir=%s | в куст, жду исход" % dir)
	else:
		intents_rejected += 1
		GameLog.verbose(LOG_TAG, "СЛЕПОЙ_УДАР_ОТКЛОНЁН_ЯДРОМ | dir=%s" % dir)


## Отдельный метод — тестируемый шов детерминизма (прецедент: _pick_direction
## в sim_ai_duel T2 — тот же сид, та же последовательность).
func _pick_blind_direction() -> String:
	return DIRECTIONS[rng.randi_range(0, DIRECTIONS.size() - 1)]


## Исход слепого удара получен — возврат в фазу ожидания (решение ждёт исход).
func _on_blind_strike_outcome() -> void:
	if _search_phase != "BLIND_STRIKE":
		return
	_search_phase = _blind_return_phase if _blind_return_phase != "" else "SEARCH"
	_blind_holding = false
	_next_blind_roll = _now() + profile.blind_strike_interval
	GameLog.verbose(LOG_TAG, "СЛЕПОЙ_УДАР_ИСХОД | возврат в фазу %s" % _search_phase)


## Ядро свободно для удара (те же гейты, что у _maybe_attack — единая дисциплина).
func _core_free_for_attack() -> bool:
	return not combat.is_recovery and not combat.is_input_locked \
			and not combat.is_block_active and not combat.enemy_block_active \
			and get_attack_cooldown_left() <= 0.0


# === B3: ПУБЛИЧНОЕ СОСТОЯНИЕ ПОИСКА (читают AIIntent, панель, стенды) ===
func get_search_phase() -> String:
	return _search_phase


## Остаток текущей фазы поиска, с (0 = без таймера/не ищет).
func get_search_left() -> float:
	match _search_phase:
		"SEARCH":
			return maxf(0.0, _search_until - _now())
		"AMBUSH_WAIT":
			return maxf(0.0, _ambush_until - _now())
	return 0.0


## Точка-цель рулёжки (INVESTIGATE: last_seen; BLIND_STRIKE: край куста).
func get_search_target() -> Vector3:
	return _search_target


func get_orbit_center() -> Vector3:
	return _orbit_center


## Радиус орбиты: ЗА ОСНОВУ БЕРЁТСЯ ТЕРРИТОРИЯ КУСТА (вердикт заказчика
## 17.10.2026) — при привязанном кусте не меньше «радиус куста + полкорпуса»
## (0.5 — замер сцены: BoxShape3D_xh4up size.x 0.996826/2), чтобы враг кружил
## вокруг куста, а не срезал через него; ручка patrol_radius — нижняя граница
## для случая без куста (орбита вокруг last_seen).
func get_orbit_radius() -> float:
	if _bush != null:
		return maxf(profile.patrol_radius, _bush_radius + 0.5)
	return profile.patrol_radius


## Стоит ли на месте в поиске (AMBUSH_WAIT; BLIND_STRIKE после подхода).
func is_search_holding() -> bool:
	if _search_phase == "AMBUSH_WAIT":
		return true
	return _search_phase == "BLIND_STRIKE" and _blind_holding


## Точка фейсинга в фазах поиска (null = legacy «к игроку»). В поиске фейсинг
## НЕ следует за фактической позицией скрытого игрока — иначе поворот корпуса
## выдаёт его (нечестно); смотрим на last_seen / куст / центр орбиты.
func get_facing_point() -> Variant:
	# B4 + Q7.25: фейсинг — по ОПУБЛИКОВАННОМУ move_state (а не по внутреннему
	# _survival_mode): GUARD бывает двух источников (самосохранение И пост по
	# умолчанию) — правила общие. null = legacy «к игроку, если виден».
	match move_state:
		"FLEE":
			if is_player_visible():
				return null # бежит лицом к игроку (читаемость отхода, прецедент RETREAT)
			# Игрока не видит — смотрит КУДА БЕЖИТ (вектор бегства: от источника
			# испуга / к кусту в полуплоске «от» — get_survival_target мог бы
			# смотреть назад, на куст позади: бег «спиной вперёд» — Q7.25 фикс).
			var fd := get_flee_direction()
			if fd.length_squared() > 0.0001:
				return owner_body.global_position + fd * 2.0
			return null
		"HIDE":
			return null # в кусте: следит за игроком, если тот виден; иначе замер
		"GUARD":
			if is_player_visible():
				return null # следит за игроком (legacy-фейсинг)
			return _guard_target # в пути/на патруле без игрока: смотрит на пост
	match _search_phase:
		"INVESTIGATE":
			return _search_target
		"SEARCH":
			return _orbit_center
		"AMBUSH_WAIT", "BLIND_STRIKE":
			return _bush_center if _bush != null else _search_target
	return null


## Связанный куст (публично для стендов/панели; null = не у куста).
func get_linked_bush() -> Area3D:
	return _bush


## Виден ли игрок СЕЙЧАС (публично: читает AIIntent для ЧЕСТНОГО фейсинга —
## Q7.23, наблюдение заказчика «всегда поворачивается лицом к персонажу, даже
## когда не видит его»). Источник — perception (тот же сенсор, что ведёт
## last_seen); без perception — legacy «считаем видимым» (поведение Q≤7.22).
func is_player_visible() -> bool:
	if perception != null and "player_visible" in perception:
		return bool(perception.get("player_visible"))
	return true


# === B4: САМОСОХРАНЕНИЕ (adr §B4, ревизия вердиктами 17.10.2026) ===
## Триггер: hp НИЖЕ flee_hp_threshold И «не уверен в победе» (уверенность НИЖЕ
## flee_confidence_threshold). Поведение: FLEE (к ближайшему кусту, если он в
## полуплоске «от игрока», иначе просто прочь) → стелс в кусте → HIDE;
## выход — «когда игрока нет рядом» (dist > flee_exit_distance; БЕЗ таймеров —
## дизайн-принцип заказчика) → GUARD: охранять пост у манекена (группа
## guard_group). Реарм: угроза снова видна и близко → FLEE. Выздоровел
## (hp/уверенность выше порогов; в будущем — регенерация) → обычные решения.
func _update_survival() -> String:
	# Обе ручки выключены (переключение профиля настройками/стендом) — режим
	# гасим сразу, без залипания (в HIDE — со снятием стелса).
	if not profile.self_preservation_enabled and not profile.fear_on_ambush_damage \
			and _survival_mode != "":
		if _survival_mode == "HIDE":
			_exit_own_stealth()
		_exit_survival("ВЫКЛЮЧЕНО_ПРОФИЛЕМ")
		return ""
	var hp := _hp_ratio()
	var conf := _confidence()
	var healthy := hp >= profile.flee_hp_threshold or conf >= profile.flee_confidence_threshold
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var has_player := player != null and is_instance_valid(player)
	var dist := owner_body.global_position.distance_to(player.global_position) if has_player else INF
	var visible := is_player_visible()
	match _survival_mode:
		"":
			if not profile.self_preservation_enabled or healthy:
				return ""
			if visible and dist <= profile.flee_threat_range:
				_enter_survival("FLEE")
			else:
				# Немедленной угрозы нет — к посту (раненый не рыщет по карте).
				_enter_survival("GUARD")
		"FLEE":
			if visible:
				_fear_active = false # угроза обнаружена — обычные правила
			# Испуг (урон от невидимого) держит бегство при ЛЮБОМ hp; без испуга
			# выздоровел → бой. Выход — только дистанцией (БЕЗ таймеров, вердикт).
			if not _fear_active and healthy:
				_exit_survival("ВЫЗДОРОВЕЛ")
				return ""
			if _is_own_stealthed():
				_survival_mode = "HIDE"
				GameLog.compact(LOG_TAG, "САМОСОХРАНЕНИЕ | HIDE — затаился в кусте (стелс)")
			elif dist > profile.flee_exit_distance:
				_fear_active = false
				_enter_survival("GUARD")
				GameLog.compact(LOG_TAG, "САМОСОХРАНЕНИЕ | FLEE→GUARD — игрока нет рядом (%.1f м)" % dist)
		"HIDE":
			if visible:
				_fear_active = false
			if not _fear_active and healthy:
				_exit_own_stealth()
				_exit_survival("ВЫЗДОРОВЕЛ")
				return ""
			if not _is_own_stealthed():
				# Q7.26 (наблюдение заказчика, −1 балл: «вытолкнул полностью из
				# куста, а враг продолжает пассивно стоять»): стелс УТРАЧЕН —
				# прятаться больше негде, standing в открытом поле бессмысленно.
				# Фактовая проверка (без таймеров): угроза видна и близко →
				# снова бежать; иначе → к посту.
				if visible and dist <= profile.flee_threat_range:
					_enter_survival("FLEE")
					GameLog.compact(LOG_TAG, "САМОСОХРАНЕНИЕ | куст потерян (вытолкнут?) — угроза рядом, снова бегу")
				else:
					_enter_survival("GUARD")
					GameLog.compact(LOG_TAG, "САМОСОХРАНЕНИЕ | куст потерян — иду к посту")
			elif dist > profile.flee_exit_distance:
				_fear_active = false
				_exit_own_stealth()
				_enter_survival("GUARD")
				GameLog.compact(LOG_TAG, "САМОСОХРАНЕНИЕ | вылез: игрока нет рядом (%.1f > %.1f м) — охранять пост" % [
					dist, profile.flee_exit_distance])
		"GUARD":
			if not _fear_active and healthy:
				_exit_survival("ВЫЗДОРОВЕЛ")
				return ""
			if visible and dist <= profile.flee_threat_range:
				_enter_survival("FLEE") # реарм: угроза подошла к посту
	return _survival_mode


func _enter_survival(mode: String) -> void:
	_survival_mode = mode
	if mode == "FLEE" and _search_phase != "":
		_end_search("ИСПУГ_ИЛИ_БЕГСТВО") # самосохранение важнее поиска
	if mode == "FLEE":
		# Цель бегства — ближайший куст (видимый террейн — знать его честно;
		# тот же замер формы, что у поиска B3).
		var found := _find_nearest_bush(owner_body.global_position, INF)
		_survival_bush = found.get("bush")
		_survival_bush_center = found.get("center", Vector3.ZERO)
		GameLog.compact(LOG_TAG, "САМОСОХРАНЕНИЕ | FLEE — hp=%.2f уверенность=%.2f куст=%s" % [
			_hp_ratio(), _confidence(), "да" if _survival_bush != null else "нет"])
	elif mode == "GUARD":
		_guard_target = _find_guard_point()
		GameLog.compact(LOG_TAG, "САМОСОХРАНЕНИЕ | GUARD — пост (%.1f, %.1f) валиден=%s" % [
			_guard_target.x, _guard_target.z, str(_guard_valid)])


func _exit_survival(reason: String) -> void:
	_survival_mode = ""
	_survival_bush = null
	_fear_active = false
	_fear_source = Vector3.ZERO
	GameLog.compact(LOG_TAG, "САМОСОХРАНЕНИЕ_ОКОНЧЕНО | причина=%s" % reason)


## Q7.25 (вердикт заказчика): урон от НЕВИДИМОГО атакующего → испуг → FLEE от
## источника удара (направление удара — честный факт контакта, не «знание»
## позиции: источник даёт HealthComponent.damaged из аргумента ядра). Работает
## при любом hp; снимается видимостью атакующего или дистанцией выхода.
func _on_damaged(_amount: float, attacker_pos: Vector3) -> void:
	if not profile.fear_on_ambush_damage:
		return
	if is_player_visible():
		return # видимая угроза — обычные боевые решения, не испуг
	_fear_active = true
	_fear_source = attacker_pos
	_enter_survival("FLEE")
	GameLog.compact(LOG_TAG, "ИСПУГ | урон от невидимого атакующего — бегу от источника (%.1f, %.1f)" % [
		attacker_pos.x, attacker_pos.z])


## Доля hp (0..1). Нет сенсора — считаем здоровым (fail-safe: самосохранение
## не срабатывает на пустом месте).
func _hp_ratio() -> float:
	if health != null and health.has_method("get_hp_ratio"):
		return float(health.call("get_hp_ratio"))
	return 1.0


## Честная оценка «уверенности в победе» (adr §B4): доля hp + боевой опыт
## Memory (средняя успешность МОИХ атак и доля заблокированных из них).
## Линеаризация опыта: record = 0.5 + (avg_success − 0.5) − 0.5·avg_block_rate:
## нейтральный опыт (данных нет: success 0.5, block 0.0) = 0.5; все удары
## прошли = 1.0; все заблокировали = 0.0. Коэффициенты 1.0/0.5 — ПЕРВИЧНАЯ
## гипотеза (задокументирована); веса hp/опыта — ручки профиля (данные).
func _confidence() -> float:
	var record := 0.5
	if memory != null and memory.has_method("get_attack_success"):
		var succ_sum := 0.0
		var block_sum := 0.0
		for d in DIRECTIONS:
			succ_sum += float(memory.call("get_attack_success", d))
			block_sum += float(memory.call("get_attack_block_rate", d))
		var avg_succ := succ_sum / float(DIRECTIONS.size())
		var avg_block := block_sum / float(DIRECTIONS.size())
		record = clampf(0.5 + (avg_succ - 0.5) - 0.5 * avg_block, 0.0, 1.0)
	return clampf(profile.confidence_hp_weight * _hp_ratio() \
		+ profile.confidence_record_weight * record, 0.0, 1.0)


## Направление бегства (мировой нормализованный вектор): к кусту, если он в
## полуплоске «от игрока» (не бежим СКВОЗЬ игрока), иначе — прочь от игрока
## (тот же fallback, что у отхода B2).
func get_flee_direction() -> Vector3:
	var away := get_retreat_direction()
	if _fear_active and _fear_source != Vector3.ZERO:
		# Испуг: прочь от ИСТОЧНИКА УДАРА (факт контакта — честный сенсор).
		var from_src := owner_body.global_position - _fear_source
		from_src.y = 0.0
		if from_src.length() > 0.05:
			away = from_src.normalized()
	if _survival_bush != null and away.length_squared() > 0.0001:
		var to_bush := _survival_bush_center - owner_body.global_position
		to_bush.y = 0.0
		if to_bush.length() > 0.1 and to_bush.normalized().dot(away) > 0.0:
			return to_bush.normalized()
	return away


## Точка-цель рулёжки самосохранения (куст / пост; FLEE без куста — виртуальная
## точка в направлении бегства, нужна только фейсингу).
func get_survival_target() -> Vector3:
	match _survival_mode:
		"FLEE":
			if _survival_bush != null:
				return _survival_bush_center
			return owner_body.global_position + get_flee_direction() * 3.0
		"GUARD":
			return _guard_target
	return owner_body.global_position


## Полная неподвижность в самосохранении — только HIDE (затаился в кусте).
## GUARD с Q7.25 ПАТРУЛИРУЕТ у поста (вердикт: «патрулировать рядом») —
## стояние на месте заказчик видел как «зависает».
func is_survival_holding() -> bool:
	return _survival_mode == "HIDE"


func get_survival_mode() -> String:
	return _survival_mode


func _is_own_stealthed() -> bool:
	var sh := owner_body.get_node_or_null("MovementShell")
	return sh != null and bool(sh.get("is_stealthed"))


func _exit_own_stealth() -> void:
	var sh := owner_body.get_node_or_null("MovementShell")
	if sh != null and sh.has_method("set_stealthed"):
		sh.call("set_stealthed", false)


## Ближайший пост охраны: ближайший узел группы guard_group (данные сцены —
## манекен DummyMannequin в группе "dummy_enemy"). Нет поста — стоим на месте.
func _find_guard_point() -> Vector3:
	var best: Node3D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(profile.guard_group):
		var n3 := node as Node3D
		if n3 == null:
			continue
		var d := owner_body.global_position.distance_to(n3.global_position)
		if d < best_d:
			best_d = d
			best = n3
	if best == null:
		_guard_valid = false
		return owner_body.global_position
	_guard_valid = true
	return best.global_position


# === РИТМ ДУЭЛИ (B1) ===
## Сколько секунд осталось до права на следующее намерение атаки (0 = можно).
## Публично: читает панель журнала ИИ и стенд sim_ai_duel.
func get_attack_cooldown_left() -> float:
	return maxf(0.0, _next_attack_time - _now())


func _schedule_next_attack() -> void:
	var lo := profile.attack_interval_min
	var hi := maxf(profile.attack_interval_max, lo)
	if hi <= 0.0:
		_next_attack_time = 0.0 # legacy: бей сразу, как ядро свободно
		return
	_next_attack_time = _now() + rng.randf_range(lo, hi)
	GameLog.verbose(LOG_TAG, "РИТМ | пауза %.2f с до следующей атаки" % (_next_attack_time - _now()))


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


# === СЛУЖЕБНОЕ ===
func _utility_active() -> bool:
	return utility != null and bool(utility.get("enabled")) and utility.is_operational()


func _utility_wants_block() -> bool:
	return _utility_active() and utility.wants_block()
