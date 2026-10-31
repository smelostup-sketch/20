// ============================================================================
// SkyVeil.gdshaderinc — КОМПОНЕНТ вуали Q7.34 (Sky3.2.7, шаг S10)
// ============================================================================
// Происхождение: донор V4 `SKYHC-DS.txt` (senior rewrite SKYHC-5), имена hc_*/DS_*
// сохранены (совместимость со стендом/архивом). Правки по спецификации
// ПЛАН_небо_S2_Q7.34.md §3.2 (все три):
//   1. Мировой якорь УДАЛЁН, origin = vec3(0.0) всегда: builtin-позиция кадра по
//      документации движка инвалидирует radiance cubemap при каждом движении
//      камеры; плите на 6 км мировая привязка визуально ничего не даёт.
//   2. Потолок DS_hc_max_sample_dist → const (численная страховка, не ручка).
//   3. Свет вуали — 4.1.3 (этап 04, план света §4.5/v2 §5): ЕДИНАЯ угловая
//      палитра hc_angular_palette() по mu = dot(view, sun); зоны Anti-Solar /
//      Transition / Solar, цвета и границы mu — ДАННЫЕ (AtmosphereLighting-
//      Profile → State → CirrusVeilBinding). Старая 3-цветная рампа veil_ramp_*
//      (L1/L2/L3) слита в палитру: «разная удалённость вуали от соляра даёт
//      разные цвета» (задача 2) сохранено, одна рампа живёт в модуле.
//
// Композит (согласован с заказчиком 30.10.2026): SCENE-LINEAR, до тонмапа —
// вуаль участвует в той же цепи, что купол/солнце/луна/звёзды (ВУАЛЬ_план §3).
//
// Контракт с хостом (объявить ДО #include):
//   (Sky3.2.14, H1) uniform cloud_light_direction УДАЛЁН: направление света
//   вуали = sk_sun_dir (геометрия солнца, единый источник), заглушки нет
//   (4.1.3, этап 04) остальной контракт хоста cloud_light_color/strength и
//   cloud_ambient_sky_color/energy УДАЛЁН: uniform'ы освещения объявляет
//   САМ модуль (hc_sun_*, hc_ambient_*, hc_palette_* — см. ниже), пишет их
//   событийно CirrusVeilBinding (AtmosphereShaderBindingComponent) из
//   AtmosphereLightingState (план света §4.4: имена — данные сцены).
//
// Интеграция в `void sky()` хоста (SkyEnvironment.gdshader, секция «ВУАЛЬ»):
//   гейт hc_enabled=false (дефолт) → DS_veil_composite не вызывается хостом:
//   ноль выборок текстуры, кадр ПОБИТОВО равен небу без вуали (приёмка S10/S11).
//
// ============================================================================

// --- Текстуры вуали ---
uniform sampler3D noise_pw     : repeat_enable, filter_linear;  // Perlin-Worley 128^3
uniform sampler3D noise_worley : repeat_enable, filter_linear;  // Worley 32^3

// --- Uniform'ы вуали (имена сохранены) ---
uniform bool  hc_enabled           = false;    // ГЕЙТ S10: false = ноль выборок текстуры, кадр побитово прежний
uniform float hc_layer_bottom      = 18000.0;  // Sky3.2.11: плита поднята ×3 (приказ заказчика): 6 км -> 18 км
uniform float hc_layer_top         = 21600.0;  // Sky3.2.11: 7.2 км -> 21.6 км (толщина та же, 3.6 км)
uniform float hc_scale             = 60000.0;
uniform float hc_stretch           = 3.2;     // Sky3.2.13: перистые гряды (образец 233/234: 3.5); непрерывность уже рвут break/fiber
uniform float hc_stretch_angle_deg = 25.0;
uniform float hc_field_scale       = 260000.0;
uniform float hc_field_amp         = 0.60;
uniform float hc_coverage          = 0.52;    // Sky3.2.13: покрытие по образцу 233/234 (между 0.50 и реф 0.56)
uniform float hc_softness          = 0.30;    // Sky3.2.13: кромки определённее (реф 0.22), но не ленты (0.40 было размыто)
uniform float hc_tau_per_km        = 0.30;    // Sky3.2.13: присутствие пера (реф 0.35), тонкость сохранена
uniform float hc_curtain_start     = 18000.0;   // Sky3.2.10: полная альфа до path 18 км (~95 км дальности; заказчик: минимум 90 км)
uniform float hc_curtain_end       = 55000.0;   // Sky3.2.10: сход к нулю у истинного горизонта (path ~55 км), НЕ диском над головой
uniform vec3  hc_offset            = vec3(0.0);
uniform vec3  hc_color             : source_color = vec3(0.92, 0.93, 0.96);
uniform float hc_detail_strength   = 0.45;    // Sky3.2.13: размыв кромки Worley (реф 0.35 + запас на перистость)
uniform float hc_detail_scale      = 3000.0;
uniform bool  hc_use_lighting      = false;
uniform float hc_light_gain        = 1.0;
uniform float hc_ambient_gain      = 1.0;
uniform bool  hc_use_shadowing     = false;
uniform float hc_shadow_strength   = 0.75;
uniform float hc_shadow_max_dist   = 12000.0;
uniform float hc_debug             = 0.0;

