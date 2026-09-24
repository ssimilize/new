-- Server entry point: boots the kernel with every system listed in the Manifest.
local Kernel = require(script.Parent.Kernel.Kernel)
local Adapters = require(script.Parent.Kernel.Adapters)
local Manifest = require(script.Parent.Manifest)

local kernel = Kernel.new({ adapters = Adapters.Roblox() })

for _, name in Manifest.Systems do
	local folder = script.Parent.Systems:FindFirstChild(name)
	if folder then
		local ok, module = pcall(require, folder)
		if ok then
			kernel:AddSystem(module)
		else
			warn(string.format("[Main] system %s failed to load: %s", name, tostring(module)))
		end
	else
		warn("[Main] system listed in Manifest but not found: " .. name)
	end
end

kernel:Start()
