--[[
	EggHunt controller (update 1.4, Spring Bloom): draws this round's painted eggs around the
	Market Square and lets the player pick them up.

	Reads global.EggHunt { active, round, spots } and profile.EggHunt { round, found }. Every
	spot in `spots` the player has not found this round gets an egg (EggModel, tinted from
	Config.EggHunt.Colors) with a "Pick up" ProximityPrompt → EggHunt.Find { spot }. The
	server checks the distance again; eggs vanish once the profile lists them as found.
	Eggs live in Workspace.EggHunt (client-only, so each player sees only their own).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local EggModel = require(script.Parent.Parent.Visuals.EggModel)
local StoreKit = require(script.Parent.Parent.UI.Components.StoreKit)

local Cfg = Config.EggHunt

local EggHunt = {
	Name = "EggHunt",
	Dependencies = {},
}

local ctx
local folder: Instance? = nil
local eggs = {} -- [spot] = Model
local drawnKey = ""

local function tbl(path: string)
	local v = ctx.Store:Get(path)
	return if type(v) == "table" then v else {}
end

-- Spots that should show an egg right now.
local function visibleSpots(): { number }
	local g = tbl("global.EggHunt")
	if g.active ~= true or type(g.spots) ~= "table" then
		return {}
	end
	local mine = tbl("profile.EggHunt")
	local found = if mine.round == g.round and type(mine.found) == "table" then mine.found else {}
	local list = {}
	for _, spot in g.spots do
		if Cfg.Spots[spot] and not table.find(found, spot) then
			table.insert(list, spot)
		end
	end
	return list
end

local function clearEggs()
	for _, model in eggs do
		model:Destroy()
	end
	table.clear(eggs)
end

local function pickUp(spot: number)
	local ok, res = StoreKit.request(ctx, "EggHunt.Find", { spot = spot })
	if not ok or type(res) ~= "table" then
		return
	end
	if eggs[spot] then
		eggs[spot]:Destroy()
		eggs[spot] = nil
	end
	local token = Config.Events.Active(ctx:Now())
	local tokenName = if token then token.token.name else "tokens"
	if res.complete then
		ctx:Toast(string.format("You found every egg this round! +%d %s", res.tokens or 0, tokenName), "reward")
	else
		ctx:Toast(string.format("Painted egg! +%d %s (%d left)", res.tokens or 0, tokenName, res.left or 0), "reward")
	end
end

local function buildEgg(spot: number)
	local pos = Cfg.Spots[spot]
	-- A plain shell in the spot's colour with white paint over it.
	local model = EggModel.Build("bloom", { size = 2.2, tint = Color3.fromHex(Cfg.Colors[(spot - 1) % #Cfg.Colors + 1]) })
	model.Name = "HuntEgg" .. spot
	local root = model.PrimaryPart :: BasePart
	root.CFrame = CFrame.new(pos[1], pos[2] + 1.2, pos[3]) * CFrame.Angles(0, math.rad(spot * 37), math.rad(12))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickUp"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = "Painted Egg"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = math.max(6, Cfg.Reach - 4)
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX -- the pad hint; Racing and Surf never use X
	prompt.Parent = root
	prompt.Triggered:Connect(function()
		pickUp(spot)
	end)
	model:SetAttribute("Spot", spot)
	model.Parent = folder
	eggs[spot] = model
end

local function draw()
	if not folder then
		return
	end
	local spots = visibleSpots()
	local key = table.concat(spots, ",")
	if key == drawnKey then
		return
	end
	drawnKey = key
	clearEggs()
	for _, spot in spots do
		buildEgg(spot)
	end
end

function EggHunt.Init(context)
	ctx = context
end

function EggHunt.Start()
	local f = Instance.new("Folder")
	f.Name = "EggHunt"
	f.Parent = workspace
	folder = f
	ctx.Store:Observe("global.EggHunt", draw)
	ctx.Store:Observe("profile.EggHunt", draw)
	draw()
end

return EggHunt
