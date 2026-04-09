-- components/lootrules.lua
-- Loot Rules – profile-based loot management (Vanilla 1.12 / Lua 5.0 / SuperWoW)

local getn      = table.getn
local tinsert   = table.insert
local floor     = math.floor
local mmod      = math.mod
local strfind   = string.find
local sfmt      = string.format

-- Strip realm suffix from player name ("Foo-Realm" → "Foo")
local function StripRealm(name)
    if not name then return name end
    local dash = strfind(name, "-", 1, true)
    return dash and string.sub(name, 1, dash - 1) or name
end

-- Returns the raid subgroup (1-8) for a given player name, or nil if not found
local function GetPlayerSubgroup(name)
    local n = GetNumRaidMembers()
    for i = 1, n do
        local rname, _, subgroup = GetRaidRosterInfo(i)
        if rname == name then return subgroup end
    end
    return nil
end

-- ============================================================
-- DB helpers
-- ============================================================
local function GetLRDB()
    local db = amptieRaidToolsDB
    if not db.lootProfiles then
        db.lootProfiles = {
            ["Default"] = {
                mode             = "none",
                triggerMinQuality = 4,
                triggerItemIds   = {},
                buttons = {
                    { name="Main Spec", priority=1 },
                    { name="Off Spec",  priority=2 },
                    { name="Pass",      priority=3 },
                },
                timer    = 60,
                officers = {},
                autoLoot = { enabled=false, maxQuality=2 },
            }
        }
    end
    if not db.activeLRProfile  then db.activeLRProfile  = "Default" end
    if not db.lrZoneBindings   then db.lrZoneBindings   = {}        end
    -- lcPopupAnchor / lcCouncilAnchor are nil until the user drags a frame for the first time
    return db
end

local function GetActiveLRProfile()
    local db = GetLRDB()
    return db.lootProfiles[db.activeLRProfile]
end

-- ============================================================
-- Quality colours
-- ============================================================
local QUALITY_COLORS = {
    [0]="|cFF9D9D9D",[1]="|cFFFFFFFF",[2]="|cFF1EFF00",
    [3]="|cFF0070DD",[4]="|cFFA335EE",[5]="|cFFFF8000",
}

-- ============================================================
-- Zone table
-- zones = extra zone names beyond the primary "zone" field (e.g. multi-wing instances)
-- minRaid/maxRaid = raid size guards (for distinguishing 10- vs 40-man variants)
-- ============================================================
-- Use global ART_ZONES + "outraid" for loot rules
local ART_LR_ZONES = {}
if ART_ZONES then
    for i = 1, getn(ART_ZONES) do ART_LR_ZONES[i] = ART_ZONES[i] end
end
tinsert(ART_LR_ZONES, { key="outraid", label="Out of Raid", zone=nil })

local function GetCurrentLRZoneKey()
    local n = GetNumRaidMembers() or 0
    if n == 0 then return "outraid" end
    local zone = GetRealZoneText()
    if not zone then return "outraid" end
    for i = 1, getn(ART_LR_ZONES) do
        local z = ART_LR_ZONES[i]
        if z.zone then
            -- check primary zone name
            local match = (z.zone == zone)
            -- check additional zone names
            if not match and z.zones then
                for j = 1, getn(z.zones) do
                    if z.zones[j] == zone then match = true; break end
                end
            end
            if match then
                if (not z.minRaid or n >= z.minRaid) and (not z.maxRaid or n <= z.maxRaid) then
                    return z.key
                end
            end
        end
    end
    return "outraid"
end

-- ============================================================
-- Session state (runtime only)
-- ============================================================
-- Multi-session support (one per loot item)
local allSessions  = {}  -- [sid] = session
local sessionOrder = {}  -- ordered array of sids
local councilIdx   = 1   -- which session the council frame shows

local function GetCouncilSession()
    local sid = sessionOrder[councilIdx]
    return sid and allSessions[sid] or nil
end

local function AddSession(s)
    allSessions[s.sid] = s
    tinsert(sessionOrder, s.sid)
end

local function RemoveSession(sid)
    allSessions[sid] = nil
    local newOrder = {}; local nn = 0
    for i = 1, getn(sessionOrder) do
        if sessionOrder[i] ~= sid then
            nn = nn + 1; newOrder[nn] = sessionOrder[i]
        end
    end
    newOrder.n = nn
    sessionOrder = newOrder
    if councilIdx > nn then councilIdx = math.max(1, nn) end
end

-- Returns true if any session is still open for voting (not yet awarded or closed).
local function HasUnawardedSession()
    for i = 1, getn(sessionOrder) do
        local s = allSessions[sessionOrder[i]]
        if s and not s.awarded then return true end
    end
    return false
end

-- forward declarations
local OpenVotePopup
local CloseVotePopup
local OpenCouncilFrame
local CloseCouncilFrame
local SendLC
local OnLCMessage
local RefreshCouncilRows
local UpdateCouncilNav
local RebuildRightPanel
local SimulateLoot


-- ============================================================
-- Simulation data (Test button)
-- ============================================================
local SIM_ITEMS = {
    { itemLink="|cFFa335ee|Hitem:810:0:0:0|h[Hammer of the Northern Wind]|h|r",
      quality=4, iconPath="Interface\\Icons\\INV_Hammer_11" },
    { itemLink="|cFFa335ee|Hitem:19099:0:0:0|h[Glacial Blade]|h|r",
      quality=4, iconPath="Interface\\Icons\\INV_Weapon_ShortBlade_06" },
}
local lrPanelRef    = nil
local lrRightFrame  = nil
-- Pending roll: set when a vote button with rollMax > 0 is clicked;
-- cleared once the CHAT_MSG_SYSTEM roll result arrives.
local pendingRoll       = nil  -- { sid, btnIdx, btnName, comment, max }
local pendingDoubleVote = nil  -- { sid, btnIdx, btnName, comment, max, frame } — popup stays open

local CLASS_SHORT = {
    WARRIOR="War", PALADIN="Pala", HUNTER="Hunt", ROGUE="Rog",
    PRIEST="Pri", SHAMAN="Sha", MAGE="Mage", WARLOCK="Lock", DRUID="Dru",
}
local SORT_OPTS   = {"priority","roll","name","class","guildRank","dkp"}
local SORT_LABELS = {priority="Priority",roll="Roll",name="Name",class="Class",guildRank="G.Rank",dkp="DKP Bid"}

local function EnsureCouncilSettings(prof)
    if not prof.councilCols then
        prof.councilCols = {prio=true, class=false, spec=false, guildRank=false}
    end
    if not prof.councilSort then
        prof.councilSort = {primary="priority", secondary="roll", tertiary="name"}
    elseif not prof.councilSort.tertiary then
        prof.councilSort.tertiary = "name"
    end
end

local function GetRosterCache()
    local cache = {}
    for i = 1, GetNumRaidMembers() do
        local rname, _, _, _, _, fileName = GetRaidRosterInfo(i)
        if rname then
            cache[rname] = cache[rname] or {}
            cache[rname].class = CLASS_SHORT[fileName] or fileName or ""
        end
    end
    local ng = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, ng do
        local gname, rankName = GetGuildRosterInfo(i)
        if gname then
            cache[gname] = cache[gname] or {}
            cache[gname].guildRank = rankName or ""
        end
    end
    return cache
end

-- ============================================================
-- Profile Export / Import helpers
-- Format: LRv1~mode~tq~tqon~timer~alEnabled:alMaxQ~cols~sort~officers~tids~buttons
--   cols    = prio:class:spec:guildRank  (1/0)
--   sort    = primary:secondary:tertiary (sort key names)
--   officers= name1;name2;...  (empty = none)
--   tids    = id1;id2;...       (empty = none)
--   buttons = name|prio|rollMax|dv ; ...
-- ============================================================
local function LRSplit(s, sep)
    local result = {}
    local sepLen = string.len(sep)
    local i = 1
    while true do
        local j = string.find(s, sep, i, true)
        if not j then tinsert(result, string.sub(s, i)); break end
        tinsert(result, string.sub(s, i, j - 1))
        i = j + sepLen
    end
    return result
end

local function LRExportProfile(prof)
    if not prof then return "LRv1" end
    EnsureCouncilSettings(prof)
    local mode   = prof.mode or "none"
    local tq     = tostring(prof.triggerMinQuality or 4)
    local tqon   = (prof.triggerByQuality ~= false) and "1" or "0"
    local timer  = tostring(prof.timer or 60)
    local al     = prof.autoLoot or {}
    local alStr  = ((al.enabled and "1") or "0") .. ":" .. tostring(al.maxQuality or 2)
    local cols   = prof.councilCols or {}
    local colStr = ((cols.prio and "1") or "0") .. ":" ..
                   ((cols.class and "1") or "0") .. ":" ..
                   ((cols.spec and "1") or "0") .. ":" ..
                   ((cols.guildRank and "1") or "0")
    local srt    = prof.councilSort or {}
    local srtStr = (srt.primary or "priority") .. ":" ..
                   (srt.secondary or "roll") .. ":" ..
                   (srt.tertiary or "name")
    -- officers
    local offParts = {}
    local offs = prof.officers or {}
    for oi = 1, getn(offs) do tinsert(offParts, offs[oi]) end
    local offStr = ""
    for pi = 1, getn(offParts) do
        if pi > 1 then offStr = offStr .. ";" end
        offStr = offStr .. offParts[pi]
    end
    -- trigger item IDs
    local tidParts = {}
    local tids = prof.triggerItemIds or {}
    for id in pairs(tids) do tinsert(tidParts, tostring(id)) end
    local tidStr = ""
    for pi = 1, getn(tidParts) do
        if pi > 1 then tidStr = tidStr .. ";" end
        tidStr = tidStr .. tidParts[pi]
    end
    -- buttons
    local btns = prof.buttons or {}
    local btnParts = {}
    for bi = 1, getn(btns) do
        local b = btns[bi]
        tinsert(btnParts,
            (b.name or "") .. "^" ..
            tostring(b.priority or bi) .. "^" ..
            tostring(b.rollMax or 0) .. "^" ..
            (((b.isDoubleVote or b.dv) and "1") or "0"))
    end
    local btnStr = ""
    for pi = 1, getn(btnParts) do
        if pi > 1 then btnStr = btnStr .. ";" end
        btnStr = btnStr .. btnParts[pi]
    end
    return "LRv1~"..mode.."~"..tq.."~"..tqon.."~"..timer.."~"..alStr.."~"..colStr.."~"..srtStr.."~"..offStr.."~"..tidStr.."~"..btnStr
end

local function LRImportProfile(str)
    if not str or string.len(str) < 4 then return nil, "Empty string" end
    if string.sub(str, 1, 4) ~= "LRv1" then return nil, "Unknown format (expected LRv1...)" end
    local body = string.sub(str, 5)
    local fields = LRSplit(body, "~")
    -- fields[1]=mode, [2]=tq, [3]=tqon, [4]=timer, [5]=al, [6]=cols, [7]=sort, [8]=officers, [9]=tids, [10]=btns
    -- (leading empty string if body starts with ~)
    local fi = 1
    if getn(fields) > 0 and fields[1] == "" then fi = 2 end
    local function F(n) return fields[fi + n - 1] or "" end
    local mode = F(1)
    if mode ~= "lootcouncil" and mode ~= "dkp" then mode = "none" end
    local tq = tonumber(F(2)) or 4
    if tq < 0 then tq = 0 end; if tq > 5 then tq = 5 end
    local tqon = (F(3) == "1")
    local timer = tonumber(F(4)) or 60
    if timer < 5 then timer = 5 end
    -- autoLoot
    local alParts = LRSplit(F(5), ":")
    local alEnabled = (alParts[1] == "1")
    local alMaxQ    = tonumber(alParts[2]) or 2
    -- councilCols
    local colParts = LRSplit(F(6), ":")
    local cols = {
        prio      = (colParts[1] ~= "0"),
        class     = (colParts[2] == "1"),
        spec      = (colParts[3] == "1"),
        guildRank = (colParts[4] == "1"),
    }
    -- councilSort
    local VALID_SORT = {priority=true,roll=true,name=true,class=true,guildRank=true}
    local srtParts = LRSplit(F(7), ":")
    local function vs(v, def) if VALID_SORT[v] then return v end; return def end
    local srt = {
        primary   = vs(srtParts[1], "priority"),
        secondary = vs(srtParts[2], "roll"),
        tertiary  = vs(srtParts[3], "name"),
    }
    -- officers
    local officers = {}
    local offStr = F(8)
    if offStr ~= "" then
        local offParts = LRSplit(offStr, ";")
        for oi = 1, getn(offParts) do
            if offParts[oi] ~= "" then tinsert(officers, offParts[oi]) end
        end
    end
    -- trigger item IDs
    local triggerItemIds = {}
    local tidStr = F(9)
    if tidStr ~= "" then
        local tidParts = LRSplit(tidStr, ";")
        for ti = 1, getn(tidParts) do
            local id = tonumber(tidParts[ti])
            if id then triggerItemIds[id] = true end
        end
    end
    -- buttons
    local buttons = {}
    local btnStr = F(10)
    if btnStr ~= "" then
        local btnParts = LRSplit(btnStr, ";")
        for bi = 1, getn(btnParts) do
            local bp = LRSplit(btnParts[bi], "^")
            local bname = bp[1] or ""
            if bname ~= "" then
                tinsert(buttons, {
                    name          = bname,
                    priority      = tonumber(bp[2]) or bi,
                    rollMax       = tonumber(bp[3]) or 0,
                    isDoubleVote  = (bp[4] == "1"),
                })
            end
        end
    end
    if getn(buttons) == 0 then
        buttons = {
            {name="Main Spec",priority=1,rollMax=0,isDoubleVote=false},
            {name="Off Spec", priority=2,rollMax=0,isDoubleVote=false},
            {name="Pass",     priority=6,rollMax=0,isDoubleVote=false},
        }
    end
    return {
        mode             = mode,
        triggerMinQuality = tq,
        triggerByQuality  = tqon,
        timer            = timer,
        autoLoot         = { enabled=alEnabled, maxQuality=alMaxQ },
        councilCols      = cols,
        councilSort      = srt,
        officers         = officers,
        triggerItemIds   = triggerItemIds,
        buttons          = buttons,
    }
end

-- ============================================================
-- Shared UI helpers
-- ============================================================
local BTN_BD = {
    bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
    tile=true, tileSize=16, edgeSize=12,
    insets={left=3,right=3,top=3,bottom=3},
}
local ROW_BD = {
    bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
    tile=true, tileSize=16, edgeSize=0,
    insets={left=0,right=0,top=0,bottom=0},
}
local INPUT_BD = {
    bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
    tile=true, tileSize=8, edgeSize=8,
    insets={left=3,right=3,top=3,bottom=3},
}

local function MakeBtn(parent, text, w, h)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(w or 100); btn:SetHeight(h or 22)
    btn:SetBackdrop(BTN_BD)
    btn:SetBackdropColor(0.12,0.12,0.15,0.95)
    btn:SetBackdropBorderColor(0.35,0.35,0.4,1)
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight","ADD")
    local lbl = btn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    lbl:SetPoint("CENTER",btn,"CENTER",0,0)
    lbl:SetText(text)
    btn.label = lbl
    btn:SetScript("OnEnter",function() this:SetBackdropColor(0.18,0.18,0.22,0.95) end)
    btn:SetScript("OnLeave",function() this:SetBackdropColor(0.12,0.12,0.15,0.95) end)
    return btn
end

local function MakeEB(parent, w, h, multiline)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetWidth(w or 120); eb:SetHeight(h or 20)
    eb:SetBackdrop(INPUT_BD)
    eb:SetBackdropColor(0.06,0.06,0.08,0.95)
    eb:SetBackdropBorderColor(0.3,0.3,0.36,1)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextInsets(4,4,2,2)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(200)
    if multiline then eb:SetMultiLine(true) end
    eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    return eb
end

local function MakeDivider(parent, anchorFrame, yOff)
    local d = parent:CreateTexture(nil,"ARTWORK")
    d:SetHeight(1)
    d:SetPoint("TOPLEFT",  anchorFrame,"TOPLEFT",  0, yOff)
    d:SetPoint("TOPRIGHT", anchorFrame,"TOPRIGHT", 0, yOff)
    d:SetTexture(0.25,0.25,0.28,0.7)
    return d
end

local function SectionHdr(parent, text, anchorFrame, yOff)
    local fs = parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    fs:SetPoint("TOPLEFT", anchorFrame,"TOPLEFT", 0, yOff)
    fs:SetText(text)
    fs:SetTextColor(0.8,0.8,1,1)
    return fs
end

-- ============================================================
-- Button encode / decode helpers for LC_OPEN
-- Format per button: "name~priority~rollMax~dv"  (~ never appears in names)
-- rollMax 0 = no roll; > 0 = RandomRoll(1, rollMax) on click
-- dv 1 = double-vote (popup stays open after clicking; player picks a second button)
-- ============================================================
-- Returns a "^name~prio~roll~dv^..." suffix string (empty if no buttons)
local function EncodeOfficers(officers)
    if not officers or getn(officers) == 0 then return "" end
    local out = ""
    for i = 1, getn(officers) do
        if i > 1 then out = out..";" end
        out = out..officers[i]
    end
    return out
end

local function EncodeLCButtons(buttons)
    local out = ""
    for i = 1, getn(buttons) do
        local b = buttons[i]
        if b.name and b.name ~= "" then
            out = out.."^"..b.name.."~"..tostring(b.priority or 99)
                      .."~"..tostring(b.rollMax or 0)
                      .."~"..tostring(b.isDoubleVote and 1 or 0)
        end
    end
    return out
end

-- Parses button fields from msg parts starting at startIdx
-- Supports 4-field "name~prio~rollMax~dv", 3-field and legacy 2-field formats
local function DecodeLCButtons(msgParts, startIdx)
    local buttons = {}; local n = 0
    for i = startIdx, getn(msgParts) do
        local piece = msgParts[i]
        if piece and piece ~= "" then
            -- try 4-field format first
            local _, _, bname, bprio, broll, bdv = string.find(piece, "^(.-)~(%d+)~(%d+)~(%d+)$")
            if bname and bprio then
                n = n + 1
                buttons[n] = { name=bname, priority=tonumber(bprio),
                               rollMax=tonumber(broll) or 0,
                               isDoubleVote=(tonumber(bdv) == 1) }
            else
                -- 3-field fallback
                local _, _, bn3, bp3, br3 = string.find(piece, "^(.-)~(%d+)~(%d+)$")
                if bn3 and bp3 then
                    n = n + 1
                    buttons[n] = { name=bn3, priority=tonumber(bp3), rollMax=tonumber(br3) or 0 }
                else
                    -- legacy 2-field
                    local _, _, bn2, bp2 = string.find(piece, "^(.-)~(%d+)$")
                    if bn2 and bp2 then
                        n = n + 1
                        buttons[n] = { name=bn2, priority=tonumber(bp2), rollMax=0 }
                    end
                end
            end
        end
    end
    buttons.n = n
    return buttons
