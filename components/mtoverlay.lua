-- amptieRaidTools – MT Overlay (mtoverlay.lua)
-- Floating health-bar frames for Main Tanks, draggable
-- Vanilla 1.12 / Lua 5.0 / TurtleWoW / SuperWoW

local getn    = table.getn
local tinsert = table.insert
local floor   = math.floor
local mmod    = math.mod
local mmax    = math.max
local mmin    = math.min
local GetTime = GetTime

local NUM_MT_SLOTS = 8
local HANDLE_H     = 12   -- drag handle height when unlocked

local CLASS_COLORS = {
	WARRIOR  = { 0.78, 0.61, 0.43 },
	PALADIN  = { 0.96, 0.55, 0.73 },
	HUNTER   = { 0.67, 0.83, 0.45 },
	ROGUE    = { 1.00, 0.96, 0.41 },
	PRIEST   = { 1.00, 1.00, 1.00 },
	SHAMAN   = { 0.00, 0.44, 0.87 },
	MAGE     = { 0.41, 0.80, 0.94 },
	WARLOCK  = { 0.58, 0.51, 0.79 },
	DRUID    = { 1.00, 0.49, 0.04 },
}

local function GetOvlDB()
	if not amptieRaidToolsDB then return nil end
	local db = amptieRaidToolsDB
	if not db.raidAssists then db.raidAssists = {} end
	local ra = db.raidAssists
	if not ra.mtOverlay then
		ra.mtOverlay = {
			shown      = false,
			locked     = true,
			frameW     = 120,
			frameH     = 36,
			cols       = 4,
			spacing    = 4,
			classColor = false,
			point      = "CENTER",
			x          = 0,
			y          = 0,
		}
	end
	if ra.mtOverlay.locked == nil then ra.mtOverlay.locked = true end
	return ra.mtOverlay
end

local function GetUnitForName(name)
	if not name or name == "" then return nil end
	local numRaid = GetNumRaidMembers()
	if numRaid > 0 then
		for i = 1, numRaid do
			if UnitName("raid" .. i) == name then
				return "raid" .. i
			end
		end
	end
	local numParty = GetNumPartyMembers()
	for i = 0, numParty do
		local u = (i == 0) and "player" or ("party" .. i)
		if UnitName(u) == name then return u end
	end
	return nil
end

local function GetHPColor(unit)
	local cur = UnitHealth(unit)    or 0
	local max = UnitHealthMax(unit) or 1
	if max == 0 then max = 1 end
	local pct = cur / max
	if pct > 0.5 then
		local t = (pct - 0.5) * 2
		return 1 - t, 1, 0
	else
		local t = pct * 2
		return 1, t, 0
	end
end

local ovlFrame    = nil
local dragHandle  = nil
local mtFrames    = {}
local updateTimer = 0
local UPDATE_INTERVAL = 0.1

local function GetMTNames()
	if not amptieRaidToolsDB or not amptieRaidToolsDB.raidAssists then return {} end
	return amptieRaidToolsDB.raidAssists.mainTanks or {}
end

local function LayoutOverlay()
	local db = GetOvlDB()
	if not db or not ovlFrame then return end
	local fw   = db.frameW  or 120
	local fh   = db.frameH  or 36
	local sp   = db.spacing or 4
	local cols = db.cols    or 4
	if cols < 1 then cols = 1 end
	if cols > NUM_MT_SLOTS then cols = NUM_MT_SLOTS end

	local locked  = (db.locked ~= false)   -- default true
	local handleH = locked and 0 or HANDLE_H

	-- show/hide drag handle
	if dragHandle then
		if locked then
			dragHandle:Hide()
		else
			dragHandle:Show()
		end
	end

	-- count only non-empty MT slots
	local mts    = GetMTNames()
	local active = {}
	for i = 1, NUM_MT_SLOTS do
		if mts[i] and mts[i] ~= "" then
			tinsert(active, i)
		end
	end
	local count = getn(active)
	if count == 0 then count = 1 end

	local usedCols = mmin(count, cols)
	local rows     = floor((count - 1) / cols) + 1
	local gridW    = usedCols * fw + (usedCols - 1) * sp
	local gridH    = rows     * fh + (rows     - 1) * sp

	ovlFrame:SetWidth( gridW)
	ovlFrame:SetHeight(gridH + handleH)

	-- stretch handle to full grid width
	if dragHandle then
		dragHandle:SetWidth(gridW)
	end

	-- position each active frame below the handle; hide the rest
	local slot = 0
	for i = 1, NUM_MT_SLOTS do
		local f = mtFrames[i]
		if not f then break end
		if mts[i] and mts[i] ~= "" then
			f:SetWidth(fw)
			f:SetHeight(fh)
			local col = mmod(slot, cols)
			local row = floor(slot / cols)
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", ovlFrame, "TOPLEFT",
				col * (fw + sp),
				-(row * (fh + sp)) - handleH)
			slot = slot + 1
		else
			f:ClearAllPoints()
		end
	end
