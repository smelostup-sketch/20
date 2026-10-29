#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
palette_apply_user.py — шаг S4C плана Q7.34: ПАЛИТРЫ ЗАКАЗЧИКА (CSV) в стопы пресетов.

Источник истины по цветам — csv заказчика (копии лежат рядом КАК .txt:
palettes_user_1-5.txt, palettes_user_6-10.txt — Godot импортит любой .csv в res://
как файл переводов и ломает импорт проекта). Арт-калибровки S3/S4 ими ПОЛНОСТЬЮ
заменены (черновик).

Формат csv: строка = слот (по порядку 1..10), колонки:
  Шаг 1 (верх) … Шаг 6 (низ/свет) — sRGB-байты экрана сверху вниз по куполу.
Маппинг на стопы рампы (обратный порядок, источник = низ):
  col_glow   = Шаг 6   col_band2 = Шаг 3
  col_horizon= Шаг 5   col_mid   = Шаг 2
  col_band   = Шаг 4   col_anti  = Шаг 1
ПРИГЛУШЕНИЕ (Q7.34 COLORS4, запрос заказчика 29.10: «на пару-тройку тонов ниже,
блеклее»): каждый hex csv параметрически пересчитывается mute_hex() в HSL
(display-пространство): L×(1−0.08·T), S×(1−0.10·T), T = MUTE_TONES = 3.
Не хардкод: регулировка одной константой, csv не изменяются.
COLORS5: стопы col_* = ДИСПЛЕЙНЫЕ ДАННЫЕ (приглушённый hex/255, encoded sRGB) —
шейдер смешивает их в кодированном пространстве (плавный градиент) и декодирует
один раз; байт экрана на стопе = приглушённый hex побайтово в ОБОИХ режимах
тонмапа (Filmic/Linear, sk_tonemap). col_halo = linear(glow)*1.4 (правило S3,
единственный linear-HDR цвет).
Монотонная яркость не навязывается: немонотонность (арт-слои, слоты 04/06)
разрешена — правило валидатора понижено до warning (S4C).
Позиции p1..p6 НЕ ТРОГАЮТСЯ (хардкод «по высотам 0/18/…/90°» из COLORS3 откатан
по указанию заказчика 29.10); калибровка градиента — доли% с замочками в панели
(SkyControlPanel, COLORS4).

.tres правится хирургически: col_*, col_halo, preset_name; остальное байт-в-байт.
Зеркало SkyPresetValidator (правила 1-8, монотонность = warning) + check_set —
по набору 10 слотов; ошибки обязаны быть пусты.

