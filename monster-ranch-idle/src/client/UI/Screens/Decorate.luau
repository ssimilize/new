--[[
	Decorate (glow-up Z · Build your ranch): placement mode's toolbar and tray. A non-modal screen;
	the world side (draft, ghosts, grid overlay, camera, taps and drags, pad buttons, hiding the HUD)
	is the Decor controller, entered by Open and left by Close. Opened from the HUD's 🔨 button and
	the Ranch screen's "Build your ranch".

	  top-left    pieces placed / the Ranch Level cap
	  top-right   Save (Decor.Save with the whole layout) · ✕ leave (asks again with unsaved changes)
	  right       Rotate (45°) · Remove (back to the tray) · Undo
	  bottom      kind tabs (All, Fences, Paths, …) and the tray of owned pieces with how many are
	              left: tap one to put it on the nearest free spot, then tap or drag the ground
	  status      what to do next, or why the selected piece is red
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Logic.DecorLayout)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)

local New = Create.New
local C = Theme.Colors

local TABS = {
	{ id = "all", name = "All" },
	{ id = "fence", name = "Fences" },
	{ id = "path", name = "Paths" },
	{ id = "light", name = "Lights" },
	{ id = "water", name = "Water" },
	{ id = "plant", name = "Plants" },
	{ id = "seat", name = "Seats" },
	{ id = "arch", name = "Arches" },
	{ id = "statue", name = "Statues" },
	{ id = "toy", name = "Toys" },
	{ id = "fun", name = "Fun" },
}

