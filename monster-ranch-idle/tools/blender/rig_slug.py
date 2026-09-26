"""Rigs and animates a slug monster (a long body lying on the ground, head at the front, eye stalks
or horns on top) in headless Blender. Same outputs as rig_quadruped.py; see riglib.py.

  blender -b --factory-startup --python tools/blender/rig_slug.py -- <model.glb> <out dir>

Fitted from the model's own shape: the body is sliced across its length, and the centre of each
slice gives the spine, so a body that rears up at the front (Cinderwyrm) gets a spine that rises
with it. The front quarter is the head; the stalks (or horns) are the highest point on each side
of the head. Bones: hips at the middle, chest and head forward, three tail bones back.
The crawl is a wave that runs from the tail to the head.
"""

import math
import sys
from pathlib import Path

import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from riglib import X, Y, Z, armature, below_base, finish, footprint_scale, framed_views, log, pulse, rot, run, set_game_scale, surface_samples  # noqa: E402
from riglib import about, box, ramp  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1 :]
SRC, OUT = Path(ARGS[0]).resolve(), Path(ARGS[1]).resolve()
SPINE = ["tail.3", "tail.2", "tail.1", "hips", "chest", "head"]  # back to front


def fit(mesh) -> dict:
    P = np.array([v.co[:] for v in mesh.data.vertices])
    H = float(np.ptp(P[:, 2]))
    S = surface_samples(mesh)
    front, back = float(P[:, 1].min()), float(P[:, 1].max())
    length = back - front

    # Head: the front quarter. Stalks: the highest point on each side of it.
    head_zone = P[P[:, 1] < front + 0.3 * length]
    crown_line = head_zone[np.abs(head_zone[:, 0]) < 0.04 * H]
    crown = float(crown_line[:, 2].max()) if len(crown_line) else float(head_zone[:, 2].max())
    stalks = {}
    for side, sel in (("L", head_zone[:, 0] > 0.05 * H), ("R", head_zone[:, 0] < -0.05 * H)):
        pts = head_zone[sel]
        if len(pts):
            tip = pts[pts[:, 2].argmax()]
            if tip[2] > crown + 0.04 * H:
                stalks[side] = tip

    # Spine: the centre of each cross-section, from just behind the snout to near the tail tip,
    # ignoring the stalks (they would pull the head's centre up).
    body = S[S[:, 2] < crown + 0.01 * H] if stalks else S
    stations = np.linspace(front + 0.1 * length, back - 0.04 * length, 7)
    joints = []
    for y in stations:
        ring = body[np.abs(body[:, 1] - y) < 0.04 * length]
        z = 0.5 * (ring[:, 2].min() + ring[:, 2].max()) if len(ring) else 0.3 * H
        joints.append([0.0, float(y), float(z)])
    joints = joints[::-1]  # tail tip first
    for side, tip in list(stalks.items()):
        base = np.array([tip[0] * 0.7, tip[1], crown - 0.02 * H])
        stalks[side] = (base, tip)

    set_game_scale(footprint_scale(P))
    marks = {
        "height": H,
        "front": front,
        "back": back,
        "crown": crown,
        "spine": joints,
        "stalks": {k: [b.tolist(), t.tolist()] for k, (b, t) in stalks.items()},
    }
    log(f"landmarks: length {length:.2f} x height {H:.2f}, spine z {joints[0][2]:.2f} (tail) .. {joints[-1][2]:.2f} (head), stalks {len(stalks)}")
    return marks


def build(marks: dict):
    H = marks["height"]
    arm, bone = armature()
    j = [Vector(p) for p in marks["spine"]]  # 7 joints, tail tip first
    mid = j[3]
    bone("root", (0, mid.y, 0), (0, mid.y - 0.25 * H, 0), deform=False)
    bone("hips", j[3], j[4], "root")
    bone("chest", j[4], j[5], "hips", connect=True)
    # The head reaches from the neck to the snout, level with its joint.
    snout = Vector((0, marks["front"], j[6].z))
    bone("head", j[5], snout, "chest", connect=True)
    bone("tail.1", j[3], j[2], "hips")
    bone("tail.2", j[2], j[1], "tail.1", connect=True)
    bone("tail.3", j[1], j[0], "tail.2", connect=True)
    for side, (base, tip) in marks["stalks"].items():
        bone(f"stalk.{side}", base, tip, "head")
    return finish(arm)


