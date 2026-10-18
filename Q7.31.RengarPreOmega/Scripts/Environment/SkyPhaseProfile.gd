extends Resource
class_name SkyPhaseProfile
## Профиль фазы неба (данные, .tres): ВСЕ динамические параметры неба и света
## для одной фазы (закат / сумерки / ночь). Палитры градиента (9 цветов фаз) —
## художественные константы материала омега-неба, фазы между собой смешиваются
## ВЕСАМИ sunset_amount/night_amount (их тоже хранит профиль).
## interpolate() — построчный lerp всех каналов: контроллер не держит твинов
## на каждый параметр, одна математика смешивания (без гонок твинов, промт §7).

## Веса фаз в шейдере: закат = (1, 0), сумерки = (0, 0), ночь = (0, 1).
@export var sunset_amount := 1.0
@export var night_amount := 0.0
## Дымка горизонта.
@export var horizon_haze_strength := 0.55
@export var horizon_haze_color := Color(0.85, 0.35, 0.30)
## Облака: форма.
@export_range(0.0, 0.95, 0.01) var cloud_coverage := 0.45
@export_range(0.02, 1.0, 0.01) var cloud_density := 0.35
@export_range(0.0, 1.0, 0.01) var cloud_opacity := 0.85
@export_range(0.05, 4.0, 0.01) var cloud_large_scale := 0.55
@export_range(0.1, 12.0, 0.05) var cloud_detail_scale := 2.1
@export_range(0.0, 1.5, 0.01) var cloud_detail_strength := 0.45
## Облака: независимое движение слоёв (направление + скорость, м/с условные).
@export var wind_large_dir := Vector2(1.0, 0.25)
@export_range(0.0, 0.5, 0.001) var wind_large_speed := 0.012
@export var wind_detail_dir := Vector2(0.6, -0.8)
@export_range(0.0, 0.5, 0.001) var wind_detail_speed := 0.02
## Облака: освещение (псевдо-объём сдвигом к источнику).
@export var cloud_light_direction := Vector3(-0.4, 0.25, -0.8)
@export var cloud_light_color := Color(1.0, 0.55, 0.45)
@export var cloud_dark_color := Color(0.16, 0.08, 0.16)
@export_range(0.0, 2.0, 0.05) var cloud_light_strength := 1.0
## Луна (визуальный элемент неба; сцену освещает DirectionalLight3D).
@export var moon_direction := Vector3(0.35, 0.45, -0.82)
@export_range(0.005, 0.2, 0.001) var moon_size := 0.045
@export_range(0.0, 3.0, 0.05) var moon_intensity := 0.0
@export_range(0.0, 2.0, 0.05) var moon_halo_strength := 0.0
@export var moon_color := Color(0.92, 0.94, 1.0)
## Звёзды.
@export_range(0.0, 2.0, 0.05) var star_intensity := 0.0
@export_range(0.0, 1.0, 0.01) var star_visibility := 0.0
## Свет сцены (DirectionalLight3D) и заливка Environment.
@export var light_color := Color(1.0, 0.62, 0.35)
@export_range(0.0, 8.0, 0.05) var light_energy := 2.2
@export var light_euler_deg := Vector3(-10.0, 0.0, -35.0)
@export_range(0.0, 4.0, 0.05) var ambient_energy := 1.0


func copy_from(other: SkyPhaseProfile) -> void:
	interpolate(other, other, 1.0)


## Построчный lerp: self = lerp(a, b, t). Цвета/векторы — своими lerp,
## углы света — прямой lerp эйлеров (позы фаз близки, gimbal не грозит).
func interpolate(a: SkyPhaseProfile, b: SkyPhaseProfile, t: float) -> void:
	var k := clampf(t, 0.0, 1.0)
	sunset_amount = lerp(a.sunset_amount, b.sunset_amount, k)
	night_amount = lerp(a.night_amount, b.night_amount, k)
	horizon_haze_strength = lerp(a.horizon_haze_strength, b.horizon_haze_strength, k)
	horizon_haze_color = a.horizon_haze_color.lerp(b.horizon_haze_color, k)
	cloud_coverage = lerp(a.cloud_coverage, b.cloud_coverage, k)
	cloud_density = lerp(a.cloud_density, b.cloud_density, k)
	cloud_opacity = lerp(a.cloud_opacity, b.cloud_opacity, k)
	cloud_large_scale = lerp(a.cloud_large_scale, b.cloud_large_scale, k)
	cloud_detail_scale = lerp(a.cloud_detail_scale, b.cloud_detail_scale, k)
	cloud_detail_strength = lerp(a.cloud_detail_strength, b.cloud_detail_strength, k)
	wind_large_dir = a.wind_large_dir.lerp(b.wind_large_dir, k)
	wind_large_speed = lerp(a.wind_large_speed, b.wind_large_speed, k)
	wind_detail_dir = a.wind_detail_dir.lerp(b.wind_detail_dir, k)
	wind_detail_speed = lerp(a.wind_detail_speed, b.wind_detail_speed, k)
	cloud_light_direction = a.cloud_light_direction.lerp(b.cloud_light_direction, k)
	cloud_light_color = a.cloud_light_color.lerp(b.cloud_light_color, k)
	cloud_dark_color = a.cloud_dark_color.lerp(b.cloud_dark_color, k)
	cloud_light_strength = lerp(a.cloud_light_strength, b.cloud_light_strength, k)
	moon_direction = a.moon_direction.lerp(b.moon_direction, k)
	moon_size = lerp(a.moon_size, b.moon_size, k)
	moon_intensity = lerp(a.moon_intensity, b.moon_intensity, k)
	moon_halo_strength = lerp(a.moon_halo_strength, b.moon_halo_strength, k)
	moon_color = a.moon_color.lerp(b.moon_color, k)
	star_intensity = lerp(a.star_intensity, b.star_intensity, k)
	star_visibility = lerp(a.star_visibility, b.star_visibility, k)
	light_color = a.light_color.lerp(b.light_color, k)
	light_energy = lerp(a.light_energy, b.light_energy, k)
	light_euler_deg = a.light_euler_deg.lerp(b.light_euler_deg, k)
	ambient_energy = lerp(a.ambient_energy, b.ambient_energy, k)
