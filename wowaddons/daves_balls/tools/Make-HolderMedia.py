"""Paint optional bottom orb-holder and effect TGA layers for daves_balls.

Generates 3 distinct bottom-only cradle variants (512x256, 32-bit uncompressed
BGRA TGA, top-left origin) engineered to sit cleanly underneath the lower arc
of the glass sphere (ORB_R = 0.80) without cluttering the upper orb:

  - Chalice : Gilded Chalice (wrought dark-iron & antique brass cup + keystone gem)
  - Arcane  : Arcane Cradle (Titan/Dalaran levitation ring & plasma conduits)
  - Sanctum : Sanctum Lotus (carved dark-basalt & antique-gold blooming lotus altar
              basin with a visible 3/4 concave dish for bobbing & cast shadows)

Also writes shared effect layers:
  - OrbCastShadow.tga (256x128) - two-zone umbra+penumbra light-driven cast shadow
  - OrbMote.tga       (64x64)   - luminous swirling dust speck with micro-glint
  - OrbWisp.tga       (64x64)   - tapered organic drifting stardust/ember wisp
  - OrbTail.tga       (128x32)  - silky tapered comet-tail ribbon for 3D dust trails

Each holder variant writes 5 layers:
  Holder<Name>Back.tga   - rear cradle/petals/basin dish behind the orb & shadow
  Holder<Name>Front.tga  - foreground cradle/petals in front of the lower glass
  Holder<Name>Liquid.tga - ADD glow tinted by the orb's liquid colour (+ flow mask)
  Holder<Name>Accent.tga - ADD energy/runes/veins tinted by the orb's accent colour
  Holder<Name>Sheen.tga  - ADD left-lit metallic specular (mirrored in Lua for right)
"""

from __future__ import annotations

import math
import os
import struct
import sys

W = 512
H = 256

# Normalized orb coordinates (orb center = (0, 0), glass sphere radius = 0.80):
# u in [-1.16, +1.16] (span 2.32), v in [-1.14, +0.02] (span 1.16) -> exact 2:1 square pixels.
ORB_R = 0.80
U_MIN, U_MAX = -1.16, 1.16
V_MIN, V_MAX = -1.14, 0.02
PX_DU = (U_MAX - U_MIN) / W


def clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    if value < lo:
        return lo
    if value > hi:
        return hi
    return value


