--[[
	Generates models with Roblox's own 3D generator (GenerationService:GenerateModelAsync, the Cube
	model), from Studio in Edit, through the Studio MCP's execute_luau, and posts each result's mesh
	and texture to receiver.py so assemble.py can turn it into a GLB for the Blender tools.
	Run it with its arguments set in front of this file's text:
		_G.RbxGenArgs = {
			post = "http://127.0.0.1:38519/",
			jobs = {
				{ key = "jellow", image = 73296225544466, prompt = "a cute baby jelly blob creature" },
				{ key = "haybale", prompt = "a stylized cartoon hay bale", size = { 4, 3, 3 }, maxTriangles = 4000 },
				{ key = "stall", image = 99059759260142, parts = { "walls", "roof", "awning" } },
			},
		}
	A job needs an image (an Image asset id: upload the concept with the MCP's upload_image) or a
	prompt, or both: an image steers the shape and colours, a prompt on top steers details (a fox
	image came out stubby-legged; the same image with "four long slender legs" did not). size is
	the approximate box {x, y, z}; maxTriangles is at most 20000 (the API refuses more); parts names
	up to 8 groups, each its own MeshPart with its own 1024 px texture (the triangles are shared).
	publish = true also publishes every part's mesh and texture as assets, as generated (a prop for
	World/SceneryMeshes.luau needs nothing more); a model whose texture colormatch.py will change
	needs only its mesh published here, and the corrected PNG uploaded with upload_image. To publish
	only the keepers after looking at the review sheet, leave publish off and call
	_G.RbxGenPublish(post, { key, ... }) later in the same Studio session.
	The same inputs give (nearly) the same model: a re-run of the jelly blob matched exactly, one of
	the fox differed by 1% of its triangles and looked the same. To get another take, change the
	prompt or the image. A prompt can fail "Moderation failed" for nothing (an oak tree "with a
	thick trunk"); reword it.
	It returns JSON: { done, jobs = { key = { state, secs, parts, error } } }. All jobs run at once
	(8 in parallel took 21-45 s each on 2026-09-25; no rate limit was hit). A call waits at most 55 s;
	if something was still running, `return _G.RbxGenStatus()` in a later call reports it. Results
	also stay in Workspace.RbxGen to look at: delete that folder before saving the place.
	Findings and the rest of the road: tools/rbxgen/README.md.
]]

local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")
local GenerationService = game:GetService("GenerationService")
local HttpService = game:GetService("HttpService")

local CHUNK = 900000 -- characters per post: a 1024 px texture is ~5.6 MB of base64

local function post(url: string, key: string, part: string, kind: string, data: string)
	local n = math.ceil(#data / CHUNK)
	for i = 1, n do
		HttpService:PostAsync(
			url,
			HttpService:JSONEncode({
				gen = key,
				part = part,
				kind = kind,
				i = i,
				n = n,
				data = string.sub(data, (i - 1) * CHUNK + 1, i * CHUNK),
			})
		)
	end
end

local function round(x: number): number
	return math.floor(x * 10000 + 0.5) / 10000
end

-- One MeshPart's mesh (positions, UVs and normals, each indexed per face corner, as EditableMesh
-- keeps them) and its texture (raw RGBA, base64). The generated content is opaque, not an asset:
-- it can be read but lives only as long as the instance.
local function send(url: string, key: string, model: Model, p: MeshPart): string
	local em = AssetService:CreateEditableMeshAsync(p.MeshContent, { FixedSize = false })
	local vid, pos, uvid, uvs, nid, nrm = {}, {}, {}, {}, {}, {}
	for i, v in em:GetVertices() do
		vid[v] = i - 1
		local q = em:GetPosition(v)
		table.insert(pos, round(q.X))
		table.insert(pos, round(q.Y))
		table.insert(pos, round(q.Z))
	end
	for i, u in em:GetUVs() do
		uvid[u] = i - 1
		local q = em:GetUV(u)
		table.insert(uvs, round(q.X))
		table.insert(uvs, round(q.Y))
	end
	for i, u in em:GetNormals() do
		nid[u] = i - 1
		local q = em:GetNormal(u)
		table.insert(nrm, round(q.X))
		table.insert(nrm, round(q.Y))
		table.insert(nrm, round(q.Z))
	end
	local faces, faceUVs, faceNormals = {}, {}, {}
	for _, f in em:GetFaces() do
		for _, v in em:GetFaceVertices(f) do
			table.insert(faces, vid[v])
		end
		for _, u in em:GetFaceUVs(f) do
			table.insert(faceUVs, uvid[u])
		end
		for _, u in em:GetFaceNormals(f) do
			table.insert(faceNormals, nid[u])
		end
	end
	em:Destroy()
	local rel = model:GetPivot():ToObjectSpace(p.CFrame)
	post(
		url,
		key,
		p.Name,
		"mesh",
		HttpService:JSONEncode({
			name = p.Name,
			size = { p.Size.X, p.Size.Y, p.Size.Z },
			cframe = { rel:GetComponents() },
			positions = pos,
			uvs = uvs,
			normals = nrm,
			faces = faces,
			faceUVs = faceUVs,
			faceNormals = faceNormals,
		})
	)
	local tex = "no texture"
	if p.TextureContent.SourceType ~= Enum.ContentSourceType.None then
		local img = AssetService:CreateEditableImageAsync(p.TextureContent)
		local pixels = img:ReadPixelsBuffer(Vector2.zero, img.Size)
		post(url, key, p.Name, `tex{img.Size.X}x{img.Size.Y}`, buffer.tostring(EncodingService:Base64Encode(pixels)))
		tex = `{img.Size.X}px`
		img:Destroy()
	end
	return `{p.Name} {#faces // 3} tris {tex}`
