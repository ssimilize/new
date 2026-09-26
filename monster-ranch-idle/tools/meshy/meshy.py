"""Meshy API client for Monster Ranch art: concepts, models, textures, rigs.

The API key comes from the MESHY_API_KEY environment variable (on Windows, the user variable is
also read straight from the registry, so a key saved after the shell started still works). The
key is only ever sent in the Authorization header to api.meshy.ai: never printed, logged, saved
or forwarded to the signed download URLs.

Every task has a NAME, and its files live in art/meshy/<name>/:
  submission.json  what was sent (images as hashes, never the key) and Meshy's reply
  status.json      the last poll (holds signed download URLs: don't share it)
  <downloads>      model.glb, model.fbx, texture_*.png, image_*.png, thumbnail.png

`create` spends credits. It writes submission.json BEFORE posting and refuses a name that already
has one, so an uncertain reply can never turn into a second purchase: poll the name instead.
Every create and every finished task is appended to art/meshy/ledger.jsonl.

  python tools/meshy/meshy.py balance
  python tools/meshy/meshy.py create text-to-image barn-concept --settings '{"ai_model": "nano-banana", "prompt": "..."}'
  python tools/meshy/meshy.py create image-to-3d barn --link input_task_id=barn-concept --settings '{...}'
  python tools/meshy/meshy.py create image-to-3d egg --image image_url=art/ref/egg.png --settings '{...}'
  python tools/meshy/meshy.py create multi-image-to-3d fox --images image_urls=a.png,b.png,c.png --settings '{...}'
  python tools/meshy/meshy.py poll barn --wait
  python tools/meshy/meshy.py download barn
  python tools/meshy/meshy.py list

Settings may also be read from a file: --settings @path/to/settings.json
"""

import argparse
import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art" / "meshy"
API = "https://api.meshy.ai/openapi/"

# Task kind -> API version. Text to 3D moved to v2; everything else is v1.
KINDS = {
    "text-to-3d": "v2",
    "text-to-image": "v1",
    "image-to-image": "v1",
    "image-to-3d": "v1",
    "multi-image-to-3d": "v1",
    "retexture": "v1",
    "remesh": "v1",
    "rigging": "v1",
    "animations": "v1",
}
TERMINAL = ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED")


def api_key() -> str:
    key = os.environ.get("MESHY_API_KEY", "").strip()
    if not key and sys.platform == "win32":
        import winreg

        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as reg:
                key = str(winreg.QueryValueEx(reg, "MESHY_API_KEY")[0]).strip()
        except OSError:
            pass
    if not key:
        raise SystemExit("MESHY_API_KEY is not set. See tools/meshy/README.md.")
    return key


