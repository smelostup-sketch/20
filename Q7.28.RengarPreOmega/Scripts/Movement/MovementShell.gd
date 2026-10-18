extends Node
class_name MovementShell
## MovementShell (Q7.14, унификация мувмента Шаг 1) — эволюция StateComponent.
## Тонкая «раковина» движения, ЕДИНСТВЕННАЯ у любого существа (игрок, враг,
## манекен, будущая курица/грифон). Не знает ни про клавиатуру, ни про ИИ,
## ни про гравитацию напрямую:
##   1) принимает MovementIntent от провайдера (экспорт provider_path;
##      без провайдера — нулевое намерение: манекен стоит);
##   2) ЕДИНСТВЕННЫЙ писатель кинематики тела: rotation.y (политика фейсинга),
##      move_and_slide(); velocity пишут делегаты (локомоция/действия) по её приказу;
##   3) маршрутизирует одноразовые запросы (прыжок → засада/прыжок, dash/dodge →
##      компоненты способностей с их гейтами);
##   4) владеет состоянием пола (was_on_floor) и recovery-блендингом после рывков.
##
## Совместимость: предоставляет прежнюю поверхность StateComponent (свойства
## is_leaping/is_stealthed/…, set_stealthed/set_leaping, get_leap_direction,
## jump_requested, сигналы state_changed/action_started/action_ended) —
## потребители меняют только путь узла.
##
## Порядок тика (важно): провайдер намерения — УЗЕЛ РАНЬШЕ shell в дереве
## (родительский скрипт тела и провайдер тикают до shell); действие в полёте
## важнее freeze (legacy: dodge/dash ветка шла раньше лока ввода).

signal state_changed(state_name: String, value: bool)
signal action_started(dir: Vector2, type: int)
signal action_ended

const LOG_TAG := "Состояние"

@export var profile: CreatureProfile
@export var provider_path: NodePath          # IntentProvider (get_intent); пусто = стационар
@export var combat_path: NodePath = NodePath("../CombatComponent")
@export var attack_input_path: NodePath = NodePath("../AttackInputComponent")
## Множитель скорости экземпляра (body-экспорт character_speed_multiplier
## переносится сюда в _ready владельца — legacy-паттерн сохранён).
@export var speed_multiplier := 1.0

var owner_body: CharacterBody3D = null
var provider: Node = null
var combat: Node = null
var attack_input: Node = null
var locomotion: GroundLocomotion = null
var leap: LeapComponent = null
var stealth: StealthComponent = null
var mobility_actions: Array[MobilityAction] = []

var was_on_floor := false
var mobility_recovery_active := false
## Одноразовый флаг прыжка (совместимость с sim_leap и прежним контрактом;
## провайдер подаёт прыжок через intent.jump_requested — shell объединяет источники).
var jump_requested := false
## Точки расширения будущих режимов (legacy-контракт AttackInputComponent).
var is_climbing := false
var is_swimming := false

# --- совместимость: прежние свойства StateComponent (геттеры на компоненты) ---
var is_leaping: bool:
	get: return leap != null and leap.is_leaping
var is_stealthed: bool:
	get: return stealth != null and stealth.is_stealthed
var is_dodging: bool:
	get:
		for a in mobility_actions:
			if a.action_type == MobilityAction.ActionType.DODGE and a.is_active:
				return true
		return false
var is_dashing: bool:
	get:
		for a in mobility_actions:
			if a.action_type == MobilityAction.ActionType.DASH and a.is_active:
				return true
		return false


func _ready() -> void:
	owner_body = get_parent() as CharacterBody3D
	if owner_body == null:
		push_error("MovementShell должен быть потомком CharacterBody3D")
		return
	if profile == null:
		push_error("MovementShell: profile (CreatureProfile) не назначен — движение невозможно")
		return
	if provider_path != NodePath():
		provider = get_node_or_null(provider_path)
		if provider == null or not provider.has_method("get_intent"):
			push_warning("MovementShell: провайдер намерения '%s' не найден/без get_intent() — стационар" % provider_path)
			provider = null
	combat = get_node_or_null(combat_path)
	if attack_input_path != NodePath():
		attack_input = get_node_or_null(attack_input_path)
		if attack_input == null:
			# Нормально для врага/манекена: у них нет компонента ввода атаки.
			attack_input = null
	# Обход детей: локомоция и способности — СОСЕДИ внутри shell (единая точка сборки).
	for child in get_children():
		if child is GroundLocomotion:
			locomotion = child
			locomotion.setup(self)
		elif child is LeapComponent:
			leap = child
			leap.setup(self)
		elif child is StealthComponent:
			stealth = child
			stealth.setup(self)
		elif child is MobilityAction:
			var action := child as MobilityAction
			action.setup(self)
			mobility_actions.append(action)
			action.action_started.connect(_on_action_started)
			action.action_ended.connect(_on_action_ended)
	if locomotion == null:
		push_error("MovementShell: не найден GroundLocomotion среди детей")
	was_on_floor = owner_body.is_on_floor()


