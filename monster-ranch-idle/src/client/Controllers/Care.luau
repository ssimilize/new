--[[
	Care controller (glow-up Q): bond in the world.

	  Taps      a tap on one of your own pen monsters opens the Care screen for it (World's own-tap
	            hook, World.OwnTapHandler). The screen runs the gestures and asks Bond.Care.
	  Plates    a small "♥ n  Name" nameplate over every pen monster at Config.Bond.NameplateHearts
	            or more (global.Bond.here[..].plates), on every plot; low graphics: your plot only.
	  Gate      each occupied plot's gate shows its owner's best friends (global.Bond.here[..].best,
	            up to Config.Bond.BestFriends) as portraits from UI/Art/Sheet on a BillboardGui
	            above the plot sign, so visitors see them. Low graphics: a shorter draw distance.
	Everything re-syncs once a second (models are pooled and rebuilt by World), and only rebuilds
	a gui when what it shows changed.
	Public: Care.Open(id) -> boolean
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Sheet = require(UI.Art.Sheet)

local New = Create.New
local C = Theme.Colors

local Care = {
	Name = "Care",
	Dependencies = { "World" },
}

local ctx
local world
local heartbeat: RBXScriptConnection? = nil
local plates = {} -- [userId .. ":" .. id] = { gui, label, key }
local gates = {} -- [plotIndex] = { gui, key }

local function playerGui(): Instance?
	return ctx.Player:FindFirstChildOfClass("PlayerGui")
end

local function lowGraphics(): boolean
	return ctx.Store:Get("profile.Settings.lowGraphics") == true
end

function Care.Open(id: string): boolean
	if type(id) ~= "string" then
		return false
	end
	ctx.Router:Open("Care", { id = id })
	return true
end

-- Nameplates ----------------------------------------------------------------------------------

local function syncPlates(here, parent: Instance)
	local seen = {}
	local low = lowGraphics()
	for key, view in if type(here) == "table" then here else {} do
		local userId = tonumber(string.sub(tostring(key), 2))
		if userId and type(view) == "table" and type(view.plates) == "table" and (not low or userId == ctx.Player.UserId) then
			for _, row in view.plates do
				local model = world.MonsterModel and world.MonsterModel(userId, tostring(row.id))
				local root = model and model.PrimaryPart
				if root then
					local plateKey = userId .. ":" .. tostring(row.id)
					seen[plateKey] = true
					local plate = plates[plateKey]
					if not plate then
						local gui = New("BillboardGui", {
							Name = "BondPlate",
							Size = UDim2.fromOffset(170, 30),
							StudsOffset = Vector3.new(0, 4.2, 0),
							MaxDistance = 70,
							AlwaysOnTop = false,
							LightInfluence = 0,
							Parent = parent,
						})
						local label = Create.Text({
							Text = "",
							TextSize = Theme.TextSize.Small,
							TextColor3 = C.Pink,
							Stroke = true,
							Size = UDim2.fromScale(1, 1),
							Parent = gui,
						})
						label:SetAttribute("Localize", false)
						plate = { gui = gui, label = label }
						plates[plateKey] = plate
					end
					plate.gui.Adornee = root
					plate.label.Text = string.format("♥%d  %s", tonumber(row.hearts) or 0, tostring(row.name or ""))
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

-- Ranch gate ----------------------------------------------------------------------------------

local function gateAnchor(index: number): Instance?
	local worldFolder = workspace:FindFirstChild("World")
	local plotsFolder = worldFolder and worldFolder:FindFirstChild("Plots")
	local plot = plotsFolder and plotsFolder:FindFirstChild("Plot" .. index)
	local gate = plot and plot:FindFirstChild("Gate")
	return (gate and (gate:FindFirstChild("Sign") or gate)) or (plot and plot:FindFirstChild("Floor"))
end

local function buildGate(index: number, best, parent: Instance)
	local gui = New("BillboardGui", {
		Name = "BestFriends" .. index,
		Size = UDim2.fromScale(12, 4.2),
		StudsOffset = Vector3.new(0, 8.6, 0),
		MaxDistance = if lowGraphics() then 90 else 160,
		LightInfluence = 0,
		Parent = parent,
	})
	Create.Text({
		Name = "Caption",
		Text = "Best friends",
		TextScaled = true,
		TextColor3 = C.Pink,
		Stroke = true,
		Size = UDim2.fromScale(1, 0.24),
		Parent = gui,
	})
	local count = #best
	for i, friend in best do
		local slot = New("Frame", {
			Name = "Friend" .. i,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5 + (i - (count + 1) / 2) / 3, 0.26),
			Size = UDim2.fromScale(0.3, 0.74),
			BackgroundTransparency = 1,
			Parent = gui,
		})
		local frame = New("Frame", {
			Name = "Portrait",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(0.7, 0.72),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			BackgroundColor3 = C.Panel,
			Parent = slot,
		}, { Create.Corner(12), Create.Stroke(2) })
		local art = Sheet.portrait(tostring(friend.form), { Parent = frame })
		if not art then
			local fallback =
				Create.Text({ Text = "♥", TextScaled = true, TextColor3 = C.Pink, Size = UDim2.fromScale(1, 1), Parent = frame })
			fallback:SetAttribute("Localize", false)
		end
		local label = Create.Text({
			Name = "Hearts",
			Text = string.format("♥%d", tonumber(friend.hearts) or 0),
			TextScaled = true,
			TextColor3 = C.Pink,
			Stroke = true,
			Position = UDim2.fromScale(0, 0.74),
			Size = UDim2.fromScale(1, 0.26),
			Parent = slot,
		})
		label:SetAttribute("Localize", false)
	end
	gui.Adornee = gateAnchor(index)
	return gui
end

local function syncGates(here, plots, parent: Instance)
	for index = 1, #Config.World.Plots do
		local plot = if type(plots) == "table" then plots[index] else nil
		local userId = if type(plot) == "table" then tonumber(plot.userId) or 0 else 0
		local view = if userId ~= 0 and type(here) == "table" then here["u" .. userId] else nil
		local best = if type(view) == "table" and type(view.best) == "table" then view.best else {}
		local parts = { tostring(userId), tostring(lowGraphics()) }
		for _, friend in best do
			table.insert(parts, string.format("%s/%s/%s", tostring(friend.id), tostring(friend.form), tostring(friend.hearts)))
		end
		local key = table.concat(parts, "|")
		local gate = gates[index]
		if gate and (gate.key ~= key or not gate.gui.Parent) then
			gate.gui:Destroy()
			gates[index] = nil
			gate = nil
		end
		if not gate and #best > 0 then
			gates[index] = { gui = buildGate(index, best, parent), key = key }
		elseif gate and not gate.gui.Adornee then
			gate.gui.Adornee = gateAnchor(index)
		end
	end
end

local function sync()
	local parent = playerGui()
	if not parent then
		return
	end
	local here = ctx.Store:Get("global.Bond.here")
	syncPlates(here, parent)
	syncGates(here, ctx.Store:Get("global.Plots"), parent)
end

function Care.Init(context)
	ctx = context
	world = ctx:GetController("World")
	world.OwnTapHandler = function(id: string): boolean
		return Care.Open(id)
	end
end

function Care.Start()
	local since = 1
	heartbeat = RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= 1 then
			since = 0
			sync()
		end
	end)
end

function Care.Destroy()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	for _, plate in plates do
		plate.gui:Destroy()
	end
	for _, gate in gates do
		gate.gui:Destroy()
	end
	plates, gates = {}, {}
end

return Care
