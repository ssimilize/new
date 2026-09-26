--[[
	PROTOTYPE Studio runner (Edit, through the MCP's execute_luau): generates part-segmented monsters
	with GenerationService:GenerateModelAsync (text + SchemaDefinition groups) and publishes every
	part's mesh and texture as assets, so they load anywhere with CreateMeshPartAsync. The approach
	is tools/rbxgen/generate.luau's (a peer session's), minus the GLB export: nothing is posted.

	Set the arguments in front of this file's text:
		_G.MonsterGenArgs = { wave = 8, jobs = { { key, prompt, parts = {...}, size = {x, y, z} }, ... } }
	It starts in the background and returns at once; `return _G.MonsterGenStatus()` reports progress.
	Results: Workspace.MonsterGen.<key>, each MeshPart tagged MeshAsset / TextureAsset.

	`wave` jobs generate at once (8 took 21-45 s each for tools/rbxgen); publishes go one at a time
	across all jobs (11 at once failed "Too Many Requests" on 2026-09-25).
]]

local AssetService = game:GetService("AssetService")
local GenerationService = game:GetService("GenerationService")
local HttpService = game:GetService("HttpService")

local state = _G.MonsterGen or { jobs = {}, publishing = false }
_G.MonsterGen = state
-- Upload safety (the account was moderated mid-batch on 2026-09-26, HTTP 403 "User is moderated"):
-- uploads are at least `uploadGap` seconds apart, and the FIRST failed upload of any kind sets
-- `halt`, after which nothing uploads again until a person clears it (_G.MonsterGen.halt = nil).
state.uploadGap = state.uploadGap or 20
state.lastUpload = state.lastUpload or 0

local function upload(object, assetType, info)
	assert(not state.halt, "uploads halted: " .. tostring(state.halt))
	local waitFor = state.lastUpload + state.uploadGap - os.clock()
	if waitFor > 0 then
		task.wait(waitFor)
	end
	assert(not state.halt, "uploads halted: " .. tostring(state.halt))
	state.lastUpload = os.clock()
	local status, idOrError = AssetService:CreateAssetAsync(object, assetType, info)
	if status ~= Enum.CreateAssetResult.Success then
		state.halt = `{status} {idOrError}`
		error(`upload failed, halting all uploads: {status} {idOrError}`, 0)
	end
	state.uploads = (state.uploads or 0) + 1
	return idOrError
end

-- Asset names over 50 characters are refused ("Asset name length is invalid", HTTP 400), which
-- CreateAssetAsync reports only as UploadFailed unless its third value is read: "thornbolt back
-- decoration_geom (Monster Ranch prototype)" failed that way, and looked like a rate limit.
local function publishPart(key: string, p: MeshPart)
	local partName = string.gsub(string.gsub(p.Name, "_geom$", ""), "[^%w ]", "")
	local name = string.sub(`{key} {partName}`, 1, 50)
	local info = { Name = name, Description = "Monster Ranch Idle prototype: Roblox generator, animatable parts" }
	-- Parts already published (a retry after a texture failed) keep their ids.
	if not p:GetAttribute("MeshAsset") then
		local em = AssetService:CreateEditableMeshAsync(p.MeshContent, { FixedSize = false })
		local okUp, meshId = pcall(upload, em, Enum.AssetType.Mesh, info)
		em:Destroy()
		assert(okUp, meshId)
		p:SetAttribute("MeshAsset", `rbxassetid://{meshId}`)
	end
	if not p:GetAttribute("TextureAsset") and p.TextureContent.SourceType ~= Enum.ContentSourceType.None then
		local img = AssetService:CreateEditableImageAsync(p.TextureContent)
		local okUp, imageId = pcall(upload, img, Enum.AssetType.Image, info)
		img:Destroy()
		assert(okUp, imageId)
		p:SetAttribute("TextureAsset", `rbxassetid://{imageId}`)
	end
end

