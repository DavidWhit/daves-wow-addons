-- daves_sack / UI.lua
-- One combined bag window dressed in the same chrome as WoW's HUD Edit Mode
-- window: Blizzard's own translucent dialog border, centred white title and
-- close button, a Settings button in the toolbar that opens the Settings
-- window, a delete button beside that gear, and resize grips in the bottom
-- corners. Blizzard templates are used where
-- they exist so each client draws its native art; our own icons cover the rest.
--
-- Performance notes
--  * Item buttons are created once per bag slot and reused forever (pooled).
--  * BAG_UPDATE only marks bags dirty; work is batched into one pass per frame.
--  * Nothing is scanned or drawn while the window is closed; opening it
--    catches up on whatever changed.
--  * Only bags that actually changed are re-read, and the grid is only
--    re-laid-out when an item moved, appeared or disappeared (stack counts,
--    locks and cooldowns just repaint the affected button).

local _, ns = ...
local M = ns.MEDIA
local GetNumSlots, ReadSlot, Categorize = ns.GetNumSlots, ns.ReadSlot, ns.Categorize
local floor, ceil, max, min, abs, sort, find, format = math.floor, math.ceil, math.max, math.min, math.abs, table.sort, string.find, string.format
local ipairs, pairs, wipe = ipairs, pairs, wipe

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------
local TRIM   = { 0.23, 0.23, 0.25, 1 }     -- edge of common/empty slots
local REAGENT_TRIM = { 0.3, 0.45, 0.3, 1 } -- edge of empty reagent-bag slots: a hint of Blizzard's green bag art
local LINE   = { 1, 1, 1, 0.14 }           -- dividers
local SLOTBG = { 0.08, 0.08, 0.09, 1 }
local MUTED  = { 0.55, 0.55, 0.55, 1 }

local SLOT, GAP, PAD = 37, 5, 18
local HEADER_H, SECTION_GAP = 18, 10
local SUB_H, SUB_GAP = 14, 6           -- profession groups inside Reagents
local PLUS, MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"
local GROUP_NAMES = ns.GROUP_NAMES
-- Sections that can be split into sub-categories, and the setting for each.
local SPLIT_SETTING = { [ns.CAT_REAGENT] = "splitReagents", [ns.CAT_CONSUME] = "splitConsumables" }
local TOP_H, FOOT_H = 76, 44

local FREE_CAT = ns.NUM_CATEGORIES + 1
local SECTION_NAMES = {}
for i, n in ipairs(ns.CATEGORY_NAMES) do SECTION_NAMES[i] = n end
SECTION_NAMES[FREE_CAT] = "Free Space"

ns.TIPS = "Drag the window to move it. Drag a bottom corner to resize it. Click a section name to collapse it. Scroll with the mouse wheel or the bar on the right. Drag an item onto the delete button beside Settings to destroy it."
-- 8 is the narrowest width where Sort, Settings, the delete button and a usable
-- search box all fit, with the scrollbar gutter reserved.
local MIN_COLS, MAX_COLS = 8, 36
local MIN_VIEW = 3 * (SLOT + GAP)       -- the item area is never shorter than ~3 rows
ns.MIN_COLS, ns.MAX_COLS, ns.MIN_VIEW = MIN_COLS, MAX_COLS, MIN_VIEW

---------------------------------------------------------------------------
-- Pixel-perfect hairlines
-- A 1px line only survives if it lands exactly on a screen pixel. The window's
-- position, size and border insets are therefore all snapped to the physical
-- pixel grid, and every hairline is re-placed whenever the UI scale changes.
---------------------------------------------------------------------------
local px = 1                      -- one physical pixel, in this window's units
local hairlines = {}              -- { texture, owner, side, inset }

local function Snap(v) return floor(v / px + 0.5) * px end

local function Tex(parent, layer, sub, c)
	local t = parent:CreateTexture(nil, layer, nil, sub)
	t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
	return t
end

local function PlaceHairline(h)
	local t, f, side, inset = h[1], h[2], h[3], h[4]
	if side == 0 then t:SetHeight(px) return end           -- free-standing horizontal rule
	local i = Snap(inset)
	t:ClearAllPoints()
	if side == 1 then     t:SetPoint("TOPLEFT", f, i, -i);    t:SetPoint("TOPRIGHT", f, -i, -i);   t:SetHeight(px)
	elseif side == 2 then t:SetPoint("BOTTOMLEFT", f, i, i);  t:SetPoint("BOTTOMRIGHT", f, -i, i); t:SetHeight(px)
	elseif side == 3 then t:SetPoint("TOPLEFT", f, i, -i);    t:SetPoint("BOTTOMLEFT", f, i, i);   t:SetWidth(px)
	else                  t:SetPoint("TOPRIGHT", f, -i, -i);  t:SetPoint("BOTTOMRIGHT", f, -i, i); t:SetWidth(px) end
end

