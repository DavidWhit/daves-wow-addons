-- daves_map / QuestDetails.lua
-- Drill-in Quest Text & Details reader inside Dave's Map's right content pane.
-- Displays live Quest Log objectives, completion text, full description, rewards (XP, coin, choice items,
-- fixed items, currencies, spells, titles, skill points), QuestieDB turn-in/chain context, and action buttons
-- (`Track`/`Untrack`, `Pin`/`Pinned`, `Link`, `Share`, `Abandon` with a taint-free HUD Edit Mode confirm dialog; uses the shared toolbar Back arrow beside Search).

local _, ns = ...

local ui = ns.PanelUI
local C = ns.PANEL_CONST
local LIST_PAD, SCROLL_GUTTER = C.LIST_PAD, C.SCROLL_GUTTER
local Sound = ns.Sound

local dState = {
	pane = nil,
	scroll = nil,
	body = nil,
	scrollBar = nil,
	nativeScroll = false,
	syncingScroll = false,
	trackBtn = nil,
	pinBtn = nil,
	shareBtn = nil,
	linkBtn = nil,
	abandonBtn = nil,
	titleFS = nil,
	metaFS = nil,
	groupBadge = nil,
	turnInBtn = nil,
	headers = {},
	lines = {},
	cards = {},
	chainRows = {},
	pendingItems = {},
	confirm = nil,
	confirmQuestID = nil,
	lastBodyW = 0,
	contentH = 0,
	scrollPx = 0,
	lastRenderedQ = nil,
}

---------------------------------------------------------------------------
-- Helper Controls & Pooled Elements
---------------------------------------------------------------------------
local function TryTemplate(kind, name, parent, template)
	local ok, f = pcall(CreateFrame, kind, name, parent, template)
	return ok and f or nil
end

local function MakeActionPill(parent, label, width, onClick, tip)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, 22)
	b:RegisterForClicks("LeftButtonUp", "Button4Up")
	b.frame = ns.AddBrassPillSlices(b, "BACKGROUND", 11, nil, 0.96, 0.92, 0.86, 0.72)
	b.hl = ns.AddBrassPillSlices(b, "HIGHLIGHT", 11, "ADD", 0.35)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("CENTER", 0, 0)
	b.text:SetText(label)
	b.tip = tip
	function b:SetPillEnabled(on)
		self.isDisabled = not on
		self:SetAlpha(on and 1 or 0.42)
		if self.hl then self.hl:SetAlpha(on and 0.35 or 0) end
	end
	b:SetScript("OnClick", function(self, button)
		if button == "Button4" then
			if ns.GoBack then ns.GoBack() end
			return
		end
		if self.isDisabled then return end
		onClick(self)
	end)
	b:SetScript("OnEnter", function(self)
		if not self.tip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(ns.StripCodes(self.text:GetText() or ""), 1, 0.82, 0.2)
		GameTooltip:AddLine(self.tip, 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

local function AcquireHeader(idx)
	local h = dState.headers[idx]
	if h then return h end
	h = CreateFrame("Frame", nil, dState.body)
	h:SetHeight(20)
	h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h.text:SetPoint("TOPLEFT", 0, 0)
	h.text:SetPoint("TOPRIGHT", 0, 0)
	h.text:SetJustifyH("LEFT")
	h.line = h:CreateTexture(nil, "ARTWORK")
	h.line:SetHeight(1)
	h.line:SetPoint("BOTTOMLEFT", 0, 0)
	h.line:SetPoint("BOTTOMRIGHT", 0, 0)
	h.line:SetColorTexture(0.85, 0.70, 0.35, 0.28)
	dState.headers[idx] = h
	return h
end

local function AcquireLine(idx)
	local fs = dState.lines[idx]
	if fs then return fs end
	fs = dState.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(true)
	fs:SetSpacing(2)
	dState.lines[idx] = fs
	return fs
end

local function AcquireCard(idx)
	local c = dState.cards[idx]
	if c then return c end
	c = CreateFrame("Button", nil, dState.body)
	c:SetHeight(32)
	c:RegisterForClicks("LeftButtonUp", "Button4Up")
	c.bg = c:CreateTexture(nil, "BACKGROUND")
	c.bg:SetAllPoints()
	c.bg:SetColorTexture(0.10, 0.08, 0.05, 0.56)
	c.border = CreateFrame("Frame", nil, c, BackdropTemplateMixin and "BackdropTemplate" or nil)
	c.border:SetAllPoints()
	c.border:EnableMouse(false)
	if c.border.SetBackdrop then
		c.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		c.border:SetBackdropBorderColor(0.42, 0.34, 0.18, 0.55)
	end
	local hl = c:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.84, 0.25, 0.14)
	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetSize(24, 24)
	c.icon:SetPoint("LEFT", 4, 0)
	c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	c.qty = c:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	c.qty:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT", 1, -1)
	c.qty:SetJustifyH("RIGHT")
	c.name = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.name:SetPoint("LEFT", c.icon, "RIGHT", 7, 0)
	c.name:SetPoint("RIGHT", c, "RIGHT", -6, 0)
	c.name:SetJustifyH("LEFT")
	c.name:SetWordWrap(false)
	c:SetScript("OnClick", function(self, button)
		if button == "Button4" then
			if ns.GoBack then ns.GoBack() end
			return
		end
		if IsModifiedClick and IsModifiedClick("CHATLINK") then
			local link = self.link
			if not link and self.itemID then
				local _, _, _, _, itemLink = ns.ItemDisplay(self.itemID)
				link = itemLink
			end
			local insertLink = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
			if link and insertLink then insertLink(link) end
		end
	end)
	c:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.kind == "item" then
			if self.link and GameTooltip.SetHyperlink then
				GameTooltip:SetHyperlink(self.link)
			elseif self.itemID and GameTooltip.SetItemByID then
				GameTooltip:SetItemByID(self.itemID)
			elseif self.tipTitle then
				GameTooltip:SetText(self.tipTitle, 1, 1, 1)
			end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Shift-click: link item in chat", 0.5, 0.8, 1)
			GameTooltip:Show()
			if IsModifiedClick and IsModifiedClick("COMPAREITEMS") and GameTooltip_ShowCompareItem then
				GameTooltip_ShowCompareItem(GameTooltip)
			end
		elseif self.kind == "currency" and self.currencyID then
			if GameTooltip.SetCurrencyByID then
				GameTooltip:SetCurrencyByID(self.currencyID, self.amount)
			else
				GameTooltip:SetText(self.tipTitle or "Currency", 1, 1, 1)
			end
			GameTooltip:Show()
		elseif self.kind == "spell" and self.spellID then
			if GameTooltip.SetSpellByID then
				GameTooltip:SetSpellByID(self.spellID)
			else
				GameTooltip:SetText(self.tipTitle or "Spell", 1, 1, 1)
			end
			GameTooltip:Show()
		end
	end)
	c:SetScript("OnLeave", GameTooltip_Hide)
	dState.cards[idx] = c
	return c
