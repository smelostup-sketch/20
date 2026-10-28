extends Node
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
## данные света вуали общие с небом: lit → cloud_light_color, zen → cloud_ambient_sky_color
## (в v0.5.2 вуаль была выключена, связка не использовалась; выкл → значения материала);
## (б) слайдер ветра (дрейф вуали) — пишет wind_speed рига VeilSkyRig;
## (в) строки панели единообразны: имя + контрол + число (стиль меню бенча).
## Управление: 8/F8 — панель, F9 — скриншот (user://skylab_shots/). Слой 8 (конвенция v0.13).

# Полные роли M1 (adapted, inv-Filmic): zenith/horizon/lit/shadow/rim = palettes.json
const ADAPTED := {
	"ref1": {
		"zenith": Vector3(0.118023, 0.176595, 0.520467),
		"horizon": Vector3(2.000000, 0.651464, 0.143677),
		"lit": Vector3(2.000000, 0.188911, 0.063227),
		"shadow": Vector3(0.080143, 0.054996, 0.143677),
		"rim": Vector3(2.000000, 0.107580, 0.039325),
	},
	"ref2": {
		"zenith": Vector3(0.083492, 0.109613, 0.173629),
		"horizon": Vector3(2.000000, 0.205382, 0.143677),
		"lit": Vector3(2.000000, 0.078501, 0.060409),
		"shadow": Vector3(0.143677, 0.054996, 0.066121),
		"rim": Vector3(2.000000, 0.748773, 0.272116),
	},
	"ref3": {
		"zenith": Vector3(0.205382, 0.254722, 1.040193),
		"horizon": Vector3(2.000000, 1.065300, 0.467553),
		"lit": Vector3(2.000000, 0.549748, 0.626839),
		"shadow": Vector3(0.413874, 0.192106, 0.272116),
		"rim": Vector3(2.000000, 1.377643, 0.467553),
	},
	"ref4": {
		"zenith": Vector3(0.015954, 0.022894, 0.060409),
		"horizon": Vector3(2.000000, 0.078501, 0.036102),
		"lit": Vector3(2.000000, 0.107580, 0.054996),
		"shadow": Vector3(0.143677, 0.025475, 0.036102),
		"rim": Vector3(2.000000, 0.258963, 0.188911),
	},
	"ref5": {
		"zenith": Vector3(0.024600, 0.109613, 0.355120),
		"horizon": Vector3(2.000000, 1.065300, 0.406819),
		"lit": Vector3(1.866999, 1.500198, 1.205897),
		"shadow": Vector3(0.205382, 0.285952, 0.539759),
		"rim": Vector3(1.340321, 0.272116, 0.188911),
	},
}
const SEQ := ["ref1", "ref2", "ref3", "ref4", "ref5"]	# последовательность бленда (4b)
const PRESET_ELEV := [-1.5, 1.0, 10.0, 0.0, -5.0]
const PRESET_AZIM := [180.0, 180.0, 180.0, 180.0, 180.0]
const PANEL_W := 352.0

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
	{"u": "hc_light_gain", "n": "Прямой свет вуали", "a": 0.0, "b": 2.0, "s": 0.05, "d": 1.0,
	 "h": "Яркость солнечной составляющей вуали: независимая ручка интенсивности слоя (0 — остаётся только заливка небом)"},
	{"u": "hc_ambient_gain", "n": "Заливка неба вуали", "a": 0.0, "b": 2.0, "s": 0.05, "d": 1.0,
	 "h": "Яркость небесной заливки вуали (0 — остаётся только прямой свет)"},
	{"u": "hc_layer_bottom", "n": "Низ вуали", "a": 3000.0, "b": 12000.0, "s": 100.0, "d": 6000.0,
	 "h": "Высота нижней границы слоя вуали в метрах"},
	{"u": "hc_layer_top", "n": "Верх вуали", "a": 3500.0, "b": 15000.0, "s": 100.0, "d": 7200.0,
	 "h": "Высота верхней границы: вместе с нижней задаёт толщину и плотность на взгляд"},
	{"u": "hc_curtain_start", "n": "Начало растворения", "a": 1000.0, "b": 20000.0, "s": 250.0, "d": 4000.0,
	 "h": "С какой длины пути в слое вуаль начинает таять (к горизонту путь длиннее)"},
	{"u": "hc_curtain_end", "n": "Полное растворение", "a": 2000.0, "b": 40000.0, "s": 250.0, "d": 14000.0,
	 "h": "Длина пути, за которой вуали нет: горизонт остаётся чистым, без полосы и мерцания"},
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
@export var capture_settle_frames := 40
@export var shots_dir := "user://skylab_shots/"
@export var refs_dir := "res://Q7.32_SKYprav_3.1/refs/"

var _light: DirectionalLight3D = null
var _sky_mat: ShaderMaterial = null
var _rig: Node = null
var _layer: CanvasLayer = null
var _panel_root: Control = null
var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _elev_slider: HSlider = null
var _azim_slider: HSlider = null
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
var _float_rows := {}		# uniform -> {"sl": HSlider, "val": Label}
var _offset_sliders := {}	# "x"/"y"/"z" -> HSlider
var _hc_offset_base := Vector3.ZERO
var _tint_veil := true
var _saved_light_col: Variant = null
var _saved_amb_col: Variant = null


