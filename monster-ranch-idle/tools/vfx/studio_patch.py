"""Bundle changed source files for a targeted import into the open Studio place.

    python tools/vfx/studio_patch.py <out.json> <file> [<file> ...]

Each file (a path under src/, per default.project.json) becomes
{ path = {"ReplicatedStorage","Shared","Config","Vfx"}, class, source, head } where `head` is the
file's git HEAD content (null for a new file), so the Luau side can refuse to overwrite a script whose
Studio Source has drifted from HEAD (someone else's edit). Serve the JSON over localhost and apply it
with an execute_luau call (see art/vfx/SYSTEM_PACKET.md verification notes).
"""
import json
import subprocess
import sys
from pathlib import Path

ROOTS = {
    "src/shared": ["ReplicatedStorage", "Shared"],
    "src/server": ["ServerScriptService", "Server"],
    "src/client": ["StarterPlayer", "StarterPlayerScripts", "Client"],
}


def entry(file: str) -> dict:
    rel = Path(file).as_posix()
    for prefix, root in ROOTS.items():
        if rel.startswith(prefix + "/"):
            parts = rel[len(prefix) + 1 :].split("/")
            break
    else:
        raise SystemExit(f"not under src/: {file}")
    name = parts[-1]
    cls = "ModuleScript"
    for suffix, c in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")):
        if name.endswith(suffix):
            name, cls = name[: -len(suffix)], c
            break
    path = root + parts[:-1] + ([] if name == "init" else [name])
    head = subprocess.run(["git", "show", f"HEAD:{rel}"], capture_output=True, text=True, encoding="utf-8")
    return {
        "path": path,
        "class": cls,
        "source": Path(file).read_text(encoding="utf-8"),
        "head": head.stdout if head.returncode == 0 else None,
    }


if __name__ == "__main__":
    out = [entry(f) for f in sys.argv[2:]]
    Path(sys.argv[1]).write_text(json.dumps(out), encoding="utf-8")
    print(len(out), "files", sum(len(e["source"]) for e in out), "bytes")
