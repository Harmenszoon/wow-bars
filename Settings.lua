local addon, Bars = ...
local manager, dialog = EditModeManagerFrame, EditModeSystemSettingsDialog
local ACTION_BAR = Enum.EditModeSystem.ActionBar
local DEFAULT = "blizzard"
local styles = { DEFAULT, "clipped", "square", "trimmed", "outline", "trimmedOutline" }
local labels = {
	blizzard = "Blizzard",
	clipped = "Borderless (clipped corners)",
	square = "Borderless (square)",
	trimmed = "Trimmed square",
	outline = "Thin outline",
	trimmedOutline = "Trimmed square with outline",
}

local controls, borderRow, opacityRow, sizeRow, backgroundRow, hideRow
local controlsMode, controlsAnchor, nativeSizeRow, coveredSlider
local ready, deferred
local draft, editLayout, saving, copySource
local names, empty = {}, {}

local function database(layout)
	if layout and layout.layoutType == Enum.EditModeLayoutType.Account then return BarsLayouts end
	if layout and layout.layoutType == Enum.EditModeLayoutType.Character then return BarsCharacterLayouts end
end

local function saved(layout)
	local db = database(layout)
	local values = db and db[layout.layoutName]
	return type(values) == "table" and values or empty
end

local function choices(layout)
	return layout == editLayout and draft or saved(layout)
end

local function barOptions(layout, index)
	local options = layout[index]
	return type(options) == "table" and options or nil
end

local function percent(value)
	return type(value) == "number" and value >= 0 and value <= 100 and math.floor(value / 5 + 0.5) * 5 or 100
end

local function valueFor(layout, index, key)
	local options = barOptions(choices(layout), index)
	local value = options and options[key]
	if key == "opacity" then return percent(value) end
	if key == "size" then
		if type(value) == "number" and value >= 25 and value <= 300 then return math.floor(value / 5 + 0.5) * 5 end
		return nil
	end
	if key == "hideBackground" or key == "hidden" then return value == true end
	return labels[value] and value or DEFAULT
end

local function refreshPreview()
	local bar = dialog.attachedToSystem
	if Bars.BarKey(bar) and opacityRow:IsVisible() then
		local widget = opacityRow.Slider
		if widget.InteractionFlags:IsAnySet() or widget.Back:IsMouseMotionFocus() or widget.Forward:IsMouseMotionFocus() then
			Bars.PreviewOpacity(bar)
			return
		end
	end
	Bars.PreviewOpacity(nil)
end

local function syncSlider(row, value)
	local slider = row.Slider.Slider
	if slider:GetValue() ~= value then
		row.syncing = true
		slider:SetValue(value)
		row.syncing = nil
	end
end

local function refreshControls()
	local bar = dialog.attachedToSystem
	if not controls or not controls:IsShown() or not bar then return end
	local layout = manager:GetActiveLayoutInfo()
	local key, option = Bars.VisibilityOption(bar)
	if key then
		local hidden
		if option then hidden = bar:GetSettingValue(option.setting) == option.modes.Hidden
		else hidden = valueFor(layout, key, "hidden") end
		hideRow.Button:SetChecked(hidden)
	end
	local index = Bars.BarKey(bar)
	if not index then return end
	if bar.system == ACTION_BAR then
		if borderRow.bar ~= bar or borderRow.style ~= valueFor(layout, index, "border") then
			borderRow.Dropdown:GenerateMenu()
		end
	elseif sizeRow then
		syncSlider(sizeRow, valueFor(layout, index, "size") or Bars.NativeSize(bar))
		backgroundRow.Button:SetChecked(valueFor(layout, index, "hideBackground"))
	end
	syncSlider(opacityRow, valueFor(layout, index, "opacity"))
	refreshPreview()
end

local function refresh()
	if not ready or not manager:IsInitialized() then return end
	if InCombatLockdown() then
		if not deferred then
			deferred = true
			EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_REGEN_ENABLED", function()
				deferred = nil
				refresh()
			end)
		end
		return
	end
	local layout = manager:GetActiveLayoutInfo()
	for _, bar in ipairs(manager.registeredSystemFrames) do
		local index = Bars.BarKey(bar)
		if index then
			if bar.system == ACTION_BAR then
				if not Bars.ApplyBorder(bar, valueFor(layout, index, "border")) then Bars.RefreshBorder(bar) end
			else
				Bars.ApplySize(bar, valueFor(layout, index, "size"))
				Bars.ApplyBackground(bar, valueFor(layout, index, "hideBackground"))
			end
			Bars.ApplyOpacity(bar, valueFor(layout, index, "opacity"))
		end
	end
	Bars.RefreshVisibility(choices(layout))
	refreshControls()
