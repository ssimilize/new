--[[
	ViewportMonster (C2): a ViewportFrame that shows one Visuals model (monster or egg),
	framed automatically, with optional slow spin. Used by the hatch reveal and MonsterDetail.

		local vm = ViewportMonster.new({ Size = UDim2.fromOffset(260, 260), Parent = card, Spin = 0.6 })
		vm:SetAppearance(Appearance.Of(monster))   -- or vm:SetEgg("crystal")
		vm:SetYaw(rad) / vm:SetRoll(rad) / vm:SetZoom(mult) / vm:SetSpin(radPerSecond)
		vm:Clear()  vm:Destroy()

	Only Visuals builders are used, so real art replaces the placeholders automatically. Monsters
	are built without particle effects (vfx = false): a ViewportFrame does not render particles.
	The spin loop skips work while the frame (or any ancestor) is hidden.
]]

local RunService = game:GetService("RunService")

local Visuals = script.Parent.Parent.Parent.Visuals
local MonsterModel = require(Visuals.MonsterModel)
local EggModel = require(Visuals.EggModel)

local ViewportMonster = {}
ViewportMonster.__index = ViewportMonster

local function shown(gui: Instance): boolean
	local node: Instance? = gui
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

function ViewportMonster.new(props: {
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	Spin: number?,
	ZIndex: number?,
	Name: string?,
})
	local self = setmetatable({}, ViewportMonster)
	local vp = Instance.new("ViewportFrame")
	vp.Name = props.Name or "ViewportMonster"
	vp.BackgroundTransparency = 1
	vp.Size = props.Size or UDim2.fromOffset(240, 240)
	vp.Position = props.Position or UDim2.new()
	vp.AnchorPoint = props.AnchorPoint or Vector2.zero
	vp.ZIndex = props.ZIndex or 1
	vp.Ambient = Color3.fromRGB(190, 190, 190)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-0.6, -1, 0.8)

	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.Parent = vp
	vp.CurrentCamera = camera

	self.Root = vp
	self.Camera = camera
	self._yaw = 0
	self._roll = 0
	self._zoom = 1
	self._spin = props.Spin or 0
	self._model = nil
	self._center = Vector3.zero
	self._radius = 2

	self._conn = RunService.RenderStepped:Connect(function(dt)
		if self._spin ~= 0 and self._model and shown(vp) then
			self._yaw = (self._yaw + self._spin * dt) % (math.pi * 2)
			self:_pose()
		end
	end)
	vp.Destroying:Connect(function()
		if self._conn then
			self._conn:Disconnect()
			self._conn = nil
		end
	end)
	if props.Parent then
		vp.Parent = props.Parent
	end
	return self
end

function ViewportMonster:_pose()
	if not self._model then
		return
	end
	-- Rotate around the model's visual centre so spins and wobbles stay in frame.
	local c = self._center
	local pivot = CFrame.new(c) * CFrame.Angles(0, self._yaw, 0) * CFrame.Angles(0, 0, self._roll) * CFrame.new(-c)
	self._model:PivotTo(pivot)
end

function ViewportMonster:_frame()
	local fov = math.rad(self.Camera.FieldOfView)
	local distance = (self._radius / math.tan(fov / 2)) * 1.15 * self._zoom
	local eye = self._center + Vector3.new(0, self._radius * 0.25, -distance)
	self.Camera.CFrame = CFrame.lookAt(eye, self._center)
end

function ViewportMonster:_use(model: Model)
	self:Clear()
	model:PivotTo(CFrame.new())
	local cf, size = model:GetBoundingBox()
	self._center = cf.Position
	self._radius = math.max(size.X, size.Y, size.Z) * 0.55
	self._model = model
	model.Parent = self.Root
	self:_pose()
	self:_frame()
end

function ViewportMonster:SetAppearance(appearance)
	local ok, model = pcall(MonsterModel.Build, appearance, { anchored = true, vfx = false }) -- particles do not render here
	if ok and model then
		self:_use(model)
	else
		warn("[ViewportMonster] could not build monster: " .. tostring(model))
		self:Clear()
	end
end

function ViewportMonster:SetEgg(eggType: string)
	local ok, model = pcall(EggModel.Build, eggType, { anchored = true })
	if ok and model then
		self:_use(model)
	else
		self:Clear()
	end
end

function ViewportMonster:SetYaw(rad: number)
	self._yaw = rad
	self:_pose()
end

function ViewportMonster:SetRoll(rad: number)
	self._roll = rad
	self:_pose()
end

function ViewportMonster:SetZoom(mult: number)
	self._zoom = math.max(0.2, mult)
	self:_frame()
end

function ViewportMonster:SetSpin(radPerSecond: number)
	self._spin = radPerSecond
end

function ViewportMonster:HasModel(): boolean
	return self._model ~= nil
end

function ViewportMonster:Clear()
	if self._model then
		self._model:Destroy()
		self._model = nil
	end
	self._yaw, self._roll = 0, 0
end

function ViewportMonster:Destroy()
	self:Clear()
	self.Root:Destroy()
end

return ViewportMonster
