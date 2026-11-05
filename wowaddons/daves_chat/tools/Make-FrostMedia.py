"""Generate frosted-glass TGA textures for daves_chat Faint mode.

Writes uncompressed 32-bit top-left-origin neutral-luminance TGA textures into Media/
(tinted in-game via SetVertexColor so any color-picker tint reproduces accurately):
  - frost_glass.tga (64x64): 9-slice rounded frosted-glass shell (16px slice margins)
    with SDF anti-aliased 5px corners, subsurface edge scatter, and top-left specular catch-light.
  - frost_grain.tga (128x128): seamlessly tileable multi-scale cloudy diffusion + fine
    sandblasted etched-glass micro-grain.
"""

from __future__ import annotations

import math
import os
import random
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
        t = 1.0
    return t * t * (3.0 - 2.0 * t)


def write_tga(path: str, width: int, height: int, bgra: bytearray) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # 18-byte uncompressed 32-bit BGRA header, top-left origin (0x28 = 0x20 | 8 alpha bits).
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    with open(path, "wb") as f:
        f.write(header)
        f.write(bgra)


def build_frost_glass(size: int = 64) -> bytearray:
    """64x64 9-slice rounded frosted-glass pane (slice margins: 16, 16, 16, 16)."""
    inset = 1.0
    radius = 5.0
    half = size * 0.5
    # Half-extents of the inner corner-center box; 1 + 5 = 6 <= 16 so every curved/lit feature
    # stays strictly inside the 16px 9-slice margins and the 32x32 center is 100% uniform.
    # At inset (2, -2) to (-2, 2), pixel (2.5, 2.5) is hypot(3.5, 3.5) = 4.95 <= 5.0 (inside corner).
    bx = half - inset - radius
    by = half - inset - radius

    # Light coming from top-left (-0.65, -0.76) in top-left screen coordinates.
    lx, ly = -0.65, -0.76
    buf = bytearray(size * size * 4)
    idx = 0

    for y in range(size):
        py = (y + 0.5) - half
        ay = abs(py) - by
        for x in range(size):
            px = (x + 0.5) - half
            ax = abs(px) - bx

            ox = ax if ax > 0.0 else 0.0
            oy = ay if ay > 0.0 else 0.0
            out_len = math.hypot(ox, oy)
            in_dist = min(max(ax, ay), 0.0)
            # Signed distance to rounded rect border (negative inside, 0 on rim, positive outside).
            sdf = out_len + in_dist - radius

            # Outward normal of the SDF, invariant along the 4 straight 9-slice stretch strips.
            if out_len > 1e-6:
                nx = math.copysign(ox / out_len, px)
                ny = math.copysign(oy / out_len, py)
            elif ax > ay:
                nx = 1.0 if px >= 0.0 else -1.0
                ny = 0.0
            else:
                nx = 0.0
                ny = 1.0 if py >= 0.0 else -1.0

            # Anti-aliased outer coverage with a gentle ~1.2px feathered glass edge.
            cov = 1.0 - _smoothstep(-0.55, 0.85, sdf)
            if cov <= 0.001:
                buf[idx : idx + 4] = b"\x00\x00\x00\x00"
                idx += 4
                continue

            depth = max(0.0, -sdf)  # distance inward from the glass edge

            # Subsurface edge scatter (within 6.5px of rim, fully settled well before 16px slice line).
            scatter = 1.0 - _smoothstep(0.0, 6.5, depth)
            # Crisp 1.3px bevel catch-light right along the glass rim.
            rim = math.exp(-((sdf + 0.45) / 0.95) ** 2)

            # Directional catch-light: brightest on top-left rim, still softly present on bottom-right.
            facing = 0.5 + 0.5 * (nx * lx + ny * ly)  # [0..1]
            rim_strength = rim * (0.35 + 0.65 * facing)

            # Neutral white/silver frosted-glass luminance so SetVertexColor tints true to any
            # ColorPickerFrame RGB choice (default {0.82, 0.87, 0.94} gives cool frosted glass).
            lum = _clamp_byte(228.0 + 10.0 * scatter + 17.0 * rim_strength)

            # Interior alpha 210/255 (0.824), rising to 255 on the top-left specular rim.
            base_a = 210.0 + 14.0 * scatter + 35.0 * rim_strength
            a = min(255.0, base_a) * cov

            buf[idx] = lum
            buf[idx + 1] = lum
            buf[idx + 2] = lum
            buf[idx + 3] = _clamp_byte(a)
            idx += 4

    return buf


