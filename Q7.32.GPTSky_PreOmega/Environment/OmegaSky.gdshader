
shader_type sky;

uniform vec3 sun_direction = vec3(0.0, 0.0, -1.0);
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);

uniform bool sun_enabled = true;
uniform bool moon_enabled = false;

uniform vec3 color_solar : source_color = vec3(1.0, 0.72, 0.48);
uniform vec3 color_warm : source_color = vec3(0.55, 0.25, 0.24);
uniform vec3 color_mid : source_color = vec3(0.12, 0.16, 0.30);
uniform vec3 color_deep : source_color = vec3(0.025, 0.035, 0.095);
uniform vec3 color_antisolar : source_color = vec3(0.008, 0.012, 0.035);

uniform float solar_stop : hint_range(0.01, 0.5) = 0.14;
uniform float warm_stop : hint_range(0.1, 0.8) = 0.38;
uniform float deep_stop : hint_range(0.3, 0.99) = 0.78;

uniform float horizon_stretch : hint_range(1.0, 3.0) = 2.5;
uniform float stretch_power : hint_range(0.5, 4.0) = 1.5;

uniform float sky_energy : hint_range(0.0, 4.0) = 1.0;

uniform vec3 moon_color : source_color = vec3(0.35, 0.48, 0.75);
uniform float moon_intensity : hint_range(0.0, 1.0) = 0.12;
uniform float moon_spread : hint_range(1.0, 80.0) = 14.0;

uniform bool veil_enabled = false;
uniform vec3 veil_color : source_color = vec3(0.45, 0.52, 0.70);
uniform float veil_coverage : hint_range(0.0, 1.0) = 0.55;
uniform float veil_density : hint_range(1.0, 12.0) = 4.0;
uniform float veil_opacity : hint_range(0.0, 1.0) = 0.25;
uniform float veil_speed : hint_range(0.0, 0.1) = 0.003;


float hash3(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}


float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float n000 = hash3(i + vec3(0.0, 0.0, 0.0));
    float n100 = hash3(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash3(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash3(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash3(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash3(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash3(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash3(i + vec3(1.0, 1.0, 1.0));

    float x00 = mix(n000, n100, f.x);
    float x10 = mix(n010, n110, f.x);
    float x01 = mix(n001, n101, f.x);
    float x11 = mix(n011, n111, f.x);

    return mix(mix(x00, x10, f.y),
               mix(x01, x11, f.y), f.z);
}


float fbm3(vec3 p) {
    float value = 0.0;
    float amplitude = 0.5;

    for (int i = 0; i < 4; i++) {
        value += noise3(p) * amplitude;
        p *= 2.03;
        amplitude *= 0.5;
    }

    return value;
}


// Сферическое расстояние с управляемой анизотропией.
// В полюсах азимутальная ось выбирается безопасно.
float spherical_distance(vec3 d, vec3 s, float stretch) {
    s = normalize(s);

    vec3 azimuth_axis = vec3(s.z, 0.0, -s.x);
    float azimuth_length = length(azimuth_axis);

    if (azimuth_length < 0.0001) {
        azimuth_axis = vec3(1.0, 0.0, 0.0);
    } else {
        azimuth_axis /= azimuth_length;
    }

    vec3 meridian_axis = normalize(cross(s, azimuth_axis));

    float x = dot(d, azimuth_axis) / stretch;
    float y = dot(d, meridian_axis);
    float z = dot(d, s);

    return atan(length(vec2(x, y)), z) / PI;
}


vec3 gradient_color(float t) {
    float a = max(solar_stop, 0.001);
    float b = max(warm_stop, a + 0.001);
    float c = max(deep_stop, b + 0.001);

    vec3 col;

    if (t < a) {
        col = mix(color_solar, color_warm,
                  smoothstep(0.0, a, t));
    } else if (t < b) {
        col = mix(color_warm, color_mid,
                  smoothstep(a, b, t));
    } else if (t < c) {
        col = mix(color_mid, color_deep,
                  smoothstep(b, c, t));
    } else {
        col = mix(color_deep, color_antisolar,
                  smoothstep(c, 1.0, t));
    }

    return col;
}


void sky() {
    vec3 d = normalize(EYEDIR);
    vec3 s = normalize(sun_direction);
    vec3 m = normalize(moon_direction);

    // 1. Симметричное растяжение у горизонта,
    //    круглое поле у зенита и надира.
    float stretch_factor =
        pow(max(0.0, 1.0 - abs(s.y)), stretch_power);

    float stretch = mix(1.0, horizon_stretch, stretch_factor);

    float t = spherical_distance(d, s, stretch);
    vec3 col = gradient_color(clamp(t, 0.0, 1.0));

    // 2. Видимый диск соляра. Градиент остаётся
    //    привязанным к направлению даже при выключенном свете.
    if (sun_enabled) {
        float sun_dot = dot(d, s);
        float disc = smoothstep(
            cos(0.0060),
            cos(0.0035),
            sun_dot
        );

        col = mix(col, color_solar, disc);
    }

    // 3. Слабый локальный лунный градиент.
    if (moon_enabled) {
        float moon_dot = clamp(dot(d, m), -1.0, 1.0);
        float moon_lobe = exp(-(1.0 - moon_dot) * moon_spread);
        col = mix(col, moon_color,
                  clamp(moon_lobe * moon_intensity, 0.0, 1.0));
    }

    // 4. Независимая процедурная вуаль.
    if (veil_enabled) {
        vec3 wind = vec3(TIME * veil_speed, 0.0,
                         TIME * veil_speed * 0.37);

        float cloud_noise = fbm3(d * veil_density + wind);
        float clouds = smoothstep(
            veil_coverage,
            min(veil_coverage + 0.2, 1.0),
            cloud_noise
        );

        float opacity = clouds * veil_opacity;

        // Частичное затенение и изменение оттенка.
        col *= 1.0 - opacity * 0.45;
        col = mix(col, veil_color, opacity * 0.55);
    }

    COLOR = col * sky_energy;
}
