"""Runs inside Blender: decimates a form's already-rigged, already-baked mesh (art/rigs/<form>/rig.blend)
to a low triangle budget for Low-graphics and crowd-capped fights, and writes a mesh.json in the same
shape export_roblox.py writes (so MeshMonster's loader needs no new code path).

  blender -b art/rigs/<form>/rig.blend --python tools/blender/lowpoly_export.py -- <form> <out dir> <target tris>

rig.blend is opened and never saved: the decimated mesh lives only in a duplicate object, on a copy of
the scene, discarded when Blender exits. The duplicate's Decimate modifier (Collapse, applied) is the
only change; the armature (bones, names, order) is untouched, so the vertex-group -> bone-index mapping
below is exactly the one export_roblox.py used for the full mesh, and the low mesh's skin data plugs
into the SAME MeshMonsters/<form>.luau bones and clips. UVs survive a Collapse decimate (edge collapse
interpolates them, it does not re-pack the atlas), so the low mesh keeps the full model's texture: no
re-bake, no new upload, MeshMonsterAssets.<form>.lowMesh reuses .texture.

Writes <out dir>/<form>/mesh.json (same fields as art/rigs/<form>/mesh.json: positions, normals, uvs,
tris, skin, bones) and prints "[lowpoly] <form>: A -> B tris (ratio), C KB" for pipeline.py's summary.
"""

import base64
import json
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Matrix

ARGS = sys.argv[sys.argv.index("--") + 1 :]
FORM, OUT, TARGET_TRIS = ARGS[0], Path(ARGS[1]).resolve(), int(ARGS[2])
OUT.mkdir(parents=True, exist_ok=True)
C = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))
C4 = C.to_4x4()


def b64(fmt: str, values) -> str:
    return base64.b64encode(struct.pack("<" + fmt * (len(values) // len(fmt)), *values)).decode()


def triangle_count(mesh) -> int:
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def main():
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    source = next(o for o in bpy.data.objects if o.type == "MESH")
    before = triangle_count(source.data)

    # A duplicate carries the decimate modifier; the original (and the file on disk) is untouched.
    bpy.ops.object.select_all(action="DESELECT")
    source.select_set(True)
    bpy.context.view_layer.objects.active = source
    bpy.ops.object.duplicate()
    dup = bpy.context.view_layer.objects.active
    dup.name = f"{FORM}_lowpoly"

    ratio = max(0.02, min(1.0, TARGET_TRIS / before)) if before > 0 else 1.0
    mod = dup.modifiers.new("LowPoly", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = dup
    bpy.ops.object.modifier_apply(modifier=mod.name)

    me = dup.data
    after = triangle_count(me)

    bones = list(arm.data.bones)
    index = {b.name: i for i, b in enumerate(bones)}
    uv_layer = me.uv_layers.active.data
    normals = me.corner_normals
    world = dup.matrix_world
    corner_of, verts, tris = {}, [], []
    for tri in me.loop_triangles:
        face = []
        for loop in tri.loops:
            v = me.loops[loop].vertex_index
            uv = uv_layer[loop].uv
            n = normals[loop].vector
            key = (v, round(uv.x, 5), round(uv.y, 5), round(n.x, 3), round(n.y, 3), round(n.z, 3))
            if key not in corner_of:
                corner_of[key] = len(verts)
                verts.append((v, uv.copy(), n.copy()))
            face.append(corner_of[key])
        tris.extend(face)
    if len(verts) > 65535:
        raise SystemExit(f"{FORM}: {len(verts)} low-poly vertices, too many for u16 indices")

    positions, norms, uvs, skin = [], [], [], []
    groups = {g.index: g.name for g in dup.vertex_groups}
    for v, uv, n in verts:
        p = C @ (world @ me.vertices[v].co)
        q = (C @ (world.to_3x3() @ n)).normalized()
        positions += [p.x, p.y, p.z]
        norms += [q.x, q.y, q.z]
        uvs += [uv.x, 1.0 - uv.y]
        weights = sorted(
            ((g.weight, index[groups[g.group]]) for g in me.vertices[v].groups if g.weight > 0 and groups[g.group] in index),
            reverse=True,
        )[:4]
        total = sum(w for w, _ in weights) or 1.0
        quant = [round(255 * w / total) for w, _ in weights]
        quant[0] += 255 - sum(quant) if quant else 0
        ids = [i for _, i in weights]
        skin += (ids + [0, 0, 0, 0])[:4] + (quant + [0, 0, 0, 0])[:4]

    bone_list = []
    for b in bones:
        m = C4 @ arm.matrix_world @ b.matrix_local
        t, q = m.to_translation(), m.to_quaternion()
        bone_list.append({"name": b.name, "cframe": [round(t.x, 5), round(t.y, 5), round(t.z, 5), round(q.x, 6), round(q.y, 6), round(q.z, 6), round(q.w, 6)]})

    mesh_json = {
        "form": FORM,
        "vertices": len(verts),
        "triangles": len(tris) // 3,
        "positions": b64("f", positions),
        "normals": b64("f", norms),
        "uvs": b64("f", uvs),
        "tris": b64("H", tris),
        "skin": b64("B", skin),
        "bones": bone_list,
    }
    form_dir = OUT / FORM
    form_dir.mkdir(parents=True, exist_ok=True)
    path = form_dir / "mesh.json"
    path.write_text(json.dumps(mesh_json), encoding="utf-8")
    kb = path.stat().st_size // 1024
    print(f"[lowpoly] {FORM}: {before} -> {after} tris (ratio {ratio:.3f}), {len(verts)} verts, {kb} KB", flush=True)

    bpy.data.objects.remove(dup, do_unlink=True)


main()
