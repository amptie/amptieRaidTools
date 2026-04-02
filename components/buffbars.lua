-- components/buffbars.lua
-- Player Buff Bars (Buff, Debuff, Weapon) + Consolidated Buffs
-- Lua 5.0 / WoW 1.12 / TurtleWoW (SuperWoW)

local getn    = table.getn
local tinsert = table.insert
local floor   = math.floor
local mceil   = math.ceil
local mmax    = math.max
local mmin    = math.min
local GetTime = GetTime
local sfmt    = string.format
local UnitBuff   = UnitBuff
local UnitDebuff = UnitDebuff

local BB_HAS_SUPERWOW = (SpellInfo ~= nil)

-- ============================================================
-- Constants
-- ============================================================
local BB_TIMER_H     = 12
local BB_PAD         = 2
local BB_UPDATE_INT  = 0.25
local BB_MAX_BUFFS   = 32
local BB_MAX_DEBUFFS = 16
local BB_MAX_WEAPONS = 2
local BB_ICON_DEFAULT = 30

local BB_DEBUFF_COL = {
    Magic   = { r=0.20, g=0.60, b=1.00 },
    Poison  = { r=0.00, g=0.60, b=0.00 },
    Curse   = { r=0.60, g=0.00, b=1.00 },
    Disease = { r=0.60, g=0.40, b=0.00 },
}
local BB_DEBUFF_COL_NONE = { r=0.80, g=0.00, b=0.00 }

local BB_DEFAULT_CONSOLIDATED = {
    "Power Word: Fortitude",   "Prayer of Fortitude",
    "Shadow Protection",       "Prayer of Shadow Protection",
    "Divine Spirit",           "Prayer of Spirit",
    "Arcane Intellect",        "Arcane Brilliance",
    "Mark of the Wild",        "Gift of the Wild",
    "Blessing of Salvation",   "Greater Blessing of Salvation",
    "Blessing of Wisdom",      "Greater Blessing of Wisdom",
    "Blessing of Might",       "Greater Blessing of Might",
    "Blessing of Kings",       "Greater Blessing of Kings",
    "Blessing of Light",       "Greater Blessing of Light",
    "Trueshot Aura",
}

-- ============================================================
-- DB
-- ============================================================
local function GetBBDB()
    if not amptieRaidToolsDB then return nil end
    if not amptieRaidToolsDB.buffBars then amptieRaidToolsDB.buffBars = {} end
    local db = amptieRaidToolsDB.buffBars
    -- Version migration: resets saved positions when the anchor math changed.
    -- Bump bbBarsVersion whenever OnDragStop math or anchor reference changes.
    -- v3: OnDragStop formula corrected (GetRight()-UIParent:GetRight() instead of -GetWidth())
    if db.bbBarsVersion ~= 3 then
        db.bbBarsVersion  = 3
        db.buffBarX       = 0;   db.buffBarY   = -160
        db.debuffBarX     = 0;   db.debuffBarY = -200
        db.weaponBarX     = 0;   db.weaponBarY = -240
    end
    -- Consolidated
    if db.consolidatedEnabled == nil then db.consolidatedEnabled = false end
    if db.consolidatedLocked  == nil then db.consolidatedLocked  = true  end
    if db.consolidatedPoint   == nil then db.consolidatedPoint   = "CENTER" end
    if db.consolidatedX       == nil then db.consolidatedX       = 0     end
    if db.consolidatedY       == nil then db.consolidatedY       = 220   end
    if not db.consolidatedList then
        db.consolidatedList = {}
        for i = 1, getn(BB_DEFAULT_CONSOLIDATED) do
            db.consolidatedList[i] = BB_DEFAULT_CONSOLIDATED[i]
        end
    end
    -- Buff bar
    if db.buffBarEnabled        == nil then db.buffBarEnabled        = false end
    if db.buffBarLocked         == nil then db.buffBarLocked         = true  end
    if db.buffBarNumPerRow      == nil then db.buffBarNumPerRow      = 16    end
    if db.buffBarX              == nil then db.buffBarX              = 0     end
    if db.buffBarY              == nil then db.buffBarY              = -160  end
    if db.buffIconSz            == nil then db.buffIconSz            = BB_ICON_DEFAULT end
    if db.hideConsolidatedInBar == nil then db.hideConsolidatedInBar = true  end
    -- Debuff bar
    if db.debuffBarEnabled    == nil then db.debuffBarEnabled    = false end
    if db.debuffBarLocked     == nil then db.debuffBarLocked     = true  end
    if db.debuffBarNumPerRow  == nil then db.debuffBarNumPerRow  = 8     end
    if db.debuffBarX          == nil then db.debuffBarX          = 0     end
    if db.debuffBarY          == nil then db.debuffBarY          = -200  end
    if db.debuffIconSz        == nil then db.debuffIconSz        = BB_ICON_DEFAULT end
    -- Weapon bar
    if db.weaponBarEnabled == nil then db.weaponBarEnabled = false end
    if db.weaponBarLocked  == nil then db.weaponBarLocked  = true  end
    if db.weaponBarX       == nil then db.weaponBarX       = 0     end
    if db.weaponBarY       == nil then db.weaponBarY       = -240  end
    if db.weaponIconSz     == nil then db.weaponIconSz     = BB_ICON_DEFAULT end
    -- Persistent Blizzard buff frame suppression (independent of aRT bars)
    if db.hideBlizzBuffFrame == nil then db.hideBlizzBuffFrame = false end
    return db
end

-- ============================================================
-- Hidden tooltip for buff name resolution (non-SuperWoW)
-- ============================================================
local bbScanTip     = CreateFrame("GameTooltip", "ART_BB_ScanTip", UIParent, "GameTooltipTemplate")
local bbScanTipText = nil

local function BBGetPlayerBuffName(slot0)
    -- buffIndex is the actual internal slot number; slot0 is the ordinal position
    -- among HELPFUL buffs. SetPlayerBuff and all Buff APIs require buffIndex.
    local buffIndex = GetPlayerBuff(slot0, "HELPFUL")
    if buffIndex < 0 then return nil end
    if not bbScanTipText then
        bbScanTipText = getglobal("ART_BB_ScanTipTextLeft1")
    end
    bbScanTip:SetOwner(UIParent, "ANCHOR_NONE")
    bbScanTip:SetPlayerBuff(buffIndex)
    return bbScanTipText and bbScanTipText:GetText() or nil
end

-- ============================================================
-- Timer formatting
-- ============================================================
local function BBFmtTime(sec)
    if sec <= 0    then return "" end
    if sec >= 3600 then return floor(sec / 3600) .. "h" end
    if sec >= 60   then return floor(sec / 60)   .. "m" end
    if sec >= 10   then return floor(sec)         .. "s" end
    return sfmt("%.1f", sec)
end

-- ============================================================
-- Shared backdrop
-- ============================================================
local BB_BD = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile=true, tileSize=16, edgeSize=10,
    insets = { left=3, right=3, top=3, bottom=3 },
}

-- ============================================================
-- Utility: small button
-- ============================================================
local function BBMakeBtn(parent, label, w, h)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(w or 60)
    btn:SetHeight(h or 18)
    btn:SetBackdrop(BB_BD)
    btn:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    btn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetAllPoints(btn)
    fs:SetJustifyH("CENTER")
    fs:SetText(label or "")
    btn._fs = fs
    btn.SetText = function(b, t) b._fs:SetText(t) end
    btn:SetScript("OnEnter", function() this:SetBackdropBorderColor(1, 0.82, 0, 0.8) end)
    btn:SetScript("OnLeave", function() this:SetBackdropBorderColor(0.35, 0.35, 0.4, 1) end)
    return btn
end

-- ============================================================
-- Utility: icon button
-- ============================================================
local function BBMakeIconBtn(parent, slot0)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(BB_ICON_DEFAULT)
    btn:SetHeight(BB_ICON_DEFAULT + BB_TIMER_H)
    btn:RegisterForClicks("RightButtonUp")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT",     btn, "TOPLEFT",     0, 0)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, BB_TIMER_H)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(icon)
    border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
    border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    border:Hide()
    btn.border = border

    local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, 2)
    count:Hide()
    btn.count = count

    local timer = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timer:SetPoint("TOP", btn, "BOTTOM", 0, BB_TIMER_H)
    timer:SetJustifyH("CENTER")
    timer:SetTextColor(1, 1, 1, 1)
    btn.timer = timer

    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
        if this.buffIndex and this.buffIndex >= 0 then
            GameTooltip:SetPlayerBuff(this.buffIndex)
        elseif this.isWeapon and this.label then
            GameTooltip:SetText(this.label, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn.buffIndex = -1
    btn.slot0 = slot0
    return btn
end

-- Resize icon button to new pixel size (reanchors sub-elements)
local function BBResizeIconBtn(btn, sz)
    btn:SetWidth(sz)
    btn:SetHeight(sz + BB_TIMER_H)
    btn.icon:ClearAllPoints()
    btn.icon:SetPoint("TOPLEFT",     btn, "TOPLEFT",     0, 0)
    btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, BB_TIMER_H)
    btn.border:ClearAllPoints()
    btn.border:SetAllPoints(btn.icon)
end

