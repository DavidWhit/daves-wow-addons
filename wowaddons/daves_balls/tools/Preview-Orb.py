"""Composite the orb TGA layers (and optional bottom holders, cast shadow & dust) to a PNG.

The PNG container is written with the stdlib. It will not be byte-identical to a
System.Drawing PNG. The pixels are the same sequence the PowerShell script stores.
"""

from __future__ import annotations

import math
import os
import struct
import sys
import zlib

S = 256
LAYERS = (
    "OrbBack", "OrbMask", "OrbShade", "OrbGloss", "OrbGlass", "OrbWave",
    "OrbCloud", "OrbVeins", "OrbSparks", "OrbCore", "OrbHalo",
)

HOLDER_NAMES = {
    "chalice": "Chalice",
    "arcane": "Arcane",
    "sanctum": "Sanctum",
}
SHADOW_Y_NORM = {
    "none": -0.97,
    "chalice": -0.83,
    "arcane": -0.94,
    "sanctum": -0.875,
}
HOLDER_U_MIN, HOLDER_U_MAX = -1.16, 1.16
HOLDER_V_MIN, HOLDER_V_MAX = -1.14, 0.02


def _round_byte(value):
    return round(min(1.0, max(0.0, value)) * 255.0)


def _wrap(value):
    number = round(value)
    return (number % S + S) % S


def _load(media):
    loaded = {}
    for name in LAYERS:
        with open(os.path.join(media, name + ".tga"), "rb") as handle:
            loaded[name] = handle.read()
    return loaded


def _load_tga(path):
    with open(path, "rb") as handle:
        blob = handle.read()
    w, h = struct.unpack_from("<HH", blob, 12)
    top_left = bool(blob[17] & 0x20)
    return (w, h, top_left, blob)


def _sample_tga(tga, fx, fy):
    w, h, top_left, blob = tga
    if fx < 0.0 or fx >= w or fy < 0.0 or fy >= h:
        return (0.0, 0.0, 0.0, 0.0)
    x0 = int(math.floor(fx))
    y0 = int(math.floor(fy))
    x1 = min(w - 1, x0 + 1)
    y1 = min(h - 1, y0 + 1)
    tx = fx - x0
    ty = fy - y0

    def at(ix, iy):
        row = iy if top_left else (h - 1 - iy)
        i = 18 + (row * w + ix) * 4
        return (blob[i + 2] / 255.0, blob[i + 1] / 255.0, blob[i] / 255.0, blob[i + 3] / 255.0)

    c00 = at(x0, y0)
    c10 = at(x1, y0)
    c01 = at(x0, y1)
    c11 = at(x1, y1)
    return tuple(
        (c00[k] * (1.0 - tx) + c10[k] * tx) * (1.0 - ty)
        + (c01[k] * (1.0 - tx) + c11[k] * tx) * ty
        for k in range(4)
    )


def _px(layers, name, x, y):
    blob = layers[name]
    x = _wrap(x)
    y = _wrap(y)
    i = 18 + (y * S + x) * 4
    return (
        blob[i + 2] / 255.0,
        blob[i + 1] / 255.0,
        blob[i] / 255.0,
        blob[i + 3] / 255.0,
    )


