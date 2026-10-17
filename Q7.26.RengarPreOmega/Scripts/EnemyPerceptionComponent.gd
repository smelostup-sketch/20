extends Node
class_name EnemyPerceptionComponent

const LOG_TAG := "Восприятие"

## Честные сенсоры врага (Q7.17, Фаза A; контракт заказчика «восприятие честное»).
## Наблюдает ТОЛЬКО видимые признаки и факты контакта:
## - атака игрока: сигнал ядра attack_performed (момент старта анимации — видимое);
## - блок игрока: ТОЛЬКО «мечом» — факт, что собственная атака отменена ядром с
##   reason="blocked" (block невидим: ни позы, ни клипа — знать о нём иначе значит
##   подглядывать; вердикт заказчика 2026-10-12: «пусть узнаёт мечом»);
## - мобильность игрока: сигнал shell action_started (dash/dodge — видимое движение).
## B3 (Q7.21): видимость игрока (dist <= vision_range И не в стелсе — в рамках
## игровой абстракции стелс = «исчез из чувств») + last_seen_position/since_seen
## и события player_lost/player_regained — честный сенсор «потерял игрока»
## (последняя ВИДИМАЯ точка фиксируется по факту видимости).
## Аудит Q7.16 нашёл здесь подглядывания (подписка на block_started — невидимое
## состояние; опрос is_attack_in_progress() — FSM ввода игрока, включает фазу
## START_DELAY до анимации). Оба устранены; во внутренности чужих компонентов
## perception больше не читает (компонентная чистота).
## API сохранён: замороженный UtilityAI-материал компилируется и питается теми
## же методами (семантика is_player_blocking изменена на честную — см. ниже).

signal player_attack_observed(direction: String)
signal player_block_observed(direction: String)
signal player_mobility_observed(action_name: String)
## B3 (adr_ai_phase_b.md §B3): переходы видимости игрока — события для мозга.
## player_lost несёт ПОСЛЕДНЮЮ ВИДИМУЮ позицию: враг видел, куда игрок вошёл
## (честно — фиксация по факту видимости, а не чтение текущей позиции сквозь куст).
signal player_lost(last_position: Vector3)
signal player_regained()

## Окно «атака игрока видна» (с). Родословная: клип игрока AT_RIGHT 3.833 с /
## attack_animation_speed 3.75 ≈ 1.02 с — примерно столько атака различима глазом.
@export_range(0.1, 3.0, 0.05) var player_attack_visibility_window := 1.0
## Дальность зрения (B3). Родословная: legacy detection_range=8.0 (EnemyController
## → экспорт AIBrainComponent) — тот же источник числа; в сцене оба не перекрыты
## (дефолты 8.0), расходиться не должны. Технический долг: унификация
## detection_range/vision_range в одну ручку — кандидат B5/спринта чистки.
@export_range(0.5, 30.0, 0.5) var vision_range := 8.0
## Сколько помним факт «мой удар заблокировали» (с). Родословная: длительность
## блока игрока block_active_duration 0.5 + запас на реакцию.
@export_range(0.1, 3.0, 0.05) var player_block_memory_window := 0.7

var enemy_body: CharacterBody3D
var player_body: CharacterBody3D
var player_combat: CombatComponent
var player_shell: MovementShell
var own_combat: CombatComponent

var last_player_attack_direction := "UP"
var last_player_attack_time := -999.0
var last_player_block_direction := "UP"
var last_player_block_time := -999.0
var last_player_mobility_time := -999.0
var last_player_mobility_action := ""

# === B3: видимость игрока и «последняя видимая точка» ===
## В рамках игровой абстракции стелс = «исчез из чувств» (adr §B3): игрок видим,
## пока dist <= vision_range И НЕ в стелсе. Оба признака — наблюдаемые факты
## (дистанция — кинематика; стелс — публичное состояние shell, тот же источник,
## что читает legacy-ветка мозга). since_seen = INF, пока ни разу не видели.
var player_visible := false
var last_seen_position := Vector3.ZERO
var since_seen := INF
var _ever_visible := false


func _physics_process(delta: float) -> void:
	if enemy_body == null or player_body == null or not is_instance_valid(player_body):
		return
	var visible_now := is_player_visible_now()
	if visible_now:
		last_seen_position = player_body.global_position
		since_seen = 0.0
		if not player_visible and _ever_visible:
			GameLog.verbose(LOG_TAG, "ИГРОК_СНОВА_ВИДИМ | dist=%.2f" % get_distance_to_player())
			player_regained.emit()
	else:
		if player_visible:
			# Момент исчезновения: фиксируем последнюю ВИДИМУЮ позицию (честно —
			# враг видел, куда игрок вошёл; текущую позицию сквозь куст не читает).
			GameLog.verbose(LOG_TAG, "ИГРОК_ПОТЕРЯН | last_seen=(%.2f, %.2f, %.2f)" % [
				last_seen_position.x, last_seen_position.y, last_seen_position.z])
			player_lost.emit(last_seen_position)
		if _ever_visible:
			since_seen += delta
	player_visible = visible_now
	_ever_visible = _ever_visible or visible_now


