--[[
	Bond (glow-up Q): bond hearts between a player and each of their own monsters, raised by the
	care gestures (Pet, Brush, Play) of the Care screen. Tuning in Config.Bond, rules in Logic/Bond.

	  Care      Bond.Care { id, kind }: the monster must be the player's and in one of their pens,
	            the kind must be off its per-monster cooldown (Config.Bond.cooldown), and bond-adding
	            cares from one player are at least Config.Bond.minGap seconds apart. +1 point.
	            The client plays the gesture either way; it only asks once the kind is ready.
	            Returns { hearts, points, gained, learned = trickId|false }.
	  Unlocks   a heart on the monster card and MonsterDetail (client), tricks at Config.Bond.Tricks
	            hearts (Community.Trick asks Bond:Hearts), a nameplate over the pen monster from
	            NameplateHearts, and +1% of that monster's own coin rate per 2 hearts, at most +5%
	            (Ranch per-monster modifier "bond"; income only, never fights).
	  Leaving   bond belongs to the monster on this ranch. MonsterRemoved (sell, retire, fuse,
	            trade, market, rebirth) deletes its entry, and a monster that arrives by trade gets
	            a fresh id, so bond can't be farmed and sold. Bond never decays.

	Save section (profile.Bond), version 1:
	  list  = { [monsterId] = { pts, pet = unix?, brush = unix?, play = unix? } }   -- last bond-adding care per kind
	  cares = number                                                              -- lifetime bond-adding cares
	Migrate repairs a section from any earlier version (Logic/Bond.Sanitize); PlayerAdded drops
	entries of monsters the player no longer has.
	Global (global.Bond): here = { ["u" .. userId] = {
	  best   = { { id, hearts, form, variant, name } },   -- up to BestFriends, the ranch gate
	  plates = { { id, hearts, name } },                  -- from NameplateHearts, up to MaxPlates
	} }
	Public: Bond:Hearts(player, id) -> number, Bond:Points(player, id) -> number.
	Bus: publishes BondRaised (player, { id, hearts, points, kind, heartUp }).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logic = require(Shared.Logic.Bond)
local Formulas = require(Shared.Logic.Formulas)
local TableUtil = require(Shared.Logic.TableUtil)
local BondConfig = require(Shared.Config).Bond

local Bond = {
	Name = "Bond",
	Dependencies = { "Monsters" },
	OptionalDependencies = { "Ranch" },
}

local ctx
local Cfg
local Monsters

local lastCare = {} -- [player] = ctx:Now() of the player's last bond-adding care

Bond.Profile = {
	Version = 1,
	Default = function()
		return { list = {}, cares = 0 }
	end,
	Migrate = function(section, _fromVersion)
		return Logic.Sanitize(section, BondConfig)
	end,
}

local function section(player)
	local s = ctx:Section(player)
	if not s then
		ctx:Fail("Your ranch is still loading")
	end
	return s
end

-- The public view of this player's bond for the ranch gate and the nameplates.
local function publicView(player, s)
	local best = {}
	for _, row in Logic.Best(s.list, Cfg.BestFriends, Cfg) do
		local m = Monsters:Get(player, row.id)
		if m then
			table.insert(
				best,
				{ id = row.id, hearts = row.hearts, form = m.form, variant = m.variant or 0, name = Formulas.DisplayName(m) }
			)
		end
	end
	local plates = {}
	for _, row in Logic.Best(s.list, Cfg.MaxPlates, Cfg) do
		local m = Monsters:Get(player, row.id)
		if m and row.hearts >= Cfg.NameplateHearts then
			table.insert(plates, { id = row.id, hearts = row.hearts, name = Formulas.DisplayName(m) })
		end
	end
	return { best = best, plates = plates }
end

local function publish(player)
	local s = ctx:Section(player)
	local global = ctx:Global()
	global.here = global.here or {}
	local key = "u" .. player.UserId
	local view = if s then publicView(player, s) else nil
	if view and #view.best == 0 then
		view = nil
	end
	if not TableUtil.equal(global.here[key], view) then
		global.here[key] = view
		ctx:DirtyGlobal("here", key)
	end
end

local function refreshIncome(player)
	local Ranch = ctx:GetSystem("Ranch")
	if Ranch then
		Ranch:Refresh(player)
	end
end

local function care(player, payload)
	local s = section(player)
	local kind = Cfg.KindById[payload.kind]
	local m = Monsters:Get(player, payload.id)
	if not m then
		ctx:Fail("That monster doesn't exist")
	end
	local Ranch = ctx:GetSystem("Ranch")
	if Ranch and Ranch:PenOf(player, payload.id) <= 0 then
		ctx:Fail("Only monsters in your pens can be cared for")
	end
	local now = ctx:Now()
	local entry = s.list[payload.id]
	local ready = Logic.Ready(entry, kind.id, now, Cfg)
	if not ready then
		ctx:Fail("Your monster already loved that. Try another kind of care")
	end
	if lastCare[player] and now - lastCare[player] < Cfg.minGap then
		ctx:Fail("Give your monster a moment to rest")
	end
	lastCare[player] = now
	if not entry then
		entry = { pts = 0 }
		s.list[payload.id] = entry
	end
	local before = Logic.Hearts(entry.pts, Cfg)
	entry.pts = math.min(entry.pts + 1, Cfg.HeartAt[#Cfg.HeartAt])
	entry[kind.id] = now
	s.cares += 1
	local hearts = Logic.Hearts(entry.pts, Cfg)
	ctx:Dirty(player, "list", payload.id)
	ctx:Dirty(player, "cares")
	local learned = false
	if hearts > before then
		for _, trick in Cfg.Tricks do
			if trick.bond > before and trick.bond <= hearts then
				learned = trick.id
			end
		end
		if Logic.IncomePct(hearts, Cfg) ~= Logic.IncomePct(before, Cfg) then
			refreshIncome(player)
		end
		publish(player)
	end
	ctx.Bus:Publish(
		"BondRaised",
		player,
		{ id = payload.id, hearts = hearts, points = entry.pts, kind = kind.id, heartUp = hearts > before }
	)
	ctx.Analytics.Custom(player, "BondCare", 1, { kind = kind.id, hearts = hearts })
	return { hearts = hearts, points = entry.pts, gained = true, learned = learned }
end

function Bond.Init(context)
	ctx = context
	Cfg = ctx.Config.Bond
	Monsters = ctx:GetSystem("Monsters")
	ctx.Net:Handle("Bond.Care", care)
	ctx.Bus:Subscribe("MonsterRemoved", function(player, detail)
		local s = ctx:Section(player)
		local id = type(detail) == "table" and detail.id
		if s and type(id) == "string" and s.list[id] then
			local hearts = Logic.Hearts(s.list[id].pts, Cfg)
			s.list[id] = nil
			ctx:Dirty(player, "list", id)
			if hearts > 0 then
				publish(player)
			end
		end
	end)
	ctx.Bus:Subscribe("MonsterChanged", function(player, detail)
		local s = ctx:Section(player)
		local id = type(detail) == "table" and detail.id
		if s and type(id) == "string" and s.list[id] and s.list[id].pts > 0 then
			publish(player) -- a rename or an evolution shows on the gate and the nameplate
		end
	end)
end

function Bond.Start()
	local Ranch = ctx:GetSystem("Ranch")
	if Ranch and Ranch.RegisterMonsterRateModifier then
		Ranch:RegisterMonsterRateModifier("bond", function(player, m)
			local s = ctx:Section(player)
			local entry = s and type(m) == "table" and s.list[m.id]
			return if entry then Logic.IncomePct(Logic.Hearts(entry.pts, Cfg), Cfg) else 0
		end)
	end
end

function Bond.PlayerAdded(player)
	local s = ctx:Section(player)
	if not s then
		return
	end
	local stale = {}
	for id in s.list do
		if not Monsters:Get(player, id) then
			table.insert(stale, id)
		end
	end
	for _, id in stale do
		s.list[id] = nil
		ctx:Dirty(player, "list", id)
	end
	publish(player)
	if #stale > 0 then
		refreshIncome(player)
	end
end

function Bond.PlayerRemoving(player)
	lastCare[player] = nil
	local global = ctx:Global()
	local key = "u" .. player.UserId
	if global.here and global.here[key] then
		global.here[key] = nil
		ctx:DirtyGlobal("here", key)
	end
end

-- Public API ------------------------------------------------------------------------------------

function Bond:Points(player, id: string): number
	local s = ctx:Section(player)
	local entry = s and s.list[id]
	return if entry then entry.pts else 0
end

function Bond:Hearts(player, id: string): number
	return Logic.Hearts(self:Points(player, id), Cfg)
end

return Bond
