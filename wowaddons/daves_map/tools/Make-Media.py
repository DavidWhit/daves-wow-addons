"""Paint daves_map's Media textures.

Writes uncompressed 32-bit top-left-origin BGRA TGA textures into Media/:
  - dot.tga (64x64): soft white dot for category fallback pins.
  - ring.tga (64x64): additive glow highlight ring for hovered/selected pins.
  - findme.tga (64x64): gold/brass compass crosshair icon (matches daves_sack/Media/gear.tga).
  - waypoint.tga (64x64): gold/brass teardrop map pin icon (matches daves_sack/Media/gear.tga).
  - plus.tga (64x64): gold/brass '+' icon matching the toolbar icon palette.
  - minus.tga (64x64): gold/brass '-' icon matching plus.tga's bar weight (square canvas, no stretch).
  - pill.tga (128x64): symmetric beveled brass pill button frame (uniform border on all 4 sides at any UI scale).
  - slot.tga (64x64): symmetric square beveled brass skill-tab button frame (square sibling of pill.tga).
  - tab_base.tga (64x64): gold/brass stacked map layers icon for the Base tab.
  - tab_tracker.tga (64x64): gold/brass quest tracker checklist icon for the Tracker tab.
  - tab_zone.tga (64x64): gold/brass sculpted quest exclamation icon for the Zone tab.
  - tab_dungeon.tga (64x64): gold/brass dungeon archway portal icon for the Dungeon tab.
  - back.tga (64x64): gold/brass left-pointing arrow icon for the slim rail Back button.
  - sparkle.tga (64x64): crisp 4-point white star glint + soft core for additive node shimmer sparkles.
  - gear.tga (64x64): copied from daves_sack/Media/gear.tga if present, for exact visual parity.
"""

from __future__ import annotations

import math
import os
import shutil
import struct

SIZE = 64
OUTLINE_RGB = (20.0, 12.0, 2.0)


def smoothstep(edge0, edge1, value):
    if edge1 == edge0:
        return 0.0 if value < edge0 else 1.0
    span = (value - edge0) / (edge1 - edge0)
    t = min(1.0, max(0.0, span))
    return t * t * (3.0 - 2.0 * t)


def _byte(value):
    iv = round(value)
    if iv < 0:
        return 0
    if iv > 255:
        return 255
    return iv


def write_tga_bytes(path: str, bgra: bytearray, width: int = SIZE, height: int | None = None) -> None:
    if height is None:
        height = width
    os.makedirs(os.path.dirname(path), exist_ok=True)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    with open(path, "wb") as handle:
        handle.write(header)
        handle.write(bgra)


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
    write_tga_bytes(path, pixels, SIZE)


def _sd_round_box(px: float, py: float, cx: float, cy: float, hx: float, hy: float, r: float) -> float:
    dx = abs(px - cx) - (hx - r)
    dy = abs(py - cy) - (hy - r)
    return math.hypot(max(dx, 0.0), max(dy, 0.0)) + min(max(dx, dy), 0.0) - r


def _sd_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    pax, pay = px - ax, py - ay
    bax, bay = bx - ax, by - ay
    h = max(0.0, min(1.0, (pax * bax + pay * bay) / max(1e-6, bax * bax + bay * bay)))
    return math.hypot(pax - bax * h, pay - bay * h)


def _sd_triangle_down(px: float, py: float, cx: float, y_top: float, y_tip: float, top_hw: float, r: float) -> float:
    ax, ay = cx - top_hw, y_top
    bx, by = cx + top_hw, y_top
    tx, ty = cx, y_tip
    d = min(
        _sd_segment(px, py, ax, ay, bx, by),
        _sd_segment(px, py, bx, by, tx, ty),
        _sd_segment(px, py, tx, ty, ax, ay),
    )
    if y_top <= py <= y_tip:
        span = top_hw * (y_tip - py) / max(1e-5, y_tip - y_top)
        if abs(px - cx) <= span:
            d = -d
    return d - r


