--[[
	Kitchen & Pantry (update 3.10): a Kitchen on the player's plot (Systems/World builds it, the
	client's "Cook" prompt opens the Kitchen screen) cooks food into dishes on the server clock.
	Dishes wait in the Pantry until they are served to a monster. Recipes and numbers in
	Config.Kitchen, rules in Logic/Kitchen.

	Save section (profile.Kitchen), version 1:
	  slots    = { [1..MaxSlots] = { recipe = id|false, startedAt, readyAt } }   -- always MaxSlots
	  pantry   = { [dishId] = n }                  -- at most Config.Kitchen.PantryCap each
	  golden   = number                            -- golden produce (a recipe ingredient)
	  seeds    = number                            -- Golden seeds waiting to be planted
	  harvests = number                            -- food plots harvested since the kitchen opened
	                                                  (the n-th rolls Logic/Kitchen.GoldenSeed)
	  boosts   = { [monsterId] = { job = { { from, to } }, loot = boolean } }
	  cooked   = number                            -- dishes collected, ever
	Session (session.Kitchen): { slotCount, fish, fishing }   -- fish = Fishing:FishCount (0 without
	                                                            Fishing); fishing = Fishing is plugged in and unlocked

	Actions:
	  Kitchen.Cook { recipe, slot? }   charges every ingredient at once (all or nothing) and starts
	                                   the slot (the first free one when `slot` is nil)
	  Kitchen.Collect {}               moves finished dishes into the Pantry -> { dishes = { [id]: n } }
	  Kitchen.Serve { id, dish }       one Pantry dish to one monster -> { effect }
	  Kitchen.PlantGolden { plot }     a Golden seed into an empty Feed Garden plot -> { readyAt }

	Effects (Config.Kitchen.Effects): meals (Monsters:AddMeals + MonsterFed per meal + feed Mood),
	mood (to the max), bond (Bond:AddHeart), job (Jobs:RegisterOutputBoost "kitchen"), loot
	(Expeditions:RegisterLootModifier "kitchen", spent when a run with that monster is claimed).

	Optional systems, looked up in Start: Fishing (FishCount / SpendFish; absent = 0 fish), Bond,
	Jobs, Expeditions, Ranch (golden crop + harvest hook).

	Bus: publishes DishCooked (player, { dish, count }) per collected slot; WelcomeItem when dishes
	finished cooking while the player was away.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local Logic = require(Shared.Logic.Kitchen)

local Kitchen = {
	Name = "Kitchen",
	Dependencies = { "Currency", "Progression", "Monsters" },
	OptionalDependencies = { "Fishing", "Bond", "Jobs", "Expeditions", "Ranch" },
}

local HOUR = 3600

local ctx
local Config, Rules
local Currency, Progression, Monsters
local Fishing, Bond

local announced = {} -- [player] = { [slot] = readyAt } finished slots already toasted

Kitchen.Profile = {
	Version = 1,
	Default = function()
		local slots = {}
		for i = 1, Rules.MaxSlots do
			slots[i] = Logic.EmptySlot()
		end
		return { slots = slots, pantry = {}, golden = 0, seeds = 0, harvests = 0, boosts = {}, cooked = 0 }
	end,
}

-- Helpers ------------------------------------------------------------------------------

local function section(player)
	return ctx:Section(player)
end

local function isUnlocked(player)
	return function(key: string): boolean
		return Progression:IsUnlocked(player, key)
	end
end

local function fishCount(player): number
	if not Fishing then
		return 0
	end
	local ok, n = pcall(Fishing.FishCount, Fishing, player)
	return if ok and type(n) == "number" then math.max(0, math.floor(n)) else 0
end

local function refreshSession(player)
	local sess = ctx:Session(player)
	if not sess or not section(player) then
		return
	end
	local count = Logic.SlotCount(isUnlocked(player))
	local fish = fishCount(player)
	-- The fish recipes read "Needs fish from the Fishing Pond" until the Pond is open to this player.
	local fishing = Fishing ~= nil and Progression:IsUnlocked(player, Config.Fishing.Unlock)
	if sess.slotCount ~= count or sess.fish ~= fish or sess.fishing ~= fishing then
		sess.slotCount = count
		sess.fish = fish
		sess.fishing = fishing
		ctx:DirtySession(player)
	end
end

local function dishName(id: string): string
	local r = Rules.ById[id]
	return if r then r.name else id
end

-- Public API ------------------------------------------------------------------------------

function Kitchen:SlotCount(player): number
	return Logic.SlotCount(isUnlocked(player))
end

-- Actions ---------------------------------------------------------------------------------

local function cook(player, payload)
	Progression:Require(player, Rules.Unlock)
	local s = section(player)
	local open = Kitchen:SlotCount(player)
	local index = payload.slot
	if index then
		if index > open then
			ctx:Fail(string.format("Cooking slot %d opens at Ranch Level %d", index, Progression:UnlockLevel(Rules.SlotUnlock)))
		end
		if s.slots[index].recipe then
			ctx:Fail("That cooking slot is busy")
		end
	else
		for i = 1, open do
			if not s.slots[i].recipe then
				index = i
				break
			end
		end
		if not index then
			ctx:Fail("Every cooking slot is busy")
		end
	end
	local recipe = Rules.ById[payload.recipe]
	local food, fish, golden = Logic.Split(recipe)
	-- Check everything first so nothing is spent unless all of it can be.
	if fish > 0 then
		if not Fishing then
			ctx:Fail("Needs fish from the Fishing Pond")
		elseif fishCount(player) < fish then
			ctx:Fail("Not enough fish")
		end
	end
	if golden > (s.golden or 0) then
		ctx:Fail(string.format("Not enough %s", Rules.Golden.name))
	end
	local cost = {}
	for flavor, n in food do
		cost["food." .. flavor] = n
	end
	local ok, missing = Currency:CanAfford(player, cost)
	if not ok then
		ctx:Fail(Currency:MissingText(missing :: string))
	end
	if fish > 0 then
		local called, spent = pcall(Fishing.SpendFish, Fishing, player, fish)
		if not called or spent ~= true then
			ctx:Fail("Not enough fish")
		end
	end
	if not Currency:Spend(player, cost, "kitchen") then
		ctx:Fail("Not enough food")
	end
	if golden > 0 then
		s.golden -= golden
		ctx:Dirty(player, "golden")
	end
	local now = ctx:Now()
	s.slots[index] = { recipe = recipe.id, startedAt = now, readyAt = now + recipe.minutes * 60 }
	ctx:Dirty(player, "slots")
	if announced[player] then
		announced[player][index] = nil
	end
	refreshSession(player)
	return { slot = index, readyAt = s.slots[index].readyAt }
end

-- Moves every finished slot whose dishes fit into the Pantry. Returns ({ [dish] = n }, blocked).
local function collectReady(player)
	local s = section(player)
	local now = ctx:Now()
	local got, blocked = {}, nil
	for index, slot in s.slots do
		if Logic.IsReady(slot, now) then
			local recipe = Rules.ById[slot.recipe]
			if not recipe then
				s.slots[index] = Logic.EmptySlot()
				ctx:Dirty(player, "slots")
			else
				local have = s.pantry[recipe.id] or 0
				if have + recipe.makes > Rules.PantryCap then
					blocked = blocked or recipe.id
				else
					s.pantry[recipe.id] = have + recipe.makes
					s.cooked = (s.cooked or 0) + recipe.makes
					s.slots[index] = Logic.EmptySlot()
					got[recipe.id] = (got[recipe.id] or 0) + recipe.makes
					ctx:Dirty(player, "pantry", recipe.id)
					ctx:Dirty(player, "slots")
					ctx:Dirty(player, "cooked")
					ctx.Bus:Publish("DishCooked", player, { dish = recipe.id, count = recipe.makes })
				end
			end
		end
	end
	return got, blocked
end

local function collect(player)
	Progression:Require(player, Rules.Unlock)
	local got, blocked = collectReady(player)
	if next(got) == nil then
		if blocked then
			ctx:Fail(string.format("The Pantry has no room for more %s", dishName(blocked)))
		end
		ctx:Fail("Nothing is ready yet")
	end
	return { dishes = got }
end

local function boostOf(player, id: string, create: boolean?)
	local s = section(player)
	local entry = s.boosts[id]
	if not entry and create then
		entry = { job = {}, loot = false }
		s.boosts[id] = entry
	end
	return entry
end

local function serve(player, payload)
	Progression:Require(player, Rules.Unlock)
	local s = section(player)
	local recipe = Rules.ById[payload.dish]
	if (s.pantry[recipe.id] or 0) <= 0 then
		ctx:Fail(string.format("You have no %s in the Pantry", recipe.name))
	end
	local m = Monsters:Get(player, payload.id)
	if not m then
		ctx:Fail("That monster doesn't exist")
	end
	local problem = Logic.ServeProblem(recipe, m, {
		hearts = if Bond then Bond:Hearts(player, m.id) else 0,
		boost = boostOf(player, m.id),
		now = ctx:Now(),
	})
	if problem then
		ctx:Fail(problem)
	end
	local effect = recipe.effect
	local now = ctx:Now()
	if effect == "meals" then
		if Monsters:AddMeals(player, m.id, recipe.flavor, Rules.MealsPerDish) <= 0 then
			ctx:Fail(string.format("%s has eaten enough to grow", Formulas.DisplayName(m)))
		end
		Monsters:AddMood(player, m.id, Config.Economy.Mood.feedGain * Rules.MealsPerDish)
		for _ = 1, Rules.MealsPerDish do
			ctx.Bus:Publish("MonsterFed", player, { id = m.id, flavor = recipe.flavor })
		end
	elseif effect == "mood" then
		Monsters:AddMood(player, m.id, Config.Economy.Mood.max)
	elseif effect == "bond" then
		if not Bond or not Bond:AddHeart(player, m.id, "dish") then
			ctx:Fail(string.format("%s already has every Bond heart", Formulas.DisplayName(m)))
		end
	elseif effect == "job" then
		local entry = boostOf(player, m.id, true)
		entry.job = Logic.AddWindow(entry.job, now, Rules.JobBoost.hours * HOUR)
		ctx:Dirty(player, "boosts", m.id)
	elseif effect == "loot" then
		local entry = boostOf(player, m.id, true)
		entry.loot = true
		ctx:Dirty(player, "boosts", m.id)
	end
	s.pantry[recipe.id] -= 1
	if s.pantry[recipe.id] <= 0 then
		s.pantry[recipe.id] = nil
	end
	ctx:Dirty(player, "pantry", recipe.id)
	ctx:Notify(player, string.format("%s enjoyed the %s!", Formulas.DisplayName(m), recipe.name), "success")
	return { effect = effect }
end

local function plantGolden(player, payload)
	Progression:Require(player, Rules.Unlock)
	local s = section(player)
	if (s.seeds or 0) <= 0 then
		ctx:Fail("You have no Golden seeds")
	end
	local Ranch = ctx:GetSystem("Ranch")
	if not Ranch then
		ctx:Fail("The Feed Garden isn't available right now")
	end
	Progression:Require(player, Config.Economy.Garden.unlock)
	local readyAt, err = Ranch:PlantCrop(player, payload.plot, Rules.Golden.id, Rules.GoldenGrowMinutes * 60)
	if not readyAt then
		ctx:Fail(err or "Something is already growing there")
	end
	s.seeds -= 1
	ctx:Dirty(player, "seeds")
	return { readyAt = readyAt }
end

-- Timers ------------------------------------------------------------------------------------

local function announceReady(player)
	local s = section(player)
	local seen = announced[player]
	if not s or not seen then
		return
	end
	local now = ctx:Now()
	for index, slot in s.slots do
		if Logic.IsReady(slot, now) and seen[index] ~= slot.readyAt then
			seen[index] = slot.readyAt
			ctx:Notify(player, string.format("%s is ready in the Kitchen!", dishName(slot.recipe)), "info")
		end
	end
end

-- Lifecycle -----------------------------------------------------------------------------------

function Kitchen.Init(context)
	ctx = context
	Config = ctx.Config
	Rules = Config.Kitchen
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	table.clear(announced)

	ctx.Net:Handle("Kitchen.Cook", cook)
	ctx.Net:Handle("Kitchen.Collect", collect)
	ctx.Net:Handle("Kitchen.Serve", serve)
	ctx.Net:Handle("Kitchen.PlantGolden", plantGolden)

	ctx.Bus:Subscribe("FishCaught", function(player)
		refreshSession(player)
	end)
	ctx.Bus:Subscribe("LevelUp", function(player)
		refreshSession(player)
	end)
	ctx.Bus:Subscribe("MonsterRemoved", function(player, detail)
		local s = player and section(player)
		local id = type(detail) == "table" and detail.id
		if s and type(id) == "string" and s.boosts[id] then
			s.boosts[id] = nil
			ctx:Dirty(player, "boosts", id)
		end
	end)
	-- A loot snack lasts one expedition: spent when a run with that monster is claimed.
	ctx.Bus:Subscribe("ExpeditionClaimed", function(player, detail)
		local s = player and section(player)
		if not s or type(detail) ~= "table" or type(detail.squad) ~= "table" then
			return
		end
		for _, id in detail.squad do
			local entry = s.boosts[id]
			if entry and entry.loot then
				entry.loot = false
				ctx:Dirty(player, "boosts", id)
			end
		end
	end)

	ctx:Every(5, function()
		for _, player in ctx:Players() do
			announceReady(player)
			refreshSession(player)
		end
	end)
end

function Kitchen.Start()
	Fishing = ctx:GetSystem("Fishing")
	Bond = ctx:GetSystem("Bond")
	local Jobs = ctx:GetSystem("Jobs")
	if Jobs and Jobs.RegisterOutputBoost then
		Jobs:RegisterOutputBoost("kitchen", function(player, id)
			local s = section(player)
			return if s then Logic.JobBoosts(s.boosts[id]) else nil
		end)
	end
	local Expeditions = ctx:GetSystem("Expeditions")
	if Expeditions then
		Expeditions:RegisterLootModifier("kitchen", function(player, ids)
			local s = section(player)
			local pct = 0
			if s and type(ids) == "table" then
				for _, id in ids do
					local entry = s.boosts[id]
					if entry and entry.loot then
						pct += Rules.LootPct
					end
				end
			end
			return pct
		end)
	end
	local Ranch = ctx:GetSystem("Ranch")
	if Ranch and Ranch.RegisterCrop then
		Ranch:RegisterCrop(Rules.Golden.id, function(player)
			local s = section(player)
			if not s then
				return
			end
			s.golden = (s.golden or 0) + Rules.GoldenYield
			ctx:Dirty(player, "golden")
			ctx:Notify(player, string.format("+%d %s for the Kitchen!", Rules.GoldenYield, Rules.Golden.name), "reward")
		end)
		Ranch:RegisterHarvestHook("kitchen", function(player)
			local s = section(player)
			if not s or not Progression:IsUnlocked(player, Rules.Unlock) then
				return
			end
			s.harvests = (s.harvests or 0) + 1
			ctx:Dirty(player, "harvests")
			if Logic.GoldenSeed(player.UserId, s.harvests) then
				s.seeds = (s.seeds or 0) + 1
				ctx:Dirty(player, "seeds")
				ctx:Notify(player, "You found a Golden seed! Plant it in the Feed Garden.", "reward")
			end
		end)
	end
end

function Kitchen.PlayerAdded(player, info)
	local s = section(player)
	for i = 1, Rules.MaxSlots do
		if type(s.slots[i]) ~= "table" then
			s.slots[i] = Logic.EmptySlot()
		end
	end
	s.pantry = if type(s.pantry) == "table" then s.pantry else {}
	s.boosts = if type(s.boosts) == "table" then s.boosts else {}
	-- Monsters that left while the player was away take their boosts with them.
	local stale = {}
	for id in s.boosts do
		if not Monsters:Get(player, id) then
			table.insert(stale, id)
		end
	end
	for _, id in stale do
		s.boosts[id] = nil
		ctx:Dirty(player, "boosts", id)
	end
	local now = ctx:Now()
	local lastSeen = info and info.lastSeen or 0
	local seen = {}
	local finished = 0
	for index, slot in s.slots do
		if Logic.IsReady(slot, now) then
			seen[index] = slot.readyAt
			if lastSeen > 0 and slot.readyAt > lastSeen then
				finished += Rules.ById[slot.recipe] and Rules.ById[slot.recipe].makes or 1
			end
		end
	end
	announced[player] = seen
	if finished > 0 then
		ctx.Bus:Publish("WelcomeItem", player, {
			kind = "kitchen",
			text = if finished == 1
				then "A dish finished cooking in your Kitchen"
				else string.format("%d dishes finished cooking in your Kitchen", finished),
		})
	end
	refreshSession(player)
end

function Kitchen.PlayerRemoving(player)
	announced[player] = nil
end

return Kitchen
