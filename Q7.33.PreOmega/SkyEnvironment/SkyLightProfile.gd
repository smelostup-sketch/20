extends Resource
class_name SkyLightProfile
## Q7.33 — Resource с данными света сцены (п. 14.2 ТЗ).
## Это то, что в B было таблицей GROUND (без полей bounce/be — BounceLight не
## переносится, решение 5). Читает и применяет только SkyLightController.

@export var key_color: Color = Color.WHITE
@export_range(0.0, 8.0) var key_energy: float = 2.2
@export var moon_light_color: Color = Color(0.35, 0.48, 0.75)
@export_range(0.0, 2.0) var moon_light_energy: float = 0.12
@export_range(0.0, 4.0) var ambient_energy: float = 1.0
