extends CharacterBody3D

# Разделение труда (Q7.17, Фаза A ИИ):
#   решения (move_state, намерение атаки по исходам ядра) — AIBrainComponent;
#   движение — MovementShell через AIIntentComponent ( CreatureProfile);
#   исполнение атаки/урон/блок/стан — CombatComponent (единое ядро);
#   контроллер — клей: анимационные множители, UI (полоска/индикатор/телеграф),
#   делегаты урона и блока. Legacy-экспорты detection_range/stop_distance/
#   utility_ai_enabled переехали (мозг / UtilityAI.enabled) — без двойных флагов.

@export_group("Character Speed")
@export_range(0.1, 3.0, 0.05) var character_speed_multiplier: float = 1.0
@export_range(0.1, 3.0, 0.05) var attack_animation_speed: float = 1.0

@onready var health_comp: HealthComponent = $HealthComponent
@onready var shell: MovementShell = $MovementShell
@onready var combat_comp: CombatComponent = $CombatComponent
@onready var brain: AIBrainComponent = $AIBrainComponent
@onready var animation_comp: EnemyAnimationComponent = $AnimationComponent
@onready var damage_label: DamageLabelComponent = $DamageLabelComponent

var telegraph_label: Label3D = null
var hp_bar: MeshInstance3D = null

func _ready() -> void:
	if shell:
		shell.speed_multiplier = character_speed_multiplier
	if animation_comp:
		animation_comp.movement_animation_speed = character_speed_multiplier
		animation_comp.attack_animation_speed = attack_animation_speed
		animation_comp.apply_runtime_speeds()
	_create_enemy_hp_bar()
	_create_telegraph_label()
	if health_comp:
		health_comp.hp_changed.connect(_on_hp_changed)
		health_comp.died.connect(_on_enemy_died)

func _physics_process(_delta: float) -> void:
	# Q7.17 (Фаза A): решения — в AIBrainComponent (ждут исходы ядра), движение —
	# в MovementShell через AIIntentComponent. Контроллер обновляет только UI.
	# Микро-изменение (задокументировано в changes.md): телеграф обновляется и в
	# стане — legacy оставлял устаревшую ⚡ после прерванной ударом атаки
	# (early-return ветки не вызывали _update_telegraph_visibility).
	_update_enemy_indicator()
	_update_enemy_hp_bar()
	_update_telegraph_visibility()

func _on_hp_changed(_current: float, _max_hp: float) -> void:
	_update_enemy_hp_bar()

func _on_enemy_died() -> void:
	GameLog.compact("Враг", "СМЕРТЬ")
	queue_free()

func is_blocking_active(player_attack_direction: String) -> bool:
	return combat_comp != null and combat_comp.is_blocking_active(player_attack_direction)

func notify_successful_block(direction: String) -> void:
	if combat_comp != null:
		combat_comp.notify_successful_block(direction)

