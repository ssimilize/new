"""What every body type's rig script shares (rig_quadruped.py, rig_moth.py, rig_slug.py, rig_blob.py,
rig_sprite.py, rig_bunny.py, rig_golem.py, rig_bug.py): import and clean a Meshy model, find shapes in it, build and skin a
skeleton, key clips, export, and render previews. Runs inside Blender; each rig script puts this
folder on sys.path and imports it.

A rig script supplies three things: landmarks fitted from the model's own shape, a skeleton built
from them, and clip functions. Every body type keys the same three clips (idle, walk, hop), which is
what MonsterAnimator plays. Clip functions return (pose, lift): pose maps a bone to a world-axis
rotation, or to (rotation, world offset) for a bone that also moves; lift moves the body bone.

The model is scaled to 1 m tall with its lowest point on the ground (or `lift` above it, for body
types that hover), centred on x and y, facing -y (Blender), as Meshy delivers it.
"""

import itertools
import json
import math
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Quaternion, Vector

FPS = 30
HEIGHT = 1.0  # the model is scaled to 1 m tall; the game scales it to its stage size
X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))


def log(*parts):
    print("[rig]", *parts, flush=True)


# ─── Import and clean ───────────────────────────────────────────────────────────────────


def import_model(src: Path, lift: float = 0.0):
    """Imports the GLB as one welded mesh named "Monster", 1 m tall, standing (or hovering `lift`
    metres) above the ground, centred on x and y."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(src))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in bpy.context.scene.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    mesh = bpy.context.view_layer.objects.active
    # Unparent from any glTF empties, keeping the world transform, then bake it in.
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.context.scene.objects):
        if o is not mesh:
            bpy.data.objects.remove(o)
    mesh.name = "Monster"

    # glTF splits vertices along UV seams; weld them so the surface is one piece again.
    bm = bmesh.new()
    bm.from_mesh(mesh.data)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(mesh.data)
    bm.free()

    # Stand it on the ground, centred, 1 m tall.
    co = np.array([v.co[:] for v in mesh.data.vertices])
    lo, hi = co.min(0), co.max(0)
    scale = HEIGHT / (hi[2] - lo[2])
    offset = Vector((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]))
    for v in mesh.data.vertices:
        v.co = (v.co + offset) * scale
    if lift:
        for v in mesh.data.vertices:
            v.co.z += lift
    log(f"mesh: {before} -> {len(mesh.data.vertices)} verts after welding seams, {len(mesh.data.polygons)} faces")
    return mesh


def islands(mesh) -> int:
    bm = bmesh.new()
    bm.from_mesh(mesh.data)
    seen, count = set(), 0
    for v in bm.verts:
        if v.index in seen:
            continue
        count += 1
        stack = [v]
        while stack:
            x = stack.pop()
            if x.index not in seen:
                seen.add(x.index)
                stack.extend(e.other_vert(x) for e in x.link_edges)
    bm.free()
    return count


def set_game_scale(scale: float):
    """How big the game draws this model relative to a fox of the same stage (export_roblox.py
    writes it into the module as `scale`; MeshMonster multiplies it in). Long or wide body types
    are drawn smaller than their height alone would make them."""
    bpy.context.scene["game_scale"] = float(scale)
    log(f"game scale {scale:.2f}")


def footprint_scale(P: np.ndarray, reference: float = 1.1) -> float:
    """A game scale that keeps a long or wide model's bulk near a fox's: 1 for a model no longer or
    wider than `reference` times its height, shrinking with the square root beyond that."""
    extent = max(np.ptp(P[:, 0]), np.ptp(P[:, 1])) / max(np.ptp(P[:, 2]), 1e-6)
    return min(1.0, math.sqrt(reference / extent))


# ─── Shapes ─────────────────────────────────────────────────────────────────────────────


def points(mesh) -> np.ndarray:
    return np.array([v.co[:] for v in mesh.data.vertices])


def components(points: np.ndarray, cell: float, min_size: int = 3):
    """Connected blobs of 2D (or 3D) points on a grid (8- or 26-neighbour), largest first."""
    if len(points) == 0:
        return []
    steps = list(itertools.product((-1, 0, 1), repeat=points.shape[1]))
    keys = np.floor(points / cell).astype(int)
    cells = {}
    for i, k in enumerate(map(tuple, keys)):
        cells.setdefault(k, []).append(i)
    seen, blobs = set(), []
    for start in cells:
        if start in seen:
            continue
        stack, members = [start], []
        while stack:
            c = stack.pop()
            if c in seen or c not in cells:
                continue
            seen.add(c)
            members.extend(cells[c])
            stack.extend(tuple(a + b for a, b in zip(c, step)) for step in steps)
        if len(members) >= min_size:
            blobs.append(np.array(members))
    blobs.sort(key=len, reverse=True)
    return blobs


def footprints(P: np.ndarray, H: float, want: int, cell: float, slices=(0.08, 0.06, 0.045, 0.03, 0.02), floor: float = 0.0):
    """The blobs of points near the ground (or `floor`), seen from above: (feet points, blobs).
    Feet that touch at the first slice height merge into one blob there, so thinner slices are
    tried until `want` blobs appear."""
    feet, blobs = P[:0], []
    for slice_height in slices:
        feet = P[P[:, 2] < floor + slice_height * H]
        blobs = components(feet[:, :2], cell)
        if len(blobs) >= want:
            break
    return feet, blobs


def surface_samples(mesh, per_triangle: int = 12) -> np.ndarray:
    """Points spread over every triangle (a vertex-only cloud has holes across big faces)."""
    mesh.data.calc_loop_triangles()
    tris = np.array([[mesh.data.vertices[i].co[:] for i in t.vertices] for t in mesh.data.loop_triangles])
    rng = np.random.default_rng(0)
    u, v = rng.random((2, len(tris), per_triangle))
    flip = u + v > 1
    u[flip], v[flip] = 1 - u[flip], 1 - v[flip]
    a, b, c = tris[:, 0, None, :], tris[:, 1, None, :], tris[:, 2, None, :]
    return (a + (b - a) * u[..., None] + (c - a) * v[..., None]).reshape(-1, 3)


def top_pair(P: np.ndarray, H: float, above: float = 0.86, apart: float = 0.05):
    """The highest point on each side (x > 0 is "L", the model's left), among points above
    `above` x height: ear, antenna or eye-stalk tips. {} when nothing sticks up on a side."""
    top = P[P[:, 2] > above * H]
    tips = {}
    for side, sel in (("L", top[:, 0] > apart * H), ("R", top[:, 0] < -apart * H)):
        pts = top[sel]
        if len(pts):
            tips[side] = pts[pts[:, 2].argmax()]
    return tips


def chain(pts: np.ndarray, base: np.ndarray, joints: int = 3):
    """A bone chain through a limb given its points: from `base` out to the far end, with joints at
    the centroids of the points 1/joints, 2/joints, ... of the way out."""
    d = np.linalg.norm(pts - base, axis=1)
    tip = pts[d > np.quantile(d, 0.97)].mean(0)
    out = [base]
    for q in [i / joints for i in range(1, joints)]:
        ring = pts[np.abs(d - q * d.max()) < 0.06 * d.max()]
        out.append(ring.mean(0) if len(ring) else base + (tip - base) * q)
    out.append(tip)
    return out


# ─── Skeleton ───────────────────────────────────────────────────────────────────────────


def armature():
    """Starts an armature in edit mode. Returns (arm, bone): bone(name, head, tail, parent=None,
    deform=True, connect=False) adds an edit bone. Call finish(arm) when done."""
    arm_data = bpy.data.armatures.new("MonsterRig")
    arm = bpy.data.objects.new("MonsterRig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def bone(name, head, tail, parent=None, deform=True, connect=False):
        b = eb.new(name)
        b.head, b.tail = Vector(head), Vector(tail)
        b.use_deform = deform
        if parent:
            b.parent = eb[parent]
            b.use_connect = connect
        # Roll so the bone's Z axis points up (or forward for vertical bones): only for a
        # tidy rig in the editor; the animation works in world axes and ignores roll.
        b.align_roll(Z if abs((b.tail - b.head).normalized().dot(Z)) < 0.9 else -Y)
        return b

    return arm, bone


def finish(arm):
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.data.display_type = "STICK"
    log(f"skeleton: {len(arm.data.bones)} bones")
    return arm


def below_base(v, bone) -> bool:
    """For ears, antennae and eye stalks: a vertex below the bone's base belongs to its parent."""
    return v.co.z < bone.head_local.z


def inboard(v, bone) -> bool:
    """For wings, arms and fins that stick out sideways: a vertex nearer the middle than the
    bone's base belongs to its parent (the body), so a flap never dents the body."""
    return abs(v.co.x) < abs(bone.head_local.x)


def skin(mesh, arm, give_back=(("ear.", below_base),)):
    """Bone-heat skinning with the fixes every body type needs, then at most four bones a vertex.
    give_back: (bone name prefix, test(vertex, bone)): weight a matching bone holds on a vertex the
    test picks goes to the bone's parent instead."""
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    # Bone heat leaves separate pieces it cannot reach (eyes, nose, mouth stuck onto a face)
    # unweighted. Each such vertex copies the weights of the nearest weighted vertex, so a nose
    # moves with the face it sits on. (Nearest BONE is wrong: the nose's nearest bone is the neck.)
    from mathutils.kdtree import KDTree

    groups = {g.index: g.name for g in mesh.vertex_groups}
    weighted = [v for v in mesh.data.vertices if sum(g.weight for g in v.groups) > 1e-6]
    orphans = [v for v in mesh.data.vertices if sum(g.weight for g in v.groups) <= 1e-6]
    tree = KDTree(len(weighted))
    for i, v in enumerate(weighted):
        tree.insert(v.co, i)
    tree.balance()
    for v in orphans:
        _, i, _ = tree.find(v.co)
        for g in weighted[i].groups:
            mesh.vertex_groups[g.group].add([v.index], g.weight, "REPLACE")

    # Limbs own only their own part: bone heat hands an ear the top of the skull too (the head
    # bone ends where the ears begin), so an ear flick would dent the head; a wing likewise takes
    # the flank it sits on.
    for prefix, belongs_to_parent in give_back:
        for bone in arm.data.bones:
            if not bone.name.startswith(prefix) or bone.name not in mesh.vertex_groups or not bone.parent:
                continue
            if bone.parent.name not in mesh.vertex_groups:
                continue
            parent_group = mesh.vertex_groups[bone.parent.name]
            group = mesh.vertex_groups[bone.name]
            for v in mesh.data.vertices:
                if not belongs_to_parent(v, bone):
                    continue
                for g in v.groups:
                    if g.group == group.index and g.weight > 0:
                        parent_group.add([v.index], g.weight, "ADD")
                        group.remove([v.index])
                        break
    # Roblox skins with at most four bones per vertex.
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    per_bone = {name: 0 for name in groups.values()}
    for v in mesh.data.vertices:
        for g in v.groups:
            if g.weight > 0.5:
                per_bone[groups[g.group]] += 1
    log(f"skin: {len(orphans)} unreached vertices copied the weights of their nearest weighted vertex")
    log("skin: vertices mostly owned per bone " + ", ".join(f"{k}={n}" for k, n in per_bone.items()))
    empty = [k for k, n in per_bone.items() if n == 0]
    if empty:
        log("skin: WARNING bones owning no vertex outright: " + ", ".join(empty))
    return len(orphans)


# ─── Animation ──────────────────────────────────────────────────────────────────────────


def rot(axis: Vector, degrees: float) -> Quaternion:
    return Quaternion(axis, math.radians(degrees))


def apply_pose(arm, pose: dict, lift: Vector, lift_bone: str = "hips"):
    """pose: bone -> world-axis rotation (applied about the bone's own joint, on top of its
    parent), or (rotation, world offset). lift: a world offset for the body bone."""
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        rest = pb.bone.matrix_local.to_quaternion()
        entry = pose.get(pb.name, Quaternion())
        q, offset = entry if isinstance(entry, tuple) else (entry, None)
        pb.rotation_quaternion = rest.inverted() @ q @ rest
        if pb.name == lift_bone:
            pb.location = rest.inverted() @ (lift + (offset if offset is not None else Vector()))
        else:
            pb.location = rest.inverted() @ offset if offset is not None else Vector()


def animate(arm, clips: dict, lift_bone: str = "hips", moving=()) -> dict:
    """clips: name -> (function(arm, frame, frames) -> (pose, lift), frames). Keys every bone's
    rotation each frame, and the location of the body bone and of the `moving` bones."""
    arm.animation_data_create()
    actions = {}
    for name, (clip, frames) in clips.items():
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        arm.animation_data.action = action
        for f in range(frames + 1):  # the last frame repeats the first, so the loop closes
            pose, lift = clip(arm, f % frames, frames)
            apply_pose(arm, pose, lift, lift_bone)
            for pb in arm.pose.bones:
                pb.keyframe_insert("rotation_quaternion", frame=f)
                if pb.name == lift_bone or pb.name in moving:
                    pb.keyframe_insert("location", frame=f)
        action.frame_range = (0, frames)
        actions[name] = action
        log(f"clip {name}: {frames} frames at {FPS} fps")
    arm.animation_data.action = actions["idle"]
    return actions


def pulse(t: float, start: float, end: float) -> float:
    """0 outside [start, end], rising to 1 and back as a half sine inside it (t in 0..1)."""
    if t < start or t > end:
        return 0.0
    return math.sin(math.pi * (t - start) / (end - start))


# ─── Output ─────────────────────────────────────────────────────────────────────────────


def export(out: Path):
    bpy.context.scene.render.fps = FPS
    bpy.ops.wm.save_as_mainfile(filepath=str(out / "rig.blend"))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(out / "rig.glb"),
        export_format="GLB",
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_skins=True,
        export_yup=True,
        # Sample and keep every frame, so the clips play exactly as keyed. (Clip lengths are in
        # seconds: a re-import at Blender's default 24 fps shows the 2 s idle as 48 frames.)
        export_optimize_animation_size=False,
        export_force_sampling=True,
    )
    bpy.ops.export_scene.fbx(
        filepath=str(out / "rig.fbx"),
        object_types={"ARMATURE", "MESH"},
        add_leaf_bones=False,
        bake_anim=True,
        bake_anim_use_all_actions=True,
        bake_anim_use_nla_strips=False,
        bake_anim_force_startend_keying=True,
        path_mode="COPY",
        embed_textures=True,
    )
    log("exported rig.blend, rig.glb, rig.fbx")


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = scene.render.resolution_y = 420
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("World")
    world.color = (0.62, 0.76, 0.86)
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.62, 0.76, 0.86, 1)
    bg.inputs[1].default_value = 1.0
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
    scene.collection.objects.link(sun)
    ground = bpy.data.meshes.new("Ground")
    ground.from_pydata([(-3, -3, 0), (3, -3, 0), (3, 3, 0), (-3, 3, 0)], [], [(0, 1, 2, 3)])
    g = bpy.data.objects.new("Ground", ground)
    mat = bpy.data.materials.new("Grass")
    mat.diffuse_color = (0.36, 0.62, 0.3, 1)
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.36, 0.62, 0.3, 1)
    ground.materials.append(mat)
    scene.collection.objects.link(g)
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def aim(cam, eye, target):
    cam.location = eye
    cam.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()


