# Meshy

`meshy.py` drives the [Meshy API](https://docs.meshy.ai) for the game's 3D art: concept images,
models, textures and rigs. Python 3.8+, no packages.

## The key

The tool reads `MESHY_API_KEY` from the environment. Save it once as a Windows user variable, from
a PowerShell terminal (the key is typed at a hidden prompt, so it stays out of the shell history):

```powershell
$k = Read-Host "Meshy API key" -AsSecureString; [Environment]::SetEnvironmentVariable("MESHY_API_KEY", [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($k)), "User")
```

Keys are made at <https://www.meshy.ai/settings/api>. The tool also reads the user variable
straight from the registry, so terminals that were already open don't need restarting. To remove it:
`[Environment]::SetEnvironmentVariable("MESHY_API_KEY", $null, "User")`.

The key is sent only in the Authorization header to `api.meshy.ai`. It is never printed, saved
into a task record, or sent to the signed download URLs.

## Use

From `monster-ranch-idle/`:

```sh
python tools/meshy/meshy.py balance                      # free
python tools/meshy/meshy.py create <kind> <name> --settings '<json>' [--link FIELD=NAME] [--image FIELD=PATH]
python tools/meshy/meshy.py poll <name> --wait           # free
python tools/meshy/meshy.py download <name>              # free
python tools/meshy/meshy.py list
```

Kinds: `text-to-image`, `image-to-image`, `text-to-3d` (v2), `image-to-3d`, `multi-image-to-3d`,
`retexture`, `remesh`, `rigging`, `animations`. The settings are the API's own body fields.

- `--link input_task_id=barn-concept` passes another task's id: image-to-3d from a text-to-image
  concept, `preview_task_id` for a text-to-3d refine, `input_task_id` for rigging.
- `--image image_url=art/ref/egg.png` sends a local png or jpg as a data URI.

Each task's files go to `art/meshy/<name>/` (gitignored): `submission.json`, `status.json` (holds
signed URLs, so don't share it), and the downloads (`model.glb`, `texture_0_base_color.png`,
`image_0.png`, `thumbnail.png`, ...). Every create and every finished task is appended to
`art/meshy/ledger.jsonl` with the credits it used.

**`create` spends credits.** It writes `submission.json` before posting and refuses a name that
already has one, so a timeout or an unclear reply never becomes a second purchase. Poll the name to
find out what happened. The one exception is a 4xx reply, a definite refusal with no task and no
charge (say, `429 NoMorePendingTasks`: this plan holds at most 10 pending tasks), which may be
created again under the same name.

## The roster batch

`roster/batch.py` makes monsters in bulk: concept (`nano-banana-pro`; stages 2 and 3 are
image-to-image edits of the previous stage, so a line keeps its look) -> a local background cut and
a hole check -> image-to-3d with `roster/model.json`. The designs are in `roster/subjects.py`;
`roster/roster.json` is the game's species list (`lune run tools/meshy/roster/dump`).

```sh
python tools/meshy/roster/batch.py plan  scorchling,scorchmoth       # what it would make, and the cost
python tools/meshy/roster/batch.py run   scorchling,scorchmoth --concepts
python tools/meshy/roster/batch.py sheet scorchling,scorchmoth       # art/compare/roster-concepts.png
python tools/meshy/roster/batch.py run   scorchling,scorchmoth       # the models
```

## Which settings, and why (A/B on Petalpaw, 2026-09-25)

Compared on one concept, rendered in Blender and in Studio:

| Setting | Verdict |
|---|---|
| `ai_model: meshy-7.1` | **Use.** Smooth shapes, parts attached, colours true to the concept. |
| `ai_model: meshy-6` + `remove_lighting` | No: paler, washed-out colours. `remove_lighting` only works on meshy-6; meshy-7.1 ignores it (the pilot's `true` did nothing). |
| `model_type: smart-topology` (`meshy-t2`, 15 instead of 30) | No: faceted surfaces, a crumpled tail, and the leaf sprout came out floating above the head. |
| `texture_resolution: 4k` | **Use.** Same price as 2k; the game bakes it down to 1024 (Roblox's cap), and a bigger source makes a cleaner bake. 8k (+5) adds nothing at 1024. |
| `enable_pbr: true` | Free, kept, but not used in game: on MeshMonster's runtime meshes the normal map drew creases along triangle edges (Roblox's tangents are not the ones the map was baked against) and roughness alone looked the same. Useful if monsters become uploaded meshes. |
| `image_enhancement: false` | **Use.** `true` restyles the input; our concepts already have the style. |
| `geometry_resolution: 2k/4k` (+5) | Not bought: it refines the high-poly surface, which the remesh to 6,000 faces throws away. |
| `target_polycount: 6000` | Kept. Close-ups show facets on the head outline; 10,000 would be smoother at the same price if the game ever shows monsters up close. |
| `texture_prompt` / `texture_image_url` | Not used: +10 credits, and the concept already guides the texture. |
| `save_pre_remeshed_model` | Not needed: the pre-remesh mesh (273k faces) comes without UVs or texture. |
| Concept model | `nano-banana-pro` (9). `nano-banana` (3) drew plush fur with a grey halo; `nano-banana-2` (6) plush fur. Only pro kept the pilot's smooth vinyl look. |
| Concept background | Flat grey, cut out locally (`batch.py matte()`). Meshy's `remove_background` cut pale bellies out as background four times (Petalpaw's white chest, then Mossbun twice and Pearlfin), and image-to-3d filled each hole with a dark patch. A clearly coloured pixel is never background, however close to the grey (the shaded rim of a lavender belly is), and a hovering monster's shadow, which the image model draws tinted in the monster's colour, is cut from under it (batch 3). |
| Multi-image to 3D | No (pilot): same price, paler colours, invented detail from generated side views. |

Per monster: 9 (concept) + 30 (model) = 39 credits, plus re-rolls (about 1 concept in 5 needed one in
the first batch).

## Costs (Meshy's pricing page, Sep 2026)

| Task | Credits |
|---|---|
| text-to-image | 3 (`nano-banana`), 6 (`nano-banana-2`), 9 (`nano-banana-pro`, `gpt-image-2`) |
| text-to-3d preview (mesh only) | 5 (`meshy-t2`) to 20 (`meshy-7.1`) |
| text-to-3d refine (texture) | 10 (2K/4K), 15 (8K) |
| image-to-3d | 5 (mesh only, `meshy-t2`) to 35 (8K textures, `meshy-7.1`) |
| retexture | 10 (2K/4K), 15 (8K) |
| remesh / rigging | 5 each |
| animations | 3 per action |

A concept first (`text-to-image`, 3 credits) and then `image-to-3d` from it keeps a whole set
of monsters in one style and spends 3D credits only on designs that were approved.