local function Hairline(t, f, side, inset)
	local h = { t, f, side, inset or 0 }
	hairlines[#hairlines + 1] = h
	PlaceHairline(h)
	return t
end

local function Rule(parent, layer, sub, c)
	return Hairline(Tex(parent, layer, sub, c), parent, 0)
end

-- Creates a frame from a Blizzard template if this client has it.
local function TryTemplate(kind, name, parent, template)
	local ok, f = pcall(CreateFrame, kind, name, parent, template)
	if ok and f then return f end
end

-- Gold / silver / copper with the real coin icons. Built by hand from the coin
-- art every client has shipped since 2004, so it never depends on which
-- version-specific money API exists (Retail moved its helper in 11.0).
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:14:14:2:0|t"
local GOLD_ICON, SILVER_ICON, COPPER_ICON = format(COIN, "Gold"), format(COIN, "Silver"), format(COIN, "Copper")
local Group = BreakUpLargeNumbers or tostring

local function MoneyString(m)
	m = m or 0
	local g, s, c = floor(m / 10000), floor(m / 100) % 100, m % 100
	local out = ""
	if g > 0 then out = Group(g) .. GOLD_ICON end
	if s > 0 then out = out .. (out ~= "" and "  " or "") .. s .. SILVER_ICON end
	if c > 0 or out == "" then out = out .. (out ~= "" and "  " or "") .. c .. COPPER_ICON end
	return out
end
ns.MoneyString = MoneyString

local function Sound(kit)
	if SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local frame, content, search, slotsText, barBg, barFill, money
local reagentText, reagentBarBg, reagentBarFill      -- footer: the reagent bag's own counter
local ahRow, ahValueText, ahTimeText, ahScanBarBg, ahScanBarFill  -- footer bottom row: cached AH bag value, status & scan progress bar
local ahBagValue, ahPricedStacks, ahTradeableStacks = 0, 0, 0
local AH_ROW_H = 18
local function AhRowOffset() return (ns.db and ns.db.showAuctionPrices ~= false) and AH_ROW_H or 0 end
local scroll, track, thumb, nativeBar, maxScroll = nil, nil, nil, nil, 0
local contentW, contentH = 1, 1
-- "Fit height to my items" fits when the bags open (or you change a setting /
-- collapse a section), then the size is locked while they stay open: new
-- items scroll instead of stretching the window.
local lockedViewH, refitHeight = nil, true
local tokens, numTokens, tokenButtons, footLine = {}, 0, {}, nil   -- backpack currencies
local bagBorder                                                     -- Blizzard's dialog border (Background setting)
local refitting, refitWidth = false, 0
local bagList, inList = {}, {}
local holders, buttons = {}, {}        -- holders[bag] = frame with ID = bag; buttons[bag][slot]
local sections, headers = {}, {}
for i = 1, FREE_CAT do sections[i] = {} end
local dirty, dirtyAll, layoutDirty = {}, true, true
local freeButton, freeCount, totalSlots = nil, 0, 0
local freeReagentButton, reagentFree, reagentTotal = nil, 0, 0   -- the reagent bag, counted apart
local counter = 0
local BAR_W, BAR_GAP = 120, 16

---------------------------------------------------------------------------
-- Item buttons
---------------------------------------------------------------------------
local HIDE_KEYS = { "IconBorder", "IconOverlay", "IconOverlay2", "NewItemTexture", "BattlepayItemTexture",
	"flash", "JunkIcon", "UpgradeIcon", "ItemContextOverlay", "IconQuestTexture", "ExtendedSlot" }

local function Skin(b)
	b.emptyBackgroundAtlas = nil      -- Retail would paint its own empty-slot art into the icon
	local name = b:GetName()
	b.fbIcon = b.icon or b.Icon or _G[name .. "IconTexture"]
	b.fbCount = b.Count or _G[name .. "Count"]
	b.fbCooldown = b.Cooldown or _G[name .. "Cooldown"]

	local nt = b:GetNormalTexture(); if nt then nt:SetAlpha(0) end
	for _, k in ipairs(HIDE_KEYS) do local r = b[k]; if r and r.SetAlpha then r:SetAlpha(0) end end
	local q = _G[name .. "IconQuestTexture"]; if q then q:SetAlpha(0) end

	local bg = b:CreateTexture(nil, "BACKGROUND", nil, -7)
	bg:SetTexture(M .. "slot"); bg:SetVertexColor(SLOTBG[1], SLOTBG[2], SLOTBG[3]); bg:SetAllPoints()

	local icon = b.fbIcon
	icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if b.CreateMaskTexture and icon.AddMaskTexture then
		local mask = b:CreateMaskTexture()
		mask:SetTexture(M .. "slot", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(icon)
		icon:AddMaskTexture(mask)
	end

	b.fbGlow = b:CreateTexture(nil, "OVERLAY", nil, 1)
	b.fbGlow:SetTexture(M .. "slotglow"); b.fbGlow:SetAllPoints(); b.fbGlow:SetBlendMode("ADD"); b.fbGlow:Hide()
	b.fbEdge = b:CreateTexture(nil, "OVERLAY", nil, 2)
	b.fbEdge:SetTexture(M .. "slotedge"); b.fbEdge:SetAllPoints()

	local hl = b:GetHighlightTexture()
	if hl then hl:SetTexture(M .. "slot"); hl:SetAllPoints(); hl:SetVertexColor(1, 1, 1, 0.12) end
	local pt = b:GetPushedTexture()
	if pt then pt:SetTexture(M .. "slot"); pt:SetAllPoints(); pt:SetVertexColor(1, 1, 1, 0.2) end

	if b.fbCount then b.fbCount:ClearAllPoints(); b.fbCount:SetPoint("BOTTOMRIGHT", -3, 3) end
	if b.fbCooldown then b.fbCooldown:ClearAllPoints(); b.fbCooldown:SetAllPoints(icon) end
end

local function NewButton(bag, slot)
	counter = counter + 1
	local name, parent = "DavesSackItem" .. counter, holders[bag]
	local ok, b = pcall(CreateFrame, "ItemButton", name, parent, "ContainerFrameItemButtonTemplate")
	if not ok then b = CreateFrame("Button", name, parent, "ContainerFrameItemButtonTemplate") end
	b:SetID(slot)              -- bag comes from the parent holder's ID (Blizzard's own fallback)
	b:SetSize(SLOT, SLOT)
	-- Blizzard's template pins item buttons to frame level 10; put them above
	-- our window so they, not the window, receive the mouse (tooltips, clicks).
	b:SetFrameLevel(frame:GetFrameLevel() + 5)   -- window +0, scroll +1, content +2, holder +3
	Skin(b)

	-- Tooltips/clicks stay entirely Blizzard's own handlers (no wrapping), so
	-- hovering and using items never runs through addon code (no taint).
	b.fbRec, b.fbKey, b.fbReagent = {}, bag * 100 + slot, ns.IsReagentBag(bag)
	b.pTex = false             -- forces the first paint
	return b
end

-- Only touches the cooldown widget when there is (or was) a cooldown to show.
local GetCD = ns.GetCooldown
local function SetCooldown(b, bag, slot)
	local cd = b.fbCooldown
	if not (cd and GetCD and CooldownFrame_Set) then return end
	if b.fbRec.id then
		local s, d, e = GetCD(bag, slot)
		local active = (d or 0) > 0
		if active or b.fbHasCD then CooldownFrame_Set(cd, s, d, e); b.fbHasCD = active end
	elseif b.fbHasCD then
		CooldownFrame_Set(cd, 0, 0, 0); b.fbHasCD = false
	end
end

-- Repaints only when something visible actually changed.
local function Paint(b)
	local r = b.fbRec
	if b.pTex == r.texture and b.pCount == r.count and b.pLock == r.locked and b.pQ == r.quality then return end
	b.pTex, b.pCount, b.pLock, b.pQ = r.texture, r.count, r.locked, r.quality
	-- Widget calls only, never Blizzard's SetItemButton* helpers: SetItemButtonCount writes button.count from
	-- addon code, and Blizzard reads that when you sell a refundable item back at a vendor (ContainerFrame.lua
	-- GetExtendedPriceString), which then runs tainted.
	local icon = b.fbIcon
	icon:SetTexture(r.texture); icon:SetShown(r.texture ~= nil)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetDesaturated(r.locked and true or false)
	local cnt = b.fbCount
	if cnt then
		local n = r.count or 0
		if n > 1 then
			cnt:SetText(GetFormattedItemQuantity and GetFormattedItemQuantity(n) or n)
			cnt:SetTextColor(1, 1, 1); cnt:Show()
		else
			cnt:Hide()
		end
	end
	local c = r.id and r.quality and r.quality >= 2 and ITEM_QUALITY_COLORS[r.quality]
	if c then
		b.fbEdge:SetVertexColor(c.r, c.g, c.b, 0.9)
		if r.quality >= 3 then b.fbGlow:SetVertexColor(c.r, c.g, c.b, 0.45); b.fbGlow:Show() else b.fbGlow:Hide() end
	else
		local trim = (not r.id and b.fbReagent) and REAGENT_TRIM or TRIM
		b.fbEdge:SetVertexColor(trim[1], trim[2], trim[3], 1)
		b.fbGlow:Hide()
	end
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------
local function SlotList(bag)
	local list = buttons[bag]
	if not list then
		local h = CreateFrame("Frame", nil, content)
		h:SetID(bag); h:SetSize(1, 1); h:SetPoint("TOPLEFT")
		holders[bag] = h
		list = { n = 0 }
		buttons[bag] = list
	end
	return list
end

-- Item buttons are made ahead, outside combat, for every slot of every bag we show (BetterBags does the same): a
-- ContainerFrameItemButtonTemplate button created during combat runs its clicks tainted, and using an item from it in
-- combat is blocked ("daves_sack tried to call UseContainerItem()"). That happened when the first opening after a
-- /reload was in combat. So scanning never creates one in combat; a slot without a button waits for combat to end.
local missedInCombat = false
local function MakeButtons(bag)
	if InCombatLockdown() then return end
	local list = SlotList(bag)
	for slot = 1, GetNumSlots(bag) or 0 do
		if not list[slot] then list[slot] = NewButton(bag, slot) end
	end
end

local function ScanBag(bag)
	local list = SlotList(bag)
	MakeButtons(bag)
	-- Buttons are made in slot order, so any missing (combat) are the last ones: show the ones that exist.
	local n = math.min(GetNumSlots(bag) or 0, #list)
	if n < (GetNumSlots(bag) or 0) then missedInCombat = true end
	if n ~= list.n then layoutDirty = true end
	for slot = 1, n do
		local b = list[slot]
		local rec = b.fbRec
		if ReadSlot(bag, slot, rec) or rec.recat then
			rec.recat = nil
			local cat, grp = Categorize(bag, slot, rec)
			if cat ~= b.fbCat or grp ~= b.fbGroup then b.fbCat, b.fbGroup = cat, grp; layoutDirty = true end
			if not cat then layoutDirty = true end
			SetCooldown(b, bag, slot)         -- item moved in: show its cooldown right away
		end
		Paint(b)
	end
	for slot = n + 1, #list do
		local b = list[slot]
		b:Hide(); b.fbRec.id, b.fbCat = nil, nil
	end
	list.n = n
end

-- Only plain bags count toward "free space" (not quivers, soul/herb bags or
-- the keyring). The reagent bag (modern client) gets its own count.
local GetFreeSlots = C_Container.GetContainerNumFreeSlots
local generalBag, reagentBag = {}, {}

local function SyncBagList()
	ns.BuildBagList(bagList)
	wipe(inList); wipe(generalBag); wipe(reagentBag)
	local normal = NUM_BAG_SLOTS or 4
	for _, bag in ipairs(bagList) do
		inList[bag] = true; dirty[bag] = true
		if bag >= 0 and bag <= normal then
			local _, family = GetFreeSlots(bag)
			generalBag[bag] = (family or 0) == 0
		elseif ns.IsReagentBag(bag) then
			reagentBag[bag] = (GetNumSlots(bag) or 0) > 0        -- equipped?
		end
	end
	for bag, list in pairs(buttons) do
		if not inList[bag] then for _, b in ipairs(list) do b:Hide() end; list.n = 0 end
	end
	layoutDirty = true
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local function SortCompare(a, b)
	local ra, rb = a.fbRec, b.fbRec
	local qa, qb = ra.quality or 0, rb.quality or 0
	if qa ~= qb then return qa > qb end
	local ca, cb = ra.classID or 99, rb.classID or 99
	if ca ~= cb then return ca < cb end
	local ia, ib = ra.id or 0, rb.id or 0
	if ia ~= ib then return ia < ib end
	if ra.count ~= rb.count then return ra.count > rb.count end
	return a.fbKey < b.fbKey
end

-- A sub-category switched off in Settings shows its items under the
-- section's "Other …" group instead.
local function EffGroup(b)
	local g = b.fbGroup or 99
	if ns.db.offGroups[g] then return ns.OtherGroupFor(g) end
	return g
end

-- Split sections: by sub-category first, then the normal order.
local function SortReagent(a, b)
	local ga, gb = EffGroup(a), EffGroup(b)
	if ga ~= gb then return ga < gb end
	return SortCompare(a, b)
end

local Layout
local subHeaders, usedSub = {}, {}

local function GetSubHeader(g)
	local h = subHeaders[g]
	if h then return h end
	h = CreateFrame("Button", nil, content)
	h:SetHeight(SUB_H)
	h.toggle = h:CreateTexture(nil, "ARTWORK")
	h.toggle:SetSize(11, 11); h.toggle:SetPoint("LEFT", 8, 0)
	h.label = h:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	h.label:SetPoint("LEFT", h.toggle, "RIGHT", 4, 0)
	h.label:SetText(GROUP_NAMES[g] or "Other")
	h.count = h:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	h.count:SetPoint("LEFT", h.label, "RIGHT", 5, 0)
	local hl = h:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture("Interface\\Buttons\\UI-PlusButton-Hilight"); hl:SetBlendMode("ADD"); hl:SetAllPoints(h.toggle)
	local key = "r" .. g
	h:SetScript("OnReceiveDrag", function() ns.StoreCursorItem() end)
	h:SetScript("OnClick", function()
		if CursorHasItem and CursorHasItem() then ns.StoreCursorItem() return end
		ns.db.collapsed[key] = (not ns.db.collapsed[key]) or nil
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		refitHeight = true                         -- you asked for it: re-fit
		Layout()
	end)
	subHeaders[g] = h
	return h
end

-- Lays out s[first..last] as a grid starting at y; returns the y below it.
local function PlaceGrid(s, first, last, y, cols)
	for i = first, last do
		local b, n = s[i], i - first
		local x = (n % cols) * (SLOT + GAP)
		local by = -(y + floor(n / cols) * (SLOT + GAP))
		if b.fbX ~= x or b.fbY ~= by then      -- only move buttons whose cell changed
			b.fbX, b.fbY = x, by
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", content, "TOPLEFT", x, by)
		end
		b:Show()
	end
	return y + ceil((last - first + 1) / cols) * (SLOT + GAP) - GAP
end

local function GetHeader(cat)
	local h = headers[cat]
	if h then return h end
	h = CreateFrame("Button", nil, content)
	h:SetHeight(HEADER_H)
	h.toggle = h:CreateTexture(nil, "ARTWORK")
	h.toggle:SetSize(14, 14); h.toggle:SetPoint("LEFT", -1, 0)
	h.label = h:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	h.label:SetPoint("LEFT", h.toggle, "RIGHT", 4, 0)
	h.label:SetText(SECTION_NAMES[cat])
	h.count = h:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	h.count:SetPoint("LEFT", h.label, "RIGHT", 6, 0)
	local hl = h:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture("Interface\\Buttons\\UI-PlusButton-Hilight"); hl:SetBlendMode("ADD"); hl:SetAllPoints(h.toggle)
	h.line = Rule(h, "ARTWORK", 0, LINE)
	h.line:SetPoint("LEFT", h.count, "RIGHT", 8, 0); h.line:SetPoint("RIGHT", 0, 0)
	h:SetScript("OnReceiveDrag", function() ns.StoreCursorItem() end)
	h:SetScript("OnClick", function()
		if CursorHasItem and CursorHasItem() then ns.StoreCursorItem() return end
		ns.db.collapsed[cat] = (not ns.db.collapsed[cat]) or nil
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		refitHeight = true                         -- you asked for it: re-fit
		Layout()
	end)
	headers[cat] = h
	return h
end

local function FillBar(fill, used, total, width)
	local f = total > 0 and used / total or 0
	fill:SetWidth(max(px, width * f))
	if f >= 1 then fill:SetColorTexture(0.9, 0.25, 0.2, 1)
	elseif f >= 0.9 then fill:SetColorTexture(1, 0.55, 0.1, 1)
	else fill:SetColorTexture(0.85, 0.85, 0.85, 1) end
end

-- Unique tradeable itemKeys currently in the player's bags (for a fast AH browse query on AUCTION_HOUSE_SHOW).
local seenTradeable = {}
function ns.BuildTradeableItemKeys(makeKey)
	if not makeKey then return nil end
	wipe(seenTradeable)
	local keys = {}
	local GetSlotInfo = C_Container and C_Container.GetContainerItemInfo
	for _, bag in ipairs(bagList) do
		if bag ~= KEYRING_CONTAINER then
			local list = buttons[bag]
			if list and list.n and list.n > 0 then
				for slot = 1, list.n do
					local b = list[slot]
					local r = b and b.fbRec
					local id = r and r.id
					if id and (r.count or 0) > 0 and not r.bound and b.fbCat ~= ns.CAT_QUEST and not seenTradeable[id] then
						seenTradeable[id] = true
						keys[#keys + 1] = makeKey(id)
					end
				end
			elseif GetSlotInfo then
				local num = GetNumSlots(bag) or 0
				for slot = 1, num do
					local info = GetSlotInfo(bag, slot)
					local id = info and info.itemID
					if id and (info.stackCount or 0) > 0 and not info.isBound and not seenTradeable[id] then
						local cat = ns.Categorise(id, info.hyperlink, bag, slot)
						if cat ~= ns.CAT_QUEST then
							seenTradeable[id] = true
							keys[#keys + 1] = makeKey(id)
						end
					end
				end
			end
		end
	end
	return keys
end

local lastAhShow
local function UpdateAuctionFooter()
	if not ahRow then return end
	local show = ns.db and ns.db.showAuctionPrices ~= false
	if show ~= lastAhShow then
		lastAhShow = show
		local off = show and AH_ROW_H or 0
		slotsText:ClearAllPoints(); slotsText:SetPoint("BOTTOMLEFT", PAD + 4, 24 + off)
		barBg:ClearAllPoints(); barBg:SetPoint("BOTTOMLEFT", PAD + 4, 14 + off)
		money:ClearAllPoints(); money:SetPoint("BOTTOMRIGHT", -PAD - 4, 17 + off)
		ahRow:SetShown(show)
	end
	if not show then return end

	local prices = ns.db and ns.db.ahPrices
	local total, priced, tradeable = 0, 0, 0
	for _, bag in ipairs(bagList) do
		if bag ~= KEYRING_CONTAINER then
			local list = buttons[bag]
			if list then
				for slot = 1, list.n do
					local b = list[slot]
					local r = b.fbRec
					if r.id and (r.count or 0) > 0 and not r.bound and b.fbCat ~= ns.CAT_QUEST then
						tradeable = tradeable + 1
						local p = prices and prices[r.id]
						if p and p > 0 then
							total = total + p * r.count
							priced = priced + 1
						end
					end
				end
			end
		end
	end
	ahBagValue, ahPricedStacks, ahTradeableStacks = total, priced, tradeable

	local hasCache = (ns.db and ns.db.ahUpdated) or (ns.ahCachedCount or 0) > 0
	local doneFlash = not ns.ahScanning and ns.ahScanDoneUntil and GetTime and GetTime() < ns.ahScanDoneUntil
	local scanText
	if ns.ahScanning then
		scanText = ns.ahScanProgress and format("|cffd4a94eCaching AH %d%%…|r", ns.ahScanProgress) or "|cffd4a94eCaching AH…|r"
	elseif doneFlash then
		scanText = "|cff5cd65cAH Cache Complete|r"
	end
	if hasCache then
		ahValueText:SetText(format("|cffd4a94eAH:|r %s", MoneyString(total)))
		if scanText then
			ahTimeText:SetText(scanText)
		else
			local age = ns.FormatAge and ns.FormatAge(ns.db.ahUpdated)
			ahTimeText:SetText(age and ("Updated " .. age) or "")
		end
	else
		ahValueText:SetText("|cff8c8c8cAH: Visit Auction House to cache prices|r")
		ahTimeText:SetText(scanText or "")
	end

	if ahScanBarBg and ahScanBarFill then
		if ns.ahScanning or doneFlash then
			local pct = doneFlash and 100 or max(5, min(100, ns.ahScanProgress or 15))
			local barW = max(40, (frame:GetWidth() or 300) - (PAD + 4) * 2)
			if doneFlash then
				ahScanBarFill:SetColorTexture(0.35, 0.82, 0.42, 1)
			else
				ahScanBarFill:SetColorTexture(0.85, 0.68, 0.25, 1)
			end
			ahScanBarFill:SetWidth(max(2, barW * pct / 100))
			ahScanBarBg:Show(); ahScanBarFill:Show()
		else
			ahScanBarBg:Hide(); ahScanBarFill:Hide()
		end
	end
end

-- Two counters side by side: your bags, then the reagent bag (only while one
-- is equipped). Nothing shrinks or overlaps: the window's minimum width is
-- measured from these strings and the gold (ns.MinColumns, below).
local lastUsed, lastTotal, lastRUsed, lastRTotal
local function UpdateFooter()
	UpdateAuctionFooter()
	local used, rUsed = totalSlots - freeCount, reagentTotal - reagentFree
	if used == lastUsed and totalSlots == lastTotal and rUsed == lastRUsed and reagentTotal == lastRTotal then return end
	lastUsed, lastTotal, lastRUsed, lastRTotal = used, totalSlots, rUsed, reagentTotal
	slotsText:SetText(format("%d |cff8c8c8c/|r %d", used, totalSlots))
	FillBar(barFill, used, totalSlots, BAR_W)
	if reagentTotal > 0 then
		reagentText:SetText(format("%d |cff8c8c8c/|r %d |cff8c8c8creagents|r", rUsed, reagentTotal))
		FillBar(reagentBarFill, rUsed, reagentTotal, BAR_W)
		reagentText:Show(); reagentBarBg:Show(); reagentBarFill:Show()
	else
		reagentText:Hide(); reagentBarBg:Hide(); reagentBarFill:Hide()
	end
end

---------------------------------------------------------------------------
-- Hard size limits. A width or height that can't show the window properly
-- is never allowed, however it's set (slider, corner grip, a saved value,
-- a reagent bag or another digit of gold arriving):
--  * at least enough columns for the footer: both counters and the gold
--    side by side, never overlapping, and never fewer than MIN_COLS
--    (the toolbar needs that floor too);
--  * at most the columns that fit on the screen;
--  * the item area at least ~3 rows, and at most what the screen leaves
--    under the toolbar and footer.
---------------------------------------------------------------------------
local function ScreenSize()
	local sc = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
	local w, h = UIParent:GetWidth() * sc, UIParent:GetHeight() * sc
	if w < 200 or h < 200 then return nil end        -- not sized yet (very early load)
	return w, h
end

function ns.MaxColumns()
	local screenW = ScreenSize()
	if not screenW then return MAX_COLS end
	local gutter = nativeBar and 12 or 0
	return max(MIN_COLS, min(MAX_COLS, floor((screenW - PAD * 2 - gutter + GAP) / (SLOT + GAP))))
end

function ns.MinColumns()
	local w = 4 + max(BAR_W, slotsText:GetStringWidth() or 0)
	if reagentTotal > 0 then w = w + BAR_GAP + max(BAR_W, reagentText:GetStringWidth() or 0) end
	w = w + 12 + (money:GetStringWidth() or 0) + 4
	if ahRow and ahRow:IsShown() then
		local ahW = 4 + (ahValueText:GetStringWidth() or 0) + 12 + (ahTimeText:GetStringWidth() or 0) + 4
		if ahW > w then w = ahW end
	end
	return max(MIN_COLS, min(ns.MaxColumns(), ceil((w + GAP) / (SLOT + GAP))))
end

function ns.ClampColumns(c)
	return max(ns.MinColumns(), min(ns.MaxColumns(), floor((c or MIN_COLS) + 0.5)))
end

function ns.MaxViewHeight()
	local _, screenH = ScreenSize()
	if not screenH then return 1400 end
	return max(MIN_VIEW, Snap(screenH - TOP_H - FOOT_H - 40))
end

function ns.ClampViewHeight(h)
	if not h then return nil end
	return max(MIN_VIEW, min(ns.MaxViewHeight(), floor(h + 0.5)))
end

-- Retail item buttons replace SetAlpha with one that only dims the icon; use
-- the plain frame version so our slot edge and glow dim too.
local BaseSetAlpha
do
	local mt = getmetatable(UIParent)
	local idx = mt and mt.__index
	local f = type(idx) == "table" and idx.SetAlpha
	BaseSetAlpha = f or function(b, a) b:SetAlpha(a) end
end

local function ShowCount(b, n, trim)
	if not b then return end
	local c = b.fbCount
	c:SetText(n); c:SetTextColor(MUTED[1], MUTED[2], MUTED[3]); c:Show()
	b.fbEdge:SetVertexColor(trim[1], trim[2], trim[3], 1)
	b.pCount = -1          -- our text replaced the stack count; repaint if it ever gets an item
end

local function ShowFreeCount()
	if ns.db.oneBag then return end
	ShowCount(freeButton, freeCount, TRIM)
	ShowCount(freeReagentButton, reagentFree, REAGENT_TRIM)
end

-- "12" alone, or "12 bag, 8 reagent" while a reagent bag is equipped.
local function FreeHeaderText()
	if reagentTotal > 0 then return format("%d bag, %d reagent", freeCount, reagentFree) end
	return freeCount
end

local function ApplySearch()
	local q = ns.searchText
	for _, bag in ipairs(bagList) do
		local list = buttons[bag]
		if list then
			for slot = 1, list.n do
				local b, r = list[slot], list[slot].fbRec
				local a = (not q or not r.id or (r.name and find(r.name, q, 1, true))) and 1 or 0.25
				if b.fbA ~= a then b.fbA = a; BaseSetAlpha(b, a) end
			end
		end
	end
end

Layout = function()
	layoutDirty = false
	for i = 1, FREE_CAT do wipe(sections[i]) end
	freeButton, freeCount, totalSlots = nil, 0, 0
	freeReagentButton, reagentFree, reagentTotal = nil, 0, 0

	local oneBag = ns.db.oneBag
	local allSlots = sections[1]

	for _, bag in ipairs(bagList) do
		local list = buttons[bag]
		local n = list and list.n or 0
		local general, reagent = generalBag[bag], reagentBag[bag]
		if general then totalSlots = totalSlots + n elseif reagent then reagentTotal = reagentTotal + n end
		for slot = 1, n do
			local b = list[slot]
			if not b.fbCat then
				if general then
					freeCount = freeCount + 1
					if not oneBag and not freeButton then freeButton = b end
				elseif reagent then
					reagentFree = reagentFree + 1
					if not oneBag and not freeReagentButton then freeReagentButton = b end
				end
			end
			if oneBag then
				-- Keyring reports 32 capacity slots even with 1 key; only include filled keyring slots in the flat grid.
				if bag ~= KEYRING_CONTAINER or b.fbRec.id then
					Paint(b)
					allSlots[#allSlots + 1] = b
				else
					b:Hide()
				end
			elseif b.fbCat then
				local s = sections[b.fbCat]; s[#s + 1] = b
			elseif b ~= freeButton and b ~= freeReagentButton then
				b:Hide()
			end
		end
	end
	if not oneBag then
		-- Every item has a category (Miscellaneous catches the rest), so the Free
		-- Space tiles hold no items: they're the empty slots you drop onto (e.g.
		-- the other half of a split stack): one for your bags and, when a reagent
		-- bag is equipped, one for it. On by default; can be hidden.
		local freeS, show = sections[FREE_CAT], ns.db.showFreeSpace
		if freeButton then if show then freeS[#freeS + 1] = freeButton else freeButton:Hide() end end
		if freeReagentButton then if show then freeS[#freeS + 1] = freeReagentButton else freeReagentButton:Hide() end end
	end

	UpdateFooter()                                 -- strings first: the minimum width is measured from them
	local cols = ns.ClampColumns(ns.db.columns)
	if cols ~= ns.db.columns then
		ns.db.columns = cols
		if ns.RefreshOptions then ns.RefreshOptions() end
	end
	local width = cols * SLOT + (cols - 1) * GAP
	local collapsed = ns.db.collapsed
	local y = 0
	wipe(usedSub)
	if oneBag then
		for _, h in pairs(headers) do h:Hide() end
		if #allSlots > 0 then
			y = PlaceGrid(allSlots, 1, #allSlots, 0, cols) + SECTION_GAP
		end
	else
		for cat = 1, FREE_CAT do
			local s = sections[cat]
			if #s > 0 then
				local h = GetHeader(cat)
				h:ClearAllPoints(); h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y); h:SetWidth(width)
				h.count:SetText(cat == FREE_CAT and FreeHeaderText() or #s)
				h:Show()
				y = y + HEADER_H + 5
				if collapsed[cat] then
					h.toggle:SetTexture(PLUS)
					for _, b in ipairs(s) do b:Hide() end
					y = y + SECTION_GAP - 5
				elseif cat == FREE_CAT then
					h.toggle:SetTexture(MINUS)
					y = PlaceGrid(s, 1, #s, y, cols) + SECTION_GAP   -- bags tile first, reagent tile beside it: never sorted
				elseif SPLIT_SETTING[cat] and ns.db[SPLIT_SETTING[cat]] ~= false then
					h.toggle:SetTexture(MINUS)
					if #s > 1 then sort(s, SortReagent) end
					local i, n = 1, #s
					while i <= n do
						local g = EffGroup(s[i])
						local j = i
						while j < n and EffGroup(s[j + 1]) == g do j = j + 1 end
						local sh = GetSubHeader(g)
						sh:ClearAllPoints(); sh:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y); sh:SetWidth(width)
						sh.count:SetText(j - i + 1)
						sh:Show(); usedSub[g] = true
						y = y + SUB_H + 3
						if collapsed["r" .. g] then
							sh.toggle:SetTexture(PLUS)
							for k = i, j do s[k]:Hide() end
						else
							sh.toggle:SetTexture(MINUS)
							y = PlaceGrid(s, i, j, y, cols)
						end
						y = y + SUB_GAP
						i = j + 1
					end
					y = y - SUB_GAP + SECTION_GAP
				else
					h.toggle:SetTexture(MINUS)
					if #s > 1 then sort(s, SortCompare) end
					y = PlaceGrid(s, 1, #s, y, cols) + SECTION_GAP
				end
			elseif headers[cat] then
				headers[cat]:Hide()
			end
		end
	end

	for g, sh in pairs(subHeaders) do if not usedSub[g] then sh:Hide() end end
	ShowFreeCount()

	content:SetSize(width, max(y, 1))
	contentW, contentH = width, max(y, 1)
	ns.ApplyView()
	if ns.RefitCurrencies then ns.RefitCurrencies() end
end

---------------------------------------------------------------------------
-- Update cycle
---------------------------------------------------------------------------
local function UpdateCooldowns()
	if not (ns.GetCooldown and CooldownFrame_Set) then return end
	for _, bag in ipairs(bagList) do
		local list = buttons[bag]
		if list then
			for slot = 1, list.n do
				local b = list[slot]
				if b.fbRec.id and b:IsShown() then SetCooldown(b, bag, slot) end
			end
		end
	end
end

local function UpdateMoney()
	money:SetText(MoneyString(GetMoney()))
	if numTokens > 0 and ns.RefitCurrencies then ns.RefitCurrencies() end
	if frame:IsShown() and ns.MinColumns() > ns.db.columns then Layout() end   -- more digits: widen
end

-- Windows you click items away into (sell, mail, trade, bank, auction).
local INTERACTION_WINDOWS = { "MerchantFrame", "MailFrame", "TradeFrame", "BankFrame", "GuildBankFrame",
	"AuctionHouseFrame", "AuctionFrame", "AccountBankPanel", "VoidStorageFrame" }
local function InteractionWindowOpen()
	for i = 1, #INTERACTION_WINDOWS do
		local f = _G[INTERACTION_WINDOWS[i]]
		if f and f.IsShown and f:IsShown() then return true end
	end
	return false
end
ns.InteractionWindowOpen = InteractionWindowOpen

-- Only while one of those windows is open AND the cursor is over the bags do
-- emptied slots stay as gaps, so the next item never slides under a
-- right-click (no accidental vendor sales). Everywhere else — merging stacks,
-- using items — the grid tidies up immediately.
local function HoldGaps()
	return frame:IsMouseOver() and InteractionWindowOpen()
end

local reflowWaiting = false
local function ReflowLater()
	reflowWaiting = false
	if frame:IsShown() and layoutDirty then
		if HoldGaps() then reflowWaiting = true; C_Timer.After(0.3, ReflowLater)
		else Layout(); if ns.searchText then ApplySearch() end end
	end
end

local function Update(force)
	if dirtyAll then dirtyAll = false; SyncBagList() end
	for bag in pairs(dirty) do
		if inList[bag] then ScanBag(bag) end
		dirty[bag] = nil
	end
	if layoutDirty then
		-- Re-sort right away unless gaps are being held (see HoldGaps), and
		-- always just after Sort or when the Free Space tile itself got filled.
		if force or ns.db.oneBag or GetTime() < (ns.sortingUntil or 0) or not HoldGaps()
			or (freeButton and freeButton.fbRec.id) or (freeReagentButton and freeReagentButton.fbRec.id) then Layout()
		else
			freeCount, reagentFree = 0, 0
			for bag in pairs(generalBag) do if generalBag[bag] then freeCount = freeCount + (GetFreeSlots(bag) or 0) end end
			for bag in pairs(reagentBag) do if reagentBag[bag] then reagentFree = reagentFree + (GetFreeSlots(bag) or 0) end end
			ShowFreeCount(); UpdateFooter()
			if not reflowWaiting then reflowWaiting = true; C_Timer.After(0.3, ReflowLater) end
		end
	else
		ShowFreeCount(); UpdateFooter()
	end
	if ns.searchText then ApplySearch() end
end

local pending, cdDirty, currencyDirty = false, false, false
local function Flush()
	pending = false
	if not frame:IsShown() then cdDirty, currencyDirty = false, false return end
	if dirtyAll or layoutDirty or next(dirty) then Update() end
	if cdDirty then cdDirty = false; UpdateCooldowns() end
	if currencyDirty then currencyDirty = false; ns.RefreshCurrencies() end
end
local function Schedule()
	if not pending and frame:IsShown() then
		pending = true
		C_Timer.After(0, Flush)
	end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
-- Always anchored by its bottom-right corner (so it grows up and left like the
-- default bags), with offsets snapped to whole screen pixels.
function ns.ResetPosition()
	local p = ns.db.pos                       -- stored in screen units, so Scale doesn't move it
	local x, y = -90, 120
	if p then
		local sc = frame:GetEffectiveScale()
		x, y = p[1] / sc, p[2] / sc
	end
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", Snap(x), Snap(y))
end

local function SavePosition()
	local right, bottom = frame:GetRight(), frame:GetBottom()
	if not (right and bottom) then return end
	local sc, us = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
	ns.db.pos = { right * sc - UIParent:GetRight() * us, bottom * sc - UIParent:GetBottom() * us }
	ns.db.point = nil
	ns.ResetPosition()
end

local function UpdatePixels()
	local _, h = GetPhysicalScreenSize()
	local s = frame:GetEffectiveScale()
	px = (h and h > 0 and s and s > 0) and (768 / h / s) or 1
	for i = 1, #hairlines do PlaceHairline(hairlines[i]) end
	if barFill then barFill:SetHeight(Snap(4)); reagentBarFill:SetHeight(Snap(4)) end
end
ns.UpdatePixels = UpdatePixels

function ns.ApplyScale()
	refitHeight = true
	frame:SetScale(ns.db.scale)
	UpdatePixels()
	ns.ResetPosition()
	-- A bigger scale can push the columns past the screen: the limits win.
	if frame:IsShown() and ns.ClampColumns(ns.db.columns) ~= ns.db.columns then Layout() else ns.ApplyView() end
end

-- Background behind the items: a standard Blizzard background (the Background
-- style setting) at the Background slider's darkness. 80% is Blizzard's
-- translucent Edit Mode dialog (the default look); 100% is as solid as its
-- opaque dialogs (Blizzard_SharedXML/Shared/Dialog/DialogTemplates.xml: the
-- translucent border is a black "Bg" texture at 0.8, the opaque one at 1).
-- The styles are the backgrounds Blizzard's own dialogs use (same file): the
-- light and dark dialog papers (DialogBorderTemplate / DialogBorderDarkTemplate)
-- and the marble and rock of the old panels (Interface\FrameGeneral\UI-Background-*).
-- A style may name an atlas (guarded by C_Texture.GetAtlasInfo) with a file to fall
-- back on; none does at present. The
-- slider's alpha is applied as the texture's vertex alpha, so every style keeps
-- the translucency. The Settings window follows the same settings.
ns.BACKGROUND_STYLES = {
	{ key = "dark",       name = "Dark" },                                                                            -- plain black, the translucent dialog (the default)
	{ key = "dialog",     name = "Light paper",   file = "Interface\\DialogFrame\\UI-DialogBox-Background", tile = true },
	{ key = "darkdialog", name = "Dark paper",    file = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", tile = true },
	{ key = "marble",     name = "Marble",        file = "Interface\\FrameGeneral\\UI-Background-Marble", tile = true },
	{ key = "rock",       name = "Rock",          file = "Interface\\FrameGeneral\\UI-Background-Rock", tile = true },
}
-- (Tooltip and Parchment were offered in 1.7.9 and removed the same day at the user's request; a saved key
-- that no longer exists falls back to Dark in ns.BackgroundStyle.)

function ns.BackgroundStyle(key)
	for _, s in ipairs(ns.BACKGROUND_STYLES) do if s.key == key then return s end end
	return ns.BACKGROUND_STYLES[1]
end

local function HasAtlas(name)
	return name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function SetBackground(border, a, style)
	if not border then return end
	local bg = border.Bg
	if bg then   -- the dialog template's background texture: swap what it shows, keep the alpha on top
		if style.atlas and HasAtlas(style.atlas) then
			bg:SetHorizTile(false); bg:SetVertTile(false)
			bg:SetAtlas(style.atlas, false)
			bg:SetVertexColor(1, 1, 1, a)
		elseif style.file then
			local wrap = style.tile and "REPEAT" or "CLAMP"
			bg:SetTexture(style.file, wrap, wrap)
			bg:SetTexCoord(0, 1, 0, 1)
			bg:SetHorizTile(style.tile or false); bg:SetVertTile(style.tile or false)
			bg:SetVertexColor(1, 1, 1, a)
		else
			bg:SetHorizTile(false); bg:SetVertTile(false)
			bg:SetColorTexture(0, 0, 0, a)
		end
	elseif border.SetBackdrop then   -- the classic backdrop fallback: files only (a backdrop can't show an atlas)
		local file = style.file
		border:SetBackdrop({
			bgFile = file or "Interface\\Buttons\\WHITE8X8", tile = style.tile or false, tileSize = 256,
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		if file then border:SetBackdropColor(1, 1, 1, a) else border:SetBackdropColor(0, 0, 0, a) end
	end
end

function ns.ApplyBackground()
	local a = max(0.2, min(1, ns.db.background or 0.8))
	local style = ns.BackgroundStyle(ns.db.backgroundStyle)
	SetBackground(bagBorder, a, style)
	SetBackground(ns.optionsBorder, a, style)
	SetBackground(ns.confirmBorder, a, style)
end

function ns.Relayout()
	layoutDirty, refitHeight = true, true
	if frame:IsShown() then Layout() end
end

-- Height of the item area. If you've sized the window (corner grips or the
-- Options slider) it stays that tall and scrolls; on "fit to items" it grows
-- with your bags up to 80% of the screen, then scrolls.
function ns.ViewHeight()
	local fixed = ns.db.viewHeight
	if fixed then return Snap(ns.ClampViewHeight(fixed)) end
	local _, screenH = ScreenSize()
	if not screenH then return Snap(max(MIN_VIEW, contentH)) end
	return Snap(max(MIN_VIEW, min(contentH, floor(screenH * 0.8) - TOP_H - FOOT_H)))
end

function ns.CurrentViewHeight() return scroll:GetHeight() end

-- Resizes the window around the current grid without re-sorting anything.
function ns.ApplyView()
	local viewH
	if ns.db.viewHeight or refitHeight or not lockedViewH then
		viewH = ns.ViewHeight()
	else
		viewH = lockedViewH                    -- open: keep the size, let the grid scroll
	end
	refitHeight, lockedViewH = false, viewH
	scroll:SetSize(contentW, viewH)
	maxScroll = max(0, contentH - viewH)
	local gutter = nativeBar and 12 or 0      -- always reserved, so the width never jumps
	frame:SetSize(Snap(contentW + PAD * 2 + gutter), Snap(TOP_H + viewH + FOOT_H))
	if numTokens > 0 and frame:GetWidth() ~= refitWidth then ns.RefitCurrencies() end
	ns.ScrollTo(scroll:GetVerticalScroll())
end

function ns.ScrollTo(v)
	v = max(0, min(maxScroll, v or 0))
	if nativeBar then
		-- Blizzard's bar drives the position; only pull it back if the grid shrank.
		if scroll:GetVerticalScroll() > maxScroll then scroll:SetVerticalScroll(maxScroll) end
		return
	end
	scroll:SetVerticalScroll(Snap(v))
	if maxScroll <= 0 then
		track:Hide(); thumb:Hide()
		return
	end
	local h = track:GetHeight()
	if not h or h <= 0 then h = scroll:GetHeight() end
	local viewH = h
	local thumbH = max(24, h * viewH / (viewH + maxScroll))
	thumb:SetHeight(thumbH)
	thumb:ClearAllPoints()
	thumb:SetPoint("TOP", track, "TOP", 0, -((h - thumbH) * v / maxScroll))
	track:Show(); thumb:Show()
end

---------------------------------------------------------------------------
-- Drop an item anywhere on the window: a reagent goes into the reagent bag
-- first (setting "Prefer the reagent bag", unless it's full), anything else
-- into the first free slot of a normal bag. Checked live, so a slot changed
-- this instant is never hit.
---------------------------------------------------------------------------
local PickupContainerItem = C_Container.PickupContainerItem
local GetContainerItemID = C_Container.GetContainerItemID

local function DropIntoBag(bag, needFit)
	local free, family = GetFreeSlots(bag)                -- live: catches bag swaps too
	if (free or 0) == 0 then return false end
	if needFit then
		local kind, itemID = GetCursorInfo()
		if (family or 0) == 0 or kind ~= "item" or not ns.FitsBagFamily(itemID, family) then return false end
	elseif (family or 0) ~= 0 then
		return false
	end
	for slot = 1, (GetNumSlots(bag) or 0) do
		if not GetContainerItemID(bag, slot) then
			PickupContainerItem(bag, slot)
			return true
		end
	end
	return false
end

function ns.StoreCursorItem()
	if not (CursorHasItem and CursorHasItem() and PickupContainerItem) then return end
	if ns.REAGENT_BAG and ns.db.preferReagentBag ~= false and GetCursorInfo then
		if DropIntoBag(ns.REAGENT_BAG, true) then return end
	end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		if DropIntoBag(bag) then return end
	end
	if UIErrorsFrame and ERR_INV_FULL then UIErrorsFrame:AddMessage(ERR_INV_FULL, 1, 0.1, 0.1) end
end

---------------------------------------------------------------------------
-- Backpack currencies: whatever you ticked "Show on Backpack" in the Currency
-- tab, shown in the footer with Blizzard's own tooltips. WoW: Forever and
-- Retail use C_CurrencyInfo (checked in Blizzard's Forever 1.60.1 source);
-- older Classic clients the global; Classic Era has no currencies (row stays hidden).
---------------------------------------------------------------------------
local function GetBackpackToken(i)
	local t = C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo(i)
	if t then return t.iconFileID, t.quantity, t.currencyTypesID end
end

local FOOT_BASE, TOKEN_ROW_Y, TOKEN_ROW_H, TOKEN_GAP = 44, 26, 20, 10
ns.HasCurrencyAPI = GetBackpackToken ~= nil

local function FormatCount(n)
	local s = BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
	if #s > 6 and AbbreviateNumbers then s = AbbreviateNumbers(n) end
	return s
end

local function TokenTooltip(owner, token)
	if not token then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if token.index and GameTooltip.SetBackpackToken then
		GameTooltip:SetBackpackToken(token.index)
		if TOKEN_REMOVE_FROM_BACKPACK_INSTRUCTION then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(TOKEN_REMOVE_FROM_BACKPACK_INSTRUCTION, 0.1, 1, 0.1, true)
		end
	elseif token.listIndex and GameTooltip.SetCurrencyToken then
		GameTooltip:SetCurrencyToken(token.listIndex)
	elseif token.currencyID and GameTooltip.SetCurrencyByID then
		GameTooltip:SetCurrencyByID(token.currencyID, token.quantity)
	end
	GameTooltip:Show()
end

-- Item on the cursor, link, untrack: same as Blizzard's backpack tokens. A plain click opens the Character
-- window, but never from here (below).
local function TokenClick(b)
	if CursorHasItem and CursorHasItem() then ns.StoreCursorItem() return end
	local C = C_CurrencyInfo
	if IsModifiedClick and C then
		if IsModifiedClick("CHATLINK") and HandleModifiedItemClick then
			local link = (b.currencyID and C.GetCurrencyLink and C.GetCurrencyLink(b.currencyID, b.quantity))
				or (b.listIndex and C.GetCurrencyListLink and C.GetCurrencyListLink(b.listIndex))
			if link and HandleModifiedItemClick(link) then return end
		end
		if IsModifiedClick("TOKENWATCHTOGGLE") and b.index and b.currencyID and C.SetCurrencyBackpackByID then
			C.SetCurrencyBackpackByID(b.currencyID, false)   -- our hook refreshes the row
		end
	end
end

-- Opening the Character window from addon code (ToggleCharacter, CharacterFrame:ToggleTokenFrame; 1.0-1.7.13 did)
-- runs Blizzard's panel code tainted and leaves its state ours. So a plain click goes through one secure button:
-- a SecureActionButtonTemplate "click" on Blizzard's CharacterMicroButton, which opens the Character window as
-- Blizzard code, on the paper doll (the Currency tab is one click further). A protected button makes the window
-- protected too (see the X below), so it covers the hovered currency only outside combat and is parked on
-- PLAYER_REGEN_DISABLED. In combat a plain click does nothing, as before; links and untracking still work.
local currencyOpen
local currencyPark = CreateFrame("Frame"); currencyPark:Hide()
function ns.ParkCurrencyOpen()
	if currencyOpen and not InCombatLockdown() then
		currencyOpen:ClearAllPoints(); currencyOpen:SetParent(currencyPark); currencyOpen.token = nil
	end
end

local function MakeCurrencyOpen()
	local b = CreateFrame("Button", nil, currencyPark, "SecureActionButtonTemplate")
	b:RegisterForClicks("LeftButtonUp")
	b:SetAttribute("useOnKeyDown", false)
	b:SetAttribute("clickbutton", CharacterMicroButton)
	b:SetScript("PreClick", function(self)
		if InCombatLockdown() then return end   -- attributes are locked in combat (it is parked then anyway)
		local held = CursorHasItem and CursorHasItem()
		local modified = IsModifiedClick and (IsModifiedClick("CHATLINK") or IsModifiedClick("TOKENWATCHTOGGLE"))
		self:SetAttribute("type", not (held or modified) and "click" or nil)
	end)
	b:SetScript("PostClick", function(self)
		if self.token and not self:GetAttribute("type") then TokenClick(self.token) end
	end)
	b:SetScript("OnEnter", function(self) if self.token then TokenTooltip(self, self.token) end end)
	b:SetScript("OnLeave", function() GameTooltip:Hide(); ns.ParkCurrencyOpen() end)
	b:SetScript("OnReceiveDrag", function() ns.StoreCursorItem() end)
	currencyOpen = b
end

local function CoverToken(token)
	if InCombatLockdown() or not CharacterMicroButton then return end
	if not currencyOpen then MakeCurrencyOpen() end
	currencyOpen.token = token
	currencyOpen:SetParent(frame); currencyOpen:ClearAllPoints(); currencyOpen:SetAllPoints(token)
	currencyOpen:SetFrameLevel(token:GetFrameLevel() + 1)
end

local function TokenButton(i)
	local b = tokenButtons[i]
	if b then return b end
	b = CreateFrame("Button", nil, frame)
	b:SetHeight(16)
	b:SetFrameLevel(frame:GetFrameLevel() + 6)
	b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(14, 14); b.icon:SetPoint("RIGHT")
	b.count = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	b.count:SetPoint("RIGHT", b.icon, "LEFT", -3, 0)
	b:SetScript("OnEnter", function(self) TokenTooltip(self, self); CoverToken(self) end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnReceiveDrag", function() ns.StoreCursorItem() end)
	b:SetScript("OnClick", TokenClick)
	tokenButtons[i] = b
	return b
end

local function PlaceFooterLine()
	footLine:ClearAllPoints()
	footLine:SetPoint("BOTTOMLEFT", PAD, FOOT_H - 4)
	footLine:SetPoint("BOTTOMRIGHT", -PAD, FOOT_H - 4)
end

-- Lays the currencies out right-to-left: on the same line to the left of your
-- gold when the window width permits it, or stacked with the gold alongside
-- the stacked bag capacity + fill bar when narrower.
function ns.RefitCurrencies()
	if refitting then return end
	refitting = true
	refitWidth = frame:GetWidth()
	local avail = refitWidth - PAD * 2 - 8
	local off = AhRowOffset()
	local leftW = max(BAR_W, slotsText:GetStringWidth() or 0)
	if reagentTotal > 0 then
		leftW = leftW + BAR_GAP + max(BAR_W, reagentText:GetStringWidth() or 0)
	end
	local moneyW = money:GetStringWidth() or 0

	local totalTokenW = 0
	for i = 1, numTokens do
		local t, b = tokens[i], TokenButton(i)
		b.index, b.currencyID, b.quantity, b.listIndex = t[1], t[4], t[3], t[5]
		b.icon:SetTexture(t[2])
		b.count:SetText(FormatCount(t[3]))
		local w = (b.count:GetStringWidth() or 0) + 20
		b.w = w
		totalTokenW = totalTokenW + w + (i > 1 and TOKEN_GAP or 0)
	end
	for i = numTokens + 1, #tokenButtons do tokenButtons[i]:Hide() end

	local want
	if numTokens == 0 then
		money:ClearAllPoints()
		money:SetPoint("BOTTOMRIGHT", -PAD - 4, 17 + off)
		want = FOOT_BASE + off
	elseif leftW + 16 + totalTokenW + TOKEN_GAP + moneyW <= avail then
		-- Single line: currencies sit inline to the left of gold on the same row.
		money:ClearAllPoints()
		money:SetPoint("BOTTOMRIGHT", -PAD - 4, 17 + off)
		local x = moneyW + TOKEN_GAP
		for i = 1, numTokens do
			local b = tokenButtons[i]
			b:SetWidth(b.w)
			b:ClearAllPoints()
			b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(PAD + 4 + x), 16 + off)
			b:Show()
			x = x + b.w + TOKEN_GAP
		end
		want = FOOT_BASE + off
	else
		-- Stacked: gold aligns with the bottom fill bar, and the first currency row
		-- aligns with the bag capacity text above it.
		money:ClearAllPoints()
		money:SetPoint("BOTTOMRIGHT", -PAD - 4, 13 + off)
		local row, used = 0, 0
		local row0Avail = max(60, avail - leftW - 14)
		for i = 1, numTokens do
			local b = tokenButtons[i]
			local w = b.w
			local limit = (row == 0) and row0Avail or avail
			if used > 0 and used + w > limit then row, used = row + 1, 0 end
			b.row, b.x = row, used
			used = used + w + TOKEN_GAP
		end
		local rows = row + 1
		for i = 1, numTokens do
			local b = tokenButtons[i]
			b:SetWidth(b.w)
			b:ClearAllPoints()
			b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(PAD + 4 + b.x), TOKEN_ROW_Y + off + (rows - 1 - b.row) * TOKEN_ROW_H)
			b:Show()
		end
		want = FOOT_BASE + 4 + off + (rows - 1) * TOKEN_ROW_H
	end

	if want ~= FOOT_H then
		FOOT_H = want
		PlaceFooterLine()
		refitHeight = true                     -- footer changed: fit the grid to the new space
		ns.ApplyView()
	end
	refitting = false
end

function ns.RefreshAuctionFooter()
	if not frame then return end
	UpdateAuctionFooter()
	if frame:IsShown() then
		ns.RefitCurrencies()
		if ns.MinColumns() > ns.db.columns then
			Layout()
		end
	end
	if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Reads watched backpack currencies plus any discovered currencies you hold
-- (such as WoW: Forever's supply-crate Trader currency), even if "Show on Backpack"
-- hasn't been manually ticked in the Currency tab yet.
local seenCurrencies = {}
function ns.RefreshCurrencies()
	numTokens = 0
	wipe(seenCurrencies)
	local C = C_CurrencyInfo
	if C and ns.db.showCurrencies ~= false then
		if GetBackpackToken then
			for i = 1, 30 do
				local icon, count, id = GetBackpackToken(i)
				if not icon then break end                          -- the watched list has no gaps
				numTokens = numTokens + 1
				local t = tokens[numTokens] or {}
				t[1], t[2], t[3], t[4], t[5] = i, icon, count or 0, id, nil
				tokens[numTokens] = t
				if id then seenCurrencies[id] = true end
			end
		end
		if C.GetCurrencyListSize and C.GetCurrencyListInfo then
			local n = C.GetCurrencyListSize() or 0
			for idx = 1, n do
				local info = C.GetCurrencyListInfo(idx)
				if info and not info.isHeader and not info.isTypeUnused and (info.quantity or 0) > 0 and info.iconFileID then
					local id = info.currencyID
					if not id and C.GetCurrencyListLink and C.GetCurrencyIDFromLink then
						local link = C.GetCurrencyListLink(idx)
						if link then id = C.GetCurrencyIDFromLink(link) end
					end
					if not (id and seenCurrencies[id]) then
						if id then seenCurrencies[id] = true end
						numTokens = numTokens + 1
						local t = tokens[numTokens] or {}
						t[1], t[2], t[3], t[4], t[5] = nil, info.iconFileID, info.quantity, id, idx
						tokens[numTokens] = t
					end
				end
			end
		end
	end
	ns.RefitCurrencies()
end

function ns.MarkCurrencies()
	currencyDirty = true
	Schedule()
end

---------------------------------------------------------------------------
-- Taint-free destroy confirmation dialog (same Edit Mode chrome as the bags).
-- Never calls StaticPopup_Show from addon code, so Blizzard's shared StaticPopup
-- frames stay untainted for protected actions. While open, the item stays on the
-- cursor (same as Blizzard's native world-drop prompt): clicking Destroy runs in
-- a fresh hardware event and calls DeleteCursorItem(); Cancel or Escape puts the
-- item back via ClearCursor(); dropping the item elsewhere hides the dialog on
-- CURSOR_CHANGED.
---------------------------------------------------------------------------
local AskDestroy
do
	local confirm
	local confirmRec = {}
	local upper = string.upper

	local function SameCursorItem()
		if not (confirm and CursorHasItem and CursorHasItem() and GetCursorInfo) then return false end
		local kind, id, link = GetCursorInfo()
		if kind ~= "item" or id ~= confirm.itemID or link ~= confirm.itemLink then return false end
		if confirm.bag and C_Cursor and C_Cursor.GetCursorItem then
			local loc = C_Cursor.GetCursorItem()
			if not (loc and loc.IsEqualToBagAndSlot and loc:IsEqualToBagAndSlot(confirm.bag, confirm.slot)) then
				return false
			end
		end
		return true
	end

	local function SetYesEnabled(on)
		confirm.yesReady = on
		local b = confirm.yesBtn
		if on and b.Enable then b:Enable() elseif not on and b.Disable then b:Disable() end
		if not b.Disable then b:SetAlpha(on and 1 or 0.45) end
	end

	local function AcceptDestroy()
		if not (confirm and confirm.yesReady) then return end
		if confirm.needType and upper(confirm.edit:GetText() or "") ~= upper(confirm.confirmWord or "DELETE") then
			return
		end
		confirm.keepCursor = true
		if SameCursorItem() and DeleteCursorItem then
			DeleteCursorItem()
		end
		confirm:Hide()
	end

	local function CancelDestroy()
		if confirm then confirm:Hide() end
	end

	function ns.HideDestroyConfirm(keep)
		if confirm and confirm:IsShown() then
			confirm.keepCursor = keep
			confirm:Hide()
		end
	end

	-- While an item is on the cursor, nudging the mouse between mouse-down and
	-- mouse-up can dispatch OnReceiveDrag instead of OnClick; accept either so
	-- clicking Delete / Cancel / X never misses.
	local function BindConfirmClick(btn, fn)
		btn:SetScript("OnClick", function(self)
			self.down = false
			fn()
		end)
		btn:SetScript("OnMouseDown", function(self, b)
			if b == "LeftButton" and (not self.IsEnabled or self:IsEnabled()) then
				self.down = true
			end
		end)
		btn:SetScript("OnLeave", function(self) self.down = false end)
		btn:SetScript("OnHide", function(self) self.down = false end)
		btn:SetScript("OnReceiveDrag", function(self)
			if self.down and (not self.IsEnabled or self:IsEnabled()) then
				self.down = false
				fn()
			end
		end)
	end

	local function MakeConfirmButton(parent, text, width)
		local b = TryTemplate("Button", nil, parent, "UIPanelButtonTemplate")
		if not b then
			b = CreateFrame("Button", nil, parent)
			local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetColorTexture(0.45, 0.08, 0.06, 1); bg:SetAllPoints()
			b:SetNormalFontObject("GameFontNormal")
			local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetColorTexture(1, 1, 1, 0.08); hl:SetAllPoints()
		end
		if b.SetText then b:SetText(text) end
		b:SetSize(width, 22)
		b:RegisterForClicks("LeftButtonUp")
		return b
	end

	local function BuildConfirm()
		confirm = CreateFrame("Frame", "DavesSackConfirm", UIParent)
		confirm:SetSize(340, 140)
		confirm:SetPoint("TOP", UIParent, "TOP", 0, -135)
		confirm:SetFrameStrata("FULLSCREEN_DIALOG")
		confirm:SetClampedToScreen(true)
		confirm:EnableMouse(true); confirm:SetMovable(true); confirm:RegisterForDrag("LeftButton")
		if confirm.SetDontSavePosition then confirm:SetDontSavePosition(true) end
		confirm:SetScript("OnDragStart", function(self)
			if not (CursorHasItem and CursorHasItem()) then self:StartMoving() end
		end)
		confirm:SetScript("OnDragStop", confirm.StopMovingOrSizing)
		confirm:Hide()
		tinsert(UISpecialFrames, "DavesSackConfirm")

		local border = TryTemplate("Frame", nil, confirm, "DialogBorderTranslucentTemplate")
		if border then
			border:SetAllPoints()
		else
			border = CreateFrame("Frame", nil, confirm, BackdropTemplateMixin and "BackdropTemplate" or nil)
			border:SetAllPoints(); border:SetFrameLevel(confirm:GetFrameLevel())
			border:SetBackdrop({
				bgFile = "Interface\\Buttons\\WHITE8X8",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32,
				insets = { left = 11, right = 12, top = 12, bottom = 11 },
			})
			border:SetBackdropColor(0, 0, 0, 0.8)
		end
		ns.confirmBorder = border
		ns.ApplyBackground()

		local title = confirm:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
		title:SetPoint("TOP", 0, -15)
		title:SetText("Destroy Item")

		local close = TryTemplate("Button", nil, confirm, "UIPanelCloseButton")
		if close then
			close:SetPoint("TOPRIGHT")
		else
			close = CreateFrame("Button", nil, confirm)
			close:SetSize(32, 32); close:SetPoint("TOPRIGHT", 2, 2)
			close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
			close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
			close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
		end
		close:SetFrameLevel(confirm:GetFrameLevel() + 5)
		close:RegisterForClicks("LeftButtonUp")
		BindConfirmClick(close, CancelDestroy)

		local slotBox = CreateFrame("Frame", nil, confirm)
		slotBox:SetSize(36, 36)
		slotBox:SetPoint("TOPLEFT", 24, -46)
		slotBox:EnableMouse(true)
		local slotBg = slotBox:CreateTexture(nil, "BACKGROUND")
		slotBg:SetTexture(M .. "slot"); slotBg:SetVertexColor(SLOTBG[1], SLOTBG[2], SLOTBG[3]); slotBg:SetAllPoints()
		local icon = slotBox:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		if slotBox.CreateMaskTexture and icon.AddMaskTexture then
			local mask = slotBox:CreateMaskTexture()
			mask:SetTexture(M .. "slot", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(icon)
			icon:AddMaskTexture(mask)
		end
		local edge = slotBox:CreateTexture(nil, "OVERLAY")
		edge:SetTexture(M .. "slotedge"); edge:SetAllPoints()
		local countFS = slotBox:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		countFS:SetPoint("BOTTOMRIGHT", -3, 3)
		slotBox:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if confirm.bag and confirm.slot and GameTooltip.SetBagItem then
				GameTooltip:SetBagItem(confirm.bag, confirm.slot)
			elseif confirm.itemLink and GameTooltip.SetHyperlink then
				GameTooltip:SetHyperlink(confirm.itemLink)
			end
			GameTooltip:Show()
		end)
		slotBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
		confirm.slotBox, confirm.icon, confirm.edge, confirm.count = slotBox, icon, edge, countFS

		local prompt = confirm:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		prompt:SetPoint("LEFT", slotBox, "RIGHT", 10, 0)
		prompt:SetWidth(340 - 24 - 36 - 10 - 24)
		prompt:SetJustifyH("LEFT")
		if prompt.SetWordWrap then prompt:SetWordWrap(true) end
		confirm.prompt = prompt

		local hint = confirm:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		confirm.hint = hint

		local edit = CreateFrame("EditBox", "DavesSackConfirmEdit", confirm, "InputBoxTemplate")
		edit:SetAutoFocus(false)
		edit:SetSize(160, 22)
		edit:SetMaxLetters(32)
		edit:SetScript("OnTextChanged", function(self)
			if not confirm.needType then return end
			local word = confirm.confirmWord or "DELETE"
			SetYesEnabled(upper(self:GetText() or "") == upper(word))
		end)
		edit:SetScript("OnEnterPressed", AcceptDestroy)
		edit:SetScript("OnEscapePressed", CancelDestroy)
		confirm.edit = edit

		local yesBtn = MakeConfirmButton(confirm, DELETE or "Destroy", 112)
		yesBtn:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -6, 16)
		BindConfirmClick(yesBtn, AcceptDestroy)
		confirm.yesBtn = yesBtn

		local noBtn = MakeConfirmButton(confirm, CANCEL or "Cancel", 112)
		noBtn:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 6, 16)
		BindConfirmClick(noBtn, CancelDestroy)
		confirm.noBtn = noBtn

		confirm:SetScript("OnEvent", function()
			if not SameCursorItem() then confirm:Hide() end
		end)
		confirm:SetScript("OnShow", function(self)
			pcall(self.RegisterEvent, self, "CURSOR_CHANGED")
			Sound("IG_MAINMENU_OPEN")
		end)
		confirm:SetScript("OnHide", function(self)
			pcall(self.UnregisterEvent, self, "CURSOR_CHANGED")
			local keep = self.keepCursor
			self.keepCursor = nil
			self.needType = false
			edit:ClearFocus()
			edit:SetText("")
			if GameTooltip:GetOwner() == slotBox then GameTooltip:Hide() end
			if not keep and SameCursorItem() and ClearCursor then ClearCursor() end
			Sound("IG_MAINMENU_CLOSE")
		end)
	end

	AskDestroy = function(itemID, itemLink)
		if not confirm then BuildConfirm() end
		local bag, slot
		if C_Cursor and C_Cursor.GetCursorItem then
			local loc = C_Cursor.GetCursorItem()
			if loc and loc.IsBagAndSlot and loc:IsBagAndSlot() then
				bag, slot = loc:GetBagAndSlot()
			end
		end
		local icon, count, quality, link
		if bag and slot then
			ReadSlot(bag, slot, confirmRec)
			icon, count, quality, link = confirmRec.texture, confirmRec.count or 1, confirmRec.quality, confirmRec.link or itemLink
		end
		if not icon or not quality then
			local fbIcon, fbQ = ns.ItemSummary(itemID, itemLink)
			icon = icon or fbIcon
			quality = quality or fbQ or 1
		end
		count = (count and count > 0) and count or 1
		link = link or itemLink

		confirm.keepCursor = nil
		confirm.itemID, confirm.itemLink, confirm.bag, confirm.slot = itemID, itemLink, bag, slot
		confirm.icon:SetTexture(icon); confirm.icon:SetShown(icon ~= nil)
		if count > 1 then confirm.count:SetText(count); confirm.count:Show() else confirm.count:Hide() end
		local c = quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		if c then
			confirm.edge:SetVertexColor(c.r, c.g, c.b, 0.9)
		else
			confirm.edge:SetVertexColor(TRIM[1], TRIM[2], TRIM[3], 1)
		end

		local nameText = link or ("item #" .. tostring(itemID))
		local qtyText = count > 1 and (" |cffaaaaaax" .. count .. "|r") or ""
		confirm.prompt:SetText(format("Destroy %s%s?", nameText, qtyText))

		local rowH = max(36, (confirm.prompt:GetStringHeight() or 20) + 4)
		local needType = quality >= 3 and quality ~= 7   -- Rare+ (except Heirloom), matching Blizzard's rule
		local word = DELETE_ITEM_CONFIRM_STRING or "DELETE"
		confirm.needType = needType
		confirm.confirmWord = word
		if needType then
			confirm.hint:SetText(format("Type %s to confirm:", word))
			confirm.hint:ClearAllPoints()
			confirm.hint:SetPoint("TOP", confirm, "TOP", 0, -(46 + rowH + 8))
			confirm.hint:Show()
			confirm.edit:SetText("")
			confirm.edit:ClearAllPoints()
			confirm.edit:SetPoint("TOP", confirm.hint, "BOTTOM", 0, -6)
			confirm.edit:Show()
			SetYesEnabled(false)
			confirm:SetHeight(46 + rowH + 8 + 14 + 6 + 22 + 50)
		else
			confirm.hint:Hide()
			confirm.edit:SetText("")
			confirm.edit:Hide()
			SetYesEnabled(true)
			confirm:SetHeight(46 + rowH + 50)
		end

		confirm:Show()
		if needType then
			confirm.edit:SetFocus()
		else
			SetYesEnabled(true)
		end
	end
end

local function Build()
	frame = CreateFrame("Frame", "DavesSackFrame", UIParent)
	ns.frame = frame
	frame:SetScale(ns.db.scale)
	local _, h = GetPhysicalScreenSize()
	local s = frame:GetEffectiveScale()
	if h and h > 0 and s and s > 0 then px = 768 / h / s end
	if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
	frame:SetFrameStrata("HIGH"); frame:SetFrameLevel(10); frame:SetClampedToScreen(true)
	frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if not (CursorHasItem and CursorHasItem()) then self:StartMoving() end end)
	frame:SetScript("OnReceiveDrag", function() ns.StoreCursorItem() end)
	frame:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" then ns.StoreCursorItem() end end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
	frame:Hide()
	tinsert(UISpecialFrames, "DavesSackFrame")

	-- Edit Mode chrome: Blizzard's translucent dialog border (falls back to the
	-- classic dialog backdrop on a client without it).
	local border = TryTemplate("Frame", nil, frame, "DialogBorderTranslucentTemplate")
	if border then
		border:SetAllPoints()
	else
		border = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
		border:SetAllPoints(); border:SetFrameLevel(frame:GetFrameLevel())
		border:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		border:SetBackdropColor(0, 0, 0, 0.8)
	end
	bagBorder = border
	ns.ApplyBackground()

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("TOP", 0, -15)
	title:SetText(INVENTORY_TOOLTIP or "Inventory")

	-- Two close buttons in one spot. Outside combat the secure one: a SecureActionButtonTemplate "click" on
	-- Blizzard's backpack button, so Blizzard's ToggleAllBags runs as Blizzard code, untainted, its bag state stays
	-- in step with our window (the hooks below follow it; our window plays the close sound). Calling CloseAllBags from
	-- here would taint that state (1.7.7). If Blizzard's bags are already closed (/sack opened ours) the click just
	-- hides us.
	-- A protected button makes the window protected too, as a child and even when only anchored to it (1.7.10 had
	-- it on UIParent, anchored: every B press in combat was blocked). So it sits on the window only outside combat:
	-- PLAYER_REGEN_DISABLED fires just before lockdown and parks it off the window until PLAYER_REGEN_ENABLED.
	-- In combat the plain button stands in. It hides our window only (our own close sound plays), so Blizzard's
	-- bags stay "open" and the next B press closes them; the one after opens them.
	local function PinClose(b)   -- on the window's corner, above its contents
		b:SetParent(frame); b:ClearAllPoints()
		b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", b.anchorX, b.anchorY)
		b:SetFrameLevel(frame:GetFrameLevel() + 5)
	end
	local function MakeClose(template)
		local b = TryTemplate("Button", nil, frame, template and ("UIPanelCloseButton, " .. template) or "UIPanelCloseButton")
		if b then
			b.anchorX, b.anchorY = 0, 0
		else
			b = CreateFrame("Button", nil, frame, template)
			b:SetSize(32, 32); b.anchorX, b.anchorY = 2, 2
			b:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
			b:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
			b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
		end
		PinClose(b)
		return b
	end
	local plainClose = MakeClose(nil)
	plainClose:SetScript("OnClick", function()
		if CursorHasItem and CursorHasItem() then ns.StoreCursorItem(); return end
		frame:Hide()
	end)

	local close
	local park = CreateFrame("Frame"); park:Hide()
	local function MakeSecureClose()
		close = MakeClose("SecureActionButtonTemplate")
		-- On release, whatever the key-down cvar says (SecureActionButton_ShouldUseOnKeyDown reads this attribute
		-- first): acting on mouse-down hid the window before the mouse-up came, and the X stayed pushed (1.7.13).
		close:RegisterForClicks("AnyUp")
		close:SetAttribute("useOnKeyDown", false)
		close:SetAttribute("type", "click")
		close:SetAttribute("clickbutton", MainMenuBarBackpackButton)
		close:SetScript("PreClick", function(self)
			if InCombatLockdown() then return end   -- attributes are locked in combat (it is parked then anyway)
			-- an item on the cursor goes into the bags our way (PostClick), not through Blizzard's button
			local held = CursorHasItem and CursorHasItem()
			self:SetAttribute("type", (not held and ns.BlizzardBagsOpen()) and "click" or nil)
		end)
		close:SetScript("PostClick", function()
			if CursorHasItem and CursorHasItem() then ns.StoreCursorItem(); return end
			if frame:IsShown() and not ns.BlizzardBagsOpen() then frame:Hide() end
		end)
	end
	-- Outside combat only (PLAYER_REGEN_DISABLED counts: lockdown starts after it).
	function ns.CloseButtonForCombat(inCombat)
		if not MainMenuBarBackpackButton then return end   -- no backpack button to click: the plain one stays
		if not close then
			if inCombat then return end
			MakeSecureClose()
		end
		if inCombat then
			close:ClearAllPoints(); close:SetParent(park)
		else
			PinClose(close)
			close:SetButtonState("NORMAL")   -- back on a window that may already be open (B in combat): no OnShow
		end
		plainClose:SetShown(inCombat)
	end
	-- A /reload in combat: the plain button until it ends (PLAYER_REGEN_ENABLED makes the secure one).
	if not InCombatLockdown() then ns.CloseButtonForCombat(false) end
	-- Guard: a button whose window hides mid-click never gets its mouse-up and would stay "pushed" (its pushed
	-- art sits a pixel or two off). Unpush on every show.
	local function UnpushClose()
		plainClose:SetButtonState("NORMAL")
		if close and not InCombatLockdown() then close:SetButtonState("NORMAL") end
	end

	-- Sort (Blizzard's standard red panel button), then the search box.
	local searchRight = -PAD
	if ns.SortBags then
		local sortBtn = TryTemplate("Button", nil, frame, "UIPanelButtonTemplate") or CreateFrame("Button", nil, frame)
		sortBtn:SetSize(64, 22)
		sortBtn:SetPoint("TOPRIGHT", -PAD, -42)
		if sortBtn.SetText then sortBtn:SetText("Sort") end
		sortBtn:SetScript("OnClick", function()
			Sound("UI_BAG_SORTING_01")
			ns.sortingUntil = GetTime() + 5          -- show sorted results even while hovering
			ns.SortBags()
		end)
		searchRight = -PAD - 64 - 8
	end

	-- Settings: Blizzard's panel button with our gear icon centred beside the label.
	local settings = TryTemplate("Button", "DavesSackSettingsButton", frame, "UIPanelButtonTemplate")
	if not settings then
		settings = CreateFrame("Button", "DavesSackSettingsButton", frame)
		local bg = settings:CreateTexture(nil, "BACKGROUND")
		bg:SetColorTexture(0.45, 0.08, 0.06, 1); bg:SetAllPoints()
		settings:SetNormalFontObject("GameFontNormal")
		local hl = settings:CreateTexture(nil, "HIGHLIGHT")
		hl:SetColorTexture(1, 1, 1, 0.08); hl:SetAllPoints()
	end
	settings:SetText("Settings")
	settings:SetSize(96, 22)                  -- after SetText: some clients auto-fit the width
	settings:SetPoint("TOPRIGHT", searchRight, -42)
	local gearIcon = settings:CreateTexture(nil, "OVERLAY")
	gearIcon:SetTexture(M .. "gear"); gearIcon:SetSize(14, 14)
	local label = settings.GetFontString and settings:GetFontString()
	if label then
		label:ClearAllPoints(); label:SetPoint("CENTER", 9, 0)   -- icon + text centred as a pair
		gearIcon:SetPoint("RIGHT", label, "LEFT", -4, 0)
	else
		gearIcon:SetPoint("LEFT", 10, 0)
	end
	settings:SetScript("OnClick", function()
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		if ns.ToggleOptions then ns.ToggleOptions() end
	end)
	searchRight = searchRight - 96 - 8

	-- Delete, immediately left of Settings so it sits beside the gear. Drop a held item on it,
	-- or click it while holding one. DeleteCursorItem requires a hardware event and destroys the
	-- cursor item immediately (it does NOT raise DELETE_ITEM_CONFIRM — Blizzard's confirmation
	-- popup calls DeleteCursorItem after you click Yes). When "Confirm delete (trash)" is ticked in
	-- Settings (the default), our own taint-free dialog asks first (and asks to type DELETE for
	-- rare and better items); when unticked, DeleteCursorItem runs right away.
	local DELETE_W = 22
	local deleteBtn = CreateFrame("Button", "DavesSackDeleteButton", frame)
	deleteBtn:SetSize(DELETE_W, 22)
	deleteBtn:SetPoint("TOPRIGHT", searchRight, -42)
	deleteBtn:SetFrameLevel(frame:GetFrameLevel() + 5)
	deleteBtn:RegisterForClicks("LeftButtonUp")
	local deleteIcon = deleteBtn:CreateTexture(nil, "ARTWORK")
	deleteIcon:SetPoint("CENTER")
	deleteIcon:SetSize(18, 18)
	deleteIcon:SetTexture(M .. "trash")
	local deleteHL = deleteBtn:CreateTexture(nil, "HIGHLIGHT")
	deleteHL:SetPoint("CENTER")
	deleteHL:SetSize(18, 18)
	deleteHL:SetTexture(M .. "trash")
	deleteHL:SetBlendMode("ADD")
	deleteHL:SetAlpha(0.4)
	-- Brighter while holding an item, and only listens to CURSOR_CHANGED while the bags are open.
	local function DropReady()
		local held = CursorHasItem and CursorHasItem()
		deleteIcon:SetAlpha(held and 1 or 0.65)
	end
	deleteBtn:SetScript("OnEvent", DropReady)
	deleteBtn:SetScript("OnShow", function(self)
		pcall(self.RegisterEvent, self, "CURSOR_CHANGED")
		DropReady()
	end)
	deleteBtn:SetScript("OnHide", function(self)
		pcall(self.UnregisterEvent, self, "CURSOR_CHANGED")
	end)
	-- A drop can fire OnClick, OnReceiveDrag and OnMouseUp in the same frame; only act once.
	local destroyPending
	local function DestroyHeld()
		if destroyPending or not (DeleteCursorItem and CursorHasItem and CursorHasItem() and GetCursorInfo) then return end
		local kind, itemID, itemLink = GetCursorInfo()
		if kind ~= "item" or not itemID then return end
		destroyPending = true
		C_Timer.After(0, function() destroyPending = false end)
		if ns.db.confirmDestroy == false then
			ns.HideDestroyConfirm(true)
			DeleteCursorItem()
		else
			AskDestroy(itemID, itemLink)
		end
	end
	deleteBtn:SetScript("OnClick", DestroyHeld)
	deleteBtn:SetScript("OnReceiveDrag", DestroyHeld)
	deleteBtn:SetScript("OnMouseUp", function(_, b) if b == "LeftButton" then DestroyHeld() end end)
	deleteBtn:SetScript("OnEnter", function(self)
		DropReady()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Delete / Trash")
		GameTooltip:AddLine(ns.db.confirmDestroy == false
			and "Drag an item here to destroy it immediately."
			or "Drag an item here to destroy it (asks to confirm).", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	deleteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	searchRight = searchRight - DELETE_W - 8

	local function OnSearch(self)
		local t = self:GetText()
		ns.searchText = t ~= "" and t:lower() or nil
		ApplySearch()
	end
	search = TryTemplate("EditBox", "DavesSackSearch", frame, "SearchBoxTemplate")
	if search then
		search:SetHeight(20)
		search:SetPoint("TOPLEFT", PAD + 6, -43)       -- template's left cap hangs out ~6px
		search:SetPoint("TOPRIGHT", searchRight, -43)
		search:HookScript("OnTextChanged", OnSearch)
	else
		search = CreateFrame("EditBox", "DavesSackSearch", frame, "InputBoxTemplate")
		search:SetAutoFocus(false); search:SetHeight(20)
		search:SetPoint("TOPLEFT", PAD + 6, -43); search:SetPoint("TOPRIGHT", searchRight, -43)
		search:SetScript("OnTextChanged", OnSearch)
	end
	search:SetScript("OnEnterPressed", search.ClearFocus)

	-- Scrolling grid: Blizzard's standard scroll frame, so the bar looks and
	-- scrolls like the rest of the UI (wheel, arrows, drag, click the track).
	-- On a client without it, a plain ScrollFrame plus our own slim bar.
	scroll = TryTemplate("ScrollFrame", "DavesSackScroll", frame, "ScrollFrameTemplate")
	nativeBar = scroll and scroll.ScrollBar
	if not nativeBar then
		scroll = scroll or CreateFrame("ScrollFrame", "DavesSackScroll", frame)
	end
	scroll:SetPoint("TOPLEFT", PAD, -TOP_H)
	scroll:SetSize(1, 1)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	if nativeBar then
		if nativeBar.SetHideIfUnscrollable then nativeBar:SetHideIfUnscrollable(true) end
		nativeBar:ClearAllPoints()
		nativeBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 0)
		nativeBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 0)
		if scroll.SetPanExtent then scroll:SetPanExtent(SLOT + GAP) end   -- one row per wheel notch
		-- Never set the scroll position from inside a scroll callback: Blizzard's
		-- bar and frame update each other, and changing the value there loops
		-- forever (v1.6 crashed with "C stack overflow" doing exactly that).
	else
		scroll:EnableMouseWheel(true)
		scroll:SetScript("OnMouseWheel", function(self, delta)
			ns.ScrollTo(self:GetVerticalScroll() - delta * (SLOT + GAP))
		end)
		track = Tex(frame, "ARTWORK", 0, LINE)
		track:SetWidth(4)
		track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", PAD - 7, 0)
		track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", PAD - 7, 0)
		thumb = CreateFrame("Button", nil, frame)
		thumb:SetWidth(8)
		thumb:SetFrameLevel(frame:GetFrameLevel() + 6)
		local tt = Tex(thumb, "ARTWORK", 0, { 0.55, 0.55, 0.58, 0.95 })
		tt:SetPoint("TOP"); tt:SetPoint("BOTTOM"); tt:SetWidth(4)
		local th = Tex(thumb, "HIGHLIGHT", 0, { 1, 0.82, 0, 0.6 })
		th:SetPoint("TOP"); th:SetPoint("BOTTOM"); th:SetWidth(4)
		local function Drag(self)
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then self:SetScript("OnUpdate", nil) return end
			local _, cy = GetCursorPosition()
			cy = cy / self:GetEffectiveScale()
			local free = track:GetHeight() - self:GetHeight()
			if free > 0 then ns.ScrollTo(self.startScroll + (self.startY - cy) * maxScroll / free) end
		end
		thumb:SetScript("OnMouseDown", function(self)
			local _, cy = GetCursorPosition()
			self.startY, self.startScroll = cy / self:GetEffectiveScale(), scroll:GetVerticalScroll()
			self:SetScript("OnUpdate", Drag)                   -- only runs while dragging
		end)
		thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
		thumb:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
	end

	-- Footer: divider, slot usage, gold, and bottom Auction House cache status.
	FOOT_H = FOOT_BASE + AhRowOffset()
	footLine = Rule(frame, "ARTWORK", 0, LINE)
	PlaceFooterLine()

	local ahOff = AhRowOffset()
	slotsText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	slotsText:SetPoint("BOTTOMLEFT", PAD + 4, 24 + ahOff)
	barBg = Tex(frame, "ARTWORK", 0, LINE)
	barBg:SetSize(BAR_W, 4); barBg:SetPoint("BOTTOMLEFT", PAD + 4, 14 + ahOff)
	barFill = Tex(frame, "ARTWORK", 1, { 0.85, 0.85, 0.85, 1 })
	barFill:SetHeight(4); barFill:SetPoint("LEFT", barBg, "LEFT")
	-- The reagent bag's counter sits to the right of the bag counter.
	reagentText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	reagentText:SetPoint("BOTTOMLEFT", barBg, "BOTTOMRIGHT", BAR_GAP, 10)
	reagentBarBg = Tex(frame, "ARTWORK", 0, LINE)
	reagentBarBg:SetSize(BAR_W, 4); reagentBarBg:SetPoint("BOTTOMLEFT", barBg, "BOTTOMRIGHT", BAR_GAP, 0)
	reagentBarFill = Tex(frame, "ARTWORK", 1, { 0.85, 0.85, 0.85, 1 })
	reagentBarFill:SetHeight(4); reagentBarFill:SetPoint("LEFT", reagentBarBg, "LEFT")
	reagentText:Hide(); reagentBarBg:Hide(); reagentBarFill:Hide()

	money = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	money:SetPoint("BOTTOMRIGHT", -PAD - 4, 17 + ahOff)

	ahRow = CreateFrame("Button", nil, frame)
	ahRow:SetHeight(14)
	ahRow:SetPoint("BOTTOMLEFT", PAD + 4, 15)
	ahRow:SetPoint("BOTTOMRIGHT", -PAD - 4, 15)
	ahRow:SetFrameLevel(frame:GetFrameLevel() + 6)
	ahValueText = ahRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	ahValueText:SetPoint("LEFT", ahRow, "LEFT", 0, 0)
	ahTimeText = ahRow:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	ahTimeText:SetPoint("RIGHT", ahRow, "RIGHT", 0, 0)
	ahScanBarBg = Tex(ahRow, "ARTWORK", 0, LINE)
	ahScanBarBg:SetHeight(3)
	ahScanBarBg:SetPoint("BOTTOMLEFT", ahRow, "BOTTOMLEFT", 0, -4)
	ahScanBarBg:SetPoint("BOTTOMRIGHT", ahRow, "BOTTOMRIGHT", 0, -4)
	ahScanBarFill = Tex(ahRow, "ARTWORK", 1, { 0.85, 0.68, 0.25, 1 })
	ahScanBarFill:SetHeight(3)
	ahScanBarFill:SetPoint("LEFT", ahScanBarBg, "LEFT")
	ahScanBarBg:Hide(); ahScanBarFill:Hide()
	ahRow:SetScript("OnReceiveDrag", function() ns.StoreCursorItem() end)
	ahRow:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" then ns.StoreCursorItem() end end)
	ahRow:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Auction House Price Cache")
		local cached = ns.ahCachedCount or 0
		if (ns.db and ns.db.ahUpdated) or cached > 0 then
			GameTooltip:AddDoubleLine("Tradeable Bag AH Value", MoneyString(ahBagValue), 1, 0.82, 0, 1, 1, 1)
			GameTooltip:AddDoubleLine("Priced Bag Stacks", format("%d / %d", ahPricedStacks, ahTradeableStacks), 1, 0.82, 0, 1, 1, 1)
			GameTooltip:AddDoubleLine("Cached Items", Group(cached), 1, 0.82, 0, 1, 1, 1)
			if ns.db and ns.db.ahUpdated then
				local age = (ns.FormatAge and ns.FormatAge(ns.db.ahUpdated)) or ""
				local stamp = date and date("%b %d, %H:%M", ns.db.ahUpdated) or nil
				GameTooltip:AddDoubleLine("Last Updated", stamp and (age .. " (" .. stamp .. ")") or age, 1, 0.82, 0, 1, 1, 1)
			end
		else
			GameTooltip:AddLine("No Auction House prices cached yet.", 0.7, 0.7, 0.7, true)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Prices update automatically when you open or browse the Auction House.", 0.65, 0.65, 0.65, true)
		GameTooltip:Show()
	end)
	ahRow:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local ahTick = 0
	ahRow:SetScript("OnUpdate", function(_, elapsed)
		ahTick = ahTick + (elapsed or 0)
		if ahTick < 15 then return end
		ahTick = 0
		if not ns.ahScanning and ns.db and ns.db.ahUpdated and ns.FormatAge then
			local age = ns.FormatAge(ns.db.ahUpdated)
			ahTimeText:SetText(age and ("Updated " .. age) or "")
		end
	end)

	-- Resize grips in the bottom corners (the top corners hold the gear and
	-- close buttons). Width snaps to whole columns; height is free and sticks.
	local rs = {}
	local resizer = CreateFrame("Frame"); resizer:Hide()
	resizer:SetScript("OnUpdate", function(self)
		if not rs.x then return end
		if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then rs.stop() return end
		local sc = frame:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		local dx, dy = cx / sc - rs.x, cy / sc - rs.y
		local w = min(rs.right and (rs.w + dx) or (rs.w - dx), rs.maxW)
		local cols = ns.ClampColumns(floor((w - PAD * 2 + GAP) / (SLOT + GAP) + 0.5))
		local vh = ns.db.viewHeight
		if vh or abs(dy) > 3 then                -- a sideways drag keeps "fit height" on
			vh = ns.ClampViewHeight(min(rs.maxH, rs.h - dy))
		end
		if cols ~= ns.db.columns then
			ns.db.columns, ns.db.viewHeight = cols, vh
			Layout()
		elseif vh ~= ns.db.viewHeight then
			ns.db.viewHeight = vh
			ns.ApplyView()
		else
			return
		end
		if ns.RefreshOptions then ns.RefreshOptions() end
	end)
	local function StartResize(right)
		local left, rightX, top = frame:GetLeft(), frame:GetRight(), frame:GetTop()
		if not (left and top) then return end
		local sc = frame:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		rs.right, rs.x, rs.y, rs.w, rs.h = right, cx / sc, cy / sc, frame:GetWidth(), scroll:GetHeight()
		-- never grow past the screen edge on the dragged side, or below the bottom
		local screenW = UIParent:GetWidth() * UIParent:GetEffectiveScale() / sc
		rs.maxW = right and (screenW - left) or rightX
		rs.maxH = top - TOP_H - FOOT_H - 4
		frame:ClearAllPoints()                  -- pin the top corner opposite the grip
		if right then frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		else frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", rightX, top) end
		resizer:Show()
	end
	local function StopResize()
		if not resizer:IsShown() then return end
		resizer:Hide()
		rs.x = nil
		SavePosition()
	end
	rs.stop = StopResize
	for _, right in ipairs({ true, false }) do
		local g = CreateFrame("Button", nil, frame)
		g:SetSize(16, 16)
		g:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", right and -3 or 3, 3)
		g:SetFrameLevel(frame:GetFrameLevel() + 20)
		local t = g:CreateTexture(nil, "OVERLAY"); t:SetTexture(M .. "grip"); t:SetAllPoints(); t:SetAlpha(0.55)
		local hl = g:CreateTexture(nil, "HIGHLIGHT"); hl:SetTexture(M .. "grip"); hl:SetAllPoints(); hl:SetBlendMode("ADD")
		if not right then t:SetTexCoord(1, 0, 0, 1); hl:SetTexCoord(1, 0, 0, 1) end
		g:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then StartResize(right) end end)
		g:SetScript("OnMouseUp", StopResize)
		g:SetScript("OnHide", StopResize)
		g:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Drag to resize"); GameTooltip:Show()
		end)
		g:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end

	frame:SetScript("OnShow", function()
		ns.BagSound("IG_BACKPACK_OPEN")
		UnpushClose()
		-- Categories ticked under "Start collapsed" in Settings open collapsed each time.
		local collapsed, startFolded = ns.db.collapsed, ns.db.startFolded
		for cat = 1, FREE_CAT do
			local want = startFolded[cat] or nil
			if collapsed[cat] ~= want then collapsed[cat] = want; layoutDirty = true end
		end
		refitHeight = true                         -- fit to what's in the bags now
		Update(true); UpdateCooldowns(); UpdateMoney(); ns.RefreshCurrencies()
		if refitHeight then ns.ApplyView() end     -- nothing changed since last time: fit anyway
	end)
	-- Never call Blizzard's bag functions (CloseAllBags, ToggleAllBags…) from
	-- here: they'd run tainted and taint Blizzard's bag state. The merchant
	-- window then inherits it when it opens the bags, and right-clicking an item
	-- there is blocked ("only available to the Blizzard UI", UseContainerItem).
	frame:SetScript("OnHide", function()
		search:ClearFocus()
		ns.ParkCurrencyOpen()
		ns.BagSound("IG_BACKPACK_CLOSE")
	end)
end

---------------------------------------------------------------------------
-- Replace the default bags
---------------------------------------------------------------------------
function ns.Open()  if not frame:IsShown() then frame:Show() end end
function ns.Close() if frame:IsShown() then frame:Hide() end end
-- /sack toggles our window alone (a slash command can't click Blizzard's backpack button securely), so Blizzard's
-- bags may be left out of step until the next key press or button click, which the hooks below follow.
function ns.Toggle() frame:SetShown(not frame:IsShown()) end

-- Whether Blizzard considers any of the bags we show open: read only (IsBagOpen looks at its frames' IsShown),
-- so nothing of Blizzard's is written from addon code.
local BACKPACK = Enum and Enum.BagIndex and Enum.BagIndex.Backpack or 0
function ns.BlizzardBagsOpen()
	if not IsBagOpen then return false end
	if IsBagOpen(BACKPACK) then return true end
	for id in pairs(inList) do if IsBagOpen(id) then return true end end
	return false
end

-- The bag open/close sounds: our window always plays its own. Blizzard's container frames play theirs from
-- OnShow/OnHide, which never run while a frame is parked on the hidden parent (below): it never becomes visible.
-- 1.7.10-1.7.13 hooked their OnShow/OnHide (HookScript) to tell; those hooks ran inside Blizzard's bag opening
-- and are gone. The bank taint itself came from the event muting below.
function ns.BagSound(kit) Sound(kit) end

local hidden = CreateFrame("Frame"); hidden:Hide()

-- While one of Blizzard's container frames is showing *your* bags we park it on a hidden parent, so only our
-- window is seen. On Classic clients bank bags reuse the same frames, so they get their parent back (Forever's
-- bank has no container frames). A parked frame never runs its OnShow, where Blizzard registers its bag-update
-- events, so it only keeps the few it registers at load (bag opened/closed, quest log, bag slots changed).
-- Never switch those off from here (1.1-1.7.13 did): together with our
-- window following Blizzard's bag calls (Follow, below), that tainted every window that opens the bags - the
-- bank and the mailbox - for the rest of the session. The bank's free first tab was blocked
-- ("PurchaseBankTab()"), and so was every item used from the bags in combat afterwards: Blizzard's item click
-- reads BankPanel.bankType even with the bank closed ("UseContainerItem()"). Found by switching each piece off
-- in game, 1.7.14.
local origParent = {}

local function Park(f)
	if f:GetParent() ~= hidden then origParent[f] = f:GetParent() end
	f:SetParent(hidden)
end

local function Unpark(f)
	if f:GetParent() == hidden then f:SetParent(origParent[f] or UIParent) end
end

local function Claim(f)
	if not (f and f.GetID) then return end
	if inList[f:GetID()] then Park(f) else Unpark(f) end
end

local function TakeOverBlizzardBags()
	-- Park every container frame now, before Blizzard first shows one: shown under UIParent first and parked
	-- after, a frame would play its open sound and then its close sound in the same instant. Bank bags get
	-- theirs back through Claim, after ContainerFrame_GenerateFrame (which shows every container frame).
	for i = 1, 20 do local f = _G["ContainerFrame" .. i]; if f then Park(f) end end
	if ContainerFrame_GenerateFrame then hooksecurefunc("ContainerFrame_GenerateFrame", Claim) end
	if ContainerFrameCombinedBags then Park(ContainerFrameCombinedBags) end

	-- After any of Blizzard's bag calls, our window follows Blizzard's own open/closed state (read only) instead
	-- of toggling by itself: the two can't drift apart (a drift made Blizzard's frames, and their sounds, run
	-- the opposite way to ours), and Blizzard's rules - bags opened by the mailbox or vendor close with it, bags
	-- you opened yourself stay open - apply to us for free. Several of these call each other; following the state
	-- is idempotent, so that doesn't matter.
	local function Follow()
		local open = ns.BlizzardBagsOpen()
		if open ~= frame:IsShown() then frame:SetShown(open) end
	end
	for _, name in ipairs({ "ToggleAllBags", "ToggleBackpack", "ToggleKeyRing", "OpenAllBags", "OpenBackpack",
		"CloseAllBags", "CloseBackpack", "ToggleBag", "OpenBag", "CloseBag" }) do
		if _G[name] then hooksecurefunc(name, Follow) end
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
local function TryRegister(e) pcall(events.RegisterEvent, events, e) end

local handlers = {
	BAG_UPDATE = function(bag) if bag then dirty[bag] = true end; Schedule() end,
	BAG_UPDATE_DELAYED = Schedule,
	-- Picking up / dropping an item: just repaint that one slot.
	ITEM_LOCK_CHANGED = function(bag, slot)
		if not (slot and bag) then return end
		if not frame:IsShown() then dirty[bag] = true; return end
		local list = buttons[bag]
		local b = list and slot <= list.n and list[slot]
		if not b then return end
		if ReadSlot(bag, slot, b.fbRec) then b.fbRec.recat = true; dirty[bag] = true; Schedule()
		else Paint(b) end
	end,
	-- Fires on every global cooldown: batch to one pass per frame.
	BAG_UPDATE_COOLDOWN = function() cdDirty = true; Schedule() end,
	PLAYER_MONEY = function() if frame:IsShown() then UpdateMoney() end end,
	CURRENCY_DISPLAY_UPDATE = function() ns.MarkCurrencies() end,
}

-- Item info arrived for something we had to file as Misc: re-check it.
handlers.GET_ITEM_INFO_RECEIVED = function(itemID)
	if not (itemID and ns.waiting[itemID]) then return end
	ns.waiting[itemID] = nil
	for bag, list in pairs(buttons) do
		for slot = 1, list.n do
			local rec = list[slot].fbRec
			if rec.id == itemID then rec.recat = true; dirty[bag] = true end
		end
	end
	Schedule()
end

local function RescaleSoon()
	C_Timer.After(0, function()
		UpdatePixels(); ns.ResetPosition()
		layoutDirty, refitHeight = true, true
		if frame:IsShown() then Layout() end
	end)
end
handlers.UI_SCALE_CHANGED = RescaleSoon
handlers.DISPLAY_SIZE_CHANGED = RescaleSoon
-- Outside combat: a button for every slot of every bag we show, so none is made in combat (see MakeButtons).
-- resync re-reads which bags we show first (they changed); a scan that met a slot without a button rescans.
local function PrepareButtons(resync)
	if InCombatLockdown() then return end
	if resync then SyncBagList() end
	for bag in pairs(inList) do MakeButtons(bag) end
	if missedInCombat then
		missedInCombat = false
		for bag in pairs(inList) do dirty[bag] = true end
		Schedule()
	end
end
handlers.BAG_CONTAINER_UPDATE = function() dirtyAll = true; PrepareButtons(true); Schedule() end
handlers.BAG_SLOT_FLAGS_UPDATED = handlers.BAG_CONTAINER_UPDATE
handlers.PLAYER_ENTERING_WORLD = handlers.BAG_CONTAINER_UPDATE   -- bag sizes are known by now

-- Combat: the secure close button leaves the window, so the window can still be shown and hidden (see Build), and
-- every item button is made beforehand (PLAYER_REGEN_DISABLED comes just before lockdown).
handlers.PLAYER_REGEN_DISABLED = function()
	if ns.CloseButtonForCombat then ns.CloseButtonForCombat(true) end
	ns.ParkCurrencyOpen()   -- off the window before lockdown, like the secure X
	PrepareButtons()
end
handlers.PLAYER_REGEN_ENABLED = function()
	if ns.CloseButtonForCombat then ns.CloseButtonForCombat(false) end
	PrepareButtons()
end

events:SetScript("OnEvent", function(_, event, ...) handlers[event](...) end)

function ns.OnLoad()
	Build()
	ns.ResetPosition()
	ns.ApplyScale()
	ns.db.viewHeight = ns.ClampViewHeight(ns.db.viewHeight)   -- saved sizes obey the limits too
	SyncBagList()
	PrepareButtons()
	TakeOverBlizzardBags()

	-- Split stacks: once you pick the amount, the new stack goes straight into
	-- a free slot, so it shows up beside the original (same category) with no
	-- scrolling to Free Space. Skipped while a window you'd drop it into is open.
	local splitPending = false
	local function PlaceSplit()
		splitPending = false
		if CursorHasItem and CursorHasItem() then ns.StoreCursorItem() end
	end
	local function OnSplit(bag)
		if splitPending or ns.db.autoPlaceSplit == false or not inList[bag] then return end
		if InteractionWindowOpen() then return end
		splitPending = true
		C_Timer.After(0, PlaceSplit)              -- next frame, once the stack is on the cursor
	end
	if C_Container and C_Container.SplitContainerItem then pcall(hooksecurefunc, C_Container, "SplitContainerItem", OnSplit) end

	-- "Show on Backpack" ticked/unticked in the Currency tab
	local function OnWatchChanged() ns.MarkCurrencies() end
	local C = C_CurrencyInfo
	if C and C.SetCurrencyBackpack then pcall(hooksecurefunc, C, "SetCurrencyBackpack", OnWatchChanged) end
	if C and C.SetCurrencyBackpackByID then pcall(hooksecurefunc, C, "SetCurrencyBackpackByID", OnWatchChanged) end
	for e in pairs(handlers) do TryRegister(e) end
end
