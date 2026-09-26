--[[
	BattleStage (glow-up V): the pure planning behind fights drawn in 3D (plain numbers and tables,
	no Roblox types). Used by UI/Screens/Parts/Battle (3D or 2D), Parts/BattleStage and
	Visuals/BattleArena, tuned by Config/BattleStage, unit-tested in BattleStage.spec.

	  BattleStage.Choose(info, cfg) -> "3d" | "2d", reason
	      info = { units, low, cameraFree, frameMs? }; cfg = Config.BattleStage
	  BattleStage.Theme(cfg, stageKey?) -> theme      a region id, "arena", "raid"; else default
	  BattleStage.Row(count, layout) -> { { back, across } }   one side's spots: `back` studs behind
	      the front line, `across` sideways from the centre line; up to `perRow` per row
	  BattleStage.Placement(units, cfg) -> { [key] = { x, z, scale, boss, side } }
	      allies at x < 0, enemies at x > 0 (stage space); a lone boss stands centred behind its row
	  BattleStage.Size(scaleFor, boss, cfg) -> number   the MonsterModel.Build opts.scale that draws a
	      monster whose own MonsterModel.ScaleFor is `scaleFor` at the battle size
	  BattleStage.Step(eventCount, pace) -> seconds    base time per event (the 2D viewer's pace)
	  BattleStage.Pause(ev, step, pace) -> seconds      the time after one event
	  BattleStage.Length(events, pace) -> seconds       the whole replay at 1x (lead + events + tail)
	  BattleStage.Shots(events, units, cfg) -> { [eventIndex] = { kind, actor, target } }
	      camera cuts: "wide" at the first event, "shoulder" behind the attacker on a big hit (crit,
	      special, or `bigHit` of the target's max HP), "close" on the finishing blow's target (the
	      hit before the last KO), "wide" again `hold` seconds after a shoulder / close shot; never
	      two cuts closer than `minCut` seconds (the finishing blow always gets its close-up)
	  BattleStage.FinishingBlow(events) -> index?       the hit that caused the fight's last KO
	  BattleStage.Limiter(live, perSecond) -> limiter   limiter:Take(now, priority?) -> boolean
	      at most `perSecond` new ones in any second (priority ignores the rate), at most `live`
	      alive at once: limiter:Done() when one ends. limiter.alive, limiter.taken (counters)
	  BattleStage.Caps(cfg, low) -> { bolts, numbers, sparks }   the { live, perSecond } per kind
	  BattleStage.NewState(units) -> state               { hp, shield, stunned, fainted }
	  BattleStage.Apply(state, ev) -> subject?           one event on the HP / shield / stun state
	      (the same rules as the 2D viewer); returns the key whose bar changed
	  BattleStage.Floater(ev, amountText) -> { text, color, big }?   the floating number for an
	      event (color is a Theme.Colors key); nil when the event shows none
	  BattleStage.Attacks(kind) -> boolean               the actor lunges and a bolt flies
	  BattleStage.Hurts(kind) -> boolean                 the target flinches
]]

local BattleStage = {}

local ATTACKS = { hit = true, crit = true, special = true, stun = true, miss = true }
local HURTS = { hit = true, crit = true, special = true, stun = true, reflect = true }
local DAMAGES = { hit = true, crit = true, special = true, reflect = true, stun = true }
local LONGER = { special = true, crit = true, faint = true }

function BattleStage.Choose(info, cfg): (string, string)
	if not info.cameraFree then
		return "2d", "camera"
	end
	if info.low and (info.units or 0) > cfg.fallback.lowMaxUnits then
		return "2d", "low"
	end
	if type(info.frameMs) == "number" and info.frameMs > cfg.fallback.maxFrameMs then
		return "2d", "slow"
	end
	return "3d", "ok"
end

function BattleStage.Theme(cfg, stageKey: string?)
	local themes = cfg.themes
	return (stageKey and themes[stageKey]) or themes.default
end

function BattleStage.Row(count: number, layout)
	local spots = {}
	local perRow = math.max(1, layout.perRow)
	local rows = math.max(1, math.ceil(count / perRow))
	local placed = 0
	for r = 1, rows do
		-- The front row takes the larger half, so 5 = 3 + 2 and 8 = 4 + 4.
		local left = count - placed
		local inRow = math.ceil(left / (rows - r + 1))
		-- A back row sits in the gaps of the one in front (half a step sideways).
		local shift = if r % 2 == 0 and inRow < perRow then layout.spacing * 0.5 else 0
		for i = 1, inRow do
			local across = (i - (inRow + 1) / 2) * layout.spacing + shift
			table.insert(spots, { back = (r - 1) * layout.rowDepth, across = across })
		end
		placed += inRow
	end
	return spots
end

function BattleStage.Placement(units, cfg)
	local layout = cfg.layout
	local sides = { ally = {}, enemy = {} }
	for _, unit in units or {} do
		local side = if unit.side == "enemy" then "enemy" else "ally"
		table.insert(sides[side], unit)
	end
	local out = {}
	for side, list in sides do
		local sign = if side == "enemy" then 1 else -1
		local bosses, others = {}, {}
		for _, unit in list do
			table.insert(if unit.boss then bosses else others, unit)
		end
		local spots = BattleStage.Row(#others, layout)
		local depth = 0
		for i, unit in others do
			local spot = spots[i]
			depth = math.max(depth, spot.back)
			out[unit.key] = { x = sign * (layout.front + spot.back), z = spot.across, scale = 1, boss = false, side = side }
		end
		-- Bosses stand behind their row (centred; several spread out).
		local bossBack = if #others > 0 then depth + layout.bossBack + layout.rowDepth * 0.5 else layout.bossBack
		for i, unit in bosses do
			local across = (i - (#bosses + 1) / 2) * layout.spacing * 2
			out[unit.key] = { x = sign * (layout.front + bossBack), z = across, scale = cfg.scale.boss, boss = true, side = side }
		end
	end
	return out
end

function BattleStage.Size(scaleFor: number, boss: boolean?, cfg): number
	local s = math.max(scaleFor, 0.01)
	local shown = math.clamp(s, cfg.scale.min, cfg.scale.max)
	local size = cfg.scale.unit * shown / s
	if boss then
		size *= cfg.scale.boss
	end
	return size
end

function BattleStage.Step(eventCount: number, pace): number
	return math.clamp(pace.budget / math.max(1, eventCount), pace.min, pace.max)
end

function BattleStage.Pause(ev, step: number, pace): number
	if ev and LONGER[ev.kind] then
		return step + pace.extra
	end
	return step
end

function BattleStage.Length(events, pace): number
	local step = BattleStage.Step(#(events or {}), pace)
	local total = pace.lead + pace.tail
	for _, ev in events or {} do
		total += BattleStage.Pause(ev, step, pace)
	end
	return total
end

function BattleStage.FinishingBlow(events): number?
	local list = events or {}
	for i = #list, 1, -1 do
		if list[i].kind == "faint" then
			local target = list[i].target or list[i].actor
			for j = i - 1, 1, -1 do
				local ev = list[j]
				if DAMAGES[ev.kind] and (ev.target or ev.actor) == target then
					return j
				end
			end
			return i
		end
	end
	return nil
end

function BattleStage.Shots(events, units, cfg)
	local cam = cfg.camera
	local list = events or {}
	local maxHp = {}
	for _, unit in units or {} do
		maxHp[unit.key] = math.max(1, unit.maxHp or 1)
	end
	local step = BattleStage.Step(#list, cfg.pace)
	local finish = BattleStage.FinishingBlow(list)
	local shots = {}
	local t = cfg.pace.lead
	local lastCut = -math.huge
	local wideAt = nil -- when the wide comes back after a shoulder / close shot
	for i, ev in list do
		local kind = nil
		if i == 1 then
			kind = "wide"
		elseif i == finish then
			kind = "close"
		elseif ATTACKS[ev.kind] and ev.kind ~= "miss" and ev.target and t - lastCut >= cam.minCut then
			local big = ev.kind == "crit" or ev.kind == "special" or (ev.amount or 0) >= cam.bigHit * (maxHp[ev.target] or math.huge)
			if big then
				kind = "shoulder"
			end
		end
		if not kind and wideAt and t >= wideAt and t - lastCut >= cam.minCut * 0.5 then
			kind = "wide"
		end
		if kind then
			shots[i] = { kind = kind, actor = ev.actor, target = if ev.target then ev.target else ev.actor }
			lastCut = t
			wideAt = if kind == "wide" then nil else t + cam.hold
		end
		t += BattleStage.Pause(ev, step, cfg.pace)
	end
	return shots
end

function BattleStage.Limiter(live: number, perSecond: number)
	local limiter = { alive = 0, taken = 0, live = live, perSecond = perSecond, stamps = {} }
	function limiter:Take(now: number, priority: boolean?): boolean
		if self.live <= 0 then
			return false
		end
		if self.alive >= self.live then
			return false
		end
		local stamps = self.stamps
		while #stamps > 0 and now - stamps[1] >= 1 do
			table.remove(stamps, 1)
		end
		if not priority and #stamps >= self.perSecond then
			return false
		end
		table.insert(stamps, now)
		self.alive += 1
		self.taken += 1
		return true
	end
	function limiter:Done()
		self.alive = math.max(0, self.alive - 1)
	end
	return limiter
end

function BattleStage.Caps(cfg, low: boolean)
	local caps = cfg.caps
	if low then
		return caps.low
	end
	return { bolts = caps.bolts, numbers = caps.numbers, sparks = caps.sparks }
end

function BattleStage.NewState(units)
	local state = { hp = {}, maxHp = {}, shield = {}, stunned = {}, fainted = {} }
	for _, unit in units or {} do
		state.hp[unit.key] = unit.maxHp or 0
		state.maxHp[unit.key] = math.max(1, unit.maxHp or 1)
		state.shield[unit.key] = 0
	end
	return state
end

function BattleStage.Apply(state, ev): string?
	local kind = ev.kind
	local target = if ev.target then ev.target else ev.actor
	local subject = if kind == "regen" or kind == "stunned" then ev.actor else target
	if not subject then
		return nil
	end
	if kind == "shield" then
		state.shield[subject] = (state.shield[subject] or 0) + (ev.amount or 0)
	elseif kind == "stun" then
		state.stunned[subject] = true
	elseif kind == "stunned" then
		state.stunned[subject] = nil
	end
	if DAMAGES[kind] then
		local before = state.hp[subject] or 0
		local lost = math.max(0, before - (ev.hp or before))
		local absorbed = math.max(0, (ev.amount or 0) - lost)
		state.shield[subject] = math.max(0, (state.shield[subject] or 0) - absorbed)
	end
	if kind == "faint" then
		state.hp[subject] = 0
	elseif type(ev.hp) == "number" and state.hp[subject] ~= nil then
		state.hp[subject] = ev.hp
	end
	if (state.hp[subject] or 1) <= 0 then
		state.fainted[subject] = true
		state.stunned[subject] = nil
	end
	return subject
end

-- The same words as the 2D viewer (already in the Locale catalogues).
function BattleStage.Floater(ev, amount: string)
	local kind = ev.kind
	if kind == "hit" or kind == "special" then
		return { text = "-" .. amount, color = "White", big = false }
	elseif kind == "crit" then
		return { text = "CRIT -" .. amount, color = "Gold", big = true }
	elseif kind == "reflect" then
		return { text = "Thorns -" .. amount, color = "Pink", big = false }
	elseif kind == "miss" then
		return { text = "MISS", color = "Gray", big = false }
	elseif kind == "heal" or kind == "regen" then
		return { text = "+" .. amount, color = "Green", big = false }
	elseif kind == "shield" then
		return { text = "SHIELD +" .. amount, color = "Blue", big = false }
	elseif kind == "stun" then
		return { text = if (ev.amount or 0) > 0 then "STUN -" .. amount else "STUNNED!", color = "Gold", big = true }
	elseif kind == "stunned" then
		return { text = "Stunned…", color = "Gold", big = false }
	elseif kind == "faint" then
		return { text = "KO", color = "Red", big = true }
	end
	return nil
end

function BattleStage.Attacks(kind: string): boolean
	return ATTACKS[kind] == true
end

function BattleStage.Hurts(kind: string): boolean
	return HURTS[kind] == true
end

return BattleStage
