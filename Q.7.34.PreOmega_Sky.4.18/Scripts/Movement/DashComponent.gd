extends MobilityAction
class_name DashComponent
## Рывок (double-tap направления), Q7.14. Триггер — у провайдера намерения
## (PlayerIntentComponent детектит double-tap по Input Map); здесь — исполнение
## и гейты. Числа — прежние дефолты StateComponent: dash_speed=18, dash_duration=0.15
## (родословная: legacy-экспорты, перенос без ретюнинга).

func _init() -> void:
	action_type = ActionType.DASH
	action_speed = 18.0
	action_duration = 0.15


func action_label() -> String:
	return "РЫВОК"


func _profile_allows() -> bool:
	return shell.profile == null or shell.profile.can_dash


func _on_started(_dir_input: Vector2) -> void:
	# Dash — утверждённая отмена атаки (legacy request_dash_cancel; выполняется
	# только когда сам dash прошёл все гейты).
	if shell.attack_input != null:
		shell.attack_input.request_dash_cancel()