return {
	Name = "Decorate",
	Build = function(ctx)
		local screen = { Modal = false }
		local decor = nil -- the controller, looked up on open
		local tab = "all"
		local leaving = false
		local changedConn = nil

		local root = New("Frame", {
			Name = "Decorate",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		})

		local count = Create.Text({
			Name = "Count",
			Text = "",
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Left,
			Stroke = true,
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.fromOffset(220, 30),
			Parent = root,
		})
		local status = Create.Text({
			Name = "Status",
			Text = "",
			TextSize = Theme.TextSize.Small,
			Stroke = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -136),
			Size = UDim2.new(1, -150, 0, 24),
			Parent = root,
		})

		local function toast(err: any)
			if err then
				ctx:Toast(tostring(err), "error")
			end
		end

		local saveButton = Button.new({
			Name = "Save",
			Text = "Save",
			Color = C.Green,
			Size = UDim2.fromOffset(100, 46),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -64, 0, 8),
			Parent = root,
			OnClick = function()
				if not decor then
					return
				end
				local ok, err = decor.Save()
				if ok then
					ctx:Toast("Your ranch layout is saved!", "success")
				else
					toast(err)
				end
			end,
		})
		Button.new({
			Name = "Leave",
			Text = "✕",
			Color = C.Red,
			Size = UDim2.fromOffset(46, 46),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 8),
			Parent = root,
			OnClick = function()
				if decor and decor.Dirty() and not leaving then
					leaving = true
					ctx:Toast("You have unsaved changes. Tap ✕ again to leave.", "info")
					return
				end
				ctx.Router:Close("Decorate")
			end,
		})

		local tools = New("Frame", {
			Name = "Tools",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 60),
			Size = UDim2.fromOffset(100, 150),
			Parent = root,
		}, { New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })
		local function tool(name: string, text: string, color: Color3, order: number, fn)
			local b = Button.new({
				Name = name,
				Text = text,
				Color = color,
				Size = UDim2.fromOffset(100, 44),
				TextSize = Theme.TextSize.Small,
				Parent = tools,
				OnClick = function()
					if decor then
						fn()
					end
				end,
			})
			b.Root.LayoutOrder = order
			return b
		end
		tool("Rotate", "Rotate", C.Blue, 1, function()
			decor.Rotate()
		end)
		tool("Remove", "Remove", C.Orange, 2, function()
			decor.Remove()
		end)
		tool("Undo", "Undo", C.Purple, 3, function()
			decor.Undo()
		end)

		local tabRow = New("ScrollingFrame", {
			Name = "Tabs",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 8, 1, -94),
			Size = UDim2.new(1, -16, 0, 38),
			CanvasSize = UDim2.fromScale(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 0,
			ScrollBarImageTransparency = 1,
			Parent = root,
		}, {
			New("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 4),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local tray = New("ScrollingFrame", {
			Name = "Tray",
			BackgroundColor3 = C.Dark,
			BackgroundTransparency = 0.35,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 8, 1, -6),
			Size = UDim2.new(1, -16, 0, 86),
			CanvasSize = UDim2.fromScale(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 4,
			Parent = root,
		}, {
			Create.Corner(12),
			New("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			New("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
		})

		local refresh

		local tabButtons = {}
		for i, t in TABS do
			local b = Button.new({
				Name = "Tab_" .. t.id,
				Text = t.name,
				Color = C.Gray,
				Size = UDim2.fromOffset(86, 36),
				TextSize = Theme.TextSize.Small,
				Sound = "UITab",
				Parent = tabRow,
				OnClick = function()
					tab = t.id
					refresh()
				end,
			})
			b.Root.LayoutOrder = i
			tabButtons[t.id] = b
		end

		local tiles = {}
		local empty: TextLabel? = nil
		local function clearTiles()
			for _, b in tiles do
				b:Destroy()
			end
			table.clear(tiles)
			if empty then
				empty:Destroy()
				empty = nil
			end
		end

		refresh = function()
			for id, b in tabButtons do
				b:SetColor(if id == tab then C.Orange else C.Gray)
			end
			clearTiles()
			if not decor then
				return
			end
			leaving = false
			local draft = decor.Draft()
			local level = tonumber(ctx.Store:Get("profile.Progression.level")) or 1
			count.Text = string.format("Decor %d / %d", #draft, Layout.Cap(level))
			local available = decor.Available()
			local order = 0
			for _, def in Config.Decor.List do
				local n = available[def.id]
				if n and (tab == "all" or def.kind == tab) then
					order += 1
					local b = Button.new({
						Name = "Piece_" .. def.id,
						Text = string.format("%s ×%d", def.name, n),
						Color = if def.event then C.Pink elseif def.set == "starter" then C.Green else C.Blue,
						Size = UDim2.fromOffset(128, 70),
						TextSize = Theme.TextSize.Small,
						Parent = tray,
						OnClick = function()
							local ok, err = decor.Add(def.id)
							if not ok then
								toast(err)
							end
						end,
					})
					b.Root.LayoutOrder = order
					table.insert(tiles, b)
				end
			end
			if order == 0 then
				empty = Create.Text({
					Name = "Empty",
					Text = "Nothing here yet. Buy decor in the Store!",
					TextSize = Theme.TextSize.Small,
					Stroke = true,
					Size = UDim2.fromOffset(360, 60),
					Parent = tray,
				})
			end
			local selected = decor.Selected()
			local problem = selected and decor.Problems()[selected]
			if problem then
				status.Text = problem
				status.TextColor3 = C.Red
			elseif selected then
				status.Text = "Tap or drag the ground to move it"
				status.TextColor3 = C.Card
			else
				status.Text = "Pick a piece below, or tap one on your ranch"
				status.TextColor3 = C.Card
			end
			saveButton:SetDisabled(not decor.Dirty())
		end

		screen.Root = root
		screen.Open = function()
			decor = ctx:GetController("Decor")
			tab = "all"
			leaving = false
			local ok, err = decor.Enter()
			if not ok then
				toast(err)
				task.defer(function()
					ctx.Router:Close("Decorate")
				end)
				return
			end
			if changedConn then
				changedConn:Disconnect()
			end
			changedConn = decor.Changed:Connect(refresh)
			refresh()
		end
		screen.Close = function()
			if changedConn then
				changedConn:Disconnect()
				changedConn = nil
			end
			if decor then
				decor.Exit()
			end
			clearTiles()
		end
		return screen
	end,
}
