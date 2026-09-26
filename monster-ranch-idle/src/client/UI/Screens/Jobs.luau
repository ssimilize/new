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

	Reads: profile.Jobs.slots, session.Jobs.slotCount, profile.Monsters.list,
	profile.Progression.level (all tolerated nil).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local JobsLogic = require(Shared.Logic.Jobs)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Rules = Config.Jobs
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

		local collectAll = Button.new({
			Name = "CollectAll",
			Text = "Collect all",
			Color = C.Green,
			Size = UDim2.fromOffset(170, 44),
			TextSize = Theme.TextSize.Body,
			LayoutOrder = 1,
			Parent = panel.HeaderRight,
		})

		Util.text({
			Text = string.format("Teens and Adults resting in the barn can work. Workers store up to %d hours.", Rules.MaxHours),
			TextColor3 = C.TextMuted,
			Size = UDim2.new(1, 0, 0, 22),
			Parent = panel.Body,
		})
		local row = New("Frame", {
			Name = "Slots",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, 0, 1, -30),
			Parent = panel.Body,
		}, { Create.List("x", 10) })

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

		local function draw()
			if not isOpen then
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
				lockOverlay = Util.lockOverlay(panel.Body, Util.unlockText(Rules.Unlock))
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				bag.clean()
				for _, path in { "profile.Jobs", "session.Jobs", "profile.Monsters.list", "profile.Progression.level" } do
					bag.add(ctx.Store:Observe(path, refresh))
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
