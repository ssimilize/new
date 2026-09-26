--[[
	Postcards (glow-up X): every finished expedition sends a postcard home. Rules in
	Logic/Postcards, the save in Systems/Postcards, the card in UI/Components/PostcardView.

	A postcard is data, never a picture: the region, up to `maxMonsters` squad appearances, a
	line id from the region's pool, a loot summary and the date. The client redraws it: a sky
	gradient, the region's backdrop parts in a ViewportFrame, the squad's real models posed with
	`poses`, the region name on a stamp and the line in a handwritten font.

	Album: the newest `perRegion` postcards of each region stay, favourites (★, at most
	`maxFavourites`) stay for good, and the whole album never holds more than `maxTotal`; the
	oldest non-favourite drops first. Received postcards live in the same album.

	Sending: to a Roblox friend through the Market mailbox, behind the same sender gates as gifts
	(Systems/Gifts: Gifts:Gate), `Send.perDay` a UTC day and `Send.perFriendPerDay` to one friend.

	Scenes (all units in studs, the squad stands on the ground at z = 0 facing the camera at -z):
	  sky = { top, bottom }  ground = colour  stamp = colour  font = handwriting colour
	  props = { { shape = "Block"|"Ball"|"Cylinder", size = { x, y, z }, pos = { x, y, z }, color,
	              rot = { x, y, z }? (degrees), material = Enum.Material name? } }
	Lines: `text` has one %s for a squad member's name. Every text is in Locale es / pt.
]]

local Postcards = {}

Postcards.perRegion = 6 -- non-favourite postcards kept per region
Postcards.maxTotal = 36 -- the whole album, favourites included
Postcards.maxFavourites = 12
Postcards.maxMonsters = 3 -- squad members drawn on one card
Postcards.maxLoot = 6 -- loot lines on the back
Postcards.maxSentPerCard = 10 -- friends one postcard can go to (remembered to refuse a repeat)
Postcards.recvMemory = 60 -- received mail ids remembered, so a repeated delivery adds nothing
Postcards.poses = { "cheer", "sit", "cheer2" } -- by squad position; "idle" where a form lacks it

Postcards.Send = {
	perDay = 5,
	perFriendPerDay = 2,
}

local function prop(shape: string, size, pos, color: string, extra: { [string]: any }?)
	local p = { shape = shape, size = size, pos = pos, color = color }
	for k, v in extra or {} do
		p[k] = v
	end
	return p
end

