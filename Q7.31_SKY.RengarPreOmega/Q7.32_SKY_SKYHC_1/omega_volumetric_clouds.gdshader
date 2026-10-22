shader_type sky;

// B6: compile-time tier дорогого прохода: 0 = full (Reference, марш в full-res),
// 1 = half (марш в half-res subpass), 2 = quarter (марш в quarter-res subpass).
// Варианты строит стенд патчем строки #define (спайк B5: code-patch Shader работает;
// спайк B6: #if вокруг render_mode компилируется).
#define SKY_TIER 1
#if SKY_TIER == 1
render_mode use_half_res_pass;
#elif SKY_TIER == 2
render_mode use_quarter_res_pass;
#endif
// omega_volumetric_clouds.gdshader — RENGAR PROTOTYPE OMEGA, компонент Q7.32_SKY_SKYHC_1.
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
// ЭТАП D3: ПРАВКИ ЧИТАЕМОСТИ (два фикса по итогам просмотра D2):
//   (1) РЕЗКОСТЬ ГРАДИЕНТА НЕБА: sky_grad_sharp — симметричная S-кривая поверх каждого
//       окна палитры (вертикаль + 4 угловых кольца): >1 сжимает переходы к середине окна,
//       цветовые зоны становятся различимее, границы горизонта/зенита/колец — чётче;
//       1.0 → побитово D2; <1 → ещё плавнее.
//   (2) ТВЁРДАЯ КРОМКА ОБЛАКОВ: cloud_edge_contrast — контрастная кривая альфы вокруг 0.5
//       в поле плотности: >1 сужает полосу перехода прозрачность→плотность, силуэт
//       становится твёрдым, контур читаемым; 1.0 → побитово D2. Контраст применяется
//       к форме ДО высотного профиля/curtain и виден и в марше, и в теневых лучах.
// Формулы марша/освещения/масок не изменены.
// ЭТАП D2 (история): ФАЗА ПРАВОК освещения (три фикса по итогам просмотра D1):
//   (1) РАЗМЫТОЕ СОЛНЦЕ ЗА ОБЛАКОМ: широкий glow-член ∝ (1−T)·pow(cosθ, sun_blur_power):
//       где облако закрывает диск (T→0), резкий круг гаснет и остаётся большое мягкое
//       пятно света; где чисто (T=1) — glow=0, диск резкий. use_sun_blur=false → вид D1.
//   (2) КОНТРОВЫЕ НЕ ТАК ТЁМНЫ: powder_strength 0.60→0.30, ms_sun_gain стал uniform
//       (0.30→0.45), ms_strength 0.5→0.65 — внутреннее свечение теней сильнее.
//   (3) ОСВЕЩЁННЫЕ ГРАНИ БЕЛЕЕ: hg_diffuse_mix — доля изотропного ответа в фазе:
//       phase_eff = mix(1.0, phase_HG, hg_diffuse_mix); при солнце за спиной освещённые
//       объёмы читаются светло-серыми/белыми, блик к солнцу сохраняется (ослабленный).
// Формулы марша/масок/градиента не изменены. ЭТАП D1 (история): (1) дефолт плотности по выбору заказчика: base_scale 35500, coverage 0.23,
// softness 0.17, detail_scale 3000, detail_strength 0.60, erosion 0.30, stretch 1.75;
// (2) градиент неба чище и плавнее: цепочка ОТ СОЛНЦА: бело-жёлтый (sky_band_white) →
// розовый (sky_band_pink) → светло-голубой/средний (sky_band_mid) → тёмный сине-фиолетовый
// (sky_antisolar); окна расширены для плавности; sky_band_red переименован в sky_band_mid.
// Формулы марша/освещения/масок не изменены (C9).
// ФАЗА C, ЭТАП C9 (история): настройка 7 — освещение облаков ПОД градиент неба (пункт 7 плана):
//   (a) рампа цвета солнца по углу взгляда к солнцу (cosθ): у солнца — light_color
//       (бело-розовый), середина — ramp_near (розовый), далеко — ramp_far (красный):
//       кромки окрашиваются по удалению от солнца, как в референсах;
//   (b) ambient-верх из зенита градиента: use_ambient_from_sky → amb_top = G(up)·gain:
//       под голубым зенитом облака белые, под тёмно-синим — темнее (без ручных цветов).
//   Оба выключены → побитово C8.
// ФАЗА C, ЭТАП C8 (история): настройка 6 — ГРАДИЕНТНОЕ НЕБО G(dir) по палитре референсов
// (refs_palette.md): 5 цветовых стопов-данных: горизонт, зенит, антисолнце,
// красное кольцо, розовое кольцо у солнца. Угловая сборка:
//   base = mix(horizon, zenith, sstep(0.02,0.35, dir.y))          — вертикаль
//   base = mix(base, antisolar, sstep(-0.25,-0.80, cosθ))         — тёмный антисолнечный край
//   base = mix(base, band_red,  sstep(0.25,0.70, cosθ))           — красное кольцо
//   base = mix(base, band_pink, sstep(0.70,0.93, cosθ))           — розовое у солнца
// use_gradient_sky=false → плоский sky_color (побитово C7 по фону). Диск/гало солнца и
// облака композитятся ПОВЕРХ G(dir) (miss-пиксели = G, субпас-композит mix(G+sun, …)).
// ФАЗА C, ЭТАП C7 (история): настройка 5 — «чище горизонт»: distance curtain — плотность облаков
// плавно → 0 на дистанциях [far_curtain_start, far_curtain_end]: скользящие лучи у
// горизонта (путь десятки км) больше не набирают оптически толстый «вал» из облаков и
// их теней; горизонт становится чистым небом (которое в C8 получит градиент).
// Выкл → побитово C6. Формулы освещения/маски/анизотропии не изменены.
// ФАЗА C, ЭТАП C6 (история): настройка 4 — «солнце белее»: цвет ДИСКА отделён от цвета освещения
// (sun_disk_color): белое горячее ядро при красном/коралловом свете и гало — как в
// референсах заката (refs_palette.md: horizon_sun #FBEBDE/#FAFFC9 при крамсон-небе).
// Гало остаётся цветом освещения (cloud_light_color) — красное кольцо вокруг белого ядра.
// ФАЗА C, ЭТАП C5 (история): настройка 2 — горизонтальная ориентация масс без потери «этажей»:
//   (a) высотно-зависимая анизотропия: stretch(h) = mix(aniso_base, aniso_top, h) —
//       у основания башни (2.2), к верху плоские «шляпы» (0.75);
//   (b) cloud_horizontal_stretch: удлинение масс по горизонтали (линзы/пласты);
//   (c) y-warp: низкочастотный сдвиг выборки по Y (3D-шум PW на warp_scale) сбивает
//       прямые вертикальные столбы, не ломая высотный профиль.
//   Всё выключено → побитово C4. Формулы освещения/маски/марша не изменены.
// ФАЗА C, ЭТАП C4 (история): художественная настройка 1 — «крупнее и реже»: weather mask (§3.1 ТЗ) —
// крупномасштабные зоны без облаков из той же PW-текстуры на периоде weather_scale:
// вычитание из n до порога coverage, поэтому формы масс не страдают, а небо становится
// островным. Выкл (use_weather_mask=false) → побитово C3. Крупность масс — параметры
// cloud_base_scale/coverage/offset (крутятся в меню 9).
// ФАЗА C, ЭТАП C2 (история): ВИДИМОЕ СОЛНЦЕ — аналитический диск источника света + гало в фоне
// (sun_visible/sun_size/sun_softness/sun_intensity/sun_halo_strength/sun_halo_power).
// Диск рисуется в ФОНОВОМ члене ДО композита с облаками → облака честно закрывают его
// через transmittance (sun·T); серебристая кромка HG остаётся. В subpass-ветке диск
// считается в full-res (не размывается tier'ом); в cubemap-ветке присутствует
// (согласованные блики/ambient). Диагноз-режимы 1-12 солнце НЕ показывают (чистота вкладов).
// ФАЗА B, ЭТАП B6 (содержание): ПРОИЗВОДИТЕЛЬНОСТЬ — subpasses (half/quarter-res) с premultiplied-
// контрактом (rgb=накопленное рассеяние, ALPHA=1−T), cheap-композит в full-res,
// упрощённая ветка AT_CUBEMAP_PASS, compile-time tier (#define SKY_TIER + патч кода
// стендом), профили Performance/Balanced/Quality/Reference.
// МЕХАНИКА (проверено docs 4.7 + спайком B6): render_mode use_half/quarter_res_pass
// лишь РАЗРЕШАЕТ pass; ветвление — built-in-булевы AT_HALF_RES_PASS/AT_QUARTER_RES_PASS/
// AT_CUBEMAP_PASS; результат subpass читается в full-res как HALF_RES_COLOR/
// QUARTER_RES_COLOR (vec4: rgb + a). Без ветвления AT_* режимы_compile-pass не дают
// эффекта (спайк B6: cost и пиксли идентичны) — поэтому B4-замеры «нет разницы».
// ФАЗА B, ЭТАП B5 (история): ДИАГНОСТИКА — единый cloud_debug_mode 0-8 (§7 промта) + геометрические
// 9-12 (наследие A3), ОДИН марш на все режимы, честный пропуск вычислений uniform-гейтами
// ДО вызова дорогих функций (таблица гейтов — README §1); legacy debug_mode удалён
// (legacy 5/6 = cdm 0/2, legacy preview = cdm 1 без gain).
// Формулы освещения B4/B3 и физика A3-A7 НЕ изменены.
// ФАЗА B, ЭТАП B4 (история): ОСВЕЩЕНИЕ ч.2 — self-shadowing (марш к источнику), powder effect,
// approximate multiple scattering, atmospheric perspective. Каждый эффект — независимый
// uniform-переключатель (§4.3 промта) с честным пропуском вычислений при выключении
// (uniform-гейт ДО вызова дорогой функции; полная диагностика пропуска — B5).
// Наследие: A3-A6 геометрия/марш/композитинг, A7 профиль, B1 текстуры, B2 shaping,
// B3 освещение ч.1 (sun+HG+ambient).
//
// ИСТОРИЯ КОМПОНЕНТА (кумулятивно):
//   A3-A6: геометрия слоя, марш Beer-Lambert, композитинг (сохранены, регрессия).
//   A7:    высотный профиль кучевых (плоское основание + купольный верх).
//   B1:    3D-текстурный конвейер плотности (Perlin-Worley 128³ + Worley 32³,
//          sampler3D; текстуры собираются из .bin через CloudTextureLoader —
//          персистенция ImageTexture3D через ResourceSaver в 4.7-stable сломана).
//   B2:    density shaping — эрозия краёв, вертикальная связность, distance-fade.
//   B3:    освещение ч.1: sun+HG+ambient-градиент, переключаемые, без хардкода фаз.
//   B4:    освещение ч.2 (этот этап). Плотность/геометрия/view-марш НЕ изменены:
//          при выключенных B4-эффектах (use_self_shadow/use_powder/use_ms/
//          use_atmo_perspective = false) марш ПОБИТОВО совпадает с B3, а при рецепте
//          «изотропный единичный свет» B3 — с B2. Регрессия проверяется зеркалом.
//
// МОДЕЛЬ ОСВЕЩЕНИЯ B4:
//   L(p, view) = cloud_color · [ sun · phase(cosθ) · T_light(p) · powder(d)
//                              + ambient(p.y) · cloud_ambient_energy
//                              + ms(p, T_light, d) ]
//   T_light — Beer-Lambert пропускание короткого марша к источнику (self-shadowing,
//   light_steps 3/4/6 по §4.2 промта, shadow_ray_length — длина марша);
//   powder(d) = mix(1, 1−exp(−2d), powder_strength) — затемнение тонких краёв в
//   контровом свете (аппроксимация документирована: множитель от локальной плотности,
//   не зависит от длины шага → сходимость марша не ломается);
//   ms = ms_strength · [ light_color·strength·MS_SUN_GAIN·(1−T_light)   (солнечный
//        диффузный проник) + ambient(p.y)·energy·MS_AMB_GAIN·d ]        (ambient MS)
//        — изотропно, без дополнительного марша; при выключенном self-shadowing
//        солнечная часть MS = 0 (T_light≡1), документировано.
//   cosθ = dot(view, normalize(cloud_light_direction)) — направление НА источник
//   (конвенция продакшн-неба: cloud_light_direction/color/strength — те же имена,
//   что пишет TimeOfDayController из SkyPhaseProfile; Q7.33 подключится без переименований).
//   phase — Henyey-Greenstein, нормированная так, что phase(cosθ, g=0) ≡ 1
//   (игровая конвенция БЕЗ множителя 1/4π: изотропный случай точно воспроизводит
//   равномерное освещение B2; яркость калибруется cloud_light_strength).
//   ambient(p.y) = use_ambient_gradient ? mix(ground, sky, h) : sky,
//   h — доля высоты в слое [0,1] (низ слоя темнее/теплее, верх светлее/небеснее).
//   Atmospheric perspective: пост-смешение накопленного цвета облака к atmo_color
//   с фактором sstep(atmo_start, atmo_end, t_near) — дальние массы сливаются с
//   атмосферой; premultiplied-согласование сохраняется (alpha = 1−T не меняется):
//   cloudC = mix(cloudC, atmo_color·(1−T), f); COLOR = sky_color·T + cloudC.
//
// ДИАГНОСТИКА B5: uniform cloud_debug_mode, ОДИН марш на все режимы 0-8:
//   0 = финальный рендер (lit-марш + atmo-композит); 1 = базовая плотность (средняя d);
//   2 = T (Beer-Lambert); 3 = поле self-shadowing (взвешенное среднее T_light);
//   4 = знак вклада HG (серый = изотроп); 5 = снятое powder-ом прямое излучение;
//   6 = накопленный MS; 7 = накопленный ambient; 8 = фактор atmo-перспективы (без марша);
//   9-12 = геометрические режимы A3 БЕЗ марша: HIT/MISS-маска, t_near, длина пути,
//   чистое небо. Каждый режим показывает ИМЕННО исследуемый член (не цветовой фильтр).
//   ЧЕСТНЫЙ ПРОПУСК: гейты need_terms/need_shadow/need_powder/need_ms/need_amb —
//   uniform-ветвления ДО вызова дорогих функций (марш тени, члены освещения);
//   режимы 1-2 не считают освещение вовсе, 8-12 не считают марш.
//   Плейсхолдеры пропущенных членов: t_light=1, powder=1, ms=0, amb=0 (документировано).
//
// СОЗНАТЕЛЬНО ОТСУТСТВУЕТ (этап B6): профили качества и subpasses, AT_CUBEMAP_PASS-
// упрощение, jitter тени/TAA.
//
// ПЕРЕКЛЮЧАТЕЛИ (§4.3 промта — независимо включать/выключать каждый эффект):
//   use_hg_phase=false      → phase≡1 (изотроп, как B2 по угловой зависимости);
//   cloud_light_strength=0  → нет прямого света (остался ambient);
//   use_ambient_gradient=false → ambient постоянен (cloud_ambient_sky_color);
//   cloud_ambient_energy=0  → нет ambient (остался прямой свет).
//   Все переключатели — uniform-ветвления (одинаковы для всех пикселей кадра,
//   wave-дивергенции нет). Стенд: F1 (солнце вкл/выкл), F2 (HG), F3 (ambient-градиент).
//
// ЦВЕТА НЕ ХАРДКОДЯТСЯ (§2 промта): закат/сумерки/ночь — наборы значений uniform'ов
// (рецепты в README §5), в алгоритме плотности и освещения фазы не зашиты.
//
// МАСШТАБЫ (калиброваны в B1/B2, без изменений):
//   cloud_base_scale = 16000 м на период PW-текстуры → массы 1-3 км, воксел 125 м;
//   cloud_detail_scale = 1200 м на период Worley → выступы ~150 м, воксел 37.5 м.
//
// ВЕТЕР: cloud_offset (метры, мировое смещение поля) пишется с CPU (стенд/контроллер)
// — TIME в шейдере НЕ используется (radiance cubemap не дёргается каждый кадр).

