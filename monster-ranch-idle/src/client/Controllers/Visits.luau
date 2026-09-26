--[[
	Visits controller (glow-up Y): the crown over the server's most-liked ranch, the Visiting
	Showcase and the Ranch of the Week stage. Server side: Systems/Visits; tuning Config.Visits.

	  Crown     global.Visits.crown = { userId, plot, likes, name }: a gold crown (neon points on a
	            ring, a warm PointLight) spinning above that plot's gate; it moves when the holder
	            changes and hides when nobody holds it.
	  Showcase  session.Visits.showcase (only this player's): the friend's ranch snapshot drawn by
	            Visuals/RanchShowcase at Config.Visits.Showcase.center, plus a HUD bar with the
	            owner's name, Like (Visits.Like), Go there (walks the character to the gate) and
	            Leave (Visits.Leave). Only this client draws it.
	  Stage     global.Visits.stage: last week's most-liked ranch on a stage north-west of the
	            Market Square, its showiest monsters on pedestals (models only within modelRange).
	Nothing is built in the hub place.

	  Visits.Visit(userId, name)   -- Friends screen "Visit ranch": here -> toast with the plot,
	                               -- teleport -> after teleportWaitSeconds still here -> snapshot
	  Visits.Stats() -> { crownPlot, showcaseOwner, showcaseMonsters, stageMonsters }  (tests)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local Client = script.Parent.Parent
local MonsterModel = require(Client.Visuals.MonsterModel)
local RanchShowcase = require(Client.Visuals.RanchShowcase)
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)
local Button = require(Client.UI.Components.Button)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Visits
local W = Config.World

local Visits = {
	Name = "Visits",
	Dependencies = {},
}

local ctx
local connections = {}
local crown = { model = nil :: Model?, plot = 0, angle = 0, base = nil :: CFrame? }
local showcase = { model = nil :: Model?, owner = 0, monsters = 0 }
local stage = { folder = nil :: Folder?, models = {}, key = "", near = false, entry = nil, plate = nil :: TextLabel? }
local bar = { frame = nil :: Frame?, title = nil :: TextLabel? }
local retry = nil -- { userId, at } a snapshot request waiting on a teleport that may not happen
local elapsed = 0

local function isHub(): boolean
	return ctx.Store:Get("global.TradingHub.mode") == "hub"
end

local function toast(ok: boolean, res: any)
	if not ok then
		ctx:Toast(tostring(res), "error")
	end
end

-- Crown -----------------------------------------------------------------------------------------

local function gateTop(index: number): CFrame?
	local plot = W.Plots[index]
	if not plot then
		return nil
	end
	local world = workspace:FindFirstChild("World")
	local plots = world and world:FindFirstChild("Plots")
	local model = plots and plots:FindFirstChild("Plot" .. index)
	local gate = model and model:FindFirstChild("Gate")
	local sign = gate and gate:FindFirstChild("Sign")
	if sign and sign:IsA("BasePart") then
		return CFrame.new(sign.Position + Vector3.new(0, Cfg.Crown.height - 8, 0))
	end
	local c = plot.center
	local cf = CFrame.new(c[1], W.GroundY or 0, c[3]) * CFrame.Angles(0, math.rad((plot.facing or 0) - 90), 0)
	return CFrame.new((cf * CFrame.new(W.PlotSize[1] / 2 - 2, Cfg.Crown.height, 0)).Position)
end

local function buildCrown(): Model
	local model = Instance.new("Model")
	model.Name = "RanchCrown"
	local gold = Color3.fromHex(Cfg.Crown.color)
	local function piece(name: string, size: Vector3, cf: CFrame, neon: boolean): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.CFrame = cf
		p.Color = gold
		p.Material = if neon then Enum.Material.Neon else Enum.Material.Metal
		p.Parent = model
		return p
	end
	local core = piece("Core", Vector3.new(1, 1, 1), CFrame.new(), true)
	core.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex(Cfg.Crown.glow)
	light.Brightness = 3
	light.Range = 18
	light.Parent = core
	for i = 1, 10 do
		local a = (i - 1) / 10 * math.pi * 2
		piece("Band" .. i, Vector3.new(1.7, 1.2, 0.5), CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -2.6), false)
	end
	for i = 1, 5 do
		local a = (i - 1) / 5 * math.pi * 2
		piece(
			"Point" .. i,
			Vector3.new(0.8, 2.2, 0.8),
			CFrame.Angles(0, a, 0) * CFrame.new(0, 1.6, -2.6) * CFrame.Angles(0, 0, math.rad(45)),
			true
		)
	end
	model.PrimaryPart = core
	return model
end

local function syncCrown()
	local data = ctx.Store:Get("global.Visits.crown")
	local plot = if type(data) == "table" then tonumber(data.plot) or 0 else 0
	local at = if plot > 0 and not isHub() then gateTop(plot) else nil
	if not at then
		if crown.model then
			crown.model:Destroy()
			crown.model = nil
		end
		crown.plot = 0
		return
	end
	if not crown.model then
		crown.model = buildCrown()
		crown.model.Parent = workspace
	end
	crown.plot = plot
	crown.base = at
	crown.model:SetAttribute("Plot", plot)
	crown.model:SetAttribute("Owner", data.userId)
	crown.model:PivotTo(at * CFrame.Angles(0, crown.angle, 0))
end

-- Showcase --------------------------------------------------------------------------------------

local function showcaseOrigin(): CFrame
	local c = Cfg.Showcase.center
	return CFrame.new(c[1], (W.GroundY or 0) + c[2], c[3])
end

local function goThere()
	local character = ctx.Player.Character
	if not character then
		return
	end
	local at = showcaseOrigin() * CFrame.new(0, 4, -Cfg.Showcase.size[2] / 2 - 6)
	pcall(function()
		character:PivotTo(CFrame.lookAt(at.Position, showcaseOrigin().Position + Vector3.new(0, 4, 0)))
	end)
end

local function buildBar()
	local frame = New("Frame", {
		Name = "VisitBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -118),
		Size = UDim2.fromOffset(372, 92),
		BackgroundColor3 = C.Panel or Color3.fromRGB(30, 30, 40),
		BackgroundTransparency = 0.2,
		Visible = false,
		Parent = ctx.UI.Hud,
	})
	New("UICorner", { CornerRadius = UDim.new(0, 12), Parent = frame })
	bar.title = Create.Text({
		Text = "",
		TextSize = Theme.TextSize.Small + 1,
		Size = UDim2.new(1, -12, 0, 30),
		Position = UDim2.fromOffset(6, 2),
		Parent = frame,
	})
	local row = New("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(6, 36),
		Size = UDim2.new(1, -12, 0, 50),
		Parent = frame,
	})
	New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = row,
	})
	local function add(name: string, text: string, color: Color3, order: number, fn)
		Button.new({
			Name = name,
			Text = text,
			Color = color,
			Size = UDim2.fromOffset(116, 46),
			TextSize = Theme.TextSize.Small + 1,
			LayoutOrder = order,
			Parent = row,
			OnClick = fn,
		})
	end
	add("Like", "Like", C.Pink or C.Orange, 1, function()
		local ok, res = ctx.Net:Request("Visits.Like")
		if ok then
			ctx:Toast("You liked this ranch!", "success")
		end
		toast(ok, res)
	end)
	add("GoThere", "Go there", C.Blue, 2, goThere)
	add("Leave", "Leave", C.Gray, 3, function()
		local ok, res = ctx.Net:Request("Visits.Leave")
		toast(ok, res)
	end)
	bar.frame = frame
