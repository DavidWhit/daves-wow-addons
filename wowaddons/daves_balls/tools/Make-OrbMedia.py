"""Paint daves_balls orb TGA files. Matches Make-OrbMedia.ps1.

32-bit uncompressed TGA, bottom-left origin. -Out is required.
System.Random(seed) is the .NET Framework generator PowerShell 5.1 uses.
"""

from __future__ import annotations

import math
import os
import struct
import sys

S = 256
ORB_R = 0.80
MBIG = 2147483647
MSEED = 161803398


class DotNetRandom:
    """Windows PowerShell 5.1 / .NET Framework System.Random."""

    def __init__(self, seed):
        self.seed_array = [0] * 56
        subtraction = MBIG if seed == -2147483648 else abs(seed)
        mj = MSEED - subtraction
        self.seed_array[55] = mj
        mk = 1
        for i in range(1, 55):
            ii = (21 * i) % 55
            self.seed_array[ii] = mk
            mk = mj - mk
            if mk < 0:
                mk += MBIG
            mj = self.seed_array[ii]
        for _k in range(1, 5):
            for i in range(1, 56):
                self.seed_array[i] -= self.seed_array[1 + (i + 30) % 55]
                if self.seed_array[i] < 0:
                    self.seed_array[i] += MBIG
        self.inext = 0
        self.inextp = 21

    def _sample(self):
        loc_next = self.inext + 1
        loc_nextp = self.inextp + 1
        if loc_next >= 56:
            loc_next = 1
        if loc_nextp >= 56:
            loc_nextp = 1
        ret = self.seed_array[loc_next] - self.seed_array[loc_nextp]
        if ret == MBIG:
            ret -= 1
        if ret < 0:
            ret += MBIG
        self.seed_array[loc_next] = ret
        self.inext = loc_next
        self.inextp = loc_nextp
        return ret

    def next_double(self):
        return self._sample() * (1.0 / MBIG)


def _channel(component):
    # [byte][int] after clamping. PowerShell [int] rounds halves to even.
    value = round(component * 255.0)
    if value < 0:
        value = 0
    elif value > 255:
        value = 255
    return value


def _byte_min255(value):
    # [byte][math]::Min(255.0, value): half away from the ends via [int]-style rounding.
    value = round(min(255.0, value))
    if value < 0:
        value = 0
    return value


def clamp01(value):
    return max(0.0, min(1.0, value))


def smooth(edge0, edge1, value):
    span = (value - edge0) / (edge1 - edge0)
    k = clamp01(span)
    return k * k * (3.0 - 2.0 * k)


def ell(u, v, cx, cy, rx, ry):
    a = (u - cx) / rx
    b = (v - cy) / ry
    return math.sqrt(a * a + b * b)


def shine(u, v):
    cy = ORB_R * 0.975 - ORB_R / 3.0
    e = ell(u, v, 0.0, cy, ORB_R / 6.0, ORB_R / 10.0)
    return 0.35 * math.exp(-2.2 * e * e)


def flow(u, v, seed, k=1.0):
    x = (u + 1.0) / 2.0 * 2.0 * math.pi * k
    y = (v + 1.0) / 2.0 * 2.0 * math.pi * k
    wx = 0.9 * math.sin(2.0 * y + 1.7 * seed) + 0.5 * math.sin(3.0 * x - 5.0 * y + seed)
    wy = 0.9 * math.sin(2.0 * x + 0.6 + seed) + 0.5 * math.sin(4.0 * x + 3.0 * y + 2.0 * seed)
    px = x + wx
    py = y + wy
    n = 0.50 * math.sin(2.0 * px + 3.0 * py + seed)
    n += 0.35 * math.sin(-3.0 * px + 2.0 * py + 2.1 * seed)
    n += 0.25 * math.sin(5.0 * px - 1.0 * py + 0.4)
    n += 0.15 * math.sin(1.0 * px + 6.0 * py + 3.3 * seed)
    return n / 1.25


def ridge(n, width, power):
    return math.pow(1.0 - min(1.0, abs(n) / width), power)


def _header():
    header = bytearray(18)
    header[2] = 2
    header[12:16] = struct.pack("<HH", S, S)
    header[16] = 32
    header[17] = 8
    return header