end

-- ============================================================
-- SendLC
-- ============================================================
SendLC = function(msg, whisperTarget)
    if whisperTarget then
        SendAddonMessage("ART_LC", msg, "WHISPER", whisperTarget)
        return
    end
    if GetNumRaidMembers() > 0 then
        SendAddonMessage("ART_LC", msg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendAddonMessage("ART_LC", msg, "PARTY")
    end
end

-- ============================================================
-- IsPlayerML helper
-- ============================================================
local function IsPlayerML()
    local method, partyIdx, raidIdx = GetLootMethod()
    if method ~= "master" then return false end
    if raidIdx ~= nil then
        return UnitIsUnit("raid"..raidIdx, "player")
    elseif partyIdx ~= nil then
        if partyIdx == 0 then return true end
        return UnitIsUnit("party"..partyIdx, "player")
    end
    return false
end

local function IsOfficer(name, officers)
    if not officers then return false end
    for i = 1, getn(officers) do
        if officers[i] == name then return true end
    end
    return false
end

-- ============================================================
-- Item display helpers
-- ============================================================
local function GetItemTexture(itemLink)
    if itemLink then
        local _, _, iid = string.find(itemLink, "item:(%d+)")
        if iid then
            local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(tonumber(iid))
            if tex then return tex end
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Builds "item:ID:0:0:0" hyperlink for GameTooltip:SetHyperlink (vanilla-safe full format)
local function ItemHyperlink(itemLink)
    if not itemLink then return nil end
    local _, _, iid = string.find(itemLink, "item:(%d+)")
    return iid and ("item:"..iid..":0:0:0") or itemLink
end

-- ============================================================
-- VOTE POPUP  (one frame per session, stacked vertically)
-- ============================================================
local popupWindows  = {}  -- [sid] = frame
local popupOrder    = {}  -- ordered sid list (for stacking)
-- Saved anchor: position of the first popup, updated on drag and on close.
-- Subsequent loot sessions open the first popup at this saved position.
local popupAnchorPt    = "CENTER"
local popupAnchorRelPt = "CENTER"
local popupAnchorX     = 0
local popupAnchorY     = 80

local function SavePopupAnchor(f)
    -- Use absolute screen coordinates so chained relative anchors don't pollute the saved position
    local cx, cy = f:GetCenter()
    if cx and cy then
        popupAnchorPt    = "CENTER"
        popupAnchorRelPt = "BOTTOMLEFT"
        popupAnchorX     = cx
        popupAnchorY     = cy
        local db = GetLRDB()
        db.lcPopupAnchor = {x=cx, y=cy}
    end
end

local function ReflowPopups()
    -- Pass 1: collect visible popups and chain each below the previous.
    -- The first visible popup is the user-movable anchor — its position is not touched.
    local visibles = {}
    local prev = nil
    for i = 1, getn(popupOrder) do
        local sid = popupOrder[i]
        local pf  = popupWindows[sid]
        if pf and pf:IsShown() then
            if not prev then
                prev = pf
            else
                pf:ClearAllPoints()
                pf:SetPoint("TOP", prev, "BOTTOM", 0, -8)
                prev = pf
            end
            tinsert(visibles, pf)
        end
    end
    -- Pass 2: if the bottom of the last popup is below the screen edge,
    -- shift the anchor upward and re-chain inline (no recursion).
    local vn = getn(visibles)
    if vn == 0 then return end
    local lastBot = visibles[vn]:GetBottom()
    if lastBot and lastBot < 2 then          -- 2px safety margin
        local anchor  = visibles[1]
        local ax, ay  = anchor:GetCenter()
        if ax and ay then
            local shift  = 2 - lastBot       -- move up by deficit
            local screenH = UIParent:GetHeight()
            local newCy  = math.min(ay + shift, screenH - anchor:GetHeight() / 2)
            anchor:ClearAllPoints()
            anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ax, newCy)
            -- re-chain remaining popups after the anchor
            for vi = 2, vn do
                visibles[vi]:ClearAllPoints()
                visibles[vi]:SetPoint("TOP", visibles[vi-1], "BOTTOM", 0, -8)
            end
        end
    end
end

OpenVotePopup = function(s)
    -- already open → just reflow
    if popupWindows[s.sid] then
        popupWindows[s.sid]:Show()
        ReflowPopups()
        return
    end

    -- Count valid buttons first — needed to compute frame width & column layout
    local valid = {}; local vc = 0
    local buttons_pre = s.buttons or {}
    for bi = 1, getn(buttons_pre) do
        if buttons_pre[bi].name and buttons_pre[bi].name ~= "" then
            vc = vc + 1; valid[vc] = buttons_pre[bi]
        end
    end
    -- Layout constants
    local BW, BH   = 100, 24
    local COLS      = (vc > 3) and 2 or 1          -- 2 columns when 4+ buttons
    local BTN_AREA_W = COLS * BW + (COLS - 1) * 4  -- 100 or 204
    local LEFT_W    = 296                            -- comment EB width
    local FRAME_W   = 12 + LEFT_W + 10 + BTN_AREA_W + 12
    local RIGHT_OFF = 12 + BTN_AREA_W + 10          -- nameBtn right offset from frame right

    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetWidth(FRAME_W)
    -- height is set dynamically below
    f:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
    f:SetBackdropColor(0.06,0.06,0.1,0.97)
    f:SetBackdropBorderColor(0.6,0.5,0.8,1)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop",  function()
        this:StopMovingOrSizing()
        -- keep anchor in sync when the user moves the top popup
        if getn(popupOrder) > 0 and popupOrder[1] == this._sid then
            SavePopupAnchor(this)
        end
    end)
    f:SetScript("OnHide", function()
        local closedSid = this._sid
        popupWindows[closedSid] = nil
        local newOrder = {}; local nn = 0
        for i = 1, getn(popupOrder) do
            if popupOrder[i] ~= closedSid then
                nn = nn + 1; newOrder[nn] = popupOrder[i]
            end
        end
        newOrder.n = nn; popupOrder = newOrder
        ReflowPopups()
    end)
    f._sid = s.sid

    local titleFS = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    titleFS:SetPoint("TOPLEFT",f,"TOPLEFT",12,-10)
    titleFS:SetTextColor(1,0.82,0,1)
    local modeLabel = s.isDKP and "DKP – Bid" or "Loot Council – Vote"
    if s.isSim then
        local pos, tot = 1, getn(sessionOrder)
        for i = 1, tot do if sessionOrder[i] == s.sid then pos = i; break end end
        titleFS:SetText(modeLabel.."  |cFF33CCFF[Sim "..pos.."/"..tot.."]|r")
    else
        titleFS:SetText(modeLabel)
    end
    f.titleFS = titleFS

    local timerFS = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    timerFS:SetPoint("TOPRIGHT",f,"TOPRIGHT",-12,-10)
    timerFS:SetTextColor(0.8,0.8,1,1)
    f.timerFS = timerFS

    local iconBtn = CreateFrame("Button",nil,f)
    iconBtn:SetWidth(36); iconBtn:SetHeight(36)
    iconBtn:SetPoint("TOPLEFT",titleFS,"BOTTOMLEFT",0,-6)
    iconBtn:EnableMouse(true)
    local iconTexObj = iconBtn:CreateTexture(nil,"BORDER")
    iconTexObj:SetAllPoints(iconBtn)
    iconTexObj:SetTexCoord(0.06,0.94,0.06,0.94)
    iconTexObj:SetTexture(s.iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
    local hl = ItemHyperlink(s.itemLink)
    iconBtn.hyperlink = hl
    iconBtn.itemLink  = s.itemLink
    iconBtn:SetScript("OnEnter",function()
        if not this.hyperlink then return end
        GameTooltip:SetOwner(this,"ANCHOR_BOTTOM")
        GameTooltip:SetHyperlink(this.hyperlink)
        GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)
    iconBtn:SetScript("OnClick",function()
        if IsControlKeyDown() and this.itemLink then
            DressUpItemLink(this.itemLink)
        end
    end)
    f.iconBtn    = iconBtn
    f.iconTexObj = iconTexObj

    local nameBtn = CreateFrame("Button",nil,f)
    nameBtn:SetPoint("TOPLEFT",iconBtn,"TOPRIGHT",6,0)
    nameBtn:SetPoint("RIGHT",f,"RIGHT",-RIGHT_OFF,0)
    nameBtn:SetHeight(36)
    nameBtn:EnableMouse(true)
    local nameFS = nameBtn:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    nameFS:SetAllPoints(nameBtn)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetJustifyV("MIDDLE")
    local nameText = s.itemLink or "Unknown"
    if (s.quantity or 1) > 1 then nameText = nameText .. " |cFFFFD700x" .. tostring(s.quantity) .. "|r" end
    nameFS:SetText(nameText)
    nameBtn.hyperlink = hl
    nameBtn.itemLink  = s.itemLink
    nameBtn:SetScript("OnEnter",function()
        if not this.hyperlink then return end
        GameTooltip:SetOwner(this,"ANCHOR_BOTTOM")
        GameTooltip:SetHyperlink(this.hyperlink)
        GameTooltip:Show()
    end)
    nameBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)
    nameBtn:SetScript("OnClick",function()
        if IsControlKeyDown() and this.itemLink then
            DressUpItemLink(this.itemLink)
        end
    end)
    f.nameBtn = nameBtn
    f.nameFS  = nameFS

    -- DKP bid field (only for DKP sessions)
    local dkpBidEB = nil
    if s.isDKP then
        local dkpBidLbl = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        dkpBidLbl:SetPoint("TOPLEFT",iconBtn,"BOTTOMLEFT",0,-8)
        dkpBidLbl:SetText("DKP Bid:")
        dkpBidLbl:SetTextColor(0.4,0.75,1,1)
        dkpBidEB = MakeEB(f,70,20)
        dkpBidEB:SetPoint("TOPLEFT",dkpBidLbl,"BOTTOMLEFT",0,-3)
        f.dkpBidEB = dkpBidEB
    end

    local commentLbl = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    if s.isDKP and dkpBidEB then
        commentLbl:SetPoint("TOPLEFT",dkpBidEB,"BOTTOMLEFT",0,-8)
    else
        commentLbl:SetPoint("TOPLEFT",iconBtn,"BOTTOMLEFT",0,-8)
    end
    commentLbl:SetText("Comment (optional):")
    commentLbl:SetTextColor(0.6,0.6,0.65,1)

    -- comment EB spans left content area (x=12 to x=308, width=296)
    local commentEB = MakeEB(f, 296, 20)
    commentEB:SetPoint("TOPLEFT",commentLbl,"BOTTOMLEFT",0,-3)
    f.commentEB = commentEB

    -- Button grid: 1 column for ≤3 buttons, 2 columns for 4+
    -- Row-major: Btn1 Btn2 / Btn3 Btn4 / Btn5 Btn6
    local btnRows  = math.max(1, ceil(vc / COLS))
    local btnAreaH = btnRows * BH + (btnRows - 1) * 4
    -- Left column height: DKP adds bid row (lbl14+gap3+EB20+gap8) = 45px extra over 81
    local LEFT_H = s.isDKP and 126 or 81
    local contentH = math.max(LEFT_H, btnAreaH)
    -- Frame: top(10)+title(18)+gap(6)+content+gap(8)+status(14)+bottom(10) = 66+content
    f:SetHeight(66 + contentH)

    -- Button area anchored top-right, aligned with the icon row (y=-34)
    local btnArea = CreateFrame("Frame",nil,f)
    btnArea:SetPoint("TOPRIGHT",f,"TOPRIGHT",-12,-34)
    btnArea:SetWidth(BTN_AREA_W)
    btnArea:SetHeight(btnAreaH)
    f.btnArea = btnArea
    f.voteBtns = {}

    local statusFS = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    statusFS:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",12,10)
    statusFS:SetTextColor(0.6,0.8,0.6,1)
    statusFS:SetText("Waiting for your vote...")
    f.statusFS = statusFS
    for bi = 1, vc do
        local rm   = valid[bi].rollMax or 0
        local isDV = valid[bi].isDoubleVote and true or false
        local label = valid[bi].name
        local vb = MakeBtn(f.btnArea, label, BW, BH)
        local col = mmod(bi - 1, COLS)
        local row = floor((bi - 1) / COLS)
        vb:SetPoint("TOPLEFT",f.btnArea,"TOPLEFT", col*(BW+4), -row*(BH+4))
        vb.btnIdx       = bi
        vb.btnName      = valid[bi].name
        vb.rollMax      = rm
        vb.isDoubleVote = isDV
        vb:SetScript("OnClick", function()
            local sess = allSessions[f._sid]
            if not sess or sess.closed then return end
            local comment = f.commentEB:GetText() or ""

            if this.isDoubleVote then
                -- Double-vote: fire roll / send DV message, keep popup open
                if this._dvDone then return end  -- already clicked once
                this._dvDone = true
                this:SetBackdropColor(0.04,0.12,0.22,0.95)
                this:SetBackdropBorderColor(0.4,0.7,1,1)
                this.label:SetTextColor(0.5,0.8,1,1)
                if this.rollMax and this.rollMax > 0 then
                    local dkpBidDV = (sess.isDKP and f.dkpBidEB) and (tonumber(f.dkpBidEB:GetText()) or 0) or 0
                    if sess.isDKP and dkpBidDV <= 0 then
                        f.statusFS:SetText("|cFFFF4444Please enter a DKP bid before voting.|r")
                        return
                    end
                    pendingDoubleVote = {
                        sid     = sess.sid,
                        btnIdx  = this.btnIdx,
                        btnName = this.btnName,
                        comment = comment,
                        max     = this.rollMax,
                        dkp     = dkpBidDV,
                    }
                    RandomRoll(1, this.rollMax)
                else
                    local mySpec  = (AmptieRaidTools_PlayerInfo and AmptieRaidTools_PlayerInfo.spec) or ""
                    local dkpBid2 = (sess.isDKP and f.dkpBidEB) and (tonumber(f.dkpBidEB:GetText()) or 0) or 0
                    if sess.isDKP and dkpBid2 <= 0 then
                        f.statusFS:SetText("|cFFFF4444Please enter a DKP bid before voting.|r")
                        return
                    end
                    local dvMsg = "LC_DVOTE^"..sess.sid.."^"..this.btnIdx.."^"..comment.."^0^"..mySpec.."^"..tostring(dkpBid2)
                    SendLC(dvMsg)
                    local myName = UnitName("player")
                    if myName then
                        sess.dVotes[myName] = {btn=this.btnIdx, btnName=this.btnName, comment=comment, roll=0, spec=mySpec, dkp=dkpBid2}
                    end
                end
                f.statusFS:SetText("|cFF88CCFF"..this.btnName.." noted — pick your main vote|r")
                return
            end

            -- Regular vote: highlight selection, close popup
            for _, vb2 in pairs(f.voteBtns) do
                if not vb2.isDoubleVote then
                    vb2:SetBackdropColor(0.1,0.1,0.14,0.95)
                    vb2:SetBackdropBorderColor(0.35,0.35,0.42,1)
                    vb2.label:SetTextColor(0.85,0.85,0.85,1)
                end
            end
            this:SetBackdropColor(0.22,0.18,0.04,0.95)
            this:SetBackdropBorderColor(1,0.82,0,1)
            this.label:SetTextColor(1,0.82,0,1)
            if this.rollMax and this.rollMax > 0 then
                pendingRoll = {
                    sid     = sess.sid,
                    btnIdx  = this.btnIdx,
                    btnName = this.btnName,
                    comment = comment,
                    max     = this.rollMax,
                }
                RandomRoll(1, this.rollMax)
            else
                local mySpec = (AmptieRaidTools_PlayerInfo and AmptieRaidTools_PlayerInfo.spec) or ""
                local dkpBid = (sess.isDKP and f.dkpBidEB) and (tonumber(f.dkpBidEB:GetText()) or 0) or 0
                local msg = "LC_VOTE^"..sess.sid.."^"..this.btnIdx.."^"..comment.."^0^"..mySpec.."^"..tostring(dkpBid)
                SendLC(msg)
                local myName = UnitName("player")
                if myName then
                    sess.votes[myName] = {btn=this.btnIdx, btnName=this.btnName, comment=comment, roll=0, spec=mySpec, dkp=dkpBid}
                end
                f:Hide()
            end
        end)
        f.voteBtns[bi] = vb
    end

    -- Position: first popup uses the saved anchor; others attach below the last one
    local n = getn(popupOrder)
    if n == 0 then
        -- Sync runtime locals from DB so saved position survives reloads
        -- Only apply if the user has previously dragged the frame (pa ~= nil)
        local pa = GetLRDB().lcPopupAnchor
        if pa and pa.x ~= nil then
            popupAnchorPt    = "CENTER"
            popupAnchorRelPt = "BOTTOMLEFT"
            popupAnchorX     = pa.x
            popupAnchorY     = pa.y or 80
        end
        -- else: file-level defaults ("CENTER","CENTER",0,80) place it in screen center
        f:SetPoint(popupAnchorPt, UIParent, popupAnchorRelPt, popupAnchorX, popupAnchorY)
    else
        local lastF = popupWindows[popupOrder[n]]
        if lastF then
            f:SetPoint("TOP", lastF, "BOTTOM", 0, -8)
        else
            f:SetPoint(popupAnchorPt, UIParent, popupAnchorRelPt, popupAnchorX, popupAnchorY)
        end
    end

    popupWindows[s.sid] = f
    tinsert(popupOrder, s.sid)
    f:Show()
end

CloseVotePopup = function(sid)
    if sid then
        local f = popupWindows[sid]
        if f then f:Hide() end
    else
        -- close all: copy order first to avoid modification during iteration
        local tmp = {}; local tn = getn(popupOrder)
        for i = 1, tn do tmp[i] = popupOrder[i] end; tmp.n = tn
        for i = 1, getn(tmp) do
            local f = popupWindows[tmp[i]]
            if f then f:Hide() end
        end
    end
end

-- ============================================================
-- COUNCIL FRAME helpers
-- ============================================================

local function DoNormalAward(pname)
    local cs = GetCouncilSession()
    if not cs then return end
    local vd      = cs.votes and cs.votes[pname]
    local btnName = (vd and vd.btnName) or ""
    local roll    = (vd and vd.roll)    or 0
    local dkp     = (vd and vd.dkp)     or 0
    local aMsg = "LC_AWARD^"..cs.sid.."^"..pname.."^"..(cs.itemLink or "")
                 .."^"..btnName.."^"..tostring(roll).."^"..tostring(dkp)
    if not cs.isSim then
        local cidx = nil
        for ci = 1, 40 do
            local cn = GetMasterLootCandidate(ci)
            if not cn then break end
            if StripRealm(cn) == StripRealm(pname) then cidx = ci; break end
        end
        if not cidx then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[ART-LC]|r "..pname.." not a loot candidate.")
            return
        end
        GiveMasterLoot(cs.slot, cidx)
    end
    SendLC(aMsg)
    cs.awardCount = (cs.awardCount or 0) + 1
    if not cs.awardedTo then cs.awardedTo = {} end
    tinsert(cs.awardedTo, pname)
    if cs.slots then
        local newSlots = {}; newSlots.n = 0
        for si = 2, getn(cs.slots) do tinsert(newSlots, cs.slots[si]) end
        cs.slots   = newSlots
        cs.slot    = cs.slots[1] or cs.slot
    end
    local remaining = (cs.quantity or 1) - cs.awardCount
    if remaining <= 0 then cs.awarded = cs.awardedTo[1] end
    cs.pendingTmogWinner = nil
    CloseVotePopup(cs.sid)
    UpdateCouncilNav()
    RefreshCouncilRows()
