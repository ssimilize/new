--[[
	SoundCompat (Foundry adoption lane 1d): the Soundscape controller's music chain and ambience
	beds now come from the vendored Score and Soundscape packages (Logic/Audio.FoundrySound). The
	old rules survive verbatim in tests/runtime/OldAudio.luau (Logic/Audio at Ranch main f1dab15);
	this spec proves the new path hands the Audio kit exactly what the old one did:
	  - decisions: every context (flags, phase, weather, event; booleans and other truthy values),
	    in two orders through one live Soundscape instance: the same chain, the same bed levels in
	    the same iteration order, the same fountain level, bit for bit;
	  - frames: two booted clients walk the same scripted day (every area x weather x phase, the
	    combat and event themes, Music and Sfx toggled off and on), one on the packages and one on
	    OldAudio, and every Sound and SoundGroup matches on every frame.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")

	local Logic = t.Shared("Logic.Audio")
	local ServerFoundry = t.Server("Kernel.ServerFoundry")
	local Bus = t.Server("Kernel.Bus")
	local Api = t.Shared("Kernel.Api")
	local Rng = t.Shared("Logic.Rng")

	local WEATHERS = {
		"clear",
		"rain",
		"heatwave",
		"thunderstorm",
		"snow",
		"bloodmoon",
		"starfall",
		"lanternnight",
		"pollenstorm",
		"beachday",
		"aurora",
	}
	local FLAGS = { "raid", "racing", "battle", "stampede", "reef", "sky", "hub" }
	local BED_KEYS = { "AmbienceBirds", "AmbienceCrickets", "AmbienceWind", "AmbienceRain", "AmbienceHubCrowd", "AmbienceReef" }

	-- The frozen old rules, loaded as if they sat at Shared.Logic.Audio (their requires resolve there).
	local function oldAudio()
		local proxy = t.Loader.game:GetService("ReplicatedStorage").Shared.Logic.Audio
		local chunk = luau.load(fs.readFile(t.Root .. "/tests/runtime/OldAudio.luau"), {
			debugName = "tests/runtime/OldAudio.luau",
			environment = { script = proxy, require = t.Loader.require },
		})
		return chunk()
	end
	local Old = oldAudio()

	local function foundry()
		return ServerFoundry.new({
			folder = t.Loader.game:GetService("ReplicatedStorage").Shared:FindFirstChild("Foundry"),
			requireModule = t.Loader.require,
			Bus = Bus.new(Api.Topics),
			serverTime = function()
				return 1234.5
			end,
			warn = function() end,
			print = function() end,
		})
	end

	-- Every context: 2^7 flag sets x phase x weather (unset, the 11 kinds, an unknown one) x event
	-- (none, the five themes, an unknown one). Odd states use truthy non-booleans, as a Preview may.
	local function allStates(): { any }
		local weathers = table.clone(WEATHERS)
		table.insert(weathers, "fog")
		table.insert(weathers, false) -- unset
		local events = { false, "unknownfest" }
		for event in Old.EventMusic do
			table.insert(events, event)
		end
		table.sort(events, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local states = {}
		for mask = 0, 2 ^ #FLAGS - 1 do
			for night = 0, 1 do
				for _, weather in weathers do
					for _, event in events do
						local odd = #states % 2 == 1
						local s = {}
						for i, flag in FLAGS do
							if bit32.btest(mask, 2 ^ (i - 1)) then
								s[flag] = if odd then i else true
							elseif odd then
								s[flag] = false
							end
						end
						if night == 1 then
							s.night = if odd then "yes" else true
						end
						s.weather = if weather then weather else nil
						s.event = if event then event else nil
						table.insert(states, s)
					end
				end
			end
		end
		return states
	end

	local function keysInOrder(map): string
		local out = {}
		for key, value in map do
			table.insert(out, key .. "=" .. string.format("%.17g", value))
		end
		return table.concat(out, ",")
	end

	local function chainText(chain): string
		return table.concat(chain, ",")
	end

	describe("SoundCompat", function()
		it("builds a valid score and scape from Logic/Audio's rules", function()
			local f = foundry()
			local Score, Scape = f.packages.Score, f.packages.Soundscape
			expect(Score ~= nil and Scape ~= nil).toBe(true)
			expect(Score.validate(Logic.ScoreDef())).toEqual({})
			expect(Scape.validate(Logic.ScapeDef())).toEqual({})
			-- every key the old chains name has a theme
			local named = {}
			for _, theme in Logic.MusicThemes do
				for _, key in theme.keys do
					named[key] = true
				end
			end
			for _, key in Old.EventMusic do
				expect(named[key]).toBe(true)
			end
			for _, key in { "MusicRaid", "MusicRacing", "MusicBattle", "MusicStampede", "MusicReef", "MusicSkyIslands", "MusicHub" } do
				expect(named[key]).toBe(true)
			end
		end)

		it("decides the same chain, beds and fountain as OldAudio for every context, bit for bit", function()
			local f = foundry()
			local runner, err = Logic.FoundrySound(f.packages.Score, f.packages.Soundscape, f.adapter("Soundscape"))
			expect(err).toBeNil()
			local states = allStates()
			expect(#states).toBe(128 * 2 * 13 * 7)
			-- the enumeration order, then a seeded shuffle, through one live Soundscape instance
			local order = {}
			for i = 1, #states do
				order[i] = i
			end
			local shuffled = table.clone(order)
			local rng = Rng.new(1729)
			for i = #shuffled, 2, -1 do
				local j = math.floor(rng:Next() * i) + 1
				shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
			end
			local compared, mismatches = 0, {}
			for _, walk in { order, shuffled } do
				for _, index in walk do
					local s = states[index]
					local beds, fountain = runner.Beds(s, 0.5)
					local chain = runner.Music(s)
					local oldBeds = Old.Beds(s)
					local oldFountain = if s.sky or s.reef then 0 else 1
					local same = chainText(chain) == chainText(Old.MusicChain(s))
						and keysInOrder(beds) == keysInOrder(oldBeds)
						and fountain == oldFountain
					for _, key in BED_KEYS do
						same = same and beds[key] == oldBeds[key]
					end
					compared += 1
					if not same and #mismatches < 5 then
						table.insert(mismatches, string.format("state %d: %s | %s", index, chainText(chain), keysInOrder(beds)))
					end
				end
			end
			expect(compared).toBe(2 * 128 * 2 * 13 * 7)
			expect(table.concat(mismatches, "\n")).toBe("")
		end)

		it("keeps an empty id falling through the chain exactly as before", function()
			local f = foundry()
			local runner = Logic.FoundrySound(f.packages.Score, f.packages.Soundscape, f.adapter("Soundscape"))
			local music = {}
			for _, theme in Logic.MusicThemes do
				for _, key in theme.keys do
					music[key] = true
				end
			end
			local keys = {}
			for key in music do
				table.insert(keys, key)
			end
			table.sort(keys)
			local states = allStates()
			local rng = Rng.new(99)
			for _ = 1, 64 do
				local sounds = {}
				for _, key in keys do
					sounds[key] = if rng:Next() < 0.5 then "" else "rbxassetid://1"
				end
				for _ = 1, 200 do
					local s = states[math.floor(rng:Next() * #states) + 1]
					expect(Logic.First(sounds, runner.Music(s))).toBe(Old.First(sounds, Old.MusicChain(s)))
				end
			end
		end)
	end)

	describe("SoundCompat client", function()
		local function allSystems()
			local list = {}
			for _, name in t.Server("Manifest").Systems do
				if name ~= "World" then
					table.insert(list, name)
				end
			end
			return list
		end

		-- The scripted day: every area x weather by day then by night, then the combat and event
		-- themes; Music off for a stretch, Sfx off for another, both off for a third.
		local function script(): { any }
			local areas = {
				{},
				{ hub = true },
				{ sky = true },
				{ sky = true, hub = true },
				{ reef = true },
			}
			local out = {}
			for _, night in { false, true } do
				for _, area in areas do
					for _, weather in WEATHERS do
						local s = table.clone(area)
						s.night = night
						s.weather = weather
						table.insert(out, s)
					end
				end
			end
			for _, s in
				{
					{ raid = true, weather = "rain" },
					{ racing = true, hub = true },
					{ battle = true, night = true },
					{ stampede = true, sky = true },
					{ event = "frostfall", weather = "snow" },
					{ event = "lunarlanterns", night = true, hub = true },
					{ event = "springbloom", sky = true },
					{ event = "summersplash", reef = true },
					{ event = "harvestmoon", night = true, weather = "thunderstorm" },
					{ weather = "clear" },
				}
			do
				table.insert(out, s)
			end
			return out
		end

		local SETTINGS = {
			[30] = { music = false },
			[46] = { music = true },
			[60] = { sfx = false },
			[76] = { sfx = true },
			[90] = { music = false, sfx = false },
			[98] = { music = true, sfx = true },
		}
		local HOLD, FRAME = 2, 1 / 20

		local function snapshot(c): string
			local parts = {}
			local service = c.globals.game:GetService("SoundService")
			local places = { service, c.globals.workspace:FindFirstChild("AudioEmitters") }
			for _, place in places do
				for _, d in if place then place:GetDescendants() else {} do
					if d:IsA("Sound") then
						table.insert(
							parts,
							string.format(
								"%s|%s|%.17g|%s|%s|%.17g",
								d.Name,
								d.SoundId,
								d.Volume,
								tostring(d.Playing),
								tostring(d.Looped),
								d.PlaybackSpeed
							)
						)
					elseif d:IsA("SoundGroup") then
						table.insert(parts, string.format("group %s|%.17g", d.Name, d.Volume))
					end
				end
			end
			return table.concat(parts, "\n")
		end

		local function run(useOld: boolean): ({ string }, { string }, boolean)
			math.randomseed(4101)
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local scape = c.kernel:GetController("Soundscape")
			local adopted = scape.Adopted()
			if useOld then
				scape.Legacy = Old
				scape.Wire(nil)
			end
			local frames = {}
			for i, s in script() do
				for key, value in SETTINGS[i] or {} do
					c:Request("Settings.Set", { key = key, value = value })
				end
				scape.Preview(s)
				for _ = 1, HOLD / FRAME do
					c:Advance(FRAME, FRAME)
					table.insert(frames, snapshot(c))
				end
			end
			local problems = c:Problems({ "%[Soundscape%] Foundry Score / Soundscape are not vendored" })
			local played = table.clone(c.world.log.sounds)
			table.insert(frames, "one-shots: " .. table.concat(played, ","))
			return frames, problems, adopted
		end

		it("plays the same Sounds on every frame of a scripted day as OldAudio", function()
			local new, newProblems, adopted = run(false)
			expect(adopted).toBe(true)
			expect(table.concat(newProblems, "\n")).toBe("")
			local old, oldProblems, _ = run(true)
			expect(table.concat(oldProblems, "\n")).toBe("")
			expect(#new).toBe(#old)
			expect(#new > 4000).toBe(true)
			local audible = 0
			for i = 1, #new do
				if new[i] ~= old[i] then
					error(string.format("frame %d differs:\nnew:\n%s\nold:\n%s", i, new[i], old[i]))
				end
				if string.find(new[i], "|true|true|", 1, true) then
					audible += 1
				end
			end
			expect(audible > #new / 2).toBe(true) -- loops really played
		end)

		it("warns once and stays on Logic/Audio without the packages, and lists what it keeps", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local scape = c.kernel:GetController("Soundscape")
			expect(scape.Adopted()).toBe(true)
			local F = c.kernel.Foundry
			scape.Wire({ packages = { Contract = F.packages.Contract, Score = F.packages.Score }, adapter = F.adapter })
			expect(scape.Adopted()).toBe(false)
			scape.Wire({ packages = {}, adapter = F.adapter })
			scape.Preview({ weather = "rain", hub = true })
			c:Advance(4)
			local warnings = 0
			for _, w in c.world.warnings do
				if string.find(w, "[Soundscape]", 1, true) then
					warnings += 1
				end
			end
			expect(warnings).toBe(1)
			local service = c.globals.game:GetService("SoundService")
			local playing = {}
			for _, place in { service, c.globals.workspace:FindFirstChild("AudioEmitters") } do
				for _, d in if place then place:GetDescendants() else {} do
					if d:IsA("Sound") and d.Looped and d.Playing then
						playing[d.Name] = true
					end
				end
			end
			expect(playing.MusicHub).toBe(true)
			expect(playing.AmbienceRain).toBe(true)
			expect(playing.AmbienceHubCrowd).toBe(true)
			scape.Wire(F)
			expect(scape.Adopted()).toBe(true)
			local count = 0
			for key, why in scape.NotAdopted do
				count += 1
				expect(type(key) == "string" and type(why) == "string" and #why >= 20).toBe(true)
			end
			expect(count >= 4).toBe(true)
		end)
	end)
end
