"""Rigs and animates a sprite monster (a small round floating body, tiny arms, a wispy tail trailing
behind) in headless Blender. Same outputs as rig_quadruped.py; see riglib.py.

  blender -b --factory-startup --python tools/blender/rig_sprite.py -- <model.glb> <out dir>

Fitted from the model's own shape:
  body   a sphere through the upper half of the model: centred on it, as big as its typical
         distance from that centre
  tail   what lies well outside that sphere, behind and below its centre
  arms   what sticks out sideways past the sphere below its centre (cloud puffs can hide them:
         then there are none)
  head   from the centre up to the crown (a droplet or tuft on top rides along)
The model hovers (LIFT above the ground) and bobs; the tail trails with a wave.
"""

import math
import sys
from pathlib import Path

import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from riglib import X, Y, Z, armature, chain, finish, footprint_scale, framed_views, inboard, log, pulse, rot, run, set_game_scale  # noqa: E402
from riglib import about, box, ramp  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1 :]
SRC, OUT = Path(ARGS[0]).resolve(), Path(ARGS[1]).resolve()
LIFT = 0.15  # hover height (m, model 1 m tall)


def fit(mesh) -> dict:
    P = np.array([v.co[:] for v in mesh.data.vertices])
    z0, H = P[:, 2].min(), float(np.ptp(P[:, 2]))

    upper = P[P[:, 2] > np.median(P[:, 2])]
    centre = np.array([0.0, float(np.median(upper[:, 1])), float(np.median(upper[:, 2]))])
    radius = float(np.median(np.linalg.norm(upper - centre, axis=1)))
    # The centre of the sphere through the upper half sits high; the body's middle is lower.
    centre[2] -= 0.35 * radius
    d = np.linalg.norm(P - centre, axis=1)
    crown_line = P[np.abs(P[:, 0]) < 0.06 * H]
    crown = float(crown_line[:, 2].max())

    tail_pts = P[(d > 1.2 * radius) & (P[:, 1] > centre[1]) & (P[:, 2] < centre[2])]
    tail = None
    if len(tail_pts) > 30:
        dt = np.linalg.norm(tail_pts - centre, axis=1)
        base = tail_pts[dt < np.quantile(dt, 0.1)].mean(0)
        tail = [j.tolist() for j in chain(tail_pts, base, joints=3)]

    arms = {}
    for side, sign in (("L", 1), ("R", -1)):
        pts = P[(sign * P[:, 0] > 1.02 * radius) & (P[:, 2] < centre[2] + 0.1 * radius) & (np.abs(P[:, 1] - centre[1]) < 0.6 * radius)]
        if len(pts) > 25:
            base = np.array([sign * 0.8 * radius, float(pts[:, 1].mean()), float(pts[:, 2].mean())])
            arms[side] = [j.tolist() for j in chain(pts, base, joints=1)]

    set_game_scale(footprint_scale(P))
    marks = {
        "height": H,
        "floor": float(z0),
        "centre": centre.tolist(),
        "radius": radius,
        "crown": crown,
        "tail": tail,
        "arms": arms,
    }
    log(f"landmarks: body centre z {centre[2]:.2f}, radius {radius:.2f}, crown {crown:.2f}, tail {'yes' if tail else 'no'}, arms {len(arms)}")
    return marks


def build(marks: dict):
    H = marks["height"]
    arm, bone = armature()
    c, r = Vector(marks["centre"]), marks["radius"]
    bone("root", (0, c.y, 0), (0, c.y - 0.25 * H, 0), deform=False)
    bone("body", (0, c.y, c.z - 0.6 * r), c, "root")
    bone("head", c, (0, c.y, marks["crown"]), "body", connect=True)
    for side, (base, tip) in marks["arms"].items():
        bone(f"arm.{side}", base, tip, "body")
    if marks["tail"]:
        j = [Vector(p) for p in marks["tail"]]
        bone("tail.1", j[0], j[1], "body")
        bone("tail.2", j[1], j[2], "tail.1", connect=True)
        bone("tail.3", j[2], j[3], "tail.2", connect=True)
    return finish(arm)


