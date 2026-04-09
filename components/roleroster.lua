-- components/roleroster.lua
-- Role Roster — broadcasts own spec via addon messages, displays T/H/C/M in the Roles tab
-- Vanilla 1.12 / Lua 5.0 / TurtleWoW / SuperWoW

local getn    = table.getn
local tinsert = table.insert
local strfind = string.find

local ROLE_PREFIX = "ART_RL"

local ROLE_BADGE  = { Tank="T", Healer="H", Melee="M", Caster="C" }
local ROLE_ORDER  = { Tank=1, Healer=2, Melee=3, Caster=4 }
local FILTER_OPTIONS = { "All", "Tank", "Healer", "Melee", "Caster" }

-- Own addon version (from TOC)
local OWN_VERSION = GetAddOnMetadata("amptieRaidTools", "Version") or "0"

-- session data
local rosterSpecs    = {}   -- playerName -> spec string
local rosterAltSpecs = {}   -- playerName -> {Tank="MC", PhysDPS="BWL", ...}
local rosterClasses  = {}   -- playerName -> uppercase class (e.g. "WARRIOR")
local rosterVersions = {}   -- playerName -> version string (from addon message)
local rlFilter       = "All"
local rlPanel        = nil

local ALT_ROLE_ICONS = {
	Tank    = "Interface\\Icons\\INV_Shield_04",
	PhysDPS = "Interface\\Icons\\INV_Sword_20",
	Caster  = "Interface\\Icons\\Spell_Frost_FrostBolt02",
	Healer  = "Interface\\Icons\\Spell_Holy_HolyBolt",
}
-- Maps alt role key -> broad role (to exclude matching current role)
local ALT_ROLE_BROAD = {
	Tank    = "Tank",
	PhysDPS = "Melee",
	Caster  = "Caster",
	Healer  = "Healer",
}

-- ============================================================
-- Helpers
-- ============================================================

-- Compare two version strings "major.minor" — returns true if v >= ref
local function VersionAtLeast(v, ref)
    if not v or not ref then return false end
    -- Parse "1.2" → major=1, minor=2; handles single number "1" → minor=0
    local function parse(s)
        local dot = strfind(s, ".", 1, true)
        if dot then
            return tonumber(string.sub(s, 1, dot - 1)) or 0,
                   tonumber(string.sub(s, dot + 1)) or 0
        end
        return tonumber(s) or 0, 0
    end
    local vMaj, vMin = parse(v)
    local rMaj, rMin = parse(ref)
    if vMaj ~= rMaj then return vMaj > rMaj end
    return vMin >= rMin
end

local function GetMsgChannel()
    if GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers() > 0 then return "PARTY" end
    return nil
end

-- ============================================================
-- Broadcast / receive own spec + alt specs
-- ============================================================
local BroadcastOwnSpec   -- forward declaration

local function BuildAltStr()
    local db = amptieRaidToolsDB
    if not db or not db.altSpecs then return "" end
    local parts = {}
    for k, v in pairs(db.altSpecs) do
        tinsert(parts, k .. ":" .. v)
    end
    if getn(parts) == 0 then return "" end
    local s = parts[1]
    for i = 2, getn(parts) do s = s .. ";" .. parts[i] end
    return s
end

-- msg format: "S^CLASS^spec" or "S^CLASS^spec^Tank:MC;PhysDPS:BWL"
function ART_RL_OnOwnSpecChanged(spec)
    local ch = GetMsgChannel()
    if not ch then return end
    if not spec or spec == "" then spec = "not specified" end
    local _, cl = UnitClass("player")
    local classUpper = cl and string.upper(cl) or "UNKNOWN"
    local altStr = BuildAltStr()
    local msg = "S^" .. classUpper .. "^" .. spec
    if altStr ~= "" then msg = msg .. "^" .. altStr else msg = msg .. "^" end
    msg = msg .. "^" .. OWN_VERSION
    SendAddonMessage(ROLE_PREFIX, msg, ch)
end

-- Called from home.lua when alt specs change
function ART_RL_OnAltSpecsChanged(altSpecs)
    BroadcastOwnSpec()
end

BroadcastOwnSpec = function()
    local spec = AmptieRaidTools_PlayerInfo and AmptieRaidTools_PlayerInfo.spec or "not specified"
    ART_RL_OnOwnSpecChanged(spec)
end

local function RequestSpecs()
    local ch = GetMsgChannel()
    if not ch then return end
    SendAddonMessage(ROLE_PREFIX, "R", ch)
end

-- ── Spec broadcast with slot-based jitter ─────────────────────
-- RAID_ROSTER_UPDATE fires many times during a pull. Instead of all 40
-- players sending at the same moment, each player waits for their own
-- timeslot: offset = (raidSlot-1) / total * interval. This spreads the
-- 40 packets evenly across the full interval window.
local rlBroadcastDirty  = false
local RL_POLL_INTERVAL  = 5.0
local rlScheduledSendAt = 0   -- GetTime() value when this player should send

