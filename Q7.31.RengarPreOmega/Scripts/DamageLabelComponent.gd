extends Node
class_name DamageLabelComponent

## Визуальный компонент: всплывающая цифра урона над владельцем.
## Единый источник для врага и манекена (Q7.13, чистка п.10: раньше код был
## продублирован байт-в-байт в EnemyController и DummyEnemyController).
## Без боевой логики, здоровья и коллизий — только визуал; параметры —
## экспорты (data-driven), поведение 1:1 с прежним встроенным кодом.

@export var font_size := 28
@export var outline_size := 3
@export var text_color := Color(1, 0.3, 0.3)
@export var spawn_height := 1.0   # На сколько выше владельца появляется цифра
@export var rise_to_y := 2.8      # Локальная y-цель всплытия (пространство root)
@export var rise_time := 0.6      # Секунды всплытия и затухания

var owner_body: Node3D = null


func _ready() -> void:
	owner_body = get_parent() as Node3D
	if owner_body == null:
		push_error("DamageLabelComponent должен быть дочерним узлом Node3D")


func spawn(value: int) -> void:
	if owner_body == null or not owner_body.is_inside_tree():
		return
	var lbl := Label3D.new()
	lbl.text = str(value)
	lbl.font_size = font_size
	lbl.outline_size = outline_size
	lbl.modulate = text_color
	lbl.no_depth_test = true
	get_tree().root.add_child(lbl)
	lbl.global_position = owner_body.global_position + Vector3(0, spawn_height, 0)
	var cam := get_viewport().get_camera_3d()
	if cam:
		lbl.global_rotation.y = cam.global_rotation.y
	var tw := create_tween()
	tw.parallel().tween_property(lbl, "position:y", rise_to_y, rise_time).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, rise_time)
	tw.finished.connect(lbl.queue_free)
