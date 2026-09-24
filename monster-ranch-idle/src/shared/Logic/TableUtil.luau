-- Small table helpers shared by server, client and tests.
local TableUtil = {}

function TableUtil.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[TableUtil.deepCopy(k)] = TableUtil.deepCopy(v)
	end
	return copy :: any
end

function TableUtil.count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function TableUtil.keys<K>(t: { [K]: any }): { K }
	local list = {}
	for k in t do
		table.insert(list, k)
	end
	return list
end

-- Fills missing keys of `target` from `template` (recursively for nested records).
-- Values already present in `target` are never overwritten.
function TableUtil.reconcile(target: { [any]: any }, template: { [any]: any })
	for k, v in template do
		if target[k] == nil then
			target[k] = TableUtil.deepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" and next(v) ~= nil and #v == 0 then
			-- Only recurse into record-like tables (string keys), never into arrays/maps of items.
			local isRecord = true
			for key in v do
				if type(key) ~= "string" then
					isRecord = false
					break
				end
			end
			if isRecord then
				TableUtil.reconcile(target[k], v)
			end
		end
	end
	return target
end

function TableUtil.find<T>(list: { T }, predicate: (T) -> boolean): (T?, number?)
	for i, v in list do
		if predicate(v) then
			return v, i
		end
	end
	return nil, nil
end

function TableUtil.removeValue<T>(list: { T }, value: T): boolean
	for i = #list, 1, -1 do
		if list[i] == value then
			table.remove(list, i)
			return true
		end
	end
	return false
end

function TableUtil.equal(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not TableUtil.equal(v, b[k]) then
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

-- Paths address nested values as dot-separated strings: "pens.1.jar".
-- Rule: a segment made only of digits is an array index (number key). Every other
-- segment is a string key. Maps must therefore never use digit-only string keys
-- (user-keyed maps use "u<userId>").
function TableUtil.splitPath(path: string): { any }
	local parts = {}
	for part in string.gmatch(path, "[^%.]+") do
		if string.match(part, "^%d+$") then
			table.insert(parts, tonumber(part))
		else
			table.insert(parts, part)
		end
	end
	return parts
end

function TableUtil.joinPath(parts: { any }): string
	local text = {}
	for i, part in parts do
		text[i] = tostring(part)
	end
	return table.concat(text, ".")
end

function TableUtil.getPath(root: any, parts: { any }): any
	local node = root
	for _, key in parts do
		if type(node) ~= "table" then
			return nil
		end
		node = node[key]
	end
	return node
end

-- Sets a value at a path, creating intermediate tables. `value == nil` deletes.
function TableUtil.setPath(root: { [any]: any }, parts: { any }, value: any)
	local node = root
	for i = 1, #parts - 1 do
		local key = parts[i]
		if type(node[key]) ~= "table" then
			node[key] = {}
		end
		node = node[key]
	end
	node[parts[#parts]] = value
end

return TableUtil
