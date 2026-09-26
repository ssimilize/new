--[[
	Visuals/RaceTrack (glow-up LR): draws the live-race loop in the world (Config.LiveRace.Track),
	purely decorative — a rider's movement is checked by the server projecting it onto the
	centreline (Logic/LiveRace.Project), never by physics, so nothing here needs to collide.

	RaceTrack.Build() -> Model   builds once under workspace ("LiveRaceTrack"); a second call
	                             replaces the old one (quality changes, tests)
	RaceTrack.Clear()
	RaceTrack.PartCount() -> number   (tests, Studio perf checks)

	A road strip round the oval, a start/finish arch, three checkpoint arches, low hurdle bars,
	a lit strip on the boost pads' side of the track, the start pad platform and the podium
	blocks. `Track.mesh` (optional) would replace the road parts; every piece stays a part with a
	material until an id is uploaded.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Logic = require(ReplicatedStorage.Shared.Logic.LiveRace)

local Cfg = Config.LiveRace
local Track = Cfg.Track

local ROAD_COLOR = Color3.fromHex("#5B4636")
local EDGE_COLOR = Color3.fromHex("#E8E2D6")
local ARCH_COLOR = Color3.fromHex("#C0573E")
local HURDLE_COLOR = Color3.fromHex("#FFFFFF")
local PAD_COLOR = Color3.fromHex("#7FD8FF")
local START_COLOR = Color3.fromHex("#3A7D44")
local PODIUM_COLORS = { Color3.fromHex("#FFD447"), Color3.fromHex("#C7C7C7"), Color3.fromHex("#B8733A") }

local RaceTrack = {}

local model: Model? = nil

-- Yaw (Y radians) so a part's LookVector faces (dx, 0, dz): Roblox's CFrame.Angles(0, yaw, 0)
-- gives LookVector = (-sin(yaw), 0, -cos(yaw)). Shared with Controllers/LiveRace (riders face
-- their direction of travel the same way).
function RaceTrack.Yaw(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end
local yawFor = RaceTrack.Yaw

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end

local function buildRoad(parent: Instance)
	local steps = math.max(48, Track.curveSegments * 8)
	local len = Logic.Length()
	local segLen = len / steps
	-- On the curves a straight piece must reach round the outer edge (radius + halfWidth), which is
	-- longer than the centreline: stretch the road by that ratio there so no grass shows between
	-- pieces; each edge line follows its own radius (+ lateral = the inside of the loop).
	local stretch = Track.halfWidth / Track.radius
	local edgeStretch = (Track.halfWidth - 0.6) / Track.radius
	for i = 0, steps - 1 do
		local u = (i + 0.5) * segLen
		local x, z, dx, dz = Logic.Point(u)
		local yaw = yawFor(dx, dz)
		local curve = Logic.IsCurve(u)
		local pieceLen = segLen * (if curve then 1 + stretch else 1) + 0.6
		part(
			parent,
			"Road" .. i,
			Vector3.new(Track.halfWidth * 2, 0.4, pieceLen), -- Z runs along the track (Yaw)
			CFrame.new(x, Track.center[2] + Track.roadY, z) * CFrame.Angles(0, yaw, 0),
			ROAD_COLOR,
			Enum.Material.Concrete
		)
		-- Edge lines (inside and outside).
		for _, side in { -1, 1 } do
			local ex, ez = Logic.Point(u, side * (Track.halfWidth - 0.6))
			part(
				parent,
				string.format("Edge%d_%d", i, side),
				Vector3.new(0.8, 0.45, segLen * (if curve then 1 - side * edgeStretch else 1) + 0.6),
				CFrame.new(ex, Track.center[2] + Track.roadY + 0.05, ez) * CFrame.Angles(0, yaw, 0),
				EDGE_COLOR
			)
		end
	end
end

local function buildArch(parent: Instance, name: string, u: number, color: Color3)
	local x, z, dx, dz = Logic.Point(u)
	local yaw = yawFor(dx, dz)
	local cf = CFrame.new(x, Track.center[2], z) * CFrame.Angles(0, yaw, 0)
	local width = Track.halfWidth * 2 + 4
	part(parent, name .. "_L", Vector3.new(1.2, 14, 1.2), cf * CFrame.new(-width / 2, 7, 0), color)
	part(parent, name .. "_R", Vector3.new(1.2, 14, 1.2), cf * CFrame.new(width / 2, 7, 0), color)
	part(parent, name .. "_Top", Vector3.new(width + 1.2, 1.2, 1.2), cf * CFrame.new(0, 14, 0), color)
end

local function buildHurdles(parent: Instance)
	for i, f in Cfg.Hurdles do
		local u = f * Logic.Length()
		local x, z, dx, dz = Logic.Point(u)
		local yaw = yawFor(dx, dz)
		part(
			parent,
			"Hurdle" .. i,
			Vector3.new(Track.halfWidth * 2 - 2, 3, 1),
			CFrame.new(x, Track.center[2] + 1.5, z) * CFrame.Angles(0, yaw, 0),
			HURDLE_COLOR,
			Enum.Material.Neon
		)
	end
end

local function buildBoostPads(parent: Instance)
	for i, pad in Cfg.BoostPads do
		local u = pad.at * Logic.Length()
		local lateral = pad.side * (Track.halfWidth * 0.6)
		local x, z, dx, dz = Logic.Point(u, lateral)
		local yaw = yawFor(dx, dz)
		local p = part(
			parent,
			"BoostPad" .. i,
			Vector3.new(Track.halfWidth - 1, 0.5, Cfg.PadLength),
			CFrame.new(x, Track.center[2] + Track.roadY + 0.1, z) * CFrame.Angles(0, yaw, 0),
			PAD_COLOR,
			Enum.Material.Neon
		)
		p.Transparency = 0.15
	end
end

local function buildStartAndPodium(parent: Instance)
	part(parent, "StartPad", Vector3.new(14, 1, 10), CFrame.new(Cfg.StartPad[1], Cfg.StartPad[2] + 0.5, Cfg.StartPad[3]), START_COLOR)
	for i, color in PODIUM_COLORS do
		local height = 5 - i
		part(
			parent,
			"Podium" .. i,
			Vector3.new(6, height, 6),
			CFrame.new(Cfg.Podium[1] + (i - 2) * 7, Cfg.Podium[2] + height / 2, Cfg.Podium[3]),
			color
		)
	end
end

function RaceTrack.Clear()
	if model then
		model:Destroy()
		model = nil
	end
end

function RaceTrack.Build(): Model
	RaceTrack.Clear()
	local m = Instance.new("Model")
	m.Name = "LiveRaceTrack"
	buildRoad(m)
	for i, f in Cfg.Checkpoints do
		buildArch(m, "Checkpoint" .. i, f * Logic.Length(), if f >= 1 then ARCH_COLOR else EDGE_COLOR)
	end
	buildHurdles(m)
	buildBoostPads(m)
	buildStartAndPodium(m)
	m.Parent = workspace
	model = m
	return m
end

function RaceTrack.PartCount(): number
	if not model then
		return 0
	end
	local n = 0
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

return RaceTrack
