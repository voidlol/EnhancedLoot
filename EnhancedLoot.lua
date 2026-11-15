-- Enhanced Loot
-- Pop-up bars for looted items, money and experience.
-- Author: voidlol - https://github.com/voidlol/EnhancedLoot
-- Target: WoW Forever live client (1.60.x, Interface 16001), Lua 5.1.
-- Core: bars, events, slash commands. The settings panel lives in Options.lua.

local _, ns = ...

local defaults = {
	duration    = 5,
	darkmode    = true,
	lightmode   = false,
	glow        = false,
	currency    = true,
	experience  = true,
	questmark   = true,
	unlooted    = true,
	qualitybg   = false,
	fontFamily  = "Friz Quadrata TT",
	fontOutline = "OUTLINE",
	fontSize    = 12,
	rarity      = { true, true, true, true, true, true, true },
	scale       = 1,
	width       = 360,
	height      = 22,
	gap         = 4,
	maxbars     = 8,
	growth      = "UP",
	anchorPoint = "CENTER",
	x           = 0,
	y           = -170,
	unlocked    = false,
	alpha       = 1,
	fadeIn      = 0.15,
	fadeOut     = 0.45,
}

local db
local mover
local WHITE = "Interface\\Buttons\\WHITE8X8"
local COIN = {
	gold   = "Interface\\MoneyFrame\\UI-GoldIcon",
	silver = "Interface\\MoneyFrame\\UI-SilverIcon",
	copper = "Interface\\MoneyFrame\\UI-CopperIcon",
}
local FONT = "Fonts\\FRIZQT__.TTF"
local COUNT_FONT = "Fonts\\FRIZQT__.TTF"
-- coin-pile icons by amount (copper / silver / gold)
local COIN_ICON_SMALL, COIN_ICON_MEDIUM, COIN_ICON_LARGE = 133788, 133786, 133784
local XP_ICON = 894556
local PRICE_COLOR = "|cffa4763b"
local _GetItemCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount

-- API compatibility: modern clients (11.x / this build) removed the global
-- GetItemInfo in favour of C_Item.GetItemInfo.
local _GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local _GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
local _RequestItemData = C_Item and C_Item.RequestLoadItemDataByID

-- fonts: SharedMedia (LibSharedMedia-3.0) aware
local function GetLSM()
	if not LibStub then return nil end
	local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0", true)
	if ok then return lsm end
	return nil
end

local function ResolveFontPath()
	local name = db and db.fontFamily
	if name and name:find("\\", 1, false) then
		return name -- direct path (built-in fallback entries)
	end
	local lsm = GetLSM()
	if lsm and name then
		local path = lsm:Fetch("font", name, true)
		if path then return path end
	end
	return FONT
end

local function ApplyFont(fs, size)
	local flags = db and db.fontOutline
	if not flags or flags == "" then flags = nil end
	fs:SetFont(ResolveFontPath(), size or (db and db.fontSize) or 12, flags)
end

-- ============================================================== utils

local function CopyDefaults(src, dst)
	if type(src) ~= "table" then return dst end
	if type(dst) ~= "table" then dst = {} end
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = CopyDefaults(v, type(dst[k]) == "table" and dst[k] or {})
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

local function Clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function Money()
	if GetMoney then return GetMoney() end
	return 0
end

