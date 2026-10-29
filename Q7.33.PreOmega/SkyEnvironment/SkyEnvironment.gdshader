shader_type sky;
// ВЕРСИЯ: Q7.33 (единая сборка, 28.10.2026). Происхождение: Q7.32.PreOmega.SL
// (preomega_sky.gdshader, r11_s4_antisolar180_nohorline), перенесён в SkyEnvironment/.
//
// >>> НОРМАТИВНЫЙ ДОКУМЕНТ: ТЗ_небо_единая_сборка_Q7.33.md (глава 11).
// >>> Четыре сущности: СОЛЯР, ГРАДИЕНТ P(dir), АНТИСОЛЯР, ЛУНА. Зенит/надир —
// >>> НЕ сущности и своего цвета не имеют (SKY_CORE_SPEC §7).
//
// Вуаль удалена в Q7.33, архив в архив/veil/ (задел для задачи З-1 «Облака»;
// вместе с ней удалены мёртвые uniform-интерфейсы освещения слоя облаков).
//
// ИСТОРИЯ ГРАДИЕНТА (сохранена из r10_s4/r11_s4 — метрика не тронута, п. 11.1 ТЗ):
//   r11_s4 Ф1 «антисоляр стягивается к соляру»: dv = dot(w, upn), обе составляющие
//     из касательной плоскости в точке sd → u(-s) = 1 точно на любой высоте солнца;
//   r11_s4 Ф2 «эллипс вырождается»: hh = dh / S, S = mix(sk_arc_stretch, 1.0, gate)
//     → у полюса S = 1, u = угол/π, честный круг;
//   r10_s4: wedge/below/zen_w удалены как костыли (не возвращать — п. 19.7 ТЗ).

