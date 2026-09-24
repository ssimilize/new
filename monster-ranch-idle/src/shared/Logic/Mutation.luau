--[[
	Mutation rules: adding a mutation to a monster's list with the per-monster cap and combos.

	Mutation.Add(muts, id) -> (newMuts, result)
	  result = "added" | "combined" | "duplicate" | "full"
	The input list is not modified.
]]

local Config = require(script.Parent.Parent.Config)
local Mutations = Config.Mutations

local Mutation = {}

function Mutation.ComboOf(a: string, b: string): string?
	local pair = { a, b }
	table.sort(pair)
	return Mutations.Combos[pair[1] .. "+" .. pair[2]]
end

function Mutation.Add(muts: { string }, id: string): ({ string }, string)
	local list = table.clone(muts or {})
	for _, existing in list do
		if existing == id then
			return list, "duplicate"
		end
		-- Already holding a combo made from this mutation counts as a duplicate too.
		local def = Mutations.ById[existing]
		if def and def.combo and (def.combo[1] == id or def.combo[2] == id) then
			return list, "duplicate"
		end
	end
	for i, existing in list do
		local combo = Mutation.ComboOf(existing, id)
		if combo then
			list[i] = combo
			return list, "combined"
		end
	end
	if #list >= Mutations.MaxPerMonster then
		return list, "full"
	end
	table.insert(list, id)
	return list, "added"
end

function Mutation.Has(muts: { string }?, id: string): boolean
	for _, existing in muts or {} do
		if existing == id then
			return true
		end
	end
	return false
end

return Mutation
