"""Turns what generate.luau posted from Studio into files the Blender tools read.

  python tools/rbxgen/assemble.py POSTED_DIR [KEY ...]

POSTED_DIR is receiver.py's folder of posts. Every post is one chunk of one part's mesh (JSON) or
texture (base64 RGBA, `tex<W>x<H>`); this joins the chunks and writes, per generation key:

  art/rbxgen/<key>/model.glb    every part as its own mesh node, placed where it sat in the model
                                (Roblox and glTF are both Y-up and right-handed, so positions go over
                                as they are; the generated models face +Z, glTF's front)
  art/rbxgen/<key>/<part>.png   the part's texture (1024 px: Roblox generates no larger), and
                                <part>.raw.png, the same as generated (colormatch.py reads it)
  art/rbxgen/<key>/<part>.npz   the part's mesh, so build() can remake model.glb after a texture edit
  art/rbxgen/<key>/meta.json    parts, vertex and triangle counts, sizes, and each part's published
                                {mesh, texture} ids when the job had publish = true

A key that was posted twice keeps its last post. With no KEY, every key in the folder.
"""

import base64
import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art" / "rbxgen"


def collect(posted: Path) -> dict:
    """{key: {part: {kind: text}}} from the chunk posts, in the order they arrived."""
    chunks: dict = {}
    for path in sorted(posted.glob("*.json")):
        try:
            post = json.loads(path.read_bytes())
        except ValueError:
            continue
        if not isinstance(post, dict) or "gen" not in post:
            continue
        slot = chunks.setdefault(post["gen"], {}).setdefault(post["part"], {})
        if post["i"] == 1:
            slot[post["kind"]] = [None] * post["n"]
        slot[post["kind"]][post["i"] - 1] = post["data"]
    out = {}
    for key, parts in chunks.items():
        for part, kinds in parts.items():
            for kind, pieces in kinds.items():
                if None in pieces:
                    print(f"{key}/{part}/{kind}: {pieces.count(None)} chunk(s) missing, skipped")
                    continue
                out.setdefault(key, {}).setdefault(part, {})[kind] = "".join(pieces)
    return out


def unshare(mesh: dict):
    """Roblox faces index positions, UVs and normals separately; glTF wants one index per corner, so
    every distinct (position, uv, normal) triple becomes a vertex."""
    pos = np.array(mesh["positions"], np.float32).reshape(-1, 3)
    uvs = np.array(mesh["uvs"], np.float32).reshape(-1, 2)
    nrm = np.array(mesh["normals"], np.float32).reshape(-1, 3)
    corners = np.stack([mesh["faces"], mesh["faceUVs"], mesh["faceNormals"]], axis=1)
    triples, index = np.unique(corners, axis=0, return_inverse=True)
    return pos[triples[:, 0]], uvs[triples[:, 1]], nrm[triples[:, 2]], index.reshape(-1).astype(np.uint32)


def glb(nodes: list) -> bytes:
    """A minimal GLB: one node per part (mesh + its own material with the embedded PNG)."""
    blob = bytearray()
    views, accessors, meshes, materials, textures, images, gltf_nodes = [], [], [], [], [], [], []

    def view(data: bytes, target=None) -> int:
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), **({"target": target} if target else {})})
        blob.extend(data)
        return len(views) - 1

    def accessor(array: np.ndarray, kind: str, target) -> int:
        entry = {"bufferView": view(array.tobytes(), target), "count": len(array), "type": kind}
        if array.dtype == np.uint32:
            entry["componentType"] = 5125
        else:
            entry["componentType"] = 5126
            if kind == "VEC3":
                entry["min"], entry["max"] = array.min(0).tolist(), array.max(0).tolist()
        accessors.append(entry)
        return len(accessors) - 1

    for node in nodes:
        pos, uv, nrm, index = node["arrays"]
        attrs = {"POSITION": accessor(pos, "VEC3", 34962), "NORMAL": accessor(nrm, "VEC3", 34962), "TEXCOORD_0": accessor(uv, "VEC2", 34962)}
        prim = {"attributes": attrs, "indices": accessor(index, "SCALAR", 34963)}
        if node.get("png"):
            images.append({"bufferView": view(node["png"]), "mimeType": "image/png"})
            textures.append({"source": len(images) - 1})
            materials.append({"name": node["name"], "pbrMetallicRoughness": {"baseColorTexture": {"index": len(textures) - 1}, "metallicFactor": 0.0, "roughnessFactor": 1.0}})
            prim["material"] = len(materials) - 1
        meshes.append({"name": node["name"], "primitives": [prim]})
        gltf_nodes.append({"name": node["name"], "mesh": len(meshes) - 1, "matrix": node["matrix"]})

    doc = {
        "asset": {"version": "2.0", "generator": "monster-ranch rbxgen/assemble.py"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(gltf_nodes)))}],
        "nodes": gltf_nodes,
        "meshes": meshes,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    if images:
        doc.update(images=images, textures=textures, materials=materials, samplers=[{}])
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    while len(blob) % 4:
        blob.append(0)
    body = struct.pack("<II", len(text), 0x4E4F534A) + text + struct.pack("<II", len(blob), 0x004E4942) + bytes(blob)
    return struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body


