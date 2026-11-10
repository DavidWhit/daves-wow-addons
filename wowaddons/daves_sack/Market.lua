-- daves_sack / Market.lua
-- Companion Market Analysis & Insights window opened from the gavel button
-- beside the trash can in the bag toolbar (or /sack market). Styled in the
-- same HUD Edit Mode dialog chrome as DavesSackFrame and Bag Settings.

local _, ns = ...
local M = ns.MEDIA
local C_Item = C_Item
local GetItemInfo = C_Item and C_Item.GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant
local GetQualityByID = C_Item and C_Item.GetItemQualityByID
local RequestLoadItemData = C_Item and C_Item.RequestLoadItemDataByID
local floor, max, min, abs, sort, find, format =
	math.floor, math.max, math.min, math.abs, table.sort, string.find, string.format
local ipairs, pairs, wipe = ipairs, pairs, wipe
local Group = BreakUpLargeNumbers or tostring

local WIDTH, MIN_HEIGHT, MAX_HEIGHT = 460, 440, 620
local PAD = 16
local ROW_H, ROW_GAP = 40, 3
local MAX_ROWS = 60

local TRIM = { 0.23, 0.23, 0.25, 1 }
local SLOTBG = { 0.08, 0.08, 0.09, 1 }
local AH_CUT = 0.95 -- 5% standard Auction House cut

local SMALL_GOLD   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t"
local SMALL_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t"
local SMALL_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t"

local TABS = {
	{ id = 1, label = "Trends",        title = "Market Trends & Movers" },
	{ id = 2, label = "Top 10 Sold",   title = "Top 10 Hot & Turned-Over Items" },
	{ id = 3, label = "Top 20 Margin", title = "Top 20 Highest Margin Opportunities" },
	{ id = 4, label = "Bag Advisor",   title = "Bag Market Advisor (Your Items)" },
}

local SUB_FILTERS = {
	[1] = {
		{ key = "all",    label = "All Movers" },
		{ key = "up",     label = "Rising" },
		{ key = "down",   label = "Dipping" },
		{ key = "scarce", label = "Scarce" },
		{ key = "bags",   label = "In Bags" },
	},
	[2] = {
		{ key = "all",    label = "Top 10 Hot" },
		{ key = "turn",   label = "Turnover" },
		{ key = "bids",   label = "Active Bids" },
		{ key = "vol",    label = "High Volume" },
	},
	[3] = {
		{ key = "all",    label = "Top 20 All" },
		{ key = "flip",   label = "Market Flips" },
		{ key = "vendor", label = "Vendor Profit" },
		{ key = "snipe",  label = "Bid Snipes" },
	},
	[4] = {
		{ key = "all",    label = "All Bag Items" },
		{ key = "sell",   label = "Sell Now" },
		{ key = "vendor", label = "Vendor > AH" },
		{ key = "value",  label = "Top Stack" },
	},
}

local mkt
local activeTab = 1
local activeSub = { [1] = "all", [2] = "all", [3] = "all", [4] = "all" }
local searchFilter = nil
local userDragged = false
local rows, tabBtns, subBtns = {}, {}, {}
local bagHoldings = {}
local entries, entryPool = {}, {}
local pendingItemLoad = {}

local function AcquireEntry(idx)
	local e = entryPool[idx]
	if not e then
		e = {}
		entryPool[idx] = e
	end
	return e
end

local function TryTemplate(kind, name, parent, template)
	local ok, f = pcall(CreateFrame, kind, name, parent, template)
	if ok and f then return f end
end

local function Sound(kit)
	if SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

local function Money(copper)
	if ns.MoneyString then return ns.MoneyString(floor((copper or 0) + 0.5)) end
	return tostring(copper or 0)
end

-- Concise 12x12 coin format (at most 2 denominations) so subtitles never overflow or truncate.
local function CompactMoney(copper)
	copper = floor((copper or 0) + 0.5)
	local g = floor(copper / 10000)
	local s = floor((copper % 10000) / 100)
	local c = copper % 100
	if g >= 100 then
		return Group(g) .. SMALL_GOLD
	elseif g > 0 then
		if s > 0 then return Group(g) .. SMALL_GOLD .. " " .. s .. SMALL_SILVER end
		return Group(g) .. SMALL_GOLD
	elseif s > 0 then
		if c > 0 and s < 10 then return s .. SMALL_SILVER .. " " .. c .. SMALL_COPPER end
		return s .. SMALL_SILVER
	end
	return c .. SMALL_COPPER
end

local function QualityColor(q)
	local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if c then return c.r, c.g, c.b, c.hex or "" end
	if q == 0 then return 0.62, 0.62, 0.62, "|cff9d9d9d" end
	return 1, 1, 1, "|cffffffff"
end

-- Resolves item metadata from GetItemInfo / GetItemInfoInstant / cached market record.
local function ResolveItemMeta(id, m, bagRec)
	local name, link, quality, _, _, _, _, _, _, icon, vendorPrice, classID
	if GetItemInfo then
		name, link, quality, _, _, _, _, _, _, icon, vendorPrice, classID = GetItemInfo(id)
	end
	if not icon and GetItemInfoInstant then
		local _, _, _, _, instIcon, instClass = GetItemInfoInstant(id)
		icon, classID = instIcon, classID or instClass
	end
	if m then
		if name and name ~= "" then m.nm = name else name = m.nm end
		if quality and quality >= 0 then m.qu = quality else quality = m.qu end
	end
	if bagRec then
		name = name or (bagRec.link and string.match(bagRec.link, "%[(.-)%]"))
		link = link or bagRec.link
		quality = quality or bagRec.quality
		icon = icon or bagRec.icon
		classID = classID or bagRec.classID
	end
	if not quality and GetQualityByID then
		quality = GetQualityByID(link or id)
	end
	return name, link, quality or 1, icon or 134400, vendorPrice or 0, classID
end

