@tool
extends Node3D
class_name BushGrassComponent
## Декоративная трава — МАРКЕР ЗОНЫ КУСТА (Q7.22, ревизии Q7.23/Q7.25).
## Задание заказчика (17.10.2026): «сделать траву — маркером куста, т.е. она
## должна быть по всей площади куста» + кайма снаружи («мягкий переход» — идея
## заказчика, +1 балл). Две зоны раскладки:
##   ЗАПОЛНЕНИЕ (fill) — равномерный случайный посев по всей ТЕРРИТОРИИ куста
##     (квадрат fill_half_size — замер формы куста в сцене): трава ЧИТАЕТСЯ как
##     зона стелса; текстура-заглушка BushMarker удалена из сцены (вердикт).
##   КАЙМА (fringe) — кольцо сразу за границей территории (ring_radius_min =
##     край заполнения → ring_radius_max): мягкий переход к обычной зоне.
##
## Q7.25 — МНОГОМОДЕЛЬНОСТЬ (ответ на вопрос заказчика «сможем рандомизировать
## заполнение, если добавлю ещё 2 модели пучка?» — ДА): grass_scene_paths —
## МАССАВ путей (данные, inspector); каждый пучок получает случайную модель из
## массива (сидированный RNG — раскладка воспроизводима). Один MultiMesh держит
## ОДИН меш, поэтому на каждую модель создаётся свой потомок MultiMeshInstance3D
## («Tufts_N») — draw call'ов = число моделей (3 модели = 3 draw call'а — всё
## ещё копейки; консультация CONSULT_poly_budget §3Б).
##
## ЧИСТО ДЕКОРАЦИЯ: без коллизий, без поведения, НЕ в группе "bush" — зона
## стелса (Area3D куста) и геймплей не меняются.
##
## ПОЧЕМУ ГЕНЕРАЦИЯ В КОДЕ (честная родословная решения, замеры 17.10.2026):
## в headless-среде разработки (dummy RenderingServer) данные MultiMesh живут
## только на стороне сервера рендеринга: CPU-буфер пуст (замер: buffer.size()=0),
## set/get_instance_transform уходит в identity БЕЗ ошибок, сохранение
## (.tres/.res/sub_resource) записывает пустоту. На реальной машине трансформы
## хранит сервер рендеринга. Кодовая генерация работает в обоих окружениях
## гарантированно, детерминирована (сид) и настраивается данными (экспорты).
## Раскладка — ЧИСТАЯ МАТЕМАТИКА (_compute_placement, без RenderingServer):
## верифицируема headless; на GPU её отдаёт стандартный set_instance_transform.
##
## РОДОСЛОВНАЯ ЧИСЕЛ (замеры «линейкой» 17.10.2026; сводка — changes.md):
## - trava1_500.glb: 504 треугольника, 1 материал, 0 костей, AABB
##   0.554×0.951×0.388 м, пивот в ЦЕНТРЕ пучка (min.y = −0.476);
## - смещение основания до пивота НЕ захардкожено — измеряется из AABB КАЖДОЙ
##   модели при каждой пересборке (линейка встроена в код);
## - территория куста: BoxShape3D 6×6×6 → полуэкстента 3.0 (замер сцены);
## - узел в сцене стоит в ЦЕНТРЕ КУСТА на уровне земли: (0.073, 0.5, −5.187) —
##   замер сцены: Bush (0, 0.51, −5) + CollisionShape3D offset (0.073, ·, −0.187);
##   земля: Ground BoxMesh 40×1×40, центр y=0 → верх y=+0.5 (спавн игрока
##   подтверждает: низ его колбокса 0.5).
##
## БЮДЖЕТ («без фанатизма»): куст (72+32) + разброс 40 = 144 пучка × ~500 тр.
## ≈ 72к тр. ≈ 7% кадрового бюджета 1 млн (консультация §4); плотность
## заполнения куста 2 пучка/м² (36 м²), каймы ≈ 1.1 пучка/м², разброса
## 0.025 пучка/м² (1600 м²) — «немного», как просил заказчик.
## Ручки ниже — данные (inspector); дефолты = поставка Q7.25.

