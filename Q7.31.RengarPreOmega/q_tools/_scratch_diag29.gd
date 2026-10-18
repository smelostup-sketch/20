extends SceneTree
var frame := 0
func _process(_d: float) -> bool:
	frame += 1
	if frame == 2:
		var scn := load("res://Основная_сцена.tscn") as PackedScene
		var inst := scn.instantiate()
		root.add_child(inst)
		print("D children: ")
		for c in inst.get_children():
			print("D   child: %s (%s)" % [c.name, c.get_class()])
		var ctl := inst.get_node_or_null("TimeOfDayController")
		print("D ctl=%s" % str(ctl))
		if ctl != null:
			print("D ctl script=%s light=%s sky=%s" % [str(ctl.get_script()), str(ctl.get("light")), str(ctl.get("sky"))])
		var tst := (load("res://Сцена_неба.tscn") as PackedScene).instantiate()
		root.add_child(tst)
		var tctl := tst.get_node_or_null("TimeOfDayController")
		print("D test ctl=%s light=%s" % [str(tctl != null), str(tctl.get("light")) if tctl else "-"])
		quit(0); return true
	return false