-- Rejects grey vendor trash, white vendor armor/weapons, and absurd gold-seller / prank price walls.
local function IsNoiseItem(m, quality, vendorPrice, classID)
	local q = quality or (m and m.qu) or 1
	-- Poor (grey) items are vendor trash, never real AH market movers
	if q == 0 then return true end
	-- White weapons & armor are vendor gear, not market commodities
	if q == 1 and (classID == 2 or classID == 4) then return true end
	local p = m and m.p or 0
	local posts = m and m.n or 1
	-- Single/double post of a cheap common item listed for >50g and >250x vendor price is gold-transfer/prank noise
	if q <= 1 and posts <= 2 and p >= 500000 and (not vendorPrice or vendorPrice == 0 or p > vendorPrice * 250) then
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Data analysis builders for the 4 tabs
---------------------------------------------------------------------------
-- Only reports a % price trend when we have a genuine multi-scan baseline (m.prev or m.avg from >=2 scans).
local function ComputeTrendPct(m)
	if not (m and m.p and m.p > 0) then return 0, nil end
	local base = (m.prev and m.prev > 0 and m.prev ~= m.p and m.prev)
		or ((m.s or 1) >= 2 and m.avg and m.avg > 0 and m.avg ~= m.p and m.avg)
		or nil
	if base and base > 0 then
		local pct = ((m.p - base) / base) * 100
		-- Ignore absurd >400% thin-supply spikes (1-2 posts left after normal stock cleared)
		if pct > 400 and (m.n or 1) <= 2 then
			return 0, base
		end
		return pct, base
	end
	return 0, m.avg or m.p
end

local function ComputeBestMargin(m, quality, vendorPrice, classID)
	if not (m and m.p and m.p > 0) then return nil end
	local buy = m.p
	local posts = m.n or 1
	local totalQty = m.q or 1
	local floorQty = m.mq or totalQty
	local isGear = (classID == 2 or classID == 4)
	local bestProfit, bestPct, bestTarget, bestKind, bestQty = 0, 0, 0, nil, floorQty

	-- 1. Risk-free Vendor Arbitrage: buyout is strictly below NPC vendor sell price (even for grey/gear items!)
	if vendorPrice and vendorPrice > buy then
		local prof = vendorPrice - buy
		local pct = (prof / buy) * 100
		return prof, pct, vendorPrice, "vendor", floorQty
	end

	-- Exclude grey trash and white vendor gear from all resale/flip calculations
	if IsNoiseItem(m, quality, vendorPrice, classID) then
		return nil
	end

	-- 2. Instant Market Flip (p vs p2):
	--    * Never on Weapons/Armor (classID 2/4), because base itemID groups different random suffixes ("of the Whale" vs "of the Monkey")
	--      and low-volume green/blue BoEs have arbitrary seller pricing rather than a liquid floor.
	--    * Requires liquid market depth (>=6 active posts, >=8 total units) and a small cheap floor (<=35% of supply, <=40 units)
	--      so a 2-post outlier or wishful second seller is never mistaken for a real flip.
	if not isGear and m.p2 and m.p2 > buy and posts >= 6 and totalQty >= 8 and floorQty <= 40 and floorQty <= totalQty * 0.35 then
		local target = m.p2
		if (m.s or 1) >= 2 and m.avg and m.avg > 0 then
			target = min(target, floor(m.avg * 1.35 + 0.5))
		end
		-- Cap credible single-scan flip spread at 3.5x (anything wider without history is a price wall)
		if target > buy and target <= buy * 3.5 then
			local netTarget = floor(target * AH_CUT)
			local prof = netTarget - buy
			if prof >= 100 then -- at least 1 silver net profit per unit
				local pct = (prof / buy) * 100
				if pct >= 12 and pct <= 250 then
					bestProfit, bestPct, bestTarget, bestKind = prof, pct, target, "flip"
				end
			end
		end
	end

	-- 3. Historical Flip (current buyout below multi-scan rolling average):
	--    Requires >=2 scans and liquid supply (>=5 posts; >=8 for gear).
	local minHistPosts = isGear and 8 or 5
	if (m.s or 1) >= 2 and m.avg and m.avg > buy and m.avg <= buy * 3.5 and posts >= minHistPosts then
		local netTarget = floor(m.avg * AH_CUT)
		local prof = netTarget - buy
		if prof >= 100 then
			local pct = (prof / buy) * 100
			if pct >= 12 and prof > bestProfit then
				bestProfit, bestPct, bestTarget, bestKind = prof, pct, m.avg, "hist"
			end
		end
	end

	-- 4. Bid Snipe (lowest bid vs lowest buyout on liquid items):
	if not isGear and posts >= 5 and m.bid and m.bid > 0 and m.bid < buy * 0.80 and m.bid >= buy * 0.15 then
		local netTarget = floor(buy * AH_CUT)
		local prof = netTarget - m.bid
		if prof >= 200 then
			local pct = (prof / m.bid) * 100
			if pct >= 15 and pct <= 300 and (bestKind == nil or bestProfit == 0) then
				bestProfit, bestPct, bestTarget, bestKind = prof, pct, buy, "snipe"
			end
		end
	end

	if not bestKind then return nil end
	return bestProfit, bestPct, bestTarget, bestKind, bestQty
end

local function MatchesSearch(name, id)
	if not searchFilter then return true end
	if name and find(string.lower(name), searchFilter, 1, true) then return true end
	if tostring(id) == searchFilter then return true end
	return false
end

