shader_type sky;
// omega_sky_shader.gdshader — процедурное небо Rengar Prototype Omega (Q7.29).
// Тёмное фэнтези: багровый закат → фиолетовые сумерки → лунная ночь. ДНЯ НЕТ.
// Godot 4.3-совместимый синтаксис sky-шейдера: точка входа void sky(),
// направление взгляда — built-in EYEDIR (vec3), вывод — COLOR (vec3).
// (SKY_COORDS в sky-шейдере 4.x — vec2-uv панорамы, НЕ направление: проверено
// по внутренним шейдерам движка 18.10.2026.)
//
// СЕКЦИИ (логические, один проход): 1 градиент, 2 горизонтная дымка, 3 крупные
// облака, 4 деталь облаков, 5 освещение облаков, 6 луна, 7 звёзды, 8 композит.
//
// ВРЕМЯ/ДВИЖЕНИЕ: облака НЕ используют TIME и не шагуют на кадр — контроллер
// (TimeOfDayController) накапливает смещения на CPU (double, без дрейфа за
// длинные сессии) и пишет cloud_offset_large / cloud_offset_detail: движение
// независимо от частоты кадров и от камеры; направления слоёв независимы.
//
// КАЧЕСТВО: quality_detail (0=Performance, 1=Quality) гейтит detail-слой шума,
// второй слой облаков и гало луны. Ветвление по uniform — документировано в
// отчёте: стоимость ветки одинакова для всех пикселей кадра (uniform-branch),
// реальную цену слоёв измеряет заказчик на своём железе (процедура в отчёте).

// === 1. ПАЛИТРЫ ФАЗ (контроллер lerpt веса и цвета) ===
// Веса фаз: sunset_amount=1,night=0 → закат; 0,0 → сумерки; 0,1 → ночь.
uniform float sunset_amount = 1.0;
uniform float night_amount = 0.0;
uniform vec3 sunset_horizon_color : source_color = vec3(0.72, 0.08, 0.18);
uniform vec3 sunset_mid_color : source_color = vec3(0.52, 0.14, 0.40);
uniform vec3 sunset_zenith_color : source_color = vec3(0.10, 0.06, 0.20);
uniform vec3 twilight_horizon_color : source_color = vec3(0.38, 0.14, 0.36);
uniform vec3 twilight_mid_color : source_color = vec3(0.20, 0.11, 0.36);
uniform vec3 twilight_zenith_color : source_color = vec3(0.05, 0.04, 0.14);
uniform vec3 night_horizon_color : source_color = vec3(0.09, 0.12, 0.26);
uniform vec3 night_mid_color : source_color = vec3(0.05, 0.07, 0.18);
uniform vec3 night_zenith_color : source_color = vec3(0.012, 0.018, 0.06);

// === 2. ДЫМКА ГОРИЗОНТА ===
uniform float horizon_haze_strength = 0.55;
uniform vec3 horizon_haze_color : source_color = vec3(0.85, 0.35, 0.30);

// === 3-5. ОБЛАКА ===
uniform sampler2D cloud_large_tex : repeat_enable;
uniform sampler2D cloud_detail_tex : repeat_enable;
uniform vec2 cloud_offset_large = vec2(0.0);
uniform vec2 cloud_offset_detail = vec2(0.0);
uniform float cloud_coverage = 0.45;
uniform float cloud_density = 0.35;
uniform float cloud_opacity = 0.85;
uniform float cloud_large_scale = 0.55;
uniform float cloud_detail_scale = 2.1;
uniform float cloud_detail_strength = 0.45;
uniform vec3 cloud_light_direction = vec3(-0.4, 0.25, -0.8);
uniform vec3 cloud_light_color : source_color = vec3(1.0, 0.55, 0.45);
uniform vec3 cloud_dark_color : source_color = vec3(0.16, 0.08, 0.16);
uniform float cloud_light_strength = 1.0;

// === 6. ЛУНА ===
uniform vec3 moon_direction = vec3(0.35, 0.45, -0.82);
uniform float moon_size = 0.045;          // угловой радиус, радианы
uniform float moon_intensity = 0.0;       // 0 днём-закатом, ~1.2 ночью
uniform float moon_halo_strength = 0.0;
uniform vec3 moon_color : source_color = vec3(0.92, 0.94, 1.0);

// === 7. ЗВЁЗДЫ ===
uniform float star_intensity = 0.0;
uniform float star_visibility = 0.0;      // контроллер растит к ночи

// === 9. КАЧЕСТВО ===
uniform float quality_detail = 1.0;       // 0 = Performance, 1 = Quality

// === 3b. ЗАМОСТКА ОБЛАКОВ (Q7.30) ===
// Авторские текстуры облаков заказчика (v1/v2) НЕ бесшовные: замер «линейкой»
// 18.10.2026 (отношение скачка на стыке к среднему внутреннему скачку):
//   v1: H=1.94, V=3.05;  v2: H=3.73, V=2.58  (порог заметности ~1.5).
// Обычный REPEAT дал бы видимую линию шва поперёк неба при дрейфе облаков.
// Треугольная волна uv (период 2 в uv-пространстве) замощает зеркально:
// значение C0-непрерывно на границе плитки (линии нет), производная
// меняет знак — для шумовых облаков незаметно. Оригиналы автора не правим;
// когда придёт обещанная бесшовная «текстура маленьких облаков» — сэмплирование
// можно вернуть к plain texture() одной правкой этой функции.
float cloud_sample(sampler2D tex, vec2 uv) {
	vec2 m = mod(uv, 2.0);
	return texture(tex, 1.0 - abs(1.0 - m)).r;
}

