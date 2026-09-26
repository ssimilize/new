--[[
	StampedeArena (glow-up U): pure rules for the Stampede drawn in the world (Controllers/StampedeArena).
	No Roblox types; unit-tested in StampedeArena.spec.

	  StampedeArena.Rings(n, inner, gap, spacing) -> { { x, z, ring } }
	      n slots round the centre, inner ring first. A ring of radius r holds floor(2πr / spacing)
	      (at least 3); the last, partial ring spreads its members evenly. Odd rings are turned half
	      a slot so neighbours on consecutive rings don't line up.
	  StampedeArena.Pick(squads, myUserId, perPlayer, cap) -> { { userId, look, mine } }
	      who is drawn: the local player's squad first, then everyone else round-robin (every
	      player's lead before anyone's second), at most perPlayer each and cap in all.
	  StampedeArena.AttackOffset(index, count, period) -> seconds
	      when squad monster `index` first attacks, spreading `count` monsters over one period.
	  StampedeArena.Crossed(prevFrac, frac, thresholds) -> threshold?
	      the deepest stagger threshold crossed going from prevFrac down to frac (nil if none).
	  StampedeArena.newPacer(perSecond) -> pacer   pacer:Take(now) -> boolean
	      at most perSecond successes in any one-second window (a ring of the last send times).
	  StampedeArena.Approach(value, target, dt, seconds) -> number
	      moves value linearly toward target, the whole way in `seconds`.
	  StampedeArena.MaxMonsters(cfg, level) -> number   the squad model cap for a Quality level.
]]

local StampedeArena = {}

local TAU = math.pi * 2

function StampedeArena.Rings(n: number, inner: number, gap: number, spacing: number): { { x: number, z: number, ring: number } }
	local out = {}
	local placed, ring = 0, 1
	while placed < n do
		local r = inner + (ring - 1) * gap
		local capacity = math.max(3, math.floor(TAU * r / spacing))
		local here = math.min(capacity, n - placed)
		local turn = if ring % 2 == 0 then 0.5 else 0
		for i = 1, here do
			local a = (i - 1 + turn) / here * TAU
			table.insert(out, { x = math.cos(a) * r, z = math.sin(a) * r, ring = ring })
		end
		placed += here
		ring += 1
	end
	return out
end

function StampedeArena.Pick(squads: { any }?, myUserId: number?, perPlayer: number, cap: number): { any }
	local out = {}
	if type(squads) ~= "table" then
		return out
	end
	local others = {}
	for _, entry in squads do
		if type(entry) == "table" and type(entry.looks) == "table" then
			if entry.userId == myUserId then
				for i, look in entry.looks do
					if i > perPlayer or #out >= cap then
						break
					end
					table.insert(out, { userId = entry.userId, look = look, mine = true })
				end
			else
				table.insert(others, entry)
			end
		end
	end
	for slot = 1, perPlayer do
		for _, entry in others do
			if #out >= cap then
				return out
			end
			local look = entry.looks[slot]
			if look then
				table.insert(out, { userId = entry.userId, look = look, mine = false })
			end
		end
	end
	return out
end

function StampedeArena.AttackOffset(index: number, count: number, period: number): number
	if count <= 0 then
		return 0
	end
	-- Interleave neighbours (golden-ratio steps) so the ring ripples instead of sweeping round.
	local f = ((index - 1) * 0.6180339887) % 1
	return f * period
end

function StampedeArena.Crossed(prevFrac: number?, frac: number, thresholds: { number }): number?
	if type(prevFrac) ~= "number" or frac >= prevFrac then
		return nil
	end
	local deepest = nil
	for _, t in thresholds do
		if prevFrac > t and frac <= t and (deepest == nil or t < deepest) then
			deepest = t
		end
	end
	return deepest
end

function StampedeArena.newPacer(perSecond: number)
	local size = math.max(1, math.floor(perSecond))
	local times = table.create(size, -math.huge)
	local head = 1
	local pacer = {}
	function pacer:Take(now: number): boolean
		-- times[head] is the oldest of the last `size` sends.
		if now - times[head] < 1 then
			return false
		end
		times[head] = now
		head = head % size + 1
		return true
	end
	return pacer
end

function StampedeArena.Approach(value: number, target: number, dt: number, seconds: number): number
	local step = if seconds > 0 then dt / seconds else 1
	if value < target then
		return math.min(target, value + step)
	end
	return math.max(target, value - step)
end

function StampedeArena.MaxMonsters(cfg, level: number): number
	local list = cfg.maxMonsters
	return list[math.clamp(level, 1, #list)] or list[#list]
end

return StampedeArena
