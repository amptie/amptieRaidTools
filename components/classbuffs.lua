-- components/classbuffs.lua
-- Class Buff Tracker — overlay showing who needs class buffs
-- Lua 5.0 / WoW 1.12 / TurtleWoW (SuperWoW)

local getn    = table.getn
local tinsert = table.insert
local strfind = string.find
local floor   = math.floor
local GetTime = GetTime
local UnitBuff  = UnitBuff
local UnitClass = UnitClass
local UnitName  = UnitName

-- SuperWoW detection: SpellInfo only exists with SuperWoW
local CB_HAS_SUPERWOW = (SpellInfo ~= nil)

-- Hidden tooltip for non-SuperWoW buff name scanning (tooltip approach)
local cbScanTip     = CreateFrame("GameTooltip", "ART_CB_ScanTip", UIParent, "GameTooltipTemplate")
local cbScanTipText = nil  -- resolved lazily on first use

-- ── Custom overlay tooltip (pfUI-safe: not GameTooltip) ──────
local CB_TIP_PAD = 6
local CB_TIP_LINE_H = 14
local cbTipFrame = CreateFrame("Frame", "ART_CB_TipFrame", UIParent)
cbTipFrame:SetFrameStrata("TOOLTIP")
cbTipFrame:SetBackdrop({
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 10,
    insets = { left=3, right=3, top=3, bottom=3 },
})
cbTipFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
cbTipFrame:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
cbTipFrame:Hide()
local cbTipLines = {}
local function CBTipGetLine(idx)
    if not cbTipLines[idx] then
        local fs = cbTipFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", cbTipFrame, "TOPLEFT", CB_TIP_PAD, -(CB_TIP_PAD + (idx-1)*CB_TIP_LINE_H))
        fs:SetJustifyH("LEFT")
        cbTipLines[idx] = fs
    end
    return cbTipLines[idx]
end
local function CBTipShow(anchorFrame, lines)
    -- lines = { {text, r, g, b}, ... }
    local maxW = 0
    for i = 1, getn(lines) do
        local ln = CBTipGetLine(i)
        ln:SetText(lines[i][1])
        ln:SetTextColor(lines[i][2], lines[i][3], lines[i][4], 1)
        ln:Show()
        local w = ln:GetStringWidth()
        if w > maxW then maxW = w end
    end
    -- hide unused lines
    for i = getn(lines)+1, getn(cbTipLines) do cbTipLines[i]:Hide() end
    local h = getn(lines) * CB_TIP_LINE_H + CB_TIP_PAD * 2
    local w = maxW + CB_TIP_PAD * 2
    cbTipFrame:SetWidth(w)
    cbTipFrame:SetHeight(h)
    cbTipFrame:ClearAllPoints()
    cbTipFrame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 4, 0)
    cbTipFrame:Show()
end
local function CBTipHide()
    cbTipFrame:Hide()
end

-- ============================================================
-- Buff group definitions
-- ============================================================
local CB_GROUPS = {
    { key="AI",     casterClass="MAGE",    label="Arcane Intellect",
      filter="mana_only", icon="Interface\\Icons\\Spell_Holy_MagicalSentry",
      names={"Arcane Intellect","Arcane Brilliance"} },
    { key="FORT",   casterClass="PRIEST",  label="Fortitude",
      filter="everyone",  icon="Interface\\Icons\\Spell_Holy_WordFortitude",
      names={"Power Word: Fortitude","Prayer of Fortitude"} },
    { key="SHPRO",  casterClass="PRIEST",  label="Shadow Protection",
      filter="everyone",  icon="Interface\\Icons\\Spell_Shadow_AntiShadow",
      names={"Shadow Protection","Prayer of Shadow Protection"} },
    { key="SPIRIT", casterClass="PRIEST",  label="Divine Spirit",
      filter="mana_only", excludeClasses={HUNTER=true},
      icon="Interface\\Icons\\Spell_Holy_DivineSpirit",
      names={"Divine Spirit","Prayer of Spirit"} },
    { key="MOTW",   casterClass="DRUID",   label="Mark of the Wild",
      filter="everyone",  icon="Interface\\Icons\\Spell_Nature_Regeneration",
      names={"Mark of the Wild","Gift of the Wild"} },
    { key="BSALV",  casterClass="PALADIN", label="Bless. of Salvation",
      filter="everyone",  icon="Interface\\Icons\\Spell_Holy_SealOfSalvation",
      names={"Blessing of Salvation","Greater Blessing of Salvation"} },
    { key="BWIS",   casterClass="PALADIN", label="Bless. of Wisdom",
      filter="mana_only", icon="Interface\\Icons\\Spell_Holy_SealOfWisdom",
      names={"Blessing of Wisdom","Greater Blessing of Wisdom"} },
    { key="BMIGHT", casterClass="PALADIN", label="Bless. of Might",
      filter="everyone",  excludeClasses={WARLOCK=true, PRIEST=true, MAGE=true},
      icon="Interface\\Icons\\Spell_Holy_FistOfJustice",
      names={"Blessing of Might","Greater Blessing of Might"} },
    { key="BKINGS", casterClass="PALADIN", label="Bless. of Kings",
      filter="everyone",  icon="Interface\\Icons\\Spell_Magic_GreaterBlessingofKings",
      names={"Blessing of Kings","Greater Blessing of Kings"} },
    { key="BLIGHT", casterClass="PALADIN", label="Bless. of Light",
      filter="everyone",  icon="Interface\\Icons\\Spell_Holy_PrayerOfHealing02",
      names={"Blessing of Light","Greater Blessing of Light"} },
    { key="EBLESS", casterClass="DRUID",  label="Emerald Blessing",
      filter="everyone",  icon="Interface\\Icons\\Spell_Nature_ProtectionformNature",
      aura=true,  -- self-cast aura: only check if anyone has it
      names={"Emerald Blessing"} },
}

-- Classes without mana (excluded from mana_only filter)
local CB_NO_MANA = { WARRIOR=true, ROGUE=true }

