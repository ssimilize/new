--[[
	Monsters (S2): owns every monster record, growth, feeding, levels, stars and the Codex.

	Save section (profile.Monsters):
	  list    = { [id] = Monster }      -- see ARCHITECTURE.md → Monster record
	  codex   = { [lineId] = { forms = { [formId] = true }, variants = { normal|golden|rainbow = true }, count } }
	  nextId  = number
	  grown   = number                   -- total growths (the first one is a short tutorial timer)

	Public API (other systems):
	  Monsters:Create(player, spec, source, force?) -> record?, err?   -- spec: see Logic/MonsterGen
	  Monsters:Insert(player, record, source) -> record                -- trade receive (new id)
	  Monsters:Get(player, id) -> record?                               -- live table: call Changed after edits
	  Monsters:All(player) -> { [id]: record }
	  Monsters:Count(player) -> number
	  Monsters:CodexCount(player) -> number                             -- forms discovered
	  Monsters:Capacity(player) -> number
	  Monsters:Remove(player, id, reason) -> record?                    -- refuses busy monsters
	  Monsters:Available(player, id) -> record?, why?                   -- exists and not busy
	  Monsters:SetBusy(player, id, tag | false)                          -- "expedition"|"breeding"|"trade"
	  Monsters:SetLocation(player, id, "barn"|"pen", penIndex)           -- Ranch only
	  Monsters:Changed(player, id, fields?)
	  Monsters:AddMutation(player, id, mutationId) -> "added"|"combined"|"duplicate"|"full"|"missing"
	  Monsters:AddMood(player, id, amount)
	  Monsters:AddVisibleTrait(player, id) -> traitId?                  -- Rebirth's 3rd trait slot
	  Monsters:CoinRate(player, id) -> number
	  Monsters:Stats(player, id) -> stats?
	  Monsters:Appearance(player, id) -> Appearance?
	  Monsters:RegisterCapacityProvider(fn(player) -> number)
	  Monsters:RegisterMoodFloorProvider(fn(player) -> number)
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local MonsterGen = require(Shared.Logic.MonsterGen)
local Mutation = require(Shared.Logic.Mutation)
local Appearance = require(Shared.Logic.Appearance)

local Monsters = {
	Name = "Monsters",
	Dependencies = { "Currency" },
}

Monsters.Profile = {
	Version = 1,
	Default = function()
		return { list = {}, codex = {}, nextId = 1, grown = 0 }
	end,
}

local ctx
local Currency
local Config

local capacityProviders = {}
local moodFloorProviders = {}
local growing = {} -- [player] = { [id] = true }

local DEFAULT_CAPACITY = 60
local VARIANT_NAMES = { [0] = "normal", [1] = "golden", [2] = "rainbow" }

-- Helpers ------------------------------------------------------------------------------

local function section(player)
	return ctx:Section(player)
end

local function mustGet(player, id: string)
	local m = section(player).list[id]
	if not m then
		ctx:Fail("That monster doesn't exist")
	end
	return m
end

local function recordCodex(player, m)
	local s = section(player)
	local entry = s.codex[m.line]
	if not entry then
		entry = { forms = {}, variants = {}, count = 0 }
		s.codex[m.line] = entry
	end
	entry.forms[m.form] = true
	entry.variants[VARIANT_NAMES[m.variant or 0]] = true
	ctx:Dirty(player, "codex", m.line)
end

local function trackGrowing(player, m, id: string)
	growing[player] = growing[player] or {}
	if (m.growEndsAt or 0) > 0 then
		growing[player][id] = true
	else
		growing[player][id] = nil
	end
end

local function moodFloor(player, m): number
	local floor = ctx.Config.Economy.Mood.floor
	for _, id in Formulas.ActiveTraits(m) do
		local t = Config.Traits.ById[id]
		if t and t.effect.moodFloor then
			floor = math.max(floor, t.effect.moodFloor)
		end
	end
	for _, provider in moodFloorProviders do
		local ok, value = pcall(provider, player)
		if ok and type(value) == "number" then
			floor = math.max(floor, value)
		end
	end
	return floor
end

-- Public API ------------------------------------------------------------------------------

function Monsters:RegisterCapacityProvider(fn)
	table.insert(capacityProviders, fn)
end

function Monsters:RegisterMoodFloorProvider(fn)
	table.insert(moodFloorProviders, fn)
end

function Monsters:Capacity(player): number
	if #capacityProviders == 0 then
		return DEFAULT_CAPACITY
	end
	local total = 0
	for _, provider in capacityProviders do
		local ok, value = pcall(provider, player)
		if ok and type(value) == "number" then
			total += value
		end
	end
	return total
end

function Monsters:Count(player): number
	local s = section(player)
	if not s then
		return 0
	end
	local n = 0
	for _ in s.list do
		n += 1
	end
	return n
end

-- Forms discovered across every line (the Codex completion count).
function Monsters:CodexCount(player): number
	local s = section(player)
	if not s then
		return 0
	end
	local n = 0
	for _, entry in s.codex do
		for _ in entry.forms or {} do
			n += 1
		end
	end
	return n
end

function Monsters:Get(player, id: string)
	local s = section(player)
	return s and s.list[id]
end

function Monsters:All(player)
	local s = section(player)
	return s and s.list or {}
end

function Monsters:Changed(player, id: string, fields: { string }?)
	ctx:Dirty(player, "list", id)
	ctx.Bus:Publish("MonsterChanged", player, { id = id, fields = fields })
end

local function insert(player, record, source: string)
	local s = section(player)
	local id = "m" .. tostring(s.nextId)
	s.nextId += 1
	record.id = id
	s.list[id] = record
	s.codex[record.line] = s.codex[record.line] or { forms = {}, variants = {}, count = 0 }
	s.codex[record.line].count += 1
	recordCodex(player, record)
	trackGrowing(player, record, id)
	ctx:Dirty(player, "list", id)
	ctx:Dirty(player, "nextId")
	ctx.Bus:Publish("MonsterCreated", player, { id = id, source = source })
	return record
end

function Monsters:Create(player, spec, source: string, force: boolean?)
	local s = section(player)
	if not s then
		return nil, "Profile not loaded"
	end
	if not force and Monsters:Count(player) >= Monsters:Capacity(player) then
		return nil, "Your ranch is full. Sell monsters or upgrade the barn."
	end
	local record = MonsterGen.New(ctx.Rng, spec, ctx:Now())
	return insert(player, record, source), nil
end

function Monsters:Insert(player, record, source: string)
	local copy = table.clone(record)
	copy.muts = table.clone(record.muts or {})
	copy.traits = table.clone(record.traits or {})
	copy.meals = table.clone(record.meals or {})
	copy.loc, copy.pen, copy.busy, copy.locked = "barn", 0, false, false
	return insert(player, copy, source)
end

function Monsters:Available(player, id: string)
	local m = Monsters:Get(player, id)
	if not m then
		return nil, "That monster doesn't exist"
	end
	if m.busy then
		return nil, Formulas.DisplayName(m) .. " is busy"
	end
	return m, nil
end

function Monsters:Remove(player, id: string, reason: string)
	local s = section(player)
	local m = s and s.list[id]
	if not m or m.busy then
		return nil
	end
	s.list[id] = nil
	if growing[player] then
		growing[player][id] = nil
	end
	ctx:Dirty(player, "list", id)
	ctx.Bus:Publish("MonsterRemoved", player, { id = id, reason = reason, pen = m.pen, loc = m.loc })
	return m
end

-- Rolls one more visible trait (never hidden-only, never one it already has). Returns the
-- trait id, or nil when the monster is missing or has no trait left to roll.
function Monsters:AddVisibleTrait(player, id: string): number?
	local m = Monsters:Get(player, id)
	if not m then
		return nil
	end
	m.traits = m.traits or {}
	local taken = {}
	for _, t in m.traits do
		taken[t] = true
	end
	if m.hidden and m.hidden ~= 0 then
		taken[m.hidden] = true
	end
	local ok, trait = pcall(MonsterGen.PickTrait, ctx.Rng, taken, false)
	if not ok or trait == nil then
		return nil
	end
	table.insert(m.traits, trait)
	Monsters:Changed(player, id, { "traits" })
	return trait
end

function Monsters:SetBusy(player, id: string, tag: string | false)
	local m = Monsters:Get(player, id)
	if m then
		m.busy = tag
		Monsters:Changed(player, id, { "busy" })
	end
end

function Monsters:SetLocation(player, id: string, loc: string, pen: number)
	local m = Monsters:Get(player, id)
	if m then
		m.loc = loc
		m.pen = pen
		Monsters:Changed(player, id, { "loc", "pen" })
	end
end

function Monsters:AddMutation(player, id: string, mutationId: string): string
	local m = Monsters:Get(player, id)
	if not m then
		return "missing"
	end
	local list, result = Mutation.Add(m.muts, mutationId)
	if result == "added" or result == "combined" then
		m.muts = list
		Monsters:Changed(player, id, { "muts" })
	end
	return result
end

function Monsters:AddMood(player, id: string, amount: number)
	local m = Monsters:Get(player, id)
	if not m then
		return
	end
	local mood = Config.Economy.Mood
	local value = math.clamp((m.mood or mood.start) + amount, moodFloor(player, m), mood.max)
	if value ~= m.mood then
		m.mood = value
		Monsters:Changed(player, id, { "mood" })
	end
end

function Monsters:CoinRate(player, id: string): number
	local m = Monsters:Get(player, id)
	return if m then Formulas.CoinRate(m) else 0
end

function Monsters:Stats(player, id: string)
	local m = Monsters:Get(player, id)
	return m and Formulas.Stats(m)
end

function Monsters:Appearance(player, id: string)
	local m = Monsters:Get(player, id)
	return m and Appearance.Of(m)
end

-- Growth -------------------------------------------------------------------------------

local function evolve(player, id: string, m)
	local fromForm = m.form
	local nextStage = m.stage + 1
	local form
	if nextStage == 2 then
		form = Config.Species.ById[m.line].forms[2]
	else
		form = Config.Species.AdultForDiet(m.line, m.meals)
	end
	m.stage = nextStage
	m.form = form.id
	m.meals = {}
	m.growEndsAt = 0
	trackGrowing(player, m, id)
	recordCodex(player, m)
	Monsters:Changed(player, id, { "stage", "form", "meals", "growEndsAt" })
	ctx.Net:Fire(player, "Monsters.Evolved", { id = id, fromForm = fromForm, toForm = form.id, stage = nextStage })
	ctx.Bus:Publish("MonsterEvolved", player, { id = id, stage = nextStage, form = form.id })
	ctx.Bus:Publish("RanchXP", player, {
		amount = if nextStage == 2 then Config.Unlocks.XP.growTeen else Config.Unlocks.XP.growAdult,
		reason = "grow",
	})
	return form
end

local function processGrowth(player, now: number): number
	local set = growing[player]
	if not set then
		return 0
	end
	local done = 0
	for id in table.clone(set) do
		local m = Monsters:Get(player, id)
		if not m or (m.growEndsAt or 0) == 0 then
			set[id] = nil
		elseif now >= m.growEndsAt then
			evolve(player, id, m)
			done += 1
		end
	end
	return done
end

-- Lifecycle ----------------------------------------------------------------------------

function Monsters.Init(context)
	ctx = context
	table.clear(capacityProviders)
	table.clear(moodFloorProviders)
	table.clear(growing)
	Config = ctx.Config
	Currency = ctx:GetSystem("Currency")

	ctx.Net:Handle("Monsters.Rename", function(player, payload)
		local m = mustGet(player, payload.id)
		local name = string.gsub(payload.name, "^%s+", "")
		name = string.gsub(name, "%s+$", "")
		if name ~= "" then
			local filtered = ctx.Services.Text.Filter(name, player.UserId)
			if not filtered then
				ctx:Fail("That name couldn't be checked. Try again.")
			end
			name = filtered
		end
		m.name = name
		Monsters:Changed(player, payload.id, { "name" })
		return { name = name }
	end)

	ctx.Net:Handle("Monsters.SetLocked", function(player, payload)
		local m = mustGet(player, payload.id)
		m.locked = payload.locked
		Monsters:Changed(player, payload.id, { "locked" })
		return nil
	end)

	ctx.Net:Handle("Monsters.Feed", function(player, payload)
		local m = mustGet(player, payload.id)
		local amount = payload.amount or 1
		local needed = Formulas.MealsNeeded(m.stage)
		if needed then
			-- Never charge for meals beyond what growth needs (they would be wasted).
			local mealMult = Config.Traits.Product(Formulas.ActiveTraits(m), "mealMult")
			local remaining = math.max(0, needed - Formulas.MealsEaten(m))
			amount = math.clamp(amount, 1, math.max(1, math.ceil(remaining / mealMult)))
		end
		Currency:Charge(player, { ["food." .. payload.flavor] = amount }, "feed")
		local mealMult = Config.Traits.Product(Formulas.ActiveTraits(m), "mealMult")
		if needed then
			m.meals = m.meals or {}
			m.meals[payload.flavor] = (m.meals[payload.flavor] or 0) + amount * mealMult
		end
		Monsters:AddMood(player, payload.id, Config.Economy.Mood.feedGain * amount)
		Monsters:Changed(player, payload.id, { "meals" })
		for _ = 1, amount do
			ctx.Bus:Publish("MonsterFed", player, { id = payload.id, flavor = payload.flavor })
		end
		return { meals = Formulas.MealsEaten(m), mood = m.mood }
	end)

	ctx.Net:Handle("Monsters.LevelUp", function(player, payload)
		local m = mustGet(player, payload.id)
		local cap = Formulas.LevelCap(m)
		if m.lv >= cap then
			ctx:Fail(if m.stage < 3 then "Max level for this stage. Grow it up!" else "Max level. Add stars to raise the cap.")
		end
		local gained = 0
		for _ = 1, payload.times do
			if m.lv >= cap then
				break
			end
			local cost = Config.Economy.LevelCost(m.lv)
			if gained == 0 then
				Currency:Charge(player, cost, "levelup")
			elseif not Currency:Spend(player, cost, "levelup") then
				break
			end
			m.lv += 1
			gained += 1
			ctx.Bus:Publish("MonsterLeveled", player, { id = payload.id, lv = m.lv })
		end
		Monsters:Changed(player, payload.id, { "lv" })
		ctx.Bus:Publish("RanchXP", player, { amount = Config.Unlocks.XP.monsterLevelUp * gained, reason = "levelup" })
		return { lv = m.lv }
	end)

	ctx.Net:Handle("Monsters.Grow", function(player, payload)
		local m = mustGet(player, payload.id)
		if m.busy then
			ctx:Fail(Formulas.DisplayName(m) .. " is busy")
		end
		local ok, why = Formulas.CanGrow(m)
		if not ok then
			ctx:Fail(why or "Can't grow yet")
		end
		local s = section(player)
		local seconds = if s.grown == 0 then Config.Economy.TutorialGrowSeconds else Formulas.GrowSeconds(m)
		s.grown += 1
		ctx:Dirty(player, "grown")
		m.growEndsAt = ctx:Now() + seconds
		trackGrowing(player, m, payload.id)
		Monsters:Changed(player, payload.id, { "growEndsAt" })
		return { growEndsAt = m.growEndsAt }
	end)

	ctx.Net:Handle("Monsters.StarUp", function(player, payload)
		if payload.id == payload.fodder then
			ctx:Fail("Pick a different monster to fuse")
		end
		local m = mustGet(player, payload.id)
		local fodder = mustGet(player, payload.fodder)
		if fodder.line ~= m.line or fodder.rarity ~= m.rarity then
			ctx:Fail("Fuse a monster of the same species and rarity")
		end
		if fodder.locked then
			ctx:Fail(Formulas.DisplayName(fodder) .. " is locked")
		end
		if fodder.busy or m.busy then
			ctx:Fail("One of these monsters is busy")
		end
		if (m.stars or 1) >= Formulas.MaxStars(m) then
			ctx:Fail("Already at max stars")
		end
		Monsters:Remove(player, payload.fodder, "fuse")
		m.stars = (m.stars or 1) + 1
		Monsters:Changed(player, payload.id, { "stars" })
		return { stars = m.stars }
	end)

	ctx.Net:Handle("Monsters.Sell", function(player, payload)
		local s = section(player)
		local total, sold = 0, 0
		local unique = {}
		for _, id in payload.ids do
			unique[id] = true
		end
		local count = Monsters:Count(player)
		for id in unique do
			local m = s.list[id]
			if not m then
				ctx:Fail("That monster doesn't exist")
			elseif m.locked then
				ctx:Fail(Formulas.DisplayName(m) .. " is locked")
			elseif m.busy then
				ctx:Fail(Formulas.DisplayName(m) .. " is busy")
			end
		end
		local uniqueCount = 0
		for _ in unique do
			uniqueCount += 1
		end
		if count - uniqueCount < 1 then
			ctx:Fail("You need to keep at least one monster")
		end
		for id in unique do
			local m = s.list[id]
			total += Formulas.SellPrice(m)
			Monsters:Remove(player, id, "sell")
			sold += 1
		end
		Currency:Add(player, "coins", total, "sell")
		return { coins = total, sold = sold }
	end)

	ctx:Every(1, function()
		local now = ctx:Now()
		for _, player in ctx:Players() do
			processGrowth(player, now)
		end
	end)

	ctx:Every(Config.Economy.Mood.decayEvery, function()
		for _, player in ctx:Players() do
			for id in Monsters:All(player) do
				Monsters:AddMood(player, id, -Config.Economy.Mood.decayAmount)
			end
		end
	end)
end

function Monsters.PlayerAdded(player, _info)
	growing[player] = {}
	for id, m in Monsters:All(player) do
		-- Trades and expeditions never survive a rejoin; clear stale busy tags that the owning
		-- systems re-apply in their own PlayerAdded (expeditions/breeding keep theirs).
		trackGrowing(player, m, id)
	end
	local done = processGrowth(player, ctx:Now())
	if done > 0 then
		ctx.Bus:Publish("WelcomeItem", player, {
			kind = "evolve",
			text = if done == 1 then "1 monster grew up" else string.format("%d monsters grew up", done),
		})
	end
end

function Monsters.PlayerRemoving(player)
	growing[player] = nil
end

return Monsters
