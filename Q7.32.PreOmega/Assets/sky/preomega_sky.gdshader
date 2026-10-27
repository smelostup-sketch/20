shader_type sky;
// preomega_sky.gdshader — Q7.32.PreOmega.SL (небо-лайт), шаг 1 наведения порядка (2026-10-25).
// Происхождение: RENGAR PROTOTYPE OMEGA, компонент Q7.32.PreOmega.SL, Q732_SKY_v0.5.3.
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
// §10.2 (SKY_TZ_LUT7, 25.10.26): ВУАЛЬ ПЕРЕВЕДЕНА НА ОБЩУЮ P(dir): цвет =
//   sky_palette(dir)·(1+veil_lift)+veil_warm, альфа = узор плиты SKYHC × высотная
//   маска × солнечная маска × veil_master (таблицы §8.1/§8.2 по K-ключам). Модель
//   освещения вуали SKYHC-4 (hc_lit_color/hc_color/hc_*_gain/рампа C9) УДАЛЕНА —
//   ссылки на неё в исторических комментариях ниже относятся к модели до §10.2
//   (полный оригинал — в архиве Q7.32.PreOmega.SL/_PACKED/Q7.32.PreOmega.CUMULUS/).
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
uniform float sk_glow_int : hint_range(0.0, 4.0) = 0.30;
uniform float sk_glow_exp : hint_range(1.0, 128.0) = 6.0;
uniform float sk_wedge_int : hint_range(0.0, 2.0) = 0.35;
uniform float sk_wedge_az : hint_range(0.5, 16.0) = 3.0;	// v0.5.1: спад добавочного света вдоль горизонта
uniform float sk_zen_lift : hint_range(1.0, 6.0) = 2.0;	// v0.5.1: зенит = СРЕДНЯЯ точка между полюсами, не тёмная
uniform float sk_wedge_k : hint_range(0.0, 32.0) = 4.0;
uniform vec3 sk_sun_dir = vec3(0.0, 0.0, -1.0);	// направление НА солнце (мировое; конвенция basis.z DirectionalLight3D)
// ФИДБЕК 27.10.26 раунд 2 («луна и солнце не связаны, могут быть одновременно»):
// направление НА ЛУНУ — независимый uniform (раньше луна жёстко сидела на антисоляре:
// md = -sd). Пишет панель (лестница MOONPOS по K-ключам + слайдеры «Высота/Азимут луны»).
uniform vec3 sk_moon_dir = vec3(0.0, 0.766, 0.643);	// НА луну (мировое; дефолт elev 50° azim 0°)
uniform vec3 sk_anti_col : source_color = vec3(0.0202, 0.00718, 0.0152);	// v0.5.1: антисоляр = самая тёмная точка купола
uniform float sk_anti_p_lo : hint_range(0.3, 4.0) = 0.6;	// v0.5.2: низкое солнце — широкое тёмное ядро
uniform float sk_anti_p_hi : hint_range(0.3, 4.0) = 3.0;	// v0.5.2: высокое солнце — узкое ядро
uniform float sk_low_dim : hint_range(0.0, 1.0) = 0.25;	// v0.13: купол темнее при низком солнце
uniform vec3 sk_below_col : source_color = vec3(0.030, 0.011, 0.018);	// v0.9: ниже горизонта
uniform float sk_below_int : hint_range(0.0, 1.0) = 0.55;
// Сумеречные пояса (feedback 27.10.26, «скудный градиент K0-K2»): два доп. стопа
// на солнечной стороне купола — цвет/вес/окно по высоте (синус угла, как hmask).
// Данные из таблицы SHAPE лестницы K0-K6; w = 0 → член не выполняется (K3-K6
// побитово прежние). Тот же приём, что гейт hc_detail_strength (SKYHC-3.3).
uniform vec3 sk_band_col : source_color = vec3(0.0);
uniform float sk_band_w : hint_range(0.0, 1.0) = 0.0;
uniform float sk_band_lo = 0.05;
uniform float sk_band_hi = 0.30;
uniform vec3 sk_band2_col : source_color = vec3(0.0);
uniform float sk_band2_w : hint_range(0.0, 1.0) = 0.0;
uniform float sk_band2_lo = 0.22;
uniform float sk_band2_hi = 0.55;
// ВЕРХНИЙ ЗЕНИТНЫЙ СТОП рампы §3.1 (фидбек 27.10.26 раунд 2 «скудный градиент»):
// выше поясов купол уходит не в плоский zen_mid, а непрерывно темнеет к sk_zenith
// (zenith→mid→horizon многостопный рамп ТЗ). w=0 → член тождественен (K3-K6 побитово).
uniform float sk_top_w : hint_range(0.0, 1.0) = 0.0;
uniform float sk_top_lo = 0.35;
uniform float sk_top_hi = 0.90;
// SUNARC (фидбек 27.10.26 р3 п.3, раунд 6): вес радиальной рампы стоков по угловому
// удалению от солнца u = atan2(|dir×sd|, dir·sd)/π (0 = солнце, 1 = антисоляр).
// Изолинии градиента = дуги вокруг солнца; солнце в надире → градиент стартует под
// нами, зенит (= антисоляр) = самая тёмная точка. 0 = прежний купол (K3-K6 побитово;
// при 0 arc-ветка НЕ вычисляется, а не смешивается с нулевым весом).
uniform float sk_arc_w : hint_range(0.0, 1.0) = 0.0;
// SUNARC-ЭЛЛИПС (фидбек 27.10.26 р6 п.2): растяжение изолиний рампы по горизонтали
// (эллипс с горизонтальной большой осью вокруг солнца): горизонтальное угловое
// смещение считается в 1/S раз вертикального. 1.0 = круг (K3-K6, побитово при arc_w=0).
uniform float sk_arc_stretch = 1.0;
uniform float sk_dither : hint_range(0.0, 1.0) = 1.0;

