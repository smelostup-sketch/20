extends SceneTree
## baseline_fingerprint.gd — инструмент фазы 0 SKYprav (TZ «улучшение формы и освещения
## кучевых», п.6: «зафиксировать исходный результат на одинаковых настройках и ракурсе»).
## READ-ONLY: ничего не меняет, ничего не ассертит — печатает фингерпринт исходного
## состояния (детерминированный: без RNG, фиксированные сетки/лучи) и метрики формы для
## аудиторских гипотез бугристости. Все параметры — ИЗ МАТЕРИАЛА и preset_table()
## (данные, не хардкод). Последующие шаги правок перезапускают инструмент и сверяют
## фингерпринт: любое отличие объясняется в README шага (атрибуция, прецедент P4).
## Запуск:
##   godot --headless --path <проект> --script res://Q7.32_SKYprav_3.1/_selftest/baseline_fingerprint.gd
## Ракурс GPU-протокола (для визуальной фиксации заказчиком) — в README §6.
## v2 (prav_1.2): добавлен блок F8 — полосные энергии E100/E500/E2000 и статистика
## выступов (ранги d>0.3, CV — анти-регулярность): метрики выбора механизма фазы 2.

const MAT_PATH := "res://Q7.32_SKYprav_3.1/omega_clouds_test_material.tres"
const BENCH_PATH := "res://Q7.32_SKYprav_3.1/CloudsTestBench.gd"


