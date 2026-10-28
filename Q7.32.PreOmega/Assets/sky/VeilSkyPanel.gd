extends Node
## ВЕРСИЯ: Q7.32_SkyLight_r11_s4_antisolar180_nohorline (27.10.2026, сессия 4, сборка 2).
## r11_s4: метрика u_ellip на честной 360° сфере (антисоляр = 180° от соляра при любой
## высоте солнца, эллипс → круг у зенита/надира) + зеркальный луч плиты вуали (нет
## границы на горизонте, below_ext удалён). Данные PAL/SHAPE не менялись.
## r10_s4: градиент −wedge −zen_w −below (H1/H3/H4).
## VeilSkyPanel — интерфейс настроек вуали и пресетов освещения по референсам.
## Шаг 1.1 (2026-10-25): ПЕРЕНОС в рабочий состав Q7.32.PreOmega.SL двух инструментов
## из упакованных (_PACKED/Q7.32.PreOmega.BENCH/), урезанных под состав
## «вуаль + градиент + свет» (без кучевых и карточек):
##   1. SkyLabPanel.gd v0.5.2 — состояния ref1-ref5 (палитры M1, ADAPTED — дословно),
##      t-блендер соседних ключей, солнце (высота/азимут → DirectionalLight3D + sk_sun_dir),
##      миниатюры/оверлей референсов, скриншоты F9 (выдержка под incremental-небо),
##      read-only обратный синк со светом (драг-гард, порог 0.2°) — логика портится 1:1;
##   2. CloudsTestBench.gd — меню «Вуаль: протяжённая облачность (SKYHC)»: полный набор
##      ручек hc_* (диапазоны/шаги/подсказки — из данных меню бенча), пресеты
##      «Масштаб A/B» (HC_SCALE_PRESETS) и «Характер A/B» (HC_CHAR_PRESETS) — дословно.
## Удалено при переносе: карточки (set_state/set_sun/якоря), гейт кучевых sk_clouds_on,
## записи в удалённые uniform'ы (sk_ramp0-4, sk_rim_col, atmo_color).
## ДОБАВЛЕНО (задокументировано): (а) чекбокс «Красить вуаль состоянием» — по SKYHC-4
## цвет вуали берётся из общей P(dir) (§10.2): sk_mid + veil_* из лестницы; связка света: lit → cloud_light_color
## (в v0.5.2 вуаль была выключена, связка не использовалась; выкл → значения материала);
## (б) слайдер ветра (дрейф вуали) — пишет wind_speed рига VeilSkyRig;
## (в) строки панели единообразны: имя + контрол + число (стиль меню бенча).
## IBL-ЛАГ (SKY_TZ_LUT7 §7, способ 1): любое изменение состояния/ручек неба форсирует
## Sky.process_mode = REALTIME на SETTLE_FRAMES кадров (кубмапа догоняет без лага),
## в статике — INCREMENTAL. Кубмапа после шага 1 = градиент+диск+вуаль (один семпл,
## марша нет) — REALTIME дёшев, декорреляция не нужна.
## СОСТОЯНИЯ (SKY_TZ_LUT7 §2, переразметка 25.10.26): лестница K0-K6 по elev солнца
## (K0-K2 = ночные, извлечение с референсов N1-N5 — NIGHT_ADAPTED; K3-K6 = прежние
## ref1/ref4/ref3/ref5 = O1/O4/O3/O5; ref2/O2 = support ключа K4). Свет земли — из той
## же лестницы: KEY = light_color/energy основного света, BOUNCE = нижний BounceLight
## (GROUND, §8.5+Приложение А), FILL = IBL неба. Тест «единый источник»: выключи небо —
## земля читается как то же состояние.
## Управление: 8/F8 — панель, F9 — скриншот (user://skylab_shots/). Слой 8 (конвенция v0.13).
## Экспорт start_visible=false — панель скрыта на старте (интеграция в игровые сцены);
## состояние ref4 при этом всё равно применяется в _ready (детерминированный старт).
## МЫШЬ (конвенция SkyDebugUI Q7.31): открытие панели СОХРАНЯЕТ текущий режим мыши и
## ставит VISIBLE, закрытие — ВОЗВРАЩАЕТ сохранённый (в игровой сцене снова CAPTURED,
## в песочнице неба остаётся VISIBLE). Чисто событийно, без таймеров. Камера мышью
## вращается только в CAPTURED (ThirdPersonCamera) — при открытой панели обзор стоит.

# Полные роли M1 (adapted, inv-Filmic): zenith/horizon/lit/shadow/rim = palettes.json
const ADAPTED := {
	"ref1": {
		"zenith": Vector3(0.118023, 0.176595, 0.520467),
		"horizon": Vector3(2.000000, 0.651464, 0.143677),
		"glow": Vector3(2.000000, 0.651464, 0.143677),	# K3-K6: ядро зари = горизонт (побитово прежний вид)
		"band": Vector3(0.0, 0.0, 0.0), "band2": Vector3(0.0, 0.0, 0.0),
		"lit": Vector3(2.000000, 0.188911, 0.063227),
		"shadow": Vector3(0.080143, 0.054996, 0.143677),
		"rim": Vector3(2.000000, 0.107580, 0.039325),
	},
	"ref2": {
		"zenith": Vector3(0.083492, 0.109613, 0.173629),
		"horizon": Vector3(2.000000, 0.205382, 0.143677),
		"glow": Vector3(2.000000, 0.205382, 0.143677),	# K3-K6: ядро зари = горизонт (побитово прежний вид)
		"band": Vector3(0.0, 0.0, 0.0), "band2": Vector3(0.0, 0.0, 0.0),
		"lit": Vector3(2.000000, 0.078501, 0.060409),
		"shadow": Vector3(0.143677, 0.054996, 0.066121),
		"rim": Vector3(2.000000, 0.748773, 0.272116),
	},
	"ref3": {
		"zenith": Vector3(0.205382, 0.254722, 1.040193),
		"horizon": Vector3(2.000000, 1.065300, 0.467553),
		"glow": Vector3(2.000000, 1.065300, 0.467553),	# K3-K6: ядро зари = горизонт (побитово прежний вид)
		"band": Vector3(0.0, 0.0, 0.0), "band2": Vector3(0.0, 0.0, 0.0),
		"lit": Vector3(2.000000, 0.549748, 0.626839),
		"shadow": Vector3(0.413874, 0.192106, 0.272116),
		"rim": Vector3(2.000000, 1.377643, 0.467553),
	},
	"ref4": {
		"zenith": Vector3(0.015954, 0.022894, 0.060409),
		"horizon": Vector3(2.000000, 0.078501, 0.036102),
		"glow": Vector3(2.000000, 0.078501, 0.036102),	# K3-K6: ядро зари = горизонт (побитово прежний вид)
		"band": Vector3(0.0, 0.0, 0.0), "band2": Vector3(0.0, 0.0, 0.0),
		"lit": Vector3(2.000000, 0.107580, 0.054996),
		"shadow": Vector3(0.143677, 0.025475, 0.036102),
		"rim": Vector3(2.000000, 0.258963, 0.188911),
	},
	"ref5": {
		"zenith": Vector3(0.024600, 0.109613, 0.355120),
		"horizon": Vector3(2.000000, 1.065300, 0.406819),
		"glow": Vector3(2.000000, 1.065300, 0.406819),	# K3-K6: ядро зари = горизонт (побитово прежний вид)
		"band": Vector3(0.0, 0.0, 0.0), "band2": Vector3(0.0, 0.0, 0.0),
		"lit": Vector3(1.866999, 1.500198, 1.205897),
		"shadow": Vector3(0.205382, 0.285952, 0.539759),
		"rim": Vector3(1.340321, 0.272116, 0.188911),
	},
}
const SEQ := ["K0", "K1", "K2", "K3", "K4", "K5", "K6"]	# лестница K-ключей (SKY_TZ_LUT7 §2); ref2/O2 = support K4, не ключ
const PRESET_ELEV := [-30.0, -13.5, -5.0, 0.3, 0.5, 4.0, 15.0]	# K3: +0.3 (солнце НАД горизонтом, баг р5)	# высота солнца по ключам (§2)
const PRESET_AZIM := [180.0, 180.0, 180.0, 180.0, 180.0, 180.0, 180.0]
const LADDER_NAMES := ["K0 глубокая ночь", "K1 астро-сумерки", "K2 синий час", "K3 контровой закат",
	"K4 багровый закат", "K5 золотой час", "K6 поздний день"]
const THUMBS := ["N2.jpg", "N4.jpg", "N5.jpg", "ref1.png", "ref4.png", "ref3.png", "ref5.png"]

