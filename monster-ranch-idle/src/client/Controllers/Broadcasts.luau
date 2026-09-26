--[[
	Broadcasts controller (C3).

	Social.Broadcast events become banners at the top of ctx.UI.Overlay (at most 3 at once,
	coloured by kind, with a MonsterIcon when an appearance is included). Respects
	profile.Settings.hideBroadcasts (hiding also clears the visible banners).

	Also owns two other always-on server-event presentations for C3 features:
	  · Boss.Result → the Stampede result popup (rank, share, rewards, egg), shown even when
	    the Boss screen is closed. At the arena (StampedeArena:Fountain) the popup waits for the
	    loot fountain out of the fallen giant, which already flew the rewards.
	  · profile.Settings.lowGraphics → UI/Anim.enabled (reduced motion).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Logic.Format)

local UI = script.Parent.Parent.UI
local Create = require(UI.Create)
local Theme = require(UI.Theme)
local Anim = require(UI.Anim)
local MonsterIcon = require(UI.Components.MonsterIcon)
local Util = require(UI.Screens.Parts.Util)
local Dialog = require(UI.Screens.Parts.Dialog)

local New = Create.New
local C = Theme.Colors

local MAX_BANNERS = 3
local LIFETIME = 6

local Broadcasts = {
	Name = "Broadcasts",
	Dependencies = {},
}

local ctx
local container: Frame
local hidden = false
local order = 0

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("#FF7A7A")),
	ColorSequenceKeypoint.new(0.28, Color3.fromHex("#FFB84D")),
	ColorSequenceKeypoint.new(0.52, Color3.fromHex("#5FC96B")),
	ColorSequenceKeypoint.new(0.76, Color3.fromHex("#4FA3F0")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("#B06BF0")),
})

-- Colour for a broadcast kind. Kinds are free-form strings from Social, so match loosely.
local function styleFor(kind: string, text: string): (Color3, boolean)
	local k = string.lower(kind or "") .. " " .. string.lower(text or "")
	if string.find(k, "rainbow") or string.find(k, "aurora") or string.find(k, "mythic") or string.find(k, "prismatic") then
		return C.Pink, true
	elseif string.find(k, "golden") then
		return Color3.fromHex("#D49A12"), false
	elseif string.find(k, "hybrid") or string.find(k, "discover") then
		return C.Purple, false
	elseif string.find(k, "huge") or string.find(k, "weight") then
		return C.Orange, false
	elseif string.find(k, "legendary") then
		return Theme.Rarity(5), false
	elseif string.find(k, "epic") then
		return Theme.Rarity(4), false
	elseif string.find(k, "weather") or string.find(k, "totem") or string.find(k, "starfall") or string.find(k, "storm") then
		return C.Blue, false
	elseif string.find(k, "boss") or string.find(k, "stampede") then
		return C.Red, false
	elseif string.find(k, "trade") then
		return C.Green, false
	end
	return Color3.fromHex("#1F2B24"), false
end

local function banners(): { GuiObject }
	local list = {}
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	return list
end

local function remove(banner: GuiObject)
	if not banner.Parent then
		return
	end
	if not Anim.enabled then
		banner:Destroy()
		return
	end
	Anim.tween(banner, { BackgroundTransparency = 1 }, 0.25)
	for _, d in banner:GetDescendants() do
		if d:IsA("TextLabel") then
			Anim.tween(d, { TextTransparency = 1 }, 0.25)
		end
	end
	task.delay(0.28, function()
		banner:Destroy()
	end)
end

