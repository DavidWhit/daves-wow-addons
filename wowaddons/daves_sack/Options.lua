-- daves_sack / Options.lua
-- The Settings window opened by the Settings button: same Edit Mode chrome as
-- the bag window, laid out in two columns so it stays short. Built the first
-- time it's opened, so it costs nothing until used. Controls use Blizzard
-- templates where the client has them and fall back to plain widgets plus our
-- own art (Media\thumb) where it doesn't.

local ADDON, ns = ...
local M = ns.MEDIA
local floor, format = math.floor, string.format

local opt
local controls = {}
local WIDTH, HEIGHT = 470, 480
local LEFT_X, LEFT_W = 24, 200          -- left column
local RIGHT_X, RIGHT_W = 252, 194       -- right column
local FULL_W = WIDTH - 48

local function TryTemplate(kind, name, parent, template)
	local ok, f = pcall(CreateFrame, kind, name, parent, template)
	if ok and f then return f end
end

local function Sound(kit)
	if SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

local function Label(parent, text, font)
	local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
	fs:SetText(text)
	return fs
end

-- Gold section title with a divider running to the end of its column.
local function Header(text, x, y, width)
	local h = Label(opt, text, "GameFontNormal")
	h:SetPoint("TOPLEFT", x, y)
	local line = opt:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 0.14); line:SetHeight(1)
	line:SetPoint("LEFT", h, "RIGHT", 8, 0)
	line:SetWidth(math.max(1, width - (h:GetStringWidth() or 0) - 8))
end

