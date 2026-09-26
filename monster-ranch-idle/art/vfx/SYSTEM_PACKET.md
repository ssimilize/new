# Packet: the VFX system (Monster Ranch Idle) - particle effects for monsters, landmarks, moments

Repo: C:\Users\sim\Documents\monster ranch\monster-ranch-idle (Luau + Rojo; read CLAUDE.md one level up
and in this folder first - the architecture, the update pattern and the test-harness gotchas). Branch
update-3.2-frostbite-glacier. Another Claude session is active in this repo (tools/rbxgen,
prototypes/): touch only the files this packet names or creates, and do NOT git add/commit.

## What exists
- Every monster in the game is built by `src/client/Visuals/MonsterModel.luau` `MonsterModel.Build`
  (pens via Controllers/World.luau, mounts Controllers/Riding.luau, Showtime, UI/Components/
  ViewportMonster.luau). Forms with a published mesh go through `Visuals/MeshMonster.luau` and return
  early: mesh monsters (135 of them, the real art) currently get NO element, mutation or shiny effect.
  The placeholder path has old Fire/Smoke/Sparkles/ParticleEmitter decorations for elements,
  mutations (`appearance.muts`) and variant 1 (shiny) / variant 2 (Rainbow attribute).
- `Controllers/World.luau` has `buildFx` coin/heart bursts (makeEmitter/burst), `lowGraphics` from
  `profile.Settings.lowGraphics`, `goldTint` (statues) that destroys emitters, `night`.
- Hub buildings: server `Systems/World/Build.luau` makes `Workspace.<world>/Hub/Buildings/<id>`
  Models (attrs HubId...) from `Config.World.Hub` (ids: eggShop, feedStore, trading, gate,
  hallOfFame, arena, market, starAltar, showStage, surfShack, clubPlaza, championsArena, raidPortal,
  racetrack, hubPortal, workshop); `Systems/World/Dress.luau` swaps in 3D meshes (Body/Door stay as
  invisible anchors). The Sky Gate portal part is found in `Controllers/SkyIslands.luau`
  (gate:FindFirstChild("Portal"), attribute SkyGate). Read these to find stable anchor parts.
- Events: `Eggs.Hatched`, `Monsters.Evolved`, `Progression.LevelUp` (ctx.Net:On), action returns of
  `Monsters.LevelUp` (UI/Screens/MonsterDetail.luau) and `Rebirth.Rebirth` (UI/Screens/Rebirth.luau).
- Config.Elements (ember tide sprout spark gloom stone light void), Config.Mutations.List (14 incl.
  combos), Config.Rarities.

## Design decisions already made (do not revisit)
- Sprites: Codex cartoon sprites, one per name in art/vfx/SPRITES.md (flame droplet leaf bolt star
  wisp ember bubble petal pebble voidswirl star5 heart coin snowflake prism confetti ring puff swirl
  rune glow). Some have a `_grey` tintable twin. Ids are uploaded by the lead into a GENERATED module
  `src/shared/Config/VfxSprites.luau`: `return { [name] = { color = "rbxassetid://..", grey = "rbxassetid://.." | nil } }`.
  Create it now with the six ids below and leave the rest missing; the runtime must fall back
  gracefully (skip that emitter, never error) for a missing sprite.
    flame   color rbxassetid://107692587402219
    droplet color rbxassetid://73677735848345  grey rbxassetid://82627815866475
    leaf    color rbxassetid://140636343652703 grey rbxassetid://140216378977142
    bolt    color rbxassetid://87865711460500
    star    color rbxassetid://98416133973738  grey rbxassetid://92893789248192
    wisp    color rbxassetid://99181613521488  grey rbxassetid://87624842102539
- Engine tuning learned in Studio (hard rules): daytime LightEmission 0.15-0.3 (0.8-1 washed every
  sprite to white on the sunny sky); glow above 0.5 only for portal cores / night; fire uses the
  own-colour sprite (a tinted grey flame goes pastel); tinted grey sprites only for neutral shapes and
  where one sprite serves many colours; Size and Transparency are always NumberSequences (fade in
  fast, out slow); :Emit(n) for bursts, never toggling Enabled; ZOffset to lift bursts out of meshes.