## Пучков внутри территории куста (заполнение-маркер).
@export_range(0, 512, 1) var fill_count := 72:
	set(value):
		fill_count = value
		_rebuild_safe()
## Полуэкстента территории куста, м. Родословная: BoxShape3D куста 6×6×6 / 2
## (замер сцены). Форма квадратная (равномерный посев по квадрату территории).
@export_range(0.5, 20.0, 0.1) var fill_half_size := 3.0:
	set(value):
		fill_half_size = value
		_rebuild_safe()
## Пучков в кайме за территорией (мягкий переход — вердикт заказчика).
@export_range(0, 512, 1) var fringe_count := 32:
	set(value):
		fringe_count = value
		_rebuild_safe()
## Внутренний радиус каймы, м = край заполнения (3.0): кайма начинается ОТ
## границы территории, не залезая внутрь (там заполнение).
@export_range(0.5, 20.0, 0.1) var ring_radius_min := 3.0:
	set(value):
		ring_radius_min = value
		_rebuild_safe()
## Внешний радиус каймы, м = 3.0 + 1.2: полоса перехода, не поле.
@export_range(0.5, 25.0, 0.1) var ring_radius_max := 4.2:
	set(value):
		ring_radius_max = value
		_rebuild_safe()
## Пучков РЕДКОГО РАЗБРОСА по всей локации (Q7.27, вердикт заказчика: «по всей
## локации можно немного раскидать эти пучки в случайном порядке (пусть их
## будет немного)»). 0 = разброса нет (куст-маркер не меняется).
@export_range(0, 512, 1) var scatter_count := 0:
	set(value):
		scatter_count = value
		_rebuild_safe()
## Полуэкстента квадрата разброса, м. Родословная: Ground BoxMesh 40×40
## (замер сцены) / 2 = 20 — вся рабочая площадка.
@export_range(1.0, 60.0, 0.5) var scatter_half_size := 20.0:
	set(value):
		scatter_half_size = value
		_rebuild_safe()
## Зазор вокруг объёма куста, куда разброс НЕ сеет (м): куст остаётся читаемым
## «сосредоточием травы» (вердикт), разброс не размывает его силуэт.
## Родословная: полкорпуса существа 0.5 (замер сцены BoxShape3D_xh4up).
@export_range(0.0, 5.0, 0.1) var scatter_bush_clearance := 0.5:
	set(value):
		scatter_bush_clearance = value
		_rebuild_safe()
## Сид раскладки (дата постановки задачи) — та же раскладка при каждом запуске.
@export var layout_seed := 20261017:
	set(value):
		layout_seed = value
		_rebuild_safe()
## Разброс масштаба ±20% — ряд не выглядит витринным (консультация §3Б).
@export_range(0.1, 2.0, 0.05) var scale_min := 0.8:
	set(value):
		scale_min = value
		_rebuild_safe()
@export_range(0.1, 3.0, 0.05) var scale_max := 1.2:
	set(value):
		scale_max = value
		_rebuild_safe()
## МОДЕЛИ пучков (PackedScene с MeshInstance3D внутри) — массив = данные:
## заказчик добавляет новые модели травы ПРОСТО ДОПИСЫВАЯ пути (вердикт-ответ
## Q7.25: рандомизация заполнения по моделям — из коробки).
@export var grass_scene_paths: Array[String] = ["res://Assets/jungle/trava1_500.glb"]:
	set(value):
		grass_scene_paths = value
		_rebuild_safe()


func _ready() -> void:
	_rebuild_safe()


## Пересборка с защитой: сеттеры экспорт-ручек срабатывают ДО входа в дерево
## при загрузке сцены — там собирать нечего (соберёт _ready).
func _rebuild_safe() -> void:
	if is_inside_tree():
		_rebuild()


