-- components/raidsetups.lua
-- Raid Setups — save and apply raid group compositions
-- Vanilla 1.12 / Lua 5.0 / TurtleWoW

local getn    = table.getn
local tinsert = table.insert
local floor   = math.floor

local NUM_GROUPS = 8
local NUM_SLOTS  = 5

local groupEBs  = {}   -- groupEBs[g][s] = EditBox
local groupHdrs = {}   -- groupHdrs[g]   = FontString header
local tagBtns   = {}   -- tagBtns[g][s]  = Button (locked-name display + drag source)
local dragSource = nil -- { g=int, s=int } while a drag is in progress

-- ============================================================
-- DB helpers
-- ============================================================
local function GetDB()
	if not amptieRaidToolsDB then return nil end
	if not amptieRaidToolsDB.raidSetups then
		amptieRaidToolsDB.raidSetups = { profiles = {} }
	end
	if not amptieRaidToolsDB.raidSetups.profiles then
		amptieRaidToolsDB.raidSetups.profiles = {}
	end
	return amptieRaidToolsDB.raidSetups
end

local function FindProfile(name)
	local db = GetDB()
	if not db then return nil, nil end
	for i = 1, getn(db.profiles) do
		if db.profiles[i].name == name then
			return i, db.profiles[i]
		end
	end
	return nil, nil
end

local function GetCurrentGroups()
	local groups = {}
	for g = 1, NUM_GROUPS do
		groups[g] = {}
		for s = 1, NUM_SLOTS do
			local eb = groupEBs[g] and groupEBs[g][s]
			groups[g][s] = (eb and eb:GetText()) or ""
		end
	end
	return groups
end

local function LoadProfileIntoUI(profile)
	if not profile then return end
	for g = 1, NUM_GROUPS do
		for s = 1, NUM_SLOTS do
			local eb = groupEBs[g] and groupEBs[g][s]
			if eb then
				local name = profile.groups and profile.groups[g] and profile.groups[g][s] or ""
				eb:SetText(name)
			end
		end
	end
end

-- Returns uppercase class token for a player name from the current raid/party, or nil.
local function GetRaidMemberClass(name)
	if not name or name == "" then return nil end
	local numRaid = GetNumRaidMembers()
	if numRaid > 0 then
		for i = 1, numRaid do
			if UnitName("raid" .. i) == name then
				local _, cl = UnitClass("raid" .. i)
				return cl and string.upper(cl) or nil
			end
		end
	else
		local me = UnitName("player")
		if me == name then
			local _, cl = UnitClass("player")
			return cl and string.upper(cl) or nil
		end
		local numParty = GetNumPartyMembers()
		for i = 1, numParty do
			if UnitName("party" .. i) == name then
				local _, cl = UnitClass("party" .. i)
				return cl and string.upper(cl) or nil
			end
		end
	end
	return nil
end

-- Apply backdrop + text color to a tagBtn based on player name.
-- Class color if found in group, red if in a group but not found, neutral if solo.
local function ApplyTagColors(tag, name)
	local inGroup = GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
	local cl = GetRaidMemberClass(name)
	local cc = cl and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cl]
	if cc then
		-- Class color: darkened for bg, medium for border, full for text
		tag:SetBackdropColor(cc.r * 0.18, cc.g * 0.18, cc.b * 0.18, 0.95)
		tag:SetBackdropBorderColor(cc.r * 0.55, cc.g * 0.55, cc.b * 0.55, 1)
		tag.tagLabel:SetTextColor(cc.r, cc.g, cc.b, 1)
	elseif inGroup then
		-- Name not in group → red
		tag:SetBackdropColor(0.22, 0.04, 0.04, 0.95)
		tag:SetBackdropBorderColor(0.65, 0.15, 0.15, 1)
		tag.tagLabel:SetTextColor(1.0, 0.45, 0.45, 1)
	else
		-- Solo: neutral slate
		tag:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
		tag:SetBackdropBorderColor(0.35, 0.35, 0.40, 1)
		tag.tagLabel:SetTextColor(0.85, 0.85, 0.85, 1)
	end
end

