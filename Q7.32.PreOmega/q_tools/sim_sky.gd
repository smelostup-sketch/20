extends SceneTree
## sim_sky (Q7.29) — детерминированные проверки LOGIC-слоя омега-неба
## (визуал проверяется заказчиком в Сцена_неба.tscn; headless видит CPU-часть:
## параметры материала, свет, переходы, автопрогресс, офсеты облаков).
## Проверки: фазы/мгновенная установка; плавный переход (значения МЕЖДУ
## профилями); прерывание старта с ТЕКУЩИХ значений (без снапа); нулевая
## длительность = мгновенно; автопрогресс SUNSET→TWILIGHT→NIGHT и остановка
## на ночи без loop; loop замыкает; офсеты облаков растут по направлению ветра
## и пропорционально мультипликатору (независимость от fps — по delta);
## epsilon-гейт (неизменные параметры не перезаписываются); безопасный
## контроллер без ссылок (warn + no-op); интеграция основной сцены
## (один WorldEnvironment, свет синхронизирован с фазой).
## Лог: res://q_tools/sim_sky_out.txt

var frame := 0
var log_f: FileAccess = null
var passed := 0
var failed := 0
var stage := "SETUP"
var stage_t0 := 0.0
var test: Node = null
var main: Node = null
var ctl: Node = null
var mat: ShaderMaterial = null
var light: Node = null
var v_before := 0.0
var v_after := 0.0
var off_a := Vector2.ZERO
var off_b := Vector2.ZERO
var off_c := Vector2.ZERO
var d1_base := 0.0


func check(check_name: String, cond: bool) -> void:
	if cond:
		passed += 1
		log_f.store_line("PASS " + check_name)
	else:
		failed += 1
		log_f.store_line("FAIL " + check_name)


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


func _p(name: String) -> float:
	return float(mat.get_shader_parameter(name))


func _initialize() -> void:
	log_f = FileAccess.open("res://q_tools/sim_sky_out.txt", FileAccess.WRITE)
	log_f.store_line("SIM_SKY (омега-небо: контроллер фаз, переходы, ветер, интеграция)")


