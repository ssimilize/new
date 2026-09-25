--[[
	Surf screen (update 2.0 · Summer Splash): the Surf Shack minigame.

	lobby   rules, your best score and runs, Start (Surf.Start → seed)
	surfing three lanes; rocks and seashells ride down to your surfer (Logic/Surf.Course from
	        the seed). ◀ / ▶ (or A / D, ← / →, pad D-pad or left stick) switch lanes; every switch is recorded as
	        { t, lane }. Hitting Config.Lives rocks or reaching Config.Duration ends the run.
	result  Surf.Finish { run, inputs } → the server's score, shells, Seashells and best.
	The screen only shows the run; the server replays the moves to decide the score.
	Opened from the Surf Shack in the hub.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local SurfLogic = require(Shared.Logic.Surf)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Surf

local LOOKAHEAD = 2.4 -- seconds of course visible above the surfer
local FIELD = Vector2.new(360, 330)
local STICK_PUSH = 0.6 -- left stick X past this switches one lane
local STICK_REARM = 0.3 -- and must come back inside this before the next switch

return {
	Name = "Surf",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Surf Shack",
			Color = C.Blue,
			Size = UDim2.fromOffset(900, 500),
			OnClose = function()
				ctx.Router:Close("Surf")
			end,
		})

		local isOpen = false
		local mode = "lobby"
		local run = nil -- { id, seed, course, inputs, lane, elapsed, shells, hits, done, seen }
		local lastResult = nil
		local conn = nil
		local inputConn = nil
		local stickConn = nil
		local stickArmed = true

		local body = New("Frame", { Name = "SurfBody", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })

		local function clear()
			Util.clear(body)
		end

		local function stopLoop()
			if conn then
				conn:Disconnect()
				conn = nil
			end
		end

		local draw

		-- Result -------------------------------------------------------------------------------
		local function finish()
			if not run or run.done then
				return
			end
			run.done = true
			stopLoop()
			local ok, res = Util.requestOnce(ctx, "Surf.Finish", { run = run.id, inputs = run.inputs })
			lastResult = if ok and type(res) == "table" then res else nil
			mode = "result"
			draw()
		end

		-- Surfing ------------------------------------------------------------------------------
		local function move(delta: number)
			if mode ~= "surfing" or not run or run.done then
				return
			end
			local lane = math.clamp(run.lane + delta, 1, Cfg.Lanes)
			if lane == run.lane then
				return
			end
			run.lane = lane
			local t = math.floor(run.elapsed * 1000 + 0.5) / 1000
			local last = run.inputs[#run.inputs]
			if last and last.t > t then
				t = last.t
			end
			if #run.inputs < Cfg.MaxInputs then
				table.insert(run.inputs, { t = t, lane = lane })
			end
		end

		local function drawSurfing()
			local field = New("Frame", {
				Name = "Waves",
				BackgroundColor3 = Color3.fromHex("#3FB6D9"),
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 6),
				Size = UDim2.fromOffset(FIELD.X, FIELD.Y),
				ClipsDescendants = true,
				Parent = body,
			}, { Create.Corner(14), Create.Stroke(3) })
			for i = 1, Cfg.Lanes - 1 do
				New("Frame", {
					BackgroundColor3 = C.White,
					BackgroundTransparency = 0.6,
					BorderSizePixel = 0,
					Position = UDim2.new(i / Cfg.Lanes, -1, 0, 0),
					Size = UDim2.new(0, 2, 1, 0),
					Parent = field,
				})
			end
			local surfer = New("Frame", {
				Name = "Surfer",
				BackgroundColor3 = C.Orange,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(54, 30),
				Parent = field,
			}, { Create.Corner(15), Create.Stroke(3) })
			local items = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = field })
			local status = Util.text({
				Name = "SurfStatus",
				Text = "",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.new(0, 0, 0, FIELD.Y + 10),
				Size = UDim2.new(1, 0, 0, 26),
				Parent = body,
			})
			local controls = New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -2),
				Size = UDim2.fromOffset(FIELD.X + 280, 70),
				Parent = body,
			})
			Button.new({
				Name = "Left",
				Text = "◀",
				TextSize = 34,
				Color = C.Blue,
				Size = UDim2.fromOffset(120, 64),
				Parent = controls,
				OnClick = function()
					move(-1)
				end,
			})
			Button.new({
				Name = "Right",
				Text = "▶",
				TextSize = 34,
				Color = C.Blue,
				Size = UDim2.fromOffset(120, 64),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Parent = controls,
				OnClick = function()
					move(1)
				end,
			})

			local markers = {}
			local function laneX(lane: number): number
				return (lane - 0.5) / Cfg.Lanes * FIELD.X
			end
			local surferY = FIELD.Y - 36
			stopLoop()
			conn = RunService.Heartbeat:Connect(function(dt)
				if not run or run.done then
					return
				end
				run.elapsed += dt
				-- Local feedback only; the server decides the real score.
				for index, item in run.course do
					if not run.seen[index] and item.t <= run.elapsed then
						run.seen[index] = true
						if SurfLogic.LaneAt(run.inputs, item.t) == item.lane then
							if item.kind == "shell" then
								run.shells += 1
							else
								run.hits += 1
							end
						end
					end
				end
				surfer.Position = UDim2.fromOffset(laneX(run.lane), surferY)
				for index, item in run.course do
					local ahead = item.t - run.elapsed
					local marker = markers[index]
					if
						ahead >= -0.3
						and ahead <= LOOKAHEAD
						and not (run.seen[index] and item.kind == "shell" and SurfLogic.LaneAt(run.inputs, item.t) == item.lane)
					then
						if not marker then
							marker = New("Frame", {
								Name = if item.kind == "shell" then "Shell" else "Rock",
								BackgroundColor3 = if item.kind == "shell" then C.Gold else Color3.fromHex("#6B6F74"),
								AnchorPoint = Vector2.new(0.5, 0.5),
								Size = UDim2.fromOffset(if item.kind == "shell" then 30 else 44, if item.kind == "shell" then 30 else 36),
								Parent = items,
							}, { Create.Corner(if item.kind == "shell" then 15 else 10), Create.Stroke(2) })
							markers[index] = marker
						end
						marker.Position = UDim2.fromOffset(laneX(item.lane), surferY - ahead / LOOKAHEAD * surferY)
					elseif marker then
						marker:Destroy()
						markers[index] = nil
					end
				end
				local left = math.max(0, Cfg.Duration - run.elapsed)
				local hearts = string.rep("♥", math.max(0, Cfg.Lives - run.hits))
				status.Text = string.format("❂ %d   %s   %s left", run.shells, hearts, Format.clock(left))
				if run.hits >= Cfg.Lives or run.elapsed >= Cfg.Duration then
					task.spawn(finish)
				end
			end)
		end

		local function startRun()
			local ok, res = Util.requestOnce(ctx, "Surf.Start")
			if not ok or type(res) ~= "table" then
				return
			end
			run = {
				id = res.run,
				seed = res.seed,
				course = SurfLogic.Course(res.seed),
				inputs = {},
				lane = Cfg.StartLane,
				elapsed = 0,
				shells = 0,
				hits = 0,
				done = false,
				seen = {},
			}
			mode = "surfing"
			draw()
		end

		-- Lobby and result ---------------------------------------------------------------------
		local function drawLobby()
			local stats = StoreKit.tbl(ctx.Store, "profile.Surf")
			local open = Config.Events.ActiveId(ctx:Now()) == Cfg.Event
			local card = Util.card({ Title = "Ride the waves!", Size = UDim2.new(1, 0, 1, 0), Parent = body })
			Util.text({
				Text = string.format(
					"Switch lanes with ◀ ▶ (or A / D). Catch seashells, dodge rocks: %d hits and you wipe out. A run lasts %d seconds.\n\nScore: %d per shell + %d per second on your board. Every %d points pays 1 Seashell (up to %d a run).",
					Cfg.Lives,
					Cfg.Duration,
					Cfg.ShellPoints,
					Cfg.SecondPoints,
					Cfg.PointsPerToken,
					Cfg.MaxTokensPerRun
				),
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromOffset(16, 44),
				Size = UDim2.new(1, -32, 0, 120),
				Parent = card,
			})
			Util.text({
				Name = "SurfBest",
				Text = string.format("Best score: %d · Runs: %d", tonumber(stats.best) or 0, tonumber(stats.runs) or 0),
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(16, 176),
				Size = UDim2.new(1, -32, 0, 30),
				Parent = card,
			})
			Button.new({
				Name = "StartSurf",
				Text = if open then "Start surfing" else "Opens during Summer Splash",
				Color = if open then C.Green else C.Gray,
				Disabled = not open,
				Size = UDim2.fromOffset(320, 64),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -16),
				Parent = card,
				OnClick = function()
					if open then
						startRun()
					end
				end,
			})
		end

		local function drawResult()
			local card = Util.card({ Title = "Wave report", Size = UDim2.new(1, 0, 1, 0), Parent = body })
			local r = lastResult
			Util.text({
				Name = "SurfResult",
				Text = if r
					then string.format(
						"Score %d\n%d shells · %s on the board · %d rocks hit\n+%d Seashells · Best %d",
						r.score or 0,
						r.shells or 0,
						Format.clock(math.floor(r.survived or 0)),
						r.hits or 0,
						r.tokens or 0,
						r.best or 0
					)
					else "That run couldn't be scored. Try again!",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Header,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(16, 60),
				Size = UDim2.new(1, -32, 0, 180),
				Parent = card,
			})
			local row = New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -16),
				Size = UDim2.fromOffset(520, 64),
				Parent = card,
			}, { Create.List("x", 16, Enum.HorizontalAlignment.Center) })
			Button.new({
				Name = "SurfAgain",
				Text = "Surf again",
				Color = C.Green,
				Size = UDim2.fromOffset(220, 60),
				LayoutOrder = 1,
				Parent = row,
				OnClick = startRun,
			})
			Button.new({
				Name = "SurfDone",
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
			clear()
			-- While surfing, the Gamepad controller clears its cursor (so the D-pad switches
			-- lanes instead of moving it) and shows this legend.
			panel.Root:SetAttribute("GamepadLegend", if mode == "surfing" then "◀ ▶ Switch lanes · Ⓑ Close" else nil)
			if mode == "surfing" then
				drawSurfing()
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
				mode = if run and not run.done then "surfing" else "lobby"
				inputConn = UserInputService.InputBegan:Connect(function(input, processed)
					local key = input.KeyCode
					-- The gamepad cursor is cleared while surfing, so nothing on screen consumes
					-- the D-pad; `processed` only guards typing on a keyboard.
					if key == Enum.KeyCode.DPadLeft then
						move(-1)
						return
					elseif key == Enum.KeyCode.DPadRight then
						move(1)
						return
					end
					if processed then
						return
					end
					if key == Enum.KeyCode.A or key == Enum.KeyCode.Left then
						move(-1)
					elseif key == Enum.KeyCode.D or key == Enum.KeyCode.Right then
						move(1)
					end
				end)
				-- Left stick: one lane per push past the deadzone; it re-arms back near the centre.
				stickArmed = true
				stickConn = UserInputService.InputChanged:Connect(function(input)
					if input.KeyCode ~= Enum.KeyCode.Thumbstick1 then
						return
					end
					local x = input.Position.X
					if math.abs(x) < STICK_REARM then
						stickArmed = true
					elseif stickArmed and math.abs(x) >= STICK_PUSH then
						stickArmed = false
						move(if x < 0 then -1 else 1)
					end
				end)
				draw()
			end,
			Close = function()
				isOpen = false
				stopLoop()
				if run and not run.done then
					run.done = true -- leaving the shack ends the run without a score
				end
				panel.Root:SetAttribute("GamepadLegend", nil)
				if inputConn then
					inputConn:Disconnect()
					inputConn = nil
				end
				if stickConn then
					stickConn:Disconnect()
					stickConn = nil
				end
			end,
		}
	end,
}
