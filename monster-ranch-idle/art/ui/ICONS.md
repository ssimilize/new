# UI item and currency icons

The icon table for `tools/ui/codex_icons.py`. Every row is one 256 px icon generated with the Codex
CLI image tool in the same cartoon style as the particle sprites (`art/vfx/SPRITES.md`): the
attachments are the Kindlefox concept and the six approved particle anchors.

- **Currencies** and **Items** are written by hand.
- **Decor**, **Pen themes** and **Accessories** are synced from `src/shared/Config` by
  `python tools/ui/codex_icons.py sync`: new config entries get a row with a default subject, rows
  already here are never touched (edit a subject freely), and rows whose id left the config are
  reported, not deleted.
- Eggs are not here on purpose: their icons are rendered from the 3D egg models by another packet,
  and until then `MonsterIcon.egg` keeps its procedural drawing.

Row name = `<group>_<id>`; the game looks icons up by that name (`src/client/UI/Art/Icons.luau`).
Colours: main, second, outline. The outline is always the UI ink.

## Style block (sent word for word with every icon)

Game UI item icon for a cute cartoon monster-ranch game on Roblox. Match the attached images: the
first is a monster from the game (soft, rounded, chunky vinyl-toy look), the others are approved
particle sprites from this game, and they set the EXACT drawing style. Draw it as a flat 2D cartoon
sticker, NOT realistic, NOT painterly, NOT 3D-rendered:
- one chunky, instantly readable object with a bold silhouette that still reads at 32 pixels; big
  simple shapes, few details, no thin parts
- soft cel shading: 3 flat tones (base, one darker shade, one lighter tint) with clean edges, no
  noisy texture, no airbrush
