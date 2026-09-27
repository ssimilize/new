--[[
	Exhibits (update 3.12 · Honey & stars): Museum Exhibits in the Curator wing beside the Codex
	Museum. Rules: Config/Exhibits and Logic/Exhibits. Opened from the Curator desk's "Exhibits"
	prompt (Controllers/CuratorWing) and the Codex screen's Exhibits button.

	Save section (profile.Exhibits, version 1):
	  filled = { [setId]: { [itemId]: true } }   exhibits on display
	  paid   = { [setId]: step }                 reward steps claimed (0..3, in order)

	Filling:
	  fossils  by itself: FossilFound with complete = true; back-filled on join (DigSite:Completed)
	  stars    by itself: StarCharted; back-filled on join (Observatory:Charted)
	  aquarium Exhibits.Donate: one fish of that kind is used up (Fishing:SpendFish(player, 1, id))
	  relics   Exhibits.Donate: one copy from decor storage (Shop:TakeDecor); placed copies never
	  honey    Exhibits.Donate: one jar (Apiary:SpendHoney(player, kind, 1))
	Auto-fills happen before the unlock too (the record is kept); donating and claiming need
	Ranch Level 18. Back-filling on join does not publish (it is not a new exhibit this week).

	Actions:
	  Exhibits.Donate { set, item } -> { set, item }
	    Fails: locked, unknown set or item, a set that fills itself (its hint), already on display,
	    nothing to donate, every copy placed.
	  Exhibits.Claim { set } -> { set, step, rewards, title? }
	    Pays the next reward step the set has reached (Logic/Exhibits.Claimable): gems and stardust
	    through Rewards (source "exhibits"), and on the last step the set's title (Mastery:GrantItem;
	    re-granted on join if Mastery was missing).

	Publishes ExhibitDonated (player, { set, item }) for each new exhibit, donated or filled by
	itself (the weekly goal exhibits_3). Registers Tourists:RegisterAppealBonus("exhibits") in Start.

	Public API:
	  Exhibits:Filled(player) -> { [setId]: { [itemId]: true } }
	  Exhibits:Appeal(player) -> number   0 before the unlock
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Exhibits)

local Exhibits = {
	Name = "Exhibits",
	Dependencies = { "Progression", "Rewards" },
	OptionalDependencies = { "Shop", "Decor", "Fishing", "DigSite", "Apiary", "Observatory", "Tourists", "Mastery" },
}

local function normalize(s)
	if type(s) ~= "table" then
		s = {}
	end
	local filled, paid = {}, {}
	if type(s.filled) == "table" then
		for setId, items in s.filled do
			if type(setId) == "string" and type(items) == "table" then
				local keep = {}
				for itemId, yes in items do
					if type(itemId) == "string" and yes == true then
						keep[itemId] = true
					end
				end
				filled[setId] = keep
			end
		end
	end
	if type(s.paid) == "table" then
		for setId, step in s.paid do
			if type(setId) == "string" and type(step) == "number" and step == step then
				paid[setId] = math.clamp(math.floor(step), 0, 3)
			end
		end
	end
	for key in s do
		s[key] = nil
	end
	s.filled, s.paid = filled, paid
	return s
end

Exhibits.Profile = {
	Version = 1,
	Default = function()
		return { filled = {}, paid = {} }
	end,
	Migrate = function(section, _fromVersion)
		return normalize(section)
	end,
}

local ctx
local Config, Cfg
local Progression, Rewards

