--[[
	SoundCheck (Studio only): audition every Config.Sounds key before its id is approved.

	Registered by the Soundscape controller only when RunService:IsStudio(), so live games never
	have it (it is not in the client Manifest). Lists every key under its kind (Logic/Audio.Kind)
	with its group, its id (+N variations) or "empty", and Play / Stop. Loops and scatter beds
	play alone at full through Audio.Override; one-shots play as the game would (pitch range, cooldown, group
	volume). Voices play at a Baby, Teen and Adult pitch. The Music row previews a context
	(Soundscape.Preview) so crossfades, beds and thunder can be heard; "Live" hands back control.
	Developer tool: text is English only (Localize = false).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logic = require(ReplicatedStorage.Shared.Logic.Audio)

local UI = script.Parent.Parent
local Client = UI.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Panel = require(UI.Components.Panel)
local Widgets = require(UI.Components.Widgets)
local Audio = require(Client.Audio)

local New = Create.New
local C = Theme.Colors

local ROW = 48

-- Contexts the Music row can force; each is a Soundscape state (Logic/Audio.MusicChain, Beds).
local CONTEXTS = {
	{ "Live", nil },
	{ "Ranch day", { weather = "clear" } },
	{ "Ranch night", { weather = "clear", night = true } },
	{ "Hub", { weather = "clear", hub = true } },
	{ "Sky Islands", { weather = "clear", sky = true } },
	{ "Battle", { weather = "clear", battle = true } },
	{ "Stampede", { weather = "clear", stampede = true } },
	{ "Rain", { weather = "rain" } },
	{ "Storm", { weather = "thunderstorm", night = true } },
}
for eventId in Logic.EventMusic do
	table.insert(CONTEXTS, { "Event: " .. eventId, { weather = "clear", event = eventId } })
end

local VOICE_STAGES = { { "Baby", 1 }, { "Teen", 2 }, { "Adult", 3 } }

local function plain(gui: Instance)
	gui:SetAttribute("Localize", false)
	for _, d in gui:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			d:SetAttribute("Localize", false)
		end
	end
end

return {
	Name = "SoundCheck",
	Build = function(ctx)
		local panel = Panel.new({
			Title = "Sound Check",
			Color = C.Gray,
			Size = UDim2.fromOffset(940, 520),
			OnClose = function()
				ctx.Router:Close("SoundCheck")
			end,
		})
		local list = Widgets.List({ Parent = panel.Body, Padding = 6 })
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end

		local function soundscape()
			return ctx:GetController("Soundscape")
		end

		local function heading(text: string)
			Create.Text({
				Text = text,
				Font = Theme.Fonts.Display,
				TextSize = Theme.TextSize.Body + 2,
				Size = UDim2.new(1, 0, 0, 30),
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = nextOrder(),
				Parent = list,
			})
		end

		local function small(text: string, color: Color3, width: number, parent: Instance)
			return Create.Text({
				Text = text,
				TextSize = Theme.TextSize.Small,
				TextColor3 = color,
				Size = UDim2.new(0, width, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Parent = parent,
			})
		end

		-- Music contexts ---------------------------------------------------------------------
		heading("Music contexts")
		local contexts = New("Frame", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = nextOrder(),
			Parent = list,
		}, { Create.Grid(Vector2.new(170, 44), 6) })
		local nowRow = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = nextOrder(),
			Parent = list,
		})
		local nowPlaying = small("", C.TextMuted, 800, nowRow)
		local function paintNowPlaying()
			local key = Audio.Music()
			nowPlaying.Text = "Music now: " .. (key or "silent (no filled key in this context)")
		end
		for _, context in CONTEXTS do
			Button.new({
				Text = context[1],
				Color = if context[2] then C.Blue else C.Green,
				TextSize = Theme.TextSize.Small,
				Size = UDim2.fromOffset(170, 44),
				Parent = contexts,
				OnClick = function()
					Audio.Override(nil)
					local scape = soundscape()
					if scape then
						scape.Preview(context[2])
					end
					paintNowPlaying()
				end,
			})
		end
		Button.new({
			Text = "Stop all",
			Color = C.Red,
			TextSize = Theme.TextSize.Small,
			Size = UDim2.fromOffset(170, 44),
			Parent = contexts,
			OnClick = function()
				Audio.Override(nil)
				for _, key in Audio.Keys() do
					Audio.Stop(key)
				end
			end,
		})

		-- Every key, by kind -----------------------------------------------------------------
		local byKind = {}
		for _, key in Audio.Keys() do
			local kind = Logic.Kind(key)
			byKind[kind] = byKind[kind] or {}
			table.insert(byKind[kind], key)
		end
		local filled, total = 0, 0

		local function keyRow(key: string)
			local spec = Audio.Spec(key)
			if not spec then
				return
			end
			total += 1
			filled += if spec.empty then 0 else 1
			local row = New("Frame", {
				Name = "Key_" .. key,
				BackgroundColor3 = C.White,
				BackgroundTransparency = 0.6,
				Size = UDim2.new(1, 0, 0, ROW),
				LayoutOrder = nextOrder(),
				Parent = list,
			}, {
				Create.Corner(8),
				Create.List("x", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
				Create.Padding(0, 8, 0, 8),
			})
			small(key, C.Text, 190, row)
			local mode = if spec.scatter then " · scatter" elseif spec.looped then " · loop" else ""
			small(spec.group .. mode, C.TextMuted, 120, row)
			local idText = if #spec.ids > 1 then string.format("%s +%d", spec.id, #spec.ids - 1) else spec.id
			small(if spec.empty then "empty" else idText, if spec.empty then C.Red else C.Green, 250, row)
			if Logic.Kind(key) == "Voices" then
				for _, stage in VOICE_STAGES do
					Button.new({
						Text = stage[1],
						Color = C.Blue,
						TextSize = Theme.TextSize.Small,
						Size = UDim2.fromOffset(84, 44),
						Sound = false,
						Parent = row,
						OnClick = function()
							local pitch = Logic.VoicePitch({ stage = stage[2] })
							Audio.Play(key, { pitch = pitch })
						end,
					})
				end
			else
				Button.new({
					Text = "Play",
					Color = C.Green,
					TextSize = Theme.TextSize.Small,
					Size = UDim2.fromOffset(84, 44),
					Sound = false,
					Parent = row,
					OnClick = function()
						if spec.looped or spec.scatter then
							Audio.Override(key)
						elseif key == "CoinTick" then
							for i = 0, 7 do
								task.delay(i * 0.12, Audio.Streak, key)
							end
						else
							Audio.Play(key)
						end
					end,
				})
			end
			Button.new({
				Text = "Stop",
				Color = C.Gray,
				TextSize = Theme.TextSize.Small,
				Size = UDim2.fromOffset(84, 44),
				Sound = false,
				Parent = row,
				OnClick = function()
					if spec.looped or spec.scatter then
						Audio.Override(nil)
					end
					Audio.Stop(key)
				end,
			})
		end

		for _, kind in Logic.KindOrder do
			local keys = byKind[kind]
			if keys then
				heading(kind)
				for _, key in keys do
					keyRow(key)
				end
			end
		end
		heading(string.format("%d of %d keys have an id", filled, total))
		plain(panel.Root)

		return {
			Root = panel.Root,
			Open = function()
				paintNowPlaying()
			end,
			Close = function()
				Audio.Override(nil)
				local scape = soundscape()
				if scape then
					scape.Preview(nil)
				end
			end,
		}
	end,
}