end

local function AcquireChainRow(idx)
	local r = dState.chainRows[idx]
	if r then return r end
	r = CreateFrame("Button", nil, dState.body)
	r:SetHeight(22)
	r:RegisterForClicks("LeftButtonUp", "Button4Up")
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.84, 0.25, 0.14)
	r.num = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	r.num:SetPoint("LEFT", 4, 0)
	r.num:SetWidth(22)
	r.num:SetJustifyH("LEFT")
	r.status = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	r.status:SetPoint("RIGHT", -4, 0)
	r.status:SetJustifyH("RIGHT")
	r.title = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.title:SetPoint("LEFT", r.num, "RIGHT", 2, 0)
	r.title:SetPoint("RIGHT", r.status, "LEFT", -8, 0)
	r.title:SetJustifyH("LEFT")
	r.title:SetWordWrap(false)
	r:SetScript("OnClick", function(self, button)
		if button == "Button4" then
			if ns.GoBack then ns.GoBack() end
			return
		end
		if not self.pin then return end
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		local stepQ = ns.LogQuestIDForPin and ns.LogQuestIDForPin(self.pin) or nil
		if ns.CloseDungeonView then ns.CloseDungeonView() end
		local target = ns.ActivePinTarget and ns.ActivePinTarget(self.pin) or self.pin
		if stepQ and stepQ ~= ui.detailQuestID and ns.QuestInLog(stepQ) then
			ns.OpenQuestDetails(stepQ, self.pin)
			ns.SetFocusedPin(self.pin, true)
			ns.ShowPinMap(target, true)
		else
			ns.SetFocusedPin(self.pin, true)
			ns.ShowPinMap(target, true)
		end
	end)
	dState.chainRows[idx] = r
	return r
end

---------------------------------------------------------------------------
-- Taint-Free HUD Edit Mode Abandon Confirmation Dialog
---------------------------------------------------------------------------
local function BuildAbandonDialog()
	if dState.confirm then return dState.confirm end
	local f = CreateFrame("Frame", "DavesMapAbandonConfirm", UIParent)
	f:SetSize(340, 152)
	f:SetFrameStrata("DIALOG")
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	tinsert(UISpecialFrames, "DavesMapAbandonConfirm")

	local border = TryTemplate("Frame", nil, f, "DialogBorderTranslucentTemplate")
	if border then
		border:SetAllPoints()
	else
		border = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
		border:SetAllPoints()
		border:SetFrameLevel(f:GetFrameLevel())
		border:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		border:SetBackdropColor(0, 0, 0, 0.85)
	end
	f.border = border

	f.heading = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	f.heading:SetPoint("TOP", 0, -15)
	f.heading:SetText("Abandon Quest")

	f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.body:SetPoint("TOPLEFT", 20, -44)
	f.body:SetPoint("TOPRIGHT", -20, -44)
	f.body:SetJustifyH("CENTER")
	f.body:SetWordWrap(true)
	f.body:SetSpacing(3)

	f.yesBtn = MakeActionPill(f, "|cffff6b6bAbandon|r", 112, function()
		local q = dState.confirmQuestID
		dState.confirmQuestID = nil
		f:Hide()
		if q and ns.QuestInLog(q) and C_QuestLog.CanAbandonQuest and C_QuestLog.CanAbandonQuest(q) then
			C_QuestLog.SetSelectedQuest(q)
			C_QuestLog.SetAbandonQuest()
			C_QuestLog.AbandonQuest()
			Sound("IG_QUEST_LOG_ABANDON_QUEST")
			if ui.detailQuestID == q and ns.CloseQuestDetails then
				ns.CloseQuestDetails(true)
			end
		end
	end)
	f.yesBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -8, 16)

	f.noBtn = MakeActionPill(f, "|cffe8d8a8Cancel|r", 112, function()
		Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
		dState.confirmQuestID = nil
		f:Hide()
	end)
	f.noBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", 8, 16)

	f:SetScript("OnHide", function()
		dState.confirmQuestID = nil
	end)
	dState.confirm = f
	return f
end