// Явный smoothstep (переносимость между бэкендами, A5).
float sstep(float lo, float hi, float x) {
	float t = clamp((x - lo) / (hi - lo), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// === Фон неба ===
uniform bool use_gradient_sky = true;			// выкл → плоский sky_color
uniform vec3 sky_color : source_color = vec3(0.32, 0.47, 0.68);	// плоское небо (use_gradient_sky=false)

// ==== ПАЛИТРА ГРАДИЕНТА: соляр → антисоляр, стопы = данные состояния ====
uniform vec3 sk_horizon : source_color = vec3(1.0, 0.3529, 0.2275);	// COLORS5: display-данные (hex/255)
uniform vec3 sk_glow_col : source_color = vec3(1.0, 0.3529, 0.2275);	// COLORS5: display-данные (hex/255)
uniform float sk_glow_int : hint_range(0.0, 4.0) = 0.30;
uniform float sk_glow_exp : hint_range(1.0, 128.0) = 6.0;
uniform vec3 sk_sun_dir = vec3(0.0, 0.0, -1.0);	// направление НА солнце (мировое; конвенция basis.z DirectionalLight3D)
uniform vec3 sk_moon_dir = vec3(0.0, 0.766, 0.643);	// НА луну (мировое; независима от солнца; дефолт elev 50° azim 0°)
uniform vec3 sk_anti_col : source_color = vec3(0.1596, 0.0789, 0.1330);	// антисоляр = самая тёмная точка купола (COLORS5: display hex/255)
// Q7.33 (C.3, п. 11.7): ореол источника и стрик — ОТДЕЛЬНЫЙ цвет, не связанный со
// стопом 0 рампы (sk_glow_col). Два независимых uniform'а, никакого коэффициента связи.
uniform vec3 sk_halo_col : source_color = vec3(2.0, 0.078501, 0.036102);	// ореол источника + стрик (ЕДИНСТВЕННЫЙ linear-HDR цвет: >1, конвертится scene2disp)
uniform vec3 sk_band_col : source_color = vec3(0.0);	// пояс 1 рампы (цвет — данные ключа)
uniform vec3 sk_band2_col : source_color = vec3(0.0);	// пояс 2 рампы (цвет — данные ключа)
// === ГРАДИЕНТ КУПОЛА: ЕДИНАЯ МОДЕЛЬ НА ВСЕ КЛЮЧИ ===
// Купол = ОДНА многостопная рампа по угловому удалению от солнца u (u_ellip),
// 0 = направление на солнце, 1 = антисоляр. Между ключами различаются ТОЛЬКО
// ДАННЫЕ. ЛЕСТНИЦА СТОПОВ (порядок от солнца к антисоляру):
//   u < p1        sk_glow_col   ядро зари (у солнца)
//   p1 .. p2      sk_horizon    горизонтальный пояс
//   p2 .. p3      sk_band_col   пояс 1
//   p3 .. p4      sk_band2_col  пояс 2
//   p4 .. p5      sk_mid        средний купол
//   p5 .. 1       sk_anti_col   самая тёмная область (антисоляр)
// Q7.34 (COLORS5): данные стопов — КОДИРОВАННЫЙ display (palette hex/255, 0..1).
// ramp_u смешивает их В КОДИРОВАННОМ ПРОСТРАНСТВЕ (равномерный плавный градиент,
// как CSS; прежний mix в линейном свете давал «резкий» переход: большая часть
// угла тонула вблизи тёмного стопа). Декодирование — один раз в sky_palette_disp.
uniform float sk_p1 = 0.010;	// край ядра зари (u); 0.010 ≈ 1.8° вокруг солнца
uniform float sk_p2 = 0.075;	// положение стопа sk_horizon (u)
uniform float sk_p3 = 0.155;	// положение стопа sk_band_col (u)
uniform float sk_p4 = 0.300;	// положение стопа sk_band2_col (u)
uniform float sk_p5 = 0.520;	// положение стопа sk_mid (u)
// Q7.33 (шаг C.1, решение 3): рампа ЦЕЛИКОМ данные — ноль констант в шейдере.
uniform float sk_p6 : hint_range(0.0, 1.0) = 1.0;	// антисоляр (конец); 1.0 = самый плавный уход
uniform float sk_sharp : hint_range(0.05, 1.0) = 1.0;	// резкость переходов: 1.0 = окно на всю дистанцию до стопа, 0.1 = почти ступени
// Q7.34 (COLORS6, S15): «дыхание» купола — СИЛА динамического варпа шкалы u от
// высоты солнца: γ = 1 + sk_breathe·sin(elev) (см. ramp_u). Диапазон 0..0.9
// гарантирует γ ≥ 0.1 > 0 — pow определён на всей шкале, включая полюса;
// 0.0 = функция побитово выключена (γ ≡ 1, pow(u,1) = u). Данные пресета.
uniform float sk_breathe : hint_range(0.0, 0.9) = 0.0;
// Q7.34 (COLORS7, S17): компенсация складки у горизонта: сжатие антисолярных окон
// шкалы в пригоризонтной зоне силой, пропорциональной стретчу эллипса (S−1) и
// близости взгляда к горизонту (h). 0 = побитовое выкл. Закон — в ramp_u.
uniform float sk_squeeze : hint_range(0.0, 2.0) = 0.0;
// ЭЛЛИПС: ГЛОБАЛЬНАЯ константа формы. Горизонтальная составляющая углового
// смещения делится на S → изолинии градиента = эллипсы с горизонтальной большой осью.
uniform float sk_arc_stretch : hint_range(1.0, 4.0) = 2.4;
uniform float sk_dither : hint_range(0.0, 1.0) = 1.0;

// === Общая угловая палитра P(dir): средний пояс рампы ===
uniform vec3 sk_mid : source_color = vec3(0.4157, 0.2275, 0.3529);	// mid K4 (багровый закат; COLORS5: display hex/255)

// === Солнце — аналитический диск (fwidth-AA) + два ореола (средний g1, широкий g2) ===
uniform bool sun_enabled = true;			// мастер-выключатель диска и ореолов (имя A, решение 15)
uniform float sun_size_deg = 1.8;			// художественный угловой радиус диска, °
uniform float sun_core_int = 5.0;			// HDR-яркость ядра (bloom-порог ~1.0)
uniform float sun_g1_int = 0.35;			// средний ореол: амплитуда
uniform float sun_g1_exp = 8.0;				// средний ореол: угловой спад
uniform float sun_g2_int = 0.12;			// широкое поле: амплитуда
uniform float sun_g2_exp = 2.5;				// широкое поле: угловой спад
uniform vec3 sun_disk_color = vec3(1.0, 0.953, 0.816);	// display-space, доли hex/255 по K-ключам

// === Луна (Q7.33: без фаз — всегда полная, решение 10; антипод погашен механизмом солнца, п. 11.3) ===
uniform bool moon_enabled = true;			// мастер-выключатель луны (конвенция A, решение 15)
uniform float moon_size = 0.02;				// угловой радиус луны, радианы (~1.1°, художественный)
uniform vec3 moon_color = vec3(0.753, 0.784, 0.910);	// display-space, доли hex/255 по K-ключам
uniform float moon_glow_int = 0.0;			// амплитуда ореола луны (0.35/0.2/0.1 для K0/K1/K2)
uniform float moon_glow_exp = 40.0;			// угловой спад ореола луны

// === Звёзды (процедурные, два слоя hash-точек с мягким ядром, без мерцания) ===
uniform float star_intensity = 0.0;			// 1.0/0.7/0.25/0.05/0 для K0..K4+
// Q7.33 (C.6, п. 11.10): режим отладки (замена диагностики вуали из B).
uniform int sky_debug_mode : hint_range(0, 2) = 0;	// 0 = небо, 1 = u, 2 = номер сегмента
// Q7.34 (S2): эксперимент comp_linear УДАЛЁН. Q7.34 (COLORS5): цепей вывода ДВЕ,
// и они зеркальны движку — переключатель sk_tonemap (см. ниже). Данные стопов
// (col_* = palette hex/255) и их байт-точность на экране ОДИНАКОВЫ в обоих режимах.
uniform int sk_tonemap : hint_range(0, 1) = 0;	// 0 = Filmic (цепь A, сцены заморожены tonemap_mode=2), 1 = Linear (tonemap_mode=0)

// === Ассеты заказчика: стрик-глэйр и деталь луны ===
uniform sampler2D streak_tex : filter_linear;		// рисованный горизонтальный глэйр (бесцветный)
uniform float streak_int = 0.0;				// интенсивность стриков по K-ключам (K4 золото → 0.5)
// Q7.33 (C.3, решение 3): границы гейта стрика — данные, не зашитые градусы.
uniform float sk_streak_gate_lo : hint_range(0.0, 180.0) = 45.0;
uniform float sk_streak_gate_hi : hint_range(0.0, 180.0) = 60.0;
// Q7.34 (S8, баг 3.4): ЭКРАННЫЙ базис стрика — пишется контроллером покадрово из
// камеры (right камеры, спроектированный перпендикулярно sd). Стрик горизонтален
// на экране при любом солнце; на полюсах не вырождается (баг 3.2, H1).
uniform vec3 sk_streak_right = vec3(1.0, 0.0, 0.0);
uniform sampler2D moon_detail_tex : filter_linear;	// grayscale-карта кратеров
uniform float moon_detail_int = 0.5;		// доля детали (кратеры)

// u_ellip(dir, sd) — угловое удаление от солнца в ЭЛЛИПТИЧЕСКОЙ метрике, 0..1:
//   0 = направление на солнце, 1 = антисоляр. Вертикальная составляющая смещения
//   входит как есть, горизонтальная — делённой на S (sk_arc_stretch, ГЛОБАЛЬНАЯ
//   константа): свет расходится вдоль горизонта в S раз дальше, чем по высоте.
//   Численно устойчиво: sin(угла) = |dir × sd|, cos(угла) = dir · sd — без acos.
//   МЕТРИКА НЕ ТРОНУТА (п. 11.1 ТЗ): u(-s) = 1.00000 на всех 19 контрольных
//   высотах; в плоскости солнца u = угол/π точно; у полюса S → 1, не вырождается.
float u_ellip(vec3 dir, vec3 sd) {
	vec3 w = dir - sd * dot(dir, sd);			// смещение, перпендикулярное sd (касательное)
	vec3 up0 = abs(sd.y) > 0.99 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	vec3 upr = up0 - sd * dot(up0, sd);			// «вверх» в плоскости солнце-зенит
	float lu = length(upr);
	vec3 upn = (lu > 1e-5) ? upr / lu : vec3(0.0, 0.0, 1.0);
	vec3 rgt = (lu > 1e-5) ? cross(sd, upn) : vec3(1.0, 0.0, 0.0);	// вдоль горизонту
	// r11_s4 ФИКС 1/2: dv из КАСАТЕЛЬНОЙ плоскости в точке sd → u(антисоляр) = 1 точно.
	float dv = dot(w, upn);
	// r11_s4 ФИКС 2/2: растяжение снимается ПЛАВНЫМ УХОДОМ S → 1 у зенита/надира солнца.
	float S = mix(max(sk_arc_stretch, 1.0), 1.0, sstep(0.85, 0.99, abs(sd.y)));
	float hh = abs(dot(w, rgt)) / S;
	return atan(sqrt(dv * dv + hh * hh), dot(dir, sd)) / 3.141592653589793;
}

// Окно перехода (Q7.33, п. 11.5): прижато к ПРАВОМУ стопу, ширина = (hi-lo)*sk_sharp.
// Положение цветов на шкале не плывёт при изменении резкости.
float win(float lo, float hi, float x) {
	float w = (hi - lo) * sk_sharp;			// окно прижато к ПРАВОМУ стопу
	return smoothstep(hi - w, hi, x);
}

// Многостопная рампа градиента по u (лестница стопов — см. uniform'ы выше).
// Q7.33 (C.1): ноль литералов, ноль max()-страховок порядка. Дыра невозможна
// структурно: окно каждого перехода заканчивается ровно в своём стопе, последнее —
// ровно в sk_p6 (Q7.34: p6 — данные; p6 < 1 даёт плоский хвост цвета антиследа
// до антисоляра — семантика правила 5 валидатора). Порядок стопов обеспечивают
// панель (п. 13.4) и валидатор (глава 15); при неупорядоченных данных smoothstep
// с e0 > e1 даёт ступеньку — не аварию и не молчаливый баг. Шейдер — тупой исполнитель.
vec3 ramp_u(vec3 dir, vec3 sd) {
	// Q7.34 (COLORS6 v2, S15): «дыхание» купола — варп шкалы u. Закон v2 (29.10,
	// усиление ×1.5 по требованию заказчика): x = sk_breathe·sd.y (sd.y = sin
	// высоты солнца), γ = (1+x)/(1−0.5x). Эквивалент: сдвиг границ в видимом
	// (лог-)пространстве (1/γ−1) = 1.5·(1/γ₁−1), где γ₁ = 1+x — закон v1: границы
	// долей уезжают РОДНО в 1.5 раза дальше, без клампов и колен. Солнце ВЫШЕ
	// горизонта (γ>1): границы p_k → p_k^(1/γ) — солярные кольца (glow, горизонт,
	// ближние пояса) РАЗДУВАЮТСЯ за счёт дальних, хвост антисоляра сжимается.
	// НИЖЕ горизонта (γ<1) — обратное. На горизонте x=0 → γ=1 побитово: базовые
	// доли художника. γ ∈ [0.1/1.45, 1.9/0.55] = [0.069, 3.455] > 0 — pow безопасен
	// при любом sk_breathe∈[0,0.9] и любом направлении. Одна ручка силы на пресет,
	// знак даёт высота; u_ellip не тронут.
	float x = sk_breathe * sd.y;
	float g = (1.0 + x) / (1.0 - 0.5 * x);
	// Q7.34 (COLORS7, S17): компенсация складки у горизонта — ВТОРОЙ сомножитель
	// экспоненты (способ 1, согласован 29.10): ключ не солнце, а близость ВЗГЛЯДА
	// к горизонту h = 1 на горизонте → 0 к |dir.y| = 0.5; сила пропорциональна
	// стретчу эллипса: S — ТА ЖЕ формула, что в u_ellip (u_ellip не тронут; формула
	// продублирована 1:1, тождество проверяет selftest #14). γ_arc ≥ 1: у горизонта
	// солярные окна растягиваются дополнительно, антисолярные СЖИМАЮТСЯ именно там.
	// Экспоненты перемножаются: u^(g·γ_arc) — монотонно, новых складок не создаёт;
	// S=1 (эллипс выкл / солнце у зенита) или squeeze=0 → побитово вне.
	float S = mix(max(sk_arc_stretch, 1.0), 1.0, sstep(0.85, 0.99, abs(sd.y)));
	float h = 1.0 - sstep(0.10, 0.50, abs(dir.y));
	g *= 1.0 + sk_squeeze * (S - 1.0) * h;
	float u = pow(u_ellip(dir, sd), g);
	vec3 c = sk_glow_col;						// ядро зари (у солнца)
	c = mix(c, sk_horizon,   win(sk_p1, sk_p2, u));
	c = mix(c, sk_band_col,  win(sk_p2, sk_p3, u));
	c = mix(c, sk_band2_col, win(sk_p3, sk_p4, u));
	c = mix(c, sk_mid,       win(sk_p4, sk_p5, u));
	c = mix(c, sk_anti_col,  win(sk_p5, sk_p6, u));
	return c;
}

// P(dir) — ЕДИНАЯ угловая палитра состояния: см. sky_palette_disp НИЖЕ
// (Q7.34 COLORS5: перенесена за конверторы disp2scene/scene2disp — в шейдерном
// языке функция обязана быть объявлена до использования).

// Filmic (tonemap.glsl Godot 4.7) и ТОЧНАЯ аналитическая инверсия
// (квадратное уравнение рациональной кривой; clamp display к 1.32 — асимптота).
// Нужны для display-space композита небесных тел: багровое не уходит в бурое.
const float FA = 0.88;
const float FB = 0.60;
const float FCB = 0.06;
const float FDE = 0.002;
const float FDF = 0.06;
const float FEF = 0.03333333;
const float FN = 0.7285913529;

float filmic_raw(float x) {
	float c = max(x, 0.0);
	return ((c * (FA * c + FCB) + FDE) / (c * (FA * c + FB) + FDF)) - FEF;
}

float filmic(float x) {
	return filmic_raw(x) / FN;
}

float inv_filmic(float t) {
	float tt = min(t, 1.32);
	float Y = tt * FN + FEF;
	float a = FA * (1.0 - Y);
	float b = FCB - Y * FB;
	float c = FDE - Y * FDF;
	if (a <= 1e-6) {
		return 64.0;
	}
	float d2 = b * b - 4.0 * a * c;
	return max((-b + sqrt(max(d2, 0.0))) / (2.0 * a), 0.0);
}

vec3 filmic3(vec3 v) {
	return vec3(filmic(v.x), filmic(v.y), filmic(v.z));
}

vec3 inv_filmic3(vec3 v) {
	return vec3(inv_filmic(v.x), inv_filmic(v.y), inv_filmic(v.z));
}

// Q7.34 (S2): функции srgb_to_linear/srgb_to_linear3 УДАЛЕНЫ вместе с comp_linear —
// стали мёртвым кодом (единственным потребителем была удалённая экспериментальная цепь).
// Q7.34 (S5, баг 3.1): sRGB OETF и обратная — для dither СТРОГО в пространстве
// квантования: сетка байтов экрана равномерна именно в encoded-значениях (цепь A:
// байт = srgb_encode(disp)), поэтому ±0.5/255 там = ±0.5 байта экрана на любом тоне.
vec3 srgb_oetf3(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 srgb_oetf_inv3(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.0031308), c));
}

