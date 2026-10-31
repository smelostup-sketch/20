extends SceneTree
## Q7.34.PreOmega_Sky3.2.2 (вариант Б-мир, выбор заказчика) — headless-тест стрика.
## Запуск:
##   godot --headless --path Q7.33.PreOmega --script q_tools/test_streak_basis.gd
##
## Доказывает четыре факта:
##   1. СТАРЫЙ базис (S8: sk_streak_right = right камеры, спроецированный ⊥ sd)
##      наклоняется к горизонту мира при рыскании камеры — это и есть баг
##      «стрик меняет наклон при повороте камеры». Наклон = asin(|right_w.y|).
##   2. НОВЫЙ базис (мир: right_w = normalize(cross(up0, sd))) имеет нулевой наклон
##      при ЛЮБОМ солнце, включая полюса, и не даёт NaN ни в одной ветке.
##   3. СТАРАЯ UV-развёртка (хорда sin θ, делённая на radians(60)) горизонтально
##      не достигала края текстуры вовсе (sin θ ≤ 1 < 1.047) — спрайт использовался
##      на ~95 % и сжимался к краям; НОВАЯ (гномоника tan θ / tan(half_w))
##      достигает края ровно на θ = half_w и совпадает с аспектом текстуры 2:1.
##   4. Шейдер компилируется; uniform sk_streak_right удалён; два новых полуугла есть.

func _dir(az_deg: float, el_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()


func _cam_right(yaw_deg: float, pitch_deg: float) -> Vector3:
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	var f := -Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)).normalized()
	return f.cross(Vector3.UP).normalized()


func _uniform_default(sh: Shader, name: String) -> float:
	var re := RegEx.new()
	re.compile(name + "[^=\\n]*=[^0-9\\n-]*(-?[0-9]+\\.?[0-9]*)")
	var m := re.search(sh.code)
	return float(m.get_string(1)) if m != null else -1.0


func _init() -> void:
	var fails := 0

	# Шейдер и материал с дефолтами — нужны секции 3 (полууглы) и 4 (состав).
	var sh = ResourceLoader.load("res://SkyEnvironment/SkyEnvironment.gdshader", "Shader",
			ResourceLoader.CACHE_MODE_IGNORE)
	var mat := ShaderMaterial.new()
	if sh != null:
		mat.shader = sh

	print("=== 1. СТАРЫЙ базис (камера): наклон right_w к горизонту мира, градусы ===")
	var worst := 0.0
	for el in [0.0, 15.0, 30.0, 45.0, 60.0]:
		var sd := _dir(180.0, el)
		var line := "  el=%4.1f |" % el
		for yaw in [0.0, 45.0, 90.0, 135.0, 180.0, 270.0]:
			var bx := _cam_right(yaw, 0.0)
			var rr := bx - sd * bx.dot(sd)
			var rw := rr.normalized() if rr.length() > 1e-6 else Vector3(1, 0, 0)
			var tilt := rad_to_deg(asin(clampf(abs(rw.y), 0.0, 1.0)))
			worst = maxf(worst, tilt)
			line += " %5.1f" % tilt
		print(line)
	print("  макс. наклон = %.1f° (полоса плывёт при рыскании) — баг подтверждён: %s"
			% [worst, "ДА" if worst > 1.0 else "НЕТ"])
	if worst < 1.0:
		print("  FAIL: старый базис не наклоняется, гипотеза А1 не подтвердилась")
		fails += 1

	print("=== 2. НОВЫЙ базис (мир): наклон и безопасность на полюсах ===")
	for el in [-90.0, -89.9, -60.0, -30.0, 0.0, 30.0, 60.0, 89.9, 90.0]:
		var sd := _dir(180.0, el)
		var up0 := Vector3(0, 0, 1) if absf(sd.y) > 0.999 else Vector3(0, 1, 0)
		var rwv := up0.cross(sd)
		var lr := rwv.length()
		var rw := rwv / lr if lr > 1e-6 else Vector3(1, 0, 0)
		var tilt := rad_to_deg(asin(clampf(abs(rw.y), 0.0, 1.0)))
		var ok := absf(tilt) < 1e-6 and rw.is_finite() and lr > 1e-6
		print("  el=%6.1f | наклон=%9.6f° | |cross|=%.6f | finite=%s | %s"
				% [el, tilt, lr, str(rw.is_finite()), "OK" if ok else "FAIL"])
		if not ok:
			fails += 1

	print("=== 3. UV-развёртка: досягаемость края текстуры по горизонтали ===")
	var old_max := 0.0
	for i in range(0, 90):
		var th := deg_to_rad(float(i))
		old_max = maxf(old_max, abs(sin(th)) / deg_to_rad(60.0))
	print("  старая (sin θ / radians(60)): макс |suv.x−0.5|·2 = %.3f → край НЕ досягаем (%s)"
			% [old_max, "баг" if old_max < 1.0 else "ok"])
	if sh == null:
		print("  FAIL: шейдер не загрузился, полууглы не прочитать")
		fails += 1
	else:
		# Дефолты читаем из исходника шейдера: ShaderMaterial.get_shader_parameter
		# до первого set возвращает Nil, а uniform_list дефолты не несёт.
		var hw := _uniform_default(sh, "sk_streak_half_w_deg")
		var hh := _uniform_default(sh, "sk_streak_half_h_deg")
		if hw < 0.0 or hh < 0.0:
			print("  FAIL: полууглы не найдены в шейдере")
			fails += 1
		var aspect := (tan(deg_to_rad(hw)) / tan(deg_to_rad(hh)))
		print("  новая (tan θ / tan(half_w)): suv.x = 1 ровно на θ = half_w = %.1f°; аспект бокса = %.3f (текстура 2.000)" % [hw, aspect])
		if abs(aspect - 2.0) > 0.02:
			print("  FAIL: аспект бокса не совпадает с аспектом streak_glare.png")
			fails += 1

	print("=== 4. Шейдер: компиляция и состав uniform'ов ===")
	if sh == null:
		print("  FAIL: шейдер не загрузился")
		quit(1)
		return
	var has_old := false
	var has_w := false
	var has_h := false
	for d in sh.get_shader_uniform_list():
		var n: String = d["name"]
		if n == "sk_streak_right":
			has_old = true
		if n == "sk_streak_half_w_deg":
			has_w = true
		if n == "sk_streak_half_h_deg":
			has_h = true
	print("  компилируется: да | sk_streak_right удалён: %s | half_w: %s | half_h: %s"
			% [str(not has_old), str(has_w), str(has_h)])
	if has_old or not has_w or not has_h:
		fails += 1

	print("")
	if fails == 0:
		print("TEST_STREAK_BASIS: PASS")
	else:
		print("TEST_STREAK_BASIS: FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)
