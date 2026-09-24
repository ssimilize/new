--[[
	Ranch (C2): ranch management. Params: { pen? }.

	  left nav    Pen 1..n · Buy next pen · Buildings · Feed Garden
	  pen tab     live jar (session.Ranch rates/caps, §6 formula) + Ranch.Collect; monsters in
	              the pen (tap → MonsterDetail, "To barn" → Ranch.Assign pen 0); Add monsters
	              (Monsters pick mode, barn monsters only → Ranch.Assign); capacity and jar
	              upgrades (Ranch.Upgrade); decor slots (owned decor from profile.Shop.decor →
	              Ranch.PlaceDecor, tap placed decor to take it back); theme picker
	              (Ranch.SetPenTheme; free or owned themes)
	  buy pen     next pen's unlock level and price → Ranch.BuyPen
	  buildings   barn storage, incubator speed and garden upgrades (Ranch.Upgrade)
	  garden      plots: plant a flavour (Ranch.Plant), timers, harvest one or all (Ranch.Harvest)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
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
local InsetPopup = require(UI.Components.InsetPopup)

local New = Create.New
local C = Theme.Colors
local Economy = Config.Economy

local Ranch = { Name = "Ranch" }

local function tierOf(value: any): number
	return math.max(1, math.floor(tonumber(value) or 1))
end

local function hoursText(seconds: number): string
	return Format.duration(seconds)
end

function Ranch.Build(ctx)
	local store = ctx.Store
	local selected = "pen1"
	local live = {} -- { pen, bar, button, rateLabel } for the open pen
	local plotTimers = {} -- { label, readyAt }

	local panel = Panel.new({
		Title = "Ranch",
		Color = C.Orange,
		Size = UDim2.fromOffset(980, 490),
		OnClose = function()
			ctx.Router:Close("Ranch")
		end,
	})
	local incomeLabel = Create.Text({
		Text = "",
		TextSize = Theme.TextSize.Body,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		TextWrapped = false,
		LayoutOrder = 1,
		Parent = panel.HeaderRight,
	})
	local nav = Widgets.List({ Size = UDim2.fromOffset(176, 400), Padding = 8, Parent = panel.Body })
	local content =
		Widgets.List({ Position = UDim2.fromOffset(186, 0), Size = UDim2.new(1, -186, 1, 0), Padding = 10, Parent = panel.Body })
	local watch
	local popup = InsetPopup.new({
		Parent = panel.Card,
		Title = "",
		Size = UDim2.fromOffset(520, 360),
		OnHide = function()
			-- Changes that arrived while the popup was open were held back; show them now.
			if watch then
				watch.Refresh()
			end
		end,
	})

	local refresh

	local function pens()
		return StoreKit.pens(store)
	end

	local function sectionTitle(text: string, order: number)
		return Tiles.label({
			Text = text,
			TextSize = Theme.TextSize.Header - 2,
			Size = UDim2.new(1, -10, 0, 30),
			LayoutOrder = order,
			Parent = content,
		})
	end

	-- A card with a title, a description and an action button on the right.
	local function actionCard(
		order: number,
		title: string,
		desc: string,
		buttonText: string,
		color: Color3,
		enabled: boolean,
		onClick: () -> ()
	)
		local card = Tiles.card({ Size = UDim2.new(1, -12, 0, 76), LayoutOrder = order, Parent = content })
		Tiles.label({
			Text = title,
			TextSize = Theme.TextSize.Body + 1,
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -230, 0, 26),
			Parent = card,
		})
		Tiles.label({
			Text = desc,
			TextSize = Theme.TextSize.Small,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(14, 36),
			Size = UDim2.new(1, -230, 0, 34),
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = card,
		})
		local b = Button.new({
			Text = buttonText,
			Color = color,
			TextSize = 18,
			Size = UDim2.fromOffset(200, 52),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Parent = card,
			OnClick = onClick,
		})
		b:SetDisabled(not enabled)
		return card, b
	end

	-- Popups ------------------------------------------------------------------------

	local function openThemePicker(penIndex: number)
		local pen = pens()[penIndex]
		if type(pen) ~= "table" then
			return
		end
		popup:SetTitle(string.format("Pen %d theme", penIndex))
		popup:SetSize(UDim2.fromOffset(520, 380))
		Tiles.clear(popup.Body)
		local list = Widgets.List({ Size = UDim2.fromScale(1, 1), Padding = 8, Parent = popup.Body })
		local owned = StoreKit.tbl(store, "profile.Shop.themes")
		for i, theme in Config.Decor.PenThemes do
			local has = theme.price == nil or owned[theme.id] == true
			if has or not theme.event or theme.event == Config.Flags.ActiveEvent then
				local row = Tiles.card({ Size = UDim2.new(1, -12, 0, 60), LayoutOrder = i, Parent = list })
				New("Frame", {
					BackgroundColor3 = Color3.fromHex(theme.ground),
					Position = UDim2.fromOffset(10, 10),
					Size = UDim2.fromOffset(40, 40),
					Parent = row,
				}, {
					Create.Corner(8),
					Create.Stroke(4, Color3.fromHex(theme.fence)),
				})
				Tiles.label({
					Text = theme.name,
					TextSize = Theme.TextSize.Body,
					Position = UDim2.fromOffset(60, 0),
					Size = UDim2.new(1, -220, 1, 0),
					Parent = row,
				})
				local inUse = (pen.theme or "wood") == theme.id
				Button.new({
					Text = if inUse then "In use" elseif has then "Use" else "Get in Store",
					Color = if inUse then C.Gray elseif has then C.Green else C.Pink,
					TextSize = 17,
					Size = UDim2.fromOffset(140, 46),
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Parent = row,
					OnClick = function()
						if inUse then
							return
						elseif not has then
							popup:Hide()
							if ctx.Router:Has("Store") then
								ctx.Router:Open("Store", { tab = "decor" })
							end
							return
						end
						local ok = StoreKit.request(ctx, "Ranch.SetPenTheme", { pen = penIndex, theme = theme.id })
						if ok then
							popup:Hide()
						end
					end,
				})
			end
		end
		popup:Show()
	end

	local function openDecorPicker(penIndex: number)
		popup:SetTitle(string.format("Decorate pen %d", penIndex))
		popup:SetSize(UDim2.fromOffset(520, 380))
		Tiles.clear(popup.Body)
		local list = Widgets.List({ Size = UDim2.fromScale(1, 1), Padding = 8, Parent = popup.Body })
		local any = false
		local decor = StoreKit.tbl(store, "profile.Shop.decor")
		for i, def in Config.Decor.List do
			local n = tonumber(decor[def.id]) or 0
			if n > 0 then
				any = true
				local row = Tiles.card({ Size = UDim2.new(1, -12, 0, 60), LayoutOrder = i, Parent = list })
				New("Frame", {
					BackgroundColor3 = Color3.fromHex(def.color),
					Position = UDim2.fromOffset(10, 10),
					Size = UDim2.fromOffset(40, 40),
					Parent = row,
				}, { Create.Corner(8), Create.Stroke(2) })
				Tiles.label({
					Text = string.format("%s ×%d · +%d mood", def.name, n, def.mood),
					TextSize = Theme.TextSize.Body,
					Position = UDim2.fromOffset(60, 0),
					Size = UDim2.new(1, -200, 1, 0),
					Parent = row,
				})
				Button.new({
					Text = "Place",
					Color = C.Green,
					Size = UDim2.fromOffset(110, 46),
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Parent = row,
					OnClick = function()
						local ok = StoreKit.request(ctx, "Ranch.PlaceDecor", { decor = def.id, pen = penIndex })
						if ok then
							popup:Hide()
						end
					end,
				})
			end
		end
		if not any then
			Tiles.label({
				Text = "You have no decor to place. Decor keeps monsters happy!",
				TextSize = Theme.TextSize.Body,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, -12, 0, 60),
				LayoutOrder = 1,
				Parent = list,
			})
			Button.new({
				Text = "Browse decor",
				Color = C.Pink,
				Size = UDim2.fromOffset(200, 48),
				LayoutOrder = 2,
				Parent = list,
				OnClick = function()
					popup:Hide()
					if ctx.Router:Has("Store") then
						ctx.Router:Open("Store", { tab = "decor" })
					else
						ctx:Toast("Coming soon", "info")
					end
				end,
			})
		end
		popup:Show()
	end

	local function openPlantPicker(plot: number)
		popup:SetTitle(string.format("Plant in plot %d", plot))
		popup:SetSize(UDim2.fromOffset(460, 330))
		Tiles.clear(popup.Body)
		local list = Tiles.col({ Size = UDim2.fromScale(1, 1), Parent = popup.Body }, 8)
		for i, flavor in Config.Food.List do
			local row = Tiles.frame({ Size = UDim2.new(1, 0, 0, 52), LayoutOrder = i, Parent = list })
			New("Frame", {
				BackgroundColor3 = Theme.Food(flavor.id),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.fromOffset(28, 28),
				Parent = row,
			}, { Create.Round(), Create.Stroke(2) })
			Tiles.label({
				Text = string.format("%s · +%d in %s", flavor.name, Economy.Garden.yield, Format.duration(Economy.Garden.growSeconds)),
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(38, 0),
				Size = UDim2.new(1, -160, 1, 0),
				Parent = row,
			})
			Button.new({
				Text = "Plant",
				Color = C.Green,
				Size = UDim2.fromOffset(110, 46),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Parent = row,
				OnClick = function()
					local ok = StoreKit.request(ctx, "Ranch.Plant", { plot = plot, flavor = flavor.id })
					if ok then
						popup:Hide()
					end
				end,
			})
		end
		popup:Show()
	end

	-- Tabs ---------------------------------------------------------------------------

	local function renderPen(penIndex: number)
		local pen = pens()[penIndex]
		if type(pen) ~= "table" then
			return
		end
		local now = ctx:Now()
		local ids = StoreKit.asTable(pen.monsters)
		local capacity = tonumber(pen.capacity) or Economy.Pens.startCapacity
		local jar, full, rate = StoreKit.jar(store, penIndex, now)
		local jarTier = tierOf(pen.jarTier)
		local capSeconds = if rate > 0 then full / rate else (Economy.JarTiers[jarTier] and Economy.JarTiers[jarTier].seconds or 3600)

		-- Jar card
		local jarCard = Tiles.card({ Size = UDim2.new(1, -12, 0, 104), LayoutOrder = 1, Parent = content })
		local themeDef = Config.Decor.PenThemeById[pen.theme or "wood"]
		Tiles.label({
			Text = string.format("Pen %d · %d / %d monsters", penIndex, #ids, capacity),
			TextSize = Theme.TextSize.Header - 2,
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.new(1, -250, 0, 30),
			Parent = jarCard,
		})
		local rateLabel = Tiles.label({
			Text = "",
			TextSize = Theme.TextSize.Small,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(14, 36),
			Size = UDim2.new(1, -250, 0, 20),
			Parent = jarCard,
		})
		rateLabel.Text = string.format(
			"%s coins/s · jar holds %s · %s",
			Format.short(math.floor(rate * 10) / 10),
			hoursText(capSeconds),
			if themeDef then themeDef.name else "Wooden Fence"
		)
		local jarBar = Widgets.Bar({
			Color = C.Coin,
			Value = if full > 0 then jar / full else 0,
			Text = Format.short(math.floor(jar)) .. " / " .. Format.short(math.floor(full)),
			Position = UDim2.fromOffset(14, 64),
			Size = UDim2.new(1, -250, 0, 24),
			Parent = jarCard,
		})
		local collectButton = Button.new({
			Text = "Collect",
			Color = C.Green,
			Icon = Icon.new("coin", 24),
			Size = UDim2.fromOffset(220, 56),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 8),
			Parent = jarCard,
			OnClick = function()
				local ok, res = StoreKit.request(ctx, "Ranch.Collect", { pen = penIndex })
				if ok then
					local coins = type(res) == "table" and tonumber(res.coins) or 0
					ctx:Sound("CoinCollect")
					ctx:Toast("+" .. Format.short(coins) .. " coins", "reward")
				end
			end,
		})
		Button.new({
			Text = "Theme",
			Color = C.Purple,
			TextSize = 17,
			Size = UDim2.fromOffset(104, 30),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -12, 1, -6),
			Parent = jarCard,
			OnClick = function()
				openThemePicker(penIndex)
			end,
		})
		live = { pen = penIndex, bar = jarBar, button = collectButton }

		-- Monsters in the pen
		sectionTitle("Monsters", 2)
		local grid = New("Frame", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -12, 0, 0),
			LayoutOrder = 3,
			Parent = content,
		}, { Create.Grid(Vector2.new(104, 156), 10) })
		for i, id in ids do
			local m = StoreKit.monster(store, id)
			if m then
				local cell = Tiles.frame({ Size = UDim2.fromOffset(104, 156), LayoutOrder = i, Parent = grid })
				local ok, ap = pcall(Appearance.Of, m)
				if ok then
					local card = MonsterIcon.card(ap, 104, Formulas.DisplayName(m))
					card.Parent = cell
					Tiles.tap(card, function()
						ctx.Router:Open("MonsterDetail", { id = id })
					end)
				end
				Button.new({
					Text = "To barn",
					Color = C.Gray,
					TextSize = 16,
					Size = UDim2.fromOffset(104, 44),
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale(0, 1),
					Parent = cell,
					OnClick = function()
						StoreKit.request(ctx, "Ranch.Assign", { id = id, pen = 0 })
					end,
				})
			end
		end
		if #ids < capacity then
			local add = Tiles.card({ Size = UDim2.fromOffset(104, 156), LayoutOrder = 999, Parent = grid, Color = C.PanelDeep })
			Create.Text({ Text = "+", TextSize = 56, TextColor3 = C.Green, Stroke = true, Size = UDim2.new(1, 0, 0, 96), Parent = add })
			Tiles.label({
				Text = "Add monsters",
				TextSize = Theme.TextSize.Small + 1,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 96),
				Size = UDim2.new(1, 0, 0, 44),
				Parent = add,
			})
			Tiles.tap(add, function()
				local room = capacity - #ids
				ctx.Router:Open("Monsters", {
					pick = {
						title = string.format("Add to Pen %d (up to %d)", penIndex, room),
						max = room,
						filter = function(m)
							return not m.busy and m.loc ~= "pen"
						end,
						returnTo = "Ranch",
						returnParams = { pen = penIndex },
						onPick = function(picked)
							local added = 0
							for _, id in picked do
								local ok = StoreKit.request(ctx, "Ranch.Assign", { id = id, pen = penIndex })
								if not ok then
									break
								end
								added += 1
							end
							if added > 0 then
								ctx:Toast(string.format("%d monsters moved into Pen %d", added, penIndex), "success")
							end
						end,
					},
				})
			end)
		end

		-- Upgrades
		sectionTitle("Upgrades", 4)
		local capCost = Economy.Pens.capacityCost[capacity]
		local maxed = capacity >= Economy.Pens.maxCapacity or not capCost
		actionCard(
			5,
			if maxed then "Capacity · max" else string.format("Capacity %d → %d", capacity, capacity + 1),
			"More monsters in a pen means more coins.",
			if maxed then "Maxed" else Format.short(capCost) .. " coins",
			C.Green,
			not maxed and StoreKit.canAfford(store, { coins = capCost or 0 }),
			function()
				StoreKit.request(ctx, "Ranch.Upgrade", { target = "capacity", pen = penIndex })
			end
		)
		local nextJar = Economy.JarTiers[jarTier + 1]
		actionCard(
			6,
			if nextJar
				then string.format("Coin jar %s → %s", hoursText(Economy.JarTiers[jarTier].seconds), hoursText(nextJar.seconds))
				else "Coin jar · max",
			"A bigger jar keeps filling longer while you're away.",
			if nextJar then Format.short(nextJar.cost) .. " coins" else "Maxed",
			C.Green,
			nextJar ~= nil and StoreKit.canAfford(store, { coins = nextJar.cost }),
			function()
				StoreKit.request(ctx, "Ranch.Upgrade", { target = "jar", pen = penIndex })
			end
		)

		-- Decor
		sectionTitle(string.format("Decor (%d slots)", Config.Decor.PerPen), 7)
		local decorRow = Tiles.row({ Size = UDim2.new(1, -12, 0, 96), LayoutOrder = 8, Parent = content }, 10)
		local placed = StoreKit.asTable(pen.decor)
		for slot = 1, Config.Decor.PerPen do
			local decorId = placed[slot]
			local def = decorId and Config.Decor.ById[decorId]
			local tile = Tiles.card({
				Size = UDim2.fromOffset(150, 92),
				LayoutOrder = slot,
				Parent = decorRow,
				Color = if def then C.Card else C.PanelDeep,
			})
			if def then
				New("Frame", {
					BackgroundColor3 = Color3.fromHex(def.color),
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 8),
					Size = UDim2.fromOffset(40, 40),
					Parent = tile,
				}, { Create.Corner(8), Create.Stroke(2) })
				Tiles.label({
					Text = def.name .. "\nTap to take back",
					TextSize = Theme.TextSize.Small - 1,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(4, 50),
					Size = UDim2.new(1, -8, 0, 38),
					Parent = tile,
				})
				Tiles.tap(tile, function()
					StoreKit.request(ctx, "Ranch.PlaceDecor", { decor = decorId, pen = 0 })
				end)
			else
				Create.Text({
					Text = "+",
					TextSize = 40,
					TextColor3 = C.Orange,
					Stroke = true,
					Size = UDim2.new(1, 0, 0, 56),
					Parent = tile,
				})
				Tiles.label({
					Text = "Place decor",
					TextSize = Theme.TextSize.Small,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(0, 56),
					Size = UDim2.new(1, 0, 0, 30),
					Parent = tile,
				})
				Tiles.tap(tile, function()
					openDecorPicker(penIndex)
				end)
			end
		end
	end

	local function renderBuyPen()
		local n = #pens() + 1
		if n > Economy.Pens.max then
			sectionTitle("All pens owned!", 1)
			return
		end
		local key = Economy.Pens.unlocks[n]
		local price = Economy.Pens.buyCost[n] or 0
		local unlocked = StoreKit.isUnlocked(store, key)
		sectionTitle(string.format("Pen %d", n), 1)
		actionCard(
			2,
			if unlocked then string.format("Build Pen %d", n) else StoreKit.lockText(key),
			string.format("Room for %d more monsters earning coins.", Economy.Pens.startCapacity),
			if unlocked then Format.short(price) .. " coins" else string.format("Lv %d", StoreKit.unlockLevel(key)),
			C.Green,
			unlocked and StoreKit.canAfford(store, { coins = price }),
			function()
				local ok, res = StoreKit.request(ctx, "Ranch.BuyPen")
				if ok then
					local pen = type(res) == "table" and tonumber(res.pen) or n
					ctx:Toast(string.format("Pen %d is ready!", pen), "success")
					selected = "pen" .. pen
					refresh()
				end
			end
		)
	end

	local function renderBuildings()
		local ranch = StoreKit.tbl(store, "profile.Ranch")
		local session = StoreKit.tbl(store, "session.Ranch")
		sectionTitle("Buildings", 1)
		Tiles.label({
			Text = string.format(
				"Monsters %d / %d · income %s coins/s",
				tonumber(session.used) or 0,
				tonumber(session.capacity) or 0,
				Format.short(math.floor((tonumber(session.income) or 0) * 10) / 10)
			),
			TextSize = Theme.TextSize.Body,
			TextColor3 = C.TextMuted,
			Size = UDim2.new(1, -12, 0, 26),
			LayoutOrder = 2,
			Parent = content,
		})
		local barnTier = tierOf(ranch.barnTier or ranch.barn)
		local nextBarn = Economy.Barn.capacity[barnTier + 1]
		local barnCost = Economy.Barn.cost[barnTier + 1]
		actionCard(
			3,
			string.format("Barn · holds %d", Economy.Barn.capacity[barnTier] or 0),
			if nextBarn then string.format("Upgrade to hold %d monsters.", nextBarn) else "Fully upgraded.",
			if nextBarn then Format.short(barnCost or 0) .. " coins" else "Maxed",
			C.Green,
			nextBarn ~= nil and StoreKit.canAfford(store, { coins = barnCost or 0 }),
			function()
				StoreKit.request(ctx, "Ranch.Upgrade", { target = "barn" })
			end
		)
		local incTier = tierOf(ranch.incubatorTier or ranch.incubatorSpeed)
		local speeds = Economy.Incubators.speedTiers
		local nextSpeed = speeds[incTier + 1]
		local incCost = Economy.Incubators.speedCost[incTier + 1]
		actionCard(
			4,
			string.format("Incubators · −%s hatch time", Format.percent(speeds[incTier] or 0)),
			if nextSpeed then string.format("Upgrade to −%s.", Format.percent(nextSpeed)) else "Fully upgraded.",
			if nextSpeed then Format.short(incCost or 0) .. " coins" else "Maxed",
			C.Green,
			nextSpeed ~= nil and StoreKit.canAfford(store, { coins = incCost or 0 }),
			function()
				StoreKit.request(ctx, "Ranch.Upgrade", { target = "incubatorSpeed" })
			end
		)
		local gardenTier = tierOf(StoreKit.asTable(ranch.garden).tier)
		local nextPlots = Economy.Garden.plots[gardenTier + 1]
		local gardenCost = Economy.Garden.cost[gardenTier + 1]
		local gardenOpen = StoreKit.isUnlocked(store, Economy.Garden.unlock)
		actionCard(
			5,
			string.format("Feed Garden · %d plots", Economy.Garden.plots[gardenTier] or 0),
			if not gardenOpen
				then StoreKit.lockText(Economy.Garden.unlock)
				elseif nextPlots then string.format("Upgrade to %d plots.", nextPlots)
				else "Fully upgraded.",
			if nextPlots then Format.short(gardenCost or 0) .. " coins" else "Maxed",
			C.Green,
			gardenOpen and nextPlots ~= nil and StoreKit.canAfford(store, { coins = gardenCost or 0 }),
			function()
				StoreKit.request(ctx, "Ranch.Upgrade", { target = "garden" })
			end
		)
	end

	local function renderGarden()
		if not StoreKit.isUnlocked(store, Economy.Garden.unlock) then
			sectionTitle("Feed Garden", 1)
			Tiles.label({
				Text = StoreKit.lockText(Economy.Garden.unlock) .. ". Grow food for your monsters while you're away.",
				TextSize = Theme.TextSize.Body,
				TextColor3 = C.TextMuted,
				Size = UDim2.new(1, -12, 0, 60),
				LayoutOrder = 2,
				Parent = content,
			})
			return
		end
		local garden = StoreKit.tbl(store, "profile.Ranch.garden")
		local plots = StoreKit.asTable(garden.plots)
		local count = #plots
		if count == 0 then
			count = Economy.Garden.plots[tierOf(garden.tier)] or 0
		end
		local now = ctx:Now()
		local header = Tiles.frame({ Size = UDim2.new(1, -12, 0, 52), LayoutOrder = 1, Parent = content })
		Tiles.label({ Text = "Feed Garden", TextSize = Theme.TextSize.Header - 2, Size = UDim2.new(1, -200, 1, 0), Parent = header })
		local anyReady = false
		for i = 1, count do
			local p = plots[i]
			if type(p) == "table" and p.flavor and (tonumber(p.readyAt) or math.huge) <= now then
				anyReady = true
			end
		end
		local harvestAll = Button.new({
			Text = "Harvest all",
			Color = C.Green,
			Size = UDim2.fromOffset(180, 48),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Parent = header,
			OnClick = function()
				StoreKit.request(ctx, "Ranch.Harvest", {})
			end,
		})
		harvestAll:SetDisabled(not anyReady)
		local grid = New("Frame", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -12, 0, 0),
			LayoutOrder = 2,
			Parent = content,
		}, { Create.Grid(Vector2.new(170, 150), 10) })
		for i = 1, count do
			local p = plots[i]
			local card = Tiles.card({ Size = UDim2.fromOffset(170, 150), LayoutOrder = i, Parent = grid })
			Tiles.label({
				Text = "Plot " .. i,
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 4),
				Size = UDim2.new(1, 0, 0, 20),
				Parent = card,
			})
			local flavor = type(p) == "table" and p.flavor and Config.Food.ById[p.flavor]
			if not flavor then
				Tiles.label({
					Text = "Empty",
					TextSize = Theme.TextSize.Body,
					TextColor3 = C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(0, 40),
					Size = UDim2.new(1, 0, 0, 30),
					Parent = card,
				})
				Button.new({
					Text = "Plant",
					Color = C.Green,
					Size = UDim2.fromOffset(140, 46),
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -8),
					Parent = card,
					OnClick = function()
						openPlantPicker(i)
					end,
				})
			else
				local readyAt = tonumber(p.readyAt) or 0
				New("Frame", {
					BackgroundColor3 = Theme.Food(flavor.id),
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 28),
					Size = UDim2.fromOffset(36, 36),
					Parent = card,
				}, { Create.Round(), Create.Stroke(2) })
				Tiles.label({
					Text = flavor.name,
					TextSize = Theme.TextSize.Small,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(0, 66),
					Size = UDim2.new(1, 0, 0, 20),
					Parent = card,
				})
				if readyAt <= now then
					Button.new({
						Text = "Harvest",
						Color = C.Orange,
						Size = UDim2.fromOffset(140, 46),
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -8),
						Parent = card,
						OnClick = function()
							StoreKit.request(ctx, "Ranch.Harvest", { plot = i })
						end,
					})
				else
					local timer = Tiles.label({
						Text = Format.clock(readyAt - now),
						TextSize = Theme.TextSize.Header - 2,
						TextColor3 = C.Green,
						TextXAlignment = Enum.TextXAlignment.Center,
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -14),
						Size = UDim2.new(1, 0, 0, 30),
						Parent = card,
					})
					table.insert(plotTimers, { label = timer, readyAt = readyAt, done = false })
				end
			end
		end
		local nextPlots = Economy.Garden.plots[tierOf(garden.tier) + 1]
		if nextPlots then
			local cost = Economy.Garden.cost[tierOf(garden.tier) + 1] or 0
			actionCard(
				3,
				string.format("More plots (%d → %d)", count, nextPlots),
				"More plots, more food.",
				Format.short(cost) .. " coins",
				C.Green,
				StoreKit.canAfford(store, { coins = cost }),
				function()
					StoreKit.request(ctx, "Ranch.Upgrade", { target = "garden" })
				end
			)
		end
	end

	-- Nav ---------------------------------------------------------------------------

	local function navButton(id: string, text: string, color: Color3, order: number, locked: boolean?)
		local b = Button.new({
			Text = text,
			Color = if selected == id then C.Orange elseif locked then C.Gray else color,
			TextSize = 18,
			Size = UDim2.fromOffset(160, 48),
			LayoutOrder = order,
			Parent = nav,
			OnClick = function()
				selected = id
				refresh()
			end,
		})
		return b
	end

	function refresh()
		live = {}
		table.clear(plotTimers)
		local owned = pens()
		local count = #owned
		local session = StoreKit.tbl(store, "session.Ranch")
		incomeLabel.Text = string.format("Income %s/s", Format.short(math.floor((tonumber(session.income) or 0) * 10) / 10))

		if string.sub(selected, 1, 3) == "pen" then
			local n = tonumber(string.sub(selected, 4)) or 1
			if n > count then
				selected = if count > 0 then "pen1" else "buildings"
			end
		end

		Tiles.clear(nav)
		for i = 1, count do
			navButton("pen" .. i, "Pen " .. i, C.Green, i)
		end
		if count < Economy.Pens.max then
			local key = Economy.Pens.unlocks[count + 1]
			navButton("buy", "+ Pen " .. (count + 1), C.Blue, 10, not StoreKit.isUnlocked(store, key))
		end
		navButton("buildings", "Buildings", C.Purple, 11)
		navButton("garden", "Feed Garden", C.Green, 12, not StoreKit.isUnlocked(store, Economy.Garden.unlock))

		Tiles.clear(content)
		if count == 0 and string.sub(selected, 1, 3) == "pen" then
			selected = "buildings"
		end
		if string.sub(selected, 1, 3) == "pen" then
			renderPen(tonumber(string.sub(selected, 4)) or 1)
		elseif selected == "buy" then
			renderBuyPen()
		elseif selected == "garden" then
			renderGarden()
		else
			renderBuildings()
		end
	end

	watch = StoreKit.watch(store, {
		"profile.Ranch",
		"session.Ranch",
		"profile.Shop",
		"profile.Monsters.list",
		"profile.Currency.coins",
		"profile.Progression.level",
	}, function()
		if not popup:IsOpen() then
			refresh()
		end
	end)

	local tick
	return {
		Root = panel.Root,
		Open = function(params)
			local pen = type(params) == "table" and tonumber(params.pen) or nil
			if pen then
				selected = "pen" .. math.floor(pen)
			end
			popup:Hide()
			watch.Start()
			local acc = 0
			tick = RunService.Heartbeat:Connect(function(dt)
				acc += dt
				if acc < 0.5 then
					return
				end
				acc = 0
				local now = ctx:Now()
				if live.pen then
					local jar, full = StoreKit.jar(store, live.pen, now)
					live.bar:SetValue(if full > 0 then jar / full else 0)
					live.bar:SetText(Format.short(math.floor(jar)) .. " / " .. Format.short(math.floor(full)))
					live.button:SetText(if jar >= 1 then "Collect +" .. Format.short(math.floor(jar)) else "Collect")
				end
				for _, t in plotTimers do
					if not t.done then
						if t.readyAt <= now then
							t.done = true
							watch.Refresh()
						else
							t.label.Text = Format.clock(t.readyAt - now)
						end
					end
				end
			end)
		end,
		Close = function()
			watch.Stop()
			popup:Hide()
			if tick then
				tick:Disconnect()
				tick = nil
			end
		end,
	}
end

return Ranch
