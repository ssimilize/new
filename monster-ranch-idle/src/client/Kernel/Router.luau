--[[
	Router: opens and closes screens (menus). One modal screen is open at a time.

	A screen module (src/client/UI/Screens/<Name>.luau) returns:
	  {
	    Name = "EggShop",
	    Build = function(ctx) -> screen   -- called once, on first open
	  }
	where `screen` is:
	  {
	    Root = GuiObject,                 -- parented by the Router into UI.Screens
	    Open = function(params) end?,     -- every time it opens
	    Close = function() end?,          -- every time it closes
	    Modal = boolean?,                 -- default true (dims the world, closes other modals)
	  }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.Kernel.Signal)
local Anim = require(script.Parent.Parent.UI.Anim)

local Router = {}
Router.__index = Router

function Router.new(kernel)
	local self = setmetatable({
		_kernel = kernel,
		_modules = {},
		_screens = {},
		_current = nil,
		Opened = Signal.new(),
		Closed = Signal.new(),
	}, Router)

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BackgroundColor3 = Color3.fromRGB(10, 18, 14)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.Visible = false
	dim.ZIndex = 0
	dim.Parent = kernel.UI.Screens
	dim.Activated:Connect(function()
		self:Close()
	end)
	self._dim = dim
	return self
end

function Router:Register(module)
	assert(
		type(module) == "table" and type(module.Name) == "string" and type(module.Build) == "function",
		"screen modules need Name and Build"
	)
	self._modules[module.Name] = module
end

function Router:Has(name: string): boolean
	return self._modules[name] ~= nil
end

function Router:_get(name: string)
	local screen = self._screens[name]
	if screen then
		return screen
	end
	local module = self._modules[name]
	if not module then
		warn("[Router] no screen registered named " .. name)
		return nil
	end
	local ok, result = xpcall(module.Build, debug.traceback, self._kernel:ScreenContext(name))
	if not ok or type(result) ~= "table" or not result.Root then
		warn(string.format("[Router] %s.Build failed: %s", name, tostring(result)))
		return nil
	end
	result.Root.Visible = false
	result.Root.Parent = self._kernel.UI.Screens
	self._screens[name] = result
	return result
end

function Router:Open(name: string, params: any?)
	local screen = self:_get(name)
	if not screen then
		return
	end
	local modal = screen.Modal ~= false
	if modal and self._current and self._current ~= name then
		self._switching = true -- one open sound for a swap, not a close and an open
		self:Close(self._current)
		self._switching = false
	end
	if modal then
		self._current = name
		self._dim.Visible = true
	end
	-- Re-opening a visible screen (e.g. a world prompt while its menu is up) closes it
	-- first so its Open-time timers and watchers are not started twice.
	if screen.Root.Visible and screen.Close then
		screen.Close()
	end
	screen.Root.Visible = true
	Anim.popIn(screen.Root)
	if screen.Open then
		task.spawn(screen.Open, params)
	end
	self._kernel:Sound("UIOpen")
	self.Opened:Fire(name, params)
end

function Router:Close(name: string?)
	local target = name or self._current
	if not target then
		return
	end
	local screen = self._screens[target]
	if not screen or not screen.Root.Visible then
		return
	end
	screen.Root.Visible = false
	if screen.Close then
		task.spawn(screen.Close)
	end
	if self._current == target then
		self._current = nil
		self._dim.Visible = false
	end
	if not self._switching then
		self._kernel:Sound("UIClose")
	end
	self.Closed:Fire(target)
end

function Router:Toggle(name: string, params: any?)
	if self:IsOpen(name) then
		self:Close(name)
	else
		self:Open(name, params)
	end
end

function Router:IsOpen(name: string): boolean
	local screen = self._screens[name]
	return screen ~= nil and screen.Root.Visible
end

function Router:Current(): string?
	return self._current
end

-- The root of a screen that has been built (nil before its first open).
function Router:Root(name: string): GuiObject?
	local screen = self._screens[name]
	return screen and screen.Root
end

return Router
