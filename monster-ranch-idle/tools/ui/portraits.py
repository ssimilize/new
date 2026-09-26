"""Renders monster UI portraits from the rigged Meshy models, many forms per Blender process.

  blender -b --factory-startup --python tools/ui/portraits.py -- [--forms a,b | --species] [--force]
          [--size 256] [--out art/portraits] [--rigs <dir with <form>/rig.glb>]

--species renders every form in src/shared/Config/Species.luau that has a rig (the form list comes
from tools/ui/config_dump.luau); --forms renders just those. Forms that already have a PNG are skipped
unless --force, so a re-run after a merge only renders the new forms. Rigs default to art/rigs in this
checkout, else the main checkout's (they are git-ignored; see tools/ui/uiart.py).

Each form is loaded, stood on the ground and scaled to 1 m tall the way tools/blender/look.py does,
then drawn with its own embedded texture (texture_game.png beside the rig is only a fallback: it is
laid out for the exported game mesh, not the rig's UVs) under a soft three-point
light with an ink outline: an inverted-hull Solidify shell in #1B1B1B with backface culling, like
the UI's outlined shapes. The camera is orthographic from the front three-quarter, a little above,
and is fitted to the model's projected outline so every portrait has the same padding. Colour
management is "Standard" so the texture colours stay true. Output: <out>/<form>.png, RGBA, size px.
"""

import math
import sys
import time
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import uiart  # noqa: E402  (stdlib only, so Blender's Python can import it)

PAD = 0.07  # empty margin on each side, as a fraction of the image
OUTLINE = 0.016  # hull thickness in metres (model height = 1 m)
INK_LINEAR = (0.0109, 0.0109, 0.0109, 1)  # sRGB #1B1B1B
VIEW = Vector((-1.9, -2.3, 1.05)).normalized()  # front three-quarter from the model's right, slightly above


def parse(argv):
    out = {"forms": None, "species": False, "force": False, "size": 256, "out": uiart.ROOT / "art" / "portraits",
           "rigs": uiart.art_source("art/rigs")}
    i = 0
    while i < len(argv):
        k = argv[i]
        if k == "--species":
            out["species"] = True
        elif k == "--force":
            out["force"] = True
        elif k in ("--forms", "--size", "--out", "--rigs"):
            v = argv[i + 1]
            i += 1
            out[k[2:]] = v.split(",") if k == "--forms" else int(v) if k == "--size" else Path(v).resolve()
        i += 1
    return out


def textured_material(tex_path: Path, old):
    mat = bpy.data.materials.new("Portrait")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.8
    bsdf.inputs["Specular IOR Level"].default_value = 0.2
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 0.35  # lifts the shadow side so colours read true
    add = nt.nodes.new("ShaderNodeAddShader")
    # the glb's own texture matches its UVs; texture_game.png (the game's re-baked 1024 copy) is laid
    # out for the exported mesh, so it is only a fallback for a rig with no embedded image
    src = None
    if old is not None and old.node_tree:
        src = next((n.image for n in old.node_tree.nodes if n.type == "TEX_IMAGE" and n.image), None)
    if src is None and tex_path.exists():
        src = bpy.data.images.load(str(tex_path), check_existing=True)
    if src is not None:
        img = nt.nodes.new("ShaderNodeTexImage")
        img.image = src
        nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(img.outputs["Color"], emit.inputs["Color"])
    nt.links.new(bsdf.outputs[0], add.inputs[0])
    nt.links.new(emit.outputs[0], add.inputs[1])
    nt.links.new(add.outputs[0], out.inputs["Surface"])
    return mat


def ink_material():
    mat = bpy.data.materials.new("Ink")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = INK_LINEAR
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    mat.use_backface_culling = True
    return mat


def add_light(scene, name, energy, direction, size_deg):
    light = bpy.data.lights.new(name, "SUN")
    light.energy = energy
    light.angle = math.radians(size_deg)
    obj = bpy.data.objects.new(name, light)
    obj.rotation_euler = (-Vector(direction)).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(obj)


