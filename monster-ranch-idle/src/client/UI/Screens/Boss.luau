--[[
	Boss screen (C3): the Stampede. A modal that can be opened any time.

	Idle: the next boss and a countdown to its start. Lobby / active: Join (Boss.Join), the
	HP bar, timer and participant count, floating damage numbers, your squad, the top-10
	damage board (you highlighted), your damage and share, and a big CHEER button whose
	taps are batched every 0.5 s into Boss.Cheer { taps }. The cheer meter reads
	session.Boss.cheer. Boss.Result is shown by the Broadcasts controller (so it appears
	even when this screen is closed).

	Reads: global.Boss, session.Boss, profile.Expeditions.squad, profile.Monsters.list,
	profile.Progression.level (all tolerated nil).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Appearance = require(Shared.Logic.Appearance)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local BossConfig = Config.Boss

local function bossDef(id: string?)
	for _, b in BossConfig.Rotation do
		if b.id == id then
			return b
		end
	end
	return nil
end

local function bossForStart(startsAt: number)
	local slot = math.floor(startsAt / BossConfig.Period)
	return BossConfig.Rotation[(slot % #BossConfig.Rotation) + 1]
end

return {
	Name = "Boss",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Stampede",
			Color = Color3.fromHex("#C0573E"),
			Size = UDim2.fromOffset(1040, 520),
			OnClose = function()
				ctx.Router:Close("Boss")
			end,
		})

		local isOpen = false
		local bag = Util.bag()
		local pendingTaps = 0
		local lastHp = nil
		local lastBossKey = nil
		local refresh

		local function boss()
			return ctx.Store:Get("global.Boss") or { state = "idle" }
		end
		local function me()
			return ctx.Store:Get("session.Boss") or { joined = false, damage = 0, cheer = 0 }
		end
		local function nextStart(b): number
			if b.startsAt and b.startsAt > ctx:Now() then
				return b.startsAt
			end
			return math.ceil(ctx:Now() / BossConfig.Period) * BossConfig.Period
		end
		local function currentDef(b)
			local def = bossDef(b.bossId)
			if def then
				return def
			end
			return bossForStart(if b.state == "idle" then nextStart(b) else (b.startsAt or nextStart(b)))
		end

		-- Arena --------------------------------------------------------------------------------

		local arena = New("Frame", {
			Name = "Arena",
			BackgroundColor3 = Color3.fromHex("#2E4A36"),
			Size = UDim2.new(0, 640, 1, 0),
			ClipsDescendants = true,
			Parent = panel.Body,
		}, { Create.Corner(Theme.Radius.Card), Create.Stroke(Theme.Stroke.Card) })
		local arenaGrad = Instance.new("UIGradient")
		arenaGrad.Color = ColorSequence.new(Color3.fromHex("#5F8F5A"), Color3.fromHex("#2B3D2E"))
		arenaGrad.Rotation = 90
		arenaGrad.Parent = arena

		local bossName = Create.Text({
			Text = "",
			TextSize = Theme.TextSize.Title,
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 34),
			Parent = arena,
		})
		local hpBar = Widgets.Bar({
			Color = C.Red,
			Value = 1,
			Size = UDim2.new(1, -80, 0, 24),
			Position = UDim2.fromOffset(40, 46),
			Parent = arena,
		})
		local statusLabel = Create.Text({
			Text = "",
			TextSize = Theme.TextSize.Body,
			Position = UDim2.fromOffset(0, 72),
			Size = UDim2.new(1, 0, 0, 26),
			Parent = arena,
		})
		local bossHolder = New("Frame", {
			Name = "BossHolder",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.44),
			Size = UDim2.fromOffset(150, 150),
			Parent = arena,
		})
		local floaters = New("Frame", {
			Name = "Floaters",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 6,
			Parent = arena,
		})
		local squadRow = New("Frame", {
			Name = "Squad",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 12, 1, -10),
			Size = UDim2.new(0, 200, 0, 64),
			Parent = arena,
		}, { Create.List("x", 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom) })
		local centreInfo = Create.Text({
			Text = "",
			TextSize = Theme.TextSize.Body,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.62, 0),
			Size = UDim2.new(0.9, 0, 0, 50),
			Parent = arena,
		})

		-- Cheer column (bottom centre).
		local cheerHolder = New("Frame", {
			Name = "Cheer",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 60, 1, -8),
			Size = UDim2.fromOffset(260, 108),
			Parent = arena,
		})
		local cheerLabel = Create.Text({
			Text = "Cheer 0%",
			TextSize = Theme.TextSize.Body,
			Size = UDim2.new(1, 0, 0, 22),
			Parent = cheerHolder,
		})
		local cheerBar = Widgets.Bar({
			Color = C.Gold,
			Value = 0,
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.fromOffset(0, 24),
			Parent = cheerHolder,
		})
		local cheerButton = Button.new({
			Text = "CHEER!",
			Color = C.Pink,
			TextSize = Theme.TextSize.Title,
			Size = UDim2.new(1, 0, 0, 62),
			Position = UDim2.fromOffset(0, 44),
			Parent = cheerHolder,
		})
		local joinButton = Button.new({
			Text = "Join the Stampede",
			Color = C.Green,
			TextSize = Theme.TextSize.Button,
			Size = UDim2.fromOffset(300, 62),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 60, 1, -16),
			Parent = arena,
		})

		-- Board --------------------------------------------------------------------------------

		local boardCard =
			Util.card({ Title = "Damage", Position = UDim2.fromOffset(652, 0), Size = UDim2.new(1, -652, 1, 0), Parent = panel.Body })
		local boardList = New("Frame", {
			Name = "Board",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 40),
			Size = UDim2.new(1, -20, 0, 290),
			Parent = boardCard,
		}, { Create.List("y", 3) })
		local youLabel = Util.text({
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = Theme.TextSize.Body,
			Position = UDim2.new(0, 14, 1, -84),
			Size = UDim2.new(1, -28, 0, 26),
			Parent = boardCard,
		})
		Util.text({
			Text = string.format("Top %d get a Stampede Egg", BossConfig.Rewards.topGuaranteed),
			TextColor3 = C.TextMuted,
			Position = UDim2.new(0, 14, 1, -54),
			Size = UDim2.new(1, -28, 0, 44),
			Parent = boardCard,
		})

		-- Behaviour ----------------------------------------------------------------------------

		local function floater(amount: number, maxHp: number)
			if not Anim.enabled then
				return
			end
			local big = amount >= maxHp * 0.04
			local label = Create.Text({
				Text = "-" .. Format.short(math.floor(amount)),
				TextSize = if big then Theme.TextSize.Title else Theme.TextSize.Header,
				TextColor3 = if big then C.Gold else C.White,
				Stroke = true,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, math.random(-110, 110), 0.42, math.random(-50, 30)),
				Size = UDim2.fromOffset(200, 40),
				ZIndex = 7,
				Parent = floaters,
			})
			Anim.tween(label, { Position = label.Position - UDim2.fromOffset(0, 50), TextTransparency = 1 }, 1)
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				Anim.tween(stroke, { Transparency = 1 }, 1)
			end
			task.delay(1.05, function()
				label:Destroy()
			end)
		end

		local function drawBoss(def)
			local key = def and def.id or ""
			if key == lastBossKey then
				return
			end
			lastBossKey = key
			Util.clear(bossHolder)
			if def and Config.Species.ById[def.line] then
				local ok, ap = pcall(Appearance.Preview, def.line, 3, def.form, 5)
				if ok then
					local icon = MonsterIcon.new(ap, 150)
					icon.Parent = bossHolder
				end
			end
		end

		local squadKey = nil
		local function drawSquad()
			local ids = ctx.Store:Get("profile.Expeditions.squad") or {}
			local list = Util.monsters(ctx)
			-- Boss state patches arrive every second; only rebuild the icons when the squad
			-- (or one of its monsters' looks) actually changed.
			local parts = {}
			for _, id in ids do
				local m = list[id]
				table.insert(
					parts,
					tostring(id) .. ":" .. (if type(m) == "table" then tostring(m.line) .. tostring(m.stage) .. tostring(m.form) else "-")
				)
			end
			local key = table.concat(parts, ",")
			if key == squadKey then
				return
			end
			squadKey = key
			Util.clear(squadRow)
			for i, id in ids do
				local ap = Util.appearance(list[id])
				if ap then
					local icon = MonsterIcon.new(ap, 56)
					icon.LayoutOrder = i
					icon.Parent = squadRow
				end
			end
		end

		local function drawBoard(b)
			Util.clear(boardList)
			local dealt = math.max(1, (b.maxHp or 0) - (b.hp or 0))
			local myId = ctx.Player.UserId
			local board = if type(b.board) == "table" then b.board else {}
			if #board == 0 then
				Util.text({
					Text = if b.state == "active" then "No damage yet. Cheer them on!" else "The board fills up when the Stampede starts.",
					TextColor3 = C.TextMuted,
					Size = UDim2.new(1, 0, 0, 44),
					Parent = boardList,
				})
			end
			for i, entry in board do
				if i > 10 then
					break
				end
				local isMe = entry.userId == myId
				local row = New("Frame", {
					BackgroundColor3 = if isMe then Color3.fromHex("#FFE9A8") else C.Card,
					BackgroundTransparency = if isMe then 0 else 1,
					Size = UDim2.new(1, 0, 0, 26),
					LayoutOrder = i,
					Parent = boardList,
				}, { Create.Corner(6) })
				Util.text({
					Text = string.format("%d · %s", i, if isMe then "You" else (entry.name or "?")),
					Font = if isMe then Theme.Fonts.Display else Theme.Fonts.Body,
					Position = UDim2.fromOffset(8, 0),
					Size = UDim2.new(1, -90, 1, 0),
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextWrapped = false,
					TextColor3 = if i <= BossConfig.Rewards.topGuaranteed then C.Text else C.TextMuted,
					Parent = row,
				})
				Util.text({
					Text = Format.percent((entry.damage or 0) / dealt),
					TextXAlignment = Enum.TextXAlignment.Right,
					Position = UDim2.new(1, -86, 0, 0),
					Size = UDim2.new(0, 78, 1, 0),
					Parent = row,
				})
			end
			local mine = me()
			if mine.joined or (mine.damage or 0) > 0 then
				youLabel.Text = string.format(
					"You: %s dmg · %s",
					Format.short(math.floor(mine.damage or 0)),
					Format.percent((mine.damage or 0) / dealt)
				)
			else
				youLabel.Text = if b.state == "idle" then "" else "You haven't joined yet"
			end
		end

		local function statusText(): string
			local b = boss()
			local now = ctx:Now()
			if b.state == "active" then
				local pct = if (b.maxHp or 0) > 0 then (b.hp or 0) / b.maxHp else 1
				return string.format(
					"%s · %s left · %d players",
					Format.percent(pct),
					Format.clock((b.endsAt or now) - now),
					b.participants or #(b.board or {})
				)
			elseif b.state == "lobby" then
				return string.format("Starting in %s · %d joined", Format.clock((b.startsAt or now) - now), b.participants or 0)
			end
			return "Next Stampede in " .. Format.clock(nextStart(b) - now)
		end

		local function updateCheer()
			local mine = me()
			local value = math.clamp((mine.cheer or 0) + pendingTaps * BossConfig.CheerPerTap, 0, 1)
			cheerBar:SetValue(value, true)
			cheerLabel.Text = "Cheer " .. Format.percent(value)
		end

		local function draw()
			if not isOpen then
				return
			end
			local b = boss()
			local mine = me()
			local def = currentDef(b)
			drawBoss(def)
			bossName.Text = string.upper(def and def.name or "Stampede")
			local frac = if (b.maxHp or 0) > 0 then math.clamp((b.hp or 0) / b.maxHp, 0, 1) else 1
			hpBar:SetValue(if b.state == "active" then frac else 1, true)
			if b.state == "active" and lastHp and b.hp and b.hp < lastHp then
				floater(lastHp - b.hp, b.maxHp or 1)
			end
			lastHp = if b.state == "active" then b.hp else nil
			statusLabel.Text = statusText()

			local unlocked = Util.unlocked(ctx, BossConfig.Unlock)
			local canJoin = unlocked and (b.state == "lobby" or b.state == "active") and not mine.joined
			joinButton:SetVisible(canJoin or b.state == "idle")
			joinButton:SetDisabled(not canJoin)
			joinButton:SetText(if b.state == "idle" then "Join opens soon" else "Join the Stampede")
			cheerHolder.Visible = b.state == "active" and mine.joined == true
			if b.state == "idle" then
				centreInfo.Text = if unlocked
					then "Every participant gets a Boss Chest. Join from any screen when the horn sounds!"
					else Util.unlockText(BossConfig.Unlock)
			elseif b.state == "lobby" then
				centreInfo.Text = if mine.joined
					then "You're in! Your squad attacks automatically."
					else "Join now. Your squad attacks automatically."
			else
				centreInfo.Text = if mine.joined then "" else "Join to add your squad's power!"
			end
			centreInfo.Visible = not cheerHolder.Visible
			drawSquad()
			drawBoard(b)
			updateCheer()
		end
		refresh = Util.debounce(draw)

		joinButton:SetOnClick(function()
			local ok = Util.requestOnce(ctx, "Boss.Join")
			if ok then
				ctx:Toast("You joined the Stampede!", "success")
				ctx:Sound("BossHorn")
			end
		end)

		cheerButton:SetOnClick(function()
			pendingTaps = math.min(pendingTaps + 1, BossConfig.MaxTapsPerRequest * 2)
			Anim.pulse(cheerButton.Root, 0.08)
			updateCheer()
		end)

		local lastError = 0
		local loopId = 0
		local function flushLoop()
			loopId += 1
			local id = loopId
			while isOpen and id == loopId do
				task.wait(0.5)
				if pendingTaps > 0 and isOpen and id == loopId then
					local taps = math.min(pendingTaps, BossConfig.MaxTapsPerRequest)
					pendingTaps -= taps
					local ok, res = ctx.Net:Request("Boss.Cheer", { taps = taps })
					if not ok then
						pendingTaps = 0
						if os.clock() - lastError > 4 then
							lastError = os.clock()
							ctx:Toast(tostring(res), "error")
						end
					end
					updateCheer()
				end
			end
		end

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				lastHp = nil
				lastBossKey = nil
				bag.clean()
				for _, path in { "global.Boss", "session.Boss", "profile.Expeditions.squad", "profile.Progression.level" } do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				bag.add(Widgets.Countdown(statusLabel, function()
					return ctx:Now() + 1
				end, function()
					return statusText()
				end))
				task.spawn(flushLoop)
				refresh()
			end,
			Close = function()
				isOpen = false
				pendingTaps = 0
				bag.clean()
			end,
		}
	end,
}
