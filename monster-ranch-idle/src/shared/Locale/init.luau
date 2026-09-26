--[[
	Locale (update 3.2): the game in Spanish and Portuguese (Brazil).

	English stays the source language in code. Each catalogue (`es`, `pt`) maps an English
	string the game shows to its translation, the way a Roblox LocalizationTable maps its
	Source column:

	  ["Egg Shop"] = "Tienda de huevos",                                    -- exact
	  ["Unlocks at Ranch Level {1}"] = "Se desbloquea en el Nivel de Rancho {1}", -- template

	A template's {1}, {2}, … {12} each stand for one non-empty piece of text. The pieces a
	template matches are translated too (whole, or split on list separators), then put
	back in the order the translation asks for. Numbers, names and anything else without
	an entry pass through unchanged. A string with no match stays English.

	Neither screens nor server messages call this: the client's Localize controller runs
	every text the player sees through Translate.

	  Locale.Languages                     { { id, name } } (names in their own language)
	  Locale.Choices                       values of profile.Settings.language
	  Locale.FromLocaleId(localeId) -> id  Roblox locale ("es-mx", "pt-br") -> "es" | "pt" | "en"
	  Locale.Pick(setting, localeId) -> id the language to show
	  Locale.Translate(id, text) -> text
	  Locale.Explain(id, text) -> (text?, missing)  the translation (nil if nothing matched)
	                                       and every piece with letters left in English
	  Locale.Catalog(id) -> { [source] = translation }
	  Locale.Placeholders(text) -> { n }   sorted placeholder numbers (catalogue checks)
	  Locale.Register(id, catalog)         tests: a catalogue under an id of their own
]]

local Locale = {}

Locale.Languages = {
	{ id = "en", name = "English" },
	{ id = "es", name = "Español" },
	{ id = "pt", name = "Português" },
}

-- "auto" follows the player's Roblox language.
Locale.Choices = { "auto", "en", "es", "pt" }

local CATALOGS = { es = script.es, pt = script.pt }
local registered: { [string]: { [string]: string } } = {}

-- Text with no entry of its own is split on the joints the UI builds text with: lines,
-- " · " between facts, "Label: value", "A → B" and "Grove Egg ×2". Pieces a template
-- matched may also be comma lists ("Grove Egg, Pearl Egg").
local TEXT_SEPARATORS = { "\n", " · ", ": ", " → ", " ×" }
local PIECE_SEPARATORS = { "\n", " · ", ": ", " → ", " ×", ", " }
local MAX_DEPTH = 3
local CACHE_LIMIT = 4000
-- Leading and trailing symbols and emoji ("✔ Normal", "🔒 Learn Trailblazer") are set aside
-- like spaces: bytes from 0x80 up (English source letters are ASCII).
local EDGES = "^([%s\128-\255]*)(.-)([%s\128-\255]*)$"

function Locale.FromLocaleId(localeId: string?): string
	local prefix = string.match(string.lower(tostring(localeId or "")), "^(%a+)")
	if prefix == "es" or prefix == "pt" then
		return prefix
	end
	return "en"
end

function Locale.Pick(setting: string?, localeId: string?): string
	if setting == "en" or setting == "es" or setting == "pt" then
		return setting
	end
	return Locale.FromLocaleId(localeId)
end

function Locale.Placeholders(text: string): { number }
	local list = {}
	for n in string.gmatch(text, "{(%d+)}") do
		table.insert(list, tonumber(n) :: number)
	end
	table.sort(list)
	return list
end

-- ─── Compiled catalogues ────────────────────────────────────────────────────────────

type Template = {
	source: string,
	target: string,
	pattern: string,
	order: { number },
	literal: number,
}

type Compiled = {
	catalog: { [string]: string },
	exact: { [string]: string },
	byLead: { [string]: { Template } },
	open: { Template },
	cache: { [string]: string | false },
	cached: number,
}

local compiled: { [string]: Compiled } = {}