def _shade_gold(px: float, py: float, d_metal: float, cyl: float, spec_boost: bool = False):
    diag = (1.0 - (px - 8.0) / 48.0) * 0.55 + (1.0 - (py - 6.0) / 52.0) * 0.45
    diag = max(0.0, min(1.0, diag))
    shade = 0.25 + 0.55 * diag + 0.20 * max(0.0, min(1.0, cyl))
    if spec_boost and -4.2 < d_metal < -1.1:
        shade = min(1.0, shade + 0.18)
    gold_r = 118.0 + (242.0 - 118.0) * shade
    gold_g = 86.0 + (200.0 - 86.0) * shade
    gold_b = 22.0 + (91.0 - 22.0) * shade
    metal_t = 1.0 - smoothstep(-0.7, 0.7, d_metal)
    r = OUTLINE_RGB[0] + (gold_r - OUTLINE_RGB[0]) * metal_t
    g = OUTLINE_RGB[1] + (gold_g - OUTLINE_RGB[1]) * metal_t
    b = OUTLINE_RGB[2] + (gold_b - OUTLINE_RGB[2]) * metal_t
    return r, g, b


def build_findme_icon(size: int = SIZE) -> bytearray:
    """Gold/brass compass crosshair target icon matching daves_sack's toolbar icons."""
    bgra = bytearray(size * size * 4)
    cx, cy = 32.0, 32.0

    for y in range(size):
        py = y + 0.5
        for x in range(size):
            px = x + 0.5
            dist = math.hypot(px - cx, py - cy)

            # Outer compass ring (bold weight matched to gear.tga at 18x18)
            d_ring = abs(dist - 18.5) - 4.5
            # Center bullseye pip
            d_dot = dist - 7.2
            # Four cardinal crosshair spokes extending outside & slightly inside the ring
            d_top = _sd_round_box(px, py, cx, 10.5, 4.0, 7.6, 2.2)
            d_bot = _sd_round_box(px, py, cx, 53.5, 4.0, 7.6, 2.2)
            d_lft = _sd_round_box(px, py, 10.5, cy, 7.6, 4.0, 2.2)
            d_rgt = _sd_round_box(px, py, 53.5, cy, 7.6, 4.0, 2.2)

            d_union = min(d_ring, d_dot, d_top, d_bot, d_lft, d_rgt)
            if d_union > 0.8:
                continue

            alpha = 1.0 - smoothstep(-0.6, 0.7, d_union)
            if alpha <= 0.0:
                continue

            d_metal = d_union + 1.85
            cyl = math.cos(min(1.0, abs(dist - 18.5) / 5.0) * 1.1) if d_dot > 1.5 else math.cos((dist / 7.5) * 1.1)
            r, g, b = _shade_gold(px, py, d_metal, cyl, spec_boost=(py < 30.0))

            idx = (y * size + x) * 4
            bgra[idx] = _byte(b)
            bgra[idx + 1] = _byte(g)
            bgra[idx + 2] = _byte(r)
            bgra[idx + 3] = _byte(alpha * 255.0)

    return bgra


def build_waypoint_icon(size: int = SIZE) -> bytearray:
    """Gold/brass map pin / teardrop waypoint icon matching daves_sack's toolbar icons."""
    bgra = bytearray(size * size * 4)
    cx = 32.0
    head_y = 22.5
    head_r = 18.5
    tip_y = 59.5
    # Exact geometric tangent of the circle (cx, head_y, head_r) to the tip (cx, tip_y)
    dy_tip = tip_y - head_y
    tan_y = head_y + (head_r * head_r) / dy_tip
    tan_hw = head_r * math.sqrt(max(0.0, 1.0 - (head_r / dy_tip) ** 2))

    for y in range(size):
        py = y + 0.5
        for x in range(size):
            px = x + 0.5

            # Smooth tangent-continuous teardrop silhouette (exact tangent, zero seam)
            d_head = math.hypot(px - cx, py - head_y) - head_r
            d_tip = _sd_triangle_down(px, py, cx, tan_y, tip_y, tan_hw, 0.0)
            d_outer = min(d_head, d_tip)

            # Circular cutout hole inside the pin head
            d_hole = math.hypot(px - cx, py - head_y) - 7.8
            d_shape = max(d_outer, -d_hole)

            if d_shape > 0.8:
                continue

            alpha = 1.0 - smoothstep(-0.6, 0.7, d_shape)
            if alpha <= 0.0:
                continue

            d_metal = d_shape + 1.95
            cyl = math.cos(((px - cx) / 19.5) * 1.15)
            r, g, b = _shade_gold(px, py, d_metal, cyl, spec_boost=(py < 24.0))

            idx = (y * size + x) * 4
            bgra[idx] = _byte(b)
            bgra[idx + 1] = _byte(g)
            bgra[idx + 2] = _byte(r)
            bgra[idx + 3] = _byte(alpha * 255.0)

    return bgra


