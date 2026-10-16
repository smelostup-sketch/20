extends CharacterBody3D

@export_group("Dummy Enemy Settings")
@export var block_chance := 0.95  # 95% шанс заблокировать атаку
@export var dummy_color := Color(1.0, 1.0, 0.0, 1.0)  # Желтый цвет

@onready var health_comp: HealthComponent = $HealthComponent
@onready var combat_comp: CombatComponent = $CombatComponent
@onready var animation_comp: EnemyAnimationComponent = $AnimationComponent
@onready var model_tint: ModelTintComponent = $ModelTintComponent
@onready var damage_label: DamageLabelComponent = $DamageLabelComponent

var player: Node3D = null

func _ready() -> void:
	# Устанавливаем желтый цвет модели
	if model_tint:
		model_tint.set_tint(dummy_color)
	
	# Применяем цвет к HP бару если есть
	_create_dummy_hp_bar()
	
	# Манекен не должен иметь гравитации и движения
	velocity = Vector3.ZERO

func _physics_process(_delta: float) -> void:
	# Манекен никогда не двигается: MovementShell БЕЗ провайдера намерения
	# (нулевой intent) держит его на месте, гравитация — на полу (Q7.14).
	# Контроллер обновляет только тренировочный индикатор.
	_update_dummy_indicator()

func _create_dummy_hp_bar() -> void:
	var hp_bar = MeshInstance3D.new()
	hp_bar.name = "DummyHPBar"
	var box = BoxMesh.new()
	box.size = Vector3(0.6, 0.08, 0.05)
	hp_bar.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 0.0)  # Желтый HP бар
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hp_bar.material_override = mat
	hp_bar.position = Vector3(0, 2.4, 0)
	add_child(hp_bar)

func _update_dummy_indicator() -> void:
	if not has_node("StateLabel"):
		var lbl = Label3D.new()
		lbl.name = "StateLabel"
		lbl.font_size = 32
		lbl.outline_size = 2
		lbl.no_depth_test = true
		lbl.position = Vector3(0, 2.6, 0)
		lbl.modulate = Color(1.0, 1.0, 0.0, 1.0)  # Желтый текст
		add_child(lbl)
	
	var lbl = get_node("StateLabel")
	if lbl:
		if combat_comp and combat_comp.enemy_block_active:
			lbl.text = "🛡️"
		else:
			lbl.text = "🎯"  # Манекен готов к тренировке
		
		# Поворот к камере
		var cam = get_viewport().get_camera_3d()
		if cam:
			lbl.global_rotation.y = cam.global_rotation.y

func is_blocking_active(player_attack_direction: String) -> bool:
	# Манекен блокирует с высоким шансом
	if combat_comp == null:
		return false
	
	# 95% шанс блока
	if randf() < block_chance:
		combat_comp.activate_enemy_block(_get_random_block_direction())
		return combat_comp.is_blocking_active(player_attack_direction)
	
	return false

func _get_random_block_direction() -> String:
	var directions = ["LEFT", "RIGHT", "UP"]
	return directions[randi() % directions.size()]

func notify_successful_block(direction: String) -> void:
	if combat_comp != null:
		combat_comp.notify_successful_block(direction)

func take_dmg(amount: float, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	# Блок решается ОДИН раз — в контактном обработчике ядра
	# (is_blocking_active с реальным направлением атаки); take_dmg вызывается
	# только когда блок НЕ сработал. Прежний ролл is_blocking_active("") здесь
	# был всегда ложен (BLOCK_RESPONSE[""] не существует), но побочно включал
	# enemy_block на каждый урон — двойной ролл убран (Q7.13, чистка п.5).
	
	if health_comp and not health_comp.is_dead:
		if damage_label:
			damage_label.spawn(int(amount))
		health_comp.take_dmg(amount, attacker_pos)
		GameLog.compact("Манекен", "УРОН | amount=%.1f" % amount)
