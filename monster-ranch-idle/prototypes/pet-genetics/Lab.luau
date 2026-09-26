--[[
	PROTOTYPE breeding lab for Studio (Edit, or a Play server). Builds Workspace.PetGeneticsLab:
	a row of pure-bred founders, then litters of crosses, each pet labelled with its genes, stats
	and skills. Nothing here is wired into the game; the modules live in
	ServerStorage.PetGeneticsLab (Genetics, Assembler, PartLibrary, Lab).

		local Lab = require(game.ServerStorage.PetGeneticsLab.Lab)
		Lab.run()                                   -- the default show
		Lab.cross("tiger", "chick", 6, 900)         -- one more litter row: a x b, count, first seed

	Tint: a part's colour gene is shown through SurfaceAppearance.Color over the part's own
	texture (ColorMap), which only Studio/plugin code may set; a live game would clone
	prepared SurfaceAppearance templates instead.
]]

local AssetService = game:GetService("AssetService")

local here = script.Parent
local Genetics = require(here.Genetics)
local Assembler = require(here.Assembler)
local Library = require(here.PartLibrary)

local Lab = {}

local SPACING = 9
local ROW = 16
local templates: { [string]: MeshPart } = {}

local function makePart(entry): MeshPart
	local template = templates[entry.mesh]
	if not template then
		template = AssetService:CreateMeshPartAsync(Content.fromUri(entry.mesh))
		templates[entry.mesh] = template
	end
	local part = template:Clone()
	part.TextureID = entry.texture
	part:SetAttribute("Texture", entry.texture)
	return part
end

local function paint(part: MeshPart, color: Color3)
	pcall(function()
		local sa = Instance.new("SurfaceAppearance")
		sa.ColorMap = part:GetAttribute("Texture")
		sa.Color = color
		sa.Parent = part
	end)
end

local function root(): Instance
	local folder = workspace:FindFirstChild("PetGeneticsLab")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "PetGeneticsLab"
		folder.Parent = workspace
	end
	return folder
end

local function label(model: Model, title: string, genome)
	local p = Genetics.express(genome)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Genes"
	gui.Size = UDim2.fromOffset(190, 92)
	gui.StudsOffsetWorldSpace = Vector3.new(0, model:GetExtentsSize().Y + 2.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = Color3.fromRGB(28, 26, 38)
	text.BackgroundTransparency = 0.25
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Font = Enum.Font.GothamMedium
	text.TextSize = 11
	text.TextWrapped = true
	text.TextYAlignment = Enum.TextYAlignment.Top
	local parts = {}
	for _, locus in Genetics.Loci do
		local shown, pair = p.parts[locus], genome.loci[locus]
		local hidden = if pair[1] == shown then pair[2] else pair[1]
		if shown ~= "none" or hidden ~= "none" then
			table.insert(parts, locus .. ":" .. shown .. (if hidden ~= shown then "/" .. hidden else ""))
		end
	end
	local s = p.stats
	text.Text = string.format(
		"<b>%s</b>\n%s\nPOW %d  SPD %d  LCK %d  VIT %d\n%s",
		title,
		table.concat(parts, "  "),
		s.power,
		s.speed,
		s.luck,
		s.vitality,
		table.concat(p.skills, " · ")
	)
	text.RichText = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = text
	text.Parent = gui
	gui.Parent = model.PrimaryPart
end

local function spawnPet(genome, title: string, at: Vector3): Model
	local model = Assembler.build(Genetics.express(genome), Library, makePart, paint)
	model.Name = title
	model:PivotTo(model:GetPivot() + at)
	label(model, title, genome)
	model.Parent = root()
	return model
end

local rows = 0

-- One row: a litter of `count` babies of a x b, seeds from `seed`. Returns the babies' genomes.
function Lab.cross(a, b, count: number, seed: number, title: string?)
	local ga = if type(a) == "string" then Genetics.fromSpecies(a) else a
	local gb = if type(b) == "string" then Genetics.fromSpecies(b) else b
	rows += 1
	local z = rows * ROW
	local babies = {}
	for i = 1, count do
		local baby = Genetics.breed(seed + i, ga, gb)
		babies[i] = baby
		spawnPet(baby, string.format("%s #%d", title or (tostring(a) .. " x " .. tostring(b)), i), Vector3.new((i - 1) * SPACING, 0, z))
	end
	return babies
end

function Lab.run()
	local old = workspace:FindFirstChild("PetGeneticsLab")
	if old then
		old:Destroy()
	end
	rows = 0
	local ids = {}
	for id in Library do
		table.insert(ids, id)
	end
	table.sort(ids)
	for i, id in ids do
		spawnPet(Genetics.fromSpecies(id), Genetics.Species[id].name .. " (founder)", Vector3.new((i - 1) * SPACING, 0, 0))
	end
	local f1 = Lab.cross("dragon", "cat", 6, 100)
	Lab.cross("corgi", "chick", 6, 200)
	Lab.cross("tiger", "dog", 6, 300)
	-- Grandchildren of two dragon x cat babies: hidden cat genes (no wings, cat ears) come back.
	Lab.cross(f1[1], f1[2], 6, 400, "F2 (dragon x cat)^2")
	return root()
end

return Lab