// Q7.34 (COLORS5): конверторы display-linear ↔ scene-linear для sk_tonemap.
// Filmic(0): display = filmic(scene), обратно — точная аналитическая инверсия (цепь A).
// Linear(1): движок не тонмаппит — display = scene (OETF sRGB делает сам движок).
// В обоих режимах байт экрана на стопах = hex палитры: sky() пишет
// COLOR = disp2scene(disp), движок возвращает disp 1:1.
vec3 disp2scene(vec3 d) {
	return sk_tonemap == 1 ? d : inv_filmic3(d);
}

vec3 scene2disp(vec3 x) {
	return sk_tonemap == 1 ? x : filmic3(x);
}

// P(dir) — ЕДИНАЯ угловая палитра состояния. Возвращает DISPLAY-LINEAR цвет.
// Q7.34 (COLORS5): рампа смешивается в КОДИРОВАННОМ пространстве (стопы = hex/255)
// и декодируется один раз — градиент равномерный на глаз (прежний mix в линейном
// свете + filmic давал «резкие» переходы). Ореол источника смешивается в scene-linear
// (вид Q7.33 сохранён: форма glow_exp общая, яркость glow_int — данные).
// Q7.33 (C.5, решение 9): множителя затемнения при низком солнце нет — яркость
// купола задаётся только данными стопов.
vec3 sky_palette_disp(vec3 dir) {
	vec3 sd = normalize(sk_sun_dir);
	vec3 disp;
	if (use_gradient_sky) {
		disp = srgb_oetf_inv3(ramp_u(dir, sd));	// encoded mix → display-linear
	} else {
		disp = scene2disp(sky_color);
	}
	float sp = clamp(dot(dir, sd), 0.0, 1.0);
	float w = clamp(pow(sp, sk_glow_exp) * sk_glow_int, 0.0, 1.0);
	return scene2disp(mix(disp2scene(disp), sk_halo_col, w));
}