Запуск: python3 palette_apply_user.py [--write] [--check-png OUT.png] [--mute N]
"""
import colorsys
import csv
import io
import os
import re
import struct
import sys
import zlib

import palette_tool as pt

BASE = os.path.dirname(os.path.abspath(__file__))
PRESET_DIR = os.path.join(BASE, '..', 'SkyEnvironment', 'SkyPreset')
# .txt, НЕ .csv: Godot импортит любой .csv в res:// как файл переводов
# (CSV-translation importer) и ломает импорт проекта (ошибка 29.10.2026).
CSV_FILES = ['palettes_user_1-5.txt', 'palettes_user_6-10.txt']
# Q7.34 (COLORS2, 29.10.2026): путаница заказчика в нумерации строк 6-9 — палитры
# едут в слоты по.preview-арту слота: строка 6 -> слот 8, 7 -> 9, 8 -> 7, 9 -> 6.
# Строки 1-5 и 10 — на своих местах. Csv не правим (данные заказчика), маппинг здесь.
ROW_TO_SLOT = {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 8, 7: 9, 8: 7, 9: 6, 10: 10}
MIN_GAP = 0.01

# COLORS5: col_* — ДИСПЛЕЙНЫЕ ДАННЫЕ (hex/255); col_halo — единственный linear HDR.
COL_DEFAULTS = {'col_glow': (1.0, 0.7677, 0.5545), 'col_horizon': (0.9552, 0.7177, 0.6073),
                'col_band': (0.8067, 0.6868, 0.8379), 'col_band2': (0.6506, 0.6506, 0.8635),
                'col_mid': (0.4389, 0.5299, 0.7177), 'col_anti': (0.1586, 0.2036, 0.3794),
                'col_halo': (2.0, 0.5, 0.2)}


# ---------------------------------------------------------------- приглушение (Q7.34 COLORS4)
# Заказчик (29.10): «цвета на пару-тройку тонов ниже, блеклее». НЕ хардкод hex:
# параметрический пересчёт в display-пространстве (HSL). Один «тон» = −8% светлоты
# и −10% насыщенности (мультипликативно: чёрный остаётся чёрным, hue не крутится).
# MUTE_TONES = 3 → L×0.76, S×0.70. Регулировка одной цифрой: MUTE_TONES.
MUTE_TONES = 3
MUTE_L_PER_TONE = 0.08
MUTE_S_PER_TONE = 0.10


def mute_hex(h):
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5))
    hue, lig, sat = colorsys.rgb_to_hls(r, g, b)
    lig = max(0.0, lig * (1.0 - MUTE_L_PER_TONE * MUTE_TONES))
    sat = max(0.0, sat * (1.0 - MUTE_S_PER_TONE * MUTE_TONES))
    r, g, b = colorsys.hls_to_rgb(hue, lig, sat)
    return '#%02X%02X%02X' % (round(r * 255.0), round(g * 255.0), round(b * 255.0))


def load_preset(path):
    pr = pt.read_preset(path)
    for k, v in COL_DEFAULTS.items():
        pr.setdefault(k, v)
    pr['has_light'] = 'light = SubResource' in open(path, encoding='utf-8').read()
    return pr


def read_rows():
    """-> {slot: (label, [6 hex сверху вниз])}"""
    out = {}
    slot = 0
    for fn in CSV_FILES:
        rows = csv.reader(io.open(os.path.join(BASE, fn), encoding='utf-8-sig'))
        for r in rows:
            if not r or not r[0].strip() or r[0].startswith(('Референс', 'Пресет')):
                continue
            slot += 1
            label = re.sub(r'^\d+\.\s*', '', r[0].strip())
            out[ROW_TO_SLOT[slot]] = (label, [h.strip() for h in r[1:7]])
    return out


def hex_byte(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def mirror_validate(pr):
    errs, warns = [], []
    stops = [pr['col_glow'], pr['col_horizon'], pr['col_band'],
             pr['col_band2'], pr['col_mid'], pr['col_anti']]
    pos = [pr['p%d' % i] for i in range(1, 7)]
    names = ['glow', 'horizon', 'band', 'band2', 'mid', 'anti']
    for i in range(5):
        if pos[i + 1] - pos[i] < MIN_GAP - 1e-9:
            errs.append('зазор p%d-p%d < 1%%' % (i + 1, i + 2))
    for i in range(5):
        if all(abs(stops[i][k] - stops[i + 1][k]) < 1e-12 for k in range(3)):
            errs.append('стопы %s==%s' % (names[i], names[i + 1]))
    prev = pt.lum(stops[0])
    viol = 0
    for i in range(1, 201):                                   # монотонность = WARNING (S4C)
        u = pr['p1'] + (1.0 - pr['p1']) * i / 200.0
        cur = pt.lum(pt.ramp_color(stops, pos, pr['sharp'], u))
        if cur >= prev - 1e-12:
            viol += 1
        prev = cur
    if viol:
        warns.append('монотонность L(u): %d нарушений (арт-слой, разрешено)' % viol)
    if pos[5] < 1.0:
        warns.append('p6=%.3f < 1.0' % pos[5])
    for i in range(5):
        if (pos[i + 1] - pos[i]) * pr['sharp'] < 0.02:
            warns.append('окно p%d->p%d почти скачок' % (i + 1, i + 2))
    for i in range(6):
        if max(stops[i]) > 1.0 + 1e-6:
            warns.append('стоп %s: канал > 1 — данные должны быть display hex/255 (COLORS5)' % names[i])
    return errs, warns


def mirror_check_set(presets):
    warns = []
    items = [(n, p) for n, p in sorted(presets.items())
             if p is not None and p.get('has_light', True)]
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            a, b = items[i][1], items[j][1]
            if all(a['p%d' % k] == b['p%d' % k] for k in range(1, 6)):
                warns.append('форма p1..p5 идентична: %02d и %02d' % (items[i][0], items[j][0]))
    return warns


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
                 'preset_name = "%02d · %s (Q7.34, палитра заказчика)"' % (slot, label),
                 old, flags=re.M)
    return old


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


def render_check(path, rows):
    """rows: [(slot, label, hexes_csv, hexes_muted, stops)] — слева swatchи заказчика
    (csv как есть), рядом — приглушённые (то, что загружено), справа рампа слота
    в байтах неба (цепь A)."""
    sw_w, rh, strip_w = 48, 120, 240
    W = sw_w * 2 + 8 + 4 + strip_w
    H = (rh + 6) * len(rows)
    buf = bytearray(W * H * 3)

    def put(x, y, c):
        i = (y * W + x) * 3
        buf[i:i + 3] = bytes(c)

    for r, (slot, label, hexes, hexes_m, stops) in enumerate(rows):
        y0 = r * (rh + 6)
        for k in range(6):                                   # 6 swatchей сверху вниз
            ya, yb = y0 + k * rh // 6, y0 + (k + 1) * rh // 6
            b0 = tuple(int(hexes[k][i:i + 2], 16) for i in (1, 3, 5))
            b1 = tuple(int(hexes_m[k][i:i + 2], 16) for i in (1, 3, 5))
            for y in range(ya, yb):
                for x in range(sw_w):
                    put(x, y, b0)                            # csv оригинал
                for x in range(sw_w + 4, sw_w * 2 + 4):
                    put(x, y, b1)                            # приглушённый (загружен)
        pr = load_preset(os.path.join(PRESET_DIR, 'Preset_%02d.tres' % slot))
        pos = [pr['p%d' % i] for i in range(1, 7)]
        for y in range(rh):
            u = y / (rh - 1.0)
            c = pt.byte_disp(pt.ramp_color(stops, pos, 1.0, u))
            for x in range(sw_w * 2 + 8 + 4, W):
                put(x, y0 + y, c)
    write_png(path, W, H, buf)


def main():
    global MUTE_TONES
    write = '--write' in sys.argv
    if '--mute' in sys.argv:                     # COLORS5: ручка приглушения из CLI
        MUTE_TONES = int(sys.argv[sys.argv.index('--mute') + 1])
    check_png = None
    if '--check-png' in sys.argv:
        check_png = sys.argv[sys.argv.index('--check-png') + 1]
    rows_csv = read_rows()
    report, ok, rows = [], True, []
    for slot in sorted(rows_csv):
        label, hexes = rows_csv[slot]
        hexes_m = [mute_hex(h) for h in hexes]               # приглушение (параметр MUTE_TONES)
        bts = [hex_byte(h) for h in hexes_m]
        encs = [tuple(b / 255.0 for b in bb) for bb in bts]  # COLORS5: стопы = display hex/255
        stops = [encs[5], encs[4], encs[3], encs[2], encs[1], encs[0]]   # glow..anti
        glow_lin = pt.lin_from_byte_A(bts[5])                # halo — linear HDR (правило S3)
        halo = tuple(glow_lin[k] * 1.4 for k in range(3))
        pr = load_preset(os.path.join(PRESET_DIR, 'Preset_%02d.tres' % slot))
        planned = dict(pr)
        for n, s in zip(['col_glow', 'col_horizon', 'col_band', 'col_band2', 'col_mid', 'col_anti'], stops):
            planned[n] = s
        errs, warns = mirror_validate(planned)
        ok &= not errs
        report.append('== слот %02d · %s' % (slot, label))
        report.append('   csv:        %s' % ' '.join(hexes))
        report.append('   приглушено (MUTE_TONES=%d, L×%.2f S×%.2f): %s' % (
            MUTE_TONES, 1.0 - MUTE_L_PER_TONE * MUTE_TONES, 1.0 - MUTE_S_PER_TONE * MUTE_TONES,
            ' '.join(hexes_m)))
        for n, st, h in zip(['glow', 'horizon', 'band', 'band2', 'mid', 'anti'],
                            stops, reversed(hexes_m)):
            report.append('   %-8s %s -> disp(%6.4f,%6.4f,%6.4f) небо=%3d %3d %3d' % (
                n, h, st[0], st[1], st[2], *pt.byte_disp(st)))
            assert pt.byte_disp(st) == hex_byte(h), 'байт стопа != приглушённый hex'
        report.append('   зеркало валидатора: %s%s' % (
            'OK' if not errs else '; '.join(errs),
            (' | warn: ' + '; '.join(warns)) if warns else ''))
        if write:
            path = os.path.join(PRESET_DIR, 'Preset_%02d.tres' % slot)
            text = patch_tres(path, slot, label, stops, halo)
            assert len(text) > 500, 'patch_tres вернул пустышку'
            open(path, 'w', encoding='utf-8').write(text)
            report.append('   ЗАПИСАН %s' % os.path.basename(path))
        rows.append((slot, label, hexes, hexes_m, stops))

    report.append('== НАБОР: зеркало SkyPresetValidator по 10 слотам')
    presets = {n: load_preset(os.path.join(PRESET_DIR, 'Preset_%02d.tres' % n))
               for n in range(1, 11)}
    set_errs = 0
    for n in sorted(presets):
        e, w = mirror_validate(presets[n])
        set_errs += len(e)
        report.append('   %02d %-52s errors=%d warns=%d%s' % (
            n, presets[n]['preset_name'][:52], len(e), len(w),
            (' :: ' + '; '.join(e + w)) if (e or w) else ''))
    sw = mirror_check_set(presets)
    report.append('   check_set: %s' % ('; '.join(sw) if sw else 'предупреждений нет'))
    report.append('   ИТОГО ошибок по набору: %d' % set_errs)
    ok &= (set_errs == 0)
    print('\n'.join(report))
    if check_png and rows:
        render_check(check_png, rows)
    print('S4C CHECK: %s' % ('PASS' if ok else 'FAIL'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
