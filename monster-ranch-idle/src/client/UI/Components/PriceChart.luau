--[[
	PriceChart (M3, update 1.3 · Market Day): a small daily price chart drawn with Frames only
	(no images), so it reskins through Theme like the rest of the UI kit.

		local chart = PriceChart.new({ Size = UDim2.fromOffset(420, 150), Parent = frame })
		chart:SetSeries(days)   -- { { day, count, low, high, avg } }, oldest first (PriceHistory.Get)
		chart:SetSeries(nil)    -- "No sales yet"
		chart:SetMessage("Loading…")

	One column per UTC day, ending at the newest day with a sale (at least 7 and at most
	Config.Market.HistoryDays columns). Each day with sales draws a thin low–high range and a
	bar up to the average price; days without sales stay empty. The highest price, the last
	average and the sales count are written above the plot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Theme = require(script.Parent.Parent.Theme)
local Create = require(script.Parent.Parent.Create)

local New = Create.New
local C = Theme.Colors

local MIN_COLUMNS = 7
local HEADER = 24

local PriceChart = {}
PriceChart.__index = PriceChart

local function label(props)
	local p = {
		Font = Theme.Fonts.Body,
		TextColor3 = C.TextMuted,
		Stroke = false,
		TextSize = Theme.TextSize.Tiny + 1,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in props do
		p[k] = v
	end
	return Create.Text(p)
end

function PriceChart.new(props: {
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
	LayoutOrder: number?,
	Color: Color3?,
})
	local self = setmetatable({}, PriceChart)
	self._color = props.Color or C.Orange

	local root = New("Frame", {
		Name = "PriceChart",
		BackgroundColor3 = C.Card,
		Size = props.Size or UDim2.fromOffset(420, 150),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ClipsDescendants = true,
		Parent = props.Parent,
	}, { Create.Corner(Theme.Radius.Card), Create.Stroke(2, C.Line), Create.Padding(6, 10, 6, 10) })

	self._high = label({
		Name = "High",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.5, 0, 0, HEADER - 4),
		Parent = root,
	})
	self._summary = label({
		Name = "Summary",
		Text = "",
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, 0, 0, HEADER - 4),
		Parent = root,
	})
	local plot = New("Frame", {
		Name = "Plot",
		BackgroundColor3 = C.PanelDeep,
		BackgroundTransparency = 0.4,
		Position = UDim2.fromOffset(0, HEADER),
		Size = UDim2.new(1, 0, 1, -HEADER),
		Parent = root,
	}, { Create.Corner(6) })
	-- Baseline and a faint mid line to read heights against.
	New("Frame", {
		Name = "Baseline",
		BackgroundColor3 = C.Line,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		Parent = plot,
	})
	New("Frame", {
		Name = "Midline",
		BackgroundColor3 = C.Line,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 1),
		Parent = plot,
	})
	self._bars = New("Frame", { Name = "Bars", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = plot })
	self._message = label({
		Name = "Message",
		Text = "",
		TextSize = Theme.TextSize.Small,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = plot,
	})

	self.Root = root
	self.Plot = plot
	self:SetSeries(nil)
	return self
end

function PriceChart:SetMessage(text: string)
	for _, child in self._bars:GetChildren() do
		child:Destroy()
	end
	self._high.Text = ""
	self._summary.Text = ""
	self._message.Text = text
	self._message.Visible = true
end

-- days: { { day, count, low, high, avg } } with days without sales left out.
function PriceChart:SetSeries(days: { any }?)
	local valid = {}
	for _, d in if type(days) == "table" then days else {} do
		if type(d) == "table" and tonumber(d.day) and (tonumber(d.avg) or 0) > 0 then
			table.insert(valid, d)
		end
	end
	if #valid == 0 then
		self:SetMessage("No sales yet")
		return
	end
	table.sort(valid, function(a, b)
		return a.day < b.day
	end)
	self._message.Visible = false
	for _, child in self._bars:GetChildren() do
		child:Destroy()
	end

	local last = valid[#valid].day
	local span = math.clamp(last - valid[1].day + 1, MIN_COLUMNS, Config.Market.HistoryDays)
	local first = last - span + 1
	local top, sales = 0, 0
	for _, d in valid do
		if d.day >= first then
			top = math.max(top, tonumber(d.high) or d.avg, d.avg)
			sales += tonumber(d.count) or 0
		end
	end
	top = math.max(top, 1)

	local slot = 1 / span
	local barWidth = 0.6
	for _, d in valid do
		if d.day < first then
			continue
		end
		local x = (d.day - first) * slot
		local avg = d.avg / top
		local low = math.clamp((tonumber(d.low) or d.avg) / top, 0, 1)
		local high = math.clamp((tonumber(d.high) or d.avg) / top, 0, 1)
		local column = New("Frame", {
			Name = "Day" .. tostring(d.day),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(x, 0),
			Size = UDim2.fromScale(slot, 1),
			Parent = self._bars,
		})
		if high > low then
			New("Frame", {
				Name = "Range",
				BackgroundColor3 = C.Ink,
				BackgroundTransparency = 0.55,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 1 - low),
				Size = UDim2.new(0, 2, high - low, 0),
				ZIndex = 3,
				Parent = column,
			})
		end
		New("Frame", {
			Name = "Bar",
			BackgroundColor3 = self._color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(barWidth, 0, math.clamp(avg, 0.03, 1), 0),
			ZIndex = 2,
			Parent = column,
		}, { Create.Corner(3) })
	end

	local newest = valid[#valid]
	self._high.Text = "High " .. Format.short(math.floor(top))
	self._summary.Text = string.format(
		"Last avg %s · %d sale%s in %dd",
		Format.short(math.floor(newest.avg + 0.5)),
		sales,
		if sales == 1 then "" else "s",
		span
	)
end

function PriceChart:Destroy()
	self.Root:Destroy()
end

return PriceChart