def arms(pose: dict, raise_deg: float, wave: float = 0.0):
    pose["arm.L"] = rot(Y, -raise_deg - wave)
    pose["arm.R"] = rot(Y, raise_deg - wave)


def tail(pose: dict, ph: float, sway: float, lift: float):
    for i in (1, 2, 3):
        pose[f"tail.{i}"] = rot(Z, sway * math.sin(ph - 0.9 * i)) @ rot(X, lift + 0.5 * sway * math.sin(ph - 0.9 * i + 1))


def clip_idle(arm, f, n):
    ph = 2 * math.pi * f / n
    pose = {"head": rot(Y, 4 * math.sin(ph)) @ rot(X, 3 * math.sin(2 * ph))}
    arms(pose, 10 * math.sin(2 * ph), 6 * math.sin(ph))
    tail(pose, 2 * ph, 12, 0)
    return pose, Vector((0, 0, 0.035 * math.sin(ph)))


def clip_walk(arm, f, n):
    ph = 2 * math.pi * f / n
    pose = {"body": rot(X, 12), "head": rot(X, -6)}
    arms(pose, -15 + 8 * math.sin(2 * ph))
    tail(pose, 2 * ph, 14, 10)  # streams out behind
    return pose, Vector((0, 0, 0.02 + 0.02 * math.sin(2 * ph)))


def clip_hop(arm, f, n):
    t = f / n
    up = pulse(t, 0.0, 1.0)
    pose = {"head": rot(X, -10 * up)}
    arms(pose, 55 * up, 15 * math.sin(4 * math.pi * t) * up)
    tail(pose, 4 * math.pi * t, 18 * up, -15 * up)
    return pose, Vector((0, 0, 0.22 * up))



# ─── The extra clips (riglib.EXTRA: sleep, eat, cheer, cheer2, attack, hurt, faint, sit, trick) ──


def env(t: float, rise: float = 0.12, fall: float = 0.85) -> float:
    """1 through a one-shot clip, easing in from 0 at its start and back to 0 at its end."""
    return ramp(t, 0.0, rise) * (1 - ramp(t, fall, 1.0))


def centre(arm) -> Vector:
    lo, hi = box(arm)
    return (lo + hi) / 2


def reach(pose, forward, down=0.0):
    """Both arms swung forward (degrees) and lowered (degrees)."""
    pose["arm.L"] = rot(Z, -forward) @ rot(Y, down)
    pose["arm.R"] = rot(Z, forward) @ rot(Y, -down)


def curl(pose, side, droop):
    for i in (1, 2, 3):
        pose[f"tail.{i}"] = rot(Z, side) @ rot(X, droop)


def clip_sleep(arm, f, n):
    """Lands and curls up, arms hugged in, tail wrapped round; slow breaths."""
    b = math.sin(2 * math.pi * f / n)
    pose = {"body": rot(X, 22 + 1.5 * b), "head": rot(X, 18 + 2 * b)}
    reach(pose, 45, 30)
    curl(pose, 30, 25)  # tucked up: a hanging tail would prop the body off the ground
    return pose, Vector((0, 0, -LIFT)), 1.0


def clip_eat(arm, f, n):
    """Hovers low, nose down, nibbling from its hands."""
    t = f / n
    chew = 0.5 - 0.5 * math.cos(2 * math.pi * 3 * t)
    pose = {"body": rot(X, 25), "head": rot(X, 15 + 8 * chew)}
    reach(pose, 60 + 8 * chew, -20)
    tail(pose, 4 * math.pi * t, 10, 5)
    return pose, Vector((0, 0, -0.08 + 0.015 * math.sin(2 * math.pi * t)))


