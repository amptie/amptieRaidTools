-- amptieRaidTools - QoL Settings (Vanilla 1.12 / Lua 5.0)

local getn    = table.getn
local tinsert = table.insert
local floor   = math.floor
local strfind = string.find

-- ============================================================
-- Database defaults
-- ============================================================
local QOL_DEFAULTS = {
    GINV         = false,  -- Accept invites from guild mates
    FINV         = false,  -- Accept invites from friends
    SINV         = false,  -- Accept invites from strangers
    DINV         = false,  -- Accept invites when idle in BG or queue
    EBG          = false,  -- Auto enter battleground
    LBG          = false,  -- Auto leave battleground when battle ends
    QBG          = false,  -- Re-queue after leaving BG
    RBG          = false,  -- Auto release in BG
    AQUE         = false,  -- Leader queue announce
    SBG          = false,  -- Block BG quest sharing
    WORLDDUNGEON = false,  -- Mute world chat in dungeons
    WORLDRAID    = false,  -- Mute world chat in raids
    WORLDBG      = false,  -- Mute world chat in battlegrounds
    WORLDUNCHECK = false,  -- Mute world chat permanently
    SUMM         = false,  -- Auto accept summon
    RIGHT        = false,  -- Improved right click (item into trade/mail/AH)
    SHIFTSPLIT   = false,  -- Easy stack split/merge with Shift+click
    CAM          = false,  -- Extended camera distance
    DUEL         = false,  -- Auto decline duels
    REZ          = false,  -- Auto accept instance resurrection
    GOSSIP       = false,  -- Auto process gossip (single option)
    DISMOUNT     = false,  -- Auto dismount on action
    AUTOSTANCE   = false,  -- Auto stance on action
    QUESTREPEAT  = false,  -- Quest Repeat with CTRL
}

local function GetQolDB()
    local db = amptieRaidToolsDB
    if not db.qolSettings then db.qolSettings = {} end
    local s = db.qolSettings
    for k, v in pairs(QOL_DEFAULTS) do
        if s[k] == nil then s[k] = v end
    end
    return s
end

local function QDB(key)
    return GetQolDB()[key]
end

-- ============================================================
-- Zone / instance helpers
-- ============================================================
local function QoL_IsInBG()
    local zone = GetRealZoneText()
    if not zone then return false end
    return (strfind(zone, "Alterac Valley") or strfind(zone, "Warsong Gulch") or
            strfind(zone, "Arathi Basin") or strfind(zone, "Eye of the Storm") or
            strfind(zone, "Strand of the Ancients") or strfind(zone, "Isle of Conquest"))
            and true or false
end

local function QoL_IsDungeon()
    return GetBindingText and false or false  -- checked via GetRealZoneText
end

local function QoL_IsInDungeon()
    local _, instanceType = IsInInstance()
    return instanceType == "party"
end

local function QoL_IsInRaid()
    local _, instanceType = IsInInstance()
    return instanceType == "raid"
end

local function QoL_IsInQueue()
    -- BattlefieldStatus: 1=none,2=queued,3=waiting,4=active
    for i = 1, 3 do
        local status = GetBattlefieldStatus(i)
        if status == "queued" or status == "confirm" then return true end
    end
    return false
end

local function QoL_IsFriend(name)
    if not name then return false end
    for i = 1, GetNumFriends() do
        local fn = GetFriendInfo(i)
        if fn == name then return true end
    end
    return false
end

local function QoL_IsGuildMate(name)
    if not name then return false end
    for i = 1, GetNumGuildMembers() do
        local gn = GetGuildRosterInfo(i)
        if gn == name then return true end
    end
    return false
end

-- ============================================================
-- Dismount helper (hidden tooltip trick)
-- ============================================================
local qolTipFrame = CreateFrame("GameTooltip", "ART_QoL_Tip", UIParent, "GameTooltipTemplate")
qolTipFrame:SetOwner(UIParent, "ANCHOR_NONE")

