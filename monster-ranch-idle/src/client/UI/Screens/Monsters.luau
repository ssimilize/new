--[[
	Monsters (C2): the roster.

	Params:
	  { tab? = "all" | "pens" | "barn" | "busy" }
	  { pick = { title, filter = fn(monster) -> bool, max = 1, onPick = fn({ ids }), returnTo, returnParams } }

	Normal mode  tabs (All / In pens / Barn / Busy), sort (rarity, level, power, newest),
	             tap → MonsterDetail { id }. "Sell" toggles multi-select sell mode with a total
	             price preview (Formulas.SellPrice) → Monsters.Sell { ids } (two taps to confirm).
	Pick mode    (ARCHITECTURE §5) only monsters passing `filter` are shown (a filter that
	             errors counts as false). max == 1: a tap picks. max > 1: select up to `max`,
	             then Confirm. On pick the screen closes, opens `returnTo` with `returnParams`,
	             THEN calls onPick(ids) (so the returning screen's Open runs first and onPick can
	             update it). Closing without picking (✕, dim, back) reopens `returnTo` with
	             `returnParams` and never calls onPick, unless another screen was opened instead.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local Appearance = require(Shared.Logic.Appearance)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Icon = require(UI.Components.Icon)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)
local Tiles = require(UI.Components.Tiles)

local New = Create.New
local C = Theme.Colors

local Monsters = { Name = "Monsters" }

local CARD = 104
local SORTS = { "rarity", "level", "power", "newest" }
local SORT_NAMES = { rarity = "Rarity", level = "Level", power = "Power", newest = "Newest" }
local BUSY_TEXT = { expedition = "Away", breeding = "Breeding", trade = "Trading" }

local function idNumber(id: string): number
	return tonumber(string.match(id, "%d+")) or 0
end

local function signature(m): string
	return table.concat({
		tostring(m.form),
		tostring(m.stage),
		tostring(m.rarity),
		tostring(m.variant),
		tostring(m.lv),
		tostring(m.stars),
		table.concat(StoreKit.asTable(m.muts), ","),
		tostring(m.name),
		tostring(m.busy),
		tostring(m.locked),
		tostring(m.loc),
		tostring(m.pen),
		tostring(m.weight),
		tostring(m.growEndsAt),
	}, "|")
end

function Monsters.Build(ctx)
	local store = ctx.Store
	local tab = "all"
	local sortIndex = 1
	local sellMode = false
	local pick = nil -- active pick request (normalised)
	local selected = {} -- id -> true
	local selectedCount = 0
	local confirmUntil = 0
	local cells = {} -- id -> { cell, sig, check }

	local panel = Panel.new({
		Title = "Monsters",
		Color = C.Green,
		Size = UDim2.fromOffset(980, 490),
		OnClose = function()
			ctx.Router:Close("Monsters")
		end,
	})
	local sortButton =
		Button.new({ Text = "Sort: Rarity", Color = C.Blue, Size = UDim2.fromOffset(170, 44), LayoutOrder = 1, Parent = panel.HeaderRight })
	local sellButton =
		Button.new({ Text = "Sell", Color = C.Red, Size = UDim2.fromOffset(110, 44), LayoutOrder = 2, Parent = panel.HeaderRight })

	local refresh
	local tabs = Widgets.Tabs({
		Tabs = {
			{ id = "all", text = "All", width = 110 },
			{ id = "pens", text = "In pens", width = 130 },
			{ id = "barn", text = "Barn", width = 110 },
			{ id = "busy", text = "Busy", width = 110 },
		},
		Selected = "all",
		Parent = panel.Body,
		OnChanged = function(id)
			tab = id
			if refresh then
				refresh()
			end
		end,
	})
	local grid = Widgets.Scroll({
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -114),
		Cell = Vector2.new(CARD, CARD + 30),
		Padding = 10,
		Parent = panel.Body,
	})
	local emptyLabel = Tiles.label({
		Text = "",
		TextSize = Theme.TextSize.Body,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 150),
		Size = UDim2.new(1, 0, 0, 40),
		Visible = false,
		Parent = panel.Body,
	})

	-- Bottom action bar
	local bar = Tiles.frame({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 56),
		Parent = panel.Body,
	})
	local barLabel = Tiles.label({ Text = "", TextSize = Theme.TextSize.Body, Size = UDim2.new(1, -420, 1, 0), Parent = bar })
	local barButtons = Tiles.row({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 420, 1, 0),
		Parent = bar,
	}, 10, Enum.HorizontalAlignment.Right)
	local clearButton =
		Button.new({ Text = "Clear", Color = C.Gray, Size = UDim2.fromOffset(110, 50), LayoutOrder = 1, Parent = barButtons })
	local actionButton =
		Button.new({ Text = "Sell", Color = C.Red, Size = UDim2.fromOffset(240, 52), LayoutOrder = 2, Parent = barButtons })

	-- Data --------------------------------------------------------------------------

	local function passesTab(m): boolean
		if pick then
			return true
		end
		if tab == "pens" then
			return m.loc == "pen" and not m.busy
		elseif tab == "barn" then
			return m.loc ~= "pen" and not m.busy
		elseif tab == "busy" then
			return m.busy ~= nil and m.busy ~= false
		end
		return true
	end

	local function passesPick(id: string, m): boolean
		if not pick or not pick.filter then
			return true
		end
		-- Filters may compare ids; give them one even if the record lacks the field.
		local record = if m.id == id then m else setmetatable({ id = id }, { __index = m })
		local ok, result = pcall(pick.filter, record)
		return ok and result == true
	end

	local function sortedList()
		local list = {}
		local power = {}
		local mode = SORTS[sortIndex]
		for id, m in StoreKit.monsters(store) do
			if type(m) == "table" and Config.Species.ById[m.line or ""] then
				if passesTab(m) and passesPick(id, m) then
					table.insert(list, { id = id, m = m })
					if mode == "power" then
						local ok, p = pcall(Formulas.MonsterPower, m)
						power[id] = if ok then p else 0
					end
				end
			end
		end
		table.sort(list, function(a, b)
			local ma, mb = a.m, b.m
			if mode == "level" and (ma.lv or 1) ~= (mb.lv or 1) then
				return (ma.lv or 1) > (mb.lv or 1)
			elseif mode == "power" and power[a.id] ~= power[b.id] then
				return power[a.id] > power[b.id]
			elseif mode == "newest" then
				local ba, bb = tonumber(ma.born) or 0, tonumber(mb.born) or 0
				if ba ~= bb then
					return ba > bb
				end
				return idNumber(a.id) > idNumber(b.id)
			end
			if (ma.rarity or 1) ~= (mb.rarity or 1) then
				return (ma.rarity or 1) > (mb.rarity or 1)
			end
			if (ma.lv or 1) ~= (mb.lv or 1) then
				return (ma.lv or 1) > (mb.lv or 1)
			end
			return idNumber(a.id) < idNumber(b.id)
		end)
		return list
	end

	local function sellable(m): (boolean, string?)
		if m.locked then
			return false, Formulas.DisplayName(m) .. " is locked"
		end
		if m.busy then
			return false, Formulas.DisplayName(m) .. " is busy"
		end
		return true, nil
	end

	-- Cards -----------------------------------------------------------------------

	local onTap

	local function buildCell(id: string, m)
		local ok, ap = pcall(Appearance.Of, m)
		if not ok then
			return nil
		end
		local cell = Tiles.frame({ Name = id, Size = UDim2.fromOffset(CARD, CARD + 30) })
		local footer = string.format("Lv %d · %s", m.lv or 1, Formulas.DisplayName(m))
		local card = MonsterIcon.card(ap, CARD, footer)
		card.Parent = cell
		if (m.stars or 1) > 1 then
			Create.Text({
				Text = string.rep("★", math.min(m.stars, 5)),
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.Gold,
				Stroke = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(6, 2),
				Size = UDim2.fromOffset(80, 18),
				ZIndex = 12,
				Parent = cell,
			})
		end
		if m.locked then
			local lock = Icon.new("lock", 22)
			lock.AnchorPoint = Vector2.new(1, 0)
			lock.Position = UDim2.new(1, -4, 0, 4)
			lock.ZIndex = 12
			lock.Parent = cell
		elseif m.loc == "pen" and not m.busy then
			local chip = Widgets.Chip({ Text = "Pen " .. tostring(m.pen or "?"), Color = C.Green, Parent = cell })
			chip.AnchorPoint = Vector2.new(1, 0)
			chip.Position = UDim2.new(1, -2, 0, 2)
			chip.ZIndex = 12
		end
		if (tonumber(m.growEndsAt) or 0) > 0 then
			local chip = Widgets.Chip({ Text = "Growing", Color = C.Blue, Parent = cell })
			chip.Position = UDim2.fromOffset(2, CARD - 30)
			chip.ZIndex = 12
		end
		local dim
		if m.busy then
			dim = New("Frame", {
				BackgroundColor3 = C.Dark,
				BackgroundTransparency = 0.45,
				Size = UDim2.fromOffset(CARD, CARD + 22),
				ZIndex = 13,
				Parent = cell,
			}, { Create.Corner(Theme.Radius.Card) })
			Create.Text({
				Text = BUSY_TEXT[m.busy] or "Busy",
				TextSize = Theme.TextSize.Body,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 14,
				Parent = dim,
			})
		end
		local check = New("Frame", {
			Name = "Check",
			BackgroundColor3 = C.Green,
			BackgroundTransparency = 0.35,
			Size = UDim2.fromOffset(CARD, CARD + 22),
			Visible = false,
			ZIndex = 15,
			Parent = cell,
		}, { Create.Corner(Theme.Radius.Card), Create.Stroke(4, C.Green) })
		Create.Text({ Text = "✔", TextSize = 44, Size = UDim2.fromScale(1, 1), ZIndex = 16, Parent = check })
		Tiles.tap(cell, function()
			onTap(id)
		end, 30)
		return { cell = cell, check = check }
	end

	local function updateSelectionVisuals()
		for id, entry in cells do
			entry.check.Visible = selected[id] == true
		end
	end

	local function updateBar()
		local list = StoreKit.monsters(store)
		clearButton:SetVisible(false)
		actionButton:SetVisible(false)
		if pick then
			if pick.max == 1 then
				barLabel.Text = "Tap a monster to pick it"
			else
				barLabel.Text = string.format("Selected %d / %d", selectedCount, pick.max)
				clearButton:SetVisible(selectedCount > 0)
				actionButton:SetVisible(true)
				actionButton:SetColor(C.Green)
				actionButton:SetText(string.format("Confirm (%d)", selectedCount))
				actionButton:SetDisabled(selectedCount == 0)
			end
			return
		end
		if sellMode then
			local total = 0
			for id in selected do
				local m = list[id]
				if type(m) == "table" then
					local ok, price = pcall(Formulas.SellPrice, m)
					total += if ok then price else 0
				end
			end
			barLabel.Text = string.format("Selected %d · sells for %s coins", selectedCount, Format.short(total))
			clearButton:SetVisible(selectedCount > 0)
			actionButton:SetVisible(true)
			actionButton:SetColor(C.Red)
			actionButton:SetDisabled(selectedCount == 0)
			actionButton:SetText(if os.clock() < confirmUntil then "Tap again to sell" else string.format("Sell %d", selectedCount))
			return
		end
		local count = 0
		for _ in list do
			count += 1
		end
		local capacity = StoreKit.num(store, "session.Ranch.capacity")
		barLabel.Text = if capacity > 0
			then string.format("%d monsters · room for %d", count, capacity)
			else string.format("%d monsters", count)
	end

	function refresh()
		local list = sortedList()
		local keep = {}
		for i, entry in ipairs(list) do
			local id, m = entry.id, entry.m
			local sig = signature(m)
			local c = cells[id]
			if c and c.sig ~= sig then
				c.cell:Destroy()
				c = nil
				cells[id] = nil
			end
			if not c then
				c = buildCell(id, m)
				if c then
					c.sig = sig
					cells[id] = c
					c.cell.Parent = grid
				end
			end
			if c then
				c.cell.LayoutOrder = i
				c.cell.Visible = true
				keep[id] = true
			end
		end
		for id, c in cells do
			if not keep[id] then
				if StoreKit.monsters(store)[id] == nil then
					c.cell:Destroy()
					cells[id] = nil
				else
					c.cell.Visible = false
				end
			end
		end
		-- Drop selections that vanished (sold, now busy, filtered out).
		selectedCount = 0
		for id in selected do
			if keep[id] then
				selectedCount += 1
			else
				selected[id] = nil
			end
		end
		emptyLabel.Visible = #list == 0
		emptyLabel.Text = if pick then "No monsters fit. Hatch or grow more!" else "Nothing here yet."
		updateSelectionVisuals()
		updateBar()
	end

	local function finishPick(ids: { string })
		local p = pick
		pick = nil -- set first: the Close handler below must not treat this as a cancel
		ctx.Router:Close("Monsters")
		if p.returnTo and ctx.Router:Has(p.returnTo) then
			ctx.Router:Open(p.returnTo, p.returnParams)
		end
		if p.onPick then
			task.spawn(function()
				local ok, err = xpcall(p.onPick, debug.traceback, ids)
				if not ok then
					warn("[Monsters] onPick failed: " .. tostring(err))
				end
			end)
		end
	end

	function onTap(id: string)
		local m = StoreKit.monsters(store)[id]
		if type(m) ~= "table" then
			return
		end
		if pick then
			if pick.max == 1 then
				finishPick({ id })
				return
			end
			if selected[id] then
				selected[id] = nil
			elseif selectedCount >= pick.max then
				ctx:Toast(string.format("You can pick up to %d", pick.max), "info")
				return
			else
				selected[id] = true
			end
		elseif sellMode then
			if selected[id] then
				selected[id] = nil
			else
				local ok, why = sellable(m)
				if not ok then
					ctx:Toast(why or "Can't sell that", "error")
					return
				end
				selected[id] = true
			end
			confirmUntil = 0
		else
			ctx.Router:Open("MonsterDetail", { id = id })
			return
		end
		selectedCount = 0
		for _ in selected do
			selectedCount += 1
		end
		updateSelectionVisuals()
		updateBar()
	end

	local function setSellMode(on: boolean)
		sellMode = on
		table.clear(selected)
		selectedCount = 0
		confirmUntil = 0
		sellButton:SetText(if on then "Done" else "Sell")
		sellButton:SetColor(if on then C.Gray else C.Red)
		panel:SetTitle(if on then "Sell monsters" else "Monsters")
		updateSelectionVisuals()
		updateBar()
	end

	sortButton:SetOnClick(function()
		sortIndex = sortIndex % #SORTS + 1
		sortButton:SetText("Sort: " .. SORT_NAMES[SORTS[sortIndex]])
		refresh()
	end)
	sellButton:SetOnClick(function()
		setSellMode(not sellMode)
	end)
	clearButton:SetOnClick(function()
		table.clear(selected)
		selectedCount = 0
		confirmUntil = 0
		updateSelectionVisuals()
		updateBar()
	end)
	actionButton:SetOnClick(function()
		if pick then
			local ids = {}
			for id in selected do
				table.insert(ids, id)
			end
			if #ids > 0 then
				finishPick(ids)
			end
			return
		end
		if not sellMode or selectedCount == 0 then
			return
		end
		if os.clock() >= confirmUntil then
			confirmUntil = os.clock() + 3
			updateBar()
			task.delay(3.1, updateBar)
			return
		end
		confirmUntil = 0
		local ids = {}
		for id in selected do
			if #ids < 50 then
				table.insert(ids, id)
			end
		end
		local ok, res = StoreKit.request(ctx, "Monsters.Sell", { ids = ids })
		if ok then
			local coins = type(res) == "table" and tonumber(res.coins) or 0
			ctx:Toast(string.format("Sold %d for %s coins", #ids, Format.short(coins)), "reward")
			table.clear(selected)
			selectedCount = 0
		end
		refresh()
	end)

	local watch = StoreKit.watch(store, { "profile.Monsters.list", "session.Ranch" }, function()
		refresh()
	end)

	return {
		Root = panel.Root,
		Open = function(params)
			local p = type(params) == "table" and params or {}
			table.clear(selected)
			selectedCount = 0
			sellMode = false
			confirmUntil = 0
			sellButton:SetText("Sell")
			sellButton:SetColor(C.Red)
			if type(p.pick) == "table" then
				pick = {
					title = tostring(p.pick.title or "Pick a monster"),
					filter = if type(p.pick.filter) == "function" then p.pick.filter else nil,
					max = math.max(1, math.floor(tonumber(p.pick.max) or 1)),
					onPick = if type(p.pick.onPick) == "function" then p.pick.onPick else nil,
					returnTo = if type(p.pick.returnTo) == "string" then p.pick.returnTo else nil,
					returnParams = p.pick.returnParams,
				}
				panel:SetTitle(pick.title)
				panel:SetColor(C.Purple)
				sellButton:SetVisible(false)
				tabs.Root.Visible = false
				grid.Position = UDim2.fromOffset(0, 0)
				grid.Size = UDim2.new(1, 0, 1, -64)
			else
				pick = nil
				panel:SetTitle("Monsters")
				panel:SetColor(C.Green)
				sellButton:SetVisible(true)
				tabs.Root.Visible = true
				grid.Position = UDim2.fromOffset(0, 50)
				grid.Size = UDim2.new(1, 0, 1, -114)
				local wanted = if p.tab == "pens" or p.tab == "barn" or p.tab == "busy" then p.tab else "all"
				tab = wanted
				tabs:Select(wanted)
			end
			grid.CanvasPosition = Vector2.zero
			watch.Start()
			watch.Refresh()
		end,
		Close = function()
			watch.Stop()
			local p = pick
			pick = nil
			if p then
				-- Cancelled pick: go back to the caller, unless the player opened something else.
				task.defer(function()
					if p.returnTo and ctx.Router:Current() == nil and ctx.Router:Has(p.returnTo) then
						ctx.Router:Open(p.returnTo, p.returnParams)
					end
				end)
			end
		end,
	}
end

return Monsters
