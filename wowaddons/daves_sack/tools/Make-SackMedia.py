"""Generate custom TGA icon media for daves_sack.

Writes uncompressed 32-bit top-left-origin BGRA TGA textures into Media/:
  - trash.tga (64x64): Gold/brass trash can icon (lid, top handle, tapered body
    with three vertical ribs) matching the palette and outline of gear.tga.
  - gavel.tga (64x64): Gold/brass auctioneer's gavel and sound block icon for
    the Market Analysis & Insights toolbar button.
  - sort.tga (64x64): Gold/brass sort icon (downward arrow on the left with
    three graduated horizontal bars on the right) for the Sort Bags toolbar
    button.
"""

from __future__ import annotations

import math
import os
import struct


def _clamp_byte(v: float) -> int:
    iv = round(v)
    if iv < 0:
        return 0
    if iv > 255:
        return 255
    return iv


def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    if edge1 == edge0:
        return 0.0 if x < edge0 else 1.0
    t = (x - edge0) / (edge1 - edge0)
    if t < 0.0:
        t = 0.0
    elif t > 1.0:
        return 1.0
    return t * t * (3.0 - 2.0 * t)


def _sd_round_box(px: float, py: float, cx: float, cy: float, hx: float, hy: float, r: float) -> float:
    dx = abs(px - cx) - (hx - r)
    dy = abs(py - cy) - (hy - r)
    ox = max(dx, 0.0)
    oy = max(dy, 0.0)
    return math.hypot(ox, oy) + min(max(dx, dy), 0.0) - r


def _sd_trapezoid(px: float, py: float, y0: float, y1: float, top_hw: float, bot_hw: float, r: float) -> float:
    """Signed distance to a vertical symmetric trapezoid centered at x=32 with rounded corners."""
    cy = 0.5 * (y0 + y1)
    hy = 0.5 * (y1 - y0)
    t = max(0.0, min(1.0, (py - y0) / max(1e-5, y1 - y0)))
    hw = top_hw + (bot_hw - top_hw) * t
    dx = abs(px - 32.0) - (hw - r)
    dy = abs(py - cy) - (hy - r)
    ox = max(dx, 0.0)
    oy = max(dy, 0.0)
    return math.hypot(ox, oy) + min(max(dx, dy), 0.0) - r


def _sd_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    pax, pay = px - ax, py - ay
    bax, bay = bx - ax, by - ay
    h = max(0.0, min(1.0, (pax * bax + pay * bay) / (bax * bax + bay * bay)))
    return math.hypot(pax - bax * h, pay - bay * h)


def _sd_triangle_isoceles_down(px: float, py: float, cx: float, y_top: float, y_tip: float, top_hw: float, r: float) -> float:
    """Signed distance to a downward-pointing symmetric triangle with top at y_top, tip at (cx, y_tip), rounded by r."""
    ax, ay = cx - top_hw, y_top
    bx, by = cx + top_hw, y_top
    tx, ty = cx, y_tip
    d1 = _sd_segment(px, py, ax, ay, bx, by)
    d2 = _sd_segment(px, py, bx, by, tx, ty)
    d3 = _sd_segment(px, py, tx, ty, ax, ay)
    d = min(d1, d2, d3)
    if y_top <= py <= y_tip:
        span = top_hw * (y_tip - py) / max(1e-5, y_tip - y_top)
        if abs(px - cx) <= span:
            d = -d
    return d - r


def write_tga(path: str, width: int, height: int, bgra: bytearray) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    with open(path, "wb") as f:
        f.write(header)
        f.write(bgra)


