--[[
	FamePlaza controller (glow-up O): the Hall of Fame plaza south-west of the Market Square
	(Config.Codex.Plaza). Every player on the server has their best statue there
	(global.HallOfFame.plaza, filled by Systems/HallOfFame) on a pedestal with their name.

	Pedestals and name plates are built once for every slot; a slot's golden statue
	(MonsterModel.Build, look "golden", no particles) is built only while the camera is within
	modelRange of the plaza, and rebuilt when its owner's best statue changes. An empty slot shows
	a bare pedestal. Nothing is built in the hub place. No state, actions or bus topics.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Museum = require(Shared.Logic.Museum)

local Client = script.Parent.Parent
local MonsterModel = require(Client.Visuals.MonsterModel)
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)

local New = Create.New
local P = Config.Codex.Plaza

local FamePlaza = {
	Name = "FamePlaza",
	Dependencies = {},
}

local ctx
local folder: Folder? = nil
local slots = {} -- [slot] = { base, name, gui, model?, key?, entry? }
local near = false
local connections = {}

local function buildPlaza()
	local f = Instance.new("Folder")
	f.Name = "FamePlaza"
	local ox, oy, oz = P.origin[1], P.origin[2], P.origin[3]
	local rows = math.ceil(P.max / P.perRow)
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(P.perRow * P.spacing + 6, 0.6, rows * P.rowGap + 10)
	floor.CFrame = CFrame.new(ox, oy + 0.3, oz - 8 - (rows - 1) * P.rowGap / 2)
	floor.Color = Color3.fromHex("#E8DCC0")
	floor.Material = Enum.Material.Cobblestone
	floor.Parent = f
	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.Size = Vector3.new(20, 3, 0.6)
	sign.CFrame = CFrame.new(ox, oy + 6, oz + 1)
	sign.Color = Color3.fromHex("#D49A12")
	sign.Parent = f
	local gui = New("SurfaceGui", { Face = Enum.NormalId.Back, CanvasSize = Vector2.new(400, 60), LightInfluence = 0, Parent = sign })
	Create.Text({
		Text = "Hall of Fame Plaza",
		TextSize = Theme.TextSize.Title,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	for slot = 1, P.max do
		local x, y, z = Museum.PlazaSpot(Config, slot)
		local base = Instance.new("Part")
		base.Name = "Pedestal" .. slot
		base.Anchored = true
		base.Size = Vector3.new(P.pedestal[1], P.pedestal[2], P.pedestal[3])
		base.CFrame = CFrame.new(x, y + 0.6 + P.pedestal[2] / 2, z)
		base.Color = Color3.fromHex("#EDEAE4")
		base.Material = Enum.Material.Marble
		base.Parent = f
		local plate = New("BillboardGui", {
			Name = "Owner",
			Adornee = base,
			Size = UDim2.fromOffset(160, 30),
			StudsOffset = Vector3.new(0, 1.2, 0),
			MaxDistance = P.modelRange,
			LightInfluence = 0,
			Enabled = false,
			Parent = base,
		})
		local label =
			Create.Text({ Text = "", TextSize = Theme.TextSize.Body, Size = UDim2.fromScale(1, 1), Stroke = true, Parent = plate })
		label:SetAttribute("Localize", false) -- a player's name
		slots[slot] = { base = base, name = label, gui = plate }
	end
	f.Parent = workspace
	folder = f
end

local function clearModel(s)
	if s.model then
		s.model:Destroy()
		s.model = nil
	end
end

local function buildModel(s)
	if s.model or not s.entry or not near then
		return
	end
	local ok, model = pcall(MonsterModel.Build, s.entry.appearance, { anchored = true, vfx = false, look = "golden" })
	if not ok or not model then
		return
	end
	local top = s.base.Position + Vector3.new(0, s.base.Size.Y / 2, 0)
	local height = tonumber(model:GetAttribute("Height")) or 3
	local at = top + Vector3.new(0, height / 2, 0)
	model:PivotTo(CFrame.lookAt(at, at + Vector3.new(0, 0, 1)))
	model.Parent = folder
	s.model = model
end

local function refresh()
	local plaza = ctx.Store:Get("global.HallOfFame.plaza")
	local bySlot = {}
	if type(plaza) == "table" then
		for key, entry in plaza do
			if type(entry) == "table" and type(entry.slot) == "number" and slots[entry.slot] and type(entry.appearance) == "table" then
				bySlot[entry.slot] = { key = key, entry = entry }
			end
		end
	end
	for slot, s in slots do
		local now = bySlot[slot]
		local form = now and now.entry.appearance.form
		local same = now ~= nil and s.key == now.key and s.form == form
		if not same then
			clearModel(s)
			s.key = now and now.key
			s.entry = now and now.entry
			s.form = form
			s.name.Text = if now then tostring(now.entry.name or "") else ""
			s.gui.Enabled = now ~= nil
			buildModel(s)
		end
	end
end

function FamePlaza.Init(context)
	ctx = context
end

function FamePlaza.Start()
	local acc = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < 1 then
				return
			end
			acc = 0
			if not folder then
				if not ctx.Store.Ready or ctx.Store:Get("global.TradingHub.mode") == "hub" then
					return
				end
				buildPlaza()
				refresh()
				table.insert(connections, ctx.Store:Observe("global.HallOfFame", refresh))
			end
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local at = camera.CFrame.Position
			local dx, dz = at.X - P.origin[1], at.Z - P.origin[3]
			local nowNear = dx * dx + dz * dz <= P.modelRange * P.modelRange
			if nowNear ~= near then
				near = nowNear
				for _, s in slots do
					if near then
						buildModel(s)
					else
						clearModel(s)
					end
				end
			end
		end)
	)
end

-- Tests: statues shown (3D models) and owners listed.
function FamePlaza.Stats(): (number, number)
	local models, owners = 0, 0
	for _, s in slots do
		if s.model then
			models += 1
		end
		if s.entry then
			owners += 1
		end
	end
	return models, owners
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function FamePlaza.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, s in slots do
		clearModel(s)
	end
	table.clear(slots)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return FamePlaza
