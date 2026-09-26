--[[
	CodexMuseum controller (glow-up O): a walk-in hall south-east of the Market Square
	(Config.Codex.Museum), built on this client for the local player's own Codex
	(profile.Monsters.codex). One pedestal per species line, in wings by element (Logic/Museum.Layout).

	  undiscovered line   a dark silhouette slab and "???" on the pedestal
	  discovered, far     the line's name on the pedestal ("plate")
	  discovered, near    a portrait sign over the pedestal ("sign", within signRange)
	  nearest few         the line's most grown found form as a 3D monster (MonsterModel.Build)

	Every updateEvery seconds Logic/Museum.Plan picks the states from the camera position: at most
	maxModels 3D monsters (lowModels in low graphics, no particles there). Models leaving the set
	are parked in a pool by form (Museum.newPool) and reused when that form comes back. Nothing is
	built in the hub place. No state, actions or bus topics.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Appearance = require(Shared.Logic.Appearance)
local Museum = require(Shared.Logic.Museum)

local Client = script.Parent.Parent
local MonsterModel = require(Client.Visuals.MonsterModel)
local MonsterIcon = require(Client.UI.Components.MonsterIcon)
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)

local New = Create.New
local M = Config.Codex.Museum

local CodexMuseum = {
	Name = "CodexMuseum",
	Dependencies = {},
}

local ctx
local folder: Folder? = nil
local layout
local pedestals = {} -- [i] = { part, label, slab, sign?, model?, form?, state }
local known = {} -- [lineId] = true
local bestForm = {} -- [lineId] = { stage, form }
local plan, scratch, previous = {}, {}, {}
local opts = { max = M.maxModels, modelRange = M.modelRange, signRange = M.signRange, previous = previous }
local pool
local lowGraphics = false
local connections = {}

local STONE = Color3.fromHex("#EDE3D3")
local DARK = Color3.fromHex("#3B3350")

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function textSign(parent: BasePart, face: Enum.NormalId, text: string, size: Vector2): TextLabel
	local gui = New("SurfaceGui", {
		Face = face,
		CanvasSize = size,
		LightInfluence = 0,
		Parent = parent,
	})
	return Create.Text({
		Text = text,
		TextSize = Theme.TextSize.Title,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
end

local function lineName(lineId: string): string
	local def = Config.Species.ById[lineId]
	return if def then def.forms[1].name else lineId
end

local function buildHall()
	local f = Instance.new("Folder")
	f.Name = "CodexMuseum"
	local b = layout.bounds
	local cx, cz = (b.minX + b.maxX) / 2, (b.minZ + b.maxZ) / 2
	local w, d = b.maxX - b.minX, b.maxZ - b.minZ
	local y = M.origin[2]
	part({
		Name = "Floor",
		Size = Vector3.new(w, 0.6, d),
		CFrame = CFrame.new(cx, y + 0.3, cz),
		Color = STONE,
		Material = Enum.Material.Marble,
		Parent = f,
	})
	-- Low walls on three sides; the entrance side (+z) stays open.
	local h = M.wallHeight
	for _, wall in
		{
			{ Vector3.new(w, h, 1), Vector3.new(cx, y + h / 2, b.minZ) },
			{ Vector3.new(1, h, d), Vector3.new(b.minX, y + h / 2, cz) },
			{ Vector3.new(1, h, d), Vector3.new(b.maxX, y + h / 2, cz) },
		}
	do
		part({ Name = "Wall", Size = wall[1], CFrame = CFrame.new(wall[2]), Color = STONE, Material = Enum.Material.Marble, Parent = f })
	end
	local arch = part({
		Name = "Entrance",
		Size = Vector3.new(24, 4, 1),
		CFrame = CFrame.new(M.origin[1], y + h + 2, b.maxZ),
		Color = Theme.Colors.Blue,
		CanCollide = false,
		Parent = f,
	})
	textSign(arch, Enum.NormalId.Back, "Codex Museum", Vector2.new(480, 80))
	for _, wing in layout.wings do
		local sign = part({
			Name = "Wing",
			Size = Vector3.new(M.wingWidth - 2, 2, 0.4),
			CFrame = CFrame.new(wing.x, y + 5, wing.z + 1),
			Color = if wing.element then Color3.fromHex(Config.Elements.ById[wing.element].color) else Theme.Colors.Purple,
			CanCollide = false,
			Parent = f,
		})
		textSign(sign, Enum.NormalId.Back, wing.title, Vector2.new(300, 40))
	end
	local size = Vector3.new(M.pedestal[1], M.pedestal[2], M.pedestal[3])
	for i, p in layout.pedestals do
		local base = part({
			Name = p.line,
			Size = size,
			CFrame = CFrame.new(p.x, p.y + size.Y / 2 + 0.6, p.z),
			Color = STONE,
			Material = Enum.Material.Marble,
			Parent = f,
		})
		local slab = part({
			Name = "Silhouette",
			Size = Vector3.new(size.X * 0.6, 2.4, 0.3),
			CFrame = CFrame.new(p.x, p.y + size.Y + 1.8, p.z),
			Color = DARK,
			CanCollide = false,
			CanQuery = false,
			Parent = base,
		})
		local label = textSign(base, Enum.NormalId.Back, "???", Vector2.new(200, 60))
		pedestals[i] = { part = base, label = label, slab = slab, state = "plate", line = p.line }
	end
	f.Parent = workspace
	folder = f
end

local function releaseModel(ped)
	if ped.model then
		ped.model.Parent = nil
		pool:Give(ped.form, ped.model)
		ped.model = nil
	end
end

local function showModel(ped)
	local best = bestForm[ped.line]
	if not best then
		return
	end
	local model = pool:Take(best.form)
	if not model then
		local ok, built = pcall(function()
			local ap = Appearance.Preview(ped.line, best.stage, best.form)
			return MonsterModel.Build(ap, { anchored = true, vfx = not lowGraphics })
		end)
		if not ok then
			return
		end
		model = built
	end
	local top = ped.part.Position + Vector3.new(0, ped.part.Size.Y / 2, 0)
	local height = tonumber(model:GetAttribute("Height")) or 3
	local at = top + Vector3.new(0, height / 2, 0)
	model:PivotTo(CFrame.lookAt(at, at + Vector3.new(0, 0, 1)))
	model.Parent = folder
	ped.model = model
	ped.form = best.form
end

local function setSign(ped, on: boolean)
	if on and not ped.sign then
		local best = bestForm[ped.line]
		if not best then
			return
		end
		local ok, ap = pcall(Appearance.Preview, ped.line, best.stage, best.form)
		if not ok then
			return
		end
		local gui = New("BillboardGui", {
			Name = "Portrait",
			Adornee = ped.part,
			Size = UDim2.fromOffset(64, 64),
			StudsOffset = Vector3.new(0, 3.5, 0),
			MaxDistance = M.signRange,
			LightInfluence = 0,
			Parent = ped.part,
		})
		local icon = MonsterIcon.new(ap, 64)
		icon.Parent = gui
		ped.sign = gui
	end
	if ped.sign then
		ped.sign.Enabled = on
	end
end

local function apply(i: number, state: string)
	local ped = pedestals[i]
	if ped.state == state then
		return
	end
	if ped.state == "model" then
		releaseModel(ped)
	end
	if state == "model" then
		showModel(ped)
	end
	setSign(ped, state == "sign")
	ped.state = state
	previous[i] = state
end

-- Re-reads the Codex: which lines are known and their most grown found form.
local function readCodex()
	local codex = ctx.Store:Get("profile.Monsters.codex")
	table.clear(known)
	local changed = {}
	for _, def in Config.Species.Lines do
		local entry = type(codex) == "table" and codex[def.id]
		local forms = type(entry) == "table" and type(entry.forms) == "table" and entry.forms or nil
		local best
		if forms then
			for stage, form in def.forms do
				if stage == 3 then
					for _, adult in form do
						if forms[adult.id] then
							best = { stage = 3, form = adult.id }
						end
					end
				elseif forms[form.id] then
					best = { stage = stage, form = form.id }
				end
			end
		end
		local old = bestForm[def.id]
		if (old and old.form) ~= (best and best.form) then
			changed[def.id] = true
		end
		bestForm[def.id] = best
		known[def.id] = best ~= nil
	end
	for i, ped in pedestals do
		if changed[ped.line] then
			local found = known[ped.line]
			ped.label.Text = if found then lineName(ped.line) else "???"
			ped.slab.Transparency = if found then 1 else 0
			-- A newly grown form replaces the model and portrait.
			if ped.sign then
				ped.sign:Destroy()
				ped.sign = nil
			end
			if ped.state == "model" then
				releaseModel(ped)
			end
			ped.state = "plate"
			previous[i] = "plate"
		end
	end
end

local function step()
	local camera = workspace.CurrentCamera
	if not folder or not camera then
		return
	end
	local at = camera.CFrame.Position
	opts.max = if lowGraphics then M.lowModels else M.maxModels
	Museum.Plan(layout.pedestals, at.X, at.Z, known, opts, plan, scratch)
	for i = 1, #pedestals do
		apply(i, plan[i] or "plate")
	end
end

function CodexMuseum.Init(context)
	ctx = context
end

function CodexMuseum.Start()
	local built = false
	local acc = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < M.updateEvery then
				return
			end
			acc = 0
			if not built then
				if not ctx.Store.Ready or ctx.Store:Get("global.TradingHub.mode") == "hub" then
					return
				end
				built = true
				layout = Museum.Layout(Config)
				pool = Museum.newPool(M.maxModels, function(model)
					model:Destroy()
				end)
				buildHall()
				readCodex()
				table.insert(connections, ctx.Store:Observe("profile.Monsters.codex", readCodex))
				table.insert(
					connections,
					ctx.Store:Observe("profile.Settings", function(settings)
						local low = type(settings) == "table" and settings.lowGraphics == true
						if low ~= lowGraphics then
							lowGraphics = low
							pool:Clear() -- spare models were built with the other particle setting
						end
					end)
				)
			end
			step()
		end)
	)
end

-- Tests: live 3D models, spare models in the pool, and pedestals built.
function CodexMuseum.Stats(): (number, number, number)
	local live = 0
	for _, ped in pedestals do
		if ped.model then
			live += 1
		end
	end
	return live, if pool then pool:Size() else 0, #pedestals
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function CodexMuseum.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if pool then
		pool:Clear()
	end
	table.clear(pedestals)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return CodexMuseum
