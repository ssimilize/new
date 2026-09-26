"""Rigs and animates a moth monster (upright body, two wing sheets on its back, antennae, dangling
legs) in headless Blender. Same outputs as rig_quadruped.py; see riglib.py for the shared parts.

  blender -b --factory-startup --python tools/blender/rig_moth.py -- <model.glb> <out dir>

Fitted from the model's own shape:
  wings     where the model turns thin front-to-back: moving out from the middle, the first column
            of the mesh whose depth drops well below the body's is the wing root, and everything
            further out is wing
  body      what is left in the middle; its lowest points are the dangling feet
  antennae  the highest point on each side of the body
The model hovers (LIFT above the ground). Wings flap by swinging back about the vertical axis at
their root, closing behind the back like a butterfly's.
"""

import math
import sys
from pathlib import Path

import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from riglib import X, Y, Z, armature, below_base, chain, finish, footprint_scale, footprints, framed_views, inboard, log, pulse, rot, run, set_game_scale  # noqa: E402
from riglib import about, box, ramp  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1 :]
SRC, OUT = Path(ARGS[0]).resolve(), Path(ARGS[1]).resolve()
LIFT = 0.15  # hover height (m, model 1 m tall)


def fit(mesh) -> dict:
    P = np.array([v.co[:] for v in mesh.data.vertices])
    z0, H = P[:, 2].min(), np.ptp(P[:, 2])

    # Wing root: the body is deep front-to-back, a wing is a thin sheet. Depth per |x| column,
    # measured over the middle of the height (the feet and antennae are thin too).
    band = P[(P[:, 2] > z0 + 0.25 * H) & (P[:, 2] < z0 + 0.85 * H)]
    ax = np.abs(band[:, 0])
    step = 0.02 * H
    depths = []
    for i in range(int(ax.max() / step)):
        col = band[(ax >= i * step) & (ax < (i + 1) * step)]
        depths.append(np.ptp(col[:, 1]) if len(col) > 3 else 0.0)
    depths = np.array(depths)
    body_depth = depths[: max(1, len(depths) // 6)].max()
    thin = np.nonzero(depths < 0.45 * body_depth)[0]
    root_x = float((thin[0] if len(thin) else int(0.6 * len(depths))) * step)
    if ax.max() < 1.3 * root_x:
        raise SystemExit(f"no wings: the model is {ax.max():.2f} wide and thins out at {root_x:.2f}")

    core = P[np.abs(P[:, 0]) < root_x]
    centre_y = float(np.median(core[:, 1]))

    # Antennae: the highest point on each side of the body; they join the head at its crown.
    crown = float(core[np.abs(core[:, 0]) < 0.05 * H][:, 2].max())
    top = core[core[:, 2] > crown - 0.02 * H]
    antennae = {}
    for side, sel in (("L", top[:, 0] > 0.04 * H), ("R", top[:, 0] < -0.04 * H)):
        pts = top[sel]
        if len(pts):
            tip = pts[pts[:, 2].argmax()]
            if tip[2] > crown + 0.06 * H:
                antennae[side] = (np.array([tip[0] * 0.6, tip[1], crown - 0.03 * H]), tip)
    head_top = crown if antennae else float(core[:, 2].max())

    # Feet: the lowest points of the body, if two separate ones hang there.
    feet_pts, blobs = footprints(core, H, 2, 0.03 * H, slices=(0.1, 0.07, 0.05), floor=z0)
    feet = {}
    if len(blobs) >= 2:
        for b in sorted(blobs[:2], key=lambda b: feet_pts[b][:, 0].mean()):
            foot = feet_pts[b].mean(0)
            feet["R" if foot[0] < 0 else "L"] = foot.tolist()
    body_bottom = z0 + (0.22 * H if feet else 0.05 * H)
    neck = body_bottom + 0.55 * (head_top - body_bottom)

    # Wings: one chain per side from the root at the back of the body out to the far edge.
    wings = {}
    for side, sign in (("L", 1), ("R", -1)):
        pts = P[sign * P[:, 0] > root_x]
        near = pts[sign * pts[:, 0] < root_x + 0.05 * H]
        base = near.mean(0) if len(near) else np.array([sign * root_x, centre_y, neck])
        base[0] = sign * root_x
        wings[side] = [j.tolist() for j in chain(pts, base, joints=2)]

    marks = {
        "height": float(H),
        "floor": float(z0),
        "root_x": root_x,
        "centre_y": centre_y,
        "body_bottom": float(body_bottom),
        "neck": float(neck),
        "head_top": float(head_top),
        "antennae": {k: [b.tolist(), t.tolist()] for k, (b, t) in antennae.items()},
        "feet": feet,
        "wings": wings,
    }
    set_game_scale(footprint_scale(P))
    log(f"landmarks: wing root x {root_x:.3f} (model half-width {ax.max():.3f}), body {body_bottom:.2f}..{head_top:.2f}, antennae {len(antennae)}, feet {len(feet)}")
    return marks


def build(marks: dict):
    H = marks["height"]
    arm, bone = armature()
    cy = marks["centre_y"]
    bottom, neck, top = marks["body_bottom"], marks["neck"], marks["head_top"]
    bone("root", (0, cy, 0), (0, cy - 0.25 * H, 0), deform=False)
    bone("body", (0, cy, bottom), (0, cy, neck), "root")
    bone("head", (0, cy, neck), (0, cy, top), "body", connect=True)
    for side, (base, tip) in marks["antennae"].items():
        bone(f"antenna.{side}", base, tip, "head")
    for side, joints in marks["wings"].items():
        j = [Vector(p) for p in joints]
        bone(f"wing.{side}.1", j[0], j[1], "body")
        bone(f"wing.{side}.2", j[1], j[2], f"wing.{side}.1", connect=True)
    for side, foot in marks["feet"].items():
        bone(f"leg.{side}", (foot[0], foot[1], bottom + 0.04 * H), (foot[0], foot[1], foot[2]), "body")
    return finish(arm)


def wings(pose: dict, open_deg: float, bend: float = 0.0):
    """Swings both wings back by open_deg (0 = spread as modelled) about the vertical axis."""
    pose["wing.L.1"] = rot(Z, open_deg)
    pose["wing.R.1"] = rot(Z, -open_deg)
    pose["wing.L.2"] = rot(Z, bend)
    pose["wing.R.2"] = rot(Z, -bend)


def clip_idle(arm, f, n):
    ph = 2 * math.pi * f / n
    flap = 4 * ph  # four slow beats in the 2 s loop
    pose = {"head": rot(Y, 4 * math.sin(ph)) @ rot(X, 3 * math.sin(2 * ph))}
    wings(pose, 32 * (0.5 - 0.5 * math.cos(flap)), 8 * (0.5 - 0.5 * math.cos(flap - 0.8)))
    for side, p in (("L", 0.0), ("R", 1.3)):
        pose[f"antenna.{side}"] = rot(X, 6 * math.sin(2 * ph + p))
        pose[f"leg.{side}"] = rot(X, 8 * math.sin(ph + p))
    return pose, Vector((0, 0, 0.03 * math.sin(ph)))


def clip_walk(arm, f, n):
    ph = 2 * math.pi * f / n
    flap = 2 * ph  # two quick beats in 0.8 s
    pose = {"body": rot(X, 10), "head": rot(X, -8 + 3 * math.sin(flap))}
    wings(pose, 40 * (0.5 - 0.5 * math.cos(flap)), 12 * (0.5 - 0.5 * math.cos(flap - 0.8)))
    for side in ("L", "R"):
        pose[f"antenna.{side}"] = rot(X, 12 + 5 * math.sin(flap))
        pose[f"leg.{side}"] = rot(X, 25)
    # Each beat lifts the body a little.
    return pose, Vector((0, 0, 0.02 + 0.025 * math.sin(flap - 0.5)))


def clip_hop(arm, f, n):
    t = f / n
    up = pulse(t, 0.0, 1.0)
    beat = math.sin(math.pi * 3 * t) ** 2  # three fast beats, closed at both ends
    pose = {"head": rot(X, -8 * up)}
    wings(pose, 45 * beat, 15 * beat)
    for side in ("L", "R"):
        pose[f"antenna.{side}"] = rot(X, 18 * up)
        pose[f"leg.{side}"] = rot(X, 20 * up)
    return pose, Vector((0, 0, 0.22 * up))



# ─── The extra clips (riglib.EXTRA: sleep, eat, cheer, cheer2, attack, hurt, faint, sit, trick) ──


def env(t: float, rise: float = 0.12, fall: float = 0.85) -> float:
    """1 through a one-shot clip, easing in from 0 at its start and back to 0 at its end."""
    return ramp(t, 0.0, rise) * (1 - ramp(t, fall, 1.0))


def centre(arm) -> Vector:
    lo, hi = box(arm)
    return (lo + hi) / 2


def wing_pose(pose, back, up, bend=0.0):
    """back: + swings the wings back (as wings()); up: + raises them; bend: the outer halves."""
    pose["wing.L.1"] = rot(Z, back) @ rot(Y, -up)
    pose["wing.R.1"] = rot(Z, -back) @ rot(Y, up)
    pose["wing.L.2"] = rot(Z, bend)
    pose["wing.R.2"] = rot(Z, -bend)


def feelers(pose, lean, sway=0.0):
    pose["antenna.L"] = rot(X, lean) @ rot(Y, sway)
    pose["antenna.R"] = rot(X, lean) @ rot(Y, -sway)


def clip_sleep(arm, f, n):
    """Lands, folds its wings back over the body like a tent, antennae drooping; slow breaths."""
    b = math.sin(2 * math.pi * f / n)
    pose = {"body": rot(X, 8), "head": rot(X, 18 + 2 * b)}
    wing_pose(pose, 62 - 4 * b, 12, 10)
    feelers(pose, 35)
    for side in ("L", "R"):
        pose[f"leg.{side}"] = rot(X, -20)
    return pose, Vector((0, 0, -LIFT)), 1.0


def clip_eat(arm, f, n):
    """Hovers low, nose down to a flower, sipping with small nods; slow wingbeats."""
    t = f / n
    sip = 0.5 - 0.5 * math.cos(2 * math.pi * 3 * t)
    flap = 0.5 - 0.5 * math.cos(2 * math.pi * 2 * t)
    pose = {"body": rot(X, 22), "head": rot(X, 15 + 8 * sip)}
    wing_pose(pose, 30 * flap, 0, 8 * flap)
    feelers(pose, 20 + 6 * sip)
    return pose, Vector((0, 0, -0.1 + 0.01 * math.sin(2 * math.pi * t)))


def clip_cheer(arm, f, n):
    """Flutters up with a happy wiggle, antennae up."""
    t = f / n
    r = ramp(t, 0.0, 0.25) * (1 - ramp(t, 0.7, 1.0))
    beat = math.sin(math.pi * 6 * t) ** 2
    pose = {"body": rot(Y, 14 * math.sin(4 * math.pi * t) * r), "head": rot(X, -8 * r)}
    wing_pose(pose, 45 * beat, 10 * beat * r, 15 * beat)
    feelers(pose, -15 * r)
    for side in ("L", "R"):
        pose[f"leg.{side}"] = rot(X, 25 * r)
    return pose, Vector((0, 0, 0.2 * r))


def clip_cheer2(arm, f, n):
    """Spreads its wings wide in a display and pops up twice."""
    t = f / n
    e = env(t, 0.15, 0.8)
    pop = max(0.0, math.sin(4 * math.pi * t))
    pose = {"body": rot(X, -12 * e), "head": rot(X, -6 * e)}
    wing_pose(pose, -12 * e + 10 * pop, 18 * e, -6 * e)
    feelers(pose, -18 * e, 10 * e)
    return pose, Vector((0, 0, 0.12 * pop))


def clip_attack(arm, f, n):
    """Rears back and up, then dives forward wings swept back, and recovers."""
    t = f / n
    wind = ramp(t, 0.0, 0.35) * (1 - ramp(t, 0.35, 0.5))
    hit = ramp(t, 0.35, 0.52) * (1 - ramp(t, 0.6, 1.0))
    pose = {"body": rot(X, -20 * wind + 28 * hit), "head": rot(X, 10 * hit)}
    wing_pose(pose, -10 * wind + 55 * hit, 15 * wind, 15 * hit)
    feelers(pose, -20 * (wind + hit))
    return pose, Vector((0, 0.1 * wind - 0.26 * hit, 0.08 * wind - 0.08 * hit))


def clip_hurt(arm, f, n):
    """Knocked back and down in the air, wings crumpling forward."""
    t = f / n
    e = ramp(t, 0.0, 0.15) * (1 - ramp(t, 0.3, 1.0))
    shake = math.sin(2 * math.pi * 5 * t) * e
    pose = {"body": rot(X, -22 * e) @ rot(Y, 10 * shake), "head": rot(X, -10 * e)}
    wing_pose(pose, -12 * e, 10 * e, -10 * e)
    feelers(pose, -30 * e)
    return pose, Vector((0, 0.1 * e, -0.04 * e))


def clip_faint(arm, f, n):
    """Flutters weakly, drifts down to the ground and lies tipped over, wings flat."""
    t = f / n
    fall = ramp(t, 0.2, 0.85)
    flap = (0.5 - 0.5 * math.cos(2 * math.pi * 2 * t)) * (1 - fall)
    q = rot(Y, 25 * fall) @ rot(X, 12 * fall)
    pose = {"body": q, "head": rot(X, 20 * fall)}
    wing_pose(pose, 20 * flap, -8 * fall, 0)
    feelers(pose, 40 * fall)
    for side in ("L", "R"):
        pose[f"leg.{side}"] = rot(X, -30 * fall)
    return pose, about(arm, q, centre(arm), "body") + Vector((0, 0, -LIFT * fall)), fall


def clip_sit(arm, f, n):
    """Lands and rests, wings raised and slowly opening and closing."""
    t = f / n
    b = math.sin(2 * math.pi * t)
    pose = {"body": rot(X, -4), "head": rot(Z, 8 * math.sin(2 * math.pi * t)) @ rot(X, 4)}
    wing_pose(pose, 18, 50 + 18 * b, 6)
    feelers(pose, 8 * math.sin(4 * math.pi * t), 6)
    return pose, Vector((0, 0, -LIFT)), 1.0


def clip_trick(arm, f, n):
    """A barrel roll: rises and turns a full circle about its long axis."""
    t = f / n
    e = env(t)
    q = rot(Y, 360 * ramp(t, 0.1, 0.9))
    beat = math.sin(math.pi * 7 * t) ** 2
    pose = {"body": q, "head": rot(X, -8 * e)}
    wing_pose(pose, 35 * beat, 0, 12 * beat)
    feelers(pose, -20 * e)
    return pose, about(arm, q, centre(arm), "body") + Vector((0, 0, 0.18 * math.sin(math.pi * t)))


EXTRA_CLIPS = {
    "sleep": clip_sleep,
    "eat": clip_eat,
    "cheer": clip_cheer,
    "cheer2": clip_cheer2,
    "attack": clip_attack,
    "hurt": clip_hurt,
    "faint": clip_faint,
    "sit": clip_sit,
    "trick": clip_trick,
}

CLIPS = {"idle": (clip_idle, 60), "walk": (clip_walk, 24), "hop": (clip_hop, 24)}

if __name__ == "__main__":  # add_clips.py imports the clip functions
    run(
        SRC,
        OUT,
        ARGS,
        fit,
        build,
        CLIPS,
        lift=LIFT,
        lift_bone="body",
        give_back=(("antenna.", below_base), ("wing.", inboard)),
        views=framed_views,
        extra=EXTRA_CLIPS,
    )