-- Slot visual: show tagBtn (locked) when EB has text, show EB (editable) when empty.
-- Only affects currently shown frames — scrolled-out slots stay hidden.
local function RefreshSlotVisual(g, s)
	local eb  = groupEBs[g] and groupEBs[g][s]
	local tag = tagBtns[g]  and tagBtns[g][s]
	if not eb then return end
	local name = eb:GetText()
	local locked = name and name ~= ""
	if tag then
		if locked then
			tag.tagLabel:SetText(name)
			ApplyTagColors(tag, name)
			tag:Show()
			eb:Hide()
		else
			tag:Hide()
			eb:Show()
		end
	else
		eb:Show()
	end
end

-- Swap text between two slots and refresh their visuals.
local function SwapSlots(g1, s1, g2, s2)
	local eb1 = groupEBs[g1] and groupEBs[g1][s1]
	local eb2 = groupEBs[g2] and groupEBs[g2][s2]
	if not eb1 or not eb2 then return end
	local t1 = eb1:GetText()
	local t2 = eb2:GetText()
	eb1:SetText(t2)
	eb2:SetText(t1)
	RefreshSlotVisual(g1, s1)
	RefreshSlotVisual(g2, s2)
end

-- ============================================================
-- Apply setup to actual raid
-- oRA2-inspired: SetRaidSubgroup when group has space,
-- SwapRaidSubgroup when full, max 14 actions/pass, retry every 1s
-- ============================================================
local applyTargetGroup  = {}   -- name -> desired subgroup
local applyActive       = false
local applyRetries      = 0
local applyTimer        = 0
local MAX_APPLY_RETRIES = 10
local MAX_ACTIONS_PASS  = 14

local function GetSelfRank()
	local selfName = UnitName("player")
	for i = 1, GetNumRaidMembers() do
		local name, rank = GetRaidRosterInfo(i)
		if name == selfName then return rank end
	end
	return 0
end

-- One pass: move up to MAX_ACTIONS_PASS players towards their target group.
-- Returns number of moves issued.
local function DoApplyPass()
	-- Snapshot current roster (indices matter for the API)
	local rosterByIdx = {}
	local groupCount  = {}
	for g = 1, NUM_GROUPS do groupCount[g] = 0 end
	for i = 1, GetNumRaidMembers() do
		local name, _, subgroup = GetRaidRosterInfo(i)
		if name then
			rosterByIdx[i] = { name = name, group = subgroup }
			groupCount[subgroup] = (groupCount[subgroup] or 0) + 1
		end
	end

	local actions = 0
	for i = 1, GetNumRaidMembers() do
		if actions >= MAX_ACTIONS_PASS then break end
		local info = rosterByIdx[i]
		if info then
			local tg = applyTargetGroup[info.name]
			if tg and info.group ~= tg then
				if groupCount[tg] < 5 then
					-- Target group has room — move directly
					groupCount[info.group] = groupCount[info.group] - 1
					groupCount[tg]         = groupCount[tg] + 1
					rosterByIdx[i].group   = tg
					SetRaidSubgroup(i, tg)
					actions = actions + 1
				else
					-- Target group full — find a swap candidate:
					-- someone in tg whose own target is NOT tg (or unknown)
					for j = 1, GetNumRaidMembers() do
						local jinfo = rosterByIdx[j]
						if jinfo and j ~= i and jinfo.group == tg then
							local jTarget = applyTargetGroup[jinfo.name]
							if not jTarget or jTarget ~= tg then
								local oldGroup     = info.group
								rosterByIdx[i].group = tg
								rosterByIdx[j].group = oldGroup
								SwapRaidSubgroup(i, j)
								actions = actions + 1
								break
							end
						end
					end
				end
			end
		end
	end
	return actions
end

-- Check whether every player that has a target is already in it
local function ApplyIsComplete()
	for i = 1, GetNumRaidMembers() do
		local name, _, subgroup = GetRaidRosterInfo(i)
		if name then
			local tg = applyTargetGroup[name]
			if tg and subgroup ~= tg then return false end
		end
	end
	return true
end

local applyFrame = CreateFrame("Frame", "ART_RS_ApplyFrame", UIParent)
applyFrame:SetScript("OnUpdate", function()
	if not applyActive then return end
	local dt = arg1
	if not dt or dt < 0 then dt = 0 end
	applyTimer = applyTimer + dt
	if applyTimer < 1.0 then return end
	applyTimer = 0

	if ApplyIsComplete() then
		applyActive = false
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Setup applied successfully.")
		return
	end

	applyRetries = applyRetries + 1
	if applyRetries >= MAX_APPLY_RETRIES then
		applyActive = false
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Apply finished (some players could not be moved).")
		return
	end

	DoApplyPass()
end)