-- ============================================================
-- Utility: layout buttons left-to-right, wrapping at numPerRow
-- displayCount: total slots to render (real buffs + preview placeholders).
--   nil / omitted  = same as visible (no preview)
--   > visible      = extra slots shown as dimmed question-mark placeholders
--   0              = collapse parent to 1x1 (no backdrop visible, used when
--                    locked and nothing to show)
-- ============================================================
-- rtl=true: buttons fill right-to-left (button 1 = rightmost); frame TOPRIGHT
-- is the stable edge — used when consolidated anchors to the buff bar's right.
local function BBLayout(buttons, numPerRow, visible, iconSz, displayCount, rtl)
    numPerRow    = numPerRow or 16
    iconSz       = iconSz   or BB_ICON_DEFAULT
    if displayCount == nil then displayCount = visible end
    local stepH  = iconSz + BB_PAD
    local stepV  = iconSz + BB_TIMER_H + BB_PAD
    local n      = getn(buttons)
    local parent = buttons[1]:GetParent()
    local dispCols = displayCount > 0 and mmin(displayCount, numPerRow) or 0
    for i = 1, n do
        local btn = buttons[i]
        BBResizeIconBtn(btn, iconSz)
        if i <= displayCount then
            local rowIdx = floor((i - 1) / numPerRow)
            local posIdx = math.mod(i - 1, numPerRow)  -- 0 = first placed
            local x, y
            btn:ClearAllPoints()
            if rtl then
                -- Anchor each icon to the frame's TOPRIGHT corner.
                -- posIdx 0 = rightmost icon, always at frame.TOPRIGHT - BB_PAD.
                -- Frame grows leftward; icon 1 screen position never shifts.
                x = -(posIdx * stepH + BB_PAD)
                y = -(rowIdx * stepV + BB_PAD)
                btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x, y)
            else
                x = posIdx * stepH + BB_PAD
                y = -(rowIdx * stepV + BB_PAD)
                btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
            end
            if i <= visible then
                btn.icon:SetAlpha(1)
                btn:EnableMouse(true)
            else
                btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                btn.icon:SetAlpha(0.2)
                btn.timer:SetText("")
                btn.border:Hide()
                btn.count:Hide()
                btn:EnableMouse(false)
            end
            btn:Show()
        else
            btn:Hide()
        end
    end
    if displayCount == 0 then
        parent:SetWidth(1); parent:SetHeight(1)
        parent:SetAlpha(0)  -- suppress backdrop cross artifact on empty 1x1 frame
        return 0, 0
    end
    parent:SetAlpha(1)
    local dispRows = mceil(displayCount / numPerRow)
    local fw = dispCols * stepH + BB_PAD * 2
    local fh = dispRows * (iconSz + BB_PAD) + BB_PAD * 2
    parent:SetWidth(fw)
    parent:SetHeight(fh)
    return fw, fh
end

-- ============================================================
-- ── Consolidated hover popup (shown on mouse-over of Con icon)
-- ============================================================
local bbConHoverFrame = nil
local bbConHoverBtns  = {}

-- Delayed-hide guard: keeps the hover popup alive while mouse moves between
-- bbConFrame and bbConHoverFrame / its child buttons.
local bbConHideDelay   = 0
local BB_CON_HIDE_WAIT = 0.15
local bbConHoverGuard  = CreateFrame("Frame", nil, UIParent)
bbConHoverGuard:Hide()
bbConHoverGuard:SetScript("OnUpdate", function()
    local dt = arg1; if not dt then dt = 0 end
    bbConHideDelay = bbConHideDelay - dt
    if bbConHideDelay <= 0 then
        bbConHoverGuard:Hide()
        if bbConHoverFrame then bbConHoverFrame:Hide() end
    end
end)
local function BBConCancelHide() bbConHoverGuard:Hide() end
local function BBConStartHide()
    bbConHideDelay = BB_CON_HIDE_WAIT
    bbConHoverGuard:Show()
end

