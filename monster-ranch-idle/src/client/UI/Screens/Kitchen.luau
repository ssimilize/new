--[[
	Kitchen (update 3.10): the Kitchen & Pantry screen. Opened by the "Cook" prompt on the
	Kitchen's door (Controllers/Interaction) and by the "Pantry" button in Monster Detail's feed
	popup. No HUD button.

	Tabs:
	  Cook     the cooking slots (locked, empty, cooking with a timer, ready) and one card per
	           recipe: its dish, ingredient chips (food colours, fish, golden), its effect, the
	           cook time and Cook (Kitchen.Cook; the server picks the first free slot). Fish
	           recipes without the Fishing system say "Needs fish from the Fishing Pond".
	  Pantry   one card per dish with how many are stored, the effect and Serve: Monsters pick
	           mode with the monsters that can eat it (Logic/Kitchen.ServeProblem) -> Kitchen.Serve.
	           The Golden seeds bar plants a seed in the first empty Feed Garden plot
	           (Kitchen.PlantGolden).
	Header: Collect (Kitchen.Collect). Finished dishes are collected when the screen opens.
	Params: { tab? = "cook" | "pantry", serve? = monsterId }  -- serve: Serve feeds that monster
	directly (from Monster Detail).

	Reads: profile.Kitchen, session.Kitchen, profile.Currency.food, profile.Monsters.list,
	profile.Progression.level, profile.Ranch.garden, profile.Bond.list (all tolerated nil).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local KitchenLogic = require(Shared.Logic.Kitchen)
local BondLogic = require(Shared.Logic.Bond)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local Util = require(script.Parent.Parts.Util)
local DishIcon = require(script.Parent.Parts.DishIcon)

local New = Create.New
local C = Theme.Colors
local Rules = Config.Kitchen

local FISH_COLOR = Color3.fromHex("#5E9FD6")

local function chip(parent: Instance, color: Color3, amount: number, order: number)
	local row = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(46, 22),
		LayoutOrder = order,
		Parent = parent,
	}, { Create.List("x", 3, nil, Enum.VerticalAlignment.Center) })
	New("Frame", {
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(16, 16),
		LayoutOrder = 1,
		Parent = row,
	}, { Create.Round(), Create.Stroke(1.5) })
	Util.text({
		Text = tostring(amount),
		TextSize = Theme.TextSize.Small,
		Size = UDim2.fromOffset(26, 22),
		LayoutOrder = 2,
		Parent = row,
	})
end

