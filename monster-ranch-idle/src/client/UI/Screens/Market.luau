--[[
	Market screen (M3, update 1.3 · Market Day). Built against ARCHITECTURE §8: the Market and
	PriceHistory server systems answer Market.* and PriceHistory.Get; this screen only reads
	the Store and sends requests.

	Tabs:
	  Browse       listings from every server (Market.Browse): kind (all / monsters / eggs),
	               an item filter (species + rarity + variant, or egg type → Config.Market.ItemKey),
	               sort (cheapest / priciest / newest) and pages. Buy opens a confirm with the
	               price and the item's price chart (PriceHistory.Get) → Market.Buy { listing, price }.
	  Sell         pick a monster (Monsters pick mode, returnTo "Market") or an egg from storage,
	               type a price ("12k" works), see the tax and "you get" line, use the suggested
	               price (recent average from PriceHistory.Get) and, in a club, "Club only".
	               → Market.List { kind, id, price, club }.
	  My listings  Market.Mine: state, time left and Cancel (→ Market.Cancel), plus sales stats.
	  Club post    the club trading post (Market.Browse { club = true }); hidden without a club.

	The header shows "Collect mail" while session.Market.mail holds coins or items that could
	not be delivered yet (→ Market.Collect). The Market.MailCollected toast lives in the Hud
	controller, because this screen is only built the first time it opens.
	Open params: { tab? = "browse" | "sell" | "mine" | "club" }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Appearance = require(Shared.Logic.Appearance)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Icon = require(UI.Components.Icon)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)
local PriceChart = require(UI.Components.PriceChart)
local Util = require(script.Parent.Parts.Util)
local Dialog = require(script.Parent.Parts.Dialog)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Market

local MARKET = Color3.fromHex("#F2A93B")
local TEAL = Color3.fromHex("#2BA89A")
local ROW = 64
local SUGGEST_DAYS = 7

local SORTS = {
	{ id = "price", text = "Cheapest first" },
	{ id = "-price", text = "Priciest first" },
	{ id = "new", text = "Newest first" },
}
local STATE_TEXT = { open = "On sale", sold = "Sold", cancelled = "Cancelled", expired = "Expired" }
local STATE_COLOR = { open = C.Green, sold = C.Blue, cancelled = C.Gray, expired = C.Gray }

local Market = { Name = "Market" }

-- Helpers ------------------------------------------------------------------------------

local function eggName(eggType: string?): string
	local def = eggType and Config.Eggs.ById[eggType]
	return if def then def.name else "Egg"
end

local function variantName(variant: number?): string?
	local v = Config.Rarities.Variants[variant or 0]
	return if v and (variant or 0) > 0 then v.name else nil
end

-- "12000", "12,000", "12k", "1.5m" → whole coins (nil when it isn't a number).
function Market.parsePrice(text: string): number?
	local cleaned = string.lower(string.gsub(text or "", "[%s,_]", ""))
	local number, suffix = string.match(cleaned, "^(%d*%.?%d+)([kmb]?)$")
	local n = tonumber(number)
	if not n then
		return nil
	end
	local mult = if suffix == "k" then 1e3 elseif suffix == "m" then 1e6 elseif suffix == "b" then 1e9 else 1
	return math.floor(n * mult + 1e-6)
end

-- Recent average price, weighted by sales, from a PriceHistory.Get series. Falls back to the
-- last sale price.
function Market.suggest(days: { any }?, last: number?): number?
	local list = if type(days) == "table" then days else {}
	local newest = 0
	for _, d in list do
		newest = math.max(newest, tonumber(d.day) or 0)
	end
	local total, count = 0, 0
	for _, d in list do
		local n = tonumber(d.count) or 0
		if (tonumber(d.day) or 0) > newest - SUGGEST_DAYS and n > 0 and tonumber(d.avg) then
			total += d.avg * n
			count += n
		end
	end
	local price = if count > 0 then total / count else tonumber(last)
	if not price or price <= 0 then
		return nil
	end
	return math.clamp(math.floor(price + 0.5), Cfg.MinPrice, Cfg.MaxPrice)
end

-- Display name for a Listing's item (client view).
local function itemTitle(listing): string
	local item = type(listing.item) == "table" and listing.item or {}
	if listing.kind == "egg" then
		return eggName(item.egg or string.match(tostring(listing.key), "^e:(.+)$"))
	end
	local name = item.name or (item.appearance and item.appearance.name) or "Monster"
	local v = variantName(item.variant)
	return if v then v .. " " .. name else name
end

local function itemDetail(listing): string
	local item = type(listing.item) == "table" and listing.item or {}
	if listing.kind == "egg" then
		return "Unhatched egg · rarity rolls when it hatches"
	end
	local parts = { Theme.RarityName(item.rarity or 1) }
	table.insert(parts, "Lv " .. tostring(item.lv or 1) .. " " .. string.rep("★", math.clamp(item.stars or 1, 1, 5)))
	if item.weight then
		table.insert(parts, Format.weight(item.weight))
	end
	local muts = {}
	for _, id in item.muts or {} do
		local def = Config.Mutations.ById[id]
		table.insert(muts, if def then def.name else tostring(id))
	end
	if #muts > 0 then
		table.insert(parts, table.concat(muts, ", "))
	end
	return table.concat(parts, " · ")
end

local function itemIcon(listing, size: number): GuiObject
	local item = type(listing.item) == "table" and listing.item or {}
	if listing.kind == "egg" then
		local eggType = item.egg or string.match(tostring(listing.key), "^e:(.+)$")
		if eggType and Config.Eggs.ById[eggType] then
			return MonsterIcon.egg(eggType, size)
		end
		return Icon.new("egg", size)
	end
	if type(item.appearance) == "table" then
		local ok, icon = pcall(MonsterIcon.new, item.appearance, size)
		if ok and icon then
			return icon
		end
	end
	return Icon.new("star", size)
end

local function loadError(err): string
	if err == "TooFast" then
		return "Slow down a little, then Refresh."
	elseif err == "NotAvailable" or err == "UnknownAction" then
		return "The market is not open yet."
	end
	return StoreKit.errorText(err)
end

local function textBox(props)
	return New("TextBox", {
		Name = props.Name,
		Text = "",
		PlaceholderText = props.Placeholder,
		ClearTextOnFocus = false,
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Body + 2,
		TextColor3 = C.Text,
		PlaceholderColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = C.Card,
		Size = props.Size,
		Position = props.Position,
		Parent = props.Parent,
	}, { Create.Corner(Theme.Radius.Button), Create.Stroke(Theme.Stroke.Button), Create.Padding(0, 12, 0, 12) })
end

-- Build --------------------------------------------------------------------------------

function Market.Build(ctx)
	local store = ctx.Store
	local panel = Panel.new({
		Title = "Market",
		Color = MARKET,
		Size = UDim2.fromOffset(1000, 500),
		OnClose = function()
			ctx.Router:Close("Market")
		end,
	})
	local body = panel.Body

	local isOpen = false
	local tab = "browse"
	local render, loadList, reloadList
	local generation = 0 -- bumps on every list load so late answers never draw over newer ones
	local filter = { kind = nil, key = nil, label = nil, sort = "price" }
	local page = 1
	local more = false
	local chosen = nil -- sell tab: { kind, id }
	local clubOnly = false
	local sellHistory = { key = nil, days = nil, last = nil, suggest = nil }

	local function clubView()
		local s = store:Get("session.Clubs")
		return if type(s) == "table" and type(s.club) == "table" then s.club else nil
	end

	local function mail(): (number, number)
		local m = StoreKit.tbl(store, "session.Market").mail
		if type(m) ~= "table" then
			return 0, 0
		end
		local items = if type(m.items) == "table" then #m.items else (tonumber(m.items) or 0)
		return tonumber(m.coins) or 0, items
	end

	-- Header: mailbox ---------------------------------------------------------------------

	local mailButton = Button.new({
		Name = "CollectMail",
		Text = "Collect mail",
		Color = C.Green,
		Size = UDim2.fromOffset(190, 44),
		TextSize = Theme.TextSize.Small + 1,
		Icon = Icon.new("coin", 24),
		LayoutOrder = 1,
		Parent = panel.HeaderRight,
	})
	mailButton:SetVisible(false)
	mailButton:SetOnClick(function()
		local ok, res = Util.requestOnce(ctx, "Market.Collect")
		if ok and type(res) == "table" then
			local got = {}
			if (tonumber(res.coins) or 0) > 0 then
				table.insert(got, "+" .. Format.short(res.coins) .. " coins")
			end
			local items = if type(res.items) == "table" then #res.items else 0
			if items > 0 then
				table.insert(got, string.format("%d item%s", items, if items == 1 then "" else "s"))
			end
			if #got > 0 then
				ctx:Toast("Mail collected: " .. table.concat(got, " and "), "reward")
				ctx:Sound("CoinCollect")
			end
			if (tonumber(res.left) or 0) > 0 then
				ctx:Toast(string.format("%d item%s still waiting. Make room first.", res.left, if res.left == 1 then "" else "s"), "info")
			end
		end
	end)

	-- Tabs --------------------------------------------------------------------------------

	local tabs = Widgets.Tabs({
		Tabs = {
			{ id = "browse", text = "Browse", width = 140 },
			{ id = "sell", text = "Sell", width = 120 },
			{ id = "mine", text = "My listings", width = 160 },
			{ id = "club", text = "Club post", width = 150 },
		},
		Selected = tab,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = body,
		OnChanged = function(id)
			if id ~= tab then
				tab = id
				page = 1
				render()
			end
		end,
	})
	local clubTabButton = nil
	for _, child in tabs.Root:GetChildren() do
		if child:IsA("GuiButton") and child.LayoutOrder == 4 then
			clubTabButton = child
		end
	end

	local pages = New("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		Parent = body,
	})

	-- ─── Browse / Club post ──────────────────────────────────────────────────────────────

	local browse = New("Frame", { Name = "Browse", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = pages })
	local filterRow = New("Frame", {
		Name = "Filters",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = browse,
	}, { Create.List("x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })

	local kindTabs = Widgets.Tabs({
		Tabs = {
			{ id = "all", text = "All", width = 80 },
			{ id = "monster", text = "Monsters", width = 120 },
			{ id = "egg", text = "Eggs", width = 90 },
		},
		Selected = "all",
		Size = UDim2.fromOffset(310, 44),
		Parent = filterRow,
		OnChanged = function(id)
			local kind = if id == "all" then nil else id
			if kind ~= filter.kind then
				filter.kind = kind
				filter.key, filter.label = nil, nil
				page = 1
				render()
			end
		end,
	})
	kindTabs.Root.LayoutOrder = 1

	local filterButton = Button.new({
		Name = "ItemFilter",
		Text = "Any item",
		Color = C.Blue,
		Size = UDim2.fromOffset(220, 40),
		TextSize = Theme.TextSize.Small + 1,
		LayoutOrder = 2,
		Parent = filterRow,
	})
	local sortButton = Button.new({
		Name = "Sort",
		Text = SORTS[1].text,
		Color = C.Purple,
		Size = UDim2.fromOffset(170, 40),
		TextSize = Theme.TextSize.Small + 1,
		LayoutOrder = 3,
		Parent = filterRow,
	})
	sortButton:SetOnClick(function()
		local index = 1
		for i, s in SORTS do
			if s.id == filter.sort then
				index = i
			end
		end
		filter.sort = SORTS[index % #SORTS + 1].id
		page = 1
		render()
	end)

	local browseList = Widgets.List({
		Name = "Listings",
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -102),
		Padding = 6,
		Parent = browse,
	})

	local pager = New("Frame", {
		Name = "Pager",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 46),
		Parent = browse,
	})
	local browseNote = Util.text({
		Text = "",
		TextColor3 = C.TextMuted,
		Size = UDim2.new(1, -330, 1, 0),
		Parent = pager,
	})
	local pagerButtons = New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 320, 1, 0),
		Parent = pager,
	}, { Create.List("x", 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
	local prevButton = Button.new({
		Name = "PrevPage",
		Text = "◀",
		Color = C.Gray,
		Size = UDim2.fromOffset(56, 44),
		LayoutOrder = 1,
		Parent = pagerButtons,
	})
	local pageLabel = Util.text({
		Text = "Page 1",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(80, 44),
		LayoutOrder = 2,
		Parent = pagerButtons,
	})
	local nextButton = Button.new({
		Name = "NextPage",
		Text = "▶",
		Color = C.Gray,
		Size = UDim2.fromOffset(56, 44),
		LayoutOrder = 3,
		Parent = pagerButtons,
	})
	Button.new({
		Name = "Refresh",
		Text = "Refresh",
		Color = C.Blue,
		Size = UDim2.fromOffset(100, 44),
		TextSize = Theme.TextSize.Small + 1,
		LayoutOrder = 4,
		Parent = pagerButtons,
		OnClick = function()
			reloadList()
		end,
	})
	prevButton:SetOnClick(function()
		if page > 1 then
			page -= 1
			reloadList()
		end
	end)
	nextButton:SetOnClick(function()
		if more then
			page += 1
			reloadList()
		end
	end)

	-- ─── Sell ────────────────────────────────────────────────────────────────────────────

	local sell = New("Frame", { Name = "Sell", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = pages })
	local itemCard = Util.card({ Name = "Item", Title = "What to sell", Size = UDim2.new(0.4, -6, 1, 0), Parent = sell })
	local itemBody = New("Frame", {
		Name = "ItemBody",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 40),
		Size = UDim2.new(1, -24, 1, -48),
		Parent = itemCard,
	})
	local priceCard =
		Util.card({ Name = "Price", Title = "Price", Position = UDim2.new(0.4, 6, 0, 0), Size = UDim2.new(0.6, -6, 1, 0), Parent = sell })
	local priceBox = textBox({
		Name = "PriceBox",
		Placeholder = string.format("Coins (at least %s)", Format.short(Cfg.MinPrice)),
		Position = UDim2.fromOffset(14, 40),
		Size = UDim2.new(1, -250, 0, 46),
		Parent = priceCard,
	})
	local suggestButton = Button.new({
		Name = "Suggest",
		Text = "Suggested: —",
		Color = C.Blue,
		Size = UDim2.fromOffset(216, 46),
		TextSize = Theme.TextSize.Small + 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 40),
		Parent = priceCard,
	})
	local taxLabel = Util.text({
		Name = "Tax",
		Text = "",
		TextSize = Theme.TextSize.Small + 1,
		Position = UDim2.fromOffset(14, 92),
		Size = UDim2.new(1, -28, 0, 44),
		Parent = priceCard,
	})
	local sellChart = PriceChart.new({
		Position = UDim2.fromOffset(14, 140),
		Size = UDim2.new(1, -28, 0, 144),
		Parent = priceCard,
	})
	local clubButton = Button.new({
		Name = "ClubOnly",
		Text = "Club only: off",
		Color = C.Gray,
		Size = UDim2.fromOffset(190, 50),
		TextSize = Theme.TextSize.Small + 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -10),
		Parent = priceCard,
	})
	clubButton:SetOnClick(function()
		clubOnly = not clubOnly
		render()
	end)
	local listButton = Button.new({
		Name = "List",
		Text = "List for sale",
		Color = C.Green,
		Size = UDim2.fromOffset(230, 50),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -10),
		Parent = priceCard,
	})
	local slotsLabel = Util.text({
		Name = "Slots",
		Text = "",
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -254, 1, -10),
		Size = UDim2.new(1, -470, 0, 50),
		Parent = priceCard,
	})

	-- ─── My listings ─────────────────────────────────────────────────────────────────────

	local mine = New("Frame", { Name = "Mine", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = pages })
	local mineSummary = Util.text({
		Name = "Summary",
		Text = "",
		TextSize = Theme.TextSize.Small + 1,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = mine,
	})
	local mailLine = Util.text({
		Name = "MailLine",
		Text = "",
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = mine,
	})
	local mineList = Widgets.List({
		Name = "MyListings",
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		Padding = 6,
		Parent = mine,
	})

	-- Shared rows ---------------------------------------------------------------------------

	local function message(list: Instance, text: string)
		Util.clear(list)
		Util.text({
			Name = "Message",
			Text = text,
			TextColor3 = C.TextMuted,
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -8, 0, 60),
			Parent = list,
		})
	end

	local function listingRow(list: Instance, listing, order: number)
		local row = New("Frame", {
			Name = "Listing_" .. tostring(listing.id),
			BackgroundColor3 = if listing.mine then Color3.fromHex("#FFF1CC") else C.Card,
			Size = UDim2.new(1, -8, 0, ROW),
			LayoutOrder = order,
			Parent = list,
		}, { Create.Corner(10), Create.Stroke(2, C.Line, 0.3) })
		local icon = itemIcon(listing, ROW - 12)
		icon.Position = UDim2.fromOffset(8, 6)
		icon.Parent = row
		local title = Util.text({
			Name = "Title",
			Text = itemTitle(listing),
			Font = Theme.Fonts.Display,
			TextSize = Theme.TextSize.Body,
			Position = UDim2.fromOffset(ROW + 8, 6),
			Size = UDim2.new(1, -(ROW + 440), 0, 26),
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Parent = row,
		})
		if listing.club then
			title.Text = "[Club] " .. title.Text
		end
		Util.text({
			Name = "Detail",
			Text = itemDetail(listing),
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(ROW + 8, 34),
			Size = UDim2.new(1, -(ROW + 440), 0, 22),
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Parent = row,
		})
		local who = if listing.mine then "You" else tostring(listing.sellerName or "Someone")
		Util.text({
			Name = "Seller",
			Text = "by " .. who,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -290, 0, 6),
			Size = UDim2.fromOffset(140, 26),
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Parent = row,
		})
		local timeLabel = Util.text({
			Name = "TimeLeft",
			Text = "",
			TextColor3 = C.TextMuted,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -290, 0, 34),
			Size = UDim2.fromOffset(140, 22),
			Parent = row,
		})
		local expiresAt = tonumber(listing.expiresAt) or 0
		if listing.state == nil or listing.state == "open" then
			local function leftText(left: number): string
				return if left > 0 then Format.duration(left) .. " left" else "Expired"
			end
			timeLabel.Text = leftText(expiresAt - ctx:Now())
			Widgets.Countdown(timeLabel, function()
				return expiresAt
			end, leftText)
		else
			local chip = Widgets.Chip({
				Text = string.upper(STATE_TEXT[listing.state] or tostring(listing.state)),
				Color = STATE_COLOR[listing.state] or C.Gray,
				Parent = row,
			})
			chip.AnchorPoint = Vector2.new(1, 0)
			chip.Position = UDim2.new(1, -330, 0, 32)
		end
		local price = Widgets.Amount({ Icon = "coin", Text = Format.short(listing.price or 0), Parent = row })
		price.AnchorPoint = Vector2.new(1, 0.5)
		price.Position = UDim2.new(1, -140, 0.5, 0)
		return row
	end

	-- Buying ------------------------------------------------------------------------------

	local function confirmBuy(listing)
		local price = tonumber(listing.price) or 0
		local coins = StoreKit.balance(store, "coins")
		local chart
		local dialog = Dialog.show(ctx.UI.Top, {
			Title = "Buy " .. itemTitle(listing) .. "?",
			Color = MARKET,
			Size = Vector2.new(640, 440),
			Build = function(content)
				local head = New("Frame", {
					Name = "Item",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 72),
					LayoutOrder = 1,
					Parent = content,
				})
				local icon = itemIcon(listing, 68)
				icon.Parent = head
				Util.text({
					Text = itemDetail(listing),
					Position = UDim2.fromOffset(80, 0),
					Size = UDim2.new(1, -80, 0, 44),
					Parent = head,
				})
				Util.text({
					Text = string.format(
						"Sold by %s · %s",
						tostring(listing.sellerName or "someone"),
						Format.duration(math.max(0, (tonumber(listing.expiresAt) or 0) - ctx:Now())) .. " left"
					),
					TextColor3 = C.TextMuted,
					Position = UDim2.fromOffset(80, 44),
					Size = UDim2.new(1, -80, 0, 24),
					Parent = head,
				})
				chart = PriceChart.new({ Size = UDim2.new(1, 0, 0, 150), LayoutOrder = 2, Parent = content })
				chart:SetMessage("Loading prices…")
				Util.text({
					Text = string.format("Price %s coins · you have %s", Format.commas(price), Format.short(coins)),
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body,
					TextColor3 = if coins >= price then C.Text else C.Red,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, 0, 0, 26),
					LayoutOrder = 3,
					Parent = content,
				})
			end,
			Buttons = {
				{ Text = "Cancel", Color = C.Gray },
				{
					Text = "Buy · " .. Format.short(price),
					Color = C.Green,
					OnClick = function()
						task.spawn(function()
							local ok, res = Util.requestOnce(ctx, "Market.Buy", { listing = listing.id, price = price })
							if ok then
								local where = if type(res) == "table" and res.kind == "egg" then "egg storage" else "barn"
								ctx:Toast(string.format("You bought %s! It's in your %s.", itemTitle(listing), where), "success")
								ctx:Sound("CoinCollect")
							end
							reloadList()
						end)
					end,
				},
			},
		})
		if listing.key then
			task.spawn(function()
				local ok, res = ctx.Net:Request("PriceHistory.Get", { key = listing.key })
				if not dialog.IsOpen() or not chart then
					return
				end
				if ok and type(res) == "table" then
					chart:SetSeries(res.days)
				else
					chart:SetMessage("No price history right now")
				end
			end)
		end
	end

	local function confirmCancel(listing)
		Dialog.confirm(ctx.UI.Top, {
			Title = "Take " .. itemTitle(listing) .. " off the market?",
			Text = "It comes back to you, or to your mailbox if there's no room.",
			ConfirmText = "Take it back",
			ConfirmColor = C.Red,
			OnConfirm = function()
				local ok, res = Util.requestOnce(ctx, "Market.Cancel", { listing = listing.id })
				if ok then
					if type(res) == "table" and res.returned == false then
						ctx:Toast("No room, so it went to your mailbox.", "info")
					else
						ctx:Toast(itemTitle(listing) .. " is back home.", "success")
					end
				end
				reloadList()
			end,
		})
	end

	local function actionButton(row: Frame, listing)
		local isMine = listing.mine == true
		local open = listing.state == nil or listing.state == "open"
		local b = Button.new({
			Name = if isMine then "Cancel" else "Buy",
			Text = if isMine then "Cancel" else "Buy",
			Color = if isMine then C.Red else C.Green,
			Size = UDim2.fromOffset(120, 46),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Parent = row,
		})
		b:SetDisabled(not open)
		b:SetOnClick(function()
			if isMine then
				confirmCancel(listing)
			else
				confirmBuy(listing)
			end
		end)
	end

	-- Filter dialog -------------------------------------------------------------------------

	local function eggFilter()
		Dialog.show(ctx.UI.Top, {
			Title = "Which egg?",
			Color = MARKET,
			Size = Vector2.new(700, 380),
			Build = function(content, close)
				local grid = Widgets.Scroll({
					Name = "EggTypes",
					Cell = Vector2.new(120, 130),
					Padding = 8,
					Size = UDim2.new(1, 0, 1, 0),
					Parent = content,
				})
				grid.LayoutOrder = 2
				for i, def in Config.Eggs.List do
					local cell = New("TextButton", {
						Name = "Egg_" .. def.id,
						Text = "",
						AutoButtonColor = false,
						BackgroundColor3 = C.Card,
						LayoutOrder = i,
						Parent = grid,
					}, { Create.Corner(Theme.Radius.Card), Create.Stroke(if filter.key == "e:" .. def.id then 4 else 2.5, C.Ink) })
					local icon = MonsterIcon.egg(def.id, 70)
					icon.AnchorPoint = Vector2.new(0.5, 0)
					icon.Position = UDim2.new(0.5, 0, 0, 8)
					icon.Parent = cell
					Util.text({
						Text = def.name,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.new(0, 4, 1, -44),
						Size = UDim2.new(1, -8, 0, 40),
						Parent = cell,
					})
					cell.Activated:Connect(function()
						filter.kind = "egg"
						filter.key = Cfg.ItemKey("egg", { type = def.id })
						filter.label = def.name
						page = 1
						close()
						render()
					end)
				end
			end,
			Buttons = {
				{
					Text = "Any egg",
					Color = C.Gray,
					OnClick = function()
						filter.key, filter.label = nil, nil
						page = 1
						render()
					end,
				},
			},
		})
	end

	local function monsterFilter()
		local draft = { line = nil, rarity = 1, variant = 0 }
		if filter.key then
			local line, rarity, variant = string.match(filter.key, "^m:([^:]+):(%d+):(%d+)$")
			if line then
				draft = { line = line, rarity = tonumber(rarity) or 1, variant = tonumber(variant) or 0 }
			end
		end
		Dialog.show(ctx.UI.Top, {
			Title = "Which monster?",
			Color = MARKET,
			Size = Vector2.new(800, 450),
			Build = function(content)
				local refreshers = {}
				local function refreshAll()
					for _, fn in refreshers do
						fn()
					end
				end
				local function chipRow(name: string, order: number, entries, get, set)
					local row = New("Frame", {
						Name = name,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 42),
						LayoutOrder = order,
						Parent = content,
					}, { Create.List("x", 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
					for i, entry in entries do
						local b = Button.new({
							Name = name .. "_" .. tostring(entry.value),
							Text = entry.text,
							Color = entry.color,
							Size = UDim2.fromOffset(entry.width or 118, 40),
							TextSize = Theme.TextSize.Small,
							LayoutOrder = i,
							Parent = row,
							OnClick = function()
								set(entry.value)
								refreshAll()
							end,
						})
						table.insert(refreshers, function()
							local stroke = b.Root:FindFirstChildOfClass("UIStroke")
							if stroke then
								stroke.Color = if get() == entry.value then C.Gold else C.Ink
								stroke.Thickness = if get() == entry.value then 4 else Theme.Stroke.Button
							end
						end)
					end
				end
				local rarities = {}
				for i in Config.Rarities.List do
					table.insert(rarities, { value = i, text = Theme.RarityName(i), color = Theme.Rarity(i) })
				end
				chipRow("Rarity", 2, rarities, function()
					return draft.rarity
				end, function(v)
					draft.rarity = v
				end)
				local variants = {}
				for v = 0, 2 do
					local def = Config.Rarities.Variants[v]
					table.insert(variants, {
						value = v,
						text = if def then def.name else tostring(v),
						color = if v == 1 then Color3.fromHex("#E0A915") elseif v == 2 then C.Pink else C.Gray,
					})
				end
				chipRow("Variant", 3, variants, function()
					return draft.variant
				end, function(v)
					draft.variant = v
				end)
				local grid = Widgets.Scroll({
					Name = "Species",
					Cell = Vector2.new(86, 100),
					Padding = 6,
					Size = UDim2.new(1, 0, 1, -100),
					Parent = content,
				})
				grid.LayoutOrder = 4
				for i, line in Config.Species.Lines do
					local cell = New("TextButton", {
						Name = "Line_" .. line.id,
						Text = "",
						AutoButtonColor = false,
						BackgroundColor3 = C.Card,
						LayoutOrder = i,
						Parent = grid,
					}, { Create.Corner(10), Create.Stroke(2, C.Ink) })
					local ok, ap = pcall(Appearance.Preview, line.id, 1)
					if ok and ap then
						local icon = MonsterIcon.new(ap, 58)
						icon.AnchorPoint = Vector2.new(0.5, 0)
						icon.Position = UDim2.new(0.5, 0, 0, 4)
						icon.Parent = cell
					end
					Util.text({
						Text = if ok and ap then ap.name else line.id,
						TextSize = Theme.TextSize.Tiny + 1,
						TextXAlignment = Enum.TextXAlignment.Center,
						TextTruncate = Enum.TextTruncate.AtEnd,
						TextWrapped = false,
						Position = UDim2.new(0, 2, 1, -30),
						Size = UDim2.new(1, -4, 0, 26),
						Parent = cell,
					})
					local stroke = cell:FindFirstChildOfClass("UIStroke")
					table.insert(refreshers, function()
						if stroke then
							stroke.Color = if draft.line == line.id then C.Gold else C.Ink
							stroke.Thickness = if draft.line == line.id then 4 else 2
						end
					end)
					cell.Activated:Connect(function()
						draft.line = line.id
						refreshAll()
					end)
				end
				refreshAll()
			end,
			Buttons = {
				{
					Text = "Any monster",
					Color = C.Gray,
					OnClick = function()
						filter.key, filter.label = nil, nil
						page = 1
						render()
					end,
				},
				{
					Text = "Show these",
					Color = C.Green,
					OnClick = function()
						if not draft.line then
							ctx:Toast("Pick a species first", "info")
							return false
						end
						local ok, ap = pcall(Appearance.Preview, draft.line, 1)
						local name = if ok and ap then ap.name else draft.line
						local v = variantName(draft.variant)
						filter.kind = "monster"
						filter.key = Cfg.ItemKey("monster", { line = draft.line, rarity = draft.rarity, variant = draft.variant })
						filter.label = string.format("%s %s%s", Theme.RarityName(draft.rarity), if v then v .. " " else "", name)
						page = 1
						render()
						return nil
					end,
				},
			},
		})
	end

	filterButton:SetOnClick(function()
		if filter.kind == "egg" then
			eggFilter()
		else
			monsterFilter()
		end
	end)

	-- Selling -----------------------------------------------------------------------------

	local function storageEggs(): { [string]: { string } }
		local eggs = StoreKit.tbl(store, "profile.Eggs")
		local inSlot = {}
		for _, slot in StoreKit.asTable(eggs.slots) do
			if type(slot) == "table" and slot.egg then
				inSlot[slot.egg] = true
			end
		end
		local byType = {}
		for id, egg in StoreKit.asTable(eggs.list) do
			if not inSlot[id] and type(egg) == "table" and egg.type then
				byType[egg.type] = byType[egg.type] or {}
				table.insert(byType[egg.type], id)
			end
		end
		for _, ids in byType do
			table.sort(ids)
		end
		return byType
	end

	-- The chosen item's record, or nil once it is gone (listed, sold, hatched…).
	local function chosenRecord()
		if not chosen then
			return nil
		end
		if chosen.kind == "monster" then
			local m = StoreKit.monster(store, chosen.id)
			return if m and not m.busy and not m.locked then m else nil
		end
		local egg = StoreKit.tbl(store, "profile.Eggs.list")[chosen.id]
		if type(egg) ~= "table" then
			return nil
		end
		for _, slot in StoreKit.tbl(store, "profile.Eggs.slots") do
			if type(slot) == "table" and slot.egg == chosen.id then
				return nil
			end
		end
		return egg
	end

	local function loadHistory(key: string)
		sellHistory = { key = key, days = nil, last = nil, suggest = nil }
		sellChart:SetMessage("Loading prices…")
		local ok, res = ctx.Net:Request("PriceHistory.Get", { key = key })
		if sellHistory.key ~= key then
			return
		end
		if ok and type(res) == "table" then
			sellHistory.days = res.days
			sellHistory.last = res.last
			sellHistory.suggest = Market.suggest(res.days, res.last)
			sellChart:SetSeries(res.days)
		else
			sellChart:SetMessage("No price history right now")
		end
		if isOpen then
			render()
		end
	end

	local function choose(kind: string, id: string)
		chosen = { kind = kind, id = id }
		sellHistory = { key = nil }
		if isOpen and tab == "sell" then
			render()
		end
	end

	local function pickMonster()
		Util.pick(ctx, {
			title = "Pick a monster to sell",
			max = 1,
			filter = function(m)
				return not m.busy and not m.locked
			end,
			returnTo = "Market",
			returnParams = { tab = "sell" },
			onPick = function(ids)
				choose("monster", ids[1])
			end,
		})
	end

	local function pickEgg()
		local byType = storageEggs()
		local types = {}
		for eggType in byType do
			table.insert(types, eggType)
		end
		table.sort(types, function(a, b)
			local da, db = Config.Eggs.ById[a], Config.Eggs.ById[b]
			return (da and da.order or 99) < (db and db.order or 99)
		end)
		if #types == 0 then
			ctx:Toast("No eggs in storage. Eggs in incubators can't be sold.", "info")
			return
		end
		Dialog.show(ctx.UI.Top, {
			Title = "Sell an egg",
			Color = MARKET,
			Size = Vector2.new(660, 340),
			Build = function(content, close)
				local grid = Widgets.Scroll({
					Name = "StoredEggs",
					Cell = Vector2.new(130, 150),
					Padding = 10,
					Size = UDim2.new(1, 0, 1, 0),
					Parent = content,
				})
				grid.LayoutOrder = 2
				for i, eggType in types do
					local cell = New("TextButton", {
						Name = "Egg_" .. eggType,
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
						Text = string.format("%s ×%d", (string.gsub(eggName(eggType), " Egg$", "")), #byType[eggType]),
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.new(0, 4, 1, -48),
						Size = UDim2.new(1, -8, 0, 40),
						Parent = cell,
					})
					cell.Activated:Connect(function()
						close()
						choose("egg", byType[eggType][1])
					end)
				end
			end,
		})
	end

	listButton:SetOnClick(function()
		local record = chosenRecord()
		if not chosen or not record then
			ctx:Toast("Pick a monster or an egg first", "info")
			return
		end
		local price = Market.parsePrice(priceBox.Text)
		if not price or price < Cfg.MinPrice or price > Cfg.MaxPrice then
			ctx:Toast(string.format("Set a price from %s to %s coins", Format.short(Cfg.MinPrice), Format.short(Cfg.MaxPrice)), "error")
			return
		end
		local club = clubOnly and clubView() ~= nil
		local ok = Util.requestOnce(ctx, "Market.List", { kind = chosen.kind, id = chosen.id, price = price, club = club })
		if ok then
			ctx:Toast(if club then "Posted to your club's trading post!" else "Listed! Players on every server can buy it now.", "success")
			ctx:Sound("ButtonClick")
			chosen = nil
			priceBox.Text = ""
			tabs:Select("mine")
		end
	end)
	suggestButton:SetOnClick(function()
		if sellHistory.suggest then
			priceBox.Text = tostring(sellHistory.suggest)
		else
			ctx:Toast("No recent sales to go by. Pick your own price.", "info")
		end
	end)
	priceBox:GetPropertyChangedSignal("Text"):Connect(function()
		if #priceBox.Text > 24 then
			priceBox.Text = string.sub(priceBox.Text, 1, 24)
			return
		end
		if isOpen and tab == "sell" then
			render()
		end
	end)

	-- Redraws the item card only when the chosen item changes (the price box re-renders on
	-- every keystroke). Returns the item key, or nil when nothing is chosen.
	local drawnItem, drawnKey = nil, nil
	local function drawSellItem()
		local record = chosenRecord()
		if not record then
			chosen = nil
		end
		local sig = if record and chosen then chosen.kind .. ":" .. chosen.id else "none"
		if sig == drawnItem then
			return drawnKey
		end
		drawnItem = sig
		drawnKey = nil
		Util.clear(itemBody)
		if not record or not chosen then
			Util.text({
				Text = "Sell a monster or an egg to players on every server. It leaves your ranch until it sells or you take it back.",
				TextColor3 = C.TextMuted,
				Size = UDim2.new(1, 0, 0, 90),
				Parent = itemBody,
			})
			Button.new({
				Name = "PickMonster",
				Text = "Pick a monster",
				Color = C.Green,
				Size = UDim2.new(1, 0, 0, 54),
				Position = UDim2.fromOffset(0, 100),
				Parent = itemBody,
				OnClick = pickMonster,
			})
			Button.new({
				Name = "PickEgg",
				Text = "Pick an egg",
				Color = C.Pink,
				Size = UDim2.new(1, 0, 0, 54),
				Position = UDim2.fromOffset(0, 164),
				Parent = itemBody,
				OnClick = pickEgg,
			})
			return nil
		end
		local key
		if chosen.kind == "monster" then
			local ap = Util.appearance(record)
			if ap then
				local icon = MonsterIcon.new(ap, 110)
				icon.AnchorPoint = Vector2.new(0.5, 0)
				icon.Position = UDim2.fromScale(0.5, 0)
				icon.Parent = itemBody
				local holder = New("Frame", {
					Name = "TagHolder",
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(0, 146),
					Size = UDim2.new(1, 0, 0, 64),
					Parent = itemBody,
				})
				Util.tagChips(ap, holder)
			end
			Util.text({
				Text = if ap then ap.name else "Monster",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body + 2,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 114),
				Size = UDim2.new(1, 0, 0, 28),
				Parent = itemBody,
			})
			key = Cfg.ItemKey("monster", record)
		else
			local icon = MonsterIcon.egg(record.type, 110)
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.Position = UDim2.fromScale(0.5, 0)
			icon.Parent = itemBody
			Util.text({
				Text = eggName(record.type),
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body + 2,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 114),
				Size = UDim2.new(1, 0, 0, 28),
				Parent = itemBody,
			})
			key = Cfg.ItemKey("egg", record)
		end
		drawnKey = key
		Button.new({
			Name = "ChangeItem",
			Text = "Change",
			Color = C.Gray,
			Size = UDim2.fromOffset(140, 46),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Parent = itemBody,
			OnClick = function()
				chosen = nil
				sellHistory = { key = nil }
				priceBox.Text = ""
				render()
			end,
		})
		return key
	end

	local function drawSell()
		local key = drawSellItem()
		if key and sellHistory.key ~= key then
			task.spawn(loadHistory, key)
		elseif not key then
			sellHistory = { key = nil }
			sellChart:SetMessage("Pick an item to see its prices")
		end
		suggestButton:SetText(if sellHistory.suggest then "Suggested: " .. Format.short(sellHistory.suggest) else "Suggested: —")

		local inClub = clubView() ~= nil
		if not inClub then
			clubOnly = false
		end
		clubButton:SetVisible(inClub)
		clubButton:SetText(if clubOnly then "Club only: on" else "Club only: off")
		clubButton:SetColor(if clubOnly then TEAL else C.Gray)

		local price = Market.parsePrice(priceBox.Text)
		local tax = if clubOnly then Cfg.ClubTax else Cfg.Tax
		if not price then
			taxLabel.Text = string.format("Market tax %s. Type a price to see what you get.", Format.percent(tax))
			taxLabel.TextColor3 = C.TextMuted
		elseif price < Cfg.MinPrice or price > Cfg.MaxPrice then
			taxLabel.Text = string.format("Prices go from %s to %s coins.", Format.short(Cfg.MinPrice), Format.short(Cfg.MaxPrice))
			taxLabel.TextColor3 = C.Red
		else
			local proceeds = Cfg.Proceeds(price, clubOnly)
			taxLabel.Text = string.format(
				"Price %s · tax %s (−%s)\nYou get %s coins when it sells",
				Format.commas(price),
				Format.percent(tax),
				Format.short(price - proceeds),
				Format.commas(proceeds)
			)
			taxLabel.TextColor3 = C.Text
		end
		local listed = #StoreKit.asTable(StoreKit.tbl(store, "profile.Market").listings)
		slotsLabel.Text = string.format("%d / %d listed", listed, Cfg.MaxListings)
		listButton:SetDisabled(key == nil or price == nil or price < Cfg.MinPrice or price > Cfg.MaxPrice or listed >= Cfg.MaxListings)
	end

	-- Lists -------------------------------------------------------------------------------

	local function drawBrowse(listings)
		Util.clear(browseList)
		if #listings == 0 then
			message(
				browseList,
				if tab == "club"
					then "Nothing on your club's trading post yet. Post something from the Sell tab!"
					elseif filter.key then "Nobody is selling that right now."
					else "Nothing for sale yet. Be the first!"
			)
			return
		end
		for i, listing in listings do
			local row = listingRow(browseList, listing, i)
			actionButton(row, listing)
		end
	end

	local function drawMine(listings)
		Util.clear(mineList)
		if #listings == 0 then
			message(mineList, "You have nothing on the market. Sell something from the Sell tab!")
			return
		end
		table.sort(listings, function(a, b)
			local ao, bo = a.state == "open", b.state == "open"
			if ao ~= bo then
				return ao
			end
			return (tonumber(a.createdAt) or 0) > (tonumber(b.createdAt) or 0)
		end)
		for i, listing in listings do
			listing.mine = true
			local row = listingRow(mineList, listing, i)
			actionButton(row, listing)
		end
	end

	function loadList()
		if not isOpen then
			return
		end
		generation += 1
		local mineGen = generation
		if tab == "mine" then
			message(mineList, "Loading…")
			local ok, res = ctx.Net:Request("Market.Mine")
			if mineGen ~= generation or not isOpen or tab ~= "mine" then
				return
			end
			if ok and type(res) == "table" then
				drawMine(StoreKit.asTable(res.listings))
			else
				message(mineList, loadError(res))
			end
			return
		end
		if tab ~= "browse" and tab ~= "club" then
			return
		end
		local scope = tab
		message(browseList, "Loading…")
		prevButton:SetDisabled(true)
		nextButton:SetDisabled(true)
		pageLabel.Text = "Page " .. page
		local ok, res = ctx.Net:Request("Market.Browse", {
			kind = filter.kind,
			key = filter.key,
			sort = filter.sort,
			club = if scope == "club" then true else nil,
			page = page,
		})
		if mineGen ~= generation or not isOpen or tab ~= scope then
			return
		end
		if ok and type(res) == "table" then
			more = res.more == true
			page = tonumber(res.page) or page
			pageLabel.Text = "Page " .. page
			prevButton:SetDisabled(page <= 1)
			nextButton:SetDisabled(not more)
			drawBrowse(StoreKit.asTable(res.listings))
		else
			more = false
			prevButton:SetDisabled(page <= 1)
			message(browseList, loadError(res))
		end
	end

	-- Render ------------------------------------------------------------------------------

	local lockOverlay = nil
	local shownTab = nil

	local function drawChrome()
		local inClub = clubView() ~= nil
		if clubTabButton then
			clubTabButton.Visible = inClub
		end
		if tab == "club" and not inClub then
			tab = "browse"
			tabs:Select("browse") -- only recolours: OnChanged ignores the current tab
		end
		local coins, items = mail()
		mailButton:SetVisible(coins > 0 or items > 0)
		local parts = {}
		if coins > 0 then
			table.insert(parts, Format.short(coins) .. " coins")
		end
		if items > 0 then
			table.insert(parts, string.format("%d item%s", items, if items == 1 then "" else "s"))
		end
		mailLine.Text = if #parts > 0
			then "In your mailbox: " .. table.concat(parts, " and ") .. ". Make room, then Collect mail."
			else "Coins from sales and items that come back arrive here automatically."
		local m = StoreKit.tbl(store, "profile.Market")
		local stats = StoreKit.asTable(m.stats)
		mineSummary.Text = string.format(
			"%d / %d listed · sold %d · earned %s · bought %d",
			#StoreKit.asTable(m.listings),
			Cfg.MaxListings,
			tonumber(stats.sold) or 0,
			Format.short(tonumber(stats.earned) or 0),
			tonumber(stats.bought) or 0
		)
	end

	function render()
		if not isOpen then
			return
		end
		if lockOverlay then
			lockOverlay:Destroy()
			lockOverlay = nil
		end
		drawChrome()
		browse.Visible = tab == "browse" or tab == "club"
		sell.Visible = tab == "sell"
		mine.Visible = tab == "mine"
		local filterText = filter.label or (if filter.kind == "egg" then "Any egg" else "Any monster")
		filterButton:SetText(filterText)
		for _, s in SORTS do
			if s.id == filter.sort then
				sortButton:SetText(s.text)
			end
		end
		browseNote.Text = if tab == "club"
			then string.format("Club members only · %s tax", Format.percent(Cfg.ClubTax))
			else string.format("Listings last %s · sellers pay %s tax", Format.duration(Cfg.DurationSeconds), Format.percent(Cfg.Tax))
		kindTabs:Select(filter.kind or "all")

		if not Util.unlocked(ctx, Cfg.Unlock) then
			lockOverlay = Util.lockOverlay(body, Util.unlockText(Cfg.Unlock))
			shownTab = nil
			return
		end
		if tab == "sell" then
			drawSell()
			shownTab = tab
			return
		end
		local listKey = table.concat({ tab, tostring(filter.kind), tostring(filter.key), filter.sort, tostring(page) }, "|")
		if shownTab ~= listKey then
			shownTab = listKey
			task.spawn(loadList)
		end
	end

	-- kindTabs:Select calls OnChanged, which only re-renders on a real change.
	local refresh = Util.debounce(render)
	-- Coalesces reloads asked for in the same frame (an action's answer and the profile
	-- change it carries) into one request.
	reloadList = Util.debounce(function()
		if isOpen then
			task.spawn(loadList)
		end
	end)
	local listingsSig = ""
	local function listingsChanged()
		local sig = table.concat(StoreKit.asTable(StoreKit.tbl(store, "profile.Market").listings), ",")
		if sig ~= listingsSig then
			listingsSig = sig
			if tab == "mine" then
				reloadList()
			end
		end
		refresh()
	end

	local bag = Util.bag()
	return {
		Root = panel.Root,
		Open = function(params)
			isOpen = true
			shownTab = nil
			drawnItem = nil
			if type(params) == "table" and type(params.tab) == "string" then
				local wanted = params.tab
				if wanted == "browse" or wanted == "sell" or wanted == "mine" or wanted == "club" then
					tab = wanted
				end
			end
			tabs:Select(tab)
			bag.clean()
			for _, path in
				{
					"session.Market",
					"session.Clubs",
					"profile.Progression.level",
					"profile.Monsters.list",
					"profile.Eggs",
				}
			do
				bag.add(store:Observe(path, refresh))
			end
			listingsSig = table.concat(StoreKit.asTable(StoreKit.tbl(store, "profile.Market").listings), ",")
			bag.add(store:Observe("profile.Market", listingsChanged))
			render()
		end,
		Close = function()
			isOpen = false
			generation += 1
			bag.clean()
		end,
	}
end

return Market
