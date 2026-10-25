extends SceneTree
## skylab_palette_tool.gd — адаптация палитры M1 под итоговое отображение Filmic (Godot 4.7).
## Запуск: godot --headless -s skylab_palette_tool.gd
##
## Математика: ports of servers/rendering/renderer_rd/shaders/effects/tonemap.glsl (4.7-stable):
##   filmic(x) = ((x*(A*x + C*B) + D*E) / (x*(A*x + B) + D*F)) - E/F, затем / norm,
##   exposure_bias = 2 запечён в A,B; norm = filmic_raw(white*bias), white = Environment.white = 1.
## Канал независимый → инверсия бисекцией монотонной кривой.
## Цель: шейдер выдаёт c = inv_filmic(srgb_to_linear(palette_hex)); после пост-процесса
## (Filmic + sRGB-encode) пиксель равен палитре M1 с точностью ≤ 1/255.

const A := 0.22 * 4.0		# 0.22 * bias^2, bias = 2
const B := 0.30 * 2.0		# 0.30 * bias
const CB := 0.10 * 0.30 * 2.0	# C * B0 * bias
const DE := 0.20 * 0.01
const DF := 0.20 * 0.30
const EF := 0.01 / 0.30

const ROLES := ["zenith", "horizon", "lit", "shadow", "rim"]
const HEX := {
	"ref1": ["6f86c6", "ffd27a", "ff8a50", "5b4a7a", "ff6a3d"],
	"ref2": ["5d6b85", "ff8f7a", "ff5a4e", "7a4a52", "ffd9a0"],
	"ref3": ["8f9ce8", "ffe9c0", "ffc9d0", "b98ba0", "fff3c0"],
	"ref4": ["232c4e", "ff5a3a", "ff6a4a", "7a2f3a", "ff9d8a"],
	"ref5": ["2e6bb0", "ffe9b8", "fdf6ee", "8fa3c8", "f2a08a"],
}


func filmic_raw(x: float) -> float:
	var c := maxf(x, 0.0)
	return ((c * (A * c + CB) + DE) / (c * (A * c + B) + DF)) - EF


func norm() -> float:
	# Environment.white = 1.0, exposure_bias = 2.0 → white*bias = 2.0
	return filmic_raw(2.0)


func filmic(x: float) -> float:
	return filmic_raw(x) / norm()


func srgb_to_linear(u: float) -> float:
	if u <= 0.04045:
		return u / 12.92
	return pow((u + 0.055) / 1.055, 2.4)


func linear_to_srgb(l: float) -> float:
	if l <= 0.0031308:
		return l * 12.92
	return 1.055 * pow(l, 1.0 / 2.4) - 0.055


func inv_filmic(target_linear: float) -> float:
	var lo := 0.0
	var hi := 64.0
	for i in range(80):
		var mid := (lo + hi) * 0.5
		if filmic(mid) < target_linear:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


func hex_to_linear(h: String) -> Vector3:
	var r := srgb_to_linear(h.substr(0, 2).hex_to_int() / 255.0)
	var g := srgb_to_linear(h.substr(2, 2).hex_to_int() / 255.0)
	var b := srgb_to_linear(h.substr(4, 2).hex_to_int() / 255.0)
	return Vector3(r, g, b)


func _initialize() -> void:
	var max_err := 0.0
	print("// ADAPTED PALETTE (inv-Filmic, Godot 4.7) — scene-linear values for shader uniforms")
	print("const ADAPTED := {")
	for st in ["ref1", "ref2", "ref3", "ref4", "ref5"]:
		print('\t"%s": {' % st)
		for i in range(5):
			var lin := hex_to_linear(HEX[st][i])
			var adp := Vector3(inv_filmic(lin.x), inv_filmic(lin.y), inv_filmic(lin.z))
			# round-trip check
			var back := Vector3(linear_to_srgb(filmic(adp.x)), linear_to_srgb(filmic(adp.y)), linear_to_srgb(filmic(adp.z)))
			var want := Vector3(HEX[st][i].substr(0, 2).hex_to_int() / 255.0, HEX[st][i].substr(2, 2).hex_to_int() / 255.0, HEX[st][i].substr(4, 2).hex_to_int() / 255.0)
			max_err = maxf(max_err, absf(back.x - want.x))
			max_err = maxf(max_err, absf(back.y - want.y))
			max_err = maxf(max_err, absf(back.z - want.z))
			print('\t\t"%s": Vector3(%.6f, %.6f, %.6f),' % [ROLES[i], adp.x, adp.y, adp.z])
		print("\t},")
	print("}")
	print("// max round-trip error (display 0..1): %.6f  (= %.3f / 255)" % [max_err, max_err * 255.0])
	quit()
