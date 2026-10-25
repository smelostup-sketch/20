shader_type sky;
// skylab_clouds.gdshader — Q7.32.PreOmega.SL (небо-лайт), шаг 1 наведения порядка (2026-10-25).
// Происхождение: RENGAR PROTOTYPE OMEGA, компонент Q7.32_SKYprav_3.1, Q732_SKY_v0.5.3.
//
// СОСТАВ (оставлено по указанию заказчика — «только вуаль, градиент неба и освещение»):
//   1. ГРАДИЕНТ НЕБА + ОСВЕЩЕНИЕ КУПОЛА — модель двух полюсов v0.5.1/v0.5.2, палитра M1:
//      самая тёмная точка купола = истинный антисоляр, зенит = средняя точка полюсов,
//      доля светлого купола растёт с высотой солнца (ТЗ — CHANGELOG_STEP.md);
//      видимое солнце: диск + гало (C2).
//   2. ВУАЛЬ HighCloudLayer (этапы SKYHC-1..4, uniform'ы hc_*) — протяжённый слой
//      высокой облачности: один сэмпл плотности плиты + Beer-Lambert + curtain,
//      освещение hc_lit_color (SKYHC-4, те же источники света, что и купол).
//   КОМПОЗИТ (формула v0.5.3 без изменений): base = (bg + sunbg)·(1 − hc_a) + hc_rgb;
//   при выключенной вуали кадр побитово равен v0.5.3 с выключенными кучевыми.
//
// УДАЛЕНО (упаковано в _PACKED/Q7.32.PreOmega.CUMULUS/; полный оригинал v0.5.3 там же —
// skylab_clouds_v0.5.3_FULL.gdshader.orig):
//   - кучевые (реймарчинг): марш A3-A5, плотность cloud_density B1/B2 + PRAV-1.1..3.1,
//     weather-маска C4, анизотропия/warp C5, distance curtain C7, самозатенение/powder/
//     MS/HG B3-B4/C5a-b, atmo-перспектива B4, высотный профиль A7, subpass-тиры B6
//     (SKY_TIER, render_mode use_half/quarter_res_pass, AT_*_PASS, HALF/QUARTER_RES_COLOR),
//     диагностика cloud_debug_mode 0-12 (debug_hit_color/debug_distance_scale);
//   - ColorRamp-освещение облаков D3/SKYLAB шаг 5-6: sk_ramp0-4, sk_rim_*, sk_alpha_*,
//     sk_amb_w, sk_ramp_gamma, sk_ramp_white; размытое солнце за облаком use_sun_blur/
//     sun_blur_*; 5-стоповый градиент неба C8: sky_horizon/zenith/antisolar_color,
//     sky_band_*, sky_grad_sharp (+ sharp_mix);
//   - мёртвые uniform'ы: sk_anti_int, sk_grad_pow — в коде v0.5.2+ не использовались
//     (антисолярное ядро задают sk_anti_p_lo/hi и mix anti_c; крутизна — внутри модели);
//   - гейт кучевых sk_clouds_on (некого гейтить).
// ПРАВКА СИГНАТУРЫ: sky_gradient(vec3 dir, vec3 sundir) → sky_gradient(vec3 dir):
//   второй параметр моделью двух полюсов НЕ читался (направление — из sk_sun_dir),
//   это остаток сигнатуры C8. Вызовы обновлены (sky(), hc_lit_color()).
// ИСТОРИЧЕСКИЕ КОММЕНТАРИИ сохранённых блоков (ссылки на CPU-зеркала CloudsTestBench,
//   кучевые, C7/D3-конвенции) оставлены как есть — стенд упакован в
//   _PACKED/Q7.32.PreOmega.BENCH/, кучевые — в _PACKED/Q7.32.PreOmega.CUMULUS/.
//
// ТЕКСТУРЫ ВУАЛИ: noise_pw (Perlin-Worley 128³) и noise_worley (Worley 32³) — сырые
//   .bin рядом с шейдером; в материал пишутся ОДИН РАЗ в рантайме (VeilSkyRig.gd +
//   CloudTextureLoader.gd): персистенция ImageTexture3D через ResourceSaver в Godot 4.7
//   сломана (спайк B1). Ветер/дрейф — hc_offset с CPU (TIME в шейдере не используется).
//
// Ниже — оригинальная документация модуля вуали (ЭТАПЫ SKYHC-1..4 из v0.5.3, дословно):

