-- Assets Editor Studio plugin.
--
-- Companion to the Assets runtime (plugins/Assets/runtime/AssetsService.luau).
-- Edits the two CollectionService tag prefixes the runtime uses:
--
--   AssetKey:<name>   — exactly one Instance per name; identifies an asset.
--   AssetLabel:<name> — many Instances per name; groups assets.
--
-- Same install pattern as ComponentEditor: Rojo mounts this file at
-- ServerStorage.Editors.AssetsEditor; right-click → Save as Local Plugin.
-- See ../README.md for full instructions.

local plugin = plugin

local Selection = game:GetService("Selection")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local KEY_PREFIX = "AssetKey:"
local LABEL_PREFIX = "AssetLabel:"

----------------------------------------------------------------------
-- Module-level state and forward declarations
--
-- Lua locals don't hoist; deeper closures that reference `refresh`
-- need it declared up here so they resolve to the assignment near the
-- bottom rather than a global lookup that silently fails.
----------------------------------------------------------------------

local refresh

----------------------------------------------------------------------
-- Theme — same helper shape as ComponentEditor so colors track Dark /
-- Light Studio theme switches automatically.
----------------------------------------------------------------------

local studio = settings().Studio

local function color(name, modifier)
	return studio.Theme:GetColor(
		Enum.StudioStyleGuideColor[name],
		modifier and Enum.StudioStyleGuideModifier[modifier] or Enum.StudioStyleGuideModifier.Default
	)
end

----------------------------------------------------------------------
-- UI factory helpers — small wrappers so build code reads like a
-- hierarchy of intent. Same shape as ComponentEditor's helpers.
----------------------------------------------------------------------

local function makeFrame(props)
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = props.color or color("MainBackground")
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
	label.TextTruncate = props.truncate or Enum.TextTruncate.None
	label.Parent = props.parent
	return label
end

local function makePadding(parent, left, right, top, bottom)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, left or 0)
	pad.PaddingRight = UDim.new(0, right or 0)
	pad.PaddingTop = UDim.new(0, top or 0)
	pad.PaddingBottom = UDim.new(0, bottom or 0)
	pad.Parent = parent
	return pad
end

local function makeStroke(parent, c)
	local stroke = Instance.new("UIStroke")
	stroke.Color = c or color("Border")
	stroke.Thickness = 1
	stroke.Parent = parent
	return stroke
end

local function makeSectionHeader(parent, text)
	local header = makeFrame({
		parent = parent,
		color = color("CategoryItem"),
		size = UDim2.new(1, 0, 0, 22),
	})
	makeStroke(header, color("Border"))
	makeLabel({
		parent = header,
		text = text,
		color = color("BrightText"),
		font = Enum.Font.SourceSansBold,
		frameSize = UDim2.new(1, -16, 1, 0),
		position = UDim2.new(0, 8, 0, 0),
	})
	return header
end

----------------------------------------------------------------------
-- Tag inspection helpers
----------------------------------------------------------------------

