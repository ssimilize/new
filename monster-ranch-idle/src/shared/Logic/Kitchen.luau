--[[
	Kitchen & Pantry (update 3.10): the cooking rules. Pure: the server cooks and serves with
	them, and the client shows costs, timers and which monsters can eat a dish with the same
	functions. Numbers and recipes live in Config.Kitchen.

	Slot (profile.Kitchen.slots[i]): { recipe = recipeId | false, startedAt, readyAt }
	Boost (profile.Kitchen.boosts[monsterId]): { job = { { from, to } }, loot = boolean }

	  Kitchen.EmptySlot() -> Slot
	  Kitchen.SlotCount(isUnlocked: (key) -> boolean) -> number
	  Kitchen.Split(recipe) -> (food: { [flavor]: n }, fish: number, golden: number)
	  Kitchen.Honey(recipe) -> { [kind]: n }   3.12: the recipe's honey cost (empty when none)
	  Kitchen.Missing(recipe, have: { food = { [flavor]: n }, fish, golden, kinds?, honey? }) -> key?
	                                        "fish", "golden" or a flavour id the player is short of;
	                                        3.12: "honey" when have.honey = { [kind]: n } is short;
	                                        3.11: "seasonFish" when kinds = { [fishId]: n } lacks the
	                                        recipe's seasonFish
	  Kitchen.SeasonNote(recipe, seasonId) -> (text?, inSeason)
	                                        3.11: "In season: Winter" / "Back in Spring" (nil text = all year)
	  Kitchen.IsReady(slot, now) -> boolean
	  Kitchen.AddWindow(windows, now, seconds) -> windows
	                                        a new job boost window, merged with one still running;
	                                        keeps the newest MaxWindows
	  Kitchen.JobBoosts(entry) -> { { from, to, pct } }   what Jobs:RegisterOutputBoost returns
	  Kitchen.GoldenSeed(userId, n) -> boolean    the n-th garden harvest drops a Golden seed
	  Kitchen.ServeProblem(recipe, m, info) -> string?
	                                        why `m` can't eat the dish now (nil = it can);
	                                        info = { hearts?, now, boost? }
]]

local Config = require(script.Parent.Parent.Config)
local Formulas = require(script.Parent.Formulas)
local Rng = require(script.Parent.Rng)

local Rules = Config.Kitchen

local Kitchen = {}

Kitchen.MaxWindows = 4

-- 3.11: one literal per season (translated whole).
local IN_SEASON = {
	spring = "In season: Spring",
	summer = "In season: Summer",
	autumn = "In season: Autumn",
	winter = "In season: Winter",
}
local BACK_IN = {
	spring = "Back in Spring",
	summer = "Back in Summer",
	autumn = "Back in Autumn",
	winter = "Back in Winter",
}

function Kitchen.EmptySlot()
	return { recipe = false, startedAt = 0, readyAt = 0 }
end

function Kitchen.SlotCount(isUnlocked: (string) -> boolean): number
	if not isUnlocked(Rules.Unlock) then
		return 0
	end
	return if isUnlocked(Rules.SlotUnlock) then Rules.MaxSlots else Rules.BaseSlots
end

function Kitchen.Split(recipe)
	local food, fish, golden = {}, 0, 0
	for key, n in recipe.cost do
		if key == "honey" then
			continue -- 3.12: Kitchen.Honey
		elseif key == "fish" then
			fish = n
		elseif key == Rules.Golden.id then
			golden = n
		else
			food[key] = n
		end
	end
	return food, fish, golden
end

function Kitchen.Honey(recipe): { [string]: number }
	local honey = type(recipe) == "table" and type(recipe.cost) == "table" and recipe.cost.honey
	return if type(honey) == "table" then table.clone(honey) else {}
end

