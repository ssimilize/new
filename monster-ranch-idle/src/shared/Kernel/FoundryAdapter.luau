--[[
	FoundryAdapter: the shared core of ServerFoundry and ClientFoundry (pure; runs under Lune).

	The vendored Foundry packages (src/shared/Foundry, written by `foundry sync --game
	monster-ranch`) sit in ReplicatedStorage.Shared.Foundry as <Name>/<Name> modules, plus the
	generated Game/Game module ({ game, budgets }) that sync writes from games/monster-ranch.json.
	Systems and controllers never require Shared.Foundry themselves: each realm builds this once
	at boot and hands it over as kernel.Foundry / ctx.Foundry:

	  kernel.Foundry = {
	    packages = { <Name> = module, ... },    every vendored package, found generically
	    Contract = packages.Contract,           nil when nothing is vendored
	    game = "monster-ranch", budgets = {...}, from the generated Game module
	    rules = { <Name> = { <rule> = value } }, a package's `rules` and `tables` folders
	    libraries = { <Name> = { <lib> = value } }, a package's `library` folder
	    adapter = function(systemName) -> Contract.Adapter,
	  }

	FoundryAdapter.build(deps):
	  folder         the Shared.Foundry Instance (or a fake with GetChildren / FindFirstChild /
	                 IsA / Name); nil = nothing vendored
	  requireModule  require (injected so specs can hand in fakes)
	  on / emit      the realm's bus, already in Contract form (see ServerFoundry / ClientFoundry)
	  now            () -> number, the shared world clock in seconds (GetServerTimeNow)
	  quality        () -> 1 | 2 | 3
	  warn / print   output sinks (default the globals)
	  verbose        boolean | () -> boolean: info logs print only while true (kernel.Verbose)
]]

local FoundryAdapter = {}

FoundryAdapter.GENERATED = "Game"
FoundryAdapter.DEFAULT_GAME = "monster-ranch"
-- tag(inst, system) writes this attribute (profile tagPrefix "MR_"); nothing reads it yet
FoundryAdapter.TAG_ATTRIBUTE = "MR_System"

local function isModule(inst: any): boolean
	local ok, yes = pcall(function()
		return inst:IsA("ModuleScript")
	end)
	return ok and yes == true
end

-- modulesIn(packageFolder, name, sub, requireModule, warn) -> { <module> = value }?: the
-- ModuleScripts in the package's `sub` folder (rules, tables or library), by name.
local function modulesIn(packageFolder: any, name: string, sub: string, requireModule: (any) -> any, warnFn: (string) -> ())
	local okF, subFolder = pcall(function()
		return packageFolder:FindFirstChild(sub)
	end)
	if not okF or subFolder == nil then
		return nil
	end
	local okC, children = pcall(function()
		return subFolder:GetChildren()
	end)
	if not okC or type(children) ~= "table" then
		return nil
	end
	local out = {}
	for _, child in children do
		local moduleName = child.Name
		if type(moduleName) == "string" and out[moduleName] == nil and isModule(child) then
			local ok, value = pcall(requireModule, child)
			if ok then
				out[moduleName] = value
			else
				warnFn("[Foundry] " .. name .. "/" .. sub .. "/" .. moduleName .. " failed to load: " .. tostring(value))
			end
		end
	end
	return out
end

-- discover(folder, requireModule, warn) -> packages, gameModule?, rules, libraries
-- Every child folder <Name> holding a ModuleScript <Name> is a package, except the generated
-- Game module, which is returned separately. A module that errors is skipped with a warning.
-- rules[<Name>] merges the package's `rules` folder with its `tables` folder (rules win a
-- name clash); libraries[<Name>] is its `library` folder.
function FoundryAdapter.discover(folder: any, requireModule: (any) -> any, warnFn: (string) -> ())
	local packages, rules, libraries = {}, {}, {}
	local gameModule = nil
	if folder == nil then
		return packages, nil, rules, libraries
	end
	local names, modules, folders = {}, {}, {}
	for _, child in folder:GetChildren() do
		local name = child.Name
		if type(name) == "string" and modules[name] == nil then
			local module = child:FindFirstChild(name)
			if module ~= nil and isModule(module) then
				modules[name] = module
				folders[name] = child
				table.insert(names, name)
			end
		end
	end
	table.sort(names)
	for _, name in names do
		local ok, value = pcall(requireModule, modules[name])
		if not ok then
			warnFn("[Foundry] " .. name .. " failed to load: " .. tostring(value))
		elseif name == FoundryAdapter.GENERATED then
			gameModule = value
		else
			packages[name] = value
			local r = modulesIn(folders[name], name, "rules", requireModule, warnFn)
			local tbl = modulesIn(folders[name], name, "tables", requireModule, warnFn)
			if tbl ~= nil then
				r = r or {}
				for key, v in tbl do
					if r[key] == nil then
						r[key] = v
					end
				end
			end
			if r ~= nil then
				rules[name] = r
			end
			local lib = modulesIn(folders[name], name, "library", requireModule, warnFn)
			if lib ~= nil then
				libraries[name] = lib
			end
		end
	end
	return packages, gameModule, rules, libraries
end

-- pickBudget(value, quality) -> number?: a number as is; an array { low, medium, high } picks
-- by quality 1..3 (clamped); anything else is nil (unlimited).
function FoundryAdapter.pickBudget(value: any, quality: number): number?
	if type(value) == "number" then
		return value
	end
	if type(value) == "table" and #value > 0 then
		local v = value[math.clamp(math.floor(quality), 1, #value)]
		return if type(v) == "number" then v else nil
	end
	return nil
end

local function flag(v: any): boolean
	if type(v) == "function" then
		local ok, on = pcall(v)
		return ok and on == true
	end
	return v == true
end

function FoundryAdapter.build(deps)
	local warnFn = deps.warn or warn
	local printFn = deps.print or print
	local packages, gameModule, rules, libraries = FoundryAdapter.discover(deps.folder, deps.requireModule or require, warnFn)
	local gameId = FoundryAdapter.DEFAULT_GAME
	local budgets = {}
	if type(gameModule) == "table" then
		if type(gameModule.game) == "string" then
			gameId = gameModule.game
		end
		if type(gameModule.budgets) == "table" then
			budgets = gameModule.budgets
		end
	end
	local Contract = packages.Contract
	local now, quality, on, emit = deps.now, deps.quality, deps.on, deps.emit

	local foundry = {
		packages = packages,
		Contract = Contract,
		game = gameId,
		budgets = budgets,
		rules = rules,
		libraries = libraries,
	}

	-- adapter(systemName) -> the Contract.Adapter over this realm's kernel, for one system.
	function foundry.adapter(systemName: string)
		local prefix = "[" .. tostring(systemName) .. "] "
		return {
			game = gameId,
			now = now,
			rng = function(seed: number)
				assert(Contract ~= nil, "Foundry Contract is not vendored (src/shared/Foundry)")
				return Contract.Rng.new(seed)
			end,
			log = function(level: string, msg: string, _data: any?)
				if level == "warn" or level == "error" then
					warnFn(prefix .. tostring(msg))
				elseif flag(deps.verbose) then
					printFn(prefix .. tostring(msg))
				end
			end,
			budget = function(kind: string): number?
				return FoundryAdapter.pickBudget(budgets[kind], quality())
			end,
			quality = quality,
			on = on,
			emit = emit,
			tag = function(inst: any, system: string)
				pcall(function()
					inst:SetAttribute(FoundryAdapter.TAG_ATTRIBUTE, system)
				end)
			end,
		}
	end

	return foundry
end

return FoundryAdapter
