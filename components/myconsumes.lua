-- components/myconsumes.lua
-- My Consumes — personal consumable tracker with overlay
-- Lua 5.0 / WoW 1.12 / TurtleWoW (SuperWoW optional)

local getn    = table.getn
local tinsert = table.insert
local floor   = math.floor
local sfind   = string.find
local pairs   = pairs
local GetTime = GetTime

local MC_HAS_SUPERWOW = (SpellInfo ~= nil)

-- Zone options for rules dropdown: raids from global ART_ZONES + dungeon/pvp/world
local MC_ZONE_OPTIONS = nil  -- built lazily

local function MC_GetZoneOptions()
    if MC_ZONE_OPTIONS then return MC_ZONE_OPTIONS end
    MC_ZONE_OPTIONS = {}
    if ART_ZONES then
        for i = 1, getn(ART_ZONES) do
            tinsert(MC_ZONE_OPTIONS, { key = ART_ZONES[i].key, label = ART_ZONES[i].label })
        end
    end
    tinsert(MC_ZONE_OPTIONS, { key="dungeon", label="Dungeon" })
    tinsert(MC_ZONE_OPTIONS, { key="pvp",     label="PvP" })
    tinsert(MC_ZONE_OPTIONS, { key="world",   label="Open World" })
    return MC_ZONE_OPTIONS
end

-- Hidden tooltip for buff name scanning
local mcScanTip = CreateFrame("GameTooltip", "ART_MC_ScanTip", UIParent, "GameTooltipTemplate")
mcScanTip:SetOwner(UIParent, "ANCHOR_NONE")
local mcScanTipText = nil

-- ============================================================
-- DB
-- ============================================================
-- Built-in profile names: "Default" + all specs for the player's class
local MC_BUILTIN_PROFILES = nil  -- populated after UnitClass is available

local function MC_EnsureBuiltinProfiles(s)
    if not s.profiles then s.profiles = {} end
    if not s.profiles["Default"] then s.profiles["Default"] = { rules = {} } end
    -- Ensure class spec profiles exist
    if ART_SpecsByClass then
        local _, cl = UnitClass("player")
        cl = cl and string.upper(cl) or ""
        local specs = ART_SpecsByClass[cl] or {}
        for i = 1, getn(specs) do
            if not s.profiles[specs[i]] then s.profiles[specs[i]] = { rules = {} } end
        end
    end
    -- Build list for UI
    MC_BUILTIN_PROFILES = { "Default" }
    if ART_SpecsByClass then
        local _, cl = UnitClass("player")
        cl = cl and string.upper(cl) or ""
        local specs = ART_SpecsByClass[cl] or {}
        for i = 1, getn(specs) do tinsert(MC_BUILTIN_PROFILES, specs[i]) end
    end
end

local function MC_IsBuiltinProfile(name)
    if name == "Default" then return true end
    if ART_SpecsByClass then
        local _, cl = UnitClass("player")
        cl = cl and string.upper(cl) or ""
        local specs = ART_SpecsByClass[cl] or {}
        for i = 1, getn(specs) do
            if specs[i] == name then return true end
        end
    end
    return false
end

local function GetMCDB()
    local db = amptieRaidToolsDB
    if not db.myconsumes then db.myconsumes = {} end
    local s = db.myconsumes
    if s.ovlIconSize  == nil then s.ovlIconSize  = 32       end
    if s.ovlPerRow    == nil then s.ovlPerRow    = 8        end
    if s.ovlShown     == nil then s.ovlShown     = false    end
    if s.ovlLocked    == nil then s.ovlLocked    = true     end
    if s.reappearSec  == nil then s.reappearSec  = 0        end
    if s.reappearMode == nil then s.reappearMode = "none"   end
    if s.activeMode   == nil then s.activeMode   = "none"   end
    if s.specBinding  == nil then s.specBinding  = false   end
    MC_EnsureBuiltinProfiles(s)
    if not s.activeProfile or not s.profiles[s.activeProfile] then
        s.activeProfile = "Default"
    end
    return s
end

local function GetActiveMCProfile()
    local s = GetMCDB()
    return s.profiles[s.activeProfile]
end

-- ============================================================
-- Buff scanning (own buffs only)
-- ============================================================
local mcBuffCache = {}  -- [buffName] = timeLeft or true

local function MC_ScanPlayerBuffs()
    for k in pairs(mcBuffCache) do mcBuffCache[k] = nil end
    for i = 0, 39 do
        local buffIndex = GetPlayerBuff(i, "HELPFUL")
        if buffIndex < 0 then break end
        -- Get name via SuperWoW or tooltip fallback
        local bname = nil
        if MC_HAS_SUPERWOW then
            local _, _, spellId = UnitBuff("player", i + 1)
            if spellId and spellId > 0 then bname = SpellInfo(spellId) end
        end
        if not bname then
            if not mcScanTipText then mcScanTipText = getglobal("ART_MC_ScanTipTextLeft1") end
            mcScanTip:SetOwner(UIParent, "ANCHOR_NONE")
            mcScanTip:SetPlayerBuff(buffIndex)
            bname = mcScanTipText and mcScanTipText:GetText()
        end
        if bname and bname ~= "" then
            local tl = GetPlayerBuffTimeLeft(buffIndex)
            mcBuffCache[bname] = (tl and tl > 0) and tl or true
        end
    end
    return mcBuffCache
end

-- ============================================================
-- Bag scanning
-- ============================================================
local mcBagDirty  = true
local mcBagCache  = {}  -- [buffKey] = count

-- Resolve item IDs for a buff entry (itemKey path OR direct itemIds)
local function MC_GetItemIds(bcBuff)
    if bcBuff.itemIds then return bcBuff.itemIds end
    if bcBuff.itemKey and ART_IC_BY_KEY_ALL then
        local icItem = ART_IC_BY_KEY_ALL[bcBuff.itemKey]
        if icItem and icItem.ids then return icItem.ids end
    end
    return nil
end

local function MC_ScanBags()
    for k in pairs(mcBagCache) do mcBagCache[k] = nil end
    if not ART_BC_BY_KEY_ALL then return end
    local idToKey = {}
    local prof = GetActiveMCProfile()
    if not prof then return end
    for ri = 1, getn(prof.rules) do
        local bk = prof.rules[ri].buffKey
        local bcBuff = ART_BC_BY_KEY_ALL[bk]
        if bcBuff then
            local ids = MC_GetItemIds(bcBuff)
            if ids then
                for ii = 1, getn(ids) do idToKey[ids[ii]] = bk end
            end
        end
        if not mcBagCache[bk] then mcBagCache[bk] = 0 end
    end
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, idStr = sfind(link, "item:(%d+):")
                if idStr then
                    local id = tonumber(idStr)
                    local bk = idToKey[id]
                    if bk then
                        local _, cnt = GetContainerItemInfo(bag, slot)
                        mcBagCache[bk] = (mcBagCache[bk] or 0) + math.abs(cnt or 1)
                    end
                end
            end
        end
    end
    mcBagDirty = false
end

-- Find and use an item from bags
local function MC_UseItem(buffKey, weaponSlot)
    if not ART_BC_BY_KEY_ALL then return end
    local bcBuff = ART_BC_BY_KEY_ALL[buffKey]
    if not bcBuff then return end

    -- Shaman imbues: cast from spellbook (auto-applies to weapon, no extra click)
    if bcBuff.spellCast then
        CastSpellByName(bcBuff.spellCast)
        return
    end

    -- Item-based (potions, stones, oils, poisons)
    local ids = MC_GetItemIds(bcBuff)
    if not ids then return end
    local idSet = {}
    for ii = 1, getn(ids) do idSet[ids[ii]] = true end
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, idStr = sfind(link, "item:(%d+):")
                if idStr and idSet[tonumber(idStr)] then
                    UseContainerItem(bag, slot)
                    -- Weapon buffs: auto-apply to the correct inventory slot
                    if bcBuff.sec == "weapon" then
                        local invSlot = (weaponSlot == "OH") and 17 or 16
                        PickupInventoryItem(invSlot)
                        if ReplaceEnchant then ReplaceEnchant() end
                    end
                    return
                end
            end
        end
    end
end

-- ============================================================
-- Overlay
-- ============================================================
local mcOverlayFrame = nil
local MC_OVL_HDR_H   = 24

-- Format time: <90s → "42s", 90s-90m → "12m", >90m → "2h"
local function MC_FmtTime(sec)
    if sec <= 0 then return "" end
    if sec < 90 then return floor(sec) .. "s" end
    local m = floor(sec / 60)
    if m < 90 then return m .. "m" end
    return floor(m / 60) .. "h"
