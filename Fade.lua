local _, Bars = ...
local states, pending = {}, {}
local actionGrid, petGrid = false, false
local previewBar, selectionAlpha, flushScheduled, flyoutBar

local function isRevealed(state)
	if EditModeManagerFrame:IsEditModeActive() then return state.bar ~= previewBar end
	if state.bar.actionButtons then
		if actionGrid or petGrid or state.nativeGrid or flyoutBar == state.bar then return true end
	elseif state.bar == BagsBar and MainMenuBarBagManager.expandBarAuto then
		return true
	end
	for _, frame in ipairs(state.targets) do
		if frame:IsMouseMotionFocus() then return true end
	end
	return false
end

local function setAlpha(state, alpha)
	if alpha == state.alpha then return end
	state.bar:SetAlpha(alpha)
	state.alpha = alpha
end

local function update(state)
	local alpha = state.idle
	if not alpha then return end
	if alpha ~= state.base and isRevealed(state) then alpha = state.base end
	setAlpha(state, alpha)
end

function Bars.PreviewOpacity(bar)
	if bar and not EditModeManagerFrame:IsEditModeActive() then bar = nil end
	if bar == previewBar then return end
	local previous = previewBar
	previewBar = bar
	if previous then
		previous.Selection:SetAlpha(selectionAlpha)
		if states[previous] then update(states[previous]) end
	end
	if bar then
		selectionAlpha = bar.Selection:GetAlpha()
		bar.Selection:SetAlpha(0)
		if states[bar] then update(states[bar]) end
	end
end

-- Reveal on entry. On leave, wait for the new focus so crossing between
-- adjacent buttons never flashes the idle opacity.
local function flush()
	flushScheduled = nil
	for state in pairs(pending) do
		pending[state] = nil
		update(state)
	end
end

local function observe(bar)
	local state = { bar = bar, targets = {} }
	local function enter()
		if state.idle and bar ~= previewBar then
			pending[state] = nil
			setAlpha(state, state.base)
		end
	end
	local function leave()
		if not state.idle or state.idle == state.base or pending[state] then return end
		pending[state] = true
		if not flushScheduled then
			flushScheduled = true
			RunNextFrame(flush)
		end
	end
	local function add(frame)
		state.targets[#state.targets + 1] = frame
		frame:HookScript("OnEnter", enter)
		frame:HookScript("OnLeave", leave)
	end

	local buttons = bar.actionButtons
	local firstButton = buttons and buttons[1]
	if bar:IsMouseMotionEnabled() then
		add(bar)
	elseif not buttons or (firstButton and firstButton.container) then
		-- MultiBars enumerate direct children when sizing. The two utility
		-- containers have their own explicit layouts and can host the target.
		local area = CreateFrame("Frame", nil, firstButton and firstButton.container or bar)
		area:SetFrameLevel(bar:GetFrameLevel())
		area:SetAllPoints(bar)
		area:SetMouseClickEnabled(false)
		area:SetMouseMotionEnabled(true)
		area:SetPropagateMouseMotion(true)
		state.area = area
		add(area)
	end
	if buttons then
		for _, button in ipairs(buttons) do add(button) end
		-- Quick Keybind and the spellbook request grids directly. Blizzard
		-- keeps overlapping requests active until the last one is released.
		if bar.GetShowAllButtons then
			state.nativeGrid = bar:GetShowAllButtons()
			hooksecurefunc(bar, "SetShowGrid", function()
				local shown = bar:GetShowAllButtons()
				if state.nativeGrid ~= shown then
					state.nativeGrid = shown
					update(state)
				end
			end)
		end
	else
		Bars.ObserveUtilityButtons(bar, add)
	end
	if bar.ActionBarPageNumber then
		add(bar.ActionBarPageNumber.UpButton)
		add(bar.ActionBarPageNumber.DownButton)
	end
	bar:HookScript("OnShow", leave)
	states[bar] = state
	return state
end

function Bars.ApplyOpacity(bar, percent)
	local state = states[bar]
	if percent == 100 then
		if state and state.idle then
			state.idle = nil
			pending[state] = nil
			if state.area then state.area:Hide() end
			setAlpha(state, state.base)
		end
		return
	end
	state = state or observe(bar)
	if not state.idle then
		state.base = bar:GetAlpha()
		state.alpha = state.base
		if state.area then state.area:Show() end
	end
	state.idle = math.min(state.base, percent / 100)
	update(state)
end

local function updateAll(actionsOnly)
	for bar, state in pairs(states) do
		if not actionsOnly or bar.actionButtons then update(state) end
	end
end

EventRegistry:RegisterCallback("EditMode.Enter", function() updateAll() end)
EventRegistry:RegisterCallback("EditMode.Exit", function()
	Bars.PreviewOpacity(nil)
	updateAll()
end)
local function flyoutChanged()
	local owner = SpellFlyout:IsVisible() and SpellFlyout:GetParent()
	local previous = flyoutBar
	flyoutBar = owner and owner.bar
	if previous ~= flyoutBar then
		if states[previous] then update(states[previous]) end
		if states[flyoutBar] then update(states[flyoutBar]) end
	end
end
SpellFlyout:HookScript("OnShow", flyoutChanged)
SpellFlyout:HookScript("OnHide", flyoutChanged)
flyoutChanged()
EventRegistry:RegisterCallback("MainMenuBarManager.OnExpandChanged", function()
	local state = states[BagsBar]
	if state then update(state) end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ACTIONBAR_SHOWGRID")
events:RegisterEvent("ACTIONBAR_HIDEGRID")
events:RegisterEvent("PET_BAR_SHOWGRID")
events:RegisterEvent("PET_BAR_HIDEGRID")
events:SetScript("OnEvent", function(_, event)
	local wasShown = actionGrid or petGrid
	if event == "ACTIONBAR_SHOWGRID" then actionGrid = true
	elseif event == "ACTIONBAR_HIDEGRID" then actionGrid = false
	else petGrid = event == "PET_BAR_SHOWGRID" end
	if wasShown ~= (actionGrid or petGrid) then updateAll(true) end
end)
