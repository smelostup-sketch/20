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


## Зеркало ramp_u (Sky3.2.4): четыре стопа + положения + sharp. Порядок stops —
## ОТ солнца: [col_sky4, col_sky3, col_sky2, col_sky1] (шаг 4 у солнца, шаг 1 в антисоляре).
## Q7.34 (COLORS5): стопы = ДИСПЛЕЙНЫЕ ДАННЫЕ (palette hex/255, encoded sRGB);
## mix идёт в кодированном пространстве — как в шейдере. Байт полосы/неба =
## round(значение × 255) БЕЗ каких-либо конверсий: filmic-зеркало отсюда ушло
## вместе с цепью A старой схемы (конвертеры теперь живут в шейдере:
## disp2scene/scene2disp, и в q_tools/palette_tool.py для CPU-сверок).
static func ramp_color(stops: Array, p: Array, sharp: float, u: float) -> Color:
	var c: Color = stops[0]
	c = c.lerp(stops[1], win_f(p[0], p[1], u, sharp))
	c = c.lerp(stops[2], win_f(p[1], p[2], u, sharp))
	c = c.lerp(stops[3], win_f(p[2], p[3], u, sharp))
	return c


static func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


static func stops_of(p: SkyPreset) -> Array:
	return [p.col_sky4, p.col_sky3, p.col_sky2, p.col_sky1]


static func pos_of(p: SkyPreset) -> Array:
	return [p.q1, p.q2, p.q3, p.q4]


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

	# 1. Порядок стопов: q1 < q2 < q3 < q4, зазор >= MIN_GAP
	for i in range(3):
		if pos[i + 1] - pos[i] < MIN_GAP - 1e-9:
			errors.append("порядок стопов: q%d(%.3f) и q%d(%.3f) — зазор < %.2f" % [i + 1, pos[i], i + 2, pos[i + 1], MIN_GAP])

	# 2. Соседние цвета не совпадают побитово (порядок от солнца: sky4, sky3, sky2, sky1)
	var names := ["sky4", "sky3", "sky2", "sky1"]
	for i in range(3):
		var a: Color = stops[i]
		var b: Color = stops[i + 1]
		if a.r == b.r and a.g == b.g and a.b == b.b:
			errors.append("цвета стопов совпадают: %s == %s (пара %d-%d)" % [names[i], names[i + 1], i, i + 1])

	# 3. Монотонность яркости: сэмпл L(u) на 201 шаге на [q1, 1], строго убывает
	var prev := lum(stops[0])
	var viol := 0
	for i in range(1, 201):
		var u := p.q1 + (1.0 - p.q1) * i / 200.0
		var cur := lum(ramp_color(stops, pos, p.sharp, u))
		if cur >= prev - 1e-12:
			viol += 1
		prev = cur
	if viol > 0:
		# Q7.34 (S4C): палитры заказчика допускают немонотонную яркость (художественные
		# слои: напр. у пресета 04 циановый слой ярче горизонта). Шейдер интерполирует
		# любой порядок стопов, правило было для физического купола — понижено до
		# предупреждения: данные заказчика приоритетнее физической монотонности.
		warnings.append("монотонность яркости: %d нарушений убывания L(u) на [q1, 1] (разрешено: палитра заказчика, арт-слой)" % viol)

	# 4. light не задан
	if p.light == null:
		errors.append("light не задан: пресет без профиля света не применяется")

	# 5. q4 < 1.0 — предупреждение
	if p.q4 < 1.0:
		warnings.append("q4 = %.3f < 1.0: терминал не дотянут до антисоляра — останется плоский хвост" % p.q4)

	# 6. Ширина окна: (qN - qN-1) * sharp < 0.02 — предупреждение
	for i in range(3):
		if (pos[i + 1] - pos[i]) * p.sharp < 0.02:
			warnings.append("окно q%d→q%d шириной %.3f — переход почти скачком" % [i + 1, i + 2, (pos[i + 1] - pos[i]) * p.sharp])

	# 7. Q7.34 (COLORS5): стопы = display-данные (hex/255), канал вне [0,1] —
	#    признак старого линейного формата (до COLORS5 col_* были linear HDR).
	for i in range(4):
		var c: Color = stops[i]
		if maxf(c.r, maxf(c.g, c.b)) > 1.0 + 1e-6:
			warnings.append("стоп %s: канал > 1 — данные должны быть display hex/255 (COLORS5); похоже на старый линейный формат" % names[i])

	# 8. солнце под горизонтом при включённом — предупреждение (решения 2 и 16)
	if p.sun_enabled and p.sun_elevation < 0.0:
		warnings.append("sun_elevation = %.1f < 0 при sun_enabled: солнце под горизонтом видно — проверьте, что так задумано" % p.sun_elevation)

	# 9. Вуаль (Sky3.2.8, S11): veil == null = выключена (старый формат, НЕ ошибка —
	#    старые .tres грузятся без миграции). Включённая, но прозрачная плита —
	#    предупреждение: данные валидны, вид сомнителен (приёмка S12 «текстура-характер»).
	if p.veil != null and p.veil.veil_enabled:
		if p.veil.veil_amount < 0.01:
			warnings.append("вуаль включена, но amount = %.2f — плита почти не видна" % p.veil.veil_amount)
		if p.veil.veil_tau_per_km < 0.01:
			warnings.append("вуаль включена, но tau = %.3f/км — при толщине ~1.2 км текстуры не даст" % p.veil.veil_tau_per_km)

	return {"errors": errors, "warnings": warnings}


## Наборовая проверка (фаза H): одинаковые векторы формы q1..q3 у разных
## НАПОЛНЕННЫХ пресетов — предупреждение. Свободные слоты (light == null) не сравниваются.
static func check_set(list: Array) -> Array:
	var warnings: Array[String] = []
	for i in range(list.size()):
		for j in range(i + 1, list.size()):
			var a: SkyPreset = list[i]
			var b: SkyPreset = list[j]
			if a == null or b == null or a.light == null or b.light == null:
				continue
			if a.q1 == b.q1 and a.q2 == b.q2 and a.q3 == b.q3:
				warnings.append("пресеты %s и %s идентичны по форме q1..q3" % [a.preset_name, b.preset_name])
	return warnings
