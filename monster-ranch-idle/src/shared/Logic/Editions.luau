--[[
	Editions (glow-up W): pure rules for numbered limited editions (Config.Editions).

	  Editions.For(record, source) -> edition?      the edition a just-created record joins (nil:
	                                                not a limited line, not a minting source, or it
	                                                already carries edition fields)
	  Editions.Claim(current, size) -> (count?, n?) the store transform: the next number while the
	                                                edition has room (count = new counter to write);
	                                                nil, nil once it is full (write nothing)
	  Editions.Pending(m) -> boolean                joined an edition, still waiting for its number
	  Editions.Label(m) -> string?                  "#37/500" (numbered), nil otherwise
	  Editions.Of(m) -> (n?, size?)                 the number and edition size
]]

local Config = require(script.Parent.Parent.Config)

local Editions = {}

function Editions.For(record, source: string?)
	if type(record) ~= "table" or record.ltd ~= nil or record.ltdNo ~= nil then
		return nil
	end
	if not (source and Config.Editions.Sources[source]) then
		return nil
	end
	return Config.Editions.ByLine[record.line]
end

function Editions.Claim(current: any, size: number): (number?, number?)
	local count = math.max(0, math.floor(tonumber(current) or 0))
	if count >= size then
		return nil, nil
	end
	return count + 1, count + 1
end

function Editions.Pending(m): boolean
	return type(m) == "table" and type(m.ltd) == "string" and m.ltdNo == nil
end

function Editions.Of(m): (number?, number?)
	if type(m) ~= "table" or type(m.ltdNo) ~= "number" then
		return nil, nil
	end
	return m.ltdNo, tonumber(m.ltdOf)
end

function Editions.Label(m): string?
	local n, size = Editions.Of(m)
	if not n then
		return nil
	end
	return if size then string.format("#%d/%d", n, size) else string.format("#%d", n)
end

return Editions