def world_points(meshes) -> list[Vector]:
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ev.matrix_world
        pts += [mw @ v.co for v in me.vertices]
        ev.to_mesh_clear()
    return pts


def render_form(form: str, rig: Path, dest: Path, size: int) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(rig))
    scene = bpy.context.scene
    # the rigs carry a 2 m bone-shape Icosphere with no material: only textured meshes are the monster
    meshes = [o for o in scene.objects if o.type == "MESH" and o.data.materials]
    for o in scene.objects:
        if o.type == "MESH" and o not in meshes:
            bpy.data.objects.remove(o)
    for o in scene.objects:  # rest-ish pose: no playing actions
        if o.animation_data:
            o.animation_data.action = None
    pts = world_points(meshes)
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    root = bpy.data.objects.new("Root", None)
    scene.collection.objects.link(root)
    for o in list(scene.objects):
        if o.parent is None and o is not root:
            o.parent = root
    s = 1.0 / (hi.z - lo.z)
    root.scale = (s, s, s)
    root.location = (-(lo.x + hi.x) / 2 * s, -(lo.y + hi.y) / 2 * s, -lo.z * s)
    bpy.context.view_layer.update()

    tex = rig.parent / "texture_game.png"
    ink = ink_material()
    for o in meshes:
        old = o.data.materials[0] if o.data.materials else None
        o.data.materials.clear()
        o.data.materials.append(textured_material(tex, old))
        o.data.materials.append(ink)
        for p in o.data.polygons:
            p.material_index = 0
        hull = o.modifiers.new("InkHull", "SOLIDIFY")
        # thickness is in object space, so undo the world scale
        hull.thickness = -OUTLINE / max(o.matrix_world.to_scale())
        hull.offset = 1.0  # grow outwards from the surface
        hull.use_flip_normals = True
        hull.use_rim = False
        hull.material_offset = 1

    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.45
    scene.world = world
    add_light(scene, "Key", 2.4, (-0.9, -1.0, 1.1), 20)  # front-left, above
    add_light(scene, "Fill", 0.8, (1.2, -0.8, 0.3), 40)  # front-right, low
    add_light(scene, "Rim", 1.8, (0.4, 1.2, 0.9), 10)  # behind

    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.type = "ORTHO"
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((0, 0, 0.5))
    cam.location = target + VIEW * 6
    cam.rotation_euler = (-VIEW).to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()
    # fit: project the (outlined) model into camera space, centre it, pad it
    inv = cam.matrix_world.inverted()
    cp = [inv @ p for p in world_points(meshes)]
    x0, x1 = min(p.x for p in cp), max(p.x for p in cp)
    y0, y1 = min(p.y for p in cp), max(p.y for p in cp)
    cam.data.ortho_scale = max(x1 - x0, y1 - y0) / (1 - 2 * PAD)
    cam.location = cam.matrix_world @ Vector(((x0 + x1) / 2, (y0 + y1) / 2, 0))
    scene.render.filepath = str(dest)
    bpy.ops.render.render(write_still=True)


def main():
    a = parse(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
    rigs: Path = a["rigs"]
    if a["species"]:
        forms = [f["id"] for f in uiart.config()["forms"]]
    elif a["forms"]:
        forms = a["forms"]
    else:
        sys.exit("pass --forms a,b or --species")
    a["out"].mkdir(parents=True, exist_ok=True)
    done, skipped, norig = 0, 0, []
    t0 = time.time()
    for form in forms:
        rig = rigs / form / "rig.glb"
        dest = a["out"] / f"{form}.png"
        if not rig.exists():
            norig.append(form)
            continue
        if dest.exists() and not a["force"]:
            skipped += 1
            continue
        render_form(form, rig, dest, a["size"])
        done += 1
        print(f"[portraits] {form} ({done}, {time.time() - t0:.0f}s)", flush=True)
    print(f"[portraits] rendered {done}, skipped {skipped} existing, {len(norig)} without a rig", flush=True)
    if norig:
        print("[portraits] no rig:", ", ".join(norig), flush=True)


main()
