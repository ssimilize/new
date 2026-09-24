--[[
	Data: session-locked player profiles on top of a DataStore adapter.

	Stored value per player:
	  { data = <profile>, lock = { job = JobId, at = unix } | nil, v = 1 }

	Load:  UpdateAsync claims the lock. If another live server holds it (lock younger than
	       LockTimeout) we wait and retry; after `StealAfterAttempts` we take the lock anyway
	       (the old server notices on its next save and kicks its copy of the player).
	Save:  UpdateAsync writes data only while we still own the lock.
	Release: writes data and clears the lock.

	Profile layout:
	  data._meta = { created, lastSeen, joins, playSeconds, versions = { [System] = n } }
	  data.<SystemName> = that system's section (see System.Profile in ARCHITECTURE.md)
]]

local Data = {}
Data.__index = Data

Data.LockTimeout = 30 * 60
Data.LoadAttempts = 6
Data.StealAfterAttempts = 4
Data.RetryDelay = 3
Data.KeyPrefix = "player_"

function Data.new(kernel, store, adapters)
	return setmetatable({
		_kernel = kernel,
		_store = store,
		_adapters = adapters,
		_profiles = {}, -- [player] = data
		_saving = {}, -- [player] = true while a save is running
	}, Data)
end

local function key(player): string
	return Data.KeyPrefix .. tostring(player.UserId)
end

function Data:Get(player: any)
	return self._profiles[player]
end

function Data:IsLoaded(player: any): boolean
	return self._profiles[player] ~= nil
end

function Data:Load(player: any): (any?, string?)
	local jobId = self._adapters.JobId
	local now = self._kernel.Clock.Now()
	for attempt = 1, Data.LoadAttempts do
		local blocked = false
		local ok, result = self._store:Update(key(player), function(old)
			old = old or { v = 1 }
			local lock = old.lock
			if lock and lock.job ~= jobId and now - lock.at < Data.LockTimeout and attempt < Data.StealAfterAttempts then
				blocked = true
				return nil -- abort the write; someone else holds the lock
			end
			old.lock = { job = jobId, at = now }
			return old
		end)
		if ok and not blocked and result then
			local data = result.data or {}
			self._profiles[player] = data
			return data, nil
		end
		if not ok then
			warn(string.format("[Data] load attempt %d for %d failed: %s", attempt, player.UserId, tostring(result)))
		end
		self._adapters.Wait(Data.RetryDelay)
	end
	return nil, "Your data could not be loaded. Please rejoin."
end

-- Saves the profile. `release` also clears the session lock (player leaving / shutdown).
function Data:Save(player: any, release: boolean?): boolean
	local data = self._profiles[player]
	if not data then
		return false
	end
	if self._saving[player] and not release then
		return false
	end
	self._saving[player] = true
	local jobId = self._adapters.JobId
	local now = self._kernel.Clock.Now()
	local lostLock = false
	local ok, err = self._store:Update(key(player), function(old)
		old = old or { v = 1 }
		if old.lock and old.lock.job ~= jobId then
			lostLock = true
			return nil
		end
		old.data = data
		old.lock = if release then nil else { job = jobId, at = now }
		return old
	end)
	self._saving[player] = nil
	if lostLock then
		warn(string.format("[Data] lost session lock for %d; kicking this copy", player.UserId))
		self._profiles[player] = nil
		self._adapters.Players.Kick(player, "Your ranch was opened on another server.")
		return false
	end
	if not ok then
		warn(string.format("[Data] save for %d failed: %s", player.UserId, tostring(err)))
		return false
	end
	if release then
		self._profiles[player] = nil
	end
	return true
end

function Data:Forget(player: any)
	self._profiles[player] = nil
	self._saving[player] = nil
end

return Data