def build_trash_icon(size: int = 64) -> bytearray:
    bgra = bytearray(size * size * 4)

    # Palette matched to Media/gear.tga:
    # Dark outline: (20, 12, 2)
    # Gold body gradient: top-left highlight (242, 200, 91) -> mid (192, 152, 62) -> shadow (128, 94, 28)
    outline_r, outline_g, outline_b = 20.0, 12.0, 2.0

    for y in range(size):
        py = y + 0.5
        for x in range(size):
            px = x + 0.5

            # 1. Handle arch on top of the lid (outer box minus inner hole)
            d_handle_out = _sd_round_box(px, py, 32.0, 7.5, 10.5, 5.5, 3.0)
            d_handle_in = _sd_round_box(px, py, 32.0, 10.0, 5.0, 3.0, 1.2)
            d_handle = max(d_handle_out, -d_handle_in)

            # 2. Overhanging lid bar
            d_lid = _sd_round_box(px, py, 32.0, 14.5, 22.5, 4.2, 2.5)
            d_top = min(d_handle, d_lid)

            # 3. Tapered bin body (separated from lid so the dark seam between lid and body reads clearly)
            d_body_outer = _sd_trapezoid(px, py, 20.0, 60.0, 18.5, 15.0, 3.5)

            # Three vertical ribs (cutouts/grooves inside the bin body)
            d_rib_l = _sd_round_box(px, py, 23.0, 40.0, 2.1, 13.5, 1.8)
            d_rib_c = _sd_round_box(px, py, 32.0, 40.0, 2.1, 13.5, 1.8)
            d_rib_r = _sd_round_box(px, py, 41.0, 40.0, 2.1, 13.5, 1.8)
            d_ribs = min(d_rib_l, d_rib_c, d_rib_r)

            # Overall silhouette union of top (lid+handle) and bin body
            d_union = min(d_top, d_body_outer)

            if d_union > 0.8:
                continue

            # Outer anti-aliased alpha
            alpha = 1.0 - _smoothstep(-0.6, 0.7, d_union)
            if alpha <= 0.0:
                continue

            # Determine interior metal fill vs dark outline/grooves:
            # - Outer border of lid/handle and outer border of body have a dark outline
            # - Seam between lid and body (where both d_top and d_body_outer are near 0) stays dark
            # - Vertical ribs are recessed dark channels with a soft bevel
            seam = max(d_top, d_body_outer)  # small near the lid/body boundary

            # Distance from the nearest dark boundary (outer edge, lid-body seam, or rib groove)
            d_metal_top = min(d_handle + 1.5, d_lid + 1.9)
            d_metal_body = max(d_body_outer + 2.0, -(d_ribs - 0.8))
            d_metal = min(d_metal_top, d_metal_body)
            if seam < 1.2 and py > 17.0 and py < 21.5:
                d_metal = max(d_metal, 1.2 - seam)

            metal_t = 1.0 - _smoothstep(-0.7, 0.7, d_metal)

            # Directional lighting (top-left to bottom-right) + subtle horizontal cylinder sheen
            diag = (1.0 - (px - 10.0) / 44.0) * 0.55 + (1.0 - (py - 4.0) / 56.0) * 0.45
            diag = max(0.0, min(1.0, diag))
            cyl = math.cos(((px - 32.0) / 20.0) * 1.1)
            cyl = max(0.0, min(1.0, cyl))
            shade = 0.25 + 0.55 * diag + 0.20 * cyl

            # Specular boost along top of lid and top of body/ribs
            if -4.2 < d_metal < -1.2 and (py < 15.0 or (20.5 < py < 25.0)):
                shade = min(1.0, shade + 0.18)

            gold_r = 118.0 + (242.0 - 118.0) * shade
            gold_g = 86.0 + (200.0 - 86.0) * shade
            gold_b = 22.0 + (91.0 - 22.0) * shade

            r = outline_r + (gold_r - outline_r) * metal_t
            g = outline_g + (gold_g - outline_g) * metal_t
            b = outline_b + (gold_b - outline_b) * metal_t

            idx = (y * size + x) * 4
            bgra[idx] = _clamp_byte(b)
            bgra[idx + 1] = _clamp_byte(g)
            bgra[idx + 2] = _clamp_byte(r)
            bgra[idx + 3] = _clamp_byte(alpha * 255.0)

    return bgra


