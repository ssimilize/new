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
local Streaming = require(script.Parent.Parent.Visuals.Streaming)

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
local connections = {}

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
	if
		not entry
		or not stageBody
		or not stageBody.Parent
		or type(entry.appearance) ~= "table"
		or not Config.Species.ById[entry.appearance.line]
	then
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

-- The stage (Workspace.World.Hub.Buildings.showStage.Body) may stream in after Start, or stream
-- out and back in later (a new Body instance each time): chain Streaming.OnChild so it is found
-- whenever it exists, and drop the stale reference (AncestryChanged) so it is not reused once gone.
local function onBody(body: Instance)
	if not body:IsA("BasePart") then
		return
	end
	stageBody = body
	table.insert(
		connections,
		body.AncestryChanged:Connect(function()
			if body.Parent == nil and stageBody == body then
				stageBody = nil
				clearWalker()
			end
		end)
	)
	update()
end

local function onStage(stage: Instance)
	table.insert(connections, Streaming.OnChild(stage, "Body", onBody))
end

function Showtime.Start()
	ctx.Store:Observe("global.Contests", update)
	task.spawn(function()
		local world = workspace:WaitForChild("World", 60)
		if not world then
			return
		end
		table.insert(
			connections,
			Streaming.OnChild(world, "Hub", function(hub)
				table.insert(
					connections,
					Streaming.OnChild(hub, "Buildings", function(buildings)
						table.insert(connections, Streaming.OnChild(buildings, "showStage", onStage))
					end)
				)
			end)
		)
	end)
	update()
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function Showtime.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	clearWalker()
	stageBody = nil
end

return Showtime