local function RL_GetSendOffset()
    local n = GetNumRaidMembers()
    if n == 0 then return 0 end
    local myName = UnitName("player")
    for i = 1, n do
        if UnitName("raid"..i) == myName then
            return (i - 1) / n * RL_POLL_INTERVAL
        end
    end
    return 0
end

local rlPollFrame = CreateFrame("Frame", nil, UIParent)
rlPollFrame:SetScript("OnUpdate", function()
    if not rlBroadcastDirty then return end
    if GetTime() < rlScheduledSendAt then return end
    rlBroadcastDirty = false
    BroadcastOwnSpec()
    RequestSpecs()
end)

-- ============================================================
-- Panel refresh (forward-declared, set during Init)
-- ============================================================
local function RefreshPanel()
    if not rlPanel then return end
    if rlPanel.RefreshList then rlPanel.RefreshList() end
end

-- ============================================================
-- Addon message event frame
-- ============================================================
local rlEventFrame = CreateFrame("Frame", "ART_RL_EventFrame", UIParent)
rlEventFrame:RegisterEvent("CHAT_MSG_ADDON")
-- Roster updates handled by central ART_OnRosterUpdate (staggered)
rlEventFrame:SetScript("OnEvent", function()
    local evt = event
    local a1, a2, a3, a4 = arg1, arg2, arg3, arg4

    if evt == "CHAT_MSG_ADDON" then
        if a1 ~= ROLE_PREFIX then return end
        local msg    = a2
        local sender = a4
        if not sender or sender == "" then return end
        -- Strip realm suffix if present
        local nameOnly = sender
        local dashPos = strfind(sender, "-", 1, true)
        if dashPos then nameOnly = string.sub(sender, 1, dashPos - 1) end

        if msg == "R" then
            -- Don't broadcast immediately (40 players requesting at once = burst)
            -- The broadcast dirty flag + jitter timer handles this
            rlBroadcastDirty  = true
            rlScheduledSendAt = GetTime() + RL_GetSendOffset()
        else
            local sep = strfind(msg, "^", 1, true)
            if sep then
                local kind = string.sub(msg, 1, sep - 1)
                local val  = string.sub(msg, sep + 1)
                if kind == "S" then
                    -- val: "CLASS^spec" or "CLASS^spec^Tank:MC;PhysDPS:BWL"
                    local sep2 = strfind(val, "^", 1, true)
                    if not sep2 then return end
                    local classUpper = string.sub(val, 1, sep2 - 1)
                    local rest       = string.sub(val, sep2 + 1)
                    -- rest: "spec" or "spec^altStr^version"
                    local sep3   = strfind(rest, "^", 1, true)
                    local spec   = sep3 and string.sub(rest, 1, sep3 - 1) or rest
                    local rest2  = sep3 and string.sub(rest, sep3 + 1) or ""
                    -- rest2: "altStr^version" or "altStr" or ""
                    local sep4    = strfind(rest2, "^", 1, true)
                    local altStr  = sep4 and string.sub(rest2, 1, sep4 - 1) or rest2
                    local verStr  = sep4 and string.sub(rest2, sep4 + 1) or nil
                    rosterSpecs[nameOnly]   = spec
                    rosterClasses[nameOnly] = classUpper
                    if verStr and verStr ~= "" then rosterVersions[nameOnly] = verStr end
                    -- Parse alt specs
                    local alts = {}
                    if altStr ~= "" then
                        for pair in string.gfind(altStr, "[^;]+") do
                            local colon = strfind(pair, ":", 1, true)
                            if colon then
                                local rk   = string.sub(pair, 1, colon - 1)
                                local tier = string.sub(pair, colon + 1)
                                alts[rk] = tier
                            end
                        end
                    end
                    rosterAltSpecs[nameOnly] = alts
                    rlRosterDirty = true  -- batch UI refresh via OnUpdate
                end
            end
        end

    end
end)

-- Incremental roster rebuild: processes N members per frame
local rlRosterDirty    = false
local rlRosterPos      = 0
local rlRosterTotal    = 0
local rlRosterInGroup  = {}
local RL_ROSTER_PER_FRAME = 5

