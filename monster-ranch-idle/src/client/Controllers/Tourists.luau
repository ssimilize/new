--[[
	Tourists controller (update 3.10 · Ranch Tourists): the world side of Ranch Tourists. The
	server decides every visit (Systems/Tourists); this only draws them.

	  Guestbook stand  a small lectern of Parts beside every owned plot's gate
	                   (Config.Tourists.World.stand, kept clear of decor by Config.Decor keepOut);
	                   on the own plot it carries an "Open · Guestbook" prompt -> Router:Open("Guestbook")
	  Tourist walk     when global.Tourists.walk['u'..userId] gets a new visit, a Part-built figure
	                   (no avatar loading, no assets) walks from outside the gate to the aisle spot,
	                   pauses with a stars bubble, then walks out and is destroyed. At most one per
	                   plot; other plots are skipped in low graphics and past Decor's hideDistance.

	Everything lives in Workspace.Tourists.Plot<i>. Public (for specs):
	  Tourists.Stats() -> { stands, walking }
	  Tourists.Walker(index) -> Model?   the tourist on that plot now
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Tourists)
local Rng = require(Shared.Logic.Rng)

local Client = script.Parent.Parent
local Quality = require(Client.Visuals.Quality)
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)

local Tourists = {
	Name = "Tourists",
	Dependencies = {},
}

local W = Config.World
local R = Config.Tourists.World
local PLOT_TOP = 0.3
local PROMPT_DISTANCE = 12

local ctx
local player = Players.LocalPlayer
local root: Folder? = nil
local stands = {} -- [plotIndex] = { model, userId }
local walkers = {} -- [plotIndex] = { model, t, total, n }
local seen = {} -- ['u'..userId] = n already walked (or present at start)
local connections = {}

local function plotFrame(index: number): CFrame
	local plot = W.Plots[index]
	local c = plot.center
	return CFrame.new(c[1], W.GroundY or 0, c[3]) * CFrame.Angles(0, math.rad((plot.facing or 0) - 90), 0)
end

local function folderFor(index: number): Folder
	assert(root, "Tourists root")
	local f = root:FindFirstChild("Plot" .. index)
	if not f then
		f = Instance.new("Folder")
		f.Name = "Plot" .. index
		f.Parent = root
	end
	return f :: Folder
end

