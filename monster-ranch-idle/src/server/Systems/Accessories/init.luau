--[[
	Accessories (update 1.5 · Showtime): cosmetic items monsters wear, one per slot
	(Config/Accessories). Buying, storage and dressing up; MonsterModel draws them.

	Save section (profile.Accessories):
	  owned = { [accessoryId] = n }   -- in storage (equipped ones live on the monster: `acc`)

	Actions:
	  Accessories.Buy { accessory }                 -- price in gems or Contest Ribbons
	  Accessories.Equip { id, accessory }           -- from storage onto a monster; whatever was
	                                                   in that slot goes back to storage
	  Accessories.Unequip { id, slot }              -- back to storage
	Monsters that leave the ranch drop their accessories: Monsters:Remove strips `acc` and puts
	it in the MonsterRemoved detail, and this system returns every piece to storage.

	Public API:
	  Accessories:Add(player, accessoryId, n?)        -- rewards (Rewards kind "accessory")
	  Accessories:Count(player, accessoryId) -> n     -- in storage + equipped
	  Accessories:Collection(player) -> n             -- distinct accessories owned
	Publishes AccessoryGained (player, { id, amount, source }).
]]

local Accessories = {
	Name = "Accessories",
	Dependencies = { "Currency", "Progression", "Monsters" },
}

Accessories.Profile = {
	Version = 1,
	Default = function()
		return { owned = {} }
	end,
}

local ctx
local Config -- Config.Accessories
local Currency, Progression, Monsters

local function mustSection(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

local function store(player, s, id: string, n: number)
	local count = (s.owned[id] or 0) + n
	s.owned[id] = if count > 0 then count else nil
	ctx:Dirty(player, "owned", id)
end

-- Public API ---------------------------------------------------------------------------

function Accessories:Add(player, accessoryId: string, n: number?)
	local s = ctx:Section(player)
	local amount = math.floor(n or 1)
	if not s or not Config.ById[accessoryId] or amount <= 0 then
		return
	end
	store(player, s, accessoryId, amount)
	ctx.Bus:Publish("AccessoryGained", player, { id = accessoryId, amount = amount, source = "reward" })
end

function Accessories:Count(player, accessoryId: string): number
	local s = ctx:Section(player)
	if not s then
		return 0
	end
	local n = s.owned[accessoryId] or 0
	for _, m in Monsters:All(player) do
		if type(m.acc) == "table" then
			for _, worn in m.acc do
				if worn == accessoryId then
					n += 1
				end
			end
		end
	end
	return n
end

function Accessories:Collection(player): number
	local seen = {}
	local s = ctx:Section(player)
	if not s then
		return 0
	end
	for id in s.owned do
		seen[id] = true
	end
	for _, m in Monsters:All(player) do
		for _, worn in (if type(m.acc) == "table" then m.acc else {}) do
			seen[worn] = true
		end
	end
	local n = 0
	for _ in seen do
		n += 1
	end
	return n
end

-- Actions ------------------------------------------------------------------------------

local function wardrobeMonster(player, id: string)
	local m = Monsters:Get(player, id)
	if not m then
		ctx:Fail("That monster doesn't exist")
	end
	if m.busy == "trade" then
		ctx:Fail("That monster is in a trade")
	end
	return m
end

local function buy(player, accessoryId: string)
	local s = mustSection(player)
	Progression:Require(player, Config.Unlock)
	local def = Config.ById[accessoryId]
	if not def.price then
		ctx:Fail(def.name .. " can't be bought. Earn it!")
	end
	Currency:Charge(player, def.price, "accessory")
	store(player, s, def.id, 1)
	ctx.Bus:Publish("AccessoryGained", player, { id = def.id, amount = 1, source = "shop" })
	if def.price.gems then
		ctx:RequestSave(player)
	end
	return { owned = s.owned[def.id] or 0 }
end

local function equip(player, id: string, accessoryId: string)
	local s = mustSection(player)
	Progression:Require(player, Config.Unlock)
	wardrobeMonster(player, id)
	local def = Config.ById[accessoryId]
	if (s.owned[def.id] or 0) < 1 then
		ctx:Fail("You don't have a spare " .. def.name)
	end
	store(player, s, def.id, -1)
	local previous = Monsters:SetAccessory(player, id, def.slot, def.id)
	if previous and Config.ById[previous] then
		store(player, s, previous, 1)
	end
	return { slot = def.slot, previous = previous or false }
end

local function unequip(player, id: string, slot: string)
	local s = mustSection(player)
	local m = wardrobeMonster(player, id)
	local worn = type(m.acc) == "table" and m.acc[slot]
	if not worn then
		ctx:Fail("Nothing to take off there")
	end
	Monsters:SetAccessory(player, id, slot, nil)
	if Config.ById[worn] then
		store(player, s, worn, 1)
	end
	return { accessory = worn }
end

-- Lifecycle ----------------------------------------------------------------------------

function Accessories.Init(context)
	ctx = context
	Config = ctx.Config.Accessories
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Monsters = ctx:GetSystem("Monsters")

	ctx.Net:Handle("Accessories.Buy", function(player, payload)
		return buy(player, payload.accessory)
	end)
	ctx.Net:Handle("Accessories.Equip", function(player, payload)
		return equip(player, payload.id, payload.accessory)
	end)
	ctx.Net:Handle("Accessories.Unequip", function(player, payload)
		return unequip(player, payload.id, payload.slot)
	end)

	ctx.Bus:Subscribe("MonsterRemoved", function(player, detail)
		local s = ctx:Section(player)
		if not s or type(detail.acc) ~= "table" then
			return
		end
		for _, worn in detail.acc do
			if Config.ById[worn] then
				store(player, s, worn, 1)
			end
		end
	end)
end

return Accessories