func _ready() -> void:
	_light = get_node_or_null(sun_light_path) as DirectionalLight3D
	if _light == null:
		push_error("[VeilSky] не найден DirectionalLight3D по пути %s" % str(sun_light_path))
	var we := get_node_or_null(env_path) as WorldEnvironment
	if we != null and we.environment != null and we.environment.sky != null:
		_sky_mat = we.environment.sky.sky_material as ShaderMaterial
	if _sky_mat == null:
		push_error("[VeilSky] не найден sky-материал для записи состояний/вуали")
	_rig = get_node_or_null(rig_path)
	# значения материала до покраски состоянием — для честного отката чекбокса
	if _sky_mat != null:
		_saved_light_col = _sky_mat.get_shader_parameter("cloud_light_color")
		_saved_amb_col = _sky_mat.get_shader_parameter("cloud_ambient_sky_color")
		_hc_offset_base = _pv("hc_offset", Vector3.ZERO)
	_build_ui()
	_apply_t(4.0)	# старт с ref4 (решение D5 SkyLabPanel)
	print("[VeilSky] панель готова | 8/F8 панель, F9 скрин | t-блендер ref1..ref5 | старт ref4 | вуаль: ручки SKYHC + пресеты A/B")


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
	_blend_slider = _row_slider(vbox, "Состояние t (ref1..ref5)", 1.0, 5.0, 0.01, 4.0,
		"Состояние t: 1=ref1 … 5=ref5, между целыми — плавный бленд соседних ключей",
		func(v: float) -> void:
			if _writing:
				return
			_apply_t(v))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 4)
	vbox.add_child(presets)
	for i in range(5):
		var bt := Button.new()
		bt.text = "Ref %d" % (i + 1)
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		bt.pressed.connect(func() -> void: _apply_t(float(idx + 1)))
		presets.add_child(bt)
	_elev_slider = _row_slider(vbox, "Высота солнца, °", -15.0, 89.5, 0.1, 0.0,
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
	var tint := CheckButton.new()
	tint.text = "Красить вуаль состоянием (lit/zen)"
	tint.button_pressed = _tint_veil
	tint.tooltip_text = "Связка SKYHC-4 (общие данные света): lit → cloud_light_color, zen → cloud_ambient_sky_color. Выкл — значения материала"
	vbox.add_child(tint)
	tint.toggled.connect(func(on: bool) -> void:
		_tint_veil = on
		if not on and _sky_mat != null:
			if _saved_light_col != null:
				_sky_mat.set_shader_parameter("cloud_light_color", _saved_light_col)
			if _saved_amb_col != null:
				_sky_mat.set_shader_parameter("cloud_ambient_sky_color", _saved_amb_col)
		else:
			_apply_t(_t))
	_info = Label.new()
	vbox.add_child(_info)
	var thumbs := HBoxContainer.new()
	thumbs.add_theme_constant_override("separation", 4)
	vbox.add_child(thumbs)
	for i in range(5):
		var path := refs_dir + "ref%d.png" % (i + 1)
		var tr := TextureRect.new()
		var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if tex == null:
			push_error("[VeilSky] референс не найден: %s" % path)
		tr.texture = tex
		tr.custom_minimum_size = Vector2(60, 60)
		tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_STOP
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
	var lit := CheckButton.new()
	lit.text = "Освещение вуали (hc_use_lighting)"
	lit.button_pressed = _pb("hc_use_lighting", false)
	lit.tooltip_text = "Вкл — цвет вуали из ОБЩИХ данных света (солнце, градиент неба, рампа заката); выкл — постоянный цвет"
	vbox.add_child(lit)
	lit.toggled.connect(func(on: bool) -> void:
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("hc_use_lighting", on))
	var anch := CheckButton.new()
	anch.text = "Привязка к миру (hc_use_world_anchor)"
	anch.button_pressed = _pb("hc_use_world_anchor", true)
	anch.tooltip_text = "Вкл — рисунок стоит на месте при переносе камеры (честный параллакс); выкл — слой отсчитывается от камеры"
	vbox.add_child(anch)
	anch.toggled.connect(func(on: bool) -> void:
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("hc_use_world_anchor", on))
	var col := ColorPickerButton.new()
	var hc_col: Variant = _sky_mat.get_shader_parameter("hc_color") if _sky_mat != null else null
	col.color = hc_col if hc_col is Color else Color(0.92, 0.93, 0.96)
	vbox.add_child(_row_labeled("Цвет вуали (альбедо)", col, "Тон слоя (альбедо в модели освещения SKYHC-4)"))
	col.color_changed.connect(func(c: Color) -> void:
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("hc_color", c))
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
				_sky_mat.set_shader_parameter(unif, v))
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
## и карточки сняты; роли r0/shd продолжают жить в sk_anti_col/sk_below_col.
func _apply_t(t: float) -> void:
	_t = clampf(t, 1.0, 5.0)
	var i0 := int(floor(_t - 1.0))
	i0 = clampi(i0, 0, 3)
	var i1 := i0 + 1
	var f := clampf(_t - 1.0 - float(i0), 0.0, 1.0)
	var a: Dictionary = ADAPTED[SEQ[i0]]
	var b: Dictionary = ADAPTED[SEQ[i1]]
	var zen: Vector3 = (a["zenith"] as Vector3).lerp(b["zenith"] as Vector3, f)
	var hor: Vector3 = (a["horizon"] as Vector3).lerp(b["horizon"] as Vector3, f)
	var lit: Vector3 = (a["lit"] as Vector3).lerp(b["lit"] as Vector3, f)
	var shd: Vector3 = (a["shadow"] as Vector3).lerp(b["shadow"] as Vector3, f)
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("sk_zenith", zen)
		_sky_mat.set_shader_parameter("sk_horizon", hor)
		_sky_mat.set_shader_parameter("sk_glow_col", hor)
		var r0 := shd.lerp(zen, 0.6)	# сине-фиолетовая глубина (роль ramp0 v0.5.2)
		# v0.9 (Г2): ниже горизонта — тень состояния; v0.13: антисоляр = глубокая тень × 0.30
		_sky_mat.set_shader_parameter("sk_below_col", shd.lerp(Vector3.ZERO, 0.45))
		_sky_mat.set_shader_parameter("sk_anti_col", r0 * 0.30)
		# ДОБАВЛЕНО (связка SKYHC-4, чекбокс «Красить вуаль состоянием»): общие данные
		# света — lit как цвет источника, zen как небесная заливка вуали.
		if _tint_veil:
			_sky_mat.set_shader_parameter("cloud_light_color", lit)
			_sky_mat.set_shader_parameter("cloud_ambient_sky_color", zen)
	_state_tag = SEQ[i0 if f < 0.5 else i1]
	_writing = true
	if _blend_slider != null:
		_blend_slider.value = _t
	_writing = false
	var elev := lerpf(PRESET_ELEV[i0], PRESET_ELEV[i1], f)
	var azim := lerpf(PRESET_AZIM[i0], PRESET_AZIM[i1], f)
	_set_sun(elev, azim)
	_update_info()