func _rebuild() -> void:
	# Чистка прежних потомков-пучков (идемпотентная пересборка в редакторе/игре).
	for child in get_children():
		if child is MultiMeshInstance3D and String(child.name).begins_with("Tufts"):
			remove_child(child)
			child.free()
	# Загрузка всех моделей: {mesh, base_drop} на путь; битые пути — пропуск
	# с предупреждением (раскладка строится на загруженных).
	var models: Array = []
	for path in grass_scene_paths:
		var data := _load_grass(path)
		if not data.is_empty():
			models.append(data)
	if models.is_empty():
		push_warning("BushGrassComponent: ни одна модель не загружена — трава не построена")
		return
	var drops: Array = []
	for m in models:
		drops.append(float(m["base_drop"]))
	var placement := _compute_placement(drops)
	# Корзины по моделям (один MultiMesh = один меш = один draw call на модель).
	var buckets := {}
	for item in placement:
		var idx: int = item["model"]
		if not buckets.has(idx):
			buckets[idx] = []
		buckets[idx].append(item["xform"])
	var indices := buckets.keys()
	indices.sort() # стабильные имена потомков
	for idx in indices:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Tufts_%d" % idx
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = models[idx]["mesh"]
		var xforms: Array = buckets[idx]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		mmi.multimesh = mm
		add_child(mmi)
		if Engine.is_editor_hint():
			mmi.owner = get_tree().edited_scene_root


## Загрузка модели пучка: {mesh: Mesh, base_drop: float} или {} (с предупреждением).
## base_drop — расстояние от пивота модели до её основания, ЗАМЕР из AABB
## (с учётом трансформа MeshInstance3D внутри glb) — магических чисел нет,
## у каждой модели — СВОЙ замер.
func _load_grass(path: String) -> Dictionary:
	# Защита от ТЯЖЁЛОГО синхронного импорта: неимпортированный glb (нет
	# .import/кэша) load() распечатывает прямо в поток — 4K-текстуры trava2
	# роняли/вешали headless-среду (замер 17.10.2026: OOM при 1 ГБ RAM).
	# exists() = «ассет импортирован» — иначе пропуск с предупреждением
	# (на машине заказчика после импорта редактором exists() = true).
	# exists() НЕ годится: для файла без импорт-кэша она true, а load() затем
	# тянет синхронный импорт 4K-текстур (вешает headless — замер 17.10.2026).
	# Сайдкар .import = «ассет в импорт-пайплайне»: в редакторе/игре заказчика
	# он есть всегда; в песочнице для trava2 (4K, OOM при 1 ГБ RAM) — нет.
	if not FileAccess.file_exists(path + ".import"):
		push_warning("BushGrassComponent: %s без .import в этом окружении — пропущен" % path)
		return {}
	var scn := load(path) as PackedScene
	if scn == null:
		push_warning("BushGrassComponent: модель не загружена (%s) — пропущена" % path)
		return {}
	var inst := scn.instantiate()
	var mis := inst.find_children("", "MeshInstance3D", true, false)
	if mis.is_empty():
		push_warning("BushGrassComponent: в модели нет MeshInstance3D (%s) — пропущена" % path)
		inst.free()
		return {}
	var mi := mis[0] as MeshInstance3D
	var mesh := mi.mesh
	if mesh == null:
		push_warning("BushGrassComponent: у MeshInstance3D нет меша (%s) — пропущена" % path)
		inst.free()
		return {}
	var local_aabb: AABB = mi.transform * mesh.get_aabb()
	var base_drop := -local_aabb.position.y
	inst.free()
	return {"mesh": mesh, "base_drop": base_drop}


