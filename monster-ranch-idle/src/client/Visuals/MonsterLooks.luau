--[[
	MonsterLooks: the Golden, Rainbow and Shadow looks of 3D monsters (MeshMonster), drawn as recoloured
	copies of the form's texture. The placeholder repaints its parts instead (MonsterModel colorsFor);
	a textured MeshPart ignores its Color, so the texture itself has to change.

		MonsterLooks.For(appearance) -> Look?                 "golden" | "rainbow" | "shadow" | nil
		MonsterLooks.Apply(mesh, form, look, textureId)       swaps the mesh's texture once the look is drawn
		MonsterLooks.Recolor(look, pixels, width, height, first?, last?)   pure: RGBA8 rows in place
		MonsterLooks.SetBackend(backend?)                     tests: a fake image factory (nil = the engine's)
		MonsterLooks.Count() -> number                        recoloured images alive

	One EditableImage per (form, look), shared by every monster of that form wearing that look: loaded
	from the texture (AssetService:CreateEditableImageAsync), recoloured a few rows per frame, then set
	as each mesh's TextureContent. EditableImages count against a per-device memory budget (a 1024x1024
	texture is 4 MB), so at most MAX_IMAGES live at once; the least recently used one is destroyed and
	its meshes get their normal texture back. Apply never yields: the monster shows its normal texture
	until the look is ready. Without the API (the Lune mock) or when it fails (permissions, budget) the
	normal texture stays, with one warn per session; the Vfx sparkle still marks the variant.
	Rainbow is a static holographic look (hue across the texture and with brightness): rewriting a
	texture every frame costs too much, so MonsterAnimator never hue-cycles a 3D monster.
]]

local MonsterLooks = {}

export type Look = "golden" | "rainbow" | "shadow"
export type Backend = {
	create: (textureId: string) -> any, -- an EditableImage (Size, ReadPixelsBuffer, WritePixelsBuffer, Destroy)
	bind: (mesh: any, image: any) -> (),
	unbind: (mesh: any, textureId: string) -> (),
}

local MAX_IMAGES = 8
local ROWS_PER_STEP = 96 -- a 1024-wide texture recolours in ~11 frames instead of one long hitch

-- ─── Colour transforms (pure) ───────────────────────────────────────────────────────

-- Ramps over luminance: { t, r, g, b }. Each stop is brighter than the last, so the shading order of
-- the original texture survives.
local GOLD = {
	{ 0, 46, 24, 4 },
	{ 0.3, 150, 92, 14 },
	{ 0.6, 236, 178, 48 },
	{ 0.82, 255, 222, 110 },
	{ 1, 255, 248, 214 },
}
-- The placeholder's shadow body (#3A2D55) and belly (#6B5A8E), with a deeper floor for the creases.
local SHADOW = {
	{ 0, 12, 9, 22 },
	{ 0.5, 58, 45, 85 },
	{ 1, 107, 90, 142 },
}

local function ramp(stops, t: number): (number, number, number)
	for i = 2, #stops do
		local b = stops[i]
		if t <= b[1] or i == #stops then
			local a = stops[i - 1]
			local f = math.clamp((t - a[1]) / (b[1] - a[1]), 0, 1)
			return a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f, a[4] + (b[4] - a[4]) * f
		end
	end
	return stops[1][2], stops[1][3], stops[1][4]
end

-- 256-entry tables indexed by luminance byte, so the per-pixel work is three lookups.
local function table256(stops, gain: number)
	local r, g, b = table.create(256), table.create(256), table.create(256)
	for i = 0, 255 do
		local cr, cg, cb = ramp(stops, math.clamp(i / 255 * gain, 0, 1))
		r[i + 1], g[i + 1], b[i + 1] = math.round(cr), math.round(cg), math.round(cb)
	end
	return { r, g, b }
end

local LUT = { golden = table256(GOLD, 1.1), shadow = table256(SHADOW, 1) }

local function hsv(h: number, s: number, v: number): (number, number, number)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	i %= 6
	if i == 0 then
		return v, t, p
	elseif i == 1 then
		return q, v, p
	elseif i == 2 then
		return p, v, t
	elseif i == 3 then
		return p, q, v
	elseif i == 4 then
		return t, p, v
	end
	return v, p, q
end

-- Recolours rows first..last (0-based, default all) of an RGBA8 buffer in place. Alpha is never touched.
function MonsterLooks.Recolor(look: Look, pixels: buffer, width: number, height: number, first: number?, last: number?)
	local readu8, writeu8 = buffer.readu8, buffer.writeu8
	local y0, y1 = first or 0, math.min(last or height - 1, height - 1)
	local lut = LUT[look]
	if lut then
		local lr, lg, lb = lut[1], lut[2], lut[3]
		for y = y0, y1 do
			local o = y * width * 4
			for _ = 1, width do
				local l = (77 * readu8(pixels, o) + 150 * readu8(pixels, o + 1) + 29 * readu8(pixels, o + 2)) // 256 + 1
				writeu8(pixels, o, lr[l])
				writeu8(pixels, o + 1, lg[l])
				writeu8(pixels, o + 2, lb[l])
				o += 4
			end
		end
	elseif look == "rainbow" then
		-- Holographic: the hue runs diagonally across the texture and shifts with brightness, so
		-- neighbouring shades separate into bands; the brightness keeps the original shading.
		for y = y0, y1 do
			local o = y * width * 4
			local v = y / height * 0.45
			for x = 0, width - 1 do
				local l = (0.299 * readu8(pixels, o) + 0.587 * readu8(pixels, o + 1) + 0.114 * readu8(pixels, o + 2)) / 255
				local r, g, b = hsv((x / width * 0.7 + v + l * 0.6) % 1, 0.55, math.clamp(0.28 + l * 0.8, 0, 1))
				writeu8(pixels, o, math.round(r * 255))
				writeu8(pixels, o + 1, math.round(g * 255))
				writeu8(pixels, o + 2, math.round(b * 255))
				o += 4
			end
		end
	end
