--[[
	BugMeadow controller (update 3.13 · Wild things): the Bug Catching Meadow west of the Market
	Square (Config.World.BugMeadow, a circle scenery keeps off), built on this client from Parts:
	a grass disc, wildflowers and tall grass tufts on a seeded layout, a signpost with a "Catch bugs"
	prompt -> Router:Open("Bugs") (the screen shows its own lock), and a few bugs fluttering over
	the flowers (Meadow.bugs; Meadow.lowBugs in low graphics, none with Reduced motion).
	Everything stays inside the circle's radius. Nothing is built in the hub place.

	Public (for specs):
	  BugMeadow.Prompt() -> ProximityPrompt?
	  BugMeadow.Stats() -> (flutterers, flowers)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Rng = require(Shared.Logic.Rng)

local Client = script.Parent.Parent
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)

local New = Create.New

local BugMeadow = {
	Name = "BugMeadow",
	Dependencies = {},
}

local Meadow = {
	flowers = 44,
	tufts = 30,
	bugs = 6,
	lowBugs = 2,
	promptDistance = 12,
	edge = 2, -- studs kept clear inside the circle's edge
}

local ctx
local folder: Folder? = nil
local bugFolder: Folder? = nil
local prompt: ProximityPrompt? = nil
local flutterers = {} -- { { model, home, phase, speed, r } }
local flowerCount = 0
local lowGraphics, reducedMotion = false, false
local connections = {}
local clock = 0

local PETALS = { "#F7A8C8", "#FFFFFF", "#F5D547", "#B9A7FF", "#FF8A5B", "#8FD3FF" }
local BUG_COLORS = { "#E5484D", "#F5D547", "#4FA3E0", "#F28C28", "#C58CFF", "#F4F1E6" }

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function spot(rng, maxR: number): (number, number)
	local a = rng:Next() * math.pi * 2
	local r = math.sqrt(rng:Next()) * maxR
	return math.cos(a) * r, math.sin(a) * r
end

local function openScreen()
	if ctx.Router:Has("Bugs") then
		ctx.Router:Open("Bugs")
	end
end

local function buildSign(f: Folder, cx: number, cz: number, y: number)
	local post = part({
		Name = "Signpost",
		Size = Vector3.new(0.6, 5, 0.6),
		CFrame = CFrame.new(cx, y + 2.5, cz + 16),
		Color = Color3.fromHex("#8A5A2B"),
		Material = Enum.Material.Wood,
		CanCollide = true,
		CanQuery = true,
		Parent = f,
	})
	local board = part({
		Name = "SignBoard",
		Size = Vector3.new(6, 2, 0.3),
		CFrame = CFrame.new(cx, y + 4.4, cz + 16.2),
		Color = Color3.fromHex("#C8955A"),
		Material = Enum.Material.WoodPlanks,
		Parent = f,
	})
	local gui = New("SurfaceGui", { Face = Enum.NormalId.Back, CanvasSize = Vector2.new(300, 100), LightInfluence = 0, Parent = board })
	Create.Text({
		Text = "Bug Catching Meadow",
		TextSize = Theme.TextSize.Title,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	local anchor = Instance.new("Attachment")
	anchor.Name = "PromptAnchor"
	anchor.Position = Vector3.new(0, 0, 0)
	anchor.Parent = post
	local p = Instance.new("ProximityPrompt")
	p.Name = "BugsPrompt"
	p.ActionText = "Catch bugs"
	p.ObjectText = "Bug Catching Meadow"
	p.HoldDuration = 0
	p.MaxActivationDistance = Meadow.promptDistance
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Parent = anchor
	table.insert(connections, p.Triggered:Connect(openScreen))
	prompt = p
end

local function buildMeadow()
	local area = Config.World.BugMeadow
	local cx, cz, radius = area.center[1], area.center[2], area.radius
	local y = Config.World.GroundY or 0
	local f = Instance.new("Folder")
	f.Name = "BugMeadow"
	part({
		Name = "Ground",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, radius * 2, radius * 2),
		CFrame = CFrame.new(cx, y + 0.1, cz) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromHex("#8CCB5E"),
		Material = Enum.Material.Grass,
		Parent = f,
	})
	local rng = Rng.new(Rng.seed("bug_meadow", 1))
	local inner = radius - Meadow.edge
	flowerCount = 0
	for i = 1, Meadow.flowers do
		local dx, dz = spot(rng, inner)
		local h = 0.8 + rng:Next() * 0.8
		part({
			Name = "Stem",
			Size = Vector3.new(0.12, h, 0.12),
			CFrame = CFrame.new(cx + dx, y + h / 2, cz + dz),
			Color = Color3.fromHex("#4E8F3A"),
			Parent = f,
		})
		part({
			Name = "Flower",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.5, 0.5, 0.5),
			CFrame = CFrame.new(cx + dx, y + h, cz + dz),
			Color = Color3.fromHex(PETALS[(i - 1) % #PETALS + 1]),
			Material = Enum.Material.SmoothPlastic,
			Parent = f,
		})
		flowerCount += 1
	end
	for _ = 1, Meadow.tufts do
		local dx, dz = spot(rng, inner)
		local h = 1.2 + rng:Next() * 1.2
		for k = 0, 2 do
			part({
				Name = "Tuft",
				Size = Vector3.new(0.15, h, 0.4),
				CFrame = CFrame.new(cx + dx, y + h / 2, cz + dz) * CFrame.Angles(math.rad(10 - k * 10), math.rad(k * 60), 0),
				Color = Color3.fromHex("#6FAF45"),
				Parent = f,
			})
		end
	end
	buildSign(f, cx, cz, y)
	f.Parent = workspace
	folder = f
end

local function clearBugs()
	table.clear(flutterers)
	if bugFolder then
		bugFolder:Destroy()
		bugFolder = nil
	end
end

local function buildBugs()
	clearBugs()
	if not folder then
		return
	end
	local count = if reducedMotion then 0 elseif lowGraphics then Meadow.lowBugs else Meadow.bugs
	if count == 0 then
		return
	end
	local area = Config.World.BugMeadow
	local y = Config.World.GroundY or 0
	local rng = Rng.new(Rng.seed("bug_meadow_flutter", 1))
	local bf = Instance.new("Folder")
	bf.Name = "Flutterers"
	for i = 1, count do
		local dx, dz = spot(rng, area.radius - Meadow.edge - 4)
		local model = Instance.new("Model")
		model.Name = "Flutterer"
		local body = part({
			Name = "Body",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.35, 0.35, 0.35),
			Color = Color3.fromHex(BUG_COLORS[(i - 1) % #BUG_COLORS + 1]),
			Parent = model,
		})
		model.PrimaryPart = body
		for side = -1, 1, 2 do
			local wing = part({
				Name = "Wing",
				Size = Vector3.new(0.5, 0.05, 0.35),
				Color = Color3.fromHex("#F4FBFF"),
				Transparency = 0.3,
				Parent = model,
			})
			wing:SetAttribute("Side", side)
		end
		model.Parent = bf
		table.insert(flutterers, {
			model = model,
			home = Vector3.new(area.center[1] + dx, y + 2.5, area.center[2] + dz),
			phase = rng:Next() * math.pi * 2,
			speed = 0.6 + rng:Next() * 0.6,
			r = 1.5 + rng:Next() * 2,
		})
	end
	bf.Parent = folder
	bugFolder = bf
end

local function animate(dt: number)
	clock += dt
	for _, b in flutterers do
		local a = clock * b.speed + b.phase
		local at = b.home + Vector3.new(math.cos(a) * b.r, math.sin(a * 3) * 0.4, math.sin(a * 1.3) * b.r)
		local flap = math.sin(clock * 24 + b.phase) * 0.6
		for _, p in b.model:GetChildren() do
			if p:IsA("BasePart") then
				local side = p:GetAttribute("Side")
				if side then
					p.CFrame = CFrame.new(at) * CFrame.new(side * 0.3, 0, 0) * CFrame.Angles(0, 0, side * flap)
				else
					p.CFrame = CFrame.new(at)
				end
			end
		end
	end
end

function BugMeadow.Init(context)
	ctx = context
end

function BugMeadow.Start()
	local built = false
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			if not built then
				if not ctx.Store.Ready or ctx.Store:Get("global.TradingHub.mode") == "hub" then
					return
				end
				built = true
				buildMeadow()
				buildBugs()
				table.insert(
					connections,
					ctx.Store:Observe("profile.Settings", function(settings)
						local low = type(settings) == "table" and settings.lowGraphics == true
						local calm = type(settings) == "table" and settings.reducedMotion == true
						if low ~= lowGraphics or calm ~= reducedMotion then
							lowGraphics, reducedMotion = low, calm
							buildBugs()
						end
					end)
				)
			end
			if #flutterers > 0 then
				animate(dt)
			end
		end)
	)
end

function BugMeadow.Prompt(): ProximityPrompt?
	return prompt
end

function BugMeadow.Stats(): (number, number)
	return #flutterers, flowerCount
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function BugMeadow.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	clearBugs()
	if folder then
		folder:Destroy()
		folder = nil
	end
	prompt = nil
end

return BugMeadow
