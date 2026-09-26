"""Builds a fox-type monster from scratch in headless Blender (no AI model): a test of hand-made
procedural art against Meshy's. Cindlet is the spec below.

  blender -b --factory-startup --python tools/blender/model_fox.py -- <out dir>

How it is made:
  1. The body is a metaball: head, cheeks, muzzle, chest, body, rump, four legs, paws and a tail
     as soft blobs that melt into one smooth toy-like surface, converted to a mesh.
  2. Face and ears are separate small meshes snapped onto that surface by ray casts from the head's
     centre: glossy eyes with highlights, nose, a "w" mouth (a bevelled curve), cone ears with an
     inner ear, and a flame on the tail tip.
  3. Colours are painted per vertex from the design's own landmarks (cream muzzle and chest, gold
     forehead flame and cheek swooshes, dark paws and ear tips, a gold-to-cream tail tip).
  4. A decimated copy (about 4,800 body triangles) is the game model: it is UV-unwrapped and the
     full-detail model's colours are baked onto it (selected to active) as one 1024 texture, so the
     result is a plain textured mesh like Meshy's: the same GLB the rig script takes.

Writes <out dir>/model.glb, model.blend, texture.png.
"""

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

OUT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
OUT.mkdir(parents=True, exist_ok=True)

SURFACE = 0.575  # a metaball's visible radius per unit of radius (stiffness 2, threshold 0.6)


def srgb(hex_: str):
    return tuple(int(hex_[i : i + 2], 16) / 255 for i in (1, 3, 5))


# ─── Spec: Cindlet (ember fox, baby) ────────────────────────────────────────────────────

COLORS = {
    "fur": srgb("#F2724E"),
    "cream": srgb("#FFE0C4"),
    "gold": srgb("#FFC766"),
    "tip": srgb("#FFF0C8"),
    "dark": srgb("#7C3326"),
    "ear_tip": srgb("#A63E2C"),
    "inner_ear": srgb("#FFD98C"),
    "eye": srgb("#141216"),
    "shine": srgb("#FFFFFF"),
    "nose": srgb("#3A2320"),
}
HEAD = Vector((0, -0.08, 0.53))
MUZZLE = Vector((0, -0.30, 0.44))
FRONT_Y, BACK_Y, LEG_X = -0.06, 0.22, 0.125
TAIL = [Vector(p) for p in ((0, 0.30, 0.27), (0.0, 0.40, 0.31), (0.02, 0.48, 0.38), (0.04, 0.53, 0.47), (0.05, 0.55, 0.55))]
TAIL_R = (0.05, 0.058, 0.068, 0.078, 0.085)


def log(*parts):
    print("[model]", *parts, flush=True)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def activate(obj):
    for o in bpy.context.scene.objects:
        o.select_set(o is obj)
    bpy.context.view_layer.objects.active = obj


# ─── 1. The body ────────────────────────────────────────────────────────────────────────


def build_body():
    mb = bpy.data.metaballs.new("Body")
    mb.resolution = mb.render_resolution = 0.008
    mb.threshold = 0.6

    def ball(co, visible_r):
        e = mb.elements.new(type="BALL")
        e.co, e.radius, e.stiffness = co, visible_r / SURFACE, 2.0

    def ellipsoid(co, semi):
        r = max(semi)
        e = mb.elements.new(type="ELLIPSOID")
        e.co, e.radius, e.stiffness = co, r / SURFACE, 2.0
        e.size_x, e.size_y, e.size_z = (s / r for s in semi)

    def capsule(a, b, visible_r):
        a, b = Vector(a), Vector(b)
        e = mb.elements.new(type="CAPSULE")
        e.co, e.radius, e.stiffness = (a + b) / 2, visible_r / SURFACE, 2.0
        e.size_x = (b - a).length / 2
        e.rotation = Vector((1, 0, 0)).rotation_difference((b - a).normalized())

    ellipsoid(HEAD, (0.30, 0.26, 0.27))
    for s in (-1, 1):
        ball((s * 0.21, -0.15, 0.43), 0.10)  # cheek fluff
    ellipsoid(MUZZLE, (0.11, 0.075, 0.07))
    ball((0, -0.05, 0.28), 0.13)  # chest
    ellipsoid((0, 0.09, 0.25), (0.15, 0.21, 0.13))  # body
    ball((0, 0.21, 0.24), 0.13)  # rump
    for y in (FRONT_Y, BACK_Y):
        for s in (-1, 1):
            capsule((s * LEG_X, y, 0.07), (s * LEG_X, y, 0.2), 0.052)
            ellipsoid((s * LEG_X, y - 0.02, 0.045), (0.055, 0.075, 0.045))  # paw
    # Tail: capsules between the joints (a chain of balls reads as a lumpy caterpillar).
    for i in range(len(TAIL) - 1):
        capsule(TAIL[i], TAIL[i + 1], (TAIL_R[i] + TAIL_R[i + 1]) / 2)
    ball(TAIL[-1], TAIL_R[-1])

    obj = link(bpy.data.objects.new("Body", mb))
    activate(obj)
    bpy.ops.object.convert(target="MESH")
    body = bpy.context.view_layer.objects.active
    bpy.ops.object.shade_smooth()
    log(f"body: metaball -> {len(body.data.polygons)} faces")
    return body