local function BBBuildConHoverFrame()
    bbConHoverFrame = CreateFrame("Frame", "ART_BB_ConHoverFrame", UIParent)
    bbConHoverFrame:SetFrameStrata("HIGH")
    bbConHoverFrame:EnableMouse(true)
    bbConHoverFrame:SetScript("OnEnter", function() BBConCancelHide() end)
    bbConHoverFrame:SetScript("OnLeave", function() BBConStartHide()  end)
    bbConHoverFrame:Hide()

    -- "none active" label shown when no buffs
    local noLbl = bbConHoverFrame:CreateFontString(
        "ART_BB_ConHoverNoLbl", "OVERLAY", "GameFontHighlightSmall")
    noLbl:SetAllPoints(bbConHoverFrame)
    noLbl:SetJustifyH("CENTER")
    noLbl:SetTextColor(0.55, 0.55, 0.55, 1)
    noLbl:SetText("none active")
    noLbl:Hide()
    bbConHoverFrame.noLbl = noLbl

    for i = 1, BB_MAX_BUFFS do
        local btn = BBMakeIconBtn(bbConHoverFrame, i - 1)
        btn:SetScript("OnEnter", function()
            BBConCancelHide()
            GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
            if this.buffIndex and this.buffIndex >= 0 then
                GameTooltip:SetPlayerBuff(this.buffIndex)
            elseif this.isWeapon and this.label then
                GameTooltip:SetText(this.label, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            BBConStartHide()
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function()
            if this.buffIndex and this.buffIndex >= 0 then
                CancelPlayerBuff(this.buffIndex)
            end
        end)
        bbConHoverBtns[i] = btn
    end
end

local function BBUpdateConHover()
    if not bbConHoverFrame then return end
    local db = GetBBDB()
    if not db then return end

    local conSet = {}
    local list   = db.consolidatedList
    for i = 1, getn(list) do conSet[list[i]] = true end

    -- Pre-scan: collect all helpful buff data in one pass, resolving names via the
    -- scan tooltip before any filtering. This avoids calling SetPlayerBuff inside the
    -- active-buff collection loop, which can disturb aura query ordering in WoW 1.12.
    local helpful = {}
    for slot = 0, BB_MAX_BUFFS - 1 do
        local buffIndex, untilCancelled = GetPlayerBuff(slot, "HELPFUL")
        if buffIndex < 0 then break end
        tinsert(helpful, {
            buffIndex      = buffIndex,
            untilCancelled = untilCancelled,
            tex            = GetPlayerBuffTexture(buffIndex),
            apps           = GetPlayerBuffApplications(buffIndex),
            timeLeft       = GetPlayerBuffTimeLeft(buffIndex),
            name           = BBGetPlayerBuffName(slot),
        })
    end

    -- Filter to consolidated list
    local active = {}
    for i = 1, getn(helpful) do
        local h = helpful[i]
        if h.name and conSet[h.name] then
            tinsert(active, h)
        end
    end

    local visible = getn(active)
    local iconSz  = db.buffIconSz or BB_ICON_DEFAULT

    if visible == 0 then
        for i = 1, getn(bbConHoverBtns) do bbConHoverBtns[i]:Hide() end
        local stepH = iconSz + BB_PAD
        bbConHoverFrame:SetWidth(stepH * 5 + BB_PAD * 2)
        bbConHoverFrame:SetHeight(iconSz + BB_TIMER_H + BB_PAD * 2)
        bbConHoverFrame.noLbl:Show()
        return
    end

    bbConHoverFrame.noLbl:Hide()
    local numPerRow = db.buffBarNumPerRow or 16
    for i = 1, getn(bbConHoverBtns) do
        local btn = bbConHoverBtns[i]
        if i <= visible then
            local a = active[i]
            btn.buffIndex      = a.buffIndex
            btn.untilCancelled = a.untilCancelled
            btn.icon:SetTexture(a.tex)
            btn.border:Hide()
            if a.apps and a.apps > 1 then
                btn.count:SetText(a.apps); btn.count:Show()
            else
                btn.count:Hide()
            end
            local tl = a.timeLeft
            btn.timer:SetText((tl and tl > 0) and BBFmtTime(tl) or "")
            btn.timer:SetTextColor(1, (tl and tl < 60) and 1 or 1, (tl and tl < 60) and 0 or 1, 1)
        else
            btn:Hide()
        end
    end
    BBLayout(bbConHoverBtns, 5, visible, iconSz, nil, true)
end

-- ============================================================
-- ── Consolidated Buffs main icon
-- ============================================================
local bbConFrame    = nil
local bbConExpFrame = nil
local bbConExpBtns  = {}
local bbConExpShown = false

local function BBScanConsolidated()
    local db = GetBBDB()
    if not db then return 0, 0, {} end
    local list  = db.consolidatedList
    local total = getn(list)
    local playerNames = {}
    for slot = 0, BB_MAX_BUFFS - 1 do
        local buffIndex = GetPlayerBuff(slot, "HELPFUL")
        if buffIndex < 0 then break end
        local name = BBGetPlayerBuffName(slot)
        if name then playerNames[name] = true end
    end
    local count, active = 0, {}
    for i = 1, total do
        if playerNames[list[i]] then
            count = count + 1
            tinsert(active, list[i])
        end
    end
    return count, total, active
end

local function BBUpdateConsolidated()
    if not bbConFrame or not bbConFrame:IsShown() then return end
    local count, total = BBScanConsolidated()
    bbConFrame.countText:SetText(tostring(count))

    if bbConHoverFrame and bbConHoverFrame:IsShown() then
        BBUpdateConHover()
    end

    if not bbConExpShown or not bbConExpFrame then return end
    local db2  = GetBBDB()
    local list = db2 and db2.consolidatedList or {}
    local tot2 = getn(list)
    local playerNames = {}
    for slot = 0, BB_MAX_BUFFS - 1 do
        local buffIndex = GetPlayerBuff(slot, "HELPFUL")
        if buffIndex < 0 then break end
        local name = BBGetPlayerBuffName(slot)
        if name then playerNames[name] = true end
    end
    local numBtns = getn(bbConExpBtns)
    for i = 1, numBtns do
        local row = bbConExpBtns[i]
        if i <= tot2 then
            row.label:SetText(list[i])
            row.dot:SetTextColor(playerNames[list[i]] and 0.3 or 0.6,
                                 playerNames[list[i]] and 1.0 or 0.0,
                                 0.0, 1)
            row:Show()
        else
            row:Hide()
        end
    end
    bbConExpFrame:SetHeight(mmax(1, tot2) * 18 + 10)
end

local function BBCreateConsolidatedExpFrame()
    bbConExpFrame = CreateFrame("Frame", "ART_BB_ConExpFrame", bbConFrame)
    bbConExpFrame:SetFrameStrata("HIGH")
    bbConExpFrame:SetWidth(190)
    bbConExpFrame:SetHeight(200)
    bbConExpFrame:SetPoint("TOPLEFT", bbConFrame, "TOPRIGHT", 4, 0)
    bbConExpFrame:SetBackdrop(BB_BD)
    bbConExpFrame:SetBackdropColor(0, 0, 0, 0.88)
    bbConExpFrame:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
    bbConExpFrame:Hide()
    for i = 1, 32 do
        local row = CreateFrame("Frame", nil, bbConExpFrame)
        row:SetHeight(18)
        row:SetPoint("TOPLEFT",  bbConExpFrame, "TOPLEFT",  6, -(i - 1) * 18 - 5)
        row:SetPoint("TOPRIGHT", bbConExpFrame, "TOPRIGHT", -6, 0)
        row:Hide()
        local dot = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dot:SetPoint("LEFT", row, "LEFT", 0, 0)
        dot:SetWidth(12)
        dot:SetText("●")
        row.dot = dot
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", dot, "RIGHT", 4, 0)
        lbl:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetTextColor(0.9, 0.9, 0.9, 1)
        row.label = lbl
        bbConExpBtns[i] = row
    end
end

-- Reattach consolidated icon to right edge of buff bar (or float standalone)
-- Forward-declared; defined after bbBuffFrame is in scope at call time
local BBUpdateConAnchor

local function BBCreateConsolidatedFrame()
    local db = GetBBDB()
    local iconSz = (db and db.buffIconSz) or BB_ICON_DEFAULT
    bbConFrame = CreateFrame("Frame", "ART_BB_ConFrame", UIParent)
    bbConFrame:SetFrameStrata("MEDIUM")
    bbConFrame:SetWidth(iconSz + BB_PAD * 2)
    bbConFrame:SetHeight(iconSz + BB_PAD * 2)
    bbConFrame:SetMovable(true)
    bbConFrame:SetClampedToScreen(true)
    bbConFrame:EnableMouse(true)
    local conPt = (db and db.consolidatedPoint) or "CENTER"
    bbConFrame:SetPoint(conPt, UIParent, conPt,
        db and db.consolidatedX or 0, db and db.consolidatedY or 220)
    bbConFrame:RegisterForDrag("LeftButton")
    bbConFrame:SetScript("OnDragStart", function()
        local d = GetBBDB()
        if d and not d.buffBarLocked then this:StartMoving() end
    end)
    bbConFrame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local d = GetBBDB()
        if d then
            local p, _, _, x, y = this:GetPoint()
            d.consolidatedPoint = p
            d.consolidatedX = x
            d.consolidatedY = y
        end
    end)
    bbConFrame:SetBackdrop(BB_BD)
    bbConFrame:SetBackdropColor(0, 0, 0, 0.75)
    bbConFrame:SetBackdropBorderColor(1, 0.82, 0, 0.8)
    bbConFrame:Hide()

    local icon = bbConFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT",     bbConFrame, "TOPLEFT",     BB_PAD, -BB_PAD)
    icon:SetPoint("BOTTOMRIGHT", bbConFrame, "BOTTOMRIGHT", -BB_PAD, BB_PAD)
    icon:SetTexture("Interface\\Icons\\inv_misc_enggizmos_21")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    bbConFrame.mainIcon = icon

    local ct = bbConFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    ct:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, 2)
    ct:SetTextColor(1, 1, 1, 1)
    ct:SetText("0")
    bbConFrame.countText = ct

    -- Invisible Button overlay covering the full icon area.
    -- Buttons have more reliable full-area mouse detection in WoW 1.12 than Frames.
    -- Drag is handled on hitBtn (not the parent Frame) because a child Button with
    -- EnableMouse absorbs mouse-down before the parent Frame's RegisterForDrag fires.
    local hitBtn = CreateFrame("Button", nil, bbConFrame)
    hitBtn:SetAllPoints(bbConFrame)
    hitBtn:SetFrameLevel(bbConFrame:GetFrameLevel() + 2)
    hitBtn:RegisterForClicks("LeftButtonUp")
    hitBtn:RegisterForDrag("LeftButton")
    hitBtn:SetScript("OnDragStart", function()
        local d = GetBBDB()
        if d and not d.buffBarLocked then
            bbConFrame:StartMoving()
        end
    end)
    hitBtn:SetScript("OnDragStop", function()
        bbConFrame:StopMovingOrSizing()
        local d = GetBBDB()
        if d then
            local p, _, _, x, y = bbConFrame:GetPoint()
            d.consolidatedPoint = p
            d.consolidatedX = x
            d.consolidatedY = y
        end
        -- Re-anchor buff bar to follow
        BBUpdateConAnchor()
    end)

    hitBtn:SetScript("OnClick", function()
        if not bbConExpFrame then BBCreateConsolidatedExpFrame() end
        bbConExpShown = not bbConExpShown
        if bbConExpShown then
            bbConExpFrame:Show()
            BBUpdateConsolidated()
        else
            bbConExpFrame:Hide()
        end
    end)
    hitBtn:SetScript("OnEnter", function()
        if not bbConHoverFrame then BBBuildConHoverFrame() end
        BBConCancelHide()
        bbConHoverFrame:ClearAllPoints()
        bbConHoverFrame:SetPoint("TOPRIGHT", bbConFrame, "BOTTOMRIGHT", 0, -4)
        BBUpdateConHover()
        bbConHoverFrame:Show()
    end)
    hitBtn:SetScript("OnLeave", function()
        BBConStartHide()
    end)
end

-- ============================================================
-- ── Buff Bar
-- ============================================================
local bbBuffFrame = nil
local bbBuffBtns  = {}

BBUpdateConAnchor = function()
    if not bbConFrame then return end
    local db = GetBBDB()
    -- Consolidated is always the master anchor at its saved position
    bbConFrame:ClearAllPoints()
    local conPt = (db and db.consolidatedPoint) or "CENTER"
    bbConFrame:SetPoint(conPt, UIParent, conPt,
        db and db.consolidatedX or 0, db and db.consolidatedY or 220)
    -- Buff bar (when active) anchors TOPRIGHT to consolidated's TOPLEFT,
    -- so buffs build left from the consolidated button
    if bbBuffFrame and bbBuffFrame:IsShown() and db and db.buffBarEnabled then
        bbBuffFrame:ClearAllPoints()
        bbBuffFrame:SetPoint("TOPRIGHT", bbConFrame, "TOPLEFT", -BB_PAD, 0)
    end
end

local function BBCreateBuffBar()
    local db = GetBBDB()
    -- Container: NO backdrop on the main frame. A child frame provides the backdrop
    -- and is sized only to cover visible slots. The container itself is NEVER resized
    -- based on content — this keeps the TOPRIGHT anchor stable in WoW 1.12.
    bbBuffFrame = CreateFrame("Frame", "ART_BB_BuffFrame", UIParent)
    bbBuffFrame:SetFrameStrata("MEDIUM")
    bbBuffFrame:SetMovable(true)
    bbBuffFrame:SetClampedToScreen(true)
    bbBuffFrame:EnableMouse(false)  -- enabled only when content is visible
    bbBuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", db and db.buffBarX or 0, db and db.buffBarY or -160)
    bbBuffFrame:RegisterForDrag("LeftButton")
    bbBuffFrame:SetScript("OnDragStart", function()
        local d = GetBBDB()
        if d and not d.buffBarLocked then
            -- When consolidated is active, dragging the buff bar moves the consolidated frame
            if d.consolidatedEnabled and bbConFrame and bbConFrame:IsShown() then
                bbConFrame:StartMoving()
            else
                this:StartMoving()
            end
        end
    end)
    bbBuffFrame:SetScript("OnDragStop", function()
        local d = GetBBDB()
        if d and d.consolidatedEnabled and bbConFrame and bbConFrame:IsShown() then
            bbConFrame:StopMovingOrSizing()
            local p, _, _, x, y = bbConFrame:GetPoint()
            if d then d.consolidatedPoint = p; d.consolidatedX = x; d.consolidatedY = y end
            BBUpdateConAnchor()
        else
            this:StopMovingOrSizing()
            if d then
                d.buffBarX = this:GetRight() - UIParent:GetRight()
                d.buffBarY = this:GetTop()   - UIParent:GetTop()
            end
        end
    end)
    -- No backdrop on the buff bar — icons float without a background box.
    -- Initialize with a valid non-zero size
    local initSz = (db and db.buffIconSz) or BB_ICON_DEFAULT
    local initPR = (db and db.buffBarNumPerRow) or 16
    bbBuffFrame:SetWidth(mmin(BB_MAX_BUFFS, initPR) * (initSz + BB_PAD) + BB_PAD * 2)
    bbBuffFrame:SetHeight(initSz + BB_TIMER_H + BB_PAD * 2 + BB_PAD)
    bbBuffFrame:Hide()
    for i = 1, BB_MAX_BUFFS do
        local btn = BBMakeIconBtn(bbBuffFrame, i - 1)
        btn:SetScript("OnClick", function()
            if this.buffIndex >= 0 then CancelPlayerBuff(this.buffIndex) end
        end)
        bbBuffBtns[i] = btn
    end
