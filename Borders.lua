local _, Bars = ...
local buttons, applied = {}, {}
local cooldowns = { "cooldown", "chargeCooldown", "lossOfControlCooldown" }
local rim = { "NormalTexture", "SlotArt", "SlotBackground" }
local feedback = {
	PushedTexture = { 0, 0, 0, 0.35 },
	HighlightTexture = { 1, 1, 1, 0.18 },
	CheckedTexture = { 1, 0.8, 0.32, 0.38 },
}

-- Change only Blizzard's icon mask. Other masks on the same texture belong
-- to their owners. The same mask can clip our empty slot and button feedback.
local function hasMask(texture, mask)
	for i = 1, texture:GetNumMaskTextures() do
		if texture:GetMaskTexture(i) == mask then return true end
	end
	return false
end

local function setMask(texture, mask, enabled)
	if enabled == hasMask(texture, mask) then return end
	if enabled then texture:AddMaskTexture(mask) else texture:RemoveMaskTexture(mask) end
end

local function updateEmptySlot(button)
	local state = buttons[button]
	if not state.style then return end
	local empty = not button.icon:IsShown()
	if not empty and state.textureOnly then
		local texture = button.icon:GetTexture()
		empty = not issecretvalue(texture) and texture == nil
	end
	if state.slot:IsShown() ~= empty then state.slot:SetShown(empty) end
end

local function capture(button)
	local state = buttons[button] or {}
	state.coords = { button.icon:GetTexCoord() }
	state.masked = hasMask(button.icon, button.IconMask)
	for _, key in ipairs(rim) do state[key] = button[key]:GetAlpha() end
	for key in pairs(feedback) do
		local region = button[key]
		local original = {
			atlas = region:GetAtlas(), anchors = RegionUtil.GetPointsArray(region),
			width = region:GetWidth(), height = region:GetHeight(),
			masked = hasMask(region, button.IconMask),
		}
		if not original.atlas then
			original.texture, original.coords = region:GetTexture(), { region:GetTexCoord() }
		end
		state[key] = original
	end
	for _, key in ipairs(cooldowns) do state[key] = RegionUtil.GetPointsArray(button[key]) end
	if not state.slot then
		state.slot = button:CreateTexture(nil, "BACKGROUND", nil, -8)
		state.slot:SetColorTexture(0, 0, 0, 0.45)
		state.slot:SetAllPoints(button.icon)
		-- Blizzard selects a new pressed atlas when it reapplies bar art.
		hooksecurefunc(button, "UpdateButtonArt", function()
			if state.style then button.PushedTexture:SetColorTexture(unpack(feedback.PushedTexture)) end
		end)
		-- Action and pet buttons hide empty icons. Stance and possess buttons
		-- clear the texture instead. A filled icon needs no second dark layer.
		if button.UpdateButtonState then
			hooksecurefunc(button, "UpdateButtonState", updateEmptySlot)
		elseif button.UpdateAction and button.Update then
			hooksecurefunc(button, "Update", updateEmptySlot)
		else
			state.textureOnly = true
			hooksecurefunc(button.icon, "SetTexture", function() updateEmptySlot(button) end)
		end
	end
	buttons[button] = state
	return state
end

