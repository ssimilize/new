--[[
	Community controller (glow-up L): the way into the emote wheel and the Friends screen, the
	player emotes themselves, and the VIP balcony pads.

	  HUD          two small buttons in the bottom-left corner of ctx.UI.Hud, above the gamepad
	               legend and left of the bottom bar: Emotes (the wheel) and Friends (gifts,
	               invites, rewards). Shown on every device, so touch players have them too.
	  Shortcuts    G on a keyboard and D-pad down on a pad toggle the wheel while no other
	               screen is open (the Gamepad controller binds B / LB / RB / Y; A and X belong
	               to buttons and world prompts).
	  Emotes       Roblox's default emotes on the local character: the Animate script's PlayEmote
	               (the /e animations, Roblox-owned), else Humanoid:PlayEmote. Character animation
	               replicates, so everyone sees them.
	  Tricks       the nearest own pen monster (World.NearestOwn within Config.Community.TrickRange)
	               through Community.Trick; the server tells everyone and World plays it.
	  Balcony      prompts on the parts with attribute VipPad (World/Balcony): "enter" asks
	               Community.Balcony { enter = true }, "exit" { enter = false }.

	Public: Community.PlayEmote(emoteId) -> boolean, Community.Trick(trickId) -> boolean (yields).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Button = require(UI.Components.Button)
local Icon = require(UI.Components.Icon)
local StoreKit = require(UI.Components.StoreKit)

local C = Theme.Colors
local Cfg = Config.Community

local Community = {
	Name = "Community",
	Dependencies = { "World" },
}

local ctx
local tricking = false

local EmoteById = {}
for _, emote in Cfg.Emotes do
	EmoteById[emote.id] = emote
end

local function character(): Model?
	return ctx.Player.Character
end

function Community.PlayEmote(emoteId: string): boolean
	local emote = EmoteById[emoteId]
	local char = character()
	if not emote or not char then
		return false
	end
	local animate = char:FindFirstChild("Animate")
	local bindable = animate and animate:FindFirstChild("PlayEmote")
	if bindable and bindable:IsA("BindableFunction") then
		local ok, played = pcall(function()
			return bindable:Invoke(emote.anim)
		end)
		if ok and played then
			return true
		end
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local ok, played = pcall(function()
			return (humanoid :: any):PlayEmote(emote.anim)
		end)
		if ok and played == true then
			return true
		end
	end
	ctx:Toast("Stand still on the ground to emote", "info")
	return false
end

function Community.Trick(trickId: string): boolean
	if tricking then
		return false
	end
	local char = character()
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local world = ctx:GetController("World")
	local id = if root and root:IsA("BasePart") and world and world.NearestOwn then world.NearestOwn(root.Position, Cfg.TrickRange) else nil
	if not id then
		ctx:Toast("Stand near a monster in one of your pens", "info")
		return false
	end
	tricking = true
	local ok, res = ctx.Net:Request("Community.Trick", { id = id, trick = trickId })
	tricking = false
	if not ok then
		ctx:Toast(StoreKit.errorText(res), "error")
		return false
	end
	return true
end

local function toggleWheel()
	if ctx.Router:IsOpen("EmoteWheel") then
		ctx.Router:Close("EmoteWheel")
	elseif ctx.Router:Current() == nil and ctx.Router:Has("EmoteWheel") then
		ctx.Router:Open("EmoteWheel")
	end
end

-- The tutorial card sits in the same corner, so the row waits until the tutorial is done.
local function tutorialRunning(): boolean
	local step = tonumber(ctx.Store:Get("profile.Quests.tutorial.step"))
	return step ~= nil and step <= #Config.Quests.Tutorial
end

local function buildHud()
	local row = Instance.new("Frame")
	row.Name = "CommunityButtons"
	row.Visible = not tutorialRunning()
	ctx.Store:Observe("profile.Quests.tutorial.step", function()
		row.Visible = not tutorialRunning()
	end)
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0, 1)
	row.Position = UDim2.new(0, 16, 1, -64)
	row.Size = UDim2.fromOffset(206, 48)
	row.Parent = ctx.UI.Hud
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	Button.new({
		Name = "Emotes",
		Text = "Emotes",
		Color = C.Purple,
		Size = UDim2.fromOffset(100, 48),
		TextSize = Theme.TextSize.Small + 1,
		LayoutOrder = 1,
		Parent = row,
		OnClick = toggleWheel,
	})
	Button.new({
		Name = "Friends",
		Text = "Friends",
		Color = C.Blue,
		Size = UDim2.fromOffset(100, 48),
		TextSize = Theme.TextSize.Small + 1,
		Icon = Icon.new("friendship", 20),
		LayoutOrder = 2,
		Parent = row,
		OnClick = function()
			if ctx.Router:Has("Friends") then
				ctx.Router:Open("Friends")
			end
		end,
	})
end

-- VIP balcony pads --------------------------------------------------------------------------------

local function usePad(kind: string)
	local ok, res = ctx.Net:Request("Community.Balcony", { enter = kind == "enter" })
	if not ok then
		ctx:Toast(StoreKit.errorText(res), "info")
		if kind == "enter" and ctx.Router:Has("Store") then
			ctx.Router:Open("Store", { tab = "passes" })
		end
	end
end

local function addPrompt(part: BasePart, kind: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = if kind == "enter" then "Go up" else "Go down"
	prompt.ObjectText = "VIP Balcony"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = part
	prompt.Triggered:Connect(function()
		usePad(kind)
	end)
end

local function findPads()
	local world = workspace:WaitForChild("World", 30)
	local hub = world and world:WaitForChild("Hub", 10)
	if not hub then
		return
	end
	for _, inst in hub:GetDescendants() do
		local kind = inst:GetAttribute("VipPad")
		if inst:IsA("BasePart") and (kind == "enter" or kind == "exit") then
			addPrompt(inst, kind)
		end
	end
end

-- Lifecycle ----------------------------------------------------------------------------------------

function Community.Init(context)
	ctx = context
end

function Community.Start()
	buildHud()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.DPadDown then
			toggleWheel()
		end
	end)
	task.spawn(findPads)
end

return Community