end
local MC_OVL_PAD      = 6
local MC_OVL_GAP      = 3
local mcInCombat      = false

-- Custom tooltip (pfUI-safe)
local MC_TIP_PAD    = 6
local MC_TIP_LINE_H = 14
local mcTipFrame = CreateFrame("Frame", "ART_MC_TipFrame", UIParent)
mcTipFrame:SetFrameStrata("TOOLTIP")
mcTipFrame:SetBackdrop({
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 10,
    insets = { left=3, right=3, top=3, bottom=3 },
})
mcTipFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
mcTipFrame:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
mcTipFrame:Hide()
local mcTipLines = {}
local function MCTipGetLine(idx)
    if not mcTipLines[idx] then
        local fs = mcTipFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", mcTipFrame, "TOPLEFT", MC_TIP_PAD, -(MC_TIP_PAD + (idx-1)*MC_TIP_LINE_H))
        fs:SetJustifyH("LEFT")
        mcTipLines[idx] = fs
    end
    return mcTipLines[idx]
end
local function MCTipShow(anchor, lines)
    local maxW = 0
    for i = 1, getn(lines) do
        local ln = MCTipGetLine(i)
        ln:SetText(lines[i][1])
        ln:SetTextColor(lines[i][2], lines[i][3], lines[i][4], 1)
        ln:Show()
        local w = ln:GetStringWidth()
        if w > maxW then maxW = w end
    end
    for i = getn(lines)+1, getn(mcTipLines) do mcTipLines[i]:Hide() end
    mcTipFrame:SetWidth(maxW + MC_TIP_PAD * 2)
    mcTipFrame:SetHeight(getn(lines) * MC_TIP_LINE_H + MC_TIP_PAD * 2)
    mcTipFrame:ClearAllPoints()
    mcTipFrame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    mcTipFrame:Show()
end
local function MCTipHide() mcTipFrame:Hide() end

local function MCSetOverlayCombatState(inCombat)
    if not mcOverlayFrame then return end
    if not mcOverlayFrame.combatFS then
        local cf = CreateFrame("Frame", nil, mcOverlayFrame)
        cf:SetAllPoints(mcOverlayFrame)
        cf:SetFrameLevel(mcOverlayFrame:GetFrameLevel() + 20)
        local cfs = cf:CreateFontString(nil, "OVERLAY")
        cfs:SetFont("Fonts\\FRIZQT__.TTF", 11, "THICKOUTLINE")
        cfs:SetPoint("CENTER", mcOverlayFrame, "CENTER", 0, 0)
        cfs:SetTextColor(0.7, 0.3, 0.3, 1)
        cfs:SetText("infight: disabled")
        mcOverlayFrame.combatFS = cfs
        mcOverlayFrame.combatFrame = cf
    end
    if inCombat then
        for i = 1, getn(mcOverlayFrame.icons) do
            local ic = mcOverlayFrame.icons[i]
            if ic:IsShown() then ic.tex:SetVertexColor(0.3, 0.3, 0.3) end
        end
        mcOverlayFrame.combatFS:Show()
    else
        for i = 1, getn(mcOverlayFrame.icons) do
            mcOverlayFrame.icons[i].tex:SetVertexColor(1, 1, 1)
        end
        mcOverlayFrame.combatFS:Hide()
    end
end

local function CreateMCOverlay()
    local s = GetMCDB()
    local f = CreateFrame("Frame", "ART_MC_Overlay", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetWidth(200); f:SetHeight(60)
    if s.ovlX and s.ovlY then
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", s.ovlX, s.ovlY)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    end
    f:SetMovable(true); f:SetClampedToScreen(true)
    f:Hide()

    -- Drag hit button: covers entire overlay, only shown when unlocked.
    -- Because it's one large button, OnDragStop always fires on it
    -- regardless of where the cursor ends up (same as buff bars hitBtn).
    local hitBtn = CreateFrame("Button", nil, f)
    hitBtn:SetAllPoints(f)
    hitBtn:SetFrameLevel(f:GetFrameLevel() + 10)
    hitBtn:RegisterForDrag("LeftButton")
    hitBtn:SetScript("OnDragStart", function()
        f:StartMoving()
    end)
    hitBtn:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local d = GetMCDB()
        d.ovlX = f:GetLeft(); d.ovlY = f:GetBottom()
    end)
    hitBtn:Hide()
    f.hitBtn = hitBtn

    f.icons = {}
    local emptyLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyLabel:SetPoint("TOPLEFT", f, "TOPLEFT", MC_OVL_PAD + 2, -(MC_OVL_PAD + 2))
    emptyLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    emptyLabel:SetText("No rules configured.")
    f.emptyLabel = emptyLabel

    mcOverlayFrame = f
end

local RefreshMCOverlay  -- forward decl

