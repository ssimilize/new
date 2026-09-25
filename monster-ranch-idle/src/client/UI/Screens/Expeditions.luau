--[[
	Expeditions screen (C3). Params: { region? }.

	Stages tab: region tabs, the stage path (cleared / current / locked / boss), the squad
	panel (Monsters pick mode → Expeditions.SetSquad), squad power vs recommended power, an
	element hint, the duration picker, a loot preview, "Fight stage N" (Expeditions.Fight →
	battle replay viewer) and "Start expedition" (Expeditions.Start), plus the expedition
	slots list (Claim, Claim all, Recall).
	Caravans tab: open / join / leave / launch co-op lobbies from global.Expeditions.caravans.

	Reads: profile.Expeditions, session.Expeditions, global.Expeditions, profile.Monsters.list,
	profile.Progression.level (all tolerated nil).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local Util = require(script.Parent.Parts.Util)
local Dialog = require(script.Parent.Parts.Dialog)
local BattleReplay = require(script.Parent.Parts.BattleReplay)

local New = Create.New
local C = Theme.Colors
local Regions = Config.Regions
local Elements = Config.Elements

local DURATION_TEXT = { [900] = "15m", [3600] = "1h", [14400] = "4h", [28800] = "8h" }

local function durationText(seconds: number): string
	return DURATION_TEXT[seconds] or Format.duration(seconds)
end

local function bonusText(seconds: number): string
	local bonus = Regions.DurationBonus[seconds] or 1
	if bonus <= 1 then
		return ""
	end
	return string.format(" +%d%%", math.floor((bonus - 1) * 100 + 0.5))
end

local function elementName(id: string): string
	local e = Elements.ById[id]
	return if e then e.name else id
end

local function joinNames(list: { string }): string
	if #list <= 1 then
		return list[1] or ""
	end
	return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- Monster power, guarded (a record with an unknown species must not break the screen).
local function powerOf(m): number
	if not m then
		return 0
	end
	local ok, p = pcall(Formulas.MonsterPower, m)
	return if ok and type(p) == "number" then p else 0
end

-- Recommended power: Logic/BattleSim when it exists, else a local estimate from Config.
local function recommendedPower(regionId: string, stage: number): number
	local BattleSim = Util.logic("BattleSim")
	if BattleSim and type(BattleSim.RecommendedPower) == "function" then
		local ok, value = pcall(BattleSim.RecommendedPower, regionId, stage)
		if ok and type(value) == "number" then
			return math.floor(value)
		end
	end
	local r = Regions.ById[regionId]
	if not r then
		return 0
	end
	local band = Regions.Band(regionId, stage)
	local t = (stage - band.first) / math.max(1, band.last - band.first)
	local lv = math.floor(band.levels[1] + (band.levels[2] - band.levels[1]) * t + 0.5)
	local rarity = math.floor(band.rarity[1] + (band.rarity[2] - band.rarity[1]) * t + 0.5)
	local per = powerOf({ line = band.enemyLines[1], stage = 3, rarity = rarity, lv = lv, stars = 1, traits = {}, hidden = 0, muts = {} })
	if per <= 0 then
		per = 100
	end
	local units = Regions.WaveSize
	if r.bosses[stage] then
		units = Regions.WaveSize - 1 + Regions.BossStatMult
	end
	return math.floor(per * units * 0.9)
end

return {
	Name = "Expeditions",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Expeditions",
			Color = C.Blue,
			Size = UDim2.fromOffset(1060, 530),
			OnClose = function()
				ctx.Router:Close("Expeditions")
			end,
		})

		local region = Regions.List[1].id
		local selectedStage: number? = nil
		local duration = Regions.Durations[1]
		local caravanDuration = Regions.Caravan.durations[1]
		local mode = "stages"
		local isOpen = false
		local bag = Util.bag()
		local viewer = nil
		local refresh

		-- State readers -----------------------------------------------------------------

		local function exp()
			return ctx.Store:Get("profile.Expeditions") or {}
		end
		local function sess()
			return ctx.Store:Get("session.Expeditions") or {}
		end
		local function cleared(regionId: string): number
			local c = exp().cleared
			return if type(c) == "table" then (c[regionId] or 0) else 0
		end
		local function squadSize(): number
			return sess().squadSize or Regions.SquadSize.base
		end
		local function slotCount(): number
			return sess().slotCount or 1
		end
		local function squadIds(): { string }
			local s = exp().squad
			return if type(s) == "table" then s else {}
		end
		-- The last stage this player can reach in a region (deeper bands have their own unlock).
		local function maxStage(regionId: string): number
			local r = Regions.ById[regionId]
			local d = r and r.depths
			if d and not Util.unlocked(ctx, d.unlock) then
				return d.from - 1
			end
			return Regions.Stages(regionId)
		end
		local function currentStage(): number
			return math.min(cleared(region) + 1, maxStage(region))
		end
		local function stage(): number
			local s = selectedStage or currentStage()
			return math.clamp(s, 1, math.min(cleared(region) + 1, maxStage(region)))
		end
		local function farmStage(): number
			return math.min(stage(), cleared(region))
		end
		local function regionUnlocked(r): boolean
			return Util.unlocked(ctx, r.unlock)
		end
		local function freeSlot(): number?
			local slots = exp().slots or {}
			for i = 1, math.min(slotCount(), Regions.Slots.max) do
				local s = slots[i]
				if not s or s.state ~= "running" then
					return i
				end
			end
			return nil
		end

		-- Layout --------------------------------------------------------------------------

		local modeTabs = Widgets.Tabs({
			Tabs = { { id = "stages", text = "Stages" }, { id = "caravans", text = "Caravans" } },
			Selected = "stages",
			Size = UDim2.fromOffset(280, 44),
			Parent = panel.HeaderRight,
			OnChanged = function(id)
				mode = id
				if refresh then
					refresh()
				end
			end,
		})
		modeTabs.Root.LayoutOrder = 1

		local regionRow = New("Frame", {
			Name = "Regions",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 44),
			Parent = panel.Body,
		}, { Create.List("x", 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })

		local stagesView = New("Frame", {
			Name = "Stages",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 54),
			Size = UDim2.new(1, 0, 1, -54),
			Parent = panel.Body,
		})
		local caravanView = New("Frame", {
			Name = "Caravans",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 54),
			Size = UDim2.new(1, 0, 1, -54),
			Visible = false,
			Parent = panel.Body,
		})

		local mapCard, mapTitle = Util.card({ Title = "", Size = UDim2.fromOffset(560, 196), Parent = stagesView })
		mapCard.ClipsDescendants = true
		local mapGrad = Instance.new("UIGradient")
		mapGrad.Rotation = 90
		mapGrad.Parent = mapCard
		mapTitle.TextColor3 = C.White
		Create.TextStroke().Parent = mapTitle
		local mapInfo = Create.Text({
			Text = "",
			Font = Theme.Fonts.Body,
			TextSize = Theme.TextSize.Small,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(14, 34),
			Size = UDim2.new(1, -28, 0, 20),
			Parent = mapCard,
		})
		local nodes = New("Frame", {
			Name = "Nodes",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 60),
			Size = UDim2.new(1, -28, 0, 130),
			Parent = mapCard,
		})
		-- Page switch for regions with a deeper band (Coral Coast → Coral Depths).
		local pageRow = New("Frame", {
			Name = "Pages",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 6),
			Size = UDim2.fromOffset(212, 40),
			Visible = false,
			ZIndex = 4,
			Parent = mapCard,
		}, { Create.List("x", 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
		local coastButton = Button.new({
			Name = "Coast",
			Text = "Coast",
			Color = C.Orange,
			TextSize = Theme.TextSize.Small + 1,
			Size = UDim2.fromOffset(96, 36),
			LayoutOrder = 1,
			Parent = pageRow,
		})
		local depthsButton = Button.new({
			Name = "Depths",
			Text = "Depths",
			Color = C.Gray,
			TextSize = Theme.TextSize.Small + 1,
			Size = UDim2.fromOffset(110, 36),
			LayoutOrder = 2,
			Parent = pageRow,
		})

		local slotsCard = Util.card({
			Title = "Expeditions",
			Position = UDim2.fromOffset(0, 206),
			Size = UDim2.new(0, 560, 1, -206),
			Parent = stagesView,
		})
		local claimAll = Button.new({
			Text = "Claim all",
			Color = C.Green,
			Size = UDim2.fromOffset(140, 44),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 4),
			TextSize = Theme.TextSize.Body,
			Parent = slotsCard,
		})
		local slotList =
			Widgets.List({ Position = UDim2.fromOffset(4, 50), Size = UDim2.new(1, -8, 1, -54), Padding = 6, Parent = slotsCard })

		local squadCard, squadTitle =
			Util.card({ Title = "Squad", Position = UDim2.fromOffset(572, 0), Size = UDim2.new(1, -572, 1, 0), Parent = stagesView })
		squadTitle.Size = UDim2.new(0, 220, 0, 26)
		local bestButton = Button.new({
			Text = "Best squad",
			Color = C.Purple,
			Size = UDim2.fromOffset(150, 44),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 4),
			TextSize = Theme.TextSize.Body,
			Parent = squadCard,
		})
		local squadRow = New("Frame", {
			Name = "SquadRow",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 52),
			Size = UDim2.new(1, -20, 0, 118),
			Parent = squadCard,
		}, { Create.List("x", 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
		local powerLabel = Util.text({
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = Theme.TextSize.Body,
			Position = UDim2.fromOffset(14, 174),
			Size = UDim2.new(0.5, -14, 0, 24),
			Parent = squadCard,
		})
		local recLabel = Util.text({
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(0.5, 0, 0, 174),
			Size = UDim2.new(0.5, -14, 0, 24),
			Parent = squadCard,
		})
		local hintLabel = Util.text({
			Text = "",
			TextColor3 = C.TextMuted,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(14, 200),
			Size = UDim2.new(1, -28, 0, 40),
			Parent = squadCard,
		})
		local durationRow = New("Frame", {
			Name = "Durations",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 242),
			Size = UDim2.new(1, -20, 0, 44),
			Parent = squadCard,
		}, { Create.List("x", 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
		local lootHolder = New("Frame", {
			Name = "Loot",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 290),
			Size = UDim2.new(1, -28, 0, 30),
			Parent = squadCard,
		})
		local actions = New("Frame", {
			Name = "Actions",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -20, 0, 54),
			Parent = squadCard,
		}, { Create.List("x", 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
		local fightButton =
			Button.new({ Text = "Fight", Color = C.Orange, Size = UDim2.fromOffset(196, 54), LayoutOrder = 1, Parent = actions })
		local startButton =
			Button.new({ Text = "Start", Color = C.Green, Size = UDim2.fromOffset(212, 54), LayoutOrder = 2, Parent = actions })

		local durationButtons = {}
		for i, seconds in Regions.Durations do
			durationButtons[seconds] = Button.new({
				Text = durationText(seconds) .. bonusText(seconds),
				Color = C.Gray,
				Size = UDim2.fromOffset(98, 44),
				TextSize = Theme.TextSize.Small + 1,
				LayoutOrder = i,
				Parent = durationRow,
				OnClick = function()
					duration = seconds
					refresh()
				end,
			})
		end

		-- Actions ------------------------------------------------------------------------

		local function setSquad(ids: { string })
			if #ids == 0 then
				ctx:Toast("Your squad needs at least one monster", "error")
				return
			end
			Util.request(ctx, "Expeditions.SetSquad", { ids = ids })
		end

		local function editSlot(index: number)
			local current = squadIds()
			Util.pick(ctx, {
				title = "Choose a squad member",
				max = 1,
				filter = function(m)
					return not m.busy
				end,
				returnTo = "Expeditions",
				returnParams = { region = region },
				onPick = function(ids)
					local picked = ids[1]
					local slots = {}
					for i = 1, squadSize() do
						slots[i] = current[i] or false
					end
					local existing = table.find(slots, picked)
					if existing then
						slots[existing] = slots[index]
					end
					slots[index] = picked
					local new = {}
					for i = 1, squadSize() do
						if slots[i] then
							table.insert(new, slots[i])
						end
					end
					setSquad(new)
				end,
			})
		end

		local function removeFromSquad(id: string)
			local new = {}
			for _, other in squadIds() do
				if other ~= id then
					table.insert(new, other)
				end
			end
			setSquad(new)
		end

		bestButton:SetOnClick(function()
			local list = {}
			for id, m in Util.monsters(ctx) do
				if not m.busy then
					table.insert(list, { id = m.id or id, power = powerOf(m) })
				end
			end
			table.sort(list, function(a, b)
				return a.power > b.power
			end)
			local ids = {}
			for i = 1, math.min(#list, squadSize()) do
				table.insert(ids, list[i].id)
			end
			setSquad(ids)
		end)

		local fight
		fight = function(stageNumber: number, retry: boolean?)
			local ok, res = Util.requestOnce(ctx, "Expeditions.Fight", { region = region, stage = stageNumber, retry = retry or nil })
			if not ok or type(res) ~= "table" then
				return
			end
			if viewer then
				viewer.Destroy()
			end
			local r = Regions.ById[region]
			local nextStage = stageNumber + 1
			local win = res.win == true
			if win then
				selectedStage = math.min(nextStage, maxStage(region))
			end
			local adsLeft = nil
			local adCap = Config.Monetization.Ads.stageRetry and Config.Monetization.Ads.stageRetry.cap
			local ads = ctx.Store:Get("profile.Monetization.ads")
			if adCap then
				local used = 0
				if type(ads) == "table" and ads.day == Util.day(ctx) and type(ads.counts) == "table" then
					used = ads.counts.stageRetry or 0
				end
				adsLeft = math.max(0, adCap - used)
			end
			viewer = BattleReplay.play(ctx, {
				replay = res.replay,
				win = win,
				rewards = res.rewards,
				title = string.format("%s · Stage %d", if r then r.name else region, stageNumber),
				winText = string.format("Stage %d cleared!", stageNumber),
				retryText = if adsLeft then string.format("Retry +20%% (ad, %d left)", adsLeft) else "Retry with +20% (ad)",
				onRetry = if adsLeft == nil or adsLeft > 0
					then function()
						fight(stageNumber, true)
					end
					else nil,
				nextText = string.format("Fight stage %d", nextStage),
				onNext = if nextStage <= maxStage(region)
					then function()
						fight(nextStage)
					end
					else nil,
				onClose = function()
					viewer = nil
				end,
			})
		end

		coastButton:SetOnClick(function()
			local d = Regions.ById[region] and Regions.ById[region].depths
			if d then
				selectedStage = math.min(cleared(region) + 1, d.from - 1)
				refresh()
			end
		end)
		depthsButton:SetOnClick(function()
			local d = Regions.ById[region] and Regions.ById[region].depths
			if not d then
				return
			end
			if not Util.unlocked(ctx, d.unlock) then
				ctx:Toast(Util.unlockText(d.unlock), "info")
			elseif cleared(region) < d.from - 1 then
				ctx:Toast(string.format("Clear stage %d to dive into the %s", d.from - 1, d.name), "info")
			else
				selectedStage = math.max(d.from, currentStage())
				refresh()
			end
		end)

		fightButton:SetOnClick(function()
			local r = Regions.ById[region]
			if not r or not regionUnlocked(r) then
				ctx:Toast(Util.unlockText(r and r.unlock or ""), "error")
				return
			end
			if #squadIds() == 0 then
				ctx:Toast("Add monsters to your squad first", "error")
				return
			end
			fight(stage())
		end)

		startButton:SetOnClick(function()
			local fs = farmStage()
			if fs < 1 then
				ctx:Toast("Clear stage 1 first", "error")
				return
			end
			if #squadIds() == 0 then
				ctx:Toast("Add monsters to your squad first", "error")
				return
			end
			local slot = freeSlot()
			if not slot then
				ctx:Toast("All expedition slots are busy", "error")
				return
			end
			local ok = Util.requestOnce(ctx, "Expeditions.Start", {
				slot = slot,
				region = region,
				stage = fs,
				duration = tostring(duration),
				squad = table.clone(squadIds()),
			})
			if ok then
				ctx:Toast(string.format("Expedition started: %s", durationText(duration)), "success")
			end
		end)

		local function grantToast(res)
			if type(res) == "table" and type(res.rewards) == "table" and #res.rewards > 0 then
				local parts = {}
				for i, item in res.rewards do
					if i > 4 then
						break
					end
					table.insert(parts, Util.rewardText(item))
				end
				ctx:Toast("+ " .. table.concat(parts, ", "), "reward")
			end
		end

		claimAll:SetOnClick(function()
			local ok, res = Util.requestOnce(ctx, "Expeditions.ClaimAll")
			if ok then
				grantToast(res)
			end
		end)

		-- Stage map ------------------------------------------------------------------------

		-- Up to 20 stages per map page, in two rows that snake back (1–10 → 11–20).
		local NODE = 44
		local function nodeCentre(s: number, first: number): Vector2
			local i = s - first + 1
			local spacing = (532 - NODE) / 9
			local row = if i <= 10 then 1 else 2
			local col = if row == 1 then i - 1 else 20 - i
			return Vector2.new(NODE / 2 + col * spacing, if row == 1 then 26 else 96)
		end

		local function drawMap(r)
			Util.clear(nodes)
			local c = cleared(region)
			local cur = currentStage()
			local sel = stage()
			local unlocked = regionUnlocked(r)
			local band = Regions.Band(r.id, sel)
			local first, last = band.first, band.last
			for s = first, last - 1 do
				local a, b = nodeCentre(s, first), nodeCentre(s + 1, first)
				local done = s < c + 1 and s + 1 <= c + 1
				New("Frame", {
					BackgroundColor3 = C.White,
					BackgroundTransparency = if done then 0.1 else 0.55,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2),
					Size = UDim2.fromOffset(math.max(6, math.abs(b.X - a.X)), math.max(6, math.abs(b.Y - a.Y))),
					Parent = nodes,
				})
			end
			for s = first, last do
				local centre = nodeCentre(s, first)
				local isBoss = r.bosses[s] ~= nil
				local color, textColor = C.Gray, C.White
				if s <= c then
					color = C.Green
				elseif s == cur then
					color = if isBoss then C.Red else C.Orange
				elseif isBoss then
					color = Color3.fromHex("#9E4B4E")
				end
				local node = New("TextButton", {
					Name = "Stage" .. s,
					Text = if isBoss then "BOSS" else tostring(s),
					Font = Theme.Fonts.Display,
					TextSize = if isBoss then Theme.TextSize.Small else Theme.TextSize.Body,
					TextColor3 = textColor,
					AutoButtonColor = false,
					BackgroundColor3 = color,
					BackgroundTransparency = if s > cur then 0.25 else 0,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(centre.X, centre.Y),
					Size = UDim2.fromOffset(if isBoss then 58 else NODE, NODE),
					ZIndex = 3,
					Parent = nodes,
				}, {
					Create.Round(),
					Create.Stroke(if s == sel then 4 else 2.5, if s == sel then C.Gold else C.Ink),
				})
				node.Activated:Connect(function()
					if not unlocked then
						return
					end
					if s > cur then
						ctx:Toast(string.format("Clear stage %d first", cur), "error")
						return
					end
					selectedStage = s
					refresh()
				end)
				if s == cur and unlocked then
					Anim.pulse(node, 0.18)
				end
			end
		end

		-- Squad panel ------------------------------------------------------------------------

		local function drawSquad()
			Util.clear(squadRow)
			local list = Util.monsters(ctx)
			local ids = squadIds()
			local size = squadSize()
			squadTitle.Text = string.format("Squad  %d / %d", #ids, size)
			local width = math.min(100, math.floor(430 / size) - 10)
			for i = 1, size do
				local id = ids[i]
				local m = id and list[id]
				local slot = New("TextButton", {
					Name = "Slot" .. i,
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = C.PanelDeep,
					Size = UDim2.fromOffset(width, 118),
					LayoutOrder = i,
					Parent = squadRow,
				}, { Create.Corner(Theme.Radius.Card), Create.Stroke(2.5, if m then Theme.Rarity(m.rarity or 1) else C.Line) })
				slot.Activated:Connect(function()
					editSlot(i)
				end)
				local ap = m and Util.appearance(m)
				if ap then
					local icon = MonsterIcon.new(ap, 66)
					icon.AnchorPoint = Vector2.new(0.5, 0)
					icon.Position = UDim2.new(0.5, 0, 0, 4)
					icon.Parent = slot
					Util.text({
						Text = Formulas.DisplayName(m),
						TextSize = Theme.TextSize.Small,
						TextXAlignment = Enum.TextXAlignment.Center,
						TextTruncate = Enum.TextTruncate.AtEnd,
						TextWrapped = false,
						Position = UDim2.fromOffset(2, 72),
						Size = UDim2.new(1, -4, 0, 20),
						Parent = slot,
					})
					Util.text({
						Text = string.format("Lv %d · %s", m.lv or 1, Format.short(powerOf(m))),
						TextSize = Theme.TextSize.Tiny + 1,
						TextColor3 = C.TextMuted,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.fromOffset(2, 92),
						Size = UDim2.new(1, -4, 0, 18),
						Parent = slot,
					})
					local chip = Widgets.ElementChip(ap.elements[1] or "sprout", slot)
					chip.Position = UDim2.fromOffset(4, 4)
					if m.busy then
						local away = Widgets.Chip({ Text = "AWAY", Color = C.Red, Parent = slot })
						away.Position = UDim2.fromOffset(4, 48)
					end
					local remove = Button.new({
						Text = "✕",
						Color = C.Red,
						Size = UDim2.fromOffset(44, 44),
						TextSize = 18,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(1, -8, 0, 8),
						ZIndex = 3,
						Parent = slot,
					})
					remove:SetOnClick(function()
						removeFromSquad(id)
					end)
				else
					Create.Text({
						Text = "+",
						TextSize = 44,
						TextColor3 = C.TextMuted,
						Stroke = false,
						Position = UDim2.fromOffset(0, 18),
						Size = UDim2.new(1, 0, 0, 50),
						Parent = slot,
					})
					Util.text({
						Text = "Add",
						TextXAlignment = Enum.TextXAlignment.Center,
						TextColor3 = C.TextMuted,
						Position = UDim2.fromOffset(0, 76),
						Size = UDim2.new(1, 0, 0, 20),
						Parent = slot,
					})
				end
			end
		end

		local function elementHint(r, ids)
			local list = Util.monsters(ctx)
			local mine = {}
			for _, id in ids do
				local m = list[id]
				local def = m and Config.Species.ById[m.line]
				if def then
					for _, e in def.elements do
						if not table.find(mine, e) then
							table.insert(mine, e)
						end
					end
				end
			end
			local sentences = {}
			for _, enemy in r.elements do
				local strong = {}
				for _, e in mine do
					if Elements.Multiplier(e, enemy) > 1 then
						table.insert(strong, elementName(e))
					end
				end
				if #strong > 0 then
					table.insert(
						sentences,
						string.format("%s deal ×%s to %s enemies.", joinNames(strong), tostring(Elements.Advantage), elementName(enemy))
					)
				end
			end
			for _, e in mine do
				local threats = {}
				for _, enemy in r.elements do
					if Elements.Multiplier(enemy, e) > 1 then
						table.insert(threats, elementName(enemy))
					end
				end
				if #threats > 0 then
					table.insert(
						sentences,
						string.format("%s takes ×%s from %s.", elementName(e), tostring(Elements.Advantage), joinNames(threats))
					)
				end
			end
			if #sentences == 0 then
				local counters = {}
				for _, enemy in r.elements do
					for _, e in Elements.List do
						if e.beats == enemy and not table.find(counters, e.name) then
							table.insert(counters, e.name)
						end
					end
				end
				local enemies = {}
				for _, enemy in r.elements do
					table.insert(enemies, elementName(enemy))
				end
				return string.format(
					"Enemies here are %s. %s monsters deal ×%s damage to them.",
					joinNames(enemies),
					joinNames(counters),
					tostring(Elements.Advantage)
				)
			end
			return table.concat(sentences, " ")
		end

		local function drawLoot(r)
			Util.clear(lootHolder)
			local fs = farmStage()
			if fs < 1 then
				Util.text({
					Text = "Clear stage 1 to send expeditions here.",
					TextColor3 = C.TextMuted,
					Size = UDim2.fromScale(1, 1),
					Parent = lootHolder,
				})
				return
			end
			local g = Regions.GlobalIndex(region, fs)
			local per = Regions.LootPerMinute(g)
			local minutes = duration / 60
			local bonus = Regions.DurationBonus[duration] or 1
			local items = {
				{ kind = "coins", amount = math.floor(per.coins * minutes * bonus) },
				{
					kind = "food",
					id = r.food,
					amount = math.floor(per.food * minutes * bonus),
					label = Format.short(math.floor(per.food * minutes * bonus)),
				},
				{ kind = "treats", amount = math.floor(per.treats * minutes * bonus) },
			}
			for _, egg in r.eggs or {} do
				if fs >= (egg.fromStage or 1) then
					local expected = egg.perMinute * minutes * bonus
					local def = Config.Eggs.ById[egg.egg]
					local name = if def then string.gsub(def.name, " Egg$", "") else egg.egg
					local label
					if expected >= 1 then
						label = string.format("%s ×%s", name, Format.short(math.floor(expected * 10) / 10))
					else
						local chance = 1 - (1 - math.min(1, egg.perMinute * bonus)) ^ minutes
						label = string.format("%s %s", name, Format.percent(chance))
					end
					table.insert(items, { kind = "egg", id = egg.egg, amount = 1, label = label })
				end
			end
			Util.text({
				Text = string.format("Stage %d:", fs),
				TextColor3 = C.TextMuted,
				Size = UDim2.new(0, 70, 1, 0),
				TextWrapped = false,
				Parent = lootHolder,
			})
			Util.rewardRow(items, lootHolder, {
				IconSize = 22,
				TextSize = Theme.TextSize.Small,
				Position = UDim2.fromOffset(72, 0),
				Size = UDim2.new(1, -72, 1, 0),
			})
		end

		-- Expedition slots ---------------------------------------------------------------------

		local function drawSlots()
			Util.clear(slotList)
			local slots = exp().slots or {}
			local count = slotCount()
			local now = ctx:Now()
			local anyDone = false
			for i = 1, Regions.Slots.max do
				local s = slots[i]
				local rowFrame = New("Frame", {
					Name = "Slot" .. i,
					BackgroundColor3 = C.PanelDeep,
					Size = UDim2.new(1, -4, 0, 52),
					LayoutOrder = i,
					Parent = slotList,
				}, { Create.Corner(10) })
				local title = Util.text({
					Text = "",
					Position = UDim2.fromOffset(12, 0),
					Size = UDim2.new(0.56, -12, 1, 0),
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextWrapped = false,
					Parent = rowFrame,
				})
				if i > count then
					local unlockKey = Regions.Slots.unlocks[i]
					title.Text = string.format("Slot %d · %s", i, if unlockKey then Util.unlockText(unlockKey) else "Explorer pass")
					title.TextColor3 = C.TextMuted
				elseif not s or s.state ~= "running" then
					title.Text = string.format("Slot %d · Free", i)
					title.TextColor3 = C.TextMuted
				else
					local r = s.region and Regions.ById[s.region]
					local name = if r then r.name else "Expedition"
					if s.caravan then
						name = "Caravan · " .. name
					end
					title.Text = string.format("%s %d · %s", name, s.stage or 1, durationText(s.duration or 0))
					local timer = Util.text({
						Text = "",
						Font = Theme.Fonts.Display,
						TextSize = Theme.TextSize.Body,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.new(0.56, 0, 0, 0),
						Size = UDim2.new(0.2, 0, 1, 0),
						Parent = rowFrame,
					})
					local done = (s.endsAt or 0) <= now
					local button = Button.new({
						Text = if done then "Claim" else "Recall",
						Color = if done then C.Green else C.Red,
						Size = UDim2.fromOffset(112, 44),
						TextSize = Theme.TextSize.Body,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -6, 0.5, 0),
						Parent = rowFrame,
					})
					if done then
						anyDone = true
						timer.Text = "Done!"
						timer.TextColor3 = C.Green
						button:SetOnClick(function()
							local ok, res = Util.requestOnce(ctx, "Expeditions.Claim", { slot = i })
							if ok then
								grantToast(res)
							end
						end)
					else
						timer.Text = Format.clock((s.endsAt or 0) - now)
						Widgets.Countdown(
							timer,
							function()
								return s.endsAt
							end,
							Format.clock,
							function()
								if isOpen then
									refresh()
								end
							end
						)
						button:SetOnClick(function()
							Dialog.confirm(ctx.UI.Top, {
								Title = "Recall expedition?",
								Text = "Your squad comes home now with partial loot and no duration bonus.",
								ConfirmText = "Recall",
								ConfirmColor = C.Red,
								OnConfirm = function()
									local ok, res = Util.requestOnce(ctx, "Expeditions.Recall", { slot = i })
									if ok then
										grantToast(res)
									end
								end,
							})
						end)
					end
				end
			end
			claimAll:SetDisabled(not anyDone)
		end

		-- Caravans -------------------------------------------------------------------------------

		local myId = ctx.Player.UserId

		local function myLobby()
			local lobby = sess().caravan
			local caravans = ctx.Store:Get("global.Expeditions.caravans") or {}
			if type(lobby) == "string" then
				return caravans[lobby]
			elseif type(lobby) == "table" then
				if lobby.id and caravans[lobby.id] then
					return caravans[lobby.id]
				end
				return lobby
			end
			for _, c in caravans do
				for _, member in c.members or {} do
					if member.userId == myId then
						return c
					end
				end
				if c.host == myId then
					return c
				end
			end
			return nil
		end

		local function isMember(lobby): boolean
			for _, member in lobby.members or {} do
				if member.userId == myId then
					return true
				end
			end
			return false
		end

		local function joinCaravan(lobby)
			if #squadIds() == 0 then
				ctx:Toast("Add monsters to your squad first", "error")
				return
			end
			local slot = freeSlot()
			if not slot then
				ctx:Toast("All expedition slots are busy", "error")
				return
			end
			local ok =
				Util.requestOnce(ctx, "Expeditions.JoinCaravan", { caravan = lobby.id, slot = slot, squad = table.clone(squadIds()) })
			if ok then
				ctx:Toast("Joined the caravan", "success")
			end
		end

		local caravanList, caravanRight
		do
			local left = Util.card({ Title = "Open caravans", Size = UDim2.new(0, 600, 1, 0), Parent = caravanView })
			caravanList = Widgets.List({ Position = UDim2.fromOffset(4, 40), Size = UDim2.new(1, -8, 1, -44), Padding = 8, Parent = left })
			caravanRight = Util.card({ Position = UDim2.fromOffset(612, 0), Size = UDim2.new(1, -612, 1, 0), Parent = caravanView })
		end

		local function drawCaravans()
			Util.clear(caravanList)
			Util.clear(caravanRight)
			local caravans = ctx.Store:Get("global.Expeditions.caravans") or {}
			local mine = myLobby()
			local sorted = {}
			for key, c in caravans do
				if type(c) == "table" then
					c = table.clone(c)
					c.id = c.id or key
					table.insert(sorted, c)
				end
			end
			table.sort(sorted, function(a, b)
				return (a.expiresAt or 0) < (b.expiresAt or 0)
			end)
			if #sorted == 0 then
				Util.text({
					Text = "No caravans on this server right now. Open one and invite friends!",
					TextColor3 = C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, 0, 0, 60),
					Parent = caravanList,
				})
			end
			for i, c in sorted do
				local r = Regions.ById[c.region]
				local rowFrame = New("Frame", {
					BackgroundColor3 = if mine and mine.id == c.id then Color3.fromHex("#FFF0C2") else C.PanelDeep,
					Size = UDim2.new(1, -4, 0, 66),
					LayoutOrder = i,
					Parent = caravanList,
				}, { Create.Corner(10) })
				Util.text({
					Text = string.format("%s's caravan", c.hostName or "Someone"),
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body,
					Position = UDim2.fromOffset(12, 6),
					Size = UDim2.new(1, -150, 0, 24),
					Parent = rowFrame,
				})
				local info = Util.text({
					Text = "",
					TextColor3 = C.TextMuted,
					Position = UDim2.fromOffset(12, 34),
					Size = UDim2.new(1, -150, 0, 22),
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextWrapped = false,
					Parent = rowFrame,
				})
				local base = string.format(
					"%s %d · %s · %d/%d",
					if r then r.name else "?",
					c.stage or 1,
					durationText(c.duration or 0),
					#(c.members or {}),
					Regions.Caravan.maxPlayers
				)
				info.Text = base
				Widgets.Countdown(info, function()
					return c.expiresAt
				end, function(left)
					return base .. " · closes in " .. Format.clock(left)
				end)
				local member = isMember(c)
				local full = #(c.members or {}) >= Regions.Caravan.maxPlayers
				local button = Button.new({
					Text = if member then "Joined" elseif full then "Full" else "Join",
					Color = if member then C.Gray else C.Green,
					Size = UDim2.fromOffset(120, 48),
					TextSize = Theme.TextSize.Body,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Disabled = member or full or mine ~= nil,
					Parent = rowFrame,
				})
				button:SetOnClick(function()
					joinCaravan(c)
				end)
			end

			-- Right side: my lobby or the "open a caravan" form.
			local content = New("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(14, 10),
				Size = UDim2.new(1, -28, 1, -20),
				Parent = caravanRight,
			}, { Create.List("y", 8) })
			local function line(text, order, props)
				local p = {
					Text = text,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(1, 0, 0, 20),
					LayoutOrder = order,
					Parent = content,
				}
				for k, v in props or {} do
					p[k] = v
				end
				return Util.text(p)
			end
			if mine then
				local r = Regions.ById[mine.region]
				line("Your caravan", 1, { Font = Theme.Fonts.Display, TextSize = Theme.TextSize.Body + 2 })
				line(
					string.format("%s stage %d · %s", if r then r.name else "?", mine.stage or 1, durationText(mine.duration or 0)),
					2,
					{ TextColor3 = C.TextMuted }
				)
				for j, member in mine.members or {} do
					line(
						string.format(
							"%s%s%s",
							member.name or "?",
							if member.userId == mine.host then " (host)" else "",
							if member.power then " · power " .. Format.short(member.power) else ""
						),
						10 + j
					)
				end
				local expiry = line("", 20, { TextColor3 = C.TextMuted })
				Widgets.Countdown(expiry, function()
					return mine.expiresAt
				end, function(left)
					return "Lobby closes in " .. Format.clock(left)
				end)
				local buttons = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 56),
					LayoutOrder = 30,
					Parent = content,
				}, { Create.List("x", 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
				if not isMember(mine) then
					Button.new({
						Text = "Join",
						Color = C.Green,
						Size = UDim2.fromOffset(120, 50),
						LayoutOrder = 1,
						Parent = buttons,
						OnClick = function()
							joinCaravan(mine)
						end,
					})
				end
				if mine.host == myId then
					local enough = #(mine.members or {}) >= Regions.Caravan.minPlayers
					Button.new({
						Text = "Launch",
						Color = C.Green,
						Size = UDim2.fromOffset(140, 50),
						LayoutOrder = 2,
						Disabled = not enough,
						Parent = buttons,
						OnClick = function()
							if not enough then
								ctx:Toast(string.format("Needs %d players", Regions.Caravan.minPlayers), "error")
								return
							end
							local ok = Util.requestOnce(ctx, "Expeditions.LaunchCaravan", { caravan = mine.id })
							if ok then
								ctx:Toast("Caravan launched!", "success")
							end
						end,
					})
				end
				Button.new({
					Text = "Leave",
					Color = C.Red,
					Size = UDim2.fromOffset(120, 50),
					LayoutOrder = 3,
					Parent = buttons,
					OnClick = function()
						Util.requestOnce(ctx, "Expeditions.LeaveCaravan", { caravan = mine.id })
					end,
				})
			else
				local r = Regions.ById[region]
				local fs = farmStage()
				line("Open a caravan", 1, { Font = Theme.Fonts.Display, TextSize = Theme.TextSize.Body + 2 })
				line(
					string.format(
						"Team up with %d–%d players on this server for +%d%% loot and a shared chest.",
						Regions.Caravan.minPlayers,
						Regions.Caravan.maxPlayers,
						math.floor(Regions.Caravan.lootBonus * 100 + 0.5)
					),
					2,
					{ TextColor3 = C.TextMuted }
				)
				Util.rewardRow(Regions.Caravan.chest, content, { LayoutOrder = 3 })
				line(
					if fs >= 1
						then string.format("%s · stage %d", if r then r.name else region, fs)
						else "Clear stage 1 of this region first.",
					4,
					{ Font = Theme.Fonts.Display, TextSize = Theme.TextSize.Body }
				)
				local durations = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 48),
					LayoutOrder = 5,
					Parent = content,
				}, { Create.List("x", 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
				for j, seconds in Regions.Caravan.durations do
					Button.new({
						Text = durationText(seconds),
						Color = if seconds == caravanDuration then C.Orange else C.Gray,
						Size = UDim2.fromOffset(110, 44),
						LayoutOrder = j,
						Parent = durations,
						OnClick = function()
							caravanDuration = seconds
							refresh()
						end,
					})
				end
				Button.new({
					Text = "Open caravan",
					Color = C.Green,
					Size = UDim2.fromOffset(240, 54),
					LayoutOrder = 6,
					Disabled = fs < 1,
					Parent = content,
					OnClick = function()
						if fs < 1 then
							ctx:Toast("Clear stage 1 first", "error")
							return
						end
						local ok = Util.requestOnce(ctx, "Expeditions.OpenCaravan", {
							region = region,
							stage = fs,
							duration = tostring(caravanDuration),
						})
						if ok then
							ctx:Toast("Caravan open. Invite others to join!", "success")
						end
					end,
				})
			end
			if not Util.unlocked(ctx, Regions.Caravan.unlock) then
				Util.lockOverlay(caravanRight, Util.unlockText(Regions.Caravan.unlock))
			end
		end

		-- Refresh ----------------------------------------------------------------------------------

		local function drawRegions()
			Util.clear(regionRow)
			for i, r in Regions.List do
				local unlocked = regionUnlocked(r)
				local text = r.name
				if not unlocked then
					text = string.format("%s · Lv %d", r.name, Util.unlockLevel(r.unlock))
				end
				local b = Button.new({
					Text = text,
					Color = if r.id == region then C.Orange elseif unlocked then C.Blue else C.Gray,
					Size = UDim2.fromOffset(240, 44),
					TextSize = Theme.TextSize.Small + 1,
					LayoutOrder = i,
					Parent = regionRow,
				})
				b:SetOnClick(function()
					if region ~= r.id then
						region = r.id
						selectedStage = nil
						refresh()
					end
				end)
			end
		end

		local function draw()
			if not isOpen then
				return
			end
			local r = Regions.ById[region] or Regions.List[1]
			region = r.id
			drawRegions()
			stagesView.Visible = mode == "stages"
			caravanView.Visible = mode == "caravans"
			if mode == "caravans" then
				drawCaravans()
				return
			end

			-- Map (the page follows the selected stage: main band or the Depths)
			local band = Regions.Band(r.id, stage())
			local sky = Color3.fromHex(band.colors and band.colors.sky or "#8FD3FF")
			local ground = Color3.fromHex(band.colors and band.colors.ground or "#A6DD73")
			mapCard.BackgroundColor3 = C.White
			mapGrad.Color = ColorSequence.new(sky, ground)
			mapTitle.Text = band.name
			local enemyNames = {}
			for _, e in r.elements do
				table.insert(enemyNames, elementName(e))
			end
			mapInfo.Text =
				string.format("Stage %d / %d · %s enemies", currentStage(), Regions.Stages(r.id), table.concat(enemyNames, " & "))
			local depths = r.depths
			pageRow.Visible = depths ~= nil
			if depths then
				local onDepths = band.depths
				coastButton:SetColor(if onDepths then C.Gray else C.Orange)
				depthsButton:SetColor(if onDepths then C.Orange else C.Gray)
				depthsButton:SetText(if Util.unlocked(ctx, depths.unlock) then "Depths" else "Depths 🔒")
			end
			for _, child in mapCard:GetChildren() do
				if child.Name == "Lock" then
					child:Destroy()
				end
			end
			drawMap(r)
			local unlocked = regionUnlocked(r)
			if not unlocked then
				Util.lockOverlay(mapCard, Util.unlockText(r.unlock))
			end

			-- Squad
			drawSquad()
			local ids = squadIds()
			local list = Util.monsters(ctx)
			local power = 0
			for _, id in ids do
				power += powerOf(list[id])
			end
			local s = stage()
			local rec = recommendedPower(region, s)
			powerLabel.Text = "Power " .. Format.commas(power)
			recLabel.Text = "Recommended " .. Format.commas(rec)
			recLabel.TextColor3 = if power >= rec then C.Green elseif power >= rec * 0.8 then C.Orange else C.Red
			hintLabel.Text = elementHint(r, ids)

			for seconds, b in durationButtons do
				b:SetColor(if seconds == duration then C.Orange else C.Gray)
			end
			drawLoot(r)

			local cur = currentStage()
			local allCleared = cleared(region) >= maxStage(region)
			fightButton:SetText(if allCleared and s == cur then "Replay stage " .. s else "Fight stage " .. s)
			fightButton:SetDisabled(not unlocked or #ids == 0)
			startButton:SetText(string.format("Start %s expedition", durationText(duration)))
			startButton:SetDisabled(not unlocked or farmStage() < 1 or #ids == 0 or freeSlot() == nil)
			drawSlots()
		end
		refresh = Util.debounce(draw)

		local function connect()
			bag.clean()
			for _, path in
				{
					"profile.Expeditions",
					"session.Expeditions",
					"global.Expeditions",
					"profile.Monsters.list",
					"profile.Progression.level",
				}
			do
				bag.add(ctx.Store:Observe(path, refresh))
			end
		end

		return {
			Root = panel.Root,
			Open = function(params)
				isOpen = true
				if type(params) == "table" then
					if params.region and Regions.ById[params.region] then
						if params.region ~= region then
							selectedStage = nil
						end
						region = params.region
					end
					if params.tab == "caravans" or params.tab == "stages" then
						modeTabs:Select(params.tab)
					end
				else
					-- Default to the furthest unlocked region the player has reached.
					for _, r in Regions.List do
						if regionUnlocked(r) and (cleared(r.id) > 0 or r.order == 1) then
							region = r.id
						end
					end
				end
				connect()
				refresh()
			end,
			Close = function()
				isOpen = false
				bag.clean()
			end,
		}
	end,
}