local function Tooltip(region, text)
	if not text then return end
	region:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(text, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	region:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Slider: label on the left, live value on the right, bar underneath.
local function Slider(x, y, width, label, minV, maxV, step, fmt, get, set)
	local f = CreateFrame("Frame", nil, opt)
	f:SetSize(width, 40)
	f:SetPoint("TOPLEFT", x, y)
	f.label = Label(f, label, "GameFontHighlight"); f.label:SetPoint("TOPLEFT")
	f.value = Label(f, "", "GameFontNormal"); f.value:SetPoint("TOPRIGHT")

	local s = CreateFrame("Slider", nil, f)
	f.slider = s
	s:SetOrientation("HORIZONTAL")
	s:SetHeight(20)
	s:SetPoint("BOTTOMLEFT"); s:SetPoint("BOTTOMRIGHT")
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s:SetThumbTexture(M .. "thumb")
	local th = s:GetThumbTexture(); if th then th:SetSize(16, 22) end
	local edge = s:CreateTexture(nil, "BACKGROUND", nil, -1)
	edge:SetColorTexture(0.35, 0.35, 0.38, 1)
	edge:SetPoint("LEFT", -1, 0); edge:SetPoint("RIGHT", 1, 0); edge:SetHeight(8)
	local bg = s:CreateTexture(nil, "BACKGROUND")
	bg:SetColorTexture(0, 0, 0, 0.85)
	bg:SetPoint("LEFT"); bg:SetPoint("RIGHT"); bg:SetHeight(6)

	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(self, d)
		if self.IsEnabled and not self:IsEnabled() then return end
		self:SetValue(self:GetValue() + d * step)
	end)
	s:SetScript("OnValueChanged", function(_, v)
		v = floor(v / step + 0.5) * step
		f.value:SetText(fmt(v))
		if not f.syncing and v ~= get() then set(v) end
	end)

	function f:Refresh()
		self.syncing = true
		local v = get()
		s:SetValue(v); self.value:SetText(fmt(v))
		self.syncing = false
	end
	function f:SetActive(on)
		if on and s.Enable then s:Enable() elseif not on and s.Disable then s:Disable() end
		s:EnableMouse(on); s:EnableMouseWheel(on)
		self:SetAlpha(on and 1 or 0.4)
	end
	controls[#controls + 1] = f
	return f
end

local function Check(x, y, width, label, get, set, tip, size)
	local cb = TryTemplate("CheckButton", nil, opt, "UICheckButtonTemplate")
	if not cb then
		cb = CreateFrame("CheckButton", nil, opt)
		cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
		cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
		cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
		cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
	end
	cb:SetSize(size or 26, size or 26)
	cb:SetPoint("TOPLEFT", x - 4, y)
	local builtIn = cb.Text or cb.text
	if builtIn then builtIn:SetText("") end
	local fs = Label(cb, label, "GameFontHighlight")
	fs:SetPoint("LEFT", cb, "RIGHT", 2, 1)
	fs:SetWidth(width - 30); fs:SetJustifyH("LEFT")
	if fs.SetWordWrap then fs:SetWordWrap(false) end
	cb:SetHitRectInsets(0, -(width - 30), 0, 0)          -- the label is clickable too
	cb:SetScript("OnClick", function(self)
		Sound(self:GetChecked() and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		set(self:GetChecked() and true or false)
	end)
	Tooltip(cb, tip)
	function cb:Refresh() self:SetChecked(get() and true or false) end
	controls[#controls + 1] = cb
	return cb
end

local function PanelButton(text, width)
	local b = TryTemplate("Button", nil, opt, "UIPanelButtonTemplate")
	if not b then
		b = CreateFrame("Button", nil, opt)
		local t = b:CreateTexture(nil, "BACKGROUND"); t:SetColorTexture(0.45, 0.08, 0.06, 1); t:SetAllPoints()
		b:SetNormalFontObject("GameFontNormal")
		local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetColorTexture(1, 1, 1, 0.08); hl:SetAllPoints()
	end
	b:SetText(text)
	b:SetSize(width, 22)
	return b
end

local function RefreshAll()
	for _, c in ipairs(controls) do c:Refresh() end
	if controls.height then controls.height:SetActive(ns.db.viewHeight ~= nil) end
	local splitOn = ns.db.splitConsumables ~= false
	for _, cb in ipairs(controls.consGroups or {}) do
		if splitOn and cb.Enable then cb:Enable() elseif not splitOn and cb.Disable then cb:Disable() end
		cb:SetAlpha(splitOn and 1 or 0.4)
	end
end

local function Build()
	opt = CreateFrame("Frame", "DavesSackOptions", UIParent)
	opt:SetSize(WIDTH, HEIGHT)
	opt:SetFrameStrata("DIALOG")
	opt:SetClampedToScreen(true)
	opt:EnableMouse(true); opt:SetMovable(true); opt:RegisterForDrag("LeftButton")
	if opt.SetDontSavePosition then opt:SetDontSavePosition(true) end
	opt:SetScript("OnDragStart", opt.StartMoving)
	opt:SetScript("OnDragStop", opt.StopMovingOrSizing)
	opt:Hide()
	tinsert(UISpecialFrames, "DavesSackOptions")

	local border = TryTemplate("Frame", nil, opt, "DialogBorderTranslucentTemplate")
	if border then
		border:SetAllPoints()
	else
		border = CreateFrame("Frame", nil, opt, BackdropTemplateMixin and "BackdropTemplate" or nil)
		border:SetAllPoints(); border:SetFrameLevel(opt:GetFrameLevel())
		border:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		border:SetBackdropColor(0, 0, 0, 0.8)
	end

	local title = Label(opt, "Bag Settings", "GameFontHighlightLarge")
	title:SetPoint("TOP", 0, -15)

	local close = TryTemplate("Button", nil, opt, "UIPanelCloseButton")
	if close then
		close:SetPoint("TOPRIGHT")
	else
		close = CreateFrame("Button", nil, opt)
		close:SetSize(32, 32); close:SetPoint("TOPRIGHT", 2, 2)
		close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
		close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
		close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
	end
	close:SetFrameLevel(opt:GetFrameLevel() + 5)
	close:SetScript("OnClick", function() opt:Hide() end)

	local db = ns.db

	-- Left column: Size ------------------------------------------------------
	Header("Size", LEFT_X, -50, LEFT_W)
	Slider(LEFT_X, -72, LEFT_W, "Columns", ns.MIN_COLS, ns.MAX_COLS, 1,
		function(v) return format("%d", v) end,
		function() return db.columns end,
		function(v) db.columns = v; ns.Relayout() end)
	Slider(LEFT_X, -120, LEFT_W, "Scale", 0.5, 2, 0.05,
		function(v) return format("%d%%", floor(v * 100 + 0.5)) end,
		function() return db.scale end,
		function(v) db.scale = v; ns.ApplyScale() end)
	Check(LEFT_X, -166, LEFT_W, "Fit height to my items",
		function() return db.viewHeight == nil end,
		function(on)
			db.viewHeight = (not on) and floor(ns.CurrentViewHeight() + 0.5) or nil
			ns.Relayout(); RefreshAll()
		end,
		"The window fits your items each time you open your bags (up to 80% of the screen), then keeps that size while open: new items scroll instead of resizing it. Untick to set your own height.")
	controls.height = Slider(LEFT_X, -196, LEFT_W, "Height", ns.MIN_VIEW, 1400, 10,
		function(v) return format("%d", v) end,
		function() return db.viewHeight or floor(ns.CurrentViewHeight() + 0.5) end,
		function(v) db.viewHeight = v; ns.ApplyView() end)

	-- Right column: Sub-categories + Show -------------------------------------
	local y = -50
	Header("Sub-categories", RIGHT_X, y, RIGHT_W); y = y - 20
	Check(RIGHT_X, y, RIGHT_W, "Reagents by profession",
		function() return db.splitReagents ~= false end,
		function(on) db.splitReagents = on; ns.Relayout() end,
		"Tailoring, Mining, Herbalism… Main professions win over Cooking and First Aid (linen stays under Tailoring).")
	y = y - 26
	Check(RIGHT_X, y, RIGHT_W, "Consumables by type",
		function() return db.splitConsumables ~= false end,
		function(on) db.splitConsumables = on; ns.Relayout(); RefreshAll() end,
		"Split Consumables into the groups below. Untick a group to move its items into Other Consumables.")
	y = y - 24
	-- one switch per consumable group (indented under "Consumables by type")
	controls.consGroups = {}
	for _, g in ipairs(ns.CONSUMABLE_GROUPS) do
		local cb = Check(RIGHT_X + 20, y, RIGHT_W - 20, ns.GROUP_NAMES[g],
			function() return not db.offGroups[g] end,
			function(on) db.offGroups[g] = (not on) or nil; ns.Relayout() end,
			"Untick to show these under Other Consumables instead.", 22)
		controls.consGroups[#controls.consGroups + 1] = cb
		y = y - 22
	end

	y = y - 16
	Header("Extras", RIGHT_X, y, RIGHT_W); y = y - 20
	local cur = Check(RIGHT_X, y, RIGHT_W, "Backpack currencies",
		function() return db.showCurrencies ~= false end,
		function(on) db.showCurrencies = on; ns.RefreshCurrencies() end,
		ns.HasCurrencyAPI and "Currencies you ticked \"Show on Backpack\" in the Currency tab appear in the footer."
			or "This version of the game has no currencies.")
	if not ns.HasCurrencyAPI then
		if cur.Disable then cur:Disable() end
		cur:SetAlpha(0.4)
	end
	y = y - 26
	Check(RIGHT_X, y, RIGHT_W, "Free Space tile",
		function() return db.showFreeSpace ~= false end,
		function(on) db.showFreeSpace = on; ns.Relayout() end,
		"An empty slot to drop items on. You can also drop items anywhere on the bag window.")
	y = y - 26
	Check(RIGHT_X, y, RIGHT_W, "Auto-place split stacks",
		function() return db.autoPlaceSplit ~= false end,
		function(on) db.autoPlaceSplit = on end,
		"After you split a stack, the new stack goes straight into a free slot next to the original. Paused while a merchant, mailbox, trade, bank or auction window is open, so you can drop it there.")
	y = y - 26

	-- Full width: Start collapsed (3 x 3) -------------------------------------
	local foldY = math.min(-236, y) - 20          -- below whichever column is longer
	Header("Start collapsed", LEFT_X, foldY, FULL_W)
	local names = {}
	for i, n in ipairs(ns.CATEGORY_NAMES) do names[i] = n end
	names[#names + 1] = "Free Space"
	local colW = floor(FULL_W / 3)
	for i, name in ipairs(names) do
		local col, row = (i - 1) % 3, floor((i - 1) / 3)
		Check(LEFT_X + col * colW, foldY - 20 - row * 26, colW, name,
			function() return db.startFolded[i] end,
			function(on)
				db.startFolded[i] = on or nil
				db.collapsed[i] = on or nil          -- apply right away too
				ns.Relayout()
			end)
	end

	-- Reset --------------------------------------------------------------------
	local resetY = foldY - 20 - (floor((#names - 1) / 3) + 1) * 26 - 18
	Header("Reset", LEFT_X, resetY, FULL_W)
	local resetPos = PanelButton("Reset Position", 140)
	resetPos:SetPoint("TOPLEFT", LEFT_X, resetY - 22)
	resetPos:SetScript("OnClick", function()
		db.pos = nil; ns.ResetPosition()
	end)
	local defaults = PanelButton("Restore Defaults", 150)
	defaults:SetPoint("TOPRIGHT", -24, resetY - 22)
	defaults:SetScript("OnClick", function()
		db.columns, db.scale, db.viewHeight, db.pos = 10, 1, nil, nil
		db.splitReagents, db.splitConsumables = true, true
		db.showCurrencies, db.showFreeSpace, db.autoPlaceSplit = true, true, true
		wipe(db.collapsed); wipe(db.startFolded); wipe(db.offGroups)
		ns.ApplyScale(); ns.ResetPosition(); ns.Relayout(); ns.RefreshCurrencies(); RefreshAll()
	end)

	local tips = Label(opt, ns.TIPS or "", "GameFontDisableSmall")
	tips:SetPoint("TOPLEFT", LEFT_X, resetY - 58); tips:SetWidth(FULL_W)
	tips:SetJustifyH("LEFT")
	if tips.SetWordWrap then tips:SetWordWrap(true) end
	opt:SetHeight(-(resetY - 58) + 46)

	opt:SetScript("OnShow", function()
		Sound("IG_MAINMENU_OPEN")
		RefreshAll()
	end)
	opt:SetScript("OnHide", function() Sound("IG_MAINMENU_CLOSE") end)
end

-- Open next to the bags (on whichever side has room).
local function Place()
	opt:ClearAllPoints()
	local bags = ns.frame
	local left = bags and bags:IsShown() and bags:GetLeft()
	if left then
		local roomLeft = left * bags:GetEffectiveScale() / opt:GetEffectiveScale()
		if roomLeft > WIDTH + 20 then
			opt:SetPoint("TOPRIGHT", bags, "TOPLEFT", -10, 0)
		else
			opt:SetPoint("TOPLEFT", bags, "TOPRIGHT", 10, 0)
		end
	else
		opt:SetPoint("CENTER")
	end
	-- Detach from the bag window: otherwise dragging Columns/Scale moves the
	-- bags, the Settings window moves with them, and the slider runs away.
	local l, t = opt:GetLeft(), opt:GetTop()
	if l and t then
		opt:ClearAllPoints()
		opt:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
	end
end

function ns.ToggleOptions()
	if not opt then Build() end
	if opt:IsShown() then opt:Hide() else Place(); opt:Show() end
end

-- Keeps the controls in step when the bag window is resized by its corners.
function ns.RefreshOptions()
	if opt and opt:IsShown() then RefreshAll() end
end
