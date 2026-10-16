extends Node
class_name AIIntentComponent
## Провайдер намерения движения ВРАГА (Q7.14, унификация U1).
## Читает решение контроллера (EnemyController.move_state — «намерения движения»,
## контракт Q…_2) и боевое состояние ядра, публикует MovementIntent для того же
## MovementShell, что и у игрока. ИИ НЕ перестраивается (заморожен до очереди 3):
## UtilityAI/Perception/Memory и логика решений остаются где были.
##
## Родословна поведения: перенос 1:1 веток движения legacy EnemyController:
##   стан/лок ввода/блок врага → мгновенный ноль (intent.snap_stop);
##   CHASE → направление к игроку, speed_scale 1.0;
##   RETREAT → направление utility (или ноль), speed_scale = retreat_speed_multiplier;
##   STOPPED/IDLE → мгновенный ноль (боевая читаемость телеграфа);
##   поворот корпуса к игроку — yaw = atan2(dir.x, dir.z) (legacy-формула),
##   во время recovery поворот заблокирован (legacy-гейт «if not is_recovery»).
## B3 (Q7.21): состояния поиска INVESTIGATE/SEARCH/AMBUSH_WAIT/BLIND_STRIKE —
##   рулёжка «к точке» и орбита (касательная + радиальная коррекция ORBIT_GAIN);
##   фейсинг в поиске — к ЦЕЛИ ПОИСКА (last_seen/куст/центр орбиты), не к
##   фактической позиции скрытого игрока (честность, adr §B3); speed_scale =
##   profile.search_speed_scale; цель/центр/радиус/holding публикует мозг.

const LOG_TAG := "ИИ"
## B3: коэффициент радиальной коррекции орбиты: desired = tangent +
## radial_norm * clamp((r_target − d) * ORBIT_GAIN, ±1). Родословная: 1.0 =
## равный вес касательной и коррекции — сходится на орбиту за ~четверть круга
## (замер стендом sim_ai_bush S3: к концу окна r = patrol_radius ± 1.0 м).
const ORBIT_GAIN := 1.0
## Касательная орбиты = radial, повёрнутый на +90° вокруг Y (фиксированное
## направление обхода — детерминизм бенчей, adr §4; окружность симметрична).

@export var combat_path: NodePath = NodePath("../CombatComponent")
## Источник решений (Q7.17, Фаза A): move_state и направление отхода публикует
## AIBrainComponent (прежде читали EnemyController напрямую).
@export var brain_path: NodePath = NodePath("../AIBrainComponent")
## Множитель скорости отступления (legacy-экспорт EnemyController.retreat_speed_multiplier).
@export_range(0.1, 2.0, 0.01) var retreat_speed_multiplier := 0.65

var brain: Node = null
var combat: Node = null
var _intent := MovementIntent.new()


func _ready() -> void:
	brain = get_node_or_null(brain_path)
	combat = get_node_or_null(combat_path)
	if brain == null or not "move_state" in brain:
		push_error("AIIntentComponent: не найден источник решений с move_state (AIBrainComponent)")


