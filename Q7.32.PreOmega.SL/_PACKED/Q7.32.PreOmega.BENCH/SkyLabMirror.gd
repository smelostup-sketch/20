extends RefCounted
## SkyLabMirror — параллельное численное зеркало освещения skylab_clouds.gdshader
## (SKYLAB v0.4/v0.5, шаг 5/6). Зеркалирует ТОЛЬКО новый слой освещения:
##   E_ill = clamp(t_light·(0.35+0.65·h)·powder + luminance(ambient)·0.9, 0, 1)
##   цвет = ColorRamp5(E/sk_ramp_white) + silver lining (rim с дистанционным гейтом)
##   фон = палитра M1: mix(horizon, zenith, pow(0.5h+0.5, sk_grad_pow)) + ореол + клин
## Плотность/самозатенение берутся из зеркал CloudsTestBench (код плотности не менялся).
## Старые зеркала B3/B4 в бенче остаются валидными для omega_volumetric_clouds.gdshader.
## Самотест: _selftest/test_skylab_num.gd (headless, без GPU).

const BENCH := preload("res://Q7.32_SKYprav_3.1/CloudsTestBench.gd")



## source_color-uniform'ы читаются как Color — приводим к Vector3 (простые vec3 проходят как есть).
static func pv(mat: ShaderMaterial, n: String, def: Vector3 = Vector3.ZERO) -> Vector3:
	var v: Variant = mat.get_shader_parameter(n)
	if v == null:
		return def
	if v is Color:
		var c: Color = v
		return Vector3(c.r, c.g, c.b)
	return v as Vector3


## float-uniform: get_shader_parameter даёт null, если значение не записано в материал
## (дефолт живёт в шейдере) — fallback на дефолт шейдера.
static func pf(mat: ShaderMaterial, n: String, def: float) -> float:
	var v: Variant = mat.get_shader_parameter(n)
	if v == null:
		return def
	return float(v)


