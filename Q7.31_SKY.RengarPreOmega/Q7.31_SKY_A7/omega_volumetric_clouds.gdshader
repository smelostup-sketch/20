shader_type sky;
// omega_volumetric_clouds.gdshader — RENGAR PROTOTYPE OMEGA, компонент Q7.31_SKY_A7.
// ЭТАП A7: формирование кучевых облаков — высотный профиль (плоское основание),
// крупная форма (наследие A4, ~2.5 км) и округлые выступы (детальный шум модулирует
// границу масс). Дополнительная детализация сверх двух полей FBM СОЗНАТЕЛЬНО не
// добавлялась: сначала правильный крупный силуэт (по плану этапа); оценка потребности
// в большем числе шумов — в README §6.
// ЭТАП A6 (сохранён): transmittance/compositing, соглашения вывода по документации 4.7.
//
// СОГЛАШЕНИЯ GODOT 4.7 (проверено по официальной документации sky_shader, stable/4.7):
//   - "out float ALPHA — Output alpha value, CAN ONLY BE USED IN SUBPASSES". Субпасы
//     (use_half_res_pass/use_quarter_res_pass) НЕ используются: марш считается в полном
//     разрешении, ALPHA не пишется сознательно.
//   - Небо рисуется непрозрачным фоном для всех не закрытых фрагментов: COLOR — финальная
//     радиance-сборка. Правильный композитинг — ВНУТРИ COLOR:
//     COLOR = sky_color * T + scattered, где scattered накапливается ПРЕДУМНОЖЕННЫМ
//     пропусканием (transmittance * (1 - step_tr) * cloud_color) — стандартная сборка
//     премноженной радиации; аддитивной ошибки (sky + scattered без *T) нет по построению,
//     энергосохранение scattered + T = 1 при albedo = 1 (телескопическая сумма).
//   - Шейдер также исполняется для radiance cubemap (Environment.ambient_light_source =
//     SKY) — ambient согласован с небом автоматически (один и тот же код).
//   - "in vec3 POSITION" (мировая позиция камеры) В GODOT 4.7 ЕСТЬ — исправление ошибки
//     в комментариях A5. Пока СОЗНАТЕЛЬНО не используется: слой отсчитывается от камеры,
//     мировое якорение (bottom/top от уровня моря + camera_height) — кандидат A7/A8;
//     по документации использование POSITION заставляет обновлять radiance cubemap при
//     каждом движении камеры.
//
// ЭТАП A5 (сохранён): интегрирование вдоль луча (raymarching с оптической толщиной).
//
// ДОБАВЛЕНО сверх A4:
//   - режим 5 (по умолчанию): полноценный марш по [t_near, t_end] с накоплением
//     оптической толщины по Beer-Lambert. Затухание внутри сегмента считается
//     АНАЛИТИЧЕСКИ: step_tr = exp(-density * extinction_scale * seg), вклад шага
//     transmittance * (1 - step_tr) * cloud_color — схема энергосохраняющая
//     (телескопическая сумма: scattered + transmittance == 1 при albedo=1) и
//     устойчивая к числу шагов (нет «случайных пропусков» при редких шагах);
//   - ограничение длины интегрирования: t_end = min(t_far, t_near + max_ray_length)
//     (у горизонта луч не марширует бесконечно);
//   - early termination: break при transmittance < early_exit_transmittance;
//   - контролируемое число шагов: march_steps (clamp 8..256);
//   - защита от нулевой/отрицательной длины: hit гарантирует t_far > t_near >= 0
//     (A3), плюс явный guard seg <= 0 → марш не выполняется (T=1, пустой вклад).
//
// СОЗНАТЕЛЬНО ОТСУТСТВУЕТ (по плану фазы A): освещение/self-shadowing/powder/
// multiple scattering — НЕ входят и в A6 (A6 = корректность композитинга), режимы 5/6
// рассеивают равномерный cloud_color; высотный профиль и кучевые силуэты — A7.
//
// СОХРАНЕНО (регрессия проверена): layer_interval() со всеми защитами A3, режимы
// 0-3 (геометрия), режим 4 (A4-предпросмотр средней плотности), cloud_density/FBM.
//
// Проверенные возможности Godot 4.7 sky-шейдера: EYEDIR, COLOR, uniform-ы с
// source_color, функции с out-параметрами, for с uniform-границей и break, exp() —
// компиляция подтверждена реальными запусками (GL3 + Vulkan).

