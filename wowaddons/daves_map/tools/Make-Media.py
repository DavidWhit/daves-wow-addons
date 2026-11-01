"""Paint daves_map's dot.tga and ring.tga. Matches Make-Media.ps1.

Both are uncompressed 32-bit TGA, 64x64, top-left origin.
"""

from __future__ import annotations

import math
import os
import struct
import sys

SIZE = 64


def smoothstep(edge0, edge1, value):
    span = (value - edge0) / (edge1 - edge0)
    t = min(1.0, max(0.0, span))
    return t * t * (3.0 - 2.0 * t)


def _byte(value):
    # PowerShell [int] rounds a double, with halves going to the even integer.
    return round(value) & 0xFF


def write_tga(path, pixel):
    pixels = bytearray()
    for py in range(SIZE):
        for px in range(SIZE):
            dx = (px + 0.5) / SIZE * 2.0 - 1.0
            dy = (py + 0.5) / SIZE * 2.0 - 1.0
            red, green, blue, alpha = pixel(math.sqrt(dx * dx + dy * dy))
            pixels += bytes((
                _byte(blue * 255.0),
                _byte(green * 255.0),
                _byte(red * 255.0),
                _byte(alpha * 255.0),
            ))
    header = bytearray(18)
    header[2] = 2
    header[12:16] = struct.pack("<HH", SIZE, SIZE)
    header[16] = 32
    header[17] = 0x28
    with open(path, "wb") as handle:
        handle.write(header)
        handle.write(pixels)


def dot_pixel(dist):
    inner = 1.0 - smoothstep(0.66, 0.72, dist)
    edge = 1.0 - smoothstep(0.88, 0.94, dist)
    return (inner, inner, inner, max(inner, 0.9 * edge))


def ring_pixel(dist):
    band = smoothstep(0.70, 0.75, dist) * (1.0 - smoothstep(0.85, 0.90, dist))
    glow = 0.35 * math.exp(-((dist - 0.8) / 0.12) ** 2)
    return (1.0, 1.0, 1.0, min(1.0, band + glow))


def main():
    media = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Media")
    os.makedirs(media, exist_ok=True)
    write_tga(os.path.join(media, "dot.tga"), dot_pixel)
    write_tga(os.path.join(media, "ring.tga"), ring_pixel)
    print(f"Wrote dot.tga and ring.tga to {os.path.abspath(media)}", flush=True)


if __name__ == "__main__":
    main()
