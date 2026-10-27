shader_type spatial;
// skylab_card.gdshader — SKYLAB v0.14: карточки-облака. КЛУБЛЕНИЕ УБРАНО ПОЛНОСТЬЮ
// (ревью: «полностью неудовлетворительно») — альтернативные инструменты оживления
// обсуждаются отдельно, в шейдере нет TIME-варпов.
// Освещение: 5-стоповая рампа состояния по E (form пака + направление солнца на экране
// + контровой фактор), складочная окклюзия по градиенту form, краевой свет по sun_side,
// холодная противосолнечная кромка, подмес амбиента неба, дистанционная дымка.
// Unlit через EMISSION (ALBEDO=0); палитра adapted (inv-Filmic).
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D card_mask : filter_linear;
uniform vec3 st_ramp0 : source_color = vec3(0.067343, 0.023926, 0.050686);
uniform vec3 st_ramp1 : source_color = vec3(0.143677, 0.025475, 0.036102);
uniform vec3 st_ramp2 : source_color = vec3(2.0, 0.093041, 0.045549);
uniform vec3 st_ramp3 : source_color = vec3(2.0, 0.107580, 0.054996);
uniform vec3 st_ramp4 : source_color = vec3(2.0, 1.243032, 1.221998);
uniform vec3 st_shadow : source_color = vec3(0.143677, 0.025475, 0.036102);
uniform vec3 st_lit : source_color = vec3(2.0, 0.107580, 0.054996);
uniform vec3 st_rim : source_color = vec3(2.0, 0.258963, 0.188911);
uniform vec3 st_under : source_color = vec3(2.0, 0.078501, 0.036102);
uniform vec3 st_zenith : source_color = vec3(0.015954, 0.022894, 0.060409);
uniform vec3 haze_col : source_color = vec3(2.0, 0.945, 0.918);
uniform float haze_start = 12000.0;
uniform float haze_end = 30000.0;
uniform float base_fade : hint_range(0.0, 0.5) = 0.10;
uniform float form_contrast : hint_range(0.2, 4.0) = 1.35;
uniform float form_detail : hint_range(0.0, 0.6) = 0.35;
uniform float crev_int : hint_range(0.0, 1.0) = 0.35;
uniform float dir_mix : hint_range(0.0, 1.0) = 0.25;
uniform float back_dark : hint_range(0.0, 1.0) = 0.65;
uniform float ramp_gamma : hint_range(0.5, 3.0) = 1.4;
uniform float rim_int : hint_range(0.0, 3.0) = 0.60;
uniform float rim_exp : hint_range(0.5, 16.0) = 3.0;
uniform float cool_edge : hint_range(0.0, 1.0) = 0.22;
uniform float sky_amb_mix : hint_range(0.0, 0.5) = 0.12;
uniform float under_int : hint_range(0.0, 3.0) = 0.90;
uniform vec3 sun_dir_world = vec3(0.0, 0.0, -1.0);
uniform vec2 sun_screen = vec2(0.0, 0.0);
uniform float sun_up = 0.5;
uniform float sun_below = 0.0;
uniform float flip = 0.0;

varying float v_dist;
varying vec3 v_frag_to_cam;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 cam_pos = (inverse(VIEW_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_dist = distance(wp.xyz, cam_pos);
	v_frag_to_cam = normalize(cam_pos - wp.xyz);
}

vec3 ramp5(float u) {
	u = clamp(u, 0.0, 4.0);
	if (u < 1.0) return mix(st_ramp0, st_ramp1, u);
	if (u < 2.0) return mix(st_ramp1, st_ramp2, u - 1.0);
	if (u < 3.0) return mix(st_ramp2, st_ramp3, u - 2.0);
	return mix(st_ramp3, st_ramp4, u - 3.0);
}

void fragment() {
	vec2 uv = vec2(mix(UV.x, 1.0 - UV.x, flip), UV.y);
	vec4 t = texture(card_mask, uv);
	float a = t.a * smoothstep(0.0, base_fade, uv.y);
	if (a < 0.004) {
		discard;
	}
	// нормаль кромки из градиента альфы — для направленного краевого света
	vec2 tx = 1.0 / vec2(textureSize(card_mask, 0));
	float aL = texture(card_mask, uv - vec2(tx.x, 0.0)).a;
	float aR = texture(card_mask, uv + vec2(tx.x, 0.0)).a;
	float aD = texture(card_mask, uv - vec2(0.0, tx.y)).a;
	float aU = texture(card_mask, uv + vec2(0.0, tx.y)).a;
	vec2 grad = vec2(aR - aL, aU - aD);
	vec2 n2 = length(grad) > 1e-4 ? normalize(grad) : vec2(0.0);
	vec2 ss = length(sun_screen) > 1e-4 ? normalize(sun_screen) : vec2(0.0);
	float sun_side = max(dot(n2, ss), 0.0);

	float form = clamp(pow(clamp(t.r, 0.0, 1.0), form_contrast), 0.0, 1.0);
	vec2 ss2 = length(sun_screen) > 1e-4 ? normalize(sun_screen) : vec2(0.0, 1.0);
	float vert = mix(1.0 - uv.y, uv.y, sun_up);
	float side = clamp(dot(normalize(uv - 0.5 + vec2(1e-5)), ss2) * 0.5 + 0.5, 0.0, 1.0);
	float dir2 = mix(vert, side, 0.5);
	float fs = pow(clamp(dot(-v_frag_to_cam, normalize(sun_dir_world)), 0.0, 1.0), rim_exp);
	float E_c = clamp(form * 0.60 + dir2 * 0.25 + (1.0 - fs) * 0.15, 0.0, 1.0);
	E_c *= 1.0 - back_dark * fs * 0.8;
	vec3 col = ramp5(pow(E_c, ramp_gamma) * 4.0);
	col *= 1.0 - form_detail * 0.5 + form_detail * form;
	// складки между долями: градиент form × тень — читаемость объёма
	vec2 tx2 = 2.0 / vec2(textureSize(card_mask, 0));
	float frL = texture(card_mask, uv - vec2(tx2.x, 0.0)).r;
	float frR = texture(card_mask, uv + vec2(tx2.x, 0.0)).r;
	float frD = texture(card_mask, uv - vec2(0.0, tx2.y)).r;
	float frU = texture(card_mask, uv + vec2(0.0, tx2.y)).r;
	float crev = smoothstep(0.06, 0.30, length(vec2(frR - frL, frU - frD))) * (1.0 - form);
	col = mix(col, st_ramp0, crev * crev_int);
	// краевой свет с солнечной стороны + холодная противоположная кромка
	col += st_rim * (t.g * sun_side * (0.25 + 0.75 * fs) * rim_int);
	col = mix(col, st_zenith, t.g * (1.0 - sun_side) * cool_edge);
	// ambient неба по высоте карточки
	vec3 skyamb = mix(st_under, st_zenith, clamp(uv.y, 0.0, 1.0));
	col = mix(col, skyamb, sky_amb_mix);
	col += st_under * (t.b * under_int * sun_below);
	float haze = smoothstep(haze_start, haze_end, v_dist) * 0.75;
	col = mix(col, haze_col, haze);
	a *= 1.0 - 0.45 * haze;
	ALBEDO = vec3(0.0);
	EMISSION = col;
	ALPHA = a;
}