## ЧИСТАЯ математика раскладки (без RenderingServer — верифицируемо headless):
## ЗОНА 1 (fill): равномерный случайный посев по квадрату территории куста
## (x, z ∈ [−fill_half_size, +fill_half_size] от нуля узла — узел в центре куста);
## ЗОНА 2 (fringe): кольцо [ring_radius_min, ring_radius_max], выборка
## равномерная по ПЛОЩАДИ: r = sqrt(r_in² + (r_out²−r_in²)·u).
## ПОРЯДОК ВЫЗОВОВ RNG НА ПУЧОК ФИКСИРОВАН (позиция → модель → масштаб →
## поворот) — детерминизм раскладки при одном сиде гарантирован.
## Возврат: Array of {xform: Transform3D, model: int}; основание пучка на земле
## узла при любом масштабе и модели: y = base_drop[модель] · s.
func _compute_placement(drops: Array) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var n_models := drops.size()
	var s_min := minf(scale_min, scale_max)
	var s_max := maxf(scale_min, scale_max)
	var h := maxf(0.1, fill_half_size)
	for i in fill_count:
		var pos := Vector3(rng.randf_range(-h, h), 0.0, rng.randf_range(-h, h))
		out.append(_tuft(rng, pos, drops, n_models, s_min, s_max))
	var r_in := minf(ring_radius_min, ring_radius_max)
	var r_out := maxf(ring_radius_min, ring_radius_max)
	for i in fringe_count:
		var r: float = sqrt(r_in * r_in + (r_out * r_out - r_in * r_in) * rng.randf())
		var a := rng.randf() * TAU
		out.append(_tuft(rng, Vector3(r * cos(a), 0.0, r * sin(a)), drops, n_models, s_min, s_max))
	# ЗОНА 3 (scatter): редкий разброс по квадрату локации; rejection sampling —
	# кандидат отбрасывается, если попал в объём куста + clearance (кусты
	# измеряются из сцены, группа "bush" — данные, не хардкод); до 8 попыток на
	# пучок (детерминировано сидом), иначе сеем последнего кандидата.
	if scatter_count > 0:
		var bushes := _measure_bushes()
		var hs := maxf(0.5, scatter_half_size)
		for i in scatter_count:
			var pos := Vector3.ZERO
			for attempt in 8:
				pos = Vector3(rng.randf_range(-hs, hs), 0.0, rng.randf_range(-hs, hs))
				if not _inside_any_bush(pos, bushes):
					break
			out.append(_tuft(rng, pos, drops, n_models, s_min, s_max))
	return out


## Объёмы кустов сцены (горизонтальные полуэкстенты/радиусы) — для разброса.
func _measure_bushes() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	for node in get_tree().get_nodes_in_group("bush"):
		var area := node as Area3D
		if area == null:
			continue
		var center := area.global_position
		var half := Vector2(1.5, 1.5)
		for child in area.get_children():
			var cs := child as CollisionShape3D
			if cs == null or cs.shape == null:
				continue
			center = cs.global_position
			var sc := cs.global_transform.basis.get_scale().x
			if cs.shape is BoxShape3D:
				var sz: Vector3 = (cs.shape as BoxShape3D).size * 0.5 * sc
				half = Vector2(sz.x, sz.z)
			elif cs.shape is SphereShape3D:
				var rr: float = (cs.shape as SphereShape3D).radius * sc
				half = Vector2(rr, rr)
		out.append({"center": Vector2(center.x, center.z), "half": half})
	return out


func _inside_any_bush(pos: Vector3, bushes: Array) -> bool:
	var cl := scatter_bush_clearance
	for b in bushes:
		var c: Vector2 = b["center"]
		var h: Vector2 = b["half"]
		if absf(pos.x - c.x) <= h.x + cl and absf(pos.z - c.y) <= h.y + cl:
			return true
	return false


## Один пучок: модель/масштаб/поворот из сидированного RNG (порядок вызовов —
## см. _compute_placement), основание на земле (y узла) по замеру МОДЕЛИ.
func _tuft(rng: RandomNumberGenerator, ground_pos: Vector3, drops: Array, n_models: int, s_min: float, s_max: float) -> Dictionary:
	var m := rng.randi_range(0, n_models - 1)
	var s := rng.randf_range(s_min, s_max)
	var yaw := rng.randf() * TAU
	var pos := Vector3(ground_pos.x, float(drops[m]) * s, ground_pos.z)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
	return {"xform": Transform3D(basis, pos), "model": m}
