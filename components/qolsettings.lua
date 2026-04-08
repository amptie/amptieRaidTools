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
    EBG          = false,  -- Auto enter battleground
    LBG          = false,  -- Auto leave battleground when battle ends
    QBG          = false,  -- Re-queue after leaving BG
    RBG          = false,  -- Auto release in BG
    AQUE         = false,  -- Leader queue announce
    AQUEUE       = false,  -- Automate Queue (group or solo)
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
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "pvp" and true or false
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
-- Dismount helper (pfUI autoshift approach: scan tooltip body for speed text)
-- ============================================================
local qolTipFrame = CreateFrame("GameTooltip", "ART_QoL_Tip", UIParent, "GameTooltipTemplate")
qolTipFrame:SetOwner(UIParent, "ANCHOR_NONE")

-- pfUI mount detection patterns (tooltip description text, not buff name)
local QOL_MOUNT_PATTERNS = {
    -- deDE
    "^Erh%öht Tempo um (.+)%%",
    -- enUS
    "^Increases speed by (.+)%%",
    -- esES
    "^Aumenta la velocidad en un (.+)%%",
    -- frFR
    "^Augmente la vitesse de (.+)%%",
    -- ruRU
    "^%S+ увеличена на (.+)%%",
    -- koKR
    "^이동 속도 (.+)%%만큼 증가",
    -- zhCN
    "^速度提高(.+)%%",
    -- turtle-wow custom mounts
    "speed based on", "Slow and steady", "Riding",
    "Lento y constante", "Aumenta la velocidad",
}

-- pfUI error list: all errors that require dismount or form-cancel
local QOL_DISMOUNT_ERRORS = {
    SPELL_FAILED_NOT_MOUNTED,
    ERR_ATTACK_MOUNTED,
    ERR_TAXIPLAYERALREADYMOUNTED,
    SPELL_FAILED_NOT_SHAPESHIFT,
    SPELL_FAILED_NO_ITEMS_WHILE_SHAPESHIFTED,
    SPELL_NOT_SHAPESHIFTED,
    SPELL_NOT_SHAPESHIFTED_NOSPACE,
    ERR_CANT_INTERACT_SHAPESHIFTED,
    ERR_NOT_WHILE_SHAPESHIFTED,
    ERR_NO_ITEMS_WHILE_SHAPESHIFTED,
    ERR_TAXIPLAYERSHAPESHIFTED,
    ERR_MOUNT_SHAPESHIFTED,
    ERR_EMBLEMERROR_NOTABARDGEOSET,
}

-- Errors that mean "you must LEAVE your current form" → only these trigger QoL_CancelDruidForm.
-- Errors that mean "you must BE shapeshifted" (SPELL_NOT_SHAPESHIFTED etc.) must NOT cancel a form
-- the player is intentionally in (e.g. Moonkin Druid in raid would lose form on every item use).
local QOL_LEAVE_FORM_ERRORS = {
    [ERR_NOT_WHILE_SHAPESHIFTED]               = true,
    [ERR_NO_ITEMS_WHILE_SHAPESHIFTED]          = true,
    [ERR_CANT_INTERACT_SHAPESHIFTED]           = true,
    [ERR_MOUNT_SHAPESHIFTED]                   = true,
    [ERR_TAXIPLAYERSHAPESHIFTED]               = true,
    [SPELL_FAILED_NO_ITEMS_WHILE_SHAPESHIFTED] = true,
}

-- LazyPig-style frame flags for Improved Right Click (IsShown() allein reicht nicht zuverlaessig)
local artTradestatus = nil
local artMailstatus = nil
local artAuctionstatus = nil
local artBankstatus = nil
local artMerchantstatus = nil

