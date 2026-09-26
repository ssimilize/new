"""The eggs: one shared egg mesh (plus a faceted gem egg for the Crystal Egg), a painted texture per
egg type, small ornaments for a few special eggs, three crack overlays for the hatch, and renders.
From monster-ranch-idle/, with system Python (numpy + Pillow; Blender 5.1 is run for the rest):

  python tools/blender/eggs.py                 build everything into art/eggs (not in git)
  python tools/blender/eggs.py royal,sky       only repaint and re-render these eggs (meshes too)
  python tools/blender/eggs.py ids ids.json    record published ids in src/client/Visuals/EggAssets.luau

What it writes:
  art/eggs/upload/<mesh>/mesh.json   egg_shell, egg_gem, egg_orn_<egg>: publish_meshes.luau's format
                                     (no bones), so `_G.MeshPublishRun(base, { ... })` publishes them
  art/eggs/upload/<image>.png        egg_<egg> (1024 x 512, one per egg type), egg_crack1..3 (alpha),
                                     egg_painted (alpha: the Spring Bloom hunt's painted overlay),
                                     egg_ornaments (the ornaments' shared swatch palette)
  art/eggs/icons/<egg>.png           256 px, transparent, with the UI's #1B1B1B ink outline
  art/eggs/sheet.png                 every egg side by side, the crack stages, the hunt egg, and the
                                     eggs at incubator size; art/eggs/preview/sheet.jpg is a small copy
                                     that is kept in git
  src/client/Visuals/EggAssets.luau  rewritten with the ornament offsets, keeping every recorded id

ids.json maps upload names to ids: { "egg_shell": "rbxassetid://N", "egg_royal": "...",
"egg_orn_royal": "...", "egg_ornaments": "...", "egg_crack1": "...", "egg_painted": "...", ... }.

Why painted in numpy and not baked from shader nodes: the texture is a latitude-longitude map of a
surface of revolution, so every texel's point on the egg is known exactly. Each motif (spot, star,
snowflake, gem stud, fissure) is a signed distance field in the egg's own tangent plane at that
point, which gives crisp, evenly sized cartoon shapes with soft ink edges and no seam (the pattern is
evaluated in 3D, so the back seam at u = 0 / 1 is invisible). A node graph for a five-point star or a
snowflake is a sprawl of math nodes; here it is a few lines. Albedo only: the game lights it.

Axes: Blender egg frame, 1 wide and 1.3 tall, centred on the origin, front -Y; exported with
export_static.py's axes (Roblox -Z front). The Roblox MeshPart is therefore (s, 1.3 s, s) for an egg
of size s, the placeholder's box.
"""

import json
import math
import re
import subprocess
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
OUT = ROOT / "art" / "eggs"
UPLOAD = OUT / "upload"
RENDERS = OUT / "renders"
ICONS = OUT / "icons"
WORK = OUT / "work"
PREVIEW = OUT / "preview"
ASSETS = ROOT / "src" / "client" / "Visuals" / "EggAssets.luau"
EGGS_CONFIG = ROOT / "src" / "shared" / "Config" / "Eggs.luau"
INK = (0x1B, 0x1B, 0x1B)

TEX_W, TEX_H = 1024, 512
HEIGHT = 1.3
TAPER = 0.12  # the narrower top
AA = 0.0045  # egg units: about one texel, the soft edge of every shape
SHELL_SEGMENTS, SHELL_RINGS = 48, 32
GEM_SEGMENTS = 12
GEM_LEVELS = [0.0, 0.22, 0.45, 0.66, 0.84, 1.0]  # v of each ring of facets
CRACK_SCALE = 1.03  # the crack overlay is the egg's own mesh this much larger (EggModel.luau)
ORNAMENTS = ("royal", "harvest", "bloom", "sky", "glacier")
GEM_EGGS = ("crystal",)

# ─── The egg's shape ──────────────────────────────────────────────────────────────────────


def _raw(alpha):
    c = -np.cos(alpha)
    return 0.5 * np.sin(alpha) * (1 - TAPER * c), 0.5 * HEIGHT * c


_R_SCALE = 0.5 / _raw(np.linspace(0, np.pi, 4001))[0].max()  # the widest diameter is 1


def profile(alpha):
    r, z = _raw(alpha)
    return r * _R_SCALE, z


def surface(u, v):
    """The point and outward normal of the egg at texture coordinates (u, v): v = 0 bottom, 1 top;
    u = 0.5 is the front (-Y), the seam is at the back."""
    u = np.asarray(u, dtype=np.float64)
    v = np.asarray(v, dtype=np.float64)
    phi = np.pi / 2 + 2 * np.pi * u
    a = np.pi * v
    r, z = profile(a)
    e = 1e-4
    r1, z1 = profile(np.clip(a + e, 0, np.pi))
    r0, z0 = profile(np.clip(a - e, 0, np.pi))
    dr, dz = r1 - r0, z1 - z0
    cp, sp = np.cos(phi), np.sin(phi)
    p = np.stack([r * cp, r * sp, z], -1)
    n = np.stack([dz * cp, dz * sp, -dr], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return p, n


def radius_at_v(v):
    return profile(np.pi * np.asarray(v, dtype=np.float64))[0]


def v_at_z(z):
    """The v where the egg is at height z (egg units, -0.65 .. 0.65)."""
    return math.acos(max(-1.0, min(1.0, -z / (0.5 * HEIGHT)))) / math.pi


# ─── Meshes ───────────────────────────────────────────────────────────────────────────────


def _outward(positions, normals, tris):
    """Flips triangles whose winding disagrees with their vertex normals (Blender: CCW outward)."""
    p = np.asarray(positions)
    n = np.asarray(normals)
    out = []
    for a, b, c in tris:
        face = np.cross(p[b] - p[a], p[c] - p[a])
        out.append((a, b, c) if face @ (n[a] + n[b] + n[c]) >= 0 else (a, c, b))
    return out


def shell_mesh():
    """The smooth egg: latitude-longitude rings, the seam duplicated at the back, one pole vertex
    per segment (so every triangle's UVs are right)."""
    positions, normals, uvs, tris = [], [], [], []

    def vert(u, v):
        p, n = surface(u, v)
        positions.append(p.tolist())
        normals.append(n.tolist())
        uvs.append([float(u), float(v)])
        return len(positions) - 1

    rings = []
    for i in range(1, SHELL_RINGS):
        v = i / SHELL_RINGS
        rings.append([vert(j / SHELL_SEGMENTS, v) for j in range(SHELL_SEGMENTS + 1)])
    for j in range(SHELL_SEGMENTS):
        bottom = vert((j + 0.5) / SHELL_SEGMENTS, 0.0)
        tris.append((bottom, rings[0][j + 1], rings[0][j]))
        top = vert((j + 0.5) / SHELL_SEGMENTS, 1.0)
        tris.append((top, rings[-1][j], rings[-1][j + 1]))
    for i in range(len(rings) - 1):
        lo, hi = rings[i], rings[i + 1]
        for j in range(SHELL_SEGMENTS):
            tris.append((lo[j], lo[j + 1], hi[j + 1]))
            tris.append((lo[j], hi[j + 1], hi[j]))
    return {"positions": positions, "normals": normals, "uvs": uvs, "tris": _outward(positions, normals, tris)}


def gem_mesh():
    """The Crystal Egg: the same profile cut into flat facets (GEM_SEGMENTS around, GEM_LEVELS up),
    each facet with its own vertices and normal. UVs are the shell's latitude-longitude, so a
    facet is a rectangle of the texture (the painter shades facet by facet) and the crack overlays fit."""
    positions, normals, uvs, tris = [], [], [], []

    def facet(corners):
        pts = [surface(u, v)[0] for u, v in corners]
        centre = sum(pts) / len(pts)
        n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        if np.linalg.norm(n) < 1e-9:
            n = np.cross(pts[2] - pts[0], pts[3] - pts[0])
        n /= np.linalg.norm(n)
        if n @ centre < 0:
            n = -n
        base = len(positions)
        for (u, v), p in zip(corners, pts):
            positions.append(p.tolist())
            normals.append(n.tolist())
            uvs.append([float(u), float(v)])
        for k in range(1, len(corners) - 1):
            tris.append((base, base + k, base + k + 1))

    levels = GEM_LEVELS
    for j in range(GEM_SEGMENTS):
        u0, u1 = j / GEM_SEGMENTS, (j + 1) / GEM_SEGMENTS
        um = (u0 + u1) / 2
        facet([(um, 0.0), (u1, levels[1]), (u0, levels[1])])
        for i in range(1, len(levels) - 2):
            facet([(u0, levels[i]), (u1, levels[i]), (u1, levels[i + 1]), (u0, levels[i + 1])])
        facet([(u0, levels[-2]), (u1, levels[-2]), (um, 1.0)])
    return {"positions": positions, "normals": normals, "uvs": uvs, "tris": _outward(positions, normals, tris)}


C_AXES = np.array(((-1, 0, 0), (0, 0, 1), (0, 1, 0)), dtype=np.float64)  # export_static.py's axes


def write_mesh_json(name: str, mesh: dict, centre=(0.0, 0.0, 0.0)) -> None:
    """mesh.json in publish_meshes.luau's format: Roblox axes, centred on `centre` (Blender), no bones."""
    import base64
    import struct

    def b64(fmt, values):
        return base64.b64encode(struct.pack("<" + fmt * len(values), *values)).decode()

    # Weld identical corners (same position, uv and normal) so the vertex count stays small.
    index, verts, tris = {}, [], []
    for tri in mesh["tris"]:
        for k in tri:
            p, n, uv = mesh["positions"][k], mesh["normals"][k], mesh["uvs"][k]
            key = (round(p[0], 6), round(p[1], 6), round(p[2], 6), round(uv[0], 5), round(uv[1], 5), round(n[0], 3), round(n[1], 3), round(n[2], 3))
            if key not in index:
                index[key] = len(verts)
                verts.append((p, n, uv))
            tris.append(index[key])
    if len(verts) > 65535:
        raise SystemExit(f"{name}: {len(verts)} vertices, too many for u16 indices")
    c = np.asarray(centre, dtype=np.float64)
    positions, norms, uvs = [], [], []
    for p, n, uv in verts:
        q = C_AXES @ (np.asarray(p) - c)
        m = C_AXES @ np.asarray(n)
        m /= np.linalg.norm(m)
        positions += q.tolist()
        norms += m.tolist()
        uvs += [uv[0], 1.0 - uv[1]]
    out = UPLOAD / name
    out.mkdir(parents=True, exist_ok=True)
    data = {
        "form": name,
        "vertices": len(verts),
        "triangles": len(tris) // 3,
        "positions": b64("f", positions),
        "normals": b64("f", norms),
        "uvs": b64("f", uvs),
        "tris": b64("H", tris),
        "skin": b64("B", [0] * (8 * len(verts))),
        "bones": [],
    }
    (out / "mesh.json").write_text(json.dumps(data), encoding="utf-8")
    print(f"[eggs] {name}: {len(verts)} verts, {len(tris) // 3} tris", flush=True)


# ─── Colours and 2D shapes ────────────────────────────────────────────────────────────────


def hexc(h: str):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)], dtype=np.float32)


