-- Enhanced Loot
-- Standalone loot / money / XP gain bars.
-- Reimplementation of the "Enhanced_Loot" WeakAura (wago.io/UihWPxSyL) without WeakAuras.
-- Author: voidlol - https://github.com/voidlol/EnhancedLoot
-- Target: WoW Forever live client (1.60.x, Interface 16001), Lua 5.1.

local defaults = {
	duration    = 5,
	darkmode    = true,
	lightmode   = false,
	glow        = false,
	currency    = true,
	experience  = true,
	questmark   = true,
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
-- coin-pile icons the WeakAura used (copper / silver / gold amounts)
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

-- 1px border made of four textures
local function SetBorder(frame, r, g, b, a)
	if not frame._b then
		local top = NewTex(frame, "BORDER")
		top:SetPoint("TOPLEFT")
		top:SetPoint("TOPRIGHT")
		top:SetHeight(1)

		local bottom = NewTex(frame, "BORDER")
		bottom:SetPoint("BOTTOMLEFT")
		bottom:SetPoint("BOTTOMRIGHT")
		bottom:SetHeight(1)

		local left = NewTex(frame, "BORDER")
		left:SetPoint("TOPLEFT", 0, -1)
		left:SetPoint("BOTTOMLEFT", 0, 1)
		left:SetWidth(1)

		local right = NewTex(frame, "BORDER")
		right:SetPoint("TOPRIGHT", 0, -1)
		right:SetPoint("BOTTOMRIGHT", 0, 1)
		right:SetWidth(1)

		frame._b = { top, bottom, left, right }
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

	-- WeakAura look: solid black bar, square icon flush left, black border
	b.bg = NewTex(f, "BACKGROUND", 0, 0, 0, 1)
	b.bg:SetAllPoints()

	-- explicit sublevel so nothing on ARTWORK can end up drawn over the icon
	b.icon = f:CreateTexture(nil, "ARTWORK", nil, 2)
	b.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94) -- WA icon zoom 0.24
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMLEFT", 1, 1)

	-- stack / quantity count on the icon (WA "name" text at ICON_BOTTOMLEFT)
	b.count = f:CreateFontString(nil, "OVERLAY")
	b.count:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMLEFT", 1, 1)
	b.count:SetJustifyH("LEFT")

	b.name = f:CreateFontString(nil, "OVERLAY")
	ApplyFont(b.name)
	b.name:SetJustifyH("LEFT")
	b.name:SetWordWrap(false)
	b.name:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)

	b.right = f:CreateFontString(nil, "OVERLAY")
	ApplyFont(b.right)
	b.right:SetJustifyH("RIGHT")
	b.right:SetPoint("RIGHT", -5, 0)

	b.name:SetPoint("RIGHT", b.right, "LEFT", -8, 0)

	SetBorder(f, 0, 0, 0, 1)
	return b
end

local function SizeBar(b)
	b.frame:SetSize(db.width, db.height)
	b.frame:SetScale(db.scale)
	b.icon:SetWidth(db.height - 2)
	b.count:SetFont(COUNT_FONT, math.max(8, math.floor(db.height * 0.55 + 0.5)), "THICKOUTLINE")
end

local function AcquireBar()
	local b = table.remove(pool)
	if not b then b = BuildBar() end

	-- clear state left over from the bar's previous use
	b.kind, b.key, b.stacks, b.amount, b.price = nil, nil, nil, nil, nil
	b.quality, b.quest, b.pending, b.dying = nil, nil, nil, nil
	b.displayName, b.nameText, b.nameColor, b.rightText, b.iconTexture = nil, nil, nil, nil, nil
	b.countText, b.forceQuest = nil, nil

	SizeBar(b)
	b.frame:SetAlpha(1)
	return b
end

local function ApplyBackdrop(b)
	local r, g, bl, a = 0, 0, 0, 0.55
	if db.darkmode and not db.lightmode then
		r, g, bl, a = 0, 0, 0, 0.65
	elseif db.lightmode and not db.darkmode then
		r, g, bl, a = 1, 1, 1, 0.65
	end
	b.bg:SetVertexColor(r, g, bl, a)
end

local function Render(b)
	local r, g, bl = 1, 1, 1
	local q = b.quality or 1

	if b.kind == "loot" then
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
	b.right:SetText(b.rightText or "")
