"""Particle-sprite bake-off entrant: OpenAI GPT Image 2 via the Images API.

Two approaches, both writing into art/vfx/bakeoff/gpt/:
  sheet   ONE 1536x1024 image, six sprites in a 3x2 grid on pure black, cut into cells,
          alpha derived from brightness and un-premultiplied.
  single  one 1024x1024 image per sprite, background="transparent" png (falls back to a
          black background + brightness keying if the model refuses transparency).

ROUTE CHANGE 2026-09-25: the API account had no credits (HTTP 429), so images are now made by the
Codex CLI's built-in image tool (ChatGPT subscription) and dropped into gpt/raw/ under the same names
(sheet_<tag>.png, single_<tag>_<sprite>.png); the gen-* commands below are the API route and refuse
to run unless --allow-api is given. cut-*/pick/result work on whatever is in raw/.

Usage (from the repo root):
  python tools/vfx/gpt_sprites.py gen-sheet  --tag r1 [--quality medium]
  python tools/vfx/gpt_sprites.py gen-single --tag r1 [--quality medium] [--only flame,leaf]
  python tools/vfx/gpt_sprites.py cut-sheet  --raw art/vfx/bakeoff/gpt/raw/sheet_r1.png
  python tools/vfx/gpt_sprites.py cut-single --tag r1 [--only ...]
  python tools/vfx/gpt_sprites.py pick --approach single|sheet [--from sheet:leaf,...]
  python tools/vfx/gpt_sprites.py result --wall-minutes N --notes-file notes.txt

The API key is read from os.environ["OPENAI_API_KEY"] only and is never printed or logged.
Every raw API image is kept under gpt/raw/, every call (usage, seconds, cost) in gpt/raw/calls.jsonl.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
from pathlib import Path

import numpy as np
import requests
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art" / "vfx" / "bakeoff" / "gpt"
RAW = OUT / "raw"
CALLS = RAW / "calls.jsonl"

MODEL = "gpt-image-2"
URL = "https://api.openai.com/v1/images/generations"

# USD per 1M tokens, gpt-image-2 STANDARD tier. The pricing page (fetched 2026-09-25) lists the
# Batch tier as image-in 4.00 / text-in 2.50 / image-out 15.00; Batch is half of Standard, so
# Standard = 8 / 5 / 30. The guide's calculator quotes medium 1024x1024 at $0.053 and medium
# 1536x1024 at $0.041; we log both the token-based and the calculator figure and budget on the max.
PRICE = {"text_in": 5.00, "image_in": 8.00, "image_out": 30.00}
CALC_USD = {("low", "1024x1024"): 0.006, ("low", "1536x1024"): 0.005,
            ("medium", "1024x1024"): 0.053, ("medium", "1536x1024"): 0.041,
            ("high", "1024x1024"): 0.211, ("high", "1536x1024"): 0.165}
BUDGET_USD = 3.00

SPRITES = ["flame", "droplet", "leaf", "bolt", "star", "wisp"]
# sprites whose body is an opaque solid shape (keying from brightness would make dark shading
# see-through), vs glow sprites whose alpha IS their brightness
SOLID = {"droplet", "leaf"}

STYLE = ("polished stylized mobile-game VFX particle texture, in the style of Genshin Impact and "
         "Pet Simulator effects, soft glow, clean readable silhouette, bright saturated colour, "
         "flat front view, single isolated object, no text, no letters, no border, no frame, "
         "no drop shadow, no ground, no scenery")

DESC = {
    "flame": "a single stylized flame tongue, soft glowing white-yellow core fading to warm orange "
             "at the edges, one smooth curved tapering tip, soft glowing edges",
    "droplet": "a single cartoon water droplet, rounded bottom and pointed top, bright clear blue, "
               "glossy white specular highlight on the upper left, smooth clean outline",
    "leaf": "one small fresh green leaf with a lighter central midrib and a short stem, simple "
            "clean silhouette, gentle soft shading",
    "bolt": "a single jagged lightning bolt zigzag, bright white-hot core with yellow edges, "
            "slight soft yellow glow around it",
    "star": "a four-point twinkle sparkle star, long thin slightly curved points, white-hot "
            "centre, pale gold tint, soft round glow halo around the centre",
    "wisp": "a soft curling puff of violet magic smoke, a wispy swirl with no hard edges, "
            "gently glowing, fading softly at every edge",
}

# prompt revisions: round tags map to extra guidance appended per sprite
EXTRA: dict[str, dict[str, str]] = {"r1": {}, "r2": {}}


def _key() -> str:
    k = os.environ.get("OPENAI_API_KEY")
    if not k:
        sys.exit("OPENAI_API_KEY not set")
    return k


def spent_usd() -> float:
    if not CALLS.exists():
        return 0.0
    tot = 0.0
    for line in CALLS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            tot += json.loads(line).get("usd_budgeted", 0.0)
    return tot


def cost_of(usage: dict, quality: str, size: str) -> dict:
    itd = usage.get("input_tokens_details") or {}
    text_in = itd.get("text_tokens", usage.get("input_tokens", 0))
    image_in = itd.get("image_tokens", 0)
    out = usage.get("output_tokens", 0)
    tok = (text_in * PRICE["text_in"] + image_in * PRICE["image_in"] + out * PRICE["image_out"]) / 1e6
    calc = CALC_USD.get((quality, size))
    return {"usd_tokens": round(tok, 5), "usd_calculator": calc,
            "usd_budgeted": round(max(tok, calc or 0.0), 5)}


def generate(name: str, prompt: str, size: str, quality: str, background: str) -> Path | None:
    """One Images API call. Saves raw png + a jsonl log row. Returns the raw path or None."""
    RAW.mkdir(parents=True, exist_ok=True)
    worst = CALC_USD.get((quality, size), 0.25) * 1.5
    if spent_usd() + worst > BUDGET_USD:
        sys.exit(f"budget guard: spent {spent_usd():.3f} + ~{worst:.3f} would pass ${BUDGET_USD}")
    body = {"model": MODEL, "prompt": prompt, "size": size, "quality": quality, "n": 1,
            "output_format": "png"}
    if background:
        body["background"] = background
    t0 = time.time()
    r = requests.post(URL, headers={"Authorization": "Bearer " + _key(),
                                    "Content-Type": "application/json"},
                      json=body, timeout=600)
    secs = round(time.time() - t0, 2)
    row = {"name": name, "model": MODEL, "size": size, "quality": quality,
           "background": background, "prompt": prompt, "seconds": secs, "status": r.status_code,
           "time": time.strftime("%Y-%m-%dT%H:%M:%S")}
    if r.status_code != 200:
        try:
            err = r.json().get("error", {})
            row["error"] = {"message": err.get("message"), "code": err.get("code"),
                            "param": err.get("param")}
        except ValueError:
            row["error"] = {"message": r.text[:300]}
        row["usd_budgeted"] = 0.0
        with CALLS.open("a", encoding="utf-8") as f:
            f.write(json.dumps(row) + "\n")
        print(f"[{name}] HTTP {r.status_code}: {row['error'].get('message')}")
        if r.status_code in (401, 429):
            sys.exit("API refused the account (auth/quota); nothing generated")
        return None
    j = r.json()
    usage = j.get("usage") or {}
    row["usage"] = usage
    row.update(cost_of(usage, quality, size))
    row["response_background"] = j.get("background")
    path = RAW / f"{name}.png"
    path.write_bytes(base64.b64decode(j["data"][0]["b64_json"]))
    row["raw"] = str(path.relative_to(ROOT)).replace("\\", "/")
    rp = j["data"][0].get("revised_prompt")
    if rp:
        row["revised_prompt"] = rp
    with CALLS.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row) + "\n")
    print(f"[{name}] {secs}s usage={usage} ${row['usd_tokens']} (calc {row['usd_calculator']})"
          f" total spent ${spent_usd():.3f}")
    return path


# ---------------------------------------------------------------------------------- image ops

def key_black(rgb: np.ndarray, solid: bool, lo: float = 0.035, hi: float = 0.9,
              solid_thr: float = 0.12) -> np.ndarray:
    """rgb float 0..1 on black -> straight-alpha RGBA float. alpha = brightness (max channel),
    remapped lo..hi; colour un-premultiplied. solid=True also fills the silhouette interior
    (flood-filled from the border on a thresholded mask) so dark shading stays opaque."""
    v = rgb.max(axis=2)
    a = np.clip((v - lo) / (hi - lo), 0.0, 1.0)
    if solid:
        thr = (v > solid_thr).astype(np.uint8) * 255
        m = Image.fromarray(thr, "L")
        m = m.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
        # flood the background from a border pixel that is dark
        filled = m.copy()
        ImageDraw.floodfill(filled, (0, 0), 128)
        inside = Image.fromarray(((np.asarray(filled) != 128) * 255).astype(np.uint8))
        core = np.asarray(inside.filter(ImageFilter.MinFilter(7)), np.float32) / 255
        soft = np.asarray(inside.filter(ImageFilter.MinFilter(3)).filter(
            ImageFilter.GaussianBlur(1.0)), np.float32) / 255
        a_b = a
        a = np.maximum(a, soft)
        # core keeps its drawn (shaded) colour; the edge band is un-premultiplied by the
        # brightness alpha so the anti-aliased dark rim does not survive as a fringe
        div = np.where(core > 0.5, 1.0, np.maximum(a_b, 1e-4))
    else:
        div = np.maximum(a, 1e-4)
    col = np.clip(rgb / div[..., None], 0, 1)
    col = np.where(a[..., None] > 1e-3, col, 0.0)
    return np.dstack([col, a])


def to_uint8(rgba: np.ndarray) -> Image.Image:
    return Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def frame(img: Image.Image, size: int = 256, fill: float = 0.80, athr: int = 6) -> Image.Image:
    """Trim to alpha bbox, centre in a square, scale so the long side = fill*size."""
    a = np.asarray(img.getchannel("A"))
    ys, xs = np.nonzero(a > athr)
    if len(xs) == 0:
        return Image.new("RGBA", (size, size), (0, 0, 0, 0))
    crop = img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    w, h = crop.size
    s = fill * size / max(w, h)
    nw, nh = max(1, round(w * s)), max(1, round(h * s))
    small = crop.convert("RGBa").resize((nw, nh), Image.LANCZOS).convert("RGBA")
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(small, ((size - nw) // 2, (size - nh) // 2))
    # zero colour under zero alpha (clean for any later filtering)
    arr = np.asarray(out).copy()
    arr[arr[..., 3] == 0, :3] = 0
    return Image.fromarray(arr, "RGBA")


def to_grey(img: Image.Image) -> Image.Image:
    """Tintable version: luminance only, normalised so the brightest body is white, gently lifted
    so the sprite reads light-grey/white and tints cleanly. Alpha unchanged."""
    arr = np.asarray(img).astype(np.float32) / 255
    rgb, a = arr[..., :3], arr[..., 3]
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    body = lum[a > 0.5]
    peak = np.percentile(body, 99) if body.size else 1.0
    ln = np.clip(lum / max(peak, 1e-3), 0, 1)
    g = 0.30 + 0.70 * ln ** 0.8
    g = np.where(a > 0, g, 0)
    return to_uint8(np.dstack([g, g, g, a]))


def contact(folder: Path, names: list[str], out: Path) -> None:
    cell, pad = 128, 8
    rows = [("grey", "#202028"), ("color", "#202028"), ("grey", "#E8E8E8"), ("color", "#E8E8E8")]
    W = pad + len(names) * (cell + pad)
    H = pad + len(rows) * (cell + pad)
    sheet = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    for ri, (kind, bg) in enumerate(rows):
        y = pad + ri * (cell + pad)
        strip = Image.new("RGBA", (W, cell + pad), bg)
        sheet.paste(strip, (0, y - pad // 2))
        for ci, n in enumerate(names):
            p = folder / (f"{n}.png" if kind == "grey" else f"{n}_color.png")
            if not p.exists():
                continue
            sp = Image.open(p).convert("RGBA").resize((cell, cell), Image.LANCZOS)
            sheet.alpha_composite(sp, (pad + ci * (cell + pad), y))
    sheet.convert("RGB").save(out)


def write_pair(color: Image.Image, dest: Path, name: str) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    framed = frame(color)
    framed.save(dest / f"{name}_color.png")
    to_grey(framed).save(dest / f"{name}.png")


# ---------------------------------------------------------------------------------- commands

def sheet_prompt(tag: str) -> str:
    order = ", ".join(f"({i + 1}) {DESC[n]}" for i, n in enumerate(SPRITES))
    extra = EXTRA.get(tag, {}).get("sheet", "")
    return ("A game VFX sprite sheet: exactly six separate particle sprites arranged in a strict "
            "grid of 3 columns and 2 rows on a pure solid black (#000000) background. Each sprite "
            "sits centred in its own equal-size cell, filling about 70% of the cell, with plain "
            "black space between cells; nothing touches or crosses a cell boundary; no grid "
            "lines. Reading order left-to-right, top row then bottom row: " + order + ". "
            "Every sprite: " + STYLE + ". " + extra).strip()


def single_prompt(name: str, tag: str, background: str) -> str:
    bg = ("isolated on a fully transparent background" if background == "transparent"
          else "isolated on a pure solid black (#000000) background")
    extra = EXTRA.get(tag, {}).get(name, "")
    return (f"A single game particle sprite: {DESC[name]}. Centred, filling about 80% of the "
            f"square frame, {bg}. {STYLE}. {extra}").strip()


def _api_guard(a):
    if not a.allow_api:
        sys.exit("API route disabled (use the Codex CLI route); pass --allow-api to override")


def cmd_gen_sheet(a):
    _api_guard(a)
    generate(f"sheet_{a.tag}", sheet_prompt(a.tag), "1536x1024", a.quality, "opaque")


def cmd_gen_single(a):
    _api_guard(a)
    only = a.only.split(",") if a.only else SPRITES
    for n in only:
        p = generate(f"single_{a.tag}_{n}", single_prompt(n, a.tag, a.background), "1024x1024",
                     a.quality, a.background)
        if p is None:
            print("request refused (see calls.jsonl error); if it names `background`, rerun with "
                  "--background opaque")
            return


def cmd_cut_sheet(a):
    # Codex's image tool may hand back RGBA with a crude blocky background matte that keeps black
    # blobs around each sprite; ignore it: flatten onto black and key from brightness instead.
    src = Image.open(ROOT / a.raw).convert("RGBA")
    raw = Image.new("RGBA", src.size, (0, 0, 0, 255))
    raw.alpha_composite(src)
    raw = raw.convert("RGB")
    arr = np.asarray(raw).astype(np.float32) / 255
    H, W = arr.shape[:2]
    cw, ch = W // 3, H // 2
    dest = OUT / (a.dest or "sheet")
    solid = set(a.solid.split(",")) - {""} if a.solid is not None else SOLID
    for i, n in enumerate(SPRITES):
        cx, cy = (i % 3) * cw, (i // 3) * ch
        cellarr = arr[cy:cy + ch, cx:cx + cw]
        edge = np.concatenate([cellarr[0], cellarr[-1], cellarr[:, 0], cellarr[:, -1]]).max()
        if edge > 0.1:
            print(f"warning: {n} cell border brightness {edge:.2f} (sprite may cross the cell)")
        write_pair(to_uint8(key_black(cellarr, n in solid, solid_thr=a.solid_thr)), dest, n)
    contact(dest, SPRITES, dest / "contact.png")
    print("wrote", dest)


def cmd_cut_single(a):
    only = a.only.split(",") if a.only else SPRITES
    dest = OUT / "single"
    for n in only:
        p = RAW / f"single_{a.tag}_{n}.png"
        img = Image.open(p)
        if img.mode == "RGBA" and np.asarray(img.getchannel("A")).min() < 250:
            write_pair(img.convert("RGBA"), dest, n)
        else:  # opaque fallback on black
            arr = np.asarray(img.convert("RGB")).astype(np.float32) / 255
            write_pair(to_uint8(key_black(arr, n in SOLID)), dest, n)
    contact(dest, SPRITES, dest / "contact.png")
    print("wrote", dest)


def cmd_pick(a):
    """Copy the delivered set into gpt/ top level: default all from one approach, with
    per-sprite overrides like --from sheet:leaf,single:wisp."""
    src = {n: a.approach for n in SPRITES}
    if a.frm:
        for tok in a.frm.split(","):
            appr, n = tok.split(":")
            src[n] = appr
    for n, appr in src.items():
        for suf in ("", "_color"):
            Image.open(OUT / appr / f"{n}{suf}.png").save(OUT / f"{n}{suf}.png")
    contact(OUT, SPRITES, OUT / "contact.png")
    (OUT / "picked_from.json").write_text(json.dumps(src, indent=1))
    print("picked", src)


def cmd_result(a):
    rows = [json.loads(l) for l in CALLS.read_text(encoding="utf-8").splitlines() if l.strip()]
    ok = [r for r in rows if r["status"] == 200]
    per_call = [{"name": r["name"], "quality": r["quality"], "size": r["size"],
                 "background": r["background"], "seconds": r["seconds"], "status": r["status"],
                 "usage": r.get("usage"), "usd_tokens": r.get("usd_tokens"),
                 "usd_calculator": r.get("usd_calculator"), "usd_budgeted": r.get("usd_budgeted", 0)}
                for r in rows]
    by = {}
    for r in ok:
        appr = "sheet" if r["name"].startswith("sheet") else "single"
        d = by.setdefault(appr, {"calls": 0, "usd": 0.0, "seconds": 0.0})
        d["calls"] += 1
        d["usd"] = round(d["usd"] + r["usd_budgeted"], 4)
        d["seconds"] = round(d["seconds"] + r["seconds"], 1)
    runs = json.loads(Path(a.runs_file).read_text(encoding="utf-8")) if a.runs_file else []
    for r in runs:
        d = by.setdefault(r["approach"], {"calls": 0, "usd": 0.0, "seconds": 0.0})
        d["calls"] += 1
        d["seconds"] = round(d["seconds"] + r["seconds"], 1)
    notes = Path(a.notes_file).read_text(encoding="utf-8") if a.notes_file else ""
    res = {
        "method": "gpt (GPT Image via Codex CLI built-in image tool; API route blocked by 429)",
        "wall_minutes": a.wall_minutes,
        "generation_seconds": round(sum(r["seconds"] for r in rows) + sum(r["seconds"] for r in runs), 1),
        "cost": {"usd": round(sum(r.get("usd_budgeted", 0) for r in rows), 4),
                 "subscription": "codex runs use the ChatGPT subscription, 0 USD marginal",
                 "usd_by_tokens": round(sum(r.get("usd_tokens") or 0 for r in ok), 4),
                 "pricing": {"per_1M_tokens": PRICE, "calculator_per_image": {
                     f"{q} {s}": v for (q, s), v in CALC_USD.items()}}},
        "attempts": len(rows) + len(runs),
        "codex_runs": runs,
        "by_approach": by,
        "picked_from": json.loads((OUT / "picked_from.json").read_text()) if (OUT / "picked_from.json").exists() else None,
        "scripts": ["tools/vfx/gpt_sprites.py"],
        "calls": per_call,
        "notes": notes,
    }
    (OUT / "result.json").write_text(json.dumps(res, indent=1), encoding="utf-8")
    print(json.dumps({k: res[k] for k in ("generation_seconds", "cost", "attempts", "by_approach")}, indent=1))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("gen-sheet"); s.add_argument("--tag", default="r1"); s.add_argument("--quality", default="medium")
    s.add_argument("--allow-api", action="store_true")
    s = sub.add_parser("gen-single"); s.add_argument("--tag", default="r1"); s.add_argument("--quality", default="medium")
    s.add_argument("--only"); s.add_argument("--background", default="transparent")
    s.add_argument("--allow-api", action="store_true")
    s = sub.add_parser("cut-sheet"); s.add_argument("--raw", required=True)
    s.add_argument("--solid", help="comma list of sprites keyed as solid shapes ('' = none)")
    s.add_argument("--dest", help="subfolder of gpt/ (default sheet)")
    s.add_argument("--solid-thr", type=float, default=0.12,
                   help="brightness above which a solid sprite's silhouette is filled opaque; raise it "
                        "(~0.35) to let a dark drawn outline fall back to brightness alpha")
    s = sub.add_parser("cut-single"); s.add_argument("--tag", default="r1"); s.add_argument("--only")
    s = sub.add_parser("pick"); s.add_argument("--approach", default="single"); s.add_argument("--from", dest="frm")
    s = sub.add_parser("result"); s.add_argument("--wall-minutes", type=float, required=True); s.add_argument("--notes-file")
    s.add_argument("--runs-file", help="json list of codex runs {name, approach, seconds, images}")
    a = ap.parse_args()
    {"gen-sheet": cmd_gen_sheet, "gen-single": cmd_gen_single, "cut-sheet": cmd_cut_sheet,
     "cut-single": cmd_cut_single, "pick": cmd_pick, "result": cmd_result}[a.cmd](a)


if __name__ == "__main__":
    main()
