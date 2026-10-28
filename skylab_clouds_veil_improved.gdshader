shader_type sky;

// === Текстуры вуали (конвейер B1: .bin → ImageTexture3D через CloudTextureLoader) ===
uniform sampler3D noise_pw : repeat_enable, filter_linear;		// Perlin-Worley 128³ (base shape)
uniform sampler3D noise_worley : repeat_enable, filter_linear;	// Worley 32³ (деталь/выступы)

// === Фон неба ===
uniform bool use_gradient_sky = true;			// выкл → плоский sky_color (C7)
uniform vec3 sky_color : source_color = vec3(0.32, 0.47, 0.68);	// плоское небо (use_gradient_sky=false); резерв ambient вуали (SKYHC-4)

// ==== SKYLAB: палитра неба M1 — ГРАДИЕНТ + ОСВЕЩЕНИЕ КУПОЛА (модель двух полюсов v0.5.1/v0.5.2) ====
uniform vec3 sk_zenith : source_color = vec3(0.015954, 0.022894, 0.060409);
uniform vec3 sk_horizon : source_color = vec3(2.0, 0.078501, 0.036102);
uniform vec3 sk_glow_col : source_color = vec3(2.0, 0.078501, 0.036102);
uniform float sk_glow_int : hint_range(0.0, 1.0) = 0.30;
uniform float sk_glow_exp : hint_range(1.0, 32.0) = 6.0;
uniform float sk_wedge_int : hint_range(0.0, 1.0) = 0.35;
uniform float sk_wedge_az : hint_range(0.5, 16.0) = 3.0;	// v0.5.1: спад добавочного света вдоль горизонта
uniform float sk_zen_lift : hint_range(1.0, 6.0) = 2.0;	// v0.5.1: зенит = СРЕДНЯЯ точка между полюсами, не тёмная
uniform float sk_wedge_k : hint_range(0.0, 32.0) = 4.0;
uniform vec3 sk_sun_dir = vec3(0.0, 0.0, -1.0);	// направление НА солнце (мировое; конвенция basis.z DirectionalLight3D)
uniform vec3 sk_anti_col : source_color = vec3(0.0202, 0.00718, 0.0152);	// v0.5.1: антисоляр = самая тёмная точка купола
uniform float sk_anti_p_lo : hint_range(0.3, 4.0) = 0.6;	// v0.5.2: низкое солнце — широкое тёмное ядро
uniform float sk_anti_p_hi : hint_range(0.3, 4.0) = 3.0;	// v0.5.2: высокое солнце — узкое ядро
uniform float sk_low_dim : hint_range(0.0, 1.0) = 0.25;	// v0.13: купол темнее при низком солнце
uniform vec3 sk_below_col : source_color = vec3(0.030, 0.011, 0.018);	// v0.9: ниже горизонта
uniform float sk_below_int : hint_range(0.0, 1.0) = 0.55;
uniform float sk_dither : hint_range(0.0, 1.0) = 1.0;

// === Освещение — прямой источник (солнце/луна). Конвенция имён продакшн-неба: ===
// cloud_light_direction/color/strength — те же, что пишет TimeOfDayController из
// SkyPhaseProfile (примечание B4; подключение к основному проекту без переименований). ===
uniform vec3 cloud_light_direction = vec3(-0.75, 0.50, -0.43);	// направление НА источник (нормализуется; конвенция продакшн-неба)
uniform vec3 cloud_light_color : source_color = vec3(1.0, 0.97, 0.92);	// цвет источника (нейтральный дневной; закат/ночь — рецепты в README)
uniform float cloud_light_strength = 0.70;		// интенсивность прямого света (0 = выключен)

// === C9: окраска освещения под градиент (общие данные источника; читает вуаль SKYHC-4) ===
uniform bool use_sun_color_ramp = false;		// выкл → свет одним cloud_light_color (C8)
uniform vec3 ramp_near_color : source_color = vec3(0.95, 0.30, 0.25);	// розовый середняк
uniform vec3 ramp_far_color : source_color = vec3(0.70, 0.08, 0.08);	// красный вдали от солнца
uniform bool use_ambient_from_sky = false;		// выкл → ambient из cloud_ambient_sky_color (C8)
uniform float ambient_sky_gain = 1.2;			// множитель яркости зенита G(up) для ambient

// === Освещение — ambient (верх слоя; земная доля была только у кучевых — удалена) ===
uniform vec3 cloud_ambient_sky_color : source_color = vec3(0.55, 0.63, 0.82);		// ambient верха слоя (небесный)
uniform float cloud_ambient_energy = 0.45;		// интенсивность ambient (0 = выключен)

