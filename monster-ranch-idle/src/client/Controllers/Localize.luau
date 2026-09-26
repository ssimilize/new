--[[
	Localize (update 3.2): shows every text in the player's language (Shared/Locale).

	Language: profile.Settings.language ("auto" | "en" | "es" | "pt"); "auto" and a
	profile that has not loaded yet follow Player.LocaleId (Locale.Pick).

	Watches every TextLabel and TextButton under the PlayerGui and the Workspace (menus,
	toasts, billboards, hub signs) and every TextBox's PlaceholderText, never what a player
	types. When code sets a text, the controller keeps it as that object's English source
	and shows Locale.Translate of it, so screens and server messages stay in English in code
	and switching language re-translates everything in place.

	Fit: a translation wider than its English shrinks the text by the ratio of their
	lengths, never below MIN_FIT of the original size, so it takes no more room than the
	English did. Scaled text needs nothing, and nor does wrapped text in a box that grows
	with it (AutomaticSize Y).

	Opt out with the attribute Localize = false (language names, text players wrote).
	Roblox's own AutoLocalize is switched off on every LayerCollector seen, so the engine
	never translates a second time.

	  Localize:Language() -> "en" | "es" | "pt"
	  Localize:Source(textObject) -> string?   the English it was given
	  Localize:BaseSize(textObject) -> number? its TextSize before fitting
	  Localize.Changed    Signal(language)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Locale = require(Shared.Locale)
local Signal = require(Shared.Kernel.Signal)

local MIN_FIT = 0.75

type Record = { source: string, out: string, base: number?, applied: number? }

local Localize = {
	Name = "Localize",
	Dependencies = {},
	Changed = Signal.new(),
}

local ctx
local language = "en"
local records: { [Instance]: Record } = setmetatable({}, { __mode = "k" }) :: any
local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function visibleLength(text: string): number
	local plain = string.gsub(text, "<[^>]->", "")
	return utf8.len(plain) or #plain
end

local function optedOut(object: Instance): boolean
	return object:GetAttribute("Localize") == false
end

local function fit(object: any, rec: Record)
	if object.TextScaled then
		return
	end
	local grows = object.TextWrapped and (object.AutomaticSize == Enum.AutomaticSize.Y or object.AutomaticSize == Enum.AutomaticSize.XY)
	if rec.applied and object.TextSize ~= rec.applied then
		-- The screen changed the size itself since we last fitted: that is the new base.
		rec.base = object.TextSize
	end
	rec.base = rec.base or object.TextSize
	local base = rec.base :: number
	local size = base
	if not grows and rec.out ~= rec.source then
		local from, to = visibleLength(rec.source), visibleLength(rec.out)
		if to > from and to > 0 then
			size = math.max(math.floor(base * from / to), math.ceil(base * MIN_FIT))
		end
	end
	if object.TextSize ~= size then
		object.TextSize = size
	end
	rec.applied = size
end

local function apply(object: any)
	local rec = records[object]
	if not rec then
		return
	end
	local out = if optedOut(object) then rec.source else Locale.Translate(language, rec.source)
	rec.out = out
	if object:IsA("TextBox") then
		if object.PlaceholderText ~= out then
			object.PlaceholderText = out
		end
		return
	end
	if object.Text ~= out then
		object.Text = out
	end
	if rec.base or out ~= rec.source then
		fit(object, rec)
	end
end

local function textOf(object: any): string
	return if object:IsA("TextBox") then object.PlaceholderText else object.Text
end

local function watch(object: Instance)
	if watched[object] then
		return
	end
	if object:IsA("LayerCollector") then
		watched[object] = true
		local collector: any = object
		collector.AutoLocalize = false
		return
	end
	if not (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")) then
		return
	end
	watched[object] = true
	local current = textOf(object)
	records[object] = { source = current, out = current }
	apply(object)
	local property = if object:IsA("TextBox") then "PlaceholderText" else "Text"
	object:GetPropertyChangedSignal(property):Connect(function()
		local rec = records[object]
		local now = textOf(object)
		if rec and now ~= rec.out then
			rec.source = now
			apply(object)
		end
	end)
end

local function watchTree(root: Instance)
	for _, object in root:GetDescendants() do
		watch(object)
	end
	root.DescendantAdded:Connect(watch)
end

local function pick(): string
	local settings = ctx.Store:Get("profile.Settings")
	local setting = if type(settings) == "table" then settings.language else nil
	return Locale.Pick(setting, ctx.Player.LocaleId)
end

local function refresh()
	local next = pick()
	if next == language then
		return
	end
	language = next
	for object in records do
		if object.Parent then
			apply(object)
		end
	end
	Localize.Changed:Fire(language)
end

function Localize:Language(): string
	return language
end

-- The English a watched text object was given (nil if it isn't watched).
function Localize:Source(object: Instance): string?
	local rec = records[object]
	return rec and rec.source
end

-- The TextSize the English had before a translation was fitted.
function Localize:BaseSize(object: Instance): number?
	local rec = records[object]
	return if rec then rec.base or (object :: any).TextSize else nil
end

function Localize.Init(context)
	ctx = context
	language = pick()
	local gui = ctx.Player:FindFirstChildOfClass("PlayerGui") or ctx.Player:WaitForChild("PlayerGui")
	watchTree(gui)
	watchTree(workspace)
	ctx.Store:Observe("profile.Settings", refresh)
end

function Localize.Start()
	refresh()
end

return Localize