local rlRosterFrame = CreateFrame("Frame", nil, UIParent)
rlRosterFrame:SetScript("OnUpdate", function()
    if not rlRosterDirty then return end
    if rlRosterPos == 0 then
        -- Init pass
        for k in pairs(rlRosterInGroup) do rlRosterInGroup[k] = nil end
        rlRosterTotal = GetNumRaidMembers()
        if rlRosterTotal == 0 then rlRosterTotal = GetNumPartyMembers() end
        rlRosterPos = 1
        return
    end
    local endPos = rlRosterPos + RL_ROSTER_PER_FRAME - 1
    if endPos > rlRosterTotal then endPos = rlRosterTotal end
    local numRaid = GetNumRaidMembers()
    for i = rlRosterPos, endPos do
        local unit, name, cl
        if numRaid > 0 then
            unit = "raid" .. i
        else
            if i == 1 then unit = "player"
            else unit = "party" .. (i - 1) end
        end
        name = UnitName(unit)
        if name then
            rlRosterInGroup[name] = true
            local _, c = UnitClass(unit)
            if c then rosterClasses[name] = string.upper(c) end
        end
    end
    rlRosterPos = endPos + 1
    if rlRosterPos > rlRosterTotal then
        -- Pass complete: prune and refresh
        for name in pairs(rosterSpecs) do
            if not rlRosterInGroup[name] then
                rosterSpecs[name]    = nil
                rosterAltSpecs[name] = nil
                rosterClasses[name]  = nil
                rosterVersions[name] = nil
            end
        end
        local me = UnitName("player")
        if me then
            if not rosterSpecs[me] then
                local spec = AmptieRaidTools_PlayerInfo and AmptieRaidTools_PlayerInfo.spec
                if spec and spec ~= "" then rosterSpecs[me] = spec end
            end
            if not rosterClasses[me] then
                local _, c = UnitClass("player")
                if c then rosterClasses[me] = string.upper(c) end
            end
        end
        rlBroadcastDirty  = true
        rlScheduledSendAt = GetTime() + RL_GetSendOffset()
        RefreshPanel()
        rlRosterDirty = false
        rlRosterPos   = 0
    end
end)

if ART_OnRosterUpdate then ART_OnRosterUpdate(function()
    rlRosterDirty = true
    rlRosterPos   = 0
end, 0.1) end

-- Public accessor for buff check target counting
function ART_RL_GetRosterSpecs() return rosterSpecs end