uniform vec3 sky_color : source_color = vec3(0.32, 0.47, 0.68);	// фон: лучи без пересечения
uniform float cloud_layer_bottom = 1500.0;	// низ слоя, мировые единицы (м)
uniform float cloud_layer_top = 3500.0;		// верх слоя, мировые единицы (м)

// Отладочные режимы (клавиши стенда 0-5):
//   0 = маска HIT/MISS; 1 = дальность входа t_near; 2 = длина пути; 3 = чистый sky_color;
//   4 = A4-предпросмотр (средняя плотность × gain); 5 = A5-объёмный марш (по умолчанию);
//   6 = A6-визуализация пропускания: COLOR = vec3(T) (белый = прозрачно, чёрный = плотно).
uniform float debug_mode = 5.0;
uniform vec3 debug_hit_color : source_color = vec3(1.0, 0.75, 0.25);
uniform float debug_distance_scale = 20000.0;	// нормировка дальностей режимов 1-2, м

// === A4: параметры поля плотности ===
uniform vec3 cloud_color : source_color = vec3(0.95, 0.95, 0.97);	// цвет масс (режим 4) / равномерное рассеяние (режимы 5/6; освещение — вне фазы A)
uniform float density_frequency = 0.0004;	// ~1/2500 м — размер масс
uniform float density_coverage = 0.5;			// порог FBM: больше → яснее
uniform float density_softness = 0.1;			// мягкость краёв масс (окно smoothstep ±)
uniform vec3 density_offset = vec3(0.0);		// сдвиг поля (A5+: CPU-дрейф от контроллера)
uniform float preview_steps = 32.0;				// шаги предпросмотра режима 4 (clamp 4..128)
uniform float preview_gain = 1.0;				// яркость режима 4 = средняя плотность × gain

// === A7: выступы и высотный профиль ===
uniform float detail_frequency = 0.0016;		// частота выступов (~1/625 м — доли крупной массы)
uniform float detail_strength = 0.18;			// амплитуда модуляции границы масс (сравнима с softness)
uniform float height_base_fade = 0.15;			// доля слоя снизу: нарастание плотности (плоское основание)
uniform float height_top_fade = 0.35;			// доля слоя сверху: спад плотности (купольный верх)

// === A5: параметры интегрирования ===
uniform float march_steps = 64.0;				// шаги марша режима 5 (clamp 8..256)
uniform float max_ray_length = 30000.0;			// предел длины интегрирования, м
uniform float extinction_scale = 0.0025;		// σ: коэффициент экстинкции на единицу плотности, 1/м
uniform float early_exit_transmittance = 0.01;	// порог раннего завершения по пропусканию

// Целочисленный хэш решётки. ПОЧЕМУ НЕ float-хэш: кросс-драйверное расследование A5
// показало, что fract-каскад (hash13 Дэйва Хоскинса) даёт СИСТЕМАТИЧЕСКИ разные поля
// на Vulkan (lavapipe) и GL3 (llvmpipe) — расхождение средней плотности ~0.027 на
// разреженном поле, далеко за пределами float-шума; бинарный порог это маскировал.
// Побитовые операции над uint детерминированы побитово на любом совместимом бэкенде
// (умножение/сдвиг/xor по модулю 2^32), поэтому хэш целочисленный.
// Ограничение: координаты решётки |p| < 32000 (сдвиг +32768 должен оставаться >= 0;
// наши p = pos*0.0004 + offset заведомо |p| < 100).
uint ihash3(ivec3 p) {
	uvec3 q = uvec3(p + ivec3(32768));
	uint h = q.x * 374761393u + q.y * 668265263u + q.z * 2147483647u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return h ^ (h >> 16u);
}

float hash13i(ivec3 p) {
	return float(ihash3(p)) * (1.0 / 4294967295.0);
}

