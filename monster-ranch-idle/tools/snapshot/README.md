# Snapshot

Renders a picture of the game as it is now, without Roblox Studio: the real server systems
and the real client run in the Lune test harness, and the resulting parts and GUI are drawn
in headless Chromium (three.js for the 3D world, HTML/CSS for the ScreenGui tree).

```sh
# 1. Build a lived-in ranch and dump what the player sees (from monster-ranch-idle/)
lune run tools/snapshot/scene tools/snapshot/scene.json [ScreenName]

# 2. Render it (needs Node and a Chromium; CHROMIUM_PATH overrides the default path)
cd tools/snapshot && npm install
node render.mjs scene.json ranch.png                     # HUD + ranch overview
node render.mjs scene.json pen.png "eye=x,y,z&at=x,y,z&fov=40&noui=1"   # close-up
```

`SNAPSHOT_PLACE=hub lune run tools/snapshot/scene out.json TradingHub` builds the Trading Hub
place instead (update 3.0: hub layout, no plots, ads on the Trade Board); frame it with a raw
`eye`/`at` camera.

The fourth argument frames the camera: `toHub,side,up,look` (studs around the player's plot)
or a raw query with `eye`, `at`, `fov` and `noui`.

What it shows is the procedural placeholder art (Visuals/MonsterModel, World/Build) with
approximate lighting; fonts, UI strokes and layouts are close to Roblox but not pixel exact.
Particles, SurfaceGuis and BillboardGuis are not drawn. Latest pictures: `docs/snapshots/`.
