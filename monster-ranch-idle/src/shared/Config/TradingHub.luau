--[[
	Trading Hub (update 3.0 · Year Two): a second place in the same Roblox universe where
	traders from every server meet. Profiles are shared across the universe, so your
	monsters come with you; trades themselves still run through the Trade system between two
	players on the same hub server.

	The Trade Board lists ads from every hub server (Services.HubBoard, a MemoryStore sorted
	map): what someone offers (up to MaxOffer monsters or eggs), what they want (tags from
	`Wants`) and a preset note (`Notes`, never free text). "Meet" sends a trade request when
	the poster is on your hub server, or teleports you to theirs.

	PlaceIds: fill in the real place ids when publishing (0 = not published yet; Travel and
	Return then refuse). A server runs in hub mode when its PlaceId is PlaceIds.Hub, or when
	Workspace has the attribute PlaceMode = "hub" (Studio testing).
]]

local TradingHub = {}

TradingHub.Unlock = "trading"
TradingHub.PlaceIds = { Main = 0, Hub = 0 } -- VERIFY: set when the places are published
TradingHub.AdSeconds = 30 * 60 -- an ad lives this long unless its poster leaves or trades
TradingHub.PostCooldown = 30
TradingHub.MaxOffer = 4
TradingHub.MaxWants = 3
TradingHub.BoardSize = 40 -- ads read per refresh (newest first)
TradingHub.RefreshSeconds = 15

-- What an ad can ask for. `rarity` = at least that rarity; `element` = has that element.
TradingHub.Wants = {
	{ id = "offers", name = "Any offers" },
	{ id = "legendary", name = "Legendary+", rarity = 5 },
	{ id = "mythic", name = "Mythic", rarity = 6 },
	{ id = "variant", name = "Shiny / Rainbow" },
	{ id = "mutated", name = "Mutated" },
	{ id = "huge", name = "Huge" },
	{ id = "hybrid", name = "Hybrids" },
	{ id = "eggs", name = "Eggs" },
	{ id = "light", name = "Light", element = "light" },
	{ id = "void", name = "Void", element = "void" },
}

TradingHub.Notes = {
	"Open to offers!",
	"Fair trades only",
	"Collecting for my Codex",
	"Will add extra for Mythics",
	"Quick trades please",
	"Looking for hybrids",
	"Trading duplicates",
	"Come find me at a booth!",
}

-- The hub place's own layout (World/Build builds it instead of the ranch map).
TradingHub.World = {
	plazaRadius = 110,
	spawn = { 0, 3, 40 },
	buildings = {
		{
			id = "tradeBoard",
			name = "Trade Board",
			position = { 0, 0, -64 },
			size = { 26, 14, 8 },
			color = "#4FB6F2",
			screen = "TradingHub",
		},
		{ id = "trading", name = "Trading Plaza", position = { -64, 0, 0 }, size = { 20, 14, 26 }, color = "#4FB6F2", screen = "Trade" },
		{ id = "market", name = "Market", position = { 64, 0, 0 }, size = { 20, 12, 22 }, color = "#F2A93B", screen = "Market" },
		{
			id = "returnPortal",
			name = "Back to Ranch",
			position = { 0, 0, 72 },
			size = { 16, 18, 10 },
			color = "#43B649",
			screen = "TradingHub",
		},
	},
	booths = { radius = 40, count = 8, size = { 10, 8, 8 }, colors = { "#EF6FA8", "#F2A93B", "#43B649", "#8B6AD8" } },
}

TradingHub.WantsById = {}
for _, w in TradingHub.Wants do
	TradingHub.WantsById[w.id] = w
end

-- "hub" on the Trading Hub place (or with the Studio override), otherwise "main".
function TradingHub.Mode(placeId: number?, override: string?): string
	if override == "hub" then
		return "hub"
	end
	if TradingHub.PlaceIds.Hub ~= 0 and placeId == TradingHub.PlaceIds.Hub then
		return "hub"
	end
	return "main"
end

return TradingHub
