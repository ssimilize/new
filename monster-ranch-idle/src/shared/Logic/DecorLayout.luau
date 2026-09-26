--[[
	DecorLayout (glow-up Z · Build your ranch): the pure placement rules, shared by the server
	(Systems/Decor validates every save) and the client (placement mode shows bad spots in red).

	A layout is a list of entries { id, x, z, rot }: id a Config.Decor piece, x/z plot-local grid
	units (Config.Decor.Layout.grid studs each) from the plot centre in the plot's own frame
	(+x toward the gate), rot 0..7 in 45° steps. Footprints are the axis-aligned box round the
	rotated `size`. A piece must stay inside the plot (less `edge`), off every keep-out (aisle,
	gate, incubator pad, barn, statue row, garden), either wholly inside a pen's floor (clear of
	its rails and prop spots) or wholly clear of the pen, and off every other piece of its layer
	(flat pieces like paths only meet flat pieces).

	  DecorLayout.Cap(level) -> pieces allowed at that Ranch Level
	  DecorLayout.Half(def, rot) -> hx, hz          studs
	  DecorLayout.Stud(entry) -> x, z               plot-local studs of the centre
	  DecorLayout.Check(entry) -> err?              one piece on its own
	  DecorLayout.Overlaps(a, b) -> boolean
	  DecorLayout.Problems(list) -> { [i] = err }   every bad entry (placement mode's red)
	  DecorLayout.Validate(list, level, available) -> ok, err?, index?
	                                                available[id] = copies the player owns in all
	  DecorLayout.Counts(list) -> { [id] = n }
	  DecorLayout.PenOf(entry) -> pen index | nil   the pen floor holding the piece's centre
	  DecorLayout.PenDecor(list, pen, perPen) -> { id }   mood pieces standing in that pen (best first)
	  DecorLayout.FreeSpot(list, id, x, z, rot?) -> x?, z?   nearest valid free spot to (x, z)
	  DecorLayout.Migrate(pens, list) -> placed, leftover   old slot decor { [pen] = { id } } onto the
	                                                layout at the old slot spots (or the nearest free
	                                                spot); leftover ids go back to storage
	  DecorLayout.Clean(list) -> list               copies known ids with whole numbers only
	  DecorLayout.Same(a, b) -> boolean             entry equality (the client's diff)
]]

local Config = require(script.Parent.Parent.Config)

local DecorLayout = {}

local L = Config.Decor.Layout
local W = Config.World
local G = L.grid
local SQRT2 = math.sqrt(2)

DecorLayout.MaxX = math.floor((W.PlotSize[1] / 2) / G)
DecorLayout.MaxZ = math.floor((W.PlotSize[2] / 2) / G)

-- Pen rects and their prop spots (plot-local studs).
local PENS = {}
for i, o in W.PenOffsets do
	PENS[i] = { cx = o[1], cz = o[3], hx = W.PenSize[1] / 2, hz = W.PenSize[2] / 2 }
end
local PROP_SPOTS = {}
do
	local P = Config.Pens
	for _, s in P.ThemeSpots or {} do
		table.insert(PROP_SPOTS, s)
	end
	if P.HabitatSpot then
		table.insert(PROP_SPOTS, P.HabitatSpot)
	end
	for _, u in P.Upgrades or {} do
		table.insert(PROP_SPOTS, u.at)
	end
end

local function hits(ax: number, az: number, ahx: number, ahz: number, bx: number, bz: number, bhx: number, bhz: number): boolean
	return math.abs(ax - bx) < ahx + bhx - 1e-6 and math.abs(az - bz) < ahz + bhz - 1e-6
end

function DecorLayout.Cap(level: number?): number
	local lv = math.max(1, math.floor(tonumber(level) or 1))
	return math.min(L.capMax, L.capBase + L.capStep * math.floor(lv / L.capEvery))
end

function DecorLayout.Half(def, rot: number?): (number, number)
	local w, d = def.size[1], def.size[2]
	local r = math.floor(tonumber(rot) or 0) % 8
	if r % 2 == 1 then
		local s = (w + d) / (2 * SQRT2)
		return s, s
	end
	if r % 4 == 2 then
		w, d = d, w
	end
	return w / 2, d / 2
end

function DecorLayout.Stud(entry): (number, number)
	return entry.x * G, entry.z * G
end

local function box(entry)
	local def = Config.Decor.ById[entry.id]
	local hx, hz = DecorLayout.Half(def, entry.rot)
	local x, z = DecorLayout.Stud(entry)
	return x, z, hx, hz, def
end

function DecorLayout.PenOf(entry): number?
	local x, z = DecorLayout.Stud(entry)
	for i, pen in PENS do
		if math.abs(x - pen.cx) < pen.hx and math.abs(z - pen.cz) < pen.hz then
			return i
		end
	end
	return nil
end

function DecorLayout.Check(entry): string?
	local def = type(entry) == "table" and Config.Decor.ById[entry.id]
	if not def then
		return "That decor doesn't exist"
	end
	local x, z, hx, hz = box(entry)
	local px, pz = W.PlotSize[1] / 2 - L.edge, W.PlotSize[2] / 2 - L.edge
	if math.abs(x) + hx > px + 1e-6 or math.abs(z) + hz > pz + 1e-6 then
		return "That spot is outside your ranch"
	end
	for _, k in L.keepOut do
		if hits(x, z, hx, hz, k[1], k[2], k[3], k[4]) then
			return "That spot is blocked"
		end
	end
	for _, pen in PENS do
		local ix, iz = pen.hx - L.penInset, pen.hz - L.penInset
		local inside = math.abs(x - pen.cx) + hx <= ix + 1e-6 and math.abs(z - pen.cz) + hz <= iz + 1e-6
		if inside then
			for _, s in PROP_SPOTS do
				if hits(x, z, hx, hz, pen.cx + s[1], pen.cz + s[2], L.propClear, L.propClear) then
					return "That spot is blocked"
				end
			end
		elseif hits(x, z, hx, hz, pen.cx, pen.cz, pen.hx + L.penOutset, pen.hz + L.penOutset) then
			return "Keep decor clear of the pen fences"
		end
	end
	return nil
end

function DecorLayout.Overlaps(a, b): boolean
	local ax, az, ahx, ahz, adef = box(a)
	local bx, bz, bhx, bhz, bdef = box(b)
	if (adef.flat == true) ~= (bdef.flat == true) then
		return false
	end
	return hits(ax, az, ahx, ahz, bx, bz, bhx, bhz)
end

function DecorLayout.Problems(list): { [number]: string }
	local out = {}
	for i, entry in list do
		local err = DecorLayout.Check(entry)
		if err then
			out[i] = err
		end
	end
	for i = 1, #list do
		if not out[i] then
			for j = 1, #list do
				if j ~= i and not (out[j] and out[j] ~= "Decorations can't overlap") and DecorLayout.Overlaps(list[i], list[j]) then
					out[i] = "Decorations can't overlap"
					break
				end
			end
		end
	end
	return out
end

function DecorLayout.Counts(list): { [string]: number }
	local counts = {}
	for _, entry in list do
		counts[entry.id] = (counts[entry.id] or 0) + 1
	end
	return counts
end

function DecorLayout.Validate(list, level: number?, available: { [string]: number }): (boolean, string?, number?)
	local cap = DecorLayout.Cap(level)
	if #list > cap then
		return false, string.format("Your ranch holds up to %d decorations. Level up for more!", cap), nil
	end
	for id, n in DecorLayout.Counts(list) do
		if n > (available[id] or 0) then
			return false, "You don't own enough of that decor", nil
		end
	end
	for i, entry in list do
		local err = DecorLayout.Check(entry)
		if err then
			return false, err, i
		end
	end
	for i = 1, #list do
		for j = i + 1, #list do
			if DecorLayout.Overlaps(list[i], list[j]) then
				return false, "Decorations can't overlap", j
			end
		end
	end
	return true, nil, nil
end

function DecorLayout.PenDecor(list, pen: number, perPen: number): { string }
	local found = {}
	for _, entry in list do
		local def = Config.Decor.ById[entry.id]
		if def and (def.mood or 0) > 0 and DecorLayout.PenOf(entry) == pen then
			table.insert(found, entry.id)
		end
	end
	table.sort(found, function(a, b)
		local ma, mb = Config.Decor.ById[a].mood, Config.Decor.ById[b].mood
		if ma ~= mb then
			return ma > mb
		end
		return a < b
	end)
	local out = {}
	for i = 1, math.min(perPen, #found) do
		out[i] = found[i]
	end
	return out
end

local function fits(list, entry): boolean
	if DecorLayout.Check(entry) then
		return false
	end
	for _, other in list do
		if other ~= entry and DecorLayout.Overlaps(entry, other) then
			return false
		end
	end
	return true
end

function DecorLayout.FreeSpot(list, id: string, x: number, z: number, rot: number?): (number?, number?)
	if not Config.Decor.ById[id] then
		return nil, nil
	end
	local r = rot or 0
	local maxRing = math.max(DecorLayout.MaxX, DecorLayout.MaxZ) * 2
	for ring = 0, maxRing do
		for dx = -ring, ring do
			for dz = -ring, ring do
				if math.max(math.abs(dx), math.abs(dz)) == ring then
					local cx, cz = x + dx, z + dz
					if math.abs(cx) <= DecorLayout.MaxX and math.abs(cz) <= DecorLayout.MaxZ then
						local entry = { id = id, x = cx, z = cz, rot = r }
						if fits(list, entry) then
							return cx, cz
						end
					end
				end
			end
		end
	end
	return nil, nil
end

function DecorLayout.Migrate(pens, list): ({ any }, { string })
	local placed = table.clone(list or {})
	local leftover = {}
	for penIndex, ids in pens or {} do
		local pen = PENS[penIndex]
		for slot, id in ids do
			local spot = L.legacySpots[slot] or L.legacySpots[#L.legacySpots]
			if pen and Config.Decor.ById[id] then
				local gx = math.floor((pen.cx + spot[1] * pen.hx) / G + 0.5)
				local gz = math.floor((pen.cz + spot[2] * pen.hz) / G + 0.5)
				local x, z = DecorLayout.FreeSpot(placed, id, gx, gz, 0)
				if x then
					table.insert(placed, { id = id, x = x, z = z, rot = 0 })
				else
					table.insert(leftover, id)
				end
			elseif Config.Decor.ById[id] then
				table.insert(leftover, id)
			end
		end
	end
	return placed, leftover
end

function DecorLayout.Clean(list): { any }
	local out = {}
	for _, e in if type(list) == "table" then list else {} do
		if type(e) == "table" and Config.Decor.ById[e.id] and type(e.x) == "number" and type(e.z) == "number" then
			table.insert(out, { id = e.id, x = math.floor(e.x), z = math.floor(e.z), rot = math.floor(tonumber(e.rot) or 0) % 8 })
		end
	end
	return out
end

function DecorLayout.Same(a, b): boolean
	return a.id == b.id and a.x == b.x and a.z == b.z and (a.rot or 0) == (b.rot or 0)
end

return DecorLayout
