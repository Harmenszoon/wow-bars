local _, Bars = ...
local manager = EditModeManagerFrame
local system = Enum.EditModeSystem

-- These dropdowns already have a Hidden value. Keep Blizzard's layout and
-- its combat rules authoritative, including changes made through the dropdown.
local native = {
	[system.ActionBar] = { setting = Enum.EditModeActionBarSetting.VisibleSetting, modes = Enum.ActionBarVisibleSetting },
	[system.AuraFrame] = { setting = Enum.EditModeAuraFrameSetting.VisibleSetting, modes = Enum.AuraFrameVisibleSetting },
	[system.CooldownViewer] = { setting = Enum.EditModeCooldownViewerSetting.VisibleSetting, modes = Enum.CooldownViewerVisibleSetting },
	[system.PersonalResourceDisplay] = { setting = Enum.EditModePersonalResourceDisplaySetting.VisibleSetting, modes = Enum.PersonalResourceDisplayVisibleSetting },
	[system.DamageMeter] = { setting = Enum.EditModeDamageMeterSetting.Visibility, modes = Enum.DamageMeterVisibility },
	[system.SwingTimer] = { setting = Enum.EditModeSwingTimerSetting.Visibility, modes = Enum.EditModeSwingTimerVisibility },
}

function Bars.VisibilityOption(frame)
	if not frame or frame.system == nil then return end
	-- The gryphons already have Blizzard's own Hidden checkbox.
	if frame.system == system.MainActionBarEndCap and frame:HasSetting(Enum.EditModeMainActionBarEndCapSetting.Hidden) then return end
	local key = Bars.BarKey(frame)
	local option = native[frame.system]
	if option and frame:HasSetting(option.setting) then
		return key or ("hud:%d:%d"):format(frame.system, frame.systemIndex or 0), option
	end
	return key or frame:GetName() or ("hud:%d:%d"):format(frame.system, frame.systemIndex or 0)
end

function Bars.NativeVisibilityValue(frame, option, options, hide)
	local modes = option.modes
	if hide then
		local previous = frame:GetSettingValue(option.setting)
		options.previousVisibility = previous ~= modes.Always and previous or nil
		return modes.Hidden
	end
	local previous = options.previousVisibility
	options.previousVisibility = nil
	for _, item in ipairs(frame.settingDisplayInfoMap[option.setting].options) do
		if item.value == previous and previous ~= modes.Hidden then return previous end
	end
	return modes.Always
end

-- The client's alwaysBlocked roleset gates the whole frame, including mouse
-- input. Blizzard can still own its parent, anchors, animations and shown state.
local BLOCKED = "alwaysBlocked"
local owned, wanted = {}, {}
local haveOverrides, waitingForCombat
local chatHidden, chatHooked, tooltipAnchor, tooltipHooked, tooltipQueued

local function setBlocked(frame, hide)
	if hide == (owned[frame] == true) then return end
	if InCombatLockdown() then
		local allowed = frame:CanChangeProtectedState()
		if not canaccessvalue(allowed) or not allowed then
			if not waitingForCombat then
				waitingForCombat = true
				Bars.QueueRefresh()
			end
			return
		end
	end
	if hide then
		if tContains(frame:GetRolesetNames(), BLOCKED) then return end
		frame:AddRoleset(BLOCKED)
		owned[frame] = true
	else
		owned[frame] = nil
		frame:RemoveRoleset(BLOCKED)
	end
end

local function want(frame)
	if frame then wanted[frame] = true end
end

local function wantDock()
	chatHidden = true
	if not chatHooked then
		chatHooked = true
		local function dockChanged(dock, window)
			if chatHidden and dock == GeneralDockManager then
				setBlocked(window, window == ChatFrame1 or window.dock == dock)
			end
		end
		hooksecurefunc("FCFDock_AddChatFrame", dockChanged)
		hooksecurefunc("FCFDock_RemoveChatFrame", dockChanged)
	end
	-- The dock controls and its windows have separate parents. The input
	-- box and undocked windows are independent of the Edit Mode element.
	want(GeneralDockManager)
	want(QuickJoinToastButton)
	want(TextToSpeechButtonFrame)
	want(ChatFrameToggleVoiceDeafenButton)
	want(ChatFrameToggleVoiceMuteButton)
	for _, window in ipairs(FCFDock_GetChatFrames(GeneralDockManager)) do want(window) end
end

local function tooltipUsesHUDAnchor()
	local restricted = GameTooltip:IsAnchoringRestricted()
	if not canaccessvalue(restricted) or restricted then return false end
	local _, anchor = GameTooltip:GetPoint(1)
	return canaccessvalue(anchor) and anchor == tooltipAnchor
end

local function syncTooltip()
	if tooltipAnchor then setBlocked(GameTooltip, tooltipUsesHUDAnchor()) end
end

local function checkTooltipNextFrame()
	tooltipQueued = nil
	syncTooltip()
end

local function wantHUDTooltip(frame)
	tooltipAnchor = frame
	if not tooltipHooked then
		tooltipHooked = true
		-- The same GameTooltip also serves bags, menus and action buttons.
		-- Blizzard finishes its default HUD anchor with an explicit SetPoint.
		hooksecurefunc(GameTooltip, "SetPoint", syncTooltip)
		hooksecurefunc(GameTooltip, "SetOwner", function(_, _, anchorType)
			if not tooltipAnchor then return end
			if canaccessvalue(anchorType) and anchorType ~= "ANCHOR_NONE" then
				setBlocked(GameTooltip, false)
			elseif owned[GameTooltip] and not tooltipQueued then
				tooltipQueued = true
				RunNextFrame(checkTooltipNextFrame)
			end
		end)
	end
	if tooltipUsesHUDAnchor() then want(GameTooltip) end
end

local function showForEditing()
	chatHidden, tooltipAnchor = nil, nil
	for frame in pairs(owned) do setBlocked(frame, false) end
end

function Bars.RefreshVisibility(settings)
	waitingForCombat = nil
	if manager:IsEditModeActive() then
		showForEditing()
		return
	end
	wipe(wanted)
	haveOverrides, chatHidden, tooltipAnchor = nil, nil, nil
	for _, options in pairs(settings) do
		if type(options) == "table" and options.hidden == true then haveOverrides = true break end
	end
	if haveOverrides then
		for _, frame in ipairs(manager.registeredSystemFrames) do
			local key, option = Bars.VisibilityOption(frame)
			local options = settings[key]
			if not option and type(options) == "table" and options.hidden == true then
				want(frame)
				if frame == ChatFrame1 then wantDock()
				elseif frame.system == system.HudTooltip then wantHUDTooltip(frame) end
			end
		end
	end
	for frame in pairs(owned) do
		if not wanted[frame] then setBlocked(frame, false) end
	end
	for frame in pairs(wanted) do setBlocked(frame, true) end
end

-- EnterEditMode clears these flags before it shows selections and snap targets.
hooksecurefunc(manager, "ClearActiveChangesFlags", function()
	if manager:IsEditModeActive() and not InCombatLockdown() then showForEditing() end
end)
hooksecurefunc(manager, "RegisterSystemFrame", function()
	if haveOverrides then Bars.QueueRefresh() end
end)
EventRegistry:RegisterCallback("EditMode.Exit", function() Bars.QueueRefresh() end)
