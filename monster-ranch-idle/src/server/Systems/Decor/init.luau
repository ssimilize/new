--[[
	Decor (glow-up Z · Build your ranch): decor placed freely on the player's plot. Pieces and
	art: Config/Decor, Config/DecorArt; rules: Logic/DecorLayout. Owned-but-unplaced pieces stay
	in Shop's storage (profile.Shop.decor); placing takes them out, removing puts them back.

	Save section (profile.Decor), version 1:
	  layout   = { { id, x, z, rot } }   plot-local grid units (Config.Decor.Layout.grid studs), rot 0..7 × 45°
	  migrated = boolean                 the old pen slots (Ranch pens[i].decor) were moved onto the layout
	  starter  = boolean                 the free starter set (Config.Decor `starter` counts) was granted

	Actions:
	  Decor.Save { layout } -> { count }   the whole layout from placement mode. Every piece must be
	      owned (storage + already placed), inside the plot and off the keep-outs, pen rails and
	      each other, and the count within DecorLayout.Cap(Ranch Level). Fails change nothing.

	Join (bus PlayerReady): grants the starter set once, then moves any old pen-slot decor onto the
	layout at the old slot spots (Ranch:TakePenDecor); pieces with no free spot go back to storage.

	Public API:
	  Decor:Layout(player) -> { { id, x, z, rot } }    a copy (Plots replicates it; visits copy it)
	  Decor:PenDecor(player, pen) -> { decorId }       mood pieces standing in that pen, best
	                                                   Config.Decor.PerPen first (Ranch's mood aura)
	  Decor:Placed(player, decorId) -> number          copies of a piece on the layout
	Publishes PlotChanged after a save or a migration (Plots rebuilds the plot).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Layout = require(Shared.Logic.DecorLayout)

local Decor = {
	Name = "Decor",
	Dependencies = { "Progression", "Shop" },
	OptionalDependencies = { "Ranch" },
}

Decor.Profile = {
	Version = 1,
	Default = function()
		return { layout = {}, migrated = false, starter = false }
	end,
}

local ctx
local Config
local Progression, Shop

local function section(player)
	return ctx:Section(player)
end

local function copy(list)
	local out = table.create(#list)
	for i, e in list do
		out[i] = { id = e.id, x = e.x, z = e.z, rot = e.rot }
	end
	return out
end

local function setup(player)
	local s = section(player)
	if not s then
		return
	end
	s.layout = Layout.Clean(s.layout)
	if not s.starter then
		s.starter = true
		for _, def in Config.Decor.List do
			if def.starter then
				Shop:AddDecor(player, def.id, def.starter)
			end
		end
		ctx:Dirty(player, "starter")
	end
	if not s.migrated then
		s.migrated = true
		local Ranch = ctx:GetSystem("Ranch")
		local taken = if Ranch and Ranch.TakePenDecor then Ranch:TakePenDecor(player) else {}
		local placed, leftover = Layout.Migrate(taken, s.layout)
		s.layout = placed
		for _, id in leftover do
			Shop:ReturnDecor(player, id)
		end
		ctx:Dirty(player, "layout")
		ctx:Dirty(player, "migrated")
		ctx.Bus:Publish("PlotChanged", player, {})
	end
end

-- Public API ------------------------------------------------------------------------------

function Decor:Layout(player)
	local s = section(player)
	return if s then copy(s.layout) else {}
end

function Decor:PenDecor(player, pen: number): { string }
	local s = section(player)
	return if s then Layout.PenDecor(s.layout, pen, Config.Decor.PerPen) else {}
end

function Decor:Placed(player, decorId: string): number
	local s = section(player)
	return if s then Layout.Counts(s.layout)[decorId] or 0 else 0
end

-- Lifecycle ---------------------------------------------------------------------------------

function Decor.Init(context)
	ctx = context
	Config = ctx.Config
	Progression = ctx:GetSystem("Progression")
	Shop = ctx:GetSystem("Shop")

	ctx.Bus:Subscribe("PlayerReady", setup)

	ctx.Net:Handle("Decor.Save", function(player, payload)
		setup(player)
		local s = section(player)
		local list = Layout.Clean(payload.layout)
		local old = Layout.Counts(s.layout)
		local available = {}
		for id in Layout.Counts(list) do
			available[id] = Shop:DecorCount(player, id) + (old[id] or 0)
		end
		local ok, err = Layout.Validate(list, Progression:GetLevel(player), available)
		if not ok then
			ctx:Fail(err or "That layout can't be saved")
		end
		local new = Layout.Counts(list)
		for id, n in old do
			if n > (new[id] or 0) then
				Shop:AddDecor(player, id, n - (new[id] or 0))
			end
		end
		for id, n in new do
			for _ = 1, n - (old[id] or 0) do
				Shop:TakeDecor(player, id)
			end
		end
		s.layout = list
		ctx:Dirty(player, "layout")
		ctx.Bus:Publish("PlotChanged", player, {})
		return { count = #list }
	end)
end

function Decor.PlayerAdded(player, _info)
	-- Plots and the starter grant wait for PlayerReady (every system loaded); a save before
	-- then runs setup itself.
	local s = section(player)
	if s then
		s.layout = Layout.Clean(s.layout)
	end
end

return Decor
