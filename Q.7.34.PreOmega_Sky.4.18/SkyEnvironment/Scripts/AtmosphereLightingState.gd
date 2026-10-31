extends RefCounted
class_name AtmosphereLightingState
## Q.7.34.PreOmega_Sky.4.1.1 (план света, этап 01) — контейнер актуальных данных
## освещения. Ничего не рассчитывает и не знает о шейдерах (план §4.2).
## v2 §3.1: три категории в ОДНОМ состоянии с явной семантикой каждого поля.
## После публикации не мутируется: AtmosphereLightingComponent создаёт НОВЫЙ
## контейнер на каждый publish() (подписчики могут держать ссылку безопасно).

## Направление ИЗ сцены К источнику света (Sun). Совпадает с basis.z узла
## DirectionalLight3D (конвенция sk_sun_dir проекта: лучи идут вдоль -Z).
var sun_direction: Vector3 = Vector3.UP

## Direct Lighting: цвет и интенсивность Sun (интенсивность уже умножена на
## AtmosphereLightingProfile.direct_multiplier компонентом — потребитель не множит).
var sun_color: Color = Color.WHITE
var sun_energy: float = 1.0

## Veil Artistic Palette: три цвета угловых зон + границы переходов по mu.
var anti_solar_color: Color
var transition_color: Color
var solar_color: Color

var anti_solar_mu: float
var solar_mu: float
var transition_position: float

## Ambient Environment: цветовая среда Sky Gradient.
var ambient_zenith_color: Color
var ambient_horizon_color: Color
var ambient_strength: float