end

-- Publishes a part's mesh and texture as the user's assets, as they came from the generator: the
-- ids go in a data module (World/SceneryMeshes.luau takes { mesh, texture }) and load with
-- CreateMeshPartAsync. A fresh texture can render blank for a few seconds while it streams in.
local function publish(key: string, p: MeshPart): { mesh: string, texture: string? }
	local name = `{key} {p.Name} (Monster Ranch Idle)`
	local em = AssetService:CreateEditableMeshAsync(p.MeshContent, { FixedSize = false })
	local status, meshId = AssetService:CreateAssetAsync(
		em,
		Enum.AssetType.Mesh,
		{ Name = name, Description = "Monster Ranch Idle: made with Roblox's generator (tools/rbxgen)" }
	)
	em:Destroy()
	assert(status == Enum.CreateAssetResult.Success, `mesh publish: {status}`)
	local ids = { mesh = `rbxassetid://{meshId}` }
	if p.TextureContent.SourceType ~= Enum.ContentSourceType.None then
		local img = AssetService:CreateEditableImageAsync(p.TextureContent)
		local status2, imageId = AssetService:CreateAssetAsync(
			img,
			Enum.AssetType.Image,
			{ Name = name, Description = "Monster Ranch Idle: made with Roblox's generator (tools/rbxgen)" }
		)
		img:Destroy()
		assert(status2 == Enum.CreateAssetResult.Success, `texture publish: {status2}`)
		ids.texture = `rbxassetid://{imageId}`
	end
	return ids
end

-- Publishes every part of a model, one publish at a time across all jobs (11 publishes at once
-- failed "Too Many Requests" for a peer session, 2026-09-25; waves of 3 all passed), and posts
-- the ids so assemble.py records them.
local function publishModel(url: string, key: string, model: Model, state)
	state.published = state.published or {}
	for _, p in model:GetDescendants() do
		if p:IsA("MeshPart") then
			while _G.RbxGen.publishing do
				task.wait(0.2)
			end
			_G.RbxGen.publishing = true
			local ok, ids = pcall(publish, key, p)
			_G.RbxGen.publishing = false
			assert(ok, ids)
			state.published[p.Name] = ids
			post(url, key, p.Name, "ids", HttpService:JSONEncode(ids))
		end
	end
end

