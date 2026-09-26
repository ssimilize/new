--[[
	Surf (update 2.0 · Summer Splash): the Surf Shack minigame. Rules: Config/Surf and
	Logic/Surf.

	Save section (profile.Surf): { best, runs }
	Actions:
	  Surf.Start -> { run, seed, duration }       -- only while Summer Splash runs
	  Surf.Finish { run, inputs = { { t, lane } } } -> { score, shells, hits, survived, tokens, best }
	The server keeps the open run (seed, start time) in memory. Finish replays the inputs
	against the seed; the run must have taken at least the simulated time on the wall clock
	(minus Config.GraceSeconds) and be finished within Duration + LateSeconds. Seashells go
	through Events:Grant (the event's daily cap). Publishes SurfRun (player, { score, shells }).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Surf)

local Surf = {
	Name = "Surf",
	Dependencies = { "Events" },
}

Surf.Profile = {
	Version = 1,
	Default = function()
		return { best = 0, runs = 0 }
	end,
}

local ctx
local Config -- Config.Surf
local Events

local runs = {} -- [player] = { id, seed, startedAt }
local nextRun = 0

local function running(): boolean
	return ctx.Config.Events.ActiveId(ctx:Now()) == Config.Event
end

local function start(player)
	if not running() then
		ctx:Fail("The Surf Shack opens during Summer Splash")
	end
	nextRun += 1
	local seed = ctx.Rng:Int(1, 2 ^ 30)
	runs[player] = { id = nextRun, seed = seed, startedAt = ctx.Clock.Precise() }
	return { run = nextRun, seed = seed, duration = Config.Duration }
end

local function finish(player, runId: number, inputs)
	local run = runs[player]
	if not run or run.id ~= runId then
		ctx:Fail("That surf run has ended. Start a new one!")
	end
	runs[player] = nil
	local ok, why = Logic.Valid(inputs)
	if not ok then
		ctx:Fail(string.format("That run didn't add up (%s)", tostring(why)))
	end
	local result = Logic.Simulate(run.seed, inputs)
	local elapsed = ctx.Clock.Precise() - run.startedAt
	if elapsed + Config.GraceSeconds < result.survived then
		ctx:Fail("That run finished too quickly")
	end
	if elapsed > Config.Duration + Config.LateSeconds then
		ctx:Fail("That surf run has ended. Start a new one!")
	end
	local s = ctx:Section(player)
	local tokens = 0
	if s then
		s.runs += 1
		s.best = math.max(s.best, result.score)
		ctx:Dirty(player)
		local want = math.min(Config.MaxTokensPerRun, math.floor(result.score / Config.PointsPerToken))
		tokens = Events:Grant(player, want, "surf")
	end
	ctx.Bus:Publish("SurfRun", player, { score = result.score, shells = result.shells })
	return {
		score = result.score,
		shells = result.shells,
		hits = result.hits,
		survived = result.survived,
		tokens = tokens,
		best = if s then s.best else result.score,
	}
end

function Surf.Init(context)
	ctx = context
	Config = ctx.Config.Surf
	Events = ctx:GetSystem("Events")
	table.clear(runs)
	ctx.Net:Handle("Surf.Start", function(player)
		return start(player)
	end)
	ctx.Net:Handle("Surf.Finish", function(player, payload)
		return finish(player, payload.run, payload.inputs)
	end)
end

function Surf.PlayerRemoving(player)
	runs[player] = nil
end

return Surf