# Ночные ключи K0-K2: извлечение с референсов N1-N5 (Приложение А SKY_TZ_LUT7.md,
# inv-Filmic как у M1; zenith = антисоляр по терминологической пометке заказчика).
# ПРАВКА 27.10.26 (вердикт: ОДИН режим Filmic для всех ключей): роли перенастроены
# под Filmic + богатый градиент горизонта по описанию заказчика — K1/K2: почти белое
# ядро (~1°) → светло-розовый → сливовый → светло-голубой → насыщенно-синий →
# темно-синий → очень темно-синий на антисоляре; K2 — та же лестница, сдвинутая к
# горизонту (белого/розового больше, синего меньше); K0 — широкая розовая полоса N2 →
# бирюза → глубокий синий. Новые роли: glow = ядро зари (белое/розовое, HDR),
# band = сливовый пояс, band2 = голубой пояс (окна/веса — в SHAPE, только K0-K2).
# r10_s4: роли zenith/rim/band/band2/shadow этой таблицы КОДОМ НЕ ЧИТАЮТСЯ (таблица —
# зеркало palettes.json; активные роли градиента живут в PAL, из этой читается только lit).
# Самая тёмная точка = PAL.anti → sk_anti_col; «тень ниже горизонта» (sk_below_col)
# удалена вместе с границей (H1). Таблица оставлена как есть — не данные градиента.
const NIGHT_ADAPTED := {
	"K0": {
		"zenith": Vector3(0.000886, 0.001921, 0.005799),
		"horizon": Vector3(0.003206, 0.013163, 0.031508),
		"glow": Vector3(2.210000, 2.040000, 2.040000),
		"band": Vector3(0.004951, 0.072247, 0.107485),
		"band2": Vector3(0.002702, 0.009457, 0.034871),
		"lit": Vector3(0.006654, 0.037160, 0.136288),
		"shadow": Vector3(0.001765, 0.005262, 0.020632),
		"rim": Vector3(0.008093, 0.037160, 0.148779),
	},
	"K1": {
		"zenith": Vector3(0.001106, 0.002154, 0.015241),
		"horizon": Vector3(0.276519, 0.070545, 0.121227),
		"glow": Vector3(2.210000, 2.040000, 2.040000),
		"band": Vector3(0.057822, 0.015160, 0.042866),
		"band2": Vector3(0.035545, 0.090684, 0.241053),
		"lit": Vector3(0.115877, 0.097818, 0.992580),
		"shadow": Vector3(0.002548, 0.004020, 0.030353),
		"rim": Vector3(0.060409, 0.246447, 1.091338),
	},
	"K2": {
		"zenith": Vector3(0.001415, 0.002478, 0.015383),
		"horizon": Vector3(0.297533, 0.081107, 0.138905),
		"glow": Vector3(2.295000, 2.125000, 2.125000),
		"band": Vector3(0.069511, 0.020750, 0.059922),
		"band2": Vector3(0.041974, 0.096450, 0.231603),
		"lit": Vector3(0.188911, 0.118023, 1.065300),
		"shadow": Vector3(0.003541, 0.006120, 0.042183),
		"rim": Vector3(0.118023, 0.090465, 0.948150),
	},
}

# === ПАЛИТРА ГРАДИЕНТА r7 (вердикт 27.10.2026): ЕДИНАЯ лестница стопов на все 7 ключей ===
# Роли = стопы многостопной рампы по угловому удалению от солнца (см. преамбулу
# uniform'ов шейдера): glow = ядро зари, horizon = горизонтальный пояс, band/band2 =
# пояса 1/2, mid = средний купол, anti = самая тёмная область (антисоляр).
# r10_s4: роль zenith УДАЛЕНА — она существовала только для члена «затемнение кверху»
# (H4), которого больше нет; зенит своего цвета не имеет (SKY_CORE_SPEC §2).
# Ночи K0-K2 сняты с рефов N2/N4/N5 (display-hex →
# inv-Filmic, методика Приложения А); дни K3-K6 ПОДОГНАНЫ СИМУЛЯТОРОМ под прежнюю
# дневную модель (вердикт: «дневные пресеты — эталон, ночи подгоняем под них»),
# поэтому вид дня сохранён по семейству цветов. Всё — ДАННЫЕ: различаются только
# цвета стопов, их положения (SHAPE p1..p5), интенсивности, звёзды и луна.
const PAL := {
	"K0": {"glow": Vector3(0.070610, 0.326581, 0.992580), "horizon": Vector3(0.070610, 0.326581, 0.992580),
		"band": Vector3(0.018133, 0.073704, 0.285952), "band2": Vector3(0.008605, 0.051124, 0.212331),
		"mid": Vector3(0.008093, 0.022894, 0.080143), "anti": Vector3(0.004500, 0.012600, 0.044100)},
	"K1": {"glow": Vector3(1.693430, 0.361155, 1.693430), "horizon": Vector3(1.500198, 0.258963, 1.545003),
		"band": Vector3(0.246447, 0.122403, 1.304579), "band2": Vector3(0.000659, 0.246447, 1.270320),
		"mid": Vector3(0.024600, 0.146210, 2.000000), "anti": Vector3(0.000659, 0.002266, 0.040431)},
	"K2": {"glow": Vector3(1.931571, 0.223167, 1.641443), "horizon": Vector3(0.511148, 0.126904, 1.237453),
		"band": Vector3(0.086932, 0.080143, 0.992580), "band2": Vector3(0.003523, 0.064664, 0.592171),
		"mid": Vector3(0.000000, 0.016666, 0.406819), "anti": Vector3(0.000000, 0.010000, 0.244100)},
	"K3": {"glow": Vector3(1.497146, 0.488115, 0.109209), "horizon": Vector3(1.347526, 0.462816, 0.185316),
		"band": Vector3(0.678532, 0.349693, 0.525607), "band2": Vector3(0.293441, 0.284576, 0.721489),
		"mid": Vector3(0.187626, 0.266684, 0.775313), "anti": Vector3(0.102631, 0.150740, 0.443464)},
	"K4": {"glow": Vector3(1.495439, 0.058800, 0.027273), "horizon": Vector3(1.321247, 0.055905, 0.034771),
		"band": Vector3(0.574072, 0.043485, 0.066933), "band2": Vector3(0.153412, 0.036493, 0.085040),
		"mid": Vector3(0.035700, 0.034537, 0.090107), "anti": Vector3(0.019562, 0.020039, 0.051492)},
	"K5": {"glow": Vector3(1.445022, 0.779749, 0.406481), "horizon": Vector3(1.215704, 0.699542, 0.639205),
		"band": Vector3(0.647789, 0.500906, 1.215552), "band2": Vector3(0.407688, 0.416928, 1.459219),
		"mid": Vector3(0.316991, 0.385205, 1.551262), "anti": Vector3(0.144360, 0.159572, 0.620580)},
	"K6": {"glow": Vector3(0.912254, 0.544090, 0.396620), "horizon": Vector3(0.602613, 0.409797, 0.444780),
		"band": Vector3(0.382833, 0.314477, 0.478964), "band2": Vector3(0.147188, 0.212277, 0.515616),
		"mid": Vector3(0.046718, 0.168702, 0.531242), "anti": Vector3(0.028579, 0.062979, 0.164483)},
}

# Земля (SKY_TZ_LUT7 §8.5 + Приложение А, флаги разрешены заказчиком 25.10.26):
# KEY = DirectionalLight3D.color/energy, BOUNCE = нижний свет (узел BounceLight, be =
# его энергия). FILL = IBL-кубмапа неба (§7). Все из той же лестницы — рассинхрон
# невозможен. ПРАВКА 27.10.26 (вердикт: один режим — Filmic): K0-K2 пересчитаны
# inverse-Filmic от прежних Linear-целей — вид земли на ночах СОХРАНЁН, но теперь в
# едином Filmic-режиме (filmic(color×e) = прежняя линейная цель с точностью 1e-9).
# K3-K6 — прежние значения (они и так настраивались под Filmic).
# SKY_TZ_LUT7 §7 (способ 1): пока состояние движется — кубмапа неба пересобирается
# КАЖДЫЙ кадр (REALTIME), в статике у ключа — INCREMENTAL. 30 кадров после последней
# правки = переходные процессы затухают до возврата режима.
const SETTLE_FRAMES := 30

