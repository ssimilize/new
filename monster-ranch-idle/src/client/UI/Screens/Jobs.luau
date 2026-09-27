--[[
	Jobs (update 3.7): the Job Board screen.

	One card per slot (Config.Jobs.MaxSlots):
	  locked    "Unlocks at Ranch Level N"
	  empty     a button per job ("Miner · ATK"); tapping one opens Monsters pick mode with the
	            free Teens and Adults in the barn, best at that job's stat first → Jobs.Assign
	  working   the job, the worker, its stat, its rate (Logic/Jobs), a storage bar that fills
	            over MaxHours with what it has built up, a flavour button for foragers
	            (Jobs.SetFlavor) and Recall (Jobs.Recall)
	Header: Collect all (Jobs.Collect). Stored amounts tick every second while open.

	Tabs (3.8): "Jobs" (the slots above) and "Orders" (Ranch Orders, Logic/Orders): one card
	per order with its buyer, the requirement in words, the rewards (and the egg a hard order
	rolled), Reroll (once a day, Orders.Reroll) and
	  monster orders  "Choose monster": Monsters pick mode with the Teens and Adults that meet it
	                  (not busy, not locked), cheapest first, then a confirm naming the monster
	                  that leaves → Orders.Fill { index, id }
	  goods orders    "Hand over" → Orders.Fill { index }
		3.9 buyer reputation: each card shows its buyer's level (and "Favourite" on the extra
	favourite buyer order); the header's "Buyers" button swaps the cards for the Buyers panel:
	the 8 buyers with their level, a bar to the next level and the next perk.
Params: { tab? = "jobs" | "orders" }.

	Reads: profile.Jobs.slots, session.Jobs.slotCount, profile.Monsters.list,
	profile.Progression.level, profile.Orders, profile.Currency.food (all tolerated nil).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local JobsLogic = require(Shared.Logic.Jobs)
local OrdersLogic = require(Shared.Logic.Orders)

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
local Rules = Config.Jobs
local OrderRules = Config.Orders
local StatNames = Config.Genetics.StatNames

local HOUR = 3600

-- The job's headline number for one worker, as the card shows it.
local function rateText(jobId: string, m): string
	if jobId == "herder" then
		return string.format("Pen Mood drops %d%% slower", math.floor(JobsLogic.Shield({ m }) * 100 + 0.5))
	elseif jobId == "miner" then
		return string.format("%s coins an hour", Format.short(math.floor(JobsLogic.CoinsPerSecond(m) * HOUR)))
	elseif jobId == "guard" then
		return string.format("Coin jars +%d min", math.floor(JobsLogic.GuardMinutes(m) + 0.5))
	elseif jobId == "forager" then
		return string.format("%.1f food an hour", JobsLogic.FoodPerHour(m))
	elseif jobId == "scout" then
		return string.format("%s egg chance an hour", Format.percent(JobsLogic.EggChancePerHour(m), 1))
	end
	return ""
end

local function storedText(jobId: string, rewards, full: boolean): string
	local n = 0
	for _, r in rewards do
		n += r.amount or 0
	end
	local text
	if jobId == "miner" then
		text = "Coins stored: " .. Format.short(n)
	elseif jobId == "forager" then
		text = "Food stored: " .. tostring(n)
	elseif jobId == "scout" then
		text = "Eggs found: " .. tostring(n)
	else
		return "On duty"
	end
	return if full then text .. " · Full" else text
end

return {
	Name = "Jobs",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Job Board",
			Color = C.Purple,
			Size = UDim2.fromOffset(1040, 520),
			OnClose = function()
				ctx.Router:Close("Jobs")
			end,
		})

		local isOpen = false
		local bag = Util.bag()
		local refresh
		local tickers = {} -- per working card: fn() that updates its stored amount
		local lockOverlay = nil
		local ordersLock = nil
		local tab = "jobs"
		local showBuyers = false -- 3.9: the Orders tab shows the Buyers panel instead of the cards

		local collectAll = Button.new({
			Name = "CollectAll",
			Text = "Collect all",
			Color = C.Green,
			Size = UDim2.fromOffset(170, 44),
			TextSize = Theme.TextSize.Body,
			LayoutOrder = 1,
			Parent = panel.HeaderRight,
		})

		local buyersButton = Button.new({
			Name = "BuyersToggle",
			Text = "Buyers",
			Color = C.Purple,
			Size = UDim2.fromOffset(170, 44),
			TextSize = Theme.TextSize.Body,
			LayoutOrder = 2,
			Parent = panel.HeaderRight,
		})
		buyersButton:SetVisible(false)

		local tabs = Widgets.Tabs({
			Tabs = { { id = "jobs", text = "Jobs" }, { id = "orders", text = "Orders" } },
			Selected = tab,
			Size = UDim2.fromOffset(276, 44),
			Parent = panel.Body,
			OnChanged = function(id)
				tab = id
				if refresh then
					refresh()
				end
			end,
		})
		local jobsIntro = Util.text({
			Text = string.format("Teens and Adults resting in the barn can work. Workers store up to %d hours.", Rules.MaxHours),
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(290, 0),
			Size = UDim2.new(1, -290, 0, 44),
			Parent = panel.Body,
		})
		local ordersIntro = Util.text({
			Text = "Buyers post new orders every day. A monster you hand over leaves for good.",
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(290, 0),
			Size = UDim2.new(1, -290, 0, 44),
			Visible = false,
			Parent = panel.Body,
		})
		local jobsView = New("Frame", {
			Name = "JobsView",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 50),
			Size = UDim2.new(1, 0, 1, -50),
			Parent = panel.Body,
		})
		local row = New("Frame", {
			Name = "Slots",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = jobsView,
		}, { Create.List("x", 10) })
		local ordersView = New("Frame", {
			Name = "OrdersView",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 50),
			Size = UDim2.new(1, 0, 1, -50),
			Visible = false,
			Parent = panel.Body,
		})
		local ordersRow = New("Frame", {
			Name = "Orders",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = ordersView,
		}, { Create.List("x", 10) })
		local buyersView = New("Frame", {
			Name = "Buyers",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = ordersView,
		})

		local function slots()
			local list = ctx.Store:Get("profile.Jobs.slots")
			return if type(list) == "table" then list else {}
		end
		local function slotCount(): number
			local s = ctx.Store:Get("session.Jobs")
			if s and type(s.slotCount) == "number" then
				return s.slotCount
			end
			return JobsLogic.SlotCount(function(key)
				return Util.unlocked(ctx, key)
			end)
		end
		local function scoutEggs()
			return JobsLogic.ScoutEggs(function(key)
				return Util.unlocked(ctx, key)
			end)
		end

		-- Actions ---------------------------------------------------------------------------

		local function chooseWorker(index: number, job)
			local statName = StatNames[job.stat] or job.stat
			Util.pick(ctx, {
				title = string.format("Choose a %s (best %s first)", job.name, statName),
				max = 1,
				filter = function(m)
					return (m.stage or 1) >= Rules.MinStage and not m.busy and m.loc ~= "pen"
				end,
				sortBy = function(m)
					return Formulas.Stats(m)[job.stat] or 0
				end,
				returnTo = "Jobs",
				onPick = function(ids)
					Util.requestOnce(ctx, "Jobs.Assign", { slot = index, job = job.id, id = ids[1] })
				end,
			})
		end

		collectAll:SetOnClick(function()
			local ok, res = Util.requestOnce(ctx, "Jobs.Collect")
			if ok and type(res) == "table" and (type(res.rewards) ~= "table" or #res.rewards == 0) then
				ctx:Toast("Nothing to collect yet", "info")
			end
		end)
		buyersButton:SetOnClick(function()
			showBuyers = not showBuyers
			if refresh then
				refresh()
			end
		end)

		-- Cards -----------------------------------------------------------------------------

		local function card(index: number)
			local root = Util.card({
				Name = "Slot" .. index,
				Size = UDim2.new(0.2, -8, 1, 0),
				LayoutOrder = index,
				Parent = row,
			})
			local col = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Parent = root,
			}, { Create.Padding(8, 8, 8, 8), Create.List("y", 6, Enum.HorizontalAlignment.Center) })
			Util.text({
				Text = string.format("Slot %d", index),
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body + 1,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = 1,
				Parent = col,
			})
			return root, col
		end

		local function drawLocked(index: number)
			local root = card(index)
			local key = Rules.SlotUnlocks[index - Rules.BaseSlots] or Rules.Unlock
			Util.lockOverlay(root, Util.unlockText(key))
		end

		local function drawEmpty(index: number)
			local _, col = card(index)
			Util.text({
				Text = "Pick a job",
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = 2,
				Parent = col,
			})
			for i, job in Rules.List do
				Button.new({
					Name = "Job_" .. job.id,
					Text = string.format("%s · %s", job.name, StatNames[job.stat] or job.stat),
					Color = Color3.fromHex(job.color),
					Size = UDim2.new(1, 0, 0, 40),
					TextSize = Theme.TextSize.Small + 1,
					LayoutOrder = 2 + i,
					Parent = col,
					OnClick = function()
						chooseWorker(index, Rules.ById[job.id])
					end,
				})
			end
		end

		local function drawWorking(index: number, slot, m)
			local root, col = card(index)
			local job = Rules.ById[slot.job]
			local chips = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 26),
				LayoutOrder = 2,
				Parent = col,
			}, { Create.List("x", 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
			Widgets.Chip({ Text = job.name, Color = Color3.fromHex(job.color), Parent = chips })
			local ap = Util.appearance(m)
			if ap then
				local icon = MonsterIcon.new(ap, 72)
				icon.LayoutOrder = 3
				icon.Parent = col
			end
			Util.text({
				Text = Formulas.DisplayName(m),
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Small + 1,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = 4,
				Parent = col,
			})
			Util.text({
				Text = string.format("%s: %s", StatNames[job.stat] or job.stat, Format.commas(Formulas.Stats(m)[job.stat] or 0)),
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 18),
				LayoutOrder = 5,
				Parent = col,
			})
			Util.text({
				Text = rateText(job.id, m),
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 34),
				LayoutOrder = 6,
				Parent = col,
			})
			local bar = Widgets.Bar({
				Color = Color3.fromHex(job.color),
				Size = UDim2.new(1, 0, 0, 14),
				LayoutOrder = 7,
				Parent = col,
			})
			bar.Root.Visible = job.collects
			local stored = Util.text({
				Name = "Stored",
				Text = "",
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 18),
				LayoutOrder = 8,
				Parent = col,
			})
			if job.id == "forager" then
				local flavor = Config.Food.ById[slot.flavor] or Config.Food.List[1]
				Button.new({
					Name = "Flavor",
					Text = flavor.name,
					Color = Theme.Food(flavor.id),
					Size = UDim2.new(1, 0, 0, 34),
					TextSize = Theme.TextSize.Small,
					LayoutOrder = 9,
					Parent = col,
					OnClick = function()
						local ids = Config.Food.Ids
						local at = table.find(ids, flavor.id) or 0
						Util.requestOnce(ctx, "Jobs.SetFlavor", { slot = index, flavor = ids[at % #ids + 1] })
					end,
				})
			end
			Button.new({
				Name = "Recall",
				Text = "Recall",
				Color = C.Red,
				Size = UDim2.new(1, -16, 0, 40),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				TextSize = Theme.TextSize.Body,
				Parent = root,
				OnClick = function()
					Util.requestOnce(ctx, "Jobs.Recall", { slot = index })
				end,
			})
			table.insert(tickers, function(now: number)
				local pending = JobsLogic.Pending(slot, m, now, scoutEggs())
				local full = JobsLogic.IsFull(slot, now)
				stored.Text = storedText(job.id, pending, full)
				if job.collects then
					bar:SetValue(JobsLogic.Elapsed(slot, now) / (Rules.MaxHours * HOUR), false)
				end
			end)
		end

		local function tick()
			local now = ctx:Now()
			for _, fn in tickers do
				fn(now)
			end
		end

		-- Orders (3.8) -------------------------------------------------------------------------

		local function orders()
			local p = ctx.Store:Get("profile.Orders")
			return if type(p) == "table" then p else {}
		end

		local function repPoints()
			local rep = orders().rep
			return if type(rep) == "table" then rep else {}
		end

		-- The order's buyer's reputation level (3.9).
		local function buyerLevel(order): number
			return OrdersLogic.RepLevel(repPoints()[OrdersLogic.BuyerId(order)])
		end

		-- A monster the picker may offer for `order`.
		local function eligible(order, m): boolean
			return type(m) == "table" and not m.busy and not m.locked and OrdersLogic.Qualifies(order, m)
		end

		local function confirmHandOver(index: number, id: string, level: number)
			local m = Util.monsters(ctx)[id]
			if not m then
				return
			end
			Dialog.confirm(ctx.UI.Top, {
				Title = "Hand over this monster?",
				Text = string.format(
					"%s leaves your ranch for good. The buyer pays %s coins.",
					Formulas.DisplayName(m),
					Format.commas(OrdersLogic.Coins(m, level))
				),
				ConfirmText = "Hand over",
				ConfirmColor = C.Orange,
				OnConfirm = function()
					Util.requestOnce(ctx, "Orders.Fill", { index = index, id = id })
				end,
			})
		end

		local function chooseFor(index: number, order)
			local count = 0
			for _, m in Util.monsters(ctx) do
				if eligible(order, m) then
					count += 1
				end
			end
			if count == 0 then
				ctx:Toast("None of your free Teens or Adults meet this order yet", "info")
				return
			end
			Util.pick(ctx, {
				title = "Choose a monster for this order (cheapest first)",
				max = 1,
				filter = function(m)
					return eligible(order, m)
				end,
				-- The picker sorts highest first: the cheapest monster that qualifies leads.
				sortBy = function(m)
					return -Formulas.SellPrice(m)
				end,
				returnTo = "Jobs",
				returnParams = { tab = "orders" },
				onPick = function(ids)
					confirmHandOver(index, ids[1], buyerLevel(order))
				end,
			})
		end

		local function drawOrder(index: number, order, rerollsLeft: number, count: number)
			local level = buyerLevel(order)
			local root = Util.card({
				Name = "Order" .. index,
				Size = UDim2.new(1 / count, -(10 * (count - 1)) / count, 1, 0),
				LayoutOrder = index,
				Parent = ordersRow,
			})
			local col = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, -56),
				Parent = root,
			}, { Create.Padding(10, 10, 10, 10), Create.List("y", 6, Enum.HorizontalAlignment.Center) })
			Util.text({
				Text = OrdersLogic.Buyer(order),
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body + 1,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = 1,
				Parent = col,
			})
			local d = OrderRules.Difficulty[order.difficulty] or OrderRules.Difficulty.easy
			local chips = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 26),
				LayoutOrder = 2,
				Parent = col,
			}, { Create.List("x", 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
			Widgets.Chip({ Text = d.name, Color = Color3.fromHex(d.color), Parent = chips })
			Widgets.Chip({ Name = "BuyerLevel", Text = string.format("Level %d", level), Color = C.Purple, LayoutOrder = 2, Parent = chips })
			if order.favourite then
				Widgets.Chip({ Name = "Favourite", Text = "Favourite", Color = C.Gold, LayoutOrder = 3, Parent = chips })
			end
			Util.text({
				Name = "Requirement",
				Text = OrdersLogic.RequirementText(order),
				TextSize = Theme.TextSize.Body,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 48),
				LayoutOrder = 3,
				Parent = col,
			})
			local hint
			if order.kind == "goods" then
				local food = ctx.Store:Get("profile.Currency.food")
				local have = if type(food) == "table" then food[order.food] or 0 else 0
				hint = string.format("You have %s", Format.commas(math.floor(have)))
			else
				local n = 0
				for _, m in Util.monsters(ctx) do
					if eligible(order, m) then
						n += 1
					end
				end
				hint = string.format("Monsters that qualify: %d", n)
			end
			Util.text({
				Text = hint,
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = 4,
				Parent = col,
			})
			local base, egg = {}, nil
			for _, item in OrdersLogic.Pay(order) do
				if item.kind == "egg" then
					egg = item
				else
					table.insert(base, item)
				end
			end
			Util.rewardRow(base, col, { LayoutOrder = 5, Align = Enum.HorizontalAlignment.Center })
			if order.kind == "monster" then
				local bonus = math.floor(OrdersLogic.CoinBonus(level) * 100 + 0.5)
				Util.text({
					Name = "Coins",
					Text = if bonus > 0
						then string.format("Plus coins: %d times its sell price +%d%%", OrderRules.CoinMult, bonus)
						else string.format("Plus coins: %d times its sell price", OrderRules.CoinMult),
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, 0, 0, 20),
					LayoutOrder = 6,
					Parent = col,
				})
			end
			if egg then
				local eggRow = Util.rewardRow({ egg }, col, { LayoutOrder = 7, Align = Enum.HorizontalAlignment.Center })
				eggRow.Name = "Egg"
			end

			if order.filled then
				Util.text({
					Name = "Filled",
					Text = "Order filled",
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body + 1,
					TextColor3 = C.Green,
					TextXAlignment = Enum.TextXAlignment.Center,
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -14),
					Size = UDim2.new(1, -16, 0, 30),
					Parent = root,
				})
				return
			end
			local hasReroll = rerollsLeft > 0
			if hasReroll then
				Button.new({
					Name = "Reroll",
					Text = "Reroll",
					Color = C.Gray,
					Size = UDim2.new(0.38, -8, 0, 44),
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 8, 1, -8),
					TextSize = Theme.TextSize.Small + 1,
					Parent = root,
					OnClick = function()
						Util.requestOnce(ctx, "Orders.Reroll", { index = index })
					end,
				})
			end
			Button.new({
				Name = "Fill",
				Text = if order.kind == "goods" then "Hand over" else "Choose monster",
				Color = C.Green,
				Size = if hasReroll then UDim2.new(0.62, -12, 0, 44) else UDim2.new(1, -16, 0, 44),
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -8, 1, -8),
				TextSize = Theme.TextSize.Body,
				Parent = root,
				OnClick = function()
					if order.kind == "goods" then
						Util.requestOnce(ctx, "Orders.Fill", { index = index })
					else
						chooseFor(index, order)
					end
				end,
			})
		end

		-- 3.9: the Buyers panel, 4 x 2 cards: name, level, a bar to the next level, the next perk.
		local function drawBuyers()
			Util.clear(buyersView)
			local rep = repPoints()
			local ids = OrderRules.BuyerIds
			local cols = 4
			local rows = math.ceil(#ids / cols)
			for i, id in ids do
				local b = OrderRules.BuyerById[id]
				local points = math.floor(tonumber(rep[id]) or 0)
				local level, from, to = OrdersLogic.RepProgress(points)
				local root = Util.card({
					Name = "Buyer_" .. id,
					Size = UDim2.new(1 / cols, -8, 1 / rows, -8),
					Position = UDim2.new(((i - 1) % cols) / cols, 4, math.floor((i - 1) / cols) / rows, 4),
					Parent = buyersView,
				})
				local col = New("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Parent = root,
				}, { Create.Padding(8, 10, 8, 10), Create.List("y", 4, Enum.HorizontalAlignment.Center) })
				Util.text({
					Name = "BuyerName",
					Text = b.name,
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, 0, 0, 24),
					LayoutOrder = 1,
					Parent = col,
				})
				Util.text({
					Name = "Level",
					Text = string.format("Level %d", level),
					TextColor3 = C.Purple,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, 0, 0, 20),
					LayoutOrder = 2,
					Parent = col,
				})
				Widgets.Bar({
					Name = "RepBar",
					Value = if to then (points - from) / (to - from) else 1,
					Text = if to then string.format("%d / %d", points, to) else "Max level",
					Color = C.Purple,
					Size = UDim2.new(1, 0, 0, 20),
					LayoutOrder = 3,
					Parent = col,
				})
				local perk = OrderRules.Rep.Perks[level + 1]
				Util.text({
					Name = "NextPerk",
					Text = if perk then string.format("Level %d: %s", level + 1, perk) else "All perks earned",
					TextColor3 = C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Top,
					Size = UDim2.new(1, 0, 1, -76),
					LayoutOrder = 4,
					Parent = col,
				})
			end
		end

		local function drawOrders()
			Util.clear(ordersRow)
			Util.clear(buyersView)
			if ordersLock then
				ordersLock:Destroy()
				ordersLock = nil
			end
			local unlocked = Util.unlocked(ctx, OrderRules.Unlock)
			buyersButton:SetVisible(unlocked)
			buyersButton:SetText(if showBuyers then "Show orders" else "Buyers")
			ordersRow.Visible = not (unlocked and showBuyers)
			buyersView.Visible = unlocked and showBuyers
			if not unlocked then
				ordersLock = Util.lockOverlay(ordersView, Util.unlockText(OrderRules.Unlock))
				return
			end
			if showBuyers then
				drawBuyers()
				return
			end
			local p = orders()
			local list = if type(p.list) == "table" then p.list else {}
			local left = math.max(0, OrderRules.RerollsPerDay - (tonumber(p.rerolls) or 0))
			-- PerDay orders, plus the favourite buyer order when one was posted (3.9).
			local shown = {}
			for index = 1, OrderRules.PerDay + 1 do
				if type(list[index]) == "table" then
					table.insert(shown, index)
				end
			end
			for _, index in shown do
				-- The favourite order can't be rerolled.
				drawOrder(index, list[index], if index <= OrderRules.PerDay then left else 0, #shown)
			end
		end

		local function draw()
			if not isOpen then
				return
			end
			local onJobs = tab ~= "orders"
			jobsView.Visible = onJobs
			jobsIntro.Visible = onJobs
			collectAll.Root.Visible = onJobs
			if onJobs then
				buyersButton:SetVisible(false)
			end
			ordersView.Visible = not onJobs
			ordersIntro.Visible = not onJobs
			if not onJobs then
				table.clear(tickers)
				drawOrders()
				return
			end
			Util.clear(row)
			table.clear(tickers)
			if lockOverlay then
				lockOverlay:Destroy()
				lockOverlay = nil
			end
			local list = Util.monsters(ctx)
			local open = slotCount()
			local current = slots()
			for index = 1, Rules.MaxSlots do
				local slot = current[index]
				local m = type(slot) == "table" and slot.job and slot.monster and list[slot.monster]
				if index > open then
					drawLocked(index)
				elseif m then
					drawWorking(index, slot, m)
				else
					drawEmpty(index)
				end
			end
			tick()
			if not Util.unlocked(ctx, Rules.Unlock) then
				lockOverlay = Util.lockOverlay(jobsView, Util.unlockText(Rules.Unlock))
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function(params)
				isOpen = true
				showBuyers = false
				bag.clean()
				for _, path in
					{
						"profile.Jobs",
						"session.Jobs",
						"profile.Monsters.list",
						"profile.Progression.level",
						"profile.Orders",
						"profile.Currency.food",
					}
				do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				if type(params) == "table" and (params.tab == "jobs" or params.tab == "orders") and params.tab ~= tab then
					tabs:Select(params.tab)
				end
				refresh()
				task.spawn(function()
					while isOpen do
						task.wait(1)
						if isOpen then
							tick()
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
