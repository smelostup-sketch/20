extends Node
## SkyLabPanel — компаньон-панель стенда Q7.32_SKYprav_3.1 (план v1.0, zip v0.3).
##
## v0.3: (а) панель позиционируется явно от фактического размера окна — не уезжает
## за правую границу; (б) шаг 4b: блендер состояний — слайдер t ∈ [1..5] по
## последовательности ref1→ref5, палитра и солнце интерполируются между СОСЕДНИМИ
## ключами (D2), пресеты = целые t.
##
## НЕ модифицирует CloudsTestBench.gd. Солнце: панель пишет DirectionalLight3D,
## бенч читает по конвенции sync_sun_from_light; обратный синк — read-only,
## выключен во время драга ползунков (drag-guard) и пока изменение < 0.2°.
## Управление: F8 — панель, F9 — скриншот (выдержка 40 кадров под incremental-небо).

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
const WHITE_ADAPTED := Vector3(2.0, 2.0, 2.0)	# display-white после Filmic = scene 2.0
const SEQ := ["ref1", "ref2", "ref3", "ref4", "ref5"]	# последовательность бленда (4b)
const PRESET_ELEV := [-1.5, 1.0, 10.0, 0.0, -5.0]
const PRESET_AZIM := [180.0, 180.0, 180.0, 180.0, 180.0]
const PANEL_W := 352.0

@export var sun_light_path: NodePath = ^"../DirectionalLight3D"
@export var env_path: NodePath = ^"../WorldEnvironment"
@export var capture_settle_frames := 40
@export var shots_dir := "user://skylab_shots/"
@export var refs_dir := "res://Q7.32_SKYprav_3.1/refs/"

var _light: DirectionalLight3D = null
var _sky_mat: ShaderMaterial = null
var _cards: Node = null
var _layer: CanvasLayer = null
var _panel_root: Control = null
var _panel: PanelContainer = null
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
var _include_ui := false
var _vp_cache := Vector2.ZERO