## Порт _set_sun SkyLabPanel: dir = направление НА солнце; свет смотрит вдоль -dir
## (looking_at(-dir)); sk_sun_dir пишется тем же вектором (конвенция панели).
func _set_sun(elev: float, azim: float) -> void:
	_cur_elev = clampf(elev, -15.0, 89.5)
	_cur_azim = azim
	var e := deg_to_rad(_cur_elev)
	var a := deg_to_rad(_cur_azim)
	var dir := Vector3(cos(e) * sin(a), sin(e), cos(e) * cos(a))
	if _light != null:
		_writing = true
		var t := Transform3D()
		t = t.looking_at(-dir, Vector3.UP)
		t.origin = _light.global_position
		_light.global_transform = t
		if _elev_slider != null:
			_elev_slider.value = _cur_elev
		if _azim_slider != null:
			_azim_slider.value = _cur_azim
		_writing = false
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("sk_sun_dir", dir)
	_update_info()


func _update_info() -> void:
	if _info != null:
		_info.text = "t=%.2f (%s)  elev=%+.1f°  azim=%.1f°" % [_t, _state_tag, _cur_elev, _cur_azim]


func _show_overlay(idx: int) -> void:
	var path := refs_dir + "ref%d.png" % (idx + 1)
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


## Панель: правый верхний угол окна с отступом 8 px, ширина фикс, высота не больше окна.
func _place_panel() -> void:
	if _panel == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vps := vp.get_visible_rect().size
	var h := maxf(_panel.get_combined_minimum_size().y, 32.0)
	h = minf(h, vps.y - 16.0)
	var x := vps.x - PANEL_W - 8.0
	if x < 4.0:
		x = 4.0
	_panel.position = Vector2(x, 8.0)
	_panel.size = Vector2(PANEL_W, h)
	_vp_cache = vps


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F8 or event.keycode == KEY_8:
			_panel_root.visible = not _panel_root.visible
		elif event.keycode == KEY_F9:
			_request_capture()


func _request_capture() -> void:
	_capture_in = max(1, capture_settle_frames)


func _process(_delta: float) -> void:
	var vp := get_viewport()
	if vp != null and vp.get_visible_rect().size != _vp_cache:
		_place_panel()
	# read-only синк со светом (конвенция бенча): только вне драга и при изменении > 0.2°
	if _light != null and not _writing and not _dragging:
		var d := _light.global_transform.basis.z
		var elev := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
		var azim := rad_to_deg(atan2(d.x, d.z))
		if absf(elev - _cur_elev) > 0.2 or absf(azim - _cur_azim) > 0.2:
			_cur_elev = clampf(elev, -15.0, 89.5)
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
