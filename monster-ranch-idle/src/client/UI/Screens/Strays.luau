--[[
	Strays screen (update 3.13 · Wild things): the befriend minigame for the stray wandering on the
	player's plot. Opened from the stray's "Befriend" prompt (Controllers/Strays); no HUD button.

	Left: the stray (portrait, name, rarity and element) and when it wanders off.
	Right: with no stray, when the next one comes and the Stray Log totals. With a stray, an
	"Approach" button calls Strays.Start (its one attempt) and the three rounds play here: each
	round shows the stray's hint and the choices "Wait quietly" (Choice_wait) and "Offer <treat>"
	(Choice_<flavour>, one per flavour the player has food of; each costs one). After the last
	round the choices go to Strays.Submit once; the server says whether it was befriended.
	Test hooks: the round frame carries a Round attribute.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Strays)
local Appearance = require(Shared.Logic.Appearance)
local Format = require(Shared.Logic.Format)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local StoreKit = require(UI.Components.StoreKit)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Strays

return {
	Name = "Strays",
	Build = function(ctx)
		local store = ctx.Store
		local panel = Panel.new({
			Title = "Stray Monsters",
			Color = C.Orange,
			Size = UDim2.fromOffset(860, 470),
			OnClose = function()
				ctx.Router:Close("Strays")
			end,
		})

		local isOpen = false
		local busy = false
		local run = nil -- { slot, line, rarity, favourite, hints, choices }
		local last = nil -- the last Submit result
		local clockLabel = nil
		local lastSecond = -1
		local conn = nil

		local body = New("Frame", { Name = "StraysBody", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })

		local draw

		local function current()
			local s = StoreKit.tbl(store, "session.Strays")
			local stray = s.stray
			if type(stray) ~= "table" or (tonumber(stray.leavesAt) or 0) <= ctx:Now() then
				return nil, s
			end
			return stray, s
		end

		local function clockText(): string
			local stray, s = current()
			if stray then
				return string.format("Wanders off in %s", Format.duration(math.max(1, stray.leavesAt - ctx:Now())))
			end
			local nextAt = tonumber(s.nextAt) or 0
			return string.format("Next stray in %s", Format.duration(math.max(1, nextAt - ctx:Now())))
		end

		local function submit()
			busy = true
			local ok, res = Util.requestOnce(ctx, "Strays.Submit", { slot = run.slot, choices = run.choices })
			busy = false
			if ok and type(res) == "table" then
				last = res
				run = nil
			else
				-- Refused (short of food, barn full): the rounds start over, nothing was used.
				run.choices = {}
			end
			draw()
		end

		local function approach(slot: number)
			if busy or run then
				return
			end
			busy = true
			local ok, res = Util.requestOnce(ctx, "Strays.Start", { slot = slot })
			busy = false
			if ok and type(res) == "table" then
				run = {
					slot = res.slot,
					line = res.line,
					rarity = res.rarity,
					favourite = res.favourite,
					hints = StoreKit.asTable(res.hints),
					choices = {},
				}
				last = nil
			end
			draw()
		end

		local function choose(choice: string)
			if busy or not run then
				return
			end
			table.insert(run.choices, choice)
			if #run.choices >= Cfg.Rounds then
				submit()
			else
				draw()
			end
		end

		local function drawStray(line: string?, rarity: number?)
			local card = Util.card({ Name = "StrayCard", Size = UDim2.fromOffset(300, 430), Parent = body })
			if line then
				local icon = MonsterIcon.new(Appearance.Preview(line, 3, nil, rarity or 1, 0), 160)
				icon.AnchorPoint = Vector2.new(0.5, 0)
				icon.Position = UDim2.new(0.5, 0, 0, 16)
				icon.Parent = card
				Util.text({
					Name = "StrayName",
					Text = string.format("Stray %s", Logic.Name(line)),
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body + 2,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(10, 186),
					Size = UDim2.new(1, -20, 0, 30),
					Parent = card,
				})
				local chips = New("Frame", {
					Name = "Chips",
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(10, 222),
					Size = UDim2.new(1, -20, 0, 32),
				}, { Create.List("x", 6, Enum.HorizontalAlignment.Center) })
				Widgets.RarityChip(rarity or 1, chips)
				local def = Config.Species.ById[line]
				if def and def.elements[1] then
					Widgets.ElementChip(def.elements[1], chips)
				end
				chips.Parent = card
			else
				Util.text({
					Name = "NoStray",
					Text = "No stray around right now",
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextWrapped = true,
					Position = UDim2.fromOffset(10, 120),
					Size = UDim2.new(1, -20, 0, 60),
					Parent = card,
				})
			end
			clockLabel = Util.text({
				Name = "StrayClock",
				Text = clockText(),
				TextSize = Theme.TextSize.Small + 1,
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(10, 262),
				Size = UDim2.new(1, -20, 0, 26),
				Parent = card,
			})
			local p = StoreKit.tbl(store, "profile.Strays")
			local left = tonumber(StoreKit.tbl(store, "session.Strays").left) or Cfg.DailyCap
			Util.text({
				Name = "StrayTotals",
				Text = string.format("Befriended: %d · today %d / %d", tonumber(p.total) or 0, Cfg.DailyCap - left, Cfg.DailyCap),
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = true,
				Position = UDim2.fromOffset(10, 380),
				Size = UDim2.new(1, -20, 0, 40),
				Parent = card,
			})
		end

		local function drawResult(card: Instance)
			local name = Logic.Name(last.line)
			local text
			if last.befriended then
				local stat = Config.Genetics.StatNames[last.gene or ""]
				text = if stat
					then string.format("Befriended! %s joined your ranch · %s gene +1 grade", name, stat)
					else string.format("Befriended! %s joined your ranch", name)
			else
				text = string.format("The %s ran off... %d / %d right", name, last.correct or 0, Cfg.Rounds)
			end
			Util.text({
				Name = "StrayResult",
				Text = text,
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				TextColor3 = if last.befriended then C.Green else C.Red,
				TextWrapped = true,
				Position = UDim2.fromOffset(16, 48),
				Size = UDim2.new(1, -32, 0, 60),
				Parent = card,
			})
		end

		local function drawRound(card: Instance)
			local i = #run.choices + 1
			local round = New("Frame", {
				Name = "StrayRound",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 44),
				Size = UDim2.new(1, -32, 1, -56),
				Parent = card,
			})
			round:SetAttribute("Round", i)
			Util.text({
				Name = "RoundTitle",
				Text = string.format("Round %d / %d", i, Cfg.Rounds),
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				Size = UDim2.new(1, 0, 0, 28),
				Parent = round,
			})
			Util.text({
				Name = "Hint",
				Text = tostring(run.hints[i] or ""),
				TextSize = Theme.TextSize.Body,
				TextColor3 = C.Purple,
				TextWrapped = true,
				Position = UDim2.fromOffset(0, 32),
				Size = UDim2.new(1, 0, 0, 52),
				Parent = round,
			})
			local choices = New("Frame", {
				Name = "Choices",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 92),
				Size = UDim2.new(1, 0, 1, -92),
			}, { Create.Grid(Vector2.new(250, 56), 8) })
			choices.Parent = round
			Button.new({
				Name = "Choice_wait",
				Text = "Wait quietly",
				Color = C.Blue,
				Size = UDim2.fromOffset(250, 56),
				LayoutOrder = 0,
				Parent = choices,
				OnClick = function()
					choose("wait")
				end,
			})
			-- Treats already picked this attempt are not spent yet, but they will be.
			local planned = {}
			for _, c in run.choices do
				planned[c] = (planned[c] or 0) + Cfg.TreatCost
			end
			local order = 0
			for _, food in Config.Food.List do
				local have = StoreKit.balance(store, "food." .. food.id) - (planned[food.id] or 0)
				if have >= Cfg.TreatCost then
					order += 1
					Button.new({
						Name = "Choice_" .. food.id,
						Text = string.format("Offer %s (%d)", food.name, have),
						Color = C.Orange,
						Size = UDim2.fromOffset(250, 56),
						LayoutOrder = order,
						Parent = choices,
						OnClick = function()
							choose(food.id)
						end,
					})
				end
			end
			if order == 0 then
				Util.text({
					Name = "NoFood",
					Text = "No food to offer. Grow some in the garden!",
					TextSize = Theme.TextSize.Small,
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					LayoutOrder = 9,
					Size = UDim2.fromOffset(250, 56),
					Parent = choices,
				})
			end
		end

		function draw()
			if not isOpen then
				return
			end
			Util.clear(body)
			local stray = current()
			local showLine = if run then run.line elseif stray then stray.line elseif last then last.line else nil
			local showRarity = if run then run.rarity elseif stray then stray.rarity elseif last then last.rarity else nil
			drawStray(showLine, showRarity)
			local card = Util.card({
				Name = "BefriendCard",
				Title = "Befriend",
				Position = UDim2.fromOffset(312, 0),
				Size = UDim2.new(1, -312, 1, 0),
				Parent = body,
			})
			if run then
				drawRound(card)
			elseif last then
				drawResult(card)
			elseif stray and not stray.tried then
				Util.text({
					Name = "StrayIntro",
					Text = string.format(
						"A shy stray! Read its mood each round: offer a treat or wait quietly. Get %d of %d right to befriend it.",
						Cfg.Need,
						Cfg.Rounds
					),
					TextSize = Theme.TextSize.Body,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					Position = UDim2.fromOffset(16, 48),
					Size = UDim2.new(1, -32, 0, 84),
					Parent = card,
				})
				local slot = stray.slot
				Button.new({
					Name = "Approach",
					Text = "Approach",
					Color = C.Green,
					Size = UDim2.new(0.5, 0, 0, 56),
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 150),
					Parent = card,
					OnClick = function()
						approach(slot)
					end,
				})
			else
				Util.text({
					Name = "StrayWaiting",
					Text = if stray
						then "You already tried with this stray. Another will wander by soon."
						else "Strays wander onto your ranch while you play. Come say hello when one arrives!",
					TextSize = Theme.TextSize.Body,
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					Position = UDim2.fromOffset(16, 48),
					Size = UDim2.new(1, -32, 0, 84),
					Parent = card,
				})
			end
			if not Util.unlocked(ctx, Cfg.Unlock) then
				Util.lockOverlay(body, Util.unlockText(Cfg.Unlock))
			end
		end

		local function tick()
			if not isOpen then
				return
			end
			local second = math.floor(ctx:Now())
			if second ~= lastSecond then
				lastSecond = second
				if clockLabel and clockLabel.Parent then
					clockLabel.Text = clockText()
				end
			end
		end

		local watch = StoreKit.watch(store, { "session.Strays", "profile.Strays", "profile.Progression" }, function()
			if not busy and not run then
				draw()
			end
		end)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				last = nil
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
				-- An attempt in progress is kept (the server keeps it open too), so reopening the
				-- screen picks the rounds up where they were.
			end,
		}
	end,
}