// --- DS: новые ручки ---
uniform float DS_hc_jitter          = 0.0;      // 0 = выкл; >0 разбивает бандинг (дефолт 0: детерминизм приёмки «побитово»)
uniform float DS_hc_alpha_scale     = 1.0;      // 0..1, для fade / LOD

// --- Ветер (Sky3.2.11, вкладка «Погода»): адвекция характера, GPU-side ---
uniform bool  hc_wind_enabled      = false;   // гейт: выкл = детерминизм и побитово off
uniform float hc_wind_speed        = 15.0;    // м/с (сила ветра; высотный поток 0..60)
uniform float hc_wind_dir_deg      = 0.0;     // куда НЕСЁТ характер, азимут ° (конвенция азимутов сцены)

// --- Форма Sky3.2.12 (приказ п.2/п.4): разрывы покрытия и второй масштаб волокон ---
// Оба поля — НЕЗАВИСИМЫЕ низкие/средние частоты того же noise_pw (новых текстур нет):
// разрыв рвёт coverage крупными дырами, волокно ворпит КООРДИНАТУ до shape (доменный
// варп ломает геометрию полос, а не ложится шумом поверх — п.4).
uniform float hc_break_amount      = 0.40;     // 0..1: вспомогательные разрывы (основной ритм — field, как в образце)
uniform float hc_break_scale       = 120000.0; // масштаб разрывов, м (ниже field_scale 260 км: второй ритм дыр)
uniform float hc_fiber_amp         = 8000.0;   // амплитуда варпа волокон, м: крючья_uncinus как в образце 233/234
uniform float hc_fiber_scale       = 18000.0;  // масштаб волокон, м (средняя частота, самостоятельно)
// Ветер физичен (м/с), но плита 60 км: реальный дрейф неотличим от покоя.
// timelapse — честное ускорение времени дрейфа (данные, не костыль): v_eff = v * N.
uniform float hc_wind_timelapse    = 60.0;     // ×N к скорости дрейфа (таймлапс, 1 = реальное время)

// --- 4.1.3 (этап 04): контракт ОСВЕЩЕНИЯ вуали — владение модуля ----------
// Писатель — CirrusVeilBinding из AtmosphereLightingState (событийно, без
// polling); хост эти параметры больше не объявляет (v2 §3.2: никакого
// дублирования данных освещения). Направление — sk_sun_dir хоста (H1).
// Direct Lighting (v2 §3.1): действительный цвет и интенсивность Sun
// (интенсивность уже с profile.direct_multiplier — потребитель не множит).
uniform vec3  hc_sun_color      : source_color = vec3(1.0);
uniform float hc_sun_energy                  = 1.0;
// Ambient Environment (v2 §3.1): цветовая среда Sky Gradient (этап 03 —
// окружение пресета: зенит = col_light3). Дефолт — байт-значение старого
// контракта (col_light3/L3): вуаль не ослеплена до первой публикации state.
// Горизонт среды — для воздушной перспективы (v2 §7), подключается после
// замеров этапа 05 (curtain требует проверки на двойное затухание).
uniform vec3  hc_ambient_zenith : source_color = vec3(0.2078, 0.2863, 0.3725);
uniform float hc_ambient_strength            = 1.0;
// Veil Artistic Palette (v2 §5): три угловые зоны по mu + границы переходов.
// Дефолты класса — план света §4.1; проектные данные — Profiles/
// AtmosphereLightingProfile.tres (стартовые tint §4.5). Палитра — ОТТЕНОК
// прямого света, не источник: плотность/геометрию/оптическую толщину не
// трогает (v2 §5.2, план §4.5).
uniform vec3  hc_palette_anti_solar : source_color = vec3(0.42, 0.48, 0.68);
uniform vec3  hc_palette_transition : source_color = vec3(0.78, 0.76, 0.82);
uniform vec3  hc_palette_solar      : source_color = vec3(1.0, 0.83, 0.65);
uniform float hc_palette_anti_solar_mu       = -0.35;
uniform float hc_palette_solar_mu            = 0.75;
uniform float hc_palette_transition_position = 0.5;

