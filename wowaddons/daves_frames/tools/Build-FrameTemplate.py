"""Draw the daves_frames paint mask from one set of sizes.

This is a colour key, not artwork. Health, mana, and the portrait opening stay
blue (the game draws them). The ring, the 5px lip, and the thicker outer frame
are the only paintable regions. The level icon is drawn by the addon, on top
of the lower ring, so the ring is painted straight through that spot.

Layout pixels match Layout.lua. The paint file is 2x, 2048 x 544.

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
W, H = 1024, 272
CX, CY = 512, 136
R_IN, R_OUT = 105, 128
LIP = 5
OUTER = 22
PAD = 8
BAR_H = 56
SCALE = 2  # image pixels per layout pixel. 2x fits a 2048-wide atlas.
ATLAS_H = 1024

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
BADGE_DY = (R_IN + R_OUT) // 2
BADGE = (CX, CY + BADGE_DY)

# art texcoord bottom: the 2x mask occupies the top of a 2048 x 1024 atlas
ART = (0, 1, 0, round((H * SCALE) / ATLAS_H, 6))

MAGENTA = (255, 0, 255)    # outside. Do not paint.
BLUE = (0, 0, 255)         # health, mana, portrait opening. The game draws these.
GREEN = (0, 255, 0)        # 5px lip around each bar.
GREY = (128, 128, 128)     # thicker outer frame around that lip.
ORANGE = (255, 128, 0)     # portrait ring. Paintable.

COLOURS = {
    "outside": MAGENTA,
    "game": BLUE,
    "lip": GREEN,
    "frame": GREY,
    "ring": ORANGE,
}


def dist2(x, y):
    dx = (x + 0.5) - CX
    dy = (y + 0.5) - CY
    return dx * dx + dy * dy


def inside(x, y, left, top, right, bottom):
    return left <= x < right and top <= y < bottom


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
    assert W == 1024 and H == 272
    assert (H * SCALE, W * SCALE) == (544, 2048)
    assert ART[3] == 0.531250
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
    # Ring clears the top and bottom of the canvas by PAD, using pixel centres.
    assert dist2(CX, CY - R_OUT) <= R_OUT * R_OUT
    assert dist2(CX, CY - R_OUT - 1) > R_OUT * R_OUT
    assert LANE_L == (16, 376) and LANE_R == (648, 1008)
    assert BADGE == (512, 252) and BADGE_DY == 116


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
            if classify(xx, yy) != classify(W - 1 - xx, yy):
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


def render(scale):
    w, h = W * scale, H * scale
    buf = bytearray(w * h * 3)
    for y in range(H):
        row = [classify(x, y) for x in range(W)]
        for sy in range(scale):
            base = ((y * scale + sy) * w) * 3
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

    return {
        "unit": "layout px, y down. The PNG is SCALE times this.",
        "scale": SCALE,
        "canvas": {"w": W, "h": H},
        "image": {"w": W * SCALE, "h": H * SCALE},
        "atlas": {"w": W * SCALE, "h": ATLAS_H, "art": list(ART)},
        "center": {"cx": CX, "cy": CY},
        "portrait": {"rIn": R_IN, "rOut": R_OUT, "pad": 4},
        "lip": LIP,
        "outer": OUTER,
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
        },
        "level": {
            "cx": BADGE[0], "cy": BADGE[1], "dy": BADGE_DY,
            "atlas": "UI-HUD-UnitFrame-SmallCircle",
        },
        "colours": {name: "#{:02X}{:02X}{:02X}".format(*rgb) for name, rgb in COLOURS.items()},
        "paint": ["lip", "frame", "ring"],
        "doNotPaint": ["outside", "game"],
    }


def check_layout_lua():
    text = open(LAYOUT, encoding="utf-8").read()
    wanted = {
        "w = 1024, h = 272": "w = 1024, h = 272",
        "cx = 512, cy = 136, rIn = 105, rOut = 128": "cx, cy, radii",
        "winL = 35, winR = 989, winT = 108, winB = 164": "windows",
        "cut = { 35, 989, 108, 164 }": "cut",
        "hidden = 128": "hidden",
        "plateL = 8, plateR = 1016, plateT = 81, plateB = 191": "plate",
        "pivotY = 189": "pivot",
        "laneL = { 16, 376 }, laneR = { 648, 1008 }": "lanes",
        "art = { 0, 1, 0, 0.531250 }": "art texcoord",
    }
    missing = [label for line, label in wanted.items() if line not in text]
    if missing:
        raise SystemExit("Layout.lua does not match this template: " + ", ".join(missing))


def main():
    check_geometry()
    check_pixels()
    check_layout_lua()
    path = os.path.join(GUIDES, "frame-template.png")
    w, h, rgb = render(SCALE)
    write_png(path, w, h, rgb)
    one = os.path.join(GUIDES, "frame-template-1x.png")
    w1, h1, rgb1 = render(1)
    write_png(one, w1, h1, rgb1)
    spec_path = os.path.join(TEMPLATE, "frame-template.json")
    with open(spec_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(spec(), f, indent=2)
        f.write("\n")
    print(f"wrote {path} ({w}x{h})")
    print(f"wrote {one} ({w1}x{h1})")
    print(f"wrote {spec_path}")
    print(
        f"holes {HOLE_L},{WIN_T}..{HOLE_LI},{WIN_B} and {HOLE_RI},{WIN_T}..{HOLE_R},{WIN_B}"
        f"  lip {LIP}  outer {OUTER}  ring {R_IN}..{R_OUT}"
    )


if __name__ == "__main__":
    main()
