extends Node3D
## SkyLabCards — v0.7 (фикс шага 7 по ревью): карточки ЖИВУТ В МИРЕ.
##
## Архитектура после ревью («карточки прилеплены на камеру»):
##   - карточки = MeshInstance3D (QuadMesh) в мировых координатах, Y-билборд (rotation.y
##     к камере каждый кадр) → полный параллакс при движении/повороте камеры;
##   - frustum-якоря (ax, ay, scale) — это ИНСТРУМЕНТ РАЗМЕЩЕНИЯ: «навёл — приколол»:
##     мировая позиция и размер вычисляются из луча камеры в момент изменения ручки
##     или по кнопке «Переякорить»; после этого карточка мировая и не следует за камерой;
##   - стиккер-чувство убрано в шейдере: дистанционная дымка haze + base_fade (низ тонет
##     в море облаков); depth_draw_never + depth test → земля корректно перекрывает;
##   - порядок слоёв: transparent-пасс после неба = L4 поверх реймарчинга L3; рамки
##     ставятся ЗА зону far_curtain (12–24 км) и тонут в дымке = дальние массы, hero
##     ближе (9 км) и crisp — как в ref5.
##
## Маски: утверждённые паки v2. Цвета состояний и солнце пишет SkyLabPanel.

const CARD_DEFS := [
	{
		"name": "gen_simple",
		"tex": "res://Q7.32_SKYprav_3.1/cards/T_CARD_GEN_SIMPLE_01_mask.png",
		"ax": 0.0, "ay": 0.0, "scale": 0.55, "dist": 9000.0,
		"flip": false, "visible": true,
		"haze_start": 14000.0, "haze_end": 34000.0,
		"life_amp": 0.007,
	},
]

const RIM_EXP := 3.0

@export var camera_path: NodePath = ^"../Camera3D"

var _cam: Camera3D = null
var _cards: Array = []
var _sun_dir := Vector3(0.0, 0.0, -1.0)
var _sun_elev := 0.0


func _ready() -> void:
	_cam = get_node_or_null(camera_path) as Camera3D
	if _cam == null:
		push_error("[SkyLabCards] камера не найдена: %s" % str(camera_path))
		return
	for def in CARD_DEFS:
		var mi := MeshInstance3D.new()
		mi.name = "Card_" + str(def["name"])
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		mi.mesh = q
		var mat := ShaderMaterial.new()
		mat.shader = load("res://Q7.32_SKYprav_3.1/skylab_card.gdshader")
		mat.set_shader_parameter("card_mask", load(str(def["tex"])))
		mat.set_shader_parameter("flip", 1.0 if bool(def["flip"]) else 0.0)
		mat.set_shader_parameter("haze_start", float(def["haze_start"]))
		mat.set_shader_parameter("haze_end", float(def["haze_end"]))
		if def.has("life_amp"):
			mat.set_shader_parameter("life_amp", float(def["life_amp"]))
		if def.has("form_contrast"):
			mat.set_shader_parameter("form_contrast", float(def["form_contrast"]))
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = bool(def["visible"])
		add_child(mi)
		_cards.append({"node": mi, "mat": mat, "def": def.duplicate(),
				"ax": float(def["ax"]), "ay": float(def["ay"]),
				"scale": float(def["scale"]), "visible": bool(def["visible"])})
		_pin_to_anchor(_cards.size() - 1)
	print("[SkyLabCards] v0.5.2: %d карточек(и), мировые билборды с параллаксом" % _cards.size())


func card_count() -> int:
	return _cards.size()


func card_name(i: int) -> String:
	return str(_cards[i]["def"]["name"])


func get_card_param(i: int, key: String) -> float:
	if i < 0 or i >= _cards.size():
		return 0.0
	return float(_cards[i][key])


## Смена якоря/масштаба = переприкол в мир из ТЕКУЩЕЙ камеры (инструмент размещения).
func set_card_param(i: int, key: String, v: float) -> void:
	if i < 0 or i >= _cards.size():
		return
	_cards[i][key] = v
	_pin_to_anchor(i)