def mix(a, b, t):
    """a to b by t; a per-pixel t (H x W) is broadcast over the colour channels."""
    t = np.asarray(t, dtype=np.float32)
    if t.ndim >= 1 and t.shape[-1] not in (1, 3):
        t = t[..., None]
    return np.asarray(a, dtype=np.float32) * (1 - t) + np.asarray(b, dtype=np.float32) * t


WHITE = hexc("#FFFFFF")
BLACK = hexc("#000000")


def lighten(c, t):
    return mix(c, WHITE, t)


def darken(c, t):
    """Deeper, not greyer: scales towards black and keeps a little saturation."""
    c = np.asarray(c, dtype=np.float32)
    return np.clip(c * (1 - t) - (c.mean() - c) * t * 0.35, 0, 1)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def sd_circle(x, y, r):
    return np.hypot(x, y) - r


def sd_ellipse(x, y, a, b):
    return (np.hypot(x / a, y / b) - 1) * min(a, b)


def sd_blob(x, y, r, p1, p2, wob=1.0):
    th = np.arctan2(y, x)
    return np.hypot(x, y) - r * (1 + wob * (0.11 * np.sin(3 * th + p1) + 0.05 * np.sin(5 * th + p2)))


def sd_vesica(x, y, r, d):
    """A leaf along y (iq's vesica), 2 sqrt(r^2 - d^2) long and 2 (r - d) wide."""
    x, y = np.abs(x), np.abs(y)
    b = math.sqrt(r * r - d * d)
    return np.where((y - b) * d > x * b, np.hypot(x, y - b), np.hypot(x + d, y) - r)


def sd_star5(x, y, r, rf):
    k1x, k1y = 0.809016994375, -0.587785252292
    k2x, k2y = -k1x, k1y
    x = np.abs(x)
    d = np.maximum(k1x * x + k1y * y, 0)
    x, y = x - 2 * d * k1x, y - 2 * d * k1y
    d = np.maximum(k2x * x + k2y * y, 0)
    x, y = x - 2 * d * k2x, y - 2 * d * k2y
    x = np.abs(x)
    y = y - r
    bax, bay = rf * -k1y, rf * k1x - 1
    h = np.clip((x * bax + y * bay) / (bax * bax + bay * bay), 0, r)
    return np.hypot(x - bax * h, y - bay * h) * np.sign(y * bax - x * bay)


def sd_sparkle(x, y, r):
    """A four-point twinkle."""
    ax, ay = np.abs(x) / r, np.abs(y) / r
    return (np.sqrt(ax) + np.sqrt(ay) - 1) * r * 0.4


def sd_segment(x, y, ax, ay, bx, by):
    px, py = x - ax, y - ay
    dx, dy = bx - ax, by - ay
    h = np.clip((px * dx + py * dy) / (dx * dx + dy * dy + 1e-12), 0, 1)
    return np.hypot(px - dx * h, py - dy * h)


def sd_polyline(x, y, pts):
    d = None
    for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
        s = sd_segment(x, y, ax, ay, bx, by)
        d = s if d is None else np.minimum(d, s)
    return d


def sd_triangle(x, y, r):
    """An equilateral triangle pointing up (iq)."""
    k = math.sqrt(3.0)
    x = np.abs(x) - r
    y = y + r / k
    flip = x + k * y > 0
    nx = np.where(flip, (x - k * y) / 2, x)
    ny = np.where(flip, (-k * x - y) / 2, y)
    nx = nx - np.clip(nx, -2 * r, 0)
    return -np.hypot(nx, ny) * np.sign(ny)


def sd_box(x, y, hx, hy, rad=0.0):
    qx, qy = np.abs(x) - hx + rad, np.abs(y) - hy + rad
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - rad


def sd_snowflake(x, y, r, w):
    th = np.arctan2(y, x)
    rho = np.hypot(x, y)
    th = np.mod(th, math.pi / 3)
    th = np.where(th > math.pi / 6, math.pi / 3 - th, th)
    fx, fy = rho * np.cos(th), rho * np.sin(th)
    c60, s60 = math.cos(math.pi / 3), math.sin(math.pi / 3)
    d = sd_segment(fx, fy, 0, 0, r, 0) - w
    d = np.minimum(d, sd_segment(fx, fy, 0.45 * r, 0, 0.45 * r + 0.32 * r * c60, 0.32 * r * s60) - w * 0.85)
    d = np.minimum(d, sd_segment(fx, fy, 0.72 * r, 0, 0.72 * r + 0.2 * r * c60, 0.2 * r * s60) - w * 0.75)
    return np.minimum(d, rho - 0.16 * r)


# ─── The canvas ───────────────────────────────────────────────────────────────────────────