local function QoL_Dismount()
    -- pfUI approach: scan tooltip body text for speed increase patterns (0-indexed)
    for i = 0, 31 do
        qolTipFrame:SetOwner(UIParent, "ANCHOR_NONE")
        qolTipFrame:SetPlayerBuff(i)
        -- check all tooltip text lines (name on line 1, description on line 2+)
        for lineIdx = 1, 5 do
            local lineFrame = getglobal("ART_QoL_TipTextLeft" .. lineIdx)
            if lineFrame then
                local txt = lineFrame:GetText()
                if txt then
                    for _, pat in pairs(QOL_MOUNT_PATTERNS) do
                        if strfind(txt, pat) then
                            CancelPlayerBuff(i)
                            return
                        end
                    end
                end
            end
        end
    end
end

-- Druid shapeshift forms that block normal spellcasting
local ART_QOL_DRUID_FORM_NAMES = {
    ["Moonkin Form"]      = true,
    ["Tree of Life"]      = true,
    ["Bear Form"]         = true,
    ["Dire Bear Form"]    = true,
    ["Cat Form"]          = true,
    ["Travel Form"]       = true,
    ["Aquatic Form"]      = true,
    ["Swift Flight Form"] = true,
    ["Flight Form"]       = true,
}

local QOL_HAS_SUPERWOW = (SpellInfo ~= nil)

local function QoL_CancelDruidForm()
    for slot = 0, 39 do
        local buffIndex = GetPlayerBuff(slot, "HELPFUL")
        if buffIndex < 0 then break end
        local matched = false
        if QOL_HAS_SUPERWOW then
            -- SuperWoW: UnitBuff returns spellId as 3rd value → SpellInfo → name
            local _, _, spellId = UnitBuff("player", slot + 1)
            if spellId and spellId > 0 then
                local sname = SpellInfo(spellId)
                matched = sname and ART_QOL_DRUID_FORM_NAMES[sname]
            end
        end
        if not matched then
            -- Non-SuperWoW fallback: tooltip scan via SetPlayerBuff (uses correct buffIndex)
            qolTipFrame:SetOwner(UIParent, "ANCHOR_NONE")
            qolTipFrame:SetPlayerBuff(buffIndex)
            local txt = ART_QoL_TipTextLeft1 and ART_QoL_TipTextLeft1:GetText()
            matched = txt and ART_QOL_DRUID_FORM_NAMES[txt]
        end
        if matched then
            CancelPlayerBuff(buffIndex)
            return
        end
    end
end

-- ============================================================
-- Auto-Stance: on error, switch stance / toggle form off
-- ============================================================
-- Find current druid form name (for toggle-off via CastSpellByName)
local function QoL_GetCurrentFormName()
    for i = 0, 39 do
        local buffIdx = GetPlayerBuff(i, "HELPFUL")
        if buffIdx < 0 then break end
        if QOL_HAS_SUPERWOW then
            local _, _, spellId = UnitBuff("player", i + 1)
            if spellId and spellId > 0 then
                local sname = SpellInfo(spellId)
                if sname and ART_QOL_DRUID_FORM_NAMES[sname] then
                    return sname
                end
            end
        end
        qolTipFrame:SetOwner(UIParent, "ANCHOR_NONE")
        qolTipFrame:SetPlayerBuff(buffIdx)
        local txt = ART_QoL_TipTextLeft1 and ART_QoL_TipTextLeft1:GetText()
        if txt and ART_QOL_DRUID_FORM_NAMES[txt] then
            return txt
        end
    end
    return nil
end

local function art_strsplit(delimiter, subject)
    local fields = {}
    local pattern = string.format("([^%s]+)", delimiter)
    string.gsub(subject, pattern, function(c) fields[table.getn(fields)+1] = c end)
    return unpack(fields)
end

local art_stance_scanStr = string.gsub(SPELL_FAILED_ONLY_SHAPESHIFT, "%%s", "(.+)")