const GROUND := {
	"K0": {"key": Color(0.333, 0.470, 0.684), "e": 0.0970, "bounce": Color(0.131, 0.348, 0.658), "be": 0.0312},
	"K1": {"key": Color(0.224, 0.284, 0.652), "e": 0.0363, "bounce": Color(0.211, 0.146, 0.626), "be": 0.0189},
	"K2": {"key": Color(0.686, 0.391, 0.603), "e": 0.0730, "bounce": Color(0.335, 0.164, 0.636), "be": 0.0213},
	"K3": {"key": Color(1.0, 0.698, 0.478), "e": 1.4, "bounce": Color(0.761, 0.439, 0.290), "be": 0.4},
	"K4": {"key": Color(1.0, 0.541, 0.353), "e": 2.2, "bounce": Color(0.831, 0.290, 0.196), "be": 0.4},
	"K5": {"key": Color(1.0, 0.851, 0.627), "e": 2.0, "bounce": Color(0.878, 0.690, 0.502), "be": 0.4},
	"K6": {"key": Color(1.0, 0.941, 0.816), "e": 1.8, "bounce": Color(0.941, 0.863, 0.784), "be": 0.4},
}
# === ФОРМА r10_s4 (была r7, вердикт 27.10.2026 «все пресеты кодируются одинаково») ===
# В шейдере НЕТ веток по номеру ключа. Здесь — ТОЛЬКО данные ключа:
#   glow_int — ИНТЕНСИВНОСТЬ ореола источника (форма общая: glow_exp — константа материала);
#   low_dim — притемнение купола при низком солнце (скаляр, hue не меняет);
#   p1..p5 — ПОЛОЖЕНИЯ стопов градиента (соотношения лестницы, угловые доли 0..1).
# r10_s4 УДАЛЕНО из формы (три члена шейдера удалены безвозвратно, SKY_CORE_SPEC §3 п.4):
#   wedge_int — интенсивность световой полосы у горизонта (H3);
#   below_int — сила «тени ниже горизонта» (H1, граница);
#   zen_w — вес затемнения кверху (H4, костыль).
# Значения glow_int/low_dim/p1..p5 НЕ перенастраивались (вердикт: «только удалить код и
# данные, палитры не трогать») — вид ночей K0-K2 уедет, доводка стопами отдельным шагом.
const SHAPE := {
	"K0": {"glow_int": 0.10, "low_dim": 0.30,
		"p1": 0.050, "p2": 0.230, "p3": 0.420, "p4": 0.600, "p5": 0.750},
	"K1": {"glow_int": 0.20, "low_dim": 0.25,
		"p1": 0.020, "p2": 0.120, "p3": 0.240, "p4": 0.420, "p5": 0.600},
	"K2": {"glow_int": 0.25, "low_dim": 0.22,
		"p1": 0.015, "p2": 0.140, "p3": 0.280, "p4": 0.440, "p5": 0.600},
	"K3": {"glow_int": 0.30, "low_dim": 0.25,
		"p1": 0.010, "p2": 0.075, "p3": 0.155, "p4": 0.300, "p5": 0.520},
	"K4": {"glow_int": 0.30, "low_dim": 0.25,
		"p1": 0.010, "p2": 0.075, "p3": 0.155, "p4": 0.300, "p5": 0.520},
	"K5": {"glow_int": 0.30, "low_dim": 0.25,
		"p1": 0.010, "p2": 0.075, "p3": 0.155, "p4": 0.300, "p5": 0.520},
	"K6": {"glow_int": 0.30, "low_dim": 0.25,
		"p1": 0.010, "p2": 0.075, "p3": 0.155, "p4": 0.300, "p5": 0.520},
}
# порядок записи SHAPE в шейдер (uniform = "sk_" + ключ)
const SHAPE_KEYS := ["glow_int", "low_dim", "p1", "p2", "p3", "p4", "p5"]	# r10_s4: −wedge_int/below_int/zen_w

const PANEL_W := 352.0

# Вуаль по K-ключам (§8.2, r7): master/sun/sun_exp/lift/warm + лунный шеен.
# r7: густота вуали = оптическая толщина плиты по лучу (hc_alpha), поэтому
# veil_curve/veil_zen_floor/veil_refract УДАЛЕНЫ (вердикт п.1: зенит не влияет
# сам по себе ни на что; вуаль в зените видна за счёт базовой плотности слоя).
# master ночей поднят: при честной толщине прежние 0.05-0.32 давали невидимую вуаль.
const VEILP := {
	"K0": {"master": 0.35, "sun": 0.0, "sun_exp": 6.0, "lift": 0.0, "warm": Color(0.02, 0.05, 0.12, 1), "moon": 0.5, "blob": Color(0.004, 0.008, 0.030, 1)},
	"K1": {"master": 0.45, "sun": 0.2, "sun_exp": 6.0, "lift": 0.05, "warm": Color(0.06, 0.04, 0.12, 1), "moon": 0.35, "blob": Color(0.010, 0.008, 0.045, 1)},
	"K2": {"master": 0.50, "sun": 0.5, "sun_exp": 5.0, "lift": 0.1, "warm": Color(0.10, 0.06, 0.16, 1), "moon": 0.2, "blob": Color(0.030, 0.020, 0.090, 1)},
	"K3": {"master": 0.55, "sun": 1.2, "sun_exp": 4.0, "lift": 0.2, "warm": Color(0.165, 0.094, 0.063, 1), "moon": 0.05, "blob": Color(0.120, 0.050, 0.060, 1)},
	"K4": {"master": 0.6, "sun": 1.4, "sun_exp": 4.0, "lift": 0.22, "warm": Color(0.165, 0.078, 0.031, 1), "moon": 0.0, "blob": Color(0.160, 0.050, 0.080, 1)},
	"K5": {"master": 0.5, "sun": 1.0, "sun_exp": 5.0, "lift": 0.18, "warm": Color(0.102, 0.078, 0.031, 1), "moon": 0.0, "blob": Color(0.200, 0.120, 0.250, 1)},
	"K6": {"master": 0.4, "sun": 0.7, "sun_exp": 6.0, "lift": 0.15, "warm": Color(0.063, 0.063, 0.039, 1), "moon": 0.0, "blob": Color(0.250, 0.300, 0.450, 1)},
}

# Солнце/луна/звёзды по K-ключам (§8.4): диск (цвет/размер°/core), луна (фаза/цвет/glow),
# звёзды (интенсивность). Для K0-K2 диск ниже горизонта — гасится vis-гейтом шейдера.
const SUNMOON := {
	"K0": {"disc": Vector3(1.0, 0.914, 0.753), "size": 1.5, "core": 2.0, "mphase": 1.0,
		"mcol": Vector3(0.933, 0.949, 1.0), "mglow": 0.35, "star": 1.0, "streak": 0.0},
	"K1": {"disc": Vector3(1.0, 0.914, 0.753), "size": 1.5, "core": 2.0, "mphase": 1.0,
		"mcol": Vector3(0.847, 0.878, 0.961), "mglow": 0.2, "star": 0.7, "streak": 0.0},
	"K2": {"disc": Vector3(1.0, 0.914, 0.753), "size": 1.5, "core": 2.0, "mphase": 1.0,
		"mcol": Vector3(0.753, 0.784, 0.910), "mglow": 0.1, "star": 0.25, "streak": 0.0},
	"K3": {"disc": Vector3(1.0, 0.914, 0.753), "size": 1.5, "core": 2.0, "mphase": 0.0,
		"mcol": Vector3(0.753, 0.784, 0.910), "mglow": 0.0, "star": 0.05, "streak": 0.2},
	"K4": {"disc": Vector3(1.0, 0.953, 0.816), "size": 1.8, "core": 5.0, "mphase": 0.0,
		"mcol": Vector3(0.753, 0.784, 0.910), "mglow": 0.0, "star": 0.0, "streak": 0.5},
	"K5": {"disc": Vector3(1.0, 0.941, 0.784), "size": 2.2, "core": 6.0, "mphase": 0.0,
		"mcol": Vector3(0.753, 0.784, 0.910), "mglow": 0.0, "star": 0.0, "streak": 0.3},
	"K6": {"disc": Vector3(1.0, 0.965, 0.910), "size": 2.0, "core": 5.0, "mphase": 0.0,
		"mcol": Vector3(0.753, 0.784, 0.910), "mglow": 0.0, "star": 0.0, "streak": 0.15},
}

# Положение луны по K-ключам (фидбек 27.10.26 раунд 2: луна НЕ привязана к антисоляру,
# независима от солнца, может быть одновременно с ним): K0 — высокая луна hero-рефа N2;
# K1/K2 — ниже и западнее (полная фаза, видна); K3-K6 — дневные позиции в восточной
# половине неба (фаза 0 по §8.4 — тело существует, диск не виден, пока фаза не поднята).
# Слайдеры «Высота/Азимут луны» пишут sk_moon_dir поверх лестницы; ночью (elev солнца
# ≤ -2°) ключевой свет сцены разворачивается НА луну (логика освещения §6).
const MOONPOS := {
	"K0": {"elev": 62.0, "azim": 160.0},
	"K1": {"elev": 40.0, "azim": 205.0},
	"K2": {"elev": 26.0, "azim": 225.0},
	"K3": {"elev": 55.0, "azim": 250.0},
	"K4": {"elev": 50.0, "azim": 260.0},
	"K5": {"elev": 45.0, "azim": 270.0},
	"K6": {"elev": 40.0, "azim": 280.0},
}

