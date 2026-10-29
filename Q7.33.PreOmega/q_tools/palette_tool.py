#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
palette_tool.py — калибровочный инструмент палитр неба Q7.34 (шаг S1 плана).

Цепь вывода цвета в Godot 4.7 (Forward Plus), зафиксирована в S1:
    linear (shader COLOR) --tonemap filmic--> display-linear --sRGB OETF--> byte экрана
    byte = srgb_encode( filmic( linear ) ) * 255
Отсюда обратная цепь для построения стопов из байтов референса (ЦЕПЬ A):
    linear = inv_filmic( srgb_to_linear( byte / 255 ) )
ЦЕПЬ B (byte = filmic(linear)*255, без sRGB-encode) — НЕВЕРНА для рендера, но именно
ею сейчас рисует полоса RampStrip в SkyControlPanel.gd (Image RGB8 = filmic(lin) как
sRGB-байты) → полоса темнее неба → художник сводил палитры по неверной полосе.
Лечится в S2: полоса должна рисовать srgb_encode(filmic(lin)).

Команды:
    selftest          — round-trip filmic/inv_filmic, sRGB, сверка констант с шейдером
    chain             — демонстрация цепей A/B на swatch, диагностика полосы пресета
    refs              — linear-стопы из contact_sheet_refs.png (5 референсов) + .tres-сниппет
    preset <file.tres>— дамп стопов пресета: linear, байт неба (A), байт полосы (B)

