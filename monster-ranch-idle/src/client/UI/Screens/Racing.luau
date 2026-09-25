--[[
	Racing screen (update 3.0 · Year Two): Monster Racing on the Racetrack.

	lobby   rules, today's ghosts (Logic/Racing.Ghosts on today's track), your best time
	        today, Racing Cup points and paid races left. "Pick a racer" (Monsters pick mode,
	        Adults) → Racing.Start.
	racing  a side view of the track: hurdles and mud slide toward your monster; a progress
	        strip shows you and the three ghosts. Jump (Space / W / ↑, pad A / D-pad ↑) and Boost
	        (Shift / B, pad RT / RB; never X, the world prompts' key) are recorded as { t, a } at the local simulation's time (Logic/Racing.Step, the
	        same code the server replays).
	result  Racing.Finish → the server's time, place, rewards and Cup points.
	Opened from the Racetrack in the hub.

	Reads: profile.Racing, profile.Monsters.list, profile.Progression.level.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Rng = require(Shared.Logic.Rng)
local RaceLogic = require(Shared.Logic.Racing)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Racing

local VIEW = 90 -- metres of track visible ahead of the racer
local BEHIND = 18 -- metres visible behind the racer
local FIELD = Vector2.new(820, 170)
local PLACES = { "1st", "2nd", "3rd", "4th" }

local function today(ctx)
	local day = Util.day(ctx)
	local track = RaceLogic.Track(Rng.seed("racing", day))
	return day, track, RaceLogic.Ghosts(track, day)
end

local function timeText(seconds: number): string
	return string.format("%.2fs", seconds)
end

return {
	Name = "Racing",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Racetrack",
			Color = C.Orange,
			Size = UDim2.fromOffset(900, 500),
			OnClose = function()
				ctx.Router:Close("Racing")
			end,
		})

		local isOpen = false
		local mode = "lobby"
		local race = nil -- { id, racer, track, ghosts, state, inputs, acc, done }
		local lastResult = nil
		local lastRacer = nil
		local conn = nil
		local inputConn = nil

		local body = New("Frame", { Name = "RaceBody", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })

		local function stopLoop()
			if conn then
				conn:Disconnect()
				conn = nil
			end
		end

		local draw

		-- Result -------------------------------------------------------------------------------
		local function finish()
			if not race or race.done then
				return
			end
			race.done = true
			stopLoop()
			local ok, res = Util.requestOnce(ctx, "Racing.Finish", { race = race.id, inputs = race.inputs })
			lastResult = if ok and type(res) == "table" then res else nil
			mode = "result"
			draw()
		end

		-- Racing -------------------------------------------------------------------------------
		local function act(a: string)
			if mode ~= "racing" or not race or race.done or #race.inputs >= Cfg.MaxInputs then
				return
			end
			local t = race.state.t
			local last = race.inputs[#race.inputs]
			if last and last.t > t then
				t = last.t
			end
			table.insert(race.inputs, { t = t, a = a })
		end

		local function drawRacing()
			local strip = New("Frame", {
				Name = "Progress",
				BackgroundColor3 = C.PanelDeep,
				Position = UDim2.fromOffset(40, 4),
				Size = UDim2.new(1, -80, 0, 34),
				Parent = body,
			}, { Create.Corner(10) })
			local dots = {}
			local function dot(name: string, color: Color3, size: number)
				local d = New("Frame", {
					Name = name,
					BackgroundColor3 = color,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0, 0.5),
					Size = UDim2.fromOffset(size, size),
					Parent = strip,
				}, { Create.Corner(size // 2), Create.Stroke(2) })
				return d
			end
			for i, g in race.ghosts do
				dots[i] = dot("Ghost" .. i, C.Gray, 16)
				dots[i]:SetAttribute("Name", g.name)
			end
			local me = dot("Me", C.Orange, 22)

			local field = New("Frame", {
				Name = "Track",
				BackgroundColor3 = Color3.fromHex("#D9B88A"),
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 46),
				Size = UDim2.fromOffset(FIELD.X, FIELD.Y),
				ClipsDescendants = true,
				Parent = body,
			}, { Create.Corner(14), Create.Stroke(3) })
			local features = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = field })
			local groundY = FIELD.Y - 34
			local pxPerM = FIELD.X / (VIEW + BEHIND)
			local racerX = BEHIND * pxPerM
			local icon = if race.racer
				then MonsterIcon.new(race.racer, 64)
				else New("Frame", { BackgroundColor3 = C.Orange, Size = UDim2.fromOffset(48, 40) }, { Create.Corner(12) })
			icon.Name = "Racer"
			icon.AnchorPoint = Vector2.new(0.5, 1)
			icon.Parent = field
			local finishLine = New("Frame", {
				Name = "Finish",
				BackgroundColor3 = C.White,
				BorderSizePixel = 0,
				Size = UDim2.new(0, 8, 1, 0),
				Parent = features,
			})
			local marks = {}
			for i, h in race.track.hurdles do
				marks["h" .. i] = { x = h, w = 0, kind = "hurdle" }
			end
			for i, m in race.track.mud do
				marks["m" .. i] = { x = m.from, w = m.to - m.from, kind = "mud" }
			end
			for key, mark in marks do
				mark.frame = New("Frame", {
					Name = if mark.kind == "mud" then "Mud" else "Hurdle",
					BackgroundColor3 = if mark.kind == "mud" then Color3.fromHex("#7A5230") else C.White,
					AnchorPoint = Vector2.new(0, 1),
					Size = if mark.kind == "mud" then UDim2.fromOffset(mark.w * pxPerM, 18) else UDim2.fromOffset(10, 34),
					Visible = false,
					Parent = features,
				}, { Create.Corner(4), if mark.kind == "hurdle" then Create.Stroke(2) else nil })
				mark.key = key
			end

			local status = Util.text({
				Name = "RaceStatus",
				Text = "",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.new(0, 0, 0, 46 + FIELD.Y + 6),
				Size = UDim2.new(1, 0, 0, 26),
				Parent = body,
			})
			local staminaBack = New("Frame", {
				Name = "Stamina",
				BackgroundColor3 = C.PanelDeep,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 46 + FIELD.Y + 36),
				Size = UDim2.fromOffset(300, 14),
				Parent = body,
			}, { Create.Corner(7) })
			local staminaFill = New("Frame", {
				BackgroundColor3 = C.Green,
				Size = UDim2.fromScale(1, 1),
				Parent = staminaBack,
			}, { Create.Corner(7) })

			local controls = New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -2),
				Size = UDim2.fromOffset(FIELD.X, 70),
				Parent = body,
			})
			Button.new({
				Name = "Boost",
				Text = "Boost",
				Color = C.Purple,
				Size = UDim2.fromOffset(200, 64),
				Parent = controls,
				OnClick = function()
					act("boost")
				end,
			})
			Button.new({
				Name = "Jump",
				Text = "Jump",
				Color = C.Blue,
				Size = UDim2.fromOffset(200, 64),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Parent = controls,
				OnClick = function()
					act("jump")
				end,
			})

			local function place(x: number, width: number)
				return (x - race.state.x) * pxPerM + racerX, width
			end
			stopLoop()
			conn = RunService.Heartbeat:Connect(function(dt)
				if not race or race.done then
					return
				end
				race.acc += dt
				while race.acc >= Cfg.Step and not race.state.finished and race.state.t < Cfg.MaxSeconds do
					race.acc -= Cfg.Step
					RaceLogic.Step(race.track, race.state, race.inputs)
				end
				local s = race.state
				local hop = if s.air > 0 then math.sin((1 - s.air / Cfg.JumpSeconds) * math.pi) * 40 else 0
				icon.Position = UDim2.fromOffset(racerX, groundY - hop)
				icon.Rotation = if s.stun > 0 then 25 else 0
				for _, mark in marks do
					local px = place(mark.x, 0)
					local visible = px > -mark.w * pxPerM - 20 and px < FIELD.X + 20
					mark.frame.Visible = visible
					if visible then
						mark.frame.Position = UDim2.fromOffset(px, groundY + (if mark.kind == "mud" then 12 else 0))
					end
				end
				finishLine.Position = UDim2.fromOffset(place(Cfg.Length, 0), 0)
				me.Position = UDim2.fromScale(math.clamp(s.x / Cfg.Length, 0, 1), 0.5)
				for i, g in race.ghosts do
					dots[i].Position = UDim2.fromScale(math.clamp(s.t / g.time, 0, 1), 0.5)
				end
				staminaFill.Size = UDim2.fromScale(s.stamina / Cfg.MaxStamina, 1)
				staminaFill.BackgroundColor3 = if s.stamina >= Cfg.BoostCost then C.Green else C.Gray
				local ahead = 1
				for _, g in race.ghosts do
					if g.time <= s.t then
						ahead += 1
					end
				end
				status.Text = string.format(
					"%s · %d / %d m · %s",
					timeText(s.t),
					math.floor(math.min(s.x, Cfg.Length)),
					Cfg.Length,
					if s.stun > 0 then "Stumbled!" elseif s.boost > 0 then "Boost!" else PLACES[math.min(ahead, 4)]
				)
				if s.finished or s.t >= Cfg.MaxSeconds then
					task.spawn(finish)
				end
			end)
		end

		local function startRace(id: string)
			local m = Util.monsters(ctx)[id]
			local ok, res = Util.requestOnce(ctx, "Racing.Start", { id = id })
			if not ok or type(res) ~= "table" then
				return
			end
			lastRacer = id
			local track = RaceLogic.Track(Rng.seed("racing", res.day))
			race = {
				id = res.race,
				racer = Util.appearance(m),
				track = track,
				ghosts = res.ghosts,
				state = RaceLogic.New(res.speed),
				inputs = {},
				acc = 0,
				done = false,
			}
			mode = "racing"
			draw()
		end

		local function pickRacer()
			if not Util.unlocked(ctx, Cfg.Unlock) then
				ctx:Toast(Util.unlockText(Cfg.Unlock), "error")
				return
			end
			Util.pick(ctx, {
				title = "Pick your racer",
				max = 1,
				filter = function(m)
					return m.stage == 3 and (not m.busy or m.busy == "riding")
				end,
				returnTo = "Racing",
				onPick = function(ids)
					task.defer(startRace, ids[1])
				end,
			})
		end

		-- Lobby and result ---------------------------------------------------------------------
		local function drawLobby()
			local stats = StoreKit.tbl(ctx.Store, "profile.Racing")
			local day, _, ghosts = today(ctx)
			local left = if stats.day == day then math.max(0, Cfg.RewardedPerDay - (tonumber(stats.rewarded) or 0)) else Cfg.RewardedPerDay
			local rules = Util.card({ Title = "Monster Racing", Size = UDim2.new(0, 520, 1, 0), Parent = body })
			Util.text({
				Text = string.format(
					"Race one of your Adults %d m down today's track. Faster monsters run faster, but you win with timing:\n• Jump over hurdles (a stumble costs %.1f s)\n• Boost for ×%.1f speed (%d stamina, it refills)\n• Mud slows you down\nPaid races left today: %d / %d",
					Cfg.Length,
					Cfg.StumbleSeconds,
					Cfg.BoostMult,
					Cfg.BoostCost,
					left,
					Cfg.RewardedPerDay
				),
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromOffset(16, 44),
				Size = UDim2.new(1, -32, 0, 190),
				Parent = rules,
			})
			Button.new({
				Name = "PickRacer",
				Text = if Util.unlocked(ctx, Cfg.Unlock) then "Pick a racer" else Util.unlockText(Cfg.Unlock),
				Color = if Util.unlocked(ctx, Cfg.Unlock) then C.Green else C.Gray,
				Size = UDim2.fromOffset(320, 64),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -16),
				Parent = rules,
				OnClick = pickRacer,
			})
			local board = Util.card({
				Title = "Today's ghosts",
				Position = UDim2.fromOffset(530, 0),
				Size = UDim2.new(1, -530, 1, 0),
				Parent = body,
			})
			local lines = {}
			for i, g in ghosts do
				table.insert(lines, string.format("%d. %s · %s", i, g.name, timeText(g.time)))
			end
			local bestToday = if stats.bestDay == day then tonumber(stats.bestToday) or 0 else 0
			local cup = if stats.week == Config.Leaderboards.Week(ctx:Now()) then tonumber(stats.cup) or 0 else 0
			table.insert(lines, "")
			table.insert(lines, "Your best today: " .. (if bestToday > 0 then timeText(bestToday) else "none yet"))
			table.insert(lines, string.format("Racing Cup this week: %d pts", cup))
			table.insert(lines, string.format("Races: %d · Wins: %d", tonumber(stats.races) or 0, tonumber(stats.wins) or 0))
			Util.text({
				Name = "Ghosts",
				Text = table.concat(lines, "\n"),
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromOffset(16, 44),
				Size = UDim2.new(1, -32, 1, -56),
				Parent = board,
			})
		end

		local function drawResult()
			local card = Util.card({ Title = "Race results", Size = UDim2.new(1, 0, 1, 0), Parent = body })
			local r = lastResult
			Util.text({
				Name = "RaceResult",
				Text = if r
					then string.format(
						"%s place · %s\n%d stumbles · +%d Cup points · Best %s",
						PLACES[r.place] or "?",
						if r.finished then timeText(r.time) else "DNF",
						r.stumbles or 0,
						r.cup or 0,
						if (r.best or 0) > 0 then timeText(r.best) else "-"
					)
					else "That race couldn't be timed. Try again!",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Header,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(16, 50),
				Size = UDim2.new(1, -32, 0, 110),
				Parent = card,
			})
			if r and type(r.rewards) == "table" and #r.rewards > 0 then
				Util.rewardRow(r.rewards, card, {
					IconSize = 32,
					Position = UDim2.fromOffset(16, 180),
					Size = UDim2.new(1, -32, 0, 40),
					Align = Enum.HorizontalAlignment.Center,
				})
			elseif r then
				Util.text({
					Text = "No rewards: you've used today's paid races.",
					TextColor3 = C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(16, 190),
					Size = UDim2.new(1, -32, 0, 30),
					Parent = card,
				})
			end
			local row = New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -16),
				Size = UDim2.fromOffset(520, 64),
				Parent = card,
			}, { Create.List("x", 16, Enum.HorizontalAlignment.Center) })
			Button.new({
				Name = "RaceAgain",
				Text = "Race again",
				Color = C.Green,
				Size = UDim2.fromOffset(220, 60),
				LayoutOrder = 1,
				Parent = row,
				OnClick = function()
					if lastRacer and Util.monsters(ctx)[lastRacer] then
						startRace(lastRacer)
					else
						pickRacer()
					end
				end,
			})
			Button.new({
				Name = "RaceDone",
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
			-- While running, the Gamepad controller clears its cursor (so A jumps instead of
			-- pressing a button) and shows this legend.
			panel.Root:SetAttribute("GamepadLegend", if mode == "racing" then "Ⓐ Jump · RT Boost · Ⓑ Close" else nil)
			if mode == "racing" then
				drawRacing()
			elseif mode == "result" then
				drawResult()
			else
				drawLobby()
			end
		end

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				mode = if race and not race.done then "racing" elseif mode == "result" then "result" else "lobby"
				inputConn = UserInputService.InputBegan:Connect(function(input, processed)
					local key = input.KeyCode
					-- Pad buttons: the gamepad cursor is cleared while racing, so nothing on
					-- screen consumes them; `processed` only guards typing on a keyboard.
					if key == Enum.KeyCode.ButtonA or key == Enum.KeyCode.DPadUp then
						act("jump")
						return
					elseif key == Enum.KeyCode.ButtonR2 or key == Enum.KeyCode.ButtonR1 then
						act("boost")
						return
					end
					if processed then
						return
					end
					if key == Enum.KeyCode.Space or key == Enum.KeyCode.W or key == Enum.KeyCode.Up then
						act("jump")
					elseif key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.B then
						act("boost")
					end
				end)
				draw()
			end,
			Close = function()
				isOpen = false
				stopLoop()
				panel.Root:SetAttribute("GamepadLegend", nil)
				if race and not race.done then
					race.done = true -- leaving the track ends the race without a time
				end
				mode = "lobby"
				if inputConn then
					inputConn:Disconnect()
					inputConn = nil
				end
			end,
		}
	end,
}