RefreshMCOverlay = function()
    if not mcOverlayFrame then return end
    if not mcOverlayFrame:IsShown() then return end

    local s        = GetMCDB()
    local iconSz   = s.ovlIconSize or 32
    local perRow   = s.ovlPerRow   or 8
    local unlocked = not s.ovlLocked
    local prof     = GetActiveMCProfile()
    local rules    = prof and prof.rules or {}

    -- Hide all
    for i = 1, getn(mcOverlayFrame.icons) do mcOverlayFrame.icons[i]:Hide() end
    mcOverlayFrame.emptyLabel:Hide()

    -- When unlocked: show ALL rules in the profile (preview mode)
    -- When locked: filter by current zone
    local visRules = {}
    if unlocked then
        for ri = 1, getn(rules) do tinsert(visRules, rules[ri]) end
    else
        local curZone = ART_GetCurrentZoneKey and ART_GetCurrentZoneKey() or "world"
        for ri = 1, getn(rules) do
            local r = rules[ri]
            -- nil = all zones; {} = none; {key=true} = specific
            if not r.zones then
                tinsert(visRules, r)
            elseif next(r.zones) and r.zones[curZone] then
                tinsert(visRules, r)
            end
        end
    end

    if getn(visRules) == 0 then
        mcOverlayFrame:SetWidth(1); mcOverlayFrame:SetHeight(1)
        return
    end

    MC_ScanPlayerBuffs()
    if mcBagDirty then MC_ScanBags() end

    -- Build icon data
    local iconData = {}
    for ri = 1, getn(visRules) do
        local r  = visRules[ri]
        local bk = r.buffKey
        local bcBuff = ART_BC_BY_KEY_ALL and ART_BC_BY_KEY_ALL[bk]
        if bcBuff then
            local hasBuff = false
            local timeLeft = 0
            if bcBuff.sec == "weapon" then
                -- Weapon buff: check GetWeaponEnchantInfo for the assigned slot
                local wSlot = r.weaponSlot or "MH"
                local hasMH, mhExp, _, hasOH, ohExp = GetWeaponEnchantInfo()
                if wSlot == "OH" then
                    hasBuff = hasOH and true or false
                    timeLeft = hasOH and ((ohExp or 0) / 1000) or 0
                else
                    hasBuff = hasMH and true or false
                    timeLeft = hasMH and ((mhExp or 0) / 1000) or 0
                end
            elseif bcBuff.isFood then
                -- Food: check if ANY known food buff is active
                local foodAny = ART_BC_BY_KEY_ALL and ART_BC_BY_KEY_ALL["FOOD_ANY"]
                local foodNames = foodAny and foodAny.buffNames
                if foodNames then
                    for fi = 1, getn(foodNames) do
                        local v = mcBuffCache[foodNames[fi]]
                        if v then
                            hasBuff = true
                            if type(v) == "number" and v > timeLeft then timeLeft = v end
                        end
                    end
                end
            elseif bcBuff.buffNames then
                for fi = 1, getn(bcBuff.buffNames) do
                    local v = mcBuffCache[bcBuff.buffNames[fi]]
                    if v then
                        hasBuff = true
                        if type(v) == "number" and v > timeLeft then timeLeft = v end
                    end
                end
            elseif bcBuff.buffName then
                local v = mcBuffCache[bcBuff.buffName]
                if v then
                    hasBuff = true
                    if type(v) == "number" then timeLeft = v end
                end
            end
            local bagCount = mcBagCache[bk] or 0
            local reappearThr = r.reappearOverride or s.reappearSec or 0
            tinsert(iconData, {
                buffKey     = bk,
                label       = bcBuff.name,
                icon        = bcBuff.icon,
                hasBuff     = hasBuff,
                timeLeft    = timeLeft,
                bagCount    = bagCount,
                reappearThr = reappearThr,
                weaponSlot  = r.weaponSlot,
                isSpellCast = bcBuff.spellCast and true or false,
            })
        end
    end

    local numIcons = getn(iconData)
    if numIcons == 0 then
        mcOverlayFrame:SetWidth(1); mcOverlayFrame:SetHeight(1)
        return
    end

    local displayIdx = 0
    for i = 1, numIcons do
        local d = iconData[i]

        -- Determine visual state
        local show      = true
        local vertR, vertG, vertB = 1, 1, 1
        local showCount = true

        -- When unlocked: always show all icons at full color with bag count
        if not unlocked and d.hasBuff then
            local enoughTime = (d.reappearThr == 0) or (d.timeLeft == 0) or (d.timeLeft > d.reappearThr)
            if enoughTime then
                if s.activeMode == "disappear" then show = false
                elseif s.activeMode == "grey"  then vertR, vertG, vertB = 0.4, 0.4, 0.4; showCount = false
                else showCount = false end
            else
                if s.reappearMode == "grey"  then vertR, vertG, vertB = 0.4, 0.4, 0.4
                elseif s.reappearMode == "red" then vertR, vertG, vertB = 1, 0.3, 0.3
                end
            end
        end

        if show then
            displayIdx = displayIdx + 1
            local col  = math.mod(displayIdx - 1, perRow)
            local row  = floor((displayIdx - 1) / perRow)
            local xOff = MC_OVL_PAD + col * (iconSz + MC_OVL_GAP)
            local yOff = -(MC_OVL_PAD + row * (iconSz + MC_OVL_GAP))

            local btn = mcOverlayFrame.icons[displayIdx]
            if not btn then
                btn = CreateFrame("Button", nil, mcOverlayFrame)
                btn:RegisterForClicks("LeftButtonUp")
                btn:EnableMouse(true)
                local tex = btn:CreateTexture(nil, "BACKGROUND")
                tex:SetAllPoints(btn)
                btn.tex = tex
                local countFS = btn:CreateFontString(nil, "OVERLAY")
                countFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "THICKOUTLINE")
                countFS:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 2)
                countFS:SetJustifyH("RIGHT")
                btn.countFS = countFS
                local timerFS = btn:CreateFontString(nil, "OVERLAY")
                timerFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "THICKOUTLINE")
                timerFS:SetPoint("CENTER", btn, "CENTER", 0, 0)
                timerFS:SetJustifyH("CENTER")
                timerFS:SetTextColor(1, 1, 1, 1)
                timerFS:Hide()
                btn.timerFS = timerFS
                btn:SetScript("OnEnter", function()
                    local tipLines = {}
                    tinsert(tipLines, { this.buffLabel or "?", 1, 0.82, 0 })
                    if this.hasBuff then
                        local tlStr = "active"
                        if this.timeLeft and this.timeLeft > 0 then
                            local m = floor(this.timeLeft / 60)
                            local sec = floor(math.mod(this.timeLeft, 60))
                            tlStr = m .. ":" .. (sec < 10 and "0" or "") .. sec
                        end
                        tinsert(tipLines, { "Buff: " .. tlStr, 0.4, 1, 0.4 })
                    else
                        tinsert(tipLines, { "Buff: not active", 1, 0.4, 0.4 })
                    end
                    tinsert(tipLines, { "In bags: " .. tostring(this.bagCount or 0), 0.7, 0.7, 0.7 })
                    if not GetMCDB().ovlLocked then
                        tinsert(tipLines, { " ", 1, 1, 1 })
                        tinsert(tipLines, { "Drag to move", 0.5, 0.5, 0.5 })
                    else
                        tinsert(tipLines, { " ", 1, 1, 1 })
                        tinsert(tipLines, { "Click: use consumable", 0.5, 0.5, 0.5 })
                    end
                    MCTipShow(mcOverlayFrame, tipLines)
                end)
                btn:SetScript("OnLeave", function() MCTipHide() end)
                btn:SetScript("OnClick", function()
                    if mcInCombat then return end
                    if not GetMCDB().ovlLocked then return end
                    if this.buffKey then MC_UseItem(this.buffKey, this.weaponSlot) end
                end)
                tinsert(mcOverlayFrame.icons, btn)
            end

            btn:SetWidth(iconSz); btn:SetHeight(iconSz)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", mcOverlayFrame, "TOPLEFT", xOff, yOff)
            btn.tex:SetTexture(d.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            btn.tex:SetVertexColor(vertR, vertG, vertB)
            local fontSize = math.max(floor(iconSz * 0.38), 9)
            btn.countFS:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "THICKOUTLINE")
            btn.timerFS:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "THICKOUTLINE")
            -- Show timer when buff is active with known duration; otherwise show bag count
            if d.hasBuff and d.timeLeft and d.timeLeft > 0 then
                btn.countFS:Hide()
                local tmStr = MC_FmtTime(d.timeLeft)
                btn.timerFS:SetText(tmStr)
                -- Color: white normally, yellow below 5min, red below 1min
                if d.timeLeft < 60 then
                    btn.timerFS:SetTextColor(1, 0.3, 0.3, 1)
                elseif d.timeLeft < 300 then
                    btn.timerFS:SetTextColor(1, 0.82, 0, 1)
                else
                    btn.timerFS:SetTextColor(1, 1, 1, 1)
                end
                btn.timerFS:Show()
            else
                btn.timerFS:Hide()
                if showCount and not d.isSpellCast then
                    btn.countFS:SetText(tostring(d.bagCount))
                    btn.countFS:SetTextColor(d.bagCount > 0 and 1 or 1, d.bagCount > 0 and 0.82 or 0.3, d.bagCount > 0 and 0 or 0.3, 1)
                    btn.countFS:Show()
                else
                    btn.countFS:Hide()
                end
            end
            btn.buffKey    = d.buffKey
            btn.buffLabel  = d.label
            btn.hasBuff    = d.hasBuff
            btn.timeLeft   = d.timeLeft
            btn.bagCount   = d.bagCount
            btn.weaponSlot = d.weaponSlot
            btn:Show()
        end
    end

    -- Hide leftover icons
    for i = displayIdx + 1, getn(mcOverlayFrame.icons) do
        mcOverlayFrame.icons[i]:Hide()
    end

    -- Recalc frame size based on actually displayed icons
    if displayIdx == 0 then
        mcOverlayFrame:SetWidth(1); mcOverlayFrame:SetHeight(1)
    else
        local actCols  = math.min(displayIdx, perRow)
        local actRows  = math.ceil(displayIdx / perRow)
        local actW     = MC_OVL_PAD * 2 + actCols * iconSz + (actCols - 1) * MC_OVL_GAP
        local actH     = MC_OVL_PAD * 2 + actRows * iconSz + (actRows - 1) * MC_OVL_GAP
        mcOverlayFrame:SetWidth(math.max(actW, 60))
        mcOverlayFrame:SetHeight(actH)
    end

    -- Show/hide drag overlay based on lock state
    if mcOverlayFrame.hitBtn then
        if unlocked then
            mcOverlayFrame.hitBtn:Show()
        else
            mcOverlayFrame.hitBtn:Hide()
        end
    end
end

-- ============================================================
-- Spec binding: auto-switch profile on spec change (first login only, not reload)
-- ============================================================
local mcLastBoundSpec = nil
local mcIsFirstLogin  = true  -- true until first PLAYER_LOGIN, then false on reload

-- Detect first login vs reload: PLAYER_LOGIN fires once per session.
-- On /reload, PLAYER_ENTERING_WORLD fires but PLAYER_LOGIN does NOT fire again
-- if we already consumed it. We use a dedicated frame for this.
local mcLoginFrame = CreateFrame("Frame")
mcLoginFrame:RegisterEvent("PLAYER_LOGIN")
mcLoginFrame:SetScript("OnEvent", function()
    mcIsFirstLogin = true
    mcLoginFrame:UnregisterEvent("PLAYER_LOGIN")
end)

-- Called from home.lua via AmptieRaidTools_RefreshSpecInBackground every 5s
function ART_MC_OnSpecChanged(spec)
    if not spec or spec == "not specified" then
        mcLastBoundSpec = spec
        return
    end
    if spec == mcLastBoundSpec then return end
    mcLastBoundSpec = spec
    -- Only switch on first login, not on reload/zone change
    if not mcIsFirstLogin then return end
    local s = GetMCDB()
    if not s.specBinding then return end
    -- Check if a profile with this spec name exists
    if s.profiles and s.profiles[spec] then
        s.activeProfile = spec
        mcBagDirty = true
        if mcOverlayFrame and mcOverlayFrame:IsShown() then RefreshMCOverlay() end
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r My Consumes: Auto-profile -> " .. spec)
    end
