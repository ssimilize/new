--[[
	TreasureMaps (update 3.13 · Wild things): map pieces, Treasure Maps and their guardians. Rules:
	Config/TreasureMaps and Logic/TreasureMaps. Reached from the Expeditions screen's "Maps" button
	(Screens/TreasureMaps); no world building.

	Save section (profile.TreasureMaps), version 1:
	  pieces                 -- loose map pieces (at most Cfg.PieceCap)
	  maps = { { id, region, stage, seed } }   -- held maps (at most Cfg.MaxMaps)
	  made                   -- maps ever made (the next map's id and its seed's counter)
	  rolls                  -- drop rolls ever (the drop seed's counter)
	  digs                   -- guardian fights ever (the fight seed's counter)
	  opened                 -- chests opened ever

	Actions:
	  TreasureMaps.Dig { map } -> { win, map, region, replay, rewards, maps }
	    Fights the map's guardian with the default Expeditions squad (every member free) through
	    Logic/TreasureMaps.Fight (Logic/BattleSim, Dojo techniques apply), seeded by (userId, map,
	    digs). A win opens the chest (Rewards source Cfg.Source), uses the map and publishes
	    TreasureOpened; a loss keeps the map (no cost, retry any time).

	Public API:
	  TreasureMaps:AddPieces(player, n) -> number    pieces held after joining full sets into maps
	                                                 (Rewards kind "map_piece")
	  TreasureMaps:Drop(player, source) -> { Reward }  a drop roll for "expedition" | "fishing" | "dig"
	                                                 | "bounty": {} before the unlock or on a miss,
	                                                 else { map_piece }. The host grants it with its
	                                                 own rewards (Expeditions claims and bounty
	                                                 payouts, Fishing catches, Dig Site finds).
	  TreasureMaps:Pieces(player) -> number
	  TreasureMaps:Maps(player) -> { map }

	Maps are made whenever pieces arrive, a stage is cleared (StageCleared) or the player joins,
	if there is room and an open region (open, unlocked, a stage cleared) to put the X in.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.TreasureMaps)

local TreasureMaps = {
	Name = "TreasureMaps",
	Dependencies = { "Progression", "Monsters", "Rewards", "Expeditions" },
}

TreasureMaps.Profile = {
	Version = 1,
	Default = function()
		return {
			pieces = 0,
			maps = {},
			made = 0,
			rolls = 0,
			digs = 0,
			opened = 0,
		}
	end,
}

local ctx
local Cfg -- Config.TreasureMaps
local Regions -- Config.Regions
local Progression, Monsters, Rewards, Expeditions

-- The regions an X can go in: open, unlocked and with a cleared stage (in region order).
local function openRegions(player)
	local open = {}
	for _, region in Regions.List do
		if Regions.IsOpen(region, ctx:Now()) and Progression:IsUnlocked(player, region.unlock) then
			local cleared = Expeditions:Cleared(player, region.id)
			if cleared >= 1 then
				table.insert(open, { region = region.id, cleared = cleared })
			end
		end
	end
	return open
end

-- Joins full sets of pieces into maps while there is room and somewhere to put the X.
local function combine(player, s)
	local made = 0
	while s.pieces >= Cfg.PiecesPerMap and #s.maps < Cfg.MaxMaps do
		local seed = Logic.MapSeed(player.UserId, s.made + 1)
		local x = Logic.Roll(openRegions(player), seed)
		if not x then
			break
		end
		s.made += 1
		s.pieces -= Cfg.PiecesPerMap
		table.insert(s.maps, { id = s.made, region = x.region, stage = x.stage, seed = seed })
		made += 1
	end
	s.pieces = math.clamp(s.pieces, 0, Cfg.PieceCap)
	if made > 0 then
		ctx:Dirty(player)
		ctx:Notify(player, "A Treasure Map is ready! Dig it up from the Expeditions screen", "info")
	end
end

-- Public API ---------------------------------------------------------------------------

function TreasureMaps:AddPieces(player, n: number): number
	local s = ctx:Section(player)
	if not s then
		return 0
	end
	-- Full sets become maps first; what is left waits, at most Cfg.PieceCap (combine clamps).
	s.pieces += math.clamp(math.floor(tonumber(n) or 0), 0, 1000)
	combine(player, s)
	ctx:Dirty(player)
	return s.pieces
end

function TreasureMaps:Drop(player, source: string)
	local s = ctx:Section(player)
	if not s or not Progression:IsUnlocked(player, Cfg.Unlock) then
		return {}
	end
	s.rolls += 1
	ctx:Dirty(player, "rolls")
	local n = Logic.Drops(source, Logic.DropSeed(player.UserId, source, s.rolls))
	if n <= 0 then
		return {}
	end
	return { { kind = "map_piece", amount = n } }
end

function TreasureMaps:Pieces(player): number
	local s = ctx:Section(player)
	return if s then s.pieces else 0
end

function TreasureMaps:Maps(player)
	local s = ctx:Section(player)
	return if s then s.maps else {}
end

-- Actions ----------------------------------------------------------------------------------

local function squadOf(player)
	local ids = Expeditions:GetSquad(player)
	if #ids == 0 then
		ctx:Fail("Pick a squad first")
	end
	local members = {}
	for _, id in ids do
		local m, why = Monsters:Available(player, id)
		if not m then
			ctx:Fail(why or "That squad can't go")
		end
		table.insert(members, m)
	end
	return members
end

local function dig(player, payload)
	Progression:Require(player, Cfg.Unlock)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	local index, map = nil, nil
	for i, m in s.maps do
		if m.id == payload.map then
			index, map = i, m
		end
	end
	if not map then
		ctx:Fail("That map is gone")
	end
	local members = squadOf(player)

	local seed = Logic.FightSeed(player.UserId, map.id, s.digs)
	s.digs += 1
	local replay = Logic.Fight(members, map, seed)

	local rewards = {}
	if replay.win then
		table.remove(s.maps, index)
		s.opened += 1
		rewards = Rewards:Grant(player, Logic.Chest(map), Cfg.Source, { silent = true })
		ctx.Bus:Publish("TreasureOpened", player, { region = map.region })
		ctx.Analytics.Custom(player, "treasure_opened", map.stage, { region = map.region })
		-- Waiting pieces may make a new map now that there is room.
		combine(player, s)
	end
	ctx:Dirty(player)
	return {
		win = replay.win,
		map = map.id,
		region = map.region,
		replay = replay,
		rewards = rewards,
		maps = #s.maps,
	}
end

-- Lifecycle ----------------------------------------------------------------------------

function TreasureMaps.Init(context)
	ctx = context
	Cfg = ctx.Config.TreasureMaps
	Regions = ctx.Config.Regions
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	Rewards = ctx:GetSystem("Rewards")
	Expeditions = ctx:GetSystem("Expeditions")

	ctx.Net:Handle("TreasureMaps.Dig", dig)

	-- A first clear may open the region waiting pieces need.
	ctx.Bus:Subscribe("StageCleared", function(player)
		local s = ctx:Section(player)
		if s and s.pieces >= Cfg.PiecesPerMap then
			combine(player, s)
		end
	end)
end

function TreasureMaps.PlayerAdded(player)
	local s = ctx:Section(player)
	if not s then
		return
	end
	-- Drops anything a damaged save left behind.
	for _, key in { "pieces", "made", "rolls", "digs", "opened" } do
		s[key] = math.max(0, math.floor(tonumber(s[key]) or 0))
	end
	local maps = {}
	for _, m in (if type(s.maps) == "table" then s.maps else {}) do
		if
			type(m) == "table"
			and Regions.ById[m.region]
			and type(m.stage) == "number"
			and m.stage >= 1
			and m.stage <= Regions.Stages(m.region)
			and type(m.seed) == "number"
			and type(m.id) == "number"
			and #maps < Cfg.MaxMaps
		then
			table.insert(maps, m)
		end
	end
	s.maps = maps
	combine(player, s)
	ctx:Dirty(player)
end

return TreasureMaps
