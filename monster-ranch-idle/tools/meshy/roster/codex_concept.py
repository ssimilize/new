"""Draws a roster concept with the Codex image tool instead of Meshy's paid text/image-to-image.

batch.py `run ... --codex` calls draw() for each concept. The picture lands where a Meshy concept
would (art/meshy/<name>/image_0.png, 1024x1024 RGB on the flat grey backdrop) with a SUCCEEDED
status.json and a submission.json marked "codex", so the rest of batch.py (check, matte, sheet,
image-to-3d) treats it like any other concept and never asks Meshy about it.

The driver is codexgen's fast driver (codexgen-kit/tools/codexgen/gen.py): one read-only
`codex exec` per picture that calls image_gen exactly once; the PNG is taken from the run's own
session folder. Slots are shared machine-wide with every codexgen run (~/.codexgen/slots).
"""

from __future__ import annotations

import json
import os
import re
import socket
import subprocess
import time
from pathlib import Path

from PIL import Image

MODEL = os.environ.get("CODEX_CONCEPT_MODEL") or "gpt-6-luna"
EFFORT = os.environ.get("CODEX_CONCEPT_EFFORT") or "max"
TIMEOUT = 12 * 60
SIZE = 1024
CODEX_IMAGES = Path.home() / ".codex" / "generated_images"
SLOTS_DIR = Path(os.environ.get("CODEXGEN_SLOTS_DIR") or Path.home() / ".codexgen" / "slots")
MAX_SLOTS = max(1, int(os.environ.get("CODEXGEN_SLOTS") or 60))
SLOT_STALE = 40 * 60

DRIVER = (
    "Call the image generation tool EXACTLY ONCE. Its prompt is the ART BRIEF below, passed on word for word. "
    "{refs}"
    "Do not read files, run shell commands, or inspect, verify, copy or edit the result, and never make a second "
    "image: the picture is saved automatically even if the tool output shows nothing. After the one call, reply DONE."
    "\n\nART BRIEF:\n\n"
)
# Image 1 labels. A style picture must say STYLE ONLY, or image_gen copies its creature into the result.
REF_STYLE = (
    "Include the attached image in the call, labelled in the prompt: 'Image 1: STYLE REFERENCE ONLY - copy its "
    "rendering (vinyl-toy material, soft even lighting, the flat grey background, framing and scale), never its "
    "creature, body or colours; draw only the creature the brief describes'. "
)
REF_PARENT = (
    "Include the attached image in the call, labelled in the prompt: 'Image 1: this creature's previous growth "
    "stage - keep its identity, colours, markings and rendering, and grow it as the brief describes'. "
)


def _alive(pid: int) -> bool:
    out = subprocess.run(f'tasklist /FI "PID eq {pid}" /NH', shell=True, capture_output=True, text=True).stdout
    return str(pid) in out


def _slot(label: str) -> Path:
    SLOTS_DIR.mkdir(parents=True, exist_ok=True)
    while True:
        for k in range(MAX_SLOTS):
            file = SLOTS_DIR / f"slot-{k}.lock"
            try:
                fd = os.open(file, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                os.write(fd, json.dumps({"pid": os.getpid(), "host": socket.gethostname(), "label": label, "t": time.time()}).encode())
                os.close(fd)
                return file
            except FileExistsError:
                try:
                    info = json.loads(file.read_text())
                except (OSError, ValueError):
                    continue
                stale = time.time() - info.get("t", 0) > SLOT_STALE or (
                    info.get("host") == socket.gethostname() and info.get("pid") != os.getpid() and not _alive(info["pid"])
                )
                if stale:
                    file.unlink(missing_ok=True)
        time.sleep(2)


def _square(path: Path) -> Image.Image:
    """Centre-crop to a square and scale to the 1024 px Meshy concepts use."""
    image = Image.open(path).convert("RGB")
    side = min(image.size)
    left, top = (image.width - side) // 2, (image.height - side) // 2
    image = image.crop((left, top, left + side, top + side))
    return image.resize((SIZE, SIZE), Image.LANCZOS) if side != SIZE else image


def draw(folder: Path, prompt: str, ref: Path | None, ref_role: str) -> str | None:
    """Draws one concept into `folder`. Returns None on success, else the reason it failed."""
    folder.mkdir(parents=True, exist_ok=True)
    refs = (REF_STYLE if ref_role == "style" else REF_PARENT) if ref else ""
    command = f"codex exec --ignore-user-config --skip-git-repo-check -m {MODEL} -c model_reasoning_effort={EFFORT} -s read-only"
    command += f' --image "{ref}" -- -' if ref else " -"
    submission = {"state": "CODEX", "model": MODEL, "effort": EFFORT, "ref": str(ref) if ref else None, "ref_role": ref_role, "prompt": prompt}
    (folder / "submission.json").write_text(json.dumps(submission, indent=2), encoding="utf-8")
    slot = _slot(f"monster-ranch:{folder.name}")
    try:
        result = subprocess.run(
            command, input=DRIVER.format(refs=refs) + prompt, cwd=folder, shell=True, capture_output=True,
            text=True, encoding="utf-8", errors="replace", timeout=TIMEOUT,
        )
        log = f"$ {command}\n\n{result.stdout}\n{result.stderr}"
    except subprocess.TimeoutExpired as timeout:
        partial = timeout.stdout or ""
        log = f"$ {command}\n\n{partial.decode('utf-8', 'replace') if isinstance(partial, bytes) else partial}\n[timed out after {TIMEOUT}s]"
    finally:
        slot.unlink(missing_ok=True)
    (folder / "codex.log").write_text(log, encoding="utf-8")
    match = re.search(r"session id: ([0-9a-f-]+)", log)
    if not match:
        reason = "Codex answered 401: run `codex login`" if ("401" in log or "Unauthorized" in log) else "no codex session id in the log"
        (folder / "status.json").write_text(json.dumps({"status": "FAILED", "reason": reason}), encoding="utf-8")
        return reason
    own = sorted((CODEX_IMAGES / match.group(1)).glob("*.png"), key=lambda f: f.stat().st_mtime)
    if not own:
        reason = f"session {match.group(1)} generated no image"
        (folder / "status.json").write_text(json.dumps({"status": "FAILED", "reason": reason}), encoding="utf-8")
        return reason
    _square(own[-1]).save(folder / "image_0.png")
    status = {"status": "SUCCEEDED", "source": "codex", "session": match.group(1), "generations": len(own)}
    (folder / "status.json").write_text(json.dumps(status, indent=2), encoding="utf-8")
    return None
