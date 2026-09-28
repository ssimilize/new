-- Server entry point: boots the kernel with every system listed in the Manifest.
local Kernel = require(script.Parent.Kernel.Kernel)
local Adapters = require(script.Parent.Kernel.Adapters)
local Manifest = require(script.Parent.Manifest)
local ServerFoundry = require(script.Parent.Kernel.ServerFoundry)

local kernel = Kernel.new({ adapters = Adapters.Roblox() })

-- The vendored Foundry packages (Shared.Foundry), handed to every system as ctx.Foundry.
kernel.Foundry = ServerFoundry.new({
	folder = game:GetService("ReplicatedStorage").Shared:FindFirstChild("Foundry"),
	requireModule = require,
	Bus = kernel.Bus,
	serverTime = function()
		return workspace:GetServerTimeNow()
	end,
	verbose = kernel.Verbose,
})

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

-- Studio only: the QA bridge (ServerStorage.QABridge) for staged checks, see Kernel/QABridge.
if kernel.Adapters.IsStudio then
	require(script.Parent.Kernel.QABridge).Attach(kernel)

	-- Launch checklist (R2-LAUNCH): warn once about owner-created ids still unset (game
	-- passes, products, badges, the group, reminder templates/secret). Never on a live
	-- server; see docs/GO_LIVE.md.
	local Shared = game:GetService("ReplicatedStorage").Shared
	local LaunchCheck = require(Shared.Logic.LaunchCheck)
	local Config = require(Shared.Config)
	local missing = LaunchCheck.Missing(Config)
	if #missing > 0 then
		warn("[Main] " .. LaunchCheck.Summary(missing))
	end
end
