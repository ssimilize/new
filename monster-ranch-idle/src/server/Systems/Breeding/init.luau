--[[
	Breeding (S5): the Breeding Barn. Two Adults go into a pod, a timer runs, and the baby is
	rolled with Logic/Breeding when the player claims it.

	Save section (profile.Breeding):
	  pods       = { [1..2] = { state = "idle"|"running", a = id|false, b = id|false, startedAt, endsAt, seed } }
	  daily      = { day, counts = { [monsterId] = breeds used today } }   -- UTC day
	  discovered = { [lineId] = true }                                      -- lines this player has bred

	Session (session.Breeding): { podCount, breedsPerDay }

	Actions: Breeding.Start { pod, a, b } · Breeding.Claim { pod } · Breeding.Cancel { pod }
	  (Claim returns the baby and `surges`, how many of its genes surged: Logic/Genetics)

	Rules:
	  • unlock "breeding"; pods = 1 + Breeding Pod pass (Monetization:HasPass, optional)
	  • both parents are Adults, different, owned and not busy; each parent breeds at most
	    breedsPerDay times per UTC day (Config.Breeding.BreedsPerDay + bonus providers)
	  • fee = Logic/Breeding.Fee (coins, never refunded); time = Logic/Breeding.Seconds
	  • parents carry the busy tag "breeding" until the baby is claimed or the pod is cancelled
	  • the roll is seeded at Start, so re-trying a failed claim (full ranch) gives the same baby

	Public API:
	  Breeding:RegisterBreedsPerDayBonus(key, fn(player) -> n)
	  Breeding:BreedsPerDay(player) -> number
	  Breeding:PodCount(player) -> number

	Bus: publishes Bred { id, hybrid, discovery } (discovery = a hybrid this player never bred
	before, and the first of that line on this server; Social broadcasts it), RanchXP, and
	WelcomeItem for pods that finished while the player was away.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local BreedingLogic = require(Shared.Logic.Breeding)
local Formulas = require(Shared.Logic.Formulas)
local Rng = require(Shared.Logic.Rng)

local Breeding = {
	Name = "Breeding",
	Dependencies = { "Currency", "Progression", "Monsters" },
	OptionalDependencies = { "Monetization" },
}

local function idlePod()
	return { state = "idle", a = false, b = false, startedAt = 0, endsAt = 0, seed = 0 }
end

Breeding.Profile = {
	Version = 1,
	Default = function()
		local pods = {}
		for i = 1, 2 do
			pods[i] = idlePod()
		end
		return { pods = pods, daily = { day = 0, counts = {} }, discovered = {} }
	end,
}

local ctx
local Config
local Currency, Progression, Monsters

local bonusProviders = {} -- [key] = fn(player) -> n
local serverDiscovered = {} -- [lineId] = true: hybrids already discovered on this server
local notified = {} -- [player] = { [pod] = true } pods whose "ready" toast was shown

-- Helpers ------------------------------------------------------------------------------

local function section(player)
	return ctx:Section(player)
end

local function podCountFor(player): number
	local pods = Config.Breeding.Pods
	local Monetization = ctx:GetSystem("Monetization")
	local hasPass = Monetization ~= nil and Monetization:HasPass(player, "breedingPod") == true
	return math.min(pods.max, pods.base + (if hasPass then pods.passPods else 0))
end

local function refreshDaily(player, s)
	local today = ctx:Day()
	if s.daily.day ~= today then
		s.daily = { day = today, counts = {} }
		ctx:Dirty(player, "daily")
	end
end

local function refreshSession(player)
	local sess = ctx:Session(player)
	if not sess or not section(player) then
		return
	end
	local podCount, perDay = podCountFor(player), Breeding:BreedsPerDay(player)
	if sess.podCount ~= podCount or sess.breedsPerDay ~= perDay then
		sess.podCount = podCount
		sess.breedsPerDay = perDay
		ctx:DirtySession(player)
	end
end

local function resetPod(player, index: number)
	local s = section(player)
	s.pods[index] = idlePod()
	ctx:Dirty(player, "pods")
	if notified[player] then
		notified[player][index] = nil
	end
end

local function freeParents(player, pod)
	for _, id in { pod.a, pod.b } do
		local m = id and Monsters:Get(player, id)
		if m and m.busy == "breeding" then
			Monsters:SetBusy(player, id, false)
		end
	end
end

local function mustPod(player, index: number)
	local pod = section(player).pods[index]
	if not pod then
		ctx:Fail("That pod doesn't exist")
	end
	return pod
end

local function requireParent(player, id: string)
	local m, why = Monsters:Available(player, id)
	if not m then
		ctx:Fail(why or "That monster doesn't exist")
	end
	if m.stage < 3 then
		ctx:Fail(Formulas.DisplayName(m) .. " must be an Adult to breed")
	end
	return m
end

-- Public API ------------------------------------------------------------------------------

function Breeding:RegisterBreedsPerDayBonus(key: string, fn)
	bonusProviders[key] = fn
end

function Breeding:BreedsPerDay(player): number
	local total = Config.Breeding.BreedsPerDay
	for key, provider in bonusProviders do
		local ok, value = pcall(provider, player)
		if ok and type(value) == "number" and value == value then
			total += math.max(0, math.floor(value))
		elseif not ok then
			warn(string.format("[Breeding] breeds-per-day provider '%s' failed: %s", key, tostring(value)))
		end
	end
	return total
end

function Breeding:PodCount(player): number
	return podCountFor(player)
end

-- Actions ---------------------------------------------------------------------------------

local function start(player, payload)
	Progression:Require(player, Config.Breeding.Unlock)
	local s = section(player)
	if payload.pod > podCountFor(player) then
		ctx:Fail("Get the Breeding Pod pass to use a second pod")
	end
	local pod = mustPod(player, payload.pod)
	if pod.state ~= "idle" then
		ctx:Fail("That pod is already in use")
	end
	if payload.a == payload.b then
		ctx:Fail("Pick two different monsters")
	end
	local a = requireParent(player, payload.a)
	local b = requireParent(player, payload.b)

	refreshDaily(player, s)
	local perDay = Breeding:BreedsPerDay(player)
	for _, parent in { a, b } do
		if (s.daily.counts[parent.id] or 0) >= perDay then
			ctx:Fail(Formulas.DisplayName(parent) .. " has no breeds left today")
		end
	end

	local fee = BreedingLogic.Fee(a, b)
	if fee > 0 then
		Currency:Charge(player, { coins = fee }, "breeding")
	end

	local now = ctx:Now()
	local endsAt = now + BreedingLogic.Seconds(a, b)
	s.pods[payload.pod] = {
		state = "running",
		a = a.id,
		b = b.id,
		startedAt = now,
		endsAt = endsAt,
		seed = ctx.Rng:Int(1, 2147483646),
	}
	for _, parent in { a, b } do
		s.daily.counts[parent.id] = (s.daily.counts[parent.id] or 0) + 1
		Monsters:SetBusy(player, parent.id, "breeding")
	end
	if notified[player] then
		notified[player][payload.pod] = nil
	end
	ctx:Dirty(player, "pods")
	ctx:Dirty(player, "daily")
	refreshSession(player)
	return { endsAt = endsAt }
end

local function claim(player, payload)
	local s = section(player)
	local pod = mustPod(player, payload.pod)
	if pod.state ~= "running" then
		ctx:Fail("Nothing is breeding in that pod")
	end
	if ctx:Now() < pod.endsAt then
		ctx:Fail("Still breeding. Check back soon!")
	end
	local a, b = Monsters:Get(player, pod.a), Monsters:Get(player, pod.b)
	if not a or not b then
		freeParents(player, pod)
		resetPod(player, payload.pod)
		ctx:Fail("The parents are no longer on your ranch")
	end

	local spec, isHybrid = BreedingLogic.Roll(Rng.new(pod.seed), a, b)
	local record, err = Monsters:Create(player, spec, "breed")
	if not record then
		ctx:Fail(err or "Your ranch is full. Sell monsters or upgrade the barn.")
	end

	freeParents(player, pod)
	resetPod(player, payload.pod)

	local newForPlayer = not s.discovered[spec.line]
	if newForPlayer then
		s.discovered[spec.line] = true
		ctx:Dirty(player, "discovered", spec.line)
	end
	local discovery = isHybrid and newForPlayer and not serverDiscovered[spec.line]
	if isHybrid then
		serverDiscovered[spec.line] = true
	end

	ctx.Bus:Publish("Bred", player, { id = record.id, hybrid = isHybrid, discovery = discovery })
	ctx.Bus:Publish("RanchXP", player, { amount = Config.Unlocks.XP.breed, reason = "breed" })
	ctx.Analytics.Custom(player, "Breed", record.rarity, {
		line = spec.line,
		hybrid = tostring(isHybrid),
		variant = tostring(record.variant),
	})
	return { monster = record, hybridDiscovered = isHybrid and newForPlayer, surges = spec.surges or 0 }
end

local function cancel(player, payload)
	local pod = mustPod(player, payload.pod)
	if pod.state ~= "running" then
		ctx:Fail("That pod is empty")
	end
	freeParents(player, pod)
	resetPod(player, payload.pod)
	return nil
end

-- Timers ------------------------------------------------------------------------------------

local function announceReady(player)
	local s = section(player)
	if not s then
		return
	end
	local now = ctx:Now()
	local seen = notified[player]
	if not seen then
		seen = {}
		notified[player] = seen
	end
	for index, pod in s.pods do
		if pod.state == "running" and now >= pod.endsAt and not seen[index] then
			seen[index] = true
			ctx:Notify(player, "A baby is ready in the Breeding Barn!", "success")
		end
	end
end

-- Lifecycle -----------------------------------------------------------------------------------

function Breeding.Init(context)
	ctx = context
	Config = ctx.Config
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	-- Fresh module state (tests boot many kernels in one process).
	table.clear(bonusProviders)
	table.clear(serverDiscovered)
	table.clear(notified)

	ctx.Net:Handle("Breeding.Start", start)
	ctx.Net:Handle("Breeding.Claim", claim)
	ctx.Net:Handle("Breeding.Cancel", cancel)

	ctx.Bus:Subscribe("PassesChanged", function(player)
		refreshSession(player)
	end)

	ctx:Every(1, function()
		for _, player in ctx:Players() do
			announceReady(player)
		end
	end)
	-- Bonus providers (Hall of Fame upgrades) have no change topic; poll cheaply.
	ctx:Every(10, function()
		for _, player in ctx:Players() do
			refreshSession(player)
		end
	end)
end

function Breeding.PlayerAdded(player, info)
	local s = section(player)
	refreshDaily(player, s)
	local now = ctx:Now()
	local seen = {}
	notified[player] = seen
	local finishedAway = 0
	for index, pod in s.pods do
		if pod.state == "running" then
			local a, b = Monsters:Get(player, pod.a), Monsters:Get(player, pod.b)
			if not a or not b then
				freeParents(player, pod)
				resetPod(player, index)
			else
				-- Re-assert the busy tag in case a crash saved the parents without it.
				for _, parent in { a, b } do
					if parent.busy ~= "breeding" then
						Monsters:SetBusy(player, parent.id, "breeding")
					end
				end
				if now >= pod.endsAt then
					seen[index] = true
					if pod.endsAt > (info and info.lastSeen or 0) then
						finishedAway += 1
					end
				end
			end
		end
	end
	if finishedAway > 0 then
		ctx.Bus:Publish("WelcomeItem", player, {
			kind = "breeding",
			text = if finishedAway == 1
				then "A baby is ready in the Breeding Barn"
				else string.format("%d babies are ready in the Breeding Barn", finishedAway),
		})
	end
	refreshSession(player)
end

function Breeding.PlayerRemoving(player)
	notified[player] = nil
end

return Breeding
