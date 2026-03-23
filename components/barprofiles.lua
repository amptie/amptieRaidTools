-- ============================================================
-- Bar Profiles: save/restore action bar layouts, linked to specs
-- No dependency on ActionBarProfiles or any other addon
-- Vanilla 1.12 / Lua 5.0 / TurtleWoW / SuperWoW
-- ============================================================

ART_BarProfiles          = ART_BarProfiles          or {}
ART_ActiveBarProfileName = ART_ActiveBarProfileName  or "none"
ART_BarSpecBindings      = ART_BarSpecBindings       or {}

ART_BarProfiles["none"] = ART_BarProfiles["none"] or {}

local getn    = table.getn
local tinsert = table.insert
local pairs   = pairs
local GetTime = GetTime

-- Save bars 1-6 (slots 1-72)
local ART_BP_MAX_SLOT = 72

-- ============================================================
-- Hidden tooltip for reading action slot names
-- ============================================================
local ART_BP_Tip = CreateFrame("GameTooltip", "ART_BP_Tip", UIParent, "GameTooltipTemplate")
ART_BP_Tip:SetOwner(UIParent, "ANCHOR_NONE")

local function ART_BP_TipLine(n)
	local f = getglobal("ART_BP_TipTextLeft" .. n)
	return f and f:GetText()
end

-- ============================================================
-- Read a single action slot (type + name)
-- ============================================================
local function ART_BP_GetSlotData(slot)
	if not HasAction(slot) then return nil end

	-- Macros: GetActionText is non-destructive and returns the macro name
	local mname = GetActionText(slot)
	if mname and mname ~= "" then
		return {t = "macro", n = mname}
	end

	-- Use tooltip to read the display name
	ART_BP_Tip:ClearLines()
	ART_BP_Tip:SetAction(slot)
	local name = ART_BP_TipLine(1)
	if not name or name == "" then return nil end

	-- Temporarily pick up to identify type, then immediately restore
	PickupAction(slot)
	local isSpell = CursorHasSpell()
	PlaceAction(slot)

	if isSpell then
		local rank = ART_BP_TipLine(2)
		if rank and string.find(rank, "^Rank") then
			return {t = "spell", n = name, r = rank}
		end
		return {t = "spell", n = name}
	end

	return {t = "item", n = name}
end

-- ============================================================
-- Capture current bars into a named profile
-- ============================================================
local function ART_BP_CaptureProfile(name)
	if not name or name == "" or name == "none" then return 0 end
	ART_BarProfiles[name] = {}
	local count = 0
	for i = 1, ART_BP_MAX_SLOT do
		local data = ART_BP_GetSlotData(i)
		if data then
			ART_BarProfiles[name][i] = data
			count = count + 1
		end
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Bar profile '" .. name .. "' captured: " .. count .. " slots")
	return count
end

-- ============================================================
-- Build lookup maps used during restore
-- ============================================================
local function ART_BP_BuildSpellMap()
	local map = {}
	for t = 1, MAX_SKILLLINE_TABS do
		local _, _, offset, numSpells = GetSpellTabInfo(t)
		if not offset then break end
		for s = 1, numSpells do
			local idx    = offset + s
			local sn, sr = GetSpellName(idx, BOOKTYPE_SPELL)
			if sn then
				map[sn] = idx  -- highest rank wins (tabs are low->high)
				if sr and sr ~= "" then
					map[sn .. "|" .. sr] = idx
				end
			end
		end
	end
	return map
end

local function ART_BP_BuildItemMap()
	local map = {}
	for bag = 0, NUM_BAG_SLOTS do
		for s = 1, GetContainerNumSlots(bag) do
			if GetContainerItemInfo(bag, s) then
				ART_BP_Tip:ClearLines()
				ART_BP_Tip:SetBagItem(bag, s)
				local n = ART_BP_TipLine(1)
				if n and not map[n] then
					map[n] = {bag = bag, slot = s}
				end
			end
		end
	end
	return map
end

