--[[
	GeneLab screen (update 3.10 · Ranch life): the Gene Lab. Params: { id? } (an Adult's id).

	Reached from Monster Detail (the Gene Lab button on the genes line) and the Breeding Barn's
	header; no HUD button. "Choose an Adult" opens the Monsters picker (free Adults only).

	One row per gene stat: its grade, the pair, the Lab's odds and Stardust cost for tuning the
	weaker gene (Logic/GeneLab, or "Lab limit reached" at Config.GeneLab.Cap), a "Locked" chip
	when the monster's `geneLock` is that stat, Tune (GeneLab.Tune) and Lock (GeneLab.Lock, a
	confirm that says the Star Shards are not refunded when a lock is replaced). The header line
	shows the tunes left today (profile.GeneLab, UTC day) and the player's Stardust and Star
	Shards; a tune's result shows under the rows with a pulse (success) or a shake (no luck).

	Reads: profile.GeneLab, profile.Monsters.list, profile.Currency.stardust,
	profile.HallOfFame.starShards, profile.Progression.level (all tolerated nil).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local Genetics = require(Shared.Logic.Genetics)
local LabLogic = require(Shared.Logic.GeneLab)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local GeneGrades = require(UI.Components.GeneGrades)
local Tiles = require(UI.Components.Tiles)
local Util = require(script.Parent.Parts.Util)
local Dialog = require(script.Parent.Parts.Dialog)

local New = Create.New
local C = Theme.Colors
local Rules = Config.GeneLab

local ROW_H = 54
local ROW_GAP = 6
local ROWS_Y = 64

local function statName(stat: string): string
	return Config.Genetics.StatNames[stat] or stat
end

return {
	Name = "GeneLab",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Gene Lab",
			Color = C.Purple,
			Size = UDim2.fromOffset(880, 480),
			OnClose = function()
				ctx.Router:Close("GeneLab")
			end,
		})

		local bag = Util.bag()
		local currentId: string? = nil
		local busy = false
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
			Size = UDim2.new(0.55, 0, 0, 30),
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
			Size = UDim2.new(0.45, 0, 0, 30),
			Parent = body,
		})
		local tunesLabel = Util.text({
			Name = "TunesLeft",
			Text = "",
			TextSize = Theme.TextSize.Body,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(0, 32),
			Size = UDim2.new(1, 0, 0, 26),
			Parent = body,
		})
		local emptyLabel = Util.text({
			Name = "Empty",
			Text = "Choose an Adult to tune its genes",
			TextSize = Theme.TextSize.Header,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, ROWS_Y + 90),
			Size = UDim2.new(1, 0, 0, 40),
			Parent = body,
		})

		local rows = {} -- [stat] = { frame, badgeSlot, pair, odds, locked, tune, lock }
		local tuneStat, lockStat -- set below
		for i, stat in Config.Genetics.Stats do
			local frame = New("Frame", {
				Name = "Stat_" .. stat,
				BackgroundColor3 = C.PanelDeep,
				Position = UDim2.fromOffset(0, ROWS_Y + (i - 1) * (ROW_H + ROW_GAP)),
				Size = UDim2.new(1, 0, 0, ROW_H),
				Parent = body,
			}, { Create.Corner(8) })
			Util.text({
				Text = statName(stat),
				TextSize = Theme.TextSize.Body,
				TextWrapped = false,
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(0, 56, 1, 0),
				Parent = frame,
			})
			local badgeSlot = Tiles.frame({
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 70, 0.5, 0),
				Size = UDim2.fromOffset(28, 22),
				Parent = frame,
			})
			local pair = Util.text({
				Name = "Pair",
				Text = "",
				TextSize = Theme.TextSize.Body,
				TextWrapped = false,
				Position = UDim2.fromOffset(108, 0),
				Size = UDim2.new(0, 130, 1, 0),
				Parent = frame,
			})
			local odds = Util.text({
				Name = "Odds",
				Text = "",
				TextSize = Theme.TextSize.Small,
				TextColor3 = C.TextMuted,
				Position = UDim2.fromOffset(242, 0),
				Size = UDim2.new(1, -242 - 346, 1, 0),
				Parent = frame,
			})
			local locked = New("Frame", {
				Name = "Locked",
				BackgroundColor3 = C.Gold,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -250, 0.5, 0),
				Size = UDim2.fromOffset(84, 28),
				Visible = false,
				Parent = frame,
			}, { Create.Corner(14) })
			Util.text({
				Text = "Locked",
				TextSize = Theme.TextSize.Small,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.fromScale(1, 1),
				Parent = locked,
			})
			local tune = Button.new({
				Name = "Tune",
				Text = "Tune",
				Color = C.Green,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -128, 0.5, 0),
				Size = UDim2.fromOffset(110, 44),
				TextSize = Theme.TextSize.Body,
				Parent = frame,
				OnClick = function()
					tuneStat(stat)
				end,
			})
			local lock = Button.new({
				Name = "LockGene",
				Text = "Lock",
				Color = C.Purple,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(110, 44),
				TextSize = Theme.TextSize.Body,
				Parent = frame,
				OnClick = function()
					lockStat(stat)
				end,
			})
			rows[stat] = { frame = frame, badgeSlot = badgeSlot, pair = pair, odds = odds, locked = locked, tune = tune, lock = lock }
		end

		local resultY = ROWS_Y + #Config.Genetics.Stats * (ROW_H + ROW_GAP)
		local resultLabel = Util.text({
			Name = "Result",
			Text = "",
			TextSize = Theme.TextSize.Body,
			Position = UDim2.fromOffset(0, resultY),
			Size = UDim2.new(1, 0, 0, 26),
			Parent = body,
		})
		Util.text({
			Name = "Help",
			Text = string.format(
				"Tuning raises the weaker gene of a pair, up to %d. A lock costs %d Star Shards: this monster's next baby gets its better gene of that stat.",
				Rules.Cap,
				Rules.LockShards
			),
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(0, resultY + 28),
			Size = UDim2.new(1, 0, 0, 40),
			Parent = body,
		})

		local function monster()
			local m = currentId and Util.monsters(ctx)[currentId]
			if m and (m.stage or 1) >= 3 then
				return m
			end
			return nil
		end

		local function tunesLeft(): number
			return LabLogic.TunesLeft(ctx.Store:Get("profile.GeneLab"), Util.day(ctx))
		end

		local function draw()
			local m = monster()
			local stardust = tonumber(ctx.Store:Get("profile.Currency.stardust")) or 0
			local shards = tonumber(ctx.Store:Get("profile.HallOfFame.starShards")) or 0
			local left = tunesLeft()
			walletLabel.Text = string.format("%s Stardust · %d Star Shards", Format.commas(stardust), shards)
			tunesLabel.Text = string.format("Tunes left today: %d/%d", left, Rules.DailyTunes)
			nameLabel.Text = if m then string.format("%s · %s", Formulas.DisplayName(m), Formulas.FormName(m)) else ""
			emptyLabel.Visible = m == nil
			for stat, row in rows do
				row.frame.Visible = m ~= nil
				if m then
					local a, b = Genetics.Pair(m.genes, stat)
					local _, gene = LabLogic.Weaker(m.genes, stat)
					local chance = LabLogic.Chance(gene)
					Tiles.clear(row.badgeSlot)
					GeneGrades.badge({ Points = a + b, Size = UDim2.fromScale(1, 1), Parent = row.badgeSlot })
					row.pair.Text = string.format("Genes %d + %d", a, b)
					if chance then
						row.odds.Text =
							string.format("%d%% chance · %s Stardust", math.floor(chance * 100 + 0.5), Format.commas(LabLogic.Cost(gene)))
					else
						row.odds.Text = "Lab limit reached"
					end
					row.locked.Visible = m.geneLock == stat
					row.tune:SetDisabled(chance == nil or left <= 0)
					row.lock:SetDisabled(m.geneLock == stat)
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

		tuneStat = function(stat: string)
			local m = monster()
			if busy or not m then
				return
			end
			busy = true
			local ok, res = Util.requestOnce(ctx, "GeneLab.Tune", { id = m.id, stat = stat })
			busy = false
			if not ok or type(res) ~= "table" then
				return
			end
			local row = rows[stat]
			if res.success then
				resultLabel.TextColor3 = C.Green
				resultLabel.Text = string.format("Success! %s gene is now %d", statName(stat), res.gene)
				Anim.pulse(row.frame, 0.06)
			else
				resultLabel.TextColor3 = C.Red
				resultLabel.Text = string.format("No luck this time. %s gene stays at %d", statName(stat), res.gene)
				Anim.shake(row.frame)
			end
			Anim.popIn(resultLabel)
			draw()
		end

		lockStat = function(stat: string)
			local m = monster()
			if busy or not m then
				return
			end
			Dialog.confirm(ctx.UI.Top, {
				Title = "Lock this gene?",
				Text = string.format(
					"Spend %d Star Shards to lock %s? The next baby gets this monster's better %s gene. A new lock replaces this one, and Star Shards are not refunded.",
					Rules.LockShards,
					statName(stat),
					statName(stat)
				),
				ConfirmText = "Lock",
				ConfirmColor = C.Purple,
				OnConfirm = function()
					local ok = Util.requestOnce(ctx, "GeneLab.Lock", { id = m.id, stat = stat })
					if ok then
						resultLabel.TextColor3 = C.Purple
						resultLabel.Text = string.format("%s locked for the next baby", statName(stat))
						Anim.pulse(rows[stat].frame, 0.06)
						draw()
					end
				end,
			})
		end

		pickButton:SetOnClick(function()
			Util.pick(ctx, {
				title = "Choose an Adult",
				max = 1,
				filter = function(m)
					return (m.stage or 1) >= 3 and not m.busy
				end,
				returnTo = "GeneLab",
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
				for _, path in
					{
						"profile.GeneLab",
						"profile.Monsters.list",
						"profile.Currency.stardust",
						"profile.HallOfFame.starShards",
						"profile.Progression.level",
					}
				do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				if type(params) == "table" and type(params.id) == "string" and params.id ~= currentId then
					currentId = params.id
					resultLabel.Text = ""
				end
				draw()
			end,
			Close = function()
				bag.clean()
			end,
		}
	end,
}
