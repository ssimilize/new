"""Rigs and animates a bunny monster (sitting upright on big hind feet, long ears or antlers, a puff
of a tail) in headless Blender. Same outputs as rig_quadruped.py; see riglib.py.

  blender -b --factory-startup --python tools/blender/rig_bunny.py -- <model.glb> <out dir>

Fitted from the model's own shape:
  ears   scanning down from the top, the ears (or antlers, or coral) are two or more separate
         pieces in each slice until they join the head: the first slice that is one piece across
         the middle, wide enough to be a head, is the ear base. Each ear gets a two-bone chain.
  neck   a real dip in the outline 52-72% of the way up to the ear base, else 58% of the way
  feet   the front-most ground contact on each side (the hind feet of a sitting bunny; for one
         sitting up on its front legs too, the front paws)
  tail   what sticks out behind the body's back below the neck
The walk is a run of small hops; the ears lag behind the body.
"""

import math
import sys
from pathlib import Path

import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from riglib import X, Y, Z, armature, below_base, chain, components, finish, footprint_scale, framed_views, log, pulse, rot, run, set_game_scale, surface_samples  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1 :]
SRC, OUT = Path(ARGS[0]).resolve(), Path(ARGS[1]).resolve()


def fit(mesh) -> dict:
    P = np.array([v.co[:] for v in mesh.data.vertices])
    H = float(np.ptp(P[:, 2]))
    # Slices are read from points spread over the surface: a big smooth head has so few vertices
    # in a thin slice that it falls apart into pieces (Clovermane's ear base came out at 0.58).
    S = surface_samples(mesh, 6)
    body = S[(S[:, 2] > 0.25 * H) & (S[:, 2] < 0.4 * H)]
    body_w = float(np.ptp(body[:, 0]))

    # Ear base: the first slice, scanning down, that is one piece across the middle and at least
    # half as wide as the body (Mossbun's mushroom crosses the middle but is narrow).
    ear_base = 0.7 * H
    for z in np.arange(0.97, 0.4, -0.01) * H:
        ring = S[np.abs(S[:, 2] - z) < 0.008 * H]
        if len(ring) < 8:
            continue
        pieces = [ring[b] for b in components(ring[:, :2], 0.03 * H, min_size=2)]
        if any(p[:, 0].min() < -0.05 * H and p[:, 0].max() > 0.05 * H and np.ptp(p[:, 0]) > 0.5 * body_w for p in pieces):
            ear_base = float(z)
            break

    ears = {}
    for side, sign in (("L", 1), ("R", -1)):
        pts = P[(sign * P[:, 0] > 0.02 * H) & (P[:, 2] > ear_base)]
        if len(pts) > 30:
            root = pts[pts[:, 2] < ear_base + 0.05 * H].mean(0)
            ears[side] = [j.tolist() for j in chain(pts, root, joints=2)]

    # Neck: a real dip in the outline, at least 8% narrower than the widest slice of the body below
    # it and of the head above it, 52-72% of the way up to the ear base (a chibi's head is about the
    # top 40%; lower dips are between the haunches and the paws), nearest to 58%. Without one (a
    # mane, paws held at the chest, a round head on a round body) the neck goes at 58%. (The
    # narrowest slice alone found the top of Mossbun's round head, and Clovermane's and Thornbuck's
    # haunches.)
    zs = np.arange(0.3 * ear_base, 0.85 * ear_base, 0.01 * H)
    widths = []
    for z in zs:
        ring = S[np.abs(S[:, 2] - z) < 0.008 * H]
        widths.append(float(np.quantile(np.abs(ring[:, 0]), 0.9)) if len(ring) > 8 else np.nan)
    widths = np.array(widths)
    neck = 0.58 * ear_base
    dips = []
    for i in range(1, len(zs) - 1):
        below, above = np.nanmax(widths[:i]), np.nanmax(widths[i + 1 :])
        if not 0.52 * ear_base <= zs[i] <= 0.72 * ear_base:
            continue
        if widths[i] < 0.92 * below and widths[i] < 0.92 * above and widths[i] <= np.nanmin(widths[max(0, i - 3) : i + 4]):
            dips.append(float(zs[i]))
    if dips:
        neck = min(dips, key=lambda z: abs(z - 0.58 * ear_base))
    head_y = float(np.median(P[(P[:, 2] > neck) & (P[:, 2] < ear_base)][:, 1]))
    body_y = float(np.median(P[(P[:, 2] > 0.1 * H) & (P[:, 2] < neck)][:, 1]))

    # Feet: the front of the ground contact on each side.
    ground = P[P[:, 2] < 0.05 * H]
    feet = {}
    for side, sign in (("L", 1), ("R", -1)):
        pts = ground[sign * ground[:, 0] > 0.03 * H]
        if len(pts) > 5:
            front = pts[pts[:, 1] < np.quantile(pts[:, 1], 0.35)]
            feet[side] = [float(front[:, 0].mean()), float(pts[:, 1].mean()), float(np.quantile(pts[:, 1], 0.05))]

    # Tail: behind the back, below the neck.
    back_band = P[(P[:, 2] > 0.15 * H) & (P[:, 2] < neck) & (np.abs(P[:, 0]) < 0.3 * body_w)]
    back = float(np.quantile(back_band[:, 1], 0.8))
    tail_pts = P[(P[:, 1] > back + 0.03 * H) & (P[:, 2] < neck)]
    tail = None
    if len(tail_pts) > 25:
        near = tail_pts[tail_pts[:, 1] < np.quantile(tail_pts[:, 1], 0.15)].mean(0)
        tail = [j.tolist() for j in chain(tail_pts, near, joints=1)]

    set_game_scale(footprint_scale(P))
    marks = {
        "height": H,
        "ear_base": ear_base,
        "neck": neck,
        "head_y": head_y,
        "body_y": body_y,
        "ears": ears,
        "feet": feet,
        "tail": tail,
    }
    log(f"landmarks: ear base {ear_base:.2f}, neck {neck:.2f}, ears {len(ears)}, feet {len(feet)}, tail {'yes' if tail else 'no'}")
    return marks


