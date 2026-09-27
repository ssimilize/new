--[[
	StringRequire: Roblox's require-by-string, resolved over instances, for the vendored Foundry
	packages only. `foundry sync` copies them into src/shared/Foundry, where they require each
	other by string (require("./Flock"), require("../Contract/Contract"), require("@self/part1")).
	Game code keeps instance requires: both loaders (Loader, ClientHarness) still refuse a string
	require from anywhere else.

	  "./X/Y"    script.Parent.X.Y
	  "../X"     script.Parent.Parent.X
	  "@self/X"  script.X   (a ModuleScript's own children, e.g. a Rojo init.luau folder)

	Works on anything with .Parent and :FindFirstChild (Loader proxies, RobloxMock instances).
]]

local StringRequire = {}

StringRequire.PREFIX = "src/shared/Foundry/"

-- allowed(sourcePath, root): true when the requiring module's file sits under src/shared/Foundry.
function StringRequire.allowed(sourcePath: string?, root: string): boolean
	if type(sourcePath) ~= "string" then
		return false
	end
	local path = string.gsub(sourcePath, "\\", "/")
	local base = string.gsub(root, "\\", "/") .. "/"
	if string.sub(path, 1, #base) ~= base then
		return false
	end
	return string.sub(path, #base + 1, #base + #StringRequire.PREFIX) == StringRequire.PREFIX
end

-- resolve(script, target) -> the instance `target` names, relative to `script`; errors when a
-- step is missing or the path does not start with ./, ../ or @self.
function StringRequire.resolve(script: any, target: string): any
	local parts = string.split(target, "/")
	local node
	if parts[1] == "@self" then
		node = script
	elseif parts[1] == "." then
		node = script.Parent
	elseif parts[1] == ".." then
		node = script.Parent and script.Parent.Parent
	else
		error(string.format("require(%q): a string require starts with ./, ../ or @self/", target), 3)
	end
	for i = 2, #parts do
		local part = parts[i]
		if part == ".." then
			node = node and node.Parent
		elseif part ~= "." and part ~= "" then
			node = node and node:FindFirstChild(part)
		end
		if node == nil then
			error(string.format("require(%q): %s is missing", target, part), 3)
		end
	end
	if node == nil then
		error(string.format("require(%q) names nothing", target), 3)
	end
	return node
end

return StringRequire