def composite(media, color, level, tilt_deg):
    layers = _load(media)
    deep = tuple(channel * 0.35 for channel in color)
    glow = tuple(channel + (1.0 - channel) * 0.35 for channel in color)
    gold = (1.0, 0.72, 0.30)
    level_y = round((0.1 + 0.8 * level) * S)
    rgb = bytearray(S * S * 3)
    for y in range(S):
        for x in range(S):
            red = 0.12
            green = 0.12
            blue = 0.12

            def over(sample, alpha, red=red, green=green, blue=blue):
                return (
                    red * (1.0 - alpha) + sample[0] * alpha,
                    green * (1.0 - alpha) + sample[1] * alpha,
                    blue * (1.0 - alpha) + sample[2] * alpha,
                )

            def add(sample, alpha, red=red, green=green, blue=blue):
                return (
                    red + sample[0] * alpha,
                    green + sample[1] * alpha,
                    blue + sample[2] * alpha,
                )

            pixel = _px(layers, "OrbHalo", x, y)
            red, green, blue = add(glow, pixel[3])
            pixel = _px(layers, "OrbBack", x, y)
            red, green, blue = over(pixel, pixel[3], red, green, blue)
            mask = _px(layers, "OrbMask", x, y)[3]
            surf = level_y + math.tan(tilt_deg * math.pi / 180.0) * (x - 128)
            if y < surf and mask > 0:
                red, green, blue = over(deep, mask, red, green, blue)
                sample = _px(layers, "OrbCloud", x * 0.8 + 40, y * 0.8 + 70)
                red, green, blue = add(glow, sample[3] * 0.45 * mask, red, green, blue)
                sample = _px(layers, "OrbVeins", x * 0.55, y * 0.55)
                red, green, blue = add(glow, sample[3] * 0.9 * mask, red, green, blue)
                sample = _px(layers, "OrbVeins", x * 0.45 + 100, y * 0.45 + 30)
                red, green, blue = add(gold, sample[3] * 0.7 * mask, red, green, blue)
                sample = _px(layers, "OrbSparks", x, y)
                red, green, blue = add((1.0, 1.0, 1.0), sample[3] * 0.8 * mask, red, green, blue)
                sample = _px(layers, "OrbCore", x, y)
                red, green, blue = add(gold, sample[3] * 0.8 * mask, red, green, blue)
            dy = y - surf
            if abs(dy) < 18:
                wave = _px(layers, "OrbWave", x * 0.75 + 30, 128 + dy * 256 / 36)
                red, green, blue = add(glow, wave[3] * 0.6 * mask, red, green, blue)
            pixel = _px(layers, "OrbShade", x, y)
            red, green, blue = over(pixel, pixel[3], red, green, blue)
            pixel = _px(layers, "OrbGloss", x, y)
            red, green, blue = add(pixel, pixel[3] * 0.8, red, green, blue)
            pixel = _px(layers, "OrbGlass", x, y)
            red, green, blue = add(pixel, pixel[3], red, green, blue)
            row = (S - 1 - y) * S + x
            rgb[row * 3] = _round_byte(red)
            rgb[row * 3 + 1] = _round_byte(green)
            rgb[row * 3 + 2] = _round_byte(blue)
    return rgb


def _smooth(edge0, edge1, value):
    if edge0 == edge1:
        return 1.0 if value >= edge1 else 0.0
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def _eval_orbit_pattern(pattern, phase, lift, p):
    """Evaluate analytic 3D orbital coordinates (x, y, z, env) in orb space."""
    rx = p["rx"]
    ry = p["ry"]
    y_base = p["y_base"]
    tilt = p["tilt"]
    ct, st = math.cos(tilt), math.sin(tilt)
    env = 1.0

    if pattern == "helix":
        h = lift % 1.0
        env = _smooth(0.0, 0.14, h) * (1.0 - _smooth(0.84, 1.0, h))
        a = phase + (0.0 if p["strand"] > 0 else math.pi)
        bulge = rx * (0.74 + 0.30 * math.sin(h * math.pi))
        ox = bulge * math.cos(a)
        oz = math.sin(a)
        oy = -0.68 + h * 1.36 + oz * 0.13
    elif pattern == "figure8":
        ox = rx * math.sin(phase)
        oy = y_base + ry * math.sin(2.0 * phase)
        oz = math.cos(phase)
    elif pattern == "vortex":
        h = lift % 1.0
        env = _smooth(0.0, 0.12, h) * (1.0 - _smooth(0.80, 1.0, h))
        rad = (0.56 + 0.58 * math.pow(h, 0.65)) * (rx / 1.0)
        swirl = phase + h * 6.2
        ox = rad * math.cos(swirl)
        oz = math.sin(swirl)
        oy = -0.80 + h * 1.64 + oz * (0.09 + 0.11 * h)
    else:
        # "ring": tilted 3D Saturn ring / equatorial halo with subtle harmonic wave.
        ca, sa = math.cos(phase), math.sin(phase)
        ox = ca * rx
        oz = sa
        oy = y_base + oz * ry + 0.065 * math.sin(phase * 2.0 + p["wave"])

    px = ox * ct - oy * st
    py = ox * st + oy * ct
    return px, py, oz, env


