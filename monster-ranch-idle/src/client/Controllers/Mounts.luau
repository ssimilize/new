--[[
	Mounts controller (glow-up T): brings every rider's mount to life. The Riding controller welds
	the mount ("Mount" under the character) and moves the rider; this one only poses it:

	  · walk while the rider moves, its clip time scaled by the measured speed and the mount's size
	    (Logic/Companions.ClipRate), idle when standing, the hop clip when the rider jumps;
	    MeshMonster.Pose eases each switch, so the gait blends.
	  · Speed is measured from the rider's root-part position each frame (smoothed), so other
	    players' mounts animate just like our own; global.Riding.riders[...].speed caps it, so a
	    teleport never reads as a sprint.
	  · Only riders in global.Riding.riders are visited (no scan of every player per frame).
	    Placeholder mounts have no bones and stay as they were.

	  · Glow-up DR: inside the Deep Reef (Logic/Swim.Inside) the walk clip plays slowed as strokes
	    (Logic/Swim.ClipSpeed), speed is measured in 3D and there are no hops.

	Public: Mounts:StateOf(userId) -> "idle"|"walk"|"hop"|nil, Mounts:SpeedOf(userId) -> number.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Logic = require(ReplicatedStorage.Shared.Logic.Companions)
local Swim = require(ReplicatedStorage.Shared.Logic.Swim) -- glow-up DR

local UI = script.Parent.Parent.UI
local StoreKit = require(UI.Components.StoreKit)
local Gait = require(script.Parent.Parent.Visuals.Gait)

local Cfg = Config.Companions

local Mounts = {
	Name = "Mounts",
	Dependencies = { "Riding" },
}

local ctx
local list = {} -- array of rider records (rebuilt when global.Riding.riders changes)
local byUser = {} -- [userId] = record

local function refresh()
	local riders = StoreKit.tbl(ctx.Store, "global.Riding.riders")
	table.clear(list)
	local keep = {}
	for key, rider in riders do
		local userId = tonumber(string.match(tostring(key), "^u(%d+)$"))
		if userId and type(rider) == "table" then
			local record = byUser[userId]
				or { userId = userId, model = nil, gait = nil, last = nil, speed = 0, hopLeft = 0, state = "idle", cap = 0 }
			record.cap = tonumber(rider.speed) or Config.Riding.Max
			keep[userId] = record
			table.insert(list, record)
		end
	end
	table.clear(byUser)
	for userId, record in keep do
		byUser[userId] = record
	end
end

local function step(dt: number)
	if dt <= 0 then
		return
	end
	for _, r in list do
		local player = Players:GetPlayerByUserId(r.userId)
		local character = player and player.Character
		local mount = character and character:FindFirstChild("Mount")
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not mount or not hrp or not hrp:IsA("BasePart") then
			r.model, r.gait, r.last = nil, nil, nil
			continue
		end
		if mount ~= r.model then
			r.model = mount
			r.gait = Gait.new(mount :: Model)
			r.last = nil
			r.speed = 0
		end
		local pos = hrp.Position
		local last = r.last
		r.last = pos
		-- Glow-up DR: in the Deep Reef a mount swims: the walk clip slowed into strokes (3D speed,
		-- no hops); the swim controller tilts and bobs rider and mount together.
		local Reef = Config.DeepReef
		if Swim.Inside(pos.X, pos.Y, pos.Z, Reef.Area, 2) then
			if last then
				local dx, dy, dz = pos.X - last.X, pos.Y - last.Y, pos.Z - last.Z
				local speed = math.sqrt(dx * dx + dy * dy + dz * dz) / dt
				if speed <= r.cap * 2 + 8 then
					r.speed += (speed - r.speed) * math.min(1, Cfg.Smoothing * dt)
				end
			end
			r.hopLeft = 0
			r.state = if r.speed > 1 then "walk" else "idle"
			r.gait:Step(r.state, dt, Swim.ClipSpeed(r.speed, Reef.Swim))
			continue
		end
		if last then
			local dx, dy, dz = pos.X - last.X, pos.Y - last.Y, pos.Z - last.Z
			local horizontal = math.sqrt(dx * dx + dz * dz) / dt
			if horizontal <= r.cap * 1.6 + 4 and math.abs(dy) <= Cfg.OwnerJump then
				r.speed += (horizontal - r.speed) * math.min(1, Cfg.Smoothing * dt)
				if dy / dt > Cfg.JumpSpeed and r.hopLeft <= 0 then
					r.hopLeft = Cfg.HopSeconds
				end
			end -- else a teleport or a respawn: not a sprint, not a jump
		end
		r.hopLeft = math.max(0, r.hopLeft - dt)
		r.state = Logic.Gait(r.speed, r.hopLeft > 0)
		r.gait:Step(r.state, dt, r.speed)
	end
end

function Mounts:StateOf(userId: number): string?
	local r = byUser[userId]
	return if r and r.gait then r.state else nil
end

function Mounts:SpeedOf(userId: number): number
	local r = byUser[userId]
	return if r then r.speed else 0
end

function Mounts.Init(context)
	ctx = context
end

function Mounts.Start()
	ctx.Store:Observe("global.Riding.riders", refresh)
	refresh()
	RunService.Heartbeat:Connect(step)
end

return Mounts
