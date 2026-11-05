"""Draw the daves_frames paint masks (standard and extended) from one set of sizes.

This is a colour key, not artwork. Health, mana, and the portrait opening stay
blue (the game draws them). The 5 px lip, the 22 px outer frame, the portrait
ring, and the level ring are the paintable regions on the standard mask. The
yellow disc inside the level ring is the number placeholder, not paint.

`frame-template-ai.png` adds 276 image px of magenta top and bottom padding
(2048 x 1152, exact 16:9) so 16:9 AI image editors (Gemini Nano Banana /
Imagine) preserve exact 1:1 proportions without stretching or clipping the
portrait ring.

`frame-template-extended-ai.png` (2048 x 1152, exact 16:9) keeps every standard
section at the exact same size and position, and adds:
1. A top #FF8000 Orange crest circle (centre 512, 20, radius 37 / diameter 74,
   4/5 of the 92 px bottom level ring) that blends with the portrait ring and
   overlays the top of the portrait opening and portrait frame.
2. A background #FF0000 Red rectangle behind all sections (x = 222..802,
   y = -70..350 layout px; 580 x 420 layout px / 1160 x 840 image px) reserved
   for optional intricate artwork that may overlap the drawable armor bands
   while keeping Blue (#0000FF) and Yellow (#FFFF00) off-limits and keying any
   unfilled #FF0000 Red space to transparent in the packed texture.

Layout pixels match Layout.lua. The exact canvas mask is 2x, 2048 x 600
(2048 x 840 in extended mode).

    py -3 tools/Build-FrameTemplate.py
"""

from __future__ import annotations

import argparse
import json
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(ROOT)
TEMPLATE = os.path.join(ROOT, "template")
GUIDES = os.path.join(TEMPLATE, "guides")
LAYER_GUIDES = os.path.join(GUIDES, "layers")
LAYOUT = os.path.join(ADDON, "Layout.lua")

# Modular per-section 16:9 stencil guides (2048 x 1152), ordered back-to-front (Order 1 -> Order 6):
LAYER_SPECS = (
    (1, "backdrop", "layer-1-backdrop-ai.png", True),
    (2, "frame", "layer-2-frame-ai.png", False),
    (3, "lip", "layer-3-lip-ai.png", False),
    (4, "ring", "layer-4-ring-ai.png", False),
    (5, "crest", "layer-5-crest-ai.png", True),
    (6, "level", "layer-6-level-ai.png", False),
)
LAYER_KEYS = tuple(spec[1] for spec in LAYER_SPECS)

# Layout pixels, y grows downward. One source for the mask and for Layout.lua.
W = 1024
CX, CY = 512, 136
R_IN, R_OUT = 105, 128
LIP = 5
OUTER = 22
PAD = 8
BAR_H = 56
SCALE = 2  # image pixels per layout pixel. 2x fits a 2048-wide atlas.
ATLAS_W = W * SCALE
ATLAS_H = 1024
AI_PAD_LAYOUT = 138  # 276 image px top & bottom -> 2048 x 1152 (exact 16:9)

WIN_T = CY - BAR_H // 2
WIN_B = CY + BAR_H // 2
RING_L = CX - R_OUT
RING_R = CX + R_OUT
HOLE_L = PAD + OUTER + LIP
HOLE_LI = RING_L - LIP          # left hole ends, then the lip, then the ring
HOLE_RI = RING_R + LIP
HOLE_R = W - PAD - OUTER - LIP
LIP_L = HOLE_L - LIP
LIP_R = HOLE_R + LIP
LIP_T = WIN_T - LIP
LIP_B = WIN_B + LIP
PLATE_L = LIP_L - OUTER
PLATE_R = LIP_R + OUTER
PLATE_T = LIP_T - OUTER
PLATE_B = LIP_B + OUTER
HIDDEN = R_OUT                  # bar inner edge is the ring's outer edge
PIVOT_Y = 189                   # hook (14px above) sits in the bottom frame
LANE_L = (16, CX - R_OUT - 8)
LANE_R = (CX + R_OUT + 8, W - PAD - 8)

# Level badge: outer diameter 92 (4x the 23px portrait ring band), white painted
# border 16px thick on top of the portrait ring, 60px yellow hole inside.
BADGE_R_OUT = 2 * (R_OUT - R_IN)
BADGE_BAND = 16
BADGE_R_IN = BADGE_R_OUT - BADGE_BAND
BADGE_DY = (R_IN + R_OUT) // 2
BADGE = (CX, CY + BADGE_DY)
H = BADGE[1] + BADGE_R_OUT + 2

# Extended template additions (all standard sections stay 100% unchanged):
# 1. Top orange crest circle on the upper portrait ring midline (512, 20),
#    radius 37 (diameter 74 = 4/5 of the 92px bottom level ring guide).
TOP_BADGE_DY = -BADGE_DY
TOP_BADGE = (CX, CY + TOP_BADGE_DY)
TOP_BADGE_R = round(BADGE_R_OUT * 4 / 5)  # 37 layout px (74 diameter)

# 2. Background red rectangle behind all sections for optional intricate art:
#    expanded by 50 layout px (100 image px) per side around the 480x320 base box.
EXT_RED_W = 580
EXT_RED_L = CX - EXT_RED_W // 2           # 222
EXT_RED_R = CX + EXT_RED_W // 2           # 802
EXT_RED_T = -70                           # 70 layout px above y=0 (53px above top circle)
EXT_RED_B = 350                           # 50 layout px below y=300 (52px below level ring)
EXT_RED_H = EXT_RED_B - EXT_RED_T         # 420 layout px (840 image px)
EXT_TOP_H = -EXT_RED_T                    # 70 layout px (140 image px)
EXT_BOT_H = EXT_RED_B - H                 # 50 layout px (100 image px)