local function CoinString(copper, signed)
	local neg = copper < 0
	local abs = math.abs(copper)
	local g = math.floor(abs / 10000)
	local s = math.floor((abs % 10000) / 100)
	local c = abs % 100
	local out = {}
	if signed then
		out[#out + 1] = neg and "|cffff6060-" or "|cff60ff60+"
	end
	if g > 0 then
		out[#out + 1] = string.format(" %d|T%s:12:12|t", g, COIN.gold)
	end
	if s > 0 or g > 0 then
		out[#out + 1] = string.format(" %d|T%s:12:12|t", s, COIN.silver)
	end
	out[#out + 1] = string.format(" %d|T%s:12:12|t", c, COIN.copper)
	return table.concat(out)
end

local function QualityColor(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function HexColor(r, g, b)
	return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- ============================================================== frame helpers

local function NewTex(parent, layer, r, g, b, a)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(WHITE)
	t:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
	return t
end

-- size of one physical screen pixel in this frame's own coordinates
local function PixelSize(frame)
	local factor
	if PixelUtil and PixelUtil.GetPixelToUIUnitFactor then
		factor = PixelUtil.GetPixelToUIUnitFactor()
	else
		local _, h = GetPhysicalScreenSize()
		factor = 768 / ((h and h > 0) and h or 768)
	end
	local scale = frame:GetEffectiveScale()
	if not scale or scale <= 0 then scale = 1 end
	return factor / scale
end

-- round to the pixel grid (even=true keeps an even pixel count so a CENTER
-- anchor doesn't put the edges on half pixels)
local function Snap(v, px, even)
	local n = math.floor(v / px + 0.5)
	if even and n % 2 == 1 then n = n + 1 end
	return n * px
end

-- lay the four border lines out exactly one physical pixel thick
local function SizeBorder(frame)
	local t = frame._b
	if not t then return end
	local px = PixelSize(frame)
	local top, bottom, left, right = t[1], t[2], t[3], t[4]
	for _, tex in ipairs(t) do
		tex:ClearAllPoints()
		if tex.SetSnapToPixelGrid then
			tex:SetSnapToPixelGrid(false)
			tex:SetTexelSnappingBias(0)
		end
	end
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(px)
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	bottom:SetHeight(px)
	left:SetPoint("TOPLEFT", 0, -px)
	left:SetPoint("BOTTOMLEFT", 0, px)
	left:SetWidth(px)
	right:SetPoint("TOPRIGHT", 0, -px)
	right:SetPoint("BOTTOMRIGHT", 0, px)
	right:SetWidth(px)
end

-- 1px border made of four textures
local function SetBorder(frame, r, g, b, a)
	if not frame._b then
		frame._b = {
			NewTex(frame, "BORDER"), NewTex(frame, "BORDER"),
			NewTex(frame, "BORDER"), NewTex(frame, "BORDER"),
		}
		SizeBorder(frame)
	end
	for _, t in ipairs(frame._b) do
		t:SetVertexColor(r, g, b, a)
	end
end

-- ============================================================== bar pool

local bars = {}
local pool = {}

local function Layout()
	local step = db.height + db.gap
	for i, b in ipairs(bars) do
		local off = (i - 1) * step
		if db.growth == "DOWN" then off = -off end
		b.targetY = db.y + off
	end
end

local function RemoveBar(index)
	local b = table.remove(bars, index)
	if b then
		b.frame:Hide()
		b.frame:ClearAllPoints()
		pool[#pool + 1] = b
		Layout()
	end
end

local function BuildBar()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(db.width, db.height)
	f:SetFrameStrata("MEDIUM")
	f:SetAlpha(0)

	local b = { frame = f }

	b.glow = NewTex(f, "BACKGROUND", 1, 1, 1, 0)
	b.glow:SetPoint("TOPLEFT", -6, 6)
	b.glow:SetPoint("BOTTOMRIGHT", 6, -6)

	-- bar: backdrop, square icon flush left, 1px border
	b.bg = NewTex(f, "BACKGROUND", 0, 0, 0, 1)
	b.bg:SetAllPoints()

	-- explicit sublevel so nothing on ARTWORK can end up drawn over the icon
	b.icon = f:CreateTexture(nil, "ARTWORK", nil, 2)
	b.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94) -- crop the icon's built-in edge

	-- bag count in the icon's bottom-left corner
	b.count = f:CreateFontString(nil, "OVERLAY")
	b.count:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMLEFT", 1, 1)
	b.count:SetJustifyH("LEFT")

	b.name = f:CreateFontString(nil, "OVERLAY")
	ApplyFont(b.name)
	b.name:SetJustifyH("LEFT")
	b.name:SetWordWrap(false)
	if b.name.SetMaxLines then b.name:SetMaxLines(1) end
	b.name:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)

	b.right = f:CreateFontString(nil, "OVERLAY")
	ApplyFont(b.right)
	b.right:SetJustifyH("RIGHT")
	-- never wrap: a wrapped price spills above and below the bar
	b.right:SetWordWrap(false)
	if b.right.SetMaxLines then b.right:SetMaxLines(1) end
	b.right:SetPoint("RIGHT", -5, 0)

	-- price row: separate number + coin texture per denomination, laid out
	-- right-to-left. Inline |T|t icons in one string get mis-measured by this
	-- client and either overflow the bar or get truncated.
	b.coinParts = {}
	for i = 1, 3 do
		local t = f:CreateFontString(nil, "OVERLAY")
		ApplyFont(t)
		t:SetWordWrap(false)
		local ic = f:CreateTexture(nil, "OVERLAY")
		b.coinParts[i] = { text = t, icon = ic }
	end

	SetBorder(f, 0, 0, 0, 1)
	return b
end

local function SizeBar(b)
	b.frame:SetScale(db.scale)
	local px = PixelSize(b.frame)
	b.px = px
	local w, h = Snap(db.width, px, true), Snap(db.height, px, true)
	b.frame:SetSize(w, h)
	SizeBorder(b.frame)
	-- icon sits inside the 1px border
	b.icon:ClearAllPoints()
	b.icon:SetPoint("TOPLEFT", px, -px)
	b.icon:SetPoint("BOTTOMLEFT", px, px)
	b.icon:SetWidth(h - 2 * px)
	b.count:SetFont(COUNT_FONT, math.max(8, math.floor(db.height * 0.55 + 0.5)), "THICKOUTLINE")
end

local function AcquireBar()
	local b = table.remove(pool)
	if not b then b = BuildBar() end

	-- clear state left over from the bar's previous use
	b.kind, b.key, b.stacks, b.amount, b.price = nil, nil, nil, nil, nil
	b.quality, b.quest, b.pending, b.dying = nil, nil, nil, nil
	b.displayName, b.nameText, b.nameColor, b.rightText, b.iconTexture = nil, nil, nil, nil, nil
	b.coinValue = nil
	b.countText, b.forceQuest = nil, nil

	SizeBar(b)
	b.frame:SetAlpha(1)
	return b
end

local function ApplyBackdrop(b)
	if b.kind == "lost" then
		b.bg:SetVertexColor(0.45, 0.02, 0.02, 0.75)
		return
	end
	-- optional: tint uncommon+ and quest items in their own colour (darkened so the
	-- same-coloured name stays readable)
	if db.qualitybg and b.kind == "loot" and (b.quest or (b.quality or 1) >= 2) then
		local cr, cg, cb
		if b.quest then
			cr, cg, cb = 1, 0.82, 0
		else
			cr, cg, cb = QualityColor(b.quality)
		end
		b.bg:SetVertexColor(cr * 0.4, cg * 0.4, cb * 0.4, 0.75)
		return
	end
	local r, g, bl, a = 0, 0, 0, 0.55
	if db.darkmode and not db.lightmode then
		r, g, bl, a = 0, 0, 0, 0.65
	elseif db.lightmode and not db.darkmode then
		r, g, bl, a = 1, 1, 1, 0.65
	end
	b.bg:SetVertexColor(r, g, bl, a)
end

local function PriceIconSize()
	return ((db and db.fontSize) or 13) + 2
end

-- price layout: "12<g> 5<s> 3<c>" in bronze; returns the leftmost
-- region so the name can stop in front of it, or nil when there is no price
local function LayoutCoins(b)
	local parts = b.coinParts
	for _, p in ipairs(parts) do
		p.text:Hide(); p.icon:Hide()
		p.text:ClearAllPoints(); p.icon:ClearAllPoints()
	end
	local value = b.coinValue
	if not value or value <= 0 then return nil end

	local c = value % 100
	local s = math.floor(value / 100) % 100
	local g = math.floor(value / 10000)
	local list
	if g > 0 then
		list = { { g, COIN.gold }, { s, COIN.silver }, { c, COIN.copper } }
	elseif s > 0 then
		list = { { s, COIN.silver }, { c, COIN.copper } }
	else
		list = { { c, COIN.copper } }
	end

	local sz = PriceIconSize()
	local anchor, point, off = b.frame, "RIGHT", -5
	local n = #list
	for i = n, 1, -1 do
		local p = parts[n - i + 1]
		p.icon:SetTexture(list[i][2])
		p.icon:SetSize(sz, sz)
		p.icon:SetPoint("RIGHT", anchor, point, off, 0)
		p.text:SetText(PRICE_COLOR .. list[i][1] .. "|r")
		p.text:SetPoint("RIGHT", p.icon, "LEFT", -1, 0)
		p.icon:Show(); p.text:Show()
		anchor, point, off = p.text, "LEFT", -4
	end
	return anchor
end

local function Render(b)
	local r, g, bl = 1, 1, 1
	local q = b.quality or 1

	if b.kind == "loot" or b.kind == "lost" then
		r, g, bl = QualityColor(q)
	elseif b.kind == "money" then
		r, g, bl = 1, 0.82, 0.1
	else
		r, g, bl = 0.55, 0.4, 1
	end

	ApplyBackdrop(b)

	b.glow:SetVertexColor(r, g, bl, db.glow and 0.35 or 0)
	b.glow:SetShown(db.glow)

	-- GetItemInfo returns itemTexture as a *string* on this client; SetTexture()
	-- needs a number for texture ids, so normalise before handing it over
	local icon = b.iconTexture
	if type(icon) == "string" then
		icon = tonumber(icon) or icon   -- numeric string -> number, path -> unchanged
	end
	b.icon:SetTexture(icon or 134400)

	local name = b.nameText or b.displayName or "?"

	local marker = ""
	if b.quest and db.questmark ~= false then
		-- Blizzard's yellow quest-giver "!" icon, sized to the name font
		local sz = (db.fontSize or 12) + 2
		marker = "|TInterface\\GossipFrame\\AvailableQuestIcon:" .. sz .. ":" .. sz .. "|t "
	end

	if b.nameColor then
		-- colour codes need the full 8 hex digits: |cAARRGGBB
		b.name:SetText(marker .. "|cff" .. b.nameColor .. name .. "|r")
	else
		b.name:SetText(marker .. name)
	end

	b.count:SetText(b.countText or "")

	-- right side: coin row for prices/money, plain text otherwise (XP)
	local leftmost = LayoutCoins(b)
	b.name:ClearAllPoints()
	b.name:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
	if leftmost then
		b.right:SetText("")
		b.right:Hide()
		b.name:SetPoint("RIGHT", leftmost, "LEFT", -8, 0)
	else
		b.right:SetText(b.rightText or "")
		b.right:Show()
		b.name:SetPoint("RIGHT", b.right, "LEFT", -8, 0)
	end
end

local function ShortNumber(n)
	if AbbreviateNumbers then return AbbreviateNumbers(n) end
	if n >= 1000000 then return string.format("%.1fM", math.floor(n / 100000) / 10) end
	if n >= 1000 then return string.format("%.1fK", math.floor(n / 100) / 10) end
	return tostring(n)
end

local function BagCount(id)
	if not _GetItemCount then return nil end
	local ok, n = pcall(_GetItemCount, id)
	if ok and type(n) == "number" and n > 0 then return n end
	return nil
end

-- ============================================================== entries

local function FindBar(kind, key)
	for _, b in ipairs(bars) do
		if b.kind == kind and not b.dying and (key == nil or b.key == key) then
			return b
		end
	end
end

local function ShowEntry(b)
	b.age = 0
	b.dying = nil
	SizeBar(b)
	b.frame:Show()
	table.insert(bars, 1, b)
	while #bars > db.maxbars do
		RemoveBar(#bars)
	end
	Layout()
	b.curY = b.targetY + (db.growth == "DOWN" and 10 or -10)
	local px = b.px or 1
	b.frame:SetPoint(db.anchorPoint, UIParent, db.anchorPoint, Snap(db.x, px), Snap(b.curY, px))
	b.frame:SetAlpha(0)
	Render(b)
end

local QUEST_ITEM_CLASS = 12 -- Enum.ItemClass.Questitem

local function ItemData(id)
	local name, quality, icon, sellPrice, classID

	if _GetItemInfo then
		local n, _, q, _, _, cls, _, _, _, i, sp = _GetItemInfo(id)
		name, quality, icon, sellPrice, classID = n, q, i, sp, cls
	end

	if not icon and _GetItemInfoInstant then
		local _, itype, _, _, i = _GetItemInfoInstant(id)
		icon = i
		if type(itype) == "string" and itype == "Quest" then
			classID = QUEST_ITEM_CLASS
		end
	end

	if not name and _RequestItemData then
		_RequestItemData(id)
	end

	-- modern clients return a numeric classID, older ones a "Quest" string
	local quest = (classID == QUEST_ITEM_CLASS) or (classID == "Quest")
	return name, quality or 1, icon, sellPrice or 0, quest
end

local function UpdateLootBar(b)
	local name, quality, icon, sellPrice, quest = ItemData(b.key)

	if name then
		b.displayName = name
		b.quality = quality
		b.iconTexture = icon or b.iconTexture
		b.price = sellPrice
		b.quest = quest or b.forceQuest
		b.pending = nil
		local r, g, bl = QualityColor(quality)
		b.nameColor = HexColor(r, g, bl)
	else
		b.pending = true
		b.displayName = b.displayName or ("Item " .. tostring(b.key))
		b.iconTexture = b.iconTexture or icon
	end

	local name = b.displayName
	if #name > 35 then name = name:sub(1, 35) .. "..." end
	-- always show the looted amount, even x1
	b.nameText = name .. "|cff00ff00 x" .. (b.stacks or 1) .. "|r"

	-- icon shows how many you now have in bags (refreshed on BAG_UPDATE_DELAYED)
	local have = b.kind == "loot" and BagCount(b.key) or nil
	b.countText = have and tostring(have) or nil

	b.coinValue = b.price
	b.rightText = nil
	Render(b)
end

local function AddLoot(itemID, count, forceQuest)
	count = count or 1
	local _, quality, _, _, quest = ItemData(itemID)
	quest = quest or forceQuest
	if not quest and db.rarity[(quality or 1) + 1] == false then return end

	local b = FindBar("loot", itemID)
	if b then
		b.stacks = (b.stacks or 1) + count
		b.age = 0
	else
		b = AcquireBar()
		b.kind = "loot"
		b.key = itemID
		b.stacks = count
		b.pending = true
		b.forceQuest = forceQuest
		ShowEntry(b)
	end

	UpdateLootBar(b)
end

-- item that stayed in the loot window (bags full, closed early, ...)
local function AddUnlooted(itemID, count, forceQuest)
	if not db.unlooted then return end
	count = count or 1
	local _, quality, _, _, quest = ItemData(itemID)
	quest = quest or forceQuest
	if not quest and db.rarity[(quality or 1) + 1] == false then return end

	local b = FindBar("lost", itemID)
	if b then
		b.stacks = (b.stacks or 1) + count
		b.age = 0
	else
		b = AcquireBar()
		b.kind = "lost"
		b.key = itemID
		b.stacks = count
		b.pending = true
		b.forceQuest = forceQuest
		ShowEntry(b)
	end

	UpdateLootBar(b)
end

local function AddMoney(delta)
	if not db.currency or not delta or delta == 0 then return end
	local b = FindBar("money")
	if b then
		b.amount = (b.amount or 0) + delta
		b.age = 0
	else
		b = AcquireBar()
		b.kind = "money"
		b.key = "money"
		b.quality = 1
		b.nameText = "Coins"
		b.nameColor = HexColor(QualityColor(1))
		b.amount = delta
		ShowEntry(b)
	end
	local absAmount = math.abs(b.amount)
	b.iconTexture = COIN_ICON_SMALL
	if absAmount > 99 then b.iconTexture = COIN_ICON_MEDIUM end
	if absAmount > 9999 then b.iconTexture = COIN_ICON_LARGE end
	b.coinValue = b.amount
	b.rightText = nil
	Render(b)
end

local function AddXP(amount, isQuest)
	if not db.experience or not amount or amount <= 0 then return end
	local key = isQuest and "xp_quest" or "xp_creature"
	local b = FindBar("xp", key)
	if b then
		b.amount = b.amount + amount
		b.age = 0
	else
		b = AcquireBar()
		b.kind = "xp"
		b.key = key
		b.quality = 1
		b.iconTexture = XP_ICON
		b.nameText = "Experience"
		b.nameColor = "ffffff"
		b.amount = amount
		ShowEntry(b)
	end
	-- XP total on the right side, like loot/money prices
	b.countText = nil
	b.rightText = string.format("|cff60ff60+%d|r", b.amount)
	Render(b)
end

-- ============================================================== mover

local function RefreshLayout()
	for _, b in ipairs(bars) do
		SizeBar(b)
		ApplyFont(b.name)
		ApplyFont(b.right)
		for _, p in ipairs(b.coinParts) do ApplyFont(p.text) end
		Render(b)
	end
	if mover and mover.title then
		ApplyFont(mover.title, 12)
		ApplyFont(mover.hint, 10)
	end
	Layout()
end

local function BuildMover()
	if mover then
		mover:SetShown(db.unlocked)
		return
	end
	mover = CreateFrame("Frame", "EnhancedLootMover", UIParent)
	mover:SetSize(220, 46)
	mover:SetPoint(db.anchorPoint, UIParent, db.anchorPoint, db.x, db.y)
	mover:SetFrameStrata("DIALOG")
	mover:SetMovable(true)
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:SetClampedToScreen(true)

	local bg = NewTex(mover, "BACKGROUND", 0.1, 0.1, 0.12, 0.85)
	bg:SetAllPoints()
	SetBorder(mover, 1, 0.82, 0.1, 1)

	local t = mover:CreateFontString(nil, "OVERLAY")
	mover.title = t
	ApplyFont(t, 12)
	t:SetPoint("CENTER", 0, 8)
	t:SetText("Enhanced Loot")
	t:SetTextColor(1, 0.82, 0.1)

	local h = mover:CreateFontString(nil, "OVERLAY")
	mover.hint = h
	ApplyFont(h, 10)
	h:SetPoint("CENTER", 0, -8)
	h:SetText("drag me  ·  /el lock")
	h:SetTextColor(0.7, 0.7, 0.7)

	mover:SetScript("OnDragStart", function(self) self:StartMoving() end)
	mover:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		db.anchorPoint, db.x, db.y = point, x, y
		self:ClearAllPoints()
		self:SetPoint(point, UIParent, point, x, y)
		RefreshLayout()
	end)

	mover:SetShown(db.unlocked)
end

-- ============================================================== driver

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, dt)
	if not db or #bars == 0 then return end
	for i = #bars, 1, -1 do
		local b = bars[i]
		b.age = b.age + dt

		if not b.dying and b.age >= db.duration then
			b.dying = 0
		end

		local a
		if b.dying then
			b.dying = b.dying + dt
			a = 1 - (b.dying / db.fadeOut)
		elseif b.age < db.fadeIn then
			a = b.age / db.fadeIn
		else
			a = 1
		end

		b.frame:SetAlpha(Clamp(a, 0, 1) * db.alpha)

		if b.dying and b.dying >= db.fadeOut then
			RemoveBar(i)
		else
			local k = Clamp(dt * 14, 0, 1)
			b.curY = b.curY + (b.targetY - b.curY) * k
			local px = b.px or 1
	b.frame:SetPoint(db.anchorPoint, UIParent, db.anchorPoint, Snap(db.x, px), Snap(b.curY, px))
			if db.glow then
				b.glow:SetAlpha(0.25 + 0.12 * math.sin(GetTime() * 4))
			end
		end
	end
end)

-- ============================================================== events

local events = CreateFrame("Frame")
local lastMoney = 0

local ConsumeLooted -- defined with the loot-window tracking below

-- Turn a client format string ("You receive loot: %sx%d.") into a Lua pattern,
-- so parsing works in every client language.
local function PatternFromFormat(fmt)
	if type(fmt) ~= "string" or fmt == "" then return nil end
	local p = fmt:gsub("%%%d?%$?s", "\001"):gsub("%%%d?%$?d", "\002")
	p = p:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	p = p:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
	return "^" .. p
end

local function Patterns(...)
	local list = {}
	for i = 1, select("#", ...) do
		local pat = PatternFromFormat((select(i, ...)))
		if pat then list[#list + 1] = pat end
	end
	return list
end

-- own-loot templates; the *_MULTIPLE ones must be tried first
local SELF_LOOT_MULTI = Patterns(LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_CREATED_SELF_MULTIPLE)
local SELF_LOOT = Patterns(LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_CREATED_SELF)
-- "%s dies, you gain %d experience." (rested/group bonus text only follows it)
local XP_KILL = Patterns(COMBATLOG_XPGAIN_FIRSTPERSON)

-- CHAT_MSG_LOOT payload after the text: playerName(1) ... playerName2(4) ...
-- guid(11). true/false when it says who looted, nil when it doesn't.
local function LootedByPlayer(...)
	local guid = select(11, ...)
	local me = UnitGUID and UnitGUID("player")
	if type(guid) == "string" and guid ~= "" and me then
		return guid == me
	end
	local who = select(4, ...)
	if type(who) ~= "string" or who == "" then who = select(1, ...) end
	if type(who) == "string" and who ~= "" then
		return who:match("^[^%-]+") == UnitName("player") -- strip "-Realm"
	end
	return nil
end

local function OnLoot(msg, ...)
	if type(msg) ~= "string" then return end
	local id = tonumber(msg:match("item:(%d+)"))
	if not id then return end

	local count, selfMsg
	for _, pat in ipairs(SELF_LOOT_MULTI) do
		local _, n = msg:match(pat)
		if n then count, selfMsg = tonumber(n), true; break end
	end
	if not selfMsg then
		for _, pat in ipairs(SELF_LOOT) do
			if msg:match(pat) then count, selfMsg = 1, true; break end
		end
	end

	local mine = LootedByPlayer(...)
	if mine == nil then mine = selfMsg end
	if not mine then return end

	-- fallback count: first number after the item link ("...|h|rx3.")
	count = count or tonumber(msg:match("|h|r[^%d|]*(%d+)")) or 1
	ConsumeLooted(id, count)
	AddLoot(id, count)
end

local function OnMoney()
	local money = Money()
	local delta = money - lastMoney
	lastMoney = money
	if delta > 0 then AddMoney(delta) end
end

local function OnXP(msg)
	if type(msg) ~= "string" then return end
	for _, pat in ipairs(XP_KILL) do
		local _, n = msg:match(pat)
		if n then
			AddXP(tonumber(n), false)
			return
		end
	end
	-- not a kill: quest, exploration, ... (first number is the amount)
	local amount = tonumber(msg:match("(%d+)"))
	if not amount then return end
	local quest
	if #XP_KILL > 0 then
		quest = true
	else -- client has no template: old English heuristic
		quest = msg:lower():find("quest", 1, true) ~= nil
	end
	AddXP(amount, quest)
end

-- snapshot the loot window when it opens, drop slots as they get looted,
-- and on close report whatever is still left
local lootSlots = {}
local lootCleared = {} -- slots already taken this loot session
local reported = {} -- "sourceGUID:itemID" -> GetTime(), so re-opening a corpse doesn't repeat

local function SnapshotLoot()
	if not GetNumLootItems then return end
	local n = GetNumLootItems() or 0
	for slot = 1, n do
		if not lootSlots[slot] and not lootCleared[slot] then
			local isItem = true
			if GetLootSlotType then
				local t = GetLootSlotType(slot)
				isItem = (t == 1) or (Enum and Enum.LootSlotType and t == Enum.LootSlotType.Item)
			end
			local link = isItem and GetLootSlotLink and GetLootSlotLink(slot)
			local id = link and tonumber(link:match("item:(%d+)"))
			if id then
				local _, _, quantity, _, _, locked, isQuestItem = GetLootSlotInfo(slot)
				local source = GetLootSourceInfo and GetLootSourceInfo(slot)
				lootSlots[slot] = {
					id = id,
					count = (quantity and quantity > 0) and quantity or 1,
					locked = locked, -- group roll / not ours to take
					quest = isQuestItem,
					source = source or "?",
					bag = BagCount(id) or 0, -- bag count before looting
				}
			end
		end
	end
end

-- Fast autoloot can close the window before LOOT_SLOT_CLEARED / the loot chat
-- line arrive, so leftovers are only *candidates* at LOOT_CLOSED. They are
-- confirmed after a short grace period, and dropped if the item turned up in
-- the loot chat or in the bags meanwhile.
local LOST_GRACE = 1.5
local pendingLost = {}

ConsumeLooted = function(id, count)
	local left = count or 1
	for slot, info in pairs(lootSlots) do
		if left <= 0 then break end
		if info.id == id then
			local take = math.min(left, info.count)
			info.count = info.count - take
			left = left - take
			if info.count <= 0 then lootSlots[slot] = nil end
		end
	end
	for i = #pendingLost, 1, -1 do
		if left <= 0 then break end
		local info = pendingLost[i]
		if info.id == id then
			local take = math.min(left, info.count)
			info.count = info.count - take
			left = left - take
			if info.count <= 0 then table.remove(pendingLost, i) end
		end
	end
end

local function FlushUnlooted()
	if #pendingLost == 0 then return end
	local now = GetTime()
	for k, t in pairs(reported) do
		if now - t > 300 then reported[k] = nil end
	end
	for i = #pendingLost, 1, -1 do
		local info = pendingLost[i]
		if now - info.t >= LOST_GRACE then
			table.remove(pendingLost, i)
			local gained = (BagCount(info.id) or 0) - info.bag
			local missing = info.count - math.max(0, gained)
			local key = info.source .. ":" .. info.id
			if missing > 0 and not reported[key] then
				reported[key] = now
				AddUnlooted(info.id, missing, info.quest)
			end
		end
	end
end

local function ReportUnlooted()
	local now = GetTime()
	for _, info in pairs(lootSlots) do
		if not info.locked and info.count > 0 then
			info.t = now
			pendingLost[#pendingLost + 1] = info
		end
	end
	wipe(lootSlots)
	wipe(lootCleared)
end

local lostTicker = CreateFrame("Frame")
local lostElapsed = 0
lostTicker:SetScript("OnUpdate", function(_, dt)
	lostElapsed = lostElapsed + dt
	if lostElapsed < 0.25 then return end
	lostElapsed = 0
	if db then FlushUnlooted() end
end)

events:RegisterEvent("LOOT_READY")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_SLOT_CLEARED")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CHAT_MSG_LOOT")
events:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")

events:SetScript("OnEvent", function(_, event, arg1, ...)
	if event == "ADDON_LOADED" and arg1 == "EnhancedLoot" then
		EnhancedLootDB = CopyDefaults(defaults, EnhancedLootDB or {})
		db = EnhancedLootDB
		ns.db = db
	elseif event == "PLAYER_LOGIN" then
		if not db then
			EnhancedLootDB = CopyDefaults(defaults, EnhancedLootDB or {})
			db = EnhancedLootDB
			ns.db = db
		end
		lastMoney = Money()
		local path = GameFontNormal:GetFont()
		if path and path ~= "" then FONT = path end
		BuildMover()
		if ns.RegisterOptions then ns.RegisterOptions() end
	elseif event == "PLAYER_ENTERING_WORLD" then
		lastMoney = Money()
	elseif event == "CHAT_MSG_LOOT" then
		OnLoot(arg1, ...)
	elseif event == "PLAYER_MONEY" then
		OnMoney()
	elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
		OnXP(arg1)
	elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
		if db then RefreshLayout() end
	elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
		SnapshotLoot()
	elseif event == "LOOT_SLOT_CLEARED" then
		if arg1 then lootSlots[arg1] = nil; lootCleared[arg1] = true end
	elseif event == "LOOT_CLOSED" then
		ReportUnlooted()
	elseif event == "GET_ITEM_INFO_RECEIVED" or event == "BAG_UPDATE_DELAYED" then
		local all = event == "BAG_UPDATE_DELAYED"
		for _, b in ipairs(bars) do
			if (b.kind == "loot" and (all or b.pending)) or (b.kind == "lost" and b.pending) then
				UpdateLootBar(b)
			end
		end
	end
end)

-- ============================================================== slash

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100EnhancedLoot|r " .. tostring(msg))
end

local function Bool(v)
	v = tostring(v or ""):lower()
	return v == "on" or v == "1" or v == "true" or v == "yes"
end

local function Help()
	Print("commands:")
	Print("  /el duration <sec>")
	Print("  /el darkmode on|off   /el lightmode on|off")
	Print("  /el glow on|off")
	Print("  /el currency on|off   /el experience on|off")
	Print("  /el unlooted on|off     red bars for items left in the loot window")
	Print("  /el qualitybg on|off    tint green/blue/epic/legendary/quest item bars")
	Print("  /el rarity <0-6> on|off")
	Print("  /el questmark on|off    gold ! on quest items")
	Print("  /el font <name>         SharedMedia font family (/el fonts)")
	Print("  /el fontsize <n>        font size, 8-32")
	Print("  /el outline none|outline|thick")
	Print("  /el scale <n>   /el width <n>   /el height <n>")
	Print("  /el maxbars <n>  /el growth up|down")
	Print("  /el unlock | /el lock")
	Print("  /el | /el options       open the settings panel")
	Print("  /el help                this list")
	Print("  /el test | /el reset")
end

local handlers = {}
ns.handlers = handlers

function handlers.duration(v)
	db.duration = Clamp(tonumber(v) or db.duration, 0.5, 60)
	Print("duration = " .. db.duration)
end

function handlers.darkmode(v)
	db.darkmode = Bool(v)
	Print("darkmode = " .. tostring(db.darkmode))
	RefreshLayout()
end

function handlers.lightmode(v)
	db.lightmode = Bool(v)
	Print("lightmode = " .. tostring(db.lightmode))
	RefreshLayout()
end

function handlers.glow(v)
	db.glow = Bool(v)
	Print("glow = " .. tostring(db.glow))
	RefreshLayout()
end

function handlers.currency(v)
	db.currency = Bool(v)
	Print("currency = " .. tostring(db.currency))
end

function handlers.qualitybg(v)
	db.qualitybg = Bool(v)
	Print("qualitybg = " .. tostring(db.qualitybg))
	RefreshLayout()
end

function handlers.unlooted(v)
	db.unlooted = Bool(v)
	Print("unlooted = " .. tostring(db.unlooted))
end

function handlers.experience(v)
	db.experience = Bool(v)
	Print("experience = " .. tostring(db.experience))
end

function handlers.font(v)
	v = (v or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if v == "" then
		Print("usage: /el font <name> - see /el fonts")
		return
	end
	db.fontFamily = v
	Print("font = " .. v .. (ResolveFontPath() and "" or " (not found, using default)"))
	RefreshLayout()
end

function handlers.fontsize(v)
	db.fontSize = Clamp(tonumber(v) or db.fontSize, 8, 32)
	Print("fontsize = " .. db.fontSize)
	RefreshLayout()
end

local OUTLINE_VALUES = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }

function handlers.outline(v)
	local key = tostring(v or ""):lower()
	if OUTLINE_VALUES[key] == nil then
		Print("usage: /el outline none|outline|thick")
		return
	end
	db.fontOutline = OUTLINE_VALUES[key]
	Print("outline = " .. (key == "" and "none" or key))
	RefreshLayout()
end






function handlers.fonts()
	local lsm = GetLSM()
	local list = lsm and lsm:List("font")
	if list and #list > 0 then
		Print(("%d SharedMedia fonts:"):format(#list))
		for i, name in ipairs(list) do
			if i > 20 then
				Print(("  ... and %d more"):format(#list - 20))
				break
			end
			Print("  " .. name)
		end
	else
		Print("no SharedMedia fonts installed - using built-in fonts")
	end
end

function handlers.questmark(v)
	db.questmark = Bool(v)
	Print("questmark = " .. tostring(db.questmark))
	RefreshLayout()
end

function handlers.rarity(q, state)
	q = tonumber(q)
	if not q or q < 0 or q > 6 then
		Print("usage: /el rarity <0-6> on|off")
		return
	end
	db.rarity[q + 1] = Bool(state)
	Print(("rarity %d = %s"):format(q, tostring(db.rarity[q + 1])))
end

function handlers.scale(v)
	db.scale = Clamp(tonumber(v) or db.scale, 0.5, 3)
	Print("scale = " .. db.scale)
	RefreshLayout()
end

function handlers.width(v)
	db.width = Clamp(tonumber(v) or db.width, 120, 800)
	Print("width = " .. db.width)
	RefreshLayout()
end

function handlers.height(v)
	db.height = Clamp(tonumber(v) or db.height, 10, 80)
	Print("height = " .. db.height)
	RefreshLayout()
end

function handlers.maxbars(v)
	db.maxbars = Clamp(math.floor(tonumber(v) or db.maxbars), 1, 30)
	Print("maxbars = " .. db.maxbars)
end

function handlers.growth(v)
	v = tostring(v or ""):lower()
	if v ~= "up" and v ~= "down" then
		Print("usage: /el growth up|down")
		return
	end
	db.growth = v:upper()
	Print("growth = " .. db.growth)
	Layout()
end

function handlers.unlock()
	db.unlocked = true
	BuildMover()
	if mover then mover:Show() end
	Print("unlocked - drag the marker, then /el lock")
end

function handlers.lock()
	db.unlocked = false
	if mover then mover:Hide() end
	Print("locked")
end

local function Preview()
	AddLoot(2589, 3)          -- Linen Cloth
	AddLoot(723, 1, true)     -- Goretusk Liver, forced to show as a quest item
	AddLoot(19019, 1)         -- Thunderfury (legendary) for the quality tint
	AddMoney(12345)
	AddXP(350, false)
	AddUnlooted(2592, 2)      -- Wool Cloth, as if bags were full
end
ns.Preview = Preview

function handlers.test()
	Preview()
	Print("preview shown")
end

function handlers.options()
	if ns.OpenOptions then
		ns.OpenOptions()
	else
		Print("options panel is not available yet")
	end
end

function handlers.reset()
	EnhancedLootDB = CopyDefaults(defaults, {})
	db = EnhancedLootDB
	ns.db = db
	RefreshLayout()
	Print("defaults restored")
end

local function Dispatch(input)
	local cmd, rest = input:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")

	if cmd == "" then handlers.options(); return end
	if cmd == "help" then Help(); return end
	if cmd == "rarity" then
		local q, state = rest:match("^(%S+)%s*(%S*)$")
		handlers.rarity(q, state == "" and "on" or state)
		return
	end
	local fn = handlers[cmd]
	if not fn then
		Print("unknown command: " .. cmd .. " - try /el help")
		return
	end
	fn(rest)
end

SLASH_ENHANCEDLOOT1 = "/el"
SLASH_ENHANCEDLOOT2 = "/enhancedloot"
SlashCmdList["ENHANCEDLOOT"] = Dispatch

-- shared with Options.lua
ns.SetBorder = SetBorder
ns.GetLSM = GetLSM
ns.RefreshLayout = RefreshLayout
