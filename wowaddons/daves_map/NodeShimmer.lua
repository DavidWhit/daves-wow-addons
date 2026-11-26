-- daves_map / NodeShimmer.lua
-- Optional loot-style golden sparkle & shimmer overlay attached to Blizzard's soft-interact
-- GameObject nameplate (`softinteract`) for nearby harvestable nodes (herbs, mining veins,
-- chests, gatherables). Off by default; toggled in Map Settings (gear) / Base / Options.
--
-- Taint-free design:
--   * Anchors one lightweight click-through UIParent shimmer frame to a non-forbidden
--     `softinteract` nameplate, and uses `hooksecurefunc` on `UpdateSoftTargetIconInternal`
--     to silence duplicate soft-interact icon alpha (`SetAlpha(0)`) on NPCs/town furniture.
--   * Snapshots the player's original SoftTarget CVars before enabling and restores them
--     cleanly when turned off (deferring CVar writes until PLAYER_REGEN_ENABLED if in combat).
--   * Zero event hooks and zero OnUpdate cost while disabled or when no node is targeted.

local _, ns = ...

local SHIMMER_CVARS = {
	{ name = "SoftTargetInteract",          val = "3" },  -- Enum.SoftTargetEnableFlags.Any (KB+M & Gamepad)
	{ name = "SoftTargetInteractArc",       val = "2" },  -- wide cone so off-center nodes catch as you pass
	{ name = "SoftTargetInteractRange",     val = "30" }, -- clamped cleanly by client to max allowed range
	{ name = "SoftTargetIconInteract",      val = "1" },  -- required for GameObject soft-interact nameplate icon
	{ name = "SoftTargetIconGameObject",    val = "1" },  -- enable soft-interact on GameObjects (herbs/veins/chests)
	{ name = "SoftTargetLowPriorityIcons",  val = "1" },  -- include non-quest interactable objects
}

-- Town/utility GameObjects that are not harvestable nodes or lootables.
local IGNORE_OBJECT_PATTERNS = {
	"mailbox",
	"anvil",
	"forge",
	"chair",
	"bench",
	"stool",
	"meeting stone",
	"summoning portal",
	"guild vault",
	"guild bank",
	"barber",
	"command board",
	"hero's call board",
	"warchief's command",
	"bulletin board",
	"wanted poster",
	"cooking fire",
	"campfire",
	"portal to ",
	"portal:",
	"soulwell",
	"refreshment table",
	"mage table",
}

-- 10 staggered loot-sparkle motes: { xOff, yStart, travel, speed, phase, size, swayAmp, swayFreq, spin, r, g, b }
local MOTE_SPECS = {
	{ -22, -24, 56, 0.52, 0.05, 16, 3.0, 2.4,  0.65, 1.00, 0.92, 0.48 },
	{  18, -22, 58, 0.48, 0.22, 18, 3.4, 2.1, -0.55, 1.00, 0.98, 0.80 },
	{  -6, -26, 62, 0.56, 0.40, 20, 2.6, 2.8,  0.48, 1.00, 0.86, 0.34 },
	{  25, -18, 50, 0.46, 0.58, 14, 2.8, 2.5, -0.72, 1.00, 0.94, 0.58 },
	{ -26, -16, 48, 0.50, 0.74, 15, 3.2, 2.2,  0.58, 1.00, 0.98, 0.84 },
	{   9, -26, 60, 0.58, 0.14, 17, 2.4, 3.0, -0.50, 1.00, 0.88, 0.38 },
	{ -14, -20, 54, 0.44, 0.33, 13, 3.0, 2.3,  0.80, 1.00, 0.96, 0.72 },
	{   2, -24, 64, 0.54, 0.66, 21, 2.2, 2.6, -0.42, 1.00, 0.92, 0.52 },
	{  15, -24, 52, 0.49, 0.86, 15, 2.9, 2.7,  0.62, 1.00, 0.98, 0.86 },
	{ -19, -22, 56, 0.55, 0.50, 16, 2.7, 2.9, -0.68, 1.00, 0.85, 0.32 },
}

local state = {
	watcher = nil,
	shimmer = nil,
	plate = nil,
	elapsed = 0,
	pendingCVarSync = false,
	refreshQueued = false,
	iconHooked = false,
	initialized = false,
}

---------------------------------------------------------------------------
-- Pure Queries & Helpers
---------------------------------------------------------------------------
function ns.IsNodeShimmerOn()
	return (ns.db and ns.db.nodeShimmer == true) == true
end

local function IsIgnoredObjectName(name)
	if type(name) ~= "string" or issecretvalue(name) or name == "" then return false end
	local low = name:lower()
	for _, pat in ipairs(IGNORE_OBJECT_PATTERNS) do
		if low:find(pat, 1, true) then return true end
	end
	return false