local function QoL_Dismount()
    local playerName = UnitName("player")
    for i = 1, 40 do
        local buffName, _, _, _, _, _, _, isStealable = UnitBuff("player", i)
        if not buffName then break end
        qolTipFrame:SetUnitBuff("player", i)
        local line = ART_QoL_TipTextLeft1
        if line then
            local txt = line:GetText()
            if txt and (strfind(txt, "Mount") or strfind(txt, "Riding") or strfind(txt, "Swift") or
                        strfind(txt, "Steed") or strfind(txt, "Charger") or strfind(txt, "Raptor") or
                        strfind(txt, "Wolf") or strfind(txt, "Gryphon") or strfind(txt, "Wyvern") or
                        strfind(txt, "Ram") or strfind(txt, "Kodo") or strfind(txt, "Mechanostrider") or
                        strfind(txt, "Frostsaber") or strfind(txt, "Nightsaber") or strfind(txt, "Skeletal") or
                        strfind(txt, "Tiger") or strfind(txt, "Stormpike") or strfind(txt, "Dreadsteed") or
                        strfind(txt, "Felsteed")) then
                CancelPlayerBuff(i - 1)
                return
            end
        end
    end
end

-- ============================================================
-- World Chat Mute
-- ============================================================
local worldChatMuted = false
local worldChatChannels = {}

local function QoL_SaveWorldChannels()
    for k in pairs(worldChatChannels) do worldChatChannels[k] = nil end
    worldChatChannels.n = 0
    for i = 1, 10 do
        local idx, name = GetChannelName(i)
        if name and name ~= "" then
            local lower = string.lower(name)
            if strfind(lower, "world") or strfind(lower, "trade") or
               strfind(lower, "local") or strfind(lower, "general") then
                tinsert(worldChatChannels, { idx = idx, name = name })
            end
        end
    end
end

local function QoL_MuteWorldChat()
    QoL_SaveWorldChannels()
    for i = 1, getn(worldChatChannels) do
        ChatFrame_RemoveChannel(ChatFrame1, worldChatChannels[i].name)
    end
    worldChatMuted = true
end

local function QoL_UnmuteWorldChat()
    for i = 1, getn(worldChatChannels) do
        ChatFrame_AddChannel(ChatFrame1, worldChatChannels[i].name)
    end
    worldChatMuted = false
end

local function QoL_ZoneCheck()
    local db = GetQolDB()
    local shouldMute = db.WORLDUNCHECK
    if not shouldMute and db.WORLDBG   and QoL_IsInBG()      then shouldMute = true end
    if not shouldMute and db.WORLDRAID and QoL_IsInRaid()     then shouldMute = true end
    if not shouldMute and db.WORLDDUNGEON and QoL_IsInDungeon() then shouldMute = true end

    if shouldMute and not worldChatMuted then
        QoL_MuteWorldChat()
    elseif not shouldMute and worldChatMuted then
        QoL_UnmuteWorldChat()
    end
end

-- Quest Repeat shared state (declared here so QoL_HandleGossip can access it)
local qrData = { quest = nil, item = nil }

-- ============================================================
-- Camera distance
-- ============================================================
local function QoL_RefreshCamera()
    if QDB("CAM") then
        SetCVar("cameraDistanceMax", "50")
    end
end

-- ============================================================
-- Gossip auto-select
-- ============================================================
local function QoL_HandleGossip()
    -- QUESTREPEAT: find the remembered quest in gossip buttons and click it
    if QDB("QUESTREPEAT") and IsControlKeyDown() and qrData.quest then
        for i = 1, NUMGOSSIPBUTTONS do
            local btn = getglobal("GossipTitleButton" .. i)
            if btn and btn:IsVisible() and btn:GetText() == qrData.quest then
                btn:Click()
                return
            end
        end
        -- Quest not found in gossip → reset so we don't loop forever
        qrData.quest = nil
        qrData.item  = nil
        return
    end

    -- GOSSIP auto-select: single non-interactive option
    if not QDB("GOSSIP") then return end
    local opts = { GetGossipOptions() }
    -- GetGossipOptions returns alternating text, type pairs
    local numOptions = getn(opts) / 2
    if numOptions == 1 then
        local gossipType = opts[2]
        if gossipType ~= "vendor" and gossipType ~= "trainer" and gossipType ~= "taxi" then
            SelectGossipOption(1)
        end
    end
end

-- ============================================================
-- Item-to-trade helper (right click)
-- ============================================================
local function QoL_ItemIsTradeable(bag, slot)
    qolTipFrame:SetBagItem(bag, slot)
    local itemName = ART_QoL_TipTextLeft1
    if itemName and itemName:GetText() then return true end
    return false
