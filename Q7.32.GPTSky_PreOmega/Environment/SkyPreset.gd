
extends Resource
class_name SkyPreset

@export var preset_name: String = "New Preset"
@export var preview: Texture2D

@export_range(0.0, 360.0, 1.0) var sun_azimuth: float = 0.0
@export_range(-90.0, 90.0, 1.0) var sun_elevation: float = 10.0

@export var color_solar: Color = Color(1.0, 0.72, 0.48)
@export var color_warm: Color = Color(0.55, 0.25, 0.24)
@export var color_mid: Color = Color(0.12, 0.16, 0.30)
@export var color_deep: Color = Color(0.025, 0.035, 0.095)
@export var color_antisolar: Color = Color(0.008, 0.012, 0.035)

@export_range(1.0, 3.0, 0.05) var horizon_stretch: float = 2.5
@export_range(0.0, 4.0, 0.05) var sky_energy: float = 1.0
