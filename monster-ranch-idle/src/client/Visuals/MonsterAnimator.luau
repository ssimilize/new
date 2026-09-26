--[[
	MonsterAnimator (C1): procedural placeholder animation for MonsterModel / EggModel models.
	THE ANIMATION SWAP POINT: authored AnimationTracks replace the internals later; keep the API.

		local anim = MonsterAnimator.new(model)
		anim:SetBase(CFrame.new(x, floorY, z))    -- ground point + facing (front is -Z)
		anim:Play("idle")                          -- idle | walk | happy | eat | attack | hurt | sleep
		anim:Play("sit")                           -- sit (loops) | trick (once) | faint (holds until the next Play)
		anim:MoveTo(Vector3.new(x, floorY, z), function() end)   -- hop-walk, faces travel direction
		anim:Destroy()                             -- stops animating (does not destroy the model)

	Extra (non-contract) helpers:
	  anim:Play("wobble") + anim:SetIntensity(0..1)   egg wobble (faster near 1)
	  anim:IsMoving(), anim:GetPosition(), anim:Stop()  (Stop cancels a MoveTo)
	  anim:GetState()                                  the state playing ("idle" after a one-shot ends)
	  MonsterAnimator.SkinnedClip(...)                 which authored clip a 3D monster plays (below)
	  MonsterAnimator.SetLowGraphics(bool)             fewer updates for every animator
	  MonsterAnimator.Count()                          live animators (debug)

	One shared RenderStepped connection drives every animator. It connects when the first
	animator is created and disconnects when the last one is destroyed. Animators further than
	PAUSE_DISTANCE studs from the camera are paused; mid-distance ones (and all of them in low
	graphics) update at a reduced rate. The model is moved with model:PivotTo(base * offset).
	Rainbow models (attribute Rainbow) and prismatic ones (attribute Prismatic, set by the
	caller) cycle their "Body" part colour through a precomputed hue table.
	Near animators also squash and stretch the "Body" part: through its SpecialMesh Scale when
	it has one (cheap, no physics update), otherwise through its Size (never welds).
	Skinned models (attribute Skinned, built by MeshMonster) play their authored clips instead: walk
	while moving, idle at rest, and sleep, eat, attack, hurt, faint, sit and trick by name; happy is
	cheer or cheer2 at random. A form whose modules lack a clip (rigged before the extra clips) falls
	back to what it did before: sleep is idle slowed, eat, hurt, sit and faint keep the procedural
	offset over idle, happy and trick spin through hop, attack lunges through hop. The hop-walk bounce
	is dropped (the walk clip bobs). Authored attack, hurt, trick and cheer clips run their own length.
]]

local RunService = game:GetService("RunService")

local MeshMonster = require(script.Parent.MeshMonster)

local MonsterAnimator = {}
MonsterAnimator.__index = MonsterAnimator

local PAUSE_DISTANCE = 250
local MID_DISTANCE = 90
local SQUASH_DISTANCE = 60
local MID_INTERVAL = 1 / 20
local LOW_INTERVAL = 1 / 15
local HUE_STEPS = 72

local ONE_SHOT = { happy = 0.9, eat = 1.6, attack = 0.55, hurt = 0.5, trick = 1.1 }
local LOOPING = { idle = true, walk = true, sleep = true, wobble = true, sit = true }
local HOLD = { faint = true } -- stays until the next Play or MoveTo
local CLIP_LENGTH = { happy = true, attack = true, hurt = true, trick = true } -- authored ones run their own length

local TAU = math.pi * 2
local sin, cos, abs, min, clamp = math.sin, math.cos, math.abs, math.min, math.clamp

-- Precomputed colours so hue cycling never allocates per frame.
local RAINBOW = table.create(HUE_STEPS)
local PRISMATIC = table.create(HUE_STEPS)
for i = 1, HUE_STEPS do
	local h = (i - 1) / HUE_STEPS
	RAINBOW[i] = Color3.fromHSV(h, 0.62, 1)
	PRISMATIC[i] = Color3.fromHSV(h, 0.28, 1)
end

local FLASH_COLOR = Color3.fromRGB(255, 90, 90)

local animators = {} -- array of live animators
local connection: RBXScriptConnection? = nil
local lowGraphics = false
local clock = 0

local function smooth(p: number): number
	return p * p * (3 - 2 * p)
end

local step -- forward declaration

local function ensureLoop()
	if connection == nil and #animators > 0 then
		connection = RunService.RenderStepped:Connect(step)
	end
end

local function stopLoopIfIdle()
	if connection and #animators == 0 then
		connection:Disconnect()
		connection = nil
	end
end