def triangles(obj) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def light_copy(obj, target_tris: int):
    """A decimated copy for the game; the full-detail original keeps the painted colours."""
    copy = obj.copy()
    copy.data = obj.data.copy()
    link(copy)
    activate(copy)
    dec = copy.modifiers.new("Decimate", "DECIMATE")
    dec.ratio = min(1.0, target_tris / triangles(obj))
    bpy.ops.object.modifier_apply(modifier=dec.name)
    return copy


# ─── 2. Face and ears ───────────────────────────────────────────────────────────────────


def surface(body, origin, direction):
    """Where a ray from inside the body leaves it: (point, outward normal)."""
    ok, loc, normal, _ = body.ray_cast(Vector(origin), Vector(direction).normalized())
    if not ok:
        raise SystemExit(f"ray from {origin} along {direction} missed the body")
    return loc, normal


def uv_sphere(name, radius=1.0, segments=20, rings=10):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    bm.to_mesh(me)
    bm.free()
    obj = link(bpy.data.objects.new(name, me))
    for p in me.polygons:
        p.use_smooth = True
    return obj


def cone(name, radius, depth, segments=20):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=0.0, depth=depth)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, depth / 2))  # base at z = 0
    bm.to_mesh(me)
    bm.free()
    obj = link(bpy.data.objects.new(name, me))
    for p in me.polygons:
        p.use_smooth = True
    return obj


def frame(z_axis: Vector, front: Vector) -> Matrix:
    """Rotation whose Z is z_axis and whose Y faces `front` as nearly as it can."""
    z = z_axis.normalized()
    y = (front - front.dot(z) * z).normalized()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed().to_4x4()


def place(obj, location, rotation: Matrix, scale):
    obj.matrix_world = Matrix.Translation(location) @ rotation @ Matrix.Diagonal((*scale, 1))


def smooth_subsurf(obj, levels=2):
    activate(obj)
    mod = obj.modifiers.new("Subsurf", "SUBSURF")
    mod.levels = levels
    bpy.ops.object.modifier_apply(modifier=mod.name)