end

-- After first spec binding fires, mark as no longer first login
-- so zone changes / reloads don't re-trigger
local mcSpecBindDoneFrame = CreateFrame("Frame")
mcSpecBindDoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
local mcEnterWorldCount = 0
mcSpecBindDoneFrame:SetScript("OnEvent", function()
    mcEnterWorldCount = mcEnterWorldCount + 1
    -- First PLAYER_ENTERING_WORLD = login; second+ = reload/zone change
    if mcEnterWorldCount > 1 then
        mcIsFirstLogin = false
    end
end)

-- ============================================================
-- Events + poll
-- ============================================================
local mcPollTimer = 0
local MC_POLL_INTERVAL = 1.0

local mcEventFrame = CreateFrame("Frame", "ART_MC_EventFrame", UIParent)
mcEventFrame:RegisterEvent("PLAYER_AURAS_CHANGED")
mcEventFrame:RegisterEvent("BAG_UPDATE")
mcEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mcEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
mcEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
mcEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
mcEventFrame:SetScript("OnEvent", function()
    local evt = event
    if evt == "PLAYER_REGEN_DISABLED" then
        mcInCombat = true
        MCSetOverlayCombatState(true)
    elseif evt == "PLAYER_REGEN_ENABLED" then
        mcInCombat = false
        MCSetOverlayCombatState(false)
        if mcOverlayFrame and mcOverlayFrame:IsShown() then RefreshMCOverlay() end
    elseif evt == "BAG_UPDATE" then
        mcBagDirty = true
    elseif evt == "PLAYER_ENTERING_WORLD" or evt == "ZONE_CHANGED_NEW_AREA" then
        mcBagDirty = true
        -- Restore overlay on login/reload if it was shown before
        local d = GetMCDB()
        if d.ovlShown and not mcOverlayFrame then CreateMCOverlay() end
        if d.ovlShown and mcOverlayFrame and not mcOverlayFrame:IsShown() then
            mcOverlayFrame:Show()
        end
        if mcOverlayFrame and mcOverlayFrame:IsShown() then RefreshMCOverlay() end
    end
    -- PLAYER_AURAS_CHANGED: handled by poll timer
end)

local mcPollFrame = CreateFrame("Frame", nil, UIParent)
mcPollFrame:SetScript("OnUpdate", function()
    if mcInCombat then return end
    local dt = arg1 or 0
    mcPollTimer = mcPollTimer + dt
    if mcPollTimer >= MC_POLL_INTERVAL then
        mcPollTimer = 0
        if mcOverlayFrame and mcOverlayFrame:IsShown() then
            RefreshMCOverlay()
        end
    end
end)

