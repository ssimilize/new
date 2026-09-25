"""Rigs and animates a golem monster (upright chunky body, big arms hanging at its sides, two short
thick legs) in headless Blender. Same outputs as rig_quadruped.py; see riglib.py.

  blender -b --factory-startup --python tools/blender/rig_golem.py -- <model.glb> <out dir>

Fitted from the model's own shape:
  arms      somewhere down its length a hanging arm stands clear of the body: across a horizontal
            slice, the surface covers |x| from the middle out to the body's side, then nothing, then
            the arm. The gap marks the arm's root; the longest run of such slices is the arm (a
            crystal on a shoulder can leave a gap higher up). Each arm gets a two-bone chain.
            (Slices are read as |x| occupancy per side, not as connected pieces: a rocky surface
            breaks a thin slice into fragments.)
  shoulder  above the arm, where the outline narrows from the arms' span to the head's; the head
            starts there
  legs      the two ground contacts inside the arms; the hip is just above the crotch, the lowest
            point of the body on its centre line
The walk is a heavy side-to-side stomp with the arms swinging against the legs; the hop throws both
fists up.
"""

import math
import sys
from pathlib import Path

import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from riglib import X, Y, Z, armature, chain, finish, footprint_scale, footprints, framed_views, log, pulse, rot, run, set_game_scale, surface_samples  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1 :]
SRC, OUT = Path(ARGS[0]).resolve(), Path(ARGS[1]).resolve()


def arm_gaps(S: np.ndarray, H: float, sign: int):
    """Slices (bottom up) where the arm on this side stands clear of the body:
    [(z, root |x|, outer |x|, gap width)], root being the middle of the gap. The surface samples are
    sparse enough to leave holes of a bin or two inside the body, so those are closed first, and
    the arm is the outermost stretch of |x| the surface covers."""
    step = 0.01 * H
    found = []
    for z in np.arange(0.06, 0.8, 0.01) * H:
        ring = S[np.abs(S[:, 2] - z) < 0.012 * H]
        ax = sign * ring[:, 0]
        ax = ax[ax > 0]
        if len(ax) < 20:
            continue
        bins = np.bincount((ax / step).astype(int))
        covered = np.nonzero(bins >= 2)[0]
        # Stretches of covered bins, joined across holes under 0.025 H.
        stretches = [[covered[0], covered[0] + 1]]
        for b in covered[1:]:
            if (b - stretches[-1][1]) * step < 0.025 * H:
                stretches[-1][1] = b + 1
            else:
                stretches.append([b, b + 1])
        if len(stretches) < 2:
            continue
        (_, inner_end), (outer_start, outer_end) = stretches[-2], stretches[-1]
        if bins[outer_start:].sum() >= 15 and (outer_end - outer_start) * step >= 0.03 * H:
            found.append((float(z), 0.5 * (inner_end + outer_start) * step, float(np.quantile(ax, 0.995)), (outer_start - inner_end) * step))
    return found


def arm_run(gaps: list, H: float) -> list:
    """The longest run of consecutive slices (lowest on a tie): a gap below a shoulder crystal and
    one beside it are two runs. A lone slice counts only with a wide gap (Acornling's nub of an
    arm stands clear in one slice)."""
    runs = []
    for g in gaps:
        if runs and g[0] - runs[-1][-1][0] < 0.015 * H:
            runs[-1].append(g)
        else:
            runs.append([g])
    runs = [r for r in runs if len(r) >= 2 or r[0][3] >= 0.04 * H]
    return max(runs, key=len) if runs else []


