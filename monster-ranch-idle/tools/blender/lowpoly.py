"""Low-poly LOD meshes for Low graphics and crowd-capped fights (R2-LOWQ): decimates each form's
already-rigged, already-baked model (art/rigs/<form>/rig.blend, read-only) to a cheap triangle
budget, keeping its skin weights and bone names so the SAME MeshMonsters/<form> rig module and clips
(idle, walk, hop, ...) still drive it, and the SAME published texture (its UVs survive the decimate,
so no re-bake, no new upload: MeshMonsterAssets.<form>.lowMesh reuses .texture).

  python tools/blender/lowpoly.py FORM[,FORM...] [--out DIR] [--tris N]

--out defaults to a scratch directory outside the repo (see OUT below); this step never writes into
art/ (read-only source) and never uploads anything. What is left, from Studio, once the lead is ready
to publish a batch: publish_meshes.luau on OUT/<form>/mesh.json like a full mesh, with suffix = "low"
in its arguments, then asset_ids.py --json with lowMesh ids to record them (all 271 published this
way 2026-09-27).

Target triangles: 1,500. The full models this pipeline already ships run 6,000-10,600 triangles
(art/rigs/*/mesh.json); 1,500 is roughly a 4-7x cut, the usual size for a background/crowd LOD, and
keeps a full 40-monster raid under 60,000 triangles instead of a quarter million. Run
lowpoly_export.py's Decimate (Collapse, applied to a duplicate; rig.blend itself is never saved) below
that floor and small forms lose their silhouette (ears, wings, stingers), so --tris can raise it for a
form that reads badly; there is no per-form override file yet.

  python tools/blender/lowpoly.py --all      # every form already published (MeshMonsterAssets.luau),
                                              # one Blender process each (~10-20 s apiece)
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools" / "blender"
BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")
# The rigged sources live in the main checkout's art/ (read-only; a worktree's own art/ has no
# rigs/). Hardcoded like pipeline.py's own BLENDER/STYLUA paths, for the same reason: this tool runs
# from whatever worktree, but art/rigs does not.
MAIN_ART = Path(r"C:\Users\sim\Documents\monster ranch\monster-ranch-idle\art")
RIGS = ROOT / "art" / "rigs" if (ROOT / "art" / "rigs").is_dir() else MAIN_ART / "rigs"
DEFAULT_OUT = Path(r"C:\Users\sim\AppData\Local\Temp\claude\C--Users-sim-Desktop-claude\fbd1627e-c44a-4365-a5c9-c053ed02dcd9\scratchpad\r2\lowq")
ASSETS = ROOT / "src" / "client" / "Visuals" / "MeshMonsterAssets.luau"
TARGET_TRIS = 1500


def published_forms() -> list:
    """Every form with both ids already set (MeshMonsterAssets.luau), for --all."""
    import re

    forms = []
    for line in ASSETS.read_text(encoding="utf-8").splitlines():
        m = re.match(r'^\t(\w+) = \{ mesh = "([^"]+)", texture = "([^"]+)"', line)
        if m:
            forms.append(m.group(1))
    return forms


def run(form: str, out: Path, target: int) -> None:
    rig = RIGS / form / "rig.blend"
    if not rig.exists():
        raise SystemExit(f"{form}: no rig at {rig}")
    result = subprocess.run(
        [str(BLENDER), "-b", str(rig), "--python", str(HERE / "lowpoly_export.py"), "--", form, str(out), str(target)],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    lines = [line for line in result.stdout.splitlines() if line.startswith("[lowpoly]")]
    if result.returncode != 0 or not lines:
        raise SystemExit(f"{form}: lowpoly export failed\n" + result.stdout[-3000:] + result.stderr[-3000:])
    print(lines[0], flush=True)


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    flags = sys.argv[2:]
    out = Path(flags[flags.index("--out") + 1]) if "--out" in flags else DEFAULT_OUT
    target = int(flags[flags.index("--tris") + 1]) if "--tris" in flags else TARGET_TRIS
    forms = published_forms() if sys.argv[1] == "--all" else [f for f in sys.argv[1].split(",") if f]
    out.mkdir(parents=True, exist_ok=True)
    for form in forms:
        run(form, out, target)


if __name__ == "__main__":
    main()