class Canvas:
    """A W x H latitude-longitude texture of the egg. Row j is v = (j + 0.5) / H (bottom first)."""

    def __init__(self, seed: int, w: int = TEX_W, h: int = TEX_H, alpha: bool = False):
        self.w, self.h = w, h
        u = (np.arange(w) + 0.5) / w
        v = (np.arange(h) + 0.5) / h
        self.U, self.V = np.meshgrid(u, v)
        p, n = surface(self.U, self.V)
        self.P, self.N = p.astype(np.float32), n.astype(np.float32)
        self.Z = self.P[..., 2]
        self.PHI = np.pi / 2 + 2 * np.pi * self.U
        self.row_r = radius_at_v(v)
        self.rgb = np.zeros((h, w, 3), dtype=np.float32)
        self.a = np.zeros((h, w), dtype=np.float32) if alpha else None
        self.rng = np.random.default_rng(seed)

    # Whole-egg fields ------------------------------------------------------------------

    def noise(self, freq=3.0, seed=0, octaves=4):
        rng = np.random.default_rng(seed + 991)
        total = np.zeros(self.U.shape, dtype=np.float32)
        for _ in range(octaves):
            k = rng.normal(size=3)
            k = k / np.linalg.norm(k) * freq * rng.uniform(0.7, 1.4)
            total += np.sin(self.P @ k.astype(np.float32) * 2 * np.pi + rng.uniform(0, 2 * np.pi))
        return total / octaves

    def base(self, bottom, top, wash=0.015, seed=1):
        t = smoothstep(0.08, 0.95, self.V)[..., None]
        self.rgb[:] = mix(bottom, top, t) + self.noise(2.2, seed)[..., None] * wash
        if self.a is not None:
            self.a[:] = 1

    def over(self, a, color, rs=slice(None), cs=slice(None)):
        a = np.asarray(a, dtype=np.float32)[..., None]
        col = np.asarray(color, dtype=np.float32)
        self.rgb[rs, cs] = self.rgb[rs, cs] * (1 - a) + col * a
        if self.a is not None:
            self.a[rs, cs] = self.a[rs, cs] * (1 - a[..., 0]) + a[..., 0]

    def cover(self, d, soft=AA):
        return np.clip(0.5 - d / soft, 0, 1)

    # Motifs in the tangent plane --------------------------------------------------------

    def window(self, uv, reach):
        u0, v0 = uv
        dv = reach / (0.4 * math.pi) + 2 / self.h
        j0 = max(0, int(math.floor((v0 - dv) * self.h)))
        j1 = min(self.h, int(math.ceil((v0 + dv) * self.h)) + 1)
        rmin = float(self.row_r[j0:j1].min())
        if 2 * math.pi * rmin < 4.2 * reach:
            cols = np.arange(self.w)
        else:
            du = reach / (2 * math.pi * rmin) * 1.15 + 2 / self.w
            cols = np.arange(int(math.floor((u0 - du) * self.w)), int(math.ceil((u0 + du) * self.w)) + 1) % self.w
        return slice(j0, j1), cols

    def local(self, uv, reach, rot=0.0):
        rs, cs = self.window(uv, reach)
        p = self.P[rs][:, cs]
        n = self.N[rs][:, cs]
        c, nc = surface(uv[0], uv[1])
        c, nc = c.astype(np.float32), nc.astype(np.float32)
        e = np.cross(np.array([0, 0, 1], dtype=np.float32), nc)
        if np.linalg.norm(e) < 1e-3:
            e = np.array([1, 0, 0], dtype=np.float32)
        e /= np.linalg.norm(e)
        up = np.cross(nc, e)
        er = math.cos(rot) * e + math.sin(rot) * up
        upr = -math.sin(rot) * e + math.cos(rot) * up
        d = p - c
        x, y = d @ er, d @ upr
        facing = ((n @ nc) > 0.15) & ((d @ nc) > -reach)
        return rs, cs, x, y, facing

    def paint(self, uv, reach, sdf, color, rot=0.0, grow=0.0, alpha=1.0, soft=AA):
        """Paints one shape: sdf(x, y) in egg units round uv's tangent plane; color may be a
        function of (x, y) for a painted gradient."""
        rs, cs, x, y, facing = self.local(uv, reach, rot)
        a = self.cover(sdf(x, y) - grow, soft) * facing * alpha
        col = color(x, y) if callable(color) else color
        self.over(a, col, rs, cs)

    def inked(self, uv, reach, sdf, fill, ink, width=0.011, rot=0.0, shine=None):
        """A cartoon motif: an ink rim, the fill, and a small highlight up and to the left."""
        self.paint(uv, reach, sdf, ink, rot, grow=width)
        self.paint(uv, reach, sdf, fill, rot)
        if shine is not None:
            k, col = shine
            self.paint(uv, reach, lambda x, y: sd_ellipse(x + k * 0.35, y - k * 0.38, k * 0.3, k * 0.18), col, rot, alpha=0.8)

    # Strokes on the surface --------------------------------------------------------------

    def stroke(self, cov, path, w0, w1, soft=AA):
        """Max-coverage of a polyline of (u, v) points, its width tapering from w0 to w1."""
        pts = [surface(u, v)[0].astype(np.float32) for u, v in path]
        n = len(pts) - 1
        for i in range(n):
            a, b = pts[i], pts[i + 1]
            (ua, va), (ub, vb) = path[i], path[i + 1]
            if ub - ua > 0.5:
                ub -= 1
            elif ua - ub > 0.5:
                ub += 1
            wa = w0 + (w1 - w0) * i / n
            wb = w0 + (w1 - w0) * (i + 1) / n
            reach = float(np.linalg.norm(b - a)) / 2 + max(wa, wb) + 4 * soft
            rs, cs = self.window(((ua + ub) / 2 % 1.0, (va + vb) / 2), reach)
            p = self.P[rs][:, cs]
            ab = b - a
            t = np.clip(((p - a) @ ab) / float(ab @ ab + 1e-12), 0, 1)
            dist = np.linalg.norm(p - (a + t[..., None] * ab), axis=-1)
            cov_part = self.cover(dist - (wa + (wb - wa) * t), soft)
            cov[rs, cs] = np.maximum(cov[rs, cs], cov_part)

    def layer(self):
        return np.zeros((self.h, self.w), dtype=np.float32)

    # Placement ------------------------------------------------------------------------------

    def scatter(self, n, spacing, vmin=0.1, vmax=0.9, avoid=(), tries=4000):
        """About n points spread evenly by area (Poisson-disc on the surface) with v in [vmin, vmax]."""
        chosen, pts = [], [np.asarray(surface(*a)[0]) for a in avoid]
        for _ in range(tries):
            if len(chosen) >= n:
                break
            u = self.rng.uniform()
            v = math.acos(1 - 2 * self.rng.uniform()) / math.pi
            if not vmin <= v <= vmax:
                continue
            p = surface(u, v)[0]
            if all(np.linalg.norm(p - q) >= spacing for q in pts):
                chosen.append((u, v))
                pts.append(p)
        return chosen

    def walk(self, start, heading, steps, step=0.07, turn=0.6):
        """A crack's path: a random walk on the surface from start (u, v), heading in radians
        (0 = along +u, pi/2 = up)."""
        u, v = start
        path = [(u, v)]
        for _ in range(steps):
            heading += self.rng.uniform(-turn, turn)
            r = max(float(radius_at_v(v)), 0.08)
            u = (u + step * math.cos(heading) / (2 * math.pi * r)) % 1.0
            v = min(0.93, max(0.07, v + step * math.sin(heading) / (0.62 * math.pi)))
            path.append((u, v))
        return path

    def save(self, path: Path):
        from PIL import Image

        rgb = np.clip(np.flipud(self.rgb) * 255 + 0.5, 0, 255).astype(np.uint8)
        if self.a is None:
            Image.fromarray(rgb, "RGB").save(path)
        else:
            a = np.clip(np.flipud(self.a) * 255 + 0.5, 0, 255).astype(np.uint8)
            Image.fromarray(np.dstack([rgb, a]), "RGBA").save(path)


# ─── The eggs ─────────────────────────────────────────────────────────────────────────────


def ink_of(c, t=0.45):
    return darken(c, t)


def paint_spots(cv: Canvas, s, k):
    """Meadow: round, slightly wobbly spots with a shine, and freckles."""
    cv.base(darken(s, 0.1), lighten(s, 0.12))
    for u, v in cv.scatter(17, 0.33, 0.1, 0.9):
        r = cv.rng.uniform(0.09, 0.14)
        p1, p2 = cv.rng.uniform(0, 6.3, 2)
        cv.inked((u, v), r * 1.6, lambda x, y, r=r, p1=p1, p2=p2: sd_blob(x, y, r, p1, p2), k, ink_of(k, 0.4), shine=(r, lighten(k, 0.4)))
    for u, v in cv.scatter(26, 0.12, 0.08, 0.92):
        r = cv.rng.uniform(0.014, 0.026)
        cv.paint((u, v), r * 2, lambda x, y, r=r: sd_circle(x, y, r), mix(s, k, 0.55))


def paint_leaves(cv: Canvas, s, k):
    """Grove: scattered leaves with a pale midrib, and seed dots."""
    cv.base(darken(s, 0.12), lighten(s, 0.1))
    for u, v in cv.scatter(17, 0.3, 0.1, 0.9):
        size = cv.rng.uniform(1.15, 1.5)
        r, d = 0.13 * size, 0.092 * size
        rot = cv.rng.uniform(-1.2, 1.2)
        half = math.sqrt(r * r - d * d)
        leaf = lambda x, y, r=r, d=d: sd_vesica(x, y, r, d)
        cv.inked((u, v), half * 1.4, leaf, lambda x, y: mix(k, lighten(k, 0.25), np.clip(0.5 - x * 6, 0, 1)), ink_of(k, 0.4), rot=rot)
        cv.paint((u, v), half * 1.4, lambda x, y, h=half: sd_segment(x, y, 0, -h * 0.85, 0, h * 0.7) - 0.0045, lighten(k, 0.45), rot=rot)
    for u, v in cv.scatter(22, 0.12, 0.08, 0.92):
        r = cv.rng.uniform(0.014, 0.024)
        cv.paint((u, v), r * 2, lambda x, y, r=r: sd_circle(x, y, r), mix(s, k, 0.5))


def paint_flowers(cv: Canvas, s, k):
    """Bloom: five-petal flowers in pink, lilac and white, with little leaf pairs."""
    cv.base(mix(s, hexc("#FFC6E2"), 0.35), lighten(s, 0.35))
    petals = [hexc("#FF8FC4"), hexc("#C9A2FF"), hexc("#FFFFFF"), hexc("#FFB067")]
    spots = cv.scatter(13, 0.33, 0.12, 0.9)
    for u, v in spots:
        rot = cv.rng.uniform(0, 6.3)
        for side in (-1, 1):
            cv.inked((u, v), 0.26, lambda x, y, side=side: sd_vesica(x - side * 0.12, y + 0.04, 0.085, 0.057), k, ink_of(k, 0.4), width=0.008, rot=rot + side * 0.9)
    for i, (u, v) in enumerate(spots):
        col = petals[i % len(petals)]
        rot = cv.rng.uniform(0, 6.3)
        size = cv.rng.uniform(1.3, 1.6)

        def flower(x, y, size=size):
            d = None
            for p in range(5):
                a = p * 2 * math.pi / 5
                e = sd_circle(x - math.cos(a) * 0.052 * size, y - math.sin(a) * 0.052 * size, 0.043 * size)
                d = e if d is None else np.minimum(d, e)
            return d

        ink = ink_of(col, 0.35) if col.mean() < 0.95 else hexc("#E59BC0")
        cv.inked((u, v), 0.12 * size, flower, col, ink, width=0.009, rot=rot)
        cv.inked((u, v), 0.05, lambda x, y, size=size: sd_circle(x, y, 0.028 * size), hexc("#FFD447"), hexc("#D39A1C"), width=0.007)
    for u, v in cv.scatter(20, 0.1, 0.08, 0.92, avoid=spots):
        r = cv.rng.uniform(0.012, 0.02)
        cv.paint((u, v), r * 2, lambda x, y, r=r: sd_circle(x, y, r), mix(s, k, 0.6))