def _generate_preview_motes(pattern, color, accent, count=20, tails=True, tail_length=68, phase_shift=0.0):
    """Build multi-pattern 3D orbiting motes and curved 3-segment OrbTail ribbons for PNG preview."""
    glow = tuple(c + (1.0 - c) * 0.42 for c in color)
    pat = (pattern or "ring").lower()
    tail_scale = max(0.20, min(1.0, tail_length / 100.0))
    tail_segs = 3
    motes = []
    tail_list = []

    # Golden-ratio quasi-random spacing produces organic-looking, non-clumping snapshot previews.
    phi = 0.61803398875
    patterns_cycle = ("ring", "helix", "figure8", "vortex")

    for i in range(count):
        q1 = (i * phi + 0.13 + phase_shift * 0.17) % 1.0
        q2 = ((i + 1) * 0.7548776662 + phase_shift * 0.29) % 1.0
        q3 = ((i + 1) * 0.5698402909 + phase_shift * 0.41) % 1.0
        q4 = ((i + 1) * 0.3819660112 + phase_shift * 0.53) % 1.0

        active_pat = patterns_cycle[i % 4] if pat == "mixed" else pat
        is_wisp = 0.55 < q1 <= 0.84
        is_spark = q1 > 0.84

        if active_pat == "ring":
            params = {
                "rx": 0.92 + q2 * 0.26,
                "ry": 0.18 + q3 * 0.14,
                "y_base": -0.10 + (q4 - 0.5) * 0.24,
                "tilt": (-0.34 if phase_shift < 0.5 else 0.30) + (q3 - 0.5) * 0.16,
                "wave": q4 * 2.0 * math.pi,
                "strand": 1,
            }
            phase = (i / max(count, 1)) * 2.0 * math.pi + phase_shift * 1.7 + q2 * 0.25
            lift = q3
            lag_step = 0.26 * tail_scale
            lift_step = 0.0
        elif active_pat == "helix":
            params = {
                "rx": 0.94 + q2 * 0.20,
                "ry": 0.14,
                "y_base": 0.0,
                "tilt": (0.16 if phase_shift < 0.5 else -0.18) + (q3 - 0.5) * 0.10,
                "wave": 0.0,
                "strand": 1 if (i % 2 == 0) else -1,
            }
            lift = (i / max(count, 1) + phase_shift * 0.23) % 1.0
            phase = lift * 5.2 + phase_shift * 2.1
            lag_step = 0.25 * tail_scale
            lift_step = 0.044 * tail_scale
        elif active_pat == "figure8":
            params = {
                "rx": 0.96 + q2 * 0.22,
                "ry": 0.44 + q3 * 0.20,
                "y_base": -0.04 + (q4 - 0.5) * 0.14,
                "tilt": (-0.24 if phase_shift < 0.5 else 0.26) + (q3 - 0.5) * 0.12,
                "wave": 0.0,
                "strand": 1,
            }
            phase = (i / max(count, 1)) * 2.0 * math.pi + phase_shift * 1.4 + q2 * 0.18
            lift = 0.5
            lag_step = 0.22 * tail_scale
            lift_step = 0.0
        else:
            # "vortex": ascending spiral rising from the lower cradle & widening around the orb.
            params = {
                "rx": 0.96 + q2 * 0.16,
                "ry": 0.14,
                "y_base": 0.0,
                "tilt": (q3 - 0.5) * 0.10,
                "wave": 0.0,
                "strand": 1,
            }
            lift = (0.08 + 0.84 * (i / max(count, 1)) + phase_shift * 0.17) % 1.0
            phase = (i % 2) * math.pi + q4 * 0.55 + phase_shift * 2.1
            lag_step = 0.08 * tail_scale
            lift_step = 0.048 * tail_scale

        # Sample head (k=0) and 3 trailing orbit points along the exact analytic curve.
        pts = []
        for k in range(tail_segs + 1):
            pts.append(_eval_orbit_pattern(active_pat, phase - k * lag_step, lift - k * lift_step, params))

        hx, hy, hz, henv = pts[0]
        if henv <= 0.02:
            continue

        depth = (hz + 1.0) * 0.5
        rad = (0.088 + q2 * 0.058) if is_wisp else ((0.044 + q2 * 0.038) if is_spark else (0.052 + q2 * 0.044))
        head_rad = rad * (0.72 + 0.36 * depth)
        wb = 0.42 if is_spark else 0.18
        col = tuple(
            (glow[c] + (accent[c] - glow[c]) * q4) * (1.0 - wb) + wb
            for c in range(3)
        )
        base_alpha = (0.48 + 0.44 * depth) * (0.90 if is_spark else 0.72) * henv

        # Tangent heading from trailing point pts[1] toward head pts[0].
        hdx = hx - pts[1][0]
        hdy = hy - pts[1][1]
        h_ang = math.atan2(hdy, hdx) if (hdx * hdx + hdy * hdy) > 1e-8 else 0.0
        motes.append((hx, hy, hz >= 0.0, head_rad, is_wisp, math.cos(h_ang), math.sin(h_ang), col, base_alpha))

        if tails:
            taper_w = (0.82, 0.62, 0.44)
            taper_a = (0.76, 0.50, 0.26)
            for k in range(1, tail_segs + 1):
                ax, ay, az, aenv = pts[k - 1]
                bx, by, bz, benv = pts[k]
                seg_env = min(aenv, benv)
                if seg_env <= 0.02:
                    continue
                # Skip wrap-around jump if ascending lift crossed 0/1 boundary between adjacent points.
                dx = ax - bx
                dy = ay - by
                seg_dist = math.hypot(dx, dy)
                if seg_dist > 0.75:
                    continue
                cx = 0.5 * (ax + bx)
                cy = 0.5 * (ay + by)
                cz = 0.5 * (az + bz)
                ang = math.atan2(dy, dx) if seg_dist > 1e-5 else h_ang
                ca, sa = math.cos(ang), math.sin(ang)
                s_depth = (cz + 1.0) * 0.5
                # Overlap neighboring segments cleanly so OrbTail's feathered ends form one silky ribbon.
                half_len = max(seg_dist * 0.94, rad * 0.78)
                half_thick = rad * taper_w[k - 1] * (0.76 + 0.34 * s_depth)
                seg_alpha = (0.52 + 0.44 * s_depth) * taper_a[k - 1] * seg_env * (0.92 if is_spark else 0.80)
                bbox_x = abs(ca) * half_len + abs(sa) * half_thick
                bbox_y = abs(sa) * half_len + abs(ca) * half_thick
                tail_list.append((cx, cy, cz >= 0.0, half_len, half_thick, ca, sa, col, seg_alpha, bbox_x, bbox_y))

    return motes, tail_list


