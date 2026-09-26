--[[
	Glyphs: UI text never uses a character the game's font cannot draw. FredokaOne (Theme.Fonts)
	has no U+2715 "✕", so every close button labelled with it rendered as a blank square (found in
	Studio 2026-09-26); "X" draws cleanly. Scans string literals in src/client and src/shared,
	comments excluded.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local fs = require("@lune/fs")

	-- Characters FredokaOne renders as nothing (checked with TextService in Studio).
	local MISSING = { "✕" }

	local function walk(dir: string, out: { string })
		for _, name in fs.readDir(dir) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				walk(path, out)
			elseif name:match("%.luau$") then
				table.insert(out, path)
			end
		end
		return out
	end

	describe("Glyphs", function()
		it("keeps characters FredokaOne cannot draw out of UI strings", function()
			local files = walk(t.Root .. "/src/client", {})
			walk(t.Root .. "/src/shared", files)
			local found = {}
			for _, path in files do
				local n = 0
				for line in (fs.readFile(path) .. "\n"):gmatch("([^\n]*)\n") do
					n += 1
					local code = line:gsub("%-%-.*$", "")
					for _, glyph in MISSING do
						for literal in code:gmatch('"([^"]*)"') do
							if literal:find(glyph, 1, true) then
								table.insert(found, string.format("%s:%d %s", path:sub(#t.Root + 2), n, literal))
							end
						end
					end
				end
			end
			expect(table.concat(found, "\n")).toBe("")
		end)
	end)
end