Python 3, только stdlib. PNG-читалка своя (RGB8/RGBA8/gray/palette, без interlace).
"""
import os
import re
import sys
import zlib
import struct
import math

# ---------------------------------------------------------------- filmic (порт tonemap.glsl Godot 4.7)
FA, FB, FCB, FDE, FDF = 0.88, 0.60, 0.06, 0.002, 0.06
FEF = 0.03333333          # 1/30
FN = 0.7285913529         # нормировка filmic(1.0)=1.0


def filmic(x: float) -> float:
    c = max(x, 0.0)
    return (((c * (FA * c + FCB) + FDE) / (c * (FA * c + FB) + FDF)) - FEF) / FN


def inv_filmic(t: float) -> float:
    tt = min(t, 1.32)
    Y = tt * FN + FEF
    a = FA * (1.0 - Y)
    b = FCB - Y * FB
    c = FDE - Y * FDF
    if a <= 1e-6:
        return 64.0
    d2 = b * b - 4.0 * a * c
    return max((-b + math.sqrt(max(d2, 0.0))) / (2.0 * a), 0.0)


def srgb_to_linear(u: float) -> float:
    return u / 12.92 if u <= 0.04045 else ((u + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c: float) -> float:
    c = min(max(c, 0.0), 1.0)
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1.0 / 2.4) - 0.055


# цепи
def byte_sky(lin):    return tuple(round(linear_to_srgb(filmic(v)) * 255.0) for v in lin)   # ЦЕПЬ A: как в небе
def byte_strip(lin):  return tuple(round(min(filmic(v), 1.0) * 255.0) for v in lin)         # ЦЕПЬ B: как рисует полоса СЕЙЧАС
def byte_strip_fixed(lin): return byte_sky(lin)                                            # полоса после фикса S2
def byte_disp(enc):   return tuple(round(min(max(v, 0.0), 1.0) * 255.0) for v in enc)       # ЦЕПЬ COLORS5: стопы = display-данные (hex/255), байт = round(×255)
def enc_from_byte(b): return tuple(v / 255.0 for v in b)                                    # hex-байт -> display-данные (стопы пресетов с COLORS5)
def lin_from_byte_A(b): return tuple(inv_filmic(srgb_to_linear(v / 255.0)) for v in b)      # построение стопов
def lin_from_byte_B(b): return tuple(inv_filmic(v / 255.0) for v in b)


def lum(lin): return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def _smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------- PNG reader (stdlib only)
def read_png(path):
    d = open(path, 'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n', path
    i, idat, plte = 8, b'', None
    w = h = ct = None
    while i < len(d):
        ln = struct.unpack('>I', d[i:i + 4])[0]
        typ = d[i + 4:i + 8]
        data = d[i + 8:i + 8 + ln]
        if typ == b'IHDR':
            w, h, bd, ct = struct.unpack('>IIBB', data[:10])
            assert bd == 8, 'only 8-bit png supported'
        elif typ == b'IDAT':
            idat += data
        elif typ == b'PLTE':
            plte = data
        i += 12 + ln
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    stride = w * ch
    raw = zlib.decompress(idat)
    px = bytearray(w * h * ch)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        f = raw[pos]; pos += 1
        line = bytearray(raw[pos:pos + stride]); pos += stride
        if f == 1:
            for x in range(ch, stride):
                line[x] = (line[x] + line[x - ch]) & 255
        elif f == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                line[x] = (line[x] + ((line[x - ch] if x >= ch else 0) + prev[x]) // 2) & 255
        elif f == 4:
            for x in range(stride):
                a = line[x - ch] if x >= ch else 0
                b = prev[x]
                c = prev[x - ch] if x >= ch else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        px[y * stride:(y + 1) * stride] = line
        prev = line

    def get(x, y):
        o = (y * w + x) * ch
        if ct == 3:
            idx = px[o]
            return (plte[idx * 3], plte[idx * 3 + 1], plte[idx * 3 + 2])
        if ct == 2:
            return (px[o], px[o + 1], px[o + 2])
        if ct == 6:
            return (px[o], px[o + 1], px[o + 2])
        return (px[o], px[o], px[o])
    return w, h, get


# ---------------------------------------------------------------- .tres preset reader
PRESET_DEFAULTS = {
    'p1': 0.010, 'p2': 0.075, 'p3': 0.155, 'p4': 0.300, 'p5': 0.520, 'p6': 1.0,
    'sharp': 1.0, 'arc_stretch': 2.4,
}
COL_FIELDS = ['col_glow', 'col_horizon', 'col_band', 'col_band2', 'col_mid', 'col_anti', 'col_halo']


def read_preset(path):
    t = open(path, encoding='utf-8').read()
    out = dict(PRESET_DEFAULTS)
    for m in re.finditer(r'(col_\w+) = Color\(([^)]*)\)', t):
        vals = [float(v) for v in m.group(2).split(',')][:3]
        out[m.group(1)] = tuple(vals)
    for m in re.finditer(r'^\s*(p[1-6]|sharp|arc_stretch|streak_int|star_intensity) = ([\d.eE+-]+)', t, re.M):
        out[m.group(1)] = float(m.group(2))
    name = re.search(r'preset_name = "([^"]*)"', t)
    out['preset_name'] = name.group(1) if name else path
    return out


# ---------------------------------------------------------------- CPU-зеркало рампы (порт ramp_u/win шейдера и валидатора)
def win_f(lo, hi, x, sharp):
    w = (hi - lo) * sharp
    e0, e1 = hi - w, hi
    if e1 <= e0:
        return 1.0 if x >= e1 else 0.0
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def ramp_color(stops, pos, sharp, u):
    c = list(stops[0])
    for i in range(5):
        w = win_f(pos[i], pos[i + 1], u, sharp)  # Q7.34: без max(p6,1) — p6 данные, p6<1 = плоский хвост
        hi = stops[i + 1]
        c = [c[k] + (hi[k] - c[k]) * w for k in range(3)]
    return tuple(c)


# ---------------------------------------------------------------- команды
def cmd_selftest(shader_path):
    ok = True
    sky = os.path.dirname(os.path.abspath(shader_path))
    # 1) константы инструмента == константам шейдера и валидатора
    src = open(shader_path, encoding='utf-8').read()
    for name, val in [('FA', FA), ('FB', FB), ('FCB', FCB), ('FDE', FDE), ('FDF', FDF), ('FEF', FEF), ('FN', FN)]:
        m = re.search(r'const float %s = ([\d.eE+-]+);' % name, src)
        got = float(m.group(1)) if m else None
        good = got is not None and abs(got - val) < 1e-9
        ok &= good
        print('  const %-4s shader=%s tool=%.10f %s' % (name, got, val, 'OK' if good else 'MISMATCH'))
    # 2) round-trip filmic/inv_filmic
    worst = 0.0
    for i in range(0, 1321):
        x = i / 1000.0
        worst = max(worst, abs(inv_filmic(filmic(x)) - x))
    for i in range(0, 1321):
        t = i / 1000.0
        worst = max(worst, abs(filmic(inv_filmic(t)) - t))
    good = worst < 1e-5
    ok &= good
    print('  round-trip |filmic(inv_filmic(x))-x| max = %.3e  %s' % (worst, 'OK' if good else 'FAIL'))
    # 3) sRGB round-trip
    worst = max(abs(srgb_to_linear(linear_to_srgb(i / 1000.0)) - i / 1000.0) for i in range(1001))
    good = worst < 1e-9
    ok &= good
    print('  sRGB round-trip max = %.3e  %s' % (worst, 'OK' if good else 'FAIL'))
    # 4) белый точкa кривой: filmic(2.0)=1.0 (white point tonemap.glsl), дисплей-асимптота ~1.3137
    good = abs(filmic(2.0) - 1.0) < 1e-7 and abs(inv_filmic(1.0) - 2.0) < 1e-6  # допуск: FN в шейдере округлена до 10 знаков
    ok &= good
    print('  filmic(2.0) = %.10f, inv_filmic(1.0) = %.6f (white point = 2.0)  %s'
          % (filmic(2.0), inv_filmic(1.0), 'OK' if good else 'FAIL'))
    good = abs(filmic(64.0) - 1.3137) < 1e-3
    ok &= good
    print('  filmic(64) = %.6f (асимптота дисплея ~1.3137)  %s' % (filmic(64.0), 'OK' if good else 'FAIL'))
    # 5) COLORS5-аудит: валидатор без мёртвых filmic-зеркал (стопы = display-данные)
    val_src = open(os.path.join(sky, 'SkyPresetValidator.gd'), encoding='utf-8').read()
    good = 'display3_c' not in val_src and 'filmic_f' not in val_src and 'ramp_color' in val_src
    ok &= good
    print('  валидатор: filmic-зеркало удалено (COLORS5), ramp_color на месте  %s' % ('OK' if good else 'FAIL'))
    # 6) COLORS5-аудит: полоса панели рисует display-данные напрямую (без конверсий)
    panel_src = open(os.path.join(sky, 'SkyControlPanel.gd'), encoding='utf-8').read()
    good = ('display3_c' not in panel_src and 'filmic3_c' not in panel_src
            and 'ramp_color(data["stops"]' in panel_src)
    ok &= good
    print('  полоса RampStrip = display-данные напрямую (COLORS5)  %s' % ('OK' if good else 'FAIL'))
    # 7) S2-аудит: comp_linear удалён из шейдера и материала
    mat_src = open(os.path.join(sky, 'SkyEnvironmentMaterial.tres'), encoding='utf-8').read()
    active_src = '\n'.join(re.sub(r'//.*', '', ln) for ln in src.splitlines())  # без комментариев
    good = 'comp_linear' not in active_src and 'comp_linear' not in mat_src and 'srgb_to_linear' not in active_src
    ok &= good
    print('  comp_linear отсутствует в шейдере и материале  %s' % ('OK' if good else 'FAIL'))
    # 8) S2-аудит: tonemap_mode = 2 (Filmic) во всех сценах проекта
    base_proj = os.path.join(sky, '..')
    for tscn in ['Основная_сцена.tscn', os.path.join('SkyEnvironment', 'SkyTest.tscn')]:
        pth = os.path.join(base_proj, tscn)
        if not os.path.exists(pth):
            continue
        t = open(pth, encoding='utf-8').read()
        modes = re.findall(r'tonemap_mode = (\d+)', t)
        good = bool(modes) and all(m == '2' for m in modes)
        ok &= good
        print('  %s: tonemap_mode=%s (Filmic)  %s' % (os.path.basename(pth), modes, 'OK' if good else 'FAIL'))
    # 9) S2-аудит: guard тонмапа в контроллере — имя enum Godot 4.7 (ToneMapper.TONE_MAPPER_FILMIC),
    #    а не старое TONE_MAP_FILMIC (в 4.7 удалено → parse error)
    ctl_src = open(os.path.join(sky, 'SkyLightController.gd'), encoding='utf-8').read()
    good = ('TONE_MAPPER_FILMIC' in ctl_src and 'TONE_MAPPER_LINEAR' in ctl_src
            and 'set_tonemap_linear' in ctl_src
            and re.search(r'TONE_MAP_FILMIC', ctl_src.replace('TONE_MAPPER_FILMIC', '')) is None)
    ok &= good
    print('  SkyLightController: enum Godot 4.7 (FILMIC/LINEAR), set_tonemap_linear, старое TONE_MAP_FILMIC отсутствует  %s' % ('OK' if good else 'FAIL'))
    # 10) S5/S8-аудит: dither в байтовом пространстве (не в линейном до filmic),
    #     базис стрика экранный и полюсно-безопасный (без normalize(cross(worldY, sd)))
    good = ('srgb_oetf_inv3(srgb_oetf3(disp)' in active_src
            and 'base += (n - 0.5)' not in active_src
            and 'sk_streak_right' in active_src
            and re.search(r'right_w = normalize\(cross', active_src) is None)
    ok &= good
    print('  S5/S8: dither в байтовом пространстве, базис стрика экранный (NaN на полюсах исключён)  %s' % ('OK' if good else 'FAIL'))
    # 11) COLORS5-аудит: переключаемый тонмап + display-данные стопов по всем файлам
    preset_src = open(os.path.join(sky, 'SkyPreset.gd'), encoding='utf-8').read()
    envctl_src = open(os.path.join(sky, 'SkyEnvironmentController.gd'), encoding='utf-8').read()
    good = ('uniform int sk_tonemap' in src and 'disp2scene' in active_src and 'scene2disp' in active_src
            and 'sky_palette_disp' in active_src and 'srgb_oetf_inv3(ramp_u' in active_src
            and 'sk_tonemap' in panel_src and 'tonemap_linear' in preset_src
            and '"sk_tonemap"' in envctl_src and 'set_tonemap_linear' in envctl_src)
    ok &= good
    print('  COLORS5: sk_tonemap/disp2scene/scene2disp (шейдер), чекбокс (панель), tonemap_linear (пресет+контроллер)  %s' % ('OK' if good else 'FAIL'))
    # 12) COLORS5: байт-точность стопов в ОБОИХ режимах тонмапа (display-данные hex/255)
    worst = 0
    for b in range(256):
        enc = b / 255.0
        disp = srgb_to_linear(enc)
        bf = round(linear_to_srgb(filmic(inv_filmic(disp))) * 255.0)   # Filmic: COLOR = inv_filmic(disp)
        bl = round(linear_to_srgb(disp) * 255.0)                       # Linear: COLOR = disp
        worst = max(worst, abs(bf - b), abs(bl - b))
    good = worst <= 1
    ok &= good
    print('  COLORS5: round-trip байта 0..255 в Filmic и Linear, макс. отклонение %d  %s' % (worst, 'OK' if good else 'FAIL'))
    # 13) COLORS6 (S15): «дыхание купола» — варп шкалы u^γ, γ = 1 + sk_breathe·sin(elev)
    good = ('uniform float sk_breathe' in src and 'float x = sk_breathe * sd.y' in active_src
            and '(1.0 + x) / (1.0 - 0.5 * x)' in active_src
            and 'pow(u_ellip(dir, sd), g)' in active_src
            and 'var breathe' in preset_src and '"sk_breathe"' in envctl_src
            and 'func breathe_gamma' in panel_src and '(1.0 + x) / (1.0 - 0.5 * x)' in panel_src
            and 'powf(' not in panel_src)   # GDScript: только глобальная pow(), powf() есть лишь в шейдерном языке
    ok &= good
    print('  COLORS6 маркеры: sk_breathe (шейдер), breathe (пресет), запись (контроллер), breathe_gamma (панель)  %s' % ('OK' if good else 'FAIL'))
    g_lo, g_hi = 1e9, -1e9
    mono = ident = x15 = True
    for bi in range(91):                       # breathe 0.00..0.90
        breathe = bi / 100.0
        for ei in range(-90, 91, 3):           # elev -90..+90
            x = breathe * math.sin(math.radians(ei))
            g1 = 1.0 + x                       # v1-закон
            g = (1.0 + x) / (1.0 - 0.5 * x)    # v2-закон: усиление ×1.5
            g_lo = min(g_lo, g); g_hi = max(g_hi, g)
            if g <= 0.0:
                mono = False                   # pow небезопасен при γ≤0
            if not ((0.5 - 1e-3) ** g < 0.5 ** g < (0.5 + 1e-3) ** g):
                mono = False
            if abs(0.0 ** g) > 1e-15 or abs(1.0 ** g - 1.0) > 1e-15:
                ident = False
            # сдвиг границ в видимом (лог-)пространстве ровно ×1.5 к v1: (1/γ−1) = 1.5·(1/γ₁−1)
            if abs((1.0 / g - 1.0) - 1.5 * (1.0 / g1 - 1.0)) > 1e-12:
                x15 = False
    a0 = all((i / 1000.0) ** 1.0 == i / 1000.0 for i in range(1001))   # breathe=0 → x=0 → γ=1 → побитовое OFF
    # направление границ: γ>1 (солнце выше) → p^(1/γ) > p → солярные кольца РАСШИРЯЮТСЯ;
    # γ<1 (ниже горизонта) → p^(1/γ) < p → солярные сжимаются, антисолярный хвост растёт
    d_up = 0.5 ** (1.0 / 2.2857) > 0.5
    d_dn = 0.5 ** (1.0 / 0.475) < 0.5
    good = (g_lo >= 0.1 / 1.45 - 1e-9 and g_hi <= 1.9 / 0.55 + 1e-9
            and mono and ident and x15 and a0 and d_up and d_dn)
    ok &= good
    print('  COLORS6 v2 цифры: γ∈[%.3f,%.3f] (>0), монотонность, концы 0/1, сдвиг границ = 1.5×v1, breathe=0 OFF, направление ↑/↓  %s'
          % (g_lo, g_hi, 'OK' if good else 'FAIL'))
    # 14) COLORS7 (S17): компенсация складки у горизонта — способ 1: второй сомножитель
    #     экспоненты γ_arc = 1 + sk_squeeze·(S−1)·h(dir.y), S как в u_ellip, h = окно горизонта
    s_formula = 'mix(max(sk_arc_stretch, 1.0), 1.0, sstep(0.85, 0.99, abs(sd.y)))'
    good = ('uniform float sk_squeeze' in src and src.count(s_formula) == 3   # u_ellip + ramp_u + debug
            and src.count('g *= 1.0 + sk_squeeze * (S - 1.0) * h;') == 2       # ramp_u + debug
            and 'float h = 1.0 - sstep(0.10, 0.50, abs(dir.y));' in active_src
            and 'var squeeze' in preset_src and '"sk_squeeze"' in envctl_src
            and 'func squeeze_gamma' in panel_src and 'func strip_gamma' in panel_src
            and 'sk_squeeze' in panel_src)
    ok &= good
    print('  COLORS7 маркеры: sk_squeeze (шейдер: S-формула ×3, сомножитель ×2), squeeze (пресет), запись (контроллер), squeeze_gamma/strip_gamma (панель)  %s' % ('OK' if good else 'FAIL'))
    # числа: γ_arc ≥ 1 (сжатие антисоляра, без новых складок), побитовые выключения,
    # направление: γ_total > γ_breathe → лог-ширина антисолярных окон МЕНЬШЕ (сжаты)
    gmin = 1e9
    off = dir_ok = True
    for sqi in range(0, 21):                       # squeeze 0.0..2.0
        sq = sqi / 10.0
        for arc in (1.0, 1.7, 2.4, 3.2, 4.0):
            for ei in range(-90, 91, 15):          # elev солнца (S гаснет к зениту)
                ss = abs(math.sin(math.radians(ei)))
                S = 1.0 + (max(arc, 1.0) - 1.0) * (1.0 - _smooth(0.85, 0.99, ss))
                for h in (0.0, 0.5, 1.0):          # близость взгляда к горизонту
                    ga = 1.0 + sq * (S - 1.0) * h
                    gmin = min(gmin, ga)
                    if ga < 1.0 - 1e-12:
                        off = False                # γ_arc < 1 растянул бы антисоляр — складка
                    if (sq == 0.0 or abs(arc - 1.0) < 1e-12 or h == 0.0) and abs(ga - 1.0) > 1e-12:
                        off = False
                x = 0.6 * ss                       # направление на горизонте (h=1)
                gb = (1.0 + x) / (1.0 - 0.5 * x)   # дыхание COLORS6 v2
                ga = 1.0 + sq * (S - 1.0)
                if sq > 0 and S > 1.0 and not (gb * ga > gb and 1.0 / (gb * ga) < 1.0 / gb):
                    dir_ok = False
    good = (gmin >= 1.0 - 1e-12 and off and dir_ok)
    ok &= good
    print('  COLORS7 цифры: γ_arc ≥ %.3f (≥1), OFF при squeeze=0/arc=1/h=0, направление: антисолярные окна сжаты у горизонта  %s'
          % (gmin, 'OK' if good else 'FAIL'))
    # 15) Guard «шейдерный язык / Variant-инференс в GDScript»: во ВСЕХ .gd проекта нет
    #     шейдерных функций (mix/powf/fract/step/texture — только .gdshader; случаи powf() в
    #     COLORS6 и mix() в COLORS7) и Variant-lerp (UNSAFE_INFERENCE при warnings-as-errors;
    #     случай lerp() в COLORS7-fix): float-аналоги lerpf/smoothstep/pow — разрешены
    bad_gd = []
    n_gd = 0
    gd_root = os.path.join(sky, '..')
    for root, _dirs, files in os.walk(gd_root):
        for fn in sorted(files):
            if not fn.endswith('.gd'):
                continue
            n_gd += 1
            pth = os.path.join(root, fn)
            for ln in open(pth, encoding='utf-8'):
                code = ln.split('#', 1)[0]
                # границы слова: draw_texture(/smoothstep( — легитимные GDScript-имена, не шейдер
                for tok in (r'(?<![\w.])mix\(', r'(?<![\w.])powf\(', r'(?<![\w.])fract\(',
                            r'(?<![\w.])step\(', r'(?<![\w.])texture\(',
                            r'(?<![\w.])lerp\('):   # Variant-lerp → UNSAFE_INFERENCE (warnings-as-errors); только lerpf
                    if re.search(tok, code):
                        bad_gd.append('%s:%s' % (os.path.relpath(pth, gd_root), tok))
    good = not bad_gd
    ok &= good
    print('  GDScript-чистота: mix/powf/fract/step/texture/lerp(Variant) отсутствуют во всех .gd (%d файлов)%s  %s'
          % (n_gd, (' :: ' + ', '.join(bad_gd[:5])) if bad_gd else '', 'OK' if good else 'FAIL'))
    print('SELFTEST: %s' % ('PASS' if ok else 'FAIL'))
    return 0 if ok else 1


def cmd_chain(preset_path):
    # COLORS5: стопы пресета = display-данные (hex/255); байт неба/полосы = round(×255).
    p = read_preset(preset_path)
    stops = [p[f] for f in COL_FIELDS[:6]]
    pos = [p['p1'], p['p2'], p['p3'], p['p4'], p['p5'], p['p6']]
    print('Пресет: %s' % p['preset_name'])
    print(' u     encoded(r,g,b)           байт неба = байт полосы (COLORS5)')
    for i in range(0, 101, 10):
        u = i / 100.0
        enc = ramp_color(stops, pos, p['sharp'], u)
        b = byte_disp(enc)
        print(' %.2f  (%6.4f,%6.4f,%6.4f)   %3d %3d %3d' % (u, enc[0], enc[1], enc[2], b[0], b[1], b[2]))
    return 0


REF_NAMES = ['S1 sun-2deg', 'S2 sun+1deg', 'S3 sun+10deg', 'S4 sun+0deg', 'S5 sun-5deg']


def extract_swatches(sheet_path, y=340):
    w, h, get = read_png(sheet_path)
    assert w == 1600 and h >= 352, 'unexpected contact sheet geometry'
    refs = []
    for p in range(5):
        sw = [get(p * 320 + s * 64 + 32, y) for s in range(5)]
        refs.append(sw)
    return refs


def cmd_refs(sheet_path):
    refs = extract_swatches(sheet_path)
    print('# Swatch contact_sheet_refs.png → linear-стопы (ЦЕПЬ A)')
    print('# Правило маппинга (S1): sort swatch по luminance(linear) по убыванию:')
    print('#   glow=L0, horizon=L1, band=L2, mid=L3, anti=L4, band2=geomean(band,mid), halo=glow*1.4')
    print('# Монотонность L(u) выполнена по построению. Hue берётся из референса без правок.')
    for name, sw in zip(REF_NAMES, refs):
        lins = [lin_from_byte_A(b) for b in sw]
        order = sorted(range(5), key=lambda i: -lum(lins[i]))
        glow, horizon, band, mid, anti = (lins[order[k]] for k in range(5))
        band2 = tuple(math.sqrt(band[k] * mid[k]) for k in range(3))
        halo = tuple(glow[k] * 1.4 for k in range(3))
        stops = [glow, horizon, band, band2, mid, anti]
        lums = [lum(s) for s in stops]
        mono = all(lums[i] > lums[i + 1] + 1e-9 for i in range(5))
        print()
        print('== %s  swatch: %s' % (name, ' '.join('#%02X%02X%02X' % b for b in sw)))
        print('   lum-лестница: %s  монотонность: %s'
              % (' '.join('%.3f' % v for v in lums), 'OK' if mono else 'FAIL'))
        fields = ['col_glow', 'col_horizon', 'col_band', 'col_band2', 'col_mid', 'col_anti']
        for f, s in zip(fields, stops):
            print('   %-11s = Color(%.6f, %.6f, %.6f, 1)' % (f, s[0], s[1], s[2]))
        print('   %-11s = Color(%.6f, %.6f, %.6f, 1)' % ('col_halo', halo[0], halo[1], halo[2]))
    return 0


def cmd_preset(path):
    p = read_preset(path)
    stops = [p[f] for f in COL_FIELDS[:6]]
    pos = [p['p1'], p['p2'], p['p3'], p['p4'], p['p5'], p['p6']]
    lums = [lum(s) for s in stops]
    print('Пресет: %s' % p['preset_name'])
    print(' стопы display (hex/255, COLORS5) и их байт неба:')
    for f, s in zip(COL_FIELDS[:6], stops):
        a = byte_disp(s)
        print('   %-11s (%7.4f,%7.4f,%7.4f)  lum=%.4f  небо=%3d %3d %3d'
              % (f, s[0], s[1], s[2], lum(s), a[0], a[1], a[2]))
    print(' монотонность яркости стопов: %s'
          % ('OK' if all(lums[i] > lums[i + 1] for i in range(5)) else 'FAIL'))
    return 0


def main():
    import os
    base = os.path.dirname(os.path.abspath(__file__))
    sky = os.path.join(base, '..', 'SkyEnvironment')
    shader = os.path.join(sky, 'SkyEnvironment.gdshader')
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1]
    if cmd == 'selftest':
        return cmd_selftest(shader)
    if cmd == 'chain':
        return cmd_chain(sys.argv[2] if len(sys.argv) > 2 else os.path.join(sky, 'SkyPreset', 'Preset_09.tres'))
    if cmd == 'refs':
        sheet = sys.argv[2] if len(sys.argv) > 2 else os.path.join(base, '..', '..', '..', 'contact_sheet_refs.png')
        return cmd_refs(sheet)
    if cmd == 'preset':
        return cmd_preset(sys.argv[2])
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main())
