--[[
	Apiary (update 3.12 · Honey & stars): the Apiary screen. Opened by the "Tend" prompt at the
	beehives (Controllers/Apiary). No HUD button.

	  Left    one card per hive: locked ("Unlocks at Ranch Level 27"), empty ("Assign a keeper":
	          Monsters pick mode with the free Adults in the barn, best SPD first -> Apiary.Assign)
	          or tended: the keeper, honey an hour (the Sprout bonus noted), a fill bar with the
	          stored honey, the time to full, and Unassign (Apiary.Unassign).
	  Right   the honey store: each kind and Royal Jelly with its count and "Sell all"
	          (Apiary.Sell, SellSeconds of ranch income each).
	Header: Collect all (Apiary.Collect). The intro names this season's honey.

	Reads: profile.Apiary, session.Apiary, profile.Monsters.list, profile.Progression.level (all
	tolerated nil).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local Logic = require(Shared.Logic.Apiary)

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
local Rules = Config.Apiary

local HIVE_W = 236
local STORE_W = 256

local function iconKind(kind: string): string
	return if kind == Rules.RoyalJelly.id then kind else "honey_" .. kind
end

return {
	Name = "Apiary",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Apiary",
			Color = C.Coin,
			Size = UDim2.fromOffset(1040, 520),
			OnClose = function()
				ctx.Router:Close("Apiary")
			end,
		})

		local isOpen = false
		local bag = Util.bag()
		local refresh
		local tickers = {} -- per tended hive: fn() that updates its bar and times
		local lock = nil

		local collectAll = Button.new({
			Name = "CollectAll",
			Text = "Collect all",
			Color = C.Green,
			Size = UDim2.fromOffset(170, 44),
			TextSize = Theme.TextSize.Body,
			Parent = panel.HeaderRight,
		})

		local intro = Util.text({
			Name = "Intro",
			Text = "",
			TextColor3 = C.TextMuted,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 44),
			Parent = panel.Body,
		})
		local view = New("Frame", {
			Name = "View",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 50),
			Size = UDim2.new(1, 0, 1, -50),
			Parent = panel.Body,
		})

		local function apiary()
			local a = ctx.Store:Get("profile.Apiary")
			return if type(a) == "table" then a else {}
		end
		local function session()
			local s = ctx.Store:Get("session.Apiary")
			return if type(s) == "table" then s else {}
		end
		local function hiveCount(): number
			local s = session()
			if type(s.hives) == "number" then
				return s.hives
			end
			return Logic.HiveCount(function(key)
				return Util.unlocked(ctx, key)
			end)
		end
		local function extra(): number
			return tonumber(session().extra) or 0
		end
		local function have(kind: string): number
			local store = apiary().store
			return if type(store) == "table" then tonumber(store[kind]) or 0 else 0
		end

		-- Actions ---------------------------------------------------------------------------

		local function chooseKeeper(index: number)
			Util.pick(ctx, {
				title = string.format("Choose a keeper for Beehive %d (best SPD first)", index),
				max = 1,
				filter = function(m)
					return (m.stage or 1) >= Rules.MinStage and not m.busy and m.loc ~= "pen"
				end,
				sortBy = function(m)
					return Formulas.Stats(m).spd or 0
				end,
				returnTo = "Apiary",
				onPick = function(ids)
					Util.requestOnce(ctx, "Apiary.Assign", { hive = index, id = ids[1] })
				end,
			})
		end

		collectAll:SetOnClick(function()
			local ok = Util.requestOnce(ctx, "Apiary.Collect")
			if ok then
				ctx:Sound("CoinCollect")
			end
		end)

		-- Hives -------------------------------------------------------------------------------

		local function drawHive(parent: Instance, index: number)
			local card = Util.card({
				Name = "Hive" .. index,
				Size = UDim2.new(0, HIVE_W, 1, 0),
				LayoutOrder = index,
				Parent = parent,
			})
			Util.text({
				Text = string.format("Beehive %d", index),
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(12, 8),
				Size = UDim2.new(1, -24, 0, 28),
				Parent = card,
			})
			if index > hiveCount() then
				Util.lockOverlay(card, Util.unlockText(Rules.HiveUnlocks[index]))
				return
			end
			local hives = apiary().hives
			local hive = type(hives) == "table" and hives[index] or nil
			local m = type(hive) == "table" and hive.monster and Util.monsters(ctx)[hive.monster] or nil
			if not m then
				Util.text({
					Name = "Empty",
					Text = "No keeper yet. An Adult resting in the barn can tend this hive.",
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					TextSize = Theme.TextSize.Small,
					Position = UDim2.fromOffset(12, 44),
					Size = UDim2.new(1, -24, 0, 90),
					Parent = card,
				})
				Button.new({
					Name = "Assign",
					Text = "Assign a keeper",
					Color = C.Orange,
					Size = UDim2.new(1, -24, 0, 44),
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 12, 1, -12),
					TextSize = Theme.TextSize.Small + 1,
					Parent = card,
					OnClick = function()
						chooseKeeper(index)
					end,
				})
				-- Honey left in a hive whose keeper left the ranch still collects.
				if type(hive) == "table" and Logic.Total(hive.stored) >= 1 then
					Util.text({
						Name = "Leftover",
						Text = string.format("%d honey waiting", math.floor(Logic.Total(hive.stored))),
						TextSize = Theme.TextSize.Small,
						Position = UDim2.fromOffset(12, 140),
						Size = UDim2.new(1, -24, 0, 24),
						Parent = card,
					})
				end
				return
			end
			local name = Util.text({
				Name = "Keeper",
				Text = Formulas.DisplayName(m),
				TextSize = Theme.TextSize.Small + 1,
				Position = UDim2.fromOffset(12, 40),
				Size = UDim2.new(1, -24, 0, 24),
				Parent = card,
			})
			name:SetAttribute("Localize", false)
			local perHour = Logic.PerHour(m)
			Util.text({
				Name = "Rate",
				Text = string.format("%s honey an hour", string.format("%.1f", perHour)),
				TextSize = Theme.TextSize.Small,
				Position = UDim2.fromOffset(12, 66),
				Size = UDim2.new(1, -24, 0, 22),
				Parent = card,
			})
			if Logic.IsSprout(m) then
				Util.text({
					Name = "Sprout",
					Text = "Sprout keeper · +25% honey",
					TextColor3 = C.Green,
					TextSize = Theme.TextSize.Small,
					Position = UDim2.fromOffset(12, 88),
					Size = UDim2.new(1, -24, 0, 22),
					Parent = card,
				})
			end
			local bar = Widgets.Bar({
				Name = "Fill",
				Color = C.Coin,
				Text = "",
				Size = UDim2.new(1, -24, 0, 24),
				Position = UDim2.fromOffset(12, 118),
				Parent = card,
			})
			local full = Util.text({
				Name = "FullIn",
				Text = "",
				TextSize = Theme.TextSize.Small,
				Position = UDim2.fromOffset(12, 148),
				Size = UDim2.new(1, -24, 0, 24),
				Parent = card,
			})
			local function tick()
				local now = ctx:Now()
				local pending = Logic.Pending(hive, m, now, extra())
				local cap = Logic.Cap(m, extra())
				bar:SetValue(if cap > 0 then pending / cap else 0)
				bar:SetText(string.format("%d / %d honey", math.floor(pending), math.floor(cap)))
				local left = Logic.SecondsToFull(hive, m, now, extra())
				if left <= 0 then
					full.Text = "Full · collect it!"
					full.TextColor3 = C.Red
				else
					full.Text = string.format("Full in %s", Format.duration(left))
					full.TextColor3 = C.TextMuted
				end
			end
			tick()
			table.insert(tickers, tick)
			Button.new({
				Name = "Unassign",
				Text = "Unassign",
				Color = C.Purple,
				Size = UDim2.new(1, -24, 0, 44),
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 12, 1, -12),
				TextSize = Theme.TextSize.Small + 1,
				Parent = card,
				OnClick = function()
					Util.requestOnce(ctx, "Apiary.Unassign", { hive = index })
				end,
			})
		end

		-- Store -------------------------------------------------------------------------------

		local function drawStore(parent: Instance)
			local col = Util.card({
				Name = "Store",
				Size = UDim2.new(0, STORE_W, 1, 0),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Parent = parent,
			})
			Util.text({
				Text = "Honey store",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(12, 6),
				Size = UDim2.new(1, -24, 0, 28),
				Parent = col,
			})
			local list = New("Frame", {
				Name = "Kinds",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(8, 38),
				Size = UDim2.new(1, -16, 1, -44),
				Parent = col,
			}, { Create.List("y", 4) })
			for i, kind in Rules.AllIds do
				local n = have(kind)
				local row = New("Frame", {
					Name = "Kind_" .. kind,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 62),
					LayoutOrder = i,
					Parent = list,
				})
				local icon = Icon.new(iconKind(kind), 30)
				icon.Position = UDim2.fromOffset(0, 20)
				icon.Parent = row
				Util.text({
					Text = Logic.Name(kind),
					TextSize = Theme.TextSize.Small,
					Position = UDim2.fromOffset(36, 0),
					Size = UDim2.new(1, -36, 0, 20),
					Parent = row,
				})
				local count = Util.text({
					Name = "Count",
					Text = string.format("×%d", n),
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Small + 1,
					Position = UDim2.fromOffset(36, 24),
					Size = UDim2.new(1, -136, 0, 30),
					Parent = row,
				})
				count:SetAttribute("Localize", false)
				local sell = Button.new({
					Name = "Sell_" .. kind,
					Text = "Sell all",
					Color = C.Green,
					Size = UDim2.fromOffset(100, 44),
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, 18),
					TextSize = Theme.TextSize.Small,
					Parent = row,
					OnClick = function()
						local amount = have(kind)
						if amount > 0 then
							local ok = Util.requestOnce(ctx, "Apiary.Sell", { kind = kind, amount = amount })
							if ok then
								ctx:Sound("CoinCollect")
							end
						end
					end,
				})
				sell:SetDisabled(n <= 0)
			end
		end

		-- Draw ------------------------------------------------------------------------------

		local function anyHoney(): boolean
			local hives = apiary().hives
			local list = Util.monsters(ctx)
			local now = ctx:Now()
			for _, hive in (if type(hives) == "table" then hives else {}) do
				if type(hive) == "table" then
					local m = hive.monster and list[hive.monster] or nil
					if Logic.Pending(hive, m, now, extra()) >= 1 then
						return true
					end
				end
			end
			return false
		end

		local function draw()
			if not isOpen then
				return
			end
			Util.clear(view)
			table.clear(tickers)
			if lock then
				lock:Destroy()
				lock = nil
			end
			local kind = Rules.ById[Logic.KindAt(ctx:Now())]
			intro.Text = string.format(
				"This season the bees make %s. A hive holds %d hours of honey, then waits to be collected.",
				kind.name,
				Rules.CapHours + extra()
			)
			local row = New("Frame", {
				Name = "Hives",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -(STORE_W + 10), 1, 0),
				Parent = view,
			}, { Create.List("x", 8) })
			for index = 1, Rules.MaxHives do
				drawHive(row, index)
			end
			drawStore(view)
			collectAll:SetDisabled(not anyHoney())
			if not Util.unlocked(ctx, Rules.Unlock) then
				lock = Util.lockOverlay(view, Util.unlockText(Rules.Unlock))
				collectAll:SetDisabled(true)
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				bag.clean()
				for _, path in { "profile.Apiary", "session.Apiary", "profile.Monsters.list", "profile.Progression.level" } do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				draw()
				task.spawn(function()
					while isOpen do
						task.wait(1)
						if isOpen then
							for _, tick in tickers do
								tick()
							end
							if Util.unlocked(ctx, Rules.Unlock) then
								collectAll:SetDisabled(not anyHoney())
							end
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
