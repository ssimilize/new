--[[
	LocaleHarvest: finds the English text the game can show, for the Locale specs and for
	translators. With LOCALE_REPORT=<file>, the Locale specs also write what is still
	missing to that file (one line per string, grouped by where it was found).

	  LocaleHarvest.fromFormat(fmt) -> template          "%d coins left" -> "{1} coins left"
	  LocaleHarvest.configStrings(Config) -> { Found }   every name / desc / text in Config
	  LocaleHarvest.serverMessages(root) -> { Found }    literals and formats the server sends:
	                                                     ctx:Fail, ctx:Notify, Social:Broadcast
	  LocaleHarvest.keptNames(Config) -> { [text] = true }  names that stay English
	  LocaleHarvest.missing(Locale, lang, text, kept) -> { string }   pieces left in English
	  LocaleHarvest.write(path, lines)

	Found = { text = string, where = string }
]]

local fs = require("@lune/fs")

local LocaleHarvest = {}

-- ─── printf → template ──────────────────────────────────────────────────────────────

-- A printf conversion the game uses: %s, %d, %.1f, %g, %02d, %q (never "5% per level").
local SPEC = "%%([%-0]?%d*%.?%d*[sdifgxq%%])"

-- Every %d / %s / %.1f / %02d becomes the next {n}; %% is a literal percent sign.
function LocaleHarvest.fromFormat(fmt: string): string
	local n = 0
	local out = string.gsub(fmt, SPEC, function(spec)
		if spec == "%" then
			return "%"
		end
		n += 1
		return "{" .. n .. "}"
	end)
	return out
end

-- ─── Config ─────────────────────────────────────────────────────────────────────────

local TEXT_KEYS = { name = true, desc = true, text = true, title = true, short = true, broadcast = true, label = true, hint = true }
local FORMAT_KEYS = { format = true }
-- Name tables of people, whose names stay English, and of Roblox places (internal lookups,
-- not text: "Trading Hub" is still translated where the game shows it).
local KEPT_TABLES = { BotNames = true, GhostNames = true }
local SKIPPED_TABLES = { PlaceNames = true }

function LocaleHarvest.keptNames(Config): { [string]: boolean }
	local kept = {}
	for _, line in Config.Species.Lines do
		for _, stage in line.forms do
			if stage.name then
				kept[stage.name] = true
			else
				for _, form in stage do
					kept[form.name] = true
				end
			end
		end
	end
	-- Boss banners shout names in capitals.
	for name in table.clone(kept) do
		kept[string.upper(name)] = true
	end
	for key in KEPT_TABLES do
		for _, holder in { Config.Arena, Config.Racing } do
			for _, name in (holder and holder[key]) or {} do
				kept[name] = true
			end
		end
	end
	return kept
end

function LocaleHarvest.configStrings(Config): { { text: string, where: string } }
	local found, seen, visited = {}, {}, {}
	local function add(text: string, where: string)
		if not seen[text] and string.find(text, "%a") then
			seen[text] = true
			table.insert(found, { text = text, where = where })
		end
	end
	local function walk(value, path: string, key: any)
		if type(value) == "string" then
			if type(key) == "string" and TEXT_KEYS[key] then
				-- Some texts are formats the game fills in ("Breed %s monsters").
				add(if string.find(value, "%%[%-0]?%d*%.?%d*[sdifgq]") then LocaleHarvest.fromFormat(value) else value, path)
			elseif type(key) == "string" and FORMAT_KEYS[key] then
				add(LocaleHarvest.fromFormat(value), path)
			end
			return
		end
		if type(value) ~= "table" or visited[value] then
			return
		end
		visited[value] = true
		if type(key) == "string" and SKIPPED_TABLES[key] then
			return
		end
		local isNameTable = type(key) == "string" and string.match(key, "Names$") ~= nil and not KEPT_TABLES[key]
		for k, v in value do
			if isNameTable and type(v) == "string" then
				add(v, path .. "." .. tostring(k))
			else
				walk(v, path .. "." .. tostring(k), k)
			end
		end
	end
	for name, section in Config do
		if name ~= "Flags" and name ~= "Sounds" then
			walk(section, "Config." .. name, name)
		end
	end
	table.sort(found, function(a, b)
		return a.where < b.where
	end)
	return found
