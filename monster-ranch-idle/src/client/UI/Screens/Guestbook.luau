--[[
	Guestbook (update 3.10 · Ranch Tourists): the ranch's Appeal and what tourists said about it.
	Opened from the Guestbook stand beside the plot gate (Controllers/Tourists) and the Decorate
	screen's "Guestbook" button.

	  left    the Appeal stars and score (0-100), one bar per category (Config.Tourists.Categories),
	          the tip for the weakest one, the next tourist's countdown and the total welcomed
	  right   the newest reviews (profile.Tourists.book): tourist, stars, praise and gripe
	Before Ranch Level Config.Unlocks.Features.tourists a lock covers the body.

	Reads: session.Tourists, profile.Tourists, profile.Progression.level (all tolerated nil).
	No actions: the server decides every visit (Systems/Tourists).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Logic = require(Shared.Logic.Tourists)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Rules = Config.Tourists

local LEFT = 340

return {
	Name = "Guestbook",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Guestbook",
			Color = C.Blue,
			Size = UDim2.fromOffset(900, 500),
			OnClose = function()
				ctx.Router:Close("Guestbook")
			end,
		})

		local isOpen = false
		local bag = Util.bag()
		local lock = nil

		-- Left: the Appeal card ---------------------------------------------------------------
		local card = Util.card({ Name = "Appeal", Size = UDim2.new(0, LEFT, 1, -8), Parent = panel.Body })
		local stars = Util.text({
			Name = "Stars",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = Theme.TextSize.Title,
			TextColor3 = C.Gold,
			Stroke = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(1, -20, 0, 36),
			Parent = card,
		})
		stars:SetAttribute("Localize", false)
		local score = Util.text({
			Name = "Score",
			Text = "",
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(10, 46),
			Size = UDim2.new(1, -20, 0, 24),
			Parent = card,
		})
		local bars = {}
		for i, cat in Rules.Categories do
			local y = 78 + (i - 1) * 32
			Util.text({
				Name = "Label_" .. cat.id,
				Text = cat.name,
				Position = UDim2.fromOffset(14, y),
				Size = UDim2.fromOffset(130, 24),
				Parent = card,
			})
			bars[cat.id] = Widgets.Bar({
				Name = "Part_" .. cat.id,
				Color = Color3.fromHex(cat.color),
				Position = UDim2.fromOffset(148, y + 3),
				Size = UDim2.new(1, -164, 0, 18),
				Parent = card,
			})
		end
		local tipBox = New("Frame", {
			Name = "TipBox",
			BackgroundColor3 = Color3.fromHex("#FFF4D6"),
			Position = UDim2.fromOffset(12, 244),
			Size = UDim2.new(1, -24, 0, 52),
			Parent = card,
		}, { Create.Corner(10), Create.Stroke(2) })
		local tip = Util.text({
			Name = "Tip",
			Text = "",
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(8, 4),
			Size = UDim2.new(1, -16, 1, -8),
			Parent = tipBox,
		})
		local nextLabel = Util.text({
			Name = "Next",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(10, 306),
			Size = UDim2.new(1, -20, 0, 24),
			Parent = card,
		})
		local total = Util.text({
			Name = "Total",
			Text = "",
			TextColor3 = C.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(10, 334),
			Size = UDim2.new(1, -20, 0, 24),
			Parent = card,
		})

		-- Right: the reviews ------------------------------------------------------------------
		local right = New("Frame", {
			Name = "Reviews",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(LEFT + 12, 0),
			Size = UDim2.new(1, -(LEFT + 12), 1, -8),
			Parent = panel.Body,
		})
		Util.text({
			Name = "ReviewsTitle",
			Text = "Reviews",
			Font = Theme.Fonts.Display,
			TextSize = Theme.TextSize.Body + 2,
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.new(1, -12, 0, 28),
			Parent = right,
		})
		local list =
			Widgets.List({ Name = "List", Padding = 8, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 1, -32), Parent = right })

		local function session()
			local s = ctx.Store:Get("session.Tourists")
			return if type(s) == "table" then s else {}
		end

		local function drawReview(i: number, r)
			local good = Rules.Praise[r.good]
			local bad = r.bad and Rules.Gripes[r.bad]
			local praise = good and good[r.gi] and good[r.gi].text
			local gripe = bad and bad[r.bi] and bad[r.bi].text
			local cardFrame = Util.card({
				Name = "Review" .. i,
				Size = UDim2.new(1, -8, 0, if gripe then 92 else 68),
				LayoutOrder = i,
				Parent = list,
			})
			local who = Util.text({
				Name = "Who",
				Text = Rules.Visitors[r.who] or Rules.Visitors[1],
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(12, 6),
				Size = UDim2.new(1, -140, 0, 24),
				Parent = cardFrame,
			})
			who:SetAttribute("Localize", false) -- a name
			local s = Util.text({
				Name = "Stars",
				Text = Logic.StarText(r.stars or 1),
				TextColor3 = C.Gold,
				Stroke = true,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 6),
				Size = UDim2.fromOffset(120, 24),
				Parent = cardFrame,
			})
			s:SetAttribute("Localize", false)
			if praise then
				Util.text({
					Name = "Praise",
					Text = praise,
					TextWrapped = true,
					Position = UDim2.fromOffset(12, 32),
					Size = UDim2.new(1, -24, 0, 26),
					Parent = cardFrame,
				})
			end
			if gripe then
				Util.text({
					Name = "Gripe",
					Text = gripe,
					TextWrapped = true,
					TextColor3 = C.TextMuted,
					Position = UDim2.fromOffset(12, 58),
					Size = UDim2.new(1, -24, 0, 26),
					Parent = cardFrame,
				})
			end
		end

		local function draw()
			if not isOpen then
				return
			end
			local sess = session()
			local open = Util.unlocked(ctx, Rules.Unlock)
			stars.Text = Logic.StarText(sess.stars or 1)
			score.Text = string.format("Appeal %d/100", tonumber(sess.score) or 0)
			local parts = if type(sess.parts) == "table" then sess.parts else {}
			for id, bar in bars do
				bar:SetValue(tonumber(parts[id]) or 0)
			end
			tip.Text = if type(sess.tip) == "string" then sess.tip else ""
			local profile = ctx.Store:Get("profile.Tourists")
			profile = if type(profile) == "table" then profile else {}
			total.Text = string.format("Tourists welcomed: %d", tonumber(profile.count) or 0)
			nextLabel.Visible = open

			Util.clear(list)
			local book = if type(profile.book) == "table" then profile.book else {}
			for i, r in book do
				if type(r) == "table" then
					drawReview(i, r)
				end
			end
			if #book == 0 then
				Util.text({
					Name = "Empty",
					Text = "No reviews yet. A tourist visits every 10 minutes.",
					TextWrapped = true,
					TextColor3 = C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, -8, 0, 60),
					Parent = list,
				})
			end

			if lock then
				lock:Destroy()
				lock = nil
			end
			if not open then
				lock = Util.lockOverlay(panel.Body, Util.unlockText(Rules.Unlock))
			end
		end
		local refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				bag.clean()
				for _, path in { "session.Tourists", "profile.Tourists", "profile.Progression.level" } do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				nextLabel.Text = ""
				bag.add(Widgets.Countdown(nextLabel, function()
					return tonumber(session().nextAt)
				end, function(left: number)
					return string.format("Next tourist in %s", Format.clock(left))
				end))
				draw()
			end,
			Close = function()
				isOpen = false
				bag.clean()
			end,
		}
	end,
}
