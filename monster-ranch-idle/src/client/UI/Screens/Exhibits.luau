--[[
	Exhibits screen (update 3.12 · Museum Exhibits): what is on display in the Curator wing.
	Opened from the Curator desk's "Exhibits" prompt (Controllers/CuratorWing) and the Codex
	screen's Exhibits button; no HUD button. Open params: { set = setId }.

	Left: a button per set shown (Set_<id>, Logic/Exhibits.Sets) with its count. Right, for the
	chosen set: its progress bar, the three reward steps (items needed, gems, stardust, the title
	on the last) and a Claim button (ClaimStep -> Exhibits.Claim, one step at a time), then a tile
	per exhibit (Exhibit_<itemId>, attribute Filled): on display, a Donate button with how many you
	have (Donate -> Exhibits.Donate; fish, relics from decor storage, honey), or the set's hint for
	sets that fill themselves. The header shows the whole museum's count and its Tourist appeal.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Exhibits)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local StoreKit = require(UI.Components.StoreKit)
local Tiles = require(UI.Components.Tiles)
local Util = require(script.Parent.Parts.Util)
local FishIcon = require(script.Parent.Parts.FishIcon)
local BugIcon = require(script.Parent.Parts.BugIcon)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Exhibits

local function hex(s: string?, fallback: string): Color3
	local ok, c = pcall(Color3.fromHex, s or fallback)
	return if ok then c else Color3.fromHex(fallback)
end

-- An exhibit's icon, drawn from UI shapes (no images).
local function iconOf(setId: string, item, size: number, dim: boolean): GuiObject
	if setId == "aquarium" then
		return FishIcon.new(item.id, size, dim)
	elseif setId == "insects" then
		return BugIcon.new(item.id, size, dim)
	end
	local root = New("Frame", { Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) })
	local c1 = if dim then Color3.fromHex("#3B3350") else hex(item.color, "#EDE3D3")
	local c2 = if dim then Color3.fromHex("#2A2440") else hex(item.color2, "#3A2A1C")
	if setId == "fossils" then
		New("Frame", {
			BackgroundColor3 = c1,
			Position = UDim2.fromScale(0.1, 0.12),
			Size = UDim2.fromScale(0.42, 0.42),
			Parent = root,
		}, { Create.Round(), Create.Stroke(2) })
		for i = 0, 2 do
			New("Frame", {
				BackgroundColor3 = c1,
				Position = UDim2.fromScale(0.5, 0.42 + i * 0.16),
				Size = UDim2.fromScale(0.4, 0.1),
				Parent = root,
			}, { Create.Corner(3), Create.Stroke(1.5) })
		end
	elseif setId == "relics" then
		New("Frame", {
			BackgroundColor3 = c1,
			Position = UDim2.fromScale(0.18, 0.2),
			Size = UDim2.fromScale(0.64, 0.7),
			Parent = root,
		}, { Create.Corner(6), Create.Stroke(3, c2) })
	elseif setId == "honey" then
		New("Frame", {
			BackgroundColor3 = c1,
			Position = UDim2.fromScale(0.18, 0.28),
			Size = UDim2.fromScale(0.64, 0.64),
			Parent = root,
		}, { Create.Corner(10), Create.Stroke(2) })
		New("Frame", {
			BackgroundColor3 = if dim then c2 else Color3.fromHex("#8A5A2B"),
			Position = UDim2.fromScale(0.24, 0.12),
			Size = UDim2.fromScale(0.52, 0.18),
			Parent = root,
		}, { Create.Corner(4), Create.Stroke(2) })
	else
		New("Frame", {
			BackgroundColor3 = if dim then c2 else Color3.fromHex("#2B2250"),
			Position = UDim2.fromScale(0.08, 0.08),
			Size = UDim2.fromScale(0.84, 0.84),
			Parent = root,
		}, { Create.Round(), Create.Stroke(2) })
		for i, at in { { 0.3, 0.3 }, { 0.6, 0.45 }, { 0.4, 0.66 } } do
			New("Frame", {
				BackgroundColor3 = c1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(at[1], at[2]),
				Size = UDim2.fromScale(if i == 1 then 0.16 else 0.1, if i == 1 then 0.16 else 0.1),
				Rotation = 45,
				Parent = root,
			})
		end
	end
	return root
end

return {
	Name = "Exhibits",
	Build = function(ctx)
		local store = ctx.Store
		local panel = Panel.new({
			Title = "Museum Exhibits",
			Color = C.Purple,
			Size = UDim2.fromOffset(980, 500),
			OnClose = function()
				ctx.Router:Close("Exhibits")
			end,
		})
		local summary = Create.Text({
			Name = "ExhibitsSummary",
			Text = "",
			TextSize = Theme.TextSize.Body,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 40),
			TextWrapped = false,
			Parent = panel.HeaderRight,
		})

		local body = New("Frame", { Name = "ExhibitsBody", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })
		local side = Tiles.col({ Name = "Sets", Size = UDim2.new(0, 190, 1, 0), Parent = body }, 8)
		local main = New("Frame", {
			Name = "SetView",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(204, 0),
			Size = UDim2.new(1, -204, 1, 0),
			Parent = body,
		})

		local selected = Cfg.Sets[1].id
		local busy = false
		local draw

		local function filledOf()
			return StoreKit.tbl(store, "profile.Exhibits.filled")
		end

		-- How many of an item you could donate now (and, for relics, how many are placed).
		local function haveOf(setId: string, itemId: string): (number, number)
			if setId == "aquarium" then
				return StoreKit.num(store, "profile.Fishing.fish." .. itemId, 0), 0
			elseif setId == "relics" then
				local placed = 0
				for _, entry in StoreKit.asTable(store:Get("profile.Decor.layout")) do
					if type(entry) == "table" and entry.id == itemId then
						placed += 1
					end
				end
				return StoreKit.num(store, "profile.Shop.decor." .. itemId, 0), placed
			elseif setId == "honey" then
				-- The Apiary keeps its jars in profile.Apiary.store ({ [kind]: n }, royal_jelly included).
				local jars = StoreKit.tbl(store, "profile.Apiary.store")
				return tonumber(jars[itemId]) or 0, 0
			end
			return 0, 0
		end

		local function request(action: string, payload)
			if busy then
				return
			end
			busy = true
			local ok, err = ctx.Net:Request(action, payload)
			busy = false
			if not ok then
				ctx:Toast(tostring(err), "error")
			end
			draw()
		end

		local function drawSide(sets, filled)
			Tiles.clear(side)
			for i, set in sets do
				local have, total = Logic.Count(Config, set.id, filled)
				Button.new({
					Name = "Set_" .. set.id,
					Text = string.format("%s · %d / %d", set.name, have, total),
					TextSize = Theme.TextSize.Small + 1,
					Color = if set.id == selected then C.Orange else C.Gray,
					Size = UDim2.fromOffset(186, 52),
					LayoutOrder = i,
					Parent = side,
					Sound = "UITab",
					OnClick = function()
						selected = set.id
						draw()
					end,
				})
			end
		end

		local function drawSet(set, filled)
			Tiles.clear(main)
			local items = Logic.Items(Config, set.id) or {}
			local have, total = Logic.Count(Config, set.id, filled)
			local paid = tonumber(StoreKit.tbl(store, "profile.Exhibits.paid")[set.id]) or 0
			local head = Tiles.card({ Name = "SetHead", Size = UDim2.new(1, -8, 0, 116), Parent = main })
			Tiles.label({
				Text = set.name,
				TextSize = Theme.TextSize.Header,
				Position = UDim2.fromOffset(12, 6),
				Size = UDim2.new(0.5, 0, 0, 30),
				Parent = head,
			})
			Widgets.Bar({
				Name = "SetProgress",
				Value = if total > 0 then have / total else 0,
				Text = string.format("%d / %d on display", have, total),
				Color = hex(set.color, "#6B5BD6"),
				Position = UDim2.fromOffset(12, 40),
				Size = UDim2.new(1, -170, 0, 22),
				Parent = head,
			})
			local steps =
				Tiles.row({ Name = "Steps", Position = UDim2.fromOffset(12, 70), Size = UDim2.new(1, -170, 0, 40), Parent = head }, 6)
			for step = 1, #Cfg.Steps do
				local need = Logic.Need(Cfg.Steps, total, step)
				local gems, dust = Logic.Reward(Config, total, step)
				local done = paid >= step
				local cell = New("Frame", {
					Name = "Step" .. step,
					BackgroundColor3 = if done then C.Green elseif have >= need then C.Gold else C.PanelDeep,
					BackgroundTransparency = if done or have >= need then 0 else 0.3,
					Size = UDim2.new(1 / 3, -4, 1, 0),
					LayoutOrder = step,
					Parent = steps,
				}, { Create.Corner(8), Create.Stroke(2) })
				cell:SetAttribute("Paid", done)
				Tiles.label({
					Text = if step == #Cfg.Steps
						then string.format("%d · %d gems · %d stardust · title", need, gems, dust)
						else string.format("%d · %d gems · %d stardust", need, gems, dust),
					TextSize = Theme.TextSize.Small,
					TextColor3 = if done or have >= need then C.Ink else C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.fromScale(1, 1),
					Parent = cell,
				})
			end
			local ready = Logic.Claimable(Config, set.id, filled, { [set.id] = paid })
			local claim = Button.new({
				Name = "ClaimStep",
				Text = if paid >= #Cfg.Steps then "Claimed" else "Claim",
				Color = if ready then C.Green else C.Gray,
				Disabled = ready == nil,
				Size = UDim2.fromOffset(136, 56),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Parent = head,
				OnClick = function()
					if ready then
						request("Exhibits.Claim", { set = set.id })
					end
				end,
			})
			claim.Root:SetAttribute("Step", ready or 0)

			local list = Widgets.List({
				Name = "ExhibitList",
				Position = UDim2.fromOffset(0, 124),
				Size = UDim2.new(1, -8, 1, -124),
				Padding = 8,
				Parent = main,
			})
			local grid = New("Frame", {
				Name = "ExhibitGrid",
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, -12, 0, 0),
				LayoutOrder = 1,
				Parent = list,
			}, { Create.Grid(Vector2.new(176, 128), 8) })
			local mine = StoreKit.asTable(filled[set.id])
			for i, item in items do
				local on = mine[item.id] == true
				local card = Tiles.card({ Name = "Exhibit_" .. item.id, LayoutOrder = i, Parent = grid })
				card:SetAttribute("Filled", on)
				local icon = iconOf(set.id, item, 44, not on)
				icon.Position = UDim2.fromOffset(8, 8)
				icon.Parent = card
				Tiles.label({
					Text = item.name,
					TextSize = Theme.TextSize.Small + 1,
					TextWrapped = true,
					Position = UDim2.fromOffset(58, 6),
					Size = UDim2.new(1, -64, 0, 48),
					Parent = card,
				})
				if on then
					Tiles.label({
						Name = "OnDisplay",
						Text = "On display",
						TextSize = Theme.TextSize.Small,
						TextColor3 = C.Green,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.new(0, 8, 1, -50),
						Size = UDim2.new(1, -16, 0, 44),
						Parent = card,
					})
				elseif set.fill ~= "donate" then
					Tiles.label({
						Name = "Hint",
						Text = set.hint or "",
						TextSize = Theme.TextSize.Small,
						TextColor3 = C.TextMuted,
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.new(0, 8, 1, -60),
						Size = UDim2.new(1, -16, 0, 54),
						Parent = card,
					})
				else
					local n, placed = haveOf(set.id, item.id)
					Button.new({
						Name = "Donate",
						Text = if n > 0 then string.format("Donate · have %d", n) elseif placed > 0 then "All placed" else "None yet",
						TextSize = Theme.TextSize.Small,
						Color = if n > 0 then C.Green else C.Gray,
						Disabled = n <= 0,
						Size = UDim2.new(1, -16, 0, 48),
						Position = UDim2.new(0, 8, 1, -56),
						Parent = card,
						OnClick = function()
							if n > 0 then
								request("Exhibits.Donate", { set = set.id, item = item.id })
							end
						end,
					})
				end
			end
		end

		function draw()
			local filled = filledOf()
			local sets = Logic.Sets(Config)
			local found = false
			for _, set in sets do
				found = found or set.id == selected
			end
			if not found and sets[1] then
				selected = sets[1].id
			end
			local have, total = 0, 0
			for _, set in sets do
				local h, t = Logic.Count(Config, set.id, filled)
				have += h
				total += t
			end
			local appeal = if Util.unlocked(ctx, Cfg.Unlock) then Logic.Appeal(Config, filled) else 0
			summary.Text = string.format("%d / %d on display · Tourist appeal +%d", have, total, appeal)
			drawSide(sets, filled)
			if Cfg.ById[selected] then
				drawSet(Cfg.ById[selected], filled)
			end
			local lock = body:FindFirstChild("Lock")
			if lock then
				lock:Destroy()
			end
			if not Util.unlocked(ctx, Cfg.Unlock) then
				Util.lockOverlay(body, Util.unlockText(Cfg.Unlock))
			end
		end

		local watch = StoreKit.watch(store, {
			"profile.Exhibits",
			"profile.Fishing.fish",
			"profile.Shop.decor",
			"profile.Decor.layout",
			"profile.Apiary",
			"profile.Progression",
		}, function()
			if not busy then
				draw()
			end
		end)

		return {
			Root = panel.Root,
			Open = function(params)
				if type(params) == "table" and type(params.set) == "string" and Cfg.ById[params.set] then
					selected = params.set
				end
				watch.Start()
				draw()
			end,
			Close = function()
				watch.Stop()
			end,
		}
	end,
}
