-- ============================================================
-- Bar Profiles: save/restore action bar layouts, linked to specs
-- No dependency on ActionBarProfiles or any other addon
-- Vanilla 1.12 / Lua 5.0 / TurtleWoW / SuperWoW
-- ============================================================

ART_BarProfiles          = ART_BarProfiles          or {}
ART_ActiveBarProfileName = ART_ActiveBarProfileName  or "none"
ART_BarSpecBindings      = ART_BarSpecBindings       or {}
ART_ItemSetBindings      = ART_ItemSetBindings       or {}

ART_BarProfiles["none"] = ART_BarProfiles["none"] or {}

local getn    = table.getn
local tinsert = table.insert
local pairs   = pairs
local GetTime = GetTime
local strfind = string.find

-- WoW 1.12: Slots 1–72 = 6 standard bars (12 each); 73–120 = stance/form/bonus bars;
-- 121–144 = extra bars.  RingMenu and similar addons can map buttons to higher slots
-- (RingMenu default startPageID=13 → slots 13–24, but configurable).  Use 180 to
-- cover up to page 15, matching any realistic RingMenu or Bartender configuration.
local ART_BP_MAX_SLOT = 180

local ART_BP_SPECS_BY_CLASS = {
	WARRIOR = { "Arms", "Fury Sweeping Strikes", "Fury", "Fury Two-Handed", "Fury Protection", "Protection", "Deep Protection" },
	PALADIN = { "Shockadin", "Retribution", "Holy", "Protection" },
	MAGE    = { "Arcane", "Fire", "Frost" },
	DRUID   = { "Balance", "Feral Cat", "Feral Bear", "Restoration" },
	ROGUE   = { "Assassination", "Combat", "Subtlety" },
	SHAMAN  = { "Elemental", "Spellhancer", "Spellhancer Tank", "Enhancement", "Enhancement Tank", "Restoration" },
	HUNTER  = { "Beastmaster", "Marksman", "Survival" },
	PRIEST  = { "Discipline Smite", "Discipline Holy", "Holy", "Shadow" },
	WARLOCK = { "SM/Ruin", "Affliction", "Demonology", "Destruction Fire" },
}

-- ============================================================
-- Hidden tooltip for reading action slot names
-- ============================================================
local ART_BP_Tip = CreateFrame("GameTooltip", "ART_BP_Tip", UIParent, "GameTooltipTemplate")
ART_BP_Tip:SetOwner(UIParent, "ANCHOR_NONE")

local function ART_BP_TipLine(n)
	local f = getglobal("ART_BP_TipTextLeft" .. n)
	return f and f:GetText()
end

local function ART_BP_TipRightLine(n)
	local f = getglobal("ART_BP_TipTextRight" .. n)
	if not f or not f:IsShown() then return nil end
	local t = f:GetText()
	if t and t ~= "" then return t end
	return nil
end

-- ============================================================
-- Build a fast-lookup set of all known spell names (used during capture)
-- ============================================================
local function ART_BP_BuildSpellNameSet()
	local set = {}
	for t = 1, MAX_SKILLLINE_TABS do
		local _, _, offset, numSpells = GetSpellTabInfo(t)
		if not offset then break end
		for s = 1, numSpells do
			local sn = GetSpellName(offset + s, BOOKTYPE_SPELL)
			if sn then set[sn] = true end
		end
	end
	return set
end

