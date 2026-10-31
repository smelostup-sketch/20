extends SceneTree
## Q7.34.PreOmega_Sky3.2.3 (Б6, без скриншота): численная диагностика «рыбьего глаза».
## Годот-дефолты камеры + фактические настройки проекта + таблица горизонтального
## FOV. Рендер не нужен: всё считается из данных сцены/проекта.
func _init() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	print("=== дефолты Camera3D Godot 4.7 ===")
	print("  fov = %.1f | projection = %d (0=persp,1=ortho,2=free) | keep_aspect = %d (0=KEEP_WIDTH,1=KEEP_HEIGHT)"
			% [cam.fov, cam.projection, cam.keep_aspect])
	print("  near = %.2f far = %.1f" % [cam.near, cam.far])
	# project.godot: секции [display] нет -> окно по умолчанию 1152x648, stretch отключён
	print("=== проект: секции [display] нет (window/stretch/aspect не зафиксированы) ===")
	var vfov := cam.fov
	print("=== горизонтальный FOV при vFOV %.0f и keep_aspect=%d ===" % [vfov, cam.keep_aspect])
	var cases := [["4:3", 1.333], ["16:10", 1.600], ["16:9 (дефолт-окно 1152x648)", 1.778],
			["20:9", 2.222], ["21:9", 2.333]]
	for c in cases:
		var label: String = c[0]
		var aspect: float = c[1]
		var hfov := rad_to_deg(2.0 * atan(tan(deg_to_rad(vfov) * 0.5) * aspect))
		print("  %-28s aspect=%.3f -> hFOV = %6.1f°" % [label, aspect, hfov])
	# и сколько даёт vFOV 60 при том же окне (вариант рецепта)
	print("  --- при vFOV 60: ---")
	for c in cases:
		var label: String = c[0]
		var aspect: float = c[1]
		var hfov := rad_to_deg(2.0 * atan(tan(deg_to_rad(60.0)) * aspect) / 1.0)
		hfov = rad_to_deg(2.0 * atan(tan(deg_to_rad(60.0) * 0.5) * aspect))
		print("  %-28s aspect=%.3f -> hFOV = %6.1f°" % [label, aspect, hfov])
	# Sky3.2.5 (приказ заказчика 30.10): «Фов можно уменьшить до 93 градусов».
	# Реализация: keep_aspect = KEEP_WIDTH (0) + fov = 93.0 → fov в Godot при
	# KEEP_WIDTH — ГОРИЗОНТАЛЬНЫЙ: hFOV = 93° при ЛЮБОМ аспекте окна (рыбий глаз
	# не вернётся на широких окнах), вертикаль производна.
	print("=== ПОСЛЕ ФИКСА (Sky3.2.5): keep_aspect=KEEP_WIDTH, fov=93 (горизонтальный) ===")
	var hfov_fix := 93.0
	for c in cases:
		var label: String = c[0]
		var aspect: float = c[1]
		var v := rad_to_deg(2.0 * atan(tan(deg_to_rad(hfov_fix) * 0.5) / aspect))
		print("  %-28s hFOV = 93.0° (фикс.)  vFOV = %5.1f°" % [label, v])
	print("=== перспектива третьего лица (ThirdPersonCamera.gd) ===")
	print("  distance = 4.0 (min 2.5 / max 10.0), target_height = 1.5, mouse_sens = 0.004")
	print("  ДО:  vFOV 75, дистанция 4 м → вертикальный охват на цели = %.2f м" % (2.0 * 4.0 * tan(deg_to_rad(vfov) * 0.5)))
	var v169 := rad_to_deg(2.0 * atan(tan(deg_to_rad(93.0) * 0.5) / 1.778))
	print("  ПОСЛЕ (16:9): vFOV %.1f → охват на цели = %.2f м" % [v169, 2.0 * 4.0 * tan(deg_to_rad(v169) * 0.5)])
	print("DONE")
	quit(0)
