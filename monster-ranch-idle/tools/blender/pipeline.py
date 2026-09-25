"""Takes Meshy models into the game: rig (by body type) -> bake -> export -> stylua.

  python tools/blender/pipeline.py FORM[,FORM...] [--previews]

For each form: art/meshy/<form>-model/model.glb is rigged by its line's archetype's script into
art/rigs/<form>/, the texture is re-baked there (bake_texture.py), and the data module and 1024 px
textures are exported to src/client/Visuals/MeshMonsters/<form>.luau, art/rigs/<form>/mesh.json and
art/export/. --previews also renders the rig previews (slower). What is left, from Studio: upload
art/export/<form>.png with the Studio MCP's upload_image, publish mesh.json with
publish_meshes.luau, and record both ids (asset_ids.py). See README.md.

The archetype comes from tools/meshy/roster/roster.json (the game's Species lines).
"""

import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools" / "blender"
BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")
STYLUA = Path(r"C:\Users\sim\Documents\real idle rpg test\tools\bin\stylua.exe")
RIGS = {
    "fox": "rig_quadruped.py",
    "moth": "rig_moth.py",
    "slug": "rig_slug.py",
    "blob": "rig_blob.py",
    "sprite": "rig_sprite.py",
    "bunny": "rig_bunny.py",
    "golem": "rig_golem.py",
    "bug": "rig_bug.py",
}
MODULES = ROOT / "src" / "client" / "Visuals" / "MeshMonsters"


def archetypes() -> dict:
    roster = json.loads((ROOT / "tools" / "meshy" / "roster" / "roster.json").read_text(encoding="utf-8"))
    return {form["id"]: line["archetype"] for line in roster["lines"] for form in line["forms"]}


def blender(*args) -> str:
    result = subprocess.run([str(BLENDER), "-b", *args], capture_output=True, text=True, cwd=ROOT)
    lines = [line for line in result.stdout.splitlines() if line.startswith(("[rig]", "[bake]", "[export]", "[atlas]"))]
    if result.returncode != 0 or "Traceback" in result.stdout + result.stderr or "SystemExit" in result.stdout:
        raise SystemExit("\n".join(lines) + "\n" + result.stdout[-2000:] + result.stderr[-2000:])
    return "\n".join(lines)


def run(form: str, kind: str, previews: bool) -> None:
    script = RIGS.get(kind)
    if script is None:
        raise SystemExit(f"{form}: no rig script for the {kind} body type")
    model = ROOT / "art" / "meshy" / f"{form}-model" / "model.glb"
    rig_dir = ROOT / "art" / "rigs" / form
    if not model.exists():
        raise SystemExit(f"{form}: no model at {model}")
    started = time.time()
    rig = blender("--factory-startup", "--python", str(HERE / script), "--", str(model), str(rig_dir), *([] if previews else ["--no-preview"]))
    # A rig script that refuses a model (raise SystemExit) still leaves Blender exiting 0.
    if not (rig_dir / "rig.blend").exists() or (rig_dir / "rig.blend").stat().st_mtime < started:
        raise SystemExit(f"{form}: the {kind} rig did not finish\n{rig}")
    if previews:
        subprocess.run([sys.executable, str(HERE / "previews.py"), str(rig_dir)], capture_output=True, check=True)
    bake = blender(str(rig_dir / "rig.blend"), "--python", str(HERE / "bake_texture.py"))
    export = blender(str(rig_dir / "rig.blend"), "--python", str(HERE / "export_roblox.py"), "--", form, str(MODULES), str(ROOT / "art" / "export"))
    subprocess.run([str(STYLUA), str(MODULES / f"{form}.luau")], check=True)
    summary = [line for line in (rig + "\n" + bake + "\n" + export).splitlines() if line.startswith(("[rig] landmarks", "[rig] skeleton", "[rig] game scale", "[rig] skin: WARNING", "[bake]", "[export]"))]
    print(f"== {form} ({kind})\n" + "\n".join(summary), flush=True)


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    kinds = archetypes()
    forms = [f for f in sys.argv[1].split(",") if f]
    unknown = [f for f in forms if f not in kinds]
    if unknown:
        raise SystemExit(f"not in the roster: {', '.join(unknown)}")
    for form in forms:
        run(form, kinds[form], "--previews" in sys.argv[2:])


if __name__ == "__main__":
    main()