float hash13(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

vec3 hash33(vec3 p) {
	return vec3(
		fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123),
		fract(sin(dot(p, vec3(269.5, 183.3, 246.1))) * 43758.5453123),
		fract(sin(dot(p, vec3(113.5, 271.9, 124.6))) * 43758.5453123));
}

// Две смещённые кубические сетки по направлению — без регулярной решётки в кадре.
float star_field(vec3 d) {
	vec3 p = d * 150.0;
	vec3 cell = floor(p);
	vec3 f = fract(p);
	vec3 rnd = hash33(cell);
	float s = step(0.88, rnd.z) * smoothstep(0.14, 0.0, length(f - (0.5 + 0.55 * (rnd - 0.5)))) * (0.45 + 0.55 * rnd.y);
	vec3 p2 = p + vec3(0.37, 0.53, 0.71);
	vec3 cell2 = floor(p2);
	vec3 f2 = fract(p2);
	vec3 rnd2 = hash33(cell2);
	s += step(0.91, rnd2.x) * smoothstep(0.10, 0.0, length(f2 - (0.5 + 0.55 * (rnd2 - 0.5)))) * (0.35 + 0.65 * rnd2.z);
	return clamp(s, 0.0, 1.0);
}

float moon_craters(vec3 d) {
	// Дешёвая «поверхность» луны: крупный hash по направлению, только внутри диска.
	return 0.85 + 0.15 * hash13(floor(d * 90.0));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	float up = max(h, 0.0);

	// --- 1. Градиент неба: три стопа фазы, фигурные smoothstep (без полос) ---
	vec3 hor = mix(mix(twilight_horizon_color, sunset_horizon_color, sunset_amount), night_horizon_color, night_amount);
	vec3 mid = mix(mix(twilight_mid_color, sunset_mid_color, sunset_amount), night_mid_color, night_amount);
	vec3 zen = mix(mix(twilight_zenith_color, sunset_zenith_color, sunset_amount), night_zenith_color, night_amount);
	vec3 col = mix(hor, mid, smoothstep(0.0, 0.26, up));
	col = mix(col, zen, smoothstep(0.16, 0.62, up));
	// Ниже горизонта — тёмная земля-дымка, без резкой границы.
	col = mix(hor * 0.30, col, smoothstep(-0.07, 0.03, h));

	// --- 7. Звёзды (ранний слой: облака и луна перекроют) ---
	float stars = star_field(dir) * star_visibility * star_intensity;
	col += vec3(stars);

	// --- 6. Луна: диск + мягкое гало; светит ТОЛЬКО в небе (освещает сцену
	//        отдельный DirectionalLight3D — контракт промта §4.3) ---
	vec3 mdir = normalize(moon_direction + vec3(0.0001));
	float mdot = dot(dir, mdir);
	float ang = acos(clamp(mdot, -1.0, 1.0));
	float disk = 1.0 - smoothstep(moon_size * 0.88, moon_size, ang);
	float halo = pow(max(mdot, 0.0), 120.0) * moon_halo_strength
		+ pow(max(mdot, 0.0), 12.0) * moon_halo_strength * 0.18 * quality_detail;
	col += moon_color * (disk * moon_intensity * moon_craters(dir) + halo);

	// --- 3-4. Облака: планарная проекция с защитой у горизонта ---
	float cfade = smoothstep(-0.02, 0.10, h);
	vec2 uv = dir.xz / max(h, 0.06);
	float n1 = cloud_sample(cloud_large_tex, uv * cloud_large_scale + cloud_offset_large);
	float shape = n1;
	float detail_v = 0.0;
	if (quality_detail > 0.5) {
		detail_v = (cloud_sample(cloud_detail_tex, uv * cloud_detail_scale + cloud_offset_detail) - 0.5) * cloud_detail_strength;
		shape += detail_v;
	}
	float cov = clamp(cloud_coverage, 0.0, 0.95);
	float mask = smoothstep(1.0 - cov, 1.0 - cov + max(cloud_density, 0.02), shape);
	if (quality_detail > 0.5) {
		// Второй слой: другой масштаб и собственное смещение — глубина без volumetric.
		vec2 uv2 = uv * (cloud_large_scale * 2.3) + cloud_offset_large * 0.55 + cloud_offset_detail * 0.30 + vec2(0.37, 0.71);
		float n3 = cloud_sample(cloud_large_tex, uv2);
		float shape2 = n3 + (cloud_sample(cloud_detail_tex, uv2 * 1.7 + cloud_offset_detail * 1.3) - 0.5) * cloud_detail_strength * 0.5;
		float mask2 = smoothstep(1.05 - cov, 1.05 - cov + cloud_density + 0.10, shape2) * 0.55;
		mask = clamp(mask + mask2 * (1.0 - mask), 0.0, 1.0);
	}
	float cloud_a = mask * cloud_opacity * cfade;

	// --- 5. Освещение облаков: сдвиг-сэмпл к источнику = псевдо-объём ---
	vec2 ldir2 = normalize(cloud_light_direction + vec3(0.0001)).xz;
	float sh = cloud_sample(cloud_large_tex, uv * cloud_large_scale + cloud_offset_large - ldir2 * 0.02);
	float shade = clamp((shape - sh) * 6.0 + 0.55, 0.0, 1.0);
	vec3 ccol = mix(cloud_dark_color, cloud_light_color, clamp(shade * cloud_light_strength, 0.0, 1.0));

	// --- 8. Композит: облака поверх звёзд/луны (маска облаков их укрывает) ---
	col = mix(col, ccol, cloud_a);

	// --- 2. Дымка горизонта последней: склеивает облака с горизонтом ---
	float haze = exp(-max(h + 0.02, 0.0) * 7.0) * horizon_haze_strength;
	col = mix(col, horizon_haze_color, clamp(haze, 0.0, 0.80));

	COLOR = col;
}
