--[[
	EditionPlates controller (glow-up W): a small "#37/500" tag at the feet of every numbered
	limited-edition monster in a pen, on every plot (global.Plots pens[].monsters[].appearance
	.ltdNo / .ltdOf). It sits at the feet so it never covers the bond nameplate above the head.
	Models come from World.MonsterModel (pooled and rebuilt by World), so everything re-syncs once
	a second and a gui is only rebuilt when its text changes. Low graphics: your own plot only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)

local New = Create.New

local EditionPlates = {
	Name = "EditionPlates",
	Dependencies = { "World" },
}

local ctx
local world
local heartbeat: RBXScriptConnection? = nil
local plates = {} -- [userId .. ":" .. id] = { gui, label }

local function playerGui(): Instance?
	return ctx.Player:FindFirstChildOfClass("PlayerGui")
end

local function lowGraphics(): boolean
	return ctx.Store:Get("profile.Settings.lowGraphics") == true
end

local function plateFor(key: string, parent: Instance)
	local plate = plates[key]
	if plate then
		return plate
	end
	local gui = New("BillboardGui", {
		Name = "EditionPlate",
		Size = UDim2.fromOffset(84, 24),
		StudsOffset = Vector3.new(0, -0.2, 0),
		MaxDistance = 60,
		AlwaysOnTop = false,
		LightInfluence = 0,
		Parent = parent,
	})
	local label = Create.Text({
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = Color3.fromHex(Config.Editions.Color),
		Stroke = true,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	plate = { gui = gui, label = label }
	plates[key] = plate
	return plate
end

local function sync()
	local parent = playerGui()
	if not parent then
		return
	end
	local seen = {}
	local low = lowGraphics()
	local plots = ctx.Store:Get("global.Plots")
	for _, plot in if type(plots) == "table" then plots else {} do
		local userId = type(plot) == "table" and tonumber(plot.userId) or 0
		if userId > 0 and (not low or userId == ctx.Player.UserId) and type(plot.pens) == "table" then
			for _, pen in plot.pens do
				for _, row in if type(pen) == "table" and type(pen.monsters) == "table" then pen.monsters else {} do
					local ap = type(row) == "table" and row.appearance
					if type(ap) == "table" and type(ap.ltdNo) == "number" then
						local model = world.MonsterModel and world.MonsterModel(userId, tostring(row.id))
						local root = model and model.PrimaryPart
						if root then
							local key = userId .. ":" .. tostring(row.id)
							seen[key] = true
							local plate = plateFor(key, parent)
							plate.gui.Adornee = root
							local text = string.format("#%d/%d", ap.ltdNo, tonumber(ap.ltdOf) or 0)
							if plate.label.Text ~= text then
								plate.label.Text = text
							end
						end
					end
				end
			end
		end
	end
	for key, plate in plates do
		if not seen[key] then
			plate.gui:Destroy()
			plates[key] = nil
		end
	end
end

function EditionPlates.Init(context)
	ctx = context
	world = ctx:GetController("World")
end

function EditionPlates.Start()
	local since = 1
	heartbeat = RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= 1 then
			since = 0
			sync()
		end
	end)
end

function EditionPlates.Destroy()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	for _, plate in plates do
		plate.gui:Destroy()
	end
	plates = {}
end

-- One sync now (tests and the first frame after a plot change).
EditionPlates.Sync = function()
	sync()
end

return EditionPlates
