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

return Boss