end

local defaults = { border = DEFAULT, opacity = 100, hideBackground = false, hidden = false }

function Bars.SelectSetting(bar, key, value)
	local layout = manager:GetActiveLayoutInfo()
	local index, visibility
	if key == "hidden" then index, visibility = Bars.VisibilityOption(bar)
	else index = Bars.BarKey(bar) end
	if not index or not layout or InCombatLockdown() then return end
	if key == "opacity" then value = percent(value) end
	local current = valueFor(layout, index, key)
	if visibility then current = bar:GetSettingValue(visibility.setting) == visibility.modes.Hidden end
	if key == "size" then current = current or Bars.NativeSize(bar) end
	if value == current then return end
	if layout ~= editLayout then
		editLayout, draft = layout, CopyTable(saved(layout))
	end
	local options = barOptions(draft, index) or {}
	local stored, nativeSetting, nativeValue = value
	if key == "size" then
		local setting = Bars.SizeSetting(bar)
		local info = bar.settingDisplayInfoMap[setting]
		if info and bar:HasSetting(setting) and value >= info.minValue and value <= info.maxValue then
			nativeSetting, nativeValue, stored = setting, value, nil
		elseif value == Bars.NativeSize(bar) then
			stored = nil
		end
	elseif visibility then
		nativeSetting, stored = visibility.setting, nil
		nativeValue = Bars.NativeVisibilityValue(bar, visibility, options, value)
	elseif value == defaults[key] then
		stored = nil
	end
	options[key] = stored
	draft[index] = next(options) and options or nil
	if nativeSetting then manager:OnSystemSettingChange(bar, nativeSetting, nativeValue) end
	if key == "size" then
		Bars.ApplySize(bar, options.size)
	elseif key == "hideBackground" then Bars.ApplyBackground(bar, value)
	elseif key == "border" then Bars.ApplyBorder(bar, value)
	elseif key == "opacity" then Bars.ApplyOpacity(bar, value) end
	if not bar:HasActiveChanges() then bar:SetHasActiveChanges(true) end
	refreshControls()
end

local function makeCheckbox(group, index, label, key)
	local row = CreateFrame("Frame", nil, group, "EditModeSettingCheckboxTemplate")
	row.layoutIndex = index
	row.Label:SetText(label)
	row.OnCheckButtonClick = function()
		if row:IsVisible() then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			Bars.SelectSetting(dialog.attachedToSystem, key, row.Button:GetChecked() == true)
		end
	end
	return row
end

local function makeSlider(group, index, label, key, low, high)
	local row = CreateFrame("Frame", nil, group, "EditModeSettingSliderTemplate")
	row.layoutIndex = index
	row.Label:SetText(label)
	row.cbrHandles:Unregister()
	local widget = row.Slider
	widget.Slider:SetObeyStepOnDrag(true)
	widget:Init(100, low, high, (high - low) / 5, {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(value) return ("%d%%"):format(value + 0.5) end,
	})
	widget:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		local bar = dialog.attachedToSystem
		if not row.syncing and row:IsVisible() and Bars.BarKey(bar) then Bars.SelectSetting(bar, key, value) end
	end, row)
	return row
end

local function uncoverSizeRow()
	if coveredSlider then coveredSlider:Show() end
	coveredSlider = nil
end

