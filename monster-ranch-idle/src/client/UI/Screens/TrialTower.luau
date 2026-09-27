--[[
	TrialTower screen (update 3.12 · Honey & stars): the Trial Tower. Opened from the tower's prompt
	in the Market Square (World.Hub "trialTower", Controllers/Interaction) and the "Tower"
	button in the Expeditions header; no HUD button.

	Left card   this week's climb: the floor to fight, this week's best, the all-time record,
	            attempts left today, Retry tokens, the next milestone and its rewards, and the time
	            to the weekly reset (ticks once a second).
	Right card  the next floor's enemies (Logic/TrialTower.Preview: the same for everyone this
	            week; names, powers, a BOSS badge on boss floors), the squad in use (the
	            Expeditions squad), "Fight" (TrialTower.Fight → the replay on the battle stage,
	            Parts/Battle) and a link to the "tower" leaderboard.
	Locked below Ranch Level 26 (a lock overlay).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local TowerLogic = require(Shared.Logic.TrialTower)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)
local Battle = require(script.Parent.Parts.Battle)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.TrialTower
local Boards = Config.Leaderboards

local STONE = Color3.fromHex("#8A8FA3")

return {
	Name = "TrialTower",
	Build = function(ctx)
		local store = ctx.Store
		local panel = Panel.new({
			Title = "Trial Tower",
			Color = STONE,
			Size = UDim2.fromOffset(900, 520),
			OnClose = function()
				ctx.Router:Close("TrialTower")
			end,
		})

		local isOpen = false
		local viewer = nil
		local resetLabel = nil
		local tickConn = nil
		local acc = 0

		local body = New("Frame", { Name = "TowerBody", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })

		local draw

		local function week(): number
			return Boards.Week(ctx:Now())
		end

		-- The save as the server would settle it right now (a stale day or week reads as fresh).
		local function state()
			local s = StoreKit.tbl(store, "profile.TrialTower")
			local wk = week()
			local sameWeek = tonumber(s.week) == wk
			local best = if sameWeek then tonumber(s.best) or 0 else 0
			local used = if tonumber(s.day) == Util.day(ctx) then tonumber(s.used) or 0 else 0
			return {
				week = wk,
				best = best,
				floor = best + 1,
				record = math.max(tonumber(s.record) or 0, best),
				left = math.max(0, Cfg.DailyAttempts - used),
				retries = tonumber(s.retries) or 0,
			}
		end

		local function squad(): { string }
			local e = StoreKit.tbl(store, "profile.Expeditions")
			local list = StoreKit.monsters(store)
			local out = {}
			for _, id in (if type(e.squad) == "table" then e.squad else {}) do
				if list[id] then
					table.insert(out, id)
				end
			end
			return out
		end

		local function resetText(): string
			local left = math.max(0, Boards.WeekEndsAt(week()) - ctx:Now())
			return string.format("New climb in %s", Format.duration(left))
		end

		local function line(parent, name: string, text: string, y: number, props)
			local merged = {
				Name = name,
				Text = text,
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(16, y),
				Size = UDim2.new(1, -32, 0, 26),
				Parent = parent,
			}
			for k, v in props or {} do
				merged[k] = v
			end
			return Util.text(merged)
		end

		-- Fight ---------------------------------------------------------------------------------
		local fight
		fight = function()
			local ok, res = Util.requestOnce(ctx, "TrialTower.Fight")
			if not ok or type(res) ~= "table" then
				return
			end
			if viewer then
				viewer.Destroy()
			end
			local floor = tonumber(res.floor) or 1
			local win = res.win == true
			viewer = Battle.play(ctx, {
				replay = res.replay,
				win = win,
				rewards = res.rewards,
				title = string.format("Trial Tower · Floor %d", floor),
				stage = TowerLogic.Region(floor),
				winText = string.format("Floor %d cleared!", floor),
				loseText = if res.spent == "retry"
					then "Defeated! A Retry token was used"
					else string.format("Defeated! Attempts left today: %d", tonumber(res.left) or 0),
				nextText = string.format("Fight floor %d", floor + 1),
				onNext = if win then fight else nil,
				onClose = function()
					viewer = nil
					if draw then
						draw()
					end
				end,
			})
			draw()
		end

		-- Layout --------------------------------------------------------------------------------
		local function drawClimb(st)
			local card = Util.card({
				Name = "Climb",
				Title = "This week's climb",
				Size = UDim2.new(0, 360, 1, 0),
				Parent = body,
			})
			line(card, "FloorLabel", string.format("Floor %d", st.floor), 40, {
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Title,
				Size = UDim2.new(1, -32, 0, 40),
			})
			line(card, "Best", string.format("This week's best: floor %d", st.best), 86)
			line(card, "Record", string.format("All-time record: floor %d", st.record), 114)
			line(card, "Attempts", string.format("Attempts left today: %d/%d", st.left, Cfg.DailyAttempts), 150, {
				TextColor3 = if st.left > 0 then C.Text else C.TextMuted,
			})
			line(card, "Retries", string.format("Retry tokens: %d", st.retries), 178)
			local next = TowerLogic.NextMilestone(st.best)
			line(card, "Milestone", string.format("Next milestone: floor %d", next), 214)
			Util.rewardRow(TowerLogic.Milestone(next) or {}, card, {
				Position = UDim2.fromOffset(16, 244),
				Size = UDim2.new(1, -32, 0, 34),
			})
			line(card, "Weekly", "Milestones pay once a week. The climb starts over every Saturday.", 290, {
				TextWrapped = true,
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
				Size = UDim2.new(1, -32, 0, 44),
			})
			resetLabel = line(card, "Reset", resetText(), 344, { TextColor3 = C.TextMuted })
		end

		local function drawFloor(st)
			local preview = TowerLogic.Preview(st.week, st.floor)
			local card = Util.card({
				Name = "NextFloor",
				Title = if preview.boss then string.format("Boss floor %d", st.floor) else string.format("Floor %d enemies", st.floor),
				Position = UDim2.fromOffset(376, 0),
				Size = UDim2.new(1, -376, 1, 0),
				Parent = body,
			})
			if preview.boss then
				local badge = New("Frame", {
					Name = "BossBadge",
					BackgroundColor3 = C.Red,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -14, 0, 8),
					Size = UDim2.fromOffset(78, 26),
					Parent = card,
				}, { Create.Corner(UDim.new(0, 8)) })
				Util.text({
					Text = "BOSS",
					Font = Theme.Fonts.Display,
					TextColor3 = C.White,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.fromScale(1, 1),
					Parent = badge,
				})
			end
			local region = Config.Regions.ById[preview.region]
			line(card, "Region", if region then region.name else preview.region, 40, { TextColor3 = C.TextMuted })
			local list = New("Frame", {
				Name = "Enemies",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 72),
				Size = UDim2.new(1, -32, 0, 150),
				Parent = card,
			}, { Create.List("y", 6) })
			for i, e in preview.list do
				local row = New("Frame", {
					Name = "Enemy" .. i,
					BackgroundColor3 = if e.boss then Color3.fromHex("#F6D5D6") else C.Panel,
					Size = UDim2.new(1, 0, 0, 40),
					LayoutOrder = i,
					Parent = list,
				}, { Create.Corner(UDim.new(0, 10)) })
				Util.text({
					Name = "EnemyName",
					Text = e.name,
					TextSize = Theme.TextSize.Body,
					Position = UDim2.fromOffset(12, 0),
					Size = UDim2.new(0.6, -12, 1, 0),
					Parent = row,
				})
				-- Power, not level: a floor's enemies are scaled to its power, and their levels
				-- (from a random stage of the region) would go down between floors.
				Util.text({
					Name = "EnemyPower",
					Text = string.format("Power %s", Format.short(e.power or 0)),
					TextSize = Theme.TextSize.Small,
					TextColor3 = C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Right,
					Position = UDim2.new(0.6, 0, 0, 0),
					Size = UDim2.new(0.4, -12, 1, 0),
					Parent = row,
				})
			end

			local ids = squad()
			line(
				card,
				"Squad",
				if #ids > 0
					then string.format("Your Expeditions squad: %d monsters", #ids)
					else "Pick a squad on the Expeditions screen first",
				234,
				{ TextColor3 = if #ids > 0 then C.Text else C.TextMuted }
			)
			local canFight = #ids > 0 and (st.left > 0 or st.retries > 0)
			if #ids > 0 and not canFight then
				line(card, "NoAttempts", "No attempts left today. Use a Retry token or come back tomorrow", 262, {
					TextWrapped = true,
					TextColor3 = C.TextMuted,
					Size = UDim2.new(1, -32, 0, 44),
				})
			end
			local row = New("Frame", {
				-- Buttons share the card's width (fixed widths ran the Leaderboard button past the
				-- card's edge on a 1914 px Studio screen).
				Name = "Actions",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 16, 1, -14),
				Size = UDim2.new(1, -32, 0, 60),
				Parent = card,
			}, { Create.List("x", 12, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
			Button.new({
				Name = "Fight",
				Text = "Fight",
				Color = if canFight then C.Orange else C.Gray,
				Size = UDim2.new(0.36, -8, 0, 56),
				LayoutOrder = 1,
				Parent = row,
				OnClick = function()
					if #squad() == 0 then
						ctx:Toast("Pick a squad on the Expeditions screen first", "info")
						return
					end
					fight()
				end,
			})
			Button.new({
				Name = "Squad",
				Text = "Squad",
				Color = C.Blue,
				Size = UDim2.new(0.28, -8, 0, 56),
				LayoutOrder = 2,
				Parent = row,
				OnClick = function()
					ctx.Router:Open("Expeditions", { tab = "stages" })
				end,
			})
			Button.new({
				Name = "Board",
				Text = "Leaderboard",
				Color = C.Purple,
				Size = UDim2.new(0.36, -8, 0, 56),
				LayoutOrder = 3,
				Parent = row,
				OnClick = function()
					ctx.Router:Open("Leaderboards", { board = "tower" })
				end,
			})
		end

		function draw()
			if not isOpen then
				return
			end
			Util.clear(body)
			resetLabel = nil
			local st = state()
			drawClimb(st)
			drawFloor(st)
			if not Util.unlocked(ctx, Cfg.Unlock) then
				Util.lockOverlay(body, Util.unlockText(Cfg.Unlock))
			end
		end

		local watch = StoreKit.watch(store, { "profile.TrialTower", "profile.Expeditions.squad", "profile.Progression" }, function()
			draw()
		end)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				watch.Start()
				acc = 0
				tickConn = RunService.Heartbeat:Connect(function(dt)
					acc += dt
					if acc < 1 then
						return
					end
					acc = 0
					if resetLabel and resetLabel.Parent then
						resetLabel.Text = resetText()
					end
				end)
				draw()
			end,
			Close = function()
				isOpen = false
				watch.Stop()
				if tickConn then
					tickConn:Disconnect()
					tickConn = nil
				end
			end,
		}
	end,
}
