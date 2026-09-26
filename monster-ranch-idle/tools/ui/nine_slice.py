"""Draws the 9-slice panel and button skins (system Python + Pillow + numpy), at 2x for crispness.

  python tools/ui/nine_slice.py            # writes art/ui/upload/panel.png, button.png + art/ui/nine_slice_preview.png

The skins are OVERLAYS, not fills: the game keeps drawing each panel and button in its own colour
(cream #FFF7E3 panels, any colour for buttons) and lays the skin on top, so one uploaded image serves
every button colour. A skin is transparent in the middle and adds only what flat frames cannot:
a crisp #1B1B1B outline on the inside edge, a soft white highlight under the top edge, a subtle inner
shade toward the bottom and, for buttons, the chunky 7 px lip. Radii and strokes are Theme's
(panel 18 px / 4 px, button 14 px / 3 px) at 2x; the game uses SliceScale 0.5. SLICES below must
match Theme.Slices in src/client/UI/Theme.luau.

Every shape is drawn at 8x the output size and box-downsampled, so edges are anti-aliased.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import uiart  # noqa: E402

SS = 4  # supersampling on top of the 2x output
SLICES = {
    # name: (size px @2x, radius, outline, lip, slice inset) - the slice inset is SliceCenter's margin
    "panel": (128, 36, 8, 0, 44),
    "button": (96, 28, 6, 14, 32),
}


def _mask(size: int, box: tuple[float, float, float, float], radius: float) -> np.ndarray:
    """Anti-aliased rounded-rect coverage (0..1) at `size` px; box and radius in output px."""
    big = Image.new("L", (size * SS, size * SS), 0)
    x0, y0, x1, y1 = (v * SS for v in box)
    ImageDraw.Draw(big).rounded_rectangle((x0, y0, x1 - 1, y1 - 1), radius=radius * SS, fill=255)
    return np.asarray(big.resize((size, size), Image.BOX)).astype(np.float32) / 255


def _over(dst: np.ndarray, rgb: tuple[int, int, int], alpha: np.ndarray) -> None:
    """Composite a flat colour with per-pixel alpha over dst (premultiplied-free, straight alpha)."""
    a0 = dst[..., 3]
    a = alpha + a0 * (1 - alpha)
    for c in range(3):
        num = rgb[c] / 255 * alpha + dst[..., c] * a0 * (1 - alpha)
        dst[..., c] = np.where(a > 0, num / np.maximum(a, 1e-6), 0)
    dst[..., 3] = a


def skin(name: str) -> Image.Image:
    size, r, t, lip, _inset = SLICES[name]
    full = _mask(size, (0, 0, size, size), r)
    inner = _mask(size, (t, t, size - t, size - t), max(1, r - t))
    y = np.arange(size, dtype=np.float32)[:, None] * np.ones((1, size), np.float32)
    out = np.zeros((size, size, 4), np.float32)

    # inner shade: a soft darkening that ramps in over the lower part of the bottom slice
    band = 18 if name == "panel" else 12
    start = size - t - lip - band
    ramp = np.clip((y - start) / band, 0, 1) ** 1.5
    _over(out, (0, 0, 0), inner * ramp * (0.10 if name == "panel" else 0.12))
    # lip (buttons): the chunky darker base, with a hairline of light on its top edge
    if lip:
        lip_top = size - t - lip
        _over(out, (0, 0, 0), inner * (y >= lip_top) * 0.22)
        _over(out, (255, 255, 255), inner * ((y >= lip_top - 2) & (y < lip_top)) * 0.18)
    # top highlight: a rounded white band just under the top outline, inset from the corners
    hl_h = 6 if name == "panel" else 10
    hl = _mask(size, (t + r * 0.45, t + 2, size - t - r * 0.45, t + 2 + hl_h), hl_h / 2)
    _over(out, (255, 255, 255), hl * (0.55 if name == "panel" else 0.42))
    # the outline ring, on the inside edge
    _over(out, uiart.INK, np.clip(full - inner, 0, 1))
    out[..., 3] *= full
    return Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def nine_slice(img: Image.Image, w: int, h: int, inset: int, scale: float) -> Image.Image:
    """How Roblox draws ScaleType.Slice with a square SliceCenter inset and SliceScale."""
    s = img.size[0]
    m = round(inset * scale)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    xs, ys = [0, inset, s - inset, s], [0, inset, s - inset, s]
    dx, dy = [0, m, w - m, w], [0, m, h - m, h]
    for i in range(3):
        for j in range(3):
            part = img.crop((xs[i], ys[j], xs[i + 1], ys[j + 1]))
            tw, th = dx[i + 1] - dx[i], dy[j + 1] - dy[j]
            if tw > 0 and th > 0:
                out.alpha_composite(part.resize((tw, th), Image.LANCZOS), (dx[i], dy[j]))
    return out


def _filled(w: int, h: int, radius: int, colour: str, skin_img: Image.Image, inset: int) -> Image.Image:
    base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    m = _mask(max(w, h), (0, 0, w, h), radius)[:h, :w]
    fill = Image.new("RGBA", (w, h), colour)
    fill.putalpha(Image.fromarray((m * 255).astype(np.uint8)))
    base.alpha_composite(fill)
    base.alpha_composite(nine_slice(skin_img, w, h, inset, 0.5))
    return base


def preview(skins: dict[str, Image.Image], out: Path) -> None:
    sheet = Image.new("RGBA", (560, 300), "#7CC456")
    sheet.alpha_composite(_filled(300, 260, 18, "#FFF7E3", skins["panel"], SLICES["panel"][4]), (20, 20))
    for i, col in enumerate(["#43B649", "#F2A93B", "#EF6FA8", "#4FB6F2", "#9AA39C"]):
        sheet.alpha_composite(_filled(200, 50 if i else 58, 14, col, skins["button"], SLICES["button"][4]),
                              (340, 24 + i * 54))
    sheet.convert("RGB").save(out)


def main():
    uiart.UPLOAD.mkdir(parents=True, exist_ok=True)
    skins = {n: skin(n) for n in SLICES}
    for n, im in skins.items():
        im.save(uiart.UPLOAD / f"{n}.png")
        size, _r, _t, _lip, inset = SLICES[n]
        print(f"{n}.png {size}x{size}  SliceCenter = Rect.new({inset}, {inset}, {size - inset}, {size - inset}), SliceScale 0.5")
    preview(skins, uiart.ART_UI / "nine_slice_preview.png")


if __name__ == "__main__":
    main()