// ============================================================================
// Внутренности
// ============================================================================

const float DS_HC_EPS = 1e-6;

// Кэш инвариантов на один вызов DS_veil_composite. Строится 1 раз на пиксель;
// экономит 6 делений и 2 тригонометрических вызова на каждый сэмпл плотности
// (а сэмплов по умолчанию 1 + до 2 на самозатенение).
struct DS_VeilCtx {
    float ca;              // cos(угла вытянутости)
    float sa;              // sin(угла вытянутости)
    float inv_stretch;
    float inv_scale;
    float inv_field_scale;
    float inv_detail_scale;
    float inv_break_scale;
    float inv_fiber_scale;
    float cov;
    float soft;
    float tau_per_km;
    float top;             // верх плиты (защищённый от вырождения)
    vec3  offset;
};

DS_VeilCtx DS_build_ctx() {
    DS_VeilCtx c;
    float a = radians(hc_stretch_angle_deg);
    c.ca = cos(a);
    c.sa = sin(a);
    c.inv_stretch       = 1.0 / max(hc_stretch, 0.05);
    c.inv_scale         = 1.0 / max(hc_scale, 1.0);
    c.inv_field_scale   = 1.0 / max(hc_field_scale, 1.0);
    c.inv_detail_scale  = 1.0 / max(hc_detail_scale, 1.0);
    c.inv_break_scale   = 1.0 / max(hc_break_scale, 1.0);
    c.inv_fiber_scale   = 1.0 / max(hc_fiber_scale, 1.0);
    c.cov        = clamp(hc_coverage, 0.0, 1.0);
    c.soft       = max(hc_softness, 1e-4);
    c.tau_per_km = max(hc_tau_per_km, 0.0);
    c.top        = hc_layer_bottom + max(hc_layer_top - hc_layer_bottom, 1e-4);
    c.offset     = hc_offset;
    return c;
}

