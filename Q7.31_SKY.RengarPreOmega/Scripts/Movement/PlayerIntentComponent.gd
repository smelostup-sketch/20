extends Node
class_name PlayerIntentComponent
## Провайдер намерения движения ИГРОКА (Q7.14, унификация U2/U3).
## Единственный компонент движения, который знает про устройство ввода:
## читает Input Map-экшены (move_forward/back/left/right, jump, dodge_left,
## dodge_right — никакого хардкода KEY_*), детектит double-tap рывка и
## публикует MovementIntent для MovementShell. Игровую логику (гейты, физику)
## НЕ содержит — отказы живут в исполнителях.
##
## Родословна логики: перенос 1:1 из legacy StateComponent.process()
## (дискретная матрица 8 направлений через sign(), double-tap окно 0.25 с,
## Q/E как модификаторы уклона к WASD) и _movement_basis() Q7.12
## (yaw камеры всегда; free-look останавливает только поворот КОРПУСА —
## направление движения/рывков следует за взглядом, как было).

const LOG_TAG := "Ввод"

@export var camera_path: NodePath = NodePath("../../Camera3D")
@export var combat_path: NodePath = NodePath("../CombatComponent")
@export_range(0.05, 1.0, 0.01) var double_tap_window := 0.25 # legacy StateComponent

var camera: Node = null
var combat: Node = null
var _intent := MovementIntent.new()

# Фрейм-буфер double-tap (legacy: _last_tap_time/_last_tap_key)
var _last_tap_time := -999.0
var _last_tap_action := ""


func _ready() -> void:
	if camera_path != NodePath():
		camera = get_node_or_null(camera_path)
		if camera == null:
			push_warning("PlayerIntentComponent: камера '%s' не найдена — движение без поворота корпуса" % camera_path)
	if combat_path != NodePath():
		combat = get_node_or_null(combat_path)


func get_intent() -> MovementIntent:
	_intent.reset()

	# 1. ДИСКРЕТНАЯ МАТРИЦА 8 направлений (legacy шаг 4: sign() → ровно 8 клеток).
	var raw := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		raw.x -= 1.0
	if Input.is_action_pressed("move_right"):
		raw.x += 1.0
	if Input.is_action_pressed("move_forward"):
		raw.y -= 1.0
	if Input.is_action_pressed("move_back"):
		raw.y += 1.0
	if raw != Vector2.ZERO:
		_intent.direction = Vector2(signf(raw.x), signf(raw.y)).normalized()

	# 2. YAW камеры: направление движения/рывков — всегда по взгляду;
	#    поворот корпуса — только вне свободного обзора (free-look, тильда).
	if camera != null:
		_intent.yaw = float(camera.get_view_yaw())
		_intent.has_yaw = not camera.is_free_look_active()

	# 3. Прыжок: одноразовый (just_pressed), потребляет MovementShell.
	_intent.jump_requested = Input.is_action_just_pressed("jump")

	# 4. Лок ввода после урона: горизонталь не трогаем (legacy freeze),
	#    НО действие в полёте важнее лока — приоритет у shell (legacy-порядок).
	if combat != null and combat.is_input_locked:
		_intent.freeze_horizontal = true

	# 5. УКЛОН: dodge_left/dodge_right как модификаторы направления к WASD
	#    (legacy шаг 5: без зажатой базы WASD — игнор; Q/E сдвигают ось X).
	if Input.is_action_just_pressed("dodge_left") or Input.is_action_just_pressed("dodge_right"):
		var base := Vector2.ZERO
		if Input.is_action_pressed("move_left"):
			base.x -= 1.0
		if Input.is_action_pressed("move_right"):
			base.x += 1.0
		if Input.is_action_pressed("move_forward"):
			base.y -= 1.0
		if Input.is_action_pressed("move_back"):
			base.y += 1.0
		if base != Vector2.ZERO:
			var dodge_input := base
			if Input.is_action_pressed("dodge_left"):
				dodge_input.x -= 1.0
			if Input.is_action_pressed("dodge_right"):
				dodge_input.x += 1.0
			_intent.action_request = "dodge"
			_intent.action_dir = dodge_input.normalized()

	# 6. РЫВОК: double-tap одного из направлений (legacy шаг 6). Dash всегда
	#    один из четырёх направлений double-tap, даже если зажата другая клавиша.
	if _intent.action_request == "":
		var tapped := ""
		# Приоритет опроса — legacy StateComponent: W > A > S > D.
		if Input.is_action_just_pressed("move_forward"):
			tapped = "move_forward"
		elif Input.is_action_just_pressed("move_left"):
			tapped = "move_left"
		elif Input.is_action_just_pressed("move_back"):
			tapped = "move_back"
		elif Input.is_action_just_pressed("move_right"):
			tapped = "move_right"
		if tapped != "":
			var now := Time.get_ticks_msec() * 0.001
			if tapped == _last_tap_action and (now - _last_tap_time) < double_tap_window:
				_intent.action_request = "dash"
				_intent.action_dir = _cardinal_of(tapped)
				_last_tap_time = 0.0
				_last_tap_action = ""
			else:
				_last_tap_time = now
				_last_tap_action = tapped

	return _intent


func _cardinal_of(action_name: String) -> Vector2:
	match action_name:
		"move_forward":
			return Vector2(0.0, -1.0)
		"move_back":
			return Vector2(0.0, 1.0)
		"move_left":
			return Vector2(-1.0, 0.0)
		"move_right":
			return Vector2(1.0, 0.0)
	return Vector2(0.0, -1.0)