// ЭТАП SKYHC-1: ОТДЕЛЬНЫЙ СЛОЙ ПРОТЯЖЁННОЙ ОБЛАЧНОСТИ HighCloudLayer («вуаль»).
//   Широкие вытянутые неоднородные образования ВЫШЕ кучевых (плита hc_layer_bottom..
//   hc_layer_top против 1500..3500 у кучевых): связывают отдельные кучи, дают небу
//   масштаб и глубину. Это НЕ второй слой кучевых (своего марша, теневых лучей,
//   powder/MS нет) и НЕ равномерный туман (крупномасштабное поле разрывов + вытянутость
//   + порог с мягким окном). Модель этапа 1 — один сэмпл плотности в середине плиты
//   + Beer-Lambert по длине пути в плите (у зенита тоньше, к горизонту плотнее) +
//   curtain по длине пути (чистый горизонт, как C7 у кучевых). Цвет — один uniform
//   hc_color (освещение и сутки — этап SKYHC-4). Новые текстуры НЕ добавлены: обе
//   выборки из существующей noise_pw на разных периодах.
//   КООРДИНАТЫ: только направление луча EYEDIR (SCREEN_UV/SKY_COORDS не используются,
//   вручную вслед за камерой рисунок не перемещается). hc_use_world_anchor=true →
//   плита в МИРОВЫХ высотах, начало отсчёта POSITION (позиция камеры): при переносе
//   камеры рисунок стоит на месте (честный параллакс). Цена (выбор заказчика, документирован):
//   по докам Godot чтение POSITION форсирует обновление radiance cubemap при движении
//   камеры; Sky.process_mode=INCREMENTAL растягивает его по кадрам. Если замер фазы 6
//   покажет цену высокой — вариант: compile-time #define (как SKY_TIER) вместо uniform.
//   ГЕЙТ ИДЕНТИЧНОСТИ: hc_enabled=false (дефолт ШЕЙДЕРА) → ветка не выполняется,
//   hc_a=0/hc_rgb=0 → base = bg + sunbg → кадр ПОБИТОВО равен Q7.32_SKY_D3.
//   КОМПОЗИТ (порядок по глубине): небо+солнце → ВУАЛЬ (дальше) → кучевые (ближе,
//   закрывают вуаль своим alpha). Диск солнца вуаль ослабляет честно (через тот же mix).
//   ДИАГНОСТИКА: hc_debug 0/1/2/3 = выкл/плотность/альфа/оптическая толщина (без марша
//   кучевых — честный пропуск, как у режимов 8-12). CPU-зеркало: CloudsTestBench.compute_hc_layer().
// ЭТАП SKYHC-2 (фаза 2 ТЗ): КООРДИНАТЫ И СТАБИЛЬНОСТЬ РИСУНКА — ПРОВЕРЕНО, состав и
//   код модуля вуали НЕ изменены (ни новых uniform'ов, ни новых вычислений). Выводы:
//   (1) EYEDIR — МИРОВОЕ направление пикселя (док-пример texture(RADIANCE, EYEDIR) и
//       штатный ProceduralSky: dot(LIGHT0_DIRECTION, EYEDIR) — LIGHT0_DIRECTION мировой);
//       POSITION — «Camera position, in world space» (docs, Sky built-ins). Рисунок —
//       функция только (мировой луч, позиция камеры): повороты камеры его НЕ меняют;
//   (2) перенос камеры эквивариантен: p_mid(O+Δ) = p_mid(O) + Δ − dir·(Δ.y/dir.y);
//       срединная плоскость плиты МИРОВАЯ (p_mid.y ≡ (bottom+top)/2), путь
//       path = (top−bottom)/dir.y от высоты камеры не зависит (подъём камеры меняет
//       только горизонтальное положение точки выборки, не оптическую толщину);
//   (3) параллакс оболочки оценён и ограничен геометрией: угловой сдвиг особенностей
//       ≤ asin(|Δ|/(L−|Δ|)), L ≥ 6.6 км → перепад арены 50 м даёт ≤ ~0.5° (дальняя
//       плита, «плавания» рисунка нет); guards: |dir.y| ≤ 1e-6 — нет пересечения,
//       path > curtain_end (~4.9° над горизонтом) — α точно 0, HC_MAX_DIST ограничивает
//       точку выборки у горизонта; зенит без полярного шва (азимутальная развёртка
//       непрерывна, сдвиг точки выборки ~1 м);
//   (4) швов нет: PW-текстура периодична (perlin_tile mod cells, Worley периодический,
//       box_blur_wrap), sample_tex (fposmod) и GPU repeat_enable заворачивают непрерывно;
//       мировые периоды рисунка (T⁻¹ от периода текстуры, T — hc_sample_coord) ≈ сотни
//       км — дрейф/перенос пересекает их без скачка (density инвариантна к offset+Δo);
//   (5) SCREEN_UV/SKY_COORDS/TIME в модуле отсутствуют (HC1-10, HC2-10/12), вуаль
//       считается только в full-res/cubemap-ветках (контракт subpass B6 не изменён).
//   Инструменты фазы 2 на стенде: WASD/QE — перенос камеры, T — тур (yaw 360° →
//   качание pitch → дрейф позиции; ветер на время тура замораживается), J/K — эталон
//   позиции камеры и отчёт стабильности (Δd/Δα/параллакс по фиксированному набору лучей).
// ЭТАП SKYHC-3.1 (фаза 3 ТЗ, шаг 1): КРУПНЫЙ РИСУНОК И МАСШТАБ — код модуля вуали НЕ
//   изменён (0 новых uniform'ов, дефолты прежние: 60k/3.5/260k). Диапазоны ручек
//   масштаба подтверждены/откалиброваны развёртками hc_pattern_stats (окно ±60 км,
//   детерминированные сетки): scale 20-200 км — «ok» (рябь ниже ~8 км, пятно выше
//   ~300 км), stretch 0.5-6 — отклик along/across ≈ 0.8·stretch без поперечной ряби,
//   field/scale ≥ 1.5 — иначе пелена (σ→0.09; взаимодействие задокументировано в меню).
//   Анализ и пресеты A/B живут в стенде: hc_pattern_stats/hc_degeneracy (классы
//   ripple/blob/veil/ok), HC_SCALE_PRESETS (36/60/110/150 км) + строка меню «Масштаб A/B».
// ЭТАП SKYHC-3.2 (фаза 3 ТЗ, шаг 2): РАЗРЫВЫ И НЕОДНОРОДНОСТЬ + АУДИТ РУЧЕК — код
//   модуля вуали по-прежнему НЕ изменён (0 новых uniform'ов, дефолты прежние:
//   coverage 0.56 / softness 0.22 / field_amp 0.60; формула cov_eff заморожена).
//   Развёртки данных (стенд + сьют): coverage — ручка количества (clear 0.03→0.78 на
//   0.05→0.90; ≤0.20 риск «пятна», ≥0.80 почти пусто — задокументировано подсказкой);
//   softness — ручка мягкости (mid 0.04→0.83 на 0.01→0.60, геометрия 0.5-уровня стоит;
//   ниже 0.10 контуры жёсткие: Δd/250 м → 1.0 — подсказка рекомендует ≥ 0.10);
//   field_amp — ручка неоднородности (σ 0.12→0.39; amp↑ уводит эффективный порог вниз
//   (среднее PW-поля ≈ 0.29 ≠ 0.5) — компенсируется coverage, подсказка обновлена).
//   АУДИТ НЕЗАВИСИМОСТИ (ТЗ: «не добавлять множество параметров… одного эффекта»):
//   7 ручек × 9 наблюдаемых (включая block_std — пространственную неоднородность по
//   блокам 30 км); у каждой ручки есть «собственный» эффект с запасом ≥ 2×: softness —
//   mid_frac, stretch — анизотропия, scale — чистая геометрия, field_scale — block_std
//   и укорочение гряд, coverage — чистое количество (purity), field_amp — контраст
//   (spread), tau_per_km — оптика при замороженном рисунке (Δdensity ≡ 0). Пара
//   field_amp×coverage коллинеарна в агрегатах (|cos| ≈ 0.95, встречные знаки) —
//   НЕ дубликаты: различимы purity/spread; связь задокументирована подсказками меню.
//   Инструменты стенда: HC_CHAR_PRESETS + строка «Характер A/B (пресеты)» (Плотная
//   вуаль/Базовый/Острова и окна/Редкие гряды — лестница clear 0.17→0.46, все «ok»),
//   hc_alpha_response/hc_observables/hc_knob_signature/hc_signature_cos/hc_preset_to_hp.
// ЭТАП SKYHC-3.3 (фаза 3 ТЗ, шаг 3): МЕЛКАЯ ДЕТАЛИЗАЦИЯ — последний параметр фазы 3
//   («интенсивность мелкой детализации»): +2 uniform'а (hc_detail_strength 0-1, дефолт
//   ШЕЙДЕРА 0 = побитово 3.2; материал задаёт 0.35; hc_detail_scale 800-8000 м, дефолт
//   3000). Worley-бугорки (существующая noise_worley 32³, новых текстур нет) модулируют
//   ПОРОГ внутри полосы перехода (треугольный вес 1−|shape−cov|/soft): interior/exterior
//   образований не тронуты — фактура появляется только на кромках, вуаль не превращается
//   в дым. Конвенция кучевых B1/B2 (str·(detail−0.5), среднее Worley ≈0.35 — лёгкий
//   уклон эрозии). Координата детали q0 = p + hc_offset — БЕЗ поворота/сжатия гряд
//   (бугорки изотропны, stretch деталь не затрагивает — аудит 3.2 в силе); дрейф — тот
//   же hc_offset. Цена: +1 texture(noise_worley) на пиксель ТОЛЬКО при strength > 0
//   (uniform-гейт, в off — 0); циклов/марша нет. Алиасинг: воксел 94 м (3000/32) на
//   6.6 км ≈ 15 px (1080p) — запас; нижняя граница меню 800 м задокументирована.
//   Domain-warp ОСОЗНАННО не добавлен: для вуали на этом этапе польза неизмерима, а цена
//   — ещё одна выборка и две ручки (ТЗ: не умножать параметры); вопрос к фазе 6/7.
// ЭТАП SKYHC-4 (фаза 4 ТЗ): ОСВЕЩЕНИЕ И ВРЕМЯ СУТОК — +3 uniform'а (hc_use_lighting,
//   дефолт ШЕЙДЕРА false = побитово 3.3, материал задаёт true; hc_light_gain и
//   hc_ambient_gain — независимые доли прямого света и заливки). Модель hc_lit_color():
//   прямой свет = cloud_light_color·strength × рампа C9 (use_sun_color_ramp/ramp_near/
//   ramp_far по cosθ — та же формула, что у кучевых) × мягкий терминатор
//   shade ∈ [0.60, 1] (константы окна −0.35/0.55 — статус guard'ов); заливка =
//   amb_top C9 (use_ambient_from_sky → G(up)·ambient_sky_gain или sky_color, иначе
//   cloud_ambient_sky_color) × cloud_ambient_energy; всё × альбедо hc_color (роль
//   cloud_color у кучевых). Марша теней/powder/MS/HG НЕТ (ТЗ п.3: без имитации контраста
//   объёмного облака). ВТОРОГО ЦИКЛА СУТОК НЕТ (ТЗ п.6): закат/сумерки/ночь приходят из
//   тех же uniform'ов, которые пишут пресеты F10-F14/TimeOfDayController для всего неба;
//   анти-пинк ночь (ТЗ п.5) обеспечена источником данных (night: light_color холодно-
//   синий, strength 0.5, sky-градиент тёмный) и проверена сьютом (HC4-6/7).

