--[[
	Syntax-checks every .luau file under src/ and tests/ with the Luau compiler.
	Client code cannot run in Lune, so this is its first line of defence.
	Usage: lune run tests/lint
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local ROOT = string.gsub(process.cwd, "/$", "")
if not fs.isDir(ROOT .. "/src") and fs.isDir(ROOT .. "/monster-ranch-idle/src") then
	ROOT ..= "/monster-ranch-idle"
end

local checked, failed = 0, 0
local function walk(path: string)
	for _, entry in fs.readDir(path) do
		local full = path .. "/" .. entry
		if fs.isDir(full) then
			walk(full)
		elseif string.match(entry, "%.luau$") then
			checked += 1
			local ok, err = pcall(luau.compile, fs.readFile(full))
			if not ok then
				failed += 1
				print("✗ " .. string.sub(full, #ROOT + 2) .. "\n  " .. tostring(err))
			end
		end
	end
end
walk(ROOT .. "/src")
walk(ROOT .. "/tests")
print(string.format("%d files checked, %d with syntax errors", checked, failed))
process.exit(if failed > 0 then 1 else 0)
