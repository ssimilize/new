--[[
	Riding controller (update 2.0): draws every rider's mount and moves the local rider.

	  · global.Riding.riders['u'..userId] = { appearance, speed }: each rider's mount model
	    (MonsterModel, scaled by Config.Riding.MountScale) is welded under their
	    HumanoidRootPart as "Mount", massless and without collision.
	  · The local rider walks at session.Riding.speed with a higher HipHeight so the avatar
	    sits on the mount; both go back to normal on dismount.
	  · A "Get off" button (Hud layer) calls Riding.Dismount while riding. Mounting starts
	    from the Ride button on the monster screen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Button = require(UI.Components.Button)
local StoreKit = require(UI.Components.StoreKit)
local MonsterModel = require(script.Parent.Parent.Visuals.MonsterModel)

local Cfg = Config.Riding
local DEFAULT_HIP = 2

local Riding = {
	Name = "Riding",
	Dependencies = {},
}

local ctx
local shown = {} -- [Player] = key of the mount drawn for them
local dismountButton = nil
local baseHip: number? = nil
local localHeight = 0 -- height of the local player's mount (0 = not riding)

local function riders()
	return StoreKit.tbl(ctx.Store, "global.Riding.riders")
end

local function mountKey(rider): string
	local ap = rider.appearance or {}
	local acc = {}
	for _, slot in Config.Accessories.Slots do
		table.insert(acc, if type(ap.acc) == "table" then ap.acc[slot] or "-" else "-")
	end
	return table.concat({ tostring(ap.form), tostring(ap.variant), table.concat(ap.muts or {}, "+"), table.concat(acc, ",") }, "|")
end

local function removeMount(character: Instance?)
	local old = character and character:FindFirstChild("Mount")
	if old then
		old:Destroy()
	end
end

-- Returns the mount's height in studs (0 when nothing was built). `hip` is the rider's
-- HipHeight before mounting.
local function attachMount(character: Model, rider, hip: number): number
	removeMount(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or type(rider.appearance) ~= "table" or not Config.Species.ById[rider.appearance.line] then
		return 0
	end
	local ok, model = pcall(MonsterModel.Build, rider.appearance, { anchored = false, scale = Cfg.MountScale })
	if not ok then
		return 0
	end
	local height = tonumber(model:GetAttribute("Height")) or 3 * Cfg.MountScale
	model.Name = "Mount"
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Massless = true
		end
	end
	-- The rider's HipHeight is raised by height × 0.8 (updateLocal), so the root part floats
	-- DEFAULT_HIP + height × 0.8 + half its size above the ground: put the mount's feet there.
	local drop = hip + height * 0.8 + hrp.Size.Y / 2
	-- Monsters face -Z like characters, so the mount looks where the rider looks.
	model:PivotTo(hrp.CFrame * CFrame.new(0, -drop, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hrp
	weld.Part1 = model.PrimaryPart
	weld.Parent = model.PrimaryPart
	model.Parent = character
	return height
end

local function localHumanoid(): Humanoid?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function localBaseHip(): number
	local humanoid = localHumanoid()
	baseHip = baseHip or (if humanoid then humanoid.HipHeight else DEFAULT_HIP)
	return baseHip :: number
end

-- Speed and hip height follow session.Riding and the mount drawn for us (the two can
-- arrive in either order).
local function updateLocal()
	local humanoid = localHumanoid()
	local sess = StoreKit.tbl(ctx.Store, "session.Riding")
	local riding = type(sess.mount) == "string"
	if humanoid then
		local base = localBaseHip()
		humanoid.WalkSpeed = if riding then (tonumber(sess.speed) or Cfg.WalkSpeed) else Cfg.WalkSpeed
		humanoid.HipHeight = if riding and localHeight > 0 then base + localHeight * 0.8 else base
	end
	if dismountButton then
		dismountButton:SetVisible(riding)
	end
end

local function refresh()
	local list = riders()
	for _, player in Players:GetPlayers() do
		local rider = list["u" .. tostring(player.UserId)]
		local character = player.Character
		local key = if type(rider) == "table" then mountKey(rider) else nil
		if character and key ~= shown[player] then
			shown[player] = key
			local isLocal = player == Players.LocalPlayer
			local height = 0
			if key then
				height = attachMount(character, rider, if isLocal then localBaseHip() else DEFAULT_HIP)
			else
				removeMount(character)
			end
			if isLocal then
				localHeight = height
			end
		end
	end
	updateLocal()
end

function Riding.Init(context)
	ctx = context
end

function Riding.Start()
	dismountButton = Button.new({
		Name = "DismountButton",
		Text = "Get off",
		Color = Theme.Colors.Orange,
		TextSize = Theme.TextSize.Body,
		Size = UDim2.fromOffset(150, 52),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -120),
		Parent = ctx.UI.Hud,
		OnClick = function()
			StoreKit.request(ctx, "Riding.Dismount")
		end,
	})
	dismountButton:SetVisible(false)
	ctx.Store:Observe("global.Riding.riders", refresh)
	ctx.Store:Observe("session.Riding", refresh)
	local function watch(player)
		player.CharacterAdded:Connect(function()
			shown[player] = nil
			if player == Players.LocalPlayer then
				baseHip = nil
				localHeight = 0
			end
			task.defer(refresh)
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		shown[player] = nil
	end)
	refresh()
end

return Riding
