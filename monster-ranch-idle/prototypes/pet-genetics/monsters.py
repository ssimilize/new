"""PROTOTYPE: the generate_mesh requests for animatable, Pet Simulator-style Monster Ranch monsters.

Each baby form (stage 1) of the game's lines gets a prompt built from its design words in
tools/meshy/roster/subjects.py and a part list per archetype, chosen so that every part that
should MOVE (ears, eyes, mouth, wings, antennae, tail, legs, arms, head decoration) comes out as
its own MeshPart for Animator.luau. generate_mesh takes at most 8 part names.

Why a `head decoration` part: without it the generator lumps whatever sits on the head (Petalpaw's
flower) into the `eyes` part, and a blink then squashes the flower too.

    python prototypes/pet-genetics/monsters.py            # JSON list of requests (lines 1-42)
    python prototypes/pet-genetics/monsters.py petalpaw   # just those forms
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROSTER = os.path.join(HERE, "..", "..", "tools", "meshy", "roster")
sys.path.insert(0, ROSTER)
import subjects  # noqa: E402

# Parts per archetype (max 8). Legs are split front/back where a walk needs alternating pairs.
PARTS = {
    "fox": ["body", "left ear", "right ear", "eyes", "head decoration", "tail", "front legs", "back legs"],
    "bunny": ["body", "left ear", "right ear", "eyes", "mouth", "tail", "feet", "arms"],
    "moth": ["body", "eyes", "mouth", "antennae", "left wings", "right wings", "legs", "head decoration"],
    "slug": ["body", "eyes", "mouth", "antennae", "tail", "back decoration"],
    "blob": ["body", "eyes", "mouth", "feet", "head decoration"],
    "sprite": ["body", "eyes", "mouth", "arms", "tail", "head decoration"],
    "bug": ["body", "eyes", "mouth", "antennae", "wings", "legs", "head decoration"],
    "golem": ["body", "head", "eyes", "mouth", "left arm", "right arm", "legs", "head decoration"],
}

# Suggested size (studs) per archetype: wide for wings, low for slugs.
SIZE = {
    "fox": (5, 5, 5.5),
    "bunny": (5, 6, 5),
    "moth": (7, 5, 5),
    "slug": (5, 3.5, 6.5),
    "blob": (5, 4.5, 5),
    "sprite": (5, 5, 5),
    "bug": (6, 4.5, 5.5),
    "golem": (5, 5.5, 4.5),
}

# Cindlet was made in the Meshy pilot, so it has no words in subjects.py.
EXTRA = {
    "cindlet": "Cindlet, a baby fire fox: warm orange fur, a cream chest, a small flame burning on the tip of "
    "its tail, a tiny flame tuft on top of its head.",
}

# Words that tripped the generator's moderation (a false positive), replaced wholesale.
REWORD = {
    "mudpuff": "Mudpuff, a baby frog blob: a soft round caramel body with a few round speckles and a little "
    "green lily pad on its head.",
    "jellow": "Jellow, a baby gummy blob: a round glossy yellow gummy-candy body, a small frilly cap on top of "
    "its head, a few tiny sparkle dots.",
}

STYLE = (
    "Big glossy black eyes with white highlights and a small happy mouth, clearly separate on the face. "
    "Pet Simulator toy style: a cute cube-shaped blocky rounded body, smooth toy surfaces, bright "
    "saturated colours, a simple readable silhouette."
)


def requests(only=None, last_line=42):
    roster = json.load(open(os.path.join(ROSTER, "roster.json"), encoding="utf-8"))
    out = []
    for order, line in enumerate(roster["lines"], 1):
        if order > last_line:
            break
        base = line["forms"][0]
        form = base["id"] if isinstance(base, dict) else base[0]["id"]
        if only and form not in only:
            continue
        arch = line["archetype"]
        words = REWORD.get(form) or subjects.SUBJECTS.get(form) or EXTRA.get(form)
        if not words:
            continue
        prompt = f"{words} It is {subjects.BODY[arch]}. {STYLE}"
        x, y, z = SIZE[arch]
        out.append(
            {
                "form": form,
                "line": order,
                "archetype": arch,
                "hover": arch in ("moth", "sprite"),
                "prompt": prompt,
                "parts": ", ".join(PARTS[arch]),
                "size": {"x": x, "y": y, "z": z},
            }
        )
    return out


if __name__ == "__main__":
    print(json.dumps(requests(set(sys.argv[1:]) or None), indent=1))
