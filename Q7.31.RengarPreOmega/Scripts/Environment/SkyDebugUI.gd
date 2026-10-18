extends Node
class_name SkyDebugUI
## Отладочная панель неба (Q7.30, замена SkyDebugPreview из Q7.29).
## Клавиша 0 — показать/скрыть панель; работает и в Сцене_неба, и в Основной_сцене.
## На панели: текущая фаза и её смена (кнопки, плавно 3 с или мгновенно),
## автопрогресс, покрытие облаков и скорость ветра (слайдеры), качество.
##
## РОДОСЛОВНАЯ ФИКСА (Q7.31): в Основной_сцене мышь захвачена камерой
## (ThirdPersonCamera._ready → Input.MOUSE_MODE_CAPTURED), поэтому клики
## уходили в камеру и кнопками/слайдерами панели было нельзя воспользоваться.
## Теперь открытие панели СОХРАНЯЕТ текущий режим мыши и ставит VISIBLE,
## закрытие — ВОЗВРАЩАЕТ сохранённый (в Основной_сцене снова CAPTURED,
## в Сцене_неба остаётся VISIBLE). Чисто событийно, без таймеров.
##
## РОДОСЛОВНАЯ ФИКСА (Q7.30): в Q7.29 горячие клавиши не работали по двум
## причинам: (1) у SkyDebugPreview экспорт был node-typed
## (`@export var controller: TimeOfDayController`), а рукописный tscn присваивал
## в него NodePath — Godot такую конверсию не делает, controller оставался null
## и любой ключ уходил в early return; (2) в Основной_сцене узла превью не было
## вовсе. Здесь экспорт — NodePath (проектный паттерн light_path/player_path),
## узел добавлен в ОБЕ сцены. Цифровых хоткеев 1–9 больше нет: всё на панели.
##
## Панель строится кодом (без tscn-Control): рукописный tscn не резолвит
## node-typed экспорты, а программная сборка не зависит от порядка загрузки.
## Никаких таймеров: реакция только на события ввода и сигналы Control.

@export var controller_path: NodePath

const PHASE_NAMES := ["ЗАКАТ", "СУМЕРКИ", "НОЧЬ"]
const COVERAGE_MAX := 0.95  # совпадает с клампом debug_set_coverage контроллера
const WIND_MAX := 5.0       # ручка панели; контроллер клампит шире (0..10)

var controller: TimeOfDayController = null

var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _status: Label = null
var _cov_slider: HSlider = null
var _cov_value: Label = null
var _wind_slider: HSlider = null
var _wind_value: Label = null
var _auto_check: CheckBox = null
var _instant_check: CheckBox = null
var _quality_check: CheckBox = null
var _syncing := false          # программная установка слайдеров не толкает контроллер
var _cov_dragging := false     # пока тянем слайдер — не перезаписываем его из контроллера
var _wind_dragging := false
var _saved_mouse_mode: int = Input.MOUSE_MODE_VISIBLE  # режим мыши до открытия панели (Q7.31)

## Q7.31: чтение/запись режима мыши вынесены в инъектируемые Callable.
## Причина: headless-DisplayServer игнорирует режим мыши (замер: set CAPTURED →
## get 0), поэтому стенд sim_debug_ui подменяет эти две функции и проверяет
## логику освобождения/возврата захвата честно. В игре дефолты = настоящий Input.
var mouse_get_mode: Callable = func() -> int: return Input.get_mouse_mode()
var mouse_set_mode: Callable = func(m: int) -> void: Input.set_mouse_mode(m)


func _ready() -> void:
	if controller_path != NodePath():
		controller = get_node_or_null(controller_path) as TimeOfDayController
	if controller == null:
		push_warning("SkyDebugUI: контроллер суток не найден по пути %s — панель отключена" % str(controller_path))
		return
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if _panel == null:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_0:
		_toggle_panel()
		get_viewport().set_input_as_handled()