local function PromptAbandonQuest(questID)
	if not (questID and ns.QuestInLog(questID) and C_QuestLog.CanAbandonQuest and C_QuestLog.CanAbandonQuest(questID)) then
		return
	end
	local f = BuildAbandonDialog()
	dState.confirmQuestID = questID
	local prevSelected = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest() or 0
	C_QuestLog.SetSelectedQuest(questID)
	C_QuestLog.SetAbandonQuest()
	local title = ns.QuestTitle(questID) or ("Quest #" .. tostring(questID))
	local items = C_QuestLog.GetAbandonQuestItems and C_QuestLog.GetAbandonQuestItems() or nil
	local itemNames = {}
	if type(items) == "table" then
		for _, iid in ipairs(items) do
			local nm = ns.ItemDisplay and ns.ItemDisplay(iid) or nil
			itemNames[#itemNames + 1] = nm or ("Item #" .. tostring(iid))
		end
	end
	if prevSelected and prevSelected ~= 0 and prevSelected ~= questID then
		C_QuestLog.SetSelectedQuest(prevSelected)
	end
	local msg = ("Abandon |cffffd200%s|r?"):format(title)
	if #itemNames > 0 then
		msg = msg .. "\n\n|cffff8888Destroys quest item(s):|r " .. table.concat(itemNames, ", ")
	end
	f.body:SetText(msg)
	local textH = math.max(36, math.ceil((f.body:GetStringHeight() or 36) + 0.5))
	f:SetHeight(math.max(126, textH + 92))
	if ns.ApplyDialogBackground and ns.db then
		local a = math.max(0.2, math.min(1.0, ns.db.background or 0.8))
		local style = ns.BackgroundStyle and ns.BackgroundStyle(ns.db.backgroundStyle)
		ns.ApplyDialogBackground(f.border, a, style)
	end
	Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
	f:Show()
end

---------------------------------------------------------------------------
-- Scrollbar Sync
---------------------------------------------------------------------------
local function SyncDetailsScroll()
	if not (dState.scroll and dState.body) then return end
	local viewH = dState.scroll:GetHeight() or 0
	local totalH = dState.contentH or 0
	local maxScroll = math.max(0, totalH - viewH)
	dState.scrollPx = math.max(0, math.min(dState.scrollPx or 0, maxScroll))
	dState.scroll:SetVerticalScroll(dState.scrollPx)
	local showScroll = maxScroll > 1 and viewH > 0
	if dState.scrollBar and dState.nativeScroll then
		dState.syncingScroll = true
		if not showScroll then
			dState.scrollBar:SetVisibleExtentPercentage(1)
			dState.scrollBar:SetScrollPercentage(0, true)
		else
			local visPct = math.max(0.06, math.min(0.99, viewH / totalH))
			local panPct = math.max(0.02, math.min(0.5, 48 / maxScroll))
			dState.scrollBar:SetPanExtentPercentage(panPct)
			dState.scrollBar:SetVisibleExtentPercentage(visPct)
			dState.scrollBar:SetScrollPercentage(dState.scrollPx / maxScroll, true)
		end
		dState.syncingScroll = false
	end
end

---------------------------------------------------------------------------
-- Quest Text & Rewards Layout Builder
---------------------------------------------------------------------------
local function QualityHex(quality)
	if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
		local c = ITEM_QUALITY_COLORS[quality]
		return ("ff%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
	end
	return "ffffffff"
end

local function RefreshDetails(resetScroll)
	if not (dState.pane and dState.pane:IsShown()) then return end
	local q = ui.detailQuestID
	if not (type(q) == "number" and q ~= 0 and not issecretvalue(q)) then
		dState.pane:Hide()
		return
	end
	local inLog = ns.QuestInLog(q)
	if not inLog then
		if ns.CloseQuestDetails then ns.CloseQuestDetails(true) end
		return
	end

	local logIndex = ns.QuestLogIndex(q)
	if not logIndex then
		if ns.CloseQuestDetails then ns.CloseQuestDetails(true) end
		return
	end
	local info = ns.QuestInfo(logIndex)
	if not info then return end

	local prevSelected = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest() or 0
	C_QuestLog.SetSelectedQuest(q)

	-- Update header action pills
	local watched = ns.QuestWatched(q)
	dState.trackBtn.text:SetText(watched and "|cffffd200Untrack|r" or "|cffe8d8a8Track|r")
	dState.trackBtn:SetWidth(watched and 68 or 58)
	dState.trackBtn:SetPillEnabled(true)

	local isPinned = (ns.db and ns.db.pinned and ns.db.pinned[q] == true) == true
	local isReady = ns.QuestReady(q)
	if isPinned then
		dState.pinBtn.text:SetText("|cff9ea4b0Pinned|r")
		dState.pinBtn:SetWidth(58)
		dState.pinBtn.tip = "This quest is already pinned so it stays tracked across zones. Click Untrack (or the tracker pin) to unpin it."
		dState.pinBtn:SetPillEnabled(false)
	elseif isReady then
		dState.pinBtn.text:SetText("|cffe8d8a8Pin|r")
		dState.pinBtn:SetWidth(46)
		dState.pinBtn.tip = "Ready to turn in quests stay in the Ready to Turn In section automatically."
		dState.pinBtn:SetPillEnabled(false)
	else
		dState.pinBtn.text:SetText("|cffe8d8a8Pin|r")
		dState.pinBtn:SetWidth(46)
		dState.pinBtn.tip = "Pin this quest so it stays tracked on the Objective Tracker even when you change zones."
		dState.pinBtn:SetPillEnabled(true)
	end

	local canShare = (C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(q) == true) and (IsInGroup and IsInGroup() == true)
	dState.shareBtn:SetPillEnabled(canShare)

	dState.linkBtn:SetPillEnabled(true)

	local canAbandon = C_QuestLog.CanAbandonQuest and C_QuestLog.CanAbandonQuest(q) == true
	dState.abandonBtn:SetPillEnabled(canAbandon)

	-- Reset pooled widgets & hide any tooltip owned by a pooled element
	local tipOwner = GameTooltip:IsShown() and GameTooltip:GetOwner() or nil
	wipe(dState.pendingItems)
	for _, h in ipairs(dState.headers) do h:Hide() end
	for _, fs in ipairs(dState.lines) do fs:Hide(); fs:SetText("") end
	for _, c in ipairs(dState.cards) do
		if tipOwner == c then GameTooltip:Hide(); tipOwner = nil end
		c:Hide()
		c.itemID, c.link, c.currencyID, c.spellID, c.amount, c.tipTitle, c.kind = nil, nil, nil, nil, nil, nil, nil
		c.icon:SetVertexColor(1, 1, 1)
		c.icon:SetDesaturated(false)
		c.qty:SetText("")
	end
	for _, r in ipairs(dState.chainRows) do
		if tipOwner == r then GameTooltip:Hide(); tipOwner = nil end
		r:Hide()
		r.pin = nil
	end
	if tipOwner == dState.turnInBtn or tipOwner == dState.groupBadge then
		GameTooltip:Hide()
	end
	dState.turnInBtn:Hide()
	dState.groupBadge:Hide()
	dState.groupBadge.questID = nil

	local rawScrollW = dState.scroll:GetWidth()
	local scrollW = (type(rawScrollW) == "number" and not issecretvalue(rawScrollW) and rawScrollW > 0) and rawScrollW or 460
	local bodyW = math.max(220, math.floor(scrollW - 8))
	dState.lastBodyW = bodyW
	dState.body:SetWidth(bodyW)

	local y = 4
	local nHead, nLine, nCard, nChain = 0, 0, 0, 0

	local function AddHeader(text)
		nHead = nHead + 1
		local h = AcquireHeader(nHead)
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", 0, -y)
		h:SetWidth(bodyW)
		h.text:SetText("|cffffd200" .. text .. "|r")
		h:Show()
		y = y + 24
	end

	local function AddParagraph(text, r, g, b, indent)
		if not text or text == "" then return end
		nLine = nLine + 1
		local fs = AcquireLine(nLine)
		local left = indent or 0
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", left, -y)
		fs:SetWidth(math.max(120, bodyW - left))
		fs:SetTextColor(r or 0.92, g or 0.90, b or 0.84)
		fs:SetText(text)
		fs:Show()
		local h = math.max(14, math.ceil((fs:GetStringHeight() or 14) + 0.5))
		y = y + h + 6
	end

	-- 1. Title & Metadata
	local lvl = info.level or 0
	local title = info.title or ns.QuestTitle(q) or ("Quest #" .. tostring(q))
	local isComplete = ns.QuestComplete(q) == true or ns.QuestReady(q)
	local isFailed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(q) == true
	local lvlPrefix = (lvl > 0 and ns.DiffHex) and ("|c%s[%d]|r "):format(ns.DiffHex(lvl), lvl) or ""
	local failSuffix = isFailed and " |cffff4444(Failed)|r" or ""

	dState.titleFS:ClearAllPoints()
	dState.titleFS:SetPoint("TOPLEFT", 0, -y)
	dState.titleFS:SetWidth(bodyW)
	dState.titleFS:SetText(lvlPrefix .. "|cffffdf70" .. title .. "|r" .. failSuffix)
	dState.titleFS:Show()
	y = y + math.max(20, math.ceil((dState.titleFS:GetStringHeight() or 20) + 0.5)) + 3

	local metaParts = {}
	if isFailed then
		metaParts[#metaParts + 1] = "|cffff4444Failed|r"
	elseif isComplete then
		metaParts[#metaParts + 1] = "|cffffd200Ready to Turn In|r"
	elseif isPinned then
		metaParts[#metaParts + 1] = "|cffffd200Pinned|r"
	elseif watched then
		metaParts[#metaParts + 1] = "|cff59ff73Tracked|r"
	else
		metaParts[#metaParts + 1] = "|cff9ea4b0In Quest Log|r"
	end

	local tagInfo = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(q) or nil
	if tagInfo and tagInfo.tagName and not issecretvalue(tagInfo.tagName) and tagInfo.tagName ~= "" then
		metaParts[#metaParts + 1] = "|cff7fd4ff" .. tagInfo.tagName .. "|r"
	end
	local sugGroup = (C_QuestLog.GetSuggestedGroupSize and C_QuestLog.GetSuggestedGroupSize(q)) or info.suggestedGroup or 0
	if type(sugGroup) == "number" and not issecretvalue(sugGroup) and sugGroup > 0 then
		metaParts[#metaParts + 1] = ("|cffe8d8a8Group (%d)|r"):format(sugGroup)
	end
	local pin = ui.detailPin or (ns.QuestPin and ns.QuestPin(q))
	if not pin and ns.FindQuestPinsForTracker then
		local found = ns.FindQuestPinsForTracker(q)
		pin = found and found[1] or nil
	end
	local qZone = (pin and ns.ZoneName and ns.ZoneName(pin)) or nil
	if not qZone then
		local qMap = ns.QuestUiMapID and ns.QuestUiMapID(q) or 0
		local mInfo = (qMap and qMap ~= 0 and C_Map.GetMapInfo) and C_Map.GetMapInfo(qMap) or nil
		qZone = mInfo and mInfo.name or nil
	end
	if qZone and qZone ~= "" then
		metaParts[#metaParts + 1] = "|cffc0c6d0" .. qZone .. "|r"
	end
	local timeLeft = GetQuestLogTimeLeft and GetQuestLogTimeLeft() or nil
	if type(timeLeft) == "number" and not issecretvalue(timeLeft) and timeLeft > 0 and SecondsToTime then
		metaParts[#metaParts + 1] = "|cffffa040Time: " .. SecondsToTime(timeLeft) .. "|r"
	end

	local gCnt = (ns.ShowGroupQuestCount and ns.ShowGroupQuestCount() and IsInGroup and IsInGroup() and ns.GroupQuestCount)
		and ns.GroupQuestCount(q) or 0
	local metaLeft = 0
	if gCnt and gCnt > 0 then
		dState.groupBadge.questID = q
		local bw = ns.StyleGroupCountPill(dState.groupBadge, gCnt)
		dState.groupBadge:ClearAllPoints()
		dState.groupBadge:SetPoint("TOPLEFT", 0, -y + 2)
		dState.groupBadge:Show()
		metaLeft = bw + 6
	end
	dState.metaFS:ClearAllPoints()
	dState.metaFS:SetPoint("TOPLEFT", metaLeft, -y)
	dState.metaFS:SetWidth(math.max(120, bodyW - metaLeft))
	dState.metaFS:SetText(table.concat(metaParts, "  -  "))
	dState.metaFS:Show()
	y = y + math.max(18, math.ceil((dState.metaFS:GetStringHeight() or 16) + 0.5)) + 10

	-- 2. Objectives & Turn-In
	local description, objectivesText = GetQuestLogQuestText(logIndex)
	if issecretvalue(description) then description = nil end
	if issecretvalue(objectivesText) then objectivesText = nil end

	AddHeader("Objectives")
	local numObj = (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(logIndex)) or 0
	if issecretvalue(numObj) then numObj = 0 end
	local anyObjective = false
	for i = 1, numObj do
		local objText, _, finished = GetQuestLogLeaderBoard(i, logIndex)
		if type(objText) == "string" and not issecretvalue(objText) and objText ~= "" then
			anyObjective = true
			if finished then
				AddParagraph("[Done] " .. objText, 0.55, 0.85, 0.58, 8)
			else
				AddParagraph("- " .. objText, 0.96, 0.96, 0.96, 8)
			end
		end
	end
	local reqMoney = C_QuestLog.GetRequiredMoney and C_QuestLog.GetRequiredMoney(q) or 0
	if type(reqMoney) == "number" and not issecretvalue(reqMoney) and reqMoney > 0 then
		anyObjective = true
		local have = GetMoney and GetMoney() or 0
		local doneM = (not issecretvalue(have)) and have >= reqMoney
		local coinStr = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) and C_CurrencyInfo.GetCoinTextureString(reqMoney) or tostring(reqMoney)
		AddParagraph((doneM and "[Done] Required money: " or "- Required money: ") .. coinStr, doneM and 0.55 or 0.96, doneM and 0.85 or 0.96, doneM and 0.58 or 0.96, 8)
	end
	if isComplete then
		local compText = GetQuestLogCompletionText and GetQuestLogCompletionText(logIndex) or nil
		if type(compText) == "string" and not issecretvalue(compText) and compText ~= "" then
			AddParagraph(compText, 1, 0.88, 0.35, 8)
			anyObjective = true
		end
	end
	local D = ns.DATA
	local endPin = (pin and D and D.endp and D.endp[pin] and D.endp[pin] ~= 0) and D.endp[pin] or nil
	if endPin and D.title[endPin] then
		local eZone = ns.ZoneName and ns.ZoneName(endPin) or nil
		local turnTxt = "Turn in: |cff7fd4ff" .. D.title[endPin] .. "|r" .. (eZone and (" (" .. eZone .. ")") or "")
		dState.turnInBtn.targetPin = endPin
		dState.turnInBtn.lbl:SetText(turnTxt)
		dState.turnInBtn:ClearAllPoints()
		dState.turnInBtn:SetPoint("TOPLEFT", 8, -y)
		dState.turnInBtn:SetWidth(math.max(120, bodyW - 8))
		dState.turnInBtn:Show()
		y = y + 22
		anyObjective = true
	end
	if type(objectivesText) == "string" and objectivesText ~= "" then
		AddParagraph(objectivesText, 0.90, 0.86, 0.76, 0)
		anyObjective = true
	end
	if not anyObjective then
		AddParagraph("No objective text available.", 0.65, 0.68, 0.72, 0)
	end
	y = y + 6

	-- 3. Description
	if type(description) == "string" and description ~= "" then
		AddHeader("Description")
		AddParagraph(description, 0.90, 0.86, 0.76, 0)
		y = y + 6
	end

	-- 4. Rewards
	local showRewards = (not C_QuestLog.ShouldShowQuestRewards) or (C_QuestLog.ShouldShowQuestRewards(q) ~= false)
	if showRewards then
		local xp = GetQuestLogRewardXP and GetQuestLogRewardXP() or 0
		local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney() or 0
		local honor = GetQuestLogRewardHonor and GetQuestLogRewardHonor() or 0
		local titleReward = GetQuestLogRewardTitle and GetQuestLogRewardTitle() or nil
		local skillName, _, skillPts = nil, nil, 0
		if GetQuestLogRewardSkillPoints then
			skillName, _, skillPts = GetQuestLogRewardSkillPoints()
		end
		local numChoices = GetNumQuestLogChoices and GetNumQuestLogChoices(q, true) or 0
		local numFixed = GetNumQuestLogRewards and GetNumQuestLogRewards() or 0
		local currencies = (C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardCurrencies and C_QuestInfoSystem.GetQuestRewardCurrencies(q))
			or (C_QuestLog.GetQuestRewardCurrencies and C_QuestLog.GetQuestRewardCurrencies(q)) or {}
		local spells = (C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardSpells and C_QuestInfoSystem.GetQuestRewardSpells(q)) or {}

		if issecretvalue(xp) then xp = 0 end
		if issecretvalue(money) then money = 0 end
		if issecretvalue(honor) then honor = 0 end
		if issecretvalue(numChoices) then numChoices = 0 end
		if issecretvalue(numFixed) then numFixed = 0 end

		local hasRewards = (xp > 0) or (money > 0) or (honor > 0)
			or (type(titleReward) == "string" and not issecretvalue(titleReward) and titleReward ~= "")
			or (type(skillName) == "string" and not issecretvalue(skillName) and skillPts and skillPts > 0)
			or numChoices > 0 or numFixed > 0 or #currencies > 0 or #spells > 0

		if hasRewards then
			AddHeader("Rewards")
			local sumParts = {}
			if xp > 0 then
				sumParts[#sumParts + 1] = ("|cffe8d8a8%s XP|r"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or tostring(xp))
			end
			if money > 0 then
				local coin = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) and C_CurrencyInfo.GetCoinTextureString(money) or tostring(money)
				sumParts[#sumParts + 1] = coin
			end
			if honor > 0 then
				sumParts[#sumParts + 1] = ("|cff7fd4ff%d Honor|r"):format(honor)
			end
			if type(skillName) == "string" and not issecretvalue(skillName) and skillPts and skillPts > 0 then
				sumParts[#sumParts + 1] = ("|cff59ff73+%d %s|r"):format(skillPts, skillName)
			end
			if type(titleReward) == "string" and not issecretvalue(titleReward) and titleReward ~= "" then
				sumParts[#sumParts + 1] = ("|cffffd200Title: %s|r"):format(titleReward)
			end
			if #sumParts > 0 then
				AddParagraph(table.concat(sumParts, "    "), 0.95, 0.92, 0.85, 0)
			end

			local function PlaceCards(list)
				if #list == 0 then return end
				local cols = bodyW >= 390 and 2 or 1
				local gap = 6
				local cardW = cols == 2 and math.floor((bodyW - gap) / 2) or bodyW
				for idx, spec in ipairs(list) do
					nCard = nCard + 1
					local card = AcquireCard(nCard)
					local col = (idx - 1) % cols
					local rowIdx = math.floor((idx - 1) / cols)
					local cx = col * (cardW + gap)
					local cy = y + rowIdx * 36
					card:ClearAllPoints()
					card:SetPoint("TOPLEFT", cx, -cy)
					card:SetWidth(cardW)
					card.kind = spec.kind
					card.itemID = spec.itemID
					card.link = spec.link
					card.currencyID = spec.currencyID
					card.spellID = spec.spellID
					card.amount = spec.amount
					card.tipTitle = spec.name
					card.icon:SetTexture(spec.texture or 134400)
					if spec.usable == false then
						card.icon:SetVertexColor(0.95, 0.25, 0.25)
					else
						card.icon:SetVertexColor(1, 1, 1)
					end
					card.qty:SetText((spec.amount and spec.amount > 1) and tostring(spec.amount) or "")
					card.name:SetText(("|c%s%s|r"):format(spec.hex or "ffffffff", spec.name or "Reward"))
					card:Show()
				end
				local rows = math.ceil(#list / cols)
				y = y + rows * 36 + 4
			end

			local cList = {}
			if numChoices > 0 then
				for i = 1, numChoices do
					local lootType = (GetQuestLogChoiceInfoLootType and GetQuestLogChoiceInfoLootType(i)) or 0
					if lootType == 1 and C_QuestLog.GetQuestRewardCurrencyInfo then
						local ci = C_QuestLog.GetQuestRewardCurrencyInfo(q, i, true)
						if ci and ci.name and not issecretvalue(ci.name) then
							cList[#cList + 1] = {
								kind = "currency", currencyID = ci.currencyID, name = ci.name,
								texture = ci.texture, amount = ci.totalRewardAmount or ci.quantity,
								hex = QualityHex(ci.quality), usable = true,
							}
						end
					else
						local name, tex, count, quality, usable, itemID = GetQuestLogChoiceInfo(i)
						if name and not issecretvalue(name) then
							local link = GetQuestLogItemLink and GetQuestLogItemLink("choice", i) or nil
							if issecretvalue(link) then link = nil end
							cList[#cList + 1] = {
								kind = "item", itemID = itemID, link = link, name = name, texture = tex,
								amount = count, hex = QualityHex(quality), usable = usable ~= false,
							}
						elseif type(itemID) == "number" and itemID > 0 and not issecretvalue(itemID) then
							dState.pendingItems[itemID] = true
							if C_Item and C_Item.RequestLoadItemDataByID then
								C_Item.RequestLoadItemDataByID(itemID)
							end
						end
					end
				end
				if #cList > 0 then
					AddParagraph(#cList == 1 and "You will receive:" or "Choose one of these rewards:", 0.82, 0.84, 0.88, 0)
					PlaceCards(cList)
				end
			end

			local fList = {}
			for i = 1, numFixed do
				local name, tex, count, quality, usable, itemID = GetQuestLogRewardInfo(i)
				if name and not issecretvalue(name) then
					local link = GetQuestLogItemLink and GetQuestLogItemLink("reward", i) or nil
					if issecretvalue(link) then link = nil end
					fList[#fList + 1] = {
						kind = "item", itemID = itemID, link = link, name = name, texture = tex,
						amount = count, hex = QualityHex(quality), usable = usable ~= false,
					}
				elseif type(itemID) == "number" and itemID > 0 and not issecretvalue(itemID) then
					dState.pendingItems[itemID] = true
					if C_Item and C_Item.RequestLoadItemDataByID then
						C_Item.RequestLoadItemDataByID(itemID)
					end
				end
			end
			for _, ci in ipairs(currencies) do
				if ci and ci.name and not issecretvalue(ci.name) then
					fList[#fList + 1] = {
						kind = "currency", currencyID = ci.currencyID, name = ci.name,
						texture = ci.texture, amount = ci.totalRewardAmount or ci.quantity,
						hex = QualityHex(ci.quality), usable = true,
					}
				end
			end
			for _, spellID in ipairs(spells) do
				if type(spellID) == "number" and spellID > 0 and C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardSpellInfo then
					local knownSpell = false
					if C_SpellBook and C_SpellBook.IsSpellInSpellBook and Enum and Enum.SpellBookSpellBank then
						knownSpell = C_SpellBook.IsSpellInSpellBook(spellID, Enum.SpellBookSpellBank.Player, true) == true
					end
					local si = C_QuestInfoSystem.GetQuestRewardSpellInfo(q, spellID)
					if si and si.texture and not knownSpell and si.name and not issecretvalue(si.name) then
						fList[#fList + 1] = {
							kind = "spell", spellID = spellID, name = si.name,
							texture = si.texture, amount = 1, hex = "ff7fd4ff", usable = true,
						}
					end
				end
			end
			if #fList > 0 then
				AddParagraph(#cList > 0 and "You will also receive:" or "You will receive:", 0.82, 0.84, 0.88, 0)
				PlaceCards(fList)
			end
			y = y + 4
		end
	end

	-- 5. Quest Chain Context (when QuestieDB knows this quest's chain)
	if pin and ns.ChainFor then
		local ch = ns.ChainFor(pin)
		if ch and #ch.steps > 1 then
			local doneCnt = 0
			for _, s in ipairs(ch.steps) do
				if ns.PinDone(s) then doneCnt = doneCnt + 1 end
			end
			AddHeader(("Quest Chain (%d/%d completed)"):format(doneCnt, #ch.steps))
			for idx, stepPin in ipairs(ch.steps) do
				nChain = nChain + 1
				local row = AcquireChainRow(nChain)
				row.pin = stepPin
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -y)
				row:SetWidth(bodyW)
				local sst = ns.PinQuestState and ns.PinQuestState(stepPin) or nil
				local isCur = (stepPin == pin) or (D and D.qid[stepPin] == q)
				local sTitle = (D and D.title[stepPin]) or ("Step " .. idx)
				if isCur then
					row.num:SetText(("|cffffd200%d.|r"):format(idx))
					row.title:SetText("|cffffd200" .. sTitle .. "|r")
					row.status:SetText(isComplete and "|cffffd200Ready|r" or "|cff7fd4ffCurrent|r")
				elseif sst == "done" then
					row.num:SetText(("|cff777b84%d.|r"):format(idx))
					row.title:SetText("|cff777b84" .. sTitle .. "|r")
					row.status:SetText("|cff6d8f74Done|r")
				else
					row.num:SetText(("|cff59ff73%d.|r"):format(idx))
					row.title:SetText("|cffc8d8c8" .. sTitle .. "|r")
					if sst == "ready" then
						row.status:SetText("|cffffd200Ready|r")
					elseif sst == "log" then
						row.status:SetText("|cff7fd4ffIn Log|r")
					else
						row.status:SetText("|cff888888Next|r")
					end
				end
				row:Show()
				y = y + 23
			end
			y = y + 6
		end
	end

	if prevSelected and prevSelected ~= 0 and prevSelected ~= q then
		C_QuestLog.SetSelectedQuest(prevSelected)
	end

	dState.contentH = y + 12
	dState.body:SetHeight(dState.contentH)
	if resetScroll or dState.lastRenderedQ ~= q then
		dState.scrollPx = 0
		dState.lastRenderedQ = q
	end
	SyncDetailsScroll()
end
ns.RefreshQuestDetails = RefreshDetails

---------------------------------------------------------------------------
-- Construction inside Dave's Map's Right Content Pane (`Panel.lua`)
---------------------------------------------------------------------------
function ns.InitQuestDetailsPane(content)
	if dState.pane or not content then return end
	local pane = CreateFrame("Frame", nil, content)
	dState.pane = pane
	ui.detailsPane = pane
	pane:Hide()
	pane:EnableMouse(true)
	pane:SetScript("OnMouseUp", function(_, button)
		if button == "Button4" and ns.GoBack then ns.GoBack() end
	end)

	local bg = pane:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.14)
	dState.bg = bg

	-- Top bar: `Track` / `Pin` / `Link` / `Share` on left, destructive `Abandon` separated on right (toolbar Back arrow lives beside Search)
	local topBar = CreateFrame("Frame", nil, pane)
	topBar:SetHeight(28)
	topBar:SetPoint("TOPLEFT", 0, 0)
	topBar:SetPoint("TOPRIGHT", 0, 0)

	dState.trackBtn = MakeActionPill(topBar, "|cffe8d8a8Track|r", 58, function(self)
		if ui.detailQuestID and ns.ToggleQuestTrack then
			ns.ToggleQuestTrack(ui.detailQuestID)
			RefreshDetails(false)
			if ns.RefreshTrackerPins then ns.RefreshTrackerPins() end
			if ns.UpdateFocus then ns.UpdateFocus(false) end
			if ns.Refresh then ns.Refresh() end
			if GameTooltip:IsShown() and GameTooltip:GetOwner() == self then
				local onEnter = self:GetScript("OnEnter")
				if onEnter then onEnter(self) end
			end
		end
	end, "Track or untrack this quest on the Objective Tracker.")
	dState.trackBtn:SetPoint("LEFT", 4, 0)

	dState.pinBtn = MakeActionPill(topBar, "|cffe8d8a8Pin|r", 46, function(self)
		if ui.detailQuestID and ns.PinQuest and ns.PinQuest(ui.detailQuestID) then
			RefreshDetails(false)
			if ns.RefreshTrackerPins then ns.RefreshTrackerPins() end
			if ns.UpdateFocus then ns.UpdateFocus(false) end
			if ns.Refresh then ns.Refresh() end
			if GameTooltip:IsShown() and GameTooltip:GetOwner() == self then
				local onEnter = self:GetScript("OnEnter")
				if onEnter then onEnter(self) end
			end
		end
	end, "Pin this quest so it stays tracked on the Objective Tracker even when you change zones.")
	dState.pinBtn:SetPoint("LEFT", dState.trackBtn, "RIGHT", 4, 0)

	dState.linkBtn = MakeActionPill(topBar, "|cffe8d8a8Link|r", 48, function()
		if ns.LinkQuestInChat and ui.detailQuestID then
			ns.LinkQuestInChat(ui.detailQuestID, true)
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		end
	end, "Insert a clickable quest link into chat.")
	dState.linkBtn:SetPoint("LEFT", dState.pinBtn, "RIGHT", 4, 0)

	dState.shareBtn = MakeActionPill(topBar, "|cffe8d8a8Share|r", 54, function()
		local q = ui.detailQuestID
		local idx = q and ns.QuestLogIndex(q)
		if idx and QuestLogPushQuest then
			QuestLogPushQuest(idx)
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		end
	end, "Share this quest with your party or raid.")
	dState.shareBtn:SetPoint("LEFT", dState.linkBtn, "RIGHT", 4, 0)

	dState.abandonBtn = MakeActionPill(topBar, "|cffff8888Abandon|r", 70, function()
		PromptAbandonQuest(ui.detailQuestID)
	end, "Abandon this quest (asks for confirmation first).")
	dState.abandonBtn:SetPoint("RIGHT", -4, 0)

	local div = pane:CreateTexture(nil, "ARTWORK")
	div:SetHeight(1)
	div:SetPoint("TOPLEFT", 2, -29)
	div:SetPoint("TOPRIGHT", -2, -29)
	div:SetColorTexture(1, 1, 1, 0.14)

	-- Scrollable Quest Text body
	local scroll = CreateFrame("ScrollFrame", nil, pane)
	dState.scroll = scroll
	scroll:SetClipsChildren(true)
	scroll:SetPoint("TOPLEFT", 4, -34)
	scroll:SetPoint("BOTTOMRIGHT", -(SCROLL_GUTTER + 2), 4)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta)
		dState.scrollPx = (dState.scrollPx or 0) - delta * 44
		SyncDetailsScroll()
	end)
	scroll:SetScript("OnSizeChanged", function(_, w)
		local safeW = (type(w) == "number" and not issecretvalue(w)) and w or nil
		if dState.pane:IsShown() and safeW and math.abs(safeW - (dState.lastBodyW + 8)) > 2 then
			RefreshDetails(false)
		else
			SyncDetailsScroll()
		end
	end)

	local body = CreateFrame("Frame", nil, scroll)
	dState.body = body
	body:SetSize(440, 200)
	scroll:SetScrollChild(body)

	dState.titleFS = body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	dState.titleFS:SetJustifyH("LEFT")
	dState.titleFS:SetWordWrap(true)

	dState.metaFS = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dState.metaFS:SetJustifyH("LEFT")
	dState.metaFS:SetWordWrap(true)

	dState.groupBadge = ns.CreateGroupCountPill(body, 19, 9, "GameFontHighlightSmall", "ANCHOR_RIGHT", false)

	local turnBtn = CreateFrame("Button", nil, body)
	turnBtn:SetHeight(20)
	turnBtn:RegisterForClicks("LeftButtonUp", "Button4Up")
	local thl = turnBtn:CreateTexture(nil, "HIGHLIGHT")
	thl:SetAllPoints()
	thl:SetColorTexture(0.45, 0.82, 1.0, 0.14)
	turnBtn.lbl = turnBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	turnBtn.lbl:SetAllPoints()
	turnBtn.lbl:SetJustifyH("LEFT")
	turnBtn.lbl:SetWordWrap(false)
	turnBtn:SetScript("OnClick", function(self, button)
		if button == "Button4" then
			if ns.GoBack then ns.GoBack() end
			return
		end
		if not self.targetPin then return end
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		if IsShiftKeyDown() or IsControlKeyDown() then
			ns.SetWaypoint(self.targetPin)
			return
		end
		if ns.CloseDungeonView then ns.CloseDungeonView() end
		ns.ShowPinMap(self.targetPin, true)
	end)
	turnBtn:Hide()
	dState.turnInBtn = turnBtn

	local sb = TryTemplate("EventFrame", nil, pane, "MinimalScrollBar")
	if sb and sb.RegisterCallback and sb.SetVisibleExtentPercentage then
		dState.scrollBar = sb
		dState.nativeScroll = true
		sb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -2)
		sb:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 2)
		if sb.SetHideIfUnscrollable then sb:SetHideIfUnscrollable(true) end
		sb:RegisterCallback("OnScroll", function(_, pct)
			if dState.syncingScroll then return end
			local viewH = scroll:GetHeight() or 0
			local maxScroll = math.max(0, (dState.contentH or 0) - viewH)
			dState.scrollPx = math.max(0, math.min(maxScroll, (pct or 0) * maxScroll))
			scroll:SetVerticalScroll(dState.scrollPx)
		end, scroll)
	end

	pane:SetScript("OnShow", function()
		RefreshDetails(false)
	end)
	pane:SetScript("OnHide", function()
		if dState.confirm and dState.confirm:IsShown() then
			dState.confirm:Hide()
		end
	end)
end

function ns.LayoutQuestDetailsPane(skipRefresh)
	if not (dState.pane and ui.listTopY) then return end
	dState.pane:ClearAllPoints()
	dState.pane:SetPoint("TOPLEFT", LIST_PAD, ui.listTopY)
	dState.pane:SetPoint("BOTTOMRIGHT", -LIST_PAD, LIST_PAD)
	if not skipRefresh and dState.pane:IsShown() then
		RefreshDetails(false)
	end
end

function ns.ApplyDetailsStyle(alpha, style)
	if dState.confirm and dState.confirm.border and ns.ApplyDialogBackground then
		ns.ApplyDialogBackground(dState.confirm.border, alpha, style)
	end
	if dState.bg then
		local bgA = (style and style.key == "marble") and 0.48 or ((style and style.key == "dialog") and 0.22 or 0.10)
		dState.bg:SetColorTexture(0, 0, 0, bgA)
	end
end

local detailEvents = CreateFrame("Frame")
detailEvents:RegisterEvent("QUEST_LOG_UPDATE")
detailEvents:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
detailEvents:RegisterEvent("QUEST_REMOVED")
detailEvents:RegisterEvent("QUEST_TURNED_IN")
detailEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
detailEvents:RegisterEvent("ITEM_DATA_LOAD_RESULT")
detailEvents:SetScript("OnEvent", function(_, event, arg1)
	if not (dState.pane and dState.pane:IsShown() and ui.detailQuestID) then return end
	if event == "ITEM_DATA_LOAD_RESULT" then
		if not (arg1 and dState.pendingItems[arg1]) then return end
		dState.pendingItems[arg1] = nil
		RefreshDetails(false)
		return
	end
	if (event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN") and arg1 == ui.detailQuestID then
		if ns.CloseQuestDetails then ns.CloseQuestDetails(true) end
		return
	end
	RefreshDetails(false)
end)
