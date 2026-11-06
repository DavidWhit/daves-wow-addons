-- daves_chat / Window.lua
-- Outer dialog frame, left scrollable tab column, inner chat-text frame, background painting,
-- snap-dragging, corner resizing, draggable message-bubble open icon when collapsed,
-- whisper pulse alerts, single-pass layout orchestration, and runtime watchers.

local _, ns = ...

-- Same backgrounds as Dave's Sack (Blizzard's own dialog papers and classic panel textures).
ns.BACKGROUND_STYLES = {
	{ key = "dark",       name = "Dark" },
	{ key = "dialog",     name = "Light paper", file = "Interface\\DialogFrame\\UI-DialogBox-Background", tile = true, light = true },
	{ key = "darkdialog", name = "Dark paper",  file = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", tile = true },
	{ key = "marble",     name = "Marble",      file = "Interface\\FrameGeneral\\UI-Background-Marble", tile = true, light = true },
	{ key = "rock",       name = "Rock",        file = "Interface\\FrameGeneral\\UI-Background-Rock", tile = true, light = true },
}

function ns.BackgroundStyle(key)
	for _, s in ipairs(ns.BACKGROUND_STYLES) do
		if s.key == key then return s end
	end
	return ns.BACKGROUND_STYLES[1]
end

local function PaintTexture(bg, a, style)
	if not bg then return end
	if style.atlas and ns.HasAtlas(style.atlas) then
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
end

local function PaintBackdrop(border, a, style)
	if not border or not border.SetBackdrop then return end
	local file = style.file
	border:SetBackdrop({
		bgFile = file or "Interface\\Buttons\\WHITE8X8", tile = style.tile or false, tileSize = 256,
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	if file then border:SetBackdropColor(1, 1, 1, a) else border:SetBackdropColor(0, 0, 0, a) end
end

local function DialogFillTexture(dialog)
	if not dialog then return end
	if dialog.davesFill then return dialog.davesFill end
	local n = dialog.GetNumChildren and dialog:GetNumChildren() or 0
	for i = 1, n do
		local child = select(i, dialog:GetChildren())
		if child and child.Bg then
			child.Bg:Show()
			dialog.davesFill = child.Bg
			return child.Bg
		end
	end
	local tex = dialog:CreateTexture(nil, "BACKGROUND")
	tex:SetPoint("TOPLEFT", dialog, "TOPLEFT", 7, -7)
	tex:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -7, 7)
	dialog.davesFill = tex
	return tex
end

-- The fill is its own BACKGROUND frame parented to UIParent (chat frames are LOW strata,
-- so a fill on the MEDIUM dialog would cover the text). Window Settings shares the style.
function ns:ApplyBackground()
	local a = ns.Clamp(ns.db.background or 0.8, 0.2, 1)
	local style = ns.BackgroundStyle(ns.db.backgroundStyle)
	if ns.border and ns.border.Bg and ns.fillTex then ns.border.Bg:Hide() end
	if ns.fillTex then
		PaintTexture(ns.fillTex, a, style)
	elseif ns.border then
		PaintBackdrop(ns.border, a, style)
	end
	if ns.tabColumnFill then
		if style.light then
			ns.tabColumnFill:SetColorTexture(0, 0, 0, math.min(0.22, a * 0.22))
		else
			ns.tabColumnFill:SetColorTexture(0, 0, 0, math.min(0.26, a * 0.26))
		end
	end
	if ns.chatBoxFill then
		if style.light then
			ns.chatBoxFill:SetColorTexture(0, 0, 0, math.min(0.24, a * 0.24))
		else
			ns.chatBoxFill:SetColorTexture(0, 0, 0, math.min(0.42, a * 0.42))
		end
	end
	if ns.settingsDivider then
		if style.light then
			ns.settingsDivider:SetColorTexture(0, 0, 0, 0.5)
		else
			ns.settingsDivider:SetColorTexture(1, 1, 1, 0.28)
		end
	end
	if ns.tabDivider then
		if style.light then
			ns.tabDivider:SetColorTexture(0, 0, 0, 0.4)
		else
			ns.tabDivider:SetColorTexture(1, 1, 1, 0.2)
		end
	end
	local editBg = DialogFillTexture(ns.editDialog)
	if editBg then PaintTexture(editBg, a, style) end
	if ns.RefreshTabs and ns.anchor and ns.anchor:IsShown() then
		ns:RefreshTabs()
	end
end

-- Applies Faint mode's frosted-glass strength and color strictly to the inner chat-text pane
-- (ns.frost, anchored to ns.chatBox — never the outer window, header, tab list, or input strip).
function ns:ApplyFrost()
	if not ns.frost then return end
	local s = ns.Clamp((ns.db and tonumber(ns.db.frostStrength)) or ns.DEFAULTS.frostStrength, 0, 1)
	local c = ns:GetFrostColor()
	local cr, cg, cb = c[1], c[2], c[3]
	if ns.frostGlass then
		if ns.frostHasGlassTex then
			ns.frostGlass:SetVertexColor(cr, cg, cb)
		else
			ns.frostGlass:SetColorTexture(cr * 0.9, cg * 0.9, cb * 0.9, 0.82)
		end
		ns.frostGlass:SetAlpha(0.86 * s)
	end
	if ns.frostGrain then
		local gr, gg, gb = 0.65 * cr + 0.35, 0.65 * cg + 0.35, 0.65 * cb + 0.35
		if ns.frostHasGrainTex then
			ns.frostGrain:SetVertexColor(gr, gg, gb)
		else
			ns.frostGrain:SetColorTexture(gr, gg, gb, 0.21)
		end
		ns.frostGrain:SetAlpha(0.65 * s)
	end
	if ns.frostSheen then
		local sr, sg, sb = 0.50 * cr + 0.50, 0.50 * cg + 0.50, 0.50 * cb + 0.50
		local topA = 0.11 * s
		if ns.frostSheen.SetGradient and CreateColor then
			ns.frostSheen:SetColorTexture(1, 1, 1, 1)
			ns.frostSheen:SetGradient("VERTICAL",
				CreateColor(sr, sg, sb, 0),
				CreateColor(sr, sg, sb, topA))
		else
			ns.frostSheen:SetColorTexture(sr, sg, sb, 0.5 * topA)
		end
	end
	if ns.SyncFrostAlpha then ns:SyncFrostAlpha() end
end

---------------------------------------------------------------------------
-- Shared magnetic snap-drag helper (uses ns.EditMode.SnapRect)
---------------------------------------------------------------------------
local function ResetButtonVisual(btn)
	if btn and btn.SetButtonState then
		btn:SetButtonState("NORMAL", false)
	end
end

local function MakeSnapMover(target, opts)
	opts = opts or {}
	local moving = false
	local mover = {}

	function mover.Stop()
		if not moving then return end
		moving = false
		target.isSnapMoving = nil
		target.isMovingIcon = nil
		if opts.markDragged then
			target.dragStopTime = GetTime()
		end
		target:SetScript("OnUpdate", nil)
		ResetButtonVisual(target)
		if opts.onStop then opts.onStop(target) end
	end

	function mover.Start()
		if moving then return end
		if target.IsProtected and target:IsProtected() and InCombatLockdown() then return end
		local scale = target:GetEffectiveScale()
		local ox, oy = target:GetCenter()
		if not ox then return end
		local cx, cy = GetCursorPosition()
		local grabX, grabY = cx - ox * scale, cy - oy * scale
		moving = true
		target.isSnapMoving = true
		if opts.markDragged then target.isMovingIcon = true end
		ResetButtonVisual(target)
		target:SetScript("OnUpdate", function(self)
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
				mover.Stop()
				return
			end
			if self.GetButtonState and self.SetButtonState and self:GetButtonState() ~= "NORMAL" then
				self:SetButtonState("NORMAL", false)
			end
			local sc, ui = self:GetEffectiveScale(), UIParent:GetEffectiveScale()
			local mx, my = GetCursorPosition()
			local x, y = (mx - grabX) / ui, (my - grabY) / ui
			local w, h = self:GetWidth() * sc / ui, self:GetHeight() * sc / ui
			if not IsShiftKeyDown() and ns.EditMode and ns.EditMode.SnapRect then
				local left, bottom = ns.EditMode.SnapRect(self, x - w / 2, y - h / 2, w, h)
				x, y = left + w / 2, bottom + h / 2
			end
			if opts.clampScreen then
				local halfW, halfH = w / 2, h / 2
				local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
				x = ns.Clamp(x, halfW, sw - halfW)
				y = ns.Clamp(y, halfH, sh - halfH)
			end
			self:ClearAllPoints()
			self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * ui / sc, y * ui / sc)
		end)
	end

	return mover
end

local function WireDragHandle(handle, mover, resetOnRightClick)
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", mover.Start)
	handle:SetScript("OnDragStop", mover.Stop)
	handle:SetScript("OnHide", mover.Stop)
	if resetOnRightClick then
		handle:SetScript("OnMouseUp", function(_, button)
			if button == "RightButton" then ns:ResetPosition() end
		end)
	end
end

---------------------------------------------------------------------------
-- Window, inner chat frame, draggable message-bubble open icon, and corner grips
---------------------------------------------------------------------------
local HYPERLINK_TOOLTIP_TYPES = {
	item = true,
	enchant = true,
	spell = true,
	mount = true,
	quest = true,
	achievement = true,
	talent = true,
	pvptal = true,
	glyph = true,
	currency = true,
	instancelock = true,
	battlePetAbil = true,
	garrmission = true,
	garrfollower = true,
	garrfollowerability = true,
	garrtech = true,
	azessence = true,
	conduit = true,
	transmogappearance = true,
	transmogillusion = true,
	transmogset = true,
	keystone = true,
	mawpower = true,
	apower = true,
	unit = true,
	outfit = true,
	dungeonScore = true,
	housingdecor = true,
	housingblueprint = true,
}

local PLAYER_LINK_TYPES = {
	player = true,
	playerCommunity = true,
	playerGM = true,
	BNplayer = true,
	BNplayerCommunity = true,
}

local playerInfoCache = {}
local LOCALIZED_CLASS_TO_FILE = {}
if LOCALIZED_CLASS_NAMES_MALE then
	for file, loc in pairs(LOCALIZED_CLASS_NAMES_MALE) do LOCALIZED_CLASS_TO_FILE[loc] = file end
end
if LOCALIZED_CLASS_NAMES_FEMALE then
	for file, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do LOCALIZED_CLASS_TO_FILE[loc] = file end
end

local function IsCleanString(s)
	return type(s) == "string" and (not issecretvalue or not issecretvalue(s)) and s ~= ""
end

local function IsCleanPositiveNumber(n)
	return type(n) == "number" and (not issecretvalue or not issecretvalue(n)) and n > 0
end

local function ShortPlayerName(name)
	if not IsCleanString(name) then return nil end
	if Ambiguate then
		local ok, short = pcall(Ambiguate, name, "short")
		if ok and IsCleanString(short) then return short end
	end
	return name:match("^([^%-]+)") or name
end

local function CachePlayerInfo(name, level, raceName, className, classFile, guildName, guildRank, zone, note)
	local short = ShortPlayerName(name)
	if not short then return nil end
	local key = short:lower()
	local entry = playerInfoCache[key]
	if not entry then
		entry = {}
		playerInfoCache[key] = entry
	end
	if IsCleanString(name) and (not entry.fullName or name:find("-", 1, true)) then entry.fullName = name end
	if IsCleanPositiveNumber(level) then entry.level = level end
	if IsCleanString(raceName) then entry.raceName = raceName end
	if IsCleanString(className) then
		entry.className = className
		if not IsCleanString(classFile) and LOCALIZED_CLASS_TO_FILE[className] then
			classFile = LOCALIZED_CLASS_TO_FILE[className]
		end
	end
	if IsCleanString(classFile) then entry.classFile = classFile end
	if IsCleanString(guildName) then entry.guildName = guildName end
	if IsCleanString(guildRank) then entry.guildRank = guildRank end
	if IsCleanString(zone) then entry.zone = zone end
	if IsCleanString(note) then entry.note = note end
	return entry
end

local function CacheUnitPlayerInfo(unit, targetGuid, targetKey)
	if not (UnitExists and UnitIsPlayer) then return nil end
	local exists = UnitExists(unit)
	if not exists or (issecretvalue and issecretvalue(exists)) then return nil end
	local isPlayer = UnitIsPlayer(unit)
	if not isPlayer or (issecretvalue and issecretvalue(isPlayer)) then return nil end
	local uName, uRealm = UnitName(unit)
	if not IsCleanString(uName) then return nil end
	local short = ShortPlayerName(uName)
	local key = short and short:lower()
	if targetGuid or targetKey then
		local uGuid = UnitGUID and UnitGUID(unit)
		local guidMatch = targetGuid and IsCleanString(uGuid) and uGuid == targetGuid
		local nameMatch = targetKey and key == targetKey
		if not guidMatch and not nameMatch then return nil end
	end
	local full = IsCleanString(uRealm) and (uName .. "-" .. uRealm) or uName
	local level = UnitLevel and UnitLevel(unit)
	local raceName = UnitRace and UnitRace(unit)
	local className, classFile = nil, nil
	if UnitClass then className, classFile = UnitClass(unit) end
	local guildName, guildRank = nil, nil
	if GetGuildInfo then guildName, guildRank = GetGuildInfo(unit) end
	return CachePlayerInfo(full, level, raceName, className, classFile, guildName, guildRank)
end

local function CacheWhoResults()
	if not (C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetWhoInfo) then return end
	local ok, numWhos = pcall(C_FriendList.GetNumWhoResults)
	if not ok or not IsCleanPositiveNumber(numWhos) then return end
	for i = 1, math.min(numWhos, 50) do
		local okInfo, info = pcall(C_FriendList.GetWhoInfo, i)
		if okInfo and type(info) == "table" then
			CachePlayerInfo(info.fullName, info.level, info.raceStr, info.classStr, info.filename, info.fullGuildName, nil, info.area)
		end
	end
end

local UNIT_TOKENS = { "player", "target", "mouseover", "focus", "party1", "party2", "party3", "party4" }

local function LookupClubMember(clubID, guid, shortKey, isGuild)
	if not (C_Club and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return end
	local ok, members = pcall(C_Club.GetClubMembers, clubID)
	if not ok or type(members) ~= "table" then return end
	local playerGuild = isGuild and GetGuildInfo and GetGuildInfo("player") or nil
	if not IsCleanString(playerGuild) then playerGuild = nil end
	for i = 1, math.min(#members, 500) do
		local okM, m = pcall(C_Club.GetMemberInfo, clubID, members[i])
		if okM and type(m) == "table" and IsCleanString(m.name) then
			local mShort = ShortPlayerName(m.name)
			local mKey = mShort and mShort:lower()
			local mGuid = IsCleanString(m.guid) and m.guid or nil
			if (guid and mGuid == guid) or (shortKey and mKey == shortKey) then
				local className, classFile, raceName
				if IsCleanPositiveNumber(m.classID) and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
					local ci = C_CreatureInfo.GetClassInfo(m.classID)
					if type(ci) == "table" then
						className, classFile = ci.className, ci.classFile
					end
				end
				if IsCleanPositiveNumber(m.race) and C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
					local ri = C_CreatureInfo.GetRaceInfo(m.race)
					if type(ri) == "table" then raceName = ri.raceName end
				end
				CachePlayerInfo(m.name, m.level, raceName, className, classFile, playerGuild, m.guildRank, m.zone, m.memberNote)
				return
			end
		end
	end
end

local function ShowPlayerHyperlinkTooltip(chatFrame, linkType, linkOptions, link, text)
	if not (GameTooltip and GameTooltip.SetText and GameTooltip.AddLine) then return end
	if not IsCleanString(linkOptions) then return end

	local rawName, lineIDStr, clubIDStr, bnetIDStr
	if linkType == "playerCommunity" then
		rawName, clubIDStr = linkOptions:match("^([^:]+):?([^:]*)")
	elseif linkType == "BNplayer" then
		rawName, bnetIDStr, lineIDStr = linkOptions:match("^([^:]+):([^:]*):?([^:]*)")
	elseif linkType == "BNplayerCommunity" then
		rawName, bnetIDStr, clubIDStr = linkOptions:match("^([^:]+):([^:]*):?([^:]*)")
	else
		rawName, lineIDStr = linkOptions:match("^([^:]+):?([^:]*)")
	end
	if not IsCleanString(rawName) then return end

	local shortName = ShortPlayerName(rawName) or rawName
	local shortKey = shortName:lower()
	local inLockdown = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()

	local bnetTag, bnetCharName
	local guid
	local bnetID = tonumber(bnetIDStr)
	if IsCleanPositiveNumber(bnetID) and C_BattleNet and C_BattleNet.GetAccountInfoByID then
		local ok, acct = pcall(C_BattleNet.GetAccountInfoByID, bnetID)
		if ok and type(acct) == "table" then
			if IsCleanString(acct.battleTag) then bnetTag = acct.battleTag end
			local ga = acct.gameAccountInfo
			if type(ga) == "table" then
				if IsCleanString(ga.characterName) then
					bnetCharName = ga.characterName
					shortName = ShortPlayerName(ga.characterName) or shortName
					shortKey = shortName:lower()
				end
				if IsCleanString(ga.playerGuid) then guid = ga.playerGuid end
				CachePlayerInfo(ga.characterName or rawName, ga.characterLevel, ga.raceName, ga.className, nil, nil, nil, ga.areaName, acct.note)
			end
		end
	end

	local lineID = tonumber(lineIDStr)
	if not guid and IsCleanPositiveNumber(lineID) and not inLockdown and C_ChatInfo and C_ChatInfo.GetChatLineSenderGUID then
		local valid = not C_ChatInfo.IsValidChatLine or C_ChatInfo.IsValidChatLine(lineID)
		if valid then
			local ok, g = pcall(C_ChatInfo.GetChatLineSenderGUID, lineID)
			if ok and IsCleanString(g) then guid = g end
		end
	end

	if guid then
		if GetPlayerInfoByGUID then
			local ok, locClass, engClass, locRace, _, _, pName, pRealm = pcall(GetPlayerInfoByGUID, guid)
			if ok then
				local full = (IsCleanString(pName) and IsCleanString(pRealm)) and (pName .. "-" .. pRealm) or (IsCleanString(pName) and pName or rawName)
				CachePlayerInfo(full, nil, locRace, locClass, engClass)
			end
		end
		if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
			local ok, ga = pcall(C_BattleNet.GetGameAccountInfoByGUID, guid)
			if ok and type(ga) == "table" then
				CachePlayerInfo(ga.characterName or rawName, ga.characterLevel, ga.raceName, ga.className, nil, nil, nil, ga.areaName)
			end
		end
		if C_RecentAllies and C_RecentAllies.IsSystemEnabled and C_RecentAllies.IsSystemEnabled()
			and C_RecentAllies.IsRecentAllyDataReady and C_RecentAllies.IsRecentAllyDataReady()
			and C_RecentAllies.GetRecentAllyByGUID then
			local ok, ally = pcall(C_RecentAllies.GetRecentAllyByGUID, guid)
			if ok and type(ally) == "table" and type(ally.characterData) == "table" then
				local cd = ally.characterData
				local className, classFile, raceName
				if IsCleanPositiveNumber(cd.classID) and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
					local ci = C_CreatureInfo.GetClassInfo(cd.classID)
					if type(ci) == "table" then className, classFile = ci.className, ci.classFile end
				end
				if IsCleanPositiveNumber(cd.raceID) and C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
					local ri = C_CreatureInfo.GetRaceInfo(cd.raceID)
					if type(ri) == "table" then raceName = ri.raceName end
				end
				local loc = type(ally.stateData) == "table" and ally.stateData.currentLocation or nil
				CachePlayerInfo(cd.fullName or rawName, cd.level, raceName, className, classFile, nil, nil, loc)
			end
		end
	end

	for i = 1, #UNIT_TOKENS do
		if CacheUnitPlayerInfo(UNIT_TOKENS[i], guid, shortKey) then break end
	end
	local entry = playerInfoCache[shortKey]
	if not (entry and entry.level) then
		for i = 1, 40 do
			if CacheUnitPlayerInfo("raid" .. i, guid, shortKey) or CacheUnitPlayerInfo("nameplate" .. i, guid, shortKey) then break end
		end
	end

	if C_FriendList and C_FriendList.GetFriendInfo then
		local ok, fInfo = pcall(C_FriendList.GetFriendInfo, rawName)
		if not (ok and type(fInfo) == "table") and shortName ~= rawName then
			ok, fInfo = pcall(C_FriendList.GetFriendInfo, shortName)
		end
		if ok and type(fInfo) == "table" then
			CachePlayerInfo(fInfo.name or rawName, fInfo.level, nil, fInfo.className, nil, nil, nil, fInfo.area, fInfo.notes)
		end
	end

	entry = playerInfoCache[shortKey]
	if not (entry and entry.level) and not inLockdown then
		local clubID = tonumber(clubIDStr)
		if IsCleanPositiveNumber(clubID) then
			LookupClubMember(clubID, guid, shortKey, false)
		end
		entry = playerInfoCache[shortKey]
		if not (entry and entry.level) and C_Club and C_Club.GetGuildClubId then
			local ok, guildClubID = pcall(C_Club.GetGuildClubId)
			if ok and IsCleanPositiveNumber(guildClubID) and guildClubID ~= clubID then
				LookupClubMember(guildClubID, guid, shortKey, true)
			end
		end
	end

	entry = playerInfoCache[shortKey]
	if not (entry and entry.level) then
		CacheWhoResults()
		entry = playerInfoCache[shortKey]
	end

	local title = shortName
	if IsCleanString(text) then
		local bracketed = text:match("%[([^%]]+)%]")
		if IsCleanString(bracketed) then title = bracketed end
	end
	if bnetTag then title = bnetTag end

	local r, g, b = 1, 1, 1
	if linkType == "BNplayer" or linkType == "BNplayerCommunity" then
		r, g, b = 0.51, 0.77, 1.0
	elseif entry and IsCleanString(entry.classFile) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile] then
		local cc = RAID_CLASS_COLORS[entry.classFile]
		r, g, b = cc.r or 1, cc.g or 1, cc.b or 1
	end

	ns.AnchorTooltip(ns.anchor or chatFrame)
	GameTooltip:SetText(title, r, g, b)

	if bnetCharName then
		local cr, cg, cb = 0.85, 0.85, 0.85
		if entry and IsCleanString(entry.classFile) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classFile] then
			local cc = RAID_CLASS_COLORS[entry.classFile]
			cr, cg, cb = cc.r or cr, cc.g or cg, cc.b or cb
		end
		GameTooltip:AddLine(bnetCharName, cr, cg, cb)
	end

	local level = entry and entry.level
	local raceName = entry and entry.raceName
	local className = entry and entry.className
	if level and raceName and className then
		GameTooltip:AddLine(("Level %d %s %s"):format(level, raceName, className), 1, 1, 1)
	elseif level and className then
		GameTooltip:AddLine(("Level %d %s"):format(level, className), 1, 1, 1)
	elseif level and raceName then
		GameTooltip:AddLine(("Level %d %s"):format(level, raceName), 1, 1, 1)
	elseif level then
		GameTooltip:AddLine(("Level %d"):format(level), 1, 1, 1)
	elseif raceName and className then
		GameTooltip:AddLine(("%s %s"):format(raceName, className), 1, 1, 1)
	elseif className then
		GameTooltip:AddLine(className, 1, 1, 1)
	end

	if entry and entry.guildName then
		if entry.guildRank then
			GameTooltip:AddLine(("<%s> (%s)"):format(entry.guildName, entry.guildRank), 0.4, 0.85, 0.4)
		else
			GameTooltip:AddLine(("<%s>"):format(entry.guildName), 0.4, 0.85, 0.4)
		end
	elseif entry and entry.guildRank then
		GameTooltip:AddLine(entry.guildRank, 0.4, 0.85, 0.4)
	end

	if entry and entry.zone then
		GameTooltip:AddLine(entry.zone, 0.85, 0.85, 0.85)
	end
	if entry and entry.note then
		GameTooltip:AddLine(entry.note, 1, 0.82, 0, true)
	end

	if linkType == "playerGM" then
		GameTooltip:AddLine("Click to whisper", 0.65, 0.65, 0.65)
	elseif linkType == "BNplayer" or linkType == "BNplayerCommunity" then
		GameTooltip:AddLine("Click to whisper • Right-click for menu", 0.65, 0.65, 0.65)
	elseif not level then
		GameTooltip:AddLine("Click to whisper • Right-click for menu • Shift-click for /who (level)", 0.65, 0.65, 0.65)
	else
		GameTooltip:AddLine("Click to whisper • Right-click for menu • Shift-click for /who", 0.65, 0.65, 0.65)
	end

	GameTooltip:Show()
	ns.hyperlinkTooltipShown = true
	ns.activePlayerTooltip = { chatFrame = chatFrame, link = link, text = text }
end

local function HideHyperlinkTooltip()
	if not ns.hyperlinkTooltipShown then return end
	ns.hyperlinkTooltipShown = false
	ns.activePlayerTooltip = nil
	if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
	if BattlePetTooltip and BattlePetTooltip.Hide then BattlePetTooltip:Hide() end
end

local function ShowHyperlinkTooltip(chatFrame, link, text)
	if not (ns.db and ns.db.enabled) or (ns.db.collapsed and not ns.inEditMode) then return end
	if not chatFrame or (chatFrame ~= ChatFrame1 and not chatFrame.isDocked) then return end
	if not IsCleanString(link) then return end
	local linkType, linkOptions = link:match("^([^:]+):(.*)$")
	if not linkType then return end

	if PLAYER_LINK_TYPES[linkType] then
		ShowPlayerHyperlinkTooltip(chatFrame, linkType, linkOptions, link, text)
		return
	end

	ns.activePlayerTooltip = nil
	if linkType == "battlepet" then
		if IsCleanString(text) and type(BattlePetToolTip_ShowLink) == "function" then
			ns.AnchorTooltip(ns.anchor or chatFrame)
			local ok, shown = pcall(BattlePetToolTip_ShowLink, text)
			if ok and shown then ns.hyperlinkTooltipShown = true end
		end
		return
	end

	if not HYPERLINK_TOOLTIP_TYPES[linkType] or not (GameTooltip and GameTooltip.SetHyperlink) then return end
	ns.AnchorTooltip(ns.anchor or chatFrame)
	local ok, shown = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
	if ok and shown ~= false then
		GameTooltip:Show()
		ns.hyperlinkTooltipShown = true
	else
		GameTooltip:Hide()
	end
end

function ns:UPDATE_MOUSEOVER_UNIT()
	CacheUnitPlayerInfo("mouseover")
end

function ns:PLAYER_TARGET_CHANGED()
	CacheUnitPlayerInfo("target")
end

function ns:GROUP_ROSTER_UPDATE()
	for i = 1, #UNIT_TOKENS do
		CacheUnitPlayerInfo(UNIT_TOKENS[i])
	end
end

function ns:WHO_LIST_UPDATE()
	CacheWhoResults()
	local active = ns.activePlayerTooltip
	if ns.hyperlinkTooltipShown and active then
		ShowHyperlinkTooltip(active.chatFrame, active.link, active.text)
	end
end

local function BuildWindow(anchor)
	local border = ns.TryTemplate("Frame", nil, anchor, "DialogBorderTranslucentTemplate") -- editmode-ui: ok
	if border then
		border:SetAllPoints()
	else
		border = CreateFrame("Frame", nil, anchor, BackdropTemplateMixin and "BackdropTemplate" or nil)
		border:SetAllPoints()
		border:SetFrameLevel(anchor:GetFrameLevel())
		border:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		border:SetBackdropColor(0, 0, 0, 0.8)
	end
	border:EnableMouse(false)
	if border.EnableMouseWheel then border:EnableMouseWheel(false) end
	ns.border = border
	if border.Bg then border.Bg:Hide() end

	local topLevel = math.max(anchor:GetFrameLevel() or 0,
		(border and border.GetFrameLevel and border:GetFrameLevel()) or 0)

	-- Behind the chat text on UIParent at BACKGROUND strata; scaled in Dock.lua to match anchor
	-- so its 7px dialog-border inset, inner chat well, and tiled textures line up at every window scale.
	local fill = CreateFrame("Frame", nil, UIParent)
	fill:SetFrameStrata("BACKGROUND")
	fill:SetAllPoints(anchor)
	ns.fill = fill

	local fillTex = fill:CreateTexture(nil, "BACKGROUND", nil, 0)
	fillTex:SetPoint("TOPLEFT", fill, "TOPLEFT", 7, -7)
	fillTex:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", -7, 7)
	ns.fillTex = fillTex

	ns:BuildHeader(anchor)

	-- Left-side vertical chat tab list container (inside the main window frame).
	local tabColumn = CreateFrame("Frame", nil, anchor)
	tabColumn:SetWidth(ns.TAB_WIDTH or 104)
	tabColumn:SetFrameLevel(topLevel + 10)
	ns.tabColumn = tabColumn

	local tabColumnFill = fill:CreateTexture(nil, "BACKGROUND", nil, 1)
	tabColumnFill:SetAllPoints(tabColumn)
	ns.tabColumnFill = tabColumnFill

	local tabDivider = tabColumn:CreateTexture(nil, "BORDER")
	tabDivider:SetWidth(1)
	tabDivider:SetPoint("TOPRIGHT", tabColumn, "TOPRIGHT", 0, 0)
	tabDivider:SetPoint("BOTTOMRIGHT", tabColumn, "BOTTOMRIGHT", 0, 0)
	tabDivider:SetColorTexture(1, 1, 1, 0.2)
	ns.tabDivider = tabDivider

	-- Bordered inner frame around the chat message area next to the left tab stack.
	-- Its NineSlice border renders on MEDIUM strata while its Bg stays hidden so LOW-strata chat text
	-- is never covered; chatBoxFill draws the recessed inner pane behind the text on BACKGROUND strata.
	local chatBox = ns.TryTemplate("Frame", nil, anchor, "InsetFrameTemplate") -- editmode-ui: ok
	if not chatBox then
		chatBox = CreateFrame("Frame", nil, anchor, BackdropTemplateMixin and "BackdropTemplate" or nil)
		if chatBox.SetBackdrop then
			chatBox:SetBackdrop({
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
				insets = { left = 3, right = 3, top = 3, bottom = 3 },
			})
			chatBox:SetBackdropBorderColor(0.65, 0.65, 0.65, 0.85)
		end
	end
	chatBox:SetFrameLevel(anchor:GetFrameLevel() + 5)
	if chatBox.Bg then chatBox.Bg:Hide() end
	chatBox:EnableMouse(false)
	if chatBox.NineSlice and chatBox.NineSlice.EnableMouse then
		chatBox.NineSlice:EnableMouse(false)
	end
	ns.chatBox = chatBox

	local chatBoxFill = fill:CreateTexture(nil, "BACKGROUND", nil, 1)
	chatBoxFill:SetPoint("TOPLEFT", chatBox, "TOPLEFT", 3, -3)
	chatBoxFill:SetPoint("BOTTOMRIGHT", chatBox, "BOTTOMRIGHT", -3, 3)
	ns.chatBoxFill = chatBoxFill

	-- Frosted-glass backing behind the inner chat-text pane while Faint mode has faded the window
	-- chrome out: lifts dark scenes with a translucent milky-etched glass pane + subtle specular rim
	-- so dark and light messages stay readable while keeping an airy, borderless transparent look.
	local frost = CreateFrame("Frame", nil, UIParent)
	frost:SetFrameStrata("BACKGROUND")
	frost:SetFrameLevel((fill:GetFrameLevel() or 0) + 1)
	frost:SetAllPoints(chatBox)
	frost:EnableMouse(false)
	if frost.SetFlattensRenderLayers then frost:SetFlattensRenderLayers(true) end
	frost:SetAlpha(0)
	frost:Hide()
	ns.frost = frost

	local frostGlass = frost:CreateTexture(nil, "BACKGROUND", nil, 0)
	frostGlass:SetAllPoints()
	if frostGlass.SetTextureSliceMargins and frostGlass:SetTexture(ns.MEDIA .. "frost_glass") then
		frostGlass:SetTextureSliceMargins(16, 16, 16, 16)
		ns.frostHasGlassTex = true
	else
		frostGlass:SetColorTexture(0.74, 0.78, 0.85, 0.82)
		ns.frostHasGlassTex = false
	end
	ns.frostGlass = frostGlass

	local frostGrain = frost:CreateTexture(nil, "BACKGROUND", nil, 1)
	frostGrain:SetPoint("TOPLEFT", frost, "TOPLEFT", 2, -2)
	frostGrain:SetPoint("BOTTOMRIGHT", frost, "BOTTOMRIGHT", -2, 2)
	if frostGrain:SetTexture(ns.MEDIA .. "frost_grain", "REPEAT", "REPEAT") then
		frostGrain:SetHorizTile(true)
		frostGrain:SetVertTile(true)
		ns.frostHasGrainTex = true
	else
		frostGrain:SetColorTexture(0.88, 0.92, 0.96, 0.21)
		ns.frostHasGrainTex = false
	end
	ns.frostGrain = frostGrain

	local frostSheen = frost:CreateTexture(nil, "BACKGROUND", nil, 2)
	frostSheen:SetPoint("TOPLEFT", frost, "TOPLEFT", 2, -2)
	frostSheen:SetPoint("BOTTOMRIGHT", frost, "BOTTOMRIGHT", -2, 2)
	frostSheen:SetColorTexture(1, 1, 1, 1)
	ns.frostSheen = frostSheen

	-- Header, top lip, and empty tab-column drag outside Edit Mode (anchor itself stays mouse-off
	-- outside Edit Mode so clicks pass through to chat links and the 3D world).
	local windowMover = MakeSnapMover(anchor, {
		onStop = function(self)
			local point, _, relPoint, x, y = self:GetPoint(1)
			if point then ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y } end
			if ns.editDialog and ns.editDialog:IsShown() then ns.editDialog:Refresh() end
		end,
	})

	local drag = CreateFrame("Frame", nil, anchor)
	drag:SetPoint("TOPLEFT", anchor, "TOPLEFT", 6, -4)
	drag:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -32, -4)
	drag:SetHeight(14)
	drag:SetFrameLevel(topLevel + 20)
	WireDragHandle(drag, windowMover, true)
	drag:SetScript("OnEnter", function(self)
		ns.AnchorTooltip(self)
		GameTooltip:SetText("Drag to move")
		GameTooltip:AddLine("Right-click to reset the position.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	drag:SetScript("OnLeave", function() GameTooltip:Hide() end)
	ns.dragStrip = drag

	WireDragHandle(ns.settingsBar, windowMover, true)
	-- Left-drag on empty tab-list space still moves the window, but right-clicking inside the tab
	-- list must never reset the window position.
	WireDragHandle(tabColumn, windowMover, false)

	-- Draggable message-bubble icon shown while collapsed; independent of the window's rectangle.
	local toggle = ns.MakeChatIcon(UIParent, "DavesChatToggle")
	toggle:SetFrameStrata("MEDIUM")
	toggle:SetFrameLevel(40)
	toggle:SetClampedToScreen(true)
	local iconMover = MakeSnapMover(toggle, {
		clampScreen = true,
		markDragged = true,
		onStop = function(self)
			local point, _, relPoint, x, y = self:GetPoint(1)
			if point then ns.db.iconPos = { point = point, relPoint = relPoint, x = x, y = y } end
		end,
	})
	toggle:RegisterForDrag("LeftButton")
	toggle:SetScript("OnDragStart", iconMover.Start)
	toggle:SetScript("OnDragStop", iconMover.Stop)
	toggle:SetScript("OnHide", iconMover.Stop)
	toggle:SetScript("OnClick", function(self)
		ResetButtonVisual(self)
		if self.isMovingIcon or (self.dragStopTime and (GetTime() - self.dragStopTime) < 0.05) then
			return
		end
		ns.Sound("IG_CHAT_EMOTE_BUTTON")
		local opening = ns.db.collapsed
		ns:SetCollapsed(not ns.db.collapsed)
		if opening and ns.SelectDefaultTab then ns:SelectDefaultTab(false) end
	end)
	toggle:SetScript("OnEnter", function(self)
		ns.AnchorTooltip(self, "RIGHT")
		GameTooltip:SetText("Open chat")
		GameTooltip:AddLine("Drag to move this icon.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
	toggle:Hide()
	ns.toggle = toggle

	-- Bottom-left and bottom-right resize grips with EditMode.SnapEdge snapping.
	ns.grips = {}
	local rs = {}
	local resizer = CreateFrame("Frame")
	resizer:Hide()
	local function StopResize()
		if not resizer:IsShown() then return end
		resizer:Hide()
		rs.x = nil
		ns.resizing = nil
		local point, _, relPoint, x, y = anchor:GetPoint(1)
		if point then ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y } end
		if ns.editDialog and ns.editDialog:IsShown() then ns.editDialog:Refresh() end
	end
	resizer:SetScript("OnUpdate", function()
		if not rs.x then return end
		if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then StopResize() return end
		local minW = ns.MIN_WIDTH
		local minH = ns:MinFrameHeight()
		local sc = anchor:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		local dx, dy = cx / sc - rs.x, cy / sc - rs.y
		local w = math.max(minW, math.min(rs.right and (rs.w + dx) or (rs.w - dx), rs.maxW))
		local h = math.max(minH, math.min(rs.h - dy, rs.maxH))
		if ns.EditMode and ns.EditMode.SnapEdge then
			local ui = sc / UIParent:GetEffectiveScale()
			local function Frame(v) return v / ui end
			if rs.right then
				w = math.max(minW, Frame(ns.EditMode.SnapEdge((rs.left + w) * ui, true)) - rs.left)
			else
				w = math.max(minW, rs.rightX - Frame(ns.EditMode.SnapEdge((rs.rightX - w) * ui, true)))
			end
			h = math.max(minH, rs.top - Frame(ns.EditMode.SnapEdge((rs.top - h) * ui, false)))
		end
		ns.db.width, ns.db.height = math.floor(w + 0.5), math.floor(h + 0.5)
		anchor:SetSize(ns.db.width, ns.db.height)
		ns:LayoutWindow()
		if ns.editDialog and ns.editDialog:IsShown() and ns.editDialog.RefreshValues then
			ns.editDialog:RefreshValues()
		end
	end)
	local function StartResize(right)
		local left, rightX, top = anchor:GetLeft(), anchor:GetRight(), anchor:GetTop()
		if not (left and top and rightX) then return end
		local sc = anchor:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		rs.right, rs.x, rs.y = right, cx / sc, cy / sc
		rs.w, rs.h, rs.left, rs.rightX, rs.top = anchor:GetWidth(), anchor:GetHeight(), left, rightX, top
		local screenW = UIParent:GetWidth() * UIParent:GetEffectiveScale() / sc
		rs.maxW = right and (screenW - left) or rightX
		rs.maxH = top - 8
		anchor:ClearAllPoints()
		if right then
			anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		else
			anchor:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", rightX, top)
		end
		ns.resizing = true
		resizer:Show()
	end
	for _, right in ipairs({ true, false }) do
		local g = CreateFrame("Button", nil, anchor)
		g:SetSize(16, 16)
		g:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", right and -4 or 4, 4)
		g:SetFrameLevel(topLevel + 40)
		local t = g:CreateTexture(nil, "OVERLAY")
		t:SetTexture(ns.MEDIA .. "grip"); t:SetAllPoints(); t:SetAlpha(0.55)
		local hl = g:CreateTexture(nil, "HIGHLIGHT")
		hl:SetTexture(ns.MEDIA .. "grip"); hl:SetAllPoints(); hl:SetBlendMode("ADD")
		if not right then t:SetTexCoord(1, 0, 0, 1); hl:SetTexCoord(1, 0, 0, 1) end
		g:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then StartResize(right) end end)
		g:SetScript("OnMouseUp", StopResize)
		g:SetScript("OnHide", StopResize)
		g:SetScript("OnEnter", function(self)
			ns.AnchorTooltip(self)
			GameTooltip:SetText("Drag to resize")
			GameTooltip:Show()
		end)
		g:SetScript("OnLeave", function() GameTooltip:Hide() end)
		ns.grips[#ns.grips + 1] = g
	end

	ns:ApplyBackground()
	ns:ApplyFrost()
end

function ns:PlaceToggle()
	local btn, anchor = ns.toggle, ns.anchor
	if not btn then return end
	if not ns.db.iconPos and anchor and anchor:GetLeft() and anchor:GetBottom() then
		local sc = (anchor:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
		ns.db.iconPos = {
			point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT",
			x = anchor:GetLeft() * sc, y = anchor:GetBottom() * sc,
		}
	end
	local pos = ns.db.iconPos or { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 16, y = 16 }
	btn:ClearAllPoints()
	btn:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

---------------------------------------------------------------------------
-- Whisper button / tab pulse alert (reads no secret message/sender payload)
---------------------------------------------------------------------------
function ns.SetButtonPulse(button, active, duration)
	if not button then return end
	if not active then
		button.alerting = false
		button.alertUntil = nil
		if button.glow then button.glow:SetAlpha(0) end
		if button.pulse then button.pulse:Hide() end
		return
	end
	if not button.glow then
		local glow = button:CreateTexture(nil, "OVERLAY")
		glow:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
		glow:SetAllPoints()
		glow:SetBlendMode("ADD")
		glow:SetAlpha(0)
		button.glow = glow
		local pulse = CreateFrame("Frame", nil, button)
		pulse:Hide()
		pulse:SetScript("OnUpdate", function()
			local timed = button.alertUntil and GetTime() <= button.alertUntil
			if not button.alerting and not timed then
				button.alertUntil = nil
				glow:SetAlpha(0)
				pulse:Hide()
				return
			end
			glow:SetAlpha(0.25 + 0.65 * math.abs(math.sin(GetTime() * 4)))
		end)
		button.pulse = pulse
	end
	if duration then
		button.alertUntil = GetTime() + duration
	else
		button.alerting = true
	end
	button.pulse:Show()
end

local function PulseButton(button)
	ns.SetButtonPulse(button, true, 8)
end

function ns:AlertWhisper()
	if not ns.db.whisperAlert then return end
	PulseButton(ns.toggle)
	local selected = ns.VisibleChatFrame and ns.VisibleChatFrame()
	if selected ~= ChatFrame1 then
		if ns.db.showTabs == false then
			ns.hiddenTabAlertUntil = GetTime() + 8
		end
		if ns.tabs then
			for i = 1, #ns.tabs do
				local tab = ns.tabs[i]
				if tab and tab.chatFrame == ChatFrame1 then
					tab.alertUntil = GetTime() + 8
					break
				end
			end
		end
		if ns.RefreshTabs and (not ns.db.collapsed or ns.inEditMode) then
			ns:RefreshTabs()
		end
	end
end

function ns:CHAT_MSG_WHISPER()
	ns:AlertWhisper()
end

function ns:CHAT_MSG_BN_WHISPER()
	ns:AlertWhisper()
end

---------------------------------------------------------------------------
-- Clicking any window control (header icons, Social/Channels, tab list, drag strip, resize grips,
-- close X, or the Window Settings dialog) clears the Say box so it never floats above them.
-- Clicks on the chat text itself are left alone so shift-clicking links into the box still works.
---------------------------------------------------------------------------
local function MouseOverShown(frame)
	if not (frame and frame.IsShown and frame:IsShown() and frame.IsMouseOver) then return false end
	local over = frame:IsMouseOver()
	if issecretvalue and issecretvalue(over) then return false end
	return over and true or false
end

local function MouseOverWindowControls()
	if MouseOverShown(ns.settingsBar) or MouseOverShown(ns.closeButton)
		or MouseOverShown(ns.dragStrip) or MouseOverShown(ns.tabColumn)
		or MouseOverShown(ns.editDialog) then
		return true
	end
	if ns.grips then
		for i = 1, #ns.grips do
			if MouseOverShown(ns.grips[i]) then return true end
		end
	end
	return false
end

function ns:GLOBAL_MOUSE_DOWN()
	if not ns.db.enabled or (ns.db.collapsed and not ns.inEditMode) then return end
	if not (ns.OwnedEditBoxActive and ns:OwnedEditBoxActive()) then return end
	if MouseOverWindowControls() then
		ns:CloseOwnedEditBoxes(true)
	end
end

---------------------------------------------------------------------------
-- Faint mode: while the window isn't hovered, fade every piece of window chrome (border, outer
-- background, header, tab list, inner frame border, scrollbar, resting edit box, grips) while
-- cross-fading in the frosted-glass backing behind the chat text so dark and light messages stay readable.
-- Runs on its own UIParent child frame (EditMode.Attach owns the anchor's OnUpdate while dragging).
---------------------------------------------------------------------------
local FAINT_FADE_IN = 0.15   -- seconds to fade chrome back in on hover
local FAINT_FADE_OUT = 0.4   -- seconds to fade chrome out after the hover delay
local FAINT_DELAY = 0.6      -- seconds the chrome stays after the mouse leaves

ns.chromeAlpha = 1

local function IsFrostPreviewing(now)
	if ns.resizing then
		ns.frostPreviewUntil = nil
		return false
	end
	if ns.frostColorPicking then
		if ColorPickerFrame and ColorPickerFrame.IsShown and ColorPickerFrame:IsShown() then
			return true
		end
		ns.frostColorPicking = false
	end
	now = now or GetTime()
	if ns.frostPreviewUntil then
		if now < ns.frostPreviewUntil then return true end
		ns.frostPreviewUntil = nil
	end
	return false
end

function ns:SyncFrostAlpha()
	if not ns.frost then return end
	local open = ns.db and ns.db.enabled and (not ns.db.collapsed or ns.inEditMode)
	local strength = ns.Clamp((ns.db and tonumber(ns.db.frostStrength)) or ns.DEFAULTS.frostStrength, 0, 1)
	local previewing = open and IsFrostPreviewing()
	local active = open and strength > 0.001 and (ns.db.faint or previewing or (ns.chromeAlpha or 1) < 0.999)
	local textA = 1
	if active and not previewing then
		if ns.frostTextAlpha == nil then
			ns.frostTextAlpha = ns.ActiveChatTextAlpha and ns.ActiveChatTextAlpha() or 1
		end
		textA = ns.frostTextAlpha
	end
	local frostA = active and (ns.Clamp(1 - (ns.chromeAlpha or 1), 0, 1) * textA) or 0
	if frostA > 0.001 then
		ns.frost:SetAlpha(frostA)
		if not ns.frost:IsShown() then ns.frost:Show() end
	else
		ns.frost:SetAlpha(0)
		if ns.frost:IsShown() then ns.frost:Hide() end
	end
end

function ns:PreviewFrost(duration)
	ns.frostPreviewUntil = GetTime() + (duration or 1.4)
	ns:SyncFrostAlpha()
end

function ns:BeginFrostColorPick()
	ns.frostColorPicking = true
	ns:PreviewFrost(0.5)
end

local function SetChromeAlpha(a)
	ns.chromeAlpha = a
	if ns.anchor then ns.anchor:SetAlpha(a) end
	if ns.fill then ns.fill:SetAlpha(a) end
	ns:SyncFrostAlpha()
	if ns.ApplyOwnedChromeAlpha then ns:ApplyOwnedChromeAlpha() end
end

local function KeepTabsOpen()
	if ns.inEditMode or ns.resizing then return true end
	if ns.anchor and ns.anchor.isSnapMoving then return true end
	if ns.tabColumn and ns.tabColumn.isThumbDragging then return true end
	if MouseOverShown(ns.anchor) then return true end
	if ns.IsTabMenuOpen and ns.IsTabMenuOpen() then return true end
	if StaticPopup_Visible and StaticPopup_Visible("NAME_CHAT") then return true end
	if ns.editDialog and ns.editDialog.IsShown and ns.editDialog:IsShown() then return true end
	return false
end

local function KeepChromeVisible()
	if KeepTabsOpen() then return true end
	if ns.OwnedEditBoxActive and ns:OwnedEditBoxActive() then return true end
	return false
end

local function StartFaintFader()
	local lastHover = 0
	local fader = CreateFrame("Frame", nil, UIParent)
	fader:SetScript("OnUpdate", function(_, elapsed)
		local open = ns.db.enabled and (not ns.db.collapsed or ns.inEditMode)
		local now = GetTime()

		-- Auto-close open tabs once the cursor leaves the chat window (and no tab menu / drag /
		-- Window Settings / Edit Mode session is active), expanding chat to the full window width.
		if open and ns.db.showTabs ~= false then
			if KeepTabsOpen() then
				ns.tabsAutoCloseArmed = true
				ns.lastTabsHover = now
			elseif ns.tabsAutoCloseArmed and now - (ns.lastTabsHover or 0) > FAINT_DELAY then
				if not (ChatFrame1 and ChatFrame1.IsProtected and ChatFrame1:IsProtected() and InCombatLockdown()) then
					ns.tabsAutoCloseArmed = false
					if ns.SetShowTabs then ns:SetShowTabs(false) end
				end
			end
		else
			ns.tabsAutoCloseArmed = false
		end

		local previewing = open and IsFrostPreviewing(now)
		local target = 1
		if previewing then
			target = 0
		elseif open and ns.db.faint then
			if KeepChromeVisible() then lastHover = now end
			if now - lastHover > FAINT_DELAY then target = 0 end
		end

		local a = ns.chromeAlpha or 1
		local textChanged = false
		if previewing or (open and (ns.db.faint or a < 0.999)) then
			local wantText = 1
			if not previewing and ns.db.faint and ns.ActiveChatTextAlpha then
				wantText = ns.ActiveChatTextAlpha()
			end
			local prevTa = ns.frostTextAlpha
			local ta = (prevTa == nil) and wantText or prevTa
			if wantText > ta then
				ta = math.min(wantText, ta + elapsed / FAINT_FADE_IN)
			elseif wantText < ta then
				ta = math.max(wantText, ta - elapsed / FAINT_FADE_OUT)
			end
			textChanged = (ta ~= prevTa)
			ns.frostTextAlpha = ta
		else
			ns.frostTextAlpha = nil
		end

		local chromeChanged = (a ~= target)
		if chromeChanged then
			if target > a then
				a = math.min(target, a + elapsed / FAINT_FADE_IN)
			else
				local rate = previewing and FAINT_FADE_IN or FAINT_FADE_OUT
				a = math.max(target, a - elapsed / rate)
			end
			SetChromeAlpha(a)
		elseif textChanged then
			ns:SyncFrostAlpha()
		end
	end)
	ns.faintFader = fader
end

function ns:ApplyFaint()
	-- Turning faint off snaps the chrome fully visible right away.
	if not ns.db.faint then
		ns.frostPreviewUntil = nil
		ns.frostTextAlpha = nil
		SetChromeAlpha(1)
	else
		ns:SyncFrostAlpha()
	end
end

---------------------------------------------------------------------------
-- Single-pass window layout & enable/collapse state machine
---------------------------------------------------------------------------
function ns:LayoutWindow()
	if not ns.db.enabled or not ns.anchor then return end
	local open = not ns.db.collapsed or ns.inEditMode
	ns:ApplyOwnedScale()
	if open then
		ns:PlaceSettings()
		ns:PlaceHeaderButtons()
		ns:SeatChat()
		ns:RefreshTabs()
	else
		ns:SeatChat()
		ns:SyncChatChrome("closed")
	end
end

function ns:ApplyEnabled()
	local on = ns.db.enabled and true or false
	local open = on and (not ns.db.collapsed or ns.inEditMode)
	local showTabs = open and (ns.db.showTabs ~= false)

	if ns.border then ns.border:SetShown(open) end
	if ns.fill then ns.fill:SetShown(open) end
	ns:SyncFrostAlpha()
	if ns.settingsBar then ns.settingsBar:SetShown(open) end
	if ns.tabsToggleButton then
		ns.tabsToggleButton:SetShown(open)
		if open then
			ResetButtonVisual(ns.tabsToggleButton)
			if ns.SyncTabsToggleButton then ns:SyncTabsToggleButton() end
		else
			ns.SetButtonPulse(ns.tabsToggleButton, false)
		end
	end
	if ns.chatSettingsButton then
		ns.chatSettingsButton:SetShown(open)
		if open then ResetButtonVisual(ns.chatSettingsButton) end
	end
	if ns.windowSettingsButton then
		ns.windowSettingsButton:SetShown(open)
		if open then ResetButtonVisual(ns.windowSettingsButton) end
	end
	if ns.closeButton then
		ns.closeButton:SetShown(open)
		if open then ResetButtonVisual(ns.closeButton) end
	end
	if ns.tabColumn then ns.tabColumn:SetShown(showTabs) end
	if ns.tabColumnFill then ns.tabColumnFill:SetShown(showTabs) end
	if ns.chatBox then ns.chatBox:SetShown(open) end
	if ns.chatBoxFill then ns.chatBoxFill:SetShown(open) end
	if ns.dragStrip then ns.dragStrip:SetShown(open) end
	if not open then HideHyperlinkTooltip() end
	if ns.grips then
		for i = 1, #ns.grips do ns.grips[i]:SetShown(open) end
	end
	if ns.toggle then
		local showToggle = on and ns.db.collapsed and true or false
		ns.toggle:SetShown(showToggle)
		if showToggle then ResetButtonVisual(ns.toggle) end
	end
	if not showTabs and ns.tabs then
		for i = 1, #ns.tabs do ns.tabs[i]:Hide() end
	end

	if open then
		if ns.anchor and not ns.anchor:IsShown() then ns.anchor:Show() end
		ns:ApplyBackground()
		ns:LayoutWindow()
	elseif on then
		-- Seat while anchor has a valid rect, place the message-bubble open icon, then hide the anchor
		-- so the closed window's rectangle takes no mouse or wheel input.
		if ns.anchor and not ns.anchor:IsShown() then ns.anchor:Show() end
		ns:LayoutWindow()
		ns:PlaceToggle()
		if ns.anchor and not ns.inEditMode then ns.anchor:Hide() end
	else
		if ns.anchor then ns.anchor:Hide() end
		ns:ResetOwnedScale()
		ns:SyncChatChrome("restore")
		ns:PlaceHeaderButtons()
	end
end

function ns:SetCollapsed(collapsed)
	if collapsed and ns.CloseOwnedEditBoxes then
		ns:CloseOwnedEditBoxes()
	end
	ns.db.collapsed = collapsed and true or false
	if not collapsed then
		ns.SetButtonPulse(ns.toggle, false)
	end
	ns:ApplyEnabled()
end

---------------------------------------------------------------------------
-- Initialization, hooks, and UIParent watcher
---------------------------------------------------------------------------
function ns:Init()
	local anchor = CreateFrame("Frame", "DavesChatAnchor", UIParent)
	anchor:SetSize(ns.db.width, ns.db.height)
	anchor:SetClampedToScreen(true)
	ns.anchor = anchor

	BuildWindow(anchor)
	ns:InitEditMode(anchor)
	ns:HookChatAlerts()
	ns:HookChatFlickerGuards()
	ns:HookChatPositionGuards()
	ns:ApplyEnabled()
	StartFaintFader()

	-- Re-hide Blizzard's real tabs, recompute auto-fitted tab width, and refresh our list whenever the dock updates tabs.
	local updatingDockTabs = false
	if hooksecurefunc and type(FCFDock_UpdateTabs) == "function" then
		hooksecurefunc("FCFDock_UpdateTabs", function()
			if updatingDockTabs or not ns.db.enabled then return end
			updatingDockTabs = true
			ns:ApplyOwnedScale()
			if not ns.db.collapsed or ns.inEditMode then
				ns:SeatChat()
				ns:RefreshTabs()
			else
				ns:SeatChat()
			end
			updatingDockTabs = false
		end)
	end

	-- Exit Edit Mode and specialization changes call UpdateLayoutInfo without firing
	-- EDIT_MODE_LAYOUTS_UPDATED, resetting ChatFrame1's anchor. Reseat synchronously before draw.
	if EditModeManagerFrame and hooksecurefunc then
		local function ReseatAfterEditMode()
			if not ns.db or not ns.db.enabled then return end
			ns:LayoutWindow()
			if not anchor:GetCenter() then
				ns.Defer(function() ns:LayoutWindow() end)
			end
		end
		hooksecurefunc(EditModeManagerFrame, "UpdateLayoutInfo", ReseatAfterEditMode)
		if type(EditModeManagerFrame.ExitEditMode) == "function" then
			hooksecurefunc(EditModeManagerFrame, "ExitEditMode", ReseatAfterEditMode)
		end
		if type(EditModeManagerFrame.RevertAllChanges) == "function" then
			hooksecurefunc(EditModeManagerFrame, "RevertAllChanges", ReseatAfterEditMode)
		end
	end

	-- Follow the anchor while dragged (the anchor's own OnUpdate belongs to Edit Mode),
	-- and catch any unhooked ChatFrame1 drift before the frame renders.
	-- Parented to UIParent so it keeps watching while the window is collapsed.
	local seatX, seatY, seatW, seatH
	local watcher = CreateFrame("Frame", nil, UIParent)
	watcher:SetScript("OnUpdate", function()
		if not ns.db.enabled then return end
		if ns.db.collapsed and not ns.inEditMode then
			if ns.DockEditFocused() then
				ns:SetCollapsed(false)
				return
			end
			if not ns:IsChatSeated() then
				ns:SeatChat()
			else
				ns:EnforceOwnedChrome()
			end
			return
		end

		ns:EnforceOwnedChrome()
		if (ns.FriendsWanted() and not ns.friendsX) or (ns.TtsWanted() ~= ns.seenTtsWanted) then
			ns:LayoutWindow()
		elseif ns:FriendsDrifted() then
			ns:PinHeaderIcons()
		end

		local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
		if selected ~= ns.seenTab then
			ns.seenTab = selected
			ns:RefreshTabs()
		end

		local x, y = anchor:GetCenter()
		if not x then return end
		local w, h = math.floor(anchor:GetWidth()), math.floor(anchor:GetHeight())
		local fx, fy = math.floor(x), math.floor(y)
		if fx == seatX and fy == seatY and w == seatW and h == seatH and ns:IsChatSeated() then return end
		local sizeChanged = (w ~= seatW) or (h ~= seatH)
		seatX, seatY, seatW, seatH = fx, fy, w, h
		if sizeChanged then
			ns:LayoutWindow()
		else
			ns:ApplyOwnedScale()
			ns:SeatChat()
		end
	end)

	ns.events:RegisterEvent("UPDATE_CHAT_WINDOWS")
	ns.events:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
	ns.events:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	ns.events:RegisterEvent("DISPLAY_SIZE_CHANGED")
	ns.events:RegisterEvent("UI_SCALE_CHANGED")
	ns.events:RegisterEvent("PLAYER_REGEN_ENABLED")
	ns.events:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
	ns.events:RegisterEvent("CHANNEL_UI_UPDATE")
	ns.events:RegisterEvent("CHAT_MSG_WHISPER")
	ns.events:RegisterEvent("CHAT_MSG_BN_WHISPER")
	ns.events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	ns.events:RegisterEvent("PLAYER_TARGET_CHANGED")
	ns.events:RegisterEvent("GROUP_ROSTER_UPDATE")
	ns.events:RegisterEvent("WHO_LIST_UPDATE")
	ns:GROUP_ROSTER_UPDATE()
	-- GLOBAL_MOUSE_DOWN is Mainline/Forever; skip it where the client does not know the event.
	local validate = C_EventUtils and C_EventUtils.IsEventValid
	if validate then
		if validate("GLOBAL_MOUSE_DOWN") then ns.events:RegisterEvent("GLOBAL_MOUSE_DOWN") end
	else
		pcall(ns.events.RegisterEvent, ns.events, "GLOBAL_MOUSE_DOWN")
	end

	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", function()
			ns.inEditMode = true
			ns:ApplyEnabled()
		end, ns)
		EventRegistry:RegisterCallback("EditMode.Exit", function()
			ns.inEditMode = false
			ns:ApplyEnabled()
		end, ns)
		-- IM style leaves the edit box shown; only an actual focus opens a closed window.
		EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusGained", function(_, editBox)
			if not ns.db.enabled then return end
			local frame = editBox and editBox.chatFrame
			if frame and frame ~= ChatFrame1 and not frame.isDocked then return end
			if not frame and editBox ~= (ChatFrame1 and ChatFrame1.editBox) then return end
			if editBox and editBox.EnableMouse then editBox:EnableMouse(true) end
			if ns.db.collapsed then
				ns:SetCollapsed(false)
			end
		end, ns)
		-- ChatFrameMixin:OnHyperlinkEnter / OnHyperlinkLeave (ChatFrame.lua:27-33) broadcast via
		-- EventRegistry without showing a tooltip on their own; listening here shows link tooltips on
		-- hover without touching or tainting ChatFrame1..10 scripts.
		EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", function(_, chatFrame, link, text)
			ShowHyperlinkTooltip(chatFrame, link, text)
		end, ns)
		EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", function(_, chatFrame)
			if chatFrame and chatFrame ~= ChatFrame1 and not chatFrame.isDocked then return end
			HideHyperlinkTooltip()
		end, ns)
	end
end