-- Dedicated error listener frame
local art_stance_frame = CreateFrame("Frame")
art_stance_frame:RegisterEvent("UI_ERROR_MESSAGE")
art_stance_frame:SetScript("OnEvent", function()
    local a1 = arg1
    if not a1 then return end
    if not amptieRaidToolsDB or not amptieRaidToolsDB.qolSettings then return end
    if not amptieRaidToolsDB.qolSettings.AUTOSTANCE then return end

    -- Warrior/Paladin: "Can only be used in Battle Stance, ..."
    for stances in string.gfind(a1, art_stance_scanStr) do
        for _, stance in pairs({ art_strsplit(",", stances) }) do
            CastSpellByName(string.gsub(stance, "^%s*(.-)%s*$", "%1"))
        end
        return
    end

    -- Druid: shapeshift errors → cast current form again to toggle it off
    local isLeaveForm = (QOL_LEAVE_FORM_ERRORS and QOL_LEAVE_FORM_ERRORS[a1])
        or strfind(a1, "shapeshift")
        or strfind(a1, "shapeshifted")
        or strfind(a1, "Shapeshift")
    if isLeaveForm then
        if strfind(a1, "interact") and UnitAffectingCombat("player") then return end
        local formName = QoL_GetCurrentFormName()
        if formName then
            CastSpellByName(formName)
        else
            QoL_CancelDruidForm()
        end
    end
end)

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

-- LazyPig-compatible GOSSIP_SHOW state (GossipOptions = types at indices 1..5; dsc = first option text)
local artGossipTypes = {}
local artGossipQuestState = { qnpc = nil, index = 0 }

local function QoL_TwipeGossipTable(t)
    for i = table.getn(t), 1, -1 do
        table.remove(t, i)
    end
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

-- LazyPig_ProcessQuests: GetGossipActiveQuests / GetGossipAvailableQuests varargs -> [i] = "title level"
-- Lua 5.0 / WoW 1.12: "arg" existiert nur bei Vararg-Signatur (...), sonst nil
local function QoL_ProcessGossipQuestList(...)
    local quest = {}
    local n = arg.n
    local i
    for i = 1, n, 2 do
        local title, level = arg[i], arg[i + 1]
        local idx = (i + 1) / 2
        quest[idx] = tostring(title or "") .. " " .. tostring(level or "")
    end
    return quest
end

-- ============================================================
-- Invite helper functions (ported from LazyPig)
-- ============================================================
local function QoL_IsFriend(name)
    for i = 1, GetNumFriends() do
        if GetFriendInfo(i) == name then return true end
    end
    return false
end

local function QoL_IsGuildMate(name)
    if IsInGuild() then
        for i = 1, GetNumGuildMembers() do
            if string.lower(GetGuildRosterInfo(i)) == string.lower(name) then
                return true
            end
        end
    end
    return false
end

local function QoL_IsInBGOrQueue()
    for i = 1, 3 do
        local status = GetBattlefieldStatus(i)
        if status == "active" or status == "queued" or status == "confirm" then
            return true
        end
    end
    return false
end

-- ============================================================
-- Camera distance
-- ============================================================
local function QoL_RefreshCamera()
    if QDB("CAM") then
        SetCVar("cameraDistanceMax", "50")
    end
end