local edges = {
	{ "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
	{ "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" },
}

local function updateOutline(button, state, shown)
	if not shown then
		if state.pixel then
			for _, edge in ipairs(state.edges) do edge:Hide() end
			state.pixel = nil
		end
		return
	end
	local pixel = PixelUtil.GetPixelToUIUnitFactor() / button:GetEffectiveScale()
	if state.pixel == pixel then return end
	state.edges = state.edges or {}
	for i, corners in ipairs(edges) do
		local edge = state.edges[i]
		if not edge then
			edge = button:CreateTexture(nil, "ARTWORK", nil, 0)
			edge:SetColorTexture(0, 0, 0, 1)
			edge:SetPoint(corners[1], button.icon, corners[1])
			edge:SetPoint(corners[2], button.icon, corners[2])
			state.edges[i] = edge
		end
		if i <= 2 then edge:SetHeight(pixel) else edge:SetWidth(pixel) end
		if not state.pixel then edge:Show() end
	end
	state.pixel = pixel
end

local function hasOutline(style)
	return style == "outline" or style == "trimmedOutline"
end

local function styleButton(button, style)
	local state = buttons[button]
	if not state or not state.style then
		if style == "blizzard" then return end
		state = capture(button)
	end

	local stock = style == "blizzard"
	local clipped = style == "clipped"
	local square = not stock and not clipped
	local mask = button.IconMask
	setMask(button.icon, mask, clipped or (stock and state.masked))
	setMask(state.slot, mask, clipped)
	for _, key in ipairs(rim) do button[key]:SetAlpha(stock and state[key] or 0) end

	if style == "trimmed" or style == "trimmedOutline" then
		button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	elseif state.style == "trimmed" or state.style == "trimmedOutline" then
		button.icon:SetTexCoord(unpack(state.coords))
	end

	for key, color in pairs(feedback) do
		local region, original = button[key], state[key]
		setMask(region, mask, clipped or (stock and original.masked))
		if stock then
			-- UpdateButtonArt below selects the current bar's pressed atlas.
			if key ~= "PushedTexture" then
				if original.atlas then
					region:SetAtlas(original.atlas)
				else
					region:SetTexture(original.texture)
					region:SetTexCoord(unpack(original.coords))
				end
			end
			region:SetSize(original.width, original.height)
			RegionUtil.ApplyRegionPoints(region, original.anchors)
		else
			region:SetColorTexture(unpack(color))
			region:ClearAllPoints()
			region:SetAllPoints(button.icon)
		end
	end
	for _, key in ipairs(cooldowns) do
		if square then
			button[key]:ClearAllPoints()
			button[key]:SetAllPoints(button.icon)
		elseif state.style and state.style ~= "clipped" then
			RegionUtil.ApplyRegionPoints(button[key], state[key])
		end
	end
	updateOutline(button, state, hasOutline(style))
	if stock then
		state.style = nil
		state.slot:Hide()
		button:UpdateButtonArt()
	else
		state.style = style
		updateEmptySlot(button)
	end
end

-- The main action bar and bag bar recycle their dividers when rotated.
local dividers = {}
local function hideDividers(bar)
	local alphas = dividers[bar]
	if not alphas then return end
	local pool = bar.isHorizontal and bar.HorizontalDividersPool or bar.VerticalDividersPool
	if not pool then return end
	for divider in pool:EnumerateActive() do
		local alpha = divider:GetAlpha()
		if alpha ~= 0 then
			alphas[divider] = alphas[divider] or alpha
			divider:SetAlpha(0)
		end
	end
end

function Bars.SetDividersHidden(bar, hidden)
	local alphas = dividers[bar]
	if hidden then
		if alphas then return end
		if alphas == nil then hooksecurefunc(bar, "UpdateDividers", hideDividers) end
		dividers[bar] = {}
		hideDividers(bar)
	elseif alphas then
		for divider, alpha in pairs(alphas) do divider:SetAlpha(alpha) end
		dividers[bar] = false
	end
end

function Bars.ApplyBorder(bar, style)
	if style == (applied[bar] or "blizzard") then return end
	for _, button in ipairs(bar.actionButtons) do
		if button.IconMask and button.icon then styleButton(button, style) end
	end
	applied[bar] = style ~= "blizzard" and style or nil
	if bar == MainActionBar then Bars.SetDividersHidden(bar, applied[bar] ~= nil) end
	return true
end

-- Icon Size changes the effective scale without resizing the button.
function Bars.RefreshBorder(bar)
	if not hasOutline(applied[bar]) then return end
	for _, button in ipairs(bar.actionButtons) do
		local state = buttons[button]
		if state and state.style then updateOutline(button, state, true) end
	end
end
