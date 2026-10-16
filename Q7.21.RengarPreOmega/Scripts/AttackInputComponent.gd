
extends Node
class_name AttackInputComponent

const LOG_TAG := "Ввод"

## Компонент ввода направленной атаки.
## Владеет вводом, ожиданием жеста и последовательностью атаки.
##
## CombatComponent:
## - подтверждает/отклоняет атаку;
## - сообщает об interruption.
##
## AnimationComponent:
## - проигрывает attack animation;
## - сообщает о фактическом окончании animation clip.
##
## AttackInputComponent НЕ рассчитывает длительность атаки.

signal waiting_for_direction_started
signal direction_locked(direction: String)
signal attack_committed(direction: String)
signal attack_input_cancelled(reason: String)
signal attack_sequence_finished

enum InputState { IDLE, WAITING_DIRECTION, START_DELAY, ATTACKING }

@export_group("Attack Direction Input")
@export_range(0.0, 0.25, 0.01, "suffix:s")
var attack_start_delay := 0.05

@export_range(0.1, 10.0, 0.1)
var direction_threshold := 0.5

@export var combat_path: NodePath = NodePath("../CombatComponent")
@export var movement_shell_path: NodePath = NodePath("../MovementShell")
@export var animation_component_path: NodePath = NodePath("../AnimationComponent")

# Логирование (Q7.13): единый журнал GameLog, тег LOG_TAG ниже.
# compact = события ввода; verbose = игноры нажатий и попытки.
# Режим принадлежит SettingsService; локального флага логов нет.

var owner_body: CharacterBody3D
var combat_comp: CombatComponent
var movement_shell: MovementShell
var animation_component: Node

var input_state: InputState = InputState.IDLE
var accumulated_mouse_delta := Vector2.ZERO
var locked_direction := ""
var delay_left := 0.0


func _ready() -> void:
	owner_body = get_parent() as CharacterBody3D

	if owner_body == null:
		push_error(
			"AttackInputComponent должен быть дочерним узлом CharacterBody3D"
		)
		return

	combat_comp = get_node_or_null(combat_path) as CombatComponent
	movement_shell = get_node_or_null(movement_shell_path) as MovementShell
	animation_component = get_node_or_null(animation_component_path)

	if combat_comp == null or movement_shell == null:
		push_error(
			"AttackInputComponent: не найдены CombatComponent или MovementShell"
		)
		return

	if animation_component == null:
		push_error(
			"AttackInputComponent: не найден AnimationComponent по пути "
			+ str(animation_component_path)
		)
		return

	if not animation_component.has_signal("attack_animation_finished"):
		push_error(
			"AttackInputComponent: AnimationComponent не имеет сигнала "
			+ "attack_animation_finished"
		)
		return

	combat_comp.attack_cancelled.connect(_on_combat_attack_cancelled)

	# Окончание атаки определяется реальным окончанием AnimationPlayer.
	animation_component.connect(
		"attack_animation_finished",
		_on_attack_finished
	)

	_vtrace(
		"ГОТОВ | delay=%.2fs threshold=%.2f"
		% [attack_start_delay, direction_threshold]
	)


func _physics_process(delta: float) -> void:
	if input_state != InputState.START_DELAY:
		return

	if not _can_continue_attack():
		_cancel_input("state_invalid")
		return

	delay_left -= delta

	if delay_left <= 0.0:
		_commit_attack()


func process_mouse_delta(relative: Vector2) -> void:
	if input_state != InputState.WAITING_DIRECTION:
		return

	accumulated_mouse_delta += relative

	var candidate := _resolve_direction(accumulated_mouse_delta)

	if candidate.is_empty():
		return

	locked_direction = candidate
	input_state = InputState.START_DELAY
	delay_left = attack_start_delay

	direction_locked.emit(locked_direction)

	_trace(
		"DIRECTION_LOCKED | dir=%s delta=%s | start in %.2fs"
		% [
			locked_direction,
			_format_delta(),
			attack_start_delay
		]
	)


func press_attack() -> bool:
	if input_state != InputState.IDLE:
		_vtrace(
			"НАЖАТИЕ_ИГНОР | state=%s | reason=active_sequence"
			% get_state_name()
		)
		return false

	if not _can_begin_attack():
		_vtrace(
			"НАЖАТИЕ_ИГНОР | state=%s | reason=%s"
			% [
				get_state_name(),
				_get_begin_failure_reason()
			]
		)
		return false

	input_state = InputState.WAITING_DIRECTION
	accumulated_mouse_delta = Vector2.ZERO
	locked_direction = ""
	delay_left = 0.0

	waiting_for_direction_started.emit()

	_trace(
		"НАЖАТИЕ_ПРИНЯТО | state=WAITING_DIRECTION | ожидание жеста мыши"
	)

	return true


func release_attack() -> void:
	# Быстрый клик до выбора направления полностью отменяется.
	# После фиксации направления отпускание больше не отменяет атаку.
	if input_state == InputState.WAITING_DIRECTION:
		_cancel_input("released_before_direction")

	elif (
		input_state == InputState.START_DELAY
		or input_state == InputState.ATTACKING
	):
		_vtrace(
			"ОТПУСКАНИЕ_ИГНОР | state=%s | атака продолжается"
			% get_state_name()
		)