func get_intent() -> MovementIntent:
	_intent.reset()
	var body := get_parent() as CharacterBody3D
	if body == null:
		return _intent

	# 1. Приоритетные состояния: стан / лок ввода / активный блок врага —
	#    мгновенная остановка (legacy ветки с velocity=0 и move_and_slide).
	if combat != null and (combat.stun_timer > 0.0 or combat.is_input_locked or combat.enemy_block_active):
		_intent.snap_stop = true
		return _intent

	# 2. Намерение движения из решения контроллера.
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var move_state: String = brain.move_state
	# Фейсинг — к игроку во всех неблокированных состояниях (legacy: поворот
	# работал в CHASE/RETREAT/STOPPED/IDLE, гейт — только recovery).
	# ЕДИНАЯ КОНВЕНЦИЯ (Q7.15): вперёд у всех существ = −Z корпуса; yaw «смотреть
	# на цель» = atan2(−dx, −dz). EnemyVisual развёрнут на 180° в сцене (как
	# VisualModel игрока), поэтому мировая картинка идентична прежней.
	# Родословна: Q7.14 rev.1 — инверсия погони из-за разнобоя конвенций
	# (враг legacy: +Z к игроку, input-space «вперёд» = −Y); rev.2 — локальная
	# заплатка (0,+1); Q7.15 — унификация, «вперёд» снова универсальное (0,−1).
	var yaw := 0.0
	var has_facing := false
	var has_target := player != null and is_instance_valid(player)
	# B3: в состояниях поиска фейсинг — к ЦЕЛИ ПОИСКА (last_seen / куст / центр
	# орбиты), НЕ к фактической позиции скрытого игрока: поворот корпуса выдал
	# бы его (нечестно — нарушение контракта восприятия adr §B3).
	var face_point: Variant = null
	match move_state:
		"INVESTIGATE", "SEARCH", "AMBUSH_WAIT", "BLIND_STRIKE":
			if brain.has_method("get_facing_point"):
				face_point = brain.get_facing_point()
	if face_point != null:
		var dir_f: Vector3 = face_point - body.global_position
		dir_f.y = 0.0
		if dir_f.length() > 0.01:
			dir_f = dir_f.normalized()
			yaw = atan2(-dir_f.x, -dir_f.z) # та же единая формула: −Z корпуса к цели
			has_facing = true
			_intent.yaw = yaw
			_intent.has_yaw = true
			_intent.facing_locked = combat != null and combat.is_recovery
	elif has_target:
		var dir_p := player.global_position - body.global_position
		dir_p.y = 0.0
		if dir_p.length() > 0.01:
			dir_p = dir_p.normalized()
			yaw = atan2(-dir_p.x, -dir_p.z) # единая формула: −Z корпуса к цели
			has_facing = true
			_intent.yaw = yaw
			_intent.has_yaw = true
			_intent.facing_locked = combat != null and combat.is_recovery
	match move_state:
		"CHASE":
			if has_facing:
				_intent.direction = Vector2(0.0, -1.0) # вперёд к игроку (единая конвенция −Z)
			else:
				# Цель ровно под/над врагом: горизонталь вырождена — стоим
				# (legacy «полз» со скоростью ≈ 0 из-за неренормализации y).
				_intent.snap_stop = true
		"RETREAT":
			var retreat_dir := Vector3.ZERO
			if brain.has_method("get_retreat_direction"):
				retreat_dir = brain.get_retreat_direction()
			retreat_dir.y = 0.0
			if retreat_dir.length() > 0.01:
				retreat_dir = retreat_dir.normalized()
				# Направление в input-space ЕДИНОГО yaw намерения (иначе локомоция
				# разрешит вектор в другой базе): local = inverse(yaw) * world.
				var local := Basis(Vector3.UP, yaw).inverse() * retreat_dir
				_intent.direction = Vector2(local.x, local.z)
				_intent.speed_scale = retreat_speed_multiplier
			else:
				_intent.snap_stop = true # без utility-направления отступать некуда
		"INVESTIGATE":
			# B3: к последней видимой точке / краю куста (цель публикует мозг).
			# Фейсинг уже смотрит на ту же точку → движение «вперёд» (как CHASE).
			if has_facing:
				_intent.direction = Vector2(0.0, -1.0)
				_intent.speed_scale = _search_speed_scale()
			else:
				_intent.snap_stop = true # точка прямо под врагом — вырождение
		"BLIND_STRIKE":
			# B3: подход к краю куста, затем изготовка/удар («атакующий стоит» —
			# та же семантика snap_stop, что у STOPPED; махом владеет анимация).
			if brain.has_method("is_search_holding") and brain.is_search_holding():
				_intent.snap_stop = true
			elif has_facing:
				_intent.direction = Vector2(0.0, -1.0)
				_intent.speed_scale = _search_speed_scale()
			else:
				_intent.snap_stop = true
		"AMBUSH_WAIT":
			# B3: засада у края куста — стоять, фейсинг к кусту (выше).
			_intent.snap_stop = true
		"SEARCH":
			# B3: патруль-орбита. Мировой вектор: касательная вокруг центра +
			# радиальная коррекция до patrol_radius; в input-space ЕДИНОГО yaw
			# (фейсинг к центру — «следит за кустом, шагая боком»; паттерн
			# преобразования — тот же, что в RETREAT).
			var center := body.global_position
			var radius := 4.0
			if brain.has_method("get_orbit_center"):
				center = brain.get_orbit_center()
			if brain.has_method("get_orbit_radius"):
				radius = brain.get_orbit_radius()
			var radial := body.global_position - center
			radial.y = 0.0
			var d := radial.length()
			if d < 0.05:
				# Вырождение (враг ровно в центре орбиты, например last_seen без
				# куста): выталкиваем вдоль форварда корпуса — на след. тике d > 0.
				radial = -body.global_transform.basis.z
				radial.y = 0.0
				if radial.length() < 0.01:
					radial = Vector3(0.0, 0.0, 1.0)
				d = radial.length()
			var radial_norm := radial / d
			var tangent := Vector3(-radial_norm.z, 0.0, radial_norm.x) # +90° вокруг Y
			var correction := radial_norm * clampf((radius - d) * ORBIT_GAIN, -1.0, 1.0)
			var desired := tangent + correction
			if desired.length() < 0.01:
				desired = tangent
			desired = desired.normalized()
			var local_o := Basis(Vector3.UP, yaw).inverse() * desired
			_intent.direction = Vector2(local_o.x, local_o.z)
			_intent.speed_scale = _search_speed_scale()
		_:
			# STOPPED / IDLE / прочее — мгновенная остановка (legacy else-ветка).
			_intent.snap_stop = true
	return _intent


## Множитель скорости состояний поиска (ручка профиля — данные; 1.0 = CHASE).
func _search_speed_scale() -> float:
	if brain != null and brain.get("profile") != null:
		var scale_value: Variant = (brain.get("profile") as Resource).get("search_speed_scale")
		if scale_value != null:
			return float(scale_value)
	return 1.0

