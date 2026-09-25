--[[
	Clubs screen (update 1.2). Reads session.Clubs.club (the ClubView built by the Clubs
	server system), global.Clubs.here (club tags of players on this server) and the
	player's level.

	No club: "Start a club" (name, tag, colour, emblem, open/invite only → Clubs.Create) and
	"Join a club" (code → Clubs.Join, or an open club of someone here → Clubs.JoinPlayer).
	In a club: header (emblem, name, tag, code, members) and four tabs:
	  Members   roles, weekly points, who is here; officers kick, the owner promotes
	  Goals     this week's goals with progress and Clubs.ClaimGoal
	  Boss      the weekly club boss: Clubs.AttackBoss (daily attacks) and Clubs.ClaimBoss
	  Settings  open / invite only, colour, emblem (officers+), leave the club
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Logic.Format)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)
local Dialog = require(script.Parent.Parts.Dialog)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Clubs

local Clubs = { Name = "Clubs" }

local ROLE_TEXT = { owner = "Owner", officer = "Officer", member = "Member" }
local ROLE_RANK = { owner = 3, officer = 2, member = 1 }
local TEAL = Color3.fromHex("#2BA89A")

local function colorOf(index: number?): Color3
	return Color3.fromHex(Cfg.Colors[index or 1] or Cfg.Colors[1])
end

local function glyphOf(emblem: string?): string
	local e = emblem and Cfg.EmblemById[emblem]
	return if e then e.glyph else "★"
end

-- A round badge with the club's emblem in its colour.
local function emblemBadge(parent: Instance, color: Color3, glyph: string, size: number, props)
	local badge = New("Frame", {
		Name = "Emblem",
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	}, { Create.Round(), Create.Stroke(3) })
	for k, v in props or {} do
		(badge :: any)[k] = v
	end
	Create.Text({
		Text = glyph,
		TextScaled = true,
		Size = UDim2.fromScale(0.62, 0.62),
		Position = UDim2.fromScale(0.19, 0.19),
		Parent = badge,
	})
	return badge
end

