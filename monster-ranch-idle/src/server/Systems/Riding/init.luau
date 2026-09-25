--[[
	Riding (update 2.0): ride an Adult monster around the world. Rules: Config/Riding.

	Session (session.Riding): { mount = monsterId|false, speed }
	Global  (global.Riding):  { riders = { ['u'..userId] = { appearance, speed } } }
	  every client draws each rider's mount under their character; the rider's own client
	  sets its walk speed from `speed`.

	Actions: Riding.Mount { id } (an Adult that is not busy), Riding.Dismount.
	The rider is dismounted when the monster changes owner, leaves the ranch or becomes busy,
	and when the player leaves. Publishes Mounted (player, { id, speed }).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Appearance = require(Shared.Logic.Appearance)

local Riding = {
	Name = "Riding",
	Dependencies = { "Progression", "Monsters" },
}

local ctx
local Config -- Config.Riding
local Progression, Monsters

local mounts = {} -- [player] = monsterId

local function key(player): string
	return "u" .. tostring(player.UserId)
end

local function publish(player)
	local g = ctx:Global()
	local id = mounts[player]
	local m = id and Monsters:Get(player, id)
	if m then
		g.riders[key(player)] = { appearance = Appearance.Of(m), speed = Config.SpeedFor(m) }
	else
		g.riders[key(player)] = nil
	end
	ctx:DirtyGlobal("riders")
	local sess = ctx:Session(player)
	if sess then
		sess.mount = if m then id else false
		sess.speed = if m then Config.SpeedFor(m) else Config.WalkSpeed
		ctx:DirtySession(player)
	end
end

local function dismount(player)
	if mounts[player] then
		mounts[player] = nil
		publish(player)
	end
end

local function mount(player, id: string)
	Progression:Require(player, Config.Unlock)
	local m = Monsters:Get(player, id)
	if not m then
		ctx:Fail("That monster doesn't exist")
	end
	if m.stage < 3 then
		ctx:Fail("Only Adults are big enough to ride")
	end
	if m.busy then
		ctx:Fail("That monster is busy")
	end
	mounts[player] = id
	publish(player)
	ctx.Bus:Publish("Mounted", player, { id = id, speed = Config.SpeedFor(m) })
	return { speed = Config.SpeedFor(m) }
end

function Riding.Init(context)
	ctx = context
	Config = ctx.Config.Riding
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")
	table.clear(mounts)
	ctx:Global().riders = {}

	ctx.Net:Handle("Riding.Mount", function(player, payload)
		return mount(player, payload.id)
	end)
	ctx.Net:Handle("Riding.Dismount", function(player)
		if not mounts[player] then
			ctx:Fail("You aren't riding")
		end
		dismount(player)
		return nil
	end)

	ctx.Bus:Subscribe("MonsterRemoved", function(player, detail)
		if mounts[player] == detail.id then
			dismount(player)
		end
	end)
	ctx.Bus:Subscribe("MonsterChanged", function(player, detail)
		if mounts[player] ~= detail.id then
			return
		end
		local m = Monsters:Get(player, detail.id)
		if not m or m.busy then
			dismount(player)
		else
			publish(player) -- new accessories, level or mutation show on the mount
		end
	end)
end

function Riding.PlayerAdded(player, _info)
	local sess = ctx:Session(player)
	sess.mount = false
	sess.speed = Config.WalkSpeed
	ctx:DirtySession(player)
end

function Riding.PlayerRemoving(player)
	if mounts[player] then
		mounts[player] = nil
		ctx:Global().riders[key(player)] = nil
		ctx:DirtyGlobal("riders")
	end
end

return Riding
