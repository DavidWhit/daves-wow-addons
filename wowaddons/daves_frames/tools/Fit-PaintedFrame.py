"""Retired. The paint mask is tools/Build-FrameTemplate.py.

Imagine paints one plate onto guides/frame-template.png. See
tools/template/PAINT-LAYERS.md. This script exits unless --paintings is passed.
"""
from __future__ import annotations

import os
import struct
import zlib
from collections import deque

ROOT = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(ROOT)
PAINT = os.path.join(ROOT, "template", "paintings")
MEDIA = os.path.join(ADDON, "Media")
PREVIEW = os.path.join(ROOT, "template", "preview")

# One crop for every variant, in source pixels. Pad around the elite dragon.
X0, Y0 = 218, 60
CROP_W, CROP_H = 840, 400
K = 2  # art pixels per source pixel
ATLAS_W, ATLAS_H = 2048, 1024

# Measured on the elite painting, full-image pixels.
RING_C = (646.5, 233.0)
R_IN_SRC = 73
WIN = (271, 208, 1005, 247)  # L T R B


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
    """255 when the pixel is the flat magenta key, including the darker band."""
    if g > 115 or r < 80 or b < 70:
        return 0
    pink = min(r, b) - g
    if pink < 35 or abs(r - b) > 120:
        return 0
    return min(255, int(pink * 3))


def key_image(w, h, rgba):
    a = bytearray(w * h)
    for i in range(w * h):
        o = i * 4
        m = mag_amount(rgba[o], rgba[o + 1], rgba[o + 2])
        a[i] = 0 if m > 140 else 255 - m // 2 if m > 40 else 255
    # Exterior vs holes.
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
        if x > 0:
            push(x - 1, y)
        if x + 1 < w:
            push(x + 1, y)
        if y > 0:
            push(x, y - 1)
        if y + 1 < h:
            push(x, y + 1)
    # Fill pinholes (cracks), keep the portrait, the bars, and the tail loop.
    seen = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if a[i] > 40 or ext[i] or seen[i]:
                continue
            comp = []
            q = deque([i])
            seen[i] = 1
            while q:
                j = q.popleft()
                comp.append(j)
                px, py = j % w, j // w
                for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                    if 0 <= nx < w and 0 <= ny < h:
                        k = ny * w + nx
                        if a[k] <= 40 and not ext[k] and not seen[k]:
                            seen[k] = 1
                            q.append(k)
            if len(comp) >= 800:
                continue
            for j in comp:
                px, py = j % w, j // w
                for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                    if 0 <= nx < w and 0 <= ny < h and a[ny * w + nx] == 255:
                        s = (ny * w + nx) * 4
                        d = j * 4
                        rgba[d:d + 3] = rgba[s:s + 3]
                        a[j] = 255
                        break
    for i in range(w * h):
        rgba[i * 4 + 3] = a[i]
    return rgba


def crop(rgba, w):
    out = bytearray(CROP_W * CROP_H * 4)
    for y in range(CROP_H):
        s = ((Y0 + y) * w + X0) * 4
        d = y * CROP_W * 4
        out[d:d + CROP_W * 4] = rgba[s:s + CROP_W * 4]
    return out


def scale2(src, w, h):
    ow, oh = w * K, h * K
    out = bytearray(ow * oh * 4)
    def sample(x, y):
        if x < 0:
            x = 0
        elif x >= w:
            x = w - 1
        if y < 0:
            y = 0
        elif y >= h:
            y = h - 1
        i = (y * w + x) * 4
        return src[i], src[i + 1], src[i + 2], src[i + 3]
    for y in range(oh):
        sy = (y + 0.5) / K - 0.5
        y0 = int(sy) if sy >= 0 else 0
        fy = sy - y0
        y1 = y0 + 1 if y0 + 1 < h else y0
        if fy < 0:
            fy = 0
        for x in range(ow):
            sx = (x + 0.5) / K - 0.5
            x0 = int(sx) if sx >= 0 else 0
            fx = sx - x0
            x1 = x0 + 1 if x0 + 1 < w else x0
            if fx < 0:
                fx = 0
            c00, c10, c01, c11 = sample(x0, y0), sample(x1, y0), sample(x0, y1), sample(x1, y1)
            o = (y * ow + x) * 4
            for k in range(4):
                top = c00[k] * (1 - fx) + c10[k] * fx
                bot = c01[k] * (1 - fx) + c11[k] * fx
                out[o + k] = int(top * (1 - fy) + bot * fy + 0.5)
    return out


