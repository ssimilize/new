"""Render the six bake-off particle sprites in headless Blender, then cut them to 256 px with PIL.

    python tools/vfx/blender_sprites.py OUTDIR [--only flame,star] [--res 1024] [--fill 0.8]
                                        [--raw DIR] [--blender PATH] [--post-only]

One file, two halves:
- Run with the system python (has PIL + numpy): it launches
  `blender -b --factory-startup --python <this file> -- --render RAWDIR ...`, then post-processes.
- Run inside Blender (bpy importable): it builds each sprite scene and renders it at RES px,
  orthographic front view (camera on -Y looking +Y, X right, Z up), Cycles on the GPU (OptiX/CUDA,
  CPU fallback), Film > Transparent, view transform Standard (so ramp colours come out exact).

Every sprite is rendered twice: `tint` (white / grey materials: luminance carries the shading, for
ParticleEmitter.Color) and `color` (natural colour). Surfaces use emission-only "fake lit" shaders
(N.L driven colour ramps, facing ramps, toon specular) so there are no lights to balance; the flame
is an emission+absorption volume shaped by a node-built SDF, the wisp a lit Principled Volume.

Post: premultiply, trim to the alpha bbox, centre, scale so the longer side fills FILL of the frame
(LANCZOS on premultiplied data), un-premultiply, and bleed colour into the fully transparent pixels
(so bilinear/mip filtering in Roblox never pulls in black). Writes `<sprite>.png`,
`<sprite>_color.png`, `contact.png` (dark #202028 and light #E8E8E8 strips, plus 24 px thumbnails).

Adding a sprite: write a `build_<name>(variant)` that adds objects around the origin within about
+-1.2 units and register it in BUILDERS.
"""
import argparse
import json
import math
import os
import subprocess
import sys
import time

SPRITES = ["flame", "droplet", "leaf", "bolt", "star", "wisp"]
VARIANTS = ["tint", "color"]
BLENDER_DEFAULT = r"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe"

try:
    import bpy  # noqa: F401
    import mathutils
except ImportError:
    bpy = None


# ----------------------------------------------------------------------------------------------
# Blender half
# ----------------------------------------------------------------------------------------------

def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def col(x, a=1.0):
    """sRGB hex '#rrggbb' or a grey level 0..1 (display value) -> linear RGBA tuple."""
    if isinstance(x, (int, float)):
        v = _lin(float(x))
        return (v, v, v, a)
    h = x.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return (_lin(r), _lin(g), _lin(b), a)


def norm(v):
    l = math.sqrt(sum(c * c for c in v))
    return tuple(c / l for c in v)


LIGHT = norm((-0.55, -0.65, 0.6))   # towards the key light: upper-left, towards camera
VIEW = (0.0, -1.0, 0.0)             # towards the camera


