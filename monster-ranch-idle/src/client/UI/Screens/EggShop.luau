--[[
	EggShop (C2): the global-restock egg shop (mock-shop).

	  header      restock countdown (global.Shop.endsAt)
	  left        egg cards in Config.Eggs order: price, stock left (global.Shop.stock −
	              profile.Shop.bought), SOLD OUT, lock, Starlit pity / Royal lucky meter.
	              Event eggs only while their event runs (StoreKit.activeEvent); Starlit hidden when
	              session.Monetization.paidRandomAllowed == false; eggs without a price are
	              not sold here.
	  right       odds for the selected egg (always shown before buying): rarity bars,
	              variant odds (Lucky Hatcher aware), hatch time, possible species,
	              Buy ×1 / ×Max → Shop.BuyEgg
	  bottom-left free daily egg (rewarded ad) → Shop.ClaimFreeEgg
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
local Tiles = require(UI.Components.Tiles)
local StatBar = require(UI.Components.StatBar)

local New = Create.New
local C = Theme.Colors

local EggShop = { Name = "EggShop" }

local function sortedEggs()
	local list = table.clone(Config.Eggs.List)
	table.sort(list, function(a, b)
		return (a.order or 0) < (b.order or 0)
	end)
	return list
end

local function priceKey(egg): (string?, number)
	for key, amount in StoreKit.asTable(egg.price) do
		return key, amount
	end
	return nil, 0
end

function EggShop.Build(ctx)
	local store = ctx.Store
	local selected: string? = nil

	local panel = Panel.new({
		Title = "Egg Shop",
		Color = C.Pink,
		Size = UDim2.fromOffset(980, 490),
		OnClose = function()
			ctx.Router:Close("EggShop")
		end,
	})
	Create.Text({
		Text = "Restock in",
		TextSize = Theme.TextSize.Body,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		TextWrapped = false,
		LayoutOrder = 1,
		Parent = panel.HeaderRight,
	})
	local restock = Create.Text({
		Text = "--:--",
		TextSize = Theme.TextSize.Header,
		TextColor3 = C.Gold,
		Stroke = true,
		Size = UDim2.fromOffset(80, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
		Parent = panel.HeaderRight,
	})

	local grid = Widgets.Scroll({
		Size = UDim2.fromOffset(624, 332),
		Cell = Vector2.new(114, 184),
		Padding = 10,
		Parent = panel.Body,
	})

	-- Free daily egg (rewarded ad)
	local freeRow = Tiles.card({ Position = UDim2.fromOffset(0, 342), Size = UDim2.fromOffset(612, 58), Parent = panel.Body })
	local freeEggType = Config.Monetization.Ads.freeEgg and Config.Monetization.Ads.freeEgg.egg or "grove"
	local freeIcon = MonsterIcon.egg(freeEggType, 44)
	freeIcon.Position = UDim2.fromOffset(10, 7)
	freeIcon.Parent = freeRow
	local freeText = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Body,
		Position = UDim2.fromOffset(62, 0),
		Size = UDim2.new(1, -250, 1, 0),
		Parent = freeRow,
	})
	local freeButton = Button.new({
		Text = "▶ Free egg",
		Color = C.Orange,
		Size = UDim2.fromOffset(170, 46),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Parent = freeRow,
	})

	-- Odds panel
	local odds = Tiles.card({ Position = UDim2.fromOffset(636, 0), Size = UDim2.fromOffset(308, 400), Parent = panel.Body })
	local oddsList = Tiles.col({ Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 1, -80), Parent = odds }, 6)
	local buyRow = Tiles.row({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -20, 0, 54),
		Parent = odds,
	}, 8, Enum.HorizontalAlignment.Center)
	local buyIcon = Tiles.frame({ Size = UDim2.fromOffset(24, 24) })
	local buyOne =
		Button.new({ Text = "Buy", Color = C.Green, Size = UDim2.fromOffset(150, 52), Icon = buyIcon, LayoutOrder = 1, Parent = buyRow })
	local buyMax = Button.new({ Text = "×Max", Color = C.Orange, Size = UDim2.fromOffset(124, 52), LayoutOrder = 2, Parent = buyRow })

	-- State -------------------------------------------------------------------------

	local function eggCount(): number
		local n = 0
		for _ in StoreKit.tbl(store, "profile.Eggs.list") do
			n += 1
		end
		return n
	end

	local function visible(egg): boolean
		if not egg.price then
			return false
		end
		if egg.event and egg.event ~= StoreKit.activeEvent() then
			return false
		end
		if
			(egg.paidRandom or Config.Monetization.PaidRandomEggs[egg.id])
			and store:Get("session.Monetization.paidRandomAllowed") == false
		then
			return false
		end
		return true
	end

	-- Returns (left, inThisRestock). math.huge = unlimited.
	local function stockLeft(egg): (number, boolean)
		if egg.stock and egg.stock.unlimited then
			return math.huge, true
		end
		local shop = StoreKit.tbl(store, "global.Shop")
		local stock = tonumber(StoreKit.asTable(shop.stock)[egg.id])
		if not stock or stock == 0 then
			return 0, false
		end
		if stock < 0 then
			return math.huge, true
		end
		local mine = StoreKit.tbl(store, "profile.Shop")
		local bought = 0
		if mine.window == nil or mine.window == shop.window then
			bought = tonumber(StoreKit.asTable(mine.bought)[egg.id]) or 0
		end
		return math.max(0, stock - bought), true
	end

	local function maxBuy(egg): number
		local left = stockLeft(egg)
		local n = math.min(Config.Eggs.MaxBuyPerRequest, left, StoreKit.affordCount(store, egg.price, egg.event))
		n = math.min(n, Config.Economy.MaxEggs - eggCount())
		return math.max(0, n)
	end

	local function stockText(egg): string
		local left, inRestock = stockLeft(egg)
		if left == math.huge then
			return "Unlimited"
		elseif left > 0 then
			return string.format("%d left", left)
		end
		local chance = egg.stock and egg.stock.appearChance
		if not inRestock and chance and chance < 1 then
			return string.format("%s of restocks", Format.percent(chance))
		end
		return "Next restock"
	end

	local function meterText(egg): string?
		local pity = StoreKit.tbl(store, "profile.Eggs.pity")
		if egg.pity then
			return string.format("Pity %d / %d", tonumber(pity.starlit) or 0, egg.pity.count)
		elseif egg.luckyMeter then
			return string.format("Lucky %d / %d", tonumber(pity.royal) or 0, egg.luckyMeter.every)
		end
		return nil
	end

	local function buy(egg, amount: number)
		if amount < 1 then
			return
		end
		local ok, res = StoreKit.request(ctx, "Shop.BuyEgg", { egg = egg.id, amount = amount })
		if ok then
			local got = type(res) == "table" and type(res.eggs) == "table" and #res.eggs or amount
			ctx:Toast(string.format("Bought %d × %s", got, egg.name), "success")
			ctx.Bus:Publish("Hud.Flash", "Eggs")
		end
	end

	-- Rendering -------------------------------------------------------------------

	local refresh

	local function eggCard(egg, order: number)
		local locked = not StoreKit.isUnlocked(store, egg.unlock or "egg_meadow")
		local left = stockLeft(egg)
		local isSelected = selected == egg.id
		local card = Tiles.card({ Name = egg.id, LayoutOrder = order, Parent = grid })
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke and isSelected then
			stroke.Color = C.Pink
			stroke.Thickness = 5
		end
		local icon = MonsterIcon.egg(egg.id, 70)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 8)
		icon.Parent = card
		Tiles.label({
			Text = string.gsub(egg.name, " Egg$", ""),
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 80),
			Size = UDim2.new(1, 0, 0, 22),
			Parent = card,
		})
		local cost = Tiles.cost(egg.price, card, egg.event, { TextSize = Theme.TextSize.Body, Height = 24 })
		cost.AnchorPoint = Vector2.new(0.5, 0)
		cost.Position = UDim2.new(0.5, 0, 0, 104)
		Tiles.label({
			Text = stockText(egg),
			TextSize = Theme.TextSize.Small,
			TextColor3 = if left > 0 then C.TextMuted else C.Red,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(2, 130),
			Size = UDim2.new(1, -4, 0, 20),
			Parent = card,
		})
		local meter = meterText(egg)
		if meter then
			Tiles.label({
				Text = meter,
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.Purple,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(2, 152),
				Size = UDim2.new(1, -4, 0, 20),
				Parent = card,
			})
		elseif egg.event then
			local chip = Widgets.Chip({ Text = "EVENT", Color = C.Blue, Parent = card })
			chip.AnchorPoint = Vector2.new(0.5, 0)
			chip.Position = UDim2.new(0.5, 0, 0, 150)
		end
		if left <= 0 and not locked then
			local ribbon = New("Frame", {
				BackgroundColor3 = C.Red,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 44),
				Size = UDim2.new(1, 10, 0, 28),
				Rotation = -12,
				ZIndex = 10,
				Parent = card,
			}, { Create.Stroke(2) })
			Create.Text({ Text = "SOLD OUT", TextSize = Theme.TextSize.Body, Size = UDim2.fromScale(1, 1), ZIndex = 11, Parent = ribbon })
		end
		if locked then
			Tiles.lock(card, string.format("Lv %d", StoreKit.unlockLevel(egg.unlock)))
		end
		Tiles.tap(card, function()
			selected = egg.id
			refresh()
		end, 30)
	end

	local function renderOdds(egg)
		Tiles.clear(oddsList)
		Tiles.label({
			Text = egg.name .. " odds",
			TextSize = Theme.TextSize.Header - 2,
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = 1,
			Parent = oddsList,
		})
		for i, pct in egg.odds do
			if pct > 0 then
				StatBar.new({
					Label = Theme.RarityName(i),
					Color = Theme.Rarity(i),
					Value = pct / 100,
					Text = Format.percent(pct / 100, 1),
					LabelWidth = 86,
					ValueWidth = 50,
					Height = 22,
					LayoutOrder = 1 + i,
					Parent = oddsList,
				})
			end
		end
		local lucky = StoreKit.hasPass(store, "luckyHatcher")
		local chances = if lucky then Config.Rarities.LuckyVariantChance else Config.Rarities.VariantChance
		local pool = Config.Species.Pools[egg.pool] or {}
		local hatch = egg.hatchSeconds or 0
		local speed = math.clamp(StoreKit.num(store, "session.Eggs.speed"), 0, 0.75)
		local hatchText = Format.duration(hatch * (1 - speed))
		local notes = {
			string.format(
				"Golden %s · Rainbow %s%s",
				Format.percent(chances.golden, 2),
				Format.percent(chances.rainbow, 2),
				if lucky then " (Lucky)" else ""
			),
			string.format("Hatch time %s · %d species possible", hatchText, #pool),
		}
		if egg.forcedMutation and Config.Mutations.ById[egg.forcedMutation] then
			table.insert(notes, Config.Mutations.ById[egg.forcedMutation].name .. " mutation guaranteed")
		end
		if egg.pity then
			table.insert(notes, string.format("A %s or better within %d eggs", Theme.RarityName(egg.pity.minRarity), egg.pity.count))
		elseif egg.luckyMeter then
			table.insert(
				notes,
				string.format("Every %dth hatch is %s or better", egg.luckyMeter.every, Theme.RarityName(egg.luckyMeter.minRarity))
			)
		end
		Tiles.label({
			Text = table.concat(notes, "\n"),
			TextSize = Theme.TextSize.Small,
			TextColor3 = C.TextMuted,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, 0, 0, 20 * #notes),
			LayoutOrder = 20,
			Parent = oddsList,
		})
		local speciesRow = New("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 44),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 4,
			LayoutOrder = 21,
			Parent = oddsList,
		}, { Create.List("x", 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
		local codex = StoreKit.tbl(store, "profile.Monsters.codex")
		for i, lineId in pool do
			local icon
			if codex[lineId] then
				local ok, ap = pcall(Appearance.Preview, lineId, 1)
				icon = if ok then MonsterIcon.new(ap, 38) else MonsterIcon.silhouette(lineId, 38)
			else
				icon = MonsterIcon.silhouette(lineId, 38)
			end
			icon.LayoutOrder = i
			icon.Parent = speciesRow
		end

		local locked = not StoreKit.isUnlocked(store, egg.unlock or "egg_meadow")
		local key, amount = priceKey(egg)
		local left = stockLeft(egg)
		local max = maxBuy(egg)
		local iconKind = StoreKit.iconFor(StoreKit.costKey(key or "coins", egg.event))
		Tiles.clear(buyIcon)
		Icon.new(iconKind, 24).Parent = buyIcon
		buyOne:SetText(Format.short(amount))
		if locked then
			buyMax:SetText(string.format("Lv %d", StoreKit.unlockLevel(egg.unlock)))
		elseif left <= 0 then
			buyMax:SetText("Sold out")
		else
			buyMax:SetText(string.format("×%d", math.max(max, 1)))
		end
		local canBuy = not locked and left > 0 and max >= 1
		-- Stays tappable so a tap can explain why the egg can't be bought.
		buyOne:SetColor(if canBuy then C.Green else C.Gray)
		buyMax:SetDisabled(not canBuy or max < 2)
		buyOne:SetOnClick(function()
			if locked then
				ctx:Toast(StoreKit.lockText(egg.unlock), "info")
			elseif left <= 0 then
				ctx:Toast("Sold out. Check back after the restock!", "info")
			elseif not StoreKit.canAfford(store, egg.price, egg.event) then
				ctx:Toast("Not enough " .. (if key == "token" then "event tokens" else key or "coins"), "error")
			elseif eggCount() >= Config.Economy.MaxEggs then
				ctx:Toast("Your egg storage is full", "error")
			else
				buy(egg, 1)
			end
		end)
		buyMax:SetOnClick(function()
			buy(egg, maxBuy(egg))
		end)
	end

	local function renderFree()
		local now = ctx:Now()
		local def = Config.Eggs.ById[freeEggType]
		local claimedToday = StoreKit.num(store, "profile.Shop.freeEggDay", -1) == StoreKit.day(now)
		local left = StoreKit.adsLeft(store, "freeEgg", now)
		local available = Config.Flags.RewardedAds and not claimedToday and left > 0
		freeText.Text = if available
			then string.format("Free %s every day · watch a short ad", if def then def.name else "egg")
			else "Free egg claimed. Come back tomorrow!"
		freeButton:SetDisabled(not available)
		freeRow.Visible = Config.Flags.RewardedAds == true
	end

	function refresh()
		Tiles.clear(grid)
		local shown = {}
		for _, egg in sortedEggs() do
			if visible(egg) then
				table.insert(shown, egg)
			end
		end
		if not selected or not Config.Eggs.ById[selected] or not visible(Config.Eggs.ById[selected]) then
			selected = nil
			for _, egg in shown do
				if StoreKit.isUnlocked(store, egg.unlock or "egg_meadow") and (stockLeft(egg)) > 0 then
					selected = egg.id
					break
				end
			end
			selected = selected or (shown[1] and shown[1].id)
		end
		for i, egg in shown do
			eggCard(egg, i)
		end
		local egg = selected and Config.Eggs.ById[selected]
		odds.Visible = egg ~= nil
		if egg then
			renderOdds(egg)
		end
		renderFree()
	end

	freeButton:SetOnClick(function()
		local ok, res = StoreKit.request(ctx, "Shop.ClaimFreeEgg")
		if ok then
			local id = type(res) == "table" and res.egg
			local def = Config.Eggs.ById[id or freeEggType]
			ctx:Toast(string.format("Got a free %s!", if def then def.name else "egg"), "success")
			ctx.Bus:Publish("Hud.Flash", "Eggs")
		end
	end)

	local watch = StoreKit.watch(store, {
		"global.Shop",
		"profile.Shop",
		"profile.Eggs",
		"profile.Currency",
		"profile.Progression.level",
		"session.Monetization",
		"session.Eggs",
		"profile.Monetization",
		"profile.Monsters.codex",
	}, function()
		refresh()
	end)

	local stopCountdown
	return {
		Root = panel.Root,
		Open = function()
			watch.Start()
			if stopCountdown then
				stopCountdown()
			end
			stopCountdown = Widgets.Countdown(
				restock,
				function()
					local endsAt = tonumber(store:Get("global.Shop.endsAt"))
					if endsAt and endsAt > ctx:Now() then
						return endsAt
					end
					-- Restocks run on a fixed global clock; show the next one until the Shop replicates.
					return math.ceil(ctx:Now() / Config.Eggs.RestockSeconds) * Config.Eggs.RestockSeconds
				end,
				Format.clock,
				function()
					task.delay(1, watch.Refresh)
				end
			)
		end,
		Close = function()
			watch.Stop()
			if stopCountdown then
				stopCountdown()
				stopCountdown = nil
			end
		end,
	}
end

return EggShop