-- ============================================================
-- Apply a profile: restore action bar slots from saved data
-- Handles spells, macros (native + SuperMacro), and items.
-- ============================================================
local function ART_BP_ApplyProfile(name)
	if not name or name == "none" or not ART_BarProfiles[name] then return end
	if UnitAffectingCombat("player") == 1 then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[aRT]|r Cannot apply bar profile while in combat.")
		return
	end

	local prof     = ART_BarProfiles[name]
	local spellMap = ART_BP_BuildSpellMap()
	local itemMap  = ART_BP_BuildItemMap()
	local applied  = 0
	local failList = {}

	ClearCursor()

	-- Helper: clear a slot before placing new content
	local function ClearSlot(i)
		if HasAction(i) then
			PickupAction(i)
			ClearCursor()
		end
	end

	-- Restore slot by slot.
	-- Spells and macros are always available → always replace the slot.
	-- Items: only replace if found in inventory; otherwise leave the slot as-is
	-- so that items picked up later in the session (e.g. raid drops) stay bound.
	for i = 1, ART_BP_MAX_SLOT do
		local d = prof[i]
		if d then
			if d.t == "spell" then
				local key = d.r and (d.n .. "|" .. d.r) or d.n
				local idx = spellMap[key] or spellMap[d.n]
				if idx then
					ClearSlot(i)
					PickupSpell(idx, BOOKTYPE_SPELL)
					PlaceAction(i)
					applied = applied + 1
				else
					tinsert(failList, d.n)
				end

			elseif d.t == "macro" then
				local idx = GetMacroIndexByName(d.n)
				if idx and idx > 0 then
					ClearSlot(i)
					PickupMacro(idx)
					PlaceAction(i)
					applied = applied + 1
				elseif type(GetSuperMacroInfo) == "function" then
					local sn = GetSuperMacroInfo(d.n)
					if sn then
						ClearSlot(i)
						PickupMacro(0, d.n)
						PlaceAction(i)
						applied = applied + 1
					else
						tinsert(failList, d.n .. " (macro)")
					end
				else
					tinsert(failList, d.n .. " (macro)")
				end

			elseif d.t == "item" then
				local loc = itemMap[d.n]
				if loc then
					ClearSlot(i)
					PickupContainerItem(loc.bag, loc.slot)
					PlaceAction(i)
					applied = applied + 1
				else
					-- Try equipped items
					local found = false
					for inv = 1, 19 do
						ART_BP_Tip:ClearLines()
						ART_BP_Tip:SetInventoryItem("player", inv)
						if ART_BP_TipLine(1) == d.n then
							ClearSlot(i)
							PickupInventoryItem(inv)
							PlaceAction(i)
							applied = applied + 1
							found = true
							break
						end
					end
					-- Item not in inventory: leave slot untouched
				end
			end
		end
	end

	ART_ActiveBarProfileName = name
	DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Bar Profile '" .. name .. "' applied: " .. applied .. " slots")
	if getn(failList) > 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[aRT]|r Bar Profile missing spells/macros: " .. table.concat(failList, ", "))
	end
end

-- ============================================================
-- Spec binding: raid-zone check
-- ============================================================
local ART_BP_RaidZones = {
	["Zul'Gurub"]=true, ["Tower of Karazhan"]=true, ["Ruins of Ahn'Qiraj"]=true,
	["Temple of Ahn'Qiraj"]=true, ["Ahn'Qiraj"]=true, ["Molten Core"]=true,
	["Blackwing Lair"]=true, ["Naxxramas"]=true, ["Emerald Sanctum"]=true,
	["Onyxia's Lair"]=true,
}
local function ART_BP_IsInRaid()
	if IsInInstance() ~= 1 then return false end
	local zone = GetRealZoneText()
	return zone and ART_BP_RaidZones[zone] and true or false
end

-- ============================================================
-- Spec binding: state
-- ============================================================
local ART_BP_SpecBindingUI_Refresh_fn = nil
local ART_BP_LastBoundSpec = nil

-- Reset after loading screen so the bound profile re-applies once on next spec check
local ART_BP_EnterWorldFrame = CreateFrame("Frame", "ART_BP_EnterWorldFrame", UIParent)
ART_BP_EnterWorldFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
ART_BP_EnterWorldFrame:SetScript("OnEvent", function()
	ART_BP_LastBoundSpec = nil
end)