end

-- The look an appearance wears, with the placeholder's precedence: Rainbow (the animator's hue
-- cycle wins there), then the shadow mutation (painted over Golden), then Golden.
function MonsterLooks.For(appearance): Look?
	if appearance.variant == 2 then
		return "rainbow"
	end
	for _, m in appearance.muts or {} do
		if m == "shadow" then
			return "shadow"
		end
	end
	if appearance.variant == 1 then
		return "golden"
	end
	return nil
end

-- ─── Shared images ───────────────────────────────────────────────────────────────────

type Entry = { image: any?, used: number, users: { [any]: boolean }, texture: string }

local entries: { [string]: Entry } = {}
local failed: { [string]: boolean } = {}
local count = 0
local clock = 0
local backend: Backend? = nil
local engine: (Backend | false)? = nil
local warned = false

local function fail(reason: string)
	if not warned then
		warned = true
		warn("[MonsterLooks] 3D monsters keep their normal texture (Golden, Rainbow and Shadow looks off): " .. reason)
	end
end

-- The engine's EditableImage API, looked up once; false when this runtime lacks it.
local function engineBackend(): Backend?
	if engine == nil then
		local ok = pcall(function()
			assert(Content and Content.fromUri and Content.fromObject, "no Content")
			assert(game:GetService("AssetService").CreateEditableImageAsync, "no CreateEditableImageAsync")
		end)
		engine = if ok
			then {
				create = function(textureId: string)
					return (game:GetService("AssetService") :: any):CreateEditableImageAsync(Content.fromUri(textureId))
				end,
				bind = function(mesh, image)
					mesh.TextureContent = Content.fromObject(image)
				end,
				unbind = function(mesh, textureId: string)
					mesh.TextureContent = Content.fromUri(textureId)
				end,
			}
			else false
	end
	return if engine then engine else nil
end

local function release(key: string, api: Backend)
	local entry = entries[key]
	if not entry then
		return
	end
	entries[key] = nil
	count -= 1
	if entry.image then
		for mesh in entry.users do
			pcall(api.unbind, mesh, entry.texture)
		end
		pcall(function()
			entry.image:Destroy()
		end)
	end
end

local function evict(keep: string, api: Backend)
	while count > MAX_IMAGES do
		local oldest, at = nil, math.huge
		for key, entry in entries do
			if key ~= keep and entry.used < at then
				oldest, at = key, entry.used
			end
		end
		if not oldest then
			return
		end
		release(oldest, api)
	end
end

local function draw(key: string, entry: Entry, look: Look, api: Backend)
	local ok, image = pcall(function()
		local image = api.create(entry.texture)
		local size = image.Size
		local width, height = size.X, size.Y
		local pixels = image:ReadPixelsBuffer(Vector2.zero, size)
		for first = 0, height - 1, ROWS_PER_STEP do
			if first > 0 then
				task.wait()
			end
			MonsterLooks.Recolor(look, pixels, width, height, first, first + ROWS_PER_STEP - 1)
		end
		image:WritePixelsBuffer(Vector2.zero, size, pixels)
		return image
	end)
	if entries[key] ~= entry then -- evicted while it was drawing
		if ok then
			pcall(function()
				image:Destroy()
			end)
		end
		return
	end
	if not ok then
		fail(tostring(image))
		failed[key] = true
		entries[key] = nil
		count -= 1
		for mesh in entry.users do
			pcall(api.unbind, mesh, entry.texture)
		end
		return
	end
	entry.image = image
	for mesh in entry.users do
		pcall(api.bind, mesh, image)
	end
end

-- An entry holds its meshes strongly until they are destroyed: a weak key could lose a mesh whose Lua
-- wrapper was collected while the part lives on, and that mesh would never get its drawn look.
local function hold(entry: Entry, mesh: any)
	if entry.users[mesh] then
		return
	end
	entry.users[mesh] = true
	pcall(function()
		mesh.Destroying:Once(function()
			entry.users[mesh] = nil
		end)
	end)
end

-- Gives `mesh` the look: at once when the form's look is drawn, else when it finishes. Never yields.
function MonsterLooks.Apply(mesh: any, form: string, look: Look?, textureId: string)
	if look == nil or (LUT[look] == nil and look ~= "rainbow") then
		return
	end
	local api = backend or engineBackend()
	if not api then
		fail("no EditableImage API")
		return
	end
	local key = form .. "|" .. look
	if failed[key] then
		return
	end
	clock += 1
	local entry = entries[key]
	if entry then
		entry.used = clock
		hold(entry, mesh)
		if entry.image then
			pcall(api.bind, mesh, entry.image)
		end
		return
	end
	entry = { image = nil, used = clock, users = {}, texture = textureId }
	hold(entry, mesh)
	entries[key] = entry
	count += 1
	evict(key, api)
	task.spawn(draw, key, entry, look, api)
end

function MonsterLooks.SetBackend(fake: Backend?)
	local api = backend or engineBackend()
	if api then
		for key in entries do
			release(key, api)
		end
	end
	table.clear(entries)
	table.clear(failed)
	count, warned = 0, false
	backend = fake
end

function MonsterLooks.Count(): number
	return count
end

return MonsterLooks
