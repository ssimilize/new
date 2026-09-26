--[[
	World/Balcony (glow-up L): placeholder geometry for the VIP balcony beside the plaza, from
	Config.Community.VipBalcony. Built into Hub by Build.world (main place only).

	  Hub/VipBalcony                Model (attrs HubId = "vipBalcony", DisplayName)
	    Body                        the deck floor (World/Dress can fit a model here later)
	    Pillar1..4, Rail*           supports and a waist-high rail with collision
	    Sofa*, Rug, Sign            lounge dressing and the name board
	    ReturnPad                   Part on the deck (attr VipPad = "exit")
	  Hub/VipPad                    Part on the ground (attr VipPad = "enter")

	The client puts prompts on the VipPad parts and asks Community.Balcony; the server moves the
	character (only VIP Rancher owners up) and moves anyone else off the deck.
]]

local Balcony = {}

local GOLD = Color3.fromHex("#FFC83D")
local DECK = Color3.fromHex("#8C5A3C")
local STONE = Color3.fromHex("#E9DFC9")
local VELVET = Color3.fromHex("#7B3FA0")

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	for key, value in props or {} do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function sign(parent: BasePart, text: string, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameGui"
	gui.Size = UDim2.fromScale(14, 3)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = GOLD
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromHex("#5A3A00")
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = parent
end

-- Builds the balcony under `hub`; returns the number of parts made.
function Balcony.build(Config, hub: Instance, groundY: number): number
	local b = Config.Community and Config.Community.VipBalcony
	if not b then
		return 0
	end
	local count = 0
	local function add(...)
		count += 1
		return part(...)
	end

	local model = Instance.new("Model")
	model.Name = "VipBalcony"
	model:SetAttribute("HubId", "vipBalcony")
	model:SetAttribute("DisplayName", "VIP Balcony")

	local sx, sz = b.deckSize[1], b.deckSize[2]
	local floorY = groundY + b.height
	local centre = Vector3.new(b.deck[1], floorY - 0.5, b.deck[3])
	-- Face the fountain, like the hub buildings.
	local look = Vector3.new(0, centre.Y, 0)
	local cf = CFrame.lookAt(centre, look)
	local body = add("Body", Vector3.new(sx, 1, sz), cf, DECK, model)
	model.PrimaryPart = body

	for i, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local offset = CFrame.new(corner[1] * (sx / 2 - 1), -(b.height / 2), corner[2] * (sz / 2 - 1))
		add("Pillar" .. i, Vector3.new(2, b.height, 2), cf * offset, STONE, model)
	end
	local railH = 3
	add("RailFront", Vector3.new(sx, railH, 0.6), cf * CFrame.new(0, railH / 2 + 0.5, -sz / 2 + 0.3), GOLD, model)
	add("RailBack", Vector3.new(sx, railH, 0.6), cf * CFrame.new(0, railH / 2 + 0.5, sz / 2 - 0.3), GOLD, model)
	add("RailLeft", Vector3.new(0.6, railH, sz), cf * CFrame.new(-sx / 2 + 0.3, railH / 2 + 0.5, 0), GOLD, model)
	add("RailRight", Vector3.new(0.6, railH, sz), cf * CFrame.new(sx / 2 - 0.3, railH / 2 + 0.5, 0), GOLD, model)
	add("Rug", Vector3.new(sx - 6, 0.1, sz - 6), cf * CFrame.new(0, 0.55, 0), VELVET, model, { CanCollide = false })
	add("SofaLeft", Vector3.new(6, 1.6, 2.4), cf * CFrame.new(-sx / 4, 1.3, sz / 2 - 2.4), VELVET, model)
	add("SofaRight", Vector3.new(6, 1.6, 2.4), cf * CFrame.new(sx / 4, 1.3, sz / 2 - 2.4), VELVET, model)
	local board = add("Sign", Vector3.new(8, 2, 0.5), cf * CFrame.new(0, railH + 1.6, -sz / 2 + 0.3), GOLD, model)
	sign(board, "VIP Balcony", 2.5)
	local back = add("ReturnPad", Vector3.new(4, 0.3, 4), cf * CFrame.new(sx / 2 - 3.5, 0.65, -sz / 2 + 3.5), GOLD, model, {
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	back:SetAttribute("VipPad", "exit")
	model.Parent = hub

	local padPos = Vector3.new(b.pad[1], groundY + 0.35, b.pad[3])
	local pad = add("VipPad", Vector3.new(6, 0.4, 6), CFrame.new(padPos), GOLD, hub, { Material = Enum.Material.Neon, CanCollide = false })
	pad:SetAttribute("VipPad", "enter")
	sign(pad, "VIP Balcony", 4)
	return count
end

return Balcony
