--[[
	Companions (glow-up T): pick monsters to walk beside you; everyone on the server sees them.
	Cosmetic only: a companion keeps its pen, its income and everything else. Rules and tuning:
	Config/Companions, Logic/Companions.

	Save section (profile.Companions), version 2:
	  ids = { monsterId }        -- chosen companions, in formation order, ≤ Config.Companions.MaxSlots
	  (v1, the single-slot first cut, saved { id = monsterId|false }; Logic/Companions.Migrate)

	Global (global.Companions):
	  walkers = { ['u'..userId] = { { id, appearance } } }   -- the companions drawn for each player:
	    the saved ids that still exist, aren't busy or ridden, capped at the player's slots
	    (Config.Companions.Slots, VipSlots with the VIP Rancher pass). `appearance` is
	    Monsters:Appearance (Mastery's aura included); it is re-sent only when its look changes.

	Actions:
	  Companions.Set { ids } -> { ids }    ids = {} sends everyone home. Each id must be the
	                                        player's own monster, not busy (expedition, breeding,
	                                        trade) and not the one they ride; at most their slots.

	Upkeep: a companion that is removed (sold, retired, fused, traded, listed on the Market,
	rebirth), becomes busy or gets mounted leaves the list. Losing VIP keeps the saved list but
	draws only the first slot. PassesChanged re-publishes (a pass bought mid-session).

	Public API:
	  Companions:Of(player) -> { monsterId }      the saved list (read-only)
	  Companions:Slots(player) -> number
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Companions)

local Companions = {
	Name = "Companions",
	Dependencies = { "Monsters" },
	OptionalDependencies = { "Monetization", "Riding" },
}

Companions.Profile = {
	Version = 2,
	Default = function()
		return { ids = {} }
	end,
	Migrate = function(section, fromVersion)
		return Logic.Migrate(section, fromVersion)
	end,
}

local ctx
local Cfg -- Config.Companions
local Monsters

local shown = {} -- [player] = { [id] = signature } of what global.walkers holds for them

local function key(player): string
	return "u" .. tostring(player.UserId)
end

local function isVip(player): boolean
	local mon = ctx:GetSystem("Monetization")
	return mon ~= nil and mon:HasPass(player, Cfg.VipPass) == true
end

local function mountOf(player): string?
	local riding = ctx:GetSystem("Riding")
	return riding and riding.MountOf and riding:MountOf(player) or nil
end

-- Why `id` can't walk right now (nil = it can).
local function unfit(player, id: string): string?
	local m = Monsters:Get(player, id)
	if not m then
		return "That monster doesn't exist"
	end
	if m.busy then
		return "That monster is busy"
	end
	if mountOf(player) == id then
		return "You're riding that monster"
	end
	return nil
end

-- Drops saved ids that can no longer walk. Returns the section.
local function prune(player)
	local section = ctx:Section(player)
	if not section then
		return nil
	end
	local kept = {}
	for _, id in Logic.Clean(section.ids, Cfg.MaxSlots) do
		if not unfit(player, id) then
			table.insert(kept, id)
		end
	end
	if #kept ~= #section.ids then
		section.ids = kept
		ctx:Dirty(player, "ids")
	end
	return section
end

local function publish(player, force: boolean?)
	local section = prune(player)
	if not section then
		return
	end
	local slots = Companions:Slots(player)
	local list, sigs = {}, {}
	local changed = force == true
	local before = shown[player] or {}
	for i, id in section.ids do
		if i > slots then
			break
		end
		local appearance = Monsters:Appearance(player, id)
		if appearance then
			table.insert(list, { id = id, appearance = appearance })
			sigs[id] = Logic.Signature(appearance)
			if before[id] ~= sigs[id] then
				changed = true
			end
		end
	end
	local g = ctx:Global()
	local old = g.walkers[key(player)]
	if (if old then #old else 0) ~= #list then
		changed = true
	elseif old then
		for i, entry in old do
			if entry.id ~= list[i].id then
				changed = true
			end
		end
	end
	if not changed then
		return
	end
	shown[player] = sigs
	g.walkers[key(player)] = if #list > 0 then list else nil
	ctx:DirtyGlobal("walkers")
end

local function set(player, ids: { string })
	local slots = Companions:Slots(player)
	local seen = {}
	for _, id in ids do
		if seen[id] then
			ctx:Fail("Pick each monster once")
		end
		seen[id] = true
	end
	if #ids > slots then
		if slots < Cfg.VipSlots then
			ctx:Fail(string.format("Walk with up to %d monsters with VIP Rancher", Cfg.VipSlots))
		end
		ctx:Fail(string.format("You can walk with up to %d monsters", slots))
	end
	for _, id in ids do
		local why = unfit(player, id)
		if why then
			ctx:Fail(why)
		end
	end
	local section = ctx:Section(player)
	section.ids = table.clone(ids)
	ctx:Dirty(player, "ids")
	publish(player)
	return { ids = table.clone(section.ids) }
end

local function isCompanion(player, id: string): boolean
	local section = ctx:Section(player)
	return section ~= nil and table.find(section.ids, id) ~= nil
end

function Companions:Of(player): { string }
	local section = ctx:Section(player)
	return if section then section.ids else {}
end

function Companions:Slots(player): number
	return Logic.Slots(isVip(player))
end

function Companions.Init(context)
	ctx = context
	Cfg = ctx.Config.Companions
	Monsters = ctx:GetSystem("Monsters")
	table.clear(shown)
	ctx:Global().walkers = {}

	ctx.Net:Handle("Companions.Set", function(player, payload)
		return set(player, payload.ids)
	end)

	ctx.Bus:Subscribe("MonsterRemoved", function(player, detail)
		if isCompanion(player, detail.id) then
			publish(player)
		end
	end)
	ctx.Bus:Subscribe("MonsterChanged", function(player, detail)
		if isCompanion(player, detail.id) then
			publish(player) -- busy → leaves; a new look (evolved, accessory, mutation) → re-sent
		end
	end)
	ctx.Bus:Subscribe("Mounted", function(player, detail)
		if isCompanion(player, detail.id) then
			publish(player)
		end
	end)
	ctx.Bus:Subscribe("PassesChanged", function(player)
		publish(player)
	end)
end

function Companions.PlayerAdded(player, _info)
	publish(player, true)
end

function Companions.PlayerRemoving(player)
	shown[player] = nil
	local g = ctx:Global()
	if g.walkers[key(player)] ~= nil then
		g.walkers[key(player)] = nil
		ctx:DirtyGlobal("walkers")
	end
end

return Companions
