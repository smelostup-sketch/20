extends SceneTree
func _measure_glb(path: String, with_bones: bool) -> void:
	var scn := load(path) as PackedScene
	if scn == null:
		print("R27 %s: НЕ ЗАГРУЗИЛОСЬ" % path); return
	var inst := scn.instantiate()
	var tris := 0; var surf := 0; var mats := {}
	var aabb := AABB(); var first := true
	var bones := 0; var bone_names: Array = []
	var nodes := 0
	for mi in inst.find_children("", "MeshInstance3D", true, false):
		nodes += 1
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null: continue
		var w: AABB = (mi as MeshInstance3D).transform * m.get_aabb()
		aabb = w if first else aabb.merge(w)
		first = false
		for s in m.get_surface_count():
			surf += 1
			var arr := m.surface_get_arrays(s)
			var idx: Array = arr[Mesh.ARRAY_INDEX]
			var vts: Array = arr[Mesh.ARRAY_VERTEX]
			tris += (idx.size() / 3) if idx.size() > 0 else (vts.size() / 3)
			var mat := m.surface_get_material(s)
			if mat != null:
				var key := mat.resource_name if mat.resource_name != "" else mat.get_class()
				mats[key] = true
				if mat is BaseMaterial3D:
					var tex: Texture = (mat as BaseMaterial3D).albedo_texture
					if tex != null: mats[key] = "%dx%d" % [tex.get_width(), tex.get_height()]
	for sk in inst.find_children("", "Skeleton3D", true, false):
		var s3 := sk as Skeleton3D
		bones = maxi(bones, s3.get_bone_count())
		for b in mini(s3.get_bone_count(), 400):
			bone_names.append(s3.get_bone_name(b))
	print("R27 %s: трис=%d поверх=%d материалов=%d узлов_mesh=%d" % [path, tris, surf, mats.size(), nodes])
	print("R27 %s: AABB pos=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)" % [path, aabb.position.x, aabb.position.y, aabb.position.z, aabb.size.x, aabb.size.y, aabb.size.z])
	print("R27 %s: материалы=%s" % [path, str(mats)])
	if with_bones:
		print("R27 %s: костей=%d" % [path, bones])
		var mix := 0; var other: Array = []
		for bn in bone_names:
			if String(bn).begins_with("mixamorig"): mix += 1
			elif other.size() < 8: other.append(bn)
		print("R27 %s: mixamorig-костей=%d из %d; примеры иных: %s" % [path, mix, bones, str(other)])
		print("R27 %s: первые 12 костей: %s" % [path, str(bone_names.slice(0, 12))])
	inst.free()

func _measure_tex(path: String) -> void:
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		print("R27 tex %s: ошибка загрузки" % path); return
	var w := img.get_width(); var h := img.get_height()
	# Шов по горизонтали: колонка 0 vs колонка w-1; базовая линия: w-2 vs w-1
	var wrap := 0.0; var inner := 0.0
	for y in range(0, h, max(1, h / 256)):
		var a0 := img.get_pixel(0, y); var a1 := img.get_pixel(w - 1, y); var a2 := img.get_pixel(w - 2, y)
		wrap += abs(a0.r - a1.r) + abs(a0.g - a1.g) + abs(a0.b - a1.b)
		inner += abs(a2.r - a1.r) + abs(a2.g - a1.g) + abs(a2.b - a1.b)
	var n := float(h / max(1, h / 256))
	var wrap_v := wrap / n / 3.0; var inner_v := inner / n / 3.0
	var wrapv := 0.0; var innerv := 0.0
	for x in range(0, w, max(1, w / 256)):
		var b0 := img.get_pixel(x, 0); var b1 := img.get_pixel(x, h - 1); var b2 := img.get_pixel(x, h - 2)
		wrapv += abs(b0.r - b1.r) + abs(b0.g - b1.g) + abs(b0.b - b1.b)
		innerv += abs(b2.r - b1.r) + abs(b2.g - b1.g) + abs(b2.b - b1.b)
	var wrapv_v := wrapv / n / 3.0; var innerv_v := innerv / n / 3.0
	print("R27 tex %s: %dx%d | шов H wrap=%.4f inner=%.4f (x%.1f) | шов V wrap=%.4f inner=%.4f (x%.1f)" % [
		path, w, h, wrap_v, inner_v, (wrap_v / maxf(inner_v, 0.0001)), wrapv_v, innerv_v, (wrapv_v / maxf(innerv_v, 0.0001))])

func _initialize() -> void:
	_measure_glb("res://Assets/jungle/trava2_500.glb", false)
	_measure_glb("res://Assets/jungle/trava3_500.glb", false)
	_measure_glb("res://Assets/ruins/platforma4k.glb", false)
	_measure_glb("res://Assets/rengar/безгривы_28к.glb", true)
	_measure_tex("res://Assets/textures/jung_textures/2eed25d7-85bc-43c1-9782-b2b8498ef369(1).png")
	_measure_tex("res://Assets/textures/jung_textures/2eed25d7-85bc-43c1-9782-b2b8498ef369(2).png")
	quit(0)
