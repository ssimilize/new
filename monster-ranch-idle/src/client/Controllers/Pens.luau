--[[
	Pens controller (glow-up R · pens that grow): dresses every plot's pens and Feed Garden from
	replicated state, so everyone on the server sees the same upgrades.

	  global.Plots[i].pens[p]   { theme, capacity, jarTier, monsters = { { appearance } } }
	                            -> fence tier (jar tier), capacity props (hay nest, trough, pond, hut,
	                               shade tree), theme floor / rail materials and signature props, and
	                               the dominant element's habitat (Logic/Pens.Plan, Config.Pens)
	  global.Plots[i].garden    { tier, plots = { { flavor, readyAt } } } -> beds and crops
	  profile.Ranch.garden      the local player's own garden (exact while rain speeds it up)
	  profile.Settings.lowGraphics   own plot "lite" (small pieces dropped), other plots "far"

	Where things go: Workspace.World.Plots.Plot<i>.Pens.Pen<p>.Dress (a Model: props, habitat,
	fence caps; attrs FenceTier, Theme, Habitat) and Plot<i>.Garden (a Model). The pen's own
	Floor / Rail* / Post* parts are restyled in place (Visuals/PenDress.Paint). Spots for monster
	behaviour: parts with PenSpot ("food" | "water" | "shelter" | "bed") and Habitat = elementId.

	Rebuilds: each pen has three groups (fence caps, props, habitat) keyed by Logic/Pens; a group
	is rebuilt only when its key changes (upgrade, theme, dominant element, detail level). The
	garden is keyed by its crop stages. Other plots farther than Config.Pens.FarDistance from the
	camera draw "far". Plots updates are handled one deferred step later, after World has painted
	the theme colours; every Config.Pens.CheckSeconds a timer re-checks crop stages and distance.
	Nothing runs per frame.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Pens)

local Client = script.Parent.Parent
local PenDress = require(Client.Visuals.PenDress)

local WorldConfig = Config.World
local PenConfig = Config.Pens

local Pens = {
	Name = "Pens",
	Dependencies = { "World" },
}

local PLOT_COUNT = #WorldConfig.Plots
local MAX_PENS = math.min(Config.Economy.Pens.max, #WorldConfig.PenOffsets)
local GROUPS = { "fence", "props", "habitat" }

local ctx
local world: Instance? = nil
local connections = {}
local running = false
local lowGraphics = false
local latestPlots = nil
local ownGarden = nil
local scheduled = false
local views = {} -- [plotIndex] = { far, pens = { [p] = penView }, garden = { key, model, parts } }
local stats = { builds = 0, gardenBuilds = 0 }

local function now(): number
	return if ctx then ctx:Now() else os.time()
end

local function plotModel(index: number): Instance?
	local plots = world and world:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot" .. index)
end

local function penModel(index: number, pen: number): Instance?
	local plot = plotModel(index)
	local pens = plot and plot:FindFirstChild("Pens")
	return pens and pens:FindFirstChild("Pen" .. pen)
end

local function floorTop(model: Instance): CFrame?
	local floor = model:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		return floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)
	end
	return nil
end

local function getView(index: number)
	local view = views[index]
	if not view then
		view = { far = false, pens = {}, garden = { key = nil, model = nil, parts = {} } }
		views[index] = view
	end
	return view
end

local function penView(view, pen: number)
	local pv = view.pens[pen]
	if not pv then
		pv = { keys = {}, groups = { fence = {}, props = {}, habitat = {} }, dress = nil, dressed = false }
		view.pens[pen] = pv
	end
	return pv
end

local function destroyParts(list)
	for _, part in list do
		part:Destroy()
	end
	table.clear(list)
end

local function clearPen(pv, model: Instance?)
	for _, group in GROUPS do
		destroyParts(pv.groups[group])
		pv.keys[group] = nil
	end
	if pv.dress then
		pv.dress:Destroy()
		pv.dress = nil
	end
	if pv.dressed and model then
		PenDress.Restore(model)
	end
	pv.dressed = false
end

local function ownIndex(list): number?
	local me = Players.LocalPlayer
	if not me or type(list) ~= "table" then
		return nil
	end
	for i = 1, PLOT_COUNT do
		local data = list[i]
		if type(data) == "table" and data.userId == me.UserId and me.UserId ~= 0 then
			return i
		end
	end
	return nil
end

local function detailFor(view, own: boolean): string
	if own then
		return if lowGraphics then "lite" else "full"
	end
	return if lowGraphics or view.far then "far" else "full"
end

local function syncPen(view, index: number, p: number, pen, detail: string)
	local model = penModel(index, p)
	local pv = penView(view, p)
	if not model then
		return
	end
	if type(pen) ~= "table" then
		if pv.dressed then
			clearPen(pv, model)
		end
		return
	end
	local area = floorTop(model)
	if not area then
		return
	end
	local plan = Logic.Plan(Config, pen, detail)
	-- Every pass: World repaints theme colours when a theme or decor changes.
	PenDress.Paint(model, plan)
	pv.dressed = true
	local dress = pv.dress
	if not dress or dress.Parent ~= model then
		dress = Instance.new("Model")
		dress.Name = "Dress"
		dress.Parent = model
		pv.dress = dress
	end
	dress:SetAttribute("FenceTier", plan.fence.id)
	dress:SetAttribute("Theme", plan.theme)
	dress:SetAttribute("Habitat", plan.element or "")
	for _, group in GROUPS do
		if pv.keys[group] ~= plan.keys[group] then
			destroyParts(pv.groups[group])
			pv.keys[group] = plan.keys[group]
			stats.builds += 1
			if group == "fence" then
				pv.groups.fence = PenDress.Caps(dress, model, plan)
			else
				pv.groups[group] = PenDress.Entries(dress, area, plan[group], plan)
			end
		end
	end
end

local function syncGarden(view, index: number, garden, detail: string)
	local g = view.garden
	local plot = plotModel(index)
	local floor = plot and plot:FindFirstChild("Floor")
	local gardenDetail = if detail == "far" then "far" else "full"
	local key = if floor and floor:IsA("BasePart") then Logic.GardenKey(Config, garden, now(), gardenDetail) else "none"
	if g.key == key then
		return
	end
	g.key = key
	destroyParts(g.parts)
	if key == "none" then
		if g.model then
			g.model:Destroy()
			g.model = nil
		end
		return
	end
	local floorPart = floor :: BasePart
	if not g.model or g.model.Parent ~= plot then
		local model = Instance.new("Model")
		model.Name = "Garden"
		model.Parent = plot
		g.model = model
	end
	local o = WorldConfig.GardenOffset
	local base = floorPart.CFrame * CFrame.new(o[1], floorPart.Size.Y / 2, o[3])
	stats.gardenBuilds += 1
	g.parts = PenDress.Garden(g.model, base, garden, now(), gardenDetail)
end

local function syncAll()
	if not running or not world then
		return
	end
	local list = latestPlots
	local own = ownIndex(list)
	for i = 1, PLOT_COUNT do
		local data = if type(list) == "table" then list[i] else nil
		if type(data) ~= "table" or (tonumber(data.userId) or 0) == 0 then
			data = nil
		end
		local view = getView(i)
		local detail = detailFor(view, i == own)
		local pens = if data and type(data.pens) == "table" then data.pens else {}
		for p = 1, MAX_PENS do
			syncPen(view, i, p, pens[p], detail)
		end
		local garden = if data then data.garden else nil
		if i == own and type(ownGarden) == "table" then
			garden = ownGarden
		end
		syncGarden(view, i, garden, detail)
	end
end

-- Coalesces updates and runs after World's own observer has painted the pens.
local function schedule()
	if scheduled then
		return
	end
	scheduled = true
	task.defer(function()
		scheduled = false
		syncAll()
	end)
end

local function updateDistance()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local at = camera.CFrame.Position
	for i, plot in WorldConfig.Plots do
		local view = getView(i)
		local c = plot.center
		local d = math.sqrt((at.X - c[1]) ^ 2 + (at.Z - c[3]) ^ 2)
		if view.far then
			view.far = d > PenConfig.FarDistance - PenConfig.FarHysteresis
		else
			view.far = d > PenConfig.FarDistance + PenConfig.FarHysteresis
		end
	end
end

local function check()
	if not running then
		return
	end
	updateDistance()
	syncAll()
	task.delay(PenConfig.CheckSeconds, check)
end

-- Tests: groups (re)built so far, garden builds, and the parts the controller holds now.
function Pens.Stats(): { builds: number, gardenBuilds: number, parts: number }
	local parts = 0
	for _, view in views do
		for _, pv in view.pens do
			for _, group in GROUPS do
				parts += #pv.groups[group]
			end
		end
		parts += #view.garden.parts
	end
	return { builds = stats.builds, gardenBuilds = stats.gardenBuilds, parts = parts }
end

function Pens.Init(context)
	ctx = context
end

function Pens.Start()
	running = true
	table.insert(
		connections,
		ctx.Store:Observe("profile.Settings", function(settings)
			local low = type(settings) == "table" and settings.lowGraphics == true
			if low ~= lowGraphics then
				lowGraphics = low
				schedule()
			end
		end)
	)
	table.insert(
		connections,
		ctx.Store:Observe("profile.Ranch.garden", function(garden)
			ownGarden = garden
			schedule()
		end)
	)
	table.insert(
		connections,
		ctx.Store:Observe("global.Plots", function(list)
			latestPlots = list
			schedule()
		end)
	)
	task.spawn(function()
		local w = workspace:WaitForChild("World", 60)
		if w and running then
			world = w
			updateDistance()
			syncAll()
			task.delay(PenConfig.CheckSeconds, check)
		end
	end)
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function Pens.Destroy()
	running = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for i, view in views do
		for p, pv in view.pens do
			clearPen(pv, penModel(i, p))
		end
		destroyParts(view.garden.parts)
		if view.garden.model then
			view.garden.model:Destroy()
		end
	end
	table.clear(views)
	world = nil
end

return Pens