// Солнце — аналитический диск с fwidth-AA (crisp-кромка на любом разрешении)
// + два ореола цветом sk_glow_col (C.3: sk_halo_col).
vec3 sun_celestial(vec3 dir, vec3 sd) {
	if (!sun_enabled) {
		return vec3(0.0);
	}
	// Q7.33 (C.4, решение 2): гейта по высоте НЕТ — солнце видимо всегда, в том числе
	// ниже горизонта. Ночью приглушается энергией света и sun_core_int в пресете (решение 11).
	float ang = acos(clamp(dot(dir, sd), -1.0, 1.0));
	float sunR = radians(max(sun_size_deg, 0.1));
	float edge = max(fwidth(ang) * 1.5, 0.0004);
	float disc = 1.0 - smoothstep(sunR - edge, sunR + edge, ang);
	float d = max(dot(dir, sd), 0.0);
	vec3 gdisp = scene2disp(sk_halo_col);	// цвет ореолов/стрика в display (COLORS5: режимозависимо; sk_halo_col — linear HDR)
	vec3 col = sun_disk_color * (disc * sun_core_int)
			+ gdisp * (pow(d, sun_g1_exp) * sun_g1_int)
			+ gdisp * (pow(d, sun_g2_exp) * sun_g2_int);
	// Стрик-глэйр v1: угловой анизотропный спрайт вокруг источника (горизонталь мира).
	if (streak_int > 0.0) {
		// Q7.34 (S7/S8, баги 3.2/3.4): базис ЭКРАННЫЙ (uniform sk_streak_right от
		// контроллера, покадрово): стрик всегда горизонтален на экране («рыбий глаз»
		// устранён) и не вырождается на зените/надире. Прежний
		// right_w = normalize(cross(worldY, sd)) давал normalize(0) = NaN при |sd.y|→1.
		// Фолбэки полюсно-безопасны: NaN невозможен ни в одной ветке.
		vec3 rr = sk_streak_right - sd * dot(sk_streak_right, sd);
		float lr = length(rr);
		vec3 right_w = (lr > 1e-5) ? rr / lr
				: ((abs(sd.y) > 0.99) ? vec3(1.0, 0.0, 0.0)
				: normalize(cross(vec3(0.0, 1.0, 0.0), sd)));
		vec3 up_w = cross(sd, right_w);
		vec3 to = dir - sd * dot(dir, sd);
		vec2 suv = vec2(dot(to, right_w) / radians(60.0), dot(to, up_w) / radians(6.0)) * 0.5 + 0.5;
		// ФИКС: стрик только вблизи источника (иначе suv сходится в центр спрайта на
		// антисоляре — блик лезет на противоположную сторону купола). C.3: границы в uniform'ы.
		float sgate = 1.0 - smoothstep(radians(sk_streak_gate_lo), radians(sk_streak_gate_hi), ang);
		if (suv.x > 0.0 && suv.x < 1.0 && suv.y > 0.0 && suv.y < 1.0) {
			col += gdisp * (texture(streak_tex, suv).r * streak_int * sgate);
		}
	}
	return col;
}

