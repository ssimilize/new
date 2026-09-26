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
    # The rest of World.Hub (2026-09-25), drawn in Tripo Studio. Proportions follow each placeholder's
    # size (x wide, y tall, z deep), since Dress.luau fits the model to its footprint.
    "trading": "A cozy cartoon trading post for a monster ranch: sky-blue walls (#4FB6F2) with white trim, "
    "a wide open market counter across the front under a blue and white striped awning, a big golden "
    "balance-scales shape on the roof as the shop sign, crates and a barrel stacked tight against the "
    "wall beside the counter, a teal tiled roof. Deeper than it is wide.",
    "gate": "A grand cartoon expedition gate for a monster ranch: a tall stone archway with big closed "
    "green (#43B649) wooden doors, a big compass shape at the top of the arch as its sign, ivy on the "
    "stones, a stout round tower on each side with a small flag shape on top. Taller than it is wide.",
    "hallOfFame": "A cartoon hall of fame for a monster ranch: a small purple (#8B6AD8) marble temple with "
    "white columns across the front, a golden trophy shape on top of the pediment as its sign, three wide "
    "steps up to a big double door, golden star decorations along the roof edge. Wider than it is tall.",
    "arena": "A cartoon monster stampede arena: a low round red (#E5484D) and cream stadium wall with a big "
    "arched entrance at the front, a red and white striped circus-tent roof over it, pennant flags along "
    "the rim, a big horn shape above the entrance as its sign. As deep as it is wide, much wider than tall.",
    "market": "A cozy cartoon market stall building: a warm orange (#F2A93B) wooden stall with a pitched "
    "roof, an orange and white striped awning over a long wooden counter full of fruit and vegetable "
    "baskets, hanging lanterns, crates stacked against the sides. A little wider than it is tall.",
    "starAltar": "A magical cartoon star altar for a monster ranch: a round violet (#6B5BD6) stone platform "
    "with three steps, a carved pedestal in the middle holding a big glowing golden star, small crystal "
    "pillars around the edge. As tall as it is wide.",
    "showStage": "A cartoon showtime stage for monster contests: a low pink (#FF7AC8) wooden stage with a "
    "curved back wall, pink and gold curtains tied back at the sides, a row of round spotlights along the "
    "top, a big gold star on the back wall as its sign. Three times as wide as it is tall.",
    "surfShack": "A cartoon beach surf shack: a small aqua-blue (#3FB6D9) wooden hut on short stilts with a "
    "thatched straw roof, colourful surfboards leaning against the front wall, a tiki torch at each front "
    "corner, a big wave shape on the roof as its sign. A little wider than it is tall.",
    "clubPlaza": "A cartoon clubhouse for a monster ranch: a teal (#2BA89A) two-storey cottage with a round "
    "tower on one side topped by a pennant flag, a big front door under a small porch roof, window boxes "
    "with flowers. About as tall as it is wide.",
    "championsArena": "A grand cartoon champions' colosseum: a round red (#C0392B) and gold stone colosseum "
    "with arched openings on two levels, a big golden laurel crown shape above the main gate as its sign, "
    "banners hanging between the arches. Twice as wide as it is tall.",
    "raidPortal": "A cartoon raid portal for a monster ranch: a tall violet (#6B5BD6) stone ring standing "
    "upright on a round stepped base, a swirling purple and cyan magic portal filling the ring, glowing "
    "runes carved on the stones, crystal spikes around the base. Taller than it is wide.",
    "racetrack": "A cartoon racetrack grandstand for monster races: a low orange (#FF8A3D) wooden grandstand "
    "with three rows of benches under a striped canopy roof, a checkered flag shape on top as its sign, a "
    "small starting gate beside it. Three times as wide as it is tall.",
    "hubPortal": "A cartoon travel portal tower for a trading hub: a sky-blue (#4FB6F2) round stone tower "
    "with a big arched doorway filled with a swirling blue portal, a pointed blue roof with a golden coin "
    "shape on top as its sign. Taller than it is wide.",
    "workshop": "A cozy cartoon crafting workshop: a pink (#FF7AC8) timber-framed cottage with a big "
    "chimney, a workbench with tools under a small awning at the front, a big gear-and-hammer shape on the "
    "roof as its sign, wooden crates of materials against the wall. Wider than it is tall.",
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
