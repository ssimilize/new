--[[
	Logic/DigSite (update 3.11 · Seasons & secrets): pure rules of the Dig Site (Config/DigSite),
	used by Systems/DigSite (the authority) and the Dig Site screen (labels only: the client never
	sees a layout).

	  DigSite.Seed(userId, n, secret) -> number      the dig's seed: ("digsite", userId, dig number, secret)
	  DigSite.Layout(seed) -> { Find }               Find = { tile, kind, fossil?, piece?, amount?, id? }
	  DigSite.Distance(a, b) -> number               steps along rows and columns between two tiles
	  DigSite.Hint(finds, found, tile) -> number     distance from `tile` to the nearest find not yet
	                                                 dug up (found = { [tile]: true }); 0 = none left
	  DigSite.HintText(distance) -> string           "Hot!" / "Warm" / "Cool" / "Cold"
	  DigSite.Complete(pieces) -> boolean            a fossil's pieces table has every piece
	  DigSite.Fossils(pieces) -> number              fossils complete (profile.DigSite.pieces)
	  DigSite.PieceCount(pieces) -> number           pieces owned across every fossil

	Tiles are numbered 1..Grid² row by row (tile = (row - 1) × Grid + col).
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)

local Cfg = Config.DigSite

local DigSite = {}

function DigSite.Seed(userId: number, n: number, secret: number): number
	return Rng.seed("digsite", userId, n, secret)
end

local function weights(list): { number }
	local out = {}
	for i, entry in list do
		out[i] = entry.weight
	end
	return out
end

function DigSite.Layout(seed: number): { any }
	local rng = Rng.new(seed)
	local count = if rng:Chance(Cfg.TwoFindChance) then 2 else 1
	local used, finds = {}, {}
	local kindWeights, relicWeights = weights(Cfg.Kinds), weights(Cfg.Relics)
	for _ = 1, count do
		local tile = rng:Int(1, Cfg.Tiles)
		while used[tile] do
			tile = tile % Cfg.Tiles + 1
		end
		used[tile] = true
		local kind = Cfg.Kinds[rng:Weighted(kindWeights)].id
		local find: { [string]: any } = { tile = tile, kind = kind }
		if kind == "piece" then
			find.fossil = Cfg.Fossils[rng:Int(1, #Cfg.Fossils)].id
			find.piece = Cfg.Pieces[rng:Int(1, #Cfg.Pieces)].id
		elseif kind == "amber" then
			find.amount = rng:Int(Cfg.Amber[1], Cfg.Amber[2])
		elseif kind == "relic" then
			find.id = Cfg.Relics[rng:Weighted(relicWeights)].id
		else
			find.id = Cfg.Egg
		end
		table.insert(finds, find)
	end
	return finds
end

function DigSite.Distance(a: number, b: number): number
	local g = Cfg.Grid
	local ar, ac = (a - 1) // g, (a - 1) % g
	local br, bc = (b - 1) // g, (b - 1) % g
	return math.abs(ar - br) + math.abs(ac - bc)
end

function DigSite.Hint(finds: { any }, found: { [number]: boolean }, tile: number): number
	local best = 0
	for _, f in finds do
		if not found[f.tile] then
			local d = DigSite.Distance(tile, f.tile)
			if best == 0 or d < best then
				best = d
			end
		end
	end
	return best
end

function DigSite.HintText(distance: number): string
	if distance <= 0 then
		return "Nothing left"
	elseif distance == 1 then
		return "Hot!"
	elseif distance == 2 then
		return "Warm"
	elseif distance == 3 then
		return "Cool"
	end
	return "Cold"
end

function DigSite.Complete(pieces): boolean
	if type(pieces) ~= "table" then
		return false
	end
	for _, p in Cfg.Pieces do
		if not pieces[p.id] then
			return false
		end
	end
	return true
end

function DigSite.Fossils(all): number
	local n = 0
	for _, f in Cfg.Fossils do
		if type(all) == "table" and DigSite.Complete(all[f.id]) then
			n += 1
		end
	end
	return n
end

function DigSite.PieceCount(all): number
	local n = 0
	for _, f in Cfg.Fossils do
		local have = type(all) == "table" and all[f.id]
		if type(have) == "table" then
			for _, p in Cfg.Pieces do
				if have[p.id] then
					n += 1
				end
			end
		end
	end
	return n
end

return DigSite
