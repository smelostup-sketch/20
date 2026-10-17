extends CharacterBody3D

@onready var health_comp: HealthComponent = $HealthComponent
@onready var shell: MovementShell = $MovementShell
@onready var combat_comp: CombatComponent = $CombatComponent
@onready var attack_input_comp: AttackInputComponent = $AttackInputComponent
@onready var stacks_comp: StacksComponent = $StacksComponent
@onready var animation_comp: MixamoAnimationComponent = $AnimationComponent

@export_group("Character Speed")
@export_range(0.1, 3.0, 0.05) var character_speed_multiplier: float = 1.0
@export_range(0.1, 3.0, 0.05) var attack_animation_speed: float = 3.75 # Ускорено на 200% от стандартного значения 1.25

func _ready() -> void:
	if shell:
		shell.speed_multiplier = character_speed_multiplier
	if animation_comp:
		animation_comp.movement_animation_speed = character_speed_multiplier
		animation_comp.attack_animation_speed = attack_animation_speed
		animation_comp.apply_runtime_speeds()
	if health_comp:
		health_comp.hp_changed.connect(_on_hp_changed)
		health_comp.died.connect(_on_player_died)
	if combat_comp:
		combat_comp.hit_detected.connect(_on_hit_detected)

# Движение (Q7.14, унификация): MovementShell само ведёт физический тик
# (намерение -> фейсинг -> локомоция/действия -> move_and_slide -> кэш пола),
# PlayerIntentComponent читает Input Map-экшены (включая "jump" для прыжка).
# Тело больше не оркестрирует шаги движения вручную.

func _input(event: InputEvent) -> void:
	# 1. Движение мыши (идёт всегда, распределяется внутри компонента).
	if event is InputEventMouseMotion:
		attack_input_comp.process_mouse_delta(event.relative)
		combat_comp.process_mouse_delta(event.relative)
		return

	# 2. Клавиатура: прыжок — Input Map-экшен "jump" (читает провайдер
	#    намерения в физтик-тик); тильда обрабатывается камерой.

	# 3. Мышь: боевые кнопки — Input Map-экшены "attack" (ЛКМ) и "block" (ПКМ),
	#    Q7.16 п.7A: ребайндимы, хардкод кнопок устранён. Поток MouseMotion выше —
	#    сырые дельты для жестов (и будущих финтов: дуговых траекторий оружия) —
	#    не затрагивается. Извлечение CombatInputComponent (п.7C) — в фазу финтов.
	if event is InputEventMouseButton:
		if event.is_action_pressed("block"):
			if attack_input_comp.request_block():
				combat_comp.set_block_input_pressed()
		elif event.is_action_released("block"):
			combat_comp.set_block_input_released()
		elif event.is_action_pressed("attack"):
			attack_input_comp.press_attack()
		elif event.is_action_released("attack"):
			attack_input_comp.release_attack()

# === ДЕЛЕГАТЫ (НЕ УДАЛЯТЬ) ===
func take_dmg(amount: float, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	stacks_comp.register_combat_event() # Получение урона = бой
	if combat_comp: combat_comp.player_take_dmg(amount, attacker_pos)

func is_blocking_active(enemy_attack_dir: String) -> bool:
	return combat_comp.is_blocking_active(enemy_attack_dir)

func notify_successful_block(direction: String) -> void:
	if combat_comp != null:
		combat_comp.notify_successful_block(direction)

func _on_hp_changed(current: float, max_hp: float) -> void:
	if not is_inside_tree():
		return
	var ui = get_tree().get_first_node_in_group("player_ui")
	if ui and ui.has_method("set_hp"): ui.set_hp(current, max_hp)

func _on_player_died() -> void:
	GameLog.compact("Игрок", "СМЕРТЬ")
	set_process(false); set_physics_process(false)
	get_tree().reload_current_scene()

func _on_hit_detected(_target: Node) -> void:
	stacks_comp.register_combat_event() # Нанесение урона = бой
	if combat_comp.last_attack_was_in_leap:
		stacks_comp.add_purple()
	else:
		stacks_comp.add_gold()
	combat_comp.last_attack_was_in_leap = false
