#!/usr/bin/env python3
"""Генерирует иконку 512x512 для PulseAgent v2.0 (фон индиго #3F51B5 + белый символ ИИ-агента) без PIL."""
import sys, zlib, struct, math

SIZE = 512
out = sys.argv[1] if len(sys.argv) > 1 else "assets/icon/icon.png"

def inside_icon(x, y):
    cx, cy = 256.0, 256.0
    dx, dy = x - cx, y - cy
    dist = math.hypot(dx, dy)
    if 165 <= dist <= 185:
        return True
    if abs(dx) <= 95 and abs(dy) <= 75:
        if math.hypot(dx + 40, dy + 10) < 18 or math.hypot(dx - 40, dy + 10) < 18:
            return False
        if abs(dx) <= 45 and 22 <= dy <= 34:
            return False
        return True
    if abs(dx) <= 10 and -130 <= dy <= -75:
        return True
    if math.hypot(dx, dy + 140) <= 18:
        return True
    return False

rows = []
for y in range(SIZE):
    t = y / (SIZE - 1.0)
    br = int(63 + (40 - 63) * t)
    bg = int(81 + (53 - 81) * t)
    bb = int(181 + (147 - 181) * t)
    row = bytearray([0])
    for x in range(SIZE):
        hits = 0
        for sy in (0.25, 0.75):
            for sx in (0.25, 0.75):
                if inside_icon(x + sx, y + sy):
                    hits += 1
        a = hits / 4.0
        r = int(br + (255 - br) * a)
        g = int(bg + (255 - bg) * a)
        b = int(bb + (255 - bb) * a)
        row += bytes((r, g, b))
    rows.append(bytes(row))

def chunk(tag, data):
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xffffffff)

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
png += chunk(b"IEND", b"")

with open(out, "wb") as f:
    f.write(png)
print("icon written:", out)
