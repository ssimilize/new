"""What each monster looks like, for the concept images (tools/meshy/roster/batch.py).

Species.luau only holds names, elements and an archetype, so the design words live here. The
archetype's BODY plan is fixed per archetype so every model of one archetype can share a Blender
rig script (tools/blender/rig_<archetype>.py): keep new subjects inside it.

Stage 1 is drawn from text. Stages 2 and 3 are image-to-image edits of the previous stage's
concept (a branching line's adults both start from the teen), so a line keeps its colours and
markings: their text says what CHANGES.
"""

# Pilot style (tools/meshy/pilot/make_concepts.py) with two fixes found in the 2026-09-25 A/B:
# "vinyl-toy" (nano-banana drew plush fur without it) and a grey background (on white, background
# removal cut Petalpaw's white chest out and Meshy filled the hole with black).
STYLE = (
    "Stylized 3D render for a cozy monster-collecting game. Chunky, rounded, toy-like shapes, "
    "smooth matte vinyl-toy surfaces, bright saturated colours, a simple readable silhouette, "
    "every part attached to the body. Full body, three-quarter front view, centred, plain flat "
    "medium grey background (#8C8C8C), soft even lighting, no text, no ground shadow."
)
EYES = "Big glossy black eyes with a white highlight, a small happy mouth. "

BODY = {
    "fox": "standing on all four legs, with a head, ears and a tail",
    "bunny": "sitting upright on two big hind feet, with small front paws, two long upright ears and a round tail",
    "moth": "hovering in the air, with a small round body, two pairs of wings spread wide to the sides, two antennae and tiny legs tucked under",
    "slug": "lying low on the ground with no legs, a big round head at the front and the body tapering to a tail behind",
    "blob": "a round squishy body with no neck, standing on two stubby little feet, the face on the front of the body",
    "sprite": "floating in the air, a small round body with tiny stubby arms and no legs, the lower body trailing off into a short wispy tail",
    "bug": "standing on six short stubby legs, a round shell-backed body, two antennae and small wings folded on the back",
    "golem": "standing on two short thick legs, a chunky blocky body with big strong arms and a small head",
}

# "Slimmer and taller, longer limbs" for every teen (first batch) turned the blob Brinelotl and the
# sprite Rainpuff into long-legged bipeds: growth words must keep the archetype's body plan.
STAGE = {
    1: "A tiny baby monster: a round chubby body, an oversized head, stubby limbs. ",
    2: "Evolve this creature into its teen form: the same creature, the same colours and markings and "
    "the same body plan, a little bigger and a little more detailed. ",
    3: "Evolve this creature into its adult form: the same colours and markings and the same body "
    "plan, bigger, stronger and more impressive, with bolder features. ",
}