-- ============================================================
-- Gossip auto-select (GOSSIP_SHOW logic 1:1 from LazyPig LazyPig_OnEvent GOSSIP_SHOW)
-- ============================================================
local function QoL_HandleGossip()
    -- QUESTREPEAT gossip (1:1 from QuestRepeat addon)
    if QDB("QUESTREPEAT") then
        if IsControlKeyDown() and qrData.quest then
            local titleButton
            for i = 1, NUMGOSSIPBUTTONS do
                titleButton = getglobal("GossipTitleButton" .. i)
                if titleButton:IsVisible() and titleButton:GetText() == qrData.quest then
                    titleButton:Click()
                    return
                end
            end
            -- quest not found in gossip — no reset, same as QuestRepeat
        else
            qrData.quest = nil
            qrData.item  = nil
        end
    end

    -- LazyPig: GOSSIP_SHOW runs fully every time; processgossip only gates some branches.
    -- QBG can still auto-select battlemaster when GOSSIP is off (same as LazyPig).
    QoL_TwipeGossipTable(artGossipTypes)
    local dsc = nil
    local gossipnr = nil
    local gossipbreak = nil
    local db = GetQolDB()
    local processgossip = db.GOSSIP and not IsShiftKeyDown()

    dsc, artGossipTypes[1], _, artGossipTypes[2], _, artGossipTypes[3], _, artGossipTypes[4], _, artGossipTypes[5] = GetGossipOptions()

    local ActiveQuest = QoL_ProcessGossipQuestList(GetGossipActiveQuests())
    local AvailableQuest = QoL_ProcessGossipQuestList(GetGossipAvailableQuests())

    if artGossipQuestState.qnpc ~= UnitName("npc") then
        artGossipQuestState.index = 0
        artGossipQuestState.qnpc = UnitName("npc")
    end

    if table.getn(AvailableQuest) ~= 0 or table.getn(ActiveQuest) ~= 0 then
        gossipbreak = true
    end

    local i
    for i = 1, 5 do
        if not artGossipTypes[i] then
            break
        end
        if artGossipTypes[i] == "binder" then
            local bind = GetBindLocation()
            if not (bind == GetSubZoneText() or bind == GetZoneText() or bind == GetRealZoneText() or bind == GetMinimapZoneText()) then
                gossipbreak = true
            end
        elseif gossipnr then
            gossipbreak = true
        elseif artGossipTypes[i] == "trainer" and dsc == "Reset my talents." then
            gossipbreak = false
        elseif ((artGossipTypes[i] == "trainer" and processgossip)
                or (artGossipTypes[i] == "vendor" and processgossip)
                or (artGossipTypes[i] == "battlemaster" and (db.QBG or db.AQUEUE or processgossip))
                or (artGossipTypes[i] == "gossip" and processgossip)
                or (artGossipTypes[i] == "banker" and string.find(dsc or "", "^I would like to check my deposit box.") and processgossip)
                or (artGossipTypes[i] == "petition" and (IsAltKeyDown() or IsShiftKeyDown() or string.find(dsc or "", "Teleport me to the Molten Core")) and processgossip))
        then
            gossipnr = i
        elseif artGossipTypes[i] == "taxi" and processgossip then
            gossipnr = i
            QoL_Dismount()
        end
    end

    if not gossipbreak and gossipnr then
        SelectGossipOption(gossipnr)
    end
end

-- ============================================================
-- LazyPig_ItemIsTradeable (1:1): mail/AH attachability via tooltip lines
-- ============================================================
local function QoL_ItemIsTradeable(bag, slot)
    local i
    for i = 1, 29 do
        local fs = getglobal("ART_QoL_TipTextLeft" .. i)
        if fs then fs:SetText("") end
    end
    qolTipFrame:SetBagItem(bag, slot)
    for i = 1, qolTipFrame:NumLines() do
        local text = getglobal("ART_QoL_TipTextLeft" .. i):GetText()
        if text == ITEM_SOULBOUND then
            return nil
        elseif text == ITEM_BIND_QUEST then
            return nil
        elseif text == ITEM_CONJURED then
            return nil
        end
    end
    return true
end

-- LazyPig_MailtoCheck: MailTo-Addon-Kompatibilitaet
local function QoL_MailtoCheck(msg)
    if not MailTo_Option then return end
    local db = GetQolDB()
    local disable = db.RIGHT or db.SHIFTSPLIT
    MailTo_Option.noshift = disable
    MailTo_Option.noauction = disable
    MailTo_Option.notrade = disable
    MailTo_Option.noclick = disable
    if msg then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Improved Right Click / Easy Split may override MailTo options.")
    end
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

-- Wie LazyPig_EndSplit bei MAIL/AH/BANK/TRADE zu
local function QoL_EndSplitShortcut()
    splitVal   = 1
    splitTimer = nil
end

