--[[
	Logic/Dojo (update 3.11 · Seasons & secrets): the Dojo's rules, pure and Roblox-free.
	Numbers in Config/Techniques; the system is Systems/Dojo, the battle side Logic/BattleSim.

	A monster's techniques: `m.tech = { { id, lv } }` (at most Config.Techniques.MaxSlots).

	Dojo.Slots(hearts) -> number                  1, or 2 from Bond heart Slot2Hearts
	Dojo.Known(m) -> { { id, lv } }               the record's valid techniques (a clean copy)
	Dojo.Level(m, techId) -> number               0 when not learned
	Dojo.Learnable(m) -> { technique }            techniques of the monster's element(s)
	Dojo.Check(m, techId, hearts) -> (lv?, why?)  the level a training would reach, or why not
	Dojo.Cost(lv) -> (stardust, seconds)          learning (lv 1) or levelling up to lv
	Dojo.Apply(tech, techId, lv) -> { { id, lv } } a new list with techId at lv (appended if new)
	Dojo.Forget(tech, techId) -> { { id, lv } }   a new list without techId
	Dojo.Copy(tech) -> { { id, lv } }?            a deep copy (nil when empty); Monsters:Insert
	Dojo.ForBattle(tech) -> { Effect }?           BattleSim's view: { id, kind, power, ... } per slot
	Dojo.Effect(techId, lv) -> Effect?            one technique's numbers at a level
]]

local Config = require(script.Parent.Parent.Config)

local Rules = Config.Techniques
local Species = Config.Species

local Dojo = {}

function Dojo.Slots(hearts: number?): number
	return if (hearts or 0) >= Rules.Slot2Hearts then Rules.MaxSlots else 1
end

function Dojo.Known(m)
	local list = {}
	local tech = m and m.tech
	if type(tech) ~= "table" then
		return list
	end
	for _, entry in tech do
		if #list >= Rules.MaxSlots then
			break
		end
		if type(entry) == "table" and Rules.ById[entry.id] then
			local lv = math.clamp(math.floor(tonumber(entry.lv) or 1), 1, Rules.MaxLevel)
			table.insert(list, { id = entry.id, lv = lv })
		end
	end
	return list
end

function Dojo.Level(m, techId: string): number
	for _, entry in Dojo.Known(m) do
		if entry.id == techId then
			return entry.lv
		end
	end
	return 0
end

function Dojo.Learnable(m)
	local list = {}
	local def = m and Species.ById[m.line]
	if not def then
		return list
	end
	for _, element in def.elements do
		for _, tech in Rules.ByElement[element] or {} do
			table.insert(list, tech)
		end
	end
	return list
end

local function canLearnElement(m, techId: string): boolean
	for _, tech in Dojo.Learnable(m) do
		if tech.id == techId then
			return true
		end
	end
	return false
end

function Dojo.Check(m, techId: string, hearts: number?): (number?, string?)
	local tech = Rules.ById[techId]
	if not tech then
		return nil, "That technique doesn't exist"
	end
	if (m.stage or 1) < Rules.MinStage then
		return nil, "Only Adults can train at the Dojo"
	end
	local lv = Dojo.Level(m, techId)
	if lv >= Rules.MaxLevel then
		return nil, "That technique is already at its top level"
	end
	if lv == 0 then
		if not canLearnElement(m, techId) then
			return nil, "This monster can only learn techniques of its own element"
		end
		local known = #Dojo.Known(m)
		if known >= Rules.MaxSlots then
			return nil, "Both technique slots are full. Forget one first"
		elseif known >= Dojo.Slots(hearts) then
			return nil, string.format("The 2nd technique slot opens at Bond heart %d", Rules.Slot2Hearts)
		end
	end
	return lv + 1, nil
end

function Dojo.Cost(lv: number): (number, number)
	local row = Rules.Train[math.clamp(lv, 1, Rules.MaxLevel)]
	return row.stardust, row.seconds
end

function Dojo.Apply(tech, techId: string, lv: number)
	local list = Dojo.Known({ tech = tech })
	for _, entry in list do
		if entry.id == techId then
			entry.lv = lv
			return list
		end
	end
	table.insert(list, { id = techId, lv = lv })
	return list
end

function Dojo.Forget(tech, techId: string)
	local list = {}
	for _, entry in Dojo.Known({ tech = tech }) do
		if entry.id ~= techId then
			table.insert(list, entry)
		end
	end
	return list
end

function Dojo.Copy(tech)
	if type(tech) ~= "table" then
		return nil
	end
	local list = {}
	for _, entry in tech do
		if type(entry) == "table" then
			table.insert(list, { id = entry.id, lv = entry.lv })
		end
	end
	return if #list > 0 then list else nil
end

function Dojo.Effect(techId: string, lv: number)
	local tech = Rules.ById[techId]
	if not tech then
		return nil
	end
	local fx = tech.levels[math.clamp(lv, 1, Rules.MaxLevel)]
	return {
		id = tech.id,
		kind = tech.kind,
		power = fx.power,
		heal = fx.heal,
		shield = fx.shield,
		lifesteal = fx.lifesteal,
		stunChance = fx.stunChance,
	}
end

function Dojo.ForBattle(tech)
	if type(tech) ~= "table" or #tech == 0 then
		return nil
	end
	local list = {}
	for _, entry in Dojo.Known({ tech = tech }) do
		table.insert(list, Dojo.Effect(entry.id, entry.lv))
	end
	return if #list > 0 then list else nil
end

return Dojo