function MonsterAnimator.new(model: Model)
	local root = model.PrimaryPart
	local body = model:FindFirstChild("Body")
	local height = model:GetAttribute("Height")
	local self = setmetatable({
		model = model,
		_body = if body and body:IsA("BasePart") then body else nil,
		_bodySize = if body and body:IsA("BasePart") then body.Size else nil,
		_bodyMesh = if body then body:FindFirstChildOfClass("SpecialMesh") else nil,
		_squashed = false,
		_size = if type(height) == "number" then math.max(1, height) else (if root then root.Size.Y else 2),
		_halfHeight = if root then root.Size.Y / 2 else 1,
		_base = model:GetPivot(),
		_pos = model:GetPivot().Position,
		_state = "idle",
		_t = 0,
		_accum = 0,
		_phase = math.random() * TAU,
		_hueOffset = math.random(1, HUE_STEPS),
		_rainbow = model:GetAttribute("Rainbow") == true,
		_prismatic = model:GetAttribute("Prismatic") == true,
		_skinned = model:GetAttribute("Skinned") == true,
		_has = function(clip: string): boolean
			return MeshMonster.HasClip(model, clip)
		end,
		_cheer = "cheer",
		_length = 0,
		_target = nil :: Vector3?,
		_onArrive = nil :: (() -> ())?,
		_speed = 5 + (if type(height) == "number" then height else 3) * 0.6,
		_intensity = 0,
		_highlight = nil :: Highlight?,
		_dead = false,
		_index = 0,
	}, MonsterAnimator)
	table.insert(animators, self)
	self._index = #animators
	ensureLoop()
	return self
end

function MonsterAnimator.SetLowGraphics(on: boolean)
	lowGraphics = on == true
end

function MonsterAnimator.Count(): number
	return #animators
end

function MonsterAnimator:SetBase(cframe: CFrame)
	self._base = cframe
	self._pos = cframe.Position
	if self._state ~= "walk" then
		self.model:PivotTo(cframe)
	end
end

function MonsterAnimator:GetPosition(): Vector3
	return self._pos
end

function MonsterAnimator:IsMoving(): boolean
	return self._target ~= nil
end

function MonsterAnimator:GetState(): string
	return self._state
end

function MonsterAnimator:SetIntensity(x: number)
	self._intensity = clamp(x, 0, 1)
end

function MonsterAnimator:Play(state: string)
	if self._dead then
		return
	end
	if not (ONE_SHOT[state] or LOOPING[state] or HOLD[state]) then
		state = "idle"
	end
	if state == "walk" and self._target == nil then
		state = "idle"
	end
	if state ~= self._state or ONE_SHOT[state] then
		self._t = 0
	end
	self._state = state
	if state == "happy" then
		self._cheer = if math.random() < 0.5 then "cheer" else "cheer2"
	end
	self._length = ONE_SHOT[state] or 0
	local clip = if state == "happy" then self._cheer else state
	if self._skinned and CLIP_LENGTH[state] and MeshMonster.HasClip(self.model, clip) then
		self._length = MeshMonster.Length(self.model, clip) or self._length
	end
	if state == "hurt" then
		self:_flash()
	end
end

function MonsterAnimator:MoveTo(position: Vector3, onArrive: (() -> ())?)
	if self._dead then
		return
	end
	self._target = Vector3.new(position.X, self._pos.Y, position.Z)
	self._onArrive = onArrive
	if not ONE_SHOT[self._state] then
		self._state = "walk"
		self._t = 0
	end
end

function MonsterAnimator:Stop()
	self._target = nil
	self._onArrive = nil
	if self._state == "walk" then
		self._state = "idle"
		self._t = 0
	end
end

function MonsterAnimator:_flash()
	local highlight = self._highlight
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.OutlineTransparency = 1
		highlight.FillColor = FLASH_COLOR
		highlight.Parent = self.model
		self._highlight = highlight
	end
	highlight.FillTransparency = 0.15
	highlight.Enabled = true
end

function MonsterAnimator:_restoreBody()
	if self._squashed and self._body and self._bodySize then
		if self._bodyMesh then
			self._bodyMesh.Scale = Vector3.new(1, 1, 1)
		else
			self._body.Size = self._bodySize
		end
		self._squashed = false
	end
end

function MonsterAnimator:_squash(amount: number, near: boolean)
	local body, size = self._body, self._bodySize
	if not body or not size then
		return
	end
	if not near or lowGraphics then
		self:_restoreBody()
		return
	end
	local scale = Vector3.new(1 + amount * 0.5, 1 - amount, 1 + amount * 0.5)
	if self._bodyMesh then
		self._bodyMesh.Scale = scale
	else
		body.Size = size * scale
	end
	self._squashed = true