local function escape(s: string): string
	return (string.gsub(s, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

local function parse(source: string, target: string): Template
	local pattern, order, literal = { "^" }, {}, 0
	local pos = 1
	while true do
		local s, e, n = string.find(source, "{(%d+)}", pos)
		if not s then
			break
		end
		local piece = string.sub(source, pos, s - 1)
		literal += #piece
		table.insert(pattern, escape(piece))
		table.insert(pattern, "(.-)")
		table.insert(order, tonumber(n) :: number)
		pos = e + 1
	end
	local tail = string.sub(source, pos)
	literal += #tail
	table.insert(pattern, escape(tail))
	table.insert(pattern, "$")
	return { source = source, target = target, pattern = table.concat(pattern), order = order, literal = literal }
end

-- More literal text first, so "Collect all +{1}" wins over "{1} +{2}".
local function bySpecificity(a: Template, b: Template): boolean
	if a.literal ~= b.literal then
		return a.literal > b.literal
	end
	return a.source < b.source
end

local function compile(id: string): Compiled?
	local existing = compiled[id]
	if existing then
		return existing
	end
	local catalog = registered[id]
	if not catalog then
		local module = CATALOGS[id]
		if not module then
			return nil
		end
		catalog = require(module) :: { [string]: string }
	end
	local c: Compiled = { catalog = catalog, exact = {}, byLead = {}, open = {}, cache = {}, cached = 0 }
	for source, target in catalog do
		if string.find(source, "{%d+}") then
			local t = parse(source, target)
			local lead = string.sub(source, 1, 1)
			if lead == "{" then
				table.insert(c.open, t)
			else
				c.byLead[lead] = c.byLead[lead] or {}
				table.insert(c.byLead[lead], t)
			end
		else
			c.exact[source] = target
		end
	end
	table.sort(c.open, bySpecificity)
	for _, list in c.byLead do
		table.sort(list, bySpecificity)
	end
	compiled[id] = c
	return c
end

-- Tests pin the matching rules with a small catalogue under an id of their own.
function Locale.Register(id: string, catalog: { [string]: string })
	registered[id] = catalog
	compiled[id] = nil
end

function Locale.Catalog(id: string): { [string]: string }
	local c = compile(id)
	return if c then c.catalog else {}
end

-- ─── Matching ───────────────────────────────────────────────────────────────────────

local resolve

-- Number suffixes from Logic/Format read the same in every language: "1.2K", "3h 12m",
-- "4.5 kg", "+30 XP".
local UNITS = {
	K = true,
	M = true,
	B = true,
	T = true,
	Qa = true,
	Qi = true,
	Sx = true,
	Sp = true,
	Oc = true,
	No = true,
	Dc = true,
	d = true,
	h = true,
	m = true,
	s = true,
	kg = true,
	XP = true,
}

-- Whether a text has words to translate. English source text: ASCII letters are enough,
-- so "×2", "★★★" and "12:30" have none.
local function hasLetters(text: string): boolean
	if not string.find(text, "%a") then
		return false
	end
	-- A unit after a digit or a placeholder ("{1}s" from a "%ds" format) is not a word.
	local stripped = string.gsub(text, "([%d}])%s?(%a+)", function(digit, unit)
		return if UNITS[unit] then digit else nil
	end)
	return string.find(stripped, "%a") ~= nil
end

local function piece(c: Compiled, text: string, depth: number, missing: { string }?): string
	if not hasLetters(text) then
		return text
	end
	local hit = c.exact[text]
	if hit then
		return hit
	end
	local found = if depth < MAX_DEPTH then resolve(c, text, depth + 1, PIECE_SEPARATORS, missing) else nil
	if found then
		return found
	end
	if missing then
		table.insert(missing, text)
	end
	return text
end

local function tryTemplates(c: Compiled, list: { Template }?, text: string, depth: number, missing: { string }?): string?
	if not list then
		return nil
	end
	for _, t in list do
		local caps = table.pack(string.match(text, t.pattern))
		if caps[1] ~= nil then
			local empty = false
			for i = 1, #t.order do
				if caps[i] == "" then
					empty = true
					break
				end
			end
			if not empty then
				local args = {}
				for i, n in t.order do
					args[n] = piece(c, caps[i], depth, missing)
				end
				return (string.gsub(t.target, "{(%d+)}", function(n)
					return args[tonumber(n)] or ""
				end))
			end
		end
	end
	return nil
end

-- Splits on the first separator the text contains and translates each part. Succeeds when
-- at least one part with letters was known, so "Cindlet · Lv 5" still translates "Lv 5".
local function trySplit(c: Compiled, text: string, depth: number, separators: { string }, missing: { string }?): string?
	for _, sep in separators do
		if string.find(text, sep, 1, true) then
			local parts, scratch, known = {}, {}, false
			local pos = 1
			while true do
				local s, e = string.find(text, sep, pos, true)
				local part = string.sub(text, pos, if s then s - 1 else #text)
				local before = #scratch
				local out = piece(c, part, depth, scratch)
				table.insert(parts, out)
				if out ~= part or (hasLetters(part) and #scratch == before) then
					known = true
				end
				if not s then
					break
				end
				pos = e + 1
			end
			if not known then
				return nil
			end
			if missing then
				table.move(scratch, 1, #scratch, #missing + 1, missing)
			end
			return table.concat(parts, sep)
		end
	end
	return nil
end

-- The translation of `text`, or nil when nothing in it matched. Pieces left in English
-- are appended to `missing` when it is given.
function resolve(c: Compiled, text: string, depth: number, separators: { string }, missing: { string }?): string?
	local hit = c.exact[text]
	if hit then
		return hit
	end
	local lead, body, trail = string.match(text, EDGES)
	if body ~= text then
		if not hasLetters(body) then
			return nil
		end
		local inner = resolve(c, body, depth, separators, missing)
		return if inner then lead .. inner .. trail else nil
	end
	local found = tryTemplates(c, c.byLead[string.sub(text, 1, 1)], text, depth, missing) or tryTemplates(c, c.open, text, depth, missing)
	if found then
		return found
	end
	if depth < MAX_DEPTH then
		return trySplit(c, text, depth, separators, missing)
	end
	return nil
end

function Locale.Translate(id: string, text: string): string
	if id == "en" or type(text) ~= "string" or text == "" or not hasLetters(text) then
		return text
	end
	local c = compile(id)
	if not c then
		return text
	end
	local cached = c.cache[text]
	if cached ~= nil then
		return if cached then cached else text
	end
	local out = resolve(c, text, 0, TEXT_SEPARATORS, nil)
	if c.cached >= CACHE_LIMIT then
		table.clear(c.cache)
		c.cached = 0
	end
	c.cache[text] = out or false
	c.cached += 1
	return out or text
end

function Locale.Explain(id: string, text: string): (string?, { string })
	local missing = {}
	if id == "en" or type(text) ~= "string" or not hasLetters(text) then
		return text, missing
	end
	local c = compile(id)
	if not c then
		return nil, { text }
	end
	local out = resolve(c, text, 0, TEXT_SEPARATORS, missing)
	if not out and #missing == 0 then
		table.insert(missing, text)
	end
	return out, missing
end

return Locale