func _ready() -> void:
	_light = get_node_or_null(sun_light_path) as DirectionalLight3D
	if _light == null:
		push_error("[SkyLab] не найден DirectionalLight3D по пути %s" % str(sun_light_path))
	var we := get_node_or_null(env_path) as WorldEnvironment
	if we != null and we.environment != null and we.environment.sky != null:
		_sky_mat = we.environment.sky.sky_material as ShaderMaterial
	if _sky_mat == null:
		push_error("[SkyLab] не найден sky-материал для записи палитр состояний")
	_cards = get_node_or_null(^"../SkyLabCards")
	_build_ui()
	_apply_t(4.0)	# старт с ref4 (решение D5)
	print("[SkyLab] v0.5.2 | 8/F8 панель, F9 скрин | t-блендер ref1..ref5 | start=ref4")


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 8	# v0.13: ниже UI бенча (9) — старый интерфейс доступен при отладке
	add_child(_layer)

	_panel_root = Control.new()
	_panel_root.name = "SkyLabRoot"
	_panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_panel_root)

	_panel = PanelContainer.new()
	# без якорей: позиция/размер ставятся явно в _place_panel() от размера окна
	_panel_root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "SkyLab v0.5.2"
	vbox.add_child(title)

	_blend_slider = HSlider.new()
	_blend_slider.min_value = 1.0
	_blend_slider.max_value = 5.0
	_blend_slider.step = 0.01
	_blend_slider.value = 4.0
	_blend_slider.custom_minimum_size = Vector2(0, 24)
	_blend_slider.tooltip_text = "Состояние t: 1=ref1 … 5=ref5, между целыми — плавный бленд соседних ключей"
	_blend_slider.value_changed.connect(func(v: float) -> void:
		if _writing:
			return
		_apply_t(v))
	vbox.add_child(_blend_slider)

	_elev_slider = _make_slider(-15.0, 89.5, 0.1, 0.0)
	_azim_slider = _make_slider(0.0, 360.0, 0.5, 180.0)
	vbox.add_child(_elev_slider)
	vbox.add_child(_azim_slider)

	_info = Label.new()
	vbox.add_child(_info)

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

	var shot := Button.new()
	shot.text = "Скриншот (F9)"
	shot.pressed.connect(func() -> void: _request_capture())
	vbox.add_child(shot)

	var inc := CheckButton.new()
	inc.text = "UI в кадре"
	vbox.add_child(inc)
	inc.toggled.connect(func(on: bool) -> void: _include_ui = on)

	var cld := CheckButton.new()
	cld.text = "Кучевые (sk_clouds_on)"
	cld.button_pressed = _sky_mat != null and float(_sky_mat.get_shader_parameter("sk_clouds_on")) > 0.5
	vbox.add_child(cld)
	cld.toggled.connect(func(on: bool) -> void:
		if _sky_mat != null:
			_sky_mat.set_shader_parameter("sk_clouds_on", 1.0 if on else 0.0))

	var thumbs := HBoxContainer.new()
	thumbs.add_theme_constant_override("separation", 4)
	vbox.add_child(thumbs)
	for i in range(5):
		var path := refs_dir + "ref%d.png" % (i + 1)
		var tr := TextureRect.new()
		var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if tex == null:
			push_error("[SkyLab] референс не найден: %s" % path)
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

	var cards_title := Label.new()
	cards_title.text = "Карточки (frustum-якоря)"
	vbox.add_child(cards_title)
	if _cards != null and _cards.has_method("card_count"):
		for i in range(_cards.card_count()):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			vbox.add_child(row)
			var vis := CheckButton.new()
			vis.text = _cards.card_name(i)
			vis.button_pressed = true
			var idx := i
			vis.toggled.connect(func(on: bool) -> void: _cards.set_card_visible(idx, on))
			row.add_child(vis)
			var ranges := {"ax": [-1.3, 1.3], "ay": [-1.0, 1.0], "scale": [0.2, 2.2]}
			for key in ["ax", "ay", "scale"]:
				var rng: Array = ranges[key]
				var sl := HSlider.new()
				sl.min_value = rng[0]
				sl.max_value = rng[1]
				sl.step = 0.01
				sl.value = 0.0 if key != "scale" else 1.0
				sl.custom_minimum_size = Vector2(70, 20)
				sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sl.tooltip_text = key
				var k: String = key
				sl.value = _cards.get_card_param(idx, k)
				sl.value_changed.connect(func(v: float) -> void: _cards.set_card_param(idx, k, v))
				row.add_child(sl)

	var reanch := Button.new()
	reanch.text = "Переякорить всё (из текущей камеры)"
	reanch.pressed.connect(func() -> void:
		if _cards != null and _cards.has_method("reanchor_all"):
			_cards.reanchor_all())
	vbox.add_child(reanch)

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


func _make_slider(minv: float, maxv: float, step: float, val: float) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = minv
	sl.max_value = maxv
	sl.step = step
	sl.value = val
	sl.custom_minimum_size = Vector2(0, 24)
	sl.value_changed.connect(func(v: float) -> void:
		if _writing:
			return
		if sl == _elev_slider:
			_set_sun(v, _cur_azim)
		else:
			_set_sun(_cur_elev, v))
	sl.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			_dragging = ev.pressed)
	return sl