end

-- ============================================================
-- Stack split session state (persists between clicks, resets after 9s)
-- ============================================================
local splitVal      = 1
local splitTimer    = nil
local splitDuration = 9
local splitAltTime  = 0
local splitCtrlTime = 0
local splitLastClick = 0

local splitWatchFrame = CreateFrame("Frame", "ART_QoL_SplitWatch", UIParent)
splitWatchFrame:SetScript("OnUpdate", function()
    if not splitTimer then return end
    local t = GetTime()
    if t > splitTimer then
        splitVal   = 1
        splitTimer = nil
        return
    end
    local alt  = IsAltKeyDown()
    local ctrl = IsControlKeyDown()
    if alt and not ctrl and splitVal < 100 and t > splitAltTime then
        splitVal     = splitVal + 1
        splitAltTime = t + 0.125
        splitTimer   = t + splitDuration
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00CCFF[Split]|r " .. splitVal)
    elseif ctrl and not alt and splitVal > 1 and t > splitCtrlTime then
        splitVal      = splitVal - 1
        splitCtrlTime = t + 0.125
        splitTimer    = t + splitDuration
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00CCFF[Split]|r " .. splitVal)
    end
end)

-- ============================================================
-- UseContainerItem hook (right click + shift split)
-- ============================================================
local _OrigUseContainerItem = UseContainerItem
UseContainerItem = function(bag, slot)
    local db = GetQolDB()

    -- Improved right click: move item into open trade/mail/AH slot.
    -- Skip if LazyPig's RIGHT is active — it handles trade/mail/AH/GMail/CT_Mail
    -- correctly and is already in the _OrigUseContainerItem chain below.
    if db.RIGHT and not (LPCONFIG and LPCONFIG.RIGHT) then
        if TradeFrame and TradeFrame:IsShown() then
            local count = 1
            while count <= 7 do
                if not GetTradePlayerItemLink(count) then
                    ClickTradeButton(count)
                    PickupContainerItem(bag, slot)
                    PlaceTradeItem(count)
                    return
                end
                count = count + 1
            end
        end
        if SendMailFrame and SendMailFrame:IsShown() then
            PickupContainerItem(bag, slot)
            ClickSendMailItemButton()
            if CursorHasItem() then ClearCursor() end
            return
        end
    end

    -- Easy stack split: Shift+right-click, split splitVal items into empty slot
    -- Skip if LazyPig's SHIFTSPLIT is active — defer to its implementation.
    -- Alt held in OnUpdate increases splitVal, Ctrl decreases. Resets after 9s.
    if db.SHIFTSPLIT and not (LPCONFIG and LPCONFIG.SHIFTSPLIT) and IsShiftKeyDown() and not IsAltKeyDown() and not CursorHasItem() then
        local t = GetTime()
        if (t - splitLastClick) < 0.3 then return end
        local _, itemCount, locked = GetContainerItemInfo(bag, slot)
        if not locked and itemCount and itemCount > 1 then
            local count = splitVal
            if count >= itemCount then count = itemCount - 1 end
            if count < 1 then count = 1 end
            local destBag, destSlot
            for b = 0, NUM_BAG_FRAMES do
                for s = 1, GetContainerNumSlots(b) do
                    if not (b == bag and s == slot) and not GetContainerItemLink(b, s) then
                        destBag, destSlot = b, s
                        break
                    end
                end
                if destBag then break end
            end
            if destBag then
                SplitContainerItem(bag, slot, count)
                PickupContainerItem(destBag, destSlot)
                splitLastClick = t
                splitTimer     = t + splitDuration
                return
            end
        end
    end

    _OrigUseContainerItem(bag, slot)
end

-- ============================================================
-- Quest Repeat hooks  (mirrors QuestRepeat addon logic exactly)
-- PostHook pattern: original always runs first so UI elements
-- are fully initialised before we interact with them.
-- ============================================================
local _OrigQuestDetailOnShow   = QuestFrameDetailPanel_OnShow
local _OrigQuestProgressOnShow = QuestFrameProgressPanel_OnShow
local _OrigQuestRewardOnShow   = QuestFrameRewardPanel_OnShow
local _OrigQuestGreetOnShow    = QuestFrameGreetingPanel_OnShow

