-- Client entry point: boots the client kernel with the controllers and screens in the Manifest.
local ClientKernel = require(script.Parent.Kernel.ClientKernel)
local Manifest = require(script.Parent.Manifest)

local kernel = ClientKernel.new()

for _, name in Manifest.Controllers do
	local module = script.Parent.Controllers:FindFirstChild(name)
	if module then
		local ok, result = pcall(require, module)
		if ok then
			kernel:AddController(result)
		else
			warn(string.format("[Main] controller %s failed to load: %s", name, tostring(result)))
		end
	else
		warn("[Main] controller listed in Manifest but not found: " .. name)
	end
end

for _, name in Manifest.Screens do
	local module = script.Parent.UI.Screens:FindFirstChild(name)
	if module then
		local ok, result = pcall(require, module)
		if ok then
			kernel.Router:Register(result)
		else
			warn(string.format("[Main] screen %s failed to load: %s", name, tostring(result)))
		end
	else
		warn("[Main] screen listed in Manifest but not found: " .. name)
	end
end

kernel:Start()