def composite_holder(
    media,
    color,
    level,
    tilt_deg,
    holder_key,
    size=320,
    bob_v=0.0,
    cast_shadow=False,
    light_x=-0.55,
    light_bright=0.88,
    dust_pattern=None,
    dust_tails=True,
    tail_length=68,
    dust_count=20,
    phase_shift=0.0,
):
    """Render an orb with optional bottom holder, bob offset, cast shadow & 3D multi-pattern dust trails."""
    layers = _load(media)
    h_tex = None
    key = (holder_key or "none").lower()
    h_name = HOLDER_NAMES.get(key)
    if h_name:
        h_tex = {
            part: _load_tga(os.path.join(media, f"Holder{h_name}{part}.tga"))
            for part in ("Back", "Front", "Liquid", "Accent", "Sheen")
        }
    shadow_tga = _load_tga(os.path.join(media, "OrbCastShadow.tga")) if cast_shadow else None
    has_dust = bool(dust_pattern)
    mote_tga = _load_tga(os.path.join(media, "OrbMote.tga")) if has_dust else None
    wisp_tga = _load_tga(os.path.join(media, "OrbWisp.tga")) if has_dust else None
    tail_tga = _load_tga(os.path.join(media, "OrbTail.tga")) if (has_dust and dust_tails) else None

    deep = tuple(channel * 0.35 for channel in color)
    glow = tuple(channel + (1.0 - channel) * 0.35 for channel in color)
    gold = (1.0, 0.72, 0.30)
    if has_dust:
        all_motes, all_tails = _generate_preview_motes(
            dust_pattern, color, gold,
            count=dust_count, tails=dust_tails, tail_length=tail_length, phase_shift=phase_shift,
        )
    else:
        all_motes, all_tails = [], []

    rear_motes = [m for m in all_motes if not m[2]]
    front_motes = [m for m in all_motes if m[2]]
    rear_tails = [t for t in all_tails if not t[2]]
    front_tails = [t for t in all_tails if t[2]]

    u_lo, u_hi = -1.24, 1.24
    v_lo, v_hi = -1.22, 1.12
    w = size
    h = int(round(size * (v_hi - v_lo) / (u_hi - u_lo)))
    rgb = bytearray(w * h * 3)
    level_v = -0.80 + 1.60 * level
    tan_tilt = math.tan(tilt_deg * math.pi / 180.0)

    sh_cy = SHADOW_Y_NORM.get(key, -0.88)
    sh_cx = -light_x * 0.16
    sh_rx = 0.44 + 0.08 * max(0.0, bob_v / 0.08) + 0.05 * abs(light_x)
    sh_ry = 0.125 + 0.025 * max(0.0, bob_v / 0.08)
    sh_alpha = (0.30 + 0.65 * light_bright) * (0.95 - 0.25 * max(0.0, bob_v / 0.08))

    def sample_holder(part, u, v, mirror_x=False):
        tga = h_tex[part]
        tw, th = tga[0], tga[1]
        hu = -u if mirror_x else u
        fx = (hu - HOLDER_U_MIN) / (HOLDER_U_MAX - HOLDER_U_MIN) * tw - 0.5
        fy = (HOLDER_V_MAX - v) / (HOLDER_V_MAX - HOLDER_V_MIN) * th - 0.5
        return _sample_tga(tga, fx, fy)

    def sample_dust(u, v, row_motes, row_tails):
        acc_r = acc_g = acc_b = 0.0
        if row_tails and tail_tga is not None:
            tw, th = tail_tga[0], tail_tga[1]
            for cx, cy, _, hlen, hth, ca, sa, tcol, ta, bx, _ in row_tails:
                du = u - cx
                if abs(du) > bx:
                    continue
                dv = v - cy
                lx = du * ca + dv * sa
                if abs(lx) > hlen:
                    continue
                ly = -du * sa + dv * ca
                if abs(ly) > hth:
                    continue
                fx = (lx / hlen * 0.5 + 0.5) * tw - 0.5
                fy = (-ly / hth * 0.5 + 0.5) * th - 0.5
                pix = _sample_tga(tail_tga, fx, fy)
                a = pix[3] * ta
                if a > 1e-4:
                    acc_r += tcol[0] * pix[0] * a
                    acc_g += tcol[1] * pix[1] * a
                    acc_b += tcol[2] * pix[2] * a
        for mx, my, _, mrad, is_wisp, ca, sa, mcol, ma in row_motes:
            dx = u - mx
            if abs(dx) > mrad:
                continue
            dy = v - my
            if is_wisp:
                lx = dx * ca + dy * sa
                ly = -dx * sa + dy * ca
                if abs(lx) > mrad or abs(ly) > mrad:
                    continue
                spr = wisp_tga
                fx = (lx / mrad * 0.5 + 0.5) * spr[0] - 0.5
                fy = (-ly / mrad * 0.5 + 0.5) * spr[1] - 0.5
            else:
                spr = mote_tga
                fx = (dx / mrad * 0.5 + 0.5) * spr[0] - 0.5
                fy = (-dy / mrad * 0.5 + 0.5) * spr[1] - 0.5
            pix = _sample_tga(spr, fx, fy)
            a = pix[3] * ma
            if a > 1e-4:
                acc_r += mcol[0] * pix[0] * a
                acc_g += mcol[1] * pix[1] * a
                acc_b += mcol[2] * pix[2] * a
        return acc_r, acc_g, acc_b

    for py in range(h):
        v = v_hi - (py + 0.5) * (v_hi - v_lo) / h
        v_orb = v - bob_v
        orb_y = (v_orb + 1.0) * 0.5 * (S - 1)
        row_rm = [m for m in rear_motes if abs(v - m[1]) <= m[3]] if rear_motes else None
        row_rt = [t for t in rear_tails if abs(v - t[1]) <= t[10]] if rear_tails else None
        row_fm = [m for m in front_motes if abs(v - m[1]) <= m[3]] if front_motes else None
        row_ft = [t for t in front_tails if abs(v - t[1]) <= t[10]] if front_tails else None
        has_rear_dust = bool(row_rm or row_rt)
        has_front_dust = bool(row_fm or row_ft)
        for px in range(w):
            u = u_lo + (px + 0.5) * (u_hi - u_lo) / w
            orb_x = (u + 1.0) * 0.5 * (S - 1)
            red, green, blue = 0.11, 0.11, 0.13

            def over(c, a):
                nonlocal red, green, blue
                red = red * (1.0 - a) + c[0] * a
                green = green * (1.0 - a) + c[1] * a
                blue = blue * (1.0 - a) + c[2] * a

            def add(c, a):
                nonlocal red, green, blue
                red += c[0] * a
                green += c[1] * a
                blue += c[2] * a

            # 1. Holder Back (dish floor + rear petals behind shadow & orb)
            if h_tex:
                hb = sample_holder("Back", u, v)
                if hb[3] > 0.0:
                    over(hb, hb[3])

            # 2. Rear 3D swirling dust motes & curved OrbTail segments (behind orb)
            if has_rear_dust:
                dr, dg, db = sample_dust(u, v, row_rm or (), row_rt or ())
                red += dr
                green += dg
                blue += db

            # 3. Light-driven Cast Shadow (on top of stone dish floor, underneath bobbing orb!)
            if shadow_tga is not None:
                sx = (u - sh_cx) / sh_rx
                sy = (v - sh_cy) / sh_ry
                if -1.0 <= sx <= 1.0 and -1.0 <= sy <= 1.0:
                    st = _sample_tga(
                        shadow_tga,
                        (sx * 0.5 + 0.5) * shadow_tga[0] - 0.5,
                        (-sy * 0.5 + 0.5) * shadow_tga[1] - 0.5,
                    )
                    if st[3] > 0.0:
                        over(st, st[3] * sh_alpha)

            # 4. Bobbing Orb body
            if -1.0 <= u <= 1.0 and -1.0 <= v_orb <= 1.0:
                ix, iy = round(orb_x), round(orb_y)
                add(glow, _px(layers, "OrbHalo", ix, iy)[3])
                bk = _px(layers, "OrbBack", ix, iy)
                over(bk, bk[3])
                mask = _px(layers, "OrbMask", ix, iy)[3]
                surf_v = level_v + tan_tilt * u
                if v_orb < surf_v and mask > 0.0:
                    over(deep, mask)
                    add(glow, _px(layers, "OrbCloud", ix * 0.8 + 40, iy * 0.8 + 70)[3] * 0.45 * mask)
                    add(glow, _px(layers, "OrbVeins", ix * 0.55, iy * 0.55)[3] * 0.90 * mask)
                    add(gold, _px(layers, "OrbVeins", ix * 0.45 + 100, iy * 0.45 + 30)[3] * 0.70 * mask)
                    add((1.0, 1.0, 1.0), _px(layers, "OrbSparks", ix, iy)[3] * 0.80 * mask)
                    add(gold, _px(layers, "OrbCore", ix, iy)[3] * 0.80 * mask)
                dy_px = (v_orb - surf_v) * (S * 0.5)
                if abs(dy_px) < 18.0 and mask > 0.0:
                    wv = _px(layers, "OrbWave", ix * 0.75 + 30, 128 + dy_px * 256 / 36)
                    add(glow, wv[3] * 0.60 * mask)
                sh = _px(layers, "OrbShade", ix, iy)
                over(sh, sh[3])
                gl = _px(layers, "OrbGloss", ix, iy)
                add(gl, gl[3] * 0.85)
                gs = _px(layers, "OrbGlass", ix, iy)
                over(gs, gs[3])

            # 5. Stationary Holder Front + Liquid/Flow/Accent/Sheen
            if h_tex:
                hf = sample_holder("Front", u, v)
                if hf[3] > 0.0:
                    over(hf, hf[3])
                hl = sample_holder("Liquid", u, v)
                if hl[3] > 0.0:
                    add(glow, hl[3] * 0.72)
                    vx = (u * 0.55 + 0.35) * S
                    vy = (v * 0.55 + 0.40) * S
                    add(glow, _px(layers, "OrbVeins", vx, vy)[3] * hl[3] * 0.65)
                ha = sample_holder("Accent", u, v)
                if ha[3] > 0.0:
                    add(gold, ha[3] * 0.86)
                hsl = sample_holder("Sheen", u, v, mirror_x=False)
                if hsl[3] > 0.0:
                    add(hsl, hsl[3] * 0.74)
                hsr = sample_holder("Sheen", u, v, mirror_x=True)
                if hsr[3] > 0.0:
                    add(hsr, hsr[3] * 0.28)

            # 6. Front 3D swirling dust motes & curved OrbTail segments (in front of orb & holder)
            if has_front_dust:
                dr, dg, db = sample_dust(u, v, row_fm or (), row_ft or ())
                red += dr
                green += dg
                blue += db

            off = (py * w + px) * 3
            rgb[off] = _round_byte(red)
            rgb[off + 1] = _round_byte(green)
            rgb[off + 2] = _round_byte(blue)
    return w, h, rgb


