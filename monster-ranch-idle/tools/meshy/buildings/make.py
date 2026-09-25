"""Makes hub buildings with Meshy, the way roster/batch.py makes monsters: concept -> local cut-out
-> image-to-3d (same model settings). Buildings are static, so there is no rig: see
tools/blender/export_static.py for the step into the game.

  python tools/meshy/buildings/make.py concept ID[,ID...]   draw the concepts (nano-banana-pro, 9 cr each)
  python tools/meshy/buildings/make.py model ID[,ID...]     model them from the cut-outs (30 cr each)

Files: art/meshy/<id>-concept/ (image_0.png, cutout.png) and art/meshy/<id>-model/ (model.glb).
The id is the building's id in Config/World.luau (World.Hub), or "barn" for the plot barn, which
the 2026-09-25 pilot made (tools/meshy/pilot: nano-banana on white with Meshy's own cut-out).
"""

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ART = ROOT / "art" / "meshy"
sys.path.insert(0, str(HERE.parent / "roster"))
from batch import matte, meshy  # noqa: E402
from PIL import Image  # noqa: E402

# roster/subjects.py's STYLE with the creature words taken out.
STYLE = (
    "Stylized 3D render for a cozy monster-collecting game. Chunky, rounded, toy-like shapes, "
    "smooth matte surfaces, bright saturated colours, a simple readable silhouette, every part "
    "attached to the building. The whole building alone, three-quarter front view, centred, plain "
    "flat medium grey background (#8C8C8C), soft even lighting, no text or letters anywhere, no "
    "ground, no ground shadow."
)

# Colours are World.Hub's. Props stand against the walls, not loose in front (image-to-3d would
# model a loose prop as a floating piece), and a sign is a shape, not lettering.
BUILDINGS = {
    "eggShop": "A cozy cartoon egg shop for a monster ranch: bright pink walls (#EF6FA8) with cream "
    "trim, a rounded roof shaped like the top of a big egg in cream with pink spots, a wide shop "
    "front with a big arched door in the middle and a display window on each side showing "
    "colourful spotted eggs on shelves, a pink and white striped awning over the door, a giant "
    "spotted egg sitting on top of the roof as the shop sign. Wider than it is tall.",
    "feedStore": "A cozy cartoon farm feed store for a monster ranch: warm orange walls (#F2A93B) "
    "with white trim and wooden corner posts, a red-brown gabled roof, a wide shop front with a "
    "big double door in the middle under a green and white striped awning, sacks of grain and a "
    "crate of carrots and berries stacked tight against the wall beside the door, a big carrot "
    "shape mounted on the roof ridge as the shop sign. Wider than it is tall.",
}


def concept(ids: list[str]) -> None:
    for i in ids:
        settings = {"ai_model": "nano-banana-pro", "prompt": BUILDINGS[i] + " " + STYLE, "aspect_ratio": "1:1", "remove_background": False}
        print(i, meshy("create", "text-to-image", f"{i}-concept", "--settings", json.dumps(settings)).get("state"), flush=True)
    for i in ids:
        meshy("poll", f"{i}-concept", "--wait")
        meshy("download", f"{i}-concept")
        src = ART / f"{i}-concept" / "image_0.png"
        matte(Image.open(src)).save(src.with_name("cutout.png"))
        print(i, "cut out:", src.with_name("cutout.png"), flush=True)


def model(ids: list[str]) -> None:
    for i in ids:
        image = ART / f"{i}-concept" / "cutout.png"
        reply = meshy("create", "image-to-3d", f"{i}-model", "--image", f"image_url={image}", "--settings", "@" + str(HERE.parent / "roster" / "model.json"))
        print(i, reply.get("state"), flush=True)
    for i in ids:
        meshy("poll", f"{i}-model", "--wait")
        meshy("download", f"{i}-model")
        print(i, "model:", ART / f"{i}-model" / "model.glb", flush=True)


if __name__ == "__main__":
    {"concept": concept, "model": model}[sys.argv[1]](sys.argv[2].split(","))
