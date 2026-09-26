--[[
	Interaction controller (C1): ProximityPrompts in the 3D world that open screens.

	  hub buildings    Workspace.World.Hub.Buildings/<id> (attrs HubId, Screen) -> Router:Open(Screen)
	  own pens         Workspace.World.Plots.Plot<i>.Pens.Pen<n> -> Router:Open("Ranch", { pen = n })
	                   plus a "Build Pen" prompt on the next locked pen -> Router:Open("Ranch")
	  own incubator    IncubatorPad -> Router:Open("Incubators")
	  own barn         Barn -> Router:Open("Monsters")

	Ranch prompts exist only on the local player's own plot (found in global.Plots by UserId)
	and are rebuilt when the plot or the number of owned pens changes. Prompts are created on
	the client, so Triggered fires locally. Screens that are not plugged in yet show a toast.
]]

local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Interaction = {
	Name = "Interaction",
	Dependencies = {},
}

local PROMPT_DISTANCE = 12
local PEN_PROMPT_DISTANCE = 14

local ctx
local player = Players.LocalPlayer
local world: Instance? = nil
local hubPrompts = {} -- Instances created for hub buildings
local ranchPrompts = {} -- Instances created for the own plot
local ranchKey = ""
local likePrompts = {} -- "Like ranch" prompts on other players' plot gates
local likeKey = ""
local connections = {}

local function open(screen: string, params: any?)
	if ctx.Router:Has(screen) then
		ctx.Router:Open(screen, params)
	else
		ctx:Toast("Coming soon", "info")
	end
end

-- Creates an Attachment at `worldPosition` under `part` with a prompt on it. Destroying the
-- attachment (see clear) also destroys the prompt and disconnects its Triggered handler.
local function addPrompt(
	list,
	part: BasePart,
	worldPosition: Vector3,
	action: string,
	object: string,
	distance: number,
	onTrigger: () -> ()
)
	local attachment = Instance.new("Attachment")
	attachment.Name = "PromptAnchor"
	attachment.Position = part.CFrame:PointToObjectSpace(worldPosition)
	attachment.Parent = part

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = distance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX -- the pad hint; Racing and Surf never use X
	prompt.Parent = attachment
	prompt.Triggered:Connect(function()
		onTrigger()
	end)
	table.insert(list, attachment)
	return prompt
end

local function clear(list)
	for _, inst in list do
		inst:Destroy()
	end
	table.clear(list)
end

-- Hub ---------------------------------------------------------------------------------------

local function buildHubPrompts()
	clear(hubPrompts)
	local hub = world and world:FindFirstChild("Hub")
	local buildings = hub and hub:FindFirstChild("Buildings")
	if not buildings then
		return
	end
	for _, model in buildings:GetChildren() do
		local screen = model:GetAttribute("Screen")
		local hubId = model:GetAttribute("HubId")
		if type(screen) == "string" and hubId ~= nil then
			local door = model:FindFirstChild("Door")
			local body = model:FindFirstChild("Body")
			local anchor = if door and door:IsA("BasePart") then door elseif body and body:IsA("BasePart") then body else nil
			if anchor then
				-- Just outside the front face, at chest height.
				local front = anchor.CFrame * CFrame.new(0, -anchor.Size.Y / 2 + 3, -anchor.Size.Z / 2 - 1.5)
				local name = model:GetAttribute("DisplayName")
				addPrompt(
					hubPrompts,
					anchor,
					front.Position,
					"Open",
					if type(name) == "string" then name else model.Name,
					PROMPT_DISTANCE,
					function()
						open(screen)
					end
				)
			end
		end
	end
end

-- Own plot ------------------------------------------------------------------------------------

local function ownPlot(plots): (number?, number)
	if type(plots) ~= "table" then
		return nil, 0
	end
	for i, plot in plots do
		if type(plot) == "table" and plot.userId == player.UserId then
			return i, if type(plot.pens) == "table" then #plot.pens else 0
		end
	end
	return nil, 0
end

