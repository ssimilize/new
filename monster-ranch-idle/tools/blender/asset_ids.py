"""Records a form's uploaded asset ids in src/client/Visuals/MeshMonsterAssets.luau.

  python tools/blender/asset_ids.py <form> [mesh=rbxassetid://N] [texture=rbxassetid://N]
  python tools/blender/asset_ids.py --json ids.json     # {"form": {"mesh": ..., "texture": ...}, ...}

The texture is art/export/<form>.png, uploaded with the Studio MCP's upload_image. The mesh is
published from Studio by publish_meshes.luau. MeshMonster builds a form only once it has both.

The ids live in their own module, not in the generated one, so re-exporting a rig never loses them.
Only the colour texture is used: a normal map drew creases on the runtime-built meshes the game
used at first (2026-09-25), and Meshy's roughness map alone looked the same as the plain texture.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "src" / "client" / "Visuals" / "MeshMonsterAssets.luau"
ID = re.compile(r"^rbxassetid://\d+$")
ENTRY = re.compile(r'^\t(\w+) = \{ mesh = "([^"]*)", texture = "([^"]*)" \},$')
HEADER = """--[[
	MeshMonsterAssets: the uploaded assets of each MeshMonsters form. Written by
	tools/blender/asset_ids.py; the mesh is published by tools/blender/publish_meshes.luau and the
	texture uploaded with the Studio MCP. MeshMonster builds a form only when both are set.
]]

return {
"""


def load() -> dict:
    ids = {}
    if ASSETS.exists():
        for line in ASSETS.read_text(encoding="utf-8").splitlines():
            m = ENTRY.match(line)
            if m:
                ids[m.group(1)] = {"mesh": m.group(2), "texture": m.group(3)}
    return ids


def save(ids: dict) -> None:
    lines = [f'\t{form} = {{ mesh = "{v.get("mesh", "")}", texture = "{v.get("texture", "")}" }},' for form, v in sorted(ids.items())]
    ASSETS.write_text(HEADER + "\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")


def main() -> None:
    ids = load()
    if len(sys.argv) == 3 and sys.argv[1] == "--json":
        updates = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    elif len(sys.argv) >= 3:
        updates = {sys.argv[1]: dict(arg.split("=", 1) for arg in sys.argv[2:])}
    else:
        raise SystemExit(__doc__)
    for form, values in updates.items():
        if not re.fullmatch(r"[a-z0-9]+", form):
            raise SystemExit(f"not a form id: {form}")
        for kind, value in values.items():
            if kind not in ("mesh", "texture") or not ID.match(value):
                raise SystemExit(f"{form}: bad {kind} {value!r}")
        ids.setdefault(form, {"mesh": "", "texture": ""}).update(values)
    save(ids)
    for form in updates:
        print(f"{form}: mesh {ids[form]['mesh'] or '-'}, texture {ids[form]['texture'] or '-'}")


if __name__ == "__main__":
    main()
