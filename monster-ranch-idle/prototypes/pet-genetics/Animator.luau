--[[
	PROTOTYPE (not part of the game): procedural animation for monsters that Roblox's mesh generator
	made PART BY PART (generate_mesh, explicit segmentation: body, left ear, eyes, mouth, tail,
	front legs, left wings, ...). No skeleton, no keyframes: each part gets a ROLE from its name and
	a PIVOT from its shape, and every frame turns or squashes it about that pivot, relative to the
	body.

	  role      pivot                          motion
	  ear       base (bottom of its box)       slow sway + a quick twitch every few seconds
	  antenna   base                           sway
	  crest     base                           sway (a head tuft, leaf, flame on top)
	  eyes      centre                         blink: squash flat and back, every 2-5 s
	  mouth     centre                         chatter: opens and closes a couple of times now and then
	  tail      where it meets the body        wag side to side
	  wing      inner edge (nearest the body)  flap, mirrored left/right; fast for hoverers
	  leg       top (the hip)                  swing while walking, front and back in opposite phase
	  arm       top (the shoulder)             gentle swing, bigger while walking
	  head      bottom (the neck)              small nod
	  body      -                              breathing bob; hoverers bob higher

	Animator.rig(model, options?) -> Rig    options: { hover = bool, seed = number, path = fn(t) -> CFrame }
	Animator.check(model) -> { blink, chatter, notes }  is each eyes/mouth part only eyes / a mouth?
	Rig:setWalking(bool)                     legs and arms walk
	Rig:step(t)                              pose at time t (seconds); call every frame
	Rig:reset()                              back to the rest pose
	Animator.run(rigs) -> stop()             drives rigs from RunService.Heartbeat (Edit or Play)

	The generator's segmentation is a guess: an `eyes` part can take a flower on the head with it, a
	`mouth` the whole face patch or the nose. Animator.check measures each against the body and
	the rig leaves out a blink or a chatter that would squash more than eyes or a mouth.

	Parts are moved with workspace:BulkMoveTo; the model's body (its PrimaryPart) is the root and
	may be moved by the caller (walking) between frames: call Rig:moveTo(cframe) instead of
	PivotTo so the rest pose follows.
]]

local RunService = game:GetService("RunService")

local Animator = {}

-- Part name (letters and spaces only, lower case) -> role. Unknown names stay still.
local ROLE_BY_WORD = {
	{ "ear", "ear" },
	{ "antenna", "antenna" },
	{ "stalk", "antenna" },
	{ "eye", "eyes" },
	{ "mouth", "mouth" },
	{ "beak", "mouth" },
	{ "tail", "tail" },
	{ "wing", "wing" },
	{ "leg", "leg" },
	{ "feet", "leg" },
	{ "foot", "leg" },
	{ "arm", "arm" },
	{ "decoration", "crest" },
	{ "head", "head" },
	{ "top", "crest" },
	{ "tuft", "crest" },
	{ "crest", "crest" },
	{ "horn", "ear" },
	{ "body", "body" },
}

local function roleOf(name: string): string?
	local clean = string.lower((string.gsub(string.gsub(name, "_geom$", ""), "[^%a ]", "")))
	for _, pair in ROLE_BY_WORD do
		if string.find(clean, pair[1], 1, true) then
			return pair[2], clean
		end
	end
	return nil, clean
end

-- A small seeded random source per rig, so pets do not blink in step.
local function rand(seed: number)
	local s = seed
	return function(lo: number, hi: number): number
		s = (s * 1103515245 + 12345) % 2147483648
		return lo + (s / 2147483648) * (hi - lo)
	end
end

-- Is each eyes / mouth part only that? Measured against the body: eyes flatter than a third of the
-- body's height and not taller than wide; a mouth under a quarter of the body's height and under
-- half its width, and lower than the eyes when both exist.
function Animator.check(model: Model)
	local body = model.PrimaryPart
	local eyes, mouth
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= body then
			local role = roleOf(d.Name)
			if role == "eyes" then
				eyes = d
			elseif role == "mouth" then
				mouth = d
			end
		end
	end
	local notes = {}
	local blink, chatter = eyes ~= nil, mouth ~= nil
	if body and eyes then
		if eyes.Size.Y > body.Size.Y / 3 or eyes.Size.Y > eyes.Size.X then
			blink = false
			table.insert(notes, "eyes part holds more than eyes: no blink")
		end
	end
	if body and mouth then
		if mouth.Size.Y > body.Size.Y / 4 or mouth.Size.X > body.Size.X / 2 then
			chatter = false
			table.insert(notes, "mouth part is bigger than a mouth: no chatter")
		elseif eyes and blink and mouth.Position.Y > eyes.Position.Y then
			chatter = false
			table.insert(notes, "mouth part sits above the eyes: no chatter")
		end
	end
	return { blink = blink, chatter = chatter, notes = notes }
