--[[
	Apiary controller (update 3.12 · Honey & stars): the beehives on the local player's own plot,
	at Config.Apiary.World (plot-local centre (-8, 0, -47), the north strip between the pens and
	the Fishing Pond; keep-out in Config.Decor). Built from Parts on the client, like the 3.11
	merchant caravan: no assets, no server geometry.

	  three stands in a row (legs and a board); an open hive stands on each (box hives 1 and 3,
	  a straw skep on 2); a locked hive shows its empty stand. A tended hive has a few bees
	  (small Parts) circling it, none on Low graphics or with reduced motion.
	  a "Tend · Apiary" prompt on the middle stand -> Router:Open("Apiary") (the screen shows
	  its own lock before Ranch Level 14).

	Everything lives in Workspace.Apiary (outside Workspace.World, so the Interaction
	controller's geometry rescans never see it). Rebuilt when the own plot, the open hive count
	or the keepers change. Public (for specs):
	  Apiary.Model() -> Model?             the apiary now (nil without an own plot)
	  Apiary.Prompt() -> ProximityPrompt?
	  Apiary.Bees() -> number              bee parts flying now
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Apiary)
local Quality = require(script.Parent.Parent.Visuals.Quality)
local Anim = require(script.Parent.Parent.UI.Anim)

local Apiary = {
	Name = "Apiary",
	Dependencies = {},
}

local W = Config.Apiary.World
local BEES_PER_HIVE = 3

local ctx
local player = Players.LocalPlayer
local root: Folder? = nil
local model: Model? = nil
local prompt: ProximityPrompt? = nil
local bees = {} -- { { part, center: Vector3, radius, speed, phase } }
local connections = {}
local builtKey = ""
local clock = 0

local function part(
	name: string,
	size: Vector3,
	cf: CFrame,
	color: string,
	parent: Instance,
	shape: Enum.PartType?,
	mat: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Color = Color3.fromHex(color)
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function ownPlot(): number?
	local plots = ctx.Store:Get("global.Plots")
	if type(plots) ~= "table" then
		return nil
	end
	for i, plot in plots do
		if type(plot) == "table" and plot.userId == player.UserId then
			return i
		end
	end
	return nil
end

local function plotFrame(index: number): CFrame?
	local def = Config.World.Plots[index]
	if not def then
		return nil
	end
	local c = def.center
	return CFrame.new(c[1], Config.World.GroundY, c[3]) * CFrame.Angles(0, math.rad((def.facing or 0) - 90), 0)
end

local function openHives(): number
	local s = ctx.Store:Get("session.Apiary")
	if type(s) == "table" and type(s.hives) == "number" then
		return s.hives
	end
	local level = tonumber(ctx.Store:Get("profile.Progression.level")) or 1
	return Logic.HiveCount(function(key)
		local need = Config.Unlocks.Features[key]
		return need ~= nil and level >= need
	end)
end

local function keepers(): { boolean }
	local list = {}
	local a = ctx.Store:Get("profile.Apiary")
	local hives = type(a) == "table" and a.hives or {}
	for i = 1, Config.Apiary.MaxHives do
		local h = hives[i]
		list[i] = type(h) == "table" and h.monster ~= false and h.monster ~= nil
	end
	return list
end

local function beesWanted(): boolean
	return not Quality.IsLow() and Anim.enabled ~= false
end

local function buildHive(i: number, base: CFrame, parent: Instance)
	if i == 2 then
		-- A straw skep: stacked rings narrowing to a dome, a dark entrance at the front.
		for r, ring in { { 2.8, 0.8 }, { 2.5, 0.8 }, { 2.0, 0.7 } } do
			part(
				"Skep" .. r,
				Vector3.new(ring[2], ring[1], ring[1]),
				base * CFrame.new(0, 0.4 + (r - 1) * 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)),
				"#D9B25F",
				parent,
				Enum.PartType.Cylinder,
				Enum.Material.Fabric
			)
		end
		part(
			"SkepTop",
			Vector3.new(1.6, 1.6, 1.6),
			base * CFrame.new(0, 2.3, 0),
			"#C9A04E",
			parent,
			Enum.PartType.Ball,
			Enum.Material.Fabric
		)
		part("Entrance", Vector3.new(0.7, 0.4, 0.2), base * CFrame.new(0, 0.3, 1.35), "#3A2A14", parent)
	else
		-- A box hive: two painted boxes, a lid and a landing board.
		part("BoxLow", Vector3.new(2.8, 1.1, 2.4), base * CFrame.new(0, 0.55, 0), "#F2E3B5", parent, nil, Enum.Material.Wood)
		part("BoxHigh", Vector3.new(2.8, 1.1, 2.4), base * CFrame.new(0, 1.65, 0), "#F2C230", parent, nil, Enum.Material.Wood)
		part("Lid", Vector3.new(3.2, 0.3, 2.8), base * CFrame.new(0, 2.35, 0), "#A0703D", parent, nil, Enum.Material.Wood)
		part("Landing", Vector3.new(1.6, 0.12, 0.5), base * CFrame.new(0, 0.12, 1.4), "#A0703D", parent, nil, Enum.Material.Wood)
		part("Entrance", Vector3.new(1.2, 0.25, 0.1), base * CFrame.new(0, 0.3, 1.21), "#3A2A14", parent)
	end
end

local function clearBees()
	for _, bee in bees do
		bee.part:Destroy()
	end
	table.clear(bees)
end

local function build(index: number, open: number, tended: { boolean })
	if model then
		model:Destroy()
		model = nil
		prompt = nil
	end
	table.clear(bees)
	local plotCf = plotFrame(index)
	if not plotCf or not root then
		return
	end
	local m = Instance.new("Model")
	m.Name = "Apiary"
	local o = W.offset
	-- Hives face +z: toward the plot's middle aisle.
	local site = plotCf * CFrame.new(o[1], 0, o[3])
	for i = 1, Config.Apiary.MaxHives do
		local standCf = site * CFrame.new((i - 2) * W.spacing, 0, 0)
		local stand = Instance.new("Model")
		stand.Name = "Hive" .. i
		for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			part(
				"Leg",
				Vector3.new(0.35, 1.4, 0.35),
				standCf * CFrame.new(c[1] * 1.5, 0.7, c[2] * 1.2),
				"#7A5634",
				stand,
				nil,
				Enum.Material.Wood
			)
		end
		local board = part("Board", Vector3.new(3.6, 0.3, 3), standCf * CFrame.new(0, 1.55, 0), "#94775A", stand, nil, Enum.Material.Wood)
		stand.PrimaryPart = board
		local isOpen = i <= open
		stand:SetAttribute("Open", isOpen)
		stand:SetAttribute("Tended", isOpen and tended[i] == true)
		if isOpen then
			local hiveBase = standCf * CFrame.new(0, 1.7, 0)
			buildHive(i, hiveBase, stand)
			if tended[i] and beesWanted() then
				for b = 1, BEES_PER_HIVE do
					local bee = part("Bee", Vector3.new(0.3, 0.3, 0.3), hiveBase, "#F2C230", stand, Enum.PartType.Ball, Enum.Material.Neon)
					table.insert(bees, {
						part = bee,
						center = (hiveBase * CFrame.new(0, 1.8, 0)).Position,
						radius = 1.6 + b * 0.35,
						speed = 1.6 + b * 0.4,
						phase = b * 2.1 + i,
					})
				end
			end
		end
		stand.Parent = m
	end
	-- The sign post in front of the middle stand carries the prompt.
	local signCf = site * CFrame.new(0, 0, 3.4)
	part("SignPost", Vector3.new(0.3, 2.6, 0.3), signCf * CFrame.new(0, 1.3, 0), "#7A5634", m, nil, Enum.Material.Wood)
	local sign = part("Sign", Vector3.new(2.6, 1, 0.2), signCf * CFrame.new(0, 2.5, 0), "#F2C230", m, nil, Enum.Material.Wood)
	m.PrimaryPart = sign
	local attachment = Instance.new("Attachment")
	attachment.Name = "PromptAnchor"
	attachment.Parent = sign
	local p = Instance.new("ProximityPrompt")
	p.Name = "TendPrompt"
	p.ActionText = "Tend"
	p.ObjectText = "Apiary"
	p.HoldDuration = 0
	p.MaxActivationDistance = W.promptDistance
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Parent = attachment
	p.Triggered:Connect(function()
		if ctx.Router:Has("Apiary") then
			ctx.Router:Open("Apiary")
		else
			ctx:Toast("Coming soon", "info")
		end
	end)
	prompt = p
	m.Parent = root
	model = m
end

local function sync()
	local index = ownPlot()
	if not index then
		if model then
			model:Destroy()
			model = nil
			prompt = nil
			table.clear(bees)
		end
		builtKey = ""
		return
	end
	local open = openHives()
	local tended = keepers()
	local flags = {}
	for i = 1, Config.Apiary.MaxHives do
		flags[i] = if tended[i] then "1" else "0"
	end
	local key = string.format("%d:%d:%s:%s", index, open, table.concat(flags), tostring(beesWanted()))
	if key ~= builtKey or not model then
		builtKey = key
		clearBees()
		build(index, open, tended)
	end
end

local function step(dt: number)
	if #bees == 0 then
		return
	end
	clock += dt
	for _, bee in bees do
		local a = clock * bee.speed + bee.phase
		local offset = Vector3.new(math.cos(a) * bee.radius, math.sin(a * 2.3) * 0.4, math.sin(a) * bee.radius * 0.7)
		bee.part.CFrame = CFrame.new(bee.center + offset)
	end
end

function Apiary.Init(context)
	ctx = context
end

function Apiary.Start()
	local folder = Instance.new("Folder")
	folder.Name = "Apiary"
	folder.Parent = workspace
	root = folder
	for _, path in { "global.Plots", "session.Apiary", "profile.Apiary.hives", "profile.Progression.level" } do
		table.insert(connections, ctx.Store:Observe(path, sync))
	end
	table.insert(connections, Quality.Changed:Connect(sync))
	table.insert(connections, RunService.Heartbeat:Connect(step))
	-- Reduced motion (UI/Anim.enabled) has no signal: look again now and then.
	local since = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt: number)
			since += dt
			if since >= 2 then
				since = 0
				sync()
			end
		end)
	)
	sync()
end

function Apiary.Destroy()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	if root then
		root:Destroy()
		root = nil
	end
	model = nil
	prompt = nil
	table.clear(bees)
	builtKey = ""
end

function Apiary.Model(): Model?
	return model
end

function Apiary.Prompt(): ProximityPrompt?
	return prompt
end

function Apiary.Bees(): number
	return #bees
end

return Apiary
