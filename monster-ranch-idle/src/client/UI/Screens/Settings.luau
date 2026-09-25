--[[
	Settings screen (C3): the language (3.2) and toggles for music, sound effects, low
	graphics and hiding broadcasts → Settings.SetLanguage { language } and
	Settings.Set { key, value }. Reads profile.Settings (tolerated nil).

	Language comes first so a player who can't read the current one still finds it. Its
	button cycles Auto → English → Español → Português; language names are never
	translated, and Auto shows the language it picked.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Util = require(script.Parent.Parts.Util)
local Locale = require(ReplicatedStorage.Shared.Locale)

local New = Create.New
local C = Theme.Colors

local ROW_HEIGHT = 60

local ROWS = {
	{ key = "music", name = "Music", desc = "Background music", default = true },
	{ key = "sfx", name = "Sound effects", desc = "Buttons, hatches and battles", default = true },
	{ key = "lowGraphics", name = "Low graphics", desc = "Fewer effects and less motion. Helps older phones.", default = false },
	{ key = "hideBroadcasts", name = "Hide broadcasts", desc = "Hide server-wide announcements", default = false },
}

local LANGUAGE_NAMES = {}
for _, language in Locale.Languages do
	LANGUAGE_NAMES[language.id] = language.name
end

return {
	Name = "Settings",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Settings",
			Color = C.Gray,
			Size = UDim2.fromOffset(620, 480),
			OnClose = function()
				ctx.Router:Close("Settings")
			end,
		})
		local list = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -50),
			Parent = panel.Body,
		}, { Create.List("y", 8) })

		local bag = Util.bag()
		local toggles = {}
		local pending = {}

		local function saved(key: string): any
			local settings = ctx.Store:Get("profile.Settings")
			return if type(settings) == "table" then settings[key] else nil
		end

		local function current(key: string, default: boolean): boolean
			if pending[key] ~= nil then
				return pending[key]
			end
			local value = saved(key)
			if type(value) == "boolean" then
				return value
			end
			return default
		end

		local function row(order: number, name: string, desc: string, buttonWidth: number)
			local frame = Util.card({ Size = UDim2.new(1, 0, 0, ROW_HEIGHT), LayoutOrder = order, Parent = list })
			Util.text({
				Text = name,
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body + 1,
				Position = UDim2.fromOffset(14, 4),
				Size = UDim2.new(1, -(buttonWidth + 40), 0, 26),
				Parent = frame,
			})
			Util.text({
				Text = desc,
				TextColor3 = C.TextMuted,
				Position = UDim2.fromOffset(14, 30),
				Size = UDim2.new(1, -(buttonWidth + 40), 0, 24),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Parent = frame,
			})
			return Button.new({
				Text = "",
				Color = C.Gray,
				Size = UDim2.fromOffset(buttonWidth, 50),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Parent = frame,
			})
		end

		-- Language -----------------------------------------------------------------
		local languageButton = row(0, "Language", "Menus and messages", 210)

		local function languageSetting(): string
			local value = pending.language or saved("language")
			return if table.find(Locale.Choices, value) then value else "auto"
		end

		local function paintLanguage()
			local setting = languageSetting()
			if setting == "auto" then
				local picked = Locale.FromLocaleId(ctx.Player.LocaleId)
				languageButton:SetText(string.format("Auto · %s", LANGUAGE_NAMES[picked]))
				languageButton:SetColor(C.Gray)
			else
				languageButton:SetText(LANGUAGE_NAMES[setting])
				languageButton:SetColor(C.Blue)
			end
		end

		languageButton:SetOnClick(function()
			local index = table.find(Locale.Choices, languageSetting()) or 1
			local nextValue = Locale.Choices[index % #Locale.Choices + 1]
			pending.language = nextValue
			paintLanguage()
			Util.request(ctx, "Settings.SetLanguage", { language = nextValue })
			pending.language = nil
			paintLanguage()
		end)
		paintLanguage()

		-- Toggles ------------------------------------------------------------------
		local function paint(item)
			local on = current(item.key, item.default)
			local b = toggles[item.key]
			b:SetText(if on then "On" else "Off")
			b:SetColor(if on then C.Green else C.Gray)
		end

		for i, item in ROWS do
			local toggle = row(i, item.name, item.desc, 120)
			toggles[item.key] = toggle
			toggle:SetOnClick(function()
				local value = not current(item.key, item.default)
				pending[item.key] = value
				paint(item)
				Util.request(ctx, "Settings.Set", { key = item.key, value = value })
				pending[item.key] = nil
				paint(item)
			end)
			paint(item)
		end

		Util.text({
			Text = string.format("User ID %d · share this with support if something goes wrong.", ctx.Player.UserId),
			TextColor3 = C.TextMuted,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, -170, 0, 44),
			Parent = panel.Body,
		})
		Button.new({
			Text = "Codes",
			Color = C.Orange,
			Size = UDim2.fromOffset(150, 46),
			TextSize = Theme.TextSize.Body,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 1),
			Parent = panel.Body,
			OnClick = function()
				if ctx.Router:Has("Store") then
					ctx.Router:Open("Store", { tab = "codes" })
				end
			end,
		})

		return {
			Root = panel.Root,
			Open = function()
				bag.clean()
				bag.add(ctx.Store:Observe("profile.Settings", function()
					paintLanguage()
					for _, item in ROWS do
						paint(item)
					end
				end))
			end,
			Close = function()
				bag.clean()
			end,
		}
	end,
}
