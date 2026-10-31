#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ВНИМАНИЕ (COLORS5, 29.10): инструмент устарел — стопы col_* теперь ДИСПЛЕЙНЫЕ
данные (hex/255), а не linear inv_filmic. Записывать .tres им НЕЛЬЗЯ (формат
стопов изменён); оставлен как историческая механика арт-калибровки S3/S4.

palette_apply_s4.py — шаг S4 плана Q7.34: сверка и перекалибровка ОСТАЛЬНЫХ
пяти слотов (01/04/05/08/10) по их арт-референсам, удаление масштабирующих
коэффициентов «×0.7…» из данных и имён пресетов.

Метод (тот же, что S3):
  1. Из арт-референса слота (preset_NN.jpg/png) семплируются 5 patch-областей
     ЧИСТОГО купола (медиана байтов): glow, horizon, band, mid, anti.
  2. Байты -> linear по ЦЕПИ A: linear = inv_filmic(srgb_to_linear(byte/255)).
  3. band2 = geomean(band, mid); halo = glow*1.4.
  4. Монотонность яркости стопов (требование валидатора): при нарушении стоп
     затемняется скаляром (hue сохраняется): lum[i] := lum[i-1]*0.85.
  5. .tres правится ХИРУРГИЧЕСКИ: заменяются только строки col_* / col_halo /
     preset_name. Всё остальное (light, звёзды, луна, p1..p5, streak...)
     сохраняется байт-в-байт — в отличие от полной перезаписи S3.
  6. Набор из 10 слотов прогоняется через CPU-зеркало SkyPresetValidator
     (правила 1-8) + check_set: ошибки обязаны быть пусты.

Формы рамп p1..p5 НЕ меняются (у этих пяти слотов они свои, унаследованы из
Q7.33 и различны — check_set на них не срабатывает). У слотов S3 (02/03/06/07/09)
форма общая P_DEFAULT — это даёт предупреждения check_set, но не ошибки;
развод форм слотов S3 — отдельное решение заказчика, в S4 не трогаем.

Миниатюры (preview) в S4 не меняются: арт и есть источник калибровки.
Пересохранение миниатюр из рендера — действие заказчика в игре (кнопка панели
«Сохранить в… (с миниатюрой)»), см. README патча.

Зависимость: Pillow нужен ТОЛЬКО для .jpg-референсов (01/04/05); .png читает
чистый ридер palette_tool.read_png. Без Pillow скрипт обработает слоты 08/10
и сообщит, какие пропущены.