local function BuildEntries()
	wipe(entries)
	if ns.CollectBagHoldings then
		ns.CollectBagHoldings(bagHoldings)
	else
		wipe(bagHoldings)
	end

	local market = ns.db and ns.db.ahMarket or {}
	local prices = ns.db and ns.db.ahPrices or {}
	local sub = activeSub[activeTab] or "all"
	local poolIdx = 0

	if activeTab == 1 then
		-- Tab 1: Market Trends & Movers
		for id, m in pairs(market) do
			local p = m.p or prices[id]
			if p and p > 0 then
				local bagRec = bagHoldings[id]
				local name, link, quality, icon, vendorPrice, classID = ResolveItemMeta(id, m, bagRec)
				if (bagRec or not IsNoiseItem(m, quality, vendorPrice, classID)) and MatchesSearch(name, id) then
					local pct, basePrice = ComputeTrendPct(m)
					local qty = m.q or 0
					local posts = m.n or 0
					local scarce = posts > 0 and qty > 0 and qty <= 5 and quality >= 1 and classID ~= 2 and classID ~= 4
					local include = false
					if sub == "all" then
						include = (posts >= 2 or bagRec ~= nil or abs(pct) >= 2)
					elseif sub == "up" then
						include = pct >= 2 and posts >= 2
					elseif sub == "down" then
						include = pct <= -2 and posts >= 2
					elseif sub == "scarce" then
						include = scarce
					elseif sub == "bags" then
						include = bagRec ~= nil
					end
					if include then
						local score = abs(pct) * 100 + (bagRec and 400 or 0) + min(600, posts * 8)
						poolIdx = poolIdx + 1
						local e = AcquireEntry(poolIdx)
						e.id, e.m, e.name, e.link, e.quality, e.icon, e.vendorPrice = id, m, name, link, quality, icon, vendorPrice
						e.bagCount = bagRec and bagRec.count or 0
						e.price, e.basePrice, e.pct, e.qty, e.posts, e.scarce, e.score = p, basePrice, pct, qty, posts, scarce, score
						entries[#entries + 1] = e
					end
				end
			end
		end
		sort(entries, function(a, b)
			if sub == "up" and a.pct ~= b.pct then return a.pct > b.pct end
			if sub == "down" and a.pct ~= b.pct then return a.pct < b.pct end
			if sub == "scarce" and a.qty ~= b.qty then return a.qty < b.qty end
			if a.score ~= b.score then return a.score > b.score end
			return (a.price or 0) > (b.price or 0)
		end)

	elseif activeTab == 2 then
		-- Tab 2: Top 10 Hot / Sold Items (Turnover, Active Bids, & High Volume)
		for id, m in pairs(market) do
			local p = m.p or prices[id]
			if p and p > 0 then
				local bagRec = bagHoldings[id]
				local name, link, quality, icon, vendorPrice, classID = ResolveItemMeta(id, m, bagRec)
				if not IsNoiseItem(m, quality, vendorPrice, classID) and MatchesSearch(name, id) then
					local qty = m.q or 0
					local prevQty = m.pq or 0
					local cleared = (prevQty > qty) and (prevQty - qty) or 0
					local bids = m.b or 0
					local bidQty = m.bq or 0
					local posts = m.n or 1
					local turn = max(m.turn or 0, cleared + bidQty)
					local include = false
					local score = 0
					if sub == "turn" then
						include = cleared > 0 or turn > 0
						score = cleared * 50 + turn * 20 + posts
					elseif sub == "bids" then
						include = bids > 0
						score = bids * 200 + bidQty * 20 + posts
					elseif sub == "vol" then
						include = qty > 0 and posts >= 3
						score = posts * 25 + qty * 2
					else
						include = (turn > 0 or bids > 0 or posts >= 3 or qty >= 10)
						score = cleared * 45 + bids * 140 + bidQty * 15 + posts * 20 + min(800, qty * 2)
					end
					if include then
						poolIdx = poolIdx + 1
						local e = AcquireEntry(poolIdx)
						e.id, e.m, e.name, e.link, e.quality, e.icon, e.vendorPrice = id, m, name, link, quality, icon, vendorPrice
						e.bagCount = bagRec and bagRec.count or 0
						e.price, e.cleared, e.turn, e.bids, e.bidQty, e.qty, e.posts, e.score =
							p, cleared, turn, bids, bidQty, qty, posts, score
						entries[#entries + 1] = e
					end
				end
			end
		end
		sort(entries, function(a, b)
			if a.score ~= b.score then return a.score > b.score end
			return (a.price or 0) > (b.price or 0)
		end)
		while #entries > 10 do entries[#entries] = nil end

	elseif activeTab == 3 then
		-- Tab 3: Top 20 Highest Margin Items
		for id, m in pairs(market) do
			local p = m.p or prices[id]
			if p and p > 0 then
				local bagRec = bagHoldings[id]
				local name, link, quality, icon, vendorPrice, classID = ResolveItemMeta(id, m, bagRec)
				if MatchesSearch(name, id) then
					local profit, pct, target, kind, buyQty = ComputeBestMargin(m, quality, vendorPrice, classID)
					if kind then
						local include = (sub == "all")
							or (sub == "flip" and (kind == "flip" or kind == "hist"))
							or (sub == "vendor" and kind == "vendor")
							or (sub == "snipe" and kind == "snipe")
						if include then
							-- Score balances unit profit, fillable floor quantity, and listing liquidity
							local depthBoost = min(3, max(1, (m.n or 1) / 8))
							local score = profit * depthBoost * (1 + min(1.5, pct / 80))
							if kind == "vendor" then score = score * 2 end
							poolIdx = poolIdx + 1
							local e = AcquireEntry(poolIdx)
							e.id, e.m, e.name, e.link, e.quality, e.icon, e.vendorPrice = id, m, name, link, quality, icon, vendorPrice
							e.bagCount = bagRec and bagRec.count or 0
							e.price = (kind == "snipe" and m.bid) or p
							e.buyout, e.profit, e.pct, e.target, e.kind, e.buyQty, e.score =
								p, profit, pct, target, kind, buyQty or 1, score
							entries[#entries + 1] = e
						end
					end
				end
			end
		end
		sort(entries, function(a, b)
			if a.score ~= b.score then return a.score > b.score end
			return (a.profit or 0) > (b.profit or 0)
		end)
		while #entries > 20 do entries[#entries] = nil end

	elseif activeTab == 4 then
		-- Tab 4: Bag Market Advisor (analyzes tradeable items currently in your bags)
		local hasFullScan = (ns.db and (ns.db.ahScanCount or 0) > 0)
		for id, bagRec in pairs(bagHoldings) do
			local m = market[id]
			local p = (m and m.p) or prices[id]
			local name, link, quality, icon, vendorPrice = ResolveItemMeta(id, m, bagRec)
			if MatchesSearch(name, id) then
				local count = bagRec.count or 1
				local pct = m and ComputeTrendPct(m) or 0
				local posts = m and m.n or nil
				local qty = m and m.q or nil
				local netUnit = p and floor(p * AH_CUT) or 0
				local netStack = netUnit * count
				local vendorStack = (vendorPrice or 0) * count

				local advice = "fair"
				if not p or p <= 0 then
					advice = (hasFullScan and quality >= 1) and "monopoly" or "uncached"
				elseif vendorPrice and vendorPrice > 0 and netUnit <= vendorPrice then
					advice = "vendor"
				elseif pct >= 10 or (posts and posts <= 3 and quality >= 1) then
					advice = "sell"
				elseif pct <= -15 then
					advice = "hold"
				end

				local include = (sub == "all")
					or (sub == "sell" and (advice == "sell" or advice == "monopoly"))
					or (sub == "vendor" and advice == "vendor")
					or (sub == "value" and (p and p > 0))
				if include then
					local priority = (advice == "sell" and 4)
						or (advice == "monopoly" and 3)
						or (advice == "vendor" and 2)
						or (advice == "fair" and 1)
						or 0
					poolIdx = poolIdx + 1
					local e = AcquireEntry(poolIdx)
					e.id, e.m, e.name, e.link, e.quality, e.icon, e.vendorPrice = id, m, name, link, quality, icon, vendorPrice
					e.bagCount, e.price, e.netUnit, e.netStack = count, p or 0, netUnit, max(netStack, vendorStack)
					e.pct, e.posts, e.qty, e.advice, e.priority = pct, posts, qty, advice, priority
					entries[#entries + 1] = e
				end
			end
		end
		sort(entries, function(a, b)
			if sub == "all" and a.priority ~= b.priority then return a.priority > b.priority end
			if a.netStack ~= b.netStack then return a.netStack > b.netStack end
			return (a.bagCount or 0) > (b.bagCount or 0)
		end)
	end
end

---------------------------------------------------------------------------
-- Row Tooltip & Click
---------------------------------------------------------------------------
local function ShowRowTooltip(row)
	local e = row.entry
	if not e then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if e.link and GameTooltip.SetHyperlink then
		GameTooltip:SetHyperlink(e.link)
	elseif e.id and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(e.id)
	else
		GameTooltip:SetText(e.name or ("Item #" .. tostring(e.id)), 1, 1, 1)
	end

	local m = e.m
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Dave's Sack Market Analysis", 0.83, 0.66, 0.31)
	if e.price and e.price > 0 then
		GameTooltip:AddDoubleLine("Lowest AH Buyout (each)", Money(e.price), 1, 0.82, 0, 1, 1, 1)
		if m and m.mq and m.mq > 0 then
			GameTooltip:AddDoubleLine("Units at Lowest Price", Group(m.mq), 0.75, 0.75, 0.75, 1, 1, 1)
		end
		if m and m.p2 and m.p2 > e.price then
			GameTooltip:AddDoubleLine("2nd-Lowest Listing", Money(m.p2), 0.75, 0.75, 0.75, 1, 1, 1)
		end
		if m and m.avg and m.avg > 0 then
			local scans = m.s or 1
			GameTooltip:AddDoubleLine(format("Historical Avg (%d %s)", scans, scans == 1 and "scan" or "scans"), Money(m.avg), 0.75, 0.75, 0.75, 1, 1, 1)
		end
		if m and m.low and m.high and m.low < m.high then
			GameTooltip:AddDoubleLine("Seen Range (Low - High)", CompactMoney(m.low) .. " - " .. CompactMoney(m.high), 0.75, 0.75, 0.75, 0.9, 0.9, 0.9)
		end
		if m and (m.q or m.n) then
			GameTooltip:AddDoubleLine("Active AH Supply", format("%s units (%s posts)", Group(m.q or 0), Group(m.n or 1)), 0.75, 0.75, 0.75, 1, 1, 1)
		end
		if m and (m.b or 0) > 0 then
			GameTooltip:AddDoubleLine("Auctions with Live Bids", format("%d (%s units)", m.b, Group(m.bq or m.b)), 0.4, 0.9, 0.5, 1, 1, 1)
		end
		GameTooltip:AddDoubleLine("Net Payout After 5% Cut", Money(floor(e.price * AH_CUT)), 0.75, 0.75, 0.75, 0.9, 0.9, 0.9)
	end
	if e.vendorPrice and e.vendorPrice > 0 then
		GameTooltip:AddDoubleLine("Vendor Sell Price (each)", Money(e.vendorPrice), 0.75, 0.75, 0.75, 1, 1, 1)
	end
	if e.bagCount and e.bagCount > 0 then
		GameTooltip:AddDoubleLine("In Your Bags", format("x%d", e.bagCount), 0.35, 0.88, 0.45, 0.35, 0.88, 0.45)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Click to highlight in bags • Shift-click to link item", 0.55, 0.55, 0.58, true)
	GameTooltip:Show()
end

local function OnRowClick(row)
	if CursorHasItem and CursorHasItem() then
		if ns.StoreCursorItem then ns.StoreCursorItem() end
		return
	end
	local e = row.entry
	if not e then return end
	if IsModifiedClick and IsModifiedClick("CHATLINK") then
		local link = e.link or (GetItemInfo and select(2, GetItemInfo(e.id)))
		local insertLink = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
		if link and insertLink and insertLink(link) then return end
	end
	if e.name and ns.SetBagSearch then
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		ns.SetBagSearch(e.name)
	end
end

---------------------------------------------------------------------------
-- Row Widget Pool & Painting
---------------------------------------------------------------------------
local function GetRow(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, mkt.content)
	r:SetHeight(ROW_H)
	r:RegisterForClicks("LeftButtonUp")

	local bg = r:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.025 or 0.05)
	r.bg = bg

	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.82, 0, 0.09)

	local rank = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	rank:SetPoint("LEFT", 5, 0)
	rank:SetWidth(24)
	rank:SetJustifyH("CENTER")
	r.rank = rank

	local slotBox = CreateFrame("Frame", nil, r)
	slotBox:SetSize(30, 30)
	slotBox:SetPoint("LEFT", 31, 0)
	local slotBg = slotBox:CreateTexture(nil, "BACKGROUND")
	slotBg:SetTexture(M .. "slot")
	slotBg:SetVertexColor(SLOTBG[1], SLOTBG[2], SLOTBG[3], 1)
	slotBg:SetAllPoints()
	local icon = slotBox:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", -2, 2)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if slotBox.CreateMaskTexture and icon.AddMaskTexture then
		local mask = slotBox:CreateMaskTexture()
		mask:SetTexture(M .. "slot", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(icon)
		icon:AddMaskTexture(mask)
	end
	local edge = slotBox:CreateTexture(nil, "OVERLAY")
	edge:SetTexture(M .. "slotedge")
	edge:SetAllPoints()
	r.icon, r.edge = icon, edge

	local nameFS = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	nameFS:SetPoint("TOPLEFT", slotBox, "TOPRIGHT", 8, -3)
	nameFS:SetWidth(225)
	nameFS:SetJustifyH("LEFT")
	if nameFS.SetWordWrap then nameFS:SetWordWrap(false) end
	r.nameFS = nameFS

	local subFS = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	subFS:SetPoint("BOTTOMLEFT", slotBox, "BOTTOMRIGHT", 8, 3)
	subFS:SetWidth(245)
	subFS:SetJustifyH("LEFT")
	if subFS.SetWordWrap then subFS:SetWordWrap(false) end
	r.subFS = subFS

	local rightTop = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	rightTop:SetPoint("TOPRIGHT", -8, -4)
	rightTop:SetJustifyH("RIGHT")
	r.rightTop = rightTop

	local rightBot = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	rightBot:SetPoint("BOTTOMRIGHT", -8, 4)
	rightBot:SetJustifyH("RIGHT")
	r.rightBot = rightBot

	r:SetScript("OnEnter", ShowRowTooltip)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r:SetScript("OnClick", OnRowClick)
	r:SetScript("OnReceiveDrag", function() if ns.StoreCursorItem then ns.StoreCursorItem() end end)

	rows[i] = r
	return r
end

local function FormatRankBadge(i)
	if i == 1 then return "|cffffd100#1|r" end
	if i == 2 then return "|cffd8d8e2#2|r" end
	if i == 3 then return "|cffd99058#3|r" end
	return format("|cff8c8c8c#%d|r", i)
end

local function PaintRow(r, idx, e, rowW)
	r.entry = e
	r:SetWidth(rowW)
	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", mkt.content, "TOPLEFT", 0, -((idx - 1) * (ROW_H + ROW_GAP)))

	r.rank:SetText(FormatRankBadge(idx))
	r.icon:SetTexture(e.icon or 134400)

	local qr, qg, qb, qHex = QualityColor(e.quality)
	if (e.quality or 1) >= 2 then
		r.edge:SetVertexColor(qr, qg, qb, 0.9)
	else
		r.edge:SetVertexColor(TRIM[1], TRIM[2], TRIM[3], 1)
	end

	local dispName = e.name
	if not dispName then
		dispName = "Item #" .. tostring(e.id)
		if RequestLoadItemData and not pendingItemLoad[e.id] then
			pendingItemLoad[e.id] = true
			pcall(RequestLoadItemData, e.id)
		end
	end
	local bagTag = (e.bagCount and e.bagCount > 0) and format(" |cff5cd65c[x%d]|r", e.bagCount) or ""
	r.nameFS:SetText(qHex .. dispName .. "|r" .. bagTag)

	if activeTab == 1 then
		-- Trends
		local supplyStr = (e.qty and e.qty > 0)
			and format("%s listed (%s %s)", Group(e.qty), Group(e.posts or 1), (e.posts == 1) and "post" or "posts")
			or "Price cached"
		if e.basePrice and e.basePrice > 0 and e.basePrice ~= e.price then
			r.subFS:SetText(format("Avg: %s • %s", CompactMoney(e.basePrice), supplyStr))
		else
			r.subFS:SetText(supplyStr)
		end
		r.rightTop:SetText(CompactMoney(e.price))
		if e.pct >= 1.5 then
			r.rightBot:SetText(format("|cff5cd65c+%.0f%% Up|r", e.pct))
		elseif e.pct <= -1.5 then
			r.rightBot:SetText(format("|cffff6b6b%.0f%% Down|r", e.pct))
		elseif e.scarce then
			r.rightBot:SetText(format("|cffffd100Scarce (%d left)|r", e.qty))
		else
			r.rightBot:SetText("|cff8c8c8cSteady|r")
		end

	elseif activeTab == 2 then
		-- Top 10 Sold / Hot
		local parts = {}
		if (e.cleared or 0) > 0 then
			parts[#parts + 1] = format("|cff5cd65cSold/Cleared: %s|r", Group(e.cleared))
		end
		if (e.bids or 0) > 0 then
			parts[#parts + 1] = format("|cffffd100%d %s|r", e.bids, e.bids == 1 and "bid" or "bids")
		end
		if (e.qty or 0) > 0 then
			parts[#parts + 1] = format("%s listed (%s posts)", Group(e.qty), Group(e.posts or 1))
		else
			parts[#parts + 1] = "Active market item"
		end
		r.subFS:SetText(table.concat(parts, " • "))
		r.rightTop:SetText(CompactMoney(e.price))
		local cap = (e.price or 0) * max(1, e.qty or 1)
		r.rightBot:SetText("|cff8c8c8cVol:|r " .. CompactMoney(cap))

	elseif activeTab == 3 then
		-- Top 20 Margins
		local tag
		if e.kind == "vendor" then
			tag = format("|cff00e5ff[Vendor]|r Buy %s -> Sell %s", CompactMoney(e.price), CompactMoney(e.target))
		elseif e.kind == "flip" then
			tag = format("|cff5cd65c[Flip x%d]|r Buy %s -> Next %s", e.buyQty or 1, CompactMoney(e.price), CompactMoney(e.target))
		elseif e.kind == "hist" then
			tag = format("|cff66ccff[Below Avg]|r Buy %s -> Avg %s", CompactMoney(e.price), CompactMoney(e.target))
		else
			tag = format("|cffffb84d[Bid Snipe]|r Bid %s -> Buy %s", CompactMoney(e.price), CompactMoney(e.target))
		end
		r.subFS:SetText(tag)
		r.rightTop:SetText("|cff5cd65c+" .. CompactMoney(e.profit) .. "|r")
		r.rightBot:SetText(format("|cff5cd65c+%.0f%% net|r", min(999, e.pct or 0)))

	elseif activeTab == 4 then
		-- Bag Advisor
		if e.advice == "sell" then
			local why = (e.pct >= 10) and format("+%.0f%% above avg", e.pct) or format("Low supply (%d posts)", e.posts or 1)
			r.subFS:SetText(format("|cff5cd65c[Sell Now]|r %s • %s/ea", why, CompactMoney(e.price)))
			r.rightTop:SetText(CompactMoney(e.netStack))
			r.rightBot:SetText("|cff5cd65cPeak AH Value|r")
		elseif e.advice == "monopoly" then
			r.subFS:SetText("|cffffd100[Monopoly]|r 0 Listed on AH!")
			r.rightTop:SetText(e.vendorPrice and e.vendorPrice > 0 and CompactMoney(e.vendorPrice * e.bagCount) or "Unlisted")
			r.rightBot:SetText("|cffffd100Set Your Price|r")
		elseif e.advice == "vendor" then
			r.subFS:SetText(format("|cffff9933[Vendor]|r NPC %s > AH Net %s", CompactMoney(e.vendorPrice), CompactMoney(e.netUnit)))
			r.rightTop:SetText(CompactMoney((e.vendorPrice or 0) * e.bagCount))
			r.rightBot:SetText("|cffff9933Sell to Vendor|r")
		elseif e.advice == "hold" then
			r.subFS:SetText(format("|cffff6b6b[Hold]|r Down %.0f%% vs avg • %s/ea", abs(e.pct), CompactMoney(e.price)))
			r.rightTop:SetText(CompactMoney(e.netStack))
			r.rightBot:SetText("|cffff6b6bHold / Wait|r")
		elseif e.advice == "uncached" then
			r.subFS:SetText("|cff8c8c8cVisit Auction House to scan price|r")
			r.rightTop:SetText(e.vendorPrice and e.vendorPrice > 0 and CompactMoney(e.vendorPrice * e.bagCount) or "—")
			r.rightBot:SetText("|cff8c8c8cUncached|r")
		else
			r.subFS:SetText(format("Unit: %s • Net stack (95%%)", CompactMoney(e.price)))
			r.rightTop:SetText(CompactMoney(e.netStack))
			r.rightBot:SetText("|cff8c8c8cFair Market|r")
		end
	end

	r:Show()
end

---------------------------------------------------------------------------
-- Header Pulse & Refresh
---------------------------------------------------------------------------
function ns.UpdateMarketScanProgressOnly()
	if not (mkt and mkt:IsShown() and mkt.stat1Val) then return end
	if ns.ahScanning then
		mkt.stat1Val:SetText(ns.ahScanProgress and format("|cffd4a94eScanning %d%%…|r", ns.ahScanProgress) or "|cffd4a94eScanning AH…|r")
	end
end

local function UpdatePulseSummary()
	local market = ns.db and ns.db.ahMarket or {}
	local totalItems, totalPosts, upCount, downCount = 0, 0, 0, 0
	for _, m in pairs(market) do
		totalItems = totalItems + 1
		totalPosts = totalPosts + (m.n or 0)
		local pct = ComputeTrendPct(m)
		if pct >= 2 then upCount = upCount + 1
		elseif pct <= -2 then downCount = downCount + 1 end
	end
	local cached = max(totalItems, ns.ahCachedCount or 0)
	local age = (ns.db and ns.db.ahUpdated and ns.FormatAge and ns.FormatAge(ns.db.ahUpdated)) or nil
	if ns.ahScanning then
		mkt.stat1Val:SetText(ns.ahScanProgress and format("|cffd4a94eScanning %d%%…|r", ns.ahScanProgress) or "|cffd4a94eScanning AH…|r")
	else
		mkt.stat1Val:SetText(format("%s items", Group(cached)))
	end
	mkt.stat1Sub:SetText(age and ("Updated " .. age) or "Visit AH to scan")

	if upCount > 0 or downCount > 0 then
		mkt.stat2Val:SetText(format("|cff5cd65c+%d Up|r   |cffff6b6b-%d Down|r", upCount, downCount))
	elseif cached > 0 then
		mkt.stat2Val:SetText("|cffd4a94eSnapshot Ready|r")
	else
		mkt.stat2Val:SetText("|cff8c8c8cNo Data|r")
	end
	mkt.stat2Sub:SetText(totalPosts > 0 and format("%s active posts", Group(totalPosts)) or "Multi-scan trends")

	local bagVal = ns.GetBagAhSummary and select(1, ns.GetBagAhSummary()) or 0
	local netBag = floor(bagVal * AH_CUT + 0.5)
	mkt.stat3Val:SetText(CompactMoney(netBag))
	mkt.stat3Sub:SetText("Your Bags (95% net)")
end

local function RefreshSubFilterBar()
	local list = SUB_FILTERS[activeTab] or {}
	local cur = activeSub[activeTab] or "all"
	local x = 0
	for i = 1, #list do
		local spec = list[i]
		local b = subBtns[i]
		if not b then
			b = CreateFrame("Button", nil, mkt.subBar)
			b:SetHeight(18)
			local bg = b:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			b.bg = bg
			local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			fs:SetPoint("CENTER", 0, 0)
			b.fs = fs
			local hl = b:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 0.82, 0, 0.12)
			subBtns[i] = b
		end
		b.fs:SetText(spec.label)
		local w = max(48, (b.fs:GetStringWidth() or 38) + 12)
		b:SetWidth(w)
		b:ClearAllPoints()
		b:SetPoint("LEFT", mkt.subBar, "LEFT", x, 0)
		local selected = (spec.key == cur)
		if selected then
			b.bg:SetColorTexture(0.83, 0.66, 0.31, 0.28)
			b.fs:SetTextColor(1, 0.86, 0.35)
		else
			b.bg:SetColorTexture(1, 1, 1, 0.06)
			b.fs:SetTextColor(0.78, 0.78, 0.80)
		end
		b:SetScript("OnClick", function()
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			activeSub[activeTab] = spec.key
			if mkt.scroll and mkt.scroll.SetVerticalScroll then
				mkt.scroll:SetVerticalScroll(0)
			end
			ns.RefreshMarket()
		end)
		b:Show()
		x = x + w + 3
	end
	for i = #list + 1, #subBtns do subBtns[i]:Hide() end
end

local function RefreshTabButtons()
	for i, spec in ipairs(TABS) do
		local b = tabBtns[i]
		if b then
			local on = (i == activeTab)
			if on then
				b.bg:SetColorTexture(0.83, 0.66, 0.31, 0.30)
				b.edge:SetColorTexture(0.85, 0.68, 0.25, 0.9)
				b.fs:SetTextColor(1, 0.86, 0.35)
			else
				b.bg:SetColorTexture(0.12, 0.12, 0.14, 0.75)
				b.edge:SetColorTexture(1, 1, 1, 0.14)
				b.fs:SetTextColor(0.82, 0.82, 0.85)
			end
		end
		if i == activeTab and mkt.secTitle then
			mkt.secTitle:SetText(spec.title)
		end
	end
end

function ns.RefreshMarket()
	if not (mkt and mkt:IsShown()) then return end
	UpdatePulseSummary()
	RefreshTabButtons()
	RefreshSubFilterBar()
	BuildEntries()

	local count = min(#entries, MAX_ROWS)
	local rowW = mkt.scroll:GetWidth() or (WIDTH - PAD * 2 - 14)
	for i = 1, count do
		local r = GetRow(i)
		PaintRow(r, i, entries[i], rowW)
	end
	for i = count + 1, #rows do
		rows[i]:Hide()
		rows[i].entry = nil
	end

	local totalH = max(1, count * (ROW_H + ROW_GAP) - ROW_GAP)
	mkt.content:SetSize(rowW, totalH)
	if mkt.scroll and mkt.scroll.GetVerticalScroll and mkt.scroll.SetVerticalScroll then
		local maxS = max(0, totalH - (mkt.scroll:GetHeight() or 280))
		if (mkt.scroll:GetVerticalScroll() or 0) > maxS then
			mkt.scroll:SetVerticalScroll(maxS)
		end
	end

	if count == 0 then
		local cached = ns.ahCachedCount or 0
		if cached == 0 then
			mkt.emptyFS:SetText("No Auction House data cached yet.\n\nOpen the Auction House in any city and Dave's Sack will automatically scan and cache market prices, supply, and margins.")
		elseif activeTab == 1 and (activeSub[1] == "up" or activeSub[1] == "down") and (ns.db.ahScanCount or 0) < 2 then
			mkt.emptyFS:SetText("Price trends compare changes across scans.\n\nYour baseline snapshot is saved! Run a second Auction House scan later to see Rising and Dipping items.")
		elseif activeTab == 3 then
			mkt.emptyFS:SetText("No liquid items currently match this margin filter.\n\n(Trash items and low-volume random-stat BoE gear are automatically filtered out.)")
		elseif activeTab == 2 and activeSub[2] == "turn" and (ns.db.ahScanCount or 0) < 2 then
			mkt.emptyFS:SetText("Turnover compares supply drops between scans.\n\nComplete a second Auction House scan later to see exact supply cleared, or view 'Top 10 Hot' now.")
		else
			mkt.emptyFS:SetText("No matching items found for this filter.")
		end
		mkt.emptyFS:Show()
	else
		mkt.emptyFS:Hide()
	end

	if activeTab == 2 then
		mkt.footHint:SetText("Ranks the Top 10 most active items by supply cleared, live bids & volume.")
	elseif activeTab == 3 then
		mkt.footHint:SetText("Deducts 5% AH cut & filters out trash/BoE suffix noise. Click row to find in bags.")
	elseif activeTab == 4 then
		mkt.footHint:SetText("Compares tradeable items in your bags against live AH prices & vendor value.")
	else
		mkt.footHint:SetText("Click any item row to highlight in bags • Shift-click to link in chat.")
	end
end

---------------------------------------------------------------------------
-- Positioning beside DavesSackFrame
---------------------------------------------------------------------------
local function SyncHeight()
	if not mkt then return end
	local bags = ns.frame
	local bagH = (bags and bags:IsShown() and bags:GetHeight()) or 480
	local h = max(MIN_HEIGHT, min(MAX_HEIGHT, floor(bagH + 0.5)))
	mkt:SetHeight(h)
	if mkt.scroll then
		local scrollH = max(140, h - 178 - 30)
		mkt.scroll:SetSize(WIDTH - PAD * 2 - 14, scrollH)
	end
end

local function DockToBags(force)
	if not mkt then return end
	if userDragged and not force then
		SyncHeight()
		return
	end
	userDragged = false
	SyncHeight()
	mkt:ClearAllPoints()
	local bags = ns.frame
	local left = bags and bags:IsShown() and bags:GetLeft()
	if left then
		local roomLeft = left * bags:GetEffectiveScale() / mkt:GetEffectiveScale()
		if roomLeft > WIDTH + 16 then
			mkt:SetPoint("TOPRIGHT", bags, "TOPLEFT", -8, 0)
		else
			mkt:SetPoint("TOPLEFT", bags, "TOPRIGHT", 8, 0)
		end
	else
		mkt:SetPoint("CENTER")
	end
end

function ns.SyncMarketAnchor()
	if mkt and mkt:IsShown() then
		DockToBags(false)
		ns.RefreshMarket()
	end
end

---------------------------------------------------------------------------
-- Build Window (lazy: created on first open)
---------------------------------------------------------------------------
local function Build()
	mkt = CreateFrame("Frame", "DavesSackMarket", UIParent)
	ns.marketFrame = mkt
	mkt:SetSize(WIDTH, 490)
	mkt:SetScale((ns.db and ns.db.scale) or 1)
	mkt:SetFrameStrata("HIGH")
	mkt:SetFrameLevel(12)
	mkt:SetClampedToScreen(true)
	mkt:EnableMouse(true)
	mkt:SetMovable(true)
	mkt:RegisterForDrag("LeftButton")
	if mkt.SetDontSavePosition then mkt:SetDontSavePosition(true) end
	mkt:SetScript("OnDragStart", function(self)
		if not (CursorHasItem and CursorHasItem()) then
			userDragged = true
			self:StartMoving()
		end
	end)
	mkt:SetScript("OnDragStop", mkt.StopMovingOrSizing)
	mkt:SetScript("OnReceiveDrag", function() if ns.StoreCursorItem then ns.StoreCursorItem() end end)
	mkt:Hide()
	tinsert(UISpecialFrames, "DavesSackMarket")

	local border = TryTemplate("Frame", nil, mkt, "DialogBorderTranslucentTemplate")
	if border then
		border:SetAllPoints()
	else
		border = CreateFrame("Frame", nil, mkt, BackdropTemplateMixin and "BackdropTemplate" or nil)
		border:SetAllPoints()
		border:SetFrameLevel(mkt:GetFrameLevel())
		border:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		border:SetBackdropColor(0, 0, 0, 0.8)
	end
	ns.marketBorder = border
	if ns.ApplyBackground then ns.ApplyBackground() end

	-- Header Title + Gavel Icon
	local title = mkt:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("TOP", 10, -15)
	title:SetText("Market Analysis")
	local titleIcon = mkt:CreateTexture(nil, "ARTWORK")
	titleIcon:SetSize(18, 18)
	titleIcon:SetPoint("RIGHT", title, "LEFT", -6, 0)
	titleIcon:SetTexture(M .. "gavel")

	local close = TryTemplate("Button", nil, mkt, "UIPanelCloseButton")
	if close then
		close:SetPoint("TOPRIGHT")
	else
		close = CreateFrame("Button", nil, mkt)
		close:SetSize(32, 32)
		close:SetPoint("TOPRIGHT", 2, 2)
		close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
		close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
		close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
	end
	close:SetFrameLevel(mkt:GetFrameLevel() + 5)
	close:SetScript("OnClick", function() mkt:Hide() end)

	-- 3 Market Pulse Summary Cards (y = -40)
	local cardW = floor((WIDTH - PAD * 2 - 12) / 3)
	local function MakeStatCard(idx, label)
		local c = CreateFrame("Frame", nil, mkt)
		c:SetSize(cardW, 38)
		c:SetPoint("TOPLEFT", PAD + (idx - 1) * (cardW + 6), -40)
		local bg = c:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, 0.045)
		local topLine = c:CreateTexture(nil, "ARTWORK")
		topLine:SetHeight(1)
		topLine:SetPoint("TOPLEFT"); topLine:SetPoint("TOPRIGHT")
		topLine:SetColorTexture(0.83, 0.66, 0.31, 0.35)
		local val = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		val:SetPoint("TOP", 0, -6)
		local sub = c:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		sub:SetPoint("BOTTOM", 0, 5)
		sub:SetText(label)
		return val, sub
	end
	mkt.stat1Val, mkt.stat1Sub = MakeStatCard(1, "AH Database")
	mkt.stat2Val, mkt.stat2Sub = MakeStatCard(2, "Market Pulse")
	mkt.stat3Val, mkt.stat3Sub = MakeStatCard(3, "Your Bags (95%)")

	-- 4 Primary Mode Tabs (y = -86)
	local tabW = floor((WIDTH - PAD * 2 - 9) / 4)
	for i, spec in ipairs(TABS) do
		local b = CreateFrame("Button", nil, mkt)
		b:SetSize(tabW, 24)
		b:SetPoint("TOPLEFT", PAD + (i - 1) * (tabW + 3), -86)
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		b.bg = bg
		local edge = b:CreateTexture(nil, "ARTWORK")
		edge:SetHeight(2)
		edge:SetPoint("BOTTOMLEFT"); edge:SetPoint("BOTTOMRIGHT")
		b.edge = edge
		local fs = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		fs:SetPoint("CENTER", 0, 1)
		fs:SetText(spec.label)
		b.fs = fs
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.08)
		b:SetScript("OnClick", function()
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			activeTab = i
			if mkt.scroll and mkt.scroll.SetVerticalScroll then mkt.scroll:SetVerticalScroll(0) end
			ns.RefreshMarket()
		end)
		tabBtns[i] = b
	end

	-- Sub-filter bar + Search box (y = -118)
	local subBar = CreateFrame("Frame", nil, mkt)
	subBar:SetSize(WIDTH - PAD * 2 - 122, 20)
	subBar:SetPoint("TOPLEFT", PAD, -118)
	mkt.subBar = subBar

	local mSearch = TryTemplate("EditBox", "DavesSackMarketSearch", mkt, "SearchBoxTemplate")
	if not mSearch then
		mSearch = CreateFrame("EditBox", "DavesSackMarketSearch", mkt, "InputBoxTemplate")
		mSearch:SetAutoFocus(false)
	end
	mSearch:SetSize(108, 20)
	mSearch:SetPoint("TOPRIGHT", -PAD, -118)
	local function OnMarketSearch(self)
		local t = self:GetText()
		searchFilter = (t and t ~= "") and string.lower(t) or nil
		if mkt.scroll and mkt.scroll.SetVerticalScroll then
			mkt.scroll:SetVerticalScroll(0)
		end
		ns.RefreshMarket()
	end
	if mSearch.HookScript then
		mSearch:HookScript("OnTextChanged", OnMarketSearch)
	else
		mSearch:SetScript("OnTextChanged", OnMarketSearch)
	end
	mSearch:SetScript("OnEnterPressed", mSearch.ClearFocus)
	mkt.search = mSearch

	-- Section Header & Divider (y = -146)
	local secTitle = mkt:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	secTitle:SetPoint("TOPLEFT", PAD, -146)
	mkt.secTitle = secTitle

	local secLine = mkt:CreateTexture(nil, "ARTWORK")
	secLine:SetHeight(1)
	secLine:SetColorTexture(1, 1, 1, 0.14)
	secLine:SetPoint("TOPLEFT", PAD, -164)
	secLine:SetPoint("TOPRIGHT", -PAD, -164)

	-- Scrollable List Area (y = -170)
	local scroll = TryTemplate("ScrollFrame", "DavesSackMarketScroll", mkt, "ScrollFrameTemplate")
	local nativeBar = scroll and scroll.ScrollBar
	if not nativeBar then
		scroll = scroll or CreateFrame("ScrollFrame", "DavesSackMarketScroll", mkt)
	end
	scroll:SetPoint("TOPLEFT", PAD, -170)
	scroll:SetSize(WIDTH - PAD * 2 - 14, 280)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - PAD * 2 - 14, 1)
	scroll:SetScrollChild(content)
	if nativeBar then
		if nativeBar.SetHideIfUnscrollable then nativeBar:SetHideIfUnscrollable(true) end
		nativeBar:ClearAllPoints()
		nativeBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
		nativeBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
		if scroll.SetPanExtent then scroll:SetPanExtent(ROW_H + ROW_GAP) end
	else
		scroll:EnableMouseWheel(true)
		scroll:SetScript("OnMouseWheel", function(self, delta)
			local cur = self:GetVerticalScroll() or 0
			local maxS = max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
			self:SetVerticalScroll(max(0, min(maxS, cur - delta * (ROW_H + ROW_GAP))))
		end)
	end
	mkt.scroll, mkt.content = scroll, content

	local emptyFS = mkt:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyFS:SetPoint("CENTER", scroll, "CENTER", 0, 10)
	emptyFS:SetWidth(WIDTH - PAD * 2 - 40)
	emptyFS:SetJustifyH("CENTER")
	if emptyFS.SetWordWrap then emptyFS:SetWordWrap(true) end
	emptyFS:Hide()
	mkt.emptyFS = emptyFS

	-- Footer divider & hint
	local footLine = mkt:CreateTexture(nil, "ARTWORK")
	footLine:SetHeight(1)
	footLine:SetColorTexture(1, 1, 1, 0.14)
	footLine:SetPoint("BOTTOMLEFT", PAD, 28)
	footLine:SetPoint("BOTTOMRIGHT", -PAD, 28)

	local footHint = mkt:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	footHint:SetPoint("BOTTOM", 0, 11)
	mkt.footHint = footHint

	-- Refresh item names when uncached item info arrives from the server
	mkt:SetScript("OnEvent", function(_, event, itemID)
		if event == "GET_ITEM_INFO_RECEIVED" and itemID and pendingItemLoad[itemID] then
			pendingItemLoad[itemID] = nil
			ns.RefreshMarket()
		end
	end)

	mkt:SetScript("OnShow", function(self)
		pcall(self.RegisterEvent, self, "GET_ITEM_INFO_RECEIVED")
		Sound("IG_MAINMENU_OPEN")
		if ns.SyncMarketButton then ns.SyncMarketButton() end
		ns.RefreshMarket()
	end)
	mkt:SetScript("OnHide", function(self)
		pcall(self.UnregisterEvent, self, "GET_ITEM_INFO_RECEIVED")
		if mkt.search then mkt.search:ClearFocus() end
		if ns.SyncMarketButton then ns.SyncMarketButton() end
		Sound("IG_MAINMENU_CLOSE")
	end)
end

function ns.IsMarketOpen()
	return mkt ~= nil and mkt:IsShown()
end

function ns.HideMarket()
	if mkt and mkt:IsShown() then
		mkt:Hide()
	end
end

function ns.ToggleMarket()
	if not mkt then Build() end
	if mkt:IsShown() then
		mkt:Hide()
	else
		DockToBags(true)
		mkt:Show()
	end
end