end

-- ============================================================
-- COUNCIL FRAME
-- ============================================================
local councilFrame = nil
local CROW_H = 22
local CROW_N = 40

local function CreateCouncilFrame()
    local f = CreateFrame("Frame","ART_LC_CouncilFrame",UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetWidth(650); f:SetHeight(440)
    local _ca = GetLRDB().lcCouncilAnchor
    if _ca and _ca.x ~= nil then
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", _ca.x, _ca.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end
    f:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
    f:SetBackdropColor(0.06,0.06,0.1,0.97)
    f:SetBackdropBorderColor(0.7,0.5,0.8,1)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function() this:StartMoving() end)
    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local cx, cy = this:GetCenter()
        if cx and cy then
            local db = GetLRDB()
            db.lcCouncilAnchor = {x=cx, y=cy}
        end
    end)
    f:Hide()

    -- X close button (top-right corner)
    local closeBtn = MakeBtn(f,"X",20,20)
    closeBtn:SetPoint("TOPRIGHT",f,"TOPRIGHT",-6,-6)
    closeBtn.label:SetTextColor(1,0.4,0.4,1)
    closeBtn:SetScript("OnClick",function() f:Hide() end)

    local timerFS = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    timerFS:SetPoint("RIGHT",closeBtn,"LEFT",-8,0)
    timerFS:SetTextColor(0.8,0.8,1,1)
    f.timerFS = timerFS

    -- Title: anchored well to the right of where the nav arrows will sit (~90px from left)
    local titleFS = f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    titleFS:SetPoint("TOPLEFT",f,"TOPLEFT",90,-10)
    titleFS:SetText("Loot Council")
    titleFS:SetTextColor(1,0.82,0,1)
    f.titleFS = titleFS

    -- Item navigation arrows (shown when >1 item)
    local prevBtn = MakeBtn(f,"<",22,20)
    prevBtn:SetPoint("TOPLEFT",f,"TOPLEFT",12,-10)
    prevBtn:SetScript("OnClick",function()
        local n = getn(sessionOrder)
        if n < 2 then return end
        councilIdx = councilIdx - 1
        if councilIdx < 1 then councilIdx = n end
        UpdateCouncilNav(); RefreshCouncilRows()
    end)
    prevBtn:Hide(); f.prevBtn = prevBtn

    local nextBtn = MakeBtn(f,">",22,20)
    nextBtn:SetPoint("LEFT",prevBtn,"RIGHT",4,0)
    nextBtn:SetScript("OnClick",function()
        local n = getn(sessionOrder)
        if n < 2 then return end
        councilIdx = councilIdx + 1
        if councilIdx > n then councilIdx = 1 end
        UpdateCouncilNav(); RefreshCouncilRows()
    end)
    nextBtn:Hide(); f.nextBtn = nextBtn

    local navFS = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    navFS:SetPoint("LEFT",nextBtn,"RIGHT",4,0)
    navFS:SetTextColor(0.7,0.7,0.8,1)
    navFS:Hide(); f.navFS = navFS

    local iconBtn = CreateFrame("Button",nil,f)
    iconBtn:SetWidth(36); iconBtn:SetHeight(36)
    iconBtn:SetPoint("TOPLEFT",titleFS,"BOTTOMLEFT",0,-6)
    iconBtn:EnableMouse(true)
    local iconTexObj = iconBtn:CreateTexture(nil,"BORDER")
    iconTexObj:SetAllPoints(iconBtn)
    iconTexObj:SetTexCoord(0.06,0.94,0.06,0.94)
    iconTexObj:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    iconBtn:SetScript("OnEnter",function()
        if not this.hyperlink then return end
        GameTooltip:SetOwner(this,"ANCHOR_BOTTOM")
        GameTooltip:SetHyperlink(this.hyperlink)
        GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)
    iconBtn:SetScript("OnClick",function()
        if IsControlKeyDown() and this.itemLink then
            DressUpItemLink(this.itemLink)
        end
    end)
    f.iconBtn    = iconBtn
    f.iconTexObj = iconTexObj

    local nameBtn = CreateFrame("Button",nil,f)
    nameBtn:SetPoint("TOPLEFT",iconBtn,"TOPRIGHT",6,0)
    nameBtn:SetPoint("RIGHT",f,"RIGHT",-12,0)
    nameBtn:SetHeight(36)
    nameBtn:EnableMouse(true)
    local nameFS = nameBtn:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    nameFS:SetPoint("TOPLEFT",    nameBtn, "TOPLEFT",  0, 0)
    nameFS:SetPoint("BOTTOMRIGHT",nameBtn, "BOTTOMRIGHT", -232, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetJustifyV("MIDDLE")
    nameBtn:SetScript("OnEnter",function()
        if not this.hyperlink then return end
        GameTooltip:SetOwner(this,"ANCHOR_BOTTOM")
        GameTooltip:SetHyperlink(this.hyperlink)
        GameTooltip:Show()
    end)
    nameBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)
    nameBtn:SetScript("OnClick",function()
        if IsControlKeyDown() and this.itemLink then
            DressUpItemLink(this.itemLink)
        end
    end)
    f.nameBtn = nameBtn
    f.nameFS  = nameFS

    -- Top DV leader line (right side of item row, same blue as DV column)
    local dvTopFS = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    dvTopFS:SetWidth(224)
    dvTopFS:SetPoint("RIGHT",  f, "RIGHT", -12, 0)
    dvTopFS:SetPoint("TOP",    nameBtn, "TOP", 0, 0)
    dvTopFS:SetHeight(36)
    dvTopFS:SetJustifyH("RIGHT")
    dvTopFS:SetJustifyV("MIDDLE")
    dvTopFS:SetText("")
    f.dvTopFS = dvTopFS

    -- column headers (fixed positions; optional ones stored for show/hide)
    local function MakeHdr(xOff, txt)
        local h = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        h:SetPoint("TOPLEFT",f,"TOPLEFT",12+xOff,-84)
        h:SetText(txt); h:SetTextColor(0.5,0.5,0.6,1)
        return h
    end
    MakeHdr(0,   "Player")
    MakeHdr(87,  "Vote")
    MakeHdr(145, "DV")
    f.hClass    = MakeHdr(195, "Class")
    f.hSpec     = MakeHdr(247, "Spec")
    f.hGuildRank= MakeHdr(299, "Rank")
    f.hPrio     = MakeHdr(351, "Prio")
    f.hRoll     = MakeHdr(379, "Roll")
    MakeHdr(411, "Comment")
    -- right-side headers
    local hCV = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    hCV:SetPoint("TOPRIGHT",f,"TOPRIGHT",-(12+56+52+4),-84)
    hCV:SetText("Off.Vote"); hCV:SetTextColor(0.5,0.5,0.6,1)
    local hCnt = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    hCnt:SetPoint("TOPRIGHT",f,"TOPRIGHT",-(12+52+4),-84)
    hCnt:SetText("Cnt"); hCnt:SetTextColor(0.5,0.5,0.6,1)
    MakeDivider(f, f, -98)

    -- Scrollable rows area
    local rowSF = CreateFrame("ScrollFrame","ART_LC_RowSF",f)
    rowSF:SetPoint("TOPLEFT",    f,"TOPLEFT",  12, -104)
    rowSF:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-6, 38)
    rowSF:EnableMouseWheel(true)

    local rowContent = CreateFrame("Frame",nil,rowSF)
    rowContent:SetWidth(616)
    rowContent:SetHeight(CROW_N * CROW_H)
    rowSF:SetScrollChild(rowContent)

    rowSF:SetScript("OnMouseWheel",function()
        local step = CROW_H * 3
        local maxScroll = math.max(0, rowContent:GetHeight() - rowSF:GetHeight())
        local newVal = rowSF:GetVerticalScroll() + (arg1 > 0 and -step or step)
        rowSF:SetVerticalScroll(math.max(0, math.min(maxScroll, newVal)))
    end)
    f.rowSF      = rowSF
    f.rowContent = rowContent

    -- rows (children of rowContent, not the outer frame)
    local rows = {}
    for ri = 1, CROW_N do
        local row = CreateFrame("Frame",nil,rowContent)
        row:SetHeight(CROW_H)
        row:SetPoint("TOPLEFT", rowContent,"TOPLEFT",  0, -(ri-1)*CROW_H)
        row:SetPoint("TOPRIGHT",rowContent,"TOPRIGHT", 0, -(ri-1)*CROW_H)

        local function FS(xOff, w)
            local fs = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            fs:SetPoint("LEFT",row,"LEFT",xOff,0)
            fs:SetWidth(w); fs:SetJustifyH("LEFT")
            return fs
        end
        row.playerFS    = FS(0,   85)
        row.voteFS      = FS(87,  56)
        row.dvoteFS     = FS(145, 48)
        row.classFS     = FS(195, 50)
        row.specFS      = FS(247, 50)
        row.guildRankFS = FS(299, 50)
        row.prioFS      = FS(351, 26); row.prioFS:SetJustifyH("CENTER")
        row.rollFS      = FS(379, 30); row.rollFS:SetJustifyH("CENTER")
        row.commentFS   = FS(411, 60)

        local ab = MakeBtn(row,"Award",52,18)
        ab:SetPoint("RIGHT",row,"RIGHT",0,0)

        -- Count button: shows # of officer votes, tooltip lists who voted
        local countBtn = CreateFrame("Button",nil,row)
        countBtn:SetWidth(28); countBtn:SetHeight(18)
        countBtn:SetPoint("RIGHT",ab,"LEFT",-4,0)
        countBtn:EnableMouse(true)
        local countFS = countBtn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        countFS:SetAllPoints(countBtn); countFS:SetJustifyH("CENTER")
        countBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)
        row.countBtn = countBtn; row.countFS = countFS

        -- Officer Vote button: toggle this officer's endorsement for this row's player
        local cvb = MakeBtn(row,"Vote",52,18)
        cvb:SetPoint("RIGHT",countBtn,"LEFT",-4,0)
        row.cvoteBtn = cvb
        ab.rowPlayer = ""
        ab.rowIsDV   = false
        ab:SetScript("OnClick",function()
            local cs = GetCouncilSession()
            if not cs or this.rowPlayer == "" then return end
            local pname   = this.rowPlayer
            local isDVRow = this.rowIsDV

            -- onlyDV path: Award was clicked on a DV row
            if isDVRow then
                local dvCnt = 0
                if cs.dVotes then for _ in pairs(cs.dVotes) do dvCnt = dvCnt + 1 end end
                if dvCnt == 1 then
                    -- Single DV only → direct award, solo disenchant messages
                    if councilFrame then councilFrame:SetFrameStrata("DIALOG") end
                    StaticPopupDialogs["ART_LC_SOLO_TMOG"] = {
                        text = "Award transmog to "..pname.."?\nThey must trade it to a raid disenchanter.",
                        button1 = "Award", button2 = "Cancel",
                        OnAccept = function()
                            if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                            local cs2 = GetCouncilSession()
                            if not cs2 then return end
                            if not cs2.isSim then
                                local cidx = nil
                                for ci = 1, 40 do
                                    local cn = GetMasterLootCandidate(ci)
                                    if not cn then break end
                                    if StripRealm(cn) == StripRealm(pname) then cidx = ci; break end
                                end
                                if not cidx then
                                    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[ART-LC]|r "..pname.." not a loot candidate.")
                                    return
                                end
                                GiveMasterLoot(cs2.slot, cidx)
                            end
                            local dvd   = cs2.dVotes and cs2.dVotes[pname]
                            local dvDkp = (dvd and dvd.dkp) or 0
                            local aMsg  = "LC_AWARD_SOLO_TMOG^"..cs2.sid.."^"..pname.."^"..(cs2.itemLink or "").."^"..tostring(dvDkp)
                            SendLC(aMsg)
                            cs2.awardCount = (cs2.awardCount or 0) + 1
                            if not cs2.awardedTo then cs2.awardedTo = {} end
                            tinsert(cs2.awardedTo, pname)
                            if cs2.slots then
                                local newSlots = {}; newSlots.n = 0
                                for si = 2, getn(cs2.slots) do tinsert(newSlots, cs2.slots[si]) end
                                cs2.slots = newSlots
                                cs2.slot  = cs2.slots[1] or cs2.slot
                            end
                            local remaining = (cs2.quantity or 1) - cs2.awardCount
                            if remaining <= 0 then cs2.awarded = pname end
                            cs2.pendingTmogWinner = nil
                            CloseVotePopup(cs2.sid)
                            UpdateCouncilNav()
                            RefreshCouncilRows()
                        end,
                        OnCancel = function()
                            if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                        end,
                        OnHide = function()
                            if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                        end,
                        timeout = 0, whileDead = true, hideOnEscape = true,
                    }
                    StaticPopup_Show("ART_LC_SOLO_TMOG")
                else
                    -- Multiple DV only → select this DV person as winner with confirmation popup.
                    -- Clicking winner's own Award row again = cancel.
                    if cs.pendingTmogWinner == pname then
                        cs.pendingTmogWinner = nil
                        RefreshCouncilRows()
                        return
                    end
                    if councilFrame then councilFrame:SetFrameStrata("DIALOG") end
                    StaticPopupDialogs["ART_LC_DV_WIN_ASK"] = {
                        text = "Set "..pname.." as transmog winner?\nOther DV voters can then receive the item for transmog.",
                        button1 = "Yes", button2 = "Cancel",
                        OnAccept = function()
                            if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                            local cs2 = GetCouncilSession()
                            if not cs2 then return end
                            cs2.pendingTmogWinner = pname
                            RefreshCouncilRows()
                        end,
                        OnCancel = function()
                            if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                        end,
                        OnHide = function()
                            if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                        end,
                        timeout = 0, whileDead = true, hideOnEscape = true,
                    }
                    StaticPopup_Show("ART_LC_DV_WIN_ASK")
                end
                return
            end

            -- Standard path (non-DV row)
            -- Check if any DV votes exist in this session
            local hasDV = false
            if cs.dVotes then
                for _ in pairs(cs.dVotes) do hasDV = true; break end
            end
            if hasDV then
                -- If transmog mode is already active, cancel it first
                if cs.pendingTmogWinner then
                    cs.pendingTmogWinner = nil
                    RefreshCouncilRows()
                    return
                end
                -- Lower council frame below StaticPopup while dialog is shown
                if councilFrame then councilFrame:SetFrameStrata("DIALOG") end
                -- Ask: transmog award or normal?
                StaticPopupDialogs["ART_LC_TMOG_ASK"] = {
                    text = "Award "..pname.." — is this a Transmog award?",
                    button1 = "Yes (pick recipient)",
                    button2 = "No (award normally)",
                    OnAccept = function()
                        if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                        local cs2 = GetCouncilSession()
                        if not cs2 then return end
                        cs2.pendingTmogWinner = pname
                        RefreshCouncilRows()
                    end,
                    OnCancel = function()
                        if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                        DoNormalAward(pname)
                    end,
                    OnHide = function()
                        if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                    end,
                    timeout = 0, whileDead = true, hideOnEscape = false,
                }
                StaticPopup_Show("ART_LC_TMOG_ASK")
            else
                -- No DV votes — normal confirm popup
                if councilFrame then councilFrame:SetFrameStrata("DIALOG") end
                StaticPopupDialogs["ART_LC_AWARD"] = {
                    text = "Award item to "..pname.."?",
                    button1 = "Award", button2 = "Cancel",
                    OnAccept = function()
                        if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                        DoNormalAward(pname)
                    end,
                    OnCancel = function()
                        if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                    end,
                    OnHide = function()
                        if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                    end,
                    timeout = 0, whileDead = true, hideOnEscape = true,
                }
                StaticPopup_Show("ART_LC_AWARD")
            end
        end)
        row.awardBtn = ab

        -- Transmog recipient button: shown on DV rows after "Yes" to transmog question
        local tb = MakeBtn(row, "Tmog", 52, 18)
        tb:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        tb.dvPlayer = nil
        tb:SetScript("OnClick", function()
            local cs = GetCouncilSession()
            if not cs or not cs.pendingTmogWinner or not this.dvPlayer then return end
            local dvPerson  = this.dvPlayer
            local winPerson = cs.pendingTmogWinner
            if councilFrame then councilFrame:SetFrameStrata("DIALOG") end
            StaticPopupDialogs["ART_LC_TMOG"] = {
                text = "Give transmog to "..dvPerson.."?\n"..winPerson.." wins — "..dvPerson.." must trade to "..winPerson,
                button1 = "Confirm", button2 = "Cancel",
                OnAccept = function()
                    if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                    local cs2 = GetCouncilSession()
                    if not cs2 then return end
                    if not cs2.isSim then
                        local cidx = nil
                        for ci = 1, 40 do
                            local cn = GetMasterLootCandidate(ci)
                            if not cn then break end
                            if StripRealm(cn) == StripRealm(dvPerson) then cidx = ci; break end
                        end
                        if not cidx then
                            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[ART-LC]|r "..dvPerson.." not a loot candidate.")
                            return
                        end
                        GiveMasterLoot(cs2.slot, cidx)
                    end
                    local wvReg    = cs2.votes  and cs2.votes[winPerson]
                    local wvDV     = cs2.dVotes and cs2.dVotes[winPerson]
                    local isRegPass = wvReg and string.lower(wvReg.btnName or "") == "pass"
                    -- Prefer DV vote data when regular vote is Pass or absent
                    local wvd      = (wvReg and not isRegPass) and wvReg or (wvDV or wvReg)
                    local btnName2 = (wvd and wvd.btnName) or ""
                    local roll2    = (wvd and wvd.roll)    or 0
                    local dkp2     = (wvd and wvd.dkp)     or 0
                    local dvd2     = cs2.dVotes and cs2.dVotes[dvPerson]
                    local dvDkp    = (dvd2 and dvd2.dkp)   or 0
                    local dvSub    = GetPlayerSubgroup(winPerson) or 0
                    local aMsg = "LC_AWARD_TMOG^"..cs2.sid.."^"..winPerson.."^"..dvPerson.."^"..(cs2.itemLink or "")
                                 .."^"..btnName2.."^"..tostring(roll2).."^"..tostring(dkp2).."^"..tostring(dvSub).."^"..tostring(dvDkp)
                    SendLC(aMsg)
                    cs2.awardCount = (cs2.awardCount or 0) + 1
                    if not cs2.awardedTo then cs2.awardedTo = {} end
                    tinsert(cs2.awardedTo, winPerson)
                    if cs2.slots then
                        local newSlots = {}; newSlots.n = 0
                        for si = 2, getn(cs2.slots) do tinsert(newSlots, cs2.slots[si]) end
                        cs2.slots = newSlots
                        cs2.slot  = cs2.slots[1] or cs2.slot
                    end
                    local remaining = (cs2.quantity or 1) - cs2.awardCount
                    if remaining <= 0 then cs2.awarded = winPerson end
                    cs2.pendingTmogWinner = nil
                    CloseVotePopup(cs2.sid)
                    UpdateCouncilNav()
                    RefreshCouncilRows()
                end,
                OnCancel = function()
                    if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                end,
                OnHide = function()
                    if councilFrame then councilFrame:SetFrameStrata("FULLSCREEN_DIALOG") end
                end,
                timeout = 0, whileDead = true, hideOnEscape = true,
            }
            StaticPopup_Show("ART_LC_TMOG")
        end)
        tb:Hide()
        row.tmogBtn = tb

        row:Hide()
        rows[ri] = row
    end
    f.rows = rows

    local closeBtn = MakeBtn(f,"End Session",100,22)
    closeBtn:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",12,10)
    closeBtn.label:SetTextColor(1,0.4,0.4,1)
    closeBtn:SetScript("OnClick",function()
        local myName = UnitName("player")
        if not IsPlayerML() and not IsRaidLeader() then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[ART-LC]|r Only the Master Looter or Raid Leader can end the session.")
            return
        end
        -- close popups first, while popupWindows/popupOrder are still intact
        CloseVotePopup()
        for i = 1, getn(sessionOrder) do
            local s = allSessions[sessionOrder[i]]
            if s then
                SendLC("LC_CLOSE^"..s.sid)
                s.closed = true
            end
        end
        -- broadcast to close all frames on all raid members
        SendLC("LC_CLOSE_ALL")
        allSessions = {}; sessionOrder = {}; sessionOrder.n = 0
        popupWindows = {}; popupOrder = {}; popupOrder.n = 0
        councilIdx = 1
        CloseCouncilFrame()
    end)

    local statusFS = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    statusFS:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-12,12)
    statusFS:SetTextColor(0.6,0.8,0.6,1)
    f.statusFS = statusFS

    councilFrame = f
