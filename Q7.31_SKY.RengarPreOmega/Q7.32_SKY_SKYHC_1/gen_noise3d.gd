extends SceneTree
## gen_noise3d.gd — офлайн-генератор 3D-шумов компонента Q7.32_SKY_SKYHC_1 (Godot 4.7).
##
## Выдаёт ДВА файла сырых вокселей (R8, порядок: x + y*size + z*size*size):
##   res://Q7.32_SKY_SKYHC_1/noise_pw_128.bin      — Perlin-Worley 128³ (base shape)
##   res://Q7.32_SKY_SKYHC_1/noise_worley_32.bin   — Worley F1 (инверт) 32³ (деталь/выступы)
##
## СВОЙСТВА (по §3.2 промта Q7.32):
##   - детерминированность: только целочисленный хэш решётки, никаких RNG-состояний;
##     повторный запуск даёт побайтово идентичные файлы (проверено sha256);
##   - seed зафиксирован константами ниже;
##   - бесшовность: периодическая решётка (mod cells) у Perlin и у Worley —
##     циклический семплинг непрерывен по всем трём осям (self-check печатается);
##   - однократная офлайн-генерация: в рантайме текстуры собираются из .bin за
##     миллисекунды (ImageTexture3D.create), НЕ генерируются каждый кадр.
##
## Запуск:  godot --headless --path <проект> --script res://Q7.32_SKY_SKYHC_1/gen_noise3d.gd
## Время: ~2-4 мин на PW 128³ (naive GDScript), ~2 c на Worley 32³.
##
## ВНИМАНИЕ (Godot 4.7): ImageTexture3D.create() принимает Array[Image] (срезы),
## а ResourceSaver НЕ сохраняет данные ImageTexture3D (raw_images пуст) — поэтому
## формат поставки .bin + рантайм-сборка (CloudTextureLoader.gd).

const PW_SIZE := 128
const PW_CELLS := 16        # период решётки Perlin (features ≈ PW_SIZE/PW_CELLS = 8 вокселей)
const PW_SEED := 1337
const WO_SIZE := 32
const WO_CELLS := 8         # ячеек Worley на период (features ≈ 4 вокселя)
const WO_SEED := 777
const OUT_DIR := "res://Q7.32_SKY_SKYHC_1/"


func ihash(ix: int, iy: int, iz: int, seed_v: int) -> int:
	var qx: int = (ix + 32768) & 0xFFFFFFFF
	var qy: int = (iy + 32768) & 0xFFFFFFFF
	var qz: int = (iz + 32768) & 0xFFFFFFFF
	var h: int = (qx * 374761393 + qy * 668265263 + qz * 2147483647 + seed_v * 144665) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return (h ^ (h >> 16)) & 0xFFFFFFFF


func hfloat(ix: int, iy: int, iz: int, seed_v: int) -> float:
	return float(ihash(ix, iy, iz, seed_v)) / 4294967295.0


func grad_dot(ix: int, iy: int, iz: int, fx: float, fy: float, fz: float, n: int, seed_v: int) -> float:
	var x: int = ((ix % n) + n) % n
	var y: int = ((iy % n) + n) % n
	var z: int = ((iz % n) + n) % n
	var h: int = ihash(x, y, z, seed_v) & 15
	var u: float = fx if h < 8 else fy
	var v: float = fy if h < 4 else (fx if (h == 12 or h == 14) else fz)
	var a: float = u if (h & 1) == 0 else -u
	var b: float = v if (h & 2) == 0 else -v
	return a + b