func set_card_visible(i: int, on: bool) -> void:
	if i < 0 or i >= _cards.size():
		return
	_cards[i]["visible"] = on
	_cards[i]["node"].visible = on


## Переприколоть все карточки из текущей камеры (кнопка в панели).
func reanchor_all() -> void:
	for i in range(_cards.size()):
		_pin_to_anchor(i)


func set_state(cols: Dictionary) -> void:
	for c in _cards:
		var m: ShaderMaterial = c["mat"]
		m.set_shader_parameter("st_shadow", cols["shadow"])
		m.set_shader_parameter("st_lit", cols["lit"])
		m.set_shader_parameter("st_rim", cols["rim"])
		m.set_shader_parameter("st_under", cols["horizon"])
		m.set_shader_parameter("st_zenith", cols["zenith"])
		m.set_shader_parameter("haze_col", cols["horizon"].lerp(Vector3(2, 2, 2), 0.45))
		for k in ["ramp0", "ramp1", "ramp2", "ramp3", "ramp4"]:
			if cols.has(k):
				m.set_shader_parameter("st_" + k, cols[k])


func set_sun(sun_dir: Vector3, elev_deg: float) -> void:
	_sun_dir = sun_dir
	_sun_elev = elev_deg


## NDC-якорь → луч камеры → мировая позиция на дистанции d; размер из угловой высоты.
func _pin_to_anchor(i: int) -> void:
	if _cam == null or i < 0 or i >= _cards.size():
		return
	var c: Dictionary = _cards[i]
	var vp := _cam.get_viewport()
	if vp == null:
		return
	var vs := vp.get_visible_rect().size
	if vs.x < 4.0 or vs.y < 4.0:
		return
	var px := Vector2((float(c["ax"]) * 0.5 + 0.5) * vs.x, (1.0 - (float(c["ay"]) * 0.5 + 0.5)) * vs.y)
	var ray := _cam.project_ray_normal(px)
	var d: float = float(c["def"]["dist"])
	var mi: MeshInstance3D = c["node"]
	mi.global_position = _cam.global_position + ray * d
	var world_h := 2.0 * d * tan(deg_to_rad(_cam.fov) * 0.5) * float(c["scale"])
	var tex: Texture2D = c["mat"].get_shader_parameter("card_mask")
	var ta := 1.0
	if tex != null:
		var ts := tex.get_size()
		ta = ts.x / maxf(ts.y, 1.0)
	var sx := world_h * ta
	if bool(c["def"]["flip"]):
		sx = -sx
	mi.scale = Vector3(sx, world_h, 1.0)


func _process(_delta: float) -> void:
	if _cam == null:
		return
	var cam_pos := _cam.global_position
	var sun_up := clampf(_sun_elev / 30.0 + 0.5, 0.0, 1.0)
	var below := 1.0 - smoothstep(-2.0, 2.0, _sun_elev)
	for c in _cards:
		var mi: MeshInstance3D = c["node"]
		# Y-билборд: лицом к камере по горизонтали, вертикаль держим
		var to_cam := cam_pos - mi.global_position
		mi.rotation.y = atan2(to_cam.x, to_cam.z)
		var m: ShaderMaterial = c["mat"]
		m.set_shader_parameter("sun_dir_world", _sun_dir)
		m.set_shader_parameter("sun_up", sun_up)
		m.set_shader_parameter("sun_below", below)
		# направление на солнце в UV-плоскости карточки (учёт зеркала flip)
		var sd := _sun_dir.normalized()
		var sx := sd.dot(_cam.global_transform.basis.x)
		var sy := sd.dot(_cam.global_transform.basis.y)
		if bool(c["def"]["flip"]):
			sx = -sx
		m.set_shader_parameter("sun_screen", Vector2(sx, sy))
