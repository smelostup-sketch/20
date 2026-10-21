extends Node
## CloudsTestBench — диагностический стенд компонента Q7.32_SKY_D3 (фаза C, этап C3).
## C3: ВНУТРИСЕССИОННОЕ МЕНЮ НАСТРОЕК (клавиша 9): полупрозрачная боковая панель со ВСЕМИ
## параметрами неба (русские названия + бытовые пояснения), правки применяются к материалу
## в реальном времени; панель занимает ~36% ширины справа и НЕ перекрывает область осмотра.
## Автономен: не зависит от игровых систем проекта; удаление узла Bench из сцены
## оставляет небо работающим (текстуры в этом случае должен назначать внешний риг —
## см. README «Назначение текстур без стенда»).
##
## Управление при ЗАПУЩЕННОЙ сцене (F6):
##   ПРАВАЯ кнопка мыши (зажать и вести) — вращение камеры (yaw/pitch), как в редакторе
##   Стрелки Влево/Вправо/Вверх/Вниз — то же вращение с клавиатуры
##   0-8 — cloud_debug_mode §7 промта: 0 финальный рендер, 1 плотность, 2 T, 3 поле
##         self-shadowing, 4 знак HG, 5 powder-съём, 6 MS, 7 ambient, 8 atmo-фактор
##   F5 — цикл геометрических режимов 9-12 (t_near/путь/чистое небо); маска 9 также в меню
##   9 (клавиша) — открыть/закрыть меню настроек; все ползунки меню пишут uniform'ы сразу
##   F1 — солнце вкл/выкл (cloud_light_strength ↔ 0, прежнее значение восстанавливается)
##   F2 — Henyey-Greenstein вкл/выкл (use_hg_phase; выкл = изотроп phase≡1)
##   F3 — ambient-градиент вкл/выкл (use_ambient_gradient; выкл = постоянный sky-ambient)
##   F4 — цикл cloud_debug_mode 0-8; F5 — цикл геометрических режимов 9-12
##   F6 / F7 / F8 / F9 — профили качества: Performance / Balanced / Quality / Reference
##   (таблица profile_table(): tier subpass + march_steps + light_steps + упрощения;
##   tier меняет compile-time вариант шейдера патчем #define SKY_TIER, кэш вариантов)
##   H — напечатать в Output: интервал [t_near, t_far], mean_density, T, шаги, early-exit
##       + разложение освещения B3: cosθ, phase, солнечный и ambient-члены, накопленное S
## В 3D-вьюпорте РЕДАКТОРА (без F6) стенд не работает — там крутите штатным orbit-режимом
## редактора; для проверки неба запускайте сцену.
##
## B3-ОБЯЗАННОСТИ стенда (добавлены к B1/B2):
##   - синхронизация cloud_light_direction с DirectionalLight3D сцены (export
##     sync_sun_from_light): свет -Z светит, +Z (basis.z) = направление НА источник —
##     конвенция продакшн-неба (TimeOfDayController/SkyPhaseProfile). Вращаете свет
##     в редакторе/рантайме — солнце неба следует за ним (запись с epsilon-гейтом,
##     как в контроллере). Для ручного управления uniform'ом выключите sync (Remote
##     → Bench → Sync Sun From Light) — иначе стенд перезапишет значение в тот же кадр;
##   - переключатели эффектов F1/F2/F3 (§4.3 промта: каждый эффект независимо
##     включается/отключается для сравнения вклада);
##   - зеркала освещения B3: hg_phase(), compute_lighting_terms(), compute_radiance(),
##     compute_march_lit() (scattered как Vector3 + раздельное накопление
##     sun/ambient-вклада) — для численных проверок без рендера;
##   - зеркала B4 (сохранены как регрессионные): compute_light_transmittance(),
##     compute_radiance_terms_b4(), compute_march_b4();
##   - зеркала B5 с ТАБЛИЦЕЙ ГЕЙТОВ: compute_terms_b5() (плейсхолдеры пропущенных
##     членов: t_light=1, powder=1, ms=0, amb=0) и compute_march_diag() (единый марш,
##     выходы всех режимов 0-8);
##   - B6: profile_table() (данные профилей) и apply_profile() (смена tier-варианта
##     шейдера + uniform'ов; текстуры и синк солнца переназначаются после смены шейдера);
##   - зеркала B1/B2 сохранены БЕЗ ИЗМЕНЕНИЙ: compute_interval, compute_density,
##     compute_mean_density, compute_march (скалярный, физика A5).
##
## B1/B2-ОБЯЗАННОСТИ (наследуются):
##   - один раз при старте собрать 3D-текстуры из .bin (CloudTextureLoader) и назначить
##     их в материал (персистенция ImageTexture3D в 4.7 сломана — см. loader);
##   - CPU-дрейф поля от ветра (wind_direction/wind_speed → cloud_offset;
##     speed=0 → поле статично/детерминировано);
##   - точность зеркал: GDScript float64 vs GLSL float32 — совпадение до ~1e-3
##     (структурные/статистические проверки).

const EPS := 1e-6
const PW_SIZE := 128
const WO_SIZE := 32
const PW_PATH := "res://Q7.32_SKY_D3/noise_pw_128.bin"
const WO_PATH := "res://Q7.32_SKY_D3/noise_worley_32.bin"
const PITCH_LIMIT_DEG := 89.0
const DEFAULT_LIGHT_STRENGTH := 0.70	# дефолт материала (восстановление после F1)

@export var camera_path: NodePath = ^"../Camera3D"
@export var env_path: NodePath = ^"../WorldEnvironment"
@export var sun_light_path: NodePath = ^"../DirectionalLight3D"	# B3: источник для синка направления
@export var sync_sun_from_light := true		# B3: писать cloud_light_direction из DirectionalLight3D
@export var pitch_speed_deg := 40.0			# скорость клавишного наклона, °/с
@export var yaw_speed_deg := 60.0			# скорость клавишного поворота, °/с
@export var mouse_sensitivity_deg := 0.15	# чувствительность мыши, °/пиксель
@export var wind_direction := Vector3(1.0, 0.0, 0.3)	# направление дрейфа поля (нормализуется)
@export var wind_speed := 0.0					# м/с; 0 = статичное поле (детерминированные тесты)
@export var default_profile := 1				# B6: 0 Perf / 1 Balanced / 2 Quality / 3 Reference

var _cam: Camera3D = null
var _mat: ShaderMaterial = null
var _sun_light: DirectionalLight3D = null
var _base_offset := Vector3.ZERO
var _drift := Vector3.ZERO
var _saved_light_strength := -1.0	# F1: значение до выключения солнца
var _cdm := 0.0					# F4: текущий cloud_debug_mode (0-8)
var _gdm := 9.0					# F5: текущий геометрический режим (9-12)
var _profile := -1				# B6: текущий профиль
var _shader_variants := {}		# B6: кэш tier-вариантов шейдера (0/1/2)
var _template_code := ""		# B6: код шаблона (tier 1) для патча
var _pw_tex: ImageTexture3D = null
var _wo_tex: ImageTexture3D = null

const _CDM_LABELS := [
	"финальный рендер", "базовая плотность", "T (Beer-Lambert)",
	"поле self-shadowing (T_light)", "знак вклада HG", "снятое powder-ом",
	"накопленный MS", "накопленный ambient", "фактор atmo-перспективы",
	"маска HIT/MISS (A3)", "t_near (A3)", "длина пути (A3)", "чистое небо (A3)"]

## CPU-копии вокселей для зеркала (загружаются один раз).
static var _pw_voxels := PackedByteArray()
static var _conv := "minus05"   # отладочная конвенция тексель-центров
static var _flips := 0          # отладочная маска инверсий осей (bit0=x, bit1=y, bit2=z)
static var _wo_voxels := PackedByteArray()


func _ready() -> void:
	_cam = get_node_or_null(camera_path) as Camera3D
	var we := get_node_or_null(env_path) as WorldEnvironment
	if _cam == null or we == null:
		push_warning("CloudsTestBench: Camera3D/WorldEnvironment не найдены — стенд отключён")
		return
	var sky_res: Sky = we.environment.sky
	if sky_res != null and sky_res.sky_material is ShaderMaterial:
		_mat = sky_res.sky_material
	else:
		push_warning("CloudsTestBench: Sky/ShaderMaterial не найдены — режимы не переключаются")
		return
	_sun_light = get_node_or_null(sun_light_path) as DirectionalLight3D
	if sync_sun_from_light and _sun_light == null:
		push_warning("CloudsTestBench: DirectionalLight3D не найден — cloud_light_direction остаётся из материала")
	_assign_textures()
	_template_code = _mat.shader.code
	_base_offset = _param_vec3("cloud_offset", Vector3.ZERO)
	apply_profile(clampi(default_profile, 0, 3))
	_build_ui()
	print("[Bench] ПКМ-drag — камера | 0-6 — режимы (5=объём, 6=T) | F1/F2/F3 — солнце/HG/ambient | H — луч+свет | sync_sun=",
		sync_sun_from_light and _sun_light != null, " | wind_speed=", wind_speed)


## Ленивая загрузка CPU-копий вокселей (для зеркала в headless-тестах и в рантайме).
static func ensure_voxels() -> bool:
	if _pw_voxels.is_empty() or _wo_voxels.is_empty():
		var loader = load("res://Q7.32_SKY_D3/CloudTextureLoader.gd")
		_pw_voxels = loader.load_voxels(PW_PATH, PW_SIZE)
		_wo_voxels = loader.load_voxels(WO_PATH, WO_SIZE)
	return not _pw_voxels.is_empty() and not _wo_voxels.is_empty()


## Сборка и назначение 3D-текстур (один раз при старте).
func _assign_textures() -> void:
	var t0 := Time.get_ticks_msec()
	var loader_script = load("res://Q7.32_SKY_D3/CloudTextureLoader.gd")
	var pw_tex: ImageTexture3D = loader_script.load_texture(PW_PATH, PW_SIZE)
	var wo_tex: ImageTexture3D = loader_script.load_texture(WO_PATH, WO_SIZE)
	if pw_tex == null:
		push_error("CloudsTestBench: PW-текстура не собрана — использую заглушку (небо будет ровным)")
		pw_tex = loader_script.placeholder_texture()
	if wo_tex == null:
		push_error("CloudsTestBench: Worley-текстура не собрана — использую заглушку")
		wo_tex = loader_script.placeholder_texture()
	_pw_tex = pw_tex
	_wo_tex = wo_tex
	_mat.set_shader_parameter("noise_pw", pw_tex)
	_mat.set_shader_parameter("noise_worley", wo_tex)
	# CPU-копии для зеркала
	ensure_voxels()
	print("[Bench] текстуры собраны из .bin за %d мс (pw=%d³ wo=%d³)" % [Time.get_ticks_msec() - t0, PW_SIZE, WO_SIZE])


## === ЗЕРКАЛА ШЕЙДЕРНЫХ ФУНКЦИЙ ===

## Зеркало layer_interval() (A3).
static func compute_interval(dir: Vector3, bottom: float, top: float) -> Dictionary:
	var d := dir.normalized()
	if absf(d.y) <= EPS:
		return {"hit": false, "t_near": 0.0, "t_far": 0.0}
	var t1 := bottom / d.y
	var t2 := top / d.y
	var t_near := maxf(minf(t1, t2), 0.0)
	var t_far := maxf(t1, t2)
	return {"hit": t_far > t_near, "t_near": t_near, "t_far": t_far}


## Трилинейная выборка из воксельного массива в GPU-соглашении:
## u — нормированные координаты (периоды), repeat-wrap, центры текселей (i+0.5)/n.
static func sample_tex(data: PackedByteArray, n: int, ux: float, uy: float, uz: float) -> float:
	if data.is_empty():
		return 0.0
	var fn := float(n)
	var shift := 0.5
	if _conv == "none":
		shift = 0.0
	elif _conv == "plus05":
		shift = -0.5
	if _flips & 1:
		ux = -ux
	if _flips & 2:
		uy = -uy
	if _flips & 4:
		uz = -uz
	var x := fposmod(ux * fn - shift, fn)
	var y := fposmod(uy * fn - shift, fn)
	var z := fposmod(uz * fn - shift, fn)
	var x0 := int(floorf(x))
	var y0 := int(floorf(y))
	var z0 := int(floorf(z))
	var fx := x - float(x0)
	var fy := y - float(y0)
	var fz := z - float(z0)
	var x1: int = (x0 + 1) % n
	var y1: int = (y0 + 1) % n
	var z1: int = (z0 + 1) % n
	var nn := n * n
	var c000 := float(data[z0 * nn + y0 * n + x0]) * (1.0 / 255.0)
	var c100 := float(data[z0 * nn + y0 * n + x1]) * (1.0 / 255.0)
	var c010 := float(data[z0 * nn + y1 * n + x0]) * (1.0 / 255.0)
	var c110 := float(data[z0 * nn + y1 * n + x1]) * (1.0 / 255.0)
	var c001 := float(data[z1 * nn + y0 * n + x0]) * (1.0 / 255.0)
	var c101 := float(data[z1 * nn + y0 * n + x1]) * (1.0 / 255.0)
	var c011 := float(data[z1 * nn + y1 * n + x0]) * (1.0 / 255.0)
	var c111 := float(data[z1 * nn + y1 * n + x1]) * (1.0 / 255.0)
	return lerpf(
		lerpf(lerpf(c000, c100, fx), lerpf(c010, c110, fx), fy),
		lerpf(lerpf(c001, c101, fx), lerpf(c011, c111, fx), fy),
		fz)


## Параметры плотности одним словарём (значения по умолчанию = дефолты материала).
static func dp_defaults(dp: Dictionary) -> Dictionary:
	var out := {
		"base_scale": 16000.0,
		"detail_scale": 1200.0,
		"coverage": 0.42,
		"softness": 0.12,
		"strength": 0.18,
		"offset": Vector3.ZERO,
		"base_fade": 0.15,
		"top_fade": 0.35,
		"erosion": 0.40,
		"stretch": 2.5,
		"edge_contrast": 1.0,	# D3: контраст кромки (1.0 = побитово D2)
		"fade_start": 4000.0,
		"fade_end": 12000.0,
		"bottom": 1500.0,
		"top": 3500.0,
		"use_curtain": false,	# регрессионный базис = поле без curtain (метрики B2/C3)
		"c_start": 12000.0,
		"c_end": 24000.0,
		"use_aniso": false,
		"aniso_base": 3.0,
		"aniso_top": 0.70,
		"h_stretch": 1.0,
		"warp": 0.0,
		"warp_scale": 9000.0,
		"use_mask": false,
		"w_scale": 70000.0,
		"w_cut": 0.35,
		"w_soft": 0.15,
		"w_strength": 0.85,
	}
	for k in dp.keys():
		out[k] = dp[k]
	return out


