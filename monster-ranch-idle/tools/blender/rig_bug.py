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
from riglib import about, box, ramp  # noqa: E402

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



# ─── The extra clips (riglib.EXTRA: sleep, eat, cheer, cheer2, attack, hurt, faint, sit, trick) ──


def env(t: float, rise: float = 0.12, fall: float = 0.85) -> float:
    """1 through a one-shot clip, easing in from 0 at its start and back to 0 at its end."""
    return ramp(t, 0.0, rise) * (1 - ramp(t, fall, 1.0))


def centre(arm) -> Vector:
    lo, hi = box(arm)
    return (lo + hi) / 2


def legs_pose(pose, body, splay=0.0, swing=0.0):
    """Every leg at world angles whatever the body does: splay spreads them out sideways (-: in),
    swing swings them back (degrees about X)."""
    for name in TRIPOD:
        out = rot(Y, -splay if name[0] == "L" else splay)
        pose[f"leg.{name}"] = body.inverted() @ out @ rot(X, swing)


def feelers(pose, lean, sway=0.0):
    pose["antenna.L"] = rot(X, lean) @ rot(Y, sway)
    pose["antenna.R"] = rot(X, lean) @ rot(Y, -sway)


def clip_sleep(arm, f, n):
    """Hunkers down, legs splayed flat, antennae drooping, abdomen breathing."""
    b = math.sin(2 * math.pi * f / n)
    body = rot(X, 2)
    pose = {"body": body, "abdomen": rot(X, -4 + 2 * b), "stinger.1": rot(X, -10)}
    legs_pose(pose, body, 55)
    feelers(pose, 45)
    buzz(pose, 0, 0, -3)
    return pose, Vector(), 1.0


def clip_eat(arm, f, n):
    """Nose down to the ground, munching, wings twitching."""
    t = f / n
    chew = 0.5 - 0.5 * math.cos(2 * math.pi * 3 * t)
    body = rot(X, 16 + 4 * chew)
    pose = {"body": body, "abdomen": rot(X, -16)}
    legs_pose(pose, body, 10)
    feelers(pose, 25 + 8 * chew)
    buzz(pose, 12 * math.pi * t, 4)
    return pose, Vector()


def clip_cheer(arm, f, n):
    """Rears up waving its front legs, wings buzzing."""
    t = f / n
    r = ramp(t, 0.0, 0.3) * (1 - ramp(t, 0.7, 1.0))
    body = rot(X, -22 * r)
    pose = {"body": body, "abdomen": rot(X, 10 * r)}
    legs_pose(pose, body)
    for side, p in (("L", 0.0), ("R", math.pi)):
        pose[f"leg.{side}.1"] = rot(X, -80 * r + 20 * math.sin(6 * math.pi * t + p) * r)
    buzz(pose, 16 * math.pi * t, 25 * r, 12 * r)
    feelers(pose, -15 * r)
    return pose, Vector((0, 0, 0.03 * r))


def clip_cheer2(arm, f, n):
    """A wiggle dance: body and abdomen swinging, legs tapping."""
    t = f / n
    e = env(t)
    s = math.sin(4 * math.pi * t) * e
    body = rot(Z, 18 * s) @ rot(Y, 6 * math.sin(8 * math.pi * t) * e)
    pose = {"body": body, "abdomen": rot(Z, -22 * s), "stinger.1": rot(Z, -15 * s)}
    legs_pose(pose, body)
    for name, group in TRIPOD.items():
        pose[f"leg.{name}"] = pose[f"leg.{name}"] @ rot(X, -20 * max(0.0, math.sin(8 * math.pi * t + (0 if group > 0 else math.pi))) * e)
    buzz(pose, 12 * math.pi * t, 15 * e)
    return pose, Vector((0, 0, 0.02 * abs(math.sin(4 * math.pi * t)) * e))


def clip_attack(arm, f, n):
    """Rears up with the abdomen raised, then lunges forward, stinger striking."""
    t = f / n
    wind = ramp(t, 0.0, 0.35) * (1 - ramp(t, 0.35, 0.5))
    hit = ramp(t, 0.35, 0.5) * (1 - ramp(t, 0.6, 1.0))
    body = rot(X, -18 * wind + 16 * hit)
    pose = {"body": body, "abdomen": rot(X, 30 * wind + 20 * hit), "stinger.1": rot(X, 30 * wind + 50 * hit)}
    legs_pose(pose, body, 0, 25 * hit)
    feelers(pose, -20 * (wind + hit))
    buzz(pose, 12 * math.pi * t, 20 * (wind + hit), 10 * (wind + hit))
    return pose, Vector((0, -0.2 * hit, 0.03 * hit))


def clip_hurt(arm, f, n):
    """Flinches back, legs pulled in, antennae swept back."""
    t = f / n
    e = ramp(t, 0.0, 0.15) * (1 - ramp(t, 0.3, 1.0))
    shake = math.sin(2 * math.pi * 5 * t) * e
    body = rot(X, -14 * e) @ rot(Z, 8 * shake)
    pose = {"body": body}
    legs_pose(pose, body, -15 * e)
    feelers(pose, -30 * e)
    return pose, Vector((0, 0.06 * e, 0.02 * e))


def clip_faint(arm, f, n):
    """Flips onto its back and lies there, legs curled up."""
    t = f / n
    flip = ramp(t, 0.2, 0.7)
    q = rot(Y, 180 * flip)
    pose = {"body": q}
    for name in TRIPOD:
        pose[f"leg.{name}"] = rot(Y, 35 * flip if name[0] == "L" else -35 * flip) @ rot(X, 40 * flip)
    feelers(pose, 40 * flip)
    return pose, about(arm, q, centre(arm), "body") + Vector((0, 0, 0.18 * math.sin(math.pi * flip))), ramp(t, 0.6, 0.85)


def clip_sit(arm, f, n):
    """Settles down, legs folded, antennae swaying, abdomen breathing."""
    t = f / n
    body = rot(X, -4)
    pose = {"body": body, "abdomen": rot(X, 2 * math.sin(2 * math.pi * t))}
    legs_pose(pose, body, 35)
    feelers(pose, 10 * math.sin(4 * math.pi * t), 8 * math.sin(2 * math.pi * t))
    return pose, Vector(), 1.0


def clip_trick(arm, f, n):
    """A buzzing backflip, legs tucked."""
    t = f / n
    e = env(t)
    q = rot(X, -360 * ramp(t, 0.15, 0.85))
    pose = {"body": q}
    legs_pose(pose, rot(X, 0), 0, 30 * e)
    buzz(pose, 20 * math.pi * t, 30 * e, 15 * e)
    return pose, about(arm, q, centre(arm), "body") + Vector((0, 0, 0.3 * math.sin(math.pi * t)))


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

CLIPS = {"idle": (clip_idle, 60), "walk": (clip_walk, 24), "hop": (clip_hop, 30)}

if __name__ == "__main__":  # add_clips.py imports the clip functions
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
        extra=EXTRA_CLIPS,
    )
