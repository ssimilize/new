-- S6 Monetization: pass caching, idempotent receipts, product handlers, rewarded ads, policy.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local M = Config.Monetization

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Monetization" }

	-- Temporarily gives Config items real ids; always restored so other specs see stock config.
	local function withIds(passIds: { [string]: number }, productIds: { [string]: number }, fn)
		local saved = {}
		for key, id in passIds do
			saved["pass." .. key] = M.PassByKey[key].gamePassId
			M.PassByKey[key].gamePassId = id
		end
		for key, id in productIds do
			saved["product." .. key] = M.ProductByKey[key].productId
			M.ProductByKey[key].productId = id
		end
		local ok, err = pcall(fn)
		for key in passIds do
			M.PassByKey[key].gamePassId = saved["pass." .. key]
		end
		for key in productIds do
			M.ProductByKey[key].productId = saved["product." .. key]
		end
		if not ok then
			error(err, 0)
		end
	end

	local function receipt(h, p, productId: number, purchaseId: string, spent: number?)
		return h.adapters._processReceipt({
			PlayerId = p.UserId,
			ProductId = productId,
			PurchaseId = purchaseId,
			CurrencySpent = spent or 49,
		})
	end

	local function topicLog(h, topic: string)
		local seen = {}
		h.kernel.Bus:Subscribe(topic, function(player, detail)
			table.insert(seen, { player = player, detail = detail })
		end)
		return seen
	end

	describe("Monetization passes", function()
		it("caches ownership on join with every pass key, and HasPass reads the cache", function()
			withIds({ doubleCoins = 9001, vip = 9002 }, {}, function()
				local h = TestKernel.new({ systems = SYSTEMS })
				h.adapters.ownedPasses[5001] = { [9001] = true }
				local p = h:Join(5001)
				local Mon = h:System("Monetization")
				expect(Mon:HasPass(p, "doubleCoins")).toBe(true)
				expect(Mon:HasPass(p, "vip")).toBe(false)
				expect(Mon:HasPass(p, "nope")).toBe(false)
				local client = h:Client(p)
				expect(client.session.Monetization.passes.doubleCoins).toBe(true)
				for _, pass in M.Passes do
					expect(type(client.session.Monetization.passes[pass.key])).toBe("boolean")
				end
				-- The cache is not re-queried: HasPass never yields.
				h.adapters.ownedPasses[5001] = {}
				expect(Mon:HasPass(p, "doubleCoins")).toBe(true)
			end)
		end)

		it("publishes PassesChanged on join when a pass is owned", function()
			withIds({ bigBarn = 9003 }, {}, function()
				local h = TestKernel.new({ systems = SYSTEMS })
				local changed = topicLog(h, "PassesChanged")
				h.adapters.ownedPasses[5002] = { [9003] = true }
				h:Join(5002)
				expect(#changed).toBe(1)
				expect(changed[1].detail.passes.bigBarn).toBe(true)
				h:Join(5003)
				expect(#changed).toBe(1)
			end)
		end)

		it("unlocks passes bought live and through RefreshPasses", function()
			withIds({ explorer = 9004, vip = 9005 }, {}, function()
				local h = TestKernel.new({ systems = SYSTEMS })
				local p = h:Join()
				local Mon = h:System("Monetization")
				local changed = topicLog(h, "PassesChanged")
				local rates = topicLog(h, "RateModifiersChanged")

				h.adapters._onPassPurchased(p, 9004)
				expect(Mon:HasPass(p, "explorer")).toBe(true)
				expect(#changed).toBe(1)
				expect(#rates).toBe(1)
				expect(h:LastEvent(p, "Kernel.Notify").payload.text).toContain("Explorer")
				h.adapters._onPassPurchased(p, 9004) -- duplicate signal: no second publish
				h.adapters._onPassPurchased(p, 12345) -- unknown pass id: ignored
				expect(#changed).toBe(1)

				h.adapters.ownedPasses[p.UserId] = { [9005] = true }
				local data = h:Call(p, "Monetization.RefreshPasses")
				expect(data.passes.vip).toBe(true)
				expect(data.passes.explorer).toBe(true) -- never revoked by a refresh
				expect(#changed).toBe(2)
				h:Call(p, "Monetization.RefreshPasses") -- burst of 2, then rate limited
				expect(h:Reject(p, "Monetization.RefreshPasses")).toBe("TooFast")
				expect(h:Client(p).session.Monetization.passes.vip).toBe(true)
			end)
		end)

		it("ignores gamePassId 0 (Studio) and never asks the Marketplace for it", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local asked = 0
			local owns = h.adapters.Marketplace.OwnsPass
			h.adapters.Marketplace.OwnsPass = function(player, id)
				asked += 1
				return owns(player, id)
			end
			local p = h:Join()
			expect(asked).toBe(0)
			expect(h:System("Monetization"):HasPass(p, "autoCollect")).toBe(false)
		end)
	end)

	describe("Monetization policy", function()
		it("caches paid-random policy and fails closed", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			h.adapters.restrictedPaidRandom[5010] = true
			local restricted = h:Join(5010)
			local free = h:Join(5011)
			local Mon = h:System("Monetization")
			expect(Mon:PaidRandomAllowed(restricted)).toBe(false)
			expect(Mon:PaidRandomAllowed(free)).toBe(true)
			expect(h:Client(restricted).session.Monetization.paidRandomAllowed).toBe(false)
			expect(Mon:PaidRandomAllowed({ UserId = 1 })).toBe(false) -- unknown player
		end)
	end)

	describe("Monetization receipts", function()
		it("grants a product once per PurchaseId and records it privately", function()
			withIds({}, { gems100 = 7001 }, function()
				local h = TestKernel.new({ systems = SYSTEMS })
				local p = h:Join()
				local purchases = topicLog(h, "Purchase")
				expect(receipt(h, p, 7001, "x1", 49)).toBe("PurchaseGranted")
				expect(receipt(h, p, 7001, "x1", 49)).toBe("PurchaseGranted")
				expect(h:Section(p, "Currency").gems).toBe(100)
				expect(#purchases).toBe(1)
				expect(purchases[1].detail.product).toBe("gems100")
				expect(purchases[1].detail.robux).toBe(49)
				expect(receipt(h, p, 7001, "x2", 49)).toBe("PurchaseGranted")
				expect(h:Section(p, "Currency").gems).toBe(200)
				expect(#h:Section(p, "Monetization").receipts).toBe(2)
				expect(h:Client(p).profile.Monetization.receipts).toBeNil()
			end)
		end)

		it("survives a rejoin: a replayed receipt is still recognised", function()
			withIds({}, { gems100 = 7001 }, function()
				local h = TestKernel.new({ systems = SYSTEMS })
				local p = h:Join()
				receipt(h, p, 7001, "r1")
				local p2 = h:Rejoin(p, 60)
				expect(receipt(h, p2, 7001, "r1")).toBe("PurchaseGranted")
				expect(h:Section(p2, "Currency").gems).toBe(100)
			end)
		end)

		it("returns NotProcessedYet for unknown products and players not in the server", function()
			withIds({}, { gems100 = 7001 }, function()
				local h = TestKernel.new({ systems = SYSTEMS })
				local p = h:Join()
				expect(receipt(h, p, 424242, "u1")).toBe("NotProcessedYet")
				expect(t.warnings[#t.warnings]).toContain("unknown developer product")
				expect(receipt(h, { UserId = 999999 }, 7001, "u2")).toBe("NotProcessedYet")
				expect(receipt(h, p, 0, "u3")).toBe("NotProcessedYet")
				expect(h:Section(p, "Currency").gems).toBe(0)
			end)
		end)

		it("honours oncePerAccount", function()
			withIds({}, { starterPack = 7002 }, function()
				local h = TestKernel.new({ systems = SYSTEMS })
				local p = h:Join()
				expect(receipt(h, p, 7002, "s1", 99)).toBe("PurchaseGranted")
				expect(h:Section(p, "Currency").gems).toBe(300)
				expect(h:Section(p, "Monetization").once.starterPack).toBe(true)
				expect(h:Client(p).profile.Monetization.once.starterPack).toBe(true)
				expect(receipt(h, p, 7002, "s2", 99)).toBe("NotProcessedYet")
				expect(h:Section(p, "Currency").gems).toBe(300)
			end)
		end)

		it("routes handler products and retries when the handler is missing or refuses", function()
			withIds({}, { totemRain = 7003 }, function()
				local h = TestKernel.new({ systems = SYSTEMS })
				local p = h:Join()
				local Mon = h:System("Monetization")
				expect(receipt(h, p, 7003, "t1")).toBe("NotProcessedYet") -- nobody registered Weather.Totem

				local calls = {}
				local accept = false
				Mon:RegisterProduct("Weather.Totem", function(player, product, info)
					table.insert(calls, { player = player, weather = product.args.weather, id = info.PurchaseId })
					return accept
				end)
				expect(receipt(h, p, 7003, "t1")).toBe("NotProcessedYet")
				accept = true
				expect(receipt(h, p, 7003, "t1")).toBe("PurchaseGranted")
				expect(receipt(h, p, 7003, "t1")).toBe("PurchaseGranted")
				expect(#calls).toBe(2)
				expect(calls[2].weather).toBe("rain")
				expect(calls[2].player).toBe(p)
			end)
		end)

		it("treats an erroring handler as not processed", function()
			withIds({}, { totemThunder = 7004 }, function()
				local h = TestKernel.new({ systems = SYSTEMS })
				local p = h:Join()
				h:System("Monetization"):RegisterProduct("Weather.Totem", function()
					error("boom")
				end)
				expect(receipt(h, p, 7004, "e1")).toBe("NotProcessedYet")
				expect(#h:Section(p, "Monetization").receipts).toBe(0)
			end)
		end)

		it("keeps only the newest receipts", function()
			withIds({}, { gems100 = 7001 }, function()
				local h = TestKernel.new({ systems = SYSTEMS })
				local p = h:Join()
				for i = 1, M.ReceiptHistory + 5 do
					receipt(h, p, 7001, "bulk" .. i)
				end
				local list = h:Section(p, "Monetization").receipts
				expect(#list).toBe(M.ReceiptHistory)
				expect(list[1].id).toBe("bulk6")
				expect(list[#list].id).toBe("bulk" .. (M.ReceiptHistory + 5))
			end)
		end)
	end)

	describe("Monetization ads", function()
		it("counts completed views up to the daily cap and resets next UTC day", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p = h:Join()
			local Mon = h:System("Monetization")
			local watched = topicLog(h, "AdWatched")
			local cap = M.Ads.hatchRush.cap
			expect(Mon:AdsLeft(p, "hatchRush")).toBe(cap)
			for _ = 1, cap do
				expect(Mon:WatchAd(p, "hatchRush")).toBe(true)
			end
			expect(Mon:AdsLeft(p, "hatchRush")).toBe(0)
			expect(Mon:WatchAd(p, "hatchRush")).toBe(false)
			local ok, why = Mon:CanWatchAd(p, "hatchRush")
			expect(ok).toBe(false)
			expect(why).toContain("tomorrow")
			expect(#watched).toBe(cap)
			expect(#h.adapters.log.ads).toBe(cap) -- the capped call never showed an ad
			expect(Mon:AdsLeft(p, "welcomeDouble")).toBe(M.Ads.welcomeDouble.cap)
			expect(h:Client(p).profile.Monetization.ads.counts.hatchRush).toBe(cap)

			h:Advance(86400)
			expect(Mon:AdsLeft(p, "hatchRush")).toBe(cap)
			expect(Mon:WatchAd(p, "hatchRush")).toBe(true)
			expect(h:Section(p, "Monetization").ads.counts.hatchRush).toBe(1)
		end)

		it("does not count skipped ads", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p = h:Join()
			local Mon = h:System("Monetization")
			h.adapters.adResult = false
			expect(Mon:WatchAd(p, "freeEgg")).toBe(false)
			expect(Mon:AdsLeft(p, "freeEgg")).toBe(1)
			h.adapters.adResult = true
			expect(Mon:WatchAd(p, "freeEgg")).toBe(true)
			expect(Mon:AdsLeft(p, "freeEgg")).toBe(0)
		end)

		it("respects the RewardedAds flag and unknown placements", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p = h:Join()
			local Mon = h:System("Monetization")
			expect(Mon:WatchAd(p, "notAPlacement")).toBe(false)
			expect(Mon:AdsLeft(p, "notAPlacement")).toBe(0)
			Config.Flags.RewardedAds = false
			local ok = pcall(function()
				expect(Mon:WatchAd(p, "stageRetry")).toBe(false)
				expect(Mon:AdsLeft(p, "stageRetry")).toBe(0)
			end)
			Config.Flags.RewardedAds = true
			expect(ok).toBe(true)
			expect(#h.adapters.log.ads).toBe(0)
		end)
	end)
end
