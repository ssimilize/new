"""Adds the extra clips (riglib.EXTRA) to a monster already rigged and published, without touching
its skeleton, its skin or its first three clips (those live in the published mesh asset and in
MeshMonsters/<form>.luau). Runs inside Blender; tools/blender/clips.py runs it for many forms.

  blender -b --factory-startup <rig dir>/rig.blend --python tools/blender/add_clips.py -- \
      <form> <rig script> <module dir> <clips dir> [--check] [--previews <out dir> [--only clip,...]]

Opens the rig read-only (nothing is saved back), proves that its bones and its idle, walk and hop
sampled again are byte for byte what <module dir>/<form>.luau holds (and stops with an error if not:
the new clips would be keyed on a skeleton the game does not have), keys the extra clips with the
body type's rig script (its EXTRA_CLIPS), proves the old clips again, and writes
<clips dir>/<form>.luau. --check only proves. --previews renders the new clips' frames into
<out dir>/frames (then previews.py <out dir> makes the GIFs and sheets).
"""

import importlib
import sys
import time
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import clipdata  # noqa: E402
import riglib  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1 :]
FORM, SCRIPT, MODULES, CLIPS = ARGS[0], ARGS[1], Path(ARGS[2]).resolve(), Path(ARGS[3]).resolve()


def main():
    started = time.time()
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    module = MODULES / f"{FORM}.luau"
    if not module.exists():
        raise SystemExit(f"{FORM}: no module at {module}")
    text = module.read_text(encoding="utf-8")
    bpy.context.scene.render.fps = riglib.FPS
    before = clipdata.prove_unchanged(arm, text, FORM)
    riglib.log(f"{FORM}: before: {before}")
    if "--check" in ARGS:
        return

    # The body bone is the one child of the (non-deforming) root in every body type.
    root = arm.data.bones["root"]
    if len(root.children) != 1:
        raise SystemExit(f"{FORM}: root has {len(root.children)} children, expected one body bone")
    lift_bone = root.children[0].name
    rig = importlib.import_module(SCRIPT)
    for name in riglib.EXTRA:
        if name in bpy.data.actions:  # a rig saved with them already: key them afresh
            bpy.data.actions.remove(bpy.data.actions[name])
    actions = riglib.animate_extra(arm, mesh, rig.EXTRA_CLIPS, lift_bone)

    after = clipdata.prove_unchanged(arm, text, FORM)
    riglib.log(f"{FORM}: after keying: {after}")
    extra = clipdata.extras_module(FORM, arm, list(riglib.EXTRA))
    CLIPS.mkdir(parents=True, exist_ok=True)
    (CLIPS / f"{FORM}.luau").write_text(extra, encoding="utf-8", newline="\n")
    riglib.log(f"{FORM}: wrote {len(extra)} characters, {len(actions)} clips in {time.time() - started:.1f} s")

    if "--previews" in ARGS:
        out = Path(ARGS[ARGS.index("--previews") + 1]).resolve()
        out.mkdir(parents=True, exist_ok=True)
        only = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else list(actions)
        shown = {name: action for name, action in actions.items() if name in only}
        riglib.previews(arm, shown, out, views=riglib.framed_views(riglib.points(mesh)), lift_bone=lift_bone)


main()
