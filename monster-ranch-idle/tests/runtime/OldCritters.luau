--[[
	Critters controller (Ambience "butterflies", "fireflies", "birds", "fish"): small life near the camera.

	  butterflies  by day: two flapping wing parts fluttering round flowers, sunflowers and pen floors
	  fireflies    at night: blinking Neon specks drifting over the same spots
	  birds        by day: perch on birdhouses and pen rails, peck, and scatter to another perch
	               (or away) when the player runs past (Config.Ambience.Critters.birds.scare)
	  fish         carp circling in the plaza fountain's basin

	Every critter is a handful of anchored, non-colliding, shadowless parts from a pool (built on
	first use, never more than `max`, parked out of the Workspace when unused). Once a second the
	spots near the camera are picked (Logic/Ambience.Nearest); critters move `rate` times a second.
	lowGraphics: no butterflies, birds or fish, and 5 fireflies. Day and night follow
	Lighting.ClockTime through the same curve as the lights (Config.Ambience.Lights on / off).
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Ambience)
local SceneryIndex = require(script.Parent.Parent.Visuals.SceneryIndex)
local Quality = require(script.Parent.Parent.Visuals.Quality)
local Streaming = require(script.Parent.Parent.Visuals.Streaming)

local Cfg = Config.Ambience
local C = Cfg.Critters

local Critters = {
	Name = "Critters",
	Dependencies = {},
}

local TAU = math.pi * 2
local PARK = CFrame.new(0, -1000, 0)

type Critter = {
	kind: string,
	parts: { BasePart },
	shown: boolean,
	seed: number,
	anchor: Vector3?, -- where it hangs about (butterflies, fireflies, fish centre)
	pos: Vector3,
	-- birds
	state: string?,
	from: Vector3?,
	to: Vector3?,
	t: number,
	duration: number,
	heading: number,
	backAt: number,
}

local ctx
local connections = {}
local lowGraphics = false -- Visuals/Quality.IsLow() (glow-up P), set in Start
local folder: Folder? = nil
local pools: { [string]: { Critter } } = { butterflies = {}, fireflies = {}, birds = {}, fish = {} }
local sincePick = math.huge
local sinceMove = 0
local clock = 0
local night = 0
local penPoints: { Vector3 } = {}
local railPoints: { Vector3 } = {}
local fountainWater: BasePart? = nil
local fountainBasin: BasePart? = nil
local worldScanned = false
local worldWatched = false
local lastPlayerPos: Vector3? = nil
local playerSpeed = 0
-- Spots are rebuilt only when the scenery index changes (scanWorld resets the version).
local spotCache: { [string]: { Vector3 } } = {}
local spotVersion = -1

local function rand(a: number, b: number): number
	return a + (b - a) * math.random()
end

local function layer(name: string): boolean
	return Logic.Enabled(Cfg.Layers, name, Lighting:GetAttribute("Ambience_" .. name))
end

local function critterFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "AmbienceCritters"
	f.Parent = workspace
	folder = f
	return f
end

local function bit(shape: string, size: Vector3, color: string, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = "Critter"
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	end
	p.Size = size
	p.Color = Color3.fromHex(color)
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = PARK
	return p
end

local function newCritter(kind: string, index: number): Critter
	local parts = {}
	if kind == "butterflies" then
		local color = C.butterflies.colors[(index - 1) % #C.butterflies.colors + 1]
		parts = { bit("Block", Vector3.new(0.45, 0.04, 0.38), color), bit("Block", Vector3.new(0.45, 0.04, 0.38), color) }
	elseif kind == "fireflies" then
		local p = bit("Ball", Vector3.new(0.22, 0.22, 0.22), C.fireflies.color, Enum.Material.Neon)
		parts = { p }
	elseif kind == "birds" then
		local color = C.birds.colors[(index - 1) % #C.birds.colors + 1]
		parts = {
			bit("Ball", Vector3.new(0.6, 0.6, 0.6), color), -- body
			bit("Ball", Vector3.new(0.38, 0.38, 0.38), color), -- head
			bit("Block", Vector3.new(0.1, 0.1, 0.2), "#F2A93B"), -- beak
			bit("Block", Vector3.new(0.5, 0.05, 0.3), color), -- wing L
			bit("Block", Vector3.new(0.5, 0.05, 0.3), color), -- wing R
		}
	else
		local color = C.fish.colors[(index - 1) % #C.fish.colors + 1]
		parts = { bit("Block", Vector3.new(0.35, 0.22, 0.9), color), bit("Block", Vector3.new(0.3, 0.18, 0.3), color) }
	end
	local c: Critter = {
		kind = kind,
		parts = parts,
		shown = false,
		seed = index * 2.39 + #kind,
		pos = Vector3.zero,
		t = 0,
		duration = 1,
		heading = 0,
		backAt = 0,
	}
	return c
end

local function show(c: Critter, on: boolean)
	if c.shown == on then
		return
	end
	c.shown = on
	local parent = if on then critterFolder() else nil
	for _, p in c.parts do
		if not on then
			p.CFrame = PARK
		end
		p.Parent = parent
	end
end

-- Grows the pool to `n` and shows the first n; the rest are parked.
local function ensure(kind: string, n: number): { Critter }
	local pool = pools[kind]
	while #pool < n do
		table.insert(pool, newCritter(kind, #pool + 1))
	end
	for i, c in pool do
		if i > n then
			show(c, false)
			c.anchor = nil
			c.state = nil
		end
	end
	return pool
end

local function scanWorld()
	local world = workspace:FindFirstChild("World")
	if not world then
		return
	end
	worldScanned = true
	spotVersion = -1
	if not worldWatched then
		-- StreamingEnabled (glow-up P): pens, rails and the fountain can stream in later.
		worldWatched = true
		local rescan = function()
			worldScanned = false
		end
		for _, name in { "Plots", "Hub" } do
			table.insert(
				connections,
				Streaming.OnChild(world, name, function(child)
					rescan()
					for _, connection in Streaming.WatchTree(child, 1, rescan) do
						table.insert(connections, connection)
					end
				end)
			)
		end
	end
	table.clear(penPoints)
	table.clear(railPoints)
	local plots = world:FindFirstChild("Plots")
	for _, d in if plots then plots:GetDescendants() else {} do
		if d:IsA("BasePart") then
			if d.Name == "Floor" and d:GetAttribute("PenIndex") ~= nil then
				table.insert(penPoints, d.Position + Vector3.new(0, d.Size.Y / 2, 0))
			elseif string.sub(d.Name, 1, 4) == "Rail" then
				table.insert(railPoints, d.Position + Vector3.new(0, d.Size.Y / 2, 0))
			end
		end
	end
	local hub = world:FindFirstChild("Hub")
	local fountain = hub and hub:FindFirstChild("Fountain")
	local water = fountain and fountain:FindFirstChild("Water")
	local basin = fountain and fountain:FindFirstChild("Basin")
	fountainWater = if water and water:IsA("BasePart") then water else nil
	fountainBasin = if basin and basin:IsA("BasePart") then basin else nil
end

local function cached(key: string, build: () -> { Vector3 }): { Vector3 }
	if spotVersion ~= SceneryIndex.Version() then
		spotVersion = SceneryIndex.Version()
		table.clear(spotCache)
	end
	local list = spotCache[key]
	if not list then
		list = build()
		spotCache[key] = list
	end
	return list
end

-- Flower spots: flowers and sunflowers (their tops), then pen floors.
local function buildFlowerSpots(): { Vector3 }
	local spots = {}
	for _, kind in { "flowers", "sunflowers" } do
		for _, part in SceneryIndex.Get(kind) do
			table.insert(spots, part.Position + Vector3.new(0, part.Size.Y / 2, 0))
		end
	end
	for _, p in penPoints do
		table.insert(spots, p)
	end
	return spots
end

local function buildPerchSpots(): { Vector3 }
	local spots = {}
	for _, part in SceneryIndex.Get("birdhouse") do
		table.insert(spots, part.Position + Vector3.new(0, part.Size.Y / 2, 0))
	end
	for _, p in railPoints do
		table.insert(spots, p)
	end
	return spots
end

local function flowerSpots(): { Vector3 }
	return cached("flowers", buildFlowerSpots)
end

local function perchSpots(): { Vector3 }
	return cached("perches", buildPerchSpots)
end

-- ─── Picking ─────────────────────────────────────────────────────────────────────────

local function assignAnchors(kind: string, spots: { Vector3 }, x: number, z: number, entry, active: boolean)
	local cap = if active then Logic.Cap(entry, lowGraphics) else 0
	local chosen = Logic.Nearest(spots, x, z, entry.radius, cap)
	local pool = ensure(kind, #chosen)
	for i, index in chosen do
		local c = pool[i]
		local spot = spots[index]
		if not c.anchor then
			c.pos = spot + Vector3.new(0, 1.5, 0)
		end
		c.anchor = spot
		show(c, true)
	end
end

local function flyTo(c: Critter, to: Vector3, state: string)
	c.from = c.pos
	c.to = to
	c.t = 0
	c.duration = math.clamp((to - c.pos).Magnitude / 14, 0.8, 4)
	c.state = state
end

local function pickBirds(x: number, z: number, active: boolean)
	local entry = C.birds
	local cap = if active then Logic.Cap(entry, lowGraphics) else 0
	local spots = perchSpots()
	local chosen = Logic.Nearest(spots, x, z, entry.radius, cap)
	local pool = pools.birds
	for i = 1, math.max(#pool, #chosen) do
		local c = pool[i]
		if i <= #chosen then
			if not c then
				c = newCritter("birds", i)
				pool[i] = c
			end
			if not c.shown and clock >= c.backAt then
				-- arrive from the sky
				local perch = spots[chosen[i]]
				c.pos = perch + Vector3.new(rand(-20, 20), 25, rand(-20, 20))
				show(c, true)
				flyTo(c, perch, "fly")
			end
		elseif c and c.shown and c.state ~= "leave" then
			flyTo(c, c.pos + Vector3.new(rand(-30, 30), 30, rand(-30, 30)), "leave")
		end
	end
end

local function pick()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if not worldScanned then
		scanWorld()
	end
	local p = camera.CFrame.Position
	night = Logic.Night(tonumber(Lighting.ClockTime) or 14, Cfg.Lights.on, Cfg.Lights.off)
	local day = night < 0.5
	local spots = flowerSpots()
	assignAnchors("butterflies", spots, p.X, p.Z, C.butterflies, day and layer("butterflies"))
	assignAnchors("fireflies", spots, p.X, p.Z, C.fireflies, not day and layer("fireflies"))
	pickBirds(p.X, p.Z, day and layer("birds"))
	-- fish: the fountain, when the camera is near
	local water = fountainWater
	local fishOn = false
	if water and water.Parent and layer("fish") then
		local dx, dz = water.Position.X - p.X, water.Position.Z - p.Z
		fishOn = dx * dx + dz * dz <= C.fish.radius * C.fish.radius
	end
	local n = if fishOn then Logic.Cap(C.fish, lowGraphics) else 0
	local pool = ensure("fish", n)
	for i = 1, n do
		local c = pool[i]
		c.anchor = (water :: BasePart).Position
		show(c, true)
	end
end

-- ─── Movement ────────────────────────────────────────────────────────────────────────

local function moveButterfly(c: Critter)
	local s, t = c.seed, clock
	local anchor = c.anchor :: Vector3
	local target = anchor + Vector3.new(math.sin(t * 0.9 + s) * 2.5, 1.2 + math.sin(t * 1.7 + s) * 0.6, math.cos(t * 0.7 + s * 1.3) * 2.5)
	local previous = c.pos
	c.pos = previous:Lerp(target, 0.12)
	local v = c.pos - previous
	if v.Magnitude > 1e-3 then
		c.heading = math.atan2(-v.X, -v.Z)
	end
	local flap = math.rad(55) * math.sin(t * 18 + s)
	local base = CFrame.new(c.pos) * CFrame.Angles(0, c.heading, 0)
	c.parts[1].CFrame = base * CFrame.Angles(0, 0, flap) * CFrame.new(-0.22, 0, 0)
	c.parts[2].CFrame = base * CFrame.Angles(0, 0, -flap) * CFrame.new(0.22, 0, 0)
end

local function moveFirefly(c: Critter)
	local s, t = c.seed, clock
	local anchor = c.anchor :: Vector3
	local target = anchor
		+ Vector3.new(math.sin(t * 0.31 + s) * 3, 1.6 + math.sin(t * 0.53 + s * 2) * 1.1, math.cos(t * 0.27 + s * 1.7) * 3)
	c.pos = c.pos:Lerp(target, 0.05)
	local p = c.parts[1]
	p.CFrame = CFrame.new(c.pos)
	-- a slow pulse with a quick bright blink now and then
	local pulse = 0.5 + 0.5 * math.sin(t * 2.2 + s * 3)
	p.Transparency = 0.85 - 0.75 * pulse * pulse * night
end

local function birdPose(c: Critter, flapping: boolean)
	local base = CFrame.new(c.pos) * CFrame.Angles(0, c.heading, 0)
	local t, s = clock, c.seed
	local peck = 0
	if not flapping then
		-- a peck every few seconds
		local cycle = (t * 0.45 + s) % 1
		peck = if cycle < 0.12 then math.sin(cycle / 0.12 * math.pi) else 0
	end
	c.parts[1].CFrame = base * CFrame.new(0, 0.3, 0)
	local head = base * CFrame.new(0, 0.7 - peck * 0.3, -0.3 - peck * 0.15)
	c.parts[2].CFrame = head
	c.parts[3].CFrame = head * CFrame.new(0, -0.03, -0.24)
	local flap = if flapping then math.rad(60) * math.sin(t * 22 + s) else math.rad(-10)
	c.parts[4].CFrame = base * CFrame.new(-0.25, 0.4, 0) * CFrame.Angles(0, 0, flap) * CFrame.new(-0.2, 0, 0)
	c.parts[5].CFrame = base * CFrame.new(0.25, 0.4, 0) * CFrame.Angles(0, 0, -flap) * CFrame.new(0.2, 0, 0)
end

local function scatter(c: Critter, player: Vector3)
	local best, bestD = nil, 0
	for _, spot in perchSpots() do
		local d = (Vector3.new(spot.X, 0, spot.Z) - Vector3.new(player.X, 0, player.Z)).Magnitude
		if d > 25 and d < C.birds.radius and (not best or d < bestD) then
			best, bestD = spot, d
		end
	end
	if best then
		flyTo(c, best, "fly")
	else
		flyTo(c, c.pos + Vector3.new(rand(-30, 30), 30, rand(-30, 30)), "leave")
	end
end

local function moveBird(c: Critter, dt: number, player: Vector3?)
	if c.state == "fly" or c.state == "leave" then
		c.t += dt
		local from, to = c.from :: Vector3, c.to :: Vector3
		local p = math.clamp(c.t / c.duration, 0, 1)
		local e = p * p * (3 - 2 * p)
		local arc = math.sin(p * math.pi) * math.min(4, (to - from).Magnitude * 0.2)
		local d = to - from
		if Vector3.new(d.X, 0, d.Z).Magnitude > 0.1 then
			c.heading = math.atan2(-d.X, -d.Z)
		end
		c.pos = from:Lerp(to, e) + Vector3.new(0, arc, 0)
		birdPose(c, true)
		if p >= 1 then
			if c.state == "leave" then
				show(c, false)
				c.state = nil
				c.backAt = clock + rand(6, 12)
			else
				c.state = "perch"
			end
		end
	else
		birdPose(c, false)
		if player and Logic.Scared(c.pos, player, playerSpeed, C.birds) then
			scatter(c, player)
		end
	end
end

local function moveFish(c: Critter)
	local water = fountainWater
	if not water then
		return
	end
	local surface = water.Position.Y + water.Size.X / 2
	if fountainBasin then
		surface = math.max(surface, fountainBasin.Position.Y + fountainBasin.Size.X / 2)
	end
	local reach = water.Size.Y / 2 - 1.5
	local s, t = c.seed, clock
	local r = math.clamp(reach * (0.45 + 0.25 * math.sin(t * 0.2 + s)), 1.5, math.max(1.5, reach))
	local a = t * (0.25 + (s % 1) * 0.15) + s * TAU
	local centre = water.Position
	c.pos = Vector3.new(centre.X + math.cos(a) * r, surface - 0.05, centre.Z + math.sin(a) * r)
	-- facing along the circle (tangent), with a little tail wag
	local heading = math.atan2(math.sin(a), -math.cos(a))
	local wag = math.sin(t * 6 + s) * 0.35
	local body = CFrame.new(c.pos) * CFrame.Angles(0, heading, 0)
	c.parts[1].CFrame = body
	c.parts[2].CFrame = body * CFrame.new(0, 0, 0.55) * CFrame.Angles(0, wag, 0)
end

local function move(dt: number)
	local character = ctx.Player and ctx.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local player: Vector3? = if root and root:IsA("BasePart") then root.Position else nil
	if player and lastPlayerPos and dt > 0 then
		local d = player - lastPlayerPos
		playerSpeed = Vector3.new(d.X, 0, d.Z).Magnitude / dt
	end
	lastPlayerPos = player
	for _, c in pools.butterflies do
		if c.shown and c.anchor then
			moveButterfly(c)
		end
	end
	for _, c in pools.fireflies do
		if c.shown and c.anchor then
			moveFirefly(c)
		end
	end
	for _, c in pools.birds do
		if c.shown then
			moveBird(c, dt, player)
		end
	end
	for _, c in pools.fish do
		if c.shown then
			moveFish(c)
		end
	end
end

local function step(dt: number)
	clock += dt
	sincePick += dt
	sinceMove += dt
	if sincePick >= C.pick then
		sincePick = 0
		pick()
	end
	if sinceMove >= 1 / C.rate then
		move(sinceMove)
		sinceMove = 0
	end
end

function Critters.Init(context)
	ctx = context
end

function Critters.Start()
	SceneryIndex.Start()
	lowGraphics = Quality.IsLow()
	table.insert(
		connections,
		Quality.Changed:Connect(function()
			if Quality.IsLow() ~= lowGraphics then
				lowGraphics = Quality.IsLow()
				sincePick = math.huge
			end
		end)
	)
	table.insert(connections, RunService.Heartbeat:Connect(step))
end

-- Tests: shown critters by kind, and the pool sizes (parts ever built).
function Critters.Stats(): ({ [string]: number }, { [string]: number })
	local shown, built = {}, {}
	for kind, pool in pools do
		local n = 0
		for _, c in pool do
			if c.shown then
				n += 1
			end
		end
		shown[kind] = n
		built[kind] = #pool
	end
	return shown, built
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function Critters.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, pool in pools do
		for _, c in pool do
			for _, p in c.parts do
				p:Destroy()
			end
		end
		table.clear(pool)
	end
	if folder then
		folder:Destroy()
	end
end

return Critters