end

-- Returns to the looping state after a one-shot finishes.
function MonsterAnimator:_endOneShot()
	if self._highlight then
		self._highlight.Enabled = false
	end
	self._state = if self._target then "walk" else "idle"
	self._t = 0
end

function MonsterAnimator:_arrive()
	local callback = self._onArrive
	self._target = nil
	self._onArrive = nil
	self._state = "idle"
	self._t = 0
	if callback then
		-- Deferred so callbacks never mutate the animator list mid-iteration.
		task.defer(callback)
	end
end

function MonsterAnimator:_update(dt: number, near: boolean)
	self._t += dt
	local t = self._t
	local s = self._size
	local state = self._state
	local phase = self._phase
	local offset: CFrame

	if state == "walk" then
		local target = self._target
		if not target then
			self._state = "idle"
			offset = CFrame.identity
		else
			local pos = self._pos
			local delta = target - pos
			local dist = delta.Magnitude
			local move = self._speed * dt
			if dist <= move or dist < 0.05 then
				self._pos = target
				self._base = CFrame.lookAt(target, target + self._base.LookVector)
				self:_arrive()
				offset = CFrame.identity
			else
				local dir = delta / dist
				local newPos = pos + dir * move
				self._pos = newPos
				self._base = CFrame.lookAt(newPos, newPos + dir)
				local hop = (t * 2.6) % 1
				local height = sin(hop * math.pi) * s * 0.22
				self:_squash(-0.12 * sin(hop * math.pi) + 0.08 * (if hop < 0.12 then 1 - hop / 0.12 else 0), near)
				offset = CFrame.new(0, height, 0) * CFrame.Angles(-0.12 * sin(hop * math.pi), 0, 0)
			end
		end
	elseif state == "idle" then
		local b = sin(t * 2.4 + phase)
		self:_squash(0.05 * b, near)
		offset = CFrame.new(0, s * 0.015 * (1 - b), 0) * CFrame.Angles(0, 0, 0.04 * sin(t * 1.2 + phase))
	elseif state == "sleep" then
		local b = sin(t * 1.3 + phase)
		self:_squash(0.035 * b, near)
		offset = CFrame.new(0, -s * 0.06, 0) * CFrame.Angles(0.08, 0, 0.22)
	elseif state == "happy" then
		local p = min(t / self._length, 1)
		local e = smooth(p)
		self:_squash(-0.1 * sin(p * math.pi), near)
		offset = CFrame.new(0, sin(p * math.pi) * s * 0.7, 0) * CFrame.Angles(0, e * TAU, 0)
		if p >= 1 then
			self:_endOneShot()
		end
	elseif state == "eat" then
		local p = min(t / self._length, 1)
		local nod = abs(sin(t * 9)) * 0.35 * (1 - p * 0.3)
		self:_squash(0.04 * sin(t * 18), near)
		offset = CFrame.new(0, 0, -s * 0.05) * CFrame.Angles(-nod, 0, 0)
		if p >= 1 then
			self:_endOneShot()
		end
	elseif state == "attack" then
		local p = min(t / self._length, 1)
		local lunge = if p < 0.35 then -0.25 * (p / 0.35) else sin((p - 0.35) / 0.65 * math.pi) * 1.1
		self:_squash(0.08 * sin(p * math.pi), near)
		offset = CFrame.new(0, sin(p * math.pi) * s * 0.12, -lunge * s * 0.5) * CFrame.Angles(-0.25 * sin(p * math.pi), 0, 0)
		if p >= 1 then
			self:_endOneShot()
		end
	elseif state == "hurt" then
		local p = min(t / self._length, 1)
		local shake = sin(t * 55) * s * 0.08 * (1 - p)
		if self._highlight then
			self._highlight.FillTransparency = 0.15 + 0.85 * p
		end
		self:_squash(0, near)
		offset = CFrame.new(shake, 0, s * 0.06 * (1 - p)) * CFrame.Angles(0.15 * (1 - p), 0, 0)
		if p >= 1 then
			self:_endOneShot()
		end
	elseif state == "sit" then
		local b = sin(t * 1.6 + phase)
		self:_squash(0.12 + 0.02 * b, near)
		offset = CFrame.new(0, -s * 0.04, 0) * CFrame.Angles(-0.15, 0, 0)
	elseif state == "faint" then
		local e = smooth(min(t / 0.7, 1))
		self:_squash(0.08 * e, near)
		offset = CFrame.new(0, s * 0.15 * e, 0) * CFrame.Angles(0, 0, 1.4 * e)
	elseif state == "trick" then
		local p = min(t / self._length, 1)
		local h = self._halfHeight
		self:_squash(-0.1 * sin(p * math.pi), near)
		offset = CFrame.new(0, h + sin(p * math.pi) * s * 0.6, 0) * CFrame.Angles(-smooth(p) * TAU, 0, 0) * CFrame.new(0, -h, 0)
		if p >= 1 then
			self:_endOneShot()
		end
	elseif state == "wobble" then
		local k = self._intensity
		local freq = 2 + k * 10
		local amp = 0.05 + k * 0.2
		local h = self._halfHeight
		local angle = sin(t * freq + phase) * amp
		local hop = if k >= 1 then abs(sin(t * 3)) * 0.3 else 0
		offset = CFrame.new(0, -h + hop, 0) * CFrame.Angles(angle * cos(phase), 0, angle * sin(phase)) * CFrame.new(0, h, 0)
	else
		offset = CFrame.identity
	end

	if self._skinned then
		local clip, time, loop, keep = MonsterAnimator.SkinnedClip(state, self._has, t, phase, self._cheer)
		if not keep then
			local spin = clip == "hop" and (state == "happy" or state == "trick")
			offset = if spin then CFrame.Angles(0, smooth(min(t / self._length, 1)) * TAU, 0) else CFrame.identity
		end
		MeshMonster.Pose(self.model, clip, time, loop)
	end

	local body = self._body
	if body then
		if self._rainbow then
			body.Color = RAINBOW[(math.floor(clock * 18) + self._hueOffset) % HUE_STEPS + 1]
		elseif self._prismatic then
			body.Color = PRISMATIC[(math.floor(clock * 30) + self._hueOffset) % HUE_STEPS + 1]
		end
	end

	self.model:PivotTo(self._base * offset)
