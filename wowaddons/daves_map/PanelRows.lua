-- daves_map / PanelRows.lua
-- Variable-height virtualized sidebar row pool: full-reset row rendering (`RenderRow`), inline chain steps
-- (completed greyed out, remaining green), bottom-of-quest item reward rows, embedded Layers/Settings controls,
-- and row click dispatch.

local _, ns = ...

local ui = ns.PanelUI
local C = ns.PANEL_CONST
local ROW_H, ROW_PAD = C.ROW_H, C.ROW_PAD
local HEAD_PAD = 10
local Sound = ns.Sound
local StripCodes = ns.StripCodes

-- Structured 4-column quest grid widths (anchored from right edge so Quest stretches cleanly)
local COL_XP_W = 74
local COL_LVL_W = 34
local COL_STARTER_W = 136
local COL_GAP = 6
local COL_STR_GAP = 8
local CHAIN_BTN_W = 42

local HAS_LOCK_ATLAS = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Padlock")) ~= nil
local HAS_TURNIN_ATLAS = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestTurnin")) ~= nil
local hoverBossRow, hoverBossName

---------------------------------------------------------------------------
-- Pooled Row Helpers & Full Property Reset
---------------------------------------------------------------------------
local function Tick(parent)
	local box = parent:CreateTexture(nil, "ARTWORK")
	box:SetAtlas("questlog-icon-ticksquare", true)
	local mark = parent:CreateTexture(nil, "OVERLAY")
	mark:SetAtlas("questlog-icon-checkmark-yellow", true)
	mark:SetPoint("CENTER", box, "CENTER", 1, 1)
	return {
		box = box,
		SetChecked = function(_, on) mark:SetShown(on == true) end,
		SetShown = function(_, on) box:SetShown(on); if not on then mark:Hide() end end,
	}
end

local function PaintStateIcon(tex, i, state)
	local D = ns.DATA
	tex:SetDesaturated(false)
	tex:SetTexCoord(0, 1, 0, 1)
	if state == "done" then
		ns.PaintDoneIcon(tex, 1)
	elseif state == "ready" then
		if HAS_TURNIN_ATLAS then
			tex:SetAtlas("QuestTurnin")
			tex:SetVertexColor(1, 1, 1)
		else
			tex:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
			tex:SetVertexColor(1, .85, .2)
		end
		tex:SetAlpha(1)
	elseif state == "log" then
		tex:SetTexture("Interface\\GossipFrame\\IncompleteQuestIcon")
		tex:SetVertexColor(1, .9, .4)
		tex:SetAlpha(1)
	elseif state == "locked" then
		if HAS_LOCK_ATLAS then
			tex:SetAtlas("Padlock")
			tex:SetVertexColor(.7, .7, .75)
		else
			ns.PaintCategoryIcon(tex, D.cat[i])
			tex:SetVertexColor(.5, .5, .55)
		end
		tex:SetAlpha(.75)
	else
		ns.PaintCategoryIcon(tex, D.cat[i])
		tex:SetAlpha(1)
	end
end

local function PlaceRowLabels(row, leftX, hasSub, rightPad)
	local rPad = rightPad or ROW_PAD
	row.label:ClearAllPoints()
	row.sub:ClearAllPoints()
	row.count:ClearAllPoints()
	if hasSub then
		row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", -rPad, -3)
		row.label:SetPoint("TOPLEFT", row, "TOPLEFT", leftX, -3)
		row.label:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
		row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", leftX, 3)
		row.sub:SetPoint("RIGHT", row, "RIGHT", -rPad, 0)
		row.sub:Show()
	else
		row.count:SetPoint("RIGHT", row, "RIGHT", -rPad, 0)
		row.label:SetPoint("LEFT", row, "LEFT", leftX, 0)
		row.label:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
		row.sub:Hide()
	end
end

local function ResetRow(row)
	row:SetAlpha(1)
	row.header:Hide()
	row.header.tick:SetShown(false)
	row.qcols:Hide()
	row.selBg:Hide()
	row.selBar:Hide()
	row.rewardBg:Hide()
	row.tick:SetShown(false)
	row.icon:Hide()
	row.icon:ClearAllPoints()
	row.icon:SetSize(15, 15)
	row.icon:SetTexCoord(0, 1, 0, 1)
	row.icon:SetVertexColor(1, 1, 1)
	row.icon:SetDesaturated(false)
	row.icon:SetAlpha(1)
	row.num:SetText("")
	row.num:ClearAllPoints()
	row.label:SetText("")
	row.label:SetAlpha(1)
	row.sub:SetText("")
	row.sub:SetAlpha(1)
	row.sub:Hide()
	row.count:SetText("")
	row.count:SetJustifyH("RIGHT")
	row.colLvl:SetText("")
	row.colLvl:Hide()
	row.colXP:SetText("")
	row.colXP:Hide()
	row.starterBtn:Hide()
	row.starterBtn.lbl:SetText("")
	row.chainBtn:Hide()
	row.chainBtn.lbl:SetText("")
	row.groupBadge.questID = nil
	row.groupBadge:Hide()
	row.groupBadge:ClearAllPoints()
	row.trackBtn.questID = nil
	row.trackBtn.tick:SetChecked(false)
	row.trackBtn:Hide()
	row.trackBtn:ClearAllPoints()
end