# Focused upper-crest #FF0000 Red horn/crown headroom box on layer-5-crest-ai.png:
# centered on CX=512 above PLATE_T=81 so standalone crest paintings focus on the
# top medallion + horns/crown without touching the bars or lower flanks.
CREST_RED_PAD_X = 30
CREST_RED_L = RING_L - CREST_RED_PAD_X    # 354 (708 image px)
CREST_RED_R = RING_R + CREST_RED_PAD_X    # 670 (1340 image px)
CREST_RED_T = EXT_RED_T                   # -70 (136 image px on 16:9 stencil)
CREST_RED_B = PLATE_T                     # 81  (438 image px on 16:9 stencil)

# Board 9-slice strip: left 150 and right 150 layout px of the plate at 2x,
# placed 8 atlas px below the 2048 x 600 art slot.
STRIP_RUN_LAYOUT = 150
STRIP_GAP_PX = 8
STRIP_Y = H * SCALE + STRIP_GAP_PX
STRIP_W = STRIP_RUN_LAYOUT * 2 * SCALE
STRIP_H = (PLATE_B - PLATE_T) * SCALE
BOARD_CORNER = OUTER + LIP + 1  # 28 layout px (56 atlas px) encloses miter + lip
STRIP_SLICE = BOARD_CORNER * SCALE

# Extended overhang atlas slots (to the right of the 600x220 strip at x=608..1768):
EXT_ATLAS_X = STRIP_W + STRIP_GAP_PX      # 608
EXT_ATLAS_W = EXT_RED_W * SCALE           # 1160
EXT_TOP_Y = STRIP_Y                       # 608
EXT_TOP_PX_H = EXT_TOP_H * SCALE          # 140 (y = 608..748)
EXT_BOT_Y = EXT_TOP_Y + EXT_TOP_PX_H + STRIP_GAP_PX  # 756
EXT_BOT_PX_H = EXT_BOT_H * SCALE          # 100 (y = 756..856)

# art, extended overhang, and strip texcoords in the 2048 x 1024 atlas
ART = (0, 1, 0, round((H * SCALE) / ATLAS_H, 6))
EXT_TOP = (
    round(EXT_ATLAS_X / ATLAS_W, 6),
    round((EXT_ATLAS_X + EXT_ATLAS_W) / ATLAS_W, 6),
    round(EXT_TOP_Y / ATLAS_H, 6),
    round((EXT_TOP_Y + EXT_TOP_PX_H) / ATLAS_H, 6),
)
EXT_BOT = (
    round(EXT_ATLAS_X / ATLAS_W, 6),
    round((EXT_ATLAS_X + EXT_ATLAS_W) / ATLAS_W, 6),
    round(EXT_BOT_Y / ATLAS_H, 6),
    round((EXT_BOT_Y + EXT_BOT_PX_H) / ATLAS_H, 6),
)
STRIP = (
    0,
    round(STRIP_W / ATLAS_W, 6),
    round(STRIP_Y / ATLAS_H, 6),
    round((STRIP_Y + STRIP_H) / ATLAS_H, 6),
)

MAGENTA = (255, 0, 255)    # outside. Do not paint.
RED = (255, 0, 0)          # extended background art box (behind everything; unfilled stays transparent).
BLUE = (0, 0, 255)         # health, mana, portrait opening. The game draws these.
GREEN = (0, 255, 0)        # 5px lip around each bar.
GREY = (128, 128, 128)     # thicker outer frame around that lip.
ORANGE = (255, 128, 0)     # portrait ring (and top crest circle on extended mask). Paintable.
WHITE = (255, 255, 255)    # level ring. Painted on top of the portrait ring.
YELLOW = (255, 255, 0)     # level placeholder, inside the level ring. Not paint.

COLOURS = {
    "outside": MAGENTA,
    "extendedArt": RED,
    "game": BLUE,
    "lip": GREEN,
    "frame": GREY,
    "ring": ORANGE,
    "levelRing": WHITE,
    "levelHole": YELLOW,
}


def dist2(x, y):
    dx = (x + 0.5) - CX
    dy = (y + 0.5) - CY
    return dx * dx + dy * dy


def inside(x, y, left, top, right, bottom):
    return left <= x < right and top <= y < bottom


def level_d2(x, y):
    dx = (x + 0.5) - BADGE[0]
    dy = (y + 0.5) - BADGE[1]
    return dx * dx + dy * dy


def top_badge_d2(x, y):
    dx = (x + 0.5) - TOP_BADGE[0]
    dy = (y + 0.5) - TOP_BADGE[1]
    return dx * dx + dy * dy


def colour(x, y):
    """Standard mask colour. The level ring and its hole are stamped on top of the plate."""
    d2 = level_d2(x, y)
    if d2 <= BADGE_R_IN * BADGE_R_IN:
        return YELLOW
    if d2 <= BADGE_R_OUT * BADGE_R_OUT:
        return WHITE
    return classify(x, y)


def colour_extended(x, y):
    """Extended mask colour (y in -AI_PAD_LAYOUT .. H + AI_PAD_LAYOUT - 1).

    - Top orange circle (centre 512,20, r=37) overlays the portrait and portrait
      ring and blends with the #FF8000 portrait ring.
    - All existing sections keep their exact size and position.
    - Background #FF0000 Red rectangle (x=222..802, y=-70..81, strictly above
      the horizontal bar top PLATE_T) sits behind the upper portrait ring and crest.
    """
    if top_badge_d2(x, y) <= TOP_BADGE_R * TOP_BADGE_R:
        return ORANGE
    if 0 <= y < H:
        c = colour(x, y)
        if c != MAGENTA:
            return c
    if inside(x, y, EXT_RED_L, EXT_RED_T, EXT_RED_R, PLATE_T):
        return RED
    return MAGENTA


