-- components/autobuffs.lua
-- AutoBuffs: automatic buff removal (Lua 5.0 / WoW 1.12 / TurtleWoW)
-- Independent of AutoBuffRemover.

local getn    = table.getn
local tinsert = table.insert

ART_BuffsList         = ART_BuffsList         or {}
ART_Profiles          = ART_Profiles          or {}
ART_Profiles["none"]  = ART_Profiles["none"]  or {}
ART_ActiveProfileName = ART_ActiveProfileName or "Standard"
ART_SpecBindings      = ART_SpecBindings      or {}
ART_SalvationOverride = ART_SalvationOverride or "profile"

local ART_AB_Categories = {
	{ cat = "Scrolls", buffs = {
		"Agility", "Intellect", "Protection", "Spirit", "Stamina", "Strength",
	}},
	{ cat = "Paladin", buffs = {
		"Blessing of Salvation",   "Greater Blessing of Salvation",
		"Blessing of Wisdom",      "Greater Blessing of Wisdom",
		"Blessing of Might",       "Greater Blessing of Might",
		"Blessing of Kings",       "Greater Blessing of Kings",
		"Blessing of Light",       "Greater Blessing of Light",
		"Blessing of Sanctuary",   "Greater Blessing of Sanctuary",
		"Daybreak",                "Holy Power",
	}},
	{ cat = "Priest", buffs = {
		"Power Word: Fortitude",   "Prayer of Fortitude",
		"Shadow Protection",       "Prayer of Shadow Protection",
		"Divine Spirit",           "Prayer of Spirit",
		"Renew",                   "Inspiration",
	}},
	{ cat = "Mage", buffs = {
		"Arcane Intellect",        "Arcane Brilliance",
		"Dampen Magic",            "Amplify Magic",
	}},
	{ cat = "Druid", buffs = {
		"Mark of the Wild",        "Gift of the Wild",
		"Thorns",                  "Rejuvenation",
		"Regrowth",                "Blessing of the Claw",
	}},
	{ cat = "Warlock", buffs = {
		"Detect Invisibility",     "Detect Greater Invisibility",
		"Detect Lesser Invisibility", "Unending Breath",
	}},
	{ cat = "Warrior", buffs = {
		"Battle Shout",
	}},
	{ cat = "Shaman", buffs = {
		"Water Walking",           "Water Breathing",
		"Spirit Link",             "Healing Way",
		"Ancestral Fortitude",     "Totemic Power",
	}},
}

-- ============================================================
-- Raid instance check (zone list analogous to InstanceTracker)
-- ============================================================

local ART_AB_RaidZones = {
	["Zul'Gurub"]            = true,
	["Tower of Karazhan"]    = true,
	["Ruins of Ahn'Qiraj"]   = true,
	["Temple of Ahn'Qiraj"]  = true,
	["Ahn'Qiraj"]            = true,
	["Molten Core"]          = true,
	["Blackwing Lair"]       = true,
	["Naxxramas"]            = true,
	["Emerald Sanctum"]      = true,
	["Onyxia's Lair"]        = true,
}

local function ART_AB_IsInRaid()
	if IsInInstance() ~= 1 then return false end
	local zone = GetRealZoneText()
	return zone and ART_AB_RaidZones[zone] and true or false
end

-- ============================================================
-- Buff removal (independent of UI)
-- ============================================================

-- Hidden tooltip frame for buff name lookup (WoW 1.12 trick)
local ART_ScanTip = CreateFrame("GameTooltip", "ART_ScanTip", nil, "GameTooltipTemplate")
ART_ScanTip:SetOwner(UIParent, "ANCHOR_NONE")

-- Get buff name at 0-based index
local function ART_AB_GetBuffName(index)
	ART_ScanTip:ClearLines()
	local x = UnitBuff("player", index + 1)
	if x then
		ART_ScanTip:SetPlayerBuff(index)
		return getglobal("ART_ScanTipTextLeft1"):GetText()
	end
end

-- Debounce: prevents duplicate chat messages when CancelPlayerBuff is async
local ART_AB_RemoveLog = {}