def fit(mesh) -> dict:
    P = np.array([v.co[:] for v in mesh.data.vertices])
    H = float(np.ptp(P[:, 2]))
    S = surface_samples(mesh, 8)

    # Arms, and the shoulder above each.
    arms, shoulders, roots = {}, [], []
    for side, sign in (("L", 1), ("R", -1)):
        gaps = arm_run(arm_gaps(S, H, sign), H)
        if not gaps:
            log(f"arm {side}: never clear of the body; no arm bones on this side")
            continue
        root_x = float(np.median([g[1] for g in gaps]))
        outer = max(g[2] for g in gaps)
        shoulder = 0.6 * H
        for z in np.arange(gaps[-1][0], 0.76 * H, 0.02 * H):
            ring = S[(np.abs(S[:, 2] - z) < 0.012 * H) & (sign * S[:, 0] > 0)]
            if len(ring) > 10 and np.quantile(sign * ring[:, 0], 0.99) < 0.8 * outer:
                shoulder = float(z)
                break
        pts = P[(sign * P[:, 0] > root_x) & (P[:, 2] < shoulder)]
        if len(pts) < 30:
            continue
        top = pts[pts[:, 2] > shoulder - 0.1 * H]
        base = top.mean(0) if len(top) else pts.mean(0)
        base[0] = sign * root_x
        base[2] = min(base[2], shoulder - 0.04 * H)
        arms[side] = [j.tolist() for j in chain(pts, base, joints=2)]
        shoulders.append(shoulder)
        roots.append(root_x)
        log(f"arm {side}: clear of the body at {gaps[0][0]:.2f}..{gaps[-1][0]:.2f}, root x {root_x:.3f}, reach {outer:.3f}, shoulder {shoulder:.2f}")
    neck = float(np.mean(shoulders)) if shoulders else 0.55 * H
    inner = min(roots) if roots else 0.3 * H

    # Legs: the ground contacts inside the arms (fists can rest on the ground too).
    central = P[np.abs(P[:, 0]) < inner]
    feet_pts, blobs = footprints(central, H, 2, 0.03 * H)
    feet = {}
    for side, sign in (("L", 1), ("R", -1)):
        mine = [b for b in blobs if sign * feet_pts[b][:, 0].mean() > 0]
        pts = feet_pts[mine[0]] if mine else feet_pts[sign * feet_pts[:, 0] > 0.02 * H]
        if len(pts) > 5:
            feet[side] = [float(pts[:, 0].mean()), float(pts[:, 1].mean())]
    centre_line = S[(np.abs(S[:, 0]) < 0.02 * H) & (S[:, 2] > 0.01 * H) & (S[:, 2] < neck)]
    crotch = float(centre_line[:, 2].min()) if len(centre_line) else 0.1 * H
    hip = float(np.clip(crotch + 0.05 * H, 0.1 * H, 0.3 * H))

    body = P[(P[:, 2] > hip) & (P[:, 2] < neck) & (np.abs(P[:, 0]) < inner)]
    head = P[(P[:, 2] > neck) & (np.abs(P[:, 0]) < inner)]
    set_game_scale(footprint_scale(P))
    marks = {
        "height": H,
        "hip": hip,
        "neck": neck,
        "top": float(P[:, 2].max()),
        "body_y": float(np.median(body[:, 1])) if len(body) else 0.0,
        "head_y": float(np.median(head[:, 1])) if len(head) else 0.0,
        "arms": arms,
        "feet": feet,
    }
    log(f"landmarks: crotch {crotch:.2f}, hip {hip:.2f}, neck {neck:.2f}, arms {len(arms)}, feet {len(feet)}")
    return marks


def build(marks: dict):
    H = marks["height"]
    arm, bone = armature()
    by, hy, hip, neck = marks["body_y"], marks["head_y"], marks["hip"], marks["neck"]
    chest = hip + 0.5 * (neck - hip)
    bone("root", (0, by, 0), (0, by - 0.25 * H, 0), deform=False)
    bone("hips", (0, by, hip), (0, by, chest), "root")
    bone("chest", (0, by, chest), (0, hy, neck), "hips", connect=True)
    bone("head", (0, hy, neck), (0, hy, marks["top"]), "chest", connect=True)
    for side, joints in marks["arms"].items():
        j = [Vector(p) for p in joints]
        bone(f"arm.{side}.1", j[0], j[1], "chest")
        bone(f"arm.{side}.2", j[1], j[2], f"arm.{side}.1", connect=True)
    for side, (x, y) in marks["feet"].items():
        bone(f"leg.{side}", (x, y, hip), (x, y, 0.02 * H), "hips")
    return finish(arm)


