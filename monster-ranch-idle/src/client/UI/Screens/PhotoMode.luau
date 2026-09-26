--[[
	PhotoMode screen: the compact toolbar, photo frames, stickers and the photo card of photo mode.
	A non-modal Router screen; the world side (camera, filters, depth of field, hiding the game UI,
	input, CaptureService) is the PhotoMode controller, started by Open and ended by Close.

	  top-right     👁 hide the toolbar for a clean shot (a tap anywhere brings it back) · ✕ leave
	  bottom row    Filter (cycles Config.Photo.Filters) · Frame (cycles Config.Photo.Frames) ·
	                Stickers (tray) · Pose · Blur on/off (hidden in low graphics) ·
	                📷 Take photo (only where CaptureService can capture)
	  sticker tray  the uploaded sprites of Config.Photo.Stickers: tap one to arm it, then tap the
	                scene to place it (it stays armed); Clear removes them all. A placed sticker
	                drags; a tap on it shows its ✕.
	  frames        polaroid border with "<name>'s ranch", a rounded vignette, a "Monster Ranch"
	                corner badge (built from the UI kit, above the scene, below the toolbar)
	  photo card    after a capture: the photo, Save (PromptSaveCapturesToGallery) and Share
	                (PromptShareCapture) where they exist, and Back. It is a UI/Focus modal, so a
	                pad's cursor and B work on it.
	Taking a photo hides the toolbar, captures, then flashes (not with reduced motion) and plays
	PhotoShutter. The root's GamepadLegend attribute lists the pad buttons (the controller reads the
	pad itself). Stickers are cleared when photo mode closes; the filter and frame are kept.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage.Shared
local PhotoConfig = require(Shared.Config.Photo)
local VfxSprites = require(Shared.Config.VfxSprites)
local PhotoRig = require(Shared.Logic.PhotoRig)

local UI = script.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Focus = require(UI.Focus)
local Button = require(UI.Components.Button)

local New = Create.New
local C = Theme.Colors

local LEGEND_CAPTURE = "Ⓐ Photo · Ⓧ Filter · Ⓨ Pose · LB/RB Frame · Ⓑ Exit"
local LEGEND_PLAIN = "Ⓧ Filter · Ⓨ Pose · LB/RB Frame · Ⓑ Exit"
local HINT_TOUCH = "Drag to look around · Pinch to zoom · Tap to focus"
local HINT_MOUSE = "Drag to look around · Right-drag to move · Scroll to zoom · Click to focus"
local HINT_STICKER = "Tap where the sticker goes"
local HINT_HIDDEN = "Tap anywhere to show the buttons"

local STICKER_SIZE = 84
local RECENT_POINTER = 1.5 -- seconds: an Activated this soon after a pointer press was that press

local FRAMES = PhotoConfig.Frames

local function stickerNames(): { string }
	local list = {}
	for _, name in PhotoConfig.Stickers do
		local sprite = VfxSprites[name]
		if sprite and sprite.color then
			table.insert(list, name)
		end
	end
	return list
end

local function emoji(text: string, size: number?): TextLabel
	return Create.Text({ Text = text, TextSize = size or 24, Size = UDim2.fromOffset(28, 28), Stroke = false })
end

return {
	Name = "PhotoMode",
	Build = function(ctx)
		local screen = { Modal = false }
		local photo = nil -- the controller, looked up on open
		local hidden = false
		local shooting = false
		local frameIndex = 1
		local armed: string? = nil
		local stickers = {} -- ImageButtons, oldest first
		local selected: GuiObject? = nil
		local drag = nil -- { sticker, input, last, moved }
		local recentPointer = {} -- [sticker] = os.clock() of its last pointer press
		local conns = {}
		local hintToken = 0
		local ringToken = 0
		local cardId: string? = nil
		local api

		local root = New("Frame", {
			Name = "PhotoMode",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		})

		-- The scene surface: sinks touches and clicks (so the world and character ignore them) and
		-- hands them to the controller.
		local surface = New("TextButton", {
			Name = "Surface",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Parent = root,
		})

		local frameArt = New("Frame", {
			Name = "FrameArt",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = root,
		})
		local stickerLayer = New("Frame", {
			Name = "Stickers",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = root,
		})

		local ring = New("Frame", {
			Name = "FocusRing",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(70, 70),
			Visible = false,
			ZIndex = 8,
			Parent = root,
		}, { Create.Round(), Create.Stroke(3, C.White, 0.1) })

		local flashFrame = New("Frame", {
			Name = "Flash",
			BackgroundColor3 = C.White,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 40,
			Parent = root,
		})

		local hint = New("Frame", {
			Name = "Hint",
			BackgroundColor3 = C.Dark,
			BackgroundTransparency = 0.35,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 14),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 38),
			Visible = false,
			ZIndex = 9,
			Parent = root,
		}, { Create.Round(), Create.Padding(0, 16, 0, 16) })
		local hintLabel = Create.Text({
			Text = "",
			TextSize = Theme.TextSize.Small + 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			TextWrapped = false,
			ZIndex = 10,
			Parent = hint,
		})

		-- Frames ----------------------------------------------------------------------------

		local frameViews = {}

		local function bar(parent: Instance, props)
			props.BackgroundColor3 = C.Panel
			props.BorderSizePixel = 0
			props.ZIndex = 2
			props.Parent = parent
			return New("Frame", props)
		end

		local polaroid = New("Frame", {
			Name = "polaroid",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = frameArt,
		})
		bar(polaroid, { Name = "Top", Size = UDim2.fromScale(1, 0.05) })
		bar(polaroid, { Name = "Left", Size = UDim2.fromScale(0.035, 1) })
		bar(polaroid, {
			Name = "Right",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.035, 1),
		})
		local polaroidBottom = bar(polaroid, {
			Name = "Bottom",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0.17),
		})
		New("Frame", {
			Name = "Edge",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.035, 0.05),
			Size = UDim2.fromScale(0.93, 0.78),
			ZIndex = 2,
			Parent = polaroid,
		}, { Create.Stroke(2, C.Line, 0) })
		local caption = Create.Text({
			Name = "Caption",
			Text = "",
			Font = Theme.Fonts.Display,
			TextColor3 = C.Text,
			Stroke = false,
			TextSize = Theme.TextSize.Header,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = polaroidBottom,
		})
		frameViews.polaroid = polaroid

		-- A thick rounded stroke around an inset frame: its outer edge runs past the screen, so
		-- only a soft rounded border shows.
		local vignette = New("Frame", {
			Name = "vignette",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(40, 40),
			Size = UDim2.new(1, -80, 1, -80),
			ZIndex = 2,
			Parent = frameArt,
		}, { Create.Corner(48), Create.Stroke(80, C.Dark, 0.3) })
		New("Frame", {
			Name = "Inner",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = vignette,
		}, { Create.Corner(48), Create.Stroke(10, C.Dark, 0.6) })
		frameViews.vignette = vignette

		local badge = New("Frame", {
			Name = "badge",
			BackgroundColor3 = C.Dark,
			BackgroundTransparency = 0.2,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -24, 1, -24),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 54),
			ZIndex = 2,
			Parent = frameArt,
		}, {
			Create.Round(),
			Create.Stroke(3, C.White, 0),
			Create.Padding(0, 20, 0, 12),
			Create.List("x", 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
		})
		local star = VfxSprites.star5 or VfxSprites.star
		if star and star.color then
			New("ImageLabel", {
				Name = "Star",
				BackgroundTransparency = 1,
				Image = star.color,
				Size = UDim2.fromOffset(38, 38),
				LayoutOrder = 1,
				ZIndex = 3,
				Parent = badge,
			})
		end
		local brand = Create.Text({
			Name = "Brand",
			Text = "Monster Ranch",
			TextSize = Theme.TextSize.Header,
			TextColor3 = C.Gold,
			Stroke = true,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			TextWrapped = false,
			LayoutOrder = 2,
			ZIndex = 3,
			Parent = badge,
		})
		brand:SetAttribute("Localize", false) -- the game's name
		frameViews.badge = badge

		local function showFrame()
			local id = (FRAMES[frameIndex] or FRAMES[1]).id
			for key, view in frameViews do
				view.Visible = key == id
			end
		end

		-- Chrome ----------------------------------------------------------------------------

		local corner = New("Frame", {
			Name = "Corner",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 12),
			Size = UDim2.fromOffset(120, 52),
			ZIndex = 10,
			Parent = root,
		}, { Create.List("x", 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Top) })

		local toolbar = New("Frame", {
			Name = "Toolbar",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.fromOffset(940, 64),
			ZIndex = 10,
			Parent = root,
		}, { Create.List("x", 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom) })

		local tray = New("Frame", {
			Name = "Tray",
			BackgroundColor3 = C.Dark,
			BackgroundTransparency = 0.3,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -86),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 72),
			Visible = false,
			ZIndex = 10,
			Parent = root,
		}, {
			Create.Corner(Theme.Radius.Card),
			Create.Stroke(2.5, C.White, 0.2),
			Create.Padding(8, 10, 8, 10),
			Create.List("x", 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
		})

		local function flashHint(text: string?, seconds: number?)
			hintToken += 1
			local token = hintToken
			if not text then
				hint.Visible = false
				return
			end
			hintLabel.Text = text
			hint.Visible = true
			task.delay(seconds or 4, function()
				if hintToken == token then
					hint.Visible = false
				end
			end)
		end

		-- Stickers --------------------------------------------------------------------------

		local trayButtons = {} -- [name] = ImageButton
		local deselect

		local function removeSticker(sticker: GuiObject)
			local at = table.find(stickers, sticker)
			if at then
				table.remove(stickers, at)
			end
			if selected == sticker then
				selected = nil
			end
			if drag and drag.sticker == sticker then
				drag = nil
			end
			recentPointer[sticker] = nil
			sticker:Destroy()
		end

		local function selectSticker(sticker: GuiObject?)
			if selected and selected ~= sticker and selected.Parent then
				local old = selected:FindFirstChild("Remove")
				if old then
					old.Visible = false
				end
			end
			selected = sticker
			if sticker then
				local remove = sticker:FindFirstChild("Remove")
				if remove then
					remove.Visible = true
				end
			end
		end
		deselect = function()
			selectSticker(nil)
		end

		local function addSticker(name: string, at: Vector2)
			local sprite = VfxSprites[name]
			if not sprite or not sprite.color then
				return
			end
			if #stickers >= PhotoConfig.MaxStickers then
				removeSticker(stickers[1])
			end
			local sticker = New("ImageButton", {
				Name = "Sticker",
				Image = sprite.color,
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(math.clamp(at.X, 0, 1), math.clamp(at.Y, 0, 1)),
				Size = UDim2.fromOffset(STICKER_SIZE, STICKER_SIZE),
				Rotation = math.random(-14, 14),
				ZIndex = 4,
				Parent = stickerLayer,
			})
			sticker:SetAttribute("Sprite", name)
			local remove = Button.new({
				Name = "Remove",
				Text = "✕",
				Color = C.Red,
				Round = true,
				Size = UDim2.fromOffset(44, 44),
				TextSize = 20,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.9, 0.1),
				ZIndex = 6,
				Parent = sticker,
				OnClick = function()
					removeSticker(sticker)
				end,
			})
			remove.Root.Visible = false
			sticker.InputBegan:Connect(function(input: InputObject)
				local kind = input.UserInputType
				if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
					recentPointer[sticker] = os.clock()
					drag = { sticker = sticker, input = input, last = Vector2.new(input.Position.X, input.Position.Y), moved = 0 }
				end
			end)
			sticker.Activated:Connect(function()
				local pressed = recentPointer[sticker]
				if pressed and os.clock() - pressed < RECENT_POINTER then
					return -- the pointer path already handled this press (drag or tap)
				end
				selectSticker(if selected == sticker then nil else sticker)
			end)
			table.insert(stickers, sticker)
			Anim.popIn(sticker, 0.2)
			ctx:Sound("PhotoSticker")
		end

		local function onPointerMoved(input: InputObject)
			if not drag then
				return
			end
			local mouse = drag.input.UserInputType == Enum.UserInputType.MouseButton1
			if input ~= drag.input and not (mouse and input.UserInputType == Enum.UserInputType.MouseMovement) then
				return
			end
			local position = Vector2.new(input.Position.X, input.Position.Y)
			local delta = position - drag.last
			drag.last = position
			drag.moved += delta.Magnitude
			local size = root.AbsoluteSize
			if size.X > 0 and size.Y > 0 then
				local p = drag.sticker.Position
				local x = math.clamp(p.X.Scale + delta.X / size.X, 0, 1)
				local y = math.clamp(p.Y.Scale + delta.Y / size.Y, 0, 1)
				drag.sticker.Position = UDim2.fromScale(x, y)
			end
		end

		local function onPointerEnded(input: InputObject)
			if not drag then
				return
			end
			local mouse = drag.input.UserInputType == Enum.UserInputType.MouseButton1
			if input ~= drag.input and not (mouse and input.UserInputType == Enum.UserInputType.MouseButton1) then
				return
			end
			local ended = drag
			drag = nil
			if PhotoRig.IsTap(ended.moved, 0) then
				selectSticker(if selected == ended.sticker then nil else ended.sticker)
			end
		end

		local function refreshTray()
			for name, b in trayButtons do
				local stroke = b:FindFirstChild("Armed")
				if stroke then
					stroke.Enabled = armed == name
				end
			end
		end

		local function arm(name: string?)
			armed = name
			refreshTray()
			if name then
				flashHint(HINT_STICKER, 3)
			end
		end

		for i, name in stickerNames() do
			local b = New("ImageButton", {
				Name = name,
				Image = VfxSprites[name].color,
				AutoButtonColor = false,
				BackgroundColor3 = C.White,
				BackgroundTransparency = 0.85,
				Size = UDim2.fromOffset(52, 52),
				LayoutOrder = i,
				ZIndex = 11,
				Parent = tray,
			}, { Create.Corner(10) })
			local stroke = Create.Stroke(3, C.Gold, 0)
			stroke.Name = "Armed"
			stroke.Enabled = false
			stroke.Parent = b
			b.Activated:Connect(function()
				ctx:Sound("UITab")
				arm(if armed == name then nil else name)
			end)
			trayButtons[name] = b
		end
		Button.new({
			Name = "ClearStickers",
			Text = "Clear",
			Color = C.Gray,
			Size = UDim2.fromOffset(100, 52),
			TextSize = Theme.TextSize.Body,
			LayoutOrder = 100,
			ZIndex = 11,
			Parent = tray,
			OnClick = function()
				for i = #stickers, 1, -1 do
					removeSticker(stickers[i])
				end
			end,
		})

		-- Toolbar ---------------------------------------------------------------------------

		local function toolButton(props)
			props.TextSize = props.TextSize or Theme.TextSize.Body
			props.ZIndex = 11
			return Button.new(props)
		end

		local hideButton = toolButton({
			Name = "HideToolbar",
			Text = "👁",
			Color = C.Gray,
			Size = UDim2.fromOffset(52, 52),
			TextSize = 24,
			LayoutOrder = 1,
			Parent = corner,
		})
		toolButton({
			Name = "Exit",
			Text = "✕",
			Color = C.Red,
			Size = UDim2.fromOffset(52, 52),
			TextSize = 24,
			LayoutOrder = 2,
			Parent = corner,
			OnClick = function()
				ctx.Router:Close("PhotoMode")
			end,
		})
		local filterButton = toolButton({
			Name = "Filter",
			Text = "Natural",
			Icon = emoji("🎨"),
			Color = C.Purple,
			Size = UDim2.fromOffset(150, 56),
			LayoutOrder = 1,
			Parent = toolbar,
		})
		local frameButton = toolButton({
			Name = "Frame",
			Text = "No frame",
			Icon = emoji("🖼"),
			Color = C.Blue,
			Size = UDim2.fromOffset(170, 56),
			LayoutOrder = 2,
			Parent = toolbar,
		})
		local heart = VfxSprites.heart
		local stickerIcon = if heart and heart.color
			then New("ImageLabel", { BackgroundTransparency = 1, Image = heart.color, Size = UDim2.fromOffset(30, 30) })
			else emoji("⭐")
		local stickersButton = toolButton({
			Name = "StickersButton",
			Text = "Stickers",
			Icon = stickerIcon,
			Color = C.Pink,
			Size = UDim2.fromOffset(140, 56),
			LayoutOrder = 3,
			Parent = toolbar,
		})
		local poseButton = toolButton({
			Name = "Pose",
			Text = "Pose",
			Icon = emoji("🎉"),
			Color = C.Orange,
			Size = UDim2.fromOffset(110, 56),
			LayoutOrder = 4,
			Parent = toolbar,
		})
		local blurButton = toolButton({
			Name = "Blur",
			Text = "Blur on",
			Icon = emoji("◎"),
			Color = C.Green,
			Size = UDim2.fromOffset(130, 56),
			LayoutOrder = 5,
			Parent = toolbar,
		})
		local shootButton = toolButton({
			Name = "TakePhoto",
			Text = "Take photo",
			Icon = emoji("📷", 26),
			Color = C.Green,
			Size = UDim2.fromOffset(180, 62),
			LayoutOrder = 6,
			Parent = toolbar,
		})

		-- Photo card ------------------------------------------------------------------------

		local card = New("Frame", {
			Name = "PhotoCard",
			BackgroundColor3 = C.Panel,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(460, 380),
			Visible = false,
			ZIndex = 30,
			Parent = root,
		}, { Create.Corner(Theme.Radius.Panel), Create.Stroke(Theme.Stroke.Panel) })
		Create.Text({
			Name = "Title",
			Text = "Nice shot!",
			TextSize = Theme.TextSize.Title,
			Position = UDim2.fromOffset(0, 10),
			Size = UDim2.new(1, 0, 0, 40),
			ZIndex = 31,
			Parent = card,
		})
		local thumb = New("ImageLabel", {
			Name = "Photo",
			BackgroundColor3 = C.Dark,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 56),
			Size = UDim2.fromOffset(400, 225),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 31,
			Parent = card,
		}, { Create.Corner(10), Create.Stroke(3, C.White, 0) })
		local cardRow = New("Frame", {
			Name = "Buttons",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(1, -24, 0, 56),
			ZIndex = 31,
			Parent = card,
		}, { Create.List("x", 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })

		local function closeCard()
			if card.Visible then
				card.Visible = false
				Focus.remove(card)
			end
			cardId = nil
		end

		local saveButton = Button.new({
			Name = "Save",
			Text = "Save",
			Color = C.Green,
			Size = UDim2.fromOffset(130, 52),
			LayoutOrder = 1,
			ZIndex = 32,
			Parent = cardRow,
			OnClick = function()
				local id = cardId
				if photo and id then
					photo:Save(id, function(saved)
						if saved then
							ctx:Toast("Saved to your gallery!", "success")
						end
					end)
				end
			end,
		})
		local shareButton = Button.new({
			Name = "Share",
			Text = "Share",
			Color = C.Blue,
			Size = UDim2.fromOffset(130, 52),
			LayoutOrder = 2,
			ZIndex = 32,
			Parent = cardRow,
			OnClick = function()
				local id = cardId
				if photo and id then
					photo:Share(id, function() end)
				end
			end,
		})
		Button.new({
			Name = "Back",
			Text = "Back",
			Color = C.Gray,
			Size = UDim2.fromOffset(130, 52),
			LayoutOrder = 3,
			ZIndex = 32,
			Parent = cardRow,
			OnClick = closeCard,
		})

		local function showCard(contentId: string)
			local caps = photo and photo:Capabilities() or {}
			cardId = contentId
			thumb.Image = contentId
			saveButton.Root.Visible = caps.save == true
			shareButton.Root.Visible = caps.share == true
			card.Visible = true
			Anim.popIn(card, 0.2)
			Focus.push(card, closeCard)
		end

		-- State -----------------------------------------------------------------------------

		local function setChrome(visible: boolean)
			corner.Visible = visible
			toolbar.Visible = visible
			tray.Visible = visible and tray:GetAttribute("Open") == true
			if not visible then
				hint.Visible = false
				ring.Visible = false
			end
		end

		local function setHidden(on: boolean)
			hidden = on
			setChrome(not on)
			deselect()
			if photo then
				photo:SetClean(on)
			end
			if on then
				flashHint(nil)
			end
		end

		local function refreshButtons()
			if not photo then
				return
			end
			filterButton:SetText(photo:Filter().name)
			frameButton:SetText((FRAMES[frameIndex] or FRAMES[1]).name)
			blurButton.Root.Visible = photo:DepthAvailable()
			local on = photo:DepthOn()
			blurButton:SetText(if on then "Blur on" else "Blur off")
			blurButton:SetColor(if on then C.Green else C.Gray)
			shootButton.Root.Visible = photo:Capabilities().capture
		end

		local function stepFrame(step: number)
			frameIndex = PhotoRig.Cycle(#FRAMES, frameIndex, step)
			showFrame()
			refreshButtons()
		end

		local function stepFilter(step: number)
			if photo then
				photo:StepFilter(step)
				refreshButtons()
			end
		end

		local function pose()
			if not photo then
				return
			end
			if photo:Pose() > 0 then
				ctx:Sound("PhotoPose")
			else
				ctx:Toast("None of your monsters are close by", "info")
			end
		end

		local function flash()
			if photo and photo:ReducedMotion() then
				return
			end
			flashFrame.BackgroundTransparency = 0.05
			flashFrame.Visible = true
			local tween = Anim.tween(flashFrame, { BackgroundTransparency = 1 }, 0.35)
			tween.Completed:Connect(function()
				flashFrame.Visible = false
			end)
		end

		local function shoot()
			if shooting or not photo or not photo:Capabilities().capture then
				return
			end
			shooting = true
			local wasHidden = hidden
			deselect()
			setChrome(false)
			photo:SetClean(true)
			task.wait()
			task.wait() -- one rendered frame without the toolbar
			photo:Capture(function(contentId)
				shooting = false
				if not root.Visible then
					return -- photo mode closed while the capture ran
				end
				setChrome(not wasHidden)
				photo:SetClean(wasHidden)
				if contentId then
					ctx:Sound("PhotoShutter")
					flash()
					showCard(contentId)
				else
					ctx:Toast("Couldn't take the photo. Try again.", "error")
				end
			end)
		end

		local function toAbsolute(position: Vector2): Vector2
			-- Input positions sit below the top bar inset; this ScreenGui ignores the inset.
			return position + GuiService:GetGuiInset()
		end

		local function toScale(position: Vector2): Vector2
			local absolute = toAbsolute(position) - root.AbsolutePosition
			local size = root.AbsoluteSize
			if size.X <= 0 or size.Y <= 0 then
				return Vector2.new(0.5, 0.5)
			end
			return Vector2.new(absolute.X / size.X, absolute.Y / size.Y)
		end

		local function showRing(position: Vector2)
			local s = toScale(position)
			ring.Position = UDim2.fromScale(s.X, s.Y)
			ring.Visible = true
			Anim.popIn(ring, 0.15)
			ringToken += 1
			local token = ringToken
			task.delay(0.8, function()
				if ringToken == token then
					ring.Visible = false
				end
			end)
		end

		local function commandFromController(name: string)
			if name == "capture" then
				shoot()
			elseif name == "filter" then
				stepFilter(1)
			elseif name == "pose" then
				pose()
			elseif name == "framePrev" then
				stepFrame(-1)
			elseif name == "frameNext" then
				stepFrame(1)
			elseif name == "toggle" then
				setHidden(not hidden)
			elseif name == "sticker" then
				local names = stickerNames()
				local pick = armed or names[math.random(1, math.max(1, #names))]
				if pick then
					addSticker(pick, Vector2.new(0.5 + (math.random() - 0.5) * 0.3, 0.45 + (math.random() - 0.5) * 0.3))
				end
			elseif name == "unsticker" then
				if #stickers > 0 then
					removeSticker(stickers[#stickers])
				end
			end
		end

		-- Wiring ----------------------------------------------------------------------------

		hideButton:SetOnClick(function()
			setHidden(true)
			flashHint(HINT_HIDDEN, 1.5)
		end)
		filterButton:SetOnClick(function()
			stepFilter(1)
		end)
		frameButton:SetOnClick(function()
			stepFrame(1)
		end)
		stickersButton:SetOnClick(function()
			local open = tray:GetAttribute("Open") ~= true
			tray:SetAttribute("Open", open)
			tray.Visible = open
			if not open then
				arm(nil)
			end
		end)
		poseButton:SetOnClick(pose)
		blurButton:SetOnClick(function()
			if photo then
				photo:SetDepth(not photo:DepthOn())
				refreshButtons()
			end
		end)
		shootButton:SetOnClick(shoot)
		surface.Activated:Connect(function()
			if hidden then
				setHidden(false)
			end
		end)

		api = {
			Root = root,
			Surface = surface,
			Tap = function(position: Vector2): boolean
				if hidden then
					setHidden(false)
					return true
				end
				if selected then
					deselect()
				end
				if armed then
					addSticker(armed, toScale(position))
					return true
				end
				return false
			end,
			Focused = showRing,
			Command = commandFromController,
			Busy = function(): boolean
				return card.Visible
			end,
		}

		screen.Root = root

		function screen.Open()
			photo = ctx:GetController("PhotoMode")
			local name = ctx.Player.DisplayName ~= "" and ctx.Player.DisplayName or ctx.Player.Name
			caption.Text = string.format("%s's ranch", name)
			hidden = false
			setChrome(true)
			showFrame()
			if photo then
				photo:Begin(api)
				root:SetAttribute("GamepadLegend", if photo:Capabilities().capture then LEGEND_CAPTURE else LEGEND_PLAIN)
			end
			refreshButtons()
			for _, conn in conns do
				conn:Disconnect()
			end
			table.clear(conns)
			table.insert(conns, UserInputService.InputChanged:Connect(onPointerMoved))
			table.insert(conns, UserInputService.InputEnded:Connect(onPointerEnded))
			table.insert(conns, ctx.Store:Observe("profile.Settings", refreshButtons))
			local last = UserInputService:GetLastInputType()
			if not string.match(last.Name, "^Gamepad%d$") then
				local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
				flashHint(if touch then HINT_TOUCH else HINT_MOUSE, 5)
			end
		end

		function screen.Close()
			for _, conn in conns do
				conn:Disconnect()
			end
			table.clear(conns)
			closeCard()
			arm(nil)
			tray:SetAttribute("Open", false)
			tray.Visible = false
			drag = nil
			for i = #stickers, 1, -1 do
				removeSticker(stickers[i])
			end
			hidden = false
			shooting = false
			flashHint(nil)
			ring.Visible = false
			flashFrame.Visible = false
			if photo then
				photo:End()
			end
		end

		return screen
	end,
}