-- ============================================================
-- UseContainerItem hook — Reihenfolge und Zweige wie LazyPig_UseContainerItem
-- ============================================================
local _OrigUseContainerItem = UseContainerItem
UseContainerItem = function(ParentID, ItemID)
    local db = GetQolDB()

    -- 1) SHIFTSPLIT zuerst (LazyPig: vor RIGHT; nicht im Haendlerfenster)
    if db.SHIFTSPLIT and not (LPCONFIG and LPCONFIG.SHIFTSPLIT)
            and not CursorHasItem() and not artMerchantstatus
            and IsShiftKeyDown() and not IsAltKeyDown() then
        local t = GetTime()
        if (t - splitLastClick) < 0.3 then return end
        local _, itemCount, locked = GetContainerItemInfo(ParentID, ItemID)
        if not locked and itemCount and itemCount > 1 then
            local count = splitVal
            if count >= itemCount then count = itemCount - 1 end
            if count < 1 then count = 1 end
            local destBag, destSlot
            for b = 0, NUM_BAG_FRAMES do
                for s = 1, GetContainerNumSlots(b) do
                    if not (b == ParentID and s == ItemID) and not GetContainerItemLink(b, s) then
                        destBag, destSlot = b, s
                        break
                    end
                end
                if destBag then break end
            end
            if destBag then
                SplitContainerItem(ParentID, ItemID, count)
                PickupContainerItem(destBag, destSlot)
                splitLastClick = t
                splitTimer     = t + splitDuration
                return
            end
        end
    end

    -- 2) Improved Right Click (LazyPig_UseContainerItem, ohne LazyPig-Kette)
    if db.RIGHT and not (LPCONFIG and LPCONFIG.RIGHT) then
        if artTradestatus and not IsShiftKeyDown() and not IsAltKeyDown() and QoL_ItemIsTradeable(ParentID, ItemID) then
            PickupContainerItem(ParentID, ItemID)
            local slot = TradeFrame_GetAvailableSlot and TradeFrame_GetAvailableSlot()
            if slot then ClickTradeButton(slot) end
            if CursorHasItem() then ClearCursor() end
            return
        end

        if GMailFrame and GMailFrame:IsVisible() and not CursorHasItem() and GMAIL_NUMITEMBUTTONS and GMail then
            local bag, item = ParentID, ItemID
            local i
            for i = 1, GMAIL_NUMITEMBUTTONS do
                if not _G["GMailButton" .. i].item then
                    if GMail:ItemIsMailable(bag, item) then
                        GMail:Print("GMail: Cannot attach item.", 1, 0.5, 0)
                        return
                    end
                    PickupContainerItem(bag, item)
                    GMail:MailButton_OnClick(_G["GMailButton" .. i])
                    GMail:UpdateItemButtons()
                    return
                end
            end
        end

        if CT_MailFrame and CT_MailFrame:IsVisible() and not IsShiftKeyDown() and not IsAltKeyDown() then
            local bag, item = ParentID, ItemID
            if ((CT_Mail_GetItemFrame and CT_Mail_GetItemFrame(bag, item))
                    or (CT_Mail_addItem and CT_Mail_addItem[1] == bag and CT_Mail_addItem[2] == item)) and not special then
                return
            end
            if not CursorHasItem() then
                CT_MailFrame.bag = bag
                CT_MailFrame.item = item
            end
            if CT_MailFrame:IsVisible() and not CursorHasItem() and CT_MAIL_NUMITEMBUTTONS then
                local i
                for i = 1, CT_MAIL_NUMITEMBUTTONS, 1 do
                    if not _G["CT_MailButton" .. i].item then
                        local canMail = CT_Mail_ItemIsMailable and CT_Mail_ItemIsMailable(bag, item)
                        if canMail then
                            DEFAULT_CHAT_FRAME:AddMessage("<CTMod> Cannot attach item, item is " .. tostring(canMail), 1, 0.5, 0)
                            return
                        end
                        if CT_oldPickupContainerItem then
                            CT_oldPickupContainerItem(bag, item)
                        else
                            PickupContainerItem(bag, item)
                        end
                        if CT_MailButton_OnClick then CT_MailButton_OnClick(_G["CT_MailButton" .. i]) end
                        if CT_Mail_UpdateItemButtons then CT_Mail_UpdateItemButtons() end
                        return
                    end
                end
            end
        end

        if artMailstatus and not IsShiftKeyDown() and not IsAltKeyDown() then
            if not QoL_ItemIsTradeable(ParentID, ItemID) then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Cannot attach item", 1, 0.5, 0)
                return
            end
            if InboxFrame and InboxFrame:IsVisible() then
                MailFrameTab_OnClick(2)
                return
            end
            if SendMailFrame and SendMailFrame:IsVisible() then
                PickupContainerItem(ParentID, ItemID)
                ClickSendMailItemButton()
                if CursorHasItem() then ClearCursor() end
                return
            end
        end

        if artAuctionstatus and not IsShiftKeyDown() and not IsAltKeyDown() then
            if not QoL_ItemIsTradeable(ParentID, ItemID) then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Cannot sell item", 1, 0.5, 0)
                return
            end
            if AuctionFrameAuctions and not AuctionFrameAuctions:IsVisible() and AuctionFrameTab3 then
                AuctionFrameTab3:Click()
                return
            end
            PickupContainerItem(ParentID, ItemID)
            if ClickAuctionSellItemButton then ClickAuctionSellItemButton() end
            if CursorHasItem() then ClearCursor() end
            return
        end
    end

    _OrigUseContainerItem(ParentID, ItemID)
