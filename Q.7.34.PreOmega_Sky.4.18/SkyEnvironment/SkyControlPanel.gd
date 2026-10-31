extends CanvasLayer
class_name SkyControlPanel
## Q7.33 — панель настройки неба (глава 13 ТЗ). Каркас из A: CanvasLayer,
## хоткей KEY_8 (решение 18), _toggle_panel с освобождением мыши, сигнал
## input_block_changed, _add_slider, GridContainer с TextureButton под пресеты.
## Print-диагностика размеров из A удалена (шаг F.1).
## Панель НЕ ПИШЕТ ни в материал, ни в свет напрямую: только через методы
## SkyEnvironmentController / SkyLightController (п. 9, два адреса записи).

signal input_block_changed(blocked: bool)

@export var controller: SkyEnvironmentController
@export var presets: Array[SkyPreset] = []
@export var presets_dir: String = "res://SkyEnvironment/SkyPreset/"

# Sky3.2.4: рампа 4 стопа. Подписи ДОСЛОВНО из palletes.html («Шаг 1 (верх)» …
# «Шаг 4 (низ/горизонт)»); порядок на полосе — ОТ солнца (u=0 слева), поэтому
# индекс 0 = шаг 4 (у солнца), индекс 3 = шаг 1 (антисоляр/зенит).
# 4.1.7 (инструкция заказчика): доли — данные владельца SkyGradientWeightsComponent
# (uniform'ы sk_q*/sk_sharp и P_UNIS/MIN_GAP_PCT удалены вместе со старой
# моделью окон; логика перераспределения/замков живёт в компоненте).
const STOP_LABELS := ["Шаг 4 (низ/горизонт)", "Шаг 3", "Шаг 2", "Шаг 1 (верх)"]
const COL_UNIS := ["sk_c4", "sk_c3", "sk_c2", "sk_c1"]
const COL_FIELDS := ["col_sky4", "col_sky3", "col_sky2", "col_sky1"]

var _panel: PanelContainer
var _tabs: TabContainer
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _is_open: bool = false
var _syncing := false

# вкладка «Градиент»
var _strip: RampStrip
var _stop_pickers: Array[ColorPickerButton] = []
var _grad_sliders: Array[HSlider] = []	# 4.1.7: ручки долей владельца (component)
var _grad_locks: Array[CheckButton] = []
var _table_labels: Array[Label] = []
var _breathe_slider: HSlider	# Q7.34 (COLORS6): «дыхание» купола
var _squeeze_slider: HSlider	# Q7.34 (COLORS7): компенсация складки у горизонта
var _arc_slider: HSlider
# вкладка «Источник»
var _sun_az: HSlider
var _sun_el: HSlider
var _moon_az: HSlider
var _moon_el: HSlider
var _sun_on: CheckButton
var _moon_on: CheckButton
var _src_sliders: Dictionary = {}
var _src_pickers: Dictionary = {}
# вкладка «Купол»
var _dither_slider: HSlider
var _stars_slider: HSlider
var _tonemap_check: CheckBox	# Q7.34 (COLORS5): Filmic/Linear
# вкладка «Свет сцены»
var _key_col: ColorPickerButton
var _key_en: HSlider
var _moon_lcol: ColorPickerButton
var _moon_len: HSlider
var _ambient_slider: HSlider
# «Свет сцены» / новый свет (4.1.4, приказ 31.10 п.3 — ручки В КОНЦЕ вкладки):
# float/форма — данные AtmosphereLightingProfile → publish() → bindings (в пресет
# НЕ входят); 4.1.6: три цвета палитры — ЖИВЫЕ данные владельца (строка
# «Окружение») → состояние компонента И _collect_current (col_light3/2/1)
var _atmo_reset_btn: Button
var _atmo_mult: HSlider
var _atmo_anti_col: ColorPickerButton
var _atmo_trans_col: ColorPickerButton
var _atmo_solar_col: ColorPickerButton
var _atmo_anti_mu: HSlider
var _atmo_solar_mu: HSlider
var _atmo_trans_pos: HSlider
var _atmo_amb_str: HSlider
# вкладка «Вуаль» (Sky3.2.8, S11)
var _veil_on: CheckButton
var _veil_col: ColorPickerButton
var _veil_lighting: CheckBox
var _veil_shadow: CheckBox
var _veil_debug_spin: SpinBox
var _veil_sliders: Dictionary = {}	# uniform -> HSlider (синхронизация из материала)
# ветер (Sky3.2.11, раздел «Погода»): живые uniform'ы, в пресет НЕ входят
var _wind_on: CheckButton
var _wind_dir: HSlider
var _wind_speed: HSlider
var _wind_tl: HSlider
var _veil_reset_btn: Button	# Sky3.2.14: ЕДИНСТВЕННЫЙ сброс настроек вуали
# пресеты-референсы (Sky3.2.14, задача 1): именованный список для художественной работы
var _ref_name: LineEdit
var _ref_list: OptionButton
# вкладка «Пресеты»
var _preset_buttons: Array[TextureButton] = []
var _save_slot: OptionButton
var _current_slot := -1
# вкладка «Отладка»
var _debug_mode_spin: SpinBox
var _log: TextEdit


# ================= полоса рампы (п. 13.2/13.4) =================
class RampStrip extends Control:
	signal stop_dragged(idx: int, pct: float)
	var host: Node = null	# SkyControlPanel
	var _drag_idx := -1

	func _init() -> void:
		custom_minimum_size = Vector2(320.0, 40.0)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_drag_idx = _nearest_marker(ev.position.x)
			else:
				_drag_idx = -1
		elif ev is InputEventMouseMotion and _drag_idx >= 0:
			stop_dragged.emit(_drag_idx, clampf(ev.position.x / maxf(size.x, 1.0) * 100.0, 0.0, 100.0))

	func _nearest_marker(x: float) -> int:
		var pos: Array = host.strip_positions_pct()
		var g: float = host.strip_gamma()	# COLORS6: маркеры на эффективных границах
		var best := -1
		var bd := 9.0
		for i in range(pos.size()):
			var d := absf(pow(float(pos[i]) / 100.0, 1.0 / g) * size.x - x)
			if d < bd:
				bd = d
				best = i
		return best

	func _draw() -> void:
		var w := int(size.x)
		var h := int(size.y)
		if w < 2 or h < 2 or host == null:
			return
		var data: Dictionary = host.strip_data()
		var g: float = host.strip_gamma()	# COLORS6: варп «дыхания» (1.0 = выкл)
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		for px in range(w):
			# COLORS6: полоса рисует ФИЗИЧЕСКУЮ шкалу u, цвет = ramp(u^γ) — как в небе.
			var u := pow(float(px) / float(w - 1), g)
			# Q7.34 (COLORS5): стопы = display-данные (hex/255), mix в кодированном
			# пространстве — результат и есть байт полосы/неба, конверсий нет.
			var c: Color = SkyPresetValidator.ramp_color(data["stops"], data["w"], data["tw"], u)
			for py in range(h):
				img.set_pixel(px, py, Color(c.r, c.g, c.b))
		draw_texture(ImageTexture.create_from_image(img), Vector2.ZERO)
		var pos: Array = host.strip_positions_pct()
		for i in range(pos.size()):
			# COLORS6: маркеры — на ЭФФЕКТИВНЫХ границах долей (p^(1/γ)), там же, где в небе
			var x := pow(float(pos[i]) / 100.0, 1.0 / g) * size.x
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), Color(1.0, 1.0, 1.0, 0.85), 1.0)
			if host.is_locked(i):
				draw_rect(Rect2(x - 3.0, size.y - 8.0, 6.0, 6.0), Color(1.0, 0.8, 0.2))


func _ready() -> void:
	_build_ui()
	_panel.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_8:
			_toggle_panel()
			get_viewport().set_input_as_handled()


func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	if _is_open:
		_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_sync_ui()
	else:
		Input.mouse_mode = _previous_mouse_mode
	input_block_changed.emit(_is_open)


func _add_slider(parent: VBoxContainer, title: String, minimum: float, maximum: float,
		initial: float, step: float, callback: Callable) -> HSlider:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(callback)
	parent.add_child(slider)
	return slider