// Луна — диск + кратеры + ореол. Фаз нет: всегда полная (решение 10).
// Гашение задней полусферы — тем же механизмом, что у солнца: угловое расстояние.
// Диагноз исходного бага (п. 11.3): старая проекция на касательную плоскость
// length(p) одинакова для dir = md и dir = -md — «вторая луна» в антиподе.
// Новая реализация: сигнатура как sun_celestial(dir, sd), ранний выход по углу,
// crisp-кромка fwidth по углу, зеркальная карта кратеров ушла вместе с веткой.
vec3 moon_celestial(vec3 dir, vec3 md_in) {
	if (!moon_enabled) {
		return vec3(0.0);
	}
	vec3 md = normalize(md_in);
	float r = max(moon_size, 0.001);

	float ang = acos(clamp(dot(dir, md), -1.0, 1.0));
	float edge = max(fwidth(ang) * 1.5, 0.0004);
	if (ang > 2.5 * r + edge) {
		return vec3(0.0);						// задняя полусфера мертва
	}

	vec3 up0 = abs(md.y) > 0.99 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up0, md));
	vec3 up = cross(md, right);
	vec2 p = vec2(dot(dir, right), dot(dir, up));

	float body = 1.0 - smoothstep(-edge, edge, ang - r);	// crisp-кромка по углу

	float det = 1.0;
	if (moon_detail_int > 0.001) {
		vec2 muv = clamp(p / r * 0.5 + 0.5, vec2(0.0), vec2(1.0));
		det = mix(1.0, texture(moon_detail_tex, muv).r * 1.7, moon_detail_int);
	}

	float mdot = max(dot(dir, md), 0.0);
	// ореол — ЦВЕТОМ СОСТОЯНИЯ (mix к mid-поясу), а не белым: K0-индиго вместо белья
	// COLORS5: sk_mid — кодированные данные (hex/255) → srgb_oetf_inv3 = его display-linear
	// (в Filmic-режиме ТОТ ЖЕ вид, что прежде давал filmic3(sk_mid_linear)).
	vec3 mgcol = mix(moon_color, srgb_oetf_inv3(sk_mid), 0.55);
	return moon_color * (body * det)
		 + mgcol * (pow(mdot, moon_glow_exp) * moon_glow_int);
}

