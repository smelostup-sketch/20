class_name MovementIntent
extends RefCounted
## Намерение движения (Q7.14, унификация мувмента, Шаг 1).
## Единый контракт между провайдером намерения (игрок — PlayerIntentComponent
## из Input Map и камеры; ИИ — AIIntentComponent из EnemyController.move_state)
## и исполнителем (MovementShell + модуль локомоции). Зеркало контракта боевого
## ядра: провайдер ОБЯЗАН подавать намерение, исполнитель отказывает по своим
## правилам (owner-agnostic).
##
## Поля:
##   direction         — input-space Vector2: x = стрейф (+вправо/−влево),
##                       y = (+назад/−вперёд); в мир разрешается через Basis(UP, yaw).
##   yaw               — мировой угол (радианы) для разрешения направления и поворота корпуса.
##   has_yaw           — false = корпус НЕ поворачивать (свободный обзор камеры, нет цели у ИИ).
##   facing_locked     — true = не поворачивать корпус в этот тик (recovery врага —
##                       поворотом владеет анимация атаки; legacy-гейт сохранён).
##   speed_scale       — множитель скорости относительно профиля (отступление врага 0.65).
##   jump_requested    — одноразовый запрос прыжка/засады (потребляет MovementShell;
##                       приоритет у LeapComponent, иначе GroundLocomotion).
##   action_request    — "" | "dash" | "dodge" — одноразовый запрос действия;
##                       shell маршрутизирует в компонент способности (гейты — там).
##   action_dir        — направление действия в input-space (dash — из double-tap,
##                       dodge — из WASD+Q/E).
##   freeze_horizontal — горизонтальную скорость НЕ трогать (лок ввода игрока 0.1 с
##                       после урона — legacy-поведение apply_physics: ранний return).
##   snap_stop         — мгновенно обнулить горизонталь (стан/лок/блок/СТОП врага —
##                       legacy-поведение EnemyController, боевая читаемость).

var direction := Vector2.ZERO
var yaw := 0.0
var has_yaw := false
var facing_locked := false
var speed_scale := 1.0
var jump_requested := false
var action_request := ""
var action_dir := Vector2.ZERO
var freeze_horizontal := false
var snap_stop := false


func reset() -> void:
	direction = Vector2.ZERO
	yaw = 0.0
	has_yaw = false
	facing_locked = false
	speed_scale = 1.0
	jump_requested = false
	action_request = ""
	action_dir = Vector2.ZERO
	freeze_horizontal = false
	snap_stop = false
