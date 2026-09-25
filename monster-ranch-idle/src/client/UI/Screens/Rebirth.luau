--[[
	Rebirth screen (update 1.4): Ranch Rebirth and the Stardust skill tree.

	Left: your Rebirth Stars and coin multiplier, the requirements (Ranch Level, coins in
	hand), and exactly what a rebirth keeps, resets and gives. "Choose Heirlooms" opens the
	Monsters pick mode (up to Config.Rebirth.Heirlooms) and then a confirmation with the
	Stardust you will get → Rebirth.Rebirth.
	Right: the skill tree, one column per branch (Rebirth.BuySkill). Locked nodes say why.

	Reads: profile.Rebirth, profile.Currency, profile.Monsters.list, profile.Progression.level
	(all tolerated nil). Opened from the Star Altar in the hub and from the Hall of Fame.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local MonsterIcon = require(UI.Components.MonsterIcon)
local Util = require(script.Parent.Parts.Util)
local Dialog = require(script.Parent.Parts.Dialog)

local New = Create.New
local C = Theme.Colors
local R = Config.Rebirth

-- "1.5", "2", "2.5": the coin multiplier of a star count.
local function mult(x: number): string
	return string.format("%g", x)
end

return {
	Name = "Rebirth",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Ranch Rebirth",
			Color = C.Purple,
			Size = UDim2.fromOffset(1040, 520),
			OnClose = function()
				ctx.Router:Close("Rebirth")
			end,
		})
		local starPill = Widgets.Pill({ Icon = "star", Text = "0", Parent = panel.HeaderRight })
		starPill.Root.LayoutOrder = 1
		local stardustPill = Widgets.Pill({ Icon = "stardust", Text = "0", Parent = panel.HeaderRight })
		stardustPill.Root.LayoutOrder = 2

		local isOpen = false
		local bag = Util.bag()
		local refresh

		local function state()
			local s = ctx.Store:Get("profile.Rebirth")
			return if type(s) == "table" then s else {}
		end
		local function stars(): number
			return tonumber(state().stars) or 0
		end
		local function skillLevel(id: string): number
			local skills = state().skills
			return if type(skills) == "table" then (tonumber(skills[id]) or 0) else 0
		end
		local function skillEffect(id: string, key: string): number
			local def = R.SkillById[id]
			return skillLevel(id) * (if def and def.effect[key] then def.effect[key] else 0)
		end
		local function heirlooms(): number
			return R.Heirlooms(stars(), skillEffect("family_vault", "heirlooms"))
		end
		local function coins(): number
			return tonumber(ctx.Store:Get("profile.Currency.coins")) or 0
		end
		local function stardust(): number
			return tonumber(ctx.Store:Get("profile.Currency.stardust")) or 0
		end
		-- Stardust the monsters outside `keep` would turn into.
		local function dustPreview(keep: { [string]: boolean }): (number, number)
			local base, count = 0, 0
			for id, m in Util.monsters(ctx) do
				if type(m) == "table" and not keep[id] then
					base += R.DustFor(m)
					count += 1
				end
			end
			return math.floor(base * (1 + skillEffect("star_sifter", "dustPct"))), count
		end

		-- Layout ----------------------------------------------------------------------------------

		local rebirthCard = Util.card({ Title = "Rebirth", Size = UDim2.new(0, 410, 1, -64), Parent = panel.Body })
		local info =
			Widgets.List({ Position = UDim2.fromOffset(10, 40), Size = UDim2.new(1, -20, 1, -46), Padding = 6, Parent = rebirthCard })
		local rebirthButton = Button.new({
			Name = "RebirthButton",
			Text = "Choose Heirlooms",
			Color = C.Orange,
			Size = UDim2.new(0, 410, 0, 56),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Parent = panel.Body,
		})
		local treeCard = Util.card({
			Title = "Stardust skill tree",
			Position = UDim2.fromOffset(422, 0),
			Size = UDim2.new(1, -422, 1, 0),
			Parent = panel.Body,
		})
		local columns = New("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(8, 38),
			Size = UDim2.new(1, -16, 1, -44),
			Parent = treeCard,
		}, {
			New("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})

		local function line(text: string, props)
			local p = props or {}
			return Util.text({
				Text = text,
				Font = p.Font or Theme.Fonts.Body,
				TextSize = p.TextSize or Theme.TextSize.Small,
				TextColor3 = p.Color or C.Text,
				TextWrapped = true,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 18),
				LayoutOrder = p.LayoutOrder,
				Parent = info,
			})
		end

		-- Rebirth flow ------------------------------------------------------------------------------

		local function confirmRebirth(ids: { string })
			local keep = {}
			for _, id in ids do
				keep[id] = true
			end
			local dust, lost = dustPreview(keep)
			local nextStar = stars() + 1
			local theme = Config.Decor.PenThemeById[R.BiomeFor(nextStar)]
			Dialog.confirm(ctx.UI.Top, {
				Title = string.format("Rebirth for Rebirth Star %d?", nextStar),
				Color = C.Purple,
				Size = Vector2.new(620, 430),
				ConfirmText = "Rebirth",
				ConfirmColor = C.Orange,
				Build = function(content)
					local row = New("Frame", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 64),
						LayoutOrder = 1,
						Parent = content,
					}, {
						New("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
							Padding = UDim.new(0, 6),
						}),
					})
					for i, id in ids do
						local ap = Util.appearance(Util.monsters(ctx)[id])
						if ap and i <= 8 then
							MonsterIcon.new(ap, 60).Parent = row
						end
					end
					Util.text({
						Text = string.format(
							"You keep these %d Heirloom%s. Your other %d monster%s become %s Stardust.",
							#ids,
							if #ids == 1 then "" else "s",
							lost,
							if lost == 1 then "" else "s",
							Format.commas(dust)
						),
						TextXAlignment = Enum.TextXAlignment.Center,
						AutomaticSize = Enum.AutomaticSize.Y,
						Size = UDim2.new(1, 0, 0, 20),
						LayoutOrder = 2,
						Parent = content,
					})
					Util.text({
						Text = string.format(
							"You lose %s coins, your pens, upgrades and garden, and your region progress.",
							Format.short(coins())
						),
						TextColor3 = C.Red,
						TextXAlignment = Enum.TextXAlignment.Center,
						AutomaticSize = Enum.AutomaticSize.Y,
						Size = UDim2.new(1, 0, 0, 20),
						LayoutOrder = 3,
						Parent = content,
					})
					Util.text({
						Text = string.format(
							"You gain Rebirth Star %d (coins ×%s) and the %s pen theme.",
							nextStar,
							mult(R.CoinMult(nextStar)),
							if theme then theme.name else "new"
						),
						Font = Theme.Fonts.Display,
						TextColor3 = C.Green,
						TextXAlignment = Enum.TextXAlignment.Center,
						AutomaticSize = Enum.AutomaticSize.Y,
						Size = UDim2.new(1, 0, 0, 20),
						LayoutOrder = 4,
						Parent = content,
					})
				end,
				OnConfirm = function()
					local ok, res = Util.requestOnce(ctx, "Rebirth.Rebirth", { keep = ids })
					if ok and type(res) == "table" then
						ctx:Toast(
							string.format("Rebirth Star %d! +%s Stardust", res.stars or nextStar, Format.commas(res.stardust or 0)),
							"reward"
						)
					end
				end,
			})
		end

		local function blockers(): { string }
			local list = {}
			if not Util.unlocked(ctx, R.Unlock) then
				table.insert(list, Util.unlockText(R.Unlock))
			end
			if stars() >= R.MaxStars then
				table.insert(list, "Every Rebirth Star earned")
			elseif coins() < R.CoinsNeeded(stars()) then
				table.insert(list, string.format("Save up %s coins", Format.short(R.CoinsNeeded(stars()))))
			end
			return list
		end

		rebirthButton:SetOnClick(function()
			local why = blockers()
			if #why > 0 then
				ctx:Toast(why[1], "error")
				return
			end
			Util.pick(ctx, {
				title = string.format("Choose up to %d Heirlooms to keep", heirlooms()),
				max = heirlooms(),
				filter = function(m)
					return not m.busy
				end,
				returnTo = "Rebirth",
				onPick = confirmRebirth,
			})
		end)

		-- Drawing ---------------------------------------------------------------------------------

		local function drawInfo()
			Util.clear(info)
			local n = stars()
			local nextStar = math.min(n + 1, R.MaxStars)
			local theme = Config.Decor.PenThemeById[R.BiomeFor(nextStar)]
			line(string.format("★ %d Rebirth Star%s · coins ×%s", n, if n == 1 then "" else "s", mult(R.CoinMult(n))), {
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				LayoutOrder = 1,
			})
			local levelOk = Util.unlocked(ctx, R.Unlock)
			local need = R.CoinsNeeded(n)
			local coinsOk = coins() >= need
			line(string.format("%s Ranch Level %d", if levelOk then "✓" else "✗", Util.unlockLevel(R.Unlock)), {
				Color = if levelOk then C.Green else C.Red,
				LayoutOrder = 2,
			})
			line(string.format("%s %s / %s coins in hand", if coinsOk then "✓" else "✗", Format.short(coins()), Format.short(need)), {
				Color = if coinsOk then C.Green else C.Red,
				LayoutOrder = 3,
			})
			line(
				string.format(
					"Keep: Ranch Level, Codex, Hall of Fame, gems, eggs, decor and themes, passes, and up to %d Heirloom monsters.",
					heirlooms()
				),
				{ LayoutOrder = 4 }
			)
			local dust, count = dustPreview({})
			line(
				string.format(
					"Reset: coins, pens and upgrades, garden and region progress. Your other monsters (%d) become up to %s Stardust.",
					count,
					Format.commas(dust)
				),
				{ Color = C.TextMuted, LayoutOrder = 5 }
			)
			local gains = {
				string.format("Rebirth Star %d (coins ×%s)", nextStar, mult(R.CoinMult(nextStar))),
				string.format("the %s pen theme", if theme then theme.name else "new"),
			}
			if n + 1 == R.CelestialStars then
				table.insert(gains, "the Celestial Egg")
			end
			if n + 1 == R.ThirdTraitStars then
				table.insert(gains, "a 3rd trait on every monster")
			end
			line("Gain: " .. table.concat(gains, ", ") .. ".", { Color = C.Green, LayoutOrder = 6 })
			local why = blockers()
			rebirthButton:SetText(if #why > 0 then why[1] else string.format("Choose Heirlooms (up to %d)", heirlooms()))
			rebirthButton:SetDisabled(#why > 0)
		end

		local function lockReason(def, level: number): string?
			if level >= def.maxLevel then
				return nil
			end
			if def.requires and skillLevel(def.requires) < 1 then
				return "Learn " .. R.SkillById[def.requires].name
			end
			if def.stars and stars() < def.stars then
				return string.format("Needs ★%d", def.stars)
			end
			return nil
		end

		local function drawTree()
			Util.clear(columns)
			local dust = stardust()
			for b, branch in R.Branches do
				local column = New("Frame", {
					Name = "Branch_" .. branch.id,
					BackgroundTransparency = 1,
					Size = UDim2.new(1 / #R.Branches, -6, 1, 0),
					LayoutOrder = b,
					Parent = columns,
				}, {
					New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
				})
				Util.text({
					Text = branch.name,
					Font = Theme.Fonts.Display,
					TextColor3 = Color3.fromHex(branch.color),
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, 0, 0, 24),
					LayoutOrder = 0,
					Parent = column,
				})
				for _, def in R.Skills do
					if def.branch == branch.id then
						local level = skillLevel(def.id)
						local maxed = level >= def.maxLevel
						local cost = def.cost[level + 1] or 0
						local lock = lockReason(def, level)
						local node = New("Frame", {
							Name = "Skill_" .. def.id,
							BackgroundColor3 = C.PanelDeep,
							Size = UDim2.new(1, 0, 0, 132),
							LayoutOrder = def.tier,
							Parent = column,
						}, { Create.Corner(10), Create.Stroke(2, Color3.fromHex(branch.color)) })
						Util.text({
							Text = string.format("%s  %d/%d", def.name, level, def.maxLevel),
							Font = Theme.Fonts.Display,
							TextSize = Theme.TextSize.Small,
							Position = UDim2.fromOffset(8, 4),
							Size = UDim2.new(1, -16, 0, 22),
							Parent = node,
						})
						Util.text({
							Text = def.desc,
							TextColor3 = C.TextMuted,
							TextSize = Theme.TextSize.Small,
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							Position = UDim2.fromOffset(8, 28),
							Size = UDim2.new(1, -16, 0, 50),
							Parent = node,
						})
						local button = Button.new({
							Name = "Buy",
							Text = if maxed then "MAX" elseif lock then "🔒 " .. lock else "✦ " .. Format.short(cost),
							Color = if lock then C.Gray else C.Purple,
							TextSize = Theme.TextSize.Small,
							Size = UDim2.new(1, -16, 0, 40),
							AnchorPoint = Vector2.new(0.5, 1),
							Position = UDim2.new(0.5, 0, 1, -6),
							Disabled = maxed or lock ~= nil or dust < cost,
							Parent = node,
						})
						button:SetOnClick(function()
							if maxed or lock then
								return
							end
							if stardust() < cost then
								ctx:Toast("Not enough Stardust", "error")
								return
							end
							local ok = Util.requestOnce(ctx, "Rebirth.BuySkill", { skill = def.id })
							if ok then
								ctx:Toast(def.name .. " learned!", "success")
							end
						end)
					end
				end
			end
		end

		local lockOverlay = nil
		local function draw()
			if not isOpen then
				return
			end
			starPill:SetText(tostring(stars()))
			stardustPill:SetText(Format.short(stardust()))
			drawInfo()
			drawTree()
			if lockOverlay then
				lockOverlay:Destroy()
				lockOverlay = nil
			end
			if not Util.unlocked(ctx, R.Unlock) then
				lockOverlay = Util.lockOverlay(panel.Body, Util.unlockText(R.Unlock))
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				bag.clean()
				for _, path in { "profile.Rebirth", "profile.Currency", "profile.Monsters.list", "profile.Progression.level" } do
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
