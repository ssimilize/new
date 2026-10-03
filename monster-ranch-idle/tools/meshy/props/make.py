"""Makes decor props with Codex concepts and Meshy models, the way buildings/make.py makes buildings.
Decor pieces are static, so there is no rig: tools/blender/export_static.py takes each model into
the game (its footprint comes from Config/Decor.luau) and Visuals/PropMesh fits it over the piece's
parts (Config/PropMeshes.luau `decor`).

  python tools/meshy/props/make.py concept ID[,ID...]   draw the concepts with Codex (free, parallel)
  python tools/meshy/props/make.py model ID[,ID...]     model them from the cut-outs (15 cr each)
  python tools/meshy/props/make.py sheet ID[,ID...]     contact sheet of the concepts (art/compare/props.png)
  python tools/meshy/props/make.py ids ids.json         write { "<id>_p0": {mesh, texture} } into PropMeshes

`all` stands for every id in PROPS. Files: art/meshy/<id>-concept/ (image_0.png, cutout.png) and
art/meshy/<id>-model/ (model.glb). Then, per prop: `python tools/blender/export_static.py <id> 0 1`,
publish art/rigs/<id>/p0/mesh.json with publish_meshes.luau and art/export/<id>_p0.png from Studio.
"""

import json
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ART = ROOT / "art" / "meshy"
sys.path.insert(0, str(HERE.parent / "roster"))
from batch import matte, meshy  # noqa: E402
from codex_concept import CODEX_IMAGES, draw  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

PROPS_LUAU = ROOT / "src" / "shared" / "Config" / "PropMeshes.luau"
JOBS = 20

STYLE = (
    "Stylized 3D render of one decoration prop for a cozy monster-ranch game. Chunky, rounded, toy-like "
    "shapes, smooth matte vinyl-toy surfaces, bright saturated colours, a simple readable silhouette, every "
    "part attached to one solid piece (nothing loose or floating). The whole prop alone, three-quarter front "
    "view from slightly above, centred and filling about two thirds of the picture, plain flat medium grey "
    "background (#8C8C8C), soft even lighting, no text or letters anywhere, no characters or creatures, no "
    "ground, no ground shadow."
)

