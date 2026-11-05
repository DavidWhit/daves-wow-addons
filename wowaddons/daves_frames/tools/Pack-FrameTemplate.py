"""Register, key, and pack an AI-painted daves_frames plate into Media/*.tga.

Supports two workflows:
1. Standard workflow (`guides/frame-template-ai.png`, 2048 x 1152, 16:9):
   - Extracts the single-box 2048 x 600 plate (grey outer frame, green 5 px lip,
     orange portrait ring, white level ring) and packs it into the top 2048 x 600
     of the 2048 x 1024 TGA atlas with the 600 x 220 board strip at y = 608.
2. Branched Extended workflow (`guides/frame-template-extended-ai.png`, 2048 x 1152,
   16:9, enabled via `--extended` or auto-detected when #FF0000 stencil red or a
   2048 x 840 plate is supplied):
   - Preserves all standard sections at their exact sizes, plus:
     * Top #FF8000 Orange crest circle (centre 512,20, r=37 layout px; 1024,40,
       r=74 image px) overlaying the top of the portrait and portrait ring.
     * Background #FF0000 Red rectangle (x=222..802, y=-70..350 layout px;
       444..1604, -140..700 image px -> 2048 x 840 extended plate) behind all
       sections for optional intricate artwork. Blue (#0000FF) and Yellow
       (#FFFF00) holes stay strictly off-limits, and any unfilled #FF0000 Red
       (or #FF00FF Magenta) space keys out to transparent.
   - Packs the middle y=0..600 into the standard top slot, the 600 x 220 strip at
     x=0..600, y=608..828, and the top/bottom extended overhang bands at
     x=608..1768, y=608..748 (top 1160 x 140) and y=756..856 (bottom 1160 x 100).

Usage:
    # Standard workflow:
    py -3 tools/Pack-FrameTemplate.py --source painted.png --out Media/frame-elite.tga --silver-out Media/frame-rareelite.tga --preview tools/template/preview/elite-preview.png

    # Extended workflow:
    py -3 tools/Pack-FrameTemplate.py --extended --source painted-ext.png --out Media/frame-boss.tga --preview tools/template/preview/boss-ext-preview.png

    # Modular per-section workflow (separate section previews + focused single-section redraws, Order 1 -> 6):
    py -3 tools/Pack-FrameTemplate.py --extended \
        --layer-backdrop backdrop.png --layer-frame frame.png --layer-lip lip.png \
        --layer-ring ring.png --layer-crest crest.png --layer-level level.png \
        --layer-dir tools/template/preview/boss-layers \
        --preview tools/template/preview/boss-ext-preview.png
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
LIP_L2, LIP_R2 = TPL.LIP_L * K, TPL.LIP_R * K          # 60, 1988
LIP_T2, LIP_B2 = TPL.LIP_T * K, TPL.LIP_B * K          # 206, 338
STRIP_Y, STRIP_W, STRIP_H = TPL.STRIP_Y, TPL.STRIP_W, TPL.STRIP_H  # 608, 600, 220

# Extended 2x mask coordinates (image pixels, relative to standard 2048x600 top-left).
TOP_BX, TOP_BY = TPL.TOP_BADGE[0] * K, TPL.TOP_BADGE[1] * K  # 1024, 40
TOP_BR = TPL.TOP_BADGE_R * K                                 # 74
EXT_RED_L, EXT_RED_R = TPL.EXT_RED_L * K, TPL.EXT_RED_R * K  # 444, 1604
EXT_RED_T, EXT_RED_B = TPL.EXT_RED_T * K, TPL.EXT_RED_B * K  # -140, 700
CREST_RED_L, CREST_RED_R = TPL.CREST_RED_L * K, TPL.CREST_RED_R * K  # 708, 1340
CREST_RED_T, CREST_RED_B = TPL.CREST_RED_T * K, TPL.CREST_RED_B * K  # -140, 162
EXT_TOP_PX = TPL.EXT_TOP_PX_H                                # 140
EXT_BOT_PX = TPL.EXT_BOT_PX_H                                # 100
EXT_IH = IH + EXT_TOP_PX + EXT_BOT_PX                        # 840
EXT_ATLAS_X, EXT_ATLAS_W = TPL.EXT_ATLAS_X, TPL.EXT_ATLAS_W  # 608, 1160
EXT_TOP_Y, EXT_BOT_Y = TPL.EXT_TOP_Y, TPL.EXT_BOT_Y          # 608, 756

LAYER_SPECS = TPL.LAYER_SPECS
LAYER_KEYS = TPL.LAYER_KEYS
LAYER_ORDER = {key: order_num for order_num, key, _, _ in LAYER_SPECS}
STD_LAYER_KEYS = tuple(key for _, key, _, ext_only in LAYER_SPECS if not ext_only)

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


def is_red_key(r: int, g: int, b: int) -> bool:
    """Flat #FF0000 Red stencil background in the extended template (excludes #FF8000 orange & gold)."""
    return r > 185 and g < 48 and b < 48 and (r - (g if g > b else b)) > 145


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


def has_extended_red_stencil(w: int, h: int, rgba: bytearray, sx: float, ox: float, sy: float, oy: float) -> bool:
    """Return True if the source image contains unfilled #FF0000 stencil red inside the extended red box."""
    x0 = max(0, int(sx * EXT_RED_L + ox))
    x1 = min(w, int(sx * EXT_RED_R + ox))
    y0 = max(0, int(sy * EXT_RED_T + oy))
    y1 = min(h, int(sy * EXT_RED_B + oy))
    red_count = 0
    for yy in range(y0, y1, 2):
        ro = yy * w * 4
        for xx in range(x0, x1, 2):
            o = ro + xx * 4
            if rgba[o + 3] >= 128 and is_red_key(rgba[o], rgba[o + 1], rgba[o + 2]):
                red_count += 1
                if red_count >= 150:
                    return True
    return False


def unpack_atlas_if_needed(w: int, h: int, rgba: bytearray):
    """Unpack a 2048x1024 .tga atlas into a clean 2048x600 (or 2048x840 extended) RGBA plate.

    Prevents the 600x220 aura-board strip at y=608..828 from being misread as bottom overhang art,
    while restoring any packed extTop (608..1768, 608..748) and extBot (608..1768, 756..856) bands.
    """
    if w != ATLAS_W or h != ATLAS_H:
        return w, h, rgba
    probes = ((414, 272), (1024, 272), (1634, 272), (1024, 504))
    if not all(rgba[(py * w + px) * 4 + 3] < 32 for px, py in probes):
        return w, h, rgba

    has_ext = False
    for sy_base, px_h in ((EXT_TOP_Y, EXT_TOP_PX), (EXT_BOT_Y, EXT_BOT_PX)):
        for yy in range(sy_base, sy_base + px_h, 2):
            ro = yy * ATLAS_W * 4
            for xx in range(EXT_ATLAS_X, EXT_ATLAS_X + EXT_ATLAS_W, 4):
                if rgba[ro + xx * 4 + 3] > 8:
                    has_ext = True
                    break
            if has_ext:
                break
        if has_ext:
            break

    if not has_ext:
        return IW, IH, bytearray(rgba[:IW * IH * 4])

    ext_plate = bytearray(IW * EXT_IH * 4)
    # Top overhang (1160 x 140 -> x=444..1604, y=0..140)
    for y in range(EXT_TOP_PX):
        s = ((EXT_TOP_Y + y) * ATLAS_W + EXT_ATLAS_X) * 4
        d = (y * IW + EXT_RED_L) * 4
        ext_plate[d:d + EXT_ATLAS_W * 4] = rgba[s:s + EXT_ATLAS_W * 4]
    # Middle standard plate (2048 x 600 -> y=140..740)
    ext_plate[EXT_TOP_PX * IW * 4:(EXT_TOP_PX + IH) * IW * 4] = rgba[:IW * IH * 4]
    # Bottom overhang (1160 x 100 -> x=444..1604, y=740..840)
    for y in range(EXT_BOT_PX):
        s = ((EXT_BOT_Y + y) * ATLAS_W + EXT_ATLAS_X) * 4
        d = ((EXT_TOP_PX + IH + y) * IW + EXT_RED_L) * 4
        ext_plate[d:d + EXT_ATLAS_W * 4] = rgba[s:s + EXT_ATLAS_W * 4]
    return IW, EXT_IH, ext_plate


