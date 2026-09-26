--[[
	Mastery screen (3.3, the endgame layer; design in Config/Mastery).

	Tabs:
	  mastery   Ranch Mastery level and bar, and every line the player has mastery in, most first
	  ladder    this season's Mythic Ladder: points, tiers and their rewards, this week's points
	  shop      the Star Shard Constellation: trait reroll (Monsters pick mode -> slot -> odds ->
	            Mastery.Reroll), prestige cosmetics and perks (Mastery.Buy / Mastery.Equip)

	Params: { tab? = "mastery" | "ladder" | "shop" }.
	Reads: profile.Mastery, profile.HallOfFame.starShards, profile.Progression.level,
	profile.Monsters.list (all tolerated nil).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local Appearance = require(Shared.Logic.Appearance)
local Logic = require(Shared.Logic.Mastery)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local Util = require(script.Parent.Parts.Util)
local MasteryBadge = require(script.Parent.Parts.MasteryBadge)

local New = Create.New
local C = Theme.Colors
local M = Config.Mastery

return {
	Name = "Mastery",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Mastery",
			Color = C.Purple,
			Size = UDim2.fromOffset(1040, 520),
			OnClose = function()
				ctx.Router:Close("Mastery")
			end,
		})
		local shardPill = Widgets.Pill({ Icon = "stardust", Text = "0", Parent = panel.HeaderRight })

		local isOpen = false
		local bag = Util.bag()
		local selected = "mastery"
		local rerollId: string? = nil
		local rerollSlot = 1
		local refresh

		local tabs = Widgets.Tabs({
			Tabs = {
				{ id = "mastery", text = "Mastery" },
				{ id = "ladder", text = "Ladder" },
				{ id = "shop", text = "Star Shards", width = 150 },
			},
			Parent = panel.Body,
			OnChanged = function(id)
				selected = id
				if refresh then
					refresh()
				end
			end,
		})
		local content = New("Frame", {
			Name = "Content",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 52),
			Size = UDim2.new(1, 0, 1, -52),
			Parent = panel.Body,
		})

		local function section()
			local s = ctx.Store:Get("profile.Mastery")
			return if type(s) == "table" then s else {}
		end
		local function tbl(value)
			return if type(value) == "table" then value else {}
		end
		local function shards(): number
			return tonumber(ctx.Store:Get("profile.HallOfFame.starShards")) or 0
		end

		local function label(props)
			props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
			return Util.text(props)
		end

		-- Mastery tab ---------------------------------------------------------------------------

		local function drawMastery()
			local s = section()
			local level = tonumber(s.level) or 0
			local xp = tonumber(s.xp) or 0
			local cost = Logic.RanchCost(level)
			local cap = Config.Unlocks.MaxLevelAt(ctx:Now())
			local ranchCard = Util.card({ Title = "Ranch Mastery", Size = UDim2.new(0, 380, 1, 0), Parent = content })
			label({
				Text = string.format("Mastery Lv %d", level),
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Header,
				Position = UDim2.fromOffset(14, 44),
				Size = UDim2.new(1, -28, 0, 40),
				Parent = ranchCard,
			})
			Widgets.Bar({
				Color = C.Purple,
				Value = math.clamp(xp / cost, 0, 1),
				Position = UDim2.fromOffset(14, 92),
				Size = UDim2.new(1, -28, 0, 22),
				Parent = ranchCard,
			})
			label({
				Text = string.format("%s / %s XP", Format.commas(math.floor(xp)), Format.commas(cost)),
				Position = UDim2.fromOffset(14, 118),
				Size = UDim2.new(1, -28, 0, 24),
				Parent = ranchCard,
			})
			label({
				Text = if Util.level(ctx) >= cap
					then "Ranch XP earned at the level cap raises your Ranch Mastery. Every level pays Star Shards."
					else string.format("Reach Ranch Level %d to start Ranch Mastery.", cap),
				TextColor3 = C.TextMuted,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromOffset(14, 150),
				Size = UDim2.new(1, -28, 0, 90),
				Parent = ranchCard,
			})

			local linesCard = Util.card({
				Title = "Line Mastery",
				Position = UDim2.fromOffset(392, 0),
				Size = UDim2.new(1, -392, 1, 0),
				Parent = content,
			})
			local list = Widgets.List({
				Position = UDim2.fromOffset(4, 38),
				Size = UDim2.new(1, -8, 1, -42),
				Padding = 6,
				Parent = linesCard,
			})
			local rows = {}
			for lineId, points in tbl(s.lines) do
				if Config.Species.ById[lineId] and (tonumber(points) or 0) > 0 then
					table.insert(rows, { line = lineId, points = tonumber(points) or 0 })
				end
			end
			table.sort(rows, function(a, b)
				if a.points ~= b.points then
					return a.points > b.points
				end
				return a.line < b.line
			end)
			if #rows == 0 then
				label({
					Text = "Hatch, level up, evolve and win fights with a line's monsters to master it.",
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					Size = UDim2.new(1, -8, 0, 60),
					Parent = list,
				})
			end
			for i, row in rows do
				local info = MasteryBadge.of(ctx, row.line)
				local frame = New("Frame", {
					BackgroundColor3 = C.PanelDeep,
					Size = UDim2.new(1, -4, 0, 58),
					LayoutOrder = i,
					Parent = list,
				}, { Create.Corner(10) })
				local ok, ap = pcall(Appearance.Preview, row.line, 3)
				if ok and ap then
					local icon = MonsterIcon.new(ap, 48)
					icon.Position = UDim2.fromOffset(6, 5)
					icon.Parent = frame
				end
				label({
					Text = string.format("%s · Lv %d", Config.Species.ById[row.line].forms[1].name, info.level),
					Font = Theme.Fonts.Display,
					Position = UDim2.fromOffset(62, 4),
					Size = UDim2.new(1, -220, 0, 24),
					Parent = frame,
				})
				Widgets.Bar({
					Color = if info.tier then Color3.fromHex(info.tier.color) else C.Blue,
					Value = math.clamp(info.into / info.need, 0, 1),
					Position = UDim2.fromOffset(62, 34),
					Size = UDim2.new(1, -220, 0, 14),
					Parent = frame,
				})
				local chips = New("Frame", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Size = UDim2.fromOffset(150, 28),
					Parent = frame,
				}, { Create.List("x", 4, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
				MasteryBadge.chip(ctx, row.line, chips)
			end
		end

		-- Ladder tab ----------------------------------------------------------------------------

		local function drawLadder()
			local s = section()
			local season = Logic.SeasonAt(ctx:Now())
			local ladder = tbl(s.ladder)
			local card = Util.card({ Title = "Mythic Ladder", Size = UDim2.fromScale(1, 1), Parent = content })
			if season == 0 then
				label({
					Text = "The Mythic Ladder opens with the next Ranch Pass season.",
					TextColor3 = C.TextMuted,
					Position = UDim2.fromOffset(14, 44),
					Size = UDim2.new(1, -28, 0, 30),
					Parent = card,
				})
				return
			end
			local current = ladder.season == season
			local points = if current then Logic.LadderPoints(ladder.xp, ladder.line) else 0
			local reached = if current then tonumber(ladder.tier) or 0 else 0
			local week = tbl(s.week)
			local weekPoints = if week.id == Config.Leaderboards.Week(ctx:Now()) then Logic.LadderPoints(week.xp, week.line) else 0
			local seasonName = ""
			for _, def in Config.Quests.Seasons do
				if def.season == season then
					seasonName = def.name
				end
			end
			label({
				Text = string.format("%s · %d points", seasonName, points),
				Font = Theme.Fonts.Display,
				Position = UDim2.fromOffset(14, 40),
				Size = UDim2.new(0.6, 0, 0, 28),
				Parent = card,
			})
			label({
				Text = string.format("This week: %d points", weekPoints),
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -14, 0, 40),
				Size = UDim2.new(0.35, 0, 0, 28),
				Parent = card,
			})
			local list = Widgets.List({ Position = UDim2.fromOffset(4, 74), Size = UDim2.new(1, -8, 1, -78), Padding = 6, Parent = card })
			for i, row in M.Ladder do
				local done = i <= reached
				local frame = New("Frame", {
					BackgroundColor3 = if done then C.Green else C.PanelDeep,
					Size = UDim2.new(1, -4, 0, 46),
					LayoutOrder = i,
					Parent = list,
				}, { Create.Corner(10) })
				label({
					Text = string.format("%s · %d points", row.name, row.points),
					Font = Theme.Fonts.Display,
					Position = UDim2.fromOffset(12, 0),
					Size = UDim2.new(0.4, 0, 1, 0),
					Parent = frame,
				})
				local rewards = {}
				if row.shards then
					table.insert(rewards, string.format("+%d Star Shards", row.shards))
				end
				for _, itemId in { row.item, row.item2 } do
					local item = itemId and M.ItemById[itemId]
					if item then
						table.insert(rewards, item.name)
					end
				end
				label({
					Text = table.concat(rewards, " · "),
					TextXAlignment = Enum.TextXAlignment.Right,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -12, 0, 0),
					Size = UDim2.new(0.58, 0, 1, 0),
					Parent = frame,
				})
			end
		end

		-- Shop tab ------------------------------------------------------------------------------

		local function drawReroll(card)
			local m = rerollId and tbl(ctx.Store:Get("profile.Monsters.list"))[rerollId]
			local choose = Button.new({
				Name = "ChooseMonster",
				Text = if m then "Change monster" else "Choose a monster",
				Color = C.Blue,
				TextSize = Theme.TextSize.Small,
				Size = UDim2.fromOffset(180, 44),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 6),
				Parent = card,
			})
			choose:SetOnClick(function()
				Util.pick(ctx, {
					title = "Pick a monster to reroll",
					max = 1,
					filter = function(monster)
						return not monster.busy and type(monster.traits) == "table" and #monster.traits > 0
					end,
					returnTo = "Mastery",
					returnParams = { tab = "shop" },
					onPick = function(ids)
						rerollId = ids[1]
						rerollSlot = 1
					end,
				})
			end)
			if not m then
				label({
					Text = "Reroll one trait of a monster. The new trait comes from the same pool as a hatch, and is never one it already has.",
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					Position = UDim2.fromOffset(14, 58),
					Size = UDim2.new(1, -28, 0, 100),
					Parent = card,
				})
				return
			end
			local traits = tbl(m.traits)
			rerollSlot = math.clamp(rerollSlot, 1, math.max(1, #traits))
			label({
				Text = Formulas.DisplayName(m),
				Font = Theme.Fonts.Display,
				Position = UDim2.fromOffset(14, 52),
				Size = UDim2.new(1, -28, 0, 24),
				Parent = card,
			})
			local slots = New("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(10, 80),
				Size = UDim2.new(1, -20, 0, 46),
			}, { Create.List("x", 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
			for i, traitId in traits do
				local t = Config.Traits.ById[traitId]
				Button.new({
					Name = "Slot" .. i,
					Text = if t then t.name else "?",
					Color = if i == rerollSlot then C.Orange else C.Gray,
					TextSize = Theme.TextSize.Small,
					Size = UDim2.fromOffset(124, 44),
					LayoutOrder = i,
					Parent = slots,
					OnClick = function()
						rerollSlot = i
						refresh()
					end,
				})
			end
			slots.Parent = card
			local odds = Logic.RerollOdds(m, rerollSlot)
			local oddsList = Widgets.List({
				Position = UDim2.fromOffset(10, 132),
				Size = UDim2.new(1, -20, 1, -196),
				Padding = 2,
				Parent = card,
			})
			for i, row in odds do
				local line = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -8, 0, 22),
					LayoutOrder = i,
					Parent = oddsList,
				})
				label({ Text = row.name, TextSize = Theme.TextSize.Small, Size = UDim2.new(0.7, 0, 1, 0), Parent = line })
				label({
					Text = string.format("%d%%", math.floor(row.pct * 100 + 0.5)),
					TextSize = Theme.TextSize.Small,
					TextXAlignment = Enum.TextXAlignment.Right,
					Position = UDim2.fromScale(0.7, 0),
					Size = UDim2.new(0.3, 0, 1, 0),
					Parent = line,
				})
			end
			local done = tonumber(tbl(section().rerolls)[rerollId]) or 0
			local cost = Logic.RerollCost(done)
			local go = Button.new({
				Name = "Reroll",
				Text = string.format("Reroll for %d shards", cost),
				Color = C.Purple,
				Size = UDim2.new(1, -20, 0, 52),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				Disabled = shards() < cost,
				Parent = card,
			})
			go:SetOnClick(function()
				if shards() < cost then
					ctx:Toast("Not enough Star Shards", "error")
					return
				end
				local ok, data = Util.requestOnce(ctx, "Mastery.Reroll", { id = rerollId, slot = rerollSlot })
				if ok and type(data) == "table" then
					local t = Config.Traits.ById[data.trait]
					ctx:Toast(string.format("New trait: %s!", if t then t.name else "?"), "success")
				end
			end)
		end

		local function itemRow(list, item, order: number)
			local s = section()
			local owned = tbl(s.owned)[item.id] == true
			local equipped = tbl(s.equipped)[item.kind] == item.id
			local frame = New("Frame", {
				BackgroundColor3 = C.PanelDeep,
				Size = UDim2.new(1, -4, 0, 62),
				LayoutOrder = order,
				Parent = list,
			}, { Create.Corner(10) })
			local level = tonumber(tbl(s.perks)[item.id]) or 0
			label({
				Text = if item.kind == "perk" then string.format("%s  Lv %d/%d", item.name, level, item.maxLevel) else item.name,
				Font = Theme.Fonts.Display,
				Position = UDim2.fromOffset(10, 4),
				Size = UDim2.new(1, -150, 0, 24),
				Parent = frame,
			})
			label({
				Text = item.desc,
				TextColor3 = C.TextMuted,
				TextSize = Theme.TextSize.Small,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromOffset(10, 30),
				Size = UDim2.new(1, -150, 0, 30),
				Parent = frame,
			})
			local text, color, disabled, action
			if item.kind == "perk" then
				local cost = item.costs[level + 1]
				text = if cost then "✦ " .. tostring(cost) else "MAX"
				color, disabled = C.Purple, cost == nil or shards() < cost
				action = function()
					Util.requestOnce(ctx, "Mastery.Buy", { item = item.id })
				end
			elseif not owned then
				text, color, disabled = "✦ " .. tostring(item.cost or 0), C.Purple, item.cost == nil or shards() < (item.cost or 0)
				action = function()
					local ok = Util.requestOnce(ctx, "Mastery.Buy", { item = item.id })
					if ok then
						ctx:Toast(string.format("%s unlocked!", item.name), "success")
					end
				end
			else
				text, color, disabled = if equipped then "Take off" else "Equip", if equipped then C.Gray else C.Green, false
				action = function()
					Util.requestOnce(ctx, "Mastery.Equip", { kind = item.kind, item = if equipped then "" else item.id })
				end
			end
			Button.new({
				Text = text,
				Color = color,
				TextSize = Theme.TextSize.Body,
				Size = UDim2.fromOffset(128, 46),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Disabled = disabled,
				Parent = frame,
				OnClick = action,
			})
		end

		local function drawShop()
			local rerollCard = Util.card({ Title = "Trait reroll", Size = UDim2.new(0, 420, 1, 0), Parent = content })
			drawReroll(rerollCard)
			local itemsCard = Util.card({
				Title = "Constellation",
				Position = UDim2.fromOffset(432, 0),
				Size = UDim2.new(1, -432, 1, 0),
				Parent = content,
			})
			local list = Widgets.List({
				Position = UDim2.fromOffset(4, 38),
				Size = UDim2.new(1, -8, 1, -42),
				Padding = 6,
				Parent = itemsCard,
			})
			local owned = tbl(section().owned)
			local order = 0
			for _, item in M.Rewards do
				if owned[item.id] then
					order += 1
					itemRow(list, item, order)
				end
			end
			for _, item in M.Shop do
				order += 1
				itemRow(list, item, order)
			end
		end

		local function draw()
			if not isOpen then
				return
			end
			shardPill:SetText(Format.short(shards()))
			Util.clear(content)
			if selected == "ladder" then
				drawLadder()
			elseif selected == "shop" then
				drawShop()
			else
				drawMastery()
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function(params)
				isOpen = true
				bag.clean()
				if type(params) == "table" and type(params.tab) == "string" then
					tabs:Select(params.tab)
				end
				for _, path in
					{
						"profile.Mastery",
						"profile.HallOfFame.starShards",
						"profile.Monsters.list",
						"profile.Progression.level",
					}
				do
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
