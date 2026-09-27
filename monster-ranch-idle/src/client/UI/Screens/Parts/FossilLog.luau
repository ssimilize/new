--[[
	FossilLog (update 3.11 · Dig Site): the Codex screen's Fossils tab. The milestone track
	(Logic/Codex.FossilMilestones: fossils completed, claimed through Codex.Claim) above a card per
	fossil in Config.DigSite: its four pieces (dug ones in bone colour, the rest dark) and whether
	its skeleton display is yours.

	  local log = FossilLog.new(ctx, parent, size)
	  log.Refresh()   -- redraw from profile.DigSite.pieces + profile.Codex.claimed
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local CodexLogic = require(Shared.Logic.Codex)
local DigLogic = require(Shared.Logic.DigSite)

local UI = script.Parent.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Widgets = require(UI.Components.Widgets)
local Button = require(UI.Components.Button)
local StoreKit = require(UI.Components.StoreKit)
local Tiles = require(UI.Components.Tiles)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.DigSite

local FossilLog = {}

function FossilLog.new(ctx, parent: Instance, size: UDim2)
	local store = ctx.Store
	local list = Widgets.List({ Size = size, Padding = 8, Parent = parent })
	list.Name = "FossilLog"
	local api = { Root = list }

	local function claim(m)
		local ok, err = ctx.Net:Request("Codex.Claim", { milestone = m.id })
		if not ok then
			ctx:Toast(tostring(err), "error")
		end
	end

	function api.Refresh()
		Tiles.clear(list)
		local pieces = StoreKit.tbl(store, "profile.DigSite.pieces")
		local claimed = StoreKit.tbl(store, "profile.Codex.claimed")
		local done = DigLogic.Fossils(pieces)

		Tiles.label({
			Name = "FossilSummary",
			Text = if DigLogic.PieceCount(pieces) == 1
				then string.format("Fossils · %d / %d complete · 1 piece", done, #Cfg.Fossils)
				else string.format("Fossils · %d / %d complete · %d pieces", done, #Cfg.Fossils, DigLogic.PieceCount(pieces)),
			TextSize = Theme.TextSize.Body,
			Size = UDim2.new(1, -12, 0, 28),
			LayoutOrder = 1,
			Parent = list,
		})
		local track = Tiles.row({ Name = "FossilMilestones", Size = UDim2.new(1, -12, 0, 64), LayoutOrder = 2, Parent = list }, 8)
		for i, m in CodexLogic.FossilMilestones() do
			local ready = done >= m.need
			local cell = Tiles.card({ Name = m.id, Size = UDim2.fromOffset(300, 60), LayoutOrder = i, Parent = track })
			Tiles.label({
				Text = string.format("Complete %d fossils · %d gems", m.need, m.gems),
				TextSize = Theme.TextSize.Small + 1,
				Position = UDim2.fromOffset(10, 4),
				Size = UDim2.new(1, -130, 0, 24),
				Parent = cell,
			})
			Widgets.Bar({
				Value = math.min(done, m.need) / m.need,
				Text = string.format("%d / %d", math.min(done, m.need), m.need),
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
					Color = if ready then C.Green else C.Gray,
					Size = UDim2.fromOffset(104, 48),
					Disabled = not ready,
					OnClick = function()
						claim(m)
					end,
				})
				b.Root.Position = UDim2.new(1, -112, 0, 6)
				b.Root.Parent = cell
			end
		end

		local grid = New("Frame", {
			Name = "FossilGrid",
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -12, 0, 0),
			LayoutOrder = 3,
			Parent = list,
		}, { Create.Grid(Vector2.new(300, 118), 8) })
		for _, def in Cfg.Fossils do
			local have = StoreKit.asTable(pieces[def.id])
			local count = 0
			for _, p in Cfg.Pieces do
				if have[p.id] then
					count += 1
				end
			end
			local complete = count == #Cfg.Pieces
			local card = Tiles.card({ Name = "Fossil_" .. def.id, LayoutOrder = def.order, Parent = grid })
			Tiles.label({
				Text = if count > 0 then def.name else "???",
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(10, 4),
				Size = UDim2.new(1, -20, 0, 24),
				Parent = card,
			})
			local row = New("Frame", {
				Name = "Pieces",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(10, 32),
				Size = UDim2.new(1, -20, 0, 44),
				Parent = card,
			}, { Create.List("x", 6) })
			for _, p in Cfg.Pieces do
				local got = have[p.id] == true
				local chip = New("Frame", {
					Name = "Piece_" .. p.id,
					BackgroundColor3 = if got then Color3.fromHex(def.color) else C.PanelDeep,
					BackgroundTransparency = if got then 0 else 0.4,
					Size = UDim2.fromOffset(64, 40),
					LayoutOrder = p.order,
					Parent = row,
				}, { Create.Corner(8), Create.Stroke(2) })
				chip:SetAttribute("Found", got)
				Tiles.label({
					Text = p.name,
					TextSize = Theme.TextSize.Small,
					TextColor3 = if got then C.Ink else C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.fromScale(1, 1),
					Parent = chip,
				})
			end
			Tiles.label({
				Text = if complete then "Complete · skeleton display unlocked" else string.format("%d / %d pieces", count, #Cfg.Pieces),
				TextSize = Theme.TextSize.Small,
				TextColor3 = if complete then C.Green else C.TextMuted,
				Position = UDim2.fromOffset(10, 82),
				Size = UDim2.new(1, -20, 0, 22),
				Parent = card,
			})
		end
	end

	return api
end

return FossilLog
