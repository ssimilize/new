--[[
	Notifications (C2): popups for server events.

	  Rewards.Granted      reward card in the one feedback queue (Toasts.push, on ctx.UI.Feedback,
	                       shared with toasts so they never overlap); its coins, gems and items fly
	                       from the card into the HUD (Celebrate:Reward; purchases are at least big)
	  Weather.Mutated      toast with a mutation chip in the same stack
	  Progression.LevelUp  gold banner with the new unlocks (Config.Unlocks.Names) in ctx.UI.Top,
	                       and a shockwave from the HUD level bar (every 10th level is big)
	  Monsters.Evolved     celebration popup (from → to MonsterIcon) in ctx.UI.Top, queued
	  session.WelcomeBack  opens the WelcomeBack screen each time `pending` turns true

	Kernel.Notify toasts are handled by the kernel itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local Appearance = require(Shared.Logic.Appearance)

local Voices = require(script.Parent.Parent.Audio.Voices)
local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Focus = require(UI.Focus)
local Button = require(UI.Components.Button)
local Icon = require(UI.Components.Icon)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)
local Tiles = require(UI.Components.Tiles)
local Toasts = require(UI.Components.Toasts)

local New = Create.New
local C = Theme.Colors

local Notifications = {
	Name = "Notifications",
	Dependencies = { "Hud", "Celebrate" },
}

local ctx

-- Feed (reward cards, mutation toasts): the shared feedback queue in UI/Components/Toasts. ---

local function pushFeed(card: GuiObject, seconds: number)
	local dismiss = Toasts.push(card, seconds)
	Tiles.tap(card, dismiss, 50)
end

-- Returns the card (tap target, no layout) and its content frame (vertical list).
local function feedCard(): (Frame, Frame)
	local card = New("Frame", {
		Name = "FeedCard",
		BackgroundColor3 = C.Panel,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
	}, {
		Create.Corner(Theme.Radius.Card),
		Create.Stroke(Theme.Stroke.Card),
		Create.Padding(8, 14, 8, 14),
	})
	local content = New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Parent = card,
	}, { Create.List("y", 6, Enum.HorizontalAlignment.Center) })
	return card, content
end

local function titleCase(source: string): string
	local text = string.gsub(source, "[_%.]", " ")
	return (string.gsub(text, "^%l", string.upper))
end

-- One reward entry: an icon GuiObject and a label.
local function rewardIcon(item): (GuiObject, string)
	local amount = tonumber(item.amount) or 0
	local kind = item.kind
	if kind == "egg" then
		local def = Config.Eggs.ById[item.id or ""]
		return MonsterIcon.egg(item.id or "meadow", 30), string.format("+%d %s", amount, if def then def.name else "Egg")
	elseif kind == "monster" then
		local ok, ap = pcall(Appearance.Preview, item.id, 1, nil, item.rarity)
		local name = if ok and ap then ap.name else "Monster"
		return (if ok and ap then MonsterIcon.new(ap, 30) else Icon.new("egg", 30)), "+" .. name
	elseif kind == "food" then
		local def = Config.Food.ById[item.id or ""]
		local icon = Icon.new("food", 28)
		return icon, string.format("+%s %s", Format.short(amount), if def then def.name else "food")
	elseif kind == "decor" then
		local def = Config.Decor.ById[item.id or ""]
		return Icon.new("star", 28), string.format("+%d %s", amount, if def then def.name else "decor")
	elseif kind == "xp" then
		return Icon.new("xp", 28), "+" .. Format.short(amount) .. " XP"
	elseif kind == "token" then
		return Icon.new("token", 28), "+" .. Format.short(amount)
	end
	return Icon.new(StoreKit.iconFor(kind or "coins"), 28), "+" .. Format.short(amount)
end

