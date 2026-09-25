--[[
	Currency (S1): every countable resource the player owns.

	Keys: "coins", "gems", "stardust", "friendship", "treats", "ribbons" (Contest Ribbons, 1.5),
	      "food.<flavor>" (sweet/spicy/savory/sour), "token.<eventId>".
	Config prices use { coins = n } / { gems = n } / { friendship = n } / { token = n } —
	`token` means the running event's token (Config.Events).

	Public API (other systems):
	  Currency:Balance(player, key) -> number
	  Currency:Add(player, key, amount, reason)
	  Currency:CanAfford(player, cost) -> boolean, missingKey?
	  Currency:Spend(player, cost, reason) -> boolean      -- all-or-nothing
	  Currency:Charge(player, cost, reason)                -- Spend or ctx:Fail("Not enough …")
	  Currency:NormalizeCost(price, eventId?) -> { [key]: n }
]]

local Currency = {
	Name = "Currency",
	Dependencies = {},
}

local SIMPLE = { coins = true, gems = true, stardust = true, friendship = true, treats = true, ribbons = true }
local DISPLAY =
	{ coins = "coins", gems = "gems", stardust = "Stardust", friendship = "Friendship Points", treats = "Treats", ribbons = "Ribbons" }

Currency.Profile = {
	Version = 1,
	Default = function()
		return {
			coins = 0,
			gems = 0,
			stardust = 0,
			friendship = 0,
			treats = 0,
			ribbons = 0,
			tokens = {},
			food = { sweet = 0, spicy = 0, savory = 0, sour = 0 },
		}
	end,
}

local ctx

function Currency.Init(context)
	ctx = context
end

local function split(key: string): (string, string?)
	local head, tail = string.match(key, "^(%a+)%.(.+)$")
	if head then
		return head, tail
	end
	return key, nil
end

local function valid(amount: number): boolean
	return type(amount) == "number" and amount == amount and amount ~= math.huge and amount ~= -math.huge
end

function Currency:Balance(player, key: string): number
	local section = ctx:Section(player)
	if not section then
		return 0
	end
	local head, tail = split(key)
	if SIMPLE[head] then
		return section[head] or 0
	elseif head == "food" then
		return section.food[tail] or 0
	elseif head == "token" then
		return section.tokens[tail] or 0
	end
	error("[Currency] unknown key " .. key)
end

local function write(player, section, key: string, value: number)
	local head, tail = split(key)
	if SIMPLE[head] then
		section[head] = value
		ctx:Dirty(player, head)
	elseif head == "food" then
		assert(ctx.Config.Food.ById[tail], "unknown food " .. tostring(tail))
		section.food[tail] = value
		ctx:Dirty(player, "food", tail)
	elseif head == "token" then
		section.tokens[tail] = value
		ctx:Dirty(player, "tokens", tail)
	else
		error("[Currency] unknown key " .. key)
	end
end

local function logEconomy(player, key: string, delta: number, balance: number, reason: string)
	if key == "coins" or key == "gems" then
		ctx.Analytics.Economy(player, delta > 0, key, math.abs(delta), balance, reason, nil)
	end
end

function Currency:Add(player, key: string, amount: number, reason: string?)
	assert(valid(amount) and amount >= 0, "[Currency] Add expects a non-negative amount")
	local section = ctx:Section(player)
	if not section or amount == 0 then
		return
	end
	amount = math.floor(amount)
	if amount == 0 then
		return
	end
	local balance = Currency:Balance(player, key) + amount
	write(player, section, key, balance)
	logEconomy(player, key, amount, balance, reason or "unknown")
	ctx.Bus:Publish("CurrencyChanged", player, { currency = key, delta = amount, reason = reason or "unknown", balance = balance })
end

-- Converts a Config price table into currency keys.
function Currency:NormalizeCost(price, eventId: string?): { [string]: number }
	local cost = {}
	for k, v in price or {} do
		if k == "token" then
			local ev = eventId or ctx.Config.Events.ActiveId(ctx:Now())
			assert(ev, "[Currency] token price used with no active event")
			cost["token." .. ev] = v
		else
			cost[k] = v
		end
	end
	return cost
end

function Currency:CanAfford(player, cost: { [string]: number }): (boolean, string?)
	for key, amount in cost do
		if Currency:Balance(player, key) < amount then
			return false, key
		end
	end
	return true, nil
end

function Currency:Spend(player, cost: { [string]: number }, reason: string?): boolean
	local section = ctx:Section(player)
	if not section then
		return false
	end
	for _, amount in cost do
		assert(valid(amount) and amount >= 0, "[Currency] Spend expects non-negative amounts")
	end
	if not Currency:CanAfford(player, cost) then
		return false
	end
	for key, amount in cost do
		if amount > 0 then
			local balance = Currency:Balance(player, key) - amount
			write(player, section, key, balance)
			logEconomy(player, key, -amount, balance, reason or "unknown")
			ctx.Bus:Publish("CurrencyChanged", player, { currency = key, delta = -amount, reason = reason or "unknown", balance = balance })
		end
	end
	return true
end

function Currency:MissingText(key: string): string
	local head, tail = split(key)
	if head == "food" then
		local food = ctx.Config.Food.ById[tail]
		return "Not enough " .. (if food then food.name else "food")
	elseif head == "token" then
		return "Not enough event tokens"
	end
	return "Not enough " .. (DISPLAY[head] or head)
end

-- Spends or fails the current request with a player-facing message.
function Currency:Charge(player, cost: { [string]: number }, reason: string?)
	local ok, missing = Currency:CanAfford(player, cost)
	if not ok then
		ctx:Fail(Currency:MissingText(missing :: string))
	end
	Currency:Spend(player, cost, reason)
end

return Currency
