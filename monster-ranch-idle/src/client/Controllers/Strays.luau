--[[
	Strays controller (update 3.13 · Wild things): the stray monster wandering on the local
	player's own plot (session.Strays.stray), only for its owner. Built on the client like the 3.12
	beehives: the monster from Visuals/MonsterModel (an Adult of the stray's line and rarity), a
	small "?" bubble over its head, and a "Befriend" prompt that opens the Strays screen.

	It paces the middle aisle near the gate (Config.Strays.World from -> to, a pause at each end);
	on Low graphics or with reduced motion it just stands at the path's middle. It is gone once the
	stray leaves (leavesAt) or its one attempt is used.

	Everything lives in Workspace.Strays (outside Workspace.World). Public (for specs):
	  Strays.Model() -> Model?            the stray now (nil when none)
	  Strays.Prompt() -> ProximityPrompt?
	  Strays.Moving() -> boolean          whether it is wandering (false when standing still)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Strays)
local Appearance = require(Shared.Logic.Appearance)
local MonsterModel = require(script.Parent.Parent.Visuals.MonsterModel)
local Quality = require(script.Parent.Parent.Visuals.Quality)
local Anim = require(script.Parent.Parent.UI.Anim)

local Strays = {
	Name = "Strays",
	Dependencies = {},
}

local W = Config.Strays.World
local PLOT_TOP = 0.3

local ctx
local player = Players.LocalPlayer
local root: Folder? = nil
local model: Model? = nil
local prompt: ProximityPrompt? = nil
local connections = {}
local builtKey = ""
local walk = nil -- { a: CFrame, b: CFrame, t, dir, pause, length, lift } while wandering

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

local function stray()
	local s = ctx.Store:Get("session.Strays.stray")
	if type(s) ~= "table" or s.tried == true or type(s.line) ~= "string" then
		return nil
	end
	if (tonumber(s.leavesAt) or 0) <= ctx:Now() then
		return nil
	end
	return s
end

local function still(): boolean
	return Quality.IsLow() or Anim.enabled == false
end

local function clear()
	if model then
		model:Destroy()
	end
	model, prompt, walk = nil, nil, nil
end

local function bubble(m: Model)
	local head = m.PrimaryPart and m.PrimaryPart:FindFirstChild("Head")
	local gui = Instance.new("BillboardGui")
	gui.Name = "StrayBubble"
	gui.Size = UDim2.fromOffset(40, 40)
	gui.StudsOffset = Vector3.new(0, 1.2, 0)
	gui.AlwaysOnTop = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.MaxDistance = 80
	gui.Adornee = if head and head:IsA("Attachment") then nil else m.PrimaryPart
	local label = Instance.new("TextLabel")
	label.Name = "Mark"
	label.Text = "?"
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromHex("#3A2A14")
	label.BackgroundColor3 = Color3.fromHex("#FFF3B0")
	label.Size = UDim2.fromScale(1, 1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = label
	label.Parent = gui
	gui.Parent = if head and head:IsA("Attachment") then head else m.PrimaryPart
end

local function build(index: number, s)
	clear()
	local plotCf = plotFrame(index)
	if not plotCf or not root then
		return
	end
	local look = Appearance.Preview(s.line, 3, nil, tonumber(s.rarity) or 1, 0)
	local ok, m = pcall(MonsterModel.Build, look, { anchored = true })
	if not ok or not m then
		return
	end
	m.Name = "Stray"
	m:SetAttribute("StrayLine", s.line)
	m:SetAttribute("StraySlot", s.slot)
	local height = tonumber(m:GetAttribute("Height")) or 3
	local lift = height / 2
	-- The path runs along the aisle; the monster faces where it walks.
	local a = plotCf * CFrame.new(W.from[1], PLOT_TOP + lift, W.from[2])
	local b = plotCf * CFrame.new(W.to[1], PLOT_TOP + lift, W.to[2])
	local mid = a:Lerp(b, 0.5)
	m:PivotTo(CFrame.lookAt(mid.Position, mid.Position + (a.Position - b.Position)))
	bubble(m)

	local p = Instance.new("ProximityPrompt")
	p.Name = "BefriendPrompt"
	p.ActionText = "Befriend"
	p.ObjectText = Logic.Name(s.line)
	p.HoldDuration = 0
	p.MaxActivationDistance = W.promptDistance
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Parent = m.PrimaryPart
	p.Triggered:Connect(function()
		if ctx.Router:Has("Strays") then
			ctx.Router:Open("Strays")
		end
	end)
	prompt = p
	m.Parent = root
	model = m
	if not still() then
		walk = { a = a, b = b, t = 0.5, dir = 1, pause = 0, length = math.max(1, (b.Position - a.Position).Magnitude) }
	end
end

local function sync()
	local index = ownPlot()
	local s = stray()
	if not index or not s then
		if model then
			clear()
		end
		builtKey = ""
		return
	end
	local key = string.format("%d:%s:%s:%s:%s", index, tostring(s.slot), s.line, tostring(s.rarity), tostring(still()))
	if key ~= builtKey or not model then
		builtKey = key
		build(index, s)
	end
end

local function step(dt: number)
	if not walk or not model then
		return
	end
	if walk.pause > 0 then
		walk.pause -= dt
		return
	end
	walk.t += walk.dir * dt * W.speed / walk.length
	if walk.t >= 1 or walk.t <= 0 then
		walk.t = math.clamp(walk.t, 0, 1)
		walk.dir = -walk.dir
		walk.pause = W.pause
	end
	local pos = walk.a.Position:Lerp(walk.b.Position, walk.t)
	local ahead = if walk.dir > 0 then walk.b.Position - walk.a.Position else walk.a.Position - walk.b.Position
	model:PivotTo(CFrame.lookAt(pos, pos + ahead))
end

function Strays.Init(context)
	ctx = context
end

function Strays.Start()
	local folder = Instance.new("Folder")
	folder.Name = "Strays"
	folder.Parent = workspace
	root = folder
	for _, path in { "global.Plots", "session.Strays" } do
		table.insert(connections, ctx.Store:Observe(path, sync))
	end
	table.insert(connections, Quality.Changed:Connect(sync))
	table.insert(connections, RunService.Heartbeat:Connect(step))
	-- Reduced motion has no signal and the stray leaves on the clock: look again now and then.
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

function Strays.Destroy()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	clear()
	if root then
		root:Destroy()
		root = nil
	end
	builtKey = ""
end

function Strays.Model(): Model?
	return model
end

function Strays.Prompt(): ProximityPrompt?
	return prompt
end

function Strays.Moving(): boolean
	return walk ~= nil
end

return Strays
