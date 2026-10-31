shader_type sky;
// ВЕРСИЯ: Q7.33 (единая сборка, 28.10.2026). Происхождение: Q7.32.PreOmega.SL
// (preomega_sky.gdshader, r11_s4_antisolar180_nohorline), перенесён в SkyEnvironment/.
//
// >>> НОРМАТИВНЫЙ ДОКУМЕНТ: ТЗ_небо_единая_сборка_Q7.33.md (глава 11).
// >>> Четыре сущности: СОЛЯР, ГРАДИЕНТ P(dir), АНТИСОЛЯР, ЛУНА. Зенит/надир —
// >>> НЕ сущности и своего цвета не имеют (SKY_CORE_SPEC §7).
//
// Вуаль: удалена в Q7.33 (решение 13), возвращена в Q7.34 (Sky3.2.7, шаг S10)
// ОТДЕЛЬНЫМ КОМПОНЕНТОМ SkyVeil.gdshaderinc под гейтом hc_enabled (дефолт false —
// кадр побитово равен безвуальному). Донор/архив — архив/veil/ и SKYHC-DS.txt.
//
// ИСТОРИЯ ГРАДИЕНТА (сохранена из r10_s4/r11_s4 — метрика не тронута, п. 11.1 ТЗ):
//   r11_s4 Ф1 «антисоляр стягивается к соляру»: dv = dot(w, upn), обе составляющие
//     из касательной плоскости в точке sd → u(-s) = 1 точно на любой высоте солнца;
//   r11_s4 Ф2 «эллипс вырождается»: hh = dh / S, S = mix(sk_arc_stretch, 1.0, gate)
//     → у полюса S = 1, u = угол/π, честный круг;
//   r10_s4: wedge/below/zen_w удалены как костыли (не возвращать — п. 19.7 ТЗ).

// ==== ВУАЛЬ (Sky3.2.7, S10; 4.1.3 этап 04): хост подключает модуль ============
// Компонентность (приказ 30.10): модуль вуали живёт ОТДЕЛЬНЫМ файлом
// SkyVeil.gdshaderinc (донор V4 DS + правки §3.2), подключается через #include.
// Композит — SCENE-LINEAR (согласовано заказчиком 30.10.2026), см. sky().
// 4.1.3 (этап 04, план света §4.4/v2 §3.2): контракт освещения вуали хоста
// (cloud_light_color/strength, cloud_ambient_sky_color/energy) УДАЛЁН —
// uniform'ы освещения объявляет сам модуль (hc_sun_*, hc_ambient_*,
// hc_palette_*) и событийно пишет CirrusVeilBinding из AtmosphereLightingState;
// направление света вуали = sk_sun_dir (H1 Sky3.2.14; геометрию пишет один
// SkyEnvironmentController — решение заказчика 30.10 п.5).