def matrix(cframe: list, scale: np.ndarray) -> list:
    """glTF's column-major 4x4 from a CFrame (x, y, z, R00..R22) and the part's mesh scale."""
    x, y, z, *r = cframe
    rot = np.array(r, np.float64).reshape(3, 3) * scale  # columns scaled: scale applies before rotation
    m = np.eye(4)
    m[:3, :3], m[:3, 3] = rot, (x, y, z)
    return m.T.reshape(-1).tolist()


def build(folder: Path) -> None:
    """model.glb from the folder's parts: <part>.npz (the mesh) and <part>.png (its texture as it is
    now, so a texture edited after assembling, e.g. by colormatch.py, goes into the model)."""
    meta = json.loads((folder / "meta.json").read_text())
    nodes = []
    for part in meta["parts"]:
        arrays = np.load(folder / f"{part['name']}.npz")
        node = {"name": part["name"], "arrays": (arrays["pos"], arrays["uv"], arrays["nrm"], arrays["index"]), "matrix": arrays["matrix"].tolist()}
        if (folder / f"{part['name']}.png").exists():
            png = io.BytesIO()
            Image.open(folder / f"{part['name']}.png").convert("RGB").save(png, "PNG")
            node["png"] = png.getvalue()
        nodes.append(node)
    (folder / "model.glb").write_bytes(glb(nodes))


def assemble(key: str, parts: dict) -> dict:
    folder = OUT / key
    folder.mkdir(parents=True, exist_ok=True)
    meta = {"key": key, "parts": []}
    for name, kinds in parts.items():
        if "mesh" not in kinds:
            continue
        mesh = json.loads(kinds["mesh"])
        pos, uv, nrm, index = unshare(mesh)
        # A MeshPart stretches its mesh's bounds to Size: carry that stretch into the node's matrix.
        scale = np.array(mesh["size"]) / np.maximum(pos.max(0) - pos.min(0), 1e-6)
        np.savez(folder / f"{name}.npz", pos=pos, uv=uv, nrm=nrm, index=index, matrix=np.array(matrix(mesh["cframe"], scale)))
        tex = next((k for k in kinds if k.startswith("tex")), None)
        if tex:
            w, h = (int(v) for v in tex[3:].split("x"))
            image = Image.frombytes("RGBA", (w, h), base64.b64decode(kinds[tex])).convert("RGB")
            image.save(folder / f"{name}.png")
            image.save(folder / f"{name}.raw.png")  # as generated; colormatch.py works from this
        meta["parts"].append({"name": name, "vertices": len(mesh["positions"]) // 3, "triangles": len(mesh["faces"]) // 3, "size": mesh["size"], "texture": tex and tex[3:]})
        if "ids" in kinds:  # generate.luau's publish = true: the part's mesh and texture asset ids
            meta["parts"][-1]["published"] = json.loads(kinds["ids"])
    (folder / "meta.json").write_text(json.dumps(meta, indent=1))
    build(folder)
    return meta


if __name__ == "__main__":
    everything = collect(Path(sys.argv[1]))
    for key in sys.argv[2:] or sorted(everything):
        meta = assemble(key, everything[key])
        tris = sum(p["triangles"] for p in meta["parts"])
        print(f"{key}: {len(meta['parts'])} part(s), {tris} triangles -> {OUT / key / 'model.glb'}")
