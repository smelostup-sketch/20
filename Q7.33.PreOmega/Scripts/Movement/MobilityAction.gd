extends Node
class_name MobilityAction
## База одноразовых мобильных способностей (dash/dodge), Q7.14.
## Компонент владеет: таймером, постоянной скоростью на время действия,
## сигналами action_started/action_ended (shell ретранслирует — контракт
## EnemyPerception сохранён) и своими ГЕЙТАМИ старта. Профиль может запретить
## способность даже при прикреплённом компоненте (двойной замок: can_* + узел).
##
## Порядок гейтов (legacy-контракт StateComponent, сохранён):
##   1) профиль (can_dash/can_dodge);
##   2) блок активен — нельзя (legacy _can_start_action);
##   3) воздух/засада — нельзя (legacy _can_start_mobility_action reason=airborne);
##   4) другое мобильное действие активно — нельзя (reason=mobility_action_active);
##   5) специальные гейты наследника (_pre_start_gate: у dodge — атака).
## Числа (скорость/длительность) — экспорты узла: прежние дефолты StateComponent
## (dodge 12/0.2, dash 18/0.15) — родословная в changes.md Q7.14.

enum ActionType { NONE, DODGE, DASH }

signal action_started(dir: Vector2, type: int)
signal action_ended

const LOG_TAG := "Состояние"

@export var action_speed := 12.0
@export var action_duration := 0.2

var shell: MovementShell = null
var body: CharacterBody3D = null
var action_type: int = ActionType.NONE
var is_active := false
var action_timer := 0.0
var action_velocity_xz := Vector2.ZERO


func setup(p_shell: MovementShell) -> void:
	shell = p_shell
	body = p_shell.owner_body


## Имя действия для логов («РЫВОК»/«УКЛОН»).
func action_label() -> String:
	return "ДЕЙСТВИЕ"


## Гейт способности в профиле (наследник: can_dash / can_dodge).
func _profile_allows() -> bool:
	return true


## Спецгейт наследника перед стартом (dodge: атака блокирует старт).
func _pre_start_gate() -> bool:
	return true


## Хук старта (dash: отмена атаки рывком — утверждённый cancel).
func _on_started(_dir_input: Vector2) -> void:
	pass


func try_start(dir_input: Vector2, yaw: float) -> bool:
	if is_active or shell == null or body == null:
		return false
	if not _profile_allows():
		GameLog.verbose(LOG_TAG, "%s_ОТКАЗ | reason=profile_capability" % action_label())
		return false
	if shell.combat != null and shell.combat.is_block_active:
		GameLog.verbose(LOG_TAG, "%s_ОТКАЗ | reason=block_active" % action_label())
		return false
	if (shell.leap != null and shell.leap.is_leaping) or not body.is_on_floor():
		GameLog.verbose(LOG_TAG, "%s_ОТКАЗ | reason=airborne" % action_label())
		return false
	if shell.is_mobility_busy():
		GameLog.verbose(LOG_TAG, "%s_ОТКАЗ | reason=mobility_action_active" % action_label())
		return false
	if not _pre_start_gate():
		return false

	# Камера-относительный вектор (legacy: 8 направлений, нормализация).
	var world := Basis(Vector3.UP, yaw) * Vector3(dir_input.x, 0.0, dir_input.y)
	world.y = 0.0
	if world.length() > 0.001:
		world = world.normalized()
	action_velocity_xz = Vector2(world.x, world.z) * action_speed
	action_timer = action_duration
	is_active = true
	shell.mobility_recovery_active = false # новый рывок гасит прежний recovery-блендинг
	_on_started(dir_input)
	action_started.emit(dir_input, action_type)
	GameLog.compact(LOG_TAG, "%s_СТАРТ | input=%s" % [action_label(), str(dir_input)])
	return true


## Вызывается shell каждый тик, пока is_active. Порядок legacy: сначала таймер —
## в тик истечения скорость действия НЕ пишется (сразу recovery-блендинг).
func tick_driven(delta: float) -> void:
	action_timer -= delta
	if action_timer <= 0.0:
		is_active = false
		action_ended.emit() # shell выставит mobility_recovery_active
		return
	body.velocity.x = action_velocity_xz.x
	body.velocity.z = action_velocity_xz.y
