"""UI item and currency icons via the Codex CLI image tool (ChatGPT subscription, never the API).

The icon table IS art/ui/ICONS.md (one markdown table per group); the style block is read word for
word from its "## Style block" section. The pipeline is tools/vfx/codex_sprites.py's: the Kindlefox
concept + the six approved particle anchors are attached to every session, so the icons share the
particle sprites' cartoon style.

Usage (from monster-ranch-idle):
  python tools/ui/codex_icons.py sync                        # add rows for new decor / themes / accessories
  python tools/ui/codex_icons.py all                         # gen every row with no raw yet, then build
  python tools/ui/codex_icons.py gen [--names a,b] [--batch 5] [--parallel 3]
  python tools/ui/codex_icons.py fix --item "cur_coin=the rim is too thin" [--item ...] [--keep "..."]
                                                             # edit-style redo of the current pick -> next rN
  python tools/ui/codex_icons.py build [--pick cur_coin=r1,cur_gem=r2]   # picks persist in raw/picks.json
  python tools/ui/codex_icons.py prompt --names a,b          # print the session prompt, run nothing

Codex writes each PNG to art/ui/icons/raw/<name>_<tag>.png (git-ignored); sessions and logs go to
raw/runs.jsonl and raw/logs/. Build trims, centres and scales every pick to 86% of 256 px, bleeds
colour into transparent pixels and writes art/ui/icons/cells/<name>.png (git-ignored), then
art/ui/icons/manifest.json and contact.jpg (dark and cream strips at 128 / 48 / 32 px). Pack the cells
with `python tools/ui/atlas.py icons`.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "vfx"))
import uiart  # noqa: E402
import gpt_sprites as gs  # noqa: E402  frame
import gpt_cartoon as gc  # noqa: E402  load_color, bleed

ROOT = uiart.ROOT
SPEC = uiart.ART_UI / "ICONS.md"
OUT = uiart.ART_UI / "icons"
CELLS = OUT / "cells"
RAW = OUT / "raw"
LOGS = RAW / "logs"
RUNS = RAW / "runs.jsonl"
PICKS = RAW / "picks.json"
ROUND2 = ROOT / "art" / "vfx" / "bakeoff" / "gpt-cartoon"
ANCHORS = ["flame", "droplet", "leaf", "bolt", "star", "wisp"]
MODEL = "gpt-6-astra"
FILL = 0.86

# Default subject words per accessory shape (Config.Accessories `shape`); a row can be edited freely.
SHAPE_WORDS = {
    "beanie": "a knitted beanie hat with a pom-pom", "bell": "a round collar bell on a little strap",
    "blush": "a pair of round rosy blush-cheek patches", "board": "a small surfboard",
    "bowtie": "a bow tie", "brim": "a wide-brimmed hat", "bubble": "a round glass bubble helmet",
    "cap": "a cap", "cape": "a flowing cape", "chef": "a puffy chef's hat", "cone": "a cone-shaped party hat",
    "crown": "a crown", "ears": "a headband with two cute ears", "flowers": "a flower crown",
    "glasses": "a pair of round glasses", "goggles": "a pair of aviator goggles", "halo": "a floating halo ring",
    "helmet": "a helmet", "horns": "a pair of little horns on a headband", "jetpack": "a small jetpack",
    "lei": "a flower lei necklace", "mask": "a face mask", "medal": "a medal on a ribbon",
    "monocle": "a monocle on a little chain", "mustache": "a curly mustache", "pack": "a small backpack",
    "scarf": "a knitted scarf", "shades": "a pair of sunglasses", "tophat": "a top hat with a band",
    "wings": "a pair of little wings", "wizard": "a pointed wizard hat",
}
DECOR_WORDS = {"disc": ", flat and low on the ground"}


# ------------------------------------------------------------------------------------ spec

def _sections(md: str) -> dict[str, list[list[str]]]:
    out, sec = {}, None
    for line in md.splitlines():
        if line.startswith("## "):
            sec = line[3:].strip()
            continue
        if sec and line.startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if set("".join(cells)) <= set("-: "):
                continue
            out.setdefault(sec, []).append(cells)
    return {k: v[1:] for k, v in out.items()}


def load_spec() -> dict[str, dict]:
    spec = {}
    for sec, rows in _sections(SPEC.read_text(encoding="utf-8")).items():
        for r in rows:
            spec[r[0]] = {"name": r[0], "group": sec, "subject": r[1], "colours": r[2]}
    return spec


def style_block() -> str:
    m = re.search(r"## Style block[^\n]*\n(.*?)\n## ", SPEC.read_text(encoding="utf-8"), re.S)
    return m.group(1).strip()


def _lighter(hexc: str, t: float = 0.55) -> str:
    c = [int(hexc[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(v + (255 - v) * t):02X}" for v in c)


def synced_rows(cfg: dict) -> dict[str, list[tuple[str, str, str]]]:
    """Default rows for the config-driven groups: {section: [(name, subject, colours)]}."""
    ink = "#1B1B1B"
    decor = [(f"decor_{d['id']}", f"a {d['name']}, a pen decoration for a monster ranch{DECOR_WORDS.get(d['shape'], '')}",
              f"{d['color']}, {_lighter(d['color'])}, {ink}") for d in cfg["decor"]]

    def fence(t):
        return t["name"] if re.search(r"fence|wall", t["name"], re.I) else f"{t['name']} themed fence"

    themes = [(f"theme_{t['id']}", f"a small square patch of ground with a short stretch of {fence(t)} standing"
               f" along its back edge, like a swatch for a ranch pen style (fence colour first, ground second)",
               f"{t['fence']}, {t['ground']}, {ink}") for t in cfg["themes"]]
    acc = [(f"acc_{a['id']}", f"{a['name']}: {SHAPE_WORDS.get(a['shape'], a['shape'])}, a {a['slot']} accessory for a"
            f" pet monster, shown on its own with nobody wearing it",
            f"{a['color']}, {a.get('color2') or _lighter(a['color'])}, {ink}") for a in cfg["accessories"]]
    return {"Decor": decor, "Pen themes": themes, "Accessories": acc}


def cmd_sync(_a):
    cfg = uiart.config()
    lines = SPEC.read_text(encoding="utf-8").splitlines()
    have = set(load_spec())
    added, stale = 0, []
    for sec, rows in synced_rows(cfg).items():
        want = {r[0] for r in rows}
        stale += [n for n, s in load_spec().items() if s["group"] == sec and n not in want]
        head = lines.index(f"## {sec}")
        end = head + 1
        while end < len(lines) and not lines[end].startswith("## "):
            end += 1
        last = max(i for i in range(head, end) if lines[i].startswith("|"))
        new = [f"| {n} | {s} | {c} |" for n, s, c in rows if n not in have]
        lines[last + 1:last + 1] = new
        added += len(new)
    SPEC.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"sync: {added} rows added, {len(load_spec())} rows total")
    if stale:
        print("rows no longer in the config (left in place):", ", ".join(stale))


# ------------------------------------------------------------------------------------ prompts

def attach_note() -> str:
    return ("Attached images: the FIRST is a monster from the game (the world's look: soft vinyl-toy cartoon). The next"
            " six are approved particle sprites from this game (" + ", ".join(ANCHORS) + "): match their drawing style"
            " (flat cel tones, chunky sticker shapes, small white highlight top-left). Unlike those sprites, icons use a"
            " near-black #1B1B1B outline.")


def colour_line(s: dict) -> str:
    return f"Colours (main / second / outline): {s['colours']}."


def _copy_rule(pairs: list[tuple[str, str]]) -> str:
    dests = "; ".join(f"{n} -> {RAW / f'{n}_{t}.png'}" for n, t in pairs)
    return ("After each image is generated, copy its PNG file (unchanged: keep the alpha channel, do not resize,"
            " convert or edit it) to exactly this path: " + dests + ". Do not create or change any other file."
            " When done, list the files you wrote.")


def gen_prompt(items: list[dict], tag: str) -> str:
    lines = [f"You are making game UI icons with your built-in image generation tool. Make {len(items)} images in the"
             f" same style, one per icon below; each is its own separate square image containing exactly one object.",
             "", attach_note(), "", style_block(), "", "Icons (subject, then colours):"]
    for i, s in enumerate(items, 1):
        lines.append(f"{i}. {s['name']}: {s['subject']}. {colour_line(s)}")
    lines += ["", _copy_rule([(s["name"], tag) for s in items])]
    return "\n".join(lines)


def fix_prompt(items: list[tuple[dict, str, str, str]], keep: str) -> str:
    n_anchor = 1 + len(ANCHORS)
    lines = [f"You are editing game UI icons with your built-in image generation tool (image edit of an attached"
             f" image). Make {len(items)} edited images, one per item below.", "", attach_note(),
             f" Attachments after those {n_anchor} are the icons to edit, in the order of the items below.", "",
             "The style every icon must keep:", style_block(), "", "Edits:"]
    for i, (s, cur, _new, fix) in enumerate(items, 1):
        lines.append(f"{i}. {s['name']} (attachment {n_anchor + i}, file {s['name']}_{cur}.png): {s['subject']}."
                     f" {colour_line(s)} FIX: {fix}. KEEP: {keep}")
    lines += ["", _copy_rule([(s["name"], new) for s, _, new, _ in items])]
    return "\n".join(lines)


# ------------------------------------------------------------------------------------ codex runs

def attempts_of(name: str) -> list[str]:
    tags = [p.stem.rsplit("_", 1)[1] for p in RAW.glob(f"{name}_r*.png")]
    return sorted((t for t in tags if t[1:].isdigit()), key=lambda t: int(t[1:]))


def run_session(session: str, prompt: str, extra: list[Path], expect: list[Path]) -> dict:
    LOGS.mkdir(parents=True, exist_ok=True)
    exe = shutil.which("codex") or "codex"
    imgs = [uiart.art_source("art/meshy/kindlefox-concept/image_0.png")]
    imgs += [ROUND2 / f"{a}_color.png" for a in ANCHORS] + list(extra)
    cmd = [exe, "exec", "-m", MODEL, "-c", 'model_reasoning_effort="high"', "--skip-git-repo-check", "-C", str(ROOT),
           "-o", str(LOGS / f"{session}.last.txt")]
    for p in imgs:
        cmd += ["-i", str(p)]
    (LOGS / f"{session}.prompt.txt").write_text(prompt, encoding="utf-8", newline="\n")
    t0 = time.time()
    with open(LOGS / f"{session}.log", "w", encoding="utf-8", errors="replace") as log:
        proc = subprocess.run(cmd, input=prompt, text=True, encoding="utf-8", stdout=log, stderr=subprocess.STDOUT,
                              cwd=str(ROOT), shell=exe.lower().endswith((".cmd", ".bat")))
    secs = round(time.time() - t0, 1)
    got = [p.name for p in expect if p.exists() and p.stat().st_mtime >= t0 - 1]
    row = {"session": session, "model": MODEL, "seconds": secs, "exit": proc.returncode,
           "expected": [p.name for p in expect], "images": got, "images_n": len(got),
           "start": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(t0))}
    with RUNS.open("a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(row) + "\n")
    print(f"[{session}] exit {proc.returncode} {secs}s images {len(got)}/{len(expect)}", flush=True)
    return row


def _parallel(jobs, parallel: int):
    with ThreadPoolExecutor(max_workers=parallel) as ex:
        return list(ex.map(lambda j: run_session(*j), jobs))


def cmd_gen(a):
    spec = load_spec()
    names = a.names.split(",") if a.names else [n for n in spec if not attempts_of(n)]
    bad = [n for n in names if n not in spec]
    if bad:
        sys.exit(f"not rows in ICONS.md: {bad}")
    if not names:
        print("nothing to generate")
        return
    jobs, stamp = [], time.strftime("%H%M%S")
    for bi in range(0, len(names), a.batch):
        by_tag: dict[str, list[dict]] = {}
        for n in names[bi:bi + a.batch]:
            by_tag.setdefault(f"r{len(attempts_of(n)) + 1}", []).append(spec[n])
        for tag, group in by_tag.items():
            jobs.append((f"gen{stamp}_{bi // a.batch}_{tag}", gen_prompt(group, tag), [],
                         [RAW / f"{s['name']}_{tag}.png" for s in group]))
    if a.dry:
        for j in jobs:
            print(j[0], [p.name for p in j[3]])
        return
    _parallel(jobs, a.parallel)


def cmd_fix(a):
    spec, picks = load_spec(), _load_picks()
    fixes = []
    for it in a.item:
        n, txt = it.split("=", 1)
        if n not in spec or not attempts_of(n):
            sys.exit(f"{n} has no row or no raw attempt yet")
        cur = picks.get(n) or attempts_of(n)[-1]
        fixes.append((spec[n], cur, f"r{len(attempts_of(n)) + 1}", txt.strip().rstrip(".")))
    keep = a.keep or "everything else exactly as it is: the shape, view, colours, outline, highlight and transparent background"
    jobs, stamp = [], time.strftime("%H%M%S")
    for bi in range(0, len(fixes), a.batch):
        chunk = fixes[bi:bi + a.batch]
        jobs.append((f"fix{stamp}_{bi // a.batch}", fix_prompt(chunk, keep),
                     [RAW / f"{s['name']}_{cur}.png" for s, cur, _, _ in chunk],
                     [RAW / f"{s['name']}_{new}.png" for s, _, new, _ in chunk]))
    _parallel(jobs, a.parallel)


def cmd_prompt(a):
    spec = load_spec()
    print(gen_prompt([spec[n] for n in a.names.split(",")], "r1"))


# ------------------------------------------------------------------------------------ build

def _load_picks() -> dict:
    return json.loads(PICKS.read_text()) if PICKS.exists() else {}


def cmd_build(a):
    spec, picks = load_spec(), _load_picks()
    if a.pick:
        for tok in a.pick.split(","):
            n, t = tok.split("=")
            picks[n] = t
        PICKS.parent.mkdir(parents=True, exist_ok=True)
        PICKS.write_text(json.dumps(picks, indent=1), encoding="utf-8", newline="\n")
    CELLS.mkdir(parents=True, exist_ok=True)
    manifest, missing = [], []
    for n, s in spec.items():
        tags = attempts_of(n)
        if not tags:
            missing.append(n)
            continue
        tag = picks.get(n, tags[-1])
        framed = gs.frame(gc.load_color(RAW / f"{n}_{tag}.png"), 256, FILL)
        gc.bleed(framed).save(CELLS / f"{n}.png")
        manifest.append({"name": n, "group": s["group"], "file": f"cells/{n}.png", "from": f"raw/{n}_{tag}.png",
                         "attempts": len(tags)})
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8", newline="\n")
    contact([m["name"] for m in manifest], OUT / "contact.jpg")
    print(f"built {len(manifest)} icons -> {CELLS}")
    if missing:
        print(f"missing raw ({len(missing)}; run gen):", ", ".join(missing))


def contact(names: list[str], out: Path, per_row: int = 12) -> None:
    """Every icon at 128 px with 48 and 32 px copies below, on a dark and a cream strip."""
    cell, pad, lab = 128, 8, 14
    rows = [names[i:i + per_row] for i in range(0, len(names), per_row)]
    band_h = lab + cell + pad + 48 + pad
    W = pad + per_row * (cell + pad)
    sheet = Image.new("RGB", (W, max(1, 2 * len(rows) * band_h)), "#000000")
    y0 = 0
    for bg, ink in (("#22202B", (230, 230, 230)), ("#FFF7E3", (40, 40, 40))):
        for row in rows:
            band = Image.new("RGBA", (W, band_h), bg)
            d = ImageDraw.Draw(band)
            for ci, n in enumerate(row):
                x = pad + ci * (cell + pad)
                d.text((x, 1), n[:22], fill=ink)
                im = Image.open(CELLS / f"{n}.png").convert("RGBA")
                band.alpha_composite(im.resize((cell, cell), Image.LANCZOS), (x, lab))
                band.alpha_composite(im.resize((48, 48), Image.LANCZOS), (x + 8, lab + cell + pad))
                band.alpha_composite(im.resize((32, 32), Image.LANCZOS), (x + 72, lab + cell + pad + 8))
            sheet.paste(band.convert("RGB"), (0, y0))
            y0 += band_h
    sheet.save(out, quality=88)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("sync")
    for nm in ("gen", "all"):
        s = sub.add_parser(nm)
        s.add_argument("--names")
        s.add_argument("--batch", type=int, default=5)
        s.add_argument("--parallel", type=int, default=3)
        s.add_argument("--dry", action="store_true")
        s.add_argument("--pick")
    s = sub.add_parser("fix")
    s.add_argument("--item", action="append", required=True, help='name="what to fix"')
    s.add_argument("--keep")
    s.add_argument("--batch", type=int, default=5)
    s.add_argument("--parallel", type=int, default=3)
    s = sub.add_parser("build")
    s.add_argument("--pick")
    s = sub.add_parser("prompt")
    s.add_argument("--names", required=True)
    a = ap.parse_args()
    if a.cmd == "all":
        cmd_gen(a)
        if not a.dry:
            cmd_build(a)
    else:
        {"sync": cmd_sync, "gen": cmd_gen, "fix": cmd_fix, "build": cmd_build, "prompt": cmd_prompt}[a.cmd](a)


if __name__ == "__main__":
    main()
