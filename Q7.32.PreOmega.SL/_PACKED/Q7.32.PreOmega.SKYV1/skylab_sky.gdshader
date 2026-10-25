shader_type sky;
// skylab_sky.gdshader — небо заново (план v1.0, zip v0.2, шаги 2+3 ядро).
// ПАЛИТРА: авторинг в display-space (M1), значения пре-адаптированы под итоговый
// Filmic Godot 4.7 инструментом skylab_palette_tool.gd (инверс кривой из
// servers/rendering/renderer_rd/shaders/effects/tonemap.glsl, 4.7-stable).
// После пост-процесса пиксель = палитра M1 (round-trip err 0/255).
// СЛОЙ ЧИСТЫЙ: без кучевых, вуали, звёзд — они вернутся отдельными шагами.
// Legacy-блок uniform внизу — заглушки тех же имён/типов, что пишет
// CloudsTestBench.gd в sky-материал (старые баги не лечим, небо строим заново).

uniform vec3 sk_zenith : source_color = vec3(0.015954, 0.022894, 0.060409);	// ref4 adapted
uniform vec3 sk_horizon : source_color = vec3(2.0, 0.078501, 0.036102);		// ref4 adapted
uniform vec3 sk_glow_col : source_color = vec3(2.0, 0.078501, 0.036102);		// ореол = горизонт состояния
uniform float sk_glow_int : hint_range(0.0, 1.0) = 0.30;
uniform float sk_glow_exp : hint_range(1.0, 32.0) = 6.0;
uniform float sk_wedge_int : hint_range(0.0, 1.0) = 0.15;
uniform float sk_wedge_k : hint_range(0.0, 32.0) = 4.0;
uniform float sk_grad_pow : hint_range(0.2, 8.0) = 1.6;
uniform vec3 sk_sun_dir = vec3(0.0, 0.0, -1.0);	// направление НА солнце (пишет SkyLabPanel)
uniform float sk_dither : hint_range(0.0, 1.0) = 1.0;

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = clamp(dir.y, -1.0, 1.0);
	float t = pow(clamp(h * 0.5 + 0.5, 0.0, 1.0), sk_grad_pow);
	vec3 col = mix(sk_horizon, sk_zenith, t);
	vec3 sd = normalize(sk_sun_dir);
	float s = clamp(dot(dir, sd), 0.0, 1.0);
	col = mix(col, sk_glow_col, clamp(pow(s, sk_glow_exp) * sk_glow_int, 0.0, 1.0));
	col = mix(col, sk_glow_col, clamp(pow(s, 4.0) * exp(-abs(h) * sk_wedge_k) * sk_wedge_int, 0.0, 1.0));
	if (sk_dither > 0.5) {
		float n = fract(sin(dot(dir, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		col += (n - 0.5) * (1.0 / 255.0);
	}
	COLOR = col;
}

// ==== LEGACY STUBS (не используются небом; типы = omega_volumetric_clouds.gdshader) ====
uniform vec3 sky_color : source_color = vec3(0.32, 0.47, 0.68);	// фон: лучи без пересечения
uniform float cloud_layer_bottom = 1500.0;	// низ слоя, м (от плоскости камеры)
uniform float cloud_layer_top = 3500.0;		// верх слоя, м
uniform float cloud_debug_mode = 0.0;
uniform vec3 debug_hit_color : source_color = vec3(1.0, 0.75, 0.25);	// геометрия 9-10
uniform float debug_distance_scale = 20000.0;	// нормировка дальностей режимов 10-11, м
uniform sampler3D noise_pw : repeat_enable, filter_linear;		// Perlin-Worley 128³ (base shape)
uniform sampler3D noise_worley : repeat_enable, filter_linear;	// Worley 32³ (деталь/выступы)
uniform vec3 cloud_color : source_color = vec3(0.95, 0.95, 0.97);	// альбедо/тон облака (B3: множитель освещения)
uniform float cloud_base_scale = 35500.0;		// метров на период PW-текстуры
uniform float cloud_detail_scale = 3000.0;		// метров на период Worley-текстуры
uniform float cloud_coverage = 0.23;			// порог ремапа (по распределению PW!)
uniform float cloud_softness = 0.17;			// мягкость краёв (окно ±)
uniform float cloud_detail_strength = 0.60;		// амплитуда модуляции порога деталью
uniform float cloud_fine_strength = 0.0;		// PRAV-3.1: амплитуда мелкой бахромы кромок (0 = побитово prav_2.1; материал задаёт состояние фазы 3)
uniform float cloud_fine_scale = 3000.0;		// PRAV-3.1: метров на период мелкой бахромы (та же noise_worley; меню 1500-6000)
uniform float cloud_erosion = 0.30;			// B2: эрозия краёв деталью (ядра масс сохраняются)
uniform float cloud_edge_contrast = 1.0;		// D3: контраст кромки (>1 твёрже силуэт; 1 = побитово D2)
uniform float detail_fade_start = 4000.0;		// B2: с этой дистанции деталь начинает гаситься
uniform float detail_fade_end = 12000.0;		// B2: с этой дистанции детали нет (лечение алиасинга марша)
uniform float cloud_vertical_stretch = 1.75;		// B2: во сколько раз PW тянется по Y (вертикальная связность)
uniform vec3 cloud_offset = vec3(0.0);			// мировое смещение поля, м (CPU-дрейф)
uniform bool use_sun_color_ramp = false;		// выкл → свет одним cloud_light_color (C8)
uniform vec3 ramp_near_color : source_color = vec3(0.95, 0.30, 0.25);	// розовый середняк
uniform vec3 ramp_far_color : source_color = vec3(0.70, 0.08, 0.08);	// красный вдали от солнца
uniform bool use_ambient_from_sky = false;		// выкл → ambient из cloud_ambient_sky_color (C8)
uniform float ambient_sky_gain = 1.2;			// множитель яркости зенита G(up) для ambient
uniform bool use_gradient_sky = true;			// выкл → плоский sky_color (C7)
uniform vec3 sky_horizon_color : source_color = vec3(0.42, 0.55, 0.75);
uniform vec3 sky_zenith_color : source_color = vec3(0.20, 0.35, 0.60);
uniform vec3 sky_antisolar_color : source_color = vec3(0.26, 0.30, 0.52);
uniform vec3 sky_band_mid : source_color = vec3(0.50, 0.68, 0.88);	// светло-голубое кольцо (средний радиус)
uniform vec3 sky_band_white : source_color = vec3(0.98, 0.96, 0.85);	// бело-жёлтое сияние вплотную к солнцу
uniform vec3 sky_band_pink : source_color = vec3(0.50, 0.60, 0.78);
uniform float sky_grad_sharp = 1.0;			// D3: резкость переходов палитры (>1 чётче зоны; 1 = побитово D2)
uniform bool use_far_curtain = true;		// выкл → побитово C6
uniform float far_curtain_start = 12000.0;	// дистанция, с которой облака начинают таять, м
uniform float far_curtain_end = 24000.0;	// дистанция, за которой облаков нет, м
uniform bool use_height_anisotropy = true;	// выкл → stretch = cloud_vertical_stretch (C4)
uniform float aniso_base = 3.0;				// вертикальное вытяжение у основания (башни)
uniform float aniso_top = 0.70;				// вытяжение у верха (<1 = плоские шляпы)
uniform float cloud_horizontal_stretch = 1.4;	// >1 удлиняет массы по горизонтали
uniform float cloud_warp_strength = 220.0;	// амплитуда y-warp, м (0 = выкл)
uniform float cloud_warp_scale = 9000.0;		// период шума warp, м
uniform bool use_weather_mask = true;			// выкл → побитово C3
uniform float weather_scale = 30000.0;			// метров на период маски (пятна просветов)
uniform float weather_cut = 0.14;				// порог поля маски: ниже — зона без облаков
uniform float weather_soft = 0.06;				// мягкость границы зоны
uniform float weather_strength = 0.9;			// сила вычитания покрытия в зоне (1 = чисто)
uniform vec3 cloud_light_direction = vec3(-0.75, 0.50, -0.43);	// направление НА источник (нормализуется; конвенция продакшн-неба)
uniform vec3 cloud_light_color : source_color = vec3(1.0, 0.97, 0.92);	// цвет источника (нейтральный дневной; закат/ночь — рецепты в README)
uniform float cloud_light_strength = 0.70;		// интенсивность прямого света (0 = выключен)
uniform bool use_hg_phase = true;			// Henyey-Greenstein вкл/выкл (false = изотроп phase≡1)
uniform float hg_g = 0.5;				// анизотропия HG: >0 вперёд, <0 назад; clamp ±0.9 в hg_phase()
uniform float hg_diffuse_mix = 0.45;			// D2: доля изотропного ответа в фазе (0 = чистый HG, вид D1)
uniform bool use_hg_dual = false;			// C5a: dual-lobe HG (выкл = одиночная доля, побитово B7)
uniform float hg_g2 = 0.25;				// C5a: анизотропия второй доли
uniform float hg_dual_mix = 0.5;			// C5a: вес второй доли 0..1 (0 = одиночная, 1 = только g2)
uniform vec3 cloud_ambient_sky_color : source_color = vec3(0.55, 0.63, 0.82);		// ambient верха слоя (небесный)
uniform vec3 cloud_ambient_ground_color : source_color = vec3(0.25, 0.27, 0.34);	// ambient низа слоя (земной)
uniform float cloud_ambient_energy = 0.45;		// интенсивность ambient (0 = выключен)
uniform bool use_ambient_gradient = true;		// false = постоянный ambient (sky-цвет)
uniform bool sun_visible = true;			// выкл → побитово C1
uniform float sun_size = 0.02;				// угловой радиус диска, радианы (~1.1°)
uniform float sun_softness = 0.25;			// мягкость кромки диска (доля радиуса)
uniform vec3 sun_disk_color : source_color = vec3(1.0, 0.98, 0.95);	// C6: цвет ядра диска (независим от света)
uniform float sun_intensity = 16.0;			// HDR-яркость диска (выше = ядро белее на Filmic)
uniform float sun_halo_strength = 0.25;		// амплитуда гало
uniform float sun_halo_power = 250.0;		// показатель углового спада гало (больше = уже)
uniform bool use_sun_blur = true;			// D2: размытое пятно света там, где облако закрыло диск
uniform float sun_blur_strength = 1.1;		// D2: амплитуда размытого пятна (∝ закрытости 1−T)
uniform float sun_blur_power = 12.0;		// D2: угловая ширина пятна (меньше = шире; 12 ≈ полуспад на 20°)
uniform bool use_self_shadow = true;		// выкл → T_light≡1 (вид B3)
uniform float light_steps = 4.0;			// §4.2: Performance 3 / Balanced 4 / Quality 6 (clamp 1..16)
uniform float shadow_ray_length = 4500.0;	// длина марша к источнику, м (0 → T_light≡1)
uniform bool use_powder = true;			// выкл → powder≡1
uniform float powder_strength = 0.3;		// 0..1: доля эффекта (D2: ослаблено с 0.60 — контровые ярче)
uniform bool use_ms = true;				// выкл → ms≡0
uniform float ms_strength = 0.65;			// 0..1; доли MS ниже — uniform'ы (D2)
uniform float ms_sun_gain = 0.45;			// D2: доля солнечного диффузного проникновения (была 0.30 const)
uniform float ms_amb_gain = 0.60;			// D2: доля ambient-члена MS (была 0.60 const)
uniform bool use_ms_order2 = false;			// C5b: MS 2-го порядка (выкл = побитово B7)
uniform bool use_atmo_perspective = true;	// выкл → композит как в B3
uniform vec3 atmo_color : source_color = vec3(0.55, 0.65, 0.85);
uniform float atmo_start = 6000.0;			// t_near, с которого начинает действовать дымка, м
uniform float atmo_end = 26000.0;			// t_near, с которого облако полностью в дымке, м
uniform float height_base_fade = 0.15;			// доля слоя снизу: нарастание (плоское основание)
uniform float height_top_fade = 0.35;			// доля слоя сверху: купольный спад
uniform float march_steps = 48.0;				// шаги марша режима 5 (clamp 8..256)
uniform float max_ray_length = 30000.0;			// предел длины интегрирования, м
uniform float extinction_scale = 0.0025;		// σ на единицу плотности, 1/м
uniform float early_exit_transmittance = 0.01;	// порог раннего завершения
uniform bool hc_enabled = false;			// мастер-гейт слоя (false → побитово D3)
uniform bool hc_use_world_anchor = true;	// true → плита в мировых высотах (POSITION), false → от плоскости камеры
uniform float hc_layer_bottom = 6000.0;		// низ плиты вуали, м
uniform float hc_layer_top = 7200.0;		// верх плиты вуали, м
uniform float hc_scale = 60000.0;			// метров на период PW: размер крупных образований (~5.6 км фичи)
uniform float hc_stretch = 3.5;				// вытянутость гряд (>1 длиннее вдоль оси, <1 — поперёк)
uniform float hc_stretch_angle_deg = 25.0;	// азимут оси вытянутости в плоскости XZ, °
uniform float hc_field_scale = 260000.0;	// период поля разрывов (крупнее hc_scale; пятна ~19 км)
uniform float hc_field_amp = 0.60;			// амплитуда модуляции порога полем разрывов (0 = равномерный слой)
uniform float hc_coverage = 0.56;			// порог формирования облачных областей
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
uniform float hc_debug = 0.0;				// 0 выкл / 1 плотность / 2 альфа / 3 оптическая толщина