end

RefreshCouncilRows = function()
    local cs = GetCouncilSession()
    if not councilFrame or not cs then return end
    -- Prefer buttons transmitted by the ML in the session; fall back to local profile
    local prof = GetActiveLRProfile()
    local btnDefs = cs.buttons or (prof and prof.buttons) or {}

    -- Build list: only players who voted and did NOT choose Pass
    local entries = {}; local ec = 0
    local totalVotes = 0
    local prof2  = GetActiveLRProfile()
    EnsureCouncilSettings(prof2 or {})
    local cols   = (prof2 and prof2.councilCols) or {prio=true}
    local sortCfg = (prof2 and prof2.councilSort) or {primary="priority", secondary="roll"}
    local roster = GetRosterCache()

    -- Show/hide optional column headers
    if councilFrame.hClass     then if cols.class     then councilFrame.hClass:Show()     else councilFrame.hClass:Hide()     end end
    if councilFrame.hSpec      then if cols.spec      then councilFrame.hSpec:Show()      else councilFrame.hSpec:Hide()      end end
    if councilFrame.hGuildRank then if cols.guildRank then councilFrame.hGuildRank:Show() else councilFrame.hGuildRank:Hide() end end
    if councilFrame.hPrio      then if cols.prio      then councilFrame.hPrio:Show()      else councilFrame.hPrio:Hide()      end end
    if councilFrame.hRoll then
        if cs and cs.isDKP then councilFrame.hRoll:SetText("DKP") else councilFrame.hRoll:SetText("Roll") end
    end

    local seen = {}
    for name, vd in pairs(cs.votes) do
        totalVotes = totalVotes + 1
        local btnName = vd.btnName or ""
        local isPass  = string.lower(btnName) == "pass"
        local dvd     = cs.dVotes and cs.dVotes[name] or nil
        local hasDV   = dvd and (dvd.btnName or "") ~= ""
        local rc = roster[name] or {}
        seen[name] = true
        -- Main vote row (skip if Pass with no DV)
        if not isPass then
            ec = ec + 1
            local prio = 99
            if vd.btn and btnDefs[vd.btn] then prio = btnDefs[vd.btn].priority or 99 end
            entries[ec] = {
                player    = name,
                btn       = vd.btn,
                btnName   = btnName,
                priority  = prio,
                roll      = vd.roll or 0,
                dkp       = vd.dkp or 0,
                comment   = vd.comment or "",
                spec      = vd.spec or "",
                class     = rc.class or "",
                guildRank = rc.guildRank or "",
                isDVRow   = false,
            }
        end
        -- DV vote: separate row
        if hasDV then
            ec = ec + 1
            entries[ec] = {
                player    = name,
                btn       = nil,
                btnName   = dvd.btnName or "",
                priority  = 99,
                roll      = dvd.roll or 0,
                dkp       = dvd.dkp  or 0,
                comment   = "",
                spec      = dvd.spec or "",
                class     = rc.class or "",
                guildRank = rc.guildRank or "",
                isDVRow   = true,
            }
        end
    end
    if cs.dVotes then
        for name, dvd in pairs(cs.dVotes) do
            if not seen[name] then
                local rc = roster[name] or {}
                ec = ec + 1
                entries[ec] = {
                    player    = name,
                    btn       = nil,
                    btnName   = dvd.btnName or "",
                    priority  = 99,
                    roll      = dvd.roll or 0,
                    dkp       = dvd.dkp  or 0,
                    comment   = "",
                    spec      = dvd.spec or "",
                    class     = rc.class or "",
                    guildRank = rc.guildRank or "",
                    isDVRow   = true,
                }
            end
        end
    end

    local function sortVal(e, field)
        if field == "priority"  then return e.priority or 99
        elseif field == "roll"  then return -(e.roll or 0)
        elseif field == "dkp"   then return -(e.dkp or 0)
        elseif field == "name"  then return e.player or ""
        elseif field == "class" then return e.class or ""
        elseif field == "guildRank" then return e.guildRank or ""
        end
        return 0
    end
    local prim = sortCfg.primary   or "priority"
    local sec  = sortCfg.secondary or "roll"
    local terc = sortCfg.tertiary  or "name"
    -- Detect onlyDV: no non-DV, non-pass entries
    local nonDVCount = 0
    local dvCount    = 0
    for i = 1, ec do
        if entries[i].isDVRow then dvCount = dvCount + 1
        else nonDVCount = nonDVCount + 1 end
    end
    local onlyDV = (nonDVCount == 0 and dvCount > 0)

    table.sort(entries, function(a, b)
        -- DV rows always sort after non-DV rows
        if a.isDVRow ~= b.isDVRow then return b.isDVRow end
        -- DV vs DV: sort by highest roll (LC) or highest DKP bid (DKP mode)
        if a.isDVRow and b.isDVRow then
            if cs and cs.isDKP then
                local da, db = -(a.dkp or 0), -(b.dkp or 0)
                if da ~= db then return da < db end
            else
                local ra, rb = -(a.roll or 0), -(b.roll or 0)
                if ra ~= rb then return ra < rb end
            end
            return (a.player or "") < (b.player or "")
        end
        -- Non-DV vs non-DV: use configured sort
        local av1, bv1 = sortVal(a, prim), sortVal(b, prim)
        if av1 ~= bv1 then return av1 < bv1 end
        local av2, bv2 = sortVal(a, sec),  sortVal(b, sec)
        if av2 ~= bv2 then return av2 < bv2 end
        local av3, bv3 = sortVal(a, terc), sortVal(b, terc)
        if av3 ~= bv3 then return av3 < bv3 end
        return (a.player or "") < (b.player or "")
    end)

    for ri = 1, CROW_N do
        local row = councilFrame.rows[ri]
        if ri <= ec then
            local e = entries[ri]
            if e.isDVRow then
                row.playerFS:SetText("|cFF88CCFF"..e.player.." (DV)|r")
                row.voteFS:SetText(e.btnName ~= "" and ("|cFF88CCFF"..e.btnName.."|r") or "")
            else
                row.playerFS:SetText(e.player)
                row.voteFS:SetText(e.btnName ~= "" and ("|cFF00FF00"..e.btnName.."|r") or "")
            end
            row.dvoteFS:SetText("")
            row.classFS:SetText(    cols.class     and e.class     or "")
            row.specFS:SetText(     cols.spec      and e.spec      or "")
            row.guildRankFS:SetText(cols.guildRank and e.guildRank or "")
            row.prioFS:SetText(cols.prio and (e.priority < 99 and tostring(e.priority) or "-") or "")
            if cs and cs.isDKP then
                row.rollFS:SetText(e.dkp > 0 and "|cFF88CCFF"..tostring(e.dkp).."|r" or "")
            else
                row.rollFS:SetText(e.roll > 0 and "|cFFFFD700"..tostring(e.roll).."|r" or "")
            end
            row.commentFS:SetText(e.comment)
            local canAward = (cs.isML or IsRaidLeader()) and not cs.awarded
            -- Award button visibility:
            --   Non-DV rows: always when canAward
            --   DV rows: only in onlyDV mode, phase 1 (no winner yet) = all rows;
            --            phase 2 (winner chosen) = only winner row (to cancel)
            local showAward
            if e.isDVRow then
                showAward = canAward and onlyDV
                            and (not cs.pendingTmogWinner or e.player == cs.pendingTmogWinner)
            else
                showAward = canAward
            end
            row.awardBtn.rowPlayer = showAward and e.player or ""
            row.awardBtn.rowIsDV   = e.isDVRow
            if showAward then row.awardBtn:Show() else row.awardBtn:Hide() end
            if row.tmogBtn then
                -- Show Tmog on DV rows when pendingTmogWinner is set.
                -- In onlyDV mode: exclude winner's own row (they ARE the winner, can't be recipient).
                -- In normal mode: show on all DV rows (MS winner has no DV row, or does — either way allowed).
                local showTmog = e.isDVRow and canAward and cs.pendingTmogWinner
                                 and (not onlyDV or e.player ~= cs.pendingTmogWinner)
                if showTmog then
                    row.tmogBtn.dvPlayer = e.player
                    row.tmogBtn:Show()
                else
                    row.tmogBtn:Hide()
                end
            end

            -- Officer vote button
            local target = e.player
            local myName = UnitName("player")
            local cv = cs.councilVotes
            local myVoted = cv[target] and cv[target][myName]
            if myVoted then
                row.cvoteBtn.label:SetTextColor(1,0.82,0,1)
                row.cvoteBtn:SetBackdropBorderColor(1,0.82,0,1)
                row.cvoteBtn:SetBackdropColor(0.22,0.18,0.04,0.95)
            else
                row.cvoteBtn.label:SetTextColor(0.85,0.85,0.85,1)
                row.cvoteBtn:SetBackdropBorderColor(0.35,0.35,0.42,1)
                row.cvoteBtn:SetBackdropColor(0.1,0.1,0.14,0.95)
            end
            row.cvoteBtn:SetScript("OnClick",function()
                local s = GetCouncilSession()
                if not s or s.closed then return end
                local me = UnitName("player")
                if not me then return end
                s.councilVotes[target] = s.councilVotes[target] or {}
                if s.councilVotes[target][me] then
                    s.councilVotes[target][me] = nil
                    SendLC("LC_CVOTE_REVOKE^"..s.sid.."^"..target)
                else
                    s.councilVotes[target][me] = true
                    SendLC("LC_CVOTE^"..s.sid.."^"..target)
                end
                RefreshCouncilRows()
            end)
            if not e.isDVRow and (cs.isOfficer or cs.isML) and not cs.awarded then
                row.cvoteBtn:Show()
            else
                row.cvoteBtn:Hide()
            end

            -- Count + tooltip
            local voters = {}; local vc2 = 0
            if not e.isDVRow and cv[target] then
                for voter in pairs(cv[target]) do
                    if cv[target][voter] then vc2=vc2+1; voters[vc2]=voter end
                end
            end
            table.sort(voters)
            row.countFS:SetText(not e.isDVRow and (vc2 > 0 and "|cFFFFD700"..tostring(vc2).."|r" or "0") or "")
            row.countBtn:SetScript("OnEnter",function()
                GameTooltip:SetOwner(this,"ANCHOR_TOPLEFT")
                GameTooltip:AddLine("Officer Votes: "..tostring(vc2),1,1,1)
                if vc2 > 0 then
                    for vi = 1, vc2 do
                        GameTooltip:AddLine(voters[vi],0.9,0.9,0.9)
                    end
                else
                    GameTooltip:AddLine("None",0.6,0.6,0.6)
                end
                GameTooltip:Show()
            end)
            row:Show()
        else
            row:Hide()
        end
    end

    local awardedTo = cs.awardedTo
    if awardedTo and getn(awardedTo) > 0 then
        local names = awardedTo[1]
        for ai = 2, getn(awardedTo) do names = names..", "..awardedTo[ai] end
        if cs.awarded then
            councilFrame.statusFS:SetText("|cFF88FF88Awarded: "..names.."|r")
        else
            local remaining = (cs.quantity or 1) - (cs.awardCount or 0)
            councilFrame.statusFS:SetText("|cFFFFD700Awarded: "..names.." — "..tostring(remaining).." remaining|r")
        end
    else
        councilFrame.statusFS:SetText("Votes: "..totalVotes.." (shown: "..ec..")")
    end

    -- Update scroll range to match actual entry count
    local contentH = math.max(ec * CROW_H, 1)
    councilFrame.rowContent:SetHeight(contentH)
    local sfH = councilFrame.rowSF:GetHeight()
    if sfH and sfH > 0 then
        local maxScroll = math.max(0, contentH - sfH)
        -- clamp current scroll position if content shrank
        local cur = councilFrame.rowSF:GetVerticalScroll()
        if cur > maxScroll then
            councilFrame.rowSF:SetVerticalScroll(maxScroll)
        end
    end
end

