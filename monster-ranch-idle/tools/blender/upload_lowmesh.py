"""Uploads low-poly monster meshes (tools/blender/lowpoly.py --fbx output) from the BURNER account
through Open Cloud, and records each form's mesh id. The owner's rule (2026-09-27): every upload goes
through the burner gravelxpixel, never Studio's signed-in main account, so publish_meshes.luau is not
used for these.

  python tools/blender/upload_lowmesh.py FORM[,FORM...] [--out DIR] [--limit N]
  python tools/blender/upload_lowmesh.py --all [--out DIR] [--limit N]    # every <out>/<form>/mesh.fbx

Each form: POST <form>/mesh.fbx as a "Model" asset (creator: the burner), wait for the operation,
download the model (asset delivery, same key), save it as <form>/model.rbxm and read its MeshPart with
lowmesh_inspect.luau: the mesh id (MeshContent) is the low mesh, and its size and bone names are checked against
<form>/mesh.json (the frame and bones the MeshMonsters/<form> rig module uses). The ledger
<out>/uploads.json keeps { form: { model, mesh, meshSize, bones, ok, problem } }; a form already in it
is skipped, so a stopped batch resumes. Nothing is written into the repo: record the ids afterwards with

  python tools/blender/upload_lowmesh.py --record [--out DIR]     # asset_ids.py lowMesh=, ok forms only

The burner's assets start private. The owner makes each MESH id Open Use in the Creator Hub (or grants
the game's universe) before the main account's game can load it.

The key is the burner's Open Cloud key, DPAPI-encrypted at ~/.roblox/burner-opencloud.key. It is
decrypted into this process only and never printed or logged.
"""

import base64
import json
import os
import re
import struct
import subprocess
import sys
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools" / "blender"
DEFAULT_OUT = Path(
    r"C:\Users\sim\AppData\Local\Temp\claude\C--Users-sim-Desktop-claude\fbd1627e-c44a-4365-a5c9-c053ed02dcd9\scratchpad\lowmesh"
)
BURNER_USER_ID = "11034262240"  # gravelxpixel
KEY_FILE = Path.home() / ".roblox" / "burner-opencloud.key"
ASSETS_URL = "https://apis.roblox.com/assets/v1/assets"
OPERATIONS_URL = "https://apis.roblox.com/assets/v1/"
DELIVERY_URL = "https://apis.roblox.com/asset-delivery-api/v1/assetId/"
SIZE_TOLERANCE = 0.02  # studs: the import may round the bounding box a little


def burner_key() -> str:
    if not KEY_FILE.exists():
        raise SystemExit(f"no burner key at {KEY_FILE}")
    ps = "[Net.NetworkCredential]::new('', (Get-Content '%s' | ConvertTo-SecureString)).Password" % str(KEY_FILE).replace("'", "''")
    out = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", ps], capture_output=True, text=True)
    key = out.stdout.strip()
    if not key:
        raise SystemExit("could not decrypt the burner key")
    return key


