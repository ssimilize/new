--[[
	GeneLab (update 3.10 · Ranch life): the Gene Lab. Tune an Adult's weaker gene for Stardust,
	or lock a stat for its next baby with Star Shards. Rules in Logic/GeneLab, numbers in
	Config/GeneLab.

	Save section (profile.GeneLab):
	  day      = UTC day of `tunes`
	  tunes    = tunes used that day (successes and failures)
	  attempts = every tune this player ever made; seeds the next roll, so a rejoin never rerolls

	Actions:
	  GeneLab.Tune { id, stat }  -> { success, stat, gene, cost, chance, tunesLeft }
	  GeneLab.Lock { id, stat }  -> { stat, cost }

	Rules:
	  • unlock Config.GeneLab.Unlock; the monster is owned, an Adult and not busy (expedition,
	    breeding, job, trade: Monsters:Available)
	  • Tune: DailyTunes per UTC day; the weaker gene (Logic/GeneLab.Weaker) must be below Cap;
	    Stardust Cost(gene) is spent whatever the roll; a success adds +1 to that gene
	  • Lock: LockShards Star Shards (HallOfFame:SpendStarShards, never refunded); sets the
	    record's `geneLock` (a lock on another stat is replaced; the same stat again is refused).
	    Breeding.Claim consumes it; Monsters:Insert clears it when the monster changes hands

	Public API:
	  GeneLab:TunesLeft(player) -> number

	Bus: publishes GeneTuned { stat, success } for every tune (Weekly goal "genelab_5").
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local Genetics = require(Shared.Logic.Genetics)
local Logic = require(Shared.Logic.GeneLab)

local GeneLab = {
	Name = "GeneLab",
	Dependencies = { "Currency", "Progression", "Monsters", "HallOfFame" },
}

GeneLab.Profile = {
	Version = 1,
	Default = function()
		return { day = 0, tunes = 0, attempts = 0 }
	end,
	Migrate = function(section)
		return section
	end,
}

local ctx
local Config, Rules
local Currency, Progression, Monsters, HallOfFame

local function refreshDaily(player, s)
	local today = ctx:Day()
	if s.day ~= today then
		s.day = today
		s.tunes = 0
		ctx:Dirty(player, "day")
		ctx:Dirty(player, "tunes")
	end
end

local function statName(stat: string): string
	return Config.Genetics.StatNames[stat] or stat
end

-- The owned, free Adult the Lab works on (fails otherwise).
local function requireAdult(player, id: string, stat: string)
	Progression:Require(player, Rules.Unlock)
	if not table.find(Config.Genetics.Stats, stat) then
		ctx:Fail("That stat has no genes")
	end
	local m, why = Monsters:Available(player, id)
	if not m then
		ctx:Fail(why or "That monster doesn't exist")
	end
	if (m.stage or 1) < 3 then
		ctx:Fail(string.format("%s must be an Adult to use the Gene Lab", Formulas.DisplayName(m)))
	end
	return m
end

-- Public API ------------------------------------------------------------------------------

function GeneLab:TunesLeft(player): number
	local s = ctx:Section(player)
	return Logic.TunesLeft(s, ctx:Day())
end

-- Actions ---------------------------------------------------------------------------------

local function tune(player, payload)
	local m = requireAdult(player, payload.id, payload.stat)
	local s = ctx:Section(player)
	refreshDaily(player, s)
	if Logic.TunesLeft(s, s.day) <= 0 then
		ctx:Fail("No Gene Lab tunes left today. Come back tomorrow!")
	end
	local index, gene = Logic.Weaker(m.genes, payload.stat)
	local chance = Logic.Chance(gene)
	if not chance then
		ctx:Fail(
			string.format("Both %s genes are %d or higher. Only breeding surges can raise them now.", statName(payload.stat), Rules.Cap)
		)
	end
	local cost = Logic.Cost(gene)
	Currency:Charge(player, { stardust = cost }, "genelab")

	local attempt = s.attempts or 0
	local success = Logic.Roll(Logic.Seed(player.UserId, m.id, attempt), chance)
	s.attempts = attempt + 1
	s.tunes = (s.tunes or 0) + 1
	ctx:Dirty(player, "attempts")
	ctx:Dirty(player, "tunes")

	if success then
		-- Genes may be missing or partial on an odd record: write a full copy back.
		local genes = Genetics.Copy(m.genes)
		genes[payload.stat][index] = gene + 1
		m.genes = genes
		Monsters:Changed(player, m.id, { "genes" })
	end
	ctx.Bus:Publish("GeneTuned", player, { stat = payload.stat, success = success })
	ctx.Analytics.Custom(player, "GeneTuned", gene, { stat = payload.stat, success = tostring(success) })
	return {
		success = success,
		stat = payload.stat,
		gene = if success then gene + 1 else gene,
		cost = cost,
		chance = chance,
		tunesLeft = Logic.TunesLeft(s, s.day),
	}
end

local function lock(player, payload)
	local m = requireAdult(player, payload.id, payload.stat)
	if m.geneLock == payload.stat then
		ctx:Fail("That gene is already locked")
	end
	if not HallOfFame:SpendStarShards(player, Rules.LockShards, "genelab") then
		ctx:Fail("Not enough Star Shards")
	end
	m.geneLock = payload.stat
	Monsters:Changed(player, m.id, { "geneLock" })
	ctx.Analytics.Custom(player, "GeneLocked", Rules.LockShards, { stat = payload.stat })
	return { stat = payload.stat, cost = Rules.LockShards }
end

-- Lifecycle -----------------------------------------------------------------------------------

function GeneLab.Init(context)
	ctx = context
	Config = ctx.Config
	Rules = Config.GeneLab
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	HallOfFame = ctx:GetSystem("HallOfFame")

	ctx.Net:Handle("GeneLab.Tune", tune)
	ctx.Net:Handle("GeneLab.Lock", lock)
end

function GeneLab.PlayerAdded(player)
	refreshDaily(player, ctx:Section(player))
end

return GeneLab
