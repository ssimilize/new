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

	-- Ranch life (2026-09-26): made with GenerationService:GenerateModelAsync (tools/rbxgen,
	-- batches/scenery1.json) and published from Studio. Every prompt ends ", cute stylized cartoon
	-- toon style". A pond from the same batch was left out: its sides stood like a cake.
	-- "a stack of three rectangular golden hay bales tied with twine"
	hayStack = { mesh = "rbxassetid://84722119704977", texture = "rbxassetid://137769960058944" },
	-- "a small patch of three round orange pumpkins with curly green vines and leaves, flat on the ground"
	pumpkins = { mesh = "rbxassetid://127104591402007", texture = "rbxassetid://81662922981376" },
	-- "a friendly scarecrow on a wooden post with a straw hat, a patched shirt and straw hands"
	scarecrow = { mesh = "rbxassetid://98776098387738", texture = "rbxassetid://82535684095517" },
	-- "an old round stone water well with a small wooden roof and a bucket hanging on a rope"
	well = { mesh = "rbxassetid://125130384778844", texture = "rbxassetid://104555735533825" },
	-- "a small wooden farm windmill with four white sails on a round stone base"
	windmill = { mesh = "rbxassetid://84065384796249", texture = "rbxassetid://135770100985708" },
	-- "a campfire ring of grey stones with crossed logs and small orange flames"
	campfire = { mesh = "rbxassetid://73862654074319", texture = "rbxassetid://121425205492474" },
	-- "a cut tree stump with visible rings on top and a few small roots, a little moss"
	stump = { mesh = "rbxassetid://139704347083662", texture = "rbxassetid://99590366476015" },
	-- "a neat stack of chopped firewood logs"
	firewood = { mesh = "rbxassetid://90809080432924", texture = "rbxassetid://106256237266060" },
	-- "a cluster of three tall sunflowers with big yellow petals, brown centres and green leaves"
	sunflowers = { mesh = "rbxassetid://97328242059091", texture = "rbxassetid://87427269913856" },
	-- "a round straw skep beehive sitting on a small wooden stool" (came out a honey pot)
	honeypot = { mesh = "rbxassetid://118118749691111", texture = "rbxassetid://90850065479528" },
	-- "a wooden park bench with a backrest"
	bench = { mesh = "rbxassetid://126370859712250", texture = "rbxassetid://80372980224481" },
	-- "a wooden farm wagon with four wooden wheels loaded with hay"
	wagon = { mesh = "rbxassetid://72441300473950", texture = "rbxassetid://98856173009985" },
	-- "a giant red toadstool mushroom with white spots and a thick white stem"
	toadstool = { mesh = "rbxassetid://98253950987332", texture = "rbxassetid://76156801352481" },
	-- "a cluster of glowing purple and light blue crystals growing out of a small grey rock"
	crystals = { mesh = "rbxassetid://132039510141445", texture = "rbxassetid://120823098658031" },
	-- "a small wooden birdhouse with a red roof on top of a tall wooden pole"
	birdhouse = { mesh = "rbxassetid://74006963536974", texture = "rbxassetid://126085232313263" },
}
