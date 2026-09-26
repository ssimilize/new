--[[
	PROTOTYPE tool, run in Studio (Edit) through execute_luau: reads the part-segmented pets that
	generate_mesh put in the Workspace (attribute PetSpecies = species id) and returns the
	PartLibrary table as JSON, which tools write to PartLibrary.luau.

	Normalised frame per species: origin at the body's centre, front = -Z (Roblox's LookVector),
	found as the side AWAY from the tail (the generator faces pets any way it likes); lengths are
	in units of the body's half size per axis, so a part can be moved onto another species' body
	by multiplying with that body's half size. `body` is the body's turned box over its largest
	dimension; `scale` is a part's size in its OWN axes over that largest dimension (the
	assembler turns every part of a species by the species' `turn`).
]]

local HttpService = game:GetService("HttpService")

-- Generated part names arrive as '["body"', '"tail"' ...: keep the letters.
local LOCUS_BY_NAME = { body = "body", ears = "ears", horns = "ears", tuft = "ears", tail = "tail", legs = "legs", wings = "back" }

-- Where the segmenter guessed wrong. chick: its "tail" is really the beak, on the FACE side, so
-- the tail rule turned it backwards; the beak becomes a `face` piece that always goes with the
-- chick's body (Assembler), and the facing comes from here instead.
local OVERRIDES = {
	chick = { turn = math.pi, rename = { tail = "face" } },
}

local function clean(name: string): string
	return (string.gsub(string.gsub(name, "_geom$", ""), "[^%a]", ""))
end

local function round(v: number): number
	return math.round(v * 10000) / 10000
end

-- The generated pets: in the Workspace, or parked in ServerStorage.PetGenerations.
local models = workspace:GetChildren()
local parked = game:GetService("ServerStorage"):FindFirstChild("PetGenerations")
if parked then
	table.move(parked:GetChildren(), 1, #parked:GetChildren(), #models + 1, models)
end

local library = {}
for _, model in models do
	local species = model:GetAttribute("PetSpecies")
	if model:IsA("Model") and type(species) == "string" then
		local parts = {}
		for _, d in model:GetDescendants() do
			if d:IsA("MeshPart") then
				local locus = LOCUS_BY_NAME[string.lower(clean(d.Name))]
				if locus then
					parts[locus] = d
				end
			end
		end
		local override = OVERRIDES[species] or {}
		for from, to in override.rename or {} do
			parts[to], parts[from] = parts[from], nil
		end
		local body = assert(parts.body, species .. " has no body")
		local tail = parts.tail
		-- Yaw that turns the pet so its front is -Z: the tail points +Z afterwards.
		local turn = 0
		if override.turn then
			turn = override.turn
		elseif tail then
			local away = tail.Position - body.Position
			if math.abs(away.X) > math.abs(away.Z) then
				-- CFrame.Angles(0, t, 0) sends +X to (cos t, 0, -sin t): -90 degrees sends +X to +Z.
				turn = if away.X > 0 then math.rad(-90) else math.rad(90)
			else
				turn = if away.Z > 0 then 0 else math.pi
			end
		end
		local rot = CFrame.Angles(0, turn, 0)
		local function turned(v: Vector3): Vector3
			return rot:VectorToWorldSpace(v)
		end
		local function turnedSize(s: Vector3): Vector3
			local t = turned(s)
			return Vector3.new(math.abs(t.X), math.abs(t.Y), math.abs(t.Z))
		end
		local bodySize = turnedSize(body.Size)
		local half = bodySize / 2
		local maxDim = math.max(bodySize.X, bodySize.Y, bodySize.Z)
		local entry = { turn = round(turn), body = { round(bodySize.X / maxDim), round(bodySize.Y / maxDim), round(bodySize.Z / maxDim) }, parts = {} }
		for locus, part in parts do
			local offset = turned(part.Position - body.Position)
			-- Size stays in the part's own axes (the assembler turns the part by `turn` too).
			local size = part.Size
			entry.parts[locus] = {
				mesh = part.MeshId,
				texture = part.TextureID,
				offset = { round(offset.X / half.X), round(offset.Y / half.Y), round(offset.Z / half.Z) },
				scale = { round(size.X / maxDim), round(size.Y / maxDim), round(size.Z / maxDim) },
			}
		end
		library[species] = entry
	end
end
return HttpService:JSONEncode(library)
