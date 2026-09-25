--[[
	Icon: small currency/resource icons drawn with shapes (or Theme.Images when set).
	Kinds: coin · gem · food · treat · stardust · friendship · token · xp · egg · star · lock · trophy

		Icon.new("coin", 28)       -- returns a Frame (size × size)
]]

local Theme = require(script.Parent.Parent.Theme)
local Create = require(script.Parent.Parent.Create)

local New = Create.New
local C = Theme.Colors

local Icon = {}

local IMAGE_KEYS =
	{ coin = "Coin", gem = "Gem", food = "Food", treat = "Treat", stardust = "Stardust", friendship = "Friendship", token = "Token" }

local function glyph(parent, text: string, color: Color3, scale: number?)
	return Create.Text({
		Text = text,
		TextColor3 = color,
		TextScaled = true,
		Size = UDim2.fromScale(scale or 0.7, scale or 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Stroke = false,
		Parent = parent,
	})
end

function Icon.new(kind: string, size: number?): Frame
	local px = size or 26
	local frame = New("Frame", {
		Name = "Icon_" .. kind,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(px, px),
	})
	local imageKey = IMAGE_KEYS[kind]
	if imageKey and Theme.Images[imageKey] ~= "" then
		New("ImageLabel", {
			BackgroundTransparency = 1,
			Image = Theme.Images[imageKey],
			Size = UDim2.fromScale(1, 1),
			Parent = frame,
		})
		return frame
	end

	local function disc(color: Color3, inner: Color3?)
		local d = New("Frame", {
			BackgroundColor3 = color,
			Size = UDim2.fromScale(1, 1),
			Parent = frame,
		}, { Create.Round(), Create.Stroke(math.max(1.5, px / 14)) })
		if inner then
			New("Frame", {
				BackgroundColor3 = inner,
				Size = UDim2.fromScale(0.55, 0.55),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 0.25,
				Parent = d,
			}, { Create.Round() })
		end
		return d
	end

	if kind == "coin" then
		local d = disc(C.Coin)
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(Color3.fromHex("#FFF0B0"), Color3.fromHex("#C58508"))
		g.Rotation = 60
		g.Parent = d
		glyph(d, "$", Color3.fromHex("#8A5A00"), 0.62)
	elseif kind == "gem" then
		local d = New("Frame", {
			BackgroundColor3 = C.Gem,
			Size = UDim2.fromScale(0.72, 0.72),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = 45,
			Parent = frame,
		}, { Create.Corner(px / 6), Create.Stroke(math.max(1.5, px / 14)) })
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(Color3.fromHex("#FFB2DA"), C.Gem)
		g.Parent = d
	elseif kind == "food" then
		local d = disc(C.Food)
		New("Frame", {
			BackgroundColor3 = C.Green,
			Size = UDim2.fromScale(0.4, 0.25),
			Position = UDim2.fromScale(0.55, -0.05),
			Rotation = -25,
			Parent = d,
		}, { Create.Round() })
	elseif kind == "treat" then
		New("Frame", {
			BackgroundColor3 = C.Treat,
			Size = UDim2.fromScale(1, 0.62),
			Position = UDim2.fromScale(0, 0.19),
			Parent = frame,
		}, { Create.Corner(px / 3), Create.Stroke(math.max(1.5, px / 14)) })
	elseif kind == "stardust" then
		local d = disc(C.Stardust)
		glyph(d, "✦", C.White, 0.7)
	elseif kind == "friendship" then
		local d = disc(C.Friendship)
		glyph(d, "♥", C.White, 0.62)
	elseif kind == "token" then
		local d = disc(C.Token)
		glyph(d, "❄", C.White, 0.7)
	elseif kind == "xp" then
		local d = disc(C.Xp)
		glyph(d, "XP", C.White, 0.6)
	elseif kind == "star" then
		glyph(frame, "★", C.Gold, 1)
	elseif kind == "trophy" then
		-- Cup, handles and base drawn from rounded frames.
		local stroke = math.max(1.5, px / 14)
		New("Frame", {
			BackgroundColor3 = C.Gold,
			Size = UDim2.fromScale(0.6, 0.5),
			Position = UDim2.fromScale(0.2, 0.08),
			Parent = frame,
		}, { Create.Corner(UDim.new(0.35, 0)), Create.Stroke(stroke) })
		for _, x in { 0.08, 0.72 } do
			New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(0.2, 0.26),
				Position = UDim2.fromScale(x, 0.14),
				Parent = frame,
			}, { Create.Round(), Create.Stroke(stroke, C.Gold) })
		end
		New("Frame", {
			BackgroundColor3 = C.Gold,
			Size = UDim2.fromScale(0.14, 0.2),
			Position = UDim2.fromScale(0.43, 0.56),
			Parent = frame,
		})
		New("Frame", {
			BackgroundColor3 = Color3.fromHex("#C58508"),
			Size = UDim2.fromScale(0.5, 0.16),
			Position = UDim2.fromScale(0.25, 0.76),
			Parent = frame,
		}, { Create.Corner(px / 10), Create.Stroke(stroke) })
	elseif kind == "lock" then
		local d = disc(C.Gray)
		glyph(d, "🔒", C.White, 0.6)
	elseif kind == "egg" then
		New("Frame", {
			BackgroundColor3 = Color3.fromHex("#C9EDA8"),
			Size = UDim2.fromScale(0.78, 1),
			Position = UDim2.fromScale(0.11, 0),
			Parent = frame,
		}, { Create.Corner(UDim.new(0.5, 0)), Create.Stroke(math.max(1.5, px / 14)) })
	else
		disc(C.Gray)
	end
	return frame
end

-- Icon kind for a Reward item.
function Icon.forReward(kind: string): string
	if kind == "egg" or kind == "monster" or kind == "decor" then
		return "egg"
	end
	return kind
end

return Icon
