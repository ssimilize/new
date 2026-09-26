--[[
	Vfx: the particle effect presets (Config/Vfx, Config/VfxSprites) and the client module that
	builds them (Visuals/Vfx, hooked into MonsterModel, World and the Landmarks controller).
	Config integrity first, then behaviour through the real client (ClientHarness).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Presets = t.Shared("Config.Vfx")
	local SpriteIds = t.Shared("Config.VfxSprites")
	local Appearance = t.Shared("Logic.Appearance")

	-- The whitelisted spec keys (Config/Vfx header).
	local KEYS = {
		sprite = true,
		grey = true,
		color = true,
		useColor = true,
		rate = true,
		emit = true,
		lifetime = true,
		size = true,
		transparency = true,
		speed = true,
		spread = true,
		accel = true,
		drag = true,
		rot = true,
		rotSpeed = true,
		lightEmission = true,
		lightInfluence = true,
		orientation = true,
		direction = true,
		shape = true,
		shapeStyle = true,
		shapeInOut = true,
		zOffset = true,
		lockedToPart = true,
		at = true,
		offset = true,
		box = true,
		core = true,
		night = true,
	}
	local ENUMS = {
		orientation = { "FacingCamera", "FacingCameraWorldUp", "VelocityParallel", "VelocityPerpendicular" },
		direction = { "Top", "Bottom", "Front", "Back", "Left", "Right" },
		shape = { "Box", "Sphere", "Cylinder", "Disc" },
		shapeStyle = { "Volume", "Surface" },
		shapeInOut = { "Outward", "Inward", "InAndOut" },
	}
	local MONSTER_AT = { feet = true, core = true, head = true, body = true }

	-- Every table of effects, with what kind of effect its specs are.
	local function groups()
		local list = {}
		for id, specs in Presets.Auras do
			table.insert(list, { name = "Auras." .. id, specs = specs, kind = "monster" })
		end
		for id, specs in Presets.Mutations do
			table.insert(list, { name = "Mutations." .. id, specs = specs, kind = "monster" })
		end
		for id, specs in Presets.Variants do
			table.insert(list, { name = "Variants." .. id, specs = specs, kind = "monster" })
		end
		for id, specs in Presets.Rarity do
			table.insert(list, { name = "Rarity." .. id, specs = specs, kind = "monster" })
		end
		for id, specs in Presets.Landmarks do
			table.insert(list, { name = "Landmarks." .. id, specs = specs, kind = "landmark" })
		end
		for id, specs in Presets.Bursts do
			table.insert(list, { name = "Bursts." .. id, specs = specs, kind = "burst" })
		end
		for id, specs in Presets.Mastery do -- 3.3 mastery auras
			table.insert(list, { name = "Mastery." .. id, specs = specs, kind = "monster" })
		end
		return list
	end

	local function live(specs): number
		local n = 0
		for _, spec in specs do
			n += (spec.rate or 0) * spec.lifetime[2]
		end
		return n
	end

	local function checkKeys(keys, label: string, problems)
		if type(keys) == "number" then
			return
		end
		if type(keys) ~= "table" or #keys < 1 or #keys > 20 then
			table.insert(problems, label .. ": needs a number or 1-20 keys")
			return
		end
		if #keys == 1 then
			table.insert(problems, label .. ": a sequence needs keys at 0 and 1")
			return
		end
		if keys[1][1] ~= 0 or keys[#keys][1] ~= 1 then
			table.insert(problems, label .. ": keys must start at t = 0 and end at t = 1")
		end
		for i = 2, #keys do
			if keys[i][1] <= keys[i - 1][1] then
				table.insert(problems, label .. ": key times must rise")
			end
		end
	end

	-- A sprite that is uploaded (and has the grey twin when the spec wants it).
	local function available(spec): boolean
		local entry = SpriteIds[spec.sprite]
		local id = entry and (if spec.grey then entry.grey else entry.color)
		return type(id) == "string" and id ~= ""
	end

	local function countAvailable(specs): number
		local n = 0
		for _, spec in specs or {} do
			if available(spec) then
				n += 1
			end
		end
		return n
	end

	local function expectClean(c)
		local problems = c:Problems()
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	local function emitters(root): { any }
		local list = {}
		for _, d in root:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				table.insert(list, d)
			end
		end
		return list
	end

	local function look(line: string, fields)
		local a = Appearance.Preview(line)
		for k, v in fields do
			a[k] = v
		end
		return a
	end

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	describe("Vfx config", function()
		it("covers every element and every mutation, and landmarks are real hub buildings", function()
			for _, e in Config.Elements.List do
				expect(type(Presets.Auras[e.id]) == "table" and #Presets.Auras[e.id] > 0).toBe(true)
			end
			for _, m in Config.Mutations.List do
				expect(type(Presets.Mutations[m.id]) == "table" and #Presets.Mutations[m.id] > 0).toBe(true)
			end
			for id in Presets.Auras do
				expect(Config.Elements.ById[id] ~= nil).toBe(true)
			end
			for id in Presets.Mutations do
				expect(Config.Mutations.ById[id] ~= nil).toBe(true)
			end
			for id in Presets.Rarity do
				expect(Config.Rarities.ById[id] ~= nil).toBe(true)
			end
			local hub = { skyGate = true }
			for _, def in Config.World.Hub do
				hub[def.id] = true
			end
			for id in Presets.Landmarks do
				if not hub[id] then
					error("landmark " .. id .. " is not a Config.World.Hub id")
				end
			end
			expect(Presets.Variants.shiny ~= nil and Presets.Variants.rainbow ~= nil).toBe(true)
			for _, name in { "hatch", "evolve", "monsterLevelUp", "ranchLevelUp", "rebirth", "coins", "hearts" } do
				expect(type(Presets.Bursts[name]) == "table" and #Presets.Bursts[name] > 0).toBe(true)
			end
		end)

		it("defines the night glow over real sprites with sane numbers", function()
			local N = Presets.Night
			expect(N ~= nil).toBe(true)
			expect(N.boost > 0 and N.cap <= 1).toBe(true)
			expect(N.dawn[1] < N.dawn[2] and N.dawn[2] < N.dusk[1] and N.dusk[1] < N.dusk[2]).toBe(true)
			for sprite, weight in N.sprites do
				expect({ sprite, Presets.Sprites[sprite] ~= nil }).toEqual({ sprite, true })
				expect(weight > 0 and weight <= 1).toBe(true)
			end
			-- Matte sprites stay lit like the world: smoke and leaves must not glow in the dark.
			for _, sprite in { "leaf", "petal", "pebble", "puff", "confetti", "heart", "coin" } do
				expect({ sprite, N.sprites[sprite] }).toEqual({ sprite, nil })
			end
			for _, group in groups() do
				for i, spec in group.specs do
					if spec.night ~= nil then
						local ok = type(spec.night) == "number" and spec.night >= 0 and spec.night <= 1
						expect({ group.name, i, ok }).toEqual({ group.name, i, true })
					end
				end
			end
		end)

		it("uses only sprites from art/vfx/SPRITES.md, with the same TINT marks", function()
			local fs = require("@lune/fs")
			local md = fs.readFile(t.Root .. "/art/vfx/SPRITES.md")
			local listed = {}
			for line in string.gmatch(md, "[^\n]+") do
				local name = string.match(line, "^|%s*([%w_]+)%s*|")
				if name and name ~= "name" then
					listed[name] = string.find(line, "TINT", 1, true) ~= nil
				end
			end
			for name, tint in listed do
				expect({ name, Presets.Sprites[name] and Presets.Sprites[name].tint }).toEqual({ name, tint })
			end
			for name in Presets.Sprites do
				expect({ name, listed[name] ~= nil }).toEqual({ name, true })
			end
			-- The generated id module only names listed sprites, and a grey id only for TINT ones.
			for name, entry in SpriteIds do
				expect({ name, Presets.Sprites[name] ~= nil }).toEqual({ name, true })
				expect(string.match(entry.color, "^rbxassetid://%d+$") ~= nil).toBe(true)
				if entry.grey ~= nil then
					expect({ name, Presets.Sprites[name].tint }).toEqual({ name, true })
					expect(string.match(entry.grey, "^rbxassetid://%d+$") ~= nil).toBe(true)
				end
			end
		end)

		it("keeps every spec to the whitelisted keys and the engine rules", function()
			local problems = {}
			for _, group in groups() do
				for i, spec in group.specs do
					local label = group.name .. "[" .. i .. "]"
					for k in spec do
						if not KEYS[k] then
							table.insert(problems, label .. ": unknown key " .. tostring(k))
						end
					end
					local sprite = Presets.Sprites[spec.sprite]
					if not sprite then
						table.insert(problems, label .. ": unknown sprite " .. tostring(spec.sprite))
					elseif spec.grey and not sprite.tint then
						table.insert(problems, label .. ": " .. spec.sprite .. " has no grey twin")
					end
					if spec.grey and spec.color == nil then
						table.insert(problems, label .. ": a grey sprite needs a color")
					end
					for key, names in ENUMS do
						if spec[key] ~= nil and not table.find(names, spec[key]) then
							table.insert(problems, label .. ": bad " .. key .. " " .. tostring(spec[key]))
						end
					end
					local lt = spec.lifetime
					if type(lt) ~= "table" or not (lt[1] > 0 and lt[1] <= lt[2]) then
						table.insert(problems, label .. ": lifetime must be { min > 0, max >= min }")
					end
					-- Rule: daylight LightEmission 0.15 - 0.3; above 0.5 only for portal cores.
					local le = spec.lightEmission
					if spec.core then
						if group.kind ~= "landmark" then
							table.insert(problems, label .. ": core is for landmark portals only")
						end
						if le == nil or le > 1 then
							table.insert(problems, label .. ": a core's lightEmission must be set, <= 1")
						end
					elseif le ~= nil and (le < 0.15 or le > 0.3) then
						table.insert(problems, label .. ": lightEmission " .. le .. " outside 0.15 - 0.3")
					end
					-- Rule: Size and Transparency are sequences; transparency fades in fast, out slow.
					checkKeys(spec.size, label .. " size", problems)
					local tr = spec.transparency or Presets.Fade
					checkKeys(tr, label .. " transparency", problems)
					if type(tr) == "table" and #tr >= 2 then
						local minT, minAt = math.huge, 0
						for _, k in tr do
							if k[2] < minT then
								minT, minAt = k[2], k[1]
							end
						end
						if tr[1][2] < 0.6 or tr[#tr][2] < 1 or minAt > 0.35 then
							table.insert(problems, label .. ": transparency must start >= 0.6, reach its lowest by 0.35, end at 1")
						end
					end
					if type(spec.color) == "table" then
						checkKeys(spec.color, label .. " color", problems)
					end
					-- Persistent effects stream (rate); bursts only :Emit.
					if group.kind == "burst" then
						if spec.rate ~= nil or type(spec.emit) ~= "number" or spec.emit < 1 then
							table.insert(problems, label .. ": a burst has emit >= 1 and no rate")
						end
						if spec.at ~= nil or spec.offset ~= nil or spec.core ~= nil then
							table.insert(problems, label .. ": a burst has no at / offset / core")
						end
					else
						if spec.emit ~= nil or type(spec.rate) ~= "number" or spec.rate <= 0 then
							table.insert(problems, label .. ": a persistent effect has a rate > 0 and no emit")
						end
					end
					if spec.useColor and group.kind ~= "burst" then
						table.insert(problems, label .. ": useColor is for bursts")
					end
					if group.kind == "monster" then
						if not MONSTER_AT[spec.at] then
							table.insert(problems, label .. ": monster at must be feet / core / head / body")
						end
						if spec.box ~= nil then
							table.insert(problems, label .. ": box is for landmarks and bursts")
						end
						if spec.shape ~= nil and spec.at ~= "body" then
							table.insert(problems, label .. ": a shape needs at = body (a part)")
						end
					elseif group.kind == "landmark" then
						if type(spec.at) ~= "table" or #spec.at ~= 3 or spec.offset ~= nil then
							table.insert(problems, label .. ": a landmark at is { x, y, z } fractions, no offset")
						end
					end
				end
			end
			if #problems > 0 then
				error(table.concat(problems, "\n"))
			end
		end)

		it("stays inside the live-particle budget", function()
			local worstAura = 0
			for id, specs in Presets.Auras do
				local n = live(specs)
				if n > Presets.Budget.aura then
					error(string.format("aura %s has %.2f live particles", id, n))
				end
				worstAura = math.max(worstAura, n)
			end
			local mutations = {}
			for _, specs in Presets.Mutations do
				table.insert(mutations, live(specs))
			end
			table.sort(mutations, function(a, b)
				return a > b
			end)
			expect(worstAura + mutations[1] + mutations[2] <= Presets.Budget.withMutations).toBe(true)
			for id, specs in Presets.Landmarks do
				local n = live(specs)
				if n > Presets.Budget.landmark then
					error(string.format("landmark %s has %.2f live particles", id, n))
				end
			end
			for _, group in { Presets.Variants, Presets.Rarity } do
				for _, specs in group do
					expect(live(specs) <= 3).toBe(true)
				end
			end
			-- 3.3: a mastery aura sits on top of everything above, so it stays a light sprinkle.
			for id, specs in Presets.Mastery do
				if live(specs) > Presets.Budget.mastery then
					error(string.format("mastery aura %s has %.2f live particles", id, live(specs)))
				end
			end
			for _, item in Config.Mastery.ItemById do
				if item.kind == "aura" then
					expect(type(Presets.Mastery[item.vfx]) == "table" and #Presets.Mastery[item.vfx] > 0).toBe(true)
				end
			end
			for _, tier in Config.Mastery.Tiers do
				if tier.aura then
					expect(type(Presets.Mastery[tier.aura]) == "table").toBe(true)
				end
			end
		end)
	end)

	describe("Vfx client", function()
		it("gives a built monster its element aura, mutation, shiny and rarity emitters", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
			local a = look("cindlet", { muts = { "charged" }, variant = 1, rarity = 5 })
			local model = MonsterModel.Build(a, { anchored = true })
			local list = emitters(model)
			local expected = countAvailable(Presets.Auras.ember)
				+ countAvailable(Presets.Mutations.charged)
				+ countAvailable(Presets.Variants.shiny)
				+ countAvailable(Presets.Rarity.legendary)
			expect(expected >= 3).toBe(true) -- flame, bolt, star are uploaded
			expect(#list).toBe(expected)
			for _, e in list do
				expect(string.match(e.Texture, "^rbxassetid://%d+$") ~= nil).toBe(true)
				expect(e.Rate > 0).toBe(true)
				expect(e.Enabled).toBe(true)
			end
			-- The old placeholder Fire / Sparkles / Smoke decorations are gone.
			for _, d in model:GetDescendants() do
				expect(d:IsA("Fire") or d:IsA("Sparkles") or d:IsA("Smoke")).toBe(false)
			end
			expectClean(c)
		end)

		it("mixes two elements at half rate each", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
			local flameId = SpriteIds.flame.color
			local function flameRate(elements)
				local model = MonsterModel.Build(look("cindlet", { elements = elements }), { anchored = true })
				for _, e in emitters(model) do
					if e.Texture == flameId then
						return e.Rate
					end
				end
				return nil
			end
			local full = flameRate({ "ember" })
			expect(full).toBe(Presets.Auras.ember[1].rate)
			expect(flameRate({ "ember", "tide" })).toBe(full / 2)
			expectClean(c)
		end)

		it("attaches nothing in a ViewportMonster or with vfx = false (statues)", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local ViewportMonster = c:require(c.clientFolder.UI.Components.ViewportMonster)
			local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
			local gui = c.Instance.new("ScreenGui")
			gui.Parent = c.playerGui
			local a = look("cindlet", { muts = { "charged", "soaked" }, variant = 2, rarity = 6 })
			c.world:Run(function()
				local vm = ViewportMonster.new({ Size = c.globals.UDim2.fromOffset(200, 200), Parent = gui })
				vm:SetAppearance(a)
			end)
			c:Advance(0.5)
			expect(#gui:GetDescendants() > 1).toBe(true) -- the model is there
			expect(#emitters(gui)).toBe(0)
			expect(#emitters(MonsterModel.Build(a, { vfx = false }))).toBe(0)
			expect(#emitters(MonsterModel.Build(a)) > 0).toBe(true)
			expectClean(c)
		end)

		it("skips a sprite that is not uploaded without an error", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local Shared = c.world.game:GetService("ReplicatedStorage").Shared
			local Sprites = c:require(Shared.Config.VfxSprites)
			local Vfx = c:require(c.clientFolder.Visuals.Vfx)
			local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
			local saved = Sprites.flame
			Sprites.flame = nil
			local model = MonsterModel.Build(look("cindlet", {}), { anchored = true })
			Sprites.flame = { color = "" } -- a broken row is skipped too
			local model2 = MonsterModel.Build(look("cindlet", {}), { anchored = true })
			Sprites.flame = saved
			expect(available(Presets.Auras.ember[1])).toBe(true) -- the flame is the one taken away
			for _, m in { model, model2 } do
				expect(#emitters(m)).toBe(countAvailable(Presets.Auras.ember) - 1)
				for _, e in emitters(m) do
					expect(e.Texture ~= saved.color and e.Texture ~= "").toBe(true)
				end
			end
			-- Coins have no uploaded sprite yet: nothing fires and World keeps its plain burst.
			if not available(Presets.Bursts.coins[1]) then
				expect(Vfx.Burst("coins", c.globals.Vector3.new(0, 5, 0))).toBe(0)
			end
			expect(Vfx.Burst("nope", c.globals.Vector3.new(0, 5, 0))).toBe(0)
			expect(Vfx.AttachLandmark(model, "nope")).toBe(nil)
			expectClean(c)
		end)

		it("glows glowing sprites at night, leaves matte ones alone, and follows the clock", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local Vfx = c:require(c.clientFolder.Visuals.Vfx)
			local MonsterModel = c:require(c.clientFolder.Visuals.MonsterModel)
			local N = Presets.Night
			-- The test world may start at night; the Landmarks controller follows the clock, so set it.
			local lighting = c.world.game:GetService("Lighting")
			lighting.ClockTime = 14

			-- The curve: day, night, and halfway through dusk and dawn.
			expect(Vfx.NightFromClock(14)).toBe(0)
			expect(Vfx.NightFromClock(0.5)).toBe(1)
			expect(math.abs(Vfx.NightFromClock((N.dusk[1] + N.dusk[2]) / 2) - 0.5) < 1e-6).toBe(true)
			expect(math.abs(Vfx.NightFromClock((N.dawn[1] + N.dawn[2]) / 2) - 0.5) < 1e-6).toBe(true)
			expect(Vfx.NightFromClock(N.dusk[1] + 0.5) < Vfx.NightFromClock(N.dusk[2] - 0.5)).toBe(true)

			-- An ember monster's flame glows at night; a sprout monster's leaves do not.
			local sprout
			for _, line in Config.Species.Lines do
				if line.elements[1] == "sprout" and #line.elements == 1 then
					sprout = line.id
					break
				end
			end
			local ember = MonsterModel.Build(look("cindlet", {}), { anchored = true })
			local leafy = MonsterModel.Build(look(sprout, {}), { anchored = true })
			local flameSpec = Presets.Auras.ember[1]
			expect(flameSpec.sprite).toBe("flame")
			local function byTexture(model, id)
				for _, e in emitters(model) do
					if e.Texture == id then
						return e
					end
				end
				return nil
			end
			local flame = byTexture(ember, SpriteIds.flame.color)
			expect(flame ~= nil).toBe(true)
			local dayLeaves = {}
			for _, e in emitters(leafy) do
				dayLeaves[e] = { e.LightEmission, e.LightInfluence }
			end
			expect(flame.LightEmission).toBe(flameSpec.lightEmission)

			Vfx.SetNight(1)
			local want = math.min(flameSpec.lightEmission + N.boost, math.max(flameSpec.lightEmission, N.cap))
			expect(math.abs(flame.LightEmission - want) < 1e-6).toBe(true)
			expect(flame.LightEmission > flameSpec.lightEmission).toBe(true)
			expect(flame.LightInfluence).toBe(0)
			expect(next(dayLeaves) ~= nil).toBe(true)
			for e, day in dayLeaves do
				expect({ e.LightEmission, e.LightInfluence }).toEqual(day)
			end

			Vfx.SetNight(0)
			expect(flame.LightEmission).toBe(flameSpec.lightEmission)

			-- The Landmarks controller follows Lighting.ClockTime.
			lighting.ClockTime = 0.5
			expect(math.abs(flame.LightEmission - want) < 1e-6).toBe(true)
			lighting.ClockTime = 14
			expect(flame.LightEmission).toBe(flameSpec.lightEmission)
			expectClean(c)
		end)

		it("in low graphics drops other plots' auras and halves the rest", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p1 = h:Join()
			local p2 = h:Join()
			local Monsters = h:System("Monsters")
			local mine = Monsters:Create(p1, { line = "cindlet", rarity = 1, muts = { "soaked" } }, "test", true)
			local theirs = Monsters:Create(p2, { line = "cindlet", rarity = 1 }, "test", true)
			h:Call(p1, "Ranch.Assign", { id = mine.id, pen = 1 })
			h:Call(p2, "Ranch.Assign", { id = theirs.id, pen = 1 })
			local c = ClientHarness.new(h, p1)
			c:Advance(2)
			local function modelOf(id: string, owner: number)
				local plots = c:Store("global.Plots")
				local folder = c.world.workspace:FindFirstChild("WorldClient")
				for i, plot in plots do
					if plot.userId == owner then
						local view = folder:FindFirstChild("Plot" .. i)
						for _, m in view:GetChildren() do
							if m:IsA("Model") and m:GetAttribute("Line") == "cindlet" then
								return m
							end
						end
					end
				end
				error("no pen model for " .. id)
			end
			local own, other = modelOf(mine.id, p1.UserId), modelOf(theirs.id, p2.UserId)
			local flameId, dropId = SpriteIds.flame.color, SpriteIds.droplet.color
			local function find(model, texture)
				for _, e in emitters(model) do
					if e.Texture == texture then
						return e
					end
				end
				error("no emitter with " .. texture)
			end
			expect(find(other, flameId).Enabled).toBe(true)
			expect(find(own, dropId).Rate).toBe(Presets.Mutations.soaked[1].rate)

			local ok = c:Request("Settings.Set", { key = "lowGraphics", value = true })
			expect(ok).toBe(true)
			c:Advance(1)
			expect(find(other, flameId).Enabled).toBe(false)
			expect(find(own, flameId).Enabled).toBe(true)
			expect(find(own, flameId).Rate).toBe(Presets.Auras.ember[1].rate)
			expect(find(own, dropId).Rate).toBe(Presets.Mutations.soaked[1].rate / 2)

			c:Request("Settings.Set", { key = "lowGraphics", value = false })
			c:Advance(1)
			expect(find(other, flameId).Enabled).toBe(true)
			expectClean(c)
		end)

		it("puts ambience on the landmarks and fires moment bursts", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(2)
			local holder = c.world.workspace:FindFirstChild("VfxClient")
			expect(holder ~= nil).toBe(true)
			for _, id in { "raidPortal", "skyGate", "starAltar" } do
				expect({ id, holder:FindFirstChild("Vfx_" .. id) ~= nil }).toEqual({ id, true })
			end
			local total = 0
			for _, folder in holder:GetChildren() do
				if string.sub(folder.Name, 1, 4) == "Vfx_" then
					total += #emitters(folder)
				end
			end
			expect(total > 0).toBe(true)

			-- Rebirth (the Rebirth screen publishes it) bursts round the character and at the altar.
			c.world:Run(function()
				c.kernel.Bus:Publish("Vfx.Burst", "rebirth")
			end)
			c:Advance(0.2)
			local bursts = holder:FindFirstChild("Bursts")
			expect(bursts ~= nil and #emitters(bursts) > 0).toBe(true)
			-- A ranch level-up from the server bursts round the character.
			local P = h:System("Progression")
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)), "test")
			c:Advance(1)
			local fired = 0
			for _, part in bursts:GetChildren() do
				if string.sub(part.Name, 1, 13) == "ranchLevelUp@" then
					fired += 1
				end
			end
			expect(fired).toBe(countAvailable(Presets.Bursts.ranchLevelUp))
			expectClean(c)
		end)
	end)
end
