--[[
	MeshClips: the 3D monsters' clip modules (Visuals/MeshMonsters/<form>: bones, idle, walk, hop;
	Visuals/MeshMonsterClips/<form>: the extra clips, tools/blender/clips.py) and how MonsterAnimator
	picks a clip for each state, with every clip and with only the first three (a form rigged before
	the extra clips, as another branch's forms are).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")

	local VISUALS = t.Root .. "/src/client/Visuals"
	local SOURCE_CAP = 200000 -- Studio refuses a ModuleScript Source this long or longer
	local BASE = { "idle", "walk", "hop" }
	local EXTRA = { "sleep", "eat", "cheer", "cheer2", "attack", "hurt", "faint", "sit", "trick" }
	local STATES = { "idle", "walk", "happy", "eat", "attack", "hurt", "sleep", "faint", "sit", "trick" }

	local function modules(folder: string): { [string]: string }
		local out = {}
		if fs.isDir(folder) then
			for _, entry in fs.readDir(folder) do
				local form = string.match(entry, "^(.+)%.luau$")
				if form then
					out[form] = fs.readFile(folder .. "/" .. entry)
				end
			end
		end
		return out
	end

	local function load(text: string, name: string)
		return luau.load(text, { debugName = name })()
	end

	-- Bytes a base64 string decodes to (MeshMonster's decoder drops newlines and padding).
	local function decodedLength(text: string): number
		local n = #string.gsub(text, "[^%w%+/]", "")
		return n // 4 * 3 + (if n % 4 == 3 then 2 elseif n % 4 == 2 then 1 else 0)
	end

	local function checkClip(form: string, name: string, clip, bones: number)
		expect(type(clip.fps) == "number" and clip.fps > 0).toBe(true)
		expect(type(clip.frames) == "number" and clip.frames >= 2).toBe(true)
		local want = clip.frames * bones * 28
		if decodedLength(clip.data) ~= want then
			error(string.format("%s %s: %d bytes of clip data, expected %d", form, name, decodedLength(clip.data), want))
		end
	end

	describe("clip modules", function()
		local main = modules(VISUALS .. "/MeshMonsters")
		local extra = modules(VISUALS .. "/MeshMonsterClips")

		it("keeps every module under Studio's Source cap", function()
			local count = 0
			for folder, list in { MeshMonsters = main, MeshMonsterClips = extra } do
				for form, text in list do
					count += 1
					if #text >= SOURCE_CAP then
						error(string.format("%s/%s.luau is %d characters (cap %d)", folder, form, #text, SOURCE_CAP))
					end
				end
			end
			expect(count > 0).toBe(true)
		end)

		it("gives every form idle, walk and hop for its bones", function()
			for form, text in main do
				local data = load(text, form)
				expect(data.form).toBe(form)
				for _, name in BASE do
					if not data.clips[name] then
						error(form .. " has no " .. name .. " clip")
					end
					checkClip(form, name, data.clips[name], #data.bones)
				end
			end
		end)

		it("gives each extra-clips module the nine new clips for its form's bones", function()
			for form, text in extra do
				local data = load(text, form)
				expect(data.form).toBe(form)
				if not main[form] then
					error("MeshMonsterClips/" .. form .. " has no MeshMonsters module beside it")
				end
				local bones = #load(main[form], form).bones
				expect(data.bones).toBe(bones)
				for _, name in EXTRA do
					if not data.clips[name] then
						error(form .. " has no " .. name .. " clip")
					end
					checkClip(form, name, data.clips[name], bones)
				end
			end
		end)
	end)

	describe("MonsterAnimator.SkinnedClip", function()
		local function animator()
			local h = TestKernel.new({ systems = {} })
			local c = ClientHarness.new(h, h:Join(), { noBoot = true })
			return c:require(c.clientFolder.Visuals.MonsterAnimator)
		end

		local function hasFrom(list: { string }): (string) -> boolean
			local set = {}
			for _, name in list do
				set[name] = true
			end
			return function(name: string): boolean
				return set[name] == true
			end
		end

		it("plays the authored clip for every state when the form has them all", function()
			local Animator = animator()
			local all = table.clone(BASE)
			table.move(EXTRA, 1, #EXTRA, #all + 1, all)
			local want = {
				idle = "idle",
				walk = "walk",
				happy = "cheer2",
				eat = "eat",
				attack = "attack",
				hurt = "hurt",
				sleep = "sleep",
				faint = "faint",
				sit = "sit",
				trick = "trick",
			}
			for _, state in STATES do
				local clip, _, loop, keep = Animator.SkinnedClip(state, hasFrom(all), 0.3, 1, "cheer2")
				expect(clip).toBe(want[state])
				expect(keep).toBe(false)
				expect(loop).toBe(state == "idle" or state == "walk" or state == "eat" or state == "sleep" or state == "sit")
			end
		end)

		it("falls back to idle, walk and hop for a module with only the three old clips", function()
			local Animator = animator()
			-- A real module's clip set: every form on this branch has only these three in MeshMonsters.
			local form, text = next(modules(VISUALS .. "/MeshMonsters"))
			local names = {}
			for name in load(text, form).clips do
				table.insert(names, name)
			end
			table.sort(names)
			expect(table.concat(names, ",")).toBe("hop,idle,walk")
			local has = hasFrom(names)
			local want = {
				idle = { "idle", false },
				walk = { "walk", false },
				happy = { "hop", false }, -- spins, as before
				eat = { "idle", true }, -- the procedural nod over idle
				attack = { "hop", true }, -- the procedural lunge over hop
				hurt = { "idle", true }, -- the procedural shake over idle
				sleep = { "idle", false }, -- idle slowed down
				faint = { "idle", true }, -- the procedural tip-over, idle held
				sit = { "idle", true },
				trick = { "hop", false }, -- a spin through hop
			}
			for _, state in STATES do
				local clip, time, _, keep = Animator.SkinnedClip(state, has, 0.5, 2, "cheer")
				expect(clip).toBe(want[state][1])
				expect(keep).toBe(want[state][2])
				expect(has(clip)).toBe(true)
				if state == "sleep" then
					expect(time).toBe((0.5 + 2) * 0.4)
				end
			end
		end)
	end)
end