local function textBox(props)
	return New("TextBox", {
		Name = props.Name,
		Text = "",
		PlaceholderText = props.Placeholder,
		ClearTextOnFocus = false,
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Body,
		TextColor3 = C.Text,
		PlaceholderColor3 = C.TextMuted,
		BackgroundColor3 = C.Card,
		Size = props.Size,
		Position = props.Position,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { Create.Corner(Theme.Radius.Button), Create.Stroke(Theme.Stroke.Button), Create.Padding(0, 12, 0, 12) })
end

function Clubs.Build(ctx)
	local store = ctx.Store
	local panel = Panel.new({
		Title = "Clubs",
		Color = TEAL,
		Size = UDim2.fromOffset(920, 500),
		OnClose = function()
			ctx.Router:Close("Clubs")
		end,
	})
	local body = panel.Body
	local render

	local function clubView()
		local s = store:Get("session.Clubs")
		return if type(s) == "table" and type(s.club) == "table" then s.club else nil
	end

	-- ─── No club ──────────────────────────────────────────────────────────────────────
	local noClub = New("Frame", { Name = "NoClub", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = body })

	local startCard = Util.card({ Title = "Start a club", Size = UDim2.new(0.5, -6, 1, 0), Parent = noClub })
	local nameBox = textBox({
		Name = "ClubName",
		Placeholder = string.format("Club name (%d–%d letters)", Cfg.NameLength[1], Cfg.NameLength[2]),
		Position = UDim2.fromOffset(14, 44),
		Size = UDim2.new(1, -28, 0, 46),
		Parent = startCard,
	})
	local tagBox = textBox({
		Name = "ClubTag",
		Placeholder = string.format("Tag (%d–%d)", Cfg.TagLength[1], Cfg.TagLength[2]),
		Position = UDim2.fromOffset(14, 98),
		Size = UDim2.fromOffset(150, 46),
		Parent = startCard,
	})
	tagBox:GetPropertyChangedSignal("Text"):Connect(function()
		local cleaned = string.upper(string.gsub(tagBox.Text, "[^%w]", ""))
		cleaned = string.sub(cleaned, 1, Cfg.TagLength[2])
		if cleaned ~= tagBox.Text then
			tagBox.Text = cleaned
		end
	end)
	nameBox:GetPropertyChangedSignal("Text"):Connect(function()
		if #nameBox.Text > Cfg.NameLength[2] * 2 then
			nameBox.Text = StoreKit.clip(nameBox.Text, Cfg.NameLength[2] * 2)
		end
	end)

	local pick = { color = 1, emblem = Cfg.Emblems[1].id, open = true }
	local colorRow = New("Frame", {
		Name = "Colors",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 154),
		Size = UDim2.new(1, -28, 0, 40),
		Parent = startCard,
	}, { Create.List("x", 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	local emblemRow = New("Frame", {
		Name = "Emblems",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 200),
		Size = UDim2.new(1, -28, 0, 44),
		Parent = startCard,
	}, { Create.List("x", 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })

	-- Swatch rows shared by "Start a club" and Settings: fn(value) is called on tap.
	local function drawSwatches(colorParent, emblemParent, current, onColor, onEmblem)
		Util.clear(colorParent)
		Util.clear(emblemParent)
		for i, hex in Cfg.Colors do
			local swatch = New("TextButton", {
				Name = "Color" .. i,
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = Color3.fromHex(hex),
				Size = UDim2.fromOffset(34, 34),
				LayoutOrder = i,
				Parent = colorParent,
			}, { Create.Round(), Create.Stroke(if current.color == i then 4 else 2, if current.color == i then C.Gold else C.Ink) })
			swatch.Activated:Connect(function()
				onColor(i)
			end)
		end
		for i, e in Cfg.Emblems do
			local chosen = current.emblem == e.id
			local b = New("TextButton", {
				Name = "Emblem_" .. e.id,
				Text = e.glyph,
				TextScaled = true,
				AutoButtonColor = false,
				BackgroundColor3 = if chosen then colorOf(current.color) else C.PanelDeep,
				Size = UDim2.fromOffset(38, 38),
				LayoutOrder = i,
				Parent = emblemParent,
			}, { Create.Corner(10), Create.Stroke(if chosen then 3 else 2, if chosen then C.Gold else C.Ink) })
			b.Activated:Connect(function()
				onEmblem(e.id)
			end)
		end
	end

	local openButton = Button.new({
		Name = "OpenToggle",
		Text = "",
		Color = C.Blue,
		Size = UDim2.fromOffset(200, 44),
		TextSize = Theme.TextSize.Small + 1,
		Position = UDim2.fromOffset(14, 254),
		Parent = startCard,
	})
	openButton:SetOnClick(function()
		pick.open = not pick.open
		render()
	end)
	Util.text({
		Text = "Open clubs can be joined by anyone on your server. Invite-only clubs need the code.",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(224, 250),
		Size = UDim2.new(1, -238, 0, 52),
		Parent = startCard,
	})
	local createButton = Button.new({
		Name = "Create",
		Text = "Create · " .. Format.short(Cfg.CreateCost.coins or 0) .. " coins",
		Color = C.Green,
		Size = UDim2.new(1, -28, 0, 52),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Parent = startCard,
	})
	createButton:SetOnClick(function()
		local ok = Util.requestOnce(ctx, "Clubs.Create", {
			name = nameBox.Text,
			tag = tagBox.Text,
			color = pick.color,
			emblem = pick.emblem,
			open = pick.open,
		})
		if ok then
			ctx:Toast("Your club is ready! Share its code with friends.", "success")
			ctx:Sound("Victory")
		end
	end)

	local joinCard = Util.card({
		Title = "Join a club",
		Position = UDim2.new(0.5, 6, 0, 0),
		Size = UDim2.new(0.5, -6, 1, 0),
		Parent = noClub,
	})
	local codeBox = textBox({
		Name = "ClubCode",
		Placeholder = "Club code",
		Position = UDim2.fromOffset(14, 44),
		Size = UDim2.new(1, -150, 0, 46),
		Parent = joinCard,
	})
	codeBox:GetPropertyChangedSignal("Text"):Connect(function()
		local cleaned = string.sub(string.upper(string.gsub(codeBox.Text, "[^%w]", "")), 1, Cfg.CodeLength)
		if cleaned ~= codeBox.Text then
			codeBox.Text = cleaned
		end
	end)
	Button.new({
		Name = "JoinCode",
		Text = "Join",
		Color = C.Green,
		Size = UDim2.fromOffset(120, 46),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 44),
		Parent = joinCard,
		OnClick = function()
			local ok, res = Util.requestOnce(ctx, "Clubs.Join", { code = codeBox.Text })
			if ok and type(res) == "table" then
				ctx:Toast("Welcome to " .. tostring(res.name) .. "!", "success")
			end
		end,
	})
	Util.text({
		Text = "Clubs on this server",
		Font = Theme.Fonts.Display,
		Position = UDim2.fromOffset(14, 102),
		Size = UDim2.new(1, -28, 0, 26),
		Parent = joinCard,
	})
	local hereList = Widgets.List({ Position = UDim2.fromOffset(4, 132), Size = UDim2.new(1, -8, 1, -136), Padding = 6, Parent = joinCard })

	local function drawHere()
		Util.clear(hereList)
		local here = store:Get("global.Clubs.here")
		local byClub = {}
		for key, info in (if type(here) == "table" then here else {}) do
			local userId = tonumber(string.sub(key, 2))
			if type(info) == "table" and userId and userId ~= ctx.Player.UserId then
				local entry = byClub[info.clubId]
				if not entry then
					entry = { info = info, userIds = {} }
					byClub[info.clubId] = entry
				end
				table.insert(entry.userIds, userId)
			end
		end
		local order = 0
		for _, entry in byClub do
			order += 1
			local info = entry.info
			local row = Util.card({ Size = UDim2.new(1, -8, 0, 56), LayoutOrder = order, Parent = hereList })
			emblemBadge(row, colorOf(info.color), glyphOf(info.emblem), 40, { Position = UDim2.fromOffset(8, 8) })
			Util.text({
				Text = string.format("[%s] %s", tostring(info.tag), tostring(info.name)),
				Font = Theme.Fonts.Display,
				Position = UDim2.fromOffset(56, 4),
				Size = UDim2.new(1, -190, 0, 26),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Parent = row,
			})
			Util.text({
				Text = string.format("%d here · %s", #entry.userIds, if info.open then "open" else "invite only"),
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
				Position = UDim2.fromOffset(56, 28),
				Size = UDim2.new(1, -190, 0, 22),
				Parent = row,
			})
			if info.open then
				Button.new({
					Name = "JoinHere",
					Text = "Join",
					Color = C.Green,
					Size = UDim2.fromOffset(110, 40),
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					TextSize = Theme.TextSize.Small + 1,
					Parent = row,
					OnClick = function()
						local ok, res = Util.requestOnce(ctx, "Clubs.JoinPlayer", { userId = entry.userIds[1] })
						if ok and type(res) == "table" then
							ctx:Toast("Welcome to " .. tostring(res.name) .. "!", "success")
						end
					end,
				})
			end
		end
		if order == 0 then
			Util.text({
				Text = "Nobody here is in a club yet. Start one, or ask a friend for their code.",
				TextColor3 = C.TextMuted,
				Size = UDim2.new(1, -8, 0, 48),
				Parent = hereList,
			})
		end
	end

	-- ─── In a club ────────────────────────────────────────────────────────────────────
	local inClub =
		New("Frame", { Name = "InClub", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = body })
	local header = Util.card({ Name = "Header", Size = UDim2.new(1, 0, 0, 64), Parent = inClub })
	local headerBadge = nil
	local clubName = Util.text({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Header,
		Position = UDim2.fromOffset(70, 4),
		Size = UDim2.new(1, -90, 0, 30),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Parent = header,
	})
	local clubInfo = Util.text({
		Text = "",
		TextSize = Theme.TextSize.Small + 1,
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(70, 34),
		Size = UDim2.new(1, -90, 0, 24),
		Parent = header,
	})

	local tab = "members"
	local tabs = Widgets.Tabs({
		Tabs = {
			{ id = "members", text = "Members", width = 140 },
			{ id = "goals", text = "Goals", width = 140 },
			{ id = "boss", text = "Club boss", width = 140 },
			{ id = "wars", text = "Club Wars", width = 140 },
			{ id = "settings", text = "Settings", width = 140 },
		},
		Selected = tab,
		Position = UDim2.fromOffset(0, 72),
		Parent = inClub,
		OnChanged = function(id)
			tab = id
			render()
		end,
	})
	local page = New("Frame", {
		Name = "Page",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 124),
		Size = UDim2.new(1, 0, 1, -124),
		Parent = inClub,
	})

	local function rewardLine(items): string
		local parts = {}
		for _, item in items or {} do
			table.insert(parts, Util.rewardText(item))
		end
		return table.concat(parts, " + ")
	end

	local function drawMembers(v)
		local list = Widgets.List({ Size = UDim2.fromScale(1, 1), Padding = 6, Parent = page })
		local myRank = ROLE_RANK[v.myRole] or 1
		for i, m in v.members do
			local isMe = m.userId == ctx.Player.UserId
			local row = New("Frame", {
				Name = "Member" .. m.userId,
				BackgroundColor3 = if isMe then Color3.fromHex("#FFE9A8") else C.Card,
				Size = UDim2.new(1, -8, 0, 48),
				LayoutOrder = i,
				Parent = list,
			}, { Create.Corner(10), Create.Stroke(2, C.Line, 0.3) })
			New("Frame", {
				Name = "Here",
				BackgroundColor3 = if m.here then C.Green else C.Gray,
				Size = UDim2.fromOffset(12, 12),
				Position = UDim2.fromOffset(12, 18),
				Parent = row,
			}, { Create.Round() })
			local chip = Widgets.Chip({
				Text = string.upper(ROLE_TEXT[m.role] or m.role),
				Color = if m.role == "owner" then C.Orange elseif m.role == "officer" then C.Blue else C.Gray,
				Parent = row,
			})
			chip.Position = UDim2.fromOffset(32, 12)
			Util.text({
				Text = string.format("%s  ·  %s pts", if isMe then "You" else tostring(m.name), Format.short(math.floor(m.points or 0))),
				Font = if isMe then Theme.Fonts.Display else Theme.Fonts.Body,
				Position = UDim2.fromOffset(130, 0),
				Size = UDim2.new(1, -440, 1, 0),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Parent = row,
			})
			local actions = New("Frame", {
				Name = "Actions",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(300, 40),
				Parent = row,
			}, { Create.List("x", 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
			local theirRank = ROLE_RANK[m.role] or 1
			local function action(text: string, color: Color3, order: number, fn)
				Button.new({
					Text = text,
					Color = color,
					Size = UDim2.fromOffset(94, 36),
					TextSize = Theme.TextSize.Small,
					LayoutOrder = order,
					Parent = actions,
					OnClick = fn,
				})
			end
			if not isMe and v.myRole == "owner" then
				if m.role == "member" then
					action("Promote", C.Blue, 1, function()
						Util.requestOnce(ctx, "Clubs.SetRole", { userId = m.userId, role = "officer" })
					end)
				elseif m.role == "officer" then
					action("Demote", C.Gray, 1, function()
						Util.requestOnce(ctx, "Clubs.SetRole", { userId = m.userId, role = "member" })
					end)
					action("Make owner", C.Orange, 2, function()
						Dialog.confirm(ctx.UI.Top, {
							Title = "Hand over the club?",
							Text = string.format("%s becomes the owner and you become an officer.", tostring(m.name)),
							ConfirmText = "Hand over",
							ConfirmColor = C.Orange,
							OnConfirm = function()
								Util.requestOnce(ctx, "Clubs.SetRole", { userId = m.userId, role = "owner" })
							end,
						})
					end)
				end
			end
			if not isMe and myRank >= ROLE_RANK.officer and myRank > theirRank then
				action("Remove", C.Red, 3, function()
					Dialog.confirm(ctx.UI.Top, {
						Title = "Remove " .. tostring(m.name) .. "?",
						Text = "They can rejoin with the club code.",
						ConfirmText = "Remove",
						ConfirmColor = C.Red,
						OnConfirm = function()
							Util.requestOnce(ctx, "Clubs.Kick", { userId = m.userId })
						end,
					})
				end)
			end
		end
	end

	local function drawGoals(v)
		local list = Widgets.List({ Size = UDim2.new(1, 0, 1, -30), Padding = 8, Parent = page })
		for i, g in v.goals do
			local row = Util.card({ Name = "Goal_" .. g.id, Size = UDim2.new(1, -8, 0, 92), LayoutOrder = i, Parent = list })
			Util.text({
				Text = g.text,
				Font = Theme.Fonts.Display,
				Position = UDim2.fromOffset(14, 8),
				Size = UDim2.new(1, -200, 0, 26),
				Parent = row,
			})
			Widgets.Bar({
				Color = if g.done then C.Green else TEAL,
				Value = if g.target > 0 then g.progress / g.target else 0,
				Text = string.format("%s / %s", Format.short(g.progress), Format.short(g.target)),
				Position = UDim2.fromOffset(14, 40),
				Size = UDim2.new(1, -200, 0, 20),
				Parent = row,
			})
			Util.text({
				Text = "Reward: " .. rewardLine(Cfg.GoalRewards[g.index]),
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
				Position = UDim2.fromOffset(14, 64),
				Size = UDim2.new(1, -200, 0, 22),
				Parent = row,
			})
			local claim = Button.new({
				Name = "Claim",
				Text = if g.claimed then "Claimed ✓" elseif g.done then "Claim" else "In progress",
				Color = if g.done and not g.claimed then C.Green else C.Gray,
				Size = UDim2.fromOffset(160, 48),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Parent = row,
			})
			claim:SetDisabled(not g.done or g.claimed)
			claim:SetOnClick(function()
				local ok, res = Util.requestOnce(ctx, "Clubs.ClaimGoal", { goal = g.id })
				if ok and type(res) == "table" then
					ctx:Toast("+ " .. rewardLine(res.rewards), "reward")
				end
			end)
		end
		local countdown = Util.text({
			Text = "",
			TextSize = Theme.TextSize.Small + 1,
			TextColor3 = C.TextMuted,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 26),
			Parent = page,
		})
		Widgets.Countdown(countdown, function()
			return v.weekEndsAt
		end, function(left)
			return "New goals in " .. Format.duration(left) .. " · everyone in the club adds progress by playing"
		end)
	end

	local function drawBoss(v)
		local b = v.boss
		local card = Util.card({ Name = "Boss", Size = UDim2.new(0.6, -6, 1, 0), Parent = page })
		Util.text({
			Text = b.name,
			Font = Theme.Fonts.Display,
			TextSize = Theme.TextSize.Header,
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -28, 0, 32),
			Parent = card,
		})
		Widgets.Bar({
			Color = C.Red,
			Value = if b.maxHp > 0 then b.hp / b.maxHp else 0,
			Text = string.format("%s / %s HP", Format.short(b.hp), Format.short(b.maxHp)),
			Position = UDim2.fromOffset(14, 48),
			Size = UDim2.new(1, -28, 0, 26),
			Parent = card,
		})
		Util.text({
			Text = string.format("Your damage: %s · Attacks left today: %d", Format.short(b.myDamage), b.attacksLeft),
			Position = UDim2.fromOffset(14, 84),
			Size = UDim2.new(1, -28, 0, 26),
			Parent = card,
		})
		Util.text({
			Text = "Your squad attacks. Stronger squads hit harder, but everyone's hits count.",
			TextSize = Theme.TextSize.Small,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(14, 112),
			Size = UDim2.new(1, -28, 0, 44),
			Parent = card,
		})
		local attack = Button.new({
			Name = "Attack",
			Text = if b.defeated then "Defeated!" else "Attack",
			Color = C.Red,
			Size = UDim2.fromOffset(200, 54),
			Position = UDim2.fromOffset(14, 168),
			Parent = card,
		})
		attack:SetDisabled(b.defeated or b.attacksLeft <= 0)
		attack:SetOnClick(function()
			local ok, res = Util.requestOnce(ctx, "Clubs.AttackBoss")
			if ok and type(res) == "table" then
				ctx:Toast(string.format("Hit for %s damage!", Format.short(res.damage or 0)), "success")
				ctx:Sound("ButtonClick")
			end
		end)
		local claim = Button.new({
			Name = "ClaimBoss",
			Text = if b.claimed then "Claimed ✓" else "Claim reward",
			Color = C.Green,
			Size = UDim2.fromOffset(200, 54),
			Position = UDim2.fromOffset(226, 168),
			Parent = card,
		})
		claim:SetDisabled(not b.defeated or b.claimed or b.myDamage <= 0)
		claim:SetOnClick(function()
			local ok, res = Util.requestOnce(ctx, "Clubs.ClaimBoss")
			if ok and type(res) == "table" then
				ctx:Toast("+ " .. rewardLine(res.rewards), "reward")
			end
		end)
		Util.text({
			Text = "Reward for everyone who attacked: " .. rewardLine(Cfg.Boss.reward),
			TextSize = Theme.TextSize.Small,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(14, 232),
			Size = UDim2.new(1, -28, 0, 40),
			Parent = card,
		})
		local top = Util.card({ Title = "Top damage", Position = UDim2.new(0.6, 6, 0, 0), Size = UDim2.new(0.4, -6, 1, 0), Parent = page })
		for i, entry in b.top do
			Util.text({
				Text = string.format("%d. %s · %s", i, tostring(entry.name), Format.short(entry.damage)),
				Position = UDim2.fromOffset(14, 40 + (i - 1) * 30),
				Size = UDim2.new(1, -28, 0, 28),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Parent = top,
			})
		end
		if #b.top == 0 then
			Util.text({
				Text = "No hits yet this week.",
				TextColor3 = C.TextMuted,
				Position = UDim2.fromOffset(14, 40),
				Size = UDim2.new(1, -28, 0, 28),
				Parent = top,
			})
		end
	end

	-- Club Wars (update 3.1) -------------------------------------------------------------
	local function leagueOf(id: string)
		if id == "champion" then
			return Cfg.War.champion
		end
		for _, l in Cfg.War.leagues do
			if l.id == id then
				return l
			end
		end
		return Cfg.War.leagues[1]
	end

	local function drawWars(v)
		local w = v.war
		local card = Util.card({ Name = "Wars", Size = UDim2.new(0.6, -6, 1, 0), Parent = page })
		if not w or not w.open then
			Util.text({
				Text = string.format(
					"Club Wars start on %s. Win raids, race for the Racing Cup and finish Stampedes to score for your club.",
					Format.date(Cfg.War.startsAt)
				),
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromOffset(14, 14),
				Size = UDim2.new(1, -28, 0, 80),
				Parent = card,
			})
			return
		end
		local league = leagueOf(w.league)
		Util.text({
			Name = "League",
			Text = string.format("%s league · %s war points", league.name, Format.commas(w.points)),
			Font = Theme.Fonts.Display,
			TextSize = Theme.TextSize.Header,
			TextColor3 = Color3.fromHex(league.color),
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -28, 0, 34),
			Parent = card,
		})
		local nextLeague = if w.next then leagueOf(w.next.id) else nil
		Widgets.Bar({
			Color = Color3.fromHex(if nextLeague then nextLeague.color else league.color),
			Value = if nextLeague then math.clamp(w.points / nextLeague.min, 0, 1) else 1,
			Text = if nextLeague
				then string.format("%s / %s to %s", Format.commas(w.points), Format.commas(nextLeague.min), nextLeague.name)
				else "Top league!",
			Position = UDim2.fromOffset(14, 50),
			Size = UDim2.new(1, -28, 0, 26),
			Parent = card,
		})
		local sources = {}
		for _, src in Cfg.War.sources do
			table.insert(sources, "• " .. src.text)
		end
		Util.text({
			Text = string.format(
				"You scored %s this week (%d more today).\n%s",
				Format.commas(w.mine),
				w.todayLeft,
				table.concat(sources, "\n")
			),
			TextSize = Theme.TextSize.Small,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(14, 86),
			Size = UDim2.new(1, -28, 0, 100),
			Parent = card,
		})
		local last = w.last
		local lastLeague = if last then leagueOf(if last.champion then "champion" else last.league) else nil
		Util.text({
			Name = "LastWeek",
			Text = if last
				then string.format(
					"Last week: %s (%s points)\nReward: %s",
					lastLeague.name,
					Format.commas(last.points),
					rewardLine(lastLeague.reward)
				)
				else "Earn war points this week to share next week's reward.",
			TextSize = Theme.TextSize.Small,
			TextColor3 = C.TextMuted,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(14, 190),
			Size = UDim2.new(1, -250, 0, 50),
			Parent = card,
		})
		local claim = Button.new({
			Name = "ClaimWar",
			Text = if last and last.claimed then "Claimed ✓" else "Claim",
			Color = C.Green,
			Size = UDim2.fromOffset(200, 50),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 190),
			Parent = card,
		})
		claim:SetDisabled(not last or last.claimed)
		claim:SetOnClick(function()
			local ok, res = Util.requestOnce(ctx, "Clubs.ClaimWar")
			if ok and type(res) == "table" then
				ctx:Toast("+ " .. rewardLine(res.rewards), "reward")
			end
		end)

		local ladder = StoreKit.tbl(store, "global.Clubs.ladder")
		local board = Util.card({
			Name = "Ladder",
			Title = "This week's ladder",
			Position = UDim2.new(0.6, 6, 0, 0),
			Size = UDim2.new(0.4, -6, 1, 0),
			Parent = page,
		})
		local rows = if type(ladder.rows) == "table" then ladder.rows else {}
		for i, row in rows do
			local mine = row.clubId == v.id
			Util.text({
				Name = "Row" .. i,
				Text = string.format(
					"%d. [%s] %s · %s",
					row.rank or i,
					tostring(row.tag),
					tostring(row.name),
					Format.commas(row.points or 0)
				),
				Font = if mine then Theme.Fonts.Display else nil,
				TextColor3 = if mine then C.Green else nil,
				TextSize = Theme.TextSize.Small,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Position = UDim2.fromOffset(14, 40 + (i - 1) * 28),
				Size = UDim2.new(1, -28, 0, 26),
				Parent = board,
			})
		end
		if #rows == 0 then
			Util.text({
				Text = "No scores yet this week.",
				TextColor3 = C.TextMuted,
				Position = UDim2.fromOffset(14, 40),
				Size = UDim2.new(1, -28, 0, 28),
				Parent = board,
			})
		end
	end

	-- Banner (3.1): a Workshop design the officer owns.
	local function drawBanner(card, v, canEdit: boolean)
		local row = New("Frame", {
			Name = "Banner",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 170),
			Size = UDim2.new(1, -28, 0, 44),
			Parent = card,
		}, { Create.List("x", 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
		Util.text({
			Text = if v.banner then "Banner: " .. tostring(v.banner.name) else "Banner: none",
			TextSize = Theme.TextSize.Small,
			Size = UDim2.fromOffset(200, 40),
			LayoutOrder = 0,
			Parent = row,
		})
		if not canEdit then
			return
		end
		local copies = StoreKit.tbl(store, "profile.Workshop.copies")
		local ids = {}
		for id, copy in copies do
			if type(copy) == "table" then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		for i = 1, math.min(5, #ids) do
			local copy = copies[ids[i]]
			local b = New("TextButton", {
				Name = "Banner_" .. ids[i],
				Text = "",
				AutoButtonColor = true,
				BackgroundColor3 = Color3.fromHex(copy.color or "#FFFFFF"),
				Size = UDim2.fromOffset(40, 40),
				LayoutOrder = i,
				Parent = row,
			}, { Create.Round(), Create.Stroke(4, Color3.fromHex(copy.color2 or "#FFFFFF")) })
			b.MouseButton1Click:Connect(function()
				Util.requestOnce(ctx, "Clubs.SetBanner", { design = ids[i] })
			end)
		end
		if #ids == 0 then
			Util.text({
				Text = "Get designs in the Workshop to hang a banner.",
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
				Size = UDim2.fromOffset(360, 40),
				LayoutOrder = 1,
				Parent = row,
			})
		elseif v.banner then
			Button.new({
				Name = "ClearBanner",
				Text = "Remove",
				Color = C.Gray,
				TextSize = Theme.TextSize.Small,
				Size = UDim2.fromOffset(110, 40),
				LayoutOrder = 9,
				Parent = row,
				OnClick = function()
					Util.requestOnce(ctx, "Clubs.SetBanner", { design = "" })
				end,
			})
		end
	end

	local function drawSettings(v)
		local canEdit = ROLE_RANK[v.myRole] >= ROLE_RANK.officer
		local card = Util.card({ Name = "Settings", Size = UDim2.new(1, 0, 1, 0), Parent = page })
		local openToggle = Button.new({
			Name = "OpenToggle",
			Text = if v.open then "Open to everyone" else "Invite only",
			Color = if v.open then C.Green else C.Gray,
			Size = UDim2.fromOffset(220, 46),
			Position = UDim2.fromOffset(14, 12),
			Parent = card,
		})
		openToggle:SetDisabled(not canEdit)
		openToggle:SetOnClick(function()
			Util.requestOnce(ctx, "Clubs.Settings", { open = not v.open })
		end)
		local colors = New("Frame", {
			Name = "Colors",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 70),
			Size = UDim2.new(1, -28, 0, 40),
			Parent = card,
		}, { Create.List("x", 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
		local emblems = New("Frame", {
			Name = "Emblems",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 116),
			Size = UDim2.new(1, -28, 0, 44),
			Parent = card,
		}, { Create.List("x", 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
		drawBanner(card, v, canEdit)
		drawSwatches(colors, emblems, { color = v.color, emblem = v.emblem }, function(i)
			if canEdit then
				Util.requestOnce(ctx, "Clubs.Settings", { color = i })
			end
		end, function(id)
			if canEdit then
				Util.requestOnce(ctx, "Clubs.Settings", { emblem = id })
			end
		end)
		if not canEdit then
			Util.text({
				Text = "Only the owner and officers can change these.",
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
				Position = UDim2.fromOffset(246, 12),
				Size = UDim2.new(1, -260, 0, 46),
				Parent = card,
			})
		end
		Button.new({
			Name = "Leave",
			Text = "Leave club",
			Color = C.Red,
			Size = UDim2.fromOffset(200, 48),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 14, 1, -12),
			Parent = card,
			OnClick = function()
				Dialog.confirm(ctx.UI.Top, {
					Title = "Leave " .. tostring(v.name) .. "?",
					Text = if v.myRole == "owner" and v.count > 1
						then "The longest-serving officer (or member) becomes the owner."
						elseif v.count <= 1 then "You're the last member, so the club will close."
						else "You can rejoin later with the club code.",
					ConfirmText = "Leave",
					ConfirmColor = C.Red,
					OnConfirm = function()
						Util.requestOnce(ctx, "Clubs.Leave")
					end,
				})
			end,
		})
	end

	-- ─── Render ───────────────────────────────────────────────────────────────────────
	local lockOverlay = nil
	local isOpen = false

	function render()
		if not isOpen then
			return
		end
		if lockOverlay then
			lockOverlay:Destroy()
			lockOverlay = nil
		end
		local v = clubView()
		noClub.Visible = v == nil
		inClub.Visible = v ~= nil
		if not v then
			openButton:SetText(if pick.open then "Open to everyone" else "Invite only")
			openButton:SetColor(if pick.open then C.Green else C.Gray)
			drawSwatches(colorRow, emblemRow, pick, function(i)
				pick.color = i
				render()
			end, function(id)
				pick.emblem = id
				render()
			end)
			drawHere()
			if not Util.unlocked(ctx, Cfg.Unlock) then
				lockOverlay = Util.lockOverlay(body, Util.unlockText(Cfg.Unlock))
			end
			return
		end
		if headerBadge then
			headerBadge:Destroy()
		end
		headerBadge = emblemBadge(header, colorOf(v.color), glyphOf(v.emblem), 50, { Position = UDim2.fromOffset(8, 7) })
		local oldBanner = header:FindFirstChild("HeaderBanner")
		if oldBanner then
			oldBanner:Destroy()
		end
		if v.banner then
			-- Update 3.1: the club's Workshop banner.
			New("Frame", {
				Name = "HeaderBanner",
				BackgroundColor3 = Color3.fromHex(v.banner.color or "#FFFFFF"),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -16, 0.5, 0),
				Size = UDim2.fromOffset(44, 56),
				Parent = header,
			}, { Create.Corner(8), Create.Stroke(5, Color3.fromHex(v.banner.color2 or "#FFFFFF")) })
		end
		clubName.Text = string.format("[%s] %s", v.tag, v.name)
		clubInfo.Text = string.format("Code %s · %d / %d members · %s", v.id, v.count, v.max, if v.open then "open" else "invite only")
		Util.clear(page)
		if tab == "goals" then
			drawGoals(v)
		elseif tab == "boss" then
			drawBoss(v)
		elseif tab == "wars" then
			drawWars(v)
		elseif tab == "settings" then
			drawSettings(v)
		else
			drawMembers(v)
		end
	end
	local refresh = Util.debounce(render)

	local bag = Util.bag()
	return {
		Root = panel.Root,
		Open = function(params)
			isOpen = true
			if type(params) == "table" and params.tab then
				tab = params.tab
				tabs:Select(tab)
			end
			bag.clean()
			for _, path in { "session.Clubs", "global.Clubs", "profile.Progression.level", "profile.Workshop.copies" } do
				bag.add(store:Observe(path, refresh))
			end
			render()
		end,
		Close = function()
			isOpen = false
			bag.clean()
		end,
	}
end

return Clubs
