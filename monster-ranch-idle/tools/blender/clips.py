"""Adds the extra clips (sleep, eat, cheer, cheer2, attack, hurt, faint, sit, trick) to forms already
in the game, with no re-rig and no re-publish: add_clips.py per form, in parallel, then stylua.

  python tools/blender/clips.py [FORM,FORM,...] [--check] [--previews [--only CLIP,...]] [--jobs N] [--rigs DIR]

No forms: every form in Visuals/MeshMonsterAssets.luau that has a MeshMonsters module. Each form's
art/rigs/<form>/rig.blend is opened read-only; its bones and old clips are proved byte-identical to
MeshMonsters/<form>.luau (a form that differs stops with an error and gets no clips module), then
MeshMonsterClips/<form>.luau is written. --check only proves. --previews also renders the new clips
to art/rigs-clips/<form>/ (preview_<clip>.gif, preview_<clip>_sheet.png side view,
preview_<clip>_front_sheet.png). --rigs: where the rigs are (default art/rigs, or the main
checkout's when this is a git worktree without them). The body type comes from the roster, as in
pipeline.py.
"""

import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pipeline import BLENDER, MODULES, RIGS, ROOT, STYLUA, archetypes  # noqa: E402

HERE = ROOT / "tools" / "blender"
CLIPS = MODULES.parent / "MeshMonsterClips"
PREVIEWS = ROOT / "art" / "rigs-clips"


def default_rigs() -> Path:
    rigs = ROOT / "art" / "rigs"
    if rigs.is_dir():
        return rigs
    # A git worktree has no art (it is git-ignored): use the main checkout's.
    common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, cwd=ROOT).stdout.strip()
    return Path(common).parent / ROOT.name / "art" / "rigs"


def game_forms() -> list:
    text = (MODULES.parent / "MeshMonsterAssets.luau").read_text(encoding="utf-8")
    return [f for f in re.findall(r"^\s+([a-z0-9]+) = \{ mesh", text, re.M) if (MODULES / f"{f}.luau").exists()]


def one(form: str, kind: str, rigs: Path, flags: list, only: str | None = None) -> tuple:
    blend = rigs / form / "rig.blend"
    if not blend.exists():
        return form, False, f"no rig at {blend}"
    args = [str(BLENDER), "-b", "--factory-startup", str(blend), "--python", str(HERE / "add_clips.py"), "--"]
    args += [form, RIGS[kind][:-3], str(MODULES), str(CLIPS)]
    if "--check" in flags:
        args.append("--check")
    if "--previews" in flags:
        args += ["--previews", str(PREVIEWS / form)] + (["--only", only] if only else [])
    result = subprocess.run(args, capture_output=True, text=True, cwd=ROOT)
    out = result.stdout + result.stderr
    lines = [line for line in out.splitlines() if line.startswith("[rig]")]
    failed = result.returncode != 0 or "Traceback" in out or "SystemExit" in out or "Error:" in out
    if not failed and "--check" not in flags and not (CLIPS / f"{form}.luau").exists():
        failed = True
    if failed:
        return form, False, "\n".join(lines) + "\n" + out[-1500:]
    if "--previews" in flags:
        subprocess.run([sys.executable, str(HERE / "previews.py"), str(PREVIEWS / form)], capture_output=True, check=True)
    return form, True, "\n".join(lines)


def main() -> None:
    flags, values, loose = [], {}, []
    args = iter(sys.argv[1:])
    for a in args:
        if a in ("--jobs", "--rigs", "--only"):
            values[a] = next(args)
        elif a.startswith("--"):
            flags.append(a)
        else:
            loose.append(a)
    jobs = int(values.get("--jobs", 6))
    rigs = Path(values["--rigs"]) if "--rigs" in values else default_rigs()
    forms = [f for f in ",".join(loose).split(",") if f] or game_forms()
    kinds = archetypes()
    unknown = [f for f in forms if f not in kinds]
    if unknown:
        raise SystemExit(f"not in the roster: {', '.join(unknown)}")
    started = time.time()
    with ThreadPoolExecutor(jobs) as pool:
        results = list(pool.map(lambda f: one(f, kinds[f], rigs, flags, values.get("--only")), forms))
    bad = [(f, why) for f, ok, why in results if not ok]
    good = [f for f, ok, _ in results if ok]
    if good and "--check" not in flags:
        subprocess.run([str(STYLUA), *[str(CLIPS / f"{f}.luau") for f in good]], check=True)
    for form, why in bad:
        print(f"== {form}: FAILED\n{why}", flush=True)
    sizes = sorted(((CLIPS / f"{f}.luau").stat().st_size, f) for f in good if (CLIPS / f"{f}.luau").exists())
    print(f"{len(good)} of {len(forms)} forms {'proved' if '--check' in flags else 'done'} in {time.time() - started:.0f} s"
          + (f"; largest clips module {sizes[-1][1]} at {sizes[-1][0]:,} bytes" if sizes else ""))
    if bad:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
