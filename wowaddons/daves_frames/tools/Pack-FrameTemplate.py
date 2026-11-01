"""Register, key, and pack an AI-painted daves_frames plate into Media/*.tga.

Reads an AI painting made on `guides/frame-template-ai.png` (2048 x 1152, 16:9)
or `guides/frame-template.png` (2048 x 600), in PNG, JPG, or TGA format, or an
already-aligned 2048 x 600 RGBA plate:

1. Finds the three blue holes (left bar, portrait, right bar) and the yellow
   level hole and fits a least-squares X/Y transform onto the 2048 x 600 single
   frame mask.
2. Samples only the paintable plate regions (grey outer frame, green 5 px lip,
   orange portrait ring, white level ring) while rejecting key colours and
   2-pixel AI fringe halos, smoothly inpaints any missing plate pixels, and
   applies 1-pixel signed-distance anti-aliasing to every edge.
3. Builds the matching 2x 600 x 220 9-slice aura board strip from the plate's
   left and right ends over a dark recessed billboard backing, packs both into
   the 2048 x 1024 TGA atlas, and optionally grades a matching silver atlas
   (`--silver-out`) for rare / rareelite.

Usage:
    py -3 tools/Pack-FrameTemplate.py --source painted.png --out Media/frame-plain.tga --silver-out Media/frame-rare.tga --preview tools/template/preview/plain-preview.png
"""

from __future__ import annotations

import argparse
import importlib.util
import math
import os
import shutil
import struct
import subprocess
import tempfile
import zlib
from collections import deque

ROOT = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(ROOT)

_spec = importlib.util.spec_from_file_location("build_tpl", os.path.join(ROOT, "Build-FrameTemplate.py"))
TPL = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(TPL)

K = TPL.SCALE
IW, IH = TPL.W * K, TPL.H * K
ATLAS_W, ATLAS_H = TPL.ATLAS_W, TPL.ATLAS_H

# Exact 2x mask coordinates (image pixels).
CX, CY = TPL.CX * K, TPL.CY * K                        # 1024, 272
R_IN, R_OUT = TPL.R_IN * K, TPL.R_OUT * K              # 210, 256
BX, BY = TPL.BADGE[0] * K, TPL.BADGE[1] * K            # 1024, 504
BR_IN, BR_OUT = TPL.BADGE_R_IN * K, TPL.BADGE_R_OUT * K  # 60, 92
HL_L, HL_R = TPL.HOLE_L * K, TPL.HOLE_LI * K           # 70, 758
HR_L, HR_R = TPL.HOLE_RI * K, TPL.HOLE_R * K           # 1290, 1978
WIN_T, WIN_B = TPL.WIN_T * K, TPL.WIN_B * K            # 216, 328
PL_L, PL_R = TPL.PLATE_L * K, TPL.PLATE_R * K          # 16, 2032
PL_T, PL_B = TPL.PLATE_T * K, TPL.PLATE_B * K          # 162, 382
STRIP_Y, STRIP_W, STRIP_H = TPL.STRIP_Y, TPL.STRIP_W, TPL.STRIP_H  # 608, 600, 220

SILVER_PAL = ((18, 22, 28), (146, 158, 174), (240, 245, 250))


# ---------------------------------------------------------------------------
# Image I/O (pure stdlib PNG/TGA + Windows System.Drawing fallback for JPEG)
# ---------------------------------------------------------------------------

def read_png(path: str):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"Not a PNG file: {path}")
    pos = 8
    w = h = ct = None
    idat = bytearray()
    while pos < len(data):
        n = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if tag == b"IHDR":
            w, h, bd, ct = struct.unpack(">IIBB", chunk[:10])
            if bd != 8 or ct not in (2, 6):
                raise SystemExit(f"Unsupported PNG format (bit_depth={bd}, color_type={ct}) in {path}")
        elif tag == b"IDAT":
            idat.extend(chunk)
        elif tag == b"IEND":
            break
    raw = zlib.decompress(bytes(idat))
    bpp = 3 if ct == 2 else 4
    stride = w * bpp
    out = bytearray(w * h * 4)
    i = 0
    prev = bytearray(stride)

    for y in range(h):
        f = raw[i]
        i += 1
        row = bytearray(raw[i:i + stride])
        i += stride
        if f == 1:
            for x in range(bpp, stride):
                row[x] = (row[x] + row[x - bpp]) & 255
        elif f == 2:
            for x in range(stride):
                row[x] = (row[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + ((left + prev[x]) >> 1)) & 255
        elif f == 4:
            for x in range(stride):
                a = row[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                row[x] = (row[x] + pr) & 255
        elif f != 0:
            raise SystemExit(f"Unsupported PNG filter {f}")
        prev = row
        if bpp == 4:
            out[y * w * 4:(y + 1) * w * 4] = row
        else:
            o = y * w * 4
            for x in range(w):
                s = x * 3
                out[o] = row[s]
                out[o + 1] = row[s + 1]
                out[o + 2] = row[s + 2]
                out[o + 3] = 255
                o += 4
    return w, h, out


def read_tga(path: str):
    data = open(path, "rb").read()
    if len(data) < 18 or data[2] != 2 or data[16] != 32:
        raise SystemExit(f"Unsupported TGA (expected uncompressed 32-bit): {path}")
    w = data[12] + (data[13] << 8)
    h = data[14] + (data[15] << 8)
    top_down = (data[17] & 0x20) != 0
    out = bytearray(w * h * 4)
    for y in range(h):
        sy = y if top_down else (h - 1 - y)
        src_row = 18 + sy * w * 4
        dst_row = y * w * 4
        for x in range(w):
            s = src_row + x * 4
            d = dst_row + x * 4
            out[d] = data[s + 2]
            out[d + 1] = data[s + 1]
            out[d + 2] = data[s]
            out[d + 3] = data[s + 3]
    return w, h, out


def read_jpeg(path: str):
    fd, tmp_png = tempfile.mkstemp(suffix=".png")
    os.close(fd)
    try:
        ps = (
            "Add-Type -AssemblyName System.Drawing; "
            f"$img = [Drawing.Image]::FromFile('{os.path.abspath(path)}'); "
            f"$img.Save('{tmp_png}', [Drawing.Imaging.ImageFormat]::Png); "
            "$img.Dispose()"
        )
        subprocess.check_call(["powershell", "-NoProfile", "-Command", ps])
        return read_png(tmp_png)
    finally:
        if os.path.exists(tmp_png):
            os.remove(tmp_png)


def read_image(path: str):
    low = path.lower()
    if low.endswith(".tga"):
        return read_tga(path)
    if low.endswith((".jpg", ".jpeg")):
        return read_jpeg(path)
    with open(path, "rb") as f:
        sig = f.read(4)
    if sig[:2] == b"\xff\xd8":
        return read_jpeg(path)
    return read_png(path)


def write_png(path: str, w: int, h: int, rgba: bytearray):
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw.extend(rgba[y * stride:(y + 1) * stride])

    def chunk(tag, payload):
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 6)))
        f.write(chunk(b"IEND", b""))