// === Освещение — прямой источник (солнце/луна). Конвенция имён продакшн-неба: ===
// cloud_light_direction/color/strength — те же, что пишет TimeOfDayController из
// SkyPhaseProfile (примечание B4; подключение к основному проекту без переименований). ===
uniform vec3 cloud_light_direction = vec3(-0.75, 0.50, -0.43);	// направление НА источник (нормализуется; конвенция продакшн-неба)
uniform vec3 cloud_light_color : source_color = vec3(1.0, 0.97, 0.92);	// цвет источника (нейтральный дневной; закат/ночь — рецепты в README)
uniform float cloud_light_strength = 0.70;		// интенсивность прямого света (0 = выключен)

// === Общая угловая палитра P(dir) (SKY_TZ_LUT7 §3.1): средний пояс рампы ===
uniform vec3 sk_mid : source_color = vec3(0.107580, 0.036102, 0.078501);	// mid K4 (багровый закат)

// === §5.1: солнце — аналитический диск (fwidth-AA) + два ореола (средний g1, широкий g2) ===
uniform bool sun_visible = true;			// мастер-гейт диска и ореолов
uniform float sun_size_deg = 1.8;			// художественный угловой радиус диска, ° (1.5-2.5 по §8.4)
uniform float sun_core_int = 5.0;			// HDR-яркость ядра (bloom-порог ~1.0, §5.3)
uniform float sun_g1_int = 0.35;			// средний ореол: амплитуда (цвет = sk_glow_col)
uniform float sun_g1_exp = 8.0;			// средний ореол: угловой спад
uniform float sun_g2_int = 0.12;			// широкое поле: амплитуда (post-glow/стрики — шаг §10.8)
uniform float sun_g2_exp = 2.5;			// широкое поле: угловой спад
uniform vec3 sun_disk_color = vec3(1.0, 0.953, 0.816);	// display-space (§5.3 bypass), доли hex/255 по K-ключам

// === §5.2: луна — SDF-серп (фазы параметром, НЕ атлас), earthshine, ореол ===
uniform float moon_size = 0.02;			// угловой радиус луны, радианы (~1.1°, художественный)
uniform float moon_phase = 0.0;			// 0 = новолуние (серп исчезает), 1 = полная
uniform vec3 moon_color = vec3(0.753, 0.784, 0.910);	// display-space, доли hex/255 по K-ключам (§8.4)
uniform float moon_glow_int = 0.0;		// амплитуда ореола луны (0.35/0.2/0.1 для K0/K1/K2)
uniform float moon_glow_exp = 40.0;		// угловой спад ореола луны

// === §5.2: звёзды (процедурные, два слоя hash-точек с мягким ядром, без мерцания) ===
uniform float star_intensity = 0.0;		// 1.0/0.7/0.25/0.05/0 для K0..K3+ (§8.4)
uniform float veil_moon = 0.0;			// лунный блик НА вуали (шеен по направлению луны)
uniform bool comp_linear = false;			// ЭКСПЕРИМЕНТ: земля без Filmic (тонмапп Linear),
										// композит неба переключается на sRGB-encode вместо inv_filmic

