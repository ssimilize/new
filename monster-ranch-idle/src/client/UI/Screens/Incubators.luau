--[[
	Incubators (C2): incubator slots and the egg inventory.

	  slots 1..4   locked beyond session.Eggs.slotCount (next unlock level or the Extra
	               Incubator pass); empty → "Place egg" (arms that slot); filled → egg,
	               progress bar and timer, READY → Eggs.Hatch; Hatch Rush rewarded ad
	               (ads left = cap − profile.Monetization.ads.counts.hatchRush, same UTC day)
	  header       Fill slots → Eggs.PlaceAuto · Hatch all → Eggs.HatchAll
	  inventory    profile.Eggs.list grouped by type; tap → Eggs.Place into the armed slot or
	               the first free usable slot (oldest egg of that type first)
	The hatch reveal itself is the Hatchery controller (Eggs.Hatched).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)
local Tiles = require(UI.Components.Tiles)

local C = Theme.Colors

local Incubators = { Name = "Incubators" }

local SLOT_W, SLOT_H = 224, 196

local function eggName(eggType: string?): string
	if eggType == "starter" then
		return "Starter Egg"
	end
	local def = eggType and Config.Eggs.ById[eggType]
	return if def then def.name else "Egg"
end

function Incubators.Build(ctx)
	local store = ctx.Store
	local armedSlot: number? = nil
	local timers = {} -- { bar, startedAt, endsAt, ready }

	local panel = Panel.new({
		Title = "Incubators",
		Color = C.Pink,
		Size = UDim2.fromOffset(980, 490),
		OnClose = function()
			ctx.Router:Close("Incubators")
		end,
	})
	local fill = Button.new({ Text = "Fill slots", Color = C.Blue, Size = UDim2.fromOffset(140, 44), LayoutOrder = 1, Parent = panel.HeaderRight })
	local hatchAll = Button.new({ Text = "Hatch all", Color = C.Green, Size = UDim2.fromOffset(150, 44), LayoutOrder = 2, Parent = panel.HeaderRight })

	local slotsRow = Tiles.row({ Size = UDim2.new(1, 0, 0, SLOT_H), Parent = panel.Body }, 16, Enum.HorizontalAlignment.Center)
	local infoLabel = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Body,
		Position = UDim2.fromOffset(4, SLOT_H + 8),
		Size = UDim2.new(0.5, 0, 0, 26),
		Parent = panel.Body,
	})
	local hintLabel = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, SLOT_H + 8),
		Size = UDim2.new(0.5, 0, 0, 26),
		Parent = panel.Body,
	})
	local grid = Widgets.Scroll({
		Position = UDim2.fromOffset(0, SLOT_H + 38),
		Size = UDim2.new(1, 0, 1, -(SLOT_H + 38)),
		Cell = Vector2.new(100, 128),
		Padding = 10,
		Parent = panel.Body,
	})

	local refresh

	local function slotsState()
		return StoreKit.tbl(store, "profile.Eggs.slots"), StoreKit.slotCount(store)
	end

	local function freeSlot(): number?
		local slots, count = slotsState()
		if armedSlot and armedSlot <= count then
			local s = slots[armedSlot]
			if type(s) ~= "table" or not s.type then
				return armedSlot
			end
		end
		for i = 1, count do
			local s = slots[i]
			if type(s) ~= "table" or not s.type then
				return i
			end
		end
		return nil
	end

	-- Texts for locked slots, in order: level unlocks not reached yet, then the pass.
	local function lockedTexts(): { string }
		local texts = {}
		local levels = {}
		for _, key in Config.Economy.Incubators.slotUnlocks do
			if not StoreKit.isUnlocked(store, key) then
				table.insert(levels, StoreKit.unlockLevel(key))
			end
		end
		table.sort(levels)
		for _, lv in levels do
			table.insert(texts, string.format("Unlocks at Lv %d", lv))
		end
		if not StoreKit.hasPass(store, "extraIncubator") then
			table.insert(texts, "Extra Incubator pass")
		end
		return texts
	end

	local function slotCard(i: number, s, usable: boolean, lockText: string?)
		local now = ctx:Now()
		local card = Tiles.card({ Name = "Slot" .. i, Size = UDim2.fromOffset(SLOT_W, SLOT_H), LayoutOrder = i, Parent = slotsRow })
		Tiles.label({
			Text = "Incubator " .. i,
			TextSize = Theme.TextSize.Small,
			TextColor3 = C.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0, 20),
			Parent = card,
		})
		if not usable then
			Tiles.lock(card, lockText or "Locked")
			return
		end
		local filled = type(s) == "table" and s.type
		if not filled then
			local armed = armedSlot == i
			if armed then
				local stroke = card:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = C.Pink
					stroke.Thickness = 5
				end
			end
			Tiles.label({
				Text = if armed then "Tap an egg below" else "Empty",
				TextSize = Theme.TextSize.Body,
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 60),
				Size = UDim2.new(1, 0, 0, 30),
				Parent = card,
			})
			Button.new({
				Text = if armed then "Cancel" else "Place egg",
				Color = if armed then C.Gray else C.Pink,
				Size = UDim2.fromOffset(170, 48),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -10),
				Parent = card,
				OnClick = function()
					armedSlot = if armed then nil else i
					refresh()
				end,
			})
			return
		end
		local icon = MonsterIcon.egg(s.type, 64)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 24)
		icon.Parent = card
		Tiles.label({
			Text = eggName(s.type),
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 88),
			Size = UDim2.new(1, 0, 0, 22),
			Parent = card,
		})
		local endsAt = tonumber(s.endsAt) or 0
		local startedAt = tonumber(s.startedAt) or (endsAt - 1)
		local ready = endsAt <= now
		local bar = Widgets.Bar({
			Color = if ready then C.Green else C.Orange,
			Value = if ready then 1 else math.clamp((now - startedAt) / math.max(1, endsAt - startedAt), 0, 1),
			Text = if ready then "READY!" else Format.clock(endsAt - now),
			Position = UDim2.fromOffset(14, 114),
			Size = UDim2.new(1, -28, 0, 20),
			Parent = card,
		})
		table.insert(timers, { bar = bar, startedAt = startedAt, endsAt = endsAt, ready = ready })
		if ready then
			Button.new({
				Text = "Hatch!",
				Color = C.Green,
				Size = UDim2.fromOffset(170, 48),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				Parent = card,
				OnClick = function()
					StoreKit.request(ctx, "Eggs.Hatch", { slot = i })
				end,
			})
		else
			local left = StoreKit.adsLeft(store, "hatchRush", now)
			local def = Config.Monetization.Ads.hatchRush
			local rush = Button.new({
				Text = string.format("▶ −%s (%d)", Format.duration(def and def.seconds or 900), left),
				Color = C.Orange,
				TextSize = Theme.TextSize.Small + 2,
				Size = UDim2.fromOffset(170, 44),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				Parent = card,
				OnClick = function()
					local ok = StoreKit.request(ctx, "Eggs.HatchRush", { slot = i })
					if ok then
						ctx:Toast("Hatch Rush! The egg is warming up faster.", "success")
					end
				end,
			})
			rush:SetDisabled(left <= 0)
			rush.Root.Visible = Config.Flags.RewardedAds == true
		end
	end

	local function eggGroups()
		local groups = {}
		for id, e in StoreKit.tbl(store, "profile.Eggs.list") do
			if type(e) == "table" and e.type then
				local g = groups[e.type]
				if not g then
					g = { type = e.type, ids = {} }
					groups[e.type] = g
				end
				table.insert(g.ids, { id = id, t = tonumber(e.t) or 0 })
			end
		end
		local list = {}
		for _, g in groups do
			table.sort(g.ids, function(a, b)
				return a.t < b.t
			end)
			table.insert(list, g)
		end
		table.sort(list, function(a, b)
			local da, db = Config.Eggs.ById[a.type], Config.Eggs.ById[b.type]
			return (da and da.order or 99) < (db and db.order or 99)
		end)
		return list
	end

	local function place(group)
		local slot = freeSlot()
		if not slot then
			ctx:Toast("All incubators are busy", "error")
			return
		end
		local first = group.ids[1]
		if not first then
			return
		end
		local ok = StoreKit.request(ctx, "Eggs.Place", { egg = first.id, slot = slot })
		if ok then
			armedSlot = nil
			refresh()
		end
	end

	function refresh()
		table.clear(timers)
		Tiles.clear(slotsRow)
		local slots, count = slotsState()
		local locks = lockedTexts()
		local lockIndex = 0
		local anyReady, anyEmpty = false, false
		local now = ctx:Now()
		for i = 1, Config.Economy.Incubators.maxSlots do
			local usable = i <= count
			local text
			if not usable then
				lockIndex += 1
				text = locks[lockIndex]
			end
			local s = slots[i]
			if usable then
				if type(s) == "table" and s.type then
					anyReady = anyReady or (tonumber(s.endsAt) or math.huge) <= now
				else
					anyEmpty = true
				end
			end
			slotCard(i, s, usable, text)
		end
		if armedSlot and armedSlot > count then
			armedSlot = nil
		end

		Tiles.clear(grid)
		local groups = eggGroups()
		local total = 0
		for i, g in groups do
			total += #g.ids
			local card = Tiles.card({ Name = g.type, LayoutOrder = i, Parent = grid })
			local icon = MonsterIcon.egg(g.type, 64)
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.Position = UDim2.new(0.5, 0, 0, 8)
			icon.Parent = card
			Tiles.label({
				Text = string.gsub(eggName(g.type), " Egg$", ""),
				TextSize = Theme.TextSize.Small + 1,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 76),
				Size = UDim2.new(1, 0, 0, 20),
				Parent = card,
			})
			Tiles.label({
				Text = "×" .. #g.ids,
				TextSize = Theme.TextSize.Body,
				TextColor3 = C.Pink,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 98),
				Size = UDim2.new(1, 0, 0, 22),
				Parent = card,
			})
			Tiles.tap(card, function()
				place(g)
			end)
		end
		if #groups == 0 then
			Tiles.label({
				Text = "No eggs yet. Buy some in the Egg Shop!",
				TextSize = Theme.TextSize.Body,
				TextColor3 = C.TextMuted,
				Size = UDim2.fromOffset(420, 40),
				Parent = grid,
			})
		end
		local speed = StoreKit.num(store, "session.Eggs.speed")
		infoLabel.Text = string.format("Your eggs: %d / %d", total, Config.Economy.MaxEggs)
		hintLabel.Text = (if armedSlot then string.format("Placing into incubator %d · ", armedSlot) else "Tap an egg to incubate it · ")
			.. (if speed > 0 then string.format("Hatch speed +%s", Format.percent(speed)) else "Upgrade incubators on the Ranch")
		hatchAll:SetDisabled(not anyReady)
		fill:SetDisabled(not (anyEmpty and total > 0))
	end

	fill:SetOnClick(function()
		local ok, res = StoreKit.request(ctx, "Eggs.PlaceAuto")
		if ok then
			local placed = type(res) == "table" and tonumber(res.placed) or 0
			ctx:Toast(if placed > 0 then string.format("Placed %d eggs", placed) else "No eggs to place", "info")
			armedSlot = nil
		end
	end)
	hatchAll:SetOnClick(function()
		StoreKit.request(ctx, "Eggs.HatchAll")
	end)

	local watch = StoreKit.watch(store, {
		"profile.Eggs",
		"session.Eggs",
		"profile.Monetization",
		"session.Monetization",
		"profile.Progression.level",
	}, function()
		refresh()
	end)

	local tick
	return {
		Root = panel.Root,
		Open = function()
			armedSlot = nil
			watch.Start()
			local acc = 0
			tick = RunService.Heartbeat:Connect(function(dt)
				acc += dt
				if acc < 0.25 then
					return
				end
				acc = 0
				local now = ctx:Now()
				for _, t in timers do
					if not t.ready then
						if t.endsAt <= now then
							t.ready = true
							watch.Refresh()
						else
							t.bar:SetValue(math.clamp((now - t.startedAt) / math.max(1, t.endsAt - t.startedAt), 0, 1))
							t.bar:SetText(Format.clock(t.endsAt - now))
						end
					end
				end
			end)
		end,
		Close = function()
			watch.Stop()
			if tick then
				tick:Disconnect()
				tick = nil
			end
		end,
	}
end

return Incubators