def write_tga(path, pixel):
    pixels = bytearray(S * S * 4)
    c = (S - 1) / 2.0
    for y in range(S):
        for x in range(S):
            u = (x - c) / c
            v = (y - c) / c
            red, green, blue, alpha = pixel(u, v)
            i = (y * S + x) * 4
            pixels[i] = _channel(blue)
            pixels[i + 1] = _channel(green)
            pixels[i + 2] = _channel(red)
            pixels[i + 3] = _channel(alpha)
    with open(path, "wb") as handle:
        handle.write(_header())
        handle.write(pixels)


def mask_pixel(u, v):
    d = math.sqrt(u * u + v * v)
    return (1.0, 1.0, 1.0, 1.0 - smooth(ORB_R - 0.01, ORB_R + 0.01, d))


def back_pixel(u, v):
    d = math.sqrt(u * u + v * v)
    return (0.05, 0.05, 0.07, 0.85 * (1.0 - smooth(ORB_R - 0.01, ORB_R + 0.01, d)))


def shade_pixel(u, v):
    d = math.sqrt(u * u + v * v)
    inside = 1.0 - smooth(ORB_R + 0.012, ORB_R + 0.025, d)
    bottom = clamp01((-v / ORB_R + 0.2) / 1.2)
    alpha = clamp01(0.02 + 0.22 * smooth(0.6 * ORB_R, ORB_R, d) + 0.15 * bottom) * inside
    return (0.0, 0.0, 0.0, alpha)


def glass_pixel(u, v):
    d = math.sqrt(u * u + v * v)
    inside = 1.0 - smooth(ORB_R - 0.005, ORB_R + 0.005, d)
    rim = math.pow(smooth(0.82 * ORB_R, ORB_R, d), 2) * 0.22 * inside
    bounce = (1.0 - smooth(0.2, 1.0, ell(u, v, 0.18, -0.52, 0.42, 0.16))) * 0.22 * inside
    ang = math.atan2(v, u) * 180.0 / math.pi
    if ang < 0.0:
        ang += 360.0
    along = smooth(118.0, 140.0, ang) * (1.0 - smooth(195.0, 218.0, ang))
    arcs = 0.0
    for radius, width, weight in ((0.93, 0.010, 0.55), (0.88, 0.006, 0.35), (0.84, 0.004, 0.25)):
        arcs += math.exp(-math.pow((d / ORB_R - radius) / width, 2)) * weight
    light = clamp01(rim + bounce + arcs * along * inside)
    if light <= 0.0:
        return (0.0, 0.0, 0.0, 0.0)
    return (0.92, 0.96, 1.0, light)


def gloss_pixel(u, v):
    d = math.sqrt(u * u + v * v)
    phi = math.atan2(u, v) * 180.0 / math.pi
    span = 90.0
    if abs(phi) >= span:
        return (1.0, 1.0, 1.0, shine(u, v))
    taper = math.cos(phi / span * math.pi / 2.0)
    outer = ORB_R * 0.975
    thick = ORB_R * 0.04 * taper
    mid = outer - thick / 2.0
    band = smooth(outer - thick - 0.006, outer - thick + 0.003, d) * (
        1.0 - smooth(outer - 0.004, outer + 0.003, d)
    )
    bloom = math.exp(-math.pow((d - mid) / 0.035, 2)) * 0.3
    alpha = clamp01((band + bloom) * math.pow(taper, 0.35) + shine(u, v))
    return (1.0, 1.0, 1.0, alpha)


def veins_pixel(u, v):
    a1 = ridge(flow(u, v, 1.0, 1.0), 0.08, 2.0)
    a2 = ridge(flow(u, v, 3.7, 2.0), 0.05, 2.0)
    hot = a1 * a1
    alpha = clamp01(a1 * 0.95 + a2 * 0.35)
    white = clamp01(0.55 + 0.45 * hot)
    return (white, white, white, alpha)


def cloud_pixel(u, v):
    n = flow(u, v, 2.3)
    m = flow(u, v, 4.1, 2.0)
    alpha = clamp01(smooth(-0.1, 0.9, n) * 0.55 + smooth(0.2, 1.0, m) * 0.25)
    return (1.0, 1.0, 1.0, alpha)


