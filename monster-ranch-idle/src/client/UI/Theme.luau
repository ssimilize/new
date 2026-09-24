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
	Friendship = hex("#EF6FA8"),
	Token = hex("#7CC7FF"),
	Xp = hex("#43B649"),
}

Theme.Fonts = {
	Display = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamBold,
	Mono = Enum.Font.Code,
}

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
	Friendship = "",
	Token = "",
	PanelTexture = "",
	ButtonTexture = "",
}

function Theme.Rarity(index: number): Color3
	local r = Config.Rarities.List[index]
	return if r then hex(r.color) else Theme.Colors.Gray
end

function Theme.RarityName(index: number): string
	local r = Config.Rarities.List[index]
	return if r then r.name else "?"
end

function Theme.Element(id: string): Color3
	local e = Config.Elements.ById[id]
	return if e then hex(e.color) else Theme.Colors.Gray
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

-- Readable text colour on top of a background colour.
function Theme.OnColor(background: Color3): Color3
	local luminance = 0.299 * background.R + 0.587 * background.G + 0.114 * background.B
	return if luminance > 0.72 then Theme.Colors.Text else Theme.Colors.White
end

return Theme
