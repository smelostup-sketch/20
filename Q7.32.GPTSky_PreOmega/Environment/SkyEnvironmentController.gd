
extends Node
class_name SkyEnvironmentController

@export var sky_material: ShaderMaterial
@export var sun_light: DirectionalLight3D
@export var moon_light: DirectionalLight3D

@export_range(0.0, 4.0, 0.05) var sun_energy: float = 1.0
@export_range(0.0, 1.0, 0.01) var moon_energy: float = 0.12

var sun_azimuth: float = 0.0
var sun_elevation: float = 10.0
var moon_azimuth: float = 180.0
var moon_elevation: float = 25.0

var sun_enabled: bool = true
var moon_enabled: bool = false


func _ready() -> void:
    _apply_all()


func _direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
    var az: float = deg_to_rad(azimuth_deg)
    var el: float = deg_to_rad(elevation_deg)

    return Vector3(
        sin(az) * cos(el),
        sin(el),
        -cos(az) * cos(el)
    ).normalized()


func _orient_light(light: DirectionalLight3D, direction: Vector3) -> void:
    # Direction указывает от наблюдателя к источнику.
    # Световые лучи идут в обратную сторону.
    var ray_direction: Vector3 = -direction.normalized()
    var up: Vector3 = Vector3.UP

    if absf(ray_direction.dot(up)) > 0.98:
        up = Vector3.FORWARD

    light.global_basis = Basis.looking_at(ray_direction, up)


func _apply_all() -> void:
    if sky_material == null:
        push_warning("SkyEnvironmentController: sky_material is not assigned.")
        return

    var sun_dir: Vector3 = _direction(sun_azimuth, sun_elevation)
    var moon_dir: Vector3 = _direction(moon_azimuth, moon_elevation)

    sky_material.set_shader_parameter("sun_direction", sun_dir)
    sky_material.set_shader_parameter("moon_direction", moon_dir)
    sky_material.set_shader_parameter("sun_enabled", sun_enabled)
    sky_material.set_shader_parameter("moon_enabled", moon_enabled)

    if sun_light != null:
        sun_light.visible = sun_enabled
        sun_light.light_energy = sun_energy
        _orient_light(sun_light, sun_dir)

    if moon_light != null:
        moon_light.visible = moon_enabled
        moon_light.light_energy = moon_energy
        _orient_light(moon_light, moon_dir)


func set_sun_angles(azimuth: float, elevation: float) -> void:
    sun_azimuth = wrapf(azimuth, 0.0, 360.0)
    sun_elevation = clampf(elevation, -90.0, 90.0)
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


func set_veil_enabled(enabled: bool) -> void:
    if sky_material != null:
        sky_material.set_shader_parameter("veil_enabled", enabled)


func set_veil_parameter(parameter: StringName, value: float) -> void:
    if sky_material != null:
        sky_material.set_shader_parameter(parameter, value)


func apply_preset(preset: SkyPreset) -> void:
    if preset == null:
        return

    sun_azimuth = preset.sun_azimuth
    sun_elevation = preset.sun_elevation

    if sky_material != null:
        sky_material.set_shader_parameter("color_solar", preset.color_solar)
        sky_material.set_shader_parameter("color_warm", preset.color_warm)
        sky_material.set_shader_parameter("color_mid", preset.color_mid)
        sky_material.set_shader_parameter("color_deep", preset.color_deep)
        sky_material.set_shader_parameter("color_antisolar", preset.color_antisolar)
        sky_material.set_shader_parameter("horizon_stretch", preset.horizon_stretch)
        sky_material.set_shader_parameter("sky_energy", preset.sky_energy)

    _apply_all()