// ЭТАП SKYHC-5 (интеграция вуали с кучевыми, 11 проверок: вклад вуали не зависит от
//   формы композита, слои побитово независимы) — верифицирован на v0.5.3; кучевые
//   упакованы, проверка снята с повестки. История этапов кучевых (PRAV-1.1..3.1,
//   D1-D3, C1-C9, B1-B6, A3-A7) — в комментариях упакованного оригинала
//   (_PACKED/Q7.32.PreOmega.CUMULUS/skylab_clouds_v0.5.3_FULL.gdshader.orig).

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

// ГРАДИЕНТ НЕБА G(dir) — МОДЕЛЬ ДВУХ ПОЛЮСОВ v0.5.1/v0.5.2 (ТЗ заказчика,
// CHANGELOG_STEP.md): полюс 1 = направление источника (светлый), полюс 2 = истинная
// антисолярная точка (самая тёмная), зенит = средняя точка между полюсами (НЕ тёмная);
// добавочный свет вдоль горизонта спадает с угловым удалением от источника (wedge);
// ниже горизонта — затемнение к тени состояния; купол темнеет при низком солнце;
// доля светлого купола = фиксированная функция высоты солнца (v0.5.2, самотест R8).
// Палитра M1 (sk_*), пре-адаптирована под Filmic (skylab_palette_tool, упакован).
// Порядок темноты (самотест R7, elev 0): антисоляр < зенит < солнечный горизонт.
// Сигнатура v0.5.3 имела неиспользуемый второй параметр (sundir) — остаток C8; убран.
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
	base = mix(base, sk_below_col, smoothstep(0.0, -0.18, h) * sk_below_int);
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

