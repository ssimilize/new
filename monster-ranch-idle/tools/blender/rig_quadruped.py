"""Rigs and animates a four-legged monster model (the fox body type) in headless Blender.

  blender -b --factory-startup --python tools/blender/rig_quadruped.py -- <model.glb> <out dir>

The skeleton is fitted to the model from its own shape, so one script serves every model of the
body type whatever its proportions: paws are the four footprints on the ground, the legs end where
the footprints merge into the body, the head is the high mass at the front, the ears are its two
highest points, and the tail is what sticks out behind the hips.

Expects a model standing on four legs, facing glTF +Z (Blender -Y), as Meshy delivers it.

Writes to <out dir>:
  rig.blend          the rigged model with every clip as an action (the editable source)
  rig.glb            model + skeleton + all clips (idle, walk, hop)
  rig.fbx            the same as FBX, one take per clip
  landmarks.json     the fitted joint positions (metres, Blender axes)
  preview_*.png      rest pose with the skeleton drawn on, and contact sheets per clip
  preview_*.gif      the clips, looping
"""

import math
import sys
from pathlib import Path

import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from riglib import X, Y, Z, armature, finish, footprints, log, rot, run, surface_samples  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1 :]
SRC, OUT = Path(ARGS[0]).resolve(), Path(ARGS[1]).resolve()


# ─── Landmarks ──────────────────────────────────────────────────────────────────────────


def fit_landmarks(mesh) -> dict:
    P = np.array([v.co[:] for v in mesh.data.vertices])
    H = P[:, 2].max()
    cell = 0.035 * H

    # Paws: the footprints on the ground. Chubby paws that touch at 8% of the height (Petalpaw's,
    # Blossomcat's front pair) merge into one footprint there, so thinner slices are tried too.
    feet, blobs = footprints(P, H, 4, cell)
    if len(blobs) < 4:
        raise SystemExit(f"expected four footprints, found {len(blobs)} (down to a 2% slice)")
    paws = [feet[b][:, :2].mean(0) for b in blobs[:4]]
    paws.sort(key=lambda p: p[1])  # front (-y) first
    front, back = sorted(paws[:2], key=lambda p: p[0]), sorted(paws[2:], key=lambda p: p[0])
    # Blender's .L is the model's left: +x when it faces -y.
    paw = {"front.R": front[0], "front.L": front[1], "back.R": back[0], "back.L": back[1]}

    front_y = (front[0][1] + front[1][1]) / 2
    back_y = (back[0][1] + back[1][1]) / 2
    length = back_y - front_y

    # Leg top: where the legs meet the body, read from the side silhouette: the lowest height at
    # which the outline between the front and back legs is closed (solid body, not a gap under
    # the belly). The surface is sampled densely so thin legs and big faces leave no holes.
    # (Earlier tries: the belly's centre hangs low between the legs on chubby models; the lowest
    # flank point catches slanted leg surfaces on long-legged ones.)
    S = surface_samples(mesh)
    cell = 0.02 * H
    gap = (S[:, 1] > front_y + 0.25 * length) & (S[:, 1] < back_y - 0.25 * length)
    span = np.arange(front_y + 0.25 * length, back_y - 0.25 * length, cell)
    leg_top = 0.3 * H
    for z in np.arange(0.03, 0.8, 0.01) * H:
        row = S[gap & (np.abs(S[:, 2] - z) < cell)]
        if len(row) == 0:
            continue
        filled = np.unique(np.floor((row[:, 1] - span[0]) / cell).astype(int))
        if len(filled) >= 0.9 * len(span):
            leg_top = float(z)
            break

    def column(y0, half, x_half=0.2):
        sel = P[(np.abs(P[:, 1] - y0) < half) & (np.abs(P[:, 0]) < x_half * H) & (P[:, 2] > leg_top)]
        return sel[:, 2].min(), sel[:, 2].max()

    # Spine height: the middle of the torso at the hips, raised a little toward the chest.
    hip_lo, hip_hi = column(back_y, 0.06 * H)
    spine_z = leg_top + 0.45 * (hip_hi - leg_top)

    # Head: the mass above the spine in front of the body's middle.
    head_pts = P[(P[:, 1] < front_y + 0.25 * length) & (P[:, 2] > spine_z + 0.12 * H)]
    head_c = head_pts.mean(0)
    # Ears: the highest points on either side.
    top = P[P[:, 2] > 0.86 * H]
    ears = {}
    for side, sel in (("L", top[:, 0] > 0.05 * H), ("R", top[:, 0] < -0.05 * H)):
        pts = top[sel]
        if len(pts):
            tip = pts[pts[:, 2].argmax()]
            base_band = P[(np.abs(P[:, 0] - tip[0]) < 0.12 * H) & (P[:, 2] > 0.74 * H) & (P[:, 2] < 0.8 * H) & (P[:, 1] < front_y + 0.4 * length)]
            base = base_band.mean(0) if len(base_band) else tip - np.array([0, 0, 0.15 * H])
            ears[side] = (base, tip)
    head_top_z = max((e[0][2] for e in ears.values()), default=head_pts[:, 2].max())

    # Tail: what sticks out behind the hips, above the legs.
    behind = back_y + 0.35 * (P[:, 1].max() - back_y)
    tail_pts = P[(P[:, 1] > behind) & (P[:, 2] > leg_top * 0.8)]
    hip = np.array([0.0, back_y, spine_z])
    tail = None
    if len(tail_pts) > 20:
        d_hip = np.linalg.norm(tail_pts - hip, axis=1)
        base = tail_pts[d_hip < np.quantile(d_hip, 0.08)].mean(0)
        d = np.linalg.norm(tail_pts - base, axis=1)
        tip = tail_pts[d > np.quantile(d, 0.97)].mean(0)
        # Joints along the tail: centroids of the points at 1/3 and 2/3 of the way out.
        joints = [base]
        for q in (1 / 3, 2 / 3):
            ring = tail_pts[np.abs(d - q * d.max()) < 0.06 * d.max()]
            joints.append(ring.mean(0) if len(ring) else base + (tip - base) * q)
        joints.append(tip)
        tail = joints

    marks = {
        "height": H,
        "leg_top": leg_top,
        "spine_z": spine_z,
        "paws": {k: [float(v[0]), float(v[1])] for k, v in paw.items()},
        "hip": hip.tolist(),
        "chest": [0.0, front_y, spine_z + 0.08 * H],
        "head_center": head_c.tolist(),
        "head_top_z": float(head_top_z),
        "ears": {k: [b.tolist(), t.tolist()] for k, (b, t) in ears.items()},
        "tail": [j.tolist() for j in tail] if tail else None,
    }
    log(f"landmarks: leg top {leg_top:.3f}, spine {spine_z:.3f}, paws {len(paw)}, ears {len(ears)}, tail {'yes' if tail else 'no'}")
    return marks