end

local function BBUpdateBuffBar()
    if not bbBuffFrame or not bbBuffFrame:IsShown() then return end
    local db      = GetBBDB()
    -- hideCon only applies when consolidated is actually enabled
    local hideCon = db and db.consolidatedEnabled and db.hideConsolidatedInBar
    local conSet  = {}
    if hideCon and db and db.consolidatedList then
        for i = 1, getn(db.consolidatedList) do conSet[db.consolidatedList[i]] = true end
    end
    local iconSz     = (db and db.buffIconSz)       or BB_ICON_DEFAULT
    local perRow     = (db and db.buffBarNumPerRow)  or 16
    local buffLocked = db and db.buffBarLocked
    local visible    = 0
    for slot = 0, BB_MAX_BUFFS - 1 do
        local buffIndex, untilCancelled = GetPlayerBuff(slot, "HELPFUL")
        if buffIndex < 0 then break end
        local skip = false
        if hideCon then
            local bname = BBGetPlayerBuffName(slot)
            if bname and conSet[bname] then skip = true end
        end
        if not skip then
            visible = visible + 1
            local btn = bbBuffBtns[visible]
            btn.buffIndex      = buffIndex
            btn.untilCancelled = untilCancelled
            btn.icon:SetTexture(GetPlayerBuffTexture(buffIndex))
            btn.border:Hide()
            local apps = GetPlayerBuffApplications(buffIndex)
            if apps and apps > 1 then btn.count:SetText(apps); btn.count:Show()
            else btn.count:Hide() end
            local tl = GetPlayerBuffTimeLeft(buffIndex)
            btn.timer:SetText((tl and tl > 0) and BBFmtTime(tl) or "")
            btn.timer:SetTextColor(1, (tl and tl < 60) and 1 or 1, (tl and tl < 60) and 0 or 1, 1)
        end
    end
    -- Resize consolidated to match icon size
    if bbConFrame then
        bbConFrame:SetWidth(iconSz + BB_PAD * 2)
        bbConFrame:SetHeight(iconSz + BB_PAD * 2)
    end
    -- ALWAYS call BBLayout with BB_MAX_BUFFS so the container frame never shrinks.
    -- This prevents TOPRIGHT anchor drift in WoW 1.12.
    BBLayout(bbBuffBtns, perRow, visible, iconSz, BB_MAX_BUFFS, true)
    -- In locked mode: hide preview slots — only real buffs are shown.
    if buffLocked then
        for i = visible + 1, BB_MAX_BUFFS do bbBuffBtns[i]:Hide() end
    end
    if buffLocked and visible == 0 then
        bbBuffFrame:SetAlpha(0)
        bbBuffFrame:EnableMouse(false)
        return
    end
    bbBuffFrame:SetAlpha(1)
    bbBuffFrame:EnableMouse(true)
end

local function BBRefreshBuffTimers()
    if not bbBuffFrame or not bbBuffFrame:IsShown() then return end
    for i = 1, BB_MAX_BUFFS do
        local btn = bbBuffBtns[i]
        if not btn:IsShown() then break end
        if btn.buffIndex >= 0 and not btn.untilCancelled then
            local tl = GetPlayerBuffTimeLeft(btn.buffIndex)
            if tl and tl > 0 then
                btn.timer:SetText(BBFmtTime(tl))
                btn.timer:SetTextColor(1, tl < 60 and 1 or 1, tl < 60 and 0 or 1, 1)
            else
                btn.timer:SetText("")
            end
        end
    end
    -- Also refresh hover popup timers
    if bbConHoverFrame and bbConHoverFrame:IsShown() then
        for i = 1, getn(bbConHoverBtns) do
            local btn = bbConHoverBtns[i]
            if not btn:IsShown() then break end
            if btn.buffIndex >= 0 and not btn.untilCancelled then
                local tl = GetPlayerBuffTimeLeft(btn.buffIndex)
                if tl and tl > 0 then
                    btn.timer:SetText(BBFmtTime(tl))
                    btn.timer:SetTextColor(1, tl < 60 and 1 or 1, tl < 60 and 0 or 1, 1)
                else
                    btn.timer:SetText("")
                end
            end
        end
    end
end

-- ============================================================
-- ── Debuff Bar
-- ============================================================
local bbDebuffFrame = nil
local bbDebuffBtns  = {}

local function BBCreateDebuffBar()
    local db = GetBBDB()
    -- Container: NO backdrop on the main frame. A child frame provides the backdrop
    -- and is sized only to cover visible slots. The container itself is NEVER resized
    -- based on content — its size is set by BBLayout with BB_MAX_DEBUFFS and only
    -- changes when settings (iconSz / perRow) change. This keeps the TOPRIGHT anchor
    -- stable: WoW 1.12 drifts the TOPRIGHT when a frame shrinks (TOPLEFT-based
    -- internally). With a fixed container size, no shrink ever happens from content.
    bbDebuffFrame = CreateFrame("Frame", "ART_BB_DebuffFrame", UIParent)
    bbDebuffFrame:SetFrameStrata("MEDIUM")
    bbDebuffFrame:SetMovable(true)
    bbDebuffFrame:SetClampedToScreen(true)
    bbDebuffFrame:EnableMouse(false)  -- enabled only when content is visible (avoids
                                      -- blocking buff bar mouse events when invisible)
    bbDebuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", db and db.debuffBarX or 0, db and db.debuffBarY or -200)
    bbDebuffFrame:RegisterForDrag("LeftButton")
    bbDebuffFrame:SetScript("OnDragStart", function()
        local d = GetBBDB()
        if d and not d.debuffBarLocked then this:StartMoving() end
    end)
    bbDebuffFrame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local d = GetBBDB()
        if d then
            -- Correct formula for TOPRIGHT→UIParent-TOPRIGHT anchor:
            -- x = GetRight() - UIParent:GetRight()  (= GetRight() - GetWidth()/2)
            d.debuffBarX = this:GetRight() - UIParent:GetRight()
            d.debuffBarY = this:GetTop()   - UIParent:GetTop()
        end
    end)
    bbDebuffFrame:Hide()
    for i = 1, BB_MAX_DEBUFFS do
        bbDebuffBtns[i] = BBMakeIconBtn(bbDebuffFrame, i - 1)
    end
end

local function BBUpdateDebuffBar()
    if not bbDebuffFrame or not bbDebuffFrame:IsShown() then return end
    local db     = GetBBDB()
    local iconSz = (db and db.debuffIconSz) or BB_ICON_DEFAULT
    local perRow = (db and db.debuffBarNumPerRow) or 8
    local locked = db and db.debuffBarLocked

    -- Pre-scan UnitDebuff for debuff type (needed for border colour).
    -- UnitDebuff and GetPlayerBuff(N,"HARMFUL") can return debuffs in different
    -- orders, so we decouple them: type is looked up by texture path after the fact.
    local typeByTex = {}
    for s = 1, BB_MAX_DEBUFFS do
        local tex, _, dtype = UnitDebuff("player", s)
        if not tex then break end
        if dtype and not typeByTex[tex] then typeByTex[tex] = dtype end
    end

    -- Main loop: drive by GetPlayerBuff so buffIndex always matches what is
    -- passed to GameTooltip:SetPlayerBuff and GetPlayerBuffTimeLeft.
    local visible = 0
    for i = 0, BB_MAX_DEBUFFS - 1 do
        local buffIndex = GetPlayerBuff(i, "HARMFUL")
        if buffIndex < 0 then break end
        local tex      = GetPlayerBuffTexture(buffIndex)
        local timeLeft = GetPlayerBuffTimeLeft(buffIndex)
        local apps     = GetPlayerBuffApplications(buffIndex)
        visible = visible + 1
        local btn = bbDebuffBtns[visible]
        btn.buffIndex = buffIndex
        btn.icon:SetTexture(tex)
        local dtype = tex and typeByTex[tex]
        local col   = (dtype and BB_DEBUFF_COL[dtype]) or BB_DEBUFF_COL_NONE
        btn.border:SetVertexColor(col.r, col.g, col.b, 1)
        btn.border:Show()
        if apps and apps > 1 then btn.count:SetText(apps); btn.count:Show()
        else btn.count:Hide() end
        if timeLeft and timeLeft > 0 then
            btn.timer:SetText(BBFmtTime(timeLeft))
            if timeLeft < 60 then
                btn.timer:SetTextColor(1, 1, 0, 1)
            else
                btn.timer:SetTextColor(1, 1, 1, 1)
            end
        else
            btn.timer:SetText("")
        end
    end

    -- ALWAYS call BBLayout with BB_MAX_DEBUFFS so the container frame is always the
    -- same width for given settings. This prevents TOPRIGHT anchor drift: WoW 1.12
    -- keeps the LEFT edge fixed on SetWidth(), so shrinking the frame shifts the right
    -- edge left. By never shrinking (always full-slot width), the anchor stays stable.
    BBLayout(bbDebuffBtns, perRow, visible, iconSz, BB_MAX_DEBUFFS, true)
    -- In locked mode: hide preview slots — only real debuffs are shown.
    if locked then
        for i = visible + 1, BB_MAX_DEBUFFS do bbDebuffBtns[i]:Hide() end
    end

    if locked and visible == 0 then
        bbDebuffFrame:SetAlpha(0)
        bbDebuffFrame:EnableMouse(false)
        return
    end
    bbDebuffFrame:SetAlpha(1)
    bbDebuffFrame:EnableMouse(true)