-- Remove buff at 0-based index
local function ART_AB_RemoveBuffByIndex(index)
	local buffName = ART_AB_GetBuffName(index)
	if buffName then
		CancelPlayerBuff(index)
		local now = GetTime()
		if not ART_AB_RemoveLog[buffName] or (now - ART_AB_RemoveLog[buffName]) > 2.0 then
			ART_AB_RemoveLog[buffName] = now
			DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Buff removed: " .. buffName)
		end
	end
end

-- Salvation buff names that can be overridden independently of the profile
local ART_AB_SALV_NAMES = {
	["Blessing of Salvation"]         = true,
	["Greater Blessing of Salvation"] = true,
}

-- Returns true if the named buff should be removed right now,
-- respecting the Salvation override setting
local function ART_AB_ShouldRemove(name)
	if ART_AB_SALV_NAMES[name] then
		local ov = ART_SalvationOverride or "profile"
		if ov == "allow"  then return false end
		if ov == "remove" then return true  end
		-- "profile": fall through to normal list check
	end
	return ART_BuffsList[name] and true or false
end

-- Single backward pass (stable indices during removal)
local function ART_AB_ScanOnce()
	for i = 40, 1, -1 do
		local name = ART_AB_GetBuffName(i)
		if name and ART_AB_ShouldRemove(name) then
			ART_AB_RemoveBuffByIndex(i)
		end
	end
end

-- Repeatedly scan until no matching buff remains (for profile activation)
local function ART_AB_ScanAndRemoveAll()
	local found = true
	local guard = 0
	while found and guard < 70 do
		found = false
		guard = guard + 1
		for i = 40, 1, -1 do
			local name = ART_AB_GetBuffName(i)
			if name and ART_AB_ShouldRemove(name) then
				ART_AB_RemoveBuffByIndex(i)
				found = true
			end
		end
	end
end

-- Throttle against event spam
local ART_AB_LastScan = 0
local ART_AB_ScanInterval = 0.2

-- PLAYER_AURAS_CHANGED: check on every player buff change
local auraFrame = CreateFrame("Frame", "ART_AB_AuraFrame", UIParent)
auraFrame:RegisterEvent("PLAYER_AURAS_CHANGED")
auraFrame:SetScript("OnEvent", function()
	local evt = event
	if evt == "PLAYER_AURAS_CHANGED" then
		local now = GetTime()
		if (now - ART_AB_LastScan) > ART_AB_ScanInterval then
			ART_AB_LastScan = now
			ART_AB_ScanOnce()
		end
	end
end)

-- ============================================================
-- Helper functions and spec binding logic (file-global)
-- ============================================================

local function ART_AB_ShallowCopy(src)
	local dst = {}
	for k, v in pairs(src) do dst[k] = v end
	return dst
end

-- Slots for UI callbacks (set by AmptieRaidTools_InitAutoBuffs)
local ART_AB_RestoreChecks_fn     = nil
local ART_AB_ProfileUI_Refresh_fn = nil

-- Activate profile by name (callable from UI and spec binding)
local function ART_AB_ActivateProfileByName(name)
	if not name or not ART_Profiles[name] then return end
	ART_ActiveProfileName = name
	for k in pairs(ART_BuffsList) do ART_BuffsList[k] = nil end
	for k, v in pairs(ART_Profiles[name]) do ART_BuffsList[k] = v end
	if ART_AB_RestoreChecks_fn     then ART_AB_RestoreChecks_fn()     end
	if ART_AB_ProfileUI_Refresh_fn then ART_AB_ProfileUI_Refresh_fn() end
	ART_AB_ScanAndRemoveAll()
end

-- Last detected spec (prevents repeated activation)
local ART_AB_LastBoundSpec = nil

-- After loading screen: reset trigger so the bound profile is reloaded once on next spec check
local enterWorldFrame = CreateFrame("Frame", "ART_AB_EnterWorldFrame", UIParent)
enterWorldFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
enterWorldFrame:SetScript("OnEvent", function()
	ART_AB_LastBoundSpec = nil
end)

