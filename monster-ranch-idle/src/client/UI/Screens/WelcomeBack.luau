--[[
	WelcomeBack (C2): the offline summary (mock-welcome). Opened by the Notifications
	controller whenever session.WelcomeBack.pending turns true.

	  away time, coin total, item cards (session.WelcomeBack.items { kind, text, icon? })
	  Collect → WelcomeBack.Claim { double = false }
	  Watch ad ×2 coins → WelcomeBack.Claim { double = true } (disabled with no welcomeDouble ads left)
	  footer: next Stampede countdown
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

local New = Create.New
local C = Theme.Colors

local WelcomeBack = { Name = "WelcomeBack" }

local KIND_ICONS = {
	coins = "coin",
	jar = "coin",
	gems = "gem",
	food = "food",
	garden = "food",
	treats = "treat",
	xp = "xp",
	expedition = "xp",
	expeditions = "xp",
	friendship = "friendship",
	stardust = "stardust",
}

local function itemIcon(item, size: number): GuiObject
	local icon = item.icon
	if type(icon) == "string" then
		if Config.Eggs.ById[icon] or icon == "starter" then
			return MonsterIcon.egg(icon, size)
		elseif Config.Species.ById[icon] then
			local ok, ap = pcall(Appearance.Preview, icon, 1)
			if ok then
				return MonsterIcon.new(ap, size)
			end
		elseif Config.Species.FormById[icon] then
			local info = Config.Species.FormById[icon]
			local ok, ap = pcall(Appearance.Preview, info.line.id, info.stage, icon)
			if ok then
				return MonsterIcon.new(ap, size)
			end
		end
	end
	local kind = tostring(item.kind or "")
	if kind == "egg" or kind == "eggs" or kind == "hatch" then
		return MonsterIcon.egg("meadow", size)
	end
	return Icon.new(KIND_ICONS[kind] or "star", size)
end

function WelcomeBack.Build(ctx)
	local store = ctx.Store

	local panel = Panel.new({
		Title = "Welcome back, Rancher!",
		Color = C.Green,
		Size = UDim2.fromOffset(640, 460),
		OnClose = function()
			ctx.Router:Close("WelcomeBack")
		end,
	})
	local away = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Body + 1,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = panel.Body,
	})
	local coinCard = Tiles.card({ Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 78), Parent = panel.Body })
	local coinIcon = Icon.new("coin", 52)
	coinIcon.Position = UDim2.fromOffset(14, 13)
	coinIcon.Parent = coinCard
	local coinText = Tiles.label({ Text = "", TextSize = Theme.TextSize.Title, Position = UDim2.fromOffset(80, 6), Size = UDim2.new(1, -90, 0, 38), Parent = coinCard })
	local coinSub = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(80, 44),
		Size = UDim2.new(1, -90, 0, 24),
		Parent = coinCard,
	})
	local items = New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 120),
		Size = UDim2.new(1, 0, 0, 146),
		Parent = panel.Body,
	}, { Create.Grid(Vector2.new(192, 68), 8) })
	local buttons = Tiles.row({ Position = UDim2.fromOffset(0, 276), Size = UDim2.new(1, 0, 0, 62), Parent = panel.Body }, 14, Enum.HorizontalAlignment.Center)
	local collect = Button.new({ Text = "Collect", Color = C.Green, Size = UDim2.fromOffset(200, 58), TextSize = Theme.TextSize.Button + 2, LayoutOrder = 1, Parent = buttons })
	local double = Button.new({ Text = "▶ Watch ad · ×2 coins", Color = C.Orange, Size = UDim2.fromOffset(300, 58), LayoutOrder = 2, Parent = buttons })
	local footer = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Small + 1,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 346),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = panel.Body,
	})

	local function render()
		local wb = StoreKit.tbl(store, "session.WelcomeBack")
		local pending = wb.pending == true
		local seconds = tonumber(wb.awaySeconds) or 0
		local coins = tonumber(wb.coins) or 0
		away.Text = if seconds > 0 then "You were away " .. Format.duration(seconds) else "Your ranch kept going!"
		coinText.Text = "+" .. Format.commas(coins)
		coinSub.Text = if pending then "Your coin jars filled up while you were away." else "All collected. See you next time!"
		Tiles.clear(items)
		local list = StoreKit.asTable(wb.items)
		for i, item in list do
			if i > 6 then
				break
			end
			if type(item) == "table" then
				local card = Tiles.card({ LayoutOrder = i, Parent = items })
				local icon = itemIcon(item, 44)
				icon.AnchorPoint = Vector2.new(1, 0.5)
				icon.Position = UDim2.new(1, -8, 0.5, 0)
				icon.Parent = card
				Tiles.label({
					Text = tostring(item.text or ""),
					TextSize = Theme.TextSize.Small,
					TextYAlignment = Enum.TextYAlignment.Center,
					Position = UDim2.fromOffset(10, 4),
					Size = UDim2.new(1, -64, 1, -8),
					Parent = card,
				})
			end
		end
		items.Visible = #list > 0
		local adsLeft = StoreKit.adsLeft(store, "welcomeDouble", ctx:Now())
		collect:SetDisabled(not pending)
		collect:SetText(if pending then "Collect" else "Collected")
		double:SetVisible(Config.Flags.RewardedAds == true)
		double:SetDisabled(not pending or adsLeft <= 0 or coins <= 0)
		double:SetText(if adsLeft > 0 then "▶ Watch ad · ×2 coins" else "No ads left today")
	end

	local function claim(isDouble: boolean)
		local ok, res = StoreKit.request(ctx, "WelcomeBack.Claim", { double = isDouble })
		if ok then
			local coins = type(res) == "table" and tonumber(res.coins) or 0
			ctx:Sound("CoinCollect")
			if coins > 0 then
				ctx:Toast("+" .. Format.short(coins) .. " coins", "reward")
			end
			ctx.Router:Close("WelcomeBack")
		end
	end
	collect:SetOnClick(function()
		claim(false)
	end)
	double:SetOnClick(function()
		claim(true)
	end)

	local watch = StoreKit.watch(store, { "session.WelcomeBack", "profile.Monetization" }, render)
	local stopFooter

	return {
		Root = panel.Root,
		Open = function()
			watch.Start()
			render()
			if stopFooter then
				stopFooter()
			end
			stopFooter = Widgets.Countdown(footer, function()
				local startsAt = tonumber(store:Get("global.Boss.startsAt"))
				if startsAt and startsAt > ctx:Now() then
					return startsAt
				end
				return math.ceil(ctx:Now() / Config.Boss.Period) * Config.Boss.Period
			end, function(left)
				return "The Stampede starts in " .. Format.clock(left)
			end)
		end,
		Close = function()
			watch.Stop()
			if stopFooter then
				stopFooter()
				stopFooter = nil
			end
		end,
	}
end

return WelcomeBack
