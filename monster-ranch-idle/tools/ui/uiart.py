"""Shared paths and helpers for the UI art tools in tools/ui (system Python + Pillow + numpy).

Not run directly. The big art sources (Meshy rigs, the Kindlefox concept) are git-ignored, so a
fresh worktree does not have them: `art_source()` looks in this checkout first, then in the main
checkout a `.claude/worktrees/<name>` worktree hangs off, then in $MRI_ART_ROOT.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # monster-ranch-idle
ART_UI = ROOT / "art" / "ui"
UPLOAD = ART_UI / "upload"  # every sheet the lead uploads, and nothing else
LUAU_ART = ROOT / "src" / "client" / "UI" / "Art"
INK = (0x1B, 0x1B, 0x1B)


def _art_roots() -> list[Path]:
    roots = [ROOT]
    parts = ROOT.parts  # <main>/.claude/worktrees/<name>/monster-ranch-idle -> <main>/monster-ranch-idle
    if "worktrees" in parts:
        i = parts.index("worktrees")
        if i >= 1 and parts[i - 1] == ".claude":
            roots.append(Path(*parts[: i - 1]) / ROOT.name)
    if os.environ.get("MRI_ART_ROOT"):
        roots.append(Path(os.environ["MRI_ART_ROOT"]))
    return roots


def art_source(rel: str) -> Path:
    """First existing <root>/<rel> (rel like 'art/rigs'); the local path if none exists."""
    for r in _art_roots():
        if (r / rel).exists():
            return r / rel
    return ROOT / rel


def config() -> dict:
    """forms / decor / themes / accessories / eggs / food, dumped by tools/ui/config_dump.luau."""
    exe = shutil.which("lune") or "lune"
    out = subprocess.run([exe, "run", "tools/ui/config_dump.luau"], cwd=str(ROOT), capture_output=True, text=True,
                         encoding="utf-8", check=True).stdout
    return json.loads(out)