def fit_source_transform(w: int, h: int, rgba: bytearray, extended: bool = False, layer_kind: str = None):
    """Fit global scale/offset plus local ring inner-radius adjustments onto 2048 x 600 (or 2048 x 840 extended)."""
    if layer_kind in ("backdrop", "crest"):
        extended = True
    if w == IW and h in (IH, ATLAS_H):
        probes = ((414, 272), (1024, 272), (1634, 272), (1024, 504))
        if all(rgba[(py * w + px) * 4 + 3] < 32 for px, py in probes):
            tag = f" [layer={layer_kind}]" if layer_kind else ""
            print(f"source {w}x{h}{tag}: pre-aligned RGBA plate detected (1:1 transform)")
            return {
                "sx": 1.0, "ox": 0.0, "sy": 1.0, "oy": 0.0,
                "pre_aligned": True, "pre_aligned_h": h, "extended": extended,
                "top_indented": False, "has_red": False, "port": None, "level": None,
            }
    if w == IW and h == EXT_IH:
        probes = (
            (414, 272 + EXT_TOP_PX),
            (1024, 272 + EXT_TOP_PX),
            (1634, 272 + EXT_TOP_PX),
            (1024, 504 + EXT_TOP_PX),
        )
        if all(rgba[(py * w + px) * 4 + 3] < 32 for px, py in probes):
            tag = f" [layer={layer_kind}]" if layer_kind else ""
            print(f"source {w}x{h}{tag}: pre-aligned extended 2048x840 RGBA plate detected (1:1 transform)")
            return {
                "sx": 1.0, "ox": 0.0, "sy": 1.0, "oy": float(EXT_TOP_PX),
                "pre_aligned": True, "pre_aligned_h": EXT_IH, "extended": True,
                "top_indented": True, "has_red": False, "port": None, "level": None,
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
    has_red = has_extended_red_stencil(w, h, rgba, sx, ox, sy, oy)
    if not extended and has_red:
        extended = True
        print("auto-detected extended template (#FF0000 Red stencil region present) -> enabling --extended workflow")

    aspect_drift = abs(sx - sy) / max(sx, 1e-9) * 100.0
    target_dim = f"{IW}x{EXT_IH} (extended)" if extended else f"{IW}x{IH}"
    tag = f" [layer={layer_kind}]" if layer_kind else ""
    print(
        f"registered {w}x{h}{tag} -> {target_dim}: "
        f"sx={sx:.5f} ox={ox:.2f} (max_err={ex:.2f}px) | "
        f"sy={sy:.5f} oy={oy:.2f} (max_err={ey:.2f}px) | "
        f"aspect_drift={aspect_drift:.2f}%"
        + ("" if level_hole else " [no yellow level hole; fitted from portrait+bars]")
    )
    if ex > 6.0 or ey > 6.0 or aspect_drift > 4.0:
        if layer_kind:
            guide_name = f"guides/layers/layer-{LAYER_ORDER[layer_kind]}-{layer_kind}-ai.png"
        else:
            guide_name = "guides/frame-template-extended-ai.png" if extended else "guides/frame-template-ai.png"
        print(
            f"WARNING: high geometry drift detected (ex={ex:.2f}px, ey={ey:.2f}px, aspect_drift={aspect_drift:.2f}%). "
            f"Ensure painting started from {guide_name} (2048x1152, 16:9)."
        )

    # Local radial inner-rim anchors for minor 1-2px bevel AA only — clamped tightly so inward
    # Blue-hole encroachment is NEVER radially smooshed into the 46px ring band.
    port_cx = portrait["cx"]
    port_cy = sy * CY + oy
    raw_port_rin_x = 0.5 * (portrait["r"] - portrait["l"])
    exp_port_rin_x = R_IN * sx
    max_rim_nudge_x = 3.0 * sx
    port_rin_x = max(exp_port_rin_x - max_rim_nudge_x, min(exp_port_rin_x + max_rim_nudge_x, raw_port_rin_x))
    top_indented = (layer_kind == "crest") or (layer_kind is None and extended)
    if top_indented:
        # On the extended monolithic guide and layer-5-crest guide, the top orange circle indents
        # the top of the blue portrait hole, so derive vertical inner radius from horizontal radius.
        raw_port_rin_y = raw_port_rin_x * (sy / max(sx, 1e-9))
        port_rin_y = port_rin_x * (sy / max(sx, 1e-9))
    else:
        raw_port_rin_y = max(10.0, port_cy - portrait["t"])
        exp_port_rin_y = R_IN * sy
        max_rim_nudge_y = 3.0 * sy
        port_rin_y = max(exp_port_rin_y - max_rim_nudge_y, min(exp_port_rin_y + max_rim_nudge_y, raw_port_rin_y))
    port_info = (port_cx, port_cy, port_rin_x, port_rin_y)

    lvl_info = None
    raw_lvl_rin = None
    if level_hole:
        raw_lvl_rx = 0.5 * (level_hole["r"] - level_hole["l"])
        raw_lvl_ry = 0.5 * (level_hole["b"] - level_hole["t"])
        raw_lvl_rin = (raw_lvl_rx, raw_lvl_ry)
        exp_lvl_rx, exp_lvl_ry = BR_IN * sx, BR_IN * sy
        lvl_rin_x = max(exp_lvl_rx - 3.0 * sx, min(exp_lvl_rx + 3.0 * sx, raw_lvl_rx))
        lvl_rin_y = max(exp_lvl_ry - 3.0 * sy, min(exp_lvl_ry + 3.0 * sy, raw_lvl_ry))
        lvl_info = (level_hole["cx"], level_hole["cy"], lvl_rin_x, lvl_rin_y)

    return {
        "sx": sx, "ox": ox, "sy": sy, "oy": oy,
        "ex": ex, "ey": ey, "aspect_drift": aspect_drift,
        "raw_port_rin": (raw_port_rin_x, raw_port_rin_y),
        "raw_lvl_rin": raw_lvl_rin,
        "pre_aligned": False, "extended": extended,
        "top_indented": top_indented, "has_red": has_red,
        "port": port_info, "level": lvl_info,
    }


def validate_painting_bounds(
    sw: int,
    sh: int,
    src: bytearray,
    xf: dict,
    allow_out_of_bounds: bool = False,
    aa_margin_guide_px: int = 7,
    max_zone_viol_px: int = 40,
    layer_kind: str = None,
):
    """Verify the AI painting stayed 100% inside drawable stencil pixels with zero smooshing or overflow.

    Checks all OFF-LIMITS stencil pixels (#FF00FF Magenta exterior, #0000FF Blue bar/portrait openings,
    and #FFFF00 Yellow level hole) outside a small JPEG 4:2:0 boundary-AA buffer (`aa_margin_guide_px`).
    When `layer_kind` is given (`backdrop|frame|lip|ring|crest|level`), validates strictly against that
    single section's 16:9 stencil (`guides/layers/layer-<N>-<layer_kind>-ai.png`).
    """
    if xf.get("pre_aligned"):
        return

    extended = bool(xf.get("extended"))
    pad_y = TPL.AI_PAD_LAYOUT * K  # 276
    if layer_kind is not None:
        gw, gh, guide = TPL.render_layer(layer_kind, K, pad_layout=TPL.AI_PAD_LAYOUT)
        has_red_stencil = layer_kind in ("backdrop", "crest")
        draw_ys = [
            gy
            for gy in range(gh)
            if any(
                (guide[(gy * gw + gx) * 3], guide[(gy * gw + gx) * 3 + 1], guide[(gy * gw + gx) * 3 + 2])
                not in (TPL.MAGENTA, TPL.BLUE, TPL.YELLOW)
                for gx in range(0, gw, 2)
            )
        ]
        top_limit_gy = min(draw_ys) if draw_ys else (pad_y + EXT_RED_T)
        bot_limit_gy = (max(draw_ys) + 1) if draw_ys else (pad_y + EXT_RED_B)
    elif extended:
        gw, gh, guide = TPL.render_extended(K, pad_layout=TPL.AI_PAD_LAYOUT)
        has_red_stencil = True
        top_limit_gy = pad_y + EXT_RED_T      # 136
        bot_limit_gy = pad_y + EXT_RED_B      # 976
    else:
        gw, gh, guide = TPL.render(K, pad_layout=TPL.AI_PAD_LAYOUT)
        has_red_stencil = False
        top_limit_gy = pad_y + (CY - R_OUT)   # 292
        bot_limit_gy = pad_y + IH             # 876

    draw_mask = bytearray(gw * gh)
    off_kind = bytearray(gw * gh)   # 1=mag_top, 2=mag_bot, 3=mag_flank, 4=blu_bar, 5=blu_port, 6=yel_lvl
    off_class = bytearray(gw * gh)  # 1=Magenta, 2=Blue, 3=Yellow
    bar_mid_l = (HL_R + CX - R_IN) // 2
    bar_mid_r = (CX + R_IN + HR_L) // 2
    for gy in range(gh):
        ro = gy * gw
        gro = ro * 3
        for gx in range(gw):
            idx = ro + gx
            o = gro + gx * 3
            c = (guide[o], guide[o + 1], guide[o + 2])
            if c == TPL.MAGENTA:
                off_class[idx] = 1
                if gy < top_limit_gy:
                    off_kind[idx] = 1
                elif gy >= bot_limit_gy:
                    off_kind[idx] = 2
                else:
                    off_kind[idx] = 3
            elif c == TPL.BLUE:
                off_class[idx] = 2
                off_kind[idx] = 4 if (gx <= bar_mid_l or gx >= bar_mid_r) else 5
            elif c == TPL.YELLOW:
                off_class[idx] = 3
                off_kind[idx] = 6
            else:
                draw_mask[idx] = 1

    near_draw = _dilate_mask(gw, gh, draw_mask, aa_margin_guide_px)
    # On modular layer guides, two off-limits fiducial colours (Magenta<->Blue, Magenta<->Yellow,
    # Blue<->Yellow) touch directly where intervening armor bands are omitted; allow exact JPEG 4:2:0
    # linear blends across a 4px seam between those adjacent off-limits colours without relaxing paint checks.
    mag_blue_seam = bytearray(gw * gh)
    blue_yel_seam = bytearray(gw * gh)
    mag_yel_seam = bytearray(gw * gh)
    for gy in range(1, gh - 1):
        ro = gy * gw
        for gx in range(1, gw - 1):
            idx = ro + gx
            c0 = off_class[idx]
            if not c0:
                continue
            for n_idx in (idx - 1, idx + 1, idx - gw, idx + gw):
                c1 = off_class[n_idx]
                if c1 and c1 != c0:
                    pair = (c0, c1) if c0 < c1 else (c1, c0)
                    if pair == (1, 2):
                        mag_blue_seam[idx] = 1
                    elif pair == (2, 3):
                        blue_yel_seam[idx] = 1
                    elif pair == (1, 3):
                        mag_yel_seam[idx] = 1
    near_mag_blue = _dilate_mask(gw, gh, mag_blue_seam, 6)
    near_blue_yel = _dilate_mask(gw, gh, blue_yel_seam, 6)
    near_mag_yel = _dilate_mask(gw, gh, mag_yel_seam, 6)

    zone_names = {
        1: "Magenta TOP exterior (above drawable ceiling)",
        2: "Magenta BOTTOM exterior (below drawable floor)",
        3: "Magenta LEFT/RIGHT flanks & bar-corner exterior",
        4: "Blue HEALTH/RESOURCE bar windows",
        5: "Blue PORTRAIT circle opening",
        6: "Yellow LEVEL-NUMBER hole",
    }
    counts = {k: 0 for k in zone_names}
    bboxes = {k: [gw, gh, 0, 0] for k in zone_names}

    sx, ox, sy, oy = xf["sx"], xf["ox"], xf["sy"], xf["oy"]
    for gy in range(gh):
        my = (gy - pad_y) + 0.5
        fy = sy * my + oy
        if fy < 1.0 or fy >= sh - 1.0:
            continue
        sy_i = int(fy)
        ro = gy * gw
        sro = sy_i * sw
        for gx in range(gw):
            idx = ro + gx
            kind = off_kind[idx]
            if not kind or near_draw[idx]:
                continue
            mx = gx + 0.5
            fx = sx * mx + ox
            if fx < 1.0 or fx >= sw - 1.0:
                continue
            so = (sro + int(fx)) * 4
            r, g, b, a = src[so], src[so + 1], src[so + 2], src[so + 3]
            if a < 128:
                continue
            if kind in (1, 2, 3):
                ok = (
                    is_magenta_key(r, g, b)
                    or (r >= 115 and b >= 110 and g < 55 and (min(r, b) - g) >= 70)
                    or (
                        has_red_stencil
                        and (
                            is_red_key(r, g, b)
                            or (r >= 165 and g <= 36 and (r - g) >= 135)
                        )
                    )
                    or (near_mag_blue[idx] and g <= 48 and b >= max(90, r - 25))
                    or (near_mag_yel[idx] and r >= 150 and r >= g - 15 and r >= b - 15)
                )
            elif kind in (4, 5):
                ok = (
                    is_blue_key(r, g, b)
                    or (b >= 110 and r < 55 and g < 55 and (b - (r if r > g else g)) >= 75)
                    or (near_mag_blue[idx] and g <= 48 and b >= max(90, r - 25))
                    or (near_blue_yel[idx] and abs(r - g) <= 28)
                )
            else:
                ok = (
                    is_yellow_key(r, g, b)
                    or (near_blue_yel[idx] and abs(r - g) <= 28)
                    or (near_mag_yel[idx] and r >= 150 and r >= g - 15 and r >= b - 15)
                )
            if not ok:
                counts[kind] += 1
                bb = bboxes[kind]
                if gx < bb[0]:
                    bb[0] = gx
                if gy < bb[1]:
                    bb[1] = gy
                if gx > bb[2]:
                    bb[2] = gx
                if gy > bb[3]:
                    bb[3] = gy

    problems = []
    for k, name in zone_names.items():
        n = counts[k]
        if n > max_zone_viol_px:
            bb = bboxes[k]
            problems.append(
                f"  - {name}: {n} out-of-bounds guide px painted (guide bbox x={bb[0]}..{bb[2]}, y={bb[1]}..{bb[3]})"
            )

    aspect_drift = xf.get("aspect_drift", 0.0)
    ex, ey = xf.get("ex", 0.0), xf.get("ey", 0.0)
    if aspect_drift > 2.5 or ex > 4.0 or ey > 4.0:
        problems.append(
            f"  - Geometry / aspect distortion: aspect_drift={aspect_drift:.2f}% (max 2.50%), max_err=({ex:.2f}px, {ey:.2f}px) (max 4.00px)"
        )

    total_viol = sum(counts.values())
    tag = f" [layer={layer_kind}]" if layer_kind else ""
    if not problems:
        print(
            f"bounds check OK{tag}: {total_viol} off-limits noise px (<= {max_zone_viol_px}/zone tolerance), "
            f"aspect_drift={aspect_drift:.2f}% (zero out-of-bounds paint, zero smoosh)"
        )
        return

    msg = (
        f"OUT-OF-BOUNDS PAINTING DETECTED{tag} (painter stepped outside drawable stencil pixels):\n"
        + "\n".join(problems)
        + "\nRefusing to clip or smoosh artwork to fit. Check drawable pixels in order "
        "(`py -3 wowaddons/daves_frames/tools/Build-FrameTemplate.py --drawable`) and repaint cleanly inside the stencil."
    )
    if allow_out_of_bounds:
        print("WARNING: " + msg)
    else:
        raise SystemExit("ERROR: " + msg)


# ---------------------------------------------------------------------------
# Signed-distance plate coverage, sampling & inpainting
# ---------------------------------------------------------------------------

def _keep_large_key_components(w: int, h: int, raw: bytearray, min_pixels: int = 400, seed_border: bool = False) -> bytearray:
    """Keep only true stencil-hole / exterior background components, never tiny enclosed gem highlights."""
    seen = bytearray(w * h)
    kept = bytearray(w * h)
    for start in range(w * h):
        if not raw[start] or seen[start]:
            continue
        q = deque([start])
        seen[start] = 1
        comp = []
        touches_border = False
        while q:
            cur = q.popleft()
            comp.append(cur)
            cx_, cy_ = cur % w, cur // w
            if cx_ == 0 or cx_ == w - 1 or cy_ == 0 or cy_ == h - 1:
                touches_border = True
            if cx_ > 0 and raw[cur - 1] and not seen[cur - 1]:
                seen[cur - 1] = 1
                q.append(cur - 1)
            if cx_ + 1 < w and raw[cur + 1] and not seen[cur + 1]:
                seen[cur + 1] = 1
                q.append(cur + 1)
            if cy_ > 0 and raw[cur - w] and not seen[cur - w]:
                seen[cur - w] = 1
                q.append(cur - w)
            if cy_ + 1 < h and raw[cur + w] and not seen[cur + w]:
                seen[cur + w] = 1
                q.append(cur + w)
        if len(comp) >= min_pixels or (seed_border and touches_border):
            for idx in comp:
                kept[idx] = 1
    return kept


def _dilate_mask(w: int, h: int, mask: bytearray, radius: int) -> bytearray:
    horiz = bytearray(w * h)
    for y in range(h):
        ro = y * w
        for x in range(w):
            x0 = 0 if x < radius else x - radius
            x1 = w if x + radius + 1 > w else x + radius + 1
            for xx in range(x0, x1):
                if mask[ro + xx]:
                    horiz[ro + x] = 1
                    break
    out = bytearray(w * h)
    for y in range(h):
        y0 = 0 if y < radius else y - radius
        y1 = h if y + radius + 1 > h else y + radius + 1
        ro = y * w
        for x in range(w):
            for yy in range(y0, y1):
                if horiz[yy * w + x]:
                    out[ro + x] = 1
                    break
    return out


def _keep_red_stencil_components(w: int, h: int, raw: bytearray, rgba: bytearray, min_pixels: int = 60) -> bytearray:
    """Keep #FF0000 Red stencil background components, including small enclosed filigree cutouts containing pure #FF0000."""
    seen = bytearray(w * h)
    kept = bytearray(w * h)
    for start in range(w * h):
        if not raw[start] or seen[start]:
            continue
        q = deque([start])
        seen[start] = 1
        comp = []
        pure_red = 0
        while q:
            cur = q.popleft()
            comp.append(cur)
            o = cur * 4
            if rgba[o] >= 225 and rgba[o + 1] <= 24 and rgba[o + 2] <= 24:
                pure_red += 1
            cx_, cy_ = cur % w, cur // w
            if cx_ > 0 and raw[cur - 1] and not seen[cur - 1]:
                seen[cur - 1] = 1
                q.append(cur - 1)
            if cx_ + 1 < w and raw[cur + 1] and not seen[cur + 1]:
                seen[cur + 1] = 1
                q.append(cur + 1)
            if cy_ > 0 and raw[cur - w] and not seen[cur - w]:
                seen[cur - w] = 1
                q.append(cur - w)
            if cy_ + 1 < h and raw[cur + w] and not seen[cur + w]:
                seen[cur + w] = 1
                q.append(cur + w)
        if len(comp) >= min_pixels or pure_red >= 2:
            for idx in comp:
                kept[idx] = 1
    return kept


def build_stencil_masks(w: int, h: int, rgba: bytearray, include_red: bool = False):
    """Return stencil key masks ignoring enclosed purple/blue/gold/ruby gem highlights."""
    raw_mag = bytearray(w * h)
    raw_blue = bytearray(w * h)
    raw_yel = bytearray(w * h)
    raw_red = bytearray(w * h) if include_red else None
    trans = bytearray(w * h)
    yel_xmin, yel_xmax = int(w * 0.35), int(w * 0.65)
    yel_ymin = int(h * 0.52)
    for i in range(w * h):
        o = i * 4
        r, g, b, a = rgba[o], rgba[o + 1], rgba[o + 2], rgba[o + 3]
        if a < 128:
            trans[i] = 1
            raw_mag[i] = 1
        elif is_magenta_key(r, g, b):
            raw_mag[i] = 1
        elif is_blue_key(r, g, b):
            raw_blue[i] = 1
        elif is_yellow_key(r, g, b):
            ix, iy = i % w, i // w
            if iy >= yel_ymin and yel_xmin <= ix <= yel_xmax:
                raw_yel[i] = 1
        elif include_red and is_red_key(r, g, b):
            raw_red[i] = 1

    ext_mag = _keep_large_key_components(w, h, raw_mag, min_pixels=2000, seed_border=True)
    blue_holes = _keep_large_key_components(w, h, raw_blue, min_pixels=400)
    yel_holes = _keep_large_key_components(w, h, raw_yel, min_pixels=300)
    red_bg = _keep_red_stencil_components(w, h, raw_red, rgba, min_pixels=60) if include_red else bytearray(w * h)

    key = bytearray(w * h)
    for i in range(w * h):
        if trans[i] or ext_mag[i] or blue_holes[i] or yel_holes[i] or red_bg[i]:
            key[i] = 1

    near_ext_mag = _dilate_mask(w, h, ext_mag, 5)
    if include_red:
        ext_or_red = bytearray(w * h)
        for i in range(w * h):
            if ext_mag[i] or red_bg[i] or blue_holes[i] or trans[i]:
                ext_or_red[i] = 1
        near_ext_red = _dilate_mask(w, h, ext_or_red, 6)
        return key, near_ext_mag, red_bg, near_ext_red
    return key, near_ext_mag


def _red_key_spill(r: int, g: int, b: int) -> int:
    """Measure pure #FF0000 Red contamination while ignoring warm gold/bronze/amber (where G >> B)."""
    gb_max = g if g > b else b
    warm_gold = (g - b) if g > b else 0
    return (r - gb_max) - int(1.18 * warm_gold)


def build_clean_metal_mask(
    w: int,
    h: int,
    rgba: bytearray,
    erode: bool = True,
    key_override: bytearray = None,
    include_red: bool = False,
) -> bytearray:
    """1 where source pixel is usable metal (not a flat key colour or JPEG 4:2:0 chroma halo)."""
    if key_override is not None:
        key = bytearray(key_override)
    else:
        res = build_stencil_masks(w, h, rgba, include_red=include_red)
        key = bytearray(res[0])
    if not erode:
        return bytearray(0 if k else 1 for k in key)

    # Mark pixels within 5px of a flat key that carry strong magenta, blue, yellow, or red JPEG 4:2:0 chroma bleed.
    near5 = _dilate_mask(w, h, key, 5)
    yel_xmin, yel_xmax = int(w * 0.38), int(w * 0.62)
    yel_ymin = int(h * 0.52)
    for i in range(w * h):
        if key[i] or not near5[i]:
            continue
        o = i * 4
        r, g, b = rgba[o], rgba[o + 1], rgba[o + 2]
        mag_excess = min(r, b) - g
        if mag_excess > 48 or (mag_excess > 24 and r > 95 and b > 90) or (b - (r if r > g else g)) > 36:
            key[i] = 1
        elif include_red and _red_key_spill(r, g, b) > 42:
            key[i] = 1
        elif abs(r - g) <= 22 and ((r if r < g else g) - b) > 70:
            ix, iy = i % w, i // w
            if iy >= yel_ymin and yel_xmin <= ix <= yel_xmax:
                key[i] = 1

    # Dilate key mask by 2px (separable 5x5 box) to strip remaining AI anti-aliasing fringe.
    dilated = _dilate_mask(w, h, key, 2)
    return bytearray(0 if d else 1 for d in dilated)


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


def extended_coverage(px: float, py: float, outer_rad_px: float = 0.0, seal_only: bool = False):
    """Return (core_pa, top_circle_pa, red_box_pa) for mask coordinate (px, py) in extended mode.

    - `core_pa`: standard plate + top orange crest circle (solid armor regions, minus blue/yellow holes).
    - `top_circle_pa`: coverage of the top orange crest circle (centre 1024,40, r=74).
    - `red_box_pa`: coverage of the background Red rectangle (444..1604, -140..700) minus off-limits
      Blue (left bar, right bar, portrait opening outside top circle/level ring) and Yellow (level hole).
    """
    d_lvl = math.hypot(px - BX, py - BY)
    sd_lvl_hole = d_lvl - BR_IN
    sd_lvl_ring = max(d_lvl - BR_OUT, -sd_lvl_hole)

    d_top = math.hypot(px - TOP_BX, py - TOP_BY)
    sd_top_circle = d_top - TOP_BR

    d_port = math.hypot(px - CX, py - CY)
    sd_port_hole = d_port - R_IN
    # The top orange circle and bottom white level ring overlay the portrait hole:
    sd_port_open = max(sd_port_hole, -sd_top_circle, -(d_lvl - BR_OUT))
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
    sd_union = min(sd_base, sd_lvl_ring, sd_top_circle)
    sd_core = max(sd_union, -sd_lvl_hole)

    sd_red_rect = sd_box(px, py, float(EXT_RED_L), float(EXT_RED_T), float(EXT_RED_R), float(EXT_RED_B))
    sd_red_allowed = max(sd_red_rect, -sd_lhole, -sd_rhole, -sd_port_open, -sd_lvl_hole)
    return cov(sd_core), cov(sd_top_circle), cov(sd_red_allowed)


def magenta_edge_chroma_key(r: int, g: int, b: int, a: int, allow_yellow: bool = False):
    """Chroma-key + despill against exterior magenta (#FF00FF) and blue for --organic-edge / extended silhouettes."""
    if a < 16 or is_blue_key(r, g, b) or (not allow_yellow and is_yellow_key(r, g, b)):
        return 0, 0, 0, 0
    mag = (min(r, b) - g) if (r > 36 and b > 32) else 0
    if mag >= 85:
        return 0, 0, 0, 0
    out_a = a
    if mag > 16:
        fade = int(255 * (85 - mag) / 69.0)
        out_a = min(out_a, fade)
    if min(r, b) - g > 4:
        r, g, b = despill_boundary_rgb(r, g, b)
    return max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)), out_a


