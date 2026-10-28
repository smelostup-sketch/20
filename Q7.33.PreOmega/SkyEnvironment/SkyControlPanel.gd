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

const MIN_GAP_PCT := 1.0	# 1% шкалы (п. 13.4); тот же MIN_GAP, что в валидаторе (0.01)
const STOP_LABELS := ["стоп 1 (ядро)", "стоп 2 (горизонт)", "стоп 3 (пояс 1)", "стоп 4 (пояс 2)", "стоп 5 (середина)", "стоп 6 (антисоляр)"]
const P_UNIS := ["sk_p1", "sk_p2", "sk_p3", "sk_p4", "sk_p5", "sk_p6"]
const COL_UNIS := ["sk_glow_col", "sk_horizon", "sk_band_col", "sk_band2_col", "sk_mid", "sk_anti_col"]
const COL_FIELDS := ["col_glow", "col_horizon", "col_band", "col_band2", "col_mid", "col_anti"]

var _panel: PanelContainer
var _tabs: TabContainer
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _is_open: bool = false
var _syncing := false

# вкладка «Градиент»
var _strip: RampStrip
var _stop_pickers: Array[ColorPickerButton] = []
var _lock_checks: Array[CheckButton] = []
var _pct_spins: Array[SpinBox] = []
var _table_labels: Array[Label] = []
var _locked: Array[bool] = [false, false, false, false, false, false]
var _sharp_slider: HSlider
var _arc_slider: HSlider
var _scale_slider: HSlider
var _scale_base: Array = []
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
# вкладка «Свет сцены»
var _key_col: ColorPickerButton
var _key_en: HSlider
var _moon_lcol: ColorPickerButton
var _moon_len: HSlider
var _ambient_slider: HSlider
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
		var best := -1
		var bd := 9.0
		for i in range(pos.size()):
			var d := absf(float(pos[i]) / 100.0 * size.x - x)
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
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		for px in range(w):
			var u := float(px) / float(w - 1)
			var lin: Color = SkyPresetValidator.ramp_color(data["stops"], data["pos"], data["sharp"], u)
			var c: Color = SkyPresetValidator.filmic3_c(lin)	# display, как в небе
			for py in range(h):
				img.set_pixel(px, py, Color(c.r, c.g, c.b))
		draw_texture(ImageTexture.create_from_image(img), Vector2.ZERO)
		var pos: Array = host.strip_positions_pct()
		for i in range(pos.size()):
			var x := float(pos[i]) / 100.0 * size.x
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
	_build_presets_tab()
	_build_debug_tab()
	_tabs.current_tab = 0


func _build_gradient_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Градиент"
	_tabs.add_child(box)

	_strip = RampStrip.new()
	_strip.host = self
	_strip.stop_dragged.connect(_on_strip_drag)
	box.add_child(_strip)

	var head := HBoxContainer.new()
	box.add_child(head)
	for i in range(6):
		var pick := ColorPickerButton.new()
		pick.custom_minimum_size = Vector2(44.0, 26.0)
		pick.color_changed.connect(_on_stop_color.bind(i))
		_stop_pickers.append(pick)
		head.add_child(pick)
	var halo_pick := ColorPickerButton.new()
	halo_pick.custom_minimum_size = Vector2(44.0, 26.0)
	halo_pick.tooltip_text = "ореол источника (sk_halo_col)"
	halo_pick.color_changed.connect(func(c: Color) -> void: _set_param("sk_halo_col", c))
	_src_pickers["sk_halo_col"] = halo_pick
	head.add_child(halo_pick)

	for i in range(6):
		var row := HBoxContainer.new()
		box.add_child(row)
		var lbl := Label.new()
		lbl.text = STOP_LABELS[i]
		lbl.custom_minimum_size = Vector2(120.0, 0.0)
		row.add_child(lbl)
		var spin := SpinBox.new()
		spin.min_value = 0.0
		spin.max_value = 100.0
		spin.step = 0.1
		spin.suffix = "%"
		spin.value_changed.connect(_on_pct_spin.bind(i))
		_pct_spins.append(spin)
		row.add_child(spin)
		var lock := CheckButton.new()
		lock.text = "замок"
		lock.toggled.connect(func(on: bool, idx: int = i) -> void:
			_locked[idx] = on
			_refresh_strip())
		_lock_checks.append(lock)
		row.add_child(lock)

	var table := VBoxContainer.new()
	box.add_child(table)
	for i in range(6):
		var tl := Label.new()
		tl.text = "—"
		_table_labels.append(tl)
		table.add_child(tl)

	_sharp_slider = _add_slider(box, "Резкость переходов sk_sharp (1.0 = окно до стопа)", 0.05, 1.0, 1.0, 0.01,
		func(v: float) -> void: _set_param("sk_sharp", v))
	_arc_slider = _add_slider(box, "Эллипс sk_arc_stretch", 1.0, 4.0, 2.4, 0.05,
		func(v: float) -> void: _set_param("sk_arc_stretch", v))

	var scale_row := HBoxContainer.new()
	box.add_child(scale_row)
	var scale_lbl := Label.new()
	scale_lbl.text = "Масштаб шкалы (0.5×…2.0×, залоченные стоят)"
	scale_row.add_child(scale_lbl)
	_scale_slider = HSlider.new()
	_scale_slider.min_value = 0.5
	_scale_slider.max_value = 2.0
	_scale_slider.step = 0.01
	_scale_slider.value = 1.0
	_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale_slider.gui_input.connect(_on_scale_gui)
	_scale_slider.value_changed.connect(_on_scale_changed)
	scale_row.add_child(_scale_slider)