def shoulder_inboard(v, bone) -> bool:
    """For an upper arm: at the shoulder, a vertex nearer the middle than the arm's root is the
    body's. Only at the shoulder: lower down a big fist reaches in past the root, and handing its
    inner half to the chest left it behind as strands when the arm swung up."""
    return abs(v.co.x) < abs(bone.head_local.x) and v.co.z > bone.head_local.z - 0.1


def above_hip(v, bone) -> bool:
    """For a leg: a vertex above the hip is the body's (bone heat hands a short thick leg the belly)."""
    return v.co.z > bone.head_local.z


def arms_pose(pose: dict, swing_l: float, swing_r: float, out: float = 0.0, bend: float = 0.0):
    """swing: + swings the arm back, - forward (degrees about X); out: spreads both arms outward."""
    for side, sign, swing in (("L", 1, swing_l), ("R", -1, swing_r)):
        pose[f"arm.{side}.1"] = rot(X, swing) @ rot(Y, -sign * out)
        pose[f"arm.{side}.2"] = rot(X, -bend)


def clip_idle(arm, f, n):
    ph = 2 * math.pi * f / n
    pose = {
        "chest": rot(X, -1.5 * math.sin(2 * ph)),
        "head": rot(Z, 7 * math.sin(ph)) @ rot(X, 2 * math.sin(2 * ph + 0.6)),
    }
    arms_pose(pose, 3 * math.sin(ph), 3 * math.sin(ph + 1.2), 2 + 2 * math.sin(2 * ph), 4)
    return pose, Vector((0, 0, 0.006 * (0.5 - 0.5 * math.cos(2 * ph))))


def clip_walk(arm, f, n):
    ph = 2 * math.pi * f / n
    s = math.sin(ph)
    hips = rot(Y, 5 * s) @ rot(Z, 4 * s)  # weight rolls onto the planted leg; the pelvis twists with the stride
    pose = {
        "hips": hips,
        "chest": rot(Y, -3 * s) @ rot(Z, -7 * s),  # the shoulders twist against the hips
        "head": rot(Y, -2 * s) @ rot(X, 2 * math.sin(2 * ph)),
    }
    # The legs swing in world axes whatever the hips do.
    pose["leg.L"] = hips.inverted() @ rot(X, -22 * s)
    pose["leg.R"] = hips.inverted() @ rot(X, 22 * s)
    arms_pose(pose, 18 * s, -18 * s, 4, 10)
    # Highest when the legs pass each other, lowest with both feet down.
    return pose, Vector((0, 0, 0.022 * (0.5 + 0.5 * math.cos(2 * ph))))


def clip_hop(arm, f, n):
    t = f / n  # crouch 0-0.25, airborne 0.25-0.7, stomp 0.7-1
    crouch = pulse(t, 0.0, 0.25) + pulse(t, 0.7, 1.0)
    air = pulse(t, 0.25, 0.7)
    hips = rot(X, 8 * crouch - 5 * air)
    pose = {
        "hips": hips,
        "chest": rot(X, 6 * crouch - 8 * air),
        "head": rot(X, 4 * crouch - 10 * air),
    }
    pose["leg.L"] = hips.inverted() @ rot(X, -18 * air)
    pose["leg.R"] = hips.inverted() @ rot(X, -18 * air)
    arms_pose(pose, -80 * air + 10 * crouch, -80 * air + 10 * crouch, 25 * air, 20 * air)
    return pose, Vector((0, 0, 0.17 * air - 0.035 * crouch))


CLIPS = {"idle": (clip_idle, 60), "walk": (clip_walk, 30), "hop": (clip_hop, 30)}

run(
    SRC,
    OUT,
    ARGS,
    fit,
    build,
    CLIPS,
    give_back=(("arm.L.1", shoulder_inboard), ("arm.R.1", shoulder_inboard), ("leg.", above_hip)),
    views=framed_views,
)