end

-- WeakAura price text: "12<g>  5<s>  3<c>" in bronze, single digits space-padded
local function PriceString(price)
	if not price or price <= 0 then return "" end
	local sz = ((db and db.fontSize) or 13) + 2
	local function icon(path) return "|T" .. path .. ":" .. sz .. "|t" end
	local c = price % 100
	local s = math.floor(price / 100) % 100
	local g = math.floor(price / 10000)
	local out
	if g > 0 then
		out = g .. icon(COIN.gold)
			.. (s < 10 and " " or "") .. s .. icon(COIN.silver)
			.. (c < 10 and " " or "") .. c .. icon(COIN.copper)
	elseif s > 0 then
		out = s .. icon(COIN.silver) .. (c < 10 and " " or "") .. c .. icon(COIN.copper)
	else
		out = c .. icon(COIN.copper)
	end
	return PRICE_COLOR .. out .. "|r"
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
	b.frame:SetSize(db.width, db.height)
	b.frame:SetScale(db.scale)
	b.frame:Show()
	table.insert(bars, 1, b)
	while #bars > db.maxbars do
		RemoveBar(#bars)
	end
	Layout()
	b.curY = b.targetY + (db.growth == "DOWN" and 10 or -10)
	b.frame:SetPoint(db.anchorPoint, UIParent, db.anchorPoint, db.x, b.curY)
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
	-- WA always shows the looted amount, even x1
	b.nameText = name .. "|cff00ff00 x" .. (b.stacks or 1) .. "|r"

	-- icon shows how many you now have in bags (refreshed on BAG_UPDATE_DELAYED)
	local have = BagCount(b.key)
	b.countText = have and tostring(have) or nil

	b.rightText = PriceString(b.price)
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
	b.rightText = PriceString(b.amount)
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
		b.quality = 4 -- WA paints the XP bar epic purple
		b.iconTexture = XP_ICON
		b.nameText = "Experience"
		b.nameColor = HexColor(QualityColor(4))
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
			b.frame:SetPoint(db.anchorPoint, UIParent, db.anchorPoint, db.x, b.curY)
			if db.glow then
				b.glow:SetAlpha(0.25 + 0.12 * math.sin(GetTime() * 4))
			end
		end
	end
end)

-- ============================================================== events

local events = CreateFrame("Frame")
local lastMoney = 0

local function OnLoot(msg)
	if type(msg) ~= "string" then return end
	local me = UnitName("player")
	if me and not msg:find(me, 1, true) and not msg:find("^You ") then return end

	local id = msg:match("item:(%d+)")
	if not id then return end
	id = tonumber(id)
	if not id then return end

	local count = tonumber(msg:match("|h%[.-%]|h|r x(%d+)")) or tonumber(msg:match("(%d+)%.$")) or 1
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
	local amount = tonumber(msg:match("(%d+)"))
	if not amount then return end
	AddXP(amount, msg:lower():find("quest", 1, true) ~= nil)
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CHAT_MSG_LOOT")
events:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("BAG_UPDATE_DELAYED")

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == "EnhancedLoot" then
		EnhancedLootDB = CopyDefaults(defaults, EnhancedLootDB or {})
		db = EnhancedLootDB
	elseif event == "PLAYER_LOGIN" then
		if not db then
			EnhancedLootDB = CopyDefaults(defaults, EnhancedLootDB or {})
			db = EnhancedLootDB
		end
		lastMoney = Money()
		local path = GameFontNormal:GetFont()
		if path and path ~= "" then FONT = path end
		BuildMover()
		if EnhancedLoot_RegisterOptions then EnhancedLoot_RegisterOptions() end
	elseif event == "PLAYER_ENTERING_WORLD" then
		lastMoney = Money()
	elseif event == "CHAT_MSG_LOOT" then
		OnLoot(arg1)
	elseif event == "PLAYER_MONEY" then
		OnMoney()
	elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
		OnXP(arg1)
	elseif event == "GET_ITEM_INFO_RECEIVED" or event == "BAG_UPDATE_DELAYED" then
		local all = event == "BAG_UPDATE_DELAYED"
		for _, b in ipairs(bars) do
			if b.kind == "loot" and (all or b.pending) then
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
	AddMoney(12345)
	AddXP(350, false)
