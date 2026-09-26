"""Makes the roster's 3D models with Meshy: concept image -> hole check -> image-to-3d.

  python tools/meshy/roster/batch.py plan  FORM[,FORM...]    what would be made, and its cost
  python tools/meshy/roster/batch.py run   FORM[,FORM...] [--concepts] [--reserve N] [--model t2|71]
                                                         make them (waits; safe to re-run; --concepts
                                                         stops before the models; --reserve: credits
                                                         to keep, default 60; --model: Smart Topology
                                                         (15, default) or meshy-7.1 (30))
  python tools/meshy/roster/batch.py reroll FORM [--from LATER]   a new concept for a form that failed;
                                                         --from redraws a baby from its teen's concept
  python tools/meshy/roster/batch.py sheet FORM[,FORM...]    contact sheet of the concepts
  python tools/meshy/roster/batch.py accept FORM[,FORM...]   pass a failed check after looking at it

Every Meshy call goes through tools/meshy/meshy.py, which refuses to create a task name twice, so
`run` can be interrupted and re-run: it only creates what is missing and waits for the rest.

Per form, in art/meshy/:
  <form>-concept[-N]  stage 1: text-to-image; stages 2-3: image-to-image from the previous stage's
                      concept (subjects.py). The highest N is the form's concept.
  <form>-model        image-to-3d from the concept (model-t2.json: Smart Topology, 10,000 faces;
                      --model 71 takes model.json: meshy-7.1 remeshed to 6,000; both 4k + PBR).
The concept is checked before its model is paid for (check.json next to it): Meshy's background
removal can cut a pale body part out as background (Petalpaw's white chest, 2026-09-25), and
image-to-3d then fills the hole with an invented dark patch. A failed check stops that form and
every later stage built on it; `reroll` makes the next concept.

Model settings, from the 2026-09-25 A/B (tools/meshy/README.md has the reasoning): meshy-7.1 (meshy-6
came out washed out, meshy-t2 at half the price was faceted and left parts floating; batch 8 uses t2
anyway, at 10,000 faces, for the price, and sends what it cannot build to --model 71), 4k texture
(same price as 2k; the game bakes it to 1024), PBR maps (free: normal and roughness go to a
SurfaceAppearance), image_enhancement off (the concept already has the style).
"""

import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ART = ROOT / "art" / "meshy"
MESHY = [sys.executable, str(ROOT / "tools" / "meshy" / "meshy.py")]
sys.path.insert(0, str(HERE))
import subjects  # noqa: E402

# nano-banana-pro (9 cr) was the only one that drew the pilot's smooth toy style in the first A/B;
# nano-banana-2 (6 cr, newer) draws better references (the owner's call, 2026-09-26, from batch 8 on).
CONCEPT_MODEL = "nano-banana-2"
# Model settings by name (--model): Smart Topology (meshy-t2) at half the price is the default from
# batch 8 on (the owner's call, 2026-09-26), at 10,000 faces (its cap is 15,000) against the facets
# the 6,000-face A/B showed; meshy-7.1 stays for the forms t2 cannot build.
MODELS = {"t2": ("model-t2.json", 15), "71": ("model.json", 30)}
MODEL = "t2"
COST = {"concept": 6, "model": MODELS[MODEL][1]}
HOVERING = {"sprite", "moth"}  # body plans drawn in the air, over a shadow of their own (matte)
# Forms drawn with grey parts in the backdrop's own grey, which matte() cut out (tight_matte instead).
GREY_PARTS = {"yetikit", "snowbrute", "avalancheyeti"}
RESERVE = 60  # credits left untouched, for re-rolls
PENDING = 10  # Meshy refuses an 11th pending task on this plan (429 NoMorePendingTasks)
# Forms made by the pilot (tools/meshy/pilot): their concepts are the parents of later stages.
PILOT = {"cindlet", "kindlefox", "blazefang"}


def roster():
    data = json.loads((HERE / "roster.json").read_text(encoding="utf-8"))
    forms = {}
    for line in data["lines"]:
        by_stage = {}
        for form in line["forms"]:
            by_stage.setdefault(form["stage"], []).append(form["id"])
        for form in line["forms"]:
            parent = by_stage[form["stage"] - 1][0] if form["stage"] > 1 else None
            forms[form["id"]] = {"form": form, "line": line, "parent": parent}
    return data["elements"], forms