uniform vec3 sky_color : source_color = vec3(0.32, 0.47, 0.68);	// фон: лучи без пересечения
uniform float cloud_layer_bottom = 1500.0;	// низ слоя, м (от плоскости камеры)
uniform float cloud_layer_top = 3500.0;		// верх слоя, м

// B5: единый диагностический режим (0-8 по §7 промта + 9-12 геометрия A3);
// клавиши стенда 0-8, F4 — цикл 0-8, F5 — цикл 9-12.
uniform float cloud_debug_mode = 0.0;
uniform vec3 debug_hit_color : source_color = vec3(1.0, 0.75, 0.25);	// геометрия 9-10
uniform float debug_distance_scale = 20000.0;	// нормировка дальностей режимов 10-11, м

// === B1: текстуры и параметры плотности (B2-shaping; в B3 без изменений) ===
uniform sampler3D noise_pw : repeat_enable, filter_linear;		// Perlin-Worley 128³ (base shape)
uniform sampler3D noise_worley : repeat_enable, filter_linear;	// Worley 32³ (деталь/выступы)
uniform vec3 cloud_color : source_color = vec3(0.95, 0.95, 0.97);	// альбедо/тон облака (B3: множитель освещения)
uniform float cloud_base_scale = 35500.0;		// метров на период PW-текстуры
uniform float cloud_detail_scale = 3000.0;		// метров на период Worley-текстуры
uniform float cloud_coverage = 0.23;			// порог ремапа (по распределению PW!)
uniform float cloud_softness = 0.17;			// мягкость краёв (окно ±)
uniform float cloud_detail_strength = 0.60;		// амплитуда модуляции порога деталью
uniform float cloud_erosion = 0.30;			// B2: эрозия краёв деталью (ядра масс сохраняются)
uniform float cloud_edge_contrast = 1.0;		// D3: контраст кромки (>1 твёрже силуэт; 1 = побитово D2)
uniform float detail_fade_start = 4000.0;		// B2: с этой дистанции деталь начинает гаситься
uniform float detail_fade_end = 12000.0;		// B2: с этой дистанции детали нет (лечение алиасинга марша)
uniform float cloud_vertical_stretch = 1.75;		// B2: во сколько раз PW тянется по Y (вертикальная связность)
uniform vec3 cloud_offset = vec3(0.0);			// мировое смещение поля, м (CPU-дрейф)

