"""Renders a model from the front three-quarter, side, below, front and back three-quarter.

  blender -b --factory-startup --python tools/blender/look.py -- <model.glb> <out prefix> [px] [lens]

px (default 420) is the image size; lens (default 50 mm) zooms in for close-ups.

Writes <out prefix>_front34.png, _side.png, _below.png, _front.png and _back34.png (420 px,
Eevee). The model is stood on the ground and scaled to 1 m tall, the same as the rig script does.
"""

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1 :]
src, prefix = Path(args[0]).resolve(), Path(args[1]).resolve()
size = int(args[2]) if len(args) > 2 else 420
lens = float(args[3]) if len(args) > 3 else 50.0
prefix.parent.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(src))
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
lo = Vector((min((o.matrix_world @ Vector(b)).x for o in meshes for b in o.bound_box), min((o.matrix_world @ Vector(b)).y for o in meshes for b in o.bound_box), min((o.matrix_world @ Vector(b)).z for o in meshes for b in o.bound_box)))
hi = Vector((max((o.matrix_world @ Vector(b)).x for o in meshes for b in o.bound_box), max((o.matrix_world @ Vector(b)).y for o in meshes for b in o.bound_box), max((o.matrix_world @ Vector(b)).z for o in meshes for b in o.bound_box)))
root = bpy.data.objects.new("Root", None)
bpy.context.scene.collection.objects.link(root)
for o in bpy.context.scene.objects:
    if o.parent is None and o is not root:
        o.parent = root
s = 1.0 / (hi.z - lo.z)
root.scale = (s, s, s)
root.location = (-(lo.x + hi.x) / 2 * s, -(lo.y + hi.y) / 2 * s, -lo.z * s)

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = scene.render.resolution_y = size
world = bpy.data.worlds.new("World")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.76, 0.86, 1)
scene.world = world
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 3.0
sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
scene.collection.objects.link(sun)
cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
cam.data.lens = lens
scene.collection.objects.link(cam)
scene.camera = cam

views = {
    "front34": ((1.9, -2.3, 1.0), (0, 0, 0.45)),
    "side": ((3.0, 0.05, 0.6), (0, 0.05, 0.45)),
    "below": ((0.0, 0.3, -2.6), (0, 0, 0.3)),
    "front": ((0.0, -3.0, 0.6), (0, 0, 0.45)),
    "back34": ((-1.9, 2.3, 1.0), (0, 0, 0.45)),
}
for name, (eye, target) in views.items():
    cam.location = eye
    cam.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = f"{prefix}_{name}.png"
    bpy.ops.render.render(write_still=True)
print("[look] wrote", ", ".join(f"{prefix.name}_{n}.png" for n in views))
