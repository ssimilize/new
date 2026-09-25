--[[
	Workshop (update 3.0 · Year Two): accessories designed by players. A design is a catalogue
	shape (Config.Accessories shapes, which decide its slot) with two colours from `Palette`
	and a name that passes the text filter, never free-form art, so everything in the
	gallery is safe to show.

	Publishing costs `SubmitCost` (at most `PerWeek` designs a week) and gives the designer
	one copy. Anyone can buy copies for `CopyPrice`; the designer earns `Royalty` Contest
	Ribbons per copy bought by someone else, collected from the Workshop (Workshop.Claim).
	Likes rank the gallery's Top tab. `ReportsToHide` reports hide a design from the gallery
	until moderators look at it (copies already bought still work).

	Designs live in a cross-server store (Services.Designs). A worn copy is encoded into the
	monster's `acc` (Config.Accessories.Encode) so it draws everywhere.
]]

local Workshop = {}

Workshop.Unlock = "workshop"
Workshop.SubmitCost = { ribbons = 40 }
Workshop.CopyPrice = { ribbons = 15 }
Workshop.Royalty = 5
Workshop.PerWeek = 3
Workshop.MaxCopies = 10 -- per design per player (storage)
Workshop.NameMin = 3
Workshop.NameMax = 20
Workshop.ReportsToHide = 3
Workshop.GallerySize = 24
Workshop.MaxDesignsKept = 50 -- design ids remembered per designer
Workshop.MaxLiked = 500
Workshop.CacheSeconds = 60 -- design records cached per server (3.0.1, DataStore budget)
Workshop.ListCacheSeconds = 30 -- Top / New id lists
-- Moderators (3.0.1) review designs hidden by reports: listed user ids, or anyone with at least
-- `minRank` in the group (id 0 = no group).
Workshop.Moderators = {} :: { number }
Workshop.ModeratorGroup = { id = 0, minRank = 200 }

Workshop.Palette = {
	"#FFFFFF",
	"#2B2B2B",
	"#E5484D",
	"#FF8A3D",
	"#F5C630",
	"#79C455",
	"#2BA89A",
	"#4FB6F2",
	"#3D5BD9",
	"#8B6AD8",
	"#FF7AC8",
	"#C98B4E",
	"#B9C3CC",
	"#FFD447",
	"#7CC7FF",
	"#3A2D55",
}

return Workshop
