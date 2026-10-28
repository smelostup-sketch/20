extends SceneTree
## Q7.33, шаги D2/D3 (ТЗ п. 12.2/12.3) — headless-тест контроллеров неба.
## Запуск из проекта B (Q7.32.PreOmega):
##   godot --headless --path . --script q_tools/test_sky_controllers.gd
## Проверяет (критерии приёмки 18.5 и шаг D3):
##   1. elev ∈ {-90, -45, 0, 45, 89.9, 90} × azim ∈ {0, 90, 180, 270}:
##      SunLight.global_transform.basis.z == _direction(azim, elev) до 1e-5;
##   2. при elev = ±90 нет ошибки движка о вырожденном базисе (следить за выводом);
##   3. солнце над горизонтом → лучи (-basis.z) идут вниз (тени от солнца);
##   4. SunLight и MoonLight независимы: движение солнца не разворачивает лунный свет;
##   5. D3: sk_sun_dir в материале == SunLight.basis.z == _direction (один расчёт).

func _initialize() -> void:
	var fails := 0
	var world := Node3D.new()
	root.add_child(world)

	var sun := DirectionalLight3D.new()
	var moon := DirectionalLight3D.new()
	world.add_child(sun)
	world.add_child(moon)

	var light_ctrl := SkyLightController.new()
	world.add_child(light_ctrl)
	light_ctrl.sun_light = sun
	light_ctrl.moon_light = moon

	# 1-3. ориентация солнца на сетке elev × azim
	for elev in [-90.0, -45.0, 0.0, 45.0, 89.9, 90.0]:
		for azim in [0.0, 90.0, 180.0, 270.0]:
			light_ctrl.set_sun_angles(azim, elev)
			var expect: Vector3 = SkyLightController.direction_from_angles(azim, elev)
			var got: Vector3 = sun.global_transform.basis.z
			if got.distance_to(expect) > 1e-5:
				fails += 1
				printerr("FAIL D2: azim=%f elev=%f basis.z=%s expect=%s" % [azim, elev, got, expect])
			if elev > 1.0 and elev < 89.0 and (-got).y >= 0.0:
				fails += 1
				printerr("FAIL D2 тени: солнце elev=%f над горизонтом, а луч не вниз" % elev)

	# 4. независимость луны
	light_ctrl.set_moon_angles(0.0, 50.0)
	var moon_quat_before: Quaternion = moon.global_basis.get_rotation_quaternion()
	light_ctrl.set_sun_angles(234.0, -12.0)
	if moon.global_basis.get_rotation_quaternion() != moon_quat_before:
		fails += 1
		printerr("FAIL D2: движение солнца развернуло лунный свет")

	# 5. D3: материал и свет читают один _direction
	var mat := ShaderMaterial.new()
	var env_ctrl := SkyEnvironmentController.new()
	world.add_child(env_ctrl)
	env_ctrl.sky_material = mat
	env_ctrl.light_controller = light_ctrl
	env_ctrl.set_sun_angles(180.0, -30.0)
	var expect_dir: Vector3 = SkyLightController.direction_from_angles(180.0, -30.0)
	var sd = mat.get_shader_parameter("sk_sun_dir")
	if not (sd is Vector3) or (sd as Vector3).distance_to(expect_dir) > 1e-6:
		fails += 1
		printerr("FAIL D3: sk_sun_dir=%s != _direction(180,-30)=%s" % [sd, expect_dir])
	if sun.global_transform.basis.z.distance_to(expect_dir) > 1e-5:
		fails += 1
		printerr("FAIL D3: SunLight.basis.z != _direction(180,-30)")
	var md_before = mat.get_shader_parameter("sk_moon_dir")
	env_ctrl.set_sun_angles(90.0, 45.0)
	if mat.get_shader_parameter("sk_moon_dir") != md_before:
		fails += 1
		printerr("FAIL D3: set_sun_angles изменил sk_moon_dir")

	if fails == 0:
		print("D2/D3 OK: basis.z == _direction на всей сетке elev×azim; тени от солнца;")
		print("          солнце/луна независимы; материал и свет согласованы (один _direction).")
	else:
		printerr("D2/D3: провалов %d" % fails)
	quit(1 if fails > 0 else 0)
