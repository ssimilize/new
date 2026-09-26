--[[
	LoginStreak (glow-up): the daily streak calendar. Opened from the HUD's Daily button and,
	once per day on join, by the DailyLogin controller (after Welcome Back, never during the
	tutorial).

	  header      streak length · shield state (ready / used today / refills Monday)
	  7 day cards the looping calendar (Config.LoginStreak.Days); claimed days ticked, today
	              highlighted, day 7 gold
	  milestones  the 28-day track (days claimed, kept when a streak restarts) with 7/14/21/28
	  today       what the claim pays (ladder eggs and income coins previewed like the server)
	  Claim       → LoginStreak.Claim; the rewards arrive as the usual reward card
	  Reminders   on/off (only when the server has reminders on) → Reminders.SetOptIn

	Everything is previewed with Logic/LoginStreak, the same rules the server claims with.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Streak = require(Shared.Logic.LoginStreak)

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

local New = Create.New
local C = Theme.Colors

local CARD_W, CARD_H = 84, 112

local LoginStreak = { Name = "LoginStreak" }

local function itemIcon(item, size: number): GuiObject
	if item.kind == "egg" and Config.Eggs.ById[item.id] then
		return MonsterIcon.egg(item.id, size)
	elseif item.kind == "accessory" then
		return Icon.new("star", size)
	end
	return Icon.new(StoreKit.iconFor(item.kind or "coins"), size)
end

local function itemText(item, income: number): string
	if item.kind == "egg" and Config.Eggs.ById[item.id] then
		return Config.Eggs.ById[item.id].name
	elseif item.kind == "accessory" and Config.Accessories.ById[item.id] then
		return Config.Accessories.ById[item.id].name
	elseif item.kind == "coins" and item.seconds then
		return "+" .. Format.short(math.max(100, income * item.seconds))
	end
	return "+" .. Format.short(tonumber(item.amount) or 0)
end

function LoginStreak.Build(ctx)
	local store = ctx.Store
	local days = Config.LoginStreak.Days

	local panel = Panel.new({
		Title = "Daily streak",
		Color = C.Gold,
		Size = UDim2.fromOffset(700, 480),
		OnClose = function()
			ctx.Router:Close("LoginStreak")
		end,
	})
	local header = Tiles.label({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Body + 2,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = panel.Body,
	})
	local shieldText = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = panel.Body,
	})
	local cards = Tiles.row({
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 0, CARD_H + 8),
		Parent = panel.Body,
	}, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

	local cardViews = {}
	for i in days do
		local big = i == Config.LoginStreak.BigDay
		local card = Tiles.card({ Size = UDim2.fromOffset(if big then CARD_W + 12 else CARD_W, CARD_H), LayoutOrder = i, Parent = cards })
		local stroke = Create.Stroke(3)
		stroke.Color = C.Gold
		stroke.Enabled = false
		stroke.Parent = card
		Tiles.label({
			Text = string.format("Day %d", i),
			TextSize = Theme.TextSize.Small,
			TextColor3 = if big then C.Gold else C.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0, 20),
			Parent = card,
		})
		local iconHolder = New("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 26),
			Size = UDim2.fromOffset(44, 44),
			Parent = card,
		})
		local amount = Tiles.label({
			Text = "",
			TextSize = Theme.TextSize.Small,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			Position = UDim2.fromOffset(2, 74),
			Size = UDim2.new(1, -4, 0, 20),
			Parent = card,
		})
		local tick = Tiles.label({
			Text = "✓",
			Font = Theme.Fonts.Display,
			TextSize = Theme.TextSize.Title,
			TextColor3 = C.Green,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(48, 40),
			Visible = false,
			ZIndex = 5,
			Parent = card,
		})
		cardViews[i] = { card = card, stroke = stroke, icon = iconHolder, amount = amount, tick = tick }
	end

	local track = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(0, 178),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = panel.Body,
	})
	local bar = Widgets.Bar({ Position = UDim2.fromOffset(0, 202), Size = UDim2.new(1, 0, 0, 18), Color = C.Gold, Parent = panel.Body })
	local marks = {}
	for i, milestone in Config.LoginStreak.Milestones do
		local x = milestone.day / Config.LoginStreak.TrackLength
		marks[i] = Tiles.label({
			Text = tostring(milestone.day),
			TextSize = Theme.TextSize.Small,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(if i == #Config.LoginStreak.Milestones then 1 else 0.5, 0),
			Position = UDim2.new(x, 0, 0, 222),
			Size = UDim2.fromOffset(40, 20),
			Parent = panel.Body,
		})
	end

	local todayTitle = Tiles.label({
		Text = "Today's reward",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 246),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = panel.Body,
	})
	local todayRow = Tiles.row({
		Position = UDim2.fromOffset(0, 270),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = panel.Body,
	}, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

	local buttons = Tiles.row(
		{ Position = UDim2.fromOffset(0, 318), Size = UDim2.new(1, 0, 0, 60), Parent = panel.Body },
		14,
		Enum.HorizontalAlignment.Center
	)
	local claim = Button.new({
		Text = "Claim",
		Color = C.Green,
		Size = UDim2.fromOffset(230, 58),
		TextSize = Theme.TextSize.Button + 2,
		LayoutOrder = 1,
		Parent = buttons,
	})
	local remind = Button.new({
		Text = "Reminders: Off",
		Color = C.Gray,
		Size = UDim2.fromOffset(210, 58),
		TextSize = Theme.TextSize.Body,
		LayoutOrder = 2,
		Parent = buttons,
	})

	local function isUnlocked(key: string): boolean
		return StoreKit.isUnlocked(store, key)
	end

	local function fillIcon(holder: Frame, items)
		Tiles.clear(holder)
		local first = items[1]
		if first then
			local icon = itemIcon(first, 44)
			icon.Parent = holder
		end
	end

	local function fillToday(items, income: number)
		Tiles.clear(todayRow)
		for i, item in items do
			if i > 5 then
				break
			end
			local entry = New("Frame", {
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 40),
				LayoutOrder = i,
				Parent = todayRow,
			}, { Create.List("x", 5, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
			local icon = itemIcon(item, 34)
			icon.LayoutOrder = 1
			icon.Parent = entry
			Tiles.label({
				Text = itemText(item, income),
				TextSize = Theme.TextSize.Small,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				TextWrapped = false,
				LayoutOrder = 2,
				Parent = entry,
			})
		end
	end

	local function render()
		local state = StoreKit.tbl(store, "profile.LoginStreak")
		local today = ctx:Now() // 86400
		local preview = Streak.Preview(state, today)
		local income = tonumber(StoreKit.tbl(store, "session.Ranch").income) or 0
		local claimed = not preview.canClaim
		local pos = tonumber(state.pos) or 0
		-- Days already ticked in this loop, and the card that is (or was) today.
		local done, current
		if claimed then
			done, current = pos, pos
		elseif preview.restarted or preview.pos == 1 then
			done, current = 0, 1
		else
			done, current = preview.pos - 1, preview.pos
		end
		for i, view in cardViews do
			local items = Streak.Resolve(days[i], isUnlocked)
			fillIcon(view.icon, items)
			-- Day cards are narrow: an egg's icon says which egg, the label only how many.
			local first = items[1]
			if first == nil then
				view.amount.Text = ""
			elseif first.kind == "egg" then
				view.amount.Text = "×" .. tostring(first.amount or 1)
			else
				view.amount.Text = itemText(first, income)
			end
			view.tick.Visible = i <= done
			view.stroke.Enabled = i == current
		end

		local streak = if claimed then tonumber(state.streak) or 0 elseif preview.restarted then 0 else tonumber(state.streak) or 0
		header.Text = if streak > 0 then string.format("🔥 Streak: %d", streak) else "Start your streak today!"
		if claimed and (tonumber(state.savedDay) or 0) == today then
			shieldText.Text = "🛡 Your shield saved your streak!"
		elseif preview.restarted then
			shieldText.Text = "Streak restarted · milestones kept"
		elseif preview.shields > 0 then
			shieldText.Text = "🛡 Shield ready: it saves your streak if you miss a day"
		else
			shieldText.Text = "🛡 No shield · a new one comes every Monday"
		end

		local shownTrack = if claimed then tonumber(state.track) or 0 else preview.track - 1
		track.Text = string.format("Milestones %d/%d", shownTrack, Config.LoginStreak.TrackLength)
		bar:SetValue(shownTrack / Config.LoginStreak.TrackLength)
		for i, milestone in Config.LoginStreak.Milestones do
			marks[i].TextColor3 = if shownTrack >= milestone.day then C.Gold else C.TextMuted
		end

		local shown = if claimed then Streak.Preview(state, today + 1) else preview
		fillToday(Streak.Resolve(Streak.Items(shown, tonumber(state.cycles) or 0), isUnlocked), income)
		todayTitle.Text = if claimed then "Tomorrow's reward" else "Today's reward"

		claim:SetDisabled(claimed)
		claim:SetText(if claimed then "Come back tomorrow!" else "Claim")
		local reminders = StoreKit.tbl(store, "session.Reminders")
		local on = StoreKit.tbl(store, "profile.Reminders").on == true
		remind:SetVisible(reminders.available == true)
		remind:SetText(if on then "Reminders: On" else "Reminders: Off")
		remind:SetColor(if on then C.Blue else C.Gray)
	end

	local busy = false
	claim:SetOnClick(function()
		if busy then
			return
		end
		busy = true
		local ok = StoreKit.request(ctx, "LoginStreak.Claim")
		busy = false
		if ok then
			ctx:Sound("CoinCollect")
			render()
		end
	end)
	remind:SetOnClick(function()
		if busy then
			return
		end
		busy = true
		local on = StoreKit.tbl(store, "profile.Reminders").on == true
		local want = not on
		if want then
			local daily = if ctx.GetController then ctx:GetController("DailyLogin") else nil
			if daily and daily.AskOptIn then
				daily:AskOptIn()
			end
		end
		StoreKit.request(ctx, "Reminders.SetOptIn", { on = want })
		busy = false
		render()
	end)

	local watch = StoreKit.watch(
		store,
		{ "profile.LoginStreak", "profile.Reminders", "session.Reminders", "profile.Progression", "session.Ranch" },
		render
	)

	return {
		Root = panel.Root,
		Open = function()
			watch.Start()
			render()
		end,
		Close = function()
			watch.Stop()
		end,
	}
end

return LoginStreak
