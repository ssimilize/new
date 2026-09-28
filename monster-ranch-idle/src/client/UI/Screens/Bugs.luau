--[[
	Bugs screen (update 3.13 · Wild things): the Bug Catching Meadow. Opened from the "Catch bugs"
	prompt on the meadow's signpost (Controllers/BugMeadow); no HUD button.

	lobby   swings left today, the honey lure (only with the Apiary: Bugs.Lure spends honey for
	        rarer bugs over the next swings), "Catch a bug" (Bugs.Start), the jar (sell a kind for
	        coins, Bugs.Sell) and a Bug Log button (the Codex's Bug Log tab).
	swing   a field with the net in the middle and a bug (a silhouette: which bug it is stays a
	        secret until it is caught) flying across on the path the server sent (Logic/Bugs.X).
	        Tap Swing (or Space / pad A) once while it is inside the net.
	result  Bugs.Submit { id, t } -> the catch (or "It flew off!"). A bug that crosses without a
	        swing is sent as a miss.
	Test hooks: the Field frame carries BugX, NetFrom, NetTo and Elapsed attributes while swinging.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local BugsLogic = require(Shared.Logic.Bugs)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local StoreKit = require(UI.Components.StoreKit)
local Util = require(script.Parent.Parts.Util)
local BugIcon = require(script.Parent.Parts.BugIcon)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Bugs

local FIELD = Vector2.new(820, 250)

return {
	Name = "Bugs",
	Build = function(ctx)
		local store = ctx.Store
		local panel = Panel.new({
			Title = "Bug Catching Meadow",
			Color = C.Green,
			Size = UDim2.fromOffset(900, 500),
			OnClose = function()
				ctx.Router:Close("Bugs")
			end,
		})

		local isOpen = false
		local mode = "lobby"
		local swing = nil -- { id, path, elapsed, done, sent }
		local lastResult = nil
		local conn, beganConn = nil, nil

		local body = New("Frame", { Name = "BugsBody", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })

		local function stopLoop()
			if conn then
				conn:Disconnect()
				conn = nil
			end
		end

		local draw

		local function section()
			return StoreKit.tbl(store, "profile.Bugs")
		end

		local function swingsLeft(s): number
			local used = if tonumber(s.day) == Util.day(ctx) then tonumber(s.swings) or 0 else 0
			return math.max(0, Cfg.FreeSwings - used)
		end

		local function hasApiary(): boolean
			return store:Get("profile.Apiary") ~= nil
		end

		-- Swing ---------------------------------------------------------------------------------
		local function submit(t: number)
			if not swing or swing.sent then
				return
			end
			swing.sent = true
			swing.done = true
			stopLoop()
			local at = math.clamp(math.floor(t * 1000 + 0.5) / 1000, 0, Cfg.MaxT)
			local ok, res = Util.requestOnce(ctx, "Bugs.Submit", { id = swing.id, t = at })
			lastResult = if ok and type(res) == "table" then res else nil
			mode = "result"
			draw()
		end

		local function tapSwing()
			if mode == "swing" and swing and not swing.done then
				task.spawn(submit, swing.elapsed)
			end
		end

		local function drawSwing()
			local field = New("Frame", {
				Name = "Field",
				BackgroundColor3 = Color3.fromHex("#8CCB5E"),
				Position = UDim2.fromOffset(18, 10),
				Size = UDim2.fromOffset(FIELD.X, FIELD.Y),
				ClipsDescendants = true,
				Parent = body,
			}, { Create.Corner(14), Create.Stroke(3) })
			local netFrom, netTo = Cfg.NetCenter - Cfg.NetHalf, Cfg.NetCenter + Cfg.NetHalf
			New("Frame", {
				Name = "Net",
				BackgroundColor3 = C.White,
				BackgroundTransparency = 0.55,
				Position = UDim2.fromScale(netFrom, 0),
				Size = UDim2.fromScale(netTo - netFrom, 1),
				Parent = field,
			}, { Create.Corner(10), Create.Stroke(2) })
			field:SetAttribute("NetFrom", netFrom)
			field:SetAttribute("NetTo", netTo)
			local bug = BugIcon.new(nil, 48, true)
			bug.Name = "BugMark"
			bug.AnchorPoint = Vector2.new(0.5, 0.5)
			bug.Rotation = 90
			bug.Parent = field
			Util.text({
				Name = "SwingHint",
				Text = "Tap Swing when the bug is inside the net!",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				TextWrapped = true,
				Position = UDim2.fromOffset(18, FIELD.Y + 24),
				Size = UDim2.fromOffset(460, 60),
				Parent = body,
			})
			local button = New("TextButton", {
				Name = "Swing",
				Text = "Swing!",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Header,
				TextColor3 = C.White,
				AutoButtonColor = true,
				BackgroundColor3 = C.Orange,
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -24, 1, -12),
				Size = UDim2.fromOffset(300, 80),
				Parent = body,
			}, { Create.Corner(16), Create.Stroke(3) })
			button.MouseButton1Click:Connect(tapSwing)

			local function render()
				local x = BugsLogic.X(swing.path, swing.elapsed)
				local y = BugsLogic.Y(swing.path, swing.elapsed)
				bug.Position = UDim2.fromScale(x, y)
				field:SetAttribute("BugX", x)
				field:SetAttribute("Elapsed", swing.elapsed)
			end
			render()
			stopLoop()
			conn = RunService.Heartbeat:Connect(function(dt)
				if not swing or swing.done then
					return
				end
				swing.elapsed += dt
				render()
				if swing.elapsed > swing.path.total + 0.3 then
					-- It crossed without a swing: a miss.
					task.spawn(submit, swing.path.total + 0.2)
				end
			end)
		end

		local function startSwing()
			local ok, res = Util.requestOnce(ctx, "Bugs.Start")
			if not ok or type(res) ~= "table" or type(res.path) ~= "table" then
				return
			end
			swing = { id = res.id, path = res.path, elapsed = 0, done = false, sent = false }
			mode = "swing"
			draw()
		end

		-- Lobby ---------------------------------------------------------------------------------
		local function drawJar(parent: Instance, s)
			local list = New("ScrollingFrame", {
				Name = "Jar",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(12, 44),
				Size = UDim2.new(1, -24, 1, -56),
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 6,
				Parent = parent,
			}, { Create.List("y", 6) })
			local jar = StoreKit.asTable(s.jar)
			local any = false
			for _, def in Cfg.List do
				local n = tonumber(jar[def.id]) or 0
				if n > 0 then
					any = true
					local row = New("Frame", {
						Name = "Row_" .. def.id,
						BackgroundColor3 = C.PanelDeep,
						BackgroundTransparency = 0.6,
						Size = UDim2.new(1, -8, 0, 52),
						LayoutOrder = def.order,
						Parent = list,
					}, { Create.Corner(10) })
					local icon = BugIcon.new(def.id, 46)
					icon.Position = UDim2.fromOffset(4, 3)
					icon.Parent = row
					Util.text({
						Text = string.format("%s ×%d", def.name, n),
						TextSize = Theme.TextSize.Body,
						Position = UDim2.fromOffset(58, 4),
						Size = UDim2.new(1, -170, 0, 24),
						Parent = row,
					})
					Util.text({
						Text = Cfg.Rarities[def.rarity].name,
						TextSize = Theme.TextSize.Small,
						TextColor3 = C.TextMuted,
						Position = UDim2.fromOffset(58, 27),
						Size = UDim2.new(1, -170, 0, 20),
						Parent = row,
					})
					Button.new({
						Name = "Sell_" .. def.id,
						Text = "Sell",
						Color = C.Gold,
						Size = UDim2.fromOffset(96, 44),
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -4, 0.5, 0),
						Parent = row,
						OnClick = function()
							Util.requestOnce(ctx, "Bugs.Sell", { bug = def.id, amount = n })
						end,
					})
				end
			end
			if not any then
				Util.text({
					Text = "Your jar is empty. Go catch some bugs!",
					TextColor3 = C.TextMuted,
					TextWrapped = true,
					Size = UDim2.new(1, -8, 0, 50),
					Parent = list,
				})
			end
		end

		local function drawLobby()
			local s = section()
			local left = swingsLeft(s)
			local lure = tonumber(s.lure) or 0
			local card = Util.card({ Name = "SwingCard", Title = "Catch bugs", Size = UDim2.new(0, 420, 1, 0), Parent = body })
			Util.text({
				Name = "Swings",
				Text = string.format("Free swings today: %d / %d", left, Cfg.FreeSwings),
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(16, 44),
				Size = UDim2.new(1, -32, 0, 26),
				Parent = card,
			})
			Util.text({
				Text = "Rarer bugs fly faster. Some only come out in one season or at night.",
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
				TextWrapped = true,
				Position = UDim2.fromOffset(16, 74),
				Size = UDim2.new(1, -32, 0, 44),
				Parent = card,
			})
			if hasApiary() then
				Util.text({
					Name = "Lure",
					Text = if lure > 0
						then string.format("Honey lure: rarer bugs for %d more swings", lure)
						else string.format("Honey lure: %d honey for rarer bugs over %d swings", Cfg.LureHoney, Cfg.LureSwings),
					TextSize = Theme.TextSize.Small,
					TextWrapped = true,
					Position = UDim2.fromOffset(16, 122),
					Size = UDim2.new(0.55, -16, 0, 50),
					Parent = card,
				})
				Button.new({
					Name = "UseLure",
					Text = "Use honey lure",
					Color = if lure > 0 then C.Gray else C.Gold,
					Disabled = lure > 0,
					Size = UDim2.new(0.45, -16, 0, 48),
					Position = UDim2.new(0.55, 0, 0, 122),
					Parent = card,
					OnClick = function()
						Util.requestOnce(ctx, "Bugs.Lure")
					end,
				})
			end
			Button.new({
				Name = "BugLog",
				Text = "Bug Log",
				Color = C.Purple,
				Size = UDim2.new(0.5, -24, 0, 50),
				Position = UDim2.fromOffset(16, 186),
				Parent = card,
				OnClick = function()
					if ctx.Router:Has("Codex") then
						ctx.Router:Open("Codex", { tab = "buglog" })
					end
				end,
			})
			Button.new({
				Name = "InsectHall",
				Text = "Insect Hall",
				Color = C.Blue,
				Size = UDim2.new(0.5, -24, 0, 50),
				Position = UDim2.new(0.5, 8, 0, 186),
				Parent = card,
				OnClick = function()
					if ctx.Router:Has("Exhibits") then
						ctx.Router:Open("Exhibits", { set = "insects" })
					end
				end,
			})
			local canSwing = left > 0
			Button.new({
				Name = "StartSwing",
				Text = if canSwing then "Catch a bug" else "No swings left today",
				Color = if canSwing then C.Green else C.Gray,
				Disabled = not canSwing,
				Size = UDim2.fromOffset(300, 64),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -16),
				Parent = card,
				OnClick = function()
					if canSwing then
						startSwing()
					end
				end,
			})
			local jarCard = Util.card({
				Name = "JarCard",
				Title = "Your bugs",
				Position = UDim2.fromOffset(436, 0),
				Size = UDim2.new(1, -436, 1, 0),
				Parent = body,
			})
			drawJar(jarCard, s)
			if not Util.unlocked(ctx, Cfg.Unlock) then
				Util.lockOverlay(body, Util.unlockText(Cfg.Unlock))
			end
		end

		local function drawResult()
			local card = Util.card({ Name = "ResultCard", Title = "In the meadow", Size = UDim2.new(1, 0, 1, 0), Parent = body })
			local r = lastResult
			local def = r and r.caught and Cfg.ById[r.bug]
			if def then
				local icon = BugIcon.new(def.id, 120)
				icon.AnchorPoint = Vector2.new(0.5, 0)
				icon.Position = UDim2.new(0.5, 0, 0, 36)
				icon.Parent = card
			end
			Util.text({
				Name = "BugResult",
				Text = if def
					then string.format("You caught a %s!", def.name)
					elseif r then "It flew off!"
					else "That swing couldn't be scored. Try again!",
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Header,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(16, 160),
				Size = UDim2.new(1, -32, 0, 40),
				Parent = card,
			})
			if def then
				Util.text({
					Name = "BugRarity",
					Text = Cfg.Rarities[def.rarity].name,
					TextSize = Theme.TextSize.Body,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(16, 202),
					Size = UDim2.new(1, -32, 0, 28),
					Parent = card,
				})
				if r.first then
					Util.text({
						Name = "BugNew",
						Text = "New in your Bug Log!",
						TextSize = Theme.TextSize.Body,
						TextColor3 = C.Green,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.fromOffset(16, 232),
						Size = UDim2.new(1, -32, 0, 28),
						Parent = card,
					})
				end
			end
			local left = if r then tonumber(r.left) or 0 else swingsLeft(section())
			local row = New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -16),
				Size = UDim2.new(0.8, 0, 0, 64),
				Parent = card,
			}, { Create.List("x", 16, Enum.HorizontalAlignment.Center) })
			Button.new({
				Name = "SwingAgain",
				Text = if left > 0 then "Catch another" else "No swings left today",
				Color = if left > 0 then C.Green else C.Gray,
				Disabled = left <= 0,
				Size = UDim2.new(0.45, 0, 0, 60),
				LayoutOrder = 1,
				Parent = row,
				OnClick = function()
					if left > 0 then
						startSwing()
					end
				end,
			})
			Button.new({
				Name = "BugsDone",
				Text = "Done",
				Color = C.Gray,
				Size = UDim2.new(0.3, 0, 0, 60),
				LayoutOrder = 2,
				Parent = row,
				OnClick = function()
					mode = "lobby"
					draw()
				end,
			})
		end

		function draw()
			if not isOpen then
				return
			end
			Util.clear(body)
			panel.Root:SetAttribute("GamepadLegend", if mode == "swing" then "Ⓐ Swing · Ⓑ Close" else nil)
			if mode == "swing" then
				drawSwing()
			elseif mode == "result" then
				drawResult()
			else
				drawLobby()
			end
		end

		local watch = StoreKit.watch(store, { "profile.Bugs", "profile.Progression", "profile.Apiary" }, function()
			if mode == "lobby" then
				draw()
			end
		end)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				mode = if swing and not swing.done then "swing" else "lobby"
				beganConn = UserInputService.InputBegan:Connect(function(input)
					if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
						tapSwing()
					end
				end)
				watch.Start()
				draw()
			end,
			Close = function()
				isOpen = false
				stopLoop()
				watch.Stop()
				if swing and not swing.done then
					swing.done = true -- walking away lets the bug go
				end
				panel.Root:SetAttribute("GamepadLegend", nil)
				if beganConn then
					beganConn:Disconnect()
					beganConn = nil
				end
			end,
		}
	end,
}
