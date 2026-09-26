# Codex round 2: cartoon particle sprites (precise brief)

Attach as style reference (codex exec -i): art/meshy/kindlefox-concept/image_0.png (a monster from
the game: soft vinyl-toy 3D cartoon, rounded chunky forms, warm saturated colours, glossy highlights).

## Shared style block (prepend to EVERY sprite prompt, word for word)

Game particle sprite for a cute cartoon monster-ranch game on Roblox. Match the attached monster's
style: soft, rounded, chunky, toy-like, friendly, saturated candy colours. Draw it as a flat 2D
cartoon sticker, NOT realistic and NOT painterly:
- bold simple silhouette that reads when shrunk to 24 pixels; thick rounded shapes, no thin wisps
- cel shading with exactly 3 flat tones (base, one darker shade, one lighter tint), hard edges between
  tones, no gradients, no airbrush, no texture, no noise
- a clean outline 4-6% of the sprite width, in a darker, saturated shade of the sprite's own colour
  (never black, never grey)
- one or two small pure-white highlight shapes (a rounded blob or a short curved stroke), top-left
- NO outer glow, NO bloom, NO soft haze, NO drop shadow, NO sparkles or extra small objects around it
- exactly ONE object, centred, filling about 80% of a square canvas, straight-on front view, flat 2D
- transparent background (PNG with alpha); if transparency is impossible, pure flat #000000 black
- no text, no border, no frame, no watermark

## Per sprite (after the style block)

1. flame: one cartoon fire flame, a teardrop body with three rounded tongues curling up, pointing
   straight UP. Outer tones orange #F57A45 / shade #D9522A, inner core yellow #FFD447 with a small
   pale-yellow #FFF1B3 centre. Outline #B8401F.
2. droplet: one cartoon water drop, round bottom and pointed tip straight UP, chubby and plump.
   Base #4AA6F0, shade #2F7FD1, light #9FD7FF, outline #1F5FA8, a big white highlight crescent.
3. leaf: one cartoon leaf, plump oval with a pointed tip, tip to the top-right at 45 degrees, short
   stem bottom-left, one curved centre vein as a lighter line, NO other veins. Base #62BF55, shade
   #3F9A3A, light #8EE07A, outline #2C6E2A.
4. bolt: one cartoon lightning bolt, a THICK chunky zig-zag with exactly two bends, like a sticker
   icon, pointing down, vertical. Base #F6CD3A, shade #E0A91E, light #FFF4C2, outline #B07A12.
5. star: one cartoon four-point twinkle star with plump curved (concave) sides and rounded tips,
   symmetrical, points up/down/left/right. Base #FFD447, shade #F2A93B, light #FFF6D6, outline #C98A1A.
6. wisp: one cartoon puff of magic smoke: three overlapping round cloud bumps with a single curly
   spiral tail at the top, like a cartoon "poof" cloud. Base #9168D0, shade #6E48B0, light #C9A8FF,
   outline #4E2F8A.

## Notes for the runner
- Generate all six in ONE codex session so the style stays consistent across them (say so in the
  prompt: "make six images in the same style, one per sprite below").
- Tintable grey versions: derive by desaturating the colour sprite (keep the 3 tones as 3 greys,
  base ~0.80, shade ~0.60, light ~0.95; outline ~0.40).