local function part(name: string, size: Vector3, cf: CFrame, color: string, parent: Instance, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromHex(color)
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Stands ---------------------------------------------------------------------------------------

local function buildStand(index: number, own: boolean)
	local base = plotFrame(index) * CFrame.new(R.stand[1], PLOT_TOP, R.stand[2]) * CFrame.Angles(0, math.rad(90), 0)
	local model = Instance.new("Model")
	model.Name = "GuestbookStand"
	part("Post", Vector3.new(0.6, 3.4, 0.6), base * CFrame.new(0, 1.7, 0), "#8A5A2B", model)
	part("Foot", Vector3.new(2, 0.3, 2), base * CFrame.new(0, 0.15, 0), "#6B4424", model)
	local desk =
		part("Desk", Vector3.new(2.6, 0.3, 1.8), base * CFrame.new(0, 3.5, 0) * CFrame.Angles(math.rad(-20), 0, 0), "#A0703D", model)
	part("Book", Vector3.new(2, 0.2, 1.4), desk.CFrame * CFrame.new(0, 0.25, 0), "#F4EBD9", model)
	part("Ribbon", Vector3.new(0.15, 0.22, 1.5), desk.CFrame * CFrame.new(0, 0.27, 0), "#E5484D", model)
	model.PrimaryPart = desk
	model.Parent = folderFor(index)
	if own then
		local anchor = Instance.new("Attachment")
		anchor.Name = "PromptAnchor"
		anchor.Position = Vector3.new(0, 0.6, 0)
		anchor.Parent = desk
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "GuestbookPrompt"
		prompt.ActionText = "Open"
		prompt.ObjectText = "Guestbook"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = PROMPT_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.Parent = anchor
		prompt.Triggered:Connect(function()
			if ctx.Router:Has("Guestbook") then
				ctx.Router:Open("Guestbook")
			end
		end)
	end
	return model
end

local function syncStands(plots)
	for index = 1, #W.Plots do
		local plot = type(plots) == "table" and plots[index]
		local userId = if type(plot) == "table" then tonumber(plot.userId) or 0 else 0
		local current = stands[index]
		if current and current.userId ~= userId then
			current.model:Destroy()
			stands[index] = nil
			current = nil
		end
		if not current and userId > 0 then
			stands[index] = { model = buildStand(index, userId == player.UserId), userId = userId }
		end
	end
end

-- Walkers --------------------------------------------------------------------------------------

local COLORS = { "#E5484D", "#4FB6F2", "#43B649", "#F2A93B", "#8B6AD8", "#EF6FA8", "#2EC4B6", "#F4C43A" }
local SKIN = { "#F1C9A5", "#D9A77E", "#A8744F", "#6E4A33", "#FFDCB8" }

local function buildFigure(seed: number, stars: number, parent: Instance): Model
	local rng = Rng.new(seed)
	local shirt, pants, hat = rng:Pick(COLORS), rng:Pick(COLORS), rng:Pick(COLORS)
	local skin = rng:Pick(SKIN)
	local model = Instance.new("Model")
	model.Name = "Tourist"
	local at = CFrame.new()
	local torso = part("Torso", Vector3.new(2, 2, 1), at * CFrame.new(0, 3, 0), shirt, model)
	part("LegL", Vector3.new(0.9, 2, 0.9), at * CFrame.new(-0.5, 1, 0), pants, model)
	part("LegR", Vector3.new(0.9, 2, 0.9), at * CFrame.new(0.5, 1, 0), pants, model)
	part("ArmL", Vector3.new(0.8, 1.9, 0.8), at * CFrame.new(-1.4, 3, 0), skin, model)
	part("ArmR", Vector3.new(0.8, 1.9, 0.8), at * CFrame.new(1.4, 3, 0), skin, model)
	local head = part("Head", Vector3.new(1.4, 1.4, 1.4), at * CFrame.new(0, 4.7, 0), skin, model, Enum.PartType.Ball)
	-- A cylinder's axis is its X: stand it up for a flat brim.
	part(
		"Hat",
		Vector3.new(0.3, 1.8, 1.8),
		at * CFrame.new(0, 5.35, 0) * CFrame.Angles(0, 0, math.rad(90)),
		hat,
		model,
		Enum.PartType.Cylinder
	)
	part("Camera", Vector3.new(0.7, 0.5, 0.4), at * CFrame.new(0, 3.2, -0.65), "#2A2419", model)
	model.PrimaryPart = torso

	local bubble = Instance.new("BillboardGui")
	bubble.Name = "Bubble"
	bubble.Adornee = head
	bubble.Size = UDim2.fromOffset(120, 36)
	bubble.StudsOffset = Vector3.new(0, 2.2, 0)
	bubble.MaxDistance = 140
	bubble.LightInfluence = 0
	bubble.AlwaysOnTop = true
	bubble.Enabled = false
	bubble.Parent = model
	local frame = Create.New("Frame", {
		BackgroundColor3 = Color3.fromHex("#FFFFFF"),
		Size = UDim2.fromScale(1, 1),
		Parent = bubble,
	}, { Create.Corner(12), Create.Stroke(2) })
	local label = Create.Text({
		Name = "Stars",
		Text = Logic.StarText(stars),
		TextSize = Theme.TextSize.Body,
		TextColor3 = Color3.fromHex("#F2A93B"),
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	label:SetAttribute("Localize", false)
	model.Parent = parent
	return model
end

local function visible(index: number, userId: number): boolean
	if userId == player.UserId then
		return true
	end
	if Quality.IsLow() then
		return false
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return true
	end
	return (camera.CFrame.Position - plotFrame(index).Position).Magnitude <= Config.Decor.Layout.hideDistance
end

local function startWalk(index: number, userId: number, visit)
	if walkers[index] then
		return -- one tourist per plot at a time
	end
	local frame = plotFrame(index)
	local from = frame * CFrame.new(R.enter[1], PLOT_TOP, R.enter[2])
	local to = frame * CFrame.new(R.spot[1], PLOT_TOP, R.spot[2])
	local walkTime = (from.Position - to.Position).Magnitude / R.speed
	local model = buildFigure(Rng.seed("tourist", userId, visit.n), tonumber(visit.stars) or 1, folderFor(index))
	walkers[index] = { model = model, t = 0, walk = walkTime, from = from, to = to }
end

local HIP = Vector3.new(0, 3, 0) -- the pivot is the torso's centre

local function place(w, cf: CFrame, facing: Vector3)
	local at = cf.Position + HIP
	w.model:PivotTo(CFrame.lookAt(at, at + Vector3.new(facing.X, 0, facing.Z)))
end

local function stepWalkers(dt: number)
	for index, w in walkers do
		w.t += dt
		local dir = w.to.Position - w.from.Position
		local bubble = w.model:FindFirstChild("Bubble")
		if w.t < w.walk then
			place(w, w.from:Lerp(w.to, w.t / w.walk), dir)
		elseif w.t < w.walk + R.pause then
			place(w, w.to, dir)
			if bubble then
				bubble.Enabled = true
			end
		elseif w.t < 2 * w.walk + R.pause then
			if bubble then
				bubble.Enabled = false
			end
			place(w, w.to:Lerp(w.from, (w.t - w.walk - R.pause) / w.walk), -dir)
		else
			w.model:Destroy()
			walkers[index] = nil
		end
	end
end

local function syncWalks()
	local plots = ctx.Store:Get("global.Plots")
	local walk = ctx.Store:Get("global.Tourists.walk")
	if type(plots) ~= "table" or type(walk) ~= "table" then
		return
	end
	local now = workspace:GetServerTimeNow()
	for index = 1, #W.Plots do
		local plot = plots[index]
		local userId = if type(plot) == "table" then tonumber(plot.userId) or 0 else 0
		local key = "u" .. userId
		local visit = walk[key]
		if userId > 0 and type(visit) == "table" and seen[key] ~= visit.n then
			seen[key] = visit.n
			if now - (tonumber(visit.at) or 0) <= R.fresh and visible(index, userId) then
				startWalk(index, userId, visit)
			end
		end
	end
end

-- Lifecycle --------------------------------------------------------------------------------------

function Tourists.Init(context)
	ctx = context
end

function Tourists.Start()
	local folder = Instance.new("Folder")
	folder.Name = "Tourists"
	folder.Parent = workspace
	root = folder
	syncStands(ctx.Store:Get("global.Plots"))
	syncWalks()
	table.insert(
		connections,
		ctx.Store:Observe("global.Plots", function()
			syncStands(ctx.Store:Get("global.Plots"))
			syncWalks()
		end)
	)
	table.insert(connections, ctx.Store:Observe("global.Tourists", syncWalks))
	table.insert(connections, RunService.Heartbeat:Connect(stepWalkers))
end

function Tourists.Destroy()
	for _, c in connections do
		-- Heartbeat connections and Store observers both have :Disconnect().
		c:Disconnect()
	end
	table.clear(connections)
	if root then
		root:Destroy()
		root = nil
	end
	table.clear(stands)
	table.clear(walkers)
end

function Tourists.Stats()
	local nStands, nWalking = 0, 0
	for _ in stands do
		nStands += 1
	end
	for _ in walkers do
		nWalking += 1
	end
	return { stands = nStands, walking = nWalking }
end

function Tourists.Walker(index: number): Model?
	local w = walkers[index]
	return w and w.model
end

return Tourists
