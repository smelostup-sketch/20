extends Node
class_name AtmosphereShaderBindingComponent
## Q.7.34.PreOmega_Sky.4.1.1 (план света, этап 02) — передача параметров
## освещения КОНКРЕТНОМУ ShaderMaterial. Один экземпляр обслуживает один
## материал; Sky Gradient и Cirrus Veil — разные экземпляры с разными именами
## uniform'ов (план §4.4: имена — ДАННЫЕ, @export, не хардкод).
##
## Границы ответственности:
## - компонент НЕ зависит от реализации шейдера: не знает, как устроены вуаль
##   или градиент, лишь передаёт параметры по указанным именам;
## - пишет ТОЛЬКО существующие uniform'ы (кэш get_shader_uniform_list в _ready);
##   пустое имя (&"") = параметр не привязан и не пишется — связка собрана
##   структурно, но инертна, пока uniform не появится в шейдере (этапы 03/04);
## - обновление событийное: сигнал lighting_changed, без _process/polling;
## - решение заказчика 30.10 п.5: binding пишет ТОЛЬКО параметры освещения;
##   форма/геометрия (sk_sun_dir и пр.) остаются за SkyEnvironmentController —
##   второй писатель геометрических uniform'ов запрещён.

@export var lighting_source: AtmosphereLightingComponent
@export var target_material: ShaderMaterial

## Названия uniforms задаются под конкретный шейдер (данные сцены).
@export_group("Common Parameters")

@export var sun_direction_uniform: StringName = &""
@export var sun_color_uniform: StringName = &""
@export var sun_energy_uniform: StringName = &""

@export var ambient_zenith_uniform: StringName = &""
@export var ambient_horizon_uniform: StringName = &""
@export var ambient_strength_uniform: StringName = &""

@export_group("Veil Palette")

## false = палитра вуали не пишется (потребитель-градиент её не имеет).
@export var bind_veil_palette: bool = false

@export var anti_solar_uniform: StringName = &""
@export var transition_uniform: StringName = &""
@export var solar_uniform: StringName = &""

@export var anti_solar_mu_uniform: StringName = &""
@export var solar_mu_uniform: StringName = &""
@export var transition_position_uniform: StringName = &""

var _available_uniforms: Dictionary = {}


func _ready() -> void:
	if lighting_source == null or target_material == null:
		push_error("AtmosphereShaderBinding: Missing references.")
		return

	_cache_uniforms()

	lighting_source.lighting_changed.connect(_on_lighting_changed)

	var initial_state: AtmosphereLightingState = lighting_source.get_current_state()
	if initial_state != null:
		_apply_state(initial_state)


func _cache_uniforms() -> void:
	_available_uniforms.clear()

	if target_material.shader == null:
		return

	for uniform_info: Dictionary in target_material.shader.get_shader_uniform_list():
		_available_uniforms[StringName(uniform_info["name"])] = true


func _set_if_available(parameter: StringName, value: Variant) -> void:
	if parameter == &"":
		return

	if not _available_uniforms.has(parameter):
		return

	target_material.set_shader_parameter(parameter, value)


func _on_lighting_changed(state: AtmosphereLightingState) -> void:
	_apply_state(state)


func _apply_state(state: AtmosphereLightingState) -> void:
	_set_if_available(sun_direction_uniform, state.sun_direction)
	_set_if_available(sun_color_uniform, state.sun_color)
	_set_if_available(sun_energy_uniform, state.sun_energy)

	_set_if_available(ambient_zenith_uniform, state.ambient_zenith_color)
	_set_if_available(ambient_horizon_uniform, state.ambient_horizon_color)
	_set_if_available(ambient_strength_uniform, state.ambient_strength)

	if not bind_veil_palette:
		return

	_set_if_available(anti_solar_uniform, state.anti_solar_color)
	_set_if_available(transition_uniform, state.transition_color)
	_set_if_available(solar_uniform, state.solar_color)

	_set_if_available(anti_solar_mu_uniform, state.anti_solar_mu)
	_set_if_available(solar_mu_uniform, state.solar_mu)
	_set_if_available(transition_position_uniform, state.transition_position)
