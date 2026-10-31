extends Resource
class_name SkyPreset
## Q7.33 — Resource-пресет неба, формат расширен по п. 14.1 ТЗ.
## Всё состояние неба, кроме света сцены (свет — SkyLightProfile, поле light).
## Полей фаз луны, множителя яркости купола, вуали и bounce НЕТ:
## фазы удалены (решение 10), множителя нет (решение 9), вуаль удалена
## (решение 13), BounceLight не переносится (решение 5).
## Дефолты цветов стопов — данные ref #2 «Солнце над облаками» из palletes.html:
## свободные слоты остаются валидными без наполнения.

@export var preset_name: String = "New Preset"
@export var preview: Texture2D

# --- положение источников (полные 180°) ---
@export_range(-90.0, 90.0)  var sun_elevation: float = 0.0
@export_range(0.0, 360.0)   var sun_azimuth: float = 180.0
@export_range(-90.0, 90.0)  var moon_elevation: float = 50.0
@export_range(0.0, 360.0)   var moon_azimuth: float = 0.0
@export var sun_enabled: bool = true
@export var moon_enabled: bool = true

# --- рампа: 4 стопа (Sky3.2.4, ТЗ: «4 цвета по palletes.html»), всё данные ---
# Нумерация col_sky1…col_sky4 ДОСЛОВНО = шаги HTML: sky1 = «Шаг 1 (верх)» (зенит,
# самый тёмный), sky4 = «Шаг 4 (низ/горизонт)» (у солнца, самый светлый). Рампа
# шейдера идёт ОТ солнца, поэтому раскладка по u обратная: u<q1 — sky4, q3..q4 — sky1.
# Q7.34 (COLORS5): col_* (кроме col_halo) — ДИСПЛЕЙНЫЕ ДАННЫЕ: palette hex/255,
# encoded sRGB 0..1. Шейдер смешивает их в кодированном пространстве (плавный
# градиент) и декодирует один раз; байт экрана на стопе = hex побайтово в обоих
# режимах тонмапа. col_halo — ЕДИНСТВЕННЫЙ linear-HDR цвет (может быть > 1).
@export var col_sky1: Color = Color(0.0157, 0.0627, 0.1333)	# шаг 1 (верх) — зенит/антисоляр
@export var col_sky2: Color = Color(0.1686, 0.4588, 0.7098)	# шаг 2
@export var col_sky3: Color = Color(0.5490, 0.7686, 0.9098)	# шаг 3
@export var col_sky4: Color = Color(1.0, 0.9529, 0.8392)	# шаг 4 (низ/горизонт) — у солнца
@export var col_halo: Color = Color(2.0, 0.5, 0.2)		# ореол источника (linear HDR)
# --- окружение: 3 цвета «от солнца/горизонта» (palletes.html, строка «Окружение») ---
# Sky3.2.4: данные; применение (SunLight/ambient/fog + тон вуали) — шаг …3.2.5.
@export var col_light1: Color = Color(1.0, 0.9529, 0.8784)	# L1 — у солнца/горизонта
@export var col_light2: Color = Color(0.9098, 0.6902, 0.6275)	# L2 — середина
@export var col_light3: Color = Color(0.2078, 0.2863, 0.3725)	# L3 — даль
@export_range(0.0, 1.0)   var q1: float = 0.010
@export_range(0.0, 1.0)   var q2: float = 0.155
@export_range(0.0, 1.0)   var q3: float = 0.520
@export_range(0.0, 1.0)   var q4: float = 1.000
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
# Q7.34.PreOmega_Sky3.2.2 (Б-мир): полууглы бокса стрика — данные пресета.
# Дефолт держит аспект streak_glare.png 1774×887 (2:1): tan(45°)/tan(26.6°) = 2.0.
@export_range(1.0, 80.0) var streak_half_w_deg: float = 45.0
@export_range(1.0, 80.0) var streak_half_h_deg: float = 26.6
@export var moon_color: Color = Color(0.753, 0.784, 0.910)
@export_range(0.001, 0.1) var moon_size: float = 0.02
@export_range(0.0, 1.0)   var moon_detail_int: float = 0.5
@export_range(0.0, 1.0)   var moon_glow_int: float = 0.0
@export_range(0.0, 80.0)  var moon_glow_exp: float = 40.0

# --- свет сцены ---
@export var light: SkyLightProfile

# --- вуаль (Sky3.2.8, S11): sub-resource-компонент по образцу light ---
## null = данных вуали нет → apply_veil держит гейт hc_enabled = false
## (кадр побитово прежний); старые .tres грузятся без миграции.
@export var veil: SkyVeilProfile
