--[[
	Social (S5): friends-on-server boost, petting and liking other ranches, and broadcasts.

	Save section (profile.Social):
	  day        = UTC day the counters below belong to
	  petsGiven  = pets given today (≤ Config.Social.PetsPerDay)
	  likesGiven = { ["u" .. userId] = true }   -- ranches liked today (≤ LikesPerDay, one per owner)
	  likes      = total likes this player's ranch has received

	Session (session.Social): { friendBoost, friendsHere }
	  friendBoost = Economy.FriendBoost.perFriend × friends on this server (capped at max).
	  Friendships come from ctx.Services.Players.IsFriendsWith (cached per pair), recomputed
	  when anyone joins or leaves; RateModifiersChanged is published for affected players.

	Actions:
	  Social.Pet { owner, id }  -- owner's monster +PetMood (× Charmer), petter +FriendshipPerPet
	  Social.Like { owner }     -- +1 like on the owner's ranch; PlotChanged for the owner, RanchLiked (glow-up Y)

	Broadcasts (Social.Broadcast event): EggHatched (rarity/variant/Huge rules in
	Config.Social.Broadcasts), Bred (hybrid discovery, Huge), Mutated (Prismatic) and
	WeatherChanged (weather with a `broadcast` scope, i.e. Aurora). "global" broadcasts are also
	published through ctx.Services.Messaging and re-broadcast by every other server.

	Public API:
	  Social:GetFriendBoost(player) -> pct (0.1 = +10%)
	  Social:GetLikes(player) -> number
	  Social:AddLike(player)          -- glow-up Y: +1 like from a snapshot visit (Visits mail)
	  Social:Broadcast(kind, text, player?, appearance?, scope?)   -- scope "server" (default) | "global" | "none"
	Registers the Ranch rate modifier "friends" (optional dependency) in Start().
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Appearance = require(Shared.Logic.Appearance)
local Formulas = require(Shared.Logic.Formulas)

local Social = {
	Name = "Social",
	Dependencies = { "Currency", "Monsters" },
	OptionalDependencies = { "Ranch" },
}

Social.Profile = {
	Version = 1,
	Default = function()
		return { day = 0, petsGiven = 0, likesGiven = {}, likes = 0 }
	end,
}

local ctx
local Config
local Currency, Monsters

local present = {} -- [player] = true from PlayerAdded until PlayerRemoving
local friendCache = {} -- [player] = { [userId] = boolean }
local globalWindow = { startedAt = 0, count = 0 }

local SCOPE_RANK = { none = 0, server = 1, global = 2 }

-- Helpers ---------------------------------------------------------------------------------

local function displayName(player): string
	return player.DisplayName or player.Name
end

local function article(word: string): string
	return if string.find(word, "^[AEIOUaeiou]") then "an" else "a"
end

local function widest(a: string?, b: string?): string?
	local ra, rb = SCOPE_RANK[a or "none"] or 0, SCOPE_RANK[b or "none"] or 0
	if ra == 0 and rb == 0 then
		return nil
	end
	return if ra >= rb then a else b
end

local function refreshDay(player, s)
	local today = ctx:Day()
	if s.day ~= today then
		s.day = today
		s.petsGiven = 0
		s.likesGiven = {}
		ctx:Dirty(player)
	end
end

local function areFriends(p, q): boolean
	local cache = friendCache[p]
	if cache and cache[q.UserId] ~= nil then
		return cache[q.UserId]
	end
	local players = ctx.Services.Players
	local result = players.IsFriendsWith(p, q.UserId) == true or players.IsFriendsWith(q, p.UserId) == true
	friendCache[p] = friendCache[p] or {}
	friendCache[p][q.UserId] = result
	friendCache[q] = friendCache[q] or {}
	friendCache[q][p.UserId] = result
	return result
end

local function recomputeBoost(player)
	local sess = ctx:Session(player)
	if not sess then
		return
	end
	local count = 0
	for other in present do
		if other ~= player and areFriends(player, other) then
			count += 1
		end
	end
	local rules = Config.Economy.FriendBoost
	local boost = math.floor(math.min(rules.max, rules.perFriend * count) * 1000 + 0.5) / 1000
	if sess.friendsHere ~= count or sess.friendBoost ~= boost then
		sess.friendsHere = count
		sess.friendBoost = boost
		ctx:DirtySession(player)
		ctx.Bus:Publish("RateModifiersChanged", player, {})
	end
end

local function mustOwner(player, ownerId: number)
	if ownerId == player.UserId then
		return nil
	end
	local owner = ctx:PlayerByUserId(ownerId)
	if not owner then
		ctx:Fail("That rancher isn't on this server anymore")
	end
	return owner
end

local function allowGlobal(): boolean
	local now = ctx:Now()
	if now - globalWindow.startedAt >= 60 then
		globalWindow.startedAt = now
		globalWindow.count = 0
	end
	if globalWindow.count >= Config.Social.GlobalBroadcastsPerMinute then
		return false
	end
	globalWindow.count += 1
	return true
end

-- Public API --------------------------------------------------------------------------------

function Social:GetFriendBoost(player): number
	local sess = ctx:Session(player)
	return sess and sess.friendBoost or 0
end

function Social:GetLikes(player): number
	local s = ctx:Section(player)
	return s and s.likes or 0
end

-- Glow-up Y: a like given to this player's ranch snapshot on another server (Visits mail).
function Social:AddLike(player)
	local s = ctx:Section(player)
	if not s then
		return
	end
	s.likes = (s.likes or 0) + 1
	ctx:Dirty(player, "likes")
	ctx.Bus:Publish("PlotChanged", player, {})
end

function Social:Broadcast(kind: string, text: string, player, appearance, scope: string?)
	local where = scope or "server"
	if where == "none" then
		return
	end
	local payload = {
		kind = kind,
		text = string.sub(text, 1, Config.Social.BroadcastTextMax),
		userId = if player then player.UserId else 0,
		appearance = appearance or nil,
	}
	ctx.Net:FireAll("Social.Broadcast", payload)
	if where == "global" and Config.Flags.GlobalBroadcasts and allowGlobal() then
		ctx.Services.Messaging.Publish(Config.Social.Broadcasts.topic, {
			job = ctx.Services.JobId,
			kind = payload.kind,
			text = payload.text,
			userId = payload.userId,
			appearance = payload.appearance,
		})
	end
end

-- Broadcast rules -------------------------------------------------------------------------------

local function onHatched(player, detail)
	local m = Monsters:Get(player, detail.id)
	if not m then
		return
	end
	local rules = Config.Social.Broadcasts
	local rarity = detail.rarity or m.rarity
	local variant = detail.variant or m.variant or 0
	local special = widest(rules.hatchRarity[rarity], rules.hatchVariant[variant])
	local huge = Formulas.IsHuge(m)
	local scope = widest(special, if huge then rules.hugeWeight else nil)
	if not scope then
		return
	end
	local words = {}
	if huge then
		table.insert(words, "HUGE")
	end
	if variant > 0 then
		table.insert(words, Config.Rarities.Variants[variant].name)
	end
	table.insert(words, Config.Rarities.List[rarity].name)
	table.insert(words, Formulas.FormName(m))
	local phrase = table.concat(words, " ")
	local suffix = if huge then string.format(" (%.2f kg)", m.weight) else ""
	local text = string.format("%s hatched %s %s%s!", displayName(player), article(phrase), phrase, suffix)
	Social:Broadcast(if special then "hatch" else "huge", text, player, Appearance.Of(m), scope)
end

local function onBred(player, detail)
	local m = Monsters:Get(player, detail.id)
	if not m then
		return
	end
	local rules = Config.Social.Broadcasts
	if detail.discovery then
		local text = string.format("%s discovered a new hybrid: %s!", displayName(player), Formulas.FormName(m))
		Social:Broadcast("discovery", text, player, Appearance.Of(m), rules.hybridDiscovery)
	elseif Formulas.IsHuge(m) then
		local text = string.format("%s bred a HUGE %s (%.2f kg)!", displayName(player), Formulas.FormName(m), m.weight)
		Social:Broadcast("huge", text, player, Appearance.Of(m), rules.hugeWeight)
	end
end

-- Scope for a weather announcement: Config.Social.Broadcasts[weatherId] wins over the
-- weather's own `broadcast` field.
local function weatherScope(weather): string?
	return Config.Social.Broadcasts[weather.id] or weather.broadcast
end

-- Weather that announces itself (Aurora) also announces the mutation it gives.
local function broadcastWeatherFor(mutationId: string)
	for _, w in Config.Weather.List do
		if w.mutation == mutationId and weatherScope(w) then
			return w
		end
	end
	return nil
end

local function onMutated(player, detail)
	local weather = broadcastWeatherFor(detail.mutation)
	if not weather then
		return
	end
	local m = Monsters:Get(player, detail.id)
	local mutation = Config.Mutations.ById[detail.mutation]
	if not m or not mutation then
		return
	end
	local text = string.format("%s's %s caught the %s mutation!", displayName(player), Formulas.DisplayName(m), mutation.name)
	Social:Broadcast("mutation", text, player, Appearance.Of(m), weatherScope(weather))
end

local function onWeather(_player, detail)
	local weather = Config.Weather.ById[detail.id or ""]
	local scope = weather and weatherScope(weather)
	if not scope then
		return
	end
	local mutation = weather.mutation and Config.Mutations.ById[weather.mutation]
	local text = if mutation
		then string.format("%s has appeared! %s mutations are possible while it lasts.", weather.name, mutation.name)
		else string.format("%s has appeared!", weather.name)
	Social:Broadcast("weather", text, nil, nil, scope)
end

local function onRemoteBroadcast(data)
	if type(data) ~= "table" or data.job == ctx.Services.JobId then
		return
	end
	if type(data.kind) ~= "string" or type(data.text) ~= "string" then
		return
	end
	ctx.Net:FireAll("Social.Broadcast", {
		kind = string.sub(data.kind, 1, 32),
		text = string.sub(data.text, 1, Config.Social.BroadcastTextMax),
		userId = if type(data.userId) == "number" then data.userId else 0,
		appearance = if type(data.appearance) == "table" then data.appearance else nil,
	})
end

-- Actions -------------------------------------------------------------------------------------

local function pet(player, payload)
	local owner = mustOwner(player, payload.owner)
	if not owner then
		ctx:Fail("Visit another ranch to pet its monsters")
	end
	local m = Monsters:Get(owner, payload.id)
	if not m then
		ctx:Fail("That monster isn't there anymore")
	end
	if m.busy == "expedition" then
		ctx:Fail(Formulas.DisplayName(m) .. " is away on an expedition")
	end
	local s = ctx:Section(player)
	refreshDay(player, s)
	local rules = Config.Social
	if s.petsGiven >= rules.PetsPerDay then
		ctx:Fail(string.format("You've petted %d monsters today. Come back tomorrow!", rules.PetsPerDay))
	end
	local charm = Config.Traits.Product(Formulas.ActiveTraits(m), "petMoodMult")
	Monsters:AddMood(owner, payload.id, rules.PetMood * charm)
	Currency:Add(player, "friendship", rules.FriendshipPerPet, "pet")
	s.petsGiven += 1
	ctx:Dirty(player, "petsGiven")
	ctx.Bus:Publish("PetGiven", player, { owner = owner.UserId })
	ctx.Bus:Publish("PetReceived", owner, { from = player.UserId, id = payload.id })
	return { friendship = Currency:Balance(player, "friendship"), left = rules.PetsPerDay - s.petsGiven }
end

local function like(player, payload)
	local owner = mustOwner(player, payload.owner)
	if not owner then
		ctx:Fail("You can't like your own ranch")
	end
	local s = ctx:Section(player)
	refreshDay(player, s)
	local key = "u" .. tostring(owner.UserId)
	if s.likesGiven[key] then
		ctx:Fail("You already liked this ranch today")
	end
	local given = 0
	for _ in s.likesGiven do
		given += 1
	end
	if given >= Config.Social.LikesPerDay then
		ctx:Fail(string.format("You've used all %d likes today", Config.Social.LikesPerDay))
	end
	s.likesGiven[key] = true
	ctx:Dirty(player, "likesGiven", key)

	local ownerSection = ctx:Section(owner)
	ownerSection.likes = (ownerSection.likes or 0) + 1
	ctx:Dirty(owner, "likes")
	ctx.Bus:Publish("PlotChanged", owner, {})
	ctx.Bus:Publish("RanchLiked", player, { owner = owner.UserId }) -- glow-up Y: Visits pays and crowns
	return { likes = ownerSection.likes }
end

-- Lifecycle -------------------------------------------------------------------------------------

function Social.Init(context)
	ctx = context
	Config = ctx.Config
	Currency = ctx:GetSystem("Currency")
	Monsters = ctx:GetSystem("Monsters")
	-- Fresh module state (tests boot many kernels in one process).
	table.clear(present)
	table.clear(friendCache)
	globalWindow.startedAt, globalWindow.count = 0, 0

	ctx.Net:Handle("Social.Pet", pet)
	ctx.Net:Handle("Social.Like", like)

	ctx.Bus:Subscribe("EggHatched", onHatched)
	ctx.Bus:Subscribe("Bred", onBred)
	ctx.Bus:Subscribe("Mutated", onMutated)
	ctx.Bus:Subscribe("WeatherChanged", onWeather)

	ctx.Services.Messaging.Subscribe(Config.Social.Broadcasts.topic, onRemoteBroadcast)
end

function Social.Start()
	local Ranch = ctx:GetSystem("Ranch")
	if Ranch then
		Ranch:RegisterRateModifier("friends", function(player, _elements)
			return Social:GetFriendBoost(player)
		end)
	end
end

function Social.PlayerAdded(player, _info)
	refreshDay(player, ctx:Section(player))
	present[player] = true
	recomputeBoost(player)
	for other in present do
		if other ~= player and areFriends(player, other) then
			recomputeBoost(other)
		end
	end
end

function Social.PlayerRemoving(player)
	present[player] = nil
	local cache = friendCache[player] or {}
	friendCache[player] = nil
	for other in present do
		if cache[other.UserId] then
			recomputeBoost(other)
		end
	end
end

return Social
