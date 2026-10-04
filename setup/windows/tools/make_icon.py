#!/usr/bin/env python3
"""Generate a small .ico for the Squirrel setup programs (no external deps)."""
import struct
import sys


def build(size: int = 256) -> bytes:
    rows = bytearray()
    edge = max(8, size // 14)
    glyph = [(0.375, 0.30, 0.625, 0.70), (0.30, 0.45, 0.70, 0.58)]
    cell = max(4, size // 16)
    for _y in range(size):          # ICO/BMP rows are stored bottom-up
        rows.append(0)             # BI_RGB padding
        for x in range(size):
            fx, fy = x / size, (size - 1 - _y) / size
            inside = edge / size <= fx <= 1 - edge / size and edge / size <= fy <= 1 - edge / size
            if not inside:
                rows += bytes((0, 0, 0, 0))
                continue
            white = False
            for gx0, gy0, gx1, gy1 in glyph:
                if gx0 <= fx <= gx1 and gy0 <= fy <= gy1:
                    if (int(fx * size) % cell) < cell - 2 and (int(fy * size) % cell) < cell - 2:
                        white = True
            rows += bytes((255, 255, 255, 255) if white else (0xC0, 0x8A, 0x2B, 0xFF))
    header = struct.pack('<IiiHHIIiiII', 40, size, size * 2, 1, 32, 0, len(rows), 0, 0, 0, 0)
    bmp = header + bytes(rows)
    dim = 0 if size >= 256 else size  # 0 means 256 in the ICO directory entry
    return struct.pack('<HHH', 0, 1, 1) + struct.pack('<BBBBHHII', dim, dim, 0, 0, 1, 32, len(bmp), 22) + bmp


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "Setup.ico"
    with open(out, "wb") as handle:
        handle.write(build())
    print("icon written:", out)
