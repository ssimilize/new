--[[
	Trade screen (C3), driven by session.Trade.

	No trade: every player on the server with a Request button (Trade.Request), plus the
	outgoing / incoming request state (Trade.Cancel / Trade.Respond).
	Open trade: your offer grid (add monsters via Monsters pick mode with returnTo "Trade",
	add eggs from profile.Eggs.list; tap to remove → Trade.SetOffer), their offer with every
	value tag (rarity, variant, mutations, weight, level, stars), Ready / Confirm / countdown /
	Cancel and a warning line.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local Util = require(script.Parent.Parts.Util)
local Dialog = require(script.Parent.Parts.Dialog)

local New = Create.New
local C = Theme.Colors
local TradeConfig = Config.Social.Trade
local MAX = TradeConfig.maxItems

local TILE = Vector2.new(110, 146)

local function eggName(eggType): string
	local def = eggType and Config.Eggs.ById[eggType]
	return if def then def.name else "Egg"
end

local function signature(item): string
	if not item then
		return ""
	end
	return tostring(item.kind) .. ":" .. tostring(item.id) .. ":" .. tostring(item.egg)
end

return {
	Name = "Trade",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Trade",
			Color = C.Purple,
			Size = UDim2.fromOffset(1040, 520),
			OnClose = function()
				ctx.Router:Close("Trade")
			end,
		})

		local isOpen = false
		local bag = Util.bag()
		local lastTheirs = {}
		local refresh

		local function trade()
			return ctx.Store:Get("session.Trade") or { status = "none" }
		end
		local function side(which: string)
			local s = trade()[which]
			return if type(s) == "table" then s else { items = {}, ready = false, confirmed = false }
		end

		-- Views --------------------------------------------------------------------------------

		local lobby = New("Frame", { Name = "Lobby", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })
		local tradeView =
			New("Frame", { Name = "TradeView", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })

		local playersCard = Util.card({ Title = "Players on this server", Size = UDim2.new(0, 560, 1, 0), Parent = lobby })
		local playerList =
			Widgets.List({ Position = UDim2.fromOffset(4, 42), Size = UDim2.new(1, -8, 1, -46), Padding = 8, Parent = playersCard })
		local statusCard =
			Util.card({ Title = "Trading", Position = UDim2.fromOffset(572, 0), Size = UDim2.new(1, -572, 1, 0), Parent = lobby })
		local statusBody = New("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 42),
			Size = UDim2.new(1, -28, 1, -52),
			Parent = statusCard,
		}, { Create.List("y", 10) })

		local function sideColumn(x: number, name: string)
			local column = New("Frame", {
				Name = name,
				BackgroundTransparency = 1,
				Position = UDim2.new(x, if x > 0 then 8 else 0, 0, 0),
				Size = UDim2.new(0.5, -8, 1, -70),
				Parent = tradeView,
			})
			local header = Util.text({
				Text = "",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body + 2,
				Size = UDim2.new(1, -140, 0, 32),
				Parent = column,
			})
			local badge = Widgets.Chip({ Text = "✓ Ready", Color = C.Green, Height = 30, Parent = column })
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, 0, 0, 1)
			local grid = New("Frame", {
				Name = "Grid",
				BackgroundColor3 = C.PanelDeep,
				Position = UDim2.fromOffset(0, 38),
				Size = UDim2.new(1, 0, 1, -38),
				Parent = column,
			}, { Create.Corner(Theme.Radius.Card), Create.Padding(8), Create.Grid(TILE, 8) })
			return { header = header, badge = badge, grid = grid }
		end
		local mineCol = sideColumn(0, "Mine")
		local theirsCol = sideColumn(0.5, "Theirs")

		local bottom = New("Frame", {
			Name = "Bottom",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 60),
			Parent = tradeView,
		})
		Util.text({
			Text = "Check every tag. Trades are final once the countdown ends. Any change resets both sides.",
			TextColor3 = C.TextMuted,
			Size = UDim2.new(1, -560, 1, 0),
			Parent = bottom,
		})
		local actions = New("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 550, 1, 0),
			Parent = bottom,
		}, { Create.List("x", 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
		local cancelButton =
			Button.new({ Text = "Cancel", Color = C.Red, Size = UDim2.fromOffset(130, 54), LayoutOrder = 1, Parent = actions })
		local readyButton =
			Button.new({ Text = "Ready", Color = C.Orange, Size = UDim2.fromOffset(170, 54), LayoutOrder = 2, Parent = actions })
		local confirmButton =
			Button.new({ Text = "Confirm", Color = C.Green, Size = UDim2.fromOffset(220, 54), LayoutOrder = 3, Parent = actions })

		-- Offer editing -------------------------------------------------------------------------

		local function offerPayload(items)
			local list = {}
			for _, item in items do
				if item.kind and item.id then
					table.insert(list, { kind = item.kind, id = item.id })
				end
			end
			return list
		end

		local function setOffer(list)
			Util.request(ctx, "Trade.SetOffer", { items = list })
		end

		local function offeredIds(): { [string]: boolean }
			local set = {}
			for _, item in side("mine").items or {} do
				if item.id then
					set[item.id] = true
				end
			end
			return set
		end

		local function addMonsters()
			local items = side("mine").items or {}
			local room = MAX - #items
			if room <= 0 then
				ctx:Toast(string.format("Up to %d items per side", MAX), "error")
				return
			end
			local offered = offeredIds()
			Util.pick(ctx, {
				title = "Add monsters to your offer",
				max = room,
				filter = function(m)
					return not m.busy and not m.locked and not offered[m.id]
				end,
				returnTo = "Trade",
				onPick = function(ids)
					local list = offerPayload(side("mine").items or {})
					for _, id in ids do
						if #list >= MAX then
							break
						end
						table.insert(list, { kind = "monster", id = id })
					end
					setOffer(list)
				end,
			})
		end

		local function availableEggs(): { [string]: { string } }
			local eggs = ctx.Store:Get("profile.Eggs") or {}
			local inSlot = {}
			for _, slot in eggs.slots or {} do
				if type(slot) == "table" and slot.egg then
					inSlot[slot.egg] = true
				end
			end
			local offered = offeredIds()
			local byType = {}
			for id, egg in eggs.list or {} do
				if not inSlot[id] and not offered[id] and type(egg) == "table" then
					byType[egg.type] = byType[egg.type] or {}
					table.insert(byType[egg.type], id)
				end
			end
			for _, ids in byType do
				table.sort(ids)
			end
			return byType
		end

		local function addEgg()
			local byType = availableEggs()
			local types = {}
			for eggType in byType do
				table.insert(types, eggType)
			end
			table.sort(types, function(a, b)
				local da, db = Config.Eggs.ById[a], Config.Eggs.ById[b]
				return (da and da.order or 99) < (db and db.order or 99)
			end)
			if #types == 0 then
				ctx:Toast("No free eggs to offer", "error")
				return
			end
			Dialog.show(ctx.UI.Top, {
				Title = "Add an egg",
				Color = C.Purple,
				Size = Vector2.new(640, 330),
				Build = function(content, close)
					local grid = New("Frame", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						LayoutOrder = 2,
						Parent = content,
					}, { Create.Grid(Vector2.new(130, 150), 10) })
					for i, eggType in types do
						local cell = New("TextButton", {
							Text = "",
							AutoButtonColor = false,
							BackgroundColor3 = C.Card,
							LayoutOrder = i,
							Parent = grid,
						}, { Create.Corner(Theme.Radius.Card), Create.Stroke(2.5) })
						local icon = MonsterIcon.egg(eggType, 80)
						icon.AnchorPoint = Vector2.new(0.5, 0)
						icon.Position = UDim2.new(0.5, 0, 0, 8)
						icon.Parent = cell
						Util.text({
							Text = string.format("%s ×%d", string.gsub(eggName(eggType), " Egg$", ""), #byType[eggType]),
							TextXAlignment = Enum.TextXAlignment.Center,
							Position = UDim2.new(0, 4, 1, -48),
							Size = UDim2.new(1, -8, 0, 40),
							Parent = cell,
						})
						cell.Activated:Connect(function()
							local list = offerPayload(side("mine").items or {})
							if #list >= MAX then
								ctx:Toast(string.format("Up to %d items per side", MAX), "error")
								return
							end
							table.insert(list, { kind = "egg", id = byType[eggType][1] })
							close()
							setOffer(list)
						end)
					end
				end,
			})
		end

		local function addMenu()
			Dialog.show(ctx.UI.Top, {
				Title = "Add to your offer",
				Color = C.Purple,
				Size = Vector2.new(500, 240),
				Text = string.format("Monsters and eggs only, up to %d items.", MAX),
				Buttons = {
					{ Text = "Monster", Color = C.Blue, OnClick = addMonsters },
					{ Text = "Egg", Color = C.Orange, OnClick = addEgg },
				},
			})
		end

		local function removeItem(index: number)
			local list = offerPayload(side("mine").items or {})
			table.remove(list, index)
			setOffer(list)
		end

		local function showDetail(item)
			Dialog.show(ctx.UI.Top, {
				Title = if item.kind == "egg" then eggName(item.egg) else (item.appearance and item.appearance.name or "Monster"),
				Color = C.Purple,
				Size = Vector2.new(520, 360),
				Build = function(content)
					if item.appearance then
						local icon = MonsterIcon.new(item.appearance, 130)
						icon.LayoutOrder = 1
						icon.Parent = content
						Util.tagChips(item.appearance, content, 2)
					else
						local icon = MonsterIcon.egg(item.egg or "meadow", 130)
						icon.LayoutOrder = 1
						icon.Parent = content
						Util.text({
							Text = "Unhatched egg. The rarity is rolled when it hatches.",
							TextXAlignment = Enum.TextXAlignment.Center,
							AutomaticSize = Enum.AutomaticSize.Y,
							Size = UDim2.new(1, 0, 0, 20),
							LayoutOrder = 2,
							Parent = content,
						})
					end
				end,
			})
		end

		-- Tiles ---------------------------------------------------------------------------------

		local function tile(parent: Instance, item, order: number, onTap)
			local ap = item and item.appearance
			local border = if ap then Theme.Rarity(ap.rarity or 1) else C.Line
			local cell = New("TextButton", {
				Name = "Tile" .. order,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = if item then C.Card else C.Panel,
				BackgroundTransparency = if item then 0 else 0.3,
				LayoutOrder = order,
				Parent = parent,
			}, { Create.Corner(Theme.Radius.Card), Create.Stroke(if item then 3 else 2, border) })
			if onTap then
				cell.Activated:Connect(onTap)
			end
			if not item then
				return cell
			end
			local lines
			if ap then
				local icon = MonsterIcon.new(ap, 62)
				icon.AnchorPoint = Vector2.new(0.5, 0)
				icon.Position = UDim2.new(0.5, 0, 0, 4)
				icon.Parent = cell
				lines = Util.valueLines(ap)
			else
				local icon = MonsterIcon.egg(item.egg or "meadow", 62)
				icon.AnchorPoint = Vector2.new(0.5, 0)
				icon.Position = UDim2.new(0.5, 0, 0, 4)
				icon.Parent = cell
				lines = { { text = eggName(item.egg), color = C.Text }, { text = "Egg", color = C.TextMuted } }
			end
			for i, lineInfo in lines do
				if i > 4 then
					break
				end
				Util.text({
					Text = lineInfo.text,
					TextColor3 = lineInfo.color,
					TextSize = Theme.TextSize.Small,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextWrapped = false,
					Position = UDim2.fromOffset(2, 66 + (i - 1) * 20),
					Size = UDim2.new(1, -4, 0, 20),
					Parent = cell,
				})
			end
			return cell
		end

		-- Drawing -----------------------------------------------------------------------------

		local function drawLobby(t)
			Util.clear(playerList)
			Util.clear(statusBody)
			local status = t.status or "none"
			local partner = if type(t.partner) == "table" then t.partner else nil
			local others = {}
			for _, p in Players:GetPlayers() do
				if p ~= ctx.Player then
					table.insert(others, p)
				end
			end
			table.sort(others, function(a, b)
				return a.DisplayName < b.DisplayName
			end)
			if #others == 0 then
				Util.text({
					Text = "Nobody else is on this server yet.",
					TextColor3 = C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, 0, 0, 60),
					Parent = playerList,
				})
			end
			for i, p in others do
				local row = New("Frame", {
					BackgroundColor3 = C.PanelDeep,
					Size = UDim2.new(1, -4, 0, 58),
					LayoutOrder = i,
					Parent = playerList,
				}, { Create.Corner(10) })
				Util.text({
					Text = p.DisplayName,
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body,
					Position = UDim2.fromOffset(12, 4),
					Size = UDim2.new(1, -170, 0, 26),
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextWrapped = false,
					Parent = row,
				})
				Util.text({
					Text = "@" .. p.Name,
					TextColor3 = C.TextMuted,
					Position = UDim2.fromOffset(12, 30),
					Size = UDim2.new(1, -170, 0, 22),
					Parent = row,
				})
				local waiting = partner ~= nil and partner.userId == p.UserId and (status == "outgoing" or status == "pending")
				local button = Button.new({
					Text = if waiting then "Waiting…" else "Request",
					Color = C.Purple,
					Size = UDim2.fromOffset(140, 46),
					TextSize = Theme.TextSize.Body,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Disabled = status ~= "none",
					Parent = row,
				})
				button:SetOnClick(function()
					local ok = Util.requestOnce(ctx, "Trade.Request", { target = p.UserId })
					if ok then
						ctx:Toast("Trade request sent to " .. p.DisplayName, "success")
					end
				end)
			end

			local function line(text, order, props)
				local p = {
					Text = text,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(1, 0, 0, 20),
					LayoutOrder = order,
					Parent = statusBody,
				}
				for k, v in props or {} do
					p[k] = v
				end
				return Util.text(p)
			end
			local name = if partner then partner.name or "Someone" else "Someone"
			if status == "outgoing" or status == "pending" then
				line(
					string.format("Waiting for %s to answer…", name),
					1,
					{ Font = Theme.Fonts.Display, TextSize = Theme.TextSize.Body + 2 }
				)
				line(string.format("Requests expire after %d seconds.", TradeConfig.requestTimeout), 2, { TextColor3 = C.TextMuted })
				Button.new({
					Text = "Cancel request",
					Color = C.Red,
					Size = UDim2.fromOffset(240, 54),
					LayoutOrder = 3,
					Parent = statusBody,
					OnClick = function()
						Util.requestOnce(ctx, "Trade.Cancel")
					end,
				})
			elseif status == "incoming" then
				line(string.format("%s wants to trade!", name), 1, { Font = Theme.Fonts.Display, TextSize = Theme.TextSize.Body + 2 })
				local row = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 56),
					LayoutOrder = 2,
					Parent = statusBody,
				}, { Create.List("x", 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
				local from = partner and partner.userId
				Button.new({
					Text = "Accept",
					Color = C.Green,
					Size = UDim2.fromOffset(150, 54),
					LayoutOrder = 1,
					Parent = row,
					OnClick = function()
						if from then
							Util.requestOnce(ctx, "Trade.Respond", { from = from, accept = true })
						end
					end,
				})
				Button.new({
					Text = "Decline",
					Color = C.Red,
					Size = UDim2.fromOffset(150, 54),
					LayoutOrder = 2,
					Parent = row,
					OnClick = function()
						if from then
							Util.requestOnce(ctx, "Trade.Respond", { from = from, accept = false })
						end
					end,
				})
			else
				line("Pick a player to send a trade request.", 1, { Font = Theme.Fonts.Display, TextSize = Theme.TextSize.Body + 1 })
				line(string.format("• Up to %d monsters and eggs per side. No currency.", MAX), 2)
				line("• Both players press Ready, then Confirm starts a short countdown.", 3)
				line("• Any change resets both sides. Check every tag before you confirm.", 4)
				line(
					string.format(
						"Trading unlocks at Ranch Level %d after %d minutes of play.",
						Util.unlockLevel(TradeConfig.unlock),
						math.floor(TradeConfig.minPlaySeconds / 60)
					),
					5,
					{ TextColor3 = C.TextMuted }
				)
			end
			if not Util.unlocked(ctx, TradeConfig.unlock) then
				Util.lockOverlay(playersCard, Util.unlockText(TradeConfig.unlock))
			end
		end

		local countdownStop = nil
		local function drawTrade(t)
			local mine, theirs = side("mine"), side("theirs")
			local partner = if type(t.partner) == "table" then t.partner else { name = "Partner" }
			panel:SetTitle("Trade with " .. (partner.name or "Partner"))
			mineCol.header.Text = "You"
			theirsCol.header.Text = partner.name or "Partner"
			local function badge(col, s)
				col.badge.Visible = s.ready == true or s.confirmed == true
				local label = col.badge:FindFirstChildOfClass("TextLabel")
				if label then
					label.Text = if s.confirmed then "✓ Confirmed" else "✓ Ready"
				end
			end
			badge(mineCol, mine)
			badge(theirsCol, theirs)

			Util.clear(mineCol.grid)
			local items = mine.items or {}
			for i = 1, MAX do
				local item = items[i]
				local cell = tile(mineCol.grid, item, i, function()
					if item then
						removeItem(i)
					else
						addMenu()
					end
				end)
				if not item and i == #items + 1 then
					Create.Text({
						Text = "+",
						TextSize = 48,
						TextColor3 = C.TextMuted,
						Stroke = false,
						Size = UDim2.fromScale(1, 0.8),
						Parent = cell,
					})
					Util.text({
						Text = "Add",
						TextColor3 = C.TextMuted,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.new(0, 0, 0.7, 0),
						Size = UDim2.new(1, 0, 0, 22),
						Parent = cell,
					})
				end
			end

			Util.clear(theirsCol.grid)
			local theirItems = theirs.items or {}
			for i = 1, MAX do
				local item = theirItems[i]
				local cell = tile(
					theirsCol.grid,
					item,
					i,
					if item
						then function()
							showDetail(item)
						end
						else nil
				)
				local sig = signature(item)
				if lastTheirs[i] ~= nil and lastTheirs[i] ~= sig then
					local stroke = cell:FindFirstChildOfClass("UIStroke")
					if stroke then
						stroke.Color = C.Orange
						stroke.Thickness = 5
					end
					Anim.pulse(cell, 0.15)
				end
				lastTheirs[i] = sig
			end

			local status = t.status
			local bothReady = mine.ready == true and theirs.ready == true
			readyButton:SetText(if mine.ready then "Not ready" else "Ready")
			readyButton:SetColor(if mine.ready then C.Gray else C.Orange)
			readyButton:SetDisabled(status == "countdown")
			if countdownStop then
				countdownStop()
				countdownStop = nil
			end
			if status == "countdown" then
				confirmButton:SetDisabled(true)
				local endsAt = t.endsAt or 0
				local function text(left)
					return string.format("Trading in %d…", math.max(0, math.ceil(left)))
				end
				confirmButton:SetText(text(endsAt - ctx:Now()))
				countdownStop = Widgets.Countdown(confirmButton.Label, function()
					return endsAt
				end, text)
			else
				confirmButton:SetText(if mine.confirmed then "Confirmed" else "Confirm")
				confirmButton:SetDisabled(not bothReady or mine.confirmed == true)
			end
		end

		readyButton:SetOnClick(function()
			Util.requestOnce(ctx, "Trade.SetReady", { ready = not side("mine").ready })
		end)
		confirmButton:SetOnClick(function()
			Util.requestOnce(ctx, "Trade.Confirm")
		end)
		cancelButton:SetOnClick(function()
			Util.requestOnce(ctx, "Trade.Cancel")
		end)

		local function draw()
			if not isOpen then
				return
			end
			local t = trade()
			local status = t.status or "none"
			local inTrade = status == "open" or status == "countdown"
			lobby.Visible = not inTrade
			tradeView.Visible = inTrade
			if inTrade then
				drawTrade(t)
			else
				lastTheirs = {}
				panel:SetTitle("Trade")
				if countdownStop then
					countdownStop()
					countdownStop = nil
				end
				drawLobby(t)
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				bag.clean()
				for _, path in { "session.Trade", "profile.Progression.level", "profile.Eggs" } do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				bag.add(Players.PlayerAdded:Connect(refresh))
				bag.add(Players.PlayerRemoving:Connect(function()
					task.defer(refresh)
				end))
				refresh()
			end,
			Close = function()
				isOpen = false
				bag.clean()
				if countdownStop then
					countdownStop()
					countdownStop = nil
				end
			end,
		}
	end,
}
