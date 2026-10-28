
extends CanvasLayer
class_name SkyControlPanel

signal input_block_changed(blocked: bool)

@export var controller: SkyEnvironmentController
@export var presets: Array[SkyPreset] = []

var _panel: PanelContainer
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _is_open: bool = false

var _sun_azimuth: HSlider
var _sun_elevation: HSlider
var _moon_azimuth: HSlider
var _moon_elevation: HSlider

var _sun_toggle: CheckButton
var _moon_toggle: CheckButton
var _veil_toggle: CheckButton

var _veil_coverage: HSlider
var _veil_density: HSlider
var _veil_opacity: HSlider
var _veil_speed: HSlider


func _ready() -> void:
	_build_ui()
	_panel.visible = false

	await get_tree().process_frame

	print("=== SKY PANEL DEBUG ===")
	print("Viewport: ", get_viewport().get_visible_rect().size)
	print("Panel size: ", _panel.size)
	print("Panel position: ", _panel.position)

	var scroll := _panel.get_child(0) as ScrollContainer
	print("Scroll size: ", scroll.size)
	print("Scroll min size: ", scroll.get_combined_minimum_size())

	var layout := scroll.get_child(0) as VBoxContainer
	print("Layout size: ", layout.size)
	print("Layout min size: ", layout.get_combined_minimum_size())



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
	else:
		Input.mouse_mode = _previous_mouse_mode

	input_block_changed.emit(_is_open)


func _add_slider(
	parent: VBoxContainer,
	title: String,
	minimum: float,
	maximum: float,
	initial: float,
	step: float,
	callback: Callable
) -> HSlider:
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


func _build_ui() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	var panel_width: float = minf(340.0, viewport_size.x - 32.0)
	var panel_height: float = minf(680.0, viewport_size.y - 32.0)

	_panel = PanelContainer.new()
	_panel.position = Vector2(16.0, 16.0)
	_panel.size = Vector2(panel_width, panel_height)
	_panel.custom_minimum_size = Vector2(panel_width, 0.0)
	_panel.clip_contents = true
	add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, panel_height - 24.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_panel.add_child(scroll)

	var layout := VBoxContainer.new()
	layout.custom_minimum_size.x = maxf(0.0, panel_width - 48.0)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	layout.add_theme_constant_override("separation", 6)
	scroll.add_child(layout)

	var title := Label.new()
	title.text = "OMEGA SKY CONTROL"
	layout.add_child(title)

	var preset_title := Label.new()
	preset_title.text = "Пресеты"
	layout.add_child(preset_title)

	var preset_grid := GridContainer.new()
	preset_grid.columns = 3
	preset_grid.add_theme_constant_override("h_separation", 6)
	preset_grid.add_theme_constant_override("v_separation", 6)
	layout.add_child(preset_grid)

	for preset: SkyPreset in presets:
		if preset == null:
			continue

		var button := TextureButton.new()
		button.ignore_texture_size = true
		button.custom_minimum_size = Vector2(80.0, 48.0)
		button.size = Vector2(80.0, 48.0)
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		button.texture_normal = preset.preview
		button.tooltip_text = preset.preset_name
		button.pressed.connect(_on_preset_pressed.bind(preset))
		preset_grid.add_child(button)

	_sun_azimuth = _add_slider(
		layout, "Соляр: азимут (°)", 0.0, 360.0,
		0.0, 1.0, _on_sun_azimuth
	)
	_sun_elevation = _add_slider(
		layout, "Соляр: надир −90° / зенит +90°", -90.0, 90.0,
		10.0, 1.0, _on_sun_elevation
	)

	_sun_toggle = CheckButton.new()
	_sun_toggle.text = "Соляр и прямое освещение"
	_sun_toggle.button_pressed = true
	_sun_toggle.toggled.connect(_on_sun_toggle)
	layout.add_child(_sun_toggle)

	_moon_azimuth = _add_slider(
		layout, "Луна: азимут (°)", 0.0, 360.0,
		180.0, 1.0, _on_moon_azimuth
	)
	_moon_elevation = _add_slider(
		layout, "Луна: надир −90° / зенит +90°", -90.0, 90.0,
		25.0, 1.0, _on_moon_elevation
	)

	_moon_toggle = CheckButton.new()
	_moon_toggle.text = "Луна и лунный свет"
	_moon_toggle.toggled.connect(_on_moon_toggle)
	layout.add_child(_moon_toggle)

	var veil_title := Label.new()
	veil_title.text = "Вуаль / перистые облака"
	layout.add_child(veil_title)

	_veil_toggle = CheckButton.new()
	_veil_toggle.text = "Включить вуаль"
	_veil_toggle.toggled.connect(_on_veil_toggle)
	layout.add_child(_veil_toggle)

	_veil_coverage = _add_slider(
		layout, "Покрытие", 0.0, 1.0,
		0.55, 0.01, _on_veil_coverage
	)
	_veil_density = _add_slider(
		layout, "Масштаб облаков", 1.0, 12.0,
		4.0, 0.1, _on_veil_density
	)
	_veil_opacity = _add_slider(
		layout, "Плотность / затенение", 0.0, 1.0,
		0.25, 0.01, _on_veil_opacity
	)
	_veil_speed = _add_slider(
		layout, "Скорость вуали", 0.0, 0.1,
		0.003, 0.001, _on_veil_speed
	)

func _on_preset_pressed(preset: SkyPreset) -> void:
	if controller == null:
		return

	controller.apply_preset(preset)
	_sun_azimuth.set_value_no_signal(preset.sun_azimuth)
	_sun_elevation.set_value_no_signal(preset.sun_elevation)


func _on_sun_azimuth(value: float) -> void:
	if controller != null:
		controller.set_sun_angles(value, _sun_elevation.value)


func _on_sun_elevation(value: float) -> void:
	if controller != null:
		controller.set_sun_angles(_sun_azimuth.value, value)


func _on_moon_azimuth(value: float) -> void:
	if controller != null:
		controller.set_moon_angles(value, _moon_elevation.value)


func _on_moon_elevation(value: float) -> void:
	if controller != null:
		controller.set_moon_angles(_moon_azimuth.value, value)


func _on_sun_toggle(enabled: bool) -> void:
	if controller != null:
		controller.set_sun_enabled(enabled)


func _on_moon_toggle(enabled: bool) -> void:
	if controller != null:
		controller.set_moon_enabled(enabled)


func _on_veil_toggle(enabled: bool) -> void:
	if controller != null:
		controller.set_veil_enabled(enabled)


func _on_veil_coverage(value: float) -> void:
	if controller != null:
		controller.set_veil_parameter("veil_coverage", value)


func _on_veil_density(value: float) -> void:
	if controller != null:
		controller.set_veil_parameter("veil_density", value)


func _on_veil_opacity(value: float) -> void:
	if controller != null:
		controller.set_veil_parameter("veil_opacity", value)


func _on_veil_speed(value: float) -> void:
	if controller != null:
		controller.set_veil_parameter("veil_speed", value)
