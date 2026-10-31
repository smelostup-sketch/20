extends Resource
class_name SkyVeilProfile
## Sky3.2.8 (S11) — Resource с данными вуали (компонентизация по приказу заказчика:
## состояние вуали — ОТДЕЛЬНЫЙ профиль-компонент, по образцу SkyLightProfile для
## света сцены; план ВУАЛЬ §4, 8 полей). Поля мапятся 1:1 на uniform'ы компонента
## SkyVeil.gdshaderinc; ЕДИНСТВЕННЫЙ писатель материала — SkyEnvironmentController.
## apply_veil (п. 9: писатель один). preset.veil == null = вуаль выключена: старые
## .tres грузятся без миграции, гейт hc_enabled остаётся false (кадр побитово прежний).

@export var veil_enabled: bool = false				# → hc_enabled (ГЕЙТ: false = побитово небо без вуали). Sky3.2.12: во всех поставленных пресетах = true ДАННЫМИ (.tres), дефолт класса оставлен выключенным ради явности .tres
@export_range(0.0, 1.0) var veil_amount: float = 1.0		# → DS_hc_alpha_scale (fade/LOD)
@export var veil_color: Color = Color(0.92, 0.93, 0.96)		# → hc_color (плоский тон при hc_use_lighting = off)
@export_range(0.0, 4.0) var veil_light_gain: float = 1.0	# → hc_light_gain (работает при hc_use_lighting = on)
@export_range(0.0, 4.0) var veil_ambient_gain: float = 1.0	# → hc_ambient_gain (работает при hc_use_lighting = on)
@export_range(0.0, 1.0) var veil_coverage: float = 0.52		# → hc_coverage (Sky3.2.13: дефолт компонента, образцы 233/234)
@export_range(0.0, 4.0) var veil_tau_per_km: float = 0.30	# → hc_tau_per_km (Sky3.2.13: дефолт компонента, перо)
@export var veil_use_shadowing: bool = false			# → hc_use_shadowing (дефолт false по плану §4)
