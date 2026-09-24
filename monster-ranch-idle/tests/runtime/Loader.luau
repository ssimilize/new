--[[
	Loader: runs Roblox-style code (instance-based `require(script.Parent.X)`,
	`game:GetService("ReplicatedStorage").Shared`) inside Lune, straight from the Rojo
	source tree. It builds lightweight "instance proxies" over the filesystem using Rojo's
	naming rules:
	  folder/                 → Folder (or ModuleScript if it has init.luau)
	  Name.luau               → ModuleScript "Name"
	  Name.server.luau        → Script "Name"      (never required)
	  Name.client.luau        → LocalScript "Name" (never required)

	Only what server/shared code needs is emulated: Name, Parent, FindFirstChild,
	WaitForChild, GetChildren, IsA, GetFullName and child access by name.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local Loader = {}

local ROOT = "" -- set by Loader.init
local MOUNTS = {} -- service name -> { childName -> fs path }

local proxyCache = {}
local moduleCache = {}
local loading = {}

-- Lune's fs calls yield, and yielding is not allowed inside metamethods, so the whole
-- source tree is scanned once in Loader.init and every lookup afterwards is in memory.
local DIRS = {} -- path -> { entry names }
local FILES = {} -- path -> source

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

local function isDir(path: string): boolean
	return DIRS[path] ~= nil
end

local function isFile(path: string): boolean
	return FILES[path] ~= nil
end

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

local makeProxy

local function childrenOf(node)
	if node.children then
		return node.children
	end
	local children = {}
	if node.mountChildren then
		for name, path in node.mountChildren do
			children[name] = makeProxy(path, name, node.proxy, isDir(path) and "dir" or "file")
		end
	elseif node.kind == "dir" then
		for _, entry in DIRS[node.path] do
			local full = node.path .. "/" .. entry
			if isDir(full) then
				children[entry] = makeProxy(full, entry, node.proxy, "dir")
			else
				local name, className = stripName(entry)
				if name and name ~= "init" and className then
					children[name] = makeProxy(full, name, node.proxy, "file", className)
				end
			end
		end
	end
	node.children = children
	return children
end

local function className(node): string
	if node.className then
		return node.className
	end
	if node.kind == "dir" then
		if isFile(node.path .. "/init.luau") then
			return "ModuleScript"
		end
		return "Folder"
	end
	return "ModuleScript"
end

function makeProxy(path: string, name: string, parent, kind: string, cls: string?)
	local cacheKey = path .. "::" .. name
	if proxyCache[cacheKey] then
		return proxyCache[cacheKey]
	end
	local node = { path = path, name = name, parent = parent, kind = kind, className = cls }
	local proxy = setmetatable({}, {
		__index = function(_, key)
			if key == "Name" then
				return node.name
			elseif key == "Parent" then
				return node.parent
			elseif key == "ClassName" then
				return className(node)
			elseif key == "FindFirstChild" then
				return function(_, childName)
					return childrenOf(node)[childName]
				end
			elseif key == "WaitForChild" then
				return function(_, childName)
					local child = childrenOf(node)[childName]
					if not child then
						error(string.format("Infinite yield: %s is not a child of %s", childName, node.name), 2)
					end
					return child
				end
			elseif key == "GetChildren" then
				return function()
					local list = {}
					for _, child in childrenOf(node) do
						table.insert(list, child)
					end
					return list
				end
			elseif key == "IsA" then
				return function(_, cls)
					return className(node) == cls
				end
			elseif key == "GetFullName" then
				return function()
					return node.path
				end
			end
			local child = childrenOf(node)[key]
			if child == nil then
				error(string.format("%s is not a valid member of %s", tostring(key), node.name), 2)
			end
			return child
		end,
		__tostring = function()
			return node.name
		end,
	})
	node.proxy = proxy
	proxyCache[cacheKey] = proxy
	Loader._nodes[proxy] = node
	return proxy
end

Loader._nodes = setmetatable({}, { __mode = "k" })

local services = {}
local game

local function sourcePathOf(proxy): string
	local node = Loader._nodes[proxy]
	assert(node, "require expects a module proxy")
	if node.kind == "dir" then
		local init = node.path .. "/init.luau"
		assert(isFile(init), "folder is not a module: " .. node.path)
		return init
	end
	return node.path
end

local environmentExtras = {}

local function makeEnv(scriptProxy)
	local env = {
		script = scriptProxy,
		game = game,
		workspace = nil,
		task = task,
		require = Loader.require,
	}
	for k, v in environmentExtras do
		env[k] = v
	end
	return env
end

function Loader.require(proxy)
	if type(proxy) == "string" then
		error("string requires are not used in game code: " .. proxy, 2)
	end
	local path = sourcePathOf(proxy)
	if moduleCache[path] ~= nil then
		return moduleCache[path]
	end
	if loading[path] then
		error("cyclic require: " .. path, 2)
	end
	loading[path] = true
	local source = FILES[path]
	local chunk = luau.load(source, {
		debugName = string.sub(path, #ROOT + 2),
		environment = makeEnv(proxy),
	})
	local result = chunk()
	loading[path] = nil
	moduleCache[path] = result
	return result
end

-- Extra globals (e.g. warn capture) injected into every loaded module.
function Loader.setGlobal(name: string, value: any)
	environmentExtras[name] = value
end

function Loader.init(root: string)
	ROOT = root
	scan(root .. "/src")
	MOUNTS = {
		ReplicatedStorage = { Shared = root .. "/src/shared" },
		ServerScriptService = { Server = root .. "/src/server" },
	}
	game = setmetatable({}, {
		__index = function(_, key)
			if key == "GetService" then
				return function(_, name)
					if services[name] then
						return services[name]
					end
					local mount = MOUNTS[name]
					if not mount then
						error("GetService('" .. name .. "') is not available in Lune tests; go through ctx.Services", 2)
					end
					local proxy = makeProxy(root .. "/<" .. name .. ">", name, nil, "service")
					local node = Loader._nodes[proxy]
					node.mountChildren = mount
					services[name] = proxy
					return proxy
				end
			end
			error("game." .. tostring(key) .. " is not available in Lune tests", 2)
		end,
	})
	Loader.game = game
end

-- Convenience: require a module by dotted path from a mount, e.g. "Shared.Logic.Rng".
function Loader.get(path: string)
	local parts = string.split(path, ".")
	local node
	if parts[1] == "Shared" then
		node = game:GetService("ReplicatedStorage").Shared
	elseif parts[1] == "Server" then
		node = game:GetService("ServerScriptService").Server
	else
		error("unknown mount " .. parts[1])
	end
	for i = 2, #parts do
		node = node[parts[i]]
	end
	return Loader.require(node)
end

-- Syntax-checks one file (used by the lint script for client code too).
function Loader.compileCheck(path: string): (boolean, string?)
	local ok, err = pcall(luau.compile, FILES[path] or fs.readFile(path))
	if ok then
		return true, nil
	end
	return false, tostring(err)
end

return Loader