- a thick, even, near-black outline (#1B1B1B), about 5% of the icon width, around the whole object
  and its main inner shapes
- one or two small pure-white highlight shapes, top-left
- a slight three-quarter view from the front and a little above, so the object has volume
- NO drop shadow, NO glow, NO sparkles or extra small objects around it, NO ground, NO background
- exactly ONE object, centred, filling about 85% of a square canvas
- transparent background (PNG with alpha); if transparency is impossible, pure flat #000000 black
- no text, no letters, no numbers, no border, no frame, no watermark

## Currencies

| name | subject | colours |
|---|---|---|
| cur_coin | a thick round gold coin with a raised rim and a simple embossed paw print in the middle | #F2B01E, #FFE38A, #1B1B1B |
| cur_gem | a faceted cut gemstone, cushion shaped with big flat facets | #E8436F, #FFB2DA, #1B1B1B |
| cur_food | a plump round red berry with two small green leaves on top | #E5484D, #43B649, #1B1B1B |
| cur_treat | a bone-shaped baked biscuit treat with a few sugar dots | #E7A33B, #FFE3B0, #1B1B1B |
| cur_stardust | a small tied cloth pouch overflowing with glittering purple stardust and one four-point star on the pouch | #8B6AD8, #D9C9FF, #1B1B1B |
| cur_starshard | a chunky five-point star-shaped crystal shard, faceted like a gem | #FFD447, #FFF6C2, #1B1B1B |
| cur_ribbon | a prize rosette ribbon: round pleated rosette with two tails hanging below | #E5486E, #FFD447, #1B1B1B |
| cur_friendship | a plump rounded heart with a small shine | #EF6FA8, #FFC6DF, #1B1B1B |
| cur_token | a round event token coin with a big snowflake embossed on its face | #7CC7FF, #E6F6FF, #1B1B1B |
| cur_xp | a green five-point star badge with a bold upward arrow on it | #43B649, #B8F0A0, #1B1B1B |
| food_sweet | a cluster of three plump pink sweet berries with a green leaf | #EF6FA8, #FFC6DF, #1B1B1B |
| food_spicy | a curved glossy red fire pepper with a green stem | #E5484D, #FF9A7A, #1B1B1B |
| food_savory | a chunky brown root vegetable (like a stubby sweet potato) with a leafy green top | #A0703D, #D9A56B, #1B1B1B |
| food_sour | a round zesty lime, half cut open to show its segments | #C3D93B, #F0F7A8, #1B1B1B |
| token_frostfall | a round event token coin with a big snowflake embossed on its face | #7CC7FF, #E6F6FF, #1B1B1B |
| token_lunarlanterns | a round event token coin shaped like a glowing red paper lantern | #FF7A45, #FFD447, #1B1B1B |
| token_springbloom | a single large pink flower petal, soft and rounded | #FF9EC7, #FFE0EE, #1B1B1B |
| token_summersplash | a scalloped seashell (scallop shape) | #FFB347, #FFE3B0, #1B1B1B |
| token_harvestmoon | a wrapped candy shaped like a crescent moon, with twisted wrapper ends | #F08A4B, #FFD8A8, #1B1B1B |

## Items

| name | subject | colours |
|---|---|---|
| item_heirloom | a golden heart-shaped locket pendant on a short chain loop, with a small star gem set in the middle | #F4C43A, #8B6AD8, #1B1B1B |
| item_totem_rain | a short carved wooden totem pole topped by a fat rain cloud with three drops | #A0703D, #7CC7FF, #1B1B1B |
| item_totem_thunder | a short carved wooden totem pole topped by a dark storm cloud with a yellow lightning bolt | #A0703D, #FFD447, #1B1B1B |
| item_totem_starfall | a short carved wooden totem pole topped by a big glowing yellow star | #6B5BD6, #FFD447, #1B1B1B |
| item_crate | a sturdy wooden supply crate with gold corner bands and a gold star on the front | #C98B2E, #FFD447, #1B1B1B |
| item_trophy | a shiny gold trophy cup with two handles on a short dark base | #FFD447, #C58508, #1B1B1B |
| item_star | a plump rounded five-point gold star | #FFD447, #FFF1B3, #1B1B1B |

## Decor

| name | subject | colours |
|---|---|---|
| decor_hay_bale | a Hay Bale, a pen decoration for a monster ranch | #E3C565, #F2E5BA, #1B1B1B |
| decor_water_trough | a Water Trough, a pen decoration for a monster ranch | #4FB6F2, #B0DEF9, #1B1B1B |
| decor_flower_bed | a Flower Bed, a pen decoration for a monster ranch | #EF6FA8, #F8BED8, #1B1B1B |
| decor_scratch_post | a Scratch Post, a pen decoration for a monster ranch | #A0703D, #D4BFA8, #1B1B1B |
| decor_mud_puddle | a chunky, glossy chocolate-brown Mud Puddle with a thick raised muddy rim and two round mud bubbles, a pen decoration for a monster ranch, seen from the front and a little above | #7A5A3A, #C3B5A6, #1B1B1B |
| decor_lantern | a Glow Lantern, a pen decoration for a monster ranch | #FFD447, #FFECAC, #1B1B1B |
| decor_fountain | a Tiny Fountain, a pen decoration for a monster ranch | #7FD0F5, #C5EAFA, #1B1B1B |
| decor_rainbow_arch | a Rainbow Arch, a pen decoration for a monster ranch | #FF7AC8, #FFC3E6, #1B1B1B |
| decor_crystal_cluster | a Crystal Cluster, a pen decoration for a monster ranch | #A9DEFF, #D8F0FF, #1B1B1B |
| decor_snow_globe | a Snow Globe, a pen decoration for a monster ranch | #E6F6FF, #F4FBFF, #1B1B1B |
| decor_gift_pile | a Gift Pile, a pen decoration for a monster ranch | #E5484D, #F3ADAF, #1B1B1B |
| decor_golden_statue | a Golden Statue, a pen decoration for a monster ranch | #F4C43A, #FAE4A6, #1B1B1B |
| decor_paper_lantern | a Paper Lantern, a pen decoration for a monster ranch | #E5484D, #F3ADAF, #1B1B1B |
| decor_moon_gate | a Moon Gate, a pen decoration for a monster ranch | #C98B2E, #E7CBA1, #1B1B1B |
| decor_jack_o_lantern | a Jack-o'-Lantern, a pen decoration for a monster ranch | #F08A4B, #F8CAAE, #1B1B1B |
| decor_haunted_tree | a Haunted Tree, a pen decoration for a monster ranch | #3A2D55, #A6A0B2, #1B1B1B |
| decor_beach_ball | a Beach Ball, a pen decoration for a monster ranch | #FF6B6B, #FFBCBC, #1B1B1B |
| decor_tiki_torch | a Tiki Torch, a pen decoration for a monster ranch | #D9A066, #EED4BA, #1B1B1B |
| decor_tulip_patch | a Tulip Patch, a pen decoration for a monster ranch, flat and low on the ground | #FF6FA5, #FFBED6, #1B1B1B |
| decor_bloom_arch | a Bloom Arch, a pen decoration for a monster ranch | #FFB3D1, #FFDDEA, #1B1B1B |
| decor_sandcastle | a Sandcastle, a pen decoration for a monster ranch | #EFD08A, #F8EACA, #1B1B1B |
| decor_beach_umbrella | a Beach Umbrella, a pen decoration for a monster ranch | #FF6B6B, #FFBCBC, #1B1B1B |
| decor_shell_pile | a Shell Pile, a pen decoration for a monster ranch | #F7C6D9, #FBE5EE, #1B1B1B |
| decor_tide_pool | a Tide Pool, a pen decoration for a monster ranch, flat and low on the ground | #3FB6D9, #A9DEEE, #1B1B1B |

## Pen themes

| name | subject | colours |
|---|---|---|
| theme_wood | a small square patch of ground with a short stretch of Wooden Fence standing along its back edge, like a swatch for a ranch pen style (fence colour first, ground second) | #9C6130, #A2D776, #1B1B1B |
| theme_stone | a small square patch of ground with a short stretch of Stone Wall standing along its back edge, like a swatch for a ranch pen style (fence colour first, ground second) | #8E8E8E, #B8C98A, #1B1B1B |
| theme_candy | a small square patch of ground with a short stretch of Candy Fence standing along its back edge, like a swatch for a ranch pen style (fence colour first, ground second) | #FF8FC8, #FFE3F1, #1B1B1B |
| theme_snowglobe | a small square patch of ground with a short stretch of Snow Globe themed fence standing along its back edge, like a swatch for a ranch pen style (fence colour first, ground second) | #BFE9FF, #F2FAFF, #1B1B1B |
| theme_boardwalk | a small square patch of ground with a short stretch of Beach Boardwalk themed fence standing along its back edge, like a swatch for a ranch pen style (fence colour first, ground second) | #D9A066, #F4DFA6, #1B1B1B |
| theme_lantern_garden | a small square patch of ground with a short stretch of Lantern Garden themed fence standing along its back edge, like a swatch for a ranch pen style (fence colour first, ground second) | #B3282D, #F6E7C8, #1B1B1B |
| theme_blossom_glade | a small square patch of ground with a short stretch of Blossom Glade themed fence standing along its back edge, like a swatch for a ranch pen style (fence colour first, ground second) | #F7A8C8, #C9EDA8, #1B1B1B |
| theme_tropical_lagoon | a small square patch of ground with a short stretch of Tropical Lagoon themed fence standing along its back edge, like a swatch for a ranch pen style (fence colour first, ground second) | #2EC4B6, #F4DFA6, #1B1B1B |
| theme_haunted_hollow | a small square patch of ground with a short stretch of Haunted Hollow themed fence standing along its back edge, like a swatch for a ranch pen style (fence colour first, ground second) | #3A2D55, #6B5B4B, #1B1B1B |
| theme_starfield | a small square patch of ground with a short stretch of Starfield Meadow themed fence standing along its back edge, like a swatch for a ranch pen style (fence colour first, ground second) | #6B5BD6, #2E3A78, #1B1B1B |
| theme_crystal_tundra | a small square patch of ground with a short stretch of Crystal Tundra themed fence standing along its back edge, like a swatch for a ranch pen style (fence colour first, ground second) | #9FE3FF, #E4F4FF, #1B1B1B |
| theme_aurora_isle | a small square patch of ground with a short stretch of Aurora Isle themed fence standing along its back edge, like a swatch for a ranch pen style (fence colour first, ground second) | #3DDC97, #1F4E5F, #1B1B1B |
| theme_sunset_mesa | a small square patch of ground with a short stretch of Sunset Mesa themed fence standing along its back edge, like a swatch for a ranch pen style (fence colour first, ground second) | #D9653B, #F2B880, #1B1B1B |
| theme_nebula | a small square patch of ground with a short stretch of Nebula Drift themed fence standing along its back edge, like a swatch for a ranch pen style (fence colour first, ground second) | #FF7AC8, #3A2D55, #1B1B1B |

## Accessories

| name | subject | colours |
|---|---|---|
| acc_sprout_cap | Sprout Cap: a cap, a head accessory for a pet monster, shown on its own with nobody wearing it | #79C455, #FFFFFF, #1B1B1B |
| acc_top_hat | Top Hat: a top hat with a band, a head accessory for a pet monster, shown on its own with nobody wearing it | #2B2B2B, #E5484D, #1B1B1B |
| acc_royal_crown | Royal Crown: a crown, a head accessory for a pet monster, shown on its own with nobody wearing it | #FFD447, #FFECAC, #1B1B1B |
| acc_party_hat | Party Hat: a cone-shaped party hat, a head accessory for a pet monster, shown on its own with nobody wearing it | #FF7AC8, #FFE38A, #1B1B1B |
| acc_witch_hat | Witch Hat: a pointed wizard hat, a head accessory for a pet monster, shown on its own with nobody wearing it | #3A2D55, #9B6BFF, #1B1B1B |
| acc_wizard_hat | Star Wizard Hat: a pointed wizard hat, a head accessory for a pet monster, shown on its own with nobody wearing it | #2E3A78, #FFE680, #1B1B1B |
| acc_beanie | Cozy Beanie: a knitted beanie hat with a pom-pom, a head accessory for a pet monster, shown on its own with nobody wearing it | #4FB6F2, #FFFFFF, #1B1B1B |
| acc_flower_crown | Flower Crown: a flower crown, a head accessory for a pet monster, shown on its own with nobody wearing it | #FF9EC7, #FFE38A, #1B1B1B |
| acc_halo | Halo: a floating halo ring, a head accessory for a pet monster, shown on its own with nobody wearing it | #FFF3B0, #FFFADB, #1B1B1B |
| acc_bunny_ears | Bunny Ears: a headband with two cute ears, a head accessory for a pet monster, shown on its own with nobody wearing it | #FFFFFF, #FFB3D1, #1B1B1B |
| acc_devil_horns | Little Horns: a pair of little horns on a headband, a head accessory for a pet monster, shown on its own with nobody wearing it | #E5484D, #F3ADAF, #1B1B1B |
| acc_chef_hat | Chef Hat: a puffy chef's hat, a head accessory for a pet monster, shown on its own with nobody wearing it | #FFFFFF, #FFFFFF, #1B1B1B |
| acc_sun_hat | Sun Hat: a wide-brimmed hat, a head accessory for a pet monster, shown on its own with nobody wearing it | #F4DFA6, #FF6B6B, #1B1B1B |
| acc_hero_helmet | Hero Helmet: a helmet, a head accessory for a pet monster, shown on its own with nobody wearing it | #E5484D, #FFD447, #1B1B1B |
| acc_space_helmet | Space Helmet: a round glass bubble helmet, a head accessory for a pet monster, shown on its own with nobody wearing it | #DFF3FF, #F1FAFF, #1B1B1B |
| acc_round_glasses | Round Glasses: a pair of round glasses, a face accessory for a pet monster, shown on its own with nobody wearing it | #2B2B2B, #A0A0A0, #1B1B1B |
| acc_sunglasses | Sunglasses: a pair of sunglasses, a face accessory for a pet monster, shown on its own with nobody wearing it | #1D1D1D, #999999, #1B1B1B |
| acc_star_shades | Star Shades: a pair of sunglasses, a face accessory for a pet monster, shown on its own with nobody wearing it | #FFD447, #FFECAC, #1B1B1B |
| acc_monocle | Monocle: a monocle on a little chain, a face accessory for a pet monster, shown on its own with nobody wearing it | #FFD447, #FFECAC, #1B1B1B |
| acc_hero_mask | Hero Mask: a face mask, a face accessory for a pet monster, shown on its own with nobody wearing it | #1D1D1D, #999999, #1B1B1B |
| acc_mustache | Dapper Mustache: a curly mustache, a face accessory for a pet monster, shown on its own with nobody wearing it | #5A3A1E, #B5A69A, #1B1B1B |
| acc_blush | Rosy Cheeks: an open round makeup blush compact with a pink blush pan and a small mirror lid, a face accessory for a pet monster, shown on its own | #FF9EC7, #FFD3E6, #1B1B1B |
| acc_snorkel | Snorkel: a pair of aviator goggles, a face accessory for a pet monster, shown on its own with nobody wearing it | #3FB6D9, #A9DEEE, #1B1B1B |
| acc_red_scarf | Red Scarf: a knitted scarf, a neck accessory for a pet monster, shown on its own with nobody wearing it | #E5484D, #F3ADAF, #1B1B1B |
| acc_bow_tie | Bow Tie: a bow tie, a neck accessory for a pet monster, shown on its own with nobody wearing it | #2B2B2B, #A0A0A0, #1B1B1B |
| acc_pink_bow | Big Pink Bow: a bow tie, a neck accessory for a pet monster, shown on its own with nobody wearing it | #FF7AC8, #FFC3E6, #1B1B1B |
| acc_gold_medal | Gold Medal: a medal on a ribbon, a neck accessory for a pet monster, shown on its own with nobody wearing it | #FFD447, #FFECAC, #1B1B1B |
| acc_flower_lei | Flower Lei: a flower lei necklace, a neck accessory for a pet monster, shown on its own with nobody wearing it | #FF6FA5, #FFE38A, #1B1B1B |
| acc_pearl_necklace | Pearl Necklace: a flower lei necklace, a neck accessory for a pet monster, shown on its own with nobody wearing it | #F4EFE4, #FAF8F3, #1B1B1B |
| acc_jingle_bell | Jingle Bell: a round collar bell on a little strap, a neck accessory for a pet monster, shown on its own with nobody wearing it | #FFD447, #E5484D, #1B1B1B |
| acc_royal_cape | Royal Cape: a flowing cape, a back accessory for a pet monster, shown on its own with nobody wearing it | #8B2E8F, #FFD447, #1B1B1B |
| acc_hero_cape | Hero Cape: a flowing cape, a back accessory for a pet monster, shown on its own with nobody wearing it | #E5484D, #F3ADAF, #1B1B1B |
| acc_bat_wings | Bat Wings: a pair of little wings, a back accessory for a pet monster, shown on its own with nobody wearing it | #3A2D55, #A6A0B2, #1B1B1B |
| acc_fairy_wings | Fairy Wings: a pair of little wings, a back accessory for a pet monster, shown on its own with nobody wearing it | #DFF3FF, #FF9EC7, #1B1B1B |
| acc_backpack | Explorer Pack: a small backpack, a back accessory for a pet monster, shown on its own with nobody wearing it | #D9A066, #EED4BA, #1B1B1B |
| acc_jetpack | Jetpack: a small jetpack, a back accessory for a pet monster, shown on its own with nobody wearing it | #9AA39C, #F0663A, #1B1B1B |
| acc_surfboard | Surfboard: a small surfboard, a back accessory for a pet monster, shown on its own with nobody wearing it | #3FB6D9, #FFFFFF, #1B1B1B |
| acc_starlight_crown | Starlight Crown: a crown, a head accessory for a pet monster, shown on its own with nobody wearing it | #B9A7FF, #E0D7FF, #1B1B1B |
| acc_rainbow_wings | Rainbow Wings: a pair of little wings, a back accessory for a pet monster, shown on its own with nobody wearing it | #FF7AC8, #7CC7FF, #1B1B1B |
