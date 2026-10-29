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
# Q7.34 (COLORS5): col_* (кроме col_halo) — ДИСПЛЕЙНЫЕ ДАННЫЕ: palette hex/255,
# encoded sRGB 0..1. Шейдер смешивает их в кодированном пространстве (плавный
# градиент) и декодирует один раз; байт экрана на стопе = hex побайтово в обоих
# режимах тонмапа. col_halo — ЕДИНСТВЕННЫЙ linear-HDR цвет (может быть > 1).
@export var col_glow: Color = Color(1.0, 0.7677, 0.5545)		# стоп 0 — ядро зари
@export var col_horizon: Color = Color(0.9552, 0.7177, 0.6073)	# стоп 1
@export var col_band: Color = Color(0.8067, 0.6868, 0.8379)		# стоп 2
@export var col_band2: Color = Color(0.6506, 0.6506, 0.8635)		# стоп 3
@export var col_mid: Color = Color(0.4389, 0.5299, 0.7177)		# стоп 4
@export var col_anti: Color = Color(0.1586, 0.2036, 0.3794)	# стоп 5 — антисоляр
@export var col_halo: Color = Color(2.0, 0.5, 0.2)		# ореол источника (linear HDR)
@export_range(0.0, 1.0)   var p1: float = 0.010
@export_range(0.0, 1.0)   var p2: float = 0.075
@export_range(0.0, 1.0)   var p3: float = 0.155
@export_range(0.0, 1.0)   var p4: float = 0.300
@export_range(0.0, 1.0)   var p5: float = 0.520
@export_range(0.0, 1.0)   var p6: float = 1.000
@export_range(0.05, 1.0)  var sharp: float = 1.0
@export_range(1.0, 4.0)   var arc_stretch: float = 2.4
# Q7.34 (COLORS6, S15): «дыхание» купола — динамический варп шкалы u от высоты
# солнца: γ = 1 + breathe·sin(elev). Выше горизонта солярные стопы раздуваются
# за счёт дальних (антисоляр сжимается), ниже — обратно. 0 = выкл (побитово
# статика). Диапазон до 0.9: гарантирует γ > 0 (pow определён на всей шкале).
@export_range(0.0, 0.9)   var breathe: float = 0.0
@export_range(0.0, 2.0)   var squeeze: float = 0.0	# Q7.34 (COLORS7): компенсация складки у горизонта

# --- купол ---
@export var dither: bool = true
@export_range(0.0, 1.0) var star_intensity: float = 0.0
# Q7.34 (COLORS5): переключаемый тонмап (заказчик: «сделай переключаемым
# линер\филмик»). false = Filmic (цепь A, дефолт сцен), true = Linear.
# Байт-точность палитры на стопах гарантирована шейдером в обоих режимах;
# различается вид HDR-композита (солнце/ореол/звёзды) и характер градиента.
@export var tonemap_linear: bool = false

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
