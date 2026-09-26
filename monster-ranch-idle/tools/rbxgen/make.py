"""Runs a batch of Roblox generations: concept images in, reviewed GLBs out. See README.md.

  python tools/rbxgen/make.py prep BATCH           concepts -> art/rbxgen/_serve/<key>.jpg; prints the URLs
  python tools/rbxgen/make.py ids BATCH UPLOADED   records upload_image's {url: "rbxassetid://N"} reply(s)
  python tools/rbxgen/make.py args BATCH           prints the _G.RbxGenArgs line for generate.luau
  python tools/rbxgen/make.py finish BATCH         assemble -> colormatch -> review sheet

BATCH is a JSON file (tools/rbxgen/batches/*.json):

  { "jobs": [
      { "key": "jellow", "concept": "art/meshy/jellow-concept/cutout.png",
        "prompt": "a cute baby jelly blob creature", "maxTriangles": 20000 },
      { "key": "p_barrel", "prompt": "a wooden water barrel with metal bands", "size": [3, 4, 3],
        "maxTriangles": 3000 } ] }

A job with a concept is image-to-3D (the prompt, if any, steers details on top); one without is
text-to-3D. `parts` (up to 8 names) splits a model into MeshParts with a texture each.
`colormatch` picks colormatch.py's mode for a job with a concept ("reinhard", the default; "hist";
"palette"), or false to keep Roblox's colours. Upload the
prep'd images with the Studio MCP's upload_image (three URLs a call; more timed out) while
`python -m http.server 38520 -d art/rbxgen/_serve` serves them, and run generate.luau from Studio
(Edit) with receiver.py listening. UPLOADED is upload_image's reply, pasted as JSON or a file of it.
"""

import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / "art" / "rbxgen"
SERVE = OUT / "_serve"
IMAGES = OUT / "images.json"  # key -> Image asset id of its uploaded concept
PORT = 38520
BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")
sys.path.insert(0, str(HERE))
from assemble import assemble, collect  # noqa: E402
from colormatch import match  # noqa: E402


def load(batch: str) -> list:
    return json.loads(Path(batch).read_text(encoding="utf-8"))["jobs"]


def flatten(src: Path) -> Image.Image:
    """The concept on flat grey, 1024 px. A cut-out's transparent background would otherwise read as
    black; the colour of the background made no difference to the result (2026-09-25 test)."""
    image = Image.open(src)
    if image.mode in ("RGBA", "LA", "P"):
        image = image.convert("RGBA")
        flat = Image.new("RGB", image.size, (140, 140, 140))
        flat.paste(image, mask=image.split()[3])
        image = flat
    return image.convert("RGB").resize((1024, 1024), Image.LANCZOS)


def prep(batch: str) -> None:
    SERVE.mkdir(parents=True, exist_ok=True)
    urls = []
    for job in load(batch):
        if job.get("concept"):
            flatten(ROOT / job["concept"]).save(SERVE / f"{job['key']}.jpg", quality=92)
            urls.append(f"http://127.0.0.1:{PORT}/{job['key']}.jpg")
    print(f"serve with: python -m http.server {PORT} -d {SERVE}")
    for i in range(0, len(urls), 3):
        print(json.dumps(urls[i : i + 3]))


def ids(batch: str, uploaded: str) -> None:
    text = Path(uploaded).read_text() if Path(uploaded).exists() else uploaded
    known = json.loads(IMAGES.read_text()) if IMAGES.exists() else {}
    for url, asset in json.loads(text).items():
        key = url.rsplit("/", 1)[-1].rsplit(".", 1)[0]
        known[key] = int(asset.rsplit("//", 1)[-1])
    IMAGES.write_text(json.dumps(known, indent=1))
    missing = [j["key"] for j in load(batch) if j.get("concept") and j["key"] not in known]
    print(f"{len(known)} image ids known" + (f"; still to upload: {', '.join(missing)}" if missing else ""))


def lua(value) -> str:
    if isinstance(value, dict):
        return "{ " + ", ".join(f"{k} = {lua(v)}" for k, v in value.items()) + " }"
    if isinstance(value, list):
        return "{ " + ", ".join(lua(v) for v in value) + " }"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value)
    return repr(value)


def args(batch: str, post: str = "http://127.0.0.1:38519/") -> None:
    known = json.loads(IMAGES.read_text()) if IMAGES.exists() else {}
    jobs = []
    for job in load(batch):
        entry = {"key": job["key"]}
        if job.get("concept"):
            if job["key"] not in known:
                raise SystemExit(f"{job['key']}: its concept is not uploaded yet (make.py prep, upload_image, make.py ids)")
            entry["image"] = known[job["key"]]
        for field in ("prompt", "size", "maxTriangles", "parts", "textures", "publish"):
            if field in job:
                entry[field] = job[field]
        jobs.append(entry)
    print(f"_G.RbxGenArgs = {lua({'post': post, 'jobs': jobs})}")


def finish(batch: str) -> None:
    jobs = load(batch)
    posted = collect(OUT / "_posted")
    missing = [j["key"] for j in jobs if j["key"] not in posted]
    if missing:
        print("not posted (still running, failed, or receiver down):", ", ".join(missing))
    done = [j for j in jobs if j["key"] in posted]
    for job in done:
        meta = assemble(job["key"], posted[job["key"]])
        line = f"{job['key']}: {sum(p['triangles'] for p in meta['parts'])} tris in {len(meta['parts'])} part(s)"
        mode = job.get("colormatch", "reinhard")
        if job.get("concept") and mode:
            match(job["key"], ROOT / job["concept"], mode, 1.0)
            line += f", colours matched to its concept ({mode})"
        print(line, flush=True)
    review([j["key"] for j in done], {j["key"]: j.get("concept") for j in done}, OUT / f"review_{Path(batch).stem}.png")


def review(keys: list, concepts: dict, sheet: Path, size: int = 280) -> None:
    """One row per key: its concept (if any), then the model from the front three-quarter, the side
    and the back three-quarter (tools/blender/look.py, which stands it 1 m tall)."""
    for key in keys:
        subprocess.run([str(BLENDER), "-b", "--factory-startup", "--python", str(ROOT / "tools" / "blender" / "look.py"), "--", str(OUT / key / "model.glb"), str(OUT / key / "look"), str(size)], capture_output=True, cwd=ROOT)
    views = ["front34", "side", "back34"]
    board = Image.new("RGB", (size * 4, size * len(keys)), (255, 255, 255))
    for row, key in enumerate(keys):
        if concepts.get(key):
            board.paste(flatten(ROOT / concepts[key]).resize((size, size)), (0, row * size))
        for col, view in enumerate(views, 1):
            path = OUT / key / f"look_{view}.png"
            if path.exists():
                board.paste(Image.open(path).convert("RGB").resize((size, size)), (col * size, row * size))
    board.save(sheet)
    print(f"review sheet: {sheet}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    command, batch = sys.argv[1], sys.argv[2]
    {"prep": lambda: prep(batch), "ids": lambda: ids(batch, sys.argv[3]), "args": lambda: args(batch), "finish": lambda: finish(batch)}[command]()