def ring_outer(src, w, h):
    """Outer radius of the ring, in source pixels, from the plain plate."""
    cx, cy = RING_C
    cx -= X0
    cy -= Y0
    found = []
    for step in range(48):
        ang = step / 48 * 6.283185
        import math
        dx, dy = math.cos(ang), math.sin(ang)
        last = None
        r = R_IN_SRC + 2
        while r < R_IN_SRC + 60:
            x = int(cx + dx * r)
            y = int(cy + dy * r)
            if not (0 <= x < w and 0 <= y < h):
                break
            if src[(y * w + x) * 4 + 3] > 200:
                last = r
            elif last is not None:
                break
            r += 1
        if last and last < R_IN_SRC + 45:
            found.append(last)
    found.sort()
    return found[len(found) // 2] if found else R_IN_SRC + 18


def plate_band(src, w, h):
    """Vertical extent of the left end cap, source pixels in the crop."""
    x_a = WIN[0] - X0 + 8
    x_b = x_a + 70
    ys = []
    for y in range(h):
        for x in range(x_a, x_b):
            if src[(y * w + x) * 4 + 3] > 200:
                ys.append(y)
                break
    return min(ys), max(ys)


def tail_span(src, w, h, plate_b):
    xs = [x for y in range(plate_b + 4, h) for x in range(w) if src[(y * w + x) * 4 + 3] > 200]
    if not xs:
        return None
    return min(xs), max(xs)


def board_strip(art, aw, ah, y0, y1):
    """Left and right 150 source px of the plate, at 2x, side by side."""
    run = 150 * K
    bh = (y1 - y0) * K
    strip = bytearray(run * 2 * bh * 4)
    src_y = y0 * K

    def copy(src_x, dst_x):
        for y in range(bh):
            s = ((src_y + y) * aw + src_x) * 4
            d = (y * run * 2 + dst_x) * 4
            strip[d:d + run * 4] = art[s:s + run * 4]

    copy(0, 0)
    copy(aw - run, run)
    return strip, run * 2, bh


def blit(dst, dw, src, sw, sh, x0, y0):
    for y in range(sh):
        if not (0 <= y0 + y < ATLAS_H):
            continue
        s = y * sw * 4
        d = ((y0 + y) * dw + x0) * 4
        dst[d:d + sw * 4] = src[s:s + sw * 4]


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


def under(art, aw, ah):
    """Stand-in portrait and bars, for the preview only."""
    out = bytearray(art)
    cx = (RING_C[0] - X0) * K
    cy = (RING_C[1] - Y0) * K
    r = (R_IN_SRC + 2) * K
    wl, wt = (WIN[0] - X0) * K, (WIN[1] - Y0) * K
    wr, wb = (WIN[2] - X0) * K, (WIN[3] - Y0) * K
    import math
    for y in range(ah):
        for x in range(aw):
            o = (y * aw + x) * 4
            if out[o + 3] > 200:
                continue
            if (x - cx) ** 2 + (y - cy) ** 2 < r * r:
                out[o:o + 4] = bytes((196, 154, 108, 255))
            elif wl <= x <= wr and wt <= y <= wb and abs(x - cx) > (R_IN_SRC + 16) * K:
                out[o:o + 4] = bytes((170, 48, 36, 255)) if x < cx else bytes((36, 78, 170, 255))
    return out


def main():
    os.makedirs(MEDIA, exist_ok=True)
    os.makedirs(PREVIEW, exist_ok=True)
    plain = None
    arts = {}
    for name in ("plain", "rare", "elite", "rareelite"):
        w, h, rgba = read_png(os.path.join(PAINT, name + ".png"))
        key_image(w, h, rgba)
        cropped = crop(rgba, w)
        if name == "plain":
            plain = cropped
        arts[name] = scale2(cropped, CROP_W, CROP_H)
        print(name, "keyed")
    r_out = ring_outer(plain, CROP_W, CROP_H)
    band0, band1 = plate_band(plain, CROP_W, CROP_H)
    tail = tail_span(arts["elite"], CROP_W * K, CROP_H * K, band1 * K)
    print(f"rOut src {r_out:.1f}  plate y {band0}..{band1}  tail px {tail}")

    aw, ah = CROP_W * K, CROP_H * K
    strip, sw, sh = board_strip(arts["plain"], aw, ah, band0, band1 + 1)
    sy = ah + 8
    if sy + sh > ATLAS_H:
        raise SystemExit(f"strip does not fit: y {sy} h {sh}")

    for name, art in arts.items():
        atlas = bytearray(ATLAS_W * ATLAS_H * 4)
        blit(atlas, ATLAS_W, art, aw, ah, 0, 0)
        blit(atlas, ATLAS_W, strip if name in ("plain", "elite") else board_strip(art, aw, ah, band0, band1 + 1)[0], sw, sh, 0, sy)
        write_tga(os.path.join(MEDIA, f"frame-{name}.tga"), ATLAS_W, ATLAS_H, atlas)
        preview = under(art, aw, ah)
        # 1x preview
        small = bytearray(CROP_W * CROP_H * 4)
        for y in range(CROP_H):
            for x in range(CROP_W):
                s = ((y * K) * aw + (x * K)) * 4
                d = (y * CROP_W + x) * 4
                small[d:d + 4] = preview[s:s + 4]
        write_png(os.path.join(PREVIEW, f"fit-{name}.png"), CROP_W, CROP_H, small)

    # Layout: source crop pixels, scaled so the window is 56 tall (the name fits at 44).
    win_h = WIN[3] - WIN[1]
    kL = 56 / win_h
    def L(v):
        return int(round(v * kL))
    cx = L(RING_C[0] - X0)
    cy = L(RING_C[1] - Y0)
    r_in = L(R_IN_SRC)
    r_out_l = L(r_out)
    win_l, win_t = L(WIN[0] - X0), L(WIN[1] - Y0)
    win_r, win_b = L(WIN[2] - X0), L(WIN[3] - Y0)
    # Window height must be 56. Rounding can miss it; pin the bottom.
    win_b = win_t + 56
    plate_t, plate_b = L(band0), L(band1)
    cap = L(36)  # ornate end, about 36 source px
    top_metal = win_t - plate_t
    if top_metal < 8:
        top_metal = 8
    bot_metal = plate_b - win_b
    if bot_metal < 8:
        bot_metal = 8
    hidden = r_out_l - 4
    # Tail in layout px, so the aura lanes stop before it.
    if tail:
        tail_l = L(tail[0] / K)
        tail_r = L(tail[1] / K)
    else:
        tail_l, tail_r = cx - r_out_l, cx + r_out_l
    w, h = L(CROP_W), L(CROP_H)
    art_h = ah
    print(f"""
kL {kL:.4f}
art = {{ 0, {aw / ATLAS_W:.6f}, 0, {art_h / ATLAS_H:.6f} }}
strip = {{ 0, {sw / ATLAS_W:.6f}, {sy / ATLAS_H:.6f}, {(sy + sh) / ATLAS_H:.6f} }}
stripPx = {{ w = {sw}, h = {sh} }}
-- Guess only. Layout.lua holds the measured slice (finial up to the bar slot, 120 / 59 / 61).
stripSlice guess = {{ top = {top_metal * K}, right = {cap * K}, bottom = {bot_metal * K}, left = {cap * K} }}
w = {w}, h = {h}
cx = {cx}, cy = {cy}, rIn = {r_in}, rOut = {r_out_l}
winL = {win_l}, winR = {win_r}, winT = {win_t}, winB = {win_b}
hidden = {hidden}
plateL = {L(0)}, plateR = {w}, plateT = {plate_t}, plateB = {plate_b}
pivotY = {plate_b - L(12)}
laneL = {{ {L(12)}, {tail_l - L(8)} }}
laneR = {{ {tail_r + L(8)}, {w - L(12)} }}
board top {top_metal} bottom {bot_metal} side {cap}
badge dy { (r_in + r_out_l) // 2 }
""")


if __name__ == "__main__":
    import sys
    if "--paintings" not in sys.argv:
        raise SystemExit(
            "Fit-PaintedFrame.py packs the old paintings and would overwrite Media\\frame-*.tga.\n"
            "The paint mask is tools\\Build-FrameTemplate.py (guides\\frame-template.png).\n"
            "Pass --paintings only to pack those old paintings on purpose."
        )
    main()
