"""Re-lays a rigged model's UVs and bakes its texture onto them with wide padding, so the texture
holds up at a distance. Runs on rig_quadruped.py's rig.blend, before export_roblox.py.

  blender -b <rig dir>/rig.blend --python tools/blender/bake_texture.py -- [size]

Why: Meshy packs hundreds of small UV islands almost edge to edge, and the thin gaps between them
hold streaks of unrelated colour. Far away the GPU samples the texture's small mip levels, which
average each seam with its neighbours on the sheet, so every seam shows as a light line on the
model (seen in Roblox, 2026-09-25). xatlas (tools/blender/atlas.py, system Python) builds a new
atlas with PADDING px between charts, the old texture is baked onto it, and every texel outside the
charts takes the colour of the nearest chart edge, so a blurred seam only ever blends with its own
colours. (The surface colour is continuous across a seam, so a chart's own edge colour is the right
padding.)

Tried first, and why not: Blender's Smart UV Project made 360+ tiny islands covering 9-34% of the
texture (Meshy's covers 62%), so the model came out blurrier; Blender's bake margins left black gaps
(EXTEND, 25 px) or a muddy grey hatched rim (ADJACENT_FACES). The rim came from the bake's partly
covered edge texels, whose colour is darkened by their coverage: they are un-premultiplied here
before the fill spreads them.

Keeps the geometry, skin and clips; replaces the UV map and the texture (saved next to rig.blend as
texture_game.png and packed into the file), then saves rig.blend.

PBR (Meshy enable_pbr, from the 2026-09-25 batch on): when the material also has a normal map and a
roughness texture, they are baked onto the same atlas (texture_game_normal.png, tangent space of the
new UVs, OpenGL +Y like Roblox; texture_game_roughness.png) and the material is rewired to the three
baked images, which export_roblox.py finds by what they feed. Metallic is dropped (Meshy's is 0).
"""

import subprocess
import sys
import tempfile
from pathlib import Path

import bpy
import numpy as np

