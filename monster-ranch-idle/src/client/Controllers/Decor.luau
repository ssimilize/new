--[[
	Decor controller (glow-up Z · Build your ranch): draws every plot's placed decor and runs the
	world side of placement mode (the Decorate screen is its toolbar and tray).

	Drawing (global.Plots[i].layout, Visuals/DecorModel into Workspace.Decor.Plot<i>): pieces are
	diffed by id + spot + rotation, so only what changed is rebuilt. Own plot: full detail. Other
	plots: `small` parts dropped past Config.Decor.Layout.farDistance (and always in low graphics),
	nothing drawn past hideDistance; the distance is re-checked every 2 s, never per frame.
	A piece's anchor part carries DecorId / PropId, PenSpot = "toy" for toys (pen monsters go to
	them) and Pen = index when it stands in a pen.

	Night lights: light pieces (Config.Decor `light`) glow Neon all day; at night (Logic/Ambience
	with Config.Ambience.Lights hours) a pool of PointLights sits on the `max` nearest within
	`radius` of the camera (`maxLow` in low graphics), refreshed twice a second.

	Placement mode (Decor.Enter / Decor.Exit, by the Decorate screen):
	  the HUD hides, the camera looks down on the own plot, a grid overlay shows the keep-outs in
	  red, and a draft copy of the layout is edited: Add(id) at the nearest free spot, tap a piece to
	  select it, tap or drag the ground to move it, Rotate (45°), Remove (back to the tray), Undo
	  (Config.Decor.Layout.undo steps), Save (Decor.Save with the whole draft). Bad pieces show a red
	  box, the selected one a white box. Pad: D-pad nudges, X rotates, Y removes, L1 undo, R1 next piece.
	  Exit restores the HUD, the camera and the saved layout.

	Public (for the screen and specs):
	  Decor.Enter() -> (ok, err?)   Decor.Exit()   Decor.Active() -> boolean
	  Decor.Draft() -> { entry }    Decor.Selected() -> index?   Decor.Problems() -> { [i] = err }
	  Decor.Available() -> { [id] = n }   pieces left for the tray (storage + saved − draft)
	  Decor.Add(id) -> (ok, err?)   Decor.Select(i)   Decor.MoveTo(x, z)   Decor.Nudge(dx, dz)
	  Decor.Rotate()   Decor.Remove()   Decor.Undo() -> boolean   Decor.Save() -> (ok, err?)
	  Decor.Dirty() -> boolean      Decor.TapAt(worldPosition)   (a tap on the ground, as input does)
	  Decor.Changed                  Signal fired after every draft change
	  Decor.PlotFolder(index) -> Folder?   Decor.Count(index) -> pieces drawn on that plot
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Layout = require(Shared.Logic.DecorLayout)
local Ambience = require(Shared.Logic.Ambience)
local Signal = require(Shared.Kernel.Signal)

local Client = script.Parent.Parent
local DecorModel = require(Client.Visuals.DecorModel)
local Quality = require(Client.Visuals.Quality)

local Decor = {
	Name = "Decor",
	Dependencies = {},
}

local L = Config.Decor.Layout
local W = Config.World
local G = L.grid
local CHECK_SECONDS = 2
local LIGHT_SECONDS = 0.5
local PLOT_TOP = 0.3 -- plot floor top (Build.luau: a 0.6 floor at GroundY)
local PEN_TOP = 0.4 -- pen floor top
local BAD = Color3.fromHex("#FF4B4B")
local PICK = Color3.fromHex("#FFFFFF")

local ctx
local player = Players.LocalPlayer
local root: Folder? = nil
local views = {} -- [plotIndex] = { folder, pieces = { [key] = { model, glow } }, detail, userId }
local latest = nil -- last global.Plots
local connections = {}
local alive = false
local lightPool = {} -- { PointLight }

Decor.Changed = Signal.new()

-- Placement session (nil when not placing)
local edit = nil

local function plotFrame(index: number): CFrame
	local plot = W.Plots[index]
	local c = plot.center
	return CFrame.new(c[1], W.GroundY, c[3]) * CFrame.Angles(0, math.rad((plot.facing or 0) - 90), 0)
end

local function keyOf(e): string
	return string.format("%s|%d|%d|%d", e.id, e.x, e.z, e.rot or 0)
end

local function originOf(index: number, e): CFrame
	local x, z = Layout.Stud(e)
	local y = if Layout.PenOf(e) then PEN_TOP else PLOT_TOP
	return plotFrame(index) * CFrame.new(x, y, z) * CFrame.Angles(0, math.rad((e.rot or 0) * 45), 0)
end

local function ownIndex(): number?
	for i, plot in if type(latest) == "table" then latest else {} do
		if type(plot) == "table" and plot.userId == player.UserId then
			return i
		end
	end
	return nil
end

local function distanceTo(index: number): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 0
	end
	return (camera.CFrame.Position - plotFrame(index).Position).Magnitude
end

local function detailFor(index: number, userId: number): string
	if userId == player.UserId then
		return "full"
	end
	local d = distanceTo(index)
	if d > L.hideDistance then
		return "none"
	end
	return if d > L.farDistance or Quality.IsLow() then "far" else "full"
end

local function getView(index: number)
	local view = views[index]
	if view then
		return view
	end
	local folder = Instance.new("Folder")
	folder.Name = "Plot" .. index
	folder.Parent = root
	view = { folder = folder, pieces = {}, detail = "full", userId = 0 }
	views[index] = view
	return view
end

local function clearPiece(view, key: string)
	local piece = view.pieces[key]
	if piece then
		piece.model:Destroy()
		view.pieces[key] = nil
	end
end

local function buildEntry(index: number, e, detail: string, parent: Instance)
	local def = Config.Decor.ById[e.id]
	if not def then
		return nil
	end
	local model, anchor, glow = DecorModel.Build(def, originOf(index, e), detail, parent)
	local pen = Layout.PenOf(e)
	if pen then
		anchor:SetAttribute("Pen", pen)
	end
	return { model = model, glow = glow }
end

-- Rebuilds only the pieces whose key changed (all of them when the detail level changes).
local function syncPlot(index: number, plot)
	local view = getView(index)
	local userId = if type(plot) == "table" then tonumber(plot.userId) or 0 else 0
	local list = if type(plot) == "table" and type(plot.layout) == "table" then plot.layout else {}
	local detail = detailFor(index, userId)
	if edit and edit.index == index then
		detail = "none" -- placement mode draws the draft instead
	end
	if detail ~= view.detail or userId ~= view.userId then
		for key in table.clone(view.pieces) do
			clearPiece(view, key)
		end
		view.detail = detail
		view.userId = userId
	end
	if detail == "none" then
		for key in table.clone(view.pieces) do
			clearPiece(view, key)
		end
		return
	end
	local want = {}
	for _, e in list do
		if type(e) == "table" and type(e.x) == "number" and type(e.z) == "number" then
			want[keyOf(e)] = e
		end
	end
	for key in table.clone(view.pieces) do
		if not want[key] then
			clearPiece(view, key)
		end
	end
	for key, e in want do
		if not view.pieces[key] then
			view.pieces[key] = buildEntry(index, e, detail, view.folder)
		end
	end
end

local function syncAll()
	if not root then
		return
	end
	for index = 1, #W.Plots do
		syncPlot(index, if type(latest) == "table" then latest[index] else nil)
	end
end

-- Night lights ------------------------------------------------------------------------------------

local function refreshLights()
	local lights = Config.Ambience.Lights
	local night = Ambience.Night(tonumber(Lighting.ClockTime) or 14, lights.on, lights.off)
	local camera = workspace.CurrentCamera
	local at = if camera then camera.CFrame.Position else Vector3.zero
	local candidates = {}
	if night > 0 then
		for _, view in views do
			for _, piece in view.pieces do
				if piece.glow and piece.glow.Parent then
					local d = (piece.glow.Position - at).Magnitude
					if d <= L.lights.radius then
						table.insert(candidates, { part = piece.glow, d = d })
					end
				end
			end
		end
		table.sort(candidates, function(a, b)
			return a.d < b.d
		end)
	end
	local max = if Quality.IsLow() then L.lights.maxLow else L.lights.max
	for i = 1, math.max(#lightPool, math.min(max, #candidates)) do
		local c = candidates[i]
		local light = lightPool[i]
		if c and i <= max then
			if not light then
				light = Instance.new("PointLight")
				light.Shadows = false
				lightPool[i] = light
			end
			light.Color = c.part.Color
			light.Range = L.lights.range
			light.Brightness = L.lights.brightness * night
			light.Enabled = true
			if light.Parent ~= c.part then
				light.Parent = c.part
			end
		elseif light then
			light.Enabled = false
		end
	end
end

-- Placement mode ------------------------------------------------------------------------------------

local function changed()
	Decor.Changed:Fire()
end

local function snapshot()
	local copy = table.create(#edit.draft)
	for i, e in edit.draft do
		copy[i] = table.clone(e)
	end
	return { draft = copy, selected = edit.selected }
end

local function pushUndo()
	table.insert(edit.undo, snapshot())
	while #edit.undo > L.undo do
		table.remove(edit.undo, 1)
	end
end

local function clearGhosts()
	for _, ghost in edit.ghosts do
		ghost.model:Destroy()
		if ghost.box then
			ghost.box:Destroy()
		end
	end
	table.clear(edit.ghosts)
end

-- Redraws the draft: pieces diffed by key, marker boxes rebuilt (a handful of parts).
local function drawDraft()
	local problems = Layout.Problems(edit.draft)
	edit.problems = problems
	local want = {}
	for i, e in edit.draft do
		want[keyOf(e) .. "#" .. i] = i
	end
	for key, ghost in table.clone(edit.ghosts) do
		if not want[key] then
			ghost.model:Destroy()
			if ghost.box then
				ghost.box:Destroy()
			end
			edit.ghosts[key] = nil
		end
	end
	for key, i in want do
		local e = edit.draft[i]
		local ghost = edit.ghosts[key]
		if not ghost then
			local built = buildEntry(edit.index, e, "full", edit.folder)
			if built then
				ghost = { model = built.model, box = nil }
				edit.ghosts[key] = ghost
			end
		end
		if ghost then
			local marked = problems[i] ~= nil or edit.selected == i
			if marked and not ghost.box then
				local hx, hz = Layout.Half(Config.Decor.ById[e.id], e.rot)
				local x, z = Layout.Stud(e)
				local box = Instance.new("Part")
				box.Name = "Marker"
				box.Anchored = true
				box.CanCollide = false
				box.CanQuery = false
				box.CanTouch = false
				box.CastShadow = false
				box.Material = Enum.Material.Neon
				box.Size = Vector3.new(hx * 2, 0.2, hz * 2)
				box.CFrame = plotFrame(edit.index) * CFrame.new(x, PEN_TOP + 0.12, z)
				box.Parent = edit.folder
				ghost.box = box
			elseif not marked and ghost.box then
				ghost.box:Destroy()
				ghost.box = nil
			end
			if ghost.box then
				ghost.box.Color = if problems[i] then BAD else PICK
				ghost.box.Transparency = if problems[i] then 0.35 else 0.55
			end
		end
	end
	changed()
end

local function overlayPart(name: string, size: Vector3, cf: CFrame, color: Color3, alpha: number)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	part.Transparency = alpha
	part.Size = size
	part.CFrame = cf
	part.Parent = edit.overlay
	return part
end

-- Grid lines every 4 cells and the keep-outs in red (about 45 parts, built once per session).
local function buildOverlay()
	local base = plotFrame(edit.index)
	local sx, sz = W.PlotSize[1], W.PlotSize[2]
	local line = Color3.fromHex("#FFFFFF")
	local step = G * 4
	for x = -math.floor(sx / 2 / step) * step, sx / 2, step do
		overlayPart("GridX", Vector3.new(0.12, 0.05, sz), base * CFrame.new(x, PLOT_TOP + 0.03, 0), line, 0.7)
	end
	for z = -math.floor(sz / 2 / step) * step, sz / 2, step do
		overlayPart("GridZ", Vector3.new(sx, 0.05, 0.12), base * CFrame.new(0, PLOT_TOP + 0.03, z), line, 0.7)
	end
	for _, k in L.keepOut do
		overlayPart("KeepOut", Vector3.new(k[3] * 2, 0.06, k[4] * 2), base * CFrame.new(k[1], PLOT_TOP + 0.05, k[2]), BAD, 0.75)
	end
end

local function ground(position: Vector3): (number, number)
	local p = plotFrame(edit.index):PointToObjectSpace(position)
	return math.floor(p.X / G + 0.5), math.floor(p.Z / G + 0.5)
end

local function screenToGround(screen: Vector3): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local dy = ray.Direction.Y
	if math.abs(dy) < 1e-4 then
		return nil
	end
	local t = (W.GroundY + PLOT_TOP - ray.Origin.Y) / dy
	if t < 0 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

local function pieceAt(x: number, z: number): number?
	for i = #edit.draft, 1, -1 do
		local e = edit.draft[i]
		local hx, hz = Layout.Half(Config.Decor.ById[e.id], e.rot)
		local ex, ez = Layout.Stud(e)
		if math.abs(x * G - ex) <= math.max(hx, G / 2) and math.abs(z * G - ez) <= math.max(hz, G / 2) then
			return i
		end
	end
	return nil
end

local function clampGrid(x: number, z: number): (number, number)
	return math.clamp(x, -Layout.MaxX, Layout.MaxX), math.clamp(z, -Layout.MaxZ, Layout.MaxZ)
end

function Decor.Active(): boolean
	return edit ~= nil
end

function Decor.Draft()
	return if edit then edit.draft else {}
end

function Decor.Selected(): number?
	return if edit then edit.selected else nil
end

function Decor.Problems()
	return if edit then edit.problems else {}
end

function Decor.Dirty(): boolean
	return edit ~= nil and edit.dirty
end

function Decor.Available(): { [string]: number }
	local out = {}
	local storage = ctx and ctx.Store:Get("profile.Shop.decor") or {}
	local saved = Layout.Counts(ctx and ctx.Store:Get("profile.Decor.layout") or {})
	local draft = Layout.Counts(if edit then edit.draft else {})
	for _, def in Config.Decor.List do
		local n = (tonumber(storage[def.id]) or 0) + (saved[def.id] or 0) - (draft[def.id] or 0)
		if n > 0 then
			out[def.id] = n
		end
	end
	return out
end

function Decor.Select(i: number?)
	if not edit then
		return
	end
	edit.selected = if i and edit.draft[i] then i else nil
	drawDraft()
end

function Decor.Add(id: string): (boolean, string?)
	if not edit then
		return false, nil
	end
	if (Decor.Available()[id] or 0) <= 0 then
		return false, "You don't own enough of that decor"
	end
	local level = tonumber(ctx.Store:Get("profile.Progression.level")) or 1
	local cap = Layout.Cap(level)
	if #edit.draft >= cap then
		return false, string.format("Your ranch holds up to %d decorations. Level up for more!", cap)
	end
	local fx, fz = 0, 12
	local sel = edit.selected and edit.draft[edit.selected]
	if sel then
		fx, fz = sel.x, sel.z
	end
	local x, z = Layout.FreeSpot(edit.draft, id, fx, fz, 0)
	if not x then
		return false, "There's no free spot for that piece"
	end
	pushUndo()
	table.insert(edit.draft, { id = id, x = x, z = z :: number, rot = 0 })
	edit.selected = #edit.draft
	edit.dirty = true
	drawDraft()
	return true, nil
end

function Decor.MoveTo(x: number, z: number)
	if not edit or not edit.selected then
		return
	end
	local e = edit.draft[edit.selected]
	local cx, cz = clampGrid(x, z)
	if e.x == cx and e.z == cz then
		return
	end
	if not edit.dragging or not edit.dragPushed then
		pushUndo()
		edit.dragPushed = edit.dragging ~= nil
	end
	e.x, e.z = cx, cz
	edit.dirty = true
	drawDraft()
end

function Decor.Nudge(dx: number, dz: number)
	if edit and edit.selected then
		local e = edit.draft[edit.selected]
		Decor.MoveTo(e.x + dx, e.z + dz)
	end
end

function Decor.Rotate()
	if not edit or not edit.selected then
		return
	end
	pushUndo()
	local e = edit.draft[edit.selected]
	e.rot = ((e.rot or 0) + 1) % 8
	edit.dirty = true
	drawDraft()
end

function Decor.Remove()
	if not edit or not edit.selected then
		return
	end
	pushUndo()
	table.remove(edit.draft, edit.selected)
	edit.selected = nil
	edit.dirty = true
	drawDraft()
end

function Decor.Undo(): boolean
	if not edit or #edit.undo == 0 then
		return false
	end
	local snap = table.remove(edit.undo)
	edit.draft = snap.draft
	edit.selected = if snap.selected and snap.draft[snap.selected] then snap.selected else nil
	edit.dirty = true
	drawDraft()
	return true
end

function Decor.Save(): (boolean, string?)
	if not edit then
		return false, nil
	end
	local payload = {}
	for i, e in edit.draft do
		payload[i] = { id = e.id, x = e.x, z = e.z, rot = e.rot or 0 }
	end
	local ok, res = ctx.Net:RequestOnce("Decor.Save", { layout = payload })
	if not ok then
		local err = if type(res) == "string" then res else nil
		-- Point at the first bad piece so the player sees what to fix.
		for i in edit.problems do
			edit.selected = i
			break
		end
		drawDraft()
		return false, err
	end
	edit.dirty = false
	edit.undo = {}
	changed()
	return true, nil
end

function Decor.TapAt(position: Vector3)
	if not edit then
		return
	end
	local x, z = ground(position)
	local hit = pieceAt(x, z)
	if hit then
		if hit ~= edit.selected then
			Decor.Select(hit)
		end
		return
	end
	Decor.MoveTo(x, z)
end

local function connectInput()
	local function pointer(input: InputObject): boolean
		local kind = input.UserInputType
		return kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
	end
	table.insert(
		edit.conns,
		UserInputService.InputBegan:Connect(function(input, processed)
			if not edit then
				return
			end
			if input.UserInputType == Enum.UserInputType.Gamepad1 then
				local key = input.KeyCode
				if key == Enum.KeyCode.DPadLeft then
					Decor.Nudge(-1, 0)
				elseif key == Enum.KeyCode.DPadRight then
					Decor.Nudge(1, 0)
				elseif key == Enum.KeyCode.DPadUp then
					Decor.Nudge(0, -1)
				elseif key == Enum.KeyCode.DPadDown then
					Decor.Nudge(0, 1)
				elseif key == Enum.KeyCode.ButtonX then
					Decor.Rotate()
				elseif key == Enum.KeyCode.ButtonY then
					Decor.Remove()
				elseif key == Enum.KeyCode.ButtonL1 then
					Decor.Undo()
				elseif key == Enum.KeyCode.ButtonR1 and #edit.draft > 0 then
					Decor.Select(((edit.selected or 0) % #edit.draft) + 1)
				end
				return
			end
			if processed or not pointer(input) then
				return
			end
			local at = screenToGround(input.Position)
			if at then
				Decor.TapAt(at)
				if edit and edit.selected then
					edit.dragging = input
					edit.dragPushed = false
				end
			end
		end)
	)
	table.insert(
		edit.conns,
		UserInputService.InputChanged:Connect(function(input)
			if not edit or not edit.dragging then
				return
			end
			local kind = input.UserInputType
			if kind ~= Enum.UserInputType.MouseMovement and kind ~= Enum.UserInputType.Touch then
				return
			end
			local at = screenToGround(input.Position)
			if at then
				local x, z = ground(at)
				Decor.MoveTo(x, z)
			end
		end)
	)
	table.insert(
		edit.conns,
		UserInputService.InputEnded:Connect(function(input)
			if edit and pointer(input) then
				edit.dragging = nil
			end
		end)
	)
end

function Decor.Enter(): (boolean, string?)
	if edit then
		return true, nil
	end
	local index = ownIndex()
	if not index or not root then
		return false, "Your ranch isn't ready yet"
	end
	local folder = Instance.new("Folder")
	folder.Name = "Placement"
	folder.Parent = root
	local overlay = Instance.new("Folder")
	overlay.Name = "Overlay"
	overlay.Parent = folder
	edit = {
		index = index,
		draft = Layout.Clean(ctx.Store:Get("profile.Decor.layout") or {}),
		undo = {},
		selected = nil,
		problems = {},
		dirty = false,
		dragging = nil,
		dragPushed = false,
		ghosts = {},
		folder = folder,
		overlay = overlay,
		conns = {},
		hud = nil,
		camera = nil,
	}
	-- Hide the game HUD while placing (the Decorate screen is the only UI).
	local ui = ctx.UI
	if ui then
		edit.hud = { hud = ui.Hud and ui.Hud.Visible, top = ui.Top and ui.Top.Visible }
		if ui.Hud then
			ui.Hud.Visible = false
		end
		if ui.Top then
			ui.Top.Visible = false
		end
	end
	local camera = workspace.CurrentCamera
	if camera then
		edit.camera = { type = camera.CameraType, cf = camera.CFrame }
		camera.CameraType = Enum.CameraType.Scriptable
		local base = plotFrame(index)
		camera.CFrame = CFrame.lookAt((base * CFrame.new(0, 105, 70)).Position, (base * CFrame.new(0, 0, 4)).Position)
	end
	syncPlot(index, latest and latest[index])
	buildOverlay()
	connectInput()
	drawDraft()
	return true, nil
end

function Decor.Exit()
	if not edit then
		return
	end
	local session = edit
	for _, c in session.conns do
		c:Disconnect()
	end
	clearGhosts()
	session.folder:Destroy()
	local ui = ctx.UI
	if ui and session.hud then
		if ui.Hud then
			ui.Hud.Visible = session.hud.hud ~= false
		end
		if ui.Top then
			ui.Top.Visible = session.hud.top ~= false
		end
	end
	local camera = workspace.CurrentCamera
	if camera and session.camera then
		camera.CameraType = session.camera.type
		camera.CFrame = session.camera.cf
	end
	edit = nil
	syncPlot(session.index, latest and latest[session.index])
	changed()
end

function Decor.PlotFolder(index: number): Folder?
	local view = views[index]
	return if view then view.folder else nil
end

function Decor.Count(index: number): number
	local view = views[index]
	local n = 0
	for _ in if view then view.pieces else {} do
		n += 1
	end
	return n
end

-- Lifecycle ------------------------------------------------------------------------------------------

function Decor.Init(context)
	ctx = context
end

function Decor.Start()
	alive = true
	local folder = Instance.new("Folder")
	folder.Name = "Decor"
	folder.Parent = workspace
	root = folder
	table.insert(
		connections,
		ctx.Store:Observe("global.Plots", function(list)
			latest = list
			syncAll()
		end)
	)
	local function check()
		if not alive then
			return
		end
		syncAll()
		task.delay(CHECK_SECONDS, check)
	end
	task.delay(CHECK_SECONDS, check)
	local function lights()
		if not alive then
			return
		end
		refreshLights()
		task.delay(LIGHT_SECONDS, lights)
	end
	task.delay(LIGHT_SECONDS, lights)
end

function Decor.Destroy()
	alive = false
	Decor.Exit()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	table.clear(views)
	table.clear(lightPool)
	if root then
		root:Destroy()
		root = nil
	end
end

return Decor
