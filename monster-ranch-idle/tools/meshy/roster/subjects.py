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
    # ── Batch 5 (2026-09-25): line 26, the last credits (line 25's four forms did not fit) ──
    # 26 jellow (blob, spark). Jellyfish are usually drawn see-through: here the jelly is solid and
    # opaque, and tentacles are short, thick and attached (thin loose ones model badly).
    "jellow": "Jellow, a baby jelly blob: a round wobbly body of solid, opaque, glossy yellow jelly, a small "
    "jellyfish-like dome on top of its head with a wavy frilled rim, a few tiny bright spark spots.",
    "glimmerjel": "Glimmerjel: a bigger jelly blob with a larger glowing dome on its head, short thick frilly "
    "tendrils along the dome's rim, bright sparkle spots on its solid opaque jelly body.",
    "voltmedusa": "Voltmedusa: a big regal jellyfish blob with a large glowing dome crown, a ring of short "
    "thick curling tentacles around the crown's rim like a mane, lightning-bolt markings on its solid "
    "opaque body.",
    # ── Batch 6 (2026-09-25): lines 25 and 27-34 ──
    # 25 shellsnap (bug, tide). Tidecrusher is also the region boss "Old Snapjaw". Claws sit low at
    # the front and ridges stay low: the bug rig reads what rises well above the shell as wings.
    "shellsnap": "Shellsnap, a baby shell crab-bug: a round blue shell on its back like a little clam, two small "
    "snapping claws at the front, two short eye-stalk antennae.",
    "clawcrest": "Clawcrest: a bigger shell bug with larger snapping claws, a row of low spiky ridges along its "
    "shell, small barnacle spots.",
    "tidecrusher": "Tidecrusher: a huge old armoured crab-bug with one giant crushing claw and one smaller claw, "
    "a thick shell crusted with barnacles, a grumpy old face with a short mossy beard.",
    "pearlguard": "Pearlguard: a graceful shell bug with a big shiny pearl set on top of its round shell, pale "
    "pearly swirl patterns, small elegant claws.",
    # 27 anglit (slug, tide + spark). Abyssangler is also the region boss "The Abyssal Lantern".
    "anglit": "Anglit, a baby anglerfish slug: a big round head with a wide friendly smile, a short thick bendy "
    "stalk on its forehead ending in a glowing yellow lure, small fin frills along its sides.",
    "lanternfin": "Lanternfin: a longer anglerfish slug with a brighter glowing lure on its stalk, fin-like "
    "frills along its back and sides, glowing yellow spots.",
    "abyssangler": "Abyssangler: a big deep-sea anglerfish serpent-slug with a large glowing lantern lure on a "
    "thick stalk, a wide toothy but friendly grin, a deep blue body with glowing yellow spots and stripes.",
    # 28 lanternling (fox, ember + spark). Dragons keep four legs and only small folded wings (the fox
    # rig has no wing bones).
    # Lanternling's first concept drew two upright creatures holding lanterns: "on all four legs"
    # goes first (as Staticat's did), and the lantern is part of the tail, not held.
    "lanternling": "Lanternling, a baby lantern fox standing on all four legs like a real fox kit: a round "
    "fluffy body, its own tail ending in a glowing paper-lantern shape, little flame-shaped ear tufts, "
    "glowing yellow cheek marks.",
    "lanternwyrm": "Lanternwyrm: a longer, slightly dragon-like fox with two small horns, scale patterns along "
    "its back, a longer tail ending in a glowing lantern.",
    "lanterndragon": "Lanterndragon: a proud four-legged dragon with small folded wings, two curved horns, "
    "flame-orange scales with golden patterns, a long tail ending in a big glowing paper lantern.",
    "moonlitdragon": "Moonlitdragon: a calm four-legged dragon glowing softly like moonlight, small folded wings, "
    "pale gold scales with orange tips, a long tail ending in a glowing crescent-moon-shaped lantern.",
    # 29 mochibun (bunny, stone)
    "mochibun": "Mochibun, a baby mochi bunny: a soft round squishy body like a rice cake, short rounded ears, a "
    "little pink blush, a small smooth pebble charm on its forehead.",
    "mooncrest": "Mooncrest: a taller bunny with long ears, a smooth stone crescent-moon crest on its forehead, "
    "speckled stone patterns on its fur.",
    "jadehare": "Jadehare: an elegant hare with long ears tipped in green jade, a polished jade gem on its "
    "forehead, carved stone patterns like a statue.",
    # 30 wickit (sprite, spark)
    "wickit": "Wickit, a baby candle sprite: a small round body like a soft candle, a tiny solid yellow flame on "
    "top of its head like a wick, drips of wax on its sides.",
    "crackleflit": "Crackleflit: a livelier sprite with a crackling spark-shaped solid flame on its head, small "
    "zigzag spark tufts on its cheeks, a longer wispy tail.",
    "skyblossom": "Skyblossom: a graceful sprite with a crown of glowing yellow petals bursting like fireworks, "
    "star-shaped sparkle markings on its body, a long elegant wispy tail.",
    # 31 cometkit (fox, ember + spark)
    # Cometkit's first concept drew two creatures; redrawn from Meteorlynx as its baby it stood up on two
    # legs: "on all four legs" goes first.
    "cometkit": "Cometkit, a baby comet fox standing on all four legs like a real fox kit: a small orange fox "
    "with a big fluffy tail shaped like a comet's tail streaming behind it, a little star mark on its forehead.",
    "meteorlynx": "Meteorlynx: a sleek lynx with tufted ears, a rocky meteor-textured patch on its back with "
    "glowing orange cracks, a long comet-shaped tail.",
    "supernova": "Supernova: a majestic fox with a radiant solid mane like a bursting star, glowing golden "
    "markings, a huge fiery comet-shaped tail.",
    # 32 moonmoth (moth, gloom + tide)
    "moonmoth": "Moonmoth, a baby moon moth: a round fluffy body, pale blue-purple wings with small crescent "
    "moon spots, two feathery antennae, short rounded tails on the lower wings.",
    "eclipsewing": "Eclipsewing: bigger wings patterned like a night sky with a glowing blue crescent on each, a "
    "fluffy collar, longer feathery antennae.",
    "nebulamoth": "Nebulamoth: a majestic moth with large wings showing swirling purple and blue nebula clouds "
    "dotted with tiny stars, a thick fluffy mane, long elegant antennae.",
    # 33 orbiton (golem, stone). A planet's ring is a solid band worn like a belt: a real ring leaves
    # see-through gaps.
    "orbiton": "Orbiton, a baby moon golem: a round stone body like a tiny moon with a few small craters, stubby "
    "rock arms and legs, a small glowing star on its forehead.",
    "asterock": "Asterock: a sturdier asteroid golem with craggy crater-covered arms, small glowing crystals set "
    "in its craters.",
    "planetitan": "Planetitan: a huge titan golem whose body is a round planet with a solid stone ring band "
    "around its middle like a belt, massive fists, glowing star specks.",
    # 34 budling (bunny, sprout)
    "budling": "Budling, a baby bud bunny: a small bunny with a closed flower bud on its head and leaf-shaped "
    "ears.",
    "petalhop": "Petalhop: a bunny with ears shaped like pink petals, a small flower blooming on its head, leaf "
    "patterns on its fur.",
    "bloomhare": "Bloomhare: an elegant hare with long petal-shaped ears, a crown of blooming flowers, a "
    "flowery round tail.",
    # ── Batch 7 (2026-09-25): lines 35-42 ──
    # 35 pollenpuff (moth, sprout + spark)
    "pollenpuff": "Pollenpuff, a baby pollen moth: a round fluffy body like a ball of yellow pollen, four small "
    "rounded leaf-green wings with yellow dots, two short antennae tipped with little pollen balls.",
    "buzzbloom": "Buzzbloom: bigger wings shaped like flower petals with yellow pollen spots, a fluffy yellow "
    "collar, longer antennae tipped with small flowers.",
    "pollenmonarch": "Pollen Monarch: a majestic moth with large wings patterned like a monarch butterfly's in "
    "green and gold with bright yellow spots, a thick fluffy yellow mane, long elegant antennae tipped with "
    "small blossoms.",
    # 36 tulipup (fox, tide + sprout)
    "tulipup": "Tulipup, a baby tulip fox standing on all four legs like a real fox kit: a small blue fox with a "
    "closed tulip bud on the tip of its tail, two small green leaves on its head like a sprout, round shiny "
    "water-drop spots on its back.",
    "dewfox": "Dewfox: a bigger fox with the tulip on its tail opening into a flower, leaf-shaped ears, small "
    "shiny blue dewdrop beads on its leaves.",
    "rainbloomfox": "Rainbloom Fox: a graceful fox with a big fluffy tail ending in a blooming tulip, a crown of "
    "small flowers and leaves on its head, blue raindrop markings on its fur.",
    # 37 lumipup (fox, light). Light is solid parts (tufts, marks, glowing tips), never loose rays: thin
    # streaks around a body model badly (Zappip's first concept).
    "lumipup": "Lumipup, a baby light pup standing on all four legs like a real puppy: a small golden puppy "
    "with floppy ears, a glowing white star mark on its forehead, a fluffy tail with a softly glowing tip.",
    "beamhound": "Beamhound: a bigger, sleek hound with pointed ears, glowing white stripes along its back like "
    "beams of light, a longer tail with a bright glowing tip.",
    # The adults branch from Beamhound.
    "sunfang": "Sunfang: a fierce but friendly wolf with a solid mane of short pointed tufts like the rays of "
    "the sun around its neck, two small fangs, glowing golden stripes on its legs.",
    "dawnmane": "Dawnmane: a gentle, noble wolf with a long flowing soft mane in dawn colours of gold and pale "
    "pink, a small glowing sunrise mark on its forehead, a long fluffy tail.",
    # 38 halobee (bug, light). The word "halo" drew a floating ring on a post whatever else the text
    # said (first concept): the baby was re-drawn from Glintwing with a dome instead.
    "halobee": "Halobee, a baby light bee: a round golden shell with soft cream stripes, a small round glowing "
    "golden dome on top of its head, two short antennae with little glowing tips.",
    "glintwing": "Glintwing: a bigger bee with shiny glittering white-gold wings folded on its back, "
    "sparkle-shaped markings on its shell, longer antennae with glowing tips.",
    "seraphly": "Seraphly: a graceful, holy-looking beetle with two feathered white wings folded flat on its "
    "back, a solid glowing golden crest on its head, shining golden patterns on its shell.",
    # 39 dawnling (sprite, light). Daybreak Seraph is also the region boss "The Sunlit Warden". No wings on
    # a sprite (the rig reads side parts as arms): the seraph's glory is a sun crest behind its head.
    "dawnling": "Dawnling, a baby dawn sprite: a small round golden body, a tiny solid sunrise-shaped crest on "
    "top of its head, soft pink blush on its cheeks.",
    # Aurelle's first concept wore a soft glow all round its outline, which the cutout keeps as part of
    # the body: its markings are painted on, and the outline is clean.
    "aurelle": "Aurelle: a bigger sprite with a small solid golden crown of pointed rays on its head, white "
    "sunbeam stripes painted on its body, a longer wispy tail, a clean outline with no glow around it.",
    "daybreakseraph": "Daybreak Seraph: a noble, shining sprite with a large solid golden sun-disc crest rising "
    "behind its head, a flowing white-gold hood-like mane, a long elegant wispy tail.",
    # 40 nullkit (fox, void)
    "nullkit": "Nullkit, a baby void kitten standing on all four legs like a real kitten: a small dark indigo "
    "kitten with big pointed ears tipped in cyan, tiny cyan star speckles on its fur, a fluffy tail.",
    "voidlynx": "Voidlynx: a sleek lynx with tufted ears, fur speckled with cyan stars like a night sky, "
    "glowing cyan bands around its paws.",
    "eventidelynx": "Eventide Lynx: a majestic lynx with long ear tufts, a starry night-sky pattern across its "
    "back, a glowing cyan crescent-moon mark on its forehead, a long fluffy tail with a starry tip.",
    # 41 hollowisp (sprite, void)
    "hollowisp": "Hollowisp, a baby void sprite: a small round dark indigo body, a tiny cyan star on its "
    "forehead, glowing cyan spots on its cheeks.",
    "riftshade": "Riftshade: a bigger shadowy sprite with glowing cyan crack-like markings across its body like "
    "rifts in space, two small pointed tufts on its head, a longer wispy tail.",
    # "Guardian" drew big clawed arms and a vortex tail of thin loose strands (first concept).
    "abysswarden": "Abyss Warden: a larger, calm, cute sprite wearing a solid dark indigo hood over its head "
    "with two small curved horns poking out, glowing cyan rune markings on its body, still tiny stubby arms, "
    "a long smooth solid wispy tail.",
    # 42 gravitoad (blob, void). Event Horizon is also the region boss "Umbra, the Hungry Star". A black
    # hole's disc is a solid band worn like a belt (as Planetitan's ring), and nothing orbits it loose.
    "gravitoad": "Gravitoad, a baby space toad: a round squishy dark indigo toad with a pale lavender belly, "
    "tiny cyan star speckles on its back.",
    "singulatoad": "Singulatoad: a bigger, heavier toad with a swirling cyan galaxy spiral on its back, a solid "
    "glowing cyan band around its middle like a belt.",
    "eventhorizon": "Event Horizon: a huge round toad like a hungry black hole, a swirling dark galaxy pattern "
    "on its back, a thick solid glowing cyan disc band around its middle like a belt, a wide grinning mouth.",
    # ── Batch 8 (2026-09-26): lines 43-63, concepts drawn in Tripo Studio (Nano Banana Pro) and modelled
    # with Roblox's own generator (tools/rbxgen). Stage 3 texts avoid "guardian"/"warden"/"reaper" words
    # (batch 7: "guardian" drew claws and loose strands).
    # 43 eclipsa (moth, light + void)
    "eclipsa": "Eclipsa, a baby eclipse moth: a round fluffy body, four small rounded wings, the top pair golden "
    "and the bottom pair deep indigo, a small solid crescent-shaped marking on its forehead, two short feathery "
    "antennae.",
    "penumbra": "Penumbra: bigger wings with golden edges fading into dark indigo, a round sun-and-moon spot on each "
    "upper wing, a fluffy two-tone collar, longer feathery antennae.",
    "totaleclipse": "Total Eclipse: a majestic moth with large dark indigo wings rimmed with a painted golden corona "
    "pattern, a round black sun spot edged in gold on each upper wing, a thick fluffy golden mane, long elegant "
    "antennae.",
    # 44 surfotter (bunny, tide): an otter on the bunny body plan, so it keeps the long ears.
    "surfotter": "Surfotter, a baby surf otter bunny: a round chubby otter-like bunny with sleek blue fur, two long "
    "upright rounded ears, a cream belly, a small wave-shaped tuft on its head, a short flat paddle tail.",
    "wavebreaker": "Wavebreaker: taller ears with wave-curl tips, bold white wave stripes on its back, a longer flat "
    "paddle tail, a confident grin.",
    "tidalchampion": "Tidal Champion: a proud athletic otter-hare with ears curling like breaking waves, a solid "
    "white foam-shaped mane around its neck, a golden wave emblem on its chest, a big paddle tail.",
    # 45 coconutty (golem, sprout)
    "coconutty": "Coconutty, a baby coconut golem: a round brown hairy coconut body with a cream coconut belly, "
    "stubby wooden arms and legs, two small green palm leaves sprouting from the top of its head.",
    "palmguard": "Palmguard: a sturdier palm-trunk golem with ring-banded bark arms, a bushy crown of palm leaves on "
    "its head, a coconut-shell chest plate.",
    "islandking": "Island King: a huge palm golem with a massive coconut-shell chest, thick bark arms ending in big "
    "fists, a tall crown of palm leaves, a flower garland around its neck.",
    # 46 sunnyray (moth, tide + light): a manta ray on the moth body plan (fin-wings, feelers).
    "sunnyray": "Sunnyray, a baby sun ray: a small round body like a baby manta ray, four wide rounded fin-wings, "
    "the top pair golden and the bottom pair sea-blue, two short curled feelers, a small sun-shaped spot on its "
    "back.",
    "glareray": "Glareray: bigger wide fin-wings with golden sunburst patterns, a short thin tail, feelers with "
    "bright golden tips.",
    "solarmanta": "Solar Manta: a majestic manta with huge fin-wings painted with a golden sun pattern fading into "
    "ocean blue, a regal crest on its head, long elegant feelers.",
    # 47 titanling (golem, stone + spark)
    "titanling": "Titanling, a baby storm-stone golem: a round grey-brown rock body with yellow lightning-bolt "
    "cracks, stubby rock arms and legs, a small lightning-bolt-shaped rock horn on its head.",
    "thundercrag": "Thundercrag: a sturdier craggy golem with jagged rock shoulders, bright yellow lightning veins "
    "across its body, bigger rock fists.",
    "stormcolossus": "Storm Colossus: a huge towering rock titan with massive fists, solid rock storm-cloud shapes on "
    "its shoulders, yellow lightning veins, a jagged crown of rock spikes.",
    # 48 wyrmlet (fox, ember + void): a dragon on four legs; wings stay small and folded (fox rig).
    "wyrmlet": "Wyrmlet, a baby shadow-fire dragon: a small round dragon standing on four legs, two tiny wing nubs "
    "on its back, two short horns, a long tail with a small flame-shaped tip, orange belly plates.",
    "ashwyrm": "Ashwyrm: a longer, leaner four-legged dragon with small folded wings on its back, glowing orange "
    "cracks along its back, curved horns, a flame-tipped tail.",
    "umbralwyrm": "Umbral Wyrm: a majestic four-legged dragon with big wings folded on its back, glowing orange-red "
    "veins, long curved horns, a spiked tail with a dark flame-shaped tip.",
    # 49 tempestray (moth, tide + spark): a storm manta on the moth body plan.
    "tempestray": "Tempestray, a baby storm ray: a small round body like a baby manta ray, four wide fin-wings with "
    "yellow zigzag lightning stripes, two short curly feelers, a tiny cloud-shaped puff on its back.",
    "squallwing": "Squallwing: bigger fin-wings with lightning-bolt patterns on the edges, a short thin tail with a "
    "bolt-shaped tip, longer feelers.",
    "maelstromray": "Maelstrom Ray: a majestic storm manta with huge fin-wings painted with swirling storm patterns "
    "and bright yellow lightning streaks, a crest shaped like a lightning bolt, long feelers.",
    # 50 floelet (slug, tide + light)
    "floelet": "Floelet, a baby ice slug: a soft glossy body, two short eye stalks with little snowflake tips, small "
    "round white frost spots on its back.",
    "rimecoil": "Rimecoil: a longer body with a row of short, rounded ice-crystal spikes along its back, frosty "
    "white stripes, eye stalks tipped with tiny crystals.",
    "frostleviathan": "Frost Leviathan, a long, proud ice sea serpent: rows of ice-crystal plates along its back, a "
    "crest of ice spikes on its head, two short curled horns, shimmering frost patterns.",
    # 51 sandskip (bunny, stone): two adults, both drawn from dunehopper.
    "sandskip": "Sandskip, a baby sand bunny: a small bunny with two long upright ears with brown tips, big feet, a "
    "few darker sand-dune stripes on its back.",
    "dunehopper": "Dunehopper: taller ears, stronger hind feet, a fluffy ruff of fur around its neck like a desert "
    "scarf, dune-wave stripes along its back.",
    "siroccohare": "Sirocco Hare: an elegant desert hare with very long swept-back ears, a swirling wind pattern in "
    "its fur, a fluffy sand-coloured mane, a confident look.",
    "oasishare": "Oasis Hare: a calm desert hare with long ears tipped with small green palm fronds, a turquoise "
    "water-drop marking on its forehead, soft green and turquoise patterns in its fur.",
    # 52 cactling (golem, sprout + stone)
    "cactling": "Cactling, a baby cactus golem: a round green cactus body with soft rounded spines, a small pink "
    "flower on its head, stubby sandstone legs and little cactus arms.",
    "pricklord": "Pricklord: a sturdier cactus golem with thick cactus-pad arms covered in soft rounded spines, "
    "sandstone feet like boots, two pink flowers on its head.",
    "saguardian": "A huge towering saguaro cactus titan: massive cactus arms raised like a strongman, sandstone rock "
    "shoulders, a crown of blooming pink and white flowers.",
    # 53 scarabit (bug, ember)
    "scarabit": "Scarabit, a baby fire scarab: a round glossy shell with golden edges, a small sun-disc marking on "
    "its back, two short antennae with ember tips.",
    "sunscarab": "Sunscarab: a bigger scarab with a shiny golden sun disc on its back, flame-shaped patterns along "
    "the shell edge, a small horn on its head.",
    "pharaohbeetle": "Pharaoh Beetle: a majestic royal beetle with a gleaming gold and orange shell, a striped "
    "pharaoh-style headdress shape on its head, a big golden sun disc on its back, an ornate horn.",
    # 54 pengling (blob, tide)
    "pengling": "Pengling, a baby penguin blob: a round squishy body with a white belly, a small orange beak, two "
    "tiny flipper nubs on its sides, a little tuft of feathers on top of its head.",
    "floeglider": "Floeglider: a rounder, bigger penguin blob with a flat ice-floe-shaped patch on its head, bigger "
    "flippers, wave-shaped markings on its back.",
    "emperorfloe": "Emperor Floe: a big stately round penguin blob with a golden-yellow collar patch, a solid "
    "crown-shaped crest of ice on its head, a proud puffed-out white chest.",
    # 55 yetikit (golem, stone + tide)
    "yetikit": "Yetikit, a baby yeti: a round fluffy furry body, stubby arms and legs, a grey stone face with two "
    "small horns, a round tummy.",
    "snowbrute": "Snowbrute: a sturdier shaggy yeti with big furry arms and stone-grey fists, icicle-shaped fur on "
    "its shoulders, two curved horns.",
    "avalancheyeti": "Avalanche Yeti: a huge towering yeti with massive furry arms, rocky stone shoulder plates "
    "capped with snow, long curved horns, a thick shaggy white mane.",
    # 56 aurowl (sprite, light)
    "aurowl": "Aurowl, a baby dawn owl: a round fluffy owl body, big round owl eyes, two small feather tufts on its "
    "head, tiny wing-arms, a short wispy feathered tail.",
    "glimmerowl": "Glimmerowl: longer feather tufts, soft golden star markings on its chest, wing-arms with bright "
    "feather tips, a longer wispy tail.",
    "aurorasage": "Aurora Sage: a wise majestic owl sprite with a flowing mane of pale gold feathers, soft pastel "
    "aurora bands painted across its wings, long feather tufts like a sage's brows, a small golden star on its "
    "forehead.",
    # 57 pumpkit (blob, ember + sprout)
    "pumpkit": "Pumpkit, a baby pumpkin blob: a round squishy pumpkin body with soft ridges, a short curly green "
    "stem and a small leaf on top of its head.",
    "gourdling": "Gourdling: a bigger pumpkin blob with deeper ridges, a curly vine wrapped around its body with "
    "small leaves, a slightly mischievous grin.",
    "jackolord": "Jack-o-Lord: a big proud pumpkin blob with a jack-o'-lantern face whose mouth glows warm orange "
    "inside, a crown of curly vines and leaves, a thick green stem.",
    # 58 scarecrowl (moth, sprout + gloom): a straw-and-patchwork moth.
    "scarecrowl": "Scarecrowl, a baby straw moth: a round fluffy body of golden straw, a tiny patched hat on its "
    "head, four small rounded wings of patched cloth, two short straw antennae.",
    "strawhoot": "Strawhoot: bigger patched-cloth wings with stitched seams, a fuller straw collar, a wider hat, "
    "longer straw antennae.",
    "harvestwarden": "A majestic harvest moth: large patched-cloth wings with stitched moon patterns, a tall "
    "pointed straw hat, a thick straw mane, long straw antennae with small wheat tips.",
    # 59 batterfly (bug, gloom)
    # The bat ears made NB2 draw an upright bat twice (2026-09-26): the beetle shape is spelled out.
    "batterfly": "Batterfly, a baby bat bug shaped like a round beetle: a low body lying lengthwise along the ground "
    "on six stubby legs, a round shell back with two small folded bat-like wings, big pointed bat ears on its head, "
    "two short antennae.",
    "duskflutter": "Duskflutter: a bigger bug with larger folded bat wings on its back, moon-shaped markings on its "
    "shell, taller bat ears.",
    "nightreaper": "A majestic night beetle: large folded bat wings on its back, a shell painted with a starry night "
    "pattern, tall bat ears, a curved horn like a crescent moon.",
    # 60 snowmitt (bunny, tide)
    "snowmitt": "Snowmitt, a baby snow bunny: a small fluffy bunny with pale ear tips, big fluffy mitten-like feet, "
    "a round fluffy tail, a ring of thicker fur around its neck like a tiny scarf.",
    "frostpaw": "Frostpaw: taller ears with icy tips, frosty patterns on its fur, bigger fluffy paws, a small "
    "icicle-shaped tuft on its head.",
    "glacierfang": "Glacierfang: a strong majestic snow hare with long swept-back ears, two small ice-crystal fangs, "
    "a thick frosty mane, ice-crystal shapes on its shoulders.",
    # 61 pinepip (golem, sprout)
    "pinepip": "Pinepip, a baby pine golem: a round body shaped like a small pine cone with green needle tufts, "
    "stubby wooden arms and legs, a tiny pine sapling growing on its head.",
    # "Like a cape" drew a spruce skirt down to the ground that hid the arms and rigged as a third
    # foot (2026-09-26): the branches are kept short and high.
    "sprucesprout": "Sprucesprout: a sturdier wooden golem with a short mantle of spruce branches on its shoulders "
    "and upper back that ends well above the ground, bark-textured arms held clear of the body, a small spruce "
    "tree on its head.",
    "evergrand": "Evergrand: a huge ancient evergreen titan with a body of dark bark and moss, massive wooden fists, "
    "a tall layered pine-tree crown on its head, small pinecones on its shoulders.",
    # 62 frostfly (moth, spark)
    "frostfly": "Frostfly, a baby frost moth: a round fluffy body, four small rounded wings shaped like snowflakes "
    "with spark dots, two short antennae tipped with tiny ice crystals.",
    "icewing": "Icewing: bigger crystal-patterned wings with zigzag spark edges, a fluffy frosty collar, longer "
    "antennae with crystal tips.",
    "aurorawing": "Aurorawing: a majestic moth with large wings painted with shimmering bands of aurora colours, a "
    "thick fluffy mane, long elegant antennae with star-shaped tips.",
    # 63 tinselkit (fox, spark + light)
    "tinselkit": "Tinselkit, a baby festive fox: a small fluffy fox with a sparkly tinsel-like tail tip, a tiny bell "
    "on a red ribbon collar, small star-shaped markings on its cheeks.",
    "garlandfox": "Garlandfox: a green garland of leaves and small red baubles wrapped around its neck, a longer "
    "sparkly tail, star markings along its back.",
    "yuletail": "Yuletail: a majestic festive fox with a huge fluffy tail tipped with a solid golden star shape, a "
    "thick garland mane with small red berries, star patterns across its fur.",
}


