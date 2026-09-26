--[[
	Nameplates controller: a small BillboardGui above each player's character with
	  · their club tag and name (global.Clubs.here, update 1.2), in the club's colour (with its banner flag since 3.1), and
	  · their champion titles (global.Leaderboards.champions), e.g. "🏆 Master Collector",
	  · (3.3) their Mythic Ladder title and nameplate flourish (global.Mastery.here), and
	  · glow-up L: VIP Rancher owners (global.Monetization.vip) get their name in VIP gold, and
	    Roblox Premium members (global.Community.premium) a small Premium badge beside it.
	Players with none of these get no nameplate. Rebuilt when any of that state changes and when
	a character spawns.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)

local New = Create.New
local C = Theme.Colors

local PLATE_NAME = "Nameplate"

local Nameplates = {
	Name = "Nameplates",
	Dependencies = {},
}

local ctx
local plates = {} -- [Player] = BillboardGui

local function titlesFor(userId: number): { string }
	local list = {}
	local champions = ctx.Store:Get("global.Leaderboards.champions")
	if type(champions) ~= "table" then
		return list
	end
	for _, board in Config.Leaderboards.Boards do
		local champ = champions[board.id]
		if type(champ) == "table" and champ.userId == userId then
			table.insert(list, board.title)
		end
	end
	return list
end

-- 3.3: the Mythic Ladder title and nameplate flourish the player equipped (global.Mastery.here).
local function masteryFor(userId: number)
	local here = ctx.Store:Get("global.Mastery.here")
	local info = type(here) == "table" and here["u" .. tostring(userId)]
	if type(info) ~= "table" then
		return nil, nil
	end
	local items = Config.Mastery.ItemById
	local title = type(info.title) == "string" and items[info.title]
	local flourish = type(info.flourish) == "string" and items[info.flourish]
	return if title and title.kind == "title" then title else nil, if flourish and flourish.kind == "flourish" then flourish else nil
end

local function clubFor(userId: number)
	local here = ctx.Store:Get("global.Clubs.here")
	local info = type(here) == "table" and here["u" .. tostring(userId)]
	return if type(info) == "table" then info else nil
end

local function listed(path: string, userId: number): boolean
	local list = ctx.Store:Get(path)
	return type(list) == "table" and list["u" .. tostring(userId)] == true
end

local function update(player: Player)
	local titles = titlesFor(player.UserId)
	local masteryTitle, flourish = masteryFor(player.UserId)
	if masteryTitle then
		table.insert(titles, masteryTitle.name)
	end
	local club = clubFor(player.UserId)
	local vip = listed("global.Monetization.vip", player.UserId)
	local premium = listed("global.Community.premium", player.UserId)
	local character = player.Character
	local anchor = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	local plate = plates[player]
	if (#titles == 0 and not club and not flourish and not vip and not premium) or not anchor then
		if plate then
			plate:Destroy()
			plates[player] = nil
		end
		return
	end
	if not plate or plate.Parent ~= anchor then
		if plate then
			plate:Destroy()
		end
		plate = New("BillboardGui", {
			Name = PLATE_NAME,
			Size = UDim2.fromOffset(260, 76),
			StudsOffset = Vector3.new(0, 3.6, 0),
			MaxDistance = 90,
			LightInfluence = 0,
			Parent = anchor,
		}, { Create.List("y", 0, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom) })
		Create.Text({
			Name = "Club",
			Text = "",
			Font = Theme.Fonts.Display,
			TextScaled = true,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = 1,
			Parent = plate,
		})
		Create.Text({
			Name = "Title",
			Text = "",
			Font = Theme.Fonts.Display,
			TextScaled = true,
			TextColor3 = C.Gold,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = 2,
			Parent = plate,
		})
		local row = New("Frame", {
			Name = "NameRow",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = 0,
			Parent = plate,
		}, { Create.List("x", 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
		local nameLabel = Create.Text({
			Name = "PlayerName",
			Text = "",
			Font = Theme.Fonts.Display,
			TextScaled = true,
			Size = UDim2.new(0, 170, 1, 0),
			LayoutOrder = 1,
			Parent = row,
		})
		nameLabel:SetAttribute("Localize", false) -- a player's own name
		local badge = Create.Text({
			Name = "Badge",
			Text = Config.Community.Premium.badge,
			Font = Theme.Fonts.Display,
			TextScaled = true,
			TextColor3 = Color3.fromHex(Config.Community.Premium.badgeColor),
			Size = UDim2.new(0, 70, 0.8, 0),
			LayoutOrder = 2,
			Parent = row,
		})
		badge.Visible = false
		plates[player] = plate
	end
	local clubLabel, titleLabel = plate.Club, plate.Title
	local nameRow = plate.NameRow
	nameRow.Visible = vip or premium
	nameRow.PlayerName.Text = player.DisplayName
	nameRow.PlayerName.TextColor3 = if vip then Color3.fromHex(Config.Community.VipBalcony.nameColor) else C.White
	nameRow.Badge.Visible = premium
	clubLabel.Visible = club ~= nil
	if club then
		clubLabel.Text = string.format("[%s] %s", tostring(club.tag), tostring(club.name))
		clubLabel.TextColor3 = Color3.fromHex(Config.Clubs.Colors[club.color] or Config.Clubs.Colors[1])
	end
	-- Update 3.1: a club banner (Workshop design) shows as a small flag before the club name.
	local flag = clubLabel:FindFirstChild("Banner")
	local banner = club and type(club.banner) == "table" and club.banner
	if banner then
		if not flag then
			flag = New("Frame", {
				Name = "Banner",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(0, -2, 0.5, 0),
				Size = UDim2.fromOffset(14, 18),
				Parent = clubLabel,
			}, { Create.Corner(3), Create.Stroke(2) })
		end
		flag.BackgroundColor3 = Color3.fromHex(banner.color or "#FFFFFF")
		local stroke = flag:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Color3.fromHex(banner.color2 or "#FFFFFF")
		end
	elseif flag then
		flag:Destroy()
	end
	local glyph = if flourish then flourish.glyph else "🏆"
	titleLabel.Visible = #titles > 0 or flourish ~= nil
	titleLabel.Text = if #titles > 0 then glyph .. " " .. table.concat(titles, " · ") else glyph
	titleLabel.TextColor3 = if flourish then Color3.fromHex(flourish.color) else C.Gold
end

local function updateAll()
	for _, player in Players:GetPlayers() do
		update(player)
	end
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function()
		task.defer(update, player)
	end)
	update(player)
end

function Nameplates.Init(context)
	ctx = context
end

function Nameplates.Start()
	ctx.Store:Observe("global.Leaderboards.champions", updateAll)
	ctx.Store:Observe("global.Clubs.here", updateAll)
	ctx.Store:Observe("global.Mastery.here", updateAll)
	ctx.Store:Observe("global.Monetization.vip", updateAll)
	ctx.Store:Observe("global.Community.premium", updateAll)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local plate = plates[player]
		if plate then
			plate:Destroy()
		end
		plates[player] = nil
	end)
end

return Nameplates
