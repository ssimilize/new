"""Exports a static model (a building: no rig, no clips) for the game, the way pipeline.py exports a
monster. From monster-ranch-idle/, with system Python:

  python tools/blender/export_static.py ID YAW [PIECES]

  1. prepare  the model (art/tripo/<ID>/model.glb from Tripo Studio, else art/meshy/<ID>-model/model.glb)
              -> art/rigs/<ID>/static.blend: one mesh, its seams kept
              (the monsters' weld would smooth a wall's corners round), turned YAW degrees about the
              vertical so the front door faces -Y, 1 unit tall, standing on the ground, centred, its
              underside dropped (never seen, and it took ~15% of the texture). Then cut into PIECES
              of equal surface area, art/rigs/<ID>/p<N>/static.blend.
  2. bake     bake_texture.py re-lays each piece's UVs with padding onto its own texture
  3. export   art/rigs/<ID>/p<N>/mesh.json, centred on the piece's box (no bones: its skin is all zero
              weights, so publish_meshes.luau publishes it unchanged), art/export/<ID>_p<N>.png at
              1024, and art/rigs/<ID>/pieces.json: the building's size and each piece's offset

Why pieces: Roblox draws a texture at 1024 px at most, and one 1024 texture over a 20-stud building
came to ~14 texels a stud (the Egg Shop, 2026-09-25: soft walls up close); Meshy's own is 4096 px.
Each piece is its own MeshPart with its own 1024 texture, so N pieces hold N times the texels.
PIECES defaults to what reaches DENSITY texels a stud at the building's size in game (its placeholder's
footprint in Config/World.luau, or Build.luau's SKY_GATE_BODY for skyGate, which World/Dress.luau fits it to), at most MAX_PIECES: a 6-stud stage
needs far fewer than a 20-stud shop, and every piece is a texture in memory on a phone.

Then publish every piece from Studio (_G.MeshPublishRun(base, { "<ID>_p0", ... }) with base serving
<ID>_p<N>/mesh.json), upload the textures, and record them with
  python tools/blender/export_static.py ids ID ids.json   (ids.json: { "<ID>_p0": {"mesh", "texture"} })
which writes the building's entry in src/server/Systems/World/BuildingMeshes.luau.

YAW: look.py's "side" view looks at the +X face and "front" at the -Y face; a model whose door
shows in the side view needs -90.
"""

import json
import math
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
DENSITY = 40  # texels a stud in game
MAX_PIECES = 8
FILL = 0.5  # share of a texture the atlas covers (atlas.py packs ~50-56%)
MESHES = ROOT / "src" / "server" / "Systems" / "World" / "BuildingMeshes.luau"

try:
    import bpy
except ImportError:
    bpy = None


def run_blender(args: list[str], building: str) -> None:
    result = subprocess.run([BLENDER, "-b", *args], capture_output=True, text=True)
    lines = [line for line in result.stdout.splitlines() if line.startswith(("[static]", "[bake]"))]
    print("\n".join(lines), flush=True)
    if result.returncode != 0 or "Traceback" in result.stderr + result.stdout:
        raise SystemExit(f"{building}: step failed\n{result.stdout[-2000:]}\n{result.stderr[-2000:]}")


def drive(building: str, yaw: str, pieces: str | None) -> None:
    out = ROOT / "art" / "rigs" / building
    for old in out.glob("p*/static.blend"):
        old.unlink()
    me = str(Path(__file__))
    x, z = footprint(building)
    run_blender(["--factory-startup", "--python", me, "--", "prepare", building, yaw, pieces or "0", str(x), str(z)], building)
    parts = []
    for blend in sorted(out.glob("p*/static.blend"), key=lambda p: int(p.parent.name[1:])):
        run_blender([str(blend), "--python", str(HERE / "bake_texture.py")], building)
        run_blender([str(blend), "--python", me, "--", "export", building, blend.parent.name], building)
        parts.append(json.loads((blend.parent / "piece.json").read_text(encoding="utf-8")))
    size = json.loads((out / "size.json").read_text(encoding="utf-8"))
    (out / "pieces.json").write_text(json.dumps({"building": building, "size": size, "parts": parts}, indent=1), encoding="utf-8")
    print(f"[static] {building}: {len(parts)} pieces -> {out / 'pieces.json'}", flush=True)


