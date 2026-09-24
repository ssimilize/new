--[[
	Parts/BattleReplay (C3): full-screen viewer for a BattleReplay (ARCHITECTURE.md §7),
	drawn in ctx.UI.Top above the Expeditions screen.

		local viewer = BattleReplay.play(ctx, {
			replay = res.replay, win = res.win, rewards = res.rewards,
			title = "Whispering Meadow · Stage 3",
			retryText = "Retry with +20% (ad)", onRetry = function() ... end,   -- shown on a loss
			nextText = "Fight stage 4", onNext = function() ... end,            -- shown on a win
			onClose = function() end,
		})
		viewer.Destroy()

	Events play in order: the actor lunges, the target shakes, floating numbers show damage,
	crits, heals, shields and stuns; element multipliers and specials get a callout.
	Skip fast-forwards the state and shows the result card.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)

local UI = script.Parent.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local Util = require(script.Parent.Util)

local New = Create.New
local C = Theme.Colors

local BattleReplay = {}

local ICON = 84
local BOSS_ICON = 110

local function hpColor(frac: number): Color3
	if frac > 0.5 then
		return C.Green
	elseif frac > 0.25 then
		return C.Orange
	end
	return C.Red
end

local function buildUnit(unit, parent: Instance, order: number)
	local size = if unit.boss then BOSS_ICON else ICON
	local slot = New("Frame", {
		Name = unit.key,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(math.max(size, 110) + 10, size + 58),
		LayoutOrder = order,
		Parent = parent,
	})
	local inner = New("CanvasGroup", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = slot,
	})
	local icon
	if unit.appearance and Config.Species.ById[unit.appearance.line] then
		icon = MonsterIcon.new(unit.appearance, size)
	else
		icon = New("Frame", { BackgroundColor3 = C.Gray, Size = UDim2.fromOffset(size, size) }, { Create.Round() })
	end
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0)
	icon.Parent = inner
	Create.Text({
		Text = unit.name or "",
		TextSize = Theme.TextSize.Small,
		Position = UDim2.fromOffset(0, size + 2),
		Size = UDim2.new(1, 0, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Parent = inner,
	})
	local bar = Widgets.Bar({
		Color = C.Green,
		Value = 1,
		Size = UDim2.new(1, -16, 0, 16),
		Position = UDim2.fromOffset(8, size + 26),
		Parent = inner,
	})
	local hpLabel = Create.Text({
		Text = Format.short(unit.maxHp or 0),
		TextSize = Theme.TextSize.Tiny + 1,
		Position = UDim2.fromOffset(0, size + 42),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = inner,
	})
	local badges = New("Frame", {
		Name = "Badges",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 26),
		ZIndex = 5,
		Parent = slot,
	}, { Create.List("x", 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top) })
	local shieldBadge = Widgets.Chip({ Text = "", Color = C.Blue, Parent = badges })
	shieldBadge.Visible = false
	local stunBadge = Widgets.Chip({ Text = "STUN", Color = C.Gold, Parent = badges })
	stunBadge.Visible = false
	return {
		unit = unit,
		slot = slot,
		inner = inner,
		bar = bar,
		hpLabel = hpLabel,
		shieldBadge = shieldBadge,
		stunBadge = stunBadge,
		iconSize = size,
	}
end