end

-- Which authored clip a skinned monster plays in `state`, at what time and whether it loops, and
-- whether the procedural offset worked out for the state still applies (keep): the fallbacks for a
-- form whose modules have only idle, walk and hop. has(clip) says whether the form has a clip;
-- cheer is the happy variant picked on Play. Pure, so the spec can check any set of clips.
function MonsterAnimator.SkinnedClip(
	state: string,
	has: (string) -> boolean,
	t: number,
	phase: number,
	cheer: string?
): (string, number, boolean, boolean)
	if state == "walk" then
		return "walk", t, true, false
	elseif state == "happy" or state == "attack" or state == "trick" then
		local clip = if state == "happy" then cheer or "cheer" else state
		if has(clip) then
			return clip, t, false, false
		end
		return "hop", t, false, state == "attack" -- attack keeps its lunge; happy and trick spin
	elseif state == "sleep" then
		if has("sleep") then
			return "sleep", t, true, false
		end
		return "idle", (t + phase) * 0.4, true, false
	elseif state == "eat" or state == "sit" then
		if has(state) then
			return state, t, true, false
		end
		return "idle", t + phase, true, true
	elseif state == "hurt" or state == "faint" then
		if has(state) then
			return state, t, false, false
		end
		return "idle", if state == "faint" then 0 else t + phase, true, true
	end
	return "idle", t + phase, true, false
end

function step(dt: number)
	clock += dt
	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	local pauseSq = PAUSE_DISTANCE * PAUSE_DISTANCE
	local midSq = MID_DISTANCE * MID_DISTANCE
	local squashSq = SQUASH_DISTANCE * SQUASH_DISTANCE
	for i = 1, #animators do
		local a = animators[i]
		if a and not a._dead and a.model.Parent ~= nil then
			local d = a._pos - camPos
			local distSq = d.X * d.X + d.Y * d.Y + d.Z * d.Z
			a._accum += dt
			if distSq <= pauseSq then
				local interval = if lowGraphics then LOW_INTERVAL elseif distSq > midSq then MID_INTERVAL else 0
				if a._accum >= interval then
					local elapsed = min(a._accum, 0.25)
					a._accum = 0
					a:_update(elapsed, distSq <= squashSq)
				end
			else
				a._accum = 0
			end
		end
	end
end

function MonsterAnimator:Destroy()
	if self._dead then
		return
	end
	self._dead = true
	self:_restoreBody()
	if self._highlight then
		self._highlight:Destroy()
		self._highlight = nil
	end
	self._target = nil
	self._onArrive = nil
	-- Swap-remove (O(1)); indexes are kept on each animator.
	local index = self._index
	local last = animators[#animators]
	if animators[index] == self then
		animators[index] = last
		last._index = index
		animators[#animators] = nil
	else
		local i = table.find(animators, self)
		if i then
			table.remove(animators, i)
			for j = i, #animators do
				animators[j]._index = j
			end
		end
	end
	stopLoopIfIdle()
end

return MonsterAnimator