# Пресеты вуали бенча (SKYHC-3.1/3.2) — дословно из CloudsTestBench.gd
const HC_SCALE_PRESETS := [
	{"n": "Мелкий 36 км", "b": "36 км", "u": {"hc_scale": 36000.0, "hc_stretch": 3.0, "hc_field_scale": 155000.0}},
	{"n": "Базовый 60 км", "b": "60 км", "u": {"hc_scale": 60000.0, "hc_stretch": 3.5, "hc_field_scale": 260000.0}},
	{"n": "Крупный 110 км", "b": "110 км", "u": {"hc_scale": 110000.0, "hc_stretch": 4.0, "hc_field_scale": 470000.0}},
	{"n": "Гигант 150 км", "b": "150 км", "u": {"hc_scale": 150000.0, "hc_stretch": 4.0, "hc_field_scale": 650000.0}},
]
const HC_CHAR_PRESETS := [
	{"n": "Плотная вуаль", "b": "Плотная", "u": {"hc_coverage": 0.46, "hc_field_amp": 0.55, "hc_softness": 0.26}},
	{"n": "Базовый", "b": "Базовый", "u": {"hc_coverage": 0.56, "hc_field_amp": 0.60, "hc_softness": 0.22}},
	{"n": "Острова и окна", "b": "Острова", "u": {"hc_coverage": 0.78, "hc_field_amp": 1.00, "hc_softness": 0.22}},
	{"n": "Редкие гряды", "b": "Редкие", "u": {"hc_coverage": 0.84, "hc_field_amp": 0.80, "hc_softness": 0.20}},
]

# Ручки вуали: данные строки меню бенча «Вуаль: протяжённая облачность (SKYHC)»
# (uniform, имя, min, max, step, дефолт шейдера/материала, подсказка бенча).
const VEIL_ROWS := [
	{"u": "hc_tau_per_km", "n": "Плотность вуали", "a": 0.0, "b": 3.0, "s": 0.01, "d": 0.35,
	 "h": "Оптическая толщина на 1 км пути: выше — вуаль плотнее и белее, 0 — слоя не видно"},
	{"u": "hc_coverage", "n": "Порог облачности", "a": 0.05, "b": 0.90, "s": 0.01, "d": 0.56,
	 "h": "Какую часть шумового поля считать облаком: выше — вуаль реже и прозрачнее. Рабочая зона 0.30-0.75 (развёртка SKYHC-3.2): ниже 0.20 — сплошное пятно без окон, выше 0.80 — почти пусто"},
	{"u": "hc_softness", "n": "Мягкость границ", "a": 0.01, "b": 0.60, "s": 0.01, "d": 0.22,
	 "h": "Ширина плавного перехода: выше — границы плотнее расплываются. Рекомендуются ≥ 0.10: ниже перепад плотности на 250 м доходит до 1.0 — контуры жёсткие (замер SKYHC-3.2)"},
	{"u": "hc_scale", "n": "Размер образований", "a": 20000.0, "b": 200000.0, "s": 1000.0, "d": 60000.0,
	 "h": "Размер крупных облачных образований в метрах: больше — шире полосы вуали. Диапазон подтверждён развёрткой SKYHC-3.1; за 200 км (при крупном поле разрывов) слой вырождается в одно пятно"},
	{"u": "hc_stretch", "n": "Вытянутость гряд", "a": 0.5, "b": 6.0, "s": 0.05, "d": 3.5,
	 "h": "Во сколько раз образования длиннее вдоль оси гряд: больше — вытянутые валы"},
	{"u": "hc_stretch_angle_deg", "n": "Азимут гряд", "a": -180.0, "b": 180.0, "s": 1.0, "d": 25.0,
	 "h": "Направление, вдоль которого вытянуты образования (градусы в плоскости горизонта)"},
	{"u": "hc_field_scale", "n": "Размер пятен разрывов", "a": 80000.0, "b": 800000.0, "s": 2000.0, "d": 260000.0,
	 "h": "Размер крупных областей разной плотности в метрах: больше — шире окна чистого неба. Держите ≥ 1.5-2× от «Размера образований»: при равных периодах слой сливается в однородную пелену (проверено развёрткой)"},
	{"u": "hc_field_amp", "n": "Неоднородность", "a": 0.0, "b": 1.0, "s": 0.01, "d": 0.60,
	 "h": "Насколько сильно поле разрывов меняет порог: 0 — равномерная полоса, 1 — острова и окна. Рекомендуются ≥ 0.30 (иначе крупная неоднородность слабая); поднятие amp уплотняет слой в среднем — компенсируйте порогом"},
	{"u": "hc_detail_strength", "n": "Сила детали", "a": 0.0, "b": 1.0, "s": 0.01, "d": 0.35,
	 "h": "Мелкие бугорки на границах образований: 0 — идеально гладкая вуаль (побитово прежний этап), 0.3-0.5 — органичная кромка; внутрь и наружу образований деталь не проникает"},
	{"u": "hc_detail_scale", "n": "Размер бугорков", "a": 800.0, "b": 8000.0, "s": 100.0, "d": 3000.0,
	 "h": "Размер бугорков мелкой детали в метрах: меньше — мельче фактура. Нижняя граница 800 — ниже возможен алиасинг на пологих углах к горизонту"},
	{"u": "veil_base", "n": "Пол узора (дымка)", "a": 0.0, "b": 1.0, "s": 0.01, "d": 0.35,
	 "h": "ФИКС А: плотность вуали там, где узора плиты нет (дымка у зари на скользящих лучах); 0 = вуаль только узором"},
	{"u": "veil_moon", "n": "Лунный блик на вуали", "a": 0.0, "b": 1.0, "s": 0.01, "d": 0.0,
	 "h": "Шеен луны на вуали (ночи K0-K2); 0 = вуаль не видит луну (A/B проверка)"},
	{"u": "sk_arc_stretch", "n": "Эллипс: растяжение света вдоль горизонта", "a": 1.0, "b": 4.0, "s": 0.05, "d": 2.4,
	 "h": "ГЛОБАЛЬНАЯ форма (вердикт 27.10.26 п.2): во сколько раз свет расходится вдоль горизонта дальше, чем по высоте. 1.0 = круг, 2.4 = эллипс с горизонтальной большой осью (ночные рефы N2/N4/N5, вердикт r9: +20%). Одна константа на все состояния — не параметр пресета"},
]
const HC_DEBUG_MODES := ["Итог", "Плотность", "Покрытие (альфа)", "Оптическая толщина"]
const OFFSET_ROWS := [
	{"ai": 0, "n": "Сдвиг поля X", "a": -200000.0, "b": 200000.0, "s": 500.0,
	 "h": "Двигает вуаль влево-вправо: выбрать красивый рисунок"},
	{"ai": 1, "n": "Сдвиг поля Y", "a": -20000.0, "b": 20000.0, "s": 100.0,
	 "h": "Выбор другого среза шумового поля по высоте (меняет рисунок, не трогая геометрию слоя)"},
	{"ai": 2, "n": "Сдвиг поля Z", "a": -200000.0, "b": 200000.0, "s": 500.0,
	 "h": "Двигает вуаль вперёд-назад: выбрать красивый рисунок"},
]

@export var sun_light_path: NodePath = ^"../DirectionalLight3D"
@export var env_path: NodePath = ^"../WorldEnvironment"
@export var rig_path: NodePath = ^"../VeilSkyRig"
@export var bounce_light_path: NodePath = ^"../BounceLight"
@export var capture_settle_frames := 40
@export var shots_dir := "user://skylab_shots/"
@export var refs_dir := "res://Assets/sky/refs/"
@export var start_visible := true	# false = панель скрыта на старте (открыть клавишей 8/F8); состояние ref4 применяется в любом случае

var _light: DirectionalLight3D = null
var _sky_mat: ShaderMaterial = null
var _rig: Node = null
var _bounce: DirectionalLight3D = null
var _sky: Sky = null
var _states := {}
var _settle := 0
var _layer: CanvasLayer = null
var _panel_root: Control = null
var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _elev_slider: HSlider = null
var _azim_slider: HSlider = null
var _moon_elev_slider: HSlider = null
var _moon_azim_slider: HSlider = null
var _cur_moon_elev := 50.0
var _cur_moon_azim := 0.0
var _blend_slider: HSlider = null
var _info: Label = null
var _overlay: TextureRect = null
var _capture_in := -1
var _state_tag := "ref4"
var _t := 4.0
var _cur_elev := 0.0
var _cur_azim := 180.0
var _writing := false
var _dragging := false
var _syncing := false
var _include_ui := false
var _vp_cache := Vector2.ZERO
var _saved_mouse_mode: int = Input.MOUSE_MODE_VISIBLE	# режим мыши до открытия панели (Q7.31)