end

local function UpdateOverlay()
	if not ovlFrame or not ovlFrame:IsShown() then return end
	local db = GetOvlDB()
	if not db then return end
	local mts = GetMTNames()
	for i = 1, NUM_MT_SLOTS do
		local f = mtFrames[i]
		if not f then break end
		local name = mts[i] or ""
		if name == "" then
			f:Hide()
		else
			f:Show()
			local unit = GetUnitForName(name)
			f.unit = unit
			f.nameText:SetText(name)
			if unit then
				local cur  = UnitHealth(unit)    or 0
				local maxH = UnitHealthMax(unit)  or 1
				if maxH == 0 then maxH = 1 end
				f.bar:SetMinMaxValues(0, maxH)
				f.bar:SetValue(cur)
				if UnitIsDead(unit) then
					f.bar:SetStatusBarColor(0.45, 0.45, 0.45, 1)
					f.hpText:SetText("Dead")
				else
					if db.classColor then
						local _, cls = UnitClass(unit)
						local c = cls and CLASS_COLORS[cls]
						if c then
							f.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
						else
							f.bar:SetStatusBarColor(0, 0.8, 0, 1)
						end
					else
						local r, g, b = GetHPColor(unit)
						f.bar:SetStatusBarColor(r, g, b, 1)
					end
					local pct = floor(cur / maxH * 100 + 0.5)
					f.hpText:SetText(pct .. "%")
				end
			else
				f.bar:SetMinMaxValues(0, 1)
				f.bar:SetValue(0)
				f.bar:SetStatusBarColor(0.3, 0.3, 0.3, 1)
				f.hpText:SetText("---")
			end
		end
	end
end