// Звёзды — два слоя hash-точек на угловой сетке с мягким ядром (стилизация);
// стабильны во времени (фон не мерцает), гаснут к горизонту и в ореоле луны.
float star_field(vec3 dir) {
	vec3 sp = dir * 90.0;
	vec3 f = fract(sp) - 0.5;
	float h = fract(sin(dot(floor(sp), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float s1 = step(0.992, h) * (1.0 - smoothstep(0.05, 0.35, length(f)));
	vec3 sp2 = dir * 160.0;
	vec3 f2 = fract(sp2) - 0.5;
	float h2 = fract(sin(dot(floor(sp2), vec3(37.719, 12.9898, 78.233))) * 43758.5453);
	float s2 = step(0.995, h2) * (1.0 - smoothstep(0.04, 0.25, length(f2))) * 0.6;
	return s1 + s2;
}

// Шесть различимых оттенков для sky_debug_mode = 2 (карта сегментов рампы).
const vec3 SEG_COLORS[6] = vec3[6](
	vec3(0.85, 0.25, 0.25), vec3(0.85, 0.65, 0.20), vec3(0.75, 0.80, 0.25),
	vec3(0.30, 0.75, 0.35), vec3(0.30, 0.55, 0.85), vec3(0.60, 0.35, 0.80));

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sd  = normalize(sk_sun_dir);
	vec3 md  = normalize(sk_moon_dir);

	if (sky_debug_mode > 0) {
		// return в sky() запрещён движком → структура ветвлением.
		float x = sk_breathe * sd.y;	// COLORS6 v2: тот же варп, что в ramp_u — карта честная
		float g = (1.0 + x) / (1.0 - 0.5 * x);
		float S = mix(max(sk_arc_stretch, 1.0), 1.0, sstep(0.85, 0.99, abs(sd.y)));	// COLORS7: как в ramp_u
		float h = 1.0 - sstep(0.10, 0.50, abs(dir.y));
		g *= 1.0 + sk_squeeze * (S - 1.0) * h;
		float u = pow(u_ellip(dir, sd), g);
		if (sky_debug_mode == 1) {
			COLOR = vec3(u);		// серая карта шкалы: 0 в соляре, 1 в антисоляре
		} else {
			int seg = u < sk_p1 ? 0 : (u < sk_p2 ? 1 : (u < sk_p3 ? 2 : (u < sk_p4 ? 3 : (u < sk_p5 ? 4 : 5))));
			COLOR = SEG_COLORS[seg];		// фактическая раскладка стопов
		}
	} else {
		// Q7.34 (COLORS5): композит в display-linear. Рампа (encoded mix) → disp;
		// HDR-добавки (солнце/луна/звёзды) — в scene-linear; обратно в display —
		// scene2disp; финальный disp2scene зеркалит движковый тонмапп (sk_tonemap):
		// Filmic → inv_filmic (движок вернёт filmic), Linear → как есть (движок не
		// тонмаппит). Байт экрана = srgb_encode(disp): на стопах = hex палитры
		// побайтово В ОБИХ режимах.
		vec3 disp = sky_palette_disp(dir);
		vec3 col = disp2scene(disp) + sun_celestial(dir, sd) + moon_celestial(dir, md);

		float horfade = smoothstep(-0.05, 0.15, dir.y);
		float mdamp = 1.0 - smoothstep(-0.02, 0.02, md.y) * pow(max(dot(dir, md), 0.0), 8.0) * 0.7;
		col += vec3(0.85, 0.90, 1.0) * (star_field(dir) * star_intensity * horfade * mdamp);

		disp = scene2disp(col);
		// Q7.34 (S5, баг 3.1): dither в байтовом пространстве: ±0.5/255 к sRGB-encoded
		// значению ДО квантования. hash(dir) детерминирован (без темпорального шума в
		// cubemap), амплитуда = половина кванта сетки — зерно невидимо, бандинг разбит.
		if (sk_dither > 0.5) {
			float n = fract(sin(dot(dir, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
			disp = srgb_oetf_inv3(srgb_oetf3(disp) + (n - 0.5) * (1.0 / 255.0));
		}
		COLOR = disp2scene(disp);
	}
}