-- Class label colors
local CB_CLASS_COLOR = {
    MAGE    = "|cFF69CCF0",
    PRIEST  = "|cFFFFFFFF",
    DRUID   = "|cFFFF7D0A",
    PALADIN = "|cFFF58CBA",
}

local CB_PREFIX = "ART_CB"

-- ============================================================
-- Settings defaults + DB helper
-- ============================================================
local CB_DEFAULTS_GRP = {}
for i = 1, getn(CB_GROUPS) do
    CB_DEFAULTS_GRP[CB_GROUPS[i].key] = true
end

local function GetCBDB()
    local db = amptieRaidToolsDB
    if not db.classbuffs then db.classbuffs = {} end
    local s = db.classbuffs
    if s.showAll     == nil then s.showAll     = false end
    if s.onlyInGroup == nil then s.onlyInGroup = true  end
    if s.ovlShown    == nil then s.ovlShown    = false end
    if s.ovlIconSize == nil then s.ovlIconSize = 32    end
    if s.ovlPerRow   == nil then s.ovlPerRow   = 5     end
    if not s.groupEnabled then s.groupEnabled = {} end
    for k, v in pairs(CB_DEFAULTS_GRP) do
        if s.groupEnabled[k] == nil then s.groupEnabled[k] = v end
    end
    return s
end

-- ============================================================
-- Runtime state
-- ============================================================
-- [groupKey] = { have={"name",...}, missing={"name",...} }
local cbResults          = {}
-- [playerName] = { [buffName]=true }
local cbAutoRemoveRoster = {}

local cbLastScan       = 0
local CB_SCAN_THROTTLE = 2.0

local cbBroadcastDirty  = false
local cbScanDirty       = false   -- set by PLAYER_AURAS_CHANGED; consumed by poll timer
local CB_POLL_INTERVAL  = 3.0
local cbPollTimer       = 0
local cbScheduledSendAt = 0

local function CB_GetSendOffset()
    local n = GetNumRaidMembers()
    if n == 0 then return 0 end
    local myName = UnitName("player")
    for i = 1, n do
        if UnitName("raid"..i) == myName then
            return (i - 1) / n * CB_POLL_INTERVAL
        end
    end
    return 0
end

-- Reused table to collect buff names per unit
local cbNameSet = {}

-- Reference to the overlay toggle checkbox in the settings panel
local cbOvlToggleCB = nil

-- ============================================================
-- Click-to-buff helpers
-- ============================================================
-- Anti-duplicate: recently buffed players (skip for CB_REBUFF_COOLDOWN seconds)
local cbRecentlyBuffed = {}
local CB_REBUFF_COOLDOWN = 6.0

local function CBGetUnitByName(name)
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            if UnitName("raid"..i) == name then return "raid"..i end
        end
    else
        if UnitName("player") == name then return "player" end
        for i = 1, GetNumPartyMembers() do
            if UnitName("party"..i) == name then return "party"..i end
        end
    end
    return nil
end

-- ============================================================
-- Filter helpers
-- ============================================================
local function CBMatchesFilter(classUpper, filter, excludeClasses)
    if excludeClasses and excludeClasses[classUpper] then return false end
    if filter == "everyone"  then return true end
    if filter == "mana_only" then return not CB_NO_MANA[classUpper] end
    return true
end

local function CBPlayerExcluded(playerName, group)
    -- Blessing of Might: exclude Marksman Hunters (ranged AP, not melee)
    if group.key == "BMIGHT" and ART_RL_GetRosterSpecs then
        local specs = ART_RL_GetRosterSpecs()
        local spec  = specs and specs[playerName]
        if spec and spec == "Marksman" then return true end
    end
    local ar = cbAutoRemoveRoster[playerName]
    if not ar then return false end
    for ni = 1, getn(group.names) do
        if ar[group.names[ni]] then return true end
    end
    return false
end

-- ============================================================
-- Addon message channel helper
-- ============================================================
local function CBGetChannel()
    if GetNumRaidMembers()  > 0 then return "RAID"  end
    if GetNumPartyMembers() > 0 then return "PARTY" end
    return nil
end

-- ============================================================
-- Auto-remove broadcasting
-- ============================================================
local function CBApplyOwnAutoRemove()
    local me = UnitName("player")
    if not me then return end
    cbAutoRemoveRoster[me] = {}
    if ART_BuffsList then
        for bname, active in pairs(ART_BuffsList) do
            if active then cbAutoRemoveRoster[me][bname] = true end
        end
    end
    -- Salvation Override: if set to "remove", include both Salvation variants
    if ART_SalvationOverride == "remove" then
        cbAutoRemoveRoster[me]["Blessing of Salvation"] = true
        cbAutoRemoveRoster[me]["Greater Blessing of Salvation"] = true
    end
end

local function CBBroadcastAutoRemove()
    CBApplyOwnAutoRemove()
    local ch = CBGetChannel()
    if not ch then return end
    local me = UnitName("player")
    local ar = me and cbAutoRemoveRoster[me]
    local msg = "AB"
    if ar then
        for bname, _ in pairs(ar) do
            local candidate = msg .. "^" .. bname
            if string.len(candidate) <= 250 then
                msg = candidate
            end
        end
    end
    SendAddonMessage(CB_PREFIX, msg, ch)
end

-- Called by autobuffs.lua after any ART_BuffsList change
function ART_CB_OnAutoRemoveChanged()
    CBApplyOwnAutoRemove()
    cbBroadcastDirty  = true
    cbScheduledSendAt = GetTime() + CB_GetSendOffset()
end

local function CBReceiveAutoRemove(sender, msg)
    local dash = strfind(sender, "-", 1, true)
    local name = dash and string.sub(sender, 1, dash - 1) or sender
    cbAutoRemoveRoster[name] = {}
    local pos = strfind(msg, "^", 1, true)
    if pos then
        local rest = string.sub(msg, pos + 1)
        for bname in string.gfind(rest, "([^^]+)") do
            cbAutoRemoveRoster[name][bname] = true
        end
    end
