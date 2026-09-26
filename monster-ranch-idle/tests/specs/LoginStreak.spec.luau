-- Glow-up LoginStreak: the 7-day calendar, the 28-day milestone track, shields, and one claim per UTC day.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.LoginStreak")

	local DAY = 86400
	local MONDAY = 20003 -- UTC day number of a Monday
	local START = MONDAY * DAY + 10 * 3600

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Ranch", "Accessories", "LoginStreak" }

	local function boot()
		local h = TestKernel.new({ systems = SYSTEMS, startTime = START })
		local p = h:Join()
		return h, p
	end

	local function nextDay(h, days: number?)
		h.adapters.advance(DAY * (days or 1))
	end

	local function kinds(items)
		local out = {}
		for _, item in items do
			local k = item.kind .. ":" .. tostring(item.id or "")
			out[k] = (out[k] or 0) + item.amount
		end
		return out
	end

	describe("LoginStreak", function()
		it("claims once per UTC day and pays through the reward card", function()
			local h, p = boot()
			local data = h:Call(p, "LoginStreak.Claim")
			expect(data.day).toBe(1)
			expect(data.streak).toBe(1)
			expect(data.track).toBe(1)
			expect(kinds(data.items)["coins:"]).toBeAtLeast(100)
			local card = h:LastEvent(p, "Rewards.Granted")
			expect(card.payload.source).toBe("daily_streak")
			expect(h:Reject(p, "LoginStreak.Claim")).toBe("Already claimed today. Come back tomorrow!")
			-- 23:59 the same UTC day: still claimed; one minute later a new day starts.
			h.adapters.advance(14 * 3600 - 60)
			h:Reject(p, "LoginStreak.Claim")
			h.adapters.advance(120)
			expect(h:Call(p, "LoginStreak.Claim").day).toBe(2)
			local client = h:Client(p).profile.LoginStreak
			expect(client.last).toBe(MONDAY + 1)
			expect(client.streak).toBe(2)
		end)

		it("keeps the claim when the same request arrives twice", function()
			local h, p = boot()
			h:Call(p, "LoginStreak.Claim")
			nextDay(h)
			h:Call(p, "LoginStreak.Claim")
			local before = h:Section(p, "Currency").gems
			h:Reject(p, "LoginStreak.Claim")
			expect(h:Section(p, "Currency").gems).toBe(before)
			expect(h:Section(p, "LoginStreak").total).toBe(2)
		end)

		it("uses the shield for one missed day, then restarts gently and keeps milestones", function()
			local h, p = boot()
			h:Call(p, "LoginStreak.Claim") -- Mon
			nextDay(h)
			h:Call(p, "LoginStreak.Claim") -- Tue
			nextDay(h, 2)
			local saved = h:Call(p, "LoginStreak.Claim") -- Thu (Wed missed)
			expect(saved.shieldUsed).toBe(true)
			expect(saved.streak).toBe(3)
			expect(saved.day).toBe(3)
			local s = h:Section(p, "LoginStreak")
			expect(s.shield).toBe(0)
			expect(s.savedDay).toBe(MONDAY + 3)
			nextDay(h, 2)
			local restarted = h:Call(p, "LoginStreak.Claim") -- Sat (Fri missed, no shield)
			expect(restarted.restarted).toBe(true)
			expect(restarted.shieldUsed).toBe(false)
			expect(restarted.day).toBe(1)
			expect(restarted.streak).toBe(1)
			expect(restarted.track).toBe(4)
			expect(h:Section(p, "LoginStreak").best).toBe(3)
		end)

		it("refills the shield every Monday", function()
			local h, p = boot()
			h:Call(p, "LoginStreak.Claim")
			nextDay(h, 2)
			h:Call(p, "LoginStreak.Claim") -- Wed, shield used
			expect(h:Section(p, "LoginStreak").shield).toBe(0)
			nextDay(h, 4) -- Sun
			h:Call(p, "LoginStreak.Claim")
			expect(h:Section(p, "LoginStreak").streak).toBe(1)
			nextDay(h, 2) -- Tue next week (Mon missed): the refilled shield covers it
			local data = h:Call(p, "LoginStreak.Claim")
			expect(data.shieldUsed).toBe(true)
			expect(data.streak).toBe(2)
		end)

		it("pays a bigger day 7 with an egg one rung up and the first milestone", function()
			local h, p = boot()
			local data
			for day = 1, 7 do
				data = h:Call(p, "LoginStreak.Claim")
				expect(data.day).toBe(day)
				nextDay(h)
			end
			expect(data.milestone).toBe(7)
			local got = kinds(data.items)
			expect(got["egg:grove"]).toBe(1)
			expect(got["gems:"]).toBe(15)
			expect(got["stardust:"]).toBe(50)
			-- The calendar loops back to day 1.
			expect(h:Call(p, "LoginStreak.Claim").day).toBe(1)
		end)

		it("completes the 28-day track once with the Golden Streak Scarf", function()
			local h, p = boot()
			local Accessories = h:System("Accessories")
			local last
			for _ = 1, 28 do
				last = h:Call(p, "LoginStreak.Claim")
				nextDay(h)
			end
			expect(last.milestone).toBe(28)
			expect(Accessories:Count(p, "golden_streak_scarf")).toBe(1)
			expect(kinds(last.items)["egg:starlit"]).toBe(1)
			expect(h:Section(p, "LoginStreak").cycles).toBe(1)
			expect(h:Call(p, "LoginStreak.Claim").track).toBe(1)
			nextDay(h)
			for _ = 2, 28 do
				last = h:Call(p, "LoginStreak.Claim")
				nextDay(h)
			end
			expect(last.milestone).toBe(28)
			expect(Accessories:Count(p, "golden_streak_scarf")).toBe(1)
			expect(kinds(last.items)["gems:"]).toBe(75 + 15)
			expect(h:Section(p, "LoginStreak").cycles).toBe(2)
		end)

		it("reports the deadline of a streak with no shield", function()
			local h, p = boot()
			local L = h:System("LoginStreak")
			expect(L:Status(p).deadline).toBeNil()
			h:Call(p, "LoginStreak.Claim")
			expect(L:Status(p).claimedToday).toBe(true)
			expect(L:Status(p).deadline).toBeNil() -- the shield covers the next miss
			h:Section(p, "LoginStreak").shield = 0
			expect(L:Status(p).deadline).toBe((MONDAY + 2) * DAY)
		end)
	end)

	describe("LoginStreak logic", function()
		it("never claims when the saved day is ahead of the server clock", function()
			local state = Logic.Default(MONDAY)
			state.last = MONDAY + 1
			expect(Logic.Preview(state, MONDAY).canClaim).toBe(false)
		end)

		it("resolves ladder eggs by what the player has unlocked", function()
			local items = { { kind = "egg", id = "ladder", step = 1, amount = 1 }, { kind = "gems", amount = 5 } }
			local low = Logic.Resolve(items, function(key)
				return key == "egg_meadow"
			end)
			expect(low[1].id).toBe("grove")
			expect(low[1].step).toBeNil()
			local top = Logic.Resolve(items, function()
				return true
			end)
			expect(top[1].id).toBe("crystal")
		end)

		it("only rewards real items", function()
			local function check(item)
				if item.kind == "egg" and item.id ~= "ladder" then
					expect(Config.Eggs.ById[item.id] ~= nil).toBe(true)
				elseif item.kind == "accessory" then
					expect(Config.Accessories.ById[item.id] ~= nil).toBe(true)
				end
			end
			for _, day in Config.LoginStreak.Days do
				for _, item in day do
					check(item)
				end
			end
			for _, milestone in Config.LoginStreak.Milestones do
				for _, item in milestone.items do
					check(item)
				end
				for _, item in milestone.first or {} do
					check(item)
				end
			end
			for _, rung in Config.LoginStreak.EggLadder do
				expect(Config.Eggs.ById[rung.egg] ~= nil).toBe(true)
			end
		end)

		it("repairs a damaged save section", function()
			local h = TestKernel.new({ systems = SYSTEMS, startTime = START })
			local section = h:System("LoginStreak").Profile.Migrate({ pos = 12, shield = 5, junk = "x", last = 3 }, 0)
			expect(section.pos).toBe(7)
			expect(section.shield).toBe(1)
			expect(section.junk).toBeNil()
			expect(section.last).toBe(3)
		end)
	end)
end