def red_magenta_edge_chroma_key(r: int, g: int, b: int, a: int, near_red_bg: bool = True):
    """Chroma-key + despill against #FF0000 Red stencil background, #FF00FF Magenta, and #0000FF Blue."""
    if a < 16 or is_blue_key(r, g, b) or is_red_key(r, g, b):
        return 0, 0, 0, 0
    r, g, b, out_a = magenta_edge_chroma_key(r, g, b, a, allow_yellow=True)
    if out_a == 0:
        return 0, 0, 0, 0
    gb_max = g if g > b else b
    warm_gold = (g - b) if g > b else 0
    neutral_cap = gb_max + int(1.18 * warm_gold)
    spill = r - neutral_cap
    # Also key small enclosed JPEG-softened #FF0000 filigree pockets (high pure-red spill with G ~ B):
    if near_red_bg or (abs(g - b) <= 24 and spill > 36):
        # 1. Pure #FF0000 Red unmixing & despill across any brightness (silver, grey, pewter, or gold):
        if spill > 6:
            denom = max(36, 255 - neutral_cap)
            t_red = spill / float(denom)
            if t_red >= 0.54 or spill >= 115:
                return 0, 0, 0, 0
            if t_red > 0.12:
                fade = int(255 * (0.54 - t_red) / 0.42)
                out_a = min(out_a, fade)
            r = min(r, neutral_cap + 3)
    if near_red_bg:
        # 2. Pure #0000FF Blue edge unmixing & despill (where top crest indents into blue portrait circle):
        rg_max = r if r > g else g
        cyan_allow = (g - r) if g > r else 0
        blue_cap = rg_max + cyan_allow
        bspill = b - blue_cap
        if bspill > 12:
            denom_b = max(36, 255 - blue_cap)
            t_blu = bspill / float(denom_b)
            if t_blu >= 0.58 or bspill >= 115:
                return 0, 0, 0, 0
            if t_blu > 0.14:
                fade_b = int(255 * (0.58 - t_blu) / 0.44)
                out_a = min(out_a, fade_b)
            b = min(b, blue_cap + 6)
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
        w_port = 1.0
        if xf.get("top_indented", xf.get("extended")):
            # Smoothly blend out radial portrait-rim warp inside the top orange crest circle (no hard step jump).
            d_top = math.hypot(px - TOP_BX, py - TOP_BY)
            if d_top <= TOP_BR:
                return bx_src, by_src
            if d_top < TOP_BR + 12.0:
                w_port = (d_top - TOP_BR) / 12.0
        dx, dy = px - CX, py - CY
        d_port = math.hypot(dx, dy)
        if R_IN - 2.0 <= d_port <= R_OUT + 6.0 and d_port > 1e-5:
            pcx, pcy, prx, pry = port
            u = max(0.0, min(1.0, (d_port - R_IN) / (R_OUT - R_IN)))
            rx = prx + u * (R_OUT * sx - prx)
            ry = pry + u * (R_OUT * sy - pry)
            px_s = pcx + (dx / d_port) * rx
            py_s = pcy + (dy / d_port) * ry
            w = w_port if d_port <= R_OUT else w_port * ((R_OUT + 6.0 - d_port) / 6.0)
            return px_s * w + bx_src * (1.0 - w), py_s * w + by_src * (1.0 - w)

    return bx_src, by_src