- Particles only simulate near the camera, so off-screen auras are cheap; still budget live particles
  (Rate x Lifetime.Max) <= 8 per monster aura, <= 12 with two mutations, landmark <= 60.

## Build
1. `src/shared/Config/Vfx.luau` - all effects as DATA: a compact emitter spec ({ sprite, grey?, color
   (hex or ColorSequence keys), rate, lifetime {min,max}, size keys, transparency keys, speed,
   spread, accel, drag, rot, rotSpeed, lightEmission, lightInfluence, orientation, shape, zOffset,
   lockedToPart, emit (burst count) ... }) and tables: `Auras[element]`, `Mutations[mutationId]`,
   `Variants.shiny / Variants.rainbow`, `Rarity` (epic/legendary faint ground glow), `Landmarks[hubId]`
   (+ `skyGate`), `Bursts[name]` (hatch, evolve, monsterLevelUp, ranchLevelUp, rebirth, coins,
   hearts). Two-element monsters mix both auras at half rate. Content per art/vfx/CATALOGUE.md -
   design the numbers yourself within the rules above. Header comment in the repo's style.
2. `src/client/Visuals/Vfx.luau` - builds emitters from specs. API (adjust if you must, document it):
   `Vfx.AttachMonster(model, appearance)` (anchor on Root / Feet / Head attachments; hovering body
   types from the body centre; scales sizes with the model's Height), `Vfx.AttachLandmark(instance,
   id)`, `Vfx.Burst(name, cframeOrPosition, opts?)` (pooled emitters, :Emit), `Vfx.SetQuality(low)`,
   `Vfx.Clear(model)`. Must work in the Lune test mock (no errors when textures/services are absent).
3. Hook into `MonsterModel.Build` for BOTH the mesh and placeholder paths (opts.vfx == false skips;
   ViewportMonster passes false - particles don't render in ViewportFrames). Remove the placeholder's
   old Fire/Smoke/Sparkles/ParticleEmitter code for mutations and variants that Vfx now covers (keep
   geometry and PointLights). Statues (goldTint) must still end up with no emitters.
4. Landmarks: attach on the client when the world/hub buildings exist (World controller or a small
   new controller registered in src/client/Manifest.luau), including the Sky Gate portal. Re-attach
   safely if Dress swaps parts later (anchor to something Dress keeps, or re-scan).
5. Bursts wired to the events above; hatch burst where the new monster appears in the world (or at
   the player's character if it is not placed yet), evolve / monster level-up at that monster's model
   in the pen (World keeps entries by id), ranch level-up and rebirth around the character (rebirth
   also at the Star Altar). World.luau coins/hearts switch to the coin/heart sprites (keep the
   plain fallback when the sprite is missing).
6. lowGraphics: auras only for monsters on your own plot, mutation rates halved, landmark rates
   halved, bursts halved (World already reads the setting - route it to Vfx.SetQuality).
7. Tests: `tests/specs/Vfx.spec.luau` - config integrity (every element and every mutation in
   Config has an entry; every landmark id is a Config.World.Hub id or skyGate; every emitter sprite
   name is in the SPRITES list; only whitelisted keys; per-aura/per-landmark live-particle budget;
   LightEmission rule), plus client behaviour through the existing harness (building a monster with
   an element and a mutation attaches emitters; ViewportMonster attaches none; lowGraphics drops
   other-plot auras; a missing sprite does not error). Mutation-check at least two tests (break the
   code, see them fail, restore).
8. Docs: keep file headers accurate; add Vfx to docs/ARCHITECTURE.md (a short section) and a line in
   CLAUDE.md "How the code fits together" pointing at tools/vfx + art/vfx/SPRITES.md.

## Checks (all must pass; stylua/selene are NOT installed on this PC - hand-format: tabs, 140 cols)
`lune run tests/lint`, `rojo build -o build.rbxl`, `rojo build hub.project.json -o hub.rbxl`,
`lune run tests` (full suite, ~2-3 min; was 536 green). Report: files touched, API, test counts,
anything you could not do. Do not commit. Do not use Roblox Studio (the lead verifies in Studio).
