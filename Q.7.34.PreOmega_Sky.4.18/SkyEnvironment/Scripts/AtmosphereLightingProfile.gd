extends Resource
class_name AtmosphereLightingProfile
## Q.7.34.PreOmega_Sky.4.1.1 (план света, этап 01) — ресурс НАСТРОЕК освещения.
## Ответственность (план §4.1, v2 §3.1): три категории параметров, не смешивая:
##   Direct Lighting      — коэффициент интенсивности Sun;
##   Ambient Environment  — цветовая среда (зенит/горизонт/сила);
##   Veil Artistic Palette— три цвета угловой палитры вуали + границы mu.
## Логики визуализации НЕТ (v2 §3.1): читается AtmosphereLightingComponent и
## упаковывается в AtmosphereLightingState; цвета вуали — художественная
## модификация наблюдаемого цвета, НЕ источники света (v2 §5.2).
## Данные проекта: res://SkyEnvironment/Profiles/AtmosphereLightingProfile.tres
## (стартовые tint — план §4.5: мягкие, околобелые; дефолты класса — план §4.1).

## Три цветовые зоны наблюдаемой вуали (v2 §5: Anti-Solar / Transition / Solar).
@export_group("Veil Angular Palette")

@export var anti_solar_color: Color = Color(0.42, 0.48, 0.68)
@export var transition_color: Color = Color(0.78, 0.76, 0.82)
@export var solar_color: Color = Color(1.0, 0.83, 0.65)

## mu = dot(view_direction, sun_direction).
## Низкое значение соответствует противосолнечному направлению.
@export_range(-1.0, 1.0, 0.01) var anti_solar_mu: float = -0.35
@export_range(-1.0, 1.0, 0.01) var solar_mu: float = 0.75
@export_range(0.05, 0.95, 0.01) var transition_position: float = 0.5

## Прямой свет: множитель интенсивности Sun (v2 §3.1 Direct Lighting).
@export_group("Direct Lighting")

@export_range(0.0, 5.0, 0.01) var direct_multiplier: float = 1.0

## Окружающая цветовая среда. Значения должны соответствовать цветовым
## параметрам Sky Gradient (план §7.2: одна среда на обоих потребителей,
## второй независимой палитры не существует).
@export_group("Sky Ambient")

@export var ambient_zenith_color: Color = Color(0.12, 0.19, 0.38)
@export var ambient_horizon_color: Color = Color(0.38, 0.40, 0.48)
@export_range(0.0, 2.0, 0.01) var ambient_strength: float = 1.0
