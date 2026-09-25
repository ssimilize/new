--[[
	Snapshot, step 1 of 2: builds a lived-in ranch with the REAL server systems and the
	REAL client (the same ClientHarness the tests use), then writes what a player would see:

	  • every visible BasePart in Workspace (size, CFrame, colour, material, shape, mesh)
	  • the PlayerGui tree (sizes, positions, colours, text, and the layout objects:
	    UIListLayout, UIGridLayout, UIPadding, UICorner, UIStroke, UIScale)
	  • the camera target (the local player's plot) and the viewport size

	    lune run tools/snapshot/scene [out.json] [screen]

	`screen` optionally opens one screen (e.g. Wardrobe) on top of the HUD.
	Step 2 (tools/snapshot/render.mjs) draws the JSON with three.js in headless Chromium.
	The result shows the procedural placeholder art, not final art.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local Vector2, Color3, UDim2, UDim = roblox.Vector2, roblox.Color3, roblox.UDim2, roblox.UDim

local ROOT = string.gsub(process.cwd, "/$", "")
if not fs.isDir(ROOT .. "/tests/specs") and fs.isDir(ROOT .. "/monster-ranch-idle/tests/specs") then
	ROOT ..= "/monster-ranch-idle"
end

local Loader = require("../../tests/runtime/Loader")
Loader.init(ROOT)
Loader.setGlobal("warn", function() end)
local TestKernel = require("../../tests/runtime/TestKernel")
local ClientHarness = require("../../tests/runtime/ClientHarness")
ClientHarness.init(ROOT)

local OUT = process.args[1] or (ROOT .. "/tools/snapshot/scene.json")
local SCREEN = process.args[2]

local Config = Loader.get("Shared.Config")
local Manifest = Loader.get("Server.Manifest")

-- Server: two ranches worth looking at ----------------------------------------------------

local systems = {}
for _, name in Manifest.Systems do
	if name ~= "World" then
		table.insert(systems, name)
	end
end
-- A spring afternoon during Spring Bloom (daytime, clear or blooming weather).
local START = Config.Events.ById.springbloom.startsAt + 2 * 3600
local h = TestKernel.new({ systems = systems, startTime = START })

local function levelTo(p, level: number)
	local P = h:System("Progression")
	while P:GetLevel(p) < level do
		P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "snapshot")
	end
end

local function finishTutorial(p)
	local q = h:Section(p, "Quests")
	q.tutorial.step = #Config.Quests.Tutorial + 1
	q.tutorial.progress = 0
end

local function adult(p, line: string, rarity: number, extra)
	local spec = { line = line, rarity = rarity, stage = 3 }
	for k, v in extra or {} do
		spec[k] = v
	end
	local m = h:System("Monsters"):Create(p, spec, "snapshot", true)
	m.lv = 30
	m.mood = 95
	return m
end

local function dress(p, m, items: { string })
	for _, id in items do
		h:System("Accessories"):Add(p, id, 1)
		h:Call(p, "Accessories.Equip", { id = m.id, accessory = id })
		h:Advance(0.3)
	end
end

local function build(p, pens: number, cast)
	levelTo(p, 32)
	finishTutorial(p)
	local Currency = h:System("Currency")
	Currency:Add(p, "coins", 60000000, "snapshot")
	Currency:Add(p, "gems", 1240, "snapshot")
	Currency:Add(p, "ribbons", 85, "snapshot")
	for _ = 2, pens do
		h:Call(p, "Ranch.BuyPen")
		h:Advance(1.1)
	end
	for i, entry in cast do
		local m = adult(p, entry.line, entry.rarity, entry.spec)
		if entry.acc then
			dress(p, m, entry.acc)
		end
		h:Call(p, "Ranch.Assign", { id = m.id, pen = entry.pen or ((i - 1) % pens + 1) })
		h:Advance(0.2)
	end
	for i, decor in { "flower_bed", "tulip_patch", "bloom_arch", "lantern", "hay_bale" } do
		h:System("Shop"):AddDecor(p, decor, 1)
		h:Call(p, "Ranch.PlaceDecor", { decor = decor, pen = (i - 1) % pens + 1 })
		h:Advance(0.4)
	end
	for slot, egg in { "royal", "crystal", "bloom" } do
		local ids = h:System("Eggs"):Add(p, egg, "snapshot", 1)
		pcall(function()
			h:Call(p, "Eggs.Place", { egg = ids[1], slot = slot })
		end)
		h:Advance(0.4)
	end
end

local me = h:Join(1001, "Rancher")
local friend = h:Join(1002, "Mia")
h:Section(me, "Rebirth").stars = 1
h:System("Shop"):GrantTheme(me, "starfield")
build(me, 4, {
	{ line = "cindlet", rarity = 4, spec = { variant = 1 }, pen = 1, acc = { "royal_crown", "royal_cape" } },
	{ line = "mossbun", rarity = 3, spec = {}, pen = 1, acc = { "flower_crown" } },
	{ line = "zappip", rarity = 5, spec = { muts = { "charged" } }, pen = 1, acc = { "sunglasses" } },
	{ line = "bubblin", rarity = 2, spec = {}, pen = 2, acc = { "red_scarf", "beanie" } },
	{ line = "petalpaw", rarity = 3, spec = {}, pen = 2 },
	{ line = "budling", rarity = 4, spec = { muts = { "blossom" } }, pen = 2, acc = { "bunny_ears", "pink_bow" } },
	{ line = "acornling", rarity = 2, spec = {}, pen = 3, acc = { "backpack" } },
	{ line = "moonmoth", rarity = 5, spec = {}, pen = 3, acc = { "halo" } },
	{ line = "orbiton", rarity = 4, spec = {}, pen = 3 },
	{ line = "cometkit", rarity = 5, spec = { variant = 2 }, pen = 4, acc = { "jetpack", "star_shades" } },
	{ line = "tulipup", rarity = 3, spec = {}, pen = 4, acc = { "sun_hat" } },
	{ line = "pollenpuff", rarity = 3, spec = {}, pen = 4, acc = { "fairy_wings" } },
})
h:Call(me, "Ranch.SetPenTheme", { pen = 2, theme = "starfield" })
build(friend, 2, {
	{ line = "lanternling", rarity = 4, spec = {}, acc = { "top_hat", "monocle" } },
	{ line = "snowmitt", rarity = 3, spec = {} },
	{ line = "shellsnap", rarity = 3, spec = {}, acc = { "hero_mask", "hero_cape" } },
	{ line = "wickit", rarity = 2, spec = {} },
})
h:Advance(3)
-- Rejoin so the client starts from the saved ranch: tutorial done, no queued level-up popups.
me = h:Rejoin(me, 5)
h:Advance(3)

-- Client ---------------------------------------------------------------------------------

local c = ClientHarness.new(h, me, { viewport = Vector2.new(1280, 720) })
c:Advance(4)
if SCREEN then
	c:Open(SCREEN)
	c:Advance(2)
end

-- Dump: parts ------------------------------------------------------------------------------

local function color(c3)
	return { math.floor(c3.R * 255 + 0.5), math.floor(c3.G * 255 + 0.5), math.floor(c3.B * 255 + 0.5) }
end

local function get(inst, prop)
	local ok, v = pcall(function()
		return inst[prop]
	end)
	return if ok then v else nil
end

local parts = {}
for _, inst in c.world.workspace:GetDescendants() do
	if inst:IsA("BasePart") and (get(inst, "Transparency") or 0) < 0.98 then
		local mesh = inst:FindFirstChildOfClass("SpecialMesh")
		local cf = inst.CFrame
		local size = inst.Size
		table.insert(parts, {
			n = inst.Name,
			k = inst.ClassName,
			s = if inst:IsA("Part") then inst.Shape.Name else nil,
			m = if mesh then mesh.MeshType.Name else nil,
			z = { size.X, size.Y, size.Z },
			cf = { cf:GetComponents() },
			c = color(inst.Color),
			mat = inst.Material.Name,
			t = get(inst, "Transparency") or 0,
		})
	end
end

-- Dump: GUI --------------------------------------------------------------------------------

local function udim2(u)
	return if typeof(u) == "UDim2" then { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset } else nil
end

local HELPERS =
	{ UIListLayout = true, UIGridLayout = true, UIPadding = true, UICorner = true, UIStroke = true, UIScale = true, UIGradient = true }

local function dumpGui(inst)
	local node = { k = inst.ClassName, n = inst.Name }
	if inst:IsA("GuiObject") then
		node.v = get(inst, "Visible")
		node.size = udim2(get(inst, "Size"))
		node.pos = udim2(get(inst, "Position"))
		local anchor = get(inst, "AnchorPoint")
		node.anchor = if anchor then { anchor.X, anchor.Y } else nil
		node.bg = color(get(inst, "BackgroundColor3") or Color3.new(1, 1, 1))
		node.bgt = get(inst, "BackgroundTransparency")
		node.z = get(inst, "ZIndex")
		node.lo = get(inst, "LayoutOrder")
		node.rot = get(inst, "Rotation")
		node.clip = get(inst, "ClipsDescendants")
		local auto = get(inst, "AutomaticSize")
		node.auto = if auto then auto.Name else nil
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			node.text = get(inst, "Text")
			node.tc = color(get(inst, "TextColor3") or Color3.new())
			node.ts = get(inst, "TextSize")
			node.tscaled = get(inst, "TextScaled")
			node.twrap = get(inst, "TextWrapped")
			local xa, ya = get(inst, "TextXAlignment"), get(inst, "TextYAlignment")
			node.tx = if xa then xa.Name else nil
			node.ty = if ya then ya.Name else nil
			local font = get(inst, "Font")
			node.font = if font then font.Name else nil
			node.ttr = get(inst, "TextTransparency")
		end
		if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			node.img = get(inst, "Image")
			node.ic = color(get(inst, "ImageColor3") or Color3.new(1, 1, 1))
		end
	elseif inst.ClassName == "UIListLayout" then
		node.dir = inst.FillDirection.Name
		node.pad = udim2(UDim2.new(inst.Padding, UDim.new()))
		node.ha = inst.HorizontalAlignment.Name
		node.va = inst.VerticalAlignment.Name
	elseif inst.ClassName == "UIGridLayout" then
		node.cell = udim2(inst.CellSize)
		node.cpad = udim2(inst.CellPadding)
		node.ha = get(inst, "HorizontalAlignment") and inst.HorizontalAlignment.Name
	elseif inst.ClassName == "UIPadding" then
		node.p = {
			inst.PaddingTop.Offset,
			inst.PaddingRight.Offset,
			inst.PaddingBottom.Offset,
			inst.PaddingLeft.Offset,
		}
	elseif inst.ClassName == "UICorner" then
		node.r = { inst.CornerRadius.Scale, inst.CornerRadius.Offset }
	elseif inst.ClassName == "UIStroke" then
		node.th = inst.Thickness
		node.sc = color(inst.Color)
		node.st = get(inst, "Transparency") or 0
		local mode = get(inst, "ApplyStrokeMode")
		node.mode = if mode then mode.Name else "Contextual"
	elseif inst.ClassName == "UIScale" then
		node.scale = inst.Scale
	elseif inst.ClassName == "UIGradient" then
		local seq = get(inst, "Color")
		if seq then
			node.g = {}
			for _, kp in seq.Keypoints do
				table.insert(node.g, { kp.Time, color(kp.Value) })
			end
		end
		node.grot = get(inst, "Rotation")
	end
	local children = {}
	for _, child in inst:GetChildren() do
		if child:IsA("GuiObject") or HELPERS[child.ClassName] then
			table.insert(children, dumpGui(child))
		end
	end
	if #children > 0 then
		node.ch = children
	end
	return node
end

local guis = {}
for _, gui in c.localPlayer.PlayerGui:GetChildren() do
	if gui:IsA("ScreenGui") and get(gui, "Enabled") ~= false then
		local node = dumpGui(gui)
		node.order = get(gui, "DisplayOrder") or 0
		table.insert(guis, node)
	end
end

-- Camera target: the local player's plot ---------------------------------------------------

local plotIndex = 1
for i, plot in h:Client(me).global.Plots or {} do
	if plot.userId == me.UserId then
		plotIndex = i
	end
end
local plot = Config.World.Plots[plotIndex]

fs.writeFile(
	OUT,
	serde.encode("json", {
		viewport = { 1280, 720 },
		plot = { center = plot.center, facing = plot.facing, index = plotIndex },
		weather = h:Client(me).global.Weather and h:Client(me).global.Weather.id or "clear",
		parts = parts,
		gui = guis,
	})
)
print(string.format("wrote %s: %d parts, %d ScreenGuis, plot %d", OUT, #parts, #guis, plotIndex))
process.exit(0)