function Kitchen.Missing(recipe, have): string?
	local food, fish, golden = Kitchen.Split(recipe)
	local store = if type(have.honey) == "table" then have.honey else {}
	for kind, n in Kitchen.Honey(recipe) do
		if n > (tonumber(store[kind]) or 0) then
			return "honey"
		end
	end
	if fish > (have.fish or 0) then
		return "fish"
	end
	if recipe.seasonFish and type(have.kinds) == "table" and (tonumber(have.kinds[recipe.seasonFish]) or 0) < 1 then
		return "seasonFish"
	end
	if golden > (have.golden or 0) then
		return "golden"
	end
	for _, flavor in Config.Food.Ids do
		local n = food[flavor]
		if n and n > ((have.food or {})[flavor] or 0) then
			return flavor
		end
	end
	return nil
end

function Kitchen.SeasonNote(recipe, seasonId: string?): (string?, boolean)
	if type(recipe) ~= "table" or recipe.season == nil then
		return nil, true
	end
	if recipe.season == seasonId then
		return IN_SEASON[recipe.season], true
	end
	return BACK_IN[recipe.season], false
end

function Kitchen.IsReady(slot, now: number): boolean
	return type(slot) == "table" and slot.recipe ~= false and slot.recipe ~= nil and now >= (slot.readyAt or 0)
end

function Kitchen.AddWindow(windows, now: number, seconds: number)
	local list = {}
	for _, w in windows or {} do
		if type(w) == "table" and type(w.from) == "number" and type(w.to) == "number" then
			table.insert(list, { from = w.from, to = w.to })
		end
	end
	local last = list[#list]
	if last and last.to >= now then
		-- Still running: the boost now lasts `seconds` from this serving.
		last.to = now + seconds
	else
		table.insert(list, { from = now, to = now + seconds })
	end
	while #list > Kitchen.MaxWindows do
		table.remove(list, 1)
	end
	return list
end

function Kitchen.JobBoosts(entry)
	local list = {}
	if type(entry) == "table" and type(entry.job) == "table" then
		for _, w in entry.job do
			table.insert(list, { from = w.from, to = w.to, pct = Rules.JobBoost.pct })
		end
	end
	return list
end

function Kitchen.JobBoostUntil(entry): number
	local until_ = 0
	for _, w in Kitchen.JobBoosts(entry) do
		until_ = math.max(until_, w.to or 0)
	end
	return until_
end

function Kitchen.GoldenSeed(userId: number, n: number): boolean
	return Rng.new(Rng.seed("golden_seed", userId, n)):Chance(Rules.GoldenSeedChance)
end

function Kitchen.ServeProblem(recipe, m, info): string?
	if type(m) ~= "table" then
		return "That monster doesn't exist"
	end
	local name = Formulas.DisplayName(m)
	local effect = recipe.effect
	if effect == "meals" then
		local needed = Formulas.MealsNeeded(m.stage or 1)
		if not needed then
			return "Only Babies and Teens eat growth meals"
		end
		if Formulas.MealsEaten(m) >= needed then
			return string.format("%s has eaten enough to grow", name)
		end
	elseif effect == "mood" then
		if (m.mood or Config.Economy.Mood.start) >= Config.Economy.Mood.max then
			return string.format("%s is already as happy as can be", name)
		end
	elseif effect == "bond" then
		if (info and info.hearts or 0) >= Config.Bond.MaxHearts then
			return string.format("%s already has every Bond heart", name)
		end
	elseif effect == "royal" then
		-- 3.12: a heart and full Mood; refused only when it would do neither.
		local fullMood = (m.mood or Config.Economy.Mood.start) >= Config.Economy.Mood.max
		if fullMood and (info and info.hearts or 0) >= Config.Bond.MaxHearts then
			return string.format("%s already has every Bond heart and full Mood", name)
		end
	elseif effect == "job" then
		if (m.stage or 1) < Config.Jobs.MinStage then
			return "Only Teens and Adults can work"
		end
	elseif effect == "loot" then
		if info and type(info.boost) == "table" and info.boost.loot then
			return string.format("%s already has a snack for its next expedition", name)
		end
	end
	return nil
end

return Kitchen
