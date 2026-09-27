--[[
	Fishing screen (update 3.10 · Ranch life): the Fishing Pond. Opened from the "Go fishing" prompt on
	the pond's dock (Controllers/Interaction); no HUD button.

	lobby    casts left today and bait, the fishing buddy (an Adult; its Luck raises the rare fish
	         and treasure chances shown), Cast (Fishing.Start), the bucket (sell a kind for coins,
	         Fishing.Sell) and a Fish Log button (the Codex's Fish Log tab).
	fishing  a bar with the fish swimming up and down (Logic/Fishing.Course from the seed) and the
	         catch zone: hold Reel (or Space / pad A) to lift it, let go and it sinks. The meter fills
	         while the zone covers the fish. The screen steps Logic/Fishing.Advance exactly like the
	         server's replay, recording every hold / release as { t, down }.
	result   Fishing.Finish { run, inputs } -> the catch (or "It got away!") and any extras.
	Test hooks: the Bar frame carries FishY, ZoneY and Meter attributes (0..1) while fishing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local FishLogic = require(Shared.Logic.Fishing)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)
local FishIcon = require(script.Parent.Parts.FishIcon)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Fishing

local BAR = Vector2.new(96, 330)

local function rareChance(bonus: number): number
	local chances = FishLogic.RarityChances(bonus)
	return (chances.rare or 0) + (chances.legendary or 0)
end

local function treasureChance(bonus: number): number
	local miss = 1
	for _, d in Cfg.Decor do
		miss *= 1 - FishLogic.ExtraChance(d.chance, d.cap, bonus)
	end
	return 1 - miss
end

return {
	Name = "Fishing",
	Build = function(ctx)
		local store = ctx.Store
		local panel = Panel.new({
			Title = "Fishing Pond",
			Color = C.Blue,
			Size = UDim2.fromOffset(900, 500),
			OnClose = function()
				ctx.Router:Close("Fishing")
			end,
		})

		local isOpen = false
		local mode = "lobby"
		local run = nil -- { id, seed, bonus, course, state, inputs, down, elapsed, done }
		local lastResult = nil
		local conn, beganConn, endedConn = nil, nil, nil

		local body = New("Frame", { Name = "FishingBody", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })

		local function stopLoop()
			if conn then
				conn:Disconnect()
				conn = nil
			end
		end

		local draw

		local function section()
			return StoreKit.tbl(store, "profile.Fishing")
		end

		local function castsLeft(s): number
			local used = if tonumber(s.day) == Util.day(ctx) then tonumber(s.casts) or 0 else 0
			return math.max(0, Cfg.FreeCasts - used)
		end

		local function buddy(s)
			local id = s.buddy
			local m = if type(id) == "string" then StoreKit.monsters(store)[id] else nil
			if m and (m.stage or 1) == 3 then
				return m
			end
			return nil
		end

		-- Result -------------------------------------------------------------------------------
		local function finish()
			if not run or run.done then
				return
			end
			run.done = true
			stopLoop()
			local ok, res = Util.requestOnce(ctx, "Fishing.Finish", { run = run.id, inputs = run.inputs })
			lastResult = if ok and type(res) == "table" then res else nil
			mode = "result"
			draw()
		end

		-- Fishing ------------------------------------------------------------------------------
		local function setDown(down: boolean)
			if mode ~= "fishing" or not run or run.done or run.down == down then
				return
			end
			run.down = down
			local t = math.floor(run.elapsed * 1000 + 0.5) / 1000
			local last = run.inputs[#run.inputs]
			if last and last.t >= t then
				t = last.t
			end
			if last and last.t == t then
				last.down = down
			elseif #run.inputs < Cfg.MaxInputs then
				table.insert(run.inputs, { t = math.min(t, Cfg.Duration), down = down })
			end
		end

		local function drawFishing()
			local field = New("Frame", {
				Name = "Bar",
				BackgroundColor3 = Color3.fromHex("#2E7FA8"),
				Position = UDim2.fromOffset(250, 6),
				Size = UDim2.fromOffset(BAR.X, BAR.Y),
				ClipsDescendants = true,
				Parent = body,
			}, { Create.Corner(14), Create.Stroke(3) })
			local zone = New("Frame", {
				Name = "Zone",
				BackgroundColor3 = C.Green,
				BackgroundTransparency = 0.35,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.new(1, -10, 0, math.floor(Cfg.ZoneSize * BAR.Y)),
				Parent = field,
			}, { Create.Corner(10) })
			local fish = FishIcon.new(run.course.fish, 52, true)
			fish.Name = "FishMark"
			fish.AnchorPoint = Vector2.new(0.5, 0.5)
			fish.Parent = field
			local meter = New("Frame", {
				Name = "Meter",
				BackgroundColor3 = C.PanelDeep,
				Position = UDim2.fromOffset(250 + BAR.X + 14, 6),
				Size = UDim2.fromOffset(26, BAR.Y),
				ClipsDescendants = true,
				Parent = body,
			}, { Create.Corner(10), Create.Stroke(2) })
			local fill = New("Frame", {
				Name = "MeterFill",
				BackgroundColor3 = C.Gold,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.fromScale(1, Cfg.StartMeter),
				Parent = meter,
			}, { Create.Corner(10) })
			local status = Util.text({
				Name = "FishStatus",
				Text = "",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				TextWrapped = true,
				Position = UDim2.fromOffset(420, 20),
				Size = UDim2.fromOffset(420, 90),
				Parent = body,
			})
			Util.text({
				Text = "Hold to lift the green zone, let go to sink. Keep the fish inside it to fill the meter!",
				TextWrapped = true,
				TextColor3 = C.TextMuted,
				Position = UDim2.fromOffset(420, 120),
				Size = UDim2.fromOffset(420, 90),
				Parent = body,
			})
			local reel = New("TextButton", {
				Name = "Reel",
				Text = "Hold to reel",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Header,
				TextColor3 = C.White,
				AutoButtonColor = true,
				BackgroundColor3 = C.Orange,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0, 630, 1, -10),
				Size = UDim2.fromOffset(300, 80),
				Parent = body,
			}, { Create.Corner(16), Create.Stroke(3) })
			reel.MouseButton1Down:Connect(function()
				setDown(true)
			end)
			reel.MouseButton1Up:Connect(function()
				setDown(false)
			end)
			reel.MouseLeave:Connect(function()
				setDown(false)
			end)

			local function render()
				local s = run.state
				local fy = FishLogic.FishAt(run.course, s.i * Cfg.Step)
				zone.Position = UDim2.new(0.5, 0, 1 - s.zone, 0)
				fish.Position = UDim2.new(0.5, 0, 1 - fy, 0)
				fill.Size = UDim2.fromScale(1, s.meter)
				field:SetAttribute("FishY", fy)
				field:SetAttribute("ZoneY", s.zone)
				field:SetAttribute("Meter", s.meter)
				local left = math.max(0, Cfg.Duration - s.i * Cfg.Step)
				status.Text = string.format("Something is biting! %s left", Format.clock(math.ceil(left)))
			end
			render()
			stopLoop()
			conn = RunService.Heartbeat:Connect(function(dt)
				if not run or run.done then
					return
				end
				run.elapsed += dt
				local s = run.state
				while not s.done and (s.i + 1) * Cfg.Step <= run.elapsed + 1e-9 do
					FishLogic.Advance(s, run.course, run.inputs)
				end
				render()
				if s.done then
					task.spawn(finish)
				end
			end)
		end

		local function startRun()
			local ok, res = Util.requestOnce(ctx, "Fishing.Start")
			if not ok or type(res) ~= "table" then
				return
			end
			local bonus = tonumber(res.bonus) or 0
			run = {
				id = res.run,
				seed = res.seed,
				bonus = bonus,
				course = FishLogic.Course(res.seed, bonus),
				state = FishLogic.NewState(),
				inputs = {},
				down = false,
				elapsed = 0,
				done = false,
			}
			mode = "fishing"
			draw()
		end

		local function chooseBuddy()
			Util.pick(ctx, {
				title = "Choose a fishing buddy (best Luck first)",
				max = 1,
				filter = function(m)
					return (m.stage or 1) == 3
				end,
				sortBy = function(m)
					return Formulas.Stats(m).luck or 0
				end,
				returnTo = "Fishing",
				onPick = function(ids)
					Util.requestOnce(ctx, "Fishing.SetBuddy", { id = ids[1] })
				end,
			})
		end

		-- Lobby --------------------------------------------------------------------------------
		local function drawBucket(parent: Instance, s)
			local list = New("ScrollingFrame", {
				Name = "Bucket",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(12, 44),
				Size = UDim2.new(1, -24, 1, -56),
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 6,
				Parent = parent,
			}, { Create.List("y", 6) })
			local fish = StoreKit.asTable(s.fish)
			local any = false
			for _, def in Cfg.Fish do
				local n = tonumber(fish[def.id]) or 0
				if n > 0 then
					any = true
					local row = New("Frame", {
						Name = "Row_" .. def.id,
						BackgroundColor3 = C.PanelDeep,
						BackgroundTransparency = 0.6,
						Size = UDim2.new(1, -8, 0, 52),
						LayoutOrder = def.order,
						Parent = list,
					}, { Create.Corner(10) })
					local icon = FishIcon.new(def.id, 46)
					icon.Position = UDim2.fromOffset(4, 3)
					icon.Parent = row
					Util.text({
						Text = string.format("%s ×%d", def.name, n),
						TextSize = Theme.TextSize.Body,
						Position = UDim2.fromOffset(58, 4),
						Size = UDim2.new(1, -170, 0, 24),
						Parent = row,
					})
					Util.text({
						Text = Cfg.RarityById[def.rarity].name,
						TextSize = Theme.TextSize.Small,
						TextColor3 = C.TextMuted,
						Position = UDim2.fromOffset(58, 27),
						Size = UDim2.new(1, -170, 0, 20),
						Parent = row,
					})
					Button.new({
						Name = "Sell_" .. def.id,
						Text = "Sell",
						Color = C.Gold,
						Size = UDim2.fromOffset(96, 44),
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -4, 0.5, 0),
						Parent = row,
						OnClick = function()
							Util.requestOnce(ctx, "Fishing.Sell", { fish = def.id, amount = n })
						end,
					})
				end
			end
			if not any then
				Util.text({
					Text = "Your bucket is empty. Cast a line!",
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					Size = UDim2.new(1, -8, 0, 50),
					Parent = list,
				})
			end
		end

		local function drawLobby()
			local s = section()
			local left = castsLeft(s)
			local bait = tonumber(s.bait) or 0
			local card = Util.card({ Name = "CastCard", Title = "Cast a line", Size = UDim2.new(0, 420, 1, 0), Parent = body })
			Util.text({
				Name = "Casts",
				Text = string.format("Free casts today: %d / %d · Bait: %d", left, Cfg.FreeCasts, bait),
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(16, 44),
				Size = UDim2.new(1, -32, 0, 26),
				Parent = card,
			})
			local m = buddy(s)
			local bonus = if m then FishLogic.BuddyBonus(Formulas.Stats(m).luck) else 0
			local buddyRow = New("Frame", {
				Name = "Buddy",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 80),
				Size = UDim2.new(1, -32, 0, 76),
				Parent = card,
			})
			local ap = m and Util.appearance(m)
			if ap then
				MonsterIcon.new(ap, 72).Parent = buddyRow
			end
			Util.text({
				Name = "BuddyName",
				Text = if m
					then string.format("Buddy: %s · Luck %d", Formulas.DisplayName(m), math.floor(Formulas.Stats(m).luck or 0))
					else "No fishing buddy yet",
				TextSize = Theme.TextSize.Body,
				TextWrapped = true,
				Position = UDim2.fromOffset(if ap then 82 else 0, 0),
				Size = UDim2.new(1, if ap then -82 else 0, 0, 40),
				Parent = buddyRow,
			})
			Util.text({
				Name = "Chances",
				Text = string.format(
					"Rare fish: %s · Treasure: %s",
					Format.percent(rareChance(bonus), 1),
					Format.percent(treasureChance(bonus), 1)
				),
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
				Position = UDim2.fromOffset(if ap then 82 else 0, 42),
				Size = UDim2.new(1, if ap then -82 else 0, 0, 24),
				Parent = buddyRow,
			})
			Button.new({
				Name = "ChooseBuddy",
				Text = if m then "Change buddy" else "Choose buddy",
				Color = C.Blue,
				Size = UDim2.fromOffset(200, 50),
				Position = UDim2.fromOffset(16, 166),
				Parent = card,
				OnClick = chooseBuddy,
			})
			Button.new({
				Name = "FishLog",
				Text = "Fish Log",
				Color = C.Purple,
				Size = UDim2.fromOffset(170, 50),
				Position = UDim2.new(1, -186, 0, 166),
				Parent = card,
				OnClick = function()
					if ctx.Router:Has("Codex") then
						ctx.Router:Open("Codex", { tab = "fishlog" })
					end
				end,
			})
			local canCast = left > 0 or bait > 0
			Button.new({
				Name = "Cast",
				Text = if left > 0 then "Cast" elseif bait > 0 then "Cast with bait" else "No casts left today",
				Color = if canCast then C.Green else C.Gray,
				Disabled = not canCast,
				Size = UDim2.fromOffset(300, 64),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -16),
				Parent = card,
				OnClick = function()
					if canCast then
						startRun()
					end
				end,
			})
			local bucket = Util.card({
				Name = "BucketCard",
				Title = "Your fish",
				Position = UDim2.fromOffset(436, 0),
				Size = UDim2.new(1, -436, 1, 0),
				Parent = body,
			})
			drawBucket(bucket, s)
			if not Util.unlocked(ctx, Cfg.Unlock) then
				Util.lockOverlay(body, Util.unlockText(Cfg.Unlock))
			end
		end

		local function drawResult()
			local card = Util.card({ Name = "ResultCard", Title = "At the pond", Size = UDim2.new(1, 0, 1, 0), Parent = body })
			local r = lastResult
			local def = r and r.caught and Cfg.ById[r.fish]
			if def then
				local icon = FishIcon.new(def.id, 120)
				icon.AnchorPoint = Vector2.new(0.5, 0)
				icon.Position = UDim2.new(0.5, 0, 0, 36)
				icon.Parent = card
			end
			Util.text({
				Name = "FishResult",
				Text = if def
					then string.format("You caught a %s!", def.name)
					elseif r then "It got away!"
					else "That cast couldn't be scored. Try again!",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Header,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(16, 160),
				Size = UDim2.new(1, -32, 0, 40),
				Parent = card,
			})
			if def then
				Util.text({
					Name = "FishWeight",
					Text = string.format("%s · %s", Format.weight(r.weight or 0), Cfg.RarityById[def.rarity].name),
					TextSize = Theme.TextSize.Body,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(16, 202),
					Size = UDim2.new(1, -32, 0, 28),
					Parent = card,
				})
				if r.first then
					Util.text({
						Name = "FishNew",
						Text = "New in your Fish Log!",
						TextSize = Theme.TextSize.Body,
						TextColor3 = C.Green,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.fromOffset(16, 232),
						Size = UDim2.new(1, -32, 0, 28),
						Parent = card,
					})
				end
				if type(r.rewards) == "table" and #r.rewards > 0 then
					Util.rewardRow(r.rewards, card, {
						Position = UDim2.fromOffset(16, 266),
						Size = UDim2.new(1, -32, 0, 36),
						Align = Enum.HorizontalAlignment.Center,
					})
				end
			end
			local row = New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -16),
				Size = UDim2.fromOffset(520, 64),
				Parent = card,
			}, { Create.List("x", 16, Enum.HorizontalAlignment.Center) })
			Button.new({
				Name = "CastAgain",
				Text = "Cast again",
				Color = C.Green,
				Size = UDim2.fromOffset(220, 60),
				LayoutOrder = 1,
				Parent = row,
				OnClick = startRun,
			})
			Button.new({
				Name = "FishDone",
				Text = "Done",
				Color = C.Gray,
				Size = UDim2.fromOffset(160, 60),
				LayoutOrder = 2,
				Parent = row,
				OnClick = function()
					mode = "lobby"
					draw()
				end,
			})
		end

		function draw()
			if not isOpen then
				return
			end
			Util.clear(body)
			panel.Root:SetAttribute("GamepadLegend", if mode == "fishing" then "Ⓐ Hold to reel · Ⓑ Close" else nil)
			if mode == "fishing" then
				drawFishing()
			elseif mode == "result" then
				drawResult()
			else
				drawLobby()
			end
		end

		local watch = StoreKit.watch(store, { "profile.Fishing", "profile.Monsters.list", "profile.Progression" }, function()
			if mode == "lobby" then
				draw()
			end
		end)

		local function isHoldKey(input): boolean
			return input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA
		end

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				mode = if run and not run.done then "fishing" else "lobby"
				beganConn = UserInputService.InputBegan:Connect(function(input)
					if isHoldKey(input) then
						setDown(true)
					end
				end)
				endedConn = UserInputService.InputEnded:Connect(function(input)
					if
						isHoldKey(input)
						or input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					then
						setDown(false)
					end
				end)
				watch.Start()
				draw()
			end,
			Close = function()
				isOpen = false
				stopLoop()
				watch.Stop()
				if run and not run.done then
					run.done = true -- leaving the pond lets the fish go
				end
				panel.Root:SetAttribute("GamepadLegend", nil)
				if beganConn then
					beganConn:Disconnect()
					beganConn = nil
				end
				if endedConn then
					endedConn:Disconnect()
					endedConn = nil
				end
			end,
		}
	end,
}