func _init() -> void:
	var B: GDScript = load(BENCH_PATH)
	if not B.ensure_voxels():
		print("FINGERPRINT: .bin не загружены —фингерпринт невозможен")
		quit(1)
		return
	var mat: ShaderMaterial = load(MAT_PATH)
	# === dp/sp/lp строго из материала (аудит-точность: dp_defaults НЕ полагаемся) ===
	var dp := {
		"base_scale": float(mat.get_shader_parameter("cloud_base_scale")),
		"detail_scale": float(mat.get_shader_parameter("cloud_detail_scale")),
		"coverage": float(mat.get_shader_parameter("cloud_coverage")),
		"softness": float(mat.get_shader_parameter("cloud_softness")),
		"strength": float(mat.get_shader_parameter("cloud_detail_strength")),
		"erosion": float(mat.get_shader_parameter("cloud_erosion")),
		"edge_contrast": float(mat.get_shader_parameter("cloud_edge_contrast")),
		"offset": _v3(mat.get_shader_parameter("cloud_offset")),
		"base_fade": float(mat.get_shader_parameter("height_base_fade")),
		"top_fade": float(mat.get_shader_parameter("height_top_fade")),
		"fade_start": float(mat.get_shader_parameter("detail_fade_start")),
		"fade_end": float(mat.get_shader_parameter("detail_fade_end")),
		"bottom": float(mat.get_shader_parameter("cloud_layer_bottom")),
		"top": float(mat.get_shader_parameter("cloud_layer_top")),
		"use_curtain": bool(mat.get_shader_parameter("use_far_curtain")),
		"c_start": float(mat.get_shader_parameter("far_curtain_start")),
		"c_end": float(mat.get_shader_parameter("far_curtain_end")),
		"use_aniso": bool(mat.get_shader_parameter("use_height_anisotropy")),
		"aniso_base": float(mat.get_shader_parameter("aniso_base")),
		"aniso_top": float(mat.get_shader_parameter("aniso_top")),
		"h_stretch": float(mat.get_shader_parameter("cloud_horizontal_stretch")),
		"warp": float(mat.get_shader_parameter("cloud_warp_strength")),
		"warp_scale": float(mat.get_shader_parameter("cloud_warp_scale")),
		"use_mask": bool(mat.get_shader_parameter("use_weather_mask")),
		"w_scale": float(mat.get_shader_parameter("weather_scale")),
		"w_cut": float(mat.get_shader_parameter("weather_cut")),
		"w_soft": float(mat.get_shader_parameter("weather_soft")),
		"w_strength": float(mat.get_shader_parameter("weather_strength")),
		"fine_strength": float(mat.get_shader_parameter("cloud_fine_strength")),
		"fine_scale": float(mat.get_shader_parameter("cloud_fine_scale")),
	}
	var sp := {
		"use_shadow": bool(mat.get_shader_parameter("use_self_shadow")),
		"light_steps": float(mat.get_shader_parameter("light_steps")),
		"shadow_len": float(mat.get_shader_parameter("shadow_ray_length")),
		"use_powder": bool(mat.get_shader_parameter("use_powder")),
		"powder_strength": float(mat.get_shader_parameter("powder_strength")),
		"use_ms": bool(mat.get_shader_parameter("use_ms")),
		"ms_strength": float(mat.get_shader_parameter("ms_strength")),
		"ms_sun_gain": float(mat.get_shader_parameter("ms_sun_gain")),
		"ms_amb_gain": float(mat.get_shader_parameter("ms_amb_gain")),
	}
	var tbl: Dictionary = B.preset_table()
	var lp: Dictionary = B.hc_lp_from_preset(tbl["neutral"])
	var bottom := float(dp.bottom)
	var top := float(dp.top)
	var march_steps := int(float(mat.get_shader_parameter("march_steps")))
	var extinction := float(mat.get_shader_parameter("extinction_scale"))
	print("=== F0. Параметры материала (источник всех чисел аудита) ===")
	print("  base_scale=%.0f detail_scale=%.0f coverage=%.2f softness=%.2f strength=%.2f erosion=%.2f edge_contrast=%.1f" % [dp.base_scale, dp.detail_scale, dp.coverage, dp.softness, dp.strength, dp.erosion, dp.edge_contrast])
	print("  aniso base/top=%.2f/%.2f h_stretch=%.2f warp=%.0f@%.0f weather=%.0f cut=%.2f soft=%.2f str=%.2f" % [dp.aniso_base, dp.aniso_top, dp.h_stretch, dp.warp, dp.warp_scale, dp.w_scale, dp.w_cut, dp.w_soft, dp.w_strength])
	print("  профиль: base_fade=%.2f top_fade=%.2f | свет: steps=%.0f len=%.0f powder=%.2f ms=%.2f(%.2f/%.2f) | марш: steps=%d ext=%.4f" % [dp.base_fade, dp.top_fade, sp.light_steps, sp.shadow_len, sp.powder_strength, sp.ms_strength, sp.ms_sun_gain, sp.ms_amb_gain, march_steps, extinction])

	# === F1. Лучевой фингерпринт: 12 фиксированных мировых лучей ===
	print("=== F1. Фингерпринт 12 лучей (марш %d шагов, neutral-свет) ===" % march_steps)
	var sum_t := 0.0
	var sum_md := 0.0
	var sum_sl := 0.0
	for i in range(0, 12):
		var el := deg_to_rad(6.0 + 70.0 * float(i % 4) / 3.0)
		var az := TAU * float(i / 4) / 3.0 + deg_to_rad(17.0)
		var dir := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
		var m: Dictionary = B.compute_march(dir, bottom, top, march_steps, 30000.0, extinction, 0.01, dp)
		var md: Dictionary = B.compute_mean_density(dir, bottom, top, march_steps, dp)
		var ml: Dictionary = B.compute_march_lit(dir, bottom, top, march_steps, 30000.0, extinction, 0.01, dp, lp)
		var t := float(m.transmittance)
		var mdf := float(md.mean_density)
		var sl := _lum(ml.scattered as Vector3)
		sum_t += t
		sum_md += mdf
		sum_sl += sl
		print("  луч %2d el=%4.1f az=%5.1f: T=%.6f mean_d=%.6f scat_lum=%.6f" % [i, rad_to_deg(el), rad_to_deg(az), t, mdf, sl])
	print("  КОНТРОЛЬНЫЕ СУММЫ: ΣT=%.6f Σmean_d=%.6f Σscat=%.6f" % [sum_t, sum_md, sum_sl])

	# === F2. Полевая статистика на трёх высотах (сетка 24×24, шаг 1 км, t=2000) ===
	print("=== F2. Поле плотности: 3 высоты, сетка 24×24 км (t=2000 → fade≈1) ===")
	for h_frac in [0.25, 0.5, 0.75]:
		var y: float = bottom + (top - bottom) * float(h_frac)
		var st := _field_stats(B, dp, y, 2000.0)
		print("  h=%.2f (y=%.0f): mean=%.4f σ=%.4f clear=%.3f dense=%.3f mid=%.3f" % [h_frac, y, st.mean, st.std, st.clear, st.dense, st.mid])

	# === F3. Бугристость: ВЧ/НЧ энергия + доминирование детали над окном ===
	print("=== F3. Бугристость: hf=mean|Δd(100м)|, lf=mean|Δd(1000м)|, доли доминирования детали ===")
	var hf_sum := 0.0
	var lf_sum := 0.0
	var n_lines := 0
	var frac_over_soft := 0.0
	var frac_over_eff := 0.0
	var n_pts := 0
	var soft := float(dp.softness)
	var eff_soft: float = soft / maxf(float(dp.edge_contrast), 1.0)
	for li in range(0, 8):
		var z0 := float(li) * 3000.0 - 10500.0
		var prev_h := -1.0
		var prev_l := -1.0
		for si in range(0, 400):
			var p := Vector3(float(si) * 100.0 - 20000.0, 2500.0, z0)
			var d: float = B.compute_density(p, dp, 2000.0)
			if prev_h >= 0.0:
				hf_sum += absf(d - prev_h)
			prev_h = d
			if si % 10 == 0:
				if prev_l >= 0.0:
					lf_sum += absf(d - prev_l)
				prev_l = d
			# компонента детали в n: str·(detail−0.5) против окна sstep
			var pw: Vector3 = p + (dp.offset as Vector3)
			var det: float = B.sample_tex(B._wo_voxels, int(B.WO_SIZE), pw.x / float(dp.detail_scale), pw.y / float(dp.detail_scale), pw.z / float(dp.detail_scale))
			var dterm: float = absf(float(dp.strength) * (det - 0.5))
			if dterm > soft:
				frac_over_soft += 1.0
			if dterm > eff_soft:
				frac_over_eff += 1.0
			n_pts += 1
		n_lines += 1
	print("  hf/lf отношение = %.3f (hf=%.5f lf=%.5f на %d линиях)" % [hf_sum / maxf(lf_sum, 1e-9) * 10.0, hf_sum / float(n_lines * 399), lf_sum / float(n_lines * 40), n_lines])
	print("  доля точек, где |деталь| > soft (%.2f): %.1f %%; > soft/edge_contrast (%.3f): %.1f %%" % [soft, frac_over_soft / float(n_pts) * 100.0, eff_soft, frac_over_eff / float(n_pts) * 100.0])

	# === F4. Размеры масс / впадин / weather-зон (run-length вдоль тех же линий) ===
	print("=== F4. Run-length: массы (d>0.5), впадины (d<0.02), weather-зоны (w<cut) ===")
	var mass_runs: Array = []
	var gap_runs: Array = []
	var zone_runs: Array = []
	for li in range(0, 8):
		var z0 := float(li) * 3000.0 - 10500.0
		var run_m := 0
		var run_g := 0
		var run_z := 0
		for si in range(0, 400):
			var p := Vector3(float(si) * 100.0 - 20000.0, 2500.0, z0)
			var d: float = B.compute_density(p, dp, 2000.0)
			var pw: Vector3 = p + (dp.offset as Vector3)
			var w: float = B.sample_tex(B._pw_voxels, int(B.PW_SIZE), pw.x / float(dp.w_scale), pw.y / float(dp.w_scale), pw.z / float(dp.w_scale))
			if d > 0.5:
				run_m += 1
				if run_g > 0:
					gap_runs.append(run_g)
				run_g = 0
			elif d < 0.02:
				run_g += 1
				if run_m > 0:
					mass_runs.append(run_m)
				run_m = 0
			else:
				if run_m > 0:
					mass_runs.append(run_m)
				if run_g > 0:
					gap_runs.append(run_g)
				run_m = 0
				run_g = 0
			if w < float(dp.w_cut):
				run_z += 1
			else:
				if run_z > 0:
					zone_runs.append(run_z)
				run_z = 0
		if run_m > 0:
			mass_runs.append(run_m)
		if run_g > 0:
			gap_runs.append(run_g)
		if run_z > 0:
			zone_runs.append(run_z)
	print("  массы: n=%d средний ранг %.0f м (×100), максимальный %.0f м" % [mass_runs.size(), _mean(mass_runs) * 100.0, _max(mass_runs) * 100.0])
	print("  впадины: n=%d средний ранг %.0f м, максимальный %.0f м" % [gap_runs.size(), _mean(gap_runs) * 100.0, _max(gap_runs) * 100.0])
	print("  weather-зоны (w<cut): n=%d средний ранг %.0f м, максимальный %.0f м" % [zone_runs.size(), _mean(zone_runs) * 100.0, _max(zone_runs) * 100.0])

	# === F5. Эрозия и тонкие фрагменты ===
	print("=== F5. Эрозия: доля изменённых точек (ero 0.30 → 0) и изолированные фрагменты ===")
	var dp_noero: Dictionary = dp.duplicate()
	dp_noero["erosion"] = 0.0
	var changed := 0
	var total5 := 0
	var specks := 0
	var dense5 := 0
	for gi in range(0, 24):
		for gj in range(0, 24):
			var p := Vector3(float(gi) * 1000.0 - 11500.0, 2500.0, float(gj) * 1000.0 - 11500.0)
			var d1: float = B.compute_density(p, dp, 2000.0)
			var d0: float = B.compute_density(p, dp_noero, 2000.0)
			if absf(d1 - d0) > 1e-6:
				changed += 1
			total5 += 1
			if d1 > 0.02:
				dense5 += 1
				var iso := true
				for nb in [Vector3(150, 0, 0), Vector3(-150, 0, 0), Vector3(0, 0, 150), Vector3(0, 0, -150)]:
					if B.compute_density(p + nb, dp, 2000.0) > 0.02:
						iso = false
				if iso:
					specks += 1
	print("  эрозия меняет %.1f %% точек сетки; изолированные фрагменты: %d из %d плотных (%.1f %%)" % [float(changed) / float(total5) * 100.0, specks, dense5, float(specks) / maxf(float(dense5), 1.0) * 100.0])

	# === F6. Вертикальный профиль плотности ===
	print("=== F6. Вертикаль: mean d и dense-доля по высотам слоя ===")
	for h_frac in [0.05, 0.15, 0.30, 0.50, 0.70, 0.85, 0.95]:
		var y: float = bottom + (top - bottom) * float(h_frac)
		var st := _field_stats(B, dp, y, 2000.0)
		print("  h=%.2f: mean=%.4f dense=%.3f clear=%.3f" % [h_frac, st.mean, st.dense, st.clear])

	# === F7. Самозатенение: T_light во внутренних точках (neutral-солнце) ===
	print("=== F7. T_light (light march %d шага × %.0f м) во внутренних точках d>0.3 ===" % [int(sp.light_steps), float(sp.shadow_len)])
	var ldir: Vector3 = (lp.light_dir as Vector3).normalized()
	var tl_vals: Array = []
	for gi in range(0, 200):
		var fi := float(gi)
		var p := Vector3(fmod(fi * 613.0, 24000.0) - 12000.0, 2100.0 + fmod(fi * 7.3, 1200.0), fmod(fi * 853.0, 24000.0) - 12000.0)
		if B.compute_density(p, dp, 2000.0) > 0.3:
			var r: Dictionary = B.compute_light_transmittance(p, ldir, dp, sp)
			tl_vals.append(float(r.t_light))
	tl_vals.sort()
	if tl_vals.is_empty():
		print("  внутренних точек не найдено")
	else:
		var n := tl_vals.size()
		print("  n=%d: min=%.4f p10=%.4f med=%.4f p90=%.4f max=%.4f mean=%.4f" % [n, float(tl_vals[0]), float(tl_vals[int(n * 0.1)]), float(tl_vals[int(n / 2)]), float(tl_vals[int(n * 0.9)]), float(tl_vals[n - 1]), _mean_f(tl_vals)])

	# === F8 (v2, prav_1.2): полосные энергии плотности — инструмент фазы 2 ===
	# E100/E500/E2000 = mean|Δd| на горизонталях 100/500/2000 м (6 линий, y=2500):
	# мелкая фактура / средние выступы / крупные массы. «Средние округлые выступы»
	# (фаза 2 ТЗ) = рост E500 при стабильных E2000 (массы не размываются) и
	# контролируемом E100 (без пены). Плюс разнообразие выступов: CV рангов d>0.3
	# (анти-регулярность: одинаковые «шарики» дали бы CV → 0).
	print("=== F8. Полосные энергии E100/E500/E2000 и выступы (d>0.3) ===")
	var e100 := 0.0
	var e500 := 0.0
	var e2000 := 0.0
	var n100 := 0
	var n500 := 0
	var n2000 := 0
	var bump_runs: Array = []
	for li in range(0, 6):
		var z0 := float(li) * 4000.0 - 10000.0
		var run_b := 0
		var ds: Array = []
		for si in range(0, 400):
			var p := Vector3(float(si) * 100.0 - 20000.0, 2500.0, z0)
			ds.append(B.compute_density(p, dp, 2000.0))
		for si in range(0, 400):
			var d0: float = ds[si]
			if d0 > 0.3:
				run_b += 1
			elif run_b > 0:
				bump_runs.append(run_b)
				run_b = 0
			if si + 1 < 400:
				e100 += absf(float(ds[si + 1]) - d0)
				n100 += 1
			if si + 5 < 400:
				e500 += absf(float(ds[si + 5]) - d0)
				n500 += 1
			if si + 20 < 400:
				e2000 += absf(float(ds[si + 20]) - d0)
				n2000 += 1
		if run_b > 0:
			bump_runs.append(run_b)
	e100 /= maxf(float(n100), 1.0)
	e500 /= maxf(float(n500), 1.0)
	e2000 /= maxf(float(n2000), 1.0)
	var b_mean := _mean(bump_runs)
	var b_var := 0.0
	for v in bump_runs:
		b_var += (float(v) - b_mean) * (float(v) - b_mean)
	var b_cv: float = sqrt(b_var / maxf(float(bump_runs.size()), 1.0)) / maxf(b_mean, 1e-9)
	print("  E100=%.5f E500=%.5f E2000=%.5f | E500/E100=%.3f E2000/E500=%.3f" % [e100, e500, e2000, e500 / maxf(e100, 1e-9), e2000 / maxf(e500, 1e-9)])
	print("  выступы d>0.3: n=%d средний ранг %.0f м, CV рангов %.3f (анти-регулярность)" % [bump_runs.size(), b_mean * 100.0, b_cv])
	print("=== FINGERPRINT DONE ===")
	quit(0)


