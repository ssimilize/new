--[[
	Companions (glow-up T): pure rules for the monsters that walk with their owner, shared by the
	server (Systems/Companions) and the client (Controllers/Companions, Controllers/Mounts).
	Tuning in Config/Companions.

	Companions.Slots(vip) -> number                          1, or 3 with VIP Rancher
	Companions.Migrate(section, fromVersion) -> section      v1 { id } → v2 { ids }, sanitised
	Companions.Clean(ids, max) -> { string }                 strings only, first of each, ≤ max
	Companions.Signature(appearance) -> string               what a drawn companion looks like
	Companions.Spot(index, height) -> (x, z)                 formation offset in the owner's space
	Companions.Speed(distance, ownerSpeed) -> number         how fast it trots towards its spot
	Companions.State(prev, distance, stillFor, hopLeft) -> "walk"|"idle"|"sit"|"hop"
	Companions.ClipRate(speed, height, length) -> number     walk clip seconds per real second
	Companions.Gait(speed, airborne) -> "walk"|"idle"|"hop"  a mount's state
	Companions.Pick(entries, cap, maxDistance) -> entries    nearest first, within range, ≤ cap
	  entries: { { distance: number, ... } } (sorted in place; the result is a new array)
]]

local Config = require(script.Parent.Parent.Config)

local Cfg = Config.Companions

local Companions = {}

function Companions.Slots(vip: boolean): number
	return if vip then Cfg.VipSlots else Cfg.Slots
end

function Companions.Clean(ids: any, max: number): { string }
	local out, seen = {}, {}
	if type(ids) ~= "table" then
		return out
	end
	for _, id in ipairs(ids) do
		if #out >= max then
			break
		end
		if type(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			table.insert(out, id)
		end
	end
	return out
end

-- v1 (the single-slot first cut) saved { id = monsterId|false }.
function Companions.Migrate(section: any, fromVersion: number): { ids: { string } }
	if type(section) ~= "table" then
		return { ids = {} }
	end
	if fromVersion < 2 then
		local ids = if type(section.ids) == "table" then section.ids else {}
		if type(section.id) == "string" then
			ids = { section.id }
		end
		section.id = nil
		section.ids = ids
	end
	section.ids = Companions.Clean(section.ids, Cfg.MaxSlots)
	return section
end

function Companions.Signature(ap: any): string
	if type(ap) ~= "table" then
		return ""
	end
	local acc = {}
	if type(ap.acc) == "table" then
		for _, slot in Config.Accessories.Slots do
			table.insert(acc, ap.acc[slot] or "-")
		end
	end
	return table.concat({
		tostring(ap.line),
		tostring(ap.form),
		tostring(ap.stage),
		tostring(ap.variant),
		tostring(ap.rarity),
		table.concat(if type(ap.muts) == "table" then ap.muts else {}, "+"),
		table.concat(acc, ","),
		tostring(ap.aura or "-"),
		tostring(math.floor((tonumber(ap.weight) or 0) * 10 + 0.5)),
	}, "|")
end

function Companions.Spot(index: number, height: number): (number, number)
	local spot = Cfg.Formation[math.clamp(index, 1, #Cfg.Formation)]
	local spread = 1 + math.max(0, (height or 3) - 3) * Cfg.SizeSpread
	return spot.x * spread, spot.z * spread
end

function Companions.Speed(distance: number, ownerSpeed: number): number
	local cap = math.clamp(math.max(ownerSpeed * Cfg.CatchUp, Cfg.MinSpeed), Cfg.MinSpeed, Cfg.MaxSpeed)
	return math.min(distance * Cfg.Gain, cap)
end

function Companions.State(prev: string, distance: number, stillFor: number, hopLeft: number): string
	if hopLeft > 0 then
		return "hop"
	end
	if distance > Cfg.StartWalk or (prev == "walk" and distance > Cfg.StopWalk) then
		return "walk"
	end
	if stillFor >= Cfg.SitAfter then
		return "sit"
	end
	return "idle"
end

function Companions.ClipRate(speed: number, height: number, length: number): number
	local stride = Cfg.Stride * math.max(height or 3, 0.5)
	local rate = speed / stride * math.max(length or 1, 0.05)
	return math.clamp(rate, Cfg.MinRate, Cfg.MaxRate)
end

function Companions.Gait(speed: number, airborne: boolean): string
	if airborne then
		return "hop"
	end
	return if speed >= Cfg.MoveSpeed then "walk" else "idle"
end

function Companions.Pick(entries: { any }, cap: number, maxDistance: number): { any }
	table.sort(entries, function(a, b)
		return a.distance < b.distance
	end)
	local out = {}
	for _, entry in entries do
		if #out >= cap or entry.distance > maxDistance then
			break
		end
		table.insert(out, entry)
	end
	return out
end

return Companions
