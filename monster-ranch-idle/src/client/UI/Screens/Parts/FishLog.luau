--[[
	FishLog (update 3.10 · Fishing Pond): the Codex screen's Fish Log tab. The milestone track
	(Logic/Codex.FishMilestones: kinds of fish caught, claimed through Codex.Claim) above a grid of
	every fish in Config.Fishing: caught ones in colour with how many and the heaviest, the rest as
	silhouettes.

	  local log = FishLog.new(ctx, parent, size)
	  log.Refresh()   -- redraw from profile.Fishing.log + profile.Codex.claimed
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local CodexLogic = require(Shared.Logic.Codex)
local FishLogic = require(Shared.Logic.Fishing)

local UI = script.Parent.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Widgets = require(UI.Components.Widgets)
local Button = require(UI.Components.Button)
local StoreKit = require(UI.Components.StoreKit)
local Tiles = require(UI.Components.Tiles)
local FishIcon = require(script.Parent.FishIcon)

local New = Create.New
local C = Theme.Colors

local FishLog = {}

function FishLog.new(ctx, parent: Instance, size: UDim2)
	local store = ctx.Store
	local list = Widgets.List({ Size = size, Padding = 8, Parent = parent })
	list.Name = "FishLog"
	local api = { Root = list }

	local function claim(m)
		local ok, err = ctx.Net:Request("Codex.Claim", { milestone = m.id })
		if not ok then
			ctx:Toast(tostring(err), "error")
		end
	end

	function api.Refresh()
		Tiles.clear(list)
		local log = StoreKit.tbl(store, "profile.Fishing.log")
		local claimed = StoreKit.tbl(store, "profile.Codex.claimed")
		local species = FishLogic.Species(log)

		Tiles.label({
			Name = "FishLogSummary",
			Text = string.format("Fish Log · %d / %d kinds caught", species, #Config.Fishing.Fish),
			TextSize = Theme.TextSize.Body,
			Size = UDim2.new(1, -12, 0, 28),
			LayoutOrder = 1,
			Parent = list,
		})
		local track = Tiles.row({ Name = "FishMilestones", Size = UDim2.new(1, -12, 0, 64), LayoutOrder = 2, Parent = list }, 8)
		for i, m in CodexLogic.FishMilestones() do
			local done = species >= m.need
			local cell = Tiles.card({ Name = m.id, Size = UDim2.fromOffset(300, 60), LayoutOrder = i, Parent = track })
			Tiles.label({
				Text = string.format("Catch %d kinds · %d gems", m.need, m.gems),
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
			Name = "FishGrid",
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -12, 0, 0),
			LayoutOrder = 3,
			Parent = list,
		}, { Create.Grid(Vector2.new(170, 124), 8) })
		for _, def in Config.Fishing.Fish do
			local entry = log[def.id]
			local n = if type(entry) == "table" then tonumber(entry.n) or 0 else 0
			local card = Tiles.card({ Name = "Log_" .. def.id, LayoutOrder = def.order, Parent = grid })
			local icon = FishIcon.new(def.id, 64, n == 0)
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.Position = UDim2.new(0.5, 0, 0, 2)
			icon.Parent = card
			Tiles.label({
				Text = if n > 0 then def.name else "???",
				TextSize = Theme.TextSize.Small + 1,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 66),
				Size = UDim2.new(1, 0, 0, 20),
				Parent = card,
			})
			Tiles.label({
				Text = if n > 0
					then string.format("×%d · best %s", n, Format.weight(tonumber(entry.best) or 0))
					else Config.Fishing.RarityById[def.rarity].name,
				TextSize = Theme.TextSize.Small - 1,
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 90),
				Size = UDim2.new(1, 0, 0, 18),
				Parent = card,
			})
		end
	end

	return api
end

return FishLog