def smooth(edge0: float, edge1: float, value: float) -> float:
    if edge0 == edge1:
        return 1.0 if value >= edge1 else 0.0
    t = clamp((value - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def lerp3(c0: tuple[float, float, float], c1: tuple[float, float, float], t: float) -> tuple[float, float, float]:
    return (c0[0] + (c1[0] - c0[0]) * t, c0[1] + (c1[1] - c0[1]) * t, c0[2] + (c1[2] - c0[2]) * t)


def smin(a: float, b: float, k: float) -> float:
    h = clamp(0.5 + 0.5 * (b - a) / k)
    return b * (1.0 - h) + a * h - k * h * (1.0 - h)


def _byte(v: float) -> int:
    n = int(round(v * 255.0))
    if n < 0:
        return 0
    if n > 255:
        return 255
    return n


def _tga_header(width: int, height: int) -> bytes:
    # Uncompressed 32-bit BGRA TGA, top-left origin (0x28).
    return struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)


def _write_tga(path: str, buf: bytearray, width: int = W, height: int = H) -> None:
    with open(path, "wb") as handle:
        handle.write(_tga_header(width, height))
        handle.write(buf)


def _put(buf: bytearray, idx: int, r: float, g: float, b: float, a: float) -> None:
    if a <= 1e-4:
        return
    buf[idx] = _byte(b)
    buf[idx + 1] = _byte(g)
    buf[idx + 2] = _byte(r)
    buf[idx + 3] = _byte(a)


def _over(
    dst: tuple[float, float, float, float],
    src: tuple[float, float, float, float],
) -> tuple[float, float, float, float]:
    sa = clamp(src[3])
    if sa <= 1e-5:
        return dst
    da = clamp(dst[3])
    out_a = sa + da * (1.0 - sa)
    if out_a <= 1e-5:
        return (0.0, 0.0, 0.0, 0.0)
    inv = 1.0 / out_a
    r = (src[0] * sa + dst[0] * da * (1.0 - sa)) * inv
    g = (src[1] * sa + dst[1] * da * (1.0 - sa)) * inv
    b = (src[2] * sa + dst[2] * da * (1.0 - sa)) * inv
    return (r, g, b, out_a)


def _bevel_dome(dist: float, bevel: float) -> float:
    """Rounded dome height profile in [0, 1] from signed distance (<=0 inside)."""
    if dist >= 0.0:
        return 0.0
    x = clamp(-dist / max(bevel, 1e-5))
    return math.sqrt(max(0.0, 1.0 - (1.0 - x) * (1.0 - x)))


def _grain(u: float, v: float) -> float:
    return (
        0.50 * math.sin(u * 41.0 + v * 29.0) * math.cos(u * 23.0 - v * 47.0)
        + 0.30 * math.sin(u * 83.0 - v * 67.0 + 1.3)
        + 0.20 * math.cos(u * 131.0 + v * 113.0)
    )


def _sample_bezier_curve(
    pts: list[tuple[float, float, float]],
    steps: int = 24,
) -> list[tuple[float, float, float, float]]:
    """Sample a Bezier control polygon of (x, y, radius) into (x, y, r, t) points."""
    n = len(pts) - 1
    out: list[tuple[float, float, float, float]] = []
    for i in range(steps + 1):
        t = i / steps
        work = list(pts)
        for _ in range(n):
            work = [
                (
                    work[j][0] + (work[j + 1][0] - work[j][0]) * t,
                    work[j][1] + (work[j + 1][1] - work[j][1]) * t,
                    work[j][2] + (work[j + 1][2] - work[j][2]) * t,
                )
                for j in range(len(work) - 1)
            ]
        out.append((work[0][0], work[0][1], work[0][2], t))
    return out


def _eval_spline(
    px: float,
    py: float,
    samples: list[tuple[float, float, float, float]],
) -> tuple[float, float, float, float]:
    """Return (signed_dist, along_t, signed_cross_norm, local_radius) to a sampled tapered curve."""
    best_sd = 1e9
    best_t = 0.0
    best_cross = 0.0
    best_r = 0.01
    for i in range(len(samples) - 1):
        ax, ay, ar, at = samples[i]
        bx, by, br, bt = samples[i + 1]
        vx, vy = bx - ax, by - ay
        wx, wy = px - ax, py - ay
        len2 = vx * vx + vy * vy
        if len2 <= 1e-12:
            continue
        f = clamp((wx * vx + wy * vy) / len2)
        cx, cy = ax + vx * f, ay + vy * f
        dx, dy = px - cx, py - cy
        d = math.hypot(dx, dy)
        r = ar + (br - ar) * f
        sd = d - r
        if sd < best_sd:
            best_sd = sd
            best_t = at + (bt - at) * f
            inv_l = 1.0 / math.sqrt(len2)
            cross = (dx * (-vy * inv_l) + dy * (vx * inv_l)) / max(r, 1e-4)
            best_cross = cross
            best_r = r
    return best_sd, best_t, best_cross, best_r


def _sd_box(px: float, py: float, cx: float, cy: float, hx: float, hy: float, r: float = 0.0) -> float:
    dx = abs(px - cx) - (hx - r)
    dy = abs(py - cy) - (hy - r)
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    inside = min(max(dx, dy), 0.0)
    return outside + inside - r


def _sd_diamond(px: float, py: float, cx: float, cy: float, rx: float, ry: float, round_r: float = 0.0) -> float:
    x = abs(px - cx) / rx
    y = abs(py - cy) / ry
    scale = (rx + ry) * 0.5
    return (x + y - 1.0) * scale * 0.7071 - round_r


def _sd_ellipse_approx(px: float, py: float, cx: float, cy: float, rx: float, ry: float) -> float:
    nx = (px - cx) / rx
    ny = (py - cy) / ry
    k0 = math.hypot(nx, ny)
    if k0 < 1e-5:
        return -min(rx, ry)
    k1 = math.hypot(nx / rx, ny / ry)
    return k0 * (k0 - 1.0) / max(k1, 1e-5)


def _shade_metal(
    u: float,
    v: float,
    nx: float,
    ny: float,
    nz: float,
    base_dark: tuple[float, float, float],
    base_mid: tuple[float, float, float],
    base_hi: tuple[float, float, float],
    orb_reflect: float,
    ao: float = 1.0,
    spec_power: float = 10.0,
    spec_strength: float = 0.48,
) -> tuple[tuple[float, float, float], float]:
    """Compute sculpted metallic RGB and left-lit cursor sheen intensity."""
    ndotl = clamp(nx * 0.12 + ny * 0.62 + nz * 0.78)
    rim = clamp(-nx * 0.45 + ny * 0.35 + nz * 0.35)
    d_orb = math.hypot(u, v) + 1e-4
    ou, ov = -u / d_orb, -v / d_orb
    orb_dot = clamp(nx * ou + ny * ov + nz * 0.25)
    orb_prox = smooth(1.12, 0.78, d_orb) * orb_reflect

    g = _grain(u, v) * 0.04
    t = clamp(ndotl * 0.80 + 0.14 + g)
    if t < 0.5:
        col = lerp3(base_dark, base_mid, t * 2.0)
    else:
        col = lerp3(base_mid, base_hi, (t - 0.5) * 2.0)

    spec = math.pow(clamp(nx * 0.08 + ny * 0.55 + nz * 0.83), spec_power) * spec_strength
    r = col[0] * ao + base_hi[0] * spec + rim * 0.05 + orb_dot * orb_prox * 0.12
    g_c = col[1] * ao + base_hi[1] * spec + rim * 0.06 + orb_dot * orb_prox * 0.10
    b = col[2] * ao + base_hi[2] * spec + rim * 0.08 + orb_dot * orb_prox * 0.10

    # Directional left-side specular for Holder<Name>Sheen.tga (mirrored in Lua for right).
    l_dot = clamp(nx * -0.76 + ny * 0.54 + nz * 0.36)
    l_side = smooth(0.42, -0.48, u)
    sheen = (
        math.pow(l_dot, 5.5) * 0.76
        + math.pow(clamp(nx * -0.58 + ny * 0.66 + nz * 0.48), 11.0) * 0.54
    ) * l_side * ao
    return (clamp(r), clamp(g_c), clamp(b)), clamp(sheen)


def _compute_normal(height_fn, u: float, v: float, relief: float = 2.6) -> tuple[float, float, float]:
    eps = PX_DU * 0.95
    hx = (height_fn(u + eps, v) - height_fn(u - eps, v)) / (2.0 * eps)
    hy = (height_fn(u, v + eps) - height_fn(u, v - eps)) / (2.0 * eps)
    nx = -hx * relief
    ny = -hy * relief
    nz = 1.0
    inv = 1.0 / math.sqrt(nx * nx + ny * ny + nz * nz)
    return (nx * inv, ny * inv, nz * inv)


# ===========================================================================
# VARIANT 1: GILDED CHALICE (Wrought Dark-Iron & Antique Brass Reliquary Cup)
# ===========================================================================
CHALICE_WING = _sample_bezier_curve([
    (0.00, -0.845, 0.068),
    (0.32, -0.815, 0.060),
    (0.56, -0.665, 0.044),
    (0.70, -0.455, 0.022),
], steps=26)

CHALICE_SCROLL = _sample_bezier_curve([
    (0.675, -0.475, 0.022),
    (0.765, -0.395, 0.018),
    (0.745, -0.325, 0.013),
    (0.695, -0.365, 0.009),
], steps=18)

CHALICE_CLASP = _sample_bezier_curve([
    (0.655, -0.485, 0.017),
    (0.635, -0.440, 0.013),
    (0.605, -0.405, 0.007),
], steps=12)


def _chalice_front_sdf(u: float, v: float) -> tuple[float, str]:
    au = abs(u)
    sd_wing, wt, wcross, _ = _eval_spline(au, v, CHALICE_WING)
    scallop = 0.006 * math.sin(wt * math.pi * 7.0) * smooth(0.08, 0.25, wt) * (1.0 - smooth(0.75, 0.96, wt))
    sd_wing -= scallop

    sd_scroll, _, _, _ = _eval_spline(au, v, CHALICE_SCROLL)
    sd_clasp, _, _, _ = _eval_spline(au, v, CHALICE_CLASP)

    neck_t = clamp((-v - 0.86) / 0.20)
    half_w = 0.165 + 0.175 * math.pow(smooth(0.32, 0.96, neck_t), 1.3) - 0.035 * math.sin(neck_t * math.pi)
    if v < -1.028:
        half_w += 0.038 * smooth(-1.025, -1.048, v)
    sd_ped = _sd_box(au, v, 0.0, -0.968, half_w, 0.098, 0.018)
    sd_foot = _sd_box(au, v, 0.0, -1.048, 0.375, 0.022, 0.011)
    sd_base = smin(sd_ped, sd_foot, 0.014)

    sd_bezel = _sd_diamond(au, v, 0.0, -0.848, 0.110, 0.120, 0.014)
    sd_gem = _sd_diamond(au, v, 0.0, -0.848, 0.058, 0.068, 0.006)

    sd_cup = smin(sd_wing, sd_base, 0.020)
    sd_all = min(sd_cup, sd_scroll, sd_clasp, sd_bezel)

    if sd_gem < 0.0:
        return sd_all, "gem"
    if sd_bezel < 0.0:
        return sd_all, "gold"
    if sd_scroll < 0.004 or sd_clasp < 0.004:
        return sd_all, "gold"
    on_wing_trim = sd_wing < 0.0 and (abs(wcross) > 0.56 or wt > 0.80)
    on_foot_trim = (abs(v - (-1.048)) < 0.017 and au < 0.375) or (abs(v - (-0.985)) < 0.012 and au < 0.255)
    if on_wing_trim or on_foot_trim:
        return sd_all, "gold"
    return sd_all, "iron"


def _chalice_height(u: float, v: float) -> float:
    au = abs(u)
    sd_wing, wt, wcross, _ = _eval_spline(au, v, CHALICE_WING)
    sd_scroll, _, _, _ = _eval_spline(au, v, CHALICE_SCROLL)
    sd_clasp, _, _, _ = _eval_spline(au, v, CHALICE_CLASP)
    neck_t = clamp((-v - 0.86) / 0.20)
    half_w = 0.165 + 0.175 * math.pow(smooth(0.32, 0.96, neck_t), 1.3) - 0.035 * math.sin(neck_t * math.pi)
    sd_ped = _sd_box(au, v, 0.0, -0.968, half_w, 0.098, 0.018)
    sd_foot = _sd_box(au, v, 0.0, -1.048, 0.375, 0.022, 0.011)
    sd_bezel = _sd_diamond(au, v, 0.0, -0.848, 0.110, 0.120, 0.014)
    sd_gem = _sd_diamond(au, v, 0.0, -0.848, 0.058, 0.068, 0.006)

    h = 0.0
    h_ped = _bevel_dome(smin(sd_ped, sd_foot, 0.014), 0.036) * 0.62
    flutes = 0.055 * math.cos(u * 42.0) * smooth(-1.02, -0.96, v) * smooth(-0.87, -0.92, v)
    mold1 = 0.16 * math.exp(-math.pow((v - (-1.048)) / 0.014, 2))
    mold2 = 0.12 * math.exp(-math.pow((v - (-0.985)) / 0.010, 2))
    h = max(h, h_ped + flutes + mold1 + mold2)

    if sd_wing < 0.005:
        h_w = _bevel_dome(sd_wing, 0.030) * 0.72
        rail = 0.18 * smooth(0.45, 0.78, abs(wcross))
        beads = 0.045 * math.pow(0.5 + 0.5 * math.cos(wt * math.pi * 16.0), 2) * smooth(0.50, 0.75, wcross)
        h = max(h, h_w + rail + beads)

    h = max(h, _bevel_dome(sd_scroll, 0.018) * 0.78)
    h = max(h, _bevel_dome(sd_clasp, 0.014) * 0.74)

    if sd_bezel < 0.004:
        h_bz = _bevel_dome(sd_bezel, 0.032) * 0.92 + 0.12
        if sd_gem < 0.0:
            fx = abs(u) / 0.058
            fy = abs(v - (-0.848)) / 0.068
            facet = clamp(1.0 - max(fx, fy) * 0.65 - (fx + fy) * 0.35)
            h_bz = 0.78 + facet * 0.42
        h = max(h, h_bz)
    return h


def paint_chalice(out_dir: str) -> None:
    buf_back = bytearray(W * H * 4)
    buf_front = bytearray(W * H * 4)
    buf_liquid = bytearray(W * H * 4)
    buf_accent = bytearray(W * H * 4)
    buf_sheen = bytearray(W * H * 4)

    iron_d, iron_m, iron_h = (0.05, 0.05, 0.07), (0.14, 0.15, 0.18), (0.36, 0.39, 0.46)
    gold_d, gold_m, gold_h = (0.24, 0.15, 0.04), (0.66, 0.48, 0.15), (0.99, 0.85, 0.44)
    gem_d, gem_m, gem_h = (0.02, 0.02, 0.03), (0.06, 0.07, 0.09), (0.22, 0.25, 0.30)

    for y in range(H):
        v = V_MAX - (y + 0.5) * (V_MAX - V_MIN) / H
        for x in range(W):
            u = U_MIN + (x + 0.5) * (U_MAX - U_MIN) / W
            idx = (y * W + x) * 4
            au = abs(u)
            d = math.hypot(u, v)
            theta = abs(math.atan2(u, -v))

            back_rgba = (0.0, 0.0, 0.0, 0.0)
            sh_ell = math.hypot(u / 0.44, (v - (-1.072)) / 0.042)
            ground_a = 0.48 * math.exp(-2.6 * sh_ell * sh_ell)
            if ground_a > 1e-4:
                back_rgba = _over(back_rgba, (0.01, 0.01, 0.02, ground_a))

            rear_ang = 1.0 - smooth(0.86, 1.06, theta)
            rear_r_in = ORB_R * 0.84
            rear_r_out = ORB_R * (1.075 - 0.06 * smooth(0.0, 1.0, theta))
            rear_band = smooth(rear_r_in - 0.012, rear_r_in + 0.010, d) * (1.0 - smooth(rear_r_out - 0.010, rear_r_out + 0.012, d))
            rear_a = rear_band * rear_ang
            if rear_a > 1e-3:
                rim_hi = smooth(rear_r_out - 0.032, rear_r_out - 0.008, d)
                rc = lerp3((0.04, 0.03, 0.03), (0.28, 0.20, 0.07), rim_hi * 0.78)
                back_rgba = _over(back_rgba, (rc[0], rc[1], rc[2], rear_a * 0.95))
            _put(buf_back, idx, *back_rgba)

            sd, mat = _chalice_front_sdf(u, v)
            front_rgba = (0.0, 0.0, 0.0, 0.0)

            if d < ORB_R + 0.006 and sd > -0.005 and sd < 0.075:
                in_glass = 1.0 - smooth(ORB_R - 0.012, ORB_R + 0.005, d)
                ao_sh = (1.0 - smooth(0.0, 0.068, max(0.0, sd))) * in_glass * 0.54 * (1.0 - smooth(0.82, 1.12, theta))
                if ao_sh > 1e-4:
                    front_rgba = _over(front_rgba, (0.01, 0.01, 0.02, ao_sh))

            body_a = 1.0 - smooth(-PX_DU * 0.75, PX_DU * 0.75, sd)
            sheen_val = 0.0
            if body_a > 1e-3:
                nx, ny, nz = _compute_normal(_chalice_height, u, v, relief=2.9)
                outline = smooth(-0.011, -0.002, sd)
                if mat == "gold":
                    rgb, sheen_val = _shade_metal(u, v, nx, ny, nz, gold_d, gold_m, gold_h, 0.85, spec_power=11.0, spec_strength=0.62)
                elif mat == "gem":
                    rgb, sheen_val = _shade_metal(u, v, nx, ny, nz, gem_d, gem_m, gem_h, 0.60, spec_power=22.0, spec_strength=0.55)
                else:
                    rgb, sheen_val = _shade_metal(u, v, nx, ny, nz, iron_d, iron_m, iron_h, 0.60, spec_power=9.0, spec_strength=0.38)
                rgb = lerp3(rgb, (0.03, 0.02, 0.02), outline * 0.78)
                front_rgba = _over(front_rgba, (rgb[0], rgb[1], rgb[2], body_a))
            _put(buf_front, idx, *front_rgba)

            liq = 0.0
            sd_gem = _sd_diamond(au, v, 0.0, -0.848, 0.058, 0.068, 0.006)
            if sd_gem < 0.022:
                facet_glow = 0.58 + 0.40 * (1.0 - smooth(-0.042, -0.004, sd_gem))
                gem_core = (1.0 - smooth(-0.006, 0.008, sd_gem)) * facet_glow
                gem_halo = math.exp(-math.pow(max(0.0, sd_gem) / 0.016, 2)) * 0.30
                liq = max(liq, gem_core + gem_halo)
            for sx, sy in ((0.295, -0.805), (0.485, -0.705)):
                sd_s = math.hypot((au - sx) / 0.030, (v - sy) / 0.014)
                liq = max(liq, math.exp(-3.0 * sd_s * sd_s) * 0.72)
            if body_a > 0.05 and d < ORB_R + 0.072:
                inner_bounce = smooth(ORB_R + 0.062, ORB_R - 0.015, d) * (1.0 - smooth(0.75, 1.05, theta)) * body_a
                liq = max(liq, inner_bounce * 0.38)
            if liq > 1e-3:
                _put(buf_liquid, idx, 1.0, 1.0, 1.0, clamp(liq))

            acc = 0.0
            gd = math.hypot(u + 0.012, v - (-0.834))
            if gd < 0.055:
                gang = math.atan2(v - (-0.834), u + 0.012)
                star = math.pow(abs(math.cos(2.0 * gang)), 12) * math.exp(-gd / 0.028)
                acc = max(acc, math.exp(-math.pow(gd / 0.011, 2)) * 0.72 + star * 0.55)
            sd_w, wt, wcross, _ = _eval_spline(au, v, CHALICE_WING)
            if sd_w < 0.0 and 0.15 < wt < 0.88:
                filigree_wave = 0.22 * math.sin(wt * math.pi * 6.0)
                vein = math.exp(-math.pow((wcross - filigree_wave) / 0.14, 2)) * smooth(0.15, 0.22, wt) * (1.0 - smooth(0.80, 0.90, wt))
                acc = max(acc, vein * 0.65)
            tip_d = math.hypot(au - 0.708, v - (-0.362))
            acc = max(acc, math.exp(-math.pow(tip_d / 0.024, 2)) * 0.58)
            if acc > 1e-3:
                _put(buf_accent, idx, 1.0, 1.0, 1.0, clamp(acc))

            if sheen_val > 1e-3 and body_a > 0.1:
                _put(buf_sheen, idx, 1.0, 0.96, 0.86, clamp(sheen_val * body_a))

    _write_tga(os.path.join(out_dir, "HolderChaliceBack.tga"), buf_back)
    _write_tga(os.path.join(out_dir, "HolderChaliceFront.tga"), buf_front)
    _write_tga(os.path.join(out_dir, "HolderChaliceLiquid.tga"), buf_liquid)
    _write_tga(os.path.join(out_dir, "HolderChaliceAccent.tga"), buf_accent)
    _write_tga(os.path.join(out_dir, "HolderChaliceSheen.tga"), buf_sheen)


# ===========================================================================
# VARIANT 2: ARCANE CRADLE (Titan/Dalaran Levitation Ring & Plasma Conduits)
# ===========================================================================
ARCANE_ARC = _sample_bezier_curve([
    (0.00, -0.975, 0.044),
    (0.32, -0.945, 0.036),
    (0.58, -0.805, 0.026),
    (0.75, -0.605, 0.015),
], steps=26)

ARCANE_PRONG_OUTER = _sample_bezier_curve([
    (0.585, -0.790, 0.024),
    (0.695, -0.660, 0.021),
    (0.735, -0.515, 0.016),
    (0.672, -0.462, 0.008),
], steps=20)

ARCANE_PRONG_MID = _sample_bezier_curve([
    (0.280, -0.942, 0.021),
    (0.315, -0.865, 0.016),
    (0.295, -0.802, 0.008),
], steps=14)

ARCANE_BOLT = _sample_bezier_curve([
    (0.666, -0.464, 0.006),
    (0.620, -0.525, 0.005),
    (0.555, -0.592, 0.005),
    (0.475, -0.645, 0.004),
], steps=18)


def _arcane_ring_sd(u: float, v: float, front_only: bool) -> tuple[float, float]:
    cy = -0.715
    rx = 0.785
    ry = 0.165
    nx = u / rx
    ny = (v - cy) / ry
    k0 = math.hypot(nx, ny)
    if k0 < 1e-5:
        return 1.0, 0.0
    k1 = math.hypot(nx / rx, ny / ry)
    sd = k0 * (k0 - 1.0) / max(k1, 1e-5)
    if front_only:
        w = 1.0 - smooth(-0.04, 0.14, ny)
        if w < 0.01:
            return 1.0, 0.0
        thick = 0.0185 * (0.76 + 0.24 * clamp(-ny))
        return abs(sd) - thick, w
    w = smooth(-0.14, 0.04, ny)
    if w < 0.01:
        return 1.0, 0.0
    thick = 0.016 * (0.86 - 0.14 * clamp(ny))
    return abs(sd) - thick, w


def _arcane_front_sdf(u: float, v: float) -> tuple[float, str]:
    au = abs(u)
    sd_arc, at, across, _ = _eval_spline(au, v, ARCANE_ARC)
    sd_p1, p1t, _, _ = _eval_spline(au, v, ARCANE_PRONG_OUTER)
    sd_p2, p2t, _, _ = _eval_spline(au, v, ARCANE_PRONG_MID)
    sd_core = _sd_diamond(au, v, 0.0, -0.970, 0.090, 0.074, 0.012)
    sd_core_socket = _sd_diamond(au, v, 0.0, -0.970, 0.044, 0.036, 0.004)
    sd_spire = _sd_diamond(au, v, 0.0, -0.878, 0.026, 0.056, 0.004)
    sd_finial = _sd_diamond(au, v, 0.0, -1.036, 0.036, 0.042, 0.004)
    sd_ring, ring_w = _arcane_ring_sd(u, v, front_only=True)
    if ring_w < 0.25:
        sd_ring = 1.0

    sd_body = min(smin(sd_arc, sd_core, 0.014), sd_p1, sd_p2, sd_spire, sd_finial, sd_ring)

    if sd_core_socket < 0.0:
        return sd_body, "socket"
    if sd_ring < 0.002:
        return sd_body, "gold"
    if (sd_p1 < 0.002 and p1t > 0.62) or (sd_p2 < 0.002 and p2t > 0.58) or sd_spire < 0.002:
        return sd_body, "gold"
    if sd_arc < 0.002 and (abs(across) > 0.60 or at > 0.84):
        return sd_body, "gold"
    if sd_core < 0.002 and sd_core > -0.020:
        return sd_body, "gold"
    if sd_finial < 0.002:
        return sd_body, "gold"
    return sd_body, "obsidian"


def _arcane_height(u: float, v: float) -> float:
    au = abs(u)
    sd_arc, _, across, _ = _eval_spline(au, v, ARCANE_ARC)
    sd_p1, _, _, _ = _eval_spline(au, v, ARCANE_PRONG_OUTER)
    sd_p2, _, _, _ = _eval_spline(au, v, ARCANE_PRONG_MID)
    sd_core = _sd_diamond(au, v, 0.0, -0.970, 0.090, 0.074, 0.012)
    sd_spire = _sd_diamond(au, v, 0.0, -0.878, 0.026, 0.056, 0.004)
    sd_finial = _sd_diamond(au, v, 0.0, -1.036, 0.036, 0.042, 0.004)
    sd_ring, ring_w = _arcane_ring_sd(u, v, front_only=True)

    h = 0.0
    if sd_arc < 0.004:
        h = max(h, _bevel_dome(sd_arc, 0.024) * 0.72 + 0.16 * smooth(0.50, 0.80, abs(across)))
    h = max(h, _bevel_dome(sd_p1, 0.016) * 0.82)
    h = max(h, _bevel_dome(sd_p2, 0.014) * 0.78)
    h = max(h, _bevel_dome(sd_core, 0.030) * 0.94 + 0.10)
    h = max(h, _bevel_dome(sd_spire, 0.014) * 0.88)
    h = max(h, _bevel_dome(sd_finial, 0.016) * 0.75)
    if ring_w >= 0.25 and sd_ring < 0.004:
        h = max(h, _bevel_dome(sd_ring, 0.013) * 0.86 * ring_w)
    return h


def paint_arcane(out_dir: str) -> None:
    buf_back = bytearray(W * H * 4)
    buf_front = bytearray(W * H * 4)
    buf_liquid = bytearray(W * H * 4)
    buf_accent = bytearray(W * H * 4)
    buf_sheen = bytearray(W * H * 4)

    obs_d, obs_m, obs_h = (0.04, 0.05, 0.09), (0.13, 0.16, 0.24), (0.42, 0.48, 0.62)
    gold_d, gold_m, gold_h = (0.28, 0.20, 0.07), (0.72, 0.56, 0.24), (1.00, 0.90, 0.58)
    sock_d, sock_m, sock_h = (0.02, 0.02, 0.04), (0.05, 0.06, 0.10), (0.18, 0.22, 0.30)

    for y in range(H):
        v = V_MAX - (y + 0.5) * (V_MAX - V_MIN) / H
        for x in range(W):
            u = U_MIN + (x + 0.5) * (U_MAX - U_MIN) / W
            idx = (y * W + x) * 4
            au = abs(u)
            d = math.hypot(u, v)
            theta = abs(math.atan2(u, -v))

            back_rgba = (0.0, 0.0, 0.0, 0.0)
            sh_ell = math.hypot(u / 0.54, (v - (-1.080)) / 0.038)
            g_sh = 0.32 * math.exp(-2.8 * sh_ell * sh_ell)
            if g_sh > 1e-4:
                back_rgba = _over(back_rgba, (0.01, 0.02, 0.04, g_sh))

            sd_back_ring, br_w = _arcane_ring_sd(u, v, front_only=False)
            if br_w > 0.01:
                br_a = (1.0 - smooth(-PX_DU * 0.8, PX_DU * 0.8, sd_back_ring)) * br_w
                if br_a > 1e-3:
                    edge_hi = smooth(-0.014, -0.004, sd_back_ring)
                    rc = lerp3((0.12, 0.14, 0.20), (0.58, 0.44, 0.18), edge_hi * 0.85)
                    back_rgba = _over(back_rgba, (rc[0], rc[1], rc[2], br_a * 0.95))
            _put(buf_back, idx, *back_rgba)

            sd, mat = _arcane_front_sdf(u, v)
            front_rgba = (0.0, 0.0, 0.0, 0.0)

            sd_fr, fr_w = _arcane_ring_sd(u, v, front_only=True)
            if d < ORB_R + 0.005 and fr_w > 0.25 and sd_fr > -0.002 and sd_fr < 0.040:
                in_g = 1.0 - smooth(ORB_R - 0.012, ORB_R + 0.005, d)
                r_sh = (1.0 - smooth(0.0, 0.036, max(0.0, sd_fr))) * in_g * 0.38 * fr_w
                if r_sh > 1e-4:
                    front_rgba = _over(front_rgba, (0.01, 0.01, 0.03, r_sh))

            body_a = 1.0 - smooth(-PX_DU * 0.75, PX_DU * 0.75, sd)
            sheen_val = 0.0
            if body_a > 1e-3:
                nx, ny, nz = _compute_normal(_arcane_height, u, v, relief=3.0)
                outline = smooth(-0.009, -0.001, sd)
                if mat == "gold":
                    rgb, sheen_val = _shade_metal(u, v, nx, ny, nz, gold_d, gold_m, gold_h, 0.90, spec_power=13.0, spec_strength=0.68)
                elif mat == "socket":
                    rgb, sheen_val = _shade_metal(u, v, nx, ny, nz, sock_d, sock_m, sock_h, 0.50, spec_power=18.0, spec_strength=0.45)
                else:
                    rgb, sheen_val = _shade_metal(u, v, nx, ny, nz, obs_d, obs_m, obs_h, 0.76, spec_power=14.0, spec_strength=0.50)
                rgb = lerp3(rgb, (0.02, 0.02, 0.04), outline * 0.72)
                front_rgba = _over(front_rgba, (rgb[0], rgb[1], rgb[2], body_a))
            _put(buf_front, idx, *front_rgba)

            liq = 0.0
            gap_r = math.exp(-math.pow((d - 0.872) / 0.058, 2))
            gap_ang = 1.0 - smooth(0.52, 0.98, theta)
            liq = max(liq, gap_r * gap_ang * 0.56)
            for ex, ey, er, ea in (
                (0.0, -0.822, 0.038, 0.85),
                (0.0, -0.970, 0.040, 0.88),
                (0.295, -0.800, 0.028, 0.78),
                (0.668, -0.464, 0.032, 0.82),
            ):
                ed = math.hypot(au - ex, v - ey)
                liq = max(liq, math.exp(-math.pow(ed / er, 2)) * ea)
            if fr_w > 0.25 and abs(sd_fr) < 0.022:
                liq = max(liq, math.exp(-math.pow(sd_fr / 0.013, 2)) * 0.44 * fr_w)
            if liq > 1e-3:
                _put(buf_liquid, idx, 1.0, 1.0, 1.0, clamp(liq))

            acc = 0.0
            sd_b, bt, _, _ = _eval_spline(au, v, ARCANE_BOLT)
            wave_off = 0.008 * math.sin(bt * math.pi * 6.0)
            bolt_d = abs(sd_b + wave_off)
            if bolt_d < 0.018:
                bolt_a = math.exp(-math.pow(bolt_d / 0.006, 2)) * (0.55 + 0.45 * math.sin(bt * math.pi))
                acc = max(acc, bolt_a * 0.86)
            sd_a, at, across, _ = _eval_spline(au, v, ARCANE_ARC)
            if sd_a < -0.002 and 0.16 < at < 0.82:
                rune_pulse = math.pow(0.5 + 0.5 * math.cos(at * math.pi * 10.0), 4)
                rune_line = math.exp(-math.pow(across / 0.22, 2))
                acc = max(acc, rune_pulse * rune_line * 0.78)
            for cx, cy, cr, ca in ((0.0, -0.970, 0.016, 0.78), (0.0, -0.822, 0.016, 0.82), (0.668, -0.464, 0.015, 0.85)):
                cd = math.hypot(au - cx, v - cy)
                acc = max(acc, math.exp(-math.pow(cd / cr, 2)) * ca)
            if acc > 1e-3:
                _put(buf_accent, idx, 1.0, 1.0, 1.0, clamp(acc))

            if sheen_val > 1e-3 and body_a > 0.1:
                _put(buf_sheen, idx, 0.96, 0.98, 1.0, clamp(sheen_val * body_a))

    _write_tga(os.path.join(out_dir, "HolderArcaneBack.tga"), buf_back)
    _write_tga(os.path.join(out_dir, "HolderArcaneFront.tga"), buf_front)
    _write_tga(os.path.join(out_dir, "HolderArcaneLiquid.tga"), buf_liquid)
    _write_tga(os.path.join(out_dir, "HolderArcaneAccent.tga"), buf_accent)
    _write_tga(os.path.join(out_dir, "HolderArcaneSheen.tga"), buf_sheen)


# ===========================================================================
# VARIANT 3: SANCTUM LOTUS (Carved Basalt & Antique-Gold Blooming Altar Basin)
# Engineered with a visible 3/4 concave dish floor in Back so the bobbing orb
# casts a live light-driven shadow onto the stone basin behind the front petals.
# ===========================================================================
DISH_CY = -0.878
DISH_RX = 0.620
DISH_RY = 0.155

# Front overlapping sculpted lotus petals (sampled curves with organic leaf taper):
SANCTUM_PETAL_CENTER = _sample_bezier_curve([
    (0.000, -0.998, 0.092),
    (0.000, -0.935, 0.118),
    (0.000, -0.858, 0.072),
    (0.000, -0.780, 0.006),
], steps=22)

SANCTUM_PETAL_MID = _sample_bezier_curve([
    (0.140, -0.985, 0.078),
    (0.325, -0.945, 0.082),
    (0.470, -0.825, 0.056),
    (0.540, -0.688, 0.006),
], steps=24)

SANCTUM_PETAL_OUTER = _sample_bezier_curve([
    (0.375, -0.935, 0.056),
    (0.625, -0.820, 0.052),
    (0.755, -0.600, 0.036),
    (0.742, -0.390, 0.006),
], steps=26)

SANCTUM_CURL_OUTER = _sample_bezier_curve([
    (0.735, -0.455, 0.018),
    (0.825, -0.415, 0.015),
    (0.845, -0.355, 0.010),
    (0.798, -0.345, 0.005),
], steps=16)

# Rear lotus petals cupping behind the lower sphere (painted into Back layer):
SANCTUM_REAR_INNER = _sample_bezier_curve([
    (0.240, -0.860, 0.072),
    (0.380, -0.760, 0.068),
    (0.455, -0.605, 0.038),
    (0.440, -0.495, 0.006),
], steps=20)

SANCTUM_REAR_OUTER = _sample_bezier_curve([
    (0.460, -0.840, 0.064),
    (0.675, -0.700, 0.056),
    (0.805, -0.470, 0.034),
    (0.785, -0.315, 0.006),
], steps=24)


def _sanctum_front_sdf(u: float, v: float) -> tuple[float, str, float, float]:
    au = abs(u)
    sd_pc, pct, pcc, _ = _eval_spline(au, v, SANCTUM_PETAL_CENTER)
    sd_pm, pmt, pmc, _ = _eval_spline(au, v, SANCTUM_PETAL_MID)
    sd_po, pot, poc, _ = _eval_spline(au, v, SANCTUM_PETAL_OUTER)
    sd_curl, _, _, _ = _eval_spline(au, v, SANCTUM_CURL_OUTER)

    # Front sculpted rim of the 3/4 altar dish (only the lower/front lip v <= DISH_CY + 0.015).
    sd_dish_edge = abs(_sd_ellipse_approx(u, v, 0.0, DISH_CY, DISH_RX, DISH_RY)) - 0.022
    if v > DISH_CY + 0.012:
        sd_dish_edge = max(sd_dish_edge, (v - (DISH_CY + 0.012)) * 1.4)

    # Tiered carved basalt pedestal foot under the lotus bowl (v in [-1.072, -0.95]).
    sd_plinth = _sd_box(au, v, 0.0, -1.015, 0.360, 0.054, 0.020)
    sd_foot = _sd_box(au, v, 0.0, -1.055, 0.455, 0.020, 0.010)
    sd_finial = _sd_diamond(au, v, 0.0, -1.058, 0.048, 0.036, 0.005)
    sd_base = smin(smin(sd_plinth, sd_foot, 0.014), sd_finial, 0.010)

    # Central recessed teardrop gemstone socket in the center front lotus petal.
    sd_gem = _sd_diamond(au, v, 0.0, -0.892, 0.040, 0.056, 0.005)
    sd_bezel = _sd_diamond(au, v, 0.0, -0.892, 0.062, 0.078, 0.008)

    sd_petals = min(sd_pc, sd_pm, sd_po, sd_curl)
    sd_all = min(smin(sd_base, sd_dish_edge, 0.018), sd_petals)

    if sd_gem < 0.0:
        return sd_all, "gem", pct, pcc
    if sd_bezel < 0.0:
        return sd_all, "gold", pct, pcc
    if sd_curl < 0.003:
        return sd_all, "gold", pot, poc

    # Crisp antique-gold leaf borders & raised central midribs on each lotus petal!
    if sd_pc < 0.002:
        if abs(pcc) > 0.72 or (abs(pcc) < 0.16 and pct > 0.25) or pct > 0.86:
            return sd_all, "gold", pct, pcc
        return sd_all, "petal", pct, pcc
    if sd_pm < 0.002:
        if abs(pmc) > 0.72 or (abs(pmc) < 0.15 and pmt > 0.15) or pmt > 0.84:
            return sd_all, "gold", pmt, pmc
        return sd_all, "petal", pmt, pmc
    if sd_po < 0.002:
        if abs(poc) > 0.68 or (abs(poc) < 0.16 and pot > 0.15) or pot > 0.82:
            return sd_all, "gold", pot, poc
        return sd_all, "petal", pot, poc

    # Gold rim band along front altar dish lip & stepped pedestal molding.
    if sd_dish_edge < 0.003:
        return sd_all, "gold", 0.5, 0.0
    if sd_finial < 0.003 or (abs(v - (-1.055)) < 0.014 and au < 0.455):
        return sd_all, "gold", 0.5, 0.0
    return sd_all, "basalt", 0.0, 0.0


def _sanctum_height(u: float, v: float) -> float:
    au = abs(u)
    sd_pc, pct, pcc, _ = _eval_spline(au, v, SANCTUM_PETAL_CENTER)
    sd_pm, pmt, pmc, _ = _eval_spline(au, v, SANCTUM_PETAL_MID)
    sd_po, pot, poc, _ = _eval_spline(au, v, SANCTUM_PETAL_OUTER)
    sd_curl, _, _, _ = _eval_spline(au, v, SANCTUM_CURL_OUTER)
    sd_dish_edge = abs(_sd_ellipse_approx(u, v, 0.0, DISH_CY, DISH_RX, DISH_RY)) - 0.022
    if v > DISH_CY + 0.012:
        sd_dish_edge = max(sd_dish_edge, (v - (DISH_CY + 0.012)) * 1.4)
    sd_plinth = _sd_box(au, v, 0.0, -1.015, 0.360, 0.054, 0.020)
    sd_foot = _sd_box(au, v, 0.0, -1.055, 0.455, 0.020, 0.010)
    sd_finial = _sd_diamond(au, v, 0.0, -1.058, 0.048, 0.036, 0.005)
    sd_bezel = _sd_diamond(au, v, 0.0, -0.892, 0.062, 0.078, 0.008)
    sd_gem = _sd_diamond(au, v, 0.0, -0.892, 0.040, 0.056, 0.005)

    # Pedestal plinth with carved stone flutes.
    h = _bevel_dome(smin(smin(sd_plinth, sd_foot, 0.014), sd_finial, 0.010), 0.036) * 0.60
    h += 0.05 * math.cos(u * 36.0) * smooth(-1.045, -0.995, v) * smooth(-0.955, -0.985, v)
    h += 0.14 * math.exp(-math.pow((v - (-1.055)) / 0.012, 2))
    if sd_dish_edge < 0.004:
        h = max(h, _bevel_dome(sd_dish_edge, 0.016) * 0.78)

    # Overlapping lotus petals layered front-to-back with raised midribs & cupped curvature!
    if sd_po < 0.005:
        midrib = math.exp(-math.pow(poc / 0.22, 2)) * 0.22
        edge_lip = smooth(0.60, 0.86, abs(poc)) * 0.14
        h = max(h, _bevel_dome(sd_po, 0.026) * 0.74 + midrib + edge_lip)
    if sd_curl < 0.004:
        h = max(h, _bevel_dome(sd_curl, 0.014) * 0.78)
    if sd_pm < 0.005:
        midrib = math.exp(-math.pow(pmc / 0.20, 2)) * 0.24
        edge_lip = smooth(0.62, 0.88, abs(pmc)) * 0.15
        h = max(h, _bevel_dome(sd_pm, 0.030) * 0.82 + midrib + edge_lip + 0.05)
    if sd_pc < 0.005:
        midrib = math.exp(-math.pow(pcc / 0.18, 2)) * 0.26
        edge_lip = smooth(0.64, 0.88, abs(pcc)) * 0.16
        h = max(h, _bevel_dome(sd_pc, 0.034) * 0.90 + midrib + edge_lip + 0.10)
    if sd_bezel < 0.004:
        h_bz = _bevel_dome(sd_bezel, 0.024) * 1.02 + 0.14
        if sd_gem < 0.0:
            fx = abs(u) / 0.040
            fy = abs(v - (-0.892)) / 0.056
            h_bz = 0.88 + clamp(1.0 - max(fx, fy) * 0.6 - (fx + fy) * 0.4) * 0.36
        h = max(h, h_bz)
    return h


def paint_sanctum(out_dir: str) -> None:
    buf_back = bytearray(W * H * 4)
    buf_front = bytearray(W * H * 4)
    buf_liquid = bytearray(W * H * 4)
    buf_accent = bytearray(W * H * 4)
    buf_sheen = bytearray(W * H * 4)

    basalt_d, basalt_m, basalt_h = (0.045, 0.048, 0.062), (0.13, 0.14, 0.175), (0.34, 0.37, 0.44)
    petal_d, petal_m, petal_h = (0.055, 0.050, 0.072), (0.16, 0.155, 0.205), (0.44, 0.43, 0.52)
    gold_d, gold_m, gold_h = (0.25, 0.16, 0.045), (0.68, 0.50, 0.165), (1.00, 0.88, 0.48)
    gem_d, gem_m, gem_h = (0.02, 0.02, 0.03), (0.06, 0.065, 0.085), (0.20, 0.23, 0.28)

    for y in range(H):
        v = V_MAX - (y + 0.5) * (V_MAX - V_MIN) / H
        for x in range(W):
            u = U_MIN + (x + 0.5) * (U_MAX - U_MIN) / W
            idx = (y * W + x) * 4
            au = abs(u)
            d = math.hypot(u, v)

            # --- BACK LAYER: ground shadow + rear sculpted lotus petals + open concave basalt dish floor ---
            back_rgba = (0.0, 0.0, 0.0, 0.0)
            sh_ell = math.hypot(u / 0.54, (v - (-1.084)) / 0.042)
            g_sh = 0.50 * math.exp(-2.6 * sh_ell * sh_ell)
            if g_sh > 1e-4:
                back_rgba = _over(back_rgba, (0.01, 0.01, 0.02, g_sh))

            # Rear outer & inner lotus petals peeking cleanly behind the lower sphere.
            for rear_curve, bright in ((SANCTUM_REAR_OUTER, 0.85), (SANCTUM_REAR_INNER, 0.95)):
                sd_r, rt, rcross, _ = _eval_spline(au, v, rear_curve)
                ra = 1.0 - smooth(-PX_DU * 0.75, PX_DU * 0.75, sd_r)
                if ra > 1e-3:
                    edge = smooth(0.60, 0.90, abs(rcross))
                    midrib = math.exp(-math.pow(rcross / 0.22, 2))
                    col = lerp3((0.06, 0.055, 0.075), (0.20, 0.18, 0.22), (0.45 + 0.55 * rt) * bright)
                    col = lerp3(col, (0.56, 0.41, 0.14), max(edge * 0.85, midrib * 0.45, smooth(0.78, 0.98, rt) * 0.75))
                    outline = smooth(-0.009, -0.001, sd_r)
                    col = lerp3(col, (0.02, 0.018, 0.022), outline * 0.80)
                    back_rgba = _over(back_rgba, (col[0], col[1], col[2], ra * 0.96))

            # 3/4 Concave Dark-Basalt Altar Dish Floor (receives the bobbing orb's CastShadow!).
            dish_nx = u / DISH_RX
            dish_ny = (v - DISH_CY) / DISH_RY
            dish_r = math.hypot(dish_nx, dish_ny)
            dish_a = 1.0 - smooth(0.985, 1.015, dish_r)
            if dish_a > 1e-3:
                # Concave lighting: slightly brighter toward back bevel lip, recessed dark well in center.
                bowl = 0.22 + 0.52 * smooth(0.15, 0.96, dish_r) + 0.18 * clamp(dish_ny)
                ang = math.atan2(dish_ny, dish_nx)
                # Subtle carved 8-fold sanctum stone channels & engraved golden inner ring!
                spokes = math.pow(abs(math.cos(4.0 * ang)), 10) * smooth(0.28, 0.45, dish_r) * (1.0 - smooth(0.72, 0.86, dish_r))
                ring_gold = math.exp(-math.pow((dish_r - 0.76) / 0.042, 2))
                outer_rim = smooth(0.86, 0.98, dish_r)
                stone = lerp3((0.06, 0.062, 0.082), (0.21, 0.22, 0.26), clamp(bowl + _grain(u, v) * 0.05))
                stone = lerp3(stone, (0.58, 0.44, 0.16), clamp(ring_gold * 0.72 + outer_rim * 0.78 + spokes * 0.28))
                back_rgba = _over(back_rgba, (stone[0], stone[1], stone[2], dish_a * 0.98))

            _put(buf_back, idx, *back_rgba)

            # --- FRONT LAYER + CONTACT SHADOW ON LOWER GLASS ---
            sd, mat, pt, pcross = _sanctum_front_sdf(u, v)
            front_rgba = (0.0, 0.0, 0.0, 0.0)

            if d < ORB_R + 0.006 and sd > -0.005 and sd < 0.068:
                in_glass = 1.0 - smooth(ORB_R - 0.012, ORB_R + 0.005, d)
                ao_sh = (1.0 - smooth(0.0, 0.060, max(0.0, sd))) * in_glass * 0.46
                if ao_sh > 1e-4:
                    front_rgba = _over(front_rgba, (0.01, 0.01, 0.02, ao_sh))

            body_a = 1.0 - smooth(-PX_DU * 0.75, PX_DU * 0.75, sd)
            sheen_val = 0.0
            if body_a > 1e-3:
                nx, ny, nz = _compute_normal(_sanctum_height, u, v, relief=3.0)
                outline = smooth(-0.010, -0.001, sd)
                if mat == "gold":
                    rgb, sheen_val = _shade_metal(u, v, nx, ny, nz, gold_d, gold_m, gold_h, 0.88, spec_power=12.0, spec_strength=0.66)
                elif mat == "gem":
                    rgb, sheen_val = _shade_metal(u, v, nx, ny, nz, gem_d, gem_m, gem_h, 0.60, spec_power=22.0, spec_strength=0.55)
                elif mat == "petal":
                    rgb, sheen_val = _shade_metal(u, v, nx, ny, nz, petal_d, petal_m, petal_h, 0.82, spec_power=11.0, spec_strength=0.46)
                else:
                    rgb, sheen_val = _shade_metal(u, v, nx, ny, nz, basalt_d, basalt_m, basalt_h, 0.65, spec_power=9.0, spec_strength=0.38)
                rgb = lerp3(rgb, (0.022, 0.018, 0.024), outline * 0.78)
                front_rgba = _over(front_rgba, (rgb[0], rgb[1], rgb[2], body_a))
            _put(buf_front, idx, *front_rgba)

            # --- LIQUID GLOW LAYER: radiant basin pool + central heart gem + inner petal bounce ---
            liq = 0.0
            # Luminous orb glow pooling across the engraved concave basalt altar dish (dims/brightens as orb bobs!).
            if dish_r < 0.96:
                pool = math.exp(-math.pow(dish_r / 0.68, 2)) * 0.56
                ring_glow = math.exp(-math.pow((dish_r - 0.76) / 0.055, 2)) * 0.48
                liq = max(liq, (pool + ring_glow) * (1.0 - body_a * 0.72))
            # Central teardrop gemstone in front lotus crown petal.
            sd_gem = _sd_diamond(au, v, 0.0, -0.892, 0.040, 0.056, 0.005)
            if sd_gem < 0.020:
                facet = 0.62 + 0.38 * (1.0 - smooth(-0.036, -0.004, sd_gem))
                liq = max(liq, (1.0 - smooth(-0.006, 0.008, sd_gem)) * facet)
                liq = max(liq, math.exp(-math.pow(max(0.0, sd_gem) / 0.015, 2)) * 0.28)
            # Soft reflected liquid light along the inner faces of the sculpted petals facing the orb.
            if body_a > 0.05 and d < ORB_R + 0.14:
                inner_b = smooth(ORB_R + 0.12, ORB_R - 0.04, d) * smooth(0.35, -0.60, pcross) * body_a
                liq = max(liq, inner_b * 0.44)
            if liq > 1e-3:
                _put(buf_liquid, idx, 1.0, 1.0, 1.0, clamp(liq))

            # --- ACCENT GLOW LAYER: luminous golden petal midrib veins, dish rune ring & tip sparks ---
            acc = 0.0
            # Glowing gold rune ring etched into the altar dish floor (visible around the bobbing shadow!).
            if dish_r < 0.92 and body_a < 0.6:
                ang = math.atan2(dish_ny, dish_nx)
                rune_seg = 0.45 + 0.55 * math.pow(0.5 + 0.5 * math.cos(ang * 12.0), 3)
                ring_a = math.exp(-math.pow((dish_r - 0.76) / 0.032, 2)) * rune_seg * (1.0 - body_a)
                acc = max(acc, ring_a * 0.72)
            # Delicate glowing filigree veins pulsing up every front lotus petal spine!
            for curve, lo_t, hi_t, weight in (
                (SANCTUM_PETAL_CENTER, 0.45, 0.94, 0.72),
                (SANCTUM_PETAL_MID, 0.18, 0.92, 0.78),
                (SANCTUM_PETAL_OUTER, 0.16, 0.92, 0.76),
            ):
                sd_p, p_t, p_c, _ = _eval_spline(au, v, curve)
                if sd_p < -0.002 and lo_t < p_t < hi_t:
                    vein = math.exp(-math.pow(p_c / 0.13, 2)) * smooth(lo_t, lo_t + 0.10, p_t) * (1.0 - smooth(hi_t - 0.12, hi_t, p_t))
                    acc = max(acc, vein * weight)
            # Crisp upper-left jewel glint + subtle tip ember points on the blooming petals.
            gd = math.hypot(u + 0.008, v - (-0.880))
            if gd < 0.042:
                acc = max(acc, math.exp(-math.pow(gd / 0.010, 2)) * 0.74)
            for tx, ty, tr, ta in (
                (0.000, -0.782, 0.016, 0.72),
                (0.538, -0.688, 0.017, 0.74),
                (0.742, -0.390, 0.018, 0.76),
            ):
                td = math.hypot(au - tx, v - ty)
                acc = max(acc, math.exp(-math.pow(td / tr, 2)) * ta)
            if acc > 1e-3:
                _put(buf_accent, idx, 1.0, 1.0, 1.0, clamp(acc))

            if sheen_val > 1e-3 and body_a > 0.1:
                _put(buf_sheen, idx, 1.0, 0.96, 0.86, clamp(sheen_val * body_a))

    _write_tga(os.path.join(out_dir, "HolderSanctumBack.tga"), buf_back)
    _write_tga(os.path.join(out_dir, "HolderSanctumFront.tga"), buf_front)
    _write_tga(os.path.join(out_dir, "HolderSanctumLiquid.tga"), buf_liquid)
    _write_tga(os.path.join(out_dir, "HolderSanctumAccent.tga"), buf_accent)
    _write_tga(os.path.join(out_dir, "HolderSanctumSheen.tga"), buf_sheen)


# ===========================================================================
# SHARED EFFECT TEXTURES: Light-Driven Cast Shadow & 3D Dust Motes / Wisps
# ===========================================================================
def paint_cast_shadow(out_dir: str) -> None:
    sw, sh = 256, 128
    buf = bytearray(sw * sh * 4)
    for y in range(sh):
        ny = (y + 0.5) / sh * 2.0 - 1.0
        for x in range(sw):
            nx = (x + 0.5) / sw * 2.0 - 1.0
            r2 = nx * nx + ny * ny
            if r2 >= 1.0:
                continue
            r = math.sqrt(r2)
            # Silky edge clamp ensures zero rectangular border even at high alpha.
            edge = 1.0 - smooth(0.76, 1.0, r)
            umbra = 0.76 * math.exp(-3.6 * r2)
            penumbra = 0.36 * math.exp(-1.25 * r2)
            alpha = clamp((umbra + penumbra) * edge)
            _put(buf, (y * sw + x) * 4, 0.01, 0.01, 0.02, alpha)
    _write_tga(os.path.join(out_dir, "OrbCastShadow.tga"), buf, sw, sh)


def paint_dust_sprites(out_dir: str) -> None:
    ps = 64
    buf_mote = bytearray(ps * ps * 4)
    buf_wisp = bytearray(ps * ps * 4)
    for y in range(ps):
        ny = (y + 0.5) / ps * 2.0 - 1.0
        for x in range(ps):
            nx = (x + 0.5) / ps * 2.0 - 1.0
            idx = (y * ps + x) * 4
            r = math.hypot(nx, ny)
            if r < 1.0:
                edge = 1.0 - smooth(0.75, 1.0, r)
                # Luminous dust mote: crisp hot core + soft atmospheric bloom + delicate 4-point sparkle.
                core = math.exp(-math.pow(r / 0.16, 2))
                halo = 0.52 * math.exp(-math.pow(r / 0.44, 2))
                cross = (
                    math.exp(-math.pow(abs(nx) / 0.06, 2)) * math.exp(-math.pow(abs(ny) / 0.48, 2))
                    + math.exp(-math.pow(abs(ny) / 0.06, 2)) * math.exp(-math.pow(abs(nx) / 0.48, 2))
                ) * 0.24
                a_mote = clamp((core + halo + cross) * edge)
                hot = clamp(0.72 + 0.28 * core)
                _put(buf_mote, idx, hot, hot, 1.0, a_mote)

                # Tapered organic dust wisp / drifting ember streak (aligned horizontally for SetRotation).
                ex = nx / 0.86
                ey = ny / 0.28
                er2 = ex * ex + ey * ey
                if er2 < 1.0:
                    w_edge = 1.0 - smooth(0.70, 1.0, math.sqrt(er2))
                    # Slightly brighter head toward +nx, softer wispy tail toward -nx.
                    head = math.exp(-math.pow(math.hypot((nx - 0.18) / 0.28, ny / 0.16), 2))
                    streak = 0.72 * math.exp(-2.4 * er2)
                    a_wisp = clamp((head * 0.88 + streak) * w_edge)
                    w_hot = clamp(0.76 + 0.24 * head)
                    _put(buf_wisp, idx, w_hot, w_hot, 1.0, a_wisp)
    _write_tga(os.path.join(out_dir, "OrbMote.tga"), buf_mote, ps, ps)
    _write_tga(os.path.join(out_dir, "OrbWisp.tga"), buf_wisp, ps, ps)
    paint_tail_sprite(out_dir)


def paint_tail_sprite(out_dir: str) -> None:
    """Paint OrbTail.tga (128x32): silky horizontally-aligned comet-tail ribbon."""
    tw, th = 128, 32
    buf_tail = bytearray(tw * th * 4)
    for y in range(th):
        ny = (y + 0.5) / th * 2.0 - 1.0
        ay = abs(ny)
        y_edge = 1.0 - smooth(0.68, 1.0, ay)
        if y_edge <= 1e-4:
            continue
        for x in range(tw):
            nx = (x + 0.5) / tw * 2.0 - 1.0
            # Asymmetric comet envelope: richest around leading shoulder (nx = +0.55),
            # feathering with zero slope to 0 at both trailing (nx = -1) and leading (nx = +1) ends.
            trail_rise = smooth(-1.0, 0.68, nx)
            if trail_rise <= 1e-5:
                continue
            lead_fade = 1.0 - smooth(0.54, 1.0, nx)
            if lead_fade <= 1e-5:
                continue
            along = math.pow(trail_rise, 0.75) * lead_fade

            # Tapered ribbon thickness: fullest near nx = +0.55, sleek toward trailing end & rounded cap at tip.
            half_w = (0.30 + 0.70 * smooth(-1.0, 0.56, nx)) * (1.0 - 0.34 * smooth(0.58, 1.0, nx))
            ry = ay / max(half_w, 0.12)

            # Bright warm-white inner filament core along ny = 0 enveloped by a soft atmospheric glow.
            core_along = math.pow(smooth(-0.96, 0.66, nx), 1.15) * (1.0 - smooth(0.52, 1.0, nx))
            core = 0.82 * math.exp(-math.pow(ry / 0.16, 2)) * core_along
            sheath = (
                0.52 * math.exp(-math.pow(ry / 0.44, 2))
                + 0.20 * math.exp(-math.pow(ry / 0.82, 2))
            ) * along
            alpha = clamp((1.0 - (1.0 - sheath) * (1.0 - core)) * y_edge)
            if alpha <= 1e-4:
                continue

            hot = clamp(core / 0.82)
            r = 1.0
            g = 0.94 + 0.055 * hot
            b = 0.86 + 0.11 * hot
            _put(buf_tail, (y * tw + x) * 4, r, g, b, alpha)
    _write_tga(os.path.join(out_dir, "OrbTail.tga"), buf_tail, tw, th)


def _parse_args(argv: list[str]) -> tuple[str, bool]:
    out = ""
    dust_only = False
    i = 0
    while i < len(argv):
        tok = argv[i]
        low = tok.lower()
        if low in ("--dust-only", "-dustonly", "/dustonly"):
            dust_only = True
        elif low in ("-out", "/out", "--out"):
            if i + 1 < len(argv):
                i += 1
                out = argv[i]
        elif low.startswith("-out:") or low.startswith("--out:"):
            out = tok.split(":", 1)[1]
        elif not tok.startswith("-") and not out:
            out = tok
        i += 1
    return out, dust_only


def main(argv: list[str]) -> None:
    out, dust_only = _parse_args(argv)
    if not out:
        print("Missing -Out", file=sys.stderr, flush=True)
        raise SystemExit(1)
    os.makedirs(out, exist_ok=True)
    if dust_only:
        paint_dust_sprites(out)
        print(f"Wrote dust sprites (OrbMote, OrbWisp, OrbTail) to {out}")
        return
    paint_chalice(out)
    paint_arcane(out)
    paint_sanctum(out)
    paint_cast_shadow(out)
    paint_dust_sprites(out)
    print(f"Wrote holder TGA layers (Chalice, Arcane, Sanctum) + CastShadow + Dust sprites (incl. OrbTail) to {out}")


if __name__ == "__main__":
    main(sys.argv[1:])