UpdateCouncilNav = function()
    if not councilFrame then return end
    local n = getn(sessionOrder)
    local cs = GetCouncilSession()
    -- nav arrows
    if n > 1 then
        councilFrame.prevBtn:Show(); councilFrame.nextBtn:Show()
        councilFrame.navFS:SetText(tostring(councilIdx).."/"..tostring(n))
        councilFrame.navFS:Show()
    else
        councilFrame.prevBtn:Hide(); councilFrame.nextBtn:Hide()
        councilFrame.navFS:Hide()
    end
    -- item icon + name
    if cs then
        local hl = ItemHyperlink(cs.itemLink)
        councilFrame.iconTexObj:SetTexture(cs.iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
        councilFrame.iconBtn.hyperlink = hl
        councilFrame.iconBtn.itemLink  = cs.itemLink
        councilFrame.nameBtn.hyperlink = hl
        councilFrame.nameBtn.itemLink  = cs.itemLink
        local nameText = cs.itemLink or "Unknown"
        local qty = cs.quantity or 1
        local awarded = cs.awardCount or 0
        local remaining = qty - awarded
        if qty > 1 then
            if remaining > 0 then
                nameText = nameText.." |cFFFFFFFFx"..tostring(remaining).."/"..tostring(qty).."|r"
            else
                nameText = nameText.." |cFF88FF88x"..tostring(qty).." (all awarded)|r"
            end
        end
        councilFrame.nameFS:SetText(nameText)
        councilFrame.titleFS:SetText(cs and cs.isDKP and "DKP Bidding" or "Loot Council")
    end

    -- Top info: DKP shows highest bidder; LC shows top DV voter
    if councilFrame.dvTopFS then
        local topText = ""
        if cs and cs.isDKP then
            -- DKP: find highest bidder from cs.votes
            local topName, topBid = nil, 0
            if cs.votes then
                for name, vd in pairs(cs.votes) do
                    if (vd.dkp or 0) > topBid then
                        topBid = vd.dkp or 0
                        topName = name
                    end
                end
            end
            if topName and topBid > 0 then
                local nameColor = "|cFFCCCCCC"
                for ri = 1, GetNumRaidMembers() do
                    local rname, _, _, _, _, fileName = GetRaidRosterInfo(ri)
                    if rname and rname == topName and fileName then
                        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[string.upper(fileName)]
                        if cc then
                            nameColor = string.format("|cFF%02X%02X%02X",
                                math.floor((cc.r or 1)*255),
                                math.floor((cc.g or 1)*255),
                                math.floor((cc.b or 1)*255))
                        end
                        break
                    end
                end
                topText = nameColor..topName.."|r|cFF88CCFF Bid: "..topBid.."|r"
            end
        else
            -- LC: top DV voter
            local dvTopName, dvTopBtnName, dvTopRoll = nil, nil, -1
            if cs and cs.dVotes then
                for name, dv in pairs(cs.dVotes) do
                    if (dv.roll or 0) > dvTopRoll then
                        dvTopRoll    = dv.roll or 0
                        dvTopName    = name
                        dvTopBtnName = dv.btnName or ""
                    end
                end
            end
            if dvTopName then
                local nameColor = "|cFFCCCCCC"
                for ri = 1, GetNumRaidMembers() do
                    local rname, _, _, _, _, fileName = GetRaidRosterInfo(ri)
                    if rname and rname == dvTopName and fileName then
                        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[string.upper(fileName)]
                        if cc then
                            nameColor = string.format("|cFF%02X%02X%02X",
                                math.floor((cc.r or 1)*255),
                                math.floor((cc.g or 1)*255),
                                math.floor((cc.b or 1)*255))
                        end
                        break
                    end
                end
                local rollStr = dvTopRoll > 0 and " Rolled "..dvTopRoll or ""
                topText = nameColor..dvTopName.."|r"
                        .."|cFF88CCFF DV("..dvTopBtnName..")"..rollStr.."|r"
            end
        end
        councilFrame.dvTopFS:SetText(topText)
    end
end

OpenCouncilFrame = function()
    if not councilFrame then CreateCouncilFrame() end
    UpdateCouncilNav()
    councilFrame.timerFS:SetText("")
    -- reset scroll to top when opening fresh
    councilFrame.rowSF:SetVerticalScroll(0)
    RefreshCouncilRows()
    councilFrame:Show()
end

CloseCouncilFrame = function()
    if councilFrame then councilFrame:Hide() end
end

-- ============================================================
-- TEST SIMULATION
-- ============================================================
SimulateLoot = function()
    local prof = GetActiveLRProfile()
    if not prof or (prof.mode ~= "lootcouncil" and prof.mode ~= "dkp") then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[ART-LC]|r Set profile mode to Loot Council or DKP first.")
        return
    end
    local isDKP = (prof.mode == "dkp")
    -- Close any existing sessions
    CloseVotePopup()
    if councilFrame then councilFrame:Hide() end
    -- Reset session state
    allSessions = {}
    sessionOrder = {}; sessionOrder.n = 0
    popupWindows = {}; popupOrder = {}; popupOrder.n = 0
    councilIdx = 1

    local timerSec = prof.timer or 60
    local buttons  = prof.buttons or {}
    local now      = GetTime()
    for idx = 1, getn(SIM_ITEMS) do
        local item = SIM_ITEMS[idx]
        local sid  = "SIM-"..tostring(idx)
        local iconPath = item.iconPath or GetItemTexture(item.itemLink)
        local s = {
            sid          = sid,
            slot         = 0,
            itemLink     = item.itemLink,
            quality      = item.quality,
            iconPath     = iconPath,
            votes        = {},
            dVotes       = {},
            councilVotes = {},
            buttons      = buttons,
            isML         = true,
            isOfficer    = true,
            isDKP        = isDKP,
            timerEnd     = now + timerSec,
            closed       = false,
            isSim        = true,
        }
        AddSession(s)
        local openMsg = "LC_OPEN^"..sid.."^0^"..item.itemLink.."^"..tostring(item.quality)
                        .."^"..iconPath.."^"..EncodeOfficers(prof.officers)
                        .."^"..(isDKP and "1" or "0")
                        .."^"..tostring(timerSec)..EncodeLCButtons(buttons)
        SendLC(openMsg)
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00CCFF[ART-LC]|r [Sim] "..item.itemLink)
    end
    -- Open vote popups for all items simultaneously (stacked)
    for i = 1, getn(sessionOrder) do
        local sess = allSessions[sessionOrder[i]]
        if sess then OpenVotePopup(sess) end
    end
    councilIdx = 1
    if not isDKP then
        OpenCouncilFrame()
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFF88CCFF[ART-LC]|r [Sim] DKP: council frame opens after timer expires.")
    end
end

-- ============================================================
-- Timer OnUpdate
-- ============================================================
local lcTimerFrame = CreateFrame("Frame","ART_LC_Timer",UIParent)
lcTimerFrame:SetScript("OnUpdate",function()
    local now = GetTime()
    -- Update timer on every open vote popup
    for i = 1, getn(popupOrder) do
        local sid = popupOrder[i]
        local f = popupWindows[sid]
        local sess = allSessions[sid]
        if f and f:IsShown() and sess and not sess.closed then
            local rem = sess.timerEnd - now
            if rem < 0 then rem = 0 end
            f.timerFS:SetText(floor(rem/60)..":"..sfmt("%02d", mmod(floor(rem),60)))
            if rem <= 0 then
                if not sess.timerExpired then
                    sess.timerExpired = true
                    -- Close the vote popup locally; council frame stays open for ML to award
                    f:Hide()
                end
            end
        end
    end
    -- DKP: auto-open council frame for officers/ML when bidding timer expires
    for i = 1, getn(sessionOrder) do
        local _s = allSessions[sessionOrder[i]]
        if _s and _s.isDKP and not _s.closed and not _s.councilOpened and now >= _s.timerEnd then
            _s.councilOpened = true
            if _s.isOfficer or _s.isML then
                if not councilFrame or not councilFrame:IsShown() then
                    councilIdx = i
                    OpenCouncilFrame()
                else
                    UpdateCouncilNav(); RefreshCouncilRows()
                end
            end
        end
    end

    -- Council frame timer (follows GetCouncilSession() = displayed item)
    if councilFrame and councilFrame:IsShown() then
        local cs = GetCouncilSession()
        if cs and not cs.closed then
            local rem = cs.timerEnd - now
            if rem < 0 then rem = 0 end
            if rem > 0 then
                local col = rem <= 10 and "FF4444" or "AAAAFF"
                councilFrame.timerFS:SetText("|cFF"..col..floor(rem/60)..":"..sfmt("%02d",mmod(floor(rem),60)).."|r")
            else
                councilFrame.timerFS:SetText("|cFFFF4444Expired|r")
            end
            if not cs.lastRefresh or (now - cs.lastRefresh) >= 1 then
                cs.lastRefresh = now
                RefreshCouncilRows()
            end
        end
    end
end)

-- ============================================================
-- ShouldTrigger
-- ============================================================
local function ShouldTrigger(quality, itemLink, prof)
    if not prof or (prof.mode ~= "lootcouncil" and prof.mode ~= "dkp") then return false end
    -- Specific item IDs always trigger regardless of mode
    if prof.triggerItemIds and itemLink then
        local _, _, idStr = strfind(itemLink, "item:(%d+):")
        if idStr then
            local id = tonumber(idStr)
            if id and prof.triggerItemIds[id] then return true end
        end
    end
    -- Quality trigger only when enabled (default: enabled)
    if prof.triggerByQuality ~= false then
        if quality >= (prof.triggerMinQuality or 4) then return true end
    end
    return false
end

-- ============================================================
-- Message handler
-- ============================================================
OnLCMessage = function(sender, msg)
    sender = StripRealm(sender)
    local parts = {}; local pc = 0
    for piece in string.gfind(msg.."^","([^^]*)%^") do
        pc = pc+1; parts[pc] = piece
    end
    if pc == 0 then return end
    local tag = parts[1]

    if tag == "LC_OPEN" then
        local sid      = parts[2]
        if allSessions[sid] then return end  -- already registered (e.g. ML-side sim sent to self)
        -- Security: only accept LC_OPEN from the actual Master Looter or Raid Leader
        do
            local validSender = false
            local lootMethod, partyML, raidML = GetLootMethod()
            if lootMethod == "master" then
                -- Check master looter name
                local mlUnit
                if raidML ~= nil then
                    mlUnit = "raid"..raidML
                elseif partyML ~= nil then
                    mlUnit = (partyML == 0) and "player" or ("party"..partyML)
                end
                if mlUnit and UnitName(mlUnit) == sender then
                    validSender = true
                end
            end
            if not validSender then
                -- Also accept from the raid leader as fallback
                local numRaid = GetNumRaidMembers()
                for ri = 1, numRaid do
                    local rname, rrank = GetRaidRosterInfo(ri)
                    if rname == sender and rrank == 2 then
                        validSender = true
                        break
                    end
                end
            end
            if not validSender then return end
        end
        local slot     = tonumber(parts[3])
        local itemLink = parts[4]
        local quality  = tonumber(parts[5]) or 0
        -- Buttons are transmitted by the ML in parts[6+]; decode them.
        -- Fall back to local profile buttons if the message predates this format.
        local prof   = GetActiveLRProfile()
        local myName = UnitName("player")
        local iconPath = (parts[6] and parts[6] ~= "") and parts[6]
                         or "Interface\\Icons\\INV_Misc_QuestionMark"
        -- parts[7] = officers (semicolon-separated), parts[8+] = buttons
        -- Older messages (no officers field) have buttons at parts[7] — detected by presence of "~"
        local isDKP = false
        local timerFromMsg    = nil
        local quantityFromMsg = nil
        local officers = {}
        local btnStart = 7
        if parts[7] and string.find(parts[7], "~", 1, true) == nil then
            -- No "~" → this is the officers field (names never contain "~")
            local offStr = parts[7] or ""
            if offStr ~= "" then
                for n in string.gfind(offStr..";", "([^;]*);") do
                    if n ~= "" then tinsert(officers, n) end
                end
            end
            btnStart = 8
            -- Check for isDKP flag at parts[8] ("0" or "1", no "~")
            if parts[8] and parts[8] ~= "" and string.find(parts[8], "~", 1, true) == nil then
                isDKP = (parts[8] == "1")
                btnStart = 9
                -- Check for timer at parts[9] (pure number, no "~")
                if parts[9] and parts[9] ~= "" and string.find(parts[9], "~", 1, true) == nil
                   and tonumber(parts[9]) then
                    timerFromMsg = tonumber(parts[9])
                    btnStart = 10
                    -- Check for quantity at parts[10] (pure number, no "~")
                    if parts[10] and parts[10] ~= "" and string.find(parts[10], "~", 1, true) == nil
                       and tonumber(parts[10]) then
                        quantityFromMsg = tonumber(parts[10])
                        btnStart = 11
                    end
                end
            end
        end
        -- Fall back to local profile officers if none transmitted (backward compat)
        if getn(officers) == 0 then
            officers = (prof and prof.officers) or {}
        end
        local buttons
        if pc >= btnStart then
            buttons = DecodeLCButtons(parts, btnStart)
        end
        if not buttons or getn(buttons) == 0 then
            buttons = (prof and prof.buttons) or {
                {name="Main Spec", priority=1},
                {name="Off Spec",  priority=2},
                {name="Pass",      priority=6},
            }
        end
        local timer    = timerFromMsg    or (prof and prof.timer) or 60
        local quantity = quantityFromMsg or 1
        local newS = {
            sid          = sid,
            slot         = slot,
            slots        = {slot},
            quantity     = quantity,
            awardCount   = 0,
            awardedTo    = {},
            itemLink     = itemLink,
            quality      = quality,
            iconPath     = iconPath,
            votes        = {},
            dVotes       = {},
            councilVotes = {},
            buttons      = buttons,
            isML         = (sender == myName),
            isOfficer    = IsOfficer(myName, officers),
            isDKP        = isDKP,
            timerEnd     = GetTime() + timer,
            closed       = false,
        }
        AddSession(newS)
        OpenVotePopup(newS)
        if not isDKP then
            if newS.isOfficer or newS.isML then
                if not councilFrame or not councilFrame:IsShown() then
                    councilIdx = getn(sessionOrder)
                    OpenCouncilFrame()
                else
                    UpdateCouncilNav()
                end
            end
        end
        -- DKP: council frame opens after timer expires (lcTimerFrame OnUpdate)

    elseif tag == "LC_VOTE" then
        local s = allSessions[parts[2]]; if not s then return end
        local btnIdx  = tonumber(parts[3])
        local comment = parts[4] or ""
        local rollVal = tonumber(parts[5]) or 0
        local spec    = parts[6] or ""
        local dkpBid  = tonumber(parts[7]) or 0
        local btnName = ""
        if s.buttons and btnIdx and s.buttons[btnIdx] then
            btnName = s.buttons[btnIdx].name or ""
        end
        if sender then
            s.votes[sender] = {btn=btnIdx, btnName=btnName, comment=comment, roll=rollVal, spec=spec, dkp=dkpBid}
        end
        if councilFrame and councilFrame:IsShown() and GetCouncilSession() == s then
            RefreshCouncilRows()
        end

    elseif tag == "LC_AWARD" then
        local s          = allSessions[parts[2]]
        local winnerName = parts[3]
        local aLink      = parts[4] or ""
        local voteName   = parts[5] or ""
        local roll       = tonumber(parts[6]) or 0
        local dkp        = tonumber(parts[7]) or 0
        -- Build announcement line
        local annLine
        if voteName ~= "" then
            annLine = "|cffffff00[aRT]|r "..winnerName.." receives "..aLink.." for "..voteName
            if dkp > 0 then
                annLine = annLine.." ("..tostring(dkp).." DKP)"
            elseif roll > 0 then
                annLine = annLine.." (Roll: "..tostring(roll)..")"
            end
        else
            annLine = "|cffffff00[aRT]|r "..winnerName.." receives "..aLink
        end
        -- Send to raid chat (ML who calls GiveMasterLoot is the only one who can
        -- SendChatMessage to RAID; all others just print locally via the addon msg)
        local myName = UnitName("player")
        if myName == sender or (not sender) then
            -- We are the awarder — send to raid chat so everyone sees it in chat log
            if GetNumRaidMembers() > 0 then
                SendChatMessage(annLine, "RAID")
            elseif GetNumPartyMembers() > 0 then
                SendChatMessage(annLine, "PARTY")
            else
                DEFAULT_CHAT_FRAME:AddMessage(annLine)
            end
        else
            -- Non-awarder: print the line locally (already received via addon msg)
            DEFAULT_CHAT_FRAME:AddMessage(annLine)
        end
        if s then
            s.awardCount = (s.awardCount or 0) + 1
            if not s.awardedTo then s.awardedTo = {} end
            tinsert(s.awardedTo, winnerName)
            -- Remove front slot (non-ML clients don't have GiveMasterLoot but track state)
            if s.slots and getn(s.slots) > 0 then
                local newSlots = {}; newSlots.n = 0
                for si = 2, getn(s.slots) do tinsert(newSlots, s.slots[si]) end
                s.slots = newSlots
            end
            local remaining = (s.quantity or 1) - s.awardCount
            if remaining <= 0 then
                s.awarded = winnerName
            end
            CloseVotePopup(s.sid)
        end
        if councilFrame and councilFrame:IsShown() then
            UpdateCouncilNav(); RefreshCouncilRows()
        end

    elseif tag == "LC_AWARD_TMOG" then
        local s          = allSessions[parts[2]]
        local winnerName = parts[3]
        local tmogName   = parts[4]
        local aLink      = parts[5] or ""
        local voteName   = parts[6] or ""
        local roll       = tonumber(parts[7]) or 0
        local dkp        = tonumber(parts[8]) or 0
        local dvSub      = tonumber(parts[9]) or 0
        local dvDkp      = tonumber(parts[10]) or 0
        -- Line 1: winner announcement with vote type, DKP or roll
        local line1
        if voteName ~= "" then
            line1 = "|cffffff00[aRT]|r "..winnerName.." wins "..aLink.." for "..voteName
            if dkp > 0 then
                line1 = line1.." ("..tostring(dkp).." DKP)"
            elseif roll > 0 then
                line1 = line1.." (Roll: "..tostring(roll)..")"
            end
        else
            line1 = "|cffffff00[aRT]|r "..winnerName.." wins "..aLink
        end
        -- Line 2: transmog recipient (+ DKP bid if present)
        local line2 = "|cffffff00[aRT]|r "..tmogName.." receives the transmog"
        if dvDkp > 0 then line2 = line2.." ("..tostring(dvDkp).." DKP)" end
        -- Line 3: trade instruction with subgroup
        local subStr = dvSub > 0 and " (Group "..tostring(dvSub)..")" or ""
        local line3 = "|cffffff00[aRT]|r "..tmogName.." "..aLink.." please trade to "..winnerName..subStr
        local myName = UnitName("player")
        if myName == sender or (not sender) then
            local ch
            if GetNumRaidMembers()  > 0 then ch = "RAID"
            elseif GetNumPartyMembers() > 0 then ch = "PARTY" end
            if ch then
                SendChatMessage(line1, ch)
                SendChatMessage(line2, ch)
                SendChatMessage(line3, ch)
            else
                DEFAULT_CHAT_FRAME:AddMessage(line1)
                DEFAULT_CHAT_FRAME:AddMessage(line2)
                DEFAULT_CHAT_FRAME:AddMessage(line3)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage(line1)
            DEFAULT_CHAT_FRAME:AddMessage(line2)
            DEFAULT_CHAT_FRAME:AddMessage(line3)
        end
        if s then
            s.awardCount = (s.awardCount or 0) + 1
            if not s.awardedTo then s.awardedTo = {} end
            tinsert(s.awardedTo, winnerName)
            if s.slots and getn(s.slots) > 0 then
                local newSlots = {}; newSlots.n = 0
                for si = 2, getn(s.slots) do tinsert(newSlots, s.slots[si]) end
                s.slots = newSlots
            end
            local remaining = (s.quantity or 1) - s.awardCount
            if remaining <= 0 then s.awarded = winnerName end
            CloseVotePopup(s.sid)
        end
        if councilFrame and councilFrame:IsShown() then
            UpdateCouncilNav(); RefreshCouncilRows()
        end

    elseif tag == "LC_AWARD_SOLO_TMOG" then
        local s        = allSessions[parts[2]]
        local tmogName = parts[3]
        local aLink    = parts[4] or ""
        local dvDkp    = tonumber(parts[5]) or 0
        -- Line 1: transmog recipient announcement
        local line1 = "|cffffff00[aRT]|r "..tmogName.." receives the transmog"
        if dvDkp > 0 then line1 = line1.." ("..tostring(dvDkp).." DKP)" end
        -- Line 2: trade to disenchanter
        local line2 = "|cffffff00[aRT]|r "..tmogName.." "..aLink.." please trade to a raid disenchanter."
        local myName = UnitName("player")
        if myName == sender or (not sender) then
            local ch
            if GetNumRaidMembers()    > 0 then ch = "RAID"
            elseif GetNumPartyMembers() > 0 then ch = "PARTY" end
            if ch then
                SendChatMessage(line1, ch)
                SendChatMessage(line2, ch)
            else
                DEFAULT_CHAT_FRAME:AddMessage(line1)
                DEFAULT_CHAT_FRAME:AddMessage(line2)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage(line1)
            DEFAULT_CHAT_FRAME:AddMessage(line2)
        end
        if s then
            s.awardCount = (s.awardCount or 0) + 1
            if not s.awardedTo then s.awardedTo = {} end
            tinsert(s.awardedTo, tmogName)
            if s.slots and getn(s.slots) > 0 then
                local newSlots = {}; newSlots.n = 0
                for si = 2, getn(s.slots) do tinsert(newSlots, s.slots[si]) end
                s.slots = newSlots
            end
            local remaining = (s.quantity or 1) - s.awardCount
            if remaining <= 0 then s.awarded = tmogName end
            CloseVotePopup(s.sid)
        end
        if councilFrame and councilFrame:IsShown() then
            UpdateCouncilNav(); RefreshCouncilRows()
        end

    elseif tag == "LC_CVOTE" then
        local s = allSessions[parts[2]]; if not s then return end
        local target = parts[3]
        if target and target ~= "" and sender then
            s.councilVotes[target] = s.councilVotes[target] or {}
            s.councilVotes[target][sender] = true
            if councilFrame and councilFrame:IsShown() and GetCouncilSession() == s then
                RefreshCouncilRows()
            end
        end

    elseif tag == "LC_CVOTE_REVOKE" then
        local s = allSessions[parts[2]]; if not s then return end
        local target = parts[3]
        if target and target ~= "" and sender then
            if s.councilVotes[target] then
                s.councilVotes[target][sender] = nil
            end
            if councilFrame and councilFrame:IsShown() and GetCouncilSession() == s then
                RefreshCouncilRows()
            end
        end

    elseif tag == "LC_DVOTE" then
        local s = allSessions[parts[2]]; if not s then return end
        local btnIdx  = tonumber(parts[3])
        local comment = parts[4] or ""
        local rollVal = tonumber(parts[5]) or 0
        local spec    = parts[6] or ""
        local dkpBid  = tonumber(parts[7]) or 0
        local btnName = ""
        if s.buttons and btnIdx and s.buttons[btnIdx] then
            btnName = s.buttons[btnIdx].name or ""
        end
        if sender then
            s.dVotes[sender] = {btn=btnIdx, btnName=btnName, comment=comment, roll=rollVal, spec=spec, dkp=dkpBid}
        end
        if councilFrame and councilFrame:IsShown() and GetCouncilSession() == s then
            UpdateCouncilNav(); RefreshCouncilRows()
        end

    elseif tag == "LC_CLOSE" then
        local s = allSessions[parts[2]]
        if s then
            s.closed = true
            CloseVotePopup(s.sid)
            RemoveSession(s.sid)
        end
        if getn(sessionOrder) == 0 then CloseCouncilFrame()
        elseif councilFrame and councilFrame:IsShown() then UpdateCouncilNav(); RefreshCouncilRows() end

    elseif tag == "LC_CLOSE_ALL" then
        -- ML/Leader ended session — close all frames on this client
        CloseVotePopup()
        allSessions = {}; sessionOrder = {}; sessionOrder.n = 0
        popupWindows = {}; popupOrder = {}; popupOrder.n = 0
        councilIdx = 1
        CloseCouncilFrame()
    end
end

-- ============================================================
-- LOOT_OPENED detection
-- ============================================================
local lcLootFrame = CreateFrame("Frame","ART_LC_LootFrame",UIParent)
lcLootFrame:RegisterEvent("LOOT_OPENED")
lcLootFrame:RegisterEvent("LOOT_CLOSED")
lcLootFrame:SetScript("OnEvent",function()
    local evt = event
    if evt == "LOOT_OPENED" then
        if not IsPlayerML() then return end
        -- Re-map loot slots for active (unawarded) sessions: closing and reopening the
        -- loot window resets slot indices, so update them by matching item links.
        -- For multi-quantity sessions track remaining slots needed.
        for i = 1, getn(sessionOrder) do
            local s = allSessions[sessionOrder[i]]
            if s and not s.awarded then
                local needed = (s.quantity or 1) - (s.awardCount or 0)
                local found = {}; local fc = 0
                for sl = 1, GetNumLootItems() do
                    local link2 = GetLootSlotLink(sl)
                    if link2 and link2 == s.itemLink then
                        fc = fc + 1; found[fc] = sl
                        if fc >= needed then break end
                    end
                end
                -- Rebuild slots list from found slots
                s.slots = {}; s.slots.n = 0
                for fi = 1, fc do tinsert(s.slots, found[fi]) end
                s.slot = s.slots[1] or s.slot
            end
        end
        if HasUnawardedSession() then return end  -- active vote in progress, wait for End Session
        local prof = GetActiveLRProfile()
        if not prof or (prof.mode ~= "lootcouncil" and prof.mode ~= "dkp") then return end
        local isDKP = (prof.mode == "dkp")
        local myName = UnitName("player")
        -- Collect items, grouping duplicates by itemLink
        local byLink = {}; local linkOrder = {}; local lo = 0
        for slot = 1, GetNumLootItems() do
            local slotTex, itemName, _, quality = GetLootSlotInfo(slot)
            if itemName and itemName ~= "" then
                local itemLink = GetLootSlotLink(slot)
                if itemLink and ShouldTrigger(quality, itemLink, prof) and GetMasterLootCandidate(1) then
                    if not byLink[itemLink] then
                        lo = lo + 1; linkOrder[lo] = itemLink
                        byLink[itemLink] = { slots={}, slots_n=0, quality=quality, tex=slotTex }
                    end
                    local g = byLink[itemLink]
                    g.slots_n = g.slots_n + 1; g.slots[g.slots_n] = slot
                end
            end
        end
        for li = 1, lo do
            local itemLink = linkOrder[li]
            local g        = byLink[itemLink]
            local quantity = g.slots_n
            local sid      = myName.."_"..g.slots[1].."_"..floor(GetTime())
            local iconPath = g.tex or GetItemTexture(itemLink)
            local slotsT   = {}; slotsT.n = quantity
            for qi = 1, quantity do slotsT[qi] = g.slots[qi] end
            local newS = {
                sid          = sid,
                slot         = slotsT[1],
                slots        = slotsT,
                quantity     = quantity,
                awardCount   = 0,
                awardedTo    = {},
                itemLink     = itemLink,
                quality      = g.quality,
                iconPath     = iconPath,
                votes        = {},
                dVotes       = {},
                councilVotes = {},
                buttons      = prof.buttons or {},
                isML         = true,
                isOfficer    = true,
                isDKP        = isDKP,
                timerEnd     = GetTime()+(prof.timer or 60),
                closed       = false,
            }
            AddSession(newS)
            local openMsg = "LC_OPEN^"..sid.."^"..slotsT[1].."^"..(itemLink or "").."^"..g.quality
                            .."^"..iconPath.."^"..EncodeOfficers(prof.officers)
                            .."^"..(isDKP and "1" or "0")
                            .."^"..tostring(prof.timer or 60)
                            .."^"..tostring(quantity)
                            ..EncodeLCButtons(prof.buttons or {})
            SendLC(openMsg)
            OpenVotePopup(newS)
            if not isDKP then
                if not councilFrame or not councilFrame:IsShown() then
                    councilIdx = getn(sessionOrder)
                    OpenCouncilFrame()
                else
                    UpdateCouncilNav()
                end
            end
            -- DKP: council frame opens after timer expires (lcTimerFrame OnUpdate)
        end
    elseif evt == "LOOT_CLOSED" then
        -- nothing — sessions stay open until awarded/closed explicitly
    end
end)

-- ============================================================
-- CHAT_MSG_SYSTEM listener — captures /roll results for vote buttons
-- WoW 1.12 roll format: "Playername rolls X (A-B)."
-- ============================================================
local lcRollFrame = CreateFrame("Frame","ART_LC_RollFrame",UIParent)
lcRollFrame:RegisterEvent("CHAT_MSG_SYSTEM")
lcRollFrame:SetScript("OnEvent",function()
    if event ~= "CHAT_MSG_SYSTEM" then return end
    if not pendingRoll and not pendingDoubleVote then return end
    local msg = arg1
    local _, _, who, val, lo, hi = string.find(msg, "^(.+) rolls (%d+) %((%d+)-(%d+)%)")
    if not who then return end
    local myName = UnitName("player")
    if who ~= myName then return end
    val = tonumber(val); lo = tonumber(lo); hi = tonumber(hi)

    local mySpec = (AmptieRaidTools_PlayerInfo and AmptieRaidTools_PlayerInfo.spec) or ""

    -- Double-vote roll: popup stays open
    if pendingDoubleVote and lo == 1 and hi == pendingDoubleVote.max then
        local pdv = pendingDoubleVote
        local vs  = allSessions[pdv.sid]
        if vs and not vs.closed then
            pendingDoubleVote = nil
            local dkpBid3 = pdv.dkp or 0
            local dvMsg = "LC_DVOTE^"..pdv.sid.."^"..pdv.btnIdx.."^"..pdv.comment.."^"..tostring(val).."^"..mySpec.."^"..tostring(dkpBid3)
            SendLC(dvMsg)
            if myName then
                vs.dVotes[myName] = {btn=pdv.btnIdx, btnName=pdv.btnName, comment=pdv.comment, roll=val, spec=mySpec, dkp=dkpBid3}
            end
        end
        return
    end

    -- Regular vote roll: popup closes after
    if pendingRoll and lo == 1 and hi == pendingRoll.max then
        local pr = pendingRoll
        local vs = allSessions[pr.sid]
        if vs and not vs.closed then
            pendingRoll = nil
            local dkpBid = 0
            local prPopup = popupWindows[pr.sid]
            if prPopup and vs.isDKP and prPopup.dkpBidEB then
                dkpBid = tonumber(prPopup.dkpBidEB:GetText()) or 0
            end
            local voteMsg = "LC_VOTE^"..pr.sid.."^"..pr.btnIdx.."^"..pr.comment.."^"..tostring(val).."^"..mySpec.."^"..tostring(dkpBid)
            SendLC(voteMsg)
            if myName then
                vs.votes[myName] = {btn=pr.btnIdx, btnName=pr.btnName, comment=pr.comment, roll=val, spec=mySpec, dkp=dkpBid}
            end
            local pf = popupWindows[pr.sid]
            if pf then pf:Hide() end
        end
    end
end)

-- ============================================================
-- ADDON_MESSAGE listener
-- ============================================================
local lcMsgFrame = CreateFrame("Frame","ART_LC_MsgFrame",UIParent)
lcMsgFrame:RegisterEvent("CHAT_MSG_ADDON")
lcMsgFrame:SetScript("OnEvent",function()
    if event ~= "CHAT_MSG_ADDON" then return end
    local prefix = arg1
    local msg    = arg2
    local sender = arg4
    if prefix ~= "ART_LC" then return end
    OnLCMessage(sender, msg)
end)

-- ============================================================
-- Zone binding
-- ============================================================
local function ApplyLRZoneBinding()
    local zk = GetCurrentLRZoneKey()   -- never nil (falls back to "outraid")
    local db = GetLRDB()
    local bp = db.lrZoneBindings[zk]
    local target
    if bp and db.lootProfiles[bp] then
        target = bp
    else
        target = "Default"
    end
    if db.activeLRProfile ~= target then
        db.activeLRProfile = target
        if lrPanelRef and lrPanelRef.refreshProfList then
            lrPanelRef.refreshProfList()
        end
        if RebuildRightPanel then RebuildRightPanel() end
    end
end

local lcZoneFrame = CreateFrame("Frame","ART_LC_ZoneFrame",UIParent)
lcZoneFrame:RegisterEvent("PLAYER_LOGIN")
lcZoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
lcZoneFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
-- Roster updates handled by central ART_OnRosterUpdate (staggered)
if ART_OnRosterUpdate then ART_OnRosterUpdate(function() ApplyLRZoneBinding() end, 0.7) end
lcZoneFrame:SetScript("OnEvent",function() ApplyLRZoneBinding() end)

-- ============================================================
-- LEFT PANEL
-- ============================================================
local function CreateLRLeftPanel(panel)
    local LEFT_W = 170
    local PROF_ROW_H = 24

    local profHdr = panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    profHdr:SetPoint("TOPLEFT", panel,"TOPLEFT", 8,-52)
    profHdr:SetText("Profiles")
    profHdr:SetTextColor(0.9, 0.75, 0.2, 1)

    local activeProfLbl = panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    activeProfLbl:SetPoint("TOPLEFT", profHdr,"BOTTOMLEFT", 0,-4)
    activeProfLbl:SetWidth(LEFT_W)
    activeProfLbl:SetJustifyH("LEFT")
    activeProfLbl:SetTextColor(0.5, 0.8, 0.5, 1)

    local profSF = CreateFrame("ScrollFrame",nil,panel)
    profSF:SetPoint("TOPLEFT",    activeProfLbl,"BOTTOMLEFT", 0,-4)
    profSF:SetPoint("BOTTOMLEFT", panel,"TOPLEFT",8,-392)
    profSF:SetWidth(LEFT_W)

    local profContent = CreateFrame("Frame",nil,profSF)
    profContent:SetWidth(LEFT_W)
    profContent:SetHeight(1)
    profSF:SetScrollChild(profContent)

    local profScrollOffset = 0
    local function SetProfScroll(val)
        local maxS = math.max(profContent:GetHeight() - profSF:GetHeight(), 0)
        if val < 0 then val = 0 end
        if val > maxS then val = maxS end
        profScrollOffset = val
        profContent:ClearAllPoints()
        profContent:SetPoint("TOPLEFT", profSF, "TOPLEFT", 0, val)
    end
    profSF:EnableMouseWheel(true)
    profSF:SetScript("OnMouseWheel", function()
        SetProfScroll(profScrollOffset - arg1 * PROF_ROW_H * 2)
    end)

    local profRows = {}

    local function RefreshProfList()
        local db = GetLRDB()
        activeProfLbl:SetText("Active: " .. (db.activeLRProfile or "--"))
        local names = {}; local cnt = 0
        for k in pairs(db.lootProfiles) do cnt=cnt+1; names[cnt]=k end
        table.sort(names)

        -- hide all existing rows
        for i = 1, getn(profRows) do profRows[i]:Hide() end

        profContent:SetHeight(math.max(cnt * PROF_ROW_H, 1))

        for i = 1, cnt do
            local row = profRows[i]
            if not row then
                row = CreateFrame("Button",nil,profContent)
                row:SetHeight(PROF_ROW_H)
                row:SetBackdrop(ROW_BD)
                row:SetBackdropColor(0,0,0,0)
                local lbl = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
                lbl:SetPoint("LEFT",row,"LEFT",6,0)
                lbl:SetPoint("RIGHT",row,"RIGHT",-4,0)
                lbl:SetJustifyH("LEFT")
                row.lbl = lbl
                row:SetScript("OnEnter",function()
                    if this.profName ~= GetLRDB().activeLRProfile then
                        this:SetBackdropColor(0.18,0.18,0.22,0.9)
                    end
                end)
                row:SetScript("OnLeave",function()
                    if this.profName == GetLRDB().activeLRProfile then
                        this:SetBackdropColor(0.18,0.22,0.18,0.9)
                    else
                        this:SetBackdropColor(0,0,0,0)
                    end
                end)
                row:SetScript("OnClick",function()
                    GetLRDB().activeLRProfile = this.profName
                    RefreshProfList()
                    if RebuildRightPanel then RebuildRightPanel() end
                end)
                profRows[i] = row
            end
            row:SetPoint("TOPLEFT", profContent,"TOPLEFT", 0, -(i-1)*PROF_ROW_H)
            row:SetPoint("RIGHT",   profContent,"RIGHT",   0, 0)
            row.profName = names[i]
            row.lbl:SetText(names[i])
            if names[i] == db.activeLRProfile then
                row.lbl:SetTextColor(0.5,1,0.5,1)
                row:SetBackdropColor(0.18,0.22,0.18,0.9)
            else
                row.lbl:SetTextColor(0.85,0.85,0.85,1)
                row:SetBackdropColor(0,0,0,0)
            end
            row:Show()
        end
        SetProfScroll(profScrollOffset)
    end

    -- ── Profile action buttons (Buff Checks layout) ──────────────
    -- y=112: Zone Bindings
    -- y=86:  New | Delete
    -- y=60:  Export | Import
    -- y=34:  Rename
    -- y=8:   Simulate Loot

    local HALF_BTN = 80

    -- New button + floating editbox
    local newBtn = MakeBtn(panel,"New",HALF_BTN,22)
    newBtn:SetPoint("BOTTOMLEFT",panel,"TOPLEFT",8,-444)
    local newProfEdit = CreateFrame("EditBox",nil,UIParent)
    newProfEdit:SetWidth(164); newProfEdit:SetHeight(22)
    newProfEdit:SetFrameStrata("FULLSCREEN_DIALOG")
    newProfEdit:SetPoint("BOTTOM",newBtn,"TOP",42,4)
    newProfEdit:SetAutoFocus(false); newProfEdit:SetMaxLetters(40)
    newProfEdit:SetFontObject(GameFontHighlightSmall)
    newProfEdit:SetTextInsets(4,4,0,0)
    newProfEdit:SetBackdrop(INPUT_BD)
    newProfEdit:SetBackdropColor(0.05,0.05,0.08,0.97)
    newProfEdit:SetBackdropBorderColor(0.35,0.35,0.4,1)
    newProfEdit:SetScript("OnEscapePressed",function() this:ClearFocus(); this:Hide() end)
    newProfEdit:SetScript("OnEnterPressed",function()
        local n = this:GetText()
        local _, _, trimmed = strfind(n,"^%s*(.-)%s*$")
        n = trimmed or n
        if n == "" then this:ClearFocus(); this:Hide(); return end
        local db = GetLRDB()
        if db.lootProfiles[n] then this:ClearFocus(); this:Hide(); return end
        db.lootProfiles[n] = {
            mode="none", triggerMinQuality=4, triggerItemIds={},
            buttons={{name="Main Spec",priority=1},{name="Off Spec",priority=2},{name="Pass",priority=6}},
            timer=60, officers={}, autoLoot={enabled=false,maxQuality=2},
        }
        db.activeLRProfile = n
        this:ClearFocus(); this:Hide()
        RefreshProfList()
        if RebuildRightPanel then RebuildRightPanel() end
    end)
    newProfEdit:Hide()
    newBtn:SetScript("OnClick",function()
        newProfEdit:SetText("")
        newProfEdit:Show(); newProfEdit:SetFocus()
    end)

    -- Delete button
    local delBtn = MakeBtn(panel,"Delete",HALF_BTN,22)
    delBtn:SetPoint("LEFT",newBtn,"RIGHT",4,0)
    delBtn.label:SetTextColor(1,0.4,0.4,1)
    delBtn:SetScript("OnClick",function()
        local db = GetLRDB()
        local active = db.activeLRProfile
        if active == "Default" then return end
        db.lootProfiles[active] = nil
        for k,v in pairs(db.lrZoneBindings) do
            if v == active then db.lrZoneBindings[k] = nil end
        end
        db.activeLRProfile = "Default"
        RefreshProfList()
        if RebuildRightPanel then RebuildRightPanel() end
    end)

    -- Rename button + floating editbox
    local renameBtn = MakeBtn(panel,"Rename",164,22)
    renameBtn:SetPoint("BOTTOMLEFT",panel,"TOPLEFT",8,-496)

    local renameProfEdit = CreateFrame("EditBox",nil,UIParent)
    renameProfEdit:SetWidth(164); renameProfEdit:SetHeight(22)
    renameProfEdit:SetFrameStrata("FULLSCREEN_DIALOG")
    renameProfEdit:SetPoint("BOTTOM",renameBtn,"TOP",0,4)
    renameProfEdit:SetAutoFocus(false); renameProfEdit:SetMaxLetters(40)
    renameProfEdit:SetFontObject(GameFontHighlightSmall)
    renameProfEdit:SetTextInsets(4,4,0,0)
    renameProfEdit:SetBackdrop(INPUT_BD)
    renameProfEdit:SetBackdropColor(0.05,0.05,0.08,0.97)
    renameProfEdit:SetBackdropBorderColor(0.35,0.35,0.4,1)
    renameProfEdit:SetScript("OnEscapePressed",function() this:ClearFocus(); this:Hide() end)
    renameProfEdit:SetScript("OnEnterPressed",function()
        local newName = this:GetText()
        local _, _, trimmed = strfind(newName,"^%s*(.-)%s*$")
        newName = trimmed or newName
        local db = GetLRDB()
        local oldName = db.activeLRProfile
        if newName == "" or newName == oldName then this:ClearFocus(); this:Hide(); return end
        if db.lootProfiles[newName] then this:ClearFocus(); this:Hide(); return end
        db.lootProfiles[newName] = db.lootProfiles[oldName]
        db.lootProfiles[oldName] = nil
        for k,v in pairs(db.lrZoneBindings) do
            if v == oldName then db.lrZoneBindings[k] = newName end
        end
        db.activeLRProfile = newName
        this:ClearFocus(); this:Hide()
        RefreshProfList()
        if RebuildRightPanel then RebuildRightPanel() end
    end)
    renameProfEdit:Hide()
    renameBtn:SetScript("OnClick",function()
        renameProfEdit:SetText(GetLRDB().activeLRProfile or "")
        renameProfEdit:Show(); renameProfEdit:SetFocus(); renameProfEdit:HighlightText()
    end)

    -- Simulate Loot
    local simBtn = MakeBtn(panel,"Simulate Loot",164,22)
    simBtn:SetPoint("BOTTOMLEFT",panel,"TOPLEFT",8,-522)
    simBtn.label:SetTextColor(0.6,0.85,1,1)
    simBtn:SetScript("OnClick",function() SimulateLoot() end)

    -- Export / Import
    local expBtn = MakeBtn(panel,"Export",HALF_BTN,22)
    expBtn:SetPoint("BOTTOMLEFT",panel,"TOPLEFT",8,-470)
    local impBtn = MakeBtn(panel,"Import",HALF_BTN,22)
    impBtn:SetPoint("LEFT",expBtn,"RIGHT",4,0)

    -- Zone Bindings button + modal
    local zoneBtn = MakeBtn(panel,"Zone Bindings",164,22)
    zoneBtn:SetPoint("BOTTOMLEFT",panel,"TOPLEFT",8,-418)
    zoneBtn.label:SetTextColor(0.7,1,0.7,1)

    local zm = CreateFrame("Frame",nil,UIParent)
    zm:SetFrameStrata("FULLSCREEN_DIALOG")
    zm:SetWidth(300)
    zm:SetHeight(40 + getn(ART_LR_ZONES)*26 + 36)
    zm:SetPoint("CENTER",UIParent,"CENTER",0,0)
    zm:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
    zm:SetBackdropColor(0.08,0.08,0.1,0.97)
    zm:SetBackdropBorderColor(0.5,0.5,0.6,1)
    zm:SetMovable(true); zm:EnableMouse(true)
    zm:RegisterForDrag("LeftButton")
    zm:SetScript("OnDragStart",function() this:StartMoving() end)
    zm:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    zm:Hide()

    local zmTit = zm:CreateFontString(nil,"OVERLAY","GameFontNormal")
    zmTit:SetPoint("TOPLEFT",zm,"TOPLEFT",12,-10)
    zmTit:SetText("Zone Bindings – Loot Rules")
    zmTit:SetTextColor(1,0.82,0,1)
    local zmClose = MakeBtn(zm,"Close",60,20)
    zmClose:SetPoint("TOPRIGHT",zm,"TOPRIGHT",-8,-8)
    zmClose:SetScript("OnClick",function() zm:Hide() end)

    local zmRows = {}
    for i = 1, getn(ART_LR_ZONES) do
        local z = ART_LR_ZONES[i]
        local row = CreateFrame("Frame",nil,zm)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", zm,"TOPLEFT",10,-34-(i-1)*26)
        row:SetPoint("TOPRIGHT",zm,"TOPRIGHT",-10,-34-(i-1)*26)
        local zl = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        zl:SetPoint("LEFT",row,"LEFT",0,0)
        zl:SetText(z.label); zl:SetWidth(100); zl:SetJustifyH("LEFT")
        local cb = MakeBtn(row,"none",140,20)
        cb:SetPoint("RIGHT",row,"RIGHT",0,0)
        cb.zoneKey = z.key
        cb:SetScript("OnClick",function()
            local db = GetLRDB()
            local zk2 = this.zoneKey
            local names2 = {}; local nc = 0
            for k2 in pairs(db.lootProfiles) do nc=nc+1; names2[nc]=k2 end
            table.sort(names2)
            local cur = db.lrZoneBindings[zk2] or "none"
            local nxt = "none"
            if cur == "none" then
                nxt = names2[1] or "none"
            else
                local found = false
                for ni = 1, nc do
                    if names2[ni] == cur then
                        nxt = (ni < nc) and names2[ni+1] or "none"
                        found = true; break
                    end
                end
                if not found then nxt = "none" end
            end
            if nxt == "none" then db.lrZoneBindings[zk2] = nil
            else db.lrZoneBindings[zk2] = nxt end
            this.label:SetText(nxt)
        end)
        zmRows[i] = cb
    end

    local function RefreshZoneModal()
        local db = GetLRDB()
        for i = 1, getn(ART_LR_ZONES) do
            local cur = db.lrZoneBindings[ART_LR_ZONES[i].key] or "none"
            zmRows[i].label:SetText(cur)
        end
    end
    zoneBtn:SetScript("OnClick",function() RefreshZoneModal(); zm:Show() end)

    -- ── Share modal (Export / Import) ───────────────────────────
    local shareModal = CreateFrame("Frame",nil,UIParent)
    shareModal:SetAllPoints(UIParent)
    shareModal:SetFrameStrata("FULLSCREEN_DIALOG")
    shareModal:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        tile=true, tileSize=16, edgeSize=0,
        insets={left=0,right=0,top=0,bottom=0},
    })
    shareModal:SetBackdropColor(0,0,0,0.60)
    shareModal:EnableMouse(true)
    shareModal:Hide()

    local smInner = CreateFrame("Frame",nil,shareModal)
    smInner:SetWidth(500)
    smInner:SetHeight(140)
    smInner:SetPoint("CENTER",shareModal,"CENTER",0,0)
    smInner:SetBackdrop(BTN_BD)
    smInner:SetBackdropColor(0.08,0.08,0.12,0.98)
    smInner:SetBackdropBorderColor(0.5,0.42,0.15,1)

    local smTitle = smInner:CreateFontString(nil,"OVERLAY","GameFontNormal")
    smTitle:SetPoint("TOPLEFT",smInner,"TOPLEFT",10,-10)
    smTitle:SetTextColor(1,0.82,0,1)

    local smDesc = smInner:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    smDesc:SetPoint("TOPLEFT",smTitle,"BOTTOMLEFT",0,-4)
    smDesc:SetTextColor(0.65,0.65,0.70,1)

    local smEB = CreateFrame("EditBox",nil,smInner)
    smEB:SetHeight(22)
    smEB:SetPoint("TOPLEFT",smDesc,"BOTTOMLEFT",0,-6)
    smEB:SetPoint("RIGHT",smInner,"RIGHT",-10,0)
    smEB:SetAutoFocus(false)
    smEB:SetMaxLetters(0)
    smEB:SetFontObject(GameFontHighlightSmall)
    smEB:SetTextInsets(4,4,0,0)
    smEB:SetBackdrop(INPUT_BD)
    smEB:SetBackdropColor(0.05,0.05,0.08,0.95)
    smEB:SetBackdropBorderColor(0.35,0.35,0.4,1)
    smEB:SetScript("OnEditFocusGained",function() this:SetBackdropBorderColor(1,0.82,0,0.8) end)
    smEB:SetScript("OnEditFocusLost",  function() this:SetBackdropBorderColor(0.35,0.35,0.4,1) end)
    smEB:SetScript("OnEscapePressed",  function() shareModal:Hide() end)

    local smStatus = smInner:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    smStatus:SetPoint("TOPLEFT",smEB,"BOTTOMLEFT",0,-4)
    smStatus:SetPoint("RIGHT",smInner,"RIGHT",-10,0)
    smStatus:SetJustifyH("LEFT")
    smStatus:SetText("")

    local smCloseBtn = MakeBtn(smInner,"Close",80,22)
    smCloseBtn:SetPoint("BOTTOMRIGHT",smInner,"BOTTOMRIGHT",-10,10)
    smCloseBtn:SetScript("OnClick",function() shareModal:Hide() end)

    local smImportBtn = MakeBtn(smInner,"Import",90,22)
    smImportBtn:SetPoint("RIGHT",smCloseBtn,"LEFT",-6,0)
    smImportBtn:Hide()

    expBtn:SetScript("OnClick",function()
        local prof = GetActiveLRProfile()
        -- Flush current editbox values to profile before serialising
        -- (handles the case where the user hasn't defocused the Roll Max / DV fields yet)
        local lcFRef = lrRightFrame and lrRightFrame.lcF
        if lcFRef and prof and prof.buttons then
            for bi = 1, 6 do
                local bd = prof.buttons[bi]
                if bd then
                    if lcFRef.btnRollEBs and lcFRef.btnRollEBs[bi] then
                        local v = tonumber(lcFRef.btnRollEBs[bi]:GetText())
                        bd.rollMax = (v and v > 0) and floor(v) or 0
                    end
                    if lcFRef.btnDVCBs and lcFRef.btnDVCBs[bi] then
                        bd.isDoubleVote = lcFRef.btnDVCBs[bi]:GetChecked() and true or false
                    end
                end
            end
        end
        smTitle:SetText("Export Profile")
        smDesc:SetText("Text is pre-selected — press Ctrl+C to copy:")
        smStatus:SetText("")
        smImportBtn:Hide()
        local exportStr = LRExportProfile(prof)
        smEB:SetText(exportStr)
        shareModal:Show()
        smEB:SetFocus()
        smEB:HighlightText()
    end)

    impBtn:SetScript("OnClick",function()
        smTitle:SetText("Import Profile")
        smDesc:SetText("Paste a profile string below and click Import:")
        smStatus:SetText("")
        smEB:SetText("")
        smImportBtn:Show()
        shareModal:Show()
        smEB:SetFocus()
    end)

    smImportBtn:SetScript("OnClick",function()
        local str = smEB:GetText()
        local prof, err = LRImportProfile(str)
        if not prof then
            smStatus:SetTextColor(1,0.4,0.4,1)
            smStatus:SetText("Error: "..(err or "unknown"))
            return
        end
        local db = GetLRDB()
        local baseName = "Imported"
        local name = baseName
        local n = 1
        while db.lootProfiles[name] do
            n = n + 1
            name = baseName .. " " .. n
        end
        db.lootProfiles[name] = prof
        db.activeLRProfile    = name
        shareModal:Hide()
        RefreshProfList()
        if RebuildRightPanel then RebuildRightPanel() end
    end)

    panel.refreshProfList = RefreshProfList
    ART_LR_OnProfilesImported = function()
        GetLRDB()
        RefreshProfList()
        RebuildRightPanel()
    end
    return RefreshProfList
end

-- ============================================================
-- RIGHT PANEL (static sub-frames, load values on switch)
-- ============================================================
local function CreateLRRightPanel(panel)
    local RX   = 186
    local rf   = CreateFrame("Frame",nil,panel)
    rf:SetPoint("TOPLEFT",    panel,"TOPLEFT",    RX,-52)
    rf:SetPoint("BOTTOMRIGHT",panel,"TOPRIGHT",-8,-522)
    lrRightFrame = rf

    -- Profile name + divider + mode buttons — always visible
    local nameFS = rf:CreateFontString(nil,"OVERLAY","GameFontNormal")
    nameFS:SetPoint("TOPLEFT",rf,"TOPLEFT",0,0)
    nameFS:SetTextColor(1,0.82,0,1)
    rf.nameFS = nameFS

    MakeDivider(rf, rf, -20)

    local modeLbl = rf:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    modeLbl:SetPoint("TOPLEFT",rf,"TOPLEFT",0,-28)
    modeLbl:SetText("Mode:"); modeLbl:SetTextColor(0.65,0.65,0.7,1)

    local MODE_IDS  = {"none","lootcouncil","dkp"}
    local MODE_LBLS = {"None","Loot Council","DKP"}
    local modeBtns  = {}
    for mi = 1, 3 do
        local mb = MakeBtn(rf, MODE_LBLS[mi], 100, 22)
        mb:SetPoint("TOPLEFT",rf,"TOPLEFT",(mi-1)*106,-46)
        mb.modeId = MODE_IDS[mi]
        mb:SetScript("OnClick",function()
            local p = GetActiveLRProfile()
            if p then p.mode = this.modeId end
            RebuildRightPanel()
        end)
        modeBtns[mi] = mb
    end
    rf.modeBtns = modeBtns

    -- Scrollable settings area (below mode buttons)
    local settingsSF = CreateFrame("ScrollFrame","ART_LR_SettingsSF",rf)
    settingsSF:SetPoint("TOPLEFT",    rf,"TOPLEFT",     0,-76)
    settingsSF:SetPoint("BOTTOMRIGHT",rf,"BOTTOMRIGHT", -2,  0)
    settingsSF:EnableMouseWheel(true)

    local settingsChild = CreateFrame("Frame",nil,settingsSF)
    settingsChild:SetWidth(560)
    settingsChild:SetHeight(40)   -- updated in RebuildRightPanel
    settingsSF:SetScrollChild(settingsChild)

    settingsSF:SetScript("OnMouseWheel",function()
        local step = 30
        local maxScroll = math.max(0, settingsChild:GetHeight() - settingsSF:GetHeight())
        local newVal = settingsSF:GetVerticalScroll() + (arg1 > 0 and -step or step)
        settingsSF:SetVerticalScroll(math.max(0, math.min(maxScroll, newVal)))
    end)
    rf.settingsSF    = settingsSF
    rf.settingsChild = settingsChild

    -- ---- "none" sub-frame ----
    local noneF = CreateFrame("Frame",nil,settingsChild)
    noneF:SetPoint("TOPLEFT",settingsChild,"TOPLEFT",0,0)
    noneF:SetWidth(560); noneF:SetHeight(40)
    local noneFS = noneF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    noneFS:SetPoint("TOPLEFT",noneF,"TOPLEFT",0,0)
    noneFS:SetText("No loot rules active. Looting proceeds normally.")
    noneFS:SetTextColor(0.6,0.6,0.65,1)
    rf.noneF = noneF

    -- ---- "dkp" sub-frame ----
    local dkpF = CreateFrame("Frame",nil,settingsChild)
    dkpF:SetPoint("TOPLEFT",settingsChild,"TOPLEFT",0,0)
    dkpF:SetWidth(560); dkpF:SetHeight(40)
    local dkpFS = dkpF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    dkpFS:SetPoint("TOPLEFT",dkpF,"TOPLEFT",0,0)
    dkpFS:SetText("DKP integration coming soon.")
    dkpFS:SetTextColor(0.6,0.6,0.65,1)
    rf.dkpF = dkpF

    -- ---- "lootcouncil" sub-frame ----
    local lcF = CreateFrame("Frame",nil,settingsChild)
    lcF:SetPoint("TOPLEFT",settingsChild,"TOPLEFT",0,0)
    lcF:SetWidth(560)
    lcF:SetHeight(568)   -- grows dynamically via offEB OnTextChanged
    rf.lcF = lcF

    -- We need the right panel width for some elements
    -- Approx 600 - 186 - 8 - 12 = 394. Use relative anchors.

    local QUALITY_NAMES = {"Poor","Common","Uncommon","Rare","Epic","Legendary"}
    local QUALITY_COLORS = {
        "|cFF9D9D9D", "|cFFFFFFFF", "|cFF1EFF00",
        "|cFF0070DD", "|cFFA335EE", "|cFFFF8000",
    }

    -- Trigger
    SectionHdr(lcF,"Trigger",lcF,0)

    -- Row 1: quality checkbox + dropdown
    local trigQualCB = CreateFrame("CheckButton",nil,lcF,"UICheckButtonTemplate")
    trigQualCB:SetWidth(20); trigQualCB:SetHeight(20)
    trigQualCB:SetPoint("TOPLEFT",lcF,"TOPLEFT",0,-19)
    trigQualCB:SetScript("OnClick",function()
        local p = GetActiveLRProfile()
        if p then p.triggerByQuality = this:GetChecked() and true or false end
    end)
    local trigQualLbl = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    trigQualLbl:SetPoint("LEFT",trigQualCB,"RIGHT",2,0)
    trigQualLbl:SetText("Auto-trigger by min. quality:"); trigQualLbl:SetTextColor(0.65,0.65,0.7,1)

    local trigQBtn = MakeBtn(lcF,"Epic",72,18)
    trigQBtn:SetPoint("LEFT",trigQualLbl,"RIGHT",4,0)
    trigQBtn._qualIdx = 5  -- default Epic (index 5 = quality 4)
    trigQBtn:SetScript("OnClick",function()
        local p = GetActiveLRProfile()
        if not p then return end
        this._qualIdx = mmod(this._qualIdx, 6) + 1
        local qval = this._qualIdx - 1
        p.triggerMinQuality = qval
        this.label:SetText(QUALITY_COLORS[this._qualIdx]..QUALITY_NAMES[this._qualIdx].."|r")
    end)

    -- Row 2: item IDs (always active, triggers regardless of quality toggle)
    local trigILbl = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    trigILbl:SetPoint("TOPLEFT",lcF,"TOPLEFT",0,-44)
    trigILbl:SetText("Always trigger for item IDs (comma-sep):")
    trigILbl:SetTextColor(0.65,0.65,0.7,1)
    local trigIEB = MakeEB(lcF,300,18)
    trigIEB:SetPoint("TOPLEFT",lcF,"TOPLEFT",0,-62)

    local function SaveTrigI()
        local p = GetActiveLRProfile()
        if p then
            p.triggerItemIds = {}
            for piece in string.gfind(trigIEB:GetText()..",","([^,]+),") do
                local n = tonumber(piece)
                if n then p.triggerItemIds[n] = true end
            end
        end
    end
    trigIEB:SetScript("OnEnterPressed",function() SaveTrigI(); this:ClearFocus() end)
    trigIEB:SetScript("OnEditFocusLost",function() SaveTrigI() end)

    MakeDivider(lcF,lcF,-84)

    -- Vote Buttons
    SectionHdr(lcF,"Vote Buttons (up to 6)",lcF,-92)
    local colNameLbl = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    colNameLbl:SetPoint("TOPLEFT",lcF,"TOPLEFT",0,-110)
    colNameLbl:SetText("Name"); colNameLbl:SetTextColor(0.5,0.5,0.55,1)
    local colPrioLbl = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    colPrioLbl:SetPoint("TOPLEFT",lcF,"TOPLEFT",116,-110)
    colPrioLbl:SetText("Prio"); colPrioLbl:SetTextColor(0.5,0.5,0.55,1)
    local colRollLbl = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    colRollLbl:SetPoint("TOPLEFT",lcF,"TOPLEFT",162,-110)
    colRollLbl:SetText("Roll Max"); colRollLbl:SetTextColor(0.5,0.5,0.55,1)
    local colDVLbl = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    colDVLbl:SetPoint("TOPLEFT",lcF,"TOPLEFT",220,-110)
    colDVLbl:SetText("DV"); colDVLbl:SetTextColor(0.5,0.7,1,1)

    local btnNameEBs = {}; local btnPrioEBs = {}; local btnRollEBs = {}; local btnDVCBs = {}
    for bi = 1, 6 do
        local y = -128-(bi-1)*22
        local neb = MakeEB(lcF,108,18)
        neb:SetPoint("TOPLEFT",lcF,"TOPLEFT",0,y)
        neb.btnIdx = bi
        neb:SetScript("OnEnterPressed",function()
            local p = GetActiveLRProfile()
            if p and p.buttons and p.buttons[this.btnIdx] then
                p.buttons[this.btnIdx].name = this:GetText()
            end; this:ClearFocus()
        end)
        neb:SetScript("OnEditFocusLost",function()
            local p = GetActiveLRProfile()
            if p and p.buttons and p.buttons[this.btnIdx] then
                p.buttons[this.btnIdx].name = this:GetText()
            end
        end)
        local peb = MakeEB(lcF,38,18)
        peb:SetPoint("TOPLEFT",lcF,"TOPLEFT",116,y)
        peb.btnIdx = bi
        peb:SetScript("OnEnterPressed",function()
            local p = GetActiveLRProfile()
            if p and p.buttons and p.buttons[this.btnIdx] then
                local v = tonumber(this:GetText())
                if v then p.buttons[this.btnIdx].priority = floor(v) end
            end; this:ClearFocus()
        end)
        peb:SetScript("OnEditFocusLost",function()
            local p = GetActiveLRProfile()
            if p and p.buttons and p.buttons[this.btnIdx] then
                local v = tonumber(this:GetText())
                if v then p.buttons[this.btnIdx].priority = floor(v) end
            end
        end)
        -- Roll Max: 0 or blank = no roll; 1-1000 = RandomRoll(1, rollMax) on click
        local reb = MakeEB(lcF,50,18)
        reb:SetPoint("TOPLEFT",lcF,"TOPLEFT",162,y)
        reb.btnIdx = bi
        local function SaveRoll()
            local p = GetActiveLRProfile()
            if p and p.buttons and p.buttons[this.btnIdx] then
                local v = tonumber(this:GetText())
                p.buttons[this.btnIdx].rollMax = (v and v > 0) and floor(v) or 0
            end
        end
        reb:SetScript("OnEnterPressed",function() SaveRoll(); this:ClearFocus() end)
        reb:SetScript("OnEditFocusLost",SaveRoll)
        local dvcb = CreateFrame("CheckButton", nil, lcF, "UICheckButtonTemplate")
        dvcb:SetWidth(20); dvcb:SetHeight(20)
        dvcb:SetPoint("TOPLEFT",lcF,"TOPLEFT",220,y+1)
        dvcb.btnIdx = bi
        dvcb:SetScript("OnClick",function()
            local p = GetActiveLRProfile()
            if p and p.buttons and p.buttons[this.btnIdx] then
                p.buttons[this.btnIdx].isDoubleVote = this:GetChecked() and true or false
            end
        end)
        btnNameEBs[bi] = neb; btnPrioEBs[bi] = peb; btnRollEBs[bi] = reb; btnDVCBs[bi] = dvcb
    end

    MakeDivider(lcF,lcF,-264)

    -- Timer
    SectionHdr(lcF,"Voting Timer",lcF,-272)
    local timerLbl = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    timerLbl:SetPoint("TOPLEFT",lcF,"TOPLEFT",0,-290)
    timerLbl:SetText("Seconds:"); timerLbl:SetTextColor(0.65,0.65,0.7,1)
    local timerEB = MakeEB(lcF,50,18)
    timerEB:SetPoint("LEFT",timerLbl,"RIGHT",6,0)
    local function SaveTimer()
        local p = GetActiveLRProfile()
        if p then
            local v = tonumber(timerEB:GetText())
            if v then p.timer = math.max(10,math.min(600,floor(v))) end
        end
    end
    timerEB:SetScript("OnEnterPressed",function() SaveTimer(); this:ClearFocus() end)
    timerEB:SetScript("OnEditFocusLost",function() SaveTimer() end)

    MakeDivider(lcF,lcF,-314)

    -- Officer Frame Display
    SectionHdr(lcF,"Officer Frame",lcF,-322)

    local ofLbl = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    ofLbl:SetPoint("TOPLEFT",lcF,"TOPLEFT",0,-340)
    ofLbl:SetText("Show columns:"); ofLbl:SetTextColor(0.65,0.65,0.7,1)

    local colDefs = {
        {key="prio",      label="Priority"},
        {key="class",     label="Class"},
        {key="spec",      label="Spec"},
        {key="guildRank", label="G.Rank"},
    }
    local colCBs = {}
    for ci = 1, 4 do
        local cd = colDefs[ci]
        local cb = CreateFrame("CheckButton",nil,lcF,"UICheckButtonTemplate")
        cb:SetWidth(20); cb:SetHeight(20)
        cb:SetPoint("TOPLEFT",lcF,"TOPLEFT",(ci-1)*80,-356)
        cb.colKey = cd.key
        cb:SetScript("OnClick",function()
            local p = GetActiveLRProfile()
            if not p then return end
            EnsureCouncilSettings(p)
            p.councilCols[this.colKey] = this:GetChecked() and true or false
        end)
        local lfs = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        lfs:SetPoint("LEFT",cb,"RIGHT",1,0)
        lfs:SetText(cd.label); lfs:SetTextColor(0.7,0.7,0.75,1)
        colCBs[ci] = cb
    end

    -- Sort order
    local sortLbl = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    sortLbl:SetPoint("TOPLEFT",lcF,"TOPLEFT",0,-382)
    sortLbl:SetText("Sort order:"); sortLbl:SetTextColor(0.65,0.65,0.7,1)

    local function MakeCycleBtn(xOff, yOff, getVal, setVal)
        local cb2 = MakeBtn(lcF,"...",82,18)
        cb2:SetPoint("TOPLEFT",lcF,"TOPLEFT",xOff,yOff)
        cb2:SetScript("OnClick",function()
            local p = GetActiveLRProfile()
            if not p then return end
            EnsureCouncilSettings(p)
            local cur = getVal(p)
            local idx = 1
            for i = 1, getn(SORT_OPTS) do
                if SORT_OPTS[i] == cur then idx = i; break end
            end
            idx = mmod(idx, getn(SORT_OPTS)) + 1
            setVal(p, SORT_OPTS[idx])
            this.label:SetText(SORT_LABELS[SORT_OPTS[idx]] or SORT_OPTS[idx])
        end)
        return cb2
    end

    local primLbl = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    primLbl:SetPoint("TOPLEFT",lcF,"TOPLEFT",0,-400)
    primLbl:SetText("1st:"); primLbl:SetTextColor(0.65,0.65,0.7,1)
    local primBtn = MakeCycleBtn(24,-400,
        function(p) return p.councilSort.primary end,
        function(p,v) p.councilSort.primary = v end)
    primBtn.label:SetText("Priority")

    local secLbl = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    secLbl:SetPoint("TOPLEFT",lcF,"TOPLEFT",116,-400)
    secLbl:SetText("2nd:"); secLbl:SetTextColor(0.65,0.65,0.7,1)
    local secBtn = MakeCycleBtn(140,-400,
        function(p) return p.councilSort.secondary end,
        function(p,v) p.councilSort.secondary = v end)
    secBtn.label:SetText("Roll")

    local tercLbl = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    tercLbl:SetPoint("TOPLEFT",lcF,"TOPLEFT",232,-400)
    tercLbl:SetText("3rd:"); tercLbl:SetTextColor(0.65,0.65,0.7,1)
    local tercBtn = MakeCycleBtn(256,-400,
        function(p) return p.councilSort.tertiary or "name" end,
        function(p,v) p.councilSort.tertiary = v end)
    tercBtn.label:SetText("Name")

    -- Store Officer Frame refs
    lcF.colCBs  = colCBs
    lcF.primBtn = primBtn
    lcF.secBtn  = secBtn
    lcF.tercBtn = tercBtn

    MakeDivider(lcF,lcF,-424)

    -- Auto-Loot
    SectionHdr(lcF,"Auto-Loot (non-council items)",lcF,-432)
    local alCB = ART_CreateCheckbox(lcF,"Auto-loot items below quality threshold")
    alCB:SetPoint("TOPLEFT",lcF,"TOPLEFT",0,-450)
    alCB.userOnClick = function()
        local p = GetActiveLRProfile()
        if p then
            if not p.autoLoot then p.autoLoot = {} end
            p.autoLoot.enabled = alCB:GetChecked()
        end
    end

    local alQLbl = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    alQLbl:SetPoint("TOPLEFT",lcF,"TOPLEFT",0,-474)
    alQLbl:SetText("Max Quality to auto-loot:"); alQLbl:SetTextColor(0.65,0.65,0.7,1)
    -- Cycle button — same pattern as Trigger quality button
    local alQBtn = MakeBtn(lcF,"",110,20)
    alQBtn:SetPoint("LEFT",alQLbl,"RIGHT",6,0)
    alQBtn._qualIdx = 3   -- default: index 3 = Uncommon (quality 2)
    alQBtn:SetScript("OnClick",function()
        this._qualIdx = math.mod(this._qualIdx, 6) + 1
        local qval = this._qualIdx - 1
        local p = GetActiveLRProfile()
        if p then
            if not p.autoLoot then p.autoLoot = {} end
            p.autoLoot.maxQuality = qval
        end
        this.label:SetText(QUALITY_COLORS[this._qualIdx]..QUALITY_NAMES[this._qualIdx].."|r")
    end)
    alQBtn.label:SetText(QUALITY_COLORS[3]..QUALITY_NAMES[3].."|r")

    MakeDivider(lcF,lcF,-498)

    -- Council / Officers — free-growing EditBox at bottom; settingsSF handles scrolling
    SectionHdr(lcF,"Council / Officers",lcF,-506)
    local offLbl = lcF:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    offLbl:SetPoint("TOPLEFT",lcF,"TOPLEFT",0,-524)
    offLbl:SetText("One name per line:"); offLbl:SetTextColor(0.65,0.65,0.7,1)

    local offSaveBtn = MakeBtn(lcF,"Save Officers",110,20)
    offSaveBtn:SetPoint("TOPLEFT",lcF,"TOPLEFT",188,-524)

    -- LC_OFF_BASE_H: lcF height when offEB has minimal (1-line) content
    local LC_OFF_BASE_H = 548
    local offEB = CreateFrame("EditBox",nil,lcF)
    offEB:SetPoint("TOPLEFT",lcF,"TOPLEFT",0,-544)
    offEB:SetWidth(300)
    offEB:SetHeight(20)
    offEB:SetMultiLine(true)
    offEB:SetMaxLetters(0)
    offEB:SetFontObject("GameFontHighlightSmall")
    offEB:SetTextInsets(4,4,2,2)
    offEB:SetAutoFocus(false)
    offEB:SetBackdrop(INPUT_BD)
    offEB:SetBackdropColor(0.04,0.04,0.06,0.9)
    offEB:SetBackdropBorderColor(0.3,0.3,0.35,1)
    offEB:SetScript("OnEscapePressed",function() this:ClearFocus() end)
    offEB:SetScript("OnTextChanged",function()
        local text = offEB:GetText()
        local lines = 1
        for _ in string.gfind(text,"\n") do lines = lines+1 end
        local h = math.max(20, lines*14+4)
        offEB:SetHeight(h)
        local totalH = LC_OFF_BASE_H + h
        lcF:SetHeight(totalH)
        settingsChild:SetHeight(totalH)
        local sfH = settingsSF:GetHeight()
        -- settingsSF handles scroll range automatically via GetVerticalScroll
    end)

    offSaveBtn:SetScript("OnClick",function()
        local p = GetActiveLRProfile()
        if not p then return end
        local txt = offEB:GetText()
        p.officers = {}; local oc = 0
        for line in string.gfind(txt.."\n","([^\n]*)\n") do
            local _, _, trimmed = strfind(line,"^%s*(.-)%s*$")
            local n = trimmed or line
            if n ~= "" then oc=oc+1; p.officers[oc]=n end
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[ART-LC]|r Saved "..oc.." officers.")
    end)

    -- Store refs for LoadLCProfile
    lcF.trigQualCB  = trigQualCB
    lcF.trigQBtn    = trigQBtn
    lcF.trigIEB     = trigIEB
    lcF.colRollLbl  = colRollLbl
    lcF.btnNameEBs  = btnNameEBs
    lcF.btnPrioEBs  = btnPrioEBs
    lcF.btnRollEBs  = btnRollEBs
    lcF.btnDVCBs    = btnDVCBs
    lcF.timerEB   = timerEB
    lcF.offEB     = offEB
    lcF.alCB      = alCB
    lcF.alQBtn    = alQBtn

    local function LoadLCProfile(prof)
        if not prof then return end
        -- ensure 6 button slots
        if not prof.buttons then prof.buttons = {} end
        while getn(prof.buttons) < 6 do
            tinsert(prof.buttons, {name="", priority=getn(prof.buttons)+1})
        end

        local qidx = (prof.triggerMinQuality or 4) + 1
        lcF.trigQualCB:SetChecked(prof.triggerByQuality ~= false)
        lcF.trigQBtn._qualIdx = qidx
        lcF.trigQBtn.label:SetText(QUALITY_COLORS[qidx]..QUALITY_NAMES[qidx].."|r")

        local idParts = {}; local ic = 0
        if prof.triggerItemIds then
            for id in pairs(prof.triggerItemIds) do ic=ic+1; idParts[ic]=tostring(id) end
        end
        local idStr = ""
        for i = 1, ic do
            if i > 1 then idStr = idStr.."," end
            idStr = idStr..idParts[i]
        end
        lcF.trigIEB:SetText(idStr)

        local isDKPMode = (prof.mode == "dkp")
        if lcF.colRollLbl then
            if isDKPMode then lcF.colRollLbl:Hide() else lcF.colRollLbl:Show() end
        end
        for bi = 1, 6 do
            local bd = prof.buttons[bi] or {name="",priority=bi}
            -- Migrate old "dv" field to "isDoubleVote" (one-time fix for old SavedVariables)
            if bd.dv ~= nil and bd.isDoubleVote == nil then
                bd.isDoubleVote = bd.dv
            end
            lcF.btnNameEBs[bi]:SetText(bd.name or "")
            lcF.btnPrioEBs[bi]:SetText(tostring(bd.priority or bi))
            lcF.btnRollEBs[bi]:SetText((bd.rollMax and bd.rollMax > 0) and tostring(bd.rollMax) or "")
            if isDKPMode then lcF.btnRollEBs[bi]:Hide() else lcF.btnRollEBs[bi]:Show() end
            lcF.btnDVCBs[bi]:SetChecked((bd.isDoubleVote or bd.dv) and 1 or nil)
        end

        lcF.timerEB:SetText(tostring(prof.timer or 60))

        local offStr = ""
        if prof.officers then
            for oi = 1, getn(prof.officers) do
                if oi > 1 then offStr = offStr.."\n" end
                offStr = offStr..prof.officers[oi]
            end
        end
        lcF.offEB:SetText(offStr)

        local al = prof.autoLoot or {}
        lcF.alCB:SetChecked(al.enabled)
        local alqidx = (al.maxQuality or 2) + 1
        lcF.alQBtn._qualIdx = alqidx
        lcF.alQBtn.label:SetText(QUALITY_COLORS[alqidx]..QUALITY_NAMES[alqidx].."|r")

        EnsureCouncilSettings(prof)
        local cols2 = prof.councilCols
        if lcF.colCBs then
            local colKeys = {"prio","class","spec","guildRank"}
            for ci = 1, 4 do
                lcF.colCBs[ci]:SetChecked(cols2[colKeys[ci]] and true or false)
            end
        end
        local csort = prof.councilSort
        if lcF.primBtn then lcF.primBtn.label:SetText(SORT_LABELS[csort.primary]   or csort.primary)   end
        if lcF.secBtn  then lcF.secBtn.label:SetText( SORT_LABELS[csort.secondary] or csort.secondary) end
        if lcF.tercBtn then lcF.tercBtn.label:SetText(SORT_LABELS[csort.tertiary or "name"] or (csort.tertiary or "name")) end
    end
    lcF.LoadLCProfile = LoadLCProfile

    -- ---- RebuildRightPanel ----
    RebuildRightPanel = function()
        local db   = GetLRDB()
        local prof = GetActiveLRProfile()
        if not prof then return end

        rf.nameFS:SetText(db.activeLRProfile)

        for mi = 1, 3 do
            local mb = modeBtns[mi]
            if mb.modeId == prof.mode then
                mb:SetBackdropColor(0.22,0.18,0.04,0.95)
                mb:SetBackdropBorderColor(1,0.82,0,1)
                mb.label:SetTextColor(1,0.82,0,1)
            else
                mb:SetBackdropColor(0.1,0.1,0.14,0.95)
                mb:SetBackdropBorderColor(0.35,0.35,0.42,1)
                mb.label:SetTextColor(0.85,0.85,0.85,1)
            end
        end

        noneF:Hide(); dkpF:Hide(); lcF:Hide()
        local contentH = 40
        if prof.mode == "none" then
            noneF:Show()
        elseif prof.mode == "dkp" or prof.mode == "lootcouncil" then
            lcF:Show()
            lcF.LoadLCProfile(prof)  -- triggers offEB OnTextChanged → lcF height updated
            contentH = lcF:GetHeight()
        end

        -- Update scroll child height and slider range
        settingsChild:SetHeight(contentH)
        local sfH = settingsSF:GetHeight()
        settingsSF:SetVerticalScroll(0)
    end

    return rf
end

-- ============================================================
-- INIT
-- ============================================================
function AmptieRaidTools_InitLootRules(body)
    local panel = CreateFrame("Frame","ART_LootRulesPanel",body)
    panel:SetAllPoints(body)
    panel.noOuterScroll = true
    AmptieRaidTools_RegisterComponent("lootrules", panel)
    lrPanelRef = panel

    -- title block
    local title = panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOPLEFT",panel,"TOPLEFT",12,-10)
    title:SetText("Loot Rules")
    title:SetTextColor(1,0.82,0,1)
    local sub = panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-3)
    sub:SetText("Profile-based loot council management. Requires Master Looter.")
    sub:SetTextColor(0.65,0.65,0.7,1)
    local hdiv = panel:CreateTexture(nil,"ARTWORK")
    hdiv:SetHeight(1)
    hdiv:SetPoint("TOPLEFT", sub,"BOTTOMLEFT",0,-6)
    hdiv:SetPoint("TOPRIGHT",panel,"TOPRIGHT",-12,0)
    hdiv:SetTexture(0.25,0.25,0.28,0.8)

    -- vertical divider between left and right
    local vdiv = panel:CreateTexture(nil,"ARTWORK")
    vdiv:SetWidth(1)
    vdiv:SetPoint("TOPLEFT",   panel,"TOPLEFT",   184,-52)
    vdiv:SetPoint("BOTTOMLEFT",panel,"TOPLEFT",184,-522)
    vdiv:SetTexture(0.25,0.25,0.28,0.8)

    GetLRDB()
    CreateLRLeftPanel(panel)
    CreateLRRightPanel(panel)

    panel.refreshProfList()
    RebuildRightPanel()

    -- Defer first RebuildRightPanel to the next frame after OnShow so that
    -- settingsSF:GetHeight() returns the real resolved value (not 0).
    panel:SetScript("OnShow", function()
        panel:SetScript("OnShow", nil)  -- run once only
        panel:SetScript("OnUpdate", function()
            panel:SetScript("OnUpdate", nil)
            RebuildRightPanel()
        end)
    end)
end

-- Global entry point for the slash command handler in main.lua
function AmptieRaidTools_CouncilShow()
    if getn(sessionOrder) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFAA00[ART-LC]|r No active loot session.")
        return
    end
    if not councilFrame or not councilFrame:IsShown() then
        councilIdx = math.max(1, getn(sessionOrder))
        OpenCouncilFrame()
    else
        councilFrame:Show()
    end
end
