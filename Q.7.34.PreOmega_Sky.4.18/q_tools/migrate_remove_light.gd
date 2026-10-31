extends SceneTree
## Q.7.34.PreOmega_Sky.4.1.1 (этап 01, граница удаления — добро заказчика
## 30.10 п.4): миграция пресетов — sub-resource `light` (SkyLightProfile)
## удаляется из всех .tres: строка `light = SubResource(...)`, блок
## [sub_resource] профиля света и строка [ext_resource] скрипта.
##
## Текстовая (FileAccess), БЕЗ загрузки Resource: скрипт SkyLightProfile.gd к
## моменту запуска может быть уже удалён, а загрузка .tres с мёртвым
## ext_resource дала бы шум/ошибки. Каждое удаление — с контролем «ровно один»
## (ловушка инструментов: молчаливый no-match при несовпадении паттерна);
## после записи — grep-контроль отсутствия следов.
##
## Сканирует SkyPreset/ и SkyPresetRefs/ (если существует — референсные слепки
## панели тоже могут нести light). Файлы без SkyLightProfile пропускаются.
## Запуск: godot --headless --path <проект> --script q_tools/migrate_remove_light.gd

const DIRS: Array[String] = [
	"res://SkyEnvironment/SkyPreset",
	"res://SkyEnvironment/SkyPresetRefs",
]

## Следы света, которых после миграции в файле быть не должно.
const TRACES: Array[String] = [
	"SkyLightProfile", "light = SubResource", "key_color", "key_energy",
	"moon_light_color", "moon_light_energy", "ambient_energy",
]


func _init() -> void:
	var migrated := 0
	var skipped := 0
	var bad := 0
	for dir: String in DIRS:
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
			continue
		var d := DirAccess.open(dir)
		if d == null:
			printerr("не открылась папка %s" % dir)
			bad += 1
			continue
		for fn: String in d.get_files():
			if not fn.ends_with(".tres"):
				continue
			var path := dir + "/" + fn
			var src := FileAccess.get_file_as_string(path)
			if not src.contains("SkyLightProfile"):
				skipped += 1
				continue
			var out := _strip_light(src)
			if out == "":
				printerr("FAIL %s (паттерн не сошёлся ровно один раз или остались следы)" % path)
				bad += 1
				continue
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				printerr("FAIL запись %s" % path)
				bad += 1
				continue
			f.store_string(out)
			f.close()
			migrated += 1
			print("OK %s" % path)
	print("MIGRATE_REMOVE_LIGHT: %s (мигрировано %d, пропущено чистых %d, ошибок %d)"
		% ["PASS" if bad == 0 else "FAIL", migrated, skipped, bad])
	quit(0 if bad == 0 else 1)


## Возвращает текст без light-блока или "" если структурный контроль не сошёлся.
func _strip_light(src: String) -> String:
	var lines := src.split("\n")

	# 1) строка [ext_resource] скрипта SkyLightProfile.gd — ровно одна
	var ext_idx := _find_lines(lines, "SkyLightProfile.gd")
	if ext_idx.size() != 1:
		return ""
	var ei: int = ext_idx[0]
	var ext_id := _attr(lines[ei], "id")
	if ext_id == "":
		return ""

	# 2) блок [sub_resource] профиля света: ровно одна строка script = ExtResource(id)
	var scr_idx := _find_lines(lines, 'script = ExtResource("%s")' % ext_id)
	if scr_idx.size() != 1:
		return ""
	var si: int = scr_idx[0]
	var start := -1
	for i in range(si, -1, -1):
		var s: String = lines[i]
		if s.begins_with("[sub_resource"):
			start = i
			break
	if start < 0:
		return ""
	var sub_id := _attr(lines[start], "id")
	if sub_id == "":
		return ""
	# конец блока: первая пустая строка или следующий заголовок секции
	var stop := si + 1
	while stop < lines.size():
		var t: String = lines[stop]
		if t.begins_with("[") or t.strip_edges() == "":
			break
		stop += 1
	# съесть одну завершающую пустую строку блока (иначе останется двойная)
	if stop < lines.size() and (lines[stop] as String).strip_edges() == "":
		stop += 1

	# 3) строка light = SubResource("sub_id") в [resource] — ровно одна
	var light_idx := _find_lines(lines, 'light = SubResource("%s")' % sub_id)
	if light_idx.size() != 1:
		return ""

	# удаление по убыванию индексов (блок, ext_resource, light-строка)
	var kill: Array[int] = []
	for i in range(start, stop):
		kill.append(i)
	kill.append(ei)
	kill.append(light_idx[0])
	kill.sort()
	kill.reverse()
	for i in kill:
		lines.remove_at(i)

	var out := "\n".join(lines)
	for tr: String in TRACES:
		if out.contains(tr):
			return ""
	return out


func _find_lines(lines: PackedStringArray, needle: String) -> Array[int]:
	var idx: Array[int] = []
	for i in range(lines.size()):
		if (lines[i] as String).contains(needle):
			idx.append(i)
	return idx


## Значение атрибута `name="..."` из строки (без RegEx — проще и без зависимостей).
## Ищем с ведущим пробелом: иначе `id="` матчится внутри `uid="`.
func _attr(line: String, attr: String) -> String:
	var key := " " + attr + '="'
	var p := line.find(key)
	if p < 0:
		return ""
	var q := line.find('"', p + key.length())
	if q < 0:
		return ""
	return line.substr(p + key.length(), q - p - key.length())