## Зеркало cloud_density() (B1+B2; в B3 формула не менялась).
static func compute_density(pos: Vector3, dp: Dictionary = {}, t: float = 0.0) -> float:
	var q := dp_defaults(dp)
	var off: Vector3 = q.offset
	var pw := pos + off
	var pw2 := pw
	if q.warp > 0.0:
		var wn := sample_tex(_pw_voxels, PW_SIZE, pw.x / q.warp_scale, pw.y / q.warp_scale, pw.z / q.warp_scale)
		pw2 = pw + Vector3(0.0, (wn - 0.5) * 2.0 * q.warp, 0.0)
	var hgt_a := clampf((pos.y - q.bottom) / maxf(q.top - q.bottom, 1e-4), 0.0, 1.0)
	var stretch_eff: float = lerpf(q.aniso_base, q.aniso_top, smoothstep(0.15, 0.85, hgt_a)) if q.use_aniso else q.stretch
	var hs := maxf(q.h_stretch, 0.05)
	var shape := sample_tex(_pw_voxels, PW_SIZE, pw2.x / (q.base_scale * hs), pw2.y / (q.base_scale * stretch_eff), pw2.z / (q.base_scale * hs))
	var detail := sample_tex(_wo_voxels, WO_SIZE, pw.x / q.detail_scale, pw.y / q.detail_scale, pw.z / q.detail_scale)
	var fade: float = 1.0 - smoothstep(q.fade_start, q.fade_end, t)
	var ero: float = q.erosion * fade
	var str: float = q.strength * (0.25 + 0.75 * fade)
	var n: float = shape - ero * (1.0 - detail) * (1.0 - shape) + str * (detail - 0.5)
	if q.use_mask:
		var w := sample_tex(_pw_voxels, PW_SIZE, pw.x / q.w_scale, pw.y / q.w_scale, pw.z / q.w_scale)
		var clear := 1.0 - smoothstep(q.w_cut - q.w_soft, q.w_cut + q.w_soft, w)
		n -= clear * q.w_strength * (q.coverage + q.softness + 0.1)
	var curtain := 1.0
	if q.use_curtain:
		curtain = 1.0 - smoothstep(q.c_start, q.c_end, t)
	var d0 := smoothstep(q.coverage - q.softness, q.coverage + q.softness, n)
	# D3: контраст кромки — как в шейдере, до curtain/профиля; 1.0 → побитово D2.
	if q.edge_contrast != 1.0:
		d0 = clampf((d0 - 0.5) * maxf(q.edge_contrast, 0.0) + 0.5, 0.0, 1.0)
	var d := d0 * curtain
	var thickness: float = maxf(q.top - q.bottom, 1e-4)
	var hgt := clampf((pos.y - q.bottom) / thickness, 0.0, 1.0)
	var profile := smoothstep(0.0, q.base_fade, hgt) * (1.0 - smoothstep(1.0 - q.top_fade, 1.0, hgt))
	return d * profile


## B3: зеркало hg_phase() — Henyey-Greenstein, нормировка изотроп=1, clamp g ±0.9.
static func hg_phase(cos_theta: float, g: float) -> float:
	var gg := clampf(g, -0.9, 0.9)
	var d := 1.0 + gg * gg - 2.0 * gg * cos_theta
	return (1.0 - gg * gg) / (d * sqrt(d))


## B3: параметры освещения одним словарём (значения по умолчанию = дефолты материала).
static func lp_defaults(lp: Dictionary) -> Dictionary:
	var out := {
		"light_dir": Vector3(-0.75, 0.50, -0.43),
		"light_color": Vector3(1.0, 0.97, 0.92),
		"light_strength": 0.70,
		"use_hg": true,
		"hg_g": 0.5,
		"use_dual": false,
		"hg_g2": 0.25,
		"dual_mix": 0.5,
		"diffuse_mix": 0.45,
		"use_ramp": false,
		"ramp_near": Vector3(0.95, 0.30, 0.25),
		"ramp_far": Vector3(0.70, 0.08, 0.08),
		"use_amb_sky": false,
		"amb_gain": 1.2,
		"g_use": true,
		"g_hor": Vector3(0.42, 0.55, 0.75),
		"g_zen": Vector3(0.20, 0.35, 0.60),
		"g_anti": Vector3(0.26, 0.30, 0.52),
		"g_mid": Vector3(0.50, 0.68, 0.88),
		"g_pink": Vector3(0.80, 0.70, 0.75),
		"g_white": Vector3(0.98, 0.96, 0.85),
		"g_sharp": 1.0,	# D3: резкость переходов палитры (1.0 = побитово D2)
		"amb_sky": Vector3(0.55, 0.63, 0.82),
		"amb_ground": Vector3(0.25, 0.27, 0.34),
		"amb_energy": 0.45,
		"use_amb_grad": true,
		"albedo": Vector3(0.95, 0.95, 0.97),
		"bottom": 1500.0,
		"top": 3500.0,
	}
	for k in lp.keys():
		out[k] = lp[k]
	return out


## B3: зеркало cloud_radiance() по членам: sun (прямой·HG·альбедо) и ambient (градиент·альбедо).
static func compute_lighting_terms(pos: Vector3, view_dir: Vector3, lp: Dictionary = {}) -> Dictionary:
	var q := lp_defaults(lp)
	var ldir: Vector3 = q.light_dir
	ldir = ldir / maxf(ldir.length(), 1e-5)	# guard как в шейдере: нулевой вектор → cosθ=0, без NaN
	var light_color: Vector3 = q.light_color
	var albedo: Vector3 = q.albedo
	var amb_sky: Vector3 = q.amb_sky
	var amb_ground: Vector3 = q.amb_ground
	var cos_theta := view_dir.normalized().dot(ldir)
	var phase: float = hg_phase(cos_theta, q.hg_g) if q.use_hg else 1.0
	phase = lerpf(phase, 1.0, clampf(q.diffuse_mix, 0.0, 1.0))
	var sun_col: Vector3 = q.light_color
	if q.use_ramp:
		var cn := clampf(cos_theta, -1.0, 1.0)
		var far_c: Vector3 = q.ramp_far
		var near_c: Vector3 = q.ramp_near
		sun_col = far_c.lerp(near_c, smoothstep(0.30, 0.80, cn)).lerp(q.light_color, smoothstep(0.93, 0.995, cn))
	var sun: Vector3 = sun_col * (q.light_strength * phase) * albedo
	var thickness: float = maxf(q.top - q.bottom, 1e-4)
	var h := clampf((pos.y - q.bottom) / thickness, 0.0, 1.0)
	var amb_top: Vector3 = amb_sky
	if q.use_amb_sky:
		var gp := {"use_grad": q.g_use, "horizon": q.g_hor, "zenith": q.g_zen,
			"antisolar": q.g_anti, "band_mid": q.g_mid, "band_pink": q.g_pink,
			"band_white": q.g_white, "grad_sharp": q.g_sharp}
		amb_top = compute_sky_gradient(Vector3(0, 1, 0), ldir, gp) * q.amb_gain
	var amb_col: Vector3 = amb_ground.lerp(amb_top, h) if q.use_amb_grad else amb_top
	var amb: Vector3 = amb_col * q.amb_energy * albedo
	return {"cos_theta": cos_theta, "phase": phase, "sun": sun, "ambient": amb,
		"total": sun + amb, "height_frac": h}


## B3: зеркало cloud_radiance() (суммарная радиация точки).
static func compute_radiance(pos: Vector3, view_dir: Vector3, lp: Dictionary = {}) -> Vector3:
	var terms := compute_lighting_terms(pos, view_dir, lp)
	var total: Vector3 = terms.total
	return total


## Зеркало предпросмотра режима 4 (A4; освещение не участвует — как в шейдере).
static func compute_mean_density(dir: Vector3, bottom: float, top: float, steps := 32, dp: Dictionary = {}) -> Dictionary:
	var iv := compute_interval(dir, bottom, top)
	if not iv.hit:
		return {"hit": false, "mean_density": 0.0}
	var q := dp_defaults(dp)
	q.bottom = bottom
	q.top = top
	var n := clampi(steps, 4, 128)
	var seg: float = (iv.t_far - iv.t_near) / float(n)
	var acc := 0.0
	var d := dir.normalized()
	for i in range(n):
		var t: float = iv.t_near + (float(i) + 0.5) * seg
		acc += compute_density(d * t, q, t)
	return {"hit": true, "mean_density": acc / float(n)}


## Зеркало физики марша (A5, БЕЗ освещения): скалярный scattered при albedo=1.
## Инвариант: scattered + T = 1. Сохранён из B2 для регрессии физики.
static func compute_march(dir: Vector3, bottom: float, top: float, steps := 64,
		max_len := 30000.0, extinction := 0.0025, early_exit := 0.01, dp: Dictionary = {}) -> Dictionary:
	var iv := compute_interval(dir, bottom, top)
	if not iv.hit:
		return {"hit": false, "transmittance": 1.0, "scattered": 0.0,
			"steps_used": 0, "t_end": 0.0, "early_exited": false}
	var q := dp_defaults(dp)
	q.bottom = bottom
	q.top = top
	var n := clampi(steps, 8, 256)
	var t_end: float = minf(float(iv.t_far), float(iv.t_near) + max_len)
	var seg: float = (t_end - float(iv.t_near)) / float(n)
	var tr := 1.0
	var sc := 0.0
	var used := 0
	var exited := false
	var d := dir.normalized()
	if seg > 0.0:
		for i in range(n):
			var t: float = float(iv.t_near) + (float(i) + 0.5) * seg
			var dens := compute_density(d * t, q, t)
			var step_tr := exp(-dens * extinction * seg)
			sc += tr * (1.0 - step_tr)
			tr *= step_tr
			used += 1
			if tr < early_exit:
				exited = true
				break
	return {"hit": true, "transmittance": tr, "scattered": sc,
		"steps_used": used, "t_end": t_end, "early_exited": exited}


## B3: зеркало режима 5 — марш с освещением. scattered: Vector3; вклад солнца и
## ambient накапливается РАЗДЕЛЬНО (sun_scattered + ambient_scattered == scattered
## точно, float64) — инструмент проверки вклада каждого эффекта (§4.3 промта).
## Transmittance НЕ зависит от освещения (инвариант B3: T ≡ T из compute_march).
static func compute_march_lit(dir: Vector3, bottom: float, top: float, steps := 64,
		max_len := 30000.0, extinction := 0.0025, early_exit := 0.01,
		dp: Dictionary = {}, lp: Dictionary = {}) -> Dictionary:
	var iv := compute_interval(dir, bottom, top)
	if not iv.hit:
		return {"hit": false, "transmittance": 1.0, "scattered": Vector3.ZERO,
			"sun_scattered": Vector3.ZERO, "ambient_scattered": Vector3.ZERO,
			"steps_used": 0, "t_end": 0.0, "early_exited": false}
	var q := dp_defaults(dp)
	q.bottom = bottom
	q.top = top
	var lq := lp_defaults(lp)
	lq.bottom = bottom
	lq.top = top
	var n := clampi(steps, 8, 256)
	var t_end: float = minf(float(iv.t_far), float(iv.t_near) + max_len)
	var seg: float = (t_end - float(iv.t_near)) / float(n)
	var tr := 1.0
	var sc := Vector3.ZERO
	var sc_sun := Vector3.ZERO
	var sc_amb := Vector3.ZERO
	var used := 0
	var exited := false
	var d := dir.normalized()
	if seg > 0.0:
		for i in range(n):
			var t: float = float(iv.t_near) + (float(i) + 0.5) * seg
			var pos := d * t
			var dens := compute_density(pos, q, t)
			var step_tr := exp(-dens * extinction * seg)
			var terms := compute_lighting_terms(pos, d, lq)
			var sun_v: Vector3 = terms.sun
			var amb_v: Vector3 = terms.ambient
			var w := tr * (1.0 - step_tr)
			sc += w * (sun_v + amb_v)
			sc_sun += w * sun_v
			sc_amb += w * amb_v
			tr *= step_tr
			used += 1
			if tr < early_exit:
				exited = true
				break
	return {"hit": true, "transmittance": tr, "scattered": sc,
		"sun_scattered": sc_sun, "ambient_scattered": sc_amb,
		"steps_used": used, "t_end": t_end, "early_exited": exited}


## B4: параметры self-shadowing/powder/MS одним словарём (дефолты = дефолты материала).
static func sp_defaults(sp: Dictionary) -> Dictionary:
	var out := {
		"use_shadow": true,
		"light_steps": 4.0,
		"shadow_len": 4500.0,
		"use_powder": true,
		"powder_strength": 0.6,
		"use_ms": true,
		"ms_strength": 0.5,
		"ms_sun_gain": 0.45,
		"ms_amb_gain": 0.60,
		"use_ms2": false,
		"ms2_gain": 0.25,
	}
	for k in sp.keys():
		out[k] = sp[k]
	return out


## B4: зеркало light_transmittance() — Beer-Lambert марш к источнику + ранний обрыв.
static func compute_light_transmittance(pos: Vector3, ldir: Vector3,
		dp: Dictionary = {}, sp: Dictionary = {}) -> Dictionary:
	var q := sp_defaults(sp)
	var n := clampi(int(q.light_steps), 1, 16)
	var seg: float = float(q.shadow_len) / float(n)
	if seg <= 0.0:
		return {"t_light": 1.0, "samples_used": 0}
	var dq := dp_defaults(dp)
	var sigma := 0.0
	var used := 0
	for i in range(n):
		var spp: Vector3 = pos + ldir * ((float(i) + 0.5) * seg)
		sigma += compute_density(spp, dq, spp.length()) * seg
		used += 1
		if sigma * 0.0025 > 4.60517:
			break
	return {"t_light": exp(-sigma * 0.0025), "samples_used": used}