def paint_facets(cv: Canvas, s, k):
    """Crystal: shaded facet by facet to match the gem mesh, bevelled edges, a shine and twinkles."""
    rng = cv.rng
    col = np.floor(cv.U * GEM_SEGMENTS).astype(int) % GEM_SEGMENTS
    levels = np.array(GEM_LEVELS)
    band = np.clip(np.searchsorted(levels, cv.V, side="right") - 1, 0, len(levels) - 2)
    light = np.array([-0.45, -0.55, 0.7])
    light /= np.linalg.norm(light)
    shade = np.zeros(cv.U.shape, dtype=np.float32)
    jitter = rng.uniform(-0.25, 0.25, (GEM_SEGMENTS, len(levels)))
    for j in range(GEM_SEGMENTS):
        for b in range(len(levels) - 1):
            um = (j + 0.5) / GEM_SEGMENTS
            vm = (levels[b] + levels[b + 1]) / 2
            _, n = surface(um, vm)
            shade[(col == j) & (band == b)] = 0.42 + 0.6 * float(n @ light) + jitter[j, b]
    deep, pale = mix(darken(s, 0.35), hexc("#3F8FE0"), 0.55), lighten(s, 0.5)
    cv.rgb[:] = mix(deep, pale, np.clip(shade, 0, 1)[..., None])
    cv.rgb[:] = mix(cv.rgb, lighten(s, 0.3), (0.15 * smoothstep(0.3, 1.0, cv.V))[..., None])
    # Bevels: a bright line along each facet's top and left edges, a deep one along bottom and right.
    fu = cv.U * GEM_SEGMENTS - np.floor(cv.U * GEM_SEGMENTS)
    lo, hi = levels[band], levels[band + 1]
    fv = (cv.V - lo) / (hi - lo)
    r = np.maximum(cv.row_r[:, None], 0.02)
    du = 2 * math.pi * r / GEM_SEGMENTS
    dv = (hi - lo) * 0.62 * math.pi
    left, right = fu * du, (1 - fu) * du
    bottom, top = fv * dv, (1 - fv) * dv
    polar = (band == 0) | (band == len(levels) - 2)
    w = 0.012
    cv.over(np.clip(1 - np.minimum(top, left) / w, 0, 1) * 0.85 * ~polar, WHITE)
    cv.over(np.clip(1 - np.minimum(bottom, right) / w, 0, 1) * 0.35 * ~polar, darken(s, 0.45))
    edge = np.clip(1 - np.minimum(left, right) / w, 0, 1) * polar
    cv.over(edge * 0.6, WHITE)
    # A diagonal shine across the front, and a few twinkles.
    x = cv.P[..., 0] + cv.P[..., 2] * 0.55
    cv.over(np.clip(1 - np.abs(x + 0.12) / 0.05, 0, 1) * 0.45 * (cv.P[..., 1] < 0), WHITE)
    cv.over(np.clip(1 - np.abs(x + 0.24) / 0.018, 0, 1) * 0.5 * (cv.P[..., 1] < 0), WHITE)
    for u, v in cv.scatter(11, 0.3, 0.15, 0.88):
        size = rng.uniform(0.045, 0.08)
        cv.paint((u, v), size * 1.2, lambda x, y, size=size: sd_sparkle(x, y, size), WHITE)


def paint_royal(cv: Canvas, s, k):
    """Royal: a gold band set with ruby and teal studs, gold pinstripes, gold twinkles."""
    cv.base(darken(s, 0.18), lighten(s, 0.12))
    z = cv.Z
    gold_ink = ink_of(k, 0.5)
    for zc, hw in ((0.0, 0.085), (0.155, 0.012), (-0.155, 0.012)):
        d = np.abs(z - zc) - hw
        cv.over(cv.cover(d - 0.011), gold_ink)
        fill = mix(k, lighten(k, 0.35), np.clip(1 - np.abs(z - zc - hw * 0.3) / (hw + 1e-6), 0, 1)[..., None] * 0.7)
        cv.over(cv.cover(d), fill)
    cv.over(cv.cover(np.abs(np.abs(z) - 0.06) - 0.004) * (np.abs(z) < 0.09), darken(k, 0.2))
    v0 = v_at_z(0.0)
    gems = [hexc("#E5484D"), hexc("#35C9C1")]
    for i in range(10):
        uv = ((i + 0.5) / 10, v0)
        gem = gems[i % 2]
        cv.inked(uv, 0.08, lambda x, y: sd_circle(x, y, 0.052), k, gold_ink, width=0.009)
        cv.paint(uv, 0.08, lambda x, y: sd_circle(x, y, 0.036), lambda x, y, gem=gem: mix(darken(gem, 0.25), lighten(gem, 0.25), np.clip(0.5 + (y - x) * 9, 0, 1)[..., None]))
        cv.paint(uv, 0.08, lambda x, y: sd_ellipse(x + 0.012, y - 0.013, 0.012, 0.008), WHITE, alpha=0.9)
    for u, v in cv.scatter(22, 0.17, 0.1, 0.9):
        if abs(float(surface(u, v)[0][2])) < 0.2:
            continue
        if cv.rng.uniform() < 0.55:
            size = cv.rng.uniform(0.035, 0.05)
            cv.paint((u, v), size * 1.2, lambda x, y, size=size: sd_sparkle(x, y, size), lighten(k, 0.2))
        else:
            cv.paint((u, v), 0.03, lambda x, y: sd_circle(x, y, 0.014), mix(s, k, 0.7))


def paint_pearl(cv: Canvas, s, k):
    """Pearl: a shimmering cream shell, a wavy blue ribbon strung with pearls."""
    cv.base(darken(s, 0.06), lighten(s, 0.3))
    tint = cv.noise(1.6, 7, 3)[..., None]
    cv.rgb[:] = mix(cv.rgb, mix(hexc("#FFD9EC"), hexc("#D5F0FF"), np.clip(tint * 0.8 + 0.5, 0, 1)), 0.22)
    wave = 0.035 * np.sin(3 * cv.PHI)
    d = np.abs(cv.Z - wave) - 0.06
    cv.over(cv.cover(d - 0.011), ink_of(k, 0.4))
    cv.over(cv.cover(d), mix(k, lighten(k, 0.3), smoothstep(-0.06, 0.06, (cv.Z - wave))[..., None]))
    for sign in (-1, 1):
        dd = np.abs(cv.Z - wave - sign * 0.105) - 0.006
        cv.over(cv.cover(dd), mix(k, s, 0.35))
    n = 26
    for i in range(n):
        u = (i + 0.5) / n
        phi = math.pi / 2 + 2 * math.pi * u
        zc = 0.035 * math.sin(3 * phi)
        uv = (u, v_at_z(zc))
        cv.inked(uv, 0.06, lambda x, y: sd_circle(x, y, 0.034), lambda x, y: mix(hexc("#F4ECE0"), WHITE, np.clip(0.5 + (y - x) * 12, 0, 1)[..., None]), hexc("#9DB3C4"), width=0.007)
        cv.paint(uv, 0.06, lambda x, y: sd_circle(x + 0.011, y - 0.012, 0.009), WHITE)
    for u, v in cv.scatter(24, 0.15, 0.1, 0.9):
        if abs(float(surface(u, v)[0][2])) < 0.16:
            continue
        cv.paint((u, v), 0.03, lambda x, y: sd_circle(x, y, 0.013), mix(s, k, 0.45))


