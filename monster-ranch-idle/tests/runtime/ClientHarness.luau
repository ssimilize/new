--[[
	ClientHarness: runs the REAL client (src/client, booted through Main.client.luau) inside
	RobloxMock, connected to a REAL server kernel from TestKernel.

		local h = TestKernel.new({ systems = ALL })
		local player = h:Join()
		local c = ClientHarness.new(h, player)     -- builds the world, boots the client
		c:Advance(2)                               -- server and client move together
		c:Open("EggShop")                          -- Router:Open in a game thread
		c:Click(c:Button("Buy", c:Screen("EggShop")))
		c:UseGamepad(true)                         -- plug a pad in (false: back to touch)
		c:Press("ButtonB")  c:Stick(-1, 0)         -- pad or keyboard keys; left stick
		c:Selected()                               -- GuiService.SelectedObject
		expect(c.world.errors).toEqual({})

	Transport follows Roblox's remote rules: payloads are copied, and tables are checked
	for shapes Roblox would mangle (mixed keys, sparse arrays, non-string keys), which are
	reported in c.transportIssues.

	The world geometry comes from the server's own builder (Systems/World/Build.luau), run
	in the client world, so every part it creates is checked by the mock too.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local RobloxMock = require("./RobloxMock")

local ClientHarness = {}
ClientHarness.__index = ClientHarness

local ROOT = nil
local FILES = {}
local DIRS = {}

local function scan(path: string)
	local entries = fs.readDir(path)
	table.sort(entries)
	DIRS[path] = entries
	for _, entry in entries do
		local full = path .. "/" .. entry
		if fs.isDir(full) then
			scan(full)
		elseif string.match(entry, "%.luau$") then
			FILES[full] = fs.readFile(full)
		end
	end
end

function ClientHarness.init(root: string)
	if ROOT == root then
		return
	end
	ROOT = root
	scan(root .. "/src")
end

-- ─── Source tree → ModuleScript instances ───────────────────────────────────────────

local function stripName(file: string): (string?, string?)
	local base = string.match(file, "^(.+)%.server%.luau$")
	if base then
		return base, "Script"
	end
	base = string.match(file, "^(.+)%.client%.luau$")
	if base then
		return base, "LocalScript"
	end
	base = string.match(file, "^(.+)%.luau$")
	if base then
		return base, "ModuleScript"
	end
	return nil, nil
end

local function mountTree(world, path: string, name: string, parent)
	local Instance = world:InstanceLibrary()
	local isModuleFolder = FILES[path .. "/init.luau"] ~= nil
	local node = Instance.new(if isModuleFolder then "ModuleScript" else "Folder")
	node.Name = name
	if isModuleFolder then
		RobloxMock.records[node].extra.source = path .. "/init.luau"
	end
	for _, entry in DIRS[path] or {} do
		local full = path .. "/" .. entry
		if DIRS[full] then
			mountTree(world, full, entry, node)
		else
			local childName, className = stripName(entry)
			if childName and childName ~= "init" and className then
				local child = Instance.new(className)
				child.Name = childName
				RobloxMock.records[child].extra.source = full
				child.Parent = node
			end
		end
	end
	node.Parent = parent
	return node
end

-- ─── Remote copy (Roblox argument rules) ────────────────────────────────────────────

local function remoteCopy(value, path: string, issues)
	local t = typeof(value)
	if t == "function" or t == "thread" then
		table.insert(issues, path .. ": " .. t .. " cannot be sent over a remote")
		return nil
	end
	if t ~= "table" then
		if t == "number" and (value ~= value or value == math.huge or value == -math.huge) then
			table.insert(issues, path .. ": non-finite number " .. tostring(value))
		end
		return value
	end
	if RobloxMock.isInstance(value) then
		return value
	end
	if getmetatable(value) ~= nil then
		table.insert(issues, path .. ": metatables are dropped by remotes")
	end
	local count, stringKeys, numberKeys, maxIndex = 0, 0, 0, 0
	for k in value do
		count += 1
		if type(k) == "string" then
			stringKeys += 1
		elseif type(k) == "number" then
			numberKeys += 1
			if k == math.floor(k) and k > 0 then
				maxIndex = math.max(maxIndex, k)
			end
		else
			table.insert(issues, path .. ": key of type " .. typeof(k) .. " is not allowed")
		end
	end
	local out = {}
	if numberKeys > 0 and stringKeys > 0 then
		table.insert(issues, path .. ": mixed table (number and string keys); Roblox drops part of it")
	elseif numberKeys > 0 and maxIndex ~= numberKeys then
		table.insert(issues, path .. ": sparse array (holes or non-integer keys); Roblox truncates it at the first nil")
	end
	for k, v in value do
		out[k] = remoteCopy(v, path .. "." .. tostring(k), issues)
	end
	return out
end
ClientHarness.remoteCopy = remoteCopy

-- ─── Harness ────────────────────────────────────────────────────────────────────────

--[[
	options = {
	  viewport = Vector2?,        -- default 1280×720 (use 568×320 for a small phone)
	  touch = boolean?,           -- TouchEnabled (default true)
	  noBoot = boolean?,          -- build the world but do not run Main.client.luau
	  localeId = string?,         -- Player.LocaleId (default "en-us"), e.g. "es-mx", "pt-br"
	}
]]
function ClientHarness.new(testKernel, player, options)
	assert(ROOT, "ClientHarness.init(root) first")
	options = options or {}
	local self = setmetatable({}, ClientHarness)
	self.server = testKernel
	self.player = player
	self.transportIssues = {}
	self.events = {}
	self._modules = {}
	self._loading = {}

	local adapters = testKernel.adapters
	local issues = self.transportIssues
	local world
	world = RobloxMock.newWorld({
		clock = adapters.Clock.Unix,
		viewport = options.viewport,
		bridge = {
			invokeServer = function(name, ...)
				if name ~= "Request" then
					error("unknown RemoteFunction " .. tostring(name))
				end
				local action, payload = ...
				action = remoteCopy(action, "InvokeServer#1", issues)
				payload = remoteCopy(payload, "InvokeServer(" .. tostring(action) .. ")", issues)
				self.requests = self.requests or {}
				table.insert(self.requests, action)
				local response = testKernel.kernel.Net:Invoke(player, action, payload)
				if not response.ok then
					self.failedRequests = self.failedRequests or {}
					table.insert(self.failedRequests, tostring(action) .. ": " .. tostring(response.err))
				end
				return remoteCopy(response, "response(" .. tostring(action) .. ")", issues)
			end,
			fireServer = function(name)
				error("client fired RemoteEvent " .. tostring(name) .. "; the kernel only uses the Request function")
			end,
		},
	})
	self.world = world
	self.globals = world:Globals()
	self.Instance = self.globals.Instance

	local game = world.game
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	RobloxMock.rawSet(UserInputService, "TouchEnabled", options.touch ~= false)
	RobloxMock.rawSet(UserInputService, "KeyboardEnabled", options.touch == false)
	RobloxMock.rawSet(UserInputService, "MouseEnabled", options.touch == false)

	-- Shared code and remotes
	mountTree(world, ROOT .. "/src/shared", "Shared", ReplicatedStorage)
	local remotes = self.Instance.new("Folder")
	remotes.Name = "KernelRemotes"
	local request = self.Instance.new("RemoteFunction")
	request.Name = "Request"
	request.Parent = remotes
	for _, name in { "Event", "State" } do
		local remote = self.Instance.new("RemoteEvent")
		remote.Name = name
		RobloxMock.records[remote].queueEvents = { OnClientEvent = true }
		remote.Parent = remotes
	end
	remotes.Parent = ReplicatedStorage
	self.remotes = remotes

	-- Local player
	local lp = RobloxMock.newInstance(world, "Player")
	RobloxMock.rawSet(lp, "Name", player.Name)
	RobloxMock.rawSet(lp, "DisplayName", player.DisplayName or player.Name)
	RobloxMock.rawSet(lp, "UserId", player.UserId)
	RobloxMock.rawSet(lp, "LocaleId", options.localeId or "en-us")
	world.localPlayer = lp
	local playerGui = RobloxMock.newInstance(world, "PlayerGui")
	RobloxMock.rawSet(playerGui, "Name", "PlayerGui")
	RobloxMock.rawSet(playerGui, "Parent", lp)
	local playerScripts = RobloxMock.newInstance(world, "PlayerScripts")
	RobloxMock.rawSet(playerScripts, "Name", "PlayerScripts")
	RobloxMock.rawSet(playerScripts, "Parent", lp)
	RobloxMock.rawSet(lp, "Parent", Players)
	self.localPlayer = lp
	self.playerGui = playerGui

	-- World geometry from the server builder
	self:_buildWorld()
	self:_spawnCharacter()

	-- Client scripts
	self.clientFolder = mountTree(world, ROOT .. "/src/client", "Client", playerScripts)

	-- Server → client delivery (async, in order), including anything sent before we attached.
	local function deliver(kind: string, a, b)
		local remote = remotes:FindFirstChild(if kind == "state" then "State" else "Event")
		if kind == "state" then
			local message = remoteCopy(a, "state", issues)
			world.sched:defer(function()
				RobloxMock.fire(remote, "OnClientEvent", message)
			end)
		else
			table.insert(self.events, { name = a, payload = b })
			local payload = remoteCopy(b, "event(" .. tostring(a) .. ")", issues)
			world.sched:defer(function()
				RobloxMock.fire(remote, "OnClientEvent", a, payload)
			end)
		end
	end
	for _, message in adapters.log.states[player] or {} do
		deliver("state", message)
	end
	for _, e in adapters.log.events[player] or {} do
		deliver("event", e.name, e.payload)
	end
	adapters.clients = adapters.clients or {}
	adapters.clients[player] = deliver

	testKernel._clientHarnesses = testKernel._clientHarnesses or {}
	table.insert(testKernel._clientHarnesses, self)

	if not options.noBoot then
		self:Boot()
	end
	return self
end

function ClientHarness:require(moduleScript)
	local rec = RobloxMock.records[moduleScript]
	if not rec or rec.class.Name ~= "ModuleScript" then
		error("Attempted to call require with invalid argument(s).", 2)
	end
	local path = rec.extra.source
	assert(path, "ModuleScript has no source: " .. moduleScript:GetFullName())
	if self._modules[path] ~= nil then
		return self._modules[path]
	end
	if self._loading[path] then
		error("Requested module was required recursively: " .. path, 2)
	end
	self._loading[path] = true
	local result = self:_run(moduleScript, path)
	self._loading[path] = nil
	if result == nil then
		error("Module code did not return exactly one value: " .. path, 2)
	end
	self._modules[path] = result
	return result
end

function ClientHarness:_env(scriptInstance)
	local env = table.clone(self.globals)
	env.script = scriptInstance
	env.require = function(target)
		return self:require(target)
	end
	return env
end

function ClientHarness:_run(scriptInstance, path: string)
	local chunk = luau.load(FILES[path], {
		debugName = string.sub(path, #ROOT + 2),
		environment = self:_env(scriptInstance),
	})
	return chunk()
end

function ClientHarness:_buildWorld()
	local world = self.world
	local folder = self.Instance.new("Folder")
	folder.Name = "ServerOnly"
	local build = self.Instance.new("ModuleScript")
	build.Name = "Build"
	RobloxMock.records[build].extra.source = ROOT .. "/src/server/Systems/World/Build.luau"
	build.Parent = folder
	local Config = self:require(world.game:GetService("ReplicatedStorage").Shared.Config)
	local Build = self:require(build)
	local adapters = self.server.adapters
	local worldFolder = Build.world(Config, Config.TradingHub.Mode(adapters.PlaceId, adapters.PlaceMode))
	worldFolder.Parent = world.workspace
	self.Config = Config
	self.Build = Build
end

function ClientHarness:_spawnCharacter()
	local Instance = self.Instance
	local character = Instance.new("Model")
	character.Name = self.player.Name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = roblox.Vector3.new(2, 2, 1)
	root.Anchored = true
	root.CFrame = roblox.CFrame.new(0, 5, 0)
	root.Parent = character
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	character.PrimaryPart = root
	character.Parent = self.world.workspace
	RobloxMock.rawSet(self.localPlayer, "Character", character)
	self.character = character
	RobloxMock.fire(self.localPlayer, "CharacterAdded", character)
end

-- Runs Main.client.luau, capturing the client kernel it creates.
function ClientHarness:Boot()
	local kernelModule = self:require(self.clientFolder.Kernel.ClientKernel)
	local originalNew = kernelModule.new
	kernelModule.new = function(...)
		local k = originalNew(...)
		self.kernel = k
		return k
	end
	local main = self.clientFolder:FindFirstChild("Main")
	assert(main and main:IsA("LocalScript"), "Main.client.luau not found")
	self.world:Run(function()
		self:_run(main, RobloxMock.records[main].extra.source)
	end)
	kernelModule.new = originalNew
	self:Settle()
end

-- Runs deferred work and one short frame, without moving the server clock.
function ClientHarness:Settle()
	self.world.sched:runDeferred()
	self.world:Frame(0)
end

-- Moves server and client time together in frames of `dt` seconds (default 0.1).
function ClientHarness:Advance(seconds: number, dt: number?)
	local server = self.server
	local adapters = server.adapters
	local worlds = server._clientHarnesses
	local frame = dt or 0.1
	local remaining = seconds
	local sinceServerStep = 0
	while remaining > 1e-9 do
		local step = math.min(frame, remaining)
		adapters.advance(step)
		sinceServerStep += step
		remaining -= step
		if sinceServerStep >= 1 - 1e-9 or remaining <= 1e-9 then
			sinceServerStep = 0
			if adapters._step then
				adapters._step()
			end
		end
		for _, harness in worlds do
			harness.world:Frame(step)
		end
	end
	server.kernel.State:FlushAll()
	for _, harness in worlds do
		harness:Settle()
	end
end

-- ─── Queries and input ──────────────────────────────────────────────────────────────

function ClientHarness:Descendants(root)
	return (root or self.playerGui):GetDescendants()
end

-- True when the GuiObject and every GuiObject/LayerCollector ancestor is visible/enabled.
function ClientHarness:IsShown(gui): boolean
	local cursor = gui
	while cursor and cursor ~= self.playerGui do
		if cursor:IsA("GuiObject") and not cursor.Visible then
			return false
		end
		if cursor:IsA("LayerCollector") and not cursor.Enabled then
			return false
		end
		cursor = cursor.Parent
	end
	return cursor == self.playerGui
end

function ClientHarness:Buttons(root, shownOnly: boolean?)
	local list = {}
	for _, d in self:Descendants(root) do
		if d:IsA("GuiButton") and (shownOnly == false or self:IsShown(d)) then
			table.insert(list, d)
		end
	end
	return list
end

local function buttonText(button): string
	if button:IsA("TextButton") and button.Text ~= "" then
		return button.Text
	end
	for _, d in button:GetDescendants() do
		if d:IsA("TextLabel") and d.Text ~= "" then
			return d.Text
		end
	end
	return ""
end
ClientHarness.buttonText = buttonText

-- Finds a shown button whose text contains `text` (plain match).
function ClientHarness:Button(text: string, root)
	for _, b in self:Buttons(root) do
		if string.find(buttonText(b), text, 1, true) then
			return b
		end
	end
	return nil
end

function ClientHarness:Texts(root): { string }
	local list = {}
	for _, d in self:Descendants(root) do
		if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and d.Text ~= "" and self:IsShown(d) then
			table.insert(list, d.Text)
		end
	end
	return list
end

function ClientHarness:HasText(text: string, root): boolean
	for _, t in self:Texts(root) do
		if string.find(t, text, 1, true) then
			return true
		end
	end
	return false
end

function ClientHarness:Click(button)
	assert(button ~= nil, "Click: no button")
	RobloxMock.fire(button, "MouseButton1Down")
	RobloxMock.fire(button, "MouseButton1Up")
	RobloxMock.fire(button, "Activated", nil, 1)
	RobloxMock.fire(button, "MouseButton1Click")
	self:Settle()
end

function ClientHarness:Type(box, text: string, enter: boolean?)
	box.Text = text
	RobloxMock.fire(box, "FocusLost", enter == true, nil)
	self:Settle()
end

function ClientHarness:Trigger(prompt)
	RobloxMock.fire(prompt, "Triggered", self.localPlayer)
	self:Settle()
end

-- ─── Gamepad (update 3.2) ───────────────────────────────────────────────────────────
-- A small stand-in for the engine's pad handling: the device state in world.input, the
-- ContextActionService bindings, and GUI navigation (A presses GuiService.SelectedObject, the
-- D-pad moves it). Navigation follows tree order rather than on-screen geometry, because the
-- mock's layout pass ignores list and grid layouts; it honours Selectable, visibility and
-- SelectionGroup + SelectionBehavior* = Stop, which is what scoping relies on.

local Enum = roblox.Enum
local NAV = { DPadUp = -1, DPadLeft = -1, DPadDown = 1, DPadRight = 1 }
local NAV_SIDE = { DPadUp = "Up", DPadLeft = "Left", DPadDown = "Down", DPadRight = "Right" }

function ClientHarness:_setLastInput(kind)
	local state = self.world.input
	if state.lastType ~= kind then
		state.lastType = kind
		RobloxMock.fire(self.world.game:GetService("UserInputService"), "LastInputTypeChanged", kind)
	end
end

-- Plugs a pad in and makes it the last input (on), or unplugs it and touches the screen (off).
function ClientHarness:UseGamepad(on: boolean)
	local state = self.world.input
	local uis = self.world.game:GetService("UserInputService")
	local pad = Enum.UserInputType.Gamepad1
	local plugged = #state.gamepads > 0 -- the harness only ever plugs in Gamepad1
	if on and not plugged then
		table.insert(state.gamepads, pad)
		RobloxMock.fire(uis, "GamepadConnected", pad)
	elseif not on and plugged then
		table.clear(state.gamepads)
		RobloxMock.fire(uis, "GamepadDisconnected", pad)
	end
	self:_setLastInput(if on then pad else Enum.UserInputType.Touch)
	self:Settle()
end

function ClientHarness:Selected()
	return self.world.game:GetService("GuiService").SelectedObject
end

function ClientHarness:_navigate(side: string, step: number)
	local gs = self.world.game:GetService("GuiService")
	local from = gs.SelectedObject
	local scope = self.playerGui
	local cursor = from.Parent
	while cursor and cursor ~= self.playerGui do
		if cursor:IsA("GuiBase2d") and cursor.SelectionGroup and cursor["SelectionBehavior" .. side] == Enum.SelectionBehavior.Stop then
			scope = cursor
			break
		end
		cursor = cursor.Parent
	end
	local list = {}
	for _, d in scope:GetDescendants() do
		if d:IsA("GuiObject") and d.Selectable and self:IsShown(d) then
			table.insert(list, d)
		end
	end
	local at = table.find(list, from)
	local target = if at then list[at + step] else list[1]
	if target then
		gs.SelectedObject = target
	end
end

-- One engine input phase: ContextActionService first, then GUI navigation, then
-- UserInputService (which always sees the input; `processed` tells it someone used it).
function ClientHarness:_input(keyCode, state, kind)
	local world = self.world
	local input = RobloxMock.newInput(world, { KeyCode = keyCode, UserInputType = kind, UserInputState = state })
	local bound = {}
	for _, action in world.input.actions do
		for _, item in action.inputs do
			if item == keyCode or item == kind then -- EnumItems compare by ==, not identity
				table.insert(bound, action)
				break
			end
		end
	end
	table.sort(bound, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.order > b.order
	end)
	local processed = false
	for _, action in bound do
		local result
		world:Run(function()
			result = action.fn(action.name, state, input)
		end)
		if result == nil or result == Enum.ContextActionResult.Sink then
			processed = true
			break
		end
	end
	local gs = world.game:GetService("GuiService")
	local selected = gs.SelectedObject
	if not processed and selected and gs.GuiNavigationEnabled then
		if keyCode == Enum.KeyCode.ButtonA then
			processed = true
			if state == Enum.UserInputState.Begin and selected:IsA("GuiButton") then
				RobloxMock.fire(selected, "Activated", input, 1)
				RobloxMock.fire(selected, "MouseButton1Click")
			end
		elseif NAV[keyCode.Name] then
			processed = true
			if state == Enum.UserInputState.Begin then
				self:_navigate(NAV_SIDE[keyCode.Name], NAV[keyCode.Name])
			end
		end
	end
	RobloxMock.fire(
		world.game:GetService("UserInputService"),
		if state == Enum.UserInputState.Begin then "InputBegan" else "InputEnded",
		input,
		processed
	)
	world.sched:runDeferred()
end

-- Presses and releases a key: a pad button ("ButtonB", Enum.KeyCode.DPadDown) or a keyboard key.
function ClientHarness:Press(key)
	local keyCode = if type(key) == "string" then Enum.KeyCode[key] else key
	local name = keyCode.Name
	local kind = if string.sub(name, 1, 6) == "Button" or string.sub(name, 1, 4) == "DPad"
		then Enum.UserInputType.Gamepad1
		else Enum.UserInputType.Keyboard
	self:_setLastInput(kind)
	self:_input(keyCode, Enum.UserInputState.Begin, kind)
	self:_input(keyCode, Enum.UserInputState.End, kind)
	self:Settle()
end

-- Moves the left stick to (x, y), each -1..1 (InputChanged, as the engine reports it).
function ClientHarness:Stick(x: number, y: number)
	local pad = Enum.UserInputType.Gamepad1
	self:_setLastInput(pad)
	local input = RobloxMock.newInput(self.world, {
		KeyCode = Enum.KeyCode.Thumbstick1,
		UserInputType = pad,
		UserInputState = Enum.UserInputState.Change,
		Position = roblox.Vector3.new(x, y, 0),
	})
	RobloxMock.fire(self.world.game:GetService("UserInputService"), "InputChanged", input, false)
	self:Settle()
end

function ClientHarness:Screen(name: string)
	local router = self.kernel.Router
	local screen = router._screens[name]
	return screen and screen.Root
end

function ClientHarness:Open(name: string, params: any?)
	self.world:Run(function()
		self.kernel.Router:Open(name, params)
	end)
	self:Settle()
	return self:Screen(name)
end

function ClientHarness:Close(name: string?)
	self.world:Run(function()
		self.kernel.Router:Close(name)
	end)
	self:Settle()
end

-- Calls ctx.Net:Request from a game thread (as a screen would) and returns ok, data.
function ClientHarness:Request(action: string, payload: any?)
	local ok, result
	self.world:Run(function()
		ok, result = self.kernel.Net:Request(action, payload)
	end)
	self:Settle()
	return ok, result
end

function ClientHarness:Store(path: string)
	return self.kernel.Store:Get(path)
end

-- Errors and warnings that indicate bugs (ignores warnings listed in `allow` patterns).
function ClientHarness:Problems(allow: { string }?)
	local list = {}
	for _, e in self.world.errors do
		table.insert(list, "error: " .. e)
	end
	for _, w in self.world.warnings do
		local allowed = false
		for _, pattern in allow or {} do
			if string.find(w, pattern) then
				allowed = true
			end
		end
		if not allowed then
			table.insert(list, "warn: " .. w)
		end
	end
	for _, issue in self.transportIssues do
		table.insert(list, "transport: " .. issue)
	end
	return list
end

function ClientHarness:ClearProblems()
	table.clear(self.world.errors)
	table.clear(self.world.warnings)
	table.clear(self.transportIssues)
end

return ClientHarness