## B4: зеркало cloud_radiance_terms() — члены радиации точки.
static func compute_radiance_terms_b4(pos: Vector3, view_dir: Vector3, d: float,
		dp: Dictionary = {}, lp: Dictionary = {}, sp: Dictionary = {}) -> Dictionary:
	var q := lp_defaults(lp)
	var sq := sp_defaults(sp)
	var ldir: Vector3 = q.light_dir
	ldir = ldir / maxf(ldir.length(), 1e-5)
	var light_color: Vector3 = q.light_color
	var albedo: Vector3 = q.albedo
	var amb_sky: Vector3 = q.amb_sky
	var amb_ground: Vector3 = q.amb_ground
	var cos_theta := view_dir.normalized().dot(ldir)
	var phase: float = hg_phase(cos_theta, q.hg_g) if q.use_hg else 1.0
	if q.use_hg and q.use_dual:
		phase = lerpf(phase, hg_phase(cos_theta, q.hg_g2), clampf(q.dual_mix, 0.0, 1.0))
	phase = lerpf(phase, 1.0, clampf(q.diffuse_mix, 0.0, 1.0))
	var sun_col: Vector3 = q.light_color
	if q.use_ramp:
		var cn := clampf(cos_theta, -1.0, 1.0)
		var far_c: Vector3 = q.ramp_far
		var near_c: Vector3 = q.ramp_near
		sun_col = far_c.lerp(near_c, smoothstep(0.30, 0.80, cn)).lerp(q.light_color, smoothstep(0.93, 0.995, cn))
	var t_light := 1.0
	if sq.use_shadow and q.light_strength > 0.0:
		var dpq := dp_defaults(dp)
		dpq.bottom = q.bottom
		dpq.top = q.top
		var lt: Dictionary = compute_light_transmittance(pos, ldir, dpq, sq)
		t_light = float(lt.t_light)
	var powder := 1.0
	if sq.use_powder:
		powder = lerpf(1.0, 1.0 - exp(-2.0 * d), sq.powder_strength)
	var sun_nopow: Vector3 = sun_col * (q.light_strength * phase) * t_light
	var sun: Vector3 = sun_nopow * powder
	var thickness: float = maxf(q.top - q.bottom, 1e-4)
	var h := clampf((pos.y - q.bottom) / thickness, 0.0, 1.0)
	var amb_top: Vector3 = amb_sky
	if q.use_amb_sky:
		var gp := {"use_grad": q.g_use, "horizon": q.g_hor, "zenith": q.g_zen,
			"antisolar": q.g_anti, "band_mid": q.g_mid, "band_pink": q.g_pink,
			"band_white": q.g_white, "grad_sharp": q.g_sharp}
		amb_top = compute_sky_gradient(Vector3(0, 1, 0), ldir, gp) * q.amb_gain
	var amb_col: Vector3 = amb_ground.lerp(amb_top, h) if q.use_amb_grad else amb_top
	var amb: Vector3 = amb_col * q.amb_energy
	var ms := Vector3.ZERO
	if sq.use_ms:
		ms = sq.ms_strength * (sun_col * q.light_strength * (sq.ms_sun_gain * (1.0 - t_light))
			+ amb_col * q.amb_energy * (sq.ms_amb_gain * d))
	return {"cos_theta": cos_theta, "phase": phase, "t_light": t_light, "powder": powder,
		"sun": sun * albedo, "ambient": amb * albedo, "ms": ms * albedo,
		"sun_nopow": sun_nopow * albedo, "sun_col": sun_col, "total": (sun + amb + ms) * albedo}


## B4: зеркало режима 5 — полный марш с освещением ч.2 и atmo-композитингом.
## ap: {use_atmo, atmo_color, atmo_start, atmo_end, sky_color}.
static func ap_defaults(ap: Dictionary) -> Dictionary:
	var out := {
		"use_atmo": true,
		"atmo_color": Vector3(0.55, 0.65, 0.85),
		"atmo_start": 6000.0,
		"atmo_end": 26000.0,
		"sky_color": Vector3(0.32, 0.47, 0.68),
	}
	for k in ap.keys():
		out[k] = ap[k]
	return out


static func compute_march_b4(dir: Vector3, bottom: float, top: float, steps := 64,
		max_len := 30000.0, extinction := 0.0025, early_exit := 0.01,
		dp: Dictionary = {}, lp: Dictionary = {}, sp: Dictionary = {}, ap: Dictionary = {}) -> Dictionary:
	var iv := compute_interval(dir, bottom, top)
	if not iv.hit:
		return {"hit": false, "transmittance": 1.0, "scattered": Vector3.ZERO,
			"sun_scattered": Vector3.ZERO, "ambient_scattered": Vector3.ZERO,
			"ms_scattered": Vector3.ZERO, "t_light_mean": 1.0, "atmo_factor": 0.0,
			"final_color": Vector3.ZERO, "steps_used": 0, "early_exited": false}
	var q := dp_defaults(dp)
	q.bottom = bottom
	q.top = top
	var lq := lp_defaults(lp)
	lq.bottom = bottom
	lq.top = top
	var sq := sp_defaults(sp)
	var aq := ap_defaults(ap)
	var n := clampi(steps, 8, 256)
	var t_end: float = minf(float(iv.t_far), float(iv.t_near) + max_len)
	var seg: float = (t_end - float(iv.t_near)) / float(n)
	var tr := 1.0
	var sc := Vector3.ZERO
	var sc_sun := Vector3.ZERO
	var sc_amb := Vector3.ZERO
	var sc_ms := Vector3.ZERO
	var sc_ms2 := Vector3.ZERO
	var wsum := 0.0
	var tl_w := 0.0
	var used := 0
	var exited := false
	var d := dir.normalized()
	if seg > 0.0:
		for i in range(n):
			var t: float = float(iv.t_near) + (float(i) + 0.5) * seg
			var pos := d * t
			var dens := compute_density(pos, q, t)
			var step_tr := exp(-dens * extinction * seg)
			var terms := compute_radiance_terms_b4(pos, d, dens, q, lq, sq)
			var sun_v: Vector3 = terms.sun
			var amb_v: Vector3 = terms.ambient
			var ms_v: Vector3 = terms.ms
			var tl: float = terms.t_light
			var ms2_v := Vector3.ZERO
			if sq.use_ms2:
				ms2_v = sq.ms2_gain * (lq.light_color as Vector3) * lq.light_strength \
						* ((1.0 - tl) * (1.0 - tr))
			var w := tr * (1.0 - step_tr)
			sc += w * (sun_v + amb_v + ms_v + ms2_v)
			sc_sun += w * sun_v
			sc_amb += w * amb_v
			sc_ms += w * ms_v
			sc_ms2 += w * ms2_v
			wsum += w
			tl_w += w * float(terms.t_light)
			tr *= step_tr
			used += 1
			if tr < early_exit:
				exited = true
				break
	var f: float = smoothstep(aq.atmo_start, aq.atmo_end, float(iv.t_near)) if aq.use_atmo else 0.0
	var cloud_c: Vector3 = sc.lerp(aq.atmo_color * (1.0 - tr), f)
	var sky_c: Vector3 = aq.sky_color
	return {"hit": true, "transmittance": tr, "scattered": sc,
		"sun_scattered": sc_sun, "ambient_scattered": sc_amb, "ms_scattered": sc_ms,
		"ms2_scattered": sc_ms2,
		"t_light_mean": tl_w / maxf(wsum, 1e-6), "atmo_factor": f,
		"final_color": sky_c * tr + cloud_c, "steps_used": used, "early_exited": exited}


## C5: зеркало закона stretch(h) из шейдера (для проверок и справки в меню).
static func aniso_stretch_at(h: float, dp: Dictionary = {}) -> float:
	var q := dp_defaults(dp)
	if not q.use_aniso:
		return q.stretch
	return lerpf(q.aniso_base, q.aniso_top, smoothstep(0.15, 0.85, clampf(h, 0.0, 1.0)))


## B5: гейты режимов (таблица из шейдера sky()): какие члены вычисляются в режиме cdm.
static func diag_gates(cdm: float) -> Dictionary:
	return {
		"terms": cdm < 0.5 or (cdm > 2.5 and cdm < 7.5),
		"shadow": cdm < 0.5 or (cdm > 2.5 and cdm < 6.5),
		"powder": cdm < 0.5 or (cdm > 3.5 and cdm < 5.5),
		"ms": cdm < 0.5 or (cdm > 5.5 and cdm < 6.5),
		"amb": cdm < 0.5 or (cdm > 6.5 and cdm < 7.5),
	}


## B5: зеркало cloud_radiance_terms() с гейтами режима; пропущенные члены — плейсхолдеры
## (t_light=1, powder=1, ms=0, amb=0) — БЕЗ альбедо (альбедо применяет марш/композит).
static func compute_terms_b5(pos: Vector3, view_dir: Vector3, d: float, cdm: float,
		dp: Dictionary = {}, lp: Dictionary = {}, sp: Dictionary = {}) -> Dictionary:
	var g := diag_gates(cdm)
	if not g.terms:
		return {"cos_theta": 0.0, "phase": 1.0, "t_light": 1.0, "powder": 1.0,
			"sun": Vector3.ZERO, "ambient": Vector3.ZERO, "ms": Vector3.ZERO,
			"sun_nopow": Vector3.ZERO}
	var q := lp_defaults(lp)
	var sq := sp_defaults(sp)
	var ldir: Vector3 = q.light_dir
	ldir = ldir / maxf(ldir.length(), 1e-5)
	var light_color: Vector3 = q.light_color
	var amb_sky: Vector3 = q.amb_sky
	var amb_ground: Vector3 = q.amb_ground
	var cos_theta := view_dir.normalized().dot(ldir)
	var phase: float = hg_phase(cos_theta, q.hg_g) if q.use_hg else 1.0
	if q.use_hg and q.use_dual:
		phase = lerpf(phase, hg_phase(cos_theta, q.hg_g2), clampf(q.dual_mix, 0.0, 1.0))
	phase = lerpf(phase, 1.0, clampf(q.diffuse_mix, 0.0, 1.0))
	var sun_col: Vector3 = q.light_color
	if q.use_ramp:
		var cn := clampf(cos_theta, -1.0, 1.0)
		var far_c: Vector3 = q.ramp_far
		var near_c: Vector3 = q.ramp_near
		sun_col = far_c.lerp(near_c, smoothstep(0.30, 0.80, cn)).lerp(q.light_color, smoothstep(0.93, 0.995, cn))
	var t_light := 1.0
	if g.shadow and sq.use_shadow and q.light_strength > 0.0:
		var dpq := dp_defaults(dp)
		dpq.bottom = q.bottom
		dpq.top = q.top
		var lt: Dictionary = compute_light_transmittance(pos, ldir, dpq, sq)
		t_light = float(lt.t_light)
	var powder := 1.0
	if g.powder and sq.use_powder:
		powder = lerpf(1.0, 1.0 - exp(-2.0 * d), sq.powder_strength)
	var sun_nopow: Vector3 = sun_col * (q.light_strength * phase) * t_light
	var sun: Vector3 = sun_nopow * powder
	var thickness: float = maxf(q.top - q.bottom, 1e-4)
	var h := clampf((pos.y - q.bottom) / thickness, 0.0, 1.0)
	var amb_top: Vector3 = amb_sky
	if q.use_amb_sky:
		var gp := {"use_grad": q.g_use, "horizon": q.g_hor, "zenith": q.g_zen,
			"antisolar": q.g_anti, "band_mid": q.g_mid, "band_pink": q.g_pink,
			"band_white": q.g_white, "grad_sharp": q.g_sharp}
		amb_top = compute_sky_gradient(Vector3(0, 1, 0), ldir, gp) * q.amb_gain
	var amb_col: Vector3 = amb_ground.lerp(amb_top, h) if q.use_amb_grad else amb_top
	var amb: Vector3 = amb_col * q.amb_energy if g.amb else Vector3.ZERO
	var ms := Vector3.ZERO
	if g.ms and sq.use_ms:
		ms = sq.ms_strength * (sun_col * q.light_strength * (sq.ms_sun_gain * (1.0 - t_light))
			+ amb_col * q.amb_energy * (sq.ms_amb_gain * d))
	return {"cos_theta": cos_theta, "phase": phase, "t_light": t_light, "powder": powder,
		"sun": sun, "ambient": amb, "ms": ms, "sun_nopow": sun_nopow, "sun_col": sun_col}


## B5: зеркало единого марша sky() — выходы всех режимов 0-8 для одного луча.
static func compute_march_diag(dir: Vector3, bottom: float, top: float, steps := 64,
		max_len := 30000.0, extinction := 0.0025, early_exit := 0.01, cdm := 0.0,
		dp: Dictionary = {}, lp: Dictionary = {}, sp: Dictionary = {}, ap: Dictionary = {}) -> Dictionary:
	var iv := compute_interval(dir, bottom, top)
	var aq := ap_defaults(ap)
	if not iv.hit:
		return {"hit": false, "transmittance": 1.0, "mean_d": 0.0, "t_light_mean": 1.0,
			"hg_sig_w": 0.0, "pow_rem_w": 0.0, "sun_acc": Vector3.ZERO,
			"amb_acc": Vector3.ZERO, "ms_acc": Vector3.ZERO, "atmo_factor": 0.0,
			"mode0_color": aq.sky_color, "steps_used": 0, "early_exited": false}
	var q := dp_defaults(dp)
	q.bottom = bottom
	q.top = top
	var lq := lp_defaults(lp)
	lq.bottom = bottom
	lq.top = top
	var sq := sp_defaults(sp)
	var g := diag_gates(cdm)
	var albedo: Vector3 = lq.albedo
	var n := clampi(steps, 8, 256)
	var t_end: float = minf(float(iv.t_far), float(iv.t_near) + max_len)
	var seg: float = (t_end - float(iv.t_near)) / float(n)
	var tr := 1.0
	var dsum := 0.0
	var used := 0
	var wsum := 0.0
	var tl_w := 0.0
	var hg_sig := 0.0
	var pow_rem := 0.0
	var sun_acc := Vector3.ZERO
	var amb_acc := Vector3.ZERO
	var ms_acc := Vector3.ZERO
	var exited := false
	var d := dir.normalized()
	var atmo_f: float = smoothstep(aq.atmo_start, aq.atmo_end, float(iv.t_near)) if aq.use_atmo else 0.0
	if seg > 0.0:
		for i in range(n):
			var t: float = float(iv.t_near) + (float(i) + 0.5) * seg
			var pos := d * t
			var dens := compute_density(pos, q, t)
			dsum += dens
			used += 1
			var step_tr := exp(-dens * extinction * seg)
			var w := tr * (1.0 - step_tr)
			wsum += w
			if g.terms:
				var terms := compute_terms_b5(pos, d, dens, cdm, q, lq, sq)
				var sun_v: Vector3 = terms.sun
				var amb_v: Vector3 = terms.ambient
				var ms_v: Vector3 = terms.ms
				var tl: float = terms.t_light
				var pwd: float = terms.powder
				var sun_np: Vector3 = terms.sun_nopow
				var ms2_v := Vector3.ZERO
				if sq.use_ms2:
					ms2_v = sq.ms2_gain * (lq.light_color as Vector3) * lq.light_strength \
							* ((1.0 - tl) * (1.0 - tr))
				sun_acc += w * sun_v
				amb_acc += w * amb_v
				ms_acc += w * (ms_v + ms2_v)
				tl_w += w * tl
				var light_color: Vector3 = lq.light_color
				var sun_iso: Vector3 = light_color * (lq.light_strength * (tl * pwd))
				hg_sig += w * (sun_v - sun_iso).dot(Vector3(0.33333, 0.33333, 0.33333))
				pow_rem += w * (sun_np - sun_v).dot(Vector3(0.33333, 0.33333, 0.33333))
			tr *= step_tr
			if tr < early_exit:
				exited = true
				break
	var wguard := maxf(wsum, 1e-6)
	var cloud_c: Vector3 = (sun_acc + amb_acc + ms_acc) * albedo
	cloud_c = cloud_c.lerp(aq.atmo_color * (1.0 - tr), atmo_f)
	return {"hit": true, "transmittance": tr, "mean_d": dsum / float(maxi(used, 1)),
		"t_light_mean": tl_w / wguard, "hg_sig_w": hg_sig / wguard,
		"pow_rem_w": pow_rem / wguard, "sun_acc": sun_acc, "amb_acc": amb_acc,
		"ms_acc": ms_acc, "atmo_factor": atmo_f,
		"mode0_color": aq.sky_color * tr + cloud_c, "steps_used": used, "early_exited": exited}


