extends Resource
class_name SkyPreset
## Q7.33 — Resource-пресет неба, формат расширен по п. 14.1 ТЗ.
## Всё состояние неба, кроме света сцены (свет — SkyLightProfile, поле light).
## Полей фаз луны, множителя яркости купола, вуали и bounce НЕТ:
## фазы удалены (решение 10), множителя нет (решение 9), вуаль удалена
## (решение 13), BounceLight не переносится (решение 5).
## Дефолты цветов стопов — различимая монотонная лестница: свободные слоты
## (02/03/07) остаются валидными без наполнения данными ключей.

@export var preset_name: String = "New Preset"
@export var preview: Texture2D

# --- положение источников (полные 180°) ---
@export_range(-90.0, 90.0)  var sun_elevation: float = 0.0
@export_range(0.0, 360.0)   var sun_azimuth: float = 180.0
@export_range(-90.0, 90.0)  var moon_elevation: float = 50.0
@export_range(0.0, 360.0)   var moon_azimuth: float = 0.0
@export var sun_enabled: bool = true
@export var moon_enabled: bool = true

# --- рампа: 6 стопов, всё данные ---
@export var col_glow: Color = Color(2.0, 0.5, 0.2)		# стоп 0 — ядро зари
@export var col_horizon: Color = Color(1.4, 0.4, 0.25)	# стоп 1
@export var col_band: Color = Color(0.6, 0.35, 0.7)		# стоп 2
@export var col_band2: Color = Color(0.3, 0.3, 0.8)		# стоп 3
@export var col_mid: Color = Color(0.12, 0.18, 0.4)		# стоп 4
@export var col_anti: Color = Color(0.02, 0.03, 0.09)	# стоп 5 — антисоляр
@export var col_halo: Color = Color(2.0, 0.5, 0.2)		# ореол источника
@export_range(0.0, 1.0)   var p1: float = 0.010
@export_range(0.0, 1.0)   var p2: float = 0.075
@export_range(0.0, 1.0)   var p3: float = 0.155
@export_range(0.0, 1.0)   var p4: float = 0.300
@export_range(0.0, 1.0)   var p5: float = 0.520
@export_range(0.0, 1.0)   var p6: float = 1.000
@export_range(0.05, 1.0)  var sharp: float = 1.0
@export_range(1.0, 4.0)   var arc_stretch: float = 2.4

# --- купол ---
@export var dither: bool = true
@export_range(0.0, 1.0) var star_intensity: float = 0.0

# --- источник ---
@export var sun_disc_color: Color = Color(1.0, 0.953, 0.816)
@export_range(0.5, 4.0)   var sun_size_deg: float = 1.8
@export_range(0.0, 8.0)   var sun_core_int: float = 5.0
@export_range(0.0, 1.0)   var glow_int: float = 0.30
@export_range(1.0, 12.0)  var glow_exp: float = 6.0
@export_range(0.0, 1.0)   var g1_int: float = 0.35
@export_range(0.0, 1.0)   var g2_int: float = 0.12
@export_range(0.0, 1.0)   var streak_int: float = 0.0
@export_range(0.0, 180.0) var streak_gate_lo: float = 45.0
@export_range(0.0, 180.0) var streak_gate_hi: float = 60.0
@export var moon_color: Color = Color(0.753, 0.784, 0.910)
@export_range(0.001, 0.1) var moon_size: float = 0.02
@export_range(0.0, 1.0)   var moon_detail_int: float = 0.5
@export_range(0.0, 1.0)   var moon_glow_int: float = 0.0
@export_range(0.0, 80.0)  var moon_glow_exp: float = 40.0

# --- свет сцены ---
@export var light: SkyLightProfile
