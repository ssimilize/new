--[[
	Stampede: the server boss. Starts every `Period` seconds (aligned to the clock, so
	:00 and :30), lasts `Duration` seconds. Boss HP scales with the combined power of the
	players who joined, so a full server always wins if everyone takes part.
]]

local Boss = {}

Boss.Unlock = "boss"
Boss.Period = 30 * 60
Boss.Duration = 90
Boss.LobbySeconds = 60 -- join button appears this long before the start
Boss.TickSeconds = 1
Boss.HpPerSquadPower = 1.2 -- boss HP = sum(squad power) × Duration × HpPerSquadPower × 0.8
Boss.DamagePerPowerPerSecond = 1.0
Boss.CheerMaxBonus = 0.2 -- +20% damage at a full cheer meter
Boss.CheerPerTap = 0.01
Boss.CheerDecayPerSecond = 0.02
Boss.MaxTapsPerRequest = 20

-- Rotation: the boss for a given start time is Rotation[(slot % #Rotation) + 1].
Boss.Rotation = {
	{ id = "mossback", name = "Old Mossback", line = "pebblet", form = "boulderback", element = "stone" },
	{ id = "brineclaw", name = "Queen Brineclaw", line = "bubblin", form = "tsunamander", element = "tide" },
	{ id = "magmaw", name = "Magmaw", line = "emberslug", form = "cinderwyrm", element = "ember" },
	{ id = "hollowking", name = "The Hollow King", line = "hushling", form = "hollowgaze", element = "gloom" },
}

Boss.Rewards = {
	participation = {
		{ kind = "coins", seconds = 600 }, -- 10 minutes of the player's ranch output
		{ kind = "food", id = "random", amount = 5 },
		{ kind = "treats", amount = 5 },
		{ kind = "gems", amount = 5 },
	},
	egg = "stampede",
	shareForEggChance = 0.05, -- players with ≥5% of total damage…
	eggChance = 0.25, -- …have this chance of a Stampede Egg
	topGuaranteed = 3, -- top 3 by damage always get one
	minDamageShare = 0.001, -- below this you only get participation if you cheered
}

-- Cheer taps accepted per second per player (server-side cap on top of the request rate limit).
Boss.MaxTapsPerSecond = 15

-- Glow-up U: the Stampede, live in the world (Controllers/StampedeArena, Logic/StampedeArena).
-- Where it stands: Config.World.StampedeArena. Nothing here changes damage or rewards.
Boss.Arena = {
	squadPerPlayer = 3, -- squad looks per player in global.Boss.squads (server cap)
	squadPlayers = 16, -- players listed there, in join order
	maxMonsters = { 8, 16, 24 }, -- squad models drawn, by Visuals/Quality level (low, medium, high)
	bossScale = 8, -- the giant: MonsterModel.Build opts.scale
	ringInner = 18, -- studs from the centre to the first ring of squads
	ringGap = 6, -- studs between rings
	ringSpacing = 6, -- studs between neighbours on a ring
	attackEvery = 2.4, -- seconds between one squad monster's attacks (staggered round the ring)
	bossAttackEvery = 4.5, -- the giant swings this often
	flinchGap = 1.5, -- at most one hurt flinch this often while damage lands
	staggers = { 0.75, 0.5, 0.25 }, -- HP fractions where the giant staggers
	chargeFrom = 70, -- studs east of the centre the giant charges in from
	boltsPerSecond = 6, -- cheer bolts drawn per second (taps beyond this still count)
	boltSeconds = 0.35, -- flight time of a bolt
	viewRange = 320, -- models are built while the player is this close to the centre
	nearRange = 90, -- the Cheer button shows this close; farther away, "To the arena"
	roarPitch = 0.55, -- the giant's cry, pitched down
	fallSeconds = 2.2, -- the fall before the loot fountain
	fountainSeconds = 2.6, -- the fountain before the result popup
	leaveSeconds = 4, -- after the fall or the end, models are removed this much later
	storm = { tint = "#A9B4D6", brightness = -0.09, contrast = 0.12, saturation = -0.28, fade = 2.5 },
	lightningEvery = { 7, 14 }, -- seconds between lightning flashes while the fight runs
}

return Boss
