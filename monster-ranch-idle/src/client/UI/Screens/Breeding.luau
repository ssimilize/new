--[[
	Breeding screen (C3): the Breeding Barn.

	Pods (session.Breeding.podCount) with timers, Claim and Cancel (fee is not refunded);
	two parent pickers (Monsters pick mode: Adults that aren't busy and have breeds left);
	a preview from Logic/Breeding.Outcomes (species with a "?" silhouette for undiscovered
	hybrids, rarity bars, mutation chance, time and fee); daily breeds left per parent;
	Start → Breeding.Start.

	Reads: profile.Breeding, session.Breeding, profile.Monsters.list, profile.Currency.coins,
	profile.Progression.level (all tolerated nil).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Formulas = require(Shared.Logic.Formulas)
local Appearance = require(Shared.Logic.Appearance)

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
local BreedingConfig = Config.Breeding

local function lineName(lineId: string): string
	local def = Config.Species.ById[lineId]
	local form = def and def.forms[1]
	return if form then form.name else lineId
end

-- Local estimate used only while Logic/Breeding is not available.
local function estimateOutcomes(a, b)
	local species = {}
	local defA, defB = Config.Species.ById[a.line], Config.Species.ById[b.line]
	local hybrid = nil
	if defA and defB then
		hybrid = BreedingConfig.HybridFor(defA.elements[1], defB.elements[1])
	end
	local odds = BreedingConfig.SpeciesOdds
	if a.line == b.line then
		table.insert(species, { line = a.line, pct = if hybrid then 100 - odds.hybrid else 100, hybrid = false })
	else
		local scale = if hybrid then 1 else 100 / (odds.parentA + odds.parentB)
		table.insert(species, { line = a.line, pct = odds.parentA * scale, hybrid = false })
		table.insert(species, { line = b.line, pct = odds.parentB * scale, hybrid = false })
	end
	if hybrid then
		table.insert(species, { line = hybrid, pct = odds.hybrid, hybrid = true })
	end
	local low, high = math.min(a.rarity, b.rarity), math.max(a.rarity, b.rarity)
	local r = BreedingConfig.RarityOdds
	local rarity = {}
	local function add(index, pct)
		index = math.clamp(index, 1, BreedingConfig.MaxBredRarity)
		for _, entry in rarity do
			if entry.rarity == index then
				entry.pct += pct
				return
			end
		end
		table.insert(rarity, { rarity = index, pct = pct })
	end
	add(low, r.lower)
	add(high, r.higher)
	add(high + 1, r.up)
	table.sort(rarity, function(x, y)
		return x.rarity < y.rarity
	end)
	local hasMuts = #(a.muts or {}) > 0 or #(b.muts or {}) > 0
	local value = 0
	for _, m in { a, b } do
		local ok, v = pcall(Formulas.Value, m)
		if ok then
			value = math.max(value, v)
		end
	end
	return {
		species = species,
		rarity = rarity,
		mutationChance = if hasMuts then BreedingConfig.MutationInheritChance else 0,
		seconds = BreedingConfig.Seconds[high] or BreedingConfig.Seconds[1],
		fee = math.floor(value * BreedingConfig.FeePct),
		goldenChance = if (a.variant or 0) >= 1 or (b.variant or 0) >= 1 then BreedingConfig.GoldenOneParentChance else 0,
		rainbowChance = if a.variant == 2 and b.variant == 2 then BreedingConfig.RainbowBothParentsChance else 0,
	}
end

local function outcomes(a, b)
	local Logic = Util.logic("Breeding")
	if Logic and type(Logic.Outcomes) == "function" then
		local ok, result = pcall(Logic.Outcomes, a, b)
		if ok and type(result) == "table" and type(result.species) == "table" then
			return result
		end
	end
	return estimateOutcomes(a, b)
end

-- pct values may be 0..1 or 0..100; normalise to 0..100 for display.
local function pctText(p: number, total: number): string
	local value = if total <= 1.001 then p * 100 else p
	if value < 1 and value > 0 then
		return string.format("%.1f%%", value)
	end
	return string.format("%d%%", math.floor(value + 0.5))
end

return {
	Name = "Breeding",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Breeding Barn",
			Color = C.Pink,
			Size = UDim2.fromOffset(1040, 520),
			OnClose = function()
				ctx.Router:Close("Breeding")
			end,
		})

		local selA: string? = nil
		local selB: string? = nil
		local pod = 1
		local isOpen = false
		local bag = Util.bag()
		local refresh

		local function data()
			return ctx.Store:Get("profile.Breeding") or {}
		end
		local function podCount(): number
			local s = ctx.Store:Get("session.Breeding")
			return math.clamp((s and s.podCount) or BreedingConfig.Pods.base, 1, BreedingConfig.Pods.max)
		end
		local function breedsPerDay(): number
			local s = ctx.Store:Get("session.Breeding")
			return (s and s.breedsPerDay) or BreedingConfig.BreedsPerDay
		end
		local function breedsLeft(id: string): number
			local daily = data().daily
			local used = 0
			if type(daily) == "table" and daily.day == Util.day(ctx) and type(daily.counts) == "table" then
				used = daily.counts[id] or 0
			end
			return math.max(0, breedsPerDay() - used)
		end
		local function podData(i: number)
			local pods = data().pods
			return if type(pods) == "table" then pods[i] else nil
		end
		local function isRunning(p): boolean
			return p ~= nil and p ~= false and p.state == "running"
		end

		-- Layout -------------------------------------------------------------------------------

		local podBar = New("Frame", {
			Name = "Pods",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 60),
			Parent = panel.Body,
		}, { Create.List("x", 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })

		local main = New("Frame", {
			Name = "Main",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 70),
			Size = UDim2.new(1, 0, 1, -70),
			Parent = panel.Body,
		})
		local cardA = Util.card({ Name = "ParentA", Size = UDim2.new(0, 210, 1, 0), Parent = main })
		Create.Text({
			Text = "♥",
			TextSize = 44,
			TextColor3 = C.Pink,
			Stroke = true,
			Position = UDim2.new(0, 214, 0.5, -30),
			Size = UDim2.fromOffset(40, 60),
			Parent = main,
		})
		local cardB = Util.card({ Name = "ParentB", Position = UDim2.fromOffset(258, 0), Size = UDim2.new(0, 210, 1, 0), Parent = main })
		local preview = Util.card({ Name = "Preview", Position = UDim2.fromOffset(480, 0), Size = UDim2.new(1, -480, 1, 0), Parent = main })

		-- Actions ---------------------------------------------------------------------------------

		local function pickParent(which: string)
			local other = if which == "a" then selB else selA
			Util.pick(ctx, {
				title = "Choose a parent",
				max = 1,
				filter = function(m)
					return m.stage == 3 and not m.busy and m.id ~= other and breedsLeft(m.id) > 0
				end,
				returnTo = "Breeding",
				onPick = function(ids)
					if which == "a" then
						selA = ids[1]
					else
						selB = ids[1]
					end
					if refresh then
						refresh()
					end
				end,
			})
		end

		local function claim(i: number)
			local ok, res = Util.requestOnce(ctx, "Breeding.Claim", { pod = i })
			if not ok or type(res) ~= "table" then
				return
			end
			local ap = Util.appearance(res.monster)
			Dialog.show(ctx.UI.Top, {
				Title = if res.hybridDiscovered then "New hybrid discovered!" else "A new monster!",
				Color = if res.hybridDiscovered then C.Purple else C.Pink,
				Size = Vector2.new(480, 380),
				Build = function(content)
					if ap then
						local icon = MonsterIcon.new(ap, 130)
						icon.LayoutOrder = 1
						icon.Parent = content
						Util.text({
							Text = ap.name,
							Font = Theme.Fonts.Display,
							TextSize = Theme.TextSize.Header,
							TextXAlignment = Enum.TextXAlignment.Center,
							Size = UDim2.new(1, 0, 0, 30),
							LayoutOrder = 2,
							Parent = content,
						})
						Util.tagChips(ap, content, 3)
					end
				end,
				Buttons = { { Text = "Nice!", Color = C.Green } },
			})
			ctx:Sound("HatchRare")
		end

		local function cancel(i: number)
			Dialog.confirm(ctx.UI.Top, {
				Title = "Cancel breeding?",
				Text = "The parents come back, but the fee is not refunded.",
				ConfirmText = "Cancel breeding",
				ConfirmColor = C.Red,
				CancelText = "Keep going",
				OnConfirm = function()
					local ok = Util.requestOnce(ctx, "Breeding.Cancel", { pod = i })
					if ok then
						ctx:Toast("Breeding cancelled", "info")
					end
				end,
			})
		end

		-- Drawing ---------------------------------------------------------------------------------

		local function drawPods()
			Util.clear(podBar)
			local now = ctx:Now()
			for i = 1, BreedingConfig.Pods.max do
				local p = podData(i)
				local locked = i > podCount()
				local card = New("TextButton", {
					Name = "Pod" .. i,
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = if locked then C.PanelDeep else C.Card,
					Size = UDim2.fromOffset(360, 56),
					LayoutOrder = i,
					Parent = podBar,
				}, { Create.Corner(Theme.Radius.Card), Create.Stroke(if i == pod then 4 else 2.5, if i == pod then C.Gold else C.Ink) })
				card.Activated:Connect(function()
					if locked then
						ctx:Toast("Get the Breeding Pod pass for a second pod", "info")
						return
					end
					pod = i
					refresh()
				end)
				local label = Util.text({
					Text = "",
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body,
					Position = UDim2.fromOffset(12, 0),
					Size = UDim2.new(1, -140, 1, 0),
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextWrapped = false,
					Parent = card,
				})
				if locked then
					label.Text = string.format("Pod %d · Breeding Pod pass", i)
					label.TextColor3 = C.TextMuted
				elseif isRunning(p) then
					local done = (p.endsAt or 0) <= now
					if done then
						label.Text = string.format("Pod %d · Ready!", i)
						label.TextColor3 = C.Green
						Button.new({
							Text = "Claim",
							Color = C.Green,
							Size = UDim2.fromOffset(118, 44),
							TextSize = Theme.TextSize.Body,
							AnchorPoint = Vector2.new(1, 0.5),
							Position = UDim2.new(1, -6, 0.5, 0),
							Parent = card,
							OnClick = function()
								claim(i)
							end,
						})
					else
						label.Text = string.format("Pod %d · %s", i, Format.clock((p.endsAt or 0) - now))
						Widgets.Countdown(label, function()
							return p.endsAt
						end, function(left)
							return string.format("Pod %d · %s", i, Format.clock(left))
						end, function()
							if isOpen then
								refresh()
							end
						end)
						Button.new({
							Text = "Cancel",
							Color = C.Red,
							Size = UDim2.fromOffset(118, 44),
							TextSize = Theme.TextSize.Body,
							AnchorPoint = Vector2.new(1, 0.5),
							Position = UDim2.new(1, -6, 0.5, 0),
							Parent = card,
							OnClick = function()
								cancel(i)
							end,
						})
					end
				else
					label.Text = string.format("Pod %d · Empty", i)
					label.TextColor3 = C.TextMuted
				end
			end
			Util.text({
				Text = string.format("Each Adult can breed %d× per day", breedsPerDay()),
				TextColor3 = C.TextMuted,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				TextWrapped = false,
				LayoutOrder = 10,
				Parent = podBar,
			})
		end

		local function drawParent(card: Frame, m, which: string, editable: boolean)
			Util.clear(card)
			local content = New("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Parent = card,
			}, { Create.Padding(10, 10, 10, 10), Create.List("y", 6, Enum.HorizontalAlignment.Center) })
			if editable then
				content.Activated:Connect(function()
					pickParent(which)
				end)
			end
			local ap = m and Util.appearance(m)
			if not ap then
				Create.Text({
					Text = "+",
					TextSize = 64,
					TextColor3 = C.TextMuted,
					Stroke = false,
					Size = UDim2.new(1, 0, 0, 150),
					LayoutOrder = 1,
					Parent = content,
				})
				Util.text({
					Text = if editable then "Choose an Adult parent" else "Empty",
					TextXAlignment = Enum.TextXAlignment.Center,
					TextColor3 = C.TextMuted,
					Size = UDim2.new(1, 0, 0, 44),
					LayoutOrder = 2,
					Parent = content,
				})
				return
			end
			local icon = MonsterIcon.new(ap, 112)
			icon.LayoutOrder = 1
			icon.Parent = content
			Util.text({
				Text = ap.name,
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body + 1,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = 2,
				Parent = content,
			})
			local chips = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 26),
				LayoutOrder = 3,
				Parent = content,
			}, { Create.List("x", 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
			Widgets.RarityChip(ap.rarity, chips)
			if ap.muts[1] then
				Widgets.MutationChip(ap.muts[1], chips)
			else
				Widgets.ElementChip(ap.elements[1], chips)
			end
			local traits = {}
			for _, t in m.traits or {} do
				local def = Config.Traits.ById[t]
				if def then
					table.insert(traits, def.name)
				end
			end
			Util.text({
				Text = if #traits > 0 then table.concat(traits, " · ") else " ",
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = 4,
				Parent = content,
			})
			Util.text({
				Text = string.format("Breeds left today: %d", breedsLeft(m.id)),
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = 5,
				Parent = content,
			})
			if editable then
				Button.new({
					Text = "Change",
					Color = C.Blue,
					Size = UDim2.new(1, 0, 0, 44),
					TextSize = Theme.TextSize.Body,
					LayoutOrder = 6,
					Parent = content,
					OnClick = function()
						pickParent(which)
					end,
				})
			end
		end

		local function drawPreview(a, b, running)
			Util.clear(preview)
			local content = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Parent = preview,
			}, { Create.Padding(10, 14, 10, 14), Create.List("y", 8) })
			local function title(text, order)
				return Util.text({
					Text = text,
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Body + 2,
					Size = UDim2.new(1, 0, 0, 26),
					LayoutOrder = order,
					Parent = content,
				})
			end

			if not a or not b then
				title("Possible offspring", 1)
				Util.text({
					Text = "Pick two Adults to see every possible outcome, the time and the fee.\nMatching the right elements can make a hybrid!",
					TextColor3 = C.TextMuted,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(1, 0, 0, 40),
					LayoutOrder = 2,
					Parent = content,
				})
				return
			end

			local o = outcomes(a, b)
			local discovered = data().discovered or {}
			title("Possible offspring", 1)

			local speciesRow = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 112),
				LayoutOrder = 2,
				Parent = content,
			}, { Create.List("x", 12, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
			local total = 0
			for _, sp in o.species or {} do
				total += sp.pct or 0
			end
			for i, sp in o.species or {} do
				local cell = New("Frame", {
					BackgroundColor3 = C.PanelDeep,
					Size = UDim2.fromOffset(110, 110),
					LayoutOrder = i,
					Parent = speciesRow,
				}, { Create.Corner(Theme.Radius.Card), Create.Stroke(2, if sp.hybrid then C.Purple else C.Line) })
				local known = not sp.hybrid or discovered[sp.line] == true
				local icon
				if known and Config.Species.ById[sp.line] then
					local ok, ap = pcall(Appearance.Preview, sp.line, 1)
					icon = if ok then MonsterIcon.new(ap, 76) else MonsterIcon.silhouette(sp.line, 76)
				else
					icon = MonsterIcon.silhouette(sp.line, 76)
					Create.Text({
						Text = "?",
						TextSize = 44,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.4),
						Size = UDim2.fromOffset(60, 60),
						ZIndex = 12,
						Parent = cell,
					})
				end
				icon.AnchorPoint = Vector2.new(0.5, 0)
				icon.Position = UDim2.new(0.5, 0, 0, 4)
				icon.Parent = cell
				Util.text({
					Text = string.format("%s %s", if known then lineName(sp.line) else "Hybrid", pctText(sp.pct or 0, total)),
					TextSize = Theme.TextSize.Small,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextWrapped = false,
					Position = UDim2.new(0, 2, 1, -26),
					Size = UDim2.new(1, -4, 0, 22),
					Parent = cell,
				})
			end

			-- Rarity bars
			local rarityRow = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 22),
				LayoutOrder = 3,
				Parent = content,
			})
			Util.text({ Text = "Rarity", Size = UDim2.new(0, 90, 1, 0), Parent = rarityRow })
			local bar = New("Frame", {
				BackgroundColor3 = C.PanelDeep,
				Position = UDim2.fromOffset(90, 0),
				Size = UDim2.new(1, -90, 1, 0),
				ClipsDescendants = true,
				Parent = rarityRow,
			}, { Create.Round(), Create.Stroke(2), Create.List("x", 0) })
			local rTotal = 0
			for _, r in o.rarity or {} do
				rTotal += r.pct or 0
			end
			local parts = {}
			for i, r in o.rarity or {} do
				local frac = if rTotal > 0 then (r.pct or 0) / rTotal else 0
				New("Frame", {
					BackgroundColor3 = Theme.Rarity(r.rarity),
					BorderSizePixel = 0,
					Size = UDim2.fromScale(frac, 1),
					LayoutOrder = i,
					Parent = bar,
				})
				table.insert(parts, string.format("%s %s", Theme.RarityName(r.rarity), pctText(r.pct or 0, rTotal)))
			end
			Util.text({
				Text = table.concat(parts, " · "),
				TextColor3 = C.TextMuted,
				Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = 4,
				Parent = content,
			})

			-- Mutations and variants
			local mutNames = {}
			for _, m in { a, b } do
				for _, id in m.muts or {} do
					local def = Config.Mutations.ById[id]
					local name = if def then def.name else id
					if not table.find(mutNames, name) then
						table.insert(mutNames, name)
					end
				end
			end
			local mutText
			if (o.mutationChance or 0) > 0 and #mutNames > 0 then
				mutText = string.format("Mutation: %s to inherit %s", Format.percent(o.mutationChance), table.concat(mutNames, " or "))
			else
				mutText = "Mutation: none to inherit"
			end
			local extras = {}
			if (o.goldenChance or 0) > 0 then
				table.insert(extras, "Golden " .. Format.percent(o.goldenChance, 1))
			end
			if (o.rainbowChance or 0) > 0 then
				table.insert(extras, "Rainbow " .. Format.percent(o.rainbowChance, 1))
			end
			if #extras > 0 then
				mutText ..= " · " .. table.concat(extras, " · ")
			end
			Util.text({ Text = mutText, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 5, Parent = content })

			-- Time, fee and the action (bottom of the card).
			local footer = New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 14, 1, -8),
				Size = UDim2.new(1, -28, 0, 56),
				Parent = preview,
			})
			local coins = ctx.Store:Get("profile.Currency.coins") or 0
			local fee = o.fee or 0
			local info = Util.text({
				Text = string.format("%s · fee %s coins", Format.duration(o.seconds or 0), Format.commas(fee)),
				TextColor3 = if coins >= fee then C.Text else C.Red,
				Size = UDim2.new(1, -236, 1, 0),
				Parent = footer,
			})
			if running then
				local p = running
				local done = (p.endsAt or 0) <= ctx:Now()
				info.Text = if done then "Ready to claim!" else "Breeding…"
				local timer = Util.text({
					Text = "",
					Font = Theme.Fonts.Display,
					TextSize = Theme.TextSize.Header,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Size = UDim2.fromOffset(220, 54),
					TextXAlignment = Enum.TextXAlignment.Center,
					Parent = footer,
				})
				if done then
					timer:Destroy()
					Button.new({
						Text = "Claim",
						Color = C.Green,
						Size = UDim2.fromOffset(220, 54),
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, 0, 0.5, 0),
						Parent = footer,
						OnClick = function()
							claim(pod)
						end,
					})
				else
					timer.Text = Format.clock((p.endsAt or 0) - ctx:Now())
					Widgets.Countdown(timer, function()
						return p.endsAt
					end)
				end
			else
				local leftA, leftB = breedsLeft(a.id), breedsLeft(b.id)
				local start = Button.new({
					Text = "Start breeding",
					Color = C.Green,
					Size = UDim2.fromOffset(220, 54),
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Disabled = leftA <= 0 or leftB <= 0,
					Parent = footer,
				})
				start:SetOnClick(function()
					if leftA <= 0 or leftB <= 0 then
						ctx:Toast("One parent has no breeds left today", "error")
						return
					end
					local ok = Util.requestOnce(ctx, "Breeding.Start", { pod = pod, a = a.id, b = b.id })
					if ok then
						selA, selB = nil, nil
						ctx:Toast("Breeding started!", "success")
					end
				end)
			end
		end

		local lockOverlay = nil
		local function draw()
			if not isOpen then
				return
			end
			if lockOverlay then
				lockOverlay:Destroy()
				lockOverlay = nil
			end
			pod = math.clamp(pod, 1, podCount())
			local list = Util.monsters(ctx)
			-- Drop selections that are no longer valid (sold, busy, traded…).
			local function valid(id)
				local m = id and list[id]
				return m ~= nil and m.stage == 3 and not m.busy
			end
			if not valid(selA) then
				selA = nil
			end
			if not valid(selB) or selB == selA then
				selB = nil
			end
			drawPods()
			local p = podData(pod)
			if isRunning(p) then
				local a = p.a and list[p.a]
				local b = p.b and list[p.b]
				drawParent(cardA, a, "a", false)
				drawParent(cardB, b, "b", false)
				if a and b then
					drawPreview(a, b, p)
				else
					drawPreview(nil, nil, nil)
				end
			else
				local a = selA and list[selA]
				local b = selB and list[selB]
				drawParent(cardA, a, "a", true)
				drawParent(cardB, b, "b", true)
				drawPreview(a, b, nil)
			end
			if not Util.unlocked(ctx, BreedingConfig.Unlock) then
				lockOverlay = Util.lockOverlay(panel.Body, Util.unlockText(BreedingConfig.Unlock))
			end
		end
		refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				bag.clean()
				for _, path in
					{
						"profile.Breeding",
						"session.Breeding",
						"profile.Monsters.list",
						"profile.Progression.level",
						"profile.Currency.coins",
					}
				do
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
