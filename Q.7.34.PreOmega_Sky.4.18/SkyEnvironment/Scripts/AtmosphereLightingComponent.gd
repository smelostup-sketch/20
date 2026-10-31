extends Node
class_name AtmosphereLightingComponent
## Q.7.34.PreOmega_Sky.4.1.1 (план света, этап 02) — компонент-ПОСТАВЩИК
## параметров освещения. Читает существующий DirectionalLight3D (Sun) и
## AtmosphereLightingProfile, собирает AtmosphereLightingState и публикует
## его через сигнал lighting_changed.
##
## Границы ответственности (план §4.3/§6, v2 §3.2-3.3):
## - НЕ рисует небо, НЕ управляет облаками, НЕ создаёт источники света;
## - НЕ пишет в материалы (это делают экземпляры AtmosphereShaderBindingComponent);
## - событийный контракт: _process()/polling ОТСУТСТВУЮТ намеренно. publish()
##   вызывается владельцем изменения Sun (в проекте — SkyLightController после
##   каждого изменения углов/цвета/энергии Sun) и один раз в _ready.

signal lighting_changed(state: AtmosphereLightingState)

@export var sun_light: DirectionalLight3D
@export var profile: AtmosphereLightingProfile

## Этап 03 + 4.1.6 (план §3/§7.2, v2 §2.1/§5.2): строка «Окружение» пресета
## (palletes.html) — ЕДИНАЯ живая палитра света для всех потребителей:
## L3 «даль» = зенит среды И anti-solar зона вуали; L2 «середина» = переходная
## зона; L1 «у солнца/горизонта» = горизонт среды И solar зона. Второй
## независимой копии палитры не существует (v2 §5.2). Поставщики: владелец
## пресета (SkyEnvironmentController.apply_palette) и живые ручки панели.
## Поля профиля (tint/ambient-цвета) = FALLBACK-данные для сцен без владельца.
var _env_anti_solar: Color
var _env_transition: Color
var _env_solar: Color
var _has_environment_palette: bool = false

var _current_state: AtmosphereLightingState


func _ready() -> void:
	publish()


## Событийный вход владельца палитры (пресет применён / ручка панели):
## три цвета строки «Окружение». Публикует состояние (без polling).
func set_environment_palette(anti_solar: Color, transition: Color, solar: Color) -> void:
	_env_anti_solar = anti_solar
	_env_transition = transition
	_env_solar = solar
	_has_environment_palette = true
	publish()


## Симметричный сброс к fallback-данным профиля (например, отладочные сцены
## без пресета). Публикует состояние.
func clear_environment_palette() -> void:
	_has_environment_palette = false
	publish()


## Собрать и опубликовать состояние. Вызывается СОБЫТИЙНО (после изменения
## Sun или данных профиля), не покадрово.
func publish() -> void:
	if sun_light == null:
		push_error("AtmosphereLighting: Sun Light is not assigned.")
		return
	if profile == null:
		push_error("AtmosphereLighting: Profile is not assigned.")
		return

	var state := AtmosphereLightingState.new()

	# DirectionalLight3D направляет лучи вдоль локальной -Z; состояние несёт
	# направление НА источник (+Z). orthonormalized() — устойчивость к масштабу
	# и перекосу узла (поправка плана §5). Конвенция совпадает с basis.z узла
	# и sk_sun_dir (один источник направления, план §7.1).
	state.sun_direction = sun_light.global_basis.orthonormalized().z.normalized()

	state.sun_color = sun_light.light_color
	state.sun_energy = sun_light.light_energy * profile.direct_multiplier

	state.anti_solar_mu = profile.anti_solar_mu
	state.solar_mu = profile.solar_mu
	state.transition_position = profile.transition_position

	# Палитра среды и вуали (этап 03 + 4.1.6): приоритет — живые данные
	# владельца (пресет/панель), fallback — данные профиля (план §7.2: среда
	# одна; v2 §5.2: без второй копии палитры; чтение отрисованного Sky
	# запрещено §7.4 — передаются параметры). Одно трио обслуживает обоих
	# потребителей: зенит = anti_solar (L3 «даль»), горизонт = solar (L1).
	if _has_environment_palette:
		state.ambient_zenith_color = _env_anti_solar
		state.ambient_horizon_color = _env_solar
		state.anti_solar_color = _env_anti_solar
		state.transition_color = _env_transition
		state.solar_color = _env_solar
	else:
		state.ambient_zenith_color = profile.ambient_zenith_color
		state.ambient_horizon_color = profile.ambient_horizon_color
		state.anti_solar_color = profile.anti_solar_color
		state.transition_color = profile.transition_color
		state.solar_color = profile.solar_color
	state.ambient_strength = profile.ambient_strength

	_current_state = state
	lighting_changed.emit(_current_state)


func get_current_state() -> AtmosphereLightingState:
	return _current_state