## Q7.31: чтение/запись режима мыши — инъектируемые Callable (headless-DisplayServer
## игнорирует режим мыши; стенды подменяют эти две функции и проверяют логику честно).
var mouse_get_mode: Callable = func() -> int: return Input.get_mouse_mode()
var mouse_set_mode: Callable = func(m: int) -> void: Input.set_mouse_mode(m)
var _float_rows := {}		# uniform -> {"sl": HSlider, "val": Label}
var _offset_sliders := {}	# "x"/"y"/"z" -> HSlider
var _hc_offset_base := Vector3.ZERO
var _tint_veil := true
var _linear_mode := false	# текущий режим земли (Linear/Filmic)
var _tonemap_override := 0	# 0 = авто (Filmic для всех), 1 = всегда Filmic, 2 = всегда Linear (отладка)
# Вердикт заказчика 27.10.26: ОДИН режим — Filmic для всех ключей. Небо от тонмаппа
# не зависит (байпас §10.8), а палитры K0-K2 и свет земли пересчитаны inverse-Filmic,
# поэтому референсные цвета проходят через Filmic 1:1. Linear оставлен только как
# отладочный оверрайд (в нём цвета земли уходят от целей — это ожидаемо).
const LIN := {"K0": false, "K1": false, "K2": false, "K3": false, "K4": false, "K5": false, "K6": false}
var _env: Environment = null
var _saved_light_col: Variant = null


func _ready() -> void:
	_light = get_node_or_null(sun_light_path) as DirectionalLight3D
	if _light == null:
		push_error("[VeilSky] не найден DirectionalLight3D по пути %s" % str(sun_light_path))
	var we := get_node_or_null(env_path) as WorldEnvironment
	if we != null and we.environment != null and we.environment.sky != null:
		_sky_mat = we.environment.sky.sky_material as ShaderMaterial
		_sky = we.environment.sky
		_env = we.environment
	if _sky_mat == null:
		push_error("[VeilSky] не найден sky-материал для записи состояний/вуали")
	_rig = get_node_or_null(rig_path)
	_bounce = get_node_or_null(bounce_light_path) as DirectionalLight3D
	_states = {
		"K0": NIGHT_ADAPTED["K0"], "K1": NIGHT_ADAPTED["K1"], "K2": NIGHT_ADAPTED["K2"],
		"K3": ADAPTED["ref1"], "K4": ADAPTED["ref4"], "K5": ADAPTED["ref3"], "K6": ADAPTED["ref5"],
	}
	# значения материала до покраски состоянием — для честного отката чекбокса
	if _sky_mat != null:
		_saved_light_col = _sky_mat.get_shader_parameter("cloud_light_color")
		_hc_offset_base = _pv("hc_offset", Vector3.ZERO)
	_build_ui()
	_set_panel_visible(start_visible)
	_apply_t(5.0)	# старт с K4 (багровый закат = прежний ref4, решение D5)
	print("[VeilSky r11_s4] панель готова | 8/F8 панель, F9 скрин | t-блендер K0..K6 | старт K4 | вуаль: ручки SKYHC + пресеты A/B | свет земли: KEY/BOUNCE из LUT | градиент: сфера 360 (антисоляр 180), −wedge −zen_w −below, без линии горизонта")


## Чтение параметра материала с фолбэком (конвенция SkyLabMirror.pf/pv: null = не записан).
func _pf(pname: String, def: float) -> float:
	if _sky_mat == null:
		return def
	var v: Variant = _sky_mat.get_shader_parameter(pname)
	return def if v == null else float(v)


func _pb(pname: String, def: bool) -> bool:
	if _sky_mat == null:
		return def
	var v: Variant = _sky_mat.get_shader_parameter(pname)
	return def if v == null else bool(v)


func _pv(pname: String, def: Vector3) -> Vector3:
	if _sky_mat == null:
		return def
	var v: Variant = _sky_mat.get_shader_parameter(pname)
	if v == null:
		return def
	if v is Color:
		var c: Color = v
		return Vector3(c.r, c.g, c.b)
	return v as Vector3


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 8	# конвенция v0.13: слой 8
	add_child(_layer)

	_panel_root = Control.new()
	_panel_root.name = "VeilSkyRoot"
	_panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.visible = false	# фикс: старт строго скрытым — иначе _set_panel_visible(false)
								# в _ready выглядит как «закрытие» и восстанавливает мышь
								# из ещё не сохранённого режима (мышь уезжала в VISIBLE на старте)
	_layer.add_child(_panel_root)

	_panel = PanelContainer.new()
	_panel_root.add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 420)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(vbox)

	var title := Label.new()
	title.text = "VeilSky — Q7.32.PreOmega.SL"
	vbox.add_child(title)

	# ===== раздел 1: освещение — состояния по референсам (порт SkyLabPanel) =====
	vbox.add_child(_section("Освещение: состояния по референсам (M1)"))
	_blend_slider = _row_slider(vbox, "Состояние t (K0..K6)", 1.0, 7.0, 0.01, 5.0,
		"Состояние t: 1=K0 … 7=K6 (лестница по elev солнца), между целыми — бленд соседних ключей",
		func(v: float) -> void:
			if _writing:
				return
			_apply_t(v))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 4)
	vbox.add_child(presets)
	for i in range(7):
		var bt := Button.new()
		bt.text = "K%d" % i
		bt.tooltip_text = "%s · реф: %s" % [LADDER_NAMES[i], THUMBS[i]]
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		bt.pressed.connect(func() -> void: _apply_t(float(idx + 1)))
		presets.add_child(bt)
	_elev_slider = _row_slider(vbox, "Высота солнца, °", -35.0, 89.5, 0.1, 0.0,
		"Высота солнца (градусы): пишет DirectionalLight3D и sk_sun_dir",
		func(v: float) -> void:
			if _writing:
				return
			_set_sun(v, _cur_azim))
	_azim_slider = _row_slider(vbox, "Азимут солнца, °", 0.0, 360.0, 0.5, 180.0,
		"Азимут солнца (градусы): пишет DirectionalLight3D и sk_sun_dir",
		func(v: float) -> void:
			if _writing:
				return
			_set_sun(_cur_elev, v))
	_track_drag(_elev_slider)
	_track_drag(_azim_slider)
	_moon_elev_slider = _row_slider(vbox, "Высота луны, °", -35.0, 89.5, 0.1, _cur_moon_elev,
		"Высота луны (градусы): пишет sk_moon_dir НЕЗАВИСИМО от солнца (27.10.26 р.2); ночью ключевой свет сцены разворачивается на луну",
		func(v: float) -> void:
			if _writing:
				return
			_set_moon(v, _cur_moon_azim))
	_moon_azim_slider = _row_slider(vbox, "Азимут луны, °", 0.0, 360.0, 0.5, _cur_moon_azim,
		"Азимут луны (градусы): пишет sk_moon_dir НЕЗАВИСИМО от солнца; луна и солнце могут быть на небе одновременно",
		func(v: float) -> void:
			if _writing:
				return
			_set_moon(_cur_moon_elev, v))
	_track_drag(_moon_elev_slider)
	_track_drag(_moon_azim_slider)
	var tint := CheckButton.new()
	tint.text = "Красить вуаль состоянием (lit/zen)"
	tint.button_pressed = _tint_veil
	tint.tooltip_text = "Связка света состояния: lit → cloud_light_color (солнце/ореол). Выкл — значения материала"
	vbox.add_child(tint)
	tint.toggled.connect(func(on: bool) -> void:
		_tint_veil = on
		if not on and _sky_mat != null:
			if _saved_light_col != null:
				_sky_mat.set_shader_parameter("cloud_light_color", _saved_light_col)
		else:
			_apply_t(_t))
	var tmode := OptionButton.new()
	for mn in ["Земля: авто (Filmic)", "Земля: всегда Filmic", "Земля: всегда Linear (отладка)"]:
		tmode.add_item(mn)
	tmode.selected = _tonemap_override
	tmode.tooltip_text = "Тонмапп ЗЕМЛИ: вердикт 27.10.26 — один режим Filmic для всех ключей (палитры K0-K2 и свет земли пересчитаны inverse-Filmic, референсные цвета проходят через Filmic 1:1). Linear — только отладка. НЕБО от режима не зависит (байпас §10.8)"
	vbox.add_child(tmode)
	tmode.item_selected.connect(func(i: int) -> void:
		_tonemap_override = i
		_apply_t(_t))
	_info = Label.new()
	vbox.add_child(_info)
	var thumbs := HBoxContainer.new()
	thumbs.add_theme_constant_override("separation", 4)
	vbox.add_child(thumbs)
	for i in range(7):
		var path: String = refs_dir + str(THUMBS[i])
		var tr := TextureRect.new()
		var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if tex == null:
			push_warning("[VeilSky] референс не найден (миниатюра пропущена): %s" % path)
		tr.texture = tex
		tr.custom_minimum_size = Vector2(60, 60)
		tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_STOP
		tr.tooltip_text = "%s · реф: %s — клик: оверлей для сравнения" % [LADDER_NAMES[i], THUMBS[i]]
		var idx := i
		tr.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_show_overlay(idx))
		thumbs.add_child(tr)
	var shot := Button.new()
	shot.text = "Скриншот (F9)"
	shot.pressed.connect(func() -> void: _request_capture())
	vbox.add_child(shot)
	var inc := CheckButton.new()
	inc.text = "UI в кадре"
	vbox.add_child(inc)
	inc.toggled.connect(func(on: bool) -> void: _include_ui = on)

	# ===== раздел 2: вуаль (порт меню SKYHC бенча) =====
	vbox.add_child(_section("Вуаль: протяжённая облачность (SKYHC)"))
	var en := CheckButton.new()
	en.text = "Слой вуали (hc_enabled)"
	en.button_pressed = _pb("hc_enabled", false)
	en.tooltip_text = "Отдельный слой протяжённой облачности: мастер-гейт"
	vbox.add_child(en)
	en.toggled.connect(func(on: bool) -> void:
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("hc_enabled", on))
	var dbg := OptionButton.new()
	for m in HC_DEBUG_MODES:
		dbg.add_item(m)
	dbg.selected = int(_pf("hc_debug", 0.0))
	dbg.tooltip_text = "Что показывать: итог или внутренности слоя (плотность, покрытие, оптическая толщина)"
	vbox.add_child(_row_labeled("Просмотр вуали", dbg,
		"Что показывать: итог или внутренности слоя (плотность, покрытие, оптическая толщина)"))
	dbg.item_selected.connect(func(i: int) -> void:
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("hc_debug", float(i)))
	for row in VEIL_ROWS:
		_row_float_unif(vbox, row)
	var anch := CheckButton.new()
	anch.text = "Привязка к миру (hc_use_world_anchor)"
	anch.button_pressed = _pb("hc_use_world_anchor", true)
	anch.tooltip_text = "Вкл — рисунок стоит на месте при переносе камеры (честный параллакс); выкл — слой отсчитывается от камеры"
	vbox.add_child(anch)
	anch.toggled.connect(func(on: bool) -> void:
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("hc_use_world_anchor", on))
	var col := ColorPickerButton.new()
	var wm_col: Variant = _sky_mat.get_shader_parameter("veil_warm") if _sky_mat != null else null
	col.color = wm_col if wm_col is Color else Color(0.165, 0.078, 0.031)
	vbox.add_child(_row_labeled("Утепление вуали", col, "veil_warm: аддитивный тёплый сдвиг: veil_col = P(dir)·(1+lift)+warm (§3.2)"))
	col.color_changed.connect(func(c: Color) -> void:
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("veil_warm", c)
		_kick_settle())
	_preset_buttons(vbox, "Масштаб A/B", HC_SCALE_PRESETS,
		"Быстрое переключение размера образований: от мелких гряд до гигантских полос (A/B масштаба фазы 3)",
		func(i: int) -> void: _apply_hc_preset(HC_SCALE_PRESETS, i))
	_preset_buttons(vbox, "Характер A/B", HC_CHAR_PRESETS,
		"Быстрое переключение характера разрывов: от плотной вуали до редких гряд (A/B неоднородности фазы 3; геометрию масштаба не меняет)",
		func(i: int) -> void: _apply_hc_preset(HC_CHAR_PRESETS, i))
	for row in OFFSET_ROWS:
		_row_offset(vbox, row)
	var wind := HSlider.new()
	wind.min_value = 0.0
	wind.max_value = 3000.0
	wind.step = 10.0
	wind.value = float(_rig.get("wind_speed")) if (_rig != null and _rig.get("wind_speed") != null) else 0.0
	wind.scrollable = false	# колесо мыши не трогает ползунок (меню 8, фидбек 27.10.26 р.2)
	vbox.add_child(_row_labeled("Ветер (дрейф вуали), м/с", wind,
		"Скорость CPU-дрейфа поля вуали (пишет wind_speed рига VeilSkyRig; 0 = статично)"))
	wind.value_changed.connect(func(v: float) -> void:
		if _rig != null:
			_rig.set("wind_speed", v))

	var hint := Label.new()
	hint.text = "8/F8 панель | F9 скрин | клик миниатюры — реф слева"
	hint.add_theme_font_size_override("font_size", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	_overlay = TextureRect.new()
	_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_overlay.modulate = Color(1, 1, 1, 0.94)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	_overlay.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_overlay.visible = false)
	_panel_root.add_child(_overlay)
	_place_panel()


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = "— " + text + " —"
	l.add_theme_font_size_override("font_size", 12)
	return l


