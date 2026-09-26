# Pet genetics prototype (not in the game)

## Round 2 (2026-09-26): whole monsters, generated in parts that MOVE

Feedback on round 1 (below): mixing parents' parts on one body does not look good. The better use
of the generator is **many more, more detailed monsters**, each split into the body parts that
should animate: ears, eyes, mouth, wings, antennae, tail, legs, arms, head decoration.

| File | What |
|---|---|
| `monsters.py` | The requests: the baby form of every Monster Ranch line 1-42, its design words from `tools/meshy/roster/subjects.py`, the body plan, the Pet Simulator style, and the part list per archetype (at most 8) |
| `batch_lines_1_42.json` | Those 42 requests as run |
| `generate_monsters.luau` | Studio runner: `GenerationService:GenerateModelAsync` (text + `SchemaDefinition` groups, 20k tris), 8 at once, then publishes every part's mesh + texture (paced, with back-off) |
| `Animator.luau` | Procedural animation from part names: blink, ear twitch, tail wag, wing flap, antenna sway, mouth chatter, head nod, breathing, walk cycle. No skeleton: each part turns about a pivot found from its box |
| `MonsterLab.luau` | `arrangeLive()` lines the fresh models up facing the camera and animates them; `capture()` + `write_monster_library.py` store the published ids; `show()` rebuilds every monster from its assets and animates it |

Findings:

- **Detail:** at 20k triangles with explicit parts the monsters are far more detailed than round 1's
  cubes, and the archetype's body-plan words hold (foxes on four legs, moths hovering, slugs low).
- **Part per animation:** a part name the generator understands comes back as its own textured
  MeshPart almost every time. Measured sizes flag the misses: `Animator.check` turns off a blink
  when the `eyes` part holds more than eyes (5 of 40) and a chatter when `mouth` is bigger than a
  mouth (3 of 40). Round 1's fox put its head flower into `eyes`; naming a `head decoration` part
  fixed that for most.
- **Facing:** the generator faces each monster any way; `arrangeLive` turns each by where its eyes are.
- **Speed:** 42 monsters generated in about 10 minutes (8 at once, 21-45 s each). One "Moderation
  failed" on harmless words (Mudpuff, reworded twice) and one "generation failed" (re-run).
- **Publishing is the slow part, and its error hides:** `CreateAssetAsync` returns `UploadFailed` for
  everything; the real reason is its THIRD value. Here it was "Asset name length is invalid" (names
  over 50 characters), which looked like rate limiting. Each part is a mesh + a texture: ~560 uploads
  for 42 monsters at 3-20 s each.
- **Animation runs in Edit too** (`RunService.Heartbeat`), so the lab moves in the Studio viewport
  without pressing Play; the same `Animator` works on a client in a live game.

Where it ended (2026-09-26):

- **Published** (every part a mesh + texture asset, rebuilt from those assets and animated in Studio):
  anglit, bubblin, coralbun, emberslug, hollowisp, mossbun, staticat, thornbolt, scorchling,
  cindlet; acornling, moonmoth, petalpaw and lumipup were uploading at 15 s a piece.
- **Kept local only**, no upload (GLB + textures in `art/rbxgen/pm_<form>/`, git-ignored; review sheet
  `art/rbxgen/review_proto_monsters_local.png`): 25 more, generated through `tools/rbxgen/generate.luau`
  from `tools/rbxgen/batches/proto_monsters_local.json`. Missing: jellow (moderation refused it three
  wordings running), wickit and gravitoad (rate limit / interrupted).
- **The account was moderated mid-batch.** After ~150 uploads in two hours (plus a peer session's
  scenery uploads), every upload returned HTTP 403 "User is moderated" and existing assets stopped
  loading until the user cleared it. `generate_monsters.luau` now spaces uploads (`uploadGap`, 15-20 s)
  and HALTS all uploading at the first failure of any kind. Publish only what will be used.
- **Entering Play destroys unpublished generations.** Any Play/Stop in the Studio (anyone's) makes
  GenerateModelAsync content that was not yet published unreadable ("non-forkable") and later
  undrawable (grey, parts missing). Publish right after generating, and keep other sessions out of Play.
- **Generation is limited per minute:** 29 of 40 started together failed "Rate limit exceeded";
  the runner now retries after a minute and can space starts (`gap`).

Round 1 (below) stays as the record of the part-mixing test; its stats/skills genome still applies
if bred babies take one parent's whole species.

A test of two things: (1) Pet Simulator-style blocky pets made with Roblox's mesh generator, and
(2) a breeding engine where a baby inherits **physical parts, stats and skills** from both
parents. Nothing here is in `src/`, the Rojo projects or `tests/specs`, so it never ships and CI
never runs it.

| File | What |
|---|---|
| `Genetics.luau` | Pure genome engine (no Roblox APIs): founders, `breed`, `express`, `describe` |
| `test.luau` | Its tests: `lune run prototypes/pet-genetics/test` (9 tests) |
| `Assembler.luau` | Builds a pet Model from a phenotype by mixing species' parts |
| `PartLibrary.luau` | Per species: facing, body box, and each part's mesh/texture/offset/scale |
| `capture.luau` | Studio tool: reads the generated pets and returns the library as JSON |
| `write_library.py` | Writes `PartLibrary.luau` from that JSON |
| `Lab.luau` | Studio breeding lab: founders + litters in `Workspace.PetGeneticsLab` |

## How the engine works

Each pet is built from five part slots (**loci**): `body` (the cube with its face), `ears`
(ears, horns or a tuft), `tail`, `legs` and `back` (wings). A genome holds **two alleles per
locus**, one from each parent, each allele a species id (or `none` when a species lacks the part).

- **Looks:** the allele with the higher dominance shows; ties are a seeded coin flip. The other
  allele is carried silently, so grandchildren can show traits their parents did not (dragon x cat
  babies all have wings; about 1 in 4 of their own babies is wingless, as Mendel predicts).
- **Colour:** two codominant colour alleles; the pet is tinted toward their blend
  (`SurfaceAppearance.Color`, 35%).
- **Stats:** a baby gets a random point between its parents' base stats, x0.92-1.12, then its
  expressed parts add modifiers (corgi legs +3 speed, dragon wings +3 speed ...).
- **Skills:** up to 2 **innate** skills drawn from both parents (6% chance of a brand-new one),
  plus **part skills** that come with the part that shows (dragon wings: Glide, cat ears: Keen
  Ears, tiger tail: Stripe Dash). What a pet looks like and what it can do always agree.
- **Mutation:** 1% per allele to become another species' part (a dragon x cat grandchild on
  tiger legs).

