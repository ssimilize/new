--[[
	Parts/Util: helpers shared by the C3 screens and controllers.

	  Util.bag()                       cleanup bag: add(conn | fn | Instance | {Disconnect}) / clean()
	  Util.request(ctx, action, p)     ctx.Net:Request with an error toast on failure
	  Util.requestOnce(ctx, action, p) same with double-tap protection
	  Util.debounce(fn)                coalesces many calls in one frame into one deferred call
	  Util.logic(name)                 lazy, pcall-guarded require of Shared.Logic.<name> (nil if missing)
	  Util.level(ctx) / unlocked(ctx, key) / unlockText(key)
	  Util.text(props)                 dark body text for cream panels
	  Util.clear(frame)                destroys GuiObject children (keeps layouts)
	  Util.rewardText(item) / rewardIcon(item, size) / rewardRow(items, parent, opts)
	  Util.valueLines(appearance)      value facts as text lines { { text, color } }
	  Util.tagChips(appearance, parent) every value tag as chips
	  Util.appearance(monster)         Appearance.Of, nil when the species is unknown
	  Util.monsters(ctx)               profile.Monsters.list or {}
	  Util.day(ctx)                    UTC day number
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Appearance = require(Shared.Logic.Appearance)

local UI = script.Parent.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Icon = require(UI.Components.Icon)
local MonsterIcon = require(UI.Components.MonsterIcon)
local Widgets = require(UI.Components.Widgets)
local StoreKit = require(UI.Components.StoreKit)
local ShowpieceChips = require(script.Parent.ShowpieceChips) -- glow-up W

local New = Create.New
local C = Theme.Colors

local Util = {}

-- Cleanup --------------------------------------------------------------------------

function Util.bag()
	local items = {}
	local bag = {}
	function bag.add(item)
		table.insert(items, item)
		return item
	end
	function bag.clean()
		local list = items
		items = {}
		for _, item in list do
			local t = typeof(item)
			if t == "function" then
				pcall(item)
			elseif t == "RBXScriptConnection" then
				item:Disconnect()
			elseif t == "Instance" then
				item:Destroy()
			elseif t == "table" and item.Disconnect then
				pcall(item.Disconnect, item)
			end
		end
	end
	return bag
end

function Util.debounce(fn: () -> ())
	local pending = false
	return function()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			fn()
		end)
	end
end

-- Requests -------------------------------------------------------------------------

local function toastError(ctx, err)
	if err == "Busy" then
		return
	end
	ctx:Toast(StoreKit.errorText(err), "error")
end

function Util.request(ctx, action: string, payload: any?): (boolean, any)
	local ok, res = ctx.Net:Request(action, payload)
	if not ok then
		toastError(ctx, res)
	end
	return ok, res
end

function Util.requestOnce(ctx, action: string, payload: any?): (boolean, any)
	local ok, res = ctx.Net:RequestOnce(action, payload)
	if not ok then
		toastError(ctx, res)
	end
	return ok, res
end

-- Logic modules written in parallel by other workstreams: required lazily and guarded.
local logicCache = {}
function Util.logic(name: string)
	if logicCache[name] then
		return logicCache[name]
	end
	local ok, mod = pcall(function()
		local inst = Shared.Logic:FindFirstChild(name)
		return if inst then require(inst) else nil
	end)
	if ok and type(mod) == "table" then
		logicCache[name] = mod
		return mod
	end
	return nil
end

-- Progress -------------------------------------------------------------------------

function Util.level(ctx): number
	return ctx.Store:Get("profile.Progression.level") or 1
end

function Util.unlockLevel(key: string): number
	return Config.Unlocks.Features[key] or 1
end

function Util.unlocked(ctx, key: string): boolean
	return Util.level(ctx) >= Util.unlockLevel(key)
end

function Util.unlockText(key: string): string
	return string.format("Unlocks at Ranch Level %d", Util.unlockLevel(key))
end

function Util.day(ctx): number
	return math.floor(ctx:Now() / 86400)
end

function Util.monsters(ctx)
	return ctx.Store:Get("profile.Monsters.list") or {}
end

function Util.appearance(m)
	if not m or not Config.Species.ById[m.line] then
		return nil
	end
	local ok, ap = pcall(Appearance.Of, m)
	return if ok then ap else nil
end

-- Text -----------------------------------------------------------------------------

function Util.text(props)
	local merged = {
		Font = Theme.Fonts.Body,
		TextColor3 = C.Text,
		Stroke = false,
		TextSize = Theme.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in props do
		merged[k] = v
	end
	return Create.Text(merged)
end

function Util.clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Rewards --------------------------------------------------------------------------

local function eggName(id)
	local def = id and Config.Eggs.ById[id]
	return if def then def.name else "Egg"
end

function Util.rewardText(item): string
	if item.label then
		return item.label
	end
	local kind = item.kind
	local amount = item.amount or 0
	if kind == "coins" then
		if (item.amount == nil or item.amount == 0) and item.seconds then
			return Format.duration(item.seconds) .. " of coins"
		end
		return Format.short(amount)
	elseif kind == "food" then
		local f = item.id and Config.Food.ById[item.id]
		return string.format("%s %s", Format.short(amount), if f then f.name else "Food")
	elseif kind == "xp" then
		return Format.short(amount) .. " XP"
	elseif kind == "egg" then
		return if amount > 1 then string.format("%s ×%d", eggName(item.id), amount) else eggName(item.id)
	elseif kind == "decor" then
		local d = item.id and Config.Decor.ById[item.id]
		return if d then d.name else "Decor"
	elseif kind == "monster" then
		local line = item.id and Config.Species.ById[item.id]
		local form = line and line.forms[1]
		local name = if form then form.name else "Monster"
		return if item.rarity then string.format("%s %s", Theme.RarityName(item.rarity), name) else name
	elseif kind == "token" then
		return Format.short(amount) .. " tokens"
	elseif kind == "accessory" then
		local a = item.id and Config.Accessories and Config.Accessories.ById[item.id]
		return if a then a.name else "Accessory"
	elseif kind == "ribbons" then
		return Format.short(amount) .. " Ribbons"
	end
	return Format.short(amount)
end

function Util.rewardIcon(item, size: number): GuiObject
	if item.kind == "egg" and item.id and Config.Eggs.ById[item.id] then
		return MonsterIcon.egg(item.id, size)
	elseif item.kind == "monster" and item.id and Config.Species.ById[item.id] then
		local ok, ap = pcall(Appearance.Preview, item.id, 1, nil, item.rarity)
		if ok then
			return MonsterIcon.new(ap, size)
		end
	end
	return Icon.new(Icon.forReward(item.kind), size)
end

-- A horizontal row of reward chips. opts: { Size, LayoutOrder, IconSize, TextSize, Light, Align, Position }
function Util.rewardRow(items, parent: Instance?, opts)
	opts = opts or {}
	local iconSize = opts.IconSize or 24
	local row = New("Frame", {
		Name = "Rewards",
		BackgroundTransparency = 1,
		Size = opts.Size or UDim2.new(1, 0, 0, iconSize + 6),
		Position = opts.Position or UDim2.new(),
		LayoutOrder = opts.LayoutOrder or 0,
		Parent = parent,
	}, { Create.List("x", 12, opts.Align or Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	for i, item in items or {} do
		local chip = New("Frame", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = i,
			Parent = row,
		}, { Create.List("x", 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
		local icon = Util.rewardIcon(item, iconSize)
		icon.LayoutOrder = 1
		icon.Parent = chip
		local textProps = {
			Text = Util.rewardText(item),
			TextSize = opts.TextSize or Theme.TextSize.Small,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			TextWrapped = false,
			LayoutOrder = 2,
			Parent = chip,
		}
		if opts.Light then
			textProps.Font = Theme.Fonts.Display
			Create.Text(textProps)
		else
			Util.text(textProps)
		end
	end
	return row
end

-- Value tags ------------------------------------------------------------------------

function Util.isHuge(ap): boolean
	local def = ap and Config.Species.ById[ap.line]
	if not def or not ap.weight then
		return false
	end
	return ap.weight >= def.weight * Config.Social.HugeWeightMult
end

local function stars(n: number): string
	return string.rep("★", math.clamp(n or 1, 1, 5))
end

-- Every fact that sets a monster's trade value, as short coloured text lines.
function Util.valueLines(ap)
	local lines = {}
	local rarity = Theme.RarityName(ap.rarity or 1)
	local variant = Config.Rarities.Variants[ap.variant or 0]
	local first = rarity
	if variant and (ap.variant or 0) > 0 then
		first ..= " · " .. variant.name
	end
	table.insert(lines, { text = first, color = Theme.Rarity(ap.rarity or 1) })
	local muts = {}
	for _, id in ap.muts or {} do
		local def = Config.Mutations.ById[id]
		table.insert(muts, if def then def.name else id)
	end
	if #muts > 0 then
		table.insert(lines, { text = table.concat(muts, ", "), color = Theme.Mutation(ap.muts[1]) })
	end
	table.insert(lines, { text = string.format("Lv %d %s", ap.lv or 1, stars(ap.stars)), color = C.Text })
	if ap.weight then
		local w = Format.weight(ap.weight)
		local size = ShowpieceChips.sizeTag(ap)
		local text = if size == "TITANIC" then w .. " · Titanic" elseif size == "HUGE" then w .. " · Huge" else w
		table.insert(lines, { text = text, color = C.TextMuted })
	end
	if type(ap.ltdNo) == "number" then -- glow-up W: limited edition number
		table.insert(lines, { text = string.format("Limited edition #%d of %d", ap.ltdNo, tonumber(ap.ltdOf) or 0), color = C.Purple })
	end
	return lines
end

-- Every value tag as chips in a wrapping row.
function Util.tagChips(ap, parent: Instance, layoutOrder: number?)
	local row = New("Frame", {
		Name = "Tags",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = layoutOrder or 0,
		Parent = parent,
	})
	local layout = Create.List("x", 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	pcall(function()
		(layout :: any).Wraps = true
	end)
	layout.Parent = row
	Widgets.RarityChip(ap.rarity or 1, row)
	Widgets.VariantChip(ap.variant or 0, row)
	for _, id in ap.muts or {} do
		Widgets.MutationChip(id, row)
	end
	for _, e in ap.elements or {} do
		Widgets.ElementChip(e, row)
	end
	if ap.weight then
		Widgets.Chip({ Text = Format.weight(ap.weight), Color = C.PanelDeep, Parent = row })
		if Util.isHuge(ap) and ap.titanic ~= true then
			Widgets.Chip({ Text = "HUGE", Color = C.Orange, Parent = row })
		end
	end
	ShowpieceChips.add(ap, row) -- glow-up W: TITANIC, #37/500
	Widgets.Chip({ Text = "Lv " .. tostring(ap.lv or 1), Color = C.Blue, Parent = row })
	Widgets.Chip({ Text = stars(ap.stars), Color = C.Gold, Parent = row })
	return row
end

-- Small pieces --------------------------------------------------------------------

-- A white card with a title label; returns (card, titleLabel).
function Util.card(props)
	local card = New("Frame", {
		Name = props.Name or "Card",
		BackgroundColor3 = props.Color or C.Card,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { Create.Corner(Theme.Radius.Card), Create.Stroke(Theme.Stroke.Card) })
	local title
	if props.Title then
		title = Util.text({
			Name = "Title",
			Text = props.Title,
			Font = Theme.Fonts.Display,
			TextSize = Theme.TextSize.Body + 2,
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -28, 0, 26),
			Parent = card,
		})
	end
	return card, title
end

-- A dark translucent lock overlay covering `parent` with a message.
function Util.lockOverlay(parent: Instance, text: string)
	local overlay = New("TextButton", {
		Name = "Lock",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.Dark,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = parent,
	}, { Create.Corner(Theme.Radius.Card) })
	local lock = Icon.new("lock", 48)
	lock.AnchorPoint = Vector2.new(0.5, 1)
	lock.Position = UDim2.new(0.5, 0, 0.5, -6)
	lock.ZIndex = 21
	lock.Parent = overlay
	for _, d in lock:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 21
		end
	end
	Create.Text({
		Text = text,
		TextSize = Theme.TextSize.Header,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 4),
		Size = UDim2.new(0.9, 0, 0, 60),
		ZIndex = 21,
		Parent = overlay,
	})
	return overlay
end

-- Opens the Monsters screen in pick mode (contract in ARCHITECTURE.md §5).
-- onPick receives a list of ids.
function Util.pick(ctx, opts)
	if not ctx.Router:Has("Monsters") then
		ctx:Toast("Monster list not available yet", "error")
		return
	end
	ctx.Router:Open("Monsters", {
		pick = {
			title = opts.title,
			filter = opts.filter,
			max = opts.max or 1,
			returnTo = opts.returnTo,
			returnParams = opts.returnParams,
			onPick = function(arg)
				local ids = arg
				if type(arg) == "table" and type(arg.ids) == "table" then
					ids = arg.ids
				elseif type(arg) == "string" then
					ids = { arg }
				end
				if type(ids) == "table" and #ids > 0 then
					opts.onPick(ids)
				end
			end,
		},
	})
end

return Util
