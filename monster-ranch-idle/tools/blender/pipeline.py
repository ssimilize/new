"""Takes Meshy models into the game: rig (by body type) -> bake -> export -> stylua.

  python tools/blender/pipeline.py FORM[,FORM...] [--previews] [--source rbxgen] [--as NAME]

--source rbxgen takes the form's model from Roblox's own generator (art/rbxgen/<form>/model.glb,
tools/rbxgen) instead of Meshy. --as NAME (one form) writes the result under another name, so a
trial version stands beside the form in the game's data without replacing it.

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


def run(form: str, kind: str, previews: bool, source: str = "meshy", name: str | None = None) -> None:
    script = RIGS.get(kind)
    if script is None:
        raise SystemExit(f"{form}: no rig script for the {kind} body type")
    model = ROOT / "art" / "rbxgen" / form / "model.glb" if source == "rbxgen" else ROOT / "art" / "meshy" / f"{form}-model" / "model.glb"
    form = name or form
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
    # Roblox's generator already hands over a 1024 px atlas with every gap between its islands
    # filled (what bake_texture.py makes out of Meshy's 4096 px one); re-baking it onto new UVs at the
    # same size kept only 57-66% of its texels (2026-09-25), so its own texture goes out as it is.
    bake = "[bake] kept Roblox's own 1024 px atlas" if source == "rbxgen" else blender(str(rig_dir / "rig.blend"), "--python", str(HERE / "bake_texture.py"))
    export = blender(str(rig_dir / "rig.blend"), "--python", str(HERE / "export_roblox.py"), "--", form, str(MODULES), str(ROOT / "art" / "export"))
    subprocess.run([str(STYLUA), str(MODULES / f"{form}.luau")], check=True)
    summary = [line for line in (rig + "\n" + bake + "\n" + export).splitlines() if line.startswith(("[rig] landmarks", "[rig] skeleton", "[rig] game scale", "[rig] skin: WARNING", "[bake]", "[export]"))]
    print(f"== {form} ({kind})\n" + "\n".join(summary), flush=True)


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    flags = sys.argv[2:]
    source = flags[flags.index("--source") + 1] if "--source" in flags else "meshy"
    name = flags[flags.index("--as") + 1] if "--as" in flags else None
    if source not in ("meshy", "rbxgen"):
        raise SystemExit(f"unknown source {source}: meshy or rbxgen")
    kinds = archetypes()
    forms = [f for f in sys.argv[1].split(",") if f]
    unknown = [f for f in forms if f not in kinds]
    if unknown:
        raise SystemExit(f"not in the roster: {', '.join(unknown)}")
    if name and len(forms) > 1:
        raise SystemExit("--as names one form's result: give one form")
    for form in forms:
        run(form, kinds[form], "--previews" in flags, source, name)


if __name__ == "__main__":
    main()
