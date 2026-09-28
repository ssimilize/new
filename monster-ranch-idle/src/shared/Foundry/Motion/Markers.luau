--!strict
-- Markers: named events on a clip's timeline, which ones a step of play time crosses, and the
-- binding table that turns them into sounds and effects.
--
--   Markers.crossed(doc, t0, t1, loop?, opts?) -> { { name, t, clipT } }   (t0, t1], sorted
--   Markers.bind(events, bindings) -> events with sound / fx / volume attached
--   Markers.checkBindings(bindings, known?) -> problems
--
-- Crossing rules (play time, not clip time):
--   * t0 exclusive, t1 inclusive, so consecutive steps never fire a marker twice;
--   * a zero-length step (t1 == t0) and a step backwards (t1 < t0, a seek back) fire nothing;
--   * a loop fires each marker once per lap it crosses, including the lap wrap; a marker at
--     t = length on a loop is the same instant as t = 0 of the next lap and fires once;
--   * a step longer than a lap (a frame hitch) fires each marker at most ONCE, at its latest
--     crossing, so a hitch never machine-guns footsteps;
--   * opts.seek = true: a deliberate jump (scrubbing, a resync): fires nothing.
-- One-shots fire each marker at most once, when t crosses it.
--
-- Binding table format (a Luau table or JSON object), shared with the Foley Binder (SO3) and
-- FX presets:
--   { [markerName] = { sound = "<sound ref>"?, fx = "<fx preset ref>"?, volume = 0..2?,
--                      pitch = { lo, hi }?, chance = 0..1?, note = "..."? } }
-- `sound` / `fx` are refs in the game's own sound and effect libraries (the binder resolves
-- them); a marker with no row is silent. bindings/<game>.luau hold examples.

local Markers = {}

-- The shared vocabulary. Clips may carry other names (Guildhall's brush, pour, puff ...);
-- `vocabulary` lists them as notes, never as errors, so every game clip still converts.
Markers.NAMES = table.freeze({ "foot.l", "foot.r", "hit", "swish", "pickup", "drop", "sit", "talk" })
local NAME_SET: { [string]: boolean } = {}
for _, n in Markers.NAMES do
	NAME_SET[n] = true
end

function Markers.isStandard(name: string): boolean
	return NAME_SET[name] == true
end

-- vocabulary(doc) -> the marker names on a clip that are not in NAMES (sorted, unique).
function Markers.vocabulary(doc: any): { string }
	local seen, out = {}, {}
	for _, m in doc.markers or {} do
		if not NAME_SET[m.name] and not seen[m.name] then
			seen[m.name] = true
			table.insert(out, m.name)
		end
	end
	table.sort(out)
	return out
end

function Markers.crossed(doc: any, t0: number, t1: number, loop: boolean?, opts: any?): { any }
	local out = {}
	local markers = doc.markers
	if type(markers) ~= "table" or #markers == 0 or not (t1 > t0) then
		return out
	end
	if opts and opts.seek then
		return out
	end
	local lp = if loop == nil then doc.loop == true else loop
	local length = doc.length
	if not lp or length <= 0 then
		for _, m in markers do
			if m.t > t0 and m.t <= t1 then
				table.insert(out, { name = m.name, t = m.t, clipT = m.t })
			end
		end
	else
		local hitch = t1 - t0 > length
		local seen: { [string]: boolean } = {}
		for _, m in markers do
			local ct = m.t % length -- t = length on a loop is t = 0 of the next lap
			local key = m.name .. "@" .. ct
			if seen[key] then
				continue
			end
			seen[key] = true
			local at = math.floor((t1 - ct) / length) * length + ct -- latest crossing <= t1
			while at > t0 do
				table.insert(out, { name = m.name, t = at, clipT = ct })
				if hitch then
					break
				end
				at -= length
			end
		end
	end
	table.sort(out, function(a, b)
		if a.t ~= b.t then
			return a.t < b.t
		end
		return a.name < b.name
	end)
	return out
end

-- bind(events, bindings) -> a copy of each event with its binding row's fields added.
-- Unbound events keep only name / t (silent).
function Markers.bind(events: { any }, bindings: { [string]: any }?): { any }
	local out = {}
	for _, e in events do
		local row = bindings and bindings[e.name]
		local ev = { name = e.name, t = e.t, clipT = e.clipT }
		if type(row) == "table" then
			for k, v in row do
				if k ~= "note" then
					ev[k] = v
				end
			end
		end
		table.insert(out, ev)
	end
	return out
end

local ROW_FIELDS = { sound = "string", fx = "string", volume = "number", pitch = "table", chance = "number", note = "string" }

-- checkBindings(bindings, known?) -> problems. `known` (a set of marker names) additionally
-- flags rows for markers no clip carries.
function Markers.checkBindings(b: any, known: { [string]: boolean }?): { string }
	local errs = {}
	if type(b) ~= "table" then
		return { "bindings: not a table" }
	end
	for name, row in b do
		local w = "binding '" .. tostring(name) .. "'"
		if type(name) ~= "string" then
			table.insert(errs, w .. ": the key must be a marker name")
			continue
		end
		if type(row) ~= "table" then
			table.insert(errs, w .. ": the row must be a table")
			continue
		end
		if row.sound == nil and row.fx == nil then
			table.insert(errs, w .. ": needs a sound or an fx")
		end
		for k, v in row do
			local want = ROW_FIELDS[k]
			if want == nil then
				table.insert(errs, w .. ": unknown field '" .. tostring(k) .. "'")
			elseif type(v) ~= want then
				table.insert(errs, w .. ": " .. k .. " must be a " .. want)
			end
		end
		if type(row.volume) == "number" and (row.volume < 0 or row.volume > 2) then
			table.insert(errs, w .. ": volume must be 0..2")
		end
		if type(row.chance) == "number" and (row.chance < 0 or row.chance > 1) then
			table.insert(errs, w .. ": chance must be 0..1")
		end
		if type(row.pitch) == "table" and not (type(row.pitch[1]) == "number" and type(row.pitch[2]) == "number" and row.pitch[1] <= row.pitch[2]) then
			table.insert(errs, w .. ": pitch must be { lo, hi } with lo <= hi")
		end
		if known and not known[name] then
			table.insert(errs, w .. ": no clip carries this marker")
		end
	end
	table.sort(errs)
	return errs
end

return Markers
