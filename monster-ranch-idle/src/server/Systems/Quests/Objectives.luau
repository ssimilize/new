--[[
	Quests/Objectives: pure rules shared by the tutorial, dailies and achievements.

	An objective is { topic, filter?, target? } (Config/Quests.luau). A bus topic's detail
	table advances it when every filter key matches:
	  minRarity = n   detail.rarity >= n
	  any other key   detail[key] == value (exact), e.g. { stage = 2 }, { hybrid = true }

	No Roblox APIs: required by the Quests system and unit-tested in Lune.
]]

local Rng = require(game:GetService("ReplicatedStorage").Shared.Logic.Rng)

local Objectives = {}

function Objectives.Matches(filter: { [string]: any }?, detail: { [string]: any }): boolean
	if filter == nil then
		return true
	end
	for key, want in filter do
		if key == "minRarity" then
			local rarity = detail.rarity
			if type(rarity) ~= "number" or rarity < want then
				return false
			end
		elseif detail[key] ~= want then
			return false
		end
	end
	return true
end

-- How much one topic event advances an objective (Config.Quests.CountField, default 1).
function Objectives.Amount(countFields: { [string]: string }?, topic: string, detail: { [string]: any }): number
	local field = countFields and countFields[topic]
	if not field then
		return 1
	end
	local n = detail[field]
	if type(n) ~= "number" or n ~= n then
		return 0
	end
	return math.max(0, math.floor(n))
end

function Objectives.Target(def): number
	return def.target or 1
end

-- Picks today's dailies: `count` distinct entries of `pool` that pass `eligible(def)`,
-- in a deterministic order for (userId, day). Returns the chosen definitions.
function Objectives.PickDailies(pool, count: number, userId: number, day: number, eligible: ((any) -> boolean)?)
	local candidates = {}
	for _, def in pool do
		if eligible == nil or eligible(def) then
			table.insert(candidates, def)
		end
	end
	Rng.new(Rng.seed("daily", userId, day)):Shuffle(candidates)
	local picked = {}
	for i = 1, math.min(count, #candidates) do
		picked[i] = candidates[i]
	end
	return picked
end

return Objectives
