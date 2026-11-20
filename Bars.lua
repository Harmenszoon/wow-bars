-- Extend Edit Mode's Icon Padding slider on every action bar that offers it.
local _, Bars = ...
local ACTION_BAR = Enum.EditModeSystem.ActionBar
local PADDING = Enum.EditModeActionBarSetting.IconPadding

-- Edit Mode saves the raw padding, even though it displays values below 2 as 2.
-- Keep the original slider, steppers and change handler so Save and Revert work.
hooksecurefunc(EditModeSystemSettingsDialog, "UpdateSettings", function(dialog, bar)
	if not bar or bar ~= dialog.attachedToSystem or bar.system ~= ACTION_BAR then return end
	for row in dialog.pools:EnumerateActiveByTemplate("EditModeSettingSliderTemplate") do
		if row.setting == PADDING then
			local widget = row.Slider
			local slider = widget.Slider
			local low, high = slider:GetMinMaxValues()
			if low == 0 then return end
			slider:SetMinMaxValues(0, high)
			local raw = bar:GetSettingValue(PADDING, true)
			if raw >= 0 and raw < low then slider:SetValue(raw) end
			widget:UpdateStepperStates()
			return
		end
	end
end)

-- Blizzard replaces oldGridSettings each time it anchors the containers.
-- Remember which grid already has our spacing, including when 0 changes to 1
-- and Blizzard sees both as 2. Only a bar with subminimum padding needs a record.
local adjusted, deferred = {}, {}

local function updatePadding(bar)
	local setting = bar.system == ACTION_BAR and bar.settingMap and bar.settingMap[PADDING]
	local grid = bar.oldGridSettings
	if not setting or not grid then return end

	local containers = bar.shownButtonContainers
	local native = math.max(bar.minButtonPadding, bar.buttonPadding)
	local padding = Clamp(setting.value, 0, native)
	local last = adjusted[bar]
	if last and last.grid ~= grid then
		adjusted[bar], last = nil, nil
	end
	if padding == (last and last.padding or native) or #containers < 2 then return end

	if InCombatLockdown() then
		if not deferred[bar] then
			deferred[bar] = true
			EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_REGEN_ENABLED", function()
				deferred[bar] = nil
				bar:UpdateGridLayout()
			end)
		end
		return
	end

	-- Blizzard starts its grid at this corner of the bar. The first container's
	-- offsets can already include alignment for differently sized buttons.
	local corner = containers[1]:GetPoint(1)
	local anchor = AnchorUtil.CreateAnchor(corner, bar, corner)
	local makeGrid = bar.isHorizontal and GridLayoutUtil.CreateStandardGridLayout or GridLayoutUtil.CreateVerticalGridLayout
	local stride = math.ceil(#containers / bar.numRows)
	local layout = makeGrid(stride, padding, padding, bar.addButtonsToRight and 1 or -1, bar.addButtonsToTop and 1 or -1)
	GridLayoutUtil.ApplyGridLayout(containers, anchor, layout)
	bar:Layout()
	bar:UpdateSpellFlyoutDirection()
	adjusted[bar] = padding < native and { grid = grid, padding = padding } or nil
	return true
end

-- The Edit Mode mixin calls this before it stacks neighbouring bars. This
-- includes the pet, stance and possess bars as their visible buttons change.
hooksecurefunc(ActionBarMixin, "UpdateGridLayout", updatePadding)
for _, bar in ipairs(EditModeManagerFrame.registeredSystemFrames) do
	if updatePadding(bar) then EditModeManagerFrame:UpdateActionBarLayout(bar) end
end

-- The previous version saved by bar name, across all layouts. Offer its
-- padding, border and opacity choices once as edits to the first layout opened.
EventRegistry:RegisterCallback("EditMode.Enter", function(owner)
	local manager = EditModeManagerFrame
	if type(BarsDB) == "table" then
		if InCombatLockdown() or not manager:GetActiveLayoutSystemInfo(ACTION_BAR, Enum.EditModeActionBarSystemIndices.MainBar) then return end
		for _, bar in ipairs(manager.registeredSystemFrames) do
			if bar.system == ACTION_BAR and bar:HasSetting(PADDING) then
				local old = BarsDB[bar:GetName()]
				local padding = type(old) == "table" and old.padding
				if type(padding) == "number" and padding >= 0 and padding <= 10 and padding % 1 == 0
					and padding ~= bar:GetSettingValue(PADDING, true) then
					manager:OnSystemSettingChange(bar, PADDING, padding)
				end
				if type(old) == "table" and old.bare == true then
					Bars.SelectSetting(bar, "border", old.zoomed == true and "trimmed" or "square")
				end
				if type(old) == "table" and type(old.opacity) == "number" and old.opacity >= 0 and old.opacity < 100 then
					Bars.SelectSetting(bar, "opacity", old.opacity)
				end
			end
		end
		BarsDB = nil
	end
	EventRegistry:UnregisterCallback("EditMode.Enter", owner)
end)