ARGS = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
SIZE = int(ARGS[0]) if ARGS else 1024
PADDING = max(4, SIZE // 160)  # px around every chart (6 at 1024: covers the mip levels that showed seams)
ATLAS = Path(__file__).resolve().parent / "atlas.py"


def feeding(tree, socket):
    """The node linked into an input socket, or None."""
    return socket.links[0].from_node if socket.is_linked else None


def main():
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    me = mesh.data
    mat = me.materials[0]
    tree = mat.node_tree
    bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
    if feeding(tree, bsdf.inputs["Base Color"]) is None:
        raise SystemExit("bake_texture.py: the material has no base colour texture")
    normal_node = feeding(tree, bsdf.inputs["Normal"])
    normal_node = normal_node if normal_node is not None and normal_node.type == "NORMAL_MAP" else None
    has_roughness = bsdf.inputs["Roughness"].is_linked
    # Names, not references: adding a UV layer reallocates the collection and stales the old one.
    old_name = me.uv_layers.active.name
    old_islands = count_islands(me)

    # New UVs from xatlas: large charts, PADDING px apart.
    corner_uv, charts, coverage = run_xatlas(me)
    me.uv_layers.active = me.uv_layers.new(name="GameUV")
    uv_data = me.uv_layers["GameUV"].data
    for poly in me.polygons:
        for corner, loop in enumerate(poly.loop_indices):
            uv_data[loop].uv = corner_uv[poly.index, corner]
    for o in bpy.context.scene.objects:
        o.select_set(o is mesh)
    bpy.context.view_layer.objects.active = mesh

    # Every source image keeps reading the old UVs; the bakes write through the new ones.
    uv_node = tree.nodes.new("ShaderNodeUVMap")
    uv_node.uv_map = old_name
    for node in tree.nodes:
        if node.type == "TEX_IMAGE":
            tree.links.new(uv_node.outputs["UV"], node.inputs["Vector"])
    if normal_node is not None:
        normal_node.uv_map = old_name  # decode in the old tangent space
    # The new UVs are the render UVs, so the normal bake encodes in their tangent space.
    for layer in me.uv_layers:
        layer.active_render = layer.name == "GameUV"

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16  # anti-aliases the resampling of the old texture
    folder = Path(bpy.data.filepath).parent
    baked = {"color": bake(tree, "DIFFUSE", "texture_game.png", folder, color=True, pass_filter={"COLOR"})}
    if has_roughness:
        baked["roughness"] = bake(tree, "ROUGHNESS", "texture_game_roughness.png", folder)
    if normal_node is not None:
        baked["normal"] = bake(tree, "NORMAL", "texture_game_normal.png", folder, normal_space="TANGENT")

    # Rewire the material to the baked images and drop the old UVs.
    for node in [n for n in tree.nodes if n.type in ("TEX_IMAGE", "SEPARATE_COLOR", "UVMAP")]:
        tree.nodes.remove(node)
    color_node = tree.nodes.new("ShaderNodeTexImage")
    color_node.image = baked["color"][0]
    tree.links.new(color_node.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.0
    if "roughness" in baked:
        rough_node = tree.nodes.new("ShaderNodeTexImage")
        rough_node.image = baked["roughness"][0]
        tree.links.new(rough_node.outputs["Color"], bsdf.inputs["Roughness"])
    if "normal" in baked:
        map_node = tree.nodes.new("ShaderNodeTexImage")
        map_node.image = baked["normal"][0]
        normal_node.uv_map = "GameUV"
        tree.links.new(map_node.outputs["Color"], normal_node.inputs["Color"])
    me.uv_layers.remove(me.uv_layers[old_name])
    me.uv_layers.active = me.uv_layers["GameUV"]
    me.uv_layers["GameUV"].active_render = True
    filled = baked["color"][1]
    print(
        f"[bake] {mesh.name}: UV islands {old_islands} -> {count_islands(me)} ({charts} xatlas charts, "
        f"coverage {coverage:.0%}), texture {SIZE}, padding {PADDING} px, {filled:.0%} of texels filled from the nearest chart; "
        f"maps: {', '.join(baked)}",
        flush=True,
    )
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)


def bake(tree, kind: str, filename: str, folder: Path, color: bool = False, **options):
    """Bakes one map onto GameUV, pads it, saves and packs it. Returns (image, share filled)."""
    image = bpy.data.images.new(Path(filename).stem, SIZE, SIZE, alpha=True, is_data=not color)
    target = tree.nodes.new("ShaderNodeTexImage")
    target.image = image
    tree.nodes.active = target
    bpy.ops.object.bake(
        type=kind,
        uv_layer="GameUV",
        margin=0,  # fill_gaps pads: Blender's margins left black gaps or a grey rim
        use_clear=True,
        **options,
    )
    filled = fill_gaps(image)
    image.filepath_raw = str(folder / filename)
    image.file_format = "PNG"
    image.save()
    image.pack()
    tree.nodes.remove(target)
    return image, filled


def run_xatlas(me):
    """Per-corner UVs (F, 3, 2) from atlas.py, which runs under the system Python (xatlas)."""
    if any(len(p.vertices) != 3 for p in me.polygons):
        raise SystemExit("bake_texture.py expects a triangle mesh (Meshy's is)")
    positions = np.array([v.co[:] for v in me.vertices], dtype=np.float32)
    faces = np.array([p.vertices[:] for p in me.polygons], dtype=np.uint32)
    with tempfile.TemporaryDirectory() as tmp:
        src, dst = Path(tmp) / "mesh.npz", Path(tmp) / "uv.npz"
        np.savez(src, positions=positions, faces=faces)
        result = subprocess.run(["python", str(ATLAS), str(src), str(dst), str(SIZE), str(PADDING)], capture_output=True, text=True)
        if result.returncode != 0:
            raise SystemExit("atlas.py failed:\n" + result.stdout + result.stderr)
        with np.load(dst) as out:  # closed before the folder goes: Windows won't delete an open file
            return out["uv"].copy(), int(out["charts"]), float(out["coverage"])


def fill_gaps(image) -> float:
    """Pads the charts: every texel the bake left empty takes the average of its filled neighbours,
    ring by ring outwards, until none is empty. Partly covered edge texels are un-premultiplied first
    (their colour is scaled down by their coverage). Returns the share of texels filled this way."""
    w, h = image.size
    px = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    alpha = px[..., 3]
    known = alpha > 0.02
    empty_share = 1 - known.mean()
    rgb = np.where(known[..., None], np.clip(px[..., :3] / np.maximum(alpha, 1e-6)[..., None], 0, 1), 0)
    while not known.all():
        total = np.zeros_like(rgb)
        count = np.zeros(known.shape, dtype=np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            shifted_known = np.roll(known, (dy, dx), axis=(0, 1))
            total += np.roll(rgb, (dy, dx), axis=(0, 1)) * shifted_known[..., None]
            count += shifted_known
        grow = ~known & (count > 0)
        rgb[grow] = total[grow] / count[grow][:, None]
        known = known | grow
    px[..., :3] = rgb
    px[..., 3] = 1.0
    image.pixels[:] = px.ravel()
    return float(empty_share)


def count_islands(me) -> int:
    """UV islands: faces joined across an edge whose two loops share UVs on both ends."""
    uv = me.uv_layers.active.data
    parent = list(range(len(me.polygons)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    seen = {}
    for poly in me.polygons:
        loops = list(poly.loop_indices)
        for a, b in zip(loops, loops[1:] + loops[:1]):
            va, vb = me.loops[a].vertex_index, me.loops[b].vertex_index
            key = (min(va, vb), max(va, vb))
            uvs = {va: tuple(round(x, 5) for x in uv[a].uv), vb: tuple(round(x, 5) for x in uv[b].uv)}
            if key in seen:
                other, other_uvs = seen[key]
                if other_uvs == uvs:
                    parent[find(poly.index)] = find(other)
            else:
                seen[key] = (poly.index, uvs)
    return len({find(i) for i in range(len(me.polygons))})


main()