## 4b: состояние t ∈ [1..5]; между целыми — линейная интерполяция СОСЕДНИХ ключей
## последовательности SEQ (палитра неба + солнце). Целые t = пресеты.
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
	var rim: Vector3 = (a["rim"] as Vector3).lerp(b["rim"] as Vector3, f)
	var r0 := Vector3.ZERO
	var r1 := Vector3.ZERO
	var r2 := Vector3.ZERO
	var r3 := Vector3.ZERO
	var r4 := Vector3.ZERO
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("sk_zenith", zen)
		_sky_mat.set_shader_parameter("sk_horizon", hor)
		_sky_mat.set_shader_parameter("sk_glow_col", hor)
		# ColorRamp освещения облаков (D3): 5 стопов из ролей состояния
		r0 = shd.lerp(zen, 0.6)		# сине-фиолетовая глубина
		r1 = shd						# сливово-бордовая тень
		r2 = lit.lerp(hor, 0.5)		# персик-коралл
		r3 = lit						# освещённая зона
		r4 = lit.lerp(WHITE_ADAPTED, 0.6)	# почти белый блик
		_sky_mat.set_shader_parameter("sk_ramp0", r0)
		_sky_mat.set_shader_parameter("sk_ramp1", r1)
		_sky_mat.set_shader_parameter("sk_ramp2", r2)
		_sky_mat.set_shader_parameter("sk_ramp3", r3)
		_sky_mat.set_shader_parameter("sk_ramp4", r4)
		_sky_mat.set_shader_parameter("sk_rim_col", rim)
		# v0.9 (Г2): море на горизонте = осветлённый горизонт (светлая полоса, не растворение)
		_sky_mat.set_shader_parameter("atmo_color", hor.lerp(WHITE_ADAPTED, 0.45))
		_sky_mat.set_shader_parameter("sk_below_col", shd.lerp(Vector3.ZERO, 0.45))
		_sky_mat.set_shader_parameter("sk_anti_col", r0 * 0.30)	# v0.13: антисоляр = глубокая тень состояния
	if _cards != null and _cards.has_method("set_state"):
		_cards.set_state({"shadow": shd, "lit": lit, "rim": rim, "horizon": hor, "zenith": zen,
				"ramp0": r0, "ramp1": r1, "ramp2": r2, "ramp3": r3, "ramp4": r4})
	_state_tag = SEQ[i0 if f < 0.5 else i1]
	_writing = true
	if _blend_slider != null:
		_blend_slider.value = _t
	_writing = false
	var elev := lerpf(PRESET_ELEV[i0], PRESET_ELEV[i1], f)
	var azim := lerpf(PRESET_AZIM[i0], PRESET_AZIM[i1], f)
	_set_sun(elev, azim)
	_update_info()


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
	if _cards != null and _cards.has_method("set_sun"):
		_cards.set_sun(dir, _cur_elev)
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


## Панель: правый верхний угол окна с отступом 8 px, ширина фикс, высота по контенту.
func _place_panel() -> void:
	if _panel == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vps := vp.get_visible_rect().size
	var h := maxf(_panel.get_combined_minimum_size().y, 32.0)
	var x := vps.x - PANEL_W - 8.0
	if x < 4.0:
		x = 4.0
	_panel.position = Vector2(x, 8.0)
	_panel.size = Vector2(PANEL_W, h)
	_vp_cache = vps


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F8 or event.keycode == KEY_8:
			# v0.14: клавиша 8 — новый интерфейс SkyLab (старый бенч-UI остаётся на 9)
			_panel_root.visible = not _panel_root.visible
		elif event.keycode == KEY_F9:
			_request_capture()


func _request_capture() -> void:
	_capture_in = max(1, capture_settle_frames)


func _process(_delta: float) -> void:
	var vp := get_viewport()
	if vp != null and vp.get_visible_rect().size != _vp_cache:
		_place_panel()
	# read-only синк со светом (F1 бенча): только вне драга и при изменении > 0.2°
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
		push_error("[SkyLab] не удалось снять кадр (пустой image)")
	else:
		DirAccess.make_dir_recursive_absolute(shots_dir)
		var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
		var path := "%sskylab_%s_el%+.1f_az%.1f_%s.png" % [shots_dir, _state_tag, _cur_elev, _cur_azim, stamp]
		var err := img.save_png(path)
		if err != OK:
			push_error("[SkyLab] save_png ошибка %d: %s" % [err, path])
		else:
			print("[SkyLab] скрин сохранён: %s" % ProjectSettings.globalize_path(path))
	if not _include_ui:
		_layer.visible = true