func fade(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


func perlin_tile(px: float, py: float, pz: float, n: int, seed_v: int) -> float:
	var ix: int = int(floorf(px))
	var iy: int = int(floorf(py))
	var iz: int = int(floorf(pz))
	var fx: float = px - float(ix)
	var fy: float = py - float(iy)
	var fz: float = pz - float(iz)
	var u: float = fade(fx)
	var v: float = fade(fy)
	var w: float = fade(fz)
	var c000: float = grad_dot(ix, iy, iz, fx, fy, fz, n, seed_v)
	var c100: float = grad_dot(ix + 1, iy, iz, fx - 1.0, fy, fz, n, seed_v)
	var c010: float = grad_dot(ix, iy + 1, iz, fx, fy - 1.0, fz, n, seed_v)
	var c110: float = grad_dot(ix + 1, iy + 1, iz, fx - 1.0, fy - 1.0, fz, n, seed_v)
	var c001: float = grad_dot(ix, iy, iz + 1, fx, fy, fz - 1.0, n, seed_v)
	var c101: float = grad_dot(ix + 1, iy, iz + 1, fx - 1.0, fy, fz - 1.0, n, seed_v)
	var c011: float = grad_dot(ix, iy + 1, iz + 1, fx, fy - 1.0, fz - 1.0, n, seed_v)
	var c111: float = grad_dot(ix + 1, iy + 1, iz + 1, fx - 1.0, fy - 1.0, fz - 1.0, n, seed_v)
	var x00: float = lerpf(c000, c100, u)
	var x10: float = lerpf(c010, c110, u)
	var x01: float = lerpf(c001, c101, u)
	var x11: float = lerpf(c011, c111, u)
	return lerpf(lerpf(x00, x10, v), lerpf(x01, x11, v), w)


## Worley F1 с предрассчитанными jitter-точками (кэш cells³) — периодический.
func worley_field(size: int, cells: int, seed_v: int, invert: bool) -> PackedByteArray:
	var pts := PackedVector3Array()
	pts.resize(cells * cells * cells)
	for cz in range(cells):
		for cy in range(cells):
			for cx in range(cells):
				var jx: float = hfloat(cx, cy, cz, seed_v + 101)
				var jy: float = hfloat(cx, cy, cz, seed_v + 202)
				var jz: float = hfloat(cx, cy, cz, seed_v + 303)
				pts[cz * cells * cells + cy * cells + cx] = Vector3(jx, jy, jz)
	var data := PackedByteArray()
	data.resize(size * size * size)
	var scale_f: float = float(cells) / float(size)
	for z in range(size):
		var pz: float = float(z) * scale_f
		var iz: int = int(floorf(pz))
		var fz: float = pz - float(iz)
		for y in range(size):
			var py: float = float(y) * scale_f
			var iy: int = int(floorf(py))
			var fy: float = py - float(iy)
			var row_base: int = z * size * size + y * size
			for x in range(size):
				var px: float = float(x) * scale_f
				var ix: int = int(floorf(px))
				var fx: float = px - float(ix)
				var best := 1e9
				for dz in range(-1, 2):
					var wz: int = ((iz + dz) % cells + cells) % cells
					var oz: float = float(iz + dz)
					for dy in range(-1, 2):
						var wy: int = ((iy + dy) % cells + cells) % cells
						var oy: float = float(iy + dy)
						for dx in range(-1, 2):
							var wx: int = ((ix + dx) % cells + cells) % cells
							var pt: Vector3 = pts[wz * cells * cells + wy * cells + wx]
							var ddx: float = float(ix + dx) + pt.x - px
							var ddy: float = oy + pt.y - py
							var ddz: float = oz + pt.z - pz
							var d2: float = ddx * ddx + ddy * ddy + ddz * ddz
							if d2 < best:
								best = d2
				var f1: float = clampf(sqrt(best) / 1.2, 0.0, 1.0)
				var val: float = (1.0 - f1) if invert else f1
				data[row_base + x] = int(clampf(val, 0.0, 1.0) * 255.0)
	return data


func perlin_worley_field(size: int, cells: int, seed_v: int, worley_pts: PackedVector3Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(size * size * size)
	var scale_f: float = float(cells) / float(size)
	for z in range(size):
		var pz: float = float(z) * scale_f
		for y in range(size):
			var py: float = float(y) * scale_f
			var row_base: int = z * size * size + y * size
			for x in range(size):
				var px: float = float(x) * scale_f
				var per: float = perlin_tile(px, py, pz, cells, seed_v) * 0.5 + 0.5
				var wor: float = worley_at(px, py, pz, cells, worley_pts)
				var pw: float = clampf((per - wor) / maxf(1.0 - wor, 1e-4), 0.0, 1.0)
				data[row_base + x] = int(clampf(pw, 0.0, 1.0) * 255.0)
	return data


func worley_at(px: float, py: float, pz: float, cells: int, pts: PackedVector3Array) -> float:
	var ix: int = int(floorf(px))
	var iy: int = int(floorf(py))
	var iz: int = int(floorf(pz))
	var best := 1e9
	for dz in range(-1, 2):
		var wz: int = ((iz + dz) % cells + cells) % cells
		var oz: float = float(iz + dz)
		for dy in range(-1, 2):
			var wy: int = ((iy + dy) % cells + cells) % cells
			var oy: float = float(iy + dy)
			for dx in range(-1, 2):
				var wx: int = ((ix + dx) % cells + cells) % cells
				var pt: Vector3 = pts[wz * cells * cells + wy * cells + wx]
				var ddx: float = float(ix + dx) + pt.x - px
				var ddy: float = oy + pt.y - py
				var ddz: float = oz + pt.z - pz
				var d2: float = ddx * ddx + ddy * ddy + ddz * ddz
				if d2 < best:
					best = d2
	return clampf(sqrt(best) / 1.2, 0.0, 1.0)


func jitter_points(cells: int, seed_v: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.resize(cells * cells * cells)
	for cz in range(cells):
		for cy in range(cells):
			for cx in range(cells):
				pts[cz * cells * cells + cy * cells + cx] = Vector3(
					hfloat(cx, cy, cz, seed_v + 101),
					hfloat(cx, cy, cz, seed_v + 202),
					hfloat(cx, cy, cz, seed_v + 303))
	return pts


func seam_ratio(data: PackedByteArray, n: int) -> float:
	var sum_wrap := 0.0
	var sum_inner := 0.0
	var cnt := 0
	for z in range(0, n, 2):
		for y in range(0, n, 2):
			var base: int = z * n * n + y * n
			var v0 := float(data[base])
			var v1 := float(data[base + n - 1])
			var v2 := float(data[base + n - 2])
			sum_wrap += absf(v0 - v1)
			sum_inner += absf(v1 - v2)
			cnt += 1
	return sum_wrap / maxf(sum_inner, 1e-6)


func checksum64(data: PackedByteArray) -> int:
	var s := 0
	for i in range(0, data.size(), 97):
		s = (s * 31 + int(data[i])) & 0x7FFFFFFF
	return s


func save_bin(data: PackedByteArray, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("gen_noise3d: не открыть %s (err %d)" % [path, FileAccess.get_open_error()])
		return
	f.store_buffer(data)
	f.close()


## B2: wrap-согласованный бокс-блюр 3³: смягчает PW-жилы (источник алиасинга
## дальнего поля при сегменте марша 469 м) без нарушения бесшовности.
func box_blur_wrap(data: PackedByteArray, n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n * n * n)
	for z in range(n):
		var zlo := ((z - 1 + n) % n) * n * n
		var zmd := z * n * n
		var zhi := ((z + 1) % n) * n * n
		for y in range(n):
			var ylo := ((y - 1 + n) % n) * n
			var ymd := y * n
			var yhi := ((y + 1) % n) * n
			for x in range(n):
				var xlo := (x - 1 + n) % n
				var xmd := x
				var xhi := (x + 1) % n
				var sum := 0
				for zr in [zlo, zmd, zhi]:
					for yr in [ylo, ymd, yhi]:
						var base: int = zr + yr
						sum += int(data[base + xlo]) + int(data[base + xmd]) + int(data[base + xhi])
				out[(z * n + y) * n + x] = int(roundf(float(sum) / 27.0))
	return out


func _init() -> void:
	print("GEN: Perlin-Worley %d³ (cells=%d, seed=%d)..." % [PW_SIZE, PW_CELLS, PW_SEED])
	var t0 := Time.get_ticks_msec()
	var pw_pts := jitter_points(PW_CELLS, PW_SEED)
	var pw := perlin_worley_field(PW_SIZE, PW_CELLS, PW_SEED, pw_pts)
	pw = box_blur_wrap(pw, PW_SIZE)
	var t1 := Time.get_ticks_msec()
	print("GEN: PW готово за %d мс (с блюром), seam_ratio=%.3f (<1.5 = бесшовно), checksum=%d" % [t1 - t0, seam_ratio(pw, PW_SIZE), checksum64(pw)])
	save_bin(pw, OUT_DIR + "noise_pw_128.bin")
	print("GEN: Worley %d³ (cells=%d, seed=%d, invert)..." % [WO_SIZE, WO_CELLS, WO_SEED])
	var wo := worley_field(WO_SIZE, WO_CELLS, WO_SEED, true)
	var t2 := Time.get_ticks_msec()
	print("GEN: Worley готово за %d мс, seam_ratio=%.3f, checksum=%d" % [t2 - t1, seam_ratio(wo, WO_SIZE), checksum64(wo)])
	save_bin(wo, OUT_DIR + "noise_worley_32.bin")
	# статистика PW (для калибровки coverage)
	var n_low := 0
	var n_high := 0
	for i in range(0, pw.size(), 7):
		if pw[i] < 64:
			n_low += 1
		if pw[i] > 192:
			n_high += 1
	print("GEN: PW статистика (выборка 1/7): low(<0.25)=%d high(>0.75)=%d из %d" % [n_low, n_high, pw.size() / 7])
	print("GEN: DONE")
	quit(0)