def build_plus_icon(size: int = SIZE) -> bytearray:
    """Bold gold/brass '+' icon matching daves_sack's toolbar icons."""
    bgra = bytearray(size * size * 4)
    cx, cy = 32.0, 32.0
    for y in range(size):
        py = y + 0.5
        for x in range(size):
            px = x + 0.5
            d_h = _sd_round_box(px, py, cx, cy, 22.0, 6.8, 2.8)
            d_v = _sd_round_box(px, py, cx, cy, 6.8, 22.0, 2.8)
            d_union = min(d_h, d_v)
            if d_union > 0.8:
                continue
            alpha = 1.0 - smoothstep(-0.6, 0.7, d_union)
            if alpha <= 0.0:
                continue
            d_metal = d_union + 2.0
            cyl_h = math.cos(min(1.0, abs(py - cy) / 7.2) * 1.1)
            cyl_v = math.cos(min(1.0, abs(px - cx) / 7.2) * 1.1)
            cyl = max(cyl_h, cyl_v)
            r, g, b = _shade_gold(px, py, d_metal, cyl, spec_boost=(py < 31.0))
            idx = (y * size + x) * 4
            bgra[idx] = _byte(b)
            bgra[idx + 1] = _byte(g)
            bgra[idx + 2] = _byte(r)
            bgra[idx + 3] = _byte(alpha * 255.0)
    return bgra


def build_minus_icon(size: int = SIZE) -> bytearray:
    """Bold gold/brass '-' icon with exact same bar weight as plus.tga on a 64x64 square canvas."""
    bgra = bytearray(size * size * 4)
    cx, cy = 32.0, 32.0
    for y in range(size):
        py = y + 0.5
        for x in range(size):
            px = x + 0.5
            d_h = _sd_round_box(px, py, cx, cy, 22.0, 6.8, 2.8)
            if d_h > 0.8:
                continue
            alpha = 1.0 - smoothstep(-0.6, 0.7, d_h)
            if alpha <= 0.0:
                continue
            d_metal = d_h + 2.0
            cyl = math.cos(min(1.0, abs(py - cy) / 7.2) * 1.1)
            r, g, b = _shade_gold(px, py, d_metal, cyl, spec_boost=(py < 31.0))
            idx = (y * size + x) * 4
            bgra[idx] = _byte(b)
            bgra[idx + 1] = _byte(g)
            bgra[idx + 2] = _byte(r)
            bgra[idx + 3] = _byte(alpha * 255.0)
    return bgra


def build_pill_frame(width: int = 128, height: int = 64) -> bytearray:
    """Symmetric rounded brass pill button frame (128x64, exact 2:1 ratio) with uniform border thickness."""
    bgra = bytearray(width * height * 4)
    cx, cy = width * 0.5, height * 0.5
    hx, hy = width * 0.5 - 2.0, height * 0.5 - 2.0
    corner_r = 12.0
    border_w = 5.4  # uniform brass frame thickness on all 4 sides

    for y in range(height):
        py = y + 0.5
        for x in range(width):
            px = x + 0.5
            d_outer = _sd_round_box(px, py, cx, cy, hx, hy, corner_r)
            if d_outer > 1.0:
                continue
            alpha_outer = 1.0 - smoothstep(-0.6, 0.8, d_outer)
            if alpha_outer <= 0.0:
                continue

            # Inner recessed dark fill (d_inner < 0 is interior, >= 0 is border band)
            d_inner = d_outer + border_w
            # Soft dark fill inside the brass border
            fill_r, fill_g, fill_b, fill_a = 15.0, 14.0, 12.0, 0.90

            if d_inner < -0.9:
                # Pure recessed dark interior with subtle top-to-bottom depth
                vt = py / height
                r = fill_r * (1.15 - 0.30 * vt)
                g = fill_g * (1.15 - 0.30 * vt)
                b = fill_b * (1.15 - 0.30 * vt)
                a = fill_a * alpha_outer
            else:
                # Brass border ring (outer dark edge -> bright brass bevel -> inner dark seam)
                # Distance into border band from its centerline (0 at center of brass rim, positive toward edges)
                band_center = -border_w * 0.5
                dist_from_center = abs(d_outer - band_center)
                rim_half = border_w * 0.5
                # Crisp dark outline at outer & inner rim edges (~1.1px each)
                d_metal = dist_from_center - (rim_half - 1.25)
                cyl = math.cos(min(1.0, dist_from_center / max(0.1, rim_half)) * 1.25)
                diag = (1.0 - px / width) * 0.45 + (1.0 - py / height) * 0.55
                shade = 0.28 + 0.50 * max(0.0, min(1.0, diag)) + 0.22 * max(0.0, cyl)
                gold_r = 122.0 + (242.0 - 122.0) * shade
                gold_g = 90.0 + (200.0 - 90.0) * shade
                gold_b = 26.0 + (92.0 - 26.0) * shade
                metal_t = 1.0 - smoothstep(-0.6, 0.6, d_metal)
                br = OUTLINE_RGB[0] + (gold_r - OUTLINE_RGB[0]) * metal_t
                bg = OUTLINE_RGB[1] + (gold_g - OUTLINE_RGB[1]) * metal_t
                bb = OUTLINE_RGB[2] + (gold_b - OUTLINE_RGB[2]) * metal_t

                # Smoothly blend interior fill into border inner edge
                border_t = smoothstep(-0.9, 0.5, d_inner)
                r = fill_r + (br - fill_r) * border_t
                g = fill_g + (bg - fill_g) * border_t
                b = fill_b + (bb - fill_b) * border_t
                a = (fill_a + (1.0 - fill_a) * border_t) * alpha_outer

            idx = (y * width + x) * 4
            bgra[idx] = _byte(b)
            bgra[idx + 1] = _byte(g)
            bgra[idx + 2] = _byte(r)
            bgra[idx + 3] = _byte(a * 255.0)
    return bgra


