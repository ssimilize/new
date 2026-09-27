--[[
	SkyIslands controller (update 2.0): getting to the Sky Islands and collecting wind crystals.

	  · Workspace.World.Sky.LaunchPad (hub) → "Fly up" prompt: teleports the character to the
	    return pad on the landing island (Ranch Level Config.SkyIslands.Unlock).
	  · ReturnPad → "Fly home" back to the hub.
	  · Gate portal → opens the Expeditions screen on the Sky Islands region.
	  · Wind crystals (client-only, Workspace.SkyCrystals): one glowing crystal per
	    Config.SkyIslands.Crystals spot that has recharged for this player
	    (profile.SkyIslands.taken), with a "Collect" prompt → SkyIslands.Collect.

	SkyIslands.IsOnIslands() -> boolean   the local character is up on the islands (Soundscape).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)

local StoreKit = require(script.Parent.Parent.UI.Components.StoreKit)
local Streaming = require(script.Parent.Parent.Visuals.Streaming)

local Cfg = Config.SkyIslands
local Sky = Config.World.Sky

local SkyIslands = {
	Name = "SkyIslands",
	Dependencies = {},
}

local ctx
local folder: Instance? = nil
local crystals = {} -- [index] = Part
local shownKey = ""
local connections = {}

local function unlocked(): boolean
	return StoreKit.level(ctx.Store) >= (Config.Unlocks.Features[Cfg.Unlock] or math.huge)
end

local function prompt(parent: Instance, action: string, object: string, distance: number, onTrigger: () -> ())
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = distance
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX -- the pad hint shown by the default prompt
	p.Parent = parent
	p.Triggered:Connect(onTrigger)
	return p
end

-- R2-STREAMING: Sky Islands is far from (and high above) the hub, so ask the server to pre-stream
-- the destination before the local pivot; the reply is awaited so the player never lands in the
-- void. World.StreamAround never fails the request itself (best-effort), so the teleport always
-- happens even if streaming is off or the request times out.
local function teleport(at: { number }, lift: number)
	local character = Players.LocalPlayer.Character
	if not (character and character.PrimaryPart) then
		return
	end
	ctx.Net:Request("World.StreamAround", { x = at[1], y = at[2] + lift, z = at[3] + 6 })
	character = Players.LocalPlayer.Character
	if character and character.PrimaryPart then
		ctx:Sound("Teleport")
		character:PivotTo(CFrame.new(at[1], at[2] + lift, at[3] + 6))
	end
end

-- Crystals ---------------------------------------------------------------------------------

local function ready(index: number, now: number): boolean
	local taken = StoreKit.tbl(ctx.Store, "profile.SkyIslands.taken")
	local at = tonumber(taken[tostring(index)]) or 0
	return now - at >= Cfg.RespawnSeconds
end

local function collect(index: number)
	-- The reward toast comes from Rewards.Granted; the crystal hides until it recharges.
	local ok = StoreKit.request(ctx, "SkyIslands.Collect", { crystal = index })
	if ok and crystals[index] then
		crystals[index]:Destroy()
		crystals[index] = nil
	end
end

local function buildCrystal(index: number)
	local pos = Cfg.Crystals[index]
	local crystal = Instance.new("Part")
	crystal.Name = "Crystal" .. index
	crystal.Anchored = true
	crystal.CanCollide = false
	crystal.CanQuery = false
	crystal.CanTouch = false
	crystal.Size = Vector3.new(1.6, 1.6, 1.6)
	crystal.Color = Color3.fromHex(if index % 2 == 0 then "#F2C94C" else "#5CE1E6")
	crystal.Material = Enum.Material.Neon
	crystal.CFrame = CFrame.new(pos[1], pos[2] + 1, pos[3]) * CFrame.Angles(math.rad(45), math.rad(index * 20), math.rad(45))
	local glow = Instance.new("PointLight")
	glow.Color = crystal.Color
	glow.Range = 10
	glow.Brightness = 1.5
	glow.Parent = crystal
	prompt(crystal, "Collect", "Wind Crystal", math.max(6, Cfg.Reach - 4), function()
		collect(index)
	end)
	crystal.Parent = folder
	crystals[index] = crystal
end

local function refreshCrystals()
	if not folder then
		return
	end
	local now = ctx:Now()
	local visible = {}
	if unlocked() then
		for i in Cfg.Crystals do
			if ready(i, now) then
				table.insert(visible, i)
			end
		end
	end
	local key = table.concat(visible, ",")
	if key == shownKey then
		return
	end
	shownKey = key
	for _, part in crystals do
		part:Destroy()
	end
	table.clear(crystals)
	for _, i in visible do
		buildCrystal(i)
	end
end

-- Pads and gate ----------------------------------------------------------------------------
-- LaunchPad, ReturnPad and the Gate's Portal each stream in on their own (and can stream out and
-- back in later as fresh instances): wire each with Streaming.OnChild rather than a one-time scan.

local function wireLaunch(launch: Instance)
	prompt(launch, "Fly up", "Sky Islands", 12, function()
		if not unlocked() then
			ctx:Toast(string.format("The Sky Islands open at Ranch Level %d", Config.Unlocks.Features[Cfg.Unlock]), "info")
			return
		end
		teleport(Sky.returnPad, 4)
	end)
end

local function wireReturn(back: Instance)
	prompt(back, "Fly home", "Market Square", 12, function()
		teleport(Sky.launchPad, 4)
	end)
end

local function wireGate(gate: Instance)
	table.insert(
		connections,
		Streaming.OnChild(gate, "Portal", function(portal)
			prompt(portal, "Enter", "Sky Gate", 14, function()
				if ctx.Router:Has("Expeditions") then
					ctx.Router:Open("Expeditions", { region = "sky" })
				end
			end)
		end)
	)
end

local function wire(skyFolder: Instance)
	table.insert(connections, Streaming.OnChild(skyFolder, "LaunchPad", wireLaunch))
	table.insert(connections, Streaming.OnChild(skyFolder, "ReturnPad", wireReturn))
	table.insert(connections, Streaming.OnChild(skyFolder, "Gate", wireGate))
end

-- Every island sits well above the ground map; anything within ISLAND_MARGIN studs under the lowest
-- island top counts as up there (bridges sag, players jump off edges before respawning).
local ISLAND_MARGIN = 40
local lowestIsland = math.huge
for _, island in Sky.islands do
	lowestIsland = math.min(lowestIsland, island.center[2])
end

function SkyIslands.IsOnIslands(): boolean
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and root.Position.Y >= lowestIsland - ISLAND_MARGIN
end

function SkyIslands.Init(context)
	ctx = context
end

function SkyIslands.Start()
	local f = Instance.new("Folder")
	f.Name = "SkyCrystals"
	f.Parent = workspace
	folder = f
	ctx.Store:Observe("profile.SkyIslands", refreshCrystals)
	ctx.Store:Observe("profile.Progression.level", refreshCrystals)
	refreshCrystals()
	-- Crystals recharge on the clock; check a few times a minute.
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 5 then
			acc = 0
			refreshCrystals()
		end
	end)
	task.spawn(function()
		local world = workspace:WaitForChild("World", 60)
		if not world then
			return
		end
		table.insert(connections, Streaming.OnChild(world, "Sky", wire))
	end)
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function SkyIslands.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(crystals)
end

return SkyIslands
