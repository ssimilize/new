--[[
	LocaleClient (update 3.2): the real client in Spanish and Portuguese.

	The walk plays every screen as a new and as a veteran player, clicking every button,
	and checks that every text shown (menus, toasts, server messages, world signs) has a
	translation. The Spanish and Portuguese catalogues hold the same keys (Locale.spec), so
	one walk proves both.

	LOCALE_REPORT=<file> lune run tests LocaleClient also writes what is missing to <file>.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local process = require("@lune/process")

	local Locale = t.Shared("Locale")
	local Config = t.Shared("Config")
	local Harvest = t.LocaleHarvest

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	-- A max-level player with every currency and one monster of every species line.
	local function veteran(h, player)
		h:System("Progression"):AddXP(player, 1e9, "test")
		local currency = h:System("Currency")
		for key, amount in { coins = 1e9, gems = 1e5, stardust = 1e5, treats = 1e4, friendship = 1e4 } do
			currency:Add(player, key, amount, "test")
		end
		for flavor in Config.Food.ById or {} do
			currency:Add(player, "food." .. flavor, 100, "test")
		end
		local ids = {}
		for i, line in Config.Species.Lines do
			local stage = (i % 3) + 1
			local spec = { line = line.id, rarity = line.rarity or 2, stage = stage }
			if stage == 3 then
				spec.form = line.forms[3][1].id
			end
			table.insert(ids, h:System("Monsters"):Create(player, spec, "test", true).id)
		end
		h:System("Eggs"):Add(player, "meadow", "test", 3)
		h:Step()
		return ids
	end

	local function expectClean(c)
		local problems = c:Problems({ "Infinite yield possible" })
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	local function localize(c)
		return c.kernel:GetController("Localize")
	end

	-- Every text the player can see right now whose English has no translation.
	local function collect(c, kept, sink, where: string)
		local controller = localize(c)
		local roots = { c.playerGui, c.world.workspace }
		for _, root in roots do
			for _, d in root:GetDescendants() do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and d:GetAttribute("Localize") ~= false then
					local shown = root ~= c.playerGui or c:IsShown(d)
					local source = shown and controller:Source(d)
					if source then
						for _, piece in Harvest.missing(Locale, "es", source, kept) do
							if not sink.where[piece] then
								sink.where[piece] = where
								table.insert(sink.list, piece)
							end
						end
					end
				end
			end
		end
	end

	local function keptFor(c)
		local kept = Harvest.keptNames(Config)
		kept[c.localPlayer.Name] = true
		kept[c.localPlayer.DisplayName] = true
		for _, language in Locale.Languages do
			kept[language.name] = true
		end
		return kept
	end

	local function finish(sink)
		local list = sink.list
		table.sort(list)
		local path = process.env.LOCALE_REPORT
		if path and #list > 0 then
			local fs = require("@lune/fs")
			local lines = {}
			for _, piece in list do
				table.insert(lines, string.format("ui\t%s\t%s", sink.where[piece], (string.gsub(piece, "\n", "\\n"))))
			end
			local existing = if fs.isFile(path) then fs.readFile(path) else ""
			fs.writeFile(path, existing .. "## UI walk\n" .. table.concat(lines, "\n") .. "\n\n")
		end
		if #list > 0 then
			local shown = table.move(list, 1, math.min(#list, 60), 1, {})
			error(string.format("%d untranslated texts (first %d):\n  %s", #list, #shown, table.concat(shown, "\n  ")))
		end
	end

	describe("Localize", function()
		it("follows the Roblox language, and the setting switches every text in place", function()
			local h = TestKernel.new({ systems = allSystems() })
			local player = h:Join()
			local c = ClientHarness.new(h, player, { localeId = "es-mx" })
			c:Advance(1)
			expect(localize(c):Language()).toBe("es")
			local settings = c:Open("Settings")
			c:Advance(0.5)
			expect(c:HasText("Ajustes", settings)).toBe(true)
			expect(c:HasText("Auto · Español", settings)).toBe(true)
			-- Auto → English → Español → Português
			c:Click(c:Button("Auto · Español", settings))
			c:Advance(0.5)
			expect(c:Store("profile.Settings.language")).toBe("en")
			expect(localize(c):Language()).toBe("en")
			expect(c:HasText("Settings", settings)).toBe(true)
			expect(c:HasText("Ajustes", settings)).toBe(false)
			c:Click(c:Button("English", settings))
			c:Advance(0.5)
			expect(c:Store("profile.Settings.language")).toBe("es")
			c:Click(c:Button("Español", settings))
			c:Advance(0.5)
			expect(c:Store("profile.Settings.language")).toBe("pt")
			expect(localize(c):Language()).toBe("pt")
			expect(c:HasText("Português", settings)).toBe(true)
			expect(c:HasText(Locale.Translate("pt", "Menus and messages"), settings)).toBe(true)
			expectClean(c)
		end)

		it("keeps the language across a rejoin and never translates what players type", function()
			local h = TestKernel.new({ systems = allSystems() })
			local player = h:Join()
			local c = ClientHarness.new(h, player)
			c:Advance(1)
			expect(localize(c):Language()).toBe("en")
			local ok = c:Request("Settings.SetLanguage", { language = "pt" })
			expect(ok).toBe(true)
			c:Advance(0.5)
			expect(localize(c):Language()).toBe("pt")
			local bad = c:Request("Settings.SetLanguage", { language = "fr" })
			expect(bad).toBe(false)
			-- A TextBox keeps the player's words; only its placeholder is translated.
			local box = c.Instance.new("TextBox")
			box.PlaceholderText = "Settings"
			box.Text = "Settings"
			box.Parent = c.kernel.UI.Screens
			c:Advance(0.1)
			expect(box.Text).toBe("Settings")
			expect(box.PlaceholderText).toBe(Locale.Translate("pt", "Settings"))
			-- Opting out keeps the English.
			local raw = c.Instance.new("TextLabel")
			raw:SetAttribute("Localize", false)
			raw.Text = "Settings"
			raw.Parent = c.kernel.UI.Screens
			c:Advance(0.1)
			expect(raw.Text).toBe("Settings")
			expectClean(c)

			h:Leave(player)
			local again = h:Join(player.UserId, player.Name)
			local c2 = ClientHarness.new(h, again)
			c2:Advance(1)
			expect(localize(c2):Language()).toBe("pt")
		end)

		it("shows a server's refusal in the player's language", function()
			local h = TestKernel.new({ systems = allSystems() })
			local player = h:Join()
			local c = ClientHarness.new(h, player, { localeId = "pt-br" })
			c:Advance(1)
			local ok, err = c:Request("Settings.SetLanguage", { language = "es" })
			expect(ok).toBe(true)
			expect(err).toBe(nil)
			c:Advance(0.5)
			c.world:Run(function()
				c.kernel:Toast("Unlocks at Ranch Level 62", "error")
			end)
			c:Advance(0.2)
			expect(c:HasText("Se desbloquea en el Nivel de Rancho 62")).toBe(true)
			expectClean(c)
		end)

		it("shrinks a translation that is longer than its English", function()
			local h = TestKernel.new({ systems = allSystems() })
			local player = h:Join()
			local c = ClientHarness.new(h, player, { localeId = "es-mx" })
			c:Advance(1)
			local label = c.Instance.new("TextLabel")
			label.TextSize = 20
			label.Text = "Settings" -- 8 letters; "Ajustes" is 7, so no change
			label.Parent = c.kernel.UI.Screens
			c:Advance(0.1)
			expect(label.TextSize).toBe(20)
			label.Text = "Menus and messages" -- 18 → "Menús y mensajes" 16: no change
			c:Advance(0.1)
			expect(label.TextSize).toBe(20)
			label.Text = "Codes" -- 5 → "Códigos" 7: 20 × 5/7 = 14.3, floored at 75 % = 15
			c:Advance(0.1)
			expect(label.Text).toBe("Códigos")
			expect(label.TextSize).toBe(15)
			label.Text = "Settings" -- back to a translation that fits restores the size
			c:Advance(0.1)
			expect(label.Text).toBe("Ajustes")
			expect(label.TextSize).toBe(20)
			expectClean(c)
		end)
	end)

	describe("Localize fit", function()
		-- Text is measured the way the mock lays out (UIScale applied, no layouts or padding),
		-- with an average glyph of CHAR × TextSize. A label only counts as too small when its
		-- English fits the room and its translation, at the fitted size, does not.
		local CHAR = 0.55
		local LINE = 1.15
		local Enum = t.Roblox.Enum

		local function visible(text: string): number
			local plain = string.gsub(text, "<[^>]->", "")
			return utf8.len(plain) or #plain
		end

		-- The room a label's text has: a label that grows sideways gets its parent's width.
		local function room(d)
			local auto = d.AutomaticSize
			local w = d.AbsoluteSize.X
			if auto == Enum.AutomaticSize.X or auto == Enum.AutomaticSize.XY then
				local parent = d.Parent
				w = if parent and parent:IsA("GuiObject") then parent.AbsoluteSize.X else math.huge
			end
			return w, d.AbsoluteSize.Y
		end

		local function fits(text: string, size: number, scale: number, w: number, h: number, wrapped: boolean): boolean
			local width = visible(text) * size * CHAR * scale
			if not wrapped then
				return width <= w * 1.02 + 1
			end
			local lines = math.max(1, math.ceil(width / math.max(1, w)))
			return lines * size * LINE * scale <= h + 2
		end

		for _, locale in { { lang = "es", id = "es-mx" }, { lang = "pt", id = "pt-br" } } do
			it("fits every screen on a small phone in " .. locale.lang, function()
				local h = TestKernel.new({ systems = allSystems() })
				local player = h:Join()
				local ids = veteran(h, player)
				local viewport = t.Roblox.Vector2.new(568, 320)
				local c = ClientHarness.new(h, player, { viewport = viewport, localeId = locale.id })
				c:Advance(1)
				local controller = localize(c)
				local manifest = c:require(c.clientFolder.Manifest)
				local overflow, long = {}, {}
				local seen = {}
				for _, name in manifest.Screens do
					local params = if name == "MonsterDetail" then { id = ids[1] } else nil
					local root = c:Open(name, params)
					c:Advance(0.5)
					for _, gui in { root, table.unpack(root:GetChildren()) } do
						if gui:IsA("GuiObject") and gui.Visible then
							local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
							if pos.X < -1 or pos.Y < -1 or pos.X + size.X > viewport.X + 1 or pos.Y + size.Y > viewport.Y + 1 then
								table.insert(
									overflow,
									string.format("%s/%s at (%d,%d) size %dx%d", name, gui.Name, pos.X, pos.Y, size.X, size.Y)
								)
							end
						end
					end
					local scale = c.kernel.UI.Scale or 1
					for _, d in c:Descendants(root) do
						if (d:IsA("TextLabel") or d:IsA("TextButton")) and c:IsShown(d) and not d.TextScaled then
							local grows = d.TextWrapped
								and (d.AutomaticSize == Enum.AutomaticSize.Y or d.AutomaticSize == Enum.AutomaticSize.XY)
							local source = controller:Source(d)
							if source and source ~= d.Text and not grows and not seen[source] then
								local w, h = room(d)
								local base = controller:BaseSize(d) or d.TextSize
								if
									fits(source, base, scale, w, h, d.TextWrapped)
									and not fits(d.Text, d.TextSize, scale, w, h, d.TextWrapped)
								then
									seen[source] = true
									local need = visible(d.Text) * d.TextSize * CHAR * scale
									table.insert(
										long,
										string.format("%s: %q -> %q (%.0f px of text in %.0f)", name, source, d.Text, need, w)
									)
								end
							end
						end
					end
					c:Close(name)
				end
				expectClean(c)
				table.sort(long)
				local problems = {}
				if #overflow > 0 then
					table.insert(problems, "off-screen on 568x320:\n  " .. table.concat(overflow, "\n  "))
				end
				if #long > 0 then
					table.insert(problems, #long .. " translations too long for their label:\n  " .. table.concat(long, "\n  "))
				end
				if #problems > 0 then
					error(table.concat(problems, "\n\n"))
				end
			end)
		end
	end)

	describe("Localize coverage", function()
		it("translates every text a new and a veteran player see", function()
			local sink = { list = {}, where = {} }

			-- A new player: the first session and every screen opened once.
			do
				local h = TestKernel.new({ systems = allSystems() })
				local player = h:Join()
				local c = ClientHarness.new(h, player, { localeId = "es-mx" })
				c:Advance(10)
				local kept = keptFor(c)
				collect(c, kept, sink, "new player HUD")
				local manifest = c:require(c.clientFolder.Manifest)
				for _, name in manifest.Screens do
					if name ~= "MonsterDetail" then
						c:Open(name)
						c:Advance(0.5)
						collect(c, kept, sink, "new player " .. name)
						c:Close(name)
					end
				end
				c:ClearProblems()
			end

			-- A veteran: every button on every screen, following one confirmation.
			local h = TestKernel.new({ systems = allSystems() })
			local player = h:Join()
			local ids = veteran(h, player)
			local c = ClientHarness.new(h, player, { localeId = "es-mx" })
			c:Advance(2)
			local kept = keptFor(c)
			collect(c, kept, sink, "veteran HUD")
			local manifest = c:require(c.clientFolder.Manifest)
			for _, name in manifest.Screens do
				local params = if name == "MonsterDetail" then { id = ids[1] } else nil
				local root = c:Open(name, params)
				c:Advance(0.5)
				collect(c, kept, sink, name)
				local count = math.min(#c:Buttons(root), 60)
				for i = 1, count do
					root = c:Open(name, params)
					c:Advance(0.2)
					local button = c:Buttons(root)[i]
					if not button then
						break
					end
					local before = {}
					for _, b in c:Buttons(c.kernel.UI.Top) do
						before[b] = true
					end
					c:Click(button)
					c:Advance(1)
					collect(c, kept, sink, name .. " button " .. i)
					for _, b in c:Buttons(c.kernel.UI.Top) do
						if not before[b] then
							c:Click(b)
							c:Advance(1)
							collect(c, kept, sink, name .. " button " .. i .. " confirm")
							break
						end
					end
					if c.kernel.Router:Current() then
						c:Close()
					end
				end
				c:Close(name)
			end
			c:ClearProblems()
			finish(sink)
		end)
	end)
end