def _sd_diamond(px: float, py: float, cx: float, cy: float, rx: float, ry: float, r: float = 0.0) -> float:
    ax, ay = abs(px - cx), abs(py - cy)
    # Signed distance to rhombus with semi-axes (rx, ry), rounded by r
    d = _sd_segment(ax, ay, rx, 0.0, 0.0, ry)
    if (ax / max(1e-5, rx)) + (ay / max(1e-5, ry)) <= 1.0:
        d = -d
    return d - r


def _render_gold_sdf(size: int, sdf_fn) -> bytearray:
    """Generic gold/brass SDF icon renderer matching daves_sack/daves_map palette & outline."""
    bgra = bytearray(size * size * 4)
    for y in range(size):
        py = y + 0.5
        for x in range(size):
            px = x + 0.5
            d_shape, cyl, spec = sdf_fn(px, py)
            if d_shape > 0.8:
                continue
            alpha = 1.0 - smoothstep(-0.6, 0.7, d_shape)
            if alpha <= 0.0:
                continue
            d_metal = d_shape + 1.95
            r, g, b = _shade_gold(px, py, d_metal, cyl, spec_boost=spec)
            idx = (y * size + x) * 4
            bgra[idx] = _byte(b)
            bgra[idx + 1] = _byte(g)
            bgra[idx + 2] = _byte(r)
            bgra[idx + 3] = _byte(alpha * 255.0)
    return bgra


def build_slot_frame(size: int = SIZE) -> bytearray:
    """Symmetric square beveled brass skill-button slot (64x64, uniform border on all 4 sides)."""
    return build_pill_frame(size, size)


def build_tab_base_icon(size: int = SIZE) -> bytearray:
    """Stacked isometric map layers icon (Base tab: POI layers & map settings)."""
    def sdf(px: float, py: float):
        # Top diamond plate
        d_top = _sd_diamond(px, py, 32.0, 20.5, 21.0, 11.2, 2.0)
        # Middle layer chevron
        d_mid = min(
            _sd_segment(px, py, 10.5, 32.5, 32.0, 44.0),
            _sd_segment(px, py, 32.0, 44.0, 53.5, 32.5),
        ) - 3.6
        # Bottom layer chevron
        d_bot = min(
            _sd_segment(px, py, 10.5, 43.0, 32.0, 54.5),
            _sd_segment(px, py, 32.0, 54.5, 53.5, 43.0),
        ) - 3.6
        d = min(d_top, d_mid, d_bot)
        cyl = 0.85 if d == d_top else 0.55
        return d, cyl, (py < 24.0)
    return _render_gold_sdf(size, sdf)