static func sstep(lo: float, hi: float, x: float) -> float:
	var d := hi - lo
	if absf(d) < 1e-6:
		return 1.0 if x >= lo else 0.0
	var t := clampf((x - lo) / d, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


##ColorRamp5: u4 ∈ [0..4] — позиция между стопами (0=тень глубины … 4=блик).
static func ramp_color(u4: float, r: Array) -> Vector3:
	var u := clampf(u4, 0.0, 4.0)
	if u < 1.0:
		return (r[0] as Vector3).lerp(r[1] as Vector3, u)
	if u < 2.0:
		return (r[1] as Vector3).lerp(r[2] as Vector3, u - 1.0)
	if u < 3.0:
		return (r[2] as Vector3).lerp(r[3] as Vector3, u - 2.0)
	return (r[3] as Vector3).lerp(r[4] as Vector3, u - 3.0)


static func _ramp_stops(mat: ShaderMaterial) -> Array:
	return [
		pv(mat, "sk_ramp0"),
		pv(mat, "sk_ramp1"),
		pv(mat, "sk_ramp2"),
		pv(mat, "sk_ramp3"),
		pv(mat, "sk_ramp4"),
	]


## Зеркало cloud_radiance_terms() в части SKYLAB-освещения (режим 0).
## dp — словарь параметров плотности бенча (CloudsTestBench.dp_defaults + материал).
static func skylab_terms(pos: Vector3, view_dir: Vector3, dp: Dictionary, mat: ShaderMaterial) -> Dictionary:
	var ldir: Vector3 = pv(mat, "cloud_light_direction", Vector3(-0.75, 0.5, -0.43))
	ldir = ldir / maxf(ldir.length(), 1e-5)
	var sp := {
		"light_steps": pf(mat, "light_steps", 4.0),
		"shadow_len": pf(mat, "shadow_ray_length", 4500.0),
		"use_powder": pf(mat, "use_powder", 1.0) > 0.5,
		"powder_strength": pf(mat, "powder_strength", 0.3),
	}
	var tl: float = BENCH.compute_light_transmittance(pos, ldir, dp, sp).t_light
	var bottom: float = pf(mat, "cloud_layer_bottom", 1500.0)
	var top: float = pf(mat, "cloud_layer_top", 3500.0)
	var hf := clampf((pos.y - bottom) / maxf(top - bottom, 1e-4), 0.0, 1.0)
	var d: float = BENCH.compute_density(pos, dp, pos.length())
	var powder := 1.0
	if pf(mat, "use_powder", 1.0) > 0.5:
		powder = lerpf(1.0, 1.0 - exp(-2.0 * d), pf(mat, "powder_strength", 0.3))
	var amb_sky := pv(mat, "cloud_ambient_sky_color")
	var amb_ground := pv(mat, "cloud_ambient_ground_color")
	var amb_col: Vector3 = amb_ground.lerp(amb_sky, hf) if pf(mat, "use_ambient_gradient", 1.0) > 0.5 else amb_sky
	var amb_lum := amb_col.dot(Vector3(0.33333, 0.33333, 0.33333))
	var e_ill := clampf(tl * (0.35 + 0.65 * hf) * powder + amb_lum * pf(mat, "sk_amb_w", 0.35) * hf, 0.0, 1.0)
	var u4 := clampf(pow(e_ill, pf(mat, "sk_ramp_gamma", 1.4)) / maxf(pf(mat, "sk_ramp_white", 1.0), 1e-3), 0.0, 1.0) * 4.0
	var color: Vector3 = ramp_color(u4, _ramp_stops(mat))
	var vd := view_dir.normalized()
	var rim_m := pow(maxf(vd.dot(ldir), 0.0), pf(mat, "sk_rim_exp", 4.0)) * (1.0 - tl)
	rim_m *= 1.0 - sstep(pf(mat, "sk_rim_fade_start", 4000.0),
			pf(mat, "sk_rim_fade_end", 12000.0), pos.length())
	var rim := rim_m * pf(mat, "sk_rim_int", 0.35)
	var rim_col: Vector3 = pv(mat, "sk_rim_col")
	color += rim_col * rim
	return {
		"E": e_ill,
		"t_light": tl,
		"height_frac": hf,
		"scatter": amb_lum * pf(mat, "sk_amb_w", 0.35) * hf,
		"powder": powder,
		"color": color,
		"rim": rim,
	}


## Зеркало sky_gradient() (без dithering: его вклад ≤ 1/255, учитывается допуском теста).
static func skylab_gradient(dir: Vector3, mat: ShaderMaterial) -> Vector3:
	var sd: Vector3 = pv(mat, "sk_sun_dir", Vector3(0.0, 0.0, -1.0)).normalized()
	var h := clampf(dir.y, -1.0, 1.0)
	var az3 := dir.dot(sd)
	var tp := clampf(0.5 + 0.5 * az3, 0.0, 1.0)
	var zen_mid: Vector3 = pv(mat, "sk_zenith") * pf(mat, "sk_zen_lift", 2.0)
	var sh := sstep(-0.03, 0.85, sd.y)
	var p_ant := lerpf(pf(mat, "sk_anti_p_lo", 0.6), pf(mat, "sk_anti_p_hi", 3.0), sh)
	var anti_c := pv(mat, "sk_anti_col", Vector3(0.0202, 0.00718, 0.0152)).lerp(zen_mid, 0.45 * sh)
	var hmask := 1.0 - sstep(0.0, 0.45, absf(h))
	var pole: Vector3
	if tp < 0.5:
		pole = anti_c.lerp(zen_mid, pow(clampf(tp / 0.5, 0.0, 1.0), p_ant))
	else:
		pole = zen_mid.lerp(pv(mat, "sk_horizon"), sstep(0.5, 1.0, tp))
	var base: Vector3 = zen_mid.lerp(pole, hmask)
	var dH := Vector2(dir.x, dir.z)
	var sH := Vector2(sd.x, sd.z)
	var azH := dH.dot(sH) / maxf(dH.length() * sH.length(), 1e-6)
	var band := pow(maxf(azH, 0.0), pf(mat, "sk_wedge_az", 3.0)) * exp(-absf(h) * pf(mat, "sk_wedge_k", 4.0)) * pf(mat, "sk_wedge_int", 0.35)
	base = base.lerp(pv(mat, "sk_glow_col"), clampf(band, 0.0, 1.0))
	var sp := clampf(az3, 0.0, 1.0)
	base = base.lerp(pv(mat, "sk_glow_col"), clampf(pow(sp, pf(mat, "sk_glow_exp", 6.0)) * pf(mat, "sk_glow_int", 0.30), 0.0, 1.0))
	base = base.lerp(pv(mat, "sk_below_col", Vector3(0.030, 0.011, 0.018)), sstep(0.0, -0.18, h) * pf(mat, "sk_below_int", 0.55))
	var low := 1.0 - sstep(0.0, 20.0, sd.y)
	base *= 1.0 - pf(mat, "sk_low_dim", 0.25) * low
	return base


## v0.5.3: адаптивное число шагов марша (тождественно sky_modes, предложение заказчика).
static func march_steps_for(dir_y: float, cheap: bool, march_steps: float) -> int:
	var base_steps := minf(march_steps, 32.0) if cheap else march_steps
	var angle_factor := 1.0
	if not cheap:
		angle_factor = clampf(1.0 / maxf(absf(dir_y), 0.25), 1.0, 4.0)
	return int(clampf(ceil(base_steps * angle_factor), 8.0, 256.0))


## Crisp-окно alpha из шага 6 (тождественно шейдеру).
static func crisp_alpha(a_raw: float, mat: ShaderMaterial) -> float:
	return sstep(pf(mat, "sk_alpha_lo", 0.10),
			pf(mat, "sk_alpha_hi", 0.90), a_raw)