Запуск: python3 palette_apply_s4.py [--write] [--check-png OUT.png]
Без --write: только отчёт и проверки. С --write: правка пяти .tres.
"""
import os
import re
import sys
import zlib
import struct

import palette_tool as pt

BASE = os.path.dirname(os.path.abspath(__file__))
PRESET_DIR = os.path.join(BASE, '..', 'SkyEnvironment', 'SkyPreset')

# ---------------------------------------------------------------------------
# patch-области ЧИСТОГО купола, доли (x0,y0,x1,y1) от W/H арта слота.
# Подобраны численным зондированием (медианы без облаков/луны/звёзд/земли).
# ---------------------------------------------------------------------------
SLOTS = {
    1: dict(ref='preset_01.jpg', label='K0 глубокая ночь',
            patches=dict(glow=(0.48, 0.806, 0.52, 0.816),    # луная полоса над водой
                         horizon=(0.48, 0.776, 0.52, 0.786),
                         band=(0.48, 0.752, 0.52, 0.762),
                         mid=(0.28, 0.26, 0.32, 0.28),
                         anti=(0.28, 0.10, 0.32, 0.12))),
    4: dict(ref='preset_04.jpg', label='K1 астро-сумерки',
            patches=dict(glow=(0.45, 0.655, 0.55, 0.67),     # розовая полоса над горами
                         horizon=(0.45, 0.60, 0.55, 0.615),
                         band=(0.50, 0.42, 0.56, 0.435),     # циан
                         mid=(0.30, 0.52, 0.36, 0.535),      # индиго
                         anti=(0.50, 0.06, 0.56, 0.075))),
    5: dict(label='K2 синий час', ref='preset_05.jpg',
            patches=dict(glow=(0.60, 0.63, 0.66, 0.645),     # розовый горизонт
                         horizon=(0.75, 0.58, 0.81, 0.595),
                         band=(0.20, 0.47, 0.26, 0.485),     # пурпур
                         mid=(0.75, 0.27, 0.81, 0.285),      # сине-пурпурный
                         anti=(0.30, 0.06, 0.36, 0.075))),
    8: dict(ref='preset_08.png', label='K3 контровой закат',
            patches=dict(glow=(0.30, 0.88, 0.38, 0.90),      # жёлтый у скрытого солнца
                         horizon=(0.52, 0.17, 0.58, 0.20),   # кремовое «окно»
                         band=(0.50, 0.10, 0.56, 0.13),
                         mid=(0.60, 0.55, 0.66, 0.58),       # лаванда
                         anti=(0.92, 0.03, 0.98, 0.06))),    # тёмный сланец угол
    10: dict(ref='preset_10.png', label='K6 ясный день, кучевые',
             patches=dict(glow=(0.46, 0.88, 0.54, 0.90),     # тёплый кремовый горизонт
                          horizon=(0.16, 0.44, 0.22, 0.47),  # бледно-тёплый
                          band=(0.28, 0.22, 0.34, 0.25),     # голубой
                          mid=(0.64, 0.60, 0.70, 0.63),      # грифельно-синий
                          anti=(0.55, 0.03, 0.61, 0.05))),   # глубокий синий зенит
}
# перекрёстные референсы плана §2.3 (информационно, в данные не пишутся)
CROSS_REFS = {'N1.jpg': 'ночной/лунный доп. реф', 'N3.jpg': 'фиолетовая ночь доп. реф',
              'ref2.png': 'красный закат доп. реф'}
NEW_NAME = '%02d · %s (Q7.34 S4, купол из арта, цепь A)'

MIN_GAP = 0.01

# Дефолты цветов из SkyPreset.gd (@export): свободные слоты HEAD (02/03/07 до S3)
# не держат строк col_* в .tres — зеркало валидатора обязано видеть те же
# значения, что увидит Godot (скрипт подставит дефолты).
COL_DEFAULTS = {'col_glow': (2.0, 0.5, 0.2), 'col_horizon': (1.4, 0.4, 0.25),
                'col_band': (0.6, 0.35, 0.7), 'col_band2': (0.3, 0.3, 0.8),
                'col_mid': (0.12, 0.18, 0.4), 'col_anti': (0.02, 0.03, 0.09),
                'col_halo': (2.0, 0.5, 0.2)}


def load_preset(path):
    """read_preset + дефолты цветов + признак наличия профиля света."""
    pr = pt.read_preset(path)
    for k, v in COL_DEFAULTS.items():
        pr.setdefault(k, v)
    pr['has_light'] = 'light = SubResource' in open(path, encoding='utf-8').read()
    return pr


# ---------------------------------------------------------------- изображения
def open_ref(path):
    """Возвращает (w, h, get(x,y)->(r,g,b))."""
    if path.lower().endswith('.png'):
        return pt.read_png(path)
    try:
        from PIL import Image
    except ImportError:
        return None
    im = Image.open(path).convert('RGB')
    px = im.load()
    return im.size[0], im.size[1], (lambda x, y: px[x, y])


def median_byte(get, w, h, box):
    fx0, fy0, fx1, fy1 = box
    x0, y0 = int(fx0 * w), int(fy0 * h)
    x1, y1 = max(int(fx1 * w), x0 + 1), max(int(fy1 * h), y0 + 1)
    vals = [get(x, y) for y in range(y0, y1) for x in range(x0, x1)]
    return tuple(sorted(c[k] for c in vals)[len(vals) // 2] for k in range(3))


# ---------------------------------------------------------------- стоп-данные
def build_stops(img, spec):
    w, h, get = img
    lin, raw = {}, {}
    for name, box in spec['patches'].items():
        b = median_byte(get, w, h, box)
        raw[name] = b
        lin[name] = pt.lin_from_byte_A(b)
    lin['band2'] = tuple((lin['band'][k] * lin['mid'][k]) ** 0.5 for k in range(3))
    stops = [lin[n] for n in ('glow', 'horizon', 'band', 'band2', 'mid', 'anti')]
    fixed = []
    for i, s in enumerate(stops):                      # монотонность (hue-preserving)
        s = list(s)
        if i > 0:
            l_prev, l_cur = pt.lum(fixed[i - 1]), pt.lum(s)
            if l_cur >= l_prev * 0.97:
                k = (l_prev * 0.85) / max(l_cur, 1e-9)
                s = [v * k for v in s]
        fixed.append(tuple(s))
    halo = tuple(fixed[0][k] * 1.4 for k in range(3))
    return raw, fixed, halo


# --------------------------------------------- CPU-зеркало SkyPresetValidator
def mirror_validate(pr):
    """Правила 1-8 GDScript-валидатора (ошибки/предупреждения)."""
    errs, warns = [], []
    stops = [pr['col_glow'], pr['col_horizon'], pr['col_band'],
             pr['col_band2'], pr['col_mid'], pr['col_anti']]
    pos = [pr['p%d' % i] for i in range(1, 7)]
    names = ['glow', 'horizon', 'band', 'band2', 'mid', 'anti']
    for i in range(5):                                            # 1. зазоры
        if pos[i + 1] - pos[i] < MIN_GAP - 1e-9:
            errs.append('зазор p%d-p%d < 1%%' % (i + 1, i + 2))
    for i in range(5):                                            # 2. совпадения
        if all(abs(stops[i][k] - stops[i + 1][k]) < 1e-12 for k in range(3)):
            errs.append('стопы %s==%s' % (names[i], names[i + 1]))
    prev = pt.lum(stops[0]); viol = 0                             # 3. монотонность L(u)
    for i in range(1, 201):
        u = pr['p1'] + (1.0 - pr['p1']) * i / 200.0
        cur = pt.lum(pt.ramp_color(stops, pos, pr['sharp'], u))
        if cur >= prev - 1e-12:
            viol += 1
        prev = cur
    if viol:
        errs.append('монотонность L(u): %d нарушений' % viol)
    if pos[5] < 1.0:                                              # 5
        warns.append('p6=%.3f < 1.0' % pos[5])
    for i in range(5):                                            # 6
        if (pos[i + 1] - pos[i]) * pr['sharp'] < 0.02:
            warns.append('окно p%d->p%d почти скачок' % (i + 1, i + 2))
    for i in range(6):                                            # 7
        if max(stops[i]) > 2.5:
            warns.append('пересвет стопа %s > 2.5' % names[i])
    return errs, warns


def mirror_check_set(presets):
    """check_set: одинаковая форма p1..p5 у наполненных пресетов — warning."""
    warns = []
    items = [(n, p) for n, p in sorted(presets.items())
             if p is not None and p.get('has_light', True)]
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            a, b = items[i][1], items[j][1]
            if all(a['p%d' % k] == b['p%d' % k] for k in range(1, 6)):
                warns.append('форма p1..p5 идентична: %02d и %02d' % (items[i][0], items[j][0]))
    return warns


# ---------------------------------------------------------------- запись .tres
def patch_tres(path, slot, label, stops, halo):
    old = open(path, encoding='utf-8').read()
    names = ['col_glow', 'col_horizon', 'col_band', 'col_band2', 'col_mid', 'col_anti']
    for n, s in zip(names, stops):
        old = re.sub(r'^%s = Color\([^)]*\)' % n,
                     '%s = Color(%.6f, %.6f, %.6f, 1)' % (n, s[0], s[1], s[2]),
                     old, flags=re.M)
    old = re.sub(r'^col_halo = Color\([^)]*\)',
                 'col_halo = Color(%.6f, %.6f, %.6f, 1)' % halo, old, flags=re.M)
    old = re.sub(r'^preset_name = "[^"]*"',
                 'preset_name = "%s"' % (NEW_NAME % (slot, label)), old, flags=re.M)
    return old


# ---------------------------------------------------------------- PNG-писатель
def write_png(path, w, h, rgb):
    raw = b''.join(b'\x00' + bytes(rgb[y * w * 3:(y + 1) * w * 3]) for y in range(h))
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 6))
    png += chunk(b'IEND', b'')
    open(path, 'wb').write(png)


def render_check(path, rows, ref_w=180, ref_h=180, strip_w=240):
    """rows: [(slot, label, ref_img_or_None, stops)] -> png «арт | рампа в байтах неба»."""
    h_row = ref_h + 8
    W = ref_w + 8 + strip_w
    H = h_row * len(rows)
    buf = bytearray(W * H * 3)

    def put(x, y, c):
        i = (y * W + x) * 3
        buf[i:i + 3] = bytes(c)

    for r, (slot, label, img, stops) in enumerate(rows):
        y0 = r * h_row
        for y in range(ref_h):                                   # миниатюра арта
            for x in range(ref_w):
                if img is not None:
                    iw, ih, get = img
                    sx, sy = x * iw // ref_w, y * ih // ref_h
                    put(x, y0 + y, get(sx, sy))
                else:
                    put(x, y0 + y, (40, 40, 40))
        pos = [0.010, 0.075, 0.155, 0.300, 0.520, 1.0]           # полоса: форма слота
        pr = pt.read_preset(os.path.join(PRESET_DIR, 'Preset_%02d.tres' % slot))
        pos = [pr['p%d' % i] for i in range(1, 7)]
        for y in range(ref_h):                                   # рампа: цепь A
            u = 0.0 + (1.0 - 0.0) * y / (ref_h - 1)
            lin = pt.ramp_color(stops, pos, 1.0, u)
            c = pt.byte_sky(lin)
            for x in range(ref_w + 8, W):
                put(x, y0 + y, c)
    write_png(path, W, H, buf)


# ---------------------------------------------------------------- main
def main():
    write = '--write' in sys.argv
    check_png = None
    if '--check-png' in sys.argv:
        check_png = sys.argv[sys.argv.index('--check-png') + 1]
    report, ok = [], True
    rows = []
    for slot in sorted(SLOTS):
        spec = SLOTS[slot]
        ref_path = os.path.join(PRESET_DIR, spec['ref'])
        img = open_ref(ref_path)
        if img is None:
            report.append('== слот %02d: ПРОПУЩЕН (нужен Pillow для %s)' % (slot, spec['ref']))
            ok = False
            continue
        raw, stops, halo = build_stops(img, spec)
        pr = load_preset(os.path.join(PRESET_DIR, 'Preset_%02d.tres' % slot))
        planned = dict(pr)
        names = ['col_glow', 'col_horizon', 'col_band', 'col_band2', 'col_mid', 'col_anti']
        for n, s in zip(names, stops):
            planned[n] = s
        errs, warns = mirror_validate(planned)
        ok &= not errs
        report.append('== слот %02d · %s · реф %s' % (slot, spec['label'], spec['ref']))
        report.append('   patch-байты: %s' % ' '.join(
            '%s#%02X%02X%02X' % (k, *raw[k]) for k in ('glow', 'horizon', 'band', 'mid', 'anti')))
        for n, s in zip(['glow', 'horizon', 'band', 'band2', 'mid', 'anti'], stops):
            report.append('   %-8s lin(%7.4f,%7.4f,%7.4f) lum=%.4f небо=%3d %3d %3d' % (
                n, s[0], s[1], s[2], pt.lum(s), *pt.byte_sky(s)))
        report.append('   форма p1..p6 сохранена: %s' % [pr['p%d' % i] for i in range(1, 7)])
        report.append('   зеркало валидатора: %s%s' % (
            'OK' if not errs else '; '.join(errs),
            (' | warn: ' + '; '.join(warns)) if warns else ''))
        if write:
            path = os.path.join(PRESET_DIR, 'Preset_%02d.tres' % slot)
            text = patch_tres(path, slot, spec['label'], stops, halo)
            assert len(text) > 500, 'patch_tres вернул пустышку — не пишем!'
            open(path, 'w', encoding='utf-8').write(text)
            report.append('   ЗАПИСАН %s' % os.path.basename(path))
        rows.append((slot, spec['label'], img, stops))

    # ---- набор из 10 слотов: зеркало validate() + check_set()
    report.append('== НАБОР: зеркало SkyPresetValidator по 10 слотам')
    presets = {}
    for n in range(1, 11):
        presets[n] = load_preset(os.path.join(PRESET_DIR, 'Preset_%02d.tres' % n))
    set_errs = 0
    for n in sorted(presets):
        e, w = mirror_validate(presets[n])
        set_errs += len(e)
        tag = '' if presets[n]['has_light'] else ' [свободный слот, дефолты скрипта]'
        report.append('   %02d %-46s errors=%d warns=%d%s%s' % (
            n, presets[n]['preset_name'][:46], len(e), len(w), tag,
            (' :: ' + '; '.join(e + w)) if (e or w) else ''))
    sw = mirror_check_set(presets)
    report.append('   check_set: %s' % ('; '.join(sw) if sw else 'предупреждений нет'))
    report.append('   ИТОГО ошибок по набору: %d' % set_errs)
    ok &= (set_errs == 0)

    # ---- перекрёстные референсы (информационно)
    report.append('== перекрёстные референсы (сравнение байтов, информационно)')
    for f, note in CROSS_REFS.items():
        p = os.path.join(PRESET_DIR, f)
        img = open_ref(p)
        if img is None:
            report.append('   %s: нужен Pillow, пропущен' % f)
            continue
        w, h, get = img
        top = median_byte(get, w, h, (0.45, 0.05, 0.55, 0.08))
        mid = median_byte(get, w, h, (0.45, 0.35, 0.55, 0.38))
        hor = median_byte(get, w, h, (0.45, 0.62, 0.55, 0.65))
        report.append('   %-9s (%s) верх#%02X%02X%02X серед#%02X%02X%02X гориз#%02X%02X%02X' % (
            f, note, *top, *mid, *hor))

    print('\n'.join(report))
    if check_png and rows:
        render_check(check_png, rows)
        report.append('check-png: %s' % check_png)
    print('S4 CHECK: %s' % ('PASS' if ok else 'FAIL'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
