--[[
	Scheduler: timed callbacks driven by the kernel's clock.
	In Roblox, Step() runs every Heartbeat. In tests, the MockKernel advances a manual clock
	and calls Step(), which makes every timer deterministic.
]]

local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(clock)
	return setmetatable({ _clock = clock, _jobs = {}, _nextId = 0 }, Scheduler)
end

local function add(self, due: number, interval: number?, fn, name: string?)
	self._nextId += 1
	local job = { id = self._nextId, due = due, interval = interval, fn = fn, name = name or "job", active = true }
	table.insert(self._jobs, job)
	return {
		Cancel = function()
			job.active = false
		end,
	}
end

-- Runs `fn(dt)` every `interval` seconds (first run after one interval).
function Scheduler:Every(interval: number, fn: (number) -> (), name: string?)
	assert(interval > 0, "interval must be positive")
	return add(self, self._clock.Precise() + interval, interval, fn, name)
end

function Scheduler:After(delay: number, fn: () -> (), name: string?)
	return add(self, self._clock.Precise() + math.max(0, delay), nil, fn, name)
end

function Scheduler:Step()
	local now = self._clock.Precise()
	local jobs = self._jobs
	local i = 1
	while i <= #jobs do
		local job = jobs[i]
		if not job.active then
			table.remove(jobs, i)
		elseif now >= job.due then
			local dt = if job.interval then job.interval else 0
			local ok, err = xpcall(job.fn, debug.traceback, dt)
			if not ok then
				warn(string.format("[Scheduler] %s failed: %s", job.name, tostring(err)))
			end
			if job.interval and job.active then
				-- Catch up without running a burst of missed ticks.
				job.due = math.max(job.due + job.interval, now)
				i += 1
			else
				job.active = false
				table.remove(jobs, i)
			end
		else
			i += 1
		end
	end
end

return Scheduler
