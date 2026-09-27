--[[
	Logic/Fishing (update 3.10 · Ranch life): pure rules of the Fishing Pond (Config/Fishing),
	shared by Systems/Fishing (the authoritative replay) and the Fishing screen (what the player
	sees, stepped with the very same functions).

	  Fishing.BuddyBonus(luck) -> pct                   Loot.LuckBonus with the buddy counted BuddyShares times
	  Fishing.RarityChances(bonus) -> { [rarityId]: p } what bites (sums to 1)
	  Fishing.ExtraChance(chance, cap, bonus) -> p      min(cap, chance × (1 + bonus)), as Bounties
	  Fishing.Roll(seed, bonus?) -> fishDef             which fish is on the line
	  Fishing.Weight(seed, fishDef) -> kg                seeded, two decimals
	  Fishing.Course(seed, bonus?) -> Course             { fish, rarity, weight, points = { { t, y } } }
	  Fishing.FishAt(course, t) -> y                     0..1, eased between the points
	  Fishing.Valid(inputs) -> ok, why?                  { { t, down } }, t ascending, in range
	  Fishing.DownAt(inputs, t) -> boolean               held at t (an input at exactly t applies)
	  Fishing.NewState() -> State                        { i, zone, vel, meter, done, caught, time }
	  Fishing.Advance(state, course, inputs)             one Step: uses DownAt(inputs, i × Step)
	  Fishing.Simulate(seed, inputs, bonus?) -> { caught, time, fish, rarity, weight, meter }
	  Fishing.Extras(seed, bonus) -> { Reward }          rare decor (one at most) and the region egg
	  Fishing.Egg() -> eggId?
	  Fishing.SpendOrder() -> { fishId }                 cheapest first (the Kitchen's SpendFish)
	  Fishing.Species(log) -> number                     kinds caught (profile.Fishing.log)

	Step i (1-based) runs from (i - 1) × Step to i × Step with the hold state at its start, so an
	input recorded while the client is between steps only reaches later steps, on both sides.
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)
local Loot = require(script.Parent.Loot)

local Cfg = Config.Fishing

local Fishing = {}

local function round(x: number, places: number): number
	local m = 10 ^ places
	return math.floor(x * m + 0.5) / m
end

function Fishing.BuddyBonus(luck: number?): number
	if type(luck) ~= "number" or luck ~= luck or luck <= 0 then
		return 0
	end
	local lucks = table.create(Cfg.BuddyShares, luck)
	return round(Loot.LuckBonus(lucks), 4)
end

local function weights(bonus: number?): { number }
	local b = math.max(0, bonus or 0)
	local list = {}
	for i, r in Cfg.Rarities do
		list[i] = if i == 1 then r.weight else r.weight * (1 + b)
	end
	return list
end

function Fishing.RarityChances(bonus: number?): { [string]: number }
	local list = weights(bonus)
	local total = 0
	for _, w in list do
		total += w
	end
	local out = {}
	for i, r in Cfg.Rarities do
		out[r.id] = list[i] / total
	end
	return out
end

function Fishing.ExtraChance(chance: number, cap: number, bonus: number?): number
	return math.min(cap, chance * (1 + math.max(0, bonus or 0)))
end

function Fishing.Roll(seed: number, bonus: number?)
	local rng = Rng.new(Rng.seed("fish", seed))
	local rarity = Cfg.Rarities[rng:Weighted(weights(bonus))]
	local pool = {}
	for _, f in Cfg.Fish do
		if f.rarity == rarity.id then
			table.insert(pool, f)
		end
	end
	return rng:Pick(pool)
end

function Fishing.Weight(seed: number, def): number
	local rng = Rng.new(Rng.seed("fish_weight", seed))
	-- Squared roll: most fish are on the light side, big ones are worth bragging about.
	local x = rng:Next()
	return math.max(0.01, round(def.weight[1] + (def.weight[2] - def.weight[1]) * x * x, 2))
end

function Fishing.Course(seed: number, bonus: number?)
	local def = Fishing.Roll(seed, bonus)
	local rarity = Cfg.RarityById[def.rarity]
	local rng = Rng.new(Rng.seed("fish_course", seed))
	local points = { { t = 0, y = Cfg.StartFish } }
	local t, y = 0, Cfg.StartFish
	while t < Cfg.Duration do
		t = round(t + rng:Float(rarity.speed[1], rarity.speed[2]), 3)
		if not rng:Chance(rarity.pause) then
			y = round(math.clamp(y + rng:Float(-rarity.range, rarity.range), Cfg.FishRange[1], Cfg.FishRange[2]), 3)
		end
		table.insert(points, { t = t, y = y })
	end
	return { fish = def.id, rarity = def.rarity, weight = Fishing.Weight(seed, def), points = points }
end

function Fishing.FishAt(course, t: number): number
	local points = course.points
	for i = 2, #points do
		local b = points[i]
		if t <= b.t then
			local a = points[i - 1]
			local span = b.t - a.t
			local k = if span > 0 then math.clamp((t - a.t) / span, 0, 1) else 1
			k = k * k * (3 - 2 * k)
			return a.y + (b.y - a.y) * k
		end
	end
	return points[#points].y
end

function Fishing.Valid(inputs): (boolean, string?)
	if type(inputs) ~= "table" or #inputs > Cfg.MaxInputs then
		return false, "too many moves"
	end
	local last = 0
	for _, input in inputs do
		if type(input) ~= "table" or type(input.t) ~= "number" or type(input.down) ~= "boolean" then
			return false, "bad move"
		end
		if input.t ~= input.t or input.t < last or input.t > Cfg.Duration then
			return false, "moves out of order"
		end
		last = input.t
	end
	return true, nil
end

function Fishing.DownAt(inputs, t: number): boolean
	local down = false
	for _, input in inputs do
		if input.t <= t then
			down = input.down
		else
			break
		end
	end
	return down
end

function Fishing.NewState()
	return { i = 0, zone = Cfg.ZoneSize / 2, vel = 0, meter = Cfg.StartMeter, done = false, caught = false, time = 0 }
end

function Fishing.Advance(state, course, inputs)
	if state.done then
		return state
	end
	local rarity = Cfg.RarityById[course.rarity]
	local dt = Cfg.Step
	local t0 = state.i * dt
	state.i += 1
	local t1 = state.i * dt
	if Fishing.DownAt(inputs, t0) then
		state.vel = math.min(Cfg.MaxSpeed, state.vel + Cfg.Lift * dt)
	else
		state.vel = math.max(-Cfg.MaxSpeed, state.vel - Cfg.Gravity * dt)
	end
	local half = Cfg.ZoneSize / 2
	state.zone += state.vel * dt
	if state.zone <= half then
		state.zone, state.vel = half, math.max(0, state.vel)
	elseif state.zone >= 1 - half then
		state.zone, state.vel = 1 - half, math.min(0, state.vel)
	end
	local fish = Fishing.FishAt(course, t1)
	if math.abs(fish - state.zone) <= half then
		state.meter = math.min(1, state.meter + rarity.fill * dt)
	else
		state.meter = math.max(0, state.meter - rarity.drain * dt)
	end
	if state.meter >= 1 then
		state.done, state.caught, state.time = true, true, round(t1, 3)
	elseif state.meter <= 0 or t1 >= Cfg.Duration - 1e-9 then
		state.done, state.caught, state.time = true, false, round(t1, 3)
	end
	return state
end

function Fishing.Simulate(seed: number, inputs, bonus: number?)
	local course = Fishing.Course(seed, bonus)
	local state = Fishing.NewState()
	while not state.done do
		Fishing.Advance(state, course, inputs)
	end
	return {
		caught = state.caught,
		time = state.time,
		fish = course.fish,
		rarity = course.rarity,
		weight = course.weight,
		meter = state.meter,
	}
end

function Fishing.Egg(): string?
	return if Config.Eggs.ById[Cfg.Egg] then Cfg.Egg else nil
end

function Fishing.Extras(seed: number, bonus: number?)
	local rng = Rng.new(Rng.seed("fish_extra", seed))
	local items = {}
	local gotDecor = false
	for _, d in Cfg.Decor do
		local hit = rng:Next() < Fishing.ExtraChance(d.chance, d.cap, bonus)
		if hit and not gotDecor then
			gotDecor = true
			table.insert(items, { kind = "decor", id = d.id, amount = 1 })
		end
	end
	local egg = Fishing.Egg()
	if rng:Next() < Fishing.ExtraChance(Cfg.EggChance, Cfg.EggChanceMax, bonus) and egg then
		table.insert(items, { kind = "egg", id = egg, amount = 1 })
	end
	return items
end

function Fishing.Value(fishId: string): number
	local def = Cfg.ById[fishId]
	local rarity = def and Cfg.RarityById[def.rarity]
	return if rarity then rarity.value else 0
end

function Fishing.SpendOrder(): { string }
	local list = table.clone(Cfg.Ids)
	table.sort(list, function(a, b)
		local va, vb = Fishing.Value(a), Fishing.Value(b)
		if va ~= vb then
			return va < vb
		end
		return Cfg.ById[a].order < Cfg.ById[b].order
	end)
	return list
end

function Fishing.Species(log): number
	local n = 0
	if type(log) == "table" then
		for id, entry in log do
			if Cfg.ById[id] and type(entry) == "table" and (tonumber(entry.n) or 0) > 0 then
				n += 1
			end
		end
	end
	return n
end

return Fishing