def footprint(building: str) -> tuple[float, float]:
    """The placeholder's x and z size in studs: World.BarnSize for the barn, else its World.Hub entry."""
    import re

    if building == "skyGate":
        # Not a World.Hub building: Build.luau gives the Sky Gate an invisible Body of this size.
        build = (ROOT / "src" / "server" / "Systems" / "World" / "Build.luau").read_text(encoding="utf-8")
        found = re.search(r"SKY_GATE_BODY = Vector3\.new\((\d+), \d+, (\d+)\)", build)
        if not found:
            raise SystemExit("skyGate: no SKY_GATE_BODY in Build.luau")
        return float(found.group(1)), float(found.group(2))
    text = (ROOT / "src" / "shared" / "Config" / "World.luau").read_text(encoding="utf-8")
    if building == "barn":
        found = re.search(r"World\.BarnSize = \{ (\d+), \d+, (\d+) \}", text)
    else:
        found = re.search(r'id = "' + re.escape(building) + r'",[\s\S]*?size = \{ (\d+), \d+, (\d+) \}', text)
    if not found:
        raise SystemExit(f"{building}: no size in Config/World.luau")
    return float(found.group(1)), float(found.group(2))


def prepare(building: str, yaw: float, pieces: int, foot_x: float, foot_z: float) -> None:
    import numpy as np
    from mathutils import Matrix, Vector

    src = ROOT / "art" / "tripo" / building / "model.glb"
    if not src.exists():
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
    me = mesh.data
    me.transform(Matrix.Rotation(math.radians(yaw), 4, "Z"))
    co = np.array([v.co[:] for v in me.vertices])
    lo, hi = co.min(0), co.max(0)
    scale = 1.0 / (hi[2] - lo[2])
    offset = Vector((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]))
    for v in me.vertices:
        v.co = (v.co + offset) * scale
    me.update()
    dims = (hi - lo) * scale

    # Faces and their areas, centroids and normals; the underside goes (edit-mode deletes keep the
    # custom normals, which a bmesh round trip would drop).
    n = len(me.polygons)
    area = np.array([p.area for p in me.polygons])
    centre = np.array([p.center[:] for p in me.polygons])
    normal = np.array([p.normal[:] for p in me.polygons])
    under = (normal[:, 2] < -0.7) & (centre[:, 2] < 0.04)
    keep = ~under

    # Pieces of equal area by recursive bisection along the longest side of each group's box.
    studs = min(foot_x / dims[0], foot_z / dims[1])  # Dress.luau's scale: studs per unit
    if pieces <= 0:
        needed = area[keep].sum() * (DENSITY * studs) ** 2 / (FILL * 1024**2)
        pieces = max(1, min(MAX_PIECES, math.ceil(needed)))
    label = np.full(n, -1)

    def split(idx: np.ndarray, count: int, first: int) -> None:
        if count == 1:
            label[idx] = first
            return
        pts = centre[idx]
        axis = int(np.argmax(np.ptp(pts, axis=0)))
        order = idx[np.argsort(pts[:, axis])]
        share = np.cumsum(area[order]) / area[order].sum()
        left = count // 2
        cut = int(np.searchsorted(share, left / count))
        split(order[:cut], left, first)
        split(order[cut:], count - left, first + left)

    split(np.nonzero(keep)[0], pieces, 0)
    for p in me.polygons:
        p.select = False
    bpy.ops.wm.save_as_mainfile(filepath=str(out / "static.blend"))
    for i in range(pieces):
        bpy.ops.wm.open_mainfile(filepath=str(out / "static.blend"))
        mesh = next(o for o in bpy.data.objects if o.type == "MESH")
        bpy.context.view_layer.objects.active = mesh
        for element in (*mesh.data.vertices, *mesh.data.edges):
            element.select = False
        for p in mesh.data.polygons:
            p.select = bool(label[p.index] != i)
        bpy.context.scene.tool_settings.mesh_select_mode = (False, False, True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.delete(type="FACE")
        bpy.ops.object.mode_set(mode="OBJECT")
        (out / f"p{i}").mkdir(exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(out / f"p{i}" / "static.blend"))
        share = area[label == i].sum() / area[keep].sum()
        print(f"[static] {building} p{i}: {len(mesh.data.polygons)} faces, {share:.0%} of the surface", flush=True)
    # Roblox axes (x width, y height, z depth), 1 unit tall.
    (out / "size.json").write_text(json.dumps([round(float(dims[0]), 5), 1.0, round(float(dims[1]), 5)]), encoding="utf-8")
    texels = math.sqrt(pieces * FILL * 1024**2 / area[keep].sum()) / studs
    print(f"[static] {building}: turned {yaw:g} deg, {dims[0]:.2f} wide x {dims[1]:.2f} deep x 1 tall, "
          f"{int(under.sum())} underside faces dropped, {pieces} pieces: ~{texels:.0f} texels a stud", flush=True)


def export(building: str, piece: str) -> None:
    import base64
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
    # Centred on the piece's own box: a MeshPart made from the published mesh puts the mesh's origin
    # at the part's centre, so a mesh standing on its origin rose half its height out of the ground
    # (Egg Shop, 2026-09-25, found by raycasting the geometry against the part's extent). The box
    # centre, from the building's centre (0, 0, 0.5), is the piece's offset in pieces.json.
    world = mesh.matrix_world
    points = [world @ me.vertices[v].co for v, _, _ in verts]
    lo = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    centre = (lo + hi) / 2
    positions, norms, uvs = [], [], []
    for (_, uv, n), point in zip(verts, points):
        p = C @ (point - centre)
        q = (C @ (world.to_3x3() @ n)).normalized()
        positions += [p.x, p.y, p.z]
        norms += [q.x, q.y, q.z]
        uvs += [uv.x, 1.0 - uv.y]

    def b64(fmt: str, values) -> str:
        return base64.b64encode(struct.pack("<" + fmt * (len(values) // len(fmt)), *values)).decode()

    name = f"{building}_{piece}"
    out = Path(bpy.data.filepath).parent
    mesh_json = {
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
    (out / "mesh.json").write_text(json.dumps(mesh_json), encoding="utf-8")
    offset = C @ (centre - Vector((0.0, 0.0, 0.5)))
    (out / "piece.json").write_text(json.dumps({"name": name, "offset": [round(x, 5) for x in offset]}), encoding="utf-8")

    # The image feeding the base colour (export_roblox.py's material_maps; that script runs on import).
    tree = me.materials[0].node_tree
    socket = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"]
    image = socket.links[0].from_node.image.copy()
    image.scale(1024, 1024)
    textures = ROOT / "art" / "export"
    textures.mkdir(parents=True, exist_ok=True)
    image.filepath_raw = str(textures / f"{name}.png")
    image.file_format = "PNG"
    image.save()
    print(f"[static] {name}: mesh.json {len(verts)} verts, {len(tris) // 3} tris; texture {image.filepath_raw}", flush=True)


def record(building: str, ids_path: str) -> None:
    """Writes the building's entry in BuildingMeshes.luau from pieces.json and the published ids."""
    pieces = json.loads((ROOT / "art" / "rigs" / building / "pieces.json").read_text(encoding="utf-8"))
    ids = json.loads(Path(ids_path).read_text(encoding="utf-8"))
    size = ", ".join(f"{x:g}" for x in pieces["size"])
    rows = []
    for part in pieces["parts"]:
        got = ids[part["name"]]
        offset = ", ".join(f"{x:g}" for x in part["offset"])
        rows.append(f'\t\t\t{{ mesh = "{got["mesh"]}", texture = "{got["texture"]}", offset = {{ {offset} }} }},')
    entry = f"\t{building} = {{\n\t\tsize = {{ {size} }},\n\t\tparts = {{\n" + "\n".join(rows) + "\n\t\t},\n\t},\n"
    text = MESHES.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    start = next((i for i, line in enumerate(lines) if line.startswith(f"\t{building} = {{")), None)
    if start is None:
        end_of_table = max(i for i, line in enumerate(lines) if line.startswith("}"))
        lines[end_of_table:end_of_table] = [entry]
    elif lines[start].rstrip().endswith("},"):  # a one-line entry
        lines[start : start + 1] = [entry]
    else:
        end = next(i for i in range(start, len(lines)) if lines[i] == "\t},\n")
        lines[start : end + 1] = [entry]
    MESHES.write_text("".join(lines), encoding="utf-8", newline="\n")
    print(f"{building}: {len(rows)} pieces recorded in {MESHES.relative_to(ROOT)}")


if __name__ == "__main__":
    if bpy is None:
        if sys.argv[1] == "ids":
            record(sys.argv[2], sys.argv[3])
        else:
            drive(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    else:
        args = sys.argv[sys.argv.index("--") + 1 :]
        if args[0] == "prepare":
            prepare(args[1], float(args[2]), int(args[3]), float(args[4]), float(args[5]))
        else:
            export(args[1], args[2])