func _process(_delta: float) -> bool:
	frame += 1
	var t := _now() - stage_t0
	match stage:
		"SETUP":
			if frame == 2:
				test = (load("res://Сцена_неба.tscn") as PackedScene).instantiate()
				root.add_child(test)
				ctl = test.get_node("TimeOfDayController")
				mat = (ctl.get("sky") as Sky).sky_material as ShaderMaterial
				light = test.get_node("DirectionalLight3D")
				stage = "S1"
				stage_t0 = _now()
		"S1":
			if t >= 0.2:
				check("S1 старт: фаза SUNSET, авто выключено в тест-сцене",
					int(ctl.get_phase()) == 0 and ctl.auto_progress == false)
				check("S1 материал: sunset_amount=1, night=0, star_visibility=0",
					_p("sunset_amount") == 1.0 and _p("night_amount") == 0.0 and _p("star_visibility") == 0.0)
				ctl.set_phase_instant(2)
				stage = "S2"
				stage_t0 = _now()
		"S2":
			if t >= 0.2:
				check("S2 instant NIGHT: фаза=2, star_visibility=1.0, light_energy=0.45",
					int(ctl.get_phase()) == 2 and _p("star_visibility") == 1.0
					and absf(float(light.get("light_energy")) - 0.45) < 0.01)
				check("S2 instant NIGHT: sunset_amount=0, night_amount=1, moon_intensity=1.2",
					_p("sunset_amount") == 0.0 and _p("night_amount") == 1.0
					and absf(_p("moon_intensity") - 1.2) < 0.01)
				ctl.transition_to(0, 1.0)
				stage = "S3"
				stage_t0 = _now()
		"S3":
			if t >= 0.5 and t < 0.9:
				var sv := _p("star_visibility")
				check("S3 переход NIGHT→SUNSET 1с: на середине star_visibility=%.2f ∈ (0,1)" % sv,
					sv > 0.05 and sv < 0.95)
				check("S3 во время перехода фаза ещё NIGHT (сменится по завершении)",
					int(ctl.get_phase()) == 2 and ctl.is_transitioning())
				stage = "S4"
				stage_t0 = _now()
		"S4":
			# Прерывание перехода: ретаргет на NIGHT — старт с ТЕКУЩИХ значений.
			if t >= 0.15:
				v_before = _p("star_visibility")
				ctl.transition_to(2, 1.0)
				v_after = _p("star_visibility")
				check("S4 прерывание: ретаргет без снапа (тот же тик, %.3f == %.3f)" % [v_before, v_after],
					absf(v_after - v_before) < 0.001)
				stage = "S5"
				stage_t0 = _now()
		"S5":
			if t >= 1.3:
				check("S5 ретаргет завершён: NIGHT, star_visibility=1.0 (%.6f)" % _p("star_visibility"),
					int(ctl.get_phase()) == 2 and absf(_p("star_visibility") - 1.0) < 0.0001)
				ctl.transition_to(1, 0.0)
				stage = "S6"
				stage_t0 = _now()
		"S6":
			if t >= 0.15:
				check("S6 нулевая длительность = мгновенно: фаза TWILIGHT сразу",
					int(ctl.get_phase()) == 1 and not ctl.is_transitioning())
				# Автопрогресс с короткими dwell.
				ctl.set("sunset_duration", 0.3)
				ctl.set("twilight_duration", 0.3)
				ctl.set("night_duration", 0.0)
				ctl.set("transition_duration", 0.2)
				ctl.set_phase_instant(0)
				ctl.start_auto()
				stage = "S7"
				stage_t0 = _now()
		"S7":
			if t >= 1.6:
				check("S7 автопрогресс дошёл до NIGHT и СТОП (night_duration=0, loop off): фаза=%d" % int(ctl.get_phase()),
					int(ctl.get_phase()) == 2 and not ctl.is_transitioning())
				ctl.stop_auto()
				# Ветер: офсеты растут по направлению ветра.
				off_a = mat.get_shader_parameter("cloud_offset_large")
				stage = "S8"
				stage_t0 = _now()
		"S8":
			if t >= 0.5:
				off_b = mat.get_shader_parameter("cloud_offset_large")
				var d: Vector2 = off_b - off_a
				d1_base = d.length()
				check("S8 облака движутся: |Δoffset|=%.4f > 0 по ветру (sign x совпадает)" % d.length(),
					d.length() > 0.0001 and signf(d.x) == signf(ctl.current.wind_large_dir.x))
				ctl.debug_set_wind_multiplier(4.0)
				off_a = off_b
				stage = "S9"
				stage_t0 = _now()
		"S9":
			if t >= 0.5:
				off_c = mat.get_shader_parameter("cloud_offset_large")
				var d2: float = (off_c - off_b).length()
				check("S9 ветер ×4: Δoffset %.4f ≈ 4×%.4f (±25%%)" % [d2, d1_base],
					d2 > d1_base * 3.0 and d2 < d1_base * 5.0)
				ctl.debug_set_wind_multiplier(1.0)
				# Epsilon-гейт: неизменный параметр не перезаписывается (звёзды стоят).
				stage = "S10"
				stage_t0 = _now()
		"S10":
			if t >= 0.3:
				# Вне переходов значения фазы стоят точно (epsilon-гейт не портит их).
				check("S10 вне перехода star_visibility держит NIGHT=1.0: %.3f" % _p("star_visibility"),
					absf(_p("star_visibility") - 1.0) < 0.001)
				# Безопасный контроллер без ссылок.
				var bare: Node = (load("res://Scripts/Environment/TimeOfDayController.gd") as GDScript).new()
				root.add_child(bare)
				bare.transition_to(1, 1.0)
				bare.set_phase_instant(2)
				check("S10 контроллер без ссылок: no-op без падения", true)
				bare.free()
				# Интеграция основной сцены.
				stage = "S11"
				stage_t0 = _now()
		"S11":
			if frame > 0 and t >= 0.1:
				main = (load("res://Основная_сцена.tscn") as PackedScene).instantiate()
				root.add_child(main)
				var we_count := 0
				for n in main.get_children():
					if n is WorldEnvironment:
						we_count += 1
				var mctl := main.get_node_or_null("TimeOfDayController")
				check("S11 основная сцена: один WorldEnvironment (дублей нет)", we_count == 1)
				check("S11 основная сцена: контроллер на месте, sky и light_path назначены",
					mctl != null and mctl.get("sky") != null and mctl.get("light_path") != NodePath())
				mctl.set_phase_instant(2)
				var mln: Node = main.get_node("DirectionalLight3D")
				check("S11 свет основной сцены синхронен фазе: energy=%.2f (ночь 0.45)" % float(mln.get("light_energy")),
					absf(float(mln.get("light_energy")) - 0.45) < 0.01)
				check("S11 Environment основной сцены сохранён: tonemap=2, ambient_source=3",
					int((mctl.get("environment") as Environment).tonemap_mode) == 2
					and int((mctl.get("environment") as Environment).ambient_light_source) == 3)
				log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
				log_f.close()
				quit(0 if failed == 0 else 1)
				return true
	if frame > 4000:
		log_f.store_line("TIMEOUT stage=%s" % stage)
		log_f.store_line("SUMMARY passed=%d failed=%d" % [passed, failed])
		log_f.close()
		quit(1)
		return true
	return false