local function mustSection(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

local function itemOf(setId: string, itemId: string)
	for _, item in Logic.Items(Config, setId) or {} do
		if item.id == itemId then
			return item
		end
	end
	return nil
end

-- Puts one exhibit on display; true when it is new.
local function fill(player, s, setId: string, itemId: string, publish: boolean): boolean
	if not itemOf(setId, itemId) then
		return false
	end
	local mine = s.filled[setId]
	if not mine then
		mine = {}
		s.filled[setId] = mine
	end
	if mine[itemId] then
		return false
	end
	mine[itemId] = true
	ctx:Dirty(player, "filled", setId)
	if publish then
		ctx.Bus:Publish("ExhibitDonated", player, { set = setId, item = itemId })
	end
	return true
end

-- Fills the self-filling sets from the systems that own them (join, and a missed event).
local function backfill(player, s)
	local DigSite = ctx:GetSystem("DigSite")
	if DigSite and DigSite.Completed then
		for fossilId in DigSite:Completed(player) do
			fill(player, s, "fossils", fossilId, false)
		end
	end
	local Observatory = ctx:GetSystem("Observatory")
	if Observatory and Observatory.Charted then
		local ok, charted = pcall(Observatory.Charted, Observatory, player)
		if ok and type(charted) == "table" then
			for chartId, yes in charted do
				if yes and type(chartId) == "string" then
					fill(player, s, "stars", chartId, false)
				end
			end
		end
	end
end

local function grantTitles(player, s)
	local Mastery = ctx:GetSystem("Mastery")
	if not Mastery then
		return
	end
	for setId, step in s.paid do
		local set = Cfg.ById[setId]
		if set and set.titleItem and step >= #Cfg.Steps then
			Mastery:GrantItem(player, set.titleItem, true)
		end
	end
end

-- Actions ------------------------------------------------------------------------------

local function spend(player, setId: string, itemId: string)
	if setId == "aquarium" then
		local Fishing = ctx:GetSystem("Fishing")
		if not (Fishing and Fishing:Have(player, itemId) > 0 and Fishing:SpendFish(player, 1, itemId)) then
			ctx:Fail("You don't have one to donate")
		end
	elseif setId == "relics" then
		local Shop = ctx:GetSystem("Shop")
		if Shop and Shop:DecorCount(player, itemId) > 0 then
			if not Shop:TakeDecor(player, itemId) then
				ctx:Fail("You don't have one to donate")
			end
			return
		end
		local Decor = ctx:GetSystem("Decor")
		if Decor and Decor:Placed(player, itemId) > 0 then
			ctx:Fail("Every copy is placed on your ranch. Put one back in storage first")
		end
		ctx:Fail("You don't have one to donate")
	elseif setId == "honey" then
		local Apiary = ctx:GetSystem("Apiary")
		if not (Apiary and Apiary:SpendHoney(player, itemId, 1)) then
			ctx:Fail("You don't have one to donate")
		end
	else
		ctx:Fail("That exhibit doesn't exist")
	end
end

local function donate(player, payload)
	local s = mustSection(player)
	Progression:Require(player, Cfg.Unlock)
	local set = Cfg.ById[payload.set]
	if not set or not itemOf(set.id, payload.item) then
		ctx:Fail("That exhibit doesn't exist")
	end
	if set.fill ~= "donate" then
		ctx:Fail(set.hint or "That exhibit fills itself")
	end
	if s.filled[set.id] and s.filled[set.id][payload.item] then
		ctx:Fail("Already on display")
	end
	spend(player, set.id, payload.item)
	fill(player, s, set.id, payload.item, true)
	ctx:RequestSave(player)
	return { set = set.id, item = payload.item }
end

local function claim(player, payload)
	local s = mustSection(player)
	Progression:Require(player, Cfg.Unlock)
	local set = Cfg.ById[payload.set]
	if not set or not Logic.Items(Config, set.id) then
		ctx:Fail("That exhibit doesn't exist")
	end
	local done = s.paid[set.id] or 0
	if done >= #Cfg.Steps then
		ctx:Fail("All rewards claimed")
	end
	local step = Logic.Claimable(Config, set.id, s.filled, s.paid)
	if not step then
		local have, total = Logic.Count(Config, set.id, s.filled)
		ctx:Fail(string.format("Fill %d more exhibits first", Logic.Need(Cfg.Steps, total, done + 1) - have))
	end
	s.paid[set.id] = step
	ctx:Dirty(player, "paid", set.id)
	local _, total = Logic.Count(Config, set.id, s.filled)
	local gems, dust = Logic.Reward(Config, total, step)
	local items = {}
	if gems > 0 then
		table.insert(items, { kind = "gems", amount = gems })
	end
	if dust > 0 then
		table.insert(items, { kind = "stardust", amount = dust })
	end
	local granted = if #items > 0 then Rewards:Grant(player, items, Cfg.Source) else {}
	local title = nil
	if step >= #Cfg.Steps and set.titleItem then
		title = set.titleItem
		grantTitles(player, s)
	end
	ctx:RequestSave(player)
	return { set = set.id, step = step, rewards = granted, title = title }
end

-- Public API ---------------------------------------------------------------------------

function Exhibits:Filled(player)
	local s = ctx:Section(player)
	return if s then s.filled else {}
end

function Exhibits:Appeal(player): number
	local s = ctx:Section(player)
	if not s or not Progression:IsUnlocked(player, Cfg.Unlock) then
		return 0
	end
	return Logic.Appeal(Config, s.filled)
end

-- Lifecycle ----------------------------------------------------------------------------

function Exhibits.Init(context)
	ctx = context
	Config = ctx.Config
	Cfg = Config.Exhibits
	Progression = ctx:GetSystem("Progression")
	Rewards = ctx:GetSystem("Rewards")

	ctx.Net:Handle("Exhibits.Donate", donate)
	ctx.Net:Handle("Exhibits.Claim", claim)

	ctx.Bus:Subscribe("FossilFound", function(player, detail)
		local s = ctx:Section(player)
		if s and type(detail) == "table" and detail.complete == true and type(detail.fossil) == "string" then
			fill(player, s, "fossils", detail.fossil, true)
		end
	end)
	ctx.Bus:Subscribe("StarCharted", function(player, detail)
		local s = ctx:Section(player)
		if s and type(detail) == "table" and type(detail.chart) == "string" then
			fill(player, s, "stars", detail.chart, true)
		end
	end)
end

function Exhibits.Start()
	local Tourists = ctx:GetSystem("Tourists")
	if Tourists and Tourists.RegisterAppealBonus then
		Tourists:RegisterAppealBonus("exhibits", function(player)
			return Exhibits:Appeal(player)
		end)
	end
end

function Exhibits.PlayerAdded(player, _info)
	local s = ctx:Section(player)
	if not s then
		return
	end
	normalize(s)
	backfill(player, s)
	grantTitles(player, s)
	ctx:Dirty(player)
end

return Exhibits
