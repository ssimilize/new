--[[
	Dojo screen (update 3.11 · Seasons & secrets): Adults learn battle techniques.
	Params: { id? } (an Adult's id). Reached from Monster Detail (the Dojo button on the genes
	line); no HUD button. "Choose an Adult" opens the Monsters picker (free Adults only).

	The mat line shows the one training in progress (who, what, a countdown) and Collect once it
	is done. One row per technique of the chosen monster's element(s) (Logic/Dojo.Learnable):
	its name, what it does, its level, the next level's Stardust and time (Config/Techniques
	Train), Learn / Level up (Dojo.Train) and Forget (Dojo.Forget, a confirm that says nothing is
	refunded). The slots line says when the 2nd slot opens (Bond heart 5).

	Reads: profile.Dojo, profile.Monsters.list, profile.Currency.stardust,
	profile.Progression.level, profile.Bond.list (all tolerated nil).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local DojoLogic = require(Shared.Logic.Dojo)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Tiles = require(UI.Components.Tiles)
local Util = require(script.Parent.Parts.Util)
local Dialog = require(script.Parent.Parts.Dialog)
local BondBadge = require(script.Parent.Parts.BondBadge)

local New = Create.New
local C = Theme.Colors
local Rules = Config.Techniques

local ROW_H = 52
local ROW_GAP = 6
local MAT_Y = 60
local ROWS_Y = 122
local MAX_ROWS = 4 -- two elements × two techniques

return {
	Name = "Dojo",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Dojo",
			Color = C.Orange,
			Size = UDim2.fromOffset(880, 480),
			OnClose = function()
				ctx.Router:Close("Dojo")
			end,
		})

		local bag = Util.bag()
		local currentId: string? = nil
		local busy = false
		local isOpen = false
		local ticking = false
		local refresh
		local lockOverlay = nil

		local pickButton = Button.new({
			Name = "Pick",
			Text = "Choose an Adult",
			Color = C.Blue,
			Size = UDim2.fromOffset(190, 44),
			TextSize = Theme.TextSize.Body,
			LayoutOrder = 1,
			Parent = panel.HeaderRight,
		})

		local body = Tiles.frame({ Size = UDim2.fromScale(1, 1), Parent = panel.Body })
		local nameLabel = Util.text({
			Name = "MonsterName",
			Text = "",
			TextSize = Theme.TextSize.Header,
			Size = UDim2.new(0.6, 0, 0, 30),
			Parent = body,
		})
		nameLabel:SetAttribute("Localize", false) -- a player-chosen name or a species name
		local walletLabel = Util.text({
			Name = "Wallet",
			Text = "",
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.4, 0, 0, 30),
			Parent = body,
		})
		local slotsLabel = Util.text({
			Name = "Slots",
			Text = "",
			TextSize = Theme.TextSize.Small,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(0, 32),
			Size = UDim2.new(1, 0, 0, 24),
			Parent = body,
		})

		-- The training mat.
		local mat = New("Frame", {
			Name = "Mat",
			BackgroundColor3 = C.PanelDeep,
			Position = UDim2.fromOffset(0, MAT_Y),
			Size = UDim2.new(1, 0, 0, ROW_H),
			Parent = body,
		}, { Create.Corner(8) })
		local matText = Util.text({
			Name = "MatText",
			Text = "",
			TextSize = Theme.TextSize.Body,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -12 - 250, 1, 0),
			Parent = mat,
		})
		local timeLabel = Util.text({
			Name = "Time",
			Text = "",
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -128, 0, 0),
			Size = UDim2.new(0, 110, 1, 0),
			Parent = mat,
		})
		local collectButton = Button.new({
			Name = "Collect",
			Text = "Collect",
			Color = C.Green,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(110, 42),
			TextSize = Theme.TextSize.Body,
			Parent = mat,
		})

		local emptyLabel = Util.text({
			Name = "Empty",
			Text = "Choose an Adult to train its techniques",
			TextSize = Theme.TextSize.Header,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, ROWS_Y + 60),
			Size = UDim2.new(1, 0, 0, 40),
			Parent = body,
		})

		local rows = {} -- [i] = { frame, name, desc, info, train, forget, tech }
		local trainTech, forgetTech -- set below
		for i = 1, MAX_ROWS do
			local frame = New("Frame", {
				Name = "Row" .. i,
				BackgroundColor3 = C.PanelDeep,
				Position = UDim2.fromOffset(0, ROWS_Y + (i - 1) * (ROW_H + ROW_GAP)),
				Size = UDim2.new(1, 0, 0, ROW_H),
				Visible = false,
				Parent = body,
			}, { Create.Corner(8) })
			local name = Util.text({
				Name = "TechName",
				Text = "",
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(12, 2),
				Size = UDim2.new(0, 190, 0, 26),
				Parent = frame,
			})
			local level = Util.text({
				Name = "Level",
				Text = "",
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.Gold,
				Position = UDim2.fromOffset(12, 26),
				Size = UDim2.new(0, 190, 0, 22),
				Parent = frame,
			})
			local desc = Util.text({
				Name = "Desc",
				Text = "",
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
				Position = UDim2.fromOffset(206, 2),
				Size = UDim2.new(1, -206 - 236, 0, 24),
				Parent = frame,
			})
			local info = Util.text({
				Name = "Info",
				Text = "",
				TextSize = Theme.TextSize.Small,
				Position = UDim2.fromOffset(206, 26),
				Size = UDim2.new(1, -206 - 236, 0, 24),
				Parent = frame,
			})
			local row = { frame = frame, name = name, level = level, desc = desc, info = info, tech = nil }
			row.train = Button.new({
				Name = "Train",
				Text = "Learn",
				Color = C.Green,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -116, 0.5, 0),
				Size = UDim2.fromOffset(112, 42),
				TextSize = Theme.TextSize.Body,
				Parent = frame,
				OnClick = function()
					if row.tech then
						trainTech(row.tech)
					end
				end,
			})
			row.forget = Button.new({
				Name = "Forget",
				Text = "Forget",
				Color = C.Gray,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(100, 42),
				TextSize = Theme.TextSize.Body,
				Parent = frame,
				OnClick = function()
					if row.tech then
						forgetTech(row.tech)
					end
				end,
			})
			rows[i] = row
		end

		local resultY = ROWS_Y + MAX_ROWS * (ROW_H + ROW_GAP)
		local resultLabel = Util.text({
			Name = "Result",
			Text = "",
			TextSize = Theme.TextSize.Body,
			Position = UDim2.fromOffset(0, resultY),
			Size = UDim2.new(1, 0, 0, 26),
			Parent = body,
		})

		local function monster()
			local m = currentId and Util.monsters(ctx)[currentId]
			if m and (m.stage or 1) >= Rules.MinStage then
				return m
			end
			return nil
		end

		local function training()
			local s = ctx.Store:Get("profile.Dojo")
			return if type(s) == "table" and type(s.training) == "table" then s.training else nil
		end

		local function drawMat()
			local t = training()
			if not t then
				matText.Text = "The training mat is free"
				timeLabel.Text = ""
				collectButton:SetVisible(false)
				return
			end
			local m = Util.monsters(ctx)[t.id]
			local tech = Rules.ById[t.tech]
			matText.Text = string.format(
				"%s is training %s · Lv %d",
				if m then Formulas.DisplayName(m) else "?",
				if tech then tech.name else t.tech,
				t.lv
			)
			local left = (t.readyAt or 0) - ctx:Now()
			collectButton:SetVisible(true)
			if left > 0 then
				timeLabel.Text = Format.clock(left)
				collectButton:SetDisabled(true)
			else
				timeLabel.Text = "Ready!"
				collectButton:SetDisabled(false)
			end
		end

		local function draw()
			local m = monster()
			local stardust = tonumber(ctx.Store:Get("profile.Currency.stardust")) or 0
			walletLabel.Text = string.format("%s Stardust", Format.commas(stardust))
			nameLabel.Text = if m then string.format("%s · %s", Formulas.DisplayName(m), Formulas.FormName(m)) else ""
			emptyLabel.Visible = m == nil
			drawMat()
			local hearts = if m then BondBadge.of(ctx, m.id).hearts else 0
			local slots = DojoLogic.Slots(hearts)
			if not m then
				slotsLabel.Text = ""
			elseif slots >= Rules.MaxSlots then
				slotsLabel.Text = string.format("Technique slots: %d/%d", #DojoLogic.Known(m), Rules.MaxSlots)
			else
				slotsLabel.Text =
					string.format("Technique slots: %d/%d · the 2nd opens at Bond heart %d", #DojoLogic.Known(m), slots, Rules.Slot2Hearts)
			end
			local learnable = if m then DojoLogic.Learnable(m) else {}
			local matTaken = training() ~= nil
			for i, row in rows do
				local tech = learnable[i]
				row.tech = tech and tech.id
				row.frame.Visible = tech ~= nil
				if tech and m then
					row.frame.Name = "Tech_" .. tech.id
					local lv = DojoLogic.Level(m, tech.id)
					row.name.Text = tech.name
					row.level.Text = if lv > 0 then string.format("Lv %d/%d", lv, Rules.MaxLevel) else "Not learned"
					row.desc.Text = Rules.KindText[tech.kind] or ""
					local nextLv, why = DojoLogic.Check(m, tech.id, hearts)
					if nextLv then
						local cost, seconds = DojoLogic.Cost(nextLv)
						row.info.Text = string.format("Lv %d · %s Stardust · %s", nextLv, Format.commas(cost), Format.duration(seconds))
						row.info.TextColor3 = if stardust >= cost then C.Text else C.Red
						row.train:SetDisabled(matTaken or stardust < cost or (m.busy ~= nil and m.busy ~= false))
					else
						row.info.Text = why or ""
						row.info.TextColor3 = C.TextMuted
						row.train:SetDisabled(true)
					end
					row.train:SetText(if lv > 0 then "Level up" else "Learn")
					row.forget:SetVisible(lv > 0)
					local t = training()
					row.forget:SetDisabled(t ~= nil and t.id == m.id)
				else
					row.frame.Name = "Row" .. i
				end
			end
			if lockOverlay then
				lockOverlay:Destroy()
				lockOverlay = nil
			end
			if not Util.unlocked(ctx, Rules.Unlock) then
				lockOverlay = Util.lockOverlay(body, Util.unlockText(Rules.Unlock))
			end
		end
		refresh = Util.debounce(draw)

		trainTech = function(techId: string)
			local m = monster()
			if busy or not m then
				return
			end
			busy = true
			local ok, res = Util.requestOnce(ctx, "Dojo.Train", { id = m.id, tech = techId })
			busy = false
			if not ok or type(res) ~= "table" then
				return
			end
			resultLabel.TextColor3 = C.Green
			resultLabel.Text = string.format("Training started: %s · Lv %d", Rules.ById[techId].name, res.lv)
			Anim.popIn(resultLabel)
			draw()
		end

		forgetTech = function(techId: string)
			local m = monster()
			if busy or not m then
				return
			end
			Dialog.confirm(ctx.UI.Top, {
				Title = "Forget this technique?",
				Text = string.format(
					"%s forgets %s. The Stardust spent on it is not refunded.",
					Formulas.DisplayName(m),
					Rules.ById[techId].name
				),
				ConfirmText = "Forget",
				ConfirmColor = C.Red,
				OnConfirm = function()
					local ok = Util.requestOnce(ctx, "Dojo.Forget", { id = m.id, tech = techId })
					if ok then
						resultLabel.TextColor3 = C.TextMuted
						resultLabel.Text = string.format("%s was forgotten", Rules.ById[techId].name)
						draw()
					end
				end,
			})
		end

		collectButton:SetOnClick(function()
			if busy then
				return
			end
			busy = true
			local ok, res = Util.requestOnce(ctx, "Dojo.Collect")
			busy = false
			if ok and type(res) == "table" and Rules.ById[res.tech] then
				resultLabel.TextColor3 = C.Gold
				resultLabel.Text = string.format("Learned %s · Lv %d", Rules.ById[res.tech].name, res.lv)
				Anim.pulse(mat, 0.06)
				draw()
			end
		end)

		pickButton:SetOnClick(function()
			Util.pick(ctx, {
				title = "Choose an Adult",
				max = 1,
				filter = function(m)
					return (m.stage or 1) >= Rules.MinStage and not m.busy
				end,
				returnTo = "Dojo",
				onPick = function(ids)
					currentId = ids[1]
					resultLabel.Text = ""
					refresh()
				end,
			})
		end)

		return {
			Root = panel.Root,
			Open = function(params)
				bag.clean()
				isOpen = true
				for _, path in
					{
						"profile.Dojo",
						"profile.Monsters.list",
						"profile.Currency.stardust",
						"profile.Progression.level",
						"profile.Bond.list",
					}
				do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				if type(params) == "table" and type(params.id) == "string" and params.id ~= currentId then
					currentId = params.id
					resultLabel.Text = ""
				end
				draw()
				if not ticking then
					ticking = true
					task.spawn(function()
						while isOpen do
							task.wait(1)
							if isOpen then
								drawMat()
							end
						end
						ticking = false
					end)
				end
			end,
			Close = function()
				isOpen = false
				bag.clean()
			end,
		}
	end,
}