// === Ассеты заказчика (25.10.26): стрик-глэйр и деталь луны ===
uniform sampler2D streak_tex : filter_linear;		// рисованный горизонтальный глэйр (бесцветный)
uniform float streak_int = 0.0;			// интенсивность стриков по K-ключам (K4 золото → 0.5)
uniform sampler2D moon_detail_tex : filter_linear;	// grayscale-карта кратеров
uniform float moon_detail_int = 0.5;		// доля детали на полных фазах (§5.2)

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
uniform float hc_detail_strength = 0.0;		// SKYHC-3.3: амплитуда мелкой детали на кромках (0 = побитово 3.2; материал задаёт 0.35)
uniform float hc_detail_scale = 3000.0;		// SKYHC-3.3: метров на период Worley (размер бугорков; меню 800-8000)
// === Вуаль на общей P(dir) (SKY_TZ_LUT7 §3.2): тон и маски по K-ключам ===
uniform float veil_master : hint_range(0.0, 1.0) = 0.6;		// общая сила слоя (K0 ночь → 0.05)
uniform float veil_base : hint_range(0.0, 1.0) = 0.35;		// ФИКС А: пол узора — вуаль живёт и без узора (дымка у зари)
uniform float veil_curve : hint_range(0.5, 6.0) = 2.0;		// высотная маска: 1 у горизонта, 0 в зените
uniform float veil_sun : hint_range(0.0, 2.0) = 1.4;		// добавка у солнца/зари (раскалённая дымка)
uniform float veil_sun_exp : hint_range(1.0, 12.0) = 4.0;	// угловая ширина солнечной маски
uniform float veil_lift : hint_range(0.0, 0.5) = 0.22;	// высветление P(dir) в теле вуали
// ВУАЛЬ МЕЖДУ НЕБОМ И НЕБЕСНЫМИ ТЕЛАМИ (фидбек 27.10.26 р3 п.2: «вуаль не скрывает
// звёзды и не искажает их, луна и звезды ближе вуали»): зенитный пол высотной маски —
// плита существует и над головой, поэтому укрывает звёзды/луну у зенита (0 = прежний
// вид, K3-K6); преломление — отклонение направления небесных тел градиентом плотности
// плиты (0 = без искажения, K3-K6; гейт uniform'ом, цена в off = 0).
uniform float veil_zen_floor : hint_range(0.0, 1.0) = 0.0;
uniform float veil_refract : hint_range(0.0, 1.0) = 0.0;
uniform vec3 veil_warm : source_color = vec3(0.165, 0.078, 0.031);	// утепление (#2a1408, K4)
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
// SUNARC: радиальная рампа стопов по u (общая для купола и P(dir) вуали — рассинхрон
// «вуаль другого цвета» исключён). Лестница стопов мягкими СТУПЕНЯМИ (rise-only, без
// спада): каждый стоп держится до следующего — перекрытий-щелей нет; переход стопа =
// его окно rise (0.4·окна, как пояса r2). Порядок стопов: ядро зари (sk_horizon) →
// слива/бирюза (band) → голубой (band2) → средний купол (zen_mid) → антисоляр (anti_c,
// окно 0.75-0.97 фикс: терминал рампы всегда антисоляр).
vec3 rad_ramp(vec3 dir, vec3 sd, out float u_o) {
	// численно устойчивый угол (фидбек 27.10.26 р6): atan2(|cross|, dot) ровнее acos
	// у u=0 и u=1; выбор формы подтверждён тестом угла в sim (расхождение < 1e-9).
	float th = atan(length(cross(dir, sd)), dot(dir, sd));
	// ЭЛЛИПС (р6 п.2): смещение раскладывается на вертикальную (в плоскости солнце-зенит)
	// и горизонтальную (вдоль горизонта) составляющие; горизонтальная ужимается в S раз
	// → изолинии = эллипсы с горизонтальной большой осью. У антисоляра (th→π) растяжение
	// плавно снимается (wq→0): u=1 точно на антисоляре, без шума q при |w|→0.
	float u = th / 3.141592653589793;
	// у надира/зенита солнца горизонтальная ось эллипса вырождена (все азимуты равны):
	// растяжение плавно снимается при |sd.y| -> 1, иначе кольцо горизонта непостоянно
	// (тест T3: надир -> равномерное кольцо)
	float S = 1.0 + (max(sk_arc_stretch, 1.0) - 1.0)
			* (1.0 - sstep(0.85, 0.99, abs(sd.y)));
	if (S > 1.001) {
		vec3 up0 = abs(sd.y) > 0.99 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
		vec3 upr = normalize(up0 - sd * dot(up0, sd));
		vec3 rgt = cross(sd, upr);
		vec3 w = dir - sd * dot(dir, sd);
		float q = abs(dot(w, rgt)) / max(length(w), 1e-6);
		float wq = q * (1.0 - sstep(0.80, 1.0, u));
		u = th * (1.0 - (1.0 - 1.0 / S) * wq) / 3.141592653589793;
	}
	u_o = u;
	vec3 zen_mid = sk_zenith * sk_zen_lift;
	float sh = smoothstep(-0.03, 0.85, sd.y);
	vec3 anti_c = mix(sk_anti_col, zen_mid, 0.45 * sh);
	vec3 c = sk_horizon;
	float e1 = max(0.4 * (sk_band_hi - sk_band_lo), 0.02);
	c = mix(c, sk_band_col, sk_band_w * sstep(sk_band_lo, sk_band_lo + e1, u));
	float e2 = max(0.4 * (sk_band2_hi - sk_band2_lo), 0.02);
	c = mix(c, sk_band2_col, sk_band2_w * sstep(sk_band2_lo, sk_band2_lo + e2, u));
	c = mix(c, zen_mid, smoothstep(sk_band2_hi, sk_band2_hi + 0.18, u));
	c = mix(c, anti_c, smoothstep(0.75, 0.97, u));
	return c;
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
	// сумеречные пояса (§8.1, ночи K0-K2): стоп-1 (слива) и стоп-2 (голубой) между
	// горизонтной полосой источника и средней точкой полюсов; гейт по tp — только
	// солнечная сторона. sk_band_w/sk_band2_w = 0 → оба mix'а тождественны (K3-K6).
	// МЯГКИЕ КРОМКИ ПОЯСОВ (фидбек 27.10.26 раунд 2: «градиенты цвета освещения
	// слишком резкие на K1-K2»): ширина перехода = 0.4·ОКНА пояса вместо фикс. 0.06 —
	// пояса пересекаются плавным кроссфейдом, жёстких полос нет. w=0 → тождественно
	// (K3-K6 побитово прежние).
	float band_tg = smoothstep(0.50, 0.85, tp);
	float e_b1 = max(0.4 * (sk_band_hi - sk_band_lo), 0.02);
	float w_b1 = sk_band_w * smoothstep(sk_band_lo, sk_band_lo + e_b1, h)
			* (1.0 - smoothstep(sk_band_hi - e_b1, sk_band_hi, h)) * band_tg;
	base = mix(base, sk_band_col, clamp(w_b1, 0.0, 1.0));
	float e_b2 = max(0.4 * (sk_band2_hi - sk_band2_lo), 0.02);
	float w_b2 = sk_band2_w * smoothstep(sk_band2_lo, sk_band2_lo + e_b2, h)
		* (1.0 - smoothstep(sk_band2_hi - e_b2, sk_band2_hi, h)) * band_tg;
	base = mix(base, sk_band2_col, clamp(w_b2, 0.0, 1.0));
	// верхний зенитный стоп: непрерывное затемнение купола к вершине (§3.1);
	// гейт sk_top_w: K3-K6 = 0 → побитово прежний купол
	float w_top = sk_top_w * smoothstep(sk_top_lo, sk_top_hi, h);
	base = mix(base, sk_zenith, clamp(w_top, 0.0, 1.0));
	// === КОНТРАКТ ПОРЯДКА МАРОК/ЧЛЕНОВ КУПОЛА (фидбек 27.10.26 р6, п.3): ===
	//   1) двухполюсный базис + пояса по h + верхний зенитный стоп (выше, r5-путь);
	//   2) SUNARC: mix к rad_ramp по sk_arc_w (при 0 ветка НЕ считается — uniform-гейт,
	//      побитовая совместимость r5, а не mix-с-нулём);
	//   3) wedge — аэрозольная дымка горизонта (h, азимут к солнцу): ПОСЛЕ дуг, вес у
	//      ночей мал и узок (wedge_k 35-70), последовательность стопов не уничтожает
	//      (проверено тестом wedge on/off в sim);
	//   4) glow-ядро (радиальное, pow(dot, glow_exp)) — белое ядро зари поверх дуг;
	//   5) below-horizon теневой mix (только h<0 — дуг над горизонтом не касается);
	//   6) low_dim — скаляр по высоте солнца (hue не меняет);
	//   7) dither. Последующие члены дуги НЕ выпрямляют: wedge/below — по h, но wedge
	//      узкий, below — ниже горизонта, low_dim — скаляр.
	if (sk_arc_w > 0.0) {
		float u_arc = 0.0;
		vec3 rad = rad_ramp(dir, sd, u_arc);
		base = mix(base, rad, sk_arc_w);
	}
	// горизонт: добавочный свет, спадающий с удалением от источника вдоль горизонта
	vec2 dH = vec2(dir.x, dir.z);
	vec2 sH = vec2(sd.x, sd.z);
	float azH = dot(dH, sH) / max(length(dH) * length(sH), 1e-6);
	// Световой эффект горизонта (р6 п.2): на arc-ключах клин стихает ПОСТЕПЕННО и равен
	// 0 ровно на антисоляре (Δaz=180°), деля полный круг 360° на две равные половины
	// (освещённую вокруг азимута солнца и тёмную вокруг антисоляра): ((1+azH)/2)^p.
	// Старая форма pow(max(azH,0),p) с отсечкой на 90° сохранена K3-K6 (побитово).
	float azf = (sk_arc_w > 0.0)
			? pow(0.5 + 0.5 * azH, max(sk_wedge_az, 0.0))
			: pow(max(azH, 0.0), sk_wedge_az);
	float band = azf * exp(-abs(h) * sk_wedge_k) * sk_wedge_int;
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

// §5.3/§10.8: Filmic (tonemap.glsl Godot 4.7) и ТОЧНАЯ аналитическая инверсия
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

float srgb_to_linear(float u) {
	return u <= 0.04045 ? u / 12.92 : pow((u + 0.055) / 1.055, 2.4);
}

vec3 srgb_to_linear3(vec3 v) {
	return vec3(srgb_to_linear(v.x), srgb_to_linear(v.y), srgb_to_linear(v.z));
}

// §5.1: солнце — аналитический диск с fwidth-AA (crisp-кромка на любом разрешении,
// тест §11.3) + два ореола цветом sk_glow_col (связаны с палитрой состояния).
// Диск и ореолы гаснут, когда источник ниже горизонта (vis): зарю держит узел P(dir).
vec3 sun_celestial(vec3 dir, vec3 sd) {
	if (!sun_visible) {
		return vec3(0.0);
	}
	float vis = smoothstep(-0.02, 0.02, sd.y);
	float ang = acos(clamp(dot(dir, sd), -1.0, 1.0));
	float sunR = radians(max(sun_size_deg, 0.1));
	float edge = max(fwidth(ang) * 1.5, 0.0004);
	float disc = 1.0 - smoothstep(sunR - edge, sunR + edge, ang);
	float d = max(dot(dir, sd), 0.0);
	vec3 gdisp = filmic3(sk_glow_col);	// цвет ореолов/стрика в display (M1 round-trip)
	vec3 col = sun_disk_color * (disc * sun_core_int)
			+ gdisp * (pow(d, sun_g1_exp) * sun_g1_int)
			+ gdisp * (pow(d, sun_g2_exp) * sun_g2_int);
	// Стрик-глэйр v1: угловой анизотропный спрайт вокруг источника (горизонталь мира;
	// точный screen-space post-pass с bypass тонмаппера — шаг §10.8).
	if (streak_int > 0.0) {
		vec3 right_w = normalize(cross(vec3(0.0, 1.0, 0.0), sd));
		vec3 up_w = cross(sd, right_w);
		vec3 to = dir - sd * dot(dir, sd);
		vec2 suv = vec2(dot(to, right_w) / radians(60.0), dot(to, up_w) / radians(6.0)) * 0.5 + 0.5;
		// ФИКС: стрик только вблизи источника (раньше suv сходился в центр спрайта на
		// антисоляре — блик лез на противоположную сторону купола)
		float sgate = 1.0 - smoothstep(radians(45.0), radians(60.0), ang);
		if (suv.x > 0.0 && suv.x < 1.0 && suv.y > 0.0 && suv.y < 1.0) {
			col += gdisp * (texture(streak_tex, suv).r * streak_int * sgate);
		}
	}
	return col * vis;
}

// §5.2: луна — SDF-фаза: body минус cut-круг, смещённый по фазе (0 = новолуние: cut
// съедает всё; 1 = полная: cut уходит за диск). Earthshine 0.06 в тени серпа.
// НАПРАВЛЕНИЕ = sk_moon_dir, НЕЗАВИСИМОЕ от солнца (фидбек 27.10.26 раунд 2: «луна и
// солнце в каждом состоянии, не связаны между собой, могут быть одновременно»):
// раньше md = -sd жёстко сажал луну на антисоляр. Кромка серпа crisp (fwidth-AA).
// Стрик-глэйр с луны СНЯТ (фидбек: «у луны горизонтальный блик солнца»): стрик-ассет
// остаётся только за солнцем (streak_int, K3-K6).
vec3 moon_celestial(vec3 dir) {
	vec3 md = normalize(sk_moon_dir);
	float mvis = smoothstep(-0.02, 0.02, md.y);
	if (mvis <= 0.0 || moon_phase <= 0.001) {
		return vec3(0.0);
	}
	vec3 up0 = abs(md.y) > 0.99 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up0, md));
	vec3 up = cross(md, right);
	vec2 p = vec2(dot(dir, right), dot(dir, up));
	float r = max(moon_size, 0.001);
	float w = max(fwidth(p.x) * 1.5, 0.0004);
	float body = 1.0 - smoothstep(-w, w, length(p) - r);
	float dist = mix(0.0, 2.2 * r, clamp(moon_phase, 0.0, 1.0));
	float cut = smoothstep(-w, w, length(p - vec2(dist, 0.0)) - r * 0.98);
	float crescent = body * cut;
	float earthshine = body * (1.0 - cut) * 0.06;
	// деталь (кратеры) — только полные фазы (§5.2), гейт smoothstep без «хлопка»
	float det_w = smoothstep(0.85, 0.95, moon_phase) * moon_detail_int;
	float det = 1.0;
	if (det_w > 0.001) {
		vec2 muv = clamp(p / r * 0.5 + 0.5, vec2(0.0), vec2(1.0));
		det = mix(1.0, texture(moon_detail_tex, muv).r * 1.7, det_w);
	}
	float mdot = max(dot(dir, md), 0.0);
	// ореол — ЦВЕТОМ СОСТОЯНИЯ (mix к mid-поясу), а не белым: K0-индиго вместо белья
	vec3 mgcol = mix(moon_color, filmic3(sk_mid), 0.55);
	vec3 col = moon_color * (crescent * det + earthshine * 0.35)
			+ mgcol * (pow(mdot, moon_glow_exp) * moon_glow_int);
	return col * mvis;
}

