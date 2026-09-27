--[[
	Spa controller (update 3.13 · Wild things): the Hot Springs on the local player's own plot,
	at Config.Spa.World (plot-local centre (-66, 0, 23), the west strip beside the incubator pad;
	keep-out {-66, 23, 7, 8} in Config.Decor). Built from Parts on the client, like the Apiary:
	no assets, no server geometry.

	  a wooden deck with three round pools (two in front, one at the back under a small roof on
	  four posts). An open pool holds warm water; a locked pool wears a wooden cover. A pool with
	  a monster soaking shows a ring of bubbles on its water (the soaking icon; the monster itself
	  stays out of the pool). Open pools breathe steam (small rising Parts), none on Low graphics
	  or with reduced motion.
	  a "Soak · Hot Springs" prompt on the sign at the front edge -> Router:Open("Spa") (the
	  screen shows its own lock before Ranch Level 29).

	Everything lives in Workspace.Spa (outside Workspace.World, so the Interaction controller's
	geometry rescans never see it). Rebuilt when the own plot, the open pool count or the soaking
	pools change. Public (for specs):
	  Spa.Model() -> Model?             the spa now (nil without an own plot)
	  Spa.Prompt() -> ProximityPrompt?
	  Spa.Steam() -> number             steam puffs rising now
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Spa)
local Quality = require(script.Parent.Parent.Visuals.Quality)
local Anim = require(script.Parent.Parent.UI.Anim)

local Spa = {
	Name = "Spa",
	Dependencies = {},
}

local W = Config.Spa.World
local POOL_SPOTS = { { -3.2, -2.4 }, { 3.2, -2.4 }, { 0, 3.6 } } -- pool centres on the deck (x, z)
local POOL_D = 5.2
local STEAM_PER_POOL = 3
local STEAM_RISE = 3.5

local ctx
local player = Players.LocalPlayer
local root: Folder? = nil
local model: Model? = nil
local prompt: ProximityPrompt? = nil
local steam = {} -- { { part, base: Vector3, speed, phase } }
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

local function openPools(): number
	local s = ctx.Store:Get("session.Spa")
	if type(s) == "table" and type(s.pools) == "number" then
		return s.pools
	end
	local level = tonumber(ctx.Store:Get("profile.Progression.level")) or 1
	return Logic.PoolCount(function(key)
		local need = Config.Unlocks.Features[key]
		return need ~= nil and level >= need
	end)
end

local function soaking(): { boolean }
	local list = {}
	local s = ctx.Store:Get("profile.Spa")
	local pools = type(s) == "table" and s.pools or {}
	for i = 1, Config.Spa.MaxPools do
		local pool = pools[i]
		list[i] = type(pool) == "table" and pool.monster ~= false and pool.monster ~= nil
	end
	return list
end

local function steamWanted(): boolean
	return not Quality.IsLow() and Anim.enabled ~= false
end

local function clearSteam()
	for _, puff in steam do
		puff.part:Destroy()
	end
	table.clear(steam)
end

local function flat(cf: CFrame): CFrame
	-- A cylinder's axis is its x: stand it up so it lies flat like a disc.
	return cf * CFrame.Angles(0, 0, math.rad(90))
end

local function build(index: number, open: number, busy: { boolean })
	if model then
		model:Destroy()
		model = nil
		prompt = nil
	end
	table.clear(steam)
	local plotCf = plotFrame(index)
	if not plotCf or not root then
		return
	end
	local m = Instance.new("Model")
	m.Name = "Spa"
	local o = W.offset
	local site = plotCf * CFrame.new(o[1], 0, o[3])
	local w, d = W.size[1] - 1, W.size[2] - 1
	part("Deck", Vector3.new(w, 0.6, d), site * CFrame.new(0, 0.3, 0), "#A0703D", m, nil, Enum.Material.WoodPlanks)
	for i, spot in POOL_SPOTS do
		local pool = Instance.new("Model")
		pool.Name = "Pool" .. i
		local base = site * CFrame.new(spot[1], 0, spot[2])
		local rim = part(
			"Rim",
			Vector3.new(0.5, POOL_D + 0.8, POOL_D + 0.8),
			flat(base * CFrame.new(0, 0.75, 0)),
			"#9C9486",
			pool,
			Enum.PartType.Cylinder,
			Enum.Material.Slate
		)
		pool.PrimaryPart = rim
		local isOpen = i <= open
		local isBusy = isOpen and busy[i] == true
		pool:SetAttribute("Open", isOpen)
		pool:SetAttribute("Soaking", isBusy)
		if isOpen then
			local water = part(
				"Water",
				Vector3.new(0.3, POOL_D, POOL_D),
				flat(base * CFrame.new(0, 0.95, 0)),
				"#6FC7D6",
				pool,
				Enum.PartType.Cylinder,
				Enum.Material.Glass
			)
			water.Transparency = 0.2
			if isBusy then
				-- The soaking icon: a ring of bubbles on the water.
				for b = 1, 5 do
					local a = b / 5 * math.pi * 2
					local bubble = part(
						"Bubble",
						Vector3.new(0.6, 0.6, 0.6),
						base * CFrame.new(math.cos(a) * 1.2, 1.3, math.sin(a) * 1.2),
						"#F4FBFF",
						pool,
						Enum.PartType.Ball,
						Enum.Material.Glass
					)
					bubble.Transparency = 0.3
				end
			end
			if steamWanted() then
				for s = 1, STEAM_PER_POOL do
					local puff =
						part("Steam", Vector3.new(0.9, 0.9, 0.9), base * CFrame.new(0, 1.2, 0), "#FFFFFF", pool, Enum.PartType.Ball)
					puff.Transparency = 0.6
					table.insert(steam, {
						part = puff,
						base = (base * CFrame.new((s - 2) * 1.1, 1.2, (s % 2) * 0.8 - 0.4)).Position,
						speed = 0.35 + s * 0.08,
						phase = s / STEAM_PER_POOL + i * 0.21,
					})
				end
			end
		else
			part(
				"Cover",
				Vector3.new(0.4, POOL_D + 0.4, POOL_D + 0.4),
				flat(base * CFrame.new(0, 1.05, 0)),
				"#7A5634",
				pool,
				Enum.PartType.Cylinder,
				Enum.Material.Wood
			)
		end
		pool.Parent = m
	end
	-- The roof over the back pool: four posts and a plank top.
	local back = POOL_SPOTS[3]
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		part(
			"Post",
			Vector3.new(0.5, 6.5, 0.5),
			site * CFrame.new(back[1] + c[1] * 3.6, 3.55, back[2] + c[2] * 3.2),
			"#7A5634",
			m,
			nil,
			Enum.Material.Wood
		)
	end
	part("Roof", Vector3.new(8.4, 0.5, 7.6), site * CFrame.new(back[1], 7, back[2]), "#8E4B32", m, nil, Enum.Material.Wood)
	-- The sign at the front edge (toward the middle aisle) carries the prompt.
	local signCf = site * CFrame.new(0, 0, -d / 2 + 0.4)
	part("SignPost", Vector3.new(0.3, 2.6, 0.3), signCf * CFrame.new(0, 1.3, 0), "#7A5634", m, nil, Enum.Material.Wood)
	local sign = part("Sign", Vector3.new(2.6, 1, 0.2), signCf * CFrame.new(0, 2.5, 0), "#6FC7D6", m, nil, Enum.Material.Wood)
	m.PrimaryPart = sign
	local attachment = Instance.new("Attachment")
	attachment.Name = "PromptAnchor"
	attachment.Parent = sign
	local p = Instance.new("ProximityPrompt")
	p.Name = "SoakPrompt"
	p.ActionText = "Soak"
	p.ObjectText = "Hot Springs"
	p.HoldDuration = 0
	p.MaxActivationDistance = W.promptDistance
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Parent = attachment
	p.Triggered:Connect(function()
		if ctx.Router:Has("Spa") then
			ctx.Router:Open("Spa")
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
			table.clear(steam)
		end
		builtKey = ""
		return
	end
	local open = openPools()
	local busy = soaking()
	local flags = {}
	for i = 1, Config.Spa.MaxPools do
		flags[i] = if busy[i] then "1" else "0"
	end
	local key = string.format("%d:%d:%s:%s", index, open, table.concat(flags), tostring(steamWanted()))
	if key ~= builtKey or not model then
		builtKey = key
		clearSteam()
		build(index, open, busy)
	end
end

local function step(dt: number)
	if #steam == 0 then
		return
	end
	clock += dt
	for _, puff in steam do
		local f = (clock * puff.speed + puff.phase) % 1
		puff.part.CFrame = CFrame.new(puff.base + Vector3.new(math.sin(f * 6) * 0.3, f * STEAM_RISE, 0))
		puff.part.Transparency = 0.55 + f * 0.45
	end
end

function Spa.Init(context)
	ctx = context
end

function Spa.Start()
	local folder = Instance.new("Folder")
	folder.Name = "Spa"
	folder.Parent = workspace
	root = folder
	for _, path in { "global.Plots", "session.Spa", "profile.Spa.pools", "profile.Progression.level" } do
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

function Spa.Destroy()
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
	table.clear(steam)
	builtKey = ""
end

function Spa.Model(): Model?
	return model
end

function Spa.Prompt(): ProximityPrompt?
	return prompt
end

function Spa.Steam(): number
	return #steam
end

return Spa