end

-- ─── Server messages ────────────────────────────────────────────────────────────────

local function listFiles(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			listFiles(full, out)
		elseif string.match(entry, "%.luau$") then
			table.insert(out, full)
		end
	end
	return out
end

-- The first string argument of a call starting at `pos`: a literal, or the format of a
-- string.format(...) call. Returns nil for anything built another way.
local function firstText(source: string, pos: number): string?
	local lit = string.match(source, '^%s*"([^"\n]*)"', pos)
	if lit then
		return lit
	end
	local fmt = string.match(source, '^%s*string%.format%(%s*"([^"\n]*)"', pos)
	if fmt then
		return LocaleHarvest.fromFormat(fmt)
	end
	return nil
end

-- The calls whose text reaches a player unchanged. `skip` = arguments before the text.
local CALLS = {
	{ pattern = "ctx:Fail%(", skip = 0 },
	{ pattern = "ctx:Notify%(", skip = 1 },
	{ pattern = ":Broadcast%(", skip = 1 },
}

function LocaleHarvest.serverMessages(root: string): { { text: string, where: string } }
	local found, seen = {}, {}
	for _, file in listFiles(root .. "/src/server", {}) do
		local source = fs.readFile(file)
		for _, call in CALLS do
			local pos = 1
			while true do
				local s, e = string.find(source, call.pattern, pos)
				if not s then
					break
				end
				local at = e + 1
				for _ = 1, call.skip do
					local comma = string.find(source, ",", at, true)
					at = if comma then comma + 1 else at
				end
				local text = firstText(source, at)
				if text and string.find(text, "%a") and not seen[text] then
					seen[text] = true
					local line = select(2, string.gsub(string.sub(source, 1, s), "\n", "")) + 1
					table.insert(found, { text = text, where = string.sub(file, #root + 2) .. ":" .. line })
				end
				pos = e + 1
			end
		end
	end
	table.sort(found, function(a, b)
		return a.where < b.where
	end)
	return found
end

-- ─── Checks and reports ─────────────────────────────────────────────────────────────

local JOINTS = { "\n", " · ", ": ", " → ", " ×", ", " }

-- A name that stays English (test players are "Player<userId>"), or text without letters.
local function isKept(text: string, kept: { [string]: boolean }): boolean
	-- Spaces, symbols and emoji at either end don't make a kept name translatable.
	local trimmed = string.match(text, "^[%s\128-\255]*(.-)[%s\128-\255]*$")
	trimmed = string.gsub(trimmed, "^%d+%.%s+", "") -- a ranked row: "1. Player1008"
	return kept[trimmed] == true or string.match(trimmed, "^Player%d+$") ~= nil or not string.find(trimmed, "%a")
end

-- Pieces of `text` left in English, minus names that stay English. A piece made only of
-- kept names ("Nimbuff · Nimbuff") is fine as it is.
function LocaleHarvest.missing(Locale, lang: string, text: string, kept: { [string]: boolean }): { string }
	local _, pieces = Locale.Explain(lang, text)
	local out = {}
	for _, piece in pieces do
		local parts = { piece }
		for _, joint in JOINTS do
			local split = {}
			for _, part in parts do
				local pos = 1
				while true do
					local s, e = string.find(part, joint, pos, true)
					table.insert(split, string.sub(part, pos, if s then s - 1 else #part))
					if not s then
						break
					end
					pos = e + 1
				end
			end
			parts = split
		end
		local allKept = true
		for _, part in parts do
			if not isKept(part, kept) then
				allKept = false
				break
			end
		end
		if not allKept then
			table.insert(out, piece)
		end
	end
	return out
end

function LocaleHarvest.write(path: string, lines: { string })
	fs.writeFile(path, table.concat(lines, "\n") .. "\n")
end

return LocaleHarvest
