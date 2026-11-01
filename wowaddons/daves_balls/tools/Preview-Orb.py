"""Composite the orb TGA layers to a PNG.

The PNG container is written with the stdlib. It will not be byte-identical to a
System.Drawing PNG. The pixels are the same sequence the PowerShell script stores.
"""

from __future__ import annotations

import math
import os
import struct
import sys
import zlib

S = 256
LAYERS = (
    "OrbBack", "OrbMask", "OrbShade", "OrbGloss", "OrbGlass", "OrbWave",
    "OrbCloud", "OrbVeins", "OrbSparks", "OrbCore", "OrbHalo",
)


def _round_byte(value):
    # [int][math]::Round of a unit component clamped to 0..1, halves to even.
    return round(min(1.0, max(0.0, value)) * 255.0)


def _wrap(value):
    number = round(value)
    return (number % S + S) % S


def _load(media):
    loaded = {}
    for name in LAYERS:
        with open(os.path.join(media, name + ".tga"), "rb") as handle:
            loaded[name] = handle.read()
    return loaded


def _px(layers, name, x, y):
    blob = layers[name]
    x = _wrap(x)
    y = _wrap(y)
    i = 18 + (y * S + x) * 4
    return (
        blob[i + 2] / 255.0,
        blob[i + 1] / 255.0,
        blob[i] / 255.0,
        blob[i + 3] / 255.0,
    )


def composite(media, color, level, tilt_deg):
    layers = _load(media)
    deep = tuple(channel * 0.35 for channel in color)
    glow = tuple(channel + (1.0 - channel) * 0.35 for channel in color)
    gold = (1.0, 0.72, 0.30)
    level_y = round((0.1 + 0.8 * level) * S)
    rgb = bytearray(S * S * 3)
    for y in range(S):
        for x in range(S):
            red = 0.12
            green = 0.12
            blue = 0.12

            def over(sample, alpha, red=red, green=green, blue=blue):
                return (
                    red * (1.0 - alpha) + sample[0] * alpha,
                    green * (1.0 - alpha) + sample[1] * alpha,
                    blue * (1.0 - alpha) + sample[2] * alpha,
                )

            def add(sample, alpha, red=red, green=green, blue=blue):
                return (
                    red + sample[0] * alpha,
                    green + sample[1] * alpha,
                    blue + sample[2] * alpha,
                )

            pixel = _px(layers, "OrbHalo", x, y)
            red, green, blue = add(glow, pixel[3])
            pixel = _px(layers, "OrbBack", x, y)
            red, green, blue = over(pixel, pixel[3], red, green, blue)
            mask = _px(layers, "OrbMask", x, y)[3]
            surf = level_y + math.tan(tilt_deg * math.pi / 180.0) * (x - 128)
            if y < surf and mask > 0:
                red, green, blue = over(deep, mask, red, green, blue)
                sample = _px(layers, "OrbCloud", x * 0.8 + 40, y * 0.8 + 70)
                red, green, blue = add(glow, sample[3] * 0.45 * mask, red, green, blue)
                sample = _px(layers, "OrbVeins", x * 0.55, y * 0.55)
                red, green, blue = add(glow, sample[3] * 0.9 * mask, red, green, blue)
                sample = _px(layers, "OrbVeins", x * 0.45 + 100, y * 0.45 + 30)
                red, green, blue = add(gold, sample[3] * 0.7 * mask, red, green, blue)
                sample = _px(layers, "OrbSparks", x, y)
                red, green, blue = add((1.0, 1.0, 1.0), sample[3] * 0.8 * mask, red, green, blue)
                sample = _px(layers, "OrbCore", x, y)
                red, green, blue = add(gold, sample[3] * 0.8 * mask, red, green, blue)
            dy = y - surf
            if abs(dy) < 18:
                wave = _px(layers, "OrbWave", x * 0.75 + 30, 128 + dy * 256 / 36)
                red, green, blue = add(glow, wave[3] * 0.6 * mask, red, green, blue)
            pixel = _px(layers, "OrbShade", x, y)
            red, green, blue = over(pixel, pixel[3], red, green, blue)
            pixel = _px(layers, "OrbGloss", x, y)
            red, green, blue = add(pixel, pixel[3] * 0.8, red, green, blue)
            pixel = _px(layers, "OrbGlass", x, y)
            red, green, blue = add(pixel, pixel[3], red, green, blue)
            # Bitmap row 0 is texture y = S-1 (SetPixel x, S-1-y).
            row = (S - 1 - y) * S + x
            rgb[row * 3] = _round_byte(red)
            rgb[row * 3 + 1] = _round_byte(green)
            rgb[row * 3 + 2] = _round_byte(blue)
    return rgb


def write_png(path, rgb):
    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    raw = bytearray()
    stride = S * 3
    for y in range(S):
        raw.append(0)
        raw += rgb[y * stride:(y + 1) * stride]
    ihdr = struct.pack(">IIBBBBB", S, S, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


def _args(argv):
    out = {"Media": "", "Out": "", "Color": "0.10,0.25,0.95", "Level": "0.65", "TiltDeg": "0"}
    i = 0
    while i < len(argv):
        token = argv[i]
        if not token.startswith("-"):
            print("Unknown argument: " + token, file=sys.stderr, flush=True)
            raise SystemExit(1)
        raw = token[1:]
        if ":" in raw:
            key, value = raw.split(":", 1)
        else:
            key = raw
            if i + 1 >= len(argv):
                print(f"Missing value for -{key}", file=sys.stderr, flush=True)
                raise SystemExit(1)
            i += 1
            value = argv[i]
        found = next((name for name in out if name.lower() == key.lower()), None)
        if not found:
            print("Unknown argument: " + token, file=sys.stderr, flush=True)
            raise SystemExit(1)
        out[found] = value
        i += 1
    return out


def main(argv):
    args = _args(argv)
    if not args["Media"] or not args["Out"]:
        print("Pass -Media <folder> -Out <png>", file=sys.stderr, flush=True)
        raise SystemExit(1)
    color = tuple(float(part) for part in args["Color"].split(","))
    rgb = composite(args["Media"], color, float(args["Level"]), float(args["TiltDeg"]))
    write_png(args["Out"], rgb)


if __name__ == "__main__":
    main(sys.argv[1:])