// === C9: окраска освещения под градиент ===
uniform bool use_sun_color_ramp = false;		// выкл → свет одним cloud_light_color (C8)
uniform vec3 ramp_near_color : source_color = vec3(0.95, 0.30, 0.25);	// розовый середняк
uniform vec3 ramp_far_color : source_color = vec3(0.70, 0.08, 0.08);	// красный вдали от солнца
uniform bool use_ambient_from_sky = false;		// выкл → ambient из cloud_ambient_sky_color (C8)
uniform float ambient_sky_gain = 1.2;			// множитель яркости зенита G(up) для ambient

// === C8: градиентное небо (5 стопов-данных, угловая сборка вокруг солнца) ===
uniform bool use_gradient_sky = true;			// выкл → плоский sky_color (C7)
uniform vec3 sky_horizon_color : source_color = vec3(0.42, 0.55, 0.75);
uniform vec3 sky_zenith_color : source_color = vec3(0.20, 0.35, 0.60);
uniform vec3 sky_antisolar_color : source_color = vec3(0.26, 0.30, 0.52);
uniform vec3 sky_band_mid : source_color = vec3(0.50, 0.68, 0.88);	// светло-голубое кольцо (средний радиус)
uniform vec3 sky_band_white : source_color = vec3(0.98, 0.96, 0.85);	// бело-жёлтое сияние вплотную к солнцу
uniform vec3 sky_band_pink : source_color = vec3(0.50, 0.60, 0.78);
uniform float sky_grad_sharp = 1.0;			// D3: резкость переходов палитры (>1 чётче зоны; 1 = побитово D2)

