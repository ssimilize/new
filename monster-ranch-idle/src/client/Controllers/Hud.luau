--[[
	Hud (C2): the always-on ranch HUD in ctx.UI.Hud.

	  top-left      coins / gems / food pills (count-up; gems → Store "gems", food → Store "food")
	  top-right     Ranch Level + XP bar (Config.Unlocks.XPToNext) · ⚙ Settings button beside it
	  top-centre    server weather banner (global.Weather) with mutation hint and countdown
	  left stack    Shop · Eggs (ready badge) · Monsters (can-grow badge) · Codex · Market
	                (locked until Config.Market.Unlock)
	  right stack   Expeditions (finished badge) · Stampede card · Quests (claimable badge)
	                · Breeding · Hall of Fame (locked until their Ranch Level)
	  bottom-centre Ranch · "Collect all +X" (live jar total, session.Ranch) · Store ("!" when the VIP crate is ready)

	Public:
	  Hud:GetTarget(name) -> GuiObject?   tutorial arrow targets: incubator, jar, shop, monster,
	                                      expeditions, weather, quests (+ any button name); the
	                                      counters coins, gems, food and the level bar (level)
	  Hud:HoldCounter(kind)               kind = "coins" | "gems" | "food": the pill keeps showing
	                                      its current number while a reward flies in (Celebrate)
	  Hud:ReleaseCounter(kind, seconds?)  counts up to the real balance over `seconds`
	  Hud:PulseCounter(kind)              a bump as a flying icon lands
	Holds nest, and each one lets go by itself after HOLD_LIMIT seconds.
	While a Stampede is in its lobby or live, the Stampede card glows gold, pulses and shows a
	badge until you join (the countdown on it is the time to the start / the end).
	Client bus: "Hud.Flash" (buttonName | targetName) pulses that button.
	The centre (weather banner, bottom bar) hides while a modal screen is open.
	Market.MailCollected (update 1.3) shows as a toast ("Your Rare Cindlet sold for 12K!").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local Appearance = require(Shared.Logic.Appearance)
local Vip = require(Shared.Logic.Vip)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Button = require(UI.Components.Button)
local Icon = require(UI.Components.Icon)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)
local Tiles = require(UI.Components.Tiles)

local New = Create.New
local C = Theme.Colors

local Hud = {
	Name = "Hud",
	Dependencies = {},
}

local ctx
local root: Frame
local buttons = {} -- name -> { gui = GuiObject, badge = badge?, lockKey = string?, lockIcon = GuiObject?, button = Button? }
local targets = {} -- tutorial target name -> GuiObject
local centre = {} -- GuiObjects hidden while a modal is open

local TARGET_ALIAS = {
	incubator = "Eggs",
	jar = "Collect",
	shop = "Shop",
	monster = "Monsters",
	expeditions = "Expeditions",
	quests = "Quests",
	weather = "Weather",
	stampede = "Stampede",
}

local function openScreen(name: string, params: any?)
	if not ctx.Router:Has(name) then
		ctx:Toast("Coming soon", "info")
		return
	end
	-- Shortcuts with params (e.g. a Store tab) switch the open screen instead of closing it.
	if params ~= nil then
		ctx.Router:Open(name, params)
	else
		ctx.Router:Toggle(name, params)
	end
end

local function isLocked(entry): boolean
	return entry.lockKey ~= nil and not StoreKit.isUnlocked(ctx.Store, entry.lockKey)
end

-- Builders --------------------------------------------------------------------------

local function sideButton(
	parent: Instance,
	name: string,
	text: string,
	color: Color3,
	icon: GuiObject,
	order: number,
	action: () -> (),
	lockKey: string?
)
	local entry = { lockKey = lockKey }
	local b = Button.new({
		Name = name,
		Text = text,
		Color = color,
		Size = UDim2.fromOffset(140, 52),
		TextSize = Theme.TextSize.Body + 1,
		Icon = icon,
		LayoutOrder = order,
		Parent = parent,
		OnClick = function()
			if isLocked(entry) then
				ctx:Toast(StoreKit.lockText(entry.lockKey), "info")
				Anim.shake(entry.gui)
				return
			end
			action()
		end,
	})
	entry.button = b
	entry.color = color
	entry.gui = b.Root
	entry.badge = Tiles.badge(b.Root)
	if lockKey then
		local lockIcon = Icon.new("lock", 24)
		lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		lockIcon.Position = UDim2.fromOffset(4, 4)
		lockIcon.ZIndex = 30
		lockIcon.Visible = false
		lockIcon.Parent = b.Root
		entry.lockIcon = lockIcon
	end
	buttons[name] = entry
	return entry
end

local function previewIcon(lineId: string, size: number): GuiObject
	local ok, ap = pcall(Appearance.Preview, lineId, 1)
	if ok and ap then
		return MonsterIcon.new(ap, size)
	end
	return Icon.new("star", size)
end

local HOLD_LIMIT = 6 -- seconds a counter may be held before it lets go by itself

local function pill(parent: Instance, kind: string, order: number, onTap: (() -> ())?)
	-- The pill lays out its children, so the tap target lives on a plain holder around it.
	local holder = Tiles.frame({ AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(), LayoutOrder = order, Parent = parent })
	local p = Widgets.Pill({ Icon = kind, Text = "0", Parent = holder })
	if onTap then
		Tiles.tap(holder, onTap)
	end
	-- shown: the balance in the Store; display: the number on screen right now.
	local state = { shown = 0, display = 0, holds = 0, holdToken = 0, stop = nil :: (() -> ())?, pill = p }
	local function countTo(value: number, seconds: number)
		if state.stop then
			state.stop()
		end
		state.stop = Anim.countUp(p.Label, state.display, value, seconds, function(n)
			state.display = n
			return Format.short(math.floor(n + 0.5))
		end)
	end
	function state.set(value: number)
		if value == state.shown then
			return
		end
		local from = state.shown
		state.shown = value
		if state.holds > 0 then
			return -- a reward is still flying in; release() shows the new total
		end
		countTo(value, 0.6)
		if value > from then
			Anim.pulse(p.Root, 0.06)
		end
	end
	function state.release(seconds: number?)
		if state.holds <= 0 then
			return
		end
		state.holds -= 1
		if state.holds == 0 then
			countTo(state.shown, seconds or 0.6)
		end
	end
	function state.hold()
		state.holds += 1
		state.holdToken += 1
		local token = state.holdToken
		if state.stop then
			state.stop() -- freeze on the number the player is looking at
			state.stop = nil
		end
		task.delay(HOLD_LIMIT, function()
			if state.holdToken == token and state.holds > 0 then
				state.holds = 1
				state.release(0.6)
			end
		end)
	end
	return state
end

-- Refreshers ------------------------------------------------------------------------

local pills = {}
local level = { label = nil, pct = nil, bar = nil }
local weather = { frame = nil, text = nil, time = nil }
local stampede = { title = nil, time = nil, iconHolder = nil, bossId = nil, card = nil, stroke = nil, live = false, pulseAt = 0 }
local collect = { button = nil, last = -1 }
local growReady = 0

local function refreshCurrency()
	pills.coins.set(StoreKit.num(ctx.Store, "profile.Currency.coins"))
	pills.gems.set(StoreKit.num(ctx.Store, "profile.Currency.gems"))
	pills.food.set(StoreKit.foodTotal(ctx.Store))
end

local shownCap = 0 -- Config.Unlocks.MaxLevelAt when the level bar was last drawn

local function refreshLevel()
	local lv = StoreKit.level(ctx.Store)
	local xp = StoreKit.num(ctx.Store, "profile.Progression.xp")
	local need = Config.Unlocks.XPToNext(lv)
	-- The cap is date-gated (60, then 70 from 3.2's launch); read it at the synced time.
	local atCap = lv >= Config.Unlocks.MaxLevelAt(ctx:Now())
	local frac = if atCap or need <= 0 then 1 else math.clamp(xp / need, 0, 1)
	level.label.Text = string.format("Ranch Lv %d", lv)
	level.pct.Text = if atCap then "MAX" else string.format("%d%%", math.floor(frac * 100))
	level.bar:SetValue(frac, true)
	for _, entry in buttons do
		if entry.lockKey then
			local locked = isLocked(entry)
			entry.lockIcon.Visible = locked
			entry.button:SetColor(if locked then C.Gray else entry.color)
		end
	end
end

local function weatherDef()
	local w = StoreKit.tbl(ctx.Store, "global.Weather")
	local def = w.id and Config.Weather.ById[w.id]
	local endsAt = tonumber(w.endsAt) or 0
	if not def or def.id == "clear" or endsAt <= ctx:Now() then
		return nil, w
	end
	return def, w
end

local function refreshWeather()
	local def = weatherDef()
	local showWeather = def ~= nil
	weather.frame.Visible = showWeather and ctx.Router:Current() == nil
	if not def then
		return
	end
	local parts = { def.name }
	local mut = def.mutation and Config.Mutations.ById[def.mutation]
	if mut then
		if def.element and def.chance and def.matchChance and def.chance > 0 then
			local el = Config.Elements.ById[def.element]
			table.insert(
				parts,
				string.format(
					"%s chance ×%d for %s",
					mut.name,
					math.floor(def.matchChance / def.chance + 0.5),
					if el then el.name else def.element
				)
			)
		else
			table.insert(parts, mut.name .. " chance")
		end
	end
	weather.text.Text = table.concat(parts, " · ") .. " ·"
end

local function refreshBadges()
	local now = ctx:Now()
	local ready = StoreKit.readyEggs(ctx.Store, now)
	buttons.Eggs.badge:Set(if ready > 0 then tostring(ready) else nil)
	local done = StoreKit.finishedExpeditions(ctx.Store, now)
	buttons.Expeditions.badge:Set(if done > 0 then tostring(done) else nil)
	local claim = StoreKit.claimableQuests(ctx.Store)
	buttons.Quests.badge:Set(if claim > 0 then tostring(claim) else nil)
	buttons.Monsters.badge:Set(if growReady > 0 then "!" else nil)
	if buttons.Store and buttons.Store.badge then
		-- VIP Rancher: today's crate is waiting in the Store.
		local passes = ctx.Store:Get("session.Monetization.passes")
		local vip = ctx.Store:Get("profile.Monetization.vip")
		local owned = type(passes) == "table" and passes[Config.Monetization.VipCrate.pass] == true
		local ready = Vip.CrateReady(owned, type(vip) == "table" and vip.day or nil, Vip.Day(now))
		buttons.Store.badge:Set(if ready then "!" else nil)
	end
end

local function refreshMonsters()
	local n = 0
	for _, m in StoreKit.monsters(ctx.Store) do
		if type(m) == "table" and not m.busy and Config.Species.ById[m.line or ""] then
			local ok, can = pcall(Formulas.CanGrow, m)
			if ok and can then
				n += 1
			end
		end
	end
	growReady = n
	refreshBadges()
end

local function bossRotation(bossId: string?)
	for _, b in Config.Boss.Rotation do
		if b.id == bossId then
			return b
		end
	end
	return Config.Boss.Rotation[1]
end

local function refreshStampede(now: number)
	local boss = StoreKit.tbl(ctx.Store, "global.Boss")
	local target, title
	if boss.state == "active" then
		title, target = "STAMPEDE LIVE!", tonumber(boss.endsAt)
	elseif boss.state == "lobby" then
		title, target = "JOIN STAMPEDE", tonumber(boss.startsAt)
	else
		title = "STAMPEDE"
		target = tonumber(boss.startsAt)
		if not target or target <= now then
			-- The boss starts on a fixed clock (Config.Boss.Period) when no state is replicated yet.
			target = math.ceil(now / Config.Boss.Period) * Config.Boss.Period
		end
	end
	stampede.title.Text = title
	stampede.time.Text = if target then Format.clock(math.max(0, target - now)) else ""
	-- Lobby or live: the card glows and pulses (with a badge until you join) so the fight is
	-- visible from the ranch; one tap opens the Boss screen.
	local live = (boss.state == "active" or boss.state == "lobby") and not isLocked(buttons.Stampede)
	local joined = StoreKit.tbl(ctx.Store, "session.Boss").joined == true
	if live ~= stampede.live then
		stampede.live = live
		stampede.stroke.Color = if live then C.Gold else C.White
		stampede.stroke.Thickness = if live then 4 else 2.5
		stampede.card.BackgroundColor3 = if live then Color3.fromHex("#7A2A1F") else C.Dark
	end
	buttons.Stampede.badge:Set(if live and not joined then "!" else nil)
	if live and not joined and now - stampede.pulseAt >= 2 then
		stampede.pulseAt = now
		Anim.pulse(stampede.card, 0.1)
	end
	local def = bossRotation(boss.bossId)
	if def and def.id ~= stampede.bossId then
		stampede.bossId = def.id
		Tiles.clear(stampede.iconHolder)
		local ok, ap = pcall(Appearance.Preview, def.line, 3, def.form, 4)
		if ok and ap then
			MonsterIcon.new(ap, 40).Parent = stampede.iconHolder
		end
	end
end

local function refreshCollect(now: number)
	local total = math.floor(StoreKit.jarTotal(ctx.Store, now))
	if total == collect.last then
		return
	end
	collect.last = total
	collect.button:SetText(if total > 0 then "Collect all +" .. Format.short(total) else "Collect all")
end

local function refreshCentre()
	local free = ctx.Router:Current() == nil
	for _, gui in centre do
		gui.Visible = free
	end
	refreshWeather()
end

-- Flash ------------------------------------------------------------------------------

local function flash(name: string)
	local key = TARGET_ALIAS[name] or name
	local entry = buttons[key]
	local gui = entry and entry.gui or targets[name]
	if not gui then
		return
	end
	local stroke = gui:FindFirstChildOfClass("UIStroke")
	task.spawn(function()
		local original = stroke and stroke.Color
		for _ = 1, 3 do
			if stroke then
				stroke.Color = C.Gold
			end
			Anim.pulse(gui, 0.15)
			task.wait(0.35)
			if stroke and original then
				stroke.Color = original
			end
			task.wait(0.1)
		end
	end)
end

-- Build ------------------------------------------------------------------------------

local function build()
	local layer = ctx.UI.Hud
	root = New("Frame", { Name = "Hud", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = layer })

	-- Currencies (top-left)
	local currencies = Tiles.row({
		Name = "Currencies",
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(560, 44),
		Parent = root,
	}, 10, Enum.HorizontalAlignment.Left)
	pills.coins = pill(currencies, "coin", 1, nil)
	pills.gems = pill(currencies, "gem", 2, function()
		openScreen("Store", { tab = "gems" })
	end)
	pills.food = pill(currencies, "food", 3, function()
		openScreen("Store", { tab = "food" })
	end)
	targets.coins = pills.coins.pill.Root
	targets.gems = pills.gems.pill.Root
	targets.food = pills.food.pill.Root

	-- Ranch Level (top-right)
	local lvFrame = Tiles.frame({
		Name = "RanchLevel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 10),
		Size = UDim2.fromOffset(220, 50),
		Parent = root,
	})
	level.label = Create.Text({
		Text = "Ranch Lv 1",
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.7, 0, 0, 24),
		Parent = lvFrame,
	})
	level.pct = Create.Text({
		Text = "0%",
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.3, 0, 0, 24),
		Parent = lvFrame,
	})
	level.bar = Widgets.Bar({ Color = C.Blue, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 16), Parent = lvFrame })
	targets.level = lvFrame

	-- Settings: a small gear left of the level bar (its old left-stack slot is the Market's).
	local settingsButton = Button.new({
		Name = "Settings",
		Text = "⚙",
		Color = C.Gray,
		Size = UDim2.fromOffset(46, 46),
		TextSize = 26,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -246, 0, 10),
		Parent = root,
		OnClick = function()
			openScreen("Settings")
		end,
	})
	buttons.Settings = { gui = settingsButton.Root, button = settingsButton, color = C.Gray }

	-- Photo mode: a small camera under the gear (top-right utility column, clear of both stacks).
	local photoButton = Button.new({
		Name = "Photo",
		Text = "📷",
		Color = C.Purple,
		Size = UDim2.fromOffset(46, 46),
		TextSize = 24,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -246, 0, 64),
		Parent = root,
		OnClick = function()
			openScreen("PhotoMode")
		end,
	})
	buttons.Photo = { gui = photoButton.Root, button = photoButton, color = C.Purple }

	-- Weather (top-centre)
	local banner = New("Frame", {
		Name = "Weather",
		BackgroundColor3 = C.Dark,
		BackgroundTransparency = 0.3,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		Visible = false,
		Parent = root,
	}, {
		Create.Round(),
		Create.Stroke(2.5, C.White, 0.1),
		Create.Padding(0, 16, 0, 16),
		Create.List("x", 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	weather.frame = banner
	weather.text = Create.Text({
		Text = "",
		TextSize = Theme.TextSize.Body,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextWrapped = false,
		LayoutOrder = 1,
		Parent = banner,
	})
	weather.time = Create.Text({
		Text = "",
		TextSize = Theme.TextSize.Body,
		TextColor3 = C.Gold,
		Stroke = true,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = banner,
	})
	Widgets.Countdown(
		weather.time,
		function()
			return tonumber(StoreKit.tbl(ctx.Store, "global.Weather").endsAt)
		end,
		Format.clock,
		function()
			refreshWeather()
		end
	)
	targets.weather = banner

	-- Left stack
	local left = Tiles.col({
		Name = "LeftStack",
		Position = UDim2.fromOffset(16, 72),
		Size = UDim2.fromOffset(150, 370),
		Parent = root,
	}, 10)
	sideButton(left, "Shop", "Shop", C.Orange, Icon.new("coin", 28), 1, function()
		openScreen("EggShop")
	end)
	sideButton(left, "Eggs", "Eggs", C.Pink, MonsterIcon.egg("royal", 30), 2, function()
		openScreen("Incubators")
	end)
	sideButton(left, "Monsters", "Monsters", C.Green, previewIcon("mossbun", 32), 3, function()
		openScreen("Monsters")
	end)
	sideButton(left, "Codex", "Codex", C.Blue, previewIcon("zappip", 32), 4, function()
		openScreen("Codex")
	end)
	sideButton(left, "Market", "Market", C.Orange, Icon.new("coin", 28), 5, function()
		openScreen("Market")
	end, Config.Market.Unlock)

	-- Right stack
	local right = Tiles.col({
		Name = "RightStack",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 72),
		Size = UDim2.fromOffset(150, 440),
		Parent = root,
	}, 10, Enum.HorizontalAlignment.Right)
	sideButton(right, "Expeditions", "Expeditions", C.Green, previewIcon("bubblin", 30), 1, function()
		openScreen("Expeditions")
	end, "expeditions").button.Label.TextSize = Theme.TextSize.Small
		+ 1

	-- Stampede card
	local card = New("TextButton", {
		Name = "Stampede",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.Dark,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromOffset(140, 58),
		LayoutOrder = 2,
		Parent = right,
	}, { Create.Corner(Theme.Radius.Button), Create.Stroke(2.5, C.White, 0.1) })
	stampede.card = card
	stampede.stroke = card:FindFirstChildOfClass("UIStroke")
	stampede.iconHolder = Tiles.frame({ Position = UDim2.fromOffset(6, 9), Size = UDim2.fromOffset(40, 40), Parent = card })
	stampede.title = Create.Text({
		Text = "STAMPEDE",
		TextSize = Theme.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(50, 6),
		Size = UDim2.new(1, -54, 0, 22),
		TextScaled = true,
		Parent = card,
	})
	stampede.time = Create.Text({
		Text = "",
		TextSize = Theme.TextSize.Body,
		TextColor3 = C.Gold,
		Stroke = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(50, 28),
		Size = UDim2.new(1, -54, 0, 24),
		Parent = card,
	})
	local stampedeEntry = { lockKey = Config.Boss.Unlock, gui = card, color = C.Dark }
	stampedeEntry.badge = Tiles.badge(card)
	local stampedeLock = Icon.new("lock", 24)
	stampedeLock.AnchorPoint = Vector2.new(0.5, 0.5)
	stampedeLock.Position = UDim2.fromOffset(4, 4)
	stampedeLock.ZIndex = 30
	stampedeLock.Parent = card
	stampedeEntry.lockIcon = stampedeLock
	stampedeEntry.button = {
		SetColor = function() end,
	}
	buttons.Stampede = stampedeEntry
	card.Activated:Connect(function()
		if isLocked(stampedeEntry) then
			ctx:Toast(StoreKit.lockText(stampedeEntry.lockKey), "info")
			Anim.shake(card)
			return
		end
		openScreen("Boss")
	end)

	sideButton(right, "Quests", "Quests", C.Orange, Icon.new("star", 28), 3, function()
		openScreen("Quests")
	end)
	sideButton(right, "Breeding", "Breeding", C.Purple, previewIcon("hushling", 30), 4, function()
		openScreen("Breeding")
	end, Config.Breeding.Unlock)
	sideButton(right, "HallOfFame", "Hall of Fame", C.Gold, Icon.new("stardust", 28), 5, function()
		openScreen("HallOfFame")
	end, Config.HallOfFame.Unlock).button.Label.TextSize =
		Theme.TextSize.Small
	sideButton(right, "Leaderboards", "Boards", Color3.fromHex("#D49A12"), Icon.new("trophy", 28), 6, function()
		openScreen("Leaderboards")
	end)
	sideButton(right, "Clubs", "Clubs", Color3.fromHex("#2BA89A"), Icon.new("friendship", 26), 7, function()
		openScreen("Clubs")
	end, Config.Clubs.Unlock)

	-- Bottom-centre
	local bottom = Tiles.row({
		Name = "BottomBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(640, 72),
		Parent = root,
	}, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
	local ranchButton = Button.new({
		Name = "Ranch",
		Text = "Ranch",
		Color = C.Orange,
		Size = UDim2.fromOffset(130, 56),
		LayoutOrder = 1,
		Parent = bottom,
		OnClick = function()
			openScreen("Ranch")
		end,
	})
	buttons.Ranch = { gui = ranchButton.Root, button = ranchButton, color = C.Orange }
	local collectButton = Button.new({
		Name = "Collect",
		Text = "Collect all",
		Color = C.Green,
		Size = UDim2.fromOffset(310, 68),
		TextSize = Theme.TextSize.Button + 2,
		Icon = Icon.new("coin", 32),
		LayoutOrder = 2,
		Parent = bottom,
		OnClick = function()
			-- Hold the coin counter so it counts up as the coins land, not when the reply does.
			local kit = ctx:GetController("Celebrate")
			local hold = kit and kit:Hold({ "coins" })
			local ok, res = StoreKit.request(ctx, "Ranch.CollectAll")
			local coins = if ok and type(res) == "table" then tonumber(res.coins) or 0 else 0
			if coins > 0 then
				ctx:Sound("CoinCollect")
				if kit then
					kit:Reward({ { kind = "coins", amount = coins } }, { from = collect.button.Root, hold = hold })
				else
					ctx:Toast("+" .. Format.short(coins) .. " coins", "reward")
				end
			elseif hold then
				hold:Release()
			end
			if ok then
				if coins <= 0 then
					ctx:Toast("The jars are empty. Come back soon!", "info")
				end
				collect.last = -1
			end
		end,
	})
	collect.button = collectButton
	buttons.Collect = { gui = collectButton.Root, button = collectButton, color = C.Green }
	local storeButton = Button.new({
		Name = "Store",
		Text = "Store",
		Color = C.Pink,
		Size = UDim2.fromOffset(130, 56),
		Icon = Icon.new("gem", 24),
		LayoutOrder = 3,
		Parent = bottom,
		OnClick = function()
			openScreen("Store")
		end,
	})
	buttons.Store = { gui = storeButton.Root, button = storeButton, color = C.Pink, badge = Tiles.badge(storeButton.Root) }

	centre = { bottom }
end

-- Market mail -------------------------------------------------------------------------

-- "m:<line>:<rarity>:<variant>" / "e:<eggType>" (Config.Market.ItemKey) → "Rare Golden Cindlet".
local function marketItemName(key: string?): string
	local eggType = string.match(tostring(key), "^e:(.+)$")
	if eggType then
		local def = Config.Eggs.ById[eggType]
		return if def then def.name else "egg"
	end
	local line, rarity, variant = string.match(tostring(key), "^m:([^:]+):(%d+):(%d+)$")
	local def = line and Config.Species.ById[line]
	if not def then
		return "item"
	end
	local first = def.forms[1]
	local v = Config.Rarities.Variants[tonumber(variant) or 0]
	local parts = { Theme.RarityName(tonumber(rarity) or 1) }
	if v and (tonumber(variant) or 0) > 0 then
		table.insert(parts, v.name)
	end
	table.insert(parts, if first and first.name then first.name else line)
	return table.concat(parts, " ")
end

local function onMailCollected(payload)
	if type(payload) ~= "table" then
		return
	end
	local sold = if type(payload.sold) == "table" then payload.sold else {}
	local coins = tonumber(payload.coins) or 0
	if #sold == 1 and type(sold[1]) == "table" then
		local sale = sold[1]
		ctx:Toast(
			string.format(
				"Your %s sold for %s! +%s coins",
				if type(sale.name) == "string" and sale.name ~= "" then sale.name else marketItemName(sale.key),
				Format.short(tonumber(sale.price) or 0),
				Format.short(tonumber(sale.proceeds) or coins)
			),
			"reward"
		)
	elseif #sold > 1 then
		ctx:Toast(string.format("%d market sales! +%s coins", #sold, Format.short(coins)), "reward")
	elseif coins > 0 then
		ctx:Toast("+" .. Format.short(coins) .. " coins from the market", "reward")
	end
	if #sold > 0 or coins > 0 then
		ctx:Sound("CoinCollect")
	end
	local returned = tonumber(payload.returned) or 0
	if returned > 0 then
		ctx:Toast(string.format("%d market item%s came back to you", returned, if returned == 1 then "" else "s"), "info")
	end
end

-- Public -----------------------------------------------------------------------------

function Hud:GetTarget(name: string): GuiObject?
	local key = TARGET_ALIAS[name] or name
	if key == "Weather" then
		return targets.weather
	end
	local entry = buttons[key]
	if entry then
		return entry.gui
	end
	return targets[name]
end

function Hud:Flash(name: string)
	flash(name)
end

function Hud:HoldCounter(kind: string)
	local state = pills[kind]
	if state then
		state.hold()
	end
end

function Hud:ReleaseCounter(kind: string, seconds: number?)
	local state = pills[kind]
	if state then
		state.release(seconds)
	end
end

function Hud:PulseCounter(kind: string)
	local state = pills[kind]
	if state then
		Anim.pulse(state.pill.Root, 0.12)
	end
end

function Hud.Init(context)
	ctx = context
	build()
	ctx.Store:Observe("profile.Currency", refreshCurrency)
	ctx.Store:Observe("session.Boss", function()
		if ctx.Store.Ready then
			refreshStampede(ctx:Now())
		end
	end)
	ctx.Store:Observe("profile.Progression", refreshLevel)
	ctx.Store:Observe("global.Weather", refreshWeather)
	ctx.Store:Observe("profile.Monsters.list", refreshMonsters)
	ctx.Store:Observe("profile.Quests", refreshBadges)
	ctx.Store:Observe("profile.Expeditions.slots", refreshBadges)
	ctx.Store:Observe("profile.Eggs.slots", refreshBadges)
	ctx.Bus:Subscribe("Hud.Flash", flash)
	ctx.Net:On("Market.MailCollected", onMailCollected)
	ctx.Router.Opened:Connect(refreshCentre)
	ctx.Router.Closed:Connect(refreshCentre)
	refreshLevel()

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.5 then
			return
		end
		acc = 0
		if not ctx.Store.Ready then
			return
		end
		local now = ctx:Now()
		refreshCollect(now)
		refreshStampede(now)
		-- The level cap rises on a date: turn "MAX" back into a percentage at that instant.
		local cap = Config.Unlocks.MaxLevelAt(now)
		if cap ~= shownCap then
			shownCap = cap
			refreshLevel()
		end
		refreshBadges()
		if weather.frame.Visible ~= (weatherDef() ~= nil and ctx.Router:Current() == nil) then
			refreshWeather()
		end
	end)
end

function Hud.Start() end

return Hud
