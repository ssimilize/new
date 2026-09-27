--[[
	Exhibits (update 3.12 · Honey & stars): Museum Exhibits. The sets built from the other configs
	(hidden while Apiary / Observatory are missing), the unlock gate, donating a fish, a relic from
	storage (never a placed copy) and honey (a fake Apiary), fossils filled by themselves and
	back-filled on join, charts from a fake Observatory, idempotence, the reward steps and the set
	title, the Tourist appeal bonus, the wing's layout and the weekly goal.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Exhibits")

	local Cfg = Config.Exhibits
	local SYSTEMS = {
		"Currency",
		"Progression",
		"Rewards",
		"Monsters",
		"Eggs",
		"Shop",
		"Decor",
		"DigSite",
		"Fishing",
		"HallOfFame",
		"Mastery",
		"Exhibits",
	}

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	-- A stand-in for the 3.12 Apiary / Observatory configs (other branches until the merge).
	local FAKE_APIARY = {
		Kinds = {
			{ id = "blossom", name = "Blossom Honey" },
			{ id = "clover", name = "Clover Honey" },
			{ id = "heather", name = "Heather Honey" },
			{ id = "frost", name = "Frost Honey" },
		},
		RoyalJelly = { id = "royal_jelly", name = "Royal Jelly" },
	}
	local FAKE_OBSERVATORY = {
		Charts = {
			{ id = "lantern", name = "The Lantern", perk = { key = "income", value = 0.02 } },
			{ id = "kite", name = "The Kite", perk = { key = "loot", value = 0.02 } },
			{ id = "hive", name = "The Hive", perk = { key = "hive_hours", value = 1 } },
		},
	}

	local function withFakes(fn)
		local hadA, hadO = Config.Apiary, Config.Observatory
		Config.Apiary = hadA or FAKE_APIARY
		Config.Observatory = hadO or FAKE_OBSERVATORY
		local ok, err = pcall(fn)
		Config.Apiary, Config.Observatory = hadA, hadO
		if not ok then
			error(err, 0)
		end
	end

	local function boot(stubs)
		local h = TestKernel.new({ systems = SYSTEMS, stubs = stubs })
		local donated = {}
		h.kernel.Bus:Subscribe("ExhibitDonated", function(player, detail)
			table.insert(donated, { player = player, detail = detail })
		end)
		return h, donated
	end

	local function curator(h)
		local p = h:Join()
		levelTo(h, p, Config.Unlocks.Features.exhibits)
		return p
	end

	local function completeFossil(h, p, fossilId: string)
		local s = h:Section(p, "DigSite")
		s.pieces[fossilId] = {}
		for _, piece in Config.DigSite.Pieces do
			s.pieces[fossilId][piece.id] = true
		end
		h.kernel.Bus:Publish("FossilFound", p, { fossil = fossilId, piece = "tail", complete = true })
	end

	describe("Sets", function()
		it("builds its item lists from the other configs and hides sets whose config is missing", function()
			if Config.Apiary == nil and Config.Observatory == nil then
				local shown = {}
				for _, set in Logic.Sets(Config) do
					table.insert(shown, set.id)
				end
				expect(table.concat(shown, ",")).toBe("fossils,aquarium,relics")
			end
			expect(#Logic.Items(Config, "fossils")).toBe(#Config.DigSite.Fossils)
			expect(#Logic.Items(Config, "aquarium")).toBe(#Config.Fishing.Fish)
			local relics = {}
			for _, item in Logic.Items(Config, "relics") do
				relics[item.id] = true
				expect(Config.Decor.ById[item.id] ~= nil).toBe(true)
			end
			for _, id in { "ancient_urn", "stone_tablet", "old_boot", "sunken_chest" } do
				expect(relics[id]).toBe(true)
			end
			for _, id in Config.Merchant.Decor do
				expect(relics[id]).toBe(true)
			end
			withFakes(function()
				expect(#Logic.Sets(Config)).toBe(5)
				expect(#Logic.Items(Config, "honey")).toBe(5)
				expect(Logic.Items(Config, "honey")[5].id).toBe("royal_jelly")
				expect(#Logic.Items(Config, "stars")).toBe(#Config.Observatory.Charts)
			end)
			-- Every set's title is a Mastery cosmetic.
			for _, set in Cfg.Sets do
				expect(Config.Mastery.ItemById[set.titleItem] ~= nil).toBe(true)
			end
		end)

		it("pays at a third, two thirds and all (ceil counts), scaled by set size", function()
			expect(Logic.Need(Cfg.Steps, 6, 1)).toBe(2)
			expect(Logic.Need(Cfg.Steps, 6, 2)).toBe(4)
			expect(Logic.Need(Cfg.Steps, 6, 3)).toBe(6)
			expect(Logic.Need(Cfg.Steps, 7, 1)).toBe(3)
			expect(Logic.Need(Cfg.Steps, 7, 2)).toBe(5)
			expect(Logic.Need(Cfg.Steps, 20, 1)).toBe(7)
			local g1, d1 = Logic.Reward(Config, 6, 1)
			local g3, d3 = Logic.Reward(Config, 6, 3)
			expect(g1).toBe(math.ceil(6 * Cfg.GemsPerItem * Cfg.Share[1]))
			expect(d3).toBe(math.ceil(6 * Cfg.StardustPerItem * Cfg.Share[3]))
			local g20 = Logic.Reward(Config, 20, 3)
			expect(g20 > g3 and d3 > d1).toBe(true)
		end)

		it("lays every pedestal out inside the Curator wing, clear of the plots and the museum", function()
			withFakes(function()
				local layout = Logic.Layout(Config)
				local wing = Config.World.CuratorWing
				local seen = {}
				local n = 0
				for _, set in Logic.Sets(Config) do
					n += #Logic.Items(Config, set.id)
				end
				expect(#layout.pedestals).toBe(n)
				for _, p in layout.pedestals do
					expect(seen[p.line]).toBeNil()
					seen[p.line] = true
					expect(math.abs(p.x - wing.center[1]) <= wing.size[1] / 2 - 2).toBe(true)
					expect(math.abs(p.z - wing.center[2]) <= wing.size[2] / 2 - 2).toBe(true)
				end
				expect(table.find(Config.World.CodexGrounds, wing) ~= nil).toBe(true)
				expect(table.find(Config.World.Scenery.keepOut, wing) ~= nil).toBe(true)
				local museum = Config.World.CodexGrounds[1]
				local apart = math.abs(museum.center[1] - wing.center[1]) > (museum.size[1] + wing.size[1]) / 2
					or math.abs(museum.center[2] - wing.center[2]) > (museum.size[2] + wing.size[2]) / 2
				expect(apart).toBe(true)
			end)
		end)
	end)

	describe("Donating", function()
		it("is locked before Ranch Level 18", function()
			local h = boot()
			local p = h:Join()
			h:Section(p, "Fishing").fish.bluegill = 1
			expect(h:Reject(p, "Exhibits.Donate", { set = "aquarium", item = "bluegill" })).toBe(
				string.format("Unlocks at Ranch Level %d", Config.Unlocks.Features.exhibits)
			)
			expect(h:Section(p, "Fishing").fish.bluegill).toBe(1)
		end)

		it("uses up one caught fish of that kind, once", function()
			local h, donated = boot()
			local p = curator(h)
			expect(h:Reject(p, "Exhibits.Donate", { set = "aquarium", item = "bluegill" })).toBe("You don't have one to donate")
			local fish = h:Section(p, "Fishing").fish
			fish.bluegill = 2
			fish.minnow = 3
			local res = h:Call(p, "Exhibits.Donate", { set = "aquarium", item = "bluegill" })
			expect(res.set).toBe("aquarium")
			expect(fish.bluegill).toBe(1)
			expect(fish.minnow).toBe(3)
			expect(h:Section(p, "Exhibits").filled.aquarium.bluegill).toBe(true)
			expect(#donated).toBe(1)
			expect(donated[1].detail.item).toBe("bluegill")
			-- Idempotent: the second copy stays in the bucket.
			expect(h:Reject(p, "Exhibits.Donate", { set = "aquarium", item = "bluegill" })).toBe("Already on display")
			expect(fish.bluegill).toBe(1)
			expect(#donated).toBe(1)
			expect(h:Reject(p, "Exhibits.Donate", { set = "aquarium", item = "shark_of_nope" })).toBe("That exhibit doesn't exist")
			expect(h:Reject(p, "Exhibits.Donate", { set = "fossils", item = "raptor" })).toBe("Complete it at the Dig Site")
		end)

		it("takes a relic from decor storage but never a placed copy", function()
			local h = boot()
			local p = curator(h)
			local Shop = h:System("Shop")
			h:Section(p, "Decor").layout = { { id = "old_boot", x = 0, z = 0, rot = 0 } }
			expect(h:Reject(p, "Exhibits.Donate", { set = "relics", item = "old_boot" })).toBe(
				"Every copy is placed on your ranch. Put one back in storage first"
			)
			expect(h:Reject(p, "Exhibits.Donate", { set = "relics", item = "ancient_urn" })).toBe("You don't have one to donate")
			Shop:AddDecor(p, "ancient_urn", 2)
			h:Call(p, "Exhibits.Donate", { set = "relics", item = "ancient_urn" })
			expect(Shop:DecorCount(p, "ancient_urn")).toBe(1)
			expect(h:Section(p, "Exhibits").filled.relics.ancient_urn).toBe(true)
			expect(#h:Section(p, "Decor").layout).toBe(1)
		end)

		it("spends a jar of honey through the Apiary", function()
			withFakes(function()
				local jars = { blossom = 1 }
				local h = boot({
					Apiary = {
						SpendHoney = function(_, _player, kind, n)
							if (jars[kind] or 0) < n then
								return false
							end
							jars[kind] -= n
							return true
						end,
					},
				})
				local p = curator(h)
				expect(h:Reject(p, "Exhibits.Donate", { set = "honey", item = "clover" })).toBe("You don't have one to donate")
				h:Call(p, "Exhibits.Donate", { set = "honey", item = "blossom" })
				expect(jars.blossom).toBe(0)
				expect(h:Section(p, "Exhibits").filled.honey.blossom).toBe(true)
			end)
		end)
	end)

	describe("Filling by itself", function()
		it("fills the Fossil Hall when a fossil is complete, and back-fills on join", function()
			local h, donated = boot()
			local p = h:Join() -- before the unlock too: the record is kept
			completeFossil(h, p, "raptor")
			expect(h:Section(p, "Exhibits").filled.fossils.raptor).toBe(true)
			expect(#donated).toBe(1)
			expect(donated[1].detail.set).toBe("fossils")
			h.kernel.Bus:Publish("FossilFound", p, { fossil = "trihorn", piece = "skull", complete = false })
			expect(h:Section(p, "Exhibits").filled.fossils.trihorn).toBeNil()
			-- A fossil completed before 3.12 (no event) arrives on join, without a weekly count.
			local pieces = h:Section(p, "DigSite").pieces
			pieces.longneck = {}
			for _, piece in Config.DigSite.Pieces do
				pieces.longneck[piece.id] = true
			end
			h:Section(p, "Exhibits").filled.fossils = nil
			h:System("Exhibits").PlayerAdded(p)
			local filled = h:Section(p, "Exhibits").filled.fossils
			expect(filled.longneck).toBe(true)
			expect(filled.raptor).toBe(true)
			expect(#donated).toBe(1)
		end)

		it("fills the Star Atlas from the Observatory's charts", function()
			withFakes(function()
				local h, donated = boot({
					Observatory = {
						Charted = function()
							return { kite = true }
						end,
					},
				})
				local p = curator(h)
				expect(h:Section(p, "Exhibits").filled.stars.kite).toBe(true)
				h.kernel.Bus:Publish("StarCharted", p, { chart = "lantern" })
				expect(h:Section(p, "Exhibits").filled.stars.lantern).toBe(true)
				expect(#donated).toBe(1)
				h.kernel.Bus:Publish("StarCharted", p, { chart = "lantern" })
				expect(#donated).toBe(1)
			end)
		end)
	end)

	describe("Rewards", function()
		it("pays each step once, in order, and the set title on completing it", function()
			local h = boot()
			local p = curator(h)
			h:Advance(1)
			expect(h:Reject(p, "Exhibits.Claim", { set = "fossils" })).toBe("Fill 2 more exhibits first")
			local gems0 = h:Section(p, "Currency").gems
			local total = #Config.DigSite.Fossils
			for i, f in Config.DigSite.Fossils do
				if i <= 2 then
					completeFossil(h, p, f.id)
				end
			end
			h:Advance(1)
			local res = h:Call(p, "Exhibits.Claim", { set = "fossils" })
			expect(res.step).toBe(1)
			local g1 = Logic.Reward(Config, total, 1)
			expect(h:Section(p, "Currency").gems).toBe(gems0 + g1)
			h:Advance(1)
			expect(h:Reject(p, "Exhibits.Claim", { set = "fossils" })).toBe("Fill 2 more exhibits first")
			for _, f in Config.DigSite.Fossils do
				completeFossil(h, p, f.id)
			end
			h:Advance(1)
			expect(h:Call(p, "Exhibits.Claim", { set = "fossils" }).step).toBe(2)
			h:Advance(1)
			local last = h:Call(p, "Exhibits.Claim", { set = "fossils" })
			expect(last.step).toBe(3)
			expect(last.title).toBe("title_exhibit_fossils")
			expect(h:Section(p, "Mastery").owned.title_exhibit_fossils).toBe(true)
			expect(h:Section(p, "Exhibits").paid.fossils).toBe(3)
			h:Advance(1)
			expect(h:Reject(p, "Exhibits.Claim", { set = "fossils" })).toBe("All rewards claimed")
		end)

		it("is locked before Ranch Level 18", function()
			local h = boot()
			local p = h:Join()
			completeFossil(h, p, "raptor")
			completeFossil(h, p, "trihorn")
			expect(h:Reject(p, "Exhibits.Claim", { set = "fossils" })).toBe(
				string.format("Unlocks at Ranch Level %d", Config.Unlocks.Features.exhibits)
			)
		end)
	end)

	describe("Tourists and the weekly goal", function()
		it("adds floor(10 x filled / total) appeal through the Tourists bonus hook", function()
			local hooks = {}
			local h = boot({
				Tourists = {
					RegisterAppealBonus = function(_, key, fn)
						hooks[key] = fn
					end,
				},
			})
			expect(type(hooks.exhibits)).toBe("function")
			local p = h:Join()
			completeFossil(h, p, "raptor")
			expect(hooks.exhibits(p)).toBe(0) -- not unlocked yet
			levelTo(h, p, Config.Unlocks.Features.exhibits)
			local total = 0
			for _, set in Logic.Sets(Config) do
				total += #Logic.Items(Config, set.id)
			end
			for _, f in Config.DigSite.Fossils do
				completeFossil(h, p, f.id)
			end
			expect(hooks.exhibits(p)).toBe(math.floor(10 * #Config.DigSite.Fossils / total))
			-- Everything on display = the cap.
			local all = h:Section(p, "Exhibits").filled
			for _, set in Logic.Sets(Config) do
				all[set.id] = all[set.id] or {}
				for _, item in Logic.Items(Config, set.id) do
					all[set.id][item.id] = true
				end
			end
			expect(hooks.exhibits(p)).toBe(Cfg.AppealMax)
		end)

		it("adds the exhibits_3 weekly goal on ExhibitDonated", function()
			local goal = Config.Weekly.ById.exhibits_3
			expect(goal.family).toBe("exhibits")
			expect(goal.unlock).toBe("exhibits")
			expect(goal.topic).toBe("ExhibitDonated")
			expect(goal.target).toBe(3)
			expect(Config.Unlocks.Features.exhibits).toBe(18)
		end)

		it("drops damaged save data on join", function()
			local h = boot()
			local p = curator(h)
			local s = h:Section(p, "Exhibits")
			s.filled = { aquarium = { bluegill = true, bad = 3 }, junk = 4 }
			s.paid = { aquarium = 9, fossils = "x" }
			h:System("Exhibits").PlayerAdded(p)
			expect(s.filled.aquarium.bluegill).toBe(true)
			expect(s.filled.aquarium.bad).toBeNil()
			expect(s.filled.junk).toBeNil()
			expect(s.paid.aquarium).toBe(3)
			expect(s.paid.fossils).toBeNil()
		end)
	end)
end
