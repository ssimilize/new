--[[
	Anim: UI motion helpers. All helpers are safe to call repeatedly and respect the
	"reduced motion" choice (Settings.lowGraphics) through Anim.enabled.
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Anim = {}
Anim.enabled = true

local function scaleOf(gui: GuiObject): UIScale
	local s = gui:FindFirstChild("AnimScale")
	if not s then
		s = Instance.new("UIScale")
		s.Name = "AnimScale"
		s.Parent = gui
	end
	return s :: UIScale
end
Anim.scaleOf = scaleOf

function Anim.tween(inst: Instance, props: { [string]: any }, time: number?, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local info = TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

-- Pops a panel in from 85% scale with a little overshoot.
function Anim.popIn(gui: GuiObject, time: number?)
	local s = scaleOf(gui)
	if not Anim.enabled then
		s.Scale = 1
		return
	end
	s.Scale = 0.85
	Anim.tween(s, { Scale = 1 }, time or 0.22, Enum.EasingStyle.Back)
end

function Anim.pressDown(gui: GuiObject)
	Anim.tween(scaleOf(gui), { Scale = 0.92 }, 0.06)
end

function Anim.pressUp(gui: GuiObject)
	Anim.tween(scaleOf(gui), { Scale = 1 }, 0.18, Enum.EasingStyle.Back)
end

function Anim.pulse(gui: GuiObject, amount: number?)
	if not Anim.enabled then
		return
	end
	local s = scaleOf(gui)
	s.Scale = 1 + (amount or 0.12)
	Anim.tween(s, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
end

function Anim.shake(gui: GuiObject)
	if not Anim.enabled then
		return
	end
	local origin = gui.Position
	task.spawn(function()
		for i = 1, 6 do
			local dx = (if i % 2 == 0 then 1 else -1) * (7 - i)
			gui.Position = origin + UDim2.fromOffset(dx, 0)
			task.wait(0.03)
		end
		gui.Position = origin
	end)
end

-- Counts a TextLabel from one number to another. `format` turns a number into text.
function Anim.countUp(label: TextLabel, from: number, to: number, time: number?, format: (number) -> string)
	if not Anim.enabled or from == to then
		label.Text = format(to)
		return
	end
	local duration = time or 0.5
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - start) / duration, 0, 1)
		local eased = 1 - (1 - alpha) ^ 3
		label.Text = format(from + (to - from) * eased)
		if alpha >= 1 then
			conn:Disconnect()
		end
	end)
end

-- Gentle infinite bob for attention (tutorial arrows, "READY!" badges). Returns a stop fn.
function Anim.bob(gui: GuiObject, pixels: number?)
	local origin = gui.Position
	local amplitude = pixels or 6
	local alive = true
	task.spawn(function()
		local t0 = os.clock()
		while alive and gui.Parent do
			if Anim.enabled then
				local y = math.sin((os.clock() - t0) * 4) * amplitude
				gui.Position = origin + UDim2.fromOffset(0, y)
			end
			RunService.RenderStepped:Wait()
		end
		if gui.Parent then
			gui.Position = origin
		end
	end)
	return function()
		alive = false
	end
end

return Anim