function ART_BP_OnSpecChanged(spec)
	if not spec or spec == "not specified" then
		ART_BP_LastBoundSpec = spec
		return
	end
	if spec == ART_BP_LastBoundSpec then return end
	ART_BP_LastBoundSpec = spec

	local binding = ART_BarSpecBindings[spec]
	if not binding then return end

	local targetProfile = nil
	if binding.mode == "raid" then
		if ART_BP_IsInRaid() then
			if binding.profile and binding.profile ~= "none" then
				targetProfile = binding.profile
			end
		else
			if binding.outProfile and binding.outProfile ~= "none" then
				targetProfile = binding.outProfile
			end
		end
	else
		if binding.profile and binding.profile ~= "none" then
			targetProfile = binding.profile
		end
	end

	if not targetProfile then return end
	if ART_ActiveBarProfileName == targetProfile then return end

	ART_BP_ApplyProfile(targetProfile)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Bar Profile: " .. spec .. " -> Auto-Profile: " .. targetProfile)
end

-- ============================================================
-- UI
-- ============================================================
local ART_BP_SPECS_BY_CLASS = {
	WARRIOR = { "Mortal Strike", "Fury + Sweeping Strikes", "Fury", "Fury Prot", "Tank", "Deep Prot" },
	PALADIN = { "Shockadin", "Retribution", "Holy", "Protection" },
	MAGE    = { "Arcane", "Fire", "Frost" },
	DRUID   = { "Balance", "Feral Cat", "Feral Bear", "Restoration" },
	ROGUE   = { "Assassination", "Combat", "Subtlety" },
	SHAMAN  = { "Elemental", "Spellhancer", "Enhancement", "Enhancement Tank", "Restoration" },
	HUNTER  = { "Beastmaster", "Marksman", "Survival" },
	PRIEST  = { "Discipline Smite", "Discipline Holy", "Holy", "Shadow" },
}