# Colours are Config/Decor.luau's (color, color2). A prop stands on a small base of its own only when
# the real thing would (a fountain's basin); loose bits sit touching the main body.
PROPS = {
    # The 1.x shop and event pieces (Decor LEGACY_ART), still built from blocks.
    "hay_bale": "A cartoon hay bale: one chunky rectangular block of golden straw (#E3C565) with soft rounded "
    "edges, two darker brown twine bands (#B08A3E) around it, a few straw tufts poking out.",
    "water_trough": "A cartoon farm water trough: a long low wooden trough of warm brown planks (#8A5A2B) on "
    "four short stubby legs, filled to the brim with bright clear blue water (#4FB6F2).",
    "flower_bed": "A cartoon raised flower bed: a low rectangular box of brown wooden planks (#8A5A2B) packed "
    "with round green leaves and bright pink flowers (#EF6FA8) with yellow centres.",
    "scratch_post": "A cartoon pet scratching post: a thick upright post wrapped in tan rope (#D8C8A8) on a "
    "square brown base (#A0703D), a round cushioned platform on top, a little ball toy hanging from it on a "
    "short string touching the post.",
    "lantern": "A cartoon glow lantern post: a slim dark iron lamppost (#4A4A4A) with a curled top, a "
    "chunky square lantern hanging from it glowing warm bright yellow (#FFD447) through its glass.",
    "fountain": "A cartoon tiny garden fountain: a round cream stone basin (#EDE7DD) filled with light blue "
    "water (#7FD0F5), a stone column in the middle with a small bowl on top, water arcing from it into the "
    "basin as solid stylised water.",
    "rainbow_arch": "A cartoon rainbow arch: a chunky semicircular arch made of soft rainbow stripes (red, "
    "orange, yellow, green, blue, purple) standing on two small fluffy white cloud feet, a few small golden "
    "stars (#FFD447) set into it.",
    "crystal_cluster": "A cartoon crystal cluster: a bunch of chunky glossy light-blue crystals (#A9DEFF) "
    "pointing up and outward from a small grey rock base, the tips glowing almost white (#E6F6FF).",
    "snow_globe": "A cartoon snow globe: a big clear glass dome (#E6F6FF) on a round dark brown wooden base "
    "(#6B4424), inside it a tiny snowy pine tree and snow drifts, white snowflakes inside the glass.",
    "gift_pile": "A cartoon pile of wrapped presents: three chunky gift boxes stacked together, red (#E5484D), "
    "green (#43B649) and white, each tied with a golden ribbon and a big bow.",
    "golden_statue": "A cartoon golden trophy statue: a shiny gold (#F4C43A) statue of a big five-pointed star "
    "on a short gold pillar, standing on a square cream marble plinth (#EDE7DD).",
    "paper_lantern": "A cartoon Chinese paper lantern stand: a short dark wooden post with a crossbar, one big "
    "round red paper lantern (#E5484D) hanging from it with golden caps top and bottom (#FFD447) and a golden "
    "tassel touching its bottom.",
    "moon_gate": "A cartoon East Asian moon gate: a big round circular gateway of warm orange-brown wood "
    "(#C98B2E) set in a short wall section, a small curved red tiled roof (#E5484D) on top.",
    "jack_o_lantern": "A cartoon jack-o'-lantern: a big round orange pumpkin (#F08A4B) with a friendly carved "
    "face (triangle eyes, wide smile) glowing warm yellow-orange from inside (#FFB347), a curly green stem.",
    "haunted_tree": "A cartoon spooky haunted tree: a short twisted dark purple trunk (#3A2D55) with bare "
    "curling branches, a cute friendly face in the bark, a few small purple leaves (#2A2230), cute not scary.",
    # Redrawn once: a white panel on the first one matted away into the grey.
    "beach_ball": "A cartoon beach ball: one round inflatable ball with wide panels in red (#FF6B6B), yellow, blue "
    "and a pale cream panel, meeting at a small cap on top. The ball is small in the picture with lots of empty "
    "grey space around it.",
    "tiki_torch": "A cartoon tiki torch: a tall bamboo pole (#D9A066) with woven bands, a bowl at the top "
    "holding a big stylised flame of solid orange and yellow (#FF9A3C), a small carved tiki face on the pole.",
    "tulip_patch": "A cartoon tulip patch: a low oval mound of grass (#6B8E3A) with a cluster of tall pink "
    "(#FF6FA5), red and yellow tulips standing up from it, broad green leaves.",
    "bloom_arch": "A cartoon flower arch: a white wooden garden arch completely covered in soft pink "
    "blossoms (#FFB3D1) and green leaves, standing on two flat feet.",
    "sandcastle": "A cartoon sandcastle: a chunky golden sand castle (#EFD08A) with three round towers with "
    "crenellations, a little arched door, a small red flag on the tallest tower, a few shells pressed in.",
    "beach_umbrella": "A cartoon beach umbrella: a big round parasol with red (#FF6B6B) and white stripes on a "
    "tall white pole stuck into a small round mound of sand.",
    "shell_pile": "A cartoon pile of seashells: a small heap of big chunky pink (#F7C6D9) and peach (#FFE3C2) "
    "seashells, a spiral conch on top, a scallop shell and a starfish at the front.",
    "tide_pool": "A cartoon tide pool: a low ring of rounded grey rocks (#8C8A84) around a shallow pool of "
    "bright teal water (#3FB6D9), a small orange starfish and green seaweed on the rocks. Much wider than tall.",
    # Glow-up Z pieces most ranches place (Decor add(...)), still built from blocks.
    "oak_tree": "A cartoon oak tree: a short thick brown trunk (#7A4A22) and a big round puffy cloud-shaped "
    "canopy of bright green leaves (#4E9A3E).",
    "pine_tree": "A cartoon pine tree: a short brown trunk (#6B4424) under three stacked chunky cone tiers of "
    "dark green needles (#2F7A4A), round tip.",
    "cherry_tree": "A cartoon cherry blossom tree: a short curved dark brown trunk (#6B4424) and a big round "
    "puffy canopy of soft pink blossoms (#FFB3D1).",
    "palm_tree": "A cartoon palm tree: a gently curved ringed tan trunk (#A0703D) with a crown of big "
    "drooping green palm fronds (#3FAF5A) and three coconuts tucked under them.",
    "round_bush": "A cartoon round bush: a big puffy round shrub of green leaves (#4E9A3E) dotted with small "
    "white flowers.",
    "park_bench": "A cartoon park bench: warm brown wooden slats (#A0703D) for the seat and back, curly black "
    "cast-iron ends and legs (#3A3A3A). Much wider than tall.",
    "street_lamp": "A cartoon old-fashioned street lamp: a tall dark slate iron post (#2F3A40) with a fluted "
    "base, a lantern head on top glowing soft warm yellow (#FFE7A3).",
    "swing_set": "A cartoon swing set: a red (#E5484D) A-frame of thick round poles with two wooden seats "
    "(#8A5A2B) hanging on chains. Wider than tall.",
    "slide": "A cartoon playground slide: a short ladder of brown wood (#A0703D) up to a small platform and a "
    "wide bright green (#43B649) curved slide down the other side. Longer than tall.",
    "barrel": "A cartoon wooden barrel: a chunky round brown barrel of planks (#8A5A2B) with two dark grey iron "
    "hoops (#4A4A4A), a lid on top.",
    "wood_crate": "A cartoon wooden crate: a chunky cube of light brown planks (#C08A4E) with darker brown "
    "corner boards and a cross brace (#7A4A22) on each side.",
    "mailbox": "A cartoon farm mailbox: a rounded blue mailbox (#4FB6F2) on a short wooden post, a little red "
    "flag (#E5484D) raised on its side.",
    "picnic_table": "A cartoon picnic table: a light brown wooden table (#B07A45) with a bench attached on each "
    "long side, darker crossed legs (#7A4A22), a red checked cloth folded on one corner.",
    # Wave 2 (after the 10-02 top-up): more of the pieces ranches place most.
    "wood_lamp": "A cartoon wooden lamp post: a chunky dark brown wooden post (#6B4424) with a crossbar, a "
    "lantern hanging from it glowing soft warm yellow (#FFD98A).",
    "garden_lantern": "A cartoon stone garden lantern: a short grey stone pagoda lantern (#A7A29A) with a little "
    "pointed cap, its window glowing warm yellow (#FFD447).",
    "torch_post": "A cartoon torch post: a short thick wooden post (#8A5A2B) wrapped with rope near the top, a "
    "metal bowl on top holding a big stylised flame of solid orange and yellow (#FF9A3C).",
    "crystal_lamp": "A cartoon crystal lamp post: a slim pale icy-blue glassy post (#BFE9FF) with a big faceted "
    "glowing cyan crystal (#8FE3FF) set on top in a little silver claw.",
    "lily_pond": "A cartoon lily pond: a wide shallow pond of bright blue water (#4FB6F2) ringed by rounded grey "
    "stones (#8C8A84), three round green lily pads with pink flowers floating on it. Much wider than tall.",
    "bird_bath": "A cartoon bird bath: a cream stone pedestal (#EDE7DD) holding a wide shallow round bowl of "
    "light blue water (#7FD0F5), a small carved leaf pattern on the bowl.",
    "potted_plant": "A cartoon potted plant: a round terracotta pot (#C9704F) with a rim, a bushy green leafy "
    "plant (#4E9A3E) growing up out of it.",
    "stone_bench": "A cartoon stone bench: a thick light grey stone slab seat (#B9B3A8) resting on two chunky "
    "darker grey stone legs (#8E8A83), rounded edges. Much wider than tall.",
    "hay_cart": "A cartoon hay cart: a small wooden farm cart (#A0703D) with two big spoked wheels and a pull "
    "handle, piled high with golden hay (#E3C565). Wider than tall.",
    "signpost": "A cartoon wooden signpost: a light brown wooden post (#C08A4E) with two blank pointed arrow "
    "boards (#A0703D) pointing different ways, no writing on them.",
    "rose_arch": "A cartoon rose arch: a cream painted wooden garden arch (#F4EBD9) wound with green vines and "
    "big red roses (#E5484D), standing on two flat feet.",
    "stone_arch": "A cartoon stone archway: a rounded arch of chunky grey cobblestones (#A7A29A) with a darker "
    "keystone (#6E6A64) at the top, standing on two square stone feet.",
    "climbing_tower": "A cartoon wooden climbing tower for pets: a square tower of light brown planks (#C08A4E) "
    "with two platforms, a little ladder up one side and a peaked roof of darker wood (#7A4A22).",
    "seesaw": "A cartoon seesaw: a long bright yellow plank (#FFD447) balanced on a blue pivot stand (#4FB6F2) in "
    "the middle, a round handle at each end. Much wider than tall.",
    "tire_swing": "A cartoon tire swing: a sturdy brown wooden frame (#8A5A2B) with a crossbar, a black rubber "
    "tire (#2E2E2E) hanging from it on a rope.",
    "bouncy_mushroom": "A cartoon bouncy mushroom: one big squishy mushroom with a round purple cap (#B56BFF) "
    "covered in white spots and a short thick white stalk.",
    "frosty_pine": "A cartoon snowy pine tree: a short brown trunk (#6B4424) under three stacked chunky cone "
    "tiers of pale frosted blue-white needles (#DDF3FF), snow on every tier.",
    "pumpkin_patch": "A cartoon pumpkin patch: a low mound of dark soil with three round orange pumpkins "
    "(#F08A4B) of different sizes and curly green vines and leaves (#3E7A2E).",
    "pirate_chest": "A cartoon pirate treasure chest: a chunky dark wooden chest (#7A4A24) with gold bands and a "
    "gold lock (#F4C43A), its lid slightly open with gold coins and a gem peeking out.",
}