def build_gavel_icon(size: int = 64) -> bytearray:
    bgra = bytearray(size * size * 4)
    outline_r, outline_g, outline_b = 20.0, 12.0, 2.0
    inv_sqrt2 = 0.7071067811865475

    for y in range(size):
        py = y + 0.5
        for x in range(size):
            px = x + 0.5

            # Local coordinates centered on the gavel head (26.0, 20.5):
            # u runs down-right (+45 deg) along the handle;
            # v runs down-left (+135 deg) along the mallet head barrel.
            dx = px - 26.0
            dy = py - 20.5
            u = (dx + dy) * inv_sqrt2
            v = (dy - dx) * inv_sqrt2

            # 1. Mallet head: central barrel + two flared striking caps at v = +-12.0
            d_barrel = _sd_round_box(u, v, 0.0, 0.0, 7.2, 10.5, 2.5)
            d_cap_lo = _sd_round_box(u, v, 0.0, 12.2, 8.8, 3.6, 2.2)
            d_cap_hi = _sd_round_box(u, v, 0.0, -12.2, 8.8, 3.6, 2.2)
            d_head = min(d_barrel, d_cap_lo, d_cap_hi)

            # 2. Angled handle extending along +u from u = 6.5 to u = 38.5
            t_handle = max(0.0, min(1.0, (u - 7.0) / 28.5))
            hw_handle = 3.5 + 1.4 * t_handle
            d_shaft = _sd_round_box(u, v, 21.5, 0.0, 15.0, hw_handle, 2.2)
            d_pommel = _sd_round_box(u, v, 37.0, 0.0, 3.2, 5.8, 2.4)
            d_handle = min(d_shaft, d_pommel)

            # 3. Horizontal sound block / anvil base at bottom-left
            d_base_top = _sd_round_box(px, py, 20.0, 49.5, 11.5, 3.3, 2.0)
            d_base_bot = _sd_round_box(px, py, 20.0, 56.0, 15.8, 4.0, 2.4)
            d_base = min(d_base_top, d_base_bot)

            d_union = min(d_head, d_handle, d_base)
            if d_union > 0.8:
                continue

            alpha = 1.0 - _smoothstep(-0.6, 0.7, d_union)
            if alpha <= 0.0:
                continue

            # Dark seams between:
            # - mallet barrel and its two flared end-caps (|v| near 8.6)
            # - mallet head and handle collar (u near 7.0)
            # - sound block top pad and bottom base (py near 52.5)
            d_groove_caps = abs(abs(v) - 8.6) - 0.8 if abs(u) < 7.5 else 10.0
            d_head_metal = max(d_head + 1.9, -d_groove_caps)

            d_groove_pommel = abs(u - 34.0) - 0.75 if abs(v) < 5.4 else 10.0
            d_handle_metal = max(d_handle + 1.85, -d_groove_pommel)

            d_base_metal = min(d_base_top + 1.75, d_base_bot + 1.85)
            seam_base = max(d_base_top, d_base_bot)
            if seam_base < 1.1 and 51.5 < py < 53.8:
                d_base_metal = max(d_base_metal, 1.1 - seam_base)

            seam_neck = max(d_head, d_handle)
            d_metal = min(d_head_metal, d_handle_metal, d_base_metal)
            if seam_neck < 1.2 and 5.6 < u < 8.8 and abs(v) < 5.6:
                d_metal = max(d_metal, 1.2 - seam_neck)

            metal_t = 1.0 - _smoothstep(-0.7, 0.7, d_metal)

            # Directional gold lighting + cylindrical sheen across barrel/handle
            diag = (1.0 - (px - 8.0) / 48.0) * 0.55 + (1.0 - (py - 4.0) / 56.0) * 0.45
            diag = max(0.0, min(1.0, diag))
            if d_base <= min(d_head, d_handle):
                cyl = math.cos(((px - 19.5) / 16.0) * 1.0)
            elif d_head <= d_handle:
                cyl = math.cos((u / 7.5) * 1.15)
            else:
                cyl = math.cos((v / 4.5) * 1.15)
            cyl = max(0.0, min(1.0, cyl))
            shade = 0.24 + 0.54 * diag + 0.22 * cyl

            # Specular highlight on upper-left bevels
            if -4.0 < d_metal < -1.1 and (u < -1.5 or (d_base < 0.0 and py < 50.5)):
                shade = min(1.0, shade + 0.18)

            gold_r = 118.0 + (242.0 - 118.0) * shade
            gold_g = 86.0 + (200.0 - 86.0) * shade
            gold_b = 22.0 + (91.0 - 22.0) * shade

            r = outline_r + (gold_r - outline_r) * metal_t
            g = outline_g + (gold_g - outline_g) * metal_t
            b = outline_b + (gold_b - outline_b) * metal_t

            idx = (y * size + x) * 4
            bgra[idx] = _clamp_byte(b)
            bgra[idx + 1] = _clamp_byte(g)
            bgra[idx + 2] = _clamp_byte(r)
            bgra[idx + 3] = _clamp_byte(alpha * 255.0)

    return bgra


