--[[
	Foundry (wave 0): the vendored Foundry packages (src/shared/Foundry, `foundry sync --game
	monster-ranch`) reach the game only through kernel.Foundry, built by Shared.Kernel.FoundryAdapter
	and its two realm wrappers (Server.Kernel.ServerFoundry, client Kernel/ClientFoundry). Nothing
	in the game reads it yet, so nothing a player sees or hears changes.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness

	local FoundryAdapter = t.Shared("Kernel.FoundryAdapter")
	local ServerFoundry = t.Server("Kernel.ServerFoundry")
	local Bus = t.Server("Kernel.Bus")
	local Api = t.Shared("Kernel.Api")
	local RanchRng = t.Shared("Logic.Rng")
	local Contract = t.Shared("Foundry.Contract.Contract")
	local Game = t.Shared("Foundry.Game.Game")

	local folder = t.Loader.game:GetService("ReplicatedStorage").Shared:FindFirstChild("Foundry")

	local function server(opts: { [string]: any }?)
		local o = opts or {}
		local warned = {}
		local bus = o.Bus or Bus.new(Api.Topics)
		local foundry = ServerFoundry.new({
			folder = if o.noFolder then nil else folder,
			requireModule = t.Loader.require,
			Bus = bus,
			serverTime = function()
				return 1234.5
			end,
			quality = o.quality,
			warn = function(msg)
				table.insert(warned, msg)
			end,
			print = function() end,
		})
		return foundry, bus, warned
	end

	describe("discovery", function()
		it("finds the vendored Contract and the generated Game module", function()
			local foundry, _, warned = server()
			expect(foundry.packages.Contract).toBe(Contract)
			expect(foundry.Contract).toBe(Contract)
			expect(foundry.game).toBe("monster-ranch")
			expect(foundry.budgets).toBe(Game.budgets)
			expect(foundry.packages.Game).toBe(nil)
			expect(#warned).toBe(0)
		end)

		it("with nothing vendored it is empty and says the Contract is missing only when asked for an rng", function()
			local foundry = server({ noFolder = true })
			expect(next(foundry.packages)).toBe(nil)
			expect(foundry.game).toBe(FoundryAdapter.DEFAULT_GAME)
			local adapter = foundry.adapter("Test")
			expect(adapter.budget("particles")).toBe(nil)
			expect(pcall(adapter.rng, 1)).toBe(false)
		end)

		it("skips a package that errors, with a warning, and keeps the rest", function()
			local function fake(name, children, isModule)
				local node = { Name = name, _children = children or {} }
				function node:GetChildren()
					return self._children
				end
				function node:FindFirstChild(n)
					for _, c in self._children do
						if c.Name == n then
							return c
						end
					end
					return nil
				end
				function node:IsA(class)
					return isModule == true and class == "ModuleScript"
				end
				return node
			end
			local good = fake("Good", { fake("Good", nil, true), fake("rules", { fake("ranch", nil, true) }) })
			local bad = fake("Bad", { fake("Bad", nil, true) })
			local values = { Good = { ok = true }, ranch = { rule = 1 } }
			local warned = {}
			local packages, _, rules = FoundryAdapter.discover(fake("Foundry", { bad, good }), function(m)
				if m.Name == "Bad" then
					error("boom")
				end
				return values[m.Name]
			end, function(msg)
				table.insert(warned, msg)
			end)
			expect(packages.Good).toBe(values.Good)
			expect(packages.Bad).toBe(nil)
			expect(rules.Good.ranch).toBe(values.ranch)
			expect(#warned).toBe(1)
		end)
	end)

	describe("the adapter", function()
		it("passes Contract.check on the server and on a booted client", function()
			local foundry = server()
			expect(Contract.check(foundry.adapter("Test"))).toEqual({})

			local h = TestKernel.new({ systems = {} })
			local c = ClientHarness.new(h, h:Join())
			local clientFoundry = c.kernel.Foundry
			expect(clientFoundry.game).toBe("monster-ranch")
			expect(clientFoundry.packages.Contract ~= nil).toBe(true)
			expect(#clientFoundry.Contract.check(clientFoundry.adapter("Test"))).toBe(0)
			local ctx = c.kernel:ScreenContext("FoundryProbe")
			expect(ctx.Foundry).toBe(clientFoundry)
		end)

		it("rng is the Foundry's mulberry32, and the same stream as the Ranch's own Rng", function()
			local adapter = server().adapter("Test")
			for _, seed in { 0, 1, 7, 42, 1234, 99999, 2 ^ 31, 4294967295, 1e9 + 7 } do
				local a, f, r = adapter.rng(seed), Contract.Rng.new(seed), RanchRng.new(seed)
				for _ = 1, 200 do
					local v = a:next()
					expect(v).toBe(f:next())
					expect(v).toBe(r:Next())
				end
				expect(a:state()).toBe(r:State())
				expect(a:int(1, 6)).toBe(r:Int(1, 6))
			end
		end)

		it("budget picks the profile's value by quality: high on the server, the client's level there", function()
			expect(server().adapter("Test").budget("particles")).toBe(600)
			for level, want in { 150, 320, 600 } do
				local adapter = server({
					quality = function()
						return level
					end,
				}).adapter("Test")
				expect(adapter.quality()).toBe(level)
				expect(adapter.budget("particles")).toBe(want)
				expect(adapter.budget("emitters")).toBe(120)
				expect(adapter.budget("noSuchBudget")).toBe(nil)
			end
		end)

		it("now is the world clock handed in, and log warns with the system's name", function()
			local foundry, _, warned = server()
			local adapter = foundry.adapter("Pens")
			expect(adapter.now()).toBe(1234.5)
			adapter.log("info", "quiet")
			adapter.log("warn", "loud")
			expect(warned).toEqual({ "[Pens] loud" })
		end)

		it("tag writes the MR_System attribute and never throws", function()
			local adapter = server().adapter("Test")
			local attrs = {}
			local inst = {}
			function inst:SetAttribute(k, v)
				attrs[k] = v
			end
			adapter.tag(inst, "Pens")
			expect(attrs.MR_System).toBe("Pens")
			adapter.tag({}, "Pens")
		end)
	end)

	describe("string requires (wave 1a)", function()
		local StringRequire = require("../runtime/StringRequire")

		local function tree()
			-- Foundry/{ Contract/{Contract}, Pkg/{Pkg, Helper, tables/{guild(init)/{part1}}} }
			local function node(name, parent)
				local n = { Name = name, Parent = parent, _kids = {} }
				function n:FindFirstChild(k)
					return self._kids[k]
				end
				if parent then
					parent._kids[name] = n
				end
				return n
			end
			local root = node("Foundry")
			local contractFolder = node("Contract", root)
			local contract = node("Contract", contractFolder)
			local pkg = node("Pkg", root)
			local main = node("Pkg", pkg)
			local helper = node("Helper", pkg)
			local guild = node("guild", node("tables", pkg))
			local part1 = node("part1", guild)
			return { contract = contract, main = main, helper = helper, guild = guild, part1 = part1 }
		end

		it("resolves ./, ../ and @self over instances, the way Roblox does", function()
			local n = tree()
			expect(StringRequire.resolve(n.main, "./Helper")).toBe(n.helper)
			expect(StringRequire.resolve(n.main, "../Contract/Contract")).toBe(n.contract)
			expect(StringRequire.resolve(n.main, "./tables/guild")).toBe(n.guild)
			expect(StringRequire.resolve(n.guild, "@self/part1")).toBe(n.part1)
			expect(StringRequire.resolve(n.part1, "../../Helper")).toBe(n.helper)
			expect(pcall(StringRequire.resolve, n.main, "./Missing")).toBe(false)
			expect(pcall(StringRequire.resolve, n.main, "Helper")).toBe(false)
		end)

		it("only the vendored packages may require by string", function()
			local root = "C:/r/monster-ranch-idle"
			expect(StringRequire.allowed(root .. "/src/shared/Foundry/Pkg/Pkg.luau", root)).toBe(true)
			expect(StringRequire.allowed("C:\\r\\monster-ranch-idle\\src\\shared\\Foundry\\Pkg\\Pkg.luau", root)).toBe(true)
			expect(StringRequire.allowed(root .. "/src/shared/Logic/Rng.luau", root)).toBe(false)
			expect(StringRequire.allowed(root .. "/src/shared/FoundryAdapter.luau", root)).toBe(false)
			expect(StringRequire.allowed(nil, root)).toBe(false)
		end)

		it("every vendored package loads through the Loader and through a booted client", function()
			local names = {}
			for _, child in folder:GetChildren() do
				if child:FindFirstChild(child.Name) then
					table.insert(names, child.Name)
				end
			end
			table.sort(names)
			local foundry, _, warned = server()
			expect(#warned).toBe(0)
			local h = TestKernel.new({ systems = {} })
			local c = ClientHarness.new(h, h:Join())
			for _, name in names do
				if name ~= "Game" then
					expect(foundry.packages[name] ~= nil).toBe(true)
					expect(c.kernel.Foundry.packages[name] ~= nil).toBe(true)
				end
			end
			expect(#names >= 2).toBe(true) -- Contract and the generated Game at least
		end)

		it("a TestKernel builds kernel.Foundry on the mock clock and every system's ctx carries it", function()
			local h = TestKernel.new({ systems = { "Currency" } })
			local foundry = h.kernel.Foundry
			expect(foundry.packages.Contract ~= nil).toBe(true)
			expect(h.kernel._systems.Currency.ctx.Foundry).toBe(foundry)
			local adapter = foundry.adapter("Currency")
			local t0 = adapter.now()
			h:Advance(90)
			expect(adapter.now() - t0).toBe(90)
			expect(adapter.budget("particles")).toBe(600)
		end)
	end)

	describe("the bus", function()
		it("server: emit publishes (player, payload); on hands over the detail with the player", function()
			local foundry, bus = server()
			local adapter = foundry.adapter("Test")
			local topic = "PlayerReady"
			local seen, raw = {}, {}
			local off = adapter.on(topic, function(payload)
				table.insert(seen, payload)
			end)
			local conn = bus:Subscribe(topic, function(player, detail)
				table.insert(raw, { player = player, detail = detail })
			end)
			local player = { Name = "p1" }
			bus:Publish(topic, player, { firstJoin = true })
			adapter.emit(topic, { player = player, awaySeconds = 3 })
			adapter.emit(topic, { awaySeconds = 4 })
			off()
			bus:Publish(topic, player, { firstJoin = false })
			conn:Disconnect()
			expect(#seen).toBe(3)
			expect(seen[1].player).toBe(player)
			expect(seen[1].firstJoin).toBe(true)
			expect(seen[2].awaySeconds).toBe(3)
			expect(seen[3].player).toBe(nil)
			expect(raw[2].player).toBe(player)
			expect(raw[3].player).toBe(nil)
			expect(raw[1].detail.player).toBe(nil) -- the kernel's own detail is never written to
			expect(#raw).toBe(4)
		end)

		it("client: emit and on carry one payload over ctx.Bus", function()
			local h = TestKernel.new({ systems = {} })
			local c = ClientHarness.new(h, h:Join())
			local adapter = c.kernel.Foundry.adapter("Test")
			local got = {}
			local off = adapter.on("Foundry.Probe", function(p)
				table.insert(got, p)
			end)
			c.kernel.Bus:Publish("Foundry.Probe", "a")
			adapter.emit("Foundry.Probe", "b")
			off()
			adapter.emit("Foundry.Probe", "c")
			expect(got).toEqual({ "a", "b" })
		end)
	end)
end
