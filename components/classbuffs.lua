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

-- ============================================================
-- Buff group definitions
-- ============================================================
local CB_GROUPS = {
    { key="AI",     casterClass="MAGE",    label="Arcane Intellect",
      filter="mana_only", names={"Arcane Intellect","Arcane Brilliance"} },
    { key="FORT",   casterClass="PRIEST",  label="Fortitude",
      filter="everyone",  names={"Power Word: Fortitude","Prayer of Fortitude"} },
    { key="SHPRO",  casterClass="PRIEST",  label="Shadow Protection",
      filter="everyone",  names={"Shadow Protection","Prayer of Shadow Protection"} },
    { key="SPIRIT", casterClass="PRIEST",  label="Divine Spirit",
      filter="mana_only", names={"Divine Spirit","Prayer of Spirit"} },
    { key="MOTW",   casterClass="DRUID",   label="Mark of the Wild",
      filter="everyone",  names={"Mark of the Wild","Gift of the Wild"} },
    { key="BSALV",  casterClass="PALADIN", label="Bless. of Salvation",
      filter="everyone",  names={"Blessing of Salvation","Greater Blessing of Salvation"} },
    { key="BWIS",   casterClass="PALADIN", label="Bless. of Wisdom",
      filter="mana_only", names={"Blessing of Wisdom","Greater Blessing of Wisdom"} },
    { key="BMIGHT", casterClass="PALADIN", label="Bless. of Might",
      filter="everyone",  names={"Blessing of Might","Greater Blessing of Might"} },
    { key="BKINGS", casterClass="PALADIN", label="Bless. of Kings",
      filter="everyone",  names={"Blessing of Kings","Greater Blessing of Kings"} },
    { key="BLIGHT", casterClass="PALADIN", label="Bless. of Light",
      filter="everyone",  names={"Blessing of Light","Greater Blessing of Light"} },
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

local cbBroadcastDirty = false
local CB_POLL_INTERVAL = 3.0
local cbPollTimer      = 0

-- Reused table to collect buff names per unit
local cbNameSet = {}

-- Reference to the overlay toggle checkbox in the settings panel
local cbOvlToggleCB = nil

-- ============================================================
-- Filter helpers
-- ============================================================
local function CBMatchesFilter(classUpper, filter)
    if filter == "everyone"  then return true end
    if filter == "mana_only" then return not CB_NO_MANA[classUpper] end
    return true
end

local function CBPlayerExcluded(playerName, group)
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
end

local function CBBroadcastAutoRemove()
    CBApplyOwnAutoRemove()
    local ch = CBGetChannel()
    if not ch then return end
    local msg = "AB"
    if ART_BuffsList then
        for bname, active in pairs(ART_BuffsList) do
            if active then
                local candidate = msg .. "^" .. bname
                if string.len(candidate) <= 250 then
                    msg = candidate
                end
            end
        end
    end
    SendAddonMessage(CB_PREFIX, msg, ch)
end

-- Called by autobuffs.lua after any ART_BuffsList change
function ART_CB_OnAutoRemoveChanged()
    CBApplyOwnAutoRemove()
    cbBroadcastDirty = true
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
local function CBScanAll()
    for i = 1, getn(CB_GROUPS) do
        local g = CB_GROUPS[i]
        cbResults[g.key] = { have={}, missing={} }
    end

    local visGroups = CBGetVisibleGroups()
    if getn(visGroups) == 0 then return end

    local numRaid  = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    local units = {}
    if numRaid > 0 then
        for i = 1, numRaid do tinsert(units, "raid" .. i) end
    else
        tinsert(units, "player")
        for i = 1, numParty do tinsert(units, "party" .. i) end
    end

    for ui = 1, getn(units) do
        local unit  = units[ui]
        local pname = UnitName(unit)
        if pname and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
            local classLocale, pclassRaw = UnitClass(unit)
            local pclass = pclassRaw and string.upper(pclassRaw) or ""

            -- Collect all buff names for this unit (one pass, reuse cbNameSet)
            for k in pairs(cbNameSet) do cbNameSet[k] = nil end
            for i = 1, 64 do
                local tex, _, spellId = UnitBuff(unit, i)
                if not tex then break end
                if spellId and spellId > 0 and SpellInfo then
                    local sname = SpellInfo(spellId)
                    if sname then cbNameSet[sname] = true end
                end
            end

            for gi = 1, getn(visGroups) do
                local g = visGroups[gi]
                if CBMatchesFilter(pclass, g.filter) and not CBPlayerExcluded(pname, g) then
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
    end
end

-- ============================================================
-- Overlay  (defined before CBTriggerScan so it's in scope)
-- ============================================================
local cbOverlayFrame = nil
local CB_OVL_HDR_H   = 24
local CB_OVL_ROW_H   = 18
local CB_OVL_MAX_VIS = 14

-- Show/hide overlay based on saved state and group membership
local function CBOverlayUpdateVisibility()
    if not cbOverlayFrame then return end
    local db = GetCBDB()
    if not db.ovlShown then
        cbOverlayFrame:Hide()
        return
    end
    if db.onlyInGroup then
        local inGroup = GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
        if not inGroup then
            cbOverlayFrame:Hide()
            return
        end
    end
    cbOverlayFrame:Show()
end

local function RefreshCBOverlay()
    if not cbOverlayFrame then return end

    CBOverlayUpdateVisibility()
    if not cbOverlayFrame:IsShown() then return end

    local visGroups = CBGetVisibleGroups()

    for i = 1, getn(cbOverlayFrame.rows) do cbOverlayFrame.rows[i]:Hide() end
    cbOverlayFrame.emptyLabel:Hide()

    if getn(visGroups) == 0 then
        cbOverlayFrame.emptyLabel:SetText("No buff groups tracked.")
        cbOverlayFrame.emptyLabel:Show()
        cbOverlayFrame.content:SetHeight(CB_OVL_ROW_H + 8)
        cbOverlayFrame:SetHeight(CB_OVL_HDR_H + CB_OVL_ROW_H + 16)
        cbOverlayFrame.sf:SetHeight(CB_OVL_ROW_H + 8)
        return
    end

    -- Build row data — only groups with at least one missing player
    local rowData = {}
    for gi = 1, getn(visGroups) do
        local g   = visGroups[gi]
        local res = cbResults[g.key]
        local haveN = res and getn(res.have)    or 0
        local missN = res and getn(res.missing) or 0
        if missN > 0 then
            tinsert(rowData, {
                group   = g,
                haveN   = haveN,
                missN   = missN,
                total   = haveN + missN,
                missing = res.missing,
            })
        end
    end

    -- All buffs complete
    if getn(rowData) == 0 then
        cbOverlayFrame.emptyLabel:SetText("|cFF44DD44Buffs complete|r")
        cbOverlayFrame.emptyLabel:Show()
        cbOverlayFrame.content:SetHeight(CB_OVL_ROW_H + 8)
        cbOverlayFrame:SetHeight(CB_OVL_HDR_H + CB_OVL_ROW_H + 16)
        cbOverlayFrame.sf:SetHeight(CB_OVL_ROW_H + 8)
        return
    end

    local numRows  = getn(rowData)
    local visCount = math.min(numRows, CB_OVL_MAX_VIS)

    cbOverlayFrame.content:SetHeight(math.max(numRows * CB_OVL_ROW_H, 1))
    cbOverlayFrame:SetHeight(CB_OVL_HDR_H + visCount * CB_OVL_ROW_H + 10)
    cbOverlayFrame.sf:SetHeight(visCount * CB_OVL_ROW_H)

    for i = 1, numRows do
        local rd  = rowData[i]
        local g   = rd.group
        local row = cbOverlayFrame.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, cbOverlayFrame.content)
            row:SetHeight(CB_OVL_ROW_H)
            row:EnableMouse(true)
            row:SetBackdrop({
                bgFile  = "Interface\\Tooltips\\UI-Tooltip-Background",
                tile = true, tileSize = 16, edgeSize = 0,
                insets = { left=0, right=0, top=0, bottom=0 },
            })
            row.lineFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.lineFS:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.lineFS:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function()
                if not this.missingNames or getn(this.missingNames) == 0 then return end
                GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
                GameTooltip:AddLine(this.buffLabel, 1, 0.82, 0, 1)
                GameTooltip:AddLine("Missing (" .. getn(this.missingNames) .. "):", 0.7, 0.7, 0.7, 1)

                local numRaid = GetNumRaidMembers()
                if numRaid > 0 and this.casterClass == "PALADIN" then
                    -- Paladin buffs: group missing players by class
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
                        if not byClass[cls] then
                            byClass[cls] = {}
                            tinsert(classOrder, cls)
                        end
                        tinsert(byClass[cls], n)
                    end
                    table.sort(classOrder)
                    for ci = 1, getn(classOrder) do
                        local cls = classOrder[ci]
                        GameTooltip:AddLine(cls .. ": " .. table.concat(byClass[cls], ", "), 1, 0.4, 0.4, 1)
                    end
                elseif numRaid > 0 then
                    -- Other buffs: group missing players by raid subgroup
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
                        if not byGroup[grp] then
                            byGroup[grp] = {}
                            tinsert(groupOrder, grp)
                        end
                        tinsert(byGroup[grp], n)
                    end
                    table.sort(groupOrder)
                    for gi = 1, getn(groupOrder) do
                        local grp = groupOrder[gi]
                        GameTooltip:AddLine("Grp " .. grp .. ": " .. table.concat(byGroup[grp], ", "), 1, 0.4, 0.4, 1)
                    end
                else
                    -- Party / solo: flat list
                    for ni = 1, getn(this.missingNames) do
                        GameTooltip:AddLine(this.missingNames[ni], 1, 0.4, 0.4, 1)
                    end
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            tinsert(cbOverlayFrame.rows, row)
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", cbOverlayFrame.content, "TOPLEFT", 0, -(i - 1) * CB_OVL_ROW_H)
        row:SetPoint("RIGHT",   cbOverlayFrame.content, "RIGHT",   0, 0)
        if math.mod(i, 2) == 0 then
            row:SetBackdropColor(0.10, 0.10, 0.12, 0.5)
        else
            row:SetBackdropColor(0.06, 0.06, 0.08, 0.3)
        end

        local cCol = CB_CLASS_COLOR[g.casterClass] or "|cFFFFFFFF"

        row.buffLabel    = g.label
        row.casterClass  = g.casterClass
        row.missingNames = rd.missing

        row.lineFS:SetText(
            cCol .. "[" .. string.sub(g.casterClass, 1, 3) .. "]|r " ..
            "|cFFFFCC00" .. g.label .. ":|r " ..
            "|cFFFF6644" .. rd.haveN .. "|r" ..
            "|cFF888888/|r" ..
            "|cFFAAAAAA" .. rd.total .. "|r"
        )
        row:Show()
    end

    -- Auto-fit overlay width
    local PAD  = 18
    local minW = cbOverlayFrame.hdrFS:GetStringWidth() + 32
    local maxW = minW
    for i = 1, numRows do
        local row = cbOverlayFrame.rows[i]
        if row and row:IsShown() then
            local tw = row.lineFS:GetStringWidth() + PAD
            if tw > maxW then maxW = tw end
        end
    end
    cbOverlayFrame:SetWidth(maxW)
    cbOverlayFrame.content:SetWidth(maxW - 10)
end

local function CreateCBOverlay()
    local db = GetCBDB()

    local f = CreateFrame("Frame", "ART_CB_Overlay", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetWidth(220)
    f:SetHeight(CB_OVL_HDR_H + CB_OVL_ROW_H + 8)
    if db.ovlX and db.ovlY then
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.ovlX, db.ovlY)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:EnableMouse(true)
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left=3, right=3, top=3, bottom=3 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.92)
    f:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    f:Hide()

    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local d = GetCBDB()
        d.ovlX = this:GetLeft()
        d.ovlY = this:GetBottom()
    end)

    local hdrFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hdrFS:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
    hdrFS:SetJustifyH("LEFT")
    hdrFS:SetTextColor(1, 0.82, 0, 1)
    hdrFS:SetText("Class Buffs")
    f.hdrFS = hdrFS

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        GetCBDB().ovlShown = false
        cbOverlayFrame:Hide()
        if cbOvlToggleCB then cbOvlToggleCB:SetChecked(false) end
    end)

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     5, -(CB_OVL_HDR_H + 2))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 5)
    f.sf = sf

    local scrollOff = 0
    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(210)
    content:SetHeight(1)
    sf:SetScrollChild(content)
    f.content = content

    local function SetOvlScroll(val)
        local maxS = math.max(content:GetHeight() - sf:GetHeight(), 0)
        if val < 0 then val = 0 end
        if val > maxS then val = maxS end
        scrollOff = val
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, val)
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function()
        SetOvlScroll(scrollOff - arg1 * CB_OVL_ROW_H * 3)
    end)

    f.rows = {}

    local emptyLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -4)
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
    CBScanAll()
    if cbOverlayFrame then RefreshCBOverlay() end
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
    sub:SetText("Tracks class buffs across the raid. Uses SuperWoW buff scanning.")
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

    -- Store ref so overlay close-button can call UpdateCBToggle
    cbOvlToggleCB = { SetChecked = function(_, val)
        if not val then
            GetCBDB().ovlShown = false
            CBOverlayUpdateVisibility()
        end
        UpdateCBToggle()
    end }

    -- ── Per-group enable checkboxes ───────────────────────────
    local div2 = MakeDivider(toggleBtn, -10)

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
    end)
