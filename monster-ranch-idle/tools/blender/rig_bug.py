"""Rigs and animates a bug monster (a round body lying along its length on six stubby legs, antennae
at the front, wings folded on the back, a stinger or tail behind) in headless Blender. Same
outputs as rig_quadruped.py; see riglib.py.

  blender -b --factory-startup --python tools/blender/rig_bug.py -- <model.glb> <out dir>

Fitted from the model's own shape:
  body      the outline of the strip down the middle (|x| small): its top along the length is the
            shell line, its ends the front of the face and the back of the body
  wings,    what rises above the shell line, in 3D pieces: pieces in the front third (or in front
  antennae  of the face) are antennae, the rest wings; one bone each, from where the piece meets
            the body to its far end
  legs      the six largest ground contacts, front to back per side
  stinger   what sticks out behind the back, as a two-bone chain
The body is two bones (the front with the face, and the abdomen, which wags). The walk is a
tripod gait (front and back legs of one side with the middle leg of the other); the wings buzz
through every clip, and the hop is a buzzing jump.
"""

import math
import sys
from pathlib import Path

import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from riglib import X, Y, Z, armature, below_base, chain, components, finish, footprint_scale, footprints, framed_views, log, pulse, rot, run, set_game_scale, surface_samples  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1 :]
SRC, OUT = Path(ARGS[0]).resolve(), Path(ARGS[1]).resolve()
LEG_TOP = 0.13  # stubby legs: the hip is this high (x height) whatever the belly does


def fit(mesh) -> dict:
    P = np.array([v.co[:] for v in mesh.data.vertices])
    H = float(np.ptp(P[:, 2]))
    S = surface_samples(mesh, 6)

    # The strip down the middle: the shell line (its top) and the body's ends at mid-height.
    strip = S[np.abs(S[:, 0]) < 0.04 * H]
    mid = strip[(strip[:, 2] > 0.3 * H) & (strip[:, 2] < 0.6 * H)]
    ys = np.arange(strip[:, 1].min(), strip[:, 1].max(), 0.02 * H)
    top, thick = [], []
    for y in ys:
        col = S[np.abs(S[:, 1] - y) < 0.012 * H]
        centre = col[np.abs(col[:, 0]) < 0.04 * H]
        top.append(centre[:, 2].max() if len(centre) else np.nan)
        thick.append(np.abs(col[:, 0]).max() if len(col) else 0.0)
    top, thick = np.array(top), np.array(thick)
    # The body is the run of wide columns around the widest; a stinger is a thin rod behind it (its
    # star tip is wide again, so a run, not every wide column). Antennae can reach out in front of
    # the face, so the front is also no further forward than the middle strip at mid-height.
    lo = hi = int(np.argmax(thick))
    while lo > 0 and thick[lo - 1] > 0.1 * H:
        lo -= 1
    while hi < len(ys) - 1 and thick[hi + 1] > 0.1 * H:
        hi += 1
    front, back = float(max(ys[lo], mid[:, 1].min())), float(ys[hi])
    inside = (ys >= front) & (ys <= back) & ~np.isnan(top)
    shell = lambda y: np.interp(y, ys[inside], top[inside])  # noqa: E731
    centre_z = float(np.median(mid[:, 2]))

    # Wings and antennae: whatever rises above the shell line, in pieces.
    above = S[((S[:, 1] >= front) & (S[:, 1] <= back) & (S[:, 2] > shell(S[:, 1]) + 0.02 * H) & (np.abs(S[:, 0]) > 0.03 * H)) | ((S[:, 1] < front) & (S[:, 2] > 0.5 * H))]
    wings, antennae = {}, {}
    third = front + (back - front) / 3
    for blob in components(above, 0.025 * H, min_size=30):
        pts = above[blob]
        cx, cy = float(pts[:, 0].mean()), float(pts[:, 1].mean())
        if abs(cx) < 0.05 * H:
            continue  # a crown or a crest on the middle: part of the body
        side = "L" if cx > 0 else "R"
        kind = antennae if cy < third else wings
        if side in kind:
            continue  # the biggest piece of each kind per side wins (pieces come largest first)
        low = pts[pts[:, 2] < np.quantile(pts[:, 2], 0.1)].mean(0)
        base = np.array([low[0], low[1], low[2] - 0.03 * H])
        d = np.linalg.norm(pts - base, axis=1)
        tip = pts[d > np.quantile(d, 0.95)].mean(0)
        kind[side] = [base.tolist(), tip.tolist()]

    # Legs: the six biggest ground contacts, front to back per side.
    feet_pts, blobs = footprints(P, H, 6, 0.03 * H)
    legs = {}
    for side, sign in (("L", 1), ("R", -1)):
        mine = sorted((feet_pts[b].mean(0) for b in blobs[:6] if sign * feet_pts[b][:, 0].mean() > 0), key=lambda p: p[1])
        for i, foot in enumerate(mine[:3]):
            legs[f"{side}.{i + 1}"] = [float(foot[0]), float(foot[1])]

    # Stinger: what sticks out behind the back.
    rod = S[S[:, 1] > back + 0.02 * H]
    stinger = None
    if len(rod) > 30:
        root = np.array([0.0, back - 0.04 * H, float(np.median(rod[rod[:, 1] < back + 0.1 * H][:, 2]))])
        stinger = [j.tolist() for j in chain(rod, root, joints=2)]

    set_game_scale(footprint_scale(P))
    marks = {
        "height": H,
        "front": front,
        "back": back,
        "centre_y": 0.5 * (front + back),
        "centre_z": centre_z,
        "wings": wings,
        "antennae": antennae,
        "legs": legs,
        "stinger": stinger,
    }
    log(f"landmarks: body {front:.2f}..{back:.2f} at z {centre_z:.2f}, wings {len(wings)}, antennae {len(antennae)}, legs {len(legs)}, stinger {'yes' if stinger else 'no'}")
    return marks