def paint_lantern(cv: Canvas, s, k):
    """Lantern: red lantern ribs, gold caps and bands, a ring of gold coin medallions."""
    cv.base(darken(s, 0.12), lighten(s, 0.08))
    ribs = 14
    t = cv.U * ribs - np.floor(cv.U * ribs)
    cv.rgb[:] *= (0.9 + 0.1 * np.sin(np.pi * t))[..., None]
    arc = np.minimum(t, 1 - t) * 2 * np.pi * np.maximum(cv.row_r[:, None], 1e-3) / ribs
    cv.over(cv.cover(arc - 0.005) * 0.8, darken(s, 0.35))
    gold_ink = ink_of(k, 0.5)
    for zc, hw in ((0.12, 0.022), (-0.12, 0.022)):
        d = np.abs(cv.Z - zc) - hw
        cv.over(cv.cover(d - 0.01), gold_ink)
        cv.over(cv.cover(d), k)
    for cap, sign in ((0.5, 1), (0.5, -1)):
        d = (sign * -cv.Z) + cap  # caps: |z| > cap
        cv.over(cv.cover(d - 0.012), gold_ink)
        cv.over(cv.cover(d), mix(k, lighten(k, 0.35), smoothstep(cap, 0.65, np.abs(cv.Z))[..., None]))
    for sign in (1, -1):
        z0 = 0.43 * sign
        for i in range(24):
            uv = ((i + 0.5) / 24, v_at_z(z0))
            cv.paint(uv, 0.03, lambda x, y: sd_circle(x, y, 0.013), k)
    v0 = v_at_z(0.0)
    for i in range(8):
        uv = ((i + 0.5) / 8, v0)
        cv.inked(uv, 0.1, lambda x, y: sd_circle(x, y, 0.068), lambda x, y: mix(k, lighten(k, 0.4), np.clip(0.5 + (y - x) * 7, 0, 1)[..., None]), gold_ink)
        cv.paint(uv, 0.1, lambda x, y: np.abs(sd_circle(x, y, 0.052)) - 0.004, darken(k, 0.3))
        cv.paint(uv, 0.1, lambda x, y: sd_box(x, y, 0.017, 0.017), gold_ink, grow=0.006)
        cv.paint(uv, 0.1, lambda x, y: sd_box(x, y, 0.017, 0.017), s)
        uv2 = (i / 8, v0)
        cv.paint(uv2, 0.06, lambda x, y: sd_sparkle(x, y, 0.04), lighten(k, 0.3))


def paint_splash(cv: Canvas, s, k):
    """Splash: sky-blue top, two rolling wave bands with white foam curls, gold sun-glints."""
    deep = hexc("#1F7FD1")
    cv.base(mix(s, deep, 0.25), lighten(s, 0.3))
    for z0, amp, n, ph, depth in ((0.02, 0.045, 5, 0.3, 0.45), (-0.27, 0.04, 6, 1.7, 0.75)):
        crest = z0 + amp * np.sin(n * cv.PHI + ph)
        below = crest - cv.Z
        water = mix(s, deep, depth)
        cv.over(cv.cover(-below - 0.012), ink_of(water, 0.35))
        cv.over(cv.cover(-below), mix(water, darken(water, 0.2), smoothstep(0, 0.25, below)[..., None]))
        cv.over(cv.cover(np.abs(below - 0.028) - 0.006) * 0.45, lighten(water, 0.35))
        foam = cv.cover(np.abs(below + 0.004) - 0.011)
        cv.over(foam, WHITE)
        for m in range(n):
            u = ((math.pi / 2 - ph) / n + 2 * math.pi * m / n - math.pi / 2) / (2 * math.pi) % 1.0
            uv = (u, v_at_z(z0 + amp + 0.028))
            curl = lambda x, y: np.maximum(sd_circle(x, y, 0.04), -sd_circle(x + 0.013, y + 0.008, 0.024))
            cv.inked(uv, 0.07, curl, WHITE, ink_of(water, 0.3), width=0.007)
    for u, v in cv.scatter(9, 0.25, 0.62, 0.9):
        cv.inked((u, v), 0.06, lambda x, y: sd_star5(x, y, 0.038, 0.5) - 0.004, k, ink_of(k, 0.45), width=0.008, rot=cv.rng.uniform(-0.4, 0.4))
    for u, v in cv.scatter(16, 0.12, 0.55, 0.92):
        r = cv.rng.uniform(0.012, 0.022)
        cv.paint((u, v), r * 2, lambda x, y, r=r: np.abs(sd_circle(x, y, r)) - 0.004, WHITE, alpha=0.85)


def paint_harvest(cv: Canvas, s, k):
    """Harvest: pumpkin ribs and a friendly glowing jack-o'-lantern face on the front."""
    cv.base(darken(s, 0.1), lighten(s, 0.08))
    ribs = 10
    t = cv.U * ribs - np.floor(cv.U * ribs)
    bulge = np.sin(np.pi * t) ** 0.6
    cv.rgb[:] = mix(darken(s, 0.25) * np.ones_like(cv.rgb), cv.rgb, bulge[..., None])
    cv.rgb[:] = mix(cv.rgb, lighten(s, 0.25), (np.clip(1 - np.abs(t - 0.38) / 0.1, 0, 1) * 0.35 * (cv.V > 0.2))[..., None])
    arc = np.minimum(t, 1 - t) * 2 * np.pi * np.maximum(cv.row_r[:, None], 1e-3) / ribs
    cv.over(cv.cover(arc - 0.006), darken(s, 0.42))
    glow, ink = hexc("#FFD25A"), k
    face = (0.5, 0.52)

    def eyes(x, y):
        return np.minimum(sd_triangle(x - 0.1, y - 0.07, 0.05), sd_triangle(x + 0.1, y - 0.07, 0.05))

    def mouth(x, y):
        d = np.maximum(sd_ellipse(x, y + 0.04, 0.17, 0.1), y + 0.035)
        for tx in (-0.05, 0.05):
            d = np.maximum(d, -sd_box(x - tx, y + 0.04, 0.018, 0.02))
        d = np.maximum(d, -sd_box(x, y + 0.13, 0.02, 0.018))
        return d

    for shape in (eyes, mouth, lambda x, y: sd_triangle(x, y - 0.0, 0.022)):
        cv.paint(face, 0.28, shape, ink, grow=0.018)
        cv.paint(face, 0.28, shape, lambda x, y: mix(hexc("#FF9A2E"), glow, np.clip(0.4 + y * 4, 0, 1)[..., None]))
    for u, v in cv.scatter(12, 0.25, 0.18, 0.85, avoid=[face]):
        if abs(u - 0.5) < 0.16 and abs(v - 0.5) < 0.2:
            continue
        cv.paint((u, v), 0.03, lambda x, y: sd_circle(x, y, 0.011), lighten(s, 0.35), alpha=0.8)


def paint_dunes(cv: Canvas, s, k):
    """Dunes: layered dune crests in warm ochre, each with a pale ridge, and sand swirls."""
    cv.base(darken(s, 0.05), lighten(s, 0.25))
    lines = [(0.34, 0.03, 2, 0.4), (0.16, 0.04, 3, 1.3), (-0.02, 0.035, 2, 2.4), (-0.2, 0.045, 3, 0.9), (-0.38, 0.03, 2, 2.9)]
    for i, (z0, amp, n, ph) in enumerate(lines):
        crest = z0 + amp * np.sin(n * cv.PHI + ph) + 0.012 * np.sin(5 * cv.PHI + ph * 2)
        below = crest - cv.Z
        cv.over(cv.cover(-below) * 0.1, darken(s, 0.25))
        w = 0.011 * (0.65 + 0.35 * np.sin(2 * cv.PHI + ph * 3))
        cv.over(cv.cover(np.abs(below) - w), mix(k, darken(k, 0.2), i / 4))
        cv.over(cv.cover(np.abs(below + 0.024) - 0.004) * 0.8, lighten(s, 0.5))
    for u, v in ((0.28, 0.62), (0.7, 0.44), (0.04, 0.5)):
        pts = []
        for m in range(60):
            a = m * 0.22
            r = 0.012 + 0.0115 * a
            pts.append((r * math.cos(a), r * math.sin(a)))
        cv.paint((u, v), 0.16, lambda x, y, pts=pts: sd_polyline(x, y, pts) - 0.008, lighten(s, 0.45), grow=0.0)
        cv.paint((u, v), 0.16, lambda x, y, pts=pts: sd_polyline(x + 0.006, y + 0.006, pts) - 0.006, k)


def night_sky(cv: Canvas, s, glow):
    cv.base(mix(s, glow, 0.25), darken(s, 0.25))
    cloud = np.clip(cv.noise(1.4, 3, 5) * 1.3, 0, 1)
    cv.over(cloud * 0.18, lighten(s, 0.35))


def paint_starlit(cv: Canvas, s, k):
    """Starlit: a painted night sky, a crescent moon, fat yellow stars and star dust."""
    night_sky(cv, s, hexc("#5D6FD0"))
    moon = (0.5, 0.72)
    crescent = lambda x, y: np.maximum(sd_circle(x, y, 0.13), -sd_circle(x - 0.065, y - 0.04, 0.115))
    cv.inked(moon, 0.16, crescent, lambda x, y: mix(hexc("#FFE680"), hexc("#FFF7C9"), np.clip(0.5 - x * 6, 0, 1)[..., None]), hexc("#C9962A"), width=0.01, rot=-0.3)
    for u, v in cv.scatter(17, 0.26, 0.1, 0.9, avoid=[moon]):
        r = cv.rng.uniform(0.06, 0.105)
        star = lambda x, y, r=r: sd_star5(x, y, r, 0.48) + 0.003
        fill = lambda x, y, r=r: mix(k, lighten(k, 0.55), np.clip(0.5 + (y - x) / r, 0, 1)[..., None])
        cv.inked((u, v), r * 1.3, star, fill, hexc("#B98722"), width=0.009, rot=cv.rng.uniform(-0.35, 0.35))
    for u, v in cv.scatter(70, 0.07, 0.06, 0.94):
        r = cv.rng.uniform(0.005, 0.011)
        cv.paint((u, v), 0.03, lambda x, y, r=r: sd_circle(x, y, r), mix(k, WHITE, cv.rng.uniform(0, 0.8)))


