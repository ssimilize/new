"""Procedural particle sprites for Monster Ranch Idle (bake-off entrant: PROCEDURAL).

Every sprite is drawn purely in code with numpy: signed-distance shapes, analytic gradients,
home-made value/fbm noise and FFT gaussian blur for glow. Drawing happens at 4x (1024 px) as a
pair of fields (L = luminance/shading, A = alpha); the fields are premultiplied, downsampled with
Lanczos to 256 px, un-premultiplied and the fully transparent pixels get their colour bled in from
the neighbours so Roblox's bilinear sampling never pulls in a dark fringe.

Outputs, per sprite:
  <name>.png        tintable version: white / light grey, luminance carries the shading
  <name>_color.png  the same fields mapped through a natural colour ramp
plus contact.png (dark #202028 and light #E8E8E8 strips, with 48 px and 24 px previews).

Usage:  python tools/vfx/procedural.py <outdir>

Adding a sprite = one function returning (L, A) at 1024 px + one colour ramp in RAMPS.
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

import numpy as np
from PIL import Image

HI = 1024          # working resolution
OUT = 256          # delivered resolution
PX = 2.0 / HI      # one working pixel in normalised units

# normalised coordinates: x right, y UP, both in [-1, 1]
_ax = (np.arange(HI) + 0.5) / HI * 2.0 - 1.0
X, Y = np.meshgrid(_ax, -_ax)


# ----------------------------------------------------------------------------- helpers

def clamp01(a):
    return np.clip(a, 0.0, 1.0)


def smoothstep(e0, e1, x):
    t = clamp01((x - e0) / (e1 - e0))
    return t * t * (3.0 - 2.0 * t)


def fill(d, soft=1.2):
    """Anti-aliased coverage from a signed distance (negative inside), soft in working pixels."""
    return clamp01(0.5 - d / (soft * PX))


def gblur(img, sigma_px):
    """Gaussian blur via FFT (zero padded so nothing wraps)."""
    if sigma_px <= 0:
        return img
    pad = int(math.ceil(sigma_px * 3))
    p = np.pad(img, pad)
    h, w = p.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    k = np.exp(-2.0 * (math.pi ** 2) * (sigma_px ** 2) * (fx ** 2 + fy ** 2))
    out = np.fft.irfft2(np.fft.rfft2(p) * k, s=p.shape)
    return out[pad:pad + img.shape[0], pad:pad + img.shape[1]]


def depth(mask, sigma_px):
    """0 at the silhouette, ->1 deep inside; a cheap interior 'distance' for shading."""
    b = gblur(mask, sigma_px)
    return clamp01((b - 0.5) * 2.0) * mask


def over(Lt, At, Lb, Ab):
    """Composite field (Lt, At) over (Lb, Ab); returns un-premultiplied (L, A)."""
    A = At + Ab * (1.0 - At)
    P = Lt * At + Lb * Ab * (1.0 - At)
    L = np.where(A > 1e-6, P / np.maximum(A, 1e-6), Lb)
    return L, A


def rot(x, y, deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return c * x + s * y, -s * x + c * y


def value_noise(freq, seed):
    """Smooth value noise sampled on the working grid, range [0, 1]."""
    rng = np.random.default_rng(seed)
    g = rng.random((freq + 2, freq + 2))
    u = (X + 1.0) * 0.5 * freq
    v = (Y + 1.0) * 0.5 * freq
    i0 = np.floor(u).astype(int)
    j0 = np.floor(v).astype(int)
    fu = u - i0
    fv = v - j0
    fu = fu * fu * fu * (fu * (fu * 6 - 15) + 10)
    fv = fv * fv * fv * (fv * (fv * 6 - 15) + 10)
    a = g[j0, i0]
    b = g[j0, i0 + 1]
    c = g[j0 + 1, i0]
    d = g[j0 + 1, i0 + 1]
    return (a * (1 - fu) + b * fu) * (1 - fv) + (c * (1 - fu) + d * fu) * fv


def fbm(freq, octaves, seed, gain=0.5):
    tot = np.zeros_like(X)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        tot += amp * value_noise(freq * (2 ** o), seed + 101 * o)
        norm += amp
        amp *= gain
    return tot / norm


def seg_dist(px, py, ax, ay, bx, by):
    """Distance to segment a-b, plus the parameter t along it."""
    dx, dy = bx - ax, by - ay
    t = clamp01(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy))
    return np.hypot(px - ax - t * dx, py - ay - t * dy), t


def polygon_sdf(pts, px=None, py=None):
    px = X if px is None else px
    py = Y if py is None else py
    d = np.full(px.shape, 1e9)
    inside = np.zeros(px.shape, bool)
    n = len(pts)
    for i in range(n):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % n]
        dd, _ = seg_dist(px, py, ax, ay, bx, by)
        d = np.minimum(d, dd)
        cond = (ay > py) != (by > py)
        xint = ax + (py - ay) * (bx - ax) / ((by - ay) + 1e-12)
        inside ^= cond & (px < xint)
    return np.where(inside, -d, d)


def tongue_sdf(px, py, base_y, radius, tip_y, lean, wobble=0.0):
    """Teardrop/flame tongue: round bottom (circle), smooth taper to a tip that leans sideways.

    Width above the equator is r*(1-t)^1.5*(1+1.5t): zero slope at the equator (no kink with the
    circle) and a long concave tip.  Returns an approximate signed distance.
    """
    t = clamp01((py - base_y) / (tip_y - base_y))
    centre = lean * t ** 2.2 + wobble * np.sin(math.pi * t)
    lower = np.sqrt(np.maximum(radius ** 2 - (py - base_y) ** 2, 0.0))
    upper = radius * (1 - t) ** 1.5 * (1 + 1.5 * t)
    w = np.where(py < base_y, lower, upper)
    dx = np.abs(px - np.where(py < base_y, 0.0, centre)) - w
    # below the circle / above the tip, fall back to true distance so the field stays sane
    dcirc = np.hypot(px, py - base_y) - radius
    d = np.where(py < base_y, dcirc, dx)
    d = np.where(py > tip_y, np.hypot(px - lean, py - tip_y), d)
    return d


def ramp(L, stops):
    """Map luminance through colour stops [(l, '#rrggbb'), ...] -> float RGB."""
    ls = np.array([s[0] for s in stops])
    cols = np.array([[int(c[i:i + 2], 16) / 255.0 for i in (1, 3, 5)] for _, c in stops])
    out = np.empty(L.shape + (3,))
    for ch in range(3):
        out[..., ch] = np.interp(L, ls, cols[:, ch])
    return out


def border_fade(A):
    """Guarantee a clean transparent border (nothing touches the frame edge)."""
    r = np.maximum(np.abs(X), np.abs(Y))
    return A * (1.0 - smoothstep(0.93, 0.995, r))


# ----------------------------------------------------------------------------- sprites
# each returns (L, A) at HI x HI. L is the tintable luminance (light grey .. white).

def sprite_flame():
    # gentle flicker on the upper half so the silhouette is not a perfect CAD curve
    n = fbm(3, 3, seed=11) - 0.5
    px = X + 0.02 * n * clamp01(Y + 0.2)
    py = Y - 0.04

    def smin(a, b, k):
        h = clamp01(0.5 + 0.5 * (b - a) / k)
        return a * h + b * (1 - h) - k * h * (1 - h)

    main = tongue_sdf(px, py, base_y=-0.40, radius=0.37, tip_y=0.86, lean=0.10, wobble=-0.07)
    lick_l = tongue_sdf(px + 0.29, py, base_y=-0.22, radius=0.17, tip_y=0.40, lean=-0.13, wobble=-0.03)
    lick_r = tongue_sdf(px - 0.27, py, base_y=-0.30, radius=0.14, tip_y=0.18, lean=0.10, wobble=0.02)
    d = smin(smin(main, lick_l, 0.05), lick_r, 0.05)
    body = fill(d)

    # inner core: a smaller tongue sitting low in the body, plus a hot bead at its root
    core_d = tongue_sdf(px - 0.01, py + 0.02, base_y=-0.46, radius=0.22, tip_y=0.34, lean=0.05, wobble=-0.04)
    core = gblur(fill(core_d), 12)
    bead = gblur(fill(tongue_sdf(px, py + 0.05, base_y=-0.48, radius=0.12, tip_y=-0.08, lean=0.0)), 10)

    dep = depth(body, 40)
    L = 0.62 + 0.20 * dep - 0.07 * clamp01(Y - 0.1)      # cooler toward the tips
    L = L + (0.93 - L) * core
    L = L + (1.0 - L) * bead
    L = clamp01(L)

    halo = 0.55 * gblur(body, 38) + 0.25 * gblur(body, 90)
    La, Aa = over(L, body, np.full_like(L, 0.72), clamp01(halo))
    return La, border_fade(Aa)


def sprite_droplet():
    px, py = X, Y + 0.02
    # classic tangent-cone teardrop: circle + straight-ish sides to a slightly rounded tip
    cy, r, tip = -0.30, 0.47, 0.84
    t = clamp01((py - cy) / (tip - cy))
    w_up = r * (1 - t) ** 1.25 * (1 + 1.25 * t)
    w = np.where(py < cy, np.sqrt(np.maximum(r * r - (py - cy) ** 2, 0)), w_up)
    d = np.abs(px) - w
    d = np.where(py < cy, np.hypot(px, py - cy) - r, d)
    d = np.where(py > tip, np.hypot(px, py - tip), d)
    body = fill(d)

    dep = depth(body, 36)
    # volume: darker toward upper-left interior, fresnel-bright rim, bright refraction crescent low-right
    L = 0.60 + 0.08 * (1 - dep)                    # rim brighter (fresnel)
    lx, ly = X - 0.10, Y + 0.44
    cres = body * gblur(fill(np.hypot(lx, ly * 1.25) - 0.30) * (1 - fill(np.hypot(lx - 0.06, (ly - 0.12) * 1.25) - 0.30)), 10)
    L = L + 0.26 * cres
    # a soft inner glow at the belly
    belly = gblur(fill(np.hypot(X * 1.1, (Y + 0.36)) - 0.22), 40)
    L = L + 0.10 * belly
    # edge ring: a crisp slightly-brighter outline sells "glossy" at small sizes
    ring = body * (1 - depth(body, 5))
    L = L + 0.14 * ring

    # specular: a curved streak upper-left + a round dot
    sx, sy = rot(X + 0.20, Y + 0.10, 28)
    streak = fill((np.hypot(sx / 0.075, sy / 0.20) - 1.0) * 0.075)
    dot = fill(np.hypot(X + 0.27, Y + 0.34) - 0.045)
    spec = clamp01(streak + dot)
    L = clamp01(L)
    L = L + (1.0 - L) * spec

    A = body * (0.90 + 0.10 * (1 - dep))
    A = np.maximum(A, spec * body)
    halo = 0.18 * gblur(body, 24)
    La, Aa = over(L, A, np.full_like(L, 0.75), halo)
    return La, border_fade(Aa)


def sprite_leaf():
    ang = 38.0                         # tip points up-right
    s, t = rot(X - 0.07, Y - 0.10, ang)   # s along the leaf, t across
    # rotate so leaf axis is the +y direction: use (t, s) as (across, along)
    u = s / 0.78                        # -1 base .. +1 tip
    mid = 0.07 * (1 - u * u) - 0.03 * u ** 3
    f = np.where(np.abs(u) < 1, (1 - np.clip(u, -1, 1)) ** 1.15 * (1 + np.clip(u, -1, 1)) ** 0.55, 0.0)
    uu = np.linspace(-1, 1, 2001)
    fmax = ((1 - uu) ** 1.15 * (1 + uu) ** 0.55).max()
    W = 0.36
    w = W * f / fmax
    dacross = t - mid
    d = np.abs(dacross) - w
    d = np.where(np.abs(u) >= 1, np.hypot(np.maximum(np.abs(u) - 1, 0) * 0.78, t - mid), d)
    blade = fill(d * 0.8)

    # stem: short tapering capsule continuing past the base with a slight hook
    sd, st = seg_dist(t, s, 0.0, -0.78, -0.05, -0.98)
    stem = fill(sd - (0.028 - 0.012 * st))
    shape = clamp01(blade + stem)

    # two-tone halves: light side / shade side
    side = smoothstep(-0.006, 0.006, dacross)
    L = 0.93 * (1 - side) + 0.74 * side
    dep = depth(blade, 30)
    L = L - 0.05 * dep * side + 0.03 * (1 - dep) * (1 - side)
    # darker at the base, lighter toward the tip
    L = L - 0.06 * clamp01(-u) + 0.03 * clamp01(u)
    # side veins: forward-swept lines, faint, fading toward the edge
    nrm = np.abs(dacross) / np.maximum(w, 1e-3)
    phase = (u - 0.55 * nrm) * 5.0
    vein = smoothstep(0.10, 0.0, np.abs(phase - np.round(phase))) * clamp01(1 - nrm) * (np.abs(u) < 0.82)
    L = L + np.where(side > 0.5, 0.07, -0.08) * vein * blade
    # midrib: bright tapering line
    rib_w = 0.016 * clamp01(0.85 - u) / 0.85 + 0.002
    rib = fill(np.abs(dacross) - rib_w) * (u > -1.02) * (u < 0.88)
    L = L + (1.0 - L) * rib * 0.9
    # glossy light patch on the light half
    gl = gblur(fill(np.hypot((t - mid + 0.14) / 0.08, (s - 0.10) / 0.28) - 1.0), 18) * (1 - side)
    L = L + 0.05 * gl
    # stem shade
    L = np.where(stem > blade, 0.78, L)
    L = clamp01(L)
    A = shape
    return L, border_fade(A)


def sprite_bolt():
    pts = [(0.12, 0.92), (0.58, 0.92), (0.20, 0.17), (0.52, 0.17), (-0.30, -0.94),
           (-0.03, -0.10), (-0.40, -0.10)]
    cx = (0.58 + -0.40) / 2
    cy = (0.92 + -0.94) / 2
    sc = 0.83
    pts = [((x - cx) * sc, (y - cy) * sc - 0.05) for x, y in pts]
    d = polygon_sdf(pts)
    # slight corner rounding: erode then dilate
    r = 0.012
    body = fill(d)
    core = gblur(fill(d + 0.068), 8)
    edge_dep = depth(body, 10)
    L = 0.80 + 0.08 * edge_dep
    L = L + (1.0 - L) * core
    L = clamp01(L)
    halo = 0.65 * gblur(body, 14) + 0.35 * gblur(body, 55)
    La, Aa = over(L, body, np.full_like(L, 0.82), clamp01(halo))
    return La, border_fade(Aa)


def sprite_star():
    p = 0.52

    def astroid(a, b, px=X, py=Y):
        f = (np.abs(px) / a) ** p + (np.abs(py) / b) ** p
        gy, gx = np.gradient(f, PX)
        g = np.hypot(gx, gy) + 1e-6
        return (f - 1.0) / g

    main = fill(astroid(0.62, 0.80))
    dx, dy = rot(X, Y, 45)
    diag = fill(astroid(0.30, 0.30, dx, dy))
    shape = clamp01(main + diag * 0.9)
    f = (np.abs(X) / 0.62) ** p + (np.abs(Y) / 0.80) ** p
    L = 0.80 + 0.20 * clamp01(1.2 - f) ** 1.5
    L = np.where(main >= diag, L, 0.86)
    core = np.exp(-(X * X + Y * Y) / (2 * 0.09 ** 2))
    L = clamp01(L + (1 - L) * core)
    A = clamp01(shape)
    halo = 0.55 * np.exp(-(X * X + Y * Y) / (2 * 0.20 ** 2)) + 0.35 * gblur(main, 22) + 0.15 * gblur(main, 60)
    La, Aa = over(L, A, np.full_like(L, 0.88), clamp01(halo))
    return La, border_fade(Aa)


def sprite_wisp():
    # a curling smoke ribbon: gaussians laid densely along an inward spiral, domain-warped with fbm
    f32 = np.float32
    wx = (fbm(3, 4, seed=21) - 0.5).astype(f32)
    wy = (fbm(3, 4, seed=37) - 0.5).astype(f32)
    px = (X + 0.14 * wx).astype(f32)
    py = (Y + 0.14 * wy).astype(f32)
    C = (0.04, 0.15)
    dens = np.zeros_like(px)
    ridge = np.zeros_like(px)
    n = 260
    for i in range(n):
        s = i / (n - 1)
        th = math.radians(205 + 450 * s)
        R = 0.50 * (1 - s) ** 0.85 + 0.06
        bx = C[0] + R * math.cos(th)
        by = C[1] + R * math.sin(th) * 0.95
        rad = 0.25 * (1 - s) ** 0.8 + 0.04
        d2 = (px - f32(bx)) ** 2 + (py - f32(by)) ** 2
        dens += np.exp(d2 * f32(-1.0 / (2 * rad * rad))) * f32(9.0 / n * (0.6 + 0.4 * (1 - s)))
        ridge = np.maximum(ridge, np.exp(d2 * f32(-1.0 / (2 * (rad * 0.5) ** 2))) * f32(0.8 + 0.2 * s))
    # two small detached puffs trailing off the tail
    for (bx, by, rad) in [(-0.63, -0.58, 0.08), (-0.78, -0.30, 0.048)]:
        d2 = (px - bx) ** 2 + (py - by) ** 2
        dens += 1.6 * np.exp(-d2 / (2 * rad * rad))
        ridge = np.maximum(ridge, 0.55 * np.exp(-d2 / (2 * (rad * 1.3) ** 2)))
    texture = fbm(6, 4, seed=5)
    dens = dens * (0.8 + 0.4 * texture)
    A = smoothstep(0.15, 1.0, dens)
    A = gblur(A, 7)
    L = 0.72 + 0.28 * clamp01(ridge) * (0.85 + 0.3 * texture)
    L = clamp01(L)
    halo = 0.22 * gblur(A, 40)
    La, Aa = over(L, clamp01(A) * 0.95, np.full_like(L, 0.74), halo)
    return La, border_fade(Aa)


def sprite_glow():
    # soft round radial orb, ALL glow (no outline): white, alpha = a smooth falloff that reaches 0
    # at r = 0.95 (the visible orb, alpha > 2%, spans ~80% of the canvas) plus a denser core
    r = np.sqrt(X * X + Y * Y)
    t = clamp01(1.0 - r / 0.95)
    core = np.exp(-(r / 0.22) ** 2)
    A = clamp01(0.7 * t * t + 0.3 * core * t)
    L = np.ones_like(A)
    return L, border_fade(A)


SPRITES = {
    "flame": sprite_flame,
    "droplet": sprite_droplet,
    "leaf": sprite_leaf,
    "bolt": sprite_bolt,
    "star": sprite_star,
    "wisp": sprite_wisp,
    "glow": sprite_glow,
}

RAMPS = {
    "flame": [(0.55, "#D2281A"), (0.66, "#FF5A14"), (0.78, "#FF9A22"), (0.90, "#FFD24A"), (1.0, "#FFF8D8")],
    "droplet": [(0.55, "#1450C8"), (0.66, "#2E86F0"), (0.82, "#6CC4FF"), (0.93, "#BDE9FF"), (1.0, "#FFFFFF")],
    "leaf": [(0.65, "#22802E"), (0.76, "#3DA83A"), (0.88, "#6CCB45"), (0.95, "#A4E36A"), (1.0, "#E0F9B0")],
    "bolt": [(0.70, "#FF9A10"), (0.82, "#FFC21E"), (0.92, "#FFE650"), (1.0, "#FFF8C4")],
    "star": [(0.78, "#FFB524"), (0.88, "#FFD660"), (0.95, "#FFF0B0"), (1.0, "#FFFFF6")],
    "wisp": [(0.66, "#5A23A8"), (0.76, "#8A48E8"), (0.86, "#B98AFF"), (0.96, "#E6D4FF"), (1.0, "#F8F0FF")],
    "glow": [(0.0, "#FFFFFF"), (1.0, "#FFFFFF")],  # white by design: tinted in the engine
}


# ----------------------------------------------------------------------------- output

def downsample(rgb, A, size=OUT):
    """Premultiply, Lanczos-downsample, un-premultiply, then bleed colour into clear pixels."""
    def rs(ch):
        return np.asarray(Image.fromarray(ch.astype(np.float32), "F").resize((size, size), Image.LANCZOS))
    a = clamp01(rs(A))
    prem = [clamp01(rs(rgb[..., c] * A)) for c in range(3)]
    a_s = np.where(a < 1.0 / 512, 0.0, a)
    out = np.zeros((size, size, 3))
    # colour bleed for (near-)transparent pixels: normalised convolution of premultiplied colour
    ab = gblur(a, 6.0) + 1e-9
    for c in range(3):
        col = np.where(a > 1e-4, prem[c] / np.maximum(a, 1e-4), 0.0)
        bleed = gblur(prem[c], 6.0) / ab
        wide = gblur(prem[c], 40.0) / (gblur(a, 40.0) + 1e-9)
        bleed = np.where(ab > 1e-4, bleed, wide)
        mix = smoothstep(0.0, 0.08, a)
        out[..., c] = clamp01(col * mix + bleed * (1 - mix))
    return out, a_s


def to_image(rgb, a):
    arr = np.dstack([rgb, a[..., None]])
    return Image.fromarray(np.round(clamp01(arr) * 255).astype(np.uint8), "RGBA")


def contact_sheet(images, path):
    names = list(images)
    cell, pad = 256, 12
    small = 64
    cols = len(names)
    width = cols * (cell + pad) + pad
    rows_per_strip = [("grey", cell), ("color", cell), ("small", small)]
    strip_h = sum(h + pad for _, h in rows_per_strip) + pad
    sheet = Image.new("RGBA", (width, strip_h * 2), (0, 0, 0, 255))
    for si, bg in enumerate([(0x20, 0x20, 0x28, 255), (0xE8, 0xE8, 0xE8, 255)]):
        strip = Image.new("RGBA", (width, strip_h), bg)
        y = pad
        for kind, h in rows_per_strip:
            for ci, n in enumerate(names):
                x = pad + ci * (cell + pad)
                if kind == "small":
                    for k, sz in enumerate((48, 24)):
                        im = images[n]["color"].resize((sz, sz), Image.LANCZOS)
                        strip.alpha_composite(im, (x + k * 60 + 20, y + (small - sz) // 2))
                        im = images[n]["grey"].resize((sz, sz), Image.LANCZOS)
                        strip.alpha_composite(im, (x + 150 + k * 60, y + (small - sz) // 2))
                else:
                    strip.alpha_composite(images[n][kind], (x, y))
            y += h + pad
        sheet.paste(strip, (0, si * strip_h))
    sheet.convert("RGB").save(path)


def main(outdir, only=None):
    os.makedirs(outdir, exist_ok=True)
    timings = {}
    images = {}
    for name, fn in SPRITES.items():
        if only and name not in only:
            continue
        t0 = time.perf_counter()
        L, A = fn()
        grey = np.repeat(L[..., None], 3, axis=2)
        col = ramp(L, RAMPS[name])
        g_rgb, g_a = downsample(grey, A)
        c_rgb, c_a = downsample(col, A)
        gi, ci = to_image(g_rgb, g_a), to_image(c_rgb, c_a)
        gi.save(os.path.join(outdir, f"{name}.png"))
        ci.save(os.path.join(outdir, f"{name}_color.png"))
        images[name] = {"grey": gi, "color": ci}
        timings[name] = round(time.perf_counter() - t0, 2)
        print(f"{name}: {timings[name]}s")
    if not only:
        t0 = time.perf_counter()
        contact_sheet(images, os.path.join(outdir, "contact.png"))
        timings["contact"] = round(time.perf_counter() - t0, 2)
    print("total: %.2fs" % sum(timings.values()))
    return timings


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    main(sys.argv[1], only=sys.argv[2:] or None)