// Явный smoothstep. Умеет обратный [lo, hi] — GLSL smoothstep для edge0>=edge1
// не определён, а нам это нужно (защита в depth-ветках).
float DS_sstep(float lo, float hi, float x) {
    float t = clamp((x - lo) / (hi - lo), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// Пересечение луча с плитой [bottom, top] в координатах origin.
// Возвращает false для: параллельного луча, взгляда вниз, камеры ниже слоя.
bool DS_layer_interval(vec3 dir, float bottom, float top, out float t_near, out float t_far) {
    t_near = 0.0; t_far = 0.0;
    if (abs(dir.y) <= DS_HC_EPS) return false;
    float t1 = bottom / dir.y;
    float t2 = top    / dir.y;
    t_near = max(min(t1, t2), 0.0);
    t_far  = max(t1, t2);
    return t_far > t_near;
}

// Поворот в систему растяжения, сжатие вдоль гряд, обратный поворот.
// Вся тригонометрия и 1/stretch взяты из ctx.
vec3 DS_veil_coord(vec3 p, DS_VeilCtx c) {
    vec3 q = p + c.offset;
    float x1 =  q.x * c.ca + q.z * c.sa;
    float z1 = -q.x * c.sa + q.z * c.ca;
    x1 *= c.inv_stretch;
    return vec3(x1 * c.ca - z1 * c.sa, q.y, x1 * c.sa + z1 * c.ca);
}

float DS_veil_density(vec3 p, DS_VeilCtx c) {
    vec3  q     = DS_veil_coord(p, c);
    // п.4: второй масштаб волокон — доменный варп: самостоятельная средняя частота
    // смещает координату ДО shape, нарушая геометрию полос изнутри (не оверлей).
    if (hc_fiber_amp > 0.0) {
        vec3 fib = texture(noise_pw, q * c.inv_fiber_scale).rgb;
        q += (fib - 0.5) * hc_fiber_amp;
    }
    float shape = texture(noise_pw, q * c.inv_scale).r;
    float field = texture(noise_pw, q * c.inv_field_scale).r;
    float cov   = clamp(c.cov + hc_field_amp * (field - 0.5) * 2.0, 0.0, 1.0);
    // п.2: крупномасштабные разрывы: независимое низкое поле рвёт coverage дырами,
    // сплошные полосы распадаются на неоднородные образования (смещённый оффсет
    // частоты — чтобы разрыв не совпадал фазой с field).
    if (hc_break_amount > 0.0) {
        float brk = texture(noise_pw, (q + vec3(0.31, 0.47, 0.17)) * c.inv_break_scale).r;
        cov = mix(cov, cov * DS_sstep(0.35, 0.75, brk), hc_break_amount);
    }
    float n     = shape;
    if (hc_detail_strength > 0.0) {
        vec3  q0     = p + c.offset;
        float det    = texture(noise_worley, q0 * c.inv_detail_scale).r;
        float w_edge = clamp(1.0 - abs(shape - cov) / c.soft, 0.0, 1.0);
        n = shape - hc_detail_strength * (det - 0.5) * 2.0 * c.soft * w_edge;
    }
    return DS_sstep(cov - c.soft, cov + c.soft, n);
}

// Пропускание внутри слоя. Две фиксированные стратификации (0.25 / 0.75).
// Детерминированно — джиттер здесь давал бы мерцание при движении камеры;
// джиттерится только основная выборка (DS_hc_jitter).
float DS_veil_shadow_transmittance(vec3 p, vec3 ldir, DS_VeilCtx c) {
    float max_dist = max(hc_shadow_max_dist, 0.0);
    if (max_dist <= DS_HC_EPS) return 1.0;

    float boundary_dist = max_dist;
    if (abs(ldir.y) > DS_HC_EPS) {
        float to_boundary = (ldir.y > 0.0)
            ? (c.top - p.y) / ldir.y
            : (hc_layer_bottom - p.y) / ldir.y;
        boundary_dist = min(boundary_dist, max(to_boundary, 0.0));
    }
    if (boundary_dist <= DS_HC_EPS) return 1.0;

    float d1 = DS_veil_density(p + ldir * (boundary_dist * 0.25), c);
    float d2 = DS_veil_density(p + ldir * (boundary_dist * 0.75), c);
    float mean_density = 0.5 * (d1 + d2);
    float tau_light    = mean_density * c.tau_per_km * (boundary_dist * 0.001);
    return exp(-tau_light * clamp(hc_shadow_strength, 0.0, 1.0));
}

// Освещение вуали (4.1.3, этап 04 — план света §4.5, v2 §4):
// Albedo × (Direct + Ambient); direct = цвет источника × художественный
// угловой tint × (интенсивность × shade × shadow_t). shadow_t умножается
// РОВНО один раз (v2 §6.2: двойное затенение запрещено); самозатенение —
// отдельный отключаемый блок hc_use_shadowing (v2 §6.3), базовая вуаль
// работает и без него.
const float DS_HC_TERM_LO     = -0.35;
const float DS_HC_TERM_HI     =  0.55;
const float DS_HC_SHADE_FLOOR =  0.60;

// Три цветовые зоны по угловой близости к солнечному направлению
// (план света §4.5, структура дословно; smoothstep → DS_sstep — явная
// формула модуля, идентична t²(3−2t), переносимость A5).
// mu = dot(view_direction, sun_direction); цвета — оттенки прямого света,
// а не источники эмиссии (v2 §5.2).
vec3 hc_angular_palette(vec3 view_dir, vec3 sun_dir) {
    float mu = clamp(
        dot(normalize(view_dir), normalize(sun_dir)),
        -1.0,
        1.0
    );

    float mu_range = max(
        hc_palette_solar_mu - hc_palette_anti_solar_mu,
        0.001
    );

    float t = clamp(
        (mu - hc_palette_anti_solar_mu) / mu_range,
        0.0,
        1.0
    );

    float middle = clamp(
        hc_palette_transition_position,
        0.05,
        0.95
    );

    if (t < middle) {
        float k = DS_sstep(0.0, middle, t);
        return mix(
            hc_palette_anti_solar,
            hc_palette_transition,
            k
        );
    }

    float k = DS_sstep(middle, 1.0, t);

    return mix(
        hc_palette_transition,
        hc_palette_solar,
        k
    );
}

vec3 DS_veil_lit_color(vec3 dir, vec3 ldir, vec3 sample_pos, DS_VeilCtx c) {
    float cos_theta = dot(dir, ldir);
    float shade     = mix(DS_HC_SHADE_FLOOR, 1.0,
                          DS_sstep(DS_HC_TERM_LO, DS_HC_TERM_HI, cos_theta));
    float shadow_t  = hc_use_shadowing
        ? DS_veil_shadow_transmittance(sample_pos, ldir, c)
        : 1.0;
    // План §4.5: sun_col — действительный цвет источника; palette_tint —
    // художественная модификация по направлению наблюдения; shadow_t —
    // пропускание прямого света; shade — направленная составляющая.
    vec3 palette_tint = hc_angular_palette(dir, ldir);
    vec3 direct  = hc_sun_color
        * palette_tint
        * (hc_sun_energy * shade * shadow_t)
        * hc_light_gain;
    vec3 ambient = hc_ambient_zenith * (hc_ambient_strength * hc_ambient_gain);
    return hc_color * (direct + ambient);
}

// ============================================================================
// Публичный API
// ============================================================================

// Композит вуали поверх фона+солнца хоста. Диагностику отдаёт всегда —
// вызывающий сам решает, рисовать её или финальный цвет.
vec3 DS_veil_composite(vec3 bg_sun, vec3 dir,
                       out float veil_alpha, out float veil_density, out float veil_tau) {
    veil_alpha = 0.0; veil_density = 0.0; veil_tau = 0.0;
    if (!hc_enabled) return bg_sun;

    DS_VeilCtx c = DS_build_ctx();
    vec3 origin = vec3(0.0);    // правка 1: без мировой привязки (cubemap не инвалидируется камерой)
    float t_near, t_far;
    if (!DS_layer_interval(dir,
                           hc_layer_bottom - origin.y,
                           c.top           - origin.y,
                           t_near, t_far)) {
        return bg_sun;
    }

    // Точка сэмпла: середина пути, джиттер (если включён) — против бандинга.
    // Sky3.2.11 (вариант A, без костылей): потолок дистанции УБРАН — сэмпл обязан
    // лежать ВНУТРИ плиты на любой дальности. Потолок тянул точку вниз по лучу
    // (высота семпла падала ниже плиты), и характер проецировался на «вертикальную
    // стену» вместо горизонтальной плиты («плоскость X -> плоскость Y» на скрине).
    // float32 хватает: координата текстуры = p/scale <= ~9, эпсилон < 0.1 м.
    float t_mid = 0.5 * (t_near + t_far);
    if (DS_hc_jitter > 0.0) {
        float r = fract(sin(dot(dir, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
        float u = clamp(0.5 + (r - 0.5) * DS_hc_jitter, 0.0, 1.0);
        t_mid = mix(t_near, t_far, u);
    }
    vec3 p = origin + dir * t_mid;
    // Ветер (Sky3.2.11): адвекция характера на GPU через TIME — НОЛЬ записей с CPU
    // (cubemap-гигиена 3.2.2 не нарушена). Выкл = сдвига нет, кадр детерминирован.
    if (hc_wind_enabled) {
        float wa = radians(hc_wind_dir_deg);
        p -= vec3(cos(wa), 0.0, sin(wa)) * (TIME * hc_wind_speed * hc_wind_timelapse);
    }

    float d    = DS_veil_density(p, c);
    float path = t_far - t_near;
    float tau  = d * c.tau_per_km * (path * 0.001);                     // м -> км
    float curtain = 1.0 - DS_sstep(hc_curtain_start, hc_curtain_end, path);
    float alpha = clamp((1.0 - exp(-tau)) * curtain * DS_hc_alpha_scale, 0.0, 1.0);

    veil_alpha   = alpha;
    veil_density = d;
    veil_tau     = tau;

    // H1 (Sky3.2.14): ЗАГЛУШКИ НЕТ — направление света вуали = геометрия солнца:
    // sk_sun_dir нормализован в хосте и пишется одним _direction() (п. 12.2).
    // Отдельных данных на направление света вуали не существует вовсе.
    vec3 ldir = sk_sun_dir;
    vec3 veil_rgb = hc_use_lighting
        ? DS_veil_lit_color(dir, ldir, p, c)
        : hc_color;

    // Премноженный композит: вуаль затеняет и фон, и солнце.
    return bg_sun * (1.0 - alpha) + veil_rgb * alpha;
}

// Диагностический цвет. 1-exp(-tau) — лог-шкала, читаемая в [0, ~5] без
// выжигания горизонта, в отличие от clamp(tau, 0, 1).
vec3 DS_veil_debug_color(float dbg, float a, float d, float tau) {
    if (dbg < 1.5) return vec3(d);
    if (dbg < 2.5) return vec3(a);
    return vec3(1.0 - exp(-tau));
}