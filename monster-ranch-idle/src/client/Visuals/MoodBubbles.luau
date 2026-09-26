--[[
	MoodBubbles (glow-up S, living pens): a small icon (💤 ❤ 🍖 ♪ 💧) that pops over a pen
	monster for a moment. Config/PenLife.Bubbles holds the icons and limits; Visuals/PenBrain pops them.

		MoodBubbles.Pop(model, kind, now) -> boolean   kind = sleep | love | food | music | wet
		MoodBubbles.Step(now)                           expire bubbles (the brain's tick, 5 a second)
		MoodBubbles.SetLow(on)                          lowGraphics: essentials only, a smaller cap
		MoodBubbles.SetSuppressed(on)                   photo mode: pop nothing
		MoodBubbles.Count() -> number                   bubbles showing
		MoodBubbles.Clear()                             hide all and drop the pool

	Only within `range` studs of the camera, at most `max` (`maxLow`) on screen, one per monster per
	`cooldown` seconds. BillboardGuis live in the PlayerGui and are pooled: a pop re-targets a free
	one (no Instance.new after the pool is full).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.PenLife).Bubbles
local PenLife = require(Shared.Logic.PenLife)

local Client = script.Parent.Parent
local Theme = require(Client.UI.Theme)
local Create = require(Client.UI.Create)
local Anim = require(Client.UI.Anim)

local New = Create.New

local MoodBubbles = {}

local free = {} :: { BillboardGui }
local liveGui = {} :: { BillboardGui }
local liveUntil = {} :: { number }
local liveCount = 0
local lastPop = setmetatable({}, { __mode = "k" }) :: { [Model]: number }
local low = false
local suppressed = false

local function build(): BillboardGui
	local gui = New("BillboardGui", {
		Name = "MoodBubble",
		Size = UDim2.fromOffset(44, 44),
		AlwaysOnTop = false,
		MaxDistance = Cfg.range,
		ResetOnSpawn = false,
		LightInfluence = 0,
		Active = false,
		Enabled = false,
	})
	local bubble = New("Frame", {
		Name = "Bubble",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(38, 38),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.08,
		Parent = gui,
	}, { Create.Round(), Create.Stroke(2) })
	Create.Text({
		Name = "Icon",
		Text = "",
		TextColor3 = Theme.Colors.Text,
		TextSize = 22,
		Size = UDim2.fromScale(1, 1),
		Stroke = false,
		Parent = bubble,
	})
	gui:SetAttribute("Localize", false) -- icons only; nothing to translate
	return gui
end

local function release(i: number)
	local gui = liveGui[i]
	gui.Enabled = false
	gui.Adornee = nil
	liveGui[i] = liveGui[liveCount]
	liveUntil[i] = liveUntil[liveCount]
	liveGui[liveCount] = nil
	liveUntil[liveCount] = nil
	liveCount -= 1
	table.insert(free, gui)
end

function MoodBubbles.SetLow(on: boolean)
	low = on == true
end

function MoodBubbles.SetSuppressed(on: boolean)
	suppressed = on == true
	if suppressed then
		for i = liveCount, 1, -1 do
			release(i)
		end
	end
end

function MoodBubbles.Count(): number
	return liveCount
end

function MoodBubbles.Pop(model: Model, kind: string, now: number): boolean
	local icon = Cfg.icons[kind]
	if not icon or suppressed then
		return false
	end
	local cap = if low then Cfg.maxLow else Cfg.max
	if not PenLife.BubbleAllowed(kind, low, liveCount, cap) then
		return false
	end
	local last = lastPop[model]
	if last and now - last < Cfg.cooldown then
		return false
	end
	local root = model.PrimaryPart
	local camera = workspace.CurrentCamera
	if not root or not camera then
		return false
	end
	if (root.Position - camera.CFrame.Position).Magnitude > Cfg.range then
		return false
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	lastPop[model] = now
	local gui = table.remove(free) or build()
	local height = model:GetAttribute("Height")
	gui.Adornee = root
	gui.StudsOffset = Vector3.new(0, (if type(height) == "number" then height * 0.6 else 1.8) + 1.4, 0)
	local bubble = gui:FindFirstChild("Bubble") :: Frame
	local label = bubble and bubble:FindFirstChild("Icon")
	if label and label:IsA("TextLabel") then
		label.Text = icon
	end
	gui.Parent = playerGui
	gui.Enabled = true
	if bubble then
		Anim.popIn(bubble, 0.25)
	end
	liveCount += 1
	liveGui[liveCount] = gui
	liveUntil[liveCount] = now + Cfg.seconds
	return true
end

function MoodBubbles.Step(now: number)
	for i = liveCount, 1, -1 do
		local gui = liveGui[i]
		local adornee = gui.Adornee
		if now >= liveUntil[i] or not adornee or not adornee:IsDescendantOf(workspace) then
			release(i)
		end
	end
end

function MoodBubbles.Clear()
	for i = liveCount, 1, -1 do
		release(i)
	end
	for _, gui in free do
		gui:Destroy()
	end
	table.clear(free)
	table.clear(lastPop)
end

return MoodBubbles
