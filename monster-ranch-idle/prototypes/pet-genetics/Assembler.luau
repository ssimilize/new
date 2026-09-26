--[[
	PROTOTYPE (not part of the game): builds a pet Model from a Genetics phenotype by putting
	together parts of different species from the PartLibrary (capture.luau made it from pets
	generated part by part with Roblox's mesh generator).

	The body comes from the body species, `phenotype.size` studs at its largest dimension. Every
	other part keeps its place RELATIVE TO THE BODY'S SURFACE: a part inside the body box along an
	axis scales with the new body's half size; a part outside it (ears on top, a tail behind) keeps
	its distance past the surface, so a cat's ears sit on a dragon's head, not inside or above it.
	Borrowed legs stretch in X/Z to the new body's footprint. Parts scale uniformly with `size`.

	Assembler.build(phenotype, library, makePart, paint?) -> Model (front = -Z, standing on y = 0)
	  makePart(entry) -> MeshPart   a fresh MeshPart of entry.mesh + entry.texture (the caller caches)
	  paint(part, Color3)           optional tint (SurfaceAppearance.Color); skipped when nil
]]

local Assembler = {}

local LOCI = { "body", "ears", "tail", "legs", "back" }
Assembler.TintStrength = 0.35 -- 0 = each part keeps its species' colours, 1 = fully the gene colour

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- One axis: the part's normalised offset `o` from its own body (half size `srcHalf`, studs) onto a
-- body of half size `half`.
local function place(o: number, srcHalf: number, half: number): number
	if math.abs(o) <= 1 then
		return o * half
	end
	local sign = if o > 0 then 1 else -1
	return sign * (half + (math.abs(o) - 1) * srcHalf)
end

function Assembler.build(phenotype, library, makePart: (any) -> MeshPart, paint: ((MeshPart, Color3) -> ())?): Model
	local S = phenotype.size
	local bodySpecies = phenotype.parts.body
	local bodyLib = assert(library[bodySpecies], "no parts for body species " .. tostring(bodySpecies))
	local bodyBox = v3(bodyLib.body) * S
	local half = bodyBox / 2
	local c = phenotype.color
	local k = Assembler.TintStrength
	local tint = Color3.new(1 + (c[1] - 1) * k, 1 + (c[2] - 1) * k, 1 + (c[3] - 1) * k)

	local model = Instance.new("Model")
	model.Name = "Pet"
	-- A species' `face` piece (the chick's beak) is not a gene of its own: it rides on its body.
	local slots = table.clone(LOCI)
	table.insert(slots, "face")
	for _, locus in slots do
		local species = if locus == "face" then bodySpecies else phenotype.parts[locus]
		local lib = library[species]
		local entry = lib and lib.parts[locus]
		if entry then
			local part = makePart(entry)
			part.Name = locus .. "_" .. species
			part.Anchored = true
			part.CanCollide = false
			local rot = CFrame.Angles(0, lib.turn, 0)
			local size = v3(entry.scale) * S
			local srcHalf = v3(lib.body) * S / 2
			if locus == "legs" and species ~= bodySpecies then
				-- Stretch the legs' footprint to the new body (in the turned frame, then back to
				-- the part's own axes: a quarter turn swaps X and Z).
				local fx, fz = half.X / srcHalf.X, half.Z / srcHalf.Z
				if math.abs(math.abs(lib.turn) - math.pi / 2) < 0.01 then
					fx, fz = fz, fx
				end
				size = Vector3.new(size.X * fx, size.Y, size.Z * fz)
			end
			part.Size = size
			local o = entry.offset
			local at = Vector3.new(place(o[1], srcHalf.X, half.X), place(o[2], srcHalf.Y, half.Y), place(o[3], srcHalf.Z, half.Z))
			part.CFrame = CFrame.new(at) * rot
			if paint then
				paint(part, tint)
			end
			part:SetAttribute("Species", species)
			part.Parent = model
			if locus == "body" then
				model.PrimaryPart = part
			end
		end
	end
	-- Stand on y = 0.
	local box, extent = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(0, extent.Y / 2 - box.Position.Y, 0))
	return model
end

return Assembler