end

local function CBPruneRoster()
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        local inGroup = {}
        for i = 1, numRaid do
            local n = UnitName("raid" .. i)
            if n then inGroup[n] = true end
        end
        for name in pairs(cbAutoRemoveRoster) do
            if not inGroup[name] then cbAutoRemoveRoster[name] = nil end
        end
    end
end

-- ============================================================
-- Visible group list
-- showAll=false: only show groups for the player's class.
--   Exception: Paladins do NOT see their own paladin groups
--   (they manage blessings via PallyPower).
-- showAll=true: show all enabled groups (raid-lead view).
-- ============================================================
local function CBGetVisibleGroups()
    local db = GetCBDB()
    local classLocale, myClassRaw = UnitClass("player")
    local myClass = myClassRaw and string.upper(myClassRaw) or ""
    local groups = {}
    for i = 1, getn(CB_GROUPS) do
        local g = CB_GROUPS[i]
        if db.groupEnabled[g.key] then
            if db.showAll then
                tinsert(groups, g)
            else
                -- Own class only; Paladins skip their own groups (PallyPower)
                if g.casterClass == myClass and myClass ~= "PALADIN" then
                    tinsert(groups, g)
                end
            end
        end
    end
    return groups
end

-- ============================================================
-- Core scan
-- ============================================================
-- Incremental scan state — scan CB_SCAN_PER_FRAME units per OnUpdate tick
-- ============================================================
local CB_SCAN_PER_FRAME = 5   -- units processed per frame; tune up/down as needed
local cbScanUnits       = {}  -- unit list for the current scan pass
local cbScanUnitN       = 0
local cbScanPos         = 0   -- next index to process
local cbScanVisGroups   = {}  -- snapshot of visible groups for this pass
local cbScanInProgress  = false

local function CBScanUnit(unit, visGroups)
    local pname = UnitName(unit)
    if not pname or not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then return end
    local classLocale, pclassRaw = UnitClass(unit)
    local pclass = pclassRaw and string.upper(pclassRaw) or ""

    for k in pairs(cbNameSet) do cbNameSet[k] = nil end
    if CB_HAS_SUPERWOW then
        for i = 1, 64 do
            local tex, _, spellId = UnitBuff(unit, i)
            if not tex then break end
            if spellId and spellId > 0 then
                local sname = SpellInfo(spellId)
                if sname then cbNameSet[sname] = true end
            end
        end
    else
        if not cbScanTipText then
            cbScanTipText = getglobal("ART_CB_ScanTipTextLeft1")
        end
        for i = 1, 32 do
            cbScanTip:SetOwner(UIParent, "ANCHOR_NONE")
            cbScanTip:SetUnitBuff(unit, i)
            local name = cbScanTipText and cbScanTipText:GetText()
            if not name or name == "" then break end
            cbNameSet[name] = true
        end
    end

    for gi = 1, getn(visGroups) do
        local g = visGroups[gi]
        if g.aura then
            -- Aura buff: if ANY scanned player has it, mark as found
            local has = false
            for ni = 1, getn(g.names) do
                if cbNameSet[g.names[ni]] then has = true; break end
            end
            if has then
                -- Use a flag so we know at least one player has it
                cbResults[g.key].auraFound = true
            end
        elseif CBMatchesFilter(pclass, g.filter, g.excludeClasses) and not CBPlayerExcluded(pname, g) then
            local has = false
            for ni = 1, getn(g.names) do
                if cbNameSet[g.names[ni]] then has = true; break end
            end
            if has then
                tinsert(cbResults[g.key].have, pname)
            else
                tinsert(cbResults[g.key].missing, pname)
            end
        end
    end
end

-- Kick off a new incremental scan pass
local function CBScanAll()
    -- Reset results
    for i = 1, getn(CB_GROUPS) do
        local g = CB_GROUPS[i]
        cbResults[g.key] = { have={}, missing={} }
    end

    local visGroups = CBGetVisibleGroups()
    if getn(visGroups) == 0 then
        cbScanInProgress = false
        return
    end

    -- Build unit list snapshot
    for k = 1, cbScanUnitN do cbScanUnits[k] = nil end
    cbScanUnitN = 0
    local numRaid  = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            cbScanUnitN = cbScanUnitN + 1
            cbScanUnits[cbScanUnitN] = "raid" .. i
        end
    else
        cbScanUnitN = cbScanUnitN + 1
        cbScanUnits[cbScanUnitN] = "player"
        for i = 1, numParty do
            cbScanUnitN = cbScanUnitN + 1
            cbScanUnits[cbScanUnitN] = "party" .. i
        end
    end

    -- Snapshot visible groups
    for k = 1, getn(cbScanVisGroups) do cbScanVisGroups[k] = nil end
    for i = 1, getn(visGroups) do cbScanVisGroups[i] = visGroups[i] end

    cbScanPos        = 1
    cbScanInProgress = true
end