# ================= построение UI =================
## Q7.34 (S9, баг 3.3): каждая вкладка — ScrollContainer: при высоте окна < ~760 px
## низ вкладок был НЕДОСТУПЕН (скролла не было вообще). Горизонтальный скролл выключен,
## вертикальный — автоматический по высоте содержимого. Название вкладки = имя узла.
func _tab_box(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	return box


func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var panel_w := minf(380.0, vp.x - 32.0)
	var panel_h := minf(700.0, vp.y - 32.0)
	_panel = PanelContainer.new()
	_panel.position = Vector2(16.0, 16.0)
	_panel.size = Vector2(panel_w, panel_h)
	_panel.clip_contents = true
	add_child(_panel)

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(_tabs)

	_build_gradient_tab()
	_build_source_tab()
	_build_dome_tab()
	_build_light_tab()
	_build_veil_tab()
	_build_presets_tab()
	_build_debug_tab()
	_tabs.current_tab = 0


func _build_gradient_tab() -> void:
	var box := _tab_box("Градиент")

	_strip = RampStrip.new()
	_strip.host = self
	_strip.stop_dragged.connect(_on_strip_drag)
	box.add_child(_strip)

	var head := HBoxContainer.new()
	box.add_child(head)
	for i in range(4):
		var pick := ColorPickerButton.new()
		pick.custom_minimum_size = Vector2(44.0, 26.0)
		pick.color_changed.connect(_on_stop_color.bind(i))
		_stop_pickers.append(pick)
		head.add_child(pick)
	# 4.1.6 (запрос заказчика 31.10): независимый цвет ореола УДАЛЁН — цвет
	# выводится из солярного стопа sk_c4 (правило S3: linear(стоп) × gain).
	# Здесь живёт только ДАННОЕ яркости: HDR gain (×1.4 — правило S3 дословно).
	var halo_lbl := Label.new()
	halo_lbl.text = "ореол"
	halo_lbl.tooltip_text = "цвет ореола/стрика = linear(col_sky4) × gain — выводится из солярного стопа, отдельного цвета НЕТ (4.1.6, правило S3)"
	head.add_child(halo_lbl)
	_src_sliders["sk_halo_hdr_gain"] = _add_slider(box, "ореол/стрик: HDR gain от солярного стопа (правило S3)", 0.0, 4.0, 1.4, 0.01,
		func(v: float) -> void: _set_param("sk_halo_hdr_gain", v))

	# 4.1.7 (инструкция заказчика): ручки долей = 4 HSlider + 4 замка CheckButton;
	# вся логика (сумма = 100%, перераспределение пропорционально, замки) —
	# владелец SkyGradientWeightsComponent. Панель строит UI и подключает ручки
	# (attach_controls — рантайм-эквивалент назначения в Inspector: UI панели
	# собирается кодом); писатель sky_color_weights один — компонент.
	for i in range(4):
		var row := HBoxContainer.new()
		box.add_child(row)
		var lbl := Label.new()
		lbl.text = STOP_LABELS[i] + ", доля %"
		lbl.custom_minimum_size = Vector2(150.0, 0.0)
		row.add_child(lbl)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 100.0
		sl.value = 25.0	# step задаёт компонент (владелец инварианта «сумма = 100»)
		sl.custom_minimum_size = Vector2(140.0, 0.0)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.tooltip_text = "Доля цвета в градиенте, %: сумма всех четырёх = 100. При правке незакреплённые перераспределяются ПРОПОРЦИОНАЛЬНО своим текущим долям; закреплённые (замочек) стоят (компонент SkyGradientWeightsComponent, 4.1.7)"
		_grad_sliders.append(sl)
		row.add_child(sl)
		var lock := CheckButton.new()
		lock.text = "замок"
		lock.tooltip_text = "закрепить долю цвета (при перераспределении стоит; прямая правка собственного слайдера возможна — семантика компонента)"
		_grad_locks.append(lock)
		row.add_child(lock)
	var gw := _grad_weights()
	if gw != null:
		gw.attach_controls(_grad_sliders, _grad_locks)
		gw.weights_changed.connect(_on_weights_changed)

	var table := VBoxContainer.new()
	box.add_child(table)
	for i in range(4):
		var tl := Label.new()
		tl.text = "—"
		_table_labels.append(tl)
		table.add_child(tl)

	# 4.1.7: мягкость переходов — глобальный параметр сцены (не данные пресета);
	# рекомендация заказчика: начать с 0.025, затем пробовать 0.04–0.06.
	_src_sliders["sky_transition_width"] = _add_slider(box, "Мягкость переходов sky_transition_width (0.025 → пробовать 0.04–0.06)", 0.0, 0.2, 0.025, 0.001,
		func(v: float) -> void: _set_param("sky_transition_width", v))
	_arc_slider = _add_slider(box, "Эллипс sk_arc_stretch", 1.0, 4.0, 2.4, 0.05,
		func(v: float) -> void: _set_param("sk_arc_stretch", v))
	# Q7.34 (COLORS6, S15): «дыхание» купола — варп шкалы u от высоты солнца.
	_breathe_slider = _add_slider(box, "Дыхание купола sk_breathe (0 = выкл; солярные кольца дышат с высотой солнца)", 0.0, 0.9, 0.0, 0.01,
		func(v: float) -> void: _set_param("sk_breathe", v))
	# Q7.34 (COLORS7, S17): компенсация складки у горизонта — антисолярные окна шкалы
	# сжимаются в пригоризонтной зоне пропорционально стретчу эллипса (способ 1).
	_squeeze_slider = _add_slider(box, "Компенсация складки у горизонта sk_squeeze (0 = выкл; антисолярные окна сжимаются у горизонта пропорционально эллипсу)", 0.0, 2.0, 0.0, 0.01,
		func(v: float) -> void: _set_param("sk_squeeze", v))



func _build_source_tab() -> void:
	var box := _tab_box("Источник")
	_sun_az = _add_slider(box, "Солнце: азимут (°)", 0.0, 360.0, 180.0, 0.5, _on_sun_angles)
	_sun_el = _add_slider(box, "Солнце: надир −90° / зенит +90°", -90.0, 90.0, 0.5, 0.5, _on_sun_angles)
	_sun_on = CheckButton.new()
	_sun_on.text = "sun_enabled (солнце и прямое освещение)"
	_sun_on.button_pressed = true
	_sun_on.toggled.connect(func(on: bool) -> void:
		if controller: controller.set_sun_enabled(on))
	box.add_child(_sun_on)
	_moon_az = _add_slider(box, "Луна: азимут (°)", 0.0, 360.0, 0.0, 0.5, _on_moon_angles)
	_moon_el = _add_slider(box, "Луна: надир −90° / зенит +90°", -90.0, 90.0, 50.0, 0.5, _on_moon_angles)
	_moon_on = CheckButton.new()
	_moon_on.text = "moon_enabled (луна и лунный свет)"
	_moon_on.button_pressed = true
	_moon_on.toggled.connect(func(on: bool) -> void:
		if controller: controller.set_moon_enabled(on))
	box.add_child(_moon_on)

	var rows: Array = [
		["sun_size_deg", "Диск солнца: размер (°)", 0.5, 4.0, 1.8, 0.05],
		["sun_core_int", "Диск солнца: HDR-ядро", 0.0, 8.0, 5.0, 0.05],
		["sk_glow_int", "Ореол: интенсивность", 0.0, 1.0, 0.30, 0.01],
		["sk_glow_exp", "Ореол: угловой спад", 1.0, 12.0, 6.0, 0.1],
		["sun_g1_int", "Средний ореол g1", 0.0, 1.0, 0.35, 0.01],
		["sun_g2_int", "Широкое поле g2", 0.0, 1.0, 0.12, 0.01],
		["streak_int", "Стрик: интенсивность", 0.0, 1.0, 0.0, 0.01],
		["sk_streak_gate_lo", "Стрик: гейт низ (°)", 0.0, 180.0, 45.0, 1.0],
		["sk_streak_gate_hi", "Стрик: гейт верх (°)", 0.0, 180.0, 60.0, 1.0],
		["sk_streak_half_w_deg", "Стрик: полуширина бокса (°)", 1.0, 80.0, 45.0, 0.5],
		["sk_streak_half_h_deg", "Стрик: полувысота бокса (°)", 1.0, 80.0, 26.6, 0.5],
		["moon_size", "Луна: угловой радиус", 0.001, 0.1, 0.02, 0.001],
		["moon_detail_int", "Луна: кратеры", 0.0, 1.0, 0.5, 0.01],
		["moon_glow_int", "Луна: ореол", 0.0, 1.0, 0.0, 0.01],
		["moon_glow_exp", "Луна: спад ореола", 0.0, 80.0, 40.0, 1.0],
	]
	for r in rows:
		var sl := _add_slider(box, r[1], r[2], r[3], r[4], r[5],
			func(v: float, uni: String = r[0]) -> void: _set_param(uni, v))
		_src_sliders[r[0]] = sl
	for uni in ["sun_disk_color", "moon_color"]:
		var pick := ColorPickerButton.new()
		pick.custom_minimum_size = Vector2(80.0, 26.0)
		pick.tooltip_text = uni
		pick.color_changed.connect(func(c: Color, u: String = uni) -> void: _set_param(u, c))
		_src_pickers[uni] = pick
		box.add_child(pick)


func _build_dome_tab() -> void:
	var box := _tab_box("Купол")
	_dither_slider = _add_slider(box, "dither (0/1)", 0.0, 1.0, 1.0, 1.0,
		func(v: float) -> void: _set_param("sk_dither", v))
	_stars_slider = _add_slider(box, "Звёзды star_intensity", 0.0, 1.0, 0.0, 0.01,
		func(v: float) -> void: _set_param("star_intensity", v))
	# Q7.34 (COLORS5): переключатель тонмапа (заказчик: «сделай переключаемым
	# линер\филмик»). Пишет uniform sk_tonemap И Environment.tonemap_mode парой —
	# только так round-trip шейдера остаётся зеркалом движка.
	_tonemap_check = CheckBox.new()
	_tonemap_check.text = "Линейный тонмап (выкл = Filmic, цепь A)"
	_tonemap_check.tooltip_text = "Filmic: HDR-сжатие (солнце/ореолы мягче), tonemap_mode=2. Linear: сырой градиент, tonemap_mode=0. Байты палитры на стопах одинаковы в обоих режимах; сохраняется в пресет (tonemap_linear)."
	_tonemap_check.toggled.connect(_on_tonemap_toggled)
	box.add_child(_tonemap_check)


func _build_light_tab() -> void:
	var box := _tab_box("Свет сцены")
	_key_col = ColorPickerButton.new()
	_key_col.custom_minimum_size = Vector2(80.0, 26.0)
	_key_col.tooltip_text = "SunLight.color"
	_key_col.color_changed.connect(func(c: Color) -> void:
		var lc := _light_ctrl()
		if lc: lc.set_key_light_color(c))
	box.add_child(_key_col)
	_key_en = _add_slider(box, "SunLight.energy", 0.0, 8.0, 2.2, 0.01,
		func(v: float) -> void:
			var lc := _light_ctrl()
			if lc: lc.set_key_light_energy(v))
	_moon_lcol = ColorPickerButton.new()
	_moon_lcol.custom_minimum_size = Vector2(80.0, 26.0)
	_moon_lcol.tooltip_text = "MoonLight.color"
	_moon_lcol.color_changed.connect(func(c: Color) -> void:
		var lc := _light_ctrl()
		if lc: lc.set_moon_light_color(c))
	box.add_child(_moon_lcol)
	_moon_len = _add_slider(box, "MoonLight.energy", 0.0, 2.0, 0.12, 0.01,
		func(v: float) -> void:
			var lc := _light_ctrl()
			if lc: lc.set_moon_light_energy(v))
	_ambient_slider = _add_slider(box, "Environment.ambient_light_energy", 0.0, 4.0, 1.0, 0.01,
		func(v: float) -> void:
			var lc := _light_ctrl()
			if lc: lc.set_ambient_energy(v))
	_build_atmosphere_handles(box)


## 4.1.4 (приказ 31.10 п.3): ручки НОВОГО света — В КОНЦЕ вкладки «Свет сцены».
## Float/форма: поля AtmosphereLightingProfile (живой ресурс компонента); каждое
## изменение → publish() → bindings событийно обновляют материалы (свет пишет
## только binding — панель в материал НЕ пишет, ноль polling); в пресет не
## сохраняются. 4.1.6: три цвета палитры — ЖИВЫЕ данные владельца (строка
## «Окружение» palletes.html): ручки правят текущее трио через
## set_environment_palette() — единый источник для зон вуали И среды — и
## собираются в _collect_current как col_light3/2/1. Границы слайдеров зеркалят
## @export_range профиля (данные контракта, не выдумка UI).
const ATMO_FIELDS := ["direct_multiplier",
	"anti_solar_color", "transition_color", "solar_color",
	"anti_solar_mu", "solar_mu", "transition_position",
	"ambient_zenith_color", "ambient_horizon_color", "ambient_strength"]


func _build_atmosphere_handles(box: VBoxContainer) -> void:
	var hdr := Label.new()
	hdr.text = "— новый свет (атмосфера: профиль → publish → bindings) —"
	box.add_child(hdr)
	_atmo_reset_btn = Button.new()
	_atmo_reset_btn.text = "Сброс атмосферы (к данным .tres)"
	_atmo_reset_btn.tooltip_text = "4.1.4: поля профиля — из его же .tres с диска (источник данных один, констант в панели нет); выбор пресета профиль не трогает. 4.1.6: живую палитру сброс НЕ трогает (данные владельца) — она восстанавливается повторным выбором пресета"
	_atmo_reset_btn.pressed.connect(_atmo_reset)
	box.add_child(_atmo_reset_btn)
	_atmo_mult = _add_slider(box, "direct multiplier (интенсивность Sun × множитель)", 0.0, 5.0, 1.0, 0.01,
		func(v: float) -> void: _atmo_set_float("direct_multiplier", v))
	_atmo_mult.tooltip_text = "profile.direct_multiplier: множитель энергии Sun в состоянии освещения (v2 §3.1 Direct Lighting)"
	var pal_hdr := Label.new()
	pal_hdr.text = "палитра света (строка «Окружение»): зоны вуали И среда — единые данные (4.1.6)"
	pal_hdr.tooltip_text = "L3 «даль» = anti-solar зона + зенит среды; L2 «середина» = переходная зона; L1 «у солнца» = solar зона + горизонт среды. Значения — из активного пресета (col_light3/2/1); правки живые и уходят в сохраняемый пресет. Тинты, не источники (v2 §5.2)"
	box.add_child(pal_hdr)
	var anti_lbl := Label.new()
	anti_lbl.text = "anti-solar tint (противосолнечная зона)"
	box.add_child(anti_lbl)
	_atmo_anti_col = ColorPickerButton.new()
	_atmo_anti_col.custom_minimum_size = Vector2(80.0, 26.0)
	_atmo_anti_col.tooltip_text = "L3 «даль» (col_light3) → hc_palette_anti_solar И hc_ambient_zenith — единые данные (4.1.6)"
	_atmo_anti_col.color_changed.connect(func(c: Color) -> void: _atmo_set_env_color("anti_solar", c))
	box.add_child(_atmo_anti_col)
	_atmo_anti_mu = _add_slider(box, "anti_solar_mu (граница зоны, cos угла)", -1.0, 1.0, -0.35, 0.01,
		func(v: float) -> void: _atmo_set_float("anti_solar_mu", v))
	var trans_lbl := Label.new()
	trans_lbl.text = "transition tint (переходная зона)"
	box.add_child(trans_lbl)
	_atmo_trans_col = ColorPickerButton.new()
	_atmo_trans_col.custom_minimum_size = Vector2(80.0, 26.0)
	_atmo_trans_col.tooltip_text = "L2 «середина» (col_light2) → hc_palette_transition (4.1.6)"
	_atmo_trans_col.color_changed.connect(func(c: Color) -> void: _atmo_set_env_color("transition", c))
	box.add_child(_atmo_trans_col)
	var solar_lbl := Label.new()
	solar_lbl.text = "solar tint (солнечная зона)"
	box.add_child(solar_lbl)
	_atmo_solar_col = ColorPickerButton.new()
	_atmo_solar_col.custom_minimum_size = Vector2(80.0, 26.0)
	_atmo_solar_col.tooltip_text = "L1 «у солнца» (col_light1) → hc_palette_solar И hc_ambient_horizon — единые данные (4.1.6)"
	_atmo_solar_col.color_changed.connect(func(c: Color) -> void: _atmo_set_env_color("solar", c))
	box.add_child(_atmo_solar_col)
	_atmo_solar_mu = _add_slider(box, "solar_mu (граница зоны, cos угла)", -1.0, 1.0, 0.75, 0.01,
		func(v: float) -> void: _atmo_set_float("solar_mu", v))
	_atmo_trans_pos = _add_slider(box, "transition_position (середина перехода, 0.05..0.95)", 0.05, 0.95, 0.5, 0.01,
		func(v: float) -> void: _atmo_set_float("transition_position", v))
	var amb_hdr := Label.new()
	amb_hdr.text = "среда — сила (цвета среды = палитра выше: зенит = L3, горизонт = L1)"
	amb_hdr.tooltip_text = "4.1.6: мёртвые fallback-пикеры ambient удалены — живые цвета среды поставляет палитра владельца (единые данные, v2 §2.1/§5.2); из профиля остаётся только СИЛА среды"
	box.add_child(amb_hdr)
	_atmo_amb_str = _add_slider(box, "ambient strength (сила окружающей среды)", 0.0, 2.0, 1.0, 0.01,
		func(v: float) -> void: _atmo_set_float("ambient_strength", v))
	_sync_atmo()


## Синхронизация ручек (без обратных сигналов): float/форма — из профиля,
## три цвета палитры — из ЖИВОГО состояния владельца (4.1.6: смена пресета
## visibly меняет палитру ручек — дефект «замороженных тинтов» устранён).
func _sync_atmo() -> void:
	var p := _atmo_profile()
	if p == null:
		return
	_atmo_mult.set_value_no_signal(p.direct_multiplier)
	var a := _atmosphere()
	var st: AtmosphereLightingState = a.get_current_state() if a != null else null
	if st != null:
		_atmo_anti_col.color = st.anti_solar_color
		_atmo_trans_col.color = st.transition_color
		_atmo_solar_col.color = st.solar_color
	_atmo_anti_mu.set_value_no_signal(p.anti_solar_mu)
	_atmo_solar_mu.set_value_no_signal(p.solar_mu)
	_atmo_trans_pos.set_value_no_signal(p.transition_position)
	_atmo_amb_str.set_value_no_signal(p.ambient_strength)


func _atmosphere() -> AtmosphereLightingComponent:
	if controller:
		return controller.atmosphere
	return null


func _atmo_profile() -> AtmosphereLightingProfile:
	var a := _atmosphere()
	if a == null:
		return null
	return a.profile


## Единственный вход ручек вкладки: поле профиля (данные) → publish() (событие).
func _atmo_set_float(field: String, v: float) -> void:
	var p := _atmo_profile()
	if p == null:
		return
	p.set(field, v)
	_atmosphere().publish()


## Ручка палитры (4.1.6): заменить ОДНУ зону в текущем трио владельца и
## опубликовать всё трио — единый источник для зон вуали И среды. Текущие
## значения читаются из состояния (не из пикеров): обратных сигналов нет.
func _atmo_set_env_color(zone: String, c: Color) -> void:
	var a := _atmosphere()
	if a == null:
		return
	var st: AtmosphereLightingState = a.get_current_state()
	var anti: Color = c if zone == "anti_solar" else st.anti_solar_color
	var trans: Color = c if zone == "transition" else st.transition_color
	var solar: Color = c if zone == "solar" else st.solar_color
	a.set_environment_palette(anti, trans, solar)


## Сброс: поля профиля из его же .tres с диска (CACHE_MODE_IGNORE — свежий
## экземпляр, живой ресурс не подменяется). Источник данных один — файл.
func _atmo_reset() -> void:
	var p := _atmo_profile()
	if p == null or p.resource_path.is_empty():
		return
	var fresh: AtmosphereLightingProfile = ResourceLoader.load(
		p.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if fresh == null:
		return
	for f: String in ATMO_FIELDS:
		p.set(f, fresh.get(f))
	_atmosphere().publish()
	_sync_atmo()
	if _log != null:
		_log.text = "атмосфера: сброс профиля к данным %s (%d полей)" % [p.resource_path, ATMO_FIELDS.size()]


## Вкладка «Вуаль» (Sky3.2.8, S11): живые ручки компонента SkyVeil. Пишем только
## через контроллер (_set_param → set_shader_param, писатель один); 8 полей пресета
## читаются обратно из uniform'ов в _collect_current. Формовые ручки (scale/stretch/
## curtain/debug) в пресет НЕ входят по плану §4 — только живые данные материала.
func _build_veil_tab() -> void:
	var box := _tab_box("Погода")	# Sky3.2.11: переименована по приказу заказчика (вуаль + ветер)
	_veil_on = CheckButton.new()
	_veil_on.text = "Вуаль включена (hc_enabled)"
	_veil_on.tooltip_text = "Гейт S10: выкл = ноль выборок текстуры, кадр побитово равен небу без вуали. Поле пресета veil_enabled."
	_veil_on.toggled.connect(func(on: bool) -> void: _set_param("hc_enabled", on))
	box.add_child(_veil_on)
	_veil_reset_btn = Button.new()
	_veil_reset_btn.text = "Сброс вуали (к дефолтам компонента)"
	_veil_reset_btn.tooltip_text = "Sky3.2.14: единственная кнопка сброса живых настроек вуали/ветра; выбор пресета вуаль НЕ трогает"
	_veil_reset_btn.pressed.connect(_veil_reset)
	box.add_child(_veil_reset_btn)
	_veil_sliders["DS_hc_alpha_scale"] = _add_slider(box, "amount (общая сила) → DS_hc_alpha_scale", 0.0, 1.0, 1.0, 0.01,
		func(v: float) -> void: _set_param("DS_hc_alpha_scale", v))
	_veil_sliders["hc_coverage"] = _add_slider(box, "coverage (заполнение плиты)", 0.0, 1.0, 0.52, 0.01,
		func(v: float) -> void: _set_param("hc_coverage", v))
	_veil_sliders["hc_tau_per_km"] = _add_slider(box, "tau на км (непрозрачность)", 0.0, 2.0, 0.30, 0.01,
		func(v: float) -> void: _set_param("hc_tau_per_km", v))
	_veil_sliders["hc_scale"] = _add_slider(box, "scale (размер характера, м)", 10000.0, 200000.0, 60000.0, 500.0,
		func(v: float) -> void: _set_param("hc_scale", v))
	_veil_sliders["hc_stretch"] = _add_slider(box, "stretch (вытянутость гряд)", 1.0, 8.0, 3.2, 0.05,
		func(v: float) -> void: _set_param("hc_stretch", v))
	_veil_sliders["hc_stretch_angle_deg"] = _add_slider(box, "азимут stretch, °", 0.0, 90.0, 25.0, 0.5,
		func(v: float) -> void: _set_param("hc_stretch_angle_deg", v))
	_veil_sliders["hc_curtain_start"] = _add_slider(box, "curtain start, м (path в плите; 18000 ≈ 95 км дальности)", 0.0, 40000.0, 18000.0, 100.0,
		func(v: float) -> void: _set_param("hc_curtain_start", v))
	_veil_sliders["hc_curtain_end"] = _add_slider(box, "curtain end, м (path; 55000 ≈ истинный горизонт)", 0.0, 120000.0, 55000.0, 100.0,
		func(v: float) -> void: _set_param("hc_curtain_end", v))
	# --- форма Sky3.2.12 (п.1-5): разрывы, волокна, кромки — живые данные ---
	_veil_sliders["hc_softness"] = _add_slider(box, "softness (мягкость кромок)", 0.05, 0.8, 0.30, 0.01,
		func(v: float) -> void: _set_param("hc_softness", v))
	_veil_sliders["hc_detail_strength"] = _add_slider(box, "detail (размыв кромки Worley)", 0.0, 1.0, 0.45, 0.01,
		func(v: float) -> void: _set_param("hc_detail_strength", v))
	_veil_sliders["hc_break_amount"] = _add_slider(box, "break (крупные разрывы покрытия)", 0.0, 1.0, 0.40, 0.01,
		func(v: float) -> void: _set_param("hc_break_amount", v))
	_veil_sliders["hc_break_scale"] = _add_slider(box, "break scale, м (масштаб разрывов)", 50000.0, 400000.0, 120000.0, 1000.0,
		func(v: float) -> void: _set_param("hc_break_scale", v))
	_veil_sliders["hc_fiber_amp"] = _add_slider(box, "fiber amp, м (варп волокон, ломает полосы)", 0.0, 20000.0, 8000.0, 100.0,
		func(v: float) -> void: _set_param("hc_fiber_amp", v))
	_veil_sliders["hc_fiber_scale"] = _add_slider(box, "fiber scale, м (второй масштаб волокон)", 5000.0, 60000.0, 18000.0, 500.0,
		func(v: float) -> void: _set_param("hc_fiber_scale", v))
	var col_lbl := Label.new()
	col_lbl.text = "veil_color (плоский тон при выкл. освещении)"
	box.add_child(col_lbl)
	_veil_col = ColorPickerButton.new()
	_veil_col.custom_minimum_size = Vector2(80.0, 26.0)
	_veil_col.tooltip_text = "hc_color; поле пресета veil_color"
	_veil_col.color_changed.connect(func(c: Color) -> void: _set_param("hc_color", c))
	box.add_child(_veil_col)
	_veil_sliders["hc_light_gain"] = _add_slider(box, "light gain (прямой свет)", 0.0, 4.0, 1.0, 0.01,
		func(v: float) -> void: _set_param("hc_light_gain", v))
	_veil_sliders["hc_ambient_gain"] = _add_slider(box, "ambient gain (небо)", 0.0, 4.0, 1.0, 0.01,
		func(v: float) -> void: _set_param("hc_ambient_gain", v))
	_veil_lighting = CheckBox.new()
	_veil_lighting.text = "Освещение вуали (hc_use_lighting)"
	_veil_lighting.tooltip_text = "вкл = цвет из угловой палитры света (Anti-Solar→Transition→Solar по mu, этап 04) и gains; выкл = плоский hc_color"
	_veil_lighting.toggled.connect(func(on: bool) -> void: _set_param("hc_use_lighting", on))
	box.add_child(_veil_lighting)
	_veil_shadow = CheckBox.new()
	_veil_shadow.text = "Самозатенение (hc_use_shadowing)"
	_veil_shadow.tooltip_text = "DS-самозатенение с клампом по границе плиты; поле пресета veil_use_shadowing"
	_veil_shadow.toggled.connect(func(on: bool) -> void: _set_param("hc_use_shadowing", on))
	box.add_child(_veil_shadow)
	var dbg_row := HBoxContainer.new()
	box.add_child(dbg_row)
	var dbg_lbl := Label.new()
	dbg_lbl.text = "hc_debug (0 выкл / 1 альфа / 2 плотность / 3 толщина)"
	dbg_row.add_child(dbg_lbl)
	_veil_debug_spin = SpinBox.new()
	_veil_debug_spin.min_value = 0
	_veil_debug_spin.max_value = 3
	_veil_debug_spin.value_changed.connect(func(v: float) -> void: _set_param("hc_debug", int(v)))
	dbg_row.add_child(_veil_debug_spin)
	# --- ветер (Sky3.2.11): адвекция характера вуали на GPU (TIME), ноль записей с CPU ---
	var wind_hdr := Label.new()
	wind_hdr.text = "— ветер (адвекция характера, GPU) —"
	box.add_child(wind_hdr)
	_wind_on = CheckButton.new()
	_wind_on.text = "Ветер включён (hc_wind_enabled)"
	_wind_on.tooltip_text = "выкл = характер неподвижен и детерминирован (приёмка «побитово»); вкл = дрейф по TIME в шейдере"
	_wind_on.toggled.connect(func(on: bool) -> void: _set_param("hc_wind_enabled", on))
	box.add_child(_wind_on)
	_wind_dir = _add_slider(box, "направление ветра (куда несёт), °", 0.0, 360.0, 0.0, 1.0,
		func(v: float) -> void: _set_param("hc_wind_dir_deg", v))
	_wind_speed = _add_slider(box, "сила ветра, м/с (высотный поток)", 0.0, 60.0, 15.0, 0.5,
		func(v: float) -> void: _set_param("hc_wind_speed", v))
	_wind_tl = _add_slider(box, "таймлапс дрейфа ×N (1 = реальное время)", 1.0, 200.0, 60.0, 1.0,
		func(v: float) -> void: _set_param("hc_wind_timelapse", v))


func _build_presets_tab() -> void:
	var box := _tab_box("Пресеты")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for i in range(presets.size()):
		var pr: SkyPreset = presets[i]
		if pr == null:
			continue
		var btn := TextureButton.new()
		btn.ignore_texture_size = true
		btn.custom_minimum_size = Vector2(80.0, 48.0)
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
		btn.texture_normal = pr.preview
		btn.tooltip_text = pr.preset_name
		btn.pressed.connect(_on_preset_pressed.bind(i))
		_preset_buttons.append(btn)
		grid.add_child(btn)

	var save_row := HBoxContainer.new()
	box.add_child(save_row)
	_save_slot = OptionButton.new()
	for i in range(1, 11):
		_save_slot.add_item("Слот %02d" % i, i)
	_save_slot.add_item("Новый (след. номер)", 99)
	save_row.add_child(_save_slot)
	var save_btn := Button.new()
	save_btn.text = "Сохранить в… (с миниатюрой)"
	save_btn.pressed.connect(func() -> void: _save_current(true))
	save_row.add_child(save_btn)
	var copy_btn := Button.new()
	copy_btn.text = "Скопировать текущий (без миниатюры)"
	copy_btn.pressed.connect(func() -> void: _save_current(false))
	save_row.add_child(copy_btn)
	var load_btn := Button.new()
	load_btn.text = "Загрузить выбранный слот с диска"
	load_btn.pressed.connect(_reload_slot)
	box.add_child(load_btn)
	# --- пресеты-референсы (Sky3.2.14, задача 1): именованный список, save/load ---
	var ref_hdr := Label.new()
	ref_hdr.text = "— пресеты-референсы (именованный список) —"
	box.add_child(ref_hdr)
	var ref_row1 := HBoxContainer.new()
	box.add_child(ref_row1)
	_ref_name = LineEdit.new()
	_ref_name.placeholder_text = "имя референса"
	_ref_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ref_row1.add_child(_ref_name)
	var ref_save := Button.new()
	ref_save.text = "Сохранить в список"
	ref_save.pressed.connect(_save_ref)
	ref_row1.add_child(ref_save)
	var ref_row2 := HBoxContainer.new()
	box.add_child(ref_row2)
	_ref_list = OptionButton.new()
	_ref_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ref_row2.add_child(_ref_list)
	var ref_load := Button.new()
	ref_load.text = "Выбрать из списка"
	ref_load.pressed.connect(_load_ref)
	ref_row2.add_child(ref_load)
	_refresh_refs()


func _build_debug_tab() -> void:
	var box := _tab_box("Отладка")
	var row := HBoxContainer.new()
	box.add_child(row)
	var lbl := Label.new()
	lbl.text = "sky_debug_mode (0 небо / 1 карта u / 2 сегменты / 3–6 чистые стопы sk_c4..sk_c1 — диагностика цепи, 4.1.8 временно)"
	row.add_child(lbl)
	_debug_mode_spin = SpinBox.new()
	_debug_mode_spin.min_value = 0
	_debug_mode_spin.max_value = 6
	_debug_mode_spin.value_changed.connect(func(v: float) -> void: _set_param("sky_debug_mode", int(v)))
	row.add_child(_debug_mode_spin)
	var check_btn := Button.new()
	check_btn.text = "Прогнать валидатор по текущим данным"
	check_btn.pressed.connect(_run_validator)
	box.add_child(check_btn)
	var set_btn := Button.new()
	set_btn.text = "Проверить набор пресетов"
	set_btn.pressed.connect(_run_set_check)
	box.add_child(set_btn)
	_log = TextEdit.new()
	_log.editable = false
	_log.custom_minimum_size = Vector2(0.0, 220.0)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_log)


# ================= данные полосы и маркеры =================
## 4.1.7: доли владельца (нормированные 0..1) — из слайдеров компонента;
## fallback — параметр материала (панель без подключённого владельца).
func strip_weights() -> Array:
	var gw := _grad_weights()
	if gw != null and gw.sliders.size() == 4:
		var tot := 0.0
		for i in range(4):
			tot += gw.sliders[i].value
		tot = maxf(tot, 0.0001)
		var out: Array = []
		for i in range(4):
			out.append(gw.sliders[i].value / tot)
		return out
	var wv_v: Variant = _get_param("sky_color_weights")
	var wv := Vector4(0.25, 0.25, 0.25, 0.25) if wv_v == null else Vector4(wv_v)
	var tot2 := maxf(wv.x + wv.y + wv.z + wv.w, 0.0001)
	return [wv.x / tot2, wv.y / tot2, wv.z / tot2, wv.w / tot2]


## Маркеры полосы — ТРИ кумулятивные границы долей b1/b2/b3 (%) (4.1.7).
func strip_positions_pct() -> Array:
	var w := strip_weights()
	var out: Array = []
	var acc := 0.0
	for i in range(3):
		acc += float(w[i]) * 100.0
		out.append(acc)
	return out


func strip_data() -> Dictionary:
	var stops: Array = []
	for uni in COL_UNIS:
		stops.append(Color(_get_param(uni)))
	var tw_v: Variant = _get_param("sky_transition_width")
	var tw: float = SkyPresetValidator.TW_DEFAULT if tw_v == null else float(tw_v)
	return {"stops": stops, "w": strip_weights(), "tw": tw}


func is_locked(i: int) -> bool:
	var gw := _grad_weights()
	return gw != null and gw.locks.size() == 4 and gw.locks[i].button_pressed


func _refresh_strip() -> void:
	if _strip:
		_strip.queue_redraw()
	_refresh_table()


## Компонент опубликовал доли (слайдер/замок/пресет) → полоса и таблица.
func _on_weights_changed(_w: Vector4) -> void:
	_refresh_strip()


func _refresh_table() -> void:
	var data := strip_data()
	var w: Array = data["w"]
	var stops: Array = data["stops"]
	var tw: float = float(data["tw"])
	var g := strip_gamma()
	var b := 0.0
	for i in range(4):
		var b_prev := b
		b += float(w[i])
		var txt := "%s: доля %.1f%%  зона u∈[%.3f..%.3f]%s" % [STOP_LABELS[i], float(w[i]) * 100.0, b_prev, b, "  🔒" if is_locked(i) else ""]
		if i < 3:
			# ширина перехода на границе — та же формула, что в get_sky_gradient
			var fi := maxf(0.0005, minf(tw, 0.45 * minf(float(w[i]), float(w[i + 1]))))
			txt += "  переход ±%.1f°" % (fi * 180.0)
			if not is_equal_approx(g, 1.0):
				txt += "  эфф.u=%.3f" % pow(b, 1.0 / g)	# COLORS6: где граница реально на куполе
		_table_labels[i].text = txt
		var bad := false
		if i < 3:
			var a: Color = stops[i]
			var c2: Color = stops[i + 1]
			if (a.r == c2.r and a.g == c2.g and a.b == c2.b) or float(w[i]) * 100.0 < 1.0:
				bad = true
		_table_labels[i].add_theme_color_override("font_color", Color(1.0, 0.25, 0.25) if bad else Color(0.85, 0.85, 0.85))


# ============ доли (4.1.7, инструкция заказчика) ============
# Логика долей (сумма = 100%, перераспределение ПРОПОРЦИОНАЛЬНО текущим долям
# незакреплённых, замки) живёт во владельце SkyGradientWeightsComponent — его
# код дословно из инструкции заказчика. Панель только маршрутизирует ввод:
# тяга маркера полосы = правка доли цвета, чья ПРАВАЯ граница — этот маркер
# (запись в слайдер владельца запускает его перераспределение и публикацию).
func _grad_weights() -> SkyGradientWeightsComponent:
	if controller != null:
		return controller.gradient_weights
	return null


## Тяга маркера на полосе (граница b_{idx+1}) = правка доли цвета idx.
func _on_strip_drag(idx: int, q: float) -> void:
	var gw := _grad_weights()
	if gw == null or idx < 0 or idx > 2 or gw.sliders.size() != 4:
		return
	# COLORS6: полоса тянет ФИЗИЧЕСКИЙ процент; доли живут в базовой шкале —
	# обратный варп q^γ (γ из sk_breathe и высоты солнца; γ=1 когда выкл).
	q = pow(clampf(q / 100.0, 0.0, 1.0), strip_gamma()) * 100.0
	# Новая доля = граница минус сумма предыдущих долей (остальные перераспределит
	# владелец; закреплённые стоят; активный слайдер правится даже под своим замком).
	var prev_sum := 0.0
	for i in range(idx):
		prev_sum += gw.sliders[i].value
	gw.sliders[idx].value = clampf(q - prev_sum, 0.0, 100.0)


# ================= записи через контроллеры =================
func _set_param(uni: String, value: Variant) -> void:
	if controller:
		controller.set_shader_param(uni, value)
	if uni in COL_UNIS or uni == "sky_transition_width" or uni == "sk_tonemap" or uni == "sk_breathe" or uni == "sk_squeeze" or uni == "sk_arc_stretch":
		_refresh_strip()


func _get_param(uni: String) -> Variant:
	if controller:
		return controller.get_shader_param(uni)
	return 0.0


## Sky3.2.9 (hotfix 3.2.8): ShaderMaterial.get_shader_parameter() возвращает NULL
## для uniform'ов, которые материалу никогда не записывались (дефолты шейдера он не
## хранит; в SkyEnvironmentMaterial.tres новых hc_* нет — файл старше вуали).
## float(null)/bool(null)/Color(null) в Godot 4 = «Nonexistent constructor» —
## _sync_ui падал при открытии панели (строка ~1038). Читаем вуаль с фолбэком на
## дефолты компонента SkyVeil.gdshaderinc (данные продублированы намеренно:
## get_shader_uniform_list() дефолты не отдаёт — ловушка 4.7).
const VEIL_DEFAULTS := {
	"hc_enabled": false,
	"DS_hc_alpha_scale": 1.0,
	"hc_color": Color(0.92, 0.93, 0.96),
	"hc_light_gain": 1.0,
	"hc_ambient_gain": 1.0,
	"hc_coverage": 0.52,
	"hc_tau_per_km": 0.30,
	"hc_use_shadowing": false,
	"hc_use_lighting": false,
	"hc_scale": 60000.0,
	"hc_stretch": 3.2,
	"hc_stretch_angle_deg": 25.0,
	"hc_curtain_start": 18000.0,	# Sky3.2.10: дальность 90+ км
	"hc_curtain_end": 55000.0,	# Sky3.2.10
	"hc_debug": 0.0,
	"hc_wind_enabled": false,
	"hc_wind_speed": 15.0,
	"hc_wind_dir_deg": 0.0,
	"hc_wind_timelapse": 60.0,
	"hc_softness": 0.30,
	"hc_detail_strength": 0.45,
	"hc_break_amount": 0.40,
	"hc_break_scale": 120000.0,
	"hc_fiber_amp": 8000.0,
	"hc_fiber_scale": 18000.0,
}

func _veil_get(uni: String) -> Variant:
	var v: Variant = _get_param(uni)
	return VEIL_DEFAULTS[uni] if v == null else v


## fix.4.1.7 (краш заказчика: SkyControlPanel.gd:1261 _sync_ui «Nonexistent
## 'float' constructor»): ТА ЖЕ ловушка, что описана в 3.2.9 выше —
## SkyEnvironmentMaterial.tres старше uniform'ов 4.1.7, и
## get_shader_parameter("sky_transition_width") возвращает NULL (дефолты
## шейдера материал не хранит); float(null) в Godot 4 = «Nonexistent
## constructor» → панель падала в момент открытия (_toggle_panel → _sync_ui).
## Фолбэк на дефолты uniform'ов шейдера (данные продублированы намеренно —
## зеркала дефолтов; get_shader_uniform_list() дефолты не отдаёт, ловушка 4.7).
const SRC_DEFAULTS := {
	"sky_transition_width": 0.025,	# зеркало uniform sky_transition_width = 0.025
	"sk_halo_hdr_gain": 1.4,	# зеркало uniform sk_halo_hdr_gain = 1.4 (защита старых материалов)
}


## Float-параметр материала с фолбэком на дефолт шейдера (NULL-безопасно).
func _src_get(uni: String) -> float:
	var v: Variant = _get_param(uni)
	return float(v) if v != null else float(SRC_DEFAULTS.get(uni, 0.0))


func _light_ctrl() -> SkyLightController:
	if controller:
		return controller.light_controller
	return null


## Q7.34 (COLORS6 v2): текущая γ варпа шкалы — ТА ЖЕ формула, что в ramp_u шейдера
## (γ = (1+x)/(1−0.5x), x = sk_breathe·sin(elev); v1-закон, усиленный ×1.5 по сдвигу
## границ): полоса и маркеры WYSIWYG с куполом.
func breathe_gamma() -> float:
	if controller == null:
		return 1.0
	var x := float(_get_param("sk_breathe")) * sin(deg_to_rad(controller.sun_elevation))
	return (1.0 + x) / (1.0 - 0.5 * x)


## Q7.34 (COLORS7): экспонента компенсации складки для ГОРИЗОНТНОГО среза полосы
## (h = 1): γ_arc = 1 + sk_squeeze·(S−1), где S — ТА ЖЕ формула стретча, что в
## u_ellip/ramp_u шейдера (smoothstep-уход к зениту солнца включён).
func squeeze_gamma() -> float:
	if controller == null:
		return 1.0
	var s := absf(sin(deg_to_rad(controller.sun_elevation)))
	var S := lerpf(maxf(float(_get_param("sk_arc_stretch")), 1.0), 1.0, smoothstep(0.85, 0.99, s))	# GDScript 4.3+: lerpf (float), не Variant-lerp и не шейдерный mix
	return 1.0 + float(_get_param("sk_squeeze")) * (S - 1.0)


## Q7.34 (COLORS7): итоговая экспонента варпа горизонтного среза полосы:
## дыхание (COLORS6 v2) × компенсация складки (COLORS7). Полоса/маркеры/drag/таблица.
func strip_gamma() -> float:
	return breathe_gamma() * squeeze_gamma()


func _on_stop_color(c: Color, idx: int) -> void:
	_set_param(COL_UNIS[idx], c)


## Q7.34 (COLORS5): переключатель Filmic/Linear — uniform + Environment парой.
func _on_tonemap_toggled(on: bool) -> void:
	if _syncing:
		return
	_set_param("sk_tonemap", 1 if on else 0)
	var lc := _light_ctrl()
	if lc != null:
		lc.set_tonemap_linear(on)
	_refresh_strip()


func _on_sun_angles(_v: float) -> void:
	if controller:
		controller.set_sun_angles(_sun_az.value, _sun_el.value)
	_refresh_strip()	# COLORS6: γ «дыхания» зависит от высоты солнца — полоса маркеров едет с ним


func _on_moon_angles(_v: float) -> void:
	if controller:
		controller.set_moon_angles(_moon_az.value, _moon_el.value)


# ================= пресеты =================
func _on_preset_pressed(index: int) -> void:
	if controller == null or index >= presets.size():
		return
	controller.apply_preset(presets[index])
	_current_slot = index
	_sync_ui()


func _reload_slot() -> void:
	var id := _save_slot.get_selected_id()
	if id == 99:
		return
	var path := presets_dir + ("Preset_%02d.tres" % id)
	if not ResourceLoader.exists(path):
		return
	var pr := load(path) as SkyPreset
	if pr and controller:
		controller.apply_preset(pr)
		_sync_ui()


func _collect_current() -> SkyPreset:
	var p := SkyPreset.new()
	p.preset_name = "слот из панели %s" % Time.get_datetime_string_from_system()
	for i in range(4):
		p.set(COL_FIELDS[i], Color(_get_param(COL_UNIS[i])))
	# Окружение (4.1.6): col_light3/2/1 — ЖИВАЯ палитра света из состояния
	# владельца: правки ручек «Свет сцены» уходят в данные пресета (прежняя
	# тихая потеря значения устранена). Fallback (нет компонента) — дефолты
	# класса SkyPreset. Ореола в пресете НЕТ: цвет выводится из col_sky4
	# (правило S3); sk_halo_hdr_gain — глобальный параметр сцены.
	var atmo := _atmosphere()
	if atmo != null:
		var st: AtmosphereLightingState = atmo.get_current_state()
		if st != null:
			p.col_light3 = st.anti_solar_color
			p.col_light2 = st.transition_color
			p.col_light1 = st.solar_color
	# 4.1.7: живые доли владельца → кумулятивные границы q1..q3; q4 = 1.0
	# (в модели долей хвост всегда дотянут до антисоляра). Поле sharp удалено
	# вместе с окнами win — мягкость теперь глобальный sky_transition_width.
	var wts := strip_weights()
	p.q1 = float(wts[0])
	p.q2 = float(wts[0]) + float(wts[1])
	p.q3 = float(wts[0]) + float(wts[1]) + float(wts[2])
	p.q4 = 1.0
	p.arc_stretch = float(_get_param("sk_arc_stretch"))
	p.breathe = float(_get_param("sk_breathe"))	# COLORS6
	p.squeeze = float(_get_param("sk_squeeze"))	# COLORS7
	p.dither = float(_get_param("sk_dither")) > 0.5
	p.star_intensity = float(_get_param("star_intensity"))
	p.tonemap_linear = int(_get_param("sk_tonemap")) == 1	# Q7.34 (COLORS5)
	p.sun_disc_color = Color(_get_param("sun_disk_color"))
	p.sun_size_deg = float(_get_param("sun_size_deg"))
	p.sun_core_int = float(_get_param("sun_core_int"))
	p.glow_int = float(_get_param("sk_glow_int"))
	p.glow_exp = float(_get_param("sk_glow_exp"))
	p.g1_int = float(_get_param("sun_g1_int"))
	p.g2_int = float(_get_param("sun_g2_int"))
	p.streak_int = float(_get_param("streak_int"))
	p.streak_gate_lo = float(_get_param("sk_streak_gate_lo"))
	p.streak_gate_hi = float(_get_param("sk_streak_gate_hi"))
	p.streak_half_w_deg = float(_get_param("sk_streak_half_w_deg"))
	p.streak_half_h_deg = float(_get_param("sk_streak_half_h_deg"))
	p.moon_color = Color(_get_param("moon_color"))
	p.moon_size = float(_get_param("moon_size"))
	p.moon_detail_int = float(_get_param("moon_detail_int"))
	p.moon_glow_int = float(_get_param("moon_glow_int"))
	p.moon_glow_exp = float(_get_param("moon_glow_exp"))
	if controller:
		p.sun_azimuth = controller.sun_azimuth
		p.sun_elevation = controller.sun_elevation
		p.moon_azimuth = controller.moon_azimuth
		p.moon_elevation = controller.moon_elevation
		p.sun_enabled = controller.sun_enabled
		p.moon_enabled = controller.moon_enabled
	# 4.1.1: свет сцены в пресет НЕ сохраняется (поле light и SkyLightProfile
	# удалены — граница 30.10 п.4). Вкладка «Свет сцены» СОХРАНЕНА (приказ
	# 31.10 п.3) как живые ручки узлов SunLight/MoonLight/Environment;
	# 4.1.4: ручки нового контракта (AtmosphereLightingProfile) добавлены
	# В КОНЕЦ вкладки — данные профиля, событийное обновление publish();
	# в пресет тоже НЕ сохраняются (профиль — отдельный ресурс).
	# вуаль (Sky3.2.8, S11): 8 полей профиля читаются обратно из материала —
	# состояние вкладки «Вуаль» сохраняется кругом вместе с пресетом
	var vp := SkyVeilProfile.new()
	vp.veil_enabled = bool(_veil_get("hc_enabled"))
	vp.veil_amount = float(_veil_get("DS_hc_alpha_scale"))
	vp.veil_color = Color(_veil_get("hc_color"))
	vp.veil_light_gain = float(_veil_get("hc_light_gain"))
	vp.veil_ambient_gain = float(_veil_get("hc_ambient_gain"))
	vp.veil_coverage = float(_veil_get("hc_coverage"))
	vp.veil_tau_per_km = float(_veil_get("hc_tau_per_km"))
	vp.veil_use_shadowing = bool(_veil_get("hc_use_shadowing"))
	p.veil = vp
	return p


func _save_current(with_thumb: bool) -> void:
	var p := _collect_current()
	var res: Dictionary = SkyPresetValidator.validate(p)
	var lines: Array[String] = []
	for w in res["warnings"]:
		lines.append("ПРЕДУПРЕЖДЕНИЕ: " + w)
	for e in res["errors"]:
		lines.append("ОШИБКА: " + e)
	if not res["errors"].is_empty():
		lines.append("сохранение заблокировано валидатором")
		_log.text = "\n".join(lines)
		_tabs.current_tab = 6	# «Отладка» (вкладка «Вуаль» сдвинула индексы, Sky3.2.8)
		return
	var id := _save_slot.get_selected_id()
	var nn := id
	if id == 99:
		nn = _next_slot_number()
	var preset_path := presets_dir + ("Preset_%02d.tres" % nn)
	var thumb_path := presets_dir + ("preset_%02d.png" % nn)
	var old_jpg := presets_dir + ("preset_%02d.jpg" % nn)
	if with_thumb:
		var img := get_viewport().get_texture().get_image()
		img.save_png(thumb_path)
		# слоты 01-05 исторически держали миниатюру .jpg: после пересохранения
		# миниатюра едина в .png (п. 13.5), старый .jpg удаляем
		if FileAccess.file_exists(old_jpg):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(old_jpg))
	var prev_res: Texture2D = null
	if ResourceLoader.exists(thumb_path):
		prev_res = load(thumb_path)
	p.preview = prev_res
	p.preset_name = "слот %02d (панель Q7.33)" % nn
	var err := ResourceSaver.save(p, preset_path)
	if err != OK:
		lines.append("ResourceSaver.save: %s" % error_string(err))
	else:
		lines.append("сохранено: %s%s" % [preset_path, " + миниатюра" if with_thumb else ""])
		if with_thumb:
			# импорт png произойдёт при перезагрузке проекта; дописываем/правляем
			# ссылку preview в .tres текстом, чтобы миниатюра была в файле сразу
			_patch_preview_into_tres(preset_path, thumb_path)
	_log.text = "\n".join(lines)


