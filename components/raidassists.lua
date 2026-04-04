-- amptieRaidTools – Component: Raid Assists (raidassists.lua)
-- Auto-Invite: whisper keyword → InviteUnit
-- Auto-Assist: PromoteToAssistant when player joins raid
-- Main Tanks: MT1-MT8 names, broadcast via addon message
-- Vanilla 1.12 / Lua 5.0 / TurtleWoW

-- Key Binding display strings
BINDING_HEADER_AMPTIERAIDTOOLS = "Raid Assist (amptieRaidTools)"
BINDING_NAME_ARTSETMT1 = "Set Target as Main Tank 1"
BINDING_NAME_ARTSETMT2 = "Set Target as Main Tank 2"
BINDING_NAME_ARTSETMT3 = "Set Target as Main Tank 3"
BINDING_NAME_ARTSETMT4 = "Set Target as Main Tank 4"
BINDING_NAME_ARTSETMT5 = "Set Target as Main Tank 5"
BINDING_NAME_ARTSETMT6 = "Set Target as Main Tank 6"
BINDING_NAME_ARTSETMT7 = "Set Target as Main Tank 7"
BINDING_NAME_ARTSETMT8 = "Set Target as Main Tank 8"

local getn    = table.getn
local tinsert = table.insert
local tremove = table.remove
local sfind   = string.find
local ssub    = string.sub
local slen    = string.len
local slower  = string.lower
local floor   = math.floor
local mmax    = math.max

local MT_PREFIX        = "ART_MT"
local NUM_MT_SLOTS     = 8
local MAX_KEYWORD_ROWS = 6    -- max invite keywords (6 is plenty)
local MAX_AA_NAMES     = 80   -- max auto-assist names stored
local DISP_ROWS        = 8    -- visible AA rows at once

-- ── DB ────────────────────────────────────────────────────────
local function GetDB()
	if not amptieRaidToolsDB then return nil end
	local db = amptieRaidToolsDB
	if not db.raidAssists then db.raidAssists = {} end
	local ra = db.raidAssists
	if not ra.inviteKeywords  then ra.inviteKeywords  = {} end
	if not ra.autoAssists     then ra.autoAssists     = {} end
	if not ra.mainTanks       then ra.mainTanks       = {} end
	if ra.autoInviteEnabled == nil then ra.autoInviteEnabled = false end
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
	return ra
end

-- ── Auto-Invite ───────────────────────────────────────────────
local function TryAutoInvite(msg, sender)
	local db = GetDB()
	if not db then return end
	local kws = db.inviteKeywords
	if getn(kws) == 0 then return end
	local lmsg = slower(msg)
	for i = 1, getn(kws) do
		local kw = kws[i]
		if kw and kw ~= "" and sfind(lmsg, slower(kw), 1, true) then
			-- keyword matched — check if enabled
			if not db.autoInviteEnabled then
				DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Auto-invite keyword matched ('" .. kw .. "') but toggle is DISABLED. Enable it in Raid Assists.")
				return
			end
			-- convert 5-man party to raid before inviting if needed
			if GetNumPartyMembers() == 4 and GetNumRaidMembers() == 0 then
				ConvertToRaid()
			end
			if GetNumRaidMembers() >= 40 then
				SendChatMessage("<aRT> The raid is full.", "WHISPER", nil, sender)
			else
				if type(InviteUnit) == "function" then
					InviteUnit(sender)
				else
					InviteByName(sender)
				end
				DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Auto-inviting: " .. sender)
			end
			return
		end
	end
end

-- ── Auto-Assist ───────────────────────────────────────────────
local function RunAutoAssists()
	local db = GetDB()
	if not db or getn(db.autoAssists) == 0 then return end
	if not IsRaidLeader() then return end   -- PromoteToAssistant requires leader
	local num = GetNumRaidMembers()
	if num == 0 then return end
	local inRaid = {}
	for i = 1, num do
		local name, rank = GetRaidRosterInfo(i)
		if name then inRaid[name] = rank end   -- 0=member, 1=assist, 2=leader
	end
	for i = 1, getn(db.autoAssists) do
		local n = db.autoAssists[i]
		if n and n ~= "" and inRaid[n] == 0 then
			PromoteToAssistant(n)
		end
	end
end

-- ── MT Broadcast ──────────────────────────────────────────────
local RefreshMTUI = nil   -- forward ref, assigned inside panel init

local function ParseMTs(str)
	local slots = {}
	local s = str .. ";"
	local pos = 1
	while pos <= slen(s) and getn(slots) < NUM_MT_SLOTS do
		local e = sfind(s, ";", pos, true)
		if not e then break end
		tinsert(slots, ssub(s, pos, e - 1))
		pos = e + 1
	end
	return slots
end

local function BroadcastMTs(silent)
	local db = GetDB()
	if not db then return end
	local ch = nil
	if GetNumRaidMembers()  > 0 then ch = "RAID"
	elseif GetNumPartyMembers() > 0 then ch = "PARTY"
	end
	if not ch then
		if not silent then
			DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Not in a group.")
		end
		return
	end
	local msg = ""
	for i = 1, NUM_MT_SLOTS do
		if i > 1 then msg = msg .. ";" end
		msg = msg .. (db.mainTanks[i] or "")
	end
	SendAddonMessage(MT_PREFIX, "MT^" .. msg, ch)
	if not silent then
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r MT list broadcast.")
	end