## B6: таблица профилей (§6 промта: гипотезы зафиксированы как дефолты профилей).
## tier: 0 = full (Reference), 1 = half-res subpass, 2 = quarter-res subpass.
static func profile_table() -> Dictionary:
	return {
		0: {"name": "Performance", "tier": 2, "march": 32.0, "light": 3.0,
			"powder": false, "ms": false},
		1: {"name": "Balanced", "tier": 1, "march": 48.0, "light": 4.0,
			"powder": true, "ms": true},
		2: {"name": "Quality", "tier": 1, "march": 64.0, "light": 6.0,
			"powder": true, "ms": true},
		3: {"name": "Reference", "tier": 0, "march": 64.0, "light": 6.0,
			"powder": true, "ms": true},
	}


## B6: compile-time вариант шейдера для tier (кэш; tier 1 = исходный ресурс).
func _tier_shader(tier: int) -> Shader:
	if _shader_variants.has(tier):
		return _shader_variants[tier]
	var sh: Shader
	if tier == 1 or _template_code == "":
		sh = _mat.shader
	else:
		sh = Shader.new()
		sh.code = _template_code.replace("#define SKY_TIER 1", "#define SKY_TIER %d" % tier)
	_shader_variants[tier] = sh
	return sh


## B6: применение профиля: tier-вариант + uniform'ы; после смены шейдера переназначаем
## текстуры (параметры материала могут сброситься) — синк солнца догонит сам (epsilon-гейт).
func apply_profile(idx: int) -> void:
	if _mat == null:
		return
	var tbl := profile_table()
	if not tbl.has(idx):
		return
	var pr: Dictionary = tbl[idx]
	var tier: int = int(pr.tier)
	# B6-ограничение (спайк): бэкенд GL3 не даёт рабочие half/quarter subpass-текстуры
	# (чёрное небо на llvmpipe, Vulkan — норма) → обходной путь: tier 0 (full) на GL3,
	# профиль продолжает управлять шагами/эффектами. Стоимость на GL3 выше — документировано.
	if tier != 0 and RenderingServer.get_current_rendering_driver_name() == "opengl3":
		push_warning("CloudsTestBench: subpass tier%d недоступен на GL3 — применяю tier 0 (full)" % tier)
		tier = 0
	var sh := _tier_shader(tier)
	if _mat.shader != sh:
		_mat.shader = sh
		if _pw_tex != null:
			_mat.set_shader_parameter("noise_pw", _pw_tex)
		if _wo_tex != null:
			_mat.set_shader_parameter("noise_worley", _wo_tex)
	_mat.set_shader_parameter("march_steps", pr.march)
	_mat.set_shader_parameter("light_steps", pr.light)
	_mat.set_shader_parameter("use_powder", pr.powder)
	_mat.set_shader_parameter("use_ms", pr.ms)
	_profile = idx
	print("[Bench] профиль %s: tier=%d march=%.0f light=%.0f powder=%s ms=%s"
		% [pr.name, tier, pr.march, pr.light, str(pr.powder), str(pr.ms)])
	if _ui_open:
		_ui_refresh()


## C1: пресеты состояний §2 промта — ДАННЫЕ (значения света из производственных
## профилей фаз profiles/sky_*.tres; ambient облаков — артистические данные стенда).
## В шейдере состояния НЕ зашиты: пресет лишь пишет uniform'ы и свет сцены.
static func preset_table() -> Dictionary:
	return {
		"sunset": {"use_height_anisotropy": false, "h_stretch": 1.0, "warp": 0.0, "use_weather_mask": false, "base_scale": 16000.0, "coverage": 0.42, "erosion": 0.40, "offset": Vector3(8000, 1600, 0), "dir": Vector3(-0.4, 0.25, -0.8), "color": Color(1.0, 0.55, 0.45, 1),
			"strength": 1.0, "amb_sky": Color(0.50, 0.28, 0.26, 1),
			"amb_gnd": Color(0.22, 0.10, 0.10, 1), "amb_energy": 0.35,
			"scene_color": Color(1.0, 0.62, 0.35, 1), "scene_energy": 2.2,
			"sky_color": Color(0.45, 0.25, 0.28, 1), "atmo_color": Color(0.75, 0.45, 0.40, 1),
			"sun_size": 0.03, "sun_intensity": 14.0, "sun_halo_strength": 0.4, "sun_halo_power": 90.0,
			"sun_disk_color": Color(1.0, 0.95, 0.88, 1),
			"grad_horizon": Color(0.72, 0.30, 0.22, 1), "grad_zenith": Color(0.25, 0.15, 0.30, 1),
			"grad_antisolar": Color(0.18, 0.12, 0.28, 1), "grad_mid": Color(0.50, 0.42, 0.55, 1),
			"grad_pink": Color(0.95, 0.45, 0.35, 1), "grad_white": Color(1.0, 0.88, 0.65, 1),
			"use_sun_color_ramp": true, "ramp_near": Color(0.95, 0.40, 0.30, 1),
			"ramp_far": Color(0.75, 0.15, 0.12, 1), "use_ambient_from_sky": true, "ambient_sky_gain": 1.3},
		"twilight": {"use_height_anisotropy": false, "h_stretch": 1.0, "warp": 0.0, "use_weather_mask": false, "base_scale": 16000.0, "coverage": 0.42, "erosion": 0.40, "offset": Vector3(8000, 1600, 0), "dir": Vector3(-0.35, 0.10, -0.93), "color": Color(0.48, 0.38, 0.60, 1),
			"strength": 0.35, "amb_sky": Color(0.24, 0.21, 0.42, 1),
			"amb_gnd": Color(0.10, 0.09, 0.18, 1), "amb_energy": 0.30,
			"scene_color": Color(0.55, 0.45, 0.75, 1), "scene_energy": 0.7,
			"sky_color": Color(0.18, 0.14, 0.30, 1), "atmo_color": Color(0.35, 0.28, 0.50, 1),
			"sun_size": 0.025, "sun_intensity": 6.0, "sun_halo_strength": 0.3, "sun_halo_power": 120.0,
			"sun_disk_color": Color(0.95, 0.93, 1.0, 1),
			"grad_horizon": Color(0.45, 0.25, 0.45, 1), "grad_zenith": Color(0.12, 0.10, 0.25, 1),
			"grad_antisolar": Color(0.08, 0.07, 0.18, 1), "grad_mid": Color(0.30, 0.25, 0.48, 1),
			"grad_pink": Color(0.65, 0.35, 0.50, 1), "grad_white": Color(0.85, 0.75, 0.90, 1),
			"use_sun_color_ramp": true, "ramp_near": Color(0.85, 0.55, 0.75, 1),
			"ramp_far": Color(0.50, 0.28, 0.52, 1), "use_ambient_from_sky": true, "ambient_sky_gain": 1.1},
		"night": {"use_height_anisotropy": false, "h_stretch": 1.0, "warp": 0.0, "use_weather_mask": false, "base_scale": 16000.0, "coverage": 0.42, "erosion": 0.40, "offset": Vector3(8000, 1600, 0), "dir": Vector3(0.35, 0.55, -0.75), "color": Color(0.55, 0.65, 0.95, 1),
			"strength": 0.5, "amb_sky": Color(0.10, 0.13, 0.25, 1),
			"amb_gnd": Color(0.05, 0.06, 0.12, 1), "amb_energy": 0.25,
			"scene_color": Color(0.62, 0.70, 0.95, 1), "scene_energy": 0.45,
			"sky_color": Color(0.04, 0.06, 0.14, 1), "atmo_color": Color(0.10, 0.14, 0.28, 1),
			"sun_size": 0.045, "sun_intensity": 4.0, "sun_halo_strength": 0.25, "sun_halo_power": 300.0,
			"sun_disk_color": Color(0.92, 0.94, 1.0, 1),
			"grad_horizon": Color(0.10, 0.13, 0.24, 1), "grad_zenith": Color(0.03, 0.05, 0.12, 1),
			"grad_antisolar": Color(0.02, 0.03, 0.09, 1), "grad_mid": Color(0.06, 0.09, 0.20, 1),
			"grad_pink": Color(0.12, 0.15, 0.26, 1), "grad_white": Color(0.85, 0.90, 1.0, 1),
			"use_sun_color_ramp": true, "ramp_near": Color(0.75, 0.82, 1.0, 1),
			"ramp_far": Color(0.40, 0.50, 0.80, 1), "use_ambient_from_sky": true, "ambient_sky_gain": 1.0},
		"neutral": {"dir": Vector3(-0.75, 0.50, -0.43), "color": Color(1.0, 0.97, 0.92, 1),
			"use_height_anisotropy": true, "aniso_base": 3.0, "aniso_top": 0.7,
			"h_stretch": 1.4, "warp": 220.0, "warp_scale": 9000.0,
			"use_far_curtain": true, "c_start": 12000.0, "c_end": 24000.0,
			"use_weather_mask": true, "base_scale": 35500.0, "coverage": 0.23, "softness": 0.17,
			"detail_scale": 3000.0, "detail_strength": 0.60, "erosion": 0.30, "stretch": 1.75,
			"offset": Vector3(3000, 1600, 9000), "weather_scale": 30000.0, "weather_cut": 0.14,
			"weather_soft": 0.06, "weather_strength": 0.9,
			"strength": 0.70, "amb_sky": Color(0.55, 0.63, 0.82, 1),
			"amb_gnd": Color(0.25, 0.27, 0.34, 1), "amb_energy": 0.45,
			"scene_color": Color(1.0, 1.0, 1.0, 1), "scene_energy": 2.2,
			"sky_color": Color(0.32, 0.47, 0.68, 1), "atmo_color": Color(0.55, 0.65, 0.85, 1),
			"sun_size": 0.02, "sun_intensity": 16.0, "sun_halo_strength": 0.25, "sun_halo_power": 250.0,
			"sun_disk_color": Color(1.0, 0.98, 0.95, 1),
			"grad_horizon": Color(0.42, 0.55, 0.75, 1), "grad_zenith": Color(0.20, 0.35, 0.60, 1),
			"grad_antisolar": Color(0.18, 0.18, 0.38, 1), "grad_mid": Color(0.50, 0.68, 0.88, 1),
			"grad_pink": Color(0.80, 0.70, 0.75, 1), "grad_white": Color(0.98, 0.97, 0.88, 1),
			"use_sun_color_ramp": false, "use_ambient_from_sky": false, "ambient_sky_gain": 1.2,
			"layer_top": 3500.0,
			"atmo_start": 6000.0, "atmo_end": 26000.0},
		# C1-art: кроваво-фиолетовый закат с большими кучевыми облаками (художественный
		# пресет: низкое кровавое солнце, фиолетовая заливка, огненная дымка, массы ×1.5)
		"blood_sunset": {"use_height_anisotropy": false, "h_stretch": 1.0, "warp": 0.0, "use_weather_mask": false, "base_scale": 28000.0, "coverage": 0.38, "erosion": 0.36, "offset": Vector3(3000, 1600, 9000), "dir": Vector3(-0.18, 0.24, -0.95), "color": Color(1.0, 0.20, 0.14, 1),
			"strength": 1.05, "amb_sky": Color(0.26, 0.10, 0.38, 1),
			"amb_gnd": Color(0.10, 0.04, 0.09, 1), "amb_energy": 0.28,
			"scene_color": Color(1.0, 0.30, 0.22, 1), "scene_energy": 1.6,
			"sky_color": Color(0.24, 0.05, 0.20, 1), "atmo_color": Color(0.38, 0.10, 0.12, 1),
			"sun_size": 0.045, "sun_intensity": 24.0, "sun_halo_strength": 0.6, "sun_halo_power": 50.0,
			"sun_disk_color": Color(1.0, 0.93, 0.86, 1),
			"grad_horizon": Color(0.65, 0.09, 0.15, 1), "grad_zenith": Color(0.20, 0.12, 0.16, 1),
			"grad_antisolar": Color(0.14, 0.10, 0.26, 1), "grad_mid": Color(0.42, 0.52, 0.72, 1),
			"grad_pink": Color(0.95, 0.35, 0.30, 1), "grad_white": Color(1.0, 0.93, 0.65, 1),
			"use_sun_color_ramp": true, "ramp_near": Color(0.90, 0.22, 0.18, 1),
			"ramp_far": Color(0.65, 0.07, 0.07, 1), "use_ambient_from_sky": true, "ambient_sky_gain": 1.0,
			"layer_top": 4000.0,
			"atmo_start": 5000.0, "atmo_end": 20000.0},
	}