function AmptieRaidTools_InitMTOverlay()
	local db = GetOvlDB()

	ovlFrame = CreateFrame("Frame", "ART_MTOverlay", UIParent)
	ovlFrame:SetFrameStrata("MEDIUM")
	ovlFrame:SetClampedToScreen(true)
	ovlFrame:SetMovable(true)

	ovlFrame:SetScript("OnUpdate", function()
		local dt = arg1
		if not dt or dt < 0 then dt = 0 end
		updateTimer = updateTimer + dt
		if updateTimer >= UPDATE_INTERVAL then
			updateTimer = 0
			UpdateOverlay()
		end
	end)

	-- Drag handle (visible only when unlocked)
	dragHandle = CreateFrame("Frame", nil, ovlFrame)
	dragHandle:SetHeight(HANDLE_H)
	dragHandle:SetPoint("TOPLEFT", ovlFrame, "TOPLEFT", 0, 0)
	dragHandle:EnableMouse(true)
	dragHandle:RegisterForDrag("LeftButton")

	local handleBg = dragHandle:CreateTexture(nil, "BACKGROUND")
	handleBg:SetAllPoints(dragHandle)
	handleBg:SetTexture(0.15, 0.15, 0.18, 0.85)

	local handleLabel = dragHandle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	handleLabel:SetPoint("CENTER", dragHandle, "CENTER", 0, 0)
	handleLabel:SetText("- - - - -")
	handleLabel:SetTextColor(0.55, 0.55, 0.55, 1)

	dragHandle:SetScript("OnDragStart", function()
		ovlFrame:StartMoving()
	end)
	dragHandle:SetScript("OnDragStop", function()
		ovlFrame:StopMovingOrSizing()
		local pt, _, _, ox, oy = ovlFrame:GetPoint()
		local oDb = GetOvlDB()
		if oDb then oDb.point = pt; oDb.x = ox; oDb.y = oy end
	end)
	dragHandle:Hide()

	-- MT health-bar frames
	for i = 1, NUM_MT_SLOTS do
		local f = CreateFrame("Frame", nil, ovlFrame)
		f:SetWidth(120)
		f:SetHeight(36)
		f.unit = nil
		f:EnableMouse(true)

		local barBg = f:CreateTexture(nil, "BACKGROUND")
		barBg:SetAllPoints(f)
		barBg:SetTexture(0.05, 0.05, 0.05, 1)

		local bar = CreateFrame("StatusBar", nil, f)
		bar:SetPoint("TOPLEFT",     f, "TOPLEFT",     1, -1)
		bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1,  1)
		bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		bar:SetMinMaxValues(0, 100)
		bar:SetValue(100)
		bar:SetStatusBarColor(0, 0.8, 0, 1)
		f.bar = bar

		local nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		nameText:SetPoint("LEFT", bar, "LEFT", 4, 1)
		nameText:SetJustifyH("LEFT")
		nameText:SetTextColor(1, 1, 1, 1)
		nameText:SetShadowOffset(1, -1)
		f.nameText = nameText

		local hpText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		hpText:SetPoint("RIGHT", bar, "RIGHT", -4, 1)
		hpText:SetJustifyH("RIGHT")
		hpText:SetTextColor(1, 1, 1, 1)
		hpText:SetShadowOffset(1, -1)
		f.hpText = hpText

		f:SetScript("OnEnter", function()
			if this.unit then
				GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
				GameTooltip:SetUnit(this.unit)
				GameTooltip:Show()
			end
		end)
		f:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		f:SetScript("OnMouseDown", function()
			if this.unit and arg1 == "LeftButton" then
				TargetUnit(this.unit)
			end
		end)

		f:Hide()
		mtFrames[i] = f
	end

	if db then
		ovlFrame:SetPoint(db.point or "CENTER", UIParent, db.point or "CENTER", db.x or 0, db.y or 0)
		if db.shown then ovlFrame:Show() else ovlFrame:Hide() end
	else
		ovlFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		ovlFrame:Hide()
	end

	LayoutOverlay()
	UpdateOverlay()
end

function AmptieRaidTools_SetMTOverlayShown(show)
	local db = GetOvlDB()
	if db then db.shown = show end
	if not ovlFrame then return end
	if show then
		LayoutOverlay()
		UpdateOverlay()
		ovlFrame:Show()
	else
		ovlFrame:Hide()
	end
end

function AmptieRaidTools_SetMTOverlayLocked(locked)
	local db = GetOvlDB()
	if db then db.locked = locked end
	LayoutOverlay()
end

function AmptieRaidTools_RefreshMTOverlayLayout()
	LayoutOverlay()
	UpdateOverlay()
end

function AmptieRaidTools_UpdateMTOverlay()
	if not ovlFrame then return end
	LayoutOverlay()
	UpdateOverlay()
end

local ART_MT_GroupEvt = CreateFrame("Frame", "ART_MT_GroupEvt", UIParent)
ART_MT_GroupEvt:RegisterEvent("RAID_ROSTER_UPDATE")
ART_MT_GroupEvt:RegisterEvent("PARTY_MEMBERS_CHANGED")
ART_MT_GroupEvt:RegisterEvent("PLAYER_LOGIN")
ART_MT_GroupEvt:RegisterEvent("PLAYER_ENTERING_WORLD")
ART_MT_GroupEvt:SetScript("OnEvent", function()
	if GetNumRaidMembers() == 0 then
		if ovlFrame then ovlFrame:Hide() end
	end
end)