## Виден ли игрок СЕЙЧАС (дистанция + стелс). Публично: читает мозг (B3) и стенды.
func is_player_visible_now() -> bool:
	if enemy_body == null or player_body == null or not is_instance_valid(player_body):
		return false
	if get_distance_to_player() > vision_range:
		return false
	if player_shell != null and bool(player_shell.get("is_stealthed")):
		return false
	return true


func _ready() -> void:
	enemy_body = get_parent() as CharacterBody3D
	if enemy_body != null:
		own_combat = enemy_body.get_node_or_null("CombatComponent") as CombatComponent
	if own_combat != null:
		# «Узнаёт мечом»: собственный исход атаки — единственный честный источник
		# знания о блоке игрока.
		own_combat.attack_cancelled.connect(_on_own_attack_cancelled)
	call_deferred("_bind_player")


func get_distance_to_player() -> float:
	if enemy_body == null or player_body == null:
		return INF
	return enemy_body.global_position.distance_to(player_body.global_position)


## Игрок атакует = атака наблюдается сейчас (в пределах окна видимости клипа).
## Честная замена прежнего опроса FSM ввода (START_DELAY был невидим).
func is_player_attacking() -> bool:
	return _now() - last_player_attack_time <= player_attack_visibility_window


## Игрок блокирует = недавно мой удар заблокировали (факт контакта).
## Честная замена прежней подписки на невидимый block_started.
func is_player_blocking() -> bool:
	return _now() - last_player_block_time <= player_block_memory_window


func is_player_moving_fast() -> bool:
	if player_body == null:
		return false
	# Скорость тела — наблюдаемая кинематика (честный сенсор).
	return Vector2(player_body.velocity.x, player_body.velocity.z).length() > 4.0


func was_player_recently_mobile(window_seconds: float) -> bool:
	return _now() - last_player_mobility_time <= window_seconds


func get_player_attack_recency(window_seconds: float) -> float:
	var elapsed := _now() - last_player_attack_time
	return clampf(1.0 - elapsed / maxf(window_seconds, 0.01), 0.0, 1.0)


func _bind_player() -> void:
	var candidate := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if candidate == null:
		push_warning("EnemyPerceptionComponent: игрок не найден")
		return
	player_body = candidate
	player_combat = player_body.get_node_or_null("CombatComponent") as CombatComponent
	player_shell = player_body.get_node_or_null("MovementShell") as MovementShell
	if player_combat != null:
		# Только ВИДИМЫЕ события: старт анимации атаки.
		player_combat.attack_performed.connect(_on_player_attack_performed)
	if player_shell != null:
		player_shell.action_started.connect(_on_player_action_started)
	_trace("ИГРОК_ПРИВЯЗАН")


func _on_player_attack_performed(direction: String, _is_leap_attack: bool) -> void:
	last_player_attack_direction = direction
	last_player_attack_time = _now()
	player_attack_observed.emit(direction)
	_trace("АТАКА_ИГРОКА | dir=" + direction)


func _on_own_attack_cancelled(reason: String) -> void:
	if reason != "blocked" or own_combat == null:
		return
	# Честный вывод: раз МОЮ атаку dir=X заблокировали — игрок держал защиту
	# BLOCK_RESPONSE[X] (зеркало, единый источник ядра). Память получает
	# НАПРАВЛЕНИЕ БЛОКА ИГРОКА (та же семантика, что у прежнего block_started).
	last_player_block_direction = CombatComponent.BLOCK_RESPONSE.get(own_combat.current_attack_dir, "UP")
	last_player_block_time = _now()
	player_block_observed.emit(last_player_block_direction)
	_trace("БЛОК_ИГРОКА | dir=" + last_player_block_direction + " (узнано мечом)")


func _on_player_action_started(_direction: Vector2, action_type: int) -> void:
	last_player_mobility_time = _now()
	last_player_mobility_action = "DODGE" if action_type == MobilityAction.ActionType.DODGE else "DASH"
	player_mobility_observed.emit(last_player_mobility_action)
	_trace("МОБИЛЬНОСТЬ_ИГРОКА | action=" + last_player_mobility_action)


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


func _trace(message: String) -> void:
	GameLog.verbose(LOG_TAG, message)