## C1: применение пресета: uniform'ы неба + DirectionalLight3D (базис из направления,
## цвет/энергия из данных пресета). Синк солнца подхватит направление сам.
func apply_preset(preset_name: String) -> void:
	if _mat == null:
		return
	var tbl := preset_table()
	if not tbl.has(preset_name):
		push_warning("CloudsTestBench: неизвестный пресет %s" % preset_name)
		return
	var pr: Dictionary = tbl[preset_name]
	var dir_v: Vector3 = (pr.dir as Vector3).normalized()
	_mat.set_shader_parameter("cloud_light_direction", dir_v)
	_mat.set_shader_parameter("cloud_light_color", pr.color)
	_mat.set_shader_parameter("cloud_light_strength", pr.strength)
	_mat.set_shader_parameter("cloud_ambient_sky_color", pr.amb_sky)
	_mat.set_shader_parameter("cloud_ambient_ground_color", pr.amb_gnd)
	_mat.set_shader_parameter("cloud_ambient_energy", pr.amb_energy)
	_mat.set_shader_parameter("sky_color", pr.sky_color)
	_mat.set_shader_parameter("atmo_color", pr.atmo_color)
	# опциональные ключи плотности/геометрии масс (пресет может менять и форму)
	if pr.has("base_scale"):
		_mat.set_shader_parameter("cloud_base_scale", pr.base_scale)
	if pr.has("coverage"):
		_mat.set_shader_parameter("cloud_coverage", pr.coverage)
	if pr.has("softness"):
		_mat.set_shader_parameter("cloud_softness", pr.softness)
	if pr.has("detail_scale"):
		_mat.set_shader_parameter("cloud_detail_scale", pr.detail_scale)
	if pr.has("detail_strength"):
		_mat.set_shader_parameter("cloud_detail_strength", pr.detail_strength)
	if pr.has("stretch"):
		_mat.set_shader_parameter("cloud_vertical_stretch", pr.stretch)
	if pr.has("use_far_curtain"):
		_mat.set_shader_parameter("use_far_curtain", pr.use_far_curtain)
	if pr.has("c_start"):
		_mat.set_shader_parameter("far_curtain_start", pr.c_start)
	if pr.has("c_end"):
		_mat.set_shader_parameter("far_curtain_end", pr.c_end)
	if pr.has("use_height_anisotropy"):
		_mat.set_shader_parameter("use_height_anisotropy", pr.use_height_anisotropy)
	if pr.has("aniso_base"):
		_mat.set_shader_parameter("aniso_base", pr.aniso_base)
	if pr.has("aniso_top"):
		_mat.set_shader_parameter("aniso_top", pr.aniso_top)
	if pr.has("h_stretch"):
		_mat.set_shader_parameter("cloud_horizontal_stretch", pr.h_stretch)
	if pr.has("warp"):
		_mat.set_shader_parameter("cloud_warp_strength", pr.warp)
	if pr.has("warp_scale"):
		_mat.set_shader_parameter("cloud_warp_scale", pr.warp_scale)
	if pr.has("use_weather_mask"):
		_mat.set_shader_parameter("use_weather_mask", pr.use_weather_mask)
	if pr.has("weather_scale"):
		_mat.set_shader_parameter("weather_scale", pr.weather_scale)
	if pr.has("weather_cut"):
		_mat.set_shader_parameter("weather_cut", pr.weather_cut)
	if pr.has("weather_soft"):
		_mat.set_shader_parameter("weather_soft", pr.weather_soft)
	if pr.has("weather_strength"):
		_mat.set_shader_parameter("weather_strength", pr.weather_strength)
	if pr.has("layer_top"):
		_mat.set_shader_parameter("cloud_layer_top", pr.layer_top)
	if pr.has("erosion"):
		_mat.set_shader_parameter("cloud_erosion", pr.erosion)
	if pr.has("edge_contrast"):
		_mat.set_shader_parameter("cloud_edge_contrast", pr.edge_contrast)
	if pr.has("grad_sharp"):
		_mat.set_shader_parameter("sky_grad_sharp", pr.grad_sharp)
	if pr.has("atmo_start"):
		_mat.set_shader_parameter("atmo_start", pr.atmo_start)
	if pr.has("atmo_end"):
		_mat.set_shader_parameter("atmo_end", pr.atmo_end)
	if pr.has("offset"):
		_mat.set_shader_parameter("cloud_offset", pr.offset)
	if pr.has("grad_horizon"):
		_mat.set_shader_parameter("sky_horizon_color", pr.grad_horizon)
		_mat.set_shader_parameter("sky_zenith_color", pr.grad_zenith)
		_mat.set_shader_parameter("sky_antisolar_color", pr.grad_antisolar)
		_mat.set_shader_parameter("sky_band_mid", pr.grad_mid)
		_mat.set_shader_parameter("sky_band_pink", pr.grad_pink)
		_mat.set_shader_parameter("sky_band_white", pr.grad_white)
	if pr.has("use_sun_color_ramp"):
		_mat.set_shader_parameter("use_sun_color_ramp", pr.use_sun_color_ramp)
	if pr.has("ramp_near"):
		_mat.set_shader_parameter("ramp_near_color", pr.ramp_near)
	if pr.has("ramp_far"):
		_mat.set_shader_parameter("ramp_far_color", pr.ramp_far)
	if pr.has("use_ambient_from_sky"):
		_mat.set_shader_parameter("use_ambient_from_sky", pr.use_ambient_from_sky)
	if pr.has("ambient_sky_gain"):
		_mat.set_shader_parameter("ambient_sky_gain", pr.ambient_sky_gain)
	if pr.has("sun_disk_color"):
		_mat.set_shader_parameter("sun_disk_color", pr.sun_disk_color)
	if pr.has("sun_size"):
		_mat.set_shader_parameter("sun_size", pr.sun_size)
	if pr.has("sun_intensity"):
		_mat.set_shader_parameter("sun_intensity", pr.sun_intensity)
	if pr.has("sun_halo_strength"):
		_mat.set_shader_parameter("sun_halo_strength", pr.sun_halo_strength)
	if pr.has("sun_halo_power"):
		_mat.set_shader_parameter("sun_halo_power", pr.sun_halo_power)
	if _sun_light != null:
		var b := Basis()
		b.z = dir_v
		var xv := Vector3.UP.cross(b.z)
		b.x = xv.normalized() if xv.length() > 1e-4 else Vector3(1, 0, 0)
		b.y = b.z.cross(b.x)
		_sun_light.transform = Transform3D(b, _sun_light.global_position)
		_sun_light.light_color = pr.scene_color
		_sun_light.light_energy = pr.scene_energy
	print("[Bench] пресет %s: dir=(%.2f,%.2f,%.2f) strength=%.2f amb_e=%.2f"
		% [preset_name, dir_v.x, dir_v.y, dir_v.z, pr.strength, pr.amb_energy])
	if _ui_open:
		_ui_refresh()


## C8: параметры градиента неба словарём (дефолты = дефолты материала).
static func gp_defaults(gp: Dictionary) -> Dictionary:
	var out := {
		"use_grad": true,
		"horizon": Vector3(0.42, 0.55, 0.75),
		"zenith": Vector3(0.20, 0.35, 0.60),
		"antisolar": Vector3(0.26, 0.30, 0.52),
		"band_mid": Vector3(0.50, 0.68, 0.88),
		"band_pink": Vector3(0.80, 0.70, 0.75),
		"band_white": Vector3(0.98, 0.96, 0.85),
		"grad_sharp": 1.0,
		"flat": Vector3(0.32, 0.47, 0.68),
	}
	for k in gp.keys():
		out[k] = gp[k]
	return out


## D3: зеркало sharp_mix() шейдера — S-кривая поверх smoothstep-окна (s=1 → побитово sstep).
static func sharp_mix(lo: float, hi: float, x: float, s: float) -> float:
	var b := smoothstep(lo, hi, x)
	if s == 1.0:
		return b
	var sc := maxf(s, 0.25)
	var u := pow(b, sc)
	var v := pow(1.0 - b, sc)
	return u / maxf(u + v, 1e-6)


## C8: зеркало sky_gradient(): вертикаль + угловые кольца вокруг солнца.
static func compute_sky_gradient(dir: Vector3, sundir: Vector3, gp: Dictionary = {}) -> Vector3:
	var q := gp_defaults(gp)
	if not q.use_grad:
		var flat: Vector3 = q.flat
		return flat
	var d := dir.normalized()
	var t := d.dot(sundir.normalized())
	var hor: Vector3 = q.horizon
	var zen: Vector3 = q.zenith
	var anti: Vector3 = q.antisolar
	var mid: Vector3 = q.band_mid
	var pink: Vector3 = q.band_pink
	var white: Vector3 = q.band_white
	var sh: float = q.grad_sharp
	var base := hor.lerp(zen, sharp_mix(0.02, 0.35, d.y, sh))
	base = base.lerp(anti, sharp_mix(-0.20, -0.80, t, sh))
	base = base.lerp(mid, sharp_mix(0.10, 0.60, t, sh))
	base = base.lerp(pink, sharp_mix(0.70, 0.92, t, sh))
	base = base.lerp(white, sharp_mix(0.92, 0.995, t, sh))
	return base


## C2: параметры видимого солнца одним словарём (дефолты = дефолты материала).
static func sup_defaults(su: Dictionary) -> Dictionary:
	var out := {
		"visible": true,
		"size": 0.02,
		"softness": 0.25,
		"intensity": 16.0,
		"halo_strength": 0.25,
		"halo_power": 250.0,
		"use_blur": true,
		"blur_strength": 1.1,
		"blur_power": 12.0,
		"disk_color": Vector3(1.0, 0.98, 0.95),
		"light_dir": Vector3(-0.75, 0.50, -0.43),
		"light_color": Vector3(1.0, 0.97, 0.92),
	}
	for k in su.keys():
		out[k] = su[k]
	return out


## C2: зеркало sun_background(): диск с мягкой кромкой + степенное гало.
static func compute_sun_bg(dir: Vector3, su: Dictionary = {}) -> Vector3:
	var q := sup_defaults(su)
	if not q.visible:
		return Vector3.ZERO
	var ldir: Vector3 = q.light_dir
	ldir = ldir / maxf(ldir.length(), 1e-5)
	var cosang := dir.normalized().dot(ldir)
	var angle := acos(clampf(cosang, -1.0, 1.0))
	var sz: float = maxf(float(q.size), 1e-4)
	var rim: float = sz * maxf(float(q.softness), 0.01)
	var disk: float = 1.0 - smoothstep(sz - rim, sz + rim, angle)
	var halo: float = float(q.halo_strength) * pow(maxf(cosang, 0.0), float(q.halo_power))
	var disk_col: Vector3 = q.disk_color
	var halo_col: Vector3 = q.light_color
	return disk_col * (float(q.intensity) * disk) + halo_col * halo


## C2: финальный композит с солнцем: (sky+sun)·T + cloudC — для проверок окклюзии.
static func compute_final_with_sun(dir: Vector3, bottom: float, top: float, steps := 64,
		max_len := 30000.0, extinction := 0.0025, early_exit := 0.01, cdm := 0.0,
		dp: Dictionary = {}, lp: Dictionary = {}, sp: Dictionary = {},
		ap: Dictionary = {}, su: Dictionary = {}) -> Dictionary:
	var ap2 := ap_defaults(ap)
	ap2.use_atmo = false	# идентичность композита проверяем без дымки
	var m: Dictionary = compute_march_diag(dir, bottom, top, steps, max_len, extinction,
		early_exit, cdm, dp, lp, sp, ap2)
	var tr: float = float(m.transmittance)
	var sunbg := compute_sun_bg(dir, su)
	var sky_c: Vector3 = ap2.sky_color
	var scattered: Vector3 = (m.mode0_color as Vector3) - sky_c * tr
	var final_c: Vector3 = (sky_c + sunbg) * tr + scattered
	# D2: размытое пятно света пропорционально закрытости (1−T)
	var blur := Vector3.ZERO
	if su.get("use_blur", true) and su.get("visible", true):
		var ldirb: Vector3 = (su.get("light_dir", Vector3(-0.75, 0.5, -0.43)) as Vector3).normalized()
		var cb := dir.normalized().dot(ldirb)
		blur = (su.get("disk_color", Vector3(1.0, 0.98, 0.95)) as Vector3) \
				* (float(su.get("blur_strength", 0.9)) * pow(maxf(cb, 0.0), float(su.get("blur_power", 40.0)))) \
				* (1.0 - tr)
	final_c += blur
	return {"final": final_c, "sun_bg": sunbg, "transmittance": tr,
		"scattered": scattered, "blur": blur, "march": m}


# === C3: ВНУТРИСЕССИОННОЕ МЕНЮ НАСТРОЕК (клавиша 9) ===
# Панель: справа, полупрозрачная, ~36% ширины окна (300-430 px), со скроллом;
# область осмотра слева остаётся открытой. Строки — данные таблицы ниже:
# k: f=ползунок, b=переключатель, c=цвет, az/el=направление солнца, ox/oy/oz=смещение поля,
# mode=режим просмотра, profiles/presets=кнопки готовых наборов.

const UI_WIDTH_RATIO := 0.36
const UI_WIDTH_MIN := 300
const UI_WIDTH_MAX := 430

const TUNE_MODE_LABELS := [
	"0 Итоговый вид", "1 Плотность (серое)", "2 Прозрачность", "3 Поле теней",
	"4 Знак блика", "5 Съём кромки к свету", "6 Внутреннее переотражение", "7 Заливка небом",
	"8 Дымка (фактор)", "9 Маска попаданий", "10 Дальность входа", "11 Длина пути",
	"12 Чистое небо"]