// Численный предел дистанции выборки (guard: у горизонта t → ∞, и координата текстуры
// теряет точность float32; curtain к этой дистанции уже гасит слой, поэтому guard
// не влияет на картинку). Документирован как константа, не uniform (не художественный параметр).
const float HC_MAX_DIST = 60000.0;

// SKYHC: координата выборки — поворот в XZ на hc_stretch_angle_deg, сжатие вдоль оси
// гряд (вытянутость) и обратный поворот; Y проходит как есть (плита тонкая → 3D-текстура
// даёт почти плоский срез, что для вуали и нужно). Смещение hc_offset — дрейф с CPU.
// CPU-зеркало: CloudsTestBench.hc_sample_coord().
vec3 hc_sample_coord(vec3 p) {
	vec3 q = p + hc_offset;
	float a = radians(hc_stretch_angle_deg);
	float ca = cos(a);
	float sa = sin(a);
	vec2 r = vec2(q.x * ca + q.z * sa, -q.x * sa + q.z * ca);	// поворот на −a
	r.x /= max(hc_stretch, 0.05);								// сжатие вдоль оси гряд
	return vec3(r.x * ca - r.y * sa, q.y, r.x * sa + r.y * ca);	// поворот на +a
}

// SKYHC: плотность вуали [0,1]. Крупный рисунок — PW на периоде hc_scale; поле разрывов —
// ТА же PW на периоде hc_field_scale, модулирует порог: ниже 0.5 — плотнее, выше — разрывы
// (области разной плотности, слой не выглядит равномерной полосой). Переход плавный
// (окно ±hc_softness), резких контуров нет. Обе выборки — из существующей noise_pw.
// SKYHC-3.3: мелкая деталь — Worley-бугорки модулируют ПОРОГ (конвенция кучевых B1/B2:
// str·(detail−0.5), центр 0.5 — среднее Worley F1 ≈0.35 даёт лёгкий уклон «эрозии», как
// у кучевых) и только внутри полосы перехода: треугольный вес 1−|shape−cov|/soft равен 0
// вне окна — interior/exterior образований не тронуты (деталь не превращает вуаль в дым).
// Координата детали — q0 = p + hc_offset (БЕЗ поворота/сжатия гряд: бугорки изотропны,
// как у кучевых, и ручка stretch деталь не затрагивает — аудит 3.2 остаётся в силе).
// Амплитуда сдвига порога = hc_detail_strength·soft (не выходит за окно). Дрейфует деталь
// с тем же hc_offset. ГЕЙТ: strength=0 → uniform-ветка не выполняется, выборки Worley
// нет, n = shape → плотность ПОБИТОВО равна SKYHC-3.2 (стоимость off = 0).
// CPU-зеркало: CloudsTestBench.compute_hc_density().
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

