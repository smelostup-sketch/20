shader_type sky;
// omega_volumetric_clouds.gdshader — RENGAR PROTOTYPE OMEGA, компонент Q7.32_SKY_B2.
// ФАЗА B, ЭТАП B1: 3D-текстурный конвейер плотности (Perlin-Worley 128³ + Worley 32³).
//
// ОТЛИЧИЕ ОТ A8: базовая форма и деталь читаются из 3D-текстур (sampler3D), а не из
// процедурного FBM (процедурная версия сохранена в архиве Q7.31_SKY_A8 как fallback).
// Совместимость подтверждена спайком B1 в Godot 4.7.stable: uniform sampler3D с
// repeat_enable/filter_linear компилируется и корректно семплирует в sky-шейдере
// на Vulkan И OpenGL3. ВАЖНО (найдено спайком): персистенция ImageTexture3D через
// ResourceSaver в 4.7-stable сломана (create() не заполняет CPU-сторону → .res
// сохраняет заглушку), поэтому текстуры поставляются сырыми .bin и собираются ОДИН
// раз при старте сцены через CloudTextureLoader (ImageTexture3D.create из срезов
// Array[Image]); в материал назначаются кодом стенда (set_shader_parameter).
//
// СОХРАНЕНО из фазы A (регрессия проверяется): layer_interval со всеми защитами
// (EPS/взгляд вниз/вырожденный интервал/камера в слое), марш Beer-Lambert с
// аналитическим затуханием в сегменте (энергосохранение S+T=1), max_ray_length,
// early termination, высотный профиль кучевых (A7), композитинг sky*T+scattered
// (A6, premultiplied-сборка), режимы 0-6, явный sstep (переносимость).
//
// СОЗНАТЕЛЬНО ОТСУТСТВУЕТ (этапы B2-B6): эрозия краёв (B2), солнечный свет/HG/
// ambient-градиент (B3), self-shadowing/powder/multiple scattering/atmospheric
// perspective (B4), полный набор cloud_debug_mode 0-8 (B5), профили качества и
// subpasses (B6). Освещение пока равномерное cloud_color.
//
// МАСШТАБЫ (калиброваны по распределению поля, см. README):
//   cloud_base_scale = 16000 м на период PW-текстуры → массы 1-3 км, воксел 125 м;
//   cloud_detail_scale = 1200 м на период Worley → выступы ~150 м, воксел 37.5 м.
//   Распределение PW аутентичное (среднее 0.178, p75=0.32, p90=0.48, «жилы» нулей
//   между ячейками) — поэтому cloud_coverage по умолчанию 0.30, а не 0.5.
//
// ВЕТЕР: cloud_offset (метры, мировое смещение поля) пишется с CPU (стенд/контроллер,
// как cloud_offset_* в v31) — TIME в шейдере НЕ используется (radiance cubemap не
// обновляется каждый кадр; соглашение проверено по документации 4.7 в A6).

uniform vec3 sky_color : source_color = vec3(0.32, 0.47, 0.68);	// фон: лучи без пересечения
uniform float cloud_layer_bottom = 1500.0;	// низ слоя, м (от плоскости камеры)
uniform float cloud_layer_top = 3500.0;		// верх слоя, м

// Отладочные режимы (клавиши стенда 0-6):
//   0 = маска HIT/MISS; 1 = дальность входа t_near; 2 = длина пути; 3 = чистый sky_color;
//   4 = предпросмотр (средняя плотность × gain); 5 = объёмный марш (по умолчанию);
//   6 = пропускание T (белый = прозрачно). Полный набор 0-8 по §7 промта — этап B5.
uniform float debug_mode = 5.0;
uniform vec3 debug_hit_color : source_color = vec3(1.0, 0.75, 0.25);
uniform float debug_distance_scale = 20000.0;	// нормировка дальностей режимов 1-2, м

// === B1: текстуры и параметры плотности ===
uniform sampler3D noise_pw : repeat_enable, filter_linear;		// Perlin-Worley 128³ (base shape)
uniform sampler3D noise_worley : repeat_enable, filter_linear;	// Worley 32³ (деталь/выступы)
uniform vec3 cloud_color : source_color = vec3(0.95, 0.95, 0.97);	// равномерное рассеяние (до B3)
uniform float cloud_base_scale = 16000.0;		// метров на период PW-текстуры
uniform float cloud_detail_scale = 1200.0;		// метров на период Worley-текстуры
uniform float cloud_coverage = 0.42;			// порог ремапа (по распределению PW!)
uniform float cloud_softness = 0.12;			// мягкость краёв (окно ±)
uniform float cloud_detail_strength = 0.18;		// амплитуда модуляции порога деталью
uniform float cloud_erosion = 0.40;			// B2: эрозия краёв деталью (ядра масс сохраняются)
uniform float detail_fade_start = 4000.0;		// B2: с этой дистанции деталь начинает гаситься
uniform float detail_fade_end = 12000.0;		// B2: с этой дистанции детали нет (лечение алиасинга марша)
uniform float cloud_vertical_stretch = 2.5;		// B2: во сколько раз PW тянется по Y (вертикальная связность)
uniform vec3 cloud_offset = vec3(0.0);			// мировое смещение поля, м (CPU-дрейф)

// === A7: высотный профиль ===
uniform float height_base_fade = 0.15;			// доля слоя снизу: нарастание (плоское основание)
uniform float height_top_fade = 0.35;			// доля слоя сверху: купольный спад

// === A5: интегрирование ===
uniform float march_steps = 64.0;				// шаги марша режима 5 (clamp 8..256)
uniform float max_ray_length = 30000.0;			// предел длины интегрирования, м
uniform float extinction_scale = 0.0025;		// σ на единицу плотности, 1/м
uniform float early_exit_transmittance = 0.01;	// порог раннего завершения

