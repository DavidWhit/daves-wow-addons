"""Retired. The paint mask is tools/Build-FrameTemplate.py.

Imagine paints one plate onto guides/frame-template.png. See
tools/template/PAINT-LAYERS.md. This script exits unless --example is passed.
"""
from __future__ import annotations

import json
import os
import struct
import zlib
from collections import deque

ROOT = os.path.dirname(os.path.abspath(__file__))
EXAMPLE = os.path.join(ROOT, "template", "example")
LAYERS = os.path.join(EXAMPLE, "layers")
OUT = os.path.join(EXAMPLE, "out")
ATLAS_W, ATLAS_H = 2048, 1024


def read_png(path):
    data = open(path, "rb").read()
    pos = 8
    w = h = ct = None
    idat = b""
    while pos < len(data):
        n = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if tag == b"IHDR":
            w, h, _, ct = struct.unpack(">IIBB", chunk[:10])
        elif tag == b"IDAT":
            idat += chunk
        elif tag == b"IEND":
            break
    raw = zlib.decompress(idat)
    bpp = {2: 3, 6: 4}[ct]
    stride = w * bpp
    out = bytearray(w * h * 4)
    i = 0
    prev = bytearray(stride)

    def paeth(a, b, c):
        p = a + b - c
        pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
        if pa <= pb and pa <= pc:
            return a
        if pb <= pc:
            return b
        return c

    for y in range(h):
        f = raw[i]
        i += 1
        row = bytearray(raw[i:i + stride])
        i += stride
        if f == 1:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + left) & 255
        elif f == 2:
            for x in range(stride):
                row[x] = (row[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + ((left + prev[x]) // 2)) & 255
        elif f == 4:
            for x in range(stride):
                a = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + paeth(a, prev[x], prev[x - bpp] if x >= bpp else 0)) & 255
        elif f != 0:
            raise SystemExit(f"png filter {f}")
        prev = row
        for x in range(w):
            s = x * bpp
            o = (y * w + x) * 4
            out[o] = row[s]
            out[o + 1] = row[s + 1]
            out[o + 2] = row[s + 2]
            out[o + 3] = 255 if bpp == 3 else row[s + 3]
    return w, h, out


def mag_amount(r, g, b):
    if g > 115 or r < 80 or b < 70:
        return 0
    pink = min(r, b) - g
    if pink < 35 or abs(r - b) > 120:
        return 0
    return min(255, int(pink * 3))


def key_magenta(w, h, rgba):
    """Drop the flat magenta field. Leave enclosed holes alone."""
    a = bytearray(w * h)
    for i in range(w * h):
        o = i * 4
        m = mag_amount(rgba[o], rgba[o + 1], rgba[o + 2])
        a[i] = 0 if m > 140 else 255 - m // 2 if m > 40 else 255
    ext = bytearray(w * h)
    q = deque()

    def push(x, y):
        i = y * w + x
        if ext[i] or a[i] > 40:
            return
        ext[i] = 1
        q.append(i)

    for x in range(w):
        push(x, 0)
        push(x, h - 1)
    for y in range(h):
        push(0, y)
        push(w - 1, y)
    while q:
        i = q.popleft()
        x, y = i % w, i // w
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h:
                push(nx, ny)
    for i in range(w * h):
        o = i * 4
        if ext[i] or a[i] == 0:
            rgba[o + 3] = 0
        else:
            rgba[o + 3] = a[i]
    return rgba


def sample(src, sw, sh, x, y):
    if x < 0 or y < 0 or x >= sw or y >= sh:
        return 0, 0, 0, 0
    o = (y * sw + x) * 4
    return src[o], src[o + 1], src[o + 2], src[o + 3]


def scale_into(src, sw, sh, dw, dh):
    out = bytearray(dw * dh * 4)
    if sw < 1 or sh < 1 or dw < 1 or dh < 1:
        return out
    for y in range(dh):
        sy = (y + 0.5) * sh / dh - 0.5
        y0 = int(sy)
        fy = sy - y0
        for x in range(dw):
            sx = (x + 0.5) * sw / dw - 0.5
            x0 = int(sx)
            fx = sx - x0
            acc = [0, 0, 0, 0]
            for oy, wy in ((0, 1 - fy), (1, fy)):
                for ox, wx in ((0, 1 - fx), (1, fx)):
                    p = sample(src, sw, sh, x0 + ox, y0 + oy)
                    wgt = wx * wy
                    for c in range(4):
                        acc[c] += p[c] * wgt
            o = (y * dw + x) * 4
            for c in range(4):
                out[o + c] = max(0, min(255, int(acc[c] + 0.5)))
    return out


def intersects(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah


def blit(dst, dw, src, sw, sh, x0, y0):
    for y in range(sh):
        dy = y0 + y
        if dy < 0 or dy >= len(dst) // (dw * 4):
            continue
        for x in range(sw):
            dx = x0 + x
            if dx < 0 or dx >= dw:
                continue
            so = (y * sw + x) * 4
            sa = src[so + 3]
            if sa == 0:
                continue
            do = (dy * dw + dx) * 4
            if sa == 255:
                dst[do:do + 4] = src[so:so + 4]
                continue
            da = dst[do + 3]
            inv = 255 - sa
            for c in range(3):
                dst[do + c] = (src[so + c] * sa + dst[do + c] * inv) // 255
            dst[do + 3] = sa + (da * inv) // 255


def write_png(path, w, h, rgba):
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw.extend(rgba[y * stride:(y + 1) * stride])

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 3)))
        f.write(chunk(b"IEND", b""))