const TUNE_SECTIONS := [
	{"title": "Вид и готовые наборы", "rows": [
		{"k": "mode", "u": "cloud_debug_mode", "n": "Режим просмотра",
		 "h": "Что показывать: итоговую картинку или внутренности (плотность, тени, вклады эффектов)"},
		{"k": "profiles", "n": "Профиль качества",
		 "h": "Готовые наборы скорости и качества: Performance самый быстрый, Reference самый точный"},
		{"k": "presets", "n": "Состояние неба",
		 "h": "Готовое освещение: нейтральное, закат, сумерки, ночь, кровавый закат"},
	]},
	{"title": "Облака: размер и количество", "rows": [
		{"k": "f", "u": "cloud_base_scale", "n": "Размер куч", "a": 8000.0, "b": 40000.0, "s": 500.0,
		 "h": "Размер облачных клубней в метрах: больше — облака крупнее и массивнее"},
		{"k": "f", "u": "cloud_coverage", "n": "Количество облаков", "a": 0.10, "b": 0.80, "s": 0.01,
		 "h": "Сколько неба занято: выше — плотнее затянуто, ниже — реже и с просветами"},
		{"k": "f", "u": "cloud_softness", "n": "Размытость краёв", "a": 0.01, "b": 0.40, "s": 0.01,
		 "h": "Выше — границы облаков мягче, ниже — резче"},
		{"k": "f", "u": "cloud_detail_scale", "n": "Размер бугорков", "a": 300.0, "b": 4000.0, "s": 50.0,
		 "h": "Размер мелких бугров на облаках в метрах: ниже — мельче бахрома"},
		{"k": "f", "u": "cloud_detail_strength", "n": "Сила бугорков", "a": 0.0, "b": 0.60, "s": 0.01,
		 "h": "Выше — кромка облака бугристее и живее"},
		{"k": "f", "u": "cloud_erosion", "n": "Рваность краёв", "a": 0.0, "b": 1.0, "s": 0.01,
		 "h": "Насколько мелкий шум съедает края: выше — края кружевнее"},
		{"k": "f", "u": "cloud_edge_contrast", "n": "Твёрдость кромки", "a": 0.5, "b": 3.0, "s": 0.05,
		 "h": "Выше — граница облака резче и твёрже, силуэт читается чётче; 1.0 — как раньше"},
		{"k": "f", "u": "cloud_vertical_stretch", "n": "Вертикальное вытяжение", "a": 0.5, "b": 4.0, "s": 0.05,
		 "h": "Выше — облака тянутся столбами, ниже — распластываются слоями"},
		{"k": "ox", "u": "cloud_offset", "n": "Сдвиг поля X", "a": -20000.0, "b": 20000.0, "s": 100.0,
		 "h": "Двигает все облака влево-вправо: выбрать красивый рисунок"},
		{"k": "oy", "u": "cloud_offset", "n": "Сдвиг поля Y", "a": -4000.0, "b": 4000.0, "s": 50.0,
		 "h": "Двигает облака по высоте внутри слоя"},
		{"k": "oz", "u": "cloud_offset", "n": "Сдвиг поля Z", "a": -20000.0, "b": 20000.0, "s": 100.0,
		 "h": "Двигает все облака вперёд-назад: выбрать красивый рисунок"},
		{"k": "f", "u": "cloud_layer_bottom", "n": "Низ слоя", "a": 500.0, "b": 3000.0, "s": 50.0,
		 "h": "Высота нижней границы облаков в метрах над камерой"},
		{"k": "f", "u": "cloud_layer_top", "n": "Верх слоя", "a": 2000.0, "b": 6000.0, "s": 50.0,
		 "h": "Высота верхней границы: выше — облака могут быть башнями выше"},
		{"k": "f", "u": "height_base_fade", "n": "Плоское основание", "a": 0.02, "b": 0.50, "s": 0.01,
		 "h": "Толщина разреженной зоны снизу: делает облакам плоское брюхо"},
		{"k": "f", "u": "height_top_fade", "n": "Купол верха", "a": 0.05, "b": 0.80, "s": 0.01,
		 "h": "Толщина разреженной зоны сверху: делает округлую шапку"},
		{"k": "f", "u": "detail_fade_start", "n": "Начало укрытия детали", "a": 1000.0, "b": 10000.0, "s": 250.0,
		 "h": "С какой дистанции прятать мелкую деталь, чтобы даль не мерцала"},
		{"k": "f", "u": "detail_fade_end", "n": "Конец укрытия детали", "a": 4000.0, "b": 30000.0, "s": 500.0,
		 "h": "Дистанция, с которой мелкая деталь скрыта полностью"},
	]},
	{"title": "Форма масс: ориентация и изгиб", "rows": [
		{"k": "b", "u": "use_height_anisotropy", "n": "Разная форма по высоте",
		 "h": "Внизу башни, вверху плоские шляпы: облака перестают быть столбами"},
		{"k": "f", "u": "aniso_base", "n": "Вытяжение внизу", "a": 0.5, "b": 4.5, "s": 0.05,
		 "h": "Насколько массы у основания тянутся вверх (башни)"},
		{"k": "f", "u": "aniso_top", "n": "Вытяжение вверху", "a": 0.2, "b": 2.0, "s": 0.05,
		 "h": "Меньше 1 — верхушки расплющивает в шляпы"},
		{"k": "f", "u": "cloud_horizontal_stretch", "n": "Горизонтальное удлинение", "a": 0.5, "b": 3.0, "s": 0.05,
		 "h": "Больше 1 — массы растягиваются в линзы и пласты"},
		{"k": "f", "u": "cloud_warp_strength", "n": "Изгиб столбов", "a": 0.0, "b": 600.0, "s": 10.0,
		 "h": "Сбивает прямые вертикальные столбы лёгким изгибом по высоте"},
		{"k": "f", "u": "cloud_warp_scale", "n": "Масштаб изгиба", "a": 3000.0, "b": 20000.0, "s": 500.0,
		 "h": "Размер волны изгиба в метрах: меньше — изгиб чаще"},
	]},
	{"title": "Небо: градиент по палитре", "rows": [
		{"k": "b", "u": "use_gradient_sky", "n": "Градиентное небо",
		 "h": "Небо переливается по высоте и вокруг солнца вместо одного цвета"},
		{"k": "c", "u": "sky_horizon_color", "n": "Цвет у горизонта",
		 "h": "Цвет неба у самой линии горизонта"},
		{"k": "c", "u": "sky_zenith_color", "n": "Цвет зенита",
		 "h": "Цвет неба прямо над головой"},
		{"k": "c", "u": "sky_antisolar_color", "n": "Цвет напротив солнца",
		 "h": "Тёмный холодный край небосвода напротив солнца"},
		{"k": "c", "u": "sky_band_mid", "n": "Среднее кольцо",
		 "h": "Цвет неба между розовым и тёмным краем (днём — светло-голубой)"},
		{"k": "c", "u": "sky_band_white", "n": "Бело-жёлтое у солнца",
		 "h": "Сияние неба вплотную к солнцу: бело-жёлтое пятно вокруг диска"},
		{"k": "c", "u": "sky_band_pink", "n": "Розовое у солнца",
		 "h": "Розовое сияние неба вплотную к солнцу"},
		{"k": "f", "u": "sky_grad_sharp", "n": "Резкость градиента", "a": 0.5, "b": 4.0, "s": 0.05,
		 "h": "Выше — переходы между цветами неба короче и чётче, зоны различимее; 1.0 — как раньше"},
	]},
	{"title": "Горизонт: чистый край", "rows": [
		{"k": "b", "u": "use_far_curtain", "n": "Растворять даль",
		 "h": "Дальние облака и их тени тают до нуля: горизонт чистый, без вала"},
		{"k": "f", "u": "far_curtain_start", "n": "Начало растворения", "a": 4000.0, "b": 20000.0, "s": 500.0,
		 "h": "С какой дистанции дальние облака начинают таять"},
		{"k": "f", "u": "far_curtain_end", "n": "Конец растворения", "a": 8000.0, "b": 40000.0, "s": 500.0,
		 "h": "За этой дистанцией облаков нет совсем"},
	]},
	{"title": "Погода: крупные просветы", "rows": [
		{"k": "b", "u": "use_weather_mask", "n": "Зоны без облаков",
		 "h": "Убирает облака целыми крупными зонами: небо становится островным"},
		{"k": "f", "u": "weather_scale", "n": "Размер пятен просветов", "a": 30000.0, "b": 120000.0, "s": 1000.0,
		 "h": "Размер окон чистого неба в метрах: больше — шире просветы"},
		{"k": "f", "u": "weather_cut", "n": "Порог чистого неба", "a": 0.10, "b": 0.60, "s": 0.01,
		 "h": "Какую часть погодного поля считать чистым небом: выше — больше просветов"},
		{"k": "f", "u": "weather_soft", "n": "Мягкость границы зон", "a": 0.02, "b": 0.40, "s": 0.01,
		 "h": "Выше — плавнее переход к зонам без облаков"},
		{"k": "f", "u": "weather_strength", "n": "Сила очистки зон", "a": 0.0, "b": 1.0, "s": 0.01,
		 "h": "Насколько чисто небо в зонах просветов: 1 — совсем без облаков"},
	]},
	{"title": "Качество и ход луча", "rows": [
		{"k": "f", "u": "march_steps", "n": "Шагов луча", "a": 16.0, "b": 128.0, "s": 4.0,
		 "h": "Сколько шагов делает луч сквозь облако: выше — точнее, но тяжелее"},
		{"k": "f", "u": "max_ray_length", "n": "Предел длины луча", "a": 5000.0, "b": 30000.0, "s": 500.0,
		 "h": "Ограничение пути луча в облаке: ниже — горизонт чище"},
		{"k": "f", "u": "extinction_scale", "n": "Плотность облаков", "a": 0.0005, "b": 0.006, "s": 0.0001,
		 "h": "Плотность и непрозрачность: выше — облака гуще и темнее внутри"},
		{"k": "f", "u": "early_exit_transmittance", "n": "Ранний останов", "a": 0.001, "b": 0.1, "s": 0.001,
		 "h": "Порог прозрачности для раннего останова луча в глухом облаке (экономия времени)"},
		{"k": "f", "u": "light_steps", "n": "Шагов тени", "a": 1.0, "b": 8.0, "s": 1.0,
		 "h": "Шаги теневого луча к солнцу: выше — тени мягче и точнее"},
		{"k": "f", "u": "shadow_ray_length", "n": "Длина тени", "a": 1000.0, "b": 9000.0, "s": 250.0,
		 "h": "Длина теневого луча в метрах: выше — тени глубже"},
	]},
	{"title": "Тени и эффекты", "rows": [
		{"k": "b", "u": "use_self_shadow", "n": "Внутренние тени",
		 "h": "Тени внутри облаков от солнца: дают ощущение объёма"},
		{"k": "b", "u": "use_powder", "n": "Контровое затемнение",
		 "h": "Приглушает тонкие края против света: контрастнее в контровом свете"},
		{"k": "f", "u": "powder_strength", "n": "Сила контрового", "a": 0.0, "b": 1.0, "s": 0.01,
		 "h": "Насколько сильно приглушать тонкие края против света"},
		{"k": "b", "u": "use_ms", "n": "Внутреннее переотражение",
		 "h": "Свет гуляет внутри облака: тени светятся изнутри, не проваливаясь в чёрное"},
		{"k": "f", "u": "ms_strength", "n": "Сила переотражения", "a": 0.0, "b": 1.0, "s": 0.01,
		 "h": "Насколько сильно свет гуляет внутри облака"},
		{"k": "f", "u": "ms_sun_gain", "n": "Солнечная доля переотражения", "a": 0.0, "b": 1.0, "s": 0.01,
		 "h": "Сколько солнечного света проникает в тени как свечение"},
		{"k": "f", "u": "ms_amb_gain", "n": "Небесная доля переотражения", "a": 0.0, "b": 1.0, "s": 0.01,
		 "h": "Сколько небесного света гуляет внутри облака"},
		{"k": "b", "u": "use_ms_order2", "n": "Второй порядок переотражения",
		 "h": "Добавляет ещё света в глубину теней (мягкое свечение ядра)"},
		{"k": "b", "u": "use_atmo_perspective", "n": "Дымка вдаль",
		 "h": "Дальние облака растворяются в цвете дымки: глубина и чистый горизонт"},
		{"k": "c", "u": "atmo_color", "n": "Цвет дымки",
		 "h": "Цвет, в который растворяются дальние облака"},
		{"k": "f", "u": "atmo_start", "n": "Начало дымки", "a": 0.0, "b": 15000.0, "s": 250.0,
		 "h": "С какой дистанции начинает действовать дымка"},
		{"k": "f", "u": "atmo_end", "n": "Полная дымка", "a": 2000.0, "b": 40000.0, "s": 500.0,
		 "h": "Дистанция, на которой облака растворились в дымке полностью"},
	]},
	{"title": "Солнце", "rows": [
		{"k": "az", "u": "cloud_light_direction", "n": "Солнце: азимут", "a": -180.0, "b": 180.0, "s": 1.0,
		 "h": "Направление по компасу: 0 — прямо по взгляду, 90 — слева, 180 — за спиной"},
		{"k": "el", "u": "cloud_light_direction", "n": "Солнце: высота", "a": -5.0, "b": 90.0, "s": 0.5,
		 "h": "Угол над горизонтом: ниже — закатнее и тени длиннее"},
		{"k": "c", "u": "cloud_light_color", "n": "Цвет света солнца",
		 "h": "Цвет, которым солнце красит облака"},
		{"k": "f", "u": "cloud_light_strength", "n": "Сила света солнца", "a": 0.0, "b": 3.0, "s": 0.01,
		 "h": "Яркость солнечного света на облаках"},
		{"k": "b", "u": "sun_visible", "n": "Диск солнца",
		 "h": "Показывать ли сам диск солнца на небе"},
		{"k": "f", "u": "sun_size", "n": "Размер диска", "a": 0.005, "b": 0.12, "s": 0.001,
		 "h": "Видимый размер диска солнца"},
		{"k": "f", "u": "sun_softness", "n": "Мягкость края диска", "a": 0.05, "b": 0.8, "s": 0.01,
		 "h": "Выше — край диска размытее"},
		{"k": "b", "u": "use_sun_color_ramp", "n": "Кромки по удалению от солнца",
		 "h": "Красит кромки облаков: у солнца светлее, дальше — розовее и краснее"},
		{"k": "c", "u": "ramp_near_color", "n": "Цвет кромки средне",
		 "h": "Розовый оттенок кромок на среднем удалении от солнца"},
		{"k": "c", "u": "ramp_far_color", "n": "Цвет кромки вдали",
		 "h": "Красный оттенок кромок далеко от солнца"},
		{"k": "c", "u": "sun_disk_color", "n": "Цвет ядра диска",
		 "h": "Цвет самого солнца: белый даёт горячее ядро даже при красном свете заката"},
		{"k": "f", "u": "sun_intensity", "n": "Яркость диска", "a": 1.0, "b": 60.0, "s": 0.5,
		 "h": "Выше — ядро диска горячее и белее"},
		{"k": "f", "u": "sun_halo_strength", "n": "Яркость ореола", "a": 0.0, "b": 1.5, "s": 0.01,
		 "h": "Световое пятно вокруг солнца: яркость"},
		{"k": "f", "u": "sun_halo_power", "n": "Ширина ореола", "a": 10.0, "b": 600.0, "s": 5.0,
		 "h": "Меньше — ореол шире и размашистее"},
		{"k": "b", "u": "use_sun_blur", "n": "Размытое солнце за облаком",
		 "h": "Когда облако закрывает солнце — вместо круга большое мягкое пятно света"},
		{"k": "f", "u": "sun_blur_strength", "n": "Яркость размытого пятна", "a": 0.0, "b": 3.0, "s": 0.05,
		 "h": "Насколько ярко свечение закрытого облаком солнца"},
		{"k": "f", "u": "sun_blur_power", "n": "Размер размытого пятна", "a": 5.0, "b": 200.0, "s": 5.0,
		 "h": "Меньше — пятно шире и размазаннее"},
		{"k": "f", "u": "hg_diffuse_mix", "n": "Рассеянный ответ фазы", "a": 0.0, "b": 1.0, "s": 0.01,
		 "h": "Сколько света солнца рассеивается во все стороны: выше — освещённые грани белее с любых углов"},
		{"k": "b", "u": "use_hg_phase", "n": "Блеск в сторону солнца",
		 "h": "Облака ярче блестят при взгляде к солнцу (серебристая кромка)"},
		{"k": "f", "u": "hg_g", "n": "Сила блеска", "a": -0.9, "b": 0.9, "s": 0.01,
		 "h": "Выше — блеск к солнцу резче и сильнее"},
		{"k": "b", "u": "use_hg_dual", "n": "Вторая доля блеска",
		 "h": "Добавляет мягкий широкий блеск поверх резкого"},
		{"k": "f", "u": "hg_g2", "n": "Ширина второй доли", "a": -0.9, "b": 0.9, "s": 0.01,
		 "h": "Насколько широк мягкий блеск"},
		{"k": "f", "u": "hg_dual_mix", "n": "Доля второй доли", "a": 0.0, "b": 1.0, "s": 0.01,
		 "h": "Сколько мягкого блеска подмешать к резкому"},
	]},
	{"title": "Небо и заливка теней", "rows": [
		{"k": "c", "u": "sky_color", "n": "Цвет чистого неба",
		 "h": "Цвет неба в просветах между облаками"},
		{"k": "b", "u": "use_ambient_gradient", "n": "Заливка верх-низ",
		 "h": "Заливка теней зависит от высоты: сверху свет неба, снизу от земли"},
		{"k": "c", "u": "cloud_ambient_sky_color", "n": "Заливка небом",
		 "h": "Цвет света неба, падающего на облака сверху"},
		{"k": "c", "u": "cloud_ambient_ground_color", "n": "Заливка землёй",
		 "h": "Цвет света от земли, падающего на облака снизу"},
		{"k": "f", "u": "cloud_ambient_energy", "n": "Сила заливки", "a": 0.0, "b": 1.5, "s": 0.01,
		 "h": "Выше — тени мягче и светлее, ниже — глубже и контрастнее"},
		{"k": "b", "u": "use_ambient_from_sky", "n": "Заливка из цвета неба",
		 "h": "Верхняя заливка берётся из зенита градиента: темнее небо — темнее тени"},
		{"k": "f", "u": "ambient_sky_gain", "n": "Сила заливки от неба", "a": 0.2, "b": 3.0, "s": 0.05,
		 "h": "Множитель яркости зенита для заливки теней"},
	]},
]