def write_tga(path: str, w: int, h: int, rgba: bytearray):
    head = bytearray(18)
    head[2] = 2
    head[12] = w & 255
    head[13] = (w >> 8) & 255
    head[14] = h & 255
    head[15] = (h >> 8) & 255
    head[16] = 32
    head[17] = 0x28  # 8-bit alpha, top-left origin
    bgra = bytearray(w * h * 4)
    bgra[0::4] = rgba[2::4]
    bgra[1::4] = rgba[1::4]
    bgra[2::4] = rgba[0::4]
    bgra[3::4] = rgba[3::4]
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(head)
        f.write(bgra)


# ---------------------------------------------------------------------------
# Key classification & multi-hole registration
# ---------------------------------------------------------------------------

def is_blue_key(r: int, g: int, b: int) -> bool:
    return b > 150 and r < 90 and g < 100 and (b - (r if r > g else g)) > 80


def is_yellow_key(r: int, g: int, b: int) -> bool:
    return r > 195 and g > 195 and b < 75 and ((r if r < g else g) - b) > 130 and abs(r - g) < 45


def is_magenta_key(r: int, g: int, b: int) -> bool:
    return r > 150 and b > 140 and g < 110 and ((r if r < b else b) - g) > 70


def find_blobs(w: int, h: int, rgba: bytearray, pred, step: int = 2, min_cells: int = 40):
    """Find bounding boxes & centroids of key-coloured connected components."""
    gw, gh = w // step, h // step
    grid = bytearray(gw * gh)
    for gy in range(gh):
        y = gy * step
        row_o = y * w * 4
        grow = gy * gw
        for gx in range(gw):
            o = row_o + (gx * step) * 4
            if rgba[o + 3] >= 128 and pred(rgba[o], rgba[o + 1], rgba[o + 2]):
                grid[grow + gx] = 1

    seen = bytearray(gw * gh)
    blobs = []
    for gy in range(gh):
        for gx in range(gw):
            idx = gy * gw + gx
            if not grid[idx] or seen[idx]:
                continue
            q = deque([idx])
            seen[idx] = 1
            count = 0
            x0 = x1 = gx
            y0 = y1 = gy
            while q:
                cur = q.popleft()
                count += 1
                cx_, cy_ = cur % gw, cur // gw
                if cx_ < x0:
                    x0 = cx_
                elif cx_ > x1:
                    x1 = cx_
                if cy_ < y0:
                    y0 = cy_
                elif cy_ > y1:
                    y1 = cy_
                for nx, ny in ((cx_ - 1, cy_), (cx_ + 1, cy_), (cx_, cy_ - 1), (cx_, cy_ + 1)):
                    if 0 <= nx < gw and 0 <= ny < gh:
                        ni = ny * gw + nx
                        if grid[ni] and not seen[ni]:
                            seen[ni] = 1
                            q.append(ni)
            if count < min_cells:
                continue
            rx0 = max(0, x0 * step - step - 1)
            rx1 = min(w - 1, x1 * step + step + 1)
            ry0 = max(0, y0 * step - step - 1)
            ry1 = min(h - 1, y1 * step + step + 1)
            fx0, fx1, fy0, fy1 = rx1, rx0, ry1, ry0
            sx_sum = sy_sum = fn = 0
            for yy in range(ry0, ry1 + 1):
                ro = yy * w * 4
                for xx in range(rx0, rx1 + 1):
                    o = ro + xx * 4
                    if rgba[o + 3] >= 128 and pred(rgba[o], rgba[o + 1], rgba[o + 2]):
                        fn += 1
                        sx_sum += xx + 0.5
                        sy_sum += yy + 0.5
                        if xx < fx0:
                            fx0 = xx
                        if xx > fx1:
                            fx1 = xx
                        if yy < fy0:
                            fy0 = yy
                        if yy > fy1:
                            fy1 = yy
            if fn > 0:
                blobs.append({
                    "n": fn,
                    "l": float(fx0),
                    "r": float(fx1 + 1),
                    "t": float(fy0),
                    "b": float(fy1 + 1),
                    "cx": sx_sum / fn,
                    "cy": sy_sum / fn,
                })
    blobs.sort(key=lambda b: b["n"], reverse=True)
    return blobs