local ART_BP_BTN_BD = {
	bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function AmptieRaidTools_InitBarProfiles(body)
	local _, playerClass = UnitClass("player")
	playerClass = playerClass and string.upper(tostring(playerClass)) or ""
	local knownSpecs = ART_BP_SPECS_BY_CLASS[playerClass] or {}

	local panel = CreateFrame("Frame", "AmptieRaidToolsBarProfilesPanel", body)
	panel:SetAllPoints(body)
	AmptieRaidTools_RegisterComponent("barprofiles", panel)

	local content = CreateFrame("Frame", "ART_BP_Content", panel)
	content:SetWidth(620)
	content:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)

	local X    = 10
	local yPos = -10

	-- Helper: create a styled button as child of content
	local function Btn(w, label)
		local btn = CreateFrame("Button", nil, content)
		btn:SetWidth(w)
		btn:SetHeight(22)
		btn:SetBackdrop(ART_BP_BTN_BD)
		btn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
		btn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
		btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
		fs:SetJustifyH("CENTER")
		fs:SetText(label)
		btn.fs = fs
		return btn
	end

	-- ── Header ──────────────────────────────────────────────
	local hdrFs = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	hdrFs:SetPoint("TOPLEFT", content, "TOPLEFT", X, yPos)
	hdrFs:SetText("Bar Profiles")
	hdrFs:SetTextColor(1, 0.82, 0, 1)
	yPos = yPos - 24

	local descFs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	descFs:SetPoint("TOPLEFT", content, "TOPLEFT", X, yPos)
	descFs:SetWidth(580)
	descFs:SetJustifyH("LEFT")
	descFs:SetText("Capture and restore action bar layouts (bars 1-6, slots 1-72). Supports spells, macros (incl. SuperCleveRoidMacros), and items. Link profiles to specs for automatic switching.")
	yPos = yPos - 40

	-- ── Profile name EditBox ─────────────────────────────────
	local profileEdit = CreateFrame("EditBox", "ART_BP_ProfileEdit", content)
	profileEdit:SetPoint("TOPLEFT", content, "TOPLEFT", X, yPos)
	profileEdit:SetWidth(160)
	profileEdit:SetHeight(24)
	profileEdit:SetAutoFocus(false)
	profileEdit:SetMaxLetters(32)
	profileEdit:SetFontObject(GameFontHighlight)
	profileEdit:SetTextInsets(6, 6, 0, 0)
	profileEdit:SetText("")
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

	-- Dropdown arrow button
	local ddBtn = CreateFrame("Button", "ART_BP_DDBtn", content)
	ddBtn:SetPoint("LEFT", profileEdit, "RIGHT", 2, 0)
	ddBtn:SetWidth(20)
	ddBtn:SetHeight(20)
	ddBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
	ddBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
	ddBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

	-- Dropdown list frame
	local DD_BACKDROP = {
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	}
	local ddList = CreateFrame("Frame", "ART_BP_DDList", panel)
	ddList:SetFrameStrata("TOOLTIP")
	ddList:SetWidth(160)
	ddList:SetBackdrop(DD_BACKDROP)
	ddList:SetBackdropColor(0.1, 0.1, 0.12, 0.98)
	ddList:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
	ddList:Hide()
	local ddItems = {}

	local function DDHide() ddList:Hide() end
	local function DDShow()
		for i = 1, getn(ddItems) do ddItems[i]:Hide() end
		local row = 0
		for name, _ in pairs(ART_BarProfiles) do
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
			item:SetPoint("RIGHT",   ddList, "RIGHT", -4, 0)
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
	ddBtn:SetScript("OnClick", function()
		if ddList:IsShown() then DDHide() else DDShow() end
	end)

	yPos = yPos - 30

	-- ── Buttons row ──────────────────────────────────────────
	local captureBtn = Btn(100, "Capture")
	captureBtn:SetPoint("TOPLEFT", content, "TOPLEFT", X, yPos)

	local applyBtn = Btn(70, "Apply")
	applyBtn:SetPoint("TOPLEFT", content, "TOPLEFT", X + 108, yPos)

	local deleteBtn = Btn(70, "Delete")
	deleteBtn:SetPoint("TOPLEFT", content, "TOPLEFT", X + 186, yPos)

	local activeLbl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	activeLbl:SetPoint("TOPLEFT", content, "TOPLEFT", X + 270, yPos - 4)
	activeLbl:SetTextColor(0.7, 0.7, 0.7, 1)
	activeLbl:SetText("Active: " .. (ART_ActiveBarProfileName or "none"))
	yPos = yPos - 36

	-- ── Separator ────────────────────────────────────────────
	local sep = content:CreateTexture(nil, "ARTWORK")
	sep:SetPoint("TOPLEFT", content, "TOPLEFT", X, yPos)
	sep:SetWidth(580)
	sep:SetHeight(1)
	sep:SetTexture(0.3, 0.3, 0.35, 0.8)
	yPos = yPos - 14

	local specSectionBaseY = yPos

	-- ── GetNextProfile cycles through ART_BarProfiles keys ──
	local function GetNextBarProfile(current)
		local opts = {"none"}
		for nm in pairs(ART_BarProfiles) do
			if nm ~= "none" then tinsert(opts, nm) end
		end
		for i = 1, getn(opts) do
			if opts[i] == current then return opts[i + 1] or opts[1] end
		end
		return "none"
	end

	-- ── Spec Bindings header ─────────────────────────────────
	local sbHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	sbHdr:SetPoint("TOPLEFT", content, "TOPLEFT", X, yPos)
	sbHdr:SetText("Spec Bindings")
	sbHdr:SetTextColor(1, 0.82, 0, 1)
	yPos = yPos - 22

	local sbDesc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sbDesc:SetPoint("TOPLEFT", content, "TOPLEFT", X, yPos)
	sbDesc:SetWidth(580)
	sbDesc:SetJustifyH("LEFT")
	sbDesc:SetText("Link a spec to a bar profile. Click Profile to cycle it, click Condition to toggle between Always and Raid.")
	yPos = yPos - 28

	local sbC1 = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sbC1:SetPoint("TOPLEFT", content, "TOPLEFT", X,       yPos)
	sbC1:SetText("Spec"); sbC1:SetTextColor(0.7, 0.7, 0.7, 1)

	local sbC2 = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sbC2:SetPoint("TOPLEFT", content, "TOPLEFT", X + 160, yPos)
	sbC2:SetText("Profile"); sbC2:SetTextColor(0.7, 0.7, 0.7, 1)

	local sbC3 = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sbC3:SetPoint("TOPLEFT", content, "TOPLEFT", X + 290, yPos)
	sbC3:SetText("Condition"); sbC3:SetTextColor(0.7, 0.7, 0.7, 1)
	yPos = yPos - 28

	local sbRowsY        = yPos
	local specBindingRows = {}

	-- Reposition all spec rows and update content height
	local function LayoutSpecRows()
		local yo = sbRowsY
		for i = 1, getn(specBindingRows) do
			local row = specBindingRows[i]
			row.specLbl:ClearAllPoints()
			row.specLbl:SetPoint("TOPLEFT", content, "TOPLEFT", X, yo - 4)
			row.profileBtn:ClearAllPoints()
			row.profileBtn:SetPoint("TOPLEFT", content, "TOPLEFT", X + 160, yo)
			row.modeBtn:ClearAllPoints()
			row.modeBtn:SetPoint("TOPLEFT", content, "TOPLEFT", X + 290, yo)
			yo = yo - 26
			if row.outRow:IsShown() then
				row.outRow:ClearAllPoints()
				row.outRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yo)
				yo = yo - 26
			end
		end
		content:SetHeight(math.abs(yo) + 20)
	end

	-- Build one row per spec
	for si = 1, getn(knownSpecs) do
		local specName = knownSpecs[si]

		local specLbl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		specLbl:SetPoint("TOPLEFT", content, "TOPLEFT", X, sbRowsY)
		specLbl:SetWidth(150); specLbl:SetJustifyH("LEFT")
		specLbl:SetText(specName)

		local profileBtn = CreateFrame("Button", nil, content)
		profileBtn:SetPoint("TOPLEFT", content, "TOPLEFT", X + 160, sbRowsY)
		profileBtn:SetWidth(120); profileBtn:SetHeight(22)
		profileBtn:SetBackdrop(ART_BP_BTN_BD)
		profileBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
		profileBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
		profileBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		local pFS = profileBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		pFS:SetPoint("CENTER", profileBtn, "CENTER", 0, 0); pFS:SetJustifyH("CENTER")
		profileBtn.fs = pFS

		local modeBtn = CreateFrame("Button", nil, content)
		modeBtn:SetPoint("TOPLEFT", content, "TOPLEFT", X + 290, sbRowsY)
		modeBtn:SetWidth(80); modeBtn:SetHeight(22)
		modeBtn:SetBackdrop(ART_BP_BTN_BD)
		modeBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
		modeBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
		modeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		local mFS = modeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		mFS:SetPoint("CENTER", modeBtn, "CENTER", 0, 0); mFS:SetJustifyH("CENTER")
		modeBtn.fs = mFS

		-- Sub-row container (shown only when mode == "raid")
		local outRow = CreateFrame("Frame", nil, content)
		outRow:SetWidth(500); outRow:SetHeight(22)
		outRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, sbRowsY)
		outRow:Hide()

		local outSpecLbl = outRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		outSpecLbl:SetPoint("TOPLEFT", outRow, "TOPLEFT", X + 20, -4)
		outSpecLbl:SetWidth(130); outSpecLbl:SetJustifyH("LEFT")
		outSpecLbl:SetText(specName); outSpecLbl:SetTextColor(0.6, 0.6, 0.6, 1)

		local outProfileBtn = CreateFrame("Button", nil, outRow)
		outProfileBtn:SetPoint("TOPLEFT", outRow, "TOPLEFT", X + 160, 0)
		outProfileBtn:SetWidth(120); outProfileBtn:SetHeight(22)
		outProfileBtn:SetBackdrop(ART_BP_BTN_BD)
		outProfileBtn:SetBackdropColor(0.10, 0.10, 0.12, 0.95)
		outProfileBtn:SetBackdropBorderColor(0.28, 0.28, 0.35, 1)
		outProfileBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		local opFS = outProfileBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		opFS:SetPoint("CENTER", outProfileBtn, "CENTER", 0, 0); opFS:SetJustifyH("CENTER")
		outProfileBtn.fs = opFS

		local outCondLbl = outRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		outCondLbl:SetPoint("TOPLEFT", outRow, "TOPLEFT", X + 290, -4)
		outCondLbl:SetWidth(80); outCondLbl:SetJustifyH("CENTER")
		outCondLbl:SetText("out of Raid"); outCondLbl:SetTextColor(0.6, 0.6, 0.6, 1)

		local capSpec = specName

		profileBtn:SetScript("OnClick", function()
			if not ART_BarSpecBindings[capSpec] then
				ART_BarSpecBindings[capSpec] = {profile = "none", mode = "always", outProfile = "none"}
			end
			local cur = ART_BarSpecBindings[capSpec].profile or "none"
			ART_BarSpecBindings[capSpec].profile = GetNextBarProfile(cur)
			this.fs:SetText(ART_BarSpecBindings[capSpec].profile)
		end)

		modeBtn:SetScript("OnClick", function()
			if not ART_BarSpecBindings[capSpec] then
				ART_BarSpecBindings[capSpec] = {profile = "none", mode = "always", outProfile = "none"}
			end
			local b = ART_BarSpecBindings[capSpec]
			if b.mode == "raid" then
				b.mode = "always"; this.fs:SetText("Always"); outRow:Hide()
			else
				b.mode = "raid"; this.fs:SetText("Raid"); outRow:Show()
			end
			LayoutSpecRows()
		end)

		outProfileBtn:SetScript("OnClick", function()
			if not ART_BarSpecBindings[capSpec] then
				ART_BarSpecBindings[capSpec] = {profile = "none", mode = "always", outProfile = "none"}
			end
			local cur = ART_BarSpecBindings[capSpec].outProfile or "none"
			ART_BarSpecBindings[capSpec].outProfile = GetNextBarProfile(cur)
			this.fs:SetText(ART_BarSpecBindings[capSpec].outProfile)
		end)

		tinsert(specBindingRows, {
			spec       = specName,
			specLbl    = specLbl,
			profileBtn = profileBtn,
			modeBtn    = modeBtn,
			outRow     = outRow,
			outProfileBtn = outProfileBtn,
		})
	end

	LayoutSpecRows()

	-- ── Refresh spec binding display ─────────────────────────
	local function RefreshBarSpecBindings()
		for i = 1, getn(specBindingRows) do
			local row  = specBindingRows[i]
			local b    = ART_BarSpecBindings[row.spec]
			local prof = (b and b.profile)    or "none"
			local mode = (b and b.mode)       or "always"
			local outp = (b and b.outProfile) or "none"
			-- Reset bindings that point to deleted profiles
			if prof ~= "none" and not ART_BarProfiles[prof] then
				prof = "none"; if b then b.profile = "none" end
			end
			if outp ~= "none" and not ART_BarProfiles[outp] then
				outp = "none"; if b then b.outProfile = "none" end
			end
			row.profileBtn.fs:SetText(prof)
			row.modeBtn.fs:SetText(mode == "raid" and "Raid" or "Always")
			if mode == "raid" then
				row.outRow:Show()
				row.outProfileBtn.fs:SetText(outp)
			else
				row.outRow:Hide()
			end
		end
		LayoutSpecRows()
	end
	ART_BP_SpecBindingUI_Refresh_fn = RefreshBarSpecBindings

	-- ── Button handlers ──────────────────────────────────────
	captureBtn:SetScript("OnClick", function()
		local name = profileEdit:GetText()
		if not name or name == "" then
			DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[aRT]|r Enter a profile name first.")
			return
		end
		if name == "none" then
			DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[aRT]|r 'none' is reserved.")
			return
		end
		ART_BP_CaptureProfile(name)
		ART_ActiveBarProfileName = name
		activeLbl:SetText("Active: " .. name)
		profileEdit:SetText(name)
		RefreshBarSpecBindings()
	end)

	applyBtn:SetScript("OnClick", function()
		local name = profileEdit:GetText()
		if not name or name == "" then return end
		if not ART_BarProfiles[name] then
			DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[aRT]|r Profile '" .. name .. "' not found.")
			return
		end
		ART_BP_ApplyProfile(name)
		activeLbl:SetText("Active: " .. ART_ActiveBarProfileName)
		RefreshBarSpecBindings()
	end)

	deleteBtn:SetScript("OnClick", function()
		local name = profileEdit:GetText()
		if not name or name == "" or name == "none" then return end
		if not ART_BarProfiles[name] then return end
		ART_BarProfiles[name] = nil
		for _, b in pairs(ART_BarSpecBindings) do
			if b.profile    == name then b.profile    = "none" end
			if b.outProfile == name then b.outProfile = "none" end
		end
		if ART_ActiveBarProfileName == name then
			ART_ActiveBarProfileName = "none"
			activeLbl:SetText("Active: none")
		end
		DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Bar profile '" .. name .. "' deleted.")
		RefreshBarSpecBindings()
	end)

	-- Initial display refresh
	RefreshBarSpecBindings()
end