## Строка: имя + контрол (стиль меню бенча). Возвращает HBox.
func _row_labeled(label_text: String, control: Control, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.tooltip_text = tip
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.tooltip_text = tip
	row.add_child(control)
	return row


## Строка слайдера с числом справа; callback(v) — на изменение.
func _row_slider(parent: Control, label_text: String, minv: float, maxv: float, stepv: float,
		init: float, tip: String, callback: Callable) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = minv
	sl.max_value = maxv
	sl.step = stepv
	sl.value = init
	sl.custom_minimum_size = Vector2(0, 22)
	sl.scrollable = false	# фидбек 27.10.26 р.2: колесо мыши НЕ трогает ползунки меню 8 —
					# прокручивает только правый вертикальный скроллбар ScrollContainer
	var val := Label.new()
	val.custom_minimum_size = Vector2(56, 0)
	val.add_theme_font_size_override("font_size", 11)
	val.text = _fmt(sl.value)
	sl.value_changed.connect(func(v: float) -> void:
		val.text = _fmt(v)
		callback.call(v))
	var row := _row_labeled(label_text, sl, tip)
	row.add_child(val)
	parent.add_child(row)
	return sl


func _row_float_unif(parent: Control, r: Dictionary) -> void:
	var unif: String = r.u
	var sl := _row_slider(parent, r.n, r.a, r.b, r.s, _pf(unif, r.d), r.h,
		func(v: float) -> void:
			if _syncing:
				return
			if _sky_mat != null:
				_sky_mat.set_shader_parameter(unif, v)
			_kick_settle())
	_float_rows[unif] = {"sl": sl}


func _row_offset(parent: Control, r: Dictionary) -> void:
	var ai: int = int(r.ai)
	var sl := _row_slider(parent, r.n, r.a, r.b, r.s, _hc_offset_base[ai], r.h,
		func(v: float) -> void:
			if _syncing:
				return
			var vec := _hc_offset_base
			vec[ai] = v
			_hc_offset_base = vec
			if _rig != null and _rig.has_method("set_hc_base_offset"):
				_rig.set_hc_base_offset(_hc_offset_base)
			elif _sky_mat != null:
				_sky_mat.set_shader_parameter("hc_offset", _hc_offset_base))
	_offset_sliders[ai] = sl


func _preset_buttons(parent: Control, label_text: String, presets: Array, tip: String, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.tooltip_text = tip
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)
	for i in presets.size():
		var pr := (presets[i] as Dictionary)
		var bt := Button.new()
		bt.text = str(pr.b)
		bt.tooltip_text = str(pr.n) + ": " + str(pr.u)
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		bt.pressed.connect(func() -> void: cb.call(idx))
		row.add_child(bt)
	parent.add_child(row)


## Пресет вуали (порт apply_hc_scale_preset/apply_hc_char_preset бенча): записать
## uniform'ы таблицы + догнать слайдеры.
func _apply_hc_preset(presets: Array, idx: int) -> void:
	if _sky_mat == null or idx < 0 or idx >= presets.size():
		return
	var pr: Dictionary = presets[int(idx)]
	var u: Dictionary = pr.u
	for k in u.keys():
		_sky_mat.set_shader_parameter(k, u[k])
		_refresh_float_row(k)
	_kick_settle()
	print("[VeilSky] Пресет вуали: %s (%s)" % [str(pr.n), str(u)])


func _refresh_float_row(unif: String) -> void:
	if not _float_rows.has(unif) or _sky_mat == null:
		return
	var sl: HSlider = _float_rows[unif]["sl"]
	_syncing = true
	sl.value = _pf(unif, sl.value)
	_syncing = false


func _track_drag(sl: HSlider) -> void:
	sl.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			_dragging = ev.pressed)


func _fmt(v: float) -> String:
	return "%.0f" % v if absf(v) >= 1000.0 else "%.2f" % v