var _ui_layer: CanvasLayer = null
var _ui_panel: PanelContainer = null
var _ui_hint: Label = null
var _ui_open := false
var _ui_syncing := false
var _ui_rows := []	# состояния строк: {k,u,ctl,val,step}


func ui_toggle() -> void:
	if _ui_panel == null:
		return
	_ui_open = not _ui_open
	_ui_panel.visible = _ui_open
	if _ui_open:
		_ui_refresh()
	print("[Bench] меню настроек: %s (клавиша 9)" % ("открыто" if _ui_open else "закрыто"))


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 32
	add_child(_ui_layer)
	var vp_w := int(get_viewport().get_visible_rect().size.x)
	var w := clampi(int(float(vp_w) * UI_WIDTH_RATIO), UI_WIDTH_MIN, UI_WIDTH_MAX)
	_ui_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.10, 0.80)
	style.set_content_margin_all(8)
	style.set_corner_radius_all(8)
	_ui_panel.add_theme_stylebox_override("panel", style)
	_ui_panel.anchor_left = 1.0
	_ui_panel.anchor_right = 1.0
	_ui_panel.anchor_top = 0.0
	_ui_panel.anchor_bottom = 1.0
	_ui_panel.offset_left = -float(w) - 10.0
	_ui_panel.offset_right = -10.0
	_ui_panel.offset_top = 10.0
	_ui_panel.offset_bottom = -10.0
	_ui_layer.add_child(_ui_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	_ui_panel.add_child(outer)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "НАСТРОЙКИ НЕБА  (9 — скрыть)"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	var hide_btn := Button.new()
	hide_btn.text = "Скрыть"
	hide_btn.pressed.connect(ui_toggle)
	head.add_child(title)
	head.add_spacer(true)
	head.add_child(hide_btn)
	outer.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	for sec in TUNE_SECTIONS:
		var st := Label.new()
		st.text = "— %s —" % sec.title
		st.add_theme_font_size_override("font_size", 13)
		st.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
		box.add_child(st)
		for r in sec.rows:
			_ui_add_row(box, r)
	_ui_hint = Label.new()
	_ui_hint.text = "9 — меню настроек | F1-F3 — эффекты | F4/F5 — режимы | F6-F9 — профили | F10-F14 — состояния | H — цифры луча"
	_ui_hint.add_theme_font_size_override("font_size", 11)
	_ui_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_ui_hint.anchor_top = 1.0
	_ui_hint.anchor_bottom = 1.0
	_ui_hint.offset_top = -22.0
	_ui_hint.offset_left = 8.0
	_ui_layer.add_child(_ui_hint)
	_ui_panel.visible = false
	_ui_refresh()


func _ui_add_row(box: VBoxContainer, r: Dictionary) -> void:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 1)
	box.add_child(wrap)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	wrap.add_child(line)
	var lab := Label.new()
	lab.text = str(r.get("n", ""))
	lab.custom_minimum_size = Vector2(128, 0)
	lab.add_theme_font_size_override("font_size", 12)
	line.add_child(lab)
	var hint := Label.new()
	hint.text = str(r.get("h", ""))
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wrap.add_child(hint)
	var state := {"k": r.k, "u": str(r.get("u", "")), "ctl": null, "val": null,
		"step": float(r.get("s", 1.0))}
	match r.k:
		"f", "ox", "oy", "oz", "az", "el":
			var sl := HSlider.new()
			sl.min_value = float(r.get("a", 0.0))
			sl.max_value = float(r.get("b", 1.0))
			sl.step = float(r.get("s", 0.01))
			sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var val := Label.new()
			val.custom_minimum_size = Vector2(52, 0)
			val.add_theme_font_size_override("font_size", 11)
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			line.add_child(sl)
			line.add_child(val)
			state.ctl = sl
			state.val = val
			sl.value_changed.connect(_ui_on_slider.bind(state))
		"b":
			var cb := CheckBox.new()
			cb.text = "вкл"
			line.add_child(cb)
			state.ctl = cb
			cb.toggled.connect(_ui_on_bool.bind(state))
		"c":
			var cp := ColorPickerButton.new()
			cp.custom_minimum_size = Vector2(70, 22)
			cp.edit_alpha = false
			line.add_child(cp)
			state.ctl = cp
			cp.color_changed.connect(_ui_on_color.bind(state))
		"mode":
			var ob := OptionButton.new()
			for ml in TUNE_MODE_LABELS:
				ob.add_item(ml)
			line.add_child(ob)
			state.ctl = ob
			ob.item_selected.connect(_ui_on_mode)
		"profiles":
			var pnames := ["Performance", "Balanced", "Quality", "Reference"]
			for i in pnames.size():
				var bt := Button.new()
				bt.text = pnames[i]
				bt.add_theme_font_size_override("font_size", 11)
				bt.pressed.connect(_ui_on_profile.bind(i))
				line.add_child(bt)
		"presets":
			var pnames := ["Нейтраль", "Закат", "Сумерки", "Ночь", "Кровавый"]
			var pkeys := ["neutral", "sunset", "twilight", "night", "blood_sunset"]
			for i in pnames.size():
				var bt := Button.new()
				bt.text = pnames[i]
				bt.add_theme_font_size_override("font_size", 11)
				bt.pressed.connect(_ui_on_preset.bind(pkeys[i]))
				line.add_child(bt)
	_ui_rows.append(state)


func _ui_on_slider(v: float, state: Dictionary) -> void:
	if _ui_syncing:
		return
	_ui_write(state, v)
	_ui_show_value(state, v)


func _ui_write(state: Dictionary, v: float) -> void:
	match state.k:
		"f":
			_mat.set_shader_parameter(state.u, v)
		"ox":
			var cur := _param_vec3(state.u, Vector3.ZERO)
			cur.x = v
			_mat.set_shader_parameter(state.u, cur)
		"oy":
			var cur := _param_vec3(state.u, Vector3.ZERO)
			cur.y = v
			_mat.set_shader_parameter(state.u, cur)
		"oz":
			var cur := _param_vec3(state.u, Vector3.ZERO)
			cur.z = v
			_mat.set_shader_parameter(state.u, cur)
		"az", "el":
			var d := _param_vec3("cloud_light_direction", Vector3(0, 0.3, -1)).normalized()
			var az := rad_to_deg(atan2(-d.x, -d.z))
			var el := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
			if state.k == "az":
				az = v
			else:
				el = v
			var azr := deg_to_rad(az)
			var elr := deg_to_rad(el)
			var nd := Vector3(-sin(azr) * cos(elr), sin(elr), -cos(azr) * cos(elr))
			_mat.set_shader_parameter("cloud_light_direction", nd)


func _ui_on_bool(on: bool, state: Dictionary) -> void:
	if _ui_syncing:
		return
	_mat.set_shader_parameter(state.u, on)


func _ui_on_color(c: Color, state: Dictionary) -> void:
	if _ui_syncing:
		return
	_mat.set_shader_parameter(state.u, c)


func _ui_on_mode(idx: int) -> void:
	if _ui_syncing:
		return
	_set_mode(float(idx))


func _ui_on_profile(idx: int) -> void:
	apply_profile(idx)


func _ui_on_preset(key: String) -> void:
	apply_preset(key)


func _ui_show_value(state: Dictionary, v: float) -> void:
	if state.val == null:
		return
	var lbl: Label = state.val
	if state.step >= 1.0:
		lbl.text = "%d" % int(roundf(v))
	elif state.step >= 0.01:
		lbl.text = "%.2f" % v
	else:
		lbl.text = "%.3f" % v


func _ui_refresh() -> void:
	if _mat == null:
		return
	_ui_syncing = true
	for state in _ui_rows:
		var ctl: Variant = state.ctl
		if ctl == null:
			continue
		match state.k:
			"f":
				var v := _param_float(state.u, 0.0)
				ctl.value = v
				_ui_show_value(state, v)
			"ox":
				var v := _param_vec3(state.u, Vector3.ZERO).x
				ctl.value = v
				_ui_show_value(state, v)
			"oy":
				var v := _param_vec3(state.u, Vector3.ZERO).y
				ctl.value = v
				_ui_show_value(state, v)
			"oz":
				var v := _param_vec3(state.u, Vector3.ZERO).z
				ctl.value = v
				_ui_show_value(state, v)
			"az", "el":
				var d := _param_vec3("cloud_light_direction", Vector3(0, 0.3, -1)).normalized()
				var az := rad_to_deg(atan2(-d.x, -d.z))
				var el := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
				var v := az if state.k == "az" else el
				ctl.value = clampf(v, ctl.min_value, ctl.max_value)
				_ui_show_value(state, ctl.value)
			"b":
				ctl.button_pressed = _param_bool(state.u, false)
			"c":
				var cv: Variant = _mat.get_shader_parameter(state.u)
				if cv is Color:
					ctl.color = cv
			"mode":
				ctl.selected = int(clampf(_param_float(state.u, 0.0), 0.0, 12.0))
	_ui_syncing = false


## === ИНТЕРАКЦИЯ ===

func _unhandled_input(event: InputEvent) -> void:
	if _mat == null or _cam == null:
		return
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		_rotate_camera(-event.relative.x * mouse_sensitivity_deg, -event.relative.y * mouse_sensitivity_deg)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_0:
				_set_mode(0.0)
			KEY_1:
				_set_mode(1.0)
			KEY_2:
				_set_mode(2.0)
			KEY_3:
				_set_mode(3.0)
			KEY_4:
				_set_mode(4.0)
			KEY_5:
				_set_mode(5.0)
			KEY_6:
				_set_mode(6.0)
			KEY_7:
				_set_mode(7.0)
			KEY_8:
				_set_mode(8.0)
			KEY_9:
				ui_toggle()
			KEY_F1:
				_toggle_sun()
			KEY_F2:
				_toggle_bool_param("use_hg_phase", "HG-фаза")
			KEY_F3:
				_toggle_bool_param("use_ambient_gradient", "ambient-градиент")
			KEY_F4:
				_cycle_cloud_debug()
			KEY_F5:
				_cycle_geom_debug()
			KEY_F6:
				apply_profile(0)
			KEY_F7:
				apply_profile(1)
			KEY_F8:
				apply_profile(2)
			KEY_F9:
				apply_profile(3)
			KEY_F10:
				apply_preset("sunset")
			KEY_F11:
				apply_preset("twilight")
			KEY_F12:
				apply_preset("night")
			KEY_F13:
				apply_preset("neutral")
			KEY_F14:
				apply_preset("blood_sunset")
			KEY_H:
				_print_center_ray()


func _rotate_camera(yaw_delta_deg: float, pitch_delta_deg: float) -> void:
	if _cam == null:
		return
	var rd := _cam.rotation_degrees
	rd.y += yaw_delta_deg
	rd.x = clampf(rd.x + pitch_delta_deg, -PITCH_LIMIT_DEG, PITCH_LIMIT_DEG)
	_cam.rotation_degrees = rd


