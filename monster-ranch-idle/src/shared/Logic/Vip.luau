--[[
	Vip: pure rules for the VIP Rancher perks (Config.Monetization.VipCrate / VipChatTag).
	Shared by the Monetization system (claims), the Store (odds, ready state) and the client's
	ChatTags controller.

	Vip.Day(now) -> UTC day number (the same as the server's ctx:Day())
	Vip.CrateReady(owned, lastDay, today) -> boolean      -- one crate per UTC day, no stacking
	Vip.CrateOdds(crate) -> { { reward = { Reward }, pct } }   -- in table order
	Vip.RollCrate(crate, userId, day, paidRandomAllowed) -> { Reward }
	  Seeded by (userId, day), so a given day's crate is fixed. `paidRandomAllowed == false`
	  returns the crate's `fixed` gift (no chance involved). Always fresh tables.
	Vip.ChatPrefix(prefixText, isVip, tag) -> string      -- tag = Config.Monetization.VipChatTag
]]

local Rng = require(script.Parent.Rng)

local Vip = {}

function Vip.Day(now: number): number
	return math.floor(now / 86400)
end

function Vip.CrateReady(owned: boolean, lastDay: any, today: number): boolean
	return owned == true and (type(lastDay) ~= "number" or lastDay < today)
end

local function copy(rewards): { any }
	local out = {}
	for i, item in rewards do
		out[i] = table.clone(item)
	end
	return out
end

function Vip.CrateOdds(crate): { { reward: { any }, pct: number } }
	local total = 0
	for _, entry in crate.table do
		total += math.max(entry.weight or 0, 0)
	end
	local out = {}
	for _, entry in crate.table do
		local pct = if total > 0 then math.max(entry.weight or 0, 0) / total * 100 else 0
		table.insert(out, { reward = copy(entry.reward), pct = pct })
	end
	return out
end

function Vip.RollCrate(crate, userId: number, day: number, paidRandomAllowed: boolean): { any }
	if not paidRandomAllowed then
		return copy(crate.fixed)
	end
	local rng = Rng.new(Rng.seed("vipcrate", userId, day))
	local entry = rng:WeightedBy(crate.table, "weight")
	return copy(entry.reward)
end

function Vip.ChatPrefix(prefixText: string?, isVip: boolean, tag): string
	local prefix = prefixText or ""
	if not isVip then
		return prefix
	end
	local label = string.format('<font color="%s">%s</font>', tag.color, tag.text)
	return if prefix == "" then label else label .. " " .. prefix
end

return Vip