def paint_celestial(cv: Canvas, s, k):
    """Celestial: a deep nebula in lilac and pink, four-point stars, a constellation and a ringed planet."""
    night_sky(cv, s, hexc("#3C2F8F"))
    neb = np.clip(cv.noise(2.2, 11, 5) * 1.6 - 0.1, 0, 1)
    neb2 = np.clip(cv.noise(3.1, 17, 5) * 1.6 - 0.3, 0, 1)
    cv.over(neb * 0.35, k)
    cv.over(neb2 * 0.25, hexc("#FF9CD8"))
    planet = (0.1, 0.62)
    cv.inked(planet, 0.12, lambda x, y: sd_circle(x, y, 0.07), lambda x, y: mix(hexc("#8C7BFF"), hexc("#C9BCFF"), np.clip(0.5 + (y - x) * 6, 0, 1)[..., None]), hexc("#4A3AA8"))
    ring = lambda x, y: np.abs(sd_ellipse(x, y, 0.12, 0.03)) - 0.008
    cv.paint(planet, 0.16, ring, hexc("#FFE680"), rot=0.35)
    pts = [(0.4, 0.66), (0.47, 0.74), (0.55, 0.7), (0.6, 0.6), (0.53, 0.52)]
    line = cv.layer()
    cv.stroke(line, pts, 0.004, 0.004)
    cv.over(line * 0.7, lighten(k, 0.3))
    for uv in pts:
        cv.paint(uv, 0.06, lambda x, y: sd_sparkle(x, y, 0.045), WHITE)
    for u, v in cv.scatter(12, 0.22, 0.1, 0.9, avoid=pts + [planet]):
        r = cv.rng.uniform(0.04, 0.075)
        cv.paint((u, v), r * 1.2, lambda x, y, r=r: sd_sparkle(x, y, r), mix(k, WHITE, 0.4), grow=0.004)
    for u, v in cv.scatter(60, 0.07, 0.06, 0.94):
        r = cv.rng.uniform(0.005, 0.01)
        cv.paint((u, v), 0.03, lambda x, y, r=r: sd_circle(x, y, r), mix(k, WHITE, cv.rng.uniform(0.3, 1)))


def paint_sky(cv: Canvas, s, k):
    """Sky: blue sky fading to white, puffy clouds with blue bellies, little gold stars."""
    cv.base(lighten(s, 0.2), mix(s, hexc("#6FC0FF"), 0.8))
    cv.rgb[:] = mix(cv.rgb, lighten(s, 0.3), smoothstep(0.45, 0.05, cv.V)[..., None])
    puffs = [(-0.07, 0.0, 0.05), (-0.02, 0.03, 0.058), (0.04, 0.02, 0.05), (0.085, -0.005, 0.038), (-0.11, -0.012, 0.034)]
    clouds = cv.scatter(9, 0.42, 0.25, 0.82)
    for u, v in clouds:
        sz = cv.rng.uniform(1.35, 1.7)

        def cloud(x, y, sz=sz):
            d = None
            for px, py, r in puffs:
                e = sd_circle(x - px * sz, y - py * sz, r * sz)
                d = e if d is None else np.minimum(d, e)
            return np.maximum(d, -(y + 0.03 * sz))

        cv.inked((u, v), 0.2 * sz, cloud, WHITE, hexc("#6FA9D6"), width=0.01)
        cv.paint((u, v), 0.2 * sz, lambda x, y, sz=sz: np.maximum(cloud(x, y, sz), 0.005 * sz - y - 0.028 * sz), hexc("#D6ECFF"), grow=0)
    for u, v in cv.scatter(14, 0.22, 0.12, 0.9, avoid=clouds):
        r = cv.rng.uniform(0.042, 0.065)
        cv.inked((u, v), r * 1.4, lambda x, y, r=r: sd_star5(x, y, r, 0.5) + 0.003, k, hexc("#C9962A"), width=0.008, rot=cv.rng.uniform(-0.4, 0.4))


def paint_fissures(cv: Canvas, s, edge, glow, core, extra=None):
    """Cracks eggs: branching fissures with a dark lip, a soft glow round them and a hot core."""
    cv.base(darken(s, 0.18), lighten(s, 0.1))
    if extra:
        extra(cv, s)
    paths = []
    starts = [(0.5, 0.8, -1.4), (0.36, 0.3, 0.9), (0.64, 0.45, 1.9), (0.8, 0.72, 2.6), (0.12, 0.62, -0.4), (0.95, 0.3, 1.2)]
    for u, v, h in starts:
        main = cv.walk((u, v), h, 10, 0.08, 0.55)
        paths.append((main, 0.025, 0.006))
        for _ in range(2):
            at = main[cv.rng.integers(2, len(main) - 2)]
            paths.append((cv.walk(at, h + cv.rng.choice([-1.2, 1.2]), 5, 0.065, 0.6), 0.018, 0.004))
    halo, lip, hot = cv.layer(), cv.layer(), cv.layer()
    for path, w0, w1 in paths:
        cv.stroke(halo, path, w0 + 0.06, w1 + 0.04, soft=0.06)
        cv.stroke(lip, path, w0 + 0.012, w1 + 0.007)
        cv.stroke(hot, path, w0 * 0.6, w1 * 0.5)
    cv.over(halo * 0.75, glow)
    cv.over(lip, edge)
    cv.over(hot, core)
    for u, v in cv.scatter(18, 0.12, 0.1, 0.9):
        r = cv.rng.uniform(0.008, 0.016)
        cv.paint((u, v), 0.03, lambda x, y, r=r: sd_circle(x, y, r), mix(s, glow, 0.6), alpha=0.9)


def scales(cv: Canvas, s):
    rows = 16
    for rr in range(rows):
        v = 0.18 + 0.64 * rr / (rows - 1)
        n = max(6, int(round(2 * math.pi * float(radius_at_v(v)) / 0.09)))
        for i in range(n):
            u = (i + (0.5 if rr % 2 else 0)) / n
            cv.paint((u, v), 0.06, lambda x, y: np.maximum(np.abs(sd_circle(x, y + 0.02, 0.045)) - 0.004, y - 0.0), lighten(s, 0.16), alpha=0.8)


def paint_stampede(cv, s, k):
    paint_fissures(cv, s, k, hexc("#FFD36B"), hexc("#FFF2B8"))


def paint_raid(cv, s, k):
    paint_fissures(cv, s, darken(s, 0.5), k, hexc("#FFF6C8"))


def paint_leviathan(cv, s, k):
    paint_fissures(cv, s, darken(s, 0.55), k, WHITE, extra=scales)


def paint_titan(cv, s, k):
    """Titan Egg (glow-up TT): gold fissures glowing on a storm-purple shell, gold sparks."""
    paint_fissures(cv, s, darken(s, 0.45), k, hexc("#FFF6C8"))
    for u, v in cv.scatter(18, 0.1, 0.12, 0.88):
        cv.paint((u, v), 0.04, lambda x, y: sd_sparkle(x, y, 0.02), lighten(k, 0.35))


def paint_snow(cv: Canvas, s, k, flakes=16):
    """Snowflake eggs: crisp six-armed flakes, a frosty lower half and frost dust."""
    cv.base(mix(s, hexc("#BFE3FF"), 0.55), lighten(s, 0.4))
    for u, v in cv.scatter(flakes, 0.3, 0.12, 0.9):
        r = cv.rng.uniform(0.085, 0.13)
        fl = lambda x, y, r=r: sd_snowflake(x, y, r, 0.014)
        cv.inked((u, v), r * 1.3, fl, lambda x, y, r=r: mix(k, lighten(k, 0.45), np.clip(0.5 + (y - x) / r, 0, 1)[..., None]), darken(k, 0.3), width=0.006, rot=cv.rng.uniform(0, 1))
    for u, v in cv.scatter(40, 0.08, 0.06, 0.94):
        r = cv.rng.uniform(0.006, 0.012)
        cv.paint((u, v), 0.03, lambda x, y, r=r: sd_circle(x, y, r), mix(k, WHITE, 0.5))


def paint_frostfall(cv, s, k):
    paint_snow(cv, s, k)