def build(marks: dict):
    H = marks["height"]
    arm, bone = armature()
    by, hy, neck, top = marks["body_y"], marks["head_y"], marks["neck"], marks["ear_base"]
    chest = 0.5 * (0.12 * H + neck)
    bone("root", (0, by, 0), (0, by - 0.25 * H, 0), deform=False)
    bone("hips", (0, by, 0.12 * H), (0, by, chest), "root")
    bone("chest", (0, by, chest), (0, hy, neck), "hips", connect=True)
    bone("head", (0, hy, neck), (0, hy, top), "chest", connect=True)
    for side, joints in marks["ears"].items():
        j = [Vector(p) for p in joints]
        bone(f"ear.{side}.1", j[0], j[1], "head")
        bone(f"ear.{side}.2", j[1], j[2], f"ear.{side}.1", connect=True)
    for side, (x, heel_y, toe_y) in marks["feet"].items():
        bone(f"foot.{side}", (x, heel_y, 0.1 * H), (x, toe_y, 0.02 * H), "hips")
    if marks["tail"]:
        base, tip = marks["tail"]
        bone("tail", base, tip, "hips")
    return finish(arm)


def ears(pose: dict, lean: float, sway: float = 0.0, flick: float = 0.0):
    """lean: + tips the ears forward, - back; the tips follow further."""
    for side, sign in (("L", 1), ("R", -1)):
        extra = flick if side == "L" else 0.0
        pose[f"ear.{side}.1"] = rot(X, 0.6 * (lean + extra)) @ rot(Y, -sign * sway)
        pose[f"ear.{side}.2"] = rot(X, 0.8 * (lean + extra))


def clip_idle(arm, f, n):
    ph = 2 * math.pi * f / n
    t = f / n
    pose = {
        "chest": rot(X, -1.5 * math.sin(2 * ph)),
        "head": rot(Y, 4 * math.sin(ph)) @ rot(X, 2 * math.sin(2 * ph + 0.5)),
        "tail": rot(Z, 15 * math.sin(4 * ph)),
    }
    ears(pose, 3 * math.sin(ph), 3 * math.sin(2 * ph), -25 * pulse(t, 0.68, 0.8))
    return pose, Vector((0, 0, 0.004 * (1 - math.cos(2 * ph)) / 2))


def clip_walk(arm, f, n):
    t = f / n  # crouch 0-0.2, airborne 0.2-0.8, land 0.8-1: one small hop per loop
    crouch = pulse(t, 0.0, 0.2) + pulse(t, 0.8, 1.0)
    air = pulse(t, 0.2, 0.8)
    pose = {
        "hips": rot(X, 10 * crouch - 6 * air),
        "chest": rot(X, 4 * crouch),
        "head": rot(X, -6 * crouch + 4 * air),
        "tail": rot(X, -15 * air),
    }
    for side in ("L", "R"):
        pose[f"foot.{side}"] = rot(X, -20 * air)
    ears(pose, -18 * air + 10 * crouch)
    return pose, Vector((0, 0, 0.1 * air - 0.02 * crouch))


def clip_hop(arm, f, n):
    t = f / n  # crouch 0-0.25, airborne 0.25-0.75, land 0.75-1
    crouch = pulse(t, 0.0, 0.25) + pulse(t, 0.75, 1.0)
    air = pulse(t, 0.25, 0.75)
    pose = {
        "hips": rot(X, 12 * crouch - 10 * air),
        "chest": rot(X, 6 * crouch - 4 * air),
        "head": rot(X, -8 * crouch - 8 * air),
        "tail": rot(X, -25 * air),
    }
    for side in ("L", "R"):
        pose[f"foot.{side}"] = rot(X, -35 * air)
    ears(pose, -30 * air + 15 * crouch, 8 * air)
    return pose, Vector((0, 0, 0.26 * air - 0.03 * crouch))


CLIPS = {"idle": (clip_idle, 60), "walk": (clip_walk, 20), "hop": (clip_hop, 24)}

run(SRC, OUT, ARGS, fit, build, CLIPS, give_back=(("ear.", below_base),), views=framed_views)
