extends SceneTree
## Sky3.2.12 (приказ 0.2): вуаль включена по умолчанию ВО ВСЕХ пресетах — ДАННЫМИ:
## в каждый Preset_XX.tres дописывается sub-resource SkyVeilProfile с veil_enabled=true
## (никакого хардкода в коде: пресет как был источником состояния, так и остался).
## Запуск: godot --headless --path <проект> --script q_tools/migrate_veil_on.gd
func _init() -> void:
	var Prof: GDScript = load("res://SkyEnvironment/SkyVeilProfile.gd")
	var bad := 0
	for i in range(1, 11):
		var path := "res://SkyEnvironment/SkyPreset/Preset_%02d.tres" % i
		var p: Resource = load(path)
		if p == null:
			printerr("не загрузился %s" % path)
			bad += 1
			continue
		if p.veil == null:
			p.veil = Prof.new()
		p.veil.veil_enabled = true
		var err := ResourceSaver.save(p, path)
		if err != OK:
			printerr("save %s: %s" % [path, error_string(err)])
			bad += 1
		else:
			print("OK %s veil_enabled=true" % path)
	print("MIGRATE_VEIL_ON: %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
	quit(0 if bad == 0 else 1)