end

local function RequestMTs()
	-- Ask lead/assist to send us the current MT list
	if GetNumRaidMembers() > 0 then
		SendAddonMessage(MT_PREFIX, "MT_REQUEST", "RAID")
	end
end

-- ── Helpers ───────────────────────────────────────────────────
local function CanBroadcastMTs()
	return IsRaidLeader() or IsRaidOfficer()
end

-- ── Event Frame ───────────────────────────────────────────────
local raEvt = CreateFrame("Frame", "ART_RA_EventFrame", UIParent)
raEvt:RegisterEvent("RAID_ROSTER_UPDATE")
raEvt:RegisterEvent("PARTY_MEMBERS_CHANGED")
raEvt:RegisterEvent("PLAYER_LOGIN")
raEvt:RegisterEvent("PLAYER_ENTERING_WORLD")
raEvt:RegisterEvent("CHAT_MSG_WHISPER")
raEvt:RegisterEvent("CHAT_MSG_ADDON")
raEvt:SetScript("OnEvent", function()
	local evt    = event
	local a1, a2 = arg1, arg2

	if evt == "PLAYER_LOGIN" or evt == "PLAYER_ENTERING_WORLD" then
		-- When joining a raid, request current MT list from lead/assist
		if GetNumRaidMembers() > 0 then
			RequestMTs()
		else
			-- Not in a raid: clear MT list
			local db = GetDB()
			if db then
				for i = 1, NUM_MT_SLOTS do db.mainTanks[i] = "" end
				if RefreshMTUI then RefreshMTUI() end
				if AmptieRaidTools_UpdateMTOverlay then AmptieRaidTools_UpdateMTOverlay() end
			end
		end

	elseif evt == "RAID_ROSTER_UPDATE" or evt == "PARTY_MEMBERS_CHANGED" then
		RunAutoAssists()
		-- New member joined: if we are lead/assist, broadcast so they get the list
		if CanBroadcastMTs() and GetNumRaidMembers() > 0 then
			BroadcastMTs(true)
		end

	elseif evt == "CHAT_MSG_WHISPER" then
		if a1 and a2 then
			local name = a2
			local d = sfind(name, "-", 1, true)
			if d then name = ssub(name, 1, d - 1) end
			TryAutoInvite(a1, name)
		end

	elseif evt == "CHAT_MSG_ADDON" then
		if a1 == MT_PREFIX then
			-- Someone requests the MT list → respond if we are lead/assist
			if a2 == "MT_REQUEST" then
				if CanBroadcastMTs() and GetNumRaidMembers() > 0 then
					BroadcastMTs(true)
				end
			else
				local _, _, payload = sfind(a2, "^MT%^(.*)$")
				if payload ~= nil then
					local db = GetDB()
					if db then
						local slots = ParseMTs(payload)
						for i = 1, NUM_MT_SLOTS do
							db.mainTanks[i] = slots[i] or ""
						end
						if RefreshMTUI then RefreshMTUI() end
						if AmptieRaidTools_UpdateMTOverlay then AmptieRaidTools_UpdateMTOverlay() end
					end
				end
			end
		end
	end
end)