// 3D value-noise: трилинейная интерполяция целочисленных хэшей углов ячейки.
float value_noise(vec3 p) {
	vec3 fl = floor(p);
	ivec3 i = ivec3(fl);
	vec3 f = p - fl;
	vec3 u = f * f * (3.0 - 2.0 * f);
	float c000 = hash13i(i + ivec3(0, 0, 0));
	float c100 = hash13i(i + ivec3(1, 0, 0));
	float c010 = hash13i(i + ivec3(0, 1, 0));
	float c110 = hash13i(i + ivec3(1, 1, 0));
	float c001 = hash13i(i + ivec3(0, 0, 1));
	float c101 = hash13i(i + ivec3(1, 0, 1));
	float c011 = hash13i(i + ivec3(0, 1, 1));
	float c111 = hash13i(i + ivec3(1, 1, 1));
	return mix(mix(mix(c000, c100, u.x), mix(c010, c110, u.x), u.y),
			mix(mix(c001, c101, u.x), mix(c011, c111, u.x), u.y), u.z);
}

// FBM, 4 октавы; нецелая лакунарность 2.03 снижает осевые артефакты решётки.
float fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	float total_amp = 0.0;
	for (int o = 0; o < 4; o++) {
		sum += amp * value_noise(p);
		total_amp += amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return sum / total_amp;
}

// Явный smoothstep (вместо встроенного): НАЙДЕНО КРОСС-ДРАЙВЕРНОЕ РАСХОЖДЕНИЕ —
// встроенный smoothstep на lavapipe (Vulkan) возвращал заниженно-ненулевые значения
// под порогом против llvmpipe/GL3 и float64-эталона (средняя плотность 0.045 против
// 0.018 на разреженном поле). Явная формула clamp + t*t*(3-2t) детерминирована
// на всех бэкендах. Зеркало: CloudsTestBench.compute_density().
float sstep(float lo, float hi, float x) {
	float t = clamp((x - lo) / (hi - lo), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// Плотность облаков (A7): крупная форма + округлые выступы + высотный профиль.
//   1) shape  = FBM на density_frequency (~2.5 км) — где массы существуют (A4);
//   2) detail = FBM на detail_frequency (~625 м) — модулирует ПОРОГ ремапа на
//      ±detail_strength/2: граница масс становится округло-бугристой (выступы),
//      ядра плотных масс и чистые зоны не затрагиваются (возмущение меньше окна);
//   3) height profile: smoothstep-нарастание у дна слоя (плоское основание — признак
//      кучевых) и спад у верха слоя (купольность). hgt — доля высоты в слое [0,1].
// Оба поля детерминированы целочисленным хэшем (A5); профиль — явный sstep (A5).
// CPU-зеркало: CloudsTestBench.compute_density() — параметры синхронизированы.
float cloud_density(vec3 p) {
	float shape = fbm(p * density_frequency + density_offset);
	float detail = fbm(p * detail_frequency + density_offset);
	float n = shape + detail_strength * (detail - 0.5);
	float lo = density_coverage - density_softness;
	float hi = density_coverage + density_softness;
	float d = sstep(lo, hi, n);
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
		// Режим 4 — A4: предпросмотр (средняя плотность вдоль луча × gain)
		if (!hit) {
			COLOR = sky_color;
		} else {
			int steps = int(clamp(preview_steps, 4.0, 128.0));
			float seg = (t_far - t_near) / float(steps);
			float acc = 0.0;
			for (int i = 0; i < steps; i++) {
				float t = t_near + (float(i) + 0.5) * seg;
				acc += cloud_density(dir * t);
			}
			float mean_density = acc / float(steps);
			COLOR = mix(sky_color, cloud_color, clamp(mean_density * preview_gain, 0.0, 1.0));
		}
	} else {
		// Режимы 5/6 — A5: объёмный марш с Beer-Lambert; A6: вывод T (режим 6).
		// Аналитическое затухание в сегменте → энергосохранение и устойчивость к шагу.
		if (!hit) {
			// MISS: T = 1 по определению → режим 5 даёт чистый фон, режим 6 — белый.
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
					float d = cloud_density(dir * t);
					float step_tr = exp(-d * extinction_scale * seg);
					scattered += transmittance * (1.0 - step_tr) * cloud_color;
					transmittance *= step_tr;
					if (transmittance < early_exit_transmittance) {
						break;	// раннее завершение: дальше вклад пренебрежим
					}
				}
			}
			if (debug_mode < 5.5) {
				// Финальный композит (A6): предумноженная сборка, фон гасится на T.
				COLOR = sky_color * transmittance + scattered;
			} else {
				// Режим 6: чистое пропускание — диагностика «плотные облака не прозрачны».
				COLOR = vec3(transmittance);
			}
		}
	}
}
