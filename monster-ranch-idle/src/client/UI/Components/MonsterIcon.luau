--[[
	MonsterIcon / EggIcon: 2D placeholder portraits built from frames, so lists of hundreds
	of monsters stay cheap (no ViewportFrames). Everything is sized in Scale, so an icon
	works at any size.

		MonsterIcon.new(appearance, 96)    -- Appearance from Logic/Appearance
		MonsterIcon.egg("crystal", 64)
		MonsterIcon.silhouette(lineId, 64) -- undiscovered Codex / hybrid preview

	Replace with image-based portraits later by filling `MonsterIcon.Portraits[formId]`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Parent.Theme)
local Create = require(script.Parent.Parent.Create)

local New = Create.New
local INK = Theme.Colors.Ink

local MonsterIcon = {}

-- formId -> "rbxassetid://..." once portraits exist.
MonsterIcon.Portraits = {}

local function blob(parent, color: Color3, pos: Vector2, size: Vector2, stroke: boolean?, z: number?, rotation: number?)
	local f = New("Frame", {
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(pos.X, pos.Y),
		Size = UDim2.fromScale(size.X, size.Y),
		ZIndex = z or 2,
		Rotation = rotation or 0,
		Parent = parent,
	}, { Create.Round() })
	if stroke ~= false then
		local s = Create.Stroke(2)
		s.Parent = f
	end
	return f
end

local function rainbow(frame: GuiObject)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("#FF7A7A")),
		ColorSequenceKeypoint.new(0.28, Color3.fromHex("#FFD35A")),
		ColorSequenceKeypoint.new(0.52, Color3.fromHex("#7BE07B")),
		ColorSequenceKeypoint.new(0.76, Color3.fromHex("#6BB8FF")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("#C17BFF")),
	})
	g.Rotation = 45
	g.Parent = frame
end

local function feature(parent, element: string, archetype: string, body: Color3, accent: Color3)
	-- Archetype silhouette extras (behind the body: ZIndex 1).
	if archetype == "fox" then
		blob(parent, body, Vector2.new(0.3, 0.2), Vector2.new(0.2, 0.3), true, 1, -20)
		blob(parent, body, Vector2.new(0.7, 0.2), Vector2.new(0.2, 0.3), true, 1, 20)
	elseif archetype == "bunny" then
		blob(parent, body, Vector2.new(0.36, 0.14), Vector2.new(0.14, 0.4), true, 1, -8)
		blob(parent, body, Vector2.new(0.64, 0.14), Vector2.new(0.14, 0.4), true, 1, 8)
	elseif archetype == "moth" or archetype == "bug" then
		local wing = if archetype == "bug" then Color3.fromHex("#DFF3FF") else accent
		blob(parent, wing, Vector2.new(0.14, 0.45), Vector2.new(0.3, 0.42), true, 1, -25)
		blob(parent, wing, Vector2.new(0.86, 0.45), Vector2.new(0.3, 0.42), true, 1, 25)
	elseif archetype == "golem" then
		blob(parent, accent, Vector2.new(0.2, 0.42), Vector2.new(0.2, 0.2), true, 1)
		blob(parent, accent, Vector2.new(0.8, 0.42), Vector2.new(0.2, 0.2), true, 1)
	elseif archetype == "sprite" then
		blob(parent, accent, Vector2.new(0.5, 0.95), Vector2.new(0.3, 0.14), false, 1)
	elseif archetype == "slug" then
		blob(parent, body, Vector2.new(0.38, 0.14), Vector2.new(0.07, 0.24), true, 1)
		blob(parent, body, Vector2.new(0.62, 0.14), Vector2.new(0.07, 0.24), true, 1)
	end
	-- Element accent on top (ZIndex 4).
	if element == "ember" then
		blob(parent, accent, Vector2.new(0.5, 0.1), Vector2.new(0.18, 0.22), true, 4, 45)
	elseif element == "tide" then
		blob(parent, accent, Vector2.new(0.1, 0.62), Vector2.new(0.16, 0.12), true, 1, -30)
		blob(parent, accent, Vector2.new(0.9, 0.62), Vector2.new(0.16, 0.12), true, 1, 30)
	elseif element == "sprout" then
		blob(parent, accent, Vector2.new(0.42, 0.1), Vector2.new(0.2, 0.1), true, 4, -30)
		blob(parent, accent, Vector2.new(0.58, 0.1), Vector2.new(0.2, 0.1), true, 4, 30)
	elseif element == "spark" then
		blob(parent, accent, Vector2.new(0.3, 0.12), Vector2.new(0.08, 0.26), true, 4, -25)
		blob(parent, accent, Vector2.new(0.7, 0.12), Vector2.new(0.08, 0.26), true, 4, 25)
	elseif element == "stone" then
		blob(parent, accent, Vector2.new(0.33, 0.16), Vector2.new(0.1, 0.2), true, 4, -20)
		blob(parent, accent, Vector2.new(0.67, 0.16), Vector2.new(0.1, 0.2), true, 4, 20)
	elseif element == "gloom" then
		blob(parent, accent, Vector2.new(0.28, 0.16), Vector2.new(0.14, 0.14), false, 4)
		blob(parent, accent, Vector2.new(0.72, 0.16), Vector2.new(0.14, 0.14), false, 4)
	end