func _next_slot_number() -> int:
	var n := 11
	while ResourceLoader.exists(presets_dir + ("Preset_%02d.tres" % n)):
		n += 1
	return n

## Замена только ПЕРВОГО вхождения (у String.replace() в GDScript нет count).
static func _replace_first(s: String, from: String, to: String) -> String:
	var i := s.find(from)
	if i < 0:
		return s
	return s.substr(0, i) + to + s.substr(i + from.length())

func _patch_preview_into_tres(preset_path: String, thumb_path: String) -> void:
	var f := FileAccess.open(preset_path, FileAccess.READ)
	if f == null:
		return
	var t := f.get_as_text()
	f.close()
	var thumb_name := thumb_path.get_file()
	if "preview =" in t:
		# правим путь существующей ссылки (jpg -> png после пересохранения)
		t = t.replace(thumb_name.replace(".png", ".jpg"), thumb_name)
		if t.find('path="%s"' % thumb_path) == -1:
			t = t.replace('path="res://SkyEnvironment/SkyPreset/%s"' % thumb_name.replace(".png", ".jpg"), 'path="%s"' % thumb_path)
	else:
		t = _replace_first(t, '[ext_resource type="Script"', '[ext_resource type="Texture2D" path="%s" id="prev_p"]\n[ext_resource type="Script"' % thumb_path)
		t = _replace_first(t, "script = ExtResource(", 'preview = ExtResource("prev_p")\nscript = ExtResource(')
	var f2 := FileAccess.open(preset_path, FileAccess.WRITE)
	if f2:
		f2.store_string(t)
		f2.close()