end

-- ============================================================
-- Quest Repeat hooks  (1:1 port of QuestRepeat addon by Kyahx)
-- Only change: reward_chosen → qrData, QDB("QUESTREPEAT") guard added.
-- ============================================================
local function QR_PostHook(original, hook)
    return function(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10)
        if original then original(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10) end
        hook(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10)
    end
end

local function QR_PreHook(original, hook)
    return function(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10)
        hook(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10)
        if original then original(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10) end
    end
end

-- Reward button PreHook: save/restore item choice (runs before original GetQuestReward call)
local function QR_QuestRewardCompleteButton_OnClick()
    if not QDB("QUESTREPEAT") then return end
    if IsControlKeyDown() and qrData.quest and qrData.item then
        QuestFrameRewardPanel.itemChoice = qrData.item
    else
        qrData.item  = QuestFrameRewardPanel.itemChoice
        qrData.quest = QuestRewardTitleText:GetText()
    end
end
QuestRewardCompleteButton_OnClick = QR_PreHook(QuestRewardCompleteButton_OnClick, QR_QuestRewardCompleteButton_OnClick)

-- Reward panel: auto-complete when choice is known or no choice needed
local function QR_QuestFrameRewardPanel_OnShow()
    if not QDB("QUESTREPEAT") then return end
    if IsControlKeyDown() and ((qrData.quest and qrData.item) or QuestFrameRewardPanel.itemChoice == 0) then
        QuestFrameCompleteQuestButton:Click()
    end
end
QuestFrameRewardPanel_OnShow = QR_PostHook(QuestFrameRewardPanel_OnShow, QR_QuestFrameRewardPanel_OnShow)

-- Detail panel: save quest name and accept
local function QR_QuestFrameDetailPanel_OnShow()
    if not QDB("QUESTREPEAT") then return end
    if IsControlKeyDown() then
        qrData.quest = QuestTitleText:GetText()
        AcceptQuest()
    end
end
QuestFrameDetailPanel_OnShow = QR_PostHook(QuestFrameDetailPanel_OnShow, QR_QuestFrameDetailPanel_OnShow)

-- Progress panel: click complete button
local function QR_QuestFrameProgressPanel_OnShow()
    if not QDB("QUESTREPEAT") then return end
    if IsControlKeyDown() then
        QuestFrameCompleteButton:Click()
    end
end
QuestFrameProgressPanel_OnShow = QR_PostHook(QuestFrameProgressPanel_OnShow, QR_QuestFrameProgressPanel_OnShow)

-- Greeting panel: find and click the remembered quest's title button
local function QR_QuestFrameGreetingPanel_OnShow()
    if not QDB("QUESTREPEAT") then return end
    if IsControlKeyDown() and qrData.quest then
        local titleButton
        for i = 1, MAX_NUM_QUESTS do
            titleButton = getglobal("QuestTitleButton" .. i)
            if titleButton:IsVisible() and titleButton:GetText() == qrData.quest then
                titleButton:Click()
                break
            end
        end
    else
        qrData.quest = nil
        qrData.item  = nil
    end
