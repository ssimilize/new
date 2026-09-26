--[[
	Parts/BattleResult: the result card after a fight, shared by the 2D viewer (Parts/BattleReplay)
	and the 3D stage (Parts/BattleStage), so both end the same way.

		local panel = BattleResult.show(ctx, parent, opts, win, {
			close = function() end,       -- Continue: the viewer tears itself down, then opts.onClose
			alive = function() return true end,
		})

	opts are the viewer's: winText, loseText, rewards, retryText + onRetry (on a loss),
	nextText + onNext (on a win). Plays the Victory / Defeat sting.
]]

local UI = script.Parent.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Util = require(script.Parent.Util)

local New = Create.New
local C = Theme.Colors

local BattleResult = {}

function BattleResult.show(ctx, parent: Instance, opts, win: boolean, hooks: { close: () -> (), alive: () -> boolean })
	local panel = Panel.new({
		Title = if win then "Victory!" else "Defeat",
		Color = if win then C.Green else C.Red,
		Size = UDim2.fromOffset(560, 300),
		Parent = parent,
	})
	panel.Root.ZIndex = 20
	local body = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -64),
		Parent = panel.Body,
	}, { Create.List("y", 10, Enum.HorizontalAlignment.Center) })
	Util.text({
		Text = if win
			then (opts.winText or "Stage cleared!")
			else (opts.loseText or "Your squad fainted. Try stronger monsters or better elements."),
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = body,
	})
	if opts.rewards and #opts.rewards > 0 then
		Util.rewardRow(opts.rewards, body, { LayoutOrder = 2, IconSize = 30, Align = Enum.HorizontalAlignment.Center })
	elseif win then
		Util.text({
			Text = "No first-clear reward this time.",
			TextColor3 = C.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = 2,
			Parent = body,
		})
	end
	local buttons = New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 56),
		Parent = panel.Body,
	}, { Create.List("x", 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	Button.new({
		Text = "Continue",
		Color = C.Gray,
		Size = UDim2.fromOffset(170, 54),
		LayoutOrder = 1,
		OnClick = hooks.close,
		Parent = buttons,
	})
	if not win and opts.onRetry then
		local retry
		retry = Button.new({
			Text = opts.retryText or "Retry with +20% (ad)",
			Color = C.Orange,
			Size = UDim2.fromOffset(300, 54),
			LayoutOrder = 2,
			Parent = buttons,
			OnClick = function()
				retry:SetDisabled(true)
				opts.onRetry()
				if hooks.alive() then
					retry:SetDisabled(false)
				end
			end,
		})
	elseif win and opts.onNext then
		Button.new({
			Text = opts.nextText or "Next stage",
			Color = C.Green,
			Size = UDim2.fromOffset(240, 54),
			LayoutOrder = 2,
			Parent = buttons,
			OnClick = function()
				opts.onNext()
			end,
		})
	end
	Anim.popIn(panel.Root)
	ctx:Sound(if win then "Victory" else "Defeat")
	return panel
end

return BattleResult