-- ── Panel UI ──────────────────────────────────────────────────
function AmptieRaidTools_InitRaidAssists(body)
	local panel = CreateFrame("Frame", "ART_RA_Panel", body)
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

	local function MakeBtn(parent, label, w, h)
		local btn = CreateFrame("Button", nil, parent)
		btn:SetWidth(w or 80)
		btn:SetHeight(h or 22)
		btn:SetBackdrop(BD)
		btn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
		btn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
		btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
		fs:SetText(label)
		btn.fs = fs
		return btn
	end

	local function MakeEB(parent, w, maxLen)
		local eb = CreateFrame("EditBox", nil, parent)
		eb:SetWidth(w or 150)
		eb:SetHeight(22)
		eb:SetFontObject(GameFontHighlightSmall)
		eb:SetTextInsets(6, 6, 0, 0)
		eb:SetBackdrop(EB_BD)
		eb:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
		eb:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
		eb:SetScript("OnEditFocusGained", function()
			this:SetBackdropBorderColor(1, 0.82, 0, 0.8)
		end)
		eb:SetScript("OnEditFocusLost", function()
			this:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
		end)
		eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
		eb:SetAutoFocus(false)
		eb:SetMaxLetters(maxLen or 32)
		return eb
	end

	-- ── Title ──────────────────────────────────────────────────
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
	title:SetText("Raid Assists")
	title:SetTextColor(1, 0.82, 0, 1)

	local COL_W  = 288
	local COL2_X = 10 + COL_W + 18
	local ROW_H  = 20
	local ROW_GAP = 2

	-- ══════════════════════════════════════════════════════════
	-- AUTO-INVITES  (left column)
	-- ══════════════════════════════════════════════════════════
	local aiHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	aiHdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -40)
	aiHdr:SetText("Auto-Invites")
	aiHdr:SetTextColor(1, 0.82, 0, 1)

	local aiToggle = MakeBtn(panel, "Disabled", 72, 18)
	aiToggle:SetPoint("LEFT", aiHdr, "RIGHT", 8, 0)

	local function UpdateAIToggle()
		local db = GetDB()
		if db and db.autoInviteEnabled then
			aiToggle.fs:SetText("Enabled")
			aiToggle:SetBackdropColor(0.08, 0.20, 0.08, 0.95)
			aiToggle:SetBackdropBorderColor(0.35, 0.75, 0.35, 1)
			aiToggle.fs:SetTextColor(0.4, 1.0, 0.4, 1)
		else
			aiToggle.fs:SetText("Disabled")
			aiToggle:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
			aiToggle:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
			aiToggle.fs:SetTextColor(0.50, 0.50, 0.50, 1)
		end
	end
	aiToggle:SetScript("OnClick", function()
		local db = GetDB()
		if not db then return end
		db.autoInviteEnabled = not db.autoInviteEnabled
		UpdateAIToggle()
	end)

	local aiDesc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	aiDesc:SetPoint("TOPLEFT", aiHdr, "BOTTOMLEFT", 0, -4)
	aiDesc:SetText("Whisper keyword → auto-invite to raid")
	aiDesc:SetTextColor(0.52, 0.52, 0.52, 1)

	local aiEB = MakeEB(panel, 196, 24)
	aiEB:SetPoint("TOPLEFT", aiDesc, "BOTTOMLEFT", 0, -6)

	local aiAddBtn = MakeBtn(panel, "+ Add", 62, 22)
	aiAddBtn:SetPoint("LEFT", aiEB, "RIGHT", 4, 0)

	local aiRows = {}
	local RefreshAIRows   -- forward

	local function DoAddKeyword()
		local txt = aiEB:GetText()
		if not txt or txt == "" then return end
		local db = GetDB()
		if not db then return end
		if getn(db.inviteKeywords) >= MAX_KEYWORD_ROWS then return end
		local lt = slower(txt)
		for i = 1, getn(db.inviteKeywords) do
			if slower(db.inviteKeywords[i]) == lt then
				aiEB:SetText(""); return
			end
		end
		-- auto-enable when first keyword is added (matches oRA2 behaviour)
		local wasEmpty = (getn(db.inviteKeywords) == 0)
		tinsert(db.inviteKeywords, txt)
		if wasEmpty and not db.autoInviteEnabled then
			db.autoInviteEnabled = true
			UpdateAIToggle()
		end
		aiEB:SetText("")
		aiEB:ClearFocus()
		RefreshAIRows()
	end
	aiAddBtn:SetScript("OnClick", DoAddKeyword)
	aiEB:SetScript("OnEnterPressed", function() DoAddKeyword() end)

	for i = 1, MAX_KEYWORD_ROWS do
		local row = CreateFrame("Frame", nil, panel)
		row:SetHeight(ROW_H)
		row:SetWidth(COL_W)
		if i == 1 then
			row:SetPoint("TOPLEFT", aiEB, "BOTTOMLEFT", 0, -4)
		else
			row:SetPoint("TOPLEFT", aiRows[i - 1], "BOTTOMLEFT", 0, -ROW_GAP)
		end
		row:Hide()
		local dot = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		dot:SetPoint("LEFT", row, "LEFT", 2, 0)
		dot:SetText("*")
		dot:SetTextColor(0.55, 0.55, 0.55, 1)
		local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		lbl:SetPoint("LEFT", dot, "RIGHT", 4, 0)
		lbl:SetTextColor(0.9, 0.9, 0.9, 1)
		row.lbl = lbl
		local del = MakeBtn(row, "x", 20, ROW_H - 2)
		del:SetPoint("RIGHT", row, "RIGHT", -2, 0)
		del.fs:SetTextColor(0.75, 0.25, 0.25, 1)
		local myI = i
		del:SetScript("OnClick", function()
			local db = GetDB()
			if not db then return end
			tremove(db.inviteKeywords, myI)
			-- auto-disable when last keyword removed
			if getn(db.inviteKeywords) == 0 and db.autoInviteEnabled then
				db.autoInviteEnabled = false
				UpdateAIToggle()
			end
			RefreshAIRows()
		end)
		aiRows[i] = row
	end

	RefreshAIRows = function()
		local db = GetDB()
		local kws = (db and db.inviteKeywords) or {}
		local n = getn(kws)
		for i = 1, MAX_KEYWORD_ROWS do
			if i <= n then
				aiRows[i].lbl:SetText(kws[i])
				aiRows[i]:Show()
			else
				aiRows[i]:Hide()
			end
		end
	end

	-- ══════════════════════════════════════════════════════════
	-- AUTO-ASSISTS  (right column, scrollable list up to 40)
	-- ══════════════════════════════════════════════════════════
	local aaHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	aaHdr:SetPoint("TOPLEFT", panel, "TOPLEFT", COL2_X, -40)
	aaHdr:SetText("Auto-Assists")
	aaHdr:SetTextColor(1, 0.82, 0, 1)

	local aaDesc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	aaDesc:SetPoint("TOPLEFT", aaHdr, "BOTTOMLEFT", 0, -4)
	aaDesc:SetText("Auto-promote to assistant when joining raid (max 80)")
	aaDesc:SetTextColor(0.52, 0.52, 0.52, 1)

	local aaEB = MakeEB(panel, 140, 64)
	aaEB:SetPoint("TOPLEFT", aaDesc, "BOTTOMLEFT", 0, -6)

	local aaAddBtn = MakeBtn(panel, "+ Add", 52, 22)
	aaAddBtn:SetPoint("LEFT", aaEB, "RIGHT", 4, 0)

	local aaImportBtn = MakeBtn(panel, "Import", 52, 22)
	aaImportBtn:SetPoint("LEFT", aaAddBtn, "RIGHT", 4, 0)

	-- scroll state
	local aaScrollOff = 0
	local LIST_W = COL_W - 22   -- narrower: leave 20px for scroll buttons + 2px gap
	local LIST_H = DISP_ROWS * (ROW_H + ROW_GAP)

	local aaListBox = CreateFrame("Frame", nil, panel)
	aaListBox:SetWidth(LIST_W)
	aaListBox:SetHeight(LIST_H)
	aaListBox:SetPoint("TOPLEFT", aaEB, "BOTTOMLEFT", 0, -4)
	aaListBox:EnableMouseWheel(true)

	local aaRows = {}
	local RefreshAARows   -- forward

	aaListBox:SetScript("OnMouseWheel", function()
		local db = GetDB()
		local n = db and getn(db.autoAssists) or 0
		local maxOff = mmax(0, n - DISP_ROWS)
		local newOff = aaScrollOff - arg1   -- arg1: +1=up, -1=down
		if newOff < 0 then newOff = 0 end
		if newOff > maxOff then newOff = maxOff end
		if newOff ~= aaScrollOff then
			aaScrollOff = newOff
			RefreshAARows()
		end
	end)

	-- Scroll buttons (native WoW scrollbar textures)
	local aaScrollUp = CreateFrame("Button", nil, panel)
	aaScrollUp:SetWidth(18)
	aaScrollUp:SetHeight(18)
	aaScrollUp:SetPoint("TOPLEFT", aaListBox, "TOPRIGHT", 2, 0)
	aaScrollUp:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
	aaScrollUp:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
	aaScrollUp:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
	aaScrollUp:SetScript("OnClick", function()
		if aaScrollOff > 0 then
			aaScrollOff = aaScrollOff - 1
			RefreshAARows()
		end
	end)

	local aaScrollDn = CreateFrame("Button", nil, panel)
	aaScrollDn:SetWidth(18)
	aaScrollDn:SetHeight(18)
	aaScrollDn:SetPoint("BOTTOMLEFT", aaListBox, "BOTTOMRIGHT", 2, 0)
	aaScrollDn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
	aaScrollDn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
	aaScrollDn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
	aaScrollDn:SetScript("OnClick", function()
		local db = GetDB()
		local n = db and getn(db.autoAssists) or 0
		local maxOff = mmax(0, n - DISP_ROWS)
		if aaScrollOff < maxOff then
			aaScrollOff = aaScrollOff + 1
			RefreshAARows()
		end
	end)

	local function DoImportText(txt)
		if not txt or txt == "" then return end
		local db = GetDB()
		if not db then return end
		for token in string.gfind(txt, "[^,;\n]+") do
			local name = string.gsub(token, "^%s*(.-)%s*$", "%1")
			if name ~= "" then
				if getn(db.autoAssists) >= MAX_AA_NAMES then break end
				local dupe = false
				for i = 1, getn(db.autoAssists) do
					if db.autoAssists[i] == name then dupe = true; break end
				end
				if not dupe then
					tinsert(db.autoAssists, name)
				end
			end
		end
		RefreshAARows()
	end

	local function DoAddAssist()
		local txt = aaEB:GetText()
		if not txt or txt == "" then return end
		DoImportText(txt)
		aaEB:SetText("")
		aaEB:ClearFocus()
	end
	aaAddBtn:SetScript("OnClick", DoAddAssist)
	aaEB:SetScript("OnEnterPressed", function() DoAddAssist() end)

	-- ── Import Popup ───────────────────────────────────────────
	local aaPopup = CreateFrame("Frame", "ART_AAImportPopup", UIParent)
	aaPopup:SetWidth(340)
	aaPopup:SetHeight(220)
	aaPopup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	aaPopup:SetFrameStrata("FULLSCREEN_DIALOG")
	aaPopup:SetMovable(true)
	aaPopup:EnableMouse(true)
	aaPopup:RegisterForDrag("LeftButton")
	aaPopup:SetScript("OnDragStart", function() this:StartMoving() end)
	aaPopup:SetScript("OnDragStop",  function() this:StopMovingOrSizing() end)
	aaPopup:SetBackdrop({
		bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	aaPopup:Hide()

	local popTitle = aaPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	popTitle:SetPoint("TOP", aaPopup, "TOP", 0, -10)
	popTitle:SetText("Import Auto-Assists")
	popTitle:SetTextColor(1, 0.82, 0, 1)

	local popHint = aaPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	popHint:SetPoint("TOP", popTitle, "BOTTOM", 0, -4)
	popHint:SetText("Comma, semicolon or newline separated")
	popHint:SetTextColor(0.55, 0.55, 0.55, 1)

	-- ScrollFrame + multiline EditBox
	local popSF = CreateFrame("ScrollFrame", "ART_AAImportSF", aaPopup, "UIPanelScrollFrameTemplate")
	popSF:SetPoint("TOPLEFT",  aaPopup, "TOPLEFT",  10, -48)
	popSF:SetPoint("BOTTOMRIGHT", aaPopup, "BOTTOMRIGHT", -30, 40)

	local popEB = CreateFrame("EditBox", nil, popSF)
	popEB:SetWidth(popSF:GetWidth())
	popEB:SetHeight(1)   -- grows with content
	popEB:SetMultiLine(true)
	popEB:SetMaxLetters(4096)
	popEB:SetFontObject(GameFontHighlightSmall)
	popEB:SetTextInsets(4, 4, 4, 4)
	popEB:SetAutoFocus(false)
	popEB:SetScript("OnEscapePressed", function() aaPopup:Hide() end)
	popSF:SetScrollChild(popEB)

	local popImport = MakeBtn(aaPopup, "Import", 80, 22)
	popImport:SetPoint("BOTTOMRIGHT", aaPopup, "BOTTOMRIGHT", -10, 10)
	popImport:SetScript("OnClick", function()
		DoImportText(popEB:GetText())
		popEB:SetText("")
		aaPopup:Hide()
	end)

	local popCancel = MakeBtn(aaPopup, "Cancel", 70, 22)
	popCancel:SetPoint("RIGHT", popImport, "LEFT", -6, 0)
	popCancel:SetScript("OnClick", function()
		popEB:SetText("")
		aaPopup:Hide()
	end)

	aaImportBtn:SetScript("OnClick", function()
		if aaPopup:IsShown() then
			aaPopup:Hide()
		else
			aaPopup:Show()
			popEB:SetFocus()
		end
	end)

	for i = 1, DISP_ROWS do
		local row = CreateFrame("Frame", nil, aaListBox)
		row:SetHeight(ROW_H)
		row:SetWidth(LIST_W)
		if i == 1 then
			row:SetPoint("TOPLEFT", aaListBox, "TOPLEFT", 0, 0)
		else
			row:SetPoint("TOPLEFT", aaRows[i - 1], "BOTTOMLEFT", 0, -ROW_GAP)
		end
		row:Hide()
		row.realIdx = nil
		local dot = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		dot:SetPoint("LEFT", row, "LEFT", 2, 0)
		dot:SetText("*")
		dot:SetTextColor(0.55, 0.55, 0.55, 1)
		local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		lbl:SetPoint("LEFT", dot, "RIGHT", 4, 0)
		lbl:SetTextColor(0.9, 0.9, 0.9, 1)
		row.lbl = lbl
		local del = MakeBtn(row, "x", 20, ROW_H - 2)
		del:SetPoint("RIGHT", row, "RIGHT", -2, 0)
		del.fs:SetTextColor(0.75, 0.25, 0.25, 1)
		local myI = i
		del:SetScript("OnClick", function()
			local db = GetDB()
			if not db then return end
			local realIdx = aaRows[myI] and aaRows[myI].realIdx
			if realIdx then
				tremove(db.autoAssists, realIdx)
				local n2 = getn(db.autoAssists)
				local maxOff = mmax(0, n2 - DISP_ROWS)
				if aaScrollOff > maxOff then aaScrollOff = maxOff end
				RefreshAARows()
			end
		end)
		aaRows[i] = row
	end

	RefreshAARows = function()
		local db = GetDB()
		local names = (db and db.autoAssists) or {}
		local n = getn(names)
		local maxOff = mmax(0, n - DISP_ROWS)
		if aaScrollOff > maxOff then aaScrollOff = maxOff end
		for i = 1, DISP_ROWS do
			local idx = i + aaScrollOff
			if idx <= n then
				aaRows[i].lbl:SetText(names[idx])
				aaRows[i].realIdx = idx
				aaRows[i]:Show()
			else
				aaRows[i].realIdx = nil
				aaRows[i]:Hide()
			end
		end
	end

	-- ══════════════════════════════════════════════════════════
	-- SEPARATOR
	-- Anchor below aaListBox (taller: 8 rows vs 6 AI rows)
	-- TOPLEFT offset brings us back to x=10 from panel left
	-- ══════════════════════════════════════════════════════════
	local sepFrame = CreateFrame("Frame", nil, panel)
	sepFrame:SetHeight(1)
	sepFrame:SetPoint("TOPLEFT", aaListBox, "BOTTOMLEFT", -(COL2_X - 10), -10)
	sepFrame:SetPoint("RIGHT",   panel,     "RIGHT", -10, 0)
	local sepTex = sepFrame:CreateTexture(nil, "ARTWORK")
	sepTex:SetAllPoints(sepFrame)
	sepTex:SetTexture(0.35, 0.35, 0.4, 0.6)

	-- ══════════════════════════════════════════════════════════
	-- MAIN TANKS
	-- ══════════════════════════════════════════════════════════
	local mtHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mtHdr:SetPoint("TOPLEFT", sepFrame, "BOTTOMLEFT", 0, -10)
	mtHdr:SetText("Main Tanks")
	mtHdr:SetTextColor(1, 0.82, 0, 1)

	local mtDesc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	mtDesc:SetPoint("TOPLEFT", mtHdr, "BOTTOMLEFT", 0, -4)
	mtDesc:SetText("MT list is broadcast to all raid members using this addon")
	mtDesc:SetTextColor(0.52, 0.52, 0.52, 1)

	local mtEBs = {}

	local broadcastBtn = MakeBtn(panel, "Broadcast MTs to Raid", 160, 22)
	broadcastBtn:SetPoint("LEFT", mtDesc, "RIGHT", 12, 0)
	broadcastBtn:SetScript("OnClick", function()
		if not CanBroadcastMTs() then
			DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Cannot broadcast: requires Raid Leader or Assist.")
			return
		end
		local db = GetDB()
		if not db then return end
		for i = 1, NUM_MT_SLOTS do
			if mtEBs[i] then db.mainTanks[i] = mtEBs[i]:GetText() end
		end
		BroadcastMTs()
		if AmptieRaidTools_UpdateMTOverlay then AmptieRaidTools_UpdateMTOverlay() end
	end)

	local MT_LBL_W  = 28
	local MT_EB_W   = 178
	local MT_ROW_H  = 24
	local MT_GAP    = 4
	local MT_COL2_X = 10 + MT_LBL_W + MT_EB_W + 44

	local function SaveMT(idx, name)
		local db = GetDB()
		if not db then return end
		db.mainTanks[idx] = name or ""
	end

	for i = 1, NUM_MT_SLOTS do
		local isRight = (i > 4)
		local rowIdx  = isRight and (i - 4) or i
		local xBase   = isRight and MT_COL2_X or 10

		local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		lbl:SetPoint("TOPLEFT", mtDesc, "BOTTOMLEFT",
			xBase,
			-8 - (rowIdx - 1) * (MT_ROW_H + MT_GAP))
		lbl:SetText("MT" .. i)
		lbl:SetTextColor(0.75, 0.75, 0.75, 1)
		lbl:SetWidth(MT_LBL_W)
		lbl:SetJustifyH("LEFT")

		local eb = MakeEB(panel, MT_EB_W, 24)
		eb:SetPoint("TOPLEFT", mtDesc, "BOTTOMLEFT",
			xBase + MT_LBL_W + 4,
			-8 - (rowIdx - 1) * (MT_ROW_H + MT_GAP))
		eb:SetHeight(MT_ROW_H - 2)

		local myI = i
		local function FocusNext()
			SaveMT(myI, this:GetText())
			this:ClearFocus()
			local next = mtEBs[myI + 1]
			if next then
				next:SetFocus()
				next:HighlightText()
			end
		end
		eb:SetScript("OnEnterPressed", FocusNext)
		eb:SetScript("OnTabPressed",   FocusNext)
		eb:SetScript("OnEditFocusLost", function()
			this:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
			SaveMT(myI, this:GetText())
			if CanBroadcastMTs() then BroadcastMTs(true) end
			if AmptieRaidTools_UpdateMTOverlay then AmptieRaidTools_UpdateMTOverlay() end
		end)
		mtEBs[i] = eb

		local clearBtn = MakeBtn(panel, "x", 16, 16)
		clearBtn:SetPoint("LEFT", eb, "RIGHT", 3, 0)
		clearBtn.fs:SetTextColor(0.7, 0.3, 0.3, 1)
		clearBtn:SetScript("OnClick", function()
			eb:SetText("")
			SaveMT(myI, "")
			if CanBroadcastMTs() then BroadcastMTs(true) end
			if AmptieRaidTools_UpdateMTOverlay then AmptieRaidTools_UpdateMTOverlay() end
		end)
	end

	-- ══════════════════════════════════════════════════════════
	-- MT OVERLAY SETTINGS
	-- Anchored 6px below the bottom of the 4-row MT grid.
	-- Row 4 bottom = mtDesc.bottom - (8 + 3*(MT_ROW_H+MT_GAP) + MT_ROW_H - 2)
	--              = mtDesc.bottom - (8 + 84 + 22) = -114  → gap → -120
	-- ══════════════════════════════════════════════════════════
	local OVL_TOP_Y = -120

	local function OvlGet(key, default)
		local db = GetDB()
		local mto = db and db.mtOverlay
		if mto == nil then return default end
		local v = mto[key]
		if v == nil then return default end
		return v
	end

	local function OvlSet(key, val)
		local db = GetDB()
		if not db then return end
		if not db.mtOverlay then db.mtOverlay = {} end
		db.mtOverlay[key] = val
	end

	-- Row 1: section header
	local ovlSecHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ovlSecHdr:SetPoint("TOPLEFT", mtDesc, "BOTTOMLEFT", 0, OVL_TOP_Y - 10)
	ovlSecHdr:SetText("MT Overlay")
	ovlSecHdr:SetTextColor(1, 0.82, 0, 1)

	-- Row 2: Show / Lock buttons (below header)
	local ovlToggle = MakeBtn(panel, "Show: OFF", 88, 20)
	ovlToggle:SetPoint("TOPLEFT", ovlSecHdr, "BOTTOMLEFT", 0, -4)

	local ovlLockBtn = MakeBtn(panel, "Locked", 72, 20)
	ovlLockBtn:SetPoint("LEFT", ovlToggle, "RIGHT", 6, 0)

	local RefreshOvlUI  -- forward ref

	local function UpdateOvlToggle()
		local shown = OvlGet("shown", false)
		if shown then
			ovlToggle.fs:SetText("Show: ON")
			ovlToggle:SetBackdropColor(0.08, 0.20, 0.08, 0.95)
			ovlToggle:SetBackdropBorderColor(0.35, 0.75, 0.35, 1)
			ovlToggle.fs:SetTextColor(0.4, 1.0, 0.4, 1)
		else
			ovlToggle.fs:SetText("Show: OFF")
			ovlToggle:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
			ovlToggle:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
			ovlToggle.fs:SetTextColor(0.50, 0.50, 0.50, 1)
		end
	end

	local function UpdateOvlLockBtn()
		local locked = OvlGet("locked", true)
		if locked then
			ovlLockBtn.fs:SetText("Locked")
			ovlLockBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
			ovlLockBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
			ovlLockBtn.fs:SetTextColor(0.50, 0.50, 0.50, 1)
		else
			ovlLockBtn.fs:SetText("Unlocked")
			ovlLockBtn:SetBackdropColor(0.20, 0.14, 0.06, 0.95)
			ovlLockBtn:SetBackdropBorderColor(0.80, 0.60, 0.20, 1)
			ovlLockBtn.fs:SetTextColor(1.0, 0.80, 0.2, 1)
		end
	end

	ovlToggle:SetScript("OnClick", function()
		local v = not OvlGet("shown", false)
		OvlSet("shown", v)
		UpdateOvlToggle()
		if AmptieRaidTools_SetMTOverlayShown then
			AmptieRaidTools_SetMTOverlayShown(v)
		end
	end)

	ovlLockBtn:SetScript("OnClick", function()
		local v = not OvlGet("locked", true)
		OvlSet("locked", v)
		UpdateOvlLockBtn()
		if AmptieRaidTools_SetMTOverlayLocked then
			AmptieRaidTools_SetMTOverlayLocked(v)
		end
	end)

	-- Spin control: label + [-] value [+]
	-- Each control is 122px wide: label(54) + btn(18) + val(28) + btn(18) + spacing(4)
	local OVL_SPIN_W = 122
	local OVL_SPIN_GAP = 20
	local ovlSpinRefreshFns = {}

	local function MakeSpinCtrl(parent, labelTxt, key, minVal, maxVal, step, default)
		local LABEL_W = 54
		local BTN_W   = 18
		local VAL_W   = 28
		local cont = CreateFrame("Frame", nil, parent)
		cont:SetHeight(20)
		cont:SetWidth(OVL_SPIN_W)

		local lbl = cont:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		lbl:SetPoint("LEFT", cont, "LEFT", 0, 0)
		lbl:SetWidth(LABEL_W)
		lbl:SetJustifyH("LEFT")
		lbl:SetText(labelTxt)
		lbl:SetTextColor(0.75, 0.75, 0.75, 1)

		local minusBtn = MakeBtn(cont, "-", BTN_W, 18)
		minusBtn:SetPoint("LEFT", cont, "LEFT", LABEL_W, 0)

		local valFS = cont:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		valFS:SetPoint("LEFT", minusBtn, "RIGHT", 2, 0)
		valFS:SetWidth(VAL_W)
		valFS:SetJustifyH("CENTER")
		valFS:SetTextColor(1, 1, 1, 1)

		local plusBtn = MakeBtn(cont, "+", BTN_W, 18)
		plusBtn:SetPoint("LEFT", valFS, "RIGHT", 2, 0)

		local function Refresh()
			valFS:SetText(tostring(OvlGet(key, default)))
		end
		Refresh()

		minusBtn:SetScript("OnClick", function()
			local v = OvlGet(key, default) - step
			if v < minVal then v = minVal end
			OvlSet(key, v)
			Refresh()
			if AmptieRaidTools_RefreshMTOverlayLayout then
				AmptieRaidTools_RefreshMTOverlayLayout()
			end
		end)
		plusBtn:SetScript("OnClick", function()
			local v = OvlGet(key, default) + step
			if v > maxVal then v = maxVal end
			OvlSet(key, v)
			Refresh()
			if AmptieRaidTools_RefreshMTOverlayLayout then
				AmptieRaidTools_RefreshMTOverlayLayout()
			end
		end)

		cont.Refresh = Refresh
		tinsert(ovlSpinRefreshFns, Refresh)
		return cont
	end

	-- Row 3: Width + Height
	local widthCtrl  = MakeSpinCtrl(panel, "Width:",  "frameW", 60,  300, 5,  120)
	local heightCtrl = MakeSpinCtrl(panel, "Height:", "frameH", 20,  80,  2,  36)
	widthCtrl:SetPoint( "TOPLEFT", mtDesc, "BOTTOMLEFT", 0,                          OVL_TOP_Y - 60)
	heightCtrl:SetPoint("TOPLEFT", mtDesc, "BOTTOMLEFT", OVL_SPIN_W + OVL_SPIN_GAP,  OVL_TOP_Y - 60)

	-- Row 4: Cols + Spacing + Color toggle
	local colsCtrl    = MakeSpinCtrl(panel, "Cols:",    "cols",    1,  8,   1,  4)
	local spacingCtrl = MakeSpinCtrl(panel, "Spacing:", "spacing", 0,  20,  1,  4)
	colsCtrl:SetPoint(   "TOPLEFT", mtDesc, "BOTTOMLEFT", 0,                          OVL_TOP_Y - 86)
	spacingCtrl:SetPoint("TOPLEFT", mtDesc, "BOTTOMLEFT", OVL_SPIN_W + OVL_SPIN_GAP,  OVL_TOP_Y - 86)

	local ovlColorBtn = MakeBtn(panel, "Green/Red", 84, 20)
	ovlColorBtn:SetPoint("LEFT", spacingCtrl, "RIGHT", OVL_SPIN_GAP, 0)

	local function UpdateOvlColorBtn()
		local cls = OvlGet("classColor", false)
		if cls then
			ovlColorBtn.fs:SetText("Class Color")
			ovlColorBtn:SetBackdropColor(0.08, 0.08, 0.20, 0.95)
			ovlColorBtn:SetBackdropBorderColor(0.35, 0.35, 0.75, 1)
			ovlColorBtn.fs:SetTextColor(0.5, 0.6, 1.0, 1)
		else
			ovlColorBtn.fs:SetText("Green/Red")
			ovlColorBtn:SetBackdropColor(0.08, 0.20, 0.08, 0.95)
			ovlColorBtn:SetBackdropBorderColor(0.35, 0.75, 0.35, 1)
			ovlColorBtn.fs:SetTextColor(0.4, 1.0, 0.4, 1)
		end
	end
	UpdateOvlColorBtn()

	ovlColorBtn:SetScript("OnClick", function()
		local v = not OvlGet("classColor", false)
		OvlSet("classColor", v)
		UpdateOvlColorBtn()
		if AmptieRaidTools_RefreshMTOverlayLayout then
			AmptieRaidTools_RefreshMTOverlayLayout()
		end
	end)

	-- Row 5: MT Targets section header
	local mtTgtHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mtTgtHdr:SetPoint("TOPLEFT", mtDesc, "BOTTOMLEFT", 0, OVL_TOP_Y - 116)
	mtTgtHdr:SetText("MT Targets")
	mtTgtHdr:SetTextColor(1, 0.82, 0, 1)

	-- Row 6: Show MT Targets checkbox
	local cbMTTargets = ART_CreateCheckbox(panel, "Show MT Targets")
	cbMTTargets:SetPoint("TOPLEFT", mtTgtHdr, "BOTTOMLEFT", 0, -4)
	cbMTTargets:SetChecked(OvlGet("showTargets", false))
	cbMTTargets.userOnClick = function()
		local v = cbMTTargets:GetChecked() and true or false
		OvlSet("showTargets", v)
		if AmptieRaidTools_RefreshMTOverlayLayout then
			AmptieRaidTools_RefreshMTOverlayLayout()
		end
	end

	-- Row 7: Target Width spin + Target color toggle
	local targetWidthCtrl = MakeSpinCtrl(panel, "Tgt Width:", "targetW", 40, 200, 5, 80)
	targetWidthCtrl:SetPoint("TOPLEFT", cbMTTargets, "BOTTOMLEFT", 0, -4)

	local tgtColorBtn = MakeBtn(panel, "Green/Red", 84, 20)
	tgtColorBtn:SetPoint("LEFT", targetWidthCtrl, "RIGHT", OVL_SPIN_GAP, 0)

	local function UpdateTgtColorBtn()
		local cls = OvlGet("targetClassColor", false)
		if cls then
			tgtColorBtn.fs:SetText("Class Color")
			tgtColorBtn:SetBackdropColor(0.08, 0.08, 0.20, 0.95)
			tgtColorBtn:SetBackdropBorderColor(0.35, 0.35, 0.75, 1)
			tgtColorBtn.fs:SetTextColor(0.5, 0.6, 1.0, 1)
		else
			tgtColorBtn.fs:SetText("Green/Red")
			tgtColorBtn:SetBackdropColor(0.08, 0.20, 0.08, 0.95)
			tgtColorBtn:SetBackdropBorderColor(0.35, 0.75, 0.35, 1)
			tgtColorBtn.fs:SetTextColor(0.4, 1.0, 0.4, 1)
		end
	end
	UpdateTgtColorBtn()

	tgtColorBtn:SetScript("OnClick", function()
		local v = not OvlGet("targetClassColor", false)
		OvlSet("targetClassColor", v)
		UpdateTgtColorBtn()
		if AmptieRaidTools_RefreshMTOverlayLayout then
			AmptieRaidTools_RefreshMTOverlayLayout()
		end
	end)

	RefreshOvlUI = function()
		UpdateOvlToggle()
		UpdateOvlLockBtn()
		UpdateOvlColorBtn()
		UpdateTgtColorBtn()
		cbMTTargets:SetChecked(OvlGet("showTargets", false))
		for i = 1, getn(ovlSpinRefreshFns) do
			ovlSpinRefreshFns[i]()
		end
	end

	-- RefreshMTUI: called when MT broadcast received from another client
	RefreshMTUI = function()
		local db = GetDB()
		if not db then return end
		for i = 1, NUM_MT_SLOTS do
			if mtEBs[i] then
				mtEBs[i]:SetText(db.mainTanks[i] or "")
			end
		end
	end

	-- ── OnShow: sync all UI from DB ────────────────────────────
	panel:SetScript("OnShow", function()
		RefreshAIRows()
		RefreshAARows()
		RefreshMTUI()
		UpdateAIToggle()
		if RefreshOvlUI then RefreshOvlUI() end
	end)

	AmptieRaidTools_RegisterComponent("raidassists", panel)
end

-- Global function called by key bindings: sets current target as MT[index]
function ART_SetMT(index)
    if not UnitExists("target") then return end
    if not UnitIsPlayer("target") then return end
    if not CanBroadcastMTs() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Cannot set MT: requires Raid Leader or Assist.")
        return
    end
    local db = amptieRaidToolsDB
    if not db or not db.raidAssists then return end
    if not db.raidAssists.mainTanks then db.raidAssists.mainTanks = {} end
    local name = UnitName("target")
    db.raidAssists.mainTanks[index] = name or ""
    if RefreshMTUI then RefreshMTUI() end
    if AmptieRaidTools_UpdateMTOverlay then AmptieRaidTools_UpdateMTOverlay() end
    BroadcastMTs(true)
end
