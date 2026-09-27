--[[
	StrayLog (update 3.13 · Wild things): the Codex screen's Stray Log tab. A summary line (lines
	met, strays befriended) above a card per line a stray of it was met (profile.Strays.met): its
	adult portrait, name and how many were met and befriended (profile.Strays.friends).

	  local log = StrayLog.new(ctx, parent, size)
	  log.Refresh()   -- redraw from profile.Strays
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Strays)
local Appearance = require(Shared.Logic.Appearance)

local UI = script.Parent.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Widgets = require(UI.Components.Widgets)
local StoreKit = require(UI.Components.StoreKit)
local Tiles = require(UI.Components.Tiles)
local MonsterIcon = require(UI.Components.MonsterIcon)

local New = Create.New
local C = Theme.Colors

local StrayLog = {}

function StrayLog.new(ctx, parent: Instance, size: UDim2)
	local store = ctx.Store
	local list = Widgets.List({ Size = size, Padding = 8, Parent = parent })
	list.Name = "StrayLog"
	local api = { Root = list }

	function api.Refresh()
		Tiles.clear(list)
		local s = StoreKit.tbl(store, "profile.Strays")
		local met, friends = StoreKit.asTable(s.met), StoreKit.asTable(s.friends)
		local lines = {}
		for lineId, n in met do
			if Config.Species.ById[lineId] and (tonumber(n) or 0) > 0 then
				table.insert(lines, lineId)
			end
		end
		table.sort(lines, function(a, b)
			return Logic.Name(a) < Logic.Name(b)
		end)

		Tiles.label({
			Name = "StraySummary",
			Text = string.format("Stray Log · %d lines met · %d befriended", #lines, tonumber(s.total) or 0),
			TextSize = Theme.TextSize.Body,
			Size = UDim2.new(1, -12, 0, 28),
			LayoutOrder = 1,
			Parent = list,
		})
		if #lines == 0 then
			Tiles.label({
				Name = "StrayEmpty",
				Text = "No strays met yet. From Ranch Level 10 they wander onto your ranch while you play.",
				TextSize = Theme.TextSize.Small + 1,
				TextColor3 = C.TextMuted,
				TextWrapped = true,
				Size = UDim2.new(1, -12, 0, 48),
				LayoutOrder = 2,
				Parent = list,
			})
			return
		end
		local grid = New("Frame", {
			Name = "StrayGrid",
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -12, 0, 0),
			LayoutOrder = 3,
			Parent = list,
		}, { Create.Grid(Vector2.new(300, 96), 8) })
		for i, lineId in lines do
			local befriended = tonumber(friends[lineId]) or 0
			local card = Tiles.card({ Name = "Stray_" .. lineId, LayoutOrder = i, Parent = grid })
			card:SetAttribute("Met", tonumber(met[lineId]) or 0)
			card:SetAttribute("Befriended", befriended)
			local icon = MonsterIcon.new(Appearance.Preview(lineId, 3), 76)
			icon.Position = UDim2.fromOffset(8, 10)
			icon.Parent = card
			Tiles.label({
				Text = Logic.Name(lineId),
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(94, 10),
				Size = UDim2.new(1, -104, 0, 26),
				Parent = card,
			})
			Tiles.label({
				Text = string.format("Met %d · Befriended %d", tonumber(met[lineId]) or 0, befriended),
				TextSize = Theme.TextSize.Small,
				TextColor3 = if befriended > 0 then C.Green else C.TextMuted,
				Position = UDim2.fromOffset(94, 44),
				Size = UDim2.new(1, -104, 0, 24),
				Parent = card,
			})
		end
	end

	return api
end

return StrayLog