def paint_glacier(cv: Canvas, s, k):
    """Glacier: a jagged blue ice floe round the bottom with shine streaks, big flakes above."""
    cv.base(mix(s, hexc("#BFE3FF"), 0.4), lighten(s, 0.4))
    tri = np.abs(((cv.PHI * 7 / (2 * np.pi)) % 1.0) - 0.5) * 2
    top = -0.1 + 0.09 * tri + 0.025 * np.sin(3 * cv.PHI + 1.1)
    below = top - cv.Z
    ice = mix(k, hexc("#3E8FD6"), 0.35)
    cv.over(cv.cover(-below - 0.012), darken(ice, 0.35))
    cv.over(cv.cover(-below), mix(lighten(ice, 0.25), darken(ice, 0.1), smoothstep(0, 0.4, below)[..., None]))
    x = cv.P[..., 0] * 0.8 + cv.Z
    streak = np.clip(1 - np.abs(np.mod(x * 6, 1.0) - 0.5) / 0.06, 0, 1) * (below > 0.05) * (cv.P[..., 1] < 0.1)
    cv.over(streak * 0.35, WHITE)
    for u, v in cv.scatter(6, 0.36, 0.55, 0.88):
        r = cv.rng.uniform(0.08, 0.11)
        fl = lambda x, y, r=r: sd_snowflake(x, y, r, 0.012)
        cv.inked((u, v), r * 1.3, fl, lambda x, y, r=r: mix(k, lighten(k, 0.45), np.clip(0.5 + (y - x) / r, 0, 1)[..., None]), darken(k, 0.3), width=0.006, rot=cv.rng.uniform(0, 1))
    for u, v in cv.scatter(30, 0.08, 0.4, 0.94):
        cv.paint((u, v), 0.04, lambda x, y: sd_sparkle(x, y, 0.02), WHITE)


PAINTERS = {
    "meadow": paint_spots,
    "grove": paint_leaves,
    "bloom": paint_flowers,
    "crystal": paint_facets,
    "royal": paint_royal,
    "pearl": paint_pearl,
    "lantern": paint_lantern,
    "splash": paint_splash,
    "harvest": paint_harvest,
    "dunes": paint_dunes,
    "starlit": paint_starlit,
    "celestial": paint_celestial,
    "sky": paint_sky,
    "stampede": paint_stampede,
    "raid": paint_raid,
    "leviathan": paint_leviathan,
    "titan": paint_titan,
    "frostfall": paint_frostfall,
    "glacier": paint_glacier,
}


# ─── Overlays ─────────────────────────────────────────────────────────────────────────────


