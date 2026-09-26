# Roblox's own 3D generator: what it can do, and the road into the game

Roblox generates textured meshes itself (the Cube model), for free, in about 30 s, from a prompt, a
concept image or both. Tested 2026-09-25 against the Meshy and Tripo models already in the game.

| Use it for | Keep Meshy / Tripo for |
|---|---|
| props and scenery: fences, barrels, crates, trees, lamps, signs (2-8k tris, one consistent toy style) | hero creatures, where the concept's colours and eyes must survive (Roblox's are paler, its eyes flat grey) |
| creatures from an approved concept when credits are short: the shape is as good as Meshy's, the body type holds, the existing rig scripts take it unchanged | buildings seen up close: Roblox textures stop at 1024 px per part; Tripo's 4K source is what `export_static.py` cuts into sharp pieces |
| drafts: 8 variations of an idea in under a minute | |

## What Roblox offers

- `GenerationService:GenerateModelAsync(inputs, schema)` - the one to use. `inputs`: `TextPrompt`,
  `Image` (an Image asset, `Content.fromAssetId`), `Size` (approximate box), `MaxTriangles` (at most
  20000: the API refuses more), `GenerateTextures`. `schema`: `{ PredefinedSchema = "Body1" }` (one
  mesh) or `{ SchemaDefinition = { Groups = { "roof", "walls", ... } } }` (up to 8 parts). Runs in
  Studio Edit (through the MCP's `execute_luau`) and in a Play server. Returns a Model whose mesh and
  texture are opaque (not assets): they can be read with `CreateEditableMeshAsync` /
  `CreateEditableImageAsync`, and last only as long as the instance.
  Docs: create.roblox.com/docs/reference/engine/classes/GenerationService, /docs/parts/model-generation.
- `GenerateMeshAsync` is deprecated; `SegmentMeshAsync` splits an existing mesh (Studio only).
- The Studio MCP's `generate_mesh` (the Assistant's Mesh Generator): text only, publishes the mesh and
  texture as assets itself, but does not take many at once: 3 of 5 started together failed here
  ("PreviewAssets not found"), and a peer session at the same time saw 6 of 11 fail "Too Many
  Requests" while waves of 3 all passed. It cannot take an image.
- `generate_texture` (Texture Generator) retextures a model in place, still at 1024 px. It repairs a
  wrong detail (grain sacks drawn with googly eyes came back as plain burlap) but repaints anything
  the prompt does not name (the carrot sign turned red): name every colour.
- Cube itself is open source (github.com/Roblox/cube) but gives geometry only, no texture, and wants
  16 GB of VRAM (this laptop's RTX 5070 has 8). No Open Cloud endpoint for 3D generation was found.

## Measured

- Texture: 1024 x 1024 per MeshPart, always. With `parts`, every part gets its own 1024 texture (a
  7-part feed store: 7 textures); the triangle budget is shared between them.
- Triangles: 7-16k for a creature at 20000, 11-16k for a building; props came in at 2-8k under
  3-8k budgets.
- Time: 21-45 s each; 8 at once from one call, no rate limit hit. Geometry only: 11 s.
- The same inputs give nearly the same model. For another take, change the prompt or the image.
- A prompt can fail "Moderation failed" for nothing ("a round leafy oak tree with a thick trunk").

## Quality, against Meshy on the same concepts

Eight monsters (fox, golem, moth, blob, slug, bee, bunny, sprite) from the roster's own concept images:

- **Shapes** match Meshy's for six of them. The image holds the body type: the fox stands on four
  legs (text alone gives an upright chibi, the 2026-09-25 pilot's finding). Text on top of the
  image steers details: "four long slender legs" lengthened the fox's stubby ones.
- **Colours** come out at about half the concept's chroma and drift warm: the yellow jelly blob came
  back peach, the gold bee beige. The background colour (grey, white, black) and the prompt ("bright
  yellow") made no difference, and text alone came out peach too. `colormatch.py` pulls the
  texture back to the concept's colours (the default mode fixed the blob, the slug and the fox).
- **Eyes** lose their glossy highlight.
- **The input matters** as much as with Meshy: a concept sheet with two moths became one fused shape.
- **Buildings**: from the concept image, the Feed Store came out whole and faithful. From text with
  parts, its layout broke (sacks floating mid-air, the awning off to one side); from the image with
  parts it held together, with 7x the texels, but the door lost its glass.
- **In game**: the Roblox Kindlefox went through `pipeline.py` unchanged (fox rig, 18 bones, trot,
  hop, idle) and stood beside the Meshy one in Play: it animates the same; it is paler, with flat
  eyes. The slug and the bee also rigged and exported (not yet looked at in Play).

## The road

```
concept image (the roster's, or any)   prompt
          \                              /
   make.py prep -> upload_image -> make.py ids -> make.py args
                              |
           Studio (Edit): generate.luau    -> receiver.py -> art/rbxgen/_posted
                              |
   make.py finish: assemble.py -> colormatch.py -> review sheet (art/rbxgen/review_<batch>.png)
                              |
   monsters:  python tools/blender/pipeline.py FORM --source rbxgen [--as NAME]
              (rig by body type, export; no re-bake: see below), then publish as usual
```

1. Write a batch file (`batches/trial.json` is one): a key, a concept and/or a prompt per job.
2. `python tools/rbxgen/make.py prep BATCH`, then serve `art/rbxgen/_serve` on port 38520 and upload
   the printed URLs with the MCP's `upload_image`, three a call. Record the reply:
   `python tools/rbxgen/make.py ids BATCH '<reply json>'`.
3. `python tools/rbxgen/receiver.py` (port 38519), then `python tools/rbxgen/make.py args BATCH` and run
   its line in front of `generate.luau`'s text with `execute_luau` (Edit). Delete `Workspace.RbxGen`
   before saving the place.
4. `python tools/rbxgen/make.py finish BATCH`, and look at the review sheet: concept, then the model
   from three sides. Re-run `colormatch.py KEY CONCEPT --mode hist|palette` on a model that needs it.
5. A monster whose key is its form id goes on with `pipeline.py FORM --source rbxgen`. `--as NAME`
   writes it under another name to try beside the live form (delete that module from
   `src/client/Visuals/MeshMonsters/` afterwards if it is not kept).

`pipeline.py` skips `bake_texture.py` for these: Roblox's atlas is already 1024 px with every gap
filled, and re-baking it onto new UVs at the same size kept only 57-66% of its texels.

Props: a job with `"publish": true` also publishes each part's mesh and texture from Studio as they
came out (one publish at a time), and `make.py finish` records the ids in its `meta.json`. They load
with `CreateMeshPartAsync` like the scenery's (a hay bale, a milk churn and a wheelbarrow checked
2026-09-25), so a prop goes straight into `src/server/Systems/World/SceneryMeshes.luau` (a peer
session's scenery, bafd3ab, made its 13 kinds with the MCP's `generate_mesh` instead: text only,
three at a time). A model whose texture `colormatch.py` changes publishes only its mesh this way; upload
its corrected PNG with `upload_image`.

## Files

- `generate.luau` - the Studio runner (all jobs at once, reads back every part, posts it in chunks).
- `receiver.py` - saves the posts. `assemble.py` - posts -> `art/rbxgen/<key>/model.glb` (+ textures,
  meshes, meta). `colormatch.py` - textures -> the concept's colours, rebuilds the GLB.
- `make.py` - the batch steps above. `batches/` - batch files.
