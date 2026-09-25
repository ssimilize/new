--[[
	Rewards (S1): grants mixed reward lists in one call and tells the client.

	Reward item: { kind, id?, amount, rarity?, seconds? }
	  coins/gems/stardust/friendship/treats/ribbons → Currency
	  coins with `seconds`                    → that many seconds of ranch income (needs Ranch)
	  food (id = flavor or "random")          → Currency food
	  token (id = eventId, default active)    → Currency token
	  xp                                      → Progression
	  egg (id = egg type)                     → Eggs
	  decor (id = decor id)                   → Shop
	  monster (id = line id, rarity)          → Monsters
	  accessory (id = accessory id)           → Accessories (1.5)

	Public API:
	  Rewards:Grant(player, items, source, options?) -> resolvedItems
	    options.silent = true  → no "Rewards.Granted" event (caller shows its own UI)
	    options.multiplier = n → multiplies every numeric amount (e.g. ×2 ad reward)
]]

local Rewards = {
	Name = "Rewards",
	Dependencies = { "Currency", "Progression" },
	OptionalDependencies = { "Eggs", "Shop", "Monsters", "Ranch", "Accessories" },
}

local ctx
local Currency, Progression

local SIMPLE = { coins = true, gems = true, stardust = true, friendship = true, treats = true, ribbons = true }

function Rewards.Init(context)
	ctx = context
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
end

local function resolve(player, item, multiplier: number)
	local out = table.clone(item)
	local amount = (item.amount or 0) * multiplier
	if item.kind == "coins" and item.seconds then
		local Ranch = ctx:GetSystem("Ranch")
		local perSecond = if Ranch then Ranch:IncomePerSecond(player) else 1
		amount = math.max(100, perSecond * item.seconds) * multiplier
		out.seconds = nil
	end
	if item.kind == "food" and (item.id == nil or item.id == "random") then
		out.id = ctx.Rng:Pick(ctx.Config.Food.Ids)
	end
	if item.kind == "token" and item.id == nil then
		out.id = ctx.Config.Events.ActiveId(ctx:Now())
	end
	out.amount = math.floor(amount)
	return out
end

function Rewards:Grant(player, items, source: string, options: { silent: boolean?, multiplier: number? }?)
	local opts = options or {}
	local multiplier = opts.multiplier or 1
	local granted = {}
	for _, raw in items or {} do
		local item = resolve(player, raw, multiplier)
		local ok = true
		if SIMPLE[item.kind] then
			Currency:Add(player, item.kind, item.amount, source)
		elseif item.kind == "food" then
			Currency:Add(player, "food." .. item.id, item.amount, source)
		elseif item.kind == "token" then
			if item.id then
				Currency:Add(player, "token." .. item.id, item.amount, source)
			else
				ok = false
			end
		elseif item.kind == "xp" then
			Progression:AddXP(player, item.amount, source)
		elseif item.kind == "egg" then
			local Eggs = ctx:GetSystem("Eggs")
			if Eggs then
				Eggs:Add(player, item.id, source, item.amount)
			else
				ok = false
			end
		elseif item.kind == "decor" then
			local Shop = ctx:GetSystem("Shop")
			if Shop then
				Shop:AddDecor(player, item.id, item.amount)
			else
				ok = false
			end
		elseif item.kind == "accessory" then
			local Accessories = ctx:GetSystem("Accessories")
			if Accessories and ctx.Config.Accessories.ById[item.id] then
				Accessories:Add(player, item.id, item.amount)
			else
				ok = false
			end
		elseif item.kind == "monster" then
			local Monsters = ctx:GetSystem("Monsters")
			if Monsters then
				for _ = 1, math.max(1, item.amount) do
					Monsters:Create(player, { line = item.id, rarity = item.rarity or 1 }, "reward", true)
				end
			else
				ok = false
			end
		else
			warn("[Rewards] unknown reward kind " .. tostring(item.kind))
			ok = false
		end
		if ok and item.amount > 0 then
			table.insert(granted, item)
		elseif not ok then
			warn(string.format("[Rewards] could not grant %s (%s): system not plugged in", tostring(item.kind), source))
		end
	end
	if not opts.silent and #granted > 0 then
		ctx.Net:Fire(player, "Rewards.Granted", { source = source, items = granted })
	end
	return granted
end

return Rewards
