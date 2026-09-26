--[[
	Visuals/RanchShowcase (glow-up Y): draws a ranch snapshot (Logic/Visits) as a compact ranch:
	a lawn, up to six pens (three across, two deep) painted and dressed by Visuals/PenDress from
	the same plan as a real pen (theme, fence tier, upgrades, habitat), their monsters
	(MonsterModel.Build, anchored, no particles), the Feed Garden, and the owner's best friends
	at the gate with their hearts. Nothing here runs per frame. Placed decor in `snap.decor` is
	left to the ranch builder (it is carried and sanitised, not drawn yet).

	  RanchShowcase.Build(snap, origin: CFrame, opts?) -> (Model, { pens, monsters })
	    origin = the showcase centre on the ground; the gate faces origin's -Z.
	    opts.title = sign text (default "Visiting Showcase"), opts.now = unix time for the garden.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PensLogic = require(Shared.Logic.Pens)

local Client = script.Parent.Parent
local PenDress = require(script.Parent.PenDress)
local MonsterModel = require(script.Parent.MonsterModel)
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)

local New = Create.New

local RanchShowcase = {}

local PEN = Config.World.PenSize
local S = Config.Visits.Showcase

local function part(name: string, size: Vector3, cf: CFrame, color: string, parent: Instance, solid: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = Color3.fromHex(color)
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function placeMonster(appearance, at: CFrame, parent: Instance, scale: number?): boolean
	local ok, model = pcall(MonsterModel.Build, appearance, { anchored = true, vfx = false, scale = scale })
	if not ok or not model then
		return false
	end
	local height = tonumber(model:GetAttribute("Height")) or 3
	model:PivotTo(at * CFrame.new(0, height / 2, 0))
	model.Parent = parent
	return true
end

local function label(parent: Instance, adornee: BasePart, text: string, offset: number, size: number, translate: boolean?)
	local gui = New("BillboardGui", {
		Name = "Label",
		Adornee = adornee,
		Size = UDim2.fromOffset(220, 34),
		StudsOffset = Vector3.new(0, offset, 0),
		MaxDistance = 220,
		LightInfluence = 0,
		Parent = parent,
	})
	local l = Create.Text({ Text = text, TextSize = size, Size = UDim2.fromScale(1, 1), Stroke = true, Parent = gui })
	if not translate then
		l:SetAttribute("Localize", false) -- numbers
	end
	return gui
end

-- One pen: a floor, four rails and four posts named like the server's pens, so PenDress paints
-- and dresses it the same way.
local function buildPen(index: number, pen, center: CFrame, parent: Instance, stats)
	local model = Instance.new("Model")
	model.Name = "Pen" .. index
	local w, d = PEN[1], PEN[2]
	part("Floor", Vector3.new(w, 0.4, d), center * CFrame.new(0, 0.5, 0), "#8BC56A", model)
	local railH = 2.5
	part("Rail1", Vector3.new(w, 0.4, 0.3), center * CFrame.new(0, 0.7 + railH, -d / 2), "#FFFFFF", model)
	part("Rail2", Vector3.new(w, 0.4, 0.3), center * CFrame.new(0, 0.7 + railH, d / 2), "#FFFFFF", model)
	part("Rail3", Vector3.new(0.3, 0.4, d), center * CFrame.new(-w / 2, 0.7 + railH, 0), "#FFFFFF", model)
	part("Rail4", Vector3.new(0.3, 0.4, d), center * CFrame.new(w / 2, 0.7 + railH, 0), "#FFFFFF", model)
	local post = 1
	for _, x in { -w / 2, w / 2 } do
		for _, z in { -d / 2, d / 2 } do
			part("Post" .. post, Vector3.new(0.6, 3.2, 0.6), center * CFrame.new(x, 0.7 + 1.6, z), "#FFFFFF", model)
			post += 1
		end
	end
	model.Parent = parent

	local plan = PensLogic.Plan(Config, pen, "full")
	PenDress.Paint(model, plan)
	local dress = Instance.new("Model")
	dress.Name = "Dress"
	dress:SetAttribute("Theme", plan.theme)
	dress.Parent = model
	local top = center * CFrame.new(0, 0.7, 0)
	PenDress.Caps(dress, model, plan)
	PenDress.Entries(dress, top, plan.props, plan)
	PenDress.Entries(dress, top, plan.habitat, plan)

	local monsters = pen.monsters or {}
	local n = #monsters
	for i, appearance in monsters do
		local col = (i - 1) % 4
		local row = math.floor((i - 1) / 4)
		local x = (col - 1.5) * (w / 5)
		local z = if n > 4 then (row - 0.5) * (d / 3) else 0
		if placeMonster(appearance, top * CFrame.new(x, 0, z) * CFrame.Angles(0, math.pi, 0), model) then
			stats.monsters += 1
		end
	end
	stats.pens += 1
end

function RanchShowcase.Build(snap, origin: CFrame, opts: { title: string?, now: number? }?)
	local o = opts or {}
	local stats = { pens = 0, monsters = 0 }
	local model = Instance.new("Model")
	model.Name = "RanchShowcase"
	model:SetAttribute("Owner", snap.userId)
	local sx, sz = S.size[1], S.size[2]
	local lawn = part("Lawn", Vector3.new(sx, 0.4, sz), origin * CFrame.new(0, 0.2, 0), "#9CD67A", model, true)
	lawn.Material = Enum.Material.Grass

	-- Pens: row 1 nearest the gate.
	local gap = S.penGap
	local front = -sz / 2 + 14
	for i, pen in snap.pens or {} do
		if i > 6 then
			break
		end
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		local x = (col - 1) * (PEN[1] + gap)
		local z = front + PEN[2] / 2 + row * (PEN[2] + gap)
		buildPen(i, pen, origin * CFrame.new(x, 0, z), model, stats)
	end

	-- Garden front left.
	if type(snap.garden) == "table" then
		local g = Instance.new("Model")
		g.Name = "Garden"
		g.Parent = model
		pcall(PenDress.Garden, g, origin * CFrame.new(-sx / 2 + 10, 0.4, -sz / 2 + 7), snap.garden, o.now or 0, "full")
	end

	-- Gate, sign and the owner's name.
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	gate.Parent = model
	local postL = part("PostL", Vector3.new(1.2, 9, 1.2), origin * CFrame.new(-8, 4.7, -sz / 2 + 1), "#FFFFFF", gate, true)
	part("PostR", Vector3.new(1.2, 9, 1.2), origin * CFrame.new(8, 4.7, -sz / 2 + 1), "#FFFFFF", gate, true)
	local sign = part("Sign", Vector3.new(18, 2.4, 0.6), origin * CFrame.new(0, 8.6, -sz / 2 + 1), "#C98B4B", gate)
	gate.PrimaryPart = postL
	local surface = New("SurfaceGui", { Face = Enum.NormalId.Front, CanvasSize = Vector2.new(360, 48), LightInfluence = 0, Parent = sign })
	Create.Text({ Text = o.title or "Visiting Showcase", TextScaled = true, Size = UDim2.fromScale(1, 1), Parent = surface })
	label(gate, sign, string.format("%s's ranch", tostring(snap.name or "")), 3, Theme.TextSize.Body, true)

	-- Best friends beside the gate, facing out.
	for i, b in snap.best or {} do
		local x = if i % 2 == 1 then -12 - (i - 1) * 2 else 12 + (i - 2) * 2
		local at = origin * CFrame.new(x, 0.4, -sz / 2 + 3) * CFrame.Angles(0, math.pi, 0)
		local stand = part("Friend" .. i, Vector3.new(3, 0.3, 3), at, "#FFD7E6", model)
		if placeMonster(b.appearance, at * CFrame.new(0, 0.2, 0), model) then
			stats.monsters += 1
			label(stand, stand, string.format("%d ♥", tonumber(b.hearts) or 0), 7, Theme.TextSize.Small)
		end
	end
	return model, stats
end

return RanchShowcase