-- Detail panel: quest offered → save name, accept if CTRL held
QuestFrameDetailPanel_OnShow = function()
    if _OrigQuestDetailOnShow then _OrigQuestDetailOnShow() end
    if not QDB("QUESTREPEAT") then return end
    if QuestTitleText then
        qrData.quest = QuestTitleText:GetText()
    end
    if IsControlKeyDown() then
        AcceptQuest()
    end
end

-- Progress panel: call CompleteQuest() directly — avoids the gold-payment
-- StaticPopup that QuestFrameCompleteButton:Click() triggers internally.
QuestFrameProgressPanel_OnShow = function()
    if _OrigQuestProgressOnShow then _OrigQuestProgressOnShow() end
    if not QDB("QUESTREPEAT") then return end
    if IsControlKeyDown() then
        CompleteQuest()
    end
end

-- Reward panel: call GetQuestReward() directly — avoids relying on
-- QuestRewardCompleteButton_OnClick global which may be nil at load time.
QuestFrameRewardPanel_OnShow = function()
    if _OrigQuestRewardOnShow then _OrigQuestRewardOnShow() end
    if not QDB("QUESTREPEAT") or not IsControlKeyDown() then return end
    local noChoice = QuestFrameRewardPanel.itemChoice == 0
    if noChoice then
        GetQuestReward(0)
    elseif qrData.item then
        QuestFrameRewardPanel.itemChoice = qrData.item
        GetQuestReward(qrData.item)
    end
    -- First time with item choices: player clicks manually; button script below saves it
end

-- Hook reward button frame script directly (safer than global function hook).
-- Saves the player's item choice for future CTRL cycles.
QuestFrameCompleteQuestButton:SetScript("OnClick", function()
    if QDB("QUESTREPEAT") then
        if IsControlKeyDown() and qrData.item then
            QuestFrameRewardPanel.itemChoice = qrData.item
        else
            qrData.item = QuestFrameRewardPanel.itemChoice
            if QuestRewardTitleText then
                qrData.quest = QuestRewardTitleText:GetText()
            end
        end
    end
    -- Always complete the quest (mirrors what the original script does)
    GetQuestReward(QuestFrameRewardPanel.itemChoice or 0)
end)

-- Greeting panel: click the remembered quest's title button directly (same as QuestRepeat)
QuestFrameGreetingPanel_OnShow = function()
    if _OrigQuestGreetOnShow then _OrigQuestGreetOnShow() end
    if not QDB("QUESTREPEAT") then return end
    if IsControlKeyDown() and qrData.quest then
        for i = 1, MAX_NUM_QUESTS do
            local btn = getglobal("QuestTitleButton" .. i)
            if btn and btn:IsVisible() and btn:GetText() == qrData.quest then
                btn:Click()
                return
            end
        end
    else
        -- CTRL released: reset so next session starts fresh
        qrData.quest = nil
        qrData.item  = nil
    end
end

-- ============================================================
-- Main event frame
-- ============================================================
local qolEventFrame = CreateFrame("Frame", "ART_QoL_EventFrame", UIParent)
qolEventFrame:RegisterEvent("PLAYER_LOGIN")
qolEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
qolEventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
qolEventFrame:RegisterEvent("RESURRECT_REQUEST")
qolEventFrame:RegisterEvent("CONFIRM_SUMMON")
qolEventFrame:RegisterEvent("DUEL_REQUESTED")
qolEventFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
qolEventFrame:RegisterEvent("GOSSIP_SHOW")
qolEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
qolEventFrame:RegisterEvent("ZONE_CHANGED")
qolEventFrame:RegisterEvent("SPELL_FAILED_ONLY_SHAPESHIFT")