end

function MonsterIcon.new(appearance, size: number?): Frame
	local px = size or 80
	local root = New("Frame", {
		Name = "MonsterIcon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(px, px),
	})
	local portrait = MonsterIcon.Portraits[appearance.form]
	if portrait then
		New("ImageLabel", { BackgroundTransparency = 1, Image = portrait, Size = UDim2.fromScale(1, 1), Parent = root })
		return root
	end

	local element = appearance.elements and appearance.elements[1] or "sprout"
	local def = Config.Elements.ById[element]
	local body = Color3.fromHex(def.color)
	local belly = Color3.fromHex(def.light)
	local accent = Color3.fromHex(def.accent)
	if appearance.variant == 1 then
		body, belly, accent = Color3.fromHex("#F4C43A"), Color3.fromHex("#FFF1B3"), Color3.fromHex("#FFE38A")
	end
	for _, m in appearance.muts or {} do
		if m == "shadow" then
			body, belly = Color3.fromHex("#3A2D55"), Color3.fromHex("#6B5A8E")
		end
	end
	-- Babies are rounder and smaller; adults fill the frame.
	local stageScale = ({ 0.78, 0.88, 1 })[appearance.stage or 1] or 1

	local holder = New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(stageScale, stageScale),
		Parent = root,
	})
	feature(holder, element, appearance.archetype or "blob", body, accent)
	local wide = appearance.archetype == "slug" or appearance.archetype == "golem"
	local bodyFrame = blob(holder, body, Vector2.new(0.5, 0.6), Vector2.new(if wide then 0.86 else 0.76, 0.72), true, 2)
	if appearance.variant == 2 then
		rainbow(bodyFrame)
	end
	blob(holder, belly, Vector2.new(0.5, 0.72), Vector2.new(0.42, 0.3), false, 3)
	-- Eyes
	for _, x in { 0.38, 0.62 } do
		local eye = blob(holder, Color3.new(1, 1, 1), Vector2.new(x, 0.5), Vector2.new(0.15, 0.18), true, 5)
		blob(eye, INK, Vector2.new(0.55, 0.58), Vector2.new(0.55, 0.55), false, 6)
		blob(eye, Color3.new(1, 1, 1), Vector2.new(0.38, 0.35), Vector2.new(0.22, 0.22), false, 7)
	end
	blob(holder, Color3.fromHex("#FF8FA3"), Vector2.new(0.27, 0.64), Vector2.new(0.1, 0.06), false, 5).BackgroundTransparency = 0.3
	blob(holder, Color3.fromHex("#FF8FA3"), Vector2.new(0.73, 0.64), Vector2.new(0.1, 0.06), false, 5).BackgroundTransparency = 0.3

	-- Mutation dots (top right).
	for i, m in appearance.muts or {} do
		blob(root, Theme.Mutation(m), Vector2.new(0.92 - (i - 1) * 0.15, 0.1), Vector2.new(0.14, 0.14), true, 8)
	end
	return root
