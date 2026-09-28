--[[
	BugLog (update 3.13 · Bug Catching Meadow): the Codex screen's Bug Log tab. The milestone track
	(Logic/Codex.BugMilestones: kinds of bug caught, claimed through Codex.Claim) above a grid of
	every bug in Config.Bugs: caught ones in colour with how many, the rest as silhouettes; each card
	shows the bug's rarity and a Season or Night badge for the bugs that only come out then.

	  local log = BugLog.new(ctx, parent, size)
	  log.Refresh()   -- redraw from profile.Bugs.log + profile.Codex.claimed
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local CodexLogic = require(Shared.Logic.Codex)
local BugsLogic = require(Shared.Logic.Bugs)

local UI = script.Parent.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Widgets = require(UI.Components.Widgets)
local Button = require(UI.Components.Button)
local StoreKit = require(UI.Components.StoreKit)
local Tiles = require(UI.Components.Tiles)
local BugIcon = require(script.Parent.BugIcon)

local New = Create.New
local C = Theme.Colors

local BugLog = {}

local function seasonName(id: string): string
	local def = Config.Seasons and Config.Seasons.ById and Config.Seasons.ById[id]
	return if def and def.name then def.name else id
end

function BugLog.new(ctx, parent: Instance, size: UDim2)
	local store = ctx.Store
	local list = Widgets.List({ Size = size, Padding = 8, Parent = parent })
	list.Name = "BugLog"
	local api = { Root = list }

	local function claim(m)
		local ok, err = ctx.Net:Request("Codex.Claim", { milestone = m.id })
		if not ok then
			ctx:Toast(tostring(err), "error")
		end
	end

	function api.Refresh()
		Tiles.clear(list)
		local log = StoreKit.tbl(store, "profile.Bugs.log")
		local claimed = StoreKit.tbl(store, "profile.Codex.claimed")
		local species = BugsLogic.Species(log)

		Tiles.label({
			Name = "BugLogSummary",
			Text = string.format("Bug Log · %d / %d kinds caught", species, #Config.Bugs.List),
			TextSize = Theme.TextSize.Body,
			Size = UDim2.new(1, -12, 0, 28),
			LayoutOrder = 1,
			Parent = list,
		})
		local track = Tiles.row({ Name = "BugMilestones", Size = UDim2.new(1, -12, 0, 64), LayoutOrder = 2, Parent = list }, 8)
		for i, m in CodexLogic.BugMilestones() do
			local done = species >= m.need
			local cell = Tiles.card({ Name = m.id, Size = UDim2.fromOffset(300, 60), LayoutOrder = i, Parent = track })
			Tiles.label({
				Text = string.format("Catch %d kinds of bug · %d gems", m.need, m.gems),
				TextSize = Theme.TextSize.Small + 1,
				Position = UDim2.fromOffset(10, 4),
				Size = UDim2.new(1, -130, 0, 24),
				Parent = cell,
			})
			Widgets.Bar({
				Value = math.min(species, m.need) / m.need,
				Text = string.format("%d / %d", math.min(species, m.need), m.need),
				Position = UDim2.fromOffset(10, 32),
				Size = UDim2.new(1, -130, 0, 18),
				Parent = cell,
			})
			if claimed[m.id] then
				local chip = Widgets.Chip({ Text = "Claimed", Color = C.Green, Height = 32, Parent = cell })
				chip.Position = UDim2.new(1, -112, 0, 14)
			else
				local b = Button.new({
					Name = "Claim",
					Text = "Claim",
					Color = if done then C.Green else C.Gray,
					Size = UDim2.fromOffset(104, 48),
					Disabled = not done,
					OnClick = function()
						claim(m)
					end,
				})
				b.Root.Position = UDim2.new(1, -112, 0, 6)
				b.Root.Parent = cell
			end
		end

		local grid = New("Frame", {
			Name = "BugGrid",
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -12, 0, 0),
			LayoutOrder = 3,
			Parent = list,
		}, { Create.Grid(Vector2.new(170, 124), 8) })
		for _, def in Config.Bugs.List do
			local n = tonumber(log[def.id]) or 0
			local card = Tiles.card({ Name = "Bug_" .. def.id, LayoutOrder = def.order, Parent = grid })
			local icon = BugIcon.new(def.id, 60, n == 0)
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.Position = UDim2.new(0.5, 0, 0, 4)
			icon.Parent = card
			Tiles.label({
				Text = if n > 0 then def.name else "???",
				TextSize = Theme.TextSize.Small + 1,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 66),
				Size = UDim2.new(1, 0, 0, 20),
				Parent = card,
			})
			local rarity = Config.Bugs.Rarities[def.rarity].name
			Tiles.label({
				Text = if n > 0 then string.format("Caught %d · %s", n, rarity) else rarity,
				TextSize = Theme.TextSize.Small - 1,
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 90),
				Size = UDim2.new(1, 0, 0, 18),
				Parent = card,
			})
			local badge = if def.night then "Night" elseif def.season then seasonName(def.season) else nil
			if badge then
				local chip = Widgets.Chip({
					Name = "Badge",
					Text = badge,
					Color = if def.night then C.Purple else C.Orange,
					Height = 22,
					Parent = card,
				})
				chip.Position = UDim2.fromOffset(4, 4)
			end
		end
	end

	return api
end

return BugLog