end

local Rig = {}
Rig.__index = Rig

-- Pivot of a part in BODY space, by role (parts are axis-aligned with the body when generated).
local function pivotFor(role: string, rest: CFrame, size: Vector3): Vector3
	local c = rest.Position
	local h = size / 2
	if role == "ear" or role == "antenna" or role == "crest" then
		return c - Vector3.new(0, h.Y, 0)
	elseif role == "leg" or role == "arm" then
		return c + Vector3.new(0, h.Y, 0)
	elseif role == "head" then
		return c - Vector3.new(0, h.Y, 0)
	elseif role == "wing" or role == "tail" then
		-- The face of the part's box nearest the body centre, along the axis it sticks out on.
		local ax, ay, az = math.abs(c.X), math.abs(c.Y), math.abs(c.Z)
		if role == "wing" or ax >= az and ax >= ay then
			return c - Vector3.new(math.sign(c.X) * h.X, 0, 0)
		elseif az >= ay then
			return c - Vector3.new(0, 0, math.sign(c.Z) * h.Z)
		end
		return c - Vector3.new(0, math.sign(c.Y) * h.Y, 0)
	end
	return c
end

function Animator.rig(model: Model, options: { hover: boolean?, seed: number? }?)
	options = options or {}
	local body = model.PrimaryPart
	assert(body, "the model needs its body as PrimaryPart")
	local self = setmetatable({}, Rig)
	self.model = model
	self.body = body
	self.root = body.CFrame
	self.hover = options.hover == true
	self.walking = false
	self.scale = math.max(body.Size.X, body.Size.Y, body.Size.Z)
	self.parts = {}
	local r = rand(options.seed or 1)
	self.random = r
	self.phase = r(0, 10)
	self.nextBlink, self.nextTwitch, self.nextChatter = r(0.5, 3), r(1, 4), r(2, 6)
	self.twitchSide = 1
	self.path = options.path
	local verdict = Animator.check(model)
	self.blink, self.chatter, self.notes = verdict.blink, verdict.chatter, verdict.notes
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= body then
			local role = roleOf(part.Name)
			if role and role ~= "body" then
				local rest = body.CFrame:ToObjectSpace(part.CFrame)
				local entry = {
					part = part,
					role = role,
					rest = rest,
					size = part.Size,
					pivot = pivotFor(role, rest, part.Size),
					-- left/right (+1 / -1) from where the part sits; front/back for legs.
					side = if rest.Position.X >= 0 then 1 else -1,
					front = rest.Position.Z <= 0,
				}
				local _, name = roleOf(part.Name)
				if string.find(name, "left", 1, true) then
					entry.side = -1
				elseif string.find(name, "right", 1, true) then
					entry.side = 1
				end
				if string.find(name, "back", 1, true) or string.find(name, "hind", 1, true) then
					entry.front = false
				elseif string.find(name, "front", 1, true) then
					entry.front = true
				end
				table.insert(self.parts, entry)
			end
		end
	end
	return self
end

function Rig:setWalking(on: boolean)
	self.walking = on
end

-- Move the whole pet (walking); the pose is re-applied from here on the next step.
function Rig:moveTo(cf: CFrame)
	self.root = cf
end

-- Rotation about a pivot, in body space.
local function about(pivot: Vector3, rot: CFrame): CFrame
	return CFrame.new(pivot) * rot * CFrame.new(-pivot)
end

-- 0..1..0 bump over `length` seconds starting at `start` (0 outside).
local function bump(t: number, start: number, length: number): number
	local x = (t - start) / length
	if x < 0 or x > 1 then
		return 0
	end
	return math.sin(x * math.pi)
end

