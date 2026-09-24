--[[
	Ranch (S3): pens, coin jars, ranch upgrades (pen capacity, jar tier, incubator speed,
	barn), decor and pen themes, and the Feed Garden.

	Save section (profile.Ranch):
	  pens          = { [1..owned] = { capacity, jarTier, jar, jarAt, monsters = { id }, decor = { decorId }, theme } }
	  incubatorTier = number                 -- Economy.Incubators.speedTiers index
	  barnTier      = number                 -- Economy.Barn index
	  garden        = { tier, plots = { [1..n] = { flavor = string|false, readyAt } } }
	  offline       = { rates = { n }, caps = { n } }   -- PRIVATE: jar rates at the last save
	Session (session.Ranch): { income, rates = { [pen] = coins/s }, caps = { [pen] = seconds }, capacity, used }

	Coin jars (see Logic/Jar): a pen's jar shows min(jar + rate × (now − jarAt), rate × cap).
	Whenever a rate or cap is about to change the jar is "settled" with the OLD rate (jar +=
	accrual, jarAt = now), then the new rate is stored. Settling also happens every
	Economy.RanchTickSeconds and before every save. The rates in effect when the player left
	are saved privately, so offline income never depends on which systems (passes, friends)
	have loaded when the player comes back.

	Rate of a pen = Σ Formulas.CoinRate(m) × (1 + Σ rate modifiers(player, elements of m))
	                × (Double Coins pass ? Economy.DoubleCoinsMult : 1)      (busy monsters: 0)
	Jar cap (s)   = JarTiers[jarTier] + VIP bonus + Hoarder minutes × 60 of the pen's monsters
	                + Σ jar-bonus providers

	Public API (other systems):
	  Ranch:IncomePerSecond(player) -> coins/s
	  Ranch:PenOf(player, monsterId) -> 0..5                  -- 0 = barn
	  Ranch:MonstersInPens(player) -> { { id, pen } }
	  Ranch:CollectAll(player, multiplier?) -> coins          -- pays every jar (× multiplier)
	  Ranch:JarTotal(player) -> coins                         -- what CollectAll would pay (×1)
	  Ranch:RegisterRateModifier(key, fn(player, elements) -> additive pct)
	  Ranch:RegisterJarBonus(key, fn(player) -> seconds)
	  Ranch:PublicPens(player) -> { { theme, decor = { decorId }, monsters = { id } } }
	  Ranch:Refresh(player)                                   -- recompute after an input changed
	  Ranch:HoldAutoCollect(player, hold)                     -- WelcomeBack keeps jars for its claim

	Registers the Monsters capacity provider (barn + pens + Big Barn pass) and the Eggs speed
	provider "incubator". Takes monsters out of pens when they become busy or are removed,
	and puts newly hatched/bred/rewarded monsters into the first pen with room.
	Publishes JarCollected, RanchXP (collectJar), PenChanged, PlotChanged.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local Jar = require(Shared.Logic.Jar)
local TableUtil = require(Shared.Logic.TableUtil)

local Ranch = {
	Name = "Ranch",
	Dependencies = { "Currency", "Progression", "Monsters" },
	OptionalDependencies = { "Eggs", "Shop", "Monetization", "Weather" },
}

local ctx
local Config, Economy
local Currency, Progression, Monsters

local rateModifiers = {} -- [key] = fn(player, elements) -> pct
local jarBonuses = {} -- [key] = fn(player) -> seconds
local joined = {} -- [player] = true once PlayerAdded finished (offline accrual applied)
local quiet = {} -- [player] = true while a batch of monster changes is applied
local holdAuto = {} -- [player] = true while WelcomeBack is waiting for its claim
local returnTo = {} -- [player] = { [monsterId] = pen } monsters that left a pen to go busy

local AUTO_PLACE = { hatch = true, starter = true, breed = true, reward = true }
-- Capacity reported when this Ranch has no data for the player (profile not loaded here):
-- Monsters' own default, so Ranch never constrains a profile it doesn't manage.
local UNLOADED_CAPACITY = 60

-- Economy is bound in Init; profiles (and so Default) are only built after Init.
local function newPen(now: number)
	return {
		capacity = Economy.Pens.startCapacity,
		jarTier = 1,
		jar = 0,
		jarAt = now,
		monsters = {},
		decor = {},
		theme = Economy.StartTheme,
	}
end

local function plots(n: number)
	local list = {}
	for i = 1, n do
		list[i] = { flavor = false, readyAt = 0 }
	end
	return list
end

Ranch.Profile = {
	Version = 1,
	Default = function()
		return {
			pens = { newPen(0) },
			incubatorTier = 1,
			barnTier = 1,
			garden = { tier = 1, plots = plots(Economy.Garden.plots[1]) },
			offline = { rates = {}, caps = {} },
		}
	end,
	Private = { "offline" },
}

-- Helpers ------------------------------------------------------------------------------

local function section(player)
	return ctx:Section(player)
end

local function hasPass(player, key: string): boolean
	local M = ctx:GetSystem("Monetization")
	if not M then
		return false
	end
	local ok, result = pcall(M.HasPass, M, player, key)
	return ok and result == true
end

local function penOf(s, id: string): number
	for i, pen in s.pens do
		if table.find(pen.monsters, id) then
			return i
		end
	end
	return 0
end

local function ownedPen(player, index: number?)
	if not index then
		ctx:Fail("Choose a pen")
	end
	local pen = section(player).pens[index :: number]
	if not pen then
		ctx:Fail("You don't own that pen yet")
	end
	return pen
end

local function charge(player, coins: number, reason: string)
	if coins > 0 then
		Currency:Charge(player, { coins = coins }, reason)
	end
end

local function numberFrom(fn, ...): number
	local ok, value = pcall(fn, ...)
	if ok and type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return 0
end

local function modifierPct(player, elements: { string }, cache): number
	local key = table.concat(elements, ",")
	local cached = cache[key]
	if cached == nil then
		cached = 0
		for _, fn in rateModifiers do
			cached += numberFrom(fn, player, elements)
		end
		cache[key] = cached
	end
	return cached
end

-- Current rate and cap of every pen, from scratch.
local function compute(player): ({ number }, { number })
	local s = section(player)
	local mult = if hasPass(player, "doubleCoins") then Economy.DoubleCoinsMult else 1
	local vip = hasPass(player, "vip")
	local bonus = 0
	for _, fn in jarBonuses do
		bonus += numberFrom(fn, player)
	end
	local cache = {}
	local rates, caps = {}, {}
	for i, pen in s.pens do
		local rate, hoarder = 0, 0
		for _, id in pen.monsters do
			local m = Monsters:Get(player, id)
			if m and not m.busy then
				rate += Jar.MonsterRate(Formulas.CoinRate(m), modifierPct(player, Formulas.Elements(m), cache), mult)
				hoarder += Config.Traits.Sum(Formulas.ActiveTraits(m), "jarCapMinutes")
			end
		end
		rates[i] = rate
		caps[i] = Jar.CapSeconds(pen.jarTier, { vip = vip, hoarderMinutes = hoarder, bonusSeconds = bonus })
	end
	return rates, caps
end

-- Settles every jar with the rates in effect until now, then stores the new rates.
-- Replicates the pens only when a rate or cap changed (settling alone does not change what
-- the client's live-jar formula shows).
local function refresh(player)
	if not joined[player] then
		return
	end
	local s = section(player)
	local sess = ctx:Session(player)
	if not s or not sess then
		return
	end
	local now = ctx:Now()
	local oldRates, oldCaps = sess.rates or {}, sess.caps or {}
	for i, pen in s.pens do
		Jar.Settle(pen, oldRates[i] or 0, oldCaps[i] or 0, now)
	end
	local rates, caps = compute(player)
	local changed = not TableUtil.equal(rates, oldRates) or not TableUtil.equal(caps, oldCaps)
	local income = 0
	for _, r in rates do
		income += r
	end
	local capacity, used = Monsters:Capacity(player), Monsters:Count(player)
	if changed or sess.capacity ~= capacity or sess.used ~= used then
		sess.rates, sess.caps, sess.income = rates, caps, income
		sess.capacity, sess.used = capacity, used
		ctx:DirtySession(player)
	end
	if changed then
		ctx:Dirty(player, "pens")
	end
end

local function penChanged(player, index: number)
	ctx:Dirty(player, "pens")
	if index > 0 then
		ctx.Bus:Publish("PenChanged", player, { pen = index })
	end
	ctx.Bus:Publish("PlotChanged", player, {})
end

local function putInPen(player, s, id: string, index: number)
	table.insert(s.pens[index].monsters, id)
	Monsters:SetLocation(player, id, "pen", index)
end

local function takeOut(player, s, id: string): number
	local from = penOf(s, id)
	if from > 0 then
		TableUtil.removeValue(s.pens[from].monsters, id)
		local m = Monsters:Get(player, id)
		if m then
			Monsters:SetLocation(player, id, "barn", 0)
		end
	end
	return from
end

local function firstPenWithRoom(s): number
	for i, pen in s.pens do
		if #pen.monsters < pen.capacity then
			return i
		end
	end
	return 0
end

-- Pays whole coins out of jars. Returns the coins added (after the multiplier).
local function collect(player, pens: { number }, multiplier: number, opts: { xp: boolean, pen: number? }): number
	refresh(player)
	local s = section(player)
	local total = 0
	for _, i in pens do
		local pen = s.pens[i]
		local whole, rest = Jar.Collectable(pen.jar)
		if whole > 0 then
			pen.jar = rest
			total += whole
		end
	end
	if total <= 0 then
		return 0
	end
	ctx:Dirty(player, "pens")
	local coins = math.floor(total * math.max(0, multiplier))
	Currency:Add(player, "coins", coins, "jar")
	ctx.Bus:Publish("JarCollected", player, { coins = coins, pen = opts.pen })
	if opts.xp then
		ctx.Bus:Publish("RanchXP", player, { amount = Config.Unlocks.XP.collectJar, reason = "collectJar" })
	end
	return coins
end

local function allPens(s): { number }
	local list = {}
	for i in s.pens do
		table.insert(list, i)
	end
	return list
end

-- Brings a player's pens in line with the monster records (after offline trades, breeding,
-- expeditions or manual data fixes).
local function reconcilePens(player, s)
	local seen = {}
	for i, pen in s.pens do
		pen.capacity = pen.capacity or Economy.Pens.startCapacity
		pen.jarTier = pen.jarTier or 1
		pen.jar = pen.jar or 0
		pen.jarAt = pen.jarAt or 0
		pen.monsters = pen.monsters or {}
		pen.decor = pen.decor or {}
		pen.theme = pen.theme or Economy.StartTheme
		local keep = {}
		for _, id in pen.monsters do
			local m = Monsters:Get(player, id)
			if m and not m.busy and not seen[id] and #keep < pen.capacity then
				seen[id] = true
				table.insert(keep, id)
				if m.loc ~= "pen" or m.pen ~= i then
					Monsters:SetLocation(player, id, "pen", i)
				end
			end
		end
		pen.monsters = keep
	end
	for id, m in Monsters:All(player) do
		if not seen[id] and (m.loc ~= "barn" or (m.pen or 0) ~= 0) then
			Monsters:SetLocation(player, id, "barn", 0)
		end
	end
end

-- Public API ------------------------------------------------------------------------------

function Ranch:RegisterRateModifier(key: string, fn)
	rateModifiers[key] = fn
	for _, player in ctx:Players() do
		refresh(player)
	end
end

function Ranch:RegisterJarBonus(key: string, fn)
	jarBonuses[key] = fn
	for _, player in ctx:Players() do
		refresh(player)
	end
end

function Ranch:Refresh(player)
	refresh(player)
end

function Ranch:IncomePerSecond(player): number
	local sess = ctx:Session(player)
	if sess and sess.income and joined[player] then
		return sess.income
	end
	if not section(player) then
		return 0
	end
	local rates = compute(player)
	local total = 0
	for _, r in rates do
		total += r
	end
	return total
end

function Ranch:PenOf(player, monsterId: string): number
	local s = section(player)
	return if s then penOf(s, monsterId) else 0
end

function Ranch:MonstersInPens(player): { { id: string, pen: number } }
	local out = {}
	local s = section(player)
	if not s then
		return out
	end
	for i, pen in s.pens do
		for _, id in pen.monsters do
			table.insert(out, { id = id, pen = i })
		end
	end
	return out
end

function Ranch:JarTotal(player): number
	local s = section(player)
	local sess = ctx:Session(player)
	if not s or not sess then
		return 0
	end
	local now = ctx:Now()
	local rates, caps = sess.rates or {}, sess.caps or {}
	local total = 0
	for i, pen in s.pens do
		total += math.floor(Jar.Value(pen.jar, rates[i] or 0, pen.jarAt, now, caps[i] or 0))
	end
	return total
end

function Ranch:CollectAll(player, multiplier: number?): number
	local s = section(player)
	if not s or not joined[player] then
		return 0
	end
	return collect(player, allPens(s), multiplier or 1, { xp = true })
end

function Ranch:PublicPens(player)
	local out = {}
	local s = section(player)
	if not s then
		return out
	end
	for _, pen in s.pens do
		table.insert(out, { theme = pen.theme, decor = table.clone(pen.decor), monsters = table.clone(pen.monsters) })
	end
	return out
end

function Ranch:HoldAutoCollect(player, hold: boolean)
	holdAuto[player] = if hold then true else nil
end

-- Bus reactions ---------------------------------------------------------------------------

local function onMonsterCreated(player, detail)
	if not joined[player] then
		return
	end
	local s = section(player)
	local m = Monsters:Get(player, detail.id)
	if m and not m.busy and AUTO_PLACE[detail.source] and penOf(s, detail.id) == 0 then
		local index = firstPenWithRoom(s)
		if index > 0 then
			putInPen(player, s, detail.id, index)
			penChanged(player, index)
		end
	end
	refresh(player)
end

local function onMonsterChanged(player, detail)
	if not joined[player] then
		return
	end
	local s = section(player)
	local id = detail.id
	local m = Monsters:Get(player, id)
	if not s or not m then
		return
	end
	local index = penOf(s, id)
	if index > 0 and m.busy then
		returnTo[player] = returnTo[player] or {}
		returnTo[player][id] = index
		takeOut(player, s, id)
		penChanged(player, index)
		refresh(player)
	elseif index == 0 and not m.busy and returnTo[player] and returnTo[player][id] then
		-- Back from an expedition or the breeding barn: return to its old pen if there's room.
		local back = returnTo[player][id]
		returnTo[player][id] = nil
		local pen = s.pens[back]
		if pen and #pen.monsters < pen.capacity then
			putInPen(player, s, id, back)
			penChanged(player, back)
			refresh(player)
		end
	elseif index > 0 and not quiet[player] then
		refresh(player)
	end
end

local function onMonsterRemoved(player, detail)
	if returnTo[player] then
		returnTo[player][detail.id] = nil
	end
	if not joined[player] then
		return
	end
	local s = section(player)
	local index = penOf(s, detail.id)
	if index > 0 then
		TableUtil.removeValue(s.pens[index].monsters, detail.id)
		penChanged(player, index)
	end
	refresh(player)
end

-- Garden ----------------------------------------------------------------------------------

local function gardenSpeed(): number
	local Weather = ctx:GetSystem("Weather")
	if not Weather then
		return 1
	end
	local ok, current = pcall(Weather.Current, Weather)
	if not ok or type(current) ~= "table" then
		return 1
	end
	local def = Config.Weather.ById[current.id]
	return if def and def.effects and def.effects.gardenSpeed then def.effects.gardenSpeed else 1
end

-- While it rains every second of growth counts `gardenSpeed` times.
local function growGardens(dt: number)
	local speed = gardenSpeed()
	if speed <= 1 then
		return
	end
	local now = ctx:Now()
	for _, player in ctx:Players() do
		local s = section(player)
		local changed = false
		for _, plot in s.garden.plots do
			if plot.flavor and plot.readyAt > now then
				plot.readyAt = math.max(now, plot.readyAt - dt * (speed - 1))
				changed = true
			end
		end
		if changed then
			ctx:Dirty(player, "garden")
		end
	end
end

local function harvest(player, s, index: number, food: { [string]: number }): boolean
	local plot = s.garden.plots[index]
	if not plot or not plot.flavor or ctx:Now() < plot.readyAt then
		return false
	end
	local yield = Economy.Garden.yield
	Currency:Add(player, "food." .. plot.flavor, yield, "garden")
	food[plot.flavor] = (food[plot.flavor] or 0) + yield
	plot.flavor = false
	plot.readyAt = 0
	return true
end

-- Upgrades ---------------------------------------------------------------------------------

local function upgrade(player, target: string, penIndex: number?): number
	local s = section(player)
	if target == "capacity" then
		local pen = ownedPen(player, penIndex)
		if pen.capacity >= Economy.Pens.maxCapacity then
			ctx:Fail("That pen is at max capacity")
		end
		charge(player, Economy.Pens.capacityCost[pen.capacity] or 0, "upgradePen")
		pen.capacity += 1
		penChanged(player, penIndex :: number)
		return pen.capacity
	elseif target == "jar" then
		local pen = ownedPen(player, penIndex)
		if pen.jarTier >= #Economy.JarTiers then
			ctx:Fail("That jar is fully upgraded")
		end
		charge(player, Economy.JarTiers[pen.jarTier + 1].cost, "upgradeJar")
		refresh(player) -- settle with the old cap first
		pen.jarTier += 1
		penChanged(player, penIndex :: number)
		return pen.jarTier
	elseif target == "incubatorSpeed" then
		local inc = Economy.Incubators
		if s.incubatorTier >= #inc.speedTiers then
			ctx:Fail("Incubators are fully upgraded")
		end
		charge(player, inc.speedCost[s.incubatorTier + 1], "upgradeIncubator")
		s.incubatorTier += 1
		ctx:Dirty(player, "incubatorTier")
		local Eggs = ctx:GetSystem("Eggs")
		if Eggs then
			Eggs:RefreshSpeed(player)
		end
		return s.incubatorTier
	elseif target == "barn" then
		if s.barnTier >= #Economy.Barn.capacity then
			ctx:Fail("The barn is fully upgraded")
		end
		charge(player, Economy.Barn.cost[s.barnTier + 1], "upgradeBarn")
		s.barnTier += 1
		ctx:Dirty(player, "barnTier")
		return s.barnTier
	elseif target == "garden" then
		Progression:Require(player, Economy.Garden.unlock)
		local garden = s.garden
		if garden.tier >= #Economy.Garden.plots then
			ctx:Fail("The garden is fully upgraded")
		end
		charge(player, Economy.Garden.cost[garden.tier + 1], "upgradeGarden")
		garden.tier += 1
		for i = #garden.plots + 1, Economy.Garden.plots[garden.tier] do
			garden.plots[i] = { flavor = false, readyAt = 0 }
		end
		ctx:Dirty(player, "garden")
		return garden.tier
	end
	ctx:Fail("Unknown upgrade")
end

-- Lifecycle ----------------------------------------------------------------------------

local capacityRegistered = setmetatable({}, { __mode = "k" })

local function registerSpeed()
	local Eggs = ctx:GetSystem("Eggs")
	if Eggs then
		Eggs:RegisterSpeedProvider("incubator", function(player)
			local s = section(player)
			local tiers = Economy.Incubators.speedTiers
			return if s then tiers[math.clamp(s.incubatorTier, 1, #tiers)] else 0
		end)
	end
end

function Ranch.Init(context)
	ctx = context
	Config = ctx.Config
	Economy = Config.Economy
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")

	ctx.Net:Handle("Ranch.Collect", function(player, payload)
		ownedPen(player, payload.pen)
		local coins = collect(player, { payload.pen }, 1, { xp = true, pen = payload.pen })
		if coins <= 0 then
			ctx:Fail("That jar is empty")
		end
		return { coins = coins }
	end)

	ctx.Net:Handle("Ranch.CollectAll", function(player)
		local coins = collect(player, allPens(section(player)), 1, { xp = true })
		if coins <= 0 then
			ctx:Fail("Your jars are empty")
		end
		return { coins = coins }
	end)

	ctx.Net:Handle("Ranch.Assign", function(player, payload)
		local s = section(player)
		local m, why = Monsters:Available(player, payload.id)
		if not m then
			ctx:Fail(why :: string)
		end
		local target = payload.pen
		if target > 0 then
			ownedPen(player, target)
		end
		local from = penOf(s, payload.id)
		if from == target then
			return nil
		end
		if target > 0 and #s.pens[target].monsters >= s.pens[target].capacity then
			ctx:Fail(string.format("Pen %d is full", target))
		end
		if returnTo[player] then
			returnTo[player][payload.id] = nil
		end
		takeOut(player, s, payload.id)
		if target > 0 then
			putInPen(player, s, payload.id, target)
		end
		refresh(player)
		if from > 0 then
			penChanged(player, from)
		end
		penChanged(player, target)
		return nil
	end)

	ctx.Net:Handle("Ranch.BuyPen", function(player)
		local s = section(player)
		local index = #s.pens + 1
		if index > Economy.Pens.max then
			ctx:Fail("You already own every pen")
		end
		Progression:Require(player, Economy.Pens.unlocks[index])
		charge(player, Economy.Pens.buyCost[index], "buyPen")
		s.pens[index] = newPen(ctx:Now())
		refresh(player)
		penChanged(player, index)
		return { pen = index }
	end)

	ctx.Net:Handle("Ranch.Upgrade", function(player, payload)
		local level = upgrade(player, payload.target, payload.pen)
		refresh(player)
		return { level = level }
	end)

	ctx.Net:Handle("Ranch.PlaceDecor", function(player, payload)
		local Shop = ctx:GetSystem("Shop")
		if not Shop then
			ctx:Fail("Decor isn't available right now")
		end
		local s = section(player)
		if payload.pen == 0 then
			for i, pen in s.pens do
				if TableUtil.removeValue(pen.decor, payload.decor) then
					Shop:ReturnDecor(player, payload.decor)
					penChanged(player, i)
					return nil
				end
			end
			ctx:Fail("That decor isn't placed in a pen")
		end
		local pen = ownedPen(player, payload.pen)
		if #pen.decor >= Config.Decor.PerPen then
			ctx:Fail(string.format("A pen holds up to %d decorations", Config.Decor.PerPen))
		end
		if not Shop:TakeDecor(player, payload.decor) then
			ctx:Fail("You don't have that decor. Buy it in the shop!")
		end
		table.insert(pen.decor, payload.decor)
		penChanged(player, payload.pen)
		return nil
	end)

	ctx.Net:Handle("Ranch.SetPenTheme", function(player, payload)
		local pen = ownedPen(player, payload.pen)
		local Shop = ctx:GetSystem("Shop")
		local owns = if Shop then Shop:OwnsTheme(player, payload.theme) else Config.Decor.PenThemeById[payload.theme].price == nil
		if not owns then
			ctx:Fail("You don't own that theme")
		end
		if pen.theme ~= payload.theme then
			pen.theme = payload.theme
			penChanged(player, payload.pen)
		end
		return nil
	end)

	ctx.Net:Handle("Ranch.Plant", function(player, payload)
		Progression:Require(player, Economy.Garden.unlock)
		local s = section(player)
		local plot = s.garden.plots[payload.plot]
		if not plot then
			ctx:Fail("That plot is locked. Upgrade the garden!")
		end
		if plot.flavor then
			ctx:Fail("Something is already growing there")
		end
		plot.flavor = payload.flavor
		plot.readyAt = ctx:Now() + Economy.Garden.growSeconds
		ctx:Dirty(player, "garden")
		return { readyAt = plot.readyAt }
	end)

	ctx.Net:Handle("Ranch.Harvest", function(player, payload)
		Progression:Require(player, Economy.Garden.unlock)
		local s = section(player)
		local food = {}
		if payload.plot then
			local plot = s.garden.plots[payload.plot]
			if not plot then
				ctx:Fail("That plot is locked. Upgrade the garden!")
			elseif not plot.flavor then
				ctx:Fail("Nothing is growing there")
			elseif not harvest(player, s, payload.plot, food) then
				ctx:Fail("That crop isn't ready yet")
			end
		else
			for i in s.garden.plots do
				harvest(player, s, i, food)
			end
			if next(food) == nil then
				ctx:Fail("Nothing is ready to harvest")
			end
		end
		ctx:Dirty(player, "garden")
		return { food = food }
	end)

	ctx.Bus:Subscribe("MonsterCreated", onMonsterCreated)
	ctx.Bus:Subscribe("MonsterChanged", onMonsterChanged)
	ctx.Bus:Subscribe("MonsterRemoved", onMonsterRemoved)
	ctx.Bus:Subscribe("RateModifiersChanged", function(player)
		if player then
			refresh(player)
		else
			for _, p in ctx:Players() do
				refresh(p)
			end
		end
	end)
	ctx.Bus:Subscribe("PassesChanged", function(player)
		refresh(player)
	end)
	ctx.Bus:Subscribe("PlayerReady", function(player)
		-- Every PlayerAdded hook has run: passes and boosts are known now.
		refresh(player)
	end)

	-- Settle, auto-collect (pass) and rain-boosted garden growth.
	ctx:Every(Economy.RanchTickSeconds, function(dt)
		for _, player in ctx:Players() do
			refresh(player)
			if not holdAuto[player] and hasPass(player, "autoCollect") then
				collect(player, allPens(section(player)), 1, { xp = false })
			end
		end
		growGardens(dt)
	end)

	-- Decor mood aura: offsets the online mood decay of monsters in decorated pens.
	ctx:Every(Economy.Mood.decayEvery, function()
		for _, player in ctx:Players() do
			local s = section(player)
			quiet[player] = true
			for _, pen in s.pens do
				local aura = 0
				for _, decorId in pen.decor do
					local def = Config.Decor.ById[decorId]
					aura += if def then def.mood else 0
				end
				if aura > 0 then
					for _, id in table.clone(pen.monsters) do
						Monsters:AddMood(player, id, aura)
					end
				end
			end
			quiet[player] = nil
			refresh(player)
		end
	end)
end

function Ranch.Start()
	-- Monsters keeps an append-only provider list. The provider reads the current `ctx`, so
	-- one registration per Monsters module is enough (Lune tests boot many kernels on the
	-- same cached modules; in a live server this runs once).
	if capacityRegistered[Monsters] then
		return registerSpeed()
	end
	capacityRegistered[Monsters] = true
	Monsters:RegisterCapacityProvider(function(player)
		local s = section(player)
		if not s then
			return UNLOADED_CAPACITY
		end
		local total = Economy.Barn.capacity[math.clamp(s.barnTier, 1, #Economy.Barn.capacity)]
		for _, pen in s.pens do
			total += pen.capacity
		end
		if hasPass(player, "bigBarn") then
			total += Economy.Barn.bigBarnPassBonus
		end
		return total
	end)
	registerSpeed()
end

function Ranch.PlayerAdded(player, _info)
	local s = section(player)
	local now = ctx:Now()
	if #s.pens == 0 then
		s.pens[1] = newPen(now)
	end
	s.offline = s.offline or { rates = {}, caps = {} }
	s.garden.plots = s.garden.plots or plots(Economy.Garden.plots[1])
	reconcilePens(player, s)

	-- Offline income: the rates saved when the player left, for the time away.
	local rates, caps = s.offline.rates or {}, s.offline.caps or {}
	for i, pen in s.pens do
		local jarAt = pen.jarAt or 0
		if jarAt > 0 and jarAt < now then
			local until_ = jarAt + math.min(now - jarAt, Economy.OfflineMaxSeconds)
			Jar.Settle(pen, rates[i] or 0, caps[i] or Jar.CapSeconds(pen.jarTier or 1), until_)
		end
		pen.jarAt = now
	end
	ctx:Dirty(player, "pens")

	local sess = ctx:Session(player)
	sess.rates, sess.caps, sess.income = {}, {}, 0
	sess.capacity, sess.used = 0, 0
	joined[player] = true
	refresh(player)
	ctx:DirtySession(player)
end

-- Settles the jars and remembers the rates for offline accrual.
local function finalize(player)
	local s = section(player)
	local sess = ctx:Session(player)
	if not s or not sess then
		return
	end
	refresh(player)
	s.offline = { rates = table.clone(sess.rates or {}), caps = table.clone(sess.caps or {}) }
end

function Ranch.BeforeSave(player)
	if joined[player] then
		finalize(player)
	end
end

function Ranch.PlayerRemoving(player)
	if joined[player] then
		finalize(player)
	end
	joined[player] = nil
	quiet[player] = nil
	holdAuto[player] = nil
	returnTo[player] = nil
end

return Ranch
