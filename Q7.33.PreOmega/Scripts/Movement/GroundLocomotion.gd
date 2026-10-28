extends Node
class_name GroundLocomotion
## Наземная локомоция (Q7.14, Шаг 1) — СЪЁМНЫЙ модуль локомоции: гравитация,
## разгон/торможение, импульс прыжка. Летающие/плавающие существа получают
## Flight/SwimLocomotion ВМЕСТО этого модуля (Шаг 2; seam — интерфейс
## setup(shell) + apply(delta, intent, mode, recovery_active)).
## Не читает ввод и не вызывает move_and_slide — только пишет velocity владельца
## по намерению и профилю (единственный писатель кинематики — MovementShell).

enum HorizontalMode {
	NORMAL,  # разгон/торможение по намерению (векторный move_toward — фикс Q7.12)
	DRIVEN,  # горизонталь ведёт действие/засада — здесь только гравитация
	FROZEN,  # лок ввода: горизонталь НЕ трогаем (legacy ранний return apply_physics)
	SNAPPED, # мгновенный ноль по горизонтали (стан/лок/блок/стоп врага — legacy)
}

var shell: MovementShell = null
var body: CharacterBody3D = null
## Профиль читается ДИНАМИЧЕСКИ из shell (смена аватара = подмена profile
## на лету; кэш здесь сломал бы «куриный» тест — ADR, критерий приёмки 3).
var profile: CreatureProfile:
	get: return shell.profile if shell != null else null


func setup(p_shell: MovementShell) -> void:
	shell = p_shell
	body = p_shell.owner_body


func apply(delta: float, intent: MovementIntent, mode: int, recovery_active: bool) -> void:
	if body == null or profile == null:
		return
	match mode:
		HorizontalMode.SNAPPED:
			body.velocity.x = 0.0
			body.velocity.z = 0.0
		HorizontalMode.NORMAL:
			_apply_horizontal(delta, intent, recovery_active)
		_:
			pass # DRIVEN/FROZEN: горизонталь принадлежит действию/заморожена
	_apply_gravity(delta)
	# Завершение засады по факту «почти остановки» на полу (legacy apply_gravity:
	# on_floor и |vy| < 1.0; состояние пола — с прошлого тика, как и раньше).
	if shell.leap != null and shell.leap.is_leaping and body.is_on_floor() and absf(body.velocity.y) < 1.0:
		shell.leap.finish_landing()
	if intent.jump_requested and profile.can_jump and _can_jump_now():
		body.velocity.y = profile.jump_force


## Целевая горизонтальная скорость для текущего намерения (порог выхода из
## recovery-блендинга рывка считает shell — legacy desired_horizontal_speed).
func desired_horizontal_speed(intent: MovementIntent) -> float:
	if intent.direction == Vector2.ZERO or profile == null:
		return 0.0
	return profile.speed * shell.speed_multiplier * intent.speed_scale


func _apply_horizontal(delta: float, intent: MovementIntent, recovery_active: bool) -> void:
	# Векторный move_toward вместо поосевого (родословна — фикс Q7.12,
	# diag_move MOUSE_OFFSET: поосевое гашение закручивало стоп до 35°).
	var moving := intent.direction != Vector2.ZERO
	var target := Vector2.ZERO
	if moving:
		var dir3 := Basis(Vector3.UP, intent.yaw) * Vector3(intent.direction.x, 0.0, intent.direction.y)
		dir3.y = 0.0
		dir3 = dir3.normalized()
		target = Vector2(dir3.x, dir3.z) * desired_horizontal_speed(intent)
	var rate: float
	if recovery_active:
		rate = profile.action_exit_deceleration
	elif moving:
		rate = profile.acceleration
	else:
		rate = profile.deceleration
	var v := Vector2(body.velocity.x, body.velocity.z).move_toward(target, rate * delta)
	body.velocity.x = v.x
	body.velocity.z = v.y


func _apply_gravity(delta: float) -> void:
	if not body.is_on_floor():
		body.velocity.y -= profile.gravity * delta
	else:
		if body.velocity.y < 0.0:
			body.velocity.y = move_toward(body.velocity.y, 0.0, profile.landing_damping * delta)


func _can_jump_now() -> bool:
	# Legacy-контракт process_jump_request: прыжок разрешён, если были на полу
	# в прошлом тике ИЛИ на полу сейчас (допуск «почти на земле», убирает
	# 1-кадровые отмены). Запрошенный в полёте прыжок одноразово отбрасывается
	# (см. changes.md Q7.14, микро-изменение 7a).
	return body.is_on_floor() or shell.was_on_floor