def meshy(*args) -> dict:
    result = subprocess.run([*MESHY, *args], capture_output=True, text=True, cwd=ROOT)
    if result.returncode != 0:
        raise SystemExit(f"meshy.py {' '.join(args[:2])} failed:\n{result.stdout}{result.stderr}")
    return json.loads(result.stdout) if result.stdout.strip().startswith("{") else {}


def concept_names(form: str) -> list[str]:
    """The form's concept tasks, oldest first: <form>-concept, then <form>-concept-2, -3, ..."""
    found = [(1, f"{form}-concept")] if (ART / f"{form}-concept").exists() else []
    for path in ART.glob(f"{form}-concept-*"):
        suffix = path.name[len(form) + len("-concept-") :]
        if suffix.isdigit():
            found.append((int(suffix), path.name))
    return [name for _, name in sorted(found)]


def concept_name(form: str) -> str:
    """The form's current concept task: the newest one, or the first to make."""
    names = concept_names(form)
    return names[-1] if names else f"{form}-concept"


def status(name: str) -> str | None:
    path = ART / name / "status.json"
    return json.loads(path.read_text(encoding="utf-8")).get("status") if path.exists() else None


def created(name: str) -> bool:
    """A task exists (or may exist) under this name. A definite 4xx refusal (no task, no charge) is
    not one: meshy.py lets that name be created again."""
    path = ART / name / "submission.json"
    if not path.exists():
        return False
    sub = json.loads(path.read_text(encoding="utf-8"))
    code = int((sub.get("response") or {}).get("http_error") or 0)
    return not (sub.get("state") == "ERROR" and 400 <= code < 500)


def settle_model(name: str) -> None:
    if status(name) not in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"):
        meshy("poll", name, "--wait")
    if status(name) == "SUCCEEDED" and not (ART / name / "model.glb").exists():
        meshy("download", name)
    print(f"[model] {name}: {status(name)}", flush=True)


