--[[
	Spa (update 3.13 · Wild things): the Hot Springs screen. Opened by the "Soak" prompt at the
	pools (Controllers/Spa). No HUD button.

	  Left    one card per pool: locked ("Unlocks at Ranch Level 45"), empty (a button per soak:
	          Monsters pick mode with the free Teens and Adults in the barn -> Spa.Soak; a Warm
	          Soak only lists monsters that still grow) or soaking: the monster, the soak, the
	          time left, Collect when done (Spa.Collect) and Stop (Spa.Cancel, the salt is lost).
	  Right   the bath salts: each soak with its time, effect, cost and the honey and food the
	          player has (or "Needs the Apiary" without it), then the active buffs with their
	          time left.

	Reads: profile.Spa, session.Spa, profile.Apiary.store, profile.Currency.food,
	profile.Monsters.list, profile.Progression.level (all tolerated nil).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local Logic = require(Shared.Logic.Spa)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Rules = Config.Spa

local SIDE_W = 330

return {
	Name = "Spa",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Hot Springs",
			Color = C.Blue,
			Size = UDim2.fromOffset(1040, 540),
			OnClose = function()
				ctx.Router:Close("Spa")
			end,
		})

		local isOpen = false
		local bag = Util.bag()
		local refresh
		local tickers = {} -- fn() per soaking pool and buff row
		local lock = nil

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

		local function spa()
			local s = ctx.Store:Get("profile.Spa")
			return if type(s) == "table" then s else {}
		end
		local function session()
			local s = ctx.Store:Get("session.Spa")
			return if type(s) == "table" then s else {}
		end
		local function poolCount(): number
			local s = session()
			if type(s.pools) == "number" then
				return s.pools
			end
			return Logic.PoolCount(function(key)
				return Util.unlocked(ctx, key)
			end)
		end
		local function hasApiary(): boolean
			return session().apiary == true
		end
		local function honeyHave(): number
			local store = ctx.Store:Get("profile.Apiary.store")
			local n = 0
			for _, kind in Config.Apiary.Ids do
				n += if type(store) == "table" then tonumber(store[kind]) or 0 else 0
			end
			return n
		end
		local function foodHave(flavour: string): number
			local food = ctx.Store:Get("profile.Currency.food")
			return if type(food) == "table" then tonumber(food[flavour]) or 0 else 0
		end
		local function canPay(def): boolean
			return hasApiary() and honeyHave() >= def.honey and foodHave(def.food) >= def.foodAmount
		end

		-- Actions ---------------------------------------------------------------------------

		local function chooseMonster(index: number, def)
			Util.pick(ctx, {
				title = string.format("Choose a monster for the %s", def.name),
				max = 1,
				filter = function(m)
					return not m.busy and m.loc ~= "pen" and (Logic.CanTake(m, def.id))
				end,
				sortBy = function(m)
					return m.lv or 1
				end,
				returnTo = "Spa",
				onPick = function(ids)
					local ok = Util.requestOnce(ctx, "Spa.Soak", { pool = index, id = ids[1], soak = def.id })
					if ok then
						ctx:Sound("CoinCollect")
					end
				end,
			})
		end

		-- Pools -------------------------------------------------------------------------------

		local function drawPool(parent: Instance, index: number)
			local card = Util.card({
				Name = "Pool" .. index,
				Size = UDim2.new(1 / Rules.MaxPools, -6, 1, 0),
				LayoutOrder = index,
				Parent = parent,
			})
			Util.text({
				Text = string.format("Pool %d", index),
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(12, 8),
				Size = UDim2.new(1, -24, 0, 28),
				Parent = card,
			})
			if index > poolCount() then
				Util.lockOverlay(card, Util.unlockText(Rules.PoolUnlocks[index]))
				return
			end
			local pools = spa().pools
			local pool = type(pools) == "table" and pools[index] or nil
			local m = type(pool) == "table" and pool.monster and Util.monsters(ctx)[pool.monster] or nil
			if not m then
				Util.text({
					Name = "Empty",
					Text = "Free pool. Pick a soak, then a Teen or Adult resting in the barn.",
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					TextSize = Theme.TextSize.Small,
					Position = UDim2.fromOffset(12, 40),
					Size = UDim2.new(1, -24, 0, 60),
					Parent = card,
				})
				local list = New("Frame", {
					Name = "Soaks",
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 12, 1, -12),
					Size = UDim2.new(1, -24, 0, 3 * 44 + 2 * 6),
					Parent = card,
				}, { Create.List("y", 6) })
				for i, def in Rules.Soaks do
					local b = Button.new({
						Name = "Soak_" .. def.id,
						Text = def.name,
						Color = Color3.fromHex(def.color),
						Size = UDim2.new(1, 0, 0, 44),
						LayoutOrder = i,
						TextSize = Theme.TextSize.Small + 1,
						Parent = list,
						OnClick = function()
							chooseMonster(index, def)
						end,
					})
					b:SetDisabled(not canPay(def))
				end
				return
			end
			local def = Rules.ById[pool.soak]
			local name = Util.text({
				Name = "Monster",
				Text = Formulas.DisplayName(m),
				TextSize = Theme.TextSize.Small + 1,
				Position = UDim2.fromOffset(12, 40),
				Size = UDim2.new(1, -24, 0, 24),
				Parent = card,
			})
			name:SetAttribute("Localize", false)
			Util.text({
				Name = "SoakName",
				Text = if def then def.name else "Soak",
				TextSize = Theme.TextSize.Small,
				Position = UDim2.fromOffset(12, 66),
				Size = UDim2.new(1, -24, 0, 22),
				Parent = card,
			})
			local left = Util.text({
				Name = "TimeLeft",
				Text = "",
				TextSize = Theme.TextSize.Small,
				Position = UDim2.fromOffset(12, 92),
				Size = UDim2.new(1, -24, 0, 22),
				Parent = card,
			})
			local collectBtn = Button.new({
				Name = "Collect",
				Text = "Collect",
				Color = C.Green,
				Size = UDim2.new(1, -24, 0, 44),
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 12, 1, -62),
				TextSize = Theme.TextSize.Small + 1,
				Parent = card,
				OnClick = function()
					local ok = Util.requestOnce(ctx, "Spa.Collect", { pool = index })
					if ok then
						ctx:Sound("CoinCollect")
					end
				end,
			})
			Button.new({
				Name = "Stop",
				Text = "Stop soak",
				Color = C.Purple,
				Size = UDim2.new(1, -24, 0, 44),
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 12, 1, -12),
				TextSize = Theme.TextSize.Small + 1,
				Parent = card,
				OnClick = function()
					Util.requestOnce(ctx, "Spa.Cancel", { pool = index })
				end,
			})
			local function tick()
				local secs = Logic.Left(pool, ctx:Now())
				if secs <= 0 then
					left.Text = "Done · collect it!"
					left.TextColor3 = C.Green
				else
					left.Text = string.format("Done in %s", Format.duration(secs))
					left.TextColor3 = C.TextMuted
				end
				collectBtn:SetDisabled(secs > 0)
			end
			tick()
			table.insert(tickers, tick)
		end

		-- Salts and buffs -----------------------------------------------------------------------

		local function drawSide(parent: Instance)
			local col = Util.card({
				Name = "Salts",
				Size = UDim2.new(0, SIDE_W, 1, 0),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Parent = parent,
			})
			local list = New("Frame", {
				Name = "List",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(10, 8),
				Size = UDim2.new(1, -20, 1, -16),
				Parent = col,
			}, { Create.List("y", 4) })
			Util.text({
				Text = "Bath salts",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				Size = UDim2.new(1, 0, 0, 26),
				LayoutOrder = 0,
				Parent = list,
			})
			local order = 1
			local honey = honeyHave()
			for _, def in Rules.Soaks do
				local row = New("Frame", {
					Name = "Salt_" .. def.id,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 62),
					LayoutOrder = order,
					Parent = list,
				})
				order += 1
				Util.text({
					Text = string.format("%s · %s", def.name, Format.duration(Logic.Seconds(def.id))),
					TextSize = Theme.TextSize.Small,
					TextColor3 = Color3.fromHex(def.color),
					Size = UDim2.new(1, 0, 0, 20),
					Parent = row,
				})
				Util.text({
					Text = def.desc,
					TextSize = Theme.TextSize.Small - 2,
					TextColor3 = C.TextMuted,
					Position = UDim2.fromOffset(0, 20),
					Size = UDim2.new(1, 0, 0, 20),
					Parent = row,
				})
				local food = Config.Food.ById[def.food]
				Util.text({
					Name = "Cost",
					Text = if hasApiary()
						then string.format(
							"%d honey (have %d) · %d %s (have %d)",
							def.honey,
							honey,
							def.foodAmount,
							if food then food.name else def.food,
							foodHave(def.food)
						)
						else "Needs the Apiary",
					TextSize = Theme.TextSize.Small - 2,
					TextWrapped = true,
					TextColor3 = if canPay(def) then C.Text else C.Red,
					Position = UDim2.fromOffset(0, 40),
					Size = UDim2.new(1, 0, 0, 22),
					Parent = row,
				})
			end
			Util.text({
				Text = "Active buffs",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				Size = UDim2.new(1, 0, 0, 26),
				LayoutOrder = order,
				Parent = list,
			})
			order += 1
			local now = ctx:Now()
			local buffs = spa().buffs
			local monsters = Util.monsters(ctx)
			local ids = {}
			for id, buff in (if type(buffs) == "table" then buffs else {}) do
				if Logic.Active(buff, now) and monsters[id] then
					table.insert(ids, id)
				end
			end
			table.sort(ids, function(a, b)
				return buffs[a].endsAt < buffs[b].endsAt
			end)
			if #ids == 0 then
				Util.text({
					Name = "NoBuffs",
					Text = "No monster is relaxed right now.",
					TextSize = Theme.TextSize.Small - 2,
					TextColor3 = C.TextMuted,
					Size = UDim2.new(1, 0, 0, 20),
					LayoutOrder = order,
					Parent = list,
				})
			end
			for _, id in ids do
				local buff = buffs[id]
				local def = Rules.ById[buff.soak]
				local row = Util.text({
					Name = "Buff_" .. id,
					Text = "",
					TextSize = Theme.TextSize.Small - 2,
					TextWrapped = true,
					Size = UDim2.new(1, 0, 0, 20),
					LayoutOrder = order,
					Parent = list,
				})
				order += 1
				local who = Formulas.DisplayName(monsters[id])
				local function tick()
					local secs = math.max(0, (tonumber(buff.endsAt) or 0) - ctx:Now())
					row.Text = string.format("%s · %s · %s left", who, def.name, Format.duration(secs))
				end
				tick()
				table.insert(tickers, tick)
			end
		end

		-- Draw ------------------------------------------------------------------------------

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
			intro.Text = string.format(
				"A soak costs a bath salt of honey and food. Collect a finished soak and the monster keeps its buff for %d hours.",
				Rules.BuffHours
			)
			local row = New("Frame", {
				Name = "Pools",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -(SIDE_W + 10), 1, 0),
				Parent = view,
			}, { Create.List("x", 8) })
			for index = 1, Rules.MaxPools do
				drawPool(row, index)
			end
			drawSide(view)
			if not Util.unlocked(ctx, Rules.Unlock) then
				lock = Util.lockOverlay(view, Util.unlockText(Rules.Unlock))
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				bag.clean()
				for _, path in
					{
						"profile.Spa",
						"session.Spa",
						"profile.Apiary.store",
						"profile.Currency.food",
						"profile.Monsters.list",
						"profile.Progression.level",
					}
				do
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
