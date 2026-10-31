extends SceneTree
## Sky3.2.14 (задача 2 заказчика): «дыхание неба» максимально во всех пресетах —
## ДАННЫМИ: breathe = 0.9 (максимум диапазона) явной строкой в каждый Preset_XX.tres.
## Дефолт класса оставлен 0.0 — ради явности данных в .tres (иначе ResourceSaver
## опустил бы строку как совпадающую с дефолтом).
## Запуск: godot --headless --path <проект> --script q_tools/migrate_breathe_max.gd
func _init() -> void:
	var bad := 0
	for i in range(1, 11):
		var path := "res://SkyEnvironment/SkyPreset/Preset_%02d.tres" % i
		var p: Resource = load(path)
		if p == null:
			printerr("не загрузился %s" % path)
			bad += 1
			continue
		p.breathe = 0.9
		var err := ResourceSaver.save(p, path)
		if err != OK:
			printerr("save %s: %s" % [path, error_string(err)])
			bad += 1
		else:
			print("OK %s breathe=0.9" % path)
	print("MIGRATE_BREATHE_MAX: %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
	quit(0 if bad == 0 else 1)