def fit_line(pairs):
    """Least-squares fit y = s * x + o across (mask_coord, src_coord) pairs."""
    n = len(pairs)
    mx = sum(p[0] for p in pairs) / n
    my = sum(p[1] for p in pairs) / n
    num = sum((p[0] - mx) * (p[1] - my) for p in pairs)
    den = sum((p[0] - mx) ** 2 for p in pairs)
    s = num / den if den > 1e-9 else 1.0
    o = my - s * mx
    max_err = max(abs((s * p[0] + o) - p[1]) for p in pairs)
    return s, o, max_err


def fit_source_transform(w: int, h: int, rgba: bytearray):
    """Fit global scale/offset plus local ring inner-radius adjustments onto 2048 x 600."""
    if w == IW and h in (IH, ATLAS_H):
        probes = ((414, 272), (1024, 272), (1634, 272), (1024, 504))
        if all(rgba[(py * w + px) * 4 + 3] < 32 for px, py in probes):
            print(f"source {w}x{h}: pre-aligned RGBA plate detected (1:1 transform)")
            return {
                "sx": 1.0, "ox": 0.0, "sy": 1.0, "oy": 0.0,
                "pre_aligned": True, "port": None, "level": None,
            }

    blue = find_blobs(w, h, rgba, is_blue_key)
    if len(blue) < 3:
        raise SystemExit(
            f"Expected 3 blue holes (left bar, portrait, right bar) in source {w}x{h}, found {len(blue)}."
        )
    three = sorted(blue[:3], key=lambda b: b["cx"])
    left_bar, portrait, right_bar = three[0], three[1], three[2]

    yellow_all = [b for b in find_blobs(w, h, rgba, is_yellow_key, min_cells=15) if b["cy"] > portrait["cy"]]
    level_hole = yellow_all[0] if yellow_all else None

    # Fit global X/Y from bar boxes and circle centres (immune to slight inner-bevel thickness differences on rings).
    x_pairs = [
        (float(HL_L), left_bar["l"]),
        (0.5 * (HL_L + HL_R), left_bar["cx"]),
        (float(HL_R), left_bar["r"]),
        (float(CX), portrait["cx"]),
        (float(HR_L), right_bar["l"]),
        (0.5 * (HR_L + HR_R), right_bar["cx"]),
        (float(HR_R), right_bar["r"]),
    ]
    y_pairs = [
        (float(WIN_T), left_bar["t"]),
        (float(WIN_T), right_bar["t"]),
        (0.5 * (WIN_T + WIN_B), left_bar["cy"]),
        (0.5 * (WIN_T + WIN_B), right_bar["cy"]),
        (float(WIN_B), left_bar["b"]),
        (float(WIN_B), right_bar["b"]),
    ]
    if level_hole:
        x_pairs.append((float(BX), level_hole["cx"]))
        y_pairs.append((float(BY), level_hole["cy"]))
    else:
        y_pairs.append((float(CY - R_IN), portrait["t"]))

    sx, ox, ex = fit_line(x_pairs)
    sy, oy, ey = fit_line(y_pairs)
    aspect_drift = abs(sx - sy) / max(sx, 1e-9) * 100.0
    print(
        f"registered {w}x{h} -> {IW}x{IH}: "
        f"sx={sx:.5f} ox={ox:.2f} (max_err={ex:.2f}px) | "
        f"sy={sy:.5f} oy={oy:.2f} (max_err={ey:.2f}px) | "
        f"aspect_drift={aspect_drift:.2f}%"
        + ("" if level_hole else " [no yellow level hole; fitted from portrait+bars]")
    )
    if ex > 6.0 or ey > 6.0 or aspect_drift > 4.0:
        print(
            f"WARNING: high geometry drift detected (ex={ex:.2f}px, ey={ey:.2f}px, aspect_drift={aspect_drift:.2f}%). "
            "Ensure painting started from guides/frame-template-ai.png (2048x1152, 16:9)."
        )

    # Local radial inner-rim anchors so slightly thicker painted ring bevels aren't shaved off.
    port_cx = portrait["cx"]
    port_cy = sy * CY + oy
    port_rin_x = 0.5 * (portrait["r"] - portrait["l"])
    port_rin_y = max(10.0, port_cy - portrait["t"])
    port_info = (port_cx, port_cy, port_rin_x, port_rin_y)

    lvl_info = None
    if level_hole:
        lvl_rin_x = 0.5 * (level_hole["r"] - level_hole["l"])
        lvl_rin_y = 0.5 * (level_hole["b"] - level_hole["t"])
        lvl_info = (level_hole["cx"], level_hole["cy"], lvl_rin_x, lvl_rin_y)

    return {
        "sx": sx, "ox": ox, "sy": sy, "oy": oy,
        "pre_aligned": False, "port": port_info, "level": lvl_info,
    }