// §5.2: звёзды — два слоя hash-точек на угловой сетке с мягким ядром (стилизация);
// стабильны во времени (фон не мерцает), гаснут к горизонту и в ореоле луны (§11.6).
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

// SKY_TZ_LUT7 §3.1: ОБЩАЯ угловая палитра P(dir) — трёхстопная рампа по высоте
// (horizon → mid → zenith; zenith = антисолярный тёмный слот по терминологической
// пометке заказчика) + солнечный узел + зона ниже горизонта. Из неё берут цвет и
// купол (будущий шаг), и вуаль (§3.2) — рассинхрон «вуаль другого цвета» невозможен.
vec3 sky_palette(vec3 dir) {
	float h = clamp(dir.y, -1.0, 1.0);
	vec3 c = mix(sk_horizon, sk_mid, smoothstep(0.02, 0.35, h));
	c = mix(c, sk_zenith, smoothstep(0.30, 0.80, h));
	// ФИКС Б (баг «светлое пятно в антисоляре»): антисолярный член той же формы, что в
	// куполе: в самой тёмной точке купола вуаль берёт тёмный цвет, а не средний пояс.
	// SUNARC: вуаль берёт ту же радиальную рампу (порядок: рампа P → дуга → антисоляр
	// → glow → below), иначе вуаль «выпрямила» бы дуги своим тоном
	if (sk_arc_w > 0.0) {
		float u_p = 0.0;
		vec3 rad_p = rad_ramp(dir, normalize(sk_sun_dir), u_p);
		c = mix(c, rad_p, sk_arc_w);
	}
	vec3 sd_p = normalize(sk_sun_dir);
	float tp = clamp(0.5 + 0.5 * dot(dir, sd_p), 0.0, 1.0);
	float w_ant = pow(clamp(1.0 - tp * 2.0, 0.0, 1.0), 1.6) * (1.0 - smoothstep(0.0, 0.5, abs(h)));
	c = mix(c, sk_anti_col, w_ant);
	float sp = clamp(dot(dir, sd_p), 0.0, 1.0);
	c = mix(c, sk_glow_col, clamp(pow(sp, sk_glow_exp) * sk_glow_int, 0.0, 1.0));
	c = mix(c, sk_below_col, smoothstep(0.0, -0.18, h) * sk_below_int);
	return c;
}

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
// SKYHC+§3.2: вклад вуали = АЛЬФА УЗОРА (плита: один сэмпл плотности + Beer-Lambert +
// curtain, прежняя геометрия SKYHC) × высотная маска × солнечная маска × veil_master.
// Цвет вуали больше НЕ однотонный: берётся из sky_palette(dir) в sky() (§3.2).
// Марша НЕТ; при !hc_enabled — немедленный выход (uniform-гейт).
// Середина пути луча в плите вуали (та же геометрия, что hc_alpha; вынесено для
// преломления небесных тел: градиент плотности берётся в этой точке).
bool slab_interval(vec3 dir, out vec3 p_o, out float path_o) {
	vec3 origin = hc_use_world_anchor ? POSITION : vec3(0.0);
	// guard толщины плиты (тот же приём, что max(top − bottom, 1e-4) в layer_height_fraction)
	float top_safe = hc_layer_bottom + max(hc_layer_top - hc_layer_bottom, 1e-4);
	float t_near = 0.0;
	float t_far = 0.0;
	if (!layer_interval(dir, hc_layer_bottom - origin.y, top_safe - origin.y, t_near, t_far)) {
		return false;
	}
	path_o = t_far - t_near;
	p_o = origin + dir * min(0.5 * (t_near + t_far), HC_MAX_DIST);
	return true;
}

