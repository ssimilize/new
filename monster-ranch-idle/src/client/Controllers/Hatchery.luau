--[[
	Hatchery (C2): the full-screen hatch reveal in ctx.UI.Top.

	On every Eggs.Hatched { slot, monster, egg } it queues a reveal:
	  egg wobbles (ViewportFrame + Visuals.EggModel) → cracks with a flash → rarity-coloured
	  burst → the monster (Visuals.MonsterModel) spins in → name, rarity, variant, elements,
	  mutations, traits and weight, with a "Nice!" button.
	Tap anywhere during the animation to skip to the result. "Skip all" clears the queue
	(Eggs.HatchAll can hatch several at once). The first starter hatch offers "Name it"
	(Monsters.Rename).

	Public: Hatchery:IsShowing() -> boolean
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local Appearance = require(Shared.Logic.Appearance)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Focus = require(UI.Focus)
local Button = require(UI.Components.Button)
local Widgets = require(UI.Components.Widgets)
local StoreKit = require(UI.Components.StoreKit)
local Tiles = require(UI.Components.Tiles)
local ViewportMonster = require(UI.Components.ViewportMonster)

local New = Create.New
local C = Theme.Colors

local Hatchery = {
	Name = "Hatchery",
	Dependencies = {},
}

local ctx
local queue = {}
local showing = false
local skipRequested = false

local ui = {} -- built once

local function stepFrame(): number
	return RunService.RenderStepped:Wait()
end

-- Runs fn(alpha) for `seconds`; returns true if the player skipped.
local function animate(seconds: number, fn: (number) -> ()): boolean
	local t0 = os.clock()
	while true do
		if skipRequested then
			return true
		end
		local alpha = math.clamp((os.clock() - t0) / seconds, 0, 1)
		fn(alpha)
		if alpha >= 1 then
			return false
		end
		stepFrame()
	end
end

local function build()
	local root = New("TextButton", {
		Name = "HatchReveal",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.Dark,
		BackgroundTransparency = 0.12,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 50,
		Selectable = false, -- the tap-to-skip backdrop; a gamepad skips with the Skip button
		Parent = ctx.UI.Top,
		Activated = function()
			if showing then
				skipRequested = true
			end
		end,
	})
	ui.root = root

	local stage = New("Frame", {
		Name = "Stage",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -70),
		Size = UDim2.fromOffset(340, 340),
		ZIndex = 51,
		Parent = root,
	})
	ui.rays = New("Frame", {
		Name = "Rays",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 560),
		Visible = false,
		ZIndex = 51,
		Parent = stage,
	})
	for i = 1, 8 do
		New("Frame", {
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 34, 1, 0),
			Rotation = i * 22.5,
			ZIndex = 51,
			Parent = ui.rays,
		}, { Create.Corner(12) })
	end
	ui.burst = New("Frame", {
		Name = "Burst",
		BackgroundColor3 = C.Gold,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 0.25,
		ZIndex = 52,
		Parent = stage,
	}, { Create.Round() })
	ui.vm = ViewportMonster.new({
		Size = UDim2.fromScale(1, 1),
		ZIndex = 53,
		Parent = stage,
	})
	ui.flash = New("Frame", {
		Name = "Flash",
		BackgroundColor3 = C.White,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 60,
		Parent = root,
	})
	ui.hint = Create.Text({
		Text = "Tap to skip",
		TextSize = Theme.TextSize.Body,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(300, 28),
		ZIndex = 55,
		Parent = root,
	})

	-- Result card (bottom).
	local info = New("Frame", {
		Name = "Info",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(760, 236),
		Visible = false,
		ZIndex = 55,
		Parent = root,
	}, { Create.List("y", 6, Enum.HorizontalAlignment.Center) })
	ui.info = info
	ui.name = Create.Text({
		Text = "",
		TextSize = Theme.TextSize.Hero,
		Size = UDim2.new(1, 0, 0, 46),
		LayoutOrder = 1,
		ZIndex = 56,
		Parent = info,
	})
	ui.chips = Tiles.row({ Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 2, ZIndex = 56, Parent = info }, 8, Enum.HorizontalAlignment.Center)
	ui.traits =
		Tiles.row({ Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 3, ZIndex = 56, Parent = info }, 8, Enum.HorizontalAlignment.Center)
	ui.details = Create.Text({
		Text = "",
		TextSize = Theme.TextSize.Body,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 4,
		ZIndex = 56,
		Parent = info,
	})
	-- Naming row (first starter only).
	ui.nameRow =
		Tiles.row({ Size = UDim2.new(1, 0, 0, 50), LayoutOrder = 5, Visible = false, Parent = info }, 10, Enum.HorizontalAlignment.Center)
	ui.nameBox = New("TextBox", {
		Name = "NameBox",
		Text = "",
		PlaceholderText = "Type a name",
		ClearTextOnFocus = false,
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Button,
		TextColor3 = C.Text,
		PlaceholderColor3 = C.TextMuted,
		BackgroundColor3 = C.Card,
		Size = UDim2.fromOffset(300, 48),
		LayoutOrder = 1,
		ZIndex = 57,
		Parent = ui.nameRow,
	}, { Create.Corner(Theme.Radius.Button), Create.Stroke(Theme.Stroke.Button) })
	ui.nameBox:GetPropertyChangedSignal("Text"):Connect(function()
		if #ui.nameBox.Text > 20 then
			ui.nameBox.Text = StoreKit.clip(ui.nameBox.Text, 20)
		end
	end)
	ui.saveName = Button.new({
		Text = "Save name",
		Color = C.Blue,
		Size = UDim2.fromOffset(160, 48),
		LayoutOrder = 2,
		ZIndex = 57,
		Parent = ui.nameRow,
	})

	ui.buttons = Tiles.row({ Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 6, Parent = info }, 14, Enum.HorizontalAlignment.Center)
	ui.nameIt = Button.new({
		Text = "Name it",
		Color = C.Blue,
		Size = UDim2.fromOffset(160, 56),
		LayoutOrder = 1,
		ZIndex = 57,
		Parent = ui.buttons,
	})
	ui.nice = Button.new({
		Text = "Nice!",
		Color = C.Green,
		Size = UDim2.fromOffset(200, 58),
		TextSize = Theme.TextSize.Button + 2,
		LayoutOrder = 2,
		ZIndex = 57,
		Parent = ui.buttons,
	})
	ui.skipAll = Button.new({
		Text = "Skip all",
		Color = C.Gray,
		Size = UDim2.fromOffset(160, 56),
		LayoutOrder = 3,
		ZIndex = 57,
		Parent = ui.buttons,
	})