def write_png(path, rgb, width=S, height=S):
    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    raw = bytearray()
    stride = width * 3
    for y in range(height):
        raw.append(0)
        raw += rgb[y * stride:(y + 1) * stride]
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


def composite_sheet(media, out_path, tile_size=320):
    """Render a 2x4 comparison grid showcasing all 4 holders & 4 multi-pattern 3D orbits with curved tails."""
    columns = [
        ("none", 0.0, False, "ring"),
        ("chalice", 0.025, True, "helix"),
        ("arcane", 0.055, True, "figure8"),
        ("sanctum", 0.065, True, "vortex"),
    ]
    rows = [
        ((0.75, 0.05, 0.05), 0.72, 3.0, 0.15),
        ((0.10, 0.25, 0.95), 0.56, -2.5, 0.72),
    ]
    tiles = []
    tw = th = 0
    for col_rgb, lvl, tilt, pshift in rows:
        row_tiles = []
        for variant, bob_v, shadow_on, pattern in columns:
            tw, th, buf = composite_holder(
                media, col_rgb, lvl, tilt, variant, size=tile_size,
                bob_v=bob_v, cast_shadow=shadow_on,
                dust_pattern=pattern, dust_tails=True, tail_length=72, dust_count=18,
                phase_shift=pshift,
            )
            row_tiles.append(buf)
        tiles.append(row_tiles)
    pad = 12
    w_all = len(columns) * tw + (len(columns) + 1) * pad
    h_all = len(rows) * th + (len(rows) + 1) * pad
    canvas = bytearray([22, 22, 26] * (w_all * h_all))
    for r_idx, row_tiles in enumerate(tiles):
        y0 = pad + r_idx * (th + pad)
        for c_idx, buf in enumerate(row_tiles):
            x0 = pad + c_idx * (tw + pad)
            for ty in range(th):
                dst_off = ((y0 + ty) * w_all + x0) * 3
                src_off = ty * tw * 3
                canvas[dst_off:dst_off + tw * 3] = buf[src_off:src_off + tw * 3]
    parent = os.path.dirname(os.path.abspath(out_path))
    if parent and not os.path.isdir(parent):
        os.makedirs(parent, exist_ok=True)
    write_png(out_path, canvas, w_all, h_all)