def build_tab_tracker_icon(size: int = SIZE) -> bytearray:
    """Bold 3-row quest tracker list with top diamond focus pip & bullets (Tracker tab)."""
    def sdf(px: float, py: float):
        # Top row: diamond focus marker + long bar
        d_b1 = _sd_diamond(px, py, 14.5, 16.0, 6.2, 6.2, 1.2)
        d_r1 = _sd_round_box(px, py, 39.5, 16.0, 15.5, 4.4, 2.2)
        # Middle row: circle bullet + bar
        d_b2 = math.hypot(px - 14.5, py - 32.0) - 5.4
        d_r2 = _sd_round_box(px, py, 39.5, 32.0, 15.5, 4.4, 2.2)
        # Bottom row: circle bullet + slightly shorter bar
        d_b3 = math.hypot(px - 14.5, py - 48.0) - 5.4
        d_r3 = _sd_round_box(px, py, 37.0, 48.0, 13.0, 4.4, 2.2)
        d = min(d_b1, d_r1, d_b2, d_r2, d_b3, d_r3)
        cyl = math.cos(min(1.0, abs((py - 16.0) % 16.0) / 5.0) * 1.1)
        return d, max(0.35, cyl), (py < 22.0)
    return _render_gold_sdf(size, sdf)


def build_tab_zone_icon(size: int = SIZE) -> bytearray:
    """Iconic bold sculpted WoW Quest '!' exclamation mark (Zone tab: zone quests & chains)."""
    def sdf(px: float, py: float):
        # Tapered exclamation stem: bold at top (y=9, hw=9.6), tapered at bottom (y=38, hw=5.0)
        t = max(0.0, min(1.0, (py - 9.0) / 29.0))
        hw = 9.6 * (1.0 - t) + 5.0 * t
        d_stem = _sd_round_box(px, py, 32.0, 23.5, hw, 16.0, 4.2)
        # Bold round dot at bottom
        d_dot = math.hypot(px - 32.0, py - 50.5) - 7.6
        d = min(d_stem, d_dot)
        cyl = math.cos(min(1.0, abs(px - 32.0) / max(3.5, hw)) * 1.1)
        return d, max(0.35, cyl), False
    return _render_gold_sdf(size, sdf)


def build_tab_dungeon_icon(size: int = SIZE) -> bytearray:
    """Classic dungeon archway portal with flush stone plinths & inner portal core (Dungeon tab)."""
    def sdf(px: float, py: float):
        # Outer stone/brass archway: top semicircle (cx=32, cy=27, r=21.5) + lower pillars ending flush at y=53
        d_arch_out = max(math.hypot(px - 32.0, min(py, 27.0) - 27.0) - 21.5, py - 53.0)
        # Cut out inner portal doorway (semicircle r=11.0 + lower opening)
        d_hole = math.hypot(px - 32.0, min(py, 28.0) - 28.0) - 11.0
        d_gate = max(d_arch_out, -d_hole)
        # Flush plinth feet right at the base of both pillars (y=49.5..56.5)
        d_foot_l = _sd_round_box(px, py, 16.0, 52.5, 8.2, 3.5, 1.6)
        d_foot_r = _sd_round_box(px, py, 48.0, 52.5, 8.2, 3.5, 1.6)
        # Glowing diamond portal core floating inside the archway
        d_core = _sd_diamond(px, py, 32.0, 35.0, 6.4, 9.6, 1.2)
        d = min(d_gate, d_foot_l, d_foot_r, d_core)
        cyl = 0.95 if d == d_core else math.cos(min(1.0, abs(px - 32.0) / 22.0) * 1.1)
        return d, max(0.35, cyl), (d == d_core)
    return _render_gold_sdf(size, sdf)


def build_back_icon(size: int = SIZE) -> bytearray:
    """Crisp bold gold left-pointing arrow for the slim left-rail Back button."""
    def sdf(px: float, py: float):
        # Arrowhead pointing left (tip at x=13, wings at x=31, y=14 / y=50)
        d_head = min(
            _sd_segment(px, py, 13.5, 32.0, 31.5, 14.0),
            _sd_segment(px, py, 13.5, 32.0, 31.5, 50.0),
        ) - 5.4
        # Horizontal shaft seamlessly fused into the arrowhead apex
        d_shaft = _sd_round_box(px, py, 34.5, 32.0, 18.5, 5.4, 2.6)
        d = min(d_head, d_shaft)
        cyl = math.cos(min(1.0, abs(py - 32.0) / 6.0) * 1.0)
        return d, max(0.35, cyl), (py < 30.0)
    return _render_gold_sdf(size, sdf)


def dot_pixel(dist):
    inner = 1.0 - smoothstep(0.66, 0.72, dist)
    edge = 1.0 - smoothstep(0.88, 0.94, dist)
    return (inner, inner, inner, max(inner, 0.9 * edge))


