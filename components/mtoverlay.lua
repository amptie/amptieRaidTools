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
			shown       = false,
			locked      = true,
			frameW      = 120,
			frameH      = 36,
			cols        = 4,
			spacing     = 4,
			classColor  = false,
			showTargets = false,
			targetW     = 80,
			point       = "CENTER",
			x           = 0,
			y           = 0,
		}
	end
	if ra.mtOverlay.locked           == nil then ra.mtOverlay.locked           = true  end
	if ra.mtOverlay.showTargets      == nil then ra.mtOverlay.showTargets      = false  end
	if ra.mtOverlay.targetW          == nil then ra.mtOverlay.targetW          = 80    end
	if ra.mtOverlay.targetClassColor == nil then ra.mtOverlay.targetClassColor = false  end
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
local tgtFrames   = {}   -- target frames parallel to mtFrames
local updateTimer = 0
local UPDATE_INTERVAL = 0.1

local function GetMTNames()
	if not amptieRaidToolsDB or not amptieRaidToolsDB.raidAssists then return {} end
	return amptieRaidToolsDB.raidAssists.mainTanks or {}
end

local function LayoutOverlay()
	local db = GetOvlDB()
	if not db or not ovlFrame then return end
	local fw          = db.frameW      or 120
	local fh          = db.frameH      or 36
	local sp          = db.spacing     or 4
	local cols        = db.cols        or 4
	local showTargets = db.showTargets or false
	local tw          = db.targetW     or 80
	if cols < 1 then cols = 1 end
	if cols > NUM_MT_SLOTS then cols = NUM_MT_SLOTS end

	-- block width: MT frame + (optional) target frame side-by-side
	local blockW = showTargets and (fw + sp + tw) or fw

	local locked  = (db.locked ~= false)

	if dragHandle then
		if locked then
			dragHandle:Hide()
		else
			dragHandle:Show()
		end
	end

	local mts    = GetMTNames()
	local active = {}
	for i = 1, NUM_MT_SLOTS do
		if mts[i] and mts[i] ~= "" then tinsert(active, i) end
	end
	local count = getn(active)
	if count == 0 then count = 1 end

	local usedCols = mmin(count, cols)
	local rows     = floor((count - 1) / cols) + 1
	local gridW    = usedCols * blockW + (usedCols - 1) * sp
	local gridH    = rows     * fh     + (rows     - 1) * sp

	-- ovlFrame covers only the MT bars — handle sits above it, not inside it
	ovlFrame:SetWidth( gridW)
	ovlFrame:SetHeight(gridH)

	-- drag handle floats above ovlFrame (no offset baked into bar positions)
	if dragHandle then
		dragHandle:SetWidth(gridW)
		dragHandle:ClearAllPoints()
		dragHandle:SetPoint("BOTTOMLEFT", ovlFrame, "TOPLEFT", 0, 0)
	end

	local slot = 0
	for i = 1, NUM_MT_SLOTS do
		local f  = mtFrames[i]
		local tf = tgtFrames[i]
		if not f then break end
		if mts[i] and mts[i] ~= "" then
			local col = mmod(slot, cols)
			local row = floor(slot / cols)
			local bx  = col * (blockW + sp)
			local by  = -(row * (fh + sp))

			f:SetWidth(fw)
			f:SetHeight(fh)
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", ovlFrame, "TOPLEFT", bx, by)

			if tf then
				if showTargets then
					tf:SetWidth(tw)
					tf:SetHeight(fh)
					tf:ClearAllPoints()
					tf:SetPoint("TOPLEFT", ovlFrame, "TOPLEFT", bx + fw + sp, by)
					tf:Show()
				else
					tf:ClearAllPoints()
					tf:Hide()
				end
			end
			slot = slot + 1
		else
			f:ClearAllPoints()
			if tf then tf:ClearAllPoints(); tf:Hide() end
		end
	end
end

local function UpdateUnitFrame(f, unit, useClassColor)
	if not unit or not UnitExists(unit) then
		f.bar:SetMinMaxValues(0, 1)
		f.bar:SetValue(0)
		f.bar:SetStatusBarColor(0.3, 0.3, 0.3, 1)
		f.hpText:SetText("---")
		return
	end
	local cur  = UnitHealth(unit)    or 0
	local maxH = UnitHealthMax(unit) or 1
	if maxH == 0 then maxH = 1 end
	f.bar:SetMinMaxValues(0, maxH)
	f.bar:SetValue(cur)
	if UnitIsDead(unit) then
		f.bar:SetStatusBarColor(0.45, 0.45, 0.45, 1)
		f.hpText:SetText("Dead")
	else
		if useClassColor then
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
end

-- Truncates f.nameText so it never overlaps f.hpText.
-- Must be called AFTER UpdateUnitFrame (which sets hpText).
local function TruncateName(f, fullName)
	local barW = f.bar:GetWidth()
	if barW <= 0 then
		f.nameText:SetText(fullName)
		return
	end
	local hpW  = f.hpText:GetStringWidth()
	-- Anchors already provide 4px padding each side; allow name to use that space
	local avail = barW - hpW + 3
	if avail <= 0 then
		f.nameText:SetText("")
		return
	end
	f.nameText:SetText(fullName)
	if f.nameText:GetStringWidth() <= avail then return end
	-- Trim one character at a time from the right, append "."
	local len = string.len(fullName)
	while len > 1 do
		len = len - 1
		f.nameText:SetText(string.sub(fullName, 1, len) .. ".")
		if f.nameText:GetStringWidth() <= avail then return end
	end
	f.nameText:SetText("")