def build_sort_icon(size: int = 64) -> bytearray:
    bgra = bytearray(size * size * 4)
    outline_r, outline_g, outline_b = 20.0, 12.0, 2.0

    for y in range(size):
        py = y + 0.5
        for x in range(size):
            px = x + 0.5

            # 1. Left downward-pointing arrow (shaft + triangular head)
            d_shaft = _sd_round_box(px, py, 16.0, 23.0, 4.8, 16.5, 2.3)
            d_head = _sd_triangle_isoceles_down(px, py, 16.0, 37.5, 56.0, 9.6, 2.4)
            d_arrow = min(d_shaft, d_head)

            # 2. Three horizontal bars on the right (long -> medium -> short), left-aligned at x = 29.0
            d_bar1 = _sd_round_box(px, py, 44.5, 13.5, 15.5, 5.2, 2.6)
            d_bar2 = _sd_round_box(px, py, 40.5, 31.5, 11.5, 5.2, 2.6)
            d_bar3 = _sd_round_box(px, py, 36.5, 49.5, 7.5, 5.2, 2.6)
            d_bars = min(d_bar1, d_bar2, d_bar3)

            d_union = min(d_arrow, d_bars)
            if d_union > 0.8:
                continue

            alpha = 1.0 - _smoothstep(-0.6, 0.7, d_union)
            if alpha <= 0.0:
                continue

            d_metal_arrow = d_arrow + 1.85
            d_metal_bars = min(d_bar1 + 1.85, d_bar2 + 1.85, d_bar3 + 1.85)
            d_metal = min(d_metal_arrow, d_metal_bars)
            metal_t = 1.0 - _smoothstep(-0.7, 0.7, d_metal)

            # Directional lighting + bevel sheen matching trash.tga and gavel.tga
            if d_arrow <= d_bars:
                diag = (1.0 - (px - 6.0) / 24.0) * 0.45 + (1.0 - (py - 6.0) / 52.0) * 0.55
                diag = max(0.0, min(1.0, diag))
                cyl = math.cos(((px - 16.0) / 10.5) * 1.1)
            else:
                near_cy = 13.5 if py < 22.5 else (31.5 if py < 40.5 else 49.5)
                diag = (1.0 - (px - 28.0) / 34.0) * 0.50 + (1.0 - (py - 6.0) / 52.0) * 0.50
                diag = max(0.0, min(1.0, diag))
                cyl = math.cos(((py - near_cy) / 5.4) * 1.15)
            cyl = max(0.0, min(1.0, cyl))
            shade = 0.27 + 0.52 * diag + 0.21 * cyl

            # Specular highlight along top edges of bars and arrow
            if -4.0 < d_metal < -1.1 and (
                (d_arrow < 0.0 and (py < 12.0 or (36.5 < py < 40.5 and abs(px - 16.0) > 4.2)))
                or (d_bar1 < 0.0 and py < 12.0)
                or (d_bar2 < 0.0 and py < 30.0)
                or (d_bar3 < 0.0 and py < 48.0)
            ):
                shade = min(1.0, shade + 0.18)

            gold_r = 118.0 + (242.0 - 118.0) * shade
            gold_g = 86.0 + (200.0 - 86.0) * shade
            gold_b = 22.0 + (91.0 - 22.0) * shade

            r = outline_r + (gold_r - outline_r) * metal_t
            g = outline_g + (gold_g - outline_g) * metal_t
            b = outline_b + (gold_b - outline_b) * metal_t

            idx = (y * size + x) * 4
            bgra[idx] = _clamp_byte(b)
            bgra[idx + 1] = _clamp_byte(g)
            bgra[idx + 2] = _clamp_byte(r)
            bgra[idx + 3] = _clamp_byte(alpha * 255.0)

    return bgra


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    media_dir = os.path.normpath(os.path.join(here, "..", "Media"))
    for name, builder in (
        ("trash.tga", build_trash_icon),
        ("gavel.tga", build_gavel_icon),
        ("sort.tga", build_sort_icon),
    ):
        out_path = os.path.join(media_dir, name)
        bgra = builder(64)
        write_tga(out_path, 64, 64, bgra)
        print(f"Wrote {out_path} ({len(bgra) + 18} bytes)")


if __name__ == "__main__":
    main()
