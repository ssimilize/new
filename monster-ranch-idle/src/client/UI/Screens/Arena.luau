--[[
	Arena screen (update 2.1): asynchronous PvP with normalized stats.

	Battle   "Find opponents" (Arena.Refresh) and up to Config.Arena.Candidates opponents,
	         each with rating, tier and team; Fight → pick 3 Adults → Arena.Attack → the
	         battle plays in Parts/BattleReplay, with the rating change on the result card.
	Defense  your defense team (profile.Arena.defense) and "Set defense team" (pick 3 Adults
	         → Arena.SetDefense), with a note on how stats are normalized.
	Rewards  tiers and their weekly rewards, this week's best tier, and "Claim" for the week
	         that just ended (Arena.ClaimWeekly).
	Season   (3.8) the arena season and its ends-in countdown (or "Season 1 starts in"), the
	         season's featured lines (+FeaturedBoost), your season best tier, the season reward
	         track (Config.Arena.SeasonRewards) and the season board's top 10 with your rank
	         (global.Leaderboards, board "arena"), or your rating and tier when you're not on it.
	Header: your rating and tier, battles left today. Opened from the Champions Arena.

	Reads: session.Arena, profile.Arena, profile.Monsters.list, profile.Progression.level,
	global.Leaderboards.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local ArenaLogic = require(Shared.Logic.Arena)
local Appearance = require(Shared.Logic.Appearance)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)
local Battle = require(script.Parent.Parts.Battle)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Arena

local function tierDef(id: string?)
	for _, t in Cfg.Tiers do
		if t.id == id then
			return t
		end
	end
	return Cfg.Tiers[1]
end

return {
	Name = "Arena",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Champions Arena",
			Color = C.Red,
			Size = UDim2.fromOffset(1000, 500),
			OnClose = function()
				ctx.Router:Close("Arena")
			end,
		})
		local ratingPill = Widgets.Pill({ Icon = "trophy", Text = "1000", Parent = panel.HeaderRight })
		ratingPill.Root.LayoutOrder = 1

		local isOpen = false
		local bag = Util.bag()
		local refresh
		local tab = "battle"

		local function sess()
			return StoreKit.tbl(ctx.Store, "session.Arena")
		end
		local function prof()
			return StoreKit.tbl(ctx.Store, "profile.Arena")
		end

		local tabs = Widgets.Tabs({
			Tabs = {
				{ id = "battle", text = "Battle" },
				{ id = "defense", text = "Defense" },
				{ id = "rewards", text = "Rewards" },
				{ id = "season", text = "Season" },
			},
			Selected = tab,
			Parent = panel.Body,
			OnChanged = function(id)
				tab = id
				refresh()
			end,
		})
		local content = New("Frame", {
			Name = "ArenaContent",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 52),
			Size = UDim2.new(1, 0, 1, -52),
			Parent = panel.Body,
		})

		local function teamRow(team, parent, size: number)
			local row = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset((size + 6) * Cfg.TeamSize, size),
				Parent = parent,
			}, { Create.List("x", 6) })
			for i, f in team or {} do
				local ap = f.look or f
				if type(ap) == "table" and Config.Species.ById[ap.line] then
					local icon = MonsterIcon.new(ap, size)
					icon.LayoutOrder = i
					icon.Parent = row
				end
			end
			return row
		end

		local function pickAdults(title: string, onPick)
			Util.pick(ctx, {
				title = title,
				max = Cfg.TeamSize,
				filter = function(m)
					return m.stage == 3
				end,
				returnTo = "Arena",
				onPick = function(ids)
					if #ids ~= Cfg.TeamSize then
						ctx:Toast(string.format("Pick %d Adults", Cfg.TeamSize), "error")
						return
					end
					onPick(ids)
				end,
			})
		end

		local function fight(index: number, candidate)
			pickAdults(string.format("Pick %d Adults to fight %s", Cfg.TeamSize, candidate.name or "them"), function(ids)
				local ok, res = Util.requestOnce(ctx, "Arena.Attack", { candidate = index, ids = ids })
				if not ok or type(res) ~= "table" then
					return
				end
				local sign = if (res.delta or 0) >= 0 then "+" else ""
				Battle.play(ctx, {
					replay = res.replay,
					win = res.win,
					rewards = res.rewards,
					title = string.format("Arena · vs %s", candidate.name or "?"),
					winText = string.format("Victory! Rating %s%d → %d", sign, res.delta or 0, res.rating or 0),
					loseText = string.format("Defeat. Rating %s%d → %d", sign, res.delta or 0, res.rating or 0),
					stage = "arena",
				})
			end)
		end

		local function drawBattle()
			local s = sess()
			local top = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), Parent = content })
			Util.text({
				Text = string.format(
					"%s tier · Battles left today: %d / %d",
					tierDef(s.tier).name,
					tonumber(s.attemptsLeft) or Cfg.AttemptsPerDay,
					Cfg.AttemptsPerDay
				),
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				Size = UDim2.new(0.6, 0, 1, 0),
				Parent = top,
			})
			Button.new({
				Name = "FindOpponents",
				Text = "Find opponents",
				Color = C.Blue,
				TextSize = Theme.TextSize.Small,
				Size = UDim2.fromOffset(190, 46),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Parent = top,
				OnClick = function()
					Util.requestOnce(ctx, "Arena.Refresh")
				end,
			})
			local list = Widgets.List({ Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 1, -58), Padding = 8, Parent = content })
			local candidates = if type(s.candidates) == "table" then s.candidates else {}
			if #candidates == 0 then
				Util.text({
					Text = "Tap Find opponents to meet challengers near your rating.",
					TextColor3 = C.TextMuted,
					Size = UDim2.new(1, 0, 0, 40),
					Parent = list,
				})
			end
			for i, c in candidates do
				local card = New("Frame", {
					Name = "Opponent" .. i,
					BackgroundColor3 = C.PanelDeep,
					Size = UDim2.new(1, -8, 0, 96),
					LayoutOrder = i,
					Parent = list,
				}, { Create.Corner(12) })
				local tier = tierDef(nil)
				for _, t in Cfg.Tiers do
					if (c.rating or 0) >= t.min then
						tier = t
					end
				end
				Util.text({
					Text = string.format("%s%s", c.name or "?", if c.bot then " (bot)" else ""),
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body,
					Position = UDim2.fromOffset(14, 8),
					Size = UDim2.fromOffset(260, 28),
					Parent = card,
				})
				Util.text({
					Text = string.format("%s · %d", tier.name, c.rating or 0),
					TextColor3 = Color3.fromHex(tier.color),
					Position = UDim2.fromOffset(14, 40),
					Size = UDim2.fromOffset(260, 24),
					Parent = card,
				})
				local row = teamRow(c.team, card, 72)
				row.Position = UDim2.fromOffset(290, 12)
				local done = c.done == true
				Button.new({
					Name = "Fight",
					Text = if done then "Fought" else "Fight",
					Color = if done then C.Gray else C.Red,
					Disabled = done or (tonumber(s.attemptsLeft) or 0) <= 0,
					Size = UDim2.fromOffset(140, 56),
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Parent = card,
					OnClick = function()
						if not done then
							fight(i, c)
						end
					end,
				})
			end
		end

		local function drawDefense()
			local ids = if type(prof().defense) == "table" then prof().defense else {}
			local team = {}
			for _, id in ids do
				local ap = Util.appearance(Util.monsters(ctx)[id])
				if ap then
					table.insert(team, ap)
				end
			end
			local card = Util.card({ Title = "Your defense team", Size = UDim2.new(1, 0, 1, 0), Parent = content })
			if #team > 0 then
				local row = teamRow(team, card, 110)
				row.Position = UDim2.fromOffset(20, 50)
			else
				Util.text({
					Text = "No defense team yet. Other players can't challenge you until you set one.",
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					Position = UDim2.fromOffset(20, 50),
					Size = UDim2.new(1, -40, 0, 50),
					Parent = card,
				})
			end
			Util.text({
				Text = string.format(
					"Fair fights: in the arena every monster fights as a Lv %d, %d★ %s of its species, with no traits, mutations or bonuses. Species, element, skill and team order are what count.",
					Cfg.Normal.lv,
					Cfg.Normal.stars,
					Theme.RarityName(Cfg.Normal.rarity)
				),
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromOffset(20, 180),
				Size = UDim2.new(1, -40, 0, 70),
				Parent = card,
			})
			Button.new({
				Name = "SetDefense",
				Text = "Set defense team",
				Color = C.Green,
				Size = UDim2.fromOffset(260, 56),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -12),
				Parent = card,
				OnClick = function()
					pickAdults(string.format("Pick %d Adults to defend", Cfg.TeamSize), function(picked)
						local ok = Util.requestOnce(ctx, "Arena.SetDefense", { ids = picked })
						if ok then
							ctx:Toast("Defense team saved!", "success")
						end
					end)
				end,
			})
		end

		local function drawRewards()
			local p = prof()
			local list = Widgets.List({ Size = UDim2.new(0.62, -6, 1, 0), Padding = 6, Parent = content })
			for i, t in Cfg.Tiers do
				local row = New("Frame", {
					BackgroundColor3 = if p.bestTier == t.id then C.Gold else C.PanelDeep,
					Size = UDim2.new(1, -6, 0, 58),
					LayoutOrder = i,
					Parent = list,
				}, { Create.Corner(10) })
				Util.text({
					Text = string.format("%s  %d+", t.name, t.min),
					Font = Theme.Fonts.Display,
					TextColor3 = Color3.fromHex(t.color),
					Position = UDim2.fromOffset(12, 0),
					Size = UDim2.fromOffset(170, 58),
					Parent = row,
				})
				Util.rewardRow(
					Cfg.WeeklyRewards[t.id] or {},
					row,
					{ Position = UDim2.fromOffset(190, 8), Size = UDim2.new(1, -200, 0, 42), IconSize = 26 }
				)
			end
			local side =
				Util.card({ Title = "This week", Position = UDim2.new(0.62, 6, 0, 0), Size = UDim2.new(0.38, -6, 1, 0), Parent = content })
			local best = if p.bestTier and p.bestTier ~= "" then tierDef(p.bestTier).name else "—"
			local last = if p.lastTier and p.lastTier ~= "" then tierDef(p.lastTier).name else nil
			Util.text({
				Text = string.format("Best tier this week: %s\nWeeks end Saturday 15:00 UTC.", best),
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromOffset(12, 40),
				Size = UDim2.new(1, -24, 0, 70),
				Parent = side,
			})
			local claimable = last ~= nil and p.claimed ~= true
			Button.new({
				Name = "ClaimWeekly",
				Text = if claimable then "Claim " .. (last :: string) .. " reward" elseif last then "Claimed" else "No reward yet",
				Color = if claimable then C.Green else C.Gray,
				Disabled = not claimable,
				TextSize = Theme.TextSize.Small,
				Size = UDim2.new(1, -24, 0, 54),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -12),
				Parent = side,
				OnClick = function()
					local ok = Util.requestOnce(ctx, "Arena.ClaimWeekly")
					if ok then
						ctx:Toast("Arena reward claimed!", "reward")
					end
				end,
			})
		end

		-- Season (3.8) ------------------------------------------------------------------------
		local countdown = nil -- the ends-in label, ticked every second while the tab is open

		local function countdownText(): string
			local now = ctx:Now()
			local season = ArenaLogic.SeasonAt(now)
			if season <= 0 then
				return string.format("Season %d starts in %s", 1, Format.duration(ArenaLogic.SeasonStartsAt(1) - now))
			end
			return string.format("Arena Season %d · ends in %s", season, Format.duration(ArenaLogic.SeasonEndsAt(season) - now))
		end

		local function drawSeason()
			local p = prof()
			local s = sess()
			local season = ArenaLogic.SeasonAt(ctx:Now())
			local rating = tonumber(s.rating) or Cfg.StartRating

			-- Left: the season, its countdown, featured lines and your season best.
			local info = Util.card({ Name = "SeasonInfo", Size = UDim2.new(0.34, -6, 1, 0), Parent = content })
			countdown = Util.text({
				Name = "SeasonCountdown",
				Text = countdownText(),
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				TextWrapped = true,
				Position = UDim2.fromOffset(12, 8),
				Size = UDim2.new(1, -24, 0, 56),
				Parent = info,
			})
			Util.text({
				Text = string.format("Featured lines fight at +%d%%", math.floor(Cfg.Season.FeaturedBoost * 100 + 0.5)),
				TextColor3 = C.TextMuted,
				TextSize = Theme.TextSize.Small,
				Position = UDim2.fromOffset(12, 66),
				Size = UDim2.new(1, -24, 0, 24),
				Parent = info,
			})
			local featured = New("Frame", {
				Name = "Featured",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12, 94),
				Size = UDim2.new(1, -24, 0, 118),
				Parent = info,
			}, { Create.List("x", 8, Enum.HorizontalAlignment.Center) })
			for i, line in ArenaLogic.Featured(math.max(1, season)) do
				local cell = New("Frame", {
					Name = "Featured_" .. line,
					BackgroundColor3 = C.PanelDeep,
					Size = UDim2.fromOffset(92, 118),
					LayoutOrder = i,
					Parent = featured,
				}, { Create.Corner(10) })
				local adults = Config.Species.ById[line].forms[3]
				local ok, look = pcall(Appearance.Preview, line, 3, adults[1].id, Cfg.Normal.rarity)
				if ok then
					local icon = MonsterIcon.new(look, 64)
					icon.AnchorPoint = Vector2.new(0.5, 0)
					icon.Position = UDim2.new(0.5, 0, 0, 4)
					icon.Parent = cell
				end
				Util.text({
					Text = Config.Species.Form(line, 1).name,
					TextSize = Theme.TextSize.Small,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(2, 68),
					Size = UDim2.new(1, -4, 0, 22),
					Parent = cell,
				})
				Util.text({
					Text = string.format("+%d%%", math.floor(Cfg.Season.FeaturedBoost * 100 + 0.5)),
					Font = Theme.Fonts.Display,
					TextColor3 = C.Green,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(2, 90),
					Size = UDim2.new(1, -4, 0, 24),
					Parent = cell,
				})
			end
			local best = if season > 0 and p.seasonOf == season and p.seasonBest and p.seasonBest ~= "" then tierDef(p.seasonBest) else nil
			Util.text({
				Name = "SeasonBest",
				Text = if best then string.format("Season best: %s", best.name) else "Season best: none yet",
				Font = Theme.Fonts.Display,
				TextColor3 = if best then Color3.fromHex(best.color) else C.TextMuted,
				Position = UDim2.fromOffset(12, 220),
				Size = UDim2.new(1, -24, 0, 30),
				Parent = info,
			})
			Util.text({
				Text = string.format(
					"Your best tier this season pays once the season ends. A new season moves every rating halfway back to %s.",
					Format.commas(Cfg.StartRating)
				),
				TextColor3 = C.TextMuted,
				TextSize = Theme.TextSize.Small,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromOffset(12, 254),
				Size = UDim2.new(1, -24, 1, -262),
				Parent = info,
			})

			-- Middle: the reward track by tier.
			local track = Widgets.List({
				Name = "SeasonTrack",
				Position = UDim2.new(0.34, 6, 0, 0),
				Size = UDim2.new(0.36, -12, 1, 0),
				Padding = 6,
				Parent = content,
			})
			for i, t in Cfg.Tiers do
				local reward = Cfg.SeasonRewards[t.id]
				if reward then
					local row = New("Frame", {
						Name = "Track_" .. t.id,
						BackgroundColor3 = if best and best.id == t.id then C.Gold else C.PanelDeep,
						Size = UDim2.new(1, -6, 0, 86),
						LayoutOrder = i,
						Parent = track,
					}, { Create.Corner(10) })
					Util.text({
						Text = t.name,
						Font = Theme.Fonts.Display,
						TextColor3 = Color3.fromHex(t.color),
						Position = UDim2.fromOffset(10, 2),
						Size = UDim2.fromOffset(110, 28),
						Parent = row,
					})
					local title = Config.Mastery.ItemById[reward.titleId]
					local aura = reward.auraId and Config.Mastery.ItemById[reward.auraId]
					Util.text({
						Text = if aura
							then string.format("Title: %s · Aura: %s", title.name, aura.name)
							else string.format("Title: %s", title.name),
						TextSize = Theme.TextSize.Small,
						TextWrapped = true,
						Position = UDim2.fromOffset(120, 2),
						Size = UDim2.new(1, -126, 0, 28),
						Parent = row,
					})
					Util.rewardRow(
						reward.items,
						row,
						{ Position = UDim2.fromOffset(10, 36), Size = UDim2.new(1, -20, 0, 42), IconSize = 24 }
					)
				end
			end

			-- Right: the season board's top 10 and you.
			local side = Util.card({
				Name = "SeasonBoard",
				Title = "Season top 10",
				Position = UDim2.new(0.7, 0, 0, 0),
				Size = UDim2.new(0.3, 0, 1, 0),
				Parent = content,
			})
			local G = ctx.Store:Get("global.Leaderboards")
			local rows = type(G) == "table" and type(G.global) == "table" and G.global.arena or nil
			if type(rows) ~= "table" or #rows == 0 then
				rows = type(G) == "table" and type(G.server) == "table" and G.server.arena or nil
			end
			rows = if season > 0 and type(rows) == "table" then rows else {}
			local list = Widgets.List({ Position = UDim2.fromOffset(8, 40), Size = UDim2.new(1, -16, 1, -96), Padding = 2, Parent = side })
			local me = ctx.Player.UserId
			local myRank = nil
			for rank, r in rows do
				if rank > 10 then
					break
				end
				if r.userId == me then
					myRank = rank
				end
				local label = Util.text({
					Name = "Rank" .. rank,
					Text = string.format("%d. %s · %s", rank, tostring(r.name or "Rancher"), Format.commas(tonumber(r.value) or 0)),
					TextSize = Theme.TextSize.Small,
					TextColor3 = if r.userId == me then C.Gold else C.Text,
					Size = UDim2.new(1, -6, 0, 24),
					LayoutOrder = rank,
					Parent = list,
				})
				label:SetAttribute("Localize", false)
			end
			if #rows == 0 then
				Util.text({
					Text = if season > 0 then "No one is on the season board yet." else "The season board opens with Season 1.",
					TextColor3 = C.TextMuted,
					TextSize = Theme.TextSize.Small,
					TextWrapped = true,
					Size = UDim2.new(1, -6, 0, 48),
					Parent = list,
				})
			end
			Util.text({
				Name = "SeasonYou",
				Text = if myRank
					then string.format("You: #%d · %s", myRank, Format.commas(rating))
					else string.format("Your rating: %s · %s tier", Format.commas(rating), tierDef(s.tier).name),
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Small,
				TextWrapped = true,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 10, 1, -6),
				Size = UDim2.new(1, -20, 0, 48),
				Parent = side,
			})
		end

		local lockOverlay = nil
		local function draw()
			if not isOpen then
				return
			end
			local s = sess()
			local rating = tonumber(s.rating) or Cfg.StartRating
			ratingPill:SetText(Format.commas(rating))
			Util.clear(content)
			countdown = nil
			if tab == "defense" then
				drawDefense()
			elseif tab == "rewards" then
				drawRewards()
			elseif tab == "season" then
				drawSeason()
			else
				drawBattle()
			end
			if lockOverlay then
				lockOverlay:Destroy()
				lockOverlay = nil
			end
			if not Util.unlocked(ctx, Cfg.Unlock) then
				lockOverlay = Util.lockOverlay(panel.Body, Util.unlockText(Cfg.Unlock))
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function(params)
				isOpen = true
				bag.clean()
				-- { tab = "season" } (the Events calendar's Go) opens straight on that tab.
				if
					type(params) == "table"
					and (params.tab == "battle" or params.tab == "defense" or params.tab == "rewards" or params.tab == "season")
				then
					tab = params.tab
					tabs:Select(params.tab)
				end
				for _, path in { "session.Arena", "profile.Arena", "profile.Monsters.list", "profile.Progression.level" } do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				bag.add(ctx.Store:Observe("global.Leaderboards", function()
					if tab == "season" then
						refresh()
					end
				end))
				refresh()
				-- 3.8: the season countdown ticks every second while the Season tab is showing.
				task.spawn(function()
					while isOpen do
						task.wait(1)
						if isOpen and countdown and countdown.Parent then
							countdown.Text = countdownText()
						end
					end
				end)
			end,
			Close = function()
				isOpen = false
				bag.clean()
			end,
		}
	end,
}