-- ============================================================
-- Settings panel
-- ============================================================
function AmptieRaidTools_InitMyConsumes(body)
    local panel = CreateFrame("Frame", "ART_MC_Panel", body)
    panel:SetAllPoints(body)
    panel:Hide()

    local BD = {
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=12,
        insets={left=3,right=3,top=3,bottom=3},
    }
    local function MakeBtn(parent, label, w, h)
        local b = CreateFrame("Button", nil, parent)
        b:SetWidth(w or 80); b:SetHeight(h or 22)
        b:SetBackdrop(BD)
        b:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
        b:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetAllPoints(b); fs:SetJustifyH("CENTER"); fs:SetText(label or "")
        b.label = fs
        return b
    end

    local s = GetMCDB()

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
    title:SetText("My Consumes")
    title:SetTextColor(1, 0.82, 0, 1)

    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("Track your personal consumables and use them with one click.")
    sub:SetTextColor(0.65, 0.65, 0.7, 1)

    local div1 = panel:CreateTexture(nil, "ARTWORK")
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -6)
    div1:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, 0)
    div1:SetTexture(0.25, 0.25, 0.28, 0.8)

    -- ── General Options (left column) ────────────────────────
    local genHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    genHdr:SetPoint("TOPLEFT", div1, "BOTTOMLEFT", 0, -10)
    genHdr:SetText("General Options")
    genHdr:SetTextColor(0.9, 0.75, 0.2, 1)

    local ROW_H = -6

    -- Icon Size slider
    local szLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    szLbl:SetPoint("TOPLEFT", genHdr, "BOTTOMLEFT", 0, -8)
    szLbl:SetTextColor(0.8, 0.8, 0.85, 1)
    szLbl:SetText("Icon Size: " .. s.ovlIconSize)

    local szSl = CreateFrame("Slider", "ART_MC_SzSlider", panel)
    szSl:SetWidth(120); szSl:SetHeight(14)
    szSl:SetPoint("LEFT", szLbl, "RIGHT", 10, 0)
    szSl:SetOrientation("HORIZONTAL")
    szSl:SetMinMaxValues(20, 64); szSl:SetValueStep(2); szSl:SetValue(s.ovlIconSize)
    local szTh = szSl:CreateTexture(nil, "OVERLAY")
    szTh:SetWidth(10); szTh:SetHeight(14); szTh:SetTexture(0.5, 0.5, 0.55, 0.9)
    szSl:SetThumbTexture(szTh)
    local szTr = szSl:CreateTexture(nil, "BACKGROUND")
    szTr:SetAllPoints(szSl); szTr:SetTexture(0.12, 0.12, 0.15, 0.8)
    szSl:SetScript("OnValueChanged", function()
        local v = floor(this:GetValue())
        GetMCDB().ovlIconSize = v
        szLbl:SetText("Icon Size: " .. v)
        if mcOverlayFrame and mcOverlayFrame:IsShown() then RefreshMCOverlay() end
    end)

    -- Icons per Row
    local prLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    prLbl:SetPoint("TOPLEFT", szLbl, "BOTTOMLEFT", 0, -8)
    prLbl:SetTextColor(0.8, 0.8, 0.85, 1)
    prLbl:SetText("Icons Per Row: " .. s.ovlPerRow)

    local prSl = CreateFrame("Slider", "ART_MC_PrSlider", panel)
    prSl:SetWidth(120); prSl:SetHeight(14)
    prSl:SetPoint("LEFT", prLbl, "RIGHT", 10, 0)
    prSl:SetOrientation("HORIZONTAL")
    prSl:SetMinMaxValues(1, 16); prSl:SetValueStep(1); prSl:SetValue(s.ovlPerRow)
    local prTh = prSl:CreateTexture(nil, "OVERLAY")
    prTh:SetWidth(10); prTh:SetHeight(14); prTh:SetTexture(0.5, 0.5, 0.55, 0.9)
    prSl:SetThumbTexture(prTh)
    local prTr = prSl:CreateTexture(nil, "BACKGROUND")
    prTr:SetAllPoints(prSl); prTr:SetTexture(0.12, 0.12, 0.15, 0.8)
    prSl:SetScript("OnValueChanged", function()
        local v = floor(this:GetValue())
        GetMCDB().ovlPerRow = v
        prLbl:SetText("Icons Per Row: " .. v)
        if mcOverlayFrame and mcOverlayFrame:IsShown() then RefreshMCOverlay() end
    end)

    -- Show / Lock buttons
    local showBtn = MakeBtn(panel, "Show Overlay", 110, 22)
    showBtn:SetPoint("TOPLEFT", prLbl, "BOTTOMLEFT", 0, -10)

    local lockBtn = MakeBtn(panel, "Lock Overlay", 110, 22)
    lockBtn:SetPoint("LEFT", showBtn, "RIGHT", 6, 0)

    local function UpdateShowBtn()
        if mcOverlayFrame and mcOverlayFrame:IsShown() then
            showBtn.label:SetText("Hide Overlay")
            showBtn:SetBackdropColor(0.22, 0.17, 0.03, 0.95)
            showBtn:SetBackdropBorderColor(1, 0.82, 0, 1)
            showBtn.label:SetTextColor(1, 0.82, 0, 1)
        else
            showBtn.label:SetText("Show Overlay")
            showBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
            showBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
            showBtn.label:SetTextColor(0.85, 0.85, 0.85, 1)
        end
    end
    local function UpdateLockBtn()
        local d = GetMCDB()
        if d.ovlLocked then
            lockBtn.label:SetText("Locked")
            lockBtn:SetBackdropBorderColor(1, 0.3, 0.3, 1)
            lockBtn.label:SetTextColor(1, 0.3, 0.3, 1)
        else
            lockBtn.label:SetText("Unlocked")
            lockBtn:SetBackdropBorderColor(0.3, 1, 0.3, 1)
            lockBtn.label:SetTextColor(0.3, 1, 0.3, 1)
        end
    end

    showBtn:SetScript("OnClick", function()
        local d = GetMCDB()
        if not mcOverlayFrame then CreateMCOverlay() end
        if mcOverlayFrame:IsShown() then
            d.ovlShown = false; mcOverlayFrame:Hide()
        else
            d.ovlShown = true; mcOverlayFrame:Show()
            mcBagDirty = true; RefreshMCOverlay()
        end
        UpdateShowBtn()
    end)
    lockBtn:SetScript("OnClick", function()
        local d = GetMCDB()
        d.ovlLocked = not d.ovlLocked
        UpdateLockBtn()
        if mcOverlayFrame and mcOverlayFrame:IsShown() then
            mcBagDirty = true
            RefreshMCOverlay()
        end
    end)

    -- Spec binding checkbox
    local cbSpecBind = ART_CreateCheckbox(panel, "Activate Spec Bindings")
    cbSpecBind:SetPoint("TOPLEFT", showBtn, "BOTTOMLEFT", 0, -10)
    cbSpecBind:SetChecked(s.specBinding)
    cbSpecBind.userOnClick = function()
        GetMCDB().specBinding = cbSpecBind:GetChecked() and true or false
    end

    -- ── Buff active / reappear modes ─────────────────────────
    local div2 = panel:CreateTexture(nil, "ARTWORK")
    div2:SetHeight(1)
    div2:SetPoint("TOPLEFT", cbSpecBind, "BOTTOMLEFT", 0, -10)
    div2:SetPoint("RIGHT", panel, "LEFT", 280, 0)
    div2:SetTexture(0.25, 0.25, 0.28, 0.5)

    -- Active mode
    local actLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    actLbl:SetPoint("TOPLEFT", div2, "BOTTOMLEFT", 0, -8)
    actLbl:SetText("When buff active:")
    actLbl:SetTextColor(0.8, 0.8, 0.85, 1)

    local ACT_MODES = { "none", "disappear", "grey" }
    local actBtn = MakeBtn(panel, s.activeMode, 90, 20)
    actBtn:SetPoint("LEFT", actLbl, "RIGHT", 8, 0)
    actBtn:SetScript("OnClick", function()
        local d = GetMCDB()
        for i = 1, 3 do
            if ACT_MODES[i] == d.activeMode then
                d.activeMode = ACT_MODES[math.mod(i, 3) + 1]
                break
            end
        end
        actBtn.label:SetText(d.activeMode)
        if mcOverlayFrame and mcOverlayFrame:IsShown() then RefreshMCOverlay() end
    end)

    -- Reappear mode
    local reapLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reapLbl:SetPoint("TOPLEFT", actLbl, "BOTTOMLEFT", 0, -8)
    reapLbl:SetText("Reappear at (sec):")
    reapLbl:SetTextColor(0.8, 0.8, 0.85, 1)

    local reapEdit = CreateFrame("EditBox", "ART_MC_ReapEdit", panel)
    reapEdit:SetPoint("LEFT", reapLbl, "RIGHT", 8, 0)
    reapEdit:SetWidth(50); reapEdit:SetHeight(20)
    reapEdit:SetAutoFocus(false); reapEdit:SetMaxLetters(5)
    reapEdit:SetFontObject(GameFontHighlight)
    reapEdit:SetTextInsets(4, 4, 0, 0)
    reapEdit:SetBackdrop(BD)
    reapEdit:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    reapEdit:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    reapEdit:SetText(tostring(s.reappearSec))
    reapEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    reapEdit:SetScript("OnEnterPressed", function()
        local v = tonumber(this:GetText()) or 0
        GetMCDB().reappearSec = v
        this:ClearFocus()
    end)

    local REAP_MODES = { "none", "grey", "red" }
    local reapModeBtn = MakeBtn(panel, s.reappearMode, 70, 20)
    reapModeBtn:SetPoint("LEFT", reapEdit, "RIGHT", 6, 0)
    reapModeBtn:SetScript("OnClick", function()
        local d = GetMCDB()
        for i = 1, 3 do
            if REAP_MODES[i] == d.reappearMode then
                d.reappearMode = REAP_MODES[math.mod(i, 3) + 1]
                break
            end
        end
        reapModeBtn.label:SetText(d.reappearMode)
        if mcOverlayFrame and mcOverlayFrame:IsShown() then RefreshMCOverlay() end
    end)

    -- ── Rules panel (right side) ─────────────────────────────
    local LEFT_W = 290
    local RIGHT_X = LEFT_W + 10
    local PANEL_TOP_Y = -52

    local rulesPanel = CreateFrame("Frame", nil, panel)
    rulesPanel:SetPoint("TOPLEFT", panel, "TOPLEFT", RIGHT_X, PANEL_TOP_Y)
    rulesPanel:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -8, -522)

    local RefreshRuleList  -- forward declaration

    local rulesHdr = rulesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rulesHdr:SetPoint("TOPLEFT", rulesPanel, "TOPLEFT", 0, 0)
    rulesHdr:SetTextColor(0.9, 0.75, 0.2, 1)

    -- Profile dropdown
    local profEdit = CreateFrame("EditBox", "ART_MC_ProfEdit", rulesPanel)
    profEdit:SetPoint("TOPLEFT", rulesHdr, "BOTTOMLEFT", 0, -6)
    profEdit:SetWidth(120); profEdit:SetHeight(22)
    profEdit:SetAutoFocus(false); profEdit:SetMaxLetters(30)
    profEdit:SetFontObject(GameFontHighlight)
    profEdit:SetTextInsets(6, 6, 0, 0)
    profEdit:SetBackdrop(BD)
    profEdit:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    profEdit:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    profEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    -- Profile dropdown arrow
    local profDdBtn = CreateFrame("Button", nil, rulesPanel)
    profDdBtn:SetPoint("LEFT", profEdit, "RIGHT", 2, 0)
    profDdBtn:SetWidth(20); profDdBtn:SetHeight(20)
    profDdBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    profDdBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    profDdBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    local profDdList = CreateFrame("Frame", "ART_MC_ProfDD", UIParent)
    if ART_RegisterPopup then ART_RegisterPopup(profDdList) end
    profDdList:SetFrameStrata("TOOLTIP")
    profDdList:SetWidth(140)
    profDdList:SetBackdrop(BD)
    profDdList:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
    profDdList:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    profDdList:Hide()
    local profDdItems = {}

    local function ProfDDRefresh()
        for pi = 1, getn(profDdItems) do profDdItems[pi]:Hide() end
        local d = GetMCDB()
        local row2 = 0
        for name, _ in pairs(d.profiles) do
            row2 = row2 + 1
            local item = profDdItems[row2]
            if not item then
                item = CreateFrame("Button", nil, profDdList)
                item:SetHeight(20)
                item:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", tile=true, tileSize=16, edgeSize=0, insets={left=0,right=0,top=0,bottom=0} })
                item:SetBackdropColor(0, 0, 0, 0)
                local ifs = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                ifs:SetPoint("LEFT", item, "LEFT", 6, 0)
                item.fs = ifs
                item:SetScript("OnEnter", function() this:SetBackdropColor(0.22, 0.22, 0.28, 0.9) end)
                item:SetScript("OnLeave", function() this:SetBackdropColor(0, 0, 0, 0) end)
                tinsert(profDdItems, item)
            end
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", profDdList, "TOPLEFT", 4, -4 - (row2-1) * 20)
            item:SetPoint("RIGHT", profDdList, "RIGHT", -4, 0)
            item.fs:SetText(name)
            item.fs:SetTextColor(1, 1, 1, 1)
            local capName = name
            item:SetScript("OnClick", function()
                local d2 = GetMCDB()
                d2.activeProfile = capName
                profDdList:Hide()
                RefreshRuleList()
                if mcOverlayFrame and mcOverlayFrame:IsShown() then mcBagDirty = true; RefreshMCOverlay() end
            end)
            item:Show()
        end
        local h = row2 * 20 + 8
        if h < 28 then h = 28 end
        profDdList:SetHeight(h)
        profDdList:ClearAllPoints()
        profDdList:SetPoint("TOPLEFT", profEdit, "BOTTOMLEFT", 0, -2)
        profDdList:Show()
    end

    profDdBtn:SetScript("OnClick", function()
        if profDdList:IsShown() then profDdList:Hide() else ProfDDRefresh() end
    end)

    local saveBtn = MakeBtn(rulesPanel, "Save", 50, 22)
    saveBtn:SetPoint("LEFT", profDdBtn, "RIGHT", 4, 0)

    local delBtn = MakeBtn(rulesPanel, "Delete", 50, 22)
    delBtn:SetPoint("LEFT", saveBtn, "RIGHT", 4, 0)

    local addBtn = MakeBtn(rulesPanel, "+ Add Rule", 90, 22)
    addBtn:SetPoint("TOPRIGHT", rulesPanel, "TOPRIGHT", 0, 0)

    -- Rules scroll area
    local rulesSF = CreateFrame("ScrollFrame", nil, rulesPanel)
    rulesSF:SetPoint("TOPLEFT", profEdit, "BOTTOMLEFT", 0, -4)
    rulesSF:SetPoint("BOTTOMRIGHT", rulesPanel, "BOTTOMRIGHT", 0, 0)

    local rulesContent = CreateFrame("Frame", nil, rulesSF)
    rulesContent:SetWidth(320); rulesContent:SetHeight(1)
    rulesSF:SetScrollChild(rulesContent)

    local rulesScrollOff = 0
    local RULE_ROW_H = 26
    local function SetRulesScroll(val)
        local maxS = math.max(rulesContent:GetHeight() - rulesSF:GetHeight(), 0)
        if val < 0 then val = 0 end
        if val > maxS then val = maxS end
        rulesScrollOff = val
        rulesContent:ClearAllPoints()
        rulesContent:SetPoint("TOPLEFT", rulesSF, "TOPLEFT", 0, val)
    end
    rulesSF:EnableMouseWheel(true)
    rulesSF:SetScript("OnMouseWheel", function()
        SetRulesScroll(rulesScrollOff - arg1 * RULE_ROW_H * 3)
    end)

    local ruleRows = {}

    -- Zone dropdown (shared, shown on click)
    local zoneDdFrame = CreateFrame("Frame", "ART_MC_ZoneDD", UIParent)

    -- Backdrop catch: fullscreen invisible frame behind dropdown, closes on click outside
    local zoneDdCatch = CreateFrame("Frame", nil, UIParent)
    zoneDdCatch:SetAllPoints(UIParent)
    zoneDdCatch:SetFrameStrata("FULLSCREEN_DIALOG")
    zoneDdCatch:EnableMouse(true)
    zoneDdCatch:Hide()
    zoneDdCatch:SetScript("OnMouseDown", function()
        zoneDdCatch:Hide()
        zoneDdFrame:Hide()
    end)
    if ART_RegisterPopup then ART_RegisterPopup(zoneDdFrame) end
    zoneDdFrame:SetFrameStrata("TOOLTIP")
    zoneDdFrame:SetWidth(160)
    zoneDdFrame:SetBackdrop(BD)
    zoneDdFrame:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
    zoneDdFrame:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    zoneDdFrame:Hide()
    zoneDdFrame:EnableMouseWheel(true)
    local zoneDdRows = {}
    local zoneDdRuleIdx = nil

    local function MC_MakeZoneDDRow(idx)
        local zrow = zoneDdRows[idx]
        if not zrow then
            zrow = CreateFrame("Button", nil, zoneDdFrame)
            zrow:SetHeight(18)
            zrow:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", tile=true, tileSize=16, edgeSize=0, insets={left=0,right=0,top=0,bottom=0} })
            zrow:SetBackdropColor(0, 0, 0, 0)
            local zfs = zrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            zfs:SetPoint("LEFT", zrow, "LEFT", 18, 0)
            zrow.fs = zfs
            local zchk = zrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            zchk:SetPoint("LEFT", zrow, "LEFT", 4, 0)
            zrow.chk = zchk
            zrow:SetScript("OnEnter", function() this:SetBackdropColor(0.22, 0.22, 0.28, 0.9) end)
            zrow:SetScript("OnLeave", function() this:SetBackdropColor(0, 0, 0, 0) end)
            zoneDdRows[idx] = zrow
        end
        return zrow
    end

    local function ZoneDDRefresh()
        local prof3 = GetActiveMCProfile()
        if not prof3 or not zoneDdRuleIdx then zoneDdFrame:Hide(); return end
        local rule = prof3.rules[zoneDdRuleIdx]
        if not rule then zoneDdFrame:Hide(); return end
        if not rule.zones then rule.zones = {} end
        local zoneOpts = MC_GetZoneOptions()

        -- Hide all rows first
        for ri = 1, getn(zoneDdRows) do zoneDdRows[ri]:Hide() end

        local rowIdx = 0
        local ROW_H = 18

        -- "All" button
        rowIdx = rowIdx + 1
        local allRow = MC_MakeZoneDDRow(rowIdx)
        allRow:ClearAllPoints()
        allRow:SetPoint("TOPLEFT", zoneDdFrame, "TOPLEFT", 4, -4 - (rowIdx-1)*ROW_H)
        allRow:SetPoint("RIGHT", zoneDdFrame, "RIGHT", -4, 0)
        allRow.fs:SetText("|cFF88FF88Select All|r")
        allRow.chk:SetText("")
        allRow:SetScript("OnClick", function()
            local p = GetActiveMCProfile()
            if not p then return end
            local ru = p.rules[zoneDdRuleIdx]
            if not ru then return end
            -- Set all keys explicitly
            ru.zones = {}
            local zo2 = MC_GetZoneOptions()
            for zi2 = 1, getn(zo2) do ru.zones[zo2[zi2].key] = true end
            ZoneDDRefresh()
            RefreshRuleList()
            if mcOverlayFrame and mcOverlayFrame:IsShown() then RefreshMCOverlay() end
        end)
        allRow:Show()

        -- "None" button
        rowIdx = rowIdx + 1
        local noneRow = MC_MakeZoneDDRow(rowIdx)
        noneRow:ClearAllPoints()
        noneRow:SetPoint("TOPLEFT", zoneDdFrame, "TOPLEFT", 4, -4 - (rowIdx-1)*ROW_H)
        noneRow:SetPoint("RIGHT", zoneDdFrame, "RIGHT", -4, 0)
        noneRow.fs:SetText("|cFFFF8888Clear All|r")
        noneRow.chk:SetText("")
        noneRow:SetScript("OnClick", function()
            local p = GetActiveMCProfile()
            if not p then return end
            local ru = p.rules[zoneDdRuleIdx]
            if not ru then return end
            ru.zones = {}
            ZoneDDRefresh()
            RefreshRuleList()
            if mcOverlayFrame and mcOverlayFrame:IsShown() then RefreshMCOverlay() end
        end)
        noneRow:Show()

        -- Zone rows
        for zi = 1, getn(zoneOpts) do
            local zo = zoneOpts[zi]
            rowIdx = rowIdx + 1
            local zrow = MC_MakeZoneDDRow(rowIdx)
            zrow:ClearAllPoints()
            zrow:SetPoint("TOPLEFT", zoneDdFrame, "TOPLEFT", 4, -4 - (rowIdx-1)*ROW_H)
            zrow:SetPoint("RIGHT", zoneDdFrame, "RIGHT", -4, 0)
            zrow.fs:SetText(zo.label)
            local isAll = (rule.zones == nil)
            local checked = isAll or (rule.zones and rule.zones[zo.key])
            zrow.chk:SetText(checked and "|cFF00FF00+|r" or "|cFF666666-|r")
            local captZKey = zo.key
            zrow:SetScript("OnClick", function()
                local p = GetActiveMCProfile()
                if not p then return end
                local ru = p.rules[zoneDdRuleIdx]
                if not ru then return end
                -- If zones is nil (= all), expand to explicit table first
                if not ru.zones then
                    ru.zones = {}
                    local zo3 = MC_GetZoneOptions()
                    for zi3 = 1, getn(zo3) do ru.zones[zo3[zi3].key] = true end
                end
                ru.zones[captZKey] = not ru.zones[captZKey] or nil
                ZoneDDRefresh()
                RefreshRuleList()
                if mcOverlayFrame and mcOverlayFrame:IsShown() then RefreshMCOverlay() end
            end)
            zrow:Show()
        end
        zoneDdFrame:SetHeight(rowIdx * ROW_H + 8)
    end

    -- Count active zones for display
    local function ZoneSummary(zones)
        if not zones then return "|cFF88FF88all|r" end
        local cnt = 0
        for _ in pairs(zones) do cnt = cnt + 1 end
        if cnt == 0 then return "|cFFFF8888none|r" end
        -- Check if all zone options are selected
        local totalOpts = getn(MC_GetZoneOptions())
        if cnt >= totalOpts then return "|cFF88FF88all|r" end
        if cnt == 1 then
            local zoneOpts = MC_GetZoneOptions()
            for k in pairs(zones) do
                for zi = 1, getn(zoneOpts) do
                    if zoneOpts[zi].key == k then return zoneOpts[zi].label end
                end
                return k
            end
        end
        return cnt .. " zones"
    end

    RefreshRuleList = function()
        local d = GetMCDB()
        rulesHdr:SetText("Rules  —  " .. (d.activeProfile or "--"))
        profEdit:SetText(d.activeProfile or "")
        local prof2 = GetActiveMCProfile()
        local rules = prof2 and prof2.rules or {}
        for i = 1, getn(ruleRows) do ruleRows[i]:Hide() end
        for i = 1, getn(rules) do
            local r = rules[i]
            local row = ruleRows[i]
            if not row then
                row = CreateFrame("Frame", nil, rulesContent)
                row:SetHeight(RULE_ROW_H); row:SetWidth(320)
                row:EnableMouse(false)
                local iconTex = row:CreateTexture(nil, "ARTWORK")
                iconTex:SetWidth(18); iconTex:SetHeight(18)
                iconTex:SetPoint("LEFT", row, "LEFT", 2, 0)
                row.iconTex = iconTex
                local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                nameFS:SetPoint("LEFT", iconTex, "RIGHT", 4, 0)
                nameFS:SetWidth(120); nameFS:SetJustifyH("LEFT")
                row.nameFS = nameFS
                -- Zone button
                local zoneBtn = MakeBtn(row, "all", 80, 18)
                zoneBtn:SetPoint("LEFT", nameFS, "RIGHT", 4, 0)
                zoneBtn:SetFrameLevel(row:GetFrameLevel() + 2)
                row.zoneBtn = zoneBtn
                -- Weapon slot toggle (MH/OH) — only shown for weapon buffs
                local wSlotBtn = MakeBtn(row, "MH", 30, 18)
                wSlotBtn:SetPoint("LEFT", zoneBtn, "RIGHT", 4, 0)
                wSlotBtn:SetFrameLevel(row:GetFrameLevel() + 2)
                wSlotBtn:Hide()
                row.wSlotBtn = wSlotBtn
                -- Delete button
                local delR = CreateFrame("Button", nil, row)
                delR:SetWidth(20); delR:SetHeight(20)
                delR:SetPoint("LEFT", wSlotBtn, "RIGHT", 4, 0)
                delR:SetFrameLevel(row:GetFrameLevel() + 2)
                local delFS = delR:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                delFS:SetAllPoints(delR); delFS:SetJustifyH("CENTER")
                delFS:SetText("|cFFFF4444X|r")
                delR:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
                delR.label = delFS
                row.delBtn = delR
                tinsert(ruleRows, row)
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", rulesContent, "TOPLEFT", 0, -(i-1) * RULE_ROW_H)
            row:SetPoint("RIGHT", rulesContent, "RIGHT", 0, 0)
            local bcBuff = ART_BC_BY_KEY_ALL and ART_BC_BY_KEY_ALL[r.buffKey]
            row.iconTex:SetTexture(bcBuff and bcBuff.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.nameFS:SetText(bcBuff and bcBuff.name or r.buffKey)
            row.zoneBtn.label:SetText(ZoneSummary(r.zones))
            -- Weapon slot toggle
            local isWeapon = bcBuff and bcBuff.sec == "weapon" and not bcBuff.spellCast
            row.delBtn:ClearAllPoints()
            if isWeapon then
                local ws = r.weaponSlot or "MH"
                row.wSlotBtn.label:SetText(ws)
                row.wSlotBtn.label:SetTextColor(ws == "MH" and 0.4 or 0.7, ws == "MH" and 0.8 or 0.5, ws == "MH" and 1 or 1, 1)
                row.wSlotBtn:Show()
                row.delBtn:SetPoint("LEFT", row.wSlotBtn, "RIGHT", 4, 0)
            else
                row.wSlotBtn:Hide()
                row.delBtn:SetPoint("LEFT", row.zoneBtn, "RIGHT", 4, 0)
            end
            local captIdx = i
            row.wSlotBtn:SetScript("OnClick", function()
                local prof3 = GetActiveMCProfile()
                if not prof3 then return end
                local rule = prof3.rules[captIdx]
                if not rule then return end
                rule.weaponSlot = (rule.weaponSlot == "MH") and "OH" or "MH"
                RefreshRuleList()
                if mcOverlayFrame and mcOverlayFrame:IsShown() then RefreshMCOverlay() end
            end)
            row.delBtn:SetScript("OnClick", function()
                local prof3 = GetActiveMCProfile()
                if prof3 then table.remove(prof3.rules, captIdx) end
                zoneDdFrame:Hide(); zoneDdCatch:Hide()
                RefreshRuleList()
                if mcOverlayFrame and mcOverlayFrame:IsShown() then mcBagDirty = true; RefreshMCOverlay() end
            end)
            row.zoneBtn:SetScript("OnClick", function()
                if zoneDdFrame:IsShown() and zoneDdRuleIdx == captIdx then
                    zoneDdFrame:Hide()
                    zoneDdCatch:Hide()
                    return
                end
                zoneDdRuleIdx = captIdx
                ZoneDDRefresh()
                zoneDdFrame:ClearAllPoints()
                zoneDdFrame:SetPoint("TOPLEFT", this, "BOTTOMLEFT", 0, -2)
                zoneDdCatch:Show()
                zoneDdFrame:Show()
            end)
            row:Show()
        end
        rulesContent:SetHeight(math.max(getn(rules) * RULE_ROW_H, 1))
    end

    -- Save profile
    saveBtn:SetScript("OnClick", function()
        local name = profEdit:GetText()
        if not name or name == "" then return end
        local d = GetMCDB()
        -- Copy current profile rules to new name
        local cur = GetActiveMCProfile()
        local newRules = {}
        if cur then
            for i = 1, getn(cur.rules) do
                local r = cur.rules[i]
                local zonesCopy = {}
                if r.zones then for k, v in pairs(r.zones) do zonesCopy[k] = v end end
                tinsert(newRules, { buffKey=r.buffKey, zones=zonesCopy, reappearOverride=r.reappearOverride, weaponSlot=r.weaponSlot })
            end
        end
        d.profiles[name] = { rules = newRules }
        d.activeProfile = name
        RefreshRuleList()
    end)

    -- Delete profile (only custom profiles, not built-in)
    delBtn:SetScript("OnClick", function()
        local name = profEdit:GetText()
        if not name or name == "" then return end
        if MC_IsBuiltinProfile(name) then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[aRT]|r Cannot delete built-in profile: " .. name)
            return
        end
        local d = GetMCDB()
        d.profiles[name] = nil
        d.activeProfile = "Default"
        RefreshRuleList()
        if mcOverlayFrame and mcOverlayFrame:IsShown() then mcBagDirty = true; RefreshMCOverlay() end
    end)

    -- Add Rule: buff picker dropdown
    local ddFrame = CreateFrame("Frame", "ART_MC_BuffDD", UIParent)
    if ART_RegisterPopup then ART_RegisterPopup(ddFrame) end
    ddFrame:SetFrameStrata("TOOLTIP")
    ddFrame:SetWidth(200)
    ddFrame:SetBackdrop(BD)
    ddFrame:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
    ddFrame:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    ddFrame:Hide()
    ddFrame:EnableMouseWheel(true)

    local DD_MAX_VIS = 12
    local DD_ROW_H   = 20
    local ddRows     = {}
    local ddScrollOff = 0
    local ddAllItems  = {}

    local function DDRefresh()
        for i = 1, getn(ddRows) do ddRows[i]:Hide() end
        local vis = getn(ddAllItems) - ddScrollOff
        if vis > DD_MAX_VIS then vis = DD_MAX_VIS end
        for i = 1, vis do
            local item = ddAllItems[i + ddScrollOff]
            local row = ddRows[i]
            if not row then
                row = CreateFrame("Button", nil, ddFrame)
                row:SetHeight(DD_ROW_H)
                row:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", tile=true, tileSize=16, edgeSize=0, insets={left=0,right=0,top=0,bottom=0} })
                row:SetBackdropColor(0, 0, 0, 0)
                local rfs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                rfs:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.fs = rfs
                row:SetScript("OnEnter", function()
                    if this.isHeader then return end
                    this:SetBackdropColor(0.22, 0.22, 0.28, 0.9)
                end)
                row:SetScript("OnLeave", function() this:SetBackdropColor(0, 0, 0, 0) end)
                tinsert(ddRows, row)
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", ddFrame, "TOPLEFT", 4, -4 - (i-1)*DD_ROW_H)
            row:SetPoint("RIGHT", ddFrame, "RIGHT", -4, 0)
            row:SetBackdropColor(0, 0, 0, 0)
            if item.isHeader then
                row.fs:SetText("|cFFFFCC00" .. item.name .. "|r")
                row.isHeader = true
                row.buffKey = nil
                row:SetScript("OnClick", nil)
            else
                row.fs:SetText("  " .. item.name)
                row.isHeader = false
                row.buffKey = item.key
                row:SetScript("OnClick", function()
                    if this.isHeader then return end
                    local prof3 = GetActiveMCProfile()
                    if prof3 then
                        local newRule = { buffKey = this.buffKey, zones = nil, reappearOverride = nil }
                    -- Default weapon slot for weapon buffs
                    local nb = ART_BC_BY_KEY_ALL and ART_BC_BY_KEY_ALL[this.buffKey]
                    if nb and nb.sec == "weapon" then newRule.weaponSlot = "MH" end
                    tinsert(prof3.rules, newRule)
                        RefreshRuleList()
                        if mcOverlayFrame and mcOverlayFrame:IsShown() then mcBagDirty = true; RefreshMCOverlay() end
                    end
                    ddFrame:Hide()
                end)
            end
            row:Show()
        end
        local h = math.min(vis, DD_MAX_VIS) * DD_ROW_H + 8
        if h < 28 then h = 28 end
        ddFrame:SetHeight(h)
    end

    ddFrame:SetScript("OnMouseWheel", function()
        ddScrollOff = ddScrollOff - arg1
        if ddScrollOff < 0 then ddScrollOff = 0 end
        local maxOff = getn(ddAllItems) - DD_MAX_VIS
        if maxOff < 0 then maxOff = 0 end
        if ddScrollOff > maxOff then ddScrollOff = maxOff end
        DDRefresh()
    end)

    -- Category mapping for dropdown sorting
    local MC_EXCLUDE = {
        FREE_ACTION=true, RESTORATIVE=true, LTD_INVULN=true, SWIFTNESS=true,
        GR_STONESHIELD=true, LESSER_INVIS=true, INVISIBILITY=true,
        MAGIC_RES=true, ELX_POISON_RES=true, INVIS_POTION=true,
    }
    local MC_CATEGORIES = {
        { header="Flasks",         keys={FLASK_TITANS=true, FLASK_SUP_PWR=true, FLASK_DIST_WIS=true, FLASK_CHROM_RES=true} },
        { header="Zanza",          keys={SPIRIT_ZANZA=true, SHEEN_ZANZA=true, SWIFTNESS_ZANZA=true} },
        { header="Tank",           keys={ELX_FORTITUDE=true, ELX_SUP_DEFENSE=true, RUMSEY_RUM=true, MEDIVH_MERLOT=true,
                                         FOOD_HARDENED_MUSH=true, FOOD_CHIMAEROK=true, FOOD_FISHE_CHOC=true,
                                         FOOD_WILDHAMMER_YAM=true, FOOD_TELABIM_MEDLEY=true, FOOD_SANDSWEPT_SPICY=true,
                                         FOOD_DEEP_SEA_STEW=true, FOOD_GURUBASHI_GUMBO=true} },
        { header="Melee",          keys={ELX_MONGOOSE=true, ELX_GIANTS=true, JUJU_POWER=true, WINTERFALL_FW=true,
                                         JUJU_MIGHT=true, MIGHTY_RAGE=true, ROIDS=true, GROUND_SCORPOK=true,
                                         FOOD_POWER_MUSH=true, FOOD_DESERT_DUMP=true, FOOD_MIGHTFISH=true,
                                         FOOD_GRILLED_SQUID=true, FOOD_SOUR_BERRY=true, FOOD_TELABIM_SURP=true,
                                         FOOD_SANDSWEPT_CRUNCH=true} },
        { header="Caster / Healer", keys={GR_ARCANE_ELX=true, DREAMSHARD_ELX=true, ELX_GR_FIRE_PWR=true,
                                          ELX_SHADOW_PWR=true, ELX_GR_NATURE_PWR=true, ELX_GR_ARCANE_PWR=true,
                                          ELX_GR_FROST_PWR=true, DREAMTONIC=true, MAGEBLOOD=true,
                                          MEDIVH_MERLOT_BLUE=true,
                                          FOOD_NIGHTFIN=true, FOOD_SOUR_GRAPES=true, FOOD_TELABIM_DELIGHT=true,
                                          FOOD_HERBAL_SALAD=true, FOOD_WATERMELON=true, FOOD_RUNN_TUM=true,
                                          FOOD_HOT_BASS=true} },
        { header="Hybrid",         keys={CONCOCTION_ARCANE=true, CONCOCTION_EMERALD=true, CONCOCTION_DREAM=true} },
        { header="Weapon Buffs",   keys={CONSECR_STONE=true, BLESSED_WIZ_OIL=true, ELEM_SHARP_STONE=true,
                                         BRILL_MANA_OIL=true, BRILL_WIZ_OIL=true} },
        { header="Shaman Imbues", keys={WPN_FLAMETONGUE=true, WPN_FROSTBRAND=true, WPN_ROCKBITER=true, WPN_WINDFURY=true} },
        { header="Rogue Poisons", keys={PSN_INSTANT=true, PSN_DEADLY=true, PSN_MINDNUMB=true, PSN_CRIPPLING=true,
                                        PSN_WOUND=true, PSN_DISSOLVENT=true, PSN_CORROSIVE=true, PSN_AGITATING=true} },
    }
    -- Keys assigned to a category
    local MC_CAT_ASSIGNED = {}
    for ci = 1, getn(MC_CATEGORIES) do
        for k in pairs(MC_CATEGORIES[ci].keys) do MC_CAT_ASSIGNED[k] = true end
    end

    addBtn:SetScript("OnClick", function()
        if ddFrame:IsShown() then ddFrame:Hide(); return end
        for k in pairs(ddAllItems) do ddAllItems[k] = nil end
        ddAllItems.n = 0
        if not ART_BC_BUFFS_ALL then return end

        local _, myClass = UnitClass("player")
        myClass = myClass and string.upper(myClass) or ""

        -- Eligible: has itemKey OR isFood OR has itemIds OR has spellCast; respects classReq
        local function mcEligible(b)
            if MC_EXCLUDE[b.key] then return false end
            if b.classReq and b.classReq ~= myClass then return false end
            return b.itemKey or b.isFood or b.itemIds or b.spellCast
        end

        -- Build categorized list (foods always last within each category)
        for ci = 1, getn(MC_CATEGORIES) do
            local cat = MC_CATEGORIES[ci]
            local elixirs = {}
            local foods   = {}
            for i = 1, getn(ART_BC_BUFFS_ALL) do
                local b = ART_BC_BUFFS_ALL[i]
                if mcEligible(b) and cat.keys[b.key] then
                    if b.isFood then tinsert(foods, { key = b.key, name = b.name })
                    else tinsert(elixirs, { key = b.key, name = b.name }) end
                end
            end
            if getn(elixirs) > 0 or getn(foods) > 0 then
                tinsert(ddAllItems, { name = cat.header, isHeader = true })
                for ii = 1, getn(elixirs) do tinsert(ddAllItems, elixirs[ii]) end
                for ii = 1, getn(foods) do tinsert(ddAllItems, foods[ii]) end
            end
        end

        -- Protection Potions: everything not in a category and not excluded
        local miscItems = {}
        for i = 1, getn(ART_BC_BUFFS_ALL) do
            local b = ART_BC_BUFFS_ALL[i]
            if mcEligible(b) and not MC_CAT_ASSIGNED[b.key] then
                tinsert(miscItems, { key = b.key, name = b.name })
            end
        end
        if getn(miscItems) > 0 then
            tinsert(ddAllItems, { name = "Protection Potions", isHeader = true })
            for ii = 1, getn(miscItems) do tinsert(ddAllItems, miscItems[ii]) end
        end

        ddScrollOff = 0
        DDRefresh()
        ddFrame:ClearAllPoints()
        ddFrame:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", 0, -2)
        ddFrame:Show()
    end)

    -- OnShow
    panel:SetScript("OnShow", function()
        local d = GetMCDB()
        if d.ovlShown then
            if not mcOverlayFrame then CreateMCOverlay() end
            mcOverlayFrame:Show()
            mcBagDirty = true
            RefreshMCOverlay()
        end
        UpdateShowBtn()
        UpdateLockBtn()
        RefreshRuleList()
    end)

    AmptieRaidTools_RegisterComponent("myconsumes", panel)
end