function BattleReplay.play(ctx, opts)
	local replay = opts.replay or { units = {}, events = {} }
	local win = if opts.win ~= nil then opts.win else replay.win == true
	local layer = ctx.UI.Top
	local alive = true
	local skipped = false

	local root = New("TextButton", {
		Name = "BattleReplay",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromHex("#1D2B22"),
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 45,
		Parent = layer,
	})
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromHex("#3C5A45"), Color3.fromHex("#18221B"))
	grad.Rotation = 90
	grad.Parent = root

	Create.Text({
		Text = opts.title or "Battle",
		TextSize = Theme.TextSize.Header + 2,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.new(0.6, 0, 0, 34),
		Parent = root,
	})
	local turnLabel = Create.Text({
		Text = "Turn 1",
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(20, 18),
		Size = UDim2.fromOffset(200, 28),
		Parent = root,
	})
	local skipButton = Button.new({
		Text = "Skip ▸▸",
		Color = C.Gray,
		Size = UDim2.fromOffset(130, 48),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 10),
		Parent = root,
	})

	local function row(y: number)
		return New("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, y),
			Size = UDim2.new(1, -40, 0, 180),
			Parent = root,
		}, { Create.List("x", 18, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	end
	local enemyRow = row(0.3)
	local allyRow = row(0.74)

	local callout = Create.Text({
		Text = "",
		TextSize = Theme.TextSize.Title,
		TextColor3 = C.Gold,
		Stroke = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(0.8, 0, 0, 40),
		ZIndex = 10,
		Parent = root,
	})
	callout.TextTransparency = 1

	local views = {}
	local hp = {}
	local shield = {}
	local order = 0
	for _, unit in replay.units or {} do
		order += 1
		local parent = if unit.side == "enemy" then enemyRow else allyRow
		views[unit.key] = buildUnit(unit, parent, order)
		hp[unit.key] = unit.maxHp or 0
		shield[unit.key] = 0
	end

	-- State ---------------------------------------------------------------------------

	local function refreshUnit(key)
		local v = views[key]
		if not v then
			return
		end
		local maxHp = math.max(1, v.unit.maxHp or 1)
		local frac = math.clamp((hp[key] or 0) / maxHp, 0, 1)
		v.bar:SetValue(frac, not skipped)
		v.bar:SetColor(hpColor(frac))
		v.hpLabel.Text = string.format("%s / %s", Format.short(math.max(0, math.floor(hp[key] or 0))), Format.short(maxHp))
		local s = shield[key] or 0
		v.shieldBadge.Visible = s > 0
		if s > 0 then
			local label = v.shieldBadge:FindFirstChildOfClass("TextLabel")
			if label then
				label.Text = "SHIELD " .. Format.short(math.floor(s))
			end
		end
		if (hp[key] or 0) <= 0 then
			v.inner.GroupTransparency = 0.6
			v.stunBadge.Visible = false
		end
	end

	-- Applies an event to the HP/shield/stun state. Returns the key whose HP changed.
	local function apply(ev)
		local kind = ev.kind
		local target = if ev.target then ev.target else ev.actor
		local subject = if kind == "regen" or kind == "stunned" then ev.actor else target
		if kind == "shield" then
			shield[subject] = (shield[subject] or 0) + (ev.amount or 0)
		elseif kind == "stun" then
			local v = views[subject]
			if v then
				v.stunBadge.Visible = true
			end
		elseif kind == "stunned" then
			local v = views[subject]
			if v then
				v.stunBadge.Visible = false
			end
		end
		if kind == "hit" or kind == "crit" or kind == "special" or kind == "reflect" or kind == "stun" then
			local before = hp[subject] or 0
			local lost = math.max(0, before - (ev.hp or before))
			local absorbed = math.max(0, (ev.amount or 0) - lost)
			shield[subject] = math.max(0, (shield[subject] or 0) - absorbed)
		end
		if kind == "faint" then
			hp[subject] = 0
		elseif type(ev.hp) == "number" and subject and hp[subject] ~= nil then
			hp[subject] = ev.hp
		end
		if subject then
			refreshUnit(subject)
		end
		return subject
	end

	-- Visuals -----------------------------------------------------------------------------

	local function floater(key, text: string, color: Color3, big: boolean?)
		local v = views[key]
		if not v or skipped then
			return
		end
		local label = Create.Text({
			Text = text,
			TextSize = if big then Theme.TextSize.Title else Theme.TextSize.Header,
			TextColor3 = color,
			Stroke = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.random(-18, 18), 0, v.iconSize * 0.35),
			Size = UDim2.fromOffset(220, 36),
			TextWrapped = false,
			ZIndex = 8,
			Parent = v.slot,
		})
		if big then
			Anim.pulse(label, 0.35)
		end
		Anim.tween(label, { Position = label.Position - UDim2.fromOffset(0, 46), TextTransparency = 1 }, 0.9)
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			Anim.tween(stroke, { Transparency = 1 }, 0.9)
		end
		task.delay(0.95, function()
			label:Destroy()
		end)
	end

	local calloutToken = 0
	local function showCallout(text: string, color: Color3)
		if skipped then
			return
		end
		calloutToken += 1
		local token = calloutToken
		callout.Text = text
		callout.TextColor3 = color
		callout.TextTransparency = 0
		Anim.pulse(callout, 0.2)
		task.delay(0.9, function()
			if token == calloutToken and callout.Parent then
				Anim.tween(callout, { TextTransparency = 1 }, 0.25)
			end
		end)
	end

	local function lunge(key)
		local v = views[key]
		if not v or skipped then
			return
		end
		local dir = if v.unit.side == "enemy" then 1 else -1
		Anim.tween(v.inner, { Position = UDim2.fromOffset(0, 18 * dir) }, 0.1)
		task.delay(0.12, function()
			if v.inner.Parent then
				Anim.tween(v.inner, { Position = UDim2.new() }, 0.14)
			end
		end)
	end

	local function shake(key)
		local v = views[key]
		if v and not skipped then
			Anim.shake(v.inner)
		end
	end

	local function nameOf(key): string
		local v = views[key]
		return if v then v.unit.name or "?" else "?"
	end

	local function play(ev)
		turnLabel.Text = "Turn " .. tostring(ev.turn or 1)
		local kind = ev.kind
		local amount = Format.short(math.floor(ev.amount or 0))
		local target = if ev.target then ev.target else ev.actor
		if kind == "hit" or kind == "crit" or kind == "special" then
			lunge(ev.actor)
			if kind == "special" then
				local skill = ev.skill and Config.Species.Skills[ev.skill]
				showCallout(string.format("%s used %s!", nameOf(ev.actor), if skill then skill.name else "a special"), C.Gold)
			end
			shake(target)
			if kind == "crit" then
				floater(target, "CRIT -" .. amount, C.Gold, true)
			else
				floater(target, "-" .. amount, C.White)
			end
			if ev.mult and ev.mult > 1 then
				showCallout(string.format("Super effective ×%s", tostring(ev.mult)), C.Green)
			elseif ev.mult and ev.mult < 1 then
				showCallout(string.format("Resisted ×%s", tostring(ev.mult)), C.Gray)
			end
		elseif kind == "reflect" then
			shake(target)
			floater(target, "Thorns -" .. amount, C.Pink)
		elseif kind == "miss" then
			lunge(ev.actor)
			floater(target, "MISS", C.Gray)
		elseif kind == "heal" then
			floater(target, "+" .. amount, C.Green)
		elseif kind == "regen" then
			floater(ev.actor, "+" .. amount, C.Green)
		elseif kind == "shield" then
			floater(target, "SHIELD +" .. amount, C.Blue)
		elseif kind == "stun" then
			lunge(ev.actor)
			shake(target)
			floater(target, if (ev.amount or 0) > 0 then "STUN -" .. amount else "STUNNED!", C.Gold, true)
		elseif kind == "stunned" then
			floater(ev.actor, "Stunned…", C.Gold)
		elseif kind == "faint" then
			floater(target, "KO", C.Red, true)
		end
		if kind == "hit" or kind == "crit" then
			ctx:Sound(if kind == "crit" then "Crit" else "Hit")
		end
		apply(ev)
	end

	-- Result card ---------------------------------------------------------------------------

	local api = {}
	local resultShown = false

	local function destroy()
		if not alive then
			return
		end
		alive = false
		root:Destroy()
	end
	api.Destroy = destroy

	local function showResult()
		if resultShown or not alive then
			return
		end
		resultShown = true
		skipButton:SetVisible(false)
		local panel = Panel.new({
			Title = if win then "Victory!" else "Defeat",
			Color = if win then C.Green else C.Red,
			Size = UDim2.fromOffset(560, 300),
			Parent = root,
		})
		panel.Root.ZIndex = 20
		local body = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -64),
			Parent = panel.Body,
		}, { Create.List("y", 10, Enum.HorizontalAlignment.Center) })
		Util.text({
			Text = if win
				then (opts.winText or "Stage cleared!")
				else (opts.loseText or "Your squad fainted. Try stronger monsters or better elements."),
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Center,
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = body,
		})
		if opts.rewards and #opts.rewards > 0 then
			Util.rewardRow(opts.rewards, body, { LayoutOrder = 2, IconSize = 30, Align = Enum.HorizontalAlignment.Center })
		elseif win then
			Util.text({
				Text = "No first-clear reward this time.",
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 2,
				Parent = body,
			})
		end
		local buttons = New("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1, 0, 0, 56),
			Parent = panel.Body,
		}, { Create.List("x", 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
		local function close()
			destroy()
			if opts.onClose then
				task.spawn(opts.onClose)
			end
		end
		Button.new({
			Text = "Continue",
			Color = C.Gray,
			Size = UDim2.fromOffset(170, 54),
			LayoutOrder = 1,
			OnClick = close,
			Parent = buttons,
		})
		if not win and opts.onRetry then
			local retry
			retry = Button.new({
				Text = opts.retryText or "Retry with +20% (ad)",
				Color = C.Orange,
				Size = UDim2.fromOffset(300, 54),
				LayoutOrder = 2,
				Parent = buttons,
				OnClick = function()
					retry:SetDisabled(true)
					opts.onRetry()
					if alive then
						retry:SetDisabled(false)
					end
				end,
			})
		elseif win and opts.onNext then
			Button.new({
				Text = opts.nextText or "Next stage",
				Color = C.Green,
				Size = UDim2.fromOffset(240, 54),
				LayoutOrder = 2,
				Parent = buttons,
				OnClick = function()
					opts.onNext()
				end,
			})
		end
		Anim.popIn(panel.Root)
		ctx:Sound(if win then "Victory" else "Defeat")
	end

	local function skip()
		if skipped or not alive then
			return
		end
		skipped = true
		showResult()
	end
	skipButton:SetOnClick(skip)

	task.spawn(function()
		local events = replay.events or {}
		local step = math.clamp(22 / math.max(1, #events), 0.14, 0.55)
		task.wait(0.5)
		for i, ev in events do
			if not alive then
				return
			end
			if skipped then
				-- Fast-forward the remaining state so the rows show the final HP.
				for j = i, #events do
					apply(events[j])
				end
				return
			end
			play(ev)
			local pause = step
			if ev.kind == "special" or ev.kind == "crit" or ev.kind == "faint" then
				pause += 0.2
			end
			task.wait(pause)
		end
		if alive and not skipped then
			task.wait(0.4)
			skip()
		end
	end)

	return api
end

return BattleReplay