def build_face(body):
    parts = []
    front = Vector((0, -1, 0))
    up = Vector((0, 0, 1))
    for s in (-1, 1):
        # Eyes: big glossy ovals, wide-set at the middle of the face, half sunk into the head.
        # Their frame: Y along the surface normal (depth), Z up the face (height), X across.
        p, n = surface(body, HEAD, (s * 0.62, -1, 0.1))
        height = (up - up.dot(n) * n).normalized()
        across = n.cross(height)
        eye_rot = Matrix((across, n, height)).transposed().to_4x4()
        eye = uv_sphere(f"Eye.{s}", segments=24, rings=12)
        w, d, h = 0.058, 0.03, 0.07
        place(eye, p - n * 0.008, eye_rot, (w, d, h))
        eye["color"] = "eye"
        # A highlight up and toward the outside, standing proud of the eye's surface.
        outward = across * (1 if across.x * s > 0 else -1)
        shine = uv_sphere(f"Shine.{s}", segments=12, rings=6)
        place(shine, p + n * 0.016 + height * 0.028 + outward * 0.018, eye_rot, (0.019, 0.01, 0.021))
        shine["color"] = "shine"
        parts += [eye, shine]

    p, n = surface(body, HEAD, (0, -1, -0.26))
    nose = uv_sphere("Nose", segments=14, rings=8)
    place(nose, p + n * 0.004, frame(-n, Vector((0, 0, 1))), (0.026, 0.02, 0.017))
    nose["color"] = "nose"
    parts.append(nose)

    # Mouth: a small "w" under the nose, each point projected onto the muzzle.
    mouth_z = p.z - 0.042
    pts = []
    for i in range(17):
        u = -1 + 2 * i / 16
        x, z = 0.036 * u, mouth_z - 0.012 * abs(math.sin(math.pi * u))
        hit, nn = surface(body, (x, HEAD.y, z), (0, -1, 0))
        pts.append(hit + nn * 0.003)
    curve = bpy.data.curves.new("Mouth", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth, curve.bevel_resolution = 0.0045, 2
    spline = curve.splines.new("POLY")
    spline.points.add(len(pts) - 1)
    for sp, q in zip(spline.points, pts):
        sp.co = (*q, 1)
    mouth = link(bpy.data.objects.new("Mouth", curve))
    activate(mouth)
    bpy.ops.object.convert(target="MESH")
    mouth = bpy.context.view_layer.objects.active
    mouth["color"] = "nose"
    parts.append(mouth)

    for s in (-1, 1):
        # Ears: flattened cones, tilted out and a little back, planted in the top of the head.
        axis = Vector((s * 0.38, 0.12, 1)).normalized()
        p, n = surface(body, HEAD, (s * 0.52, 0.02, 1))
        base = p - axis * 0.05
        rot = frame(axis, front)
        ear = cone(f"Ear.{s}", 0.12, 0.26)
        place(ear, base, rot, (1, 0.48, 1))
        smooth_subsurf(ear, 1)
        ear["color"] = "ear"
        inner = cone(f"InnerEar.{s}", 0.08, 0.19)
        place(inner, base + axis * 0.035 + (rot @ Vector((0, 1, 0))) * 0.026, rot, (1, 0.32, 1))
        smooth_subsurf(inner, 1)
        inner["color"] = "inner_ear"
        parts += [ear, inner]

    # Tail flame: a flattened cone rising from the tail's tip.
    tip_dir = (TAIL[-1] - TAIL[-2]).normalized()
    flame_axis = (tip_dir + Vector((0, 0.3, 1.2))).normalized()
    p, n = surface(body, TAIL[-2], tip_dir)
    flame = cone("Flame", 0.07, 0.15)
    place(flame, p - flame_axis * 0.05, frame(flame_axis, Vector((1, 0, 0))), (1, 0.55, 1))
    smooth_subsurf(flame, 1)
    flame["color"] = "tip"
    parts.append(flame)
    log(f"face and ears: {len(parts)} parts")
    return parts


# ─── 3. Colour ──────────────────────────────────────────────────────────────────────────


def smooth(edge0, edge1, x):
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def body_color(p: Vector, n: Vector):
    c = COLORS["fur"]
    # Cream: lower face and muzzle, chest bib, underside.
    face = (p.y < HEAD.y - 0.08) and n.y < -0.2 and (p.z < 0.465 + 0.012 * math.cos(p.x * 22)) and (p.z > 0.3)
    m = (Vector(((p.x - MUZZLE.x) / 0.15, (p.y - MUZZLE.y) / 0.12, (p.z - MUZZLE.z) / 0.1))).length
    bib = p.y < 0.0 and 0.12 < p.z < 0.37 and abs(p.x) < 0.075 + (0.37 - p.z) * 0.25 and n.y < 0.2
    under = p.z < 0.19 and -0.02 < p.y < 0.24 and abs(p.x) < 0.07
    cream = max(1.0 if (face or bib or under) else 0.0, smooth(1.25, 1.0, m))
    c = mix(c, COLORS["cream"], cream)
    # Gold: forehead flame (a drop pointing down, two dots beside it) and cheek swooshes.
    if n.y < -0.25:
        v0, v1 = 0.56, 0.71
        if v0 < p.z < v1:
            w = 0.058 * math.sin(math.pi * (p.z - v0) / (v1 - v0)) ** 0.7
            if abs(p.x) < w:
                c = COLORS["gold"]
        for s in (-1, 1):
            if (Vector((p.x - s * 0.1, p.z - 0.655))).length < 0.021:
                c = COLORS["gold"]
            dx, dz = p.x - s * 0.205, p.z - 0.49
            if abs(p.x) > 0.13 and (dx / 0.055) ** 2 + ((dz + 0.35 * s * dx) / 0.022) ** 2 < 1:
                c = COLORS["gold"]
    # Gold dots on the back legs' outer sides.
    if abs(p.x) > 0.12 and n.x * math.copysign(1, p.x) > 0.3:
        if (Vector((p.y - (BACK_Y + 0.01), p.z - 0.17))).length < 0.03:
            c = COLORS["gold"]
    # Dark paws.
    c = mix(c, COLORS["dark"], smooth(0.085, 0.05, p.z))
    # Tail: gold toward the tip, cream at the very end.
    if p.y > 0.31 and p.z > 0.24:
        along = smooth(0.40, 0.52, p.z)
        c = mix(c, COLORS["gold"], along)
        c = mix(c, COLORS["tip"], smooth(0.53, 0.6, p.z))
    return c


def paint(obj, fn):
    me = obj.data
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "POINT")
    for i, v in enumerate(me.vertices):
        p, n = obj.matrix_world @ v.co, (obj.matrix_world.to_3x3() @ v.normal).normalized()
        attr.data[i].color_srgb = (*fn(p, n), 1.0)


