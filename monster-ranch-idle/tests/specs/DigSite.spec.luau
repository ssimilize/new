--[[
	DigSite (update 3.11 · Seasons & secrets): the Dig Site. The seeded layout, taps (finds and
	warm / cold hints), one-shot dig ids and no reroll by reopening, daily free digs and shovels,
	fossil pieces (duplicates turn into amber, a complete fossil grants its skeleton display),
	relics, the Amber Egg, the Codex Fossils milestones, bounty shovels and the weekly goal.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.DigSite")

	local Cfg = Config.DigSite
	local DAY = 86400

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Decor", "DigSite", "Codex", "Weekly" }

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function boot()
		local h = TestKernel.new({ systems = SYSTEMS })
		local found, finished = {}, {}
		h.kernel.Bus:Subscribe("FossilFound", function(player, detail)
			table.insert(found, { player = player, detail = detail })
		end)
		h.kernel.Bus:Subscribe("DigFinished", function(player, detail)
			table.insert(finished, { player = player, detail = detail })
		end)
		return h, found, finished
	end

	local function digger(h)
		local p = h:Join()
		levelTo(h, p, 16)
		return p
	end

	-- The layout of the player's open dig, worked out the way the server does.
	local function layout(h, p)
		local s = h:Section(p, "DigSite")
		return Logic.Layout(Logic.Seed(p.UserId, s.open.id, s.secret))
	end

	-- Sets up a dig whose layout satisfies `want(finds)` by moving the dig number on.
	local function rigDig(h, p, want)
		local s = h:Section(p, "DigSite")
		if s.secret == 0 then
			s.secret = 424242 -- the server draws one on the first dig; a fixed one keeps the search stable
		end
		for n = 1, 5000 do
			local finds = Logic.Layout(Logic.Seed(p.UserId, n, s.secret))
			if want(finds) then
				s.n = n - 1
				s.open = false
				h:Advance(0.6)
				local res = h:Call(p, "DigSite.Start")
				expect(res.dig).toBe(n)
				return finds
			end
		end
		error("no dig matched")
	end

	local function emptyTile(finds): number
		for n = 1, Cfg.Tiles do
			local hit = false
			for _, f in finds do
				hit = hit or f.tile == n
			end
			if not hit then
				return n
			end
		end
		error("no empty tile")
	end

	describe("Logic", function()
		it("lays the same finds out from the same seed, on distinct tiles, 1 or 2 of them", function()
			local ones, twos = 0, 0
			local kinds = {}
			for seed = 1, 2000 do
				local a, b = Logic.Layout(seed), Logic.Layout(seed)
				expect(#a).toBe(#b)
				expect(#a >= 1 and #a <= 2).toBe(true)
				if #a == 1 then
					ones += 1
				else
					twos += 1
					expect(a[1].tile ~= a[2].tile).toBe(true)
				end
				for i, f in a do
					expect(f.tile).toBe(b[i].tile)
					expect(f.kind).toBe(b[i].kind)
					expect(f.tile >= 1 and f.tile <= Cfg.Tiles).toBe(true)
					kinds[f.kind] = (kinds[f.kind] or 0) + 1
					if f.kind == "piece" then
						expect(Cfg.ById[f.fossil] ~= nil and Cfg.PieceById[f.piece] ~= nil).toBe(true)
					elseif f.kind == "amber" then
						expect(f.amount >= Cfg.Amber[1] and f.amount <= Cfg.Amber[2]).toBe(true)
					elseif f.kind == "relic" then
						expect(Config.Decor.ById[f.id] ~= nil).toBe(true)
					else
						expect(f.id).toBe(Cfg.Egg)
					end
				end
			end
			expect(math.abs(twos / 2000 - Cfg.TwoFindChance) < 0.05).toBe(true)
			expect(kinds.piece > kinds.amber and kinds.amber > kinds.relic).toBe(true)
			expect((kinds.egg or 0) > 0).toBe(true)
		end)

		it("measures hints along rows and columns and seeds per user and dig number", function()
			expect(Logic.Distance(1, 1)).toBe(0)
			expect(Logic.Distance(1, 2)).toBe(1)
			expect(Logic.Distance(1, Cfg.Grid + 1)).toBe(1)
			expect(Logic.Distance(1, Cfg.Tiles)).toBe((Cfg.Grid - 1) * 2)
			local finds = { { tile = 13 }, { tile = 25 } }
			expect(Logic.Hint(finds, {}, 12)).toBe(1)
			expect(Logic.Hint(finds, { [13] = true }, 12)).toBe(Logic.Distance(12, 25))
			expect(Logic.Hint(finds, { [13] = true, [25] = true }, 12)).toBe(0)
			expect(Logic.HintText(1)).toBe("Hot!")
			expect(Logic.HintText(4)).toBe("Cold")
			expect(Logic.Seed(1, 1, 7)).toBe(Logic.Seed(1, 1, 7))
			expect(Logic.Seed(1, 1, 7) ~= Logic.Seed(1, 2, 7)).toBe(true)
			expect(Logic.Seed(1, 1, 7) ~= Logic.Seed(2, 1, 7)).toBe(true)
		end)
	end)

	describe("Digging", function()
		it("resolves taps against the hidden layout: finds, hints and the end of the dig", function()
			local h, _, finished = boot()
			local p = digger(h)
			local start = h:Call(p, "DigSite.Start")
			expect(start.left).toBe(Cfg.Taps)
			expect(start.digs).toBe(Cfg.FreeDigs - 1)
			expect(#start.tiles).toBe(0)
			expect(start.resumed).toBe(false)
			local finds = layout(h, p)
			local miss = emptyTile(finds)
			local res = h:Call(p, "DigSite.Tap", { dig = start.dig, tile = miss })
			expect(res.find).toBeNil()
			expect(res.hint).toBe(Logic.Hint(finds, {}, miss))
			expect(res.left).toBe(Cfg.Taps - 1)
			expect(res.done).toBe(false)
			expect(h:Reject(p, "DigSite.Tap", { dig = start.dig, tile = miss })).toBe("You already dug there")
			-- Every find dug up ends the dig early.
			for i, f in finds do
				res = h:Call(p, "DigSite.Tap", { dig = start.dig, tile = f.tile })
				expect(res.find ~= nil).toBe(true)
				expect(res.find.kind).toBe(f.kind)
				expect(res.done).toBe(i == #finds)
			end
			expect(#res.missed).toBe(0)
			expect(h:Section(p, "DigSite").open).toBe(false)
			expect(h:Section(p, "DigSite").total).toBe(1)
			expect(#finished).toBe(1)
			expect(finished[1].detail.finds).toBe(#finds)
			-- The id is spent.
			expect(h:Reject(p, "DigSite.Tap", { dig = start.dig, tile = 1 })).toBe("That dig is over. Start a new one!")
		end)

		it("ends after Taps taps and names the finds left buried; never rerolls on reopening", function()
			local h = boot()
			local p = digger(h)
			local finds = rigDig(h, p, function(list)
				return #list == 2
			end)
			local dig = h:Section(p, "DigSite").open.id
			-- Reopening (Start again) resumes the same dig without spending a dig.
			h:Advance(0.6)
			local again = h:Call(p, "DigSite.Start")
			expect(again.resumed).toBe(true)
			expect(again.dig).toBe(dig)
			expect(again.digs).toBe(Cfg.FreeDigs - 1)
			local taps, res = 0, nil
			for n = 1, Cfg.Tiles do
				if n ~= finds[1].tile and n ~= finds[2].tile then
					res = h:Call(p, "DigSite.Tap", { dig = dig, tile = n })
					taps += 1
					if taps == Cfg.Taps then
						break
					end
				end
			end
			expect(res.done).toBe(true)
			expect(#res.missed).toBe(2)
			expect(h:Section(p, "DigSite").open).toBe(false)
			expect(h:Reject(p, "DigSite.Tap", { dig = dig, tile = finds[1].tile })).toBe("That dig is over. Start a new one!")
			expect(h:Reject(p, "DigSite.Tap", { dig = dig, tile = 0 }) ~= nil).toBe(true)
			expect(h:Reject(p, "DigSite.Tap", { dig = dig, tile = Cfg.Tiles + 1 }) ~= nil).toBe(true)
		end)

		it("gives FreeDigs a day, then spends shovels, and resets at the UTC day", function()
			local h = boot()
			local locked = h:Join()
			expect(h:Reject(locked, "DigSite.Start")).toBe("Unlocks at Ranch Level 16")
			local p = digger(h)
			local s = h:Section(p, "DigSite")
			for i = 1, Cfg.FreeDigs do
				h:Advance(0.6)
				local res = h:Call(p, "DigSite.Start")
				expect(res.digs).toBe(Cfg.FreeDigs - i)
				s.open = false -- walk away from it (tests only)
			end
			h:Advance(0.6)
			expect(h:Reject(p, "DigSite.Start")).toBe("No digs left today. Use a shovel or come back tomorrow")
			expect(h:System("DigSite"):AddShovels(p, 1)).toBe(1)
			h:System("Rewards"):Grant(p, { { kind = "shovel", amount = 1 } }, "test")
			expect(s.shovels).toBe(2)
			h:Advance(0.6)
			expect(h:Call(p, "DigSite.Start").shovels).toBe(1)
			s.open = false
			h:Advance(0.6)
			expect(h:Call(p, "DigSite.Start").shovels).toBe(0)
			s.open = false
			h:Advance(0.6)
			expect(h:Reject(p, "DigSite.Start")).toBe("No digs left today. Use a shovel or come back tomorrow")
			h:Advance(DAY)
			expect(h:Call(p, "DigSite.Start").digs).toBe(Cfg.FreeDigs - 1)
			expect(h:System("DigSite"):AddShovels(p, 10 ^ 6)).toBe(Cfg.MaxShovels)
		end)
	end)

	describe("Finds", function()
		it("keeps new pieces, turns a duplicate into amber and publishes FossilFound", function()
			local h, found = boot()
			local p = digger(h)
			local finds = rigDig(h, p, function(list)
				return list[1].kind == "piece"
			end)
			local f = finds[1]
			local dig = h:Section(p, "DigSite").open.id
			local res = h:Call(p, "DigSite.Tap", { dig = dig, tile = f.tile })
			expect(res.find.fossil).toBe(f.fossil)
			expect(res.find.piece).toBe(f.piece)
			expect(res.find.duplicate).toBeNil()
			expect(h:Section(p, "DigSite").pieces[f.fossil][f.piece]).toBe(true)
			expect(#found).toBe(1)
			expect(found[1].detail.fossil).toBe(f.fossil)
			expect(found[1].detail.piece).toBe(f.piece)
			expect(found[1].detail.complete).toBe(false)

			-- The same piece again: amber instead.
			local s = h:Section(p, "DigSite")
			s.open = false
			local secret = s.secret
			local again
			for n = s.n + 1, s.n + 20000 do
				local l = Logic.Layout(Logic.Seed(p.UserId, n, secret))
				if l[1].kind == "piece" and l[1].fossil == f.fossil and l[1].piece == f.piece then
					s.n = n - 1
					again = l[1]
					break
				end
			end
			expect(again ~= nil).toBe(true)
			h:Advance(0.6)
			dig = h:Call(p, "DigSite.Start").dig
			local amber = h:System("Currency"):Balance(p, "amber")
			res = h:Call(p, "DigSite.Tap", { dig = dig, tile = again.tile })
			expect(res.find.duplicate).toBe(true)
			expect(h:System("Currency"):Balance(p, "amber")).toBe(amber + Cfg.DuplicateAmber)
			expect(#found).toBe(1)
		end)

		it("completes a fossil with its fourth piece and grants the skeleton display once", function()
			local h, found = boot()
			local p = digger(h)
			local finds = rigDig(h, p, function(list)
				return list[1].kind == "piece"
			end)
			local f = finds[1]
			local have = {}
			for _, piece in Cfg.Pieces do
				if piece.id ~= f.piece then
					have[piece.id] = true
				end
			end
			h:Section(p, "DigSite").pieces[f.fossil] = have
			local decor = Cfg.ById[f.fossil].decor
			expect(Config.Decor.ById[decor] ~= nil).toBe(true)
			local res = h:Call(p, "DigSite.Tap", { dig = h:Section(p, "DigSite").open.id, tile = f.tile })
			expect(res.find.complete).toBe(true)
			expect(found[#found].detail.complete).toBe(true)
			local gotDecor = false
			for _, item in res.rewards do
				gotDecor = gotDecor or (item.kind == "decor" and item.id == decor)
			end
			expect(gotDecor).toBe(true)
			expect(h:System("DigSite"):FossilsComplete(p)).toBe(1)
		end)

		it("pays amber, relic decor and the Amber Egg", function()
			local h = boot()
			local p = digger(h)
			for _, kind in { "amber", "relic", "egg" } do
				local finds = rigDig(h, p, function(list)
					return list[1].kind == kind
				end)
				local res = h:Call(p, "DigSite.Tap", { dig = h:Section(p, "DigSite").open.id, tile = finds[1].tile })
				expect(res.find.kind).toBe(kind)
				expect(#res.rewards > 0).toBe(true)
				local item = res.rewards[1]
				if kind == "amber" then
					expect(item.kind).toBe("amber")
					expect(item.amount).toBe(finds[1].amount)
				elseif kind == "relic" then
					expect(item.kind).toBe("decor")
					expect(item.id).toBe(finds[1].id)
				else
					expect(item.kind).toBe("egg")
					expect(item.id).toBe("amber")
				end
				h:Section(p, "DigSite").open = false
			end
			expect(h:System("Currency"):Balance(p, "amber") > 0).toBe(true)
		end)

		it("makes the Amber Egg a never-sold egg that hatches Stone, Sprout and Gloom lines", function()
			local egg = Config.Eggs.ById.amber
			expect(egg ~= nil).toBe(true)
			expect(egg.price).toBeNil()
			expect(egg.unlock).toBe("dig_site")
			local maxOrder = 0
			for _, e in Config.Eggs.List do
				if e.id ~= "amber" then
					maxOrder = math.max(maxOrder, e.order)
				end
			end
			expect(egg.order).toBe(maxOrder + 1)
			local pool = Config.Species.Pools.amber
			expect(#pool > 0).toBe(true)
			for _, lineId in pool do
				local el = Config.Species.ById[lineId].elements[1]
				expect(el == "stone" or el == "sprout" or el == "gloom").toBe(true)
			end
			-- Better rarity odds than the Meadow Egg's.
			expect(egg.odds[1]).toBe(0)
		end)
	end)

	describe("Rewards and goals", function()
		it("pays the Fossils milestones through Codex.Claim", function()
			local h = boot()
			local p = digger(h)
			local s = h:Section(p, "DigSite")
			local all = {}
			for _, piece in Cfg.Pieces do
				all[piece.id] = true
			end
			s.pieces = { raptor = table.clone(all) }
			expect(h:Reject(p, "Codex.Claim", { milestone = "fossil_2" })).toBe("Complete 1 more fossils first")
			s.pieces.trihorn = table.clone(all)
			local gems = h:Section(p, "Currency").gems
			local res = h:Call(p, "Codex.Claim", { milestone = "fossil_2" })
			expect(res.gems).toBe(Config.Codex.Gems.fossil[1])
			expect(h:Section(p, "Currency").gems).toBe(gems + res.gems)
			expect(h:Reject(p, "Codex.Claim", { milestone = "fossil_2" })).toBe("Already claimed")
			expect(h:Reject(p, "Codex.Claim", { milestone = "fossil_4" })).toBe("Complete 2 more fossils first")
		end)

		it("puts shovels in the bounty reward and a dig_10 weekly goal on DigFinished", function()
			local shovel = nil
			for _, item in Config.Bounties.Reward do
				if item.kind == "shovel" then
					shovel = item
				end
			end
			expect(shovel ~= nil and shovel.amount).toBe(2)
			local goal = Config.Weekly.ById.dig_10
			expect(goal.family).toBe("digsite")
			expect(goal.unlock).toBe("dig_site")
			expect(goal.topic).toBe("DigFinished")
			expect(goal.target).toBe(10)
			expect(Config.Unlocks.Features.dig_site).toBe(16)
		end)

		it("keeps the secret out of replication and drops a damaged open dig on join", function()
			local h = boot()
			local p = digger(h)
			h:Call(p, "DigSite.Start")
			local s = h:Section(p, "DigSite")
			expect(s.secret ~= 0).toBe(true)
			local spec = h:System("DigSite").Profile
			expect(table.find(spec.Private, "secret") ~= nil).toBe(true)
			s.open = { id = s.n + 5, left = 3, tiles = {} }
			s.pieces.nope = { skull = true }
			h:System("DigSite").PlayerAdded(p)
			expect(s.open).toBe(false)
			expect(s.pieces.nope).toBeNil()
		end)
	end)
end
