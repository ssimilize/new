--[[
	Theme: the placeholder visual language from the GDD mockups (chunky outlined buttons,
	cream panels, coloured header ribbons). Art can reskin the whole UI by changing this file
	and filling `Images` with uploaded asset ids; components fall back to shapes when an
	image id is empty.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Theme = {}

local hex = Color3.fromHex

Theme.Colors = {
	Ink = hex("#1B1B1B"),
	Panel = hex("#FFF7E3"),
	PanelDeep = hex("#F3E6C4"),
	Card = hex("#FFFFFF"),
	Line = hex("#CDBF9E"),
	Text = hex("#2A2419"),
	TextMuted = hex("#6B5F48"),
	White = hex("#FFFFFF"),
	Green = hex("#43B649"),
	Orange = hex("#F2A93B"),
	Pink = hex("#EF6FA8"),
	Blue = hex("#4FB6F2"),
	Purple = hex("#8B6AD8"),
	Red = hex("#E5484D"),
	Gold = hex("#FFD447"),
	Gray = hex("#9AA39C"),
	Dark = hex("#121C16"),
	Sky = hex("#86CEFF"),
	Grass = hex("#7CC456"),
	Coin = hex("#F2B01E"),
	Gem = hex("#E8436F"),
	Food = hex("#E5484D"),
	Treat = hex("#E7A33B"),
	Stardust = hex("#8B6AD8"),
	Ribbon = hex("#E5486E"),
	Friendship = hex("#EF6FA8"),
	Token = hex("#7CC7FF"),
	Xp = hex("#43B649"),
}

Theme.Fonts = {
	Display = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamBold,
	Mono = Enum.Font.Code,
}

-- R2-A11Y: two client-only mirrors of profile.Settings, read straight off the module (same
-- pattern as UI/Anim.enabled) so any component can consult them without threading ctx through.
-- Set once, on join and on every profile.Settings change, by the Broadcasts controller.
Theme.ColorBlind = false -- adds Config.Rarities.mark / Config.Elements.glyph next to every chip's colour
Theme.TextScale = 1 -- 1 = normal, ~1.15 = large (Create.Text stores the unscaled size to rescale live)

Theme.TextSize = {
	Hero = 40,
	Title = 30,
	Header = 24,
	Button = 22,
	Body = 18,
	Small = 15,
	Tiny = 12,
}

Theme.Radius = {
	Panel = 18,
	Button = 14,
	Card = 12,
	Pill = 999,
}

Theme.Stroke = {
	Panel = 4,
	Button = 3,
	Text = 2,
	Card = 3,
}

-- Uploaded art. Leave as "" to use the procedural placeholders.
Theme.Images = {
	Coin = "",
	Gem = "",
	Food = "",
	Treat = "",
	Stardust = "",
	Ribbon = "",
	Friendship = "",
	Token = "",
	PanelTexture = "rbxassetid://118806226536175",
	ButtonTexture = "rbxassetid://70470138886253",
}

-- 9-slice skins for Theme.Images.PanelTexture / ButtonTexture (tools/ui/nine_slice.py draws them at
-- 2x, hence SliceScale 0.5). They are overlays: outline, top highlight, inner shade (and the button
-- lip) over the component's own colour, so one image serves every button colour.
Theme.Slices = {
	Panel = { Center = Rect.new(44, 44, 84, 84), Scale = 0.5 },
	Button = { Center = Rect.new(32, 32, 64, 64), Scale = 0.5 },
}

function Theme.Rarity(index: number): Color3
	local r = Config.Rarities.List[index]
	return if r then hex(if Theme.ColorBlind and r.cbColor then r.cbColor else r.color) else Theme.Colors.Gray
end

function Theme.RarityName(index: number): string
	local r = Config.Rarities.List[index]
	return if r then r.name else "?"
end

-- R2-A11Y: the letter drawn next to a rarity chip's colour in colour-blind mode.
function Theme.RarityMark(index: number): string
	local r = Config.Rarities.List[index]
	return if r then r.mark else "?"
end

-- R2-A11Y: the glyph drawn next to an element chip's colour in colour-blind mode.
function Theme.ElementGlyph(id: string): string
	local e = Config.Elements.ById[id]
	return if e then e.glyph else "?"
end

function Theme.Element(id: string): Color3
	local e = Config.Elements.ById[id]
	return if e then hex(if Theme.ColorBlind and e.cbColor then e.cbColor else e.color) else Theme.Colors.Gray
end

function Theme.ElementLight(id: string): Color3
	local e = Config.Elements.ById[id]
	return if e then hex(e.light) else Theme.Colors.White
end

function Theme.Mutation(id: string): Color3
	local m = Config.Mutations.ById[id]
	return if m then hex(m.color) else Theme.Colors.Gray
end

function Theme.Food(id: string): Color3
	local f = Config.Food.ById[id]
	return if f then hex(f.color) else Theme.Colors.Food
end

-- R2-A11Y: every TextLabel/TextButton built by Create.Text carries a "BaseTextSize" attribute
-- (its size at Theme.TextScale == 1). Call this once, after changing Theme.TextScale, to resize
-- every already-built label live (screens are built once and reused - see Kernel/Router.luau -
-- so this is the only way an open or previously-opened screen picks up the new scale without a
-- rejoin). `root` is normally the whole PlayerGui.
function Theme.RescaleText(root: Instance)
	for _, inst in root:GetDescendants() do
		if inst:IsA("TextLabel") or inst:IsA("TextButton") then
			local base = inst:GetAttribute("BaseTextSize")
			if type(base) == "number" then
				inst.TextSize = base * Theme.TextScale
			end
		end
	end
end

-- Readable text colour on top of a background colour.
function Theme.OnColor(background: Color3): Color3
	local luminance = 0.299 * background.R + 0.587 * background.G + 0.114 * background.B
	return if luminance > 0.72 then Theme.Colors.Text else Theme.Colors.White
end

return Theme
