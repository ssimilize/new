--[[
	TradeRequests controller (C3).

	Trade.Incoming → a popup with Accept / Decline (Trade.Respond); accepting opens the Trade
	screen. The popup closes itself when the request expires or is withdrawn.
	session.Trade.status turning "open" (e.g. your own request was accepted) opens the Trade
	screen. Trade.Completed → a summary popup of what you received.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local UI = script.Parent.Parent.UI
local Create = require(UI.Create)
local Theme = require(UI.Theme)
local MonsterIcon = require(UI.Components.MonsterIcon)
local Util = require(UI.Screens.Parts.Util)
local Dialog = require(UI.Screens.Parts.Dialog)

local New = Create.New
local C = Theme.Colors

local TradeRequests = {
	Name = "TradeRequests",
	Dependencies = {},
}

local ctx
local incoming = nil -- open request dialog
local lastStatus = "none"

local function openTrade()
	if ctx.Router:Has("Trade") and not ctx.Router:IsOpen("Trade") then
		ctx.Router:Open("Trade")
	end
end

local function closeIncoming()
	if incoming then
		incoming.Close()
		incoming = nil
	end
end

local function onIncoming(payload)
	if type(payload) ~= "table" or type(payload.from) ~= "number" then
		return
	end
	closeIncoming()
	local from = payload.from
	local name = payload.name or "Someone"
	local dialog
	dialog = Dialog.show(ctx.UI.Top, {
		Title = "Trade request",
		Color = C.Purple,
		Size = Vector2.new(520, 260),
		Text = string.format("%s wants to trade with you.", name),
		Closable = false,
		Buttons = {
			{
				Text = "Decline",
				Color = C.Red,
				OnClick = function()
					task.spawn(Util.request, ctx, "Trade.Respond", { from = from, accept = false })
				end,
			},
			{
				Text = "Accept",
				Color = C.Green,
				OnClick = function()
					task.spawn(function()
						local ok = Util.request(ctx, "Trade.Respond", { from = from, accept = true })
						if ok then
							openTrade()
						end
					end)
				end,
			},
		},
		OnClose = function()
			if incoming == dialog then
				incoming = nil
			end
		end,
	})
	incoming = dialog
	local timeout = Config.Social.Trade.requestTimeout or 30
	task.delay(timeout, function()
		if incoming == dialog then
			closeIncoming()
		end
	end)
end

local function onCompleted(payload)
	closeIncoming()
	if ctx.Router:IsOpen("Trade") then
		ctx.Router:Close("Trade")
	end
	local received = if type(payload) == "table" and type(payload.received) == "table" then payload.received else {}
	Dialog.show(ctx.UI.Top, {
		Title = "Trade complete!",
		Color = C.Green,
		Size = Vector2.new(640, 360),
		Build = function(content)
			Util.text({
				Text = if #received > 0 then "You received:" else "You didn't receive anything in this trade.",
				TextSize = Theme.TextSize.Body,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 24),
				LayoutOrder = 1,
				Parent = content,
			})
			local grid = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 200),
				LayoutOrder = 2,
				Parent = content,
			}, { Create.Grid(Vector2.new(96, 118), 8) })
			local layout = grid:FindFirstChildOfClass("UIGridLayout")
			if layout then
				layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			end
			for i, item in received do
				if i > 8 then
					break
				end
				local ap = item.appearance
				local cell
				if type(ap) == "table" and Config.Species.ById[ap.line] then
					cell = MonsterIcon.card(ap, 96, ap.name)
				else
					local eggType = item.egg or item.id or item.type
					if type(eggType) ~= "string" or not Config.Eggs.ById[eggType] then
						eggType = "meadow"
					end
					cell = New("Frame", { BackgroundColor3 = C.Card }, { Create.Corner(Theme.Radius.Card), Create.Stroke(3) })
					local egg = MonsterIcon.egg(eggType, 76)
					egg.AnchorPoint = Vector2.new(0.5, 0)
					egg.Position = UDim2.new(0.5, 0, 0, 6)
					egg.Parent = cell
					Util.text({
						Text = Config.Eggs.ById[eggType].name,
						TextXAlignment = Enum.TextXAlignment.Center,
						TextSize = Theme.TextSize.Tiny + 1,
						Position = UDim2.new(0, 2, 1, -26),
						Size = UDim2.new(1, -4, 0, 22),
						Parent = cell,
					})
				end
				cell.LayoutOrder = i
				cell.Parent = grid
			end
		end,
		Buttons = { { Text = "Great!", Color = C.Green } },
	})
	ctx:Sound("TradeDone")
end

function TradeRequests.Init(context)
	ctx = context
	ctx.Net:On("Trade.Incoming", onIncoming)
	ctx.Net:On("Trade.Completed", onCompleted)
	ctx.Store:Observe("session.Trade.status", function(status)
		status = status or "none"
		if status == "open" and lastStatus ~= "open" and lastStatus ~= "countdown" then
			closeIncoming()
			openTrade()
		elseif status == "none" and lastStatus == "incoming" then
			-- The request was withdrawn or expired.
			closeIncoming()
		end
		lastStatus = status
	end)
end

function TradeRequests.Start() end

return TradeRequests
