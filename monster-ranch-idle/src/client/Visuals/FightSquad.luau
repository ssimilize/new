--[[
	FightSquad (R2 titan squads): shared choreography for a boss/titan fight arena - the joined
	squads standing in rings round the giant and attacking on a staggered rhythm. Lifted out of
	Controllers/StampedeArena (glow-up U) so Controllers/TitanInvasion can draw the same rings
	round its own giant; the pure ring/pick math is unchanged, in Logic/StampedeArena (Rings,
	Pick, AttackOffset, MaxMonsters), reused as-is by both fights.

	FightSquad.new(live: Folder, deps) -> squad
	    deps = { Logic = require(Shared.Logic.StampedeArena), Appearance, MonsterModel,
	             MonsterAnimator, Vfx, Config }   (Config for Species/Elements, LeadColor only)
	  squad:Sync(squadsData, myUserId, centre: Vector3, cfg, qualityLevel, lowQuality, clock) -> changed
	      squadsData = the replicated { { userId, looks = { { line, form, stage, rarity,
	      variant } } } } list; cfg = { perPlayer, cap, ringInner, ringGap, ringSpacing,
	      attackEvery }. No-ops (returns false) if the picked squad's key (quality level +
	      userId:look-count list) is unchanged since the last Sync; returns true when it rebuilt
	      (so the caller knows to re-read LeadColor). Own effects (particles) only on your own
	      monsters, and never at Low quality.
	  squad:Step(clock)          plays "attack" on any monster whose turn has come
	  squad:Clear()              destroys every model
	  squad:Count() -> number
	  squad:LeadColor(squadsData, myUserId, fallback: Color3) -> Color3
	      your lead monster's element colour (for cheer bolts), or `fallback` if you have none.
]]

local FightSquad = {}
FightSquad.__index = FightSquad

function FightSquad.new(live: Folder, deps)
	return setmetatable({
		live = live,
		deps = deps,
		squad = {},
		key = "",
	}, FightSquad)
end

local function destroyModel(entry)
	if entry.anim then
		entry.anim:Destroy()
	end
	if entry.model then
		entry.model:Destroy()
	end
end

function FightSquad:Clear()
	for _, entry in self.squad do
		destroyModel(entry)
	end
	table.clear(self.squad)
	self.key = ""
end

local function keyOf(squadsData, qualityLevel: number): string
	local parts = { tostring(qualityLevel) }
	for _, entry in (if type(squadsData) == "table" then squadsData else {}) do
		if type(entry) == "table" then
			table.insert(parts, tostring(entry.userId) .. ":" .. tostring(type(entry.looks) == "table" and #entry.looks or 0))
		end
	end
	return table.concat(parts, ",")
end

function FightSquad:LeadColor(squadsData, myUserId: number?, fallback: Color3): Color3
	local Config = self.deps.Config
	for _, entry in (if type(squadsData) == "table" then squadsData else {}) do
		if type(entry) == "table" and entry.userId == myUserId and type(entry.looks) == "table" and entry.looks[1] then
			local def = Config.Species.ById[entry.looks[1].line]
			local element = def and def.elements and Config.Elements.ById[def.elements[1]]
			if element then
				return Color3.fromHex(element.color)
			end
		end
	end
	return fallback
end

local function build(deps, live: Folder, appearance, effects: boolean): Model?
	local ok, model = pcall(deps.MonsterModel.Build, appearance, { anchored = true, vfx = effects })
	if not ok or not model then
		return nil
	end
	model.Parent = live
	deps.Vfx.SetOwned(model, false)
	return model
end

-- cfg: { perPlayer, cap, ringInner, ringGap, ringSpacing, attackEvery }
function FightSquad:Sync(squadsData, myUserId: number?, centre: Vector3, cfg, qualityLevel: number, lowQuality: boolean, clock: number)
	-- The ring size is part of the key: the titan's squads re-form once the giant (and its real
	-- footprint) is drawn.
	local key = keyOf(squadsData, qualityLevel) .. "|" .. tostring(cfg.ringInner)
	if key == self.key then
		return false
	end
	self:Clear()
	self.key = key
	local Logic = self.deps.Logic
	local picked = Logic.Pick(squadsData, myUserId, cfg.perPlayer, cfg.cap)
	local rings = Logic.Rings(#picked, cfg.ringInner, cfg.ringGap, cfg.ringSpacing)
	for i, pick in picked do
		local look = pick.look
		local ok, ap = pcall(self.deps.Appearance.Preview, look.line, look.stage, look.form, look.rarity, look.variant)
		local model = if ok and ap then build(self.deps, self.live, ap, pick.mine and not lowQuality) else nil
		if model then
			local anim = self.deps.MonsterAnimator.new(model)
			anim:SetOwn(pick.mine)
			local at = centre + Vector3.new(rings[i].x, 0, rings[i].z)
			anim:SetBase(CFrame.lookAt(at, Vector3.new(centre.X, at.Y, centre.Z)))
			table.insert(self.squad, { model = model, anim = anim, nextAttack = clock + Logic.AttackOffset(i, #picked, cfg.attackEvery) })
		end
	end
	return true
end

function FightSquad:Step(clock: number, attackEvery: number)
	for _, entry in self.squad do
		if clock >= entry.nextAttack then
			entry.nextAttack += attackEvery
			if entry.nextAttack < clock then
				entry.nextAttack = clock + attackEvery
			end
			entry.anim:Play("attack")
		end
	end
end

function FightSquad:Count(): number
	return #self.squad
end

-- Plays one animation on every drawn monster at once (the giant's fall or the end-of-fight cheer).
function FightSquad:PlayAll(animName: string)
	for _, entry in self.squad do
		entry.anim:Play(animName)
	end
end

return FightSquad
