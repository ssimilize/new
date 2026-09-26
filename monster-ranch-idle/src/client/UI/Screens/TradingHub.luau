--[[
	Trading Hub screen (update 3.0 · Year Two). One screen for both places:

	On the ranch (global.TradingHub.mode = "main"; opened from the Trading Hub portal):
	  what the hub is, a read-only preview of the Trade Board, and "Travel to the Trading
	  Hub" (TradingHub.Travel).
	In the hub (mode = "hub"; opened from the Trade Board or the Back to Ranch portal):
	  Board   ads from every hub server: offer icons, wants, note, poster and whether they
	          are on this server. Meet → TradingHub.Meet: a trade request right away when the
	          poster is here (Trade.Request), otherwise a teleport to their server.
	  My ad   up to MaxOffer monsters (Monsters pick mode), wanted tags, a preset note;
	          Post (TradingHub.Post) / Remove (TradingHub.Remove).
	  Header  "Back to ranch" (TradingHub.Return).

	Reads: global.TradingHub, session.TradingHub, profile.Monsters.list, profile.Progression.level.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.TradingHub

local function wantsText(wants): string
	local names = {}
	for _, id in wants or {} do
		local w = Cfg.WantsById[id]
		if w then
			table.insert(names, w.name)
		end
	end
	return if #names > 0 then "Wants: " .. table.concat(names, ", ") else "Wants: any offers"
end

return {
	Name = "TradingHub",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Trading Hub",
			Color = C.Blue,
			Size = UDim2.fromOffset(1000, 500),
			OnClose = function()
				ctx.Router:Close("TradingHub")
			end,
		})
		local backButton = Button.new({
			Name = "BackToRanch",
			Text = "Back to ranch",
			Color = C.Green,
			TextSize = Theme.TextSize.Small,
			Size = UDim2.fromOffset(190, 44),
			LayoutOrder = 1,
			Parent = panel.HeaderRight,
			OnClick = function()
				Util.requestOnce(ctx, "TradingHub.Return")
			end,
		})

		local isOpen = false
		local bag = Util.bag()
		local refresh
		local tab = "board"
		local draft = { ids = {}, wants = { "offers" }, note = 1 }

		local function hubState()
			return StoreKit.tbl(ctx.Store, "global.TradingHub")
		end
		local function isHub(): boolean
			return hubState().mode == "hub"
		end

		local tabs = Widgets.Tabs({
			Tabs = { { id = "board", text = "Trade Board" }, { id = "post", text = "My ad" } },
			Selected = tab,
			Parent = panel.Body,
			OnChanged = function(id)
				tab = id
				refresh()
			end,
		})
		local content = New("Frame", {
			Name = "HubContent",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 52),
			Size = UDim2.new(1, 0, 1, -52),
			Parent = panel.Body,
		})

		local function offerRow(offer, parent: Instance, size: number)
			local row = New("Frame", {
				Name = "Offer",
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset((size + 6) * Cfg.MaxOffer, size),
				Parent = parent,
			}, { Create.List("x", 6) })
			for i, item in offer or {} do
				local icon = nil
				if item.kind == "monster" and type(item.appearance) == "table" and Config.Species.ById[item.appearance.line] then
					icon = MonsterIcon.new(item.appearance, size)
				elseif item.kind == "egg" and Config.Eggs.ById[item.egg] then
					icon = Util.rewardIcon({ kind = "egg", id = item.egg, amount = 1 }, size)
				end
				if icon then
					icon.LayoutOrder = i
					icon.Parent = row
				end
			end
			return row
		end

		-- Board --------------------------------------------------------------------------------
		local function meet(ad)
			local ok, res = Util.requestOnce(ctx, "TradingHub.Meet", { ad = ad.id })
			if not ok or type(res) ~= "table" then
				return
			end
			if res.here then
				local sent = Util.requestOnce(ctx, "Trade.Request", { target = res.userId })
				if sent then
					ctx:Toast("Trade request sent to " .. tostring(ad.name), "success")
				end
			else
				ctx:Toast(string.format("Heading to %s's server…", tostring(ad.name)), "info")
			end
		end

		local function drawBoard(preview: boolean)
			local ads = hubState().ads or {}
			local list = Widgets.List({
				Name = "Ads",
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.new(1, 0, 1, if preview then -70 else -50),
				Padding = 8,
				Parent = content,
			})
			if #ads == 0 then
				Util.text({
					Text = "No ads yet. Be the first to post one!",
					TextColor3 = C.TextMuted,
					Size = UDim2.new(1, 0, 0, 40),
					Parent = list,
				})
			end
			for i, ad in ads do
				local card = New("Frame", {
					Name = "Ad" .. i,
					BackgroundColor3 = if ad.userId == ctx.Player.UserId then C.Gold else C.PanelDeep,
					Size = UDim2.new(1, -6, 0, 96),
					LayoutOrder = i,
					Parent = list,
				}, { Create.Corner(12) })
				local offer = offerRow(ad.offer, card, 72)
				offer.Position = UDim2.fromOffset(10, 12)
				Util.text({
					Text = string.format("%s%s", tostring(ad.name or "?"), if ad.here then " · on this server" else ""),
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body,
					Position = UDim2.fromOffset(330, 8),
					Size = UDim2.new(1, -520, 0, 26),
					Parent = card,
				})
				Util.text({
					Text = string.format("%s\n“%s”", wantsText(ad.wants), Cfg.Notes[ad.note] or Cfg.Notes[1]),
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					Position = UDim2.fromOffset(330, 36),
					Size = UDim2.new(1, -520, 0, 54),
					Parent = card,
				})
				if not preview and ad.userId ~= ctx.Player.UserId then
					Button.new({
						Name = "Meet",
						Text = if ad.here then "Trade" else "Meet",
						Color = if ad.here then C.Green else C.Blue,
						TextSize = Theme.TextSize.Small,
						Size = UDim2.fromOffset(160, 48),
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -12, 0.5, 0),
						Parent = card,
						OnClick = function()
							meet(ad)
						end,
					})
				end
			end
			local footer = New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, if preview then 64 else 44),
				Parent = content,
			}, { Create.List("x", 12, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
			if preview then
				Util.text({
					Text = "Traders from every server meet in the Trading Hub. Your monsters come with you.",
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					Size = UDim2.new(1, -360, 1, 0),
					LayoutOrder = 1,
					Parent = footer,
				})
				local unlocked = Util.unlocked(ctx, Cfg.Unlock)
				Button.new({
					Name = "TravelHub",
					Text = if unlocked then "Travel to the Trading Hub" else Util.unlockText(Cfg.Unlock),
					Color = if unlocked then C.Green else C.Gray,
					Disabled = not unlocked,
					TextSize = Theme.TextSize.Small,
					Size = UDim2.fromOffset(340, 58),
					LayoutOrder = 2,
					Parent = footer,
					OnClick = function()
						Util.requestOnce(ctx, "TradingHub.Travel")
					end,
				})
			else
				Button.new({
					Name = "RefreshBoard",
					Text = "Refresh",
					Color = C.Blue,
					TextSize = Theme.TextSize.Small,
					Size = UDim2.fromOffset(160, 42),
					Parent = footer,
					OnClick = function()
						Util.requestOnce(ctx, "TradingHub.Refresh")
					end,
				})
			end
		end

		-- My ad --------------------------------------------------------------------------------
		local function drawPost()
			local monsters = Util.monsters(ctx)
			local kept = {}
			for _, id in draft.ids do
				if monsters[id] then
					table.insert(kept, id)
				end
			end
			draft.ids = kept
			local mine = StoreKit.tbl(ctx.Store, "session.TradingHub").ad

			local left = Util.card({ Title = "Offering", Size = UDim2.new(0, 470, 1, 0), Parent = content })
			local offer = {}
			for _, id in draft.ids do
				table.insert(offer, { kind = "monster", appearance = Util.appearance(monsters[id]) })
			end
			local row = offerRow(offer, left, 96)
			row.Position = UDim2.fromOffset(16, 50)
			Button.new({
				Name = "PickOffer",
				Text = if #draft.ids > 0 then "Change monsters" else "Pick monsters",
				Color = C.Blue,
				TextSize = Theme.TextSize.Small,
				Size = UDim2.fromOffset(220, 48),
				Position = UDim2.fromOffset(16, 160),
				Parent = left,
				OnClick = function()
					Util.pick(ctx, {
						title = string.format("Offer up to %d monsters", Cfg.MaxOffer),
						max = Cfg.MaxOffer,
						filter = function(m)
							return not m.locked
						end,
						returnTo = "TradingHub",
						onPick = function(ids)
							draft.ids = ids
							tab = "post"
						end,
					})
				end,
			})
			Util.text({
				Name = "Note",
				Text = "“" .. (Cfg.Notes[draft.note] or Cfg.Notes[1]) .. "”",
				TextWrapped = true,
				Position = UDim2.fromOffset(16, 222),
				Size = UDim2.new(1, -32, 0, 30),
				Parent = left,
			})
			Button.new({
				Name = "NextNote",
				Text = "Change note",
				Color = C.Purple,
				TextSize = Theme.TextSize.Small,
				Size = UDim2.fromOffset(200, 44),
				Position = UDim2.fromOffset(16, 258),
				Parent = left,
				OnClick = function()
					draft.note = draft.note % #Cfg.Notes + 1
					refresh()
				end,
			})

			local right = Util.card({
				Title = string.format("Looking for (up to %d)", Cfg.MaxWants),
				Position = UDim2.fromOffset(480, 0),
				Size = UDim2.new(1, -480, 1, 0),
				Parent = content,
			})
			local grid = New("Frame", {
				Name = "Wants",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 44),
				Size = UDim2.new(1, -24, 0, 210),
				Parent = right,
			}, { New("UIGridLayout", { CellSize = UDim2.fromOffset(150, 44), CellPadding = UDim2.fromOffset(8, 8) }) })
			for i, w in Cfg.Wants do
				local on = table.find(draft.wants, w.id) ~= nil
				Button.new({
					Name = "Want_" .. w.id,
					Text = w.name,
					Color = if on then C.Orange else C.Gray,
					TextSize = Theme.TextSize.Small,
					Size = UDim2.fromOffset(150, 44),
					LayoutOrder = i,
					Parent = grid,
					OnClick = function()
						local at = table.find(draft.wants, w.id)
						if at then
							table.remove(draft.wants, at)
						elseif #draft.wants < Cfg.MaxWants then
							table.insert(draft.wants, w.id)
						else
							ctx:Toast(string.format("Pick up to %d", Cfg.MaxWants), "info")
						end
						refresh()
					end,
				})
			end
			local buttons = New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 12, 1, -10),
				Size = UDim2.new(1, -24, 0, 56),
				Parent = right,
			}, { Create.List("x", 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
			if mine then
				Button.new({
					Name = "RemoveAd",
					Text = "Remove ad",
					Color = C.Gray,
					TextSize = Theme.TextSize.Small,
					Size = UDim2.fromOffset(170, 50),
					LayoutOrder = 1,
					Parent = buttons,
					OnClick = function()
						Util.requestOnce(ctx, "TradingHub.Remove")
					end,
				})
			end
			Button.new({
				Name = "PostAd",
				Text = if mine then "Post again" else "Post ad",
				Color = if #draft.ids > 0 then C.Green else C.Gray,
				Disabled = #draft.ids == 0,
				TextSize = Theme.TextSize.Small,
				Size = UDim2.fromOffset(190, 50),
				LayoutOrder = 2,
				Parent = buttons,
				OnClick = function()
					local items = {}
					for _, id in draft.ids do
						table.insert(items, { kind = "monster", id = id })
					end
					local ok = Util.requestOnce(ctx, "TradingHub.Post", { items = items, wants = draft.wants, note = draft.note })
					if ok then
						ctx:Toast("Your ad is on the Trade Board!", "success")
						tab = "board"
						tabs:Select("board")
						refresh()
					end
				end,
			})
		end

		local function draw()
			if not isOpen then
				return
			end
			Util.clear(content)
			local hub = isHub()
			backButton.Root.Visible = hub
			tabs.Root.Visible = hub
			if not hub then
				content.Position = UDim2.fromOffset(0, 0)
				content.Size = UDim2.fromScale(1, 1)
				drawBoard(true)
				return
			end
			content.Position = UDim2.fromOffset(0, 52)
			content.Size = UDim2.new(1, 0, 1, -52)
			if tab == "post" then
				drawPost()
			else
				drawBoard(false)
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				bag.clean()
				for _, path in { "global.TradingHub", "session.TradingHub", "profile.Monsters.list", "profile.Progression.level" } do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				if tab == "post" then
					tabs:Select("post")
				end
				refresh()
			end,
			Close = function()
				isOpen = false
				bag.clean()
			end,
		}
	end,
}
