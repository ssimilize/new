--[[
	Locale (update 3.2): the matching rules of Shared/Locale, the integrity of the Spanish
	and Portuguese catalogues, and that every name and description in Config and every
	message the server sends has a translation in both.

	LOCALE_REPORT=<file> lune run tests Locale also writes what is missing to <file>.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local process = require("@lune/process")

	local Locale = t.Shared("Locale")
	local Config = t.Shared("Config")
	local Harvest = t.LocaleHarvest
	local LANGS = { "es", "pt" }

	local function report(title: string, lines: { string })
		local path = process.env.LOCALE_REPORT
		if path and #lines > 0 then
			local fs = require("@lune/fs")
			local existing = if fs.isFile(path) then fs.readFile(path) else ""
			fs.writeFile(path, existing .. "## " .. title .. "\n" .. table.concat(lines, "\n") .. "\n\n")
		end
	end

	describe("Locale matching", function()
		Locale.Register("test", {
			["Egg Shop"] = "Tienda de huevos",
			["Grove Egg"] = "Huevo del Bosque",
			["Pearl Egg"] = "Huevo de Perla",
			["Unlocks at Ranch Level {1}"] = "Se desbloquea en el Nivel de Rancho {1}",
			["{1} sold for {2}!"] = "¡{1} se vendió por {2}!",
			["Needs {1}"] = "Necesita {1}",
			["{1} line"] = "Línea {1}",
			["Lv {1}"] = "Nv {1}",
			["Collect all +{1}"] = "Recoger todo +{1}",
			["{1} +{2}"] = "{2} + {1}",
			["Ends in {1}"] = "Termina en {1}",
			["{1} Mar {2}"] = "{1} mar {2}",
			["Page {1} · first {10}"] = "Primero {10} · página {1}",
		})

		it("translates exact strings and keeps unknown ones in English", function()
			expect(Locale.Translate("test", "Egg Shop")).toBe("Tienda de huevos")
			expect(Locale.Translate("test", "Not in the catalogue")).toBe("Not in the catalogue")
			expect(Locale.Translate("en", "Egg Shop")).toBe("Egg Shop")
			expect(Locale.Translate("test", "")).toBe("")
		end)

		it("fills templates, reorders placeholders and translates the pieces", function()
			expect(Locale.Translate("test", "Unlocks at Ranch Level 62")).toBe("Se desbloquea en el Nivel de Rancho 62")
			expect(Locale.Translate("test", "Blazefang sold for 12K!")).toBe("¡Blazefang se vendió por 12K!")
			expect(Locale.Translate("test", "Needs Grove Egg")).toBe("Necesita Huevo del Bosque")
			expect(Locale.Translate("test", "Needs Grove Egg, Pearl Egg")).toBe("Necesita Huevo del Bosque, Huevo de Perla")
			expect(Locale.Translate("test", "Ends in 11 Mar 2028")).toBe("Termina en 11 mar 2028")
		end)

		it("handles placeholders past {9}", function()
			expect(Locale.Translate("test", "Page 3 · first 12")).toBe("Primero 12 · página 3")
			expect(Locale.Placeholders("{2} {10} {1}")).toEqual({ 1, 2, 10 })
		end)

		it("prefers the template with more fixed text", function()
			expect(Locale.Translate("test", "Collect all +48K")).toBe("Recoger todo +48K")
		end)

		it("splits lines and · lists, keeping what it can't translate", function()
			expect(Locale.Translate("test", "Cindlet line · Lv 5")).toBe("Línea Cindlet · Nv 5")
			expect(Locale.Translate("test", "Egg Shop\nSomething new")).toBe("Tienda de huevos\nSomething new")
			expect(Locale.Translate("test", "Needs: Grove Egg")).toBe("Needs: Huevo del Bosque")
			expect(Locale.Translate("test", "Grove Egg ×2 → Pearl Egg")).toBe("Huevo del Bosque ×2 → Huevo de Perla")
		end)

		it("sets symbols at either end aside", function()
			expect(Locale.Translate("test", "✔ Egg Shop")).toBe("✔ Tienda de huevos")
			expect(Locale.Translate("test", "🔒 Grove Egg ★")).toBe("🔒 Huevo del Bosque ★")
			expect(Locale.Translate("test", "★★★")).toBe("★★★")
		end)

		it("keeps surrounding spaces, numbers and units as they are", function()
			expect(Locale.Translate("test", "  Egg Shop ")).toBe("  Tienda de huevos ")
			expect(Locale.Translate("test", "1.2K")).toBe("1.2K")
			expect(Locale.Translate("test", "3h 12m")).toBe("3h 12m")
			expect(Locale.Translate("test", "×2")).toBe("×2")
			expect(Locale.Translate("test", "+30 XP")).toBe("+30 XP")
		end)

		it("never fills a placeholder with nothing", function()
			expect(Locale.Translate("test", "Needs ")).toBe("Needs ")
		end)

		it("explains which pieces stay in English", function()
			local out, missing = Locale.Explain("test", "Cindlet line · Something new")
			expect(out).toBe("Línea Cindlet · Something new")
			table.sort(missing)
			expect(missing).toEqual({ "Cindlet", "Something new" })
			local none, all = Locale.Explain("test", "Nothing here")
			expect(none).toBe(nil)
			expect(all).toEqual({ "Nothing here" })
			local _, clean = Locale.Explain("test", "Needs Grove Egg")
			expect(clean).toEqual({})
		end)

		it("picks the language from the setting or the Roblox locale", function()
			expect(Locale.FromLocaleId("es-mx")).toBe("es")
			expect(Locale.FromLocaleId("es-es")).toBe("es")
			expect(Locale.FromLocaleId("pt-br")).toBe("pt")
			expect(Locale.FromLocaleId("PT_pt")).toBe("pt")
			expect(Locale.FromLocaleId("en-us")).toBe("en")
			expect(Locale.FromLocaleId("fr-fr")).toBe("en")
			expect(Locale.FromLocaleId(nil)).toBe("en")
			expect(Locale.Pick("auto", "es-mx")).toBe("es")
			expect(Locale.Pick(nil, "pt-br")).toBe("pt")
			expect(Locale.Pick("en", "es-mx")).toBe("en")
			expect(Locale.Pick("pt", "en-us")).toBe("pt")
			expect(Locale.Pick("fr", "es-mx")).toBe("es")
		end)

		it("turns printf formats into templates", function()
			expect(Harvest.fromFormat("Unlocks at Ranch Level %d")).toBe("Unlocks at Ranch Level {1}")
			expect(Harvest.fromFormat("%s sold for %s coins (%.1f%%)")).toBe("{1} sold for {2} coins ({3}%)")
			expect(Harvest.fromFormat("%d:%02d")).toBe("{1}:{2}")
		end)
	end)

	describe("Locale catalogues", function()
		it("have the same keys in Spanish and Portuguese", function()
			local es, pt = Locale.Catalog("es"), Locale.Catalog("pt")
			local problems = {}
			for key in es do
				if pt[key] == nil then
					table.insert(problems, "pt is missing " .. string.format("%q", key))
				end
			end
			for key in pt do
				if es[key] == nil then
					table.insert(problems, "es is missing " .. string.format("%q", key))
				end
			end
			table.sort(problems)
			if #problems > 0 then
				error(#problems .. " keys differ:\n  " .. table.concat(problems, "\n  "))
			end
		end)

		it("keep every placeholder and translate every entry", function()
			local problems = {}
			for _, lang in LANGS do
				for key, value in Locale.Catalog(lang) do
					local a, b = Locale.Placeholders(key), Locale.Placeholders(value)
					if table.concat(a, ",") ~= table.concat(b, ",") then
						table.insert(problems, string.format("%s %q -> %q: placeholders differ", lang, key, value))
					end
					if string.find(key, "}{", 1, true) then
						table.insert(problems, string.format("%s %q: two placeholders touch, so the split is ambiguous", lang, key))
					end
					if type(value) ~= "string" or value == "" then
						table.insert(problems, string.format("%s %q: empty translation", lang, key))
					end
					if key ~= string.match(key, "^%s*(.-)%s*$") then
						table.insert(problems, string.format("%s %q: key has surrounding spaces", lang, key))
					end
				end
			end
			table.sort(problems)
			if #problems > 0 then
				error(#problems .. " problems:\n  " .. table.concat(problems, "\n  "))
			end
		end)

		it("never translate language names or monster names", function()
			local kept = Harvest.keptNames(Config)
			for _, language in Locale.Languages do
				kept[language.name] = true
			end
			local problems = {}
			for _, lang in LANGS do
				for key in Locale.Catalog(lang) do
					if kept[key] then
						table.insert(problems, lang .. " translates the name " .. key)
					end
				end
			end
			table.sort(problems)
			if #problems > 0 then
				error(table.concat(problems, "\n"))
			end
		end)
	end)

	describe("Locale coverage", function()
		local kept = Harvest.keptNames(Config)

		local function check(title: string, found)
			local lines, count = {}, 0
			for _, lang in LANGS do
				for _, item in found do
					local missing = Harvest.missing(Locale, lang, item.text, kept)
					if #missing > 0 then
						count += 1
						local text = string.gsub(table.concat(missing, " | "), "\n", "\\n")
						table.insert(lines, string.format("%s\t%s\t%s", lang, item.where, text))
					end
				end
			end
			report(title, lines)
			if count > 0 then
				local shown = table.move(lines, 1, math.min(#lines, 40), 1, {})
				error(string.format("%d untranslated (first %d):\n  %s", count, #shown, table.concat(shown, "\n  ")))
			end
		end

		it("translates every name and description in Config", function()
			local found = Harvest.configStrings(Config)
			expect(#found).toBeGreaterThan(300)
			check("Config", found)
		end)

		it("translates every message the server sends", function()
			local found = Harvest.serverMessages(t.Root)
			expect(#found).toBeGreaterThan(200)
			check("Server messages", found)
		end)
	end)
end