// === C2: видимое солнце (диск + гало источника света) ===
uniform bool sun_visible = true;			// выкл → побитово C1
uniform float sun_size = 0.02;				// угловой радиус диска, радианы (~1.1°)
uniform float sun_softness = 0.25;			// мягкость кромки диска (доля радиуса)
uniform vec3 sun_disk_color : source_color = vec3(1.0, 0.98, 0.95);	// C6: цвет ядра диска (независим от света)
uniform float sun_intensity = 16.0;			// HDR-яркость диска (выше = ядро белее на Filmic)
uniform float sun_halo_strength = 0.25;		// амплитуда гало
uniform float sun_halo_power = 250.0;		// показатель углового спада гало (больше = уже)

// === SKYHC-1: слой протяжённой облачности (вуаль) — независимый модуль ===
// Все пороги дистанций — в метрах (конвенция far_curtain_*/atmo_*). Цвета и состояния
// суток в алгоритме НЕ зашиты: hc_color — данные (этап 4 подключит cloud_light_*/G(dir)).
uniform bool hc_enabled = false;			// мастер-гейт слоя (false → побитово D3)
uniform bool hc_use_world_anchor = true;	// true → плита в мировых высотах (POSITION), false → от плоскости камеры
uniform float hc_layer_bottom = 6000.0;		// низ плиты вуали, м
uniform float hc_layer_top = 7200.0;		// верх плиты вуали, м
uniform float hc_scale = 60000.0;			// метров на период PW: размер крупных образований (~5.6 км фичи)
uniform float hc_stretch = 3.5;				// вытянутость гряд (>1 длиннее вдоль оси, <1 — поперёк)
uniform float hc_stretch_angle_deg = 25.0;	// азимут оси вытянутости в плоскости XZ, °
uniform float hc_field_scale = 260000.0;	// период поля разрывов (крупнее hc_scale; пятна ~19 км)
uniform float hc_field_amp = 0.60;			// амплитуда модуляции порога полем разрывов (0 = равномерный слой)
uniform float hc_coverage = 0.56;			// порог формирования облачных областей  // Порог формы: рост значения обычно уменьшает покрытие.
uniform float hc_softness = 0.22;			// мягкость границ (окно ±), без резких контуров
uniform float hc_tau_per_km = 0.35;		// оптическая толщина на 1 км пути при d=1 (общая плотность слоя; 0 = слоя нет; σ = hc_tau_per_km/1000)
uniform float hc_curtain_start = 4000.0;	// длина пути в плите, с которой вуаль начинает таять, м
uniform float hc_curtain_end = 14000.0;		// длина пути, за которой вуали нет (чистый горизонт), м
uniform vec3 hc_offset = vec3(0.0);			// дрейф/сдвиг поля, м (пишется с CPU, как cloud_offset)
uniform vec3 hc_color : source_color = vec3(0.92, 0.93, 0.96);	// тон вуали (этап 1: простая модель цвета)
uniform float hc_detail_strength = 0.0;		// SKYHC-3.3: амплитуда мелкой детали на кромках (0 = побитово 3.2; материал задаёт 0.35)
uniform float hc_detail_scale = 3000.0;		// SKYHC-3.3: метров на период Worley (размер бугорков; меню 800-8000)
uniform bool hc_use_lighting = false;		// SKYHC-4: гейт модели освещения (false → цвет константой hc_color, побитово 3.3; материал задаёт true)
uniform float hc_light_gain = 1.0;			// SKYHC-4: доля прямого света вуали (независимая ручка яркости слоя)
uniform float hc_ambient_gain = 1.0;		// SKYHC-4: доля заливки небом (ambient C9)
// === SKYHC-SHADOW: необязательное самозатенение ВНУТРИ слоя вуали ===
// Это не тени на земле: sky shader не может записывать shadow map для DirectionalLight3D.
// Два дополнительных сэмпла плотности вдоль направления на источник дают мягкое
// самозатенение облачной вуали. Выключено по умолчанию: можно сравнить цену и качество.
uniform bool hc_use_shadowing = false;       // отдельный дорогой блок; false = нулевая цена
uniform float hc_shadow_strength = 0.75;     // 0 = нет теней, 1 = полная расчётная оптика
uniform float hc_shadow_max_dist = 12000.0;  // ограничение длины луча тени, м

uniform float hc_debug = 0.0;				// 0 выкл / 1 плотность / 2 альфа / 3 оптическая толщина

