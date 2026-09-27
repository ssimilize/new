--[[
	Events (update 3.8 · Reasons to come back): the events calendar. Everyone has it (no unlock);
	the HUD's calendar button and its countdown chips open it.

	Three sections from Logic/Calendar.Sections(now):
	  Now         what runs now, with an "Ends in" countdown
	  This week   what starts up to the next Saturday reset
	  Coming up   the next 30 days, then the next big date of each kind however far away
	Each row: an icon, the name, its date and a one-line blurb, a live countdown, and "Go" when
	the entry names a screen this client has. An empty section says so in a friendly line.
	Countdowns tick every second while open; a row whose moment passes redraws the lists.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Format = require(Shared.Logic.Format)
local Calendar = require(Shared.Logic.Calendar)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local Icon = require(UI.Components.Icon)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors

local ROW_HEIGHT = 64
local DATE_WIDTH = 116

local SECTIONS = {
	{ id = "now", name = "Now", title = "Now", empty = "Nothing special is running right now." },
	{ id = "week", name = "Week", title = "This week", empty = "Nothing else starts before the weekly reset." },
	{ id = "later", name = "Later", title = "Coming up", empty = "Nothing more is on the calendar yet." },
}

-- Long waits read as "12d 4h", the last day as a ticking clock.
local function left(seconds: number): string
	if seconds >= 86400 then
		return Format.duration(seconds)
	end
	return Format.clock(seconds)
end

return {
	Name = "Events",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Events",
			Color = C.Blue,
			Size = UDim2.fromOffset(1000, 520),
			OnClose = function()
				ctx.Router:Close("Events")
			end,
		})

		local isOpen = false
		local tickers = {} -- { label, target, running }
		local nextChange = math.huge -- the soonest moment a row changes section

		local list = Widgets.List({ Name = "Calendar", Padding = 8, Parent = panel.Body })

		local function row(e, now: number, order: number)
			local isRunning = e.startsAt <= now
			local card = New("Frame", {
				Name = "Row_" .. e.key,
				BackgroundColor3 = C.Card,
				Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
				LayoutOrder = order,
				Parent = list,
			}, { Create.Corner(Theme.Radius.Card), Create.Stroke(Theme.Stroke.Card) })
			local icon = Icon.new(e.icon, 40)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 12, 0.5, 0)
			icon.Parent = card
			local hasGo = e.screen ~= nil and ctx.Router:Has(e.screen)
			local right = if hasGo then 330 else 230
			Util.text({
				Name = "Title",
				Text = e.name,
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(64, 6),
				Size = UDim2.new(1, -64 - right, 0, 26),
				Parent = card,
			})
			-- Date and blurb are separate labels: one joined string would read as a
			-- "{1} and {2}" template to Localize.
			Util.text({
				Name = "Date",
				Text = Format.date(e.startsAt),
				Position = UDim2.fromOffset(64, 34),
				Size = UDim2.fromOffset(DATE_WIDTH, 22),
				Parent = card,
			})
			Util.text({
				Name = "Blurb",
				Text = e.blurb or "",
				TextColor3 = C.TextMuted,
				Position = UDim2.fromOffset(64 + DATE_WIDTH, 34),
				Size = UDim2.new(1, -64 - DATE_WIDTH - right, 0, 22),
				Parent = card,
			})
			local target = if isRunning then e.endsAt else e.startsAt
			if target then
				Util.text({
					Name = "When",
					Text = if isRunning then "Ends in" else "Starts in",
					TextColor3 = C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Right,
					Position = UDim2.new(1, -right, 0, 8),
					Size = UDim2.fromOffset(210, 22),
					Parent = card,
				})
				local time = Util.text({
					Name = "Countdown",
					Text = left(target - now),
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body,
					TextXAlignment = Enum.TextXAlignment.Right,
					Position = UDim2.new(1, -right, 0, 30),
					Size = UDim2.fromOffset(210, 26),
					Parent = card,
				})
				table.insert(tickers, { label = time, target = target })
				nextChange = math.min(nextChange, target)
			end
			if hasGo then
				Button.new({
					Name = "Go",
					Text = "Go",
					Color = C.Green,
					Size = UDim2.fromOffset(84, 44),
					TextSize = Theme.TextSize.Body,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Parent = card,
					OnClick = function()
						ctx.Router:Open(e.screen)
					end,
				})
			end
		end

		local function draw()
			Util.clear(list)
			table.clear(tickers)
			nextChange = math.huge
			local now = ctx:Now()
			local sections = Calendar.Sections(now)
			local order = 0
			for _, s in SECTIONS do
				order += 1
				Util.text({
					Name = "Header_" .. s.name,
					Text = s.title,
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Header,
					Size = UDim2.new(1, -8, 0, 32),
					LayoutOrder = order,
					Parent = list,
				})
				local entries = sections[s.id]
				if #entries == 0 then
					order += 1
					Util.text({
						Name = "Empty_" .. s.name,
						Text = s.empty,
						TextColor3 = C.TextMuted,
						Size = UDim2.new(1, -8, 0, 26),
						LayoutOrder = order,
						Parent = list,
					})
				end
				for _, e in entries do
					order += 1
					row(e, now, order)
				end
			end
		end

		local function tick()
			local now = ctx:Now()
			if now >= nextChange then
				draw()
				return
			end
			for _, t in tickers do
				t.label.Text = left(t.target - now)
			end
		end

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				draw()
				task.spawn(function()
					while isOpen do
						task.wait(1)
						if isOpen then
							tick()
						end
					end
				end)
			end,
			Close = function()
				isOpen = false
			end,
		}
	end,
}
