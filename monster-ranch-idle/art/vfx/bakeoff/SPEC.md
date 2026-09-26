# Particle sprite bake-off (2026-09-25)

Goal: find the best-looking, cheapest, fastest way to make particle textures for Monster Ranch Idle
(cute, bright, stylized Meshy-made monsters; a sunny cartoon ranch). Every method makes the SAME six
test sprites; they are then shown on identical ParticleEmitters in Roblox Studio side by side.

## The six sprites

| name    | used for                              | look                                                             |
|---------|---------------------------------------|------------------------------------------------------------------|
| flame   | ember element, scorched, portals      | a single stylized flame tongue, soft bright core, tapering tip    |
| droplet | tide element, soaked                  | a water drop, glossy highlight, readable at 20 px                 |
| leaf    | sprout element, blossom               | one small leaf with a midrib, clean silhouette                    |
| bolt    | spark element, charged                | a jagged lightning zigzag, bright core, slight glow               |
| star    | light element, starstruck, shiny      | a 4-point twinkle/sparkle star with a soft glow halo              |
| wisp    | gloom / void, shadow, portal smoke    | a soft curling smoke/magic wisp puff, no hard edges               |

## Deliverables per method (folder `art/vfx/bakeoff/<method>/`)

- `<sprite>.png` for each of the six: 256x256 RGBA, transparent background, subject centred and
  filling ~80% of the frame, no text/border/drop-shadow/background remnants. This is the TINTABLE
  version: white / light-grey (luminance carries the shading), because the game tints one sprite per
  element through ParticleEmitter.Color.
- `<sprite>_color.png` (optional): the same sprite in its natural colour (flame orange, droplet blue,
  leaf green, bolt yellow, star gold-white, wisp violet), if the method produces colour naturally.
- `contact.png`: all delivered sprites on a dark (#202028) and a light (#E8E8E8) strip, for a quick look.
- `result.json`: `{ "method", "wall_minutes" (your total time incl. iteration), "generation_seconds"
  (machine/API time only), "cost" ({ "usd": n } or { "meshy_credits": n } or 0), "attempts",
  "scripts" (paths), "notes" (what worked, what failed, how repeatable it is, how hard a NEW sprite
  would be to add) }`.

Alpha matters: Roblox draws a particle texture with its alpha; a black or grey fringe around the
shape shows up as a dirty halo. For art drawn on black, derive alpha from brightness and
un-premultiply the colour; check edges on BOTH the dark and the light strip.

Rules: never print or log an API key. Do not upload anything to Roblox (the lead uploads).
Do not touch src/, tests/ or git.