// Явный smoothstep (переносимость между бэкендами, A5).
float sstep(float lo, float hi, float x) {
	float t = clamp((x - lo) / (hi - lo), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// Пересечение луча со слоем [bottom, top] (A3, без изменений).
// CPU-зеркало: CloudsTestBench.compute_interval().
bool layer_interval(vec3 dir, float bottom, float top, out float t_near, out float t_far) {
	const float EPS = 1e-6;
	t_near = 0.0;
	t_far = 0.0;
	if (abs(dir.y) <= EPS) {
		return false;				// защита 1: почти параллельный луч
	}
	float t1 = bottom / dir.y;
	float t2 = top / dir.y;
	t_near = max(min(t1, t2), 0.0);	// защиты 4-5: камера в слое / перепутаны границы
	t_far = max(t1, t2);
	return t_far > t_near;			// защиты 2-3: взгляд вниз / вырожденный интервал
}


vec3 sky_gradient(vec3 dir) {
	// v0.5.1: МОДЕЛЬ ДВУХ ПОЛЮСОВ + ГОРИЗОНТ (по ТЗ заказчика):
	//   полюс 1 = направление источника → светлый; полюс 2 = противоположный → тёмный;
	//   зенит = средняя точка между полюсами (НЕ тёмная); вдоль горизонта добавочный
	//   свет расходится, спадая с угловым удалением от основного источника.
	//   Привязка только к мировому направлению солнца.
	vec3 sd = normalize(sk_sun_dir);
	float h = clamp(dir.y, -1.0, 1.0);
	float az3 = dot(dir, sd);
	float tp = clamp(0.5 + 0.5 * az3, 0.0, 1.0);	// 0 = антисоляр, 1 = солнце
	vec3 zen_mid = sk_zenith * sk_zen_lift;			// средняя точка полюсов
	// v0.5.2 ФИКСИРОВАННЫЙ ЗАКОН: доля светлого купола растёт с высотой солнца.
	// Низкое солнце → широкое и тёмное антисолярное ядро (светлого купола мало);
	// высокое → узкое ядро и осветлённый антисоляр (светлого купола много).
	float sh = smoothstep(-0.03, 0.85, sd.y);
	float p_ant = mix(sk_anti_p_lo, sk_anti_p_hi, sh);
	vec3 anti_c = mix(sk_anti_col, zen_mid, 0.45 * sh);
	float hmask = 1.0 - smoothstep(0.0, 0.45, abs(h));	// полюса расходятся по горизонту
	vec3 pole = (tp < 0.5)
			? mix(anti_c, zen_mid, pow(clamp(tp / 0.5, 0.0, 1.0), p_ant))
			: mix(zen_mid, sk_horizon, smoothstep(0.5, 1.0, tp));
	vec3 base = mix(zen_mid, pole, hmask);
	// горизонт: добавочный свет, спадающий с удалением от источника вдоль горизонта
	vec2 dH = vec2(dir.x, dir.z);
	vec2 sH = vec2(sd.x, sd.z);
	float azH = dot(dH, sH) / max(length(dH) * length(sH), 1e-6);
	float band = pow(max(azH, 0.0), sk_wedge_az) * exp(-abs(h) * sk_wedge_k) * sk_wedge_int;
	base = mix(base, sk_glow_col, clamp(band, 0.0, 1.0));
	// ореол вокруг полюса света
	float sp = clamp(az3, 0.0, 1.0);
	base = mix(base, sk_glow_col, clamp(pow(sp, sk_glow_exp) * sk_glow_int, 0.0, 1.0));
	// ниже горизонта — в тень состояния
	// sstep поддерживает обратный диапазон; GLSL smoothstep с edge0 >= edge1 не определён.
	base = mix(base, sk_below_col, sstep(0.0, -0.18, h) * sk_below_int);
	// чем ниже солнце, тем менее освещён купол
	float low = 1.0 - smoothstep(0.0, 20.0, sd.y);
	base *= 1.0 - sk_low_dim * low;
	if (sk_dither > 0.5) {
		float n = fract(sin(dot(dir, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		base += (n - 0.5) * (1.0 / 255.0);
	}
	return base;
}

// C2: фон видимого солнца: диск с мягкой кромкой + степенное гало вокруг источника.
// angle = угол между dir и направлением на источник; диск = 1 внутри кромки, 0 снаружи.
// CPU-зеркало: CloudsTestBench.compute_sun_bg().
vec3 sun_background(vec3 dir) {
	vec3 ldir = cloud_light_direction / max(length(cloud_light_direction), 1e-5);
	float cosang = dot(dir, ldir);
	float angle = acos(clamp(cosang, -1.0, 1.0));
	float sz = max(sun_size, 1e-4);
	float rim = sz * max(sun_softness, 0.01);
	float disk = 1.0 - sstep(sz - rim, sz + rim, angle);
	float halo = sun_halo_strength * pow(max(cosang, 0.0), sun_halo_power);
	// C6: ядро — sun_disk_color, гало — cloud_light_color (белое солнце в цветном свете).
	return sun_disk_color * (sun_intensity * disk) + cloud_light_color * halo;
}

// === SKYHC-1: ФУНКЦИИ СЛОЯ ВУАЛИ (отдельный модуль, марш кучевых не трогается) ===


vec3 hc_sample_coord(vec3 p) {
	vec3 q = p + hc_offset;
	float a = radians(hc_stretch_angle_deg);
	float ca = cos(a);
	float sa = sin(a);
	vec2 r = vec2(q.x * ca + q.z * sa, -q.x * sa + q.z * ca);	// поворот на −a
	r.x /= max(hc_stretch, 0.05);								// сжатие вдоль оси гряд
	return vec3(r.x * ca - r.y * sa, q.y, r.x * sa + r.y * ca);	// поворот на +a
}


float hc_density(vec3 p) {
	vec3 q = hc_sample_coord(p);
	float shape = texture(noise_pw, q / max(hc_scale, 1.0)).r;
	float field = texture(noise_pw, q / max(hc_field_scale, 1.0)).r;
	float cov = clamp(hc_coverage + hc_field_amp * (field - 0.5) * 2.0, 0.0, 1.0);
	float soft = max(hc_softness, 1e-4);
	float n = shape;
	if (hc_detail_strength > 0.0) {
		vec3 q0 = p + hc_offset;
		float det = texture(noise_worley, q0 / max(hc_detail_scale, 1.0)).r;
		float w_edge = clamp(1.0 - abs(shape - cov) / soft, 0.0, 1.0);
		n = shape - hc_detail_strength * (det - 0.5) * 2.0 * soft * w_edge;
	}
	return sstep(cov - soft, cov + soft, n);
}


const float HC_SHADOW_EPS = 1e-4;

float hc_shadow_transmittance(vec3 p, vec3 ldir) {
	float max_dist = max(hc_shadow_max_dist, 0.0);
	if (max_dist <= HC_SHADOW_EPS) {
		return 1.0;
	}

	float boundary_dist = max_dist;
	if (abs(ldir.y) > HC_SHADOW_EPS) {
		float to_boundary = (ldir.y > 0.0)
				? (hc_layer_top - p.y) / ldir.y
				: (hc_layer_bottom - p.y) / ldir.y;
		boundary_dist = min(boundary_dist, max(to_boundary, 0.0));
	}
	if (boundary_dist <= HC_SHADOW_EPS) {
		return 1.0;
	}

	// Два сэмпла вдоль пути света. Чем выше средняя плотность и длиннее путь,
	// тем меньше пропускание. hc_tau_per_km использует ту же шкалу, что и основной слой.
	float d1 = hc_density(p + ldir * (boundary_dist * 0.25));
	float d2 = hc_density(p + ldir * (boundary_dist * 0.75));
	float mean_density = 0.5 * (d1 + d2);
	float tau_light = mean_density * max(hc_tau_per_km, 0.0) * (boundary_dist * 0.001);
	return exp(-tau_light * clamp(hc_shadow_strength, 0.0, 1.0));
}

// SKYHC-4: константы модели освещения (статус как у HC_MAX_DIST — не художественные
// параметры): окно мягкого терминатора и его пол. Отношение яркости далеко/близко к
// солнцу = 0.60 : 1.00 — cue «вуаль подсвечена со стороны солнца» БЕЗ объёмного
// контраста (ТЗ фазы 4 п.3); непрерывность и границы проверены сьютом (HC4-5).
const float HC_TERM_LO = -0.35;
const float HC_TERM_HI = 0.55;
const float HC_SHADE_FLOOR = 0.60;


vec3 hc_lit_color(vec3 dir, vec3 sample_pos) {
	vec3 ldir = cloud_light_direction / max(length(cloud_light_direction), 1e-5);
	float cos_theta = dot(dir, ldir);
	vec3 sun_col = cloud_light_color;
	if (use_sun_color_ramp) {
		sun_col = mix(mix(ramp_far_color, ramp_near_color, sstep(0.30, 0.80, cos_theta)),
				cloud_light_color, sstep(0.93, 0.995, cos_theta));
	}
	float shade = mix(HC_SHADE_FLOOR, 1.0, sstep(HC_TERM_LO, HC_TERM_HI, cos_theta));
	float shadow_t = 1.0;
	if (hc_use_shadowing) {
		// Самозатенение влияет только на прямой свет; ambient остаётся мягкой заливкой.
		shadow_t = hc_shadow_transmittance(sample_pos, ldir);
	}
	vec3 direct = sun_col * (cloud_light_strength * shade * shadow_t) * hc_light_gain;
	vec3 amb_top = cloud_ambient_sky_color;
	if (use_ambient_from_sky) {
		amb_top = (use_gradient_sky ? sky_gradient(vec3(0.0, 1.0, 0.0)) : sky_color) * ambient_sky_gain;
	}
	vec3 ambient = amb_top * (cloud_ambient_energy * hc_ambient_gain);
	return hc_color * (direct + ambient);
}

vec3 hc_evaluate(vec3 dir, out float alpha_o, out float dens_o, out float tau_o) {
	alpha_o = 0.0;
	dens_o = 0.0;
	tau_o = 0.0;
	if (!hc_enabled) {
		return vec3(0.0);
	}
	vec3 origin = hc_use_world_anchor ? POSITION : vec3(0.0);
	// guard толщины плиты (тот же приём, что max(top − bottom, 1e-4) в layer_height_fraction)
	float top_safe = hc_layer_bottom + max(hc_layer_top - hc_layer_bottom, 1e-4);
	float t_near = 0.0;
	float t_far = 0.0;
	if (!layer_interval(dir, hc_layer_bottom - origin.y, top_safe - origin.y, t_near, t_far)) {
		return vec3(0.0);
	}
	// Одна выборка в середине интервала; HC_MAX_DIST удерживает координаты в разумном диапазоне
	// у горизонта. Curtain гасит такие лучи, но это всё ещё приближение, не интеграл плотности.
	vec3 p = origin + dir * min(0.5 * (t_near + t_far), HC_MAX_DIST);
	float d = hc_density(p);
	float path = t_far - t_near;
	float tau = d * max(hc_tau_per_km, 0.0) * (path * 0.001);	// path в м → км
	float curtain = 1.0 - sstep(hc_curtain_start, hc_curtain_end, path);
	float a = clamp((1.0 - exp(-tau)) * curtain, 0.0, 1.0);
	dens_o = d;
	tau_o = tau;
	alpha_o = a;
	// SKYHC-4: гейт освещения — при hc_use_lighting=false цвет константой hc_color
	// (побитово SKYHC-3.3); при true — модель hc_lit_color (те же источники, что кучевые).
	return (hc_use_lighting ? hc_lit_color(dir, p) : hc_color) * a;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	// SKYHC-1: диагностика вуали (hc_debug 1-3) — честный пропуск: ни солнца, ни
	// градиента; показываем ИМЕННО член слоя (плотность/альфа/оптическая толщина).
	// return в sky() запрещён движком → структура ветвлением (как в v0.5.3).
	bool hc_diag = hc_debug > 0.5;
	// C2: солнце — только в финальном кадре (диагностики остаются чистыми).
	vec3 sunbg = vec3(0.0);
	if (!hc_diag && sun_visible) {
		sunbg = sun_background(dir);
	}
	// Фон неба: двухполюсный градиент G(dir) (v0.5.1/v0.5.2) или плоский sky_color.
	vec3 bg = use_gradient_sky ? sky_gradient(dir) : sky_color;
	// SKYHC-1: вуаль — один сэмпл плотности плиты + Beer-Lambert + curtain (без марша).
	// Subpass-веток больше нет (B6 удалён вместе с кучевыми) — вуаль считается во всех
	// проходах sky-шейдера (full-res и radiance cubemap), как в full-res/cubemap ветках v0.5.3.
	vec3 hc_rgb = vec3(0.0);
	float hc_a = 0.0;
	float hc_d = 0.0;
	float hc_tau = 0.0;
	hc_rgb = hc_evaluate(dir, hc_a, hc_d, hc_tau);
	// SKYHC-1: небо+солнце, ослабленные вуалью (премноженный композит — формула v0.5.3).
	// При выключенном слое hc_a=0 и hc_rgb=0 → base = bg + sunbg (чистый градиент с солнцем).
	vec3 base = (bg + sunbg) * (1.0 - hc_a) + hc_rgb;
	if (hc_diag) {
		COLOR = hc_debug < 1.5 ? vec3(hc_d) : (hc_debug < 2.5 ? vec3(hc_a) : vec3(clamp(hc_tau, 0.0, 1.0)));
	} else {
		COLOR = base;
	}
}
