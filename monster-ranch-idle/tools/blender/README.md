# Blender tools: from a Meshy model to a monster in the game

Headless Blender 5.1 (`blender -b`) scripts that rig, animate, re-texture and export the Meshy models
made by `tools/meshy`. Each form's mesh is published once as a Roblox Mesh asset (skin weights and
bones included) and its texture uploaded; the game builds one MeshPart per form from the asset,
clones it for every monster, and bends each clone with its own Bone instances
(`src/client/Visuals/MeshMonster.luau`).

```sh
python tools/blender/pipeline.py scorchling,emberslug [--previews]   # rig -> bake -> export -> stylua
```

(`--source rbxgen` takes the model from Roblox's own generator instead of Meshy: `tools/rbxgen`.)

That writes, per form, `src/client/Visuals/MeshMonsters/<form>.luau` (bounds, scale, bones, clips),
`art/rigs/<form>/mesh.json` (the mesh) and `art/export/<form>.png` (the 1024 px texture). The rest is
done from Studio, in Edit, with both files served on localhost (`python -m http.server`):

1. Texture: the Studio MCP's `upload_image` with the PNGs' URLs, about three per call (ten at once
   timed out).
2. Mesh: `execute_luau` with `publish_meshes.luau`, its arguments set in front of it (the file says
   how); ten forms a call.
3. Ids: `python tools/blender/asset_ids.py --json ids.json` (or `asset_ids.py <form> mesh=... texture=...`)
   writes `Visuals/MeshMonsterAssets.luau`. A form is drawn only once it has both ids; until then it
   gets `MonsterModel`'s placeholder.

A re-rig needs a re-publish (the bones and skin live in the mesh asset); a texture-only change needs
only a new upload.

The first version shipped the mesh arrays in the modules and built every monster through its own
EditableMesh at runtime, which needed no mesh upload. Roblox's EditableMesh memory budget reserves a
fixed block per mesh, so `CreateEditableMesh` returned nil from about the eighth monster on screen
(2026-09-25). Published meshes have no such cap: 54 at once built and posed.

## One rig script per body type

Every script fits its skeleton to the model's own shape (no hand-placed joints) and keys the same
three clips, which `MonsterAnimator` plays: `idle` (looping, 2 s), `walk` (looping) and `hop` (played
once for happy and attack, so it starts and ends at rest). Shared code is in `riglib.py`.

| Archetype | Script | Skeleton | Motion |
|---|---|---|---|
| fox | `rig_quadruped.py` | spine, neck, head, ears, 3-bone tail, 4 two-bone legs; paws are the footprints | trot, hop |
| moth | `rig_moth.py` | body, head, antennae, 2-bone wings, dangling legs; wing root is where the mesh turns thin front-to-back | hovers; wings swing back and open |
| slug | `rig_slug.py` | spine through the centre of each cross-section (rises with a rearing front), head, eye stalks | crawl wave tail to head; rears up |
| blob | `rig_blob.py` | body, a `top` bone that slides down to squash (Bone transforms can't scale), feet, tail, fins or gills | waddle, squash-and-stretch hop |
| sprite | `rig_sprite.py` | body sphere, head, arms, 3-bone tail (what lies outside the sphere, behind and below) | hovers, bobs, tail trails |
| bunny | `rig_bunny.py` | hips, chest, head, 2-bone ears (base: where the ears join one head-wide slice), feet, tail | walks in small hops, ears lag |
| golem | `rig_golem.py` | hips, chest, head, 2-bone arms (root: where a hanging arm stands clear of the body in a slice), short legs | heavy side-to-side stomp, arms swing against the legs; hop throws both fists up |
| bug | `rig_bug.py` | body (front, with the face) and abdomen, antennae and wings (what rises above the shell line), six legs, 2-bone stinger | tripod gait, wings buzz in every clip; hop is a buzzing jump |

Moths and sprites are modelled hovering above the ground, and long or wide models get a `scale`
below 1 in their module (a slug is drawn with about a fox's bulk, not its height).

## The other scripts

- `bake_texture.py`: new UVs (xatlas, via `atlas.py` under the system Python) with padding, and the
  texture re-baked onto them, so no seams show at a distance. Also bakes Meshy's normal and roughness
  maps, which the game does not use (a normal map drew creases on runtime meshes; see `asset_ids.py`).
- `export_roblox.py`: the form's Luau module (under Studio's 200,000-character Source cap), its
  `mesh.json`, and the 1024 px textures.
- `publish_meshes.luau`, `asset_ids.py`: publishing the meshes and recording the ids (above).
- `export_static.py`: the same road for a building (no rig): `python tools/blender/export_static.py
  eggShop 0` turns it to face -Y, drops the underside, cuts it into pieces of equal area (each its
  own 1024 px texture: Roblox's cap, so a big building needs several) and bakes and exports each.
  Publish the pieces like monsters, then `export_static.py ids eggShop ids.json` writes the entry in
  `src/server/Systems/World/BuildingMeshes.luau`; `World/Dress.luau` swaps the placeholder boxes for
  it. The models come from `tools/meshy/buildings/make.py`.
- `previews.py` (system Python, Pillow): GIFs and contact sheets from a rig's `frames/`.
- `look.py`: renders any GLB from five angles. `model_fox.py`: the from-scratch test (not used).

## Eggs

```sh
python tools/blender/eggs.py              # everything, ~75 s; `eggs.py royal,sky` repaints just those
python tools/blender/eggs.py ids ids.json # record published ids in src/client/Visuals/EggAssets.luau
```

`eggs.py` (system Python: numpy, Pillow; it runs Blender for `eggs_blender.py`) makes, in `art/eggs`
(not in git, bar `preview/sheet.jpg`):

- `upload/egg_shell/mesh.json` (the smooth egg, ~3,000 triangles, 1 x 1.3 x 1), `upload/egg_gem/mesh.json`
  (the Crystal Egg's 96 flat facets), `upload/egg_orn_<egg>/mesh.json` (ornaments: Royal's crown,
  Harvest's stem and leaf, Bloom's flower, Sky's wings, Glacier's frost crystals). Publish them like
  monster meshes: `_G.MeshPublishArgs = { base = "http://127.0.0.1:<port>/", forms = { "egg_shell", ... } }`
  with `http.server` serving `art/eggs/upload`.
- `upload/egg_<egg>.png` (1024 x 512, one per `Config.Eggs` id), `egg_crack1..3.png` and
  `egg_painted.png` (transparent overlays), `egg_ornaments.png` (the ornaments' shared swatches).
  Upload them with `upload_image`.
- `icons/<egg>.png` (256 px, transparent, #1B1B1B ink outline), `renders/`, and `sheet.png`: every egg,
  the crack stages, the hunt egg, and the eggs at incubator size. Look at it after any change.

The patterns are painted in numpy, not baked from shader nodes: the texture is a latitude-longitude map
of the egg, so every texel's point on the surface is known, and each motif is a distance field in the
egg's tangent plane there (crisp cartoon shapes, even sizes, an ink rim, no seam). One painter per egg
in `PAINTERS`; the tool refuses to run when a `Config.Eggs` id has none. Re-running keeps the ids already
in `EggAssets.luau` and refreshes the ornament offsets.

## Checking a change to a rig script

Rigs are deterministic, so a refactor can be proved to change nothing: rig a model before and after
and compare the bones, the skin weights and every clip's keys. (`riglib.py` was split out of
`rig_quadruped.py` that way: all seven fox rigs came out identical.) For a new or changed body type,
look at the clips rendered frame by frame, from the front and the side.