class NB:
    """Tiny shader-node builder: numbers become default values, sockets become links."""

    def __init__(self, name):
        self.mat = bpy.data.materials.new(name)
        try:
            self.mat.use_nodes = True
        except Exception:
            pass
        self.nt = self.mat.node_tree
        for n in list(self.nt.nodes):
            self.nt.nodes.remove(n)
        self.out = self.new("ShaderNodeOutputMaterial")

    def new(self, t):
        return self.nt.nodes.new(t)

    def _in(self, sock, v):
        if v is None:
            return
        if isinstance(v, bpy.types.NodeSocket):
            self.nt.links.new(v, sock)
        else:
            sock.default_value = v

    def m(self, op, a, b=None, c=None, clamp=False):
        n = self.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        self._in(n.inputs[0], a)
        self._in(n.inputs[1], b)
        self._in(n.inputs[2], c)
        return n.outputs[0]

    def clamp(self, a):
        return self.m("ADD", a, 0.0, clamp=True)

    def vm(self, op, a, b=None):
        n = self.new("ShaderNodeVectorMath")
        n.operation = op
        self._in(n.inputs[0], a)
        self._in(n.inputs[1], b)
        if op in ("DOT_PRODUCT", "LENGTH", "DISTANCE"):
            return n.outputs["Value"]
        return n.outputs["Vector"]

    def sep(self, v):
        n = self.new("ShaderNodeSeparateXYZ")
        self._in(n.inputs[0], v)
        return n.outputs[0], n.outputs[1], n.outputs[2]

    def comb(self, x, y, z):
        n = self.new("ShaderNodeCombineXYZ")
        self._in(n.inputs[0], x)
        self._in(n.inputs[1], y)
        self._in(n.inputs[2], z)
        return n.outputs[0]

    def tc(self, kind="Object"):
        return self.new("ShaderNodeTexCoord").outputs[kind]

    def normal(self):
        return self.new("ShaderNodeNewGeometry").outputs["Normal"]

    def facing(self, blend=0.5):
        n = self.new("ShaderNodeLayerWeight")
        n.inputs["Blend"].default_value = blend
        return n.outputs["Facing"]

    def smooth(self, v, lo, hi):
        n = self.new("ShaderNodeMapRange")
        n.interpolation_type = "SMOOTHSTEP"
        self._in(n.inputs["Value"], v)
        n.inputs["From Min"].default_value = lo
        n.inputs["From Max"].default_value = hi
        n.inputs["To Min"].default_value = 0.0
        n.inputs["To Max"].default_value = 1.0
        return n.outputs["Result"]

    def noise(self, vec, scale=2.0, detail=3.0, rough=0.5, w=None, distortion=0.0):
        n = self.new("ShaderNodeTexNoise")
        n.noise_dimensions = "4D"
        self._in(n.inputs["Vector"], vec)
        self._in(n.inputs["W"], 0.0 if w is None else w)
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        n.inputs["Distortion"].default_value = distortion
        return n.outputs["Fac"]

    def ramp(self, fac, stops, interp="LINEAR"):
        n = self.new("ShaderNodeValToRGB")
        cr = n.color_ramp
        cr.interpolation = interp
        el = cr.elements
        el[0].position, el[0].color = stops[0][0], stops[0][1]
        el[1].position, el[1].color = stops[-1][0], stops[-1][1]
        for pos, c in stops[1:-1]:
            e = el.new(pos)
            e.color = c
        self._in(n.inputs["Fac"], fac)
        return n.outputs["Color"]

    def mixc(self, fac, a, b):
        n = self.new("ShaderNodeMix")
        n.data_type = "RGBA"
        n.blend_type = "MIX"
        n.clamp_factor = True
        self._in(n.inputs[0], fac)
        ia = [s for s in n.inputs if s.name == "A" and s.type == "RGBA"][0]
        ib = [s for s in n.inputs if s.name == "B" and s.type == "RGBA"][0]
        self._in(ia, a)
        self._in(ib, b)
        return [s for s in n.outputs if s.type == "RGBA"][0]

    def emission(self, color, strength=1.0):
        n = self.new("ShaderNodeEmission")
        self._in(n.inputs["Color"], color)
        self._in(n.inputs["Strength"], strength)
        return n.outputs[0]

    def with_alpha(self, shader, alpha):
        t = self.new("ShaderNodeBsdfTransparent").outputs[0]
        n = self.new("ShaderNodeMixShader")
        self._in(n.inputs[0], alpha)
        self._in(n.inputs[1], t)
        self._in(n.inputs[2], shader)
        return n.outputs[0]

    def add(self, a, b):
        n = self.new("ShaderNodeAddShader")
        self._in(n.inputs[0], a)
        self._in(n.inputs[1], b)
        return n.outputs[0]

    def surface(self, s):
        self.nt.links.new(s, self.out.inputs["Surface"])
        return self.mat

    def volume(self, s):
        self.nt.links.new(s, self.out.inputs["Volume"])
        return self.mat


