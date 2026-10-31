extends Node
class_name LeapComponent
## Засада (ambush leap) Ренгара, Q7.14 — перенос из StateComponent без
## изменения формул: постоянная время-к-цели (leap_time_to_target), кламп
## скорости [min, max], дальность leap_max_range, проверка «скрыт + смотрю на
## цель» (FACING_THRESHOLD от базиса корпуса — визуальный фейсинг, не yaw камеры),
## выход из стелса на старте, прерывание столкновением (velocity *= 0.4),
## завершение по приземлении + перепроверка кустов.
## Профиль: can_leap=false → засада не срабатывает (обычный прыжок остаётся
## за GroundLocomotion, если can_jump).

const LOG_TAG := "Состояние"
const FACING_THRESHOLD: float = 0.98

@export var leap_range: float = 12.0
@export var leap_time_to_target: float = 0.45  # секунды полёта до цели (постоянное время)
@export var min_leap_speed: float = 6.0        # мин. скорость (короткие дистанции)
@export var max_leap_speed: float = 8.0        # макс. скорость (длинные дистанции, баланс)
@export var leap_max_range: float = 10.0       # макс. дистанция срабатывания засады
## Цели засады — data-driven список групп (legacy проблема 5: манекен
## тренировочный, поэтому получает тот же leap, что и враг).
@export var leap_target_groups: Array[String] = ["enemy", "dummy_enemy"]
@export var invert_forward_input: bool = false

var shell: MovementShell = null
var body: CharacterBody3D = null
var is_leaping := false
var leap_intended_dir := Vector3.ZERO


func setup(p_shell: MovementShell) -> void:
	shell = p_shell
	body = p_shell.owner_body


func set_leaping(value: bool) -> void:
	if is_leaping != value:
		is_leaping = value
		if value:
			# При прыжке выходим из стелса (legacy).
			if shell.stealth != null:
				shell.stealth.set_stealthed(false)
		if shell != null:
			shell.state_changed.emit("leap", value)


func get_leap_direction() -> Vector3:
	return leap_intended_dir.normalized()


## Попытка превратить запрос прыжка в засаду. true = запрос потреблён засадой
## (обычный прыжок не нужен). Порядок проверок — legacy process_jump_request.
func try_consume_jump(intent: MovementIntent) -> bool:
	if is_leaping or body == null:
		return false
	# Допуск «почти на земле» (legacy: не было на полу в прошлом тике и нет
	# сейчас — запрос отбрасывается ЦЕЛИКОМ, и засада, и прыжок).
	if not shell.was_on_floor and not body.is_on_floor():
		return false
	var leap_target := _find_nearest_leap_target()
	if leap_target == null:
		return false
	if shell.profile != null and not shell.profile.can_leap:
		GameLog.verbose(LOG_TAG, "ЗАСАДА_ОТКАЗ | reason=profile_capability")
		return false
	var stealthed := shell.stealth != null and shell.stealth.is_stealthed
	if not stealthed:
		return false
	var forward := -body.global_transform.basis.z.normalized()
	if invert_forward_input:
		forward = -forward
	var dir_to_target := (leap_target.global_position - body.global_position).normalized()
	if forward.dot(dir_to_target) <= FACING_THRESHOLD:
		return false
	if leap_target.global_position.distance_to(body.global_position) > leap_max_range:
		return false
	_start_ambush(leap_target)
	return true


## Пост-обработка move_and_slide (shell вызывает каждый тик): столкновение в
## полёте гасит засаду (legacy Player3d шаг 6: set_leaping(false) + velocity *= 0.4).
func on_post_move(p_body: CharacterBody3D) -> void:
	if is_leaping and p_body.get_slide_collision_count() > 0:
		set_leaping(false)
		p_body.velocity *= 0.4


## Завершение по приземлении — вызывает locomotion-гейт «почти остановки»
## (legacy apply_gravity: on_floor и |vy| < 1.0).
func finish_landing() -> void:
	set_leaping(false)
	if shell.stealth != null:
		shell.stealth.recheck_bush_overlap()


func _start_ambush(target: Node3D) -> void:
	set_leaping(true)

	var dir := target.global_position - body.global_position
	dir.y = 0.0
	leap_intended_dir = dir.normalized()

	var dist := dir.length()
	var target_speed := dist / leap_time_to_target
	target_speed = clampf(target_speed, min_leap_speed, max_leap_speed)

	body.velocity.x = leap_intended_dir.x * target_speed
	body.velocity.z = leap_intended_dir.z * target_speed
	body.velocity.y = shell.profile.jump_force if shell.profile != null else 8.0
	GameLog.compact(LOG_TAG, "ЗАСАДА_СТАРТ | dist=%.2f | speed=%.2f" % [dist, target_speed])


func _find_nearest_leap_target() -> Node3D:
	var nearest: Node3D = null
	var min_dist: float = leap_range + 1.0
	for group_name in leap_target_groups:
		for e in body.get_tree().get_nodes_in_group(group_name):
			var d := body.global_position.distance_to((e as Node3D).global_position)
			if d < min_dist:
				min_dist = d
				nearest = e as Node3D
	return nearest
