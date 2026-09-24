--[[
	T: runtime validators for anything that crosses the client → server boundary.

	Every validator is a function `(value) -> (ok: boolean, err: string?)`.
	Validators are strict: unknown keys in a struct are rejected, strings have a
	maximum length, numbers must be finite, integers must be whole.

		local schema = T.struct({ id = T.id, amount = T.integer(1, 10) })
		local ok, err = schema({ id = "m12", amount = 3 })
]]

local T = {}

export type Validator = (any) -> (boolean, string?)

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

function T.any(_value: any): (boolean, string?)
	return true
end

function T.none(value: any): (boolean, string?)
	if value == nil then
		return true
	end
	if type(value) == "table" and next(value) == nil then
		return true
	end
	return false, "expected no payload"
end

function T.boolean(value: any): (boolean, string?)
	if type(value) == "boolean" then
		return true
	end
	return false, "expected boolean"
end

function T.string(maxLen: number?, minLen: number?): Validator
	local max = maxLen or 64
	local min = minLen or 0
	return function(value)
		if type(value) ~= "string" then
			return false, "expected string"
		end
		if #value > max then
			return false, "string too long"
		end
		if #value < min then
			return false, "string too short"
		end
		return true
	end
end

function T.number(min: number?, max: number?): Validator
	return function(value)
		if type(value) ~= "number" or not isFinite(value) then
			return false, "expected number"
		end
		if min and value < min then
			return false, "number below minimum"
		end
		if max and value > max then
			return false, "number above maximum"
		end
		return true
	end
end

function T.integer(min: number?, max: number?): Validator
	local num = T.number(min, max)
	return function(value)
		local ok, err = num(value)
		if not ok then
			return false, err
		end
		if value % 1 ~= 0 then
			return false, "expected integer"
		end
		return true
	end
end

-- Ids are short alphanumeric strings (monster ids, egg ids, content ids).
function T.id(value: any): (boolean, string?)
	if type(value) ~= "string" or #value == 0 or #value > 40 then
		return false, "expected id"
	end
	if not string.match(value, "^[%w_%-]+$") then
		return false, "malformed id"
	end
	return true
end

function T.userId(value: any): (boolean, string?)
	if type(value) ~= "number" or value % 1 ~= 0 or value < -1e15 or value > 1e15 then
		return false, "expected user id"
	end
	return true
end

function T.enum(values: { string }): Validator
	local set = {}
	for _, v in values do
		set[v] = true
	end
	return function(value)
		if type(value) == "string" and set[value] then
			return true
		end
		return false, "unexpected value"
	end
end

-- Accepts a key that exists in the given config dictionary (e.g. T.key(Config.Eggs.ById)).
function T.key(dict: { [string]: any }): Validator
	return function(value)
		if type(value) == "string" and dict[value] ~= nil then
			return true
		end
		return false, "unknown key"
	end
end

function T.optional(inner: Validator): Validator
	return function(value)
		if value == nil then
			return true
		end
		return inner(value)
	end
end

function T.array(inner: Validator, maxLen: number?, minLen: number?): Validator
	local max = maxLen or 50
	local min = minLen or 0
	return function(value)
		if type(value) ~= "table" then
			return false, "expected array"
		end
		local count = 0
		for k in value do
			if type(k) ~= "number" then
				return false, "expected array"
			end
			count += 1
		end
		if count ~= #value then
			return false, "array has holes"
		end
		if count > max then
			return false, "array too long"
		end
		if count < min then
			return false, "array too short"
		end
		for i, item in ipairs(value) do
			local ok, err = inner(item)
			if not ok then
				return false, string.format("[%d] %s", i, err or "invalid")
			end
		end
		return true
	end
end

function T.struct(shape: { [string]: Validator }): Validator
	return function(value)
		if type(value) ~= "table" then
			return false, "expected table"
		end
		for k in value do
			if type(k) ~= "string" or shape[k] == nil then
				return false, "unexpected field " .. tostring(k)
			end
		end
		for key, check in shape do
			local ok, err = check(value[key])
			if not ok then
				return false, key .. ": " .. (err or "invalid")
			end
		end
		return true
	end
end

return T
