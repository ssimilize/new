--[[
	Weather (S5): the server's shared sky. Rolls weather on a fixed clock, runs day/night,
	and gives monsters standing in pens a chance to mutate while weather is active.

	Global state (global.Weather):
	  { id, startedAt, endsAt, nextRollAt, night, phaseEndsAt, summonedBy = string|false }
	  id = "clear" between events (endsAt = 0 then). Day/night and the roll clock are aligned
	  to the unix clock (Logic/WeatherRoll), so every server agrees on when night falls.

	Schedule: every Config.Weather.RollInterval seconds (while the sky is clear) one weather is
	rolled by weight: Blood Moon only at night, Flags.ActiveEvent boosts applied. Non-clear
	weather lasts Config.Weather.Duration. During it, Ticks mutation rolls are spread evenly;
	each monster in a pen (Ranch:MonstersInPens) rolls (matchChance if it has the weather's
	element, else chance) / Ticks × Weather Magnet × Stargazer (starry weather only).

	Side effects: Starfall gives everyone online a free egg (Rewards); Heatwave speeds up
	incubators through an Eggs speed provider; Aurora is broadcast by Social (it subscribes
	to WeatherChanged). Weather totems (Robux) queue behind weather that is already running.

	Public API:
	  Weather:Current() -> { id, endsAt }
	  Weather:IsNight() -> boolean
	  Weather:Effects() -> { [effectKey]: number }        -- current weather's Config effects
	  Weather:Trigger(weatherId, source, seconds?) -> boolean   -- starts now, replacing the sky
	  Weather:GuaranteeMutation(player, mutationId) -> boolean  -- tutorial: one monster mutates

	Bus: publishes WeatherChanged { id } (nil player) and Mutated { id, mutation };
	fires Weather.Mutated { id, mutation, result } to the owner.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local Mutation = require(Shared.Logic.Mutation)
local WeatherRoll = require(Shared.Logic.WeatherRoll)

local Weather = {
	Name = "Weather",
	Dependencies = { "Monsters", "Rewards" },
	OptionalDependencies = { "Ranch", "Eggs", "Monetization" },
}

-- Sources that are not a player's name (never shown as "summoned by").
local SYSTEM_SOURCES = { roll = true, tutorial = true, event = true, admin = true }

local ctx
local Config
local Monsters, Rewards

local g -- global.Weather
local ticksDone = 0
local queue = {} -- totems waiting for the current weather to end: { { id, source } }

-- Helpers --------------------------------------------------------------------------------

local function def(id: string)
	return Config.Weather.ById[id]
end

local function isActive(): boolean
	return g.id ~= "clear" and ctx:Now() < g.endsAt
end

local function applyMutation(player, id: string, mutationId: string): string
	local m = Monsters:Get(player, id)
	if not m then
		return "missing"
	end
	local before = {}
	for _, existing in m.muts or {} do
		before[existing] = true
	end
	local result = Monsters:AddMutation(player, id, mutationId)
	if result == "added" or result == "combined" then
		local gained = mutationId
		for _, now in m.muts do
			if not before[now] then
				gained = now
			end
		end
		ctx.Net:Fire(player, "Weather.Mutated", { id = id, mutation = gained, result = result })
		ctx.Bus:Publish("Mutated", player, { id = id, mutation = gained })
		ctx.Analytics.Custom(player, "Mutation", 1, { mutation = gained, weather = g.id })
	end
	return result
end

local function mutationTick(weather)
	local Ranch = ctx:GetSystem("Ranch")
	if not Ranch or not weather.mutation then
		return
	end
	for _, player in ctx:Players() do
		local ok, list = pcall(Ranch.MonstersInPens, Ranch, player)
		if ok and type(list) == "table" then
			for _, entry in list do
				local m = Monsters:Get(player, entry.id)
				if m and not m.busy then
					local chance = WeatherRoll.MutationChance(weather, Formulas.Elements(m), Formulas.ActiveTraits(m))
					if chance > 0 and ctx.Rng:Chance(chance) then
						applyMutation(player, entry.id, weather.mutation)
					end
				end
			end
		elseif not ok then
			warn("[Weather] Ranch:MonstersInPens failed: " .. tostring(list))
		end
	end
end

local startWeather

local function endWeather()
	g.id = "clear"
	g.startedAt = ctx:Now()
	g.endsAt = 0
	g.summonedBy = false
	ticksDone = Config.Weather.Ticks
	ctx:DirtyGlobal()
	ctx.Bus:Publish("WeatherChanged", nil, { id = "clear" })
	local nextUp = table.remove(queue, 1)
	if nextUp then
		startWeather(nextUp.id, nextUp.source, nil)
	end
end

function startWeather(id: string, source: string?, seconds: number?)
	local weather = def(id)
	local now = ctx:Now()
	g.id = id
	g.startedAt = now
	g.endsAt = now + math.max(1, seconds or Config.Weather.Duration)
	g.summonedBy = if source and not SYSTEM_SOURCES[source] then source else false
	ticksDone = 0
	ctx:DirtyGlobal()
	ctx.Bus:Publish("WeatherChanged", nil, { id = id })

	local freeEgg = weather.effects and weather.effects.freeEgg
	if freeEgg then
		for _, player in ctx:Players() do
			Rewards:Grant(player, { { kind = "egg", id = freeEgg, amount = 1 } }, id)
		end
	end
end

local function step()
	local now = ctx:Now()
	local night, phaseEndsAt = WeatherRoll.Phase(now)
	if g.night ~= night or g.phaseEndsAt ~= phaseEndsAt then
		g.night = night
		g.phaseEndsAt = phaseEndsAt
		ctx:DirtyGlobal()
	end

	if g.id ~= "clear" then
		local weather = def(g.id)
		local ticks = Config.Weather.Ticks
		local duration = math.max(1, g.endsAt - g.startedAt)
		while ticksDone < ticks and now >= g.startedAt + (ticksDone + 0.5) * duration / ticks do
			ticksDone += 1
			mutationTick(weather)
		end
		if now >= g.endsAt then
			endWeather()
		end
	end

	if now >= g.nextRollAt then
		g.nextRollAt = WeatherRoll.NextRollAt(now)
		ctx:DirtyGlobal()
		if g.id == "clear" then
			local id = WeatherRoll.Roll(ctx.Rng, { night = g.night, event = Config.Flags.ActiveEvent })
			if id ~= "clear" then
				startWeather(id, "roll", nil)
			end
		end
	end
end

-- Public API ------------------------------------------------------------------------------

function Weather:Current()
	return { id = g.id, endsAt = g.endsAt }
end

function Weather:IsNight(): boolean
	return (WeatherRoll.Phase(ctx:Now()))
end

function Weather:Effects()
	if not isActive() then
		return {}
	end
	return def(g.id).effects or {}
end

function Weather:Trigger(weatherId: string, source: string?, seconds: number?): boolean
	local weather = def(weatherId)
	if not weather then
		warn("[Weather] Trigger: unknown weather " .. tostring(weatherId))
		return false
	end
	if weatherId == "clear" then
		if g.id ~= "clear" then
			endWeather()
		end
		return true
	end
	startWeather(weatherId, source, seconds)
	return true
end

function Weather:GuaranteeMutation(player, mutationId: string): boolean
	if not Config.Mutations.ById[mutationId] then
		return false
	end
	-- Pen monsters first (that is what the tutorial teaches), then anything else not busy.
	local order, seen = {}, {}
	local Ranch = ctx:GetSystem("Ranch")
	if Ranch then
		local ok, list = pcall(Ranch.MonstersInPens, Ranch, player)
		if ok and type(list) == "table" then
			for _, entry in list do
				table.insert(order, entry.id)
				seen[entry.id] = true
			end
		end
	end
	local rest = {}
	for id in Monsters:All(player) do
		if not seen[id] then
			table.insert(rest, id)
		end
	end
	table.sort(rest, function(x, y)
		return (tonumber(string.sub(x, 2)) or 0) < (tonumber(string.sub(y, 2)) or 0)
	end)
	table.move(rest, 1, #rest, #order + 1, order)

	for _, id in order do
		local m = Monsters:Get(player, id)
		if m and not m.busy and not Mutation.Has(m.muts, mutationId) then
			local result = applyMutation(player, id, mutationId)
			if result == "added" or result == "combined" then
				return true
			end
		end
	end
	return false
end

-- Lifecycle -----------------------------------------------------------------------------------

function Weather.Init(context)
	ctx = context
	Config = ctx.Config
	Monsters = ctx:GetSystem("Monsters")
	Rewards = ctx:GetSystem("Rewards")

	local now = ctx:Now()
	local night, phaseEndsAt = WeatherRoll.Phase(now)
	g = ctx:Global()
	g.id = "clear"
	g.startedAt = now
	g.endsAt = 0
	g.nextRollAt = WeatherRoll.NextRollAt(now)
	g.night = night
	g.phaseEndsAt = phaseEndsAt
	g.summonedBy = false
	ticksDone = Config.Weather.Ticks
	table.clear(queue)
	ctx:DirtyGlobal()

	ctx:Every(1, step)
end

function Weather.Start()
	local Monetization = ctx:GetSystem("Monetization")
	if Monetization then
		Monetization:RegisterProduct("Weather.Totem", function(player, product)
			local id = product and product.args and product.args.weather
			if type(id) ~= "string" or not Config.Weather.Totems[id] or not def(id) then
				warn("[Weather] totem product has no valid weather: " .. tostring(id))
				return false
			end
			if isActive() then
				-- Never cut short weather someone else is enjoying (or an Aurora): wait for it.
				table.insert(queue, { id = id, source = player.Name })
				ctx:Notify(
					player,
					string.format("Your %s will start after the current %s", def(id).name, def(g.id).name),
					"success"
				)
				return true
			end
			return Weather:Trigger(id, player.Name)
		end)
	end

	local Eggs = ctx:GetSystem("Eggs")
	if Eggs then
		Eggs:RegisterSpeedProvider("heatwave", function(_player)
			local speed = if isActive() then (def(g.id).effects or {}).hatchSpeed else nil
			if not speed or speed <= 1 then
				return 0
			end
			return 1 - 1 / speed -- ×1.25 speed = 20% less time
		end)
	end
end

return Weather
