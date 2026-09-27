--[[
	ScreenDimClient: clicks on an open screen's panel never close it; clicks on the dimmed
	world around it do. The Router puts a full-screen Dim button behind every modal screen, and
	Frames let a click fall through to it, so each Panel keeps a do-nothing ClickSink button
	behind its card. Clicks are routed with ClientHarness:ClickAt, which hands a press at a
	screen point to the topmost button there, as the engine does.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Vector2 = t.Roblox.Vector2
	local Config = t.Shared("Config")

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
		-- Level 16 unlocks both screens, so their content (not a Lock cover) fills the body.
		local P = h:System("Progression")
		while P:GetLevel(p) < 16 do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
		local c = ClientHarness.new(h, p)
		c:Advance(1)
		-- Tap away the queued level-up banners, which sit over everything in the Top layer.
		for _ = 1, 30 do
			local banner = c.kernel.UI.Top:FindFirstChild("LevelUp")
			if not banner then
				break
			end
			c:Click(banner)
			c:Advance(0.5)
		end
		expect(c.kernel.UI.Top:FindFirstChild("LevelUp")).toBe(nil)
		return c
	end

	local function describeHit(gui): string
		return if gui then gui:GetFullName() else "nothing"
	end

	-- Clicks `point` and checks the press landed on `name`'s ClickSink and the screen stayed open.
	local function clickKeepsOpen(c, name: string, root, point, label: string)
		local sink = root:FindFirstChild("ClickSink")
		local hit = c:HitAt(point)
		if hit ~= sink then
			error(string.format("%s %s: the press lands on %s", name, label, describeHit(hit)), 2)
		end
		c:ClickAt(point)
		c:Advance(0.5)
		if c.kernel.Router:Current() ~= name or not c:IsShown(root) then
			error(string.format("%s %s: a click on the panel closed it", name, label), 2)
		end
	end

	describe("Screen dim", function()
		for _, name in { "Kitchen", "DigSite" } do
			it(name .. " stays open on clicks inside its panel and closes on the dim outside", function()
				local c = boot()
				local root = c:Open(name)
				c:Advance(0.5)
				expect(c.kernel.Router:Current()).toBe(name)

				local pos, size = root.AbsolutePosition, root.AbsoluteSize
				-- The header ribbon beside the title.
				clickKeepsOpen(c, name, root, pos + Vector2.new(size.X * 0.3, 20), "header")
				-- The card's padding at the bottom-left corner and along the right edge.
				clickKeepsOpen(c, name, root, pos + Vector2.new(8, size.Y - 8), "bottom-left padding")
				clickKeepsOpen(c, name, root, pos + Vector2.new(size.X - 6, size.Y * 0.6), "right padding")

				-- A gamepad cursor must never land on the sink.
				expect(root.ClickSink.Selectable).toBe(false)

				-- Just outside the panel is the dim, and a click there closes the screen.
				local outside = pos + Vector2.new(-20, size.Y / 2)
				expect(c:HitAt(outside)).toBe(c.kernel.Router._dim)
				c:ClickAt(outside)
				c:Advance(0.5)
				expect(c.kernel.Router:Current()).toBe(nil)
				expect(c:IsShown(root)).toBe(false)
				expectClean(c)
			end)
		end
	end)
end
