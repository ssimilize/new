--[[
	Observatory screen (update 3.12 · Honey & stars): the Observatory and its Star Charts. Opened
	from the "Stargaze" prompt on the telescope (Controllers/Interaction); no HUD button.

	Left: the Sky. With no sighting on, it shows the night / day state (by day "Opens at night · in
	Xm") and the star perks earned so far. During a sighting the stars are dots (TextButtons
	Star_<i>), the order to trace is a faint line pattern, and a timer runs; tap the stars in order.
	The taps (star, seconds since the start) go to Observatory.Submit when the last star is tapped or
	time runs out; the server says whether the sighting counted.

	Right: sightings left tonight, the last result, and every chart (Chart_<id>): its progress
	(0-3), its perk and its Observe button, "Charted" when finished or "Back in <season>" when its
	season is away.
	Test hooks: each star carries a Tapped attribute; each chart row a Progress attribute.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Observatory)
local Seasons = require(Shared.Logic.Seasons)
local Format = require(Shared.Logic.Format)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local StoreKit = require(UI.Components.StoreKit)
local Widgets = require(UI.Components.Widgets)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Observatory

local SKY = 390
local STAR = 44
local NIGHT_SKY = Color3.fromHex("#1B2447")
local DAY_SKY = Color3.fromHex("#8CC8EE")
local STAR_COLOR = Color3.fromHex("#FFF3B0")
local TAPPED_COLOR = Color3.fromHex("#F2A93B")

local function chartName(id): string
	local def = Cfg.ById[id]
	return if def then def.name else "Star chart"
end

local function resultText(res): string
	if res.success then
		if res.charted then
			return string.format("Chart complete: %s! Its perk is yours for good", chartName(res.chart))
		end
		return string.format("Sighting logged! %s · %d / %d", chartName(res.chart), res.progress or 0, Cfg.Observations)
	elseif res.why == "slow" then
		return "Too slow · the stars drifted away"
	elseif res.why == "fast" then
		return "Too quick · take a moment on each star"
	end
	return "Wrong order · the pattern slipped away"
end

return {
	Name = "Observatory",
	Build = function(ctx)
		local store = ctx.Store
		local panel = Panel.new({
			Title = "Observatory",
			Color = C.Purple,
			Size = UDim2.fromOffset(900, 500),
			OnClose = function()
				ctx.Router:Close("Observatory")
			end,
		})

		local isOpen = false
		local busy = false
		local run = nil -- { id, chart, stars, order, taps, elapsed, done }
		local last = nil -- the last Submit result
		local clockLabel = nil -- the countdown or timer label redrawn each second
		local lastSecond = -1
		local conn = nil
		local drawnNight = nil -- the night / day state the screen was last drawn for

		local body =
			New("Frame", { Name = "ObservatoryBody", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })

		local draw

		local function section()
			return StoreKit.tbl(store, "profile.Observatory")
		end

		local function sightingsLeft(s, night: number): number
			local used = if tonumber(s.night) == night then tonumber(s.used) or 0 else 0
			return math.max(0, Cfg.Sightings - used)
		end

		local function clockText(): string
			if run then
				return string.format("Time left: %s", Format.duration(math.max(0, math.ceil(Cfg.TimeLimit - run.elapsed))))
			end
			local isNight, _, changesAt = Logic.Night(ctx:Now())
			if isNight then
				return string.format("The stars are out · dawn in %s", Format.duration(math.max(1, changesAt - ctx:Now())))
			end
			return string.format("Opens at night · in %s", Format.duration(math.max(1, changesAt - ctx:Now())))
		end

		local function submit()
			if not run or run.done then
				return
			end
			run.done = true
			busy = true
			local taps = {}
			for _, tap in run.taps do
				table.insert(taps, { star = tap.star, t = tap.t })
			end
			if #taps == 0 then
				-- Nothing tapped: send the first star at the end so the server closes the sighting.
				taps = { { star = run.order[1], t = math.min(run.elapsed, 600) } }
			end
			local ok, res = Util.requestOnce(ctx, "Observatory.Submit", { id = run.id, taps = taps })
			busy = false
			run = nil
			last = if ok and type(res) == "table" then res else nil
			draw()
		end

		local function start(chartId: string)
			if busy or run then
				return
			end
			busy = true
			local ok, res = Util.requestOnce(ctx, "Observatory.Start", { chart = chartId })
			busy = false
			if ok and type(res) == "table" then
				run = {
					id = res.id,
					chart = res.chart,
					stars = StoreKit.asTable(res.stars),
					order = StoreKit.asTable(res.order),
					taps = {},
					elapsed = 0,
					done = false,
				}
				last = nil
			end
			draw()
		end

		local function tapStar(i: number, button: GuiButton)
			if not run or run.done or busy then
				return
			end
			for _, tap in run.taps do
				if tap.star == i then
					return
				end
			end
			table.insert(run.taps, { star = i, t = math.floor(run.elapsed * 1000 + 0.5) / 1000 })
			button:SetAttribute("Tapped", true)
			button.BackgroundColor3 = TAPPED_COLOR
			local wrong = run.order[#run.taps] ~= i
			if wrong or #run.taps >= #run.order then
				submit()
			end
		end

		local function line(parent: Instance, a, b)
			local ax, ay = a.x * SKY, a.y * SKY
			local bx, by = b.x * SKY, b.y * SKY
			local length = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
			New("Frame", {
				Name = "Pattern",
				BackgroundColor3 = C.White,
				BackgroundTransparency = 0.75,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2),
				Size = UDim2.fromOffset(length, 3),
				Rotation = math.deg(math.atan2(by - ay, bx - ax)),
				Parent = parent,
			})
		end

		local function drawSky(isNight: boolean)
			local sky = New("Frame", {
				Name = "Sky",
				BackgroundColor3 = if isNight or run then NIGHT_SKY else DAY_SKY,
				Position = UDim2.fromOffset(6, 6),
				Size = UDim2.fromOffset(SKY, SKY),
				ClipsDescendants = true,
				Parent = body,
			}, { Create.Corner(14), Create.Stroke(3) })
			clockLabel = Util.text({
				Name = "SkyClock",
				Text = clockText(),
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				TextColor3 = C.White,
				Position = UDim2.fromOffset(12, 8),
				Size = UDim2.new(1, -24, 0, 28),
				ZIndex = 3,
				Parent = sky,
			})
			if run then
				for k = 1, #run.order - 1 do
					local a, b = run.stars[run.order[k]], run.stars[run.order[k + 1]]
					if type(a) == "table" and type(b) == "table" then
						line(sky, a, b)
					end
				end
				for i, star in run.stars do
					local first = run.order[1] == i
					local button = New("TextButton", {
						Name = "Star_" .. i,
						Text = if first then "1" else "",
						Font = Theme.Fonts.Display,
						TextSize = Theme.TextSize.Small,
						TextColor3 = C.Ink,
						AutoButtonColor = true,
						BackgroundColor3 = STAR_COLOR,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(star.x * SKY, star.y * SKY),
						Size = UDim2.fromOffset(STAR, STAR),
						ZIndex = 2,
						Parent = sky,
					}, { Create.Round(), Create.Stroke(if first then 3 else 2, if first then C.Gold else nil) })
					button:SetAttribute("Tapped", false)
					button.Activated:Connect(function()
						tapStar(i, button)
					end)
				end
				return
			end
			-- No sighting on: the perks earned so far.
			local s = section()
			local y = 48
			Util.text({
				Name = "PerksTitle",
				Text = "Star perks",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				TextColor3 = C.White,
				Position = UDim2.fromOffset(12, y),
				Size = UDim2.new(1, -24, 0, 26),
				Parent = sky,
			})
			local any = false
			for _, key in Cfg.PerkKeys do
				local value = Logic.Perk(s.charts, key)
				if value > 0 then
					any = true
					y += 30
					Util.text({
						Name = "Perk_" .. key,
						Text = Logic.PerkText(key, value),
						TextSize = Theme.TextSize.Body,
						TextColor3 = STAR_COLOR,
						Position = UDim2.fromOffset(12, y),
						Size = UDim2.new(1, -24, 0, 26),
						Parent = sky,
					})
				end
			end
			if not any then
				Util.text({
					Name = "NoPerks",
					Text = "Finish a star chart to earn its perk for good.",
					TextSize = Theme.TextSize.Small,
					TextColor3 = C.White,
					TextWrapped = true,
					Position = UDim2.fromOffset(12, y + 30),
					Size = UDim2.new(1, -24, 0, 48),
					Parent = sky,
				})
			end
		end

		local function chartRow(list: Instance, def, s, isNight: boolean, seasonId: string, left: number)
			local progress = Logic.Progress(s.charts, def.id)
			local done = progress >= Cfg.Observations
			local inSeason = Logic.Available(def, seasonId)
			local row = New("Frame", {
				Name = "Chart_" .. def.id,
				BackgroundColor3 = C.Card,
				Size = UDim2.new(1, -8, 0, 84),
				LayoutOrder = def.order,
			}, { Create.Corner(10), Create.Stroke(2) })
			row:SetAttribute("Progress", progress)
			Util.text({
				Name = "ChartName",
				Text = def.name,
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(12, 4),
				Size = UDim2.new(1, -170, 0, 26),
				Parent = row,
			})
			Util.text({
				Name = "ChartInfo",
				Text = string.format("Progress %d / %d · %s", progress, Cfg.Observations, Logic.PerkText(def.perk.key, def.perk.value)),
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
				-- Two lines: the perk text ("3% better odds of rare fish") ran past one in Studio.
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromOffset(12, 32),
				Size = UDim2.new(1, -170, 0, 46),
				Parent = row,
			})
			local text, can = "Observe", isNight and left > 0 and run == nil
			if done then
				text, can = "Charted", false
			elseif not inSeason then
				local season = Config.Seasons.ById[def.season]
				text, can = string.format("Back in %s", if season then season.name else "season"), false
			end
			Button.new({
				Name = "Observe",
				Text = text,
				Color = if can then C.Green else C.Gray,
				Disabled = not can,
				Size = UDim2.fromOffset(150, 48),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Parent = row,
				OnClick = function()
					if can then
						start(def.id)
					end
				end,
			})
			row.Parent = list
		end

		function draw()
			if not isOpen then
				return
			end
			Util.clear(body)
			local now = ctx:Now()
			local isNight, night = Logic.Night(now)
			drawnNight = isNight
			local seasonId = Seasons.At(now).id
			drawSky(isNight)

			local s = section()
			local left = sightingsLeft(s, night)
			local card = Util.card({
				Name = "StarCard",
				Title = "Star charts",
				Position = UDim2.fromOffset(410, 0),
				Size = UDim2.new(1, -410, 1, 0),
				Parent = body,
			})
			Util.text({
				Name = "Sightings",
				Text = if isNight
					then string.format("Sightings left tonight: %d / %d", left, Cfg.Sightings)
					else "Come back at night to observe the stars",
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(16, 44),
				Size = UDim2.new(1, -32, 0, 26),
				Parent = card,
			})
			Util.text({
				Name = "StarNews",
				Text = if last
					then resultText(last)
					elseif run then "Tap the stars in the order the faint lines show, starting at 1"
					else "Tap a chart's stars in order three times to chart it.",
				Font = if last then Theme.Fonts.Display else nil,
				TextSize = Theme.TextSize.Small,
				TextColor3 = if last and not last.success then C.Red else C.TextMuted,
				TextWrapped = true,
				Position = UDim2.fromOffset(16, 72),
				Size = UDim2.new(1, -32, 0, 40),
				Parent = card,
			})
			local list = Widgets.List({
				Name = "Charts",
				Position = UDim2.fromOffset(8, 116),
				Size = UDim2.new(1, -16, 1, -124),
				Padding = 6,
				Parent = card,
			})
			for _, def in Cfg.Charts do
				chartRow(list, def, s, isNight, seasonId, left)
			end
			if not Util.unlocked(ctx, Cfg.Unlock) then
				Util.lockOverlay(body, Util.unlockText(Cfg.Unlock))
			end
		end

		local function tick(dt: number)
			if not isOpen then
				return
			end
			if run and not run.done then
				run.elapsed += dt
				if run.elapsed > Cfg.TimeLimit then
					submit()
					return
				end
			end
			local second = math.floor(if run then run.elapsed else ctx:Now())
			if second ~= lastSecond then
				lastSecond = second
				if not run then
					-- Night falls or dawn breaks: the whole screen changes.
					if drawnNight ~= (Logic.Night(ctx:Now())) then
						draw()
						return
					end
				end
				if clockLabel and clockLabel.Parent then
					clockLabel.Text = clockText()
				end
			end
		end

		local watch = StoreKit.watch(store, { "profile.Observatory", "profile.Progression" }, function()
			if not busy and not run then
				draw()
			end
		end)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				watch.Start()
				draw()
				if not conn then
					conn = RunService.Heartbeat:Connect(tick)
				end
			end,
			Close = function()
				isOpen = false
				watch.Stop()
				if conn then
					conn:Disconnect()
					conn = nil
				end
				-- A sighting left open is dropped: it was used when it started, and the server
				-- closes it with the next Start.
				run = nil
			end,
		}
	end,
}
