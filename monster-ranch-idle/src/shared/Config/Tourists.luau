--[[
	Ranch Tourists (update 3.10 · Ranch life): NPC visitors who tour the player's ranch, pay a
	few minutes of ranch income by how much they liked it, and leave a review in the Guestbook.
	Separate from player likes and visits (Systems/Visits). Rules: Logic/Tourists; save and
	schedule: Systems/Tourists.

	Appeal (0-100) = Σ Weights[c] × sub-score[c] (each sub-score 0..1):
	  decor    placed pieces ÷ min(DecorFull, the Ranch Level's piece cap)
	  variety  different decor kinds placed ÷ VarietyFull (kinds: Kinds)
	  pens     half pens owned ÷ Economy.Pens.max, half pen places filled ÷ pen capacity
	  rarity   mean rarity of the RarityTop rarest pen monsters ÷ the top rarity (Mythic)
	  codex    Codex forms found ÷ CodexFull
	Stars: 1, then one more at each StarSteps score.

	Visits: one tourist every Interval seconds while the owner is online, on slots aligned to the
	server clock with a per-player offset (so every server agrees and players are spread out).
	Each pays SecondsPerStar × stars seconds of ranch income (Rewards, source "tourists"). Slots
	missed while away are paid on the next join, at most AwayMax, with one Welcome Back line.
	The Guestbook keeps the newest BookSize reviews.
]]

local Tourists = {}

Tourists.Unlock = "tourists"
Tourists.Interval = 600 -- seconds between tourists
Tourists.AwayMax = 6 -- visits paid for time away
Tourists.BookSize = 20 -- reviews kept
Tourists.SecondsPerStar = 40 -- ranch income seconds per star, per visit
Tourists.StarSteps = { 20, 40, 60, 80 } -- appeal for 2, 3, 4 and 5 stars

Tourists.Weights = { decor = 25, variety = 20, pens = 20, rarity = 20, codex = 15 }
Tourists.DecorFull = 40
Tourists.VarietyFull = 8
Tourists.RarityTop = 3
Tourists.CodexFull = 60

-- Decor kinds (Config/Decor `kind`), in the order the tips suggest missing ones.
Tourists.Kinds = { "light", "water", "plant", "seat", "path", "fence", "arch", "statue", "toy", "fun" }

Tourists.Categories = {
	{ id = "decor", name = "Decor", color = "#EF6FA8" },
	{ id = "variety", name = "Variety", color = "#8B6AD8" },
	{ id = "pens", name = "Pens", color = "#43B649" },
	{ id = "rarity", name = "Rare monsters", color = "#F2A93B" },
	{ id = "codex", name = "Codex", color = "#4FB6F2" },
}

-- The tip for the weakest category. Variety names the first missing kind instead.
Tourists.Tips = {
	decor = { text = "Place more decor around your ranch" },
	variety = { text = "Try some new kinds of decor" },
	pens = { text = "Fill your pens" },
	rarity = { text = "Rare monsters in your pens draw a crowd" },
	codex = { text = "Discover more Codex forms" },
	perfect = { text = "Tourists love your ranch!" },
}
Tourists.KindTips = {
	light = { text = "More lights would be nice" },
	water = { text = "Try a water piece" },
	plant = { text = "Some plants would brighten it up" },
	seat = { text = "Visitors would love a place to sit" },
	path = { text = "A path would help visitors get around" },
	fence = { text = "A fence would tidy things up" },
	arch = { text = "An arch would make a grand entrance" },
	statue = { text = "A statue would impress visitors" },
	toy = { text = "Your monsters would enjoy a toy" },
	fun = { text = "Add something fun to look at" },
}

-- Review lines: praise for the strongest category, a gripe for the weakest (none at 100%).
-- No praise unless the strongest category is at least PraiseMin full: a bare ranch gets only its gripe.
Tourists.PraiseMin = 0.4
Tourists.Praise = {
	decor = { { text = "Such lovely decorations!" }, { text = "Every corner is beautifully decorated." } },
	variety = { { text = "So many different things to see!" }, { text = "I loved all the different decor." } },
	pens = { { text = "The pens are full of happy monsters!" }, { text = "What a busy, lively ranch!" } },
	rarity = { { text = "I saw a really rare monster!" }, { text = "Those rare monsters took my breath away!" } },
	codex = { { text = "This rancher knows so many monsters!" }, { text = "An amazing monster collection!" } },
}
Tourists.Gripes = {
	decor = { { text = "It felt a little bare." }, { text = "Some more decorations would help." } },
	variety = { { text = "Everything looked a bit the same." }, { text = "I wish there were more kinds of decor." } },
	pens = { { text = "Some pens looked empty." }, { text = "I hoped to see more monsters." } },
	rarity = { { text = "I didn't spot any rare monsters." }, { text = "The monsters were a bit ordinary." } },
	codex = { { text = "I'd love to see more kinds of monsters." }, { text = "The collection has room to grow." } },
}

-- Tourists' first names (not translated; the Guestbook marks them Localize = false).
Tourists.Visitors = {
	"Maya",
	"Leo",
	"Sofia",
	"Theo",
	"Nina",
	"Omar",
	"Lucia",
	"Kai",
	"Iris",
	"Hugo",
	"Zara",
	"Felix",
	"Ana",
	"Ravi",
	"Elsa",
	"Tomas",
}

-- World (the client's walk and the guestbook stand), plot-local studs; the plot faces +x.
Tourists.World = {
	stand = { 68, 16 }, -- beside the gate; Config.Decor.Layout.keepOut keeps decor off it
	enter = { 80, -2 }, -- where a tourist appears, just outside the gate
	spot = { 40, -2 }, -- where it stops to look, on the middle aisle
	speed = 8, -- studs a second
	pause = 6, -- seconds at the spot, with the stars bubble
	fresh = 30, -- a visit older than this (seconds) is not walked
}

Tourists.CategoryById = {}
for _, c in Tourists.Categories do
	Tourists.CategoryById[c.id] = c
end

return Tourists
