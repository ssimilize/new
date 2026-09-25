--[[
	Focus (update 3.2): which modal card is on top, so a gamepad cursor can be kept inside it.

	Router screens are tracked by the Router. Smaller modals drawn over them or over the HUD
	(Parts/Dialog, InsetPopup, the hatch reveal, the evolution popup) register their root
	while they are open. The Gamepad controller keeps the selection inside the topmost one
	and closes it with B through the close function given here. Touch and mouse play never
	read this, so registering costs nothing when no pad is in use.

	  Focus.push(root, close?)    root: the modal's full-screen GuiObject; close: its own close
	                              path, or nil when Back must not close it
	  Focus.remove(root)
	  Focus.top() -> { root, close }?   the newest entry whose root is still shown
	  Focus.isShown(gui) -> boolean     gui and every ancestor visible, under an enabled ScreenGui
	  Focus.Changed                     Signal, fires after push / remove
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.Kernel.Signal)

local Focus = {}

Focus.Changed = Signal.new()

local stack = {} -- { { root = GuiObject, close = fn? } }, oldest first

function Focus.isShown(gui: Instance?): boolean
	local cursor = gui
	while cursor do
		if cursor:IsA("GuiObject") then
			if not cursor.Visible then
				return false
			end
		elseif cursor:IsA("LayerCollector") then
			return (cursor :: any).Enabled == true and cursor.Parent ~= nil
		end
		cursor = cursor.Parent
	end
	return false
end

function Focus.remove(root: Instance)
	for i = #stack, 1, -1 do
		if stack[i].root == root then
			table.remove(stack, i)
		end
	end
	Focus.Changed:Fire()
end

function Focus.push(root: GuiObject, close: (() -> ())?)
	for i = #stack, 1, -1 do
		if stack[i].root == root then
			table.remove(stack, i)
		end
	end
	table.insert(stack, { root = root, close = close })
	Focus.Changed:Fire()
end

function Focus.top()
	for i = #stack, 1, -1 do
		local entry = stack[i]
		if entry.root.Parent == nil then
			table.remove(stack, i) -- destroyed without remove()
		elseif Focus.isShown(entry.root) then
			return entry
		end
	end
	return nil
end

return Focus
