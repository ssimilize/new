--[[
	ShowpieceChips (glow-up W): the TITANIC chip and the limited-edition chip ("#37/500", or
	LIMITED while the number is still being minted) for a monster record or an Appearance. Used by
	cards (Util.tagChips: trade window, Market, Breeding), MonsterDetail and the hatch reveal.

		ShowpieceChips.add(m, parent, layoutOrder?) -> number   chips added
		ShowpieceChips.sizeTag(m) -> "TITANIC" | "HUGE" | nil   the size word a card shows
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Editions = require(Shared.Logic.Editions)
local Titanic = require(Shared.Logic.Titanic)

local UI = script.Parent.Parent.Parent
local Widgets = require(UI.Components.Widgets)

local ShowpieceChips = {}

function ShowpieceChips.sizeTag(m): string?
	if Titanic.Is(m) then
		return "TITANIC"
	end
	local def = type(m) == "table" and Config.Species.ById[m.line]
	if def and type(m.weight) == "number" and m.weight >= def.weight * Config.Social.HugeWeightMult then
		return "HUGE"
	end
	return nil
end

function ShowpieceChips.add(m, parent: Instance, layoutOrder: number?): number
	local added = 0
	if Titanic.Is(m) then
		Widgets.Chip({
			Name = "TitanicChip",
			Text = "TITANIC",
			Color = Color3.fromHex(Config.Titanic.Color),
			LayoutOrder = layoutOrder or 0,
			Parent = parent,
		})
		added += 1
	end
	local label = Editions.Label(m)
	if label then
		Widgets.Chip({
			Name = "EditionChip",
			Text = string.format("#%d/%d", m.ltdNo, tonumber(m.ltdOf) or 0),
			Color = Color3.fromHex(Config.Editions.Color),
			LayoutOrder = (layoutOrder or 0) + 1,
			Parent = parent,
		})
		added += 1
	elseif Editions.Pending(m) then
		Widgets.Chip({
			Name = "EditionChip",
			Text = "LIMITED",
			Color = Color3.fromHex(Config.Editions.Color),
			LayoutOrder = (layoutOrder or 0) + 1,
			Parent = parent,
		})
		added += 1
	end
	return added
end

return ShowpieceChips
