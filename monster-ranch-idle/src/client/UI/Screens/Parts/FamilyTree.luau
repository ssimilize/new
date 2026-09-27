--[[
	Parts/FamilyTree (update 3.9): a monster's pedigree (Logic/Pedigree) drawn into a frame, left
	to right: the monster, its two parents, its four grandparents. Each node shows an icon, the
	name, a rarity-coloured border and the five gene grade letters (Config.Genetics.Stats order).
	An ancestor the record does not know reads "Hatched" (its child was hatched, generation 0)
	or "Unknown" (bred before pedigrees were kept).

		FamilyTree.build(parent, m) -> Frame     m = the live monster record
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Formulas = require(Shared.Logic.Formulas)
local Appearance = require(Shared.Logic.Appearance)
local Genetics = require(Shared.Logic.Genetics)
local Pedigree = require(Shared.Logic.Pedigree)

local UI = script.Parent.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local MonsterIcon = require(UI.Components.MonsterIcon)
local GeneGrades = require(UI.Components.GeneGrades)

local New = Create.New
local C = Theme.Colors

local FamilyTree = {}

local NODE_W, NODE_H, GAP_Y, COL_GAP = 216, 64, 10, 38

local function gradeLetters(parent: GuiObject, grades: string)
	local row = New("Frame", {
		Name = "Grades",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(62, 34),
		Size = UDim2.new(1, -66, 0, 22),
		Parent = parent,
	}, { Create.List("x", 3, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	for i = 1, #grades do
		local letter = string.sub(grades, i, i)
		GeneGrades.badge({ Points = Genetics.GradeMin(letter) or 0, Size = UDim2.fromOffset(24, 20), LayoutOrder = i, Parent = row })
	end
end

-- One known monster: icon, name, grades.
local function node(parent: GuiObject, name: string, slot: string, info)
	local frame = New("Frame", {
		Name = "Node_" .. slot,
		BackgroundColor3 = C.PanelDeep,
		Size = UDim2.fromOffset(NODE_W, NODE_H),
		Position = info.position,
		Parent = parent,
	}, { Create.Corner(Theme.Radius.Card), Create.Stroke(3, Theme.Rarity(info.rarity or 1)) })
	local ok, icon = pcall(function()
		return MonsterIcon.new(info.appearance, 52)
	end)
	if not ok then
		icon = MonsterIcon.silhouette(info.line, 52)
	end
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 6, 0.5, 0)
	icon.Parent = frame
	local label = Create.Text({
		Name = "Name",
		Text = name,
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.Text,
		Stroke = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Position = UDim2.fromOffset(62, 6),
		Size = UDim2.new(1, -66, 0, 24),
		Parent = frame,
	})
	label:SetAttribute("Localize", false) -- a player's name for the monster, or a form name
	gradeLetters(frame, info.grades)
	return frame
end

-- An ancestor the record does not know.
local function missing(parent: GuiObject, slot: string, position: UDim2, hatched: boolean)
	local frame = New("Frame", {
		Name = "Node_" .. slot,
		BackgroundColor3 = C.PanelDeep,
		BackgroundTransparency = 0.4,
		Size = UDim2.fromOffset(NODE_W, NODE_H),
		Position = position,
		Parent = parent,
	}, { Create.Corner(Theme.Radius.Card), Create.Stroke(2, C.Line) })
	Create.Text({
		Text = if hatched then "Hatched" else "Unknown",
		TextSize = Theme.TextSize.Body,
		TextColor3 = C.TextMuted,
		Stroke = false,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	return frame
end

local function snapInfo(snap, position: UDim2)
	local ok, ap = pcall(Appearance.Preview, snap.line, 3, snap.form, snap.rarity, snap.variant)
	return {
		appearance = if ok then ap else nil,
		line = snap.line,
		rarity = snap.rarity,
		grades = snap.grades,
		position = position,
	}
end

local function connector(parent: GuiObject, fromY: number, toY: number, x: number)
	-- An elbow from a child's right edge (fromY) to a parent's left edge (toY).
	local mid = x + COL_GAP / 2
	local top, bottom = math.min(fromY, toY), math.max(fromY, toY)
	for _, props in
		{
			{ Position = UDim2.fromOffset(x, fromY - 1), Size = UDim2.fromOffset(COL_GAP / 2, 3) },
			{ Position = UDim2.fromOffset(mid - 1, top - 1), Size = UDim2.fromOffset(3, bottom - top + 3) },
			{ Position = UDim2.fromOffset(mid, toY - 1), Size = UDim2.fromOffset(COL_GAP / 2, 3) },
		}
	do
		New("Frame", { BackgroundColor3 = C.Line, BorderSizePixel = 0, Position = props.Position, Size = props.Size, Parent = parent })
	end
end

function FamilyTree.build(parent: Instance, m)
	local root = New("Frame", {
		Name = "FamilyTree",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 4 * NODE_H + 3 * GAP_Y),
		Parent = parent,
	})
	local ped = if type(m.ped) == "table" then m.ped else nil
	local colX = { 0, NODE_W + COL_GAP, 2 * (NODE_W + COL_GAP) }
	-- Grandparents fill the right column; each parent sits beside its two, the monster between.
	local gy = {}
	for i = 1, 4 do
		gy[i] = (i - 1) * (NODE_H + GAP_Y)
	end
	local py = { (gy[1] + gy[2]) / 2, (gy[3] + gy[4]) / 2 }
	local my = (py[1] + py[2]) / 2

	local names = {}
	for _, stat in Config.Genetics.Stats do
		table.insert(names, Config.Genetics.StatNames[stat] or stat)
	end
	Create.Text({
		Name = "Legend",
		Text = string.format("Grades: %s", table.concat(names, " · ")),
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		Stroke = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(NODE_W, 44),
		Parent = root,
	})

	local ok, ap = pcall(Appearance.Of, m)
	node(root, Formulas.DisplayName(m), "self", {
		appearance = if ok then ap else nil,
		line = m.line,
		rarity = m.rarity,
		grades = Genetics.Grades(m.genes),
		position = UDim2.fromOffset(colX[1], my),
	})

	local selfHatched = (tonumber(m.gen) or 0) == 0
	for p, key in { "a", "b" } do
		local snap = ped and ped[key]
		local pos = UDim2.fromOffset(colX[2], py[p])
		connector(root, my + NODE_H / 2, py[p] + NODE_H / 2, colX[1] + NODE_W)
		if type(snap) == "table" then
			node(root, Pedigree.Name(snap), key, snapInfo(snap, pos))
		else
			missing(root, key, pos, selfHatched)
		end
		local parentHatched = type(snap) == "table" and (tonumber(snap.gen) or 0) == 0
		for g, gkey in { key .. "a", key .. "b" } do
			local index = (p - 1) * 2 + g
			local gpos = UDim2.fromOffset(colX[3], gy[index])
			connector(root, py[p] + NODE_H / 2, gy[index] + NODE_H / 2, colX[2] + NODE_W)
			local gsnap = ped and ped[gkey]
			if type(gsnap) == "table" then
				node(root, Pedigree.Name(gsnap), gkey, snapInfo(gsnap, gpos))
			else
				missing(root, gkey, gpos, if snap then parentHatched else selfHatched)
			end
		end
	end
	return root
end

return FamilyTree