// === A4: предпросмотр (режим 4) ===
uniform float preview_steps = 32.0;
uniform float preview_gain = 1.0;

// Явный smoothstep (переносимость между бэкендами, A5).
float sstep(float lo, float hi, float x) {
	float t = clamp((x - lo) / (hi - lo), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// Плотность облаков (B1): текстуры Perlin-Worley (форма) + Worley (выступы) + профиль.
// CPU-зеркало: CloudsTestBench.compute_density() (трилинейная выборка тех же .bin
// с тем же соглашением тексель-центров (i+0.5)/n — совпадение до float32-точности).
float cloud_density(vec3 p, float t) {
	vec3 pw = p + cloud_offset;
	// B2: distance-fade детали (эрозия + выступы): там, где сегмент марша длиннее
	// фич детали (дальние лучи), высокочастотная эрозия только алиасит — гасим её.
	float fade = 1.0 - sstep(detail_fade_start, detail_fade_end, t);
	float ero = cloud_erosion * fade;
	float str = cloud_detail_strength * (0.25 + 0.75 * fade);
	// B2: вертикальное растяжение базового поля — PW меняется по Y в stretch раз
	// медленнее: массы становятся вертикально связными столбами без «расслоения»
	// 3D-жилами (наблюдение B1); силуэт верха/низа по-прежнему даёт профиль A7.
	vec3 q_base = vec3(pw.x, pw.y / cloud_vertical_stretch, pw.z) / cloud_base_scale;
	float shape = texture(noise_pw, q_base).r;
	float detail = texture(noise_worley, pw / cloud_detail_scale).r;
	// B2: эрозия краёв: вычитаем (1-detail)·(1-base)·erosion — кусает оболочку массы
	// (base ниже ядра), ядро (base→1) и пустота (base→0) не затрагиваются;
	// плюс выступы B1 (пороговая модуляция деталью).
	float n = shape - ero * (1.0 - detail) * (1.0 - shape)
			+ str * (detail - 0.5);
	float d = sstep(cloud_coverage - cloud_softness, cloud_coverage + cloud_softness, n);
	// высотный профиль (высоты от плоскости камеры; guard от вырожденного слоя)
	float thickness = max(cloud_layer_top - cloud_layer_bottom, 1e-4);
	float hgt = clamp((p.y - cloud_layer_bottom) / thickness, 0.0, 1.0);
	float profile = sstep(0.0, height_base_fade, hgt) * (1.0 - sstep(1.0 - height_top_fade, 1.0, hgt));
	return d * profile;
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

void sky() {
	vec3 dir = normalize(EYEDIR);
	float t_near = 0.0;
	float t_far = 0.0;
	bool hit = layer_interval(dir, cloud_layer_bottom, cloud_layer_top, t_near, t_far);

	if (debug_mode < 0.5) {
		// Режим 0 — маска HIT/MISS (A3)
		COLOR = hit ? debug_hit_color : sky_color;
	} else if (debug_mode < 1.5) {
		// Режим 1 — дальность входа t_near (A3)
		if (hit) {
			float d = clamp(t_near / debug_distance_scale, 0.0, 1.0);
			COLOR = mix(debug_hit_color, vec3(0.25, 0.05, 0.05), d);
		} else {
			COLOR = sky_color;
		}
	} else if (debug_mode < 2.5) {
		// Режим 2 — длина пути в слое (A3)
		if (hit) {
			float th = clamp((t_far - t_near) / debug_distance_scale, 0.0, 1.0);
			COLOR = mix(vec3(0.15, 0.05, 0.20), vec3(1.0), th);
		} else {
			COLOR = sky_color;
		}
	} else if (debug_mode < 3.5) {
		// Режим 3 — чистое небо (сравнение)
		COLOR = sky_color;
	} else if (debug_mode < 4.5) {
		// Режим 4 — предпросмотр: средняя плотность вдоль луча × gain (A4)
		if (!hit) {
			COLOR = sky_color;
		} else {
			int steps = int(clamp(preview_steps, 4.0, 128.0));
			float seg = (t_far - t_near) / float(steps);
			float acc = 0.0;
			for (int i = 0; i < steps; i++) {
				float t = t_near + (float(i) + 0.5) * seg;
				acc += cloud_density(dir * t, t);
			}
			float mean_density = acc / float(steps);
			COLOR = mix(sky_color, cloud_color, clamp(mean_density * preview_gain, 0.0, 1.0));
		}
	} else {
		// Режимы 5/6 — объёмный марш Beer-Lambert (A5) / визуализация T (A6)
		if (!hit) {
			COLOR = (debug_mode < 5.5) ? sky_color : vec3(1.0);
		} else {
			int steps = int(clamp(march_steps, 8.0, 256.0));
			float t_end = min(t_far, t_near + max_ray_length);	// ограничение длины
			float seg = (t_end - t_near) / float(steps);
			float transmittance = 1.0;
			vec3 scattered = vec3(0.0);
			if (seg > 0.0) {	// защита от нулевой/отрицательной длины
				for (int i = 0; i < steps; i++) {
					float t = t_near + (float(i) + 0.5) * seg;
					float d = cloud_density(dir * t, t);
					float step_tr = exp(-d * extinction_scale * seg);
					scattered += transmittance * (1.0 - step_tr) * cloud_color;
					transmittance *= step_tr;
					if (transmittance < early_exit_transmittance) {
						break;	// раннее завершение
					}
				}
			}
			if (debug_mode < 5.5) {
				// Финальный композит (A6): предумноженная сборка, фон гасится на T.
				COLOR = sky_color * transmittance + scattered;
			} else {
				// Режим 6: чистое пропускание.
				COLOR = vec3(transmittance);
			}
		}
	}
}
