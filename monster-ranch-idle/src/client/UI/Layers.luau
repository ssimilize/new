--[[
	Layers: the root ScreenGui and four scaled layers.

	Everything is designed at DESIGN_SIZE (1100 × 560, a landscape phone). Each layer is
	sized to viewport / scale and scaled back with a UIScale, so offsets in design units
	look the same on every screen, and Scale-based sizes still fill the screen.

	  Hud      always-on HUD (currencies, side buttons)
	  Screens  menus opened by the Router (with the dim background)
	  Overlay  toasts, broadcasts, tutorial arrows
	  Top      reward popups, hatch reveals, level-up banners
]]

local Layers = {}

Layers.DESIGN_SIZE = Vector2.new(1100, 560)
Layers.MIN_SCALE = 0.55
Layers.MAX_SCALE = 1.6

function Layers.scaleFor(viewport: Vector2): number
	local s = math.min(viewport.X / Layers.DESIGN_SIZE.X, viewport.Y / Layers.DESIGN_SIZE.Y)
	return math.clamp(s, Layers.MIN_SCALE, Layers.MAX_SCALE)
end

function Layers.create(player)
	local gui = Instance.new("ScreenGui")
	gui.Name = "MonsterRanchUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = player:WaitForChild("PlayerGui")

	local layers = { Gui = gui, Scale = 1 }
	local scales = {}
	for i, name in { "Hud", "Screens", "Overlay", "Top" } do
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.BackgroundTransparency = 1
		frame.ZIndex = i * 10
		frame.Parent = gui
		local uiScale = Instance.new("UIScale")
		uiScale.Parent = frame
		scales[name] = uiScale
		layers[name] = frame
	end

	local function resize()
		-- The ScreenGui already excludes notches and system bars (DeviceSafeInsets).
		local usable = gui.AbsoluteSize
		if usable.X <= 0 or usable.Y <= 0 then
			return
		end
		local s = Layers.scaleFor(usable)
		layers.Scale = s
		for name, uiScale in scales do
			uiScale.Scale = s
			layers[name].Size = UDim2.fromOffset(usable.X / s, usable.Y / s)
		end
	end
	resize()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	return layers
end

return Layers
