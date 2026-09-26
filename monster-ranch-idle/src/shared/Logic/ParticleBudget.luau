--[[
	Logic/ParticleBudget (glow-up P): the pure rule behind Visuals/Vfx's particle budget
	(Config/Quality.Particles). Unit-tested in Quality.spec.

		ParticleBudget.Plan(demand, protected, budget, cfg) -> { [kind]: scale }
		    demand     { [kind]: live particles } the budgeted emitters would make at full rate
		    protected  live particles that are never cut (the local player's own monsters)
		    budget     the level's live-particle budget
		    cfg        { minScale, dropOrder }
		  Every kind in demand gets a scale in 0..1: 1 while everything fits; else all kinds scaled
		  together (down to cfg.minScale); then whole kinds switched off (0) in cfg.dropOrder; kinds
		  missing from dropOrder go last. If only protected particles are left and still too many,
		  every budgeted kind is 0. The result depends only on demand, so it never flaps on its own.
		ParticleBudget.Live(rate, lifetimeMin, lifetimeMax) -> number   Rate × mean Lifetime
		ParticleBudget.Allow(window, now, want, perSecond) -> number
		    the burst allowance: how many of `want` particles may be emitted now (window = a table
		    this keeps { start, used } in; one-second windows)
]]

local ParticleBudget = {}

function ParticleBudget.Live(rate: number, lifetimeMin: number, lifetimeMax: number): number
	if type(rate) ~= "number" or rate <= 0 then
		return 0
	end
	return rate * math.max(0, ((lifetimeMin or 0) + (lifetimeMax or lifetimeMin or 0)) / 2)
end

function ParticleBudget.Plan(demand: { [string]: number }, protected: number, budget: number, cfg): { [string]: number }
	local scales = {}
	local total = 0
	for kind, n in demand do
		scales[kind] = 1
		total += n
	end
	local room = budget - (protected or 0)
	if total <= room then
		return scales
	end
	if room <= 0 then
		for kind in scales do
			scales[kind] = 0
		end
		return scales
	end
	local minScale = cfg.minScale or 0.5
	local s = room / total
	if s >= minScale then
		for kind in scales do
			scales[kind] = s
		end
		return scales
	end
	-- Drop whole kinds, cheapest-to-lose first, until the rest fits at minScale.
	local order = {}
	for _, kind in cfg.dropOrder or {} do
		if demand[kind] then
			table.insert(order, kind)
		end
	end
	local rest = {}
	for kind in demand do
		if not table.find(order, kind) then
			table.insert(rest, kind)
		end
	end
	table.sort(rest)
	table.move(rest, 1, #rest, #order + 1, order)
	local remaining = total
	for _, kind in order do
		if remaining * minScale <= room then
			break
		end
		remaining -= demand[kind]
		scales[kind] = 0
	end
	local k = if remaining > 0 then math.min(1, room / remaining) else 1
	for kind, value in scales do
		if value > 0 then
			scales[kind] = k
		end
	end
	return scales
end

function ParticleBudget.Allow(window: { start: number, used: number }, now: number, want: number, perSecond: number): number
	if now - (window.start or -math.huge) >= 1 then
		window.start = now
		window.used = 0
	end
	local left = math.max(0, perSecond - (window.used or 0))
	local n = math.min(want, left)
	window.used = (window.used or 0) + n
	return n
end

return ParticleBudget