# ─── Skeleton ───────────────────────────────────────────────────────────────────────────


def build_armature(marks: dict):
    H = marks["height"]
    arm, bone = armature()

    hip, chest = Vector(marks["hip"]), Vector(marks["chest"])
    mid = (hip + chest) / 2 + Vector((0, 0, 0.03 * H))
    head_c = Vector(marks["head_center"])
    head_base = Vector((0, chest.y + 0.35 * (head_c.y - chest.y), chest.z + 0.55 * (head_c.z - chest.z)))
    head_top = Vector((0, head_c.y, marks["head_top_z"]))

    bone("root", (0, (hip.y + chest.y) / 2, 0), (0, (hip.y + chest.y) / 2 - 0.25 * H, 0), deform=False)
    bone("hips", hip, mid, "root")
    bone("chest", mid, chest, "hips", connect=True)
    bone("neck", chest, head_base, "chest", connect=True)
    bone("head", head_base, head_top, "neck", connect=True)
    for side, (base, tip) in marks["ears"].items():
        bone(f"ear.{side}", base, tip, "head")
    if marks["tail"]:
        j = [Vector(p) for p in marks["tail"]]
        bone("tail.1", j[0], j[1], "hips")
        bone("tail.2", j[1], j[2], "tail.1", connect=True)
        bone("tail.3", j[2], j[3], "tail.2", connect=True)

    top = marks["leg_top"]
    joint_z = top + 0.35 * (marks["spine_z"] - top)
    for key, (px, py) in marks["paws"].items():
        end, side = key.split(".")
        upper, lower = ("upperarm", "forearm") if end == "front" else ("thigh", "shin")
        parent = "chest" if end == "front" else "hips"
        # Knees sit a touch behind the paw column (elbows and hocks bend the same way here).
        knee = (px, py + 0.02 * H, 0.5 * top)
        bone(f"{upper}.{side}", (px, py, joint_z), knee, parent)
        bone(f"{lower}.{side}", knee, (px, py - 0.01 * H, 0.02 * H), f"{upper}.{side}", connect=True)
    return finish(arm)


