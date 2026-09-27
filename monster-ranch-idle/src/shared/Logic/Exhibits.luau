--[[
	Logic/Exhibits (update 3.12 · Honey & stars): pure rules for Museum Exhibits (Config/Exhibits).
	Shared by Systems/Exhibits, the Exhibits screen and Controllers/CuratorWing.

	  Exhibits.Items(Config, setId) -> { { id, name, color, color2? } }?   nil = the set is hidden
	      (its source config is missing: Config.Apiary / Config.Observatory before they ship)
	  Exhibits.Sets(Config) -> { setDef }                    the sets shown, in order
	  Exhibits.Count(Config, setId, filled) -> (have, total) filled = profile.Exhibits.filled
	  Exhibits.Need(Steps, total, step) -> number            items needed for reward step 1..3
	  Exhibits.Reward(Config, total, step) -> (gems, stardust)
	  Exhibits.Claimable(Config, setId, filled, paid) -> step?   the next step reached and unpaid
	  Exhibits.Appeal(Config, filled) -> number              Tourist appeal points (0..AppealMax)
	  Exhibits.Layout(Config) -> { pedestals = { { set, item, line, x, z, y } }, desk = { x, z },
	                               rows = { { set, x, z } }, bounds = { minX, maxX, minZ, maxZ } }
]]

local Exhibits = {}

local function kindEntry(k, fallbackColor: string)
	if type(k) == "string" then
		return { id = k, name = k, color = fallbackColor }
	elseif type(k) == "table" and type(k.id) == "string" then
		return { id = k.id, name = k.name or k.id, color = k.color or fallbackColor }
	end
	return nil
end

local function decorEntry(Config, id: string)
	local d = Config.Decor and Config.Decor.ById[id]
	if not d then
		return nil
	end
	return { id = id, name = d.name, color = d.color, color2 = d.color2 }
end

function Exhibits.Items(Config, setId: string)
	local set = Config.Exhibits.ById[setId]
	if not set or Config[set.config] == nil then
		return nil
	end
	local out = {}
	if setId == "fossils" then
		for _, f in Config.DigSite.Fossils do
			table.insert(out, { id = f.id, name = f.name, color = f.color })
		end
	elseif setId == "aquarium" then
		for _, f in Config.Fishing.Fish do
			table.insert(out, { id = f.id, name = f.name, color = f.color })
		end
	elseif setId == "relics" then
		local seen = {}
		local function add(id)
			if type(id) == "string" and not seen[id] then
				local entry = decorEntry(Config, id)
				if entry then
					seen[id] = true
					table.insert(out, entry)
				end
			end
		end
		for _, r in (Config.DigSite and Config.DigSite.Relics) or {} do
			add(r.id)
		end
		for _, r in (Config.Fishing and Config.Fishing.Decor) or {} do
			add(r.id)
		end
		for _, id in (Config.Merchant and Config.Merchant.Decor) or {} do
			add(id)
		end
	elseif setId == "honey" then
		local A = Config.Apiary
		for _, k in (type(A.Kinds) == "table" and A.Kinds) or {} do
			local entry = kindEntry(k, set.color)
			if entry then
				table.insert(out, entry)
			end
		end
		local jelly = kindEntry(A.RoyalJelly, "#FFF1C2")
		if jelly then
			table.insert(out, jelly)
		end
	elseif setId == "stars" then
		for _, chart in (type(Config.Observatory.Charts) == "table" and Config.Observatory.Charts) or {} do
			local entry = kindEntry(chart, set.color)
			if entry then
				table.insert(out, entry)
			end
		end
	end
	if #out == 0 then
		return nil
	end
	return out
end

function Exhibits.Sets(Config)
	local out = {}
	for _, set in Config.Exhibits.Sets do
		if Exhibits.Items(Config, set.id) then
			table.insert(out, set)
		end
	end
	return out
end

function Exhibits.Count(Config, setId: string, filled): (number, number)
	local items = Exhibits.Items(Config, setId)
	if not items then
		return 0, 0
	end
	local mine = type(filled) == "table" and filled[setId]
	local have = 0
	if type(mine) == "table" then
		for _, item in items do
			if mine[item.id] == true then
				have += 1
			end
		end
	end
	return have, #items
end

function Exhibits.Need(Steps, total: number, step: number): number
	return math.max(1, math.ceil(total * Steps[step] - 1e-9))
end

function Exhibits.Reward(Config, total: number, step: number): (number, number)
	local C = Config.Exhibits
	local share = C.Share[step] or 0
	return math.ceil(total * C.GemsPerItem * share - 1e-9), math.ceil(total * C.StardustPerItem * share - 1e-9)
end

function Exhibits.Claimable(Config, setId: string, filled, paid): number?
	local have, total = Exhibits.Count(Config, setId, filled)
	if total == 0 then
		return nil
	end
	local done = if type(paid) == "table" and type(paid[setId]) == "number" then paid[setId] else 0
	local step = done + 1
	if step > #Config.Exhibits.Steps then
		return nil
	end
	if have >= Exhibits.Need(Config.Exhibits.Steps, total, step) then
		return step
	end
	return nil
end

function Exhibits.Appeal(Config, filled): number
	local have, total = 0, 0
	for _, set in Config.Exhibits.Sets do
		local h, t = Exhibits.Count(Config, set.id, filled)
		have += h
		total += t
	end
	if total == 0 then
		return 0
	end
	return math.min(Config.Exhibits.AppealMax, math.floor(Config.Exhibits.AppealMax * have / total + 1e-9))
end

function Exhibits.Layout(Config)
	local W = Config.Exhibits.Wing
	local ground = Config.World.CuratorWing
	local cx, cz = ground.center[1], ground.center[2]
	local halfW, halfD = ground.size[1] / 2, ground.size[2] / 2
	local north = cz + halfD -- the open entrance side (+z, facing the museum's entrance road)
	local pedestals, rows = {}, {}
	local z = north - W.front
	for _, set in Exhibits.Sets(Config) do
		local items = Exhibits.Items(Config, set.id) :: any
		table.insert(rows, { set = set.id, x = cx, z = z + W.rowGap * 0.55 })
		local n = #items
		for i, item in items do
			local row = (i - 1) // W.perRow
			local col = (i - 1) % W.perRow
			local inRow = math.min(W.perRow, n - row * W.perRow)
			local x = cx + (col - (inRow - 1) / 2) * W.spacing
			table.insert(pedestals, {
				set = set.id,
				item = item.id,
				line = set.id .. ":" .. item.id,
				x = x,
				z = z - row * W.rowGap,
				y = Config.World.GroundY or 0,
			})
		end
		z -= (math.ceil(n / W.perRow) - 1) * W.rowGap + W.rowGap + W.setGap
	end
	local minZ = math.huge
	for _, p in pedestals do
		minZ = math.min(minZ, p.z - W.pedestal[3] / 2)
	end
	return {
		pedestals = pedestals,
		rows = rows,
		desk = { x = cx, z = north - 4 },
		bounds = { minX = cx - halfW, maxX = cx + halfW, minZ = cz - halfD, maxZ = north, lastZ = minZ },
	}
end

return Exhibits
