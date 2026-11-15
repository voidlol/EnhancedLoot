-- Enhanced Loot - settings panel (Blizzard Settings / Interface Options).
-- Author: voidlol - https://github.com/voidlol/EnhancedLoot

local _, ns = ...
local SetBorder = ns.SetBorder
local GetLSM = ns.GetLSM
local handlers = ns.handlers
local function RefreshLayout() ns.RefreshLayout() end

-- ============================================================== blizzard options panel

local optionsPanel
local optionsCategory
local optSync = function() end

local QUALITY_NAMES = {
	"Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact",
}

local OUTLINE_ITEMS = {
	{ name = "None",          value = "" },
	{ name = "Outline",       value = "OUTLINE" },
	{ name = "Thick outline", value = "THICKOUTLINE" },
}

local BUILTIN_FONTS = {
	{ name = "Friz Quadrata TT", value = "Fonts\\FRIZQT__.TTF" },
	{ name = "Arial Narrow",     value = "Fonts\\ARIALN.TTF" },
	{ name = "Morpheus",         value = "Fonts\\MORPHEUS.TTF" },
	{ name = "Skurri",           value = "Fonts\\SKURRI.TTF" },
}

local function FontItems()
	local items, seen = {}, {}
	local lsm = GetLSM()

	if lsm then
		local list = lsm:List("font")
		if list then
			for _, name in ipairs(list) do
				items[#items + 1] = { name = name, value = name }
				seen[name] = true
			end
		end
	end

	if #items == 0 then
		for _, f in ipairs(BUILTIN_FONTS) do
			items[#items + 1] = { name = f.name, value = f.value }
		end
	elseif not seen["Friz Quadrata TT"] then
		items[#items + 1] = { name = "Friz Quadrata TT", value = "Fonts\\FRIZQT__.TTF" }
	end

	return items
end

local function QualityLabel(i)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[i]
	if c then
		return string.format("|cff%02x%02x%02x%s|r", math.floor(c.r * 255 + 0.5),
			math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5), QUALITY_NAMES[i + 1] or ("Q" .. i))
	end
	return QUALITY_NAMES[i + 1] or ("Q" .. i)
end

local function CreateHeader(parent, text, x, y)
	local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h:SetPoint("TOPLEFT", x, y)
	h:SetText(text)
	h:SetTextColor(1, 0.82, 0.1)
	return h
end

local function CreateCheck(parent, label, x, y, getter, setter, after)
	local cb = CreateFrame("Button", nil, parent)
	cb:SetSize(18, 18)
	cb:SetPoint("TOPLEFT", x, y)
	cb:EnableMouse(true)

	local bg = cb:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.08, 0.08, 0.1, 0.9)
	SetBorder(cb, 0.45, 0.45, 0.5, 1)

	local check = cb:CreateTexture(nil, "ARTWORK")
	check:SetPoint("TOPLEFT", 3, -3)
	check:SetPoint("BOTTOMRIGHT", -3, 3)
	check:SetColorTexture(1, 0.82, 0.1, 1)

	local txt = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	txt:SetPoint("LEFT", cb, "RIGHT", 7, 0)
	txt:SetText(label)

	function cb:Sync()
		local on = getter()
		check:SetShown(on and true or false)
		if on then
			txt:SetTextColor(1, 1, 1)
		else
			txt:SetTextColor(0.55, 0.55, 0.55)
		end
	end

	cb:SetScript("OnClick", function(self)
		setter(not getter())
		self:Sync()
		if after then after() end
	end)

	cb:Sync()
	return cb
end

local function CreateSlider(parent, label, minV, maxV, step, x, y, getter, setter, after, fmt)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(220, 14)
	s:SetPoint("TOPLEFT", x, y)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(1, 1, 1, 0.15)
	track:SetPoint("LEFT", 0, 0)
	track:SetPoint("RIGHT", 0, 0)
	track:SetHeight(3)

	local lab = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lab:SetPoint("BOTTOMLEFT", 0, 16)
	lab:SetText(label)

	local val = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	val:SetPoint("BOTTOMRIGHT", 0, 16)

	local function Format(v)
		return fmt and fmt(v) or tostring(v)
	end

	function s:Sync()
		local v = getter()
		self.__sync = true
		self:SetValue(v)
		self.__sync = nil
		val:SetText(Format(v))
	end

	s:SetScript("OnValueChanged", function(self, value)
		if self.__sync then return end
		value = math.floor(value / step + 0.5) * step
		value = tonumber(string.format("%.3f", value))
		setter(value)
		val:SetText(Format(value))
		if after then after() end
	end)

	s:Sync()
	return s
end

local function CreateButton(parent, label, x, y, onClick, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 110, 22)
	b:SetPoint("TOPLEFT", x, y)

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.13, 0.13, 0.16, 0.95)
	SetBorder(b, 0.4, 0.4, 0.45, 1)

	local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	t:SetPoint("CENTER")
	t:SetText(label)
	b.label = t

	b:SetScript("OnEnter", function() bg:SetColorTexture(0.24, 0.24, 0.28, 0.95) end)
	b:SetScript("OnLeave", function() bg:SetColorTexture(0.13, 0.13, 0.16, 0.95) end)
	b:SetScript("OnClick", onClick)
	return b