end

-- ============================================================
-- Event frame + poll timer
-- ============================================================
local cbEventFrame = CreateFrame("Frame", "ART_CB_EventFrame", UIParent)
cbEventFrame:RegisterEvent("CHAT_MSG_ADDON")
cbEventFrame:RegisterEvent("PLAYER_LOGIN")
cbEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
cbEventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
cbEventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
cbEventFrame:RegisterEvent("UNIT_AURA")

local cbPollFrame = CreateFrame("Frame", nil, UIParent)
cbPollFrame:SetScript("OnUpdate", function()
    local dt = arg1
    if not dt or dt < 0 then dt = 0 end
    cbPollTimer = cbPollTimer + dt
    if cbPollTimer < CB_POLL_INTERVAL then return end
    cbPollTimer = 0
    if cbBroadcastDirty then
        cbBroadcastDirty = false
        CBBroadcastAutoRemove()
        cbLastScan = 0
        CBScanAll()
        if cbOverlayFrame then RefreshCBOverlay() end
    end
end)

cbEventFrame:SetScript("OnEvent", function()
    local evt = event
    local a1  = arg1
    local a2  = arg2
    local a4  = arg4

    if evt == "CHAT_MSG_ADDON" then
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

    elseif evt == "PLAYER_ENTERING_WORLD" then
        CBApplyOwnAutoRemove()
        cbLastScan = 0
        CBScanAll()
        local d = GetCBDB()
        if d.ovlShown then
            if not cbOverlayFrame then CreateCBOverlay() end
            RefreshCBOverlay()
        end

    elseif evt == "RAID_ROSTER_UPDATE" or evt == "PARTY_MEMBERS_CHANGED" then
        CBPruneRoster()
        cbBroadcastDirty = true
        CBTriggerScan()
        -- Update overlay visibility (may have entered/left a group)
        if cbOverlayFrame then
            CBOverlayUpdateVisibility()
            if cbOverlayFrame:IsShown() then RefreshCBOverlay() end
        end

    elseif evt == "UNIT_AURA" then
        CBTriggerScan()
    end
end)