## 4b: состояние t ∈ [1..5]; между целыми — линейная интерполяция СОСЕДНИХ ключей
## последовательности SEQ (палитра неба + солнце). Целые t = пресеты. Порт _apply_t
## SkyLabPanel v0.5.2: записи в удалённые uniform'ы (sk_ramp*/sk_rim_col/atmo_color)
## и карточки сняты; роль r0 продолжает жить в sk_anti_col (shd в r10_s4 больше не
## записывается — «тень ниже горизонта» удалена вместе с границей, вариант H1).
func _apply_t(t: float) -> void:
	_t = clampf(t, 1.0, 7.0)	# 7 ключей лестницы
	var i0 := int(floor(_t - 1.0))
	i0 = clampi(i0, 0, 5)	# 7 ключей: i0 до K5, i1 = i0+1 до K6
	var i1 := i0 + 1
	var f := clampf(_t - 1.0 - float(i0), 0.0, 1.0)
	var a: Dictionary = _states[SEQ[i0]]
	var b: Dictionary = _states[SEQ[i1]]
	var pa: Dictionary = PAL[SEQ[i0]]
	var pb: Dictionary = PAL[SEQ[i1]]
	var hor: Vector3 = (pa["horizon"] as Vector3).lerp(pb["horizon"] as Vector3, f)
	var glo: Vector3 = (pa["glow"] as Vector3).lerp(pb["glow"] as Vector3, f)
	var lit: Vector3 = (a["lit"] as Vector3).lerp(b["lit"] as Vector3, f)
	# r10_s4: локальные zen (PAL.zenith) и shd (shadow) удалены вместе со своими
	# записями sk_zenith / sk_below_col — uniform'ов больше нет (H4 и H1).
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("sk_horizon", hor)
		# 27.10.26: ядро зари — отдельная роль (ночи: почти белое/розовое HDR-ядро
		# вместо горизонта; K3-K6: glow = horizon — побитово прежний вид)
		_sky_mat.set_shader_parameter("sk_glow_col", glo)
		_sky_mat.set_shader_parameter("sk_band_col", (pa["band"] as Vector3).lerp(pb["band"] as Vector3, f))
		_sky_mat.set_shader_parameter("sk_band2_col", (pa["band2"] as Vector3).lerp(pb["band2"] as Vector3, f))
		# r10_s4 (H1): запись sk_below_col удалена — ниже горизонта работает та же рампа.
		_sky_mat.set_shader_parameter("sk_anti_col", (pa["anti"] as Vector3).lerp(pb["anti"] as Vector3, f))
		# форма купола (SHAPE, r10_s4): интенсивность ореола + low_dim + положения стопов
		# p1..p5 — из той же лестницы; веток по номеру ключа в шейдере нет.
		# Имя uniform'а = "sk_" + ключ (wedge_int/below_int/zen_w из списка изъяты).
		var sh0: Dictionary = SHAPE[SEQ[i0]]
		var sh1: Dictionary = SHAPE[SEQ[i1]]
		for sk_key in SHAPE_KEYS:
			_sky_mat.set_shader_parameter("sk_" + sk_key, lerpf(float(sh0[sk_key]), float(sh1[sk_key]), f))
		# SKY_TZ_LUT7 §10.2: средний пояс P(dir) и все параметры вуали — из той же
		# лестницы состояний: вуаль берёт ЦВЕТ из общей палитры, однотонность исключена.
		_sky_mat.set_shader_parameter("sk_mid", (pa["mid"] as Vector3).lerp(pb["mid"] as Vector3, f))
		var v0: Dictionary = VEILP[SEQ[i0]]
		var v1: Dictionary = VEILP[SEQ[i1]]
		_sky_mat.set_shader_parameter("veil_master", lerpf(float(v0["master"]), float(v1["master"]), f))
		_sky_mat.set_shader_parameter("veil_sun", lerpf(float(v0["sun"]), float(v1["sun"]), f))
		_sky_mat.set_shader_parameter("veil_sun_exp", lerpf(float(v0["sun_exp"]), float(v1["sun_exp"]), f))
		_sky_mat.set_shader_parameter("veil_lift", lerpf(float(v0["lift"]), float(v1["lift"]), f))
		_sky_mat.set_shader_parameter("veil_warm", (v0["warm"] as Color).lerp(v1["warm"] as Color, f))
		_sky_mat.set_shader_parameter("veil_blob", (v0["blob"] as Color).lerp(v1["blob"] as Color, f))
		# §10.6: солнце/луна/звёзды — из той же лестницы (§8.4)
		var s0: Dictionary = SUNMOON[SEQ[i0]]
		var s1: Dictionary = SUNMOON[SEQ[i1]]
		_sky_mat.set_shader_parameter("sun_disk_color", (s0["disc"] as Vector3).lerp(s1["disc"] as Vector3, f))
		_sky_mat.set_shader_parameter("sun_size_deg", lerpf(float(s0["size"]), float(s1["size"]), f))
		_sky_mat.set_shader_parameter("sun_core_int", lerpf(float(s0["core"]), float(s1["core"]), f))
		_sky_mat.set_shader_parameter("moon_phase", lerpf(float(s0["mphase"]), float(s1["mphase"]), f))
		_sky_mat.set_shader_parameter("moon_color", (s0["mcol"] as Vector3).lerp(s1["mcol"] as Vector3, f))
		_sky_mat.set_shader_parameter("moon_glow_int", lerpf(float(s0["mglow"]), float(s1["mglow"]), f))
		_sky_mat.set_shader_parameter("star_intensity", lerpf(float(s0["star"]), float(s1["star"]), f))
		_sky_mat.set_shader_parameter("streak_int", lerpf(float(s0["streak"]), float(s1["streak"]), f))
		_sky_mat.set_shader_parameter("veil_moon", lerpf(float(v0["moon"]), float(v1["moon"]), f))
		# связка света: lit как цвет источника (солнце/ореол); вуали отдельная заливка
		# больше не нужна — её цвет = P(dir) (§10.2)
		if _tint_veil:
			_sky_mat.set_shader_parameter("cloud_light_color", lit)
	# тонмапп земли: вердикт 27.10.26 — ОДИН режим Filmic (авто = Filmic для всех
	# ключей, LIN все false); оверрайд оставлен для отладки
	var lin_target := false
	match _tonemap_override:
		1: lin_target = false
		2: lin_target = true
		_: lin_target = bool(LIN[SEQ[i0 if f < 0.5 else i1]])
	_set_lin_raw(lin_target)
	# SKY_TZ_LUT7 §10.3: свет земли из той же лестницы — KEY (color/energy основного
	# DirectionalLight3D) и BOUNCE (нижний свет BounceLight); FILL = IBL неба (§7).
	var g0: Dictionary = GROUND[SEQ[i0]]
	var g1: Dictionary = GROUND[SEQ[i1]]
	var kc: Color = (g0["key"] as Color).lerp(g1["key"] as Color, f)
	var ke: float = lerpf(float(g0["e"]), float(g1["e"]), f)
	var bc: Color = (g0["bounce"] as Color).lerp(g1["bounce"] as Color, f)
	var be: float = lerpf(float(g0["be"]), float(g1["be"]), f)
	if _light != null:
		_light.light_color = _ground_col(kc)
		_light.light_energy = ke
	if _bounce != null:
		_bounce.light_color = _ground_col(bc)
		_bounce.light_energy = be
	_kick_settle()
	_state_tag = SEQ[i0 if f < 0.5 else i1]
	_writing = true
	if _blend_slider != null:
		_blend_slider.value = _t
	_writing = false
	var elev := lerpf(PRESET_ELEV[i0], PRESET_ELEV[i1], f)
	var azim := lerpf(PRESET_AZIM[i0], PRESET_AZIM[i1], f)
	_set_sun(elev, azim)
	# луна — из своей лестницы (независима от солнца, 27.10.26 р.2)
	var m0: Dictionary = MOONPOS[SEQ[i0]]
	var m1: Dictionary = MOONPOS[SEQ[i1]]
	_set_moon(lerpf(float(m0["elev"]), float(m1["elev"]), f),
			lerpf(float(m0["azim"]), float(m1["azim"]), f))
	_update_info()


## Порт _set_sun SkyLabPanel: dir = направление НА солнце; свет смотрит вдоль -dir
## (looking_at(-dir)); sk_sun_dir пишется тем же вектором (конвенция панели).
func _set_sun(elev: float, azim: float) -> void:
	_cur_elev = clampf(elev, -35.0, 89.5)	# K0 = -30° (ночь), прежний clamp -15 резал лестницу
	_cur_azim = azim
	var dir := _dir_from_elev_azim(_cur_elev, _cur_azim)
	# feedback 25.10.26: ночью (солнце ниже -2°) игровой ключ светит С ЛУНЫ — иначе свет
	# шёл из-под земли и луна «не влияла на мир». 27.10.26 р.2: луна независима — свет
	# разворачивается на ФАКТИЧЕСКОЕ направление луны (sk_moon_dir), а не на антисоляр.
	var light_dir := dir if _cur_elev > -2.0 else _moon_dir()
	_point_light_to(light_dir)
	_writing = true
	if _elev_slider != null:
		_elev_slider.value = _cur_elev
	if _azim_slider != null:
		_azim_slider.value = _cur_azim
	_writing = false
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("sk_sun_dir", dir)
	_kick_settle()
	_update_info()


