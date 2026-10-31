extends RefCounted
class_name SkyPresetValidator
## Q7.33 — проверки данных пресета (глава 15 ТЗ) + CPU-ЗЕРКАЛО градиента:
## одно на панель (полоса) и на валидатор; формулы те же, что в шейдере
## (4.1.7: get_sky_gradient — доли + мягкие smoothstep-переходы) и в
## q_tools/palette_tool.py. Ошибки блокируют сохранение пресета,
## предупреждения — нет. Статические функции.

const MIN_GAP := 0.01	# тот же зазор, что в панели (1% шкалы)


# ============ CPU-зеркало градиента (порт get_sky_gradient из SkyEnvironment.gdshader) ============

static func sstep_f(e0: float, e1: float, x: float) -> float:
	if e1 <= e0:
		return 1.0 if x >= e1 else 0.0
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Зеркало дефолта sky_transition_width (4.1.7): валидация данных пресета не
## имеет доступа к живому материалу — ширина перехода берётся как дефолт
## uniform'а (полоса панели передаёт живое значение материала).
const TW_DEFAULT := 0.025


## Доли четырёх цветов из кумулятивных границ q1..q4 (4.1.7): w1=q1, w2=q2−q1,
## w3=q3−q2, w4=q4−q3. Тот же вывод, что в SkyEnvironmentController.apply_palette.
static func weights_of_pos(p: Array) -> Array:
	return [p[0], p[1] - p[0], p[2] - p[1], p[3] - p[2]]


## Зеркало get_sky_gradient (4.1.7, формула заказчика): четыре доли + мягкие
## smoothstep-переходы (f = max(0.0005, min(tw, 0.45·min(доля, доля соседа)))).
## Порядок stops — ОТ солнца: [col_sky4, col_sky3, col_sky2, col_sky1] (шаг 4
## у солнца, шаг 1 в антисоляре); w — доли (нормируются здесь, как в шейдере).
## Q7.34 (COLORS5): стопы = ДИСПЛЕЙНЫЕ ДАННЫЕ (palette hex/255, encoded sRGB);
## mix идёт в кодированном пространстве — как в шейдере. Байт полосы/неба =
## round(значение × 255) БЕЗ каких-либо конверсий.
static func ramp_color(stops: Array, w: Array, tw: float, u: float) -> Color:
	var wn: Array = [0.0, 0.0, 0.0, 0.0]
	var tot := 0.0
	for i in range(4):
		tot += maxf(float(w[i]), 0.0)
	tot = maxf(tot, 0.0001)
	for i in range(4):
		wn[i] = maxf(float(w[i]), 0.0) / tot
	var b1: float = wn[0]
	var b2: float = wn[0] + wn[1]
	var b3: float = wn[0] + wn[1] + wn[2]
	var f1: float = maxf(0.0005, minf(tw, 0.45 * minf(wn[0], wn[1])))
	var f2: float = maxf(0.0005, minf(tw, 0.45 * minf(wn[1], wn[2])))
	var f3: float = maxf(0.0005, minf(tw, 0.45 * minf(wn[2], wn[3])))
	var c: Color = stops[0]
	c = c.lerp(stops[1], sstep_f(b1 - f1, b1 + f1, u))
	c = c.lerp(stops[2], sstep_f(b2 - f2, b2 + f2, u))
	c = c.lerp(stops[3], sstep_f(b3 - f3, b3 + f3, u))
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
	var w := weights_of_pos(pos)
	var prev := lum(stops[0])
	var viol := 0
	for i in range(1, 201):
		var u := p.q1 + (1.0 - p.q1) * i / 200.0
		var cur := lum(ramp_color(stops, w, TW_DEFAULT, u))
		if cur >= prev - 1e-12:
			viol += 1
		prev = cur
	if viol > 0:
		# Q7.34 (S4C): палитры заказчика допускают немонотонную яркость (художественные
		# слои: напр. у пресета 04 циановый слой ярче горизонта). Шейдер интерполирует
		# любой порядок стопов, правило было для физического купола — понижено до
		# предупреждения: данные заказчика приоритетнее физической монотонности.
		warnings.append("монотонность яркости: %d нарушений убывания L(u) на [q1, 1] (разрешено: палитра заказчика, арт-слой)" % viol)

	# 4. (4.1.1 УДАЛЕНО вместе с полем light: пресет без профиля света — норма.
	#     Свет сцены читается событийно с узла Sun, новый контракт —
	#     AtmosphereLightingProfile; правило «light не задан» больше не существует.)

	# 5. q4 < 1.0 — предупреждение (4.1.7: в модели долей хвост нормируется
	#    до антисоляра — старая семантика «плоского хвоста» ушла вместе с win/sharp)
	if p.q4 < 1.0:
		warnings.append("q4 = %.3f < 1.0: в модели долей (4.1.7) хвост нормируется до антисоляра — данные будут растянуты" % p.q4)

	# 6. (4.1.7) Вырожденная доля: w_i < 0.02 — предупреждение (зона почти
	#    исчезает; smoothstep защищён f ≥ 0.0005 — на любых данных без аварий)
	for i in range(4):
		if float(w[i]) < 0.02:
			warnings.append("доля цвета %d = %.3f — зона почти вырождена" % [i + 1, float(w[i])])

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
## пресетов — предупреждение.
## 4.1.1: маркер «наполненности» light == null ушёл вместе с полем light —
## сравниваются все ненулевые пресеты набора.
static func check_set(list: Array) -> Array:
	var warnings: Array[String] = []
	for i in range(list.size()):
		for j in range(i + 1, list.size()):
			var a: SkyPreset = list[i]
			var b: SkyPreset = list[j]
			if a == null or b == null:
				continue
			if a.q1 == b.q1 and a.q2 == b.q2 and a.q3 == b.q3:
				warnings.append("пресеты %s и %s идентичны по форме q1..q3" % [a.preset_name, b.preset_name])
	return warnings
