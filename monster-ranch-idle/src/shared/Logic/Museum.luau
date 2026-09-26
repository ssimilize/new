--[[
	Logic/Museum (glow-up O): pure rules for the walk-in Codex Museum and the Hall of Fame plaza,
	kept out of the controllers so they are unit-tested (tests/specs/Codex.spec.luau).

	  Museum.Layout(Config) -> { wings, pedestals, bounds }
	      wings     = { { id, element?, title, x, z, lines = { lineId } } }  (a sign stands at x, z)
	      pedestals = { { index, line, wing, x, y, z } }                    one per species line
	      bounds    = { minX, maxX, minZ, maxZ }                            the hall floor
	  Museum.Plan(pedestals, camX, camZ, known, opts, out, scratch) -> out
	      out[i] = "model" | "sign" | "plate" for pedestal i. Undiscovered lines are always "plate"
	      (a silhouette plate); discovered ones nearest the camera get up to opts.max models within
	      opts.modelRange (a model already shown ranks as if 15% closer, so the set does not flicker
	      at the edge), then "sign" within opts.signRange. `out` and `scratch` are reused tables
	      so a pass allocates nothing once warm.
	  Museum.newPool(cap, destroy) -> pool   :Take(key) -> obj?  :Give(key, obj)  :Size()  :Clear()
	      keeps up to `cap` spare objects by key (a model per form); the oldest spare is destroyed.
	  Museum.BestStatue(entries) -> entry?   highest rarity, newest first (entries are newest first)
	  Museum.FreeSlot(plaza, max) -> slot?   lowest plaza slot no statue holds
	  Museum.PlazaSpot(Config, slot) -> x, y, z
]]

local Museum = {}

local function wingDefs(Config)
	local wings = {}
	local byElement = {}
	for _, el in Config.Elements.List do
		local w = { id = el.id, element = el.id, title = el.name, lines = {} }
		byElement[el.id] = w
		table.insert(wings, w)
	end
	local hybrid = { id = "hybrid", title = "Hybrids", lines = {} }
	local event = { id = "event", title = "Event", lines = {} }
	for _, def in Config.Species.Lines do
		if def.event then
			table.insert(event.lines, def.id)
		elseif def.hybrid then
			table.insert(hybrid.lines, def.id)
		elseif byElement[def.elements[1]] then
			table.insert(byElement[def.elements[1]].lines, def.id)
		end
	end
	table.insert(wings, hybrid)
	table.insert(wings, event)
	local out = {}
	for _, w in wings do
		if #w.lines > 0 then
			table.insert(out, w)
		end
	end
	return out
end

function Museum.Layout(Config)
	local M = Config.Codex.Museum
	local ox, oy, oz = M.origin[1], M.origin[2], M.origin[3]
	local wings = wingDefs(Config)
	local perRow = math.max(1, M.wingsPerRow or 5)
	local rows = M.rowsPerWing
	-- Every wing row is as deep as its deepest wing.
	local rowDepth = {}
	for i, w in wings do
		local r = (i - 1) // perRow + 1
		local depth = math.ceil(#w.lines / rows) * M.spacing
		rowDepth[r] = math.max(rowDepth[r] or 0, depth)
	end
	local pedestals = {}
	local z = oz - 8 -- the entrance hall
	local lastRow = 0
	local minX, maxX = math.huge, -math.huge
	for i, w in wings do
		local r = (i - 1) // perRow + 1
		local col = (i - 1) % perRow
		if r ~= lastRow then
			if lastRow > 0 then
				z -= rowDepth[lastRow] + 10
			end
			lastRow = r
		end
		local inRow = math.min(perRow, #wings - (r - 1) * perRow)
		w.x = ox + (col - (inRow - 1) / 2) * M.wingWidth
		w.z = z
		minX = math.min(minX, w.x - M.wingWidth / 2)
		maxX = math.max(maxX, w.x + M.wingWidth / 2)
		for li, lineId in w.lines do
			local c = (li - 1) % rows
			local depthIndex = (li - 1) // rows
			local x = w.x + (c - (rows - 1) / 2) * (M.wingWidth / rows)
			table.insert(pedestals, {
				index = #pedestals + 1,
				line = lineId,
				wing = w.id,
				x = x,
				y = oy,
				z = z - 4 - depthIndex * M.spacing,
			})
		end
	end
	local minZ = z - (rowDepth[lastRow] or 0) - 6
	return {
		wings = wings,
		pedestals = pedestals,
		bounds = { minX = minX - 4, maxX = maxX + 4, minZ = minZ, maxZ = oz },
	}
end

function Museum.Plan(pedestals, camX: number, camZ: number, known, opts, out, scratch)
	local modelRange, signRange = opts.modelRange, opts.signRange
	local n = 0
	for i, p in pedestals do
		if not known[p.line] then
			out[i] = "plate"
		else
			local dx, dz = p.x - camX, p.z - camZ
			local d = math.sqrt(dx * dx + dz * dz)
			out[i] = if d <= signRange then "sign" else "plate"
			if out[i] == "sign" then
				-- A model already up ranks closer so the nearest set is stable at the range edge.
				local rank = if opts.previous and opts.previous[i] == "model" then d * 0.85 else d
				if rank <= modelRange then
					n += 1
					local slot = scratch[n]
					if not slot then
						slot = { 0, 0 }
						scratch[n] = slot
					end
					slot[1], slot[2] = rank, i
				end
			end
		end
	end
	for i = #out, #pedestals + 1, -1 do
		out[i] = nil
	end
	-- Partial selection: the `max` nearest candidates become models (n is small).
	local picks = math.min(n, opts.max)
	for k = 1, picks do
		local best = k
		for j = k + 1, n do
			if scratch[j][1] < scratch[best][1] then
				best = j
			end
		end
		scratch[k], scratch[best] = scratch[best], scratch[k]
		out[scratch[k][2]] = "model"
	end
	return out
end

function Museum.newPool(cap: number, destroy: (any) -> ())
	local spares = {} -- { { key, obj } } oldest first
	local pool = {}
	function pool:Take(key)
		for i = #spares, 1, -1 do
			if spares[i][1] == key then
				local obj = spares[i][2]
				table.remove(spares, i)
				return obj
			end
		end
		return nil
	end
	function pool:Give(key, obj)
		table.insert(spares, { key, obj })
		while #spares > cap do
			local old = table.remove(spares, 1)
			destroy(old[2])
		end
	end
	function pool:Size(): number
		return #spares
	end
	function pool:Clear()
		for _, s in spares do
			destroy(s[2])
		end
		table.clear(spares)
	end
	return pool
end

function Museum.BestStatue(entries)
	local best
	for _, e in entries or {} do
		if type(e) == "table" and type(e.appearance) == "table" then
			if not best or (tonumber(e.rarity) or 0) > (tonumber(best.rarity) or 0) then
				best = e
			end
		end
	end
	return best
end

function Museum.FreeSlot(plaza, max: number): number?
	local used = {}
	for _, entry in plaza or {} do
		if type(entry) == "table" and entry.slot then
			used[entry.slot] = true
		end
	end
	for slot = 1, max do
		if not used[slot] then
			return slot
		end
	end
	return nil
end

function Museum.PlazaSpot(Config, slot: number): (number, number, number)
	local P = Config.Codex.Plaza
	local col = (slot - 1) % P.perRow
	local row = (slot - 1) // P.perRow
	local x = P.origin[1] + (col - (P.perRow - 1) / 2) * P.spacing
	local z = P.origin[3] - 8 - row * P.rowGap
	return x, P.origin[2], z
end

return Museum