Breeding is deterministic per seed, so a server can store just the genome and rebuild the pet.

## Running the lab in Studio

Put `Genetics`, `Assembler`, `PartLibrary` and `Lab` as ModuleScripts in
`ServerStorage.PetGeneticsLab`, then in the command bar:

```lua
require(game.ServerStorage.PetGeneticsLab.Lab).run()                -- founders + 4 litters
require(game.ServerStorage.PetGeneticsLab.Lab).cross("tiger", "chick", 6, 900)
```

## Generating a species

`generate_mesh` with `segmentation = "explicit"` and `partNames` gives one textured MeshPart per
part. Pass the names as a comma string (`body, ears, tail, legs`): a JSON array came back as part
names like `["body"`. Prompts used (size 5 x 4.5 x 5, 4000 tris):

- dragon: "cute cube-shaped baby dragon pet, blocky rounded square body with a big cute face and big black eyes, small green bat wings, tiny horns, stubby legs, short tail, Pet Simulator toy style, bright green, toon" - parts `body, horns, wings, tail, legs`
- cat: "cute cube-shaped grey cat pet, ... pointy cat ears, stubby legs, curled tail, ..." - `body, ears, tail, legs`
- dog: "cute cube-shaped brown puppy dog pet, ... tongue out, floppy brown ears, stubby legs, short wagging tail, ..."
- corgi: "cute cube-shaped orange and white corgi dog pet, ... tall pointy fox-like ears, very short stubby legs, fluffy little tail, ..."
- tiger: "cute cube-shaped orange tiger cub pet with black stripes, ... small round ears, stubby legs, long striped tail, ..."
- chick: "cute cube-shaped yellow baby chick pet, ... small orange beak, little feather tuft on top of the head, tiny yellow wings on the sides, small tail feathers, stubby orange legs, ..." - `body, tuft, wings, tail, legs`

Then tag each model `PetSpecies = "<id>"`, run `capture.luau`, and `write_library.py` the JSON.

## Findings

- **The style works.** All six came out as convincing Pet Simulator-style cube pets on the first
  try; a dragon's head sits on a small body (upright), the others stand on four stubby legs.
- **Segmentation mostly works but guesses.** The chick's "tail" came back as its **beak** (on the
  face side), which also turned the chick backwards when facing was read from the tail. Fixed
  with a per-species override in `capture.luau` (the beak becomes a `face` piece that rides on
  the chick's body). Always look at each species from the front before capturing.
- **Facing is random** per generation (four of six faced +Z, one +X, one -Z): the capture faces
  every species to -Z from the tail's side.
- **Seams:** a segmented body has a hole where a part was cut off (a cat body wearing dragon horns
  shows the dip where its own ears were). Borrowed parts mostly cover it; a real version would
  generate bodies with no ears/tail as a separate `body` pass, or cap the holes in Blender.
- **Runtime generation is not the way to persist bred pets.** `GenerationService:GenerateModelAsync`
  can make a unique pet on the server at breed time (custom `SchemaDefinition` groups, optional
  image conditioning), but the result is not a saved asset: it cannot be reloaded on another
  server or another day, and it is rate-limited and moderated. The part library + genome approach
  stores only the genome and rebuilds the same pet anywhere, instantly. Runtime generation could
  still serve rare "unique mutation" events, as a later experiment.
- **Tinting:** a MeshPart's `Color` does nothing over a texture. `SurfaceAppearance.Color` tints
  the texture, but setting its `ColorMap` needs plugin/Studio security; a live game would clone
  SurfaceAppearance templates prepared in Studio (one per part) and set `.Color` at runtime.

## Before this could go into Monster Ranch

The game's monsters are Meshy models rigged per body type, and today's breeding (`Logic/Breeding`)
picks one parent's species. Moving to part-built pets means: a part library per monster line
(separately generated, seam-free parts), rigs that work across mixed parts (or simple tween
animation for cube pets), the genome saved in the monster record, and `Breeding.Roll` returning a
genome. That is a design decision for the roadmap, not something this prototype decides.
