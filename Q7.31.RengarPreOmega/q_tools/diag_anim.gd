extends SceneTree
## Q-диагностика (проблема: боковое скольжение/дрожь при старте и остановке).
## Статический анализ импортированных Mixamo-клипов: состав треков,
## наличие root-node треков (root motion), диапазоны движения Hips по осям.
## Лог: res://q_tools/diag_anim_out.txt

const SOURCES := [
	"res://Assets/Mixamo/Y Bot.fbx",
	"res://Assets/Mixamo/Idle.fbx",
	"res://Assets/Mixamo/Running.fbx",
	"res://Assets/Mixamo/Running Jump.fbx",
	"res://Assets/Mixamo/Reaction.fbx",
]


func _vec_range(anim: Animation, ti: int) -> String:
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	var n := 0
	for ki in anim.track_get_key_count(ti):
		var v = anim.track_get_key_value(ti, ki)
		var p: Variant
		if v is Vector3:
			p = v
		elif v is Transform3D:
			p = (v as Transform3D).origin
		else:
			return ""
		mn = mn.min(p)
		mx = mx.max(p)
		n += 1
	if n == 0:
		return ""
	return " X[%.4f..%.4f] Y[%.4f..%.4f] Z[%.4f..%.4f]" % [mn.x, mx.x, mn.y, mx.y, mn.z, mx.z]


func _initialize() -> void:
	var f := FileAccess.open("res://q_tools/diag_anim_out.txt", FileAccess.WRITE)
	for path in SOURCES:
		var scn := load(path) as PackedScene
		if scn == null:
			f.store_line("=== %s === LOAD FAIL" % path)
			continue
		var inst := scn.instantiate()
		f.store_line("=== %s ===" % path)
		f.store_line("root: %s (%s) transform=%s" % [inst.name, inst.get_class(), inst.transform])
		for c in inst.get_children():
			f.store_line("  child: %s (%s)" % [c.name, c.get_class()])
			if c is Skeleton3D:
				var sk := c as Skeleton3D
				f.store_line("    bones=%d bone0=%s" % [sk.get_bone_count(), sk.get_bone_name(0)])
				for bi in sk.get_bone_count():
					if sk.get_bone_parent(bi) == -1:
						f.store_line("    ROOT_BONE[%d]=%s rest_origin=%s" % [bi, sk.get_bone_name(bi), sk.get_bone_rest(bi).origin])
		var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap != null:
			f.store_line("  AnimationPlayer root_node=%s anims=%s" % [str(ap.root_node), ap.get_animation_list()])
			for aname in ap.get_animation_list():
				var anim := ap.get_animation(aname)
				f.store_line("  ANIM %s length=%.3f loop=%d tracks=%d" % [aname, anim.length, anim.loop_mode, anim.get_track_count()])
				for ti in anim.get_track_count():
					var tp := anim.track_get_path(ti)
					var tt := anim.track_get_type(ti)
					var kc := anim.track_get_key_count(ti)
					f.store_line("    [%02d] type=%d keys=%d path=%s%s" % [ti, tt, kc, tp, _vec_range(anim, ti)])
		inst.free()
	f.close()
	quit(0)