return {
	Name = "Kitchen",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Kitchen",
			Color = C.Orange,
			Size = UDim2.fromOffset(1040, 520),
			OnClose = function()
				ctx.Router:Close("Kitchen")
			end,
		})

		local isOpen = false
		local bag = Util.bag()
		local refresh
		local timers = {} -- { { label, readyAt, ready } }
		local tab = "cook"
		local serveTo: string? = nil
		local lock = nil

		local collectButton = Button.new({
			Name = "Collect",
			Text = "Collect",
			Color = C.Green,
			Size = UDim2.fromOffset(170, 44),
			TextSize = Theme.TextSize.Body,
			Parent = panel.HeaderRight,
		})

		local tabs = Widgets.Tabs({
			Tabs = { { id = "cook", text = "Cook" }, { id = "pantry", text = "Pantry" } },
			Selected = tab,
			Size = UDim2.fromOffset(276, 44),
			Parent = panel.Body,
			OnChanged = function(id)
				tab = id
				if refresh then
					refresh()
				end
			end,
		})
		local intro = Util.text({
			Name = "Intro",
			Text = "",
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(290, 0),
			Size = UDim2.new(1, -290, 0, 44),
			Parent = panel.Body,
		})
		local view = New("Frame", {
			Name = "View",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 50),
			Size = UDim2.new(1, 0, 1, -50),
			Parent = panel.Body,
		})

		local function kitchen()
			local k = ctx.Store:Get("profile.Kitchen")
			return if type(k) == "table" then k else {}
		end
		local function slotCount(): number
			local s = ctx.Store:Get("session.Kitchen")
			if type(s) == "table" and type(s.slotCount) == "number" then
				return s.slotCount
			end
			return KitchenLogic.SlotCount(function(key)
				return Util.unlocked(ctx, key)
			end)
		end
		local function fishHave(): number
			local s = ctx.Store:Get("session.Kitchen")
			return if type(s) == "table" and type(s.fish) == "number" then s.fish else 0
		end
		local function have()
			local food = {}
			local balances = ctx.Store:Get("profile.Currency.food")
			for _, flavor in Config.Food.Ids do
				food[flavor] = if type(balances) == "table" then tonumber(balances[flavor]) or 0 else 0
			end
			return { food = food, fish = fishHave(), golden = tonumber(kitchen().golden) or 0 }
		end
		local function hearts(id: string): number
			local list = ctx.Store:Get("profile.Bond.list")
			local entry = type(list) == "table" and list[id]
			return if type(entry) == "table" then BondLogic.Hearts(entry.pts, Config.Bond) else 0
		end
		local function problemFor(recipe, m): string?
			local boosts = kitchen().boosts
			return KitchenLogic.ServeProblem(recipe, m, {
				hearts = if type(m) == "table" then hearts(m.id) else 0,
				boost = type(boosts) == "table" and type(m) == "table" and boosts[m.id] or nil,
				now = ctx:Now(),
			})
		end

		-- Actions ---------------------------------------------------------------------------

		local function anyReady(): boolean
			local now = ctx:Now()
			for i, slot in (if type(kitchen().slots) == "table" then kitchen().slots else {}) do
				if i <= slotCount() and KitchenLogic.IsReady(slot, now) then
					return true
				end
			end
			return false
		end

		collectButton:SetOnClick(function()
			Util.requestOnce(ctx, "Kitchen.Collect")
		end)

		local function serve(recipe)
			if serveTo then
				local ok = Util.requestOnce(ctx, "Kitchen.Serve", { id = serveTo, dish = recipe.id })
				if ok then
					ctx:Sound("Eat")
				end
				return
			end
			Util.pick(ctx, {
				title = string.format("Serve %s to", recipe.name),
				max = 1,
				filter = function(m)
					return problemFor(recipe, m) == nil
				end,
				returnTo = "Kitchen",
				returnParams = { tab = "pantry" },
				onPick = function(ids)
					local ok = Util.requestOnce(ctx, "Kitchen.Serve", { id = ids[1], dish = recipe.id })
					if ok then
						ctx:Sound("Eat")
					end
				end,
			})
		end

		local function plantGolden()
			local garden = ctx.Store:Get("profile.Ranch.garden")
			local plots = type(garden) == "table" and garden.plots or {}
			for i, plot in plots do
				if type(plot) == "table" and not plot.flavor then
					Util.requestOnce(ctx, "Kitchen.PlantGolden", { plot = i })
					return
				end
			end
			ctx:Toast("Every Feed Garden plot is growing something", "error")
		end

		-- Cook tab --------------------------------------------------------------------------

		local function drawSlots(parent: Instance)
			local col = New("Frame", {
				Name = "Slots",
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 300, 1, 0),
				Parent = parent,
			}, { Create.List("y", 8) })
			local list = if type(kitchen().slots) == "table" then kitchen().slots else {}
			local open = slotCount()
			local now = ctx:Now()
			for index = 1, Rules.MaxSlots do
				local slot = list[index]
				local card = Util.card({
					Name = "Slot" .. index,
					Size = UDim2.new(1, 0, 0, 118),
					LayoutOrder = index,
					Parent = col,
				})
				if index > open then
					Util.lockOverlay(card, Util.unlockText(if index > Rules.BaseSlots then Rules.SlotUnlock else Rules.Unlock))
				elseif type(slot) == "table" and slot.recipe and Rules.ById[slot.recipe] then
					local recipe = Rules.ById[slot.recipe]
					local icon = DishIcon.new(recipe, 64)
					icon.Position = UDim2.fromOffset(10, 27)
					icon.Parent = card
					Util.text({
						Text = recipe.name,
						Font = Theme.Fonts.Display,
						TextSize = Theme.TextSize.Body,
						Position = UDim2.fromOffset(84, 12),
						Size = UDim2.new(1, -94, 0, 26),
						Parent = card,
					})
					local ready = KitchenLogic.IsReady(slot, now)
					local label = Util.text({
						Name = "Timer",
						Text = if ready then "Ready!" else Format.clock((slot.readyAt or 0) - now),
						TextColor3 = if ready then C.Green else C.TextMuted,
						TextSize = Theme.TextSize.Header - 2,
						Position = UDim2.fromOffset(84, 42),
						Size = UDim2.new(1, -94, 0, 30),
						Parent = card,
					})
					table.insert(timers, { label = label, readyAt = slot.readyAt or 0, ready = ready })
					if ready then
						Button.new({
							Name = "CollectSlot",
							Text = "Collect",
							Color = C.Green,
							Size = UDim2.fromOffset(130, 40),
							Position = UDim2.fromOffset(84, 72),
							TextSize = Theme.TextSize.Small + 1,
							Parent = card,
							OnClick = function()
								Util.requestOnce(ctx, "Kitchen.Collect")
							end,
						})
					end
				else
					Util.text({
						Text = string.format("Slot %d", index),
						Font = Theme.Fonts.Display,
						TextSize = Theme.TextSize.Body,
						Position = UDim2.fromOffset(14, 12),
						Size = UDim2.new(1, -28, 0, 26),
						Parent = card,
					})
					Util.text({
						Text = "Empty · pick a recipe",
						TextColor3 = C.TextMuted,
						Position = UDim2.fromOffset(14, 48),
						Size = UDim2.new(1, -28, 0, 26),
						Parent = card,
					})
				end
			end
		end

		local function drawRecipes(parent: Instance)
			local scroll = New("ScrollingFrame", {
				Name = "Recipes",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(312, 0),
				Size = UDim2.new(1, -312, 1, 0),
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 8,
				Parent = parent,
			}, { Create.Grid(Vector2.new(218, 184), 8) })
			local stock = have()
			local fishing = type(ctx.Store:Get("session.Kitchen")) == "table" and ctx.Store:Get("session.Kitchen").fishing
			for i, recipe in Rules.Recipes do
				local card =
					Util.card({ Name = "Recipe_" .. recipe.id, Size = UDim2.fromOffset(218, 184), LayoutOrder = i, Parent = scroll })
				local icon = DishIcon.new(recipe, 52)
				icon.Position = UDim2.fromOffset(6, 4)
				icon.Parent = card
				Util.text({
					Text = recipe.name,
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Small + 1,
					TextWrapped = true,
					Position = UDim2.fromOffset(62, 6),
					Size = UDim2.new(1, -68, 0, 44),
					Parent = card,
				})
				local chips = New("Frame", {
					Name = "Ingredients",
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(8, 58),
					Size = UDim2.new(1, -16, 0, 22),
					Parent = card,
				}, { Create.List("x", 2) })
				local food, fish, golden = KitchenLogic.Split(recipe)
				local order = 0
				if golden > 0 then
					order += 1
					chip(chips, Color3.fromHex(Rules.Golden.color), golden, order)
				end
				if fish > 0 then
					order += 1
					chip(chips, FISH_COLOR, fish, order)
				end
				for _, flavor in Config.Food.Ids do
					if food[flavor] then
						order += 1
						chip(chips, Theme.Food(flavor), food[flavor], order)
					end
				end
				Util.text({
					Text = Rules.Effects[recipe.effect].desc,
					TextColor3 = C.TextMuted,
					TextSize = Theme.TextSize.Small,
					TextWrapped = true,
					Position = UDim2.fromOffset(8, 82),
					Size = UDim2.new(1, -16, 0, 40),
					Parent = card,
				})
				if fish > 0 and not fishing then
					Util.text({
						Name = "NeedsFish",
						Text = "Needs fish from the Fishing Pond",
						TextColor3 = C.Red,
						TextSize = Theme.TextSize.Small,
						TextWrapped = true,
						Position = UDim2.fromOffset(8, 126),
						Size = UDim2.new(1, -16, 0, 50),
						Parent = card,
					})
				else
					Util.text({
						Text = if recipe.makes > 1
							then string.format("%s · makes %d", Format.duration(recipe.minutes * 60), recipe.makes)
							else Format.duration(recipe.minutes * 60),
						TextSize = Theme.TextSize.Small,
						Position = UDim2.fromOffset(8, 136),
						Size = UDim2.new(0, 90, 0, 40),
						Parent = card,
					})
					local b = Button.new({
						Name = "Cook_" .. recipe.id,
						Text = "Cook",
						Color = C.Orange,
						Size = UDim2.fromOffset(100, 42),
						AnchorPoint = Vector2.new(1, 1),
						Position = UDim2.new(1, -8, 1, -8),
						TextSize = Theme.TextSize.Small + 1,
						Parent = card,
						OnClick = function()
							Util.requestOnce(ctx, "Kitchen.Cook", { recipe = recipe.id })
						end,
					})
					b:SetDisabled(KitchenLogic.Missing(recipe, stock) ~= nil)
				end
			end
		end

		-- Pantry tab ------------------------------------------------------------------------

		local function drawPantry(parent: Instance)
			local k = kitchen()
			local bar = Util.card({ Name = "Golden", Size = UDim2.new(1, 0, 0, 56), Parent = parent })
			New("Frame", {
				BackgroundColor3 = Color3.fromHex(Rules.Golden.color),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 14, 0.5, 0),
				Size = UDim2.fromOffset(28, 28),
				Parent = bar,
			}, { Create.Round(), Create.Stroke(2) })
			Util.text({
				Name = "GoldenText",
				Text = string.format("Golden seeds: %d · %s: %d", tonumber(k.seeds) or 0, Rules.Golden.name, tonumber(k.golden) or 0),
				Position = UDim2.fromOffset(52, 0),
				Size = UDim2.new(1, -250, 1, 0),
				Parent = bar,
			})
			local plant = Button.new({
				Name = "PlantGolden",
				Text = "Plant a seed",
				Color = C.Green,
				Size = UDim2.fromOffset(180, 42),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				TextSize = Theme.TextSize.Small + 1,
				Parent = bar,
				OnClick = plantGolden,
			})
			plant:SetDisabled((tonumber(k.seeds) or 0) <= 0)

			local scroll = New("ScrollingFrame", {
				Name = "Dishes",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 64),
				Size = UDim2.new(1, 0, 1, -64),
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 8,
				Parent = parent,
			}, { Create.Grid(Vector2.new(242, 150), 8) })
			local pantry = if type(k.pantry) == "table" then k.pantry else {}
			local target = serveTo and Util.monsters(ctx)[serveTo]
			for i, recipe in Rules.Recipes do
				local n = tonumber(pantry[recipe.id]) or 0
				local card = Util.card({ Name = "Dish_" .. recipe.id, Size = UDim2.fromOffset(242, 150), LayoutOrder = i, Parent = scroll })
				local icon = DishIcon.new(recipe, 52)
				icon.Position = UDim2.fromOffset(6, 4)
				icon.Parent = card
				Util.text({
					Text = recipe.name,
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Small + 1,
					TextWrapped = true,
					Position = UDim2.fromOffset(62, 4),
					Size = UDim2.new(1, -120, 0, 44),
					Parent = card,
				})
				Util.text({
					Name = "Count",
					Text = string.format("×%d", n),
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body,
					TextXAlignment = Enum.TextXAlignment.Right,
					Position = UDim2.new(1, -58, 0, 10),
					Size = UDim2.fromOffset(50, 26),
					Parent = card,
				})
				Util.text({
					Text = Rules.Effects[recipe.effect].desc,
					TextColor3 = C.TextMuted,
					TextSize = Theme.TextSize.Small,
					TextWrapped = true,
					Position = UDim2.fromOffset(8, 56),
					Size = UDim2.new(1, -16, 0, 40),
					Parent = card,
				})
				local b = Button.new({
					Name = "Serve_" .. recipe.id,
					Text = "Serve",
					Color = C.Pink,
					Size = UDim2.fromOffset(110, 40),
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, -8, 1, -8),
					TextSize = Theme.TextSize.Small + 1,
					Parent = card,
					OnClick = function()
						serve(recipe)
					end,
				})
				b:SetDisabled(n <= 0 or (target ~= nil and problemFor(recipe, target) ~= nil))
			end
		end

		-- Draw ------------------------------------------------------------------------------

		local function tick()
			local now = ctx:Now()
			for _, t in timers do
				if not t.ready then
					if now >= t.readyAt then
						t.ready = true
						refresh()
					else
						t.label.Text = Format.clock(t.readyAt - now)
					end
				end
			end
		end

		local function draw()
			if not isOpen then
				return
			end
			Util.clear(view)
			table.clear(timers)
			if lock then
				lock:Destroy()
				lock = nil
			end
			local target = serveTo and Util.monsters(ctx)[serveTo]
			if target then
				intro.Text = string.format("Pick a dish for %s", Formulas.DisplayName(target))
			elseif tab == "pantry" then
				intro.Text = string.format("Serve dishes to your monsters. The Pantry holds up to %d of each.", Rules.PantryCap)
			else
				intro.Text = "Cook dishes from your food. They keep cooking while you are away."
			end
			collectButton:SetDisabled(not anyReady())
			if tab == "pantry" then
				drawPantry(view)
			else
				drawSlots(view)
				drawRecipes(view)
			end
			if not Util.unlocked(ctx, Rules.Unlock) then
				lock = Util.lockOverlay(view, Util.unlockText(Rules.Unlock))
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function(params)
				isOpen = true
				bag.clean()
				serveTo = if type(params) == "table" and type(params.serve) == "string" then params.serve else nil
				local want = if type(params) == "table" and (params.tab == "cook" or params.tab == "pantry")
					then params.tab
					elseif serveTo then "pantry"
					else nil
				if want and want ~= tab then
					tabs:Select(want)
					tab = want
				end
				for _, path in
					{
						"profile.Kitchen",
						"session.Kitchen",
						"profile.Currency.food",
						"profile.Monsters.list",
						"profile.Progression.level",
						"profile.Bond.list",
					}
				do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				refresh()
				-- Dishes that finished while the screen was closed go to the Pantry now.
				if Util.unlocked(ctx, Rules.Unlock) and anyReady() then
					task.spawn(function()
						Util.request(ctx, "Kitchen.Collect")
					end)
				end
				task.spawn(function()
					while isOpen do
						task.wait(1)
						if isOpen then
							tick()
						end
					end
				end)
			end,
			Close = function()
				isOpen = false
				serveTo = nil
				bag.clean()
			end,
		}
	end,
}
