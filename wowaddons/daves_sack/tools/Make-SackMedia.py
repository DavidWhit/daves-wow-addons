"""Generate custom TGA icon media for daves_sack.

Writes uncompressed 32-bit top-left-origin BGRA TGA textures into Media/:
  - trash.tga (64x64): Gold/brass trash can icon (lid, top handle, tapered body
    with three vertical ribs) matching the palette and outline of gear.tga.
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


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    media_dir = os.path.normpath(os.path.join(here, "..", "Media"))
    out_path = os.path.join(media_dir, "trash.tga")
    bgra = build_trash_icon(64)
    write_tga(out_path, 64, 64, bgra)
    print(f"Wrote {out_path} ({len(bgra) + 18} bytes)")


if __name__ == "__main__":
    main()
