-- Expect: minimal assertion library for specs.
local function show(v): string
	if type(v) == "table" then
		local parts = {}
		for k, x in v do
			table.insert(parts, tostring(k) .. "=" .. show(x))
			if #parts > 12 then
				table.insert(parts, "…")
				break
			end
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	elseif type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local function deepEqual(a, b): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function expect(actual)
	local e = {}
	function e.toBe(expected)
		if actual ~= expected then
			error(string.format("expected %s to be %s", show(actual), show(expected)), 2)
		end
	end
	function e.toEqual(expected)
		if not deepEqual(actual, expected) then
			error(string.format("expected %s to equal %s", show(actual), show(expected)), 2)
		end
	end
	function e.toBeNear(expected, tolerance)
		local tol = tolerance or 1e-6
		if type(actual) ~= "number" or math.abs(actual - expected) > tol then
			error(string.format("expected %s to be within %s of %s", show(actual), tostring(tol), show(expected)), 2)
		end
	end
	function e.toBeTruthy()
		if not actual then
			error(string.format("expected %s to be truthy", show(actual)), 2)
		end
	end
	function e.toBeFalsy()
		if actual then
			error(string.format("expected %s to be falsy", show(actual)), 2)
		end
	end
	function e.toBeNil()
		if actual ~= nil then
			error(string.format("expected nil, got %s", show(actual)), 2)
		end
	end
	function e.toBeGreaterThan(n)
		if not (actual > n) then
			error(string.format("expected %s > %s", show(actual), show(n)), 2)
		end
	end
	function e.toBeAtLeast(n)
		if not (actual >= n) then
			error(string.format("expected %s >= %s", show(actual), show(n)), 2)
		end
	end
	function e.toBeLessThan(n)
		if not (actual < n) then
			error(string.format("expected %s < %s", show(actual), show(n)), 2)
		end
	end
	function e.toBeAtMost(n)
		if not (actual <= n) then
			error(string.format("expected %s <= %s", show(actual), show(n)), 2)
		end
	end
	function e.toContain(item)
		if type(actual) == "string" then
			if not string.find(actual, item, 1, true) then
				error(string.format("expected %s to contain %s", show(actual), show(item)), 2)
			end
			return
		end
		for _, v in actual do
			if deepEqual(v, item) then
				return
			end
		end
		error(string.format("expected %s to contain %s", show(actual), show(item)), 2)
	end
	function e.toThrow(fragment: string?)
		local ok, err = pcall(actual)
		if ok then
			error("expected function to throw", 2)
		end
		if fragment and not string.find(tostring(err), fragment, 1, true) then
			error(string.format("expected error containing %q, got %s", fragment, tostring(err)), 2)
		end
	end
	return e
end

return expect
