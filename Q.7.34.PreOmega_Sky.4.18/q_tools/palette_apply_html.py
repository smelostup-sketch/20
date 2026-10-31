#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
palette_apply_html.py — Sky3.2.4: миграция и наполнение 10 пресетов неба
из `palletes.html` (корень репо). Единственный источник цвета — HTML; никакого
приглушения (сессия-1 MUTE_TONES/L×0.76/S×0.70 УДАЛЕНЫ: ТЗ задачи 3 требует
визуального соответствия палитре = байт-точности, архитектура COLORS5 её
гарантирует: стопы = display-данные hex/255, байт экрана на стопе = hex).

Что пишется в Preset_NN.tres (хирургически, остальное байт-в-байт):
  col_sky1..col_sky4   — строка «Небо», шаги 1..4 (hex/255)
  col_light1..col_light3 — строка «Окружение», шаги 1..3 (hex/255; применение
                         света — шаг …3.2.5, здесь только данные)
  q1..q4               — форма рампы, МИГРАЦИЯ из старой p-лестницы:
                         q1=p1 (край ядра), q2=p3, q3=p5, q4=p6 (антисоляр).
                         Промежуточные p2/p4 схлопываются: стопов стало 4.
  preset_name          — «NN · <название ref> (Q7.34, palletes.html)»
  col_halo НЕ трогается (единственный linear-HDR цвет, данные ключей, не палитра).

Запуск:
  python3 palette_apply_html.py            — dry-run: план + зеркало-валидатор
  python3 palette_apply_html.py --write    — записать .tres
После записи приёмка:  python3 palette_tool.py html --report  (70/70 Δбайт = 0).

Python 3, только stdlib.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette_tool as pt   # noqa: E402  (парсер HTML, зеркало рампы, byte_disp)

BASE = os.path.dirname(os.path.abspath(__file__))
PRESET_DIR = os.path.join(BASE, '..', 'SkyEnvironment', 'SkyPreset')
HTML = os.path.join(BASE, '..', '..', 'palletes.html')

OLD_COLS = ['col_glow', 'col_horizon', 'col_band', 'col_band2', 'col_mid', 'col_anti']
OLD_P = ['p%d' % i for i in range(1, 7)]


def read_old(path):
    """Старый .tres: p1..p6 (новый read_preset их уже не читает)."""
    t = open(path, encoding='utf-8').read()
    out = {'p%d' % i: d for i, d in zip(range(1, 7), (0.010, 0.075, 0.155, 0.300, 0.520, 1.0))}
    for m in re.finditer(r'^\s*(p[1-6]) = ([\d.eE+-]+)', t, re.M):
        out[m.group(1)] = float(m.group(2))
    return out


def patch_tres(text, slot, label, sky_enc, env_enc, q):
    lines = text.splitlines(keepends=True)
    out, inserted = [], False

    def fmt(name, c):
        return '%s = Color(%.6f, %.6f, %.6f, 1)\n' % (name, c[0], c[1], c[2])

    for ln in lines:
        head = ln.split(' = ')[0].strip()
        if head in OLD_COLS or head in OLD_P or head.startswith('col_light') or re.match(r'^q[1-4]$', head):
            if not inserted:   # на месте первого старого поля — новый блок
                for i in range(4):
                    out.append(fmt('col_sky%d' % (i + 1), sky_enc[i]))
                for i in range(3):
                    out.append(fmt('col_light%d' % (i + 1), env_enc[i]))
                for i in range(4):
                    out.append('q%d = %s\n' % (i + 1, ('%g' % q[i])))
                inserted = True
            continue           # старые col_*/p*/col_light*/q* — удаляем
        out.append(ln)
    if not inserted:           # страховка: блок не встретил старых полей — вставить перед [resource]-хвостом
        block = [fmt('col_sky%d' % (i + 1), sky_enc[i]) for i in range(4)]
        block += [fmt('col_light%d' % (i + 1), env_enc[i]) for i in range(3)]
        block += ['q%d = %g\n' % (i + 1, q[i]) for i in range(4)]
        k = next((i for i, l in enumerate(out) if l.startswith('metadata/')), len(out))
        out[k:k] = block
    text = ''.join(out)
    return re.sub(r'^preset_name = "[^"]*"',
                  'preset_name = "%02d · %s (Q7.34, palletes.html)"' % (slot, label),
                  text, flags=re.M)


def main():
    write = '--write' in sys.argv
    refs = pt.parse_html(HTML)
    ok = True
    for r in refs:
        slot = pt.REF_TO_SLOT[r['ref']]
        path = os.path.join(PRESET_DIR, 'Preset_%02d.tres' % slot)
        old = read_old(path)
        sky_enc = [pt.enc_from_byte(pt.hex_byte(h)) for h in r['sky']]     # шаги 1..4
        env_enc = [pt.enc_from_byte(pt.hex_byte(h)) for h in r['env']]     # L1..L3
        q = [old['p1'], old['p3'], old['p5'], old['p6']]
        # байт-точность по построению: round(hex/255 × 255) == hex
        for h, e in list(zip(r['sky'], sky_enc)) + list(zip(r['env'], env_enc)):
            assert tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) == pt.byte_disp(e), h
        # зеркало-валидатор на планируемых данных (ramп-порядок от солнца: sky4..sky1)
        pr = {'col_sky4': sky_enc[3], 'col_sky3': sky_enc[2], 'col_sky2': sky_enc[1], 'col_sky1': sky_enc[0],
              'q1': q[0], 'q2': q[1], 'q3': q[2], 'q4': q[3]}
        errs = pt.mirror_validate(pr)
        ok &= not errs
        print('== ref #%d %-38s → Preset_%02d' % (r['ref'], r['label'], slot))
        print('   небо (шаги 1..4): %s' % ' '.join(r['sky']))
        print('   окружение L1..L3: %s' % ' '.join(r['env']))
        print('   форма: p(%s) → q(%s)' % (
            ' '.join('%g' % old['p%d' % i] for i in range(1, 7)),
            ' '.join('%g' % v for v in q)))
        print('   зеркало-валидатор: %s' % ('OK' if not errs else '; '.join(errs)))
        if write:
            text = patch_tres(open(path, encoding='utf-8').read(), slot, r['label'], sky_enc, env_enc, q)
            assert len(text) > 500 and 'col_sky1' in text and 'col_glow' not in text, 'patch_tres сбой'
            open(path, 'w', encoding='utf-8').write(text)
            print('   ЗАПИСАН %s' % os.path.basename(path))
    print('APPLY_HTML: %s%s' % ('OK' if ok else 'FAIL', '' if write else '  (dry-run; запись: --write)'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
