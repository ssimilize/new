"""Rigs and animates a blob monster (a round body with the face on its front, two stubby feet, and
maybe a tail behind and fins or gills at the sides) in headless Blender. Same outputs as
rig_quadruped.py; see riglib.py.

  blender -b --factory-startup --python tools/blender/rig_blob.py -- <model.glb> <out dir>

Fitted from the model's own shape:
  feet    the two footprints on the ground (none is fine: the body then sits on the ground)
  body    the round mass, centred a little below the middle of its height (between the feet and
          the top of the midline); its width is read in the middle cross-section there
  tail    what sticks out behind the body's back at that height
  fins    what sticks out sideways beyond the body's width, above the feet (gills, frills, little arms)
A blob has no neck: the "top" bone carries the upper half and slides down to squash it (a Bone
transform cannot scale), which is how it breathes, crouches and lands.
"""

import math
import sys
from pathlib import Path

import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from riglib import X, Y, Z, armature, chain, finish, footprint_scale, footprints, framed_views, inboard, log, pulse, rot, run, set_game_scale  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1 :]
SRC, OUT = Path(ARGS[0]).resolve(), Path(ARGS[1]).resolve()


def fit(mesh) -> dict:
    P = np.array([v.co[:] for v in mesh.data.vertices])
    H = float(np.ptp(P[:, 2]))

    feet_pts, blobs = footprints(P, H, 2, 0.035 * H)
    feet = {}
    if len(blobs) >= 2:
        for b in blobs[:2]:
            foot = feet_pts[b].mean(0)
            feet["R" if foot[0] < 0 else "L"] = [float(foot[0]), float(foot[1]), 0.0]
        if len(feet) < 2:
            feet = {}
    foot_top = 0.14 * H if feet else 0.0

    # The body's centre sits a little below the middle of its height, between the feet and the
    # crown (the top of the midline: gills and frills at the sides stand higher). Its width is
    # read in the middle cross-section at that height, where no gill or frill reaches.
    # (The widest slice was the first try: Brinelotl's gills and Pearlfin's frills won it.)
    crown_line = P[np.abs(P[:, 0]) < 0.06 * H]
    crown = float(np.quantile(crown_line[:, 2], 0.99))
    equator = foot_top + 0.45 * (crown - foot_top)
    mid_band = P[(np.abs(P[:, 2] - equator) < 0.08 * H) & (np.abs(P[:, 0]) < 0.12 * H)]
    body_front, body_back = float(mid_band[:, 1].min()), float(np.quantile(mid_band[:, 1], 0.9))
    centre = np.array([0.0, 0.5 * (body_front + body_back), equator])
    cross = P[(np.abs(P[:, 2] - equator) < 0.05 * H) & (np.abs(P[:, 1] - centre[1]) < 0.1 * H)]
    half_width = float(np.abs(cross[:, 0]).max())

    # Tail: behind the back, below the crown.
    tail_pts = P[(P[:, 1] > body_back + 0.04 * H) & (P[:, 2] < crown - 0.1 * H)]
    tail = None
    if len(tail_pts) > 30:
        d = np.linalg.norm(tail_pts - centre, axis=1)
        base = tail_pts[d < np.quantile(d, 0.1)].mean(0)
        tail = [j.tolist() for j in chain(tail_pts, base, joints=3)]

    # Fins: sideways beyond the equator's width, above the feet.
    fins = {}
    for side, sign in (("L", 1), ("R", -1)):
        pts = P[(sign * P[:, 0] > 1.12 * half_width) & (P[:, 2] > foot_top + 0.05 * H)]
        if len(pts) > 30:
            base = pts[sign * pts[:, 0] < np.quantile(sign * pts[:, 0], 0.1)].mean(0)
            base[0] = sign * half_width
            fins[side] = [j.tolist() for j in chain(pts, base, joints=1)]

    set_game_scale(footprint_scale(P))
    marks = {
        "height": H,
        "centre": centre.tolist(),
        "half_width": half_width,
        "foot_top": foot_top,
        "crown": crown,
        "feet": feet,
        "tail": tail,
        "fins": fins,
    }
    log(f"landmarks: equator {equator:.2f} (half width {half_width:.2f}), crown {crown:.2f}, feet {len(feet)}, tail {'yes' if tail else 'no'}, fins {len(fins)}")
    return marks


