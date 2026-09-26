# Monster Ranch particle sprites: production set (Codex cartoon style)

Decided 2026-09-26: Codex (gpt-6-astra image tool, round-2 cartoon brief) won the in-engine
head-to-head against procedural. Style = the shared style block in
art/vfx/bakeoff/gpt-cartoon/PROMPT.md, word for word, with the kindlefox concept attached AND the six
approved round-2 sprites attached as style anchors (art/vfx/bakeoff/gpt-cartoon/*_color.png).

Output: art/vfx/sprites/<name>.png (own colour, 256x256 RGBA, 80% fill, colour bled into transparent
pixels) and, for sprites marked TINT, also <name>_grey.png (3 tones kept as greys: outline 0.40,
shade 0.60, base 0.80, light 0.95, highlight 1.0). manifest.json lists every file.

## Carried over from round 2 (copy, do not regenerate)

| name    | from                         | tint |
|---------|------------------------------|------|
| flame   | gpt-cartoon/flame_color.png  |      |
| droplet | gpt-cartoon/droplet_color.png| TINT |
| leaf    | gpt-cartoon/leaf_color.png   | TINT |
| bolt    | gpt-cartoon/bolt_color.png   |      |
| star    | gpt-cartoon/star_color.png   | TINT | (4-point twinkle)
| wisp    | gpt-cartoon/wisp_color.png   | TINT | (gloom puff)

## New (Codex, same brief; colours are base / shade / light / outline)

| name      | subject (after the style block)                                                        | colours | tint |
|-----------|-----------------------------------------------------------------------------------------|---------|------|
| ember     | one small round glowing ember spark, a plump circle with a tiny flame flick on top        | #FFB547 #F57A45 #FFF1B3 #B8401F | |
| bubble    | one round soap/water bubble: thick coloured rim, clear-ish lighter centre, big white shine | #9FD7FF #4AA6F0 #E6F6FF #1F5FA8 | TINT |
| petal     | one cherry-blossom petal, plump heart-tipped oval, soft notch at the top                  | #FF9EC7 #F06FA8 #FFE0EE #C4457F | TINT |
| pebble    | one chunky rounded rock chunk with 2 flat facets                                          | #A68B70 #7E6650 #E6D9C8 #54402E | TINT |
| voidswirl | one spiral of dark energy, 3 curling arms around a dark centre, teal edge light           | #3B2E6E #241A4A #5CE1E6 #140E2E | |
| star5     | one plump five-point cartoon star, rounded tips                                          | #FFD447 #F2A93B #FFF6D6 #C98A1A | TINT |
| heart     | one plump cartoon heart                                                                   | #FF6F9C #E0487A #FFC2D6 #A82857 | |
| coin      | one gold coin seen straight on, thick rim, a simple paw-print emboss in the middle       | #FFD447 #E0A91E #FFF1B3 #9A6B12 | |
| snowflake | one chunky six-arm snowflake, rounded arm ends, small side branches                      | #DFF4FF #9FD7FF #FFFFFF #4A8FC7 | TINT |
| prism     | one four-point twinkle star filled with a rainbow gradient in 5 flat bands (red orange yellow green blue) | rainbow, outline #7A4FB0 | |
| confetti  | one short curled paper confetti ribbon (a small twisted strip)                            | #FFFFFF #D6D6D6 #FFFFFF #8C8C8C (white) | TINT |
| ring      | one thick cartoon shockwave ring (a donut outline seen straight on), open empty centre    | white #FFFFFF / #D6D6D6 / outline #8C8C8C | TINT |
| puff      | one cartoon smoke "poof" cloud: 4 round bumps, no tail                                    | white #FFFFFF / #D9D9D9 / #F2F2F2 / outline #9A9A9A | TINT |
| swirl     | one flat portal vortex: 4 curved arms spiralling into the centre, seen straight on        | white #FFFFFF / #D6D6D6 / outline #8C8C8C | TINT |
| rune      | one circular magic sigil: double ring with 6 small simple runes and a star in the middle, line art with thick strokes | white #FFFFFF / outline #8C8C8C | TINT |

Grey-TINT sprites that are white by design (confetti, ring, puff, swirl, rune): the colour file IS
the tintable file; also write <name>_grey.png as a copy.

## Drawn in code (tools/vfx/procedural.py)

| name | subject | tint |
|------|---------|------|
| glow | soft round radial glow orb (the one sprite that is ALL glow, no outline) | TINT |
