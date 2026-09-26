"""Production particle sprites via the Codex CLI image tool (ChatGPT subscription, never the API).

The sprite table IS art/vfx/SPRITES.md (three markdown tables: carried / new (Codex) / procedural);
the style block is read word for word from art/vfx/bakeoff/gpt-cartoon/PROMPT.md. To add a sprite,
add one row to the "New" table in SPRITES.md and run `all`.

Usage (from the repo root):
  python tools/vfx/codex_sprites.py all                     # gen every Codex row with no raw yet, then build
  python tools/vfx/codex_sprites.py gen [--names a,b] [--batch 5] [--parallel 3]
  python tools/vfx/codex_sprites.py fix --item "coin=the rim is too thin" --item "ring=..." [--keep "..."]
                                                            # edit-style redo of the current pick -> next rN
  python tools/vfx/codex_sprites.py build [--pick coin=r1,ring=r2]   # (picks persist in raw/picks.json)
  python tools/vfx/codex_sprites.py prompt --names a,b      # print the session prompt, run nothing

Codex runs: `codex exec -m gpt-6-astra -c model_reasoning_effort="high" --skip-git-repo-check -C <repo>
-i <kindlefox> -i <six approved anchors> [-i <raw to edit>]`, prompt on stdin. Codex copies every PNG
it makes to art/vfx/sprites/raw/<name>_<tag>.png. Sessions of ~5 sprites (~70 s per image) run in
parallel; every session is logged to raw/runs.jsonl (+ raw/logs/<session>.log).

Build: real alpha kept (black background keyed as a fallback), trim / centre / 80% of 256, colour bled
into transparent pixels; TINT rows also get <name>_grey.png (tones outline .40 / shade .60 / base .80
/ light .95 / highlight 1.0, gpt_cartoon.to_grey_tones). White-by-design rows (colours mention
"white"): the colour file is the tintable file and <name>_grey.png is a copy. Carried rows are copied
from the round-2 folder; procedural rows are drawn by tools/vfx/procedural.py. Writes
art/vfx/sprites/manifest.json and contact.png (dark #22202B and light #EAF0E2 strips, 128/48/24 px).
Picks default to the newest attempt; attempts = number of raw attempts for that sprite.
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
import gpt_sprites as gs  # noqa: E402  frame, to_uint8
import gpt_cartoon as gc  # noqa: E402  load_color, bleed, to_grey_tones

ROOT = gs.ROOT
SPEC = ROOT / "art" / "vfx" / "SPRITES.md"
PROMPT_MD = ROOT / "art" / "vfx" / "bakeoff" / "gpt-cartoon" / "PROMPT.md"
ROUND2 = ROOT / "art" / "vfx" / "bakeoff" / "gpt-cartoon"
OUT = ROOT / "art" / "vfx" / "sprites"
RAW = OUT / "raw"
LOGS = RAW / "logs"
RUNS = RAW / "runs.jsonl"
PICKS = RAW / "picks.json"
KINDLEFOX = ROOT / "art" / "meshy" / "kindlefox-concept" / "image_0.png"
ANCHORS = ["flame", "droplet", "leaf", "bolt", "star", "wisp"]
MODEL = "gpt-6-astra"
HEX = re.compile(r"#[0-9A-Fa-f]{6}")


# ------------------------------------------------------------------------------------ spec parsing

def _tables(md: str) -> dict[str, list[list[str]]]:
    """{section heading: [row cells]} for every markdown table under a '## ' heading."""
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
    return {k: v[1:] for k, v in out.items()}  # drop header rows


def load_spec() -> dict[str, dict]:
    t = _tables(SPEC.read_text(encoding="utf-8"))
    spec: dict[str, dict] = {}
    for sec, rows in t.items():
        low = sec.lower()
        for r in rows:
            name = r[0]
            if low.startswith("carried"):
                spec[name] = {"name": name, "source": "carried", "from": r[1],
                              "tint": "TINT" in r[2], "white": False}
            elif low.startswith("new"):
                spec[name] = {"name": name, "source": "codex", "subject": r[1], "colours": r[2],
                              "tint": "TINT" in r[3], "white": "white" in r[2].lower()}
            elif low.startswith("drawn"):
                spec[name] = {"name": name, "source": "procedural", "subject": r[1],
                              "tint": "TINT" in r[2], "white": True}
    return spec


def style_block() -> str:
    md = PROMPT_MD.read_text(encoding="utf-8")
    m = re.search(r"## Shared style block[^\n]*\n(.*?)\n## ", md, re.S)
    return m.group(1).strip()


# ------------------------------------------------------------------------------------ prompts

def colour_line(s: dict) -> str:
    h = HEX.findall(s["colours"])
    if len(h) == 4:
        c = f"Colours: base {h[0]}, shade {h[1]}, light {h[2]}, outline {h[3]}."
    else:
        c = f"Colours (base / shade / light / outline): {s['colours']}."
    if s["white"]:
        c += (" This sprite is WHITE by design (it is tinted in the engine): white body, light-grey"
              " shade, and the grey outline exactly as given - here a grey outline is intended.")
    return c


def attach_note() -> str:
    return ("Attached images: the FIRST is a monster from the game (the world's look: soft vinyl-toy"
            " cartoon). The next six are approved particle sprites from this same set (" +
            ", ".join(ANCHORS) + "): they are the EXACT target style. Match them precisely: the same"
            " outline weight, the same flat 3-tone cel shading with hard edges, the same small white"
            " highlight top-left, the same chunky sticker look, transparent background.")


def gen_prompt(items: list[dict], tag: str) -> str:
    lines = [f"You are making game particle sprites with your built-in image generation tool. Make"
             f" {len(items)} images in the same style, one per sprite below; each is its own separate"
             f" image containing exactly one object.", "", attach_note(), "", style_block(), "",
             "Sprites (subject, then colours):"]
    for i, s in enumerate(items, 1):
        lines.append(f"{i}. {s['name']}: {s['subject']}. {colour_line(s)}")
    lines += ["", _copy_rule([(s["name"], tag) for s in items])]
    return "\n".join(lines)


def fix_prompt(items: list[tuple[dict, str, str, str]], keep: str) -> str:
    """items: (spec, current tag, new tag, what to fix)."""
    n_anchor = 1 + len(ANCHORS)
    lines = [f"You are editing game particle sprites with your built-in image generation tool (image"
             f" edit of an attached image). Make {len(items)} edited images, one per item below.", "",
             attach_note(), f" Attachments after those {n_anchor} are the sprites to edit, in the"
             f" order of the items below.", "", "The style every sprite must keep:", style_block(), "",
             "Edits:"]
    for i, (s, cur, new, fix) in enumerate(items, 1):
        lines.append(f"{i}. {s['name']} (attachment {n_anchor + i}, file {s['name']}_{cur}.png):"
                     f" {s['subject']}. {colour_line(s)} FIX: {fix}. KEEP: {keep}")
    lines += ["", _copy_rule([(s["name"], new) for s, _, new, _ in items])]
    return "\n".join(lines)


def _copy_rule(pairs: list[tuple[str, str]]) -> str:
    dests = "; ".join(f"{n} -> {RAW / f'{n}_{t}.png'}" for n, t in pairs)
    return ("After each image is generated, copy its PNG file (unchanged: keep the alpha channel, do"
            " not resize, convert or edit it) to exactly this path: " + dests + ". Do not create or"
            " change any other file. When done, list the files you wrote.")


# ------------------------------------------------------------------------------------ codex runs

def attempts_of(name: str) -> list[str]:
    tags = [p.stem.rsplit("_", 1)[1] for p in RAW.glob(f"{name}_r*.png")]
    return sorted(tags, key=lambda t: int(t[1:]))


def run_session(session: str, prompt: str, extra_images: list[Path], expect: list[Path]) -> dict:
    RAW.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    exe = shutil.which("codex") or "codex"
    imgs = [KINDLEFOX] + [ROUND2 / f"{a}_color.png" for a in ANCHORS] + list(extra_images)
    cmd = [exe, "exec", "-m", MODEL, "-c", 'model_reasoning_effort="high"', "--skip-git-repo-check",
           "-C", str(ROOT), "-o", str(LOGS / f"{session}.last.txt")]
    for p in imgs:
        cmd += ["-i", str(p)]
    (LOGS / f"{session}.prompt.txt").write_text(prompt, encoding="utf-8")
    t0 = time.time()
    with open(LOGS / f"{session}.log", "w", encoding="utf-8", errors="replace") as log:
        proc = subprocess.run(cmd, input=prompt, text=True, encoding="utf-8", stdout=log,
                              stderr=subprocess.STDOUT, cwd=str(ROOT), shell=exe.lower().endswith((".cmd", ".bat")))
    secs = round(time.time() - t0, 1)
    got = [p.name for p in expect if p.exists() and p.stat().st_mtime >= t0 - 1]
    row = {"session": session, "model": MODEL, "seconds": secs, "exit": proc.returncode,
           "expected": [p.name for p in expect], "images": got, "images_n": len(got),
           "start": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(t0))}
    with RUNS.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row) + "\n")
    print(f"[{session}] exit {proc.returncode} {secs}s images {len(got)}/{len(expect)}", flush=True)
    return row


def _parallel(jobs, parallel: int):
    with ThreadPoolExecutor(max_workers=parallel) as ex:
        return list(ex.map(lambda j: run_session(*j), jobs))


def cmd_gen(a):
    spec = load_spec()
    codex = [n for n, s in spec.items() if s["source"] == "codex"]
    names = a.names.split(",") if a.names else [n for n in codex if not attempts_of(n)]
    bad = [n for n in names if n not in codex]
    if bad:
        sys.exit(f"not Codex rows in SPRITES.md: {bad}")
    if not names:
        print("nothing to generate")
        return
    jobs, stamp = [], time.strftime("%H%M%S")
    for bi in range(0, len(names), a.batch):
        chunk = [spec[n] for n in names[bi:bi + a.batch]]
        items, expect = [], []
        # every sprite in a gen session gets its own next tag (r1 for new ones)
        by_tag: dict[str, list[dict]] = {}
        for s in chunk:
            by_tag.setdefault(f"r{len(attempts_of(s['name'])) + 1}", []).append(s)
        for tag, group in by_tag.items():
            items = group
            expect = [RAW / f"{s['name']}_{tag}.png" for s in group]
            jobs.append((f"gen{stamp}_{bi // a.batch}_{tag}", gen_prompt(items, tag), [], expect))
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
        if spec.get(n, {}).get("source") != "codex":
            sys.exit(f"{n} is not a Codex row")
        cur = picks.get(n) or attempts_of(n)[-1]
        new = f"r{len(attempts_of(n)) + 1}"
        fixes.append((spec[n], cur, new, txt.strip().rstrip(".")))
    keep = a.keep or ("everything else exactly as it is: the shape, pose, proportions, colours,"
                      " outline, highlight and transparent background")
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


def glow_image() -> Image.Image:
    import procedural as pr
    L, A = pr.sprite_glow()
    rgb, al = pr.downsample(pr.ramp(L, pr.RAMPS["glow"]), A)
    return pr.to_image(rgb, al)


def _round2_attempts(name: str) -> int:
    try:
        src = json.loads((ROUND2 / "result.json").read_text())["picked_from"][name]["from"]
        return int(src.split("_")[0][1:])
    except Exception:
        return 1


def cmd_build(a):
    spec, picks = load_spec(), _load_picks()
    if a.pick:
        for tok in a.pick.split(","):
            n, t = tok.split("=")
            picks[n] = t
        PICKS.write_text(json.dumps(picks, indent=1))
    OUT.mkdir(parents=True, exist_ok=True)
    manifest, missing, build = [], [], {}
    for n, s in spec.items():
        grey_name = f"{n}_grey.png" if s["tint"] else None
        if s["source"] == "carried":
            shutil.copyfile(ROUND2 / s["from"].replace("gpt-cartoon/", ""), OUT / f"{n}.png")
            if grey_name:
                shutil.copyfile(ROUND2 / f"{n}.png", OUT / grey_name)
            src, att, info = "codex", _round2_attempts(n), {"from": "bakeoff/gpt-cartoon (round 2)"}
        elif s["source"] == "procedural":
            img = glow_image()
            img.save(OUT / f"{n}.png")
            if grey_name:
                img.save(OUT / grey_name)
            src, att, info = "procedural", 1, {"from": "tools/vfx/procedural.py"}
        else:
            tags = attempts_of(n)
            if not tags:
                missing.append(n)
                continue
            tag = picks.get(n, tags[-1])
            framed = gs.frame(gc.load_color(RAW / f"{n}_{tag}.png"))
            gc.bleed(framed).save(OUT / f"{n}.png")
            info = {"from": f"raw/{n}_{tag}.png"}
            if grey_name and s["white"]:
                shutil.copyfile(OUT / f"{n}.png", OUT / grey_name)
            elif grey_name:
                g, ti = gc.to_grey_tones(framed)
                gc.bleed(g).save(OUT / grey_name)
                info.update(ti)
            src, att = "codex", len(tags)
        manifest.append({"name": n, "file": f"{n}.png", "grey": grey_name, "tint": s["tint"],
                         "source": src, "attempts": att})
        build[n] = info
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    (RAW / "build.json").write_text(json.dumps(build, indent=1), encoding="utf-8")  # provenance + tones
    contact([m for m in manifest], OUT / "contact.png")
    print(f"built {len(manifest)} sprites -> {OUT}")
    if missing:
        print("missing raw (run gen):", ", ".join(missing))


def contact(manifest: list[dict], out: Path, per_row: int = 11) -> None:
    cell, pad, lab = 128, 8, 14
    chunks = [manifest[i:i + per_row] for i in range(0, len(manifest), per_row)]
    band_h = lab + 2 * (cell + pad) + 56 + pad
    W = pad + per_row * (cell + pad)
    H = 2 * len(chunks) * band_h
    sheet = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    y0 = 0
    for bg, ink in (("#22202B", (230, 230, 230, 255)), ("#EAF0E2", (40, 40, 40, 255))):
        for ch in chunks:
            band = Image.new("RGBA", (W, band_h), bg)
            d = ImageDraw.Draw(band)
            for ci, m in enumerate(ch):
                x = pad + ci * (cell + pad)
                d.text((x, 2), m["name"] + (" T" if m["tint"] else ""), fill=ink)
                col = Image.open(OUT / m["file"]).convert("RGBA")
                band.alpha_composite(col.resize((cell, cell), Image.LANCZOS), (x, lab))
                if m["grey"]:
                    g = Image.open(OUT / m["grey"]).convert("RGBA")
                    band.alpha_composite(g.resize((cell, cell), Image.LANCZOS), (x, lab + cell + pad))
                y = lab + 2 * (cell + pad)
                band.alpha_composite(col.resize((48, 48), Image.LANCZOS), (x + 4, y))
                band.alpha_composite(col.resize((24, 24), Image.LANCZOS), (x + 64, y + 12))
                if m["grey"]:
                    band.alpha_composite(g.resize((24, 24), Image.LANCZOS), (x + 96, y + 12))
            sheet.paste(band, (0, y0))
            y0 += band_h
    sheet.convert("RGB").save(out)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
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
        {"gen": cmd_gen, "fix": cmd_fix, "build": cmd_build, "prompt": cmd_prompt}[a.cmd](a)


if __name__ == "__main__":
    main()
