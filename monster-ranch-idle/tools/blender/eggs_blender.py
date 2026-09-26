"""The Blender half of eggs.py (run by it; not meant to be run by hand):

  blender -b --factory-startup --python tools/blender/eggs.py -- blender art/eggs/work/job.json

Models the ornaments (a crown for Royal, a stem and leaf for Harvest, a flower for Bloom, little
wings for Sky, frost crystals for Glacier) from primitives, each part coloured by a swatch of the
shared palette texture (egg_ornaments.png: a vertical gradient per swatch, so every part is darker
underneath), exports them in publish_meshes.luau's mesh.json format with their offsets from the egg's
centre (upload/ornaments.json), and renders every egg, the crack stages and the hunt egg on
transparency for the icons and the contact sheet.
"""

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import eggs  # noqa: E402

RENDER_PX = 512


# ─── Ornament parts ───────────────────────────────────────────────────────────────────────


class Parts:
    """Accumulates parts (vertices, faces, per-vertex swatch shade) into one mesh."""

    def __init__(self, swatches):
        self.swatches = swatches
        self.verts, self.faces, self.face_uvs, self.smooth = [], [], [], []

    def add(self, bm, matrix, swatch, axis=(0, 0, 1), smooth=True):
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.transform(matrix)
        if matrix.determinant() < 0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        ax = Vector(axis).normalized()
        heights = [v.co.dot(ax) for v in bm.verts]
        lo, hi = min(heights), max(heights)
        i = self.swatches.index(swatch)
        cx, cy = i % 4, i // 4
        u = (cx + 0.5) / 4
        v_bottom = 1 - (cy + 1) / 4
        base = len(self.verts)
        bm.verts.index_update()
        shade = {}
        for v, h in zip(bm.verts, heights):
            t = (h - lo) / (hi - lo) if hi > lo else 0.5
            shade[v.index] = (u, v_bottom + (0.1 + 0.8 * t) / 4)
            self.verts.append(v.co.copy())
        for f in bm.faces:
            self.faces.append([base + v.index for v in f.verts])
            self.face_uvs.append([shade[v.index] for v in f.verts])
            self.smooth.append(smooth)
        bm.free()

    def object(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        uv = me.uv_layers.new(name="UVMap")
        k = 0
        for poly, uvs, smooth in zip(me.polygons, self.face_uvs, self.smooth):
            poly.use_smooth = smooth
            for j, loop in enumerate(poly.loop_indices):
                uv.data[loop].uv = uvs[j]
            k += 1
        me.update()
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def sphere(rx, ry, rz, segs=16, rings=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    bm.transform(Matrix.Diagonal((rx, ry, rz, 1)))
    return bm


def prism(r, h, tip, sides=6):
    """A crystal: a hexagonal prism standing on z = 0 with a pointed top."""
    bm = bmesh.new()
    low, high = [], []
    for k in range(sides):
        a = 2 * math.pi * k / sides
        low.append(bm.verts.new((r * math.cos(a), r * math.sin(a), 0)))
        high.append(bm.verts.new((r * math.cos(a), r * math.sin(a), h)))
    apex = bm.verts.new((0, 0, h + tip))
    for k in range(sides):
        n = (k + 1) % sides
        bm.faces.new((low[k], low[n], high[n], high[k]))
        bm.faces.new((high[k], high[n], apex))
    bm.faces.new(list(reversed(low)))
    return bm


def tube(path, radii, segs=10):
    """A closed tube along path (list of Vectors) with a radius per point."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(path):
        d = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        side = d.cross(Vector((0, 1, 0)) if abs(d.y) < 0.9 else Vector((1, 0, 0))).normalized()
        up = d.cross(side).normalized()
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            ring.append(bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * radii[i]))
        rings.append(ring)
    for r0, r1 in zip(rings[:-1], rings[1:]):
        for k in range(segs):
            n = (k + 1) % segs
            bm.faces.new((r0[k], r0[n], r1[n], r1[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return bm


def egg_radius(z):
    return float(eggs.radius_at_v(eggs.v_at_z(z)))


def about(point, matrix):
    p = Matrix.Translation(Vector(point))
    return p @ matrix @ p.inverted()


def crown(parts):
    z0 = 0.47
    rb = egg_radius(z0) + 0.004
    rt = rb * 1.2
    n = 10
    t = 0.024
    bm = bmesh.new()
    ob, ot, ib, it = [], [], [], []
    for k in range(n):
        a = 2 * math.pi * k / n - math.pi / 2
        h = 0.2 if k % 2 == 0 else 0.1
        ob.append(bm.verts.new((rb * math.cos(a), rb * math.sin(a), z0)))
        ot.append(bm.verts.new((rt * math.cos(a), rt * math.sin(a), z0 + h)))
        ib.append(bm.verts.new(((rb - t) * math.cos(a), (rb - t) * math.sin(a), z0)))
        it.append(bm.verts.new(((rt - t) * math.cos(a), (rt - t) * math.sin(a), z0 + h)))
    for k in range(n):
        m = (k + 1) % n
        bm.faces.new((ob[k], ob[m], ot[m], ot[k]))
        bm.faces.new((ib[m], ib[k], it[k], it[m]))
        bm.faces.new((ot[k], ot[m], it[m], it[k]))
        bm.faces.new((ob[m], ob[k], ib[k], ib[m]))
    tilt = about((0, 0, z0), Matrix.Rotation(math.radians(9), 4, "X") @ Matrix.Rotation(math.radians(-6), 4, "Y"))
    parts.add(bm, tilt, "gold", smooth=False)
    # A rim round the base, balls on the points, a jewel on the front.
    ring = [Vector((rb * 1.03 * math.cos(2 * math.pi * k / 24), rb * 1.03 * math.sin(2 * math.pi * k / 24), z0 + 0.018)) for k in range(25)]
    parts.add(tube(ring, [0.02] * 25, 8), tilt, "gold")
    for k in range(0, n, 2):
        a = 2 * math.pi * k / n - math.pi / 2
        parts.add(sphere(0.03, 0.03, 0.03, 12, 8), tilt @ Matrix.Translation((rt * math.cos(a), rt * math.sin(a), z0 + 0.215)), "ruby")
    parts.add(sphere(0.038, 0.02, 0.045, 12, 8), tilt @ Matrix.Translation((0, -(rb + 0.012), z0 + 0.075)), "teal")


def stem_and_leaf(parts):
    base = Vector((0.0, 0.0, 0.6))
    path = [base + Vector((0.05 * t * t, 0.01 * t, 0.17 * t)) for t in [i / 6 for i in range(7)]]
    parts.add(tube(path, [0.042 - 0.014 * i / 6 for i in range(7)], 12), Matrix.Identity(4), "stem")
    parts.add(sphere(0.03, 0.03, 0.012, 12, 6), Matrix.Translation(path[-1]), "stem")
    for angle, length, droop in ((205, 0.3, 0.1), (330, 0.2, 0.08)):
        bm = sphere(length / 2, length * 0.22, 0.014, 18, 8)
        for v in bm.verts:
            s = (v.co.x + length / 2) / length
            v.co.z -= droop * s * s
            v.co.z += 0.05 * (v.co.y / (length * 0.22)) ** 2 * 0.3
        m = Matrix.Translation(base + Vector((0, 0, 0.05))) @ Matrix.Rotation(math.radians(angle), 4, "Z") @ Matrix.Rotation(math.radians(-12), 4, "Y") @ Matrix.Translation((length / 2, 0, 0))
        parts.add(bm, m, "leaf", axis=(0, 0, 1))
    curl = []
    for i in range(22):
        a = i * 0.45
        r = 0.02 + 0.004 * i
        curl.append(base + Vector((-0.03 + r * math.cos(a) * 0.8, 0.03 + r * math.sin(a) * 0.8, 0.07 + 0.004 * i)))
    parts.add(tube(curl, [0.008] * len(curl), 6), Matrix.Identity(4), "leaf")


def flower(parts):
    tilt = Matrix.Translation((0.0, -0.12, 0.61)) @ Matrix.Rotation(math.radians(26), 4, "X") @ Matrix.Diagonal((1.55, 1.55, 1.55, 1))
    for k, angle in enumerate((40, 220)):
        m = tilt @ Matrix.Rotation(math.radians(angle), 4, "Z") @ Matrix.Translation((0.09, 0, -0.015)) @ Matrix.Rotation(math.radians(-10), 4, "Y")
        parts.add(sphere(0.085, 0.034, 0.012, 16, 8), m, "leaf")
    for k in range(5):
        m = tilt @ Matrix.Rotation(math.radians(72 * k + 18), 4, "Z") @ Matrix.Translation((0.062, 0, 0.012)) @ Matrix.Rotation(math.radians(-14), 4, "Y")
        parts.add(sphere(0.07, 0.046, 0.017, 16, 8), m, "petal", axis=(0, 0, 1))
    parts.add(sphere(0.04, 0.04, 0.028, 16, 8), tilt @ Matrix.Translation((0, 0, 0.03)), "centre")


def wings(parts):
    for side in (1, -1):
        root = Vector((side * 0.43, 0.04, 0.1))
        for k, (length, width, angle) in enumerate(((0.36, 0.1, 14), (0.3, 0.09, 36), (0.23, 0.08, 58))):
            m = (
                Matrix.Translation(root)
                @ Matrix.Rotation(math.radians(side * 12), 4, "Z")
                @ Matrix.Rotation(math.radians(-angle * side), 4, "Y")
                @ Matrix.Translation((side * length / 2, 0, 0))
            )
            parts.add(sphere(length / 2, 0.022, width / 2, 16, 8), m, "wing" if k else "wingtip", axis=(side, 0, 0.6))


def frost(parts):
    base = Vector((0.0, 0.0, 0.55))
    parts.add(prism(0.075, 0.21, 0.12), Matrix.Translation(base), "ice", smooth=False)
    for az, tilt, r, h in ((25, 32, 0.055, 0.14), (115, 38, 0.045, 0.1), (200, 30, 0.06, 0.15), (290, 40, 0.042, 0.09), (160, 55, 0.034, 0.07)):
        m = Matrix.Translation(base) @ Matrix.Rotation(math.radians(az), 4, "Z") @ Matrix.Rotation(math.radians(tilt), 4, "Y")
        parts.add(prism(r, h, r * 1.6), m, "icedeep" if az in (115, 290) else "ice", smooth=False)


BUILDERS = {"royal": crown, "harvest": stem_and_leaf, "bloom": flower, "sky": wings, "glacier": frost}


def export_ornament(obj, name):
    """mesh.json of the ornament, centred on its box; returns the offset (Roblox axes, egg units)."""
    me = obj.data
    me.calc_loop_triangles()
    uv = me.uv_layers.active.data
    normals = me.corner_normals
    positions, norms, uvs, tris = [], [], [], []
    for tri in me.loop_triangles:
        corner = []
        for loop in tri.loops:
            p = me.vertices[me.loops[loop].vertex_index].co
            n = normals[loop].vector
            positions.append([p.x, p.y, p.z])
            norms.append([n.x, n.y, n.z])
            uvs.append([uv[loop].uv.x, uv[loop].uv.y])
            corner.append(len(positions) - 1)
        tris.append(corner)
    lo = [min(p[i] for p in positions) for i in range(3)]
    hi = [max(p[i] for p in positions) for i in range(3)]
    centre = [(a + b) / 2 for a, b in zip(lo, hi)]
    eggs.write_mesh_json(name, {"positions": positions, "normals": norms, "uvs": uvs, "tris": tris}, centre)
    offset = eggs.C_AXES @ eggs.np.asarray(centre)
    return [round(float(x), 4) for x in offset]


# ─── Rendering ────────────────────────────────────────────────────────────────────────────


def material(name, image=None, color=None, rough=0.55, alpha=False):
    mat = bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except AttributeError:
        pass
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    if image:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(image, check_existing=True)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha:
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            if hasattr(mat, "surface_render_method"):
                mat.surface_render_method = "BLENDED"
    if color is not None:
        bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Specular IOR Level"].default_value = 0.3
    return mat


def mesh_object(name, m, smooth, mat, scale=1.0):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in m["positions"]], [], [tuple(t) for t in m["tris"]])
    uv = me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        uv.data[loop.index].uv = m["uvs"][loop.vertex_index]
    if smooth:
        me.shade_smooth()
        me.normals_split_custom_set_from_vertices([tuple(n) for n in m["normals"]])
    else:
        me.shade_flat()
    me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    obj.scale = (scale, scale, scale)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = scene.render.resolution_y = RENDER_PX
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.78, 0.83, 0.92, 1)
    bg.inputs[1].default_value = 0.85
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 2.6
    sun.data.angle = math.radians(12)
    sun.rotation_euler = (math.radians(42), math.radians(-18), math.radians(-30))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.95
    az, el = math.radians(-24), math.radians(12)
    eye = Vector((math.sin(-az) * 6, -math.cos(az) * 6, 6 * math.tan(el) + 0.06))
    cam.location = eye
    cam.rotation_euler = (Vector((0, 0, 0.06)) - eye).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam
    return scene


def render(scene, path):
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def clear(objs):
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)


def main(args):
    job = json.loads(Path(args[1]).read_text(encoding="utf-8"))
    upload, renders = Path(job["upload"]), Path(job["renders"])
    bpy.ops.wm.read_factory_settings(use_empty=True)

    palette = material("ornaments", str(upload / "egg_ornaments.png"), rough=0.45)
    ornaments, offsets = {}, {}
    for egg in job["ornaments"]:
        parts = Parts(job["swatches"])
        BUILDERS[egg](parts)
        obj = parts.object(f"orn_{egg}")
        obj.data.materials.append(palette)
        offsets[egg] = export_ornament(obj, f"egg_orn_{egg}")
        ornaments[egg] = obj
        obj.hide_render = True
    (upload / "ornaments.json").write_text(json.dumps(offsets, indent=1), encoding="utf-8")

    scene = setup_scene()
    for egg in job["eggs"]:
        shape = job[egg["shape"]]
        mat = material(egg["id"], str(upload / f"egg_{egg['id']}.png"), rough=0.2 if egg["shape"] == "gem" else 0.5)
        obj = mesh_object(egg["id"], shape, egg["shape"] == "shell", mat)
        orn = ornaments.get(egg["id"])
        if orn:
            orn.hide_render = False
        render(scene, renders / f"{egg['id']}.png")
        if orn:
            orn.hide_render = True
        clear([obj])
        print(f"[eggs] rendered {egg['id']}", flush=True)

    meadow = material("meadow_extra", str(upload / "egg_meadow.png"))
    for stage in (1, 2, 3):
        egg = mesh_object("crack_egg", job["shell"], True, meadow)
        crack = mesh_object("crack", job["shell"], True, material(f"crack{stage}", str(upload / f"egg_crack{stage}.png"), alpha=True), eggs.CRACK_SCALE)
        render(scene, renders / f"_crack{stage}.png")
        clear([egg, crack])
    hunt = mesh_object("hunt", job["shell"], True, material("hunt", color=(1.0, 0.45, 0.62), rough=0.5))
    paint = mesh_object("paint", job["shell"], True, material("paint", str(upload / "egg_painted.png"), alpha=True), 1.01)
    render(scene, renders / "_hunt.png")
    clear([hunt, paint])
    print("[eggs] rendered cracks and hunt egg", flush=True)