# ---------------------------------------------------------------------------
# Signed-distance plate coverage, sampling & inpainting
# ---------------------------------------------------------------------------

def build_clean_metal_mask(w: int, h: int, rgba: bytearray, erode: bool = True) -> bytearray:
    """1 where source pixel is usable metal (not a flat key colour or JPEG 4:2:0 chroma halo)."""
    key = bytearray(w * h)
    for i in range(w * h):
        o = i * 4
        r, g, b, a = rgba[o], rgba[o + 1], rgba[o + 2], rgba[o + 3]
        if a < 128 or is_magenta_key(r, g, b) or is_blue_key(r, g, b) or is_yellow_key(r, g, b):
            key[i] = 1
    if not erode:
        return bytearray(0 if k else 1 for k in key)

    # Mark pixels within 5px of a flat key that carry strong magenta or blue JPEG 4:2:0 chroma bleed.
    near5_h = bytearray(w * h)
    for y in range(h):
        ro = y * w
        for x in range(w):
            x0 = 0 if x < 5 else x - 5
            x1 = w if x + 6 > w else x + 6
            for xx in range(x0, x1):
                if key[ro + xx]:
                    near5_h[ro + x] = 1
                    break
    for y in range(h):
        y0 = 0 if y < 5 else y - 5
        y1 = h if y + 6 > h else y + 6
        ro = y * w
        for x in range(w):
            if key[ro + x]:
                continue
            near = False
            for yy in range(y0, y1):
                if near5_h[yy * w + x]:
                    near = True
                    break
            if near:
                o = (ro + x) * 4
                r, g, b = rgba[o], rgba[o + 1], rgba[o + 2]
                if (min(r, b) - g) > 22 or (b - (r if r > g else g)) > 32:
                    key[ro + x] = 1

    # Dilate key mask by 2px (separable 5x5 box) to strip remaining AI anti-aliasing fringe.
    horiz = bytearray(w * h)
    for y in range(h):
        ro = y * w
        for x in range(w):
            x0 = 0 if x < 2 else x - 2
            x1 = w if x + 3 > w else x + 3
            for xx in range(x0, x1):
                if key[ro + xx]:
                    horiz[ro + x] = 1
                    break
    clean = bytearray(w * h)
    for y in range(h):
        y0 = 0 if y < 2 else y - 2
        y1 = h if y + 3 > h else y + 3
        ro = y * w
        for x in range(w):
            bad = False
            for yy in range(y0, y1):
                if horiz[yy * w + x]:
                    bad = True
                    break
            if not bad:
                clean[ro + x] = 1
    return clean


def sample_valid_rgb(rgba: bytearray, clean: bytearray, w: int, h: int, fx: float, fy: float):
    """Bilinear RGB sample using only clean (non-key, non-fringe) source pixels."""
    x0 = int(math.floor(fx - 0.5))
    y0 = int(math.floor(fy - 0.5))
    tx = (fx - 0.5) - x0
    ty = (fy - 0.5) - y0
    acc_r = acc_g = acc_b = wsum = 0.0
    for dy, wy in ((0, 1.0 - ty), (1, ty)):
        yy = y0 + dy
        if yy < 0 or yy >= h:
            continue
        ro = yy * w
        for dx, wx in ((0, 1.0 - tx), (1, tx)):
            xx = x0 + dx
            if xx < 0 or xx >= w:
                continue
            idx = ro + xx
            if not clean[idx]:
                continue
            wgt = wx * wy
            if wgt <= 0.0:
                continue
            o = idx * 4
            acc_r += rgba[o] * wgt
            acc_g += rgba[o + 1] * wgt
            acc_b += rgba[o + 2] * wgt
            wsum += wgt
    if wsum <= 1e-5:
        return None
    inv = 1.0 / wsum
    return (
        int(acc_r * inv + 0.5),
        int(acc_g * inv + 0.5),
        int(acc_b * inv + 0.5),
    )


def sample_bilinear_rgba(rgba: bytearray, w: int, h: int, fx: float, fy: float):
    x0 = int(math.floor(fx - 0.5))
    y0 = int(math.floor(fy - 0.5))
    tx = (fx - 0.5) - x0
    ty = (fy - 0.5) - y0
    acc = [0.0, 0.0, 0.0, 0.0]
    for dy, wy in ((0, 1.0 - ty), (1, ty)):
        yy = 0 if y0 + dy < 0 else (h - 1 if y0 + dy >= h else y0 + dy)
        ro = yy * w * 4
        for dx, wx in ((0, 1.0 - tx), (1, tx)):
            xx = 0 if x0 + dx < 0 else (w - 1 if x0 + dx >= w else x0 + dx)
            o = ro + xx * 4
            wgt = wx * wy
            acc[0] += rgba[o] * wgt
            acc[1] += rgba[o + 1] * wgt
            acc[2] += rgba[o + 2] * wgt
            acc[3] += rgba[o + 3] * wgt
    return int(acc[0] + 0.5), int(acc[1] + 0.5), int(acc[2] + 0.5), int(acc[3] + 0.5)


def cov(sd: float) -> int:
    t = 0.5 - sd
    if t <= 0.0:
        return 0
    if t >= 1.0:
        return 255
    return int(t * 255.0 + 0.5)


def sd_box(px: float, py: float, l: float, t: float, r: float, b: float) -> float:
    dx = max(l - px, px - r)
    dy = max(t - py, py - b)
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    inside_d = min(max(dx, dy), 0.0)
    return outside + inside_d


