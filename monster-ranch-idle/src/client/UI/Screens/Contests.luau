--[[
	Showtime screen (update 1.5): Monster Contests.

	Top: this show's theme, its tags and the phase clock. The body follows global.Contests:
	  idle     next show countdown and theme, the last podium, your contest stats
	  entry    your entry (Enter / Change → Monsters pick → Contests.Enter, Withdraw, Style it
	           → Wardrobe) and everyone who has entered so far
	  runway   the monster walking now (3D), whose it is, and 1–5 stars (Contests.Vote)
	  results  the podium: rank, monster, owner, score and votes
	Header: Contest Ribbons and a Wardrobe shortcut. Opened from the Showtime Stage in the hub.

	Reads: global.Contests, session.Contests, profile.Contests, profile.Currency.ribbons,
	profile.Progression.level.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local ViewportMonster = require(UI.Components.ViewportMonster)
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Contests

local PHASE_TEXT = {
	idle = "Next show in %s",
	entry = "Entries close in %s",
	runway = "Next walk in %s",
	results = "Results · %s",
}

return {
	Name = "Contests",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Showtime",
			Color = C.Pink,
			Size = UDim2.fromOffset(1000, 500),
			OnClose = function()
				ctx.Router:Close("Contests")
			end,
		})
		local ribbonPill = Widgets.Pill({ Icon = "ribbon", Text = "0", Parent = panel.HeaderRight })
		ribbonPill.Root.LayoutOrder = 1
		Button.new({
			Name = "WardrobeLink",
			Text = "Wardrobe",
			Color = C.Purple,
			TextSize = Theme.TextSize.Small,
			Size = UDim2.fromOffset(120, 36),
			LayoutOrder = 2,
			Parent = panel.HeaderRight,
			OnClick = function()
				local entered = StoreKit.tbl(ctx.Store, "session.Contests").entered
				ctx.Router:Open("Wardrobe", if type(entered) == "string" then { id = entered } else nil)
			end,
		})

		local isOpen = false
		local bag = Util.bag()
		local refresh

		local function G()
			return StoreKit.tbl(ctx.Store, "global.Contests")
		end
		local function mine()
			return StoreKit.tbl(ctx.Store, "session.Contests")
		end

		-- Theme strip ---------------------------------------------------------------------------
		local strip = Util.card({ Size = UDim2.new(1, 0, 0, 86), Parent = panel.Body })
		local themeLabel = Util.text({
			Name = "Theme",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = Theme.TextSize.Title or 28,
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.new(0.6, 0, 0, 34),
			Parent = strip,
		})
		local descLabel = Util.text({
			Text = "",
			TextColor3 = C.TextMuted,
			TextSize = Theme.TextSize.Small,
			Position = UDim2.fromOffset(14, 42),
			Size = UDim2.new(0.6, 0, 0, 20),
			Parent = strip,
		})
		local tagRow = New("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 62),
			Size = UDim2.new(0.6, 0, 0, 22),
			Parent = strip,
		}, { Create.List("x", 6) })
		local clock = Util.text({
			Name = "Clock",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 10),
			Size = UDim2.new(0.4, -20, 0, 30),
			Parent = strip,
		})
		local phaseLabel = Util.text({
			Text = "",
			TextColor3 = C.TextMuted,
			TextSize = Theme.TextSize.Small,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 46),
			Size = UDim2.new(0.4, -20, 0, 22),
			Parent = strip,
		})
		local stopClock = nil

		-- Body ------------------------------------------------------------------------------------
		local body = New("Frame", {
			Name = "Stage",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 96),
			Size = UDim2.new(1, 0, 1, -96),
			Parent = panel.Body,
		})
		local runway = ViewportMonster.new({
			Name = "Runway",
			Size = UDim2.fromOffset(300, 290),
			Position = UDim2.fromOffset(10, 0),
			Spin = 0.8,
			Parent = body,
		})
		local runwayKey = ""

		local function enterFlow()
			Util.pick(ctx, {
				title = "Pick a monster for the show",
				max = 1,
				returnTo = "Contests",
				onPick = function(ids)
					local ok = Util.requestOnce(ctx, "Contests.Enter", { id = ids[1] })
					if ok then
						ctx:Toast("You're in the show! Dress it up before the runway starts.", "success")
					end
				end,
			})
		end

		local function drawEntry(g)
			local entered = mine().entered
			local myAp = nil
			for _, e in (if type(g.entries) == "table" then g.entries else {}) do
				if e.userId == ctx.Player.UserId then
					myAp = e.appearance
				end
			end
			local mineCard = Util.card({ Title = "Your entry", Size = UDim2.new(0, 300, 1, 0), Parent = body })
			if myAp then
				local icon = MonsterIcon.new(myAp, 120)
				icon.Position = UDim2.new(0.5, -60, 0, 40)
				icon.Parent = mineCard
			else
				Util.text({
					Text = "Enter a monster and dress it to fit the theme!",
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(10, 60),
					Size = UDim2.new(1, -20, 0, 60),
					Parent = mineCard,
				})
			end
			local row = New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				Size = UDim2.new(1, -12, 0, 46),
				Parent = mineCard,
			}, { Create.List("x", 6, Enum.HorizontalAlignment.Center) })
			Button.new({
				Name = "EnterButton",
				Text = if entered then "Change" else "Enter a monster",
				Color = C.Green,
				TextSize = Theme.TextSize.Small,
				Size = UDim2.fromOffset(if entered then 84 else 180, 44),
				LayoutOrder = 1,
				Parent = row,
				OnClick = function()
					if not Util.unlocked(ctx, Cfg.Unlock) then
						ctx:Toast(Util.unlockText(Cfg.Unlock), "error")
						return
					end
					enterFlow()
				end,
			})
			if entered then
				Button.new({
					Name = "StyleIt",
					Text = "Style it",
					Color = C.Pink,
					TextSize = Theme.TextSize.Small,
					Size = UDim2.fromOffset(92, 44),
					LayoutOrder = 2,
					Parent = row,
					OnClick = function()
						ctx.Router:Open("Wardrobe", { id = entered })
					end,
				})
				Button.new({
					Name = "Withdraw",
					Text = "Withdraw",
					Color = C.Gray,
					TextSize = Theme.TextSize.Small,
					Size = UDim2.fromOffset(92, 44),
					LayoutOrder = 3,
					Parent = row,
					OnClick = function()
						Util.requestOnce(ctx, "Contests.Withdraw")
					end,
				})
			end
			local others = Util.card({
				Title = string.format("In the show (%d / %d)", #(g.entries or {}), Cfg.MaxEntries),
				Position = UDim2.fromOffset(310, 0),
				Size = UDim2.new(1, -310, 1, 0),
				Parent = body,
			})
			local list = Widgets.Scroll({
				Cell = Vector2.new(96, 120),
				Padding = 6,
				Position = UDim2.fromOffset(6, 38),
				Size = UDim2.new(1, -12, 1, -44),
				Parent = others,
			})
			for i, e in (if type(g.entries) == "table" then g.entries else {}) do
				if type(e.appearance) == "table" and Config.Species.ById[e.appearance.line] then
					local card = MonsterIcon.card(e.appearance, 96, e.name)
					card.LayoutOrder = i
					card.Parent = list
				end
			end
		end

		local function drawRunway(g)
			local entry = type(g.entries) == "table" and g.entries[g.current or 0]
			if not entry then
				return
			end
			local key = tostring(g.show) .. ":" .. tostring(g.current)
			if key ~= runwayKey and type(entry.appearance) == "table" then
				runwayKey = key
				runway:SetAppearance(entry.appearance)
			end
			runway.Root.Visible = true
			local info = Util.card({ Position = UDim2.fromOffset(320, 0), Size = UDim2.new(1, -320, 1, 0), Parent = body })
			Util.text({
				Name = "Walker",
				Text = string.format("%s's %s", entry.name, entry.appearance and entry.appearance.name or "monster"),
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(10, 20),
				Size = UDim2.new(1, -20, 0, 32),
				Parent = info,
			})
			Util.text({
				Text = string.format("Walk %d of %d", g.current, #g.entries),
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(10, 56),
				Size = UDim2.new(1, -20, 0, 22),
				Parent = info,
			})
			if entry.userId == ctx.Player.UserId then
				Util.text({
					Text = "Your monster is on the runway! Strike a pose.",
					Font = Theme.Fonts.Display,
					TextColor3 = C.Pink,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(10, 120),
					Size = UDim2.new(1, -20, 0, 40),
					Parent = info,
				})
				return
			end
			local myVote = (mine().votes or {})[g.current]
			local stars = New("Frame", {
				Name = "Stars",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(10, 110),
				Size = UDim2.new(1, -20, 0, 70),
				Parent = info,
			}, { Create.List("x", 10, Enum.HorizontalAlignment.Center) })
			for n = 1, 5 do
				Button.new({
					Name = "Star" .. n,
					Text = "★",
					TextSize = 30,
					Color = if myVote and n <= myVote then C.Gold else C.Gray,
					Size = UDim2.fromOffset(64, 64),
					LayoutOrder = n,
					Parent = stars,
					OnClick = function()
						Util.requestOnce(ctx, "Contests.Vote", { entry = g.current, stars = n })
					end,
				})
			end
			Util.text({
				Text = if myVote
					then string.format("You gave %d ★. Tap again to change it.", myVote)
					else "How well does it fit the theme?",
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(10, 190),
				Size = UDim2.new(1, -20, 0, 22),
				Parent = info,
			})
		end

		local function drawPodium(g, title: string)
			local card = Util.card({ Title = title, Size = UDim2.new(0.62, -6, 1, 0), Parent = body })
			local list = Widgets.List({ Position = UDim2.fromOffset(6, 38), Size = UDim2.new(1, -12, 1, -44), Padding = 4, Parent = card })
			local results = if type(g.results) == "table" then g.results else {}
			if #results == 0 then
				Util.text({
					Text = "No results yet. Enter the next show!",
					TextColor3 = C.TextMuted,
					Size = UDim2.new(1, 0, 0, 30),
					Parent = list,
				})
			end
			for i, r in results do
				local row = New("Frame", {
					Name = "Result_" .. i,
					BackgroundColor3 = if r.userId == ctx.Player.UserId then C.Gold else C.PanelDeep,
					Size = UDim2.new(1, -4, 0, 56),
					LayoutOrder = i,
					Parent = list,
				}, { Create.Corner(8) })
				Util.text({
					Text = if r.rank == 1 then "🥇" elseif r.rank == 2 then "🥈" elseif r.rank == 3 then "🥉" else "#" .. r.rank,
					Font = Theme.Fonts.Display,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.fromOffset(44, 56),
					Parent = row,
				})
				if type(r.appearance) == "table" and Config.Species.ById[r.appearance.line] then
					local icon = MonsterIcon.new(r.appearance, 48)
					icon.Position = UDim2.fromOffset(46, 4)
					icon.Parent = row
				end
				Util.text({
					Text = string.format("%s · %s", r.name or "?", r.appearance and r.appearance.name or ""),
					Position = UDim2.fromOffset(100, 0),
					Size = UDim2.new(1, -220, 1, 0),
					Parent = row,
				})
				Util.text({
					Text = string.format("%.1f ★ · %d vote%s", r.score or 0, r.votes or 0, if r.votes == 1 then "" else "s"),
					TextXAlignment = Enum.TextXAlignment.Right,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -10, 0, 0),
					Size = UDim2.fromOffset(120, 56),
					Parent = row,
				})
			end
			local stats = StoreKit.tbl(ctx.Store, "profile.Contests")
			local side =
				Util.card({ Title = "Your shows", Position = UDim2.new(0.62, 6, 0, 0), Size = UDim2.new(0.38, -6, 1, 0), Parent = body })
			Util.text({
				Text = string.format(
					"Shows entered: %d\nWins: %d · Top 3: %d\nBest place: %s\nRunway votes: %d\n\nPrizes: 1st %d, 2nd %d, 3rd %d Ribbons (+ gems). Everyone who enters gets %d, and every walk you rate gives 1 (up to %d a show).",
					tonumber(stats.shows) or 0,
					tonumber(stats.wins) or 0,
					tonumber(stats.podiums) or 0,
					if (tonumber(stats.best) or 0) > 0 then "#" .. tostring(stats.best) else "–",
					tonumber(stats.votes) or 0,
					Cfg.Prizes[1][1].amount,
					Cfg.Prizes[2][1].amount,
					Cfg.Prizes[3][1].amount,
					Cfg.Prizes.entered[1].amount,
					Cfg.VoteRibbonMax
				),
				TextWrapped = true,
				TextSize = Theme.TextSize.Small,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromOffset(12, 40),
				Size = UDim2.new(1, -24, 1, -48),
				Parent = side,
			})
		end

		local lockOverlay = nil
		local function draw()
			if not isOpen then
				return
			end
			local g = G()
			local state = if type(g.state) == "string" then g.state else "idle"
			ribbonPill:SetText(Format.short(StoreKit.balance(ctx.Store, "ribbons")))
			local now = ctx:Now()
			local themeDef = Cfg.ThemeById[g.theme] or Cfg.ThemeFor(Cfg.Show(now).show)
			if state == "idle" then
				themeDef = Cfg.ThemeFor(Cfg.Show(now).show + 1)
			end
			themeLabel.Text = themeDef.name
			themeLabel.TextColor3 = Color3.fromHex(themeDef.color)
			descLabel.Text = themeDef.desc
			Util.clear(tagRow)
			for _, tag in themeDef.tags do
				Widgets.Chip({ Text = string.upper(tag), Color = Color3.fromHex(themeDef.color), TextSize = 13, Parent = tagRow })
			end
			phaseLabel.Text = if state == "idle"
				then "Next theme"
				elseif state == "entry" then "Entries open: pick and dress a monster"
				elseif state == "runway" then "On the runway: rate each look"
				else "Results are in!"
			if stopClock then
				stopClock()
			end
			local endsAt = if state == "idle" then g.nextAt else g.endsAt
			clock.Text = ""
			stopClock = Widgets.Countdown(clock, function()
				return endsAt
			end, function(left)
				return string.format(PHASE_TEXT[state] or "%s", Format.clock(left))
			end)

			for _, child in body:GetChildren() do
				if child ~= runway.Root then
					child:Destroy()
				end
			end
			runway.Root.Visible = false
			if state == "entry" then
				drawEntry(g)
			elseif state == "runway" then
				drawRunway(g)
			elseif state == "results" then
				drawPodium(g, "Results")
			else
				drawPodium(g, "Last show")
			end
			if lockOverlay then
				lockOverlay:Destroy()
				lockOverlay = nil
			end
			if not Util.unlocked(ctx, Cfg.Unlock) and state ~= "runway" then
				lockOverlay = Util.lockOverlay(panel.Body, Util.unlockText(Cfg.Unlock))
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				bag.clean()
				for _, path in
					{ "global.Contests", "session.Contests", "profile.Contests", "profile.Currency.ribbons", "profile.Progression.level" }
				do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				refresh()
			end,
			Close = function()
				isOpen = false
				if stopClock then
					stopClock()
					stopClock = nil
				end
				bag.clean()
			end,
		}
	end,
}
