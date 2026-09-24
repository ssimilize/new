--[[
	Settings screen (C3): toggles for music, sound effects, low graphics and hiding
	broadcasts → Settings.Set { key, value }. Reads profile.Settings (tolerated nil).
]]

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Util = require(script.Parent.Parts.Util)

local New = Create.New
local C = Theme.Colors

local ROWS = {
	{ key = "music", name = "Music", desc = "Background music", default = true },
	{ key = "sfx", name = "Sound effects", desc = "Buttons, hatches and battles", default = true },
	{ key = "lowGraphics", name = "Low graphics", desc = "Fewer effects and less motion. Helps older phones.", default = false },
	{ key = "hideBroadcasts", name = "Hide broadcasts", desc = "Hide server-wide announcements", default = false },
}

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
		}, { Create.List("y", 10) })

		local bag = Util.bag()
		local toggles = {}
		local pending = {}

		local function current(key: string, default: boolean): boolean
			local settings = ctx.Store:Get("profile.Settings")
			if pending[key] ~= nil then
				return pending[key]
			end
			if type(settings) == "table" and type(settings[key]) == "boolean" then
				return settings[key]
			end
			return default
		end

		local function paint(row)
			local on = current(row.key, row.default)
			local b = toggles[row.key]
			b:SetText(if on then "On" else "Off")
			b:SetColor(if on then C.Green else C.Gray)
		end

		for i, row in ROWS do
			local frame = Util.card({ Size = UDim2.new(1, 0, 0, 68), LayoutOrder = i, Parent = list })
			Util.text({
				Text = row.name,
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body + 1,
				Position = UDim2.fromOffset(14, 6),
				Size = UDim2.new(1, -160, 0, 26),
				Parent = frame,
			})
			Util.text({
				Text = row.desc,
				TextColor3 = C.TextMuted,
				Position = UDim2.fromOffset(14, 34),
				Size = UDim2.new(1, -160, 0, 24),
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Parent = frame,
			})
			local toggle = Button.new({
				Text = "",
				Color = C.Gray,
				Size = UDim2.fromOffset(120, 50),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Parent = frame,
			})
			toggles[row.key] = toggle
			toggle:SetOnClick(function()
				local value = not current(row.key, row.default)
				pending[row.key] = value
				paint(row)
				Util.request(ctx, "Settings.Set", { key = row.key, value = value })
				pending[row.key] = nil
				paint(row)
			end)
			paint(row)
		end

		Util.text({
			Text = "User ID " .. tostring(ctx.Player.UserId) .. " · share this with support if something goes wrong.",
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
					for _, row in ROWS do
						paint(row)
					end
				end))
			end,
			Close = function()
				bag.clean()
			end,
		}
	end,
}