local function makeControls()
	-- The stock dialog excludes its border from layout. Our rows can follow
	-- the dialog here without being enumerated by Blizzard's layout code.
	local group = CreateFrame("Frame", nil, dialog.Border, "VerticalLayoutFrame")
	group:Hide()
	group.spacing = dialog.Settings.spacing
	group:HookScript("OnHide", uncoverSizeRow)

	local frame = CreateFrame("Frame", nil, group, "EditModeSettingDropdownTemplate")
	borderRow = frame
	frame.layoutIndex = 1
	frame.Label:SetText("Icon Border")
	frame.Dropdown:SetupMenu(function(_, menu)
		local bar = dialog.attachedToSystem
		if not bar or bar.system ~= ACTION_BAR then return end
		frame.bar, frame.style = bar, valueFor(manager:GetActiveLayoutInfo(), bar.systemIndex, "border")
		local function selected(style) return valueFor(manager:GetActiveLayoutInfo(), bar.systemIndex, "border") == style end
		local function selectStyle(style)
			if dialog.attachedToSystem == bar then Bars.SelectSetting(bar, "border", style) end
		end
		for _, style in ipairs(styles) do menu:CreateRadio(labels[style], selected, selectStyle, style) end
	end)
	frame:Show()

	opacityRow = makeSlider(group, 2, "Idle Opacity", "opacity", 0, 100)
	local widget = opacityRow.Slider
	-- The track and steppers have separate mouse focus. Read it after both
	-- leave and enter fire so crossing between them keeps the same preview.
	local previewQueued
	local function previewAfterInput()
		previewQueued = nil
		refreshPreview()
	end
	local function interactionChanged()
		if not previewQueued then
			previewQueued = true
			RunNextFrame(previewAfterInput)
		end
	end
	widget:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnInteractStart, interactionChanged, opacityRow)
	widget:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnInteractEnd, interactionChanged, opacityRow)
	for _, stepper in ipairs({ widget.Back, widget.Forward }) do
		stepper:HookScript("OnEnter", interactionChanged)
		stepper:HookScript("OnLeave", interactionChanged)
	end
	opacityRow:HookScript("OnHide", function() Bars.PreviewOpacity(nil) end)
	opacityRow:Show()
	hideRow = makeCheckbox(group, 4, "Hide in Gameplay", "hidden")
	hideRow:Show()
	return group
end

local function makeUtilityControls()
	sizeRow = makeSlider(controls, 1, HUD_EDIT_MODE_SETTING_BAGS_SIZE, "size", 25, 300)
	backgroundRow = makeCheckbox(controls, 3, "Hide Background", "hideBackground")
end

-- Borrow the stock Size row's location. Its range is encoded by Blizzard
-- as an unsigned index. Our own slider can offer smaller sizes safely.
local function placeSizeRow(bar)
	local native
	if bar then
		local setting = Bars.SizeSetting(bar)
		for row in dialog.pools:EnumerateActiveByTemplate("EditModeSettingSliderTemplate") do
			if row.setting == setting then native = row break end
		end
	end
	local changed = native ~= nativeSizeRow
	if changed then
		uncoverSizeRow()
		nativeSizeRow = native
		sizeRow.ignoreInLayout = native ~= nil
		sizeRow.Label:SetShown(not native)
		sizeRow:ClearAllPoints()
		if native then sizeRow:SetPoint("TOPLEFT", native, "TOPLEFT") end
	end
	if native and native.Slider:IsShown() then
		coveredSlider = native.Slider
		coveredSlider:Hide()
	end
	return changed
end

hooksecurefunc(dialog, "UpdateSettings", function(_, bar)
	if bar ~= dialog.attachedToSystem then return end
	local mode
	if Bars.BarKey(bar) then mode = bar.system == ACTION_BAR and "action" or "utility"
	elseif Bars.VisibilityOption(bar) then mode = "hud" end
	if mode and not controls then controls = makeControls() end
	if not controls then return end
	local utility = mode == "utility"
	if utility and not sizeRow then makeUtilityControls() end
	local moved = sizeRow and placeSizeRow(utility and bar or nil)
	local changed = controlsMode ~= mode
	if changed then
		controlsMode = mode
		borderRow:SetShown(mode == "action")
		opacityRow:SetShown(mode == "action" or utility)
		if sizeRow then
			sizeRow:SetShown(utility)
			backgroundRow:SetShown(utility)
		end
		controls:SetShown(mode ~= nil)
	end
	if mode then
		-- UpdateSettings just anchored the stock buttons. Reserve the rows'
		-- height before Blizzard measures the dialog in UpdateSizeAndAnchors.
		local buttons = dialog.Buttons
		local point, relative, relativePoint, x, y = buttons:GetPoint(1)
		if relative ~= controlsAnchor then
			controlsAnchor = relative
			controls:ClearAllPoints()
			controls:SetPoint(point, relative, relativePoint, x, dialog.Settings:IsShown() and -controls.spacing or y)
		end
		if changed or moved then controls:Layout() end
		buttons:SetPoint(point, relative, relativePoint, x, y - controls:GetHeight() - controls.spacing)
		refreshControls()
	end
end)

local function layoutNames()
	local result = {}
	for _, layout in ipairs(manager:GetLayouts()) do result[layout] = layout.layoutName end
	return result
end

-- On exit Blizzard reloads the layout before rebuilding the party frames.
-- Capture layout changes now and apply their appearance after that work.
local refreshQueued
function Bars.QueueRefresh()
	if refreshQueued then return end
	refreshQueued = true
	RunNextFrame(function()
		refreshQueued = nil
		refresh()
	end)
