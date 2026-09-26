--[[
	Settings (S1): per-player client settings, saved with the profile.

	Save section (profile.Settings): { music, sfx, lowGraphics, hideBroadcasts, language, graphics }
	  language (3.2) = "auto" | "en" | "es" | "pt"; "auto" follows the player's Roblox
	  language on the client (Shared/Locale, Controllers/Localize).
	  graphics (glow-up P) = "auto" | "high" | "low"; lowGraphics == true still means Low (saves
	  from before it; Logic/Quality.Choice), and SetGraphics keeps the two in step.

	Actions: Settings.Set { key, value } (the boolean toggles),
	         Settings.SetLanguage { language }, Settings.SetGraphics { graphics }.
	Public: Settings:Get(player, key)
]]

local Settings = {
	Name = "Settings",
	Dependencies = {},
}

Settings.Profile = {
	Version = 1,
	Default = function()
		return { music = true, sfx = true, lowGraphics = false, hideBroadcasts = false, language = "auto", graphics = "auto" }
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
	ctx.Net:Handle("Settings.SetLanguage", function(player, payload)
		local section = ctx:Section(player)
		section.language = payload.language
		ctx:Dirty(player, "language")
		return nil
	end)
	ctx.Net:Handle("Settings.SetGraphics", function(player, payload)
		local section = ctx:Section(player)
		section.graphics = payload.graphics
		section.lowGraphics = payload.graphics == "low"
		ctx:Dirty(player, "graphics")
		ctx:Dirty(player, "lowGraphics")
		return nil
	end)
end

function Settings:Get(player, key: string): any
	local section = ctx:Section(player)
	return section and section[key]
end

return Settings
