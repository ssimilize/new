--[[
	Raids screen (update 2.1): 4-player raid bosses on this server.

	Left: the raids (Config.Raids), each with its boss and an "Open lobby" button (pick up to
	Config.Raids.PerPlayer Adults → Raids.Open). A raid that hasn't opened shows its date and
	one above the player's level its unlock level instead (3.2: Config.Raids.IsOpen / UnlockFor);
	a lobby for a raid the player can't join shows the unlock level instead of Join. Right: lobbies on this server
	(global.Raids.lobbies): members and their power; Join (pick Adults → Raids.Join),
	Leave, and Start for the host (Raids.Launch). Every member sees the battle through
	the Raids.Result event in Parts/BattleReplay. Opened from the Raid Portal.

	Reads: global.Raids, session.Raids, profile.Raids, profile.Progression.level.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Appearance = require(Shared.Logic.Appearance)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)
local BattleReplay = require(script.Parent.Parts.BattleReplay)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Raids

return {
	Name = "Raids",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Raid Portal",
			Color = C.Purple,
			Size = UDim2.fromOffset(1000, 500),
			OnClose = function()
				ctx.Router:Close("Raids")
			end,
		})
		local todayLabel = Util.text({
			Text = "",
			Font = Theme.Fonts.Display,
			TextColor3 = C.White,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.fromOffset(260, 40),
			LayoutOrder = 1,
			Parent = panel.HeaderRight,
		})

		local isOpen = false
		local bag = Util.bag()
		local refresh

		local raidsCard = Util.card({ Title = "Raids", Size = UDim2.new(0, 400, 1, 0), Parent = panel.Body })
		local raidList =
			Widgets.List({ Position = UDim2.fromOffset(6, 38), Size = UDim2.new(1, -12, 1, -44), Padding = 8, Parent = raidsCard })
		local lobbyCard = Util.card({
			Title = "Lobbies on this server",
			Position = UDim2.fromOffset(410, 0),
			Size = UDim2.new(1, -410, 1, 0),
			Parent = panel.Body,
		})
		local lobbyList =
			Widgets.List({ Position = UDim2.fromOffset(6, 38), Size = UDim2.new(1, -12, 1, -44), Padding = 8, Parent = lobbyCard })

		local function myLobby(): string?
			local id = StoreKit.tbl(ctx.Store, "session.Raids").lobby
			return if type(id) == "string" then id else nil
		end

		local function pickTeam(title: string, onPick)
			Util.pick(ctx, {
				title = title,
				max = Cfg.PerPlayer,
				filter = function(m)
					return m.stage == 3 and not m.busy
				end,
				returnTo = "Raids",
				onPick = onPick,
			})
		end

		-- Every member sees the battle, whoever pressed Start.
		ctx.Net:On("Raids.Result", function(data)
			if type(data) ~= "table" then
				return
			end
			local raid = Cfg.ById[data.raid]
			BattleReplay.play(ctx, {
				replay = data.replay,
				win = data.win,
				rewards = data.rewards,
				title = if raid then string.format("Raid · %s", raid.name) else "Raid",
				winText = "The raid boss falls!",
				loseText = "The raid boss held on. Try again!",
			})
		end)

		-- Three raid cards fit the list without scrolling (update 3.2). A raid that hasn't
		-- opened shows its date, one above the player's level shows its unlock level, in
		-- place of the Open lobby button.
		local CARD_H = 110
		local function gateText(raid): string?
			if not Cfg.IsOpen(raid, ctx:Now()) then
				return string.format("Opens on %s", Format.date(raid.opensAt))
			end
			local key = Cfg.UnlockFor(raid)
			if key ~= Cfg.Unlock and not Util.unlocked(ctx, key) then
				return Util.unlockText(key)
			end
			return nil
		end

		local function drawRaids()
			Util.clear(raidList)
			local inLobby = myLobby() ~= nil
			for i, raid in Cfg.List do
				local card = New("Frame", {
					Name = "Raid_" .. raid.id,
					BackgroundColor3 = C.PanelDeep,
					Size = UDim2.new(1, -6, 0, CARD_H),
					LayoutOrder = i,
					Parent = raidList,
				}, { Create.Corner(12) })
				local ok, ap = pcall(Appearance.Preview, raid.boss.line, 3, raid.boss.form, raid.boss.rarity)
				if ok then
					local icon = MonsterIcon.new(ap, 56)
					icon.Position = UDim2.fromOffset(8, 6)
					icon.Parent = card
				end
				Util.text({
					Text = raid.name,
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body,
					Position = UDim2.fromOffset(72, 4),
					Size = UDim2.new(1, -80, 0, 24),
					Parent = card,
				})
				Util.text({
					Name = "Desc",
					Text = raid.desc,
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextYAlignment = Enum.TextYAlignment.Top,
					Position = UDim2.fromOffset(72, 28),
					Size = UDim2.new(1, -80, 0, 36),
					Parent = card,
				})
				Util.text({
					Name = "Info",
					Text = string.format("Boss Lv %d · win: %s", raid.boss.level, Util.rewardText(raid.reward[1])),
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					Position = UDim2.fromOffset(10, 66),
					Size = UDim2.new(1, -196, 0, 38),
					Parent = card,
				})
				local gate = gateText(raid)
				if gate then
					Util.text({
						Name = "Gate",
						Text = gate,
						Font = Theme.Fonts.Display,
						TextColor3 = C.Red,
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Center,
						AnchorPoint = Vector2.new(1, 1),
						Position = UDim2.new(1, -10, 1, -6),
						Size = UDim2.fromOffset(170, 44),
						Parent = card,
					})
				else
					Button.new({
						Name = "OpenLobby",
						Text = "Open lobby",
						Color = if inLobby then C.Gray else C.Purple,
						Disabled = inLobby,
						TextSize = Theme.TextSize.Small,
						Size = UDim2.fromOffset(170, 44),
						AnchorPoint = Vector2.new(1, 1),
						Position = UDim2.new(1, -10, 1, -6),
						Parent = card,
						OnClick = function()
							if not Util.unlocked(ctx, Cfg.Unlock) then
								ctx:Toast(Util.unlockText(Cfg.Unlock), "error")
								return
							end
							pickTeam(string.format("Bring up to %d Adults", Cfg.PerPlayer), function(ids)
								Util.requestOnce(ctx, "Raids.Open", { raid = raid.id, ids = ids })
							end)
						end,
					})
				end
			end
		end

		local function drawLobbies()
			Util.clear(lobbyList)
			local lobbies = StoreKit.tbl(ctx.Store, "global.Raids.lobbies")
			local mine = myLobby()
			local ids = {}
			for id in lobbies do
				table.insert(ids, id)
			end
			table.sort(ids)
			if #ids == 0 then
				Util.text({
					Text = "No raids are forming. Open one and invite your friends!",
					TextColor3 = C.TextMuted,
					Size = UDim2.new(1, 0, 0, 40),
					Parent = lobbyList,
				})
			end
			for i, id in ids do
				local lobby = lobbies[id]
				local raid = Cfg.ById[lobby.raid]
				local members = if type(lobby.members) == "table" then lobby.members else {}
				local card = New("Frame", {
					Name = "Lobby_" .. id,
					BackgroundColor3 = if id == mine then C.Gold else C.PanelDeep,
					Size = UDim2.new(1, -6, 0, 120),
					LayoutOrder = i,
					Parent = lobbyList,
				}, { Create.Corner(12) })
				Util.text({
					Text = string.format("%s · %d/%d", if raid then raid.name else "Raid", #members, Cfg.MaxPlayers),
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body,
					Position = UDim2.fromOffset(12, 6),
					Size = UDim2.new(1, -24, 0, 26),
					Parent = card,
				})
				local names = {}
				for _, member in members do
					table.insert(names, string.format("%s (%s)", member.name or "?", Format.short(member.power or 0)))
				end
				Util.text({
					Text = table.concat(names, " · "),
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					Position = UDim2.fromOffset(12, 34),
					Size = UDim2.new(1, -220, 0, 70),
					Parent = card,
				})
				local isHost = lobby.host == ctx.Player.UserId
				local buttons = New("Frame", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, -10, 1, -8),
					Size = UDim2.fromOffset(200, 100),
					Parent = card,
				}, { Create.List("y", 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom) })
				if id == mine then
					if isHost then
						Button.new({
							Name = "StartRaid",
							Text = "Start raid",
							Color = C.Green,
							TextSize = Theme.TextSize.Small,
							Size = UDim2.fromOffset(180, 44),
							LayoutOrder = 1,
							Parent = buttons,
							OnClick = function()
								Util.requestOnce(ctx, "Raids.Launch")
							end,
						})
					end
					Button.new({
						Name = "LeaveRaid",
						Text = if isHost then "Close lobby" else "Leave",
						Color = C.Gray,
						TextSize = Theme.TextSize.Small,
						Size = UDim2.fromOffset(180, 44),
						LayoutOrder = 2,
						Parent = buttons,
						OnClick = function()
							Util.requestOnce(ctx, "Raids.Leave")
						end,
					})
				elseif not mine and #members < Cfg.MaxPlayers and raid and not Util.unlocked(ctx, Cfg.UnlockFor(raid)) then
					Util.text({
						Name = "JoinLocked",
						Text = Util.unlockText(Cfg.UnlockFor(raid)),
						TextColor3 = C.Gold,
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Right,
						Size = UDim2.fromOffset(180, 44),
						Parent = buttons,
					})
				elseif not mine and #members < Cfg.MaxPlayers then
					Button.new({
						Name = "JoinRaid",
						Text = "Join",
						Color = C.Green,
						TextSize = Theme.TextSize.Small,
						Size = UDim2.fromOffset(180, 44),
						Parent = buttons,
						OnClick = function()
							pickTeam(string.format("Bring up to %d Adults", Cfg.PerPlayer), function(picked)
								Util.requestOnce(ctx, "Raids.Join", { lobby = id, ids = picked })
							end)
						end,
					})
				end
			end
		end

		local lockOverlay = nil
		local function draw()
			if not isOpen then
				return
			end
			local p = StoreKit.tbl(ctx.Store, "profile.Raids")
			local today = if p.day == math.floor(ctx:Now() / 86400) then (tonumber(p.rewarded) or 0) else 0
			todayLabel.Text = string.format("Raid rewards today: %d/%d", today, Cfg.DailyRewards)
			drawRaids()
			drawLobbies()
			if lockOverlay then
				lockOverlay:Destroy()
				lockOverlay = nil
			end
			if not Util.unlocked(ctx, Cfg.Unlock) then
				lockOverlay = Util.lockOverlay(panel.Body, Util.unlockText(Cfg.Unlock))
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				bag.clean()
				for _, path in { "global.Raids", "session.Raids", "profile.Raids", "profile.Progression.level" } do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				refresh()
			end,
			Close = function()
				isOpen = false
				bag.clean()
			end,
		}
	end,
}