def colour_layer(layer_key, x, y):
    """Per-section 16:9 mask colour (y in -AI_PAD_LAYOUT .. H + AI_PAD_LAYOUT - 1).

    Preserves the exact 3 #0000FF Blue fiducial holes + #FFFF00 Yellow level hole +
    #FF00FF Magenta exterior on every layer guide so fit_source_transform registers
    every isolated section render to < 1 px identically, while exposing ONLY the
    requested section's exact stencil shape (never exposing other sections as Red):
      1. backdrop : #FF0000 Red upper backdrop (x=222..802, y=-70..81 outside portrait ring r=128 & top crest r=37)
      2. frame    : #808080 Grey 22px outer bar armor frame
      3. lip      : #00FF00 Green 5px bevelled inner bar lip
      4. ring     : #FF8000 Orange 23px central portrait ring (r=105..128)
      5. crest    : #FF8000 Orange d=74 top crest circle + #FF0000 Red horn headroom (x=354..670, y=-70..81 outside r=128)
      6. level    : #FFFFFF White 16px lower circular level ring
    """
    if layer_key not in LAYER_KEYS:
        raise ValueError(f"Unknown layer_key {layer_key!r}; expected one of {LAYER_KEYS}")

    d_lvl = level_d2(x, y)
    if d_lvl <= BADGE_R_IN * BADGE_R_IN:
        return YELLOW
    if layer_key == "level" and d_lvl <= BADGE_R_OUT * BADGE_R_OUT:
        return WHITE

    if 0 <= y < H:
        left_hole = inside(x, y, HOLE_L, WIN_T, HOLE_LI, WIN_B)
        right_hole = inside(x, y, HOLE_RI, WIN_T, HOLE_R, WIN_B)
        if left_hole or right_hole:
            return BLUE

    d_port = dist2(x, y)
    d_top = top_badge_d2(x, y)
    if (
        d_port <= R_IN * R_IN
        and not (layer_key == "crest" and d_top <= TOP_BADGE_R * TOP_BADGE_R)
    ):
        return BLUE

    if layer_key == "backdrop":
        if (
            inside(x, y, EXT_RED_L, EXT_RED_T, EXT_RED_R, PLATE_T)
            and d_port > R_OUT * R_OUT
            and d_top > TOP_BADGE_R * TOP_BADGE_R
        ):
            return RED
        return MAGENTA

    if layer_key == "frame":
        in_lip = 0 <= y < H and inside(x, y, LIP_L, LIP_T, LIP_R, LIP_B)
        if 0 <= y < H and d_port > R_OUT * R_OUT and not in_lip and inside(x, y, PLATE_L, PLATE_T, PLATE_R, PLATE_B):
            return GREY
        return MAGENTA

    if layer_key == "lip":
        if 0 <= y < H and d_port > R_OUT * R_OUT and inside(x, y, LIP_L, LIP_T, LIP_R, LIP_B):
            return GREEN
        return MAGENTA

    if layer_key == "ring":
        if R_IN * R_IN < d_port <= R_OUT * R_OUT:
            return ORANGE
        return MAGENTA

    if layer_key == "crest":
        if d_top <= TOP_BADGE_R * TOP_BADGE_R:
            return ORANGE
        if inside(x, y, CREST_RED_L, CREST_RED_T, CREST_RED_R, CREST_RED_B):
            return RED
        return MAGENTA

    # layer_key == "level"
    if BADGE_R_IN * BADGE_R_IN < d_lvl <= BADGE_R_OUT * BADGE_R_OUT:
        return WHITE
    return MAGENTA


def classify(x, y):
    """One layout pixel. Later regions win, so the ring and the holes stay exact."""
    d2 = dist2(x, y)
    on_ring = (R_IN * R_IN) < d2 <= (R_OUT * R_OUT)
    if on_ring:
        return ORANGE
    if d2 <= R_IN * R_IN:
        return BLUE
    left_hole = inside(x, y, HOLE_L, WIN_T, HOLE_LI, WIN_B)
    right_hole = inside(x, y, HOLE_RI, WIN_T, HOLE_R, WIN_B)
    if left_hole or right_hole:
        return BLUE
    # Lip: the 5px rectangle around each hole, extended inward until the ring.
    left_lip = inside(x, y, LIP_L, LIP_T, CX, LIP_B) and not left_hole
    right_lip = inside(x, y, CX, LIP_T, LIP_R, LIP_B) and not right_hole
    if left_lip or right_lip:
        return GREEN
    if inside(x, y, PLATE_L, PLATE_T, PLATE_R, PLATE_B):
        return GREY
    return MAGENTA


def check_geometry():
    assert W == 1024 and H == 300
    assert (H * SCALE, W * SCALE) == (600, 2048)
    assert ((H + 2 * AI_PAD_LAYOUT) * SCALE) * 16 == (W * SCALE) * 9
    assert ART[3] == 0.585938
    assert STRIP_Y == 608 and STRIP_W == 600 and STRIP_H == 220
    assert BOARD_CORNER == 28 and STRIP_SLICE == 56
    assert STRIP == (0, 0.292969, 0.59375, 0.808594)
    assert STRIP_Y + STRIP_H <= ATLAS_H
    assert TOP_BADGE == (512, 20) and TOP_BADGE_R == 37
    assert EXT_RED_L == 222 and EXT_RED_R == 802 and EXT_RED_W == 580
    assert EXT_RED_T == -70 and EXT_RED_B == 350 and EXT_RED_H == 420
    assert EXT_TOP_H == 70 and EXT_BOT_H == 50
    assert EXT_ATLAS_X == 608 and EXT_ATLAS_W == 1160
    assert EXT_TOP_Y == 608 and EXT_TOP_PX_H == 140
    assert EXT_BOT_Y == 756 and EXT_BOT_PX_H == 100
    assert EXT_ATLAS_X + EXT_ATLAS_W <= ATLAS_W
    assert EXT_BOT_Y + EXT_BOT_PX_H <= ATLAS_H
    assert EXT_TOP == (0.296875, 0.863281, 0.59375, 0.730469)
    assert EXT_BOT == (0.296875, 0.863281, 0.738281, 0.835938)
    assert HOLE_L == 35 and HOLE_LI == 379 and HOLE_RI == 645 and HOLE_R == 989
    assert WIN_T == 108 and WIN_B == 164 and (WIN_B - WIN_T) == BAR_H
    assert (HOLE_LI - HOLE_L) == (HOLE_R - HOLE_RI) == 344
    assert LIP_L == 30 and LIP_R == 994 and LIP_T == 103 and LIP_B == 169
    assert PLATE_L == 8 and PLATE_R == 1016 and PLATE_T == 81 and PLATE_B == 191
    assert (WIN_B - WIN_T) - 8 >= 44          # overlay name cap still holds the 44px name
    assert HIDDEN == R_OUT
    assert CX - HIDDEN == RING_L             # bar stops on the ring's outer edge
    assert RING_L - (CX - HIDDEN) == 0
    assert (CX - HIDDEN) - HOLE_LI == LIP     # that stop is the far side of the inner lip
    # Ring clears the top of the canvas by PAD, using pixel centres.
    assert dist2(CX, CY - R_OUT) <= R_OUT * R_OUT
    assert dist2(CX, CY - R_OUT - 1) > R_OUT * R_OUT
    assert LANE_L == (16, 376) and LANE_R == (648, 1008)
    assert BADGE == (512, 252) and BADGE_DY == 116
    assert BADGE_R_OUT == 46 and BADGE_R_IN == 30 and BADGE_BAND == 16
    assert BADGE[1] + BADGE_R_OUT < H