def matte(image: Image.Image, hovering: bool = False) -> Image.Image:
    """Cuts the flat grey background out of a concept (subjects.STYLE asks for #8C8C8C).

    Meshy's remove_background cut pale bellies out as background three times in a row (Mossbun
    twice, Pearlfin), whatever the background colour. Here the background is whatever is connected
    to the image border and looks like the background colour (or its soft shadow), so an enclosed
    belly can never be removed; gaps enclosed by the body (between legs and tail) are removed only
    where they are the background colour itself."""
    rgb = np.asarray(image.convert("RGB")).astype(np.float32)
    h, w, _ = rgb.shape
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg = np.median(border, axis=0)
    dist = np.linalg.norm(rgb - bg, axis=2)
    value, sat = rgb.mean(axis=2), rgb.max(axis=2) - rgb.min(axis=2)
    # Soft shadows, and the lighter floor some images stand on, are greys near the background's.
    shadow = (sat < 12) & (value > bg.mean() - 40) & (value < bg.mean() + 35)
    # Near the background's colour but clearly coloured is the monster: the background's saturation
    # is 0-2, and the deep-shade rim of a lavender belly (138,124,153) is within 28 of the grey
    # (Hushling's line lost the bottom of every belly, 2026-09-25).
    near = (dist < 28) & (sat < 15)
    candidate = Image.fromarray(np.where(near | shadow, 255, 0).astype(np.uint8))
    padded = Image.new("L", (w + 2, h + 2), 255)
    padded.paste(candidate, (1, 1))
    ImageDraw.floodfill(padded, (0, 0), 128)  # background = candidate pixels reachable from the border
    outside = np.asarray(padded.crop((1, 1, w + 1, h + 1))) == 128
    # Enclosed gaps (between a curled tail and the body, say): patches of the background colour
    # itself, big and flat like the background. A grey eye reflection is small, and a grey part of
    # the monster is shaded, so neither is cut (Staticat's eyes and a grey ruff were, at first).
    from scipy import ndimage

    exact = (dist < 16) & ~outside
    labels, count = ndimage.label(exact)
    gaps = np.zeros_like(exact)
    for i in range(1, count + 1):
        patch = labels == i
        # Only big patches: smaller ones can't be told from the monster by colour, flatness or
        # surroundings. A rule for small pockets (Voltmedusa's background caught under tentacle
        # curls, cut by hand in batch 5) cut holes in the grey-brown bodies of the stone line
        # (Mochibun's head, Asterock's rock limbs) in batch 6; a pocket of trapped background is
        # rare enough to catch in the visual review of the concepts.
        if patch.sum() >= 0.002 * h * w and rgb[patch].std(axis=0).max() < 4:
            gaps |= patch
    background = outside | gaps
    if hovering:
        background |= floating_shadow(rgb, ~background, bg)
    # Drop the 1 px grey fringe, then soften the edge a little.
    alpha = Image.fromarray(np.where(background, 0, 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
    out = image.convert("RGB").convert("RGBA")
    out.putalpha(alpha)
    return out


def tight_matte(image: Image.Image) -> Image.Image:
    """For a monster with grey parts the backdrop's colour (the yeti line's face, horns, hands and
    feet): matte() takes those for background or shadow, so only what is within a hair of the
    backdrop's own colour, and reachable from the border, is cut. The concepts drawn for these forms
    so far had no soft shadow to leave behind."""
    rgb = np.asarray(image.convert("RGB")).astype(np.float32)
    h, w, _ = rgb.shape
    bg = np.median(np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]]), axis=0)
    candidate = Image.fromarray(np.where(np.linalg.norm(rgb - bg, axis=2) < 9, 255, 0).astype(np.uint8))
    padded = Image.new("L", (w + 2, h + 2), 255)
    padded.paste(candidate, (1, 1))
    ImageDraw.floodfill(padded, (0, 0), 128)
    background = np.asarray(padded.crop((1, 1, w + 1, h + 1))) == 128
    alpha = Image.fromarray(np.where(background, 0, 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
    out = image.convert("RGB").convert("RGBA")
    out.putalpha(alpha)
    return out


def floating_shadow(rgb: np.ndarray, solid: np.ndarray, bg: np.ndarray) -> np.ndarray:
    """The shadow a hovering monster casts on the "ground" below it, which the image model draws
    even when asked not to, tinted with the monster's colour (so it is not a background grey).
    image-to-3d would build it as a disc. In each column the lowest run of the figure is the shadow
    when background separates it from the body above and it is dull and darker than the background;
    where a tail tip dips into the shadow, the shadow-coloured pixels inside its outline (interpolated
    from the clean columns) go too, and so do small dull pieces lying loose."""
    from scipy import ndimage

    value, sat = rgb.mean(axis=2), rgb.max(axis=2) - rgb.min(axis=2)
    dull = (value < bg.mean() + 5) & (sat < 45)
    rows = np.nonzero(solid.any(axis=1))[0]
    if len(rows) == 0:
        return np.zeros_like(solid)
    band = rows[-1] - 0.12 * (rows[-1] - rows[0])  # the shadow lies in the bottom eighth
    spans = {}
    for x in np.nonzero(solid.any(axis=0))[0]:
        ys = np.nonzero(solid[:, x])[0]
        y1 = y0 = ys[-1]
        while y0 > 0 and solid[y0 - 1, x]:
            y0 -= 1
        if y0 > band and y0 > ys[0] and dull[y0 : y1 + 1, x].mean() > 0.8:
            spans[int(x)] = (int(y0), int(y1))
    shadow = np.zeros_like(solid)
    if len(spans) < 10:
        return shadow
    for x, (y0, y1) in spans.items():
        shadow[y0 : y1 + 1, x] = True
    colour = np.median(rgb[shadow], axis=0)
    xs = np.array(sorted(spans))
    tops = np.interp(np.arange(xs[0], xs[-1] + 1), xs, [spans[x][0] for x in xs])
    bottoms = np.interp(np.arange(xs[0], xs[-1] + 1), xs, [spans[x][1] for x in xs])
    for i, x in enumerate(range(xs[0], xs[-1] + 1)):
        if x in spans:
            continue
        y0, y1 = int(tops[i]), int(bottoms[i]) + 1
        shadow[y0:y1, x] = solid[y0:y1, x] & (np.linalg.norm(rgb[y0:y1, x] - colour, axis=1) < 30)
    # Loose bits: small separate pieces of the figure, dull and in the shadow's colour.
    labels, count = ndimage.label(solid & ~shadow)
    if count > 1:
        sizes = ndimage.sum(np.ones_like(solid), labels, range(1, count + 1))
        for i in range(1, count + 1):
            piece = labels == i
            if sizes[i - 1] < 0.02 * sizes.max() and np.linalg.norm(np.median(rgb[piece], axis=0) - colour) < 40:
                shadow |= piece
    return shadow


def cutout(name: str) -> Path:
    """The concept with a transparent background: Meshy's cut-out (first batch) or matte()'s."""
    source = ART / name / "image_0.png"
    image = Image.open(source)
    if image.mode == "RGBA" and np.asarray(image.getchannel("A"))[[0, -1]].max() == 0:
        return source  # Meshy already removed the background
    path = ART / name / "cutout.png"
    if not path.exists():
        form = name.split("-concept")[0]
        _, table = roster()
        if form in GREY_PARTS:
            tight_matte(image).save(path)
        else:
            matte(image, hovering=form in table and table[form]["line"]["archetype"] in HOVERING).save(path)
    return path


def check_concept(name: str) -> dict:
    """Holes in the cut-out: transparent or see-through pixels enclosed by the silhouette.

    Only meaningful for Meshy's cut-outs: matte() removes enclosed pixels only where they are the
    background colour, so its holes are real gaps; for those only the size is checked."""
    path = cutout(name)
    image = Image.open(path)
    if image.mode != "RGBA":
        return {"pass": False, "reason": f"no alpha ({image.mode}): background not removed"}
    alpha = np.asarray(image.getchannel("A"))
    h, w = alpha.shape
    solid = Image.fromarray(np.where(alpha > 127, 255, 0).astype(np.uint8))
    padded = Image.new("L", (w + 2, h + 2), 0)
    padded.paste(solid, (1, 1))
    ImageDraw.floodfill(padded, (0, 0), 128)  # background = reachable from the border
    region = padded.crop((1, 1, w + 1, h + 1))
    holes = int((np.asarray(region) == 0).sum())
    body = int((np.asarray(region) == 255).sum())
    # See-through pixels well inside the silhouette (away from its anti-aliased rim).
    inside = np.asarray(region.point(lambda v: 255 if v != 128 else 0).filter(ImageFilter.MinFilter(13))) > 0
    faint = int((inside & (alpha < 250)).sum())
    inside_count = max(1, int(inside.sum()))
    result = {
        "silhouette_px": body + holes,
        "hole_share": round(holes / max(1, body + holes), 5),
        "faint_share": round(faint / inside_count, 5),
        "coverage": round((body + holes) / (w * h), 3),
    }
    result["matte"] = "local" if path.name == "cutout.png" else "meshy"
    # A floor under the feet: a row near the silhouette's bottom that spans most of the image
    # (Staticat's line was drawn standing on a grey strip; image-to-3d would model it as a slab).
    rows = np.nonzero((alpha > 127).any(axis=1))[0]
    bottom = alpha[rows[-1] - max(1, (rows[-1] - rows[0]) // 8) : rows[-1] + 1] > 127 if len(rows) else alpha[:0]
    result["floor_width"] = round(float(bottom.sum(axis=1).max() / w) if len(bottom) else 0.0, 3)
    sized = 0.08 < result["coverage"] < 0.8
    clean = result["matte"] == "local" or (result["hole_share"] < 0.002 and result["faint_share"] < 0.01)
    floorless = result["floor_width"] < 0.85
    result["pass"] = sized and clean and floorless
    if not result["pass"]:
        result["reason"] = (
            "subject too small or too large" if not sized else "a floor under the feet" if not floorless else "holes or see-through patches inside the silhouette"
        )
    (ART / name / "check.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def plan(forms: list[str]):
    elements, table = roster()
    steps = []
    for form in forms:
        if form not in table:
            raise SystemExit(f"unknown form {form!r}")
        if form not in subjects.SUBJECTS and form not in PILOT:
            raise SystemExit(f"{form}: no subject in tools/meshy/roster/subjects.py")
        concept = concept_name(form)
        if form not in PILOT and not created(concept):
            steps.append(("concept", form, concept))
        if not created(f"{form}-model"):
            steps.append(("model", form, f"{form}-model"))
    cost = sum(COST[kind] for kind, _, _ in steps)
    return elements, table, steps, cost


def create_concept(form: str, elements, table, name: str, source: str | None = None) -> None:
    """source: draw this (stage 1) form from a LATER stage's concept instead of from text."""
    entry = table[form]
    # The grey background stays: matte() cuts it out (Meshy's remover took pale bellies with it).
    text = subjects.prompt(entry["form"], entry["line"], elements, from_later=source is not None)
    settings = {"ai_model": CONCEPT_MODEL, "prompt": text, "aspect_ratio": "1:1", "remove_background": False}
    # The drawing to start from goes up as the image itself, not as input_task_id: a task is only found
    # by the account that made it, and after the top-up of 2026-09-26 the key saw none of the earlier
    # tasks (every stage-3 concept answered 404 "Input task not found").
    if source is not None:
        image = ART / concept_name(source) / "image_0.png"
        reply = meshy("create", "image-to-image", name, "--images", f"reference_image_urls={image}", "--settings", json.dumps(settings))
    elif entry["form"]["stage"] == 1:
        reply = meshy("create", "text-to-image", name, "--settings", json.dumps(settings))
    else:
        image = ART / concept_name(entry["parent"]) / "image_0.png"
        reply = meshy("create", "image-to-image", name, "--images", f"reference_image_urls={image}", "--settings", json.dumps(settings))
    print(f"[concept] {name}: {reply.get('state')}", flush=True)


def settle_concept(form: str) -> bool | None:
    """Waits for the form's concept and checks it. True = ready, False = failed, None = not created."""
    name = concept_name(form)
    if form in PILOT:
        return True
    if not created(name):
        return None
    if status(name) != "SUCCEEDED":
        meshy("poll", name, "--wait")
    if status(name) != "SUCCEEDED":
        print(f"[concept] {name}: {status(name)}", flush=True)
        return False
    if not (ART / name / "image_0.png").exists():
        meshy("download", name)
    check_path = ART / name / "check.json"
    check = json.loads(check_path.read_text(encoding="utf-8")) if check_path.exists() else check_concept(name)
    print(f"[check] {name}: {'pass' if check['pass'] else 'FAIL ' + check.get('reason', '')} {check}", flush=True)
    return check["pass"]


def run(forms: list[str], concepts_only: bool = False, reserve: int = RESERVE) -> None:
    elements, table, steps, cost = plan(forms)
    if concepts_only:
        cost = sum(COST[kind] for kind, _, _ in steps if kind == "concept")
    balance = meshy("balance")["balance"]
    print(f"[run] {len(steps)} tasks to create, {cost} credits; balance {balance}, reserve {reserve}", flush=True)
    if balance - cost < reserve:
        raise SystemExit("not enough credits: shorten the list")
    by_stage = sorted(forms, key=lambda f: table[f]["form"]["stage"])
    ready = {}
    # Concepts stage by stage: a later stage is drawn from its parent's checked concept.
    for form in by_stage:
        parent = table[form]["parent"]
        if parent and parent not in PILOT:
            ok = ready.get(parent)
            if ok is None:
                ok = ready[parent] = settle_concept(parent)
            if not ok:
                print(f"[skip] {form}: parent {parent} has no checked concept", flush=True)
                ready[form] = False
                continue
        if form not in PILOT and not created(concept_name(form)):
            create_concept(form, elements, table, concept_name(form))
        ready[form] = None
    for form in by_stage:
        if ready.get(form) is None:
            ready[form] = settle_concept(form)
    if concepts_only:
        print("[run] concepts done; look at them (`sheet`) before the models", flush=True)
        return
    # Models for every form whose concept passed, at most PENDING in flight (the plan's queue limit).
    in_flight = [f"{form}-model" for form in forms if created(f"{form}-model") and status(f"{form}-model") not in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED")]
    for form in forms:
        name = f"{form}-model"
        if ready.get(form) and not created(name):
            while len(in_flight) >= PENDING:
                settle_model(in_flight.pop(0))
            image = cutout(concept_name(form))
            while True:
                reply = meshy("create", "image-to-3d", name, "--image", f"image_url={image}", "--settings", "@" + str(HERE / MODELS[MODEL][0]))
                # Tasks made outside this run (a concept re-roll) hold queue slots too: on a 429,
                # wait for one of ours to finish and try again.
                if reply.get("http_error") == 429 and in_flight:
                    print(f"[model] {name}: queue full, waiting for {in_flight[0]}", flush=True)
                    settle_model(in_flight.pop(0))
                    continue
                break
            print(f"[model] {name}: {reply.get('state')}", flush=True)
            if reply.get("state") != "SUBMITTED":
                raise SystemExit(f"{name}: {reply}")
            in_flight.append(name)
    for form in forms:
        if created(f"{form}-model"):
            settle_model(f"{form}-model")
    print(f"[run] done; balance {meshy('balance')['balance']}", flush=True)


def sheet(forms: list[str]) -> None:
    tiles = []
    for form in forms:
        name = concept_name(form)
        if not (ART / name / "image_0.png").exists():
            continue
        image = Image.open(cutout(name)).convert("RGBA")
        backdrop = Image.new("RGBA", image.size, (255, 0, 255, 255))  # magenta shows every hole
        backdrop.alpha_composite(image)
        tile = backdrop.convert("RGB").resize((360, 360))
        ImageDraw.Draw(tile).text((6, 4), name, fill="white")
        tiles.append(tile)
    columns = 6
    out = Image.new("RGB", (360 * columns, 360 * ((len(tiles) + columns - 1) // columns)), "black")
    for i, tile in enumerate(tiles):
        out.paste(tile, (360 * (i % columns), 360 * (i // columns)))
    dest = ROOT / "art" / "compare" / "roster-concepts.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.save(dest)
    print(dest)


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    command, forms = sys.argv[1], [f for f in sys.argv[2].split(",") if f]
    global MODEL
    if "--model" in sys.argv:
        MODEL = sys.argv[sys.argv.index("--model") + 1]
        if MODEL not in MODELS:
            raise SystemExit(f"--model {MODEL}: one of {', '.join(MODELS)}")
        COST["model"] = MODELS[MODEL][1]
    if command == "plan":
        _, table, steps, cost = plan(forms)
        for kind, form, name in steps:
            parent = table[form]["parent"]
            print(f"{kind:8} {name:24} {'<- ' + concept_name(parent) if kind == 'concept' and parent else ''}")
        print(f"{len(steps)} tasks, {cost} credits; balance {meshy('balance')['balance']}")
    elif command == "run":
        extra = sys.argv[3:]
        reserve = int(extra[extra.index("--reserve") + 1]) if "--reserve" in extra else RESERVE
        run(forms, concepts_only="--concepts" in extra, reserve=reserve)
    elif command == "reroll":
        (form,) = forms
        elements, table = roster()
        names = concept_names(form)
        if names and status(names[-1]) not in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"):
            raise SystemExit(f"{names[-1]} is still running")
        name = f"{form}-concept-{len(names) + 1}" if names else f"{form}-concept"
        extra = sys.argv[3:]
        source = extra[extra.index("--from") + 1] if "--from" in extra else None
        if source is not None and (source not in table or status(concept_name(source)) != "SUCCEEDED"):
            raise SystemExit(f"--from {source}: no finished concept to draw from")
        create_concept(form, elements, table, name, source)
        print(f"made {name}; `run {form}` checks it and makes the model")
    elif command == "sheet":
        sheet(forms)
    elif command == "check":
        for form in forms:
            print(form, check_concept(concept_name(form)))
    elif command == "accept":
        # A failed check that a person looked at and judged harmless (say, a faint eye highlight).
        for form in forms:
            path = ART / concept_name(form) / "check.json"
            check = json.loads(path.read_text(encoding="utf-8"))
            check.update({"pass": True, "accepted": "by review, over: " + check.pop("reason", "")})
            path.write_text(json.dumps(check, indent=2), encoding="utf-8")
            print(form, check)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
