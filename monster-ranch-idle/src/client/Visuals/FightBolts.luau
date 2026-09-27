--[[
	FightBolts (R2 titan squads): shared cheer-bolt and floating-damage-number pools for a
	boss/titan fight arena. Lifted out of Controllers/StampedeArena (glow-up U) so
	Controllers/TitanInvasion can throw the same bolts at its own giant. Pure pacing (at most N
	per second) is Logic.newPacer (Logic/StampedeArena), reused as-is; this module only owns the
	pooled Instances and their flight/fade timings.

	FightBolts.new(live: Folder, opts) -> bolts
	    opts = { size, boltSeconds, flashSeconds, numberSeconds, numberPool, poolCap }
	  bolts:Launch(from: Vector3, to: Vector3, color: Color3)
	      pulls a free bolt from the pool (or builds one, up to poolCap) and sends it flying.
	  bolts:Step(dt, onHit: (Vector3) -> ())
	      advances every active bolt/number; onHit(landingPosition) fires once, the frame a bolt
	      lands (the caller does the burst, the flinch check and ShowNumber).
	  bolts:ShowNumber(at: Vector3, text: string, color: Color3)
	  bolts:ActiveBolts() -> number
	  bolts:Clear()
]]

local FightBolts = {}
FightBolts.__index = FightBolts

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

function FightBolts.new(live: Folder, opts, Create, Theme)
	return setmetatable({
		live = live,
		opts = opts,
		Create = Create,
		Theme = Theme,
		bolts = {},
		numbers = {},
	}, FightBolts)
end

function FightBolts:freeBolt()
	for _, bolt in self.bolts do
		if not bolt.active then
			return bolt
		end
	end
	if #self.bolts >= self.opts.poolCap or not self.live then
		return nil
	end
	local p = part({
		Name = "Bolt",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(self.opts.size, self.opts.size, self.opts.size),
		Material = Enum.Material.Neon,
		Transparency = 1,
		Parent = self.live,
	})
	local bolt = { part = p, t = 0, from = Vector3.zero, to = Vector3.zero, active = false, flashing = false }
	table.insert(self.bolts, bolt)
	return bolt
end

function FightBolts:Launch(from: Vector3, to: Vector3, color: Color3)
	local bolt = self:freeBolt()
	if not bolt then
		return
	end
	bolt.from = from
	bolt.to = to
	bolt.t = 0
	bolt.active = true
	bolt.flashing = false
	bolt.part.Color = color
	bolt.part.Size = Vector3.new(self.opts.size, self.opts.size, self.opts.size)
	bolt.part.Transparency = 0
	bolt.part.CFrame = CFrame.new(from)
end

function FightBolts:freeNumber()
	for _, n in self.numbers do
		if not n.active then
			return n
		end
	end
	if #self.numbers >= self.opts.numberPool or not self.live then
		return nil
	end
	local New = self.Create.New
	local Theme = self.Theme
	local anchor = part({ Name = "HitNumber", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, Parent = self.live })
	local gui = New("BillboardGui", {
		Size = UDim2.fromOffset(140, 50),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		Parent = anchor,
	})
	local label = New("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Title,
		TextColor3 = Theme.Colors.White,
		TextStrokeTransparency = 0.2,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Parent = gui,
	})
	local n = { part = anchor, gui = gui, label = label, t = 0, active = false }
	table.insert(self.numbers, n)
	return n
end

function FightBolts:ShowNumber(at: Vector3, text: string, color: Color3)
	local n = self:freeNumber()
	if not n then
		return
	end
	n.active = true
	n.t = 0
	n.part.CFrame = CFrame.new(at + Vector3.new((math.random() - 0.5) * 6, 2, (math.random() - 0.5) * 6))
	n.label.Text = text
	n.label.TextColor3 = color
	n.label.TextTransparency = 0
	n.gui.StudsOffset = Vector3.zero
	n.gui.Enabled = true
end

function FightBolts:Step(dt: number, onHit: (Vector3) -> ())
	local o = self.opts
	for _, bolt in self.bolts do
		if bolt.active then
			bolt.t += dt
			if not bolt.flashing then
				local p = bolt.t / o.boltSeconds
				if p >= 1 then
					bolt.flashing = true
					bolt.part.CFrame = CFrame.new(bolt.to)
					onHit(bolt.to)
				else
					bolt.part.CFrame = CFrame.new(bolt.from:Lerp(bolt.to, p) + Vector3.new(0, math.sin(p * math.pi) * 4, 0))
				end
			else
				local f = (bolt.t - o.boltSeconds) / o.flashSeconds
				if f >= 1 then
					bolt.active = false
					bolt.part.Transparency = 1
				else
					local s = o.size + f * 4
					bolt.part.Size = Vector3.new(s, s, s)
					bolt.part.Transparency = f
				end
			end
		end
	end
	for _, n in self.numbers do
		if n.active then
			n.t += dt
			local f = n.t / o.numberSeconds
			if f >= 1 then
				n.active = false
				n.gui.Enabled = false
			else
				n.gui.StudsOffset = Vector3.new(0, f * 4, 0)
				n.label.TextTransparency = math.max(0, f * 1.4 - 0.4)
			end
		end
	end
end

function FightBolts:ActiveBolts(): number
	local count = 0
	for _, bolt in self.bolts do
		if bolt.active then
			count += 1
		end
	end
	return count
end

function FightBolts:Clear()
	table.clear(self.bolts)
	table.clear(self.numbers)
end

return FightBolts