qolEventFrame:SetScript("OnEvent", function()
    local evt = event
    local a1  = arg1

    if evt == "PLAYER_LOGIN" or evt == "PLAYER_ENTERING_WORLD" then
        QoL_RefreshCamera()
        QoL_ZoneCheck()

    elseif evt == "PARTY_INVITE_REQUEST" then
        local db = GetQolDB()
        local inviterName = a1
        local idle = (not IsInInstance()) or QoL_IsInQueue()
        local accept = false
        if db.GINV and QoL_IsGuildMate(inviterName) then accept = true end
        if db.FINV and QoL_IsFriend(inviterName)    then accept = true end
        if db.SINV then accept = true end
        if db.DINV and idle then accept = true end
        if accept then
            AcceptGroup()
            StaticPopup_Hide("PARTY_INVITE")
        end

    elseif evt == "RESURRECT_REQUEST" then
        if QDB("REZ") and QoL_IsInDungeon() then
            AcceptResurrect()
        end

    elseif evt == "CONFIRM_SUMMON" then
        if QDB("SUMM") then
            ConfirmSummon()
            StaticPopup_Hide("CONFIRM_SUMMON")
        end

    elseif evt == "DUEL_REQUESTED" then
        if QDB("DUEL") then
            DeclineDuel()
            StaticPopup_Hide("DUEL_REQUESTED")
        end

    elseif evt == "UPDATE_BATTLEFIELD_STATUS" then
        local db = GetQolDB()
        for i = 1, 3 do
            local status, mapName, instanceID, levelRange, maxPlayers, gameType, arenaType, rated, score =
                GetBattlefieldStatus(i)
            if status == "confirm" and db.EBG then
                AcceptBattlefieldPort(i, 1)
            elseif status == "none" and db.LBG then
                -- already left; re-queue handled below
            end
        end

    elseif evt == "GOSSIP_SHOW" then
        QoL_HandleGossip()

    elseif evt == "ZONE_CHANGED_NEW_AREA" or evt == "ZONE_CHANGED" then
        QoL_ZoneCheck()

    elseif evt == "SPELL_FAILED_ONLY_SHAPESHIFT" then
        if QDB("AUTOSTANCE") then
            -- The client will cast the correct stance; just trigger dismount if mounted
            if QDB("DISMOUNT") then QoL_Dismount() end
        end
    end
end)

-- ============================================================
-- StaticPopup hook: block BG quest share
-- ============================================================
local _OrigStaticPopupOnShow = StaticPopup_OnShow
StaticPopup_OnShow = function(dialog)
    if _OrigStaticPopupOnShow then _OrigStaticPopupOnShow(dialog) end
    if not QDB("SBG") then return end
    if dialog and dialog.which == "QUEST_SHARE" and QoL_IsInBG() then
        StaticPopup_Hide("QUEST_SHARE")
    end
end

-- ============================================================
-- UI helper: tooltip for checkboxes
-- ============================================================
local function SetCbTooltip(cb, title, body)
    cb:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0, 1)
        if body and body ~= "" then
            GameTooltip:AddLine(body, 1, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- ============================================================
-- Section header helper
-- ============================================================
local SECTION_COLOR = { 0.6, 0.6, 0.65, 1 }

local function MakeSectionHeader(parent, text, anchorTo, offsetY)
    local hdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, offsetY)
    hdr:SetText(text)
    hdr:SetTextColor(0.9, 0.75, 0.2, 1)
    return hdr
end