end

local function GetEligibleSoftInteractPlate()
	if not ns.IsNodeShimmerOn() then return nil end
	if not (UnitIsGameObject and C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
	local isObj = UnitIsGameObject("softinteract")
	if issecretvalue(isObj) or isObj ~= true then return nil end
	if UnitName then
		local objName = UnitName("softinteract")
		if IsIgnoredObjectName(objName) then return nil end
	end
	local plate = C_NamePlate.GetNamePlateForUnit("softinteract")
	if not plate then return nil end
	local forb = plate.IsForbidden and plate:IsForbidden()
	if issecretvalue(forb) or forb then return nil end
	local shown = plate:IsShown()
	if issecretvalue(shown) or not shown then return nil end
	return plate
end

---------------------------------------------------------------------------
-- Soft-Target CVar Snapshot & Restore
---------------------------------------------------------------------------
local function SyncSoftTargetCVars()
	local db = ns.db
	if not (db and C_CVar and C_CVar.GetCVar and C_CVar.SetCVar) then return end
	if InCombatLockdown() then
		state.pendingCVarSync = true
		if state.watcher then state.watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
		return
	end
	state.pendingCVarSync = false
	if state.watcher then state.watcher:UnregisterEvent("PLAYER_REGEN_ENABLED") end

	if db.nodeShimmer == true then
		if type(db.nodeShimmerSavedCVars) ~= "table" then
			local saved = {}
			for _, spec in ipairs(SHIMMER_CVARS) do
				local cur = C_CVar.GetCVar(spec.name)
				if cur ~= nil and not issecretvalue(cur) then
					saved[spec.name] = tostring(cur)
				end
			end
			local curSize = C_CVar.GetCVar("SoftTargetNameplateSize")
			if curSize ~= nil and not issecretvalue(curSize) and (tonumber(curSize) or 0) <= 0 then
				saved.SoftTargetNameplateSize = tostring(curSize)
			end
			db.nodeShimmerSavedCVars = saved
		end
		for _, spec in ipairs(SHIMMER_CVARS) do
			local cur = C_CVar.GetCVar(spec.name)
			if cur ~= nil and not issecretvalue(cur) and tostring(cur) ~= spec.val then
				C_CVar.SetCVar(spec.name, spec.val)
			end
		end
		-- Restore SoftTargetNameplateInteract if an earlier build forced it to "1" (avoids extra NPC nameplates).
		if type(db.nodeShimmerSavedCVars) == "table" and db.nodeShimmerSavedCVars.SoftTargetNameplateInteract ~= nil then
			if C_CVar.GetCVar("SoftTargetNameplateInteract") ~= nil then
				C_CVar.SetCVar("SoftTargetNameplateInteract", tostring(db.nodeShimmerSavedCVars.SoftTargetNameplateInteract))
			end
			db.nodeShimmerSavedCVars.SoftTargetNameplateInteract = nil
		end
		local curSize = C_CVar.GetCVar("SoftTargetNameplateSize")
		if curSize ~= nil and not issecretvalue(curSize) and (tonumber(curSize) or 0) <= 0 then
			if type(db.nodeShimmerSavedCVars) == "table" and db.nodeShimmerSavedCVars.SoftTargetNameplateSize == nil then
				db.nodeShimmerSavedCVars.SoftTargetNameplateSize = tostring(curSize)
			end
			C_CVar.SetCVar("SoftTargetNameplateSize", "24")
		end
	elseif type(db.nodeShimmerSavedCVars) == "table" then
		for k, v in pairs(db.nodeShimmerSavedCVars) do
			if type(k) == "string" and C_CVar.GetCVar(k) ~= nil then
				C_CVar.SetCVar(k, tostring(v))
			end
		end
		db.nodeShimmerSavedCVars = nil
	end
end

---------------------------------------------------------------------------
-- Shimmer Overlay & Animation
---------------------------------------------------------------------------
local HideShimmer

local function AnimateShimmer(self, dt)
	local plate = state.plate
	if not (ns.IsNodeShimmerOn() and plate) then
		HideShimmer()
		return
	end
	local forb = plate.IsForbidden and plate:IsForbidden()
	local shown = not issecretvalue(forb) and not forb and plate:IsShown()
	local isObj = UnitIsGameObject and UnitIsGameObject("softinteract")
	local livePlate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("softinteract")
	if issecretvalue(shown) or not shown or issecretvalue(isObj) or isObj ~= true or livePlate ~= plate then
		HideShimmer()
		return
	end

	local t = state.elapsed + math.min(dt or 0, 0.05)
	state.elapsed = t

	-- Warm breathing aura & subtle golden halo
	local breath = 0.5 + 0.5 * math.sin(t * 3.1)
	self.aura:SetAlpha(0.14 + 0.14 * breath)
	local auraSz = 56 + 10 * breath
	self.aura:SetSize(auraSz, auraSz)

	local haloPhase = (t * 0.65) % 1
	local haloFade = math.sin(math.pi * haloPhase)
	self.halo:SetAlpha(0.20 * haloFade * haloFade)
	local haloSz = 38 + 26 * haloPhase
	self.halo:SetSize(haloSz, haloSz)

	-- Rising twinkling loot sparkles
	local motes = self.motes
	for idx = 1, #MOTE_SPECS do
		local sp = MOTE_SPECS[idx]
		local tex = motes[idx]
		local p = (t * sp[4] + sp[5]) % 1
		local fade = math.sin(math.pi * p)
		local twinkle = 0.62 + 0.38 * math.sin(t * (7.5 + idx * 0.7) + idx * 1.9)
		local alpha = (fade ^ 1.35) * twinkle * 0.95
		local sz = sp[6] * (0.48 + 0.70 * fade)
		local x = sp[1] + math.sin(t * sp[8] + idx * 1.3) * sp[7]
		local y = sp[2] + p * sp[3]
		tex:SetSize(sz, sz)
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", self, "CENTER", x, y)
		tex:SetAlpha(alpha)
		if tex.SetRotation then
			tex:SetRotation((t * sp[9] + idx * 0.6) % (math.pi * 2))
		end
	end
end

HideShimmer = function()
	state.plate = nil
	if state.shimmer then
		state.shimmer:SetScript("OnUpdate", nil)
		state.shimmer:Hide()
		state.shimmer:ClearAllPoints()
	end
end

local function EnsureShimmerFrame()
	if state.shimmer then return state.shimmer end
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(96, 96)
	f:SetFrameStrata("LOW")
	f:EnableMouse(false)

	local aura = f:CreateTexture(nil, "BACKGROUND")
	aura:SetTexture(ns.MEDIA .. "dot")
	aura:SetBlendMode("ADD")
	aura:SetVertexColor(1.0, 0.85, 0.28, 1)
	aura:SetPoint("CENTER", f, "CENTER", 0, -4)
	aura:SetSize(60, 60)
	f.aura = aura

	local halo = f:CreateTexture(nil, "BORDER")
	halo:SetTexture(ns.MEDIA .. "ring")
	halo:SetBlendMode("ADD")
	halo:SetVertexColor(1.0, 0.90, 0.44, 1)
	halo:SetPoint("CENTER", f, "CENTER", 0, -4)
	halo:SetSize(48, 48)
	f.halo = halo

	local motes = {}
	for idx = 1, #MOTE_SPECS do
		local sp = MOTE_SPECS[idx]
		local tex = f:CreateTexture(nil, "ARTWORK")
		tex:SetTexture(ns.MEDIA .. "sparkle")
		tex:SetBlendMode("ADD")
		tex:SetVertexColor(sp[10], sp[11], sp[12], 1)
		tex:SetSize(sp[6], sp[6])
		tex:SetPoint("CENTER", f, "CENTER", sp[1], sp[2])
		motes[idx] = tex
	end
	f.motes = motes
	f:Hide()
	state.shimmer = f
	return f
end

local function RefreshShimmer()
	local plate = GetEligibleSoftInteractPlate()
	if not plate then
		HideShimmer()
		return
	end
	local f = EnsureShimmerFrame()
	if state.plate ~= plate or not f:IsShown() then
		state.plate = plate
		f:ClearAllPoints()
		f:SetPoint("CENTER", plate, "CENTER", 0, -8)
		f:Show()
		f:SetScript("OnUpdate", AnimateShimmer)
		AnimateShimmer(f, 0)
	end
end

local function RunQueuedRefresh()
	state.refreshQueued = false
	RefreshShimmer()
end

local function QueueRefresh()
	RefreshShimmer()
	if state.refreshQueued then return end
	state.refreshQueued = true
	C_Timer.After(0, RunQueuedRefresh)
end

---------------------------------------------------------------------------
-- Suppress Duplicate Soft-Interact Icon on NPCs & Town Furniture
---------------------------------------------------------------------------
local function SafeUnitIsUnit(unit, target)
	if not (UnitIsUnit and type(unit) == "string" and not issecretvalue(unit) and unit ~= "") then return false end
	local same = UnitIsUnit(unit, target)
	return (not issecretvalue(same)) and same == true
end

local function SyncSoftTargetIconAlpha(frame, doEnemyIcon, doFriendIcon)
	if not frame then return end
	local forb = frame.IsForbidden and frame:IsForbidden()
	if issecretvalue(forb) or forb then return end
	local uf = frame.UnitFrame
	local stf = uf and uf.SoftTargetFrame
	local icon = stf and stf.Icon
	if not icon then return end
	if not ns.IsNodeShimmerOn() then
		icon:SetAlpha(1)
		return
	end
	local unit = frame.GetUnit and frame:GetUnit()
	if type(unit) ~= "string" or issecretvalue(unit) or unit == "" then
		icon:SetAlpha(1)
		return
	end
	local isObj = UnitIsGameObject and UnitIsGameObject(unit)
	if not issecretvalue(isObj) and isObj == true then
		local objName = UnitName and UnitName(unit)
		icon:SetAlpha(IsIgnoredObjectName(objName) and 0 or 1)
		return
	end
	-- Keep enemy/friendly soft-target icons if the user explicitly enabled those,
	-- but hide Blizzard's duplicate soft-interact icon on NPCs so only their default overhead icon shows.
	if (doEnemyIcon and SafeUnitIsUnit(unit, "softenemy")) or (doFriendIcon and SafeUnitIsUnit(unit, "softfriend")) then
		icon:SetAlpha(1)
	else
		icon:SetAlpha(0)
	end
end

local function RefreshAllSoftTargetIcons()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	local doEnemy = C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("SoftTargetIconEnemy") == true
	local doFriend = C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("SoftTargetIconFriend") == true
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		SyncSoftTargetIconAlpha(plate, doEnemy, doFriend)
	end
end

local function EnsureSoftTargetIconHook()
	if state.iconHooked then return end
	if NamePlateDriverFrame and type(NamePlateDriverFrame.UpdateSoftTargetIconInternal) == "function" then
		state.iconHooked = true
		hooksecurefunc(NamePlateDriverFrame, "UpdateSoftTargetIconInternal", function(_, frame, _, doEnemyIcon, doFriendIcon)
			SyncSoftTargetIconAlpha(frame, doEnemyIcon, doFriendIcon)
		end)
	end
end

---------------------------------------------------------------------------
-- Event Wiring & Public Settings API
---------------------------------------------------------------------------
local function SyncWatcherEvents()
	local w = state.watcher
	if not w then return end
	if ns.IsNodeShimmerOn() then
		w:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
		w:RegisterEvent("NAME_PLATE_UNIT_ADDED")
		w:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
		w:RegisterEvent("PLAYER_ENTERING_WORLD")
		w:RegisterEvent("PLAYER_LEAVING_WORLD")
	else
		w:UnregisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
		w:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
		w:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
		w:UnregisterEvent("PLAYER_ENTERING_WORLD")
		w:UnregisterEvent("PLAYER_LEAVING_WORLD")
	end
end

function ns.SetNodeShimmer(on)
	if not ns.db then return end
	ns.db.nodeShimmer = on == true
	if ns.db.nodeShimmer then EnsureSoftTargetIconHook() end
	SyncWatcherEvents()
	SyncSoftTargetCVars()
	RefreshAllSoftTargetIcons()
	if ns.db.nodeShimmer then
		QueueRefresh()
	else
		HideShimmer()
	end
end

function ns.InitNodeShimmer()
	if state.initialized then return end
	state.initialized = true
	local w = CreateFrame("Frame")
	w:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			if state.pendingCVarSync then
				SyncSoftTargetCVars()
				RefreshAllSoftTargetIcons()
				if ns.IsNodeShimmerOn() then QueueRefresh() end
			end
		elseif event == "PLAYER_LEAVING_WORLD" then
			HideShimmer()
		elseif event == "PLAYER_ENTERING_WORLD" then
			if ns.IsNodeShimmerOn() then
				EnsureSoftTargetIconHook()
				SyncSoftTargetCVars()
				RefreshAllSoftTargetIcons()
				QueueRefresh()
			else
				HideShimmer()
			end
		elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
			if state.plate ~= nil then
				QueueRefresh()
			elseif UnitIsGameObject then
				local isObj = UnitIsGameObject("softinteract")
				if not issecretvalue(isObj) and isObj == true then
					QueueRefresh()
				end
			end
		else
			QueueRefresh()
		end
	end)
	state.watcher = w
	SyncWatcherEvents()
	if ns.IsNodeShimmerOn() then
		EnsureSoftTargetIconHook()
		SyncSoftTargetCVars()
		RefreshAllSoftTargetIcons()
		QueueRefresh()
	elseif ns.db and type(ns.db.nodeShimmerSavedCVars) == "table" then
		SyncSoftTargetCVars()
	end
end
