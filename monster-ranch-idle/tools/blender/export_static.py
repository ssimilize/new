"""Exports a static model (a building: no rig, no clips) for the game, the way pipeline.py exports a
monster. From monster-ranch-idle/, with system Python:

  python tools/blender/export_static.py ID YAW

  1. prepare  art/meshy/<ID>-model/model.glb -> art/rigs/<ID>/static.blend: one mesh, its seams kept
              (the monsters' weld would smooth a wall's corners round), turned YAW degrees about the
              vertical so the front door faces -Y, 1 unit tall, standing on the ground, centred
  2. bake     bake_texture.py re-lays the UVs with padding (the same far-away seam fix as monsters)
  3. export   art/rigs/<ID>/mesh.json, centred on its box (no bones: its skin is all zero weights,
              so publish_meshes.luau publishes it unchanged) and art/export/<ID>.png at 1024

Then publish from Studio like a monster (_G.MeshPublishRun(base, { ID })), upload the texture, and
put both ids in src/server/Systems/World/BuildingMeshes.luau.

YAW: look.py's "side" view looks at the +X face and "front" at the -Y face; a model whose door
shows in the side view needs -90.
"""

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"

try:
    import bpy
except ImportError:
    bpy = None


def drive(building: str, yaw: str) -> None:
    out = ROOT / "art" / "rigs" / building
    blend = out / "static.blend"
    steps = [
        [BLENDER, "-b", "--factory-startup", "--python", str(Path(__file__)), "--", "prepare", building, yaw],
        [BLENDER, "-b", str(blend), "--python", str(HERE / "bake_texture.py")],
        [BLENDER, "-b", str(blend), "--python", str(Path(__file__)), "--", "export", building],
    ]
    for step in steps:
        result = subprocess.run(step, capture_output=True, text=True)
        lines = [line for line in result.stdout.splitlines() if line.startswith(("[static]", "[bake]"))]
        print("\n".join(lines), flush=True)
        if result.returncode != 0 or "Traceback" in result.stderr + result.stdout:
            raise SystemExit(f"{building}: step failed\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")


def prepare(building: str, yaw: float) -> None:
    import math

    import numpy as np
    from mathutils import Matrix, Vector

    src = ROOT / "art" / "meshy" / f"{building}-model" / "model.glb"
    out = ROOT / "art" / "rigs" / building
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(src))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in bpy.context.scene.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    mesh = bpy.context.view_layer.objects.active
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.context.scene.objects):
        if o is not mesh:
            bpy.data.objects.remove(o)
    mesh.name = "Building"
    mesh.data.transform(Matrix.Rotation(math.radians(yaw), 4, "Z"))
    co = np.array([v.co[:] for v in mesh.data.vertices])
    lo, hi = co.min(0), co.max(0)
    scale = 1.0 / (hi[2] - lo[2])
    offset = Vector((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]))
    for v in mesh.data.vertices:
        v.co = (v.co + offset) * scale
    mesh.data.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(out / "static.blend"))
    dims = (hi - lo) * scale
    print(f"[static] {building}: {len(mesh.data.vertices)} verts, {len(mesh.data.polygons)} faces, "
          f"turned {yaw:g} deg, width x depth x height {dims[0]:.2f} x {dims[1]:.2f} x {dims[2]:.2f}", flush=True)


def export(building: str) -> None:
    import base64
    import json
    import struct

    from mathutils import Matrix, Vector

    C = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))  # export_roblox.py's axes: Blender -Y front -> Roblox -Z

    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    me = mesh.data
    uv_layer = me.uv_layers.active.data
    normals = me.corner_normals
    me.calc_loop_triangles()
    corner_of, verts, tris = {}, [], []
    for tri in me.loop_triangles:
        for loop in tri.loops:
            v = me.loops[loop].vertex_index
            uv, n = uv_layer[loop].uv, normals[loop].vector
            key = (v, round(uv.x, 5), round(uv.y, 5), round(n.x, 3), round(n.y, 3), round(n.z, 3))
            if key not in corner_of:
                corner_of[key] = len(verts)
                verts.append((v, uv.copy(), n.copy()))
            tris.append(corner_of[key])
    if len(verts) > 65535:
        raise SystemExit(f"{len(verts)} vertices: too many for u16 indices")
    # Centred on its own box: a MeshPart made from the published mesh sits the mesh's origin at the
    # part's centre, so a mesh standing on its origin rose half its height out of the ground
    # (Egg Shop, 2026-09-25, found by raycasting the geometry against the part's extent).
    positions, norms, uvs = [], [], []
    world = mesh.matrix_world
    centre = Vector((0.0, 0.0, 0.5))
    for v, uv, n in verts:
        p = C @ (world @ me.vertices[v].co - centre)
        q = (C @ (world.to_3x3() @ n)).normalized()
        positions += [p.x, p.y, p.z]
        norms += [q.x, q.y, q.z]
        uvs += [uv.x, 1.0 - uv.y]

    def b64(fmt: str, values) -> str:
        return base64.b64encode(struct.pack("<" + fmt * (len(values) // len(fmt)), *values)).decode()

    out = Path(bpy.data.filepath).parent
    mesh_json = {
        "form": building,
        "vertices": len(verts),
        "triangles": len(tris) // 3,
        "positions": b64("f", positions),
        "normals": b64("f", norms),
        "uvs": b64("f", uvs),
        "tris": b64("H", tris),
        "skin": b64("B", [0] * (8 * len(verts))),
        "bones": [],
    }
    (out / "mesh.json").write_text(json.dumps(mesh_json), encoding="utf-8")

    # The image feeding the base colour (export_roblox.py's material_maps; that script runs on import).
    tree = me.materials[0].node_tree
    socket = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"]
    image = socket.links[0].from_node.image.copy()
    image.scale(1024, 1024)
    textures = ROOT / "art" / "export"
    textures.mkdir(parents=True, exist_ok=True)
    image.filepath_raw = str(textures / f"{building}.png")
    image.file_format = "PNG"
    image.save()
    print(f"[static] {building}: mesh.json {len(verts)} verts, {len(tris) // 3} tris; texture {image.filepath_raw}", flush=True)


if __name__ == "__main__":
    if bpy is None:
        drive(sys.argv[1], sys.argv[2])
    else:
        args = sys.argv[sys.argv.index("--") + 1 :]
        prepare(args[1], float(args[2])) if args[0] == "prepare" else export(args[1])
