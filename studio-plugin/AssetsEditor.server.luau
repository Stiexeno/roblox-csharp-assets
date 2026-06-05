-- Assets Editor — minimal Studio plugin for tagging Instances with
-- AssetKey: / AssetLabel: in a single panel. Mirrors the chrome
-- conventions of the Components editor so the two feel like one
-- toolset.
--
-- Selected Instance → one auto-key button (uses the Instance's Name,
-- conflicts shown inline) + a label dropdown listing every existing
-- AssetLabel:* in the place plus a "Create new…" entry that opens a
-- tiny text-input row. Existing tags are shown as removable chips.
--
-- Install: drop this file under ServerStorage or any non-replicated
-- container in Studio, right-click → Save as Local Plugin.

local plugin = plugin

local Selection = game:GetService("Selection")
local CollectionService = game:GetService("CollectionService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local StudioService = game:GetService("StudioService")

local KEY_PREFIX = "AssetKey:"
local LABEL_PREFIX = "AssetLabel:"

----------------------------------------------------------------------
-- Module-level state
----------------------------------------------------------------------

local refresh
local widget

----------------------------------------------------------------------
-- Theme
--
-- Same palette as the Components editor so the two plugins read as
-- one toolset. Dark-fixed values rather than Studio-theme-aware,
-- matching the established convention.
----------------------------------------------------------------------

local studio = settings().Studio

local function color(name, modifier)
	return studio.Theme:GetColor(
		Enum.StudioStyleGuideColor[name],
		modifier and Enum.StudioStyleGuideModifier[modifier] or Enum.StudioStyleGuideModifier.Default
	)
end

local FIELD_COLOR      = Color3.fromHex("#191A1F")
local HEADER_COLOR     = Color3.fromHex("#202227")
local SEPARATOR_COLOR  = Color3.fromHex("#202227")
local FIELD_HOVER      = HEADER_COLOR
local ADD_BUTTON_COLOR = Color3.fromHex("#335FFF")
local CHIP_REMOVE_HOVER = Color3.fromHex("#3D2A2A")

local function pageColor() return color("MainBackground") end

----------------------------------------------------------------------
-- UI helpers
----------------------------------------------------------------------

local function makeFrame(props)
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = props.color or FIELD_COLOR
	frame.BackgroundTransparency = props.transparency or 0
	frame.Size = props.size or UDim2.new(1, 0, 0, 22)
	frame.Position = props.position or UDim2.new()
	frame.Parent = props.parent
	return frame
end

local function makeLabel(props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = props.text or ""
	label.TextColor3 = props.color or color("MainText")
	label.TextXAlignment = props.align or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Font = props.font or Enum.Font.SourceSans
	label.TextSize = props.size or 14
	label.Size = props.frameSize or UDim2.new(1, 0, 1, 0)
	label.Position = props.position or UDim2.new()
	label.Parent = props.parent
	return label
end

local function roundCorners(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 4)
	corner.Parent = parent
	return corner
end

local function recordChange(name, fn)
	local id = ChangeHistoryService:TryBeginRecording(name)
	if not id then fn(); return end
	local ok, err = pcall(fn)
	if ok then
		ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
	else
		ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Cancel)
		warn("[Assets] " .. name .. " errored: " .. tostring(err))
	end
end

----------------------------------------------------------------------
-- Tag discovery
----------------------------------------------------------------------

-- Pulls every AssetKey: tag in the place. Used to detect duplicates
-- before assigning a new one.
local function allKeysInPlace()
	local keys = {}
	for _, tag in ipairs(CollectionService:GetAllTags()) do
		if string.sub(tag, 1, #KEY_PREFIX) == KEY_PREFIX then
			keys[string.sub(tag, #KEY_PREFIX + 1)] = true
		end
	end
	return keys
end

-- Pulls every AssetLabel: tag in the place. The label dropdown lists
-- these so the user can reuse instead of re-typing.
local function allLabelsInPlace()
	local labels = {}
	for _, tag in ipairs(CollectionService:GetAllTags()) do
		if string.sub(tag, 1, #LABEL_PREFIX) == LABEL_PREFIX then
			table.insert(labels, string.sub(tag, #LABEL_PREFIX + 1))
		end
	end
	table.sort(labels)
	return labels
end

-- Returns (currentKey, currentLabels[]) for the given Instance.
local function tagsOnInstance(instance)
	local key, labels = nil, {}
	for _, tag in ipairs(CollectionService:GetTags(instance)) do
		if string.sub(tag, 1, #KEY_PREFIX) == KEY_PREFIX then
			key = string.sub(tag, #KEY_PREFIX + 1)
		elseif string.sub(tag, 1, #LABEL_PREFIX) == LABEL_PREFIX then
			table.insert(labels, string.sub(tag, #LABEL_PREFIX + 1))
		end
	end
	table.sort(labels)
	return key, labels
end

----------------------------------------------------------------------
-- Section rendering
----------------------------------------------------------------------

local function buildSectionHeader(parent, label, layoutOrder)
	local header = makeFrame({
		parent = parent,
		color = HEADER_COLOR,
		size = UDim2.new(1, 0, 0, 22),
	})
	header.LayoutOrder = layoutOrder
	makeLabel({
		parent = header,
		text = label,
		color = color("MainText"),
		font = Enum.Font.SourceSansSemibold,
		size = 13,
		position = UDim2.new(0, 8, 0, 0),
		frameSize = UDim2.new(1, -16, 1, 0),
	})

	local bottomLine = Instance.new("Frame")
	bottomLine.BackgroundColor3 = SEPARATOR_COLOR
	bottomLine.BorderSizePixel = 0
	bottomLine.AnchorPoint = Vector2.new(0, 1)
	bottomLine.Size = UDim2.new(1, 0, 0, 1)
	bottomLine.Position = UDim2.new(0, 0, 1, 0)
	bottomLine.Parent = header
end

-- One row per tag (key or label) currently on the selected Instance.
-- Single chip layout: pill background, name on the left, ✕ remove on
-- the right. Click ✕ → recordChange + RemoveTag.
local function buildChip(parent, layoutOrder, displayText, onRemove)
	local row = makeFrame({
		parent = parent,
		color = FIELD_COLOR,
		size = UDim2.new(1, 0, 0, 22),
	})
	row.LayoutOrder = layoutOrder

	makeLabel({
		parent = row,
		text = displayText,
		color = color("MainText"),
		position = UDim2.new(0, 12, 0, 0),
		frameSize = UDim2.new(1, -32, 1, 0),
	})

	local removeBtn = Instance.new("TextButton")
	removeBtn.BackgroundTransparency = 1
	removeBtn.AutoButtonColor = false
	removeBtn.Text = "×"
	removeBtn.TextColor3 = color("DimmedText")
	removeBtn.Font = Enum.Font.SourceSans
	removeBtn.TextSize = 18
	removeBtn.AnchorPoint = Vector2.new(1, 0)
	removeBtn.Size = UDim2.fromOffset(20, 22)
	removeBtn.Position = UDim2.new(1, 0, 0, 0)
	removeBtn.Parent = row

	removeBtn.MouseEnter:Connect(function() removeBtn.TextColor3 = color("ErrorText") end)
	removeBtn.MouseLeave:Connect(function() removeBtn.TextColor3 = color("DimmedText") end)

	removeBtn.MouseButton1Click:Connect(onRemove)

	local bottomLine = Instance.new("Frame")
	bottomLine.BackgroundColor3 = SEPARATOR_COLOR
	bottomLine.BorderSizePixel = 0
	bottomLine.AnchorPoint = Vector2.new(0, 1)
	bottomLine.Size = UDim2.new(1, 0, 0, 1)
	bottomLine.Position = UDim2.new(0, 0, 1, 0)
	bottomLine.Parent = row
end

----------------------------------------------------------------------
-- Action buttons
----------------------------------------------------------------------

-- "+ Set Key" — prepends the Instance.Name as the AssetKey tag. If
-- another Instance already carries that key, a small inline text box
-- appears so the user can pick a non-conflicting name without leaving
-- the panel.
local function buildSetKeyButton(parent, instance)
	local btn = Instance.new("TextButton")
	btn.BackgroundColor3 = ADD_BUTTON_COLOR
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Text = "+ Set Key"
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.SourceSansSemibold
	btn.TextSize = 14
	btn.AutomaticSize = Enum.AutomaticSize.XY
	btn.Size = UDim2.new()
	btn.LayoutOrder = 100
	btn.Parent = parent
	roundCorners(btn, 5)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 20)
	pad.PaddingRight = UDim.new(0, 20)
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.Parent = btn

	btn.MouseButton1Click:Connect(function()
		local proposed = instance.Name
		local taken = allKeysInPlace()
		if taken[proposed] then
			warn(string.format(
				"[Assets] AssetKey '%s' is already in use. Rename the Instance " ..
				"or remove the existing key first.", proposed))
			return
		end
		recordChange("Set AssetKey " .. proposed, function()
			CollectionService:AddTag(instance, KEY_PREFIX .. proposed)
		end)
		refresh()
	end)
end

-- "+ Add Label ▾" — opens a small popup listing every existing
-- AssetLabel:* in the place plus a "Create new…" entry that swaps to
-- a text input. Clicking a label adds it to the selected Instance.
local function buildAddLabelButton(parent, instance)
	local btn = Instance.new("TextButton")
	btn.BackgroundColor3 = ADD_BUTTON_COLOR
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Text = "+ Add Label  ▾"
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.SourceSansSemibold
	btn.TextSize = 14
	btn.AutomaticSize = Enum.AutomaticSize.XY
	btn.Size = UDim2.new()
	btn.LayoutOrder = 101
	btn.Parent = parent
	roundCorners(btn, 5)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 20)
	pad.PaddingRight = UDim.new(0, 20)
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.Parent = btn

	local popup, backdrop

	local function closePopup()
		if popup then popup:Destroy(); popup = nil end
		if backdrop then backdrop:Destroy(); backdrop = nil end
	end

	-- Adds `label` to the selected Instance and closes the popup.
	-- Idempotent — duplicate tags are silently ignored by Roblox so a
	-- second click is harmless, but we still record the change so it
	-- shows in the undo stack.
	local function applyLabel(label)
		if label == "" then return end
		recordChange("Add AssetLabel " .. label, function()
			CollectionService:AddTag(instance, LABEL_PREFIX .. label)
		end)
		closePopup()
		refresh()
	end

	btn.MouseButton1Click:Connect(function()
		if popup then closePopup(); return end

		local btnPos = btn.AbsolutePosition
		local btnSize = btn.AbsoluteSize
		local widgetPos = widget.AbsolutePosition

		backdrop = Instance.new("TextButton")
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.BackgroundTransparency = 1
		backdrop.Text = ""
		backdrop.AutoButtonColor = false
		backdrop.ZIndex = 49
		backdrop.Parent = widget
		backdrop.MouseButton1Click:Connect(closePopup)

		popup = Instance.new("Frame")
		popup.BackgroundColor3 = FIELD_COLOR
		popup.BorderSizePixel = 0
		popup.ZIndex = 50
		popup.Size = UDim2.fromOffset(math.max(160, btnSize.X), 4)
		popup.AutomaticSize = Enum.AutomaticSize.Y
		popup.Position = UDim2.new(
			0, btnPos.X - widgetPos.X,
			0, btnPos.Y - widgetPos.Y + btnSize.Y + 4)
		popup.Parent = widget
		roundCorners(popup, 4)

		local stroke = Instance.new("UIStroke")
		stroke.Color = SEPARATOR_COLOR
		stroke.Thickness = 1
		stroke.Parent = popup

		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = popup

		local pad2 = Instance.new("UIPadding")
		pad2.PaddingTop = UDim.new(0, 4)
		pad2.PaddingBottom = UDim.new(0, 4)
		pad2.Parent = popup

		local labels = allLabelsInPlace()
		local order = 0

		if #labels == 0 then
			local row = Instance.new("TextLabel")
			row.BackgroundTransparency = 1
			row.Text = "  (no labels yet)"
			row.TextColor3 = color("DimmedText")
			row.Font = Enum.Font.SourceSans
			row.TextSize = 13
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.Size = UDim2.new(1, 0, 0, 22)
			row.ZIndex = 51
			row.Parent = popup
			row.LayoutOrder = order; order += 1
		else
			for _, label in ipairs(labels) do
				local rowBtn = Instance.new("TextButton")
				rowBtn.BackgroundColor3 = FIELD_COLOR
				rowBtn.BorderSizePixel = 0
				rowBtn.AutoButtonColor = false
				rowBtn.Text = "  " .. label
				rowBtn.TextColor3 = color("MainText")
				rowBtn.Font = Enum.Font.SourceSans
				rowBtn.TextSize = 14
				rowBtn.TextXAlignment = Enum.TextXAlignment.Left
				rowBtn.Size = UDim2.new(1, 0, 0, 22)
				rowBtn.ZIndex = 51
				rowBtn.Parent = popup
				rowBtn.LayoutOrder = order; order += 1

				rowBtn.MouseEnter:Connect(function() rowBtn.BackgroundColor3 = FIELD_HOVER end)
				rowBtn.MouseLeave:Connect(function() rowBtn.BackgroundColor3 = FIELD_COLOR end)
				rowBtn.MouseButton1Click:Connect(function() applyLabel(label) end)
			end
		end

		local separator = Instance.new("Frame")
		separator.BackgroundColor3 = SEPARATOR_COLOR
		separator.BorderSizePixel = 0
		separator.Size = UDim2.new(1, 0, 0, 1)
		separator.ZIndex = 51
		separator.Parent = popup
		separator.LayoutOrder = order; order += 1

		-- "Create new…" entry. Replaces the row's label with an inline
		-- text box on click; FocusLost commits the entered text as the
		-- new label.
		local newRow = Instance.new("TextButton")
		newRow.BackgroundColor3 = FIELD_COLOR
		newRow.BorderSizePixel = 0
		newRow.AutoButtonColor = false
		newRow.Text = "  + New label"
		newRow.TextColor3 = color("MainText")
		newRow.Font = Enum.Font.SourceSansSemibold
		newRow.TextSize = 14
		newRow.TextXAlignment = Enum.TextXAlignment.Left
		newRow.Size = UDim2.new(1, 0, 0, 22)
		newRow.ZIndex = 51
		newRow.Parent = popup
		newRow.LayoutOrder = order; order += 1

		newRow.MouseEnter:Connect(function() newRow.BackgroundColor3 = FIELD_HOVER end)
		newRow.MouseLeave:Connect(function() newRow.BackgroundColor3 = FIELD_COLOR end)

		newRow.MouseButton1Click:Connect(function()
			newRow.Text = ""
			newRow.Visible = false
			local input = Instance.new("TextBox")
			input.BackgroundColor3 = HEADER_COLOR
			input.BorderSizePixel = 0
			input.PlaceholderText = "new label"
			input.PlaceholderColor3 = color("DimmedText")
			input.Text = ""
			input.TextColor3 = color("MainText")
			input.Font = Enum.Font.SourceSans
			input.TextSize = 14
			input.TextXAlignment = Enum.TextXAlignment.Left
			input.Size = UDim2.new(1, -8, 0, 22)
			input.Position = UDim2.fromOffset(4, 0)
			input.ZIndex = 52
			input.ClearTextOnFocus = false
			input.LayoutOrder = order
			input.Parent = popup
			local inputPad = Instance.new("UIPadding")
			inputPad.PaddingLeft = UDim.new(0, 4)
			inputPad.Parent = input
			input:CaptureFocus()

			input.FocusLost:Connect(function(enterPressed)
				if not enterPressed then closePopup(); return end
				applyLabel(string.gsub(input.Text, "^%s+", ""):gsub("%s+$", ""))
			end)
		end)
	end)
end

----------------------------------------------------------------------
-- Top-level render
----------------------------------------------------------------------

local function buildInstanceRow(parent, instance)
	local row = makeFrame({
		parent = parent,
		color = HEADER_COLOR,
		size = UDim2.new(1, 0, 0, 26),
	})
	row.LayoutOrder = 0

	local info = StudioService:GetClassIcon(instance.ClassName)
	if info and info.Image then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = info.Image
		if info.ImageRectOffset then img.ImageRectOffset = info.ImageRectOffset end
		if info.ImageRectSize then img.ImageRectSize = info.ImageRectSize end
		img.AnchorPoint = Vector2.new(0, 0.5)
		img.Position = UDim2.new(0, 6, 0.5, 0)
		img.Size = UDim2.fromOffset(16, 16)
		img.Parent = row
	end

	makeLabel({
		parent = row,
		text = instance.Name,
		color = color("MainText"),
		font = Enum.Font.SourceSansSemibold,
		size = 14,
		position = UDim2.new(0, 28, 0, 0),
		frameSize = UDim2.new(1, -32, 1, 0),
	})

	local bottomLine = Instance.new("Frame")
	bottomLine.BackgroundColor3 = SEPARATOR_COLOR
	bottomLine.BorderSizePixel = 0
	bottomLine.AnchorPoint = Vector2.new(0, 1)
	bottomLine.Size = UDim2.new(1, 0, 0, 1)
	bottomLine.Position = UDim2.new(0, 0, 1, 0)
	bottomLine.Parent = row
end

local function build()
	for _, child in ipairs(widget:GetChildren()) do
		child:Destroy()
	end

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = pageColor()
	root.BorderSizePixel = 0
	root.Parent = widget

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = color("ScrollBar")
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 0)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local selected = Selection:Get()[1]
	if not selected then
		makeLabel({
			parent = scroll,
			text = "Select an Instance to tag it as an asset.",
			color = color("DimmedText"),
			align = Enum.TextXAlignment.Center,
			frameSize = UDim2.new(1, 0, 0, 40),
		})
		return
	end

	buildInstanceRow(scroll, selected)

	local currentKey, currentLabels = tagsOnInstance(selected)

	-- KEY section
	buildSectionHeader(scroll, "KEY", 1)
	if currentKey then
		buildChip(scroll, 2, KEY_PREFIX .. currentKey, function()
			recordChange("Remove AssetKey " .. currentKey, function()
				CollectionService:RemoveTag(selected, KEY_PREFIX .. currentKey)
			end)
			refresh()
		end)
	else
		local hostRow = makeFrame({
			parent = scroll,
			color = FIELD_COLOR,
			transparency = 1,
			size = UDim2.new(1, 0, 0, 36),
		})
		hostRow.BackgroundTransparency = 1
		hostRow.LayoutOrder = 2

		local centered = Instance.new("Frame")
		centered.BackgroundTransparency = 1
		centered.AutomaticSize = Enum.AutomaticSize.XY
		centered.AnchorPoint = Vector2.new(0.5, 0.5)
		centered.Position = UDim2.fromScale(0.5, 0.5)
		centered.Size = UDim2.new()
		centered.Parent = hostRow

		buildSetKeyButton(centered, selected)
	end

	-- LABELS section
	buildSectionHeader(scroll, "LABELS", 50)
	for i, label in ipairs(currentLabels) do
		buildChip(scroll, 50 + i, LABEL_PREFIX .. label, function()
			recordChange("Remove AssetLabel " .. label, function()
				CollectionService:RemoveTag(selected, LABEL_PREFIX .. label)
			end)
			refresh()
		end)
	end

	local labelButtonHost = makeFrame({
		parent = scroll,
		color = FIELD_COLOR,
		transparency = 1,
		size = UDim2.new(1, 0, 0, 36),
	})
	labelButtonHost.BackgroundTransparency = 1
	labelButtonHost.LayoutOrder = 200

	local centered = Instance.new("Frame")
	centered.BackgroundTransparency = 1
	centered.AutomaticSize = Enum.AutomaticSize.XY
	centered.AnchorPoint = Vector2.new(0.5, 0.5)
	centered.Position = UDim2.fromScale(0.5, 0.5)
	centered.Size = UDim2.new()
	centered.Parent = labelButtonHost

	buildAddLabelButton(centered, selected)
end

----------------------------------------------------------------------
-- Bootstrap
----------------------------------------------------------------------

local toolbar = plugin:CreateToolbar("Assets")
local toggle = toolbar:CreateButton("Assets Editor", "Tag the selected Instance with AssetKey / AssetLabel", "")

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false,
	false,
	300, 360,
	220, 240
)
widget = plugin:CreateDockWidgetPluginGui("AssetsEditor", widgetInfo)
widget.Title = "Assets"

toggle.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

refresh = function()
	if widget.Enabled then
		build()
	end
end

widget:GetPropertyChangedSignal("Enabled"):Connect(refresh)
Selection.SelectionChanged:Connect(refresh)
studio.ThemeChanged:Connect(refresh)