def paint_parts(parts):
    for part in parts:
        key = part["color"]
        if key == "ear":
            # Fur colour darkening toward the tip.
            zs = [(part.matrix_world @ v.co).z for v in part.data.vertices]
            lo, hi = min(zs), max(zs)
            paint(part, lambda p, n: mix(COLORS["fur"], COLORS["ear_tip"], smooth(lo + 0.55 * (hi - lo), hi, p.z)))
        elif key == "tip":
            zs = [(part.matrix_world @ v.co).z for v in part.data.vertices]
            lo, hi = min(zs), max(zs)
            paint(part, lambda p, n: mix(COLORS["gold"], COLORS["tip"], smooth(lo, hi, p.z)))
        else:
            paint(part, lambda p, n, k=key: COLORS[k])


# ─── 4. Join, unwrap, bake, export ──────────────────────────────────────────────────────


def color_material(name, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes["Principled BSDF"]
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def join(objs, name):
    for obj in objs:
        activate(obj)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in bpy.context.scene.objects:
        o.select_set(o in objs)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    return joined


def finish(body, parts):
    skin, gloss = color_material("Skin", 0.6), color_material("Gloss", 0.15)
    for obj in [body] + parts:
        obj.data.materials.clear()
        obj.data.materials.append(gloss if obj.get("color") in ("eye", "shine", "nose") else skin)

    # Two versions: the full-detail one holds the painted colours; the light one is the game model.
    light = light_copy(body, 4800)
    copies = []
    for part in parts:
        c = part.copy()
        c.data = part.data.copy()
        copies.append(link(c))
    detail = join([body] + copies, "MonsterDetail")
    monster = join([light] + parts, "Monster")

    activate(monster)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Bake the detailed colours onto the light model's texture (selected to active), so the
    # markings keep the full-detail edges instead of the decimated mesh's big triangles.
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    image = bpy.data.images.new("Monster_color", 1024, 1024)
    for mat in (skin, gloss):
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        mat.node_tree.nodes.active = node
    for o in bpy.context.scene.objects:
        o.select_set(o in (detail, monster))
    bpy.context.view_layer.objects.active = monster
    bpy.ops.object.bake(
        type="DIFFUSE",
        pass_filter={"COLOR"},
        use_selected_to_active=True,
        cage_extrusion=0.015,
        max_ray_distance=0.04,
        margin=6,
        use_clear=True,
    )
    image.filepath_raw = str(OUT / "texture.png")
    image.file_format = "PNG"
    image.save()
    bpy.data.objects.remove(detail)

    # One plain textured material, like a Meshy model.
    final = bpy.data.materials.new("Monster")
    final.use_nodes = True
    tex = final.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    bsdf = final.node_tree.nodes["Principled BSDF"]
    final.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.55
    monster.data.materials.clear()
    monster.data.materials.append(final)
    for poly in monster.data.polygons:
        poly.material_index = 0
    if "Col" in monster.data.color_attributes:
        monster.data.color_attributes.remove(monster.data.color_attributes["Col"])

    log(f"game model: {len(monster.data.vertices)} verts, {triangles(monster)} triangles, texture 1024")
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "model.blend"))
    activate(monster)
    bpy.ops.export_scene.gltf(filepath=str(OUT / "model.glb"), export_format="GLB", use_selection=True, export_yup=True)
    log("exported model.glb")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    body = build_body()
    parts = build_face(body)
    paint(body, body_color)
    paint_parts(parts)
    finish(body, parts)


main()
