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

const LOG_TAG := "ИИ"

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
	if has_target:
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
		_:
			# STOPPED / IDLE / прочее — мгновенная остановка (legacy else-ветка).
			_intent.snap_stop = true
	return _intent

