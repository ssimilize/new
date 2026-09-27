--[[
	Merchant (update 3.11 · Travelling Merchant): this visit's stock. Opened from the caravan's
	"Trade" prompt in the Market Square (Controllers/Merchant) and the Events screen's "Go".

	  header  "The merchant leaves in 43m" while the caravan is here, else "Back in 1h 12m";
	          the Trait Scrolls owned (spent from Monster Detail's "Reroll trait")
	  body    while present: one card per offer (Logic/Merchant.Stock, the same for everyone): name,
	          what it does, "Bought n/limit" and one button per way to pay ("Pay 1,200 Coins",
	          "Pay 3 Fish"); a locked offer shows what unlocks it. Away: when it returns.
	Before Ranch Level Config.Unlocks.Features.merchant a lock covers the body.

	Reads: profile.Merchant, session.Merchant, session.Ranch.income, profile.Progression.level.
	Actions: Merchant.Buy { offer, pay }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Logic = require(Shared.Logic.Merchant)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors
local Rules = Config.Merchant

local KIND_COLOR = {
	scroll = "#8B6AD8",
	seeds = "#F4C43A",
	bait = "#4FB6F2",
	shovels = "#A0703D",
	tower_retry = "#8A8FA3",
	decor = "#EF6FA8",
	egg = "#43B649",
}
local PAY_COLOR = { coins = C.Green, gems = C.Pink, amber = C.Orange, fish = C.Blue, dishes = C.Purple }

return {
	Name = "Merchant",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Travelling Merchant",
			Color = C.Purple,
			Size = UDim2.fromOffset(940, 540),
			OnClose = function()
				ctx.Router:Close("Merchant")
			end,
		})

		local isOpen = false
		local bag = Util.bag()
		local lock = nil
		local shownPresent = nil

		local status = Util.text({
			Name = "Status",
			Text = "",
			Font = Theme.Fonts.Display,
			TextSize = Theme.TextSize.Body + 2,
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -260, 0, 30),
			Parent = panel.Body,
		})
		local scrolls = Util.text({
			Name = "Scrolls",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 4),
			Size = UDim2.fromOffset(240, 26),
			Parent = panel.Body,
		})
		local grid = New("Frame", {
			Name = "Stock",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 38),
			Size = UDim2.new(1, 0, 1, -38),
			Parent = panel.Body,
		}, {
			New("UIGridLayout", {
				CellSize = UDim2.new(1 / 3, -8, 0.5, -8),
				CellPadding = UDim2.fromOffset(8, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local closed = Util.text({
			Name = "Closed",
			Text = "",
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(20, 120),
			Size = UDim2.new(1, -40, 0, 80),
			Parent = panel.Body,
		})

		local function profile()
			local p = ctx.Store:Get("profile.Merchant")
			return if type(p) == "table" then p else {}
		end

		local function income(): number
			return tonumber(ctx.Store:Get("session.Ranch.income")) or 0
		end

		local function shovelsOpen(): boolean
			return ctx.Store:Get("session.Merchant.shovels") == true
		end

		local draw -- set below

		local function buy(offerId: string, index: number)
			local ok, res = Util.request(ctx, "Merchant.Buy", { offer = offerId, pay = index })
			if ok and type(res) == "table" then
				local slot = Logic.Find(Logic.At(ctx:Now()).visit, offerId)
				ctx:Sound("CoinCollect")
				ctx:Toast(string.format("Bought %s", if slot then slot.name else offerId), "reward")
			end
			draw()
		end

		local function card(slot, order: number, visit: number)
			local p = profile()
			local bought = if p.visit == visit and type(p.bought) == "table" then tonumber(p.bought[slot.offer]) or 0 else 0
			local frame = Util.card({ Name = "Offer_" .. slot.offer, LayoutOrder = order, Parent = grid })
			New("Frame", {
				Name = "Badge",
				BackgroundColor3 = Color3.fromHex(KIND_COLOR[slot.kind] or "#A7A29A"),
				Position = UDim2.fromOffset(10, 10),
				Size = UDim2.fromOffset(34, 34),
				Parent = frame,
			}, { Create.Corner(10), Create.Stroke(2) })
			Util.text({
				Name = "Name",
				Text = slot.name,
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body,
				Position = UDim2.fromOffset(52, 6),
				Size = UDim2.new(1, -110, 0, 24),
				Parent = frame,
			})
			local amount = Util.text({
				Name = "Amount",
				Text = string.format("×%d", slot.amount),
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 6),
				Size = UDim2.fromOffset(52, 24),
				Parent = frame,
			})
			amount:SetAttribute("Localize", false)
			Util.text({
				Name = "Limit",
				Text = string.format("%d/%d bought this visit", bought, slot.limit),
				TextColor3 = C.TextMuted,
				TextSize = Theme.TextSize.Small,
				Position = UDim2.fromOffset(52, 28),
				Size = UDim2.new(1, -60, 0, 20),
				Parent = frame,
			})
			Util.text({
				Name = "Desc",
				Text = slot.desc or "",
				TextWrapped = true,
				TextSize = Theme.TextSize.Small,
				Position = UDim2.fromOffset(10, 50),
				Size = UDim2.new(1, -20, 0, 40),
				Parent = frame,
			})
			local blocked = nil
			if slot.unlock and Config.Unlocks.Features[slot.unlock] and not Util.unlocked(ctx, slot.unlock) then
				blocked = Util.unlockText(slot.unlock)
			elseif slot.kind == "shovels" and not shovelsOpen() then
				blocked = "Needs the Dig Site"
			elseif bought >= slot.limit then
				blocked = "Sold out for you this visit"
			end
			if blocked then
				Util.text({
					Name = "Blocked",
					Text = blocked,
					TextWrapped = true,
					TextColor3 = C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 10, 1, -10),
					Size = UDim2.new(1, -20, 0, 44),
					Parent = frame,
				})
				return
			end
			for i, pay in slot.pay do
				local price = Logic.PayAmount(pay, income())
				Button.new({
					Name = "Pay" .. i,
					Text = Logic.PayText(pay, price),
					Color = PAY_COLOR[pay.kind] or C.Green,
					TextSize = Theme.TextSize.Small,
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 10, 1, if i == 1 and #slot.pay > 1 then -52 else -8),
					Size = UDim2.new(1, -20, 0, 40),
					Parent = frame,
					OnClick = function()
						buy(slot.offer, i)
					end,
				})
			end
		end

		draw = function()
			if not isOpen then
				return
			end
			local now = ctx:Now()
			local at = Logic.At(now)
			shownPresent = at.present
			scrolls.Text = string.format("Trait Scrolls: %d", tonumber(profile().scrolls) or 0)
			Util.clear(grid)
			grid.Visible = at.present
			closed.Visible = not at.present
			if at.present then
				for i, slot in Logic.Stock(at.visit) do
					card(slot, i, at.visit)
				end
			else
				closed.Text = "The caravan has moved on. It parks in the Market Square for 2 hours every 6 hours."
			end
			if lock then
				lock:Destroy()
				lock = nil
			end
			if not Util.unlocked(ctx, Rules.Unlock) then
				lock = Util.lockOverlay(panel.Body, Util.unlockText(Rules.Unlock))
			end
		end
		local refresh = Util.debounce(draw)

		return {
			Root = panel.Root,
			Open = function()
				isOpen = true
				bag.clean()
				for _, path in { "profile.Merchant", "session.Merchant", "session.Ranch.income", "profile.Progression.level" } do
					bag.add(ctx.Store:Observe(path, refresh))
				end
				draw()
				status.Text = ""
				bag.add(Widgets.Countdown(status, function()
					local at = Logic.At(ctx:Now())
					return if at.present then at.endsAt else at.nextAt
				end, function(left: number)
					local present = Logic.At(ctx:Now()).present
					if present ~= shownPresent then
						refresh()
					end
					return if present
						then string.format("The merchant leaves in %s", Format.duration(left))
						else string.format("Back in %s", Format.duration(left))
				end))
			end,
			Close = function()
				isOpen = false
				bag.clean()
			end,
		}
	end,
}
