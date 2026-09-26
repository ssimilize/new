# Monster Ranch VFX catalogue (draft 2026-09-25)

Everything the first pass covers, the sprites each effect needs, and the budget. Presets are data
(`Config/Vfx.luau`), built by one client module (`Visuals/Vfx.luau`); sprites are tintable white
unless marked (c) = own colour.

## Sprite sheet to produce (the winning method makes all of these in one consistent style)

| sprite     | uses                                                        |
|------------|-------------------------------------------------------------|
| flame      | ember aura, scorched, raid portal braziers, rebirth         |
| ember      | tiny round spark: ember aura, scorched, plasma, forge-like  |
| droplet    | tide aura, soaked, surf shack                                |
| bubble     | tide aura, frozen/pearl, trading hub portal                 |
| leaf       | sprout aura, blossom                                        |
| petal (c)  | blossom mutation, Showtime Stage, sprout aura (flowers)     |
| bolt       | spark aura, charged, plasma                                 |
| twinkle    | 4-point star: light aura, starstruck, shiny, Star Altar     |
| star5      | 5-point cartoon star: starstruck, level-up, Hall of Fame    |
| glow       | soft round orb: every aura's base glow, glow mutation, portals |
| wisp       | gloom / void aura, shadow, portal smoke                     |
| smoke      | soft puff: scorched, hatch/evolve poof, dust                |
| pebble     | stone aura (small rocks drifting up), arena dust            |
| snowflake  | frosted, frozen                                             |
| heart (c)  | pet / feed feedback (replaces World.luau's plain hearts)    |
| coin (c)   | coin burst (replaces World.luau's plain coins)              |
| ring       | shockwave ring: hatch, evolve, level-up, rebirth, portal pulse |
| swirl      | portal vortex (flat, rotating, Orientation = FacingCameraWorldUp / VelocityPerpendicular) |
| rune       | circular sigil: Star Altar, raid portal floor, evolve       |
| rainbow (c)| prismatic mutation, rainbow variant                          |

## Monsters (MonsterModel.Build: mesh and placeholder alike)

- Element aura, one per element, low rate (live particles <= ~8 per monster):
  ember (flame + ember rising), tide (droplet + bubble orbiting down), sprout (leaf + petal drifting),
  spark (bolt flicker + ember sparks), stone (pebble floating up + dust), gloom (wisp + glow motes),
  light (twinkle + glow halo), void (wisp swirling inward + dark glow). Two-element monsters mix
  (half rate each). Hovering body types (moth, sprite) emit from the body centre, others from Feet.
- Mutations (replace today's Fire/Sparkles/Smoke placeholders, which mesh monsters never got):
  soaked (drips), scorched (smoke + embers), charged (bolt sparks), frosted (snowflake), starstruck
  (star5 + twinkle), shadow (dark wisp), prismatic (rainbow), glow (glow motes), blossom (petals),
  sunkissed (warm glow + twinkle), frozen (snowflake + bubble ice), plasma (bolt + ember purple),
  pearl (bubble + twinkle white), tropical (petal + droplet teal).
- Shiny (variant 1): gold twinkles; Rainbow (variant 2): rainbow twinkles.
- Rarity: epic/legendary get a faint ground glow (glow sprite, Orientation flat on the floor).
- Budget: low graphics = aura off for other players' monsters, mutations halved; never more than
  ~40 emitting monsters near the camera (distance cull through the existing pen cap).

## World landmarks (client-side, found by hub building id)

| landmark        | effect                                                                 |
|-----------------|------------------------------------------------------------------------|
| raidPortal      | swirl vortex in the arch + glow core + wisp smoke at the base + pulse ring every few s |
| hubPortal       | blue swirl + bubbles rising + twinkles                                  |
| Sky Gate portal | cloud-white swirl + twinkle + leaf/feather drift                        |
| gate (Expedition)| fireflies (glow, yellow-green) drifting round the arch                 |
| starAltar       | rune on the floor rotating + twinkles rising + star5 on rebirth         |
| showStage       | petals/confetti + spotlight glow                                        |
| hallOfFame      | gold twinkles round the statues                                         |
| arena / championsArena | dust puffs + banner embers                                      |
| surfShack       | spray droplets + bubbles                                                |
| eggShop         | soft sparkles round the sign                                            |
| workshop        | chimney smoke + ember sparks                                            |

## Moment bursts (one-shot :Emit, pooled)

hatch (Eggs.Hatched: smoke poof + ring + star5 + rarity-coloured twinkles), evolve (Monsters.Evolved:
glow column + ring + rune + element sprites), monster level-up (Monsters.LevelUp: star5 + ring),
ranch level-up (Progression.LevelUp: ring + confetti round the player), rebirth (Rebirth.Rebirth:
Star Altar column of twinkles + ring), coins / hearts (existing World.luau bursts get the new sprites).
