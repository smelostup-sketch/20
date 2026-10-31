#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ВНИМАНИЕ (COLORS5, 29.10): инструмент устарел — стопы col_* теперь ДИСПЛЕЙНЫЕ
данные (hex/255), а не linear inv_filmic. Записывать .tres им НЕЛЬЗЯ (формат
стопов изменён); оставлен как историческая механика арт-калибровки S3/S4.

palette_apply_s3.py — шаг S3 плана Q7.34: палитры 5 слотов из арт-референсов
contact_sheet_refs.png.

Метод (S3, заменяет swatch-only первый проход S1):
  1. Для каждого референса семплируются 5 PATCH-областей ЧИСТОГО КУПОЛА
     (медиана байтов по patch 6..24 px): glow, horizon, band, mid, anti.
     Swatch-полосы арта для купола неполны (S2/S4/S5: нет бирюзы/индиго/пастели),
     поэтому купол берётся из самого арта, а не из палитры арта.
  2. Байты → linear по ЦЕПИ A: linear = inv_filmic(srgb_to_linear(byte/255)).
  3. band2 = geomean(band, mid) — плавный мост; halo = glow*1.4.
  4. Монотонность яркости стопов (требование валидатора): при нарушении стоп
     затемняется скаляром (hue сохраняется): lum[i] := lum[i-1]*0.85.
  5. Пишутся .tres слотов с СОХРАНЕНИЕМ uid ресурса и preview (миниатюры
     пересохранятся из рендера на S4).