-- ============================================================
-- Overlay  (defined before CBTriggerScan so it's in scope)
-- ============================================================
local cbOverlayFrame = nil
local CB_OVL_HDR_H   = 24
local CB_OVL_ROW_H   = 18
local CB_OVL_MAX_VIS = 14

-- Show/hide overlay based on saved state and group membership.
-- Always hide when not in any group (raid or party), regardless of onlyInGroup.
local function CBOverlayUpdateVisibility()
    if not cbOverlayFrame then return end
    local db     = GetCBDB()
    local inRaid  = GetNumRaidMembers() > 0
    local inGroup = inRaid or GetNumPartyMembers() > 0
    -- showAll (= tracking all classes) requires a raid; own-class tracking works in group too
    local canShow = db.showAll and inRaid or (not db.showAll and inGroup)
    if not db.ovlShown or not canShow then
        cbOverlayFrame:Hide()
        return
    end
    cbOverlayFrame:Show()
end

local CB_OVL_PAD = 6    -- padding inside overlay frame
local CB_OVL_GAP = 3    -- gap between icons

local function RefreshCBOverlay()
    if not cbOverlayFrame then return end

    CBOverlayUpdateVisibility()
    if not cbOverlayFrame:IsShown() then return end

    local db        = GetCBDB()
    local iconSz    = db.ovlIconSize or 32
    local perRow    = db.ovlPerRow   or 5
    local visGroups = CBGetVisibleGroups()

    -- Hide all existing icons
    for i = 1, getn(cbOverlayFrame.icons) do cbOverlayFrame.icons[i]:Hide() end
    cbOverlayFrame.emptyLabel:Hide()

    if getn(visGroups) == 0 then
        cbOverlayFrame.emptyLabel:SetText("No buff groups tracked.")
        cbOverlayFrame.emptyLabel:Show()
        cbOverlayFrame:SetWidth(CB_OVL_PAD * 2 + 140)
        cbOverlayFrame:SetHeight(CB_OVL_HDR_H + 22 + CB_OVL_PAD)
        return
    end

    -- Build data — only groups with missing players (or missing auras)
    local iconData = {}
    for gi = 1, getn(visGroups) do
        local g   = visGroups[gi]
        local res = cbResults[g.key]
        if g.aura then
            -- Aura buff: show icon only if nobody in the raid has it
            if res and not res.auraFound then
                tinsert(iconData, {
                    group   = g,
                    haveN   = 0,
                    missN   = 0,
                    total   = 0,
                    missing = {},
                    isAura  = true,
                })
            end
        else
            local haveN = res and getn(res.have)    or 0
            local missN = res and getn(res.missing) or 0
            if missN > 0 then
                tinsert(iconData, {
                    group   = g,
                    haveN   = haveN,
                    missN   = missN,
                    total   = haveN + missN,
                    missing = res.missing,
                })
            end
        end
    end

    if getn(iconData) == 0 then
        cbOverlayFrame.emptyLabel:SetText("|cFF44DD44Buffs complete|r")
        cbOverlayFrame.emptyLabel:Show()
        cbOverlayFrame:SetWidth(CB_OVL_PAD * 2 + 140)
        cbOverlayFrame:SetHeight(CB_OVL_HDR_H + 22 + CB_OVL_PAD)
        return
    end

    local numIcons = getn(iconData)
    local numCols  = math.min(numIcons, perRow)
    local numRowsN = math.ceil(numIcons / perRow)

    local frameW = CB_OVL_PAD * 2 + numCols * iconSz + (numCols - 1) * CB_OVL_GAP
    local frameH = CB_OVL_HDR_H + numRowsN * iconSz + (numRowsN - 1) * CB_OVL_GAP + CB_OVL_PAD
    local finalW = math.max(frameW, 60)
    cbOverlayFrame:SetWidth(finalW)
    cbOverlayFrame:SetHeight(frameH)
    if cbOverlayFrame.hdrBar then cbOverlayFrame.hdrBar:SetWidth(finalW) end

    for i = 1, numIcons do
        local d   = iconData[i]
        local g   = d.group
        local col = math.mod(i - 1, perRow)
        local row = floor((i - 1) / perRow)
        local xOff = CB_OVL_PAD + col * (iconSz + CB_OVL_GAP)
        local yOff = -(CB_OVL_HDR_H + row * (iconSz + CB_OVL_GAP))

        local btn = cbOverlayFrame.icons[i]
        if not btn then
            btn = CreateFrame("Button", nil, cbOverlayFrame)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:EnableMouse(true)
            local tex = btn:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints(btn)
            btn.tex = tex
            local countFS = btn:CreateFontString(nil, "OVERLAY")
            countFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "THICKOUTLINE")
            countFS:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 2)
            countFS:SetJustifyH("RIGHT")
            countFS:SetTextColor(1, 0.82, 0, 1)
            btn.countFS = countFS
            btn:SetScript("OnEnter", function()
                -- Aura buff tooltip
                if this.isAura then
                    local tipLines = {}
                    tinsert(tipLines, { this.buffLabel, 1, 0.82, 0 })
                    tinsert(tipLines, { "Aura not active!", 1, 0.4, 0.4 })
                    local _, mc = UnitName("player") and UnitClass("player")
                    mc = mc and string.upper(mc) or ""
                    if this.casterClass == mc and mc ~= "PALADIN" then
                        tinsert(tipLines, { " ", 1, 1, 1 })
                        tinsert(tipLines, { "Click: cast on self", 0.5, 0.5, 0.5 })
                    end
                    CBTipShow(cbOverlayFrame, tipLines)
                    return
                end
                if not this.missingNames or getn(this.missingNames) == 0 then return end
                local tipLines = {}
                tinsert(tipLines, { this.buffLabel, 1, 0.82, 0 })
                tinsert(tipLines, { "Missing (" .. getn(this.missingNames) .. "):", 0.7, 0.7, 0.7 })

                local numRaid = GetNumRaidMembers()
                if numRaid > 0 and this.casterClass == "PALADIN" then
                    local nameClass = {}
                    for ri = 1, numRaid do
                        local n, _, _, _, cls = GetRaidRosterInfo(ri)
                        if n then nameClass[n] = cls end
                    end
                    local byClass = {}
                    local classOrder = {}
                    for ni = 1, getn(this.missingNames) do
                        local n   = this.missingNames[ni]
                        local cls = nameClass[n] or "?"
                        if not byClass[cls] then byClass[cls] = {}; tinsert(classOrder, cls) end
                        tinsert(byClass[cls], n)
                    end
                    table.sort(classOrder)
                    for ci = 1, getn(classOrder) do
                        local cls = classOrder[ci]
                        tinsert(tipLines, { cls .. ": " .. table.concat(byClass[cls], ", "), 1, 0.4, 0.4 })
                    end
                elseif numRaid > 0 then
                    local nameGroup = {}
                    for ri = 1, numRaid do
                        local n, _, subgroup = GetRaidRosterInfo(ri)
                        if n then nameGroup[n] = subgroup end
                    end
                    local byGroup = {}
                    local groupOrder = {}
                    for ni = 1, getn(this.missingNames) do
                        local n   = this.missingNames[ni]
                        local grp = nameGroup[n] or 0
                        if not byGroup[grp] then byGroup[grp] = {}; tinsert(groupOrder, grp) end
                        tinsert(byGroup[grp], n)
                    end
                    table.sort(groupOrder)
                    for gi2 = 1, getn(groupOrder) do
                        local grp = groupOrder[gi2]
                        tinsert(tipLines, { "Grp " .. grp .. ": " .. table.concat(byGroup[grp], ", "), 1, 0.4, 0.4 })
                    end
                else
                    for ni = 1, getn(this.missingNames) do
                        tinsert(tipLines, { this.missingNames[ni], 1, 0.4, 0.4 })
                    end
                end
                -- Hint for click-to-buff (only own class, non-Paladin)
                local _, mc = UnitClass("player")
                mc = mc and string.upper(mc) or ""
                if this.casterClass == mc and mc ~= "PALADIN" then
                    tinsert(tipLines, { " ", 1, 1, 1 })
                    tinsert(tipLines, { "Click: single buff  |  Right-click: group buff", 0.5, 0.5, 0.5 })
                end
                tinsert(tipLines, { "Shift-click: announce in chat", 0.5, 0.5, 0.5 })
                CBTipShow(cbOverlayFrame, tipLines)
            end)
            btn:SetScript("OnLeave", function() CBTipHide() end)
            btn:SetScript("OnClick", function()
                local mbtn = arg1
                -- Shift+click: announce in chat
                if IsShiftKeyDown() then
                    if not this.missingNames or getn(this.missingNames) == 0 then return end
                    local numRaid = GetNumRaidMembers()
                    local msg = "Missing " .. (this.buffLabel or "?") .. ": "
                    if numRaid > 0 then
                        local nameGroup = {}
                        for ri = 1, numRaid do
                            local n, _, subgroup = GetRaidRosterInfo(ri)
                            if n then nameGroup[n] = subgroup end
                        end
                        local byGroup = {}
                        local groupOrder = {}
                        for ni = 1, getn(this.missingNames) do
                            local n   = this.missingNames[ni]
                            local grp = nameGroup[n] or 0
                            if not byGroup[grp] then byGroup[grp] = {}; tinsert(groupOrder, grp) end
                            tinsert(byGroup[grp], n)
                        end
                        table.sort(groupOrder)
                        local parts = {}
                        for gi2 = 1, getn(groupOrder) do
                            local grp = groupOrder[gi2]
                            tinsert(parts, "[Grp" .. grp .. "]: " .. table.concat(byGroup[grp], ", "))
                        end
                        msg = msg .. table.concat(parts, " ")
                    else
                        msg = msg .. table.concat(this.missingNames, ", ")
                    end
                    local ch
                    if numRaid > 0 then ch = "RAID"
                    elseif GetNumPartyMembers() > 0 then ch = "PARTY" end
                    if ch then
                        SendChatMessage(msg, ch)
                    else
                        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r " .. msg)
                    end
                    return
                end

                -- Click-to-buff: only for own class, exclude Paladins (use PallyPower)
                local _, mc = UnitClass("player")
                mc = mc and string.upper(mc) or ""
                if this.casterClass ~= mc or mc == "PALADIN" then return end

                -- Aura buff: self-cast on left click only
                if this.isAura then
                    if mbtn == "RightButton" then return end
                    CastSpellByName(this.singleSpell)
                    return
                end

                if not this.missingNames or getn(this.missingNames) == 0 then return end

                local isRight = (mbtn == "RightButton")
                -- names[1] = single buff, names[2] = group buff
                local spellName = isRight and this.groupSpell or this.singleSpell
                if not spellName then return end

                -- Find first valid target (not recently buffed, visible, alive, connected)
                local now = GetTime()
                local target = nil
                for ni = 1, getn(this.missingNames) do
                    local n = this.missingNames[ni]
                    if not cbRecentlyBuffed[n] or (now - cbRecentlyBuffed[n]) > CB_REBUFF_COOLDOWN then
                        local unit = CBGetUnitByName(n)
                        if unit and UnitIsVisible(unit) and not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit) then
                            target = n
                            break
                        end
                    end
                end
                if not target then return end

                -- Mark as recently buffed (anti-duplicate before scan updates)
                cbRecentlyBuffed[target] = now

                -- Cast: save target → target player → cast → restore target
                TargetByName(target, true)
                CastSpellByName(spellName)
                TargetLastTarget()
            end)
            tinsert(cbOverlayFrame.icons, btn)
        end

        btn:SetWidth(iconSz)
        btn:SetHeight(iconSz)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", cbOverlayFrame, "TOPLEFT", xOff, yOff)
        btn.tex:SetTexture(g.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        -- Scale font size with icon size
        local fontSize = math.max(floor(iconSz * 0.38), 9)
        btn.countFS:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "THICKOUTLINE")
        btn.countFS:SetText(d.isAura and "!" or tostring(d.missN))
        btn.buffLabel    = g.label
        btn.casterClass  = g.casterClass
        btn.missingNames = d.missing
        btn.singleSpell  = g.names[1]
        btn.groupSpell   = g.names[2]
        btn.isAura       = d.isAura
        btn:Show()
    end