def write_tga(path, w, h, rgba):
    head = bytearray(18)
    head[2] = 2
    head[12] = w & 255
    head[13] = (w >> 8) & 255
    head[14] = h & 255
    head[15] = (h >> 8) & 255
    head[16] = 32
    head[17] = 0x28
    bgra = bytearray(w * h * 4)
    for i in range(0, len(rgba), 4):
        bgra[i] = rgba[i + 2]
        bgra[i + 1] = rgba[i + 1]
        bgra[i + 2] = rgba[i]
        bgra[i + 3] = rgba[i + 3]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(head)
        f.write(bgra)


def main():
    spec = json.load(open(os.path.join(EXAMPLE, "layers.json"), encoding="utf-8"))
    cw, ch = spec["canvas"]
    keep = {name: tuple(box) for name, box in spec["keepOut"].items()}
    frame = bytearray(cw * ch * 4)
    lines = ["layer  box x,y,w,h  file"]
    os.makedirs(os.path.join(OUT, "sized"), exist_ok=True)
    for layer in spec["layers"]:
        box = tuple(layer["box"])
        x, y, bw, bh = box
        if not layer.get("plate"):
            for name, zone in keep.items():
                zx, zy, zx2, zy2 = zone
                if intersects(box, (zx, zy, zx2 - zx, zy2 - zy)):
                    raise SystemExit(f"{layer['name']} overlaps {name}")
        path = os.path.join(LAYERS, layer["file"])
        sw, sh, src = read_png(path)
        key_magenta(sw, sh, src)
        scaled = scale_into(src, sw, sh, bw, bh)
        write_png(os.path.join(OUT, "sized", f"{layer['name']}_{bw}x{bh}.png"), bw, bh, scaled)
        blit(frame, cw, scaled, bw, bh, x, y)
        lines.append(f"{layer['name']}  {x},{y} {bw}x{bh}  {layer['file']}")
        print(f"{layer['name']} {bw}x{bh} at {x},{y}")
    ring = spec["punch"]["ring"]
    bars = spec["punch"]["bars"]
    cx, cy, r = ring
    x0, y0, x1, y1 = bars
    r2 = r * r
    outer = (r + 6) * (r + 6)
    for y in range(ch):
        for x in range(cw):
            d2 = (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2
            inbar = x0 <= x < x1 and y0 <= y < y1 and d2 > outer
            if d2 <= r2 or inbar:
                frame[(y * cw + x) * 4 + 3] = 0
    write_png(os.path.join(OUT, "frame.png"), cw, ch, frame)
    atlas = bytearray(ATLAS_W * ATLAS_H * 4)
    blit(atlas, ATLAS_W, frame, cw, ch, 0, 0)
    write_tga(os.path.join(OUT, "frame.tga"), ATLAS_W, ATLAS_H, atlas)
    text = "\n".join(lines) + "\n"
    text += "keep out of name, power text, and the level number. Portrait and bars are punched.\n"
    open(os.path.join(OUT, "sizes.txt"), "w", encoding="utf-8").write(text)
    print("wrote", os.path.join(OUT, "frame.png"))


if __name__ == "__main__":
    import sys
    if "--example" not in sys.argv:
        raise SystemExit(
            "Build-FrameLayers.py stacks the old example_frame composite.\n"
            "The paint mask is tools\\Build-FrameTemplate.py (guides\\frame-template.png).\n"
            "Pass --example only to rebuild that composite on purpose."
        )
    main()
