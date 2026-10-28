extends Node
class_name SkyEnvironmentController
## Q7.33 — ЕДИНСТВЕННЫЙ писатель ShaderMaterial неба (п. 9/12.2 ТЗ).
## Знает: материал, углы, пресет. НЕ знает NodePath на свет — сцена и свет
## делегируются в SkyLightController (экспорт light_controller).

@export var sky_material: ShaderMaterial
@export var light_controller: SkyLightController
## Пресет старта сцены (применяется в _ready; дефолт сборки — Preset_09 = K4).
@export var initial_preset: SkyPreset

@export_range(0.0, 4.0, 0.05) var sun_energy: float = 1.0
@export_range(0.0, 1.0, 0.01) var moon_energy: float = 0.12

var sun_azimuth: float = 180.0
var sun_elevation: float = 0.5
var moon_azimuth: float = 0.0
var moon_elevation: float = 50.0

var sun_enabled: bool = true
var moon_enabled: bool = true


func _ready() -> void:
	if initial_preset != null:
		apply_preset(initial_preset)
	else:
		_apply_all()
		if light_controller != null:
			light_controller.set_key_light_energy(sun_energy)
			light_controller.set_moon_light_energy(moon_energy)


## ОДИН _direction(azimuth, elevation) на шейдер и на свет (п. 12.2):
## тело функции — в SkyLightController.direction_from_angles (static),
## разъезд «солнце на небе» / «откуда тени» исключён.
func _direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
	return SkyLightController.direction_from_angles(azimuth_deg, elevation_deg)


func _apply_all() -> void:
	if sky_material == null:
		push_warning("SkyEnvironmentController: sky_material is not assigned.")
		return

	var sun_dir: Vector3 = _direction(sun_azimuth, sun_elevation)
	var moon_dir: Vector3 = _direction(moon_azimuth, moon_elevation)

	# имена uniform'ов — B (sk_sun_dir/sk_moon_dir), шаг D.3
	sky_material.set_shader_parameter("sk_sun_dir", sun_dir)
	sky_material.set_shader_parameter("sk_moon_dir", moon_dir)
	sky_material.set_shader_parameter("sun_enabled", sun_enabled)
	sky_material.set_shader_parameter("moon_enabled", moon_enabled)

	if light_controller != null:
		light_controller.set_sun_angles(sun_azimuth, sun_elevation)
		light_controller.set_moon_angles(moon_azimuth, moon_elevation)
		light_controller.set_sun_enabled(sun_enabled)
		light_controller.set_moon_enabled(moon_enabled)


func set_sun_angles(azimuth: float, elevation: float) -> void:
	sun_azimuth = wrapf(azimuth, 0.0, 360.0)
	sun_elevation = clampf(elevation, -90.0, 90.0)	# полные 180°, клампов B нет
	_apply_all()


func set_moon_angles(azimuth: float, elevation: float) -> void:
	moon_azimuth = wrapf(azimuth, 0.0, 360.0)
	moon_elevation = clampf(elevation, -90.0, 90.0)
	_apply_all()


func set_sun_enabled(enabled: bool) -> void:
	sun_enabled = enabled
	_apply_all()


func set_moon_enabled(enabled: bool) -> void:
	moon_enabled = enabled
	_apply_all()


## Рампа и купол: шесть стопов + ореол + форма (данные пресета → материал).
func apply_palette(preset: SkyPreset) -> void:
	if preset == null or sky_material == null:
		return
	sky_material.set_shader_parameter("sk_glow_col", preset.col_glow)
	sky_material.set_shader_parameter("sk_horizon", preset.col_horizon)
	sky_material.set_shader_parameter("sk_band_col", preset.col_band)
	sky_material.set_shader_parameter("sk_band2_col", preset.col_band2)
	sky_material.set_shader_parameter("sk_mid", preset.col_mid)
	sky_material.set_shader_parameter("sk_anti_col", preset.col_anti)
	sky_material.set_shader_parameter("sk_halo_col", preset.col_halo)
	sky_material.set_shader_parameter("sk_p1", preset.p1)
	sky_material.set_shader_parameter("sk_p2", preset.p2)
	sky_material.set_shader_parameter("sk_p3", preset.p3)
	sky_material.set_shader_parameter("sk_p4", preset.p4)
	sky_material.set_shader_parameter("sk_p5", preset.p5)
	sky_material.set_shader_parameter("sk_p6", preset.p6)
	sky_material.set_shader_parameter("sk_sharp", preset.sharp)
	sky_material.set_shader_parameter("sk_arc_stretch", preset.arc_stretch)
	sky_material.set_shader_parameter("sk_dither", 1.0 if preset.dither else 0.0)
	sky_material.set_shader_parameter("star_intensity", preset.star_intensity)


## Солнце и луна: диск, ореолы, стрик, кратеры (данные пресета → материал).
func apply_sources(preset: SkyPreset) -> void:
	if preset == null or sky_material == null:
		return
	sky_material.set_shader_parameter("sun_disk_color", preset.sun_disc_color)
	sky_material.set_shader_parameter("sun_size_deg", preset.sun_size_deg)
	sky_material.set_shader_parameter("sun_core_int", preset.sun_core_int)
	sky_material.set_shader_parameter("sk_glow_int", preset.glow_int)
	sky_material.set_shader_parameter("sk_glow_exp", preset.glow_exp)
	sky_material.set_shader_parameter("sun_g1_int", preset.g1_int)
	sky_material.set_shader_parameter("sun_g2_int", preset.g2_int)
	sky_material.set_shader_parameter("streak_int", preset.streak_int)
	sky_material.set_shader_parameter("sk_streak_gate_lo", preset.streak_gate_lo)
	sky_material.set_shader_parameter("sk_streak_gate_hi", preset.streak_gate_hi)
	sky_material.set_shader_parameter("moon_color", preset.moon_color)
	sky_material.set_shader_parameter("moon_size", preset.moon_size)
	sky_material.set_shader_parameter("moon_detail_int", preset.moon_detail_int)
	sky_material.set_shader_parameter("moon_glow_int", preset.moon_glow_int)
	sky_material.set_shader_parameter("moon_glow_exp", preset.moon_glow_exp)


## Пресет целиком: палитра + источники + свет сцены (через light_controller).
func apply_preset(preset: SkyPreset) -> void:
	if preset == null:
		return
	sun_azimuth = wrapf(preset.sun_azimuth, 0.0, 360.0)
	sun_elevation = clampf(preset.sun_elevation, -90.0, 90.0)
	moon_azimuth = wrapf(preset.moon_azimuth, 0.0, 360.0)
	moon_elevation = clampf(preset.moon_elevation, -90.0, 90.0)
	sun_enabled = preset.sun_enabled
	moon_enabled = preset.moon_enabled
	apply_palette(preset)
	apply_sources(preset)
	_apply_all()
	if light_controller != null:
		light_controller.apply_light(preset.light)


# --- единственный вход панели для живых ручек (п. 9: панель пишет только
# --- через методы контроллеров; писатель материала при этом остаётся один) ---

func set_shader_param(param: StringName, value: Variant) -> void:
	if sky_material != null:
		sky_material.set_shader_parameter(param, value)


func get_shader_param(param: StringName) -> Variant:
	if sky_material == null:
		return null
	return sky_material.get_shader_parameter(param)
