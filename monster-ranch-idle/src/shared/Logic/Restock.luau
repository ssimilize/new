--[[
	Restock: the global egg-shop clock. Pure and deterministic, so every server (and the
	client's preview) computes the same stock for the same restock window without talking
	to each other.

	Restock.Window(now) -> number                  -- floor(now / Config.Eggs.RestockSeconds)
	Restock.EndsAt(window) -> unix seconds         -- when that window's stock is replaced
	Restock.OnSale(eggDef, activeEvent?) -> bool   -- sold in the shop right now (ignores unlocks)
	Restock.EggStock(window, eggDef) -> number     -- -1 unlimited, 0 not in this restock, else n
	Restock.Roll(window, activeEvent?) -> { [eggType] = n }   -- only eggs on sale now

	Stock is a per-player allowance: every player on every server may buy up to `n` of an
	egg during the window (the Shop system tracks what each player bought).
	Each egg is seeded from (window, eggId) on its own, so adding an egg to Config never
	changes the stock of the others.
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)

local Eggs = Config.Eggs

local Restock = {}

Restock.Unlimited = -1

function Restock.Window(now: number): number
	return math.floor(now / Eggs.RestockSeconds)
end

function Restock.EndsAt(window: number): number
	return (window + 1) * Eggs.RestockSeconds
end

function Restock.OnSale(egg, activeEvent: string?): boolean
	if egg.price == nil or egg.stock == nil then
		return false
	end
	if egg.event ~= nil and egg.event ~= activeEvent then
		return false
	end
	return true
end

function Restock.EggStock(window: number, egg): number
	local stock = egg.stock
	if not stock then
		return 0
	end
	if stock.unlimited then
		return Restock.Unlimited
	end
	local rng = Rng.new(Rng.seed("restock", window, egg.id))
	if not rng:Chance(stock.appearChance or 1) then
		return 0
	end
	return rng:Int(stock.min or 1, stock.max or stock.min or 1)
end

function Restock.Roll(window: number, activeEvent: string?): { [string]: number }
	local out = {}
	for _, egg in Eggs.List do
		if Restock.OnSale(egg, activeEvent) then
			out[egg.id] = Restock.EggStock(window, egg)
		end
	end
	return out
end

return Restock