def stalks(pose: dict, lean: float, sway: float, ph: float):
    for side, p in (("L", 0.0), ("R", 1.1)):
        pose[f"stalk.{side}"] = rot(X, lean) @ rot(Y, sway * math.sin(ph + p) * (1 if side == "L" else -1))


def clip_idle(arm, f, n):
    ph = 2 * math.pi * f / n
    pose = {
        "chest": rot(X, -2 * math.sin(ph)),
        "head": rot(Z, 8 * math.sin(ph)) @ rot(X, 2 * math.sin(2 * ph)),
        "tail.1": rot(Z, 3 * math.sin(ph - 1)),
        "tail.2": rot(Z, 4 * math.sin(ph - 1.6)),
        "tail.3": rot(Z, 6 * math.sin(ph - 2.2)),
    }
    stalks(pose, 4 * math.sin(2 * ph), 10, 2 * ph)
    return pose, Vector((0, 0, 0.004 * (1 - math.cos(2 * ph)) / 2))


def clip_walk(arm, f, n):
    ph = 2 * math.pi * f / n
    pose = {}
    # A wave from the tail to the head: each segment lifts a little after the one behind it,
    # with a small side-to-side sway (more for a long wyrm than a stubby slug).
    for i, name in enumerate(SPINE):
        pose[name] = rot(X, 8 * math.sin(ph - 1.0 * i)) @ rot(Z, 5 * math.sin(ph - 0.8 * i))
    pose["head"] = rot(X, -5 * math.sin(ph - 5)) @ rot(Z, -4 * math.sin(ph - 4))
    stalks(pose, 10, 8, 2 * ph)
    return pose, Vector((0, 0, 0.006 * (1 - math.cos(2 * ph)) / 2))


def clip_hop(arm, f, n):
    t = f / n
    up = pulse(t, 0.0, 1.0)
    wiggle = math.sin(math.pi * 4 * t) * up
    pose = {
        # The front rears up and looks around; the tail stays down and wags.
        "hips": rot(X, -6 * up),
        "chest": rot(X, -22 * up),
        "head": rot(X, 18 * up) @ rot(Z, 10 * wiggle),
        "tail.1": rot(X, 8 * up),
        "tail.2": rot(Z, 10 * wiggle),
        "tail.3": rot(Z, 16 * wiggle),
    }
    stalks(pose, -15 * up, 20 * up, 4 * math.pi * t)
    return pose, Vector((0, 0, 0.04 * up))



# ─── The extra clips (riglib.EXTRA: sleep, eat, cheer, cheer2, attack, hurt, faint, sit, trick) ──


def env(t: float, rise: float = 0.12, fall: float = 0.85) -> float:
    """1 through a one-shot clip, easing in from 0 at its start and back to 0 at its end."""
    return ramp(t, 0.0, rise) * (1 - ramp(t, fall, 1.0))


def centre(arm) -> Vector:
    lo, hi = box(arm)
    return (lo + hi) / 2


def spine(pose, curl, spread=1.0):
    """Curls the tail segments to the model's right (curl degrees each)."""
    for i in (1, 2, 3):
        pose[f"tail.{i}"] = rot(Z, curl * spread**i)


def clip_sleep(arm, f, n):
    """Curls up, head resting on the ground, eye stalks drooping; slow breaths."""
    b = math.sin(2 * math.pi * f / n)
    pose = {"hips": rot(X, 1.5 * b), "chest": rot(Z, -18) @ rot(X, 8), "head": rot(Z, -22) @ rot(X, 22 + 2 * b)}
    spine(pose, 30)
    stalks(pose, 70, 0, 0)
    return pose, Vector(), 1.0


def clip_eat(arm, f, n):
    """Head down to the ground, chomping, tail swaying."""
    t = f / n
    chew = 0.5 - 0.5 * math.cos(2 * math.pi * 3 * t)
    ph = 2 * math.pi * t
    pose = {"chest": rot(X, 12), "head": rot(X, 22 + 8 * chew)}
    for i in (1, 2, 3):
        pose[f"tail.{i}"] = rot(Z, 5 * math.sin(ph - 0.8 * i))
    stalks(pose, 15 + 6 * chew, 6, 2 * ph)
    return pose, Vector()