func _v3(v: Variant) -> Vector3:
	if v is Color:
		var c: Color = v
		return Vector3(c.r, c.g, c.b)
	if v is Vector3:
		return v
	return Vector3.ZERO


func _lum(v: Vector3) -> float:
	return v.dot(Vector3(0.3333, 0.3333, 0.3333))


func _field_stats(B: GDScript, dp: Dictionary, y: float, t: float) -> Dictionary:
	var sum := 0.0
	var sum2 := 0.0
	var n_clear := 0
	var n_dense := 0
	var cnt := 0
	for gi in range(0, 24):
		for gj in range(0, 24):
			var p := Vector3(float(gi) * 1000.0 - 11500.0, y, float(gj) * 1000.0 - 11500.0)
			var d: float = B.compute_density(p, dp, t)
			sum += d
			sum2 += d * d
			cnt += 1
			if d < 0.02:
				n_clear += 1
			elif d > 0.8:
				n_dense += 1
	var mean := sum / float(cnt)
	return {"mean": mean, "std": sqrt(maxf(sum2 / float(cnt) - mean * mean, 0.0)),
		"clear": float(n_clear) / float(cnt), "dense": float(n_dense) / float(cnt),
		"mid": float(cnt - n_clear - n_dense) / float(cnt)}


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


func _mean_f(a: Array) -> float:
	return _mean(a)


func _max(a: Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, float(v))
	return m