-- ============================================================
-- AmptieRaidTools_InitQoLSettings
-- ============================================================
function AmptieRaidTools_InitQoLSettings(body)
    local panel = CreateFrame("Frame", "ART_QoLPanel", body)
    panel:SetAllPoints(body)
    panel:Hide()

    AmptieRaidTools_RegisterComponent("qolsettings", panel)

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    title:SetText("QoL Settings")
    title:SetTextColor(1, 0.82, 0, 1)

    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("Quality-of-life automations. Changes take effect immediately.")
    sub:SetTextColor(0.65, 0.65, 0.7, 1)

    -- Divider
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT",  sub, "BOTTOMLEFT",  0, -6)
    divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, 0)
    divider:SetTexture(0.25, 0.25, 0.28, 0.8)

    -- Column anchor points
    local COL1_X = 12
    local COL2_X = 320
    local ROW_H  = -12

    -- ── Column 1 ──────────────────────────────────────────────
    -- Section: Group Invite
    local hdrInvite = MakeSectionHeader(panel, "Group Invite Accept Rules", divider, -12)

    local db = GetQolDB()

    local cbGinv = ART_CreateCheckbox(panel, "Guild members")
    cbGinv:SetPoint("TOPLEFT", hdrInvite, "BOTTOMLEFT", 0, -4)
    cbGinv:SetChecked(db.GINV)
    cbGinv.userOnClick = function() GetQolDB().GINV = cbGinv:GetChecked() end
    SetCbTooltip(cbGinv, "Guild Members",
        "Automatically accept group invitations\nfrom players in your guild.")

    local cbFinv = ART_CreateCheckbox(panel, "Friends")
    cbFinv:SetPoint("TOPLEFT", cbGinv, "BOTTOMLEFT", 0, ROW_H)
    cbFinv:SetChecked(db.FINV)
    cbFinv.userOnClick = function() GetQolDB().FINV = cbFinv:GetChecked() end
    SetCbTooltip(cbFinv, "Friends",
        "Automatically accept group invitations\nfrom players on your friends list.")

    local cbSinv = ART_CreateCheckbox(panel, "Strangers")
    cbSinv:SetPoint("TOPLEFT", cbFinv, "BOTTOMLEFT", 0, ROW_H)
    cbSinv:SetChecked(db.SINV)
    cbSinv.userOnClick = function() GetQolDB().SINV = cbSinv:GetChecked() end
    SetCbTooltip(cbSinv, "Strangers",
        "Automatically accept group invitations\nfrom anyone (including strangers).")

    local cbDinv = ART_CreateCheckbox(panel, "Idle (not in instance / in queue)")
    cbDinv:SetPoint("TOPLEFT", cbSinv, "BOTTOMLEFT", 0, ROW_H)
    cbDinv:SetChecked(db.DINV)
    cbDinv.userOnClick = function() GetQolDB().DINV = cbDinv:GetChecked() end
    SetCbTooltip(cbDinv, "Idle Accept",
        "Automatically accept invitations when you are\nnot in an instance or are in a BG queue.")

    -- Section: BG Automation
    local hdrBG = MakeSectionHeader(panel, "Battleground Automation", cbDinv, -10)

    local cbEbg = ART_CreateCheckbox(panel, "Enter Battleground")
    cbEbg:SetPoint("TOPLEFT", hdrBG, "BOTTOMLEFT", 0, -4)
    cbEbg:SetChecked(db.EBG)
    cbEbg.userOnClick = function() GetQolDB().EBG = cbEbg:GetChecked() end
    SetCbTooltip(cbEbg, "Enter Battleground",
        "Automatically click the 'Enter' button\nwhen a battleground is ready.")

    local cbLbg = ART_CreateCheckbox(panel, "Leave Battleground when battle ends")
    cbLbg:SetPoint("TOPLEFT", cbEbg, "BOTTOMLEFT", 0, ROW_H)
    cbLbg:SetChecked(db.LBG)
    cbLbg.userOnClick = function() GetQolDB().LBG = cbLbg:GetChecked() end
    SetCbTooltip(cbLbg, "Leave Battleground",
        "Automatically leave the battleground\nwhen the battle is over.")

    local cbQbg = ART_CreateCheckbox(panel, "Re-Queue after leaving BG")
    cbQbg:SetPoint("TOPLEFT", cbLbg, "BOTTOMLEFT", 0, ROW_H)
    cbQbg:SetChecked(db.QBG)
    cbQbg.userOnClick = function() GetQolDB().QBG = cbQbg:GetChecked() end
    SetCbTooltip(cbQbg, "Re-Queue BG",
        "Automatically re-queue for the same battleground\nafter leaving.")

    local cbRbg = ART_CreateCheckbox(panel, "Auto Release in BG")
    cbRbg:SetPoint("TOPLEFT", cbQbg, "BOTTOMLEFT", 0, ROW_H)
    cbRbg:SetChecked(db.RBG)
    cbRbg.userOnClick = function() GetQolDB().RBG = cbRbg:GetChecked() end
    SetCbTooltip(cbRbg, "Auto Release in BG",
        "Automatically release your spirit when you die\nin a battleground.")

    local cbAque = ART_CreateCheckbox(panel, "Leader Queue Announce")
    cbAque:SetPoint("TOPLEFT", cbRbg, "BOTTOMLEFT", 0, ROW_H)
    cbAque:SetChecked(db.AQUE)
    cbAque.userOnClick = function() GetQolDB().AQUE = cbAque:GetChecked() end
    SetCbTooltip(cbAque, "Leader Queue Announce",
        "Announce to your group when you join\na battleground queue as raid/party leader.")

    local cbSbg = ART_CreateCheckbox(panel, "Block BG Quest Sharing")
    cbSbg:SetPoint("TOPLEFT", cbAque, "BOTTOMLEFT", 0, ROW_H)
    cbSbg:SetChecked(db.SBG)
    cbSbg.userOnClick = function() GetQolDB().SBG = cbSbg:GetChecked() end
    SetCbTooltip(cbSbg, "Block BG Quest Sharing",
        "Block incoming quest sharing popups\nwhile you are in a battleground.")

    -- Section: World Chat Mute
    local hdrWorld = MakeSectionHeader(panel, "World Chat Mute", cbSbg, -10)

    local cbWdun = ART_CreateCheckbox(panel, "Mute in Dungeons")
    cbWdun:SetPoint("TOPLEFT", hdrWorld, "BOTTOMLEFT", 0, -4)
    cbWdun:SetChecked(db.WORLDDUNGEON)
    cbWdun.userOnClick = function() GetQolDB().WORLDDUNGEON = cbWdun:GetChecked() QoL_ZoneCheck() end
    SetCbTooltip(cbWdun, "Mute in Dungeons",
        "Mute world/general chat channels while\nyou are inside a dungeon instance.")

    local cbWraid = ART_CreateCheckbox(panel, "Mute in Raids")
    cbWraid:SetPoint("TOPLEFT", cbWdun, "BOTTOMLEFT", 0, ROW_H)
    cbWraid:SetChecked(db.WORLDRAID)
    cbWraid.userOnClick = function() GetQolDB().WORLDRAID = cbWraid:GetChecked() QoL_ZoneCheck() end
    SetCbTooltip(cbWraid, "Mute in Raids",
        "Mute world/general chat channels while\nyou are inside a raid instance.")

    local cbWbg = ART_CreateCheckbox(panel, "Mute in Battlegrounds")
    cbWbg:SetPoint("TOPLEFT", cbWraid, "BOTTOMLEFT", 0, ROW_H)
    cbWbg:SetChecked(db.WORLDBG)
    cbWbg.userOnClick = function() GetQolDB().WORLDBG = cbWbg:GetChecked() QoL_ZoneCheck() end
    SetCbTooltip(cbWbg, "Mute in Battlegrounds",
        "Mute world/general chat channels while\nyou are in a battleground.")

    local cbWperm = ART_CreateCheckbox(panel, "Mute Permanently")
    cbWperm:SetPoint("TOPLEFT", cbWbg, "BOTTOMLEFT", 0, ROW_H)
    cbWperm:SetChecked(db.WORLDUNCHECK)
    cbWperm.userOnClick = function() GetQolDB().WORLDUNCHECK = cbWperm:GetChecked() QoL_ZoneCheck() end
    SetCbTooltip(cbWperm, "Mute Permanently",
        "Always mute world/general chat channels,\nregardless of zone or instance.")

    -- ── Column 2 ──────────────────────────────────────────────
    -- Section: Miscellaneous
    local col2Anchor = CreateFrame("Frame", nil, panel)
    col2Anchor:SetPoint("TOPLEFT", panel, "TOPLEFT", COL2_X, 0)
    col2Anchor:SetWidth(1); col2Anchor:SetHeight(1)

    local hdrMisc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrMisc:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", COL2_X - COL1_X, -12)
    hdrMisc:SetText("Miscellaneous")
    hdrMisc:SetTextColor(0.9, 0.75, 0.2, 1)

    local cbSumm = ART_CreateCheckbox(panel, "Summon Auto Accept")
    cbSumm:SetPoint("TOPLEFT", hdrMisc, "BOTTOMLEFT", 0, -4)
    cbSumm:SetChecked(db.SUMM)
    cbSumm.userOnClick = function() GetQolDB().SUMM = cbSumm:GetChecked() end
    SetCbTooltip(cbSumm, "Summon Auto Accept",
        "Automatically accept summons from\nwarlocks or meeting stones.")

    local cbRight = ART_CreateCheckbox(panel, "Improved Right Click")
    cbRight:SetPoint("TOPLEFT", cbSumm, "BOTTOMLEFT", 0, ROW_H)
    cbRight:SetChecked(db.RIGHT)
    cbRight.userOnClick = function() GetQolDB().RIGHT = cbRight:GetChecked() end
    SetCbTooltip(cbRight, "Improved Right Click",
        "Right-clicking an item in your bags will move it\ninto an open Trade, Mail, or Auction House slot.")

    local cbShift = ART_CreateCheckbox(panel, "Easy Stack Split / Merge")
    cbShift:SetPoint("TOPLEFT", cbRight, "BOTTOMLEFT", 0, ROW_H)
    cbShift:SetChecked(db.SHIFTSPLIT)
    cbShift.userOnClick = function() GetQolDB().SHIFTSPLIT = cbShift:GetChecked() end
    SetCbTooltip(cbShift, "Easy Stack Split / Merge",
        "Shift + Right-Click a stack in your bags to\nautomatically split it in half.")

    local cbCam = ART_CreateCheckbox(panel, "Extended Camera Distance")
    cbCam:SetPoint("TOPLEFT", cbShift, "BOTTOMLEFT", 0, ROW_H)
    cbCam:SetChecked(db.CAM)
    cbCam.userOnClick = function()
        GetQolDB().CAM = cbCam:GetChecked()
        QoL_RefreshCamera()
    end
    SetCbTooltip(cbCam, "Extended Camera Distance",
        "Increases the maximum camera distance beyond\nthe default WoW limit.")

    local cbDuel = ART_CreateCheckbox(panel, "Duel Auto Decline")
    cbDuel:SetPoint("TOPLEFT", cbCam, "BOTTOMLEFT", 0, ROW_H)
    cbDuel:SetChecked(db.DUEL)
    cbDuel.userOnClick = function() GetQolDB().DUEL = cbDuel:GetChecked() end
    SetCbTooltip(cbDuel, "Duel Auto Decline",
        "Automatically decline all duel requests.")

    local cbRez = ART_CreateCheckbox(panel, "Instance Resurrection Auto Accept")
    cbRez:SetPoint("TOPLEFT", cbDuel, "BOTTOMLEFT", 0, ROW_H)
    cbRez:SetChecked(db.REZ)
    cbRez.userOnClick = function() GetQolDB().REZ = cbRez:GetChecked() end
    SetCbTooltip(cbRez, "Instance Resurrection Auto Accept",
        "Automatically accept resurrection offers\nwhile inside an instance.")

    local cbGossip = ART_CreateCheckbox(panel, "Gossip Auto Processing")
    cbGossip:SetPoint("TOPLEFT", cbRez, "BOTTOMLEFT", 0, ROW_H)
    cbGossip:SetChecked(db.GOSSIP)
    cbGossip.userOnClick = function() GetQolDB().GOSSIP = cbGossip:GetChecked() end
    SetCbTooltip(cbGossip, "Gossip Auto Processing",
        "When an NPC has only one non-vendor/trainer\ngossip option, select it automatically.")

    local cbDismount = ART_CreateCheckbox(panel, "Auto Dismount")
    cbDismount:SetPoint("TOPLEFT", cbGossip, "BOTTOMLEFT", 0, ROW_H)
    cbDismount:SetChecked(db.DISMOUNT)
    cbDismount.userOnClick = function() GetQolDB().DISMOUNT = cbDismount:GetChecked() end
    SetCbTooltip(cbDismount, "Auto Dismount",
        "Automatically dismount when you use a spell or\nability that requires being on foot.")

    local cbStance = ART_CreateCheckbox(panel, "Auto Stance")
    cbStance:SetPoint("TOPLEFT", cbDismount, "BOTTOMLEFT", 0, ROW_H)
    cbStance:SetChecked(db.AUTOSTANCE)
    cbStance.userOnClick = function() GetQolDB().AUTOSTANCE = cbStance:GetChecked() end
    SetCbTooltip(cbStance, "Auto Stance",
        "When a spell fails because you are in the wrong\nstance or form, automatically switch to the correct one.")

    -- Section: Quest Repeat
    local hdrQuest = MakeSectionHeader(panel, "Quest Repeat", cbStance, -10)

    local cbQuest = ART_CreateCheckbox(panel, "Automate Quests with CTRL")
    cbQuest:SetPoint("TOPLEFT", hdrQuest, "BOTTOMLEFT", 0, -4)
    cbQuest:SetChecked(db.QUESTREPEAT)
    cbQuest.userOnClick = function() GetQolDB().QUESTREPEAT = cbQuest:GetChecked() end
    SetCbTooltip(cbQuest, "Quest Repeat (CTRL)",
        "Hold CTRL to automatically accept, complete,\nand repeat quests through all quest dialogs.\nUseful for turn-in grinding and repeatable quests.")
end
