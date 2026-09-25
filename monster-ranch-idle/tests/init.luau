--[[
	Test runner:  lune run tests [filter]

	Discovers tests/specs/*.spec.luau. Each spec returns `function(t)` and uses:
	  t.describe(name, fn)   t.it(name, fn)   t.expect(value)
	  t.Shared(path)          require a shared module ("Logic.Rng")
	  t.Server(path)          require a server module ("Kernel.Kernel")
	  t.TestKernel            boot the kernel with chosen systems (see runtime/TestKernel)
	  t.ClientHarness         run the real client against a TestKernel (see runtime/ClientHarness)
	  t.LocaleHarvest         the English text the game can show (see runtime/LocaleHarvest)
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local ROOT = string.gsub(process.cwd, "[/\\]$", "") -- a Windows cwd can end in a backslash
if not fs.isDir(ROOT .. "/tests/specs") then
	-- Allow running from the repo root: `lune run monster-ranch-idle/tests`
	if fs.isDir(ROOT .. "/monster-ranch-idle/tests/specs") then
		ROOT ..= "/monster-ranch-idle"
	end
end

local Loader = require("@self/runtime/Loader")
Loader.init(ROOT)

local warnings = {}
Loader.setGlobal("warn", function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	table.insert(warnings, table.concat(parts, " "))
end)

local expect = require("@self/runtime/Expect")
local TestKernel = require("@self/runtime/TestKernel")
local MockAdapters = require("@self/runtime/MockAdapters")
local ClientHarness = require("@self/runtime/ClientHarness")
ClientHarness.init(ROOT)
local LocaleHarvest = require("@self/runtime/LocaleHarvest")

local filter = process.args[1]

local passed, failed, skipped = 0, 0, 0
local failures = {}

local function runSpec(file: string)
	local specFn = require("@self/specs/" .. string.gsub(file, "%.luau$", ""))
	local stack = {}
	local t = {}
	t.expect = expect
	t.TestKernel = TestKernel
	t.MockAdapters = MockAdapters
	t.ClientHarness = ClientHarness
	t.LocaleHarvest = LocaleHarvest
	t.Roblox = require("@lune/roblox")
	t.Loader = Loader
	t.Root = ROOT
	t.Shared = function(path: string)
		return Loader.get("Shared." .. path)
	end
	t.Server = function(path: string)
		return Loader.get("Server." .. path)
	end
	t.warnings = warnings
	function t.describe(name: string, fn: () -> ())
		table.insert(stack, name)
		fn()
		table.remove(stack)
	end
	function t.it(name: string, fn: () -> ())
		local full = table.concat(stack, " › ") .. (if #stack > 0 then " › " else "") .. name
		if filter and not string.find(string.lower(file .. " " .. full), string.lower(filter), 1, true) then
			skipped += 1
			return
		end
		table.clear(warnings)
		local ok, err = xpcall(fn, debug.traceback)
		if ok then
			passed += 1
		else
			failed += 1
			table.insert(failures, { name = file .. " › " .. full, err = tostring(err) })
		end
	end
	specFn(t)
end

local files = {}
for _, entry in fs.readDir(ROOT .. "/tests/specs") do
	if string.match(entry, "%.spec%.luau$") then
		table.insert(files, entry)
	end
end
table.sort(files)

for _, file in files do
	local ok, err = xpcall(runSpec, debug.traceback, file)
	if not ok then
		failed += 1
		table.insert(failures, { name = file .. " (load)", err = tostring(err) })
	end
end

for _, f in failures do
	print("\n✗ " .. f.name .. "\n" .. f.err)
end
print(string.format("\n%d passed, %d failed, %d skipped (%d spec files)", passed, failed, skipped, #files))
process.exit(if failed > 0 then 1 else 0)
