--[[
	BattleStage (glow-up V): tuning and themes for fights drawn in 3D (UI/Screens/Parts/BattleStage,
	Visuals/BattleArena). Required directly (like Config/Vfx and Config/Cinematics), not listed in
	Config/init. The maths that reads it is Logic/BattleStage (unit-tested in BattleStage.spec).

	origin      where the stage stands: far outside the map, so the ranch never shows behind it.
	floor       the stage disc: radius, thickness; `wall` a ring of backdrop panels around it.
	lights      PointLights above the stage so the fight reads at night (none on Low).
	layout      studs in stage space: allies stand at x < 0 facing +x, enemies at x > 0. `front` is
	            each front row's distance from the centre line, `spacing` between neighbours in a
	            row, `rowDepth` between a front and a back row, `perRow` monsters before a second
	            row starts, `bossBack` how far a boss stands behind its front line.
	scale       every fighter is drawn at one battle size (MonsterModel.ScaleFor is clamped to
	            `min` .. `max` of it, so babies and heavy adults still differ a little); a boss
	            `boss` times bigger.
	pace        seconds between events: `budget` / events, clamped to `min` .. `max` (the 2D
	            viewer's pace), `extra` after crits, specials and KOs, `lead` before the first
	            event, `tail` before the result; `bolt` the longest flight of a projectile.
	caps        live objects and new ones per second, by quality (`low` on Quality Low): bolts,
	            floating numbers and hit sparks. A capped bolt or spark is simply not drawn (the
	            hit still lands); a number over the cap recycles the oldest one when it matters
	            (crits, KOs, specials), else it is dropped. The HP bars always update.
	camera      shots in stage space: `wide` (both teams), `shoulder` (behind the attacker, on
	            big hits), `close` (the finishing blow's target). `minCut` seconds between cuts,
	            `hold` seconds a shoulder / close shot is held before the wide comes back,
	            `bigHit` a hit taking this fraction of the target's max HP is big. `glide`
	            seconds per camera move (reduced motion cuts).
	fallback    when the 2D viewer draws the fight instead: Quality Low with more than
	            `lowMaxUnits` fighters, or a median frame slower than `maxFrameMs`.
	sprites     each element's projectile sprite (Config/VfxSprites names; a missing one is a
	            round blob in the element's colour).
	themes      one per region (Config.Regions ids) plus `arena`, `raid` and `default`: floor /
	            rim / wall colours and materials and a few props. Every prop has `mesh` ("" = the
	            parts shown here; an uploaded mesh id replaces the main part's shape later).
	            Prop kinds: rock, tree, crystal, pillar, coral, cactus, spike, mushroom, torch, banner.
	            `at` = { degrees around the stage (0 = behind the enemies), distance from the centre }.
]]

local function prop(kind: string, angle: number, distance: number, size: number, color: string, extra: { [string]: any }?)
	local p = { kind = kind, at = { angle, distance }, size = size, color = color, mesh = "" }
	for k, v in extra or {} do
		p[k] = v
	end
	return p
end

return {
	origin = { 6000, 420, 6000 },

	floor = { radius = 24, thickness = 2, rim = 1.2 },
	wall = { radius = 36, height = 26, panels = 12, width = 20 },
	lights = { brightness = 1.6, range = 60, height = 22 },

	layout = { front = 6, spacing = 4.4, rowDepth = 4, perRow = 4, bossBack = 3 },
	scale = { unit = 1.15, min = 0.85, max = 1.2, boss = 1.9 },

	pace = { budget = 22, min = 0.14, max = 0.55, extra = 0.2, lead = 0.6, tail = 0.5, bolt = 0.3 },

	caps = {
		bolts = { live = 4, perSecond = 6 },
		numbers = { live = 6, perSecond = 8 },
		sparks = { live = 4, perSecond = 4 },
		low = {
			bolts = { live = 2, perSecond = 3 },
			numbers = { live = 3, perSecond = 4 },
			sparks = { live = 0, perSecond = 0 },
		},
	},

	camera = {
		wide = { distance = 34, height = 13, look = 2.5 },
		shoulder = { back = 7, side = 3.2, height = 5, look = 2.5 },
		close = { distance = 9, height = 3, look = 2 },
		minCut = 2.4,
		hold = 1.3,
		bigHit = 0.3,
		glide = 0.35,
	},

	fallback = { lowMaxUnits = 6, maxFrameMs = 45 },

	sprites = {
		ember = "flame",
		tide = "droplet",
		sprout = "leaf",
		spark = "bolt",
		gloom = "wisp",
		stone = "pebble",
		light = "star",
		void = "voidswirl",
	},

	themes = {
		default = {
			floor = "#7FB069",
			floorMaterial = "Grass",
			rim = "#8C6D4F",
			wall = "#BFE3F2",
			props = {
				prop("rock", 40, 28, 3, "#9A9A9A"),
				prop("tree", -40, 29, 7, "#4F9A45"),
			},
		},
		meadow = {
			floor = "#86C06C",
			floorMaterial = "Grass",
			rim = "#9B7A55",
			wall = "#CDEBF7",
			props = {
				prop("tree", 35, 29, 8, "#4E9E47"),
				prop("tree", -50, 30, 7, "#5BAE4F"),
				prop("rock", 150, 27, 2.5, "#A3A3A3"),
				prop("mushroom", -140, 26, 2.5, "#E86A5C"),
			},
		},
		coral = {
			floor = "#E8D7A8",
			floorMaterial = "Sand",
			rim = "#5FA8C9",
			wall = "#8FD3EE",
			props = {
				prop("coral", 30, 28, 5, "#F07E8E"),
				prop("coral", -45, 29, 4, "#FFA86B"),
				prop("rock", 145, 27, 3, "#7F99A8"),
				prop("coral", -150, 27, 3.5, "#B77CE0"),
			},
		},
		ember = {
			floor = "#5B4A45",
			floorMaterial = "Basalt",
			rim = "#D9602F",
			wall = "#F2B27A",
			props = {
				prop("spike", 35, 29, 7, "#4A3B37"),
				prop("torch", -30, 25, 5, "#FF9A3D"),
				prop("torch", 150, 25, 5, "#FF9A3D"),
				prop("rock", -140, 27, 3, "#6B534B"),
			},
		},
		gloom = {
			floor = "#4D4466",
			floorMaterial = "Slate",
			rim = "#8C6BC7",
			wall = "#5D5580",
			props = {
				prop("mushroom", 30, 28, 4, "#A782E8"),
				prop("crystal", -40, 29, 6, "#C9A8FF"),
				prop("tree", 150, 30, 7, "#3D3552"),
				prop("mushroom", -150, 26, 3, "#5CE1E6"),
			},
		},
		sky = {
			floor = "#F3F0E6",
			floorMaterial = "Marble",
			rim = "#F2C94C",
			wall = "#D6EEFF",
			props = {
				prop("pillar", 30, 28, 9, "#FFFFFF"),
				prop("pillar", -30, 28, 9, "#FFFFFF"),
				prop("crystal", 150, 27, 5, "#FFF6D6"),
				prop("crystal", -150, 27, 5, "#DAD5F2"),
			},
		},
		dunes = {
			floor = "#E3C48A",
			floorMaterial = "Sand",
			rim = "#B98A52",
			wall = "#F7D9A3",
			props = {
				prop("cactus", 35, 29, 6, "#5E9E4A"),
				prop("rock", -40, 28, 4, "#C8955A"),
				prop("pillar", 150, 28, 7, "#D8B27A"),
				prop("cactus", -145, 27, 4, "#6DAE56"),
			},
		},
		glacier = {
			floor = "#E6F3FA",
			floorMaterial = "Snow",
			rim = "#8CC8E8",
			wall = "#CFE9F7",
			props = {
				prop("spike", 30, 29, 7, "#BFE6FA", { material = "Ice" }),
				prop("spike", -40, 29, 5, "#D8F0FF", { material = "Ice" }),
				prop("rock", 150, 27, 3, "#9FB8C7"),
				prop("crystal", -150, 27, 4, "#9FD7FF"),
			},
		},
		arena = {
			floor = "#C9B48E",
			floorMaterial = "Sandstone",
			rim = "#8E5A3C",
			wall = "#E9C98F",
			props = {
				prop("banner", 30, 28, 8, "#D9483B"),
				prop("banner", -30, 28, 8, "#3B6FD9"),
				prop("torch", 150, 25, 5, "#FF9A3D"),
				prop("torch", -150, 25, 5, "#FF9A3D"),
			},
		},
		raid = {
			floor = "#5E5A6E",
			floorMaterial = "Cobblestone",
			rim = "#C9A8FF",
			wall = "#6E6887",
			props = {
				prop("pillar", 25, 30, 10, "#8A849E"),
				prop("pillar", -25, 30, 10, "#8A849E"),
				prop("crystal", 150, 27, 6, "#5CE1E6"),
				prop("torch", -150, 25, 5, "#C9A8FF"),
			},
		},
	},
}
