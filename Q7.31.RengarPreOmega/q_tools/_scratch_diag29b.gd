extends SceneTree
var frame := 0
var tst: Node = null
var tctl: Node = null
func _process(_d: float) -> bool:
	frame += 1
	if frame == 2:
		tst = (load("res://Сцена_неба.tscn") as PackedScene).instantiate()
		root.add_child(tst)
		tctl = tst.get_node("TimeOfDayController")
		print("E frame2 light=%s in_tree=%s" % [str(tctl.get("light")), str(tctl.is_inside_tree())])
	if frame == 3:
		print("E frame3 light=%s" % str(tctl.get("light")))
		# ручной резолв как fallback-механика:
		print("E get_node('../DirectionalLight3D')=%s" % str(tctl.get_node_or_null("../DirectionalLight3D")))
		quit(0); return true
	return false