end

-- simple scrollable dropdown (no UIDropDownMenu dependency)
local function CreateDropdown(parent, x, y, width, itemsFn, getter, setter)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(width, 22)
	btn:SetPoint("TOPLEFT", x, y)

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.13, 0.13, 0.16, 0.95)
	SetBorder(btn, 0.4, 0.4, 0.45, 1)

	local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", 8, 0)
	label:SetPoint("RIGHT", -16, 0)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)

	local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	arrow:SetPoint("RIGHT", -6, 0)
	arrow:SetText("v")

	local popup = CreateFrame("Frame", nil, UIParent)
	popup:SetFrameStrata("FULLSCREEN_DIALOG")
	popup:SetClampedToScreen(true)
	popup:EnableMouseWheel(true)
	popup:Hide()

	local pbg = popup:CreateTexture(nil, "BACKGROUND")
	pbg:SetAllPoints()
	pbg:SetColorTexture(0.05, 0.05, 0.06, 0.98)
	SetBorder(popup, 0.5, 0.5, 0.55, 1)

	local ROW_H, MAXROWS = 20, 12
	local rows, offset = {}, 0

	local function LayoutRows()
		local items = itemsFn()
		local shown = math.min(MAXROWS, #items)
		for i = 1, MAXROWS do
			local r = rows[i]
			if not r then
				r = CreateFrame("Button", nil, popup)
				r:SetHeight(ROW_H)
				r:SetPoint("TOPLEFT", 2, -((i - 1) * ROW_H + 2))
				r:SetPoint("TOPRIGHT", -2, -((i - 1) * ROW_H + 2))
				r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				r.text:SetPoint("LEFT", 6, 0)
				local hl = r:CreateTexture(nil, "HIGHLIGHT")
				hl:SetAllPoints()
				hl:SetColorTexture(1, 0.82, 0.1, 0.15)
				r:SetScript("OnClick", function(self)
					if self.__value ~= nil then
						setter(self.__value)
					end
					popup:Hide()
					btn:Sync()
				end)
				rows[i] = r
			end
			local item = items[offset + i]
			if i <= shown and item then
				r.__value = item.value
				r.text:SetText(item.name)
				r:Show()
			else
				r:Hide()
			end
		end
		popup:SetSize(width, shown * ROW_H + 4)
	end

	popup:SetScript("OnMouseWheel", function(_, delta)
		local items = itemsFn()
		local maxOff = math.max(0, #items - MAXROWS)
		offset = math.max(0, math.min(maxOff, offset - delta))
		LayoutRows()
	end)

	function btn:Sync()
		local name = getter()
		if name == nil or name == "" then name = "(none)" end
		label:SetText(tostring(name))
	end

	btn:SetScript("OnClick", function(self)
		if popup:IsShown() then
			popup:Hide()
			return
		end
		offset = 0
		popup:ClearAllPoints()
		popup:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
		LayoutRows()
		popup:Show()
	end)

	btn.Sync()
	if parent.HookScript then
		parent:HookScript("OnHide", function() popup:Hide() end)
	end
	return btn
end

local function BuildOptions()
	local panel = CreateFrame("Frame")
	panel.name = "Enhanced Loot"

	local w = {}
	panel.widgets = w

	local x, y = 16, -18

	CreateHeader(panel, "Bars", x, y)
	y = y - 26

	w.duration = CreateSlider(panel, "Duration", 0.5, 15, 0.5, x, y,
		function() return ns.db.duration end,
		function(v) ns.db.duration = v end, nil,
		function(v) return string.format("%.1f s", v) end)
	y = y - 38

	w.scale = CreateSlider(panel, "Scale", 0.5, 2, 0.05, x, y,
		function() return ns.db.scale end,
		function(v) ns.db.scale = v end,
		function() RefreshLayout() end,
		function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
	y = y - 38

	w.width = CreateSlider(panel, "Width", 200, 600, 10, x, y,
		function() return ns.db.width end,
		function(v) ns.db.width = v end,
		function() RefreshLayout() end,
		function(v) return string.format("%d px", v) end)
	y = y - 38

	w.height = CreateSlider(panel, "Height", 14, 40, 1, x, y,
		function() return ns.db.height end,
		function(v) ns.db.height = v end,
		function() RefreshLayout() end,
		function(v) return string.format("%d px", v) end)
	y = y - 38

	w.maxbars = CreateSlider(panel, "Max bars", 1, 15, 1, x, y,
		function() return ns.db.maxbars end,
		function(v) ns.db.maxbars = v end, nil,
		function(v) return string.format("%d", v) end)

	-- two columns: Appearance | Show
	local colB = x + 300
	local yChecks = y - 42

	CreateHeader(panel, "Appearance", x, yChecks)
	CreateHeader(panel, "Show", colB, yChecks)
	yChecks = yChecks - 26

	w.darkmode = CreateCheck(panel, "Dark backdrop", x, yChecks,
		function() return ns.db.darkmode end,
		function(v) ns.db.darkmode = v end,
		function() RefreshLayout() end)

	w.currency = CreateCheck(panel, "Money gains", colB, yChecks,
		function() return ns.db.currency end,
		function(v) ns.db.currency = v end)
	yChecks = yChecks - 24

	w.lightmode = CreateCheck(panel, "Light backdrop", x, yChecks,
		function() return ns.db.lightmode end,
		function(v) ns.db.lightmode = v end,
		function() RefreshLayout() end)

	w.experience = CreateCheck(panel, "Experience gains", colB, yChecks,
		function() return ns.db.experience end,
		function(v) ns.db.experience = v end)
	yChecks = yChecks - 24

	w.glow = CreateCheck(panel, "Glow", x, yChecks,
		function() return ns.db.glow end,
		function(v) ns.db.glow = v end,
		function() RefreshLayout() end)

	w.questmark = CreateCheck(panel, "Quest marker (!)", colB, yChecks,
		function() return ns.db.questmark ~= false end,
		function(v) ns.db.questmark = v end,
		function() RefreshLayout() end)

	yChecks = yChecks - 24

	w.qualitybg = CreateCheck(panel, "Quality-coloured background", x, yChecks,
		function() return ns.db.qualitybg end,
		function(v) ns.db.qualitybg = v end,
		function() RefreshLayout() end)

	w.unlooted = CreateCheck(panel, "Unlooted items (red)", colB, yChecks,
		function() return ns.db.unlooted ~= false end,
		function(v) ns.db.unlooted = v end)

	y = yChecks - 36

	CreateHeader(panel, "Item quality filter", x, y)
	y = y - 26

	local rx, ry = x, y
	for q = 0, 6 do
		if q == 4 then
			rx = x
			ry = ry - 24
		end
		w["rarity" .. q] = CreateCheck(panel, QualityLabel(q), rx, ry,
			function() return ns.db.rarity[q + 1] ~= false end,
			function(v) ns.db.rarity[q + 1] = v end)
		rx = rx + 140
	end
	y = ry - 36

	CreateHeader(panel, "Font", x, y)
	y = y - 26

	w.fontFamily = CreateDropdown(panel, x, y, 240, FontItems,
		function() return ns.db.fontFamily end,
		function(v)
			ns.db.fontFamily = v
			RefreshLayout()
		end)

	w.fontOutline = CreateDropdown(panel, x + 252, y, 150,
		function() return OUTLINE_ITEMS end,
		function()
			for _, item in ipairs(OUTLINE_ITEMS) do
				if item.value == ns.db.fontOutline then return item.name end
			end
			return "None"
		end,
		function(v)
			ns.db.fontOutline = v
			RefreshLayout()
		end)

	y = y - 34

	w.fontSize = CreateSlider(panel, "Font size", 8, 32, 1, x, y,
		function() return ns.db.fontSize end,
		function(v) ns.db.fontSize = v end,
		function() RefreshLayout() end,
		function(v) return string.format("%d pt", v) end)

	y = y - 40

	CreateButton(panel, "Preview", x, y, function() ns.Preview() end)
	CreateButton(panel, "Move bars", x + 118, y, function() handlers.unlock() end)
	CreateButton(panel, "Lock bars", x + 236, y, function() handlers.lock() end)
	CreateButton(panel, "Reset", x + 354, y, function()
		handlers.reset()
		optSync()
	end)

	panel:SetSize(600, math.max(420, (-y) + 30))

	panel:SetScript("OnShow", function()
		if optSync then optSync() end
	end)

	optSync = function()
		for _, widget in pairs(w) do
			if widget.Sync then widget:Sync() end
		end
	end

	return panel
end

local fallbackWindow

local function ShowFallbackWindow()
	if not fallbackWindow then
		fallbackWindow = CreateFrame("Frame", "EnhancedLootOptionsWindow", UIParent)
		fallbackWindow:SetSize(632, optionsPanel:GetHeight() + 60)
		fallbackWindow:SetPoint("CENTER")
		fallbackWindow:SetFrameStrata("DIALOG")
		fallbackWindow:EnableMouse(true)
		fallbackWindow:SetMovable(true)
		fallbackWindow:RegisterForDrag("LeftButton")
		fallbackWindow:SetScript("OnDragStart", function(self) self:StartMoving() end)
		fallbackWindow:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

		local bg = fallbackWindow:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)
		SetBorder(fallbackWindow, 1, 0.82, 0.1, 1)

		local title = fallbackWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOPLEFT", 16, -14)
		title:SetText("Enhanced Loot")

		CreateButton(fallbackWindow, "Close", 500, -(optionsPanel:GetHeight() + 22), function()
			fallbackWindow:Hide()
		end)

		optionsPanel:SetParent(fallbackWindow)
		optionsPanel:ClearAllPoints()
		optionsPanel:SetPoint("TOPLEFT", 6, -40)
	end
	fallbackWindow:Show()
end

function ns.OpenOptions()
	if not optionsPanel then optionsPanel = BuildOptions() end
	-- the settings frame is protected: opening it in combat gets blocked
	if InCombatLockdown and InCombatLockdown() then
		DEFAULT_CHAT_FRAME:AddMessage("|cffffd100EnhancedLoot|r options can't open in combat")
		return
	end
	if Settings and optionsCategory then
		Settings.OpenToCategory(optionsCategory:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(optionsPanel)
		InterfaceOptionsFrame_OpenToCategory(optionsPanel)
	else
		ShowFallbackWindow()
	end
end

function ns.RegisterOptions()
	if optionsPanel or optionsCategory then return end
	optionsPanel = BuildOptions()

	if Settings and Settings.RegisterCanvasLayoutCategory then
		optionsCategory = Settings.RegisterCanvasLayoutCategory(optionsPanel, "Enhanced Loot")
		Settings.RegisterAddOnCategory(optionsCategory)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(optionsPanel)
	else
		optionsPanel:Hide()
		optionsPanel:SetParent(UIParent)
	end
end