end

local function layoutUpdated()
	draft, editLayout = nil, nil
	names = layoutNames()
	Bars.QueueRefresh()
end

hooksecurefunc(manager, "UpdateLayoutInfo", layoutUpdated)
hooksecurefunc(manager, "RevertSystemChanges", function(_, bar)
	local index = Bars.VisibilityOption(bar) or Bars.BarKey(bar)
	if not index then return end
	if draft then
		local original = barOptions(saved(editLayout), index)
		draft[index] = original and CopyTable(original) or nil
	end
	Bars.QueueRefresh()
end)
hooksecurefunc(manager, "OnSystemSettingChange", function(_, bar, setting, value)
	if bar.system == ACTION_BAR and setting == Enum.EditModeActionBarSetting.IconSize then
		if InCombatLockdown() then refresh() else Bars.RefreshBorder(bar) end
	end
	-- Choosing another mode in Blizzard's dropdown supersedes our remembered mode.
	local index, visibility = Bars.VisibilityOption(bar)
	if visibility and setting == visibility.setting and value ~= visibility.modes.Hidden and manager:IsEditModeActive() then
		local layout = manager:GetActiveLayoutInfo()
		local options = barOptions(choices(layout), index)
		if options and options.previousVisibility ~= nil then
			if layout ~= editLayout then editLayout, draft = layout, CopyTable(saved(layout)) end
			draft[index].previousVisibility = nil
			if not next(draft[index]) then draft[index] = nil end
		end
	end
end)

-- A save can reload all layout tables. Capture their identities before the
-- client call and commit on Blizzard's save notification. Indices can shift.
hooksecurefunc(manager, "PrepareSystemsForSave", function()
	local current = layoutNames()
	saving = { before = names, after = current, layout = editLayout, draft = draft }
	names = current
end)
EventRegistry:RegisterCallback("EditMode.SavedLayouts", function()
	if not saving then return end
	for layout, old in pairs(saving.before) do
		local name = saving.after[layout]
		local db = database(layout)
		if db and old ~= name then
			if name then db[name] = db[old] end
			db[old] = nil
		end
	end
	local db, name = database(saving.layout), saving.after[saving.layout]
	if db and name then db[name] = next(saving.draft) and saving.draft or nil end
	saving, draft, editLayout = nil, nil, nil
	Bars.QueueRefresh()
end)

-- New Layout also implements Copy and saving a modified Blizzard preset.
-- The client reverts the source before adding the copy, so capture it when
-- the naming dialog opens. Blizzard's exported layouts contain no addon data.
hooksecurefunc(manager, "ShowNewLayoutDialog", function(_, source)
	local values = choices(source or manager:GetActiveLayoutInfo())
	copySource = next(values) and CopyTable(values) or nil
end)
hooksecurefunc(manager, "MakeNewLayout", function(_, layout, kind, name, imported)
	if not layout or layout.layoutName ~= name or layout.layoutType ~= kind then return end
	for _, added in ipairs(manager:GetLayouts()) do
		if added.layoutType == kind and added.layoutName == name then
			local db = database(added)
			if db then db[name] = not imported and copySource or nil end
			copySource = nil
			Bars.QueueRefresh()
			return
		end
	end
end)

local scaleEvents = CreateFrame("Frame")
scaleEvents:RegisterEvent("UI_SCALE_CHANGED")
scaleEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleEvents:SetScript("OnEvent", Bars.QueueRefresh)

-- Version 0.3 stored one border string per bar. Preserve all layouts and
-- both storage scopes when moving those values into the per-bar options.
local function migrate(layouts, borders)
	layouts = type(layouts) == "table" and layouts or {}
	if type(borders) == "table" then
		for name, bars in pairs(borders) do
			if type(bars) == "table" then
				local options = type(layouts[name]) == "table" and layouts[name] or {}
				for index, style in pairs(bars) do
					if labels[style] and style ~= DEFAULT then
						local bar = barOptions(options, index) or {}
						bar.border = bar.border or style
						options[index] = bar
					end
				end
				if next(options) then layouts[name] = options end
			end
		end
	end
	return layouts
end

EventUtil.ContinueOnAddOnLoaded(addon, function()
	BarsLayouts = migrate(BarsLayouts, BarsBorders)
	BarsCharacterLayouts = migrate(BarsCharacterLayouts, BarsCharacterBorders)
	BarsBorders, BarsCharacterBorders = nil, nil
	ready = true
	if manager:IsInitialized() then layoutUpdated() end
end)