end

local function CreateCBOverlay()
    local db = GetCBDB()

    local f = CreateFrame("Frame", "ART_CB_Overlay", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetWidth(200)
    f:SetHeight(60)
    if db.ovlX and db.ovlY then
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.ovlX, db.ovlY)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:EnableMouse(true)
    f:Hide()

    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local d = GetCBDB()
        d.ovlX = this:GetLeft()
        d.ovlY = this:GetBottom()
    end)

    -- Header bar with backdrop (drag handle + title + close)
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetHeight(CB_OVL_HDR_H)
    hdr:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    hdr:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left=3, right=3, top=3, bottom=3 },
    })
    hdr:SetBackdropColor(0.06, 0.06, 0.08, 0.92)
    hdr:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    f.hdrBar = hdr

    local hdrFS = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hdrFS:SetPoint("TOPLEFT", hdr, "TOPLEFT", 8, -7)
    hdrFS:SetJustifyH("LEFT")
    hdrFS:SetTextColor(1, 0.82, 0, 1)
    hdrFS:SetText("Class Buffs")
    f.hdrFS = hdrFS

    local closeBtn = CreateFrame("Button", nil, hdr, "UIPanelCloseButton")
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetPoint("TOPRIGHT", hdr, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        GetCBDB().ovlShown = false
        cbOverlayFrame:Hide()
        if cbOvlToggleCB then cbOvlToggleCB:SetChecked(false) end
    end)

    f.icons = {}

    local emptyLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyLabel:SetPoint("TOPLEFT", f, "TOPLEFT", CB_OVL_PAD + 2, -(CB_OVL_HDR_H + 4))
    emptyLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    emptyLabel:SetText("No buff groups tracked.")
    f.emptyLabel = emptyLabel

    cbOverlayFrame = f