end

local function fillInfo(m)
	ui.name.Text = Formulas.DisplayName(m)
	Tiles.clear(ui.chips)
	Widgets.RarityChip(m.rarity or 1, ui.chips).LayoutOrder = 1
	local variant = Widgets.VariantChip(m.variant or 0, ui.chips)
	if variant then
		variant.LayoutOrder = 2
	end
	for i, el in Formulas.Elements(m) do
		Widgets.ElementChip(el, ui.chips).LayoutOrder = 2 + i
	end
	for i, mut in StoreKit.asTable(m.muts) do
		Widgets.MutationChip(mut, ui.chips).LayoutOrder = 5 + i
	end
	if Formulas.IsHuge(m) then
		Widgets.Chip({ Text = "HUGE", Color = C.Orange, LayoutOrder = 9, Parent = ui.chips })
	end
	Tiles.clear(ui.traits)
	for i, id in StoreKit.asTable(m.traits) do
		local t = Config.Traits.ById[id]
		if t then
			Widgets.Chip({ Text = t.name, Color = C.Blue, LayoutOrder = i, Parent = ui.traits })
		end
	end
	Widgets.Chip({ Text = "Hidden · ???", Color = C.Gray, LayoutOrder = 9, Parent = ui.traits })
	local stageDef = Config.Economy.Stages[m.stage or 1]
	ui.details.Text = string.format(
		"%s · %s · %s coins/s in a pen",
		if stageDef then stageDef.name else "Baby",
		Format.weight(tonumber(m.weight) or 1),
		Format.short(math.floor(Formulas.CoinRate(m) * 10 + 0.5) / 10)
	)
end

local function burstColor(m): Color3
	if m.variant == 1 then
		return Color3.fromHex(Config.Rarities.Variants[1].color or "#F4C43A")
	end
	return Theme.Rarity(m.rarity or 1)
end

