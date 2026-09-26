--[[
	Logic/Codex (glow-up O): Codex milestones, built from the species, egg and region content
	(design in Config/Codex's header). Pure; used by Systems/Codex, the Codex screen and the HUD.

	  Codex.Milestones() -> { Milestone }          in display order (memoised)
	  Codex.ById() -> { [id]: Milestone }
	  Codex.LineForms(lineDef) -> { formId }        every form of a line, in path order
	  Codex.Found(codex) -> { [formId]: true }      from profile.Monsters.codex
	  Codex.Progress(milestone, found) -> have, need
	  Codex.IsDone(milestone, found) -> boolean
	  Codex.Claimable(codex, claimed) -> number     done and not yet claimed

	Milestone = { id, kind = "element"|"egg"|"region"|"total", key, order, forms = { formId },
	              need, all: boolean, gems, items = { itemId }, badge: number (0 = none) }
	`key` is the element id, egg id (the first egg of the pool), region id, or "" for totals.
]]

local Config = require(script.Parent.Parent.Config)

local Codex = {}

local cache: { any }? = nil
local byId: { [string]: any }? = nil

function Codex.LineForms(def): { string }
	local list = { def.forms[1].id, def.forms[2].id }
	for _, adult in def.forms[3] do
		table.insert(list, adult.id)
	end
	return list
end

local function formsOfLines(lineIds: { string }): { string }
	local out, seen = {}, {}
	for _, lineId in lineIds do
		local def = Config.Species.ById[lineId]
		if def and not seen[lineId] then
			seen[lineId] = true
			for _, formId in Codex.LineForms(def) do
				table.insert(out, formId)
			end
		end
	end
	return out
end

local function build()
	local C = Config.Codex
	local list = {}
	local function add(m)
		m.order = #list + 1
		m.items = m.items or {}
		m.badge = tonumber(C.BadgeIds[m.id]) or 0
		table.insert(list, m)
	end

	-- Overall steps first: they are the track every player sees move.
	local completeLines = {}
	for _, def in Config.Species.Lines do
		if not def.event then
			table.insert(completeLines, def.id)
		end
	end
	local completeForms = formsOfLines(completeLines)
	for i, step in C.TotalSteps do
		if step < #completeForms then
			local title = C.TotalTitles[step]
			add({
				id = "total_" .. step,
				kind = "total",
				key = "",
				forms = completeForms,
				need = step,
				all = false,
				gems = C.Gems.total[i] or 0,
				items = if title then { title } else nil,
			})
		end
	end
	add({
		id = "complete",
		kind = "total",
		key = "",
		forms = completeForms,
		need = #completeForms,
		all = true,
		gems = C.Gems.complete,
		items = table.clone(C.CompleteItems),
	})

	-- Elements (a line's first element; no hybrids or event lines).
	for _, el in Config.Elements.List do
		local lines = {}
		for _, def in Config.Species.Lines do
			if not def.event and not def.hybrid and def.elements[1] == el.id then
				table.insert(lines, def.id)
			end
		end
		local forms = formsOfLines(lines)
		if #forms > 0 then
			for i, step in C.ElementSteps do
				if step < #forms then
					add({
						id = "el_" .. el.id .. "_" .. step,
						kind = "element",
						key = el.id,
						forms = forms,
						need = step,
						all = false,
						gems = C.Gems.elementStep[i] or 0,
					})
				end
			end
			local title = C.ElementTitles[el.id]
			add({
				id = "el_" .. el.id .. "_all",
				kind = "element",
				key = el.id,
				forms = forms,
				need = #forms,
				all = true,
				gems = C.Gems.elementAll,
				items = if title then { title } else nil,
			})
		end
	end

	-- Eggs: one track per pool, named after the first egg that hatches from it.
	local pools = {}
	for _, egg in Config.Eggs.List do
		if egg.pool and not pools[egg.pool] then
			pools[egg.pool] = true
			local forms = formsOfLines(Config.Species.Pools[egg.pool] or {})
			if #forms > 0 then
				add({
					id = "egg_" .. egg.pool,
					kind = "egg",
					key = egg.id,
					forms = forms,
					need = #forms,
					all = true,
					gems = C.Gems.egg,
				})
			end
		end
	end

	-- Regions: every line met there (enemies, the depths band, bosses).
	for _, region in Config.Regions.List do
		local lines = table.clone(region.enemyLines or {})
		if region.depths then
			for _, lineId in region.depths.enemyLines or {} do
				table.insert(lines, lineId)
			end
		end
		local stages = {}
		for stage in region.bosses or {} do
			table.insert(stages, stage)
		end
		table.sort(stages)
		for _, stage in stages do
			table.insert(lines, region.bosses[stage].line)
		end
		local forms = formsOfLines(lines)
		if #forms > 0 then
			add({
				id = "region_" .. region.id,
				kind = "region",
				key = region.id,
				forms = forms,
				need = #forms,
				all = true,
				gems = C.Gems.region,
			})
		end
	end
	return list
end

function Codex.Milestones(): { any }
	if not cache then
		cache = build()
		local map = {}
		for _, m in cache :: { any } do
			map[m.id] = m
		end
		byId = map
	end
	return cache :: { any }
end

function Codex.ById(): { [string]: any }
	Codex.Milestones()
	return byId :: { [string]: any }
end

-- profile.Monsters.codex -> { [formId]: true }. Tolerates damaged entries.
function Codex.Found(codex): { [string]: boolean }
	local found = {}
	if type(codex) ~= "table" then
		return found
	end
	for _, entry in codex do
		if type(entry) == "table" and type(entry.forms) == "table" then
			for formId, yes in entry.forms do
				if yes == true and type(formId) == "string" then
					found[formId] = true
				end
			end
		end
	end
	return found
end

function Codex.Progress(milestone, found): (number, number)
	local have = 0
	for _, formId in milestone.forms do
		if found[formId] then
			have += 1
		end
	end
	return math.min(have, milestone.need), milestone.need
end

function Codex.IsDone(milestone, found): boolean
	local have, need = Codex.Progress(milestone, found)
	return have >= need
end

function Codex.Claimable(codex, claimed): number
	local found = Codex.Found(codex)
	local n = 0
	for _, m in Codex.Milestones() do
		if not (type(claimed) == "table" and claimed[m.id]) and Codex.IsDone(m, found) then
			n += 1
		end
	end
	return n
end

return Codex
