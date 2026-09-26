--[[
	RaceGear (glow-up LR): cosmetic racing gear (saddles, trails, banners) drawn on the player's
	mount. Purely cosmetic: no stat changes. Items and milestones: Config.LiveRace.Gear.

	Save section (profile.RaceGear):
	  owned = { [gearId]: true }, equipped = { saddle, trail, banner = gearId|false },
	  races, live, podiums, wins, duels     -- milestone counters (see Config/LiveRace)
	Global (global.RaceGear): { here = { ['u'..userId]: { saddle, trail, banner } } }  -- equipped, this server

	Subscribes to RaceFinished (Monster Racing and live races): counts the race and grants every
	item whose milestone is reached (Kernel.Notify "New racing gear: <name>").
	Actions: RaceGear.Equip { kind, item } (item "" takes the kind off).
	Public: RaceGear:Grant(player, id) -> boolean (for quests and events), RaceGear:Equipped(player).
]]

local RaceGear = {
	Name = "RaceGear",
	Dependencies = {},
}

RaceGear.Profile = {
	Version = 1,
	Default = function()
		return {
			owned = {},
			equipped = { saddle = false, trail = false, banner = false },
			races = 0,
			live = 0,
			podiums = 0,
			wins = 0,
			duels = 0,
		}
	end,
}

local ctx
local Cfg -- Config.LiveRace

local function key(player): string
	return "u" .. tostring(player.UserId)
end

local function publish(player)
	local s = ctx:Section(player)
	local g = ctx:Global()
	local any = false
	local shown = {}
	for _, kind in Cfg.GearKinds do
		local id = s and s.equipped[kind]
		shown[kind] = if type(id) == "string" and s.owned[id] then id else false
		any = any or shown[kind] ~= false
	end
	g.here[key(player)] = if any then shown else nil
	ctx:DirtyGlobal("here")
end

function RaceGear:Grant(player, id: string): boolean
	local s = ctx:Section(player)
	local item = Cfg.GearById[id]
	if not s or not item or s.owned[id] then
		return false
	end
	s.owned[id] = true
	-- A first item of its kind goes straight on.
	if s.equipped[item.kind] == false then
		s.equipped[item.kind] = id
		publish(player)
	end
	ctx:Dirty(player)
	ctx:Notify(player, string.format("New racing gear: %s", item.name), "reward")
	return true
end

function RaceGear:Equipped(player)
	local s = ctx:Section(player)
	return if s then s.equipped else {}
end

local function counted(player, detail)
	local s = ctx:Section(player)
	if not s then
		return
	end
	s.races += 1
	if detail.place == 1 then
		s.wins += 1
	end
	if detail.live then
		s.live += 1
		if detail.place <= 3 then
			s.podiums += 1
		end
		if detail.place == 1 and (detail.riders or 1) >= 2 then
			s.duels += 1
		end
	end
	ctx:Dirty(player)
	for _, item in Cfg.Gear do
		if not s.owned[item.id] and (s[item.need.stat] or 0) >= item.need.n then
			RaceGear:Grant(player, item.id)
		end
	end
end

local function equip(player, kind: string, id: string)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	if id == "" then
		s.equipped[kind] = false
	else
		local item = Cfg.GearById[id]
		if not item or item.kind ~= kind then
			ctx:Fail("That gear doesn't go there")
		end
		if not s.owned[id] then
			ctx:Fail("You haven't earned that gear yet")
		end
		s.equipped[kind] = id
	end
	ctx:Dirty(player)
	publish(player)
	return nil
end

function RaceGear.Init(context)
	ctx = context
	Cfg = ctx.Config.LiveRace
	ctx:Global().here = {}
	ctx.Net:Handle("RaceGear.Equip", function(player, payload)
		return equip(player, payload.kind, payload.item)
	end)
	ctx.Bus:Subscribe("RaceFinished", counted)
end

function RaceGear.PlayerAdded(player)
	publish(player)
end

function RaceGear.PlayerRemoving(player)
	ctx:Global().here[key(player)] = nil
	ctx:DirtyGlobal("here")
end

return RaceGear