# ─── Animation ──────────────────────────────────────────────────────────────────────────


def legs(arm):
    return [b.name for b in arm.data.bones if b.name.split(".")[0] in ("upperarm", "thigh")]


def clip_idle(arm, f, n):
    ph = 2 * math.pi * f / n
    pose = {
        "chest": rot(X, -1.5 * math.sin(ph)),
        "neck": rot(X, 2 * math.sin(2 * ph)),
        "head": rot(Y, 5 * math.sin(ph)) @ rot(X, -2 * math.sin(2 * ph + 0.5)),
    }
    for i in (1, 2, 3):
        pose[f"tail.{i}"] = rot(Z, 14 * math.sin(ph - 0.7 * i))
    # One ear flicks near the end of the loop.
    flick = max(0.0, math.sin(math.pi * (f - 0.7 * n) / (0.12 * n))) if 0.7 * n <= f <= 0.82 * n else 0.0
    pose["ear.L"] = rot(X, -25 * flick)
    pose["ear.R"] = rot(X, 3 * math.sin(ph))
    return pose, Vector((0, 0, 0.006 * (1 - math.cos(2 * ph)) / 2))


def clip_walk(arm, f, n):
    ph = 2 * math.pi * f / n
    pose = {}
    # Trot: diagonal pairs move together.
    phase = {"upperarm.L": 0, "thigh.R": 0, "upperarm.R": math.pi, "thigh.L": math.pi}
    for name, p in phase.items():
        side = name.split(".")[1]
        lower = ("forearm." if name.startswith("upper") else "shin.") + side
        swing = math.sin(ph + p)  # +: paw back (stance), rising: paw moving back on the ground
        lift = max(0.0, -math.cos(ph + p))  # swing phase: paw travelling forward, off the ground
        pose[name] = rot(X, 24 * swing - 10 * lift)
        pose[lower] = rot(X, 38 * lift)
    pose["hips"] = rot(Y, 3 * math.sin(ph))
    pose["chest"] = rot(Y, -3 * math.sin(ph))
    pose["neck"] = rot(X, 3 * math.sin(2 * ph))
    pose["head"] = rot(X, -3 * math.sin(2 * ph + 0.6)) @ rot(Z, 2 * math.sin(ph))
    for i in (1, 2, 3):
        pose[f"tail.{i}"] = rot(Z, 12 * math.sin(ph - 0.8 * i)) @ rot(X, -5)
    for side, p in (("L", 0.4), ("R", 0.9)):
        pose[f"ear.{side}"] = rot(X, 6 * math.sin(2 * ph + p))
    bob = 0.025 * (1 - math.cos(2 * ph)) / 2
    return pose, Vector((0, 0, bob))


def clip_hop(arm, f, n):
    t = f / n  # crouch 0-0.25, airborne 0.25-0.75, land 0.75-1
    crouch = math.sin(math.pi * min(1, t / 0.25)) if t < 0.25 else (math.sin(math.pi * (t - 0.75) / 0.25) if t > 0.75 else 0.0)
    air = math.sin(math.pi * (t - 0.25) / 0.5) if 0.25 <= t <= 0.75 else 0.0
    height = 0.22 * air - 0.05 * crouch
    pose = {}
    for name in legs(arm):
        side = name.split(".")[1]
        lower = ("forearm." if name.startswith("upper") else "shin.") + side
        front = name.startswith("upper")
        # Crouch folds the legs; in the air the front legs reach forward and the back legs trail.
        pose[name] = rot(X, (-20 if front else 20) * crouch + (-25 if front else 30) * air)
        pose[lower] = rot(X, 35 * crouch + 25 * air)
    pose["hips"] = rot(X, -8 * air)
    pose["neck"] = rot(X, -10 * air + 6 * crouch)
    pose["head"] = rot(X, -6 * air)
    for i in (1, 2, 3):
        pose[f"tail.{i}"] = rot(X, -18 * air + 8 * crouch)
    for side in ("L", "R"):
        pose[f"ear.{side}"] = rot(X, 20 * air - 10 * crouch)
    return pose, Vector((0, 0, height))


CLIPS = {"idle": (clip_idle, 60), "walk": (clip_walk, 24), "hop": (clip_hop, 24)}


run(SRC, OUT, ARGS, fit_landmarks, build_armature, CLIPS)
