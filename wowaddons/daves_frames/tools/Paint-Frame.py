"""Retired. The paint mask is tools/Build-FrameTemplate.py.

Imagine paints the metal onto guides/frame-template.png. See
tools/template/PAINT-LAYERS.md. This script exits unless --procedural is passed.
"""

from __future__ import annotations

import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(ROOT)
MEDIA = os.path.join(ADDON, "Media")
GUIDES = os.path.join(ROOT, "template", "guides")
PREVIEW = os.path.join(ROOT, "template", "preview")

# Layout pixels. Art and guides are drawn at K times this.
K = 2
W, H = 1024, 220
CX, CY = 512, 108
R_IN, R_OUT, R_TEXT = 70, 90, 46
WIN_L, WIN_T, WIN_R, WIN_B = 32, 80, 992, 136
WIN_R_PX = 5
# Plate, then the rim (L2) 10 px inside it. L1's hole is 4 px inside L2 so the
# plate runs under the rim and the two edges never meet as a seam.
PLATE = (8, 58, 1016, 158, 12)
INNER = (18, 68, 1006, 148, 8)
L1_HOLE = (22, 72, 1002, 144, 6)
BADGE_Y, BADGE_R, BADGE_IN = 186, 24, 16
HIDDEN = 80
NAME_PX = 44
TEXT_MIN = 14  # screen pixels at the smallest scale

ATLAS_W, ATLAS_H = 2048, 1024

# Gold and silver are one drawing. Dark, mid, light.
GOLD = ((28, 16, 6), (186, 124, 38), (255, 232, 176))
SILVER = ((20, 24, 30), (148, 160, 176), (236, 242, 248))


def clamp(v, a, b):
    return a if v < a else b if v > b else v


def hypot(x, y):
    return math.sqrt(x * x + y * y)


def sd_round_box(px, py, box):
    x1, y1, x2, y2, r = box
    hx = (x2 - x1) * 0.5 - r
    hy = (y2 - y1) * 0.5 - r
    dx = abs(px - (x1 + x2) * 0.5) - hx
    dy = abs(py - (y1 + y2) * 0.5) - hy
    ax = dx if dx > 0 else 0
    ay = dy if dy > 0 else 0
    return hypot(ax, ay) + (dx if dx > dy else dy if dy > 0 else 0) - r


def sd_circle(px, py, cx, cy, r):
    return hypot(px - cx, py - cy) - r


def sd_capsule(px, py, ax, ay, bx, by, r):
    pax, pay = px - ax, py - ay
    bax, bay = bx - ax, by - ay
    den = bax * bax + bay * bay
    h = 0 if den <= 1e-6 else clamp((pax * bax + pay * bay) / den, 0, 1)
    return hypot(pax - bax * h, pay - bay * h) - r


def box_normal(px, py, box):
    x1, y1, x2, y2, r = box
    cx = (x1 + x2) * 0.5
    cy = (y1 + y2) * 0.5
    hx = (x2 - x1) * 0.5 - r
    hy = (y2 - y1) * 0.5 - r
    dx, dy = px - cx, py - cy
    ax, ay = abs(dx), abs(dy)
    qx, qy = ax - hx, ay - hy
    if qx > 0 and qy > 0:
        n = hypot(qx, qy) or 1
        nx, ny = qx / n, qy / n
    elif qx > qy:
        nx, ny = 1.0, 0.0
    else:
        nx, ny = 0.0, 1.0
    if dx < 0:
        nx = -nx
    if dy < 0:
        ny = -ny
    return nx, ny


def cov(sd):
    """Coverage 0..255 from a pixel-space signed distance. Negative is inside."""
    t = 0.5 - sd
    if t <= 0:
        return 0
    if t >= 1:
        return 255
    return int(t * 255 + 0.5)


def grain(x, y):
    n = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
    n ^= (n >> 13)
    n = (n * 1274126177) & 0xFFFFFFFF
    return (n >> 24) - 128  # -128..127


