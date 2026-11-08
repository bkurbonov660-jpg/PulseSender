#!/usr/bin/env python3
"""Генерирует иконку 512x512 (зелёный фон, play + эквалайзер) без PIL."""
import sys, zlib, struct

SIZE = 512
out = sys.argv[1] if len(sys.argv) > 1 else "icon.png"

def inside(x, y):
    # треугольник play
    if 140 <= x <= 300:
        k = (x - 140) * 106.0 / 160.0
        if 150 + k <= y <= 362 - k:
            return True
    # три полоски эквалайзера
    for x0, x1, hh in ((330, 366, 55), (386, 422, 100), (442, 478, 70)):
        if x0 <= x <= x1 and abs(y - 256) <= hh:
            return True
    return False

rows = []
for y in range(SIZE):
    t = y / (SIZE - 1.0)
    br = int(46 + (27 - 46) * t)
    bg = int(125 + (94 - 125) * t)
    bb = int(50 + (32 - 50) * t)
    row = bytearray([0])
    for x in range(SIZE):
        c = 0
        for dy in (0.25, 0.75):
            for dx in (0.25, 0.75):
                if inside(x + dx, y + dy):
                    c += 1
        a = c / 4.0
        row += bytes((int(br + (255 - br) * a),
                      int(bg + (255 - bg) * a),
                      int(bb + (255 - bb) * a)))
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
