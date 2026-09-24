-- S5 Social: friends-on-server boost, petting and likes with daily limits, and broadcasts
-- (server, global through MessagingService, and re-broadcasts from other servers).
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")

	local function boot(extraSystems)
		local modifiers = {}
		local systems = { "Currency", "Progression", "Rewards", "Monsters", "Social" }
		for _, name in extraSystems or {} do
			table.insert(systems, name)
		end
		local h = TestKernel.new({
			systems = systems,
			stubs = {
				Ranch = {
					RegisterRateModifier = function(_, key, fn)
						modifiers[key] = fn
					end,
					MonstersInPens = function()
						return {}
					end,
				},
			},
		})
		return h, modifiers
	end

	local function onTopic(h, topic)
		local seen = {}
		h.kernel.Bus:Subscribe(topic, function(player, detail)
			table.insert(seen, { player = player, detail = detail })
		end)
		return seen
	end

	local function befriend(h, a, b)
		h.adapters.friends[a] = h.adapters.friends[a] or {}
		h.adapters.friends[a][b] = true
	end

	describe("Friends on server", function()
		it("adds +10% per friend here, capped at +40%, and updates on join and leave", function()
			local h, modifiers = boot()
			local changed = onTopic(h, "RateModifiersChanged")
			befriend(h, 7001, 7002)
			befriend(h, 7005, 7001) -- friendship stored on the other side only
			befriend(h, 7001, 7006)
			befriend(h, 7001, 7007)
			befriend(h, 7001, 7008)
			local a = h:Join(7001)
			expect(h:Session(a, "Social").friendBoost).toBe(0)
			local b = h:Join(7002)
			expect(h:Session(a, "Social").friendsHere).toBe(1)
			expect(h:Session(a, "Social").friendBoost).toBeNear(0.1)
			expect(h:Session(b, "Social").friendBoost).toBeNear(0.1)
			local stranger = h:Join(7003)
			expect(h:Session(stranger, "Social").friendBoost).toBe(0)
			expect(h:Session(a, "Social").friendsHere).toBe(1)
			local changesForA = 0
			for _, c in changed do
				if c.player == a then
					changesForA += 1
				end
			end
			expect(changesForA).toBe(2) -- on its own join, then when b arrived
			h:Join(7005)
			h:Join(7006)
			h:Join(7007)
			h:Join(7008)
			expect(h:Session(a, "Social").friendsHere).toBe(5)
			expect(h:Session(a, "Social").friendBoost).toBeNear(0.4)
			expect(h:Client(a).session.Social.friendBoost).toBeNear(0.4)
			h:Leave(b)
			expect(h:Session(a, "Social").friendsHere).toBe(4)
			expect(h:Session(a, "Social").friendBoost).toBeNear(0.4)
			expect(modifiers.friends).toBeTruthy()
			expect(modifiers.friends(a, { "ember" })).toBeNear(0.4)
			expect(h:System("Social"):GetFriendBoost(stranger)).toBe(0)
		end)
	end)

	describe("Petting", function()
		it("gives the owner's monster mood and the petter Friendship Points", function()
			local h = boot()
			local given, received = onTopic(h, "PetGiven"), onTopic(h, "PetReceived")
			local owner, visitor = h:Join(), h:Join()
			local M = h:System("Monsters")
			local m = M:Create(owner, { line = "cindlet", rarity = 1, traits = { 3, 4 }, hidden = 5 }, "test", true)
			local charmer = M:Create(owner, { line = "cindlet", rarity = 1, traits = { 11, 4 }, hidden = 5 }, "test", true)
			m.mood, charmer.mood = 50, 50
			local data = h:Call(visitor, "Social.Pet", { owner = owner.UserId, id = m.id })
			expect(m.mood).toBe(50 + Config.Social.PetMood)
			expect(data.friendship).toBe(Config.Social.FriendshipPerPet)
			expect(data.left).toBe(Config.Social.PetsPerDay - 1)
			h:Call(visitor, "Social.Pet", { owner = owner.UserId, id = charmer.id })
			expect(charmer.mood).toBe(50 + 2 * Config.Social.PetMood)
			expect(given[1].detail.owner).toBe(owner.UserId)
			expect(received[1].player).toBe(owner)
			expect(received[1].detail.from).toBe(visitor.UserId)
			expect(h:Client(visitor).profile.Social.petsGiven).toBe(2)
		end)

		it("rejects your own ranch, absent owners, missing and away monsters", function()
			local h = boot()
			local owner, visitor = h:Join(), h:Join()
			local M = h:System("Monsters")
			local m = M:Create(owner, { line = "cindlet", rarity = 1 }, "test", true)
			expect(h:Reject(owner, "Social.Pet", { owner = owner.UserId, id = m.id })).toContain("another ranch")
			expect(h:Reject(visitor, "Social.Pet", { owner = 999999, id = m.id })).toContain("isn't on this server")
			expect(h:Reject(visitor, "Social.Pet", { owner = owner.UserId, id = "m404" })).toContain("isn't there")
			M:SetBusy(owner, m.id, "expedition")
			h:Advance(1)
			expect(h:Reject(visitor, "Social.Pet", { owner = owner.UserId, id = m.id })).toContain("expedition")
		end)

		it("allows PetsPerDay pets per UTC day", function()
			local h = boot()
			local owner, visitor = h:Join(), h:Join()
			local m = h:System("Monsters"):Create(owner, { line = "cindlet", rarity = 1 }, "test", true)
			for _ = 1, Config.Social.PetsPerDay do
				h:Call(visitor, "Social.Pet", { owner = owner.UserId, id = m.id })
				h:Advance(0.5)
			end
			expect(m.mood).toBe(100)
			expect(h:Reject(visitor, "Social.Pet", { owner = owner.UserId, id = m.id })).toContain("Come back tomorrow")
			h:Advance(86400)
			expect(h:Call(visitor, "Social.Pet", { owner = owner.UserId, id = m.id }).left).toBe(Config.Social.PetsPerDay - 1)
		end)
	end)

	describe("Likes", function()
		it("likes a ranch once per day, up to LikesPerDay ranches", function()
			local h = boot()
			local plotChanged = onTopic(h, "PlotChanged")
			local visitor = h:Join()
			local owners = {}
			for i = 1, Config.Social.LikesPerDay + 1 do
				owners[i] = h:Join()
			end
			expect(h:Call(visitor, "Social.Like", { owner = owners[1].UserId }).likes).toBe(1)
			expect(h:System("Social"):GetLikes(owners[1])).toBe(1)
			expect(h:Client(owners[1]).profile.Social.likes).toBe(1)
			expect(plotChanged[1].player).toBe(owners[1])
			h:Advance(1)
			expect(h:Reject(visitor, "Social.Like", { owner = owners[1].UserId })).toContain("already liked")
			expect(h:Reject(visitor, "Social.Like", { owner = visitor.UserId })).toContain("your own ranch")
			for i = 2, Config.Social.LikesPerDay do
				h:Advance(1)
				h:Call(visitor, "Social.Like", { owner = owners[i].UserId })
			end
			h:Advance(1)
			local last = owners[Config.Social.LikesPerDay + 1]
			expect(h:Reject(visitor, "Social.Like", { owner = last.UserId })).toContain("all 10 likes")
			h:Advance(86400)
			expect(h:Call(visitor, "Social.Like", { owner = owners[1].UserId }).likes).toBe(2)
			expect(h:Client(visitor).profile.Social.likesGiven["u" .. owners[1].UserId]).toBe(true)
		end)
	end)

	describe("Broadcasts", function()
		local function hatch(h, p, fields)
			local spec = { line = "cindlet", rarity = 1, variant = 0, weight = 3.2 }
			for k, v in fields do
				spec[k] = v
			end
			local m = h:System("Monsters"):Create(p, spec, "hatch", true)
			h.kernel.Bus:Publish("EggHatched", p, { id = m.id, egg = "meadow", rarity = m.rarity, variant = m.variant })
			return m
		end

		it("announces Epic+ hatches to the server and Mythic or Rainbow to every server", function()
			local h = boot()
			local p, other = h:Join(nil, "Hatcher"), h:Join()
			hatch(h, p, { rarity = 1 })
			expect(#h:Events(other, "Social.Broadcast")).toBe(0)

			hatch(h, p, { rarity = 4 })
			local ev = h:LastEvent(other, "Social.Broadcast")
			expect(ev.payload.kind).toBe("hatch")
			expect(ev.payload.text).toBe("Hatcher hatched an Epic Cindlet!")
			expect(ev.payload.userId).toBe(p.UserId)
			expect(ev.payload.appearance.line).toBe("cindlet")
			expect(#h.adapters.log.published).toBe(0)

			hatch(h, p, { rarity = 6 })
			expect(#h.adapters.log.published).toBe(1)
			expect(h.adapters.log.published[1].topic).toBe(Config.Social.Broadcasts.topic)
			expect(h.adapters.log.published[1].data.text).toContain("Mythic")
			-- our own message comes back from MessagingService and is not shown twice
			expect(#h:Events(other, "Social.Broadcast")).toBe(2)

			hatch(h, p, { rarity = 2, variant = 2 })
			expect(#h.adapters.log.published).toBe(2)
			expect(h:LastEvent(other, "Social.Broadcast").payload.text).toContain("Rainbow Uncommon")
			hatch(h, p, { rarity = 2, variant = 1 })
			expect(#h.adapters.log.published).toBe(2)
			expect(h:LastEvent(other, "Social.Broadcast").payload.text).toContain("Golden")
		end)

		it("announces Huge weights", function()
			local h = boot()
			local p = h:Join(nil, "Heavy")
			hatch(h, p, { rarity = 1, weight = 3.2 * 1.9 })
			local ev = h:LastEvent(p, "Social.Broadcast")
			expect(ev.payload.kind).toBe("huge")
			expect(ev.payload.text).toContain("HUGE Common Cindlet (6.08 kg)")
		end)

		it("re-broadcasts messages from other servers and skips its own", function()
			local h = boot()
			local p = h:Join()
			local topic = Config.Social.Broadcasts.topic
			h.adapters.Messaging.Publish(topic, { job = "other-server", kind = "hatch", text = "Far hatched a Mythic!", userId = 5 })
			h.adapters.Messaging.Publish(topic, { job = h.adapters.JobId, kind = "hatch", text = "echo", userId = 6 })
			h.adapters.Messaging.Publish(topic, { job = "other-server", kind = 5, text = "bad" })
			local events = h:Events(p, "Social.Broadcast")
			expect(#events).toBe(1)
			expect(events[1].payload.text).toBe("Far hatched a Mythic!")
			expect(events[1].payload.userId).toBe(5)
		end)

		it("announces the Aurora and Prismatic mutations to every server", function()
			local h = boot({ "Weather" })
			local p = h:Join(nil, "Skywatcher")
			h:System("Weather"):Trigger("aurora", "admin")
			local ev = h:LastEvent(p, "Social.Broadcast")
			expect(ev.payload.kind).toBe("weather")
			expect(ev.payload.text).toContain("Aurora")
			expect(#h.adapters.log.published).toBe(1)

			local m = h:System("Monsters"):Create(p, { line = "cindlet", rarity = 1 }, "test", true)
			h:System("Weather"):GuaranteeMutation(p, "prismatic")
			ev = h:LastEvent(p, "Social.Broadcast")
			expect(ev.payload.kind).toBe("mutation")
			expect(ev.payload.text).toBe("Skywatcher's Cindlet caught the Prismatic mutation!")
			expect(ev.payload.appearance.muts).toEqual({ "prismatic" })
			expect(m.muts).toEqual({ "prismatic" })
			expect(#h.adapters.log.published).toBe(2)
			-- ordinary weather is not announced
			h:System("Weather"):Trigger("rain", "admin")
			expect(#h:Events(p, "Social.Broadcast")).toBe(2)
		end)

		it("sends a direct Broadcast to the server only by default", function()
			local h = boot()
			local a, b = h:Join(), h:Join()
			h:System("Social"):Broadcast("custom", "Hello ranchers", a)
			expect(h:LastEvent(b, "Social.Broadcast").payload.text).toBe("Hello ranchers")
			h:System("Social"):Broadcast("custom", "Nobody hears this", a, nil, "none")
			expect(#h:Events(b, "Social.Broadcast")).toBe(1)
			expect(#h.adapters.log.published).toBe(0)
		end)
	end)
end