local function buildRanchPrompts(index: number?, penCount: number)
	clear(ranchPrompts)
	if not index or not world then
		return
	end
	local plots = world:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot" .. index)
	if not plot then
		return
	end
	local pens = plot:FindFirstChild("Pens")
	for n = 1, math.min(Config.Economy.Pens.max, penCount + 1) do
		local pen = pens and pens:FindFirstChild("Pen" .. n)
		local floor = pen and pen:FindFirstChild("Floor")
		if floor and floor:IsA("BasePart") then
			-- On the fence side that faces the plot's middle aisle (plot-local z = 0).
			local localCenter = plot:GetPivot():PointToObjectSpace(floor.Position)
			local side = if localCenter.Z < 0 then 1 else -1
			local edge = floor.CFrame * CFrame.new(0, 2.5, side * (floor.Size.Z / 2 + 0.8))
			if n <= penCount then
				addPrompt(ranchPrompts, floor, edge.Position, "Manage", string.format("Pen %d", n), PEN_PROMPT_DISTANCE, function()
					open("Ranch", { pen = n })
				end)
			else
				addPrompt(ranchPrompts, floor, edge.Position, "Build Pen", "Locked Pen", PEN_PROMPT_DISTANCE, function()
					open("Ranch")
				end)
			end
		end
	end
	local pad = plot:FindFirstChild("IncubatorPad")
	if pad and pad:IsA("BasePart") then
		addPrompt(ranchPrompts, pad, pad.Position + Vector3.new(0, 3, 0), "Open", "Incubators", PROMPT_DISTANCE, function()
			open("Incubators")
		end)
	end
	local barn = plot:FindFirstChild("Barn")
	local door = barn and barn:FindFirstChild("Door")
	if door and door:IsA("BasePart") then
		local front = door.CFrame * CFrame.new(0, 0, -1.5)
		addPrompt(ranchPrompts, door, front.Position, "Open", "Barn", PROMPT_DISTANCE, function()
			open("Monsters")
		end)
	end
end

-- Other players' plots: a "Like" prompt on each occupied gate (Social.Like).
local function buildLikePrompts(plots)
	clear(likePrompts)
	local folder = world and world:FindFirstChild("Plots")
	if not folder or type(plots) ~= "table" then
		return
	end
	for i, plot in plots do
		if type(plot) == "table" and (plot.userId or 0) ~= 0 and plot.userId ~= player.UserId then
			local model = folder:FindFirstChild("Plot" .. i)
			local gate = model and model:FindFirstChild("Gate")
			local post = gate and gate:FindFirstChild("PostL")
			if post and post:IsA("BasePart") then
				local owner = plot.userId
				local label = string.format("%s's ranch · %d likes", tostring(plot.name or "Player"), tonumber(plot.likes) or 0)
				addPrompt(likePrompts, post, post.Position + Vector3.new(0, 2, 0), "Like", label, PROMPT_DISTANCE, function()
					local ok, res = ctx.Net:Request("Social.Like", { owner = owner })
					if ok then
						ctx:Toast("You liked this ranch!", "success")
					else
						ctx:Toast(tostring(res), "error")
					end
				end)
			end
		end
	end
end

local function onPlots(plots)
	local parts = {}
	for i, plot in (if type(plots) == "table" then plots else {}) do
		if type(plot) == "table" then
			table.insert(parts, string.format("%d:%s:%s", i, tostring(plot.userId), tostring(plot.likes)))
		end
	end
	local nextLikeKey = table.concat(parts, "|")
	if nextLikeKey ~= likeKey then
		likeKey = nextLikeKey
		buildLikePrompts(plots)
	end

	local index, penCount = ownPlot(plots)
	local key = tostring(index) .. ":" .. penCount
	if key == ranchKey then
		return
	end
	ranchKey = key
	buildRanchPrompts(index, penCount)
end

function Interaction.Init(context)
	ctx = context
end

function Interaction.Start()
	world = workspace:WaitForChild("World", 60)
	if not world then
		warn("[Interaction] Workspace.World not found; no world prompts")
		return
	end
	buildHubPrompts()
	table.insert(connections, ctx.Store:Observe("global.Plots", onPlots))
end

-- Tears everything down (not called by the kernel today; kept so the controller can be unplugged).
function Interaction.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	clear(hubPrompts)
	clear(ranchPrompts)
	clear(likePrompts)
	ranchKey = ""
	likeKey = ""
end

return Interaction