## Q7.31: панель + мышь. В Основной_сцене мышь захвачена камерой — клики по
## панели невозможны. Открывая панель, запоминаем режим и освобождаем мышь;
## закрывая — возвращаем запомненный режим (симметрия с UIMenuController:
## меню паузы делает то же самое через DisplayServer).
func _toggle_panel() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_saved_mouse_mode = int(mouse_get_mode.call())
		if _saved_mouse_mode != Input.MOUSE_MODE_VISIBLE:
			mouse_set_mode.call(Input.MOUSE_MODE_VISIBLE)
	else:
		mouse_set_mode.call(_saved_mouse_mode)


func _process(_delta: float) -> void:
	if _panel == null:
		return
	_refresh_status()
	_sync_sliders_from_controller()


# === СБОРКА ПАНЕЛИ ===
func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "SkyDebugLayer"
	_layer.layer = 100  # поверх отладочных панелей сцены (AIDebugLog и др.)
	add_child(_layer)

	_panel = PanelContainer.new()
	_panel.name = "SkyDebugPanel"
	_panel.visible = false  # по умолчанию скрыта; клавиша 0 открывает
	_panel.position = Vector2(12, 12)
	_panel.custom_minimum_size = Vector2(430, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.10, 0.88)
	style.border_color = Color(0.55, 0.35, 0.75, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	_layer.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "НЕБО — ОТЛАДОЧНАЯ ПАНЕЛЬ   [0 — скрыть/показать]"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 1.0))
	vbox.add_child(title)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_status)

	# --- ряд фаз ---
	var phase_row := HBoxContainer.new()
	phase_row.add_theme_constant_override("separation", 6)
	vbox.add_child(phase_row)
	for i in range(3):
		var b := Button.new()
		b.text = PHASE_NAMES[i]
		b.custom_minimum_size = Vector2(96, 30)
		var phase_idx := i
		b.pressed.connect(_on_phase_button.bind(phase_idx))
		phase_row.add_child(b)
	_instant_check = CheckBox.new()
	_instant_check.text = "мгновенно"
	_instant_check.tooltip_text = "Без crossfade: set_phase_instant вместо плавных 3 с"
	phase_row.add_child(_instant_check)

	# --- ряд режимов ---
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	vbox.add_child(mode_row)
	_auto_check = CheckBox.new()
	_auto_check.text = "автопрогресс фаз"
	_auto_check.toggled.connect(_on_auto_toggled)
	mode_row.add_child(_auto_check)
	_quality_check = CheckBox.new()
	_quality_check.text = "качество (деталь+гало)"
	_quality_check.toggled.connect(_on_quality_toggled)
	mode_row.add_child(_quality_check)

	# --- слайдер облаков ---
	var cov_row := HBoxContainer.new()
	cov_row.add_theme_constant_override("separation", 8)
	vbox.add_child(cov_row)
	var cov_lbl := Label.new()
	cov_lbl.text = "облака (покрытие)"
	cov_lbl.custom_minimum_size = Vector2(130, 0)
	cov_row.add_child(cov_lbl)
	_cov_slider = HSlider.new()
	_cov_slider.min_value = 0.0
	_cov_slider.max_value = COVERAGE_MAX
	_cov_slider.step = 0.01
	_cov_slider.custom_minimum_size = Vector2(220, 0)
	_cov_slider.value_changed.connect(_on_coverage_changed)
	_cov_slider.drag_started.connect(func() -> void: _cov_dragging = true)
	_cov_slider.drag_ended.connect(func(_v: float) -> void: _cov_dragging = false)
	cov_row.add_child(_cov_slider)
	_cov_value = Label.new()
	_cov_value.custom_minimum_size = Vector2(44, 0)
	cov_row.add_child(_cov_value)

	# --- слайдер ветра ---
	var wind_row := HBoxContainer.new()
	wind_row.add_theme_constant_override("separation", 8)
	vbox.add_child(wind_row)
	var wind_lbl := Label.new()
	wind_lbl.text = "ветер (×скорость)"
	wind_lbl.custom_minimum_size = Vector2(130, 0)
	wind_row.add_child(wind_lbl)
	_wind_slider = HSlider.new()
	_wind_slider.min_value = 0.0
	_wind_slider.max_value = WIND_MAX
	_wind_slider.step = 0.05
	_wind_slider.custom_minimum_size = Vector2(220, 0)
	_wind_slider.value_changed.connect(_on_wind_changed)
	_wind_slider.drag_started.connect(func() -> void: _wind_dragging = true)
	_wind_slider.drag_ended.connect(func(_v: float) -> void: _wind_dragging = false)
	wind_row.add_child(_wind_slider)
	_wind_value = Label.new()
	_wind_value.custom_minimum_size = Vector2(44, 0)
	wind_row.add_child(_wind_value)

	var hint := Label.new()
	hint.text = "Цифровых хоткеев больше нет: всё здесь. Панель — клавиша 0 (она же освобождает мышь)."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.7, 0.65, 0.8))
	vbox.add_child(hint)

	_sync_controls_from_controller()
	_refresh_status()


