"""Grab the Studio viewport (left part, clear of floating windows) for the VFX bake-off report.

    python tools/vfx/grab.py <out.png>

Coordinates are the Studio viewport on this PC's 1920x1200 screen (HD 1080 device frame);
x stops at 1440 because a floating Claude window sits over the right edge.
"""
import sys
from PIL import ImageGrab

im = ImageGrab.grab(all_screens=False)
im.crop((200, 221, 1440, 1067)).save(sys.argv[1])
print(sys.argv[1], im.size)
