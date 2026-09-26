--[[
	Companions controller (glow-up T): draws every player's companions (global.Companions.walkers)
	and walks them beside their owner, on every client. Rules and tuning: Logic/Companions,
	Config/Companions; the server picks who walks (Systems/Companions).

	  Follow     each companion has a spot in a small V around its owner (Logic.Spot, in the
	             owner's facing), trots there at a speed that eases in as it arrives
	             (Logic.Speed; the walk clip matches it through Visuals/Gait), idles when close,
	             sits once the owner has stood still for a moment, hops when the owner jumps and
	             appears at its spot when it falls far behind or the owner teleports.
	  Ground     one ray down at the companion (else the owner's feet height) and one from the
	             owner to the spot, so a spot behind a wall is pulled back to the owner's side.
	             Companions never collide, touch or take queries: they can't block a door, and
	             thin decor is walked through.
	  Hidden     while the owner rides (global.Riding.riders), has no character, or (our own)
	             while the Racing or Surf screen is open. Photo mode keeps them: they are pose
	             subjects through World:OwnMonstersNear (Companions:PoseSubjects).
	  Phones     our own are always drawn; other players' only within DrawDistance, nearest
	             first, at most MaxOthers companions (MaxOthersLow in low graphics), re-picked
	             every PickEvery seconds; those past NearDistance update at FarHz. Other players'
	             effects follow Vfx's other-plot rules (SetOwned false).
	  HUD        a small 🐾 badge (bottom right) while our own companions walk; it opens the
	             first one's MonsterDetail, where "Walk with me" / "Stop walking" lives
	             (UI/Screens/Parts/WalkToggle).

	Public:
	  Companions:PoseSubjects(position, radius, found)   appends { model, animator, distance } for
	                                                      our drawn companions (photo mode's Pose)
	  Companions:StateOf(userId, index) -> string?        "walk" | "idle" | "sit" | "hop" | a one-shot
	  Companions:ModelOf(userId, index) -> Model?
	  Companions:Count() -> number                         companion models currently drawn
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Logic = require(ReplicatedStorage.Shared.Logic.Companions)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Button = require(UI.Components.Button)
local StoreKit = require(UI.Components.StoreKit)
local Visuals = script.Parent.Parent.Visuals
local MonsterModel = require(Visuals.MonsterModel)
local Gait = require(Visuals.Gait)
local Vfx = require(Visuals.Vfx)

local Cfg = Config.Companions
local UP = Vector3.new(0, 1, 0)
local MINIGAMES = { "Racing", "Surf" }

local Companions = {
	Name = "Companions",
	Dependencies = { "Riding" },
}

local ctx
local folder: Folder? = nil
local owners = {} -- [userId] = owner record
local ownerList = {} -- the same records, as an array for the frame loop
local rayParams: RaycastParams? = nil
local badge = nil
local pickClock = 0
local lowGraphics = false

local function localId(): number
	return Players.LocalPlayer.UserId
end

local function destroyModel(comp)
	if comp.model then
		Vfx.Clear(comp.model)
		comp.model:Destroy()
	end
	comp.model, comp.gait, comp.poser = nil, nil, nil
end

local function build(owner, comp)
	local ok, model = pcall(MonsterModel.Build, comp.appearance, { anchored = true })
	if not ok or not model then
		comp.failed = true
		return
	end
	model.Name = "Companion"
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	model:SetAttribute("Owner", owner.userId)
	comp.model = model
	comp.gait = Gait.new(model)
	comp.height = comp.gait.height
	comp.placed = false
	local gait = comp.gait
	comp.poser = {
		_state = "idle",
		Play = function(self, state: string)
			self._state = if gait:Play(state) then state else "idle"
		end,
		GetPosition = function()
			return comp.pos
		end,
	}
	Vfx.SetOwned(model, owner.userId == localId())
end

-- Walkers changed: match each owner's list by index, rebuilding a companion whose look changed.
local function refresh()
	local walkers = StoreKit.tbl(ctx.Store, "global.Companions.walkers")
	local seen = {}
	for key, list in walkers do
		local userId = tonumber(string.match(tostring(key), "^u(%d+)$"))
		if userId and type(list) == "table" then
			seen[userId] = true
			local owner = owners[userId]
			if not owner then
				owner = { userId = userId, comps = {}, last = nil, speed = 0, stillFor = 0, hidden = true, wanted = false, hopLeft = 0 }
				owners[userId] = owner
			end
			for i, entry in list do
				local sig = Logic.Signature(entry.appearance)
				local comp = owner.comps[i]
				if comp and comp.sig ~= sig then
					destroyModel(comp)
					comp = nil
				end
				if not comp then
					comp =
						{ sig = sig, index = i, pos = Vector3.zero, look = Vector3.new(0, 0, -1), state = "idle", hopLeft = 0, height = 3 }
					owner.comps[i] = comp
				end
				comp.appearance = entry.appearance
				comp.id = entry.id
				comp.failed = false
			end
			for i = #owner.comps, #list + 1, -1 do
				destroyModel(owner.comps[i])
				owner.comps[i] = nil
			end
		end
	end
	for userId, owner in owners do
		if not seen[userId] then
			for _, comp in owner.comps do
				destroyModel(comp)
			end
			owners[userId] = nil
		end
	end
	table.clear(ownerList)
	for _, owner in owners do
		table.insert(ownerList, owner)
	end
	pickClock = math.huge -- re-pick on the next frame
end

local function rootOf(userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

local function hiddenFor(owner, riders): boolean
	if riders["u" .. tostring(owner.userId)] ~= nil or not rootOf(owner.userId) then
		return true
	end
	if owner.userId == localId() then
		for _, name in MINIGAMES do
			if ctx.Router:Has(name) and ctx.Router:IsOpen(name) then
				return true
			end
		end
	end
	return false
end

-- Who is drawn: our own always, others nearest first within range and under the cap.
local function pick()
	local riders = StoreKit.tbl(ctx.Store, "global.Riding.riders")
	local me = rootOf(localId())
	local here = if me then me.Position else nil
	local entries = {}
	local exclude = { folder }
	for _, owner in ownerList do
		local hrp = rootOf(owner.userId)
		if hrp and hrp.Parent then
			table.insert(exclude, hrp.Parent)
		end
		local hidden = hiddenFor(owner, riders)
		if hidden ~= owner.hidden then
			owner.hidden = hidden
			owner.last = nil
			for _, comp in owner.comps do
				comp.placed = false
			end
		end
		owner.wanted = false
		if not hidden and hrp then
			if owner.userId == localId() then
				owner.wanted = true
			elseif here then
				for _ in owner.comps do
					table.insert(entries, { distance = (hrp.Position - here).Magnitude, owner = owner })
				end
			end
		end
	end
	local cap = if lowGraphics then Cfg.MaxOthersLow else Cfg.MaxOthers
	local allowed = {}
	for _, entry in Logic.Pick(entries, cap, Cfg.DrawDistance) do
		allowed[entry.owner] = (allowed[entry.owner] or 0) + 1
	end
	for _, owner in ownerList do
		if owner.userId ~= localId() then
			owner.wanted = (allowed[owner] or 0) > 0
		end
		local limit = if owner.userId == localId() then #owner.comps else allowed[owner] or 0
		for i, comp in owner.comps do
			local want = owner.wanted and i <= limit
			if want and not comp.model and not comp.failed then
				build(owner, comp)
			elseif not want and comp.model then
				destroyModel(comp)
			end
			if comp.model then
				comp.model.Parent = if owner.hidden then nil else folder
			end
		end
	end
	if rayParams then
		rayParams.FilterDescendantsInstances = exclude
	end
	if badge then
		local own = owners[localId()]
		local n = if own then #own.comps else 0
		badge:SetVisible(n > 0 and riders["u" .. tostring(localId())] == nil)
		badge:SetText(string.format("🐾 %d", n))
	end
end

local function groundY(x: number, z: number, fromY: number, fallback: number): number
	local hit = workspace:Raycast(Vector3.new(x, fromY + Cfg.GroundProbe, z), Vector3.new(0, -Cfg.GroundDepth, 0), rayParams)
	return if hit then hit.Position.Y else fallback
end

local function stepOwner(owner, dt: number)
	local hrp = rootOf(owner.userId)
	if not hrp then
		return
	end
	local pos = hrp.Position
	local last = owner.last
	owner.last = pos
	local teleported = last == nil
	local vy = 0
	if last then
		local dx, dz = pos.X - last.X, pos.Z - last.Z
		local moved = math.sqrt(dx * dx + dz * dz)
		if moved > Cfg.OwnerJump or math.abs(pos.Y - last.Y) > Cfg.OwnerJump then
			teleported = true -- a teleport pad, a respawn or the Sky Gate: no hop, no sprint
		else
			vy = (pos.Y - last.Y) / dt
			owner.speed += (moved / dt - owner.speed) * math.min(1, Cfg.Smoothing * dt)
		end
	end
	owner.stillFor = if owner.speed < Cfg.MoveSpeed then owner.stillFor + dt else 0
	if vy > Cfg.JumpSpeed and owner.hopLeft <= 0 then
		owner.hopLeft = Cfg.HopSeconds
		for _, comp in owner.comps do
			comp.hopLeft = Cfg.HopSeconds
		end
	end
	owner.hopLeft = math.max(0, owner.hopLeft - dt)

	local look = hrp.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 1e-3 then
		look = Vector3.new(0, 0, -1)
	else
		look = look.Unit
	end
	local right = look:Cross(UP)
	local humanoid = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
	local feetY = pos.Y - hrp.Size.Y / 2 - (if humanoid then humanoid.HipHeight else 2)
	local near = true
	local me = rootOf(localId())
	if me and owner.userId ~= localId() then
		near = (me.Position - pos).Magnitude <= Cfg.NearDistance
	end

	for _, comp in owner.comps do
		local model = comp.model
		if not model or not comp.gait then
			continue
		end
		comp.accum = (comp.accum or 0) + dt
		if not near and comp.accum < 1 / Cfg.FarHz and comp.placed then
			continue
		end
		local step = comp.accum
		comp.accum = 0
		local sx, sz = Logic.Spot(comp.index, comp.height)
		local spot = pos + right * sx - look * sz
		local reach = Vector3.new(spot.X - pos.X, 0, spot.Z - pos.Z)
		if reach.Magnitude > 1e-3 then
			local wall = workspace:Raycast(pos, reach, rayParams)
			if wall then
				local pull = math.max(0, (wall.Position - pos).Magnitude - Cfg.WallPad)
				spot = pos + reach.Unit * pull
			end
		end
		if teleported or not comp.placed then
			comp.pos = Vector3.new(spot.X, feetY, spot.Z)
			comp.look = look
			comp.placed = true
		end
		local to = Vector3.new(spot.X - comp.pos.X, 0, spot.Z - comp.pos.Z)
		local distance = to.Magnitude
		if distance > Cfg.TeleportDistance then
			comp.pos = Vector3.new(spot.X, feetY, spot.Z)
			distance = 0
		end
		comp.hopLeft = math.max(0, comp.hopLeft - step)
		comp.state = Logic.State(comp.state, distance, owner.stillFor, comp.hopLeft)
		local speed = 0
		local face = look
		if (comp.state == "walk" or comp.state == "hop") and distance > 1e-3 then
			speed = Logic.Speed(distance, owner.speed)
			local move = math.min(distance, speed * step)
			local dir = to / distance
			comp.pos += dir * move
			if distance > Cfg.StopWalk then
				face = dir
			end
		end
		comp.look = comp.look:Lerp(face, math.min(1, Cfg.TurnRate * step))
		if comp.look.Magnitude < 1e-3 then
			comp.look = look
		end
		local y = groundY(comp.pos.X, comp.pos.Z, feetY, feetY)
		comp.pos = Vector3.new(comp.pos.X, y, comp.pos.Z)
		local lift = comp.gait:Step(comp.state, step, speed)
		if comp.hopLeft > 0 then
			local p = 1 - comp.hopLeft / Cfg.HopSeconds
			lift += math.sin(p * math.pi) * Cfg.HopHeight * comp.height / 3
		end
		local at = Vector3.new(comp.pos.X, y + lift, comp.pos.Z)
		model:PivotTo(CFrame.lookAt(at, at + comp.look))
	end
end

local function step(dt: number)
	if dt <= 0 then
		return
	end
	pickClock += dt
	if pickClock >= Cfg.PickEvery then
		pickClock = 0
		pick()
	end
	for _, owner in ownerList do
		if owner.wanted and not owner.hidden then
			stepOwner(owner, dt)
		end
	end
end

function Companions:PoseSubjects(position: Vector3, radius: number, found: { any })
	local own = owners[localId()]
	if not own or own.hidden then
		return
	end
	for _, comp in own.comps do
		if comp.model and comp.poser then
			local distance = (comp.pos - position).Magnitude
			if distance <= radius then
				table.insert(found, { model = comp.model, animator = comp.poser, distance = distance })
			end
		end
	end
end

function Companions:StateOf(userId: number, index: number): string?
	local owner = owners[userId]
	local comp = owner and owner.comps[index]
	if not comp or not comp.gait then
		return nil
	end
	return comp.gait:State()
end

function Companions:ModelOf(userId: number, index: number): Model?
	local owner = owners[userId]
	local comp = owner and owner.comps[index]
	return comp and comp.model
end

function Companions:Count(): number
	local n = 0
	for _, owner in ownerList do
		for _, comp in owner.comps do
			if comp.model and comp.model.Parent then
				n += 1
			end
		end
	end
	return n
end

function Companions.Init(context)
	ctx = context
end

function Companions.Start()
	local f = Instance.new("Folder")
	f.Name = "Companions"
	f.Parent = workspace
	folder = f
	rayParams = RaycastParams.new()
	badge = Button.new({
		Name = "CompanionBadge",
		Text = "🐾 1",
		Color = Theme.Colors.Green,
		TextSize = Theme.TextSize.Body,
		Size = UDim2.fromOffset(84, 48),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -64),
		Parent = ctx.UI.Hud,
		OnClick = function()
			local ids = StoreKit.tbl(ctx.Store, "profile.Companions.ids")
			if type(ids[1]) == "string" and StoreKit.monster(ctx.Store, ids[1]) then
				ctx.Router:Open("MonsterDetail", { id = ids[1] })
			end
		end,
	})
	badge:SetVisible(false)
	ctx.Store:Observe("global.Companions.walkers", refresh)
	ctx.Store:Observe("global.Riding.riders", function()
		pickClock = math.huge
	end)
	ctx.Store:Observe("profile.Settings", function()
		local settings = StoreKit.tbl(ctx.Store, "profile.Settings")
		lowGraphics = settings.lowGraphics == true
		pickClock = math.huge
	end)
	Players.PlayerRemoving:Connect(function()
		pickClock = math.huge
	end)
	refresh()
	RunService.Heartbeat:Connect(step)
end

return Companions