def build(marks: dict):
    H = marks["height"]
    arm, bone = armature()
    cy, cz = marks["centre_y"], marks["centre_z"]
    bone("root", (0, cy, 0), (0, cy - 0.25 * H, 0), deform=False)
    bone("body", (0, cy, cz), (0, marks["front"] + 0.1 * H, cz), "root")
    bone("abdomen", (0, cy, cz), (0, marks["back"] - 0.05 * H, cz), "body")
    for side, (base, tip) in marks["antennae"].items():
        bone(f"antenna.{side}", base, tip, "body")
    for side, (base, tip) in marks["wings"].items():
        bone(f"wing.{side}", base, tip, "body")
    for name, (x, y) in marks["legs"].items():
        bone(f"leg.{name}", (x, y, LEG_TOP * H), (x, y, 0.0), "body")
    if marks["stinger"]:
        j = [Vector(p) for p in marks["stinger"]]
        bone("stinger.1", j[0], j[1], "abdomen")
        bone("stinger.2", j[1], j[2], "stinger.1", connect=True)
    return finish(arm)


def ahead_of_root(v, bone) -> bool:
    """For the stinger: a vertex in front of its root is the abdomen's."""
    return v.co.y < bone.head_local.y


def above_hip(v, bone) -> bool:
    """For a leg: a vertex above the hip is the body's."""
    return v.co.z > bone.head_local.z


def buzz(pose: dict, phase: float, amp: float, lift: float = 0.0):
    """Both wings beat about the body's long axis: phase in radians, amp in degrees; lift raises
    them (degrees) for the whole clip."""
    a = lift + amp * math.sin(phase)
    pose["wing.L"] = rot(Y, a)
    pose["wing.R"] = rot(Y, -a)


TRIPOD = {"L.1": 1, "R.2": 1, "L.3": 1, "R.1": -1, "L.2": -1, "R.3": -1}


def clip_idle(arm, f, n):
    ph = 2 * math.pi * f / n
    pose = {
        "body": rot(X, 1.5 * math.sin(2 * ph)),
        "abdomen": rot(Z, 4 * math.sin(ph)) @ rot(X, -2 * math.sin(2 * ph)),
        "stinger.1": rot(Z, 6 * math.sin(ph - 0.6)),
        "stinger.2": rot(Z, 8 * math.sin(ph - 1.2)),
    }
    buzz(pose, 10 * ph, 14)  # ten quick beats in the 2 s loop
    for side, p in (("L", 0.0), ("R", 1.4)):
        pose[f"antenna.{side}"] = rot(X, 6 * math.sin(2 * ph + p)) @ rot(Y, 4 * math.sin(ph + p))
    return pose, Vector((0, 0, 0.006 * (0.5 - 0.5 * math.cos(2 * ph))))


def clip_walk(arm, f, n):
    ph = 2 * math.pi * f / n
    s = math.sin(ph)
    body = rot(Y, 3 * s)
    pose = {
        "body": body,
        "abdomen": rot(Z, -6 * s),
        "stinger.1": rot(Z, -8 * math.sin(ph - 0.7)),
        "stinger.2": rot(Z, -10 * math.sin(ph - 1.4)),
    }
    for name, group in TRIPOD.items():
        pose[f"leg.{name}"] = body.inverted() @ rot(X, -28 * group * s)
    buzz(pose, 6 * ph, 10, 4)
    for side in ("L", "R"):
        pose[f"antenna.{side}"] = rot(X, 5 + 6 * math.sin(2 * ph))
    # Up as each tripod plants, twice a loop.
    return pose, Vector((0, 0, 0.014 * (0.5 + 0.5 * math.cos(2 * ph))))


def clip_hop(arm, f, n):
    t = f / n  # crouch 0-0.2, buzzing up and down 0.2-0.8, land 0.8-1
    crouch = pulse(t, 0.0, 0.2) + pulse(t, 0.8, 1.0)
    air = pulse(t, 0.2, 0.8)
    body = rot(X, 6 * crouch - 10 * air)  # nose up in the air
    pose = {
        "body": body,
        "abdomen": rot(X, 8 * air),
        "stinger.1": rot(X, -15 * air),
        "stinger.2": rot(X, -10 * air),
    }
    for name in TRIPOD:
        pose[f"leg.{name}"] = body.inverted() @ rot(X, 25 * air)  # legs trail back in the air
    buzz(pose, 2 * math.pi * 6 * t, 10 + 25 * air, 10 * air)
    for side in ("L", "R"):
        pose[f"antenna.{side}"] = rot(X, 15 * air - 6 * crouch)
    return pose, Vector((0, 0, 0.2 * air - 0.02 * crouch))


CLIPS = {"idle": (clip_idle, 60), "walk": (clip_walk, 24), "hop": (clip_hop, 30)}

run(
    SRC,
    OUT,
    ARGS,
    fit,
    build,
    CLIPS,
    lift_bone="body",
    give_back=(("antenna.", below_base), ("wing.", below_base), ("stinger.1", ahead_of_root), ("leg.", above_hip)),
    views=framed_views,
)