local function onRewards(payload)
	if type(payload) ~= "table" or type(payload.items) ~= "table" or #payload.items == 0 then
		return
	end
	local card, content = feedCard()
	Tiles.label({
		Text = if payload.source then "Rewards · " .. titleCase(tostring(payload.source)) else "Rewards!",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		TextWrapped = false,
		LayoutOrder = 1,
		Parent = content,
	})
	local row = New("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		LayoutOrder = 2,
		Parent = content,
	}, { Create.List("x", 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	for i, item in payload.items do
		if i > 6 then
			break
		end
		if type(item) == "table" then
			local entry = New("Frame", {
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 34),
				LayoutOrder = i,
				Parent = row,
			}, { Create.List("x", 5, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
			local icon, text = rewardIcon(item)
			icon.LayoutOrder = 1
			icon.Parent = entry
			Tiles.label({
				Text = text,
				TextSize = Theme.TextSize.Body,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				TextWrapped = false,
				LayoutOrder = 2,
				Parent = entry,
			})
		end
	end
	local hasGems = false
	for _, item in payload.items do
		if type(item) == "table" and item.kind == "gems" then
			hasGems = true
		end
	end
	local source = payload.source
	if source == "daily" or source == "achievement" or source == "pass" then
		ctx:Sound("QuestComplete")
	elseif hasGems then
		ctx:Sound("Gem")
	else
		ctx:Sound("CoinCollect")
	end
	pushFeed(card, 3.5)
	local kit = ctx:GetController("Celebrate")
	if kit then
		local source = tostring(payload.source or "")
		-- Wait a frame so the card has its place in the stack before things fly out of it.
		task.defer(function()
			kit:Reward(payload.items, {
				from = card,
				minSize = if string.sub(source, 1, 9) == "purchase:" then "big" else nil,
			})
		end)
	end
end

local function onMutated(payload)
	if type(payload) ~= "table" or not payload.mutation then
		return
	end
	local m = StoreKit.monster(ctx.Store, payload.id)
	local name = if m then Formulas.DisplayName(m) else "A monster"
	local card, content = feedCard()
	card.BackgroundColor3 = C.Dark
	local row = New("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		Parent = content,
	}, { Create.List("x", 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	if m then
		local ok, ap = pcall(Appearance.Of, m)
		if ok then
			local icon = MonsterIcon.new(ap, 38)
			icon.LayoutOrder = 1
			icon.Parent = row
		end
	end
	Create.Text({
		Text = name .. (if payload.result == "combined" then " combined into" else " got"),
		TextSize = Theme.TextSize.Body,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = row,
	})
	local chip = Widgets.MutationChip(payload.mutation, row)
	chip.LayoutOrder = 3
	ctx:Sound("WeatherStart")
	pushFeed(card, 4.5)
end

-- Level-up banner ---------------------------------------------------------------------

local levelQueue = {}
local levelShowing = false

local function showNextLevel()
	if levelShowing or #levelQueue == 0 then
		return
	end
	levelShowing = true
	local payload = table.remove(levelQueue, 1)
	local names = {}
	for _, key in StoreKit.asTable(payload.unlocks) do
		table.insert(names, Config.Unlocks.Names[key] or tostring(key))
	end
	local banner = New("TextButton", {
		Name = "LevelUp",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.Gold,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(520, if #names > 0 then 104 else 70),
		ZIndex = 30,
		Parent = ctx.UI.Top,
	}, {
		Create.Corner(Theme.Radius.Panel),
		Create.Stroke(Theme.Stroke.Panel),
		Create.Shade(0.15),
		Create.List("y", 2, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	Create.Text({
		Text = string.format("RANCH LEVEL %d!", tonumber(payload.level) or StoreKit.level(ctx.Store)),
		TextSize = Theme.TextSize.Title,
		Size = UDim2.new(1, -20, 0, 38),
		ZIndex = 31,
		LayoutOrder = 1,
		Parent = banner,
	})
	if #names > 0 then
		Create.Text({
			Text = "Unlocked: " .. table.concat(names, " · "),
			TextSize = Theme.TextSize.Body,
			Size = UDim2.new(1, -24, 0, 48),
			ZIndex = 31,
			LayoutOrder = 2,
			Parent = banner,
		})
	end
	ctx:Sound("LevelUp")
	Anim.popIn(banner, 0.3)
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		banner:Destroy()
		levelShowing = false
		showNextLevel()
	end
	banner.Activated:Connect(close)
	task.delay(if #names > 0 then 4.5 else 3, close)
end

local function onLevelUp(payload)
	if type(payload) ~= "table" then
		return
	end
	table.insert(levelQueue, payload)
	showNextLevel()
	local kit = ctx:GetController("Celebrate")
	local hud = ctx:GetController("Hud")
	if kit and hud then
		local level = tonumber(payload.level) or 0
		kit:Shockwave(hud:GetTarget("level"), C.Blue)
		kit:Play(if level > 0 and level % 10 == 0 then "big" else "medium")
	end
	if hud and #StoreKit.asTable(payload.unlocks) > 0 then
		hud:Flash("Ranch")
	end
end

-- Evolution popup ---------------------------------------------------------------------

local evolveQueue = {}
local evolveShowing = false

local function showNextEvolve()
	if evolveShowing or #evolveQueue == 0 then
		return
	end
	evolveShowing = true
	local payload = table.remove(evolveQueue, 1)
	local toInfo = Config.Species.FormById[payload.toForm or ""]
	local fromInfo = Config.Species.FormById[payload.fromForm or ""]
	local m = StoreKit.monster(ctx.Store, payload.id)
	local lineId = (m and m.line) or (toInfo and toInfo.line.id)
	if not lineId then
		evolveShowing = false
		showNextEvolve()
		return
	end
	local rarity = m and m.rarity or 1
	local variant = m and m.variant or 0
	local stage = tonumber(payload.stage) or (toInfo and toInfo.stage) or 2
	local fromAp = Appearance.Preview(lineId, math.max(1, stage - 1), payload.fromForm, rarity, variant)
	local toAp = if m then Appearance.Of(m) else Appearance.Preview(lineId, stage, payload.toForm, rarity, variant)
	local fromName = if fromInfo then fromInfo.form.name else fromAp.name
	local toName = if toInfo then toInfo.form.name else toAp.name

	local dim = New("TextButton", {
		Name = "Evolved",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.Dark,
		BackgroundTransparency = 0.4,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Selectable = false, -- a tap blocker, never a gamepad target
		Parent = ctx.UI.Top,
	})
	local card = New("Frame", {
		BackgroundColor3 = C.Panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(500, 330),
		ZIndex = 21,
		Parent = dim,
	}, { Create.Corner(Theme.Radius.Panel), Create.Stroke(Theme.Stroke.Panel) })
	local stageName = Config.Economy.Stages[stage] and Config.Economy.Stages[stage].name or ""
	Create.Text({
		Text = if stage >= 3 then "Fully grown!" else "Growing up!",
		TextSize = Theme.TextSize.Title,
		TextColor3 = C.White,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 38),
		ZIndex = 22,
		Parent = card,
	})
	local icons = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 150),
		ZIndex = 22,
		Parent = card,
	}, { Create.List("x", 18, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local a = MonsterIcon.new(fromAp, 110)
	a.LayoutOrder = 1
	a.Parent = icons
	Create.Text({
		Text = "➜",
		TextSize = 44,
		TextColor3 = C.Orange,
		Stroke = true,
		Size = UDim2.fromOffset(50, 60),
		LayoutOrder = 2,
		Parent = icons,
	})
	local b = MonsterIcon.new(toAp, 140)
	b.LayoutOrder = 3
	b.Parent = icons
	Tiles.label({
		Text = string.format("%s grew into %s (%s)!", if m and m.name ~= "" and m.name then m.name else fromName, toName, stageName),
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(20, 214),
		Size = UDim2.new(1, -40, 0, 44),
		ZIndex = 22,
		Parent = card,
	})
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		Focus.remove(dim)
		dim:Destroy()
		evolveShowing = false
		showNextEvolve()
	end
	local buttonsRow = New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, -40, 0, 54),
		ZIndex = 22,
		Parent = card,
	}, { Create.List("x", 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	if m then
		Button.new({
			Text = "View",
			Color = C.Blue,
			Size = UDim2.fromOffset(140, 50),
			LayoutOrder = 1,
			ZIndex = 23,
			Parent = buttonsRow,
			OnClick = function()
				close()
				if ctx.Router:Has("MonsterDetail") then
					ctx.Router:Open("MonsterDetail", { id = payload.id })
				end
			end,
		})
	end
	Button.new({
		Text = "Yay!",
		Color = C.Green,
		Size = UDim2.fromOffset(160, 50),
		LayoutOrder = 2,
		ZIndex = 23,
		Parent = buttonsRow,
		OnClick = close,
	})
	ctx:Sound("Evolve")
	if m then
		task.delay(0.6, Voices.Cry, m, "evolve")
	end
	Focus.push(dim, close) -- a gamepad cursor stays on the popup; B closes it like "Yay!"
	Anim.popIn(card, 0.3)
end

local function onEvolved(payload)
	if type(payload) ~= "table" then
		return
	end
	table.insert(evolveQueue, payload)
	-- Let the Store patch with the new form land before drawing the popup.
	task.delay(0.1, showNextEvolve)
end

-- Welcome Back -----------------------------------------------------------------------

local lastPending = false
local function onWelcome(state)
	local pending = type(state) == "table" and state.pending == true
	if pending and not lastPending and ctx.Router:Has("WelcomeBack") then
		ctx.Router:Open("WelcomeBack")
	end
	lastPending = pending
end

function Notifications.Init(context)
	ctx = context
	ctx.Net:On("Rewards.Granted", onRewards)
	ctx.Net:On("Weather.Mutated", onMutated)
	ctx.Net:On("Progression.LevelUp", onLevelUp)
	ctx.Net:On("Monsters.Evolved", onEvolved)
	ctx.Store:Observe("session.WelcomeBack", onWelcome)
end

function Notifications.Start() end

return Notifications