end

-- Defined here so both CBScanAll (above) and CreateCBOverlay (above) are in scope
local function CBTriggerScan()
    local now = GetTime()
    if (now - cbLastScan) < CB_SCAN_THROTTLE then return end
    cbLastScan = now
    CBScanAll()  -- starts incremental pass; overlay refreshed when pass completes
end

-- ============================================================
-- Settings panel UI
-- ============================================================
function AmptieRaidTools_InitClassBuffs(body)
    local panel = CreateFrame("Frame", "ART_CB_Panel", body)
    panel:SetAllPoints(body)
    panel:Hide()

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
    title:SetText("Class Buff Tracker")
    title:SetTextColor(1, 0.82, 0, 1)

    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("Tracks class buffs across the raid. Uses SuperWoW buff scanning (tooltip fallback for non-SuperWoW).")
    sub:SetTextColor(0.65, 0.65, 0.7, 1)

    local function MakeDivider(anchor, offY)
        local d = panel:CreateTexture(nil, "ARTWORK")
        d:SetHeight(1)
        d:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, offY)
        d:SetPoint("TOPRIGHT", panel,  "TOPRIGHT",  -12, 0)
        d:SetTexture(0.25, 0.25, 0.28, 0.8)
        return d
    end

    local div1 = MakeDivider(sub, -6)
    local db   = GetCBDB()

    -- ── View mode ─────────────────────────────────────────────
    local cbShowAll = ART_CreateCheckbox(panel, "Show All Buffs  (Raid Lead: all classes)")
    cbShowAll:SetPoint("TOPLEFT", div1, "BOTTOMLEFT", 0, -10)
    cbShowAll:SetChecked(db.showAll)
    cbShowAll.userOnClick = function()
        GetCBDB().showAll = cbShowAll:GetChecked() and true or false
        cbLastScan = 0
        CBScanAll()
        if cbOverlayFrame then RefreshCBOverlay() end
    end

    -- ── Overlay controls ──────────────────────────────────────
    local UpdateCBToggle  -- forward declaration; assigned below after toggleBtn

    local cbOnlyGroup = ART_CreateCheckbox(panel, "Show overlay only in group/raid")
    cbOnlyGroup:SetPoint("TOPLEFT", cbShowAll, "BOTTOMLEFT", 0, -8)
    cbOnlyGroup:SetChecked(db.onlyInGroup)
    cbOnlyGroup.userOnClick = function()
        GetCBDB().onlyInGroup = cbOnlyGroup:GetChecked() and true or false
        CBOverlayUpdateVisibility()
        UpdateCBToggle()
    end

    local BD_TOGGLE = {
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left=3, right=3, top=3, bottom=3 },
    }

    local toggleBtn = CreateFrame("Button", nil, panel)
    toggleBtn:SetWidth(120)
    toggleBtn:SetHeight(22)
    toggleBtn:SetBackdrop(BD_TOGGLE)
    toggleBtn:SetPoint("TOPLEFT", cbOnlyGroup, "BOTTOMLEFT", 0, -10)
    toggleBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    local toggleFS = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    toggleFS:SetPoint("CENTER", toggleBtn, "CENTER", 0, 0)
    toggleFS:SetJustifyH("CENTER")

    local toggleGroupLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toggleGroupLabel:SetPoint("LEFT", toggleBtn, "RIGHT", 6, 0)
    toggleGroupLabel:SetText("(group only)")
    toggleGroupLabel:SetTextColor(0.45, 0.45, 0.45, 1)
    toggleGroupLabel:Hide()

    UpdateCBToggle = function()
        local inGroup = GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
        local d = GetCBDB()
        if cbOverlayFrame and cbOverlayFrame:IsShown() then
            toggleFS:SetText("Hide Overlay")
            toggleBtn:SetBackdropColor(0.22, 0.17, 0.03, 0.95)
            toggleBtn:SetBackdropBorderColor(1, 0.82, 0, 1)
            toggleFS:SetTextColor(1, 0.82, 0, 1)
            toggleGroupLabel:Hide()
        elseif d.onlyInGroup and not inGroup then
            toggleFS:SetText("Show Overlay")
            toggleBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
            toggleBtn:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
            toggleFS:SetTextColor(0.40, 0.40, 0.40, 1)
            toggleGroupLabel:Show()
        else
            toggleFS:SetText("Show Overlay")
            toggleBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
            toggleBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
            toggleFS:SetTextColor(0.85, 0.85, 0.85, 1)
            toggleGroupLabel:Hide()
        end
    end
    UpdateCBToggle()

    toggleBtn:SetScript("OnClick", function()
        local d = GetCBDB()
        if cbOverlayFrame and cbOverlayFrame:IsShown() then
            d.ovlShown = false
            cbOverlayFrame:Hide()
        else
            d.ovlShown = true
            if not cbOverlayFrame then CreateCBOverlay() end
            cbLastScan = 0
            CBScanAll()
            RefreshCBOverlay()
        end
        UpdateCBToggle()
    end)

    -- ── Icon Size slider ─────────────────────────────────────
    local szLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    szLabel:SetPoint("TOPLEFT", toggleBtn, "BOTTOMLEFT", 0, -14)
    szLabel:SetTextColor(0.8, 0.8, 0.85, 1)
    szLabel:SetText("Icon Size: " .. db.ovlIconSize)

    local szSlider = CreateFrame("Slider", "ART_CB_SzSlider", panel)
    szSlider:SetWidth(140)
    szSlider:SetHeight(14)
    szSlider:SetPoint("LEFT", szLabel, "RIGHT", 10, 0)
    szSlider:SetOrientation("HORIZONTAL")
    szSlider:SetMinMaxValues(20, 64)
    szSlider:SetValueStep(2)
    szSlider:SetValue(db.ovlIconSize)
    local szThumb = szSlider:CreateTexture(nil, "OVERLAY")
    szThumb:SetWidth(10); szThumb:SetHeight(14)
    szThumb:SetTexture(0.5, 0.5, 0.55, 0.9)
    szSlider:SetThumbTexture(szThumb)
    local szTrack = szSlider:CreateTexture(nil, "BACKGROUND")
    szTrack:SetAllPoints(szSlider)
    szTrack:SetTexture(0.12, 0.12, 0.15, 0.8)
    szSlider:SetScript("OnValueChanged", function()
        local v = floor(this:GetValue())
        GetCBDB().ovlIconSize = v
        szLabel:SetText("Icon Size: " .. v)
        if cbOverlayFrame and cbOverlayFrame:IsShown() then RefreshCBOverlay() end
    end)

    -- ── Icons Per Row slider ─────────────────────────────────
    local prLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    prLabel:SetPoint("TOPLEFT", szLabel, "BOTTOMLEFT", 0, -10)
    prLabel:SetTextColor(0.8, 0.8, 0.85, 1)
    prLabel:SetText("Icons Per Row: " .. db.ovlPerRow)

    local prSlider = CreateFrame("Slider", "ART_CB_PrSlider", panel)
    prSlider:SetWidth(140)
    prSlider:SetHeight(14)
    prSlider:SetPoint("LEFT", prLabel, "RIGHT", 10, 0)
    prSlider:SetOrientation("HORIZONTAL")
    prSlider:SetMinMaxValues(1, 11)
    prSlider:SetValueStep(1)
    prSlider:SetValue(db.ovlPerRow)
    local prThumb = prSlider:CreateTexture(nil, "OVERLAY")
    prThumb:SetWidth(10); prThumb:SetHeight(14)
    prThumb:SetTexture(0.5, 0.5, 0.55, 0.9)
    prSlider:SetThumbTexture(prThumb)
    local prTrack = prSlider:CreateTexture(nil, "BACKGROUND")
    prTrack:SetAllPoints(prSlider)
    prTrack:SetTexture(0.12, 0.12, 0.15, 0.8)
    prSlider:SetScript("OnValueChanged", function()
        local v = floor(this:GetValue())
        GetCBDB().ovlPerRow = v
        prLabel:SetText("Icons Per Row: " .. v)
        if cbOverlayFrame and cbOverlayFrame:IsShown() then RefreshCBOverlay() end
    end)

    -- Store ref so overlay close-button can call UpdateCBToggle
    cbOvlToggleCB = { SetChecked = function(_, val)
        if not val then
            GetCBDB().ovlShown = false
            CBOverlayUpdateVisibility()
        end
        UpdateCBToggle()
    end }

    -- ── Per-group enable checkboxes ───────────────────────────
    local div2 = MakeDivider(prLabel, -10)

    local hdrG = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hdrG:SetPoint("TOPLEFT", div2, "BOTTOMLEFT", 0, -6)
    hdrG:SetText("Tracked Buff Groups:")
    hdrG:SetTextColor(0.8, 0.8, 0.85, 1)

    -- Note: Paladin groups shown for all, but Paladins see them only in 'Show All' mode
    local palNote = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    palNote:SetPoint("LEFT", hdrG, "RIGHT", 10, 0)
    palNote:SetText("|cFF888888Paladin buffs visible in 'Show All' mode only for Paladins (PallyPower)|r")

    local COL_W    = 270
    local ROW_H    = 22
    local NUM_COLS = 2

    for i = 1, getn(CB_GROUPS) do
        local g   = CB_GROUPS[i]
        local col = math.mod(i - 1, NUM_COLS)
        local row = floor((i - 1) / NUM_COLS)
        local cCol  = CB_CLASS_COLOR[g.casterClass] or "|cFFFFFFFF"
        local label = cCol .. "[" .. string.sub(g.casterClass, 1, 3) .. "]|r  " .. g.label
        local cb = ART_CreateCheckbox(panel, label)
        cb:SetPoint("TOPLEFT", hdrG, "BOTTOMLEFT", col * COL_W, -4 - row * ROW_H)
        cb:SetChecked(db.groupEnabled[g.key])
        local gkey = g.key
        cb.userOnClick = function()
            GetCBDB().groupEnabled[gkey] = cb:GetChecked() and true or false
            cbLastScan = 0
            CBScanAll()
            if cbOverlayFrame then RefreshCBOverlay() end
        end
    end

    -- ── Buff Bars settings section (buffbars.lua) ────────────────
    local bbAnchor = panel:CreateFontString(nil, "OVERLAY")
    bbAnchor:SetPoint("TOPLEFT", hdrG, "BOTTOMLEFT", 0, -4 - (math.ceil(getn(CB_GROUPS) / NUM_COLS)) * ROW_H - 4)

    local bbRefresh = nil
    if ART_BB_BuildSettingsSection then
        bbRefresh = ART_BB_BuildSettingsSection(panel, bbAnchor)
    end

    AmptieRaidTools_RegisterComponent("classbuffs", panel)

    -- Restore overlay state and refresh button appearance when tab is shown
    panel:SetScript("OnShow", function()
        local d = GetCBDB()
        if d.ovlShown then
            if not cbOverlayFrame then CreateCBOverlay() end
            cbLastScan = 0
            CBScanAll()
            RefreshCBOverlay()
        end
        UpdateCBToggle()
        if bbRefresh then bbRefresh() end
    end)