end

-- ============================================================
-- ── Weapon Buff Bar
-- ============================================================
local bbWeaponFrame = nil
local bbWeaponBtns  = {}

local function BBCreateWeaponBar()
    local db = GetBBDB()
    bbWeaponFrame = CreateFrame("Frame", "ART_BB_WeaponFrame", UIParent)
    bbWeaponFrame:SetFrameStrata("MEDIUM")
    bbWeaponFrame:SetMovable(true)
    bbWeaponFrame:SetClampedToScreen(true)
    bbWeaponFrame:EnableMouse(true)
    -- Frame has no visible backdrop; a child frame provides the sized backdrop
    bbWeaponFrame:SetBackdrop(nil)
    bbWeaponFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", db and db.weaponBarX or 0, db and db.weaponBarY or -240)
    bbWeaponFrame:RegisterForDrag("LeftButton")
    bbWeaponFrame:SetScript("OnDragStart", function()
        local d = GetBBDB()
        if d and not d.weaponBarLocked then this:StartMoving() end
    end)
    bbWeaponFrame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local d = GetBBDB()
        if d then
            d.weaponBarX = this:GetRight() - UIParent:GetRight()
            d.weaponBarY = this:GetTop()   - UIParent:GetTop()
        end
    end)
    -- Backdrop child: created before buttons so it renders behind them
    local wBD = CreateFrame("Frame", nil, bbWeaponFrame)
    wBD:SetBackdrop(BB_BD)
    wBD:SetBackdropColor(0, 0, 0, 0.7)
    wBD:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.8)
    wBD:Hide()
    bbWeaponFrame.backdropChild = wBD
    -- Initialize with a valid non-zero size (same reason as debuff bar).
    local initSz = (db and db.weaponIconSz) or BB_ICON_DEFAULT
    bbWeaponFrame:SetWidth(BB_MAX_WEAPONS * (initSz + BB_PAD) + BB_PAD * 2)
    bbWeaponFrame:SetHeight(initSz + BB_TIMER_H + BB_PAD * 2 + BB_PAD)
    bbWeaponFrame:Hide()
    for i = 1, BB_MAX_WEAPONS do
        local btn = BBMakeIconBtn(bbWeaponFrame, i - 1)
        btn.isWeapon   = true
        btn.hasEnchant = false
        bbWeaponBtns[i] = btn
        -- Use Blizzard's enchant tooltip: shows weapon item + enchant duration
        btn:SetScript("OnEnter", function()
            if not this.hasEnchant then return end
            BuffFrame_EnchantButton_OnEnter()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
end

local function BBUpdateWeaponBar()
    if not bbWeaponFrame or not bbWeaponFrame:IsShown() then return end
    local db     = GetBBDB()
    local locked = db and db.weaponBarLocked
    local iconSz = (db and db.weaponIconSz) or BB_ICON_DEFAULT
    local hasMH, mhExp, _, hasOH, ohExp = GetWeaponEnchantInfo()
    local visible = 0

    -- Fill active enchant slots from rightmost inward; store invSlot for tooltip.
    local function fillActive(btn, invSlot, expMs)
        btn.hasEnchant = true
        btn:SetID(invSlot)
        btn.icon:SetTexture(GetInventoryItemTexture("player", invSlot)
            or "Interface\\Icons\\INV_Misc_QuestionMark")
        btn.border:Hide()
        btn.count:Hide()
        local sec = (expMs or 0) / 1000
        if sec > 0 then
            btn.timer:SetText(BBFmtTime(sec))
            btn.timer:SetTextColor(1, sec < 60 and 1 or 1, sec < 60 and 0 or 1, 1)
        else
            btn.timer:SetText("")
        end
    end

    if hasMH then visible = visible + 1; fillActive(bbWeaponBtns[visible], 16, mhExp) end
    if hasOH  then visible = visible + 1; fillActive(bbWeaponBtns[visible], 17, ohExp) end

    -- Clear hasEnchant on preview slots
    for i = visible + 1, BB_MAX_WEAPONS do
        bbWeaponBtns[i].hasEnchant = false
    end

    -- Locked + no enchants: hide buttons and backdrop but keep the frame at its
    -- last valid size so the TOPRIGHT anchor does not drift when enchants return.
    if locked and visible == 0 then
        for i = 1, BB_MAX_WEAPONS do bbWeaponBtns[i]:Hide() end
        if bbWeaponFrame.backdropChild then bbWeaponFrame.backdropChild:Hide() end
        return
    end

    -- Always lay out BB_MAX_WEAPONS columns → frame width stays CONSTANT whether
    -- locked or unlocked, so slot 1 (rightmost) never jumps on lock/unlock.
    BBLayout(bbWeaponBtns, BB_MAX_WEAPONS, visible, iconSz, BB_MAX_WEAPONS, true)

    -- Locked: hide preview slots (only real enchants visible)
    if locked then
        for i = visible + 1, BB_MAX_WEAPONS do
            bbWeaponBtns[i]:Hide()
        end
    end

    -- Size backdrop child to cover only the displayed slots.
    -- Unlocked: BB_MAX_WEAPONS slots (real + preview); Locked: only visible slots.
    local wBD = bbWeaponFrame.backdropChild
    if wBD then
        local bdSlots = locked and visible or BB_MAX_WEAPONS
        local stepH   = iconSz + BB_PAD
        -- Width covers bdSlots icons with BB_PAD gaps + BB_PAD on each side
        -- = bdSlots*stepH + BB_PAD  (matching BBLayout's fw formula shifted by -BB_PAD
        --   so right edge lands BB_PAD inside the parent frame's right edge)
        local bdW = bdSlots * stepH + BB_PAD
        local bdH = iconSz + 3 * BB_PAD   -- = 1 row fh from BBLayout
        wBD:ClearAllPoints()
        wBD:SetPoint("TOPRIGHT", bbWeaponFrame, "TOPRIGHT", -BB_PAD, 0)
        wBD:SetWidth(bdW)
        wBD:SetHeight(bdH)
        wBD:Show()
    end
end

-- ============================================================
-- ── Shared OnUpdate (timer ticks + weapon refresh)
-- ============================================================
local bbTimerAccum = 0
local bbUpdater    = CreateFrame("Frame", nil, UIParent)
bbUpdater:Hide()
bbUpdater:SetScript("OnUpdate", function()
    local dt = arg1
    if not dt or dt < 0 then dt = 0 end
    bbTimerAccum = bbTimerAccum + dt
    if bbTimerAccum < BB_UPDATE_INT then return end
    bbTimerAccum = 0
    if bbBuffFrame   and bbBuffFrame:IsShown()   then BBUpdateBuffBar()     end
    if bbDebuffFrame and bbDebuffFrame:IsShown() then BBUpdateDebuffBar()   end
    if bbConFrame    and bbConFrame:IsShown()    then BBUpdateConsolidated() end
    if bbWeaponFrame and bbWeaponFrame:IsShown() then BBUpdateWeaponBar()   end
end)

local function BBCheckUpdater()
    local db = GetBBDB()
    if db and (db.buffBarEnabled or db.debuffBarEnabled or db.weaponBarEnabled or db.consolidatedEnabled) then
        bbUpdater:Show()
    else
        bbUpdater:Hide()
    end
end

-- ============================================================
-- ── Event frame (player-only UNIT_AURA is acceptable)
-- ============================================================
local bbEventFrame = CreateFrame("Frame", "ART_BB_EventFrame", UIParent)
bbEventFrame:RegisterEvent("UNIT_AURA")
bbEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
bbEventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
bbEventFrame:SetScript("OnEvent", function()
    local evt = event
    local a1  = arg1
    if evt == "UNIT_AURA" and a1 ~= "player" then return end
    if bbBuffFrame   and bbBuffFrame:IsShown()   then BBUpdateBuffBar()   end
    if bbDebuffFrame and bbDebuffFrame:IsShown() then BBUpdateDebuffBar() end
    if bbConFrame    and bbConFrame:IsShown()    then BBUpdateConsolidated() end
    if (evt == "UNIT_INVENTORY_CHANGED" or evt == "PLAYER_ENTERING_WORLD")
        and bbWeaponFrame and bbWeaponFrame:IsShown() then
        BBUpdateWeaponBar()
    end
end)

-- ============================================================
-- ── Blizzard frame suppression (VCB pattern)
-- ============================================================
-- Track visibility state before we suppressed it.
-- nil  = we have not suppressed it this session
-- true = it was shown when we suppressed it (restore on un-suppress)
-- false = it was already hidden when we suppressed it (don't restore)
local bbBlizzWasShown       = nil
local bbBlizzWeaponWasShown = nil

local function BBSuppressBlizzBuffFrame()
    if BuffFrame then
        -- Only snapshot once (don't overwrite a prior snapshot)
        if bbBlizzWasShown == nil then
            bbBlizzWasShown = BuffFrame:IsShown() and true or false
        end
        BuffFrame:Hide()
        for i = 0, 23 do
            local btn = getglobal("BuffButton" .. i)
            if btn then btn:UnregisterEvent("PLAYER_AURAS_CHANGED") end
        end
    end
end

local function BBRestoreBlizzBuffFrame()
    local db = GetBBDB()
    -- Keep suppressed if a bar is still active or persistent hide is on
    if db and (db.buffBarEnabled or db.debuffBarEnabled or db.hideBlizzBuffFrame) then return end
    if BuffFrame then
        for i = 0, 23 do
            local btn = getglobal("BuffButton" .. i)
            if btn then btn:RegisterEvent("PLAYER_AURAS_CHANGED") end
        end
        -- Only show if it was visible before we hid it
        if bbBlizzWasShown then
            BuffFrame:Show()
            if BuffFrame_UpdateAllBuffs then BuffFrame_UpdateAllBuffs() end
        end
    end
    bbBlizzWasShown = nil  -- reset so next suppress snapshots fresh state
end

local function BBSuppressBlizzWeaponFrame()
    if TemporaryEnchantFrame then
        if bbBlizzWeaponWasShown == nil then
            bbBlizzWeaponWasShown = TemporaryEnchantFrame:IsShown() and true or false
        end
        TemporaryEnchantFrame:Hide()
        for i = 1, 2 do
            local btn = getglobal("TempEnchant" .. i)
            if btn then btn:UnregisterEvent("PLAYER_AURAS_CHANGED") end
        end
    end
end

local function BBRestoreBlizzWeaponFrame()
    if TemporaryEnchantFrame then
        for i = 1, 2 do
            local btn = getglobal("TempEnchant" .. i)
            if btn then btn:RegisterEvent("PLAYER_AURAS_CHANGED") end
        end
        if bbBlizzWeaponWasShown then
            TemporaryEnchantFrame:Show()
            if TemporaryEnchantFrame_Update then TemporaryEnchantFrame_Update() end
        end
    end
    bbBlizzWeaponWasShown = nil
end

-- ============================================================
-- ── Show / hide helpers
-- ============================================================
local function BBShowConsolidated(show)
    local db = GetBBDB(); if not db then return end
    db.consolidatedEnabled = show
    if show then
        if not bbConFrame then BBCreateConsolidatedFrame() end
        BBUpdateConAnchor()
        BBUpdateConsolidated()
        bbConFrame:Show()
    else
        if bbConFrame      then bbConFrame:Hide()      end
        if bbConExpFrame   then bbConExpFrame:Hide()   end
        if bbConHoverFrame then bbConHoverFrame:Hide() end
        bbConExpShown = false
    end
    BBCheckUpdater()
end

local function BBShowBuffBar(show)
    local db = GetBBDB(); if not db then return end
    db.buffBarEnabled = show
    if show then
        BBSuppressBlizzBuffFrame()
        if not bbBuffFrame then BBCreateBuffBar() end
        bbBuffFrame:ClearAllPoints()
        bbBuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", db.buffBarX, db.buffBarY)
        BBUpdateBuffBar()
        bbBuffFrame:Show()
        if db.consolidatedEnabled and bbConFrame then BBUpdateConAnchor() end
    elseif bbBuffFrame then
        bbBuffFrame:Hide()
        if db.consolidatedEnabled and bbConFrame and bbConFrame:IsShown() then
            BBUpdateConAnchor()
        end
        BBRestoreBlizzBuffFrame()
    end
    BBCheckUpdater()
end

local function BBShowDebuffBar(show)
    local db = GetBBDB(); if not db then return end
    db.debuffBarEnabled = show
    if show then
        BBSuppressBlizzBuffFrame()
        if not bbDebuffFrame then BBCreateDebuffBar() end
        bbDebuffFrame:ClearAllPoints()
        bbDebuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", db.debuffBarX, db.debuffBarY)
        bbDebuffFrame:Show()
        BBUpdateDebuffBar()  -- runs immediately (frame is now shown)
    elseif bbDebuffFrame then
        bbDebuffFrame:Hide()
        BBRestoreBlizzBuffFrame()
    end
    BBCheckUpdater()
end

local function BBShowWeaponBar(show)
    local db = GetBBDB(); if not db then return end
    db.weaponBarEnabled = show
    if show then
        BBSuppressBlizzWeaponFrame()
        if not bbWeaponFrame then BBCreateWeaponBar() end
        bbWeaponFrame:ClearAllPoints()
        bbWeaponFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", db.weaponBarX, db.weaponBarY)
        BBUpdateWeaponBar()
        bbWeaponFrame:Show()
    elseif bbWeaponFrame then
        bbWeaponFrame:Hide()
        BBRestoreBlizzWeaponFrame()
    end
    BBCheckUpdater()
end

-- ============================================================
-- ── Consolidated list management popup
-- ============================================================
local bbListPopup = nil

local function BBBuildListPopup()
    local POPUP_W, POPUP_H = 300, 280
    local ROW_H = 18
    local DISP  = 10

    local pop = CreateFrame("Frame", "ART_BB_ListPopup", UIParent)
    pop:SetWidth(POPUP_W)
    pop:SetHeight(POPUP_H)
    pop:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    pop:SetFrameStrata("FULLSCREEN_DIALOG")
    pop:SetMovable(true)
    pop:EnableMouse(true)
    pop:RegisterForDrag("LeftButton")
    pop:SetScript("OnDragStart", function() this:StartMoving() end)
    pop:SetScript("OnDragStop",  function() this:StopMovingOrSizing() end)
    pop:SetBackdrop(BB_BD)
    pop:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
    pop:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
    pop:Hide()

    local title = pop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", pop, "TOP", 0, -8)
    title:SetText("Consolidated Buff List")
    title:SetTextColor(1, 0.82, 0, 1)

    local listBox = CreateFrame("Frame", nil, pop)
    listBox:SetPoint("TOPLEFT",     pop, "TOPLEFT",     8, -28)
    listBox:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -8, 56)

    local scrollOff = 0
    local rows = {}

    local function RefreshRows()
        local db2  = GetBBDB()
        local list = db2 and db2.consolidatedList or {}
        local n    = getn(list)
        for i = 1, DISP do
            local realIdx = i + scrollOff
            local row = rows[i]
            if realIdx <= n then
                row.label:SetText(list[realIdx])
                row.realIdx = realIdx
                row:Show()
            else
                row:Hide()
            end
        end
    end

    for i = 1, DISP do
        local row = CreateFrame("Frame", nil, listBox)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT",  listBox, "TOPLEFT",   0,   -(i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", listBox, "TOPRIGHT", -22,  0)
        row:Hide()
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", row, "LEFT", 4, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetTextColor(0.9, 0.9, 0.9, 1)
        row.label = lbl
        local delBtn = BBMakeBtn(row, "x", 16, 14)
        delBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        local rowRef = row
        delBtn:SetScript("OnClick", function()
            local db2 = GetBBDB()
            if db2 and rowRef.realIdx then
                table.remove(db2.consolidatedList, rowRef.realIdx)
                if scrollOff > 0 and scrollOff >= getn(db2.consolidatedList) - DISP + 1 then
                    scrollOff = mmax(0, scrollOff - 1)
                end
                RefreshRows()
                BBUpdateConsolidated()
            end
        end)
        rows[i] = row
    end

    listBox:EnableMouseWheel(true)
    listBox:SetScript("OnMouseWheel", function()
        local db2 = GetBBDB()
        local n   = db2 and getn(db2.consolidatedList) or 0
        local delta = arg1
        if delta > 0 then
            if scrollOff > 0 then scrollOff = scrollOff - 1; RefreshRows() end
        else
            if scrollOff < n - DISP then scrollOff = scrollOff + 1; RefreshRows() end
        end
    end)

    local scrollUp = BBMakeBtn(listBox, "▲", 18, 18)
    scrollUp:SetPoint("TOPRIGHT", listBox, "TOPRIGHT", 0, 0)
    scrollUp:SetScript("OnClick", function()
        if scrollOff > 0 then scrollOff = scrollOff - 1; RefreshRows() end
    end)
    local scrollDn = BBMakeBtn(listBox, "▼", 18, 18)
    scrollDn:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", 0, 0)
    scrollDn:SetScript("OnClick", function()
        local db2 = GetBBDB()
        local n   = db2 and getn(db2.consolidatedList) or 0
        if scrollOff < n - DISP then scrollOff = scrollOff + 1; RefreshRows() end
    end)

    local addEB = CreateFrame("EditBox", "ART_BB_ListPopupEB", pop)
    addEB:SetWidth(180); addEB:SetHeight(20)
    addEB:SetFontObject(GameFontHighlightSmall)
    addEB:SetTextInsets(4, 4, 0, 0)
    addEB:SetBackdrop(BB_BD)
    addEB:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    addEB:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    addEB:SetAutoFocus(false)
    addEB:SetMaxLetters(128)
    addEB:SetPoint("BOTTOMLEFT", pop, "BOTTOMLEFT", 8, 32)
    addEB:SetScript("OnEditFocusGained", function() this:SetBackdropBorderColor(1, 0.82, 0, 0.8) end)
    addEB:SetScript("OnEditFocusLost",   function() this:SetBackdropBorderColor(0.35, 0.35, 0.4, 1) end)
    addEB:SetScript("OnEscapePressed",   function() this:ClearFocus() end)

    local addBtn = BBMakeBtn(pop, "+ Add", 60, 20)
    addBtn:SetPoint("LEFT", addEB, "RIGHT", 4, 0)

    local function DoAdd()
        local txt = addEB:GetText()
        if not txt or txt == "" then return end
        local db2 = GetBBDB(); if not db2 then return end
        for token in string.gfind(txt, "[^,;]+") do
            local name = string.gsub(token, "^%s*(.-)%s*$", "%1")
            if name ~= "" then
                local dupe = false
                for i = 1, getn(db2.consolidatedList) do
                    if db2.consolidatedList[i] == name then dupe = true; break end
                end
                if not dupe then tinsert(db2.consolidatedList, name) end
            end
        end
        addEB:SetText(""); addEB:ClearFocus()
        local n2 = getn(db2.consolidatedList)
        scrollOff = mmax(0, n2 - DISP)
        RefreshRows(); BBUpdateConsolidated()
    end
    addBtn:SetScript("OnClick", DoAdd)
    addEB:SetScript("OnEnterPressed", function() DoAdd() end)

    local resetBtn = BBMakeBtn(pop, "Reset Defaults", 100, 20)
    resetBtn:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -8, 8)
    resetBtn:SetScript("OnClick", function()
        local db2 = GetBBDB(); if not db2 then return end
        db2.consolidatedList = {}
        for i = 1, getn(BB_DEFAULT_CONSOLIDATED) do
            db2.consolidatedList[i] = BB_DEFAULT_CONSOLIDATED[i]
        end
        scrollOff = 0; RefreshRows(); BBUpdateConsolidated()
    end)
    local closeBtn = BBMakeBtn(pop, "Close", 50, 20)
    closeBtn:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
    closeBtn:SetScript("OnClick", function() pop:Hide() end)

    pop.refresh = RefreshRows
    bbListPopup = pop
end

-- ============================================================
-- ── Slider helper (named for sub-element access)
-- ============================================================
local bbSliderCount = 0
local function BBMakeSlider(parent, xOffset, label, minV, maxV, step, initV, onChange)
    bbSliderCount = bbSliderCount + 1
    local sname   = "ART_BB_Slider" .. bbSliderCount

    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", parent, "LEFT", xOffset, 0)
    lbl:SetWidth(110)
    lbl:SetJustifyH("LEFT")
    lbl:SetText(label)
    lbl:SetTextColor(0.85, 0.85, 0.85, 1)

    local slider = CreateFrame("Slider", sname, parent, "OptionsSliderTemplate")
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    slider:SetValue(initV)
    slider:SetWidth(100)
    slider:SetHeight(14)
    slider:SetPoint("LEFT", lbl, "RIGHT", 6, 0)

    local low  = getglobal(sname .. "Low")
    local high = getglobal(sname .. "High")
    local txt  = getglobal(sname .. "Text")
    if low  then low:SetText(tostring(minV))  end
    if high then high:SetText(tostring(maxV)) end
    if txt  then txt:SetText("")              end

    local valLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valLbl:SetPoint("LEFT", slider, "RIGHT", 5, 0)
    valLbl:SetWidth(26)
    valLbl:SetJustifyH("LEFT")
    valLbl:SetText(tostring(initV))
    slider.valLbl = valLbl

    slider:SetScript("OnValueChanged", function()
        local v = floor(this:GetValue() / step + 0.5) * step
        valLbl:SetText(tostring(v))
        if onChange then onChange(v) end
    end)

    -- Expose SetVal so refresh can update without re-triggering onChange
    slider.SetVal = function(s, v)
        s.valLbl:SetText(tostring(v))
        s:SetValue(v)
    end
    return slider
end

-- ============================================================
-- ── Init (PLAYER_LOGIN)
-- ============================================================
function AmptieRaidTools_InitBuffBars()
    local db = GetBBDB(); if not db then return end
    if db.buffBarEnabled      then BBShowBuffBar(true)      end
    if db.debuffBarEnabled    then BBShowDebuffBar(true)    end
    if db.weaponBarEnabled    then BBShowWeaponBar(true)    end
    if db.consolidatedEnabled then BBShowConsolidated(true) end
    -- Apply persistent Blizzard buff frame suppression if enabled but no aRT bars active
    if db.hideBlizzBuffFrame and not db.buffBarEnabled and not db.debuffBarEnabled then
        BBSuppressBlizzBuffFrame()
    end
end

-- ============================================================
-- ── Settings section (called from classbuffs.lua panel init)
-- Returns a refresh function for the panel's OnShow.
-- ============================================================
function ART_BB_BuildSettingsSection(panel, anchor)
    -- Fixed column X offsets (relative to each row frame's LEFT)
    local COL_CB    = 0    -- checkbox
    local COL_LOCK  = 160  -- lock/unlock button
    local COL_XTRA  = 218  -- extra button (Manage List)
    local COL_RESET = 218  -- reset position button (debuff/weapon rows)
    local COL_RESET_CON = 306 -- reset position button (consolidated row, after Manage List)
    local ROW_H    = 22
    local SUB_H    = 20
    local INDENT   = 14

    local function MakeDivider(anch, offY)
        local d = panel:CreateTexture(nil, "ARTWORK")
        d:SetHeight(1)
        d:SetPoint("TOPLEFT",  anch,  "BOTTOMLEFT",  0, offY)
        d:SetPoint("TOPRIGHT", panel, "TOPRIGHT",   -12, 0)
        d:SetTexture(0.25, 0.25, 0.28, 0.8)
        return d
    end

    local div = MakeDivider(anchor, -10)
    local hdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hdr:SetPoint("TOPLEFT", div, "BOTTOMLEFT", 0, -8)
    hdr:SetText("Consolidated Buffs")
    hdr:SetTextColor(1, 0.82, 0, 1)

    local db = GetBBDB()

    -- Row factory: each row is a full-width frame child of panel
    local lastAnchor = hdr
    local firstRow = true
    local function NextRow(h)
        h = h or ROW_H
        local f = CreateFrame("Frame", nil, panel)
        f:SetHeight(h)
        local gap = firstRow and -8 or -4
        firstRow = false
        f:SetPoint("TOPLEFT",  lastAnchor, "BOTTOMLEFT",  0,  gap)
        f:SetPoint("TOPRIGHT", panel,      "TOPRIGHT",   -12,   0)
        lastAnchor = f
        return f
    end

    -- ── Consolidated Buffs ────────────────────────────────────
    local rowCon = NextRow(ROW_H)
    local cbCon = ART_CreateCheckbox(rowCon, "Consolidated Buffs")
    cbCon:SetPoint("LEFT", rowCon, "LEFT", COL_CB, 0)
    cbCon:SetChecked(db and db.consolidatedEnabled)
    cbCon.userOnClick = function()
        local enabled = cbCon:GetChecked() and true or false
        -- Enabling consolidated automatically hides those buffs from the bar (and vice versa)
        local d = GetBBDB()
        if d then d.hideConsolidatedInBar = enabled end
        BBShowConsolidated(enabled)
        if bbBuffFrame and bbBuffFrame:IsShown() then BBUpdateBuffBar() end
    end

    -- Combined lock: controls both buff bar and consolidated (they move together)
    local lockConBtn = BBMakeBtn(rowCon, "Unlock", 52, 18)
    lockConBtn:SetPoint("LEFT", rowCon, "LEFT", COL_LOCK, 0)
    local function UpdateLockCon()
        local d = GetBBDB()
        lockConBtn:SetText(d and d.buffBarLocked and "Unlock" or "Lock")
    end
    lockConBtn:SetScript("OnClick", function()
        local d = GetBBDB()
        if d then
            d.buffBarLocked      = not d.buffBarLocked
            d.consolidatedLocked = d.buffBarLocked
            -- Trigger preview update on both bars
            if bbBuffFrame   and bbBuffFrame:IsShown()   then BBUpdateBuffBar()   end
            if bbDebuffFrame and bbDebuffFrame:IsShown() then BBUpdateDebuffBar() end
        end
        UpdateLockCon()
    end)
    UpdateLockCon()

    local manageBtn = BBMakeBtn(rowCon, "Manage List", 82, 18)
    manageBtn:SetPoint("LEFT", rowCon, "LEFT", COL_XTRA, 0)
    manageBtn:SetScript("OnClick", function()
        if not bbListPopup then BBBuildListPopup() end
        if bbListPopup:IsShown() then bbListPopup:Hide()
        else bbListPopup.refresh(); bbListPopup:Show() end
    end)

    local resetConBtn = BBMakeBtn(rowCon, "Reset Pos", 62, 18)
    resetConBtn:SetPoint("LEFT", rowCon, "LEFT", COL_RESET_CON, 0)
    resetConBtn:SetScript("OnClick", function()
        local d = GetBBDB(); if not d then return end
        d.consolidatedPoint = "CENTER"; d.consolidatedX = 0; d.consolidatedY = 220
        d.buffBarX = 0; d.buffBarY = -160
        if bbBuffFrame and bbBuffFrame:IsShown() then
            bbBuffFrame:ClearAllPoints()
            bbBuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, -160)
        end
        if bbConFrame and bbConFrame:IsShown() then BBUpdateConAnchor() end
    end)

    -- ── Buff Bar ──────────────────────────────────────────────
    NextRow(6)  -- spacer
    local rowBuff = NextRow(ROW_H)
    local cbBuff = ART_CreateCheckbox(rowBuff, "Buff Bar")
    cbBuff:SetPoint("LEFT", rowBuff, "LEFT", COL_CB, 0)
    cbBuff:SetChecked(db and db.buffBarEnabled)
    cbBuff.userOnClick = function()
        BBShowBuffBar(cbBuff:GetChecked() and true or false)
    end

    -- No separate lock for buff bar — it shares the combined lock above

    -- Buff icon size
    local rowBuffSz = NextRow(SUB_H)
    local sliderBuffSz = BBMakeSlider(rowBuffSz, INDENT, "Icon size", 16, 48, 2,
        db and db.buffIconSz or BB_ICON_DEFAULT,
        function(v)
            local d = GetBBDB(); if not d then return end
            d.buffIconSz = v
            if bbBuffFrame and bbBuffFrame:IsShown() then BBUpdateBuffBar() end
            if bbConFrame then
                bbConFrame:SetWidth(v + BB_PAD * 2)
                bbConFrame:SetHeight(v + BB_PAD * 2)
            end
        end)

    -- Buff per-row
    local rowBuffRow = NextRow(SUB_H)
    local sliderBuffRow = BBMakeSlider(rowBuffRow, INDENT, "Per row", 4, 32, 1,
        db and db.buffBarNumPerRow or 16,
        function(v)
            local d = GetBBDB(); if not d then return end
            d.buffBarNumPerRow = v
            if bbBuffFrame and bbBuffFrame:IsShown() then BBUpdateBuffBar() end
        end)

    -- ── Debuff Bar ────────────────────────────────────────────
    NextRow(6)  -- spacer
    local rowDebuff = NextRow(ROW_H)
    local cbDebuff = ART_CreateCheckbox(rowDebuff, "Debuff Bar")
    cbDebuff:SetPoint("LEFT", rowDebuff, "LEFT", COL_CB, 0)
    cbDebuff:SetChecked(db and db.debuffBarEnabled)
    cbDebuff.userOnClick = function()
        BBShowDebuffBar(cbDebuff:GetChecked() and true or false)
    end

    local lockDebuffBtn = BBMakeBtn(rowDebuff, "Unlock", 52, 18)
    lockDebuffBtn:SetPoint("LEFT", rowDebuff, "LEFT", COL_LOCK, 0)
    local function UpdateLockDebuff()
        local d = GetBBDB()
        lockDebuffBtn:SetText(d and d.debuffBarLocked and "Unlock" or "Lock")
    end
    lockDebuffBtn:SetScript("OnClick", function()
        local d = GetBBDB(); if d then d.debuffBarLocked = not d.debuffBarLocked end
        if bbDebuffFrame and bbDebuffFrame:IsShown() then BBUpdateDebuffBar() end
        UpdateLockDebuff()
    end)
    UpdateLockDebuff()

    local resetDebuffBtn = BBMakeBtn(rowDebuff, "Reset Pos", 62, 18)
    resetDebuffBtn:SetPoint("LEFT", rowDebuff, "LEFT", COL_RESET, 0)
    resetDebuffBtn:SetScript("OnClick", function()
        local d = GetBBDB(); if not d then return end
        d.debuffBarX = 0; d.debuffBarY = -200
        if bbDebuffFrame and bbDebuffFrame:IsShown() then
            bbDebuffFrame:ClearAllPoints()
            bbDebuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, -200)
        end
    end)

    -- Debuff icon size
    local rowDebuffSz = NextRow(SUB_H)
    local sliderDebuffSz = BBMakeSlider(rowDebuffSz, INDENT, "Icon size", 16, 48, 2,
        db and db.debuffIconSz or BB_ICON_DEFAULT,
        function(v)
            local d = GetBBDB(); if not d then return end
            d.debuffIconSz = v
            if bbDebuffFrame and bbDebuffFrame:IsShown() then
                BBUpdateDebuffBar()
                -- Re-anchor after frame resize (iconSz change alters BBLayout width).
                bbDebuffFrame:ClearAllPoints()
                bbDebuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", d.debuffBarX, d.debuffBarY)
            end
        end)

    -- Debuff per-row
    local rowDebuffRow = NextRow(SUB_H)
    local sliderDebuffRow = BBMakeSlider(rowDebuffRow, INDENT, "Per row", 4, 16, 1,
        db and db.debuffBarNumPerRow or 8,
        function(v)
            local d = GetBBDB(); if not d then return end
            d.debuffBarNumPerRow = v
            if bbDebuffFrame and bbDebuffFrame:IsShown() then
                BBUpdateDebuffBar()
                -- Re-anchor after frame resize (perRow change alters BBLayout width).
                bbDebuffFrame:ClearAllPoints()
                bbDebuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", d.debuffBarX, d.debuffBarY)
            end
        end)

    -- ── Weapon Buff Bar ───────────────────────────────────────
    NextRow(6)  -- spacer
    local rowWeapon = NextRow(ROW_H)
    local cbWeapon = ART_CreateCheckbox(rowWeapon, "Weapon Buff Bar")
    cbWeapon:SetPoint("LEFT", rowWeapon, "LEFT", COL_CB, 0)
    cbWeapon:SetChecked(db and db.weaponBarEnabled)
    cbWeapon.userOnClick = function()
        BBShowWeaponBar(cbWeapon:GetChecked() and true or false)
    end

    local lockWepBtn = BBMakeBtn(rowWeapon, "Unlock", 52, 18)
    lockWepBtn:SetPoint("LEFT", rowWeapon, "LEFT", COL_LOCK, 0)
    local function UpdateLockWep()
        local d = GetBBDB()
        lockWepBtn:SetText(d and d.weaponBarLocked and "Unlock" or "Lock")
    end
    lockWepBtn:SetScript("OnClick", function()
        local d = GetBBDB()
        if d then
            d.weaponBarLocked = not d.weaponBarLocked
            if bbWeaponFrame and bbWeaponFrame:IsShown() then BBUpdateWeaponBar() end
        end
        UpdateLockWep()
    end)
    UpdateLockWep()

    local resetWepBtn = BBMakeBtn(rowWeapon, "Reset Pos", 62, 18)
    resetWepBtn:SetPoint("LEFT", rowWeapon, "LEFT", COL_RESET, 0)
    resetWepBtn:SetScript("OnClick", function()
        local d = GetBBDB(); if not d then return end
        d.weaponBarX = 0; d.weaponBarY = -240
        if bbWeaponFrame and bbWeaponFrame:IsShown() then
            bbWeaponFrame:ClearAllPoints()
            bbWeaponFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, -240)
        end
    end)

    -- Weapon icon size
    local rowWeaponSz = NextRow(SUB_H)
    local sliderWeaponSz = BBMakeSlider(rowWeaponSz, INDENT, "Icon size", 16, 48, 2,
        db and db.weaponIconSz or BB_ICON_DEFAULT,
        function(v)
            local d = GetBBDB(); if not d then return end
            d.weaponIconSz = v
            if bbWeaponFrame and bbWeaponFrame:IsShown() then
                BBUpdateWeaponBar()
                -- Re-anchor after frame resize (iconSz change alters BBLayout width).
                bbWeaponFrame:ClearAllPoints()
                bbWeaponFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", d.weaponBarX, d.weaponBarY)
            end
        end)

    -- ── Misc ──────────────────────────────────────────────────
    local divMisc = MakeDivider(lastAnchor, -10)
    local hdrMisc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hdrMisc:SetPoint("TOPLEFT", divMisc, "BOTTOMLEFT", 0, -8)
    hdrMisc:SetText("Miscellaneous")
    hdrMisc:SetTextColor(1, 0.82, 0, 1)
    lastAnchor = hdrMisc
    firstRow = true

    local rowHideBlizz = NextRow(ROW_H)
    local cbHideBlizz = ART_CreateCheckbox(rowHideBlizz, "Hide Blizzard Buff Bars")
    cbHideBlizz:SetPoint("LEFT", rowHideBlizz, "LEFT", COL_CB, 0)
    cbHideBlizz:SetChecked(db and db.hideBlizzBuffFrame)
    cbHideBlizz.userOnClick = function()
        local d = GetBBDB(); if not d then return end
        d.hideBlizzBuffFrame = cbHideBlizz:GetChecked() and true or false
        if d.hideBlizzBuffFrame then
            BBSuppressBlizzBuffFrame()
        else
            BBRestoreBlizzBuffFrame()
        end
    end

    -- Refresh callback for panel OnShow
    return function()
        local d = GetBBDB(); if not d then return end
        cbCon:SetChecked(d.consolidatedEnabled)
        cbBuff:SetChecked(d.buffBarEnabled)
        cbDebuff:SetChecked(d.debuffBarEnabled)
        cbWeapon:SetChecked(d.weaponBarEnabled)
        cbHideBlizz:SetChecked(d.hideBlizzBuffFrame)
        sliderBuffSz:SetVal(d.buffIconSz or BB_ICON_DEFAULT)
        sliderBuffRow:SetVal(d.buffBarNumPerRow or 16)
        sliderDebuffSz:SetVal(d.debuffIconSz or BB_ICON_DEFAULT)
        sliderDebuffRow:SetVal(d.debuffBarNumPerRow or 8)
        sliderWeaponSz:SetVal(d.weaponIconSz or BB_ICON_DEFAULT)
        UpdateLockCon(); UpdateLockDebuff(); UpdateLockWep()
    end
end