// SKYHC-4: константы модели освещения (статус как у HC_MAX_DIST — не художественные
// параметры): окно мягкого терминатора и его пол. Отношение яркости далеко/близко к
// солнцу = 0.60 : 1.00 — cue «вуаль подсвечена со стороны солнца» БЕЗ объёмного
// контраста (ТЗ фазы 4 п.3); непрерывность и границы проверены сьютом (HC4-5).
const float HC_TERM_LO = -0.35;
const float HC_TERM_HI = 0.55;
const float HC_SHADE_FLOOR = 0.60;

// SKYHC-4: цвет освещения вуали — ТЕ ЖЕ источники данных, что у кучевых (без дублирования
// и без второго цикла суток, ТЗ фазы 4 п.1/2/6):
//   прямой свет: cloud_light_color × cloud_light_strength, цвет — конвенция рампы C9
//     (use_sun_color_ramp/ramp_near_color/ramp_far_color по cosθ взгляда к источнику —
//     та же формула, что в cloud_radiance_terms) × мягкий терминатор
//     shade = FLOOR + (1−FLOOR)·sstep(TERM_LO, TERM_HI, cosθ) ∈ [0.60, 1].
//     Марша теней/powder/MS/HG НЕТ — тонкий слой, ТЗ п.3: «без имитации контраста
//     крупного объёмного облака»;
//   заливка: конвенция C9 для верха слоя (use_ambient_from_sky → G(up)·ambient_sky_gain
//     или sky_color, иначе cloud_ambient_sky_color) × cloud_ambient_energy; земная доля
//     ambient-градиента не используется (вуаль выше всего — mix с ground не нужен);
//   hc_color — АЛЬБЕДО вуали (та же роль, что cloud_color у кучевых).
// Закат/сумерки/ночь приходят из тех же uniform'ов, что небо и кучевые (пресеты
// F10-F14/TimeOfDayController) — вуаль согласована с атмосферой автоматически.
// CPU-зеркало: CloudsTestBench.compute_hc_lighting().
vec3 hc_lit_color(vec3 dir) {
	vec3 ldir = cloud_light_direction / max(length(cloud_light_direction), 1e-5);
	float cos_theta = dot(dir, ldir);
	vec3 sun_col = cloud_light_color;
	if (use_sun_color_ramp) {
		sun_col = mix(mix(ramp_far_color, ramp_near_color, sstep(0.30, 0.80, cos_theta)),
				cloud_light_color, sstep(0.93, 0.995, cos_theta));
	}
	float shade = mix(HC_SHADE_FLOOR, 1.0, sstep(HC_TERM_LO, HC_TERM_HI, cos_theta));
	vec3 direct = sun_col * (cloud_light_strength * shade) * hc_light_gain;
	vec3 amb_top = cloud_ambient_sky_color;
	if (use_ambient_from_sky) {
		amb_top = (use_gradient_sky ? sky_gradient(vec3(0.0, 1.0, 0.0)) : sky_color) * ambient_sky_gain;
	}
	vec3 ambient = amb_top * (cloud_ambient_energy * hc_ambient_gain);
	return hc_color * (direct + ambient);
}

// SKYHC: вклад слоя в луч. Возвращает ПРЕМУНОЖЕННУЮ радиацию (rgb = hc_color·a),
// alpha_o — покрытие, dens_o/tau_o — диагностика. Марша НЕТ: один сэмпл плотности
// в середине плиты + Beer-Lambert по длине пути в плите (path = t_far − t_near),
// поэтому у зенита вуаль тоньше, а к горизонту плотнее (физично), и curtain по той же
// длине пути гасит скользящие лучи (чистый горизонт + нет алиасинга растянутой проекции:
// у ImageTexture3D нет mip-уровней). Пересечение плиты — той же layer_interval(), что
// и у кучевых (без дублирования). При !hc_enabled — немедленный выход (uniform-гейт).
// CPU-зеркало: CloudsTestBench.compute_hc_layer().
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
	return (hc_use_lighting ? hc_lit_color(dir) : hc_color) * a;
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
