--[[
	VfxCompat (Foundry wave 1e): the effect presets come from the Foundry's EffectGraph library
	(Shared/Foundry/EffectGraph/library/monster-ranch, generated from
	packages/EffectGraph/graphs/monster-ranch.json by `foundry vfx import --package` + `vfx export`)
	and are exactly Config/Vfx's. The old table survives verbatim in tests/runtime/OldVfx.luau
	(Config/Vfx at Ranch main f1dab15).

	  - EffectGraph.toSpecsets(library) equals every preset table of OldVfx field for field: same
	    keys, same strings and booleans, numbers equal to the bit; nothing extra, nothing missing.
	  - A booted client's Visuals/VfxPresets.Table (what Visuals/Vfx and SceneryFx read) is the
	    library's and equals OldVfx whole; with the EffectGraph package removed it warns once and
	    Config/Vfx's table (equal to OldVfx too) runs.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")

	local EffectGraph = t.Shared("Foundry.EffectGraph.EffectGraph")
	local Library = t.Shared("Foundry.EffectGraph.library.monster-ranch")
	local ConfigVfx = t.Shared("Config.Vfx")
	local Old = luau.load(fs.readFile(t.Root .. "/tests/runtime/OldVfx.luau"), { debugName = "tests/runtime/OldVfx.luau" })()

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	-- exact(a, b) -> the first difference (nil = equal) and how many leaves were compared.
	-- Numbers compare by their 64-bit pattern, so 0 and -0 differ and nothing is "close enough".
	local function exact(a: any, b: any, path: string, count: { n: number }): string?
		if type(a) ~= type(b) then
			return `{path}: {type(a)} {tostring(a)} ~= {type(b)} {tostring(b)}`
		end
		if type(a) == "table" then
			for k, v in a do
				if b[k] == nil then
					return `{path}.{tostring(k)}: extra (not in the old table)`
				end
				local d = exact(v, b[k], `{path}.{tostring(k)}`, count)
				if d then
					return d
				end
			end
			for k in b do
				if a[k] == nil then
					return `{path}.{tostring(k)}: missing (in the old table)`
				end
			end
			return nil
		end
		count.n += 1
		if type(a) == "number" then
			if string.pack("<d", a) ~= string.pack("<d", b) then
				return `{path}: {string.format("%.17g", a)} ~= {string.format("%.17g", b)}`
			end
			return nil
		end
		return if a == b then nil else `{path}: {tostring(a)} ~= {tostring(b)}`
	end

	-- The old table's presets, found the way the importer finds them (importers.mr_presets): a list
	-- of specs with a sprite, directly (Titanic) or by key (Auras.ember).
	local function isSpecList(v: any): boolean
		if type(v) ~= "table" or #v == 0 then
			return false
		end
		for _, s in v do
			if type(s) ~= "table" or s.sprite == nil then
				return false
			end
		end
		return true
	end
	local function oldPresets(): { [string]: any }
		local out = {}
		for name, v in Old do
			if isSpecList(v) then
				out[name] = { [""] = v }
			elseif type(v) == "table" and next(v) ~= nil then
				local all = true
				for _, x in v do
					all = all and isSpecList(x)
				end
				if all then
					out[name] = v
				end
			end
		end
		return out
	end

	describe("the library against the old table", function()
		it("all 72 presets equal field for field, bit-equal, nothing extra and nothing missing", function()
			local built = EffectGraph.toSpecsets(Library)
			local presets, specs, count = 0, 0, { n = 0 }
			for name, byKey in oldPresets() do
				expect({ name, built[name] ~= nil }).toEqual({ name, true })
				for key, oldSpecs in byKey do
					local got = if key == "" then built[name] else built[name][key]
					local d = exact(got, oldSpecs, if key == "" then name else `{name}.{key}`, count)
					expect(d).toBe(nil)
					presets += 1
					specs += #oldSpecs
				end
			end
			-- nothing extra: every table the library builds is an old preset table, whole
			local found = oldPresets()
			for name, set in built do
				expect({ name, found[name] ~= nil }).toEqual({ name, true })
				expect(exact(set, Old[name], name, { n = 0 })).toBe(nil)
			end
			expect(presets).toBe(72)
			expect(#Library).toBe(72)
			expect(specs).toBe(132)
			print(`VfxCompat: {presets} presets, {specs} specs, {count.n} values equal to the bit`)
		end)

		it("Config/Vfx (the fallback) is still the old table exactly", function()
			expect(exact(ConfigVfx, Old, "Config.Vfx", { n = 0 })).toBe(nil)
		end)
	end)

	describe("the client's preset table", function()
		local function boot(removePackage: boolean)
			local h = TestKernel.new({ systems = allSystems() })
			local c = ClientHarness.new(h, h:Join(), { noBoot = true })
			if removePackage then
				c.world.game:GetService("ReplicatedStorage").Shared.Foundry.EffectGraph:Destroy()
			end
			c:Boot()
			c:Advance(1)
			return c, c:require(c.clientFolder.Visuals.VfxPresets)
		end

		local function notVendored(c): number
			local n = 0
			for _, w in c.world.warnings do
				if string.find(w, "EffectGraph library is not vendored", 1, true) then
					n += 1
				end
			end
			return n
		end

		it("is built from the library and equals the old table whole", function()
			local c, VfxPresets = boot(false)
			expect(VfxPresets.Using()).toBe(true)
			local live = c:require(c.world.game:GetService("ReplicatedStorage").Shared.Config.Vfx)
			expect(VfxPresets.Table.Auras ~= live.Auras).toBe(true) -- the library's tables, not Config's
			expect(exact(VfxPresets.Table, Old, "Table", { n = 0 })).toBe(nil)
			for key, why in VfxPresets.NotAdopted do
				expect({ key, #why >= 20 }).toEqual({ key, true })
			end
			expect(notVendored(c)).toBe(0)
			expect(#c:Problems()).toBe(0)
		end)

		it("without the EffectGraph package it warns once and runs Config/Vfx's presets", function()
			local c, VfxPresets = boot(true)
			expect(VfxPresets.Using()).toBe(false)
			expect(VfxPresets.Use(c.kernel.Foundry)).toBe(false)
			expect(exact(VfxPresets.Table, Old, "Table", { n = 0 })).toBe(nil)
			expect(notVendored(c)).toBe(1)
			expect(#c:Problems({ "EffectGraph library is not vendored" })).toBe(0)
		end)
	end)
end