local function ApplySetupToRaid()
	if GetNumRaidMembers() == 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Not in a raid.")
		return
	end
	if GetSelfRank() < 1 then
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Raid leader or officer required.")
		return
	end

	-- Build target map from UI EditBoxes
	for k in pairs(applyTargetGroup) do applyTargetGroup[k] = nil end
	for g = 1, NUM_GROUPS do
		for s = 1, NUM_SLOTS do
			local eb   = groupEBs[g] and groupEBs[g][s]
			local name = eb and eb:GetText() or ""
			if name ~= "" then
				applyTargetGroup[name] = g
			end
		end
	end

	applyActive  = true
	applyRetries = 0
	applyTimer   = 0
	DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Applying setup...")
	DoApplyPass()
end

-- ============================================================
-- Panel
-- ============================================================
function AmptieRaidTools_InitRaidSetups(body)
	local panel = CreateFrame("Frame", "ART_RS_Panel", body)
	panel:SetAllPoints(body)

	local BD = {
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	}
	local EB_BD = {
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 10,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	}

	-- ── Helper: styled button ──────────────────────────────────
	local function MakeBtn(label, w)
		local btn = CreateFrame("Button", nil, panel)
		btn:SetWidth(w or 60)
		btn:SetHeight(22)
		btn:SetBackdrop(BD)
		btn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
		btn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
		btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
		fs:SetText(label)
		btn.fs = fs
		return btn
	end

	-- ── Title ──────────────────────────────────────────────────
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
	title:SetText("Raid Setups")
	title:SetTextColor(1, 0.82, 0, 1)

	-- ── Profile EditBox ────────────────────────────────────────
	local profileEdit = CreateFrame("EditBox", "ART_RS_ProfileEdit", panel)
	profileEdit:SetWidth(150)
	profileEdit:SetHeight(22)
	profileEdit:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	profileEdit:SetFontObject(GameFontHighlight)
	profileEdit:SetTextInsets(6, 6, 0, 0)
	profileEdit:SetBackdrop(EB_BD)
	profileEdit:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
	profileEdit:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
	profileEdit:SetScript("OnEditFocusGained", function() this:SetBackdropBorderColor(1, 0.82, 0, 0.8) end)
	profileEdit:SetScript("OnEditFocusLost",   function() this:SetBackdropBorderColor(0.35, 0.35, 0.4, 1) end)
	profileEdit:SetScript("OnEscapePressed",   function() this:ClearFocus() end)
	profileEdit:SetAutoFocus(false)

	-- ── Buttons ────────────────────────────────────────────────
	local saveBtn  = MakeBtn("Save",          56)
	local delBtn   = MakeBtn("Delete",        56)
	local applyBtn = MakeBtn("Apply to Raid", 100)
	local ddBtn    = MakeBtn("Load Profile v",155)

	saveBtn:SetPoint( "LEFT", profileEdit, "RIGHT",  4, 0)
	delBtn:SetPoint(  "LEFT", saveBtn,     "RIGHT",  4, 0)
	applyBtn:SetPoint("LEFT", delBtn,      "RIGHT",  4, 0)
	ddBtn:SetPoint(   "LEFT", applyBtn,    "RIGHT",  4, 0)
	-- Left-align the dropdown button label
	ddBtn.fs:ClearAllPoints()
	ddBtn.fs:SetPoint("LEFT",  ddBtn, "LEFT",   8, 0)
	ddBtn.fs:SetPoint("RIGHT", ddBtn, "RIGHT", -8, 0)
	ddBtn.fs:SetJustifyH("LEFT")

	-- ── Profile dropdown ───────────────────────────────────────
	local ddFrame = CreateFrame("Frame", "ART_RS_DDFrame", UIParent)
	ddFrame:SetFrameStrata("TOOLTIP")
	ddFrame:SetWidth(155)
	ddFrame:SetBackdrop({
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 10,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	ddFrame:SetBackdropColor(0.08, 0.08, 0.11, 0.97)
	ddFrame:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
	ddFrame:Hide()

	local ddItemPool = {}

	local function RefreshDropdown()
		for i = 1, getn(ddItemPool) do ddItemPool[i]:Hide() end
		local db    = GetDB()
		local profs = (db and db.profiles) or {}
		local n     = getn(profs)
		local itemH = 22
		ddFrame:SetHeight(math.max(n, 1) * itemH + 6)
		for i = 1, n do
			local item = ddItemPool[i]
			if not item then
				item = CreateFrame("Button", nil, ddFrame)
				item:SetHeight(itemH)
				item:SetBackdrop({
					bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
					tile = true, tileSize = 16, edgeSize = 0,
					insets = { left=0, right=0, top=0, bottom=0 },
				})
				item:SetBackdropColor(0, 0, 0, 0)
				local iLbl = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				iLbl:SetPoint("LEFT", item, "LEFT", 6, 0)
				iLbl:SetTextColor(0.85, 0.85, 0.85, 1)
				item.iLbl = iLbl
				item:SetScript("OnEnter", function() this:SetBackdropColor(0.22, 0.22, 0.28, 0.9) end)
				item:SetScript("OnLeave", function() this:SetBackdropColor(0, 0, 0, 0) end)
				ddItemPool[i] = item
			end
			item:ClearAllPoints()
			item:SetPoint("TOPLEFT",  ddFrame, "TOPLEFT",   4, -3 - (i-1)*itemH)
			item:SetPoint("TOPRIGHT", ddFrame, "TOPRIGHT",  -4, -3 - (i-1)*itemH)
			local prof = profs[i]
			item.iLbl:SetText(prof.name)
			local profRef = prof
			item:SetScript("OnClick", function()
				profileEdit:SetText(profRef.name)
				LoadProfileIntoUI(profRef)
				ddFrame:Hide()
			end)
			item:Show()
		end
	end

	ddBtn:SetScript("OnClick", function()
		if ddFrame:IsShown() then
			ddFrame:Hide()
		else
			RefreshDropdown()
			ddFrame:ClearAllPoints()
			ddFrame:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
			ddFrame:Show()
		end
	end)

	saveBtn:SetScript("OnClick", function()
		local name = profileEdit:GetText()
		if not name or name == "" then return end
		local db = GetDB()
		if not db then return end
		local idx, existing = FindProfile(name)
		local grps = GetCurrentGroups()
		if existing then
			existing.groups = grps
		else
			tinsert(db.profiles, { name = name, groups = grps })
		end
	end)

	delBtn:SetScript("OnClick", function()
		local name = profileEdit:GetText()
		if not name or name == "" then return end
		local idx = FindProfile(name)
		if idx then table.remove(GetDB().profiles, idx) end
		profileEdit:SetText("")
		for g = 1, NUM_GROUPS do
			for s = 1, NUM_SLOTS do
				local eb  = groupEBs[g] and groupEBs[g][s]
				local tag = tagBtns[g]  and tagBtns[g][s]
				if eb then eb:SetText("") end
				-- Unlock any visible locked slots (scrolled-out slots stay hidden)
				if tag and tag:IsShown() then
					tag:Hide()
					if eb then eb:Show() end
				end
			end
		end
	end)

	applyBtn:SetScript("OnClick", function()
		ApplySetupToRaid()
	end)

	-- ── Clear All / Load Current / Current Export — title row, right side ──
	local currentExportBtn = MakeBtn("Current Export", 114)
	local loadCurrentBtn   = MakeBtn("Load Current",   110)
	local clearAllBtn      = MakeBtn("Clear All",       80)
	currentExportBtn.fs:SetTextColor(0.7, 1, 0.7, 1)
	currentExportBtn:SetPoint("TOPRIGHT", panel,           "TOPRIGHT", -6,  -8)
	loadCurrentBtn:SetPoint(  "RIGHT",    currentExportBtn, "LEFT",    -4,   0)
	clearAllBtn:SetPoint(     "RIGHT",    loadCurrentBtn,   "LEFT",    -4,   0)

	-- ── Separator ─────────────────────────────────────────────
	local topSep = panel:CreateTexture(nil, "ARTWORK")
	topSep:SetHeight(1)
	topSep:SetTexture(0.35, 0.35, 0.4, 0.5)
	topSep:SetPoint("TOPLEFT",  profileEdit, "BOTTOMLEFT",  0, -6)
	topSep:SetPoint("TOPRIGHT", panel,       "TOPRIGHT", -10,  0)

	-- ── Clip frame + content + slider (no ScrollFrame API needed) ─
	local COL_W     = 230
	local COL_GAP   = 12
	local XPAD      = 4
	local GRP_HDR_H = 14
	local SLOT_H    = 18
	local GRP_GAP   = 6
	local GRP_H     = GRP_HDR_H + NUM_SLOTS * SLOT_H + GRP_GAP
	local CONTENT_H = (NUM_GROUPS / 2) * GRP_H + 8
	-- GRP_H = 14 + 5*18 + 6 = 110 → CONTENT_H = 4*110+8 = 448 → fits CLIP_H(457) without scroll

	-- Ghost frame: follows cursor during drag, transparent to mouse events
	local ghostFrame = CreateFrame("Frame", "ART_RS_Ghost", UIParent)
	ghostFrame:SetWidth(COL_W)
	ghostFrame:SetHeight(SLOT_H - 1)
	ghostFrame:SetFrameStrata("TOOLTIP")
	ghostFrame:SetBackdrop(EB_BD)
	ghostFrame:SetBackdropColor(0.10, 0.18, 0.10, 0.95)
	ghostFrame:SetBackdropBorderColor(0.45, 0.75, 0.45, 1)
	ghostFrame:EnableMouse(false)
	ghostFrame:Hide()
	local ghostLabel = ghostFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ghostLabel:SetPoint("LEFT", ghostFrame, "LEFT", 4, 0)
	ghostLabel:SetTextColor(1, 1, 1, 1)
	ghostFrame:SetScript("OnUpdate", function()
		local cx, cy = GetCursorPosition()
		local sc = UIParent:GetEffectiveScale()
		ghostFrame:ClearAllPoints()
		ghostFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / sc + 10, cy / sc + 10)
	end)

	-- Clip frame: children outside its bounds are not rendered
	local clipFrame = CreateFrame("Frame", "ART_RS_Clip", panel)
	clipFrame:SetPoint("TOPLEFT",     topSep, "BOTTOMLEFT",   0,  -4)
	clipFrame:SetPoint("BOTTOMRIGHT", panel,  "TOPRIGHT", -22, -526)


	-- Content frame: taller than clip, scrolled by moving its TOPLEFT
	local content = CreateFrame("Frame", "ART_RS_Content", clipFrame)
	content:SetWidth(XPAD * 2 + COL_W * 2 + COL_GAP)
	content:SetHeight(CONTENT_H)
	content:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", 0, 0)

	-- CLIP_H: panel(530) - top offset(~69: title+profileEdit+topSep) - bottom(4) = 457
	local CLIP_H    = 457
	local CLIP_BUFFER = 8  -- extra px so items at the very edge aren't hidden prematurely

	local scrollOffset = 0

	local function GetMaxScroll()
		local max = CONTENT_H - CLIP_H
		return max > 0 and max or 0
	end

	local function SetScroll(val)
		local max = GetMaxScroll()
		if val < 0   then val = 0   end
		if val > max then val = max end
		scrollOffset = val
		content:ClearAllPoints()
		content:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", 0, val)
		local ch = CLIP_H + CLIP_BUFFER
		for g = 1, NUM_GROUPS do
			local row = floor((g - 1) / 2)
			-- Header visibility
			local hdr = groupHdrs[g]
			if hdr then
				local hTop = row * GRP_H + 2
				local hBot = hTop + GRP_HDR_H
				if hBot > val and hTop < val + ch then
					hdr:Show()
				else
					hdr:Hide()
				end
			end
			-- Slot visibility: locked slots show tagBtn, editable/empty slots show EB
			for s = 1, NUM_SLOTS do
				local eb  = groupEBs[g] and groupEBs[g][s]
				local tag = tagBtns[g]  and tagBtns[g][s]
				if eb then
					local dTop = row * GRP_H + 2 + GRP_HDR_H + (s - 1) * SLOT_H
					local dBot = dTop + SLOT_H
					if dBot > val and dTop < val + ch then
						RefreshSlotVisual(g, s)
					else
						eb:Hide()
						if tag then tag:Hide() end
					end
				end
			end
		end
	end

	-- Slider on the right side
	local slider = CreateFrame("Slider", "ART_RS_Slider", panel)
	slider:SetOrientation("VERTICAL")
	slider:SetWidth(12)
	slider:SetPoint("TOPRIGHT",    clipFrame, "TOPRIGHT",    18, 0)
	slider:SetPoint("BOTTOMRIGHT", clipFrame, "BOTTOMRIGHT", 18, 0)
	slider:SetMinMaxValues(0, math.max(CONTENT_H - CLIP_H, 0))
	slider:SetValueStep(20)
	slider:SetValue(0)
	-- Thumb texture
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetWidth(10)
	thumb:SetHeight(24)
	thumb:SetTexture(0.5, 0.5, 0.55, 0.9)
	slider:SetThumbTexture(thumb)
	-- Track background
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints(slider)
	track:SetTexture(0.12, 0.12, 0.15, 0.8)

	slider:SetScript("OnValueChanged", function()
		SetScroll(this:GetValue())
	end)

	panel:SetScript("OnShow", function()
		slider:SetValue(0)
		SetScroll(0)
	end)

	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function()
		local delta  = arg1
		local newVal = scrollOffset - delta * 30
		local max    = GetMaxScroll()
		if newVal < 0   then newVal = 0   end
		if newVal > max then newVal = max  end
		slider:SetValue(newVal)
	end)

	-- ── Group grids ────────────────────────────────────────────
	local GRP_LABELS = {
		"Grp 1","Grp 2","Grp 3","Grp 4",
		"Grp 5","Grp 6","Grp 7","Grp 8",
	}

	for g = 1, NUM_GROUPS do
		groupEBs[g] = {}
		local col  = (g - 1) - floor((g - 1) / 2) * 2  -- 0 = left, 1 = right
		local row  = floor((g - 1) / 2)                 -- 0..3
		local xOff = XPAD + col * (COL_W + COL_GAP)
		local yOff = -(row * GRP_H + 2)

		-- Group header
		local hdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		hdr:SetPoint("TOPLEFT", content, "TOPLEFT", xOff, yOff)
		hdr:SetText(GRP_LABELS[g])
		hdr:SetTextColor(1, 0.82, 0, 1)
		groupHdrs[g] = hdr

		-- 5 player slots: EditBox (editable) + tagBtn (locked display + drag source)
		if not tagBtns[g] then tagBtns[g] = {} end
		for s = 1, NUM_SLOTS do
			-- Lua 5.0: capture per-iteration copies before any closures reference them
			local myG = g
			local myS = s
			local slotY = yOff - GRP_HDR_H - (s - 1) * SLOT_H

			-- EditBox
			local eb = CreateFrame("EditBox", nil, content)
			eb:SetWidth(COL_W)
			eb:SetHeight(SLOT_H - 1)
			eb:SetPoint("TOPLEFT", content, "TOPLEFT", xOff, slotY)
			eb:SetFontObject(GameFontHighlightSmall)
			eb:SetTextInsets(4, 4, 0, 0)
			eb:SetBackdrop(EB_BD)
			eb:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
			eb:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
			eb:SetScript("OnEditFocusGained", function()
				this:SetBackdropBorderColor(1, 0.82, 0, 0.8)
			end)
			eb:SetScript("OnEditFocusLost", function()
				this:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)
				RefreshSlotVisual(myG, myS)   -- lock if text present
			end)
			eb:SetScript("OnEnterPressed", function()
				this:ClearFocus()             -- triggers OnEditFocusLost → lock
			end)
			eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
			eb:SetScript("OnTabPressed", function()
				local ns = myS + 1
				local ng = myG
				if ns > NUM_SLOTS then ns = 1; ng = ng + 1 end
				if ng > NUM_GROUPS then ng = 1 end
				local nextEB  = groupEBs[ng] and groupEBs[ng][ns]
				local nextTag = tagBtns[ng]  and tagBtns[ng][ns]
				if nextEB then
					local trow = floor((ng - 1) / 2)
					local dTop = trow * GRP_H + 2 + GRP_HDR_H + (ns - 1) * SLOT_H
					local dBot = dTop + SLOT_H
					if dTop < scrollOffset then
						slider:SetValue(dTop)
					elseif dBot > scrollOffset + CLIP_H then
						slider:SetValue(dBot - CLIP_H)
					end
					-- Unlock next slot so it's editable
					if nextTag then nextTag:Hide() end
					nextEB:Show()
					nextEB:SetFocus()
					nextEB:HighlightText()
				end
			end)
			eb:SetAutoFocus(false)
			eb:SetMaxLetters(24)
			groupEBs[g][s] = eb

			-- Tag button: shows locked name, acts as drag source
			local tagBtn = CreateFrame("Button", nil, content)
			tagBtn:SetWidth(COL_W)
			tagBtn:SetHeight(SLOT_H - 1)
			tagBtn:SetPoint("TOPLEFT", content, "TOPLEFT", xOff, slotY)
			tagBtn:SetBackdrop(EB_BD)
			tagBtn:SetBackdropColor(0.10, 0.14, 0.10, 0.95)
			tagBtn:SetBackdropBorderColor(0.28, 0.52, 0.28, 1)
			tagBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			tagBtn:RegisterForDrag("LeftButton")
			tagBtn:Hide()
			local tagLabel = tagBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			tagLabel:SetPoint("LEFT", tagBtn, "LEFT", 4, 0)
			tagLabel:SetTextColor(0.85, 1.0, 0.85, 1)
			tagBtn.tagLabel = tagLabel
			tagBtns[g][s] = tagBtn

			-- Click: unlock for editing
			tagBtn:SetScript("OnClick", function()
				this:Hide()
				local myEB = groupEBs[myG] and groupEBs[myG][myS]
				if myEB then
					myEB:Show()
					myEB:SetFocus()
					myEB:HighlightText()
				end
			end)

			-- Drag start: show ghost, record source
			tagBtn:SetScript("OnDragStart", function()
				dragSource = { g = myG, s = myS }
				local myEB = groupEBs[myG] and groupEBs[myG][myS]
				if myEB then ghostLabel:SetText(myEB:GetText()) end
				ghostFrame:Show()
			end)

			-- Drag stop: find drop target by cursor position vs frame bounds
			tagBtn:SetScript("OnDragStop", function()
				ghostFrame:Hide()
				if not dragSource then return end

				local cx, cy = GetCursorPosition()
				local sc = UIParent:GetEffectiveScale()
				local mx = cx / sc
				local my = cy / sc

				local dropG, dropS = nil, nil
				for dg = 1, NUM_GROUPS do
					if tagBtns[dg] then
						for ds = 1, NUM_SLOTS do
							-- Check whichever of tagBtn / editbox is currently visible
							local hit = nil
							local tb  = tagBtns[dg][ds]
							local deb = groupEBs[dg] and groupEBs[dg][ds]
							if tb and tb:IsShown() then
								hit = tb
							elseif deb and deb:IsShown() then
								hit = deb
							end
							if hit then
								local l = hit:GetLeft()
								local r = hit:GetRight()
								local b = hit:GetBottom()
								local t = hit:GetTop()
								if l and r and b and t
								   and mx >= l and mx <= r
								   and my >= b and my <= t then
									dropG = dg; dropS = ds
								end
							end
							if dropG then break end
						end
					end
					if dropG then break end
				end
				local src = dragSource
				dragSource = nil
				if dropG and dropS and (dropG ~= src.g or dropS ~= src.s) then
					SwapSlots(src.g, src.s, dropG, dropS)
				end
			end)
		end
	end

	clearAllBtn:SetScript("OnClick", function()
		for g = 1, NUM_GROUPS do
			for s = 1, NUM_SLOTS do
				local eb = groupEBs[g] and groupEBs[g][s]
				if eb then eb:SetText("") end
			end
		end
		SetScroll(scrollOffset)  -- unlock all slots (text cleared)
	end)

	loadCurrentBtn:SetScript("OnClick", function()
		if GetNumRaidMembers() == 0 then
			DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Not in a raid.")
			return
		end
		-- Clear fields first
		for g = 1, NUM_GROUPS do
			for s = 1, NUM_SLOTS do
				local eb = groupEBs[g] and groupEBs[g][s]
				if eb then eb:SetText("") end
			end
		end
		-- Track next free slot per group
		local nextSlot = {}
		for g = 1, NUM_GROUPS do nextSlot[g] = 1 end
		for i = 1, 40 do
			local name, _, subgroup = GetRaidRosterInfo(i)
			if name and subgroup and subgroup >= 1 and subgroup <= NUM_GROUPS then
				local s = nextSlot[subgroup]
				if s <= NUM_SLOTS then
					local eb = groupEBs[subgroup] and groupEBs[subgroup][s]
					if eb then
						eb:SetText(name)
						nextSlot[subgroup] = s + 1
					end
				end
			end
		end
	SetScroll(scrollOffset)  -- lock loaded slots
	end)

	-- Refresh slot visuals whenever the profile dropdown closes (profile loaded or dismissed)
	ddFrame:SetScript("OnHide", function()
		SetScroll(scrollOffset)
	end)

	-- ── Current Export modal ───────────────────────────────────
	local ceModal = CreateFrame("Frame", nil, UIParent)
	ceModal:SetAllPoints(UIParent)
	ceModal:SetFrameStrata("FULLSCREEN_DIALOG")
	ceModal:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", tile=true, tileSize=16, edgeSize=0, insets={left=0,right=0,top=0,bottom=0} })
	ceModal:SetBackdropColor(0, 0, 0, 0.6)
	ceModal:EnableMouse(true)
	ceModal:Hide()

	local ceInner = CreateFrame("Frame", nil, ceModal)
	ceInner:SetWidth(260)
	ceInner:SetHeight(340)
	ceInner:SetPoint("CENTER", ceModal, "CENTER", 0, 0)
	ceInner:SetBackdrop({
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile=true, tileSize=16, edgeSize=16,
		insets={left=4,right=4,top=4,bottom=4},
	})
	ceInner:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
	ceInner:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)

	local ceTitleFS = ceInner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	ceTitleFS:SetPoint("TOPLEFT", ceInner, "TOPLEFT", 14, -14)
	ceTitleFS:SetText("Current Raid")
	ceTitleFS:SetTextColor(1, 0.82, 0, 1)

	local ceHintFS = ceInner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ceHintFS:SetPoint("TOPLEFT", ceTitleFS, "BOTTOMLEFT", 0, -4)
	ceHintFS:SetText("Select all  (Ctrl+A)  then copy  (Ctrl+C)")
	ceHintFS:SetTextColor(0.55, 0.55, 0.6, 1)

	local ceCloseBtn = CreateFrame("Button", nil, ceInner, "UIPanelCloseButton")
	ceCloseBtn:SetWidth(24); ceCloseBtn:SetHeight(24)
	ceCloseBtn:SetPoint("TOPRIGHT", ceInner, "TOPRIGHT", 2, 2)
	ceCloseBtn:SetScript("OnClick", function() ceModal:Hide() end)

	local ceSF = CreateFrame("ScrollFrame", "ART_RS_CeSF", ceInner)
	ceSF:SetPoint("TOPLEFT",     ceHintFS, "BOTTOMLEFT", 0, -8)
	ceSF:SetPoint("BOTTOMRIGHT", ceInner,  "BOTTOMRIGHT", -8, 8)

	local ceEB = CreateFrame("EditBox", nil, ceSF)
	ceEB:SetWidth(ceSF:GetWidth() or 220)
	ceEB:SetHeight(1)
	ceEB:SetMultiLine(true)
	ceEB:SetFontObject(GameFontHighlight)
	ceEB:SetTextInsets(4, 4, 2, 2)
	ceEB:SetAutoFocus(false)
	ceEB:SetScript("OnEscapePressed", function() ceModal:Hide() end)
	ceSF:SetScrollChild(ceEB)

	currentExportBtn:SetScript("OnClick", function()
		local names = {}
		local count = 0
		local nr = GetNumRaidMembers()
		if nr > 0 then
			for i = 1, 40 do
				local rname = GetRaidRosterInfo(i)
				if rname then
					count = count + 1
					names[count] = rname
				end
			end
		else
			local pname = UnitName("player")
			if pname then count = count + 1; names[count] = pname end
			local np = GetNumPartyMembers()
			for i = 1, np do
				local pm = UnitName("party" .. i)
				if pm then count = count + 1; names[count] = pm end
			end
		end
		table.sort(names)
		local text = ""
		for i = 1, count do
			if i > 1 then text = text .. "\n" end
			text = text .. names[i]
		end
		ceEB:SetText(text)
		ceModal:Show()
		ceEB:SetFocus()
		ceEB:HighlightText()
	end)

	AmptieRaidTools_RegisterComponent("raidsetups", panel)
end

-- Refresh colors of all visible locked slots when raid roster changes
local rsEventFrame = CreateFrame("Frame", "ART_RS_EventFrame", UIParent)
rsEventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
rsEventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
rsEventFrame:SetScript("OnEvent", function()
    for g = 1, NUM_GROUPS do
        if tagBtns[g] then
            for s = 1, NUM_SLOTS do
                local tag = tagBtns[g][s]
                if tag and tag:IsShown() then
                    local eb = groupEBs[g] and groupEBs[g][s]
                    local name = eb and eb:GetText() or ""
                    if name ~= "" then
                        ApplyTagColors(tag, name)
                    end
                end
            end
        end
    end
end)
