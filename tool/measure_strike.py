#!/usr/bin/env python3
"""Измеряет линию зачёркивания на PNG из `tool/render_strike_preview.dart`.

Зачем: смотреть картинку «на глаз» через скриншот в чате — ненадёжно, а
сравнивать «было/стало» нужно объективно. Здесь по пикселям считаются
ровно те величины, из которых складывается впечатление:

  * толщина линии по вертикали (min/median/max) в пикселях;
  * амплитуда волны (размах середины линии по столбцам);
  * гладкость: насколько РЕЗКО меняется толщина от столбца к столбцу
    (рывки = «зубцы», из-за них линия читается рваной, а не змейкой);
  * обрез по краям текста: сколько столбцов с линией выходит за ширину
    самой длинной строки.

Запуск: python3 tool/measure_strike.py /tmp/strike_preview.png
"""
import sys
import zlib
import struct


def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'не PNG'
    pos, idat, w, h = 8, b'', 0, 0
    bit_depth = color_type = None
    while pos < len(data):
        (length,) = struct.unpack('>I', data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if ctype == b'IHDR':
            w, h, bit_depth, color_type = struct.unpack('>IIBB', body[:10])
        elif ctype == b'IDAT':
            idat += body
        elif ctype == b'IEND':
            break
        pos += 12 + length
    assert bit_depth == 8 and color_type in (2, 6), (bit_depth, color_type)
    channels = 3 if color_type == 2 else 4
    raw = zlib.decompress(idat)
    stride = w * channels
    px = bytearray(w * h * channels)
    prev = bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        if f == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        px[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, channels, px


def is_strike(r, g, b):
    """Линия — красная (brand алый или rose). Текст — тёмно-серый/чёрный."""
    return r > 90 and r - g > 45 and r - b > 45


def analyze(path):
    w, h, ch, px = read_png(path)
    stride = w * ch

    # Собираем по строкам (y): где вообще есть красные пиксели.
    row_has = []
    for y in range(h):
        found = False
        for x in range(w):
            i = y * stride + x * ch
            if is_strike(px[i], px[i + 1], px[i + 2]):
                found = True
                break
        row_has.append(found)

    # Непрерывные полосы по y — это отдельные строки текста.
    bands, start = [], None
    for y, has in enumerate(row_has):
        if has and start is None:
            start = y
        elif not has and start is not None:
            bands.append((start, y - 1))
            start = None
    if start is not None:
        bands.append((start, h - 1))

    print(f'строк с линией: {len(bands)}')
    for bi, (y0, y1) in enumerate(bands):
        cols = []
        for x in range(w):
            top = bot = None
            for y in range(y0, y1 + 1):
                i = y * stride + x * ch
                if is_strike(px[i], px[i + 1], px[i + 2]):
                    if top is None:
                        top = y
                    bot = y
            if top is not None:
                cols.append((x, top, bot, bot - top + 1))
        if not cols:
            continue
        thick = [c[3] for c in cols]
        mids = [(c[1] + c[2]) / 2 for c in cols]
        smooth, win = [], 9
        for i in range(len(mids)):
            lo, hi = max(0, i - win), min(len(mids), i + win + 1)
            chunk = sorted(mids[lo:hi])
            smooth.append(chunk[len(chunk) // 2])
        jumps = sorted(abs(thick[i] - thick[i - 1]) for i in range(1, len(thick)))
        p90 = jumps[int(len(jumps) * 0.9)] if jumps else 0
        print(
            f'  строка {bi + 1}: x {cols[0][0]}..{cols[-1][0]}, '
            f'толщина min {min(thick)} / med {sorted(thick)[len(thick) // 2]} / max {max(thick)}, '
            f'волна {max(smooth) - min(smooth):.1f} px, рывки 90п {p90}'
        )


if __name__ == '__main__':
    analyze(sys.argv[1] if len(sys.argv) > 1 else '/tmp/strike_preview.png')
