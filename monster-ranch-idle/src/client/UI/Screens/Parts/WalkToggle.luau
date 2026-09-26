--[[
	WalkToggle (glow-up T): the "Walk with me" / "Stop walking" button on MonsterDetail's portrait.
	It sends Companions.Set with this monster added or removed. With every slot taken, the new
	monster replaces the one that has walked longest (the first in the list), so a free player's
	single slot simply swaps. Hidden while the monster is busy, while it is the ridden mount, and
	when the Companions system isn't there (profile.Companions missing).

		local walk = WalkToggle.new(ctx, parent)
		walk:Refresh(id, monster)        -- from the screen's refresh
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Logic = require(ReplicatedStorage.Shared.Logic.Companions)

local UI = script.Parent.Parent.Parent
local Theme = require(UI.Theme)
local Button = require(UI.Components.Button)
local StoreKit = require(UI.Components.StoreKit)

local C = Theme.Colors

local WalkToggle = {}
WalkToggle.__index = WalkToggle

local function currentIds(store): { string }
	local ids = {}
	for _, id in StoreKit.tbl(store, "profile.Companions.ids") do
		if type(id) == "string" then
			table.insert(ids, id)
		end
	end
	return ids
end

function WalkToggle.new(ctx, parent: Instance)
	local self = setmetatable({ ctx = ctx, id = nil :: string? }, WalkToggle)
	self.button = Button.new({
		Name = "WalkWithMe",
		Text = "Walk with me",
		Color = C.Green,
		TextSize = Theme.TextSize.Small + 1,
		Size = UDim2.fromOffset(170, 44),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		ZIndex = 6,
		Parent = parent,
		OnClick = function()
			self:_toggle()
		end,
	})
	self.button:SetVisible(false)
	return self
end

function WalkToggle:_toggle()
	local ctx, id = self.ctx, self.id
	if not id then
		return
	end
	local ids = currentIds(ctx.Store)
	local at = table.find(ids, id)
	if at then
		table.remove(ids, at)
	else
		local slots = Logic.Slots(StoreKit.hasPass(ctx.Store, Config.Companions.VipPass))
		while #ids >= slots do
			table.remove(ids, 1)
		end
		table.insert(ids, id)
	end
	StoreKit.request(ctx, "Companions.Set", { ids = ids })
end

function WalkToggle:Refresh(id: string?, m: any)
	self.id = id
	local store = self.ctx.Store
	local available = type(store:Get("profile.Companions")) == "table"
	local riding = StoreKit.tbl(store, "session.Riding").mount
	local walking = id ~= nil and table.find(currentIds(store), id) ~= nil
	self.button:SetVisible(available and id ~= nil and type(m) == "table" and not m.busy and riding ~= id)
	self.button:SetText(if walking then "Stop walking" else "Walk with me")
	self.button:SetColor(if walking then C.Orange else C.Green)
end

return WalkToggle