def check_pixels():
    # Outer side of the left hole: magenta, 22 grey, 5 green, then the hole.
    y = CY
    assert classify(PLATE_L - 1, y) == MAGENTA
    assert all(classify(x, y) == GREY for x in range(PLATE_L, LIP_L))
    assert all(classify(x, y) == GREEN for x in range(LIP_L, HOLE_L))
    assert all(classify(x, y) == BLUE for x in range(HOLE_L, HOLE_LI))
    assert all(classify(x, y) == GREEN for x in range(HOLE_LI, RING_L))
    assert classify(RING_L, y) == ORANGE
    assert classify(CX, CY) == BLUE
    # Top of the left bar, away from the ring: 22 grey, 5 green, then the hole.
    x = 200
    assert all(classify(x, yy) == GREY for yy in range(PLATE_T, LIP_T))
    assert all(classify(x, yy) == GREEN for yy in range(LIP_T, WIN_T))
    assert classify(x, WIN_T) == BLUE
    # Mirror, ignoring nothing: the level mark is on the centre line.
    for yy in range(H):
        for xx in range(W // 2):
            if colour(xx, yy) != colour(W - 1 - xx, yy):
                raise SystemExit(f"not mirrored at {xx},{yy}")
    # No magenta sitting between the lip and the ring.
    for yy in range(LIP_T, LIP_B):
        for xx in range(LIP_L, LIP_R):
            if classify(xx, yy) == MAGENTA:
                raise SystemExit(f"gap at {xx},{yy}")
    # The portrait opening is blue and the ring around it is orange, including
    # the lower band where the level icon sits.
    assert classify(CX, CY - R_IN + 2) == BLUE
    assert classify(CX, CY - (R_IN + R_OUT) // 2) == ORANGE
    assert classify(BADGE[0], BADGE[1]) == ORANGE
    # Yellow hole, white band around it, and the portrait ring still orange above that band.
    assert colour(BADGE[0], BADGE[1]) == YELLOW
    assert colour(BADGE[0], BADGE[1] + BADGE_R_IN + 2) == WHITE
    assert colour(BADGE[0], BADGE[1] + BADGE_R_OUT - 1) == WHITE
    assert colour(BADGE[0], H - 1) == MAGENTA
    assert colour(CX, CY - (R_IN + R_OUT) // 2) == ORANGE
    assert colour(CX, CY) == BLUE

    # Extended template checks:
    assert colour_extended(TOP_BADGE[0], TOP_BADGE[1]) == ORANGE
    assert colour_extended(CX, TOP_BADGE[1] - TOP_BADGE_R + 1) == ORANGE  # above ring (y=-16)
    assert colour_extended(CX, CY - R_IN + 10) == ORANGE                  # overlaps top of portrait (y=41)
    assert colour_extended(CX, CY) == BLUE                                # portrait centre still blue
    assert colour_extended(BADGE[0], BADGE[1]) == YELLOW                  # level hole still yellow
    assert colour_extended(EXT_RED_L, EXT_RED_T) == RED                   # red box top-left
    assert colour_extended(EXT_RED_R - 1, PLATE_T - 1) == RED             # red box bottom-right (above bar)
    assert colour_extended(EXT_RED_R - 1, PLATE_B) == MAGENTA             # no red box below bar
    assert colour_extended(EXT_RED_L - 1, EXT_RED_T) == MAGENTA           # outside red box
    assert colour_extended(EXT_RED_L + 10, PLATE_T + 5) == GREY           # grey plate sits in front of red
    for yy in range(-AI_PAD_LAYOUT, H + AI_PAD_LAYOUT):
        for xx in range(W // 2):
            if colour_extended(xx, yy) != colour_extended(W - 1 - xx, yy):
                raise SystemExit(f"extended mask not mirrored at {xx},{yy}")

    # Modular per-section 16:9 layer checks:
    # 1. Every layer guide is mirror-symmetric and preserves the off-limits fiducials.
    # 2. Stacking Order 1..6 back-to-front reproduces colour_extended(x, ly) at every pixel,
    #    and stacking Order 2,3,4,6 reproduces colour(x, y) across 0..H-1.
    primary_draw = {
        "backdrop": RED,
        "frame": GREY,
        "lip": GREEN,
        "ring": ORANGE,
        "crest": ORANGE,
        "level": WHITE,
    }
    for yy in range(-AI_PAD_LAYOUT, H + AI_PAD_LAYOUT):
        for xx in range(W):
            if xx < W // 2:
                for lk in LAYER_KEYS:
                    if colour_layer(lk, xx, yy) != colour_layer(lk, W - 1 - xx, yy):
                        raise SystemExit(f"layer {lk} not mirrored at {xx},{yy}")
            base = colour_layer("frame", xx, yy)
            if base == GREY:
                base = MAGENTA
            ext_stack = base
            for lk in LAYER_KEYS:
                c_lk = colour_layer(lk, xx, yy)
                if c_lk == primary_draw[lk]:
                    ext_stack = c_lk
            if ext_stack != colour_extended(xx, yy):
                raise SystemExit(f"stacked extended layers != colour_extended at {xx},{yy}: {ext_stack} vs {colour_extended(xx, yy)}")
            if 0 <= yy < H:
                std_stack = base
                for lk in ("frame", "lip", "ring", "level"):
                    c_lk = colour_layer(lk, xx, yy)
                    if c_lk == primary_draw[lk]:
                        std_stack = c_lk
                if std_stack != colour(xx, yy):
                    raise SystemExit(f"stacked standard layers != colour at {xx},{yy}: {std_stack} vs {colour(xx, yy)}")


def render(scale, pad_layout=0):
    w = W * scale
    pad_px = pad_layout * scale
    h = H * scale + 2 * pad_px
    buf = bytearray(w * h * 3)
    if pad_px:
        mag_row = bytes(MAGENTA) * w
        for py in range(pad_px):
            buf[py * w * 3:(py + 1) * w * 3] = mag_row
            by = h - 1 - py
            buf[by * w * 3:(by + 1) * w * 3] = mag_row
    for y in range(H):
        row = [colour(x, y) for x in range(W)]
        for sy in range(scale):
            base = ((pad_px + y * scale + sy) * w) * 3
            i = base
            for rgb in row:
                for _ in range(scale):
                    buf[i:i + 3] = rgb
                    i += 3
    return w, h, buf


def render_extended(scale, pad_layout=AI_PAD_LAYOUT):
    w = W * scale
    total_h_layout = H + 2 * pad_layout
    h = total_h_layout * scale
    buf = bytearray(w * h * 3)
    for ly in range(-pad_layout, H + pad_layout):
        row = [colour_extended(x, ly) for x in range(W)]
        for sy in range(scale):
            py = (ly + pad_layout) * scale + sy
            base = (py * w) * 3
            i = base
            for rgb in row:
                for _ in range(scale):
                    buf[i:i + 3] = rgb
                    i += 3
    return w, h, buf


def render_layer(layer_key, scale, pad_layout=AI_PAD_LAYOUT):
    w = W * scale
    total_h_layout = H + 2 * pad_layout
    h = total_h_layout * scale
    buf = bytearray(w * h * 3)
    for ly in range(-pad_layout, H + pad_layout):
        row = [colour_layer(layer_key, x, ly) for x in range(W)]
        for sy in range(scale):
            py = (ly + pad_layout) * scale + sy
            base = (py * w) * 3
            i = base
            for rgb in row:
                for _ in range(scale):
                    buf[i:i + 3] = rgb
                    i += 3
    return w, h, buf


def write_png(path, w, h, rgb):
    raw = bytearray()
    stride = w * 3
    for y in range(h):
        raw.append(0)
        raw.extend(rgb[y * stride:(y + 1) * stride])

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    out_bytes = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    if os.path.exists(path) and open(path, "rb").read() == out_bytes:
        return
    with open(path, "wb") as f:
        f.write(out_bytes)


def spec():
    def box(left, top, right, bottom):
        return {"l": left, "t": top, "r": right, "b": bottom, "w": right - left, "h": bottom - top}

    pad_px = AI_PAD_LAYOUT * SCALE
    return {
        "unit": "layout px, y down. The PNG is SCALE times this.",
        "scale": SCALE,
        "canvas": {"w": W, "h": H},
        "image": {"w": W * SCALE, "h": H * SCALE},
        "aiImage": {"w": W * SCALE, "h": (H + 2 * AI_PAD_LAYOUT) * SCALE, "padY": pad_px, "aspect": "16:9"},
        "atlas": {
            "w": ATLAS_W,
            "h": ATLAS_H,
            "art": list(ART),
            "extTop": list(EXT_TOP),
            "extBot": list(EXT_BOT),
            "strip": list(STRIP),
            "stripY": STRIP_Y,
            "stripPx": {"w": STRIP_W, "h": STRIP_H},
            "stripSlice": {"top": STRIP_SLICE, "right": STRIP_SLICE, "bottom": STRIP_SLICE, "left": STRIP_SLICE},
        },
        "center": {"cx": CX, "cy": CY},
        "portrait": {"rIn": R_IN, "rOut": R_OUT, "pad": 4},
        "lip": LIP,
        "outer": OUTER,
        "board": {"top": BOARD_CORNER, "right": BOARD_CORNER, "bottom": BOARD_CORNER, "left": BOARD_CORNER},
        "health": box(HOLE_L, WIN_T, HOLE_LI, WIN_B),
        "mana": box(HOLE_RI, WIN_T, HOLE_R, WIN_B),
        "plate": box(PLATE_L, PLATE_T, PLATE_R, PLATE_B),
        "layout": {
            "w": W, "h": H, "cx": CX, "cy": CY,
            "rIn": R_IN, "rOut": R_OUT,
            "winL": HOLE_L, "winR": HOLE_R, "winT": WIN_T, "winB": WIN_B,
            "hidden": HIDDEN,
            "plateL": PLATE_L, "plateR": PLATE_R, "plateT": PLATE_T, "plateB": PLATE_B,
            "pivotY": PIVOT_Y,
            "laneL": list(LANE_L), "laneR": list(LANE_R),
            "art": list(ART),
            "extL": EXT_RED_L, "extR": EXT_RED_R, "extTopT": EXT_RED_T, "extBotB": EXT_RED_B,
            "extTop": list(EXT_TOP),
            "extBot": list(EXT_BOT),
            "strip": list(STRIP),
        },
        "level": {
            "cx": BADGE[0], "cy": BADGE[1], "dy": BADGE_DY,
            "outer": 2 * BADGE_R_OUT,
            "band": BADGE_BAND,
            "d": 2 * BADGE_R_IN,
        },
        "extended": {
            "guide": "guides/frame-template-extended-ai.png",
            "topCircle": {
                "cx": TOP_BADGE[0], "cy": TOP_BADGE[1], "dy": TOP_BADGE_DY,
                "r": TOP_BADGE_R, "d": 2 * TOP_BADGE_R,
                "colour": "#{:02X}{:02X}{:02X}".format(*ORANGE),
            },
            "redBox": {
                **box(EXT_RED_L, EXT_RED_T, EXT_RED_R, EXT_RED_B),
                "imageL": EXT_RED_L * SCALE,
                "imageR": EXT_RED_R * SCALE,
                "imageT": (EXT_RED_T + AI_PAD_LAYOUT) * SCALE,
                "imageB": (EXT_RED_B + AI_PAD_LAYOUT) * SCALE,
                "imageW": EXT_RED_W * SCALE,
                "imageH": EXT_RED_H * SCALE,
                "colour": "#{:02X}{:02X}{:02X}".format(*RED),
            },
            "plate": {
                "w": W, "h": EXT_RED_H,
                "topPad": EXT_TOP_H, "botPad": EXT_BOT_H,
                "imageW": W * SCALE, "imageH": EXT_RED_H * SCALE,
            },
            "atlas": {
                "extX": EXT_ATLAS_X, "extW": EXT_ATLAS_W,
                "topY": EXT_TOP_Y, "topH": EXT_TOP_PX_H,
                "botY": EXT_BOT_Y, "botH": EXT_BOT_PX_H,
                "extTop": list(EXT_TOP),
                "extBot": list(EXT_BOT),
            },
            "crestRedBox": {
                **box(CREST_RED_L, CREST_RED_T, CREST_RED_R, CREST_RED_B),
                "imageL": CREST_RED_L * SCALE,
                "imageR": CREST_RED_R * SCALE,
                "imageT": (CREST_RED_T + AI_PAD_LAYOUT) * SCALE,
                "imageB": (CREST_RED_B + AI_PAD_LAYOUT) * SCALE,
                "imageW": (CREST_RED_R - CREST_RED_L) * SCALE,
                "imageH": (CREST_RED_B - CREST_RED_T) * SCALE,
                "colour": "#{:02X}{:02X}{:02X}".format(*RED),
            },
        },
        "layerGuides": {
            key: {
                "order": order_num,
                "guide": f"guides/layers/{fname}",
                "extendedOnly": ext_only,
            }
            for order_num, key, fname, ext_only in LAYER_SPECS
        },
        "colours": {name: "#{:02X}{:02X}{:02X}".format(*rgb) for name, rgb in COLOURS.items()},
        "paint": ["lip", "frame", "ring", "levelRing", "extendedArt"],
        "doNotPaint": ["outside", "game", "levelHole"],
        "drawableOrder": drawable_order_spec(),
    }


def drawable_order_spec():
    """Exact back-to-front drawable pixel regions and net clearance budgets on the 2048x1152 extended stencil."""
    pad_px = AI_PAD_LAYOUT * SCALE
    margin_layout = 10
    margin_px = margin_layout * SCALE  # 20 image px safety margin inside #FF0000 Red edges
    top_circle_top = TOP_BADGE[1] - TOP_BADGE_R          # -17 layout
    top_circle_bot = TOP_BADGE[1] + TOP_BADGE_R          # 57 layout
    top_center_h = top_circle_top - EXT_RED_T            # 53 layout (106 img px)
    upper_flank_w = RING_L - EXT_RED_L                   # 162 layout (324 img px)
    upper_flank_h = PLATE_T - EXT_RED_T                  # 151 layout (302 img px)

    def img_y(ly):
        return (ly + AI_PAD_LAYOUT) * SCALE

    guide_by_order = {order_num: (key, f"guides/layers/{fname}") for order_num, key, fname, _ in LAYER_SPECS}

    return [
        {
            "order": 1,
            "layerKey": guide_by_order[1][0],
            "guide": guide_by_order[1][1],
            "role": "drawable-optional-backdrop",
            "name": "Red (#FF0000) upper background intricate-art box above bar & outside portrait/crest rings (behind everything; unfilled keys to transparent)",
            "hex": "#FF0000",
            "layoutBox": {"l": EXT_RED_L, "t": EXT_RED_T, "r": EXT_RED_R, "b": PLATE_T, "w": EXT_RED_W, "h": PLATE_T - EXT_RED_T},
            "imageBox": {"l": EXT_RED_L * SCALE, "t": img_y(EXT_RED_T), "r": EXT_RED_R * SCALE, "b": img_y(PLATE_T), "w": EXT_RED_W * SCALE, "h": (PLATE_T - EXT_RED_T) * SCALE},
            "safeMarginPx": {"layout": margin_layout, "image": margin_px},
            "clearances": {
                "topCenterAboveTopCircle": {
                    "layoutH": top_center_h, "imageH": top_center_h * SCALE,
                    "safeLayoutH": top_center_h - margin_layout, "safeImageH": (top_center_h - margin_layout) * SCALE,
                },
                "upperFlanksAboveBar": {
                    "layoutW": upper_flank_w, "layoutH": upper_flank_h,
                    "imageW": upper_flank_w * SCALE, "imageH": upper_flank_h * SCALE,
                    "safeImageW": (upper_flank_w - margin_layout) * SCALE, "safeImageH": (upper_flank_h - margin_layout) * SCALE,
                },
            },
        },
        {
            "order": 2,
            "layerKey": guide_by_order[2][0],
            "guide": guide_by_order[2][1],
            "role": "drawable-solid",
            "name": "Grey (#808080) 22px outer bar armor frame (in front of Red; zero vertical step-out past plateT..plateB)",
            "hex": "#808080",
            "layoutBox": {"l": PLATE_L, "t": PLATE_T, "r": PLATE_R, "b": PLATE_B, "band": OUTER},
            "imageBox": {"l": PLATE_L * SCALE, "t": img_y(PLATE_T), "r": PLATE_R * SCALE, "b": img_y(PLATE_B), "band": OUTER * SCALE},
        },
        {
            "order": 3,
            "layerKey": guide_by_order[3][0],
            "guide": guide_by_order[3][1],
            "role": "drawable-solid",
            "name": "Green (#00FF00) 5px inner bar lip (in front of Grey; frames off-limits Blue bar holes)",
            "hex": "#00FF00",
            "layoutBox": {"l": LIP_L, "t": LIP_T, "r": LIP_R, "b": LIP_B, "band": LIP},
            "imageBox": {"l": LIP_L * SCALE, "t": img_y(LIP_T), "r": LIP_R * SCALE, "b": img_y(LIP_B), "band": LIP * SCALE},
        },
        {
            "order": 4,
            "layerKey": guide_by_order[4][0],
            "guide": guide_by_order[4][1],
            "role": "drawable-solid",
            "name": "Orange (#FF8000) central portrait ring (in front of bars & Red; r=105..128 layout / 210..256 image px)",
            "hex": "#FF8000",
            "layoutCircle": {"cx": CX, "cy": CY, "rIn": R_IN, "rOut": R_OUT, "band": R_OUT - R_IN},
            "imageCircle": {"cx": CX * SCALE, "cy": img_y(CY), "rIn": R_IN * SCALE, "rOut": R_OUT * SCALE, "band": (R_OUT - R_IN) * SCALE},
        },
        {
            "order": 5,
            "layerKey": guide_by_order[5][0],
            "guide": guide_by_order[5][1],
            "role": "drawable-crest",
            "name": "Orange (#FF8000) top circular crest medallion + focused Red horn/crown headroom (blends with portrait ring; overlays portrait y=31..57 layout / y=338..390 image px)",
            "hex": "#FF8000",
            "layoutCircle": {"cx": TOP_BADGE[0], "cy": TOP_BADGE[1], "r": TOP_BADGE_R, "t": top_circle_top, "b": top_circle_bot},
            "imageCircle": {"cx": TOP_BADGE[0] * SCALE, "cy": img_y(TOP_BADGE[1]), "r": TOP_BADGE_R * SCALE, "t": img_y(top_circle_top), "b": img_y(top_circle_bot)},
            "crestRedLayoutBox": {"l": CREST_RED_L, "t": CREST_RED_T, "r": CREST_RED_R, "b": CREST_RED_B},
            "crestRedImageBox": {"l": CREST_RED_L * SCALE, "t": img_y(CREST_RED_T), "r": CREST_RED_R * SCALE, "b": img_y(CREST_RED_B)},
        },
        {
            "order": 6,
            "layerKey": guide_by_order[6][0],
            "guide": guide_by_order[6][1],
            "role": "drawable-solid-frontmost",
            "name": "White (#FFFFFF) lower circular level ring (frontmost armor layer on top of portrait ring; r=30..46 layout / 60..92 image px)",
            "hex": "#FFFFFF",
            "layoutCircle": {"cx": BADGE[0], "cy": BADGE[1], "rIn": BADGE_R_IN, "rOut": BADGE_R_OUT, "band": BADGE_BAND},
            "imageCircle": {"cx": BADGE[0] * SCALE, "cy": img_y(BADGE[1]), "rIn": BADGE_R_IN * SCALE, "rOut": BADGE_R_OUT * SCALE, "band": BADGE_BAND * SCALE},
        },
    ]


def measure_stencil_pixels(w: int, h: int, rgb: bytearray):
    """Count exact visible pixels and bounding boxes per stencil colour in a 24-bit RGB buffer."""
    stats = {}
    for y in range(h):
        ro = y * w * 3
        for x in range(w):
            o = ro + x * 3
            c = (rgb[o], rgb[o + 1], rgb[o + 2])
            st = stats.get(c)
            if st is None:
                stats[c] = [1, x, y, x, y]
            else:
                st[0] += 1
                if x < st[1]:
                    st[1] = x
                elif x > st[3]:
                    st[3] = x
                if y < st[2]:
                    st[2] = y
                elif y > st[4]:
                    st[4] = y
    return stats


def print_drawable_order_report(w: int, h: int, rgb: bytearray):
    stats = measure_stencil_pixels(w, h, rgb)
    order = drawable_order_spec()
    c_red = order[0]["clearances"]
    print(f"\n=== Drawable Pixels & Layer Order (guides/frame-template-extended-ai.png, {w}x{h}) ===")
    ordered_rows = [
        ("1 [BACK]", RED, "DRAWABLE (optional)", "Red #FF0000 upper intricate-art backdrop (above bar y<438, outside portrait/crest rings)"),
        ("2", GREY, "DRAWABLE (solid)", "Grey #808080 outer bar frame (44px band; 0 step-out past y=438..657)"),
        ("3", GREEN, "DRAWABLE (solid)", "Green #00FF00 inner bar lip (10px bevel around Blue bar holes)"),
        ("4+5", ORANGE, "DRAWABLE (solid+crest)", "Orange #FF8000 portrait ring (r=210..256) + top crest disc (1024,316 r=74, y<=390)"),
        ("6 [FRONT]", WHITE, "DRAWABLE (solid)", "White #FFFFFF lower level ring (1024,780 r=60..92, on top of portrait ring)"),
        ("X [OFF]", MAGENTA, "OFF-LIMITS (0 paint)", "Magenta #FF00FF exterior (top y=0..135, lower half y>=658 outside ring, flanks x<444 / x>=1604)"),
        ("X [OFF]", BLUE, "OFF-LIMITS (0 paint)", "Blue #0000FF health/mana windows + portrait circle (r<=210 below top crest)"),
        ("X [OFF]", YELLOW, "OFF-LIMITS (0 paint)", "Yellow #FFFF00 level-number hole (1024,780 r<=60)"),
    ]
    for tag, col, status, desc in ordered_rows:
        cnt, x0, y0, x1, y1 = stats[col]
        print(f"  Order {tag:9s} | {status:22s} | {cnt:7d} px | img x={x0:4d}..{x1:4d} ({x1-x0+1:4d}w) y={y0:4d}..{y1:4d} ({y1-y0+1:4d}h) | {desc}")
    print("  --- Red (#FF0000) Net Headroom Budgets (keep >=20 img px / 10 layout px inside Red outer edges!) ---")
    print(
        f"  * Top-center above Top Orange Circle (y_img=136..241):   total {c_red['topCenterAboveTopCircle']['imageH']:3d} img px ({c_red['topCenterAboveTopCircle']['layoutH']:2d} layout) "
        f"-> SAFE <= {c_red['topCenterAboveTopCircle']['safeImageH']:3d} img px ({c_red['topCenterAboveTopCircle']['safeLayoutH']:2d} layout)"
    )
    print(
        f"  * Upper flanks L/R of ring above bar (y_img=136..437):   total {c_red['upperFlanksAboveBar']['imageW']}x{c_red['upperFlanksAboveBar']['imageH']} img px "
        f"-> SAFE <= {c_red['upperFlanksAboveBar']['safeImageW']}x{c_red['upperFlanksAboveBar']['safeImageH']} img px per side"
    )
    print("  * Lower flanks / bottom below bar:                       0 px (Magenta OFF-LIMITS — no bottom wings or bottom chains)")
    print("  --- Modular Per-Section 16:9 Stencils (guides/layers/, back-to-front Order 1 -> 6) ---")
    for order_num, key, fname, ext_only in LAYER_SPECS:
        scope = "extended" if ext_only else "standard+extended"
        print(f"  * Order {order_num} ({key:8s}) [{scope:17s}] -> guides/layers/{fname}")


def check_layout_lua():
    text = open(LAYOUT, encoding="utf-8").read()
    wanted = {
        "w = 1024, h = 300": "w = 1024, h = 300",
        "cx = 512, cy = 136, rIn = 105, rOut = 128": "cx, cy, radii",
        "winL = 35, winR = 989, winT = 108, winB = 164": "windows",
        "cut = { 35, 989, 108, 164 }": "cut",
        "hidden = 128": "hidden",
        "plateL = 8, plateR = 1016, plateT = 81, plateB = 191": "plate",
        "pivotY = 189": "pivot",
        "laneL = { 16, 376 }, laneR = { 648, 1008 }": "lanes",
        "art = { 0, 1, 0, 0.585938 }": "art texcoord",
        "extL = 222, extR = 802, extTopT = -70, extBotB = 350": "extended overhang bounds",
        "extTop = { 0.296875, 0.863281, 0.59375, 0.730469 }": "extTop texcoord",
        "extBot = { 0.296875, 0.863281, 0.738281, 0.835938 }": "extBot texcoord",
        "strip = { 0, 0.292969, 0.59375, 0.808594 }": "strip texcoord",
        "stripPx = { w = 600, h = 220 }": "stripPx",
        "stripSlice = { top = 56, right = 56, bottom = 56, left = 56 }": "stripSlice",
        "board = { top = 28, right = 28, bottom = 28, left = 28 }": "board corner",
        "badge = { dy = 116, d = 60 }": "level circle",
    }
    missing = [label for line, label in wanted.items() if line not in text]
    if missing:
        raise SystemExit("Layout.lua does not match this template: " + ", ".join(missing))


def main():
    ap = argparse.ArgumentParser(description="Build and verify daves_frames 16:9 UV stencil guides and drawable pixel budgets.")
    ap.add_argument("--drawable", action="store_true", help="Print the full back-to-front drawable pixel map and Red headroom clearances.")
    args = ap.parse_args()

    check_geometry()
    check_pixels()
    check_layout_lua()
    ai = os.path.join(GUIDES, "frame-template-ai.png")
    wai, hai, rgbai = render(SCALE, pad_layout=AI_PAD_LAYOUT)
    write_png(ai, wai, hai, rgbai)
    ext_ai = os.path.join(GUIDES, "frame-template-extended-ai.png")
    wext, hext, rgbext = render_extended(SCALE, pad_layout=AI_PAD_LAYOUT)
    write_png(ext_ai, wext, hext, rgbext)
    layer_paths = []
    for order_num, key, fname, _ in LAYER_SPECS:
        lpath = os.path.join(LAYER_GUIDES, fname)
        wl, hl, rgbl = render_layer(key, SCALE, pad_layout=AI_PAD_LAYOUT)
        write_png(lpath, wl, hl, rgbl)
        layer_paths.append((order_num, key, lpath, wl, hl))
    spec_path = os.path.join(TEMPLATE, "frame-template.json")
    with open(spec_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(spec(), f, indent=2)
        f.write("\n")
    print(f"wrote {ai} ({wai}x{hai}, exact 16:9 AI-padded)")
    print(f"wrote {ext_ai} ({wext}x{hext}, exact 16:9 extended AI-padded)")
    for order_num, key, lpath, wl, hl in layer_paths:
        print(f"wrote {lpath} ({wl}x{hl}, Order {order_num} {key} 16:9 layer guide)")
    print(f"wrote {spec_path}")
    print(
        f"holes {HOLE_L},{WIN_T}..{HOLE_LI},{WIN_B} and {HOLE_RI},{WIN_T}..{HOLE_R},{WIN_B}"
        f"  lip {LIP}  outer {OUTER}  ring {R_IN}..{R_OUT}  strip {STRIP_W}x{STRIP_H}@{STRIP_Y}"
        f"  ext {EXT_RED_L}..{EXT_RED_R},{EXT_RED_T}..{EXT_RED_B} (topCircle r={TOP_BADGE_R}@{TOP_BADGE})"
    )
    if args.drawable:
        print_drawable_order_report(wext, hext, rgbext)


if __name__ == "__main__":
    main()