-- Called by home.lua (AmptieRaidTools_RefreshSpecInBackground)
function ART_AB_OnSpecChanged(spec)
	if not spec or spec == "not specified" then
		ART_AB_LastBoundSpec = spec
		return
	end
	if spec == ART_AB_LastBoundSpec then return end
	ART_AB_LastBoundSpec = spec

	local binding = ART_SpecBindings[spec]
	if not binding then return end

	local targetProfile = nil
	if binding.mode == "raid" then
		if ART_AB_IsInRaid() then
			if binding.profile and binding.profile ~= "none" then
				targetProfile = binding.profile
			end
		else
			if binding.outProfile and binding.outProfile ~= "none" then
				targetProfile = binding.outProfile
			else
				-- No outProfile configured: deactivate auto-buffs when leaving raid
				targetProfile = "none"
			end
		end
	else
		if binding.profile and binding.profile ~= "none" then
			targetProfile = binding.profile
		end
	end

	if not targetProfile then return end
	if ART_ActiveProfileName == targetProfile then return end

	ART_AB_ActivateProfileByName(targetProfile)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Auto-Buffs: " .. spec .. " -> Auto-Profile: " .. targetProfile)
end

-- ============================================================
-- UI-Komponente
-- ============================================================

function AmptieRaidTools_InitAutoBuffs(body)
	local panel = CreateFrame("Frame", "AmptieRaidToolsAutoBuffsPanel", body)
	panel:SetAllPoints(body)

	-- Title
	local titleFS = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	titleFS:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
	titleFS:SetText("AutoBuffs")
	titleFS:SetTextColor(1, 0.82, 0, 1)

	-- Description
	local descFS = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	descFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -4)
	descFS:SetJustifyH("LEFT")
	descFS:SetWidth(560)
	descFS:SetText("Checked buffs are automatically removed when you receive them.")

	-- Profile row
	local profileLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	profileLabel:SetPoint("TOPLEFT", descFS, "BOTTOMLEFT", 0, -10)
	profileLabel:SetText("Profile:")
	profileLabel:SetTextColor(0.7, 0.7, 0.7, 1)

	local profileEdit = CreateFrame("EditBox", "ART_AB_ProfileEdit", panel)
	profileEdit:SetPoint("LEFT", profileLabel, "RIGHT", 6, 0)
	profileEdit:SetWidth(120)
	profileEdit:SetHeight(22)
	profileEdit:SetAutoFocus(false)
	profileEdit:SetMaxLetters(40)
	profileEdit:SetFontObject(GameFontHighlight)
	profileEdit:SetTextInsets(6, 6, 0, 0)
	profileEdit:SetBackdrop({
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 10,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	profileEdit:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
	profileEdit:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
	profileEdit:SetScript("OnEditFocusGained", function()
		this:SetBackdropBorderColor(1, 0.82, 0, 0.8)
	end)
	profileEdit:SetScript("OnEditFocusLost", function()
		this:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
	end)
	profileEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)

	-- Dropdown button (arrow down)
	local ddBtn = CreateFrame("Button", "ART_AB_DDBtn", panel)
	ddBtn:SetPoint("LEFT", profileEdit, "RIGHT", 2, 0)
	ddBtn:SetWidth(20)
	ddBtn:SetHeight(20)
	ddBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
	ddBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
	ddBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

	local BD = {
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	}

	-- Save
	local saveBtn = CreateFrame("Button", "ART_AB_SaveBtn", panel)
	saveBtn:SetPoint("LEFT", ddBtn, "RIGHT", 8, 0)
	saveBtn:SetWidth(60)
	saveBtn:SetHeight(22)
	saveBtn:SetBackdrop(BD)
	saveBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
	saveBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
	saveBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	local saveBtnFS = saveBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	saveBtnFS:SetPoint("CENTER", saveBtn, "CENTER", 0, 0)
	saveBtnFS:SetJustifyH("CENTER")
	saveBtnFS:SetText("Save")

	-- Activate
	local activateBtn = CreateFrame("Button", "ART_AB_ActivateBtn", panel)
	activateBtn:SetPoint("LEFT", saveBtn, "RIGHT", 4, 0)
	activateBtn:SetWidth(70)
	activateBtn:SetHeight(22)
	activateBtn:SetBackdrop(BD)
	activateBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
	activateBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
	activateBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	local activateBtnFS = activateBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	activateBtnFS:SetPoint("CENTER", activateBtn, "CENTER", 0, 0)
	activateBtnFS:SetJustifyH("CENTER")
	activateBtnFS:SetText("Activate")

	-- Delete
	local deleteBtn = CreateFrame("Button", "ART_AB_DeleteBtn", panel)
	deleteBtn:SetPoint("LEFT", activateBtn, "RIGHT", 4, 0)
	deleteBtn:SetWidth(60)
	deleteBtn:SetHeight(22)
	deleteBtn:SetBackdrop(BD)
	deleteBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
	deleteBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
	deleteBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	local deleteBtnFS = deleteBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	deleteBtnFS:SetPoint("CENTER", deleteBtn, "CENTER", 0, 0)
	deleteBtnFS:SetJustifyH("CENTER")
	deleteBtnFS:SetText("Delete")

	-- Active profile label
	local activeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	activeLabel:SetPoint("LEFT", deleteBtn, "RIGHT", 12, 0)
	activeLabel:SetJustifyH("LEFT")
	activeLabel:SetWidth(200)

	-- Dropdown list
	local DD_BACKDROP = {
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	}
	local ddList = CreateFrame("Frame", "ART_AB_DDList", panel)
	ddList:SetFrameStrata("TOOLTIP")
	ddList:SetWidth(150)
	ddList:SetBackdrop(DD_BACKDROP)
	ddList:SetBackdropColor(0.1, 0.1, 0.12, 0.98)
	ddList:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
	ddList:Hide()
	local ddItems = {}

	local function DDHide()
		ddList:Hide()
	end

	local function DDShow()
		for i = 1, getn(ddItems) do
			ddItems[i]:Hide()
		end
		local row = 0
		for name, _ in pairs(ART_Profiles) do
			row = row + 1
			local item = ddItems[row]
			if not item then
				item = CreateFrame("Button", nil, ddList)
				item:SetHeight(22)
				item:SetBackdrop({
					bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
					tile = true, tileSize = 16, edgeSize = 0,
					insets = { left = 0, right = 0, top = 0, bottom = 0 },
				})
				item:SetBackdropColor(0, 0, 0, 0)
				local fs = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
				fs:SetPoint("LEFT", item, "LEFT", 8, 0)
				item.fs = fs
				item:SetScript("OnEnter", function()
					this:SetBackdropColor(0.22, 0.22, 0.28, 0.9)
					this.fs:SetTextColor(1, 0.82, 0, 1)
				end)
				item:SetScript("OnLeave", function()
					this:SetBackdropColor(0, 0, 0, 0)
					this.fs:SetTextColor(1, 1, 1, 1)
				end)
				tinsert(ddItems, item)
			end
			item:ClearAllPoints()
			item:SetPoint("TOPLEFT", ddList, "TOPLEFT", 4, -4 - (row - 1) * 22)
			item:SetPoint("RIGHT", ddList, "RIGHT", -4, 0)
			local capName = name
			item.fs:SetText(capName)
			item.fs:SetTextColor(1, 1, 1, 1)
			item:SetScript("OnClick", function()
				profileEdit:SetText(capName)
				DDHide()
			end)
			item:Show()
		end
		local listH = row * 22 + 8
		if listH < 28 then listH = 28 end
		ddList:SetHeight(listH)
		ddList:ClearAllPoints()
		ddList:SetPoint("TOPLEFT", profileEdit, "BOTTOMLEFT", 0, -2)
		ddList:Show()
	end

	-- Plain ScrollFrame (provides clipping of scroll child; no template needed)
	local sf = CreateFrame("ScrollFrame", "ART_AB_ScrollFrame", panel)
	sf:SetPoint("TOPLEFT",     profileLabel, "BOTTOMLEFT",  0, -10)
	sf:SetPoint("BOTTOMRIGHT", panel,        "BOTTOMRIGHT", -22,  4)

	-- ScrollChild: content taller than sf, clipped by sf bounds
	local content = CreateFrame("Frame", "ART_AB_Content", sf)
	content:SetWidth(570)
	content:SetHeight(700)
	sf:SetScrollChild(content)
	content:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0)

	-- SF_H: approximate visible height of sf = panel(~530) - top offset(~102) - bottom(4)
	local SF_H         = 424
	local scrollOffset = 0
	local artAbSlider  -- forward reference; assigned after LayoutSpecRows

	local function SetScroll(val)
		local maxScroll = math.max(content:GetHeight() - SF_H, 0)
		if val < 0        then val = 0        end
		if val > maxScroll then val = maxScroll end
		scrollOffset = val
		content:ClearAllPoints()
		content:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, val)
	end

	-- Checkboxes in 2 columns
	local COL1_X  = 12
	local COL2_X  = 300
	local ROW_H   = 22
	local allCBs  = {}
	local cbIndex = 0
	local col1Y   = 0
	local col2Y   = 0

	for ci = 1, getn(ART_AB_Categories) do
		local entry = ART_AB_Categories[ci]
		local syncY = math.min(col1Y, col2Y) - 10
		col1Y = syncY
		col2Y = syncY

		local hdr = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		hdr:SetPoint("TOPLEFT", content, "TOPLEFT", COL1_X, col1Y)
		hdr:SetText(entry.cat)
		hdr:SetTextColor(1, 0.82, 0, 1)
		col1Y = col1Y - 20
		col2Y = col1Y

		local numBuffs = getn(entry.buffs)
		for bi = 1, numBuffs do
			local buffName = entry.buffs[bi]
			cbIndex = cbIndex + 1

			local useCol1 = (math.mod(bi, 2) == 1)
			local xOff = useCol1 and COL1_X or COL2_X
			local yOff = useCol1 and col1Y   or col2Y

			local cb = ART_CreateCheckbox(content, buffName)
			cb:SetPoint("TOPLEFT", content, "TOPLEFT", xOff, yOff)
			cb.buffName = buffName

			cb:SetChecked(ART_BuffsList[buffName])
			local cbRef = cb
			cb.userOnClick = function()
				if cbRef:GetChecked() then
					ART_BuffsList[cbRef.buffName] = 1
				else
					ART_BuffsList[cbRef.buffName] = nil
				end
			end

			if useCol1 then
				col1Y = col1Y - ROW_H
			else
				col2Y = col2Y - ROW_H
			end

			tinsert(allCBs, cb)
		end
	end

	-- Restore checkboxes from ART_BuffsList
	local function RestoreChecks()
		for i = 1, getn(allCBs) do
			local cb = allCBs[i]
			cb:SetChecked(ART_BuffsList[cb.buffName])
		end
	end
	ART_AB_RestoreChecks_fn = RestoreChecks

	-- Slot for RefreshSpecBindings (set later)
	local refreshSpecBindings_fn = nil

	-- Update profile display
	local function ProfileUI_Refresh()
		ART_Profiles["none"] = {}  -- always empty, always present
		if not ART_Profiles[ART_ActiveProfileName] then
			ART_ActiveProfileName = "none"
		end
		activeLabel:SetText("Active: " .. (ART_ActiveProfileName or "--"))
		profileEdit:SetText(ART_ActiveProfileName or "")
		if refreshSpecBindings_fn then refreshSpecBindings_fn() end
	end
	ART_AB_ProfileUI_Refresh_fn = ProfileUI_Refresh

	-- ============================================================
	-- Spec Bindings section (in scroll content, below checkboxes)
	-- ============================================================

	local ART_AB_SpecsByClass = {
		WARRIOR = { "Mortal Strike", "Fury + Sweeping Strikes", "Fury", "Fury Prot", "Tank", "Deep Prot" },
		PALADIN = { "Shockadin", "Retribution", "Holy", "Protection" },
		MAGE    = { "Arcane", "Fire", "Frost" },
		DRUID   = { "Balance", "Feral Cat", "Feral Bear", "Restoration" },
		ROGUE   = { "Assassination", "Combat", "Subtlety" },
		SHAMAN  = { "Elemental", "Spellhancer", "Enhancement", "Enhancement Tank", "Restoration" },
		HUNTER  = { "Beastmaster", "Marksman", "Survival" },
		PRIEST  = { "Discipline Smite", "Discipline Holy", "Holy", "Shadow" },
	}
	local _, playerClass = UnitClass("player")
	playerClass = playerClass and string.upper(tostring(playerClass)) or ""
	local ART_AB_KnownSpecs = ART_AB_SpecsByClass[playerClass] or {}

	local SB_BTN_BACKDROP = {
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	}

	-- Get next profile in cycle list
	local function GetNextProfile(current)
		local opts = {"none"}
		for name, _ in pairs(ART_Profiles) do
			tinsert(opts, name)
		end
		for i = 1, getn(opts) do
			if opts[i] == current then
				return opts[i + 1] or opts[1]
			end
		end
		return "none"
	end

	local specBindingRows = {}

	-- Spacing below checkboxes
	local sbBaseY = math.min(col1Y, col2Y) - 20

	-- Separator / Header
	local sbHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	sbHdr:SetPoint("TOPLEFT", content, "TOPLEFT", COL1_X, sbBaseY)
	sbHdr:SetText("Spec Bindings")
	sbHdr:SetTextColor(1, 0.82, 0, 1)

	local sbDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sbDesc:SetPoint("TOPLEFT", content, "TOPLEFT", COL1_X, sbBaseY - 22)
	sbDesc:SetWidth(540)
	sbDesc:SetJustifyH("LEFT")
	sbDesc:SetText("Link a spec to a profile. Click Profile to cycle it, click Condition to toggle between Always and Raid.")

	-- Column headers
	local sbC1 = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sbC1:SetPoint("TOPLEFT", content, "TOPLEFT", COL1_X, sbBaseY - 50)
	sbC1:SetText("Spec")
	sbC1:SetTextColor(0.7, 0.7, 0.7, 1)

	local sbC2 = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sbC2:SetPoint("TOPLEFT", content, "TOPLEFT", COL1_X + 160, sbBaseY - 50)
	sbC2:SetText("Profile")
	sbC2:SetTextColor(0.7, 0.7, 0.7, 1)

	local sbC3 = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sbC3:SetPoint("TOPLEFT", content, "TOPLEFT", COL1_X + 290, sbBaseY - 50)
	sbC3:SetText("Condition")
	sbC3:SetTextColor(0.7, 0.7, 0.7, 1)

	-- Start position of rows
	local sbRowsY = sbBaseY - 72

	-- Repositions all spec rows and updates content height
	local function LayoutSpecRows()
		local yOff = sbRowsY
		for i = 1, getn(specBindingRows) do
			local row = specBindingRows[i]
			row.specLbl:ClearAllPoints()
			row.specLbl:SetPoint("TOPLEFT", content, "TOPLEFT", COL1_X, yOff - 4)
			row.profileBtn:ClearAllPoints()
			row.profileBtn:SetPoint("TOPLEFT", content, "TOPLEFT", COL1_X + 160, yOff)
			row.modeBtn:ClearAllPoints()
			row.modeBtn:SetPoint("TOPLEFT", content, "TOPLEFT", COL1_X + 290, yOff)
			yOff = yOff - 26
			if row.outRow:IsShown() then
				row.outRow:ClearAllPoints()
				row.outRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
				yOff = yOff - 26
			end
		end
		local specSectionH = 22 + 32 + 22 + 20 + math.abs(sbRowsY - yOff) + 20
		local totalH = math.abs(math.min(col1Y, col2Y)) + 20 + specSectionH
		content:SetHeight(totalH)
		if artAbSlider then
			artAbSlider:SetMinMaxValues(0, math.max(totalH - SF_H, 0))
		end
	end

	for si = 1, getn(ART_AB_KnownSpecs) do
		local specName = ART_AB_KnownSpecs[si]

		-- Spec label (positioned by LayoutSpecRows)
		local specLbl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		specLbl:SetPoint("TOPLEFT", content, "TOPLEFT", COL1_X, sbRowsY)
		specLbl:SetWidth(150)
		specLbl:SetJustifyH("LEFT")
		specLbl:SetText(specName)

		-- Profile cycle button
		local profileBtn = CreateFrame("Button", nil, content)
		profileBtn:SetPoint("TOPLEFT", content, "TOPLEFT", COL1_X + 160, sbRowsY)
		profileBtn:SetWidth(120)
		profileBtn:SetHeight(22)
		profileBtn:SetBackdrop(SB_BTN_BACKDROP)
		profileBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
		profileBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
		profileBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		local profileFS = profileBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		profileFS:SetPoint("CENTER", profileBtn, "CENTER", 0, 0)
		profileFS:SetJustifyH("CENTER")
		profileBtn.fs = profileFS

		-- Condition toggle button
		local modeBtn = CreateFrame("Button", nil, content)
		modeBtn:SetPoint("TOPLEFT", content, "TOPLEFT", COL1_X + 290, sbRowsY)
		modeBtn:SetWidth(80)
		modeBtn:SetHeight(22)
		modeBtn:SetBackdrop(SB_BTN_BACKDROP)
		modeBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
		modeBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
		modeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		local modeFS = modeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		modeFS:SetPoint("CENTER", modeBtn, "CENTER", 0, 0)
		modeFS:SetJustifyH("CENTER")
		modeBtn.fs = modeFS

		-- Sub-row container: out of Raid condition (hidden by default)
		local outRow = CreateFrame("Frame", nil, content)
		outRow:SetWidth(500)
		outRow:SetHeight(22)
		outRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, sbRowsY)
		outRow:Hide()

		local outSpecLbl = outRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		outSpecLbl:SetPoint("TOPLEFT", outRow, "TOPLEFT", COL1_X + 20, -4)
		outSpecLbl:SetWidth(130)
		outSpecLbl:SetJustifyH("LEFT")
		outSpecLbl:SetText(specName)
		outSpecLbl:SetTextColor(0.6, 0.6, 0.6, 1)

		local outProfileBtn = CreateFrame("Button", nil, outRow)
		outProfileBtn:SetPoint("TOPLEFT", outRow, "TOPLEFT", COL1_X + 160, 0)
		outProfileBtn:SetWidth(120)
		outProfileBtn:SetHeight(22)
		outProfileBtn:SetBackdrop(SB_BTN_BACKDROP)
		outProfileBtn:SetBackdropColor(0.10, 0.10, 0.12, 0.95)
		outProfileBtn:SetBackdropBorderColor(0.28, 0.28, 0.35, 1)
		outProfileBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		local outProfileFS = outProfileBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		outProfileFS:SetPoint("CENTER", outProfileBtn, "CENTER", 0, 0)
		outProfileFS:SetJustifyH("CENTER")
		outProfileBtn.fs = outProfileFS

		local outCondLbl = outRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		outCondLbl:SetPoint("TOPLEFT", outRow, "TOPLEFT", COL1_X + 290, -4)
		outCondLbl:SetText("out of Raid")
		outCondLbl:SetTextColor(0.6, 0.6, 0.6, 1)
		outCondLbl:SetWidth(80)
		outCondLbl:SetJustifyH("CENTER")

		local capSpec = specName
		profileBtn:SetScript("OnClick", function()
			if not ART_SpecBindings[capSpec] then
				ART_SpecBindings[capSpec] = { profile = "none", mode = "always", outProfile = "none" }
			end
			local cur = ART_SpecBindings[capSpec].profile or "none"
			ART_SpecBindings[capSpec].profile = GetNextProfile(cur)
			this.fs:SetText(ART_SpecBindings[capSpec].profile)
		end)

		modeBtn:SetScript("OnClick", function()
			if not ART_SpecBindings[capSpec] then
				ART_SpecBindings[capSpec] = { profile = "none", mode = "always", outProfile = "none" }
			end
			local binding = ART_SpecBindings[capSpec]
			if binding.mode == "raid" then
				binding.mode = "always"
				this.fs:SetText("Always")
				outRow:Hide()
			else
				binding.mode = "raid"
				this.fs:SetText("Raid")
				outRow:Show()
			end
			LayoutSpecRows()
		end)

		outProfileBtn:SetScript("OnClick", function()
			if not ART_SpecBindings[capSpec] then
				ART_SpecBindings[capSpec] = { profile = "none", mode = "always", outProfile = "none" }
			end
			local cur = ART_SpecBindings[capSpec].outProfile or "none"
			ART_SpecBindings[capSpec].outProfile = GetNextProfile(cur)
			this.fs:SetText(ART_SpecBindings[capSpec].outProfile)
		end)

		tinsert(specBindingRows, {
			spec          = specName,
			specLbl       = specLbl,
			profileBtn    = profileBtn,
			modeBtn       = modeBtn,
			outRow        = outRow,
			outProfileBtn = outProfileBtn,
		})
	end

	LayoutSpecRows()

	-- Custom slider — same design as Raid Setups
	artAbSlider = CreateFrame("Slider", "ART_AB_Slider", panel)
	artAbSlider:SetOrientation("VERTICAL")
	artAbSlider:SetWidth(12)
	artAbSlider:SetPoint("TOPRIGHT",    sf, "TOPRIGHT",    18, 0)
	artAbSlider:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 18, 0)
	local abThumb = artAbSlider:CreateTexture(nil, "OVERLAY")
	abThumb:SetWidth(10)
	abThumb:SetHeight(24)
	abThumb:SetTexture(0.5, 0.5, 0.55, 0.9)
	artAbSlider:SetThumbTexture(abThumb)
	local abTrack = artAbSlider:CreateTexture(nil, "BACKGROUND")
	abTrack:SetAllPoints(artAbSlider)
	abTrack:SetTexture(0.12, 0.12, 0.15, 0.8)
	artAbSlider:SetMinMaxValues(0, math.max(content:GetHeight() - SF_H, 0))
	artAbSlider:SetValueStep(20)
	artAbSlider:SetValue(0)
	artAbSlider:SetScript("OnValueChanged", function()
		SetScroll(this:GetValue())
	end)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function()
		local delta    = arg1
		local maxScroll = math.max(content:GetHeight() - SF_H, 0)
		local newVal   = scrollOffset - delta * 30
		if newVal < 0        then newVal = 0        end
		if newVal > maxScroll then newVal = maxScroll end
		artAbSlider:SetValue(newVal)
	end)

	-- Update spec binding display
	local function RefreshSpecBindings()
		for i = 1, getn(specBindingRows) do
			local row = specBindingRows[i]
			local binding = ART_SpecBindings[row.spec]
			local profileName = (binding and binding.profile) or "none"
			local mode = (binding and binding.mode) or "always"
			local outProfile = (binding and binding.outProfile) or "none"
			-- Deleted profile: reset to none
			if profileName ~= "none" and not ART_Profiles[profileName] then
				profileName = "none"
				if binding then binding.profile = "none" end
			end
			if outProfile ~= "none" and not ART_Profiles[outProfile] then
				outProfile = "none"
				if binding then binding.outProfile = "none" end
			end
			row.profileBtn.fs:SetText(profileName)
			row.modeBtn.fs:SetText(mode == "raid" and "Raid" or "Always")
			if mode == "raid" then
				row.outRow:Show()
				row.outProfileBtn.fs:SetText(outProfile)
			else
				row.outRow:Hide()
			end
		end
		LayoutSpecRows()
	end
	refreshSpecBindings_fn = RefreshSpecBindings

	-- ============================================================
	-- Button-Handler
	-- ============================================================

	-- Dropdown button
	ddBtn:SetScript("OnClick", function()
		if ddList:IsShown() then
			DDHide()
		else
			DDShow()
		end
	end)

	-- Save: store current ART_BuffsList under profile name
	saveBtn:SetScript("OnClick", function()
		local name = profileEdit:GetText()
		if not name or name == "" then return end
		if name == "none" then return end
		ART_Profiles[name] = ART_AB_ShallowCopy(ART_BuffsList)
		ProfileUI_Refresh()
		profileEdit:SetText(name)
	end)

	-- Activate: load profile, update checkboxes and buffs
	activateBtn:SetScript("OnClick", function()
		local name = profileEdit:GetText()
		if not name or name == "" then return end
		ART_AB_ActivateProfileByName(name)
	end)

	-- Delete: remove profile
	deleteBtn:SetScript("OnClick", function()
		local name = profileEdit:GetText()
		if not name or name == "" then return end
		if name == "none" then return end
		ART_Profiles[name] = nil
		if ART_ActiveProfileName == name then
			ART_ActiveProfileName = "none"
		end
		ProfileUI_Refresh()
	end)

	-- On show: update checkboxes, profile label, spec bindings, and reset scroll
	panel:SetScript("OnShow", function()
		RestoreChecks()
		ProfileUI_Refresh()
		RefreshSpecBindings()
		artAbSlider:SetMinMaxValues(0, math.max(content:GetHeight() - SF_H, 0))
		artAbSlider:SetValue(0)
		SetScroll(0)
	end)

	AmptieRaidTools_RegisterComponent("autobuffs", panel)
end
