extends Node
class_name StealthComponent
## Стелс (кусты), Q7.14 — перенос из StateComponent без изменения поведения:
## подписка на Area3D группы "bush" (body_entered/exited), сверка по instance_id
## (надёжнее ==), флаг is_stealthed, сигнал через shell.state_changed.
## Профиль: can_stealth=false → вход в куст стелс не даёт (данные, не код).

const LOG_TAG := "Состояние"

var shell: MovementShell = null
var owner_body: CharacterBody3D = null
var is_stealthed := false
var my_instance_id: int = 0


func setup(p_shell: MovementShell) -> void:
	shell = p_shell
	owner_body = p_shell.owner_body
	my_instance_id = owner_body.get_instance_id()
	_connect_bush_signals()


func _connect_bush_signals() -> void:
	for bush in owner_body.get_tree().get_nodes_in_group("bush"):
		if bush is Area3D:
			# Защита от дублей при перезагрузке сцены (legacy).
			if bush.body_entered.is_connected(_on_bush_entered):
				bush.body_entered.disconnect(_on_bush_entered)
			if bush.body_exited.is_connected(_on_bush_exited):
				bush.body_exited.disconnect(_on_bush_exited)
			bush.body_entered.connect(_on_bush_entered)
			bush.body_exited.connect(_on_bush_exited)


func _on_bush_entered(body: Node3D) -> void:
	GameLog.verbose(LOG_TAG, "КУСТ_ВХОД | body_id=%d | my_id=%d" % [body.get_instance_id(), my_instance_id])
	if body.get_instance_id() != my_instance_id:
		return
	if shell.profile != null and not shell.profile.can_stealth:
		GameLog.verbose(LOG_TAG, "СТЕЛС_ОТКАЗ | reason=profile_capability")
		return
	set_stealthed(true)


func _on_bush_exited(body: Node3D) -> void:
	if body.get_instance_id() == my_instance_id:
		set_stealthed(false)


func set_stealthed(value: bool) -> void:
	if is_stealthed != value:
		is_stealthed = value
		if shell != null:
			shell.state_changed.emit("stealth", value)
		GameLog.compact(LOG_TAG, "СТЕЛС | %s" % ("ВКЛ" if value else "ВЫКЛ"))


## Перепроверка кустов по факту приземления (legacy _check_bush_overlap).
func recheck_bush_overlap() -> void:
	for bush in owner_body.get_tree().get_nodes_in_group("bush"):
		if bush is Area3D and bush.overlaps_body(owner_body):
			if shell.profile != null and not shell.profile.can_stealth:
				return
			set_stealthed(true)
			return
