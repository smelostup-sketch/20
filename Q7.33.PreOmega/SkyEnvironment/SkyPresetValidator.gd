extends RefCounted
class_name SkyPresetValidator
## Q7.33 — проверки данных пресета (глава 15 ТЗ) + CPU-ЗЕРКАЛО рампы (п. 13.2/13.3):
## одно на панель (полоса) и на валидатор; формулы те же, что в
## sky_grad_check/sky_gradient_check.py. Ошибки блокируют сохранение пресета,
## предупреждения — нет. Статические функции.

const MIN_GAP := 0.01	# тот же зазор, что в панели (1% шкалы)


# ============ CPU-зеркало рампы (порт ramp_u/win из SkyEnvironment.gdshader) ============

static func sstep_f(e0: float, e1: float, x: float) -> float:
	if e1 <= e0:
		return 1.0 if x >= e1 else 0.0
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func win_f(lo: float, hi: float, x: float, sharp: float) -> float:
	var w := (hi - lo) * sharp
	return sstep_f(hi - w, hi, x)


## Зеркало ramp_u: шесть стопов + положения + sharp. Возвращает ЛИНЕЙНЫЙ цвет.
static func ramp_color(stops: Array, p: Array, sharp: float, u: float) -> Color:
	var c: Color = stops[0]
	c = c.lerp(stops[1], win_f(p[0], p[1], u, sharp))
	c = c.lerp(stops[2], win_f(p[1], p[2], u, sharp))
	c = c.lerp(stops[3], win_f(p[2], p[3], u, sharp))
	c = c.lerp(stops[4], win_f(p[3], p[4], u, sharp))
	c = c.lerp(stops[5], win_f(p[4], maxf(p[5], 1.0), u, sharp))
	return c


# Константы filmic() — точный порт const FA..FN из SkyEnvironment.gdshader
# (строки 168–174). На уровне класса: GDScript не поддерживает объявление
# нескольких переменных через запятую в одной строке.
const FA := 0.88
const FB := 0.60
const FCB := 0.06
const FDE := 0.002
const FDF := 0.06
const FEF := 0.03333333
const FN := 0.7285913529


## Зеркало filmic() шейдера (display-преобразование для полосы и таблицы).
static func filmic_f(x: float) -> float:
	var c := maxf(x, 0.0)
	return (((c * (FA * c + FCB) + FDE) / (c * (FA * c + FB) + FDF)) - FEF) / FN


static func filmic3_c(v: Color) -> Color:
	return Color(filmic_f(v.r), filmic_f(v.g), filmic_f(v.b), 1.0)


static func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


static func stops_of(p: SkyPreset) -> Array:
	return [p.col_glow, p.col_horizon, p.col_band, p.col_band2, p.col_mid, p.col_anti]


static func pos_of(p: SkyPreset) -> Array:
	return [p.p1, p.p2, p.p3, p.p4, p.p5, p.p6]


# ============ проверки (глава 15) ============

## Возвращает {"errors": Array[String], "warnings": Array[String]}.
static func validate(p: SkyPreset) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if p == null:
		errors.append("пресет = null")
		return {"errors": errors, "warnings": warnings}
	var stops := stops_of(p)
	var pos := pos_of(p)

	# 1. Порядок стопов: p1 < p2 < ... < p6, зазор >= MIN_GAP
	for i in range(5):
		if pos[i + 1] - pos[i] < MIN_GAP - 1e-9:
			errors.append("порядок стопов: p%d(%.3f) и p%d(%.3f) — зазор < %.2f" % [i + 1, pos[i], i + 2, pos[i + 1], MIN_GAP])

	# 2. Соседние цвета не совпадают побитово
	var names := ["glow", "horizon", "band", "band2", "mid", "anti"]
	for i in range(5):
		var a: Color = stops[i]
		var b: Color = stops[i + 1]
		if a.r == b.r and a.g == b.g and a.b == b.b:
			errors.append("цвета стопов совпадают: %s == %s (пара %d-%d)" % [names[i], names[i + 1], i, i + 1])

	# 3. Монотонность яркости: сэмпл L(u) на 201 шаге на [p1, 1], строго убывает
	var prev := lum(stops[0])
	var viol := 0
	for i in range(1, 201):
		var u := p.p1 + (1.0 - p.p1) * i / 200.0
		var cur := lum(ramp_color(stops, pos, p.sharp, u))
		if cur >= prev - 1e-12:
			viol += 1
		prev = cur
	if viol > 0:
		errors.append("монотонность яркости: %d нарушений убывания L(u) на [p1, 1]" % viol)

	# 4. light не задан
	if p.light == null:
		errors.append("light не задан: пресет без профиля света не применяется")

	# 5. p6 < 1.0 — предупреждение
	if p.p6 < 1.0:
		warnings.append("p6 = %.3f < 1.0: терминал не дотянут до антисоляра — останется плоский хвост" % p.p6)

	# 6. Ширина окна: (pN - pN-1) * sharp < 0.02 — предупреждение
	for i in range(5):
		if (pos[i + 1] - pos[i]) * p.sharp < 0.02:
			warnings.append("окно p%d→p%d шириной %.3f — переход почти скачком" % [i + 1, i + 2, (pos[i + 1] - pos[i]) * p.sharp])

	# 7. Пересвет: любой канал цвета > 2.5 — предупреждение
	for i in range(6):
		var c: Color = stops[i]
		if maxf(c.r, maxf(c.g, c.b)) > 2.5:
			warnings.append("пересвет: стоп %s, канал > 2.5" % names[i])

	# 8. солнце под горизонтом при включённом — предупреждение (решения 2 и 16)
	if p.sun_enabled and p.sun_elevation < 0.0:
		warnings.append("sun_elevation = %.1f < 0 при sun_enabled: солнце под горизонтом видно — проверьте, что так задумано" % p.sun_elevation)

	return {"errors": errors, "warnings": warnings}


## Наборовая проверка (фаза H): одинаковые векторы формы p1..p5 у разных
## НАПОЛНЕННЫХ пресетов — предупреждение («K3…K6 идентичны»). Свободные слоты
## (light == null) не сравниваются.
static func check_set(list: Array) -> Array:
	var warnings: Array[String] = []
	for i in range(list.size()):
		for j in range(i + 1, list.size()):
			var a: SkyPreset = list[i]
			var b: SkyPreset = list[j]
			if a == null or b == null or a.light == null or b.light == null:
				continue
			if a.p1 == b.p1 and a.p2 == b.p2 and a.p3 == b.p3 and a.p4 == b.p4 and a.p5 == b.p5:
				warnings.append("пресеты %s и %s идентичны по форме p1..p5" % [a.preset_name, b.preset_name])
	return warnings
