--[[
	Landmarks controller: ambient particle effects on the world's landmarks (Visuals/Vfx,
	Config.Vfx.Landmarks), attached once Workspace.World exists.

	  Hub/Buildings/<id>   every hub building whose HubId has a preset (raidPortal, hubPortal, gate,
	                       starAltar, showStage, hallOfFame, arena, championsArena, surfShack,
	                       eggShop, workshop), placed in its visible box
	  Sky/Gate             the Sky Gate arch (preset "skyGate"), placed in its visible box too

	World/Dress swaps a building's look for its 3D mesh pieces after the building exists; effects
	are placed in the visible parts' box, so a building is attached again a second after its last
	new piece arrives. A building added later (a rebuilt hub) is attached when it
	appears; one that leaves the Workspace is cleared by Vfx. Low graphics halves the landmark
	rates through Vfx.SetQuality (World routes the setting). It also drives the night glow: every
	Lighting.ClockTime change (the Weather controller sweeps it through dusk and dawn) becomes
	Vfx.SetNight(Vfx.NightFromClock(ClockTime)), for monsters, landmarks and bursts alike.
	No state, actions or bus topics.
]]

local Lighting = game:GetService("Lighting")

local Client = script.Parent.Parent
local Vfx = require(Client.Visuals.Vfx)

local Landmarks = {
	Name = "Landmarks",
	Dependencies = {},
}

local connections = {}
local attached = {} -- [Instance] = true

local pending = {} -- [Instance] = true while a re-attach is scheduled

local function attach(instance: Instance, id: any)
	if type(id) ~= "string" or attached[instance] then
		return
	end
	if Vfx.AttachLandmark(instance, id) then
		attached[instance] = true
		table.insert(
			connections,
			instance.AncestryChanged:Connect(function()
				if instance.Parent == nil then
					attached[instance] = nil
					Vfx.Clear(instance)
				end
			end)
		)
		-- Dress adds the 3D mesh pieces after the building exists; effects are placed from the
		-- visible parts' box, so place them again once the pieces stop arriving.
		table.insert(
			connections,
			instance.DescendantAdded:Connect(function(d)
				if not d:IsA("BasePart") or pending[instance] then
					return
				end
				pending[instance] = true
				task.delay(1, function()
					pending[instance] = nil
					if attached[instance] and instance.Parent then
						Vfx.AttachLandmark(instance, id)
					end
				end)
			end)
		)
	end
end

local function watchBuildings(buildings: Instance)
	for _, building in buildings:GetChildren() do
		attach(building, building:GetAttribute("HubId"))
	end
	table.insert(
		connections,
		buildings.ChildAdded:Connect(function(building)
			attach(building, building:GetAttribute("HubId"))
		end)
	)
end

function Landmarks.Init(_ctx) end

local function followClock()
	Vfx.SetNight(Vfx.NightFromClock(tonumber(Lighting.ClockTime) or 14))
end

function Landmarks.Start()
	followClock()
	table.insert(connections, Lighting:GetPropertyChangedSignal("ClockTime"):Connect(followClock))
	task.spawn(function()
		local world = workspace:WaitForChild("World", 60)
		if not world then
			return
		end
		local hub = world:WaitForChild("Hub", 30)
		local buildings = hub and hub:WaitForChild("Buildings", 30)
		if buildings then
			watchBuildings(buildings)
		end
		local sky = world:WaitForChild("Sky", 30)
		local gate = sky and sky:WaitForChild("Gate", 30)
		if gate and gate:WaitForChild("Body", 30) then
			attach(gate, "skyGate")
		end
	end)
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function Landmarks.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for instance in attached do
		Vfx.Clear(instance)
	end
	table.clear(attached)
end

return Landmarks