// === C7: distance curtain — чистый горизонт (вал у горизонта рассасывается) ===
uniform bool use_far_curtain = true;		// выкл → побитово C6
uniform float far_curtain_start = 12000.0;	// дистанция, с которой облака начинают таять, м
uniform float far_curtain_end = 24000.0;	// дистанция, за которой облаков нет, м

// === C5: ориентация масс: анизотропия по высоте, горизонтальное удлинение, y-warp ===
uniform bool use_height_anisotropy = true;	// выкл → stretch = cloud_vertical_stretch (C4)
uniform float aniso_base = 3.0;				// вертикальное вытяжение у основания (башни)
uniform float aniso_top = 0.70;				// вытяжение у верха (<1 = плоские шляпы)
uniform float cloud_horizontal_stretch = 1.4;	// >1 удлиняет массы по горизонтали
uniform float cloud_warp_strength = 220.0;	// амплитуда y-warp, м (0 = выкл)
uniform float cloud_warp_scale = 9000.0;		// период шума warp, м

// === C4: weather mask — крупномасштабные зоны без облаков («реже» без вреда формам) ===
uniform bool use_weather_mask = true;			// выкл → побитово C3
uniform float weather_scale = 30000.0;			// метров на период маски (пятна просветов)
uniform float weather_cut = 0.14;				// порог поля маски: ниже — зона без облаков
uniform float weather_soft = 0.06;				// мягкость границы зоны
uniform float weather_strength = 0.9;			// сила вычитания покрытия в зоне (1 = чисто)

// === B3: освещение — прямой источник (солнце/луна) ===
uniform vec3 cloud_light_direction = vec3(-0.75, 0.50, -0.43);	// направление НА источник (нормализуется; конвенция продакшн-неба)
uniform vec3 cloud_light_color : source_color = vec3(1.0, 0.97, 0.92);	// цвет источника (нейтральный дневной; закат/ночь — рецепты в README)
uniform float cloud_light_strength = 0.70;		// интенсивность прямого света (0 = выключен)
uniform bool use_hg_phase = true;			// Henyey-Greenstein вкл/выкл (false = изотроп phase≡1)
uniform float hg_g = 0.5;				// анизотропия HG: >0 вперёд, <0 назад; clamp ±0.9 в hg_phase()
uniform float hg_diffuse_mix = 0.45;			// D2: доля изотропного ответа в фазе (0 = чистый HG, вид D1)
uniform bool use_hg_dual = false;			// C5a: dual-lobe HG (выкл = одиночная доля, побитово B7)
uniform float hg_g2 = 0.25;				// C5a: анизотропия второй доли
uniform float hg_dual_mix = 0.5;			// C5a: вес второй доли 0..1 (0 = одиночная, 1 = только g2)

// === B3: освещение — ambient-градиент ===
uniform vec3 cloud_ambient_sky_color : source_color = vec3(0.55, 0.63, 0.82);		// ambient верха слоя (небесный)
uniform vec3 cloud_ambient_ground_color : source_color = vec3(0.25, 0.27, 0.34);	// ambient низа слоя (земной)
uniform float cloud_ambient_energy = 0.45;		// интенсивность ambient (0 = выключен)
uniform bool use_ambient_gradient = true;		// false = постоянный ambient (sky-цвет)

// === C2: видимое солнце (диск + гало источника света) ===
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

// === B4: self-shadowing (короткий марш к источнику) ===
uniform bool use_self_shadow = true;		// выкл → T_light≡1 (вид B3)
uniform float light_steps = 4.0;			// §4.2: Performance 3 / Balanced 4 / Quality 6 (clamp 1..16)
uniform float shadow_ray_length = 4500.0;	// длина марша к источнику, м (0 → T_light≡1)

// === B4: powder effect (контровые края) ===
uniform bool use_powder = true;			// выкл → powder≡1
uniform float powder_strength = 0.3;		// 0..1: доля эффекта (D2: ослаблено с 0.60 — контровые ярче)

// === B4: approximate multiple scattering (изотропно, без доп. марша) ===
uniform bool use_ms = true;				// выкл → ms≡0
uniform float ms_strength = 0.65;			// 0..1; доли MS ниже — uniform'ы (D2)
uniform float ms_sun_gain = 0.45;			// D2: доля солнечного диффузного проникновения (была 0.30 const)
uniform float ms_amb_gain = 0.60;			// D2: доля ambient-члена MS (была 0.60 const)
uniform bool use_ms_order2 = false;			// C5b: MS 2-го порядка (выкл = побитово B7)

// === B4: atmospheric perspective (дальние массы → атмосфера) ===
uniform bool use_atmo_perspective = true;	// выкл → композит как в B3
uniform vec3 atmo_color : source_color = vec3(0.55, 0.65, 0.85);
uniform float atmo_start = 6000.0;			// t_near, с которого начинает действовать дымка, м
uniform float atmo_end = 26000.0;			// t_near, с которого облако полностью в дымке, м

