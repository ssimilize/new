"""Exports a rigged monster (a rig script's rig.blend) for the game's MeshMonster builder.

  blender -b <rig dir>/rig.blend --python tools/blender/export_roblox.py -- <form id> <module dir> <texture dir>
  stylua <module dir>      # the checks format generated modules like any other source

Writes:
  <module dir>/<form>.luau   bounds, scale, bones and clips: what the game needs at run time
  <rig dir>/mesh.json        the mesh (vertices, triangles, UVs, skin weights, bones), which
                             publish_meshes.luau publishes from Studio as a Mesh asset
  <texture dir>/<form>.png   the texture at 1024 px (Roblox's cap), plus _normal and _roughness
                             when the model has PBR maps (not used in game)
The mesh and texture ids go in Visuals/MeshMonsterAssets.luau (asset_ids.py), not here, so a
re-export never loses them. (Until 2026-09-25 the mesh arrays shipped in the module and the game
built each monster through its own EditableMesh; Roblox's EditableMesh memory budget ran out at
about eight monsters on screen.)

Axes: Blender is Z up with the front at -Y; Roblox is Y up and MonsterModel's front is -Z. The
mapping (x, y, z) -> (-x, z, y) is a proper rotation, so triangle winding and bone frames survive.
Every bone's rest CFrame is given in mesh space (the builder derives the Bone instances' parent-
relative CFrames), and each clip frame is the bone's pose in its own rest frame, which is exactly
what Bone.Transform takes. Sizes are for a model 1 unit tall; the game scales at build time.

Arrays are little-endian binary in base64 (the module's clip data wrapped at 128 columns inside
long strings; mesh.json's unwrapped):
  positions, normals   f32 x3 per vertex        uvs   f32 x2 per vertex (v flipped: Roblox is top-down)
  tris                 u16 x3 per triangle      skin  u8 x4 bone indices then u8 x4 weights per vertex
  clip data            f32 x7 per bone per frame (qx, qy, qz, qw, tx, ty, tz)
"""

import base64
import json
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Matrix

ARGS = sys.argv[sys.argv.index("--") + 1 :]
FORM, MODULES, TEXTURES = ARGS[0], Path(ARGS[1]).resolve(), Path(ARGS[2]).resolve()
MODULES.mkdir(parents=True, exist_ok=True)
TEXTURES.mkdir(parents=True, exist_ok=True)
C = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))
C4 = C.to_4x4()
FPS = bpy.context.scene.render.fps
MAX_SOURCE = 190_000  # Studio refuses a Source of 200,000 characters or more