def core_pixel(u, v):
    d = math.sqrt(u * u + v * v)
    ang = math.atan2(v, u)
    rays = math.pow(abs(math.sin(3.5 * ang + 0.4)), 12) + 0.6 * math.pow(abs(math.sin(5.0 * ang + 1.3)), 16)
    alpha = clamp01(
        math.exp(-math.pow(d / 0.10, 2))
        + 0.5 * math.exp(-math.pow(d / 0.40, 2))
        + 0.45 * rays * math.exp(-d / 0.28)
    )
    return (1.0, 1.0, 1.0, alpha)


def halo_pixel(u, v):
    d = math.sqrt(u * u + v * v)
    outside = smooth(ORB_R - 0.02, ORB_R + 0.01, d)
    alpha = outside * math.exp(-math.pow((d - ORB_R) / 0.07, 2)) * 0.6
    return (1.0, 1.0, 1.0, alpha)


def wave_pixel(u, v):
    x = (u + 1.0) / 2.0
    edge = 0.15 * math.sin(x * 4.0 * math.pi) + 0.04 * math.sin(x * 8.0 * math.pi + 0.7)
    dy = v - edge
    foam = math.exp(-math.pow(dy / 0.05, 2))
    return (1.0, 1.0, 1.0, foam * 0.9)


def level_pixel(_u, v):
    return (1.0, 1.0, 1.0, 1.0 - smooth(-0.008, 0.008, v))


def write_sparks(path):
    rng = DotNetRandom(7)
    image = [0.0] * (S * S)
    for _i in range(160):
        cx = rng.next_double() * S
        cy = rng.next_double() * S
        rad = 0.6 + 1.4 * math.pow(rng.next_double(), 3)
        bright = 0.4 + 0.6 * rng.next_double()
        reach = int(math.ceil(rad * 2.5))
        fx = math.floor(cx)
        fy = math.floor(cy)
        for dy in range(-reach, reach + 1):
            for dx in range(-reach, reach + 1):
                px = ((int(fx) + dx) % S + S) % S
                py = ((int(fy) + dy) % S + S) % S
                ex = fx + dx + 0.5 - cx
                ey = fy + dy + 0.5 - cy
                val = bright * math.exp(-(ex * ex + ey * ey) / (rad * rad))
                j = py * S + px
                if val > image[j]:
                    image[j] = val
    pixels = bytearray(S * S * 4)
    for j, value in enumerate(image):
        pixels[j * 4] = 255
        pixels[j * 4 + 1] = 255
        pixels[j * 4 + 2] = 255
        pixels[j * 4 + 3] = _byte_min255(value * 255.0)
    with open(path, "wb") as handle:
        handle.write(_header())
        handle.write(pixels)


def _out_dir(argv):
    if not argv:
        return ""
    if argv[0].lower() in ("-out", "/out"):
        return argv[1] if len(argv) > 1 else ""
    if argv[0].lower().startswith("-out:"):
        return argv[0].split(":", 1)[1]
    if argv[0].startswith("-"):
        return ""
    return argv[0]


def main(argv):
    out = _out_dir(argv)
    if not out:
        print("Missing -Out", file=sys.stderr, flush=True)
        raise SystemExit(1)
    os.makedirs(out, exist_ok=True)
    write_tga(os.path.join(out, "OrbMask.tga"), mask_pixel)
    write_tga(os.path.join(out, "OrbBack.tga"), back_pixel)
    write_tga(os.path.join(out, "OrbShade.tga"), shade_pixel)
    write_tga(os.path.join(out, "OrbGlass.tga"), glass_pixel)
    write_tga(os.path.join(out, "OrbGloss.tga"), gloss_pixel)
    write_tga(os.path.join(out, "OrbVeins.tga"), veins_pixel)
    write_tga(os.path.join(out, "OrbCloud.tga"), cloud_pixel)
    write_tga(os.path.join(out, "OrbCore.tga"), core_pixel)
    write_tga(os.path.join(out, "OrbHalo.tga"), halo_pixel)
    write_sparks(os.path.join(out, "OrbSparks.tga"))
    write_tga(os.path.join(out, "OrbWave.tga"), wave_pixel)
    write_tga(os.path.join(out, "OrbLevel.tga"), level_pixel)


if __name__ == "__main__":
    main(sys.argv[1:])
