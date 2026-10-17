extends MobilityAction
class_name DodgeComponent
## Уклон (Q/E как модификаторы направления к WASD), Q7.14. Триггер и сбор
## направления — у провайдера намерения; здесь — исполнение и гейты.
## Числа — прежние дефолты StateComponent: dodge_speed=12, dodge_duration=0.2
## (родословная: legacy-экспорты, перенос без ретюнинга).

func _init() -> void:
	action_type = ActionType.DODGE
	action_speed = 12.0
	action_duration = 0.2


func action_label() -> String:
	return "УКЛОН"


func _profile_allows() -> bool:
	return shell.profile == null or shell.profile.can_dodge


func _pre_start_gate() -> bool:
	# Во время START_DELAY или ATTACKING dodge не запускается и НЕ отменяет
	# текущую атаку (legacy-контракт AttackInputComponent.blocks_dodge_start).
	if shell.attack_input != null and shell.attack_input.blocks_dodge_start():
		GameLog.verbose(LOG_TAG, "УКЛОН_ОТКАЗ | reason=attack_active | attack_state=%s"
			% shell.attack_input.get_state_name())
		return false
	# Отложенный выбор направления атаки отменяется (legacy: до фиксации
	# направления атаки ещё нет — dodge её не прерывает).
	if shell.attack_input != null:
		shell.attack_input.cancel_pending_direction_for_dodge()
	return true
