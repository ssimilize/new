--[[
	Observatory (update 3.12 · Honey & stars): the domed observatory on every plot and its Star
	Charts. Rules: Config/Observatory and Logic/Observatory. Opened from the telescope's "Stargaze"
	prompt (Controllers/Interaction).

	Save section (profile.Observatory):
	  night, used           -- sightings started on night `night` (the day-cycle index)
	  n                     -- sightings started ever (the sighting id)
	  secret                -- PRIVATE: mixed into every sighting's seed
	  charts = { [chartId]: observations }   -- successful sightings per chart (3 = charted)
	  seen                  -- successful sightings ever

	The open sighting lives in memory only (one per player, one-shot): { id, chart, order, startedAt }.

	Actions:
	  Observatory.Start { chart } -> { id, chart, stars = { { x, y } }, order, left, limit }
	    Night only; uses one of tonight's sightings; the chart must be unfinished and in season.
	  Observatory.Submit { id, taps = { { star, t } } } -> { success, why?, chart, progress, charted, left }
	    t = seconds since the start. Checks the order, rising times at least MinGap apart, the last
	    tap within TimeLimit, and that the server's own clock agrees. A failure still used the sighting.

	Public API:
	  Observatory:Charted(player) -> { [chartId]: true }
	  Observatory:Perk(player, key) -> number     the capped perk sum (0 when none or locked)

	Wires its perks into Eggs (speed provider), Ranch (rate modifier), Expeditions (loot modifier)
	and Tourists (appeal bonus) in Start; Fishing and the Dojo read Observatory:Perk themselves;
	hive_hours is read by the Apiary. Publishes StarSighted (player, { chart }) for each successful
	sighting (the weekly goal stars_5) and StarCharted (player, { chart }) when a chart is finished.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Observatory)
local Seasons = require(Shared.Logic.Seasons)

local Observatory = {
	Name = "Observatory",
	Dependencies = { "Progression" },
	OptionalDependencies = { "Eggs", "Ranch", "Expeditions", "Tourists" },
}

Observatory.Profile = {
	Version = 1,
	Private = { "secret" },
	Default = function()
		return {
			night = 0,
			used = 0,
			n = 0,
			secret = 0,
			charts = {},
			seen = 0,
		}
	end,
}

local ctx
local Cfg -- Config.Observatory
local Progression
local open = {} -- [player] = { id, chart, order, startedAt }

local function mustSection(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

local function sync(player, s, night: number)
	if s.night ~= night then
		s.night = night
		s.used = 0
		ctx:Dirty(player)
	end
end

-- Public API ---------------------------------------------------------------------------

function Observatory:Charted(player): { [string]: boolean }
	local s = ctx:Section(player)
	local out = {}
	if s then
		for _, c in Cfg.Charts do
			if Logic.Done(s.charts, c.id) then
				out[c.id] = true
			end
		end
	end
	return out
end

function Observatory:Perk(player, key: string): number
	local s = ctx:Section(player)
	if not s or not Progression:IsUnlocked(player, Cfg.Unlock) then
		return 0
	end
	return Logic.Perk(s.charts, key)
end

-- Actions ------------------------------------------------------------------------------

local function start(player, payload)
	local s = mustSection(player)
	Progression:Require(player, Cfg.Unlock)
	local now = ctx:Now()
	local isNight, night = Logic.Night(now)
	if not isNight then
		ctx:Fail("The stars come out at night. Come back after dark")
	end
	sync(player, s, night)
	local def = Cfg.ById[payload.chart]
	if not Logic.Available(def, Seasons.At(now).id) then
		ctx:Fail("That chart's stars aren't in the sky this season")
	end
	if Logic.Done(s.charts, def.id) then
		ctx:Fail("You already charted those stars")
	end
	if s.used >= Cfg.Sightings then
		ctx:Fail("No sightings left tonight. Come back tomorrow night")
	end
	if s.secret == 0 then
		s.secret = ctx.Rng:Int(1, 2 ^ 30)
	end
	s.used += 1
	s.n += 1
	local sky = Logic.Sky(Logic.Seed(player.UserId, night, s.used, s.secret), def.stars)
	open[player] = { id = s.n, chart = def.id, order = sky.order, startedAt = ctx.Clock.Precise() }
	ctx:Dirty(player)
	return {
		id = s.n,
		chart = def.id,
		stars = sky.stars,
		order = sky.order,
		left = Cfg.Sightings - s.used,
		limit = Cfg.TimeLimit,
	}
end

local function submit(player, payload)
	local s = mustSection(player)
	local run = open[player]
	if not run or run.id ~= payload.id then
		ctx:Fail("That sighting is over. Start a new one!")
	end
	open[player] = nil
	local elapsed = ctx.Clock.Precise() - run.startedAt
	local ok, why = Logic.Check(run.order, payload.taps)
	if ok then
		local last = payload.taps[#payload.taps].t
		if elapsed + Cfg.GraceSeconds < last then
			ok, why = false, "fast"
		elseif elapsed > Cfg.TimeLimit + Cfg.LateSeconds then
			ok, why = false, "slow"
		end
	end
	local charted = false
	if ok then
		local before = Logic.Progress(s.charts, run.chart)
		s.charts[run.chart] = math.min(Cfg.Observations, before + 1)
		s.seen += 1
		ctx:Dirty(player)
		ctx.Bus:Publish("StarSighted", player, { chart = run.chart })
		if Logic.Done(s.charts, run.chart) then
			charted = true
			ctx.Bus:Publish("StarCharted", player, { chart = run.chart })
			-- Perks that feed cached numbers take effect now.
			local Eggs, Ranch = ctx:GetSystem("Eggs"), ctx:GetSystem("Ranch")
			if Eggs and Eggs.RefreshSpeed then
				pcall(Eggs.RefreshSpeed, Eggs, player)
			end
			if Ranch and Ranch.Refresh then
				pcall(Ranch.Refresh, Ranch, player)
			end
		end
	end
	local _, night = Logic.Night(ctx:Now())
	local left = if s.night == night then math.max(0, Cfg.Sightings - s.used) else Cfg.Sightings
	return {
		success = ok,
		why = why,
		chart = run.chart,
		progress = Logic.Progress(s.charts, run.chart),
		charted = charted,
		left = left,
	}
end

-- Lifecycle ----------------------------------------------------------------------------

function Observatory.Init(context)
	ctx = context
	Cfg = ctx.Config.Observatory
	Progression = ctx:GetSystem("Progression")
	open = {}

	ctx.Net:Handle("Observatory.Start", start)
	ctx.Net:Handle("Observatory.Submit", submit)
end

function Observatory.Start()
	local function perk(key: string)
		return function(player)
			return Observatory:Perk(player, key)
		end
	end
	local Eggs = ctx:GetSystem("Eggs")
	if Eggs and Eggs.RegisterSpeedProvider then
		Eggs:RegisterSpeedProvider("observatory", perk("egg_speed"))
	end
	local Ranch = ctx:GetSystem("Ranch")
	if Ranch and Ranch.RegisterRateModifier then
		Ranch:RegisterRateModifier("observatory", perk("income"))
	end
	local Expeditions = ctx:GetSystem("Expeditions")
	if Expeditions and Expeditions.RegisterLootModifier then
		Expeditions:RegisterLootModifier("observatory", perk("loot"))
	end
	local Tourists = ctx:GetSystem("Tourists")
	if Tourists and Tourists.RegisterAppealBonus then
		Tourists:RegisterAppealBonus("observatory", perk("appeal"))
	end
end

function Observatory.PlayerAdded(player)
	local s = ctx:Section(player)
	if not s then
		return
	end
	-- Drops anything a damaged save left behind.
	if type(s.charts) ~= "table" then
		s.charts = {}
	end
	for id, n in s.charts do
		if not Cfg.ById[id] or type(n) ~= "number" then
			s.charts[id] = nil
		else
			s.charts[id] = Logic.Progress(s.charts, id)
		end
	end
	local _, night = Logic.Night(ctx:Now())
	sync(player, s, night)
	ctx:Dirty(player)
end

function Observatory.PlayerRemoving(player)
	open[player] = nil
end

return Observatory