def sd_round_box(px: float, py: float, l: float, t: float, r: float, b: float, rad: float) -> float:
    if rad <= 0.0:
        return sd_box(px, py, l, t, r, b)
    return sd_box(px, py, l + rad, t + rad, r - rad, b - rad) - rad


def plate_coverage(x: int, y: int, outer_rad_px: float = 0.0, seal_only: bool = False) -> int:
    """Exact 1px-antialiased alpha coverage of the 2048 x 600 single-box plate (or inner bar/ring seal)."""
    px, py = x + 0.5, y + 0.5
    d_lvl = math.hypot(px - BX, py - BY)
    sd_lvl_hole = d_lvl - BR_IN
    sd_lvl_ring = max(d_lvl - BR_OUT, -sd_lvl_hole)

    d_port = math.hypot(px - CX, py - CY)
    sd_port_hole = d_port - R_IN
    sd_port_ring = max(d_port - R_OUT, -sd_port_hole)

    sd_lhole = sd_box(px, py, HL_L, WIN_T, HL_R, WIN_B)
    sd_rhole = sd_box(px, py, HR_L, WIN_T, HR_R, WIN_B)
    if seal_only:
        pad = (TPL.LIP + 2) * K
        sd_rect = sd_box(px, py, HL_L - pad, WIN_T - pad, HR_R + pad, WIN_B + pad)
    else:
        sd_rect = sd_round_box(px, py, PL_L, PL_T, PL_R, PL_B, outer_rad_px)
    sd_bar_plate = max(sd_rect, -sd_lhole, -sd_rhole, -sd_port_hole)

    sd_base = min(sd_bar_plate, sd_port_ring)
    sd_union = min(sd_base, sd_lvl_ring)
    sd_final = max(sd_union, -sd_lvl_hole)
    return cov(sd_final)


def magenta_edge_chroma_key(r: int, g: int, b: int, a: int):
    """Chroma-key + despill against magenta (#FF00FF), blue, and yellow for --organic-edge corners."""
    if a < 16 or is_blue_key(r, g, b) or is_yellow_key(r, g, b):
        return 0, 0, 0, 0
    mag = (min(r, b) - g) if (r > 90 and b > 80) else 0
    if mag >= 115:
        return 0, 0, 0, 0
    out_a = a
    if mag > 25:
        fade = int(255 * (115 - mag) / 90.0)
        out_a = min(out_a, fade)
        cap = g + 15
        r = min(r, cap + (r - b if r > b else 0))
        b = min(b, cap)
    return max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)), out_a


def map_mask_to_source(px: float, py: float, xf: dict):
    sx, ox, sy, oy = xf["sx"], xf["ox"], xf["sy"], xf["oy"]
    bx_src = sx * px + ox
    by_src = sy * py + oy
    if xf["pre_aligned"]:
        return bx_src, by_src

    lvl = xf["level"]
    if lvl is not None:
        dx, dy = px - BX, py - BY
        d_lvl = math.hypot(dx, dy)
        if BR_IN - 2.0 <= d_lvl <= BR_OUT + 8.0 and d_lvl > 1e-5:
            lcx, lcy, lrx, lry = lvl
            u = max(0.0, min(1.0, (d_lvl - BR_IN) / (BR_OUT - BR_IN)))
            rx = lrx + u * (BR_OUT * sx - lrx)
            ry = lry + u * (BR_OUT * sy - lry)
            lx = lcx + (dx / d_lvl) * rx
            ly = lcy + (dy / d_lvl) * ry
            if d_lvl <= BR_OUT:
                return lx, ly
            w = (BR_OUT + 8.0 - d_lvl) / 8.0
            return lx * w + bx_src * (1.0 - w), ly * w + by_src * (1.0 - w)

    port = xf["port"]
    if port is not None:
        dx, dy = px - CX, py - CY
        d_port = math.hypot(dx, dy)
        if R_IN - 2.0 <= d_port <= R_OUT + 6.0 and d_port > 1e-5:
            pcx, pcy, prx, pry = port
            u = max(0.0, min(1.0, (d_port - R_IN) / (R_OUT - R_IN)))
            rx = prx + u * (R_OUT * sx - prx)
            ry = pry + u * (R_OUT * sy - pry)
            px_s = pcx + (dx / d_port) * rx
            py_s = pcy + (dy / d_port) * ry
            if d_port <= R_OUT:
                return px_s, py_s
            w = (R_OUT + 6.0 - d_port) / 6.0
            return px_s * w + bx_src * (1.0 - w), py_s * w + by_src * (1.0 - w)

    return bx_src, by_src