# ================= сброс вуали и пресеты-референсы (Sky3.2.14) =================
const REFS_DIR := "res://SkyEnvironment/SkyPresetRefs/"

## Задача 3 заказчика: выбор пресета вуаль не сбрасывает; сброс — ОДНА кнопка:
## все uniform'ы вуали/ветра возвращаются к дефолтам компонента (VEIL_DEFAULTS),
## запись только через контроллер (писатель один).
func _veil_reset() -> void:
	if controller == null:
		return
	for uni in VEIL_DEFAULTS:
		_set_param(uni, VEIL_DEFAULTS[uni])
	_sync_ui()
	if _log != null:
		_log.text = "вуаль: сброс к дефолтам компонента (%d uniform)" % VEIL_DEFAULTS.size()


## Сканирует REFS_DIR: список именованных референсов (сортировка по имени).
func _refresh_refs() -> void:
	if _ref_list == null:
		return
	_ref_list.clear()
	var dir := DirAccess.open(REFS_DIR)
	if dir == null:
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".tres"):
			names.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for nm in names:
		_ref_list.add_item(nm.get_basename(), 0)
		_ref_list.set_item_metadata(_ref_list.item_count - 1, REFS_DIR + nm)


## Сохранение ТЕКУЩЕГО состояния (включая живую вуаль) в именованный референс.
func _save_ref() -> void:
	if controller == null:
		return
	var p := _collect_current()
	var res: Dictionary = SkyPresetValidator.validate(p)
	if not res["errors"].is_empty():
		if _log != null:
			_log.text = "ОШИБКИ валидатора, сохранение заблокировано:\n" + "\n".join(res["errors"])
		return
	var raw := _ref_name.text.strip_edges()
	if raw.is_empty():
		raw = "ref_%s" % Time.get_datetime_string_from_system().replace(":", "-")
	var safe := ""
	for ch in raw:
		safe += ch if (ch.unicode_at(0) >= 48 and ch.unicode_at(0) <= 57) or (ch.unicode_at(0) >= 65 and ch.unicode_at(0) <= 90) or (ch.unicode_at(0) >= 97 and ch.unicode_at(0) <= 122) or ch in "_-" or (ch.unicode_at(0) >= 0x400 and ch.unicode_at(0) <= 0x45F) else "_"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(REFS_DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REFS_DIR))
	var path := REFS_DIR + safe + ".tres"
	p.preset_name = raw
	var err := ResourceSaver.save(p, path)
	if _log != null:
		_log.text = ("сохранён референс: %s" % path) if err == OK else ("ResourceSaver: %s" % error_string(err))
	_refresh_refs()
	for i in range(_ref_list.item_count):
		if _ref_list.get_item_metadata(i) == path:
			_ref_list.selected = i