func request_block() -> bool:
	if not can_start_block():
		_trace(
			"БЛОК_ОТКАЗ | state=%s | reason=invalid_context"
			% get_state_name()
		)
		return false

	if input_state == InputState.WAITING_DIRECTION:
		_cancel_input("block_before_direction")

	elif (
		input_state == InputState.START_DELAY
		or input_state == InputState.ATTACKING
	):
		_trace(
			"БЛОК_ОТМЕНИЛ_АТАКУ | state=%s"
			% get_state_name()
		)
		combat_comp.cancel_attack("block")

	return true


func request_dash_cancel() -> void:
	if input_state == InputState.WAITING_DIRECTION:
		_cancel_input("dash_before_direction")

	elif (
		input_state == InputState.START_DELAY
		or input_state == InputState.ATTACKING
	):
		_trace(
			"РЫВОК_ОТМЕНИЛ_АТАКУ | state=%s"
			% get_state_name()
		)
		combat_comp.cancel_attack("dash")


func cancel_pending_direction_for_dodge() -> void:
	# Dodge не прерывает уже подтверждённую атаку.
	# До фиксации направления атаки ещё нет.
	if input_state == InputState.WAITING_DIRECTION:
		_cancel_input("dodge_before_direction")


func blocks_dodge_start() -> bool:
	return (
		input_state == InputState.START_DELAY
		or input_state == InputState.ATTACKING
	)


func can_start_block() -> bool:
	if combat_comp == null or movement_shell == null or owner_body == null:
		return false

	if not owner_body.is_on_floor():
		return false

	if movement_shell.is_leaping:
		return false

	if movement_shell.is_dashing or movement_shell.is_dodging:
		return false

	if movement_shell.is_climbing or movement_shell.is_swimming:
		return false

	return true


func is_waiting_for_direction() -> bool:
	return input_state == InputState.WAITING_DIRECTION


func is_attack_in_progress() -> bool:
	return (
		input_state == InputState.START_DELAY
		or input_state == InputState.ATTACKING
	)


func get_state_name() -> String:
	return InputState.keys()[input_state]


func get_debug_mouse_delta() -> Vector2:
	return accumulated_mouse_delta


func get_debug_direction() -> String:
	return locked_direction


func _can_begin_attack() -> bool:
	# Атака разрешена на земле, в движении и в воздухе.
	# Проверка происходит на нажатии ЛКМ.
	if movement_shell == null or combat_comp == null:
		return false

	return (
		not movement_shell.is_dodging
		and not combat_comp.is_input_locked
		and not combat_comp.is_block_active
		and not combat_comp.is_recovery
	)


func _get_begin_failure_reason() -> String:
	if movement_shell == null or combat_comp == null:
		return "component_missing"

	if movement_shell.is_dodging:
		return "dodge_active"

	if combat_comp.is_input_locked:
		return "input_locked"

	if combat_comp.is_block_active:
		return "block_active"

	if combat_comp.is_recovery:
		return "recovery_active"

	return "unknown"


func _can_continue_attack() -> bool:
	# Dodge не должен принудительно отменять уже подтверждённую атаку.
	return movement_shell != null


func _resolve_direction(delta: Vector2) -> String:
	# Утверждённые направления:
	# RIGHT, LEFT и UP.
	#
	# Нижний жест не содержит fallback
	# и продолжает ожидание валидного движения.
	if (
		delta.y < -direction_threshold
		and absf(delta.y) > absf(delta.x)
	):
		return "UP"

	if absf(delta.x) >= direction_threshold:
		# Горизонтальный жест инвертирован относительно прежней схемы.
		return "RIGHT" if delta.x < 0.0 else "LEFT"

	return ""


func _commit_attack() -> void:
	if (
		input_state != InputState.START_DELAY
		or combat_comp == null
	):
		return

	_vtrace(
		"ПОПЫТКА_АТАКИ | dir=%s | leap=%s"
		% [
			locked_direction,
			str(movement_shell.is_leaping)
		]
	)

	if not combat_comp.perform_directional_attack(
		locked_direction,
		movement_shell.is_leaping
	):
		_cancel_input("combat_rejected")
		return

	input_state = InputState.ATTACKING

	attack_committed.emit(locked_direction)

	_trace(
		"АТАКА_НАЧАТА | dir=%s | state=ATTACKING"
		% locked_direction
	)


func _cancel_input(reason: String) -> void:
	if input_state == InputState.IDLE:
		return

	var previous_state := get_state_name()

	input_state = InputState.IDLE
	accumulated_mouse_delta = Vector2.ZERO
	locked_direction = ""
	delay_left = 0.0

	attack_input_cancelled.emit(reason)

	_trace(
		"СБРОС_ВВОДА | from=%s | reason=%s"
		% [
			previous_state,
			reason
		]
	)


func _on_combat_attack_cancelled(reason: String) -> void:
	_cancel_input(reason)


func _on_attack_finished() -> void:
	# Нормальное завершение атаки происходит только после
	# фактического окончания attack animation.
	if input_state != InputState.ATTACKING:
		return

	input_state = InputState.IDLE
	accumulated_mouse_delta = Vector2.ZERO
	locked_direction = ""
	delay_left = 0.0

	attack_sequence_finished.emit()

	_trace(
		"АТАКА_ЗАВЕРШЕНА | from=ATTACKING | reason=animation_complete"
	)


func _format_delta() -> String:
	return "(%.1f, %.1f)" % [
		accumulated_mouse_delta.x,
		accumulated_mouse_delta.y
	]


func _trace(message: String) -> void:
	GameLog.compact(LOG_TAG, message)

func _vtrace(message: String) -> void:
	GameLog.verbose(LOG_TAG, message)
