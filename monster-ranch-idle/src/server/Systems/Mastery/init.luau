--[[
	Mastery (3.3): the endgame layer. Design and numbers in Config/Mastery's header; pure rules in
	Logic/Mastery.

	  Ranch Mastery   Ranch XP earned at the level cap (Progression's "RanchXPOverflow") fills an
	                  endless track; each level pays Star Shards (HallOfFame:AddStarShards).
	  Line Mastery    points per species line from hatching, levelling, evolving, winning fights
	                  (StageCleared / ArenaBattle / RaidFinished squads) and retiring; tiers give
	                  badges and, at Gold and Mythic, an aura (Monsters:Appearance decorator).
	  Constellation   Star Shards buy trait rerolls, prestige cosmetics and small capped perks.
	  Mythic Ladder   season points from mastery gained while a Ranch Pass season runs; tier
	                  rewards are granted once, the moment a tier is reached. Weekly points feed
	                  the "mastery" leaderboard.

	Save section (profile.Mastery, version 1):
	  level, xp, total                    Ranch Mastery level, xp toward the next, all-time xp
	  lines    = { [lineId] = points }
	  rerolls  = { [monsterId] = n }      rerolls done on that monster (sets the next price)
	  owned    = { [itemId] = true }      cosmetics and titles
	  perks    = { [perkId] = level }
	  equipped = { aura, flourish, plinth, title }   item id or false
	  ladder   = { season, xp, line, tier }          this season's gains and the tier granted
	  week     = { id, xp, line }                    this leaderboard week's gains

	Global (global.Mastery): here = { ["u" .. userId] = { flourish, title, plinth } } for nameplates
	and statue plinths of players in this server.

	Actions: Mastery.Reroll { id, slot }, Mastery.Buy { item }, Mastery.Equip { kind, item }.
	Publishes MasteryGained, PlotChanged (a monster's aura changed), RateModifiersChanged (perks).

	Public API:
	  Mastery:AddXP(player, amount, reason)              Ranch Mastery XP (normally the overflow)
	  Mastery:AddLinePoints(player, lineId, points, reason)
	  Mastery:RanchLevel(player) -> number
	  Mastery:LineTier(player, lineId) -> 0..#Tiers
	  Mastery:WeekPoints(player) -> number               ladder points this leaderboard week
	  Mastery:PerkEffect(player, effectKey) -> number
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local Logic = require(Shared.Logic.Mastery)

local Mastery = {
	Name = "Mastery",
	Dependencies = { "Monsters", "Progression", "HallOfFame" },
	OptionalDependencies = { "Ranch", "Eggs", "Expeditions" },
}

local function emptyEquipped()
	return { aura = false, flourish = false, plinth = false, title = false }
end

-- Fills anything missing (a section saved by an older build of this version, or a bad write).
local function normalize(s)
	s.level = tonumber(s.level) or 0
	s.xp = tonumber(s.xp) or 0
	s.total = tonumber(s.total) or 0
	for _, key in { "lines", "rerolls", "owned", "perks" } do
		if type(s[key]) ~= "table" then
			s[key] = {}
		end
	end
	if type(s.equipped) ~= "table" then
		s.equipped = emptyEquipped()
	end
	for key in emptyEquipped() do
		if s.equipped[key] == nil then
			s.equipped[key] = false
		end
	end
	if type(s.ladder) ~= "table" then
		s.ladder = { season = 0, xp = 0, line = 0, tier = 0 }
	end
	if type(s.week) ~= "table" then
		s.week = { id = 0, xp = 0, line = 0 }
	end
	return s
end

Mastery.Profile = {
	Version = 1,
	Default = function()
		return normalize({})
	end,
	Migrate = function(section, _fromVersion)
		return normalize(section)
	end,
}

local ctx
local Config -- Config.Mastery
local Monsters, HallOfFame

local function mustSection(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

local function lineName(lineId: string): string
	local def = ctx.Config.Species.ById[lineId]
	return if def then def.forms[1].name else lineId
end

-- Global ---------------------------------------------------------------------------------

local function publishHere(player, s)
	local global = ctx:Global()
	global.here = global.here or {}
	local key = "u" .. tostring(player.UserId)
	global.here[key] = if s then { flourish = s.equipped.flourish, title = s.equipped.title, plinth = s.equipped.plinth } else nil
	ctx:DirtyGlobal("here", key)
end

-- Ladder and week ------------------------------------------------------------------------

local function grantItem(player, s, itemId: string?)
	if itemId and ctx.Config.Mastery.ItemById[itemId] and not s.owned[itemId] then
		s.owned[itemId] = true
		ctx:Dirty(player, "owned", itemId)
	end
end

local function syncSeason(player, s)
	local season = Logic.SeasonAt(ctx:Now())
	if s.ladder.season ~= season then
		s.ladder = { season = season, xp = 0, line = 0, tier = 0 }
		ctx:Dirty(player, "ladder")
	end
	local week = ctx.Config.Leaderboards.Week(ctx:Now())
	if s.week.id ~= week then
		s.week = { id = week, xp = 0, line = 0 }
		ctx:Dirty(player, "week")
	end
	return season
end

local function countLadder(player, s, xp: number, line: number)
	local season = syncSeason(player, s)
	s.week.xp += xp
	s.week.line += line
	ctx:Dirty(player, "week")
	if season == 0 then
		return
	end
	s.ladder.xp += xp
	s.ladder.line += line
	local tier = Logic.LadderTier(Logic.LadderPoints(s.ladder.xp, s.ladder.line))
	while s.ladder.tier < tier do
		s.ladder.tier += 1
		local row = Config.Ladder[s.ladder.tier]
		if row.shards then
			HallOfFame:AddStarShards(player, row.shards, "ladder")
		end
		grantItem(player, s, row.item)
		grantItem(player, s, row.item2)
		ctx:Notify(player, string.format("Mythic Ladder: %s tier reached!", row.name), "reward")
		ctx.Analytics.Custom(player, "LadderTier", s.ladder.tier, { season = tostring(season) })
	end
	ctx:Dirty(player, "ladder")
end

-- Gains ----------------------------------------------------------------------------------

function Mastery:AddXP(player, amount: number, reason: string?)
	local s = ctx:Section(player)
	if not s or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	amount = math.floor(amount)
	if amount <= 0 then
		return
	end
	local level, xp, gained = Logic.AddRanchXP(s.level, s.xp, amount)
	local from = s.level
	s.level, s.xp = level, xp
	s.total += amount
	ctx:Dirty(player, "level")
	ctx:Dirty(player, "xp")
	ctx:Dirty(player, "total")
	if gained > 0 then
		-- One toast and one grant however many levels a big XP drop crosses.
		local shards = 0
		for l = from + 1, from + gained do
			shards += Config.ShardsPerLevel + (if l % Config.MilestoneEvery == 0 then Config.MilestoneShards else 0)
		end
		HallOfFame:AddStarShards(player, shards, "mastery")
		ctx:Notify(player, string.format("Ranch Mastery %d! +%d Star Shards", level, shards), "reward")
		ctx.Analytics.Custom(player, "RanchMastery", level, { reason = reason or "unknown" })
	end
	countLadder(player, s, amount, 0)
	ctx.Bus:Publish("MasteryGained", player, { xp = amount })
end

function Mastery:AddLinePoints(player, lineId: string, points: number, reason: string?)
	local s = ctx:Section(player)
	if not s or type(lineId) ~= "string" or not ctx.Config.Species.ById[lineId] then
		return
	end
	if type(points) ~= "number" or points ~= points or points <= 0 then
		return
	end
	points = math.floor(points)
	local before = Logic.TierIndex(s.lines[lineId] or 0)
	s.lines[lineId] = (s.lines[lineId] or 0) + points
	ctx:Dirty(player, "lines", lineId)
	local after = Logic.TierIndex(s.lines[lineId])
	if after > before then
		local tier = Config.Tiers[after]
		ctx:Notify(player, string.format("%s line reached %s Mastery!", lineName(lineId), tier.name), "reward")
		ctx.Analytics.Custom(player, "LineMasteryTier", after, { line = lineId, reason = reason or "unknown" })
		ctx.Bus:Publish("PlotChanged", player, {}) -- a new aura on that line's pen monsters
	end
	countLadder(player, s, 0, points)
	ctx.Bus:Publish("MasteryGained", player, { xp = 0, line = lineId, points = points })
end

local function lineOf(player, id): string?
	local m = type(id) == "string" and Monsters:Get(player, id)
	return m and m.line or nil
end

local function fightWon(player, squad)
	local seen = {}
	for _, id in if type(squad) == "table" then squad else {} do
		local line = lineOf(player, id)
		if line and not seen[line] then
			seen[line] = true
			Mastery:AddLinePoints(player, line, Config.LinePoints.fightWin, "fight")
		end
	end
end

-- Queries --------------------------------------------------------------------------------

function Mastery:RanchLevel(player): number
	local s = ctx:Section(player)
	return s and s.level or 0
end

function Mastery:LineTier(player, lineId: string): number
	local s = ctx:Section(player)
	return if s then Logic.TierIndex(s.lines[lineId] or 0) else 0
end

function Mastery:WeekPoints(player): number
	local s = ctx:Section(player)
	if not s then
		return 0
	end
	if s.week.id ~= ctx.Config.Leaderboards.Week(ctx:Now()) then
		return 0
	end
	return Logic.LadderPoints(s.week.xp, s.week.line)
end

function Mastery:PerkEffect(player, effectKey: string): number
	local s = ctx:Section(player)
	return if s then Logic.PerkEffect(s.perks, effectKey) else 0
end

-- Actions --------------------------------------------------------------------------------

local function reroll(player, payload)
	local s = mustSection(player)
	local m = Monsters:Get(player, payload.id)
	if not m then
		ctx:Fail("That monster doesn't exist")
	end
	if m.busy then
		ctx:Fail(string.format("%s is busy", Formulas.DisplayName(m)))
	end
	if type(m.traits) ~= "table" or m.traits[payload.slot] == nil then
		ctx:Fail("That trait slot is empty")
	end
	local done = s.rerolls[payload.id] or 0
	local cost = Logic.RerollCost(done)
	local trait = Logic.RerollTrait(m, payload.slot, Logic.RerollSeed(player.UserId, m, done))
	if not trait then
		ctx:Fail("No other trait can roll in that slot")
	end
	if not HallOfFame:SpendStarShards(player, cost, "reroll") then
		ctx:Fail("Not enough Star Shards")
	end
	m.traits[payload.slot] = trait
	Monsters:Changed(player, payload.id, { "traits" })
	s.rerolls[payload.id] = done + 1
	ctx:Dirty(player, "rerolls", payload.id)
	ctx.Bus:Publish("RateModifiersChanged", player, {})
	ctx.Analytics.Custom(player, "TraitReroll", done + 1, { trait = tostring(trait) })
	return { trait = trait, cost = cost, rerolls = done + 1 }
end

local function buy(player, payload)
	local s = mustSection(player)
	local def = Config.ShopById[payload.item]
	if not def then
		ctx:Fail("That item doesn't exist")
	end
	if def.kind == "perk" then
		local level = s.perks[def.id] or 0
		if level >= def.maxLevel then
			ctx:Fail(string.format("%s is already maxed", def.name))
		end
		if not HallOfFame:SpendStarShards(player, def.costs[level + 1], "perk") then
			ctx:Fail("Not enough Star Shards")
		end
		s.perks[def.id] = level + 1
		ctx:Dirty(player, "perks", def.id)
		ctx.Bus:Publish("RateModifiersChanged", player, {})
		return { item = def.id, level = level + 1 }
	end
	if s.owned[def.id] then
		ctx:Fail("You already own that")
	end
	if not HallOfFame:SpendStarShards(player, def.cost, "cosmetic") then
		ctx:Fail("Not enough Star Shards")
	end
	s.owned[def.id] = true
	ctx:Dirty(player, "owned", def.id)
	-- A new cosmetic goes straight on: that is what the player bought it for.
	s.equipped[def.kind] = def.id
	ctx:Dirty(player, "equipped")
	publishHere(player, s)
	if def.kind == "aura" then
		ctx.Bus:Publish("PlotChanged", player, {})
	end
	return { item = def.id, level = 1 }
end

local function equip(player, payload)
	local s = mustSection(player)
	local kind = payload.kind
	if payload.item == "" then
		s.equipped[kind] = false
	else
		local def = Config.ItemById[payload.item]
		if not def or def.kind ~= kind then
			ctx:Fail("That item doesn't go there")
		end
		if not s.owned[def.id] then
			ctx:Fail("You don't own that yet")
		end
		s.equipped[kind] = def.id
	end
	ctx:Dirty(player, "equipped")
	publishHere(player, s)
	if kind == "aura" then
		ctx.Bus:Publish("PlotChanged", player, {})
	end
	return nil
end

-- Providers ------------------------------------------------------------------------------

-- The render-only aura key (Config/Vfx Mastery) a monster of `lineId` wears, or nil.
local function auraFor(s, lineId: string): string?
	local tier = Logic.TierIndex(s.lines[lineId] or 0)
	if tier <= 0 then
		return nil
	end
	local equipped = s.equipped.aura and Config.ItemById[s.equipped.aura]
	if equipped and equipped.vfx then
		return equipped.vfx
	end
	return Config.Tiers[tier].aura
end

local function registerProviders()
	Monsters:RegisterAppearanceDecorator("mastery", function(player, record, appearance)
		local s = ctx:Section(player)
		local aura = s and auraFor(s, record.line)
		if aura then
			appearance.aura = aura
		end
	end)
	local Eggs = ctx:GetSystem("Eggs")
	if Eggs then
		Eggs:RegisterSpeedProvider("mastery", function(player)
			return Mastery:PerkEffect(player, "hatchSpeed")
		end)
	end
	local Ranch = ctx:GetSystem("Ranch")
	if Ranch then
		Ranch:RegisterJarBonus("mastery", function(player)
			return Mastery:PerkEffect(player, "jarCapSeconds")
		end)
	end
	local Expeditions = ctx:GetSystem("Expeditions")
	if Expeditions then
		Expeditions:RegisterLootModifier("mastery", function(player)
			return Mastery:PerkEffect(player, "lootPct")
		end)
	end
end

-- Lifecycle ------------------------------------------------------------------------------

function Mastery.Init(context)
	ctx = context
	Config = ctx.Config.Mastery
	Monsters = ctx:GetSystem("Monsters")
	HallOfFame = ctx:GetSystem("HallOfFame")
	local points = Config.LinePoints

	ctx.Net:Handle("Mastery.Reroll", reroll)
	ctx.Net:Handle("Mastery.Buy", buy)
	ctx.Net:Handle("Mastery.Equip", equip)

	ctx.Bus:Subscribe("RanchXPOverflow", function(player, detail)
		Mastery:AddXP(player, detail.amount or 0, detail.reason)
	end)
	ctx.Bus:Subscribe("EggHatched", function(player, detail)
		local line = lineOf(player, detail.id)
		if line then
			Mastery:AddLinePoints(player, line, points.hatchBase + points.hatchPerRarity * (tonumber(detail.rarity) or 1), "hatch")
		end
	end)
	ctx.Bus:Subscribe("MonsterLeveled", function(player, detail)
		local line = lineOf(player, detail.id)
		if line then
			Mastery:AddLinePoints(player, line, points.levelUp, "levelup")
		end
	end)
	ctx.Bus:Subscribe("MonsterEvolved", function(player, detail)
		local line = lineOf(player, detail.id)
		if line then
			Mastery:AddLinePoints(player, line, points.evolve, "evolve")
		end
	end)
	ctx.Bus:Subscribe("MonsterRemoved", function(player, detail)
		local s = ctx:Section(player)
		if s and s.rerolls[detail.id] then
			s.rerolls[detail.id] = nil
			ctx:Dirty(player, "rerolls", detail.id)
		end
		if detail.reason == "retire" and detail.line then
			local reward = points.retireBase + points.retirePerRarity * (tonumber(detail.rarity) or 1)
			Mastery:AddLinePoints(player, detail.line, reward, "retire")
		end
	end)
	ctx.Bus:Subscribe("StageCleared", function(player, detail)
		fightWon(player, detail.squad)
	end)
	ctx.Bus:Subscribe("ArenaBattle", function(player, detail)
		if detail.won then
			fightWon(player, detail.squad)
		end
	end)
	ctx.Bus:Subscribe("RaidFinished", function(player, detail)
		if detail.win then
			fightWon(player, detail.squad)
		end
	end)
end

function Mastery.Start()
	registerProviders()
end

function Mastery.PlayerAdded(player, _info)
	local s = ctx:Section(player)
	if not s then
		return
	end
	normalize(s)
	syncSeason(player, s)
	publishHere(player, s)
end

function Mastery.PlayerRemoving(player)
	publishHere(player, nil)
end

return Mastery
