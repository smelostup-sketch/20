extends Node
class_name SkyGradientWeightsComponent
## 4.1.7 (инструкция заказчика) — контроллер долей цветов градиента неба.
## Четыре доли (сумма = 100%) → uniform sky_color_weights (0..1) материала
## градиента. Единственный писатель sky_color_weights; панель строит ручки
## (4 HSlider + 4 CheckButton-замка) и подключает их сюда (attach_controls —
## рантайм-эквивалент назначения в Inspector: UI панели собирается кодом).
## Пресет поставляет доли через SkyEnvironmentController.apply_palette →
## set_weights() (событийно, без кадра).

signal weights_changed(weights: Vector4)

@export_group("Color Sliders")
@export var sliders: Array[HSlider] = []

@export_group("Locks")
@export var locks: Array[CheckButton] = []

@export_group("Shader")
@export var sky_material: ShaderMaterial
@export var shader_parameter_name: StringName = &"sky_color_weights"

const COLOR_COUNT: int = 4
const TOTAL_WEIGHT: float = 100.0
const EPSILON: float = 0.001

## 4.1.7: кэш поставки владельца до подключения ручек (порядок _ready сцены:
## контроллер может применить стартовый пресет раньше, чем панель построит UI).
var _pending_weights := Vector4(-1.0, -1.0, -1.0, -1.0)


func _ready() -> void:
	# Случай Inspector-назначения (инструкция): ручки заданы в сцене —
	# инициализация сразу. Пустые массивы здесь — НЕ ошибка: это штатный
	# рантайм-случай (панель подключит ручки через attach_controls).
	if sliders.size() == COLOR_COUNT and locks.size() == COLOR_COUNT:
		_init_controls()


## Рантайм-подключение ручек (панель строит UI кодом): тот же путь валидации,
## ограничений и сигналов, что и Inspector-случай.
func attach_controls(new_sliders: Array[HSlider], new_locks: Array[CheckButton]) -> void:
	sliders = new_sliders
	locks = new_locks
	if _pending_weights.x >= 0.0:
		for i in range(COLOR_COUNT):
			sliders[i].set_value_no_signal(_pending_weights[i])
	_init_controls()


## Событийный вход владельца долей (пресет применён): сдвинуть слайдеры без
## обратных сигналов и опубликовать веса — тот же путь, что у ручек.
func set_weights(shares: Vector4) -> void:
	if sliders.size() != COLOR_COUNT:
		_pending_weights = shares
		return
	for i in range(COLOR_COUNT):
		sliders[i].set_value_no_signal(shares[i])
	_apply_weights()


func _init_controls() -> void:
	if sliders.size() != COLOR_COUNT or locks.size() != COLOR_COUNT:
		push_error("SkyGradientWeightsComponent: нужны ровно 4 HSlider и 4 CheckButton.")
		return

	for i in range(COLOR_COUNT):
		if sliders[i] == null or locks[i] == null:
			push_error("SkyGradientWeightsComponent: не назначен Slider или Lock #%d." % (i + 1))
			return

		sliders[i].min_value = 0.0
		sliders[i].max_value = TOTAL_WEIGHT
		# 4.1.7 (интеграция): гранулярность шкалы задаёт владелец инварианта
		# «сумма = 100%»: дефолтный step HSlider (1.0) ломает пропорциональное
		# перераспределение (пример инструкции: 16.67/16.67/16.67/50).
		sliders[i].step = 0.001

		sliders[i].value_changed.connect(_on_slider_changed.bind(i))
		locks[i].toggled.connect(_on_lock_toggled)

	# Приводим начальные значения к сумме 100%.
	_redistribute(0, sliders[0].value)


func _on_slider_changed(new_value: float, active_index: int) -> void:
	_redistribute(active_index, new_value)


func _on_lock_toggled(_pressed: bool) -> void:
	# При переключении замка доли не меняются.
	_apply_weights()


func _redistribute(active_index: int, requested_value: float) -> void:
	var locked_sum: float = 0.0
	var unlocked_indices: Array[int] = []

	# Считаем доли зафиксированных цветов.
	# Активный ползунок может менять собственное значение,
	# даже если его замочек включён.
	for i in range(COLOR_COUNT):
		if i == active_index:
			continue

		if locks[i].button_pressed:
			locked_sum += sliders[i].value
		else:
			unlocked_indices.append(i)

	# Активный цвет не может занять больше оставшегося бюджета.
	var max_active: float = TOTAL_WEIGHT - locked_sum
	var active_value: float = clampf(requested_value, 0.0, max_active)

	sliders[active_index].set_value_no_signal(active_value)

	# Остаток распределяется между незакреплёнными цветами.
	var remaining: float = TOTAL_WEIGHT - locked_sum - active_value

	if unlocked_indices.is_empty():
		# Некому отдавать остаток — активный цвет занимает его целиком.
		active_value = max_active
		sliders[active_index].set_value_no_signal(active_value)
	else:
		var old_sum: float = 0.0

		for i in unlocked_indices:
			old_sum += sliders[i].value

		if old_sum > EPSILON:
			# Сохраняем пропорции остальных цветов.
			for i in unlocked_indices:
				var ratio: float = sliders[i].value / old_sum
				sliders[i].set_value_no_signal(remaining * ratio)
		else:
			# Если все остальные значения были нулевыми,
			# делим остаток поровну.
			var equal_share: float = remaining / float(unlocked_indices.size())

			for i in unlocked_indices:
				sliders[i].set_value_no_signal(equal_share)

	_apply_weights()


func _apply_weights() -> void:
	var weights := Vector4(
		sliders[0].value,
		sliders[1].value,
		sliders[2].value,
		sliders[3].value
	)

	if sky_material != null:
		sky_material.set_shader_parameter(shader_parameter_name, weights / TOTAL_WEIGHT)

	weights_changed.emit(weights)
