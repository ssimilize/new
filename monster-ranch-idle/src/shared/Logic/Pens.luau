--[[
	Logic/Pens (pure, glow-up R): which fence, props and habitat a pen shows and how far its Feed
	Garden's crops have grown. Data is Config.Pens; drawing is Visuals/PenDress (client).

	  Pens.Fence(Config, jarTier) -> (fenceDef, index)          highest tier whose jarTier <= jarTier
	  Pens.Upgrades(Config, capacity) -> { upgradeEntry }       every capacity step reached
	  Pens.Theme(Config, themeId) -> (themeLook, themeId)       unknown themes fall back to DefaultTheme
	  Pens.Dominant(Config, monsters) -> elementId?             monsters = { { appearance = { elements } } }
	  Pens.Plan(Config, pen, detail) -> plan                    pen = a global.Plots pen view
	  Pens.Pieces(prop, detail) -> { piece }                    the pieces drawn at this detail
	  Pens.PartCount(Config, plan) -> number                    parts the plan adds (fence caps included)
	  Pens.CropStage(Config, plot, now) -> 0..4                 0 empty, 1 seeds, 2 sprouts, 3 grown, 4 ready
	  Pens.GardenKey(Config, garden, now, detail) -> string     changes only when the drawing must

	detail: "full" (own plot, or near), "lite" (low graphics: small pieces dropped) or "far"
	(small pieces, theme props and fence caps dropped). A plan's `keys` = { fence, props, habitat }
	change only when that group has to be rebuilt.
]]

local Pens = {}

function Pens.Fence(Config, jarTier: number?)
	local fences = Config.Pens.Fences
	local tier = tonumber(jarTier) or 1
	local best, index = fences[1], 1
	for i, fence in fences do
		if tier >= fence.jarTier then
			best, index = fence, i
		end
	end
	return best, index
end

function Pens.Upgrades(Config, capacity: number?)
	local list = {}
	local cap = tonumber(capacity) or Config.Economy.Pens.startCapacity
	for _, entry in Config.Pens.Upgrades do
		if cap >= entry.capacity then
			table.insert(list, entry)
		end
	end
	return list
end

function Pens.Theme(Config, themeId: any)
	local themes = Config.Pens.Themes
	if type(themeId) == "string" and themes[themeId] then
		return themes[themeId], themeId
	end
	return themes[Config.Pens.DefaultTheme], Config.Pens.DefaultTheme
end

-- The element most monsters in the pen carry (a hybrid counts for both). Ties go to the
-- element listed first in Config.Elements, so every client picks the same one.
function Pens.Dominant(Config, monsters: any): string?
	if type(monsters) ~= "table" then
		return nil
	end
	local counts, total = {}, 0
	for _, m in monsters do
		local appearance = type(m) == "table" and m.appearance
		local elements = type(appearance) == "table" and appearance.elements
		if type(elements) == "table" then
			total += 1
			local seen = {}
			for _, e in elements do
				if type(e) == "string" and not seen[e] then
					seen[e] = true
					counts[e] = (counts[e] or 0) + 1
				end
			end
		end
	end
	local rule = Config.Pens.Habitat
	if total < rule.minMonsters then
		return nil
	end
	local best, bestCount = nil, 0
	for _, element in Config.Elements.List do
		local n = counts[element.id] or 0
		if n > bestCount and Config.Pens.Habitats[element.id] then
			best, bestCount = element.id, n
		end
	end
	if best and bestCount / total >= rule.minShare then
		return best
	end
	return nil
end

function Pens.Pieces(prop, detail: string): { any }
	if detail == "full" then
		return prop.pieces
	end
	local list = {}
	for _, piece in prop.pieces do
		if not piece.small then
			table.insert(list, piece)
		end
	end
	return list
end

local function entry(Config, id: string, at: { number }, group: string, extra: { [string]: any }?)
	local prop = Config.Pens.Props[id]
	local e = { id = id, prop = prop, x = at[1], z = at[2], group = group, spot = prop and prop.spot or nil }
	for k, v in extra or {} do
		e[k] = v
	end
	return e
end

function Pens.Plan(Config, pen: any, detail: string)
	pen = if type(pen) == "table" then pen else {}
	detail = detail or "full"
	local fence, fenceIndex = Pens.Fence(Config, pen.jarTier)
	local look, themeId = Pens.Theme(Config, pen.theme)
	local capacity = tonumber(pen.capacity) or Config.Economy.Pens.startCapacity

	local props = {}
	for _, up in Pens.Upgrades(Config, capacity) do
		table.insert(props, entry(Config, up.id, up.at, "props"))
	end
	if detail ~= "far" then
		for i, id in look.props or {} do
			local spot = Config.Pens.ThemeSpots[i]
			if spot and Config.Pens.Props[id] then
				table.insert(props, entry(Config, id, spot, "props"))
			end
		end
	end
	local element = Pens.Dominant(Config, pen.monsters)
	local habitat = {}
	if element then
		table.insert(habitat, entry(Config, Config.Pens.Habitats[element], Config.Pens.HabitatSpot, "habitat", { habitat = element }))
	end

	-- The theme's own colour goes into the fence paint, so it is part of the fence key.
	local themeDef = Config.Decor.PenThemeById[themeId] or Config.Decor.PenThemes[1]
	return {
		detail = detail,
		fence = fence,
		fenceIndex = fenceIndex,
		look = look,
		theme = themeId,
		themeDef = themeDef,
		capacity = capacity,
		element = element,
		props = props,
		habitat = habitat,
		keys = {
			fence = string.format("%s#%s#%s", fence.id, themeId, detail),
			props = string.format("%d#%s#%s", capacity, themeId, detail),
			habitat = string.format("%s#%s", element or "-", detail),
		},
	}
end

function Pens.PartCount(_config, plan): number
	local n = 0
	if plan.fence.cap and plan.detail ~= "far" then
		n += 4 -- one per corner post
	end
	for _, group in { plan.props, plan.habitat } do
		for _, e in group do
			if e.prop then
				n += if e.prop.mesh ~= "" then 1 else #Pens.Pieces(e.prop, plan.detail)
			end
		end
	end
	return n
end

-- Garden ------------------------------------------------------------------------------------

function Pens.CropStage(Config, plot: any, now: number): number
	if type(plot) ~= "table" or type(plot.flavor) ~= "string" then
		return 0
	end
	local readyAt = tonumber(plot.readyAt) or 0
	local grow = Config.Economy.Garden.growSeconds
	if now >= readyAt then
		return 4
	end
	local progress = 1 - (readyAt - now) / grow
	local stage = 1
	for i, at in Config.Pens.Garden.stageAt do
		if progress >= at then
			stage = i
		end
	end
	return stage
end

function Pens.GardenKey(Config, garden: any, now: number, detail: string): string
	if type(garden) ~= "table" or type(garden.plots) ~= "table" then
		return "none"
	end
	local parts = { detail, tostring(#garden.plots) }
	for _, plot in garden.plots do
		local stage = Pens.CropStage(Config, plot, now)
		table.insert(parts, if stage == 0 then "0" else stage .. (plot.flavor or ""))
	end
	return table.concat(parts, ",")
end

return Pens