end

local function UpdateOverlay()
	if not ovlFrame or not ovlFrame:IsShown() then return end
	local db = GetOvlDB()
	if not db then return end
	local mts            = GetMTNames()
	local showTargets    = db.showTargets      or false
	local useClassCol    = db.classColor       or false
	local useTgtClassCol = db.targetClassColor or false

	for i = 1, NUM_MT_SLOTS do
		local f  = mtFrames[i]
		local tf = tgtFrames[i]
		if not f then break end
		local name = mts[i] or ""
		if name == "" then
			f:Hide()
			if tf then tf:Hide() end
		else
			f:Show()
			local unit = GetUnitForName(name)
			f.unit = unit
			UpdateUnitFrame(f, unit, useClassCol)
			TruncateName(f, name)

			if tf and showTargets then
				local tunit = unit and (unit .. "target") or nil
				if tunit and UnitExists(tunit) then
					tf:Show()
					tf.unit = tunit
					local tname = UnitName(tunit) or ""
					if useTgtClassCol then
						UpdateUnitFrame(tf, tunit, true)
					else
						-- reaction-based coloring for enemy targets
						local cur  = UnitHealth(tunit)    or 0
						local maxH = UnitHealthMax(tunit) or 1
						if maxH == 0 then maxH = 1 end
						tf.bar:SetMinMaxValues(0, maxH)
						tf.bar:SetValue(cur)
						if UnitIsDead(tunit) then
							tf.bar:SetStatusBarColor(0.45, 0.45, 0.45, 1)
							tf.hpText:SetText("Dead")
						else
							local reaction = UnitReaction(tunit, "player") or 4
							local r, g, b
							if reaction <= 2 then
								r, g, b = 0.9, 0.1, 0.1   -- hostile: red
							elseif reaction <= 4 then
								r, g, b = 0.9, 0.8, 0.1   -- neutral: yellow
							else
								r, g, b = 0.1, 0.8, 0.1   -- friendly: green
							end
							tf.bar:SetStatusBarColor(r, g, b, 1)
							local pct = floor(cur / maxH * 100 + 0.5)
							tf.hpText:SetText(pct .. "%")
						end
					end
					TruncateName(tf, tname)
					-- Raid mark icon
					if tf.raidMark then
						local markIdx = GetRaidTargetIndex(tunit)
						if markIdx then
							SetRaidTargetIconTexture(tf.raidMark, markIdx)
							tf.raidMark:Show()
						else
							tf.raidMark:Hide()
						end
					end
				else
					tf:Hide()
				end
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

	-- Drag handle: floats above ovlFrame as a separate UIParent child.
	-- This way its height is never included in ovlFrame's bounds,
	-- so locking/unlocking does not shift the MT bar positions.
	dragHandle = CreateFrame("Frame", nil, UIParent)
	dragHandle:SetFrameStrata("MEDIUM")
	dragHandle:SetHeight(HANDLE_H)
	dragHandle:SetPoint("BOTTOMLEFT", ovlFrame, "TOPLEFT", 0, 0)
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

	-- Target frames (one per MT slot, shown only when showTargets is enabled)
	for i = 1, NUM_MT_SLOTS do
		local f = CreateFrame("Frame", nil, ovlFrame)
		f:SetWidth(80)
		f:SetHeight(36)
		f.unit = nil
		f:EnableMouse(true)

		local barBg = f:CreateTexture(nil, "BACKGROUND")
		barBg:SetAllPoints(f)
		barBg:SetTexture(0.05, 0.05, 0.08, 1)

		local bar = CreateFrame("StatusBar", nil, f)
		bar:SetPoint("TOPLEFT",     f, "TOPLEFT",     1, -1)
		bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1,  1)
		bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		bar:SetMinMaxValues(0, 100)
		bar:SetValue(0)
		bar:SetStatusBarColor(0.3, 0.3, 0.3, 1)
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

		-- Raid mark icon centered over the bar text (must be on bar, not f, to render above the StatusBar frame)
		local raidMark = bar:CreateTexture(nil, "OVERLAY")
		raidMark:SetWidth(13)
		raidMark:SetHeight(13)
		raidMark:SetPoint("TOP", bar, "TOP", 0, 0)
		raidMark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
		raidMark:Hide()
		f.raidMark = raidMark

		f:SetScript("OnEnter", function()
			if this.unit and UnitExists(this.unit) then
				GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
				GameTooltip:SetUnit(this.unit)
				GameTooltip:Show()
			end
		end)
		f:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		f:SetScript("OnMouseDown", function()
			if this.unit and arg1 == "LeftButton" and UnitExists(this.unit) then
				TargetUnit(this.unit)
			end
		end)

		f:Hide()
		tgtFrames[i] = f
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
ART_MT_GroupEvt:RegisterEvent("RAID_TARGET_UPDATE")
ART_MT_GroupEvt:SetScript("OnEvent", function()
	local evt = event
	if evt == "RAID_TARGET_UPDATE" then
		UpdateOverlay()
		return
	end
	if GetNumRaidMembers() == 0 then
		if ovlFrame then ovlFrame:Hide() end
	else
		local db = GetOvlDB()
		if ovlFrame and db and db.shown then
			LayoutOverlay()
			UpdateOverlay()
			ovlFrame:Show()
		end
	end
end)