# A baby re-drawn from a later stage's concept (batch.py reroll FORM --from LATER): when the baby's
# own concept failed but its teen and adults came out right, this keeps the line consistent.
FROM_LATER = (
    "Turn this creature into its baby form: the same creature, the same colours and markings and the "
    "same body plan, much smaller and cuter, with a round chubby body, an oversized head and stubby limbs. "
)


def colours(palette: dict) -> str:
    return (
        f"Main colour {palette['color']}, belly and muzzle {palette['light']}, accents {palette['accent']} "
        f"({palette['name']} element). "
    )


def palette_for(line: dict, elements: dict) -> str:
    """One element's colours, or ONE blended scheme for a two-element line: listing two full
    schemes made the image model draw two creatures side by side, one per element (Mudpuff, all
    four of Lanternling's line, Cometkit, Moonmoth)."""
    if len(line["elements"]) == 1:
        return colours(elements[line["elements"][0]])
    a, b = (elements[e] for e in line["elements"][:2])
    return (
        f"One single creature, alone. Main colour {a['color']} blending into {b['color']}, belly and muzzle "
        f"{a['light']}, accents {b['accent']} ({a['name']} and {b['name']} elements in one body). "
    )


def prompt(form: dict, line: dict, elements: dict, from_later: bool = False) -> str:
    """The concept prompt for one form (see the module docstring)."""
    body = BODY[line["archetype"]]
    palette = palette_for(line, elements)
    subject = SUBJECTS[form["id"]]
    if from_later:
        return FROM_LATER + subject + f" It is {body}. " + palette + EYES + STYLE
    if form["stage"] == 1:
        return STAGE[1] + subject + f" It is {body}. " + palette + EYES + STYLE
    return STAGE[form["stage"]] + subject + f" Still {body}. " + palette + STYLE