-- ============================================================
-- Tab panel
-- ============================================================
function AmptieRaidTools_InitRoleRoster(body)
    local panel = CreateFrame("Frame", "ART_RR_Panel", body)
    panel:SetAllPoints(body)
    rlPanel = panel

    local BD = {
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=12,
        insets={left=3,right=3,top=3,bottom=3},
    }

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
    title:SetText("Role Roster")
    title:SetTextColor(1, 0.82, 0, 1)

    -- Description
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetWidth(500)
    desc:SetJustifyH("LEFT")
    desc:SetText("Automatically detects specs via addon messages.")
    desc:SetTextColor(0.75, 0.75, 0.75, 1)

    -- Separator
    local sep = panel:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  10, -52)
    sep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -52)
    sep:SetTexture(0.35, 0.35, 0.4, 0.5)

    -- ── Filter dropdown ──────────────────────────────────────
    local function GetFilterColor(opt)
        if opt == "All" then return 1, 0.82, 0, 1 end
        local rc = ART_ROLE_COLORS and ART_ROLE_COLORS[opt]
        if rc then return rc.r, rc.g, rc.b, 1 end
        return 0.85, 0.85, 0.85, 1
    end

    local filterBtn = CreateFrame("Button", "ART_RR_FilterBtn", panel)
    filterBtn:SetWidth(150)
    filterBtn:SetHeight(24)
    filterBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -62)
    filterBtn:SetBackdrop(BD)
    filterBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
    filterBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    filterBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    local filterLbl = filterBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    filterLbl:SetPoint("LEFT",  filterBtn, "LEFT",  8, 0)
    filterLbl:SetPoint("RIGHT", filterBtn, "RIGHT", -8, 0)
    filterLbl:SetJustifyH("LEFT")

    local function UpdateFilterLabel()
        local r, g, b, a = GetFilterColor(rlFilter)
        filterLbl:SetText("Filter: " .. rlFilter .. " v")
        filterLbl:SetTextColor(r, g, b, a)
    end
    UpdateFilterLabel()

    -- Dropdown popup
    local dd = CreateFrame("Frame", "ART_RR_Dropdown", UIParent)
    dd:SetFrameStrata("TOOLTIP")
    dd:SetWidth(150)
    local itemH   = 22
    local numOpts = getn(FILTER_OPTIONS)
    dd:SetHeight(numOpts * itemH + 6)
    dd:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3},
    })
    dd:SetBackdropColor(0.08, 0.08, 0.11, 0.97)
    dd:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    dd:Hide()

    for i = 1, numOpts do
        local opt  = FILTER_OPTIONS[i]
        local item = CreateFrame("Button", nil, dd)
        item:SetHeight(itemH)
        item:SetPoint("TOPLEFT",  dd, "TOPLEFT",  4, -3 - (i-1)*itemH)
        item:SetPoint("TOPRIGHT", dd, "TOPRIGHT", -4, -3 - (i-1)*itemH)
        item:SetBackdrop({
            bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
            tile=true, tileSize=16, edgeSize=0,
            insets={left=0,right=0,top=0,bottom=0},
        })
        item:SetBackdropColor(0, 0, 0, 0)
        local lbl = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", item, "LEFT", 6, 0)
        local r, g, b, a = GetFilterColor(opt)
        lbl:SetText(opt)
        lbl:SetTextColor(r, g, b, a)
        item:SetScript("OnEnter", function() this:SetBackdropColor(0.22, 0.22, 0.28, 0.9) end)
        item:SetScript("OnLeave", function() this:SetBackdropColor(0, 0, 0, 0) end)
        item:SetScript("OnClick", function()
            rlFilter = opt
            UpdateFilterLabel()
            dd:Hide()
            RefreshPanel()
        end)
    end

    filterBtn:SetScript("OnClick", function()
        if dd:IsShown() then
            dd:Hide()
        else
            dd:ClearAllPoints()
            dd:SetPoint("TOPLEFT", filterBtn, "BOTTOMLEFT", 0, -2)
            dd:Show()
        end
    end)

    -- ── Request Specs button ─────────────────────────────────
    local reqBtn = CreateFrame("Button", "ART_RR_ReqBtn", panel)
    reqBtn:SetWidth(130)
    reqBtn:SetHeight(24)
    reqBtn:SetPoint("LEFT", filterBtn, "RIGHT", 8, 0)
    reqBtn:SetBackdrop(BD)
    reqBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
    reqBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    reqBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local reqLbl = reqBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reqLbl:SetPoint("CENTER", reqBtn, "CENTER", 0, 0)
    reqLbl:SetText("Request Specs")
    reqLbl:SetTextColor(0.85, 0.85, 0.85, 1)
    reqBtn:SetScript("OnClick", function()
        BroadcastOwnSpec()
        RequestSpecs()
    end)

    -- ── Item Check profile dropdown ───────────────────────────
    local icSelectedProfile = nil   -- currently selected profile name

    local icDdBtn = CreateFrame("Button", "ART_RR_ICDdBtn", panel)
    icDdBtn:SetWidth(140)
    icDdBtn:SetHeight(24)
    icDdBtn:SetPoint("LEFT", reqBtn, "RIGHT", 8, 0)
    icDdBtn:SetBackdrop(BD)
    icDdBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    icDdBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    icDdBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    local icDdLbl = icDdBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icDdLbl:SetPoint("LEFT",  icDdBtn, "LEFT",  6, 0)
    icDdLbl:SetPoint("RIGHT", icDdBtn, "RIGHT", -16, 0)
    icDdLbl:SetJustifyH("LEFT")
    icDdLbl:SetText("Item Check v")
    icDdLbl:SetTextColor(0.7, 0.7, 0.7, 1)

    local icDdArrow = icDdBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icDdArrow:SetPoint("RIGHT", icDdBtn, "RIGHT", -4, 0)
    icDdArrow:SetText("v")
    icDdArrow:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Dropdown list (child of UIParent to avoid clipping)
    local icDdList = CreateFrame("Frame", "ART_RR_ICDdList", UIParent)
    icDdList:SetFrameStrata("TOOLTIP")
    icDdList:SetWidth(140)
    icDdList:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3},
    })
    icDdList:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
    icDdList:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    icDdList:Hide()

    -- Max 12 visible profile rows
    local IC_DD_MAX_ROWS = 12
    local icDdRows = {}
    for i = 1, IC_DD_MAX_ROWS do
        local row = CreateFrame("Button", nil, icDdList)
        row:SetHeight(20)
        row:SetBackdrop({
            bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
            tile=true, tileSize=16, edgeSize=0,
            insets={left=0,right=0,top=0,bottom=0},
        })
        row:SetBackdropColor(0, 0, 0, 0)
        local rl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rl:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.label = rl
        row:SetScript("OnEnter", function() this:SetBackdropColor(0.22, 0.22, 0.28, 0.9) end)
        row:SetScript("OnLeave", function() this:SetBackdropColor(0, 0, 0, 0) end)
        row:Hide()
        icDdRows[i] = row
    end

    local function ICDdClose()
        icDdList:Hide()
    end

    local function ICDdOpen()
        local names = ART_IC_GetProfileNames and ART_IC_GetProfileNames() or {}
        local n = getn(names)
        if n == 0 then return end
        local rowH = 20
        icDdList:SetHeight(n * rowH + 6)
        for i = 1, IC_DD_MAX_ROWS do
            local row = icDdRows[i]
            local name = names[i]
            if name then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",  icDdList, "TOPLEFT",  4, -3 - (i-1)*rowH)
                row:SetPoint("TOPRIGHT", icDdList, "TOPRIGHT", -4, -3 - (i-1)*rowH)
                row.label:SetText(name)
                if name == icSelectedProfile then
                    row.label:SetTextColor(1, 0.82, 0, 1)
                else
                    row.label:SetTextColor(0.85, 0.85, 0.85, 1)
                end
                row:SetScript("OnClick", function()
                    icSelectedProfile = name
                    icDdLbl:SetText(name .. " v")
                    icDdLbl:SetTextColor(0.85, 0.85, 0.85, 1)
                    ICDdClose()
                end)
                row:Show()
            else
                row:Hide()
            end
        end
        icDdList:ClearAllPoints()
        icDdList:SetPoint("TOPLEFT", icDdBtn, "BOTTOMLEFT", 0, -2)
        icDdList:Show()
    end

    icDdBtn:SetScript("OnClick", function()
        if icDdList:IsShown() then ICDdClose() else ICDdOpen() end
    end)

    -- Close IC dropdown when panel hides (OnHide can reference ICDdClose directly)
    panel:SetScript("OnHide", function() ICDdClose() end)

    -- ── Perform Check button ───────────────────────────────────
    local perfBtn = CreateFrame("Button", "ART_RR_PerfBtn", panel)
    perfBtn:SetWidth(110)
    perfBtn:SetHeight(24)
    perfBtn:SetPoint("LEFT", icDdBtn, "RIGHT", 6, 0)
    perfBtn:SetBackdrop(BD)
    perfBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local perfLbl = perfBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    perfLbl:SetPoint("CENTER", perfBtn, "CENTER", 0, 0)
    perfLbl:SetText("Perform Check")

    local function CanPerformCheck()
        local myName = UnitName("player")
        local numRaid = GetNumRaidMembers()
        if numRaid > 0 then
            for ri = 1, numRaid do
                local name, rank = GetRaidRosterInfo(ri)
                if name == myName and rank >= 1 then
                    return true
                end
            end
            return false
        end
        -- In a party (no raid), the party leader can perform checks
        return UnitIsPartyLeader("player")
    end

    local function UpdatePerfBtnState()
        if CanPerformCheck() then
            perfBtn:SetBackdropColor(0.10, 0.18, 0.10, 0.95)
            perfBtn:SetBackdropBorderColor(0.30, 0.55, 0.30, 1)
            perfLbl:SetTextColor(0.55, 0.90, 0.55, 1)
        else
            perfBtn:SetBackdropColor(0.12, 0.12, 0.14, 0.95)
            perfBtn:SetBackdropBorderColor(0.30, 0.30, 0.32, 1)
            perfLbl:SetTextColor(0.45, 0.45, 0.45, 1)
        end
    end
    UpdatePerfBtnState()

    perfBtn:SetScript("OnClick", function()
        if not CanPerformCheck() then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[Item Check]|r Requires Raid Leader or Raid Assistant.")
            return
        end
        if not icSelectedProfile then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[Item Check]|r Please select a profile first.")
            return
        end
        if ART_IC_ClearResults then ART_IC_ClearResults() end
        if ART_IC_StartCheck   then ART_IC_StartCheck(icSelectedProfile) end
    end)

    -- (OnShow is set after rrSlider/SetRRScroll are defined below)

    -- ── Column headers ───────────────────────────────────────
    local hdrY = -98

    local hdrPlayer = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrPlayer:SetPoint("TOPLEFT", panel, "TOPLEFT", 34, hdrY)
    hdrPlayer:SetText("Player")
    hdrPlayer:SetTextColor(0.8, 0.8, 0.8, 1)

    local hdrRole = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrRole:SetPoint("TOPLEFT", panel, "TOPLEFT", 152, hdrY)
    hdrRole:SetText("Role")
    hdrRole:SetTextColor(0.8, 0.8, 0.8, 1)

    local hdrSpec = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrSpec:SetPoint("TOPLEFT", panel, "TOPLEFT", 220, hdrY)
    hdrSpec:SetText("Spec")
    hdrSpec:SetTextColor(0.8, 0.8, 0.8, 1)

    local hdrAlt = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrAlt:SetPoint("TOPLEFT", panel, "TOPLEFT", 334, hdrY)
    hdrAlt:SetText("Alt Specs")
    hdrAlt:SetTextColor(0.8, 0.8, 0.8, 1)

    local hdrIC = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrIC:SetPoint("TOPLEFT", panel, "TOPLEFT", 452, hdrY)
    hdrIC:SetText("Item Check")
    hdrIC:SetTextColor(0.8, 0.8, 0.8, 1)

    local hdrSep = panel:CreateTexture(nil, "ARTWORK")
    hdrSep:SetHeight(1)
    hdrSep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  10, hdrY - 14)
    hdrSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, hdrY - 14)
    hdrSep:SetTexture(0.35, 0.35, 0.4, 0.4)

    -- ── Scrollable list ──────────────────────────────────────
    local LIST_MAX   = 40
    local rowHeight  = 18
    local listStartY = hdrY - 18
    -- CLIP_H: panel(530) - listStart(116) - bottom_pad(4) = 410
    local CLIP_H    = 410
    local CONTENT_H = LIST_MAX * rowHeight   -- 720
    local CONTENT_W = 592   -- panel(624) - left(10) - slider_area(22)

    local rrScrollOff = 0

    local clipFrame = CreateFrame("ScrollFrame", "ART_RR_Clip", panel)
    clipFrame:SetPoint("TOPLEFT",     panel, "TOPLEFT",     10, listStartY)
    clipFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -22, 4)

    local content = CreateFrame("Frame", "ART_RR_Content", clipFrame)
    content:SetWidth(CONTENT_W)
    content:SetHeight(CONTENT_H)
    clipFrame:SetScrollChild(content)
    content:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", 0, 0)

    local function GetRRMaxScroll()
        local m = CONTENT_H - CLIP_H
        return m > 0 and m or 0
    end

    local function SetRRScroll(val)
        local max = GetRRMaxScroll()
        if val < 0   then val = 0   end
        if val > max then val = max end
        rrScrollOff = val
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", 0, val)
    end

    local rrSlider = CreateFrame("Slider", "ART_RR_Slider", panel)
    rrSlider:SetOrientation("VERTICAL")
    rrSlider:SetWidth(12)
    rrSlider:SetPoint("TOPRIGHT",    clipFrame, "TOPRIGHT",    18, 0)
    rrSlider:SetPoint("BOTTOMRIGHT", clipFrame, "BOTTOMRIGHT", 18, 0)
    rrSlider:SetMinMaxValues(0, GetRRMaxScroll())
    rrSlider:SetValueStep(rowHeight)
    rrSlider:SetValue(0)
    local rrThumb = rrSlider:CreateTexture(nil, "OVERLAY")
    rrThumb:SetWidth(10)
    rrThumb:SetHeight(24)
    rrThumb:SetTexture(0.5, 0.5, 0.55, 0.9)
    rrSlider:SetThumbTexture(rrThumb)
    local rrTrack = rrSlider:CreateTexture(nil, "BACKGROUND")
    rrTrack:SetAllPoints(rrSlider)
    rrTrack:SetTexture(0.12, 0.12, 0.15, 0.8)
    rrSlider:SetScript("OnValueChanged", function()
        SetRRScroll(this:GetValue())
    end)

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function()
        local delta  = arg1
        local newVal = rrScrollOff - delta * rowHeight * 3
        local max    = GetRRMaxScroll()
        if newVal < 0   then newVal = 0   end
        if newVal > max then newVal = max end
        rrSlider:SetValue(newVal)
    end)

    -- OnShow: reset scroll + auto-select first IC profile (rrSlider/SetRRScroll in scope here)
    panel:SetScript("OnShow", function()
        rrSlider:SetValue(0)
        SetRRScroll(0)
        if not icSelectedProfile and ART_IC_GetProfileNames then
            local names = ART_IC_GetProfileNames()
            if getn(names) > 0 then
                icSelectedProfile = names[1]
                icDdLbl:SetText(names[1] .. " v")
                icDdLbl:SetTextColor(0.85, 0.85, 0.85, 1)
            end
        end
    end)

    local listRows = {}

    for i = 1, LIST_MAX do
        local row = CreateFrame("Frame", nil, content)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(i-1)*rowHeight)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i-1)*rowHeight)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        if math.mod(i, 2) == 0 then
            bg:SetTexture(0.14, 0.14, 0.17, 0.5)
        else
            bg:SetTexture(0.10, 0.10, 0.13, 0.3)
        end

        local badgeFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badgeFs:SetPoint("LEFT", row, "LEFT", 0, 0)
        badgeFs:SetWidth(28)
        badgeFs:SetJustifyH("LEFT")
        row.badge = badgeFs

        local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFs:SetPoint("LEFT", row, "LEFT", 30, 0)
        nameFs:SetWidth(110)
        nameFs:SetJustifyH("LEFT")
        row.playerName = nameFs

        local roleFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        roleFs:SetPoint("LEFT", row, "LEFT", 148, 0)
        roleFs:SetWidth(64)
        roleFs:SetJustifyH("LEFT")
        row.roleFs = roleFs

        local specFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        specFs:SetPoint("LEFT", row, "LEFT", 216, 0)
        specFs:SetWidth(110)
        specFs:SetJustifyH("LEFT")
        row.specFs = specFs

        -- Alt spec icons (up to 3 — player's own main role is always excluded)
        -- pitch=46: icon(16) + gap(2) + label(26) + gap(2) = 46, no overlap
        local altIcons = {}
        for ai = 1, 3 do
            local af = CreateFrame("Frame", nil, row)
            af:SetWidth(16)
            af:SetHeight(16)
            af:SetPoint("LEFT", row, "LEFT", 330 + (ai - 1) * 46, 0)
            local aTex = af:CreateTexture(nil, "ARTWORK")
            aTex:SetAllPoints(af)
            local aLbl = af:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            aLbl:SetPoint("LEFT", af, "RIGHT", 2, 0)
            aLbl:SetWidth(26)
            aLbl:SetJustifyH("LEFT")
            aLbl:SetTextColor(0.70, 0.70, 0.70, 1)
            af.tex = aTex
            af.lbl = aLbl
            af:Hide()
            altIcons[ai] = af
        end
        row.altIcons = altIcons

        -- Item Check icons (up to 8 missing items, x=468+)
        -- starts after 3 alt slots: 330 + 2*46 + 16 + 2 + 26 + 2 = 468
        local IC_MAX   = 8
        local IC_X     = 468
        local IC_PITCH = 14
        local icIcons  = {}
        for ji = 1, IC_MAX do
            local jf = CreateFrame("Frame", nil, row)
            jf:SetWidth(14)
            jf:SetHeight(14)
            jf:SetPoint("LEFT", row, "LEFT", IC_X + (ji - 1) * IC_PITCH, 0)
            jf:EnableMouse(true)
            local jTex = jf:CreateTexture(nil, "ARTWORK")
            jTex:SetAllPoints(jf)
            jTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            jf.tex = jTex
            jf.itemKey  = nil
            jf.haveCount = 0
            jf.itemName  = ""
            jf:SetScript("OnEnter", function()
                if not this.itemKey then return end
                GameTooltip:SetOwner(this, "ANCHOR_LEFT")
                GameTooltip:SetText(this.itemName, 1, 1, 1, 1)
                local isRes = string.find(this.itemKey, "^RES_", 1, true)
                if isRes then
                    GameTooltip:AddLine("Current: " .. this.haveCount, 0.85, 0.85, 0.85, 1)
                else
                    GameTooltip:AddLine("Have: " .. this.haveCount, 0.85, 0.85, 0.85, 1)
                end
                GameTooltip:Show()
            end)
            jf:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            jf:Hide()
            icIcons[ji] = jf
        end
        row.icIcons = icIcons

        -- "OK" label shown when player passes all checks
        local icOkLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        icOkLabel:SetPoint("LEFT", row, "LEFT", IC_X, 0)
        icOkLabel:SetText("OK")
        icOkLabel:SetTextColor(0.2, 0.9, 0.2, 1)
        icOkLabel:Hide()
        row.icOkLabel = icOkLabel

        row:Hide()
        listRows[i] = row
    end

    local emptyLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    emptyLabel:SetText("No role data yet. Waiting for group members...")
    emptyLabel:SetTextColor(0.55, 0.55, 0.55, 1)
    emptyLabel:Hide()

    -- ── RefreshList ──────────────────────────────────────────
    function panel.RefreshList()
        UpdatePerfBtnState()
        local rows = {}
        for name, spec in pairs(rosterSpecs) do
            local role    = ART_GetSpecRole    and ART_GetSpecRole(spec)    or nil
            local subrole = ART_GetSpecSubRole and ART_GetSpecSubRole(spec) or nil
            if rlFilter == "All" or role == rlFilter then
                local ord = (role and ROLE_ORDER[role]) or 5
                tinsert(rows, { name=name, spec=spec, role=role, subrole=subrole, ord=ord, hasAddon=true })
            end
        end
        -- Add raid members without the addon (only in "All" filter)
        if rlFilter == "All" then
            local numRaid  = GetNumRaidMembers()
            local numParty = GetNumPartyMembers()
            if numRaid > 0 then
                for i = 1, numRaid do
                    local rname = UnitName("raid"..i)
                    if rname and not rosterSpecs[rname] then
                        local _, cl = UnitClass("raid"..i)
                        if cl then rosterClasses[rname] = string.upper(cl) end
                        tinsert(rows, { name=rname, spec=nil, role=nil, subrole=nil, ord=10, hasAddon=false })
                    end
                end
            elseif numParty > 0 then
                for i = 1, numParty do
                    local rname = UnitName("party"..i)
                    if rname and not rosterSpecs[rname] then
                        local _, cl = UnitClass("party"..i)
                        if cl then rosterClasses[rname] = string.upper(cl) end
                        tinsert(rows, { name=rname, spec=nil, role=nil, subrole=nil, ord=10, hasAddon=false })
                    end
                end
            end
        end
        local n = getn(rows)
        -- insertion sort by role order, then name
        for i = 2, n do
            local v = rows[i]
            local j = i - 1
            while j >= 1 and (rows[j].ord > v.ord or (rows[j].ord == v.ord and rows[j].name > v.name)) do
                rows[j+1] = rows[j]
                j = j - 1
            end
            rows[j+1] = v
        end

        if n == 0 then emptyLabel:Show() else emptyLabel:Hide() end

        for i = 1, LIST_MAX do
            local row  = listRows[i]
            local data = rows[i]
            if data then
                if data.hasAddon then
                    local role  = data.role
                    local badge = (role and ROLE_BADGE[role]) or "?"
                    local rc    = ART_ROLE_COLORS and role and ART_ROLE_COLORS[role]
                    if rc then
                        row.badge:SetTextColor(rc.r, rc.g, rc.b, 1)
                        row.roleFs:SetTextColor(rc.r, rc.g, rc.b, 1)
                    else
                        row.badge:SetTextColor(0.55, 0.55, 0.55, 1)
                        row.roleFs:SetTextColor(0.55, 0.55, 0.55, 1)
                    end
                    row.badge:SetText(badge)
                    local cc = RAID_CLASS_COLORS and rosterClasses[data.name] and RAID_CLASS_COLORS[rosterClasses[data.name]]
                    if cc then
                        row.playerName:SetTextColor(cc.r, cc.g, cc.b, 1)
                    else
                        row.playerName:SetTextColor(0.85, 0.85, 0.85, 1)
                    end
                    -- Name with version
                    local nameStr = data.name
                    local ver = rosterVersions[data.name]
                    if ver then
                        local col = VersionAtLeast(ver, OWN_VERSION) and "|cFF00FF00" or "|cFFFF4444"
                        nameStr = nameStr .. " " .. col .. "(" .. ver .. ")|r"
                    end
                    row.playerName:SetText(nameStr)
                    row.roleFs:SetText(role or "?")
                    row.specFs:SetText(data.spec or "")

                    -- Alt spec icons
                    local alts = rosterAltSpecs[data.name] or {}
                    local altCount = 0
                    for ai = 1, 3 do row.altIcons[ai]:Hide() end
                    local ALT_ORDER = { "Tank", "PhysDPS", "Caster", "Healer" }
                    for aoi = 1, 4 do
                        local rk   = ALT_ORDER[aoi]
                        local tier = alts[rk]
                        if tier and ALT_ROLE_BROAD[rk] ~= role then
                            altCount = altCount + 1
                            if altCount <= 3 then
                                local af = row.altIcons[altCount]
                                af.tex:SetTexture(ALT_ROLE_ICONS[rk])
                                af.lbl:SetText(tier)
                                af:Show()
                            end
                        end
                    end

                    -- Item Check icons / OK label
                    local icResults = ART_IC_GetCheckResults and ART_IC_GetCheckResults() or {}
                    local icResult  = icResults[data.name]
                    for ji = 1, 8 do row.icIcons[ji]:Hide() end
                    row.icOkLabel:Hide()
                    if icResult and icResult.done then
                        local missing  = icResult.missing or {}
                        local icCount  = 0
                        local hasMiss  = false
                        for key, have in pairs(missing) do
                            hasMiss  = true
                            icCount  = icCount + 1
                            if icCount <= 8 then
                                local jf = row.icIcons[icCount]
                                local iName, iIcon
                                if ART_IC_GetItemDisplayInfo then
                                    iName, iIcon = ART_IC_GetItemDisplayInfo(key)
                                end
                                jf.itemKey   = key
                                jf.haveCount = have
                                jf.itemName  = iName or key
                                jf.tex:SetTexture(iIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
                                jf:Show()
                            end
                        end
                        if not hasMiss then
                            row.icOkLabel:Show()
                        end
                    end
                else
                    -- Non-addon player
                    row.badge:SetText("-")
                    row.badge:SetTextColor(0.40, 0.40, 0.40, 1)
                    local cc = RAID_CLASS_COLORS and rosterClasses[data.name] and RAID_CLASS_COLORS[rosterClasses[data.name]]
                    if cc then
                        row.playerName:SetTextColor(cc.r, cc.g, cc.b, 1)
                    else
                        row.playerName:SetTextColor(0.85, 0.85, 0.85, 1)
                    end
                    row.playerName:SetText(data.name)
                    row.roleFs:SetText("|cFF666666not installed|r")
                    row.roleFs:SetTextColor(0.40, 0.40, 0.40, 1)
                    row.specFs:SetText("")
                    for ai = 1, 3 do row.altIcons[ai]:Hide() end
                    for ji = 1, 8 do row.icIcons[ji]:Hide() end
                    row.icOkLabel:Hide()
                end

                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- Register IC refresh callback so results trigger a list refresh
    if ART_IC_SetNotifyRefresh then
        ART_IC_SetNotifyRefresh(function()
            if rlPanel and rlPanel.RefreshList then rlPanel.RefreshList() end
        end)
    end

    panel.noOuterScroll = true
    AmptieRaidTools_RegisterComponent("roleroster", panel)

    -- Add self to roster immediately
    local me = UnitName("player")
    if me then
        local spec = AmptieRaidTools_PlayerInfo and AmptieRaidTools_PlayerInfo.spec
        if spec and spec ~= "" and spec ~= "not specified" then
            rosterSpecs[me] = spec
        end
        local db = amptieRaidToolsDB
        if db and db.altSpecs then
            rosterAltSpecs[me] = db.altSpecs
        end
        local _, cl = UnitClass("player")
        if cl then rosterClasses[me] = string.upper(cl) end
        rosterVersions[me] = OWN_VERSION
    end
end