def _args(argv):
    out = {
        "Media": "", "Out": "", "Color": "0.10,0.25,0.95",
        "Level": "0.65", "TiltDeg": "0", "Holder": "", "Sheet": "",
        "Pattern": "", "Tails": "1",
    }
    i = 0
    while i < len(argv):
        token = argv[i]
        if not token.startswith("-"):
            print("Unknown argument: " + token, file=sys.stderr, flush=True)
            raise SystemExit(1)
        raw = token[1:]
        if ":" in raw:
            key, value = raw.split(":", 1)
        else:
            key = raw
            if i + 1 >= len(argv):
                print(f"Missing value for -{key}", file=sys.stderr, flush=True)
                raise SystemExit(1)
            i += 1
            value = argv[i]
        found = next((name for name in out if name.lower() == key.lower()), None)
        if not found:
            print("Unknown argument: " + token, file=sys.stderr, flush=True)
            raise SystemExit(1)
        out[found] = value
        i += 1
    return out


def main(argv):
    args = _args(argv)
    if args["Sheet"]:
        if not args["Media"]:
            print("Pass -Media <folder> -Sheet <png>", file=sys.stderr, flush=True)
            raise SystemExit(1)
        composite_sheet(args["Media"], args["Sheet"])
        return
    if not args["Media"] or not args["Out"]:
        print("Pass -Media <folder> -Out <png>", file=sys.stderr, flush=True)
        raise SystemExit(1)
    color = tuple(float(part) for part in args["Color"].split(","))
    if args["Holder"] or args["Pattern"]:
        tails_on = args["Tails"].lower() not in ("0", "false", "no", "off")
        w, h, rgb = composite_holder(
            args["Media"], color, float(args["Level"]), float(args["TiltDeg"]),
            args["Holder"] or "none",
            dust_pattern=(args["Pattern"] or None),
            dust_tails=tails_on,
        )
        write_png(args["Out"], rgb, w, h)
    else:
        rgb = composite(args["Media"], color, float(args["Level"]), float(args["TiltDeg"]))
        write_png(args["Out"], rgb)


if __name__ == "__main__":
    main(sys.argv[1:])