-- ============================================================
-- Read a single action slot (type + name) — NO cursor interaction
-- ============================================================
-- Using PickupAction/PlaceAction to detect spell vs item is fragile:
-- some slots (stance bars in the wrong stance, bonus bars, etc.) silently
-- reject PickupAction or PlaceAction, leaving the cursor dirty and causing
-- every subsequent PickupAction to SWAP instead of pick up, cascading corrupt
-- data for all remaining slots.  Instead we read the tooltip non-destructively
-- and compare the name against the spellbook to determine the type.
local function ART_BP_GetSlotData(slot, spellSet)
	if not HasAction(slot) then return nil end

	-- Macros: GetActionText is non-destructive and returns the macro name
	local mname = GetActionText(slot)
	if mname and mname ~= "" then
		return {t = "macro", n = mname}
	end

	-- Read the action name via hidden tooltip (no PickupAction needed).
	-- SetOwner must be called before every Set* call in WoW 1.12: without it
	-- the tooltip silently stops returning data after the first capture run.
	ART_BP_Tip:SetOwner(UIParent, "ANCHOR_NONE")
	ART_BP_Tip:SetAction(slot)
	local name = ART_BP_TipLine(1)
	if not name or name == "" then return nil end

	if spellSet[name] then
		-- Known spell — capture rank if the tooltip shows one
		local rank = ART_BP_TipLine(2)
		if rank and string.find(rank, "^Rank") then
			return {t = "spell", n = name, r = rank}
		end
		rank = ART_BP_TipRightLine(1)
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
	local spellSet = ART_BP_BuildSpellNameSet()
	ART_BarProfiles[name] = {}
	local count = 0
	for i = 1, ART_BP_MAX_SLOT do
		local data = ART_BP_GetSlotData(i, spellSet)
		if data then
			ART_BarProfiles[name][i] = data
			count = count + 1
		else
			ART_BarProfiles[name][i] = { t = "empty" }
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
				-- SetOwner required before every Set* call in WoW 1.12
				ART_BP_Tip:SetOwner(UIParent, "ANCHOR_NONE")
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

	-- Restore slot by slot.
	-- Pattern: ClearCursor() before every pickup, ClearCursor() after every
	-- PlaceAction.  This ensures a dirty cursor from one slot never cascades
	-- into the next (PlaceAction swaps if the slot is non-empty; the post-clear
	-- discards the old content cleanly).
	-- Spells and macros are always available → always replace the slot.
	-- Items: only replace if found in inventory; otherwise leave the slot as-is.
	for i = 1, ART_BP_MAX_SLOT do
		local d = prof[i]
		if d then
			if d.t == "empty" then
				if HasAction(i) then
					ClearCursor()
					PickupAction(i)
					ClearCursor()
				end

			elseif d.t == "spell" then
				local key = d.r and (d.n .. "|" .. d.r) or d.n
				local idx = spellMap[key] or spellMap[d.n]
				if idx then
					ClearCursor()
					PickupSpell(idx, BOOKTYPE_SPELL)
					PlaceAction(i)
					ClearCursor()
					applied = applied + 1
				else
					tinsert(failList, d.n)
				end

			elseif d.t == "macro" then
				local idx = GetMacroIndexByName(d.n)
				if idx and idx > 0 then
					ClearCursor()
					PickupMacro(idx)
					PlaceAction(i)
					ClearCursor()
					applied = applied + 1
				elseif type(GetSuperMacroInfo) == "function" then
					local sn = GetSuperMacroInfo(d.n)
					if sn then
						ClearCursor()
						PickupMacro(0, d.n)
						PlaceAction(i)
						ClearCursor()
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
					ClearCursor()
					PickupContainerItem(loc.bag, loc.slot)
					PlaceAction(i)
					ClearCursor()
					applied = applied + 1
				else
					-- Try equipped items
					for inv = 1, 19 do
						ART_BP_Tip:SetOwner(UIParent, "ANCHOR_NONE")
						ART_BP_Tip:SetInventoryItem("player", inv)
						if ART_BP_TipLine(1) == d.n then
							ClearCursor()
							PickupInventoryItem(inv)
							PlaceAction(i)
							ClearCursor()
							applied = applied + 1
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
-- Equipment-set addon helpers (ItemRack / Outfitter)
-- ============================================================
-- Holds the deferred item-set section builder; called at PLAYER_LOGIN so all
-- addon globals (Outfitter_WearOutfit, ItemRack_EquipSet, …) are guaranteed loaded.
local ART_BP_BuildItemSection_fn = nil

-- Returns sorted array of user set names from whichever addon(s) are installed.
-- Called lazily (at button click or spec change) so SavedVariables are ready.
local function ART_BP_GetEquipSets()
	local sets = {}
	local n = 0
	-- ItemRack: Rack_User[user].Sets is a hash keyed by set name
	if ItemRack_GetUserSets then
		local rawSets = ItemRack_GetUserSets()
		if rawSets then
			for name in pairs(rawSets) do
				if not strfind(name, "^ItemRack") and not strfind(name, "^Rack%-") then
					n = n + 1; sets[n] = name
				end
			end
		end
	end
	-- Outfitter: iterate categories, each holds an indexed array of outfit objects
	if Outfitter_GetCategoryOrder and gOutfitter_Settings then
		local cats = Outfitter_GetCategoryOrder()
		if cats then
			for ci = 1, getn(cats) do
				local outfits = Outfitter_GetOutfitsByCategoryID(cats[ci])
				if outfits then
					for oi = 1, getn(outfits) do
						local outfit = outfits[oi]
						if outfit and outfit.Name and not outfit.Disabled then
							n = n + 1; sets[n] = outfit.Name
						end
					end
				end
			end
		end
	end
	sets.n = n
	table.sort(sets)
	return sets