end

local function syncShowcase()
	local snap = ctx.Store:Get("session.Visits.showcase")
	local owner = if type(snap) == "table" then tonumber(snap.userId) or 0 else 0
	if owner == showcase.owner and (owner == 0 or showcase.model) then
		return
	end
	if showcase.model then
		showcase.model:Destroy()
		showcase.model = nil
	end
	showcase.owner = 0
	showcase.monsters = 0
	if bar.frame then
		bar.frame.Visible = false
	end
	if owner == 0 or isHub() then
		return
	end
	local ok, model, stats = pcall(RanchShowcase.Build, snap, showcaseOrigin(), { now = os.time() })
	if not ok or not model then
		return
	end
	model.Parent = workspace
	showcase.model = model
	showcase.owner = owner
	showcase.monsters = stats.monsters
	if not bar.frame then
		buildBar()
	end
	if bar.title then
		bar.title.Text = string.format("Visiting %s's ranch", tostring(snap.name or ""))
	end
	if bar.frame then
		bar.frame.Visible = true
	end
end

-- Ranch of the Week stage -------------------------------------------------------------------------

local function stageTop(): CFrame
	local c = Cfg.Stage.center
	return CFrame.new(c[1], (W.GroundY or 0) + c[2], c[3])
end

local function buildStage()
	local f = Instance.new("Folder")
	f.Name = "RanchOfTheWeek"
	local base = stageTop()
	local function block(name: string, size: Vector3, cf: CFrame, color: string, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = Color3.fromHex(color)
		p.Material = material
		p.CastShadow = false
		p.Parent = f
		return p
	end
	local sx, sz = Cfg.Stage.size[1], Cfg.Stage.size[2]
	block("Stage", Vector3.new(sx - 10, 1.4, sz - 12), base * CFrame.new(0, 0.7, 0), "#F3E3C3", Enum.Material.WoodPlanks)
	local back = block(
		"Backdrop",
		Vector3.new(sx - 14, 10, 0.8),
		base * CFrame.new(0, 6.4, (sz - 12) / 2 - 0.4),
		"#FF6FA8",
		Enum.Material.SmoothPlastic
	)
	local sign = New("SurfaceGui", { Face = Enum.NormalId.Front, CanvasSize = Vector2.new(400, 110), LightInfluence = 0, Parent = back })
	Create.Text({ Text = "Ranch of the Week", TextScaled = true, Size = UDim2.fromScale(1, 0.5), Parent = sign })
	local plate =
		Create.Text({ Text = "", TextScaled = true, Size = UDim2.fromScale(1, 0.45), Position = UDim2.fromScale(0, 0.52), Parent = sign })
	stage.plate = plate
	for i = 1, Cfg.Stage.maxMonsters do
		local x = (i - (Cfg.Stage.maxMonsters + 1) / 2) * 6
		local z = if i == math.ceil(Cfg.Stage.maxMonsters / 2) then -2 else 0
		block("Pedestal" .. i, Vector3.new(4, 1.2, 4), base * CFrame.new(x, 2, z), "#EDEAE4", Enum.Material.Marble)
	end
	f.Parent = workspace
	stage.folder = f
end

local function clearStageModels()
	for _, m in stage.models do
		m:Destroy()
	end
	table.clear(stage.models)
end

local function buildStageModels()
	local entry = stage.entry
	if not stage.folder or not entry or not stage.near or #stage.models > 0 then
		return
	end
	for i, appearance in entry.monsters or {} do
		local pedestal = stage.folder:FindFirstChild("Pedestal" .. i)
		if pedestal and pedestal:IsA("BasePart") then
			local ok, model = pcall(MonsterModel.Build, appearance, { anchored = true, vfx = false, scale = Cfg.Stage.scale })
			if ok and model then
				local height = tonumber(model:GetAttribute("Height")) or 3
				local at = pedestal.Position + Vector3.new(0, pedestal.Size.Y / 2 + height / 2, 0)
				model:PivotTo(CFrame.lookAt(at, at + Vector3.new(0, 0, -1)))
				model.Parent = stage.folder
				table.insert(stage.models, model)
			end
		end
	end
end

local function syncStage()
	if not stage.folder then
		return
	end
	local entry = ctx.Store:Get("global.Visits.stage")
	entry = if type(entry) == "table" then entry else nil
	local key = if entry then string.format("%s#%s", tostring(entry.userId), tostring(entry.week)) else ""
	if key == stage.key then
		return
	end
	stage.key = key
	stage.entry = entry
	clearStageModels()
	if stage.plate then
		stage.plate.Text = if entry then string.format("%s · %d likes", tostring(entry.name or ""), tonumber(entry.likes) or 0) else ""
	end
	buildStageModels()
end

-- Visiting --------------------------------------------------------------------------------------

function Visits.Visit(userId: number, name: string)
	local ok, res = ctx.Net:Request("Visits.Visit", { userId = userId })
	if not ok then
		toast(ok, res)
		return
	end
	if res.mode == "here" then
		ctx:Toast(string.format("%s is on this server: plot %d", name, tonumber(res.plot) or 0), "info")
	elseif res.mode == "teleport" then
		ctx:Toast("Taking you to your friend's server...", "info")
		retry = { userId = userId, name = name, at = elapsed + Cfg.Visit.teleportWaitSeconds }
	else
		ctx:Toast(string.format("Showing %s's ranch in the Visiting Showcase", name), "success")
		goThere()
	end
end

local function retrySnapshot()
	local r = retry
	retry = nil
	local ok, res = ctx.Net:Request("Visits.Visit", { userId = r.userId, snapshot = true })
	if ok and res.mode == "showcase" then
		ctx:Toast(string.format("Showing %s's ranch in the Visiting Showcase", r.name), "success")
		goThere()
	else
		toast(ok, res)
	end
end

-- Lifecycle -------------------------------------------------------------------------------------

function Visits.Init(context)
	ctx = context
end

function Visits.Start()
	local ready = false
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if crown.model and crown.base then
				crown.angle = (crown.angle + math.rad(Cfg.Crown.spin) * dt) % (math.pi * 2)
				local bob = math.sin(elapsed * 2) * 0.4
				crown.model:PivotTo(crown.base * CFrame.new(0, bob, 0) * CFrame.Angles(0, crown.angle, 0))
			end
			if retry and elapsed >= retry.at then
				retrySnapshot()
			end
			if not ready then
				if not ctx.Store.Ready or isHub() then
					return
				end
				ready = true
				buildStage()
				syncCrown()
				syncShowcase()
				syncStage()
				table.insert(
					connections,
					ctx.Store:Observe("global.Visits", function()
						syncCrown()
						syncStage()
					end)
				)
				table.insert(connections, ctx.Store:Observe("global.Plots", syncCrown))
				table.insert(connections, ctx.Store:Observe("session.Visits", syncShowcase))
			end
			local camera = workspace.CurrentCamera
			if camera then
				local at = camera.CFrame.Position
				local c = Cfg.Stage.center
				local dx, dz = at.X - c[1], at.Z - c[3]
				local near = dx * dx + dz * dz <= Cfg.Stage.modelRange * Cfg.Stage.modelRange
				if near ~= stage.near then
					stage.near = near
					if near then
						buildStageModels()
					else
						clearStageModels()
					end
				end
			end
		end)
	)
end

function Visits.Stats()
	return {
		crownPlot = crown.plot,
		showcaseOwner = showcase.owner,
		showcaseMonsters = showcase.monsters,
		stageMonsters = #stage.models,
		stageName = if stage.entry then stage.entry.name else nil,
	}
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function Visits.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	clearStageModels()
	for _, inst in { crown.model, showcase.model, stage.folder, bar.frame } do
		if inst then
			inst:Destroy()
		end
	end
	crown.model, showcase.model, stage.folder, bar.frame = nil, nil, nil, nil
end

return Visits