Postcards.Scenes = {
	meadow = {
		sky = { "#7CC8F7", "#E6F6FF" },
		ground = "#9BD66A",
		stamp = "#3F8A3A",
		props = {
			prop("Ball", { 9, 5, 7 }, { -9, -1, 10 }, "#6DB450"),
			prop("Ball", { 11, 6, 8 }, { 8, -1.5, 12 }, "#5FA646"),
			prop("Cylinder", { 3, 1, 1 }, { -5, 1.5, 5 }, "#7A5A3A", { rot = { 0, 0, 90 } }),
			prop("Ball", { 3.4, 3, 3.4 }, { -5, 4, 5 }, "#4E9E3E"),
			prop("Ball", { 0.8, 0.8, 0.8 }, { 3.5, 0.3, -1.5 }, "#FFE066"),
			prop("Ball", { 0.7, 0.7, 0.7 }, { -3, 0.3, -2 }, "#FF8FB8"),
		},
		lines = {
			{ id = "meadow_rock", text = "%s found a shiny rock!" },
			{ id = "meadow_nap", text = "%s napped in the clover all afternoon." },
			{ id = "meadow_bee", text = "%s made friends with a very fuzzy bee." },
			{ id = "meadow_flower", text = "%s picked you a flower. It's a little squished." },
		},
	},
	coral = {
		sky = { "#43B4E3", "#D9F4FF" },
		ground = "#F4DFA6",
		stamp = "#1F7FA8",
		props = {
			prop("Block", { 40, 0.6, 14 }, { 0, 0.2, 13 }, "#3FA6D6", { material = "Glass" }),
			prop("Cylinder", { 5, 1.2, 1.2 }, { -8, 2.5, 6 }, "#FF7F7F", { rot = { 0, 0, 90 } }),
			prop("Cylinder", { 3.5, 0.9, 0.9 }, { -6.5, 1.8, 6.5 }, "#FFA07A", { rot = { 0, 0, 80 } }),
			prop("Ball", { 1.4, 0.8, 1.4 }, { 4, 0.3, -1.5 }, "#FFF1D6"),
			prop("Ball", { 6, 3, 5 }, { 9, -0.5, 8 }, "#E8CF92"),
		},
		lines = {
			{ id = "coral_shell", text = "%s found a seashell that hums." },
			{ id = "coral_wave", text = "%s tried to catch a wave. The wave won." },
			{ id = "coral_crab", text = "%s had a staring contest with a crab." },
			{ id = "coral_sand", text = "%s built a sandcastle and guarded it all day." },
		},
	},
	ember = {
		sky = { "#E9744A", "#FFD2A8" },
		ground = "#7E5240",
		stamp = "#B8452A",
		props = {
			prop("Cylinder", { 10, 6, 6 }, { 7, 3, 14 }, "#5A3A2E", { rot = { 0, 0, 90 } }),
			prop("Ball", { 3, 1.2, 3 }, { 7, 8, 14 }, "#FF8A3D", { material = "Neon" }),
			prop("Block", { 2, 3, 2 }, { -7, 1.5, 5 }, "#4A3128", { rot = { 0, 20, 8 } }),
			prop("Ball", { 1, 0.6, 1 }, { -2.5, 0.2, -2 }, "#FF6A2A", { material = "Neon" }),
		},
		lines = {
			{ id = "ember_toast", text = "%s toasted a marshmallow on a lava vent." },
			{ id = "ember_warm", text = "%s says it's warm here. Very warm." },
			{ id = "ember_stone", text = "%s brought back a stone that's still glowing." },
			{ id = "ember_brave", text = "%s was brave near the big volcano!" },
		},
	},
	gloom = {
		sky = { "#2B2150", "#6F5A9E" },
		ground = "#4D4466",
		stamp = "#5B3F9A",
		props = {
			prop("Ball", { 2.5, 2.5, 2.5 }, { 6, 9, 16 }, "#F4F0FF", { material = "Neon" }),
			prop("Cylinder", { 0.6, 1.8, 1.8 }, { -6, 2.5, 5 }, "#B98CFF", { rot = { 0, 0, 0 }, material = "Neon" }),
			prop("Cylinder", { 2.5, 0.5, 0.5 }, { -6, 1.2, 5 }, "#D8D0E8", { rot = { 0, 0, 90 } }),
			prop("Block", { 3, 7, 2 }, { -10, 3.5, 10 }, "#3A3150", { rot = { 0, 10, 6 } }),
			prop("Ball", { 0.5, 0.5, 0.5 }, { 3, 2, -1 }, "#B8FFB0", { material = "Neon" }),
		},
		lines = {
			{ id = "gloom_glow", text = "%s followed a firefly and came back glowing." },
			{ id = "gloom_scared", text = "%s was only a tiny bit scared." },
			{ id = "gloom_mushroom", text = "%s found a mushroom that giggles." },
			{ id = "gloom_moon", text = "%s howled at the moon. The moon was polite about it." },
		},
	},
	sky = {
		sky = { "#8FCBFF", "#FFFFFF" },
		ground = "#F4F7FF",
		stamp = "#4F8FD8",
		props = {
			prop("Ball", { 8, 3, 5 }, { -8, 6, 14 }, "#FFFFFF"),
			prop("Ball", { 6, 2.5, 4 }, { 9, 8, 16 }, "#FFFFFF"),
			prop("Ball", { 4, 1.6, 3 }, { 3, 3, 9 }, "#F2F7FF"),
			prop("Block", { 0.4, 3, 0.4 }, { -5, 1.5, 3 }, "#C9A36A"),
			prop("Block", { 2.4, 1.2, 0.2 }, { -5, 3, 3 }, "#FF6F8F", { rot = { 0, 0, 8 } }),
		},
		lines = {
			{ id = "sky_cloud", text = "%s bounced on a cloud. Twice!" },
			{ id = "sky_view", text = "%s says you can see the whole ranch from up here." },
			{ id = "sky_bird", text = "%s raced a bird and almost won." },
			{ id = "sky_wind", text = "%s's ears are still flapping from the wind." },
		},
	},
	dunes = {
		sky = { "#FFB86B", "#FFF0CF" },
		ground = "#E8C27A",
		stamp = "#C47A2C",
		props = {
			prop("Ball", { 16, 5, 8 }, { -9, -1.5, 12 }, "#E2B566"),
			prop("Ball", { 14, 4, 7 }, { 10, -1.2, 14 }, "#D9A857"),
			prop("Cylinder", { 3.5, 1, 1 }, { 6, 1.75, 4 }, "#5E9E4A", { rot = { 0, 0, 90 } }),
			prop("Cylinder", { 1.4, 0.6, 0.6 }, { 6.6, 2.4, 4 }, "#5E9E4A"),
			prop("Ball", { 3, 3, 3 }, { -2, 11, 18 }, "#FFF3B0", { material = "Neon" }),
		},
		lines = {
			{ id = "dunes_sand", text = "%s has sand in places sand shouldn't be." },
			{ id = "dunes_cactus", text = "%s hugged a cactus. Don't worry, it's fine." },
			{ id = "dunes_mirage", text = "%s saw a mirage of a giant snack." },
			{ id = "dunes_ruin", text = "%s found old ruins and a very old coin!" },
		},
	},
	glacier = {
		sky = { "#A8D8FF", "#F4FBFF" },
		ground = "#EAF6FF",
		stamp = "#3E8CC4",
		props = {
			prop("Block", { 5, 9, 4 }, { -9, 4, 12 }, "#BFE4FF", { rot = { 0, 20, 6 }, material = "Glass" }),
			prop("Block", { 4, 6, 3 }, { 8, 3, 10 }, "#D6EEFF", { rot = { 0, -15, -4 }, material = "Glass" }),
			prop("Ball", { 2.2, 2.2, 2.2 }, { -5, 1.1, 4 }, "#FFFFFF"),
			prop("Ball", { 1.5, 1.5, 1.5 }, { -5, 2.9, 4 }, "#FFFFFF"),
			prop("Ball", { 0.6, 0.6, 0.6 }, { 4, 1.5, -2 }, "#FFFFFF"),
		},
		lines = {
			{ id = "glacier_snow", text = "%s built a snow monster. It looks just like them!" },
			{ id = "glacier_slide", text = "%s slid down the glacier on their belly." },
			{ id = "glacier_cold", text = "%s says hi! (Their nose is very cold.)" },
			{ id = "glacier_ice", text = "%s found a crystal of ice that never melts." },
		},
	},
}

-- Regions added later without a scene of their own.
Postcards.DefaultScene = {
	sky = { "#86CEFF", "#F2FAFF" },
	ground = "#A6DD73",
	stamp = "#6B5F48",
	props = {
		prop("Ball", { 10, 5, 7 }, { -9, -1, 11 }, "#7FBF5E"),
		prop("Ball", { 9, 4, 6 }, { 9, -1, 12 }, "#6FAF52"),
	},
	lines = {
		{ id = "any_adventure", text = "%s had a big adventure!" },
		{ id = "any_miss", text = "%s misses the ranch. And you!" },
		{ id = "any_snack", text = "%s found a snack and saved you half." },
	},
}

-- Every line id -> its text, for cards whose region's pool changed after they were written.
Postcards.LineById = {}
for _, scene in Postcards.Scenes do
	for _, line in scene.lines do
		Postcards.LineById[line.id] = line.text
	end
end
for _, line in Postcards.DefaultScene.lines do
	Postcards.LineById[line.id] = line.text
end

function Postcards.Scene(regionId: string?)
	return Postcards.Scenes[regionId or ""] or Postcards.DefaultScene
end

return Postcards