func _build_source_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Источник"
	_tabs.add_child(box)
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
	var box := VBoxContainer.new()
	box.name = "Купол"
	_tabs.add_child(box)
	_dither_slider = _add_slider(box, "dither (0/1)", 0.0, 1.0, 1.0, 1.0,
		func(v: float) -> void: _set_param("sk_dither", v))
	_stars_slider = _add_slider(box, "Звёзды star_intensity", 0.0, 1.0, 0.0, 0.01,
		func(v: float) -> void: _set_param("star_intensity", v))


func _build_light_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Свет сцены"
	_tabs.add_child(box)
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


func _build_presets_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Пресеты"
	_tabs.add_child(box)
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


func _build_debug_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Отладка"
	_tabs.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var lbl := Label.new()
	lbl.text = "sky_debug_mode (0 небо / 1 карта u / 2 сегменты)"
	row.add_child(lbl)
	_debug_mode_spin = SpinBox.new()
	_debug_mode_spin.min_value = 0
	_debug_mode_spin.max_value = 2
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
func strip_positions_pct() -> Array:
	var out: Array = []
	for uni in P_UNIS:
		out.append(float(_get_param(uni)) * 100.0)
	return out


func strip_data() -> Dictionary:
	var stops: Array = []
	for uni in COL_UNIS:
		stops.append(Color(_get_param(uni)))
	return {"stops": stops, "pos": strip_positions_pct(), "sharp": float(_get_param("sk_sharp"))}


func is_locked(i: int) -> bool:
	return _locked[i]


func _refresh_strip() -> void:
	if _strip:
		_strip.queue_redraw()
	_refresh_table()
	_sync_pct_spins()


func _sync_pct_spins() -> void:
	if _syncing:
		return
	_syncing = true
	var pos := strip_positions_pct()
	for i in range(6):
		_pct_spins[i].value = pos[i]
	_syncing = false


func _refresh_table() -> void:
	var data := strip_data()
	var pos: Array = data["pos"]
	var stops: Array = data["stops"]
	for i in range(6):
		var u := float(pos[i]) / 100.0
		var deg := u * 180.0
		var wdeg := (float(pos[i + 1]) - float(pos[i])) * float(data["sharp"]) * 180.0 if i < 5 else -1.0
		var txt := "%s: u=%.3f  %.1f%%  %.1f°" % [STOP_LABELS[i], u, float(pos[i]), deg]
		if i < 5:
			txt += "  окно %.1f°" % wdeg
		_table_labels[i].text = txt
		var bad := false
		if i < 5:
			var a: Color = stops[i]
			var b: Color = stops[i + 1]
			if (a.r == b.r and a.g == b.g and a.b == b.b) or float(pos[i + 1]) - float(pos[i]) < 1.0:
				bad = true
		_table_labels[i].add_theme_color_override("font_color", Color(1.0, 0.25, 0.25) if bad else Color(0.85, 0.85, 0.85))


# ================= алгоритм маркеров (п. 13.4) =================
func _on_strip_drag(idx: int, q: float) -> void:
	var pos := strip_positions_pct()
	# 1. q зажимается между ближайшими ЗАЛОЧЕННЫМИ соседями (или краями шкалы)
	var lo := 0.0
	var hi := 100.0
	for i in range(idx - 1, -1, -1):
		if _locked[i]:
			lo = float(pos[i])
			break
	for i in range(idx + 1, 6):
		if _locked[i]:
			hi = float(pos[i])
			break
	q = clampf(q, lo + MIN_GAP_PCT, hi - MIN_GAP_PCT)
	var old := float(pos[idx])
	# 2-3. свободные стопы делятся на две группы (до ближайших замков):
	# каждая сохраняет ПРЕЖНИЕ ПРОПОРЦИИ и укладывается в свой интервал:
	# LEFT → (lo, q), RIGHT → (q, hi)
	for i in range(idx - 1, -1, -1):
		if _locked[i]:
			break
		if old - lo > 1e-6:
			pos[i] = lo + (float(pos[i]) - lo) * (q - lo) / (old - lo)
	for i in range(idx + 1, 6):
		if _locked[i]:
			break
		if hi - old > 1e-6:
			pos[i] = q + (float(pos[i]) - old) * (hi - q) / (hi - old)
	pos[idx] = q
	_enforce_gaps(pos)
	_write_positions(pos)