end

-- Equip a named set via whichever addon owns it.
local function ART_BP_EquipItemSet(name)
	if not name or name == "none" then return end
	-- ItemRack
	if ItemRack_EquipSet and ItemRack_GetUserSets then
		local rawSets = ItemRack_GetUserSets()
		if rawSets and rawSets[name] then
			ItemRack_EquipSet(name)
			return
		end
	end
	-- Outfitter: need to find the outfit object by name to pass to WearOutfit
	if Outfitter_WearOutfit and Outfitter_GetCategoryOrder and gOutfitter_Settings then
		local cats = Outfitter_GetCategoryOrder()
		if cats then
			for ci = 1, getn(cats) do
				local catID  = cats[ci]
				local outfits = Outfitter_GetOutfitsByCategoryID(catID)
				if outfits then
					for oi = 1, getn(outfits) do
						local outfit = outfits[oi]
						if outfit and outfit.Name == name then
							Outfitter_WearOutfit(outfit, catID)
							return
						end
					end
				end
			end
		end
	end
end

-- ============================================================
-- Spec binding: state
-- ============================================================
local ART_BP_SpecBindingUI_Refresh_fn = nil
local ART_BP_LastBoundSpec      = nil
local ART_BP_SkipItemSetEquip   = false  -- true on login/reload; cleared after first real spec check

-- Reset after loading screen so the bound profile re-applies once on next spec check
local ART_BP_EnterWorldFrame = CreateFrame("Frame", "ART_BP_EnterWorldFrame", UIParent)
ART_BP_EnterWorldFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
ART_BP_EnterWorldFrame:SetScript("OnEvent", function()
	ART_BP_LastBoundSpec    = nil
	ART_BP_SkipItemSetEquip = true  -- suppress item set equip until an actual respec happens

	-- Remove spec bindings that don't belong to the current class
	if ART_BarSpecBindings then
		local _, playerClass = UnitClass("player")
		playerClass = playerClass and string.upper(playerClass) or ""
		local validSpecs = ART_BP_SPECS_BY_CLASS[playerClass]
		if validSpecs then
			-- Build fast lookup set of valid specs for this class
			local validSet = {}
			for i = 1, getn(validSpecs) do validSet[validSpecs[i]] = true end
			for spec in pairs(ART_BarSpecBindings) do
				if not validSet[spec] then
					ART_BarSpecBindings[spec] = nil
				end
			end
		else
			-- Unknown class: wipe all bindings
			for spec in pairs(ART_BarSpecBindings) do
				ART_BarSpecBindings[spec] = nil
			end
		end
	end
end)

function ART_BP_OnSpecChanged(spec)
	if not spec or spec == "not specified" then
		ART_BP_LastBoundSpec = spec
		return
	end
	if spec == ART_BP_LastBoundSpec then return end
	local wasSkipping       = ART_BP_SkipItemSetEquip
	ART_BP_LastBoundSpec    = spec
	ART_BP_SkipItemSetEquip = false   -- clear after first real spec detected

	-- ── Bar profile ──────────────────────────────────────────
	local binding = ART_BarSpecBindings[spec]
	if binding then
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
		if targetProfile and ART_ActiveBarProfileName ~= targetProfile then
			ART_BP_ApplyProfile(targetProfile)
			DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Bar Profile: " .. spec .. " -> " .. targetProfile)
		end
	end

	-- ── Item set (Outfitter / ItemRack) ──────────────────────
	if wasSkipping then return end   -- login/reload: skip equip, bar profile already applied
	local isb = ART_ItemSetBindings and ART_ItemSetBindings[spec]
	if isb then
		local setToEquip = nil
		if type(isb) == "string" then
			if isb ~= "none" then setToEquip = isb end
		else
			local mode = isb.mode or "always"
			if mode == "raid" then
				if ART_BP_IsInRaid() then
					if isb.set and isb.set ~= "none" then setToEquip = isb.set end
				else
					if isb.outSet and isb.outSet ~= "none" then setToEquip = isb.outSet end
				end
			else
				if isb.set and isb.set ~= "none" then setToEquip = isb.set end
			end
		end
		if setToEquip then
			ART_BP_EquipItemSet(setToEquip)
			DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Item Set: " .. spec .. " -> " .. setToEquip)
		end
	end