end
QuestFrameGreetingPanel_OnShow = QR_PostHook(QuestFrameGreetingPanel_OnShow, QR_QuestFrameGreetingPanel_OnShow)

-- ============================================================
-- BG leave: poll every second while inside a BG.
-- No reliance on specific event timing or localised "wins!" message text.
local bgLeavePoll = 0
local qolBgLeaveFrame = CreateFrame("Frame", nil, UIParent)
qolBgLeaveFrame:SetScript("OnUpdate", function()
    local t = GetTime()
    if t < bgLeavePoll then return end
    bgLeavePoll = t + 1
    if not QDB("LBG") then return end
    if not QoL_IsInBG() then return end
    if GetBattlefieldWinner() ~= nil then
        LeaveBattlefield()
    end
end)

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
qolEventFrame:RegisterEvent("PLAYER_DEAD")
qolEventFrame:RegisterEvent("BATTLEFIELDS_SHOW")
qolEventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
qolEventFrame:RegisterEvent("GOSSIP_SHOW")
qolEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
qolEventFrame:RegisterEvent("ZONE_CHANGED")
qolEventFrame:RegisterEvent("SPELL_FAILED_ONLY_SHAPESHIFT")
qolEventFrame:RegisterEvent("UI_ERROR_MESSAGE")
qolEventFrame:RegisterEvent("BANKFRAME_OPENED")
qolEventFrame:RegisterEvent("BANKFRAME_CLOSED")
qolEventFrame:RegisterEvent("TRADE_SHOW")
qolEventFrame:RegisterEvent("TRADE_CLOSED")
qolEventFrame:RegisterEvent("MAIL_SHOW")
qolEventFrame:RegisterEvent("MAIL_CLOSED")
qolEventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
qolEventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
qolEventFrame:RegisterEvent("MERCHANT_SHOW")
qolEventFrame:RegisterEvent("MERCHANT_CLOSED")