end

function MonsterIcon.silhouette(lineId: string, size: number?): Frame
	local def = Config.Species.ById[lineId]
	local ap = {
		elements = def and def.elements or { "gloom" },
		archetype = def and def.archetype or "blob",
		stage = 1,
		variant = 0,
		muts = {},
	}
	local icon = MonsterIcon.new(ap, size)
	for _, d in icon:GetDescendants() do
		if d:IsA("Frame") then
			d.BackgroundColor3 = Color3.fromHex("#3B3350")
		end
	end
	return icon
end

function MonsterIcon.egg(eggType: string, size: number?): Frame
	local px = size or 64
	local def = Config.Eggs.ById[eggType]
	local shell = Color3.fromHex(def and def.colors.shell or "#C9EDA8")
	local spots = Color3.fromHex(def and def.colors.spots or "#79C455")
	local root = New("Frame", {
		Name = "EggIcon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(px, px),
	})
	local egg = New("Frame", {
		BackgroundColor3 = shell,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.74, 0.94),
		ClipsDescendants = false,
		Parent = root,
	}, { Create.Corner(UDim.new(0.5, 0)), Create.Stroke(2.5) })
	local pattern = def and def.pattern or "spots"
	if pattern == "band" then
		New(
			"Frame",
			{
				BackgroundColor3 = spots,
				Position = UDim2.fromScale(0, 0.55),
				Size = UDim2.fromScale(1, 0.12),
				BorderSizePixel = 0,
				Parent = egg,
			}
		)
	elseif pattern == "stars" then
		for _, p in { Vector2.new(0.35, 0.35), Vector2.new(0.65, 0.6), Vector2.new(0.45, 0.78) } do
			Create.Text({
				Text = "✦",
				TextColor3 = spots,
				TextScaled = true,
				Stroke = false,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(p.X, p.Y),
				Size = UDim2.fromScale(0.28, 0.2),
				Parent = egg,
			})
		end
	elseif pattern == "snowflake" then
		Create.Text({
			Text = "❄",
			TextColor3 = spots,
			TextScaled = true,
			Stroke = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.55),
			Size = UDim2.fromScale(0.6, 0.4),
			Parent = egg,
		})
	elseif pattern == "facets" then
		for _, p in { Vector2.new(0.35, 0.35), Vector2.new(0.62, 0.62) } do
			New(
				"Frame",
				{
					BackgroundColor3 = spots,
					BackgroundTransparency = 0.2,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(p.X, p.Y),
					Size = UDim2.fromScale(0.18, 0.24),
					Rotation = 30,
					Parent = egg,
				}
			)
		end
	else
		for _, p in { Vector2.new(0.35, 0.38), Vector2.new(0.66, 0.6), Vector2.new(0.4, 0.76), Vector2.new(0.64, 0.28) } do
			blob(egg, spots, p, Vector2.new(0.18, 0.14), false, 3)
		end
	end
	-- Highlight
	blob(egg, Color3.new(1, 1, 1), Vector2.new(0.3, 0.22), Vector2.new(0.14, 0.1), false, 4).BackgroundTransparency = 0.35
	return root
end

-- A square card with rarity border, icon, and optional footer text. Used in grids.
function MonsterIcon.card(appearance, size: number, footer: string?): Frame
	local card = New("Frame", {
		Name = "MonsterCard",
		BackgroundColor3 = Theme.Colors.Card,
		Size = UDim2.fromOffset(size, size + (if footer then 22 else 0)),
	}, { Create.Corner(Theme.Radius.Card), Create.Stroke(3, Theme.Rarity(appearance.rarity or 1)) })
	local icon = MonsterIcon.new(appearance, size - 14)
	icon.Position = UDim2.fromOffset(7, 5)
	icon.Parent = card
	if footer then
		Create.Text({
			Text = footer,
			TextColor3 = Theme.Colors.Text,
			Stroke = false,
			TextSize = Theme.TextSize.Tiny + 1,
			Position = UDim2.new(0, 4, 1, -24),
			Size = UDim2.new(1, -8, 0, 20),
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Parent = card,
		})
	end
	return card
end

return MonsterIcon