func _on_pct_spin(v: float, idx: int) -> void:
	if _syncing:
		return
	_on_strip_drag(idx, v)
	_refresh_strip()


func _enforce_gaps(pos: Array) -> void:
	# маркеры физически не переходят друг через друга (MIN_GAP), залоченные стоят
	for pass_dir in range(2):
		if pass_dir == 0:
			for i in range(1, 6):
				if _locked[i]:
					continue
				pos[i] = maxf(float(pos[i]), float(pos[i - 1]) + MIN_GAP_PCT)
		else:
			for i in range(4, -1, -1):
				if _locked[i]:
					continue
				pos[i] = minf(float(pos[i]), float(pos[i + 1]) - MIN_GAP_PCT)
	for i in range(6):
		pos[i] = clampf(float(pos[i]), 0.0, 100.0)


func _write_positions(pos: Array) -> void:
	for i in range(6):
		_set_param(P_UNIS[i], float(pos[i]) / 100.0)
	_refresh_strip()


# ================= режим «масштаб» (п. 13.3) =================
func _on_scale_gui(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		_scale_base = strip_positions_pct()


func _on_scale_changed(k: float) -> void:
	if _scale_base.is_empty():
		_scale_base = strip_positions_pct()
	var pos: Array = []
	for i in range(6):
		if _locked[i]:
			pos.append(_scale_base[i])
		else:
			pos.append(clampf(50.0 + (float(_scale_base[i]) - 50.0) * k, 0.0, 100.0))
	_enforce_gaps(pos)
	_write_positions(pos)


# ================= записи через контроллеры =================
func _set_param(uni: String, value: Variant) -> void:
	if controller:
		controller.set_shader_param(uni, value)
	if uni in P_UNIS or uni in COL_UNIS or uni == "sk_sharp":
		_refresh_strip()


func _get_param(uni: String) -> Variant:
	if controller:
		return controller.get_shader_param(uni)
	return 0.0


func _light_ctrl() -> SkyLightController:
	if controller:
		return controller.light_controller
	return null


func _on_stop_color(c: Color, idx: int) -> void:
	_set_param(COL_UNIS[idx], c)


func _on_sun_angles(_v: float) -> void:
	if controller:
		controller.set_sun_angles(_sun_az.value, _sun_el.value)


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
	for i in range(6):
		p.set(COL_FIELDS[i], Color(_get_param(COL_UNIS[i])))
	p.col_halo = Color(_get_param("sk_halo_col"))
	for i in range(6):
		p.set(P_UNIS[i].replace("sk_", ""), float(_get_param(P_UNIS[i])))
	p.sharp = float(_get_param("sk_sharp"))
	p.arc_stretch = float(_get_param("sk_arc_stretch"))
	p.dither = float(_get_param("sk_dither")) > 0.5
	p.star_intensity = float(_get_param("star_intensity"))
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
	var lc := _light_ctrl()
	var prof := SkyLightProfile.new()
	if lc:
		prof.key_color = lc.get_key_light_color()
		prof.key_energy = lc.get_key_light_energy()
		prof.moon_light_color = lc.get_moon_light_color()
		prof.moon_light_energy = lc.get_moon_light_energy()
		prof.ambient_energy = lc.get_ambient_energy()
	p.light = prof
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
		_tabs.current_tab = 5
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
		lines.append("набор: дубликатов формы p1..p5 нет")
	_log.text = "\n".join(lines)


# ================= синхронизация UI с материалом/светом =================
func _sync_ui() -> void:
	if controller == null:
		return
	_syncing = true
	for i in range(6):
		_stop_pickers[i].color = Color(_get_param(COL_UNIS[i]))
	if "sk_halo_col" in _src_pickers:
		_src_pickers["sk_halo_col"].color = Color(_get_param("sk_halo_col"))
	for uni in _src_pickers:
		if uni != "sk_halo_col":
			_src_pickers[uni].color = Color(_get_param(uni))
	for uni in _src_sliders:
		_src_sliders[uni].set_value_no_signal(float(_get_param(uni)))
	_sharp_slider.set_value_no_signal(float(_get_param("sk_sharp")))
	_arc_slider.set_value_no_signal(float(_get_param("sk_arc_stretch")))
	_dither_slider.set_value_no_signal(float(_get_param("sk_dither")))
	_stars_slider.set_value_no_signal(float(_get_param("star_intensity")))
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
	_syncing = false
	_refresh_strip()
