--[[
	Showtime controller (update 1.5): Monster Contests in the world.

	  · a toast when a show opens its entries (players who have Monster Contests unlocked)
	  · the monster walking the runway stands on the Showtime Stage
	    (Workspace.World.Hub.Buildings.showStage.Body, built by the World system), with
	    its accessories, so everyone in the square can watch the show.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MonsterModel = require(script.Parent.Parent.Visuals.MonsterModel)
local StoreKit = require(script.Parent.Parent.UI.Components.StoreKit)

local Cfg = Config.Contests

local Showtime = {
	Name = "Showtime",
	Dependencies = {},
}

local ctx
local stageBody: BasePart? = nil
local walker: Model? = nil
local walkerKey = ""
local announced = -1

local function state()
	return StoreKit.tbl(ctx.Store, "global.Contests")
end

local function unlocked(): boolean
	return StoreKit.level(ctx.Store) >= (Config.Unlocks.Features[Cfg.Unlock] or math.huge)
end

local function clearWalker()
	if walker then
		walker:Destroy()
		walker = nil
	end
	walkerKey = ""
end

local function update()
	local g = state()
	if g.state == "entry" and type(g.show) == "number" and g.show ~= announced then
		announced = g.show
		local theme = Cfg.ThemeById[g.theme]
		if theme and unlocked() then
			ctx:Toast(string.format("Showtime! Theme: %s. Enter at the Showtime Stage.", theme.name), "info")
		end
	end
	local entry = g.state == "runway" and type(g.entries) == "table" and g.entries[g.current or 0] or nil
	if not entry or not stageBody or type(entry.appearance) ~= "table" or not Config.Species.ById[entry.appearance.line] then
		clearWalker()
		return
	end
	local key = tostring(g.show) .. ":" .. tostring(g.current)
	if key == walkerKey then
		return
	end
	clearWalker()
	walkerKey = key
	local ok, model = pcall(MonsterModel.Build, entry.appearance, { anchored = true })
	if not ok then
		return
	end
	local top = stageBody.CFrame * CFrame.new(0, stageBody.Size.Y / 2, 0)
	model:PivotTo(CFrame.new(top.Position) * CFrame.Angles(0, math.rad(90), 0))
	model.Name = "RunwayMonster"
	model.Parent = stageBody.Parent
	walker = model
end

function Showtime.Init(context)
	ctx = context
end

function Showtime.Start()
	ctx.Store:Observe("global.Contests", update)
	task.spawn(function()
		local world = workspace:WaitForChild("World", 60)
		local hub = world and world:WaitForChild("Hub", 30)
		local buildings = hub and hub:WaitForChild("Buildings", 30)
		local stage = buildings and buildings:WaitForChild("showStage", 30)
		local body = stage and stage:WaitForChild("Body", 30)
		if body and body:IsA("BasePart") then
			stageBody = body
			update()
		end
	end)
	update()
end

return Showtime
