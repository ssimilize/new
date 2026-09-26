--[[
	World/SceneryMeshes: the mesh and colour texture of every scenery kind (Config.World.Scenery
	kinds, plus "wall" and "pillar" for the perimeter), used by World/Scenery. All were made with
	Roblox's mesh generator (Studio MCP generate_mesh, 2026-09-25), which publishes each result
	as an asset; the prompt that made each is kept beside it so a kind can be regenerated.
	A kind missing here, or whose mesh fails to load, is simply left off the map.
]]

return {
	-- "cute stylized cartoon oak tree with a round fluffy green canopy and a short brown trunk, low poly toon style"
	oak = { mesh = "rbxassetid://104746270320846", texture = "rbxassetid://136153453739671" },
	-- (same prompt, a paler second take)
	oakLight = { mesh = "rbxassetid://86501059931676", texture = "rbxassetid://94883733237607" },
	-- "cute stylized cartoon pine tree, layered rounded dark green cone canopy, short brown trunk, toon style"
	pine = { mesh = "rbxassetid://86490643433449", texture = "rbxassetid://105520656337385" },
	-- "cute stylized cartoon cherry blossom tree with a round fluffy pink canopy and a short brown trunk, toon style"
	blossom = { mesh = "rbxassetid://138832521426916", texture = "rbxassetid://111155514187382" },
	-- "big smooth rounded grey boulder with patches of green moss on top, cute stylized cartoon toon style"
	boulder = { mesh = "rbxassetid://136319653339155", texture = "rbxassetid://132657263653090" },
	-- "small low pile of three rounded grey rocks with a little green moss, flat on the ground, ..." (came out a cairn)
	stones = { mesh = "rbxassetid://112583939274868", texture = "rbxassetid://125875826261553" },
	-- "low wide round leafy green shrub sitting directly on the ground, no trunk, a few small red berries, ..."
	bush = { mesh = "rbxassetid://99728005148454", texture = "rbxassetid://114886186339068" },
	-- "fallen wooden log lying on its side with a little moss, cute stylized cartoon toon style"
	log = { mesh = "rbxassetid://74749973514597", texture = "rbxassetid://136413568528783" },
	-- "cluster of three cute red mushrooms with white spots, cute stylized cartoon toon style"
	mushrooms = { mesh = "rbxassetid://72978298150174", texture = "rbxassetid://101011124903124" },
	-- "small patch of colorful wildflowers, pink yellow and white flowers with green leaves, cute stylized cartoon toon style"
	flowers = { mesh = "rbxassetid://128599741068410", texture = "rbxassetid://71724855084707" },
	-- "tuft of tall bright green grass blades, cute stylized cartoon toon style"
	grass = { mesh = "rbxassetid://95813836523002", texture = "rbxassetid://103609753768172" },
	-- "straight section of a cozy fieldstone wall made of rounded stacked grey stones with a flat top, ..."
	wall = { mesh = "rbxassetid://85696254066463", texture = "rbxassetid://122500252989985" },
	-- "square stone pillar made of stacked grey stones with a wooden cap on top, cute stylized cartoon toon style"
	pillar = { mesh = "rbxassetid://124106633912195", texture = "rbxassetid://119759638390770" },
}
