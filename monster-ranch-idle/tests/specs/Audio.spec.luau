--[[
	Audio: the sound kit rules (Logic/Audio), the Config.Sounds schema, and the client kit
	(client/Audio, Audio/Voices, the Soundscape controller, the Studio SoundCheck screen) run in
	RobloxMock: silent with empty ids, then lit up by filling ids in at runtime.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Audio")
	local Vector3 = t.Roblox.Vector3

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function expectClean(c)
		local problems = c:Problems()
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	local function boot()
		local h = TestKernel.new({ systems = allSystems() })
		local p = h:Join()
		local c = ClientHarness.new(h, p)
		c:Advance(1)
		return h, p, c
	end

	-- Fills ids into the client's own Config.Sounds (the table the kit reads) and drops cached specs.
	local function fill(c, keys: { string })
		local sounds = c.kernel.Config.Sounds
		for i, key in keys do
			local entry = sounds[key]
			local id = "rbxassetid://" .. tostring(1000 + i)
			if type(entry) == "table" then
				entry.id = id
			else
				sounds[key] = id
			end
		end
		c:require(c.clientFolder.Audio).Refresh()
	end

	local function idOf(c, key: string): string
		local entry = c.kernel.Config.Sounds[key]
		return if type(entry) == "table" then entry.id else entry
	end

	local function count(list, value): number
		local n = 0
		for _, v in list do
			if v == value then
				n += 1
			end
		end
		return n
	end

	local function soundService(c)
		return c.globals.game:GetService("SoundService")
	end

	-- A loop layer's Sound: in SoundService, or on an emitter attachment when it is positional.
	local function loopSound(c, key: string)
		local places = { c.globals.game:GetService("SoundService"), c.globals.workspace:FindFirstChild("AudioEmitters") }
		for _, place in places do
			for _, d in place:GetDescendants() do
				if d:IsA("Sound") and d.Name == key and d.Looped then
					return d
				end
			end
		end
		return nil
	end

	describe("Config.Sounds", function()
		it("resolves every entry and keeps ids empty or rbxassetid", function()
			local n = 0
			for key, entry in Config.Sounds do
				local spec = Logic.Resolve(key, entry)
				expect(spec ~= nil).toBe(true)
				expect(table.find(Logic.Groups, spec.group) ~= nil).toBe(true)
				if not spec.empty then
					expect(string.match(spec.id, "^rbxassetid://%d+$") ~= nil).toBe(true)
				end
				n += 1
			end
			expect(n >= 60).toBe(true)
		end)

		it("has every key the rules and the game ask for", function()
			local needed = { "MusicRanch", "MusicRanchNight", "MusicHub", "MusicSkyIslands", "MusicBattle", "MusicStampede" }
			for key in Logic.UIKeys do
				table.insert(needed, key)
			end
			for i = 1, Config.Rarities.Count do
				for _, key in Logic.HatchChain(i, 2) do
					table.insert(needed, key)
				end
			end
			for key in Logic.Beds({}) do
				table.insert(needed, key)
			end
			for _, e in Config.Events.List do
				expect(Logic.EventMusic[e.id] ~= nil).toBe(true)
				table.insert(needed, Logic.EventMusic[e.id])
			end
			for _, line in Config.Species.Lines do
				table.insert(needed, Logic.VoiceKey(line.archetype))
			end
			for _, key in {
				"CoinTick",
				"Gem",
				"StarUp",
				"QuestComplete",
				"KO",
				"RainStart",
				"Thunder",
				"WindGust",
				"JarCollect",
				"Pet",
				"Eat",
				"FootstepSoft",
				"AmbienceFountain",
			} do
				table.insert(needed, key)
			end
			for _, key in needed do
				if Config.Sounds[key] == nil then
					error("Config.Sounds is missing " .. key)
				end
			end
		end)
	end)

	describe("Logic/Audio", function()
		it("fills defaults for plain strings and reads the table form", function()
			local plain = Logic.Resolve("Hit", "rbxassetid://5")
			expect(plain.id).toBe("rbxassetid://5")
			expect(plain.group).toBe("Effects")
			expect(plain.volume).toBe(0.6)
			expect(plain.looped).toBe(false)
			expect(plain.maxConcurrent).toBe(4)
			local music = Logic.Resolve("MusicHub", "")
			expect(music.empty).toBe(true)
			expect(music.group).toBe("Music")
			expect(music.looped).toBe(true)
			expect(music.maxConcurrent).toBe(1)
			local full = Logic.Resolve("Custom", {
				id = "x",
				volume = 0.3,
				pitch = { 1.2, 0.8 },
				group = "Voice",
				cooldown = 2,
				maxConcurrent = 2,
				duck = 0.4,
			})
			expect(full.pitchMin).toBe(0.8)
			expect(full.pitchMax).toBe(1.2)
			expect(full.group).toBe("Voice")
			expect(full.cooldown).toBe(2)
			expect(full.duck).toBe(0.4)
			expect(Logic.Resolve("One", { id = "x", pitch = 1.5 }).pitchMax).toBe(1.5)
			expect(Logic.Resolve("UIOpen", "").group).toBe("UI")
			expect(Logic.Resolve("Nope", nil)).toBeNil()
		end)

		it("maps the two toggles onto the five groups", function()
			local on = Logic.GroupVolumes({ music = true, sfx = true })
			for _, group in Logic.Groups do
				expect(on[group] > 0).toBe(true)
			end
			local noMusic = Logic.GroupVolumes({ music = false, sfx = true })
			expect(noMusic.Music).toBe(0)
			expect(noMusic.Ambience).toBe(0)
			expect(noMusic.Voice > 0).toBe(true)
			local noSfx = Logic.GroupVolumes({ music = true, sfx = false })
			expect(noSfx.Effects + noSfx.UI + noSfx.Voice).toBe(0)
			expect(noSfx.Music > 0).toBe(true)
			expect(Logic.GroupVolumes(nil).Music > 0).toBe(true)
		end)

		it("climbs a semitone per streak step and stops at an octave", function()
			expect(Logic.StreakPitch(1)).toBe(1)
			expect(math.abs(Logic.StreakPitch(2) - 2 ^ (1 / 12)) < 1e-9).toBe(true)
			expect(Logic.StreakPitch(13)).toBe(2)
			expect(Logic.StreakPitch(40)).toBe(2)
		end)

		it("pitches voices by stage, size and a fixed per-line offset", function()
			expect(Logic.Hash("cindlet")).toBe(Logic.Hash("cindlet"))
			expect(Logic.Hash("cindlet") ~= Logic.Hash("scorchmoth")).toBe(true)
			local baby = Logic.VoicePitch({ line = "cindlet", stage = 1, height = 3 })
			local adult = Logic.VoicePitch({ line = "cindlet", stage = 3, height = 3 })
			local big = Logic.VoicePitch({ line = "cindlet", stage = 3, height = 9 })
			expect(baby > adult).toBe(true)
			expect(adult > big).toBe(true)
			expect(Logic.VoicePitch({ line = "cindlet", stage = 3, height = 3 })).toBe(adult)
			local offset = Logic.VoicePitch({ line = "cindlet", stage = 3, height = 3 }) - 1
			expect(math.abs(offset) <= 0.06 + 1e-9).toBe(true)
			expect(Logic.VoiceKey("golem")).toBe("VoiceGolem")
			expect(Logic.VoiceKey(nil)).toBe("VoiceBlob")
		end)

		it("chains hatch stings from the variant down through the rarities", function()
			local chain = Logic.HatchChain(4, 2)
			expect(chain[1]).toBe("HatchRainbow")
			expect(chain[2]).toBe("HatchGolden")
			expect(chain[3]).toBe("HatchEpic")
			expect(chain[#chain]).toBe("HatchCommon")
			expect(Logic.HatchChain(6, 0)[1]).toBe("HatchMythic")
			expect(Logic.First({ HatchEpic = "", HatchRare = "rbxassetid://1" }, Logic.HatchChain(4, 0))).toBe("HatchRare")
			expect(Logic.First({}, { "A", "B" })).toBeNil()
		end)

		it("picks music by context priority and falls back to the ranch theme", function()
			expect(Logic.MusicChain({ battle = true, stampede = true, sky = true })[1]).toBe("MusicBattle")
			expect(Logic.MusicChain({ stampede = true })[1]).toBe("MusicStampede")
			local sky = Logic.MusicChain({ sky = true, hub = true, event = "frostfall" })
			expect(sky[1]).toBe("MusicSkyIslands")
			expect(sky[2]).toBe("MusicFrostfall")
			expect(table.find(sky, "MusicHub")).toBeNil()
			local night = Logic.MusicChain({ night = true })
			expect(night[1]).toBe("MusicRanchNight")
			expect(night[#night]).toBe("MusicRanch")
			expect(Logic.MusicChain({ hub = true })[1]).toBe("MusicHub")
			expect(Logic.First({ MusicRanch = "rbxassetid://1" }, night)).toBe("MusicRanch")
		end)

		it("lays ambience beds by time, weather and place", function()
			local day = Logic.Beds({ weather = "clear" })
			expect(day.AmbienceBirds).toBe(1)
			expect(day.AmbienceCrickets).toBe(0)
			local night = Logic.Beds({ weather = "clear", night = true })
			expect(night.AmbienceCrickets).toBe(1)
			expect(night.AmbienceBirds).toBe(0)
			local storm = Logic.Beds({ weather = "thunderstorm" })
			expect(storm.AmbienceRain).toBe(1)
			expect(storm.AmbienceBirds).toBe(0)
			local sky = Logic.Beds({ weather = "rain", sky = true })
			expect(sky.AmbienceWind).toBe(1)
			expect(sky.AmbienceRain < 1).toBe(true)
			expect(Logic.Kind("HatchGolden")).toBe("Hatching")
			expect(Logic.Kind("SomethingNew")).toBe("Other")
		end)
	end)

	describe("client kit", function()
		it("is silent and creates nothing while every id is empty", function()
			local _, _, c = boot()
			local service = soundService(c)
			for _, group in Logic.Groups do
				local g = service:FindFirstChild(group)
				expect(g ~= nil and g:IsA("SoundGroup")).toBe(true)
			end
			local settings = c:Open("Settings")
			c:Advance(0.5)
			for _, b in c:Buttons(settings) do
				c:Click(b)
				c:Advance(0.3)
			end
			c:Close("Settings")
			c:Open("Arena")
			c:Advance(3)
			expect(#c.world.log.sounds).toBe(0)
			expect(service:FindFirstChild("AudioPool")).toBeNil()
			expect(c.globals.workspace:FindFirstChild("AudioEmitters")).toBeNil()
			expect(c.kernel.Router:Has("SoundCheck")).toBe(false) -- Studio only
			expectClean(c)
		end)

		it("clicks buttons and pools one-shots with cooldown and max concurrency", function()
			local _, _, c = boot()
			fill(c, { "ButtonClick", "UIOpen", "Hit" })
			local Audio = c:require(c.clientFolder.Audio)
			local click = idOf(c, "ButtonClick")
			local settings = c:Open("Settings")
			c:Advance(0.5)
			expect(count(c.world.log.sounds, idOf(c, "UIOpen"))).toBe(1)
			c:Click(c:Buttons(settings)[1])
			c:Advance(0.2)
			expect(count(c.world.log.sounds, click)).toBe(1)

			-- Same frame: the cooldown lets one through.
			expect(Audio.Play("Hit") ~= nil).toBe(true)
			expect(Audio.Play("Hit")).toBeNil()
			-- Many quick plays never grow the pool past maxConcurrent (3 for Hit).
			for _ = 1, 10 do
				c:Advance(0.06)
				Audio.Play("Hit")
			end
			local pool = soundService(c):FindFirstChild("AudioPool")
			local copies = 0
			for _, s in pool:GetChildren() do
				if s.Name == "Hit" then
					copies += 1
				end
			end
			expect(copies).toBe(3)
			expectClean(c)
		end)

		it("follows the Music and Sound effects toggles", function()
			local _, _, c = boot()
			fill(c, { "Hit", "MusicRanch" })
			local Audio = c:require(c.clientFolder.Audio)
			local service = soundService(c)
			c:Request("Settings.Set", { key = "sfx", value = false })
			c:Advance(1)
			expect(Audio.Play("Hit")).toBeNil()
			expect(service.Effects.Volume).toBe(0)
			expect(service.Voice.Volume).toBe(0)
			expect(service.Music.Volume > 0).toBe(true)
			c:Request("Settings.Set", { key = "music", value = false })
			c:Advance(4)
			expect(service.Music.Volume).toBe(0)
			local music = loopSound(c, "MusicRanch")
			expect(music == nil or not music.Playing).toBe(true)
			c:Request("Settings.Set", { key = "music", value = true })
			c:Request("Settings.Set", { key = "sfx", value = true })
			c:Advance(4)
			expect(Audio.Play("Hit") ~= nil).toBe(true)
			expect(loopSound(c, "MusicRanch").Playing).toBe(true)
			expectClean(c)
		end)

		it("climbs a coin streak, plays positional sounds and ducks music under a sting", function()
			local _, _, c = boot()
			fill(c, { "CoinTick", "Pet", "LevelUp", "MusicRanch" })
			local Audio = c:require(c.clientFolder.Audio)
			local speeds = {}
			for i = 1, 4 do
				local s = Audio.Streak("CoinTick")
				speeds[i] = s.PlaybackSpeed
				c:Advance(0.1)
			end
			for i = 2, 4 do
				expect(speeds[i] > speeds[i - 1]).toBe(true)
			end
			c:Advance(2)
			expect(Audio.Streak("CoinTick").PlaybackSpeed).toBe(speeds[1])

			local pet = Audio.Play("Pet", { at = Vector3.new(40, 2, -12) })
			expect(pet.Parent:IsA("Attachment")).toBe(true)
			expect(pet.Parent.Parent.Name).toBe("AudioEmitters")
			expect(pet.Parent.Position).toBe(Vector3.new(40, 2, -12))
			expect(pet.RollOffMode).toBe(t.Roblox.Enum.RollOffMode.InverseTapered)

			c:Advance(4)
			local music = soundService(c).Music
			local full = music.Volume
			expect(full > 0).toBe(true)
			Audio.Play("LevelUp")
			c:Advance(0.5)
			expect(music.Volume < full * 0.6).toBe(true)
			c:Advance(4)
			expect(math.abs(music.Volume - full) < 0.01).toBe(true)
			expectClean(c)
		end)
	end)

	describe("Soundscape", function()
		it("crossfades from the ranch theme to battle music and back", function()
			local _, _, c = boot()
			fill(c, { "MusicRanch", "MusicBattle", "AmbienceBirds", "AmbienceFountain" })
			c:Advance(4)
			local ranch = loopSound(c, "MusicRanch")
			expect(ranch ~= nil and ranch.Playing).toBe(true)
			expect(loopSound(c, "AmbienceFountain").Parent:IsA("Attachment")).toBe(true)
			c:Open("Arena")
			c:Advance(1)
			local battle = loopSound(c, "MusicBattle")
			expect(battle.Playing).toBe(true)
			expect(ranch.Playing).toBe(true) -- still fading out
			c:Advance(4)
			expect(ranch.Playing).toBe(false)
			c:Close("Arena")
			c:Advance(4)
			expect(ranch.Playing).toBe(true)
			expect(battle.Playing).toBe(false)
			expectClean(c)
		end)

		it("previews contexts and follows lightning with thunder", function()
			local _, _, c = boot()
			fill(c, { "MusicRanch", "MusicFrostfall", "Thunder", "AmbienceRain" })
			local scape = c.kernel:GetController("Soundscape")
			scape.Preview({ weather = "thunderstorm", event = "frostfall" })
			c:Advance(4)
			expect(loopSound(c, "MusicFrostfall").Playing).toBe(true)
			expect(loopSound(c, "AmbienceRain").Playing).toBe(true)
			c.kernel.Bus:Publish("Weather.Lightning", 1)
			c:Advance(2)
			expect(count(c.world.log.sounds, idOf(c, "Thunder"))).toBe(1)
			scape.Preview(nil)
			c:Advance(4)
			expect(loopSound(c, "MusicFrostfall").Playing).toBe(false)
			expectClean(c)
		end)
	end)

	describe("voices", function()
		it("cries by archetype and pitch, rate-limits happy, and chatters from the closest", function()
			local _, _, c = boot()
			fill(c, { "VoiceFox" })
			local Voices = c:require(c.clientFolder.Audio.Voices)
			local baby = Voices.Cry({ line = "cindlet", stage = 1 }, "hatch")
			expect(baby ~= nil).toBe(true)
			c:Advance(0.3)
			local adult = Voices.Cry({ line = "cindlet", stage = 3 }, "hatch")
			expect(baby.PlaybackSpeed > adult.PlaybackSpeed).toBe(true)
			expect(Voices.Cry({ line = "mossbun", stage = 1 }, "hatch")).toBeNil() -- a bunny: no id yet

			local Instance = c.world:InstanceLibrary()
			local function monster(x: number)
				local model = Instance.new("Model")
				local body = Instance.new("Part")
				body.Name = "Body"
				body.Anchored = true
				body.CFrame = t.Roblox.CFrame.new(x, 2, 0)
				body.Parent = model
				model.PrimaryPart = body
				model:SetAttribute("Line", "cindlet")
				model:SetAttribute("Stage", 3)
				model:SetAttribute("Height", 3)
				model.Parent = c.globals.workspace
				Voices.Track(model)
				return model
			end
			local near = monster(5)
			monster(30)
			c:Advance(0.5) -- past VoiceFox's cooldown after the adult's cry
			expect(Voices.Cry(near, "happy") ~= nil).toBe(true)
			c:Advance(2)
			expect(Voices.Cry(near, "happy")).toBeNil() -- the same monster waits
			local listener = Vector3.new(0, 2, 0)
			local played = 0
			local farPlayed = false
			for _ = 1, 40 do
				c:Advance(1)
				local before = #c.world.log.sounds
				played += Voices.Chatter(listener, 1, 60)
				if #c.world.log.sounds > before then
					for _, d in c.globals.workspace.AudioEmitters:GetDescendants() do
						if d:IsA("Sound") and d.Playing and d.Parent.Position.X > 20 then
							farPlayed = true
						end
					end
				end
			end
			expect(played > 0).toBe(true)
			expect(farPlayed).toBe(false)
			expectClean(c)
		end)
	end)

	describe("Sound Check", function()
		it("lists every key with its id state and auditions it", function()
			local _, _, c = boot()
			fill(c, { "Gem", "MusicHub" })
			c.kernel.Router:Register(c:require(c.clientFolder.UI.Screens.SoundCheck))
			local root = c:Open("SoundCheck")
			c:Advance(0.5)
			for key in c.kernel.Config.Sounds do
				expect(root:FindFirstChild("Key_" .. key, true) ~= nil).toBe(true)
			end
			local gemRow = root:FindFirstChild("Key_Gem", true)
			expect(c:HasText("rbxassetid://1001", gemRow)).toBe(true)
			expect(c:HasText("empty", root:FindFirstChild("Key_Hit", true))).toBe(true)
			c:Click(c:Button("Play", gemRow))
			c:Advance(0.2)
			expect(count(c.world.log.sounds, idOf(c, "Gem"))).toBe(1)
			c:Click(c:Button("Play", root:FindFirstChild("Key_MusicHub", true)))
			c:Advance(4)
			expect(loopSound(c, "MusicHub").Playing).toBe(true)
			c:Click(c:Button("Hub", root))
			c:Advance(1)
			expect(c:HasText("Music now: MusicHub", root)).toBe(true)
			c:Close("SoundCheck")
			c:Advance(4)
			expect(loopSound(c, "MusicHub").Playing).toBe(false)
			expectClean(c)
		end)
	end)
end
