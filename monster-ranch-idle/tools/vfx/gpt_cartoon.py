"""Bake-off entrant 'gpt-cartoon': GPT Image via the Codex CLI with the precise cartoon brief
(art/vfx/bakeoff/gpt-cartoon/PROMPT.md). Codex drops raw PNGs into gpt-cartoon/raw/<tag>_<sprite>.png;
this script turns them into the SPEC deliverables.

  python tools/vfx/gpt_cartoon.py build [--pick flame=r2,leaf=r1 ...]   # default r1 for every sprite
  python tools/vfx/gpt_cartoon.py versus
  python tools/vfx/gpt_cartoon.py result --wall-minutes N --runs-file F --notes-file F

Colour version: a real alpha channel is kept as is (trim / centre / 80% / 256); art on black is keyed
with gpt_sprites.key_black. Transparent pixels get the nearest opaque colour bled in (clean filtering).
Grey (tintable) version, per PROMPT.md: the cel tones stay distinct greys - the most common tone (base)
maps to 0.80, the darkest (outline) to 0.40, tones between them to ~0.60, lighter tones to 0.95 and
pure-white highlights to 1.0; mapping is piecewise-linear in luminance so anti-aliased edges blend.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gpt_sprites as gs  # noqa: E402  (frame, key_black, to_uint8)

ROOT = gs.ROOT
OUT = ROOT / "art" / "vfx" / "bakeoff" / "gpt-cartoon"
RAW = OUT / "raw"
ROUND1 = ROOT / "art" / "vfx" / "bakeoff" / "gpt"
SPRITES = gs.SPRITES


def load_color(p: Path) -> Image.Image:
    img = Image.open(p)
    if img.mode == "RGBA" and np.asarray(img.getchannel("A")).min() < 250:
        return img.convert("RGBA")
    arr = np.asarray(img.convert("RGB")).astype(np.float32) / 255
    return gs.to_uint8(gs.key_black(arr, True, solid_thr=0.2))


def _box3(x: np.ndarray) -> np.ndarray:
    p = np.pad(x, 1, mode="edge")
    h, w = x.shape
    return sum(p[dy:dy + h, dx:dx + w] for dy in range(3) for dx in range(3))


def bleed(img: Image.Image, iters: int = 24) -> Image.Image:
    """Fill RGB under alpha==0 with the nearest opaque-ish colour (alpha untouched)."""
    arr = np.asarray(img).astype(np.float32)
    rgb, a = arr[..., :3], arr[..., 3]
    known = (a > 0).astype(np.float32)
    acc = rgb * known[..., None]
    for _ in range(iters):
        if known.min() > 0:
            break
        s = _box3(known)
        c = np.dstack([_box3(acc[..., i] * known) for i in range(3)])
        newly = (known == 0) & (s > 0)
        acc[newly] = c[newly] / s[newly][:, None]
        known[newly] = 1.0
    acc[known == 0] = rgb[a > 0].mean(0) if (a > 0).any() else 0
    out = np.dstack([acc, a])
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGBA")


def kmeans1d(x: np.ndarray, k: int, iters: int = 30) -> np.ndarray:
    c = np.quantile(x, np.linspace(0.02, 0.98, k))
    for _ in range(iters):
        lab = np.abs(x[:, None] - c[None]).argmin(1)
        for j in range(k):
            if (lab == j).any():
                c[j] = x[lab == j].mean()
    lab = np.abs(x[:, None] - c[None]).argmin(1)
    counts = np.bincount(lab, minlength=k)
    keep = counts > 0.004 * len(x)
    return c[keep], counts[keep]


def to_grey_tones(img: Image.Image) -> tuple[Image.Image, dict]:
    arr = np.asarray(img).astype(np.float32) / 255
    rgb, a = arr[..., :3], arr[..., 3]
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    body = lum[a > 0.9]
    cent, cnt = kmeans1d(body, 6)
    o = np.argsort(cent)
    cent, cnt = cent[o], cnt[o]
    # merge tones closer than 0.04 in luminance (one flat tone split by k-means); mapping two such
    # halves to different greys turns the model's faint pixel noise into visible speckle
    mc, mn = [cent[0]], [cnt[0]]
    for c, n in zip(cent[1:], cnt[1:]):
        if c - mc[-1] < 0.04:
            mc[-1] = (mc[-1] * mn[-1] + c * n) / (mn[-1] + n)
            mn[-1] += n
        else:
            mc.append(c)
            mn.append(n)
    cent, cnt = np.array(mc), np.array(mn)
    base = int(np.argmax(cnt))
    tgt = np.zeros_like(cent)
    tgt[base] = 0.80
    dark = list(range(base))
    if dark:
        tgt[0] = 0.40
        for i in dark[1:]:  # between outline and base
            tgt[i] = 0.60 if len(dark) == 2 else 0.40 + 0.40 * (i / base) ** 0.8
    for i in range(base + 1, len(cent)):
        tgt[i] = 1.0 if cent[i] > 0.93 else 0.95
    # keep monotone
    tgt = np.maximum.accumulate(tgt)
    g = np.interp(lum, cent, tgt)
    g = np.where(a > 0, g, 0)
    info = {"tone_lum": [round(float(v), 3) for v in cent], "tone_grey": [round(float(v), 2) for v in tgt],
            "tone_share": [round(float(v) / cnt.sum(), 3) for v in cnt]}
    return gs.to_uint8(np.dstack([g, g, g, a])), info


def contact_dual(folder: Path, out: Path, bgs=("#202028", "#E8E8E8")) -> None:
    cell, pad = 128, 8
    rows = [(k, bg) for bg in bgs for k in ("grey", "color")]
    W, H = pad + 6 * (cell + pad), pad + len(rows) * (cell + pad)
    sheet = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    for ri, (kind, bg) in enumerate(rows):
        y = pad + ri * (cell + pad)
        sheet.paste(Image.new("RGBA", (W, cell + pad), bg), (0, y - pad // 2))
        for ci, n in enumerate(SPRITES):
            p = folder / (f"{n}.png" if kind == "grey" else f"{n}_color.png")
            if p.exists():
                sp = Image.open(p).convert("RGBA").resize((cell, cell), Image.LANCZOS)
                sheet.alpha_composite(sp, (pad + ci * (cell + pad), y))
    sheet.convert("RGB").save(out)


def cmd_build(a):
    pick = {n: "r1" for n in SPRITES}
    if a.pick:
        for tok in a.pick.split(","):
            n, t = tok.split("=")
            pick[n] = t
    tones = {}
    for n in SPRITES:
        src = RAW / f"{pick[n]}_{n}.png"
        framed = gs.frame(load_color(src))
        grey, info = to_grey_tones(framed)
        bleed(framed).save(OUT / f"{n}_color.png")
        bleed(grey).save(OUT / f"{n}.png")
        tones[n] = {"from": src.name, **info}
    contact_dual(OUT, OUT / "contact.png")
    (OUT / "build.json").write_text(json.dumps(tones, indent=1))
    print(json.dumps(tones, indent=1))


def cmd_versus(a):
    cell, pad = 160, 10
    bgs = ["#22202B", "#EAF0E2"]
    sets = [ROUND1, OUT]
    W = pad + 6 * (cell + pad)
    H = pad + len(bgs) * len(sets) * (cell + pad)
    sheet = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    r = 0
    for bg in bgs:
        for folder in sets:
            y = pad + r * (cell + pad)
            sheet.paste(Image.new("RGBA", (W, cell + pad), bg), (0, y - pad // 2))
            for ci, n in enumerate(SPRITES):
                p = folder / f"{n}_color.png"
                if p.exists():
                    sp = Image.open(p).convert("RGBA").resize((cell, cell), Image.LANCZOS)
                    sheet.alpha_composite(sp, (pad + ci * (cell + pad), y))
            r += 1
    sheet.convert("RGB").save(OUT / "versus.png")
    print("rows: dark[round1, cartoon], light[round1, cartoon]")


def cmd_result(a):
    runs = json.loads(Path(a.runs_file).read_text(encoding="utf-8"))
    res = {
        "method": "gpt-cartoon (GPT Image via Codex CLI image_gen, precise cartoon brief + style ref)",
        "wall_minutes": a.wall_minutes,
        "generation_seconds": round(sum(r["seconds"] for r in runs), 1),
        "cost": {"usd": 0, "subscription": "Codex CLI on the ChatGPT subscription, 0 USD marginal"},
        "attempts": len(runs),
        "codex_runs": runs,
        "picked_from": json.loads((OUT / "build.json").read_text()) if (OUT / "build.json").exists() else None,
        "scripts": ["tools/vfx/gpt_cartoon.py", "tools/vfx/gpt_sprites.py"],
        "notes": Path(a.notes_file).read_text(encoding="utf-8"),
    }
    (OUT / "result.json").write_text(json.dumps(res, indent=1), encoding="utf-8")
    print("wrote result.json")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("build"); s.add_argument("--pick")
    sub.add_parser("versus")
    s = sub.add_parser("result"); s.add_argument("--wall-minutes", type=float, required=True)
    s.add_argument("--runs-file", required=True); s.add_argument("--notes-file", required=True)
    a = ap.parse_args()
    {"build": cmd_build, "versus": cmd_versus, "result": cmd_result}[a.cmd](a)


if __name__ == "__main__":
    main()