-- `release` frees the job's generation slot as soon as the model is back: publishing is
-- serialised anyway, so the next generations should not wait for it.
local function run(job, folder: Folder, slot: number, release: () -> ())
	local st = state.jobs[job.key]
	local released = false
	local function free()
		if not released then
			released = true
			release()
		end
	end
	local ok, err = pcall(function()
		local inputs = {
			TextPrompt = job.prompt,
			MaxTriangles = job.maxTriangles or 20000,
			GenerateTextures = true,
			Size = Vector3.new(job.size.x, job.size.y, job.size.z),
		}
		local schema = { SchemaDefinition = { Groups = job.parts } }
		-- Generation is limited per minute (GenerationService docs): after ~50 in an hour, 29 of 40
		-- started together failed "Rate limit exceeded" (2026-09-26). Wait a minute and try again.
		local model
		for attempt = 1, 8 do
			local okGen, result = pcall(GenerationService.GenerateModelAsync, GenerationService, inputs, schema)
			if okGen then
				model = result
				break
			end
			if not string.find(tostring(result), "Rate limit", 1, true) or attempt == 8 then
				error(result, 0)
			end
			st.state = `rate-limited, retry {attempt}`
			task.wait(60)
		end
		free()
		st.secs = math.floor(os.clock() - st.started)
		st.state = "publishing"
		model.Name = job.key
		model:SetAttribute("Form", job.key)
		model:SetAttribute("Archetype", job.archetype)
		model:SetAttribute("Hover", job.hover == true)
		model:SetAttribute("Line", job.line)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		-- A grid, 12 studs apart, 8 per row, standing on the ground.
		local cf, size = model:GetBoundingBox()
		local col, row = (slot - 1) % 8, (slot - 1) // 8
		model:PivotTo(model:GetPivot() + (Vector3.new(col * 12, size.Y / 2, 200 + row * 14) - cf.Position))
		model.Parent = folder
		st.parts = 0
		for _, p in model:GetDescendants() do
			if p:IsA("MeshPart") then
				while state.publishing do
					task.wait(0.2)
				end
				state.publishing = true
				local okPublish, perr = pcall(publishPart, job.key, p)
				state.publishing = false
				assert(okPublish, perr)
				st.parts += 1
			end
		end
	end)
	free()
	st.state = if ok then "done" else "failed"
	st.error = if ok then nil else tostring(err)
	st.secs = st.secs or math.floor(os.clock() - st.started)
end

-- Publishes, in the background, every part in Workspace.MonsterGen that has no MeshAsset /
-- TextureAsset yet, `gap` seconds apart; a failure backs off 15, 30, 60, 120 s and the last error
-- text is kept in the status. `reverse` walks the list from the end.
-- `return _G.MonsterGenRepublishStatus` (a string) reports progress.
_G.MonsterGenRepublish = function(gap: number?, reverse: boolean?): string
	local todo = {}
	for _, model in workspace.MonsterGen:GetChildren() do
		for _, p in model:GetDescendants() do
			if p:IsA("MeshPart") and not (p:GetAttribute("MeshAsset") and p:GetAttribute("TextureAsset")) then
				table.insert(todo, { model = model.Name, part = p })
			end
		end
	end
	if reverse then
		for i = 1, #todo // 2 do
			todo[i], todo[#todo + 1 - i] = todo[#todo + 1 - i], todo[i]
		end
	end
	local done, missing, lastError = 0, 0, ""
	_G.MonsterGenRepublishStatus = `0 / {#todo} parts`
	task.spawn(function()
		for _, item in todo do
			local ok = false
			for attempt = 0, 4 do
				if attempt > 0 then
					task.wait(15 * 2 ^ (attempt - 1))
				end
				local err
				ok, err = pcall(publishPart, item.model, item.part)
				if ok then
					break
				end
				lastError = tostring(err)
			end
			if ok then
				done += 1
			else
				missing += 1
			end
			_G.MonsterGenRepublishStatus = `{done} / {#todo} parts published, {missing} gave up; last error: {lastError}`
			task.wait(gap or 1.5)
		end
		_G.MonsterGenRepublishStatus ..= " (finished)"
	end)
	return `republishing {#todo} parts in the background`
end

_G.MonsterGenStatus = function(): string
	local counts, failed, running = {}, {}, {}
	for key, st in state.jobs do
		counts[st.state] = (counts[st.state] or 0) + 1
		if st.state == "failed" then
			failed[key] = st.error
		elseif st.state ~= "done" and st.state ~= "queued" then
			running[key] = `{st.state} {st.parts or 0}p`
		end
	end
	return HttpService:JSONEncode({ counts = counts, failed = failed, running = running })
end

_G.MonsterGenRun = function(args)
	local folder = workspace:FindFirstChild("MonsterGen") or Instance.new("Folder")
	folder.Name = "MonsterGen"
	folder.Parent = workspace
	local queue = {}
	for _, job in args.jobs do
		if not (state.jobs[job.key] and state.jobs[job.key].state == "done") then
			state.jobs[job.key] = { state = "queued" }
			table.insert(queue, job)
		end
	end
	local wave = args.wave or 8
	local gap = args.gap or 0 -- seconds between starts, to stay under the per-minute limit
	task.spawn(function()
		local slot = #folder:GetChildren()
		local active = 0
		for _, job in queue do
			while active >= wave do
				task.wait(0.5)
			end
			active += 1
			slot += 1
			state.jobs[job.key] = { state = "generating", started = os.clock() }
			local mySlot = slot
			task.spawn(run, job, folder, mySlot, function()
				active -= 1
			end)
			task.wait(gap)
		end
	end)
	return `queued {#queue}`
end

return _G.MonsterGenRun(_G.MonsterGenArgs)