# form id -> what makes it that monster. Stage 1: the whole design. Stages 2-3: what changes.
SUBJECTS = {
    # 1 cindlet (fox, ember): the pilot made cindlet, kindlefox and blazefang.
    "hearthtail": "Hearthtail, a gentle, cosy adult fire fox with a calm, kind smile: a huge fluffy tail curled "
    "like a hearth flame with a warm glowing tip, a soft cream ruff around the neck, small golden flame "
    "marks on the cheeks.",
    # 2 scorchmoth (moth, ember)
    "scorchling": "Scorchling, a baby fire moth: a round fluffy body, two short feathery antennae, four small "
    "rounded wings with golden flame-shaped spots, a cream fluffy collar.",
    "scorchmoth": "Scorchmoth: bigger wings with ember eye-spots and flame-edged tips, longer feathery "
    "antennae, a fuller cream collar.",
    "pyremoth": "Pyremoth: large majestic wings patterned like flames with glowing golden edges, a thick "
    "fluffy cream mane, long elegant antennae tipped with little flames.",
    # 3 emberslug (slug, ember)
    "emberslug": "Emberslug, a baby lava slug: a soft glossy body, two short eye-stalk antennae with glowing "
    "tips, a few small glowing ember spots on its back.",
    "magmaslug": "Magmaslug: a longer body with a crust of dark rock plates on its back and glowing orange "
    "magma in the cracks between them.",
    "cinderwyrm": "Cinderwyrm, a long, proud, wyrm-like lava serpent: rows of rocky plates along its back "
    "with glowing magma seams, a small crest of flames on its head, two short horns.",
    # 4 bubblin (blob, tide)
    "bubblin": "Bubblin, a baby water blob: a jelly-like body, a curl of water like a wave on top of its "
    "head, a few round bubble spots.",
    "brinelotl": "Brinelotl: becomes a round, squat, chubby axolotl blob (no longer legs than the baby's), "
    "with feathery gills on both sides of the head and a short paddle tail.",
    "tsunamander": "Tsunamander: a big chubby salamander, a wave-shaped crest along its head and back, a "
    "thick paddle tail ending in a wave curl, bold wave stripes.",
    "pearlfin": "Pearlfin: a graceful round creature with flowing fin-like frills on the sides of the head, "
    "a shiny pearl set in its forehead, pale pearly spots.",
    # 5 drizzlet (sprite, tide)
    "drizzlet": "Drizzlet, a baby rain sprite: a small round cloud-like body, a single big water droplet on "
    "top of its head, a wispy tail shaped like a trickle of rain.",
    "rainpuff": "Rainpuff: a fluffier round rain-cloud body with soft cloud puffs around it, two droplets on "
    "its head, a longer wispy rain tail, still no legs at all.",
    "nimbuff": "Nimbuff: a big fluffy storm-cloud sprite with a large puffy cloud mane, a small rainbow "
    "stripe across its chest, a long curling wispy tail.",
    # 6 coralbun (bunny, tide)
    "coralbun": "Coralbun, a baby coral bunny: long ears shaped like soft coral branches with pink tips, a "
    "tiny sea-shell on its chest.",
    "reefhop": "Reefhop: a sportier bunny, ears like branching coral, fin-like tufts on its cheeks, a "
    "sea-shell badge on its chest.",
    "coralord": "Coralord: a big regal bunny with a crown of branching coral between its ears, a "
    "cape-like frill of seaweed, shells on its shoulders.",
    # 7 mossbun (bunny, sprout)
    "mossbun": "Mossbun, a baby moss bunny: a soft moss patch on its back, ears with leaf-shaped tips, a "
    "tiny mushroom on its head.",
    "clovermane": "Clovermane: a mane of clover leaves around its neck, a four-leaf clover on its forehead, "
    "longer ears.",
    "thornbuck": "Thornbuck: a strong bunny buck with antler-like thorny branches between its long ears, a "
    "mane of leaves, bramble bands on its legs.",
    "bloomhorn": "Bloomhorn: a gentle bunny with a single flowering horn on its forehead covered in "
    "blossoms, flower garlands around its ears.",
    # 8 petalpaw (fox, sprout)
    "petalpaw": "Petalpaw, a baby flower fox kit: small rounded ears shaped like pink flower petals, a short "
    "fluffy tail that ends in a pink blossom, a little two-leaf sprout on top of its head.",
    "blossomcat": "Blossomcat: a sleek cat-like fox, petal-shaped ears, a tail ending in a blooming flower, "
    "leaf patterns on its legs, a flower collar.",
    "florallynx": "Florallynx: a graceful lynx with tufted petal ears, a mane of blossoms around its neck, a "
    "long tail with a big bloom at the tip, vine patterns along its body.",
    # ── Batch 2 (2026-09-25): lines 9-15 ──
    # 9 acornling (golem, sprout)
    "acornling": "Acornling, a baby acorn golem: a round acorn-shaped body with a little acorn cap on its head, "
    "stubby wooden arms and legs, a tiny leaf sprouting from the cap.",
    "oakling": "Oakling: a sturdier wooden golem with bark-textured arms, a crown of small oak leaves, the "
    "acorn cap grown into a helmet.",
    "elderoak": "Elderoak: a big ancient tree golem, a thick bark-plated body, a broad crown of oak leaves on "
    "its head and shoulders, soft moss patches, a gentle face with a beard of hanging moss.",
    # 10 zappip (fox, spark)
    "zappip": "Zappip, a baby electric fox kit: lightning-bolt shaped ear tips, a zigzag lightning-bolt tail, "
    "little spark markings on its cheeks.",
    "voltfurr": "Voltfurr: a lively fox with a fluffy mane standing up with static, a longer lightning-bolt "
    "tail, zigzag stripes along its back.",
    # No loose lightning arcs (the first try drew thin floating streaks around a hollow cloud ruff),
    # and no grey: a grey part matches the background the concept is cut out of.
    "stormwhisker": "Stormwhisker: a sleek, fast fox with long whisker tufts on its cheeks, a solid fluffy "
    "cream-white ruff around the neck, a large jagged lightning-bolt tail.",
    "glowtail": "Glowtail: a gentle fox whose big fluffy tail glows like a lantern with soft yellow light, "
    "round glowing spots along its back, calm half-closed eyes.",
    # 11 buzzbee (bug, spark)
    "buzzbee": "Buzzbee, a baby electric bumblebee: a round fuzzy body with yellow and dark brown stripes, "
    "tiny wings, two antennae with little glowing ball tips, a small stinger shaped like a spark.",
    "hummbolt": "Hummbolt: a bigger bee with glowing wings, lightning-bolt stripes on its body, a spark-shaped "
    "stinger.",
    "thunderqueen": "Thunderqueen: a regal queen bee with a small golden crown, a fluffy collar, larger wings "
    "with glowing lightning veins, a long elegant striped body.",
    # 12 staticat (fox, spark)
    # Staticat's first concept stood up on two legs like a person (and on a grey floor strip):
    # "on all fours" goes first, where the image model weighs it most.
    "staticat": "Staticat, a baby electric kitten on all fours like a real cat, all four paws on the ground: "
    "fluffy fur puffed up with static, pointed cat ears with bright tips, a curly tail ending in a small "
    "spark ball.",
    "sparkitty": "Sparkitty: a playful young cat on all fours with spiky static-charged tufts on its cheeks and "
    "shoulders, a longer tail tipped with a crackling spark.",
    "voltpanther": "Voltpanther: a powerful, sleek panther with dark stripes shaped like lightning bolts and a "
    "long tail ending in a lightning bolt.",
    # 13 pebblet (golem, stone)
    "pebblet": "Pebblet, a baby pebble golem: a round smooth stone body, stubby rock arms and legs, a few "
    "small pebbles on top of its head like a tiny hairdo.",
    "cragrump": "Cragrump: a grumpy-looking but cute rock golem with craggy chunky arms and a jagged rocky "
    "ridge along its head and back.",
    "boulderback": "Boulderback: a huge sturdy golem carrying a giant boulder shell on its back, massive "
    "fists, mossy cracks.",
    "geodeon": "Geodeon: an elegant golem whose body is a cracked-open geode, glittering purple and pink "
    "crystals showing in its chest and shoulders.",
    # 14 rumblet (blob, stone)
    "rumblet": "Rumblet, a baby mole: a soft round body, a pink nose, small shovel-like digging paws in "
    "front, a little pebble on its head.",
    "quakemole": "Quakemole: a chunkier mole with big clawed digging paws and a helmet-like rock plate on "
    "its head.",
    "terramole": "Terramole: a big armoured mole with a rocky shell on its back, huge drill-like claws, a "
    "crystal on its forehead.",
    # 15 crystomp (golem, stone)
    "crystomp": "Crystomp, a baby crystal golem: a chunky stone body with a few pale glowing crystals growing "
    "from its back and head, big stomping feet.",
    "quartzhorn": "Quartzhorn: a stronger golem with a big quartz crystal horn on its head and crystal "
    "clusters on its shoulders.",
    "gemmoth": "Gemmoth: a giant golem with mammoth features, curved crystal tusks, a shaggy stone mane, gems "
    "set in its back.",
    # ── Batch 3 (2026-09-25): line 16, the last credits ──
    # 16 hushling (sprite, gloom). Nothing see-through or hollow (the concept check fails holes, and
    # Meshy fills them), nothing grey, and no wings on a sprite (the rig reads side parts as arms).
    "hushling": "Hushling, a shy baby shadow sprite: a small round body like a soft puff of twilight, a little "
    "pointed hood-like tuft on top of its head, a few tiny pale star speckles on its body.",
    "murkmoth": "Murkmoth: a fluffier dusk sprite with two soft feathery moth antennae on its head, a thick fuzzy "
    "moth-like collar around its neck, a longer wispy tail.",
    # The adults branch from Murkmoth. Hollowgaze is also the boss "The Hollow King" (Config/Boss).
    "hollowgaze": "Hollowgaze: a bigger, spooky-cute king of the shadows with a solid dark cowl around its face, "
    "softly glowing lilac eyes, a small crown of curved wispy horns, a long trailing tail.",
    "moonveil": "Moonveil: a gentle, graceful sprite with a solid flowing veil-like hood draped over its head, a "
    "small crescent moon on its forehead, pale star speckles, a long elegant wispy tail.",
    # ── Batch 4 (2026-09-25): lines 17-24 ──
    # 17 wisplet (sprite, gloom). Lanternshade is also the region boss "Lantern Wraith".
    "wisplet": "Wisplet, a baby will-o'-the-wisp sprite: a small round body with pale glowing spots on its round "
    "cheeks, a tiny solid lilac flame burning on the tip of its curled tail.",
    "wispkin": "Wispkin: a bigger wisp with two small flame-shaped tufts on its head, glowing spots along its "
    "back, a longer curling tail carrying a brighter solid lilac flame at its tip.",
    "lanternshade": "Lanternshade, a lantern wraith: a larger, spooky-cute wisp with a tall pointed hood, calm "
    "glowing eyes, its long curling tail swelling at the tip into a big round glowing lantern of lilac light "
    "with a little pointed cap.",
    # 18 gloomcap (blob, gloom)
    "gloomcap": "Gloomcap, a baby mushroom blob: a round body wearing a big purple mushroom cap on its head, "
    "the cap dotted with pale glowing lilac spots.",
    "shadeshroom": "Shadeshroom: a bigger mushroom blob with a wide drooping cap with a frilly underside, small "
    "mushrooms sprouting from its shoulders, glowing lilac spots.",
    "umbracap": "Umbracap: a large, wise mushroom blob with a huge umbrella-like cap covered in glowing lilac "
    "spots, a ring of small mushrooms around its feet, a gentle sleepy face.",
    # 19 steamling (blob, ember + tide). Steam as SOLID white puffs: a grey or see-through wisp is cut
    # out with the background.
    "steamling": "Steamling, a baby steam blob: a round body, warm orange on top fading to cool blue below, "
    "a solid puff of white steam curling up from the top of its head like a little cloud, rosy cheeks.",
    "vaporkin": "Vaporkin: a bigger steam blob with a crest of solid puffy white steam clouds along its head and "
    "back, small bubbles on its blue side and ember spots on its orange side.",
    "geyserdrake": "Geyserdrake: a big dragon-like blob with two stubby horns, a tall solid spout of white "
    "steam and blue water rising from the top of its head, orange and blue scales, a short thick tail.",
    # 20 mudpuff (blob, tide + stone)
    # Mudpuff's first concept drew TWO creatures, a brown one and a blue one (one per element); its
    # teen and adult came out one blue toad, so the baby was re-drawn from Bogtoad's concept.
    "mudpuff": "Mudpuff, a baby toad blob, one single creature: a soft round body with small mud-brown "
    "patches and pebbles stuck to it, a little green lily pad on its head.",
    "bogtoad": "Bogtoad: a chubby toad-like blob with a wide smiling mouth, bumpy muddy skin with blue spots, "
    "a lily pad with a tiny flower on its head.",
    "mireback": "Mireback: a big old swamp toad blob with a mossy mound of mud and stones on its back like a "
    "little island with a few short reeds, a wide friendly grin.",
    # 21 thornbolt (bug, spark + sprout). Keep what grows on the shell low: the bug rig reads anything
    # rising well above the shell as wings or antennae.
    "thornbolt": "Thornbolt, a baby thorn beetle: a round green shell with small yellow lightning-bolt markings, "
    "two short antennae with little leaf-shaped tips, a tiny thorn horn on its nose.",
    "voltvine": "Voltvine: a bigger beetle with thin vines wrapped flat around its shell, small glowing yellow "
    "spark spots, a stronger thorn horn on its nose.",
    "thundergrove": "Thundergrove: a big stag beetle with a mossy shell covered in small leaves and tiny glowing "
    "yellow flowers, two thorny antler-like horns on its head, yellow lightning veins on its shell.",
    # 22 lavashell (golem, ember + stone)
    "lavashell": "Lavashell, a baby lava golem: a chunky stone body with glowing orange lava cracks, a little "
    "rocky shell on its back, a tiny glowing ember on top of its head.",
    "magmatle": "Magmatle: a sturdier lava golem with a bigger domed rock shell on its back with glowing magma "
    "seams, rocky shoulder plates, fists glowing orange.",
    "volcanoise": "Volcanoise: a huge tortoise-like golem carrying a small volcano on its back with glowing "
    "orange lava in its crater, massive stone fists with magma cracks.",
    # 23 eclipsette (moth, gloom + spark)
    "eclipsette": "Eclipsette, a baby eclipse moth: a round fluffy purple body, rounded purple wings each with a "
    "golden ring like a solar eclipse, two feathery antennae.",
    "umbravolt": "Umbravolt: bigger wings with golden eclipse rings and small lightning-bolt shaped edges, a "
    "fluffy golden collar, longer antennae tipped with little sparks.",
    "eclipsior": "Eclipsior: a majestic moth with large wings each showing a glowing golden eclipse ring around a "
    "deep purple disc, a thick fluffy golden mane, long elegant antennae.",
    # 24 mirebloom (sprite, gloom + sprout)
    "mirebloom": "Mirebloom, a baby swamp-flower sprite: a small round body, a closed purple flower bud with two "
    "green leaves on top of its head, a short wispy tail like a trailing vine.",
    # "Vine-like" tails came out as bare twigs with loose leaves, and a tangle of thin vines around a
    # see-through wisp (first concepts): the tail is now a smooth solid one with a few leaves or buds.
    "bogblossom": "Bogblossom: the bud has opened into a purple flower on its head, small lily-pad-shaped "
    "leaves on its shoulders, a longer smooth solid wispy tail like the baby's with two small leaves "
    "growing on it.",
    "nightbloom": "Nightbloom: a graceful sprite with a large crown of a night-blooming flower with pale "
    "glowing purple petals, a long smooth solid wispy tail with a few small glowing flower buds growing "
    "along it.",
}


def colours(palette: dict) -> str:
    return (
        f"Main colour {palette['color']}, belly and muzzle {palette['light']}, accents {palette['accent']} "
        f"({palette['name']} element). "
    )


def prompt(form: dict, line: dict, elements: dict) -> str:
    """The concept prompt for one form (see the module docstring)."""
    body = BODY[line["archetype"]]
    palette = " ".join(colours(elements[e]) for e in line["elements"])
    subject = SUBJECTS[form["id"]]
    if form["stage"] == 1:
        return STAGE[1] + subject + f" It is {body}. " + palette + EYES + STYLE
    return STAGE[form["stage"]] + subject + f" Still {body}. " + palette + STYLE