end

-- ============================================================
-- Event frame + poll timer
-- ============================================================
-- ── Combat state (shared via global) ─────────────────────────
ART_CB_InCombat = false

local function CBSetOverlayCombatState(inCombat)
    if not cbOverlayFrame then return end
    if not cbOverlayFrame.combatFS then
        local cf = CreateFrame("Frame", nil, cbOverlayFrame)
        cf:SetAllPoints(cbOverlayFrame)
        cf:SetFrameLevel(cbOverlayFrame:GetFrameLevel() + 20)
        local cfs = cf:CreateFontString(nil, "OVERLAY")
        cfs:SetFont("Fonts\\FRIZQT__.TTF", 11, "THICKOUTLINE")
        cfs:SetPoint("CENTER", cbOverlayFrame, "CENTER", 0, -floor(CB_OVL_HDR_H / 2))
        cfs:SetTextColor(0.7, 0.3, 0.3, 1)
        cfs:SetText("infight: disabled")
        cbOverlayFrame.combatFS = cfs
        cbOverlayFrame.combatFrame = cf
    end
    if inCombat then
        for i = 1, getn(cbOverlayFrame.icons) do
            local ic = cbOverlayFrame.icons[i]
            if ic:IsShown() then ic.tex:SetVertexColor(0.3, 0.3, 0.3) end
        end
        cbOverlayFrame.combatFS:Show()
    else
        for i = 1, getn(cbOverlayFrame.icons) do
            local ic = cbOverlayFrame.icons[i]
            ic.tex:SetVertexColor(1, 1, 1)
        end
        cbOverlayFrame.combatFS:Hide()
    end
