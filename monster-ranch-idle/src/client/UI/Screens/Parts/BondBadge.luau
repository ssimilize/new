--[[
	Parts/BondBadge (glow-up Q): a monster's bond hearts as the player sees them
	(profile.Bond.list, rules in Logic/Bond). Used by the Care screen, the Monsters grid and
	MonsterDetail.

	  BondBadge.of(ctx, id) -> { points, hearts, into, need, pct }
	  BondBadge.row(hearts) -> string                      "♥♥♥♡♡♡♡♡♡♡"
	  BondBadge.card(ctx, id, parent) -> TextLabel?        a small "♥3" in a card's corner, nil at 0
	  BondBadge.chip(ctx, id, parent, layoutOrder?) -> Frame?   header chip, nil at 0 hearts
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Bond)

local UI = script.Parent.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Widgets = require(UI.Components.Widgets)

local Cfg = Config.Bond

local BondBadge = {}

function BondBadge.of(ctx, id: string)
	local list = ctx.Store:Get("profile.Bond.list")
	local entry = if type(list) == "table" then list[id] else nil
	local points = if type(entry) == "table" then tonumber(entry.pts) or 0 else 0
	local hearts, into, need = Logic.Progress(points, Cfg)
	return { points = points, hearts = hearts, into = into, need = need, pct = Logic.IncomePct(hearts, Cfg), entry = entry }
end

function BondBadge.row(hearts: number): string
	local h = math.clamp(math.floor(hearts), 0, Cfg.MaxHearts)
	return string.rep("♥", h) .. string.rep("♡", Cfg.MaxHearts - h)
end

function BondBadge.card(ctx, id: string, parent: Instance): TextLabel?
	local info = BondBadge.of(ctx, id)
	if info.hearts <= 0 then
		return nil
	end
	local label = Create.Text({
		Name = "BondHearts",
		Text = "♥" .. info.hearts,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.Pink,
		Stroke = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(6, 20),
		Size = UDim2.fromOffset(40, 18),
		ZIndex = 12,
		Parent = parent,
	})
	label:SetAttribute("Localize", false)
	return label
end

function BondBadge.chip(ctx, id: string, parent: Instance, layoutOrder: number?): Frame?
	local info = BondBadge.of(ctx, id)
	if info.hearts <= 0 then
		return nil
	end
	local chip = Widgets.Chip({
		Name = "BondBadge",
		Text = "♥ " .. info.hearts,
		Color = Theme.Colors.Pink,
		LayoutOrder = layoutOrder or 20,
		Parent = parent,
	})
	for _, d in chip:GetDescendants() do
		if d:IsA("TextLabel") then
			d:SetAttribute("Localize", false)
		end
	end
	return chip
end

return BondBadge