## Направление НА солнце/луну из высоты/азимута (конвенция панели: azim 180° = -Z).
func _dir_from_elev_azim(elev_deg: float, azim_deg: float) -> Vector3:
	var e := deg_to_rad(elev_deg)
	var a := deg_to_rad(azim_deg)
	return Vector3(cos(e) * sin(a), sin(e), cos(e) * cos(a))


func _moon_dir() -> Vector3:
	return _dir_from_elev_azim(_cur_moon_elev, _cur_moon_azim)


## Разворот DirectionalLight3D на источник (свет смотрит вдоль -light_dir).
func _point_light_to(light_dir: Vector3) -> void:
	if _light == null:
		return
	var t := Transform3D()
	t = t.looking_at(-light_dir, Vector3.UP)
	t.origin = _light.global_position
	_light.global_transform = t


## Луна (фидбек 27.10.26 р.2): независимое положение. Пишет sk_moon_dir; ночью
## (elev солнца ≤ -2°) ключевой свет сцены следует за луной (та же логика освещения,
## что «ночью ключ светит с луны», но без жёсткой привязки луны к антисоляру).
func _set_moon(elev: float, azim: float) -> void:
	_cur_moon_elev = clampf(elev, -35.0, 89.5)
	_cur_moon_azim = azim
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("sk_moon_dir", _moon_dir())
	if _cur_elev <= -2.0:
		_point_light_to(_moon_dir())
	_writing = true
	if _moon_elev_slider != null:
		_moon_elev_slider.value = _cur_moon_elev
	if _moon_azim_slider != null:
		_moon_azim_slider.value = _cur_moon_azim
	_writing = false
	_kick_settle()
	_update_info()


func _update_info() -> void:
	if _info != null:
		_info.text = "t=%.2f (%s)  sun %+.1f°/%.1f°  moon %+.1f°/%.1f°" % [
			_t, _state_tag, _cur_elev, _cur_azim, _cur_moon_elev, _cur_moon_azim]


func _show_overlay(idx: int) -> void:
	var path := refs_dir + str(THUMBS[clampi(idx, 0, THUMBS.size() - 1)])
	if not ResourceLoader.exists(path):
		return
	_overlay.texture = load(path)
	_overlay.visible = true
	_place_overlay()


## Референс: левая граница = левая граница окна, вертикально по центру.
func _place_overlay() -> void:
	if _overlay == null or not _overlay.visible or _overlay.texture == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vps := vp.get_visible_rect().size
	var ts := _overlay.texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var k := minf(vps.x / ts.x, vps.y / ts.y)
	_overlay.position = Vector2(0.0, (vps.y - ts.y * k) * 0.5)
	_overlay.size = Vector2(ts.x * k, ts.y * k)


## Панель: правый верхний угол окна с отступом 8 px. ФИКС «правый край вылезает за
## экран»: ширина берётся ФАКТИЧЕСКАЯ (строки пресетов «Масштаб/Характер A/B» шире
## PANEL_W — контейнер всё равно расширится), позиция и размер clamp'ятся окном.
func _place_panel() -> void:
	if _panel == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vps := vp.get_visible_rect().size
	var w := maxf(_panel.get_combined_minimum_size().x, PANEL_W)
	w = minf(w, vps.x - 16.0)
	var h := maxf(_panel.get_combined_minimum_size().y, 32.0)
	h = minf(h, vps.y - 16.0)
	var x := vps.x - w - 8.0
	if x < 4.0:
		x = 4.0
	_panel.position = Vector2(x, 8.0)
	_panel.size = Vector2(w, h)
	_vp_cache = vps


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F8 or event.keycode == KEY_8:
			_set_panel_visible(not _panel_root.visible)
		elif event.keycode == KEY_F9:
			_request_capture()


## §7: любой ввод, меняющий небо/свет, форсирует REALTIME-пересборку кубмапы на
## SETTLE_FRAMES кадров; в статике возвращаем INCREMENTAL (дёшево в простое).
func _kick_settle() -> void:
	_settle = maxi(_settle, SETTLE_FRAMES)
	if _sky != null:
		_sky.process_mode = Sky.PROCESS_MODE_REALTIME


## Эксперимент «земля без Filmic»: тонмапп Environment = Linear (только sRGB-encode),
## композит неба переключается на srgb_to_linear (небо выглядит так же), цвета земли
## пред-конвертируются sRGB->linear, чтобы hex'ы таблицы доходили до экрана 1:1.
func set_linear_mode(on: bool) -> void:
	_tonemap_override = 2 if on else 1
	_apply_t(_t)


func _set_lin_raw(on: bool) -> void:
	if _linear_mode == on:
		return
	_linear_mode = on
	if _env != null:
		_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR if on else Environment.TONE_MAPPER_FILMIC
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("comp_linear", on)


func _s2l(u: float) -> float:
	return u / 12.92 if u <= 0.04045 else pow((u + 0.055) / 1.055, 2.4)


func _ground_col(c: Color) -> Color:
	if _linear_mode:
		return Color(_s2l(c.r), _s2l(c.g), _s2l(c.b), 1.0)
	return c


## Видимость панели + освобождение мыши (паттерн SkyDebugUI Q7.31): открытие
## сохраняет текущий режим и ставит VISIBLE, закрытие возвращает сохранённый.
func _set_panel_visible(v: bool) -> void:
	if _panel_root == null or v == _panel_root.visible:
		return
	if v:
		_saved_mouse_mode = int(mouse_get_mode.call())
		if _saved_mouse_mode != Input.MOUSE_MODE_VISIBLE:
			mouse_set_mode.call(Input.MOUSE_MODE_VISIBLE)
	else:
		mouse_set_mode.call(_saved_mouse_mode)
	_panel_root.visible = v


func _request_capture() -> void:
	_capture_in = max(1, capture_settle_frames)


func _process(_delta: float) -> void:
	var vp := get_viewport()
	if vp != null and vp.get_visible_rect().size != _vp_cache:
		_place_panel()
	# read-only синк со светом (конвенция бенча): только вне драга и при изменении > 0.2°.
	# ФИКС 27.10.26: ночью (_cur_elev <= -2) игровой ключ светит С ЛУНЫ (_set_sun
	# flipped light на антисоляр) — настоящее солнце = -d. Без этого лунное направление
	# записывалось в sk_sun_dir, купол разворачивался, а «солнце» вставало на антисоляр.
	if _light != null and not _writing and not _dragging:
		var d := _light.global_transform.basis.z
		if _cur_elev > -2.0:
			# днём ключ кодирует СОЛНЦЕ — read-only синк солнца (конвенция бенча, порог 0.2°)
			var elev := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
			var azim := rad_to_deg(atan2(d.x, d.z))
			if absf(elev - _cur_elev) > 0.2 or absf(azim - _cur_azim) > 0.2:
				_cur_elev = clampf(elev, -35.0, 89.5)	# K0 = -30° (ночь), прежний clamp -15 резал лестницу
				_cur_azim = azim
				_writing = true
				if _elev_slider != null:
					_elev_slider.value = _cur_elev
				if _azim_slider != null:
					_azim_slider.value = _cur_azim
				_writing = false
				if _sky_mat != null:
					_sky_mat.set_shader_parameter("sk_sun_dir", d)
				_update_info()
		else:
			# ночью ключ кодирует ЛУНУ (27.10.26 р.2): внешний разворот света = правка луны
			var mel := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
			var maz := rad_to_deg(atan2(d.x, d.z))
			if absf(mel - _cur_moon_elev) > 0.2 or absf(maz - _cur_moon_azim) > 0.2:
				_set_moon(mel, maz)
	if _settle > 0:
		_settle -= 1
		if _settle == 0 and _sky != null:
			_sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	if _capture_in > 0:
		_capture_in -= 1
		if _capture_in == 0:
			_arm_capture()
	if _overlay.visible:
		_place_overlay()


func _arm_capture() -> void:
	if not _include_ui:
		_layer.visible = false
	if not RenderingServer.frame_post_draw.is_connected(_do_capture):
		RenderingServer.frame_post_draw.connect(_do_capture, CONNECT_ONE_SHOT)


func _do_capture() -> void:
	var img: Image = null
	var vpt := get_viewport()
	if vpt != null and vpt.get_texture() != null:
		img = vpt.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("[VeilSky] не удалось снять кадр (пустой image)")
	else:
		DirAccess.make_dir_recursive_absolute(shots_dir)
		var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
		var path := "%sveilsky_%s_el%+.1f_az%.1f_%s.png" % [shots_dir, _state_tag, _cur_elev, _cur_azim, stamp]
		var err := img.save_png(path)
		if err != OK:
			push_error("[VeilSky] save_png ошибка %d: %s" % [err, path])
		else:
			print("[VeilSky] скрин сохранён: %s" % ProjectSettings.globalize_path(path))
	if not _include_ui:
		_layer.visible = true
