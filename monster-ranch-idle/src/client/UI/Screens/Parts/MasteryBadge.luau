--[[
	Parts/MasteryBadge (3.3): a species line's Line Mastery as the player sees it
	(profile.Mastery.lines, rules in Logic/Mastery). Used by MonsterDetail, the Codex and the
	Mastery screen.

	  MasteryBadge.of(ctx, lineId) -> { points, level, into, need, tier? }
	  MasteryBadge.chip(ctx, lineId, parent, layoutOrder?) -> Frame?   nil below Bronze
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Logic = require(Shared.Logic.Mastery)

local UI = script.Parent.Parent.Parent
local Widgets = require(UI.Components.Widgets)

local MasteryBadge = {}

function MasteryBadge.of(ctx, lineId: string)
	local lines = ctx.Store:Get("profile.Mastery.lines")
	local points = if type(lines) == "table" then tonumber(lines[lineId]) or 0 else 0
	local level, into, need = Logic.LineLevel(points)
	return { points = points, level = level, into = into, need = need, tier = Logic.LineTier(level) }
end

function MasteryBadge.chip(ctx, lineId: string, parent: Instance, layoutOrder: number?): Frame?
	local info = MasteryBadge.of(ctx, lineId)
	if not info.tier then
		return nil
	end
	return Widgets.Chip({
		Name = "MasteryBadge",
		Text = string.format("%s Mastery", info.tier.name),
		Color = Color3.fromHex(info.tier.color),
		LayoutOrder = layoutOrder or 20,
		Parent = parent,
	})
end

return MasteryBadge