Сопоставление слотов (план §2.3): S1→07, S2→06, S3→02, S4→03, S5→09.
Запуск: python3 palette_apply_s3.py [sheet_png] [--write]
Без --write: только отчёт и проверки. С --write: перезапись 5 .tres.
"""
import os
import re
import sys

import palette_tool as pt

BASE = os.path.dirname(os.path.abspath(__file__))
PRESET_DIR = os.path.join(BASE, '..', 'SkyEnvironment', 'SkyPreset')
SHEET = os.path.join(BASE, '..', '..', '..', 'contact_sheet_refs.png')

# patch-области купола в координатах панели 320x328: (x0, y0, x1, y1)
PATCHES = {
    # значения — box (x0,y0,x1,y1) в координатах панели 320x328 либо '#RRGGBB' (swatch-якорь)
    'S1': {'glow': (166, 82, 174, 88), 'horizon': (146, 297, 154, 303), 'band': (152, 287, 158, 293),
           'mid': (166, 42, 174, 48), 'anti': (166, 27, 174, 33)},
    'S2': {'glow': '#FFD9A0', 'horizon': '#FF8F7A', 'band': (22, 147, 28, 153),
           'mid': (12, 147, 18, 153), 'anti': (22, 12, 28, 18)},
    'S3': {'glow': (166, 121, 174, 127), 'horizon': (166, 137, 174, 143), 'band': (106, 91, 114, 97),
           'mid': (56, 19, 64, 25), 'anti': (24, 5, 32, 11)},
    'S4': {'glow': (306, 66, 314, 72), 'horizon': (292, 99, 298, 105), 'band': (232, 99, 238, 105),
           'mid': (17, 7, 23, 13), 'anti': (12, 5, 18, 10)},
    'S5': {'glow': (157, 192, 163, 198), 'horizon': (162, 209, 168, 215), 'band': (157, 167, 163, 173),
           'mid': (157, 55, 163, 61), 'anti': (157, 27, 163, 33)},
}
SLOT_OF_REF = {'S1': 7, 'S2': 6, 'S3': 2, 'S4': 3, 'S5': 9}
REF_META = {
    'S1': dict(elev=-2.0, streak=0.4, key=(1.0, 0.62, 0.38), key_e=1.4),
    'S2': dict(elev=1.0, streak=0.2, key=(1.0, 0.72, 0.50), key_e=1.8),
    'S3': dict(elev=10.0, streak=0.0, key=(1.0, 0.85, 0.65), key_e=2.4),
    'S4': dict(elev=0.0, streak=0.4, key=(1.0, 0.75, 0.55), key_e=2.0),
    'S5': dict(elev=-5.0, streak=0.5, key=(1.0, 0.50, 0.32), key_e=1.0),
}
P_DEFAULT = [0.010, 0.075, 0.155, 0.300, 0.520, 1.0]

# Семантические overrides первого прохода: ('mul', src_stop, k) — затемнить от стопа src.
# S4: patch anti попал в ту же область лаванды, что и mid → антисоляр выводим из mid.
OVERRIDES = {
    'S4': {'anti': ('mul', 'mid', 0.55)},
}


def median_byte(get, ox, box):
    x0, y0, x1, y1 = box
    px = [get(ox + x, y) for y in range(y0, y1) for x in range(x0, x1)]
    return tuple(sorted(c[k] for c in px)[len(px) // 2] for k in range(3))


def build_stops(get, ox, ref):
    lin = {}
    raw = {}
    for name, box in PATCHES[ref].items():
        if isinstance(box, str):
            b = tuple(int(box[i:i + 2], 16) for i in (1, 3, 5))
        else:
            b = median_byte(get, ox, box)
        raw[name] = b
        lin[name] = pt.lin_from_byte_A(b)
    band2 = tuple((lin['band'][k] * lin['mid'][k]) ** 0.5 for k in range(3))
    lin['band2'] = band2
    for name, rule in OVERRIDES.get(ref, {}).items():
        kind, src, k = rule
        if kind == 'mul':
            lin[name] = tuple(lin[src][i] * k for i in range(3))
    stops = [lin['glow'], lin['horizon'], lin['band'], lin['band2'], lin['mid'], lin['anti']]
    # монотонность яркости (hue-preserving затемнение)
    fixed = []
    for i, s in enumerate(stops):
        s = list(s)
        if i > 0:
            l_prev = pt.lum(fixed[i - 1])
            l_cur = pt.lum(s)
            if l_cur >= l_prev * 0.97:
                k = (l_prev * 0.85) / max(l_cur, 1e-9)
                s = [v * k for v in s]
        fixed.append(tuple(s))
    halo = tuple(fixed[0][k] * 1.4 for k in range(3))
    return raw, fixed, halo


def check(stops, pos):
    errs = []
    lums = [pt.lum(s) for s in stops]
    if any(lums[i + 1] >= lums[i] for i in range(5)):
        errs.append('монотонность яркости нарушена')
    if any(pos[i + 1] - pos[i] < 0.01 for i in range(5)):
        errs.append('зазор стопов < 1%')
    for i in range(5):
        a, b = stops[i], stops[i + 1]
        if abs(a[0] - b[0]) < 1e-9 and abs(a[1] - b[1]) < 1e-9 and abs(a[2] - b[2]) < 1e-9:
            errs.append('соседние стопы совпадают (%d)' % i)
    return errs


def write_tres(slot, ref, stops, halo):
    path = os.path.join(PRESET_DIR, 'Preset_%02d.tres' % slot)
    old = open(path, encoding='utf-8').read()
    uid = re.search(r'uid="(uid://[^"]+)"\]', old).group(1)
    prev_m = re.search(r'\[ext_resource type="Texture2D"[^\n]*\n', old)
    prev_line = prev_m.group(0) if prev_m else ''
    prev_id = re.search(r'\sid="([^"]+)"', prev_line).group(1) if prev_line else None
    meta = REF_META[ref]
    L = []
    L.append('[gd_resource type="Resource" script_class="SkyPreset" format=3 uid="%s"]' % uid)
    L.append('')
    if prev_line:
        L.append(prev_line.rstrip('\n'))
    L.append('[ext_resource type="Script" uid="uid://c6o4hvxauaari" path="res://SkyEnvironment/SkyPreset.gd" id="2_script"]')
    L.append('[ext_resource type="Script" uid="uid://xpt0so3xggq8" path="res://SkyEnvironment/SkyLightProfile.gd" id="3_light"]')
    L.append('')
    L.append('[sub_resource type="Resource" id="light_%02d"]' % slot)
    L.append('script = ExtResource("3_light")')
    L.append('key_color = Color(%g, %g, %g, 1)' % meta['key'])
    L.append('key_energy = %g' % meta['key_e'])
    L.append('moon_light_color = Color(0.753, 0.784, 0.91, 1)')
    L.append('ambient_energy = 1.0')
    L.append('')
    L.append('[resource]')
    L.append('script = ExtResource("2_script")')
    L.append('preset_name = "%02d · ref %s sun%+d° (Q7.34 S3, купол из арта, цепь A)"' % (slot, ref, int(meta['elev'])))
    if prev_id:
        L.append('preview = ExtResource("%s")' % prev_id)
    L.append('sun_elevation = %g' % meta['elev'])
    L.append('sun_azimuth = 180.0')
    L.append('moon_elevation = 50.0')
    L.append('moon_azimuth = 0.0')
    names = ['col_glow', 'col_horizon', 'col_band', 'col_band2', 'col_mid', 'col_anti']
    for n, s in zip(names, stops):
        L.append('%s = Color(%.6f, %.6f, %.6f, 1)' % (n, s[0], s[1], s[2]))
    L.append('col_halo = Color(%.6f, %.6f, %.6f, 1)' % halo)
    for i, p in enumerate(P_DEFAULT):
        L.append('p%d = %g' % (i + 1, p))
    L.append('streak_int = %g' % meta['streak'])
    L.append('light = SubResource("light_%02d")' % slot)
    L.append('metadata/_custom_type_script = "uid://c6o4hvxauaari"')
    L.append('')
    return path, '\n'.join(L)


def main():
    write = '--write' in sys.argv
    sheet = sys.argv[1] if sys.argv[1:] and not sys.argv[1].startswith('--') else SHEET
    w, h, get = pt.read_png(sheet)
    report = []
    ok = True
    written = []
    for i, ref in enumerate(['S1', 'S2', 'S3', 'S4', 'S5']):
        ox = i * 320
        raw, stops, halo = build_stops(get, ox, ref)
        errs = check(stops, P_DEFAULT)
        ok &= not errs
        slot = SLOT_OF_REF[ref]
        report.append('== %s → слот %02d  patch-байты: %s' % (
            ref, slot, ' '.join('%s#%02X%02X%02X' % (k, *raw[k]) for k in ['glow', 'horizon', 'band', 'mid', 'anti'])))
        for n, s in zip(['glow', 'horizon', 'band', 'band2', 'mid', 'anti'], stops):
            report.append('   %-8s lin(%7.4f,%7.4f,%7.4f) lum=%.4f небо=%3d %3d %3d' % (
                n, s[0], s[1], s[2], pt.lum(s), *pt.byte_sky(s)))
        report.append('   проверки валидатора (зеркало): %s' % ('OK' if not errs else '; '.join(errs)))
        if write:
            path, text = write_tres(slot, ref, stops, halo)
            open(path, 'w', encoding='utf-8').write(text)
            written.append(path)
    print('\n'.join(report))
    if written:
        print('ЗАПИСАНО: %s' % ', '.join(os.path.basename(p) for p in written))
    print('S3 CHECK: %s' % ('PASS' if ok else 'FAIL'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
