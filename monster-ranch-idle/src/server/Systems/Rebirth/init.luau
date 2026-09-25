--[[
	Rebirth (update 1.4): Ranch Rebirth (prestige layer 2) and the Stardust skill tree.
	Rules and numbers live in Config/Rebirth.

	Save section (profile.Rebirth):
	  stars  = number                 -- Rebirth Stars earned (= rebirths done)
	  skills = { [skillId] = level }  -- Stardust skill tree
	  lastAt = number                 -- unix time of the last rebirth (0 = never)
	  dust   = number                 -- Stardust earned from rebirths, all time

	Rebirth.Rebirth { keep = { id } } runs in one step with no yields, so either all of it
	happens or none of it does (every section it touches lives in the same profile):
	  1. checks: Ranch Level, coins in hand, 1..Heirlooms keepers, nothing busy
	  2. unkept monsters → Stardust (Config.DustFor × (1 + Star Sifter)), then removed
	  3. coins → Head Start amount; Ranch:ResetForRebirth (new star's biome theme);
	     Expeditions:ResetForRebirth; Shop:GrantTheme
	  4. stars + 1, providers refresh (RateModifiersChanged), save requested

	Providers registered in Start (systems that are plugged in only):
	  Ranch:RegisterRateMultiplier("rebirth_stars")   Config.CoinMult(stars)
	  Ranch:RegisterRateModifier("rebirth_skill")     Golden Touch coinPct
	  Ranch:RegisterJarBonus("rebirth_skill")         Deep Pockets seconds
	  Eggs:RegisterSpeedProvider("rebirth_skill")     Warm Hands
	  Breeding:RegisterBreedsPerDayBonus("rebirth_skill")  Twin Nests
	  Expeditions:RegisterLootModifier("rebirth_skill")    Trailblazer
	  Boss:RegisterDamageModifier("rebirth_skill")         War Paint

	Third trait: from Config.ThirdTraitStars stars, every monster the player owns (and every
	monster that arrives later) gets a 3rd visible trait (Monsters:AddVisibleTrait).

	Public API:
	  Rebirth:Stars(player) -> number
	  Rebirth:SkillLevel(player, skillId) -> number
	  Rebirth:SkillEffect(player, skillId, key) -> number   -- level × per-level effect
	  Rebirth:Heirlooms(player) -> number                    -- monsters a rebirth may keep
	Publishes Rebirthed (player, { stars, dust, kept }) and RateModifiersChanged.
]]

local Rebirth = {
	Name = "Rebirth",
	Dependencies = { "Currency", "Progression", "Monsters" },
	OptionalDependencies = { "Ranch", "Expeditions", "Shop", "Eggs", "Breeding", "Boss" },
}

Rebirth.Profile = {
	Version = 1,
	Default = function()
		return { stars = 0, skills = {}, lastAt = 0, dust = 0 }
	end,
}

local ctx
local Config -- Config.Rebirth
local Currency, Progression, Monsters

local function mustSection(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

-- Public API ---------------------------------------------------------------------------

function Rebirth:Stars(player): number
	local s = ctx:Section(player)
	return s and s.stars or 0
end

function Rebirth:SkillLevel(player, skillId: string): number
	local s = ctx:Section(player)
	return s and s.skills[skillId] or 0
end

function Rebirth:SkillEffect(player, skillId: string, key: string): number
	local def = Config.SkillById[skillId]
	local per = def and def.effect[key]
	if type(per) ~= "number" then
		return 0
	end
	return Rebirth:SkillLevel(player, skillId) * per
end

function Rebirth:Heirlooms(player): number
	return Config.Heirlooms(Rebirth:Stars(player), Rebirth:SkillEffect(player, "family_vault", "heirlooms"))
end

-- Third trait --------------------------------------------------------------------------

local function grantThirdTrait(player, id: string)
	if Rebirth:Stars(player) < Config.ThirdTraitStars then
		return
	end
	local m = Monsters:Get(player, id)
	if m and #(m.traits or {}) < 3 then
		Monsters:AddVisibleTrait(player, id)
	end
end

local function grantThirdTraitAll(player)
	if Rebirth:Stars(player) < Config.ThirdTraitStars then
		return
	end
	local ids = {}
	for id in Monsters:All(player) do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		grantThirdTrait(player, id)
	end
end

-- Rebirth ------------------------------------------------------------------------------

local function checkKeep(player, keep: { string }): { [string]: boolean }
	local set, n = {}, 0
	for _, id in keep do
		if not set[id] then
			if not Monsters:Get(player, id) then
				ctx:Fail("That monster doesn't exist")
			end
			set[id] = true
			n += 1
		end
	end
	if n < 1 then
		ctx:Fail("Choose at least one Heirloom monster to keep")
	end
	local max = Rebirth:Heirlooms(player)
	if n > max then
		ctx:Fail(string.format("You can keep up to %d Heirloom monsters", max))
	end
	return set
end

local function rebirth(player, keep: { string })
	local s = mustSection(player)
	Progression:Require(player, Config.Unlock)
	if s.stars >= Config.MaxStars then
		ctx:Fail("Your ranch already has every Rebirth Star")
	end
	local need = Config.CoinsNeeded(s.stars)
	if Currency:Balance(player, "coins") < need then
		ctx:Fail(string.format("Save up %d coins to rebirth", need))
	end
	local set = checkKeep(player, keep)
	for _, m in Monsters:All(player) do
		if m.busy then
			ctx:Fail("Bring every monster home first (expeditions, breeding and trades)")
		end
	end

	-- Everything below is committed together: nothing in it can fail or yield.
	local sifter = Rebirth:SkillEffect(player, "star_sifter", "dustPct")
	local ids = {}
	local base = 0
	for id, m in Monsters:All(player) do
		if not set[id] then
			table.insert(ids, id)
			base += Config.DustFor(m)
		end
	end
	table.sort(ids)
	for _, id in ids do
		Monsters:Remove(player, id, "rebirth")
	end
	local dust = math.floor(base * (1 + sifter))

	local star = s.stars + 1
	local theme = Config.BiomeFor(star)
	local coins = Currency:Balance(player, "coins")
	if coins > 0 then
		Currency:Charge(player, { coins = coins }, "rebirth")
	end
	local start = Rebirth:SkillEffect(player, "head_start", "startCoins")
	if start > 0 then
		Currency:Add(player, "coins", start, "rebirth_head_start")
	end
	if dust > 0 then
		Currency:Add(player, "stardust", dust, "rebirth")
	end
	local Shop = ctx:GetSystem("Shop")
	if Shop then
		Shop:GrantTheme(player, theme)
	end
	local Ranch = ctx:GetSystem("Ranch")
	if Ranch then
		Ranch:ResetForRebirth(player, if Shop then theme else nil)
	end
	local Expeditions = ctx:GetSystem("Expeditions")
	if Expeditions then
		Expeditions:ResetForRebirth(player)
	end

	s.stars = star
	s.lastAt = ctx:Now()
	s.dust += dust
	ctx:Dirty(player)
	grantThirdTraitAll(player)

	local kept = 0
	for _ in set do
		kept += 1
	end
	ctx.Bus:Publish("Rebirthed", player, { stars = star, dust = dust, kept = kept })
	ctx.Bus:Publish("RateModifiersChanged", player, {})
	ctx.Analytics.Custom(player, "Rebirth", star, { dust = dust, kept = kept })
	ctx:RequestSave(player)
	return { stars = star, stardust = dust, kept = kept, theme = theme }
end

-- Skill tree ---------------------------------------------------------------------------

local function buySkill(player, skillId: string)
	local s = mustSection(player)
	Progression:Require(player, Config.Unlock)
	local def = Config.SkillById[skillId]
	local level = s.skills[def.id] or 0
	if level >= def.maxLevel then
		ctx:Fail(def.name .. " is already maxed")
	end
	if def.requires and (s.skills[def.requires] or 0) < 1 then
		ctx:Fail(string.format("Learn %s first", Config.SkillById[def.requires].name))
	end
	if def.stars and s.stars < def.stars then
		ctx:Fail(string.format("Needs %d Rebirth Star%s", def.stars, if def.stars == 1 then "" else "s"))
	end
	Currency:Charge(player, { stardust = def.cost[level + 1] }, "rebirth_skill")
	s.skills[def.id] = level + 1
	ctx:Dirty(player, "skills", def.id)
	ctx.Bus:Publish("RateModifiersChanged", player, {})
	ctx.Analytics.Custom(player, "RebirthSkill", level + 1, { skill = def.id })
	return { level = level + 1 }
end

-- Providers ----------------------------------------------------------------------------

local function registerProviders()
	local function effect(skillId: string, key: string)
		return function(player)
			return Rebirth:SkillEffect(player, skillId, key)
		end
	end

	local Ranch = ctx:GetSystem("Ranch")
	if Ranch then
		Ranch:RegisterRateMultiplier("rebirth_stars", function(player)
			return Config.CoinMult(Rebirth:Stars(player))
		end)
		Ranch:RegisterRateModifier("rebirth_skill", effect("golden_touch", "coinPct"))
		Ranch:RegisterJarBonus("rebirth_skill", effect("deep_pockets", "jarCapSeconds"))
	end
	local Eggs = ctx:GetSystem("Eggs")
	if Eggs then
		Eggs:RegisterSpeedProvider("rebirth_skill", effect("warm_hands", "hatchSpeed"))
	end
	local Breeding = ctx:GetSystem("Breeding")
	if Breeding then
		Breeding:RegisterBreedsPerDayBonus("rebirth_skill", effect("twin_nests", "breedsPerDay"))
	end
	local Expeditions = ctx:GetSystem("Expeditions")
	if Expeditions then
		Expeditions:RegisterLootModifier("rebirth_skill", effect("trailblazer", "lootPct"))
	end
	local Boss = ctx:GetSystem("Boss")
	if Boss then
		Boss:RegisterDamageModifier("rebirth_skill", effect("war_paint", "bossDmgPct"))
	end
end

-- Lifecycle ----------------------------------------------------------------------------

function Rebirth.Init(context)
	ctx = context
	Config = ctx.Config.Rebirth
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")

	ctx.Net:Handle("Rebirth.Rebirth", function(player, payload)
		return rebirth(player, payload.keep)
	end)
	ctx.Net:Handle("Rebirth.BuySkill", function(player, payload)
		return buySkill(player, payload.skill)
	end)

	ctx.Bus:Subscribe("MonsterCreated", function(player, detail)
		if ctx:IsReady(player) then
			grantThirdTrait(player, detail.id)
		end
	end)
	ctx.Bus:Subscribe("PlayerReady", function(player)
		grantThirdTraitAll(player)
	end)
end

function Rebirth.Start()
	registerProviders()
end

return Rebirth