def render(path: Path):
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def project_skeleton(arm, cam) -> list:
    """The skeleton in the current camera's image, as [name, (x, y) head, (x, y) tail] in 0..1."""
    from bpy_extras.object_utils import world_to_camera_view

    scene = bpy.context.scene
    bpy.context.view_layer.update()

    def px(p):
        c = world_to_camera_view(scene, cam, arm.matrix_world @ p)
        return [round(c.x, 4), round(1 - c.y, 4)]

    return [[b.name, px(b.head), px(b.tail)] for b in arm.pose.bones]


VIEWS = {"front34": ((1.9, -2.3, 1.0), (0, 0, 0.45)), "side": ((3.0, 0.05, 0.6), (0, 0.05, 0.45))}


def previews(arm, actions, out: Path, rest_only: bool = False, views=None, lift_bone: str = "hips"):
    """Renders the frames; tools/blender/previews.py (system Python, Pillow) turns them into
    GIFs, contact sheets and skeleton overlays using frames/manifest.json. `views` maps a view name
    to (eye, target); the default frames a model about 1 m long."""
    cam = setup_render()
    views = views or VIEWS
    frames_dir = out / "frames"
    frames_dir.mkdir(exist_ok=True)
    manifest = {"fps": FPS, "rest": {}, "clips": {}}

    arm.animation_data.action = None
    apply_pose(arm, {}, Vector(), lift_bone)
    for view, (eye, target) in views.items():
        aim(cam, eye, target)
        path = frames_dir / f"rest_{view}.png"
        render(path)
        manifest["rest"][view] = {"image": path.name, "bones": project_skeleton(arm, cam)}

    for name, action in actions.items():
        if rest_only:
            break
        arm.animation_data.action = action
        total = int(action.frame_range[1])
        step = 2 if total <= 30 else 3
        manifest["clips"][name] = {"step": step, "views": {}}
        for view, (eye, target) in views.items():
            aim(cam, eye, target)
            files = []
            for f in range(0, total, step):
                bpy.context.scene.frame_set(f)
                path = frames_dir / f"{name}_{view}_{f:03d}.png"
                render(path)
                files.append(path.name)
            manifest["clips"][name]["views"][view] = files
    (frames_dir / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    arm.animation_data.action = actions["idle"]
    log("previews rendered")


def framed_views(P: np.ndarray):
    """Preview cameras pulled back to fit a model bigger than about 1 m across."""
    reach = max(1.0, float(np.ptp(P[:, 0])), float(np.ptp(P[:, 1])), float(np.ptp(P[:, 2])))
    mid = 0.5 * (P[:, 2].min() + P[:, 2].max())
    return {
        "front34": ((1.9 * reach, -2.3 * reach, 1.0 * reach), (0, 0, mid)),
        "side": ((3.0 * reach, 0.05, 0.6 * reach), (0, 0.05, mid)),
    }


def run(src: Path, out: Path, args, fit, build, clips, lift: float = 0.0, lift_bone: str = "hips", moving=(), give_back=(("ear.", below_base),), views=None):
    """The whole rig: import, fit landmarks, build the skeleton, skin, key the clips, export,
    render previews. fit(mesh) -> marks (JSON-able); build(marks) -> armature."""
    out.mkdir(parents=True, exist_ok=True)
    mesh = import_model(src, lift)
    log(f"islands after welding: {islands(mesh)}")
    marks = fit(mesh)
    (out / "landmarks.json").write_text(json.dumps(marks, indent=2), encoding="utf-8")
    arm = build(marks)
    skin(mesh, arm, give_back)
    actions = animate(arm, clips, lift_bone, moving)
    export(out)
    if "--no-preview" not in args:
        previews(arm, actions, out, "--rest-only" in args, views(points(mesh)) if callable(views) else views, lift_bone)