def _periodic_blur(grid: list[list[float]], size: int, sigma: float) -> list[list[float]]:
    if sigma <= 0.0:
        return [row[:] for row in grid]
    rad = max(1, min(size // 2, int(math.ceil(sigma * 3.0))))
    weights = [math.exp(-0.5 * (k / sigma) ** 2) for k in range(-rad, rad + 1)]
    wsum = sum(weights)
    weights = [w / wsum for w in weights]

    horiz = [[0.0] * size for _ in range(size)]
    for y in range(size):
        row = grid[y]
        out_row = horiz[y]
        for x in range(size):
            acc = 0.0
            for k, w in enumerate(weights, start=-rad):
                acc += row[(x + k) % size] * w
            out_row[x] = acc

    out = [[0.0] * size for _ in range(size)]
    for y in range(size):
        out_row = out[y]
        for x in range(size):
            acc = 0.0
            for k, w in enumerate(weights, start=-rad):
                acc += horiz[(y + k) % size][x] * w
            out_row[x] = acc
    return out


def _normalize(grid: list[list[float]], size: int) -> list[list[float]]:
    vals = [v for row in grid for v in row]
    lo, hi = min(vals), max(vals)
    span = (hi - lo) if hi > lo else 1.0
    return [[(v - lo) / span for v in row] for row in grid]


def build_frost_grain(size: int = 128, seed: int = 20261101) -> bytearray:
    """128x128 seamlessly tileable cloudy blur diffusion + fine sandblasted frost grain."""
    rng = random.Random(seed)
    n_broad = [[rng.random() for _ in range(size)] for _ in range(size)]
    n_med = [[rng.random() for _ in range(size)] for _ in range(size)]
    n_fine = [[rng.random() for _ in range(size)] for _ in range(size)]
    n_etch = [[rng.random() for _ in range(size)] for _ in range(size)]

    cloud_broad = _normalize(_periodic_blur(n_broad, size, 15.0), size)
    cloud_med = _normalize(_periodic_blur(n_med, size, 5.0), size)
    grain_soft = _normalize(_periodic_blur(n_fine, size, 0.85), size)

    buf = bytearray(size * size * 4)
    idx = 0
    for y in range(size):
        for x in range(size):
            # Out-of-focus cloudy diffusion (72%) + fine etched sandblasted crystal grain (28%).
            cloud = 0.60 * cloud_broad[y][x] + 0.40 * cloud_med[y][x]
            etch = 0.62 * grain_soft[y][x] + 0.38 * n_etch[y][x]
            v = 0.70 * cloud + 0.30 * etch  # [0..1]

            lum = _clamp_byte(226.0 + 29.0 * v)
            a = 6.0 + 96.0 * v  # zero-pedestal [6..102] / 255 translucent frost modulation

            buf[idx] = lum
            buf[idx + 1] = lum
            buf[idx + 2] = lum
            buf[idx + 3] = _clamp_byte(a)
            idx += 4

    return buf


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    media_dir = os.path.normpath(os.path.join(here, "..", "Media"))
    glass_path = os.path.join(media_dir, "frost_glass.tga")
    grain_path = os.path.join(media_dir, "frost_grain.tga")

    glass = build_frost_glass(64)
    grain = build_frost_grain(128)
    write_tga(glass_path, 64, 64, glass)
    write_tga(grain_path, 128, 128, grain)
    print(f"Wrote {glass_path} ({len(glass) + 18} bytes)")
    print(f"Wrote {grain_path} ({len(grain) + 18} bytes)")


if __name__ == "__main__":
    main()
