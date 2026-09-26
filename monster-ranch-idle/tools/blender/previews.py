"""Turns rig_quadruped.py's rendered frames into previews (system Python with Pillow; Blender's
bundled Python has no Pillow).

  python tools/blender/previews.py <rig out dir>

Writes preview_rest_<view>.png (skeleton drawn over the rest pose), preview_<clip>.gif (the
three-quarter view, looping), preview_<clip>_sheet.png (six side-view frames, first to last) and
preview_<clip>_front_sheet.png (the same from the three-quarter view).
"""

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(sys.argv[1])
FRAMES = OUT / "frames"
manifest = json.loads((FRAMES / "manifest.json").read_text(encoding="utf-8"))

for view, rest in manifest["rest"].items():
    im = Image.open(FRAMES / rest["image"]).convert("RGB")
    d = ImageDraw.Draw(im)
    w, h = im.size
    for name, a, c in rest["bones"]:
        a, c = (a[0] * w, a[1] * h), (c[0] * w, c[1] * h)
        color = (255, 230, 60) if name.startswith(("ear", "tail")) else (40, 220, 255)
        d.line([a, c], fill=color, width=3)
        d.ellipse([a[0] - 4, a[1] - 4, a[0] + 4, a[1] + 4], fill=(255, 255, 255), outline=(0, 0, 0))
    im.save(OUT / f"preview_rest_{view}.png")

for clip, info in manifest["clips"].items():
    ms = int(1000 * info["step"] / info.get("fps", manifest["fps"]))
    for view, files in info["views"].items():
        shots = [Image.open(FRAMES / f).convert("RGB") for f in files]
        if view == "front34":
            shots[0].save(OUT / f"preview_{clip}.gif", save_all=True, append_images=shots[1:], duration=ms, loop=0)
        cols = min(6, len(shots))
        picks = [shots[round(i * (len(shots) - 1) / max(1, cols - 1))] for i in range(cols)]
        sheet = Image.new("RGB", (picks[0].width * cols, picks[0].height))
        for i, s in enumerate(picks):
            sheet.paste(s, (i * s.width, 0))
        sheet.save(OUT / f"preview_{clip}_{'front_' if view == 'front34' else ''}sheet.png")
print("previews:", sorted(p.name for p in OUT.glob("preview_*")))