def build(marks: dict):
    H = marks["height"]
    arm, bone = armature()
    c = Vector(marks["centre"])
    bone("root", (0, c.y, 0), (0, c.y - 0.25 * H, 0), deform=False)
    bone("body", (0, c.y, marks["foot_top"] + 0.02 * H), c, "root")
    bone("top", c, (0, c.y, marks["crown"]), "body", connect=True)
    for side, (x, y, _) in marks["feet"].items():
        bone(f"foot.{side}", (x, y + 0.03 * H, marks["foot_top"] + 0.04 * H), (x, y - 0.03 * H, 0.01 * H), "body")
    if marks["tail"]:
        j = [Vector(p) for p in marks["tail"]]
        bone("tail.1", j[0], j[1], "body")
        bone("tail.2", j[1], j[2], "tail.1", connect=True)
        bone("tail.3", j[2], j[3], "tail.2", connect=True)
    for side, (base, tip) in marks["fins"].items():
        bone(f"fin.{side}", base, tip, "top")
    return finish(arm)


def fin_root(v, bone) -> bool:
    """A fin gives the body back what is inboard of its root AND below it: a frill that curls up
    over the head (Pearlfin's) stays the fin's, or the flap tears it where fin meets head."""
    return inboard(v, bone) and v.co.z < bone.head_local.z


def fins(pose: dict, flap: float):
    pose["fin.L"] = rot(Y, -flap)
    pose["fin.R"] = rot(Y, flap)


def tail(pose: dict, ph: float, amp: float, lift: float = 0.0):
    for i in (1, 2, 3):
        pose[f"tail.{i}"] = rot(Z, amp * math.sin(ph - 0.8 * i)) @ rot(X, lift)


def clip_idle(arm, f, n):
    ph = 2 * math.pi * f / n
    breath = 0.5 - 0.5 * math.cos(2 * ph)
    pose = {"top": (rot(Y, 3 * math.sin(ph)) @ rot(X, -2 * breath), Vector((0, 0, -0.015 * breath)))}
    fins(pose, 8 * math.sin(2 * ph))
    tail(pose, ph, 10)
    return pose, Vector()


def clip_walk(arm, f, n):
    ph = 2 * math.pi * f / n
    # A waddle: the body rocks onto one foot while the other steps forward.
    rock = math.sin(ph)
    pose = {"body": rot(Y, 7 * rock), "top": (rot(Y, -3 * rock), Vector((0, 0, -0.01 * abs(math.cos(ph)))))}
    for side, p in (("L", 0.0), ("R", math.pi)):
        step = max(0.0, math.sin(ph + p))
        pose[f"foot.{side}"] = rot(X, -30 * step + 10 * math.sin(ph + p + math.pi / 2))
    fins(pose, 12 * math.sin(2 * ph))
    tail(pose, ph, 14)
    return pose, Vector((0, 0, 0.03 * abs(math.sin(ph))))


def clip_hop(arm, f, n):
    t = f / n  # crouch 0-0.25, airborne 0.25-0.75, land 0.75-1
    crouch = pulse(t, 0.0, 0.25) + pulse(t, 0.75, 1.0)
    air = pulse(t, 0.25, 0.75)
    pose = {"top": (rot(X, -6 * air), Vector((0, 0, -0.06 * crouch + 0.04 * air)))}
    for side in ("L", "R"):
        pose[f"foot.{side}"] = rot(X, 25 * air)
    fins(pose, 20 * air - 8 * crouch)
    tail(pose, 4 * math.pi * t, 8 * air, -8 * air)
    return pose, Vector((0, 0, 0.24 * air - 0.02 * crouch))


CLIPS = {"idle": (clip_idle, 60), "walk": (clip_walk, 24), "hop": (clip_hop, 24)}

run(SRC, OUT, ARGS, fit, build, CLIPS, lift_bone="body", moving=("top",), give_back=(("fin.", fin_root),), views=framed_views)
