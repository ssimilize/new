--[[
	Streaming (glow-up P): small helpers that keep client code working when the place turns on
	StreamingEnabled, where parts of Workspace.World arrive late, leave when the player walks
	away and come back. Nothing here assumes streaming is on; with it off they behave like a
	one-time scan.

		Streaming.Debounce(seconds, fn) -> trigger     trigger() runs fn once, `seconds` after the
		                                              first call of a burst (never re-entrant)
		Streaming.OnChild(parent, name, fn) -> connection
		    fn(child) for the child called `name` now (if there) and every time one arrives later
		    (no WaitForChild timeout: a far-away model may stream in minutes after joining)
		Streaming.WatchTree(root, seconds, fn) -> { connection }
		    fn() (debounced) whenever a descendant is added to or removed from root
]]

local Streaming = {}

function Streaming.Debounce(seconds: number, fn: () -> ()): () -> ()
	local pending = false
	return function()
		if pending then
			return
		end
		pending = true
		task.delay(seconds, function()
			pending = false
			fn()
		end)
	end
end

function Streaming.OnChild(parent: Instance, name: string, fn: (Instance) -> ()): RBXScriptConnection
	local connection = parent.ChildAdded:Connect(function(child)
		if child.Name == name then
			fn(child)
		end
	end)
	local existing = parent:FindFirstChild(name)
	if existing then
		task.spawn(fn, existing)
	end
	return connection
end

function Streaming.WatchTree(root: Instance, seconds: number, fn: () -> ()): { RBXScriptConnection }
	local trigger = Streaming.Debounce(seconds, fn)
	return {
		root.DescendantAdded:Connect(trigger),
		root.DescendantRemoving:Connect(trigger),
	}
end

return Streaming
