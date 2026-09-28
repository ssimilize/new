--[[
	VfxPresets (Foundry wave 1e): the effect preset table Visuals/Vfx and Visuals/SceneryFx read.

	The 72 specset presets (Auras, Mutations, Variants, Rarity, Landmarks, Bursts, Eggs, EggReady,
	Mastery, Scenery, Titanic) live in the Foundry's EffectGraph library
	(packages/EffectGraph/graphs/monster-ranch.json, vendored as
	Shared/Foundry/EffectGraph/library/monster-ranch). EffectGraph.toSpecsets rebuilds them exactly
	as Config/Vfx wrote them (VfxCompat.spec: field for field, bit-equal numbers).

		VfxPresets.Table                     Config/Vfx's fields; after Use found the library, its
		                                     preset tables are the library's (replaced in place, so
		                                     a module holding Table sees them)
		VfxPresets.Use(foundry) -> boolean   the Quality controller hands in ctx.Foundry at Init.
		                                     Without the EffectGraph package or its monster-ranch
		                                     library it warns once and Config/Vfx's presets stay
		VfxPresets.Build(EffectGraph, graphs, base) -> table   base's fields with the library's
		                                     preset tables (pure)
		VfxPresets.Using() -> boolean        the library's presets are in Table
		VfxPresets.NotAdopted                what stays on the old path, and why
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigVfx = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Vfx"))

local GAME = "monster-ranch"

local VfxPresets = {}

VfxPresets.NotAdopted = {
	["Config/Vfx"] = "kept: the fallback when the library is missing, and the home of the fields that are not presets "
		.. "(Sprites, Fade, Night, Budget, RefHeight, EggRefHeight, EvolveElementEmit), which World, Vfx and SceneryFx read",
	["EffectGraph.Player"] = "Visuals/Vfx and SceneryFx still build, pool, scale and budget their own ParticleEmitters "
		.. "(Logic/ParticleBudget, Config.Vfx.Night); the package's plan/Player timing, quality scaling and night rules differ",
}

VfxPresets.Table = table.clone(ConfigVfx)

local using = false
local warned = false

function VfxPresets.Build(EffectGraph: any, graphs: { any }, base: { [any]: any }): { [any]: any }
	local out = table.clone(base)
	for name, set in EffectGraph.toSpecsets(graphs) do
		out[name] = set
	end
	return out
end

function VfxPresets.Use(foundry: any): boolean
	if using then
		return true
	end
	local pkg = foundry and foundry.packages and foundry.packages.EffectGraph
	local libraries = foundry and foundry.libraries and foundry.libraries.EffectGraph
	local graphs = libraries and libraries[GAME]
	if type(pkg) == "table" and type(pkg.toSpecsets) == "function" and type(graphs) == "table" then
		for k, v in VfxPresets.Build(pkg, graphs, ConfigVfx) do
			VfxPresets.Table[k] = v
		end
		using = true
		return true
	end
	if not warned then
		warned = true
		warn("[Vfx] the Foundry EffectGraph library is not vendored; Config/Vfx's presets run")
	end
	return false
end

function VfxPresets.Using(): boolean
	return using
end

return VfxPresets