qolEventFrame:SetScript("OnEvent", function()
    local evt = event
    local a1  = arg1

    if evt == "PLAYER_LOGIN" or evt == "PLAYER_ENTERING_WORLD" then
        QoL_RefreshCamera()
        QoL_ZoneCheck()
        if evt == "PLAYER_LOGIN" then
            QoL_MailtoCheck()
        end

    elseif evt == "BANKFRAME_OPENED" then
        artBankstatus = true
        splitVal = 1

    elseif evt == "BANKFRAME_CLOSED" then
        artBankstatus = false
        QoL_EndSplitShortcut()

    elseif evt == "TRADE_SHOW" then
        artTradestatus = true
        splitVal = 1

    elseif evt == "TRADE_CLOSED" then
        artTradestatus = false
        QoL_EndSplitShortcut()

    elseif evt == "MAIL_SHOW" then
        artMailstatus = true
        splitVal = 1

    elseif evt == "MAIL_CLOSED" then
        artMailstatus = false
        QoL_EndSplitShortcut()

    elseif evt == "AUCTION_HOUSE_SHOW" then
        artAuctionstatus = true
        splitVal = 1

    elseif evt == "AUCTION_HOUSE_CLOSED" then
        artAuctionstatus = false
        QoL_EndSplitShortcut()

    elseif evt == "MERCHANT_SHOW" then
        artMerchantstatus = true

    elseif evt == "MERCHANT_CLOSED" then
        artMerchantstatus = false

    elseif evt == "PARTY_INVITE_REQUEST" then
        local db = GetQolDB()
        local name = a1
        local isGuild  = QoL_IsGuildMate(name)
        local isFriend = QoL_IsFriend(name)
        -- Who to accept from (mirrors LazyPig logic)
        local fromWho = (db.GINV and isGuild)
                     or (db.FINV and isFriend)
                     or (db.SINV and not isGuild and not isFriend)
        if fromWho then
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
            CancelDuel()
            StaticPopup_Hide("DUEL_REQUESTED")
        end

    elseif evt == "UPDATE_BATTLEFIELD_STATUS" then
        local db = GetQolDB()
        for i = 1, 3 do
            local status = GetBattlefieldStatus(i)
            if status == "confirm" and db.EBG then
                AcceptBattlefieldPort(i, 1)
            end
        end
        -- LBG is handled by the polling frame; no timer logic needed here.

    elseif evt == "CHAT_MSG_SYSTEM" then
        -- Leader Queue Announce: forward "Queued for X" system message to raid/party (LazyPig AQUE)
        if QDB("AQUE") and a1 and strfind(a1, "Queued") and UnitIsPartyLeader("player") then
            if GetNumRaidMembers() > 0 then
                SendChatMessage(a1, "RAID")
            elseif GetNumPartyMembers() > 1 then
                SendChatMessage(a1, "PARTY")
            end
        end

    elseif evt == "PLAYER_DEAD" then
        -- Auto-release spirit in battleground (LazyPig RBG)
        if QDB("RBG") and QoL_IsInBG() then
            RepopMe()
        end

    elseif evt == "BATTLEFIELDS_SHOW" then
        -- Automate Queue / Re-Queue: join as group if leader, otherwise solo (LazyPig pattern)
        if QDB("AQUEUE") or QDB("QBG") then
            if (GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0) and IsPartyLeader() then
                JoinBattlefield(0, 1)
            else
                JoinBattlefield(0)
            end
            if BattlefieldFrameCancelButton then
                BattlefieldFrameCancelButton:Click()
            end
        end

    elseif evt == "GOSSIP_SHOW" then
        QoL_HandleGossip()

    elseif evt == "ZONE_CHANGED_NEW_AREA" or evt == "ZONE_CHANGED" then
        if evt == "ZONE_CHANGED_NEW_AREA" then
            artTradestatus = nil
            artMailstatus = nil
            artAuctionstatus = nil
            artBankstatus = nil
        end
        QoL_ZoneCheck()

    elseif evt == "SPELL_FAILED_ONLY_SHAPESHIFT" then
        -- pfUI: dismount fires independently
        if QDB("DISMOUNT") then QoL_Dismount() end

    elseif evt == "UI_ERROR_MESSAGE" then
        -- Auto-dismount: fire on all pfUI-style mount/shapeshift error messages
        if QDB("DISMOUNT") and a1 then
            for _, errStr in pairs(QOL_DISMOUNT_ERRORS) do
                if a1 == errStr then
                    if a1 == ERR_CANT_INTERACT_SHAPESHIFTED and UnitAffectingCombat("player") then
                        break
                    end
                    QoL_Dismount()
                    break
                end
            end
        end
    end
end)


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

    -- Section: BG Automation
    local hdrBG = MakeSectionHeader(panel, "Battleground Automation", cbSinv, -10)

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

    local cbAqueue = ART_CreateCheckbox(panel, "Automate Queue")
    cbAqueue:SetPoint("TOPLEFT", cbAque, "BOTTOMLEFT", 0, ROW_H)
    cbAqueue:SetChecked(db.AQUEUE)
    cbAqueue.userOnClick = function() GetQolDB().AQUEUE = cbAqueue:GetChecked() end
    SetCbTooltip(cbAqueue, "Automate Queue",
        "When the battlefield window opens, automatically\njoin as a group (if you are group leader) or solo.\nNote: Re-Queue requires talking to a Battlemaster NPC\nafter leaving — the game only allows queuing via NPC.")

    -- Section: World Chat Mute
    local hdrWorld = MakeSectionHeader(panel, "World Chat Mute", cbAqueue, -10)

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
        "Same behavior as LazyPig: right-click moves items into\nTrade, Mail (incl. inbox tab switch), Auction create,\nor CT_Mail / GMail when open. Uses event flags so the\nbank and default bag clicks are not stolen by mail/trade.\nHold Shift to bypass mail/trade/AH branches.")

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
        "Same behavior as LazyPig: skip gossip choices for\ninnkeepers, flight masters, vendors, etc.\nHold Shift to bypass. Battlemaster auto-enter\nalso respects the \"Re-queue after leaving BG\" option.")

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