def paint_crack(stage: int, path: Path) -> None:
    """The hatch cracks, drawn over any egg: a jagged line round the upper third that grows
    (stage 1: a nick on the front; 2: half way round with branches; 3: all the way round)."""
    cv = Canvas(40 + stage, alpha=True)
    cv.rgb[:] = hexc("#2B2320")
    spans = {1: (0.4, 0.6, 5), 2: (0.24, 0.8, 12), 3: (0.0, 1.0, 26)}
    u0, u1, teeth = spans[stage]
    v_line = v_at_z(0.2)
    path_uv = []
    for i in range(teeth + 1):
        u = u0 + (u1 - u0) * i / teeth
        dz = 0.045 * (1 if i % 2 else -1) * (0.7 + 0.3 * math.sin(i * 2.3))
        path_uv.append((u % 1.0, v_at_z(0.2 + dz)))
    branches = []
    rng = np.random.default_rng(7)
    count = {1: 1, 2: 4, 3: 8}[stage]
    for b in range(count):
        at = path_uv[int(rng.integers(1, len(path_uv) - 1))] if stage < 3 else path_uv[int((b + 0.5) * len(path_uv) / count)]
        heading = rng.choice([-1, 1]) * rng.uniform(0.9, 1.5)
        branches.append(cv.walk(at, heading, 2 + int(rng.integers(0, 2)), 0.05, 0.5))
    light, ink = cv.layer(), cv.layer()
    lo = [(u, v - 0.012) for u, v in path_uv]
    taper = 0.004 if stage < 3 else 0.012
    cv.stroke(light, lo, 0.01, 0.01)
    cv.stroke(ink, path_uv, 0.012 if stage < 3 else 0.013, taper)
    if stage < 3:
        cv.stroke(ink, list(reversed(path_uv[: len(path_uv) // 2 + 1])), 0.004, 0.013)
    for br in branches:
        cv.stroke(ink, br, 0.008, 0.002)
    cv.rgb[:] = mix(WHITE, hexc("#2B2320"), (ink > light)[..., None].astype(np.float32))
    cv.a[:] = np.maximum(ink, light * 0.65)
    cv.rgb[:] = np.where((ink >= 0.5)[..., None], hexc("#2B2320"), np.where((light > 0)[..., None], WHITE, cv.rgb))
    cv.save(path)


def paint_painted(path: Path) -> None:
    """The Spring Bloom hunt's painted egg: white zigzags and dots over a shell tinted in game."""
    cv = Canvas(77, alpha=True)
    cv.rgb[:] = hexc("#FFFDF5")
    layer = cv.layer()
    for zc in (0.2, -0.2):
        pts = []
        for i in range(29):
            u = i / 28
            pts.append((u % 1.0 if i < 28 else 0.9999, v_at_z(zc + (0.045 if i % 2 else -0.045))))
        cv.stroke(layer, pts, 0.016, 0.016)
    for zc, hw in ((0.4, 0.012), (-0.4, 0.012)):
        layer = np.maximum(layer, cv.cover(np.abs(cv.Z - zc) - hw))
    cv.over(layer * 0.96, hexc("#FFFDF5"))
    for zc, n, r in ((0.0, 16, 0.035), (0.5, 9, 0.022), (-0.5, 10, 0.026)):
        for i in range(n):
            cv.paint(((i + 0.5) / n, v_at_z(zc)), r * 2, lambda x, y, r=r: sd_circle(x, y, r), hexc("#FFFDF5"), alpha=0.96)
    cv.save(path)


SWATCHES = [
    ("gold", "#C98A14", "#FFE27A"),
    ("ruby", "#A5202A", "#FF7A80"),
    ("teal", "#1B8F8A", "#8FF2EC"),
    ("stem", "#5A3416", "#9A6A3A"),
    ("leaf", "#3E8F2F", "#8FE06A"),
    ("petal", "#F06AA8", "#FFD2E8"),
    ("centre", "#E0A21B", "#FFE680"),
    ("wing", "#D9E8F5", "#FFFFFF"),
    ("wingtip", "#F2C94C", "#FFF2B0"),
    ("ice", "#6FB8F0", "#E8F7FF"),
    ("icedeep", "#3E8FD6", "#A9DEFF"),
    ("white", "#E6E6E6", "#FFFFFF"),
]


def paint_palette(path: Path) -> None:
    """The ornaments' swatches: a 4 x 4 grid of vertical gradients (dark at the bottom)."""
    from PIL import Image

    size, cell = 256, 64
    img = np.zeros((size, size, 3), dtype=np.float32)
    for i, (_, lo, hi) in enumerate(SWATCHES):
        cx, cy = i % 4, i // 4
        t = np.linspace(1, 0, cell)[:, None, None]  # PNG row 0 = top = light
        img[cy * cell : (cy + 1) * cell, cx * cell : (cx + 1) * cell] = mix(hexc(lo), hexc(hi), t)
    Image.fromarray(np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8), "RGB").save(path)


# ─── Config and ids ───────────────────────────────────────────────────────────────────────


def read_eggs() -> list[dict]:
    text = EGGS_CONFIG.read_text(encoding="utf-8")
    eggs = []
    for m in re.finditer(r'id = "(\w+)",\s*\n\s*name = "([^"]+)"[\s\S]*?colors = \{ shell = "(#\w+)", spots = "(#\w+)" \},\s*\n\s*pattern = "(\w+)"', text):
        eggs.append({"id": m.group(1), "name": m.group(2), "shell": m.group(3), "spots": m.group(4), "pattern": m.group(5)})
    return eggs


ID = re.compile(r"^rbxassetid://\d+$")


def load_ids() -> dict:
    """Upload name -> id, read back from EggAssets.luau."""
    ids = {}
    if not ASSETS.exists():
        return ids
    section = None
    for line in ASSETS.read_text(encoding="utf-8").splitlines():
        head = re.match(r"^\t(\w+) = \{$", line)
        if head:
            section = head.group(1)
            continue
        one = re.match(r'^\t\t(\w+) = "([^"]*)",$', line)
        orn = re.match(r'^\t\t(\w+) = \{ mesh = "([^"]*)", texture = "([^"]*)"', line)
        top = re.match(r'^\t(\w+) = "([^"]*)",$', line)
        crk = re.match(r'^\tcracks = \{ "([^"]*)", "([^"]*)", "([^"]*)" \},$', line)
        if one and section == "meshes":
            ids[f"egg_{one.group(1)}"] = one.group(2)
        elif one and section == "textures":
            ids[f"egg_{one.group(1)}"] = one.group(2)
        elif orn and section == "ornaments":
            ids[f"egg_orn_{orn.group(1)}"] = orn.group(2)
            ids["egg_ornaments"] = ids.get("egg_ornaments") or orn.group(3)
        elif crk:
            for i in range(3):
                ids[f"egg_crack{i + 1}"] = crk.group(i + 1)
        elif top and top.group(1) == "painted":
            ids["egg_painted"] = top.group(2)
    return {k: v for k, v in ids.items() if v}


def write_assets(eggs: list[dict], ids: dict, offsets: dict) -> None:
    def get(name):
        return ids.get(name, "")

    lines = [
        "--[[",
        "\tEggAssets: the published egg art (tools/blender/eggs.py). Written by that tool: re-running it",
        "\tkeeps the ids and refreshes the ornament offsets; `python tools/blender/eggs.py ids ids.json`",
        '\trecords new ids. An empty id means "not published yet": EggModel draws its placeholder egg',
        "\t(or leaves the ornament / crack / paint off) until it is set.",
        "",
        "\tmeshes     shell = the smooth egg, gem = the Crystal Egg's faceted egg (1 x 1.3 x 1 studs)",
        "\tshapes     eggs drawn on a mesh other than the shell",
        "\ttextures   one painted texture per Config.Eggs id",
        "\tornaments  a small mesh for a few eggs; offset = its centre from the egg's centre, in egg",
        "\t           widths (Roblox axes, front -Z); every ornament shares the swatch texture",
        "\tcracks     the hatch crack overlays, stages 1-3 (transparent images on the egg's own mesh)",
        "\tpainted    the Spring Bloom hunt's white paint over a tinted shell (transparent image)",
        "]]",
        "",
        "return {",
        "\tmeshes = {",
        f'\t\tshell = "{get("egg_shell")}",',
        f'\t\tgem = "{get("egg_gem")}",',
        "\t},",
        "\tshapes = {",
    ]
    lines += [f'\t\t{e} = "gem",' for e in GEM_EGGS]
    lines += ["\t},", "\ttextures = {"]
    lines += [f'\t\t{e["id"]} = "{get("egg_" + e["id"])}",' for e in eggs]
    lines += ["\t},", "\tornaments = {"]
    for e in ORNAMENTS:
        o = offsets.get(e, [0, 0, 0])
        off = ", ".join(f"{x:g}" for x in o)
        lines.append(f'\t\t{e} = {{ mesh = "{get("egg_orn_" + e)}", texture = "{get("egg_ornaments")}", offset = {{ {off} }} }},')
    lines += ["\t},"]
    lines.append(f'\tcracks = {{ "{get("egg_crack1")}", "{get("egg_crack2")}", "{get("egg_crack3")}" }},')
    lines.append(f'\tpainted = "{get("egg_painted")}",')
    lines.append("}")
    ASSETS.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"[eggs] wrote {ASSETS.relative_to(ROOT)} ({sum(1 for v in ids.values() if v)} ids)", flush=True)


def record_ids(path: str) -> None:
    eggs = read_eggs()
    ids = load_ids()
    new = json.loads(Path(path).read_text(encoding="utf-8"))
    known = {"egg_shell", "egg_gem", "egg_ornaments", "egg_painted", "egg_crack1", "egg_crack2", "egg_crack3"}
    known |= {f"egg_{e['id']}" for e in eggs} | {f"egg_orn_{e}" for e in ORNAMENTS}
    for name, value in new.items():
        if name not in known:
            raise SystemExit(f"not an egg upload: {name}")
        if not ID.match(value):
            raise SystemExit(f"{name}: bad id {value!r}")
        ids[name] = value
    offsets = {}
    got = UPLOAD / "ornaments.json"
    if got.exists():
        offsets = json.loads(got.read_text(encoding="utf-8"))
    else:
        offsets = read_offsets()
    write_assets(eggs, ids, offsets)


def read_offsets() -> dict:
    offsets = {}
    if ASSETS.exists():
        for m in re.finditer(r"\t\t(\w+) = \{ mesh = \"[^\"]*\", texture = \"[^\"]*\", offset = \{ ([^}]*) \} \}", ASSETS.read_text(encoding="utf-8")):
            offsets[m.group(1)] = [float(x) for x in m.group(2).split(",")]
    return offsets


# ─── Driver ───────────────────────────────────────────────────────────────────────────────


def outline(render: Path, out: Path, px: int = 256, width: int = 7) -> None:
    """The UI's look: a #1B1B1B ink rim round the render's silhouette, on transparency."""
    from PIL import Image, ImageFilter

    img = Image.open(render).convert("RGBA")
    alpha = img.getchannel("A")
    grown = alpha.point(lambda a: 255 if a > 40 else 0).filter(ImageFilter.GaussianBlur(width * 0.55)).point(lambda a: 255 if a > 20 else 0)
    grown = grown.filter(ImageFilter.GaussianBlur(1.2))
    ink = Image.new("RGBA", img.size, INK + (0,))
    ink.putalpha(grown)
    ink.alpha_composite(img)
    ink.resize((px, px), Image.LANCZOS).save(out)


def sheet(eggs: list[dict]) -> None:
    from PIL import Image, ImageDraw, ImageFont

    cols, cell = 6, 256
    rows = math.ceil(len(eggs) / cols)
    small = 48
    width = cols * cell
    height = rows * (cell + 34) + 300 + 110
    img = Image.new("RGBA", (width, height), (244, 239, 228, 255))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("arialbd.ttf", 22)
    except OSError:
        font = ImageFont.load_default()
    for i, e in enumerate(eggs):
        x, y = (i % cols) * cell, (i // cols) * (cell + 34)
        icon = Image.open(ICONS / f"{e['id']}.png")
        img.alpha_composite(icon, (x, y))
        text = e["name"]
        tw = draw.textlength(text, font=font)
        draw.text((x + (cell - tw) / 2, y + cell), text, fill=INK, font=font)
    y = rows * (cell + 34) + 10
    extras = [("crack1", "Crack 1"), ("crack2", "Crack 2"), ("crack3", "Crack 3"), ("hunt", "Hunt egg"), ("ready", "Pad")]
    for i, (name, label) in enumerate(extras):
        path = ICONS / f"_{name}.png"
        if path.exists():
            icon = Image.open(path).resize((240, 240), Image.LANCZOS)
            img.alpha_composite(icon, (i * 256 + 8, y))
            tw = draw.textlength(label, font=font)
            draw.text((i * 256 + (256 - tw) / 2, y + 244), label, fill=INK, font=font)
    y += 300
    for i, e in enumerate(eggs):
        icon = Image.open(ICONS / f"{e['id']}.png").resize((small, small), Image.LANCZOS)
        img.alpha_composite(icon, (20 + i * (small + 34), y + 10))
    draw.text((20, y + small + 20), "At incubator size (about 48 px on a phone)", fill=INK, font=font)
    img.save(OUT / "sheet.png")
    PREVIEW.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").resize((width // 2, height // 2), Image.LANCZOS).save(PREVIEW / "sheet.jpg", quality=86)
    print(f"[eggs] sheet: {OUT / 'sheet.png'}", flush=True)


def drive(only: list[str] | None) -> None:
    eggs = read_eggs()
    missing = [e["id"] for e in eggs if e["id"] not in PAINTERS]
    if missing:
        raise SystemExit(f"no painter for: {', '.join(missing)}")
    for d in (UPLOAD, RENDERS, ICONS, WORK):
        d.mkdir(parents=True, exist_ok=True)
    todo = [e for e in eggs if not only or e["id"] in only]
    for e in todo:
        cv = Canvas(sum(map(ord, e["id"])))
        PAINTERS[e["id"]](cv, hexc(e["shell"]), hexc(e["spots"]))
        cv.save(UPLOAD / f"egg_{e['id']}.png")
        print(f"[eggs] painted {e['id']}", flush=True)
    for stage in (1, 2, 3):
        paint_crack(stage, UPLOAD / f"egg_crack{stage}.png")
    paint_painted(UPLOAD / "egg_painted.png")
    paint_palette(UPLOAD / "egg_ornaments.png")
    shell, gem = shell_mesh(), gem_mesh()
    write_mesh_json("egg_shell", shell)
    write_mesh_json("egg_gem", gem)
    job = {
        "eggs": [{**e, "shape": "gem" if e["id"] in GEM_EGGS else "shell", "ornament": e["id"] in ORNAMENTS} for e in todo],
        "all": [e["id"] for e in eggs],
        "shell": shell,
        "gem": gem,
        "swatches": [s[0] for s in SWATCHES],
        "upload": str(UPLOAD),
        "renders": str(RENDERS),
        "ornaments": list(ORNAMENTS),
    }
    (WORK / "job.json").write_text(json.dumps(job), encoding="utf-8")
    result = subprocess.run([BLENDER, "-b", "--factory-startup", "--python", str(Path(__file__)), "--", "blender", str(WORK / "job.json")], capture_output=True, text=True)
    print("\n".join(line for line in result.stdout.splitlines() if line.startswith("[eggs]")), flush=True)
    if result.returncode != 0 or "Traceback" in result.stdout + result.stderr:
        raise SystemExit(f"blender failed\n{result.stdout[-3000:]}\n{result.stderr[-3000:]}")
    for render in RENDERS.glob("*.png"):
        outline(render, ICONS / render.name)
    write_assets(eggs, load_ids(), json.loads((UPLOAD / "ornaments.json").read_text(encoding="utf-8")))
    sheet(eggs)


if __name__ == "__main__":
    try:
        import bpy  # noqa: F401

        IN_BLENDER = True
    except ImportError:
        IN_BLENDER = False
    if IN_BLENDER:
        sys.path.insert(0, str(HERE))
        import eggs_blender

        eggs_blender.main(sys.argv[sys.argv.index("--") + 1 :])
    elif len(sys.argv) >= 3 and sys.argv[1] == "ids":
        record_ids(sys.argv[2])
    else:
        drive(sys.argv[1].split(",") if len(sys.argv) > 1 else None)