# === СОБЫТИЯ ПАНЕЛИ (только события, без таймеров) ===
func _on_phase_button(idx: int) -> void:
	if _instant_check.button_pressed:
		controller.set_phase_instant(idx)
	else:
		controller.transition_to(idx, 3.0)
	_refresh_status()


func _on_auto_toggled(on: bool) -> void:
	if on:
		controller.start_auto()
	else:
		controller.stop_auto()
	_refresh_status()


func _on_quality_toggled(on: bool) -> void:
	if controller.quality != null:
		controller.quality.quality_detail = 1.0 if on else 0.0
	_refresh_status()


func _on_coverage_changed(v: float) -> void:
	if _syncing:
		return
	controller.debug_set_coverage(v)
	_cov_value.text = "%.2f" % controller.current.cloud_coverage


func _on_wind_changed(v: float) -> void:
	if _syncing:
		return
	controller.debug_set_wind_multiplier(v)
	_wind_value.text = "%.2f" % controller.get_wind_multiplier()


# === СИНХРОНИЗАЦИЯ ===
## Хоткеи/внешние системы могли поменять состояние мимо панели — слайдеры
## догоняют контроллер, пока их не тянут рукой.
func _sync_sliders_from_controller() -> void:
	if controller.current == null:
		return
	if not _cov_dragging:
		var cov := controller.current.cloud_coverage
		if absf(_cov_slider.value - cov) > 0.001:
			_syncing = true
			_cov_slider.value = cov
			_syncing = false
		_cov_value.text = "%.2f" % cov
	if not _wind_dragging:
		var wm := controller.get_wind_multiplier()
		if absf(_wind_slider.value - wm) > 0.001:
			_syncing = true
			_wind_slider.value = wm
			_syncing = false
		_wind_value.text = "%.2f" % wm


func _sync_controls_from_controller() -> void:
	_syncing = true
	_auto_check.button_pressed = controller.auto_progress
	_quality_check.button_pressed = controller.quality != null and controller.quality.quality_detail > 0.5
	if controller.current != null:
		_cov_slider.value = controller.current.cloud_coverage
		_cov_value.text = "%.2f" % controller.current.cloud_coverage
	_wind_slider.value = controller.get_wind_multiplier()
	_wind_value.text = "%.2f" % controller.get_wind_multiplier()
	_syncing = false


func _refresh_status() -> void:
	if _status == null:
		return
	var q := "Quality"
	if controller.quality != null and controller.quality.quality_detail < 0.5:
		q = "Performance"
	var line := "фаза: %s" % PHASE_NAMES[controller.get_phase()]
	if controller.is_transitioning():
		line += "  →  %s (переход)" % PHASE_NAMES[controller.get_target_phase()]
	line += " | авто: %s | %s" % ["вкл" if controller.auto_progress else "выкл", q]
	if controller.current != null:
		line += "\nпокрытие %.2f | ветер ×%.2f" % [controller.current.cloud_coverage, controller.get_wind_multiplier()]
	_status.text = line
