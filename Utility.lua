local _, Bars = ...
local sizes, hiddenArt = {}, {}

function Bars.BarKey(bar)
	if not bar then return end
	if bar.system == Enum.EditModeSystem.ActionBar and bar.actionButtons then return bar.systemIndex end
	if bar == BagsBar then return "bags" end
	if bar == MicroMenuContainer then return "micro" end
end

function Bars.SizeSetting(bar)
	if bar == BagsBar then return Enum.EditModeBagsSetting.Size end
	if bar == MicroMenuContainer then return Enum.EditModeMicroMenuSetting.Size end
end

local function currentScale(bar)
	return bar == BagsBar and bar:GetScale() or MicroMenu.normalScale
end

function Bars.NativeSize(bar)
	local setting = Bars.SizeSetting(bar)
	if bar:HasSetting(setting) then return bar:GetSettingValue(setting) end
	return ((sizes[bar] and sizes[bar].base) or currentScale(bar)) * 100
end

-- Keep supported sizes in the native layout. Only the extended range needs
-- an addon override. MicroMenu's normal scale preserves its vehicle override.
function Bars.ApplySize(bar, size)
	local state = sizes[bar]
	if not size and not (state and state.size) then return end
	if not state then
		state = {}
		sizes[bar] = state
		hooksecurefunc(bar, "UpdateSystemSettingSize", function()
			if state.size then Bars.QueueRefresh() end
		end)
	end
	if not state.size then state.base = currentScale(bar) end
	local scale = (size or Bars.NativeSize(bar)) / 100
	state.size = size
	if not size then state.base = nil end
	if math.abs(currentScale(bar) - scale) < 0.0001 then return end
	if bar == BagsBar then
		bar:SetScale(scale)
	else
		MicroMenu:SetNormalScale(scale)
		bar:Layout()
	end
end

local function hideTexture(texture)
	if texture and hiddenArt[texture] == nil then
		hiddenArt[texture] = texture:GetAlpha()
		texture:SetAlpha(0)
	end
end

local function restoreTexture(texture)
	local alpha = hiddenArt[texture]
	if alpha ~= nil then
		texture:SetAlpha(alpha)
		hiddenArt[texture] = nil
	end
end

function Bars.ApplyBackground(bar, hidden)
	local art = bar == BagsBar and bar or MicroMenu
	local apply = hidden and hideTexture or restoreTexture
	apply(art.BorderArt)
	apply(art.BackgroundArt)
	if bar == BagsBar then Bars.SetDividersHidden(bar, hidden) end
end

function Bars.ObserveUtilityButtons(bar, add)
	if bar == BagsBar then
		for _, button in MainMenuBarBagManager:EnumerateBagButtons() do add(button) end
		if BagBarExpandToggle and bar:ShouldShowExpandToggle() then add(BagBarExpandToggle) end
	else
		for _, child in ipairs({ MicroMenu:GetChildren() }) do
			if child.layoutIndex then add(child) end
		end
		hooksecurefunc(MicroMenu, "AddButton", function(_, button) add(button) end)
	end
end
