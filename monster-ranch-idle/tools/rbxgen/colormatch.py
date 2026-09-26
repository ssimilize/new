"""Brings a generated model's textures back to its concept's colours.

  python tools/rbxgen/colormatch.py KEY CONCEPT.png [--mode reinhard|hist] [--strength 1.0]

Roblox's generator follows a concept's shapes well but paints paler and warmer than it (2026-09-25:
a yellow jelly blob came out peach, a gold bee beige; Meshy kept both). This moves each part's
texture towards the concept's foreground colours in CIELAB:

  reinhard  matches the mean and spread of L, a and b (Reinhard et al. 2001): one global shift,
            keeps the texture's own contrast pattern. The default.
  hist      matches each channel's whole histogram: closer palettes, but a texture whose areas
            differ from the concept's (a big back, a small face) can trade colours between them.
  palette   reinhard, then each of the texture's 6 colour clusters moves onto the nearest of the
            concept's: best on a creature of a few distinct colours (the void sprite's indigo body
            and lavender belly came back); no better than reinhard on the bee.

A global match cannot fix a model whose colour areas differ from the concept's: a bee generated
with more cream belly than its concept stays paler whatever the mode. Look at the review sheet.

The concept's background (its border colour: the roster draws on flat grey) is left out. Works from
<part>.raw.png, writes <part>.png and rebuilds model.glb, so it can be re-run with other settings.
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from skimage import color, exposure

sys.path.insert(0, str(Path(__file__).resolve().parent))
from assemble import OUT, build  # noqa: E402


def foreground(concept: np.ndarray) -> np.ndarray:
    """Pixels that are not the flat background: far (in Lab) from the border's median colour."""
    lab = color.rgb2lab(concept)
    border = np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])
    far = np.linalg.norm(lab - np.median(border, axis=0), axis=-1) > 12
    far = ndimage.binary_opening(far, iterations=2)
    labels, n = ndimage.label(far)
    if n > 1:  # the subject is the biggest blob; specks of noise in the background are not
        sizes = ndimage.sum(far, labels, range(1, n + 1))
        far = labels == (np.argmax(sizes) + 1)
    return ndimage.binary_erosion(far, iterations=3)  # the rim is blended with the background


def reinhard(tex: np.ndarray, ref: np.ndarray) -> np.ndarray:
    out = (tex - tex.reshape(-1, 3).mean(0)) / (tex.reshape(-1, 3).std(0) + 1e-6)
    return out * ref.std(0) + ref.mean(0)


def palette(tex: np.ndarray, ref: np.ndarray, k: int = 6) -> np.ndarray:
    """Reinhard first (removes the global cast), then each texel moves by the offset between its
    colour cluster's centre and the nearest of the concept's cluster centres, blended by distance
    so neighbouring colours don't tear apart."""
    from scipy.cluster.vq import kmeans2

    base = reinhard(tex, ref)
    flat = base.reshape(-1, 3)
    rng = np.random.default_rng(0)
    sample = flat[rng.choice(len(flat), min(len(flat), 60000), replace=False)]
    ours, _ = kmeans2(sample, k, seed=1, minit="++")
    theirs, _ = kmeans2(ref[rng.choice(len(ref), min(len(ref), 60000), replace=False)], k, seed=1, minit="++")
    target = theirs[np.argmin(np.linalg.norm(ours[:, None] - theirs[None], axis=-1), axis=1)]
    d = np.linalg.norm(flat[:, None] - ours[None], axis=-1)
    w = np.exp(-((d / 8.0) ** 2))
    w /= w.sum(1, keepdims=True) + 1e-9
    return (flat + w @ (target - ours)).reshape(tex.shape)


def match(key: str, concept_path: Path, mode: str, strength: float) -> list:
    folder = OUT / key
    concept = np.asarray(Image.open(concept_path).convert("RGB"), np.float64) / 255
    ref = color.rgb2lab(concept)[foreground(concept)]
    report = []
    for part in json.loads((folder / "meta.json").read_text())["parts"]:
        raw = folder / f"{part['name']}.raw.png"
        if not raw.exists():
            continue
        tex = color.rgb2lab(np.asarray(Image.open(raw).convert("RGB"), np.float64) / 255)
        if mode == "hist":
            moved = exposure.match_histograms(tex.reshape(-1, 1, 3), ref.reshape(-1, 1, 3), channel_axis=-1).reshape(tex.shape)
        elif mode == "palette":
            moved = palette(tex, ref)
        else:
            moved = reinhard(tex, ref)
        # Near-greys (black eyes, white glints) keep their hue: a global a/b shift tinted the fox's
        # black eyes blue. Their lightness still moves with the rest.
        chroma = np.hypot(tex[..., 1], tex[..., 2])
        keep = np.stack([np.ones_like(chroma), *[np.clip((chroma - 6) / 14, 0, 1)] * 2], axis=-1)
        out = tex + (moved - tex) * strength * keep
        rgb = np.clip(color.lab2rgb(out), 0, 1)
        Image.fromarray((rgb * 255 + 0.5).astype(np.uint8)).save(folder / f"{part['name']}.png")
        before, after = tex.reshape(-1, 3).mean(0), out.reshape(-1, 3).mean(0)
        report.append(f"{part['name']}: mean Lab {np.round(before, 1).tolist()} -> {np.round(after, 1).tolist()} (concept {np.round(ref.mean(0), 1).tolist()})")
    build(folder)
    return report


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("key")
    ap.add_argument("concept", type=Path)
    ap.add_argument("--mode", choices=["reinhard", "hist", "palette"], default="reinhard")
    ap.add_argument("--strength", type=float, default=1.0)
    a = ap.parse_args()
    print("\n".join(match(a.key, a.concept, a.mode, a.strength)))