func _physics_process(delta: float) -> void:
	if owner_body == null or profile == null or locomotion == null:
		return

	# 1. НАМЕРЕНИЕ (провайдер обязан; без провайдера — нулевое: манекен/стационар)
	var intent: MovementIntent
	if provider != null:
		intent = provider.get_intent()
	else:
		intent = _zero_intent()
	# Совмещение источников прыжка (intent + compat-флаг sim_leap/legacy).
	if jump_requested:
		intent.jump_requested = true
	jump_requested = false

	# 2. Засада имеет приоритет у прыжка (legacy process_jump_request).
	if intent.jump_requested and leap != null:
		if leap.try_consume_jump(intent):
			intent.jump_requested = false

	# 3. Маршрутизация одноразовых действий (гейты и отказы — в компонентах).
	match intent.action_request:
		"dash":
			_route_action(MobilityAction.ActionType.DASH, intent)
		"dodge":
			_route_action(MobilityAction.ActionType.DODGE, intent)

	# 4. Кинематика: действие в полёте важнее freeze (legacy-порядок веток).
	var driven := _tick_actions(delta)
	var mode := GroundLocomotion.HorizontalMode.NORMAL
	if driven or is_leaping:
		mode = GroundLocomotion.HorizontalMode.DRIVEN
	elif intent.freeze_horizontal:
		mode = GroundLocomotion.HorizontalMode.FROZEN
	elif intent.snap_stop:
		mode = GroundLocomotion.HorizontalMode.SNAPPED
	locomotion.apply(delta, intent, mode, mobility_recovery_active)

	# 5. Фейсинг: единственный писатель rotation.y (политика — профиль).
	if intent.has_yaw and not intent.facing_locked:
		owner_body.rotation.y = lerp_angle(
			owner_body.rotation.y, intent.yaw,
			1.0 - exp(-profile.facing_rate * delta))

	# 6. ФИЗИКА (единственный move_and_slide владельца движения).
	owner_body.move_and_slide()

	# 7. Пост-обработка: прерывание засады столкновением (legacy Player3d шаг 6).
	if leap != null:
		leap.on_post_move(owner_body)

	# 8. Кэш пола для следующего тика (legacy cache_floor_state).
	was_on_floor = owner_body.is_on_floor()

	# 9. Выход из recovery-блендинга рывка (legacy: порог 0.10 м/с).
	if mobility_recovery_active:
		var desired := locomotion.desired_horizontal_speed(intent)
		var current := Vector2(owner_body.velocity.x, owner_body.velocity.z).length()
		if absf(current - desired) <= 0.10:
			mobility_recovery_active = false


# === ВНЕШНИЙ API СОВМЕСТИМОСТИ (прежний StateComponent) ===
func set_stealthed(value: bool) -> void:
	if stealth != null:
		stealth.set_stealthed(value)


func get_is_stealthed() -> bool:
	return is_stealthed


func get_is_leaping() -> bool:
	return is_leaping


func get_leap_direction() -> Vector3:
	return leap.get_leap_direction() if leap != null else Vector3.ZERO


func set_leaping(value: bool) -> void:
	if leap != null:
		leap.set_leaping(value)


## Единственный писатель кинематики: ВНЕШНИЕ импульсы (нокбэк от урона) идут
## через shell, а не прямой записью body.velocity (Q7.15, вердикт заказчика
## по самоотчёту п.2). Аддитивный импульс — для нокбэка игрока.
func apply_impulse(delta_velocity: Vector3) -> void:
	if owner_body != null:
		owner_body.velocity += delta_velocity


## Полная замена скорости внешним источником — для нокбэка врага
## (legacy-семантика: velocity = knock_dir * knockback_force).
func set_velocity_override(value: Vector3) -> void:
	if owner_body != null:
		owner_body.velocity = value


func is_mobility_busy() -> bool:
	for a in mobility_actions:
		if a.is_active:
			return true
	return false


func reset_jump_request() -> void:
	jump_requested = false


# === ВНУТРЕННЕЕ ===
func _route_action(type: int, intent: MovementIntent) -> void:
	for a in mobility_actions:
		if a.action_type == type:
			# yaw намерения валиден даже при has_yaw=false (free-look): legacy
			# _movement_basis() брал yaw камеры всегда — направление рывка/уклона
			# следует за взглядом, поворот корпуса при этом может быть остановлен.
			a.try_start(intent.action_dir, intent.yaw)
			return
	# Компонент способности не прикреплён = способности у существа нет (тихий отказ;
	# профильный отказ логирует сам компонент — здесь спама быть не должно).


func _tick_actions(delta: float) -> bool:
	var driven := false
	for a in mobility_actions:
		if a.is_active:
			a.tick_driven(delta)
			driven = true
	return driven


func _on_action_started(dir: Vector2, type: int) -> void:
	action_started.emit(dir, type)


func _on_action_ended() -> void:
	mobility_recovery_active = true
	action_ended.emit()


var _shared_zero_intent := MovementIntent.new()
func _zero_intent() -> MovementIntent:
	_shared_zero_intent.reset()
	return _shared_zero_intent
