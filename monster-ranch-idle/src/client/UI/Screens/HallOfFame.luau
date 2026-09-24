--[[
	HallOfFame screen (C3).

	Statues grid (profile.HallOfFame.entries appearances), Legacy bars per element (capped at
	Config.HallOfFame.LegacyCapPerElement), the Stardust upgrades list (HallOfFame.BuyUpgrade)
	and the Retire flow: Monsters pick mode filtered to Adults at their level cap, then a
	confirmation showing the Stardust, Star Shards and Legacy you get → HallOfFame.Retire.

	Reads: profile.HallOfFame, profile.Currency.stardust, profile.Monsters.list,
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
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local Util = require(script.Parent.Parts.Util)
local Dialog = require(script.Parent.Parts.Dialog)

local New = Create.New
local C = Theme.Colors
local HoF = Config.HallOfFame

local function atLevelCap(m): boolean
	local ok, cap = pcall(Formulas.LevelCap, m)
	return ok and (m.lv or 1) >= cap
end

return {
	Name = "HallOfFame",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Hall of Fame",
			Color = C.Purple,
			Size = UDim2.fromOffset(1040, 520),
			OnClose = function()
				ctx.Router:Close("HallOfFame")
			end,
		})
		local stardustPill = Widgets.Pill({ Icon = "stardust", Text = "0", Parent = panel.HeaderRight })
		stardustPill.Root.LayoutOrder = 1

		local isOpen = false
		local bag = Util.bag()
		local refresh

		local function hof()
			return ctx.Store:Get("profile.HallOfFame") or {}
		end
		local function legacyOf(element: string): number
			local legacy = hof().legacy
			return if type(legacy) == "table" then (legacy[element] or 0) else 0
		end
		local function upgradeLevel(id: string): number
			local upgrades = hof().upgrades
			return if type(upgrades) == "table" then (upgrades[id] or 0) else 0
		end

		-- Layout ----------------------------------------------------------------------------------

		local statuesCard, statuesTitle = Util.card({ Title = "Statues", Size = UDim2.new(0, 600, 0, 240), Parent = panel.Body })
		local statues = Widgets.Scroll({
			Cell = Vector2.new(92, 114),
			Padding = 8,
			Position = UDim2.fromOffset(4, 38),
			Size = UDim2.new(1, -8, 1, -42),
			Parent = statuesCard,
		})
		local legacyCard = Util.card({
			Title = "Legacy bonus",
			Position = UDim2.fromOffset(0, 250),
			Size = UDim2.new(0, 600, 1, -250),
			Parent = panel.Body,
		})
		local legacyGrid = New("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 40),
			Size = UDim2.new(1, -28, 1, -48),
			Parent = legacyCard,
		}, { Create.Grid(Vector2.new(278, 38), 8) })

		local upgradesCard = Util.card({
			Title = "Stardust upgrades",
			Position = UDim2.fromOffset(612, 0),
			Size = UDim2.new(1, -612, 1, -64),
			Parent = panel.Body,
		})
		local upgradeList =
			Widgets.List({ Position = UDim2.fromOffset(4, 38), Size = UDim2.new(1, -8, 1, -42), Padding = 6, Parent = upgradesCard })
		local retireButton = Button.new({
			Text = "Retire a monster",
			Color = C.Orange,
			Size = UDim2.new(1, -612, 0, 56),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 612, 1, 0),
			Parent = panel.Body,
		})

		-- Retire flow -------------------------------------------------------------------------------

		local function confirmRetire(id: string)
			local m = Util.monsters(ctx)[id]
			local ap = Util.appearance(m)
			if not m or not ap then
				return
			end
			local rarity = Config.Rarities.List[m.rarity or 1]
			local element = ap.elements[1]
			local current = legacyOf(element)
			local gain = math.max(0, math.min(rarity and rarity.legacyPct or 0, HoF.LegacyCapPerElement - current))
			local shards = HoF.StarShardsPerRetire[m.rarity or 1] or 0
			local stardust = rarity and rarity.stardust or 0
			local elementDef = Config.Elements.ById[element]
			Dialog.confirm(ctx.UI.Top, {
				Title = "Retire " .. ap.name .. "?",
				Color = C.Purple,
				Size = Vector2.new(580, 400),
				ConfirmText = "Retire",
				ConfirmColor = C.Orange,
				Build = function(content)
					local icon = MonsterIcon.new(ap, 110)
					icon.LayoutOrder = 1
					icon.Parent = content
					Util.text({
						Text = "It leaves your ranch for good and becomes a statue that visitors can see.",
						TextXAlignment = Enum.TextXAlignment.Center,
						AutomaticSize = Enum.AutomaticSize.Y,
						Size = UDim2.new(1, 0, 0, 20),
						LayoutOrder = 2,
						Parent = content,
					})
					local items = {
						{ kind = "stardust", amount = stardust, label = Format.commas(stardust) .. " Stardust" },
					}
					if shards > 0 then
						table.insert(items, {
							kind = "star",
							amount = shards,
							label = string.format("%d Star Shard%s", shards, if shards > 1 then "s" else ""),
						})
					end
					Util.rewardRow(items, content, { LayoutOrder = 3, IconSize = 28, Align = Enum.HorizontalAlignment.Center })
					Util.text({
						Text = if gain > 0
							then string.format(
								"+%s coins for every %s monster (Legacy %s → %s)",
								Format.percent(gain, 1),
								if elementDef then elementDef.name else element,
								Format.percent(current, 1),
								Format.percent(current + gain, 1)
							)
							else string.format(
								"%s Legacy is already at the %s cap",
								if elementDef then elementDef.name else element,
								Format.percent(HoF.LegacyCapPerElement)
							),
						Font = Theme.Fonts.Display,
						TextXAlignment = Enum.TextXAlignment.Center,
						AutomaticSize = Enum.AutomaticSize.Y,
						Size = UDim2.new(1, 0, 0, 20),
						LayoutOrder = 4,
						Parent = content,
					})
				end,
				OnConfirm = function()
					local ok, res = Util.requestOnce(ctx, "HallOfFame.Retire", { id = id })
					if ok then
						local got = if type(res) == "table" and res.stardust then res.stardust else stardust
						ctx:Toast(string.format("%s joined the Hall of Fame! +%s Stardust", ap.name, Format.commas(got)), "reward")
					end
				end,
			})
		end

		retireButton:SetOnClick(function()
			if not Util.unlocked(ctx, HoF.Unlock) then
				ctx:Toast(Util.unlockText(HoF.Unlock), "error")
				return
			end
			Util.pick(ctx, {
				title = "Retire an Adult at its level cap",
				max = 1,
				filter = function(m)
					return m.stage == 3 and not m.busy and not m.locked and atLevelCap(m)
				end,
				returnTo = "HallOfFame",
				onPick = function(ids)
					confirmRetire(ids[1])
				end,
			})
		end)

		-- Drawing ---------------------------------------------------------------------------------

		local function drawStatues()
			Util.clear(statues)
			local entries = hof().entries
			entries = if type(entries) == "table" then entries else {}
			statuesTitle.Text = string.format("Statues (%d)", #entries)
			if #entries == 0 then
				Util.text({
					Text = "Retire an Adult at its level cap to build your first statue.",
					TextColor3 = C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.fromOffset(560, 80),
					Parent = statues,
				})
				-- The grid cell would crop the message; use a plain list layout while empty.
				local grid = statues:FindFirstChildOfClass("UIGridLayout")
				if grid then
					grid.CellSize = UDim2.fromOffset(560, 80)
				end
				return
			end
			local grid = statues:FindFirstChildOfClass("UIGridLayout")
			if grid then
				grid.CellSize = UDim2.fromOffset(92, 114)
			end
			for i, entry in entries do
				local ap = entry.appearance
				if type(ap) == "table" and Config.Species.ById[ap.line] then
					local card = MonsterIcon.card(ap, 92, ap.name)
					card.LayoutOrder = i
					card.Parent = statues
				end
			end
		end

		local function drawLegacy()
			Util.clear(legacyGrid)
			for i, e in Config.Elements.List do
				local cell = New("Frame", { BackgroundTransparency = 1, LayoutOrder = i, Parent = legacyGrid })
				Util.text({ Text = e.name, Font = Theme.Fonts.Display, Size = UDim2.new(0, 72, 1, 0), Parent = cell })
				local value = legacyOf(e.id)
				local bar = Widgets.Bar({
					Color = Theme.Element(e.id),
					Value = value / HoF.LegacyCapPerElement,
					Text = string.format("+%s / %s", Format.percent(value, 1), Format.percent(HoF.LegacyCapPerElement)),
					Position = UDim2.new(0, 76, 0.5, -10),
					Size = UDim2.new(1, -80, 0, 20),
					Parent = cell,
				})
				bar.Root.Name = "Legacy_" .. e.id
			end
		end

		local function drawUpgrades()
			Util.clear(upgradeList)
			local stardust = ctx.Store:Get("profile.Currency.stardust") or 0
			for i, u in HoF.Upgrades do
				local level = upgradeLevel(u.id)
				local maxed = level >= u.maxLevel
				local cost = u.cost[level + 1]
				local row = New("Frame", {
					BackgroundColor3 = C.PanelDeep,
					Size = UDim2.new(1, -4, 0, 66),
					LayoutOrder = i,
					Parent = upgradeList,
				}, { Create.Corner(10) })
				Util.text({
					Text = string.format("%s  Lv %d/%d", u.name, level, u.maxLevel),
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body,
					Position = UDim2.fromOffset(10, 4),
					Size = UDim2.new(1, -150, 0, 24),
					Parent = row,
				})
				Util.text({
					Text = u.desc,
					TextColor3 = C.TextMuted,
					TextYAlignment = Enum.TextYAlignment.Top,
					Position = UDim2.fromOffset(10, 30),
					Size = UDim2.new(1, -150, 0, 34),
					Parent = row,
				})
				local button = Button.new({
					Text = if maxed then "MAX" else "✦ " .. Format.short(cost or 0),
					Color = C.Purple,
					Size = UDim2.fromOffset(128, 46),
					TextSize = Theme.TextSize.Body,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Disabled = maxed or stardust < (cost or 0),
					Parent = row,
				})
				button:SetOnClick(function()
					if maxed then
						return
					end
					if stardust < (cost or 0) then
						ctx:Toast("Not enough Stardust", "error")
						return
					end
					local ok = Util.requestOnce(ctx, "HallOfFame.BuyUpgrade", { upgrade = u.id })
					if ok then
						ctx:Toast(u.name .. " upgraded!", "success")
					end
				end)
			end
		end

		local lockOverlay = nil
		local function draw()
			if not isOpen then
				return
			end
			stardustPill:SetText(Format.short(ctx.Store:Get("profile.Currency.stardust") or 0))
			local shards = hof().starShards
			retireButton:SetText(
				if type(shards) == "number" and shards > 0
					then string.format("Retire a monster  (%d ★ shards)", shards)
					else "Retire a monster"
			)
			drawStatues()
			drawLegacy()
			drawUpgrades()
			if lockOverlay then
				lockOverlay:Destroy()
				lockOverlay = nil
			end
			if not Util.unlocked(ctx, HoF.Unlock) then
				lockOverlay = Util.lockOverlay(panel.Body, Util.unlockText(HoF.Unlock))
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				bag.clean()
				for _, path in { "profile.HallOfFame", "profile.Currency.stardust", "profile.Progression.level" } do
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