def ring_pixel(dist):
    band = smoothstep(0.70, 0.75, dist) * (1.0 - smoothstep(0.85, 0.90, dist))
    glow = 0.35 * math.exp(-((dist - 0.8) / 0.12) ** 2)
    return (1.0, 1.0, 1.0, min(1.0, band + glow))


def build_sparkle_icon(size: int = SIZE) -> bytearray:
    """Crisp white 4-point loot-sparkle star with soft radial glow for additive tinting."""
    pixels = bytearray(size * size * 4)
    idx = 0
    for py in range(size):
        v = (py + 0.5) / size * 2.0 - 1.0
        av = abs(v)
        for px in range(size):
            u = (px + 0.5) / size * 2.0 - 1.0
            au = abs(u)
            r = math.hypot(u, v)
            # Hot center core + soft outer glow
            core = math.exp(-((r / 0.15) ** 2))
            halo = 0.38 * math.exp(-((r / 0.42) ** 2))
            # Tapered 4-point vertical & horizontal star rays
            w_h = 0.036 + 0.085 * max(0.0, 1.0 - au / 0.92)
            ray_h = math.exp(-((av / w_h) ** 2)) * (max(0.0, 1.0 - au / 0.94) ** 1.45)
            w_v = 0.036 + 0.085 * max(0.0, 1.0 - av / 0.92)
            ray_v = math.exp(-((au / w_v) ** 2)) * (max(0.0, 1.0 - av / 0.94) ** 1.45)
            # Subtle 45-degree diagonal micro-glints
            d1 = abs(u + v) * 0.70710678
            d2 = abs(u - v) * 0.70710678
            diag1 = 0.36 * math.exp(-((d1 / 0.055) ** 2)) * (max(0.0, 1.0 - d2 / 0.48) ** 1.6)
            diag2 = 0.36 * math.exp(-((d2 / 0.055) ** 2)) * (max(0.0, 1.0 - d1 / 0.48) ** 1.6)
            # Smooth circular clip so rotated stars never show box edges
            edge_fade = 1.0 - smoothstep(0.86, 0.98, r)
            a = min(1.0, max(core, ray_h, ray_v) + halo + diag1 + diag2) * edge_fade
            ab = _byte(a * 255.0)
            pixels[idx] = 255
            pixels[idx + 1] = 255
            pixels[idx + 2] = 255
            pixels[idx + 3] = ab
            idx += 4
    return pixels


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    media = os.path.join(here, "..", "Media")
    os.makedirs(media, exist_ok=True)
    write_tga(os.path.join(media, "dot.tga"), dot_pixel)
    write_tga(os.path.join(media, "ring.tga"), ring_pixel)
    write_tga_bytes(os.path.join(media, "sparkle.tga"), build_sparkle_icon(SIZE), SIZE)
    write_tga_bytes(os.path.join(media, "findme.tga"), build_findme_icon(SIZE), SIZE)
    write_tga_bytes(os.path.join(media, "waypoint.tga"), build_waypoint_icon(SIZE), SIZE)
    write_tga_bytes(os.path.join(media, "plus.tga"), build_plus_icon(SIZE), SIZE)
    write_tga_bytes(os.path.join(media, "minus.tga"), build_minus_icon(SIZE), SIZE)
    write_tga_bytes(os.path.join(media, "pill.tga"), build_pill_frame(128, 64), 128, 64)
    write_tga_bytes(os.path.join(media, "slot.tga"), build_slot_frame(SIZE), SIZE)
    write_tga_bytes(os.path.join(media, "tab_base.tga"), build_tab_base_icon(SIZE), SIZE)
    write_tga_bytes(os.path.join(media, "tab_tracker.tga"), build_tab_tracker_icon(SIZE), SIZE)
    write_tga_bytes(os.path.join(media, "tab_zone.tga"), build_tab_zone_icon(SIZE), SIZE)
    write_tga_bytes(os.path.join(media, "tab_dungeon.tga"), build_tab_dungeon_icon(SIZE), SIZE)
    write_tga_bytes(os.path.join(media, "back.tga"), build_back_icon(SIZE), SIZE)
    sack_gear = os.path.join(here, "..", "..", "daves_sack", "Media", "gear.tga")
    if os.path.isfile(sack_gear):
        shutil.copyfile(sack_gear, os.path.join(media, "gear.tga"))
    print(f"Wrote dot, ring, sparkle, findme, waypoint, plus, minus, pill, slot, tab_*, back, gear TGA files to {os.path.abspath(media)}", flush=True)


if __name__ == "__main__":
    main()
