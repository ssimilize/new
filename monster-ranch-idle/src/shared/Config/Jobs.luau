--[[
	Jobs (update 3.7): the Job Board. Teens and Adults resting in the barn take a job, and every
	job runs on one stat, so rarity, level, stars, traits, mutations and genes all make a better
	worker. Logic/Jobs turns the stat into a rate; Systems/Jobs keeps the board.

	A worker's power W = its stat (Formulas.Stats) ÷ RefBase[stat], the average base stat of the
	species roster: about 0.5 for a Common Teen, 3 for a Lv 20 Uncommon, 35 for a maxed Mythic.

	  herder   HP    pen monsters lose Mood more slowly while you are online: the decay is
	                 × (1 − shield), shield = HerderShield × √W, all herders together at most 1
	  miner    ATK   coins/s = its own coin rate (Formulas.CoinRate) × MinerShare × ATK affinity,
	                 affinity = (species base ATK ÷ RefBase.atk) × (1 + ATK genes + ATK traits)
	  guard    DEF   every pen's coin jar holds GuardMinutes × √W more minutes, all guards
	                 together at most GuardMaxMinutes
	  forager  SPD   ForagerPerHour × √W food an hour, in the flavour the slot picked
	  scout    Luck  each whole hour on duty: ScoutPerHour × √W chance of one egg, drawn from
	                 ScoutEggs by weight among the eggs the player has unlocked

	Miners, foragers and scouts store at most MaxHours of work, then wait to be collected.
	Guards and herders work while assigned and have nothing to collect.
]]

local Jobs = {}

Jobs.Unlock = "jobs"
Jobs.BaseSlots = 2
Jobs.SlotUnlocks = { "jobs_slot_3", "jobs_slot_4", "jobs_slot_5" } -- one more slot each
Jobs.MaxSlots = Jobs.BaseSlots + #Jobs.SlotUnlocks
Jobs.MinStage = 2 -- Teens and Adults
Jobs.MaxHours = 8
Jobs.FullNotify = true -- a toast when a worker's storage fills (once per fill)

Jobs.RefBase = { hp = 140, atk = 35, def = 24, spd = 16, luck = 7 }

Jobs.HerderShield = 0.25
Jobs.MinerShare = 0.35
Jobs.GuardMinutes = 9.5
Jobs.GuardMaxMinutes = 90
Jobs.ForagerPerHour = 1.5
Jobs.ScoutPerHour = 0.027
Jobs.ScoutEggs = {
	{ egg = "meadow", weight = 55 },
	{ egg = "grove", weight = 30 },
	{ egg = "crystal", weight = 12 },
	{ egg = "royal", weight = 3 },
}

Jobs.List = {
	{
		id = "herder",
		name = "Herder",
		stat = "hp",
		color = "#43B649",
		collects = false,
		desc = "Keeps your pen monsters happy: their Mood drops more slowly.",
	},
	{
		id = "miner",
		name = "Miner",
		stat = "atk",
		color = "#E8A23B",
		collects = true,
		desc = "Digs up coins: part of what it would earn in a pen.",
	},
	{
		id = "guard",
		name = "Guard",
		stat = "def",
		color = "#94775A",
		collects = false,
		desc = "Watches the ranch: every coin jar holds more minutes.",
	},
	{
		id = "forager",
		name = "Forager",
		stat = "spd",
		color = "#E85F33",
		collects = true,
		desc = "Gathers food in the flavour you pick.",
	},
	{
		id = "scout",
		name = "Scout",
		stat = "luck",
		color = "#8B6AD8",
		collects = true,
		desc = "Searches the wilds: a chance each hour to find an egg.",
	},
}

Jobs.ById = {}
Jobs.Ids = {}
for _, job in Jobs.List do
	Jobs.ById[job.id] = job
	table.insert(Jobs.Ids, job.id)
end

return Jobs