// === A7: высотный профиль ===
uniform float height_base_fade = 0.15;			// доля слоя снизу: нарастание (плоское основание)
uniform float height_top_fade = 0.35;			// доля слоя сверху: купольный спад

// === A5: интегрирование ===
uniform float march_steps = 48.0;				// шаги марша режима 5 (clamp 8..256)
uniform float max_ray_length = 30000.0;			// предел длины интегрирования, м
uniform float extinction_scale = 0.0025;		// σ на единицу плотности, 1/м
uniform float early_exit_transmittance = 0.01;	// порог раннего завершения

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
uniform float hc_debug = 0.0;				// 0 выкл / 1 плотность / 2 альфа / 3 оптическая толщина

// Явный smoothstep (переносимость между бэкендами, A5).
float sstep(float lo, float hi, float x) {
	float t = clamp((x - lo) / (hi - lo), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// D3: резкость перехода палитры: симметричная S-кривая поверх sstep-окна.
// s=1 → ровно sstep (побитово D2); s>1 → переход сжимается к середине окна
// (зоны различимее, границы чётче); s<1 → плавнее. Концы окна сохраняются точно.
// CPU-зеркало: CloudsTestBench.sharp_mix().
float sharp_mix(float lo, float hi, float x, float s) {
	float b = sstep(lo, hi, x);
	if (s == 1.0) {
		return b;
	}
	float sc = max(s, 0.25);
	float u = pow(b, sc);
	float v = pow(1.0 - b, sc);
	return u / max(u + v, 1e-6);
}

// B3: фазовая функция Henyey-Greenstein, нормированная на изотроп=1 (без 1/4π).
// g=0 → phase≡1 точно; |g|→1 → острый пик, поэтому g жёстко clamp'ится ±0.9
// (знаменатель (1+g²-2g·cosθ)^1.5 ≥ (1-|g|)^1.5 > 0 — деление на ноль исключено).
// CPU-зеркало: CloudsTestBench.hg_phase().
float hg_phase(float cos_theta, float g) {
	float gg = clamp(g, -0.9, 0.9);
	float d = 1.0 + gg * gg - 2.0 * gg * cos_theta;
	return (1.0 - gg * gg) / (d * sqrt(d));
}

// B4: фиксированные доли approximate MS (документированы, не uniform'ы — см. README §3).
// D2: MS_SUN_GAIN/MS_AMB_GAIN стали uniform'ами (см. блок MS выше).
const float MS2_GAIN = 0.25;			// C5b: доля MS 2-го порядка (документирована)

// B3: доля высоты точки в слое [0,1] (тот же h, что в высотном профиле A7).
float layer_height_fraction(float y) {
	float thickness = max(cloud_layer_top - cloud_layer_bottom, 1e-4);
	return clamp((y - cloud_layer_bottom) / thickness, 0.0, 1.0);
}

// Плотность облаков (B1+B2; в B3 формула НЕ изменена — регрессия проверяется зеркалом).
// CPU-зеркало: CloudsTestBench.compute_density() (трилинейная выборка тех же .bin
// с тем же соглашением тексель-центров (i+0.5)/n — совпадение до float32-точности).
float cloud_density(vec3 p, float t) {
	vec3 pw = p + cloud_offset;
	// B2: distance-fade детали (эрозия + выступы): там, где сегмент марша длиннее
	// фич детали (дальние лучи), высокочастотная эрозия только алиасит — гасим её.
	float fade = 1.0 - sstep(detail_fade_start, detail_fade_end, t);
	float ero = cloud_erosion * fade;
	float str = cloud_detail_strength * (0.25 + 0.75 * fade);
	// C5: ориентация масс: stretch зависит от высоты в слое (башни внизу, шляпы вверху),
	// горизонтальное удлинение и y-warp против прямых столбов. Выкл → формула C4.
	vec3 pw2 = pw;
	if (cloud_warp_strength > 0.0) {
		float wn = texture(noise_pw, pw / cloud_warp_scale).r;
		pw2.y += (wn - 0.5) * 2.0 * cloud_warp_strength;
	}
	float hgt_a = layer_height_fraction(p.y);
	float stretch_eff = use_height_anisotropy
			? mix(aniso_base, aniso_top, sstep(0.15, 0.85, hgt_a))
			: cloud_vertical_stretch;
	float hs = max(cloud_horizontal_stretch, 0.05);
	vec3 q_base = vec3(pw2.x / hs, pw2.y / stretch_eff, pw2.z / hs) / cloud_base_scale;
	float shape = texture(noise_pw, q_base).r;
	float detail = texture(noise_worley, pw / cloud_detail_scale).r;
	// B2: эрозия краёв + выступы B1 (пороговая модуляция деталью).
	float n = shape - ero * (1.0 - detail) * (1.0 - shape)
			+ str * (detail - 0.5);
	// C4: weather mask: крупномасштабное поле той же PW-текстуры; там, где оно ниже
	// weather_cut, покрытие вычитается до порога — целые зоны становятся чистым небом.
	// Маска движется вместе с полем (pw включает cloud_offset), форм масс не касается.
	if (use_weather_mask) {
		float w = texture(noise_pw, pw / weather_scale).r;
		float clear = 1.0 - sstep(weather_cut - weather_soft, weather_cut + weather_soft, w);
		n -= clear * weather_strength * (cloud_coverage + cloud_softness + 0.1);
	}
	float d = sstep(cloud_coverage - cloud_softness, cloud_coverage + cloud_softness, n);
	// D3: твёрдость кромки — контрастная кривая вокруг 0.5: 1.0 → побитово D2;
	// >1 → полоса перехода прозрачность→плотность уже, силуэт твёрже и читаемее.
	if (cloud_edge_contrast != 1.0) {
		d = clamp((d - 0.5) * max(cloud_edge_contrast, 0.0) + 0.5, 0.0, 1.0);
	}
	// высотный профиль A7 (h через общий helper B3 — математика идентична B2)
	float hgt = layer_height_fraction(p.y);
	float profile = sstep(0.0, height_base_fade, hgt) * (1.0 - sstep(1.0 - height_top_fade, 1.0, hgt));
	// C7: distance curtain — дальние облака (и их тени) растворяются до нуля.
	float curtain = use_far_curtain
			? 1.0 - sstep(far_curtain_start, far_curtain_end, t)
			: 1.0;
	return d * profile * curtain;
}

// D2: размытое пятно света там, где облако закрыло солнце: ∝ закрытости alpha(=1−T)
// и угловой близости к источнику (широкий pow). При alpha=0 (чисто) = 0 — диск резкий.
vec3 sun_blur_glow(vec3 dir, float alpha_occ) {
	if (!use_sun_blur || !sun_visible) {
		return vec3(0.0);
	}
	vec3 ldir = cloud_light_direction / max(length(cloud_light_direction), 1e-5);
	float cosang = dot(dir, ldir);
	return sun_disk_color * (sun_blur_strength * pow(max(cosang, 0.0), sun_blur_power)) * alpha_occ;
}

// C8: градиент неба G(dir): вертикаль + угловые кольца вокруг солнца (см. шапку).
// CPU-зеркало: CloudsTestBench.compute_sky_gradient().
vec3 sky_gradient(vec3 dir, vec3 sundir) {
	float t = dot(dir, sundir);
	// D3: все окна палитры — через sharp_mix (sky_grad_sharp=1 → побитово D1/D2).
	vec3 base = mix(sky_horizon_color, sky_zenith_color, sharp_mix(0.02, 0.35, dir.y, sky_grad_sharp));
	base = mix(base, sky_antisolar_color, sharp_mix(-0.20, -0.80, t, sky_grad_sharp));
	base = mix(base, sky_band_mid, sharp_mix(0.10, 0.60, t, sky_grad_sharp));
	base = mix(base, sky_band_pink, sharp_mix(0.70, 0.92, t, sky_grad_sharp));
	base = mix(base, sky_band_white, sharp_mix(0.92, 0.995, t, sky_grad_sharp));
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

// B4: пропускание прямого света — Beer-Lambert вдоль короткого марша к источнику.
// Произведение exp по шагам тождественно exp(−σ·Σd·seg), поэтому результат стабилен
// к числу шагов (сходимость проверена зеркалом). Ранний обрыв по σ·Σ > ln(100)
// (T_light < 0.01) — честный пропуск оставшихся сэмплов.
// CPU-зеркало: CloudsTestBench.compute_light_transmittance().
float light_transmittance(vec3 p, vec3 ldir, float steps_cap) {
	int steps = int(clamp(min(light_steps, steps_cap), 1.0, 16.0));
	float seg = shadow_ray_length / float(steps);
	if (seg <= 0.0) {
		return 1.0;
	}
	const float SIGMA_LIMIT = 4.60517;	// ln(100): T_light < 0.01
	float sigma = 0.0;
	for (int i = 0; i < steps; i++) {
		vec3 sp = p + ldir * ((float(i) + 0.5) * seg);
		sigma += cloud_density(sp, length(sp)) * seg;
		if (sigma * extinction_scale > SIGMA_LIMIT) {
			break;
		}
	}
	return exp(-sigma * extinction_scale);
}

// B4: члены радиации точки облака (sun с тенью и powder'ом / ambient / MS).
// view_dir — НОРМАЛИЗОВАННОЕ направление луча; d — локальная плотность (уже с профилем).
// Отключённые эффекты НЕ вычисляются (uniform-гейт до вызова: light_transmittance
// вызывается только при use_self_shadow && strength>0). CPU-зеркало:
// CloudsTestBench.compute_radiance_terms_b4().
void cloud_radiance_terms(vec3 p, vec3 view_dir, float d,
		bool do_shadow, bool do_powder, bool do_ms, bool do_amb, float ls_cap,
		out vec3 sun_o, out vec3 amb_o, out vec3 ms_o,
		out float t_light_o, out float powder_o, out vec3 sun_nopow_o) {
	// Прямой свет: направление нормализуется с guard'ом (нулевой вектор → cosθ=0, без NaN).
	vec3 ldir = cloud_light_direction / max(length(cloud_light_direction), 1e-5);
	float cos_theta = dot(view_dir, ldir);
	// C9: рампа цвета солнца по угловому удалению взгляда от солнца.
	vec3 sun_col = cloud_light_color;
	if (use_sun_color_ramp) {
		sun_col = mix(mix(ramp_far_color, ramp_near_color, sstep(0.30, 0.80, cos_theta)),
				cloud_light_color, sstep(0.93, 0.995, cos_theta));
	}
	// C5a: dual-lobe HG — смесь двух нормированных долей (изотропность каждой сохранена).
	float phase = 1.0;
	if (use_hg_phase) {
		float p1 = hg_phase(cos_theta, hg_g);
		phase = use_hg_dual
				? mix(p1, hg_phase(cos_theta, hg_g2), clamp(hg_dual_mix, 0.0, 1.0))
				: p1;
	}
	// D2: доля изотропного ответа: освещённые грани белее с любых углов взгляда.
	phase = mix(phase, 1.0, clamp(hg_diffuse_mix, 0.0, 1.0));
	// B4/B5: self-shadowing — марш к источнику только когда нужен И эффект включён
	// (гейт do_shadow приходит из таблицы режимов sky(), use_* — из переключателей).
	float t_light = 1.0;
	if (do_shadow && use_self_shadow && cloud_light_strength > 0.0) {
		t_light = light_transmittance(p, ldir, ls_cap);
	}
	// B4/B5: powder — гейт do_powder уже включает use_powder (таблица режимов sky()).
	float powder = 1.0;
	if (do_powder) {
		powder = mix(1.0, 1.0 - exp(-2.0 * d), powder_strength);
	}
	sun_nopow_o = sun_col * (cloud_light_strength * phase) * t_light;
	sun_o = sun_nopow_o * powder;
	// Ambient: градиент земля→небо по доле высоты в слое (или константа, если выключен).
	// C9: ambient-верх может браться из зенита градиента неба (G(up)·gain).
	vec3 amb_top = cloud_ambient_sky_color;
	if (use_ambient_from_sky) {
		amb_top = (use_gradient_sky ? sky_gradient(vec3(0.0, 1.0, 0.0), ldir) : sky_color) * ambient_sky_gain;
	}
	vec3 amb_col = use_ambient_gradient
			? mix(cloud_ambient_ground_color, amb_top, layer_height_fraction(p.y))
			: amb_top;
	amb_o = do_amb ? amb_col * cloud_ambient_energy : vec3(0.0);
	// B4: approximate MS — изотропно: солнечный диффузный проник туда, где прямой луч
	// погашен (1−T_light), плюс ambient-член, гейтнутый локальной плотностью.
	ms_o = vec3(0.0);
	if (do_ms) {
		ms_o = ms_strength * (sun_col * cloud_light_strength * (ms_sun_gain * (1.0 - t_light))
				+ amb_col * cloud_ambient_energy * (ms_amb_gain * d));
	}
	t_light_o = t_light;
	powder_o = powder;
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

// B6: единая логика режимов (B5) с контрактом subpass:
//   rgb_o  — для режима 0: ПРЕМУМНОЖЕННОЕ накопленное рассеяние (включая atmo-композит);
//            для режимов 1-12: цвет диагностики/геометрии как есть;
//   alpha_o — режим 0: 1−T (покрытие); режимы 1-12: 1.0 (непрозрачная диагностика).
// cheap=true (ветка cubemap): марш ≤32 шагов и марш тени ≤2 шагов (§8 промта:
// упрощение cubemap-ветки без грубых скачков — модель освещения та же).
void sky_modes(vec3 dir, bool hit, float t_near, float t_far, bool cheap, vec3 bg,
		out vec3 rgb_o, out float alpha_o) {
	float cdm = cloud_debug_mode;

	// Геометрические режимы 9-12 (A3) — марш и освещение НЕ вычисляются вовсе.
	if (cdm > 8.5) {
		if (cdm < 9.5) {
			rgb_o = hit ? debug_hit_color : bg;
		} else if (cdm < 10.5) {
			if (hit) {
				float d = clamp(t_near / debug_distance_scale, 0.0, 1.0);
				rgb_o = mix(debug_hit_color, vec3(0.25, 0.05, 0.05), d);
			} else {
				rgb_o = bg;
			}
		} else if (cdm < 11.5) {
			if (hit) {
				float th = clamp((t_far - t_near) / debug_distance_scale, 0.0, 1.0);
				rgb_o = mix(vec3(0.15, 0.05, 0.20), vec3(1.0), th);
			} else {
				rgb_o = bg;
			}
		} else {
			rgb_o = bg;
		}
		alpha_o = 1.0;
		return;
	}

	// atmo-фактор нужен только режимам 0 и 8 (sstep дёшев, но гейт честный).
	float atmo_f = 0.0;
	if (cdm < 0.5 || cdm > 7.5) {
		atmo_f = use_atmo_perspective ? sstep(atmo_start, atmo_end, t_near) : 0.0;
	}
	if (cdm > 7.5) {
		rgb_o = vec3(atmo_f);		// 8: фактор atmo — марш НЕ выполняется
		alpha_o = 1.0;
		return;
	}
	if (!hit) {
		if (cdm < 0.5) {
			rgb_o = vec3(0.0);			// 0: фон проходит через alpha=0
			alpha_o = 0.0;
		} else if (cdm < 1.5) {
			rgb_o = vec3(0.0);
			alpha_o = 1.0;
		} else if (cdm < 2.5) {
			rgb_o = vec3(1.0);			// 2: T=1
			alpha_o = 1.0;
		} else if (cdm < 3.5) {
			rgb_o = vec3(1.0);			// 3: тени нет
			alpha_o = 1.0;
		} else if (cdm < 4.5) {
			rgb_o = vec3(0.5);			// 4: HG нулевой
			alpha_o = 1.0;
		} else {
			rgb_o = vec3(0.0);			// 5-7: вкладов нет
			alpha_o = 1.0;
		}
		return;
	}

	// ТАБЛИЦА ГЕЙТОВ (B5): uniform-ветвления до вызова дорогих функций.
	bool need_terms = (cdm < 0.5) || (cdm > 2.5 && cdm < 7.5);
	bool need_shadow = (cdm < 0.5) || (cdm > 2.5 && cdm < 6.5);
	bool need_powder = (cdm < 0.5) || (cdm > 3.5 && cdm < 5.5);
	bool need_ms = (cdm < 0.5) || (cdm > 5.5 && cdm < 6.5);
	bool need_amb = (cdm < 0.5) || (cdm > 6.5 && cdm < 7.5);
	float ls_cap = cheap ? 2.0 : 16.0;

	int steps = int(clamp(cheap ? min(march_steps, 32.0) : march_steps, 8.0, 256.0));
	float t_end = min(t_far, t_near + max_ray_length);	// ограничение длины
	float seg = (t_end - t_near) / float(steps);
	float transmittance = 1.0;
	float dsum = 0.0;
	float used_f = 0.0;
	float wsum = 0.0;
	float tl_w = 0.0;
	float hg_sig = 0.0;
	float pow_rem = 0.0;
	vec3 sun_acc = vec3(0.0);
	vec3 amb_acc = vec3(0.0);
	vec3 ms_acc = vec3(0.0);
	if (seg > 0.0) {	// защита от нулевой/отрицательной длины
		for (int i = 0; i < steps; i++) {
			float t = t_near + (float(i) + 0.5) * seg;
			vec3 p = dir * t;
			float d = cloud_density(p, t);
			dsum += d;
			used_f += 1.0;
			float step_tr = exp(-d * extinction_scale * seg);
			float w = transmittance * (1.0 - step_tr);
			wsum += w;
			if (need_terms) {
				vec3 sun_t; vec3 amb_t; vec3 ms_t; vec3 sun_np_t; float tl; float pwd;
				cloud_radiance_terms(p, dir, d, need_shadow, need_powder, need_ms, need_amb, ls_cap,
						sun_t, amb_t, ms_t, tl, pwd, sun_np_t);
				// C5b: MS 2-го порядка — растёт с глубиной от освещённого края по ходу луча
				// (1−T_view) и с погашением прямого луча (1−T_light); без дополнительных маршей.
				vec3 ms2_t = vec3(0.0);
				if (use_ms_order2) {
					ms2_t = MS2_GAIN * cloud_light_color * cloud_light_strength	// вне функции освещения: без рампы (как в C9)
							* ((1.0 - tl) * (1.0 - transmittance));
				}
				sun_acc += w * sun_t;
				amb_acc += w * amb_t;
				ms_acc += w * (ms_t + ms2_t);	// режим 6 показывает MS суммарно (оба порядка)
				tl_w += w * tl;
				vec3 sun_iso = cloud_light_color * (cloud_light_strength * (tl * pwd));
				hg_sig += w * dot(sun_t - sun_iso, vec3(0.33333));
				pow_rem += w * dot(sun_np_t - sun_t, vec3(0.33333));
			}
			transmittance *= step_tr;
			if (transmittance < early_exit_transmittance) {
				break;	// раннее завершение
			}
		}
	}
	float wguard = max(wsum, 1e-6);
	if (cdm < 0.5) {
		// 0: premultiplied-контракт subpass: rgb = рассеяние (с atmo), alpha = 1−T
		vec3 cloudC = (sun_acc + amb_acc + ms_acc) * cloud_color;
		cloudC = mix(cloudC, atmo_color * (1.0 - transmittance), atmo_f);
		rgb_o = cloudC;
		alpha_o = 1.0 - transmittance;
	} else if (cdm < 1.5) {
		rgb_o = vec3(dsum / max(used_f, 1.0));
		alpha_o = 1.0;
	} else if (cdm < 2.5) {
		rgb_o = vec3(transmittance);
		alpha_o = 1.0;
	} else if (cdm < 3.5) {
		rgb_o = vec3(tl_w / wguard);
		alpha_o = 1.0;
	} else if (cdm < 4.5) {
		rgb_o = vec3(0.5 + 0.25 * clamp(hg_sig / wguard, -2.0, 2.0));
		alpha_o = 1.0;
	} else if (cdm < 5.5) {
		rgb_o = vec3(pow_rem / wguard);
		alpha_o = 1.0;
	} else if (cdm < 6.5) {
		rgb_o = ms_acc;
		alpha_o = 1.0;
	} else {
		rgb_o = amb_acc;
		alpha_o = 1.0;
	}
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
// CPU-зеркало: CloudsTestBench.compute_hc_density().
float hc_density(vec3 p) {
	vec3 q = hc_sample_coord(p);
	float shape = texture(noise_pw, q / max(hc_scale, 1.0)).r;
	float field = texture(noise_pw, q / max(hc_field_scale, 1.0)).r;
	float cov = clamp(hc_coverage + hc_field_amp * (field - 0.5) * 2.0, 0.0, 1.0);
	float soft = max(hc_softness, 1e-4);
	return sstep(cov - soft, cov + soft, shape);
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
	return hc_color * a;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float t_near = 0.0;
	float t_far = 0.0;
	bool hit = layer_interval(dir, cloud_layer_bottom, cloud_layer_top, t_near, t_far);
	vec3 rgb;
	float alpha;
	// SKYHC-1: диагностика вуали (hc_debug 1-3) — отдельный честный пропуск: ни марша
	// кучевых, ни солнца (показываем ИМЕННО член слоя, как режимы 8-12 у кучевых).
	// return в sky() запрещён движком → структура ветвлением.
	bool hc_diag = hc_debug > 0.5 && !AT_HALF_RES_PASS && !AT_QUARTER_RES_PASS;
	// C2: солнце — только в финальном режиме 0 и только в full-res/cubemap-ветках
	// (subpass хранит лишь облака; диагностики 1-12 остаются чистыми).
	vec3 sunbg = vec3(0.0);
	if (!hc_diag && cloud_debug_mode < 0.5 && sun_visible && !AT_HALF_RES_PASS && !AT_QUARTER_RES_PASS) {
		sunbg = sun_background(dir);
	}
	// C8: фон неба: градиент G(dir) или плоский sky_color
	vec3 ldir_bg = cloud_light_direction / max(length(cloud_light_direction), 1e-5);
	vec3 bg = use_gradient_sky ? sky_gradient(dir, ldir_bg) : sky_color;
	// SKYHC-1: вуаль считается ТОЛЬКО в ветках, где собирается итоговый кадр: subpass
	// хранит исключительно кучевые (контракт B6 не меняется).
	vec3 hc_rgb = vec3(0.0);
	float hc_a = 0.0;
	float hc_d = 0.0;
	float hc_tau = 0.0;
	if (!AT_HALF_RES_PASS && !AT_QUARTER_RES_PASS) {
		hc_rgb = hc_evaluate(dir, hc_a, hc_d, hc_tau);
	}
	// SKYHC-1: небо+солнце, ослабленные вуалью (премноженный композит). При выключенном
	// слое hc_a=0 и hc_rgb=0 → base = (bg + sunbg)·1.0 + 0.0 → побитово D3.
	vec3 base = (bg + sunbg) * (1.0 - hc_a) + hc_rgb;
	if (hc_diag) {
		COLOR = hc_debug < 1.5 ? vec3(hc_d) : (hc_debug < 2.5 ? vec3(hc_a) : vec3(clamp(hc_tau, 0.0, 1.0)));
	} else if (AT_HALF_RES_PASS || AT_QUARTER_RES_PASS) {
		// B6: дорогой марш живёт ЗДЕСЬ (1/4 или 1/16 пикселей); контракт rgb+alpha.
		sky_modes(dir, hit, t_near, t_far, false, bg, rgb, alpha);
		COLOR = rgb;
		ALPHA = alpha;
	} else if (AT_CUBEMAP_PASS) {
		// B6: упрощённая ветка radiance cubemap (§8): та же модель освещения,
		// марш ≤32 шагов, марш тени ≤2 шагов; автономна (не читает subpass).
		sky_modes(dir, hit, t_near, t_far, true, bg, rgb, alpha);
		COLOR = mix(base, rgb, alpha) + sun_blur_glow(dir, alpha);	// C2 + D2 blur + SKYHC-1
	} else {
		// Full-res background: cheap-композит из subpass (или марш в tier 0).
		#if SKY_TIER == 0
		sky_modes(dir, hit, t_near, t_far, false, bg, rgb, alpha);
		COLOR = mix(base, rgb, alpha) + sun_blur_glow(dir, alpha);
		#elif SKY_TIER == 1
		vec4 sub = HALF_RES_COLOR;
		COLOR = mix(base, sub.rgb, sub.a) + sun_blur_glow(dir, sub.a);
		#else
		vec4 sub = QUARTER_RES_COLOR;
		COLOR = mix(base, sub.rgb, sub.a) + sun_blur_glow(dir, sub.a);
		#endif
	}
}
