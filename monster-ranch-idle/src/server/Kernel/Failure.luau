--[[
	Failure: a user-facing error. Handlers call `ctx:Fail("Not enough coins")`; the kernel
	turns it into { ok = false, err = "Not enough coins" } for the client. Any other error
	is treated as a bug: logged with a traceback and reported to the client generically.
]]

local Failure = {}
Failure.__index = Failure
Failure.__tostring = function(self)
	return "Failure: " .. self.message
end

function Failure.new(message: string)
	return setmetatable({ message = message }, Failure)
end

function Failure.is(value: any): boolean
	return type(value) == "table" and getmetatable(value) == Failure
end

return Failure