// Явный smoothstep (переносимость между бэкендами, A5).
float sstep(float lo, float hi, float x) {
	float t = clamp((x - lo) / (hi - lo), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// === Фон неба ===
uniform bool use_gradient_sky = true;			// выкл → плоский sky_color
uniform vec3 sky_color : source_color = vec3(0.32, 0.47, 0.68);	// плоское небо (use_gradient_sky=false)

// ==== ПАЛИТРА ГРАДИЕНТА: соляр → антисоляр, стопы = данные состояния ====
// Q7.34 (Sky3.2.4, ТЗ заказчика + palletes.html): рампа из 4 стопов sk_c1…sk_c4.
// Нумерация ДОСЛОВНО повторяет шаги HTML: «Шаг 1 (верх)» … «Шаг 4 (низ/горизонт)».
// Рампа индексируется u ОТ солнца (0 = соляр, 1 = антисоляр), поэтому у солнца
// лежит sk_c4 (яркий горизонт), в антисоляре — sk_c1 (тёмный зенит): порядок
// обратный HTML-штрихам, цвета — те же. Дефолты = ref #2 «Солнце над облаками».
// COLORS5: display-данные (hex/255, encoded sRGB 0..1).
uniform vec3 sk_c1 : source_color = vec3(0.0157, 0.0627, 0.1333);	// шаг 1 (верх) — зенит/антисоляр, самый тёмный
uniform vec3 sk_c2 : source_color = vec3(0.1686, 0.4588, 0.7098);	// шаг 2
uniform vec3 sk_c3 : source_color = vec3(0.5490, 0.7686, 0.9098);	// шаг 3
uniform vec3 sk_c4 : source_color = vec3(1.0, 0.9529, 0.8392);	// шаг 4 (низ/горизонт) — ядро у солнца, самый светлый
uniform float sk_glow_int : hint_range(0.0, 4.0) = 0.30;
uniform float sk_glow_exp : hint_range(1.0, 128.0) = 6.0;
uniform vec3 sk_sun_dir = vec3(0.0, 0.0, -1.0);	// направление НА солнце (мировое; конвенция basis.z DirectionalLight3D)
uniform vec3 sk_moon_dir = vec3(0.0, 0.766, 0.643);	// НА луну (мировое; независима от солнца; дефолт elev 50° azim 0°)
// 4.1.6 (запрос заказчика 31.10; решение Q7.33 C.3 п.11.7 ОБ ОТСРОЧЕНИИ
// независимого цвета ореола ОТМЕНЕНО заказчиком): отдельного цвета ореола
// НЕТ — он выводится из СОЛЯРНОГО стопа рампы sk_c4 («шаг 4 — у солнца»),
// никакой второй копии цветовых данных вне рампы не существует (v2 §2.2:
// независимые цветовые поправки запрещены). HDR-яркость — gain (правило S3:
// linear(glow)×1.4; gain — данные, живая ручка вкладки «Градиент»).
uniform float sk_halo_hdr_gain : hint_range(0.0, 4.0) = 1.4;
// === ГРАДИЕНТ КУПОЛА: ЕДИНАЯ МОДЕЛЬ НА ВСЕ КЛЮЧИ ===
// Купол = ОДНА четырёхстопная рампа по угловому удалению от солнца u (u_ellip),
// 0 = направление на солнце, 1 = антисоляр. Между ключами различаются ТОЛЬКО
// ДАННЫЕ. ЛЕСТНИЦА СТОПОВ (порядок от солнца к антисоляру; Sky3.2.4):
//   u < q1        sk_c4   шаг 4 (низ/горизонт): ядро у солнца
//   q1 .. q2      sk_c3   шаг 3: пояс 1
//   q2 .. q3      sk_c2   шаг 2: пояс 2
//   q3 .. q4      sk_c1   шаг 1 (верх): зенит/антисоляр, самая тёмная область
// Q7.34 (COLORS5): данные стопов — КОДИРОВАННЫЙ display (palette hex/255, 0..1).
// get_sky_gradient смешивает их В КОДИРОВАННОМ ПРОСТРАНСТВЕ (равномерный плавный
// градиент, как CSS; прежний mix в линейном свете давал «резкий» переход: большая
// часть угла тонула вблизи тёмного стопа). Декодирование — один раз в sky_palette_disp.
// 4.1.7 (инструкция заказчика): рампа ЦЕЛИКОМ данные — ноль констант-позиций в
// шейдере. Доли четырёх цветов (сумма нормируется здесь же) — данные владельца
// SkyGradientWeightsComponent; прежние sk_q1..sk_q4/sk_sharp (окна win, прижатые
// к стопам) УДАЛЕНЫ вместе со старым способом правки долей.
uniform vec4 sky_color_weights = vec4(0.25);	// доли цветов ОТ СОЛНЦА: x=sk_c4, y=sk_c3, z=sk_c2, w=sk_c1
uniform float sky_transition_width : hint_range(0.0, 0.2) = 0.025;	// мягкость перехода (в координатах градиента); глобальный параметр сцены
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
uniform int sky_debug_mode : hint_range(0, 6) = 0;	// 0 = небо, 1 = u, 2 = сегменты, 3–6 = чистые стопы sk_c4..sk_c1 (диагностика цепи, 4.1.8 временно)
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
// Q7.34.PreOmega_Sky3.2.2 (вариант Б-мир, выбор заказчика): базис стрика МИРОВОЙ,
// камера не участвует — прежний uniform sk_streak_right (right камеры, запись
// каждый кадр) удалён вместе с покадровой записью: по документации движка любое
// изменение uniform инвалидирует radiance cubemap, и при стрике она не добиралась
// никогда. Наклон полосы больше не зависит от поворота камеры (баг «стрик меняет
// наклон при повороте камеры»).
// Полууглы бокса спрайта — ДАННЫЕ (прежние литералы radians(60)/radians(6)
// нарушали решение 3 ТЗ «ноль констант» и не совпадали с аспектом текстуры
// streak_glare.png 1774×887 = 2:1 → изображение тянулось по горизонтали в 5 раз).
// Дефолт держит аспект: tan(45°)/tan(26.6°) = 2.0 = аспект текстуры.
uniform float sk_streak_half_w_deg : hint_range(1.0, 80.0) = 45.0;
uniform float sk_streak_half_h_deg : hint_range(1.0, 80.0) = 26.6;
uniform sampler2D moon_detail_tex : filter_linear;	// grayscale-карта кратеров
uniform float moon_detail_int = 0.5;		// доля детали (кратеры)

// Sky3.2.14 (H1): include ПОСЛЕ всех uniform'ов хоста — модуль ссылается на
// sk_sun_dir (направление света вуали = геометрия солнца), объявленный выше.
#include "res://SkyEnvironment/SkyVeil.gdshaderinc"

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

// 4.1.7 (инструкция заказчика): мягкое смешение четырёх цветов по ДОЛЯМ.
// t — координата существующего градиента (ramp_u; формула координаты не менялась).
// sky_color_weights — доли цветовых ОБЛАСТЕЙ (не цвета); цвета и их порядок —
// данные шейдера/пресетов sk_c4→sk_c1 (от солнца; НОВЫХ цветовых uniform нет:
// данные пресетов едины, байт-точность palletes.html и вывод ореола из sk_c4
// сохранены). Смешение — в кодированном пространстве (COLORS5). Защита от
// нулевых ширин: f ≥ 0.0005 — smoothstep никогда не получает e0 == e1;
// f ≤ 0.45·min(доля соседей) — переходы не пересекаются, плато цвета достижимы
// побайтово (центр сегмента всегда чист: 0.45 < 0.5).
vec3 get_sky_gradient(float t) {
	vec4 w = max(sky_color_weights, vec4(0.0));
	w /= max(w.x + w.y + w.z + w.w, 0.0001);

	float b1 = w.x;
	float b2 = w.x + w.y;
	float b3 = w.x + w.y + w.z;

	float f1 = max(0.0005, min(sky_transition_width, 0.45 * min(w.x, w.y)));
	float f2 = max(0.0005, min(sky_transition_width, 0.45 * min(w.y, w.z)));
	float f3 = max(0.0005, min(sky_transition_width, 0.45 * min(w.z, w.w)));

	float blend1 = smoothstep(b1 - f1, b1 + f1, t);
	float blend2 = smoothstep(b2 - f2, b2 + f2, t);
	float blend3 = smoothstep(b3 - f3, b3 + f3, t);

	vec3 color = mix(sk_c4, sk_c3, blend1);
	color = mix(color, sk_c2, blend2);
	color = mix(color, sk_c1, blend3);

	return color;
}

// Координата градиента u (лестница долей — см. uniform'ы и get_sky_gradient).
// Формула координаты t НЕ изменена (инструкция заказчика 4.1.7 п.3): эллипс,
// «дыхание» (COLORS6) и компенсация складки (COLORS7) — как были.
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
	return get_sky_gradient(u);
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

// 4.1.6: цвет ореола/стрика — scene-linear HDR, ВЫВОДИТСЯ из солярного стопа
// рампы: encoded display-данные sk_c4 → display-linear → scene-linear → ×gain.
// При sk_tonemap=1 (Linear) disp2scene тождественна: цвет = linear(стоп)×gain —
// правило S3 дословно; под Filmic ореол проходит ту же цепь, что купол.
vec3 sk_halo_scene() {
	return disp2scene(srgb_oetf_inv3(sk_c4)) * sk_halo_hdr_gain;
}

// P(dir) — ЕДИНАЯ угловая палитра состояния. Возвращает DISPLAY-LINEAR цвет.
// Q7.34 (COLORS5): рампа смешивается в КОДИРОВАННОМ пространстве (стопы = hex/255)
// и декодируется один раз — градиент равномерный на глаз (прежний mix в линейном
// свете + filmic давал «резкие» переходы). Ореол источника смешивается в scene-linear
// (форма glow_exp общая, яркость glow_int — данные); цвет ореола — выведенный
// sk_halo_scene() из солярного стопа (4.1.6), независимых данных цвета нет.
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
	return scene2disp(mix(disp2scene(disp), sk_halo_scene(), w));
}

// Солнце — аналитический диск с fwidth-AA (crisp-кромка на любом разрешении)
// + два ореола выведенным цветом солярного стопа (C.3; 4.1.6).
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
	vec3 gdisp = scene2disp(sk_halo_scene());	// цвет ореолов/стрика в display (выведен из sk_c4, 4.1.6)
	vec3 col = sun_disk_color * (disc * sun_core_int)
			+ gdisp * (pow(d, sun_g1_exp) * sun_g1_int)
			+ gdisp * (pow(d, sun_g2_exp) * sun_g2_int);
	// Стрик-глэйр v2: угловой анизотропный спрайт вокруг источника.
	if (streak_int > 0.0) {
		// БАЗИС МИРОВОЙ (Б-мир): right_w = горизонт мира, перпендикулярный плоскости
		// солнце-зенит. up0 переключается у полюса, как в u_ellip; длина кросса
		// вырождается только при точном совпадении up0 и sd, чего переключение не
		// допускает, — guard на длину всё равно стоит (стандарт проекта: NaN ни в
		// одной ветке). Полоса параллельна горизонту мира при любой камере.
		vec3 up0 = abs(sd.y) > 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
		vec3 rw = cross(up0, sd);
		float lr = length(rw);
		vec3 right_w = (lr > 1e-6) ? rw / lr : vec3(1.0, 0.0, 0.0);
		vec3 up_w = cross(sd, right_w);
		// РАЗВЁРТКА ГНОМОНИЧЕСКАЯ (перспективно верная): t = dir/cosθ − sd даёт
		// tanθ·(cosφ, sinφ). Прежняя хорда (sinθ, делённая на фиксированный угол)
		// ошибалась вдвое на 60° и не ограничивала спрайт по горизонтали вовсе
		// (sinθ ≤ 1 < radians(60)) — картинка размазывалась на всю полусферу.
		vec3 t = dir / max(dot(dir, sd), 1e-4) - sd;
		vec2 suv = vec2(dot(t, right_w) / tan(radians(max(sk_streak_half_w_deg, 1.0))),
				dot(t, up_w) / tan(radians(max(sk_streak_half_h_deg, 1.0)))) * 0.5 + 0.5;
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
	// COLORS5: sk_c2 — кодированные данные (hex/255) → srgb_oetf_inv3 = его display-linear
	// (Sky3.2.4: прежний sk_mid средней полосы рампы = её шаг 2).
	vec3 mgcol = mix(moon_color, srgb_oetf_inv3(sk_c2), 0.55);
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

// Четыре различимых оттенка для sky_debug_mode = 2 (карта сегментов рампы).
const vec3 SEG_COLORS[4] = vec3[4](
	vec3(0.85, 0.25, 0.25), vec3(0.85, 0.65, 0.20), vec3(0.30, 0.75, 0.35), vec3(0.30, 0.55, 0.85));

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
		} else if (sky_debug_mode >= 3) {
			// 4.1.8 ВРЕМЕННО (диагностический тест по запросу заказчика 31.10, п.3):
			// чистый стоп через ВЫХОДНУЮ цепь, в обход рампы/вуали/светил — тот же
			// путь, каким плато стопа достигает экрана. Байт экрана ОБЯЗАН совпасть
			// с hex палитры побайтово (tonemap Filmic, exposure 0): любое отклонение
			// здесь = дефект выходной цепи харнесса (тонмап/экспозиция/семплинг),
			// а не рампы. 3 = sk_c4 (соляр), 4 = sk_c3, 5 = sk_c2, 6 = sk_c1.
			// (имён sky_color_* нет с 3.2.4: стопы = sk_c1..sk_c4, данные пресетов)
			vec3 stop = sk_c4;
			if (sky_debug_mode == 4) { stop = sk_c3; }
			else if (sky_debug_mode == 5) { stop = sk_c2; }
			else if (sky_debug_mode == 6) { stop = sk_c1; }
			COLOR = disp2scene(srgb_oetf_inv3(stop));
		} else {
			vec4 wd = max(sky_color_weights, vec4(0.0));	// 4.1.7: сегменты — кумулятивные доли
			wd /= max(wd.x + wd.y + wd.z + wd.w, 0.0001);
			int seg = u < wd.x ? 0 : (u < wd.x + wd.y ? 1 : (u < wd.x + wd.y + wd.z ? 2 : 3));
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

		// ВУАЛЬ (Sky3.2.7, S10): scene-linear композит СТРОГО ДО тонмапа (ВУАЛЬ_план §3,
		// подтверждено заказчиком 30.10). Премноженный композит DS: вуаль затеняет и купол,
		// и солнце/луну/звёзды (приёмка S12 «диск ослабляется»). Гейт hc_enabled=false:
		// вызова нет — ноль выборок текстуры, кадр побитово прежний (приёмка S10/S11).
		float va = 0.0;
		float vd = 0.0;
		float vt = 0.0;
		if (hc_enabled) {
			col = DS_veil_composite(col, dir, va, vd, vt);
		}
		if (hc_enabled && hc_debug > 0.5) {
			COLOR = DS_veil_debug_color(hc_debug, va, vd, vt);
		} else {
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
}
