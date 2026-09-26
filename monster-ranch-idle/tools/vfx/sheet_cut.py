"""Cut a grid sheet of glowing sprites drawn on black into particle textures.

    python tools/vfx/sheet_cut.py SHEET --rows 2 --cols 3 --names flame,droplet,leaf,bolt,star,wisp \
        --outdir art/vfx/bakeoff/meshy [--size 256] [--fill 0.82] [--gain auto|auto:NAME=1.0,...] \
        [--grey-floor 0.45] [--grey-mid 0.78] [--contact]

Per cell it writes `<name>_color.png` (natural colour) and `<name>.png` (tintable: grey whose
luminance carries the shading), both SIZE x SIZE RGBA, subject trimmed, centred and scaled so its
longer side fills FILL of the frame. `--contact` also writes `contact.png` (every delivered sprite on
a #202028 and a #E8E8E8 strip).

How the cut works:
- Gutters: the nominal grid lines are moved to the darkest column/row within +-20% of a cell, so a
  sheet whose sprites are not exactly on a grid still cuts cleanly.
- Black point: the 99th percentile of max(R,G,B) over the sheet's darkest gutter band (auto), so
  near-black noise from the image model becomes fully transparent.
- Alpha = (max(R,G,B) - black) / (white - black) * gain, clipped to 1. Colour = pixel / alpha
  (un-premultiplied, so no black fringe on a light background). `gain auto` makes the object's
  bright interior (70th percentile of its lit pixels) opaque, which keeps a solid, not-glowing
  sprite (a leaf) from turning see-through; for a glow it is ~1.
- Within a cell only the largest connected blob and blobs near it are kept (fragments of a
  neighbouring sprite that crossed the gutter are dropped). Needs scipy; skipped without it.
- Resizing is done premultiplied (PIL "RGBa") so edges never pick up the black they sat on.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

try:
    from scipy import ndimage
except ImportError:  # optional: only the stray-fragment cleanup needs it
    ndimage = None

DARK = (0x20, 0x20, 0x28)
LIGHT = (0xE8, 0xE8, 0xE8)


def gutters(profile: np.ndarray, n: int) -> list[int]:
    """n+1 cut positions along one axis, each nominal line moved to the darkest spot nearby."""
    length = len(profile)
    cell = length / n
    cuts = [0]
    for i in range(1, n):
        nominal = int(round(i * cell))
        lo, hi = max(1, int(nominal - 0.2 * cell)), min(length - 1, int(nominal + 0.2 * cell))
        window = profile[lo:hi]
        # Prefer the centre of the darkest run rather than its first pixel.
        dark = np.flatnonzero(window <= window.min() + 1e-6)
        cuts.append(lo + int(dark[len(dark) // 2]))
    cuts.append(length)
    return cuts


def black_point(value: np.ndarray, xs: list[int], ys: list[int]) -> float:
    band = []
    for x in xs[1:-1]:
        band.append(value[:, max(0, x - 3): x + 4].ravel())
    for y in ys[1:-1]:
        band.append(value[max(0, y - 3): y + 4, :].ravel())
    edge = np.concatenate([value[:4].ravel(), value[-4:].ravel(), value[:, :4].ravel(), value[:, -4:].ravel()] + band)
    return float(np.percentile(edge, 99))


def keep_main(alpha: np.ndarray) -> np.ndarray:
    if ndimage is None:
        return alpha
    mask = alpha > 0.04
    labels, count = ndimage.label(mask, structure=np.ones((3, 3)))
    if count <= 1:
        return alpha
    sizes = ndimage.sum(alpha, labels, index=range(1, count + 1))
    main = int(np.argmax(sizes)) + 1
    my, mx = np.nonzero(labels == main)
    h, w = alpha.shape
    cy0, cy1, cx0, cx1 = my.min(), my.max(), mx.min(), mx.max()
    margin = 0.12 * max(h, w)
    keep = np.zeros(count + 1, bool)
    keep[main] = True
    for idx in range(1, count + 1):
        if idx == main:
            continue
        ys, xs = np.nonzero(labels == idx)
        touches = ys.min() == 0 or xs.min() == 0 or ys.max() == h - 1 or xs.max() == w - 1
        near = ys.max() >= cy0 - margin and ys.min() <= cy1 + margin and xs.max() >= cx0 - margin and xs.min() <= cx1 + margin
        # Sparkles/embers near the subject stay; far or edge-touching pieces are a neighbour's.
        keep[idx] = near and not touches
    # Everything outside a generous dilation of the kept blobs goes, which also takes the faint
    # (below-threshold) glow of a dropped fragment and stray near-black noise with it.
    kept = keep[labels] & mask
    region = ndimage.binary_dilation(kept, iterations=max(8, int(0.06 * max(h, w))))
    out = alpha.copy()
    out[~region | (mask & ~kept)] = 0
    return out


def cut_cell(rgb: np.ndarray, black: float, gain_mode) -> tuple[np.ndarray, np.ndarray, float]:
    value = rgb.max(axis=2)
    alpha = np.clip((value - black) / (1.0 - black), 0, 1)
    alpha = keep_main(alpha)
    if gain_mode == "auto":
        lit = alpha[alpha > 0.15]
        gain = 1.0 / max(np.percentile(lit, 70), 1 / 3) if lit.size else 1.0
    else:
        gain = float(gain_mode)
    # A gain above 1 must not lift the near-black tail into a visible haze: the bottom 2% of the
    # raw range stays at zero and the ramp starts there.
    alpha = np.clip((alpha - 0.02 * (gain > 1)) * gain, 0, 1)
    # Un-premultiply against black: the (black-point corrected) pixel is alpha * colour, so
    # colour = pixel / alpha keeps alpha * colour equal to what was drawn on black.
    safe = np.maximum(alpha, 1e-4)[..., None]
    colour = np.clip(np.maximum(rgb - black, 0) / (1 - black) / safe, 0, 1)
    colour[alpha <= 0] = 0
    return colour, alpha, gain


def to_grey(colour: np.ndarray, alpha: np.ndarray, floor: float, mid: float) -> np.ndarray:
    """Luminance, stretched to [floor, 1]; a gamma then lifts the body so its median sits at `mid`
    (a tint multiplies the texture, so a dark-grey body would only ever tint dark)."""
    lum = colour @ np.array([0.2126, 0.7152, 0.0722])
    w = alpha > 0.1
    if w.any():
        lo, hi = np.percentile(lum[w], 2), np.percentile(lum[w], 99.5)
    else:
        lo, hi = 0.0, 1.0
    norm = np.clip((lum - lo) / max(hi - lo, 1e-3), 0, 1)
    if w.any() and mid > floor:
        target = (mid - floor) / (1 - floor)
        median = float(np.clip(np.median(norm[w]), 1e-3, 0.999))
        g = float(np.clip(np.log(target) / np.log(median), 0.25, 1.0))  # only ever brightens
        norm = norm ** g
    grey = floor + (1 - floor) * norm
    return np.repeat(grey[..., None], 3, axis=2)


def frame(colour: np.ndarray, alpha: np.ndarray, size: int, fill: float, box) -> Image.Image:
    y0, y1, x0, x1 = box
    rgba = np.dstack([colour[y0:y1, x0:x1], alpha[y0:y1, x0:x1]])
    img = Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").convert("RGBa")
    h, w = y1 - y0, x1 - x0
    scale = fill * size / max(h, w)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    img = img.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBa", (size, size), (0, 0, 0, 0))
    canvas.paste(img, ((size - nw) // 2, (size - nh) // 2))
    return canvas.convert("RGBA")


def contact(outdir: Path, names: list[str], size: int = 128) -> Path:
    rows = []
    for suffix in ("", "_color"):
        tiles = [outdir / f"{n}{suffix}.png" for n in names]
        if all(t.exists() for t in tiles):
            rows.append(tiles)
    pad = 8
    width = pad + len(names) * (size + pad)
    strip = size + 2 * pad
    sheet = Image.new("RGB", (width, strip * 2 * len(rows)), DARK)
    for r, tiles in enumerate(rows):
        for b, bg in enumerate((DARK, LIGHT)):
            top = (r * 2 + b) * strip
            sheet.paste(Image.new("RGB", (width, strip), bg), (0, top))
            for i, tile in enumerate(tiles):
                im = Image.open(tile).convert("RGBA").resize((size, size), Image.LANCZOS)
                sheet.paste(im, (pad + i * (size + pad), top + pad), im)
    path = outdir / "contact.png"
    sheet.save(path)
    return path


def parse_gain(text: str, names: list[str]) -> dict:
    default, per = text, {}
    if ":" in text:
        default, rest = text.split(":", 1)
        for item in rest.split(","):
            k, _, v = item.partition("=")
            per[k] = v
    return {n: per.get(n, default) for n in names}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sheet")
    ap.add_argument("--rows", type=int, required=True)
    ap.add_argument("--cols", type=int, required=True)
    ap.add_argument("--names", required=True, help="comma list, row-major; '-' skips a cell")
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--size", type=int, default=256)
    ap.add_argument("--fill", type=float, default=0.82)
    ap.add_argument("--gain", default="auto", help="auto | number | auto:name=1.2,name2=auto")
    ap.add_argument("--black", default="auto", help="auto | 0..255")
    ap.add_argument("--grey-floor", type=float, default=0.45)
    ap.add_argument("--grey-mid", type=float, default=0.78, help="median grey of the body (0 = off)")
    ap.add_argument("--contact", action="store_true")
    args = ap.parse_args()

    names = [n.strip() for n in args.names.split(",")]
    if len(names) != args.rows * args.cols:
        raise SystemExit(f"{len(names)} names for a {args.rows}x{args.cols} grid")
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    rgb = np.asarray(Image.open(args.sheet).convert("RGB"), dtype=np.float64) / 255.0
    value = rgb.max(axis=2)
    xs = gutters(value.sum(axis=0), args.cols)
    ys = gutters(value.sum(axis=1), args.rows)
    black = black_point(value, xs, ys) if args.black == "auto" else float(args.black) / 255.0
    if black > 0.2:
        # The image model sometimes ignores "black background" (Meshy nano-banana-pro drew the same
        # prompt on white on the second roll); a brightness cut of that would be all alpha.
        raise SystemExit(f"background is not black (black point {black * 255:.0f}/255): re-roll or matte it another way")
    gains = parse_gain(args.gain, names)

    report = {"sheet": str(args.sheet), "cuts_x": xs, "cuts_y": ys, "black": round(black * 255, 1), "cells": {}}
    delivered = []
    for i, name in enumerate(names):
        if name == "-":
            continue
        r, c = divmod(i, args.cols)
        cell = rgb[ys[r]: ys[r + 1], xs[c]: xs[c + 1]]
        colour, alpha, gain = cut_cell(cell, black, gains[name])
        on = np.nonzero(alpha > 0.02)
        if not on[0].size:
            report["cells"][name] = "empty"
            continue
        box = (on[0].min(), on[0].max() + 1, on[1].min(), on[1].max() + 1)
        frame(colour, alpha, args.size, args.fill, box).save(outdir / f"{name}_color.png")
        frame(to_grey(colour, alpha, args.grey_floor, args.grey_mid), alpha, args.size, args.fill, box).save(outdir / f"{name}.png")
        touches = box[0] == 0 or box[2] == 0 or box[1] == cell.shape[0] or box[3] == cell.shape[1]
        report["cells"][name] = {"gain": round(gain, 3), "bbox": [int(v) for v in box], "cell": list(cell.shape[:2]), "touches_cell_edge": bool(touches)}
        delivered.append(name)
    if args.contact and delivered:
        report["contact"] = str(contact(outdir, delivered))
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
