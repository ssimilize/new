--[[
	Arena screen (update 2.1): asynchronous PvP with normalized stats.

	Battle   "Find opponents" (Arena.Refresh) and up to Config.Arena.Candidates opponents,
	         each with rating, tier and team; Fight → pick 3 Adults → Arena.Attack → the
	         battle plays in Parts/BattleReplay, with the rating change on the result card.
	Defense  your defense team (profile.Arena.defense) and "Set defense team" (pick 3 Adults
	         → Arena.SetDefense), with a note on how stats are normalized.
	Rewards  tiers and their weekly rewards, this week's best tier, and "Claim" for the week
	         that just ended (Arena.ClaimWeekly).
	Header: your rating and tier, battles left today. Opened from the Champions Arena.

	Reads: session.Arena, profile.Arena, profile.Monsters.list, profile.Progression.level.
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
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)
local BattleReplay = require(script.Parent.Parts.BattleReplay)

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

		Widgets.Tabs({
			Tabs = { { id = "battle", text = "Battle" }, { id = "defense", text = "Defense" }, { id = "rewards", text = "Rewards" } },
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
				BattleReplay.play(ctx, {
					replay = res.replay,
					win = res.win,
					rewards = res.rewards,
					title = string.format("Arena · vs %s", candidate.name or "?"),
					winText = string.format("Victory! Rating %s%d → %d", sign, res.delta or 0, res.rating or 0),
					loseText = string.format("Defeat. Rating %s%d → %d", sign, res.delta or 0, res.rating or 0),
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

		local lockOverlay = nil
		local function draw()
			if not isOpen then
				return
			end
			local s = sess()
			local rating = tonumber(s.rating) or Cfg.StartRating
			ratingPill:SetText(Format.commas(rating))
			Util.clear(content)
			if tab == "defense" then
				drawDefense()
			elseif tab == "rewards" then
				drawRewards()
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
			Open = function()
				isOpen = true
				bag.clean()
				for _, path in { "session.Arena", "profile.Arena", "profile.Monsters.list", "profile.Progression.level" } do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				refresh()
			end,
			Close = function()
				isOpen = false
				bag.clean()
			end,
		}
	end,
}
