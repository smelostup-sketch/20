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
## Аудит Q7.16 нашёл здесь подглядывания (подписка на block_started — невидимое
## состояние; опрос is_attack_in_progress() — FSM ввода игрока, включает фазу
## START_DELAY до анимации). Оба устранены; во внутренности чужих компонентов
## perception больше не читает (компонентная чистота).
## API сохранён: замороженный UtilityAI-материал компилируется и питается теми
## же методами (семантика is_player_blocking изменена на честную — см. ниже).

signal player_attack_observed(direction: String)
signal player_block_observed(direction: String)
signal player_mobility_observed(action_name: String)

## Окно «атака игрока видна» (с). Родословная: клип игрока AT_RIGHT 3.833 с /
## attack_animation_speed 3.75 ≈ 1.02 с — примерно столько атака различима глазом.
@export_range(0.1, 3.0, 0.05) var player_attack_visibility_window := 1.0
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