function Rig:step(t: number)
	local r = self.random
	local p = t + self.phase
	-- Timers for the occasional motions.
	if t > self.nextBlink + 0.2 then
		self.nextBlink = t + r(1.8, 4.5)
	end
	if t > self.nextTwitch + 0.3 then
		self.nextTwitch = t + r(1.5, 5)
		self.twitchSide = if r(0, 1) < 0.5 then -1 else 1
	end
	if t > self.nextChatter + 0.8 then
		self.nextChatter = t + r(3, 8)
	end
	local blink = bump(t, self.nextBlink, 0.16)
	local twitch = bump(t, self.nextTwitch, 0.25)
	local chatter = if t >= self.nextChatter and t <= self.nextChatter + 0.8
		then math.abs(math.sin((t - self.nextChatter) * math.pi * 2.5))
		else 0
	local walk = if self.walking then 1 else 0

	-- Body: breathing bob (bigger for hoverers, a trot bounce while walking).
	local bob = if self.hover then math.sin(p * 2.2) * 0.06 else math.sin(p * 1.6) * 0.012
	bob += walk * math.abs(math.sin(p * 9)) * 0.03
	local rootCf = self.root * CFrame.new(0, bob * self.scale, 0)

	local parts, cframes = { self.body }, { rootCf }
	for _, e in self.parts do
		local local_ = e.rest
		local role = e.role
		if role == "ear" then
			local sway = math.sin(p * 1.3 + e.side) * math.rad(4)
			local flick = if e.side == self.twitchSide then twitch * math.rad(22) else twitch * math.rad(8)
			local_ = about(e.pivot, CFrame.Angles(0, 0, -e.side * (sway + flick))) * local_
		elseif role == "antenna" or role == "crest" then
			local sway = math.sin(p * 2.4) * math.rad(role == "crest" and 5 or 9)
			local_ = about(e.pivot, CFrame.Angles(sway, 0, math.sin(p * 1.7) * math.rad(5))) * local_
		elseif role == "tail" then
			local speed = 5 + walk * 4
			local_ = about(e.pivot, CFrame.Angles(math.sin(p * speed * 0.5) * math.rad(6), math.sin(p * speed) * math.rad(24), 0)) * local_
		elseif role == "wing" then
			local speed = if self.hover then 11 else 4
			local amount = if self.hover then math.rad(32) else math.rad(10)
			local_ = about(e.pivot, CFrame.Angles(0, 0, e.side * math.sin(p * speed) * amount)) * local_
		elseif role == "leg" then
			local swing = walk * math.sin(p * 9 + (if e.front then 0 else math.pi)) * math.rad(28)
			local_ = about(e.pivot, CFrame.Angles(swing, 0, 0)) * local_
		elseif role == "arm" then
			local swing = math.sin(p * (2 + walk * 7) + (if e.side > 0 then 0 else math.pi)) * math.rad(8 + walk * 20)
			local_ = about(e.pivot, CFrame.Angles(swing, 0, 0)) * local_
		elseif role == "head" then
			local_ = about(e.pivot, CFrame.Angles(math.sin(p * 1.2) * math.rad(3), math.sin(p * 0.7) * math.rad(4), 0)) * local_
		end
		-- Squash roles change size, about their own centre.
		if role == "eyes" and self.blink then
			e.part.Size = Vector3.new(e.size.X, e.size.Y * (1 - 0.88 * blink), e.size.Z)
		elseif role == "mouth" and self.chatter then
			e.part.Size = Vector3.new(e.size.X, e.size.Y * (1 + 0.6 * chatter), e.size.Z)
		end
		table.insert(parts, e.part)
		table.insert(cframes, rootCf * local_)
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function Rig:reset()
	for _, e in self.parts do
		e.part.Size = e.size
		e.part.CFrame = self.root * e.rest
	end
	self.body.CFrame = self.root
end

-- Drives every rig from Heartbeat; returns a function that stops and resets them.
function Animator.run(rigs: { any }): () -> ()
	local start = os.clock()
	local connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - start
		for _, rig in rigs do
			if rig.body.Parent then
				if rig.path then
					rig:moveTo(rig.path(t))
				end
				rig:step(t)
			end
		end
	end)
	return function()
		connection:Disconnect()
		for _, rig in rigs do
			rig:reset()
		end
	end
end

return Animator
