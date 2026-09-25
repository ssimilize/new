--[[
	Quests screen (C3). Params: { tab? = "daily" | "achievements" | "pass" }.

	Daily: today's quests with progress bars and Claim (Quests.ClaimDaily { index }).
	Achievements: every achievement with progress and Claim (Quests.ClaimAchievement { id }).
	Ranch Pass: tiers from Config.Quests.PassAt(now) with free and premium tracks, the pass XP bar,
	Claim (Quests.ClaimPass { tier, track }) and a premium lock with "Get Ranch Pass", which
	prompts the `ranchPass` developer product.

	Reads: profile.Quests, profile.Progression.level (tolerated nil).
]]

local MarketplaceService = game:GetService("MarketplaceService")
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
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Q = Config.Quests

local DAILY_BY_ID = {}
for _, def in Q.DailyPool do
	DAILY_BY_ID[def.id] = def
end

local function flagged(map, key: number): boolean
	if type(map) ~= "table" then
		return false
	end
	return map[key] == true or map[tostring(key)] == true
end

return {
	Name = "Quests",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Quests",
			Color = C.Green,
			Size = UDim2.fromOffset(1040, 520),
			OnClose = function()
				ctx.Router:Close("Quests")
			end,
		})

		local tab = "daily"
		local isOpen = false
		local bag = Util.bag()
		local refresh

		local tabs = Widgets.Tabs({
			Tabs = {
				{ id = "daily", text = "Daily", width = 130 },
				{ id = "achievements", text = "Achievements", width = 160 },
				{ id = "pass", text = "Ranch Pass", width = 140 },
			},
			Selected = tab,
			Size = UDim2.fromOffset(446, 44),
			Parent = panel.HeaderRight,
			OnChanged = function(id)
				tab = id
				if refresh then
					refresh()
				end
			end,
		})
		tabs.Root.LayoutOrder = 1

		local content = New("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })

		local function quests()
			return ctx.Store:Get("profile.Quests") or {}
		end

		local function claimToast(res)
			if type(res) == "table" and type(res.rewards) == "table" and #res.rewards > 0 then
				local parts = {}
				for _, item in res.rewards do
					table.insert(parts, Util.rewardText(item))
				end
				ctx:Toast("+ " .. table.concat(parts, ", "), "reward")
			else
				ctx:Toast("Claimed!", "success")
			end
		end

		-- A quest row: text, progress bar, rewards and a claim button.
		local function questRow(parent, order, def, progress: number, claimed: boolean, onClaim)
			local target = def.target or 1
			local done = progress >= target
			local row = New("Frame", {
				BackgroundColor3 = if claimed then C.PanelDeep else C.Card,
				Size = UDim2.new(1, -4, 0, 78),
				LayoutOrder = order,
				Parent = parent,
			}, { Create.Corner(Theme.Radius.Card), Create.Stroke(2.5, if done and not claimed then C.Green else C.Line) })
			Util.text({
				Text = def.text,
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(14, 6),
				Size = UDim2.new(0.5, -14, 0, 26),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Parent = row,
			})
			Widgets.Bar({
				Color = if done then C.Green else C.Blue,
				Value = math.clamp(progress / target, 0, 1),
				Text = string.format("%s / %s", Format.short(math.min(progress, target)), Format.short(target)),
				Position = UDim2.fromOffset(14, 42),
				Size = UDim2.new(0.5, -14, 0, 22),
				Parent = row,
			})
			Util.rewardRow(def.reward or {}, row, {
				Position = UDim2.new(0.5, 14, 0, 0),
				Size = UDim2.new(0.5, -170, 1, 0),
				IconSize = 26,
			})
			if claimed then
				Util.text({
					Text = "Claimed ✓",
					Font = Theme.Fonts.Display,
					TextColor3 = C.Green,
					TextXAlignment = Enum.TextXAlignment.Center,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10, 0.5, 0),
					Size = UDim2.fromOffset(130, 48),
					Parent = row,
				})
			else
				local button = Button.new({
					Text = "Claim",
					Color = C.Green,
					Size = UDim2.fromOffset(130, 50),
					TextSize = Theme.TextSize.Body,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10, 0.5, 0),
					Disabled = not done,
					Parent = row,
				})
				button:SetOnClick(function()
					if not done then
						ctx:Toast(string.format("%s / %s done", Format.short(progress), Format.short(target)), "info")
						return
					end
					onClaim()
				end)
			end
			return row
		end

		local function drawDaily()
			local header = Util.text({
				Text = "",
				TextColor3 = C.TextMuted,
				Size = UDim2.new(1, 0, 0, 26),
				Parent = content,
			})
			local nextDay = (Util.day(ctx) + 1) * 86400
			Widgets.Countdown(header, function()
				return nextDay
			end, function(left)
				return "New daily quests in " .. Format.duration(left)
			end)
			header.Text = "New daily quests in " .. Format.duration(nextDay - ctx:Now())
			local list = Widgets.List({ Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30), Padding = 8, Parent = content })
			local daily = quests().daily
			local entries = if type(daily) == "table" and type(daily.list) == "table" then daily.list else {}
			if #entries == 0 then
				Util.text({
					Text = "Your daily quests appear here each day.",
					TextColor3 = C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, 0, 0, 60),
					Parent = list,
				})
			end
			for i, entry in entries do
				local def = DAILY_BY_ID[entry.id]
				if def then
					questRow(list, i, def, entry.progress or 0, entry.claimed == true, function()
						local ok, res = Util.requestOnce(ctx, "Quests.ClaimDaily", { index = i })
						if ok then
							claimToast(res)
						end
					end)
				end
			end
			if not Util.unlocked(ctx, "dailies") then
				Util.lockOverlay(content, Util.unlockText("dailies"))
			end
		end

		local function drawAchievements()
			local list = Widgets.List({ Size = UDim2.fromScale(1, 1), Padding = 8, Parent = content })
			local state = quests().achievements
			state = if type(state) == "table" then state else {}
			local rows = {}
			for i, def in Q.Achievements do
				local s = state[def.id] or {}
				local progress = s.progress or 0
				local claimed = s.claimed == true
				-- Claimable first, then in progress, then claimed.
				local rank = if claimed then 3 elseif progress >= (def.target or 1) then 1 else 2
				table.insert(rows, { def = def, progress = progress, claimed = claimed, rank = rank, index = i })
			end
			table.sort(rows, function(a, b)
				if a.rank ~= b.rank then
					return a.rank < b.rank
				end
				return a.index < b.index
			end)
			for order, r in rows do
				questRow(list, order, r.def, r.progress, r.claimed, function()
					local ok, res = Util.requestOnce(ctx, "Quests.ClaimAchievement", { id = r.def.id })
					if ok then
						claimToast(res)
					end
				end)
			end
		end

		local function promptPass()
			local product = Config.Monetization.ProductByKey.ranchPass
			if not product or product.productId == 0 then
				ctx:Toast("Coming soon", "info")
				return
			end
			local ok, err = pcall(function()
				MarketplaceService:PromptProductPurchase(ctx.Player, product.productId)
			end)
			if not ok then
				ctx:Toast("Purchase unavailable right now", "error")
				warn("[Quests] PromptProductPurchase failed: " .. tostring(err))
			end
		end

		local function drawPass()
			local Pass = Q.PassAt(ctx:Now())
			local pass = quests().pass
			pass = if type(pass) == "table" then pass else {}
			local sameSeason = pass.season == nil or pass.season == Pass.season
			local xp = if sameSeason then (pass.xp or 0) else 0
			local premium = sameSeason and pass.premium == true
			local claimed = if sameSeason and type(pass.claimed) == "table" then pass.claimed else {}
			local tier = math.floor(xp / Pass.xpPerTier)
			local now = ctx:Now()

			-- Header strip
			local strip = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 66), Parent = content })
			local seasonText
			if now < Pass.startsAt then
				seasonText = string.format("Season %d starts in %s", Pass.season, Format.duration(Pass.startsAt - now))
			elseif now < Pass.endsAt then
				seasonText = string.format("Season %d: %s · ends in %s", Pass.season, Pass.name or "", Format.duration(Pass.endsAt - now))
			else
				seasonText = string.format("Season %d has ended", Pass.season)
			end
			Util.text({
				Text = seasonText,
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body + 2,
				Size = UDim2.new(0.6, 0, 0, 26),
				Parent = strip,
			})
			local maxTier = #Pass.tiers
			local into = xp - tier * Pass.xpPerTier
			Widgets.Bar({
				Color = C.Gold,
				Value = if tier >= maxTier then 1 else into / Pass.xpPerTier,
				Text = if tier >= maxTier
					then string.format("Tier %d · max", maxTier)
					else string.format("Tier %d · %d / %d XP to tier %d", tier, into, Pass.xpPerTier, tier + 1),
				Position = UDim2.fromOffset(0, 34),
				Size = UDim2.new(0.6, 0, 0, 24),
				Parent = strip,
			})
			Util.text({
				Text = string.format("+%d XP per daily · +%d per achievement", Pass.xpPerDaily, Pass.xpPerAchievement),
				TextColor3 = C.TextMuted,
				Position = UDim2.new(0.6, 12, 0, 0),
				Size = UDim2.new(0.4, -250, 1, 0),
				Parent = strip,
			})
			if premium then
				local chip = Widgets.Chip({ Text = "RANCH PASS ✓", Color = C.Gold, Height = 40, Parent = strip })
				chip.AnchorPoint = Vector2.new(1, 0.5)
				chip.Position = UDim2.new(1, 0, 0.5, 0)
			else
				local product = Config.Monetization.ProductByKey.ranchPass
				Button.new({
					Text = if product and product.productId ~= 0
						then string.format("Get Ranch Pass R$%d", product.price)
						else "Ranch Pass: soon",
					Color = C.Orange,
					Size = UDim2.fromOffset(236, 54),
					TextSize = Theme.TextSize.Body,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Parent = strip,
					OnClick = promptPass,
				})
			end

			-- Track labels
			local track = New(
				"Frame",
				{ BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 1, -74), Parent = content }
			)
			for i, name in { "Free", "Premium" } do
				Create.Text({
					Text = name,
					TextSize = Theme.TextSize.Body,
					TextColor3 = if i == 1 then C.Text else C.Orange,
					Stroke = false,
					Rotation = 0,
					Position = UDim2.fromOffset(0, 30 + (i - 1) * 146),
					Size = UDim2.fromOffset(84, 136),
					Parent = track,
				})
			end
			local scroller = New("ScrollingFrame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(88, 0),
				Size = UDim2.new(1, -88, 1, 0),
				ScrollBarThickness = 8,
				ScrollBarImageColor3 = C.TextMuted,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.X,
				ScrollingDirection = Enum.ScrollingDirection.X,
				Parent = track,
			}, { Create.List("x", 10), Create.Padding(0, 10, 10, 0) })

			local function rewardCard(parent, y, t, trackName, rewards)
				local reached = tier >= t
				local isClaimed = flagged(claimed[trackName], t)
				local lockedPremium = trackName == "premium" and not premium
				local card = New("Frame", {
					BackgroundColor3 = if isClaimed
						then C.PanelDeep
						elseif trackName == "premium" then Color3.fromHex("#FFF1CF")
						else C.Card,
					Position = UDim2.fromOffset(0, y),
					Size = UDim2.fromOffset(150, 136),
					Parent = parent,
				}, {
					Create.Corner(Theme.Radius.Card),
					Create.Stroke(2.5, if reached and not isClaimed and not lockedPremium then C.Green else C.Line),
				})
				local first = rewards and rewards[1]
				if first then
					local icon = Util.rewardIcon(first, 44)
					icon.AnchorPoint = Vector2.new(0.5, 0)
					icon.Position = UDim2.new(0.5, 0, 0, 6)
					icon.Parent = card
					Util.text({
						Text = Util.rewardText(first),
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.fromOffset(4, 52),
						Size = UDim2.new(1, -8, 0, 32),
						Parent = card,
					})
				end
				if isClaimed then
					Util.text({
						Text = "✓",
						Font = Theme.Fonts.Display,
						TextSize = Theme.TextSize.Header,
						TextColor3 = C.Green,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.new(0, 0, 1, -44),
						Size = UDim2.new(1, 0, 0, 40),
						Parent = card,
					})
				elseif lockedPremium then
					Util.text({
						Text = "🔒 Pass",
						TextColor3 = C.TextMuted,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.new(0, 0, 1, -44),
						Size = UDim2.new(1, 0, 0, 40),
						Parent = card,
					})
				else
					local button = Button.new({
						Text = "Claim",
						Color = C.Green,
						Size = UDim2.new(1, -16, 0, 44),
						TextSize = Theme.TextSize.Body,
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -6),
						Disabled = not reached,
						Parent = card,
					})
					button:SetOnClick(function()
						if not reached then
							ctx:Toast(string.format("Reach tier %d first", t), "info")
							return
						end
						local ok, res = Util.requestOnce(ctx, "Quests.ClaimPass", { tier = t, track = trackName })
						if ok then
							claimToast(res)
						end
					end)
				end
			end

			for t, def in Pass.tiers do
				local column = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(150, 318),
					LayoutOrder = t,
					Parent = scroller,
				})
				Util.text({
					Text = "Tier " .. t,
					Font = Theme.Fonts.Display,
					TextColor3 = if tier >= t then C.Green else C.Text,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, 0, 0, 26),
					Parent = column,
				})
				rewardCard(column, 30, t, "free", def.free)
				rewardCard(column, 176, t, "premium", def.premium)
			end
		end

		local function draw()
			if not isOpen then
				return
			end
			Util.clear(content)
			if tab == "achievements" then
				drawAchievements()
			elseif tab == "pass" then
				drawPass()
			else
				drawDaily()
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function(params)
				isOpen = true
				bag.clean()
				if type(params) == "table" and (params.tab == "daily" or params.tab == "achievements" or params.tab == "pass") then
					tabs:Select(params.tab)
				end
				for _, path in { "profile.Quests", "profile.Progression.level" } do
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