def b64(fmt: str, values) -> str:
    raw = base64.b64encode(struct.pack("<" + fmt * (len(values) // len(fmt)), *values)).decode()
    return "\n".join(raw[i : i + 128] for i in range(0, len(raw), 128))


def main():
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    me = mesh.data
    bones = list(arm.data.bones)
    index = {b.name: i for i, b in enumerate(bones)}

    # Vertices: one per distinct (position, uv, normal) corner, as glTF does.
    uv_layer = me.uv_layers.active.data
    normals = me.corner_normals
    me.calc_loop_triangles()
    world = mesh.matrix_world
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
        raise SystemExit(f"{len(verts)} vertices: too many for u16 indices")

    positions, norms, uvs, skin = [], [], [], []
    groups = {g.index: g.name for g in mesh.vertex_groups}
    for v, uv, n in verts:
        p = C @ (world @ me.vertices[v].co)
        q = (C @ (world.to_3x3() @ n)).normalized()
        positions += [p.x, p.y, p.z]
        norms += [q.x, q.y, q.z]
        uvs += [uv.x, 1.0 - uv.y]
        weights = sorted(((g.weight, index[groups[g.group]]) for g in me.vertices[v].groups if g.weight > 0 and groups[g.group] in index), reverse=True)[:4]
        total = sum(w for w, _ in weights) or 1.0
        quant = [round(255 * w / total) for w, _ in weights]
        quant[0] += 255 - sum(quant) if quant else 0  # exact 255 total after rounding
        ids = [i for _, i in weights]
        skin += (ids + [0, 0, 0, 0])[:4] + (quant + [0, 0, 0, 0])[:4]

    # Bones: rest CFrames in mesh space (Roblox axes).
    bone_lines, bone_list = [], []
    for b in bones:
        m = C4 @ arm.matrix_world @ b.matrix_local
        t, q = m.to_translation(), m.to_quaternion()
        parent = index[b.parent.name] + 1 if b.parent else 0
        cframe = [round(t.x, 5), round(t.y, 5), round(t.z, 5), round(q.x, 6), round(q.y, 6), round(q.z, 6), round(q.w, 6)]
        bone_list.append({"name": b.name, "cframe": cframe})
        bone_lines.append(
            f'\t\t{{ name = "{b.name}", parent = {parent}, deform = {str(b.use_deform).lower()}, '
            f"cframe = {{ {t.x:.5f}, {t.y:.5f}, {t.z:.5f}, {q.x:.6f}, {q.y:.6f}, {q.z:.6f}, {q.w:.6f} }} }},"
        )

    # Clips: every frame of every action, each bone's pose in its own rest frame.
    clip_lines = []
    scene = bpy.context.scene
    for action in bpy.data.actions:
        arm.animation_data.action = action
        start, end = (int(x) for x in action.frame_range)
        data = []
        for f in range(start, end + 1):
            scene.frame_set(f)
            for b in bones:
                pb = arm.pose.bones[b.name]
                loc, rot, _ = pb.matrix_basis.decompose()
                data += [rot.x, rot.y, rot.z, rot.w, loc.x, loc.y, loc.z]
        clip_lines.append(f"\t\t{action.name} = {{ fps = {FPS}, frames = {end - start + 1}, data = [[\n{b64('f', data)}\n]] }},")

    lo = [min(positions[i::3]) for i in range(3)]
    hi = [max(positions[i::3]) for i in range(3)]
    # The mesh itself, for publish_meshes.luau (Studio publishes it once as a Mesh asset; the game
    # builds from that asset, so the arrays never ship in the game's scripts).
    mesh_json = {
        "form": FORM,
        "vertices": len(verts),
        "triangles": len(tris) // 3,
        "positions": b64("f", positions).replace("\n", ""),
        "normals": b64("f", norms).replace("\n", ""),
        "uvs": b64("f", uvs).replace("\n", ""),
        "tris": b64("H", tris).replace("\n", ""),
        "skin": b64("B", skin).replace("\n", ""),
        "bones": bone_list,
    }
    (Path(bpy.data.filepath).parent / "mesh.json").write_text(json.dumps(mesh_json), encoding="utf-8")

    # One module per form, beside the others. (A folder with child modules was the old layout.)
    old_folder = MODULES / FORM
    if old_folder.is_dir():
        for old in old_folder.iterdir():
            old.unlink()
        old_folder.rmdir()
    # A rig script may set how big the game draws this model relative to a fox (riglib.set_game_scale).
    scale = float(bpy.context.scene.get("game_scale", 1.0))
    scale_line = f"\n\tscale = {scale:.3f}," if abs(scale - 1.0) > 1e-3 else ""
    text = f"""--[[
	{FORM}: generated by tools/blender/export_roblox.py from art/rigs/{FORM}/rig.blend. Do not edit.
	Read by Visuals/MeshMonster, which builds the published mesh (MeshMonsterAssets) and poses these
	bones. {len(verts)} vertices, {len(tris) // 3} triangles, {len(bones)} bones.
]]

return {{
	form = "{FORM}",
	bounds = {{ {lo[0]:.5f}, {lo[1]:.5f}, {lo[2]:.5f}, {hi[0]:.5f}, {hi[1]:.5f}, {hi[2]:.5f} }},{scale_line}
	bones = {{
{chr(10).join(bone_lines)}
	}},
	clips = {{
{chr(10).join(clip_lines)}
	}},
}}
"""
    if len(text) >= MAX_SOURCE:
        raise SystemExit(f"{FORM}.luau is {len(text)} characters: over Studio's Source cap")
    (MODULES / f"{FORM}.luau").write_text(text, encoding="utf-8", newline="\n")
    files = {f"{FORM}.luau": text}

    # Textures (bake_texture.py's, once it has run), at 1024: the base colour, plus the normal and
    # roughness maps when the model has them (kept for an uploaded-mesh path; see asset_ids.py).
    maps = {}
    for suffix, image in material_maps(me.materials[0]).items():
        copy = image.copy()
        copy.scale(1024, 1024)
        copy.filepath_raw = str(TEXTURES / f"{FORM}{suffix}.png")
        copy.file_format = "PNG"
        copy.save()
        maps[suffix or "color"] = copy.filepath_raw
    print(f"[export] {FORM}: {len(verts)} verts, {len(tris) // 3} tris, {len(bones)} bones, "
          f"{len(bpy.data.actions)} clips, largest file {max(len(t) for t in files.values()) // 1024} KB, "
          f"textures at 1024: {', '.join(maps)}", flush=True)


def material_maps(material) -> dict:
    """{"": base colour, "_normal": normal map, "_roughness": roughness} images, found by what they feed."""
    tree = material.node_tree
    bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")

    def image_into(socket):
        node = socket.links[0].from_node if socket.is_linked else None
        return node.image if node is not None and node.type == "TEX_IMAGE" else None

    maps = {"": image_into(bsdf.inputs["Base Color"]), "_roughness": image_into(bsdf.inputs["Roughness"])}
    normal = bsdf.inputs["Normal"].links[0].from_node if bsdf.inputs["Normal"].is_linked else None
    if normal is not None and normal.type == "NORMAL_MAP":
        maps["_normal"] = image_into(normal.inputs["Color"])
    if maps[""] is None:
        raise SystemExit("export_roblox.py: the material has no base colour texture")
    return {suffix: image for suffix, image in maps.items() if image is not None}


main()
