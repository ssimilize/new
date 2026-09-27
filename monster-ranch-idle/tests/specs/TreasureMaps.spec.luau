--[[
	TreasureMaps (update 3.13 · Wild things) on the server: the unlock gate, AddPieces and the
	Rewards kind map_piece, four pieces making a map in an open region, the three-map and twelve-
	piece caps, pieces waiting for a first clear, the drop hooks (an expedition claim, a bounty's
	first win, a fishing catch and a dig find give pieces once unlocked and nothing before, and the
	hosts' seeded outcomes do not move), the guardian fight (a win pays the chest, publishes
	TreasureOpened and uses the map; a loss keeps it), the map-only decor and the treasure_2 goal.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.TreasureMaps")
	local BattleSim = t.Shared("Logic.BattleSim")
	local FishLogic = t.Shared("Logic.Fishing")
	local DigLogic = t.Shared("Logic.DigSite")

	local Cfg = Config.TreasureMaps
	local UNLOCK = Config.Unlocks.Features.treasure_maps

	local SYSTEMS = {
		"Currency",
		"Progression",
		"Rewards",
		"Monsters",
		"Eggs",
		"Shop",
		"Ranch",
		"Decor",
		"Expeditions",
		"Fishing",
		"DigSite",
		"TreasureMaps",
		"Weekly",
	}

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function boot(opts)
		opts = opts or {}
		local systems = {}
		for _, name in SYSTEMS do
			if not (opts.without and name == "TreasureMaps") then
				table.insert(systems, name)
			end
		end
		local h = TestKernel.new({ systems = systems })
		local opened = {}
		h.kernel.Bus:Subscribe("TreasureOpened", function(player, detail)
			table.insert(opened, { player = player, detail = detail })
		end)
		return h, opened
	end

	-- A player at `level` (default the unlock) with `cleared` stages ({ meadow = 12 } by default).
	local function hunter(h, opts)
		opts = opts or {}
		local p = h:Join(opts.userId)
		local s = h:Section(p, "Expeditions")
		for regionId, stage in opts.cleared or { meadow = 12 } do
			s.cleared[regionId] = stage
		end
		levelTo(h, p, opts.level or UNLOCK)
		return p
	end

	local function squad(h, p, strong: boolean)
		local ids = {}
		for i = 1, if strong then 3 else 1 do
			local line = ({ "cindlet", "bubblin", "mossbun" })[i]
			local m = h:System("Monsters")
				:Create(p, { line = line, rarity = if strong then 6 else 1, stage = if strong then 3 else 1 }, "test", true)
			m.lv = if strong then 100 else 1
			table.insert(ids, m.id)
		end
		h:Call(p, "Expeditions.SetSquad", { ids = ids })
		return ids
	end

	local function find(items, kind: string)
		for _, item in items or {} do
			if item.kind == kind then
				return item
			end
		end
		return nil
	end

	local function without(items, kind: string)
		local out = {}
		for _, item in items or {} do
			if item.kind ~= kind then
				table.insert(out, item)
			end
		end
		return out
	end

	-- Runs fn with every drop chance forced to `chance`, then restores them.
	local function forced(chance: number, fn)
		local saved = table.clone(Cfg.Drops)
		for key in Cfg.Drops do
			Cfg.Drops[key] = chance
		end
		local ok, err = pcall(fn)
		for key, v in saved do
			Cfg.Drops[key] = v
		end
		if not ok then
			error(err, 0)
		end
	end

	local function dig(h, p, id: number)
		h:Advance(1)
		return h:Call(p, "TreasureMaps.Dig", { map = id })
	end

	describe("Logic", function()
		it("puts the X in an open region on a cleared stage near the top, the same from the same seed", function()
			expect(Logic.Roll({}, 5)).toBeNil()
			local open = { { region = "meadow", cleared = 12 }, { region = "coral", cleared = 3 } }
			local seen = {}
			for seed = 1, 200 do
				local a, b = Logic.Roll(open, seed), Logic.Roll(open, seed)
				expect(a.region).toBe(b.region)
				expect(a.stage).toBe(b.stage)
				seen[a.region] = true
				if a.region == "meadow" then
					expect(a.stage >= 12 - Cfg.StageSpread and a.stage <= 12).toBe(true)
				else
					expect(a.stage >= 1 and a.stage <= 3).toBe(true)
				end
			end
			expect(seen.meadow and seen.coral).toBe(true)
		end)

		it("scales the guardian to GuardianMult x the stage's recommended power and rolls the chest from the map", function()
			local map = { id = 1, region = "meadow", stage = 8, seed = 777 }
			local want = BattleSim.RecommendedPower("meadow", 8) * Cfg.GuardianMult
			local got = Logic.GuardianPower(map)
			expect(math.abs(got - want) <= 3).toBe(true)
			expect(Logic.Preview(map).power).toBe(got)
			local chest = Logic.Chest(map)
			expect(find(chest, "coins").seconds).toBe(Cfg.ChestSeconds)
			expect(find(chest, "gems").amount).toBe(Cfg.ChestGems)
			expect(find(chest, "egg").id).toBe("meadow")
			expect(#Logic.Chest(map)).toBe(#chest)
			local decor = 0
			for seed = 1, 400 do
				local d = find(Logic.Chest({ id = 1, region = "meadow", stage = 8, seed = seed }), "decor")
				if d then
					decor += 1
					expect(table.find(Cfg.Decor, d.id) ~= nil).toBe(true)
				end
			end
			expect(math.abs(decor / 400 - Cfg.DecorChance) < 0.08).toBe(true)
		end)

		it("adds 2-3 map-only decor pieces built from parts, never sold", function()
			expect(#Cfg.Decor >= 2 and #Cfg.Decor <= 3).toBe(true)
			for _, id in Cfg.Decor do
				local def = Config.Decor.ById[id]
				expect(def ~= nil).toBe(true)
				expect(def.price).toBeNil()
				expect(def.reward).toBe("treasure")
				expect(t.Shared("Config.DecorArt").Models[def.model] ~= nil).toBe(true)
			end
		end)
	end)

	describe("Pieces and maps", function()
		it("is locked below Ranch Level 23", function()
			local h = boot()
			local p = hunter(h, { level = UNLOCK - 1 })
			squad(h, p, true)
			expect(h:Reject(p, "TreasureMaps.Dig", { map = 1 })).toBe("Unlocks at Ranch Level 23")
			expect(#h:System("TreasureMaps"):Drop(p, "bounty")).toBe(0)
			levelTo(h, p, UNLOCK)
			expect(h:Reject(p, "TreasureMaps.Dig", { map = 1 })).toBe("That map is gone")
			expect(#h:System("TreasureMaps"):Drop(p, "bounty")).toBe(1)
		end)

		it("takes pieces from AddPieces and the Rewards kind map_piece; four make a map in an open region", function()
			local h = boot()
			local p = hunter(h)
			local TM = h:System("TreasureMaps")
			local granted = h:System("Rewards"):Grant(p, { { kind = "map_piece", amount = 3 } }, "test")
			expect(find(granted, "map_piece").amount).toBe(3)
			expect(TM:Pieces(p)).toBe(3)
			expect(#TM:Maps(p)).toBe(0)
			expect(TM:AddPieces(p, 1)).toBe(0)
			local maps = TM:Maps(p)
			expect(#maps).toBe(1)
			expect(maps[1].region).toBe("meadow")
			expect(maps[1].stage >= 12 - Cfg.StageSpread and maps[1].stage <= 12).toBe(true)
			expect(maps[1].id).toBe(1)
			expect(h:Client(p).profile.TreasureMaps.maps[1].region).toBe("meadow")
		end)

		it("holds at most 3 maps and 12 waiting pieces", function()
			local h = boot()
			local p = hunter(h)
			local TM = h:System("TreasureMaps")
			expect(TM:AddPieces(p, 40)).toBe(Cfg.PieceCap)
			expect(#TM:Maps(p)).toBe(Cfg.MaxMaps)
			expect(TM:AddPieces(p, 4)).toBe(Cfg.PieceCap)
			expect(#TM:Maps(p)).toBe(Cfg.MaxMaps)
		end)

		it("keeps pieces waiting until a region has a cleared stage", function()
			local h = boot()
			local p = hunter(h, { cleared = {} })
			squad(h, p, true)
			local TM = h:System("TreasureMaps")
			expect(TM:AddPieces(p, 4)).toBe(4)
			expect(#TM:Maps(p)).toBe(0)
			local res = h:Call(p, "Expeditions.Fight", { region = "meadow", stage = 1 })
			expect(res.win).toBe(true)
			expect(#TM:Maps(p)).toBe(1)
			expect(TM:Maps(p)[1].region).toBe("meadow")
			expect(TM:Maps(p)[1].stage).toBe(1)
			expect(TM:Pieces(p)).toBe(0)
		end)
	end)

	describe("Drops", function()
		local function claimOnce(h, p, ids)
			h:Call(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "900", squad = ids })
			h:Advance(901)
			return h:Call(p, "Expeditions.Claim", { slot = 1 })
		end

		it("rolls a piece on an expedition claim once unlocked, leaving the loot unchanged", function()
			forced(1, function()
				local h = boot()
				local p = hunter(h)
				local ids = squad(h, p, true)
				local claim = claimOnce(h, p, ids)
				expect(find(claim.rewards, "map_piece").amount).toBe(1)
				expect(h:System("TreasureMaps"):Pieces(p)).toBe(1)

				-- The same run without the system: the same loot, minus the piece.
				local h2 = boot({ without = true })
				local p2 = hunter(h2)
				local ids2 = squad(h2, p2, true)
				local plain = claimOnce(h2, p2, ids2)
				local a, b = without(claim.rewards, "map_piece"), plain.rewards
				expect(#a).toBe(#b)
				for i, item in a do
					expect(item.kind).toBe(b[i].kind)
					expect(item.amount).toBe(b[i].amount)
				end

				local h3 = boot()
				local p3 = hunter(h3, { level = UNLOCK - 1 })
				local ids3 = squad(h3, p3, true)
				expect(find(claimOnce(h3, p3, ids3).rewards, "map_piece")).toBeNil()
				expect(h3:System("TreasureMaps"):Pieces(p3)).toBe(0)
			end)
		end)

		it("drops at the configured rate on its own seeded stream", function()
			local hits = 0
			for n = 1, 2000 do
				hits += Logic.Drops("expedition", Logic.DropSeed(4242, "expedition", n))
			end
			expect(math.abs(hits / 2000 - Cfg.Drops.expedition) < 0.015).toBe(true)
			expect(Logic.Drops("bounty", 1)).toBe(Cfg.BountyPieces)
		end)

		it("adds a guaranteed piece to a bounty's first win once unlocked", function()
			local h = boot()
			local p = hunter(h)
			squad(h, p, true)
			local b = h:System("Expeditions"):Bounties(p)[1]
			local res = h:Call(p, "Expeditions.Fight", { region = b.region, stage = b.stage })
			expect(res.win).toBe(true)
			expect(find(res.rewards, "map_piece").amount).toBe(Cfg.BountyPieces)
			expect(h:System("TreasureMaps"):Pieces(p)).toBe(Cfg.BountyPieces)

			local h2 = boot()
			local p2 = hunter(h2, { level = UNLOCK - 1 })
			squad(h2, p2, true)
			local b2 = h2:System("Expeditions"):Bounties(p2)[1]
			local res2 = h2:Call(p2, "Expeditions.Fight", { region = b2.region, stage = b2.stage })
			expect(res2.win).toBe(true)
			expect(find(res2.rewards, "map_piece")).toBeNil()
		end)

		-- The Fishing spec's bot: follows the fish until the catch.
		local function castAndCatch(h, p)
			local FC = Config.Fishing
			local start = h:Call(p, "Fishing.Start")
			local course = FishLogic.Course(start.seed, start.bonus)
			local state = FishLogic.NewState()
			local inputs = {}
			local down = false
			while not state.done do
				local t0 = state.i * FC.Step
				local fy = FishLogic.FishAt(course, t0 + 0.2)
				local want = state.zone + state.vel * 0.3 < fy
				if want ~= down then
					down = want
					table.insert(inputs, { t = math.floor(t0 * 1000 + 0.5) / 1000, down = want })
				end
				FishLogic.Advance(state, course, inputs)
			end
			h:Advance(state.time + 0.1)
			return h:Call(p, "Fishing.Finish", { run = start.run, inputs = inputs })
		end

		it("rolls a piece on a fishing catch once unlocked", function()
			forced(1, function()
				local h = boot()
				local p = hunter(h)
				local got = nil
				for _ = 1, 3 do
					local res = castAndCatch(h, p)
					if res.caught then
						got = res
						break
					end
					h:Advance(1)
				end
				expect(got ~= nil).toBe(true)
				expect(find(got.rewards, "map_piece").amount).toBe(1)
				expect(h:System("TreasureMaps"):Pieces(p)).toBe(1)

				local h2 = boot()
				local p2 = hunter(h2, { level = UNLOCK - 1 })
				for _ = 1, 3 do
					local res = castAndCatch(h2, p2)
					expect(find(res.rewards, "map_piece")).toBeNil()
					h2:Advance(1)
				end
				expect(h2:System("TreasureMaps"):Pieces(p2)).toBe(0)
			end)
		end)

		local function digFind(h, p)
			local DC = Config.DigSite
			local s = h:Section(p, "DigSite")
			s.secret = 424242
			for n = 1, 5000 do
				local finds = DigLogic.Layout(DigLogic.Seed(p.UserId, n, s.secret))
				if #finds >= 1 then
					s.n = n - 1
					s.open = false
					h:Advance(0.6)
					local start = h:Call(p, "DigSite.Start")
					expect(start.dig).toBe(n)
					expect(DC.Tiles >= finds[1].tile).toBe(true)
					return h:Call(p, "DigSite.Tap", { dig = start.dig, tile = finds[1].tile })
				end
			end
			error("no dig matched")
		end

		it("rolls a piece on a dig find once unlocked", function()
			forced(1, function()
				local h = boot()
				local p = hunter(h)
				local res = digFind(h, p)
				expect(res.find ~= nil).toBe(true)
				expect(find(res.rewards, "map_piece").amount).toBe(1)
				expect(h:System("TreasureMaps"):Pieces(p)).toBe(1)

				local h2 = boot()
				local p2 = hunter(h2, { level = UNLOCK - 1 })
				local res2 = digFind(h2, p2)
				expect(find(res2.rewards, "map_piece")).toBeNil()
			end)
		end)
	end)

	describe("Digging up the treasure", function()
		it("fights the guardian: a win opens the chest, publishes TreasureOpened and uses the map", function()
			local h, opened = boot()
			local p = hunter(h)
			squad(h, p, true)
			local TM = h:System("TreasureMaps")
			TM:AddPieces(p, 4)
			local map = table.clone(TM:Maps(p)[1])
			local gems = h:Section(p, "Currency").gems
			local res = dig(h, p, map.id)
			expect(res.win).toBe(true)
			expect(res.map).toBe(map.id)
			expect(res.region).toBe("meadow")
			expect(type(res.replay.events)).toBe("table")
			expect(res.maps).toBe(0)
			expect(find(res.rewards, "coins") ~= nil).toBe(true)
			expect(find(res.rewards, "egg").id).toBe(Logic.Egg("meadow", map.stage))
			expect(h:Section(p, "Currency").gems - gems).toBe(Cfg.ChestGems)
			expect(#res.rewards).toBe(#Logic.Chest(map))
			expect(#TM:Maps(p)).toBe(0)
			expect(h:Section(p, "TreasureMaps").opened).toBe(1)
			expect(#opened).toBe(1)
			expect(opened[1].detail.region).toBe("meadow")
			-- One-shot: the map is used.
			h:Advance(1)
			expect(h:Reject(p, "TreasureMaps.Dig", { map = map.id })).toBe("That map is gone")
		end)

		it("keeps the map on a loss, at no cost, and a retry is allowed", function()
			local h, opened = boot()
			local p = hunter(h)
			squad(h, p, false)
			local TM = h:System("TreasureMaps")
			TM:AddPieces(p, 4)
			local id = TM:Maps(p)[1].id
			local coins = h:Section(p, "Currency").coins
			local res = dig(h, p, id)
			expect(res.win).toBe(false)
			expect(#res.rewards).toBe(0)
			expect(res.maps).toBe(1)
			expect(#TM:Maps(p)).toBe(1)
			expect(h:Section(p, "Currency").coins).toBe(coins)
			local again = dig(h, p, id)
			expect(again.win).toBe(false)
			expect(h:Section(p, "TreasureMaps").digs).toBe(2)
			expect(#opened).toBe(0)
		end)

		it("needs a squad", function()
			local h = boot()
			local p = hunter(h)
			local TM = h:System("TreasureMaps")
			TM:AddPieces(p, 4)
			expect(h:Reject(p, "TreasureMaps.Dig", { map = TM:Maps(p)[1].id })).toBe("Pick a squad first")
		end)

		it("makes a waiting set into a map once a win frees room", function()
			local h = boot()
			local p = hunter(h)
			squad(h, p, true)
			local TM = h:System("TreasureMaps")
			TM:AddPieces(p, Cfg.PiecesPerMap * (Cfg.MaxMaps + 1))
			expect(#TM:Maps(p)).toBe(Cfg.MaxMaps)
			expect(TM:Pieces(p)).toBe(Cfg.PiecesPerMap)
			dig(h, p, TM:Maps(p)[1].id)
			expect(#TM:Maps(p)).toBe(Cfg.MaxMaps)
			expect(TM:Pieces(p)).toBe(0)
		end)

		it("has the treasure_2 weekly goal counting chests opened", function()
			local goal = Config.Weekly.ById.treasure_2
			expect(goal.family).toBe("treasure")
			expect(goal.unlock).toBe("treasure_maps")
			expect(goal.topic).toBe("TreasureOpened")
			expect(goal.target).toBe(2)
			local h = boot()
			local p = hunter(h)
			squad(h, p, true)
			local TM = h:System("TreasureMaps")
			TM:AddPieces(p, 8)
			h:Section(p, "Weekly").goals = { { id = "treasure_2", progress = 0 } }
			dig(h, p, TM:Maps(p)[1].id)
			dig(h, p, TM:Maps(p)[1].id)
			expect(h:Section(p, "Weekly").goals[1].progress).toBe(2)
		end)
	end)
end