def over(dest_a, dest_l, a, light):
    """Over a coverage/light pair. light and a are 0..255. Returns new pair."""
    if a <= 0:
        return dest_a, dest_l
    if a >= 255 or dest_a <= 0:
        return a, light
    inv = 255 - a
    na = a + (dest_a * inv) // 255
    if na <= 0:
        return 0, 0
    nl = (light * a + dest_l * ((dest_a * inv) // 255)) // na
    return na, nl


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
    """BGRA, top-left origin, the layout FrameMedia.cs writes."""
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


def tint(light, pal):
    if light < 128:
        t = light / 128.0
        a, b = pal[0], pal[1]
    else:
        t = (light - 128) / 127.0
        a, b = pal[1], pal[2]
    return (
        int(a[0] + (b[0] - a[0]) * t + 0.5),
        int(a[1] + (b[1] - a[1]) * t + 0.5),
        int(a[2] + (b[2] - a[2]) * t + 0.5),
    )


def brush(px, py):
    """Broad strokes across the plate. Smooth on purpose: the aura board
    stretches the rail, and a rivet repeat would smear."""
    x = px / K
    y = py / K
    s = math.sin(x * 0.041 + 0.7) * 0.7
    s += math.sin(x * 0.017 + y * 0.05 + 1.4) * 0.55
    s += math.sin(y * 0.22 + 0.3) * 0.35
    return int(s * 22)


def face_light(nx, ny, along):
    """Top-left light on a beveled edge, plus a gentle shade down the face."""
    # nx, ny point out of the shape. Light comes from up-left, so an edge
    # facing that way is bright.
    nd = nx * -0.72 + ny * -0.62
    bevel = int(136 + nd * 118)
    return clamp(int(bevel * 0.7 + along * 0.3), 0, 255)


def build_masks():
    """Coverage and light for the shared metal, and for the elite ornament.

    Boxes are already in image pixels. Coverage is one pixel of antialiasing.
    """
    iw, ih = W * K, H * K
    metal_a = bytearray(iw * ih)
    metal_l = bytearray(iw * ih)
    orn_a = bytearray(iw * ih)
    orn_l = bytearray(iw * ih)
    # Image-pixel constants.
    k = K
    cx, cy = CX * k, CY * k
    r_in, r_out, r_text = R_IN * k, R_OUT * k, R_TEXT * k
    badge_y, badge_r, badge_in = BADGE_Y * k, BADGE_R * k, BADGE_IN * k
    win = (WIN_L * k, WIN_T * k, WIN_R * k, WIN_B * k, WIN_R_PX * k)
    plate = tuple(v * k for v in PLATE)
    inner = tuple(v * k for v in INNER)
    hole = tuple(v * k for v in L1_HOLE)
    # End clasps, inside the plate and stopping before the window.
    cap_y1, cap_y2 = plate[1] + 6 * k, plate[3] - 6 * k
    left_cap = (plate[0] + 5 * k, cap_y1, plate[0] + 22 * k, cap_y2, 3 * k)
    right_cap = (plate[2] - 22 * k, cap_y1, plate[2] - 5 * k, cap_y2, 3 * k)

    # One crest and two paws. Thick shapes, so they still read when the frame
    # is only as tall as the name. Thin spokes turn into noise at that size.
    head_cy = cy - r_in + 8 * k
    paws = []
    for sign in (1, -1):
        for ang, rad, reach in ((0.95, 8.0, 0), (0.62, 4.2, -6), (1.28, 4.2, -6)):
            a = ang if sign > 0 else math.pi - ang
            r0 = r_text + 10 * k
            r1 = r_in + (2 + reach) * k
            paws.append((
                cx + math.cos(a) * r0, cy + math.sin(a) * r0,
                cx + math.cos(a) * r1, cy + math.sin(a) * r1,
                rad * k,
            ))
    horns = []
    for sign in (1, -1):
        horns.append((
            cx + sign * 12 * k, head_cy - 4 * k,
            cx + sign * 30 * k, 6 * k,
            8 * k,
        ))

    def stamp_shape(sd, nx, ny, extra, a, light, along, gshift):
        c = cov(sd * k)
        if not c:
            return a, light
        lv = face_light(nx, ny, along + extra)
        # A bright lip on the outer pixel of a shape.
        if -6 < sd <= -0.6:
            lv = min(255, lv + 58)
        lv = clamp(lv + gshift, 0, 255)
        return over(a, light, c, lv)

    for y in range(ih):
        py = y + 0.5
        ly = py / k
        row = y * iw
        along = 118 + int(28 * (1 - ly / H))  # lighter at the top
        for x in range(iw):
            px = x + 0.5
            i = row + x
            gshift = grain(x, y) // 10

            # --- shared metal ---
            sd_plate = sd_round_box(px, py, plate)
            sd_hole = sd_round_box(px, py, hole)
            sd_inner = sd_round_box(px, py, inner)
            sd_win = sd_round_box(px, py, win)
            sd_out = sd_circle(px, py, cx, cy, r_out)
            sd_in = sd_circle(px, py, cx, cy, r_in)
            # Plate: inside the plate, outside its hole. It runs under the ring to the opening.
            plate_sd = max(sd_plate, -sd_hole)
            if sd_in < -1:
                plate_sd = max(plate_sd, -(sd_in + 1))
            rim_sd = max(sd_inner, -sd_win)
            # The window crosses the portrait. Stop the rim at the opening, or a
            # line of metal runs through the face.
            if sd_in < -1:
                rim_sd = max(rim_sd, -(sd_in + 1))
            ring_sd = max(sd_out, -sd_in)
            badge_sd = sd_circle(px, py, cx, badge_y, badge_r)
            badge_hole = sd_circle(px, py, cx, badge_y, badge_in)

            a = 0
            light = 0
            # Dark outline a couple of pixels outside the metal, never in a window or the portrait.
            outline_sd = min(plate_sd, rim_sd, ring_sd, badge_sd)
            expand = outline_sd - 2.4
            if sd_win < 0:
                expand = 1
            if sd_in < -1 and badge_sd > 0:
                expand = max(expand, -(sd_in + 1))
            oc = cov(expand * k)
            if oc:
                a, light = over(a, light, oc, 18)

            if plate_sd < 1.2:
                nx, ny = box_normal(px, py, plate)
                a, light = stamp_shape(plate_sd, nx, ny, 0, a, light, along, gshift)
            if rim_sd < 1.2:
                nx, ny = box_normal(px, py, inner)
                # The rim steps down into the window: its inner edge faces inward.
                if sd_win > -8 * k:
                    nx, ny = -nx, -ny
                a, light = stamp_shape(rim_sd, nx, ny, -12, a, light, along, gshift)
            if ring_sd < 1.2:
                dx, dy = px - cx, py - cy
                d = hypot(dx, dy) or 1
                nx, ny = dx / d, dy / d
                u = (d - r_in) / (r_out - r_in)
                # Rolled band: outer half faces out, inner half faces in, crown faces us.
                tilt = (u - 0.45) * 2
                a, light = stamp_shape(ring_sd, nx * tilt, ny * tilt, 8, a, light, along, gshift)
            # Clasps sit on the plate.
            for cap in (left_cap, right_cap):
                sd = sd_round_box(px, py, cap)
                if sd < 1:
                    nx, ny = box_normal(px, py, cap)
                    a, light = stamp_shape(sd, nx, ny, 22, a, light, along, gshift)
            if badge_sd < 1.2:
                dx, dy = px - cx, py - badge_y
                d = hypot(dx, dy) or 1
                a, light = stamp_shape(badge_sd, dx / d, dy / d, 6, a, light, along, gshift)
                # Number well: darker, still opaque, so the digits sit on metal.
                hc = cov(badge_hole * k)
                if hc:
                    a, light = over(a, light, hc, 48)
            # Painted variation on the face. The lip and the groove below stay put.
            if a > 180 and light > 24:
                light = clamp(light + brush(px, py), 0, 255)
            # A slot down each end clasp, so the end reads as a forged piece.
            for cap in (left_cap, right_cap):
                mx = (cap[0] + cap[2]) * 0.5
                if abs(px - mx) < 2.2 * k and cap[1] + 4 * k < py < cap[3] - 4 * k and light:
                    light = min(light, 44)
            # Dark groove inside the outer lip, a bright wire just inside it,
            # and a dark inner lip on the ring. These are what still read small.
            if light and -18 < sd_plate < -6 and sd_hole > 8:
                light = min(light, 44)
            if light and -26 < sd_plate < -20 and sd_hole > 12:
                light = max(light, 176)
            if light and ring_sd < 0:
                dd = hypot(px - cx, py - cy)
                if dd - r_in < 5:
                    light = min(light, 40)

            metal_a[i] = a
            metal_l[i] = light

            # --- elite ornament, hard-masked ---
            dx, dy = px - cx, py - cy
            d = hypot(dx, dy)
            # A pixel of slack so antialiasing on the brow cannot enter the text.
            in_well = d < r_text + 1.25 * k
            in_bars = sd_win < 1.5 * k and d > r_out - 2 * k
            in_digits = hypot(px - cx, py - badge_y) < badge_in + 1 * k
            if in_well or in_bars or in_digits or py < 1 or py > ih - 1:
                continue
            oa, ol = 0, 0
            # Skull on the ring's top, overlapping the forehead and stopping
            # above the text well. Horns grow out of it.
            head = sd_ellipse(px, py, cx, head_cy, 28 * k, 20 * k)
            if head < 2 * k:
                hx, hy = px - cx, py - head_cy
                c = cov(head * k)
                lv = face_light(hx / (28 * k + 1), hy / (20 * k + 1), along + 20)
                oa, ol = over(oa, ol, c, clamp(lv + 8, 0, 255))
            for hseg in horns:
                sd = sd_capsule(px, py, *hseg)
                if sd < 2 * k:
                    c = cov(sd * k)
                    oa, ol = over(oa, ol, c, clamp(along + 46, 0, 255))
            for seg in paws:
                sd = sd_capsule(px, py, *seg)
                if sd < 2 * k:
                    c = cov(sd * k)
                    oa, ol = over(oa, ol, c, clamp(along + 18, 0, 255))
            if oa and not in_well:
                orn_a[i] = oa
                orn_l[i] = ol
    return metal_a, metal_l, orn_a, orn_l


def sd_ellipse(px, py, cx, cy, rx, ry):
    # Approximate: scale y into x and use a circle. Good enough for a head.
    return hypot((px - cx) / rx, (py - cy) / ry) * min(rx, ry) - min(rx, ry)


def compose(metal_a, metal_l, orn_a, orn_l, pal, elite):
    iw, ih = W * K, H * K
    rgba = bytearray(iw * ih * 4)
    for i in range(iw * ih):
        a, light = metal_a[i], metal_l[i]
        if elite and orn_a[i]:
            a, light = over(a, light, orn_a[i], orn_l[i])
        if a <= 0:
            continue
        r, g, b = tint(light, pal)
        o = i * 4
        rgba[o] = r
        rgba[o + 1] = g
        rgba[o + 2] = b
        rgba[o + 3] = a
    return rgba


def audit(orn_a):
    """Ornament pixels that landed on the text or the bars. Must be zero."""
    iw = W * K
    k = K
    cx, cy = CX * k, CY * k
    r_text = R_TEXT * k
    r_out = R_OUT * k
    win = (WIN_L * k, WIN_T * k, WIN_R * k, WIN_B * k, WIN_R_PX * k)
    badge_in = BADGE_IN * k
    badge_y = BADGE_Y * k
    well = bars = digits = 0
    for y in range(H * K):
        py = y + 0.5
        row = y * iw
        for x in range(iw):
            if orn_a[row + x] < 8:
                continue
            px = x + 0.5
            d = hypot(px - cx, py - cy)
            if d < r_text:
                well += 1
            if sd_round_box(px, py, win) < 0 and d > r_out:
                bars += 1
            if hypot(px - cx, py - badge_y) < badge_in:
                digits += 1
    return well, bars, digits


def blit(dst, dw, rgba, w, h, x0, y0):
    for y in range(h):
        if y0 + y < 0 or y0 + y >= ATLAS_H:
            continue
        for x in range(w):
            if x0 + x < 0 or x0 + x >= dw:
                continue
            s = (y * w + x) * 4
            if rgba[s + 3] == 0:
                continue
            d = ((y0 + y) * dw + (x0 + x)) * 4
            dst[d:d + 4] = rgba[s:s + 4]


def board_strip(rgba):
    """Left and right plate ends side by side, at 2x. Solid clasps, open middle."""
    k = K
    x1, y1 = int(PLATE[0] * k), int(PLATE[1] * k)
    y2 = int(PLATE[3] * k)
    # 26 layout px of clasp, then a run of rail, from each end.
    run = int(150 * k)
    bh = y2 - y1
    strip = bytearray(run * 2 * bh * 4)
    iw = W * k

    def copy(src_x, dst_x):
        for y in range(bh):
            for x in range(run):
                s = ((y1 + y) * iw + (src_x + x)) * 4
                d = (y * run * 2 + dst_x + x) * 4
                strip[d:d + 4] = rgba[s:s + 4]

    copy(x1, 0)
    copy(int(PLATE[2] * k) - run, run)
    return strip, run * 2, bh


def pack_atlas(rgba, strip, sw, sh):
    atlas = bytearray(ATLAS_W * ATLAS_H * 4)
    art_h = H * K
    blit(atlas, ATLAS_W, rgba, W * K, art_h, 0, 0)
    sy = art_h + 8
    blit(atlas, ATLAS_W, strip, sw, sh, 0, sy)
    return atlas, art_h, sy, sw, sh


def chain_tga(path, pal):
    w, h = 32, 64
    rgba = bytearray(w * h * 4)
    dark, mid, light = pal

    def plot(x, y, col, a):
        if 0 <= x < w and 0 <= y < h and a > 0:
            i = (y * w + x) * 4
            rgba[i:i + 4] = bytes((col[0], col[1], col[2], a))

    def disc(cx, cy, rx, ry, col, a, hole=0):
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                d = hypot((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry)
                if hole and d < hole:
                    continue
                c = cov((d - 1) * min(rx, ry))
                if c:
                    plot(x, y, col, c * a // 255)

    def rod(x, y0, y1, col):
        for y in range(y0, y1):
            for dx in range(-3, 4):
                plot(x + dx, y, col, 255 if abs(dx) < 3 else 180)

    def punch(cx, cy, rx, ry):
        # plot() ignores alpha 0, so a "disc" cannot cut a hole. Clear the pixels.
        for y in range(int(cy - ry - 2), int(cy + ry + 3)):
            for x in range(int(cx - rx - 2), int(cx + rx + 3)):
                if not (0 <= x < w and 0 <= y < h):
                    continue
                d = hypot((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry)
                if d >= 1.08:
                    continue
                i = (y * w + x) * 4 + 3
                if d <= 0.82:
                    rgba[i] = 0
                else:
                    keep = int((d - 0.82) / 0.26 * rgba[i])
                    if keep < rgba[i]:
                        rgba[i] = keep

    rod(16, 30, 64, dark)
    rod(16, 0, 10, dark)
    for y in range(30, 64):
        plot(14, y, mid, 255)
        plot(15, y, light, 220)
    disc(16, 20, 9, 13, dark, 255)
    disc(16, 20, 7, 11, mid, 255)
    disc(16, 20, 5, 8, dark, 255)
    punch(16, 20, 3.6, 5.2)
    for y in range(12, 18):
        plot(12, y, light, 200)
    write_tga(path, w, h, rgba)


def stripes_tga(path):
    rgba = bytearray(32 * 32 * 4)
    for y in range(32):
        for x in range(32):
            k = (x + y) % 16
            white = k < 7
            edge = k == 7 or k == 15
            if white:
                c = (255, 255, 255, 230)
            elif edge:
                c = (210, 225, 240, 160)
            else:
                c = (160, 200, 255, 90)
            i = (y * 32 + x) * 4
            rgba[i:i + 4] = bytes(c)
    write_tga(path, 32, 32, rgba)


def fill_under(rgba):
    """Portrait disc and two bars, under the metal, for the previews only."""
    iw = W * K
    k = K
    out = bytearray(rgba)
    cx, cy = CX * k, CY * k
    r = (R_IN + 2) * k
    win_l, win_t = int(WIN_L * k), int(WIN_T * k)
    win_r, win_b = int(WIN_R * k), int(WIN_B * k)
    for y in range(H * K):
        py = y + 0.5
        for x in range(iw):
            px = x + 0.5
            i = (y * iw + x) * 4
            if rgba[i + 3] > 200:
                continue
            d = hypot(px - cx, py - cy)
            if d < r:
                # A stand-in face: warm disc, darker at the bottom.
                t = py / (H * k)
                out[i:i + 4] = bytes((int(196 - 40 * t), int(150 - 30 * t), int(110 - 20 * t), 255))
                continue
            if win_l <= px <= win_r and win_t <= py <= win_b and d > (R_OUT - 2) * k:
                if px < cx:
                    t = (px - win_l) / (cx - win_l)
                    out[i:i + 4] = bytes((int(120 + 80 * (1 - t)), int(24 + 20 * t), int(18), 255))
                else:
                    t = (px - cx) / (win_r - cx)
                    out[i:i + 4] = bytes((int(40 + 30 * t), int(70 + 40 * (1 - t)), int(170 - 40 * t), 255))
    # Metal over the stand-in.
    for i in range(0, len(rgba), 4):
        a = rgba[i + 3]
        if a <= 0:
            continue
        if a >= 255:
            out[i:i + 4] = rgba[i:i + 4]
            continue
        inv = 255 - a
        for c in range(3):
            out[i + c] = (rgba[i + c] * a + out[i + c] * inv) // 255
        out[i + 3] = 255
    return out


def downsample(rgba, sw, sh, dw, dh):
    out = bytearray(dw * dh * 4)
    for y in range(dh):
        y0 = y * sh / dh
        y1 = (y + 1) * sh / dh
        for x in range(dw):
            x0 = x * sw / dw
            x1 = (x + 1) * sw / dw
            acc = [0, 0, 0, 0]
            n = 0
            iy0, iy1 = int(y0), min(sh, int(y1 + 0.999))
            ix0, ix1 = int(x0), min(sw, int(x1 + 0.999))
            for iy in range(iy0, iy1):
                row = iy * sw
                for ix in range(ix0, ix1):
                    s = (row + ix) * 4
                    for c in range(4):
                        acc[c] += rgba[s + c]
                    n += 1
            if n:
                d = (y * dw + x) * 4
                for c in range(4):
                    out[d + c] = acc[c] // n
    return out


def guides():
    """Cropped paint maps. The paintable shape fills the picture."""
    os.makedirs(GUIDES, exist_ok=True)
    k = K
    iw = W * k

    def crop_box(x1, y1, x2, y2, pad=8):
        return (max(0, x1 - pad), max(0, y1 - pad), min(W, x2 + pad), min(H, y2 + pad))

    def new(w, h, color):
        buf = bytearray(w * h * 4)
        px = bytes(color)
        for i in range(0, len(buf), 4):
            buf[i:i + 4] = px
        return buf

    def put(buf, w, x, y, color):
        if 0 <= x < w and y >= 0:
            i = (y * w + x) * 4
            if i + 4 <= len(buf):
                buf[i:i + 4] = bytes(color)

    MAG = (255, 0, 255, 255)
    GREY = (128, 128, 128, 255)
    LGREY = (176, 176, 176, 255)
    BLUE = (0, 0, 255, 255)
    GREEN = (0, 255, 0, 255)
    YELLOW = (255, 255, 0, 255)
    CYAN = (0, 255, 255, 255)
    ORANGE = (255, 140, 0, 255)

    crops = {}

    def save_crop(name, box, painter):
        x1, y1, x2, y2 = box
        cw, ch = int((x2 - x1) * k), int((y2 - y1) * k)
        buf = new(cw, ch, MAG)
        for y in range(ch):
            py = y1 * k + y + 0.5
            for x in range(cw):
                px = x1 * k + x + 0.5
                col = painter(px / k, py / k)
                if col is not None:
                    put(buf, cw, x, y, col)
        path = os.path.join(GUIDES, name)
        write_png(path, cw, ch, buf)
        crops[name] = (int(x1 * k), int(y1 * k), cw, ch)
        print(f"  {name}  {cw}x{ch}  at {int(x1 * k)},{int(y1 * k)}")

    def l1(px, py):
        if sd_round_box(px, py, PLATE) <= 0 and sd_round_box(px, py, L1_HOLE) > 0:
            return GREY
        return None

    def l2(px, py):
        if sd_round_box(px, py, INNER) <= 0 and sd_round_box(px, py, (WIN_L, WIN_T, WIN_R, WIN_B, WIN_R_PX)) > 0:
            return GREY
        if sd_round_box(px, py, (WIN_L, WIN_T, WIN_R, WIN_B, WIN_R_PX)) <= 0:
            return BLUE
        return None

    def l3(px, py):
        d = hypot(px - CX, py - CY)
        if d <= R_OUT and d >= R_IN:
            return LGREY
        if d < R_IN:
            return BLUE
        return None

    def l4(px, py):
        d = hypot(px - CX, py - CY)
        win = sd_round_box(px, py, (WIN_L, WIN_T, WIN_R, WIN_B, WIN_R_PX)) <= 0 and d > R_OUT
        if win:
            return YELLOW
        if d <= R_TEXT or hypot(px - CX, py - BADGE_Y) <= BADGE_IN:
            return CYAN
        # Ornament may sit on the ring, the forehead, the claws' annulus, and the horn margin.
        if d <= R_OUT + 2 and py < CY + 20:
            return GREEN
        if py < CY - R_OUT + 8 and abs(px - CX) < R_OUT * 0.6:
            return GREEN
        if R_TEXT < d < R_IN + 10 and py > CY - 10:
            return GREEN
        return None

    def l5(px, py):
        d = hypot(px - CX, py - BADGE_Y)
        if d <= BADGE_IN:
            return BLUE
        if d <= BADGE_R:
            return LGREY
        return None

    print("guides")
    save_crop("L1-outer-border-guide.png", crop_box(0, PLATE[1], W, PLATE[3], 6), l1)
    save_crop("L2-inner-border-guide.png", crop_box(0, INNER[1], W, INNER[3], 6), l2)
    save_crop("L3-ring-guide.png", crop_box(CX - R_OUT - 8, CY - R_OUT - 8, CX + R_OUT + 8, CY + R_OUT + 8, 4), l3)
    save_crop("L4-ornament-guide.png", crop_box(CX - R_OUT - 16, 0, CX + R_OUT + 16, CY + R_IN, 4), l4)
    save_crop("L5-level-badge-guide.png", crop_box(CX - BADGE_R - 8, BADGE_Y - BADGE_R - 8, CX + BADGE_R + 8, BADGE_Y + BADGE_R + 8, 4), l5)

    # Full-frame map, at 1x, no empty wing field. This is the "where".
    buf = new(W, H, (24, 28, 32, 255))
    for y in range(H):
        for x in range(W):
            col = l1(x + 0.5, y + 0.5) or l2(x + 0.5, y + 0.5)
            if col == GREY:
                col = (150, 110, 55, 255) if l1(x + 0.5, y + 0.5) else (190, 150, 80, 255)
            if col is None:
                col = l3(x + 0.5, y + 0.5)
                if col == LGREY:
                    col = (210, 170, 90, 255)
                elif col == BLUE:
                    col = (70, 78, 88, 255)
            if col is None and hypot(x + 0.5 - CX, y + 0.5 - BADGE_Y) <= BADGE_R:
                col = (220, 180, 100, 255)
            if col is not None:
                put(buf, W, x, y, col)
            # Text well and bar keep-out drawn over, so the map shows what stays clear.
            d = hypot(x + 0.5 - CX, y + 0.5 - CY)
            if d <= R_TEXT:
                put(buf, W, x, y, (0, 180, 180, 255))
    write_png(os.path.join(GUIDES, "L0-stack-preview.png"), W, H, buf)
    crops["L0-stack-preview.png"] = (0, 0, W, H)

    lines = ["# Crop origin on the 2x frame canvas (x y w h), except L0 which is 1x.", f"canvas {W * k} {H * k}"]
    for name, (x, y, w, h) in crops.items():
        lines.append(f"{name} {x} {y} {w} {h}")
    with open(os.path.join(GUIDES, "offsets.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    # The old full-canvas back/front guides are the oversized ones.
    for stale in ("L4-ornament-back-guide.png", "L4-ornament-front-guide.png"):
        p = os.path.join(GUIDES, stale)
        if os.path.exists(p):
            os.remove(p)


def lua_snippet(art_h, sy, sw, sh):
    top_metal = WIN_T - PLATE[1]
    cap = WIN_L - PLATE[0]
    return f"""-- Generated by tools/Paint-Frame.py. One geometry for every variant.
art = {{ 0, 1, 0, {art_h / ATLAS_H:.6f} }}
strip = {{ 0, {sw / ATLAS_W:.6f}, {sy / ATLAS_H:.6f}, {(sy + sh) / ATLAS_H:.6f} }}
stripPx = {{ w = {sw}, h = {sh} }}
stripSlice = {{ top = {top_metal * K}, right = {cap * K}, bottom = {top_metal * K}, left = {cap * K} }}
w = {W}, h = {H}
cx = {CX}, cy = {CY}, rIn = {R_IN}, rOut = {R_OUT}
winL = {WIN_L}, winR = {WIN_R}, winT = {WIN_T}, winB = {WIN_B}
cut = {{ {WIN_L}, {WIN_R}, {WIN_T}, {WIN_B} }}
hidden = {HIDDEN}
plateL = {PLATE[0]}, plateR = {PLATE[2]}, plateT = {PLATE[1]}, plateB = {PLATE[3]}
pivotY = {PLATE[3] - 18}
laneL = {{ 16, {CX - R_OUT - 12} }}
laneR = {{ {CX + R_OUT + 12}, {W - 16} }}
"""


def main():
    print("painting")
    metal_a, metal_l, orn_a, orn_l = build_masks()
    well, bars, digits = audit(orn_a)
    print(f"ornament in text well: {well}  on bars: {bars}  on level digits: {digits}")
    if well or bars or digits:
        raise SystemExit("ornament crossed a keep-out")

    guides()
    os.makedirs(MEDIA, exist_ok=True)
    os.makedirs(PREVIEW, exist_ok=True)
    chain_tga(os.path.join(MEDIA, "chain-gold.tga"), GOLD)
    chain_tga(os.path.join(MEDIA, "chain-silver.tga"), SILVER)
    stripes_tga(os.path.join(MEDIA, "stripes.tga"))

    scale = TEXT_MIN / NAME_PX
    min_w, min_h = round(W * scale), round(H * scale)
    sheet_w, sheet_h = W, H * 4
    sheet = bytearray(sheet_w * sheet_h * 4)
    snippet = None
    for index, (name, pal, elite) in enumerate((
        ("plain", GOLD, False),
        ("rare", SILVER, False),
        ("elite", GOLD, True),
        ("rareelite", SILVER, True),
    )):
        rgba = compose(metal_a, metal_l, orn_a, orn_l, pal, elite)
        under = fill_under(rgba)
        write_png(os.path.join(PREVIEW, f"{name}.png"), W * K, H * K, under)
        small = downsample(under, W * K, H * K, min_w, min_h)
        write_png(os.path.join(PREVIEW, f"{name}-min.png"), min_w, min_h, small)
        one = downsample(under, W * K, H * K, W, H)
        for y in range(H):
            sheet[(index * H + y) * W * 4:(index * H + y) * W * 4 + W * 4] = one[y * W * 4:(y + 1) * W * 4]
        strip, sw, sh = board_strip(rgba)
        atlas, art_h, sy, sw, sh = pack_atlas(rgba, strip, sw, sh)
        write_tga(os.path.join(MEDIA, f"frame-{name}.tga"), ATLAS_W, ATLAS_H, atlas)
        snippet = (art_h, sy, sw, sh)
        print(f"  frame-{name}.tga")

    write_png(os.path.join(PREVIEW, "sheet.png"), sheet_w, sheet_h, sheet)
    # Clearance check: elite at 1x with the name box and the text well marked.
    elite = downsample(
        fill_under(compose(metal_a, metal_l, orn_a, orn_l, GOLD, True)),
        W * K, H * K, W, H,
    )
    mark(elite, W)
    write_png(os.path.join(PREVIEW, "clearance.png"), W, H, elite)
    text = lua_snippet(*snippet)
    # Not .lua: the addon checker would try to load a fragment that is not a file.
    with open(os.path.join(ROOT, "template", "layout-snippet.txt"), "w", encoding="utf-8") as f:
        f.write(text)
    print(text)
    print(f"min frame {min_w}x{min_h} at name {TEXT_MIN}px")
    old = os.path.join(MEDIA, "frame-gold.tga")
    if os.path.exists(old):
        os.remove(old)
        print("removed frame-gold.tga")


def mark(rgba, w):
    """Cyan name box and text well, so a covered glyph shows as metal over cyan."""
    def blend(x, y):
        if not (0 <= x < w and 0 <= y < H):
            return
        i = (y * w + x) * 4
        rgba[i] = (rgba[i] + 0) // 2
        rgba[i + 1] = (rgba[i + 1] + 220) // 2
        rgba[i + 2] = (rgba[i + 2] + 220) // 2

    x0 = WIN_L + 16
    x1 = CX - HIDDEN - 14
    y0 = CY - NAME_PX // 2
    y1 = CY + NAME_PX // 2
    for y in range(y0, y1):
        for x in range(x0, x1):
            blend(x, y)
    for y in range(H):
        for x in range(W):
            if hypot(x + 0.5 - CX, y + 0.5 - CY) <= R_TEXT:
                blend(x, y)


if __name__ == "__main__":
    import sys
    if "--procedural" not in sys.argv:
        raise SystemExit(
            "Paint-Frame.py draws the old procedural plate and overwrites Media\\frame-*.tga.\n"
            "The paint mask is tools\\Build-FrameTemplate.py (guides\\frame-template.png).\n"
            "Pass --procedural only to draw that old plate on purpose."
        )
    main()