local function show(payload)
	if hidden or type(payload) ~= "table" or type(payload.text) ~= "string" then
		return
	end
	local current = banners()
	for i = 1, #current - MAX_BANNERS + 1 do
		current[i]:Destroy()
	end
	order += 1
	local color, rainbow = styleFor(payload.kind, payload.text)
	local banner = New("Frame", {
		Name = "Broadcast",
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(560, 44),
		LayoutOrder = order,
		Parent = container,
	}, {
		Create.Corner(12),
		Create.Stroke(2.5),
		Create.Padding(4, 14, 4, 8),
		Create.List("x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	if rainbow then
		local g = Instance.new("UIGradient")
		g.Color = RAINBOW
		g.Parent = banner
	end
	local ap = payload.appearance
	if type(ap) == "table" and Config.Species.ById[ap.line] then
		local ok, icon = pcall(MonsterIcon.new, ap, 36)
		if ok then
			icon.LayoutOrder = 1
			icon.Parent = banner
		end
	end
	local isMe = payload.userId == ctx.Player.UserId
	Create.Text({
		Text = payload.text,
		TextSize = Theme.TextSize.Small + 1,
		TextColor3 = if isMe then C.Gold else C.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Size = UDim2.new(1, -48, 1, 0),
		LayoutOrder = 2,
		Parent = banner,
	})
	Anim.popIn(banner, 0.2)
	task.delay(LIFETIME, function()
		remove(banner)
	end)
end

-- reward = false: the rewards already flew (the arena's loot fountain).
local function showResultPopup(payload, reward: boolean)
	Dialog.show(ctx.UI.Top, {
		Title = "Stampede over!",
		Color = Color3.fromHex("#C0573E"),
		Size = Vector2.new(560, if payload.egg then 400 else 340),
		Build = function(content)
			Create.Text({
				Text = if payload.rank and payload.rank > 0 then string.format("#%d", payload.rank) else "Thanks for joining!",
				TextSize = Theme.TextSize.Hero,
				Size = UDim2.new(1, 0, 0, 48),
				LayoutOrder = 2,
				Parent = content,
			})
			Util.text({
				Text = string.format(
					"%s of the damage · %s dealt",
					Format.percent(payload.share or 0, 1),
					Format.short(math.floor(payload.damage or 0))
				),
				TextSize = Theme.TextSize.Body,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = 3,
				Parent = content,
			})
			Util.rewardRow(payload.rewards or {}, content, { LayoutOrder = 4, IconSize = 30, Align = Enum.HorizontalAlignment.Center })
			if payload.egg then
				local row = New("Frame", {
					BackgroundColor3 = Color3.fromHex("#FFF0C2"),
					Size = UDim2.new(1, 0, 0, 72),
					LayoutOrder = 5,
					Parent = content,
				}, {
					Create.Corner(12),
					Create.Stroke(2.5, C.Gold),
					Create.List("x", 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
				})
				local egg = MonsterIcon.egg(Config.Boss.Rewards.egg, 60)
				egg.LayoutOrder = 1
				egg.Parent = row
				Util.text({
					Text = "You got a Stampede Egg!",
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Header,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.new(0, 0, 1, 0),
					TextWrapped = false,
					LayoutOrder = 2,
					Parent = row,
				})
			end
		end,
		Buttons = { { Text = "Nice!", Color = C.Green } },
	})
	ctx:Sound("Victory")
	-- The chest's coins and gems fly into the HUD; a top-3 finish is a big moment.
	local kit = ctx:GetController("Celebrate")
	if reward and kit and type(payload.rewards) == "table" then
		local rank = tonumber(payload.rank) or 0
		kit:Reward(payload.rewards, { minSize = if rank >= 1 and rank <= 3 then "big" else nil })
	end
end

local function showBossResult(payload)
	if type(payload) ~= "table" then
		return
	end
	-- Glow-up U: at the arena the loot fountains out of the giant first; the popup follows.
	local arena = ctx:GetController("StampedeArena")
	if arena and arena:Fountain(payload, function(rewarded: boolean)
		showResultPopup(payload, not rewarded)
	end) then
		return
	end
	showResultPopup(payload, true)
end

function Broadcasts.Init(context)
	ctx = context
	container = New("Frame", {
		Name = "Broadcasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		-- Top centre is shared: HUD weather banner (y 12–52), then broadcasts, while
		-- toasts live above the bottom bar (see Components/Toasts).
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.fromOffset(560, MAX_BANNERS * 48),
		Parent = ctx.UI.Overlay,
	}, { Create.List("y", 4, Enum.HorizontalAlignment.Center) })

	ctx.Store:Observe("profile.Settings", function(settings)
		settings = if type(settings) == "table" then settings else {}
		hidden = settings.hideBroadcasts == true
		if hidden then
			for _, banner in banners() do
				banner:Destroy()
			end
		end
		Anim.enabled = settings.lowGraphics ~= true
	end)

	ctx.Net:On("Social.Broadcast", show)
	ctx.Net:On("Boss.Result", showBossResult)
end

function Broadcasts.Start() end

return Broadcasts