func _set_mode(m: float) -> void:
	_mat.set_shader_parameter("cloud_debug_mode", m)
	print("[Bench] cloud_debug_mode = %d (%s)" % [int(m), _CDM_LABELS[int(m)]])
	if _ui_open:
		_ui_refresh()


## B3: F1 — солнце вкл/выкл (strength ↔ 0 с восстановлением прежнего значения).
func _toggle_sun() -> void:
	if _mat == null:
		return
	var cur := _param_float("cloud_light_strength", DEFAULT_LIGHT_STRENGTH)
	if cur > 0.0:
		_saved_light_strength = cur
		_mat.set_shader_parameter("cloud_light_strength", 0.0)
		print("[Bench] солнце ВЫКЛ (cloud_light_strength=0; прежнее %.2f запомнено)" % cur)
	else:
		var restore := _saved_light_strength if _saved_light_strength > 0.0 else DEFAULT_LIGHT_STRENGTH
		_mat.set_shader_parameter("cloud_light_strength", restore)
		print("[Bench] солнце ВКЛ (cloud_light_strength=%.2f)" % restore)


## B5: F4 — цикл diagnostic-режимов §7 промта (0-8).
func _cycle_cloud_debug() -> void:
	if _mat == null:
		return
	_cdm = fmod(_cdm + 1.0, 9.0)
	_set_mode(_cdm)


## B5: F5 — цикл геометрических режимов A3 (9-12, без марша).
func _cycle_geom_debug() -> void:
	if _mat == null:
		return
	_gdm = 9.0 + fmod(_gdm - 9.0 + 1.0, 4.0)
	_set_mode(_gdm)


## B3: F2/F3 — переключение bool-uniform'ов эффекта.
func _toggle_bool_param(param_name: String, label: String) -> void:
	if _mat == null:
		return
	var cur := _param_bool(param_name, true)
	_mat.set_shader_parameter(param_name, not cur)
	print("[Bench] %s = %s (%s)" % [label, "ВКЛ" if not cur else "ВЫКЛ", param_name])


func _print_center_ray() -> void:
	if _mat == null or _cam == null:
		return
	var dir := -_cam.global_transform.basis.z
	var bottom := _param_float("cloud_layer_bottom", 1500.0)
	var top := _param_float("cloud_layer_top", 3500.0)
	var dp := _material_dp(bottom, top)
	var r := compute_interval(dir, bottom, top)
	var pitch := rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))
	if r.hit:
		var md := compute_mean_density(dir, bottom, top, 32, dp)
		var mc := compute_march(dir, bottom, top, int(_param_float("march_steps", 64.0)),
			_param_float("max_ray_length", 30000.0), _param_float("extinction_scale", 0.0025),
			_param_float("early_exit_transmittance", 0.01), dp)
		print("[Bench] pitch=%.1f° dir.y=%.5f → HIT t=[%.1f, %.1f] mean_d=%.3f T=%.4f шагов=%d%s drift=(%.0f,%.0f,%.0f)"
			% [pitch, dir.y, r.t_near, r.t_far, md.mean_density, mc.transmittance, mc.steps_used,
				" (early-exit)" if mc.early_exited else "", _drift.x, _drift.y, _drift.z])
		# B3: разложение освещения центрального луча (terms — в середине слоя, h=0.5)
		var lp := _material_lp(bottom, top)
		var mcl := compute_march_lit(dir, bottom, top, int(_param_float("march_steps", 64.0)),
			_param_float("max_ray_length", 30000.0), _param_float("extinction_scale", 0.0025),
			_param_float("early_exit_transmittance", 0.01), dp, lp)
		var mid := dir * ((float(r.t_near) + float(r.t_far)) * 0.5)
		var terms := compute_lighting_terms(mid, dir, lp)
		var sun_v: Vector3 = terms.sun
		var amb_v: Vector3 = terms.ambient
		var sc: Vector3 = mcl.scattered
		var sc_sun: Vector3 = mcl.sun_scattered
		var sc_amb: Vector3 = mcl.ambient_scattered
		print("[Bench] L: cosθ=%.3f phase=%.3f h_mid=%.2f | точка: sun=(%.2f,%.2f,%.2f) amb=(%.2f,%.2f,%.2f)"
			% [terms.cos_theta, terms.phase, terms.height_frac, sun_v.x, sun_v.y, sun_v.z,
				amb_v.x, amb_v.y, amb_v.z])
		print("[Bench] S: всего=(%.3f,%.3f,%.3f) солнце=(%.3f,%.3f,%.3f) ambient=(%.3f,%.3f,%.3f) T_lit=%.4f"
			% [sc.x, sc.y, sc.z, sc_sun.x, sc_sun.y, sc_sun.z, sc_amb.x, sc_amb.y, sc_amb.z,
				mcl.transmittance])
		# B4: тень/powder/MS в середине луча + atmo-фактор
		var sp := _material_sp()
		var ap := _material_ap()
		var mb4 := compute_march_b4(dir, bottom, top, int(_param_float("march_steps", 64.0)),
			_param_float("max_ray_length", 30000.0), _param_float("extinction_scale", 0.0025),
			_param_float("early_exit_transmittance", 0.01), dp, lp, sp, ap)
		var dmid := compute_density(mid, dp, (float(r.t_near) + float(r.t_far)) * 0.5)
		var t4 := compute_radiance_terms_b4(mid, dir, dmid, dp, lp, sp)
		var ms_v: Vector3 = t4.ms
		print("[Bench] B4: T_light(mid)=%.3f powder=%.3f ms=(%.3f,%.3f,%.3f) T_light_mean=%.3f atmo_f=%.3f"
			% [t4.t_light, t4.powder, ms_v.x, ms_v.y, ms_v.z, mb4.t_light_mean, mb4.atmo_factor])
		# C2: видимое солнце — угловое расстояние от центра взгляда и яркость фона солнца
		var su := _material_sup()
		var sunbg: Vector3 = compute_sun_bg(dir, su)
		var ldir_h: Vector3 = (su.light_dir as Vector3).normalized()
		var ang := rad_to_deg(acos(clampf(dir.normalized().dot(ldir_h), -1.0, 1.0)))
		print("[Bench] C2: солнце в %.1f° от центра взгляда, sun_bg=(%.2f,%.2f,%.2f), sun_visible=%s"
			% [ang, sunbg.x, sunbg.y, sunbg.z, str(su.visible)])
	else:
		print("[Bench] pitch=%.1f° dir.y=%.5f → MISS (пересечения со слоем нет)" % [pitch, dir.y])


## Параметры плотности из материала (для H-печати и зеркальных расчётов в рантайме).
func _material_dp(bottom: float, top: float) -> Dictionary:
	return {
		"base_scale": _param_float("cloud_base_scale", 35500.0),
		"detail_scale": _param_float("cloud_detail_scale", 1200.0),
		"coverage": _param_float("cloud_coverage", 0.23),
		"softness": _param_float("cloud_softness", 0.17),
		"strength": _param_float("cloud_detail_strength", 0.60),
		"offset": _param_vec3("cloud_offset", Vector3.ZERO),
		"base_fade": _param_float("height_base_fade", 0.15),
		"top_fade": _param_float("height_top_fade", 0.35),
		"erosion": _param_float("cloud_erosion", 0.30),
		"stretch": _param_float("cloud_vertical_stretch", 1.75),
		"edge_contrast": _param_float("cloud_edge_contrast", 1.0),
		"fade_start": _param_float("detail_fade_start", 4000.0),
		"fade_end": _param_float("detail_fade_end", 12000.0),
		"bottom": bottom,
		"top": top,
	}


## B3: параметры освещения из материала.
func _material_lp(bottom: float, top: float) -> Dictionary:
	return {
		"light_dir": _param_vec3("cloud_light_direction", Vector3(-0.75, 0.50, -0.43)),
		"light_color": _param_vec3("cloud_light_color", Vector3(1.0, 0.97, 0.92)),
		"light_strength": _param_float("cloud_light_strength", DEFAULT_LIGHT_STRENGTH),
		"use_hg": _param_bool("use_hg_phase", true),
		"hg_g": _param_float("hg_g", 0.5),
		# D3: дочитываем из материала параметры, добавленные в C5a/C9/D2 (раньше зеркало
		# марша бало рекорд-дефолты и могло разойтись с GPU при use_ramp=on и т.п.).
		"use_dual": _param_bool("use_hg_dual", false),
		"hg_g2": _param_float("hg_g2", 0.25),
		"dual_mix": _param_float("hg_dual_mix", 0.5),
		"diffuse_mix": _param_float("hg_diffuse_mix", 0.45),
		"use_ramp": _param_bool("use_sun_color_ramp", true),
		"ramp_near": _param_vec3("ramp_near_color", Vector3(0.95, 0.30, 0.25)),
		"ramp_far": _param_vec3("ramp_far_color", Vector3(0.70, 0.08, 0.08)),
		"use_amb_sky": _param_bool("use_ambient_from_sky", true),
		"amb_gain": _param_float("ambient_sky_gain", 1.2),
		"g_use": _param_bool("use_gradient_sky", true),
		"g_hor": _param_vec3("sky_horizon_color", Vector3(0.42, 0.55, 0.75)),
		"g_zen": _param_vec3("sky_zenith_color", Vector3(0.20, 0.35, 0.60)),
		"g_anti": _param_vec3("sky_antisolar_color", Vector3(0.26, 0.30, 0.52)),
		"g_mid": _param_vec3("sky_band_mid", Vector3(0.50, 0.68, 0.88)),
		"g_pink": _param_vec3("sky_band_pink", Vector3(0.50, 0.60, 0.78)),
		"g_white": _param_vec3("sky_band_white", Vector3(0.98, 0.96, 0.85)),
		"g_sharp": _param_float("sky_grad_sharp", 1.0),
		"amb_sky": _param_vec3("cloud_ambient_sky_color", Vector3(0.55, 0.63, 0.82)),
		"amb_ground": _param_vec3("cloud_ambient_ground_color", Vector3(0.25, 0.27, 0.34)),
		"amb_energy": _param_float("cloud_ambient_energy", 0.45),
		"use_amb_grad": _param_bool("use_ambient_gradient", true),
		"albedo": _param_vec3("cloud_color", Vector3(0.95, 0.95, 0.97)),
		"bottom": bottom,
		"top": top,
	}


## B4: параметры self-shadowing/powder/MS из материала.
func _material_sp() -> Dictionary:
	return {
		"use_shadow": _param_bool("use_self_shadow", true),
		"light_steps": _param_float("light_steps", 4.0),
		"shadow_len": _param_float("shadow_ray_length", 4500.0),
		"use_powder": _param_bool("use_powder", true),
		"powder_strength": _param_float("powder_strength", 0.3),
		"use_ms": _param_bool("use_ms", true),
		"ms_strength": _param_float("ms_strength", 0.65),
		"ms_sun_gain": _param_float("ms_sun_gain", 0.45),	# D3: uniform с D2 (раньше const — расхождение зеркала)
		"ms_amb_gain": _param_float("ms_amb_gain", 0.60),
		"use_ms2": _param_bool("use_ms_order2", false),
	}


## B4: параметры atmo-перспективы и фона из материала.
func _material_ap() -> Dictionary:
	return {
		"use_atmo": _param_bool("use_atmo_perspective", true),
		"atmo_color": _param_vec3("atmo_color", Vector3(0.55, 0.65, 0.85)),
		"atmo_start": _param_float("atmo_start", 6000.0),
		"atmo_end": _param_float("atmo_end", 26000.0),
		"sky_color": _param_vec3("sky_color", Vector3(0.32, 0.47, 0.68)),
	}


## C2: параметры видимого солнца из материала.
func _material_sup() -> Dictionary:
	return {
		"visible": _param_bool("sun_visible", true),
		"size": _param_float("sun_size", 0.02),
		"softness": _param_float("sun_softness", 0.25),
		"intensity": _param_float("sun_intensity", 10.0),
		"halo_strength": _param_float("sun_halo_strength", 0.25),
		"halo_power": _param_float("sun_halo_power", 250.0),
		"light_dir": _param_vec3("cloud_light_direction", Vector3(-0.75, 0.50, -0.43)),
		"light_color": _param_vec3("cloud_light_color", Vector3(1.0, 0.97, 0.92)),
	}


func _param_float(param_name: String, fallback: float) -> float:
	var v: Variant = _mat.get_shader_parameter(param_name)
	return float(v) if v != null else fallback


func _param_bool(param_name: String, fallback: bool) -> bool:
	var v: Variant = _mat.get_shader_parameter(param_name)
	return bool(v) if v != null else fallback


func _param_vec3(param_name: String, fallback: Vector3) -> Vector3:
	var v: Variant = _mat.get_shader_parameter(param_name)
	if v == null:
		return fallback
	if v is Color:	# source_color-uniform'ы приходят Color: .x/.y/.z у Color нет (баг B3-C2)
		var c: Color = v
		return Vector3(c.r, c.g, c.b)
	return Vector3(v.x, v.y, v.z)


func _process(delta: float) -> void:
	if _cam == null:
		return
	# CPU-дрейф поля от ветра (как v31: накопление на CPU, TIME в шейдере не используется)
	if wind_speed != 0.0 and _mat != null:
		_drift += wind_direction.normalized() * wind_speed * delta
		_mat.set_shader_parameter("cloud_offset", _base_offset + _drift)
	# B3: синк направления солнца с DirectionalLight3D (basis.z = НА источник; свет светит вдоль -Z).
	# Запись с epsilon-гейтом (конвенция TimeOfDayController): одинаковое значение не пишем.
	if sync_sun_from_light and _sun_light != null and _mat != null:
		var to_sun := _sun_light.global_transform.basis.z.normalized()
		var old: Variant = _mat.get_shader_parameter("cloud_light_direction")
		if old == null or (to_sun - Vector3(old.x, old.y, old.z)).length() > 0.0005:
			_mat.set_shader_parameter("cloud_light_direction", to_sun)
	var pitch := 0.0
	var yaw := 0.0
	if Input.is_physical_key_pressed(KEY_UP):
		pitch += 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		pitch -= 1.0
	if Input.is_physical_key_pressed(KEY_LEFT):
		yaw += 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		yaw -= 1.0
	if pitch != 0.0 or yaw != 0.0:
		_rotate_camera(yaw * yaw_speed_deg * delta, pitch * pitch_speed_deg * delta)
