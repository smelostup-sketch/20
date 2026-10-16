extends CanvasLayer
class_name AIDebugLogPanel

## Экранный журнал ИИ (Q7.18, запрос заказчика): панель слева сверху,
## включается/выключается тильдой (` / KEY_QUOTELEFT).
##
## Показывает РЕАЛЬНО работающий ИИ: AIBrainComponent (решения, намерения,
## ожидание исходов, движок паттернов, счётчики приёмки), состояние боевого
## ядра, честные факты восприятия. Спящий UtilityAI отображается ТОЛЬКО если
## действительно включён (enabled) — с явной пометкой. Родословна панели:
## «веса не меняются» (Q7.17 фидбек) — прежний UtilityAIThoughtLabel показывал
## замороженный снимок ВЫКЛЮЧЕННОЙ системы; панель исключает такую ошибку:
## источник данных = компоненты, принимающие решения здесь и сейчас.
##
## Debug-инструмент: читает публичное состояние компонентов и подписывается на
## их сигналы; в бой не вмешивается. UI строит сам (паттерн существующих
## дебаг-визуализаторов; геймплейный UI — в сценах/компонентах, см. долг п.11).
##
## КОНФЛИКТ КЛАВИШИ (задокументирован, ждёт решения заказчика): тильда также
## удерживает свободный обзор камеры (ThirdPersonCamera.free_look_key).
## Панель НЕ глотает событие (set_input_as_handled не вызывается) — работают
## оба: короткое нажатие переключает панель, удержание даёт свободный обзор.

@export var toggle_key: Key = KEY_QUOTELEFT
@export_range(4, 40, 1) var max_log_lines := 14
@export_range(0.1, 3.0, 0.1) var rescan_interval := 0.5
@export var panel_size := Vector2(480, 340)
@export var panel_margin := Vector2(12, 12)
@export var color_background := Color(0.004, 0.039, 0.075, 0.86)  # LoL-палитра #010A13
@export var color_title := Color(0.784, 0.667, 0.431, 1.0)        # золото #C8AA6E
@export var color_status := Color(0.85, 0.88, 0.92, 1.0)
@export var color_event := Color(0.95, 0.95, 0.92, 1.0)

var panel_visible := false
var _panel: PanelContainer = null
var _status_label: Label = null
var _log_label: Label = null
var _lines: Array[String] = []
var _tracked: Dictionary = {} # instance_id -> {enemy, brain, combat, utility, perception}
var _rescan_left := 0.0
var _t0 := 0.0


func _ready() -> void:
	layer = 50
	_t0 = Time.get_ticks_msec() * 0.001
	_build_ui()
	# Подписка на врагов сразу: лента истории копится даже когда панель скрыта —
	# открыв её, заказчик видит последние события, а не пустоту (урок sim_aihud:
	# первое «Решение движения» происходило до подписки и терялось).
	_rescan_enemies()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == toggle_key or event.physical_keycode == toggle_key):
		set_panel_visible(not panel_visible)


## Публичное переключение (для стендов и будущих настроек).
func set_panel_visible(value: bool) -> void:
	panel_visible = value
	if _panel != null:
		_panel.visible = value
	if value:
		_push("Панель включена (клавиша ~)")
		_rescan_enemies()
		_refresh_status()


func _process(delta: float) -> void:
	if not panel_visible:
		return
	_rescan_left -= delta
	if _rescan_left <= 0.0:
		_rescan_left = rescan_interval
		_rescan_enemies()
	_refresh_status()


# === СОСТАВ ДАННЫХ ===
func _rescan_enemies() -> void:
	# Чистка освободившихся.
	for id in _tracked.keys():
		var rec: Dictionary = _tracked[id]
		if not is_instance_valid(rec.get("enemy")):
			_tracked.erase(id)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var id := (enemy as Node).get_instance_id()
		if _tracked.has(id):
			continue
		var rec := {
			"enemy": enemy,
			"brain": (enemy as Node).get_node_or_null("AIBrainComponent"),
			"combat": (enemy as Node).get_node_or_null("CombatComponent"),
			"utility": (enemy as Node).get_node_or_null("EnemyUtilityAIComponent"),
			"perception": (enemy as Node).get_node_or_null("EnemyPerceptionComponent"),
		}
		_tracked[id] = rec
		_connect_enemy(rec)
		_push("Слежу за врагом %s" % (enemy as Node).name)


func _connect_enemy(rec: Dictionary) -> void:
	var brain: Node = rec.get("brain")
	var combat: Node = rec.get("combat")
	if brain != null:
		if brain.has_signal("decision_changed"):
			brain.decision_changed.connect(_on_decision_changed.bind(rec))
		if brain.has_signal("attack_decided"):
			brain.attack_decided.connect(_on_attack_decided.bind(rec))
	if combat != null:
		if combat.has_signal("attack_cancelled"):
			combat.attack_cancelled.connect(_on_attack_cancelled.bind(rec))
		if combat.has_signal("attack_finished"):
			combat.attack_finished.connect(_on_attack_finished.bind(rec))
		if combat.has_signal("hit_detected"):
			combat.hit_detected.connect(_on_hit_detected.bind(rec))
		if combat.has_signal("stun_started"):
			combat.stun_started.connect(_on_stun_started.bind(rec))