def call(method: str, path: str, payload=None) -> dict:
    body = None if payload is None else json.dumps(payload).encode()
    request = urllib.request.Request(
        API + path,
        data=body,
        method=method,
        headers={"Authorization": "Bearer " + api_key(), "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        try:
            detail = json.loads(exc.read().decode())
        except Exception:
            detail = {"message": "non-JSON error body"}
        return {"http_error": exc.code, "detail": detail}


def folder(name: str) -> Path:
    if not name or any(c in name for c in '\\/:*?"<>|') or name.startswith("."):
        raise SystemExit(f"bad task name: {name!r}")
    return OUT / name


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def ledger(entry: dict) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    entry = {"at": datetime.now(timezone.utc).isoformat(timespec="seconds"), **entry}
    with (OUT / "ledger.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")


def submission(name: str) -> dict:
    path = folder(name) / "submission.json"
    if not path.exists():
        raise SystemExit(f"no task named {name!r}")
    return read(path)


def task_id(name: str) -> str:
    sub = submission(name)
    tid = (sub.get("response") or {}).get("result")
    if not tid:
        raise SystemExit(f"{name!r} has no task id (state {sub.get('state')}); nothing to poll")
    return tid


def data_uri(path: Path) -> str:
    mime = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}.get(path.suffix.lower())
    if not mime:
        raise SystemExit(f"{path}: only png and jpg images can be sent")
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode()


# ─── commands ──────────────────────────────────────────────────────────────────────────


def cmd_balance(_args) -> dict:
    return call("GET", "v1/balance")


def cmd_create(args) -> dict:
    if args.kind not in KINDS:
        raise SystemExit(f"unknown kind {args.kind!r}; one of {', '.join(KINDS)}")
    record = folder(args.name) / "submission.json"
    if record.exists():
        # A 4xx reply is a definite refusal (no task, no charge: e.g. 429 NoMorePendingTasks when the
        # plan's 10 pending tasks are taken), so that name may be tried again. Anything else may have
        # created a task.
        previous = read(record)
        refused = previous.get("state") == "ERROR" and 400 <= int((previous.get("response") or {}).get("http_error") or 0) < 500
        if not refused:
            return {"refused": f"{args.name!r} was already submitted; poll it instead of creating it again"}
        ledger({"event": "retry", "name": args.name, "after": previous["response"].get("http_error")})
    text = args.settings
    if text.startswith("@"):
        text = Path(text[1:]).read_text(encoding="utf-8")
    payload = json.loads(text)
    audit = {"kind": args.kind, "settings": dict(payload), "links": {}, "images": {}}
    for link in args.link:
        field, _, other = link.partition("=")
        payload[field] = task_id(other)
        audit["links"][field] = {"task": other, "id": payload[field]}
    for image in args.image:
        field, _, file = image.partition("=")
        path = (ROOT / file).resolve() if not Path(file).is_absolute() else Path(file)
        payload[field] = data_uri(path)
        audit["images"][field] = {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    for images in args.images:
        field, _, files = images.partition("=")
        paths = [(ROOT / f).resolve() if not Path(f).is_absolute() else Path(f) for f in files.split(",")]
        payload[field] = [data_uri(path) for path in paths]
        audit["images"][field] = [{"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in paths]
    # Recorded before the POST: an ambiguous failure must never lead to a second purchase.
    write(record, {"state": "ATTEMPTING", "request": audit})
    result = call("POST", f"{KINDS[args.kind]}/{args.kind}", payload)
    state = "SUBMITTED" if "result" in result else "ERROR"
    write(record, {"state": state, "request": audit, "response": result})
    ledger({"event": "create", "name": args.name, "kind": args.kind, "state": state, "id": result.get("result")})
    return {"name": args.name, "state": state, **result}


def summary(task: dict) -> dict:
    keep = ("id", "status", "progress", "consumed_credits", "task_error", "http_error", "detail")
    return {k: task[k] for k in keep if k in task}


def cmd_poll(args) -> dict:
    sub = submission(args.name)
    kind, tid = sub["request"]["kind"], task_id(args.name)
    deadline = time.time() + args.timeout
    while True:
        task = call("GET", f"{KINDS[kind]}/{kind}/{tid}")
        write(folder(args.name) / "status.json", task)
        status = task.get("status")
        if not args.wait or status in TERMINAL or "http_error" in task or time.time() > deadline:
            break
        time.sleep(10)
    if status in TERMINAL and not sub.get("finished"):
        sub["finished"] = status
        write(folder(args.name) / "submission.json", sub)
        ledger({"event": "finished", "name": args.name, "status": status, "credits": task.get("consumed_credits")})
    return summary(task)


def download(url: str, dest: Path) -> dict:
    # Signed artifact URLs: fetched without any credential.
    if urlsplit(url).scheme != "https":
        raise SystemExit("artifact URL is not https")
    with urllib.request.urlopen(url, timeout=300) as response, dest.open("wb") as f:
        while chunk := response.read(1 << 20):
            f.write(chunk)
    data = dest.read_bytes()
    return {"file": dest.name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def cmd_download(args) -> dict:
    here = folder(args.name)
    task = read(here / "status.json")
    if task.get("status") != "SUCCEEDED":
        raise SystemExit(f"{args.name!r} is {task.get('status')}; poll it until SUCCEEDED")
    wanted = []
    for fmt, url in (task.get("model_urls") or {}).items():
        if url and fmt in ("glb", "fbx", "obj", "mtl", "pre_remeshed_glb"):
            wanted.append((f"model.{fmt}" if fmt != "pre_remeshed_glb" else "model_pre_remesh.glb", url))
    for i, texture in enumerate(task.get("texture_urls") or []):
        for channel, url in texture.items():
            if url:
                wanted.append((f"texture_{i}_{channel}.png", url))
    for i, url in enumerate(task.get("image_urls") or []):
        wanted.append((f"image_{i}.png", url))
    if task.get("thumbnail_url"):
        wanted.append(("thumbnail.png", task["thumbnail_url"]))

    # Rigging and animation results nest their files.
    def visit(result, prefix=""):
        for label, value in (result or {}).items():
            if isinstance(value, dict):
                visit(value, prefix + label + "_")
            elif isinstance(value, str) and value.startswith("https://"):
                suffix = Path(urlsplit(value).path).suffix.lower()
                if suffix in (".glb", ".fbx", ".png"):
                    wanted.append((prefix + label + suffix, value))

    visit(task.get("result"))
    files = [download(url, here / file) for file, url in wanted]
    write(here / "downloads.json", files)
    return {"name": args.name, "files": files}


def cmd_list(_args) -> dict:
    rows = []
    for path in sorted(OUT.glob("*/submission.json")):
        sub = read(path)
        status = path.parent / "status.json"
        task = read(status) if status.exists() else {}
        rows.append(
            {
                "name": path.parent.name,
                "kind": sub["request"]["kind"],
                "state": sub.get("state"),
                "status": task.get("status"),
                "credits": task.get("consumed_credits"),
            }
        )
    return {"tasks": rows}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("balance")
    create = sub.add_parser("create")
    create.add_argument("kind")
    create.add_argument("name")
    create.add_argument("--settings", required=True, help="JSON body, or @file")
    create.add_argument("--link", action="append", default=[], help="FIELD=NAME: another task's id")
    create.add_argument("--image", action="append", default=[], help="FIELD=PATH: a local png/jpg as a data URI")
    create.add_argument("--images", action="append", default=[], help="FIELD=PATH,PATH,...: a list of data URIs")
    poll = sub.add_parser("poll")
    poll.add_argument("name")
    poll.add_argument("--wait", action="store_true")
    poll.add_argument("--timeout", type=int, default=900)
    sub.add_parser("download").add_argument("name")
    sub.add_parser("list")
    args = parser.parse_args()
    handler = {
        "balance": cmd_balance,
        "create": cmd_create,
        "poll": cmd_poll,
        "download": cmd_download,
        "list": cmd_list,
    }[args.command]
    print(json.dumps(handler(args), indent=2))


if __name__ == "__main__":
    main()