def ids_from(arg: str) -> list[str]:
    ids = list(PROPS) if arg == "all" else arg.split(",")
    unknown = [i for i in ids if i not in PROPS]
    if unknown:
        raise SystemExit(f"unknown props: {unknown}")
    return ids


def pad(folder: Path) -> None:
    """Re-squares the concept from Codex's own picture by padding, not cropping: image_gen often answers
    wider or taller than square, and codex_concept's centre crop cut the ends off a bench or a torch.
    A 15% margin of the picture's own backdrop keeps the cut-out off the edges."""
    session = json.loads((folder / "status.json").read_text(encoding="utf-8"))["session"]
    src = sorted((CODEX_IMAGES / session).glob("*.png"), key=lambda p: p.stat().st_mtime)[-1]
    image = Image.open(src).convert("RGB")
    side = int(max(image.size) * 1.15)
    corners = [image.getpixel(p) for p in ((2, 2), (image.width - 3, 2), (2, image.height - 3), (image.width - 3, image.height - 3))]
    backdrop = tuple(sorted(c[k] for c in corners)[1] for k in range(3))
    square = Image.new("RGB", (side, side), backdrop)
    square.paste(image, ((side - image.width) // 2, (side - image.height) // 2))
    square.resize((1024, 1024), Image.LANCZOS).save(folder / "image_0.png")


def concept(ids: list[str]) -> None:
    def one(i: str) -> str:
        folder = ART / f"{i}-concept"
        if (folder / "image_0.png").exists():
            return f"{i}: already drawn"
        failed = draw(folder, PROPS[i] + " " + STYLE, None, "style")
        if failed:
            return f"{i}: FAILED {failed}"
        pad(folder)
        matte(Image.open(folder / "image_0.png")).save(folder / "cutout.png")
        return f"{i}: drawn"

    with ThreadPoolExecutor(JOBS) as pool:
        for line in pool.map(one, ids):
            print(line, flush=True)


def model(ids: list[str]) -> None:
    """Meshy queues at most 10 pending tasks a plan (429 NoMorePendingTasks, no charge), so this keeps
    them in flight: submit until refused, then wait out the oldest and download it, and go again."""
    settings = "@" + str(HERE / "model.json")
    waiting, flying = [i for i in ids if not (ART / f"{i}-model" / "model.glb").exists()], []
    while waiting or flying:
        while waiting:
            i = waiting[0]
            image = ART / f"{i}-concept" / "cutout.png"
            reply = meshy("create", "image-to-3d", f"{i}-model", "--image", f"image_url={image}", "--settings", settings)
            if reply.get("state") == "ERROR" and (reply.get("http_error") == 429 or "NoMorePendingTasks" in json.dumps(reply)):
                break
            print(i, reply.get("state") or reply.get("refused"), flush=True)
            waiting.pop(0)
            if reply.get("state") != "ERROR":
                flying.append(i)
        if flying:
            i = flying.pop(0)
            meshy("poll", f"{i}-model", "--wait")
            meshy("download", f"{i}-model")
            print(i, "model:", ART / f"{i}-model" / "model.glb", flush=True)
        elif waiting:
            time.sleep(30)  # every slot is someone else's task: wait for one to finish


def sheet(ids: list[str]) -> None:
    cell, cols = 256, 6
    rows = (len(ids) + cols - 1) // cols
    out = Image.new("RGB", (cols * cell, rows * (cell + 20)), "#202020")
    pen = ImageDraw.Draw(out)
    for n, i in enumerate(ids):
        src = ART / f"{i}-concept" / "image_0.png"
        x, y = n % cols * cell, n // cols * (cell + 20)
        if src.exists():
            out.paste(Image.open(src).convert("RGB").resize((cell, cell)), (x, y))
        pen.text((x + 4, y + cell + 3), i, fill="#FFFFFF")
    dest = ROOT / "art" / "compare" / "props.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.save(dest)
    print(dest)


def record(ids_path: str) -> None:
    """Writes each prop's { mesh, texture } into PropMeshes.luau's decor table (one piece each)."""
    got = json.loads(Path(ids_path).read_text(encoding="utf-8"))
    text = PROPS_LUAU.read_text(encoding="utf-8")
    head, body, tail = re.match(r"([\s\S]*?\n\tdecor = \{\n)([\s\S]*?)(\n\t\},[\s\S]*)", text).groups()
    rows = {re.match(r"\t\t(\w+) =", line).group(1): line for line in body.split("\n") if re.match(r"\t\t\w+ =", line)}
    for key, entry in got.items():
        prop = key.removesuffix("_p0")
        mesh = re.search(r"(\d+)$", entry["mesh"]).group(1)
        texture = re.search(r"(\d+)$", entry["texture"]).group(1)
        rows[prop] = f"\t\t{prop} = m({mesh}, {texture}),"
    PROPS_LUAU.write_text(head + "\n".join(rows.values()) + tail, encoding="utf-8", newline="\n")
    print(f"{len(got)} props recorded in {PROPS_LUAU.relative_to(ROOT)} ({len(rows)} decor entries)")


if __name__ == "__main__":
    command = sys.argv[1]
    if command == "ids":
        record(sys.argv[2])
    else:
        {"concept": concept, "model": model, "sheet": sheet}[command](ids_from(sys.argv[2]))