# ДЕЛЕГАТ УРОНА С ВИЗУАЛЬНЫМИ ЭФФЕКТАМИ
func take_dmg(amount: float, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	if health_comp and health_comp.is_dead:
		return
	if combat_comp and combat_comp.is_input_locked:
		return
	_play_hit_flash()
	if damage_label:
		damage_label.spawn(int(amount))
	_play_impact_sound()
	_spawn_impact_particles()
	if health_comp:
		health_comp.take_dmg(amount, attacker_pos)
	if combat_comp:
		combat_comp.enemy_on_take_dmg(amount, attacker_pos)

func _create_enemy_hp_bar() -> void:
	hp_bar = MeshInstance3D.new()
	hp_bar.name = "EnemyHPBar"
	var box = BoxMesh.new()
	box.size = Vector3(0.6, 0.08, 0.05)
	hp_bar.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.85, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hp_bar.material_override = mat
	hp_bar.position = Vector3(0, 2.4, 0)
	add_child(hp_bar)

func _update_enemy_hp_bar() -> void:
	if not hp_bar or not health_comp:
		return
	var ratio = health_comp.get_hp_ratio()
	var box = hp_bar.mesh as BoxMesh
	if box:
		box.size.x = 0.6 * ratio
	var cam = get_viewport().get_camera_3d()
	if cam:
		hp_bar.global_rotation.y = cam.global_rotation.y

func _create_telegraph_label() -> void:
	telegraph_label = Label3D.new()
	telegraph_label.name = "TelegraphLabel"
	telegraph_label.font_size = 40
	telegraph_label.outline_size = 3
	telegraph_label.no_depth_test = true
	telegraph_label.position = Vector3(0, 2.8, 0)
	telegraph_label.visible = false
	add_child(telegraph_label)

func _show_telegraph() -> void:
	if not telegraph_label or combat_comp.current_attack_dir == "":
		return
	# Опция B (Q7.9): стрелка показывает ТРЕБУЕМОЕ НАПРАВЛЕНИЕ БЛОКА (зеркало
	# атаки), а не сырое направление атаки: игрок уводит мышь/блок ПО стрелке.
	# Прежнее поведение (сырая стрелка атаки) заставляло зеркалить в уме и
	# уводило жест в неверную сторону. Маппинг — CombatComponent.BLOCK_RESPONSE
	# (единый источник правды, тот же, что в проверке блока).
	var block_dir: String = CombatComponent.BLOCK_RESPONSE.get(combat_comp.current_attack_dir, "UP")
	if block_dir == "UP":
		telegraph_label.text = "↑"
	elif block_dir == "LEFT":
		telegraph_label.text = "←"
	elif block_dir == "RIGHT":
		telegraph_label.text = "→"
	telegraph_label.visible = true
	var cam = get_viewport().get_camera_3d()
	if cam:
		telegraph_label.global_rotation.y = cam.global_rotation.y

func _hide_telegraph() -> void:
	if telegraph_label:
		telegraph_label.visible = false

func _update_telegraph_visibility() -> void:
	if combat_comp.is_recovery and not combat_comp.attack_swing_active:
		_show_telegraph()
	else:
		_hide_telegraph()
	if telegraph_label and telegraph_label.visible:
		var cam = get_viewport().get_camera_3d()
		if cam:
			telegraph_label.global_rotation.y = cam.global_rotation.y

func _update_enemy_indicator() -> void:
	if not has_node("StateLabel"):
		var lbl = Label3D.new()
		lbl.name = "StateLabel"
		lbl.font_size = 32
		lbl.outline_size = 2
		lbl.no_depth_test = true
		lbl.position = Vector3(0, 2.6, 0)
		add_child(lbl)
	var lbl = get_node("StateLabel")
	if combat_comp.enemy_block_active:
		lbl.text = "🛡️"
	elif combat_comp.stun_timer > 0.0:
		lbl.text = "💫"
	elif combat_comp.is_recovery and not combat_comp.attack_swing_active:
		lbl.text = "⚡"
	else:
		var move_state: String = brain.move_state if brain != null else "IDLE"
		if move_state == "IDLE":
			lbl.text = "❓"
		elif move_state == "CHASE":
			lbl.text = "❗"
		elif move_state == "STOPPED":
			lbl.text = "🛑"
		# B3 (микро-изменение Q7.21): значки состояний поиска — иначе лейбл
		# залипал на прежнем значении (debug-читаемость feel-чека).
		elif move_state == "INVESTIGATE":
			lbl.text = "❔"
		elif move_state == "SEARCH":
			lbl.text = "🔍"
		elif move_state == "AMBUSH_WAIT":
			lbl.text = "🌿"
		elif move_state == "BLIND_STRIKE":
			lbl.text = "💥"
		# B4 (Q7.24): самосохранение.
		elif move_state == "FLEE":
			lbl.text = "💨"
		elif move_state == "HIDE":
			lbl.text = "🌾"
		elif move_state == "GUARD":
			lbl.text = "📍"
	var cam = get_viewport().get_camera_3d()
	if cam:
		lbl.global_rotation.y = cam.global_rotation.y

func _play_hit_flash() -> void:
	var enemy_visual := get_node_or_null("EnemyVisual")
	if enemy_visual == null:
		return

	var meshes := enemy_visual.find_children("", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return

	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color.WHITE
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1, 0.2, 0.2)

	var original_materials: Array[Material] = []
	var valid_meshes: Array[MeshInstance3D] = []
	for mesh_node in meshes:
		var mesh := mesh_node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		valid_meshes.append(mesh)
		original_materials.append(mesh.material_override)
		mesh.material_override = flash_mat

	await get_tree().create_timer(0.15).timeout
	for index in valid_meshes.size():
		var mesh := valid_meshes[index]
		if is_instance_valid(mesh):
			mesh.material_override = original_materials[index]


func _play_impact_sound() -> void:
	var audio_player = AudioStreamPlayer.new()
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = 44100
	audio_player.stream = stream
	add_child(audio_player)
	audio_player.play()
	await get_tree().process_frame
	var playback = audio_player.get_stream_playback()
	if playback:
		var buffer: PackedVector2Array = []
		for i in range(2205):
			var t = float(i) / 2205.0
			var vol = (1.0 - t) * 0.4
			buffer.append(Vector2(randf_range(-vol, vol), randf_range(-vol, vol)))
		playback.push_buffer(buffer)
	await get_tree().create_timer(0.1).timeout
	audio_player.queue_free()

func _spawn_impact_particles() -> void:
	for i in range(5):
		var p = MeshInstance3D.new()
		p.mesh = BoxMesh.new()
		p.mesh.size = Vector3(0.15, 0.15, 0.15)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.2, 0.2, 1.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		p.material_override = mat
		get_tree().root.add_child(p)
		p.global_position = global_position + Vector3(randf_range(-0.5,0.5), randf_range(0.8,1.5), randf_range(-0.5,0.5))
		var vel = Vector3(randf_range(-3,3), randf_range(2,5), randf_range(-3,3))
		var tw = create_tween()
		tw.tween_property(p, "position", p.position + vel * 0.4, 0.4).set_trans(Tween.TRANS_EXPO)
		tw.parallel().tween_property(p, "material_override:albedo_color", Color(1,0.2,0.2,0.0), 0.4)
		tw.finished.connect(p.queue_free)