def despill_boundary_rgb(r: int, g: int, b: int, include_red: bool = False):
    """Strip residual JPEG 4:2:0 magenta/blue (and optional red) chroma bleed near mask boundaries."""
    mag = min(r, b) - g
    if mag > 5:
        drop = mag - 3
        b = max(0, b - drop)
        r = max(0, r - (drop * 3) // 4)
    blu = b - (r if r > g else g)
    if blu > 12:
        b = max(0, b - (blu - 8))
    if include_red:
        gb_max = g if g > b else b
        warm_gold = (g - b) if g > b else 0
        neutral_cap = gb_max + int(1.18 * warm_gold)
        if r > neutral_cap + 6:
            r = neutral_cap + 4
    return r, g, b


def _inpaint_missing_pixels(w: int, h: int, out: bytearray, have_rgb: bytearray, need_fill: list):
    if not need_fill:
        return
    q = deque()
    for idx in need_fill:
        x, y = idx % w, idx // w
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and have_rgb[ny * w + nx]:
                q.append(idx)
                break
    filled = []
    queued = bytearray(w * h)
    for idx in q:
        queued[idx] = 1
    while q:
        idx = q.popleft()
        if have_rgb[idx]:
            continue
        x, y = idx % w, idx // w
        sr = sg = sb = n = 0
        for dy in (-1, 0, 1):
            ny = y + dy
            if not (0 <= ny < h):
                continue
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                nx = x + dx
                if 0 <= nx < w and have_rgb[ny * w + nx]:
                    no = (ny * w + nx) * 4
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
            if 0 <= nx < w and 0 <= ny < h:
                ni = ny * w + nx
                if out[ni * 4 + 3] > 0 and not have_rgb[ni] and not queued[ni]:
                    queued[ni] = 1
                    q.append(ni)
    for _ in range(4):
        updates = []
        for idx in filled:
            x, y = idx % w, idx // w
            sr = sg = sb = n = 0
            for dy in (-1, 0, 1):
                ny = y + dy
                if 0 <= ny < h:
                    for dx in (-1, 0, 1):
                        nx = x + dx
                        if 0 <= nx < w and have_rgb[ny * w + nx]:
                            no = (ny * w + nx) * 4
                            sr += out[no]
                            sg += out[no + 1]
                            sb += out[no + 2]
                            n += 1
            if n:
                updates.append((idx * 4, sr // n, sg // n, sb // n))
        for o, r, g, b in updates:
            out[o], out[o + 1], out[o + 2] = r, g, b
    print(f"inpainted {len(filled)} key-covered plate pixels")


def _despill_plate_edges(w: int, h: int, out: bytearray, include_red: bool = False):
    edge_h = bytearray(w * h)
    for y in range(h):
        ro = y * w
        for x in range(w):
            x0 = 0 if x < 4 else x - 4
            x1 = w if x + 5 > w else x + 5
            for xx in range(x0, x1):
                if out[(ro + xx) * 4 + 3] < 240:
                    edge_h[ro + x] = 1
                    break
    for y in range(h):
        y0 = 0 if y < 4 else y - 4
        y1 = h if y + 5 > h else y + 5
        ro = y * w
        for x in range(w):
            o = (ro + x) * 4
            if out[o + 3] == 0:
                continue
            near_edge = False
            for yy in range(y0, y1):
                if edge_h[yy * w + x]:
                    near_edge = True
                    break
            if near_edge:
                r, g, b = despill_boundary_rgb(out[o], out[o + 1], out[o + 2], include_red=include_red)
                out[o], out[o + 1], out[o + 2] = r, g, b


def extract_plate(
    sw: int,
    sh: int,
    src: bytearray,
    xf: dict,
    erode_keys: bool = True,
    outer_rad_px: float = 0.0,
    organic_edge: bool = False,
):
    key_mask, near_ext_mag = build_stencil_masks(sw, sh, src, include_red=False)
    clean = build_clean_metal_mask(sw, sh, src, erode=erode_keys, key_override=key_mask)
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
                sx_i = 0 if fx < 0 else (sw - 1 if fx >= sw else int(fx))
                sy_i = 0 if fy < 0 else (sh - 1 if fy >= sh else int(fy))
                if near_ext_mag[sy_i * sw + sx_i]:
                    kr, kg, kb, ka = magenta_edge_chroma_key(sr, sg, sb, sa)
                else:
                    kr, kg, kb, ka = sr, sg, sb, sa
                fa = (ka * outer_pa) // 255
                if fa >= 20:
                    out[o], out[o + 1], out[o + 2], out[o + 3] = kr, kg, kb, fa
                    have_rgb[idx] = 1

    _inpaint_missing_pixels(IW, IH, out, have_rgb, need_fill)
    if erode_keys:
        _despill_plate_edges(IW, IH, out, include_red=False)
    return out


def extract_extended_plate(
    sw: int,
    sh: int,
    src: bytearray,
    xf: dict,
    erode_keys: bool = True,
    outer_rad_px: float = 0.0,
    organic_edge: bool = False,
) -> bytearray:
    """Extract the 2048 x 840 extended plate (y_mask = -140..700) with top circle + red box keying."""
    key_mask, near_ext_mag, red_bg, near_ext_red = build_stencil_masks(sw, sh, src, include_red=True)
    clean = build_clean_metal_mask(sw, sh, src, erode=erode_keys, key_override=key_mask, include_red=True)
    out = bytearray(IW * EXT_IH * 4)
    need_fill = []
    have_rgb = bytearray(IW * EXT_IH)

    for ey in range(EXT_IH):
        py = (ey - EXT_TOP_PX) + 0.5
        ro = ey * IW
        for x in range(IW):
            px = x + 0.5
            core_pa, top_pa, red_pa = extended_coverage(px, py, outer_rad_px=outer_rad_px, seal_only=organic_edge)
            outer_core_pa = (
                extended_coverage(px, py, outer_rad_px=outer_rad_px, seal_only=False)[0]
                if organic_edge
                else core_pa
            )
            # Standard ring/bar coverage without top circle (to check if pixel is only in the top crest circle):
            std_pa = (
                plate_coverage(x, ey - EXT_TOP_PX, outer_rad_px=outer_rad_px, seal_only=organic_edge)
                if 0 <= (ey - EXT_TOP_PX) < IH
                else 0
            )

            fx, fy = map_mask_to_source(px, py, xf)
            sx_i = 0 if fx < 0 else (sw - 1 if fx >= sw else int(fx))
            sy_i = 0 if fy < 0 else (sh - 1 if fy >= sh else int(fy))
            src_idx = sy_i * sw + sx_i
            idx = ro + x
            o = idx * 4

            # Standard structural ring/bar seal (`std_pa`) stays 100% airtight so StatusBar & portrait margins
            # never leak; sculpted top-crest overhangs (`top_pa` where `std_pa == 0`) and extended Red-box
            # ornaments (`red_pa`) chroma-key smoothly with zero circular seam across `std_pa` outer edges.
            ext_bound_pa = max(red_pa, top_pa, outer_core_pa if organic_edge else 0)
            ext_rgb = None
            ext_fa = 0
            if ext_bound_pa > std_pa and not key_mask[src_idx]:
                sr, sg, sb, sa = sample_bilinear_rgba(src, sw, sh, fx, fy)
                near_bg = bool(near_ext_red[src_idx] or near_ext_mag[src_idx])
                kr, kg, kb, ka = red_magenta_edge_chroma_key(sr, sg, sb, sa, near_red_bg=near_bg)
                ext_fa = (ka * ext_bound_pa) // 255
                if ext_fa >= 20:
                    ext_rgb = (kr, kg, kb)
                else:
                    ext_fa = 0

            if std_pa > 0:
                final_a = std_pa if std_pa >= ext_fa else ext_fa
                rgb = sample_valid_rgb(src, clean, sw, sh, fx, fy)
                if rgb is not None:
                    out[o], out[o + 1], out[o + 2], out[o + 3] = rgb[0], rgb[1], rgb[2], final_a
                    have_rgb[idx] = 1
                elif ext_rgb is not None:
                    out[o], out[o + 1], out[o + 2], out[o + 3] = ext_rgb[0], ext_rgb[1], ext_rgb[2], final_a
                    have_rgb[idx] = 1
                else:
                    out[o + 3] = final_a
                    need_fill.append(idx)
            elif ext_rgb is not None:
                out[o], out[o + 1], out[o + 2], out[o + 3] = ext_rgb[0], ext_rgb[1], ext_rgb[2], ext_fa
                have_rgb[idx] = 1

    _inpaint_missing_pixels(IW, EXT_IH, out, have_rgb, need_fill)
    if erode_keys:
        _despill_plate_edges(IW, EXT_IH, out, include_red=True)
    return out


def split_extended_plate(ext_plate: bytearray):
    """Split a 2048 x 840 extended plate into (main_2048x600, top_1160x140, bot_1160x100)."""
    main_plate = bytearray(ext_plate[EXT_TOP_PX * IW * 4:(EXT_TOP_PX + IH) * IW * 4])
    top_band = bytearray(EXT_ATLAS_W * EXT_TOP_PX * 4)
    for y in range(EXT_TOP_PX):
        s = (y * IW + EXT_RED_L) * 4
        d = y * EXT_ATLAS_W * 4
        top_band[d:d + EXT_ATLAS_W * 4] = ext_plate[s:s + EXT_ATLAS_W * 4]
    bot_band = bytearray(EXT_ATLAS_W * EXT_BOT_PX * 4)
    for y in range(EXT_BOT_PX):
        sy = EXT_TOP_PX + IH + y
        s = (sy * IW + EXT_RED_L) * 4
        d = y * EXT_ATLAS_W * 4
        bot_band[d:d + EXT_ATLAS_W * 4] = ext_plate[s:s + EXT_ATLAS_W * 4]
    return main_plate, top_band, bot_band


# ---------------------------------------------------------------------------
# Modular per-section extraction, decomposition, & Order 1 -> 6 compositing
# ---------------------------------------------------------------------------

def solid_layer_coverage(
    layer_key: str,
    px: float,
    py: float,
    outer_rad_px: float = 0.0,
    seal_only: bool = False,
) -> int:
    """Exact 1px-antialiased alpha coverage for a solid armor section (Order 2, 3, 4, or 6)."""
    if layer_key == "level":
        d_lvl = math.hypot(px - BX, py - BY)
        return cov(max(d_lvl - BR_OUT, -(d_lvl - BR_IN)))

    d_port = math.hypot(px - CX, py - CY)
    if layer_key == "ring":
        d_lvl = math.hypot(px - BX, py - BY)
        return cov(max(d_port - R_OUT, -(d_port - R_IN), -(d_lvl - BR_IN)))

    sd_lip_box = sd_box(px, py, LIP_L2, LIP_T2, LIP_R2, LIP_B2)
    if layer_key == "lip":
        sd_lhole = sd_box(px, py, HL_L, WIN_T, HL_R, WIN_B)
        sd_rhole = sd_box(px, py, HR_L, WIN_T, HR_R, WIN_B)
        return cov(max(sd_lip_box, -sd_lhole, -sd_rhole, -(d_port - R_OUT)))

    if layer_key == "frame":
        if seal_only:
            pad = (TPL.LIP + 2) * K
            sd_rect = sd_box(px, py, HL_L - pad, WIN_T - pad, HR_R + pad, WIN_B + pad)
        else:
            sd_rect = sd_round_box(px, py, PL_L, PL_T, PL_R, PL_B, outer_rad_px)
        return cov(max(sd_rect, -sd_lip_box, -(d_port - R_OUT)))

    raise ValueError(f"Not a solid layer_key: {layer_key!r}")


def allowed_keyed_layer_coverage(layer_key: str, px: float, py: float) -> int:
    """Allowed drawable region coverage (minus off-limits Blue/Yellow holes) for Order 1 (backdrop) or Order 5 (crest)."""
    d_port = math.hypot(px - CX, py - CY)
    d_lvl = math.hypot(px - BX, py - BY)
    sd_lhole = sd_box(px, py, HL_L, WIN_T, HL_R, WIN_B)
    sd_rhole = sd_box(px, py, HR_L, WIN_T, HR_R, WIN_B)
    if layer_key == "backdrop":
        sd_rect = sd_box(px, py, float(EXT_RED_L), float(EXT_RED_T), float(EXT_RED_R), float(EXT_RED_B))
        return cov(max(sd_rect, -sd_lhole, -sd_rhole, -(d_port - R_IN), -(d_lvl - BR_IN)))
    if layer_key == "crest":
        d_top = math.hypot(px - TOP_BX, py - TOP_BY)
        sd_top_circle = d_top - TOP_BR
        sd_port_open = max(d_port - R_IN, -sd_top_circle)
        sd_rect = sd_box(px, py, float(CREST_RED_L), float(CREST_RED_T), float(CREST_RED_R), float(CREST_RED_B))
        return cov(max(sd_rect, -sd_lhole, -sd_rhole, -sd_port_open, -(d_lvl - BR_IN)))
    raise ValueError(f"Not a keyed layer_key: {layer_key!r}")


def extract_single_layer(
    layer_key: str,
    sw: int,
    sh: int,
    src: bytearray,
    xf: dict,
    is_ext: bool,
    outer_rad_px: float = 0.0,
    organic_edge: bool = False,
) -> bytearray:
    """Extract one isolated section plate (2048x840 if is_ext else 2048x600) for Order 1..6."""
    plate_h = EXT_IH if is_ext else IH
    y_off = EXT_TOP_PX if is_ext else 0
    out = bytearray(IW * plate_h * 4)

    if xf.get("pre_aligned"):
        src_y_off = EXT_TOP_PX if xf.get("pre_aligned_h") == EXT_IH else 0
        is_keyed = layer_key in ("backdrop", "crest")
        for ey in range(plate_h):
            y_std = ey - y_off
            sy_src = y_std + src_y_off
            if not (0 <= sy_src < sh):
                continue
            py = y_std + 0.5
            ro = ey * IW
            sro = sy_src * sw
            for x in range(IW):
                px = x + 0.5
                pa = (
                    allowed_keyed_layer_coverage(layer_key, px, py)
                    if is_keyed
                    else solid_layer_coverage(layer_key, px, py, outer_rad_px=outer_rad_px, seal_only=False)
                )
                if pa <= 0:
                    continue
                so = (sro + x) * 4
                sa = src[so + 3]
                if sa <= 0:
                    continue
                fa = pa if sa >= 255 else (sa * pa + 127) // 255
                if fa > 0:
                    do = (ro + x) * 4
                    out[do], out[do + 1], out[do + 2], out[do + 3] = src[so], src[so + 1], src[so + 2], fa
        return out

    if layer_key in ("backdrop", "crest"):
        key_mask, near_ext_mag, _, near_ext_red = build_stencil_masks(sw, sh, src, include_red=True)
        for ey in range(plate_h):
            py = (ey - y_off) + 0.5
            ro = ey * IW
            for x in range(IW):
                px = x + 0.5
                bound_pa = allowed_keyed_layer_coverage(layer_key, px, py)
                if bound_pa <= 0:
                    continue
                fx, fy = map_mask_to_source(px, py, xf)
                sx_i = 0 if fx < 0 else (sw - 1 if fx >= sw else int(fx))
                sy_i = 0 if fy < 0 else (sh - 1 if fy >= sh else int(fy))
                src_idx = sy_i * sw + sx_i
                if key_mask[src_idx]:
                    continue
                sr, sg, sb, sa = sample_bilinear_rgba(src, sw, sh, fx, fy)
                near_bg = bool(near_ext_red[src_idx] or near_ext_mag[src_idx])
                kr, kg, kb, ka = red_magenta_edge_chroma_key(sr, sg, sb, sa, near_red_bg=near_bg)
                fa = (ka * bound_pa) // 255
                if fa >= 20:
                    o = (ro + x) * 4
                    out[o], out[o + 1], out[o + 2], out[o + 3] = kr, kg, kb, fa
        if layer_key == "crest":
            # Isolate the top crest medallion + connected exterior horns/crown (smoothly feathering any
            # Order 4 collar-context arch pixels outside TOP_BR + 10..22 so Order 5 stays pure crest):
            horn_mask = bytearray(IW * plate_h)
            q = deque()
            for ey in range(min(plate_h, y_off + CREST_RED_B)):
                py = (ey - y_off) + 0.5
                ro = ey * IW
                for x in range(CREST_RED_L, CREST_RED_R):
                    px = x + 0.5
                    if ((px - TOP_BX) ** 2 + (py - TOP_BY) ** 2) <= (TOP_BR + 8) ** 2:
                        if ((px - CX) ** 2 + (py - CY) ** 2) > (R_OUT + 1) ** 2:
                            idx = ro + x
                            if out[idx * 4 + 3] > 16:
                                horn_mask[idx] = 1
                                q.append((x, ey))
            while q:
                cx_, cy_ = q.popleft()
                for nx, ny in ((cx_ - 1, cy_), (cx_ + 1, cy_), (cx_, cy_ - 1), (cx_, cy_ + 1)):
                    if CREST_RED_L <= nx < CREST_RED_R and 0 <= ny < min(plate_h, y_off + CREST_RED_B):
                        nidx = ny * IW + nx
                        if not horn_mask[nidx] and out[nidx * 4 + 3] > 16:
                            npx, npy = nx + 0.5, (ny - y_off) + 0.5
                            if ((npx - CX) ** 2 + (npy - CY) ** 2) > (R_OUT + 1) ** 2:
                                horn_mask[nidx] = 1
                                q.append((nx, ny))
            horn_dil = _dilate_mask(IW, plate_h, horn_mask, 2)
            for ey in range(plate_h):
                py = (ey - y_off) + 0.5
                ro = ey * IW
                for x in range(IW):
                    idx = ro + x
                    o = idx * 4
                    if out[o + 3] == 0 or horn_dil[idx]:
                        continue
                    px = x + 0.5
                    d_top = math.hypot(px - TOP_BX, py - TOP_BY)
                    if d_top <= TOP_BR + 10.0:
                        continue
                    elif d_top < TOP_BR + 22.0:
                        w_keep = (TOP_BR + 22.0 - d_top) / 12.0
                        out[o + 3] = int(out[o + 3] * w_keep + 0.5)
                        if out[o + 3] == 0:
                            out[o] = out[o + 1] = out[o + 2] = 0
                    else:
                        out[o] = out[o + 1] = out[o + 2] = out[o + 3] = 0
        _despill_plate_edges(IW, plate_h, out, include_red=True)
        return out

    inc_red = bool(xf.get("has_red"))
    if inc_red:
        key_mask, near_ext_mag, _, _ = build_stencil_masks(sw, sh, src, include_red=True)
    else:
        key_mask, near_ext_mag = build_stencil_masks(sw, sh, src, include_red=False)
    clean = build_clean_metal_mask(sw, sh, src, erode=True, key_override=key_mask, include_red=inc_red)
    need_fill = []
    have_rgb = bytearray(IW * plate_h)
    use_org = organic_edge and (layer_key == "frame")

    for ey in range(y_off, y_off + IH):
        py = (ey - y_off) + 0.5
        ro = ey * IW
        for x in range(IW):
            px = x + 0.5
            pa = solid_layer_coverage(layer_key, px, py, outer_rad_px=outer_rad_px, seal_only=use_org)
            outer_pa = solid_layer_coverage(layer_key, px, py, outer_rad_px=outer_rad_px, seal_only=False) if use_org else pa
            if pa <= 0 and outer_pa <= 0:
                continue
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
            elif use_org and outer_pa > 0:
                sr, sg, sb, sa = sample_bilinear_rgba(src, sw, sh, fx, fy)
                sx_i = 0 if fx < 0 else (sw - 1 if fx >= sw else int(fx))
                sy_i = 0 if fy < 0 else (sh - 1 if fy >= sh else int(fy))
                if near_ext_mag[sy_i * sw + sx_i]:
                    kr, kg, kb, ka = magenta_edge_chroma_key(sr, sg, sb, sa)
                else:
                    kr, kg, kb, ka = sr, sg, sb, sa
                fa = (ka * outer_pa) // 255
                if fa >= 20:
                    out[o], out[o + 1], out[o + 2], out[o + 3] = kr, kg, kb, fa
                    have_rgb[idx] = 1

    _inpaint_missing_pixels(IW, plate_h, out, have_rgb, need_fill)
    _despill_plate_edges(IW, plate_h, out, include_red=inc_red)
    return out


def decompose_monolithic_to_layers(
    sw: int,
    sh: int,
    src: bytearray,
    xf: dict,
    full_plate: bytearray,
    is_ext: bool,
    outer_rad_px: float = 0.0,
    organic_edge: bool = False,
) -> dict:
    """Split a monolithic source/plate into isolated Order 1..6 (or 2,3,4,6) section RGBA plates."""
    layers = {}
    for lk in STD_LAYER_KEYS:
        layers[lk] = extract_single_layer(
            lk, sw, sh, src, xf, is_ext, outer_rad_px=outer_rad_px, organic_edge=organic_edge
        )
    if not is_ext:
        return layers

    # Separate Order 5 (top crest medallion + connected upper horns/crown) from Order 1 (backdrop):
    horn_mask = bytearray(IW * EXT_IH)
    horn_y_max = min(EXT_IH, EXT_TOP_PX + TOP_BY + TOP_BR - 14)  # 200 image px
    q = deque()
    for ey in range(horn_y_max):
        py = (ey - EXT_TOP_PX) + 0.5
        ro = ey * IW
        for x in range(CREST_RED_L, CREST_RED_R):
            px = x + 0.5
            if ((px - TOP_BX) ** 2 + (py - TOP_BY) ** 2) <= (TOP_BR + 4) ** 2:
                if ((px - CX) ** 2 + (py - CY) ** 2) > (R_OUT + 1) ** 2:
                    idx = ro + x
                    if full_plate[idx * 4 + 3] > 16:
                        horn_mask[idx] = 1
                        q.append((x, ey))
    while q:
        cx_, cy_ = q.popleft()
        for nx, ny in ((cx_ - 1, cy_), (cx_ + 1, cy_), (cx_, cy_ - 1), (cx_, cy_ + 1)):
            if CREST_RED_L <= nx < CREST_RED_R and 0 <= ny < horn_y_max:
                nidx = ny * IW + nx
                if not horn_mask[nidx] and full_plate[nidx * 4 + 3] > 16:
                    npx, npy = nx + 0.5, (ny - EXT_TOP_PX) + 0.5
                    if ((npx - CX) ** 2 + (npy - CY) ** 2) > (R_OUT + 1) ** 2:
                        horn_mask[nidx] = 1
                        q.append((nx, ny))
    horn_dil = _dilate_mask(IW, EXT_IH, horn_mask, 2)

    # Identify true outer-silhouette pixels outside the standard plate (never inside Blue/Yellow holes or
    # frame<->lip interior seams!), and tuck 3px inward ONLY where painted extended art meets the armor edge:
    true_ext = bytearray(IW * EXT_IH)
    ext_art_outside = bytearray(IW * EXT_IH)
    for ey in range(EXT_IH):
        py = (ey - EXT_TOP_PX) + 0.5
        ro = ey * IW
        for x in range(IW):
            px = x + 0.5
            sd_outer_bar = sd_round_box(px, py, PL_L, PL_T, PL_R, PL_B, outer_rad_px)
            sd_outer_ring = math.hypot(px - CX, py - CY) - R_OUT
            sd_outer_lvl = math.hypot(px - BX, py - BY) - BR_OUT
            if min(sd_outer_bar, sd_outer_ring, sd_outer_lvl) > 0.5:
                idx = ro + x
                true_ext[idx] = 1
                if full_plate[idx * 4 + 3] > 16 and not horn_dil[idx]:
                    ext_art_outside[idx] = 1
    tuck_from_art = _dilate_mask(IW, EXT_IH, ext_art_outside, 3)
    backdrop_zone = bytearray(1 if (true_ext[i] or tuck_from_art[i]) else 0 for i in range(IW * EXT_IH))

    crest_buf = bytearray(IW * EXT_IH * 4)
    backdrop_buf = bytearray(IW * EXT_IH * 4)
    for ey in range(EXT_IH):
        py = (ey - EXT_TOP_PX) + 0.5
        ro = ey * IW
        for x in range(IW):
            idx = ro + x
            o = idx * 4
            fa = full_plate[o + 3]
            if fa == 0:
                continue
            px = x + 0.5
            top_cov = cov(math.hypot(px - TOP_BX, py - TOP_BY) - TOP_BR)
            ca = 0
            if horn_dil[idx]:
                ca = fa * allowed_keyed_layer_coverage("crest", px, py) // 255
            elif top_cov > 0:
                ca = (fa * top_cov + 127) // 255
            if ca > 0:
                crest_buf[o], crest_buf[o + 1], crest_buf[o + 2], crest_buf[o + 3] = (
                    full_plate[o], full_plate[o + 1], full_plate[o + 2], ca,
                )
            if backdrop_zone[idx] and ca < fa:
                ba = allowed_keyed_layer_coverage("backdrop", px, py)
                if ba > 0:
                    rem_a = fa if ca == 0 else ((fa - ca) * ba + 127) // 255
                    rem_a = min(rem_a, ba)
                    if rem_a > 0:
                        backdrop_buf[o], backdrop_buf[o + 1], backdrop_buf[o + 2], backdrop_buf[o + 3] = (
                            full_plate[o], full_plate[o + 1], full_plate[o + 2], rem_a,
                        )
    layers["backdrop"] = backdrop_buf
    layers["crest"] = crest_buf
    return layers


def _tuck_solid_layer_under(w: int, h: int, layer_rgba: bytearray, cover_mask: bytearray, radius: int = 2) -> bytearray:
    """Extend a lower-order layer underneath present higher-order solid/opaque layers so seams stay alpha=255."""
    interior = bytearray(w * h)
    for i in range(w * h):
        if layer_rgba[i * 4 + 3] >= 180:
            interior[i] = 1
    near_in = _dilate_mask(w, h, interior, radius)
    out = bytearray(layer_rgba)
    have_rgb = bytearray(w * h)
    need_fill = []
    for i in range(w * h):
        o = i * 4
        a = out[o + 3]
        if a > 0:
            have_rgb[i] = 1
        if near_in[i] and cover_mask[i] and a < 255:
            out[o + 3] = 255
            if not have_rgb[i]:
                need_fill.append(i)
    if need_fill:
        _inpaint_missing_pixels(w, h, out, have_rgb, need_fill)
    return out


def composite_layers(layers_by_key: dict, is_ext: bool) -> bytearray:
    """Composite isolated section plates in exact back-to-front guide order (Order 1 -> Order 6)."""
    plate_h = EXT_IH if is_ext else IH
    y_off = EXT_TOP_PX if is_ext else 0
    ordered_keys = LAYER_KEYS if is_ext else STD_LAYER_KEYS
    present = [k for k in ordered_keys if k in layers_by_key and layers_by_key[k] is not None]

    dst = bytearray(IW * plate_h * 4)
    for pos, key in enumerate(present):
        src_layer = layers_by_key[key]
        if key in ("backdrop", "frame", "lip", "ring") and pos + 1 < len(present):
            cover = bytearray(IW * plate_h)
            higher_keys = present[pos + 1:]
            for hk in higher_keys:
                hbuf = layers_by_key[hk]
                is_solid_hk = hk in ("frame", "lip", "ring", "level")
                for i in range(IW * plate_h):
                    ha = hbuf[i * 4 + 3]
                    if (is_solid_hk and ha > 0) or ha >= 250:
                        cover[i] = 1
            tuck_r = 4 if key == "backdrop" else 2
            src_layer = _tuck_solid_layer_under(IW, plate_h, src_layer, cover, radius=tuck_r)

        for o in range(0, IW * plate_h * 4, 4):
            sa = src_layer[o + 3]
            if sa == 0:
                continue
            da = dst[o + 3]
            if sa >= 255 or da == 0:
                dst[o], dst[o + 1], dst[o + 2], dst[o + 3] = (
                    src_layer[o], src_layer[o + 1], src_layer[o + 2], sa,
                )
            else:
                inv = 255 - sa
                rem = (da * inv + 127) // 255
                na = sa + rem
                if na > 0:
                    half = na // 2
                    dst[o] = (src_layer[o] * sa + dst[o] * rem + half) // na
                    dst[o + 1] = (src_layer[o + 1] * sa + dst[o + 1] * rem + half) // na
                    dst[o + 2] = (src_layer[o + 2] * sa + dst[o + 2] * rem + half) // na
                    dst[o + 3] = na

    # Enforce off-limits Blue/Yellow holes across the final composite:
    for ey in range(plate_h):
        py = (ey - y_off) + 0.5
        ro = ey * IW
        for x in range(IW):
            o = (ro + x) * 4
            if dst[o + 3] == 0:
                continue
            px = x + 0.5
            if is_ext:
                core_pa, top_pa, red_pa = extended_coverage(px, py)
                cap = max(core_pa, top_pa, red_pa)
            else:
                cap = plate_coverage(x, ey)
            if cap < dst[o + 3]:
                dst[o + 3] = cap
                if cap == 0:
                    dst[o] = dst[o + 1] = dst[o + 2] = 0
    return dst


def write_layer_dir_outputs(layer_dir: str, layers_by_key: dict, is_ext: bool):
    """Write separate per-section RGBA plate PNGs and preview PNGs in Order 1 -> 6 for focused inspection & redraws."""
    os.makedirs(layer_dir, exist_ok=True)
    plate_h = EXT_IH if is_ext else IH
    ordered_keys = LAYER_KEYS if is_ext else STD_LAYER_KEYS
    for key in ordered_keys:
        buf = layers_by_key.get(key)
        if buf is None:
            continue
        order_num = LAYER_ORDER[key]
        plate_path = os.path.join(layer_dir, f"layer-{order_num}-{key}-plate.png")
        prev_path = os.path.join(layer_dir, f"layer-{order_num}-{key}-preview.png")
        write_png(plate_path, IW, plate_h, buf)
        prev = render_preview(buf, extended=is_ext)
        write_png(prev_path, IW, plate_h, prev)
        print(f"wrote section Order {order_num} ({key}): {prev_path} & {plate_path} ({IW}x{plate_h})")


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


def pack_atlas(
    plate_rgba: bytearray,
    strip_rgba: bytearray,
    top_band_rgba: bytearray = None,
    bot_band_rgba: bytearray = None,
) -> bytearray:
    atlas = bytearray(ATLAS_W * ATLAS_H * 4)
    atlas[0:IW * IH * 4] = plate_rgba
    for y in range(STRIP_H):
        s = y * STRIP_W * 4
        d = ((STRIP_Y + y) * ATLAS_W) * 4
        atlas[d:d + STRIP_W * 4] = strip_rgba[s:s + STRIP_W * 4]
    if top_band_rgba is not None:
        for y in range(EXT_TOP_PX):
            s = y * EXT_ATLAS_W * 4
            d = ((EXT_TOP_Y + y) * ATLAS_W + EXT_ATLAS_X) * 4
            atlas[d:d + EXT_ATLAS_W * 4] = top_band_rgba[s:s + EXT_ATLAS_W * 4]
        # 1px guard row at EXT_TOP_Y + EXT_TOP_PX copying y=0 of main plate for seamless bilinear filtering:
        s0 = EXT_RED_L * 4
        d0 = ((EXT_TOP_Y + EXT_TOP_PX) * ATLAS_W + EXT_ATLAS_X) * 4
        atlas[d0:d0 + EXT_ATLAS_W * 4] = plate_rgba[s0:s0 + EXT_ATLAS_W * 4]
    if bot_band_rgba is not None:
        # 1px guard row at EXT_BOT_Y - 1 copying y=IH-1 of main plate for seamless bilinear filtering:
        s1 = ((IH - 1) * IW + EXT_RED_L) * 4
        d1 = ((EXT_BOT_Y - 1) * ATLAS_W + EXT_ATLAS_X) * 4
        atlas[d1:d1 + EXT_ATLAS_W * 4] = plate_rgba[s1:s1 + EXT_ATLAS_W * 4]
        for y in range(EXT_BOT_PX):
            s = y * EXT_ATLAS_W * 4
            d = ((EXT_BOT_Y + y) * ATLAS_W + EXT_ATLAS_X) * 4
            atlas[d:d + EXT_ATLAS_W * 4] = bot_band_rgba[s:s + EXT_ATLAS_W * 4]
    return atlas


def render_preview(plate_rgba: bytearray, extended: bool = False) -> bytearray:
    """Composite the 2048 x 600 (or 2048 x 840 extended) plate over stand-in bars, portrait, and level circle."""
    h = EXT_IH if extended else IH
    y_off = EXT_TOP_PX if extended else 0
    out = bytearray(IW * h * 4)
    for ey in range(h):
        py = (ey - y_off) + 0.5
        ro = ey * IW * 4
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
    ap = argparse.ArgumentParser(description="Register, key, layer-composite, and pack AI-painted daves_frames sections or plates into Media/*.tga.")
    ap.add_argument("--source", help="Input AI-painted PNG/JPG (or pre-aligned 2048x600 / 2048x840 / 2048x1024 RGBA PNG/TGA).")
    ap.add_argument("--layer", choices=LAYER_KEYS, help="Validate/extract/preview --source as a single isolated section (backdrop|frame|lip|ring|crest|level).")
    ap.add_argument("--base-layers", help="Optional fallback monolithic painting/plate/TGA providing any sections not overridden by --layer-*.")
    ap.add_argument("--layer-backdrop", help="Order 1 [BACK] section source/plate (guides/layers/layer-1-backdrop-ai.png).")
    ap.add_argument("--layer-frame", help="Order 2 section source/plate (guides/layers/layer-2-frame-ai.png).")
    ap.add_argument("--layer-lip", help="Order 3 section source/plate (guides/layers/layer-3-lip-ai.png).")
    ap.add_argument("--layer-ring", help="Order 4 section source/plate (guides/layers/layer-4-ring-ai.png).")
    ap.add_argument("--layer-crest", help="Order 5 section source/plate (guides/layers/layer-5-crest-ai.png).")
    ap.add_argument("--layer-level", help="Order 6 [FRONT] section source/plate (guides/layers/layer-6-level-ai.png).")
    ap.add_argument("--layer-dir", help="Directory to write separate per-section preview & RGBA plate PNGs (layer-<N>-<section>-preview.png / -plate.png).")
    ap.add_argument("--extended", action="store_true", help="Use the branched extended workflow (top orange circle + background #FF0000 Red intricate art box).")
    ap.add_argument("--out", help="Output 2048x1024 TGA path (e.g. Media/frame-plain.tga).")
    ap.add_argument("--also", action="append", default=[], help="Copy primary TGA to additional path(s) (e.g. Media/frame-elite.tga).")
    ap.add_argument("--silver-out", help="Optional silver-graded 2048x1024 TGA path (e.g. Media/frame-rareelite.tga).")
    ap.add_argument("--silver-also", action="append", default=[], help="Copy silver TGA to additional path(s).")
    ap.add_argument("--outer-radius", type=float, default=0.0, help="Exact outer corner radius in layout px (e.g. 8 or 12, up to 28), applied symmetrically to plate and aura board.")
    ap.add_argument("--organic-edge", action="store_true", help="Let AI-painted rounded/chipped/sculpted outer corners stay transparent while keeping the inner 7px bar lip and rings sealed.")
    ap.add_argument("--plate-out", help="Optional output path for the clean transparent RGBA plate PNG (2048x600 standard, 2048x840 extended).")
    ap.add_argument("--preview", help="Optional output path for a composite preview PNG (2048x600 standard, 2048x840 extended).")
    ap.add_argument("--save-png", help="Save a lossless 1:1 unwarped PNG copy of --source ONLY after drawable boundary validation passes.")
    ap.add_argument("--check-only", action="store_true", help="Run registration and strict drawable-pixel boundary validation, then exit without packing.")
    ap.add_argument("--allow-out-of-bounds", action="store_true", help="Warn instead of failing when a source paints outside drawable stencil pixels.")
    args = ap.parse_args()

    TPL.check_geometry()
    TPL.check_layout_lua()

    layer_arg_map = {
        "backdrop": args.layer_backdrop,
        "frame": args.layer_frame,
        "lip": args.layer_lip,
        "ring": args.layer_ring,
        "crest": args.layer_crest,
        "level": args.layer_level,
    }
    has_multi_layers = bool(args.base_layers or any(layer_arg_map.values()))
    if not args.source and not has_multi_layers:
        ap.error("Provide --source (monolithic or with --layer) or one or more --layer-* / --base-layers inputs.")
    if args.source and has_multi_layers:
        ap.error("Use either --source or multi-layer flags (--layer-* / --base-layers), not both at once.")

    outer_rad_px = max(0.0, min(float(TPL.BOARD_CORNER), args.outer_radius) * K)

    # ------------------------------------------------------------------
    # Mode A: Multi-layer assembly (separate section previews + Order 1 -> 6 compositing)
    # ------------------------------------------------------------------
    if has_multi_layers:
        is_ext = bool(args.extended or args.layer_backdrop or args.layer_crest)
        loaded_layers = {}
        for lk in LAYER_KEYS:
            lpath = layer_arg_map[lk]
            if not lpath:
                continue
            lw, lh, lsrc = unpack_atlas_if_needed(*read_image(lpath))
            lxf = fit_source_transform(lw, lh, lsrc, extended=(is_ext or lk in ("backdrop", "crest")), layer_kind=lk)
            validate_painting_bounds(lw, lh, lsrc, lxf, allow_out_of_bounds=args.allow_out_of_bounds, layer_kind=lk)
            if lxf.get("extended") and lk in ("backdrop", "crest"):
                is_ext = True
            loaded_layers[lk] = (lpath, lw, lh, lsrc, lxf)

        base_tuple = None
        if args.base_layers:
            bw, bh, bsrc = unpack_atlas_if_needed(*read_image(args.base_layers))
            bxf = fit_source_transform(bw, bh, bsrc, extended=False)
            validate_painting_bounds(bw, bh, bsrc, bxf, allow_out_of_bounds=args.allow_out_of_bounds)
            if bxf["extended"]:
                is_ext = True
            base_tuple = (bw, bh, bsrc, bxf)

        if args.check_only:
            return

        layers_by_key = {}
        if base_tuple is not None:
            bw, bh, bsrc, bxf = base_tuple
            if bxf["extended"]:
                base_full = extract_extended_plate(
                    bw, bh, bsrc, bxf, erode_keys=not bxf["pre_aligned"],
                    outer_rad_px=outer_rad_px, organic_edge=args.organic_edge,
                )
            else:
                std_base = extract_plate(
                    bw, bh, bsrc, bxf, erode_keys=not bxf["pre_aligned"],
                    outer_rad_px=outer_rad_px, organic_edge=args.organic_edge,
                )
                if is_ext:
                    base_full = bytearray(IW * EXT_IH * 4)
                    base_full[EXT_TOP_PX * IW * 4:(EXT_TOP_PX + IH) * IW * 4] = std_base
                else:
                    base_full = std_base
            base_decomp = decompose_monolithic_to_layers(
                bw, bh, bsrc, bxf, base_full, is_ext,
                outer_rad_px=outer_rad_px, organic_edge=args.organic_edge,
            )
            for lk, buf in base_decomp.items():
                if lk not in loaded_layers:
                    layers_by_key[lk] = buf

        for lk, (lpath, lw, lh, lsrc, lxf) in loaded_layers.items():
            if not is_ext and lk in ("backdrop", "crest"):
                continue
            layers_by_key[lk] = extract_single_layer(
                lk, lw, lh, lsrc, lxf, is_ext,
                outer_rad_px=outer_rad_px, organic_edge=args.organic_edge,
            )
            if args.layer_dir and not lxf.get("pre_aligned"):
                os.makedirs(args.layer_dir, exist_ok=True)
                order_num = LAYER_ORDER[lk]
                paint_out = os.path.join(args.layer_dir, f"layer-{order_num}-{lk}-painting.png")
                write_png(paint_out, lw, lh, lsrc)
                print(f"wrote unwarped 1:1 section painting {paint_out} ({lw}x{lh})")

        if args.layer_dir:
            write_layer_dir_outputs(args.layer_dir, layers_by_key, is_ext)

        full_plate = composite_layers(layers_by_key, is_ext)
        if is_ext:
            plate, top_band, bot_band = split_extended_plate(full_plate)
            plate_h = EXT_IH
        else:
            plate, top_band, bot_band = full_plate, None, None
            plate_h = IH

    # ------------------------------------------------------------------
    # Mode B: Single-section validation / extraction / preview (--source + --layer)
    # ------------------------------------------------------------------
    elif args.layer:
        sw, sh, src = unpack_atlas_if_needed(*read_image(args.source))
        is_ext = bool(args.extended or args.layer in ("backdrop", "crest"))
        xf = fit_source_transform(sw, sh, src, extended=is_ext, layer_kind=args.layer)
        is_ext = bool(is_ext or (xf["extended"] and args.layer in ("backdrop", "crest")))
        validate_painting_bounds(
            sw, sh, src, xf, allow_out_of_bounds=args.allow_out_of_bounds, layer_kind=args.layer
        )
        if args.save_png:
            write_png(args.save_png, sw, sh, src)
            print(f"wrote unwarped 1:1 section PNG {args.save_png} ({sw}x{sh})")
        if args.check_only:
            return
        full_plate = extract_single_layer(
            args.layer, sw, sh, src, xf, is_ext,
            outer_rad_px=outer_rad_px, organic_edge=args.organic_edge,
        )
        if args.layer_dir:
            if not xf.get("pre_aligned"):
                os.makedirs(args.layer_dir, exist_ok=True)
                order_num = LAYER_ORDER[args.layer]
                paint_out = os.path.join(args.layer_dir, f"layer-{order_num}-{args.layer}-painting.png")
                write_png(paint_out, sw, sh, src)
                print(f"wrote unwarped 1:1 section painting {paint_out} ({sw}x{sh})")
            write_layer_dir_outputs(args.layer_dir, {args.layer: full_plate}, is_ext)
        if is_ext:
            plate, top_band, bot_band = split_extended_plate(full_plate)
            plate_h = EXT_IH
        else:
            plate, top_band, bot_band = full_plate, None, None
            plate_h = IH

    # ------------------------------------------------------------------
    # Mode C: Monolithic source painting/plate (--source, optional --layer-dir split)
    # ------------------------------------------------------------------
    else:
        sw, sh, src = unpack_atlas_if_needed(*read_image(args.source))
        xf = fit_source_transform(sw, sh, src, extended=args.extended)
        is_ext = xf["extended"]
        validate_painting_bounds(sw, sh, src, xf, allow_out_of_bounds=args.allow_out_of_bounds)

        if args.save_png:
            write_png(args.save_png, sw, sh, src)
            print(f"wrote unwarped 1:1 source PNG {args.save_png} ({sw}x{sh})")

        if args.check_only:
            return

        if is_ext:
            full_plate = extract_extended_plate(
                sw,
                sh,
                src,
                xf,
                erode_keys=not xf["pre_aligned"],
                outer_rad_px=outer_rad_px,
                organic_edge=args.organic_edge,
            )
            plate, top_band, bot_band = split_extended_plate(full_plate)
            plate_h = EXT_IH
        else:
            full_plate = extract_plate(
                sw,
                sh,
                src,
                xf,
                erode_keys=not xf["pre_aligned"],
                outer_rad_px=outer_rad_px,
                organic_edge=args.organic_edge,
            )
            plate, top_band, bot_band = full_plate, None, None
            plate_h = IH

        if args.layer_dir:
            layers_by_key = decompose_monolithic_to_layers(
                sw, sh, src, xf, full_plate, is_ext,
                outer_rad_px=outer_rad_px, organic_edge=args.organic_edge,
            )
            write_layer_dir_outputs(args.layer_dir, layers_by_key, is_ext)

    if args.plate_out:
        write_png(args.plate_out, IW, plate_h, full_plate)
        print(f"wrote plate {args.plate_out} ({IW}x{plate_h})")

    if args.preview:
        prev = render_preview(full_plate, extended=is_ext)
        write_png(args.preview, IW, plate_h, prev)
        print(f"wrote preview {args.preview} ({IW}x{plate_h})")

    if args.out:
        strip = build_board_strip(plate, cool_backing=False, outer_rad_px=outer_rad_px)
        atlas = pack_atlas(plate, strip, top_band_rgba=top_band, bot_band_rgba=bot_band)
        write_tga(args.out, ATLAS_W, ATLAS_H, atlas)
        print(f"wrote {args.out} ({ATLAS_W}x{ATLAS_H}{' extended' if is_ext else ''})")
        for extra in args.also:
            os.makedirs(os.path.dirname(os.path.abspath(extra)), exist_ok=True)
            shutil.copyfile(args.out, extra)
            print(f"copied -> {extra}")

    if args.silver_out:
        silver_full = grade_silver(full_plate)
        if is_ext:
            silver_plate, silver_top, silver_bot = split_extended_plate(silver_full)
        else:
            silver_plate, silver_top, silver_bot = silver_full, None, None
        silver_strip = build_board_strip(silver_plate, cool_backing=True, outer_rad_px=outer_rad_px)
        silver_atlas = pack_atlas(silver_plate, silver_strip, top_band_rgba=silver_top, bot_band_rgba=silver_bot)
        write_tga(args.silver_out, ATLAS_W, ATLAS_H, silver_atlas)
        print(f"wrote {args.silver_out} ({ATLAS_W}x{ATLAS_H}, silver{' extended' if is_ext else ''})")
        for extra in args.silver_also:
            os.makedirs(os.path.dirname(os.path.abspath(extra)), exist_ok=True)
            shutil.copyfile(args.silver_out, extra)
            print(f"copied -> {extra}")


if __name__ == "__main__":
    main()
