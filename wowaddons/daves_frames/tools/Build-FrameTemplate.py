"""Draw the daves_frames paint mask from one set of sizes.

This is a colour key, not artwork. Health, mana, and the portrait opening stay
blue (the game draws them). The 5 px lip, the 22 px outer frame, the portrait
ring, and the level ring are the only paintable regions. The yellow disc inside
the level ring is the number placeholder, not paint.

`frame-template-ai.png` adds 276 image px of magenta top and bottom padding
(2048 x 1152, exact 16:9) so 16:9 AI image editors (Gemini Nano Banana /
Imagine) preserve exact 1:1 proportions without stretching or clipping the
portrait ring.

Layout pixels match Layout.lua. The exact canvas mask is 2x, 2048 x 600.

    py -3 tools/Build-FrameTemplate.py
"""

from __future__ import annotations

import json
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(ROOT)
TEMPLATE = os.path.join(ROOT, "template")
GUIDES = os.path.join(TEMPLATE, "guides")
LAYOUT = os.path.join(ADDON, "Layout.lua")

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

# Board 9-slice strip: left 150 and right 150 layout px of the plate at 2x,
# placed 8 atlas px below the 2048 x 600 art slot.
STRIP_RUN_LAYOUT = 150
STRIP_GAP_PX = 8
STRIP_Y = H * SCALE + STRIP_GAP_PX
STRIP_W = STRIP_RUN_LAYOUT * 2 * SCALE
STRIP_H = (PLATE_B - PLATE_T) * SCALE
BOARD_CORNER = OUTER + LIP + 1  # 28 layout px (56 atlas px) encloses miter + lip
STRIP_SLICE = BOARD_CORNER * SCALE

# art and strip texcoords in the 2048 x 1024 atlas
ART = (0, 1, 0, round((H * SCALE) / ATLAS_H, 6))
STRIP = (
    0,
    round(STRIP_W / ATLAS_W, 6),
    round(STRIP_Y / ATLAS_H, 6),
    round((STRIP_Y + STRIP_H) / ATLAS_H, 6),
)

MAGENTA = (255, 0, 255)    # outside. Do not paint.
BLUE = (0, 0, 255)         # health, mana, portrait opening. The game draws these.
GREEN = (0, 255, 0)        # 5px lip around each bar.
GREY = (128, 128, 128)     # thicker outer frame around that lip.
ORANGE = (255, 128, 0)     # portrait ring. Paintable.
WHITE = (255, 255, 255)    # level ring. Painted on top of the portrait ring.
YELLOW = (255, 255, 0)     # level placeholder, inside the level ring. Not paint.

COLOURS = {
    "outside": MAGENTA,
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


def colour(x, y):
    """Mask colour. The level ring and its hole are stamped on top of the plate."""
    d2 = level_d2(x, y)
    if d2 <= BADGE_R_IN * BADGE_R_IN:
        return YELLOW
    if d2 <= BADGE_R_OUT * BADGE_R_OUT:
        return WHITE
    return classify(x, y)


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


def write_png(path, w, h, rgb):
    raw = bytearray()
    stride = w * 3
    for y in range(h):
        raw.append(0)
        raw.extend(rgb[y * stride:(y + 1) * stride])

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


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
            "strip": list(STRIP),
        },
        "level": {
            "cx": BADGE[0], "cy": BADGE[1], "dy": BADGE_DY,
            "outer": 2 * BADGE_R_OUT,
            "band": BADGE_BAND,
            "d": 2 * BADGE_R_IN,
        },
        "colours": {name: "#{:02X}{:02X}{:02X}".format(*rgb) for name, rgb in COLOURS.items()},
        "paint": ["lip", "frame", "ring", "levelRing"],
        "doNotPaint": ["outside", "game", "levelHole"],
    }


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
    check_geometry()
    check_pixels()
    check_layout_lua()
    ai = os.path.join(GUIDES, "frame-template-ai.png")
    wai, hai, rgbai = render(SCALE, pad_layout=AI_PAD_LAYOUT)
    write_png(ai, wai, hai, rgbai)
    spec_path = os.path.join(TEMPLATE, "frame-template.json")
    with open(spec_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(spec(), f, indent=2)
        f.write("\n")
    print(f"wrote {ai} ({wai}x{hai}, exact 16:9 AI-padded)")
    print(f"wrote {spec_path}")
    print(
        f"holes {HOLE_L},{WIN_T}..{HOLE_LI},{WIN_B} and {HOLE_RI},{WIN_T}..{HOLE_R},{WIN_B}"
        f"  lip {LIP}  outer {OUTER}  ring {R_IN}..{R_OUT}  strip {STRIP_W}x{STRIP_H}@{STRIP_Y}"
    )


if __name__ == "__main__":
    main()
