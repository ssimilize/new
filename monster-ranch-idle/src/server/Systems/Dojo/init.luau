--[[
	Dojo (update 3.11 · Seasons & secrets): Adults learn battle techniques. Numbers in
	Config/Techniques, rules in Logic/Dojo, the battle side in Logic/BattleSim.

	Save section (profile.Dojo):
	  training = false | { id, tech, lv, startedAt, readyAt }  -- the one training mat
	  trained  = techniques trained here, lifetime
	A monster's techniques live on its record: `m.tech = { { id, lv } }` (at most 2).

	Actions:
	  Dojo.Train { id, tech }   -> { tech, lv, cost, readyAt }  learn (lv 1) or level up
	  Dojo.Forget { id, tech }  -> { tech }                     no refund
	  Dojo.Collect {}           -> { id, tech, lv }             once the timer is done

	Rules:
	  • unlock Config.Techniques.Unlock (Ranch Level 24); owned, free (Monsters:Available) Adults
	  • techniques of the monster's own element(s); 1 slot, the 2nd at Bond heart Slot2Hearts
	    (Bond:Hearts; without Bond only 1 slot)
	  • Train charges Stardust (Train[lv]) and puts the monster on the mat with busy tag "dojo"
	    until collected; one training at a time
	  • Forget: not while that monster is on the mat; no refund. Replacing = Forget, then Train
	  • Monsters:Insert keeps `tech` (it travels with a traded monster); Pedigree ignores it

	Bus: publishes SkillTrained (player, { monsterId, skill, level }) on Collect (Weekly "dojo_3");
	WelcomeItem when a training finished while the player was away.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local Logic = require(Shared.Logic.Dojo)

local Dojo = {
	Name = "Dojo",
	Dependencies = { "Currency", "Progression", "Monsters" },
	OptionalDependencies = { "Bond" },
}

Dojo.Profile = {
	Version = 1,
	Default = function()
		return { training = false, trained = 0 }
	end,
	Migrate = function(section)
		return section
	end,
}

local ctx
local Config, Rules
local Currency, Progression, Monsters
local Bond

local function section(player)
	return ctx:Section(player)
end

local function hearts(player, id: string): number
	if Bond and type(Bond.Hearts) == "function" then
		return Bond:Hearts(player, id)
	end
	return 0
end

local function techName(techId: string): string
	local tech = Rules.ById[techId]
	return if tech then tech.name else techId
end

local function clearTraining(player)
	local s = section(player)
	local training = s.training
	s.training = false
	ctx:Dirty(player, "training")
	if training then
		local m = Monsters:Get(player, training.id)
		if m and m.busy == Rules.BusyTag then
			Monsters:SetBusy(player, m.id, false)
		end
	end
end

-- Public API ------------------------------------------------------------------------------

function Dojo:Slots(player, id: string): number
	return Logic.Slots(hearts(player, id))
end

-- Actions ---------------------------------------------------------------------------------

local function train(player, payload)
	Progression:Require(player, Rules.Unlock)
	local s = section(player)
	if s.training then
		ctx:Fail("The Dojo mat is taken. Collect the current training first")
	end
	local m, why = Monsters:Available(player, payload.id)
	if not m then
		ctx:Fail(why or "That monster doesn't exist")
	end
	local lv, whyNot = Logic.Check(m, payload.tech, hearts(player, m.id))
	if not lv then
		ctx:Fail(whyNot or "That technique can't be trained")
	end
	local cost, seconds = Logic.Cost(lv)
	Currency:Charge(player, { stardust = cost }, "dojo")
	local now = ctx:Now()
	s.training = { id = m.id, tech = payload.tech, lv = lv, startedAt = now, readyAt = now + seconds }
	ctx:Dirty(player, "training")
	Monsters:SetBusy(player, m.id, Rules.BusyTag)
	ctx.Analytics.Custom(player, "DojoTrain", cost, { tech = payload.tech, lv = tostring(lv) })
	return { tech = payload.tech, lv = lv, cost = cost, readyAt = now + seconds }
end

local function forget(player, payload)
	Progression:Require(player, Rules.Unlock)
	local m = Monsters:Get(player, payload.id)
	if not m then
		ctx:Fail("That monster doesn't exist")
	end
	local training = section(player).training
	if training and training.id == m.id then
		ctx:Fail("Wait until this monster finishes training")
	end
	if Logic.Level(m, payload.tech) == 0 then
		ctx:Fail("This monster doesn't know that technique")
	end
	local list = Logic.Forget(m.tech, payload.tech)
	m.tech = if #list > 0 then list else nil
	Monsters:Changed(player, m.id, { "tech" })
	return { tech = payload.tech }
end

local function collect(player)
	local training = section(player).training
	if not training then
		ctx:Fail("Nobody is training at the Dojo")
	end
	if ctx:Now() < training.readyAt then
		ctx:Fail("The training isn't finished yet")
	end
	local m = Monsters:Get(player, training.id)
	clearTraining(player)
	if not m then
		return { id = training.id, tech = training.tech, lv = 0 }
	end
	m.tech = Logic.Apply(m.tech, training.tech, training.lv)
	Monsters:Changed(player, m.id, { "tech" })
	local s = section(player)
	s.trained = (s.trained or 0) + 1
	ctx:Dirty(player, "trained")
	ctx.Bus:Publish("SkillTrained", player, { monsterId = m.id, skill = training.tech, level = training.lv })
	ctx:Notify(player, string.format("%s learned %s Lv %d!", Formulas.DisplayName(m), techName(training.tech), training.lv), "success")
	return { id = m.id, tech = training.tech, lv = training.lv }
end

-- Lifecycle -----------------------------------------------------------------------------------

function Dojo.Init(context)
	ctx = context
	Config = ctx.Config
	Rules = Config.Techniques
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")

	ctx.Net:Handle("Dojo.Train", train)
	ctx.Net:Handle("Dojo.Forget", forget)
	ctx.Net:Handle("Dojo.Collect", collect)

	ctx.Bus:Subscribe("MonsterRemoved", function(player, detail)
		local s = player and section(player)
		if s and s.training and s.training.id == detail.id then
			s.training = false
			ctx:Dirty(player, "training")
		end
	end)
end

function Dojo.Start()
	Bond = ctx:GetSystem("Bond")
end

function Dojo.PlayerAdded(player, info)
	local s = section(player)
	if s.trained == nil then
		s.trained = 0
	end
	local training = s.training
	if not training then
		s.training = false
		return
	end
	local m = Monsters:Get(player, training.id)
	if not m then
		s.training = false
		ctx:Dirty(player, "training")
		return
	end
	-- Re-assert the busy tag in case a crash saved the monster without it.
	if m.busy ~= Rules.BusyTag then
		Monsters:SetBusy(player, m.id, Rules.BusyTag)
	end
	local lastSeen = info and info.lastSeen or 0
	if lastSeen > 0 and training.readyAt <= ctx:Now() and training.readyAt > lastSeen then
		ctx.Bus:Publish("WelcomeItem", player, {
			kind = "dojo",
			text = string.format("%s finished training at the Dojo", Formulas.DisplayName(m)),
		})
	end
end

return Dojo