end
EnhancedLoot_Preview = Preview

function handlers.test()
	Preview()
	Print("preview shown")
end

function handlers.options()
	if EnhancedLoot_OpenOptions then
		EnhancedLoot_OpenOptions()
	else
		Print("options panel is not available yet")
	end
end

function handlers.reset()
	EnhancedLootDB = CopyDefaults(defaults, {})
	db = EnhancedLootDB
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
		function() return db.duration end,
		function(v) db.duration = v end, nil,
		function(v) return string.format("%.1f s", v) end)
	y = y - 38

	w.scale = CreateSlider(panel, "Scale", 0.5, 2, 0.05, x, y,
		function() return db.scale end,
		function(v) db.scale = v end,
		function() RefreshLayout() end,
		function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
	y = y - 38

	w.width = CreateSlider(panel, "Width", 200, 600, 10, x, y,
		function() return db.width end,
		function(v) db.width = v end,
		function() RefreshLayout() end,
		function(v) return string.format("%d px", v) end)
	y = y - 38

	w.height = CreateSlider(panel, "Height", 14, 40, 1, x, y,
		function() return db.height end,
		function(v) db.height = v end,
		function() RefreshLayout() end,
		function(v) return string.format("%d px", v) end)
	y = y - 38

	w.maxbars = CreateSlider(panel, "Max bars", 1, 15, 1, x, y,
		function() return db.maxbars end,
		function(v) db.maxbars = v end, nil,
		function(v) return string.format("%d", v) end)

	-- two columns: Appearance | Show
	local colB = x + 300
	local yChecks = y - 42

	CreateHeader(panel, "Appearance", x, yChecks)
	CreateHeader(panel, "Show", colB, yChecks)
	yChecks = yChecks - 26

	w.darkmode = CreateCheck(panel, "Dark backdrop", x, yChecks,
		function() return db.darkmode end,
		function(v) db.darkmode = v end,
		function() RefreshLayout() end)

	w.currency = CreateCheck(panel, "Money gains", colB, yChecks,
		function() return db.currency end,
		function(v) db.currency = v end)
	yChecks = yChecks - 24

	w.lightmode = CreateCheck(panel, "Light backdrop", x, yChecks,
		function() return db.lightmode end,
		function(v) db.lightmode = v end,
		function() RefreshLayout() end)

	w.experience = CreateCheck(panel, "Experience gains", colB, yChecks,
		function() return db.experience end,
		function(v) db.experience = v end)
	yChecks = yChecks - 24

	w.glow = CreateCheck(panel, "Glow", x, yChecks,
		function() return db.glow end,
		function(v) db.glow = v end,
		function() RefreshLayout() end)

	w.questmark = CreateCheck(panel, "Quest marker (!)", colB, yChecks,
		function() return db.questmark ~= false end,
		function(v) db.questmark = v end,
		function() RefreshLayout() end)

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
			function() return db.rarity[q + 1] ~= false end,
			function(v) db.rarity[q + 1] = v end)
		rx = rx + 140
	end
	y = ry - 36

	CreateHeader(panel, "Font", x, y)
	y = y - 26

	w.fontFamily = CreateDropdown(panel, x, y, 240, FontItems,
		function() return db.fontFamily end,
		function(v)
			db.fontFamily = v
			RefreshLayout()
		end)

	w.fontOutline = CreateDropdown(panel, x + 252, y, 150,
		function() return OUTLINE_ITEMS end,
		function()
			for _, item in ipairs(OUTLINE_ITEMS) do
				if item.value == db.fontOutline then return item.name end
			end
			return "None"
		end,
		function(v)
			db.fontOutline = v
			RefreshLayout()
		end)

	y = y - 34

	w.fontSize = CreateSlider(panel, "Font size", 8, 32, 1, x, y,
		function() return db.fontSize end,
		function(v) db.fontSize = v end,
		function() RefreshLayout() end,
		function(v) return string.format("%d pt", v) end)

	y = y - 40

	CreateButton(panel, "Preview", x, y, function() EnhancedLoot_Preview() end)
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

function EnhancedLoot_OpenOptions()
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

function EnhancedLoot_RegisterOptions()
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