local function reveal(entry)
	local m = entry.monster
	local okAp, ap = pcall(Appearance.Of, m)
	if not okAp then
		return
	end
	skipRequested = false
	ui.info.Visible = false
	ui.hint.Visible = true
	ui.rays.Visible = false
	ui.burst.Size = UDim2.fromOffset(0, 0)
	ui.burst.BackgroundColor3 = burstColor(m)
	ui.flash.BackgroundTransparency = 1
	ui.vm:SetSpin(0)
	ui.vm:SetEgg(if entry.egg and (Config.Eggs.ById[entry.egg] or entry.egg == "starter") then entry.egg else "meadow")
	ui.vm:SetZoom(1.35)
	ui.root.Visible = true
	Anim.popIn(ui.root, 0.2)
	Focus.push(ui.root) -- a gamepad cursor stays on the reveal's buttons

	-- 1. Wobble, getting stronger.
	local skipped = animate(1.5, function(a)
		ui.vm:SetRoll(math.sin(a * 30) * (0.05 + a * 0.3))
	end)
	-- 2. Crack: a hard shake and a flash.
	if not skipped then
		ctx:Sound("EggCrack")
		skipped = animate(0.35, function(a)
			ui.vm:SetRoll(math.sin(a * 60) * 0.35 * (1 - a))
			ui.vm:SetZoom(1.35 - a * 0.25)
		end)
	end
	-- 3. Burst + monster spinning in.
	ui.flash.BackgroundTransparency = 0
	Anim.tween(ui.flash, { BackgroundTransparency = 1 }, 0.45)
	ui.vm:SetAppearance(ap)
	ui.rays.Visible = true
	local rarity = tonumber(m.rarity) or 1
	if rarity >= 5 then
		ctx:Sound("HatchLegendary")
	elseif rarity >= 3 then
		ctx:Sound("HatchRare")
	else
		ctx:Sound("HatchCommon")
	end
	local burstSize = 300 + rarity * 30
	if not skipped then
		skipped = animate(0.8, function(a)
			local e = 1 - (1 - a) ^ 3
			ui.vm:SetYaw((1 - e) * math.pi * 4)
			ui.vm:SetZoom(3 - 2 * e)
			ui.burst.Size = UDim2.fromOffset(burstSize * e, burstSize * e)
			ui.rays.Rotation = a * 40
		end)
	end
	-- Final pose (also the skip target).
	ui.vm:SetYaw(0)
	ui.vm:SetZoom(1)
	ui.vm:SetSpin(0.6)
	ui.burst.Size = UDim2.fromOffset(burstSize, burstSize)
	ui.hint.Visible = false
	fillInfo(m)
	ui.info.Visible = true
	Anim.popIn(ui.info, 0.25)
	skipRequested = false
end

local function hide()
	ui.root.Visible = false
	Focus.remove(ui.root)
	ui.vm:Clear()
	showing = false
end

local playNext

local function setupButtons(entry)
	local m = entry.monster
	-- The starter is the first monster ever (its egg type is "starter").
	local unnamed = m.name == nil or m.name == ""
	local isStarter = unnamed
		and (
			entry.egg == "starter"
			or (StoreKit.num(ctx.Store, "profile.Monsters.nextId") <= 2 and entry.egg ~= nil and not Config.Eggs.ById[entry.egg])
		)
	ui.nameIt:SetVisible(isStarter)
	ui.nameRow.Visible = false
	ui.skipAll:SetVisible(#queue > 0)
	ui.skipAll:SetText(string.format("Skip all (%d)", #queue))
	ui.nice:SetText(if #queue > 0 then "Nice! Next" else "Nice!")
	ui.nice:SetOnClick(function()
		playNext()
	end)
	ui.skipAll:SetOnClick(function()
		local skippedCount = #queue
		table.clear(queue)
		hide()
		if skippedCount > 0 then
			ctx:Toast(string.format("%d more monsters hatched. See them in Monsters.", skippedCount), "success")
		end
	end)
	ui.nameIt:SetOnClick(function()
		ui.nameRow.Visible = true
		ui.nameIt:SetVisible(false)
		ui.nameBox.Text = ""
		ui.nameBox:CaptureFocus()
	end)
	ui.saveName:SetOnClick(function()
		local text = string.gsub(ui.nameBox.Text, "^%s+", "")
		text = string.gsub(text, "%s+$", "")
		if text == "" then
			ctx:Toast("Type a name first", "error")
			return
		end
		local ok, res = StoreKit.request(ctx, "Monsters.Rename", { id = m.id, name = text })
		if ok then
			local final = type(res) == "table" and res.name or text
			ui.name.Text = if final ~= "" then final else Formulas.DisplayName(m)
			ui.nameRow.Visible = false
			ctx:Toast("Say hi to " .. ui.name.Text .. "!", "success")
		end
	end)
end

function playNext()
	local entry = table.remove(queue, 1)
	if not entry then
		hide()
		return
	end
	showing = true
	local ok, err = xpcall(function()
		ui.buttons.Visible = true
		setupButtons(entry)
		reveal(entry)
	end, debug.traceback)
	if not ok then
		warn("[Hatchery] reveal failed: " .. tostring(err))
		playNext()
	end
end

local function onHatched(payload)
	if type(payload) ~= "table" or type(payload.monster) ~= "table" then
		return
	end
	local m = payload.monster
	if not (m.line and Config.Species.ById[m.line]) then
		return
	end
	table.insert(queue, { monster = m, egg = payload.egg, slot = payload.slot })
	if showing then
		ui.skipAll:SetVisible(true)
		ui.skipAll:SetText(string.format("Skip all (%d)", #queue))
		ui.nice:SetText("Nice! Next")
	else
		task.spawn(playNext)
	end
end

function Hatchery:IsShowing(): boolean
	return showing
end

function Hatchery.Init(context)
	ctx = context
	build()
	ctx.Net:On("Eggs.Hatched", onHatched)
end

function Hatchery.Start() end

return Hatchery