end

-- ============================================================
-- UI
-- ============================================================

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
	descFs:SetText("Capture and restore action bar layouts. Supports spells, macros (incl. SuperCleveRoidMacros), and items. Link profiles to specs for automatic switching.")
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
	if ART_RegisterPopup then ART_RegisterPopup(ddList) end
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
	local itemSetSection  = nil   -- forward ref; assigned after item-set section is built

	-- Reposition all spec rows (and the item-set section below them) + update content height
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
		-- Reposition item-set section immediately below spec rows
		if itemSetSection then
			yo = yo - 16
			itemSetSection:ClearAllPoints()
			itemSetSection:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yo)
			yo = yo - itemSetSection:GetHeight()
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

	-- ── Item Set Bindings section (Outfitter / ItemRack) ─────
	-- Detection is deferred to PLAYER_LOGIN (all addons are loaded by then).
	-- The closure captures content, X, knownSpecs, itemSetSection, LayoutSpecRows.
	ART_BP_BuildItemSection_fn = function()
		ART_BP_BuildItemSection_fn = nil   -- one-shot

		local hasItemRack  = (ItemRack_EquipSet    ~= nil)
		local hasOutfitter = (Outfitter_WearOutfit ~= nil)
		if not hasItemRack and not hasOutfitter then return end

		-- Addon title for the header
		local addonTitle
		if hasItemRack and hasOutfitter then
			addonTitle = "ItemRack / Outfitter"
		elseif hasItemRack then
			addonTitle = "ItemRack"
		else
			addonTitle = "Outfitter"
		end

		-- Section container (anchored dynamically by LayoutSpecRows)
		local isFrame = CreateFrame("Frame", nil, content)
		isFrame:SetWidth(600)

		local isy = 0   -- internal Y cursor (negative = downward)

		-- Separator line
		local isSep = isFrame:CreateTexture(nil, "ARTWORK")
		isSep:SetPoint("TOPLEFT", isFrame, "TOPLEFT", X, isy)
		isSep:SetWidth(580); isSep:SetHeight(1)
		isSep:SetTexture(0.3, 0.3, 0.35, 0.8)
		isy = isy - 14

		-- Section header (addon name)
		local isHdr = isFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		isHdr:SetPoint("TOPLEFT", isFrame, "TOPLEFT", X, isy)
		isHdr:SetText(addonTitle)
		isHdr:SetTextColor(1, 0.82, 0, 1)
		isy = isy - 26

		-- Description
		local isDesc = isFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		isDesc:SetPoint("TOPLEFT", isFrame, "TOPLEFT", X, isy)
		isDesc:SetWidth(580); isDesc:SetJustifyH("LEFT")
		isDesc:SetText("Bind your item sets to your specific specs. The set will be equipped automatically on spec change.")
		isy = isy - 24

		-- Column headers
		local isC1 = isFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		isC1:SetPoint("TOPLEFT", isFrame, "TOPLEFT", X, isy)
		isC1:SetText("Spec"); isC1:SetTextColor(0.7, 0.7, 0.7, 1)

		local isC2 = isFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		isC2:SetPoint("TOPLEFT", isFrame, "TOPLEFT", X + 160, isy)
		isC2:SetText("Item Set"); isC2:SetTextColor(0.7, 0.7, 0.7, 1)

		local isC3 = isFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		isC3:SetPoint("TOPLEFT", isFrame, "TOPLEFT", X + 290, isy)
		isC3:SetText("Condition"); isC3:SetTextColor(0.7, 0.7, 0.7, 1)
		isy = isy - 24

		local isRowsStartY = isy   -- save for LayoutItemSetRows

		-- Shared dropdown for all set-picker buttons (max 7 visible, mouse-wheel scroll)
		local IS_DD_MAX  = 7
		local IS_ROW_H   = 22

		local isDD = CreateFrame("Frame", nil, UIParent)
		if ART_RegisterPopup then ART_RegisterPopup(isDD) end
		isDD:SetFrameStrata("TOOLTIP")
		isDD:SetWidth(120)
		isDD:SetBackdrop({
			bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		isDD:SetBackdropColor(0.08, 0.08, 0.10, 1)
		isDD:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
		isDD:Hide()

		local isDDOwner   = nil    -- spec name whose dropdown is open
		local isDDAnchor  = nil    -- the set-button that triggered the open
		local isDDField   = "set"  -- "set" or "outSet"
		local isDDEntries = {}     -- full entry list (populated on open)
		isDDEntries.n     = 0
		local isDDOffset  = 0      -- first visible entry index (0-based)
		local isDDItems   = {}     -- exactly IS_DD_MAX pre-created row buttons

		-- Pre-create the fixed pool of row buttons
		for i = 1, IS_DD_MAX do
			local item = CreateFrame("Button", nil, isDD)
			item:SetHeight(IS_ROW_H)
			item:SetPoint("TOPLEFT", isDD, "TOPLEFT", 4,  -4 - (i - 1) * IS_ROW_H)
			item:SetPoint("RIGHT",   isDD, "RIGHT",  -4, 0)
			item:SetBackdrop({
				bgFile  = "Interface\\ChatFrame\\ChatFrameBackground",
				tile = true, tileSize = 16, edgeSize = 0,
				insets = { left = 0, right = 0, top = 0, bottom = 0 },
			})
			item:SetBackdropColor(0, 0, 0, 0)
			local fs = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			fs:SetPoint("LEFT", item, "LEFT", 8, 0)
			item.fs = fs
			item:SetScript("OnEnter", function()
				this:SetBackdropColor(0.22, 0.22, 0.30, 1)
				this.fs:SetTextColor(1, 0.82, 0, 1)
			end)
			item:SetScript("OnLeave", function()
				this:SetBackdropColor(0, 0, 0, 0)
				local txt     = this.fs:GetText()
				local binding = isDDOwner and ART_ItemSetBindings[isDDOwner]
				local cur     = (binding and binding[isDDField]) or "none"
				if cur == txt then
					this.fs:SetTextColor(1, 0.82, 0, 1)
				else
					this.fs:SetTextColor(1, 1, 1, 1)
				end
			end)
			item:Hide()
			isDDItems[i] = item
		end

		local function IsDDHide()
			isDD:Hide()
			isDDOwner  = nil
			isDDAnchor = nil
		end

		-- Render the visible window [offset+1 .. offset+IS_DD_MAX]
		local function IsDDRender()
			local n        = getn(isDDEntries)
			local capSpec  = isDDOwner
			local capAnch  = isDDAnchor
			local capField = isDDField
			for i = 1, IS_DD_MAX do
				local item = isDDItems[i]
				local ei   = isDDOffset + i
				if ei <= n then
					local capEntry = isDDEntries[ei]
					item.fs:SetText(capEntry)
					local binding = ART_ItemSetBindings[capSpec]
					if ((binding and binding[capField]) or "none") == capEntry then
						item.fs:SetTextColor(1, 0.82, 0, 1)
					else
						item.fs:SetTextColor(1, 1, 1, 1)
					end
					item:SetScript("OnClick", function()
						if not ART_ItemSetBindings[capSpec] then
							ART_ItemSetBindings[capSpec] = { set = "none", mode = "always", outSet = "none" }
						end
						ART_ItemSetBindings[capSpec][capField] = capEntry
						capAnch.fs:SetText(capEntry)
						IsDDHide()
					end)
					item:Show()
				else
					item:Hide()
				end
			end
		end

		-- Mouse wheel: scroll without a visible scrollbar
		isDD:EnableMouseWheel(true)
		isDD:SetScript("OnMouseWheel", function()
			local n         = getn(isDDEntries)
			local maxOffset = math.max(0, n - IS_DD_MAX)
			-- arg1: +1 = scroll up (show earlier entries), -1 = scroll down
			isDDOffset = math.max(0, math.min(maxOffset, isDDOffset - arg1))
			IsDDRender()
		end)

		local function IsDDShow(anchorBtn, specName, field)
			-- Toggle: clicking the same button+field again closes it
			if isDDOwner == specName and isDDField == (field or "set") and isDD:IsShown() then
				IsDDHide(); return
			end
			isDDOwner  = specName
			isDDAnchor = anchorBtn
			isDDField  = field or "set"
			isDDOffset = 0

			-- Rebuild entry list: "none" first, then all sets sorted
			for k in pairs(isDDEntries) do isDDEntries[k] = nil end
			isDDEntries.n = 0
			tinsert(isDDEntries, "none")
			local sets = ART_BP_GetEquipSets()
			for i = 1, getn(sets) do tinsert(isDDEntries, sets[i]) end

			-- Scroll to put the currently selected entry in view
			local binding = ART_ItemSetBindings[specName]
			local current = (binding and binding[isDDField]) or "none"
			for i = 1, getn(isDDEntries) do
				if isDDEntries[i] == current then
					isDDOffset = math.max(0, i - 1)
					if isDDOffset > math.max(0, getn(isDDEntries) - IS_DD_MAX) then
						isDDOffset = math.max(0, getn(isDDEntries) - IS_DD_MAX)
					end
					break
				end
			end

			IsDDRender()

			local visible = math.min(IS_DD_MAX, getn(isDDEntries))
			isDD:SetHeight(visible * IS_ROW_H + 8)
			isDD:ClearAllPoints()
			isDD:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
			isDD:Show()
		end

		-- Forward declaration so modeBtn closures can reference it before definition
		local LayoutItemSetRows

		-- One row per spec
		local isRows = {}
		for si = 1, getn(knownSpecs) do
			local specName = knownSpecs[si]

			local specLbl = isFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			specLbl:SetPoint("TOPLEFT", isFrame, "TOPLEFT", X, isRowsStartY - 4)
			specLbl:SetWidth(150); specLbl:SetJustifyH("LEFT")
			specLbl:SetText(specName)

			local setBtn = CreateFrame("Button", nil, isFrame)
			setBtn:SetPoint("TOPLEFT", isFrame, "TOPLEFT", X + 160, isRowsStartY)
			setBtn:SetWidth(120); setBtn:SetHeight(22)
			setBtn:SetBackdrop(ART_BP_BTN_BD)
			setBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
			setBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
			setBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			local sFS = setBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			sFS:SetPoint("LEFT", setBtn, "LEFT", 6, 0); sFS:SetJustifyH("LEFT")
			setBtn.fs = sFS

			local modeBtn = CreateFrame("Button", nil, isFrame)
			modeBtn:SetPoint("TOPLEFT", isFrame, "TOPLEFT", X + 290, isRowsStartY)
			modeBtn:SetWidth(80); modeBtn:SetHeight(22)
			modeBtn:SetBackdrop(ART_BP_BTN_BD)
			modeBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
			modeBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
			modeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			local mFS = modeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			mFS:SetPoint("CENTER", modeBtn, "CENTER", 0, 0); mFS:SetJustifyH("CENTER")
			modeBtn.fs = mFS

			-- Sub-row container (shown only when mode == "raid")
			local outRow = CreateFrame("Frame", nil, isFrame)
			outRow:SetWidth(500); outRow:SetHeight(22)
			outRow:SetPoint("TOPLEFT", isFrame, "TOPLEFT", 0, isRowsStartY)
			outRow:Hide()

			local outSpecLbl = outRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			outSpecLbl:SetPoint("TOPLEFT", outRow, "TOPLEFT", X + 20, -4)
			outSpecLbl:SetWidth(130); outSpecLbl:SetJustifyH("LEFT")
			outSpecLbl:SetText(specName); outSpecLbl:SetTextColor(0.6, 0.6, 0.6, 1)

			local outSetBtn = CreateFrame("Button", nil, outRow)
			outSetBtn:SetPoint("TOPLEFT", outRow, "TOPLEFT", X + 160, 0)
			outSetBtn:SetWidth(120); outSetBtn:SetHeight(22)
			outSetBtn:SetBackdrop(ART_BP_BTN_BD)
			outSetBtn:SetBackdropColor(0.10, 0.10, 0.12, 0.95)
			outSetBtn:SetBackdropBorderColor(0.28, 0.28, 0.35, 1)
			outSetBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			local osFS = outSetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			osFS:SetPoint("LEFT", outSetBtn, "LEFT", 6, 0); osFS:SetJustifyH("LEFT")
			outSetBtn.fs = osFS

			local outCondLbl = outRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			outCondLbl:SetPoint("TOPLEFT", outRow, "TOPLEFT", X + 290, -4)
			outCondLbl:SetWidth(80); outCondLbl:SetJustifyH("CENTER")
			outCondLbl:SetText("out of Raid"); outCondLbl:SetTextColor(0.6, 0.6, 0.6, 1)

			local capSpec = specName
			setBtn:SetScript("OnClick", function()
				IsDDShow(this, capSpec, "set")
			end)

			modeBtn:SetScript("OnClick", function()
				if not ART_ItemSetBindings[capSpec] then
					ART_ItemSetBindings[capSpec] = { set = "none", mode = "always", outSet = "none" }
				end
				local b = ART_ItemSetBindings[capSpec]
				if b.mode == "raid" then
					b.mode = "always"; this.fs:SetText("Always"); outRow:Hide()
				else
					b.mode = "raid"; this.fs:SetText("Raid"); outRow:Show()
				end
				LayoutItemSetRows()
			end)

			outSetBtn:SetScript("OnClick", function()
				IsDDShow(this, capSpec, "outSet")
			end)

			tinsert(isRows, {
				spec      = specName,
				specLbl   = specLbl,
				setBtn    = setBtn,
				modeBtn   = modeBtn,
				outRow    = outRow,
				outSetBtn = outSetBtn,
			})
		end

		LayoutItemSetRows = function()
			local yo = isRowsStartY
			for i = 1, getn(isRows) do
				local row = isRows[i]
				row.specLbl:ClearAllPoints()
				row.specLbl:SetPoint("TOPLEFT", isFrame, "TOPLEFT", X, yo - 4)
				row.setBtn:ClearAllPoints()
				row.setBtn:SetPoint("TOPLEFT", isFrame, "TOPLEFT", X + 160, yo)
				row.modeBtn:ClearAllPoints()
				row.modeBtn:SetPoint("TOPLEFT", isFrame, "TOPLEFT", X + 290, yo)
				yo = yo - 26
				if row.outRow:IsShown() then
					row.outRow:ClearAllPoints()
					row.outRow:SetPoint("TOPLEFT", isFrame, "TOPLEFT", 0, yo)
					yo = yo - 26
				end
			end
			isFrame:SetHeight(math.abs(yo) + 10)
			LayoutSpecRows()
		end

		itemSetSection = isFrame

		-- Refresh item-set row display
		local function RefreshItemSetRows()
			for i = 1, getn(isRows) do
				local row     = isRows[i]
				local b       = ART_ItemSetBindings[row.spec]
				local mode    = "always"
				local setName = "none"
				local outName = "none"
				if b then
					if type(b) == "string" then
						setName = b
					else
						mode    = b.mode   or "always"
						setName = b.set    or "none"
						outName = b.outSet or "none"
					end
				end
				row.setBtn.fs:SetText(setName)
				row.modeBtn.fs:SetText(mode == "raid" and "Raid" or "Always")
				if mode == "raid" then
					row.outRow:Show()
					row.outSetBtn.fs:SetText(outName)
				else
					row.outRow:Hide()
				end
			end
			LayoutItemSetRows()
		end

		-- Extend the panel's OnShow to also refresh item-set rows
		local origOnShow = panel:GetScript("OnShow")
		panel:SetScript("OnShow", function()
			if origOnShow then origOnShow() end
			RefreshItemSetRows()
		end)

		-- Reposition everything now that the section exists
		LayoutItemSetRows()
		RefreshItemSetRows()
	end   -- end ART_BP_BuildItemSection_fn

	-- Initial display refresh
	RefreshBarSpecBindings()
	LayoutSpecRows()
end

-- Fire the deferred item-set section build at PLAYER_LOGIN.
local ART_BP_LoginFrame = CreateFrame("Frame", "ART_BP_LoginFrame", UIParent)
ART_BP_LoginFrame:RegisterEvent("PLAYER_LOGIN")
ART_BP_LoginFrame:SetScript("OnEvent", function()
	-- Migrate legacy string values to table form
	for k, v in pairs(ART_ItemSetBindings) do
		if type(v) == "string" then
			ART_ItemSetBindings[k] = { set = v, mode = "always", outSet = "none" }
		end
	end
	if ART_BP_BuildItemSection_fn then
		ART_BP_BuildItemSection_fn()
	end
end)