def expected(form_dir: Path):
    """mesh.json's bounding box size (studs, the rig module's frame) and bone names."""
    m = json.loads((form_dir / "mesh.json").read_text(encoding="utf-8"))
    raw = base64.b64decode(m["positions"])
    p = struct.unpack("<%df" % (len(raw) // 4), raw)
    size = [max(p[i::3]) - min(p[i::3]) for i in range(3)]
    return size, [b["name"] for b in m["bones"]]


def request(method: str, url: str, key: str, **kwargs):
    """Retries rate limits and transient 5xx with backoff; returns the final response."""
    for attempt in range(8):
        r = requests.request(method, url, headers={"x-api-key": key}, timeout=60, **kwargs)
        if r.status_code == 429 or r.status_code >= 500:
            wait = float(r.headers.get("retry-after") or 0) or min(60, 5 * 2**attempt)
            print(f"  {r.status_code}, waiting {wait:.0f} s", flush=True)
            time.sleep(wait)
            continue
        return r
    return r


def upload(form: str, fbx: Path, key: str) -> str:
    body = {
        "assetType": "Model",
        "displayName": f"MRI lowmesh {form}",
        "description": "Monster Ranch Idle low-poly monster mesh",
        "creationContext": {"creator": {"userId": BURNER_USER_ID}, "expectedPrice": 0},
    }
    with fbx.open("rb") as f:
        files = {"request": (None, json.dumps(body), "application/json"), "fileContent": (fbx.name, f, "model/fbx")}
        r = request("POST", ASSETS_URL, key, files=files)
    if r.status_code != 200:
        raise RuntimeError(f"upload {r.status_code}: {r.text[:300]}")
    path = r.json().get("path") or ""
    for _ in range(90):
        time.sleep(2)
        op = request("GET", OPERATIONS_URL + path, key)
        if op.status_code != 200:
            raise RuntimeError(f"operation {op.status_code}: {op.text[:300]}")
        info = op.json()
        if info.get("done"):
            if "error" in info:
                raise RuntimeError(f"processing: {json.dumps(info['error'])[:300]}")
            return str(info["response"]["assetId"])
    raise RuntimeError("operation timed out")


def download(model_id: str, key: str, dest: Path) -> None:
    for _ in range(30):
        r = request("GET", DELIVERY_URL + model_id, key)
        location = r.json().get("location") if r.status_code == 200 else None
        if location:
            body = requests.get(location, timeout=60)
            if body.status_code == 200 and body.content:
                dest.write_bytes(body.content)
                return
        time.sleep(4)
    raise RuntimeError(f"could not download model {model_id}")


def inspect(rbxm: Path) -> dict:
    out = subprocess.run(["lune", "run", str(HERE / "lowmesh_inspect.luau"), str(rbxm)], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError("inspect failed: " + (out.stderr or out.stdout)[-300:])
    return json.loads(out.stdout.strip().splitlines()[-1])


def check(form_dir: Path, parts: list) -> tuple:
    """(mesh id, meshSize, bones, problem or None)."""
    if len(parts) != 1:
        return None, None, None, f"{len(parts)} MeshParts in the model, expected 1"
    part = parts[0]
    mesh = re.search(r"(\d+)", part["meshId"])
    mesh = f"rbxassetid://{mesh.group(1)}" if mesh else None
    size, bones = expected(form_dir)
    problems = []
    if not mesh:
        problems.append("no mesh id")
    if any(abs(a - b) > SIZE_TOLERANCE + 0.02 * b for a, b in zip(part["meshSize"], size)):
        problems.append("size %s, expected %s" % ([round(v, 3) for v in part["meshSize"]], [round(v, 3) for v in size]))
    missing = sorted(set(bones) - set(part["bones"]))
    if missing:
        problems.append("bones missing: " + ", ".join(missing[:6]))
    return mesh, part["meshSize"], part["bones"], "; ".join(problems) or None


def record(out: Path) -> None:
    ledger = json.loads((out / "uploads.json").read_text(encoding="utf-8"))
    ids = {form: {"lowMesh": row["mesh"]} for form, row in ledger.items() if row.get("ok")}
    tmp = out / "record_ids.json"
    tmp.write_text(json.dumps(ids, indent=1), encoding="utf-8")
    subprocess.run([sys.executable, str(HERE / "asset_ids.py"), "--json", str(tmp)], check=True, cwd=ROOT)
    print(f"recorded {len(ids)} lowMesh ids; {len(ledger) - len(ids)} forms not ok")


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    flags = sys.argv[1:]
    out = Path(flags[flags.index("--out") + 1]) if "--out" in flags else DEFAULT_OUT
    if "--record" in flags:
        record(out)
        return
    limit = int(flags[flags.index("--limit") + 1]) if "--limit" in flags else None
    if flags[0] == "--all":
        forms = sorted(p.parent.name for p in out.glob("*/mesh.fbx"))
    else:
        forms = [f for f in flags[0].split(",") if f]
    ledger_path = out / "uploads.json"
    ledger = json.loads(ledger_path.read_text(encoding="utf-8")) if ledger_path.exists() else {}
    todo = [f for f in forms if f not in ledger]
    if limit is not None:
        todo = todo[:limit]
    key = burner_key()
    for form in todo:
        form_dir = out / form
        try:
            model_id = upload(form, form_dir / "mesh.fbx", key)
            (form_dir / "model_id.txt").write_text(model_id, encoding="utf-8")  # kept if a later step fails
            download(model_id, key, form_dir / "model.rbxm")
            mesh, size, bones, problem = check(form_dir, inspect(form_dir / "model.rbxm")["parts"])
            row = {"model": model_id, "mesh": mesh, "meshSize": size, "bones": len(bones or []), "ok": problem is None}
            if problem:
                row["problem"] = problem
        except Exception as e:  # keep going; the ledger says what failed
            row = {"ok": False, "problem": str(e)[:300]}
        ledger[form] = row
        ledger_path.write_text(json.dumps(ledger, indent=1, sort_keys=True), encoding="utf-8")
        print(f"{form}: {'ok' if row['ok'] else 'PROBLEM'} model={row.get('model')} mesh={row.get('mesh')}"
              + (f" ({row['problem']})" if not row["ok"] else ""), flush=True)
    done = sum(1 for r in ledger.values() if r.get("ok"))
    print(f"ledger: {done} ok, {len(ledger) - done} not ok, {len(ledger)} total")


if __name__ == "__main__":
    main()
