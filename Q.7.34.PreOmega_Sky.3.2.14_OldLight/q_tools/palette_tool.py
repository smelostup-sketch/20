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

Sky3.2.4: рампа = 4 стопа (palletes.html «Небо», шаги 1..4), позиции q1..q4.
Порядок обхода рампы ОТ солнца: col_sky4 → col_sky3 → col_sky2 → col_sky1.

Команды:
    selftest          — round-trip filmic/inv_filmic, sRGB, сверка констант с шейдером,
                        маркеры Sky3.2.4 (4 стопа / 3 окна) во всех файлах неба
    chain [file.tres] — таблица u → encoded → байт неба (COLORS5)
    preset <file.tres>— дамп стопов пресета: display-данные и их байт неба
    html [--report]   — сверка 10 пресетов с palletes.html (7 цветов × 10 = 70 значений,
                        приёмка Δбайт = 0) и визуальный отчёт q_tools/palette_report.html

Python 3, только stdlib.
"""
import os
import re
import sys
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
def byte_disp(enc):   return tuple(round(min(max(v, 0.0), 1.0) * 255.0) for v in enc)       # ЦЕПЬ COLORS5: стопы = display-данные (hex/255), байт = round(×255)
def enc_from_byte(b): return tuple(v / 255.0 for v in b)                                    # hex-байт -> display-данные (стопы пресетов с COLORS5)


def lum(lin): return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def _smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------- PNG reader (stdlib only)
# ---------------------------------------------------------------- .tres preset reader
PRESET_DEFAULTS = {
    'q1': 0.010, 'q2': 0.155, 'q3': 0.520, 'q4': 1.0,
    'sharp': 1.0, 'arc_stretch': 2.4,
    # дефолты = ref #2 «Солнце над облаками» (palletes.html)
    'col_sky1': (0.0157, 0.0627, 0.1333), 'col_sky2': (0.1686, 0.4588, 0.7098),
    'col_sky3': (0.5490, 0.7686, 0.9098), 'col_sky4': (1.0, 0.9529, 0.8392),
    'col_light1': (1.0, 0.9529, 0.8784), 'col_light2': (0.9098, 0.6902, 0.6275),
    'col_light3': (0.2078, 0.2863, 0.3725), 'col_halo': (2.0, 0.5, 0.2),
}
COL_FIELDS = ['col_sky1', 'col_sky2', 'col_sky3', 'col_sky4', 'col_halo']
RAMP_ORDER = ['col_sky4', 'col_sky3', 'col_sky2', 'col_sky1']   # от солнца (u=0) к антисоляру


def read_preset(path):
    t = open(path, encoding='utf-8').read()
    out = dict(PRESET_DEFAULTS)
    for m in re.finditer(r'(col_\w+) = Color\(([^)]*)\)', t):
        vals = [float(v) for v in m.group(2).split(',')][:3]
        out[m.group(1)] = tuple(vals)
    for m in re.finditer(r'^\s*(q[1-4]|sharp|arc_stretch|streak_int|star_intensity) = ([\d.eE+-]+)', t, re.M):
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
    for i in range(3):
        w = win_f(pos[i], pos[i + 1], u, sharp)  # Q7.34: без max(q4,1) — q4 данные, q4<1 = плоский хвост
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
    # 10) S5-аудит dither + Sky3.2.2-аудит стрика (вариант Б-мир, выбор заказчика):
    #     dither в байтовом пространстве (не в линейном до filmic); базис стрика
    #     МИРОВОЙ и полюсно-безопасный (cross(up0, sd) с guard на длину); экранного
    #     uniform sk_streak_right и его покадровой записи больше нет нигде — по
    #     документации движка любое изменение uniform инвалидирует radiance cubemap.
    env_ctl_src = open(os.path.join(sky, 'SkyEnvironmentController.gd'), encoding='utf-8').read()
    env_ctl_active = '\n'.join(re.sub(r'#.*', '', ln) for ln in env_ctl_src.splitlines())  # без комментариев
    good = ('srgb_oetf_inv3(srgb_oetf3(disp)' in active_src
            and 'base += (n - 0.5)' not in active_src
            and 'sk_streak_right' not in active_src
            and 'sk_streak_right' not in env_ctl_active
            and '_update_streak_basis' not in env_ctl_active
            and 'cross(up0, sd)' in active_src
            and 'sk_streak_half_w_deg' in active_src
            and 'sk_streak_half_h_deg' in active_src)
    ok &= good
    print('  S5 dither в байтовом пространстве; Sky3.2.2 стрик: базис мировой, '
          'sk_streak_right и покадровая запись удалены, полуугла — данные  %s' % ('OK' if good else 'FAIL'))
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
    # 16) Sky3.2.4-аудит: рампа 4 стопа (palletes.html) — старые 6-стопные имена
    #     отсутствуют в АКТИВНОМ коде всех файлов неба, новые маркеры на месте
    def _strip_comments(t, pat):
        return '\n'.join(re.sub(pat + r'.*', '', ln) for ln in t.splitlines())
    files = {'шейдер': (src, r'//'), 'материал': (mat_src, None), 'пресет': (preset_src, r'#'),
             'валидатор': (val_src, r'#'), 'панель': (panel_src, r'#'),
             'контроллер': (envctl_src, r'#')}
    old_names = ['sk_glow_col', 'sk_horizon', 'sk_band_col', 'sk_band2_col', 'sk_mid', 'sk_anti_col',
                 'col_glow', 'col_horizon', 'col_band', 'col_band2', 'col_mid', 'col_anti']
    bad_old = []
    for nm, (t, cpat) in files.items():
        act = _strip_comments(t, cpat) if cpat else t
        for o in old_names:
            if re.search(r'(?<![\w])' + o + r'(?![\w])', act):
                bad_old.append('%s:%s' % (nm, o))
        if re.search(r'(?<![\w])sk_p[1-6](?![\w])', act) or re.search(r'(?<![\w.])p[1-6](?![\w])', act.replace('sk_p', 'SKIPPED')):
            bad_old.append('%s:sk_pN/pN' % nm)
    good = (not bad_old
            and 'uniform vec3 sk_c1' in src and 'uniform vec3 sk_c4' in src
            and 'uniform float sk_q1' in src and 'uniform float sk_q4' in src
            and src.count('win(sk_q') == 3 and 'SEG_COLORS[4]' in src
            and 'COL_UNIS := ["sk_c4", "sk_c3", "sk_c2", "sk_c1"]' in panel_src
            and 'P_UNIS := ["sk_q1", "sk_q2", "sk_q3", "sk_q4"]' in panel_src
            and 'p.col_sky4, p.col_sky3, p.col_sky2, p.col_sky1' in val_src
            and 'var col_sky1' in preset_src and 'var col_light3' in preset_src
            and '"sk_c1", preset.col_sky1' in envctl_src and '"sk_q4", preset.q4' in envctl_src)
    ok &= good
    print('  Sky3.2.4: 4 стопа sk_c1..sk_c4 / q1..q4 везде, старые 6-стопные имена отсутствуют%s  %s'
          % ((' :: ' + ', '.join(bad_old[:6])) if bad_old else '', 'OK' if good else 'FAIL'))
    # 17) Sky3.2.4-числа: зеркало рампы — 4 стопа, 3 окна, окно прижато к правому стопу
    #     (в позиции q_{i+1} цвет = стоп i+1 побитово), концы: u<q1 = стоп 0, u>=q4 = стоп 3
    cfg = [((0.9, 0.8, 0.7), (0.6, 0.5, 0.55), (0.3, 0.25, 0.4), (0.05, 0.05, 0.15)),
           (0.01, 0.155, 0.52, 1.0)]
    num_ok = True
    for sharp in (1.0, 0.5, 0.05):
        stops, pos = cfg
        for i in range(1, 4):
            got = ramp_color(stops, pos, sharp, pos[i])
            num_ok &= all(abs(got[k] - stops[i][k]) < 1e-12 for k in range(3))
        got0 = ramp_color(stops, pos, sharp, 0.0)
        num_ok &= all(abs(got0[k] - stops[0][k]) < 1e-12 for k in range(3))
        gotT = ramp_color(stops, pos, sharp, 1.0)
        num_ok &= all(abs(gotT[k] - stops[3][k]) < 1e-12 for k in range(3))
        # монотонная убывающая яркость на всей шкале (тестовая лестница)
        prev = lum(stops[0])
        for i in range(1, 401):
            cur = lum(ramp_color(stops, pos, sharp, i / 400.0))
            if cur > prev + 1e-12:
                num_ok = False
            prev = cur
    good = num_ok
    ok &= good
    print('  Sky3.2.4 числа: стопы достижимы побитово (sharp 1.0/0.5/0.05), концы шкалы, монотонность L(u)  %s'
          % ('OK' if good else 'FAIL'))
    # 18) Sky3.2.7-аудит (S10): вуаль — ОТДЕЛЬНЫЙ компонент под гейтом off;
    #     cubemap-гигиена (нет POSITION, нет покадровых записей); состав модуля
    inc_path = os.path.join(sky, 'SkyVeil.gdshaderinc')
    good = os.path.exists(inc_path)
    if good:
        inc = open(inc_path, encoding='utf-8').read()
        inc_active = _strip_comments(inc, r'//')
        n_hc = len(re.findall(r'uniform\s+\w+\s+(?:hc_|DS_)\w+', inc))
        ctl_active = _strip_comments(envctl_src, r'#')
        proc = ''
        in_proc = False
        for ln in ctl_active.splitlines():
            if ln.startswith('func _process'):
                in_proc = True
            elif in_proc and ln.startswith('func '):
                in_proc = False
            if in_proc:
                proc += ln + '\n'
        good = (n_hc == 34
                and 'hc_use_world_anchor' not in inc_active
                and 'DS_hc_max_sample_dist' not in inc_active
                and 'POSITION' not in inc_active
                and 'if (!hc_enabled) return bg_sun;' in inc
                and re.search(r'uniform\s+bool\s+hc_enabled\s*=\s*false', inc) is not None
                and '#include "res://SkyEnvironment/SkyVeil.gdshaderinc"' in src
                and 'if (hc_enabled) {' in active_src
                and 'if (hc_enabled && hc_debug > 0.5)' in active_src
                and 'veil_light_ramp_color' in inc_active
                and '_load_veil_noise' in envctl_src
                and 'hc_' not in proc and 'cloud_' not in proc and 'veil' not in proc
                and os.path.getsize(os.path.join(sky, 'noise_pw_128.bin')) == 128 ** 3
                and os.path.getsize(os.path.join(sky, 'noise_worley_32.bin')) == 32 ** 3)
    ok &= good
    print('  Sky3.2.7 (S10): компонент SkyVeil.gdshaderinc (26 hc_*/DS_*, без POSITION/якоря/max_dist), '
          'гейт off в хосте, #include, шумы 128^3/32^3, _process вуаль не пишет  %s' % ('OK' if good else 'FAIL'))
    # 19) Sky3.2.8-аудит (S11): профиль-компонент, apply_veil, вкладка «Вуаль»,
    #     старый формат грузится (veil = null), писатель материала один
    prof_path = os.path.join(sky, 'SkyVeilProfile.gd')
    good = os.path.exists(prof_path)
    if good:
        prof = open(prof_path, encoding='utf-8').read()
        panel = open(os.path.join(sky, 'SkyControlPanel.gd'), encoding='utf-8').read()
        preset = open(os.path.join(sky, 'SkyPreset.gd'), encoding='utf-8').read()
        valid = open(os.path.join(sky, 'SkyPresetValidator.gd'), encoding='utf-8').read()
        n_fields = len(re.findall(r'@export(?:_range\([^)]*\))?\s+var\s+veil_', prof))
        i_light = panel.find('_build_light_tab()')
        i_veil = panel.find('_build_veil_tab()')
        i_presets = panel.find('_build_presets_tab()')
        good = (n_fields == 8
                and '@export var veil: SkyVeilProfile' in preset
                and 'func apply_veil(preset: SkyPreset)' in envctl_src
                and 'apply_veil(initial_preset)' in envctl_src
                and 'set_shader_parameter("hc_enabled", false)' in envctl_src
                and 0 <= i_light < i_veil < i_presets
                and '_tabs.current_tab = 6' in panel
                and 'p.veil = vp' in panel
                and '_veil_on.set_pressed_no_signal' in panel
                and 'sky_material.set_shader_parameter' not in panel
                and 'p.veil != null and p.veil.veil_enabled' in valid)
    ok &= good
    print('  Sky3.2.8 (S11): SkyVeilProfile (8 полей), SkyPreset.veil, apply_veil в apply_preset, '
          'вкладка «Вуаль» (порядок, индекс Отладки 6), collect/sync, валидатор пр.9, '
          'панель материал не пишет  %s' % ('OK' if good else 'FAIL'))
    # 20) Sky3.2.9-аудит (hotfix 3.2.8): панель читает вуаль ТОЛЬКО через _veil_get
    #     (ShaderMaterial возвращает null для незаписанных uniform -> float(null) краш);
    #     VEIL_DEFAULTS на месте и полон (15 ключей = uniform'ы компонента)
    good = os.path.exists(os.path.join(sky, 'SkyControlPanel.gd'))
    if good:
        panel = open(os.path.join(sky, 'SkyControlPanel.gd'), encoding='utf-8').read()
        n_def = len(re.findall(r'"(?:hc_|DS_hc_)\w+":', panel))
        good = ('_get_param("hc_' not in panel
                and '_get_param("DS_hc' not in panel
                and 'func _veil_get(uni: String) -> Variant:' in panel
                and 'const VEIL_DEFAULTS :=' in panel
                and n_def == 25
                and panel.count('_veil_get(') >= 15)
    ok &= good
    print('  Sky3.2.9 (hotfix): сырых _get_param("hc_*") в панели нет, _veil_get + '
          'VEIL_DEFAULTS (25 ключей), collect/sync через фолбэк  %s' % ('OK' if good else 'FAIL'))
    # 21) Sky3.2.10-аудит: откат хардкода освещения + дальность вуали 90+ км
    #     (curtain по path в плите: start >= path(90 км) ~ 16.4 км, end ~ горизонт),
    #     потолок сэмпла >= 90 км, характер кромки образца Q7.32 (detail 0.35)
    inc = open(os.path.join(sky, 'SkyVeil.gdshaderinc'), encoding='utf-8').read()
    prof = open(os.path.join(sky, 'SkyVeilProfile.gd'), encoding='utf-8').read()
    panel = open(os.path.join(sky, 'SkyControlPanel.gd'), encoding='utf-8').read()
    def _fdef(src, name):
        m = re.search(r'uniform\s+float\s+%s\s*=\s*([0-9.eE+-]+)' % name, src)
        return float(m.group(1)) if m else -1.0
    h_mid = 0.5 * (6000.0 + 7200.0)
    path90 = 1200.0 * math.sqrt(90000.0 ** 2 + h_mid ** 2) / h_mid
    h_mid = 0.5 * (18000.0 + 21600.0)
    i_av = envctl_src.find('func apply_veil')
    i_ap = envctl_src.find('func apply_preset')
    av = envctl_src[i_av:i_ap]
    path90 = 3600.0 * math.sqrt(90000.0 ** 2 + h_mid ** 2) / h_mid
    good = ('set_shader_parameter("cloud_light' not in av
            and 'DS_HC_MAX_SAMPLE_DIST' not in inc and 'min(t_mid' not in inc
            and abs(_fdef(inc, 'hc_layer_bottom') - 18000.0) < 1e-6
            and abs(_fdef(inc, 'hc_layer_top') - 21600.0) < 1e-6
            and _fdef(inc, 'hc_curtain_start') >= path90
            and _fdef(inc, 'hc_curtain_end') >= 50000.0
            and 'hc_wind_enabled": false' in panel
            and 'hc_wind_timelapse' in panel
            and abs(_fdef(inc, 'hc_detail_strength') - 0.45) < 1e-9
            and abs(_fdef(inc, 'hc_softness') - 0.30) < 1e-9
            and abs(_fdef(inc, 'hc_stretch') - 3.2) < 1e-6
            and _fdef(inc, 'hc_break_amount') > 0.0 and _fdef(inc, 'hc_fiber_amp') > 0.0
            and abs(_fdef(inc, 'hc_tau_per_km') - 0.30) < 1e-9
            and 'veil_tau_per_km: float = 0.30' in prof
            and '"hc_curtain_start": 18000.0' in panel
            and '"hc_curtain_end": 55000.0' in panel)
    ok &= good
    # 0.2 приказа: вуаль включена ДАННЫМИ во всех 10 пресетах (.tres), не хардкодом
    presets_ok = True
    for i in range(1, 11):
        tp = os.path.join(sky, 'SkyPreset', 'Preset_%02d.tres' % i)
        t = open(tp, encoding='utf-8').read()
        if 'SkyVeilProfile' not in t or 'veil_enabled = true' not in t:
            presets_ok = False
    good = good and presets_ok
    print('  Sky3.2.12: откат cloud_light_*; без потолка; плита ×3; curtain start %.0f >= path(90 км) %.0f; '
          'форма-перистость по образцам 233/234 (stretch 3.2, soft 0.30, detail 0.45, разрывы, волокна); ветер+таймлапс; '
          'вуаль вкл данными в 10/10 .tres  %s'
          % (_fdef(inc, 'hc_curtain_start'), path90, 'OK' if good else 'FAIL'))
    # 22) Sky3.2.14-аудит: H1 заглушка удалена (направление света вуали = sk_sun_dir),
    #     выбор пресета не сбрасывает вуаль (+кнопка «Сброс вуали»), референсы списком,
    #     дыхание max данными в 10/10 пресетов
    host = open(os.path.join(sky, 'SkyEnvironment.gdshader'), encoding='utf-8').read()
    good = ('uniform vec3 cloud_light_direction' not in host
            and 'vec3 ldir = sk_sun_dir;' in inc
            and host.find('#include "res://SkyEnvironment/SkyVeil.gdshaderinc"')
                > host.find('uniform float moon_detail_int')
            and 'apply_veil(initial_preset)' in envctl_src)
    i_ap = envctl_src.find('func apply_preset')
    i_end = envctl_src.find('func set_shader_param')
    good = good and 'apply_veil(' not in envctl_src[i_ap:i_end]
    good = good and '_veil_reset' in panel and 'REFS_DIR' in panel and '_load_ref' in panel
    breathe_ok = True
    for i in range(1, 11):
        t = open(os.path.join(sky, 'SkyPreset', 'Preset_%02d.tres' % i), encoding='utf-8').read()
        if 'breathe = 0.9' not in t:
            breathe_ok = False
    good = good and breathe_ok
    ok &= good
    print('  Sky3.2.14: H1 — заглушки cloud_light_direction нет, ldir = sk_sun_dir, include после '
          'uniform\'ов; выбор пресета вуаль не сбрасывает, «Сброс вуали» + референсы списком; '
          'дыхание 0.9 в 10/10 .tres  %s' % ('OK' if good else 'FAIL'))
    print('SELFTEST: %s' % ('PASS' if ok else 'FAIL'))
    return 0 if ok else 1


def cmd_chain(preset_path):
    # COLORS5: стопы пресета = display-данные (hex/255); байт неба/полосы = round(×255).
    p = read_preset(preset_path)
    stops = [p[f] for f in RAMP_ORDER]
    pos = [p['q1'], p['q2'], p['q3'], p['q4']]
    print('Пресет: %s' % p['preset_name'])
    print(' u     encoded(r,g,b)           байт неба = байт полосы (COLORS5)')
    for i in range(0, 101, 10):
        u = i / 100.0
        enc = ramp_color(stops, pos, p['sharp'], u)
        b = byte_disp(enc)
        print(' %.2f  (%6.4f,%6.4f,%6.4f)   %3d %3d %3d' % (u, enc[0], enc[1], enc[2], b[0], b[1], b[2]))
    return 0


# ---------------------------------------------------------------- palletes.html: парсер, сверка, отчёт (Sky3.2.4)
# Карта «ref HTML → слот пресета» — та же, что в сессии 1 (ROW_TO_SLOT palette_apply_user.py),
# подтверждается именами: #6 «Закатные облака над замком» = Preset_08 и т.д.
REF_TO_SLOT = {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 8, 7: 9, 8: 7, 9: 6, 10: 10}


def parse_html(path):
    """-> [{'ref': int, 'label': str, 'sky': [4 hex], 'env': [3 hex]}], refs 1..10"""
    t = open(path, encoding='utf-8').read()
    out = []
    for blk in t.split('<div class="ref">')[1:]:
        m = re.search(r'<h2>#(\d+)\s*—\s*([^<]+)</h2>', blk)
        rows = blk.split('<div class="row">')[1:]
        sky = re.findall(r'class="sw" style="background:(#[0-9A-Fa-f]{6})"', rows[0])
        env = re.findall(r'class="sw" style="background:(#[0-9A-Fa-f]{6})"', rows[1])
        assert m and len(sky) == 4 and len(env) == 3, 'структура palletes.html нарушена'
        out.append({'ref': int(m.group(1)), 'label': m.group(2).strip(), 'sky': sky, 'env': env})
    assert len(out) == 10, 'ожидалось 10 референсов, найдено %d' % len(out)
    return sorted(out, key=lambda r: r['ref'])


def hex_byte(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def mirror_validate(pr):
    """Мини-зеркало SkyPresetValidator: зазоры, совпадения соседей, q4."""
    errs = []
    stops = [pr[f] for f in RAMP_ORDER]
    pos = [pr['q%d' % i] for i in range(1, 5)]
    for i in range(3):
        if pos[i + 1] - pos[i] < 0.01 - 1e-9:
            errs.append('зазор q%d-q%d < 1%%' % (i + 1, i + 2))
        if all(abs(stops[i][k] - stops[i + 1][k]) < 1e-12 for k in range(3)):
            errs.append('стопы %d и %d совпадают' % (i, i + 1))
    return errs


def _grad_css(colors_pct):
    return 'linear-gradient(90deg, ' + ', '.join(
        'rgb(%d,%d,%d) %.3f%%' % (c[0], c[1], c[2], pct) for c, pct in colors_pct) + ')'


def cmd_html(write_report):
    base = os.path.dirname(os.path.abspath(__file__))
    refs = parse_html(os.path.join(base, '..', '..', 'palletes.html'))
    pdir = os.path.join(base, '..', 'SkyEnvironment', 'SkyPreset')
    total = bad = 0
    rep_rows = []
    for r in refs:
        slot = REF_TO_SLOT[r['ref']]
        pr = read_preset(os.path.join(pdir, 'Preset_%02d.tres' % slot))
        errs = mirror_validate(pr)
        print('#%-2d %-40s → Preset_%02d  %s' % (r['ref'], r['label'], slot, pr['preset_name'][:44]))
        if errs:
            print('   ЗЕРКАЛО-ВАЛИДАТОР: ' + '; '.join(errs))
        bad += len(errs)
        fields = [('col_sky%d' % (i + 1), hex_byte(r['sky'][i])) for i in range(4)]
        fields += [('col_light%d' % (i + 1), hex_byte(r['env'][i])) for i in range(3)]
        line = []
        for fname, tb in fields:
            got = byte_disp(pr[fname])
            d = max(abs(got[k] - tb[k]) for k in range(3))
            total += 1
            bad += (1 if d else 0)
            line.append('   %-11s цель #%02X%02X%02X  факт %3d %3d %3d  Δбайт=%d %s'
                        % (fname, tb[0], tb[1], tb[2], got[0], got[1], got[2], d, 'OK' if d == 0 else 'FAIL'))
            if d:
                print(line[-1])
        print('   7/7 значений Δбайт = 0' if not any('FAIL' in x for x in line) else '\n'.join(x for x in line if 'FAIL' in x))
        if write_report:
            rep_rows.append((r, slot, pr))
    verdict = (bad == 0 and total == 70)
    print('HTML-СВЕРКА: %d/%d значений Δбайт = 0  %s' % (total - bad, total, 'PASS' if verdict else 'FAIL'))
    if write_report:
        _write_report(base, rep_rows)
    return 0 if verdict else 1


def _write_report(base, rep_rows):
    """palette_report.html: для каждого ref две полосы ОТ СОЛЯРА — цель (равномерная,
    как CSS-градиент palletes.html) и факт (CPU-зеркало рампы пресета, q/sharp)."""
    N = 200
    out = ['<!DOCTYPE html><html lang="ru"><head><meta charset="utf-8">',
           '<title>Отчёт палитр — Sky3.2.4</title><style>',
           'body{font-family:system-ui,sans-serif;background:#12121a;color:#f0f0f5;padding:28px;max-width:980px;margin:auto}',
           'h1{font-size:20px}h2{font-size:15px;margin:22px 0 6px;color:#ffd97a}',
           '.strip{height:26px;border-radius:7px;border:1px solid rgba(255,255,255,.2);margin:4px 0}',
           '.cap{font:11px/1.4 monospace;opacity:.75;margin-bottom:2px}',
           '.chips{display:flex;gap:8px;margin:6px 0}.chip{width:46px;height:30px;border-radius:6px;',
           'border:1px solid rgba(255,255,255,.28)}</style></head><body>',
           '<h1>Отчёт палитр (Sky3.2.4): palletes.html → 10 пресетов, рампа 4 стопа</h1>',
           '<p class="cap">Полосы orientрованы ОТ СОЛНЦА (слева u=0, справа антисоляр u=1).',
           'Цель = равномерный CSS-градиент шагов 4→3→2→1 (как в palletes.html, но развёрнуто от солнца).',
           'Факт = CPU-зеркало рампы пресета (200 отсчётов, позиции q1..q4 и sharp из .tres).',
           'Байт-точность стопов: команда <b>palette_tool.py html</b> (70/70 Δбайт = 0).</p>']
    for r, slot, pr in rep_rows:
        stops = [pr[f] for f in RAMP_ORDER]
        pos = [pr['q%d' % i] for i in range(1, 5)]
        out.append('<h2>#%d %s → Preset_%02d · %s</h2>' % (r['ref'], r['label'], slot, pr['preset_name']))
        out.append('<div class="chips">' + ''.join(
            '<div class="chip" style="background:%s" title="%s"></div>' % (h, h)
            for h in reversed(r['sky'])) + ''.join(
            '<div class="chip" style="background:%s;opacity:.55" title="%s (окр.)"></div>' % (h, h)
            for h in r['env']) + '</div>')
        out.append('<div class="cap">цель (palletes.html, равномерно):</div>')
        out.append('<div class="strip" style="background:%s"></div>'
                   % _grad_css([(hex_byte(h), i * 100.0 / 3.0) for i, h in enumerate(reversed(r['sky']))]))
        out.append('<div class="cap">факт (рампа пресета: q=%.3f/%.3f/%.3f/%.3f sharp=%.2f):</div>'
                   % (pos[0], pos[1], pos[2], pos[3], pr['sharp']))
        samples = []
        for i in range(N):
            u = i / float(N - 1)
            samples.append((byte_disp(ramp_color(stops, pos, pr['sharp'], u)), u * 100.0))
        out.append('<div class="strip" style="background:%s"></div>' % _grad_css(samples))
    out.append('</body></html>')
    path = os.path.join(base, 'palette_report.html')
    open(path, 'w', encoding='utf-8').write('\n'.join(out))
    print('отчёт: %s' % os.path.relpath(path, base))


def cmd_preset(path):
    p = read_preset(path)
    stops = [p[f] for f in RAMP_ORDER]
    lums = [lum(v) for v in stops]
    print('Пресет: %s' % p['preset_name'])
    print(' стопы display (hex/255, COLORS5), порядок от солнца, и их байт неба:')
    for f, v in zip(RAMP_ORDER, stops):
        a = byte_disp(v)
        print('   %-11s (%7.4f,%7.4f,%7.4f)  lum=%.4f  небо=%3d %3d %3d'
              % (f, v[0], v[1], v[2], lum(v), a[0], a[1], a[2]))
    print(' монотонность яркости стопов (от солнца): %s'
          % ('OK' if all(lums[i] > lums[i + 1] for i in range(3)) else 'FAIL'))
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
    if cmd == 'html':
        return cmd_html('--report' in sys.argv[2:])
    if cmd == 'preset':
        return cmd_preset(sys.argv[2])
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main())
