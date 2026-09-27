--[[
	Tourists (update 3.10 · Ranch life): NPC tourists visit the ranch, pay by its Appeal and
	write reviews in the Guestbook. Rules: Logic/Tourists; tuning: Config/Tourists. Separate from
	player likes and visits (Systems/Visits), which only read the stars for the showcase.

	Save section (profile.Tourists), version 1:
	  slot  = number|false  the last visit slot handled (Logic/Tourists.Slot); false = never
	  count = number        tourists welcomed in total
	  book  = { Review }    newest first, at most Config.Tourists.BookSize
	Session (session.Tourists): { score, stars, parts = { [categoryId] = 0..1 }, tip, nextAt, unlocked }
	Global (global.Tourists): { walk = { ['u'..userId] = { n, at, stars } } }  the last visit, for
	  every client to walk a tourist onto that plot

	Visits: from Ranch Level Config.Unlocks.Features.tourists, while the player is online (anywhere
	in the game: the ranch is their home, so no position check), one tourist per slot of
	Config.Tourists.Interval seconds on the server clock, offset per player. A visit pays
	Logic/Tourists.Pay(stars) through Rewards (source "tourists", silent + a small toast) and adds
	a review. Slots missed while away are paid on join, at most AwayMax, with one WelcomeItem.
	Before the unlock the slot just follows the clock, so nothing is owed for locked time.

	No actions: the Guestbook reads profile and session state.
	Public API:
	  Tourists:Appeal(player) -> { score, stars, parts, tip }
	  Tourists:Stars(player) -> number   0 while locked (the Visits snapshot shows it)
	Bus: publishes TouristVisited (player, { stars }) once per tourist; WelcomeItem on join.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Tourists)

local Tourists = {
	Name = "Tourists",
	Dependencies = { "Progression", "Rewards", "Monsters", "Ranch", "Decor" },
}

Tourists.Profile = {
	Version = 1,
	Default = function()
		return { slot = false, count = 0, book = {} }
	end,
}

local TICK = 5

local ctx
local Config, Rules
local Progression, Rewards, Monsters, Decor, Ranch

local function section(player)
	return ctx:Section(player)
end

local function unlocked(player): boolean
	return Progression:IsUnlocked(player, Rules.Unlock)
end

local function facts(player)
	local pens, rarities = {}, {}
	for _, pen in Ranch:PublicPens(player) or {} do
		local n = 0
		for _, id in pen.monsters or {} do
			local m = Monsters:Get(player, id)
			if m then
				n += 1
				table.insert(rarities, tonumber(m.rarity) or 1)
			end
		end
		table.insert(pens, { capacity = pen.capacity, count = n })
	end
	return {
		layout = Decor:Layout(player),
		level = Progression:GetLevel(player),
		pens = pens,
		rarities = rarities,
		codex = Monsters:CodexCount(player),
	}
end

local function appealOf(player)
	return Logic.Appeal(facts(player))
end

local function same(a, b): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if b[k] ~= v then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- Recomputes the appeal into the session; returns it.
local function refresh(player)
	local sess = ctx:Session(player)
	if not sess or not section(player) then
		return nil
	end
	local appeal = appealOf(player)
	local open = unlocked(player)
	local nextAt = Logic.NextAt(player.UserId, ctx:Now())
	if
		sess.score ~= appeal.score
		or sess.stars ~= appeal.stars
		or sess.tip ~= appeal.tip
		or sess.nextAt ~= nextAt
		or sess.unlocked ~= open
		or not same(sess.parts, appeal.parts)
	then
		sess.score, sess.stars, sess.tip, sess.nextAt, sess.unlocked = appeal.score, appeal.stars, appeal.tip, nextAt, open
		sess.parts = table.clone(appeal.parts)
		ctx:DirtySession(player)
	end
	return appeal
end

-- Handles `visits` tourists for the slots up to `slot`; returns the rewards granted.
local function welcome(player, visits: number, slot: number, silent: boolean)
	local s = section(player)
	local appeal = refresh(player) or appealOf(player)
	local now = ctx:Now()
	for i = visits, 1, -1 do
		Logic.Push(s.book, Logic.Review(player.UserId, slot - i + 1, appeal, now))
	end
	s.count = (s.count or 0) + visits
	ctx:Dirty(player)
	local granted = Rewards:Grant(player, Logic.Pay(appeal.stars, visits), "tourists", { silent = true })
	for _ = 1, visits do
		ctx.Bus:Publish("TouristVisited", player, { stars = appeal.stars })
	end
	if not silent then
		ctx:Notify(player, string.format("A tourist rated your ranch %d★", appeal.stars), "info")
		local g = ctx:Global()
		g.walk = g.walk or {}
		g.walk["u" .. player.UserId] = { n = s.count, at = now, stars = appeal.stars }
		ctx:DirtyGlobal("walk")
	end
	return granted
end

-- Moves the player's slot to now, paying the tourists due (online: normally one).
local function step(player, away: boolean)
	local s = section(player)
	if not s then
		return
	end
	local current = Logic.Slot(player.UserId, ctx:Now())
	if not unlocked(player) or type(s.slot) ~= "number" then
		if s.slot ~= current then
			s.slot = current
			ctx:Dirty(player)
		end
		return
	end
	local due = math.min(current - s.slot, Rules.AwayMax)
	if due <= 0 then
		return
	end
	s.slot = current
	welcome(player, due, current, away)
	if away then
		ctx.Bus:Publish("WelcomeItem", player, {
			kind = "tourists",
			text = if due == 1
				then "A tourist visited while you were away"
				else string.format("%d tourists visited while you were away", due),
		})
	end
end

-- Public API ---------------------------------------------------------------------------------

function Tourists:Appeal(player)
	if not section(player) then
		return nil
	end
	return appealOf(player)
end

function Tourists:Stars(player): number
	if not section(player) or not unlocked(player) then
		return 0
	end
	return appealOf(player).stars
end

-- Lifecycle ----------------------------------------------------------------------------------

function Tourists.Init(context)
	ctx = context
	Config = ctx.Config
	Rules = Config.Tourists
	Progression = ctx:GetSystem("Progression")
	Rewards = ctx:GetSystem("Rewards")
	Monsters = ctx:GetSystem("Monsters")
	Decor = ctx:GetSystem("Decor")
	Ranch = ctx:GetSystem("Ranch")
	ctx:Global().walk = {}

	for _, topic in { "PlotChanged", "PenChanged", "LevelUp", "MonsterCreated", "MonsterRemoved" } do
		ctx.Bus:Subscribe(topic, function(player)
			if player and section(player) then
				refresh(player)
			end
		end)
	end

	ctx:Every(TICK, function()
		for _, player in ctx:Players() do
			step(player, false)
			refresh(player)
		end
	end)
end

function Tourists.PlayerAdded(player)
	local s = section(player)
	s.book = if type(s.book) == "table" then s.book else {}
	s.count = tonumber(s.count) or 0
	s.slot = tonumber(s.slot) or false
	step(player, true)
	refresh(player)
end

function Tourists.PlayerRemoving(player)
	local g = ctx:Global()
	if g.walk and g.walk["u" .. player.UserId] then
		g.walk["u" .. player.UserId] = nil
		ctx:DirtyGlobal("walk")
	end
end

return Tourists
