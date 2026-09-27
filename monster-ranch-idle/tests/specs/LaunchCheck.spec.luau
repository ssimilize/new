--[[
	R2-LAUNCH: Logic/LaunchCheck finds owner-created ids Config still has as placeholders
	(game passes, developer products, Codex badges, the group, reminder templates/secret,
	the Workshop moderator group).

	RELEASE_CHECK=1 lune run tests LaunchCheck also fails if the REAL Config still has any
	missing id, so a release build can gate on it (docs/GO_LIVE.md).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local process = require("@lune/process")

	local LaunchCheck = t.Shared("Logic.LaunchCheck")
	local RealConfig = t.Shared("Config")

	local function clone(value, depth: number?)
		depth = depth or 0
		if type(value) ~= "table" or depth > 10 then
			return value
		end
		local out = {}
		for k, v in value do
			out[k] = clone(v, depth + 1)
		end
		return out
	end

	-- A copy of the real Config with every placeholder id filled in.
	local function filledConfig()
		local cfg = clone(RealConfig)
		local nextId = 1
		for _, p in cfg.Monetization.Passes do
			p.gamePassId = nextId
			nextId += 1
		end
		for _, p in cfg.Monetization.Products do
			p.productId = nextId
			nextId += 1
		end
		for milestone in cfg.Codex.BadgeIds do
			cfg.Codex.BadgeIds[milestone] = nextId
			nextId += 1
		end
		cfg.Quests.GroupId = nextId
		nextId += 1
		cfg.Reminders.SecretName = "notifications_key"
		for _, kind in cfg.Reminders.Kinds do
			cfg.Reminders.Templates[kind] = "template_" .. kind
		end
		cfg.Workshop.ModeratorGroup.id = nextId
		return cfg
	end

	describe("LaunchCheck.Missing", function()
		it("is empty once every id is filled in", function()
			local missing = LaunchCheck.Missing(filledConfig())
			expect(#missing).toBe(0)
		end)

		it("lists an unset game pass id", function()
			local cfg = filledConfig()
			cfg.Monetization.Passes[1].gamePassId = 0
			local missing = LaunchCheck.Missing(cfg)
			local found = false
			for _, entry in missing do
				if entry.area == "pass" and entry.key == cfg.Monetization.Passes[1].key then
					found = true
					expect(entry.where).toBe("Config.Monetization.Passes." .. entry.key .. ".gamePassId")
					expect(#entry.create > 0).toBe(true)
				end
			end
			expect(found).toBe(true)
			expect(#missing).toBe(1)
		end)

		it("lists an unset developer product id", function()
			local cfg = filledConfig()
			local key = cfg.Monetization.Products[1].key
			cfg.Monetization.Products[1].productId = 0
			local missing = LaunchCheck.Missing(cfg)
			expect(#missing).toBe(1)
			expect(missing[1].area).toBe("product")
			expect(missing[1].key).toBe(key)
		end)

		it("lists an unset Codex badge id", function()
			local cfg = filledConfig()
			cfg.Codex.BadgeIds.complete = 0
			local missing = LaunchCheck.Missing(cfg)
			expect(#missing).toBe(1)
			expect(missing[1].area).toBe("badge")
			expect(missing[1].key).toBe("complete")
			expect(missing[1].where).toBe("Config.Codex.BadgeIds.complete")
		end)

		it("lists an unset group id", function()
			local cfg = filledConfig()
			cfg.Quests.GroupId = 0
			local missing = LaunchCheck.Missing(cfg)
			expect(#missing).toBe(1)
			expect(missing[1].area).toBe("group")
			expect(missing[1].where).toBe("Config.Quests.GroupId")
		end)

		it("lists a blank reminders secret and template separately", function()
			local cfg = filledConfig()
			cfg.Reminders.SecretName = ""
			cfg.Reminders.Templates.egg = ""
			local missing = LaunchCheck.Missing(cfg)
			expect(#missing).toBe(2)
			local keys = {}
			for _, entry in missing do
				keys[entry.key] = entry.area
			end
			expect(keys.secret).toBe("reminders")
			expect(keys.egg).toBe("reminders")
		end)

		it("lists an unset Workshop moderator group id", function()
			local cfg = filledConfig()
			cfg.Workshop.ModeratorGroup.id = 0
			local missing = LaunchCheck.Missing(cfg)
			expect(#missing).toBe(1)
			expect(missing[1].area).toBe("moderation")
		end)
	end)

	describe("LaunchCheck.Summary", function()
		it("says nothing missing when the list is empty", function()
			expect(LaunchCheck.Summary({})).toBe("Launch checklist: nothing missing.")
		end)

		it("groups counts by area and mentions docs/GO_LIVE.md", function()
			local summary = LaunchCheck.Summary({
				{ area = "pass", key = "a", where = "x", create = "y" },
				{ area = "pass", key = "b", where = "x", create = "y" },
				{ area = "group", key = "group", where = "x", create = "y" },
			})
			expect(string.find(summary, "2 pass ids", 1, true) ~= nil).toBe(true)
			expect(string.find(summary, "the group id", 1, true) ~= nil).toBe(true)
			expect(string.find(summary, "docs/GO_LIVE.md", 1, true) ~= nil).toBe(true)
		end)
	end)

	-- Release gate: with RELEASE_CHECK=1 the REAL Config must have nothing missing. Normal CI
	-- runs (no env var) skip this so the suite stays green while the owner fills ids in later.
	it("release gate: RELEASE_CHECK=1 fails on any missing id in the real Config", function()
		if process.env.RELEASE_CHECK ~= "1" then
			return
		end
		local missing = LaunchCheck.Missing(RealConfig)
		if #missing > 0 then
			error(LaunchCheck.Summary(missing), 0)
		end
	end)
end