## Выбор референса из списка: небо применяется, вуаль НЕ трогается (задача 3).
func _load_ref() -> void:
	var id := _ref_list.selected
	if id < 0 or controller == null:
		return
	var path: String = _ref_list.get_item_metadata(id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var pr := load(path) as SkyPreset
	if pr == null:
		return
	controller.apply_preset(pr)
	_sync_ui()
	if _log != null:
		_log.text = "выбран референс: %s (вуаль не тронута)" % path


# ================= валидатор (вкладка «Отладка») =================
func _run_validator() -> void:
	var res: Dictionary = SkyPresetValidator.validate(_collect_current())
	var lines: Array[String] = []
	for e in res["errors"]:
		lines.append("ОШИБКА: " + e)
	for w in res["warnings"]:
		lines.append("ПРЕДУПРЕЖДЕНИЕ: " + w)
	if lines.is_empty():
		lines.append("валидатор: ошибок и предупреждений нет")
	_log.text = "\n".join(lines)


func _run_set_check() -> void:
	var ws: Array = SkyPresetValidator.check_set(presets)
	var lines: Array[String] = []
	for w in ws:
		lines.append("ПРЕДУПРЕЖДЕНИЕ НАБОРА: " + w)
	if lines.is_empty():
		lines.append("набор: дубликатов формы q1..q3 нет")
	_log.text = "\n".join(lines)


# ================= синхронизация UI с материалом/светом =================
func _sync_ui() -> void:
	if controller == null:
		return
	_syncing = true
	for i in range(4):
		_stop_pickers[i].color = Color(_get_param(COL_UNIS[i]))
	for uni in _src_pickers:
		_src_pickers[uni].color = Color(_get_param(uni))
	for uni in _src_sliders:
		_src_sliders[uni].set_value_no_signal(_src_get(uni))	# fix.4.1.7: NULL-безопасно (старый материал)
	var gw := _grad_weights()
	if gw != null and gw.sliders.size() == 4:
		var wv_v: Variant = _get_param("sky_color_weights")
		if wv_v != null:
			var wv := Vector4(wv_v)
			for i in range(4):
				gw.sliders[i].set_value_no_signal(wv[i] * 100.0)
	_arc_slider.set_value_no_signal(float(_get_param("sk_arc_stretch")))
	_breathe_slider.set_value_no_signal(float(_get_param("sk_breathe")))
	_squeeze_slider.set_value_no_signal(float(_get_param("sk_squeeze")))
	_dither_slider.set_value_no_signal(float(_get_param("sk_dither")))
	_stars_slider.set_value_no_signal(float(_get_param("star_intensity")))
	_tonemap_check.set_pressed_no_signal(int(_get_param("sk_tonemap")) == 1)
	_debug_mode_spin.value = float(_get_param("sky_debug_mode"))
	_sun_az.set_value_no_signal(controller.sun_azimuth)
	_sun_el.set_value_no_signal(controller.sun_elevation)
	_moon_az.set_value_no_signal(controller.moon_azimuth)
	_moon_el.set_value_no_signal(controller.moon_elevation)
	_sun_on.button_pressed = controller.sun_enabled
	_moon_on.button_pressed = controller.moon_enabled
	var lc := _light_ctrl()
	if lc:
		_key_col.color = lc.get_key_light_color()
		_key_en.set_value_no_signal(lc.get_key_light_energy())
		_moon_lcol.color = lc.get_moon_light_color()
		_moon_len.set_value_no_signal(lc.get_moon_light_energy())
		_ambient_slider.set_value_no_signal(lc.get_ambient_energy())
	_veil_on.set_pressed_no_signal(bool(_veil_get("hc_enabled")))
	for uni in _veil_sliders:
		_veil_sliders[uni].set_value_no_signal(float(_veil_get(uni)))
	_veil_col.color = Color(_veil_get("hc_color"))
	_veil_lighting.set_pressed_no_signal(bool(_veil_get("hc_use_lighting")))
	_veil_shadow.set_pressed_no_signal(bool(_veil_get("hc_use_shadowing")))
	_veil_debug_spin.value = float(_veil_get("hc_debug"))
	_wind_on.set_pressed_no_signal(bool(_veil_get("hc_wind_enabled")))
	_wind_dir.set_value_no_signal(float(_veil_get("hc_wind_dir_deg")))
	_wind_speed.set_value_no_signal(float(_veil_get("hc_wind_speed")))
	_wind_tl.set_value_no_signal(float(_veil_get("hc_wind_timelapse")))
	_sync_atmo()
	_syncing = false
	_refresh_strip()