end

local cbEventFrame = CreateFrame("Frame", "ART_CB_EventFrame", UIParent)
cbEventFrame:RegisterEvent("CHAT_MSG_ADDON")
cbEventFrame:RegisterEvent("PLAYER_LOGIN")
cbEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Roster updates handled by central ART_OnRosterUpdate (staggered)
if ART_OnRosterUpdate then ART_OnRosterUpdate(function()
    -- Only set flags — the 3s poll timer does the actual work (CBPruneRoster, scan, overlay)
    cbBroadcastDirty  = true
    cbScheduledSendAt = GetTime() + CB_GetSendOffset()
    cbScanDirty       = true
    if cbOverlayFrame then CBOverlayUpdateVisibility() end
end, 0.2) end
cbEventFrame:RegisterEvent("PLAYER_AURAS_CHANGED")
cbEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
cbEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

local cbPollFrame = CreateFrame("Frame", nil, UIParent)
cbPollFrame:SetScript("OnUpdate", function()
    if ART_CB_InCombat then return end  -- suspend all processing in combat
    local dt = arg1
    if not dt or dt < 0 then dt = 0 end
    cbPollTimer = cbPollTimer + dt

    -- Broadcast: slot-based jitter
    if cbBroadcastDirty and GetTime() >= cbScheduledSendAt then
        cbBroadcastDirty = false
        CBBroadcastAutoRemove()
    end

    -- Start a new scan pass when dirty or on the 3s tick
    if cbPollTimer >= CB_POLL_INTERVAL then
        cbPollTimer = 0
        cbScanDirty = true
    end
    if cbScanDirty and not cbScanInProgress then
        cbScanDirty = false
        cbLastScan  = GetTime()
        CBPruneRoster()  -- remove players who left (lightweight with dirty-flag gating)
        CBScanAll()
    end

    -- Incremental scan: process CB_SCAN_PER_FRAME units per OnUpdate tick
    if cbScanInProgress then
        local endPos = cbScanPos + CB_SCAN_PER_FRAME - 1
        if endPos > cbScanUnitN then endPos = cbScanUnitN end
        for i = cbScanPos, endPos do
            CBScanUnit(cbScanUnits[i], cbScanVisGroups)
        end
        cbScanPos = endPos + 1
        if cbScanPos > cbScanUnitN then
            cbScanInProgress = false
            if cbOverlayFrame then RefreshCBOverlay() end
        end
    end
end)

cbEventFrame:SetScript("OnEvent", function()
    local evt = event
    local a1  = arg1
    local a2  = arg2
    local a4  = arg4

    if evt == "CHAT_MSG_ADDON" then
        if ART_CB_InCombat then return end  -- ignore addon messages in combat
        if a1 ~= CB_PREFIX then return end
        local msg    = a2 or ""
        local sender = a4 or ""
        if string.sub(msg, 1, 2) == "AB" then
            CBReceiveAutoRemove(sender, msg)
            CBTriggerScan()
        end

    elseif evt == "PLAYER_LOGIN" then
        CBApplyOwnAutoRemove()
        CBBroadcastAutoRemove()
        CBTriggerScan()
        if AmptieRaidTools_InitBuffBars then AmptieRaidTools_InitBuffBars() end

    elseif evt == "PLAYER_ENTERING_WORLD" then
        CBApplyOwnAutoRemove()
        cbLastScan = 0
        CBScanAll()
        local d = GetCBDB()
        if d.ovlShown then
            if not cbOverlayFrame then CreateCBOverlay() end
            RefreshCBOverlay()
        end

    elseif evt == "PLAYER_AURAS_CHANGED" then
        if not ART_CB_InCombat then cbScanDirty = true end

    elseif evt == "PLAYER_REGEN_DISABLED" then
        ART_CB_InCombat = true
        cbScanInProgress = false
        CBSetOverlayCombatState(true)

    elseif evt == "PLAYER_REGEN_ENABLED" then
        ART_CB_InCombat = false
        CBSetOverlayCombatState(false)
        -- Resume: trigger a fresh scan
        cbScanDirty = true
        cbBroadcastDirty  = true
        cbScheduledSendAt = GetTime() + CB_GetSendOffset()

    end
end)