def despill_boundary_rgb(r: int, g: int, b: int):
    """Strip residual JPEG 4:2:0 magenta/blue chroma bleed near mask boundaries."""
    mag = min(r, b) - g
    if mag > 5:
        drop = mag - 3
        b = max(0, b - drop)
        r = max(0, r - (drop * 3) // 4)
    blu = b - (r if r > g else g)
    if blu > 12:
        b = max(0, b - (blu - 8))
    return r, g, b


def extract_plate(
    sw: int,
    sh: int,
    src: bytearray,
    xf: dict,
    erode_keys: bool = True,
    outer_rad_px: float = 0.0,
    organic_edge: bool = False,
):
    clean = build_clean_metal_mask(sw, sh, src, erode=erode_keys)
    out = bytearray(IW * IH * 4)
    need_fill = []
    have_rgb = bytearray(IW * IH)

    for y in range(IH):
        py = y + 0.5
        ro = y * IW
        for x in range(IW):
            px = x + 0.5
            pa = plate_coverage(x, y, outer_rad_px=outer_rad_px, seal_only=organic_edge)
            outer_pa = plate_coverage(x, y, outer_rad_px=outer_rad_px, seal_only=False) if organic_edge else pa
            fx, fy = map_mask_to_source(px, py, xf)
            idx = ro + x
            o = idx * 4
            if pa > 0:
                rgb = sample_valid_rgb(src, clean, sw, sh, fx, fy)
                if rgb is not None:
                    out[o], out[o + 1], out[o + 2], out[o + 3] = rgb[0], rgb[1], rgb[2], pa
                    have_rgb[idx] = 1
                else:
                    out[o + 3] = pa
                    need_fill.append(idx)
            elif organic_edge and outer_pa > 0:
                sr, sg, sb, sa = sample_bilinear_rgba(src, sw, sh, fx, fy)
                kr, kg, kb, ka = magenta_edge_chroma_key(sr, sg, sb, sa)
                fa = (ka * outer_pa) // 255
                if fa >= 20:
                    out[o], out[o + 1], out[o + 2], out[o + 3] = kr, kg, kb, fa
                    have_rgb[idx] = 1

    if need_fill:
        q = deque()
        for idx in need_fill:
            x, y = idx % IW, idx // IW
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < IW and 0 <= ny < IH and have_rgb[ny * IW + nx]:
                    q.append(idx)
                    break
        filled = []
        queued = bytearray(IW * IH)
        for idx in q:
            queued[idx] = 1
        while q:
            idx = q.popleft()
            if have_rgb[idx]:
                continue
            x, y = idx % IW, idx // IW
            sr = sg = sb = n = 0
            for dy in (-1, 0, 1):
                ny = y + dy
                if not (0 <= ny < IH):
                    continue
                for dx in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    nx = x + dx
                    if 0 <= nx < IW and have_rgb[ny * IW + nx]:
                        no = (ny * IW + nx) * 4
                        sr += out[no]
                        sg += out[no + 1]
                        sb += out[no + 2]
                        n += 1
            if n == 0:
                continue
            o = idx * 4
            out[o], out[o + 1], out[o + 2] = sr // n, sg // n, sb // n
            have_rgb[idx] = 1
            filled.append(idx)
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < IW and 0 <= ny < IH:
                    ni = ny * IW + nx
                    if out[ni * 4 + 3] > 0 and not have_rgb[ni] and not queued[ni]:
                        queued[ni] = 1
                        q.append(ni)
        for _ in range(4):
            updates = []
            for idx in filled:
                x, y = idx % IW, idx // IW
                sr = sg = sb = n = 0
                for dy in (-1, 0, 1):
                    ny = y + dy
                    if 0 <= ny < IH:
                        for dx in (-1, 0, 1):
                            nx = x + dx
                            if 0 <= nx < IW and have_rgb[ny * IW + nx]:
                                no = (ny * IW + nx) * 4
                                sr += out[no]
                                sg += out[no + 1]
                                sb += out[no + 2]
                                n += 1
                if n:
                    updates.append((idx * 4, sr // n, sg // n, sb // n))
            for o, r, g, b in updates:
                out[o], out[o + 1], out[o + 2] = r, g, b
        print(f"inpainted {len(filled)} key-covered plate pixels")

    # Despill residual JPEG 4:2:0 magenta/blue chroma bleed within 12px of any plate boundary.
    if erode_keys:
        edge_h = bytearray(IW * IH)
        for y in range(IH):
            ro = y * IW
            for x in range(IW):
                x0 = 0 if x < 12 else x - 12
                x1 = IW if x + 13 > IW else x + 13
                for xx in range(x0, x1):
                    if out[(ro + xx) * 4 + 3] < 240:
                        edge_h[ro + x] = 1
                        break
        for y in range(IH):
            y0 = 0 if y < 12 else y - 12
            y1 = IH if y + 13 > IH else y + 13
            ro = y * IW
            for x in range(IW):
                o = (ro + x) * 4
                if out[o + 3] == 0:
                    continue
                near_edge = False
                for yy in range(y0, y1):
                    if edge_h[yy * IW + x]:
                        near_edge = True
                        break
                if near_edge:
                    r, g, b = despill_boundary_rgb(out[o], out[o + 1], out[o + 2])
                    out[o], out[o + 1], out[o + 2] = r, g, b

    return out


# ---------------------------------------------------------------------------
# Matching 2x 600 x 220 aura board strip & silver grading
# ---------------------------------------------------------------------------

def build_board_strip(plate_rgba: bytearray, cool_backing: bool = False, outer_rad_px: float = 0.0) -> bytearray:
    """Slice left 300px and right 300px of the plate (y=162..382) over a dark recessed billboard fill."""
    run = STRIP_W // 2  # 300
    strip = bytearray(STRIP_W * STRIP_H * 4)
    border = (TPL.OUTER + TPL.LIP) * K  # 54 px metal border all round

    top_c = (11, 13, 17) if cool_backing else (13, 10, 8)
    bot_c = (24, 28, 35) if cool_backing else (28, 22, 16)
    in_l, in_r = border - 4, STRIP_W - border + 4
    in_t, in_b = border - 4, STRIP_H - border + 4
    for y in range(in_t, in_b):
        t = (y - in_t) / max(1, in_b - 1 - in_t)
        br = int(top_c[0] + (bot_c[0] - top_c[0]) * t + 0.5)
        bg = int(top_c[1] + (bot_c[1] - top_c[1]) * t + 0.5)
        bb = int(top_c[2] + (bot_c[2] - top_c[2]) * t + 0.5)
        dy_top = y - border
        dy_bot = (STRIP_H - 1 - border) - y
        shade = 1.0
        if 0 <= dy_top < 12:
            shade *= 0.42 + 0.58 * (dy_top / 12.0)
        if 0 <= dy_bot < 8:
            shade *= 0.62 + 0.38 * (dy_bot / 8.0)
        ro = y * STRIP_W * 4
        for x in range(in_l, in_r):
            dx_side = min(x - border, (STRIP_W - 1 - border) - x)
            s = shade
            if 0 <= dx_side < 12:
                s *= 0.50 + 0.50 * (dx_side / 12.0)
            o = ro + x * 4
            strip[o] = int(br * s + 0.5)
            strip[o + 1] = int(bg * s + 0.5)
            strip[o + 2] = int(bb * s + 0.5)
            strip[o + 3] = 242

    blend_half = 10
    for y in range(STRIP_H):
        py = PL_T + y
        prow = py * IW * 4
        srow = y * STRIP_W * 4
        for x in range(STRIP_W):
            if x < run:
                px = PL_L + x
            else:
                px = (PL_R - run) + (x - run)
            po = prow + px * 4
            mr, mg, mb, ma = plate_rgba[po], plate_rgba[po + 1], plate_rgba[po + 2], plate_rgba[po + 3]
            if abs(x - run) < blend_half:
                lo = prow + (PL_L + run - 1 - abs(x - run)) * 4
                ro_ = prow + ((PL_R - run) + abs(x - run)) * 4
                if plate_rgba[lo + 3] > 200 and plate_rgba[ro_ + 3] > 200:
                    w_right = (x - (run - blend_half)) / (2.0 * blend_half)
                    w_left = 1.0 - w_right
                    mr = int(plate_rgba[lo] * w_left + plate_rgba[ro_] * w_right + 0.5)
                    mg = int(plate_rgba[lo + 1] * w_left + plate_rgba[ro_ + 1] * w_right + 0.5)
                    mb = int(plate_rgba[lo + 2] * w_left + plate_rgba[ro_ + 2] * w_right + 0.5)
                    ma = max(plate_rgba[lo + 3], plate_rgba[ro_ + 3])
            if ma == 0:
                continue
            do = srow + x * 4
            if ma >= 255 or strip[do + 3] == 0:
                strip[do], strip[do + 1], strip[do + 2], strip[do + 3] = mr, mg, mb, ma
            else:
                da = strip[do + 3]
                inv = 255 - ma
                na = ma + (da * inv) // 255
                strip[do] = (mr * ma + strip[do] * ((da * inv) // 255)) // na
                strip[do + 1] = (mg * ma + strip[do + 1] * ((da * inv) // 255)) // na
                strip[do + 2] = (mb * ma + strip[do + 2] * ((da * inv) // 255)) // na
                strip[do + 3] = na
    if outer_rad_px > 0.0:
        for y in range(STRIP_H):
            ro = y * STRIP_W * 4
            for x in range(STRIP_W):
                ca = cov(sd_round_box(x + 0.5, y + 0.5, 0.0, 0.0, float(STRIP_W), float(STRIP_H), outer_rad_px))
                if ca < 255:
                    o = ro + x * 4
                    strip[o + 3] = (strip[o + 3] * ca) // 255
    return strip


def grade_silver(plate_rgba: bytearray) -> bytearray:
    """Convert a warm gold/bronze plate into forged cool silver, preserving luminance & cracks."""
    out = bytearray(len(plate_rgba))
    dark, mid, light = SILVER_PAL
    for i in range(0, len(plate_rgba), 4):
        a = plate_rgba[i + 3]
        if a == 0:
            continue
        r, g, b = plate_rgba[i], plate_rgba[i + 1], plate_rgba[i + 2]
        lum = int(0.299 * r + 0.587 * g + 0.114 * b + 0.5)
        if lum < 128:
            t = lum / 128.0
            c0, c1 = dark, mid
        else:
            t = (lum - 128) / 127.0
            c0, c1 = mid, light
        out[i] = int(c0[0] + (c1[0] - c0[0]) * t + 0.5)
        out[i + 1] = int(c0[1] + (c1[1] - c0[1]) * t + 0.5)
        out[i + 2] = int(c0[2] + (c1[2] - c0[2]) * t + 0.5)
        out[i + 3] = a
    return out


def pack_atlas(plate_rgba: bytearray, strip_rgba: bytearray) -> bytearray:
    atlas = bytearray(ATLAS_W * ATLAS_H * 4)
    atlas[0:IW * IH * 4] = plate_rgba
    for y in range(STRIP_H):
        s = y * STRIP_W * 4
        d = ((STRIP_Y + y) * ATLAS_W) * 4
        atlas[d:d + STRIP_W * 4] = strip_rgba[s:s + STRIP_W * 4]
    return atlas


def render_preview(plate_rgba: bytearray) -> bytearray:
    """Composite the 2048 x 600 plate over dark background + stand-in bars, portrait, and level circle."""
    out = bytearray(IW * IH * 4)
    for y in range(IH):
        py = y + 0.5
        ro = y * IW * 4
        for x in range(IW):
            px = x + 0.5
            o = ro + x * 4
            br, bg, bb = 20, 22, 25
            d_port = math.hypot(px - CX, py - CY)
            d_lvl = math.hypot(px - BX, py - BY)
            if d_lvl <= BR_IN + 2:
                br, bg, bb = 30, 20, 10
            elif d_port <= R_IN + 6:
                br, bg, bb = 34, 42, 50
            elif WIN_T - 4 <= py <= WIN_B + 4 and (HL_L - 8 <= px <= HL_R + 8 or HR_L - 8 <= px <= HR_R + 8):
                if px < CX:
                    t = max(0.0, min(1.0, (px - HL_L) / (HL_R - HL_L)))
                    br, bg, bb = int(40 + 25 * t), int(155 + 55 * t), int(48 + 20 * t)
                else:
                    t = max(0.0, min(1.0, (HR_R - px) / (HR_R - HR_L)))
                    br, bg, bb = int(34 + 28 * t), int(88 + 46 * t), int(196 + 38 * t)
            pa = plate_rgba[o + 3]
            if pa >= 255:
                out[o], out[o + 1], out[o + 2], out[o + 3] = plate_rgba[o], plate_rgba[o + 1], plate_rgba[o + 2], 255
            elif pa <= 0:
                out[o], out[o + 1], out[o + 2], out[o + 3] = br, bg, bb, 255
            else:
                inv = 255 - pa
                out[o] = (plate_rgba[o] * pa + br * inv) // 255
                out[o + 1] = (plate_rgba[o + 1] * pa + bg * inv) // 255
                out[o + 2] = (plate_rgba[o + 2] * pa + bb * inv) // 255
                out[o + 3] = 255
    return out


def main():
    ap = argparse.ArgumentParser(description="Register, key, and pack an AI-painted daves_frames plate into Media/*.tga.")
    ap.add_argument("--source", required=True, help="Input AI-painted PNG/JPG (or pre-aligned 2048x600 RGBA PNG/TGA).")
    ap.add_argument("--out", help="Output 2048x1024 TGA path (e.g. Media/frame-plain.tga).")
    ap.add_argument("--also", action="append", default=[], help="Copy primary TGA to additional path(s) (e.g. Media/frame-elite.tga).")
    ap.add_argument("--silver-out", help="Optional silver-graded 2048x1024 TGA path (e.g. Media/frame-rare.tga).")
    ap.add_argument("--silver-also", action="append", default=[], help="Copy silver TGA to additional path(s) (e.g. Media/frame-rareelite.tga).")
    ap.add_argument("--outer-radius", type=float, default=0.0, help="Exact outer corner radius in layout px (e.g. 8 or 12, up to 28), applied symmetrically to plate and aura board.")
    ap.add_argument("--organic-edge", action="store_true", help="Let AI-painted rounded/chipped/sculpted outer corners stay transparent while keeping the inner 7px bar lip and rings sealed.")
    ap.add_argument("--plate-out", help="Optional output path for the clean 2048x600 transparent RGBA plate PNG.")
    ap.add_argument("--preview", help="Optional output path for a 2048x600 composite preview PNG.")
    args = ap.parse_args()

    TPL.check_geometry()
    TPL.check_layout_lua()

    outer_rad_px = max(0.0, min(float(TPL.BOARD_CORNER), args.outer_radius) * K)
    sw, sh, src = read_image(args.source)
    xf = fit_source_transform(sw, sh, src)
    plate = extract_plate(
        sw,
        sh,
        src,
        xf,
        erode_keys=not xf["pre_aligned"],
        outer_rad_px=outer_rad_px,
        organic_edge=args.organic_edge,
    )

    if args.plate_out:
        write_png(args.plate_out, IW, IH, plate)
        print(f"wrote plate {args.plate_out} ({IW}x{IH})")

    if args.preview:
        prev = render_preview(plate)
        write_png(args.preview, IW, IH, prev)
        print(f"wrote preview {args.preview} ({IW}x{IH})")

    if args.out:
        strip = build_board_strip(plate, cool_backing=False, outer_rad_px=outer_rad_px)
        atlas = pack_atlas(plate, strip)
        write_tga(args.out, ATLAS_W, ATLAS_H, atlas)
        print(f"wrote {args.out} ({ATLAS_W}x{ATLAS_H})")
        for extra in args.also:
            os.makedirs(os.path.dirname(os.path.abspath(extra)), exist_ok=True)
            shutil.copyfile(args.out, extra)
            print(f"copied -> {extra}")

    if args.silver_out:
        silver_plate = grade_silver(plate)
        silver_strip = build_board_strip(silver_plate, cool_backing=True, outer_rad_px=outer_rad_px)
        silver_atlas = pack_atlas(silver_plate, silver_strip)
        write_tga(args.silver_out, ATLAS_W, ATLAS_H, silver_atlas)
        print(f"wrote {args.silver_out} ({ATLAS_W}x{ATLAS_H}, silver)")
        for extra in args.silver_also:
            os.makedirs(os.path.dirname(os.path.abspath(extra)), exist_ok=True)
            shutil.copyfile(args.silver_out, extra)
            print(f"copied -> {extra}")


if __name__ == "__main__":
    main()
