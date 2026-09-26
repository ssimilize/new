--[[
	Gait (glow-up T): plays a monster's authored clips for a model the caller moves itself: the
	companions (Controllers/Companions) and the mounts welded under riders (Controllers/Mounts).
	MonsterAnimator owns pen monsters, which walk to points at their own pace; here the walk clip
	follows the speed the model is really moving at (Logic/Companions.ClipRate), so feet match
	the ground whether the owner strolls or a mount gallops.

		local gait = Gait.new(model)
		local bob = gait:Step(state, dt, speed)   -- state: idle | walk | sit | hop | trick | happy
		gait:Play(oneShot) -> boolean             -- trick / happy once (photo mode), then back
		gait:State() -> string                    -- the state last stepped (a one-shot while it plays)

	Skinned models (MeshMonster) get Pose + Follow (worn accessories) each step; a missing clip
	falls back (sit → idle, trick → hop, happy → cheer → hop). MeshMonster.Pose eases every clip
	switch, so idle ↔ walk ↔ hop blends. Placeholder models have no bones: Step returns a small
	vertical bob in studs (a trot while walking, a crouch while sitting) the caller may add.
	Allocation-free per step.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logic = require(ReplicatedStorage.Shared.Logic.Companions)
local MeshMonster = require(script.Parent.MeshMonster)

local Gait = {}
Gait.__index = Gait

local LOOPING = { idle = true, walk = true, sit = true }
local abs, sin = math.abs, math.sin

function Gait.new(model: Model)
	local skinned = model:GetAttribute("Skinned") == true
	local height = tonumber(model:GetAttribute("Height")) or 3
	local self = setmetatable({
		model = model,
		height = height,
		_skinned = skinned,
		_wearing = skinned and MeshMonster.Follow(model),
		_state = "idle",
		_clip = "idle",
		_t = 0,
		_walkLength = (skinned and MeshMonster.Length(model, "walk")) or 1,
		_oneShot = nil :: string?,
		_oneShotLeft = 0,
		_oneShotState = "idle",
	}, Gait)
	return self
end

function Gait:_has(clip: string): boolean
	return self._skinned and MeshMonster.HasClip(self.model, clip)
end

-- The authored clip for a state, with fallbacks for forms rigged before the extra clips.
function Gait:_clipFor(state: string): string
	if state == "walk" or state == "hop" then
		return state
	elseif state == "sit" then
		return if self:_has("sit") then "sit" else "idle"
	elseif state == "trick" then
		return if self:_has("trick") then "trick" else "hop"
	elseif state == "happy" then
		if self:_has("cheer") then
			return "cheer"
		end
		return "hop"
	end
	return "idle"
end

-- A one-shot (photo mode's pose): returns false for a state it can't show as asked, so the
-- caller can try another (PhotoMode tries trick, then happy).
function Gait:Play(state: string): boolean
	if state ~= "trick" and state ~= "happy" then
		return false
	end
	if state == "trick" and self._skinned and not self:_has("trick") then
		return false
	end
	local clip = self:_clipFor(state)
	self._oneShot = clip
	self._oneShotState = state
	self._oneShotLeft = (self._skinned and MeshMonster.Length(self.model, clip)) or 1
	self._clip = clip
	self._t = 0
	return true
end

function Gait:State(): string
	return if self._oneShot then self._oneShotState else self._state
end

function Gait:Step(state: string, dt: number, speed: number): number
	if self._oneShot then
		self._oneShotLeft -= dt
		if self._oneShotLeft <= 0 or state == "walk" or state == "hop" then
			self._oneShot = nil
		end
	end
	local clip, loop
	if self._oneShot then
		clip, loop = self._oneShot, false
	else
		clip = self:_clipFor(state)
		loop = LOOPING[state] == true
		if clip ~= self._clip or state ~= self._state then
			self._t = 0
		end
	end
	self._state = state
	self._clip = clip
	local rate = 1
	if state == "walk" and not self._oneShot then
		rate = Logic.ClipRate(speed, self.height, self._walkLength) -- clip seconds per second
	end
	self._t += dt * rate
	if self._skinned then
		MeshMonster.Pose(self.model, clip, self._t, loop)
		if self._wearing then
			MeshMonster.Follow(self.model)
		end
		return 0
	end
	local t = self._t
	if state == "walk" then
		return abs(sin(t * math.pi)) * self.height * 0.12
	elseif state == "sit" then
		return -self.height * 0.08
	elseif state == "idle" then
		return (1 - sin(t * 2.4)) * self.height * 0.012
	end
	return 0
end

return Gait