local function RenderRow(row, item, yTop)
	local D = ns.DATA
	row.item = item
	if not item then
		row:Hide()
		return
	end
	ResetRow(row)
	row:SetHeight(item.h or ROW_H)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", 0, -yTop)
	row:SetPoint("RIGHT")
	row:Show()

	if item.kind == "qcols" then
		local qc = row.qcols
		local minimal = ns.db and ns.db.minimalQuestInfo == true
		local mode = (ns.db and ns.db.questSort) or "lvl"
		if mode ~= "lvl" and mode ~= "xp" and mode ~= "name" and mode ~= "starter" then
			mode = "lvl"
		end
		if minimal and (mode == "xp" or mode == "starter") then
			mode = "lvl"
		end
		local asc = not (ns.db and ns.db.questSortAsc == false)
		local arrow = asc and " ^" or " v"
		local function StyleCol(btn, text, active)
			btn.lbl:SetText(text)
			if active then
				btn.lbl:SetTextColor(1, 0.84, 0.25)
			else
				btn.lbl:SetTextColor(0.68, 0.70, 0.75)
			end
		end
		StyleCol(qc.nameBtn, mode == "name" and ("Quest" .. arrow) or "Quest", mode == "name")
		StyleCol(qc.starterBtn, mode == "starter" and ("Starter" .. arrow) or "Starter", mode == "starter")
		StyleCol(qc.lvlBtn, mode == "lvl" and ("Lvl" .. arrow) or "Lvl", mode == "lvl")
		StyleCol(qc.xpBtn, mode == "xp" and ("XP" .. arrow) or "XP", mode == "xp")
		qc.lvlBtn:ClearAllPoints()
		qc.nameBtn:ClearAllPoints()
		local nameLeft = (not ui.found and ns.db and ns.db.panelTab == "tracker") and 44 or 26
		if minimal then
			qc.xpBtn:Hide()
			qc.starterBtn:Hide()
			qc.lvlBtn:SetPoint("RIGHT", qc, "RIGHT", -ROW_PAD, 0)
			qc.nameBtn:SetPoint("LEFT", qc, "LEFT", nameLeft, 0)
			qc.nameBtn:SetPoint("RIGHT", qc.lvlBtn, "LEFT", -COL_GAP, 0)
		else
			qc.xpBtn:Show()
			qc.starterBtn:Show()
			qc.lvlBtn:SetPoint("RIGHT", qc.xpBtn, "LEFT", -COL_GAP, 0)
			qc.nameBtn:SetPoint("LEFT", qc, "LEFT", nameLeft, 0)
			qc.nameBtn:SetPoint("RIGHT", qc.starterBtn, "LEFT", -COL_STR_GAP, 0)
		end
		qc:Show()
		return
	end

	local isHeader = item.kind == "lgroup" or item.kind == "zsec" or item.kind == "head"
	if isHeader then
		row.header:Show()
		local hText = row.header.hText
		if item.kind == "lgroup" then
			row.header.icon:Hide()
			row.header.right:SetText("")
			row.header.tick:SetShown(true)
			row.header.tick:SetChecked(item.allOn == true)
			if hText then
				hText:ClearAllPoints()
				hText:SetPoint("LEFT", HEAD_PAD, 0)
				hText:SetPoint("RIGHT", row.header.tick.box, "LEFT", -8, 0)
			end
			row.header:SetText(D.groups[item.gi].title)
		elseif item.kind == "zsec" then
			row.header.icon:SetSize(14, 14)
			row.header.icon:SetTexture(ns.MEDIA .. (item.closed and "plus" or "minus"))
			row.header.icon:Show()
			if hText then
				hText:ClearAllPoints()
				hText:SetPoint("LEFT", row.header.icon, "RIGHT", 6, 0)
				hText:SetPoint("RIGHT", row.header.right, "LEFT", -8, 0)
			end
			row.header:SetText(item.title)
			row.header.right:SetText(tostring(item.n or ""))
		else
			row.header.icon:Hide()
			if item.checked ~= nil then
				row.header.right:SetText("")
				row.header.tick:SetShown(true)
				row.header.tick:SetChecked(item.checked == true)
				if hText then
					hText:ClearAllPoints()
					hText:SetPoint("LEFT", HEAD_PAD, 0)
					hText:SetPoint("RIGHT", row.header.tick.box, "LEFT", -8, 0)
				end
			else
				row.header.right:SetText(item.right or "")
				if hText then
					hText:ClearAllPoints()
					hText:SetPoint("LEFT", HEAD_PAD, 0)
					hText:SetPoint("RIGHT", row.header.right, "LEFT", -8, 0)
				end
			end
			row.header:SetText(item.title)
		end
		return
	end

	if item.kind == "note" then
		local leftX = 6
		if item.groupCount and item.groupCount > 0 then
			local gb = row.groupBadge
			gb.questID = item.groupQuestID
			local w = ns.StyleGroupCountPill(gb, item.groupCount)
			gb:SetPoint("LEFT", row, "LEFT", 6, 0)
			gb:Show()
			leftX = 6 + w + 6
		end
		PlaceRowLabels(row, leftX, item.sub ~= nil and item.sub ~= "")
		row.label:SetText("|cffcccccc" .. item.title .. "|r")
		row.sub:SetText(item.sub or "")
		return
	end

	if item.kind == "cat" then
		local c = D.cats[item.ci]
		local on = ns.IsLayerCatOn(c.id)
		row.tick:SetShown(true)
		row.tick:SetChecked(on)
		row.icon:SetPoint("LEFT", 22, 0)
		ns.PaintCategoryIcon(row.icon, item.ci)
		if not on then row.icon:SetAlpha(0.75) end
		row.icon:Show()
		PlaceRowLabels(row, 40, false)
		row.label:SetText(on and ("|cff59ff73" .. c.title .. "|r") or c.title)
		local n = ui.counts[item.ci] or 0
		row.count:SetText(n > 0 and tostring(n) or "|cff6666660|r")
		return
	end

	if item.kind == "setting_check" then
		row.tick:SetShown(true)
		row.tick:SetChecked(item.checked == true)
		PlaceRowLabels(row, 24, false)
		row.label:SetText(item.label)
		return
	end

	if item.kind == "reward" then
		local name, hex, icon, subLabel = ns.ItemDisplay(item.itemID)
		local indentPx = item.indent == 2 and 40 or 23
		row.rewardBg:ClearAllPoints()
		row.rewardBg:SetPoint("TOPLEFT", indentPx - 3, -1)
		row.rewardBg:SetPoint("BOTTOMRIGHT", -2, 1)
		row.rewardBg:SetColorTexture(0.10, 0.08, 0.05, item.dim and 0.28 or 0.48)
		row.rewardBg:Show()

		row.icon:SetSize(16, 16)
		row.icon:SetPoint("LEFT", indentPx, 0)
		row.icon:SetTexture(icon or 134400)
		row.icon:SetTexCoord(.08, .92, .08, .92)
		if item.dim then
			row:SetAlpha(0.64)
			row.icon:SetDesaturated(true)
			row.icon:SetVertexColor(.72, .74, .78)
		end
		row.icon:Show()

		local rightMeta = subLabel or ""
		if item.stepNum then
			rightMeta = rightMeta ~= "" and ("Step " .. item.stepNum .. " - " .. rightMeta) or ("Step " .. item.stepNum)
		end
		PlaceRowLabels(row, indentPx + 19, false)
		row.count:SetText(rightMeta ~= "" and ("|cff9ea4b0" .. rightMeta .. "|r") or "|cff88ddaaReward|r")
		local itemLabel = ("|c%s[%s]|r"):format(item.dim and "ff8d9199" or (hex or "ffffffff"), name or ("Item #" .. tostring(item.itemID)))
		row.label:SetText(itemLabel)
		return
	end

	if item.kind == "boss" then
		row.rewardBg:ClearAllPoints()
		row.rewardBg:SetPoint("TOPLEFT", 4, -1)
		row.rewardBg:SetPoint("BOTTOMRIGHT", -2, 1)
		row.rewardBg:SetColorTexture(0.08, 0.07, 0.06, (item.num and item.num % 2 == 0) and 0.36 or 0.20)
		row.rewardBg:Show()
		row.num:SetPoint("LEFT", row, "LEFT", 10, 0)
		row.num:SetText(("|cffffd100%d.|r"):format(item.num or 1))
		PlaceRowLabels(row, 34, false)
		row.label:SetText("|cffe8d8a8" .. (item.title or "") .. "|r")
		if item.floorNum and item.numFloors and item.numFloors > 1 then
			row.count:SetText("|cff7fd4ffF" .. item.floorNum .. "|r")
		elseif item.floorNum then
			row.count:SetText("|cffd4b56aMap|r")
		else
			row.count:SetText("")
		end
		return
	end

	if item.kind == "dung_open" then
		local i = item.i
		row.icon:SetPoint("LEFT", 5, 0)
		if i and i ~= 0 and D.cat[i] then
			ns.PaintCategoryIcon(row.icon, D.cat[i])
		else
			row.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
			row.icon:SetTexCoord(.08, .92, .08, .92)
		end
		row.icon:Show()
		row.count:SetText(item.inView and "|cff59ff73Viewing|r" or "|cff7fd4ffFloors|r")
		PlaceRowLabels(row, 23, true)
		row.label:SetText("|cffd2a6ff" .. item.title .. " Map|r")
		row.sub:SetText(item.sub or "")
		return
	end

	if item.kind == "logquest" then
		local tb = row.trackBtn
		tb.questID = item.questID
		tb.tick:SetChecked(item.watched == true)
		tb:SetPoint("LEFT", row, "LEFT", 4, 0)
		tb:Show()

		row.icon:SetPoint("LEFT", 24, 0)
		PaintStateIcon(row.icon, nil, item.state or "log")
		row.icon:Show()

		local onTracker = (not ui.found) and (ns.IsTrackerTab and ns.IsTrackerTab())
		local focusQ = ns.ActiveFocusQuest and ns.ActiveFocusQuest() or nil
		local selected = (focusQ ~= nil and focusQ == item.questID) or (ui.detailQuestID ~= nil and ui.detailQuestID == item.questID)
		if selected then
			if onTracker then
				row.selBg:SetColorTexture(0.20, 0.90, 0.42, 0.18)
				row.selBar:SetColorTexture(0.28, 0.98, 0.48, 0.98)
			else
				row.selBg:SetColorTexture(1, 0.84, 0.25, 0.14)
				row.selBar:SetColorTexture(1, 0.84, 0.25, 0.95)
			end
			row.selBg:Show()
			row.selBar:Show()
		elseif onTracker then
			row.selBg:SetColorTexture(1, 0.82, 0.20, 0.10)
			row.selBg:Show()
			row.selBar:SetColorTexture(1, 0.82, 0.20, 0.82)
			row.selBar:Show()
		end

		local minimal = ns.db and ns.db.minimalQuestInfo == true
		row.colXP:ClearAllPoints()
		row.colLvl:ClearAllPoints()
		row.starterBtn:ClearAllPoints()
		row.label:ClearAllPoints()
		if minimal then
			row.colLvl:SetPoint("RIGHT", row, "RIGHT", -ROW_PAD, 0)
		else
			row.colXP:SetPoint("RIGHT", row, "RIGHT", -ROW_PAD, 0)
			row.colLvl:SetPoint("RIGHT", row.colXP, "LEFT", -COL_GAP, 0)
			row.starterBtn:SetPoint("RIGHT", row.colLvl, "LEFT", -COL_STR_GAP, 0)
		end
		if item.groupCount and item.groupCount > 0 then
			local gb = row.groupBadge
			gb.questID = item.groupQuestID
			ns.StyleGroupCountPill(gb, item.groupCount)
			gb:SetPoint("LEFT", row, "LEFT", 42, 0)
			gb:Show()
			row.label:SetPoint("LEFT", gb, "RIGHT", 6, 0)
		else
			row.label:SetPoint("LEFT", row, "LEFT", 44, 0)
		end
		if minimal then
			row.label:SetPoint("RIGHT", row.colLvl, "LEFT", -COL_GAP, 0)
		else
			row.label:SetPoint("RIGHT", row.starterBtn, "LEFT", -COL_STR_GAP, 0)
		end
		row.sub:Hide()

		local titleColor = selected and (onTracker and "|cff59ff73" or "|cffffd200") or (onTracker and "|cffffd200" or nil)
		local rawTitle = item.title or ("Quest #" .. tostring(item.questID))
		row.label:SetText(titleColor and (titleColor .. rawTitle .. "|r") or rawTitle)
		row.colLvl:SetText(item.lvlTxt or "|cff666666-|r")
		row.colLvl:Show()
		if not minimal then
			row.starterBtn.lbl:SetText(item.zone and ("|cff9ea4b0" .. item.zone .. "|r") or "|cff666666-|r")
			row.starterBtn:Show()
			row.colXP:SetText(item.xpColTxt or "|cff7fd4ffIn Log|r")
			row.colXP:Show()
		end
		return
	end

	if item.kind == "cstep" then
		local i = item.i
		row.rewardBg:ClearAllPoints()
		row.rewardBg:SetPoint("TOPLEFT", 18, -1)
		row.rewardBg:SetPoint("BOTTOMRIGHT", -2, 1)
		row.rewardBg:SetColorTexture(0.06, 0.08, 0.10, 0.42)
		row.rewardBg:Show()

		local shiftX = 0
		if item.trackQuestID then
			local tb = row.trackBtn
			tb.questID = item.trackQuestID
			tb.tick:SetChecked(item.watched == true)
			tb:SetPoint("LEFT", row, "LEFT", 20, 0)
			tb:Show()
			shiftX = 18
		end

		-- Numbered bullet indented cleanly under the parent quest row
		row.num:SetPoint("LEFT", row, "LEFT", 24 + shiftX, 0)
		row.icon:SetSize(14, 14)
		row.icon:SetPoint("LEFT", 42 + shiftX, 0)
		PaintStateIcon(row.icon, i, item.state)
		row.icon:Show()

		-- Align cstep columns with the 4-column quest grid: Quest | Starter (link) | Lvl | XP
		row.colXP:ClearAllPoints()
		row.colLvl:ClearAllPoints()
		row.starterBtn:ClearAllPoints()
		row.label:ClearAllPoints()
		row.colXP:SetPoint("RIGHT", row, "RIGHT", -ROW_PAD, 0)
		row.colLvl:SetPoint("RIGHT", row.colXP, "LEFT", -COL_GAP, 0)
		row.starterBtn:SetPoint("RIGHT", row.colLvl, "LEFT", -COL_STR_GAP, 0)
		if item.groupCount and item.groupCount > 0 then
			local gb = row.groupBadge
			gb.questID = item.groupQuestID
			ns.StyleGroupCountPill(gb, item.groupCount)
			gb:SetPoint("LEFT", row, "LEFT", 58 + shiftX, 0)
			gb:Show()
			row.label:SetPoint("LEFT", gb, "RIGHT", 5, 0)
		else
			row.label:SetPoint("LEFT", row, "LEFT", 60 + shiftX, 0)
		end
		row.label:SetPoint("RIGHT", row.starterBtn, "LEFT", -COL_STR_GAP, 0)
		row.sub:Hide()

		local cleanTitle = D.title[i] or ""
		local starterTxt = item.starterName or "-"
		local onTracker = (not ui.found) and (ns.IsTrackerTab and ns.IsTrackerTab())
		local selPin = ns.FocusedPin()
		local focusQ = ns.ActiveFocusQuest and ns.ActiveFocusQuest() or nil
		local stepQ = item.inLogQuestID or item.trackQuestID or (D.qid[i] ~= 0 and D.qid[i] or nil)
		local isSelected = (selPin ~= nil and (selPin == i or (D.qid[selPin] ~= 0 and D.qid[selPin] == D.qid[i])))
			or (onTracker and stepQ ~= nil and ((focusQ ~= nil and focusQ == stepQ) or (ui.detailQuestID ~= nil and ui.detailQuestID == stepQ)))
		local isOnQuest = onTracker and (item.state == "log" or item.state == "ready" or item.inLogQuestID ~= nil)
		if isSelected then
			if onTracker then
				row.selBg:SetColorTexture(0.20, 0.90, 0.42, 0.18)
				row.selBar:SetColorTexture(0.28, 0.98, 0.48, 0.98)
			else
				row.selBg:SetColorTexture(1, 0.84, 0.25, 0.15)
				row.selBar:SetColorTexture(1, 0.84, 0.25, 0.95)
			end
			row.selBg:Show()
			row.selBar:Show()
		elseif isOnQuest then
			row.selBg:SetColorTexture(1, 0.82, 0.20, 0.11)
			row.selBg:Show()
			row.selBar:SetColorTexture(1, 0.82, 0.20, 0.86)
			row.selBar:Show()
		end
		if item.isDone then
			row:SetAlpha(isSelected and 0.90 or 0.66)
			row.num:SetText(("|cff777b84%d.|r"):format(item.n))
			row.icon:SetDesaturated(true)
			row.icon:SetVertexColor(.62, .65, .70)
			row.icon:SetAlpha(.70)
			local doneCol = isSelected and (onTracker and "|cff59ff73" or "|cffffd200") or "|cff777b84"
			row.label:SetText(doneCol .. cleanTitle .. "|r")
			row.starterBtn.lbl:SetText("|cff778899" .. starterTxt .. "|r")
			row.colLvl:SetText(item.lvlTxt or "|cff666666-|r")
			row.colXP:SetText(item.xpColTxt or "|cff6d8f74Done|r")
		elseif onTracker then
			local numHex = isSelected and "ff59ff73" or (isOnQuest and "ffffdf59" or "ff98a2b0")
			local txtHex = isSelected and "ff59ff73" or (isOnQuest and "ffffd200" or "ffd0d6de")
			row.num:SetText(("|c%s%d.|r"):format(numHex, item.n))
			row.label:SetText(("|c%s%s|r"):format(txtHex, cleanTitle))
			row.starterBtn.lbl:SetText(item.starterName and ("|cff7fd4ff" .. starterTxt .. "|r") or "|cff666666-|r")
			row.colLvl:SetText(item.lvlTxt or "|cff666666-|r")
			row.colXP:SetText(item.xpColTxt or "|cff666666-|r")
		else
			row.num:SetText(("|c%s%d.|r"):format(item.isCurrent and "ffffdf59" or "ff59ff73", item.n))
			row.label:SetText((isSelected and "|cffffd200" or "|cff59ff73") .. cleanTitle .. "|r")
			row.starterBtn.lbl:SetText(item.starterName and ("|cff7fd4ff" .. starterTxt .. "|r") or "|cff666666-|r")
			row.colLvl:SetText(item.lvlTxt or "|cff666666-|r")
			row.colXP:SetText(item.xpColTxt or "|cff666666-|r")
		end
		row.starterBtn:Show()
		row.colLvl:Show()
		row.colXP:Show()
		return
	end

	-- Standard `quest`, `result`, or `poi` row
	local i = item.i
	local checkShift = 0
	if item.kind == "quest" and item.trackQuestID then
		local tb = row.trackBtn
		tb.questID = item.trackQuestID
		tb.tick:SetChecked(item.watched == true)
		tb:SetPoint("LEFT", row, "LEFT", 4, 0)
		tb:Show()
		checkShift = 18
	end
	row.icon:SetPoint("LEFT", 6 + checkShift, 0)
	if item.state then
		PaintStateIcon(row.icon, i, item.state)
	else
		ns.PaintCategoryIcon(row.icon, D.cat[i])
	end
	row.icon:Show()

	local onTracker = (not ui.found) and (ns.IsTrackerTab and ns.IsTrackerTab())
	local selPin = ns.FocusedPin()
	local selQid = (selPin and D.qid[selPin] ~= 0) and D.qid[selPin] or nil
	local focusQ = onTracker and ns.ActiveFocusQuest and ns.ActiveFocusQuest() or nil
	local rowQ = item.inLogQuestID or item.trackQuestID or (D.qid[i] ~= 0 and D.qid[i] or nil)
	-- When a chain is expanded, its active child bullet displays the single selection/on-quest highlight (never duplicate on the parent row).
	local selected = false
	if not (item.hasChain and item.expanded) then
		if selPin ~= nil then
			if item.hasChain then
				selected = (selPin == i or selPin == item.activePin
					or (selQid and (D.qid[i] == selQid or (item.activePin and D.qid[item.activePin] == selQid)))
					or (item.chainSet and item.chainSet[selPin] == true))
			else
				selected = (selPin == i or (item.activePin and selPin == item.activePin)
					or (selQid and (D.qid[i] == selQid or (item.activePin and D.qid[item.activePin] == selQid))))
			end
		end
		if not selected and onTracker and rowQ ~= nil then
			selected = (focusQ ~= nil and focusQ == rowQ) or (ui.detailQuestID ~= nil and ui.detailQuestID == rowQ)
		end
	end
	local isOnQuest = onTracker and (not (item.hasChain and item.expanded))
		and (item.state == "log" or item.state == "ready" or item.inLogQuestID ~= nil)
	if selected then
		if onTracker then
			row.selBg:SetColorTexture(0.20, 0.90, 0.42, 0.18)
			row.selBar:SetColorTexture(0.28, 0.98, 0.48, 0.98)
		else
			row.selBg:SetColorTexture(1, 0.84, 0.25, 0.14)
			row.selBar:SetColorTexture(1, 0.84, 0.25, 0.95)
		end
		row.selBg:Show()
		row.selBar:Show()
	elseif isOnQuest then
		row.selBg:SetColorTexture(1, 0.82, 0.20, 0.10)
		row.selBg:Show()
		row.selBar:SetColorTexture(1, 0.82, 0.20, 0.82)
		row.selBar:Show()
	end

	local hasSub = item.sub ~= nil and item.sub ~= ""
	if item.kind == "quest" and item.lvlTxt then
		local minimal = ns.db and ns.db.minimalQuestInfo == true
		-- Structured quest grid: 4 columns (`Quest | Starter | Lvl | XP`) or minimal (`Quest | Lvl`)
		row.colXP:ClearAllPoints()
		row.colLvl:ClearAllPoints()
		row.starterBtn:ClearAllPoints()
		row.label:ClearAllPoints()
		if minimal then
			row.colLvl:SetPoint("RIGHT", row, "RIGHT", -ROW_PAD, 0)
		else
			row.colXP:SetPoint("RIGHT", row, "RIGHT", -ROW_PAD, 0)
			row.colLvl:SetPoint("RIGHT", row.colXP, "LEFT", -COL_GAP, 0)
			row.starterBtn:SetPoint("RIGHT", row.colLvl, "LEFT", -COL_STR_GAP, 0)
		end
		if item.hasChain then
			local cb = row.chainBtn
			cb:ClearAllPoints()
			cb:SetPoint("LEFT", row, "LEFT", 24 + checkShift, 0)
			cb.icon:SetTexture(ns.MEDIA .. (item.expanded and "minus" or "plus"))
			cb.icon:Show()
			local steps = item.chainSteps or 2
			local doneCnt = item.chainDone or 0
			local cntTxt = doneCnt > 0 and ("%d/%d"):format(doneCnt, steps) or tostring(steps)
			local pillW = cntTxt:find("/", 1, true) and (#cntTxt >= 4 and 58 or 52) or (#cntTxt >= 2 and 46 or CHAIN_BTN_W)
			cb:SetWidth(pillW)
			if item.expanded then
				cb.frame:SetVertexColor(1, 0.96, 0.80, 1)
				cb.icon:SetAlpha(1)
				cb.lbl:SetText("|cffffd200" .. cntTxt .. "|r")
			else
				cb.frame:SetVertexColor(0.90, 0.84, 0.68, 0.94)
				cb.icon:SetAlpha(0.88)
				cb.lbl:SetText("|cffe8d8a8" .. cntTxt .. "|r")
			end
			cb:Show()
			if item.groupCount and item.groupCount > 0 and not item.expanded then
				local gb = row.groupBadge
				gb.questID = item.groupQuestID
				ns.StyleGroupCountPill(gb, item.groupCount)
				gb:SetPoint("LEFT", cb, "RIGHT", 4, 0)
				gb:Show()
				row.label:SetPoint("LEFT", gb, "RIGHT", 6, 0)
			else
				row.label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
			end
		elseif item.groupCount and item.groupCount > 0 then
			local gb = row.groupBadge
			gb.questID = item.groupQuestID
			ns.StyleGroupCountPill(gb, item.groupCount)
			gb:SetPoint("LEFT", row, "LEFT", 24 + checkShift, 0)
			gb:Show()
			row.label:SetPoint("LEFT", gb, "RIGHT", 6, 0)
		else
			row.label:SetPoint("LEFT", row, "LEFT", 26 + checkShift, 0)
		end
		if minimal then
			row.label:SetPoint("RIGHT", row.colLvl, "LEFT", -COL_GAP, 0)
		else
			row.label:SetPoint("RIGHT", row.starterBtn, "LEFT", -COL_STR_GAP, 0)
		end
		row.sub:Hide()

		local rawName = D.title[i] or ""
		local nameTxt
		if selected then
			nameTxt = (onTracker and "|cff59ff73" or "|cffffd200") .. rawName .. "|r"
		elseif isOnQuest then
			nameTxt = "|cffffd200" .. rawName .. "|r"
		elseif item.state == "done" then
			nameTxt = "|cff777b84" .. rawName .. "|r"
			row.icon:SetAlpha(0.75)
		elseif item.state == "locked" then
			nameTxt = "|cff999999" .. rawName .. "|r"
		else
			nameTxt = rawName
		end
		row.label:SetText(nameTxt)
		row.colLvl:SetText(item.lvlTxt)
		row.colLvl:Show()
		if not minimal then
			if item.starterName then
				local sHex = (item.state == "done" and not selected) and "ff778899" or "ff7fd4ff"
				row.starterBtn.lbl:SetText("|c" .. sHex .. item.starterName .. "|r")
			else
				row.starterBtn.lbl:SetText("|cff666666-|r")
			end
			row.starterBtn:Show()
			row.colXP:SetText(item.xpColTxt or "|cff666666-|r")
			row.colXP:Show()
		end
		return
	end

	local onMap = item.here
	if onMap == nil then onMap = ns.IsPinOnCurrentMap(i) end
	local badgeTxt = item.rightTxt
	if not badgeTxt then
		if item.state then
			badgeTxt = ns.StateBadge(item.state, onMap, i)
		else
			badgeTxt = onMap and "|cff59ff73on map|r" or (ns.ZoneName(i) or "")
		end
	end
	PlaceRowLabels(row, 23, hasSub)
	local titleTxt = ns.FormatPinTitle(i, selected)
	if item.state == "done" and not selected then
		titleTxt = "|cff777b84" .. StripCodes(titleTxt) .. "|r"
		row.icon:SetAlpha(0.75)
	elseif item.state == "locked" and not selected then
		titleTxt = "|cff999999" .. StripCodes(titleTxt) .. "|r"
	end
	row.count:SetText(badgeTxt or "")
	row.label:SetText(titleTxt)
	if hasSub then row.sub:SetText(item.sub) end
end

---------------------------------------------------------------------------
-- Variable-Height Virtualized Viewport Renderer
---------------------------------------------------------------------------
local MakeRow

local function FirstVisibleIndex(items, scrollY)
	local lo, hi = 1, #items
	local ans = #items + 1
	while lo <= hi do
		local mid = math.floor((lo + hi) * 0.5)
		local it = items[mid]
		if (it.top + it.h) > scrollY then
			ans = mid
			hi = mid - 1
		else
			lo = mid + 1
		end
	end
	return ans
end

local function Render()
	if not ui.list or (ui.detailsPane and ui.detailsPane:IsShown()) then return end
	local listH = ui.list:GetHeight()
	if not listH or listH <= 0 then return end
	local items = ui.items
	local totalH = ui.totalH or 0
	local maxScroll = math.max(0, totalH - listH)

	if ui.revealItemIdx then
		local target = items[ui.revealItemIdx]
		ui.revealItemIdx = nil
		ui.revealPin = nil
		if target then
			if target.top < (ui.scrollPx + 24) then
				ui.scrollPx = math.max(0, target.top - 28)
			elseif (target.top + target.h) > (ui.scrollPx + listH - 24) then
				ui.scrollPx = math.min(maxScroll, target.top + target.h - listH + 36)
			end
			if ui.lastKey then ui.scrollByKey[ui.lastKey] = ui.scrollPx end
		end
	end

	ui.scrollPx = math.max(0, math.min(ui.scrollPx or 0, maxScroll))
	local tipOwner = GameTooltip:IsShown() and GameTooltip:GetOwner() or nil
	local first = FirstVisibleIndex(items, ui.scrollPx)
	local r = 0
	for idx = first, #items do
		local it = items[idx]
		if it.top >= ui.scrollPx + listH then break end
		r = r + 1
		local row = ui.rows[r] or MakeRow(r)
		RenderRow(row, it, it.top - ui.scrollPx)
	end
	for k = r + 1, #ui.rows do
		local row = ui.rows[k]
		if tipOwner and (tipOwner == row or tipOwner == row.header or tipOwner == row.groupBadge or tipOwner == row.trackBtn) then
			GameTooltip:Hide()
			tipOwner = nil
		end
		row:Hide()
		row.item = nil
	end
	if hoverBossRow then
		local it = hoverBossRow:IsShown() and hoverBossRow.item or nil
		if not (it and it.kind == "boss" and it.inView and it.title == hoverBossName) then
			hoverBossRow, hoverBossName = nil, nil
			if ns.HighlightDungeonBoss then ns.HighlightDungeonBoss(nil) end
		end
	end
	ui.rows.n = r
	if ns.SyncPanelScrollBar then
		ns.SyncPanelScrollBar(ui.scrollPx, listH, totalH)
	end

	if tipOwner then
		for k = 1, r do
			local row = ui.rows[k]
			if row and (tipOwner == row or tipOwner == row.header or tipOwner == row.groupBadge or tipOwner == row.trackBtn) then
				GameTooltip:Hide()
				local over = tipOwner:IsShown() and tipOwner:IsMouseOver()
				if not issecretvalue(over) and over and row.item then
					local onEnter = tipOwner:GetScript("OnEnter")
					if onEnter then onEnter(tipOwner) end
				end
				break
			end
		end
	end
end
ns.RenderPanelRows = Render

---------------------------------------------------------------------------
-- Row Click Dispatch, Settings Mutation & Tooltips
---------------------------------------------------------------------------
local function ApplySettingToggle(skey)
	local db = ns.db
	if not db then return end
	local facIdx = skey:match("^fac_(%d)$")
	if facIdx then
		local k = tonumber(facIdx)
		if not ns.factions then ns.factions = ns.DefaultFactions() end
		local nextOn = not ns.factions[k]
		ns.factions[k] = nextOn
		Sound(nextOn and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		if ns.OnFactionsChanged then ns.OnFactionsChanged() elseif ns.Refresh then ns.Refresh() end
		return
	end
	if skey:match("^blizz_") and ns.GetBlizzMapFilter and ns.SetBlizzMapFilter then
		local nextOn = not ns.GetBlizzMapFilter(skey)
		if ns.SetBlizzMapFilter(skey, nextOn) then
			Sound(nextOn and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
			if ns.NotifySetting then ns.NotifySetting(skey) end
			ns.OnLayerChanged()
		end
		return
	end
	local stitch = ns.OM and ns.OM:GetModule("worldmap")
	if skey == "trackMyZone" then
		db.trackMyZone = not (db.trackMyZone ~= false)
		Sound(db.trackMyZone and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		if ns.NotifySetting then ns.NotifySetting("trackMyZone") end
		if ns.TrackZoneQuests then ns.TrackZoneQuests() end
		ns.OnLayerChanged()
	elseif skey == "focusQuest" then
		db.focusQuest = not (db.focusQuest ~= false)
		Sound(db.focusQuest and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		if not db.focusQuest then
			if ns.SetClickFocus then ns.SetClickFocus(nil) end
			if ns.ClearTrackerFocus then ns.ClearTrackerFocus() end
		end
		if ns.NotifySetting then ns.NotifySetting("focusQuest") end
		if ns.UpdateFocus then ns.UpdateFocus(true) end
		if ns.Refresh then ns.Refresh() end
	elseif skey == "groupQuestCount" then
		db.groupQuestCount = not (db.groupQuestCount ~= false)
		Sound(db.groupQuestCount and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		if ns.NotifySetting then ns.NotifySetting("groupQuestCount") end
		if ns.RefreshGroupQuestCounts then
			ns.RefreshGroupQuestCounts()
		else
			if ns.OnGroupQuestsChanged then ns.OnGroupQuestsChanged() end
			ns.OnLayerChanged()
		end
	elseif skey == "hideCompleted" then
		db.hideCompleted = not db.hideCompleted
		Sound(db.hideCompleted and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		if ns.NotifySetting then ns.NotifySetting("hideCompleted") end
		if ns.Refresh then ns.Refresh() end
	elseif skey == "trackerTrackedOnly" then
		db.trackerTrackedOnly = not (db.trackerTrackedOnly == true)
		Sound(db.trackerTrackedOnly and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		if ns.NotifySetting then ns.NotifySetting("trackerTrackedOnly") end
		if ns.RefreshStyleDialog then ns.RefreshStyleDialog() end
		ns.OnLayerChanged()
	elseif skey == "minimalQuestInfo" then
		db.minimalQuestInfo = not (db.minimalQuestInfo == true)
		Sound(db.minimalQuestInfo and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		if ns.NotifySetting then ns.NotifySetting("minimalQuestInfo") end
		if ns.RefreshStyleDialog then ns.RefreshStyleDialog() end
		ns.OnLayerChanged()
	elseif skey == "enabled" then
		db.enabled = not (db.enabled ~= false)
		Sound(db.enabled and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		if ns.NotifySetting then ns.NotifySetting("enabled") end
		if ns.Refresh then ns.Refresh() end
	elseif skey == "mapBanner" then
		db.mapBanner = not (db.mapBanner ~= false)
		Sound(db.mapBanner and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		if ns.NotifySetting then ns.NotifySetting("mapBanner") end
		if ns.Refresh then ns.Refresh() end
	elseif stitch and stitch.db then
		if skey == "stitch_enabled" then
			stitch.db.enabled = not (stitch.db.enabled ~= false)
			Sound(stitch.db.enabled and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
			if ns.NotifySetting then ns.NotifySetting("seamless") end
			ns.Print("the seamless map changes after a /reload.")
			ns.OnLayerChanged()
		elseif skey == "stitch_dungeonMaps" then
			local on = not (stitch.db.dungeonMaps ~= false)
			stitch.db.dungeonMaps = on
			stitch.db.icons = on
			Sound(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
			if ns.NotifySetting then ns.NotifySetting("dungeonMaps") end
			if stitch.SetDungeonMaps then stitch.SetDungeonMaps(on) end
			if ns.Refresh then ns.Refresh() end
		elseif skey == "stitch_autoSwitch" then
			stitch.db.autoSwitch = not (stitch.db.autoSwitch ~= false)
			Sound(stitch.db.autoSwitch and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
			if ns.NotifySetting then ns.NotifySetting("autoSwitch") end
			ns.OnLayerChanged()
		elseif skey == "stitch_openZoomed" then
			stitch.db.openZoomed = not (stitch.db.openZoomed ~= false)
			Sound(stitch.db.openZoomed and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
			if ns.NotifySetting then ns.NotifySetting("openZoomed") end
			ns.OnLayerChanged()
		end
	end
end

local function ShowRewardItemTooltip(owner, item)
	local D = ns.DATA
	local _, _, _, _, link = ns.ItemDisplay(item.itemID)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if link and GameTooltip.SetHyperlink then
		GameTooltip:SetHyperlink(link)
	elseif GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(item.itemID)
	else
		local nm = ns.ItemDisplay(item.itemID)
		GameTooltip:SetText(nm or ("Item #" .. tostring(item.itemID)), 1, 1, 1)
	end
	if item.questPin and D and D.title[item.questPin] then
		GameTooltip:AddLine(" ")
		local prefix = item.stepNum and ("Chain Step %d: "):format(item.stepNum) or "Reward from: "
		GameTooltip:AddLine(prefix .. D.title[item.questPin], .35, 1, .45, true)
		GameTooltip:AddLine("Click: show quest on map  -  Shift-click: link item", .5, .8, 1)
	else
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Shift-click: link item in chat", .5, .8, 1)
	end
	GameTooltip:Show()
	if IsModifiedClick and IsModifiedClick("COMPAREITEMS") and GameTooltip_ShowCompareItem then
		GameTooltip_ShowCompareItem(GameTooltip)
	end
end

local function LockIfRefTab(targetPin)
	if ui.found or not ns.db then return false end
	local tab = ns.db.panelTab
	if tab == "zone" or tab == "dungeon" then
		if ns.LockRefContext then ns.LockRefContext(tab, ui.zoneMap, targetPin) end
		return true
	end
	return false
end

local function OnRowClick(row, button)
	if button == "Button4" then
		ns.GoBack()
		return
	end
	local D, db = ns.DATA, ns.db
	local item = row.item
	if not (D and db and item) or item.kind == "note" or item.kind == "qcols" then return end

	if item.kind == "head" then
		if item.action == "toggle_all_layers" then
			local nextOn = not (item.checked == true)
			if ns.SetAllOptionalLayers then ns.SetAllOptionalLayers(nextOn) end
			Sound(nextOn and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
			ns.Refresh()
		end
		return
	elseif item.kind == "lgroup" then
		local turnOff = item.allOn == true
		for _, ci in ipairs(D.groups[item.gi].cats) do
			local cat = D.cats[ci]
			if ns.IsCategoryToggleableInLayers(cat) then
				db.layerOn[cat.id] = (not turnOff) or nil
			end
		end
		Sound(turnOff and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON")
		ns.Refresh()
	elseif item.kind == "cat" then
		local id = D.cats[item.ci].id
		local nextOn = not ns.IsLayerCatOn(id)
		db.layerOn[id] = nextOn or nil
		Sound(nextOn and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		ns.Refresh()
	elseif item.kind == "setting_check" then
		ApplySettingToggle(item.skey)
		return
	elseif item.kind == "zsec" then
		db.zoneFold[item.key] = not item.closed
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		ns.OnLayerChanged()
		return
	elseif item.kind == "reward" then
		if IsModifiedClick and IsModifiedClick("CHATLINK") then
			local _, _, _, _, link = ns.ItemDisplay(item.itemID)
			local insertLink = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
			if link and insertLink and insertLink(link) then return end
		end
		if item.questPin then
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			local target = ns.ActivePinTarget(item.questPin)
			local fromRef = LockIfRefTab(target)
			if ns.CloseDungeonView then ns.CloseDungeonView() end
			ns.SetFocusedPin(item.questPin, true)
			if ns.SyncQuestDetailsPane then ns.SyncQuestDetailsPane(item.questPin) end
			ns.ShowPinMap(target, true, fromRef)
		end
	elseif item.kind == "boss" then
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		if item.inView and ns.IsDungeonViewShown and ns.IsDungeonViewShown() then
			if ns.FocusDungeonBoss then ns.FocusDungeonBoss(item.title) end
			return
		end
		local hasPin = item.dungeonPin and item.dungeonPin ~= 0
		local fromRef = hasPin and LockIfRefTab(item.dungeonPin) or false
		ns.BeforeOpenDungeonMap(hasPin and item.dungeonPin or nil, item.dungeonName)
		local opened = false
		if ns.OpenDungeonBoss then
			opened = ns.OpenDungeonBoss(item.instID, item.dungeonName, item.title)
		end
		if not opened and item.isCurrentInstance and ns.OpenCurrentInstanceMap then
			opened = ns.OpenCurrentInstanceMap()
			if opened and ns.IsDungeonViewShown and ns.IsDungeonViewShown() and ns.FocusDungeonBoss then
				ns.FocusDungeonBoss(item.title)
			end
		end
		if not opened and ns.OpenInstancePin then
			opened = ns.OpenInstancePin(hasPin and item.dungeonPin or nil, row, item.dungeonName, true)
			if opened and ns.IsDungeonViewShown and ns.IsDungeonViewShown() and ns.FocusDungeonBoss then
				ns.FocusDungeonBoss(item.title)
			end
		end
		if not (opened and ns.IsDungeonViewShown and ns.IsDungeonViewShown()) then
			ns.CancelOpenDungeonMap()
			if not opened and hasPin then ns.ShowPinMap(item.dungeonPin, true, fromRef) end
		end
		return
	elseif item.kind == "dung_open" then
		local hasPin = item.i and item.i ~= 0
		if hasPin and (IsShiftKeyDown() or IsControlKeyDown()) then
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			ns.SetWaypoint(item.i)
			return
		end
		if item.inView then
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			return
		end
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		local fromRef = hasPin and LockIfRefTab(item.i) or false
		if item.isCurrentInstance and ns.OpenCurrentInstanceMap then
			ns.BeforeOpenDungeonMap(hasPin and item.i or nil, item.title)
			if not ns.OpenCurrentInstanceMap() then
				if not (ns.OpenInstancePin and ns.OpenInstancePin(hasPin and item.i or nil, row, item.title, true)) then
					ns.CancelOpenDungeonMap()
					if hasPin then ns.ShowPinMap(item.i, true, fromRef) end
				end
			end
		elseif ns.OpenInstancePin then
			ns.BeforeOpenDungeonMap(hasPin and item.i or nil, item.title)
			if not ns.OpenInstancePin(hasPin and item.i or nil, row, item.title, true) then
				ns.CancelOpenDungeonMap()
				if hasPin then ns.ShowPinMap(item.i, true, fromRef) end
			end
		end
	elseif item.kind == "logquest" then
		if IsModifiedClick and IsModifiedClick("CHATLINK") and ns.LinkQuestInChat and ns.LinkQuestInChat(item.questID) then
			return
		end
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		if ns.OpenQuestDetails then
			ns.OpenQuestDetails(item.questID)
		end
		return
	elseif item.kind == "cstep" then
		local qid = item.trackQuestID or item.inLogQuestID or (ns.LogQuestIDForPin and ns.LogQuestIDForPin(item.i))
		if qid and IsModifiedClick and IsModifiedClick("CHATLINK") and ns.LinkQuestInChat and ns.LinkQuestInChat(qid) then
			return
		end
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		if IsShiftKeyDown() or IsControlKeyDown() then
			ns.SetWaypoint(item.i)
		elseif button == "RightButton" and qid and ns.QuestInLog(qid) and ns.OpenQuestDetails then
			ns.OpenQuestDetails(qid, item.i)
		else
			local target = item.isCurrent and ns.ActivePinTarget(item.i) or item.i
			local fromRef = LockIfRefTab(target)
			if ns.CloseDungeonView then ns.CloseDungeonView() end
			ns.SetFocusedPin(item.i, true)
			ns.ShowPinMap(target, true, fromRef)
			if not ui.found and db.panelTab == "tracker" and qid and ns.QuestInLog(qid) and ns.OpenQuestDetails then
				ns.OpenQuestDetails(qid, item.i)
			end
		end
	else
		local focusTarget = item.activePin or item.i
		local qid = item.trackQuestID or item.inLogQuestID or (focusTarget and ns.LogQuestIDForPin and ns.LogQuestIDForPin(focusTarget))
		if qid and IsModifiedClick and IsModifiedClick("CHATLINK") and ns.LinkQuestInChat and ns.LinkQuestInChat(qid) then
			return
		end
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		local icon = D.cats[D.cat[item.i]].icon
		if IsShiftKeyDown() or IsControlKeyDown() then
			ns.SetWaypoint(item.i)
		elseif button == "RightButton" and qid and ns.QuestInLog(qid) and ns.OpenQuestDetails then
			ns.OpenQuestDetails(qid, focusTarget)
		elseif icon == "instance" and ns.OpenInstancePin then
			local fromRef = LockIfRefTab(item.i)
			ns.BeforeOpenDungeonMap(item.i, D.title[item.i])
			if not ns.OpenInstancePin(item.i, row, nil, true) then
				ns.CancelOpenDungeonMap()
				ns.ShowPinMap(item.i, true, fromRef)
			end
		elseif not ui.found and db.panelTab == "tracker" and qid and ns.QuestInLog(qid) and ns.OpenQuestDetails then
			local mapTarget = ns.ActivePinTarget(focusTarget)
			if ns.CloseDungeonView then ns.CloseDungeonView() end
			ns.SetFocusedPin(focusTarget, true)
			ns.ShowPinMap(mapTarget, true, false)
			ns.OpenQuestDetails(qid, focusTarget)
		elseif item.hasChain then
			local mapTarget = ns.ActivePinTarget(focusTarget)
			local wasSelected = ns.FocusedPin() == focusTarget
			if ns.CloseDungeonView then ns.CloseDungeonView() end
			local nowExpanded = (item.expanded and not wasSelected) and true or ns.ToggleChainExpanded(item.i, item.expanded)
			ns.SetFocusedPin(focusTarget, true)
			if nowExpanded then
				local fromRef = LockIfRefTab(mapTarget)
				ns.ShowPinMap(mapTarget, true, fromRef)
			end
			ns.OnLayerChanged()
		else
			local mapTarget = ns.ActivePinTarget(focusTarget)
			local fromRef = LockIfRefTab(mapTarget)
			if ns.CloseDungeonView then ns.CloseDungeonView() end
			ns.SetFocusedPin(focusTarget, true)
			ns.ShowPinMap(mapTarget, true, fromRef)
		end
	end
	ns.RefreshIfMapHidden()
end

MakeRow = function(r)
	local row = CreateFrame("Button", nil, ui.list)
	row:SetHeight(ROW_H)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp", "Button4Up")
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAtlas("questlog-quest-glow-yellow")
	hl:SetAllPoints()
	hl:SetAlpha(.42)
	hl:SetBlendMode("ADD")

	row.rewardBg = row:CreateTexture(nil, "BACKGROUND", nil, 0)
	row.rewardBg:Hide()

	row.selBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.selBg:SetAllPoints()
	row.selBg:SetColorTexture(1, 0.84, 0.25, 0.14)
	row.selBg:Hide()

	row.selBar = row:CreateTexture(nil, "OVERLAY")
	row.selBar:SetWidth(3)
	row.selBar:SetPoint("TOPLEFT", 0, -2)
	row.selBar:SetPoint("BOTTOMLEFT", 0, 2)
	row.selBar:SetColorTexture(1, 0.84, 0.25, 0.95)
	row.selBar:Hide()

	row.header = CreateFrame("Button", nil, row, "ListHeaderVisualTemplate")
	row.header:SetAllPoints()
	row.header:SetFrameLevel(row:GetFrameLevel() + 1)
	row.header:RegisterForClicks("LeftButtonUp", "Button4Up")
	row.header.CollapseButton:Hide()
	row.header:SetNormalFontObject("GameFontHighlight")
	row.header:SetHighlightFontObject("GameFontHighlight")
	row.header.icon = row.header:CreateTexture(nil, "OVERLAY")
	row.header.icon:SetPoint("LEFT", HEAD_PAD, 0)
	row.header.icon:Hide()
	row.header.right = row.header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.header.right:SetPoint("RIGHT", -HEAD_PAD, 0)
	row.header.tick = Tick(row.header)
	row.header.tick.box:SetPoint("RIGHT", -HEAD_PAD, 0)
	row.header.tick:SetShown(false)
	local hText = row.header.ButtonText or (row.header.GetTitleRegion and row.header:GetTitleRegion()) or row.header:GetFontString()
	row.header.hText = hText
	if hText then
		hText:SetFontObject("GameFontHighlight")
		hText:SetJustifyH("LEFT")
		hText:SetWordWrap(false)
		if hText.SetNonSpaceWrap then hText:SetNonSpaceWrap(false) end
		if hText.SetMaxLines then hText:SetMaxLines(1) end
		hText:ClearAllPoints()
		hText:SetPoint("LEFT", HEAD_PAD, 0)
		hText:SetPoint("RIGHT", row.header.right, "LEFT", -8, 0)
	end
	row.header:SetScript("OnClick", function(_, button) OnRowClick(row, button) end)
	row.header:SetScript("OnEnter", function(self)
		local item = row.item
		if item and item.action == "toggle_all_layers" then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine("Toggle All Optional Layers", 1, .82, .2)
			GameTooltip:AddLine("Click to toggle all optional POI map icon layers on or off at once.", .9, .9, .9, true)
			GameTooltip:Show()
			return
		end
		if item and item.kind == "zsec" then return end
		local trunc = hText and hText.IsTruncated and hText:IsTruncated()
		if trunc and not issecretvalue(trunc) then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(hText:GetText() or "", 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	row.header:SetScript("OnLeave", function(self)
		if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
	end)

	row.tick = Tick(row)
	row.tick.box:SetPoint("LEFT", 4, 0)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(15, 15)
	row.num = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.num:SetJustifyH("LEFT")
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.sub:SetJustifyH("LEFT")
	row.sub:SetWordWrap(false)
	row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.count:SetJustifyH("RIGHT")
	row.colLvl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.colLvl:SetWidth(COL_LVL_W)
	row.colLvl:SetJustifyH("RIGHT")
	row.colLvl:SetWordWrap(false)
	row.colLvl:Hide()
	row.colXP = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.colXP:SetWidth(COL_XP_W)
	row.colXP:SetJustifyH("RIGHT")
	row.colXP:SetWordWrap(false)
	row.colXP:Hide()

	-- Dedicated 3-sliced brass pill chain expand/collapse button (uniform beveled pill.tga + gold plus/minus.tga)
	local cBtn = CreateFrame("Button", nil, row)
	cBtn:SetSize(CHAIN_BTN_W, 21)
	cBtn:SetFrameLevel(row:GetFrameLevel() + 2)
	cBtn:RegisterForClicks("LeftButtonUp", "Button4Up")
	cBtn.frame = ns.AddBrassPillSlices(cBtn, "BACKGROUND", 11)
	ns.AddBrassPillSlices(cBtn, "HIGHLIGHT", 11, "ADD", 0.35)
	cBtn.icon = cBtn:CreateTexture(nil, "ARTWORK")
	cBtn.icon:SetSize(13, 13)
	cBtn.icon:SetPoint("LEFT", 5, 0)
	cBtn.lbl = cBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cBtn.lbl:SetPoint("LEFT", cBtn.icon, "RIGHT", 2, 0)
	cBtn.lbl:SetPoint("RIGHT", -4, 0)
	cBtn.lbl:SetJustifyH("CENTER")
	cBtn.lbl:SetWordWrap(false)
	cBtn:SetScript("OnClick", function(_, button)
		if button == "Button4" then ns.GoBack(); return end
		local item = row.item
		if not (item and item.hasChain and item.i) then return end
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		ns.ToggleChainExpanded(item.i, item.expanded)
		ns.OnLayerChanged()
	end)
	cBtn:Hide()
	row.chainBtn = cBtn

	local gBadge = ns.CreateGroupCountPill(row, 21, 10, "GameFontHighlightSmall", "ANCHOR_RIGHT", true)
	gBadge:SetFrameLevel(row:GetFrameLevel() + 2)
	gBadge:SetScript("OnClick", function(_, button) OnRowClick(row, button) end)
	row.groupBadge = gBadge

	-- Clickable Quest Log track checkbox on Tracker rows (toggles Objective Tracker watch in place)
	local tBtn = CreateFrame("Button", nil, row)
	tBtn:SetSize(18, 18)
	tBtn:SetFrameLevel(row:GetFrameLevel() + 2)
	tBtn:RegisterForClicks("LeftButtonUp", "Button4Up")
	local tHl = tBtn:CreateTexture(nil, "HIGHLIGHT")
	tHl:SetAllPoints()
	tHl:SetColorTexture(1, 0.85, 0.35, 0.20)
	tBtn.tick = Tick(tBtn)
	tBtn.tick.box:SetPoint("CENTER", 0, 0)
	tBtn:SetScript("OnClick", function(self, button)
		if button == "Button4" then ns.GoBack(); return end
		if self.questID and ns.ToggleQuestTrack then
			ns.ToggleQuestTrack(self.questID)
			if ns.UpdateFocus then ns.UpdateFocus(false) end
			if ns.Refresh then ns.Refresh() elseif ns.OnLayerChanged then ns.OnLayerChanged() end
		end
	end)
	tBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Track Quest", 1, 0.82, 0.2)
		GameTooltip:AddLine("Check to track this quest on the Objective Tracker (also pins it when tracking zone quests).", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	tBtn:SetScript("OnLeave", function(self)
		if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
	end)
	tBtn:Hide()
	row.trackBtn = tBtn

	-- Dedicated clickable Starter column link button (navigates straight to the starter pickup without toggling chains)
	local sBtn = CreateFrame("Button", nil, row)
	sBtn:SetSize(COL_STARTER_W, 20)
	sBtn:SetFrameLevel(row:GetFrameLevel() + 2)
	sBtn:RegisterForClicks("LeftButtonUp", "Button4Up")
	local sHl = sBtn:CreateTexture(nil, "HIGHLIGHT")
	sHl:SetAllPoints()
	sHl:SetColorTexture(0.45, 0.82, 1.0, 0.16)
	sBtn.lbl = sBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sBtn.lbl:SetAllPoints()
	sBtn.lbl:SetJustifyH("LEFT")
	sBtn.lbl:SetWordWrap(false)
	sBtn:SetScript("OnClick", function(_, button)
		if button == "Button4" then ns.GoBack(); return end
		local item = row.item
		if not item then return end
		if item.kind == "logquest" then
			OnRowClick(row, button)
			return
		end
		local targetPin = item.starterNavPin or item.i
		if not targetPin then return end
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		if IsShiftKeyDown() or IsControlKeyDown() then
			ns.SetWaypoint(targetPin)
			return
		end
		local fromRef = LockIfRefTab(targetPin)
		if ns.CloseDungeonView then ns.CloseDungeonView() end
		ns.SetFocusedPin(targetPin, true)
		ns.ShowPinMap(targetPin, true, fromRef)
		ns.RefreshIfMapHidden()
	end)
	sBtn:Hide()
	row.starterBtn = sBtn

	-- Structured sortable 4-column header bar (`Quest | Starter | Lvl | XP`)
	local qc = CreateFrame("Frame", nil, row)
	qc:SetAllPoints()
	qc:SetFrameLevel(row:GetFrameLevel() + 2)
	local qcBg = qc:CreateTexture(nil, "BACKGROUND")
	qcBg:SetAllPoints()
	qcBg:SetColorTexture(0.05, 0.06, 0.08, 0.72)
	local qcLine = qc:CreateTexture(nil, "ARTWORK")
	qcLine:SetHeight(1)
	qcLine:SetPoint("BOTTOMLEFT", 0, 0)
	qcLine:SetPoint("BOTTOMRIGHT", 0, 0)
	qcLine:SetColorTexture(1, 1, 1, 0.14)
	local function MakeColBtn(mode, justify, width)
		local b = CreateFrame("Button", nil, qc)
		b:SetHeight(20)
		if width then b:SetWidth(width) end
		b:RegisterForClicks("LeftButtonUp", "Button4Up")
		local bhl = b:CreateTexture(nil, "HIGHLIGHT")
		bhl:SetAllPoints()
		bhl:SetColorTexture(1, 0.85, 0.35, 0.14)
		b.lbl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.lbl:SetAllPoints()
		b.lbl:SetJustifyH(justify)
		b.lbl:SetWordWrap(false)
		b:SetScript("OnClick", function(_, button)
			if button == "Button4" then ns.GoBack(); return end
			if ns.ToggleQuestSort then ns.ToggleQuestSort(mode) end
		end)
		return b
	end
	qc.xpBtn = MakeColBtn("xp", "RIGHT", COL_XP_W)
	qc.xpBtn:SetPoint("RIGHT", qc, "RIGHT", -ROW_PAD, 0)
	qc.lvlBtn = MakeColBtn("lvl", "RIGHT", COL_LVL_W)
	qc.lvlBtn:SetPoint("RIGHT", qc.xpBtn, "LEFT", -COL_GAP, 0)
	qc.starterBtn = MakeColBtn("starter", "LEFT", COL_STARTER_W)
	qc.starterBtn:SetPoint("RIGHT", qc.lvlBtn, "LEFT", -COL_STR_GAP, 0)
	qc.nameBtn = MakeColBtn("name", "LEFT", nil)
	qc.nameBtn:SetPoint("LEFT", qc, "LEFT", 26, 0)
	qc.nameBtn:SetPoint("RIGHT", qc.starterBtn, "LEFT", -COL_STR_GAP, 0)
	qc:Hide()
	row.qcols = qc

	row:SetScript("OnClick", OnRowClick)
	row:SetScript("OnEnter", function(self)
		local D = ns.DATA
		local item = self.item
		if not (D and item) then return end
		if item.kind == "reward" then
			ShowRewardItemTooltip(self, item)
		elseif item.kind == "boss" then
			if item.inView and ns.HighlightDungeonBoss then
				hoverBossRow, hoverBossName = self, item.title
				ns.HighlightDungeonBoss(item.title)
			end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(("%d. %s"):format(item.num or 1, item.title or ""), 1, .82, .2)
			if item.floorNum then
				if item.numFloors and item.numFloors > 1 then
					GameTooltip:AddLine(("Floor %d - Click to show on dungeon map"):format(item.floorNum), .5, .85, 1)
				else
					GameTooltip:AddLine("Click to highlight on dungeon map", .5, .85, 1)
				end
			else
				GameTooltip:AddLine(item.inView and "Position not mapped on floor yet" or "Click to open dungeon map", .7, .7, .7)
			end
			GameTooltip:Show()
		elseif item.tip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(item.tipTitle or StripCodes(item.label or ""), 1, .82, .2)
			GameTooltip:AddLine(item.tip, .9, .9, .9, true)
			GameTooltip:Show()
		elseif item.kind == "cat" and D.cats[item.ci].info ~= "" then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(D.cats[item.ci].title, 1, 1, 1)
			GameTooltip:AddLine(D.cats[item.ci].info, .9, .9, .9, true)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		if hoverBossRow == self then
			hoverBossRow, hoverBossName = nil, nil
			if ns.HighlightDungeonBoss then ns.HighlightDungeonBoss(nil) end
		end
		if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
	end)
	ui.rows[r] = row
	return row
end

function ns.LayoutPanelRows()
	Render()
end
