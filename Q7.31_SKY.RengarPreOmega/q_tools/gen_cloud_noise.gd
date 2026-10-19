extends SceneTree
## gen_cloud_noise (Q7.29) — детерминированная генерация двух БЕСШОВНЫХ
## grayscale-текстур шума для облаков омега-неба (1024×1024).
##
## МЕТОД (задокументирован честно): периодический value-noise FBM на решётке
## с ЗАВЁРНУТЫМ периодом (ix mod P) — бесшовность по обеим осям математическая,
## а не пост-обработка; сидированный hash-массив решётки → байт-в-байт
## воспроизводимо. Почему не FastNoiseLite.seamless: в Godot 4.7 у FastNoiseLite
## НЕТ свойства seamless (проверено рантайм-ошибкой 18.10.2026), бесшовность
## живёт в NoiseTexture2D, чья генерация в headless-рантайме ненадёжна;
## почему не «подменить нерелевантной картинкой» — шум и есть содержимое.
##
## Запуск: Godot --headless --path <версия> --script res://q_tools/gen_cloud_noise.gd
const SIZE := 1024
const OUT_LARGE := "res://Assets/sky/textures/cloud_noise_large.png"
const OUT_DETAIL := "res://Assets/sky/textures/cloud_noise_detail.png"


## Детерминированный hash клетки в [0,1): классика sin-dot, стабильна между
## запусками (одинаковая математика, без RNG-состояний).
func _cell_hash(ix: int, iy: int, seed_value: int) -> float:
	var h: float = sin(float(ix) * 127.1 + float(iy) * 311.7 + float(seed_value) * 74.7) * 43758.5453
	return h - floor(h)


## Периодический value-noise: решётка периода P завёрнута по mod P → тайл.
func _periodic_value_noise(u: float, v: float, p: int, seed_value: int) -> float:
	var x: float = u * float(p)
	var y: float = v * float(p)
	var ix: int = int(floor(x))
	var iy: int = int(floor(y))
	var fx: float = x - floor(x)
	var fy: float = y - floor(y)
	# Quintic-сглаживание (нет видимых изломов решётки)
	var sx: float = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
	var sy: float = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0)
	var ix0: int = ix % p
	var iy0: int = iy % p
	var ix1: int = (ix + 1) % p
	var iy1: int = (iy + 1) % p
	var n00: float = _cell_hash(ix0, iy0, seed_value)
	var n10: float = _cell_hash(ix1, iy0, seed_value)
	var n01: float = _cell_hash(ix0, iy1, seed_value)
	var n11: float = _cell_hash(ix1, iy1, seed_value)
	var a: float = lerp(n00, n10, sx)
	var b: float = lerp(n01, n11, sx)
	return lerp(a, b, sy)


func _fbm(u: float, v: float, base_period: int, octaves: int, seed_value: int) -> float:
	var sum: float = 0.0
	var amp: float = 0.5
	var norm: float = 0.0
	var p := base_period
	for o in octaves:
		sum += amp * _periodic_value_noise(u, v, p, seed_value + o * 101)
		norm += amp
		amp *= 0.5
		p *= 2   # период удваивается — обе оси остаются периодичными
	return sum / norm


func _generate(seed_value: int, base_period: int, octaves: int, contrast: float, out_path: String) -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var t0 := Time.get_ticks_msec()
	for y in SIZE:
		var v: float = float(y) / float(SIZE)
		for x in SIZE:
			var u: float = float(x) / float(SIZE)
			var n: float = _fbm(u, v, base_period, octaves, seed_value)
			# Контраст вокруг середины: формы облаков читаемее, средний тон 0.5
			n = clampf(0.5 + (n - 0.5) * contrast, 0.0, 1.0)
			var b: int = int(round(n * 255.0))
			img.set_pixel(x, y, Color8(b, b, b))
	var err := img.save_png(out_path)
	print("GEN_CLOUD_NOISE %s: %dx%d err=%d seed=%d period=%d oct=%d за %d мс" % [
		out_path, SIZE, SIZE, err, seed_value, base_period, octaves,
		Time.get_ticks_msec() - t0])


func _initialize() -> void:
	# Крупные массы: низкий базовый период (4 клетки на тайл), 4 октавы.
	_generate(20261018, 4, 4, 1.35, OUT_LARGE)
	# Деталь: выше базовая частота (12 клеток), 5 октав, мягче контраст.
	_generate(20261019, 12, 5, 1.15, OUT_DETAIL)
	quit(0)