def clip_cheer(arm, f, n):
    """Rises with both arms up, waving, swaying side to side."""
    t = f / n
    r = ramp(t, 0.0, 0.25) * (1 - ramp(t, 0.7, 1.0))
    pose = {"body": rot(Y, 10 * math.sin(4 * math.pi * t) * r), "head": rot(X, -10 * r)}
    arms(pose, 70 * r, 25 * math.sin(6 * math.pi * t) * r)
    tail(pose, 4 * math.pi * t, 18 * r, -12 * r)
    return pose, Vector((0, 0, 0.2 * r))


def clip_cheer2(arm, f, n):
    """Claps in front and bobs twice, head tilting."""
    t = f / n
    e = env(t)
    clap = 0.5 - 0.5 * math.cos(6 * math.pi * t)
    pose = {"head": rot(Y, 12 * math.sin(4 * math.pi * t) * e) @ rot(X, -6 * e)}
    reach(pose, (40 + 30 * clap) * e, -15 * e)
    tail(pose, 4 * math.pi * t, 14 * e, 0)
    return pose, Vector((0, 0, 0.08 * abs(math.sin(4 * math.pi * t)) * e))


def clip_attack(arm, f, n):
    """Pulls back and up, then zips forward with both arms thrust out, and recovers."""
    t = f / n
    wind = ramp(t, 0.0, 0.35) * (1 - ramp(t, 0.35, 0.5))
    hit = ramp(t, 0.35, 0.52) * (1 - ramp(t, 0.6, 1.0))
    pose = {"body": rot(X, -18 * wind + 25 * hit), "head": rot(X, -6 * wind)}
    reach(pose, -30 * wind + 70 * hit, -10 * hit)
    tail(pose, 0, 0, 20 * hit - 10 * wind)
    return pose, Vector((0, 0.1 * wind - 0.28 * hit, 0.05 * wind - 0.05 * hit))


def clip_hurt(arm, f, n):
    """Jolted back, arms flung up."""
    t = f / n
    e = ramp(t, 0.0, 0.15) * (1 - ramp(t, 0.3, 1.0))
    shake = math.sin(2 * math.pi * 5 * t) * e
    pose = {"body": rot(X, -25 * e) @ rot(Y, 10 * shake), "head": rot(X, -15 * e)}
    arms(pose, 50 * e)
    return pose, Vector((0, 0.1 * e, -0.03 * e))


def clip_faint(arm, f, n):
    """Drifts down to the ground and tips over, arms and tail limp."""
    t = f / n
    fall = ramp(t, 0.2, 0.85)
    q = rot(Y, 70 * fall) @ rot(X, 15 * fall)
    pose = {"body": q, "head": rot(X, 20 * fall)}
    arms(pose, -30 * fall)
    curl(pose, 10 * fall, -15 * fall)
    return pose, about(arm, q, centre(arm), "body") + Vector((0, 0, -LIFT * fall)), fall


def clip_sit(arm, f, n):
    """Lands and sits upright, hands resting in front, tail curled up beside it, looking about."""
    t = f / n
    pose = {"body": rot(X, -5), "head": rot(Z, 12 * math.sin(2 * math.pi * t)) @ rot(X, 4 * math.sin(4 * math.pi * t))}
    reach(pose, 30, 25)
    curl(pose, 35, 20)
    return pose, Vector((0, 0, -LIFT)), 1.0


def clip_trick(arm, f, n):
    """A backflip in the air, arms out."""
    t = f / n
    e = env(t)
    q = rot(X, -360 * ramp(t, 0.15, 0.85))
    pose = {"body": q}
    arms(pose, 40 * e)
    tail(pose, 0, 0, -15 * e)
    return pose, about(arm, q, centre(arm), "body") + Vector((0, 0, 0.25 * math.sin(math.pi * t)))


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
    run(SRC, OUT, ARGS, fit, build, CLIPS, lift=LIFT, lift_bone="body", give_back=(("arm.", inboard),), views=framed_views, extra=EXTRA_CLIPS)