-- Returns the current AssetKey value on this Instance (the bare name,
-- without the prefix) or nil if none. Multiple AssetKey tags on a
-- single Instance shouldn't happen — the editor strips the old one
-- when setting a new one — but if it does we return the first.
local function currentAssetKey(instance)
	for _, tag in ipairs(CollectionService:GetTags(instance)) do
		if tag:sub(1, #KEY_PREFIX) == KEY_PREFIX then
			return tag:sub(#KEY_PREFIX + 1), tag
		end
	end
	return nil, nil
end

local function currentLabels(instance)
	local labels = {}
	for _, tag in ipairs(CollectionService:GetTags(instance)) do
		if tag:sub(1, #LABEL_PREFIX) == LABEL_PREFIX then
			table.insert(labels, tag:sub(#LABEL_PREFIX + 1))
		end
	end
	table.sort(labels)
	return labels
end

-- All AssetLabel:* tags known to the place. Used by the Add Label
-- picker and the Project Labels panel. Filters from GetAllTags so we
-- don't pollute the result with Component: or other tag namespaces.
local function allKnownLabels()
	local out = {}
	for _, tag in ipairs(CollectionService:GetAllTags()) do
		if tag:sub(1, #LABEL_PREFIX) == LABEL_PREFIX then
			table.insert(out, tag:sub(#LABEL_PREFIX + 1))
		end
	end
	table.sort(out)
	return out
end

-- Returns Instances that already hold AssetKey:<key>, excluding the
-- one currently being edited. Used to detect conflicts before
-- applying a new key.
local function findKeyConflicts(key, exclude)
	local conflicts = {}
	for _, inst in ipairs(CollectionService:GetTagged(KEY_PREFIX .. key)) do
		if inst ~= exclude then
			table.insert(conflicts, inst)
		end
	end
	return conflicts
end

----------------------------------------------------------------------
-- AssetKey field
--
-- Single TextBox bound to the AssetKey: tag on the selected Instance.
-- On FocusLost: if value is empty, strip any existing AssetKey tag.
-- Otherwise check for a conflict — if a different Instance already
-- holds the key, show an inline error + Jump button and revert. If
-- no conflict, swap the tag in place.
----------------------------------------------------------------------

local function buildAssetKeySection(parent, instance)
	makeSectionHeader(parent, "Asset Key")

	-- Row holding the textbox.
	local row = makeFrame({
		parent = parent,
		color = color("MainBackground"),
		size = UDim2.new(1, 0, 0, 28),
	})
	makePadding(row, 8, 8, 4, 4)

	local well = makeFrame({
		parent = row,
		color = color("InputFieldBackground"),
		size = UDim2.new(1, 0, 1, 0),
	})
	makeStroke(well, color("Border"))
	makePadding(well, 6, 6, 0, 0)

	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.PlaceholderText = "(no key)"
	box.PlaceholderColor3 = color("DimmedText")
	box.Text = currentAssetKey(instance) or ""
	box.TextColor3 = color("MainText")
	box.Font = Enum.Font.SourceSans
	box.TextSize = 14
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Size = UDim2.fromScale(1, 1)
	box.ClearTextOnFocus = false
	box.Parent = well

	-- Slot for the conflict warning row. Appears under the textbox
	-- when the typed key is already held by another Instance, with
	-- a Jump button that selects the offending Instance.
	local statusSlot = makeFrame({
		parent = parent,
		color = color("MainBackground"),
		size = UDim2.new(1, 0, 0, 0),
		transparency = 1,
	})
	statusSlot.BackgroundTransparency = 1

	local function clearStatus()
		for _, child in ipairs(statusSlot:GetChildren()) do
			child:Destroy()
		end
		statusSlot.Size = UDim2.new(1, 0, 0, 0)
	end

	local function showConflict(key, conflict)
		clearStatus()
		statusSlot.Size = UDim2.new(1, 0, 0, 44)

		local block = makeFrame({
			parent = statusSlot,
			color = color("MainBackground"),
			size = UDim2.fromScale(1, 1),
		})
		makePadding(block, 8, 8, 0, 4)

		makeLabel({
			parent = block,
			text = string.format('Key "%s" is already used by:', key),
			color = color("ErrorText"),
			frameSize = UDim2.new(1, 0, 0, 18),
		})

		local jump = Instance.new("TextButton")
		jump.BackgroundColor3 = color("Button")
		jump.BorderColor3 = color("Border")
		jump.BorderSizePixel = 1
		jump.Text = conflict:GetFullName()
		jump.TextColor3 = color("LinkText")
		jump.Font = Enum.Font.SourceSans
		jump.TextSize = 13
		jump.TextXAlignment = Enum.TextXAlignment.Left
		jump.TextTruncate = Enum.TextTruncate.AtEnd
		jump.Size = UDim2.new(1, 0, 0, 20)
		jump.Position = UDim2.new(0, 0, 0, 20)
		jump.AutoButtonColor = true
		jump.Parent = block
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 6)
		pad.PaddingRight = UDim.new(0, 6)
		pad.Parent = jump

		jump.MouseButton1Click:Connect(function()
			Selection:Set({ conflict })
		end)
	end

	box.FocusLost:Connect(function()
		local newKey = box.Text:match("^%s*(.-)%s*$") or ""
		local oldKey, oldTag = currentAssetKey(instance)

		-- No-op cases.
		if newKey == (oldKey or "") then
			clearStatus()
			box.Text = newKey
			return
		end

		-- Empty new value: strip the current tag if any.
		if newKey == "" then
			if oldTag then
				CollectionService:RemoveTag(instance, oldTag)
			end
			clearStatus()
			refresh()
			return
		end

		local conflicts = findKeyConflicts(newKey, instance)
		if #conflicts > 0 then
			-- Revert the textbox; the conflict block explains why.
			box.Text = oldKey or ""
			showConflict(newKey, conflicts[1])
			return
		end

		-- Safe to apply. Remove old tag first so the Instance never
		-- briefly holds two AssetKey tags.
		if oldTag then
			CollectionService:RemoveTag(instance, oldTag)
		end
		CollectionService:AddTag(instance, KEY_PREFIX .. newKey)
		clearStatus()
		refresh()
	end)
end

----------------------------------------------------------------------
-- Labels chip section
--
-- Removable chips for each AssetLabel:* tag on the selected
-- Instance, plus an "Add Label" button that opens a picker overlay
-- listing every label known to the place (minus already-attached
-- ones) and a "New label..." option.
----------------------------------------------------------------------

local pickerOverlay

local function closePicker()
	if pickerOverlay then
		pickerOverlay:Destroy()
		pickerOverlay = nil
	end
end

-- Picker overlay for "Add Label". Same visual pattern as the
-- ComponentEditor "Add Component" overlay so the install feels
-- consistent. Bottom row is "+ New label…" which swaps the result
-- list for a single textbox input.
local function openLabelPicker(host, instance)
	closePicker()

	local attachedSet = {}
	for _, name in ipairs(currentLabels(instance)) do
		attachedSet[name] = true
	end

	pickerOverlay = Instance.new("Frame")
	pickerOverlay.Size = UDim2.fromScale(1, 1)
	pickerOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	pickerOverlay.BackgroundTransparency = 0.4
	pickerOverlay.BorderSizePixel = 0
	pickerOverlay.ZIndex = 10
	pickerOverlay.Parent = host

	local dim = Instance.new("TextButton")
	dim.BackgroundTransparency = 1
	dim.Text = ""
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 10
	dim.Parent = pickerOverlay
	dim.MouseButton1Click:Connect(closePicker)

	local card = makeFrame({
		parent = pickerOverlay,
		color = color("MainBackground"),
		size = UDim2.new(1, -24, 0, 240),
		position = UDim2.new(0, 12, 1, -252),
	})
	card.ZIndex = 11
	makeStroke(card, color("Border"))

	local header = makeFrame({
		parent = card,
		color = color("CategoryItem"),
		size = UDim2.new(1, 0, 0, 24),
	})
	header.ZIndex = 11
	makeLabel({
		parent = header,
		text = "Add Label",
		color = color("BrightText"),
		font = Enum.Font.SourceSansBold,
		frameSize = UDim2.new(1, -12, 1, 0),
		position = UDim2.new(0, 8, 0, 0),
	}).ZIndex = 11

	local searchHost = makeFrame({
		parent = card,
		color = color("InputFieldBackground"),
		size = UDim2.new(1, -16, 0, 24),
		position = UDim2.new(0, 8, 0, 30),
	})
	searchHost.ZIndex = 11
	makeStroke(searchHost, color("Border"))
	makePadding(searchHost, 6, 6, 0, 0)

	local searchBox = Instance.new("TextBox")
	searchBox.BackgroundTransparency = 1
	searchBox.PlaceholderText = "Search or type new label name…"
	searchBox.PlaceholderColor3 = color("DimmedText")
	searchBox.Text = ""
	searchBox.TextColor3 = color("MainText")
	searchBox.Font = Enum.Font.SourceSans
	searchBox.TextSize = 14
	searchBox.TextXAlignment = Enum.TextXAlignment.Left
	searchBox.Size = UDim2.fromScale(1, 1)
	searchBox.ZIndex = 11
	searchBox.Parent = searchHost
	searchBox.ClearTextOnFocus = false

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -16, 1, -68)
	list.Position = UDim2.new(0, 8, 0, 60)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 4
	list.ZIndex = 11
	list.Parent = card

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 2)
	listLayout.Parent = list

	local function applyLabel(name)
		name = name:match("^%s*(.-)%s*$") or ""
		if name == "" then return end
		CollectionService:AddTag(instance, LABEL_PREFIX .. name)
		closePicker()
		refresh()
	end

	local function makePickerRow(text, textColor, onClick)
		local row = Instance.new("TextButton")
		row.BackgroundColor3 = color("Button")
		row.BorderColor3 = color("Border")
		row.BorderSizePixel = 1
		row.Text = text
		row.TextColor3 = textColor or color("ButtonText")
		row.Font = Enum.Font.SourceSans
		row.TextSize = 14
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Size = UDim2.new(1, 0, 0, 22)
		row.AutoButtonColor = true
		row.ZIndex = 11
		row.Parent = list
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.Parent = row
		row.MouseButton1Click:Connect(onClick)
		return row
	end

	local function renderList()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("TextButton") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end

		local query = searchBox.Text:match("^%s*(.-)%s*$") or ""
		local lowered = query:lower()

		-- Filtered existing labels first.
		local matches = {}
		for _, name in ipairs(allKnownLabels()) do
			if not attachedSet[name] then
				if lowered == "" or name:lower():find(lowered, 1, true) then
					table.insert(matches, name)
				end
			end
		end
		for _, name in ipairs(matches) do
			makePickerRow(name, color("ButtonText"), function()
				applyLabel(name)
			end)
		end

		-- "Create new" row when the search box has a value that's not
		-- already an exact-match label. Lets the user mint a brand-new
		-- label without leaving the picker.
		if query ~= "" then
			local exact = false
			for _, name in ipairs(matches) do
				if name == query then exact = true; break end
			end
			if not exact and not attachedSet[query] then
				makePickerRow(
					string.format('+ Create new label "%s"', query),
					color("LinkText"),
					function() applyLabel(query) end
				)
			end
		end

		if #matches == 0 and query == "" then
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.Text = "(no labels in this place yet — type a name to create one)"
			empty.TextColor3 = color("DimmedText")
			empty.Font = Enum.Font.SourceSans
			empty.TextSize = 14
			empty.TextXAlignment = Enum.TextXAlignment.Left
			empty.Size = UDim2.new(1, 0, 0, 22)
			empty.ZIndex = 11
			empty.Parent = list
		end
	end

	-- Enter key in the search box commits the typed value as a new
	-- label — quickest path for the common case of "I know exactly
	-- what I want to call it".
	searchBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			applyLabel(searchBox.Text)
		end
	end)
	searchBox:GetPropertyChangedSignal("Text"):Connect(renderList)
	searchBox:CaptureFocus()
	renderList()
end

local function buildLabelsSection(parent, instance, host)
	makeSectionHeader(parent, "Labels")

	local labels = currentLabels(instance)

	-- Chips row. UIListLayout in horizontal mode + auto sizing on the
	-- container lets chips wrap naturally as the dock is resized.
	local chipBlock = makeFrame({
		parent = parent,
		color = color("MainBackground"),
		size = UDim2.new(1, 0, 0, 0),
	})
	chipBlock.AutomaticSize = Enum.AutomaticSize.Y
	makePadding(chipBlock, 8, 8, 4, 4)

	local chips = Instance.new("Frame")
	chips.BackgroundTransparency = 1
	chips.Size = UDim2.new(1, 0, 0, 0)
	chips.AutomaticSize = Enum.AutomaticSize.Y
	chips.Parent = chipBlock

	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Wraps = true
	chipLayout.Padding = UDim.new(0, 4)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chips

	if #labels == 0 then
		makeLabel({
			parent = chips,
			text = "(no labels)",
			color = color("DimmedText"),
			frameSize = UDim2.new(1, 0, 0, 20),
		})
	else
		for i, name in ipairs(labels) do
			local chip = Instance.new("Frame")
			chip.BackgroundColor3 = color("Button")
			chip.BorderColor3 = color("Border")
			chip.BorderSizePixel = 1
			chip.AutomaticSize = Enum.AutomaticSize.X
			chip.Size = UDim2.new(0, 0, 0, 20)
			chip.LayoutOrder = i
			chip.Parent = chips
			makePadding(chip, 8, 4, 0, 0)

			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.AutomaticSize = Enum.AutomaticSize.X
			row.Size = UDim2.new(0, 0, 1, 0)
			row.Parent = chip

			local rowLayout = Instance.new("UIListLayout")
			rowLayout.FillDirection = Enum.FillDirection.Horizontal
			rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			rowLayout.Padding = UDim.new(0, 4)
			rowLayout.Parent = row

			local nameLabel = Instance.new("TextLabel")
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = name
			nameLabel.TextColor3 = color("ButtonText")
			nameLabel.Font = Enum.Font.SourceSans
			nameLabel.TextSize = 14
			nameLabel.AutomaticSize = Enum.AutomaticSize.X
			nameLabel.Size = UDim2.new(0, 0, 1, 0)
			nameLabel.Parent = row

			local removeButton = Instance.new("TextButton")
			removeButton.BackgroundTransparency = 1
			removeButton.Text = "×"
			removeButton.TextColor3 = color("DimmedText")
			removeButton.Font = Enum.Font.SourceSansBold
			removeButton.TextSize = 16
			removeButton.Size = UDim2.new(0, 14, 0, 16)
			removeButton.AutoButtonColor = true
			removeButton.Parent = row

			removeButton.MouseButton1Click:Connect(function()
				CollectionService:RemoveTag(instance, LABEL_PREFIX .. name)
				refresh()
			end)
		end
	end

	-- Add button row underneath the chips.
	local addRow = makeFrame({
		parent = parent,
		color = color("MainBackground"),
		size = UDim2.new(1, 0, 0, 28),
	})
	makePadding(addRow, 8, 8, 4, 4)

	local addButton = Instance.new("TextButton")
	addButton.BackgroundColor3 = color("Button")
	addButton.BorderColor3 = color("Border")
	addButton.BorderSizePixel = 1
	addButton.Text = "+ Add Label"
	addButton.TextColor3 = color("ButtonText")
	addButton.Font = Enum.Font.SourceSans
	addButton.TextSize = 14
	addButton.Size = UDim2.fromScale(1, 1)
	addButton.AutoButtonColor = true
	addButton.Parent = addRow

	addButton.MouseButton1Click:Connect(function()
		openLabelPicker(host, instance)
	end)
end

----------------------------------------------------------------------
-- Project Labels panel
--
-- Read-only live registry of every AssetLabel in the place with its
-- usage count. Helps the user see at a glance what label namespace
-- already exists without having to scroll through tags in the
-- Collection editor.
----------------------------------------------------------------------

local function buildProjectLabelsSection(parent)
	makeSectionHeader(parent, "Project labels")

	local labels = allKnownLabels()
	if #labels == 0 then
		local row = makeFrame({
			parent = parent,
			color = color("MainBackground"),
			size = UDim2.new(1, 0, 0, 22),
		})
		makePadding(row, 12, 8, 0, 0)
		makeLabel({
			parent = row,
			text = "(none defined yet)",
			color = color("DimmedText"),
		})
		return
	end

	for i, name in ipairs(labels) do
		local count = #CollectionService:GetTagged(LABEL_PREFIX .. name)
		local row = makeFrame({
			parent = parent,
			color = color("MainBackground"),
			size = UDim2.new(1, 0, 0, 20),
		})
		row.LayoutOrder = i
		makePadding(row, 12, 8, 0, 0)

		makeLabel({
			parent = row,
			text = "• " .. name,
			color = color("MainText"),
			frameSize = UDim2.new(1, -60, 1, 0),
			truncate = Enum.TextTruncate.AtEnd,
		})
		makeLabel({
			parent = row,
			text = "(" .. count .. ")",
			color = color("DimmedText"),
			align = Enum.TextXAlignment.Right,
			frameSize = UDim2.new(0, 50, 1, 0),
			position = UDim2.new(1, -54, 0, 0),
		})
	end
end

----------------------------------------------------------------------
-- Top-level render
----------------------------------------------------------------------

local widget

local function build()
	closePicker()
	for _, child in ipairs(widget:GetChildren()) do
		child:Destroy()
	end

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = color("MainBackground")
	root.BorderSizePixel = 0
	root.Parent = widget

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 0)
	layout.Parent = scroll

	local selected = Selection:Get()[1]
	if selected then
		-- Selection path header so the user can confirm what they're
		-- editing without looking back at the Explorer.
		local pathBlock = makeFrame({
			parent = scroll,
			color = color("MainBackground"),
			size = UDim2.new(1, 0, 0, 24),
		})
		makePadding(pathBlock, 8, 8, 4, 0)
		makeLabel({
			parent = pathBlock,
			text = "Selected: " .. selected:GetFullName(),
			color = color("DimmedText"),
			size = 13,
			truncate = Enum.TextTruncate.AtEnd,
		})

		buildAssetKeySection(scroll, selected)
		buildLabelsSection(scroll, selected, root)
	else
		local hint = makeFrame({
			parent = scroll,
			color = color("MainBackground"),
			size = UDim2.new(1, 0, 0, 40),
		})
		makePadding(hint, 12, 12, 12, 0)
		makeLabel({
			parent = hint,
			text = "Select an Instance to edit its asset tags.",
			color = color("DimmedText"),
		})
	end

	-- Visual separator before the project-wide registry.
	local spacer = makeFrame({
		parent = scroll,
		color = color("MainBackground"),
		size = UDim2.new(1, 0, 0, 12),
		transparency = 1,
	})
	spacer.BackgroundTransparency = 1

	buildProjectLabelsSection(scroll)
end

----------------------------------------------------------------------
-- Bootstrap
----------------------------------------------------------------------

local toolbar = plugin:CreateToolbar("Assets")
local toggle = toolbar:CreateButton(
	"Assets Editor",
	"Toggle the asset tag inspector",
	""
)

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false, -- not initially enabled
	false, -- don't override saved state
	320, 440,
	240, 320
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

-- CollectionService global tag signals don't fire per-Instance — they
-- fire only when a tag *name* first appears or last disappears
-- anywhere in the place. That's still useful here for keeping the
-- Project Labels panel honest when a brand-new label is minted from
-- outside this plugin or when the last user of a label is untagged.
-- Per-Instance edits we drive ourselves trigger refresh() inline.
CollectionService.TagAdded:Connect(function(tag)
	if tag:sub(1, #LABEL_PREFIX) == LABEL_PREFIX
		or tag:sub(1, #KEY_PREFIX) == KEY_PREFIX then
		refresh()
	end
end)
CollectionService.TagRemoved:Connect(function(tag)
	if tag:sub(1, #LABEL_PREFIX) == LABEL_PREFIX
		or tag:sub(1, #KEY_PREFIX) == KEY_PREFIX then
		refresh()
	end
end)

studio.ThemeChanged:Connect(refresh)

-- ESC dismisses the Add Label overlay if it's up.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape and pickerOverlay then
		closePicker()
	end
end)

refresh()
