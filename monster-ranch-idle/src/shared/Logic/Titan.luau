--[[
	Titan (glow-up TT): pure rules for a scheduled titan invasion, shared by server and tests.
	No Roblox types; unit-tested in Titan.spec.

	  Titan.Window(schedule, duration, lobbySeconds, now) -> { startsAt, endsAt, lobbyAt, rotation }?
	      the scheduled invasion covering `now` (lobby or active), or nil outside one.
	  Titan.NextStart(schedule, now) -> number?
	      the next scheduled startsAt at or after `now` (for the "coming soon" preview), or nil.
	  Titan.ShouldReport(lastReportAt, now, everySeconds) -> boolean
	      whether it is time to flush this server's damage into the shared pool.
	  Titan.Reconcile(sharedHp, pendingLocal) -> number
	      the HP to show right now: the last confirmed shared value minus damage dealt on this
	      server since (an optimistic local estimate while a report is in flight or failing).
	  Titan.PruneServers(servers, now, staleAfter, cap?) -> { [jobId]: entry }
	      drops servers that haven't reported in `staleAfter` seconds (they emptied out or crashed),
	      then keeps the `cap` most recent (the shared record must stay small: a MemoryStore item).
	  Titan.Totals(servers) -> (serverCount, playerCount)
	  Titan.Outcome(hp, now, endsAt) -> "active" | "fallen" | "retreated"
	  Titan.Helped(damage, minDamage) -> boolean   the bar for the Titan Egg
	  Titan.Overlaps(schedule, duration, lobbySeconds, from, to) -> boolean
	      whether any scheduled invasion (lobby to end) overlaps [from, to]: the Stampede skips such
	      a period, so the two giants never share the arena.
]]

local Titan = {}

function Titan.Window(schedule: { any }, duration: number, lobbySeconds: number, now: number)
	for _, entry in schedule do
		local startsAt = entry.startsAt
		local endsAt = startsAt + duration
		local lobbyAt = startsAt - lobbySeconds
		if now >= lobbyAt and now < endsAt then
			return { startsAt = startsAt, endsAt = endsAt, lobbyAt = lobbyAt, rotation = entry.rotation }
		end
	end
	return nil
end

function Titan.NextStart(schedule: { any }, now: number): number?
	local best = nil
	for _, entry in schedule do
		if entry.startsAt >= now and (best == nil or entry.startsAt < best) then
			best = entry.startsAt
		end
	end
	return best
end

function Titan.ShouldReport(lastReportAt: number, now: number, everySeconds: number): boolean
	return now - lastReportAt >= everySeconds
end

function Titan.Reconcile(sharedHp: number, pendingLocal: number): number
	return math.max(0, sharedHp - pendingLocal)
end

function Titan.PruneServers(servers: { [string]: any }?, now: number, staleAfter: number, cap: number?): { [string]: any }
	local kept = {}
	if type(servers) ~= "table" then
		return kept
	end
	local fresh = {}
	for jobId, entry in servers do
		if type(entry) == "table" and now - (tonumber(entry.at) or 0) <= staleAfter then
			table.insert(fresh, { id = jobId, entry = entry, at = tonumber(entry.at) or 0 })
		end
	end
	if cap and #fresh > cap then
		table.sort(fresh, function(a, b)
			if a.at ~= b.at then
				return a.at > b.at
			end
			return tostring(a.id) < tostring(b.id)
		end)
	end
	for i, row in fresh do
		if cap and i > cap then
			break
		end
		kept[row.id] = row.entry
	end
	return kept
end

function Titan.Totals(servers: { [string]: any }?): (number, number)
	local serverCount, playerCount = 0, 0
	if type(servers) == "table" then
		for _, entry in servers do
			serverCount += 1
			playerCount += (type(entry) == "table" and tonumber(entry.players)) or 0
		end
	end
	return serverCount, playerCount
end

function Titan.Outcome(hp: number, now: number, endsAt: number): string
	if hp <= 0 then
		return "fallen"
	elseif now >= endsAt then
		return "retreated"
	end
	return "active"
end

function Titan.Helped(damage: number, minDamage: number): boolean
	return damage >= minDamage
end

function Titan.Overlaps(schedule: { any }, duration: number, lobbySeconds: number, from: number, to: number): boolean
	for _, entry in schedule do
		local lobbyAt = entry.startsAt - lobbySeconds
		local endsAt = entry.startsAt + duration
		if lobbyAt < to and from < endsAt then
			return true
		end
	end
	return false
end

return Titan