local function run(url: string, job, folder: Folder, slot: number)
	local state = _G.RbxGen.jobs[job.key]
	local ok, err = pcall(function()
		local inputs = { MaxTriangles = job.maxTriangles or 20000, GenerateTextures = job.textures ~= false }
		if job.image then
			inputs.Image = Content.fromAssetId(job.image)
		end
		if job.prompt then
			inputs.TextPrompt = job.prompt
		end
		if job.size then
			inputs.Size = Vector3.new(job.size[1], job.size[2], job.size[3])
		end
		local schema = if job.parts then { SchemaDefinition = { Groups = job.parts } } else { PredefinedSchema = "Body1" }
		local model = GenerationService:GenerateModelAsync(inputs, schema)
		state.secs = os.clock() - state.started
		model.Name = job.key
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		-- In a row along +X, 30 studs apart, standing on the ground: to look at from Studio.
		local cf, size = model:GetBoundingBox()
		model:PivotTo(model:GetPivot() + (Vector3.new(slot * 30, size.Y / 2, 600) - cf.Position))
		model.Parent = folder
		state.parts = {}
		for _, p in model:GetDescendants() do
			if p:IsA("MeshPart") then
				table.insert(state.parts, send(url, job.key, model, p))
			end
		end
		if job.publish then
			publishModel(url, job.key, model, state)
		end
	end)
	state.state = if ok then "done" else "failed"
	state.error = if ok then nil else tostring(err)
	state.secs = state.secs or (os.clock() - state.started)
end

-- The last run's jobs only (every job this Studio session ran stays in _G.RbxGen.jobs).
_G.RbxGenStatus = function(): string
	local done, jobs = true, {}
	for _, key in _G.RbxGen.last do
		jobs[key] = _G.RbxGen.jobs[key]
		done = done and jobs[key].state ~= "running"
	end
	return HttpService:JSONEncode({ done = done, jobs = jobs })
end

_G.RbxGenRun = function(args): string
	local folder = workspace:FindFirstChild("RbxGen") or Instance.new("Folder")
	folder.Name = "RbxGen"
	folder.Parent = workspace
	_G.RbxGen = _G.RbxGen or { jobs = {} }
	_G.RbxGen.last = {}
	for i, job in args.jobs do
		assert(job.key and (job.image or job.prompt), "a job needs a key and an image or a prompt")
		_G.RbxGen.jobs[job.key] = { state = "running", started = os.clock() }
		table.insert(_G.RbxGen.last, job.key)
		task.spawn(run, args.post, job, folder, #folder:GetChildren() + i)
	end
	local deadline = os.clock() + 55
	repeat
		task.wait(1)
		local busy = false
		for _, job in args.jobs do
			busy = busy or _G.RbxGen.jobs[job.key].state == "running"
		end
	until not busy or os.clock() > deadline
	return _G.RbxGenStatus()
end

-- Publishes models already generated this session (still in Workspace.RbxGen), for picking the
-- keepers from a review sheet first: `return _G.RbxGenPublish("http://127.0.0.1:38519/", { "a", "b" })`.
-- A publish took ~15 s a model on 2026-09-26, so the work runs in its own thread and a call waits at
-- most 50 s; call it again with the same keys to wait on: a model already published (or on its way)
-- is not published twice.
_G.RbxGenPublish = function(url: string, keys: { string }): string
	local folder = workspace:FindFirstChild("RbxGen")
	_G.RbxGen = _G.RbxGen or { jobs = {} }
	for _, key in keys do
		local state = _G.RbxGen.jobs[key] or {}
		_G.RbxGen.jobs[key] = state
		if not state.publishing and not state.publishedAll then
			state.publishing = true
			task.spawn(function()
				local model = folder and folder:FindFirstChild(key)
				local ok, err = pcall(function()
					assert(model, "not in Workspace.RbxGen")
					publishModel(url, key, model, state)
				end)
				state.publishedAll = ok
				state.publishError = if ok then nil else tostring(err)
				state.publishing = false
			end)
		end
	end
	local deadline = os.clock() + 50
	local result
	repeat
		task.wait(0.5)
		local busy = false
		result = {}
		for _, key in keys do
			local state = _G.RbxGen.jobs[key]
			busy = busy or state.publishing
			result[key] = if state.publishError
				then "error: " .. state.publishError
				elseif state.publishedAll then state.published
				else "publishing"
		end
	until not busy or os.clock() > deadline
	return HttpService:JSONEncode(result)
end

-- The arguments are used up, so sending this file again without new ones only (re)loads the
-- functions instead of running the last batch a second time.
local args = _G.RbxGenArgs
_G.RbxGenArgs = nil
if args == nil then
	return "loaded: _G.RbxGenRun(args), _G.RbxGenStatus(), _G.RbxGenPublish(url, keys)"
end
return _G.RbxGenRun(args)