# === СОБЫТИЯ (лента) ===
func _on_decision_changed(move_state: String, _rec: Dictionary) -> void:
	_push("Решение движения: %s" % move_state)


func _on_attack_decided(direction: String, _rec: Dictionary) -> void:
	_push("Намерение атаки: dir=%s (жду исход)" % direction)


func _on_attack_cancelled(reason: String, _rec: Dictionary) -> void:
	_push("Исход: атака отменена reason=%s" % reason)


func _on_attack_finished(_rec: Dictionary) -> void:
	_push("Исход: атака завершена (recovery окончен)")


func _on_hit_detected(target: Node, _rec: Dictionary) -> void:
	_push("Исход: попадание по %s" % (target.name if is_instance_valid(target) else "?"))


func _on_stun_started(duration: float, _rec: Dictionary) -> void:
	_push("Исход: стан %.2f с" % duration)


func _push(message: String) -> void:
	var t := Time.get_ticks_msec() * 0.001 - _t0
	_lines.append("[%6.2f] %s" % [t, message])
	while _lines.size() > max_log_lines:
		_lines.pop_front()
	if _log_label != null:
		_log_label.text = "\n".join(_lines)


# === ЖИВОЕ СОСТОЯНИЕ ===
func _refresh_status() -> void:
	if _status_label == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var blocks: Array[String] = []
	for id in _tracked.keys():
		var rec: Dictionary = _tracked[id]
		var enemy: Node = rec.get("enemy")
		if not is_instance_valid(enemy):
			continue
		var brain: Node = rec.get("brain")
		var combat: Node = rec.get("combat")
		var utility: Node = rec.get("utility")
		var perception: Node = rec.get("perception")
		var b: Array[String] = []
		b.append("Враг: %s" % enemy.name)
		if brain != null:
			var dist_text := "дист=н/д"
			if player != null and is_instance_valid(player):
				dist_text = "дист=%.2f" % (enemy as Node3D).global_position.distance_to(player.global_position)
			b.append("  мозг: состояние=%s | %s | ждёт_исход=%s" % [
				str(brain.get("move_state")), dist_text, str(brain.get("awaiting_outcome"))])
			var cooldown := 0.0
			if brain.has_method("get_attack_cooldown_left"):
				cooldown = brain.get_attack_cooldown_left()
			var post_stun := 0.0
			if brain.has_method("get_post_stun_left"):
				post_stun = brain.get_post_stun_left()
			b.append("  паттерн: %s (осталось %d) | ритм: %.2f с | отход_после_стана: %.2f с | намерений=%d отказов_ядра=%d исходов=%d | сид=%d" % [
				str(brain.get("_pattern_dir")), int(brain.get("_pattern_left")), cooldown, post_stun,
				int(brain.get("intents_sent")), int(brain.get("intents_rejected")),
				int(brain.get("outcomes_received")), int(brain.get("random_seed"))])
		if combat != null:
			b.append("  ядро: recovery=%s | стан=%.2f | лок=%s | блок=%s | dir=%s" % [
				str(combat.get("is_recovery")), float(combat.get("stun_timer")),
				str(combat.get("is_input_locked")), str(combat.get("enemy_block_active")),
				str(combat.get("current_attack_dir"))])
		if perception != null:
			var now := Time.get_ticks_msec() * 0.001
			b.append("  восприятие (честное): атака_игрока=%s (%.1f с назад) | блок_игрока=%s (%.1f с назад, «мечом»)" % [
				str(perception.get("last_player_attack_direction")),
				now - float(perception.get("last_player_attack_time")),
				str(perception.get("last_player_block_direction")),
				now - float(perception.get("last_player_block_time"))])
		if utility != null:
			if bool(utility.get("enabled")):
				var snap: Dictionary = utility.get_debug_snapshot()
				var scores: Dictionary = snap.get("scores", {})
				b.append("  UtilityAI (ВКЛЮЧЁН, живой): %s | веса Идти=%.2f Ждать=%.2f Удар=%.2f Отход=%.2f" % [
					str(snap.get("decision", "?")),
					float(scores.get(0, 0.0)), float(scores.get(1, 0.0)),
					float(scores.get(2, 0.0)), float(scores.get(3, 0.0))])
			else:
				b.append("  UtilityAI: ВЫКЛЮЧЕН (решения у мозга; веса не отображаются намеренно)")
		blocks.append("\n".join(b))
	if blocks.is_empty():
		blocks.append("Врагов в группе \"enemy\" не найдено")
	_status_label.text = "\n".join(blocks)


# === UI (debug-инструмент строит сам — паттерн дебаг-визуализаторов) ===
func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "AIDebugPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = color_background
	style.border_color = color_title
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10.0)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = panel_margin
	_panel.size = panel_size
	_panel.visible = false
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "ЖУРНАЛ ИИ  (~ — вкл/выкл)"
	title.add_theme_color_override("font_color", color_title)
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", color_status)
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(panel_size.x - 40, panel_size.y * 0.45)
	vbox.add_child(_status_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_log_label = Label.new()
	_log_label.add_theme_color_override("font_color", color_event)
	_log_label.add_theme_font_size_override("font_size", 12)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.custom_minimum_size = Vector2(panel_size.x - 40, panel_size.y * 0.40)
	vbox.add_child(_log_label)