float hc_alpha(vec3 dir, out float dens_o, out float tau_o) {
	dens_o = 0.0;
	tau_o = 0.0;
	if (!hc_enabled) {
		return 0.0;
	}
	vec3 p = vec3(0.0);
	float path = 0.0;
	if (!slab_interval(dir, p, path)) {
		return 0.0;
	}
	float d = hc_density(p);
	float tau = d * max(hc_tau_per_km, 0.0) * (path * 0.001);
	float curtain = 1.0 - sstep(hc_curtain_start, hc_curtain_end, path);
	float a = clamp((1.0 - exp(-tau)) * curtain, 0.0, 1.0);
	dens_o = d;
	tau_o = tau;
	return a;
}


void sky() {
	vec3 dir = normalize(EYEDIR);
	// SKYHC-1: диагностика вуали (hc_debug 1-3) — честный пропуск: ни солнца, ни
	// градиента; показываем ИМЕННО член слоя (плотность/альфа/оптическая толщина).
	// return в sky() запрещён движком → структура ветвлением (как в v0.5.3).
	bool hc_diag = hc_debug > 0.5;
	// плита вуали считается ДО небесных тел: её альфа/плотность нужны окклюзии и
	// преломлению (фидбек 27.10.26 р3 п.2 «вуаль не скрывает звёзды и не искажает»).
	float hc_a = 0.0;
	float hc_d = 0.0;
	float hc_tau = 0.0;
	hc_a = hc_alpha(dir, hc_d, hc_tau);
	// §5: солнце + луна + звёзды — аналитика в sky pass (диагностики hc_debug чистые).
	vec3 sunbg = vec3(0.0);
	if (!hc_diag) {
		// ФИКС (feedback 27.10.26 «вместо луны соляр на антисоляре»): небесные тела
		// читают НАСТОЯЩЕЕ солнце (sk_sun_dir), а не cloud_light_direction — ночью
		// игровой ключ светит С ЛУНЫ (антисоляр), и диск/ореол солнца вставали на место
		// луны, а луна гасла (mvis=0). Днём оба направления совпадают — без изменений.
		// НЕБЕСНЫЕ ТЕЛА ЗА ВУАЛЬЮ (р3 п.2): направление отклоняется градиентом плотности
		// плиты (конечные разности в середине пути, 2 доп. выборки плотности; гейт
		// veil_refract/hc_enabled/hc_d — в off цена 0, K3-K6 побитово). Звёзды и луна
		// дрожат/плывут ЗА вуалью, лимб луны искажается на кромках образований.
		vec3 cdir = dir;
		if (veil_refract > 0.0 && hc_enabled && hc_d > 0.001) {
			vec3 p = vec3(0.0);
			float pth = 0.0;
			if (slab_interval(dir, p, pth)) {
				float e = 250.0;	// шаг конечных разностей по плоскости плиты, м
				float d0 = hc_density(p);
				vec3 g = vec3(hc_density(p + vec3(e, 0.0, 0.0)) - d0, 0.0,
						hc_density(p + vec3(0.0, 0.0, e)) - d0);
				float gl = length(g);
				if (gl > 1e-5) {
					vec3 g0 = g / gl;
					vec3 gn = normalize(g0 - dir * dot(g0, dir));
					cdir = normalize(dir + gn * (veil_refract * hc_d * veil_master * 0.06));
				}
			}
		}
		vec3 sd_sun = normalize(sk_sun_dir);
		vec3 md = normalize(sk_moon_dir);	// луна независима от солнца (27.10.26 р.2)
		sunbg = sun_celestial(cdir, sd_sun) + moon_celestial(cdir);
		float horfade = smoothstep(-0.05, 0.15, dir.y);
		float mdamp = 1.0 - smoothstep(-0.02, 0.02, md.y)
				* pow(max(dot(cdir, md), 0.0), 8.0) * 0.7;
		sunbg += vec3(0.85, 0.90, 1.0) * (star_field(cdir) * star_intensity * horfade * mdamp);
	}

	// Фон неба: двухполюсный градиент G(dir) (v0.5.1/v0.5.2) или плоский sky_color.
	vec3 bg = use_gradient_sky ? sky_gradient(dir) : sky_color;
	// SKY_TZ_LUT7 §3.2: ВУАЛЬ НА ОБЩЕЙ P(dir): альфа узора плиты (SKYHC: один сэмпл
	// плотности + Beer-Lambert + curtain) × высотная маска (1 у горизонта, 0 в зените —
	// антисолярный зенит остаётся чистым) × солнечная маска (раскалённая дымка у зари)
	// × veil_master. Цвет = P(dir), высветленный/утеплённый: однотонная вуаль запрещена
	// (фиолетовый mid-пояс и тёмный зенит живут и под вуалью). Диск солнца вуаль
	// ослабляет честно (mix по всему bg+sunbg). При veil_master/hc_enabled = 0 — base = bg+sunbg.
	vec3 Pdir = sky_palette(dir);
	// высотная маска с зенитным полом: плита над головой НЕ прозрачна (veil_zen_floor),
	// поэтому вуаль укрывает звёзды/луну и у зенита; floor=0 → прежняя формула (K3-K6)
	float height_mask = mix(veil_zen_floor, 1.0,
			1.0 - pow(clamp(dir.y, 0.0, 1.0), max(veil_curve, 0.001)));
	float sp_v = clamp(dot(dir, normalize(sk_sun_dir)), 0.0, 1.0);
	float sun_mask = 1.0 + veil_sun * pow(sp_v, veil_sun_exp);
	// ФИКС А (баг «у солнца прозрачно»): узор плиты МОДУЛИРУЕТ плотность, но не гейтит:
	// shape = mix(veil_base, 1, pattern); curtain плиты больше не обнуляет дымку у зари.
	// Гейт идентичности сохранён: hc_enabled=false → shape=0 → вуали нет.
	float shape = hc_enabled ? mix(veil_base, 1.0, hc_a) : 0.0;
	float veil_a = clamp(shape * height_mask * sun_mask * veil_master, 0.0, 1.0);
	vec3 veil_col = Pdir * (1.0 + veil_lift) + veil_warm;
	// §5.3/§10.8: display-композит с bypass тонмаппера: купол+вуаль → filmic в display,
	// небесные тела ПРИБАВЛЯЮТСЯ в display (hue палитры не десатурируется Filmic'ом),
	// затем точный inv_filmic — движковый тонмапп возвращает сумму 1:1. Вуаль ближе к
	// камере: её альфа честно ослабляет небесные тела (1 − veil_a), диск в т.ч.
	vec3 base_lin = mix(bg, veil_col, veil_a);
	// лунный свет на вуали: шеен по направлению луны, пропорционально альфе вуали
	// (раньше вуаль луну «не видела» — feedback 25.10.26). Направление — sk_moon_dir
	// (независимая луна, 27.10.26 р.2): антисоляр больше не авторитет для луны.
	vec3 md_s = normalize(sk_moon_dir);
	vec3 mgc = mix(moon_color, filmic3(sk_mid), 0.55);
	float msheen = pow(max(dot(dir, md_s), 0.0), 5.0) * veil_moon * veil_a;
	vec3 disp = filmic3(base_lin) + sunbg * (1.0 - veil_a) + mgc * msheen;
	if (hc_diag) {
		COLOR = hc_debug < 1.5 ? vec3(hc_d) : (hc_debug < 2.5 ? vec3(veil_a) : vec3(clamp(hc_tau, 0.0, 1.0)));
	} else if (comp_linear) {
		// эксперимент: движок тонмаппит Linear (только sRGB-encode) — отдаём display
		// через sRGB-encode-инверсию; небо выглядит ТАК ЖЕ, земля — без Filmic
		COLOR = srgb_to_linear3(disp);
	} else {
		COLOR = inv_filmic3(disp);
	}
}
