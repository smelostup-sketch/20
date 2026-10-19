shader_type sky;
// omega_volumetric_clouds.gdshader — RENGAR PROTOTYPE OMEGA, Q7.32A, фаза A, шаг A1.
// Минимальный sky-шейдер: однотонное небо. БЕЗ raymarching, noise и освещения.
// Использованы только возможности, подтверждённые в Godot 4.7 (Forward Plus)
// и уже применяемые в производственном omega_sky_shader.gdshader:
//   shader_type sky; uniform vec3 : source_color; точка входа void sky(); вывод COLOR.
// Производственные ресурсы неба (omega_sky_*, Сцена_неба.tscn) НЕ изменяются.
// Подключение материала/неба/тестовой сцены — шаг A2 (отдельно, после подтверждения).

uniform vec3 sky_color : source_color = vec3(0.32, 0.47, 0.68);

void sky() {
	COLOR = sky_color;
}