def make_obj(name, verts, faces, mat=None, smooth=False, uvs=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    if uvs is not None:
        uv = me.uv_layers.new(name="UVMap")
        for poly in me.polygons:
            for li in poly.loop_indices:
                uv.data[li].uv = uvs[me.loops[li].vertex_index]
    if smooth:
        try:
            me.shade_smooth()
        except AttributeError:
            for p in me.polygons:
                p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if mat is not None:
        me.materials.append(mat)
    return ob


def make_curve(name, paths, bevel, mat, res=6):
    """paths: list of point lists [(x, z, radius), ...] in the XZ plane."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = bevel
    cu.bevel_resolution = res
    cu.use_fill_caps = True
    for pts in paths:
        sp = cu.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for i, (x, z, r) in enumerate(pts):
            sp.points[i].co = (x, 0.0, z, 1.0)
            sp.points[i].radius = r
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    cu.materials.append(mat)
    return ob


def fan_mesh(name, boundary, mat, centre=(0.0, 0.0, 0.0)):
    verts = [centre] + list(boundary)
    n = len(boundary)
    faces = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
    return make_obj(name, verts, faces, mat)


def cube_obj(name, half, mat):
    h = half
    v = [(-h, -h, -h), (h, -h, -h), (h, h, -h), (-h, h, -h),
         (-h, -h, h), (h, -h, h), (h, h, h), (-h, h, h)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return make_obj(name, v, f, mat)


def sphere_obj(name, mat, nu=32, nv=16):
    verts = [(0.0, 0.0, 1.0)]
    for j in range(1, nv):
        th = math.pi * j / nv
        for i in range(nu):
            ph = 2 * math.pi * i / nu
            verts.append((math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)))
    verts.append((0.0, 0.0, -1.0))
    faces = []
    for i in range(nu):
        faces.append((0, 1 + i, 1 + (i + 1) % nu))
    for j in range(nv - 2):
        a, b = 1 + j * nu, 1 + (j + 1) * nu
        for i in range(nu):
            i2 = (i + 1) % nu
            faces.append((a + i, b + i, b + i2, a + i2))
    last = len(verts) - 1
    a = 1 + (nv - 2) * nu
    for i in range(nu):
        faces.append((a + i, last, a + (i + 1) % nu))
    return make_obj(name, verts, faces, mat, smooth=True)


def clear_scene():
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                 bpy.data.lights, bpy.data.cameras, bpy.data.worlds):
        for item in list(coll):
            coll.remove(item)


def setup_scene(res, samples, ambient=0.0):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "GPU" if DEVICE != "CPU" else "CPU"
    sc.render.resolution_x = res
    sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    sc.view_settings.gamma = 1.0
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.transparent_max_bounces = 32
    w = bpy.data.worlds.new("World")
    sc.world = w
    try:
        w.use_nodes = True
    except Exception:
        pass
    bg = w.node_tree.nodes.get("Background")
    if bg is None:
        bg = w.node_tree.nodes.new("ShaderNodeBackground")
        w.node_tree.links.new(bg.outputs[0], w.node_tree.nodes.new("ShaderNodeOutputWorld").inputs[0])
    bg.inputs["Color"].default_value = (1, 1, 1, 1)
    bg.inputs["Strength"].default_value = ambient
    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.ortho_scale = 2.7
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    cam.location = (0.0, -10.0, 0.0)
    cam.rotation_euler = (math.pi / 2, 0.0, 0.0)
    sc.camera = cam


def add_sun(direction_to_light, strength, angle_deg=4.0):
    ld = bpy.data.lights.new("Sun", "SUN")
    ld.energy = strength
    ld.angle = math.radians(angle_deg)
    ob = bpy.data.objects.new("Sun", ld)
    bpy.context.scene.collection.objects.link(ob)
    d = mathutils.Vector(direction_to_light).normalized()
    ob.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    return ob


# --- the sprites -----------------------------------------------------------------------------

def build_flame(v):
    """Emission + absorption volume in a cube; density is a node-built teardrop SDF (ball + tapered
    tongue + a side lick), swayed along height and eroded by noise. Core emission is boosted so it
    clips to white (colour: clips through yellow)."""
    if v == "tint":
        stops = [(0.0, col(0.62)), (0.35, col(0.82)), (0.7, col(1.0))]
    else:
        stops = [(0.0, col("#E8361C")), (0.3, col("#FF7A1A")), (0.6, col("#FFC23A")), (0.9, col("#FFF6D0"))]
    g = NB("flame")
    p = g.tc("Object")
    x, y, z = g.sep(p)
    t = g.m("MULTIPLY_ADD", z, 0.5, 0.5, clamp=True)            # 0 bottom .. 1 top
    sway = g.m("SINE", g.m("MULTIPLY_ADD", z, 3.6, 0.9))
    x2 = g.m("ADD", x, g.m("MULTIPLY", g.m("MULTIPLY", t, 0.11), sway))
    x2 = g.m("SUBTRACT", x2, g.m("MULTIPLY", g.m("MULTIPLY", t, t), 0.16))
    zc, R, ztip = -0.45, 0.50, 0.98
    # base ball
    f1 = g.m("SUBTRACT", 1.0, g.m("DIVIDE", g.vm("LENGTH", g.comb(x2, y, g.m("SUBTRACT", z, zc))), R))
    # main tongue
    rad = g.m("MULTIPLY", R, g.m("POWER", g.clamp(g.m("DIVIDE", g.m("SUBTRACT", ztip, z), ztip - zc)), 0.78))
    rxy = g.vm("LENGTH", g.comb(x2, y, 0.0))
    f2 = g.m("SUBTRACT", 1.0, g.m("DIVIDE", rxy, g.m("ADD", rad, 0.002)))
    f2 = g.m("MULTIPLY", f2, g.m("GREATER_THAN", z, zc))
    # side lick on the right, leaning out
    x3 = g.m("SUBTRACT", g.m("SUBTRACT", x2, 0.30), g.m("MULTIPLY", g.m("MULTIPLY", t, t), 0.25))
    zt3, zb3, R3 = 0.36, -0.40, 0.22
    rad3 = g.m("MULTIPLY", R3, g.m("POWER", g.clamp(g.m("DIVIDE", g.m("SUBTRACT", zt3, z), zt3 - zb3)), 0.9))
    f3 = g.m("SUBTRACT", 1.0, g.m("DIVIDE", g.vm("LENGTH", g.comb(x3, y, 0.0)), g.m("ADD", rad3, 0.002)))
    f3 = g.m("MULTIPLY", f3, g.smooth(z, zb3, zb3 + 0.25))
    f = g.clamp(g.m("MAXIMUM", g.m("MAXIMUM", f1, f2), g.m("MULTIPLY", f3, 0.8)))
    nz = g.noise(g.vm("MULTIPLY", p, (1.0, 1.0, 0.55)), scale=3.0, detail=3.0, rough=0.5, w=1.7)
    fe = g.m("MULTIPLY", f, g.m("MULTIPLY_ADD", nz, 0.8, 0.6))
    dens = g.smooth(fe, 0.03, 0.16)
    heat = g.smooth(f, 0.0, 0.75)
    color = g.ramp(heat, stops)
    K = 6.0
    strength = g.m("MULTIPLY", dens, g.m("MULTIPLY_ADD", g.m("MULTIPLY", heat, heat), K * 4.0, K))
    absn = g.new("ShaderNodeVolumeAbsorption")
    absn.inputs["Color"].default_value = (0, 0, 0, 1)
    g._in(absn.inputs["Density"], g.m("MULTIPLY", dens, K))
    mat = g.volume(g.add(absn.outputs[0], g.emission(color, strength)))
    cube_obj("flame", 1.0, mat)
    return 64


def build_droplet(v):
    """Revolved teardrop mesh, emission 'toon' shader: N.L ramp, bounce light bottom-right,
    darker rim for the silhouette, crisp N.H specular blob top-left."""
    if v == "tint":
        P = dict(shadow=0.58, base=0.78, light=0.92, bounce=0.97, rim=0.5, spec=1.0)
        P = {k: col(c) for k, c in P.items()}
    else:
        P = dict(shadow="#1E66D8", base="#3B9BFF", light="#7CCBFF", bounce="#9BEBFF",
                 rim="#1A4FB8", spec="#FFFFFF")
        P = {k: col(c) for k, c in P.items()}
    NR, NU, m = 48, 48, 1.25
    verts = [(0.0, 0.0, 1.0)]
    for i in range(1, NR):
        th = math.pi * i / NR
        r = math.sin(th) * math.sin(th / 2) ** m
        for j in range(NU):
            ph = 2 * math.pi * j / NU
            verts.append((r * math.cos(ph), r * math.sin(ph), math.cos(th)))
    verts.append((0.0, 0.0, -1.0))
    faces = [(0, 1 + j, 1 + (j + 1) % NU) for j in range(NU)]
    for i in range(NR - 2):
        a, b = 1 + i * NU, 1 + (i + 1) * NU
        for j in range(NU):
            j2 = (j + 1) % NU
            faces.append((a + j, b + j, b + j2, a + j2))
    last = len(verts) - 1
    a = 1 + (NR - 2) * NU
    faces += [(a + j, last, a + (j + 1) % NU) for j in range(NU)]
    g = NB("droplet")
    N = g.normal()
    nl = g.vm("DOT_PRODUCT", N, LIGHT)
    c = g.ramp(nl, [(0.0, P["shadow"]), (0.45, P["base"]), (0.85, P["light"])], "EASE")
    nb = g.vm("DOT_PRODUCT", N, norm((0.75, -0.45, -0.55)))
    c = g.mixc(g.m("MULTIPLY", g.smooth(nb, 0.35, 0.6), 0.85), c, P["bounce"])
    rim = g.smooth(g.facing(0.5), 0.78, 0.92)
    c = g.mixc(rim, c, P["rim"])
    H = norm(tuple(a + b for a, b in zip(LIGHT, VIEW)))
    spec = g.smooth(g.vm("DOT_PRODUCT", N, H), 0.955, 0.965)
    c = g.mixc(spec, c, P["spec"])
    ob = make_obj("droplet", verts, faces, g.surface(g.emission(c)), smooth=True)
    ob.scale = (0.95, 0.95, 1.0)
    return 16


def build_leaf(v):
    """Two half-blades folded along the midrib (crisp two-tone), slight curl + bend, UV (u, t)
    drives midrib, side veins and a darker outline; separate stem tube. Emission toon shader."""
    if v == "tint":
        P = dict(shadow=0.66, mid=0.82, light=0.95, midrib=1.0, outline=0.5, stem=0.6)
    else:
        P = dict(shadow="#3E9A3A", mid="#5CC244", light="#94E264", midrib="#DDF8A8",
                 outline="#2A7430", stem="#3F8A34")
    P = {k: col(c) for k, c in P.items()}
    NT, NU = 64, 12
    W, L = 0.46, 1.9

    def pos(u, t):
        w = W * math.sin(math.pi * t ** 0.8)
        x = u * w + 0.07 * math.sin(math.pi * t)
        y = -0.32 * abs(u) * w + 0.22 * (t - 0.5) ** 2
        return (x, y, -L / 2 + L * t)

    verts, faces, uvs = [], [], []
    for side in (1, -1):
        base = len(verts)
        for i in range(NT + 1):
            t = i / NT
            for j in range(NU + 1):
                u = side * j / NU
                verts.append(pos(u, t))
                uvs.append((u, t))
        for i in range(NT):
            for j in range(NU):
                a = base + i * (NU + 1) + j
                b = a + NU + 1
                q = (a, a + 1, b + 1, b) if side == 1 else (a, b, b + 1, a + 1)
                faces.append(q)
    g = NB("leaf")
    u, t, _ = g.sep(g.tc("UV"))
    au = g.m("ABSOLUTE", u)
    nl = g.vm("DOT_PRODUCT", g.normal(), LIGHT)
    c = g.ramp(nl, [(0.25, P["shadow"]), (0.45, P["mid"]), (0.75, P["light"])], "EASE")
    c = g.mixc(g.m("MULTIPLY", t, 0.3), c, P["light"])
    # side veins: lines running from the midrib out towards the tip
    q = g.m("MULTIPLY", g.m("SUBTRACT", t, g.m("MULTIPLY", au, 0.32)), 7.0)
    dv = g.m("ABSOLUTE", g.m("SUBTRACT", g.m("FRACT", q), 0.5))
    vein = g.smooth(dv, 0.40, 0.47)
    vein = g.m("MULTIPLY", vein, g.m("MULTIPLY", g.smooth(au, 0.08, 0.14), g.m("SUBTRACT", 1.0, g.smooth(au, 0.6, 0.8))))
    vein = g.m("MULTIPLY", vein, g.m("MULTIPLY", g.smooth(t, 0.08, 0.16), g.m("SUBTRACT", 1.0, g.smooth(t, 0.8, 0.9))))
    c = g.mixc(g.m("MULTIPLY", vein, 0.55), c, P["midrib"])
    mr = g.m("SUBTRACT", 1.0, g.smooth(au, 0.035, 0.075))
    mr = g.m("MULTIPLY", mr, g.m("SUBTRACT", 1.0, g.smooth(t, 0.86, 0.96)))
    c = g.mixc(mr, c, P["midrib"])
    c = g.mixc(g.smooth(au, 0.9, 0.96), c, P["outline"])
    leaf = make_obj("leaf", verts, faces, g.surface(g.emission(c)), smooth=True, uvs=uvs)
    s = NB("stem")
    sc = s.ramp(s.facing(0.5), [(0.0, P["stem"]), (1.0, P["outline"])])
    stem = make_curve("stem", [[(0.0, -L / 2 + 0.05, 1.0), (-0.015, -L / 2 - 0.12, 0.9),
                                (-0.05, -L / 2 - 0.26, 0.7)]], 0.035, s.surface(s.emission(sc)))
    stem.location = (0.0, 0.02, 0.0)
    for ob in (leaf, stem):
        ob.rotation_euler = (0.0, math.radians(40.0), 0.0)
    return 16


BOLT_MAIN = [(0.31, 1.02, 0.12), (0.24, 0.88, 0.85), (-0.12, 0.38, 1.0), (0.22, 0.26, 1.0),
             (-0.20, -0.30, 0.85), (0.14, -0.40, 0.7), (-0.18, -1.0, 0.1)]
BOLT_FORK = [(-0.20, -0.30, 0.5), (-0.38, -0.46, 0.3), (-0.41, -0.64, 0.05)]


def build_bolt(v):
    """Tapered POLY curve tubes (main zigzag + a fork). Core: facing ramp white -> edge colour.
    Glow: the same curves 3.5x fatter with emission whose alpha = (1 - facing)^5 (soft bump)."""
    if v == "tint":
        core_edge, core_deep, glow = col(0.86), col(0.72), col(0.9)
    else:
        core_edge, core_deep, glow = col("#FFE45C"), col("#FFB321"), col("#FFD23A")
    g = NB("bolt_core")
    fc = g.facing(0.5)
    c = g.ramp(fc, [(0.0, col(1.0)), (0.45, col(1.0)), (0.8, core_edge), (1.0, core_deep)])
    make_curve("bolt", [BOLT_MAIN, BOLT_FORK], 0.085, g.surface(g.emission(c)))
    h = NB("bolt_glow")
    a = h.m("MULTIPLY", h.m("POWER", h.m("SUBTRACT", 1.0, h.facing(0.5)), 4.0), 0.5)
    h.surface(h.with_alpha(h.emission(glow), a))
    make_curve("bolt_glow", [BOLT_MAIN, BOLT_FORK], 0.27, h.mat)
    return 32


def build_star(v):
    """Superellipse 4-point star (vertical ray longer), a small 45-degree twin behind it, and a
    halo disc whose alpha falls off as (1 - r)^2.2. Colour from the superellipse radial param."""
    if v == "tint":
        stops = [(0.0, col(1.0)), (0.35, col(1.0)), (0.8, col(0.84)), (1.0, col(0.72))]
        halo = col(0.95)
    else:
        stops = [(0.0, col(1.0)), (0.35, col("#FFF8DC")), (0.8, col("#FFD54A")), (1.0, col("#FFB300"))]
        halo = col("#FFE58A")
    a_, b_, p = 0.72, 1.0, 0.62
    k = 2.0 / p
    bnd = []
    for i in range(256):
        ph = 2 * math.pi * i / 256
        c_, s_ = math.cos(ph), math.sin(ph)
        bnd.append((a_ * math.copysign(abs(c_) ** k, c_), 0.0, b_ * math.copysign(abs(s_) ** k, s_)))
    g = NB("star")
    x, _, z = g.sep(g.tc("Object"))
    qv = g.m("ADD", g.m("POWER", g.m("DIVIDE", g.m("ABSOLUTE", x), a_), p),
             g.m("POWER", g.m("DIVIDE", g.m("ABSOLUTE", z), b_), p))
    mat = g.surface(g.emission(g.ramp(qv, stops)))
    fan_mesh("star", bnd, mat)
    h = NB("halo")
    r = h.vm("LENGTH", h.tc("Object"))
    al = h.m("MULTIPLY", h.m("POWER", h.clamp(h.m("SUBTRACT", 1.0, r)), 2.2), 0.6)
    h.surface(h.with_alpha(h.emission(halo), al))
    disc = fan_mesh("halo", [(math.cos(2 * math.pi * i / 128), 0.0, math.sin(2 * math.pi * i / 128))
                             for i in range(128)], h.mat)
    disc.scale = (0.78, 0.78, 0.78)
    disc.location = (0.0, 0.1, 0.0)
    return 32


def _wisp_puffs(n=34):
    out = []
    for i in range(n):
        s = i / (n - 1)
        th = math.radians(210.0 + 310.0 * s)
        rho = 0.62 * (1.0 - 0.5 * s)
        out.append((0.08 + rho * math.cos(th), 0.08 + rho * math.sin(th), 0.40 * (1.0 - 0.68 * s),
                    1.0 - 0.6 * s * s))
    return out


WISP_PUFFS = _wisp_puffs()


def build_wisp(v):
    """Curling chain of volume puffs (Principled Volume, density = radial falloff x 4D noise per
    puff), lit by a soft sun from the upper left plus a white-world fill, faint self-emission."""
    if v == "tint":
        scat, emis = col(1.0), col(0.8)
    else:
        scat, emis = col("#D2B0FF"), col("#7A3AD0")
    g = NB("wisp")
    p = g.tc("Object")
    fall = g.m("POWER", g.clamp(g.m("SUBTRACT", 1.0, g.vm("LENGTH", p))), 1.3)
    wp = g.new("ShaderNodeNewGeometry").outputs["Position"]
    nz = g.noise(wp, scale=2.6, detail=4.0, rough=0.55, w=3.1, distortion=0.8)
    d = g.m("MULTIPLY", fall, g.m("MULTIPLY_ADD", nz, 1.4, 0.3))
    d = g.m("MULTIPLY", d, g.new("ShaderNodeObjectInfo").outputs["Alpha"])
    d = g.smooth(d, 0.05, 0.6)
    pv = g.new("ShaderNodeVolumePrincipled")
    pv.inputs["Color"].default_value = scat
    pv.inputs["Anisotropy"].default_value = 0.25
    g._in(pv.inputs["Density"], g.m("MULTIPLY", d, 7.0))
    pv.inputs["Emission Color"].default_value = emis
    g._in(pv.inputs["Emission Strength"], g.m("MULTIPLY", d, 1.4))
    mat = g.volume(pv.outputs[0])
    for i, (x, z, r, k) in enumerate(WISP_PUFFS):
        ob = sphere_obj("puff%d" % i, mat)
        ob.color = (1.0, 1.0, 1.0, k)
        ob.location = (x, 0.0, z)
        ob.scale = (r, r, r)
    add_sun(LIGHT, 5.0, 10.0)
    return 128


BUILDERS = {"flame": build_flame, "droplet": build_droplet, "leaf": build_leaf,
            "bolt": build_bolt, "star": build_star, "wisp": build_wisp}
AMBIENT = {"wisp": 0.8}
DEVICE = "CPU"


def setup_device():
    global DEVICE
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for dt in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = dt
            except TypeError:
                continue
            prefs.get_devices()
            gpus = [d for d in prefs.devices if d.type == dt]
            if gpus:
                for d in prefs.devices:
                    d.use = d.type == dt
                DEVICE = dt
                return
    except Exception as e:  # pragma: no cover
        print("device setup failed:", e)


def blender_main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", required=True)
    ap.add_argument("--only", default=",".join(SPRITES))
    ap.add_argument("--res", type=int, default=1024)
    a = ap.parse_args(argv)
    os.makedirs(a.render, exist_ok=True)
    setup_device()
    print("DEVICE", DEVICE)
    times = {}
    for name in a.only.split(","):
        for var in VARIANTS:
            t0 = time.time()
            clear_scene()
            setup_scene(a.res, 16, AMBIENT.get(name, 0.0))
            samples = BUILDERS[name](var)
            bpy.context.scene.cycles.samples = samples
            out = os.path.join(a.render, "%s_%s.png" % (name, var))
            bpy.context.scene.render.filepath = out
            bpy.ops.render.render(write_still=True)
            times["%s_%s" % (name, var)] = round(time.time() - t0, 2)
            print("RENDERED %s %.2fs" % (out, times["%s_%s" % (name, var)]))
    with open(os.path.join(a.render, "times.json"), "w") as f:
        json.dump({"device": DEVICE, "seconds": times}, f, indent=1)


# ----------------------------------------------------------------------------------------------
# System-python half: launch Blender, then cut / fit / bleed / contact sheet
# ----------------------------------------------------------------------------------------------

def post_one(src, dst, size=256, fill=0.8):
    import numpy as np
    from PIL import Image
    arr = np.asarray(Image.open(src).convert("RGBA")).astype(np.float32) / 255.0
    a = arr[..., 3]
    ys, xs = np.nonzero(a > 0.02)
    if len(xs) == 0:
        raise SystemExit("empty render: " + src)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    side = max(x1 - x0, y1 - y0) / fill
    pre = np.dstack([arr[..., :3] * a[..., None], a])
    H, W = a.shape
    pad = int(side)
    big = np.zeros((H + 2 * pad, W + 2 * pad, 4), np.float32)
    big[pad:pad + H, pad:pad + W] = pre
    bx0 = cx - side / 2 + pad
    by0 = cy - side / 2 + pad
    box = (bx0, by0, bx0 + side, by0 + side)
    chans = []
    for c in range(4):
        im = Image.fromarray(big[..., c], "F")
        chans.append(np.asarray(im.resize((size, size), Image.LANCZOS, box=box)))
    out = np.clip(np.dstack(chans), 0.0, None)
    alpha = np.clip(out[..., 3], 0.0, 1.0)
    rgb = out[..., :3] / np.maximum(alpha, 1e-6)[..., None]
    rgb = np.clip(rgb, 0.0, 1.0)
    # bleed: colour of (near-)transparent pixels comes from a wide blur of the premultiplied image
    bl = []
    for c in range(4):
        im = Image.fromarray(out[..., c].astype(np.float32), "F")
        im = im.resize((size // 16, size // 16), Image.BOX).resize((size, size), Image.BILINEAR)
        bl.append(np.asarray(im))
    bl = np.dstack(bl)
    bleed = np.clip(bl[..., :3] / np.maximum(bl[..., 3], 1e-6)[..., None], 0.0, 1.0)
    wgt = np.clip(alpha / 0.08, 0.0, 1.0)[..., None]
    rgb = rgb * wgt + bleed * (1.0 - wgt)
    res = np.dstack([rgb, alpha])
    Image.fromarray((res * 255.0 + 0.5).astype(np.uint8), "RGBA").save(dst)


def contact(outdir, names):
    from PIL import Image
    cell, padn = 256, 16
    rows = [("", "tint"), ("_color", "color")]
    width = padn + len(names) * (cell + padn)
    strips = []
    for bg in ((0x20, 0x20, 0x28, 255), (0xE8, 0xE8, 0xE8, 255)):
        hgt = padn + len(rows) * (cell + padn) + 24 + padn
        st = Image.new("RGBA", (width, hgt), bg)
        for ci, n in enumerate(names):
            x = padn + ci * (cell + padn)
            for ri, (suf, _) in enumerate(rows):
                p = os.path.join(outdir, n + suf + ".png")
                if not os.path.exists(p):
                    continue
                im = Image.open(p).convert("RGBA")
                st.alpha_composite(im, (x, padn + ri * (cell + padn)))
                small = im.resize((24, 24), Image.LANCZOS)
                st.alpha_composite(small, (x + ri * 40, padn + len(rows) * (cell + padn)))
        strips.append(st)
    sheet = Image.new("RGBA", (width, sum(s.height for s in strips)))
    y = 0
    for s in strips:
        sheet.paste(s, (0, y))
        y += s.height
    sheet.convert("RGB").save(os.path.join(outdir, "contact.png"))


def system_main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("outdir")
    ap.add_argument("--only", default=",".join(SPRITES))
    ap.add_argument("--res", type=int, default=1024)
    ap.add_argument("--fill", type=float, default=0.8)
    ap.add_argument("--raw", default=None, help="where the full-res renders go (default: <tempdir>/blender_sprites_raw)")
    ap.add_argument("--blender", default=BLENDER_DEFAULT)
    ap.add_argument("--post-only", action="store_true")
    a = ap.parse_args()
    names = [n for n in a.only.split(",") if n]
    bad = [n for n in names if n not in SPRITES]
    if bad or not names:
        ap.error("unknown sprite(s): %s" % bad)
    os.makedirs(a.outdir, exist_ok=True)
    import tempfile
    raw = os.path.abspath(a.raw or os.path.join(tempfile.gettempdir(), "blender_sprites_raw"))
    t0 = time.time()
    if not a.post_only:
        cmd = [a.blender, "-b", "--factory-startup", "--python", os.path.abspath(__file__), "--",
               "--render", raw, "--only", ",".join(names), "--res", str(a.res)]
        r = subprocess.run(cmd, capture_output=True, text=True)
        for line in r.stdout.splitlines():
            if line.startswith(("RENDERED", "DEVICE", "Error", "Traceback")) or "Error" in line:
                print(line)
        if r.returncode != 0:
            print(r.stdout[-4000:], r.stderr[-4000:])
            raise SystemExit("blender failed (%d)" % r.returncode)
    t1 = time.time()
    for n in names:
        post_one(os.path.join(raw, n + "_tint.png"), os.path.join(a.outdir, n + ".png"), fill=a.fill)
        post_one(os.path.join(raw, n + "_color.png"), os.path.join(a.outdir, n + "_color.png"), fill=a.fill)
    present = [n for n in SPRITES if os.path.exists(os.path.join(a.outdir, n + ".png"))]
    contact(a.outdir, present)
    print("blender %.1fs, post %.1fs" % (t1 - t0, time.time() - t1))


if __name__ == "__main__":
    if bpy is not None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
        blender_main(argv)
    else:
        system_main()
