extends RefCounted
## CloudTextureLoader — загрузка 3D-шумов компонента Q7.32_SKYprav_3.1 (Godot 4.7).
##
## ПРИЧИНА СУЩЕСТВОВАНИЯ (проверено спайком B1): персистенция ImageTexture3D через
## ResourceSaver в Godot 4.7-stable сломана — create() не заполняет CPU-сторону
## (raw_images), .res сохраняет 264-байтную заглушку, загрузка даёт невалидную 1×1×1
## (ошибки движка: "raw_images.is_empty()", "!texture.is_valid()"). Поэтому текстуры
## поставляются сырыми .bin (R8-вокселы, порядок x + y·size + z·size²) и собираются
## ОДИН РАЗ при старте сцены/рига — ImageTexture3D.create(format, w, h, d, mipmaps,
## data: Array[Image]-срезы). ВНИМАНИЕ: в 4.7 create() принимает именно Array[Image]
## (срезы глубины), НЕ плоский PackedByteArray (устаревшие примеры молча дают
## uninitialized RID и белую текстуру).
##
## Требование §3.2 промта Q7.32 «не генерировать новые 3D-текстуры каждый кадр»
## выполнено: сборка из .bin — миллисекунды, один раз; генерация — офлайн-инструмент
## gen_noise3d.gd (seed фиксирован, результат побайтово воспроизводим).


## Читает сырые вокселы; при любой проблеме — пустой массив + push_error.
static func load_voxels(path: String, size: int) -> PackedByteArray:
	var expected := size * size * size
	if not FileAccess.file_exists(path):
		push_error("CloudTextureLoader: файл не найден: %s" % path)
		return PackedByteArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CloudTextureLoader: не открыть %s (ошибка %d)" % [path, FileAccess.get_open_error()])
		return PackedByteArray()
	var data := f.get_buffer(expected)
	f.close()
	if data.size() != expected:
		push_error("CloudTextureLoader: размер %s = %d, ожидалось %d" % [path, data.size(), expected])
		return PackedByteArray()
	return data


## Собирает ImageTexture3D из срезов Array[Image] (API Godot 4.7).
static func build_texture(data: PackedByteArray, size: int) -> ImageTexture3D:
	if data.size() != size * size * size:
		push_error("CloudTextureLoader: build_texture — некорректный размер данных (%d)" % data.size())
		return null
	var plane := size * size
	var slices: Array[Image] = []
	for z in range(size):
		slices.append(Image.create_from_data(size, size, false, Image.FORMAT_R8,
			data.slice(z * plane, (z + 1) * plane)))
	var tex := ImageTexture3D.new()
	var err: int = tex.create(Image.FORMAT_R8, size, size, size, false, slices)
	if err != OK:
		push_error("CloudTextureLoader: ImageTexture3D.create вернул %d" % err)
		return null
	return tex


## Полный путь: .bin → ImageTexture3D (или null).
static func load_texture(path: String, size: int) -> ImageTexture3D:
	return build_texture(load_voxels(path, size), size)


## Заглушка 8³ среднего серого — чтобы сцена оставалась работоспособной и видимой,
## если .bin отсутствует (с явным push_error выше по потоку).
static func placeholder_texture() -> ImageTexture3D:
	var n := 8
	var slices: Array[Image] = []
	for _z in range(n):
		var sb := PackedByteArray()
		sb.resize(n * n)
		sb.fill(128)
		slices.append(Image.create_from_data(n, n, false, Image.FORMAT_R8, sb))
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_R8, n, n, n, false, slices)
	return tex
