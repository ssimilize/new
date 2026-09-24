-- Settings (S1): per-player client settings, saved with the profile.
local Settings = {
	Name = "Settings",
	Dependencies = {},
}

Settings.Profile = {
	Version = 1,
	Default = function()
		return { music = true, sfx = true, lowGraphics = false, hideBroadcasts = false }
	end,
}

local ctx

function Settings.Init(context)
	ctx = context
	ctx.Net:Handle("Settings.Set", function(player, payload)
		local section = ctx:Section(player)
		section[payload.key] = payload.value
		ctx:Dirty(player, payload.key)
		return nil
	end)
end

function Settings:Get(player, key: string): any
	local section = ctx:Section(player)
	return section and section[key]
end

return Settings