def clip_cheer(arm, f, n):
    """Rears up tall and sways, stalks waving, tail wagging."""
    t = f / n
    r = ramp(t, 0.0, 0.3) * (1 - ramp(t, 0.7, 1.0))
    sway = math.sin(4 * math.pi * t) * r
    pose = {"hips": rot(X, -6 * r), "chest": rot(X, -30 * r), "head": rot(X, 26 * r) @ rot(Z, 12 * sway)}
    for i in (1, 2, 3):
        pose[f"tail.{i}"] = rot(Z, 14 * math.sin(6 * math.pi * t - 0.8 * i) * r)
    stalks(pose, -20 * r, 25 * r, 6 * math.pi * t)
    return pose, Vector((0, 0, 0.03 * r))


def clip_cheer2(arm, f, n):
    """A happy S-wiggle running down the body, bouncing."""
    t = f / n
    e = env(t)
    pose = {}
    for i, name in enumerate(SPINE):
        pose[name] = rot(Z, 16 * math.sin(4 * math.pi * t - 1.1 * i) * e)
    pose["head"] = rot(X, -8 * e) @ pose["head"]
    stalks(pose, -10 * e, 30 * e, 8 * math.pi * t)
    return pose, Vector((0, 0, 0.02 * abs(math.sin(4 * math.pi * t)) * e))


def clip_attack(arm, f, n):
    """Rears back, then strikes forward and down, and recovers."""
    t = f / n
    wind = ramp(t, 0.0, 0.35) * (1 - ramp(t, 0.35, 0.5))
    hit = ramp(t, 0.35, 0.5) * (1 - ramp(t, 0.6, 1.0))
    pose = {"hips": rot(X, -6 * wind), "chest": rot(X, -28 * wind + 16 * hit), "head": rot(X, 20 * wind + 14 * hit)}
    stalks(pose, -30 * wind - 20 * hit, 0, 0)
    return pose, Vector((0, 0.04 * wind - 0.18 * hit, 0))


def clip_hurt(arm, f, n):
    """Recoils with a shake, eye stalks pulled back."""
    t = f / n
    e = ramp(t, 0.0, 0.15) * (1 - ramp(t, 0.3, 1.0))
    shake = math.sin(2 * math.pi * 5 * t) * e
    pose = {"chest": rot(X, -14 * e), "head": rot(X, -10 * e) @ rot(Z, 14 * shake), "tail.2": rot(Z, 10 * shake)}
    stalks(pose, -45 * e, 0, 0)
    return pose, Vector((0, 0.06 * e, 0.01 * e))


def clip_faint(arm, f, n):
    """Flops over onto its side, stalks limp."""
    t = f / n
    fall = ramp(t, 0.25, 0.75)
    q = rot(Y, 75 * fall)
    pose = {"hips": q, "head": rot(X, 12 * fall)}
    spine(pose, -10 * fall)
    stalks(pose, 50 * fall, 0, 0)
    return pose, about(arm, q, centre(arm), "hips"), fall


def clip_sit(arm, f, n):
    """Coils up with the front raised, looking around."""
    t = f / n
    pose = {"chest": rot(X, -12), "head": rot(X, 10) @ rot(Z, 8 * math.sin(2 * math.pi * t))}
    spine(pose, 32)
    stalks(pose, 4 * math.sin(4 * math.pi * t), 8, 2 * math.pi * t)
    return pose, Vector()


def clip_trick(arm, f, n):
    """Spins a full turn on the spot, front reared, tail flung out."""
    t = f / n
    e = env(t)
    q = rot(Z, 360 * ramp(t, 0.1, 0.9))
    pose = {"hips": q, "chest": rot(X, -15 * e), "head": rot(X, 10 * e)}
    spine(pose, 14 * e)
    stalks(pose, -25 * e, 20 * e, 8 * math.pi * t)
    return pose, about(arm, q, centre(arm), "hips")


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

CLIPS = {"idle": (clip_idle, 60), "walk": (clip_walk, 30), "hop": (clip_hop, 24)}

if __name__ == "__main__":  # add_clips.py imports the clip functions
    run(SRC, OUT, ARGS, fit, build, CLIPS, give_back=(("stalk.", below_base),), views=framed_views, extra=EXTRA_CLIPS)
