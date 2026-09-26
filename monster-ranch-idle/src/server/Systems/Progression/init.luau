--[[
	Progression (S1): Ranch XP and Ranch Level, and every level-gated unlock.

	The level cap is Config.Unlocks.MaxLevelAt(ctx:Now()) (date-gated: 60, then 70 from
	Sat 11 Mar 2028). At the cap, XP is not banked.

	Other systems grant XP by publishing the "RanchXP" topic (no dependency needed) or by
	calling AddXP directly.

	Public API:
	  Progression:AddXP(player, amount, reason)
	  Progression:GetLevel(player) -> number
	  Progression:IsUnlocked(player, featureKey) -> boolean
	  Progression:Require(player, featureKey)     -- ctx:Fail("Unlocks at Ranch Level N")
	  Progression:UnlockLevel(featureKey) -> number
]]

local Progression = {
	Name = "Progression",
	Dependencies = {},
}

Progression.Profile = {
	Version = 1,
	Default = function()
		return { level = 1, xp = 0 }
	end,
}

local ctx
local Unlocks

function Progression.Init(context)
	ctx = context
	Unlocks = ctx.Config.Unlocks
	ctx.Bus:Subscribe("RanchXP", function(player, detail)
		if ctx:IsReady(player) or ctx:Section(player) then
			Progression:AddXP(player, detail.amount or 0, detail.reason)
		end
	end)
end

function Progression:UnlockLevel(featureKey: string): number
	local level = Unlocks.Features[featureKey]
	assert(level, "[Progression] unknown unlock key '" .. tostring(featureKey) .. "' (add it to Config.Unlocks.Features)")
	return level
end

function Progression:GetLevel(player): number
	local section = ctx:Section(player)
	return section and section.level or 1
end

function Progression:IsUnlocked(player, featureKey: string): boolean
	return Progression:GetLevel(player) >= Progression:UnlockLevel(featureKey)
end

function Progression:Require(player, featureKey: string)
	local needed = Progression:UnlockLevel(featureKey)
	if Progression:GetLevel(player) < needed then
		ctx:Fail(string.format("Unlocks at Ranch Level %d", needed))
	end
end

function Progression:AddXP(player, amount: number, reason: string?)
	local section = ctx:Section(player)
	if not section or type(amount) ~= "number" or amount <= 0 or amount ~= amount then
		return
	end
	section.xp += amount
	-- The cap is date-gated (Config.Unlocks.LevelCaps): a player who sat at the old cap with
	-- xp reset to 0 simply starts earning toward the next level once the cap rises.
	local cap = Unlocks.MaxLevelAt(ctx:Now())
	local leveled = {}
	while section.level < cap and section.xp >= Unlocks.XPToNext(section.level) do
		section.xp -= Unlocks.XPToNext(section.level)
		section.level += 1
		table.insert(leveled, section.level)
	end
	if section.level >= cap then
		section.xp = 0
	end
	ctx:Dirty(player)
	for _, level in leveled do
		local unlocks = Unlocks.At(level)
		ctx.Net:Fire(player, "Progression.LevelUp", { level = level, unlocks = unlocks })
		ctx.Bus:Publish("LevelUp", player, { level = level })
		ctx.Analytics.Custom(player, "RanchLevel", level, { reason = reason or "unknown" })
	end
end

return Progression
