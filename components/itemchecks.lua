-- components/itemchecks.lua
-- Item Checks: raid bag inspection rules with profile system (Lua 5.0 / WoW 1.12)

local getn    = table.getn
local tinsert = table.insert
local floor   = math.floor

local _ART_IC_RefreshRules  = nil
local _ART_IC_RefreshEditor = nil
local ART_IC_dropdownHiders = {}

-- Transparent full-screen button that catches clicks outside any open dropdown
local ART_IC_catchFrame = CreateFrame("Button", nil, UIParent)
ART_IC_catchFrame:SetFrameStrata("FULLSCREEN")
ART_IC_catchFrame:SetAllPoints(UIParent)
ART_IC_catchFrame:EnableMouse(true)
ART_IC_catchFrame:Hide()
ART_IC_catchFrame:SetScript("OnClick", function()
    for i = 1, getn(ART_IC_dropdownHiders) do
        ART_IC_dropdownHiders[i]()
    end
    this:Hide()
end)

-- ============================================================
-- Shared backdrop constants
-- ============================================================
local BD_PANEL = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BD_EDIT = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 10,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- ============================================================
-- Item table  (sec = "consumable" | "item")
-- anyOne = true  → player needs any ONE of the IDs
-- grouped = true → count appearances across all IDs
-- ============================================================
local ART_IC_ITEMS = {
    -- Consumables (alphabetical)
    { key="BLESSED_WIZ_OIL",    name="Blessed Wizard Oil",                 sec="consumable", ids={23123} },
    { key="BRILL_MANA_OIL",     name="Brilliant Mana Oil",                 sec="consumable", ids={20748} },
    { key="BRILL_WIZ_OIL",      name="Brilliant Wizard Oil",               sec="consumable", ids={20749} },
    { key="CONCOCTION_ARCANE",  name="Concoction of the Arcane Giant",     sec="consumable", ids={47412} },
    { key="CONCOCTION_DREAM",   name="Concoction of the Dreamwater",       sec="consumable", ids={47414} },
    { key="CONCOCTION_EMERALD", name="Concoction of the Emerald Mongoose",  sec="consumable", ids={47410} },
    { key="CONSECR_STONE",      name="Consecrated Sharpening Stone",       sec="consumable", ids={23122} },
    { key="DREAMSHARD_ELX",     name="Dreamshard Elixir",                  sec="consumable", ids={61224} },
    { key="DREAMTONIC",         name="Dreamtonic",                         sec="consumable", ids={61423} },
    { key="ELEM_SHARP_STONE",   name="Elemental Sharpening Stone",         sec="consumable", ids={18262} },
    { key="ELX_FORTITUDE",      name="Elixir of Fortitude",                sec="consumable", ids={3825} },
    { key="ELX_GIANTS",         name="Elixir of Giants",                   sec="consumable", ids={9206} },
    { key="ELX_GR_ARCANE_PWR",  name="Elixir of Greater Arcane Power",     sec="consumable", ids={55048} },
    { key="ELX_GR_FIRE_PWR",    name="Elixir of Greater Fire Power",       sec="consumable", ids={21546} },
    { key="ELX_GR_FROST_PWR",   name="Elixir of Greater Frost Power",      sec="consumable", ids={55046} },
    { key="ELX_GR_NATURE_PWR",  name="Elixir of Greater Nature Power",     sec="consumable", ids={50237} },
    { key="ELX_MONGOOSE",       name="Elixir of the Mongoose",             sec="consumable", ids={13452} },
    { key="ELX_POISON_RES",     name="Elixir of Poison Resistance",        sec="consumable", ids={3386} },
    { key="ELX_SHADOW_PWR",     name="Elixir of Shadow Power",             sec="consumable", ids={9264} },
    { key="ELX_SUP_DEFENSE",    name="Elixir of Superior Defense",         sec="consumable", ids={13445} },
    { key="FLASK_CHROM_RES",    name="Flask of Chromatic Resistance",      sec="consumable", ids={13513} },
    { key="FLASK_DIST_WIS",     name="Flask of Distilled Wisdom",          sec="consumable", ids={13511} },
    { key="FLASK_SUP_PWR",      name="Flask of Supreme Power",             sec="consumable", ids={13512} },
    { key="FLASK_TITANS",       name="Flask of the Titans",                sec="consumable", ids={13510} },
    { key="FREE_ACTION",        name="Free Action Potion",                 sec="consumable", ids={5634} },
    { key="GR_ARCANE_ELX",      name="Greater Arcane Elixir",              sec="consumable", ids={13454} },
    { key="GR_ARCANE_PROT",     name="Greater Arcane Protection Potion",   sec="consumable", ids={13461} },
    { key="GR_FIRE_PROT",       name="Greater Fire Protection Potion",     sec="consumable", ids={13457} },
    { key="GR_FROST_PROT",      name="Greater Frost Protection Potion",    sec="consumable", ids={13456} },
    { key="GR_HOLY_PROT",       name="Greater Holy Protection Potion",     sec="consumable", ids={13460} },
    { key="GR_NATURE_PROT",     name="Greater Nature Protection Potion",   sec="consumable", ids={13458} },
    { key="GR_SHADOW_PROT",     name="Greater Shadow Protection Potion",   sec="consumable", ids={13459} },
    { key="GR_STONESHIELD",     name="Greater Stoneshield Potion",         sec="consumable", ids={13455} },
    { key="GROUND_SCORPOK",     name="Ground Scorpok Assay",               sec="consumable", ids={8412} },
    { key="INVIS_POTION",       name="Invisibility Potion",                sec="consumable", ids={9172} },
    { key="JUJU_MIGHT",         name="Juju Might",                         sec="consumable", ids={12460} },
    { key="JUJU_POWER",         name="Juju Power",                         sec="consumable", ids={12451} },
    { key="LESSER_INVIS",       name="Lesser Invisibility Potion",         sec="consumable", ids={3823} },
    { key="LTD_INVULN",         name="Limited Invulnerability Potion",     sec="consumable", ids={3387} },
    { key="MAGIC_RES_POT",      name="Magic Resistance Potion",            sec="consumable", ids={9036} },
    { key="MAGEBLOOD",          name="Mageblood Potion",                   sec="consumable", ids={20007} },
    { key="MAJ_MANA_POT",       name="Major Mana Potion",                  sec="consumable", ids={13444} },
    { key="MIGHTY_RAGE",        name="Mighty Rage Potion",                 sec="consumable", ids={13442} },
    { key="NATURE_PROT",        name="Nature Protection Potion",           sec="consumable", ids={6052} },
    { key="ROIDS",              name="R.O.I.D.S.",                         sec="consumable", ids={8410} },
    { key="RESTORATIVE",        name="Restorative Potion",                 sec="consumable", ids={9030} },
    { key="RUMSEY_RUM",         name="Rumsey Rum Black Label",             sec="consumable", ids={21151} },
    { key="SHEEN_ZANZA",        name="Sheen of Zanza",                     sec="consumable", ids={20080} },
    { key="SPIRIT_ZANZA",       name="Spirit of Zanza",                    sec="consumable", ids={20079} },
    { key="SWIFTNESS_POT",      name="Swiftness Potion",                   sec="consumable", ids={2459} },
    { key="SWIFTNESS_ZANZA",    name="Swiftness of Zanza",                 sec="consumable", ids={20081} },
    { key="WINTERFALL_FW",      name="Winterfall Firewater",               sec="consumable", ids={12820} },
    -- Items (alphabetical)
    { key="BAROV_CALLER",       name="Barov Peasant Caller",               sec="item", ids={14022,14023}, anyOne=true },
    { key="FROST_OIL",          name="Frost Oil",                          sec="item", ids={3829} },
    { key="FROST_WEAPON",       name="Frost Weapon (any)",                 sec="item", ids={10761,810,19099,13984}, grouped=true },
    { key="MAJ_HEALTHSTONE",    name="Major Healthstone",                  sec="item", ids={19013,19012,9421}, anyOne=true },
    { key="MEDIVH_MERLOT",      name="Medivh's Merlot",                    sec="item", ids={61174} },
    { key="MEDIVH_MERLOT_BLUE", name="Medivh's Merlot Blue",               sec="item", ids={61175} },
    { key="ONYXA_CLOAK",        name="Onyxa Scale Cloak",                  sec="item", ids={15138} },
    -- Resistances (checked via UnitResistance, no item IDs)
    { key="RES_FIRE",   name="Fire Resistance",   sec="resistance", resistIndex=2 },
    { key="RES_NATURE", name="Nature Resistance", sec="resistance", resistIndex=3 },
    { key="RES_FROST",  name="Frost Resistance",  sec="resistance", resistIndex=4 },
    { key="RES_SHADOW", name="Shadow Resistance", sec="resistance", resistIndex=5 },
    { key="RES_ARCANE", name="Arcane Resistance", sec="resistance", resistIndex=6 },
}

-- key → item lookup
local ART_IC_BY_KEY = {}
for _i = 1, getn(ART_IC_ITEMS) do
    ART_IC_BY_KEY[ART_IC_ITEMS[_i].key] = ART_IC_ITEMS[_i]
end

-- Hardcoded icon paths (avoids relying on GetItemInfo cache)
local ART_IC_ICONS = {
    -- Consumables
    BLESSED_WIZ_OIL    = "Interface\\Icons\\INV_Potion_138",
    BRILL_MANA_OIL     = "Interface\\Icons\\INV_Potion_100",
    BRILL_WIZ_OIL      = "Interface\\Icons\\INV_Potion_105",
    CONCOCTION_ARCANE  = "Interface\\Icons\\inv_yellow_purple_elixir_2",
    CONCOCTION_DREAM   = "Interface\\Icons\\inv_green_pink_elixir_1",
    CONCOCTION_EMERALD = "Interface\\Icons\\inv_blue_gold_elixir_2",
    CONSECR_STONE      = "Interface\\Icons\\INV_Stone_SharpeningStone_02",
    DREAMSHARD_ELX     = "Interface\\Icons\\INV_Potion_113",
    DREAMTONIC         = "Interface\\Icons\\INV_Potion_114",
    ELEM_SHARP_STONE   = "Interface\\Icons\\INV_Stone_02",
    ELX_FORTITUDE      = "Interface\\Icons\\INV_Potion_43",
    ELX_GIANTS         = "Interface\\Icons\\INV_Potion_61",
    ELX_GR_ARCANE_PWR  = "Interface\\Icons\\INV_Potion_81",
    ELX_GR_FIRE_PWR    = "Interface\\Icons\\INV_Potion_60",
    ELX_GR_FROST_PWR   = "Interface\\Icons\\INV_Potion_13",
    ELX_GR_NATURE_PWR  = "Interface\\Icons\\INV_Potion_106",
    ELX_MONGOOSE       = "Interface\\Icons\\INV_Potion_32",
    ELX_POISON_RES     = "Interface\\Icons\\INV_Potion_12",
    ELX_SHADOW_PWR     = "Interface\\Icons\\INV_Potion_46",
    ELX_SUP_DEFENSE    = "Interface\\Icons\\INV_Potion_66",
    FLASK_CHROM_RES    = "Interface\\Icons\\INV_Potion_128",
    FLASK_DIST_WIS     = "Interface\\Icons\\inv_potion_120",
    FLASK_SUP_PWR      = "Interface\\Icons\\INV_Potion_41",
    FLASK_TITANS       = "Interface\\Icons\\INV_Potion_62",
    FREE_ACTION        = "Interface\\Icons\\INV_Potion_04",
    GR_ARCANE_ELX      = "Interface\\Icons\\INV_Potion_25",
    GR_ARCANE_PROT     = "Interface\\Icons\\inv_potion_83",
    GR_FIRE_PROT       = "Interface\\Icons\\INV_Potion_117",
    GR_FROST_PROT      = "Interface\\Icons\\INV_Potion_20",
    GR_HOLY_PROT       = "Interface\\Icons\\INV_Potion_09",
    GR_NATURE_PROT     = "Interface\\Icons\\INV_Potion_22",
    GR_SHADOW_PROT     = "Interface\\Icons\\INV_Potion_23",
    GR_STONESHIELD     = "Interface\\Icons\\INV_Potion_69",
    GROUND_SCORPOK     = "Interface\\Icons\\INV_Misc_Dust_07",
    INVIS_POTION       = "Interface\\Icons\\INV_Potion_112",
    JUJU_MIGHT         = "Interface\\Icons\\INV_Misc_MonsterScales_07",
    JUJU_POWER         = "Interface\\Icons\\INV_Misc_MonsterScales_11",
    LESSER_INVIS       = "Interface\\Icons\\INV_Potion_18",
    LTD_INVULN         = "Interface\\Icons\\INV_Potion_121",
    MAGIC_RES_POT      = "Interface\\Icons\\INV_Potion_16",
    MAGEBLOOD          = "Interface\\Icons\\INV_Potion_45",
    MAJ_MANA_POT       = "Interface\\Icons\\INV_Potion_76",
    MIGHTY_RAGE        = "Interface\\Icons\\inv_potion_125",
    NATURE_PROT        = "Interface\\Icons\\INV_Potion_06",
    ROIDS              = "Interface\\Icons\\INV_Stone_15",
    RESTORATIVE        = "Interface\\Icons\\INV_Potion_118",
    RUMSEY_RUM         = "Interface\\Icons\\INV_Drink_04",
    SHEEN_ZANZA        = "Interface\\Icons\\INV_Potion_29",
    SPIRIT_ZANZA       = "Interface\\Icons\\INV_Potion_30",
    SWIFTNESS_POT      = "Interface\\Icons\\INV_Potion_95",
    SWIFTNESS_ZANZA    = "Interface\\Icons\\INV_Potion_31",
    WINTERFALL_FW      = "Interface\\Icons\\INV_Potion_92",
    -- Items
    BAROV_CALLER       = "Interface\\Icons\\INV_Misc_Bell_01",
    -- Resistances
    RES_FIRE   = "Interface\\Icons\\Spell_Fire_FlameBolt",
    RES_FROST  = "Interface\\Icons\\Spell_Frost_FrostBolt02",
    RES_ARCANE = "Interface\\Icons\\Spell_Nature_WispSplode",
    RES_SHADOW = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
    RES_NATURE = "Interface\\Icons\\Spell_Nature_Lightning",
    FROST_OIL          = "Interface\\Icons\\INV_Potion_130",
    FROST_WEAPON       = "Interface\\Icons\\INV_Sword_34",
    MAJ_HEALTHSTONE    = "Interface\\Icons\\INV_Stone_04",
    MEDIVH_MERLOT      = "Interface\\Icons\\INV_Drink_Waterskin_05",
    MEDIVH_MERLOT_BLUE = "Interface\\Icons\\INV_Drink_Waterskin_01",
    ONYXA_CLOAK        = "Interface\\Icons\\INV_Misc_Cape_05",
}

-- ============================================================
-- Who-filter data
-- ============================================================
local ART_IC_WHO_TYPES = {
    { key="everyone",  label="Everyone"    },
    { key="class",     label="Class"       },
    { key="role",      label="Role"        },
    { key="damagecat", label="Damage Type" },
    { key="spec",      label="Spec"        },
}
local ART_IC_WHO_VALUES = {
    everyone  = { { key="*", label="Everyone" } },
    class     = {
        {key="DRUID",   label="Druid"},   {key="HUNTER",  label="Hunter"},
        {key="MAGE",    label="Mage"},    {key="PALADIN", label="Paladin"},
        {key="PRIEST",  label="Priest"},  {key="ROGUE",   label="Rogue"},
        {key="SHAMAN",  label="Shaman"},  {key="WARLOCK", label="Warlock"},
        {key="WARRIOR", label="Warrior"},
    },
    role      = {
        {key="TANK",   label="Tank"},   {key="HEALER", label="Healer"},
        {key="MELEE",  label="Melee"},  {key="CASTER", label="Caster"},
    },
    damagecat = {
        {key="ARCANE",          label="Arcane"},
        {key="FIRE",            label="Fire"},
        {key="FROST",           label="Frost"},
        {key="NATURE",          label="Nature"},
        {key="SHADOW",          label="Shadow"},
        {key="PHYSICAL_MELEE",  label="Physical Melee"},
        {key="PHYSICAL_RANGED", label="Physical Ranged"},
        {key="HYBRID_MELEE",    label="Hybrid Melee"},
    },
    spec      = {
        {key="ASSASSINATION",   label="Assassination"},  {key="BALANCE",      label="Balance"},
        {key="BEASTMASTER",     label="Beastmaster"},    {key="COMBAT",       label="Combat"},
        {key="DEEP_PROT",       label="Deep Prot"},      {key="DISCIPLINE",   label="Discipline"},
        {key="ELEMENTAL",       label="Elemental"},      {key="ENHANCEMENT",  label="Enhancement"},
        {key="FERAL_BEAR",      label="Feral Bear"},     {key="FERAL_CAT",    label="Feral Cat"},
        {key="FIRE_MAGE",       label="Fire (Mage)"},    {key="FROST_MAGE",   label="Frost (Mage)"},
        {key="FURY",            label="Fury"},           {key="HOLY_PALADIN", label="Holy (Paladin)"},
        {key="HOLY_PRIEST",     label="Holy (Priest)"},  {key="MARKSMAN",     label="Marksman"},
        {key="MORTAL_STRIKE",   label="Mortal Strike"},  {key="RESTORATION",  label="Restoration"},
        {key="RETRIBUTION",     label="Retribution"},    {key="SHADOW",       label="Shadow"},
        {key="SUBTLETY",        label="Subtlety"},       {key="SURVIVAL",     label="Survival"},
        {key="TANK_PROT",       label="Prot (Paladin)"}, {key="WARRIOR_PROT", label="Prot (Warrior)"},
    },
}

-- ============================================================
-- DB helpers
-- ============================================================
local function GetICDB()
    local db = amptieRaidToolsDB
    if not db.itemCheckProfiles then
        db.itemCheckProfiles = { ["Default"] = { rules = {} } }
    end
    if not db.activeItemCheckProfile or not db.itemCheckProfiles[db.activeItemCheckProfile] then
        db.activeItemCheckProfile = "Default"
        if not db.itemCheckProfiles["Default"] then
            db.itemCheckProfiles["Default"] = { rules = {} }
        end
    end
    return db
end

local function GetActiveProfile()
    local db = GetICDB()
    return db.itemCheckProfiles[db.activeItemCheckProfile]
end

local function GetItemName(key)
    local item = ART_IC_BY_KEY[key]
    return item and item.name or key
end

-- Build a one-line summary string for a rule's conditions
local function CondSummary(conditions)
    if not conditions or getn(conditions) == 0 then return "(no conditions)" end
    local orParts = {}
    for oi = 1, getn(conditions) do
        local grp = conditions[oi]
        local andParts = {}
        for ai = 1, getn(grp) do
            local c = grp[ai]
            tinsert(andParts, c.count .. "x " .. GetItemName(c.key))
        end
        local joined = ""
        for pi = 1, getn(andParts) do
            if pi > 1 then joined = joined .. " + " end
            joined = joined .. andParts[pi]
        end
        tinsert(orParts, joined)
    end
    local result = ""
    for pi = 1, getn(orParts) do
        if pi > 1 then result = result .. "  OR  " end
        result = result .. orParts[pi]
    end
    return result
end

local function WhoLabel(who)
    if not who or who.type == "everyone" then return "Everyone" end
    local vals = ART_IC_WHO_VALUES[who.type]
    if vals then
        for i = 1, getn(vals) do
            if vals[i].key == who.value then return vals[i].label end
        end
    end
    return who.value or "?"
end

-- ============================================================
-- Shared button / editbox factory
-- ============================================================
local function MakeBtn(parent, text, w, h)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(w); btn:SetHeight(h)
    btn:SetBackdrop(BD_PANEL)
    btn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
    btn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    fs:SetText(text)
    btn.label = fs
    return btn
end

local function MakeEditBox(parent, w, h)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetWidth(w); eb:SetHeight(h)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(32)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetTextInsets(4, 4, 0, 0)
    eb:SetBackdrop(BD_EDIT)
    eb:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    eb:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    eb:SetScript("OnEditFocusGained", function() this:SetBackdropBorderColor(1,0.82,0,0.8) end)
    eb:SetScript("OnEditFocusLost",   function() this:SetBackdropBorderColor(0.35,0.35,0.4,1) end)
    eb:SetScript("OnEscapePressed",   function() this:ClearFocus() end)
    return eb
end

-- ============================================================
-- Generic dropdown helper (shared singleton per call site)
-- Creates a scrollable dropdown list anchored to a button.
-- onSelect(key, label) is called when item clicked.
-- ============================================================
local function MakeDropdown(parent, w, maxRows)
    maxRows = maxRows or 10
    local ROW_H = 20
    local dd = {}

    -- The toggle button
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(w); btn:SetHeight(20)
    btn:SetBackdrop(BD_EDIT)
    btn:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    btn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local btnLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btnLabel:SetPoint("LEFT", btn, "LEFT", 5, 0)
    btnLabel:SetPoint("RIGHT", btn, "RIGHT", -16, 0)
    btnLabel:SetJustifyH("LEFT")
    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    arrow:SetText("v")
    arrow:SetTextColor(0.7, 0.7, 0.7, 1)

    -- The list frame — child of UIParent so it's never clipped by scroll frames
    local listH = maxRows * ROW_H + 8
    local list = CreateFrame("Frame", nil, UIParent)
    list:SetFrameStrata("TOOLTIP")
    list:SetWidth(w)
    list:SetHeight(listH)
    list:SetBackdrop(BD_PANEL)
    list:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
    list:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    list:Hide()

    -- Scroll area inside list
    local sf = CreateFrame("ScrollFrame", nil, list)
    sf:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -4, 4)

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(w - 8)
    content:SetHeight(1)
    sf:SetScrollChild(content)

    local scrollOffset = 0
    local totalRows = 0

    local function SetScroll(val)
        local maxS = math.max(content:GetHeight() - (listH - 8), 0)
        if val < 0 then val = 0 end
        if val > maxS then val = maxS end
        scrollOffset = val
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, val)
    end

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function()
        SetScroll(scrollOffset - arg1 * ROW_H * 3)
    end)

    local rowFrames = {}

    dd.selectedKey   = nil
    dd.selectedLabel = nil
    dd.onSelect      = nil

    local function Hide()
        list:Hide()
        scrollOffset = 0
        SetScroll(0)
        ART_IC_catchFrame:Hide()
    end

    local function Populate(items)
        -- items = { {key=, label=, header=true|nil}, ... }
        for i = 1, getn(rowFrames) do rowFrames[i]:Hide() end
        totalRows = getn(items)
        content:SetHeight(math.max(totalRows * ROW_H, 1))
        for i = 1, totalRows do
            local it = items[i]
            local row = rowFrames[i]
            if not row then
                row = CreateFrame("Button", nil, content)
                row:SetHeight(ROW_H)
                row:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", tile=true, tileSize=16, edgeSize=0, insets={left=0,right=0,top=0,bottom=0} })
                row:SetBackdropColor(0, 0, 0, 0)
                local rfs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                rfs:SetPoint("LEFT", row, "LEFT", 6, 0)
                rfs:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                rfs:SetJustifyH("LEFT")
                row.rfs = rfs
                tinsert(rowFrames, row)
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i-1)*ROW_H)
            row:SetPoint("RIGHT",   content, "RIGHT",   0, 0)
            row.rfs:SetText(it.label)

            if it.header then
                row:EnableMouse(false)
                row:SetBackdropColor(0, 0, 0, 0)
                row.rfs:SetTextColor(0.5, 0.5, 0.55, 1)
                row:SetScript("OnClick",  function() end)
                row:SetScript("OnEnter",  function() end)
                row:SetScript("OnLeave",  function() end)
            else
                row:EnableMouse(true)
                row.rfs:SetTextColor(1, 1, 1, 1)
                local k, l = it.key, it.label
                row:SetScript("OnClick", function()
                    dd.selectedKey   = k
                    dd.selectedLabel = l
                    btnLabel:SetText(l)
                    Hide()
                    if dd.onSelect then dd.onSelect(k, l) end
                end)
                row:SetScript("OnEnter", function()
                    this:SetBackdropColor(0.22, 0.22, 0.28, 0.9)
                    this.rfs:SetTextColor(1, 0.82, 0, 1)
                end)
                row:SetScript("OnLeave", function()
                    this:SetBackdropColor(0, 0, 0, 0)
                    this.rfs:SetTextColor(1, 1, 1, 1)
                end)
            end
            row:Show()
        end
        -- section headers (grey, non-clickable) handled via special flag
    end

    btn:SetScript("OnClick", function()
        if list:IsShown() then
            Hide()
        else
            -- close all other open dropdowns first
            for i = 1, getn(ART_IC_dropdownHiders) do
                ART_IC_dropdownHiders[i]()
            end
            list:ClearAllPoints()
            list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            list:Show()
            SetScroll(0)
            ART_IC_catchFrame:Show()
        end
    end)

    tinsert(ART_IC_dropdownHiders, Hide)

    dd.btn      = btn
    dd.list     = list
    dd.SetItems = Populate
    dd.SetValue = function(key, label)
        dd.selectedKey   = key
        dd.selectedLabel = label
        btnLabel:SetText(label or "")
    end
    dd.GetKey   = function() return dd.selectedKey end
    dd.Hide     = Hide

    return dd
end

-- ============================================================
-- Item picker dropdown (special: sections + scroll)
-- Returns a MakeDropdown-style object but with consumable/item sections
-- ============================================================
local function MakeItemDropdown(parent, w)
    local items = {}
    -- Build section-aware flat list: section headers as non-clickable entries
    local lastSec = nil
    for i = 1, getn(ART_IC_ITEMS) do
        local it = ART_IC_ITEMS[i]
        if it.sec ~= lastSec then
            lastSec = it.sec
            local label
            if it.sec == "consumable" then
                label = "── Consumables ──"
            elseif it.sec == "item" then
                label = "── Items ──"
            else
                label = "── Resistances ──"
            end
            tinsert(items, { key="__HDR__"..it.sec, label=label, header=true })
        end
        tinsert(items, { key=it.key, label=it.name })
    end

    local dd = MakeDropdown(parent, w, 12)
    dd.SetItems(items)
    return dd
end

-- ============================================================
-- Rule editor state
-- ============================================================
-- ruleEditData.conditions = array of OR-groups
-- each OR-group = array of { key=itemKey, count=number }
local ruleEditData = {
    profileName = nil,
    ruleIndex   = nil,   -- nil = new
    who         = { type="everyone", value="*" },
    conditions  = {},
}

local MAX_OR  = 4
local MAX_AND = 3

local function DeepCopyConditions(src)
    local dst = {}
    for oi = 1, getn(src) do
        local grp = {}
        for ai = 1, getn(src[oi]) do
            tinsert(grp, { key=src[oi][ai].key, count=src[oi][ai].count })
        end
        tinsert(dst, grp)
    end
    return dst
end

-- ============================================================
-- Profile Export / Import helpers
-- ============================================================
local function Split(s, sep)
    local result = {}
    local sepLen = string.len(sep)
    local i = 1
    while true do
        local j = string.find(s, sep, i, true)
        if not j then
            tinsert(result, string.sub(s, i))
            break
        end
        tinsert(result, string.sub(s, i, j - 1))
        i = j + sepLen
    end
    return result
end

local function ExportProfile(prof)
    if not prof or not prof.rules then return "v1" end
    local ruleParts = {}
    for ri = 1, getn(prof.rules) do
        local rule = prof.rules[ri]
        local who  = rule.who or { type="everyone", value="*" }
        local whoStr = (who.type or "everyone") .. "^" .. (who.value or "*")
        local orParts = {}
        for oi = 1, getn(rule.conditions or {}) do
            local grp = rule.conditions[oi]
            local andParts = {}
            for ai = 1, getn(grp) do
                tinsert(andParts, grp[ai].key .. ":" .. tostring(grp[ai].count))
            end
            local andStr = ""
            for pi = 1, getn(andParts) do
                if pi > 1 then andStr = andStr .. "+" end
                andStr = andStr .. andParts[pi]
            end
            tinsert(orParts, andStr)
        end
        local condStr = ""
        for pi = 1, getn(orParts) do
            if pi > 1 then condStr = condStr .. ";" end
            condStr = condStr .. orParts[pi]
        end
        tinsert(ruleParts, whoStr .. "^" .. condStr)
    end
    local str = "v1"
    for pi = 1, getn(ruleParts) do
        str = str .. "~" .. ruleParts[pi]
    end
    return str
end

local function ImportProfile(str)
    if not str or string.len(str) < 2 then return nil, "Empty string" end
    if string.sub(str, 1, 2) ~= "v1" then return nil, "Unknown format (expected v1...)" end
    local body = string.sub(str, 3)   -- everything after "v1"
    local rules = {}
    if body == "" then return { rules = rules } end
    if string.sub(body, 1, 1) ~= "~" then return nil, "Malformed string" end
    body = string.sub(body, 2)        -- skip leading ~
    local ruleParts = Split(body, "~")
    for ri = 1, getn(ruleParts) do
        local ruleStr = ruleParts[ri]
        if ruleStr ~= "" then
            local fields = Split(ruleStr, "^")
            if getn(fields) < 2 then return nil, "Malformed rule " .. ri end
            local whoType  = fields[1]
            local whoValue = fields[2]
            local condStr  = fields[3] or ""
            -- validate whoType
            local validType = false
            for wi = 1, getn(ART_IC_WHO_TYPES) do
                if ART_IC_WHO_TYPES[wi].key == whoType then validType = true; break end
            end
            if not validType then whoType = "everyone"; whoValue = "*" end
            local conditions = {}
            if condStr ~= "" then
                local orStrs = Split(condStr, ";")
                for oi = 1, getn(orStrs) do
                    local orStr = orStrs[oi]
                    if orStr ~= "" then
                        local grp = {}
                        local andStrs = Split(orStr, "+")
                        for ai = 1, getn(andStrs) do
                            local kc    = Split(andStrs[ai], ":")
                            local key   = kc[1] or ""
                            local count = tonumber(kc[2]) or 1
                            if key ~= "" and ART_IC_BY_KEY[key] then
                                tinsert(grp, { key=key, count=count })
                            end
                        end
                        if getn(grp) > 0 then tinsert(conditions, grp) end
                    end
                end
            end
            tinsert(rules, { who={ type=whoType, value=whoValue }, conditions=conditions })
        end
    end
    return { rules = rules }
end

-- ============================================================
-- AmptieRaidTools_InitItemChecks
-- ============================================================
function AmptieRaidTools_InitItemChecks(body)
    local panel = CreateFrame("Frame", "ART_ICPanel", body)
    panel:SetAllPoints(body)
    panel:Hide()
    AmptieRaidTools_RegisterComponent("itemchecks", panel)

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    title:SetText("Item Checks")
    title:SetTextColor(1, 0.82, 0, 1)

    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    sub:SetText("Define per-role consumable requirements for raid members.")
    sub:SetTextColor(0.65, 0.65, 0.7, 1)

    -- Horizontal divider
    local hdiv = panel:CreateTexture(nil, "ARTWORK")
    hdiv:SetHeight(1)
    hdiv:SetPoint("TOPLEFT",  sub, "BOTTOMLEFT",  0, -6)
    hdiv:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, 0)
    hdiv:SetTexture(0.25, 0.25, 0.28, 0.8)

    -- Vertical divider between profile list and rules
    local vdiv = panel:CreateTexture(nil, "ARTWORK")
    vdiv:SetWidth(1)
    vdiv:SetPoint("TOP",    hdiv,  "BOTTOMLEFT", 190, 0)
    vdiv:SetPoint("BOTTOM", panel, "BOTTOMLEFT", 190, 6)
    vdiv:SetTexture(0.25, 0.25, 0.28, 0.8)

    local PANEL_TOP_Y = -50   -- below hdiv approx
    local LEFT_W  = 182
    local RIGHT_X = 198
    local RIGHT_W = 420

    -- ── Profile list (left panel) ────────────────────────────────
    local profHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profHdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, PANEL_TOP_Y)
    profHdr:SetText("Profiles")
    profHdr:SetTextColor(0.9, 0.75, 0.2, 1)

    -- Active profile label
    local activeProfLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    activeProfLabel:SetPoint("TOPLEFT", profHdr, "BOTTOMLEFT", 0, -3)
    activeProfLabel:SetWidth(LEFT_W)
    activeProfLabel:SetJustifyH("LEFT")
    activeProfLabel:SetTextColor(0.5, 0.8, 0.5, 1)

    -- Profile scroll area
    local profSF = CreateFrame("ScrollFrame", nil, panel)
    profSF:SetPoint("TOPLEFT",     activeProfLabel, "BOTTOMLEFT", 0, -4)
    profSF:SetPoint("BOTTOMLEFT",  panel, "BOTTOMLEFT", 8, 86)
    profSF:SetWidth(LEFT_W)

    local profContent = CreateFrame("Frame", nil, profSF)
    profContent:SetWidth(LEFT_W)
    profContent:SetHeight(1)
    profSF:SetScrollChild(profContent)

    local profScrollOffset = 0
    local PROF_ROW_H = 24

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
    local profNameEdit = nil   -- forward ref

    local function RefreshProfileList()
        local db = GetICDB()
        local active = db.activeItemCheckProfile
        activeProfLabel:SetText("Active: " .. (active or "--"))

        -- collect and sort profile names
        local names = {}
        for n in pairs(db.itemCheckProfiles) do tinsert(names, n) end
        table.sort(names)

        for i = 1, getn(profRows) do profRows[i]:Hide() end
        profContent:SetHeight(math.max(getn(names) * PROF_ROW_H, 1))

        for i = 1, getn(names) do
            local n = names[i]
            local row = profRows[i]
            if not row then
                row = CreateFrame("Button", nil, profContent)
                row:SetHeight(PROF_ROW_H)
                row:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", tile=true, tileSize=16, edgeSize=0, insets={left=0,right=0,top=0,bottom=0} })
                row:SetBackdropColor(0, 0, 0, 0)
                local rfs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                rfs:SetPoint("LEFT", row, "LEFT", 6, 0)
                rfs:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                rfs:SetJustifyH("LEFT")
                row.rfs = rfs
                row:SetScript("OnEnter", function()
                    local db2 = GetICDB()
                    if row.pname ~= db2.activeItemCheckProfile then
                        this:SetBackdropColor(0.18, 0.18, 0.22, 0.9)
                    end
                end)
                row:SetScript("OnLeave", function()
                    local db2 = GetICDB()
                    if row.pname ~= db2.activeItemCheckProfile then
                        this:SetBackdropColor(0, 0, 0, 0)
                    end
                end)
                tinsert(profRows, row)
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", profContent, "TOPLEFT", 0, -(i-1)*PROF_ROW_H)
            row:SetPoint("RIGHT", profContent, "RIGHT", 0, 0)
            row.pname = n
            row.rfs:SetText(n)
            if n == active then
                row:SetBackdropColor(0.18, 0.22, 0.18, 0.9)
                row.rfs:SetTextColor(0.5, 1, 0.5, 1)
            else
                row:SetBackdropColor(0, 0, 0, 0)
                row.rfs:SetTextColor(0.85, 0.85, 0.85, 1)
            end
            local pname = n
            row:SetScript("OnClick", function()
                GetICDB().activeItemCheckProfile = pname
                RefreshProfileList()
                -- RefreshRuleList is defined below; called via forward ref
                if _ART_IC_RefreshRules then _ART_IC_RefreshRules() end
            end)
            row:Show()
        end
    end

    -- New / Delete / Export / Import buttons at bottom of left panel
    -- Row 1 (bottom): Export · Import
    local expBtn = MakeBtn(panel, "Export", 80, 22)
    expBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)

    local impBtn = MakeBtn(panel, "Import", 80, 22)
    impBtn:SetPoint("LEFT", expBtn, "RIGHT", 4, 0)

    -- Row 2: Rename (full width)
    local renameBtn = MakeBtn(panel, "Rename", 164, 22)
    renameBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 34)

    -- Row 3: New · Delete
    local newProfBtn = MakeBtn(panel, "+ New", 80, 22)
    newProfBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 60)

    local delProfBtn = MakeBtn(panel, "Delete", 80, 22)
    delProfBtn:SetPoint("LEFT", newProfBtn, "RIGHT", 4, 0)

    -- Inline name editbox (hidden until New is clicked)
    local newProfEdit = MakeEditBox(panel, LEFT_W, 22)
    newProfEdit:SetPoint("BOTTOM", newProfBtn, "TOP", 0, 4)
    newProfEdit:SetMaxLetters(40)
    newProfEdit:Hide()

    -- Inline rename editbox (hidden until Rename is clicked)
    local renameProfEdit = MakeEditBox(UIParent, 164, 22)
    renameProfEdit:SetFrameStrata("FULLSCREEN_DIALOG")
    renameProfEdit:SetPoint("BOTTOM", renameBtn, "TOP", 0, 4)
    renameProfEdit:SetMaxLetters(40)
    renameProfEdit:Hide()

    newProfBtn:SetScript("OnClick", function()
        newProfEdit:Show()
        newProfEdit:SetText("")
        newProfEdit:SetFocus()
    end)

    newProfEdit:SetScript("OnEnterPressed", function()
        local name = this:GetText()
        if name and name ~= "" then
            local db = GetICDB()
            if not db.itemCheckProfiles[name] then
                db.itemCheckProfiles[name] = { rules = {} }
            end
            db.activeItemCheckProfile = name
            this:Hide()
            RefreshProfileList()
            if _ART_IC_RefreshRules then _ART_IC_RefreshRules() end
        end
        this:ClearFocus()
    end)
    newProfEdit:SetScript("OnEscapePressed", function()
        this:Hide()
        this:ClearFocus()
    end)

    delProfBtn:SetScript("OnClick", function()
        local db = GetICDB()
        local active = db.activeItemCheckProfile
        if active == "Default" then return end  -- protect default
        db.itemCheckProfiles[active] = nil
        db.activeItemCheckProfile = "Default"
        if not db.itemCheckProfiles["Default"] then
            db.itemCheckProfiles["Default"] = { rules = {} }
        end
        RefreshProfileList()
        if _ART_IC_RefreshRules then _ART_IC_RefreshRules() end
    end)

    renameBtn:SetScript("OnClick", function()
        local db = GetICDB()
        if db.activeItemCheckProfile == "Default" then return end  -- protect default
        renameProfEdit:SetText(db.activeItemCheckProfile)
        renameProfEdit:Show()
        renameProfEdit:SetFocus()
        renameProfEdit:HighlightText()
    end)

    renameProfEdit:SetScript("OnEnterPressed", function()
        local newName = this:GetText()
        local db = GetICDB()
        local oldName = db.activeItemCheckProfile
        if newName and newName ~= "" and newName ~= oldName then
            if not db.itemCheckProfiles[newName] then
                db.itemCheckProfiles[newName] = db.itemCheckProfiles[oldName]
                db.itemCheckProfiles[oldName] = nil
                db.activeItemCheckProfile = newName
                RefreshProfileList()
                if _ART_IC_RefreshRules then _ART_IC_RefreshRules() end
            end
        end
        this:Hide()
        this:ClearFocus()
    end)
    renameProfEdit:SetScript("OnEscapePressed", function()
        this:Hide()
        this:ClearFocus()
    end)

    -- ── Share modal (Export / Import) ────────────────────────────
    local shareModal = CreateFrame("Frame", nil, UIParent)
    shareModal:SetAllPoints(UIParent)
    shareModal:SetFrameStrata("FULLSCREEN_DIALOG")
    shareModal:SetBackdrop({
        bgFile  = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true, tileSize = 16, edgeSize = 0,
        insets  = { left=0, right=0, top=0, bottom=0 },
    })
    shareModal:SetBackdropColor(0, 0, 0, 0.60)
    shareModal:EnableMouse(true)
    shareModal:Hide()

    local smInner = CreateFrame("Frame", nil, shareModal)
    smInner:SetWidth(500)
    smInner:SetHeight(140)
    smInner:SetPoint("CENTER", shareModal, "CENTER", 0, 0)
    smInner:SetBackdrop(BD_PANEL)
    smInner:SetBackdropColor(0.08, 0.08, 0.12, 0.98)
    smInner:SetBackdropBorderColor(0.5, 0.42, 0.15, 1)

    local smTitle = smInner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    smTitle:SetPoint("TOPLEFT", smInner, "TOPLEFT", 10, -10)
    smTitle:SetTextColor(1, 0.82, 0, 1)

    local smDesc = smInner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    smDesc:SetPoint("TOPLEFT", smTitle, "BOTTOMLEFT", 0, -4)
    smDesc:SetTextColor(0.65, 0.65, 0.70, 1)

    local smEB = CreateFrame("EditBox", nil, smInner)
    smEB:SetHeight(22)
    smEB:SetPoint("TOPLEFT",  smDesc,  "BOTTOMLEFT", 0, -6)
    smEB:SetPoint("RIGHT",    smInner, "RIGHT",     -10,  0)
    smEB:SetAutoFocus(false)
    smEB:SetMaxLetters(0)
    smEB:SetFontObject(GameFontHighlightSmall)
    smEB:SetTextInsets(4, 4, 0, 0)
    smEB:SetBackdrop(BD_EDIT)
    smEB:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    smEB:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    smEB:SetScript("OnEditFocusGained", function() this:SetBackdropBorderColor(1, 0.82, 0, 0.8) end)
    smEB:SetScript("OnEditFocusLost",   function() this:SetBackdropBorderColor(0.35, 0.35, 0.4, 1) end)
    smEB:SetScript("OnEscapePressed",   function() shareModal:Hide() end)

    local smStatus = smInner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    smStatus:SetPoint("TOPLEFT", smEB, "BOTTOMLEFT", 0, -4)
    smStatus:SetPoint("RIGHT", smInner, "RIGHT", -10, 0)
    smStatus:SetJustifyH("LEFT")
    smStatus:SetText("")

    local smCloseBtn = MakeBtn(smInner, "Close", 80, 22)
    smCloseBtn:SetPoint("BOTTOMRIGHT", smInner, "BOTTOMRIGHT", -10, 10)
    smCloseBtn:SetScript("OnClick", function() shareModal:Hide() end)

    local smImportBtn = MakeBtn(smInner, "Import", 90, 22)
    smImportBtn:SetPoint("RIGHT", smCloseBtn, "LEFT", -6, 0)
    smImportBtn:Hide()

    expBtn:SetScript("OnClick", function()
        smTitle:SetText("Export Profile")
        smDesc:SetText("Text is pre-selected — press Ctrl+C to copy:")
        smStatus:SetText("")
        smImportBtn:Hide()
        local exportStr = ExportProfile(GetActiveProfile())
        smEB:SetText(exportStr)
        shareModal:Show()
        smEB:SetFocus()
        smEB:HighlightText()
    end)

    impBtn:SetScript("OnClick", function()
        smTitle:SetText("Import Profile")
        smDesc:SetText("Paste a profile string below and click Import:")
        smStatus:SetText("")
        smEB:SetText("")
        smImportBtn:Show()
        shareModal:Show()
        smEB:SetFocus()
    end)

    smImportBtn:SetScript("OnClick", function()
        local str = smEB:GetText()
        local prof, err = ImportProfile(str)
        if not prof then
            smStatus:SetTextColor(1, 0.4, 0.4, 1)
            smStatus:SetText("Error: " .. (err or "unknown"))
            return
        end
        local db = GetICDB()
        local baseName = "Imported"
        local name = baseName
        local n = 1
        while db.itemCheckProfiles[name] do
            n = n + 1
            name = baseName .. " " .. n
        end
        db.itemCheckProfiles[name] = prof
        db.activeItemCheckProfile  = name
        shareModal:Hide()
        RefreshProfileList()
        if _ART_IC_RefreshRules then _ART_IC_RefreshRules() end
    end)

    -- ── Rules panel (right side) ─────────────────────────────────
    local rulesPanel = CreateFrame("Frame", nil, panel)
    rulesPanel:SetPoint("TOPLEFT",    panel, "TOPLEFT", RIGHT_X, PANEL_TOP_Y)
    rulesPanel:SetPoint("BOTTOMRIGHT",panel, "BOTTOMRIGHT", -8, 8)

    local rulesHdr = rulesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rulesHdr:SetPoint("TOPLEFT", rulesPanel, "TOPLEFT", 0, 0)
    rulesHdr:SetText("Rules")
    rulesHdr:SetTextColor(0.9, 0.75, 0.2, 1)

    local addRuleBtn = MakeBtn(rulesPanel, "+ Add Rule", 90, 22)
    addRuleBtn:SetPoint("TOPRIGHT", rulesPanel, "TOPRIGHT", 0, 0)

    -- Scroll for rule rows
    local rulesSF = CreateFrame("ScrollFrame", nil, rulesPanel)
    rulesSF:SetPoint("TOPLEFT",     rulesHdr,   "BOTTOMLEFT",  0, -4)
    rulesSF:SetPoint("BOTTOMRIGHT", rulesPanel,  "BOTTOMRIGHT", 0, 0)

    local rulesContent = CreateFrame("Frame", nil, rulesSF)
    rulesContent:SetWidth(RIGHT_W)
    rulesContent:SetHeight(1)
    rulesSF:SetScrollChild(rulesContent)

    local rulesScrollOffset = 0
    local RULE_ROW_H = 30

    local function SetRulesScroll(val)
        local maxS = math.max(rulesContent:GetHeight() - rulesSF:GetHeight(), 0)
        if val < 0 then val = 0 end
        if val > maxS then val = maxS end
        rulesScrollOffset = val
        rulesContent:ClearAllPoints()
        rulesContent:SetPoint("TOPLEFT", rulesSF, "TOPLEFT", 0, val)
    end

    rulesSF:EnableMouseWheel(true)
    rulesSF:SetScript("OnMouseWheel", function()
        SetRulesScroll(rulesScrollOffset - arg1 * RULE_ROW_H * 2)
    end)

    local ruleRows = {}

    -- Rule editor overlay (defined below, forward-referenced)
    local editorPanel  -- assigned after creation

    local function RefreshRuleList()
        local db  = GetICDB()
        rulesHdr:SetText("Rules  —  " .. (db.activeItemCheckProfile or "--"))
        local prof = GetActiveProfile()
        local rules = prof and prof.rules or {}

        for i = 1, getn(ruleRows) do ruleRows[i]:Hide() end
        if getn(rules) == 0 then
            rulesContent:SetHeight(40)
            if not rulesPanel.emptyLabel then
                rulesPanel.emptyLabel = rulesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                rulesPanel.emptyLabel:SetPoint("TOPLEFT", rulesSF, "TOPLEFT", 4, -8)
                rulesPanel.emptyLabel:SetTextColor(0.5, 0.5, 0.5, 1)
            end
            rulesPanel.emptyLabel:SetText("No rules yet. Click '+ Add Rule' to create one.")
            rulesPanel.emptyLabel:Show()
            return
        end
        if rulesPanel.emptyLabel then rulesPanel.emptyLabel:Hide() end

        rulesContent:SetHeight(math.max(getn(rules) * RULE_ROW_H + 4, 1))

        for i = 1, getn(rules) do
            local rule = rules[i]
            local row  = ruleRows[i]
            if not row then
                row = CreateFrame("Frame", nil, rulesContent)
                row:SetHeight(RULE_ROW_H)
                row:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", tile=true, tileSize=16, edgeSize=0, insets={left=0,right=0,top=0,bottom=0} })
                row.whoFS  = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.whoFS:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.whoFS:SetWidth(80)
                row.whoFS:SetJustifyH("LEFT")
                row.whoFS:SetTextColor(0.6, 0.85, 1, 1)

                row.condFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.condFS:SetPoint("LEFT", row.whoFS, "RIGHT", 6, 0)
                row.condFS:SetWidth(220)
                row.condFS:SetJustifyH("LEFT")
                row.condFS:SetTextColor(0.85, 0.85, 0.85, 1)

                row.editBtn = MakeBtn(row, "Edit", 44, 20)
                row.editBtn:SetPoint("RIGHT", row, "RIGHT", -52, 0)

                row.delBtn  = MakeBtn(row, "Del", 44, 20)
                row.delBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                row.delBtn.label:SetTextColor(1, 0.4, 0.4, 1)

                tinsert(ruleRows, row)
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", rulesContent, "TOPLEFT", 0, -(i-1)*RULE_ROW_H - 2)
            row:SetPoint("RIGHT",   rulesContent,  "RIGHT",  0, 0)
            if math.mod(i, 2) == 0 then
                row:SetBackdropColor(0.1, 0.1, 0.12, 0.5)
            else
                row:SetBackdropColor(0.07, 0.07, 0.09, 0.3)
            end
            row.whoFS:SetText(WhoLabel(rule.who))
            row.condFS:SetText(CondSummary(rule.conditions))

            local ruleIdx = i
            row.editBtn:SetScript("OnClick", function()
                local prof2 = GetActiveProfile()
                local r2 = prof2 and prof2.rules and prof2.rules[ruleIdx]
                if not r2 then return end
                ruleEditData.profileName = GetICDB().activeItemCheckProfile
                ruleEditData.ruleIndex   = ruleIdx
                ruleEditData.who         = { type=r2.who.type, value=r2.who.value }
                ruleEditData.conditions  = DeepCopyConditions(r2.conditions or {})
                rulesPanel:Hide()
                editorPanel:Show()
                if _ART_IC_RefreshEditor then _ART_IC_RefreshEditor() end
            end)
            row.delBtn:SetScript("OnClick", function()
                local prof2 = GetActiveProfile()
                if prof2 and prof2.rules then
                    table.remove(prof2.rules, ruleIdx)
                    RefreshRuleList()
                end
            end)
            row:Show()
        end
    end

    -- expose for cross-reference
    _ART_IC_RefreshRules = RefreshRuleList

    addRuleBtn:SetScript("OnClick", function()
        ruleEditData.profileName = GetICDB().activeItemCheckProfile
        ruleEditData.ruleIndex   = nil
        ruleEditData.who         = { type="everyone", value="*" }
        ruleEditData.conditions  = { { { key="FLASK_TITANS", count=1 } } }
        rulesPanel:Hide()
        editorPanel:Show()
        if _ART_IC_RefreshEditor then _ART_IC_RefreshEditor() end
    end)

    -- ── Rule editor overlay ──────────────────────────────────────
    editorPanel = CreateFrame("Frame", nil, panel)
    editorPanel:SetPoint("TOPLEFT",    panel, "TOPLEFT", RIGHT_X, PANEL_TOP_Y)
    editorPanel:SetPoint("BOTTOMRIGHT",panel, "BOTTOMRIGHT", -8, 8)
    editorPanel:Hide()

    local edHdr = editorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    edHdr:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 0, 0)
    edHdr:SetTextColor(0.9, 0.75, 0.2, 1)

    -- Cancel button (top right)
    local cancelBtn = MakeBtn(editorPanel, "Cancel", 70, 22)
    cancelBtn:SetPoint("TOPRIGHT", editorPanel, "TOPRIGHT", 0, 0)
    cancelBtn:SetScript("OnClick", function()
        editorPanel:Hide()
        rulesPanel:Show()
        RefreshRuleList()
    end)

    local saveBtn = MakeBtn(editorPanel, "Save Rule", 80, 22)
    saveBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -6, 0)
    saveBtn.label:SetTextColor(0.5, 1, 0.5, 1)

    -- WHO section
    local whoHdr = editorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    whoHdr:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 0, -28)
    whoHdr:SetText("Who")
    whoHdr:SetTextColor(0.9, 0.75, 0.2, 1)

    local whoTypeDd  = MakeDropdown(editorPanel, 110, 6)
    whoTypeDd.btn:SetPoint("TOPLEFT", whoHdr, "BOTTOMLEFT", 0, -4)

    local whoValueDd = MakeDropdown(editorPanel, 150, 10)
    whoValueDd.btn:SetPoint("LEFT", whoTypeDd.btn, "RIGHT", 6, 0)

    -- Populate who-type dropdown
    local whoTypeItems = {}
    for i = 1, getn(ART_IC_WHO_TYPES) do
        tinsert(whoTypeItems, { key=ART_IC_WHO_TYPES[i].key, label=ART_IC_WHO_TYPES[i].label })
    end
    whoTypeDd.SetItems(whoTypeItems)

    local function PopulateWhoValues(typeKey)
        local vals = ART_IC_WHO_VALUES[typeKey] or ART_IC_WHO_VALUES.everyone
        local items = {}
        for i = 1, getn(vals) do
            tinsert(items, { key=vals[i].key, label=vals[i].label })
        end
        whoValueDd.SetItems(items)
        -- Do NOT auto-select here; caller is responsible for setting the displayed value
        if typeKey == "everyone" then
            whoValueDd.btn:Hide()
        else
            whoValueDd.btn:Show()
        end
    end

    whoTypeDd.onSelect = function(key, label)
        ruleEditData.who.type = key
        PopulateWhoValues(key)
        -- Reset value to first option only when the TYPE changes
        local vals = ART_IC_WHO_VALUES[key] or ART_IC_WHO_VALUES.everyone
        if getn(vals) > 0 then
            whoValueDd.SetValue(vals[1].key, vals[1].label)
            ruleEditData.who.value = vals[1].key
        end
    end

    whoValueDd.onSelect = function(key, label)
        ruleEditData.who.value = key
    end

    -- CONDITIONS section
    local condHdr = editorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    condHdr:SetPoint("TOPLEFT", whoTypeDd.btn, "BOTTOMLEFT", 0, -14)
    condHdr:SetText("Conditions  (OR groups / AND items within group)")
    condHdr:SetTextColor(0.9, 0.75, 0.2, 1)

    -- Scrollable conditions area
    local condSF = CreateFrame("ScrollFrame", nil, editorPanel)
    condSF:SetPoint("TOPLEFT",     condHdr,       "BOTTOMLEFT", 0, -4)
    condSF:SetPoint("BOTTOMRIGHT", editorPanel,   "BOTTOMRIGHT", 0, 34)

    local condContent = CreateFrame("Frame", nil, condSF)
    condContent:SetWidth(RIGHT_W)
    condContent:SetHeight(1)
    condSF:SetScrollChild(condContent)

    local condScrollOffset = 0
    local function SetCondScroll(val)
        local maxS = math.max(condContent:GetHeight() - condSF:GetHeight(), 0)
        if val < 0 then val = 0 end
        if val > maxS then val = maxS end
        condScrollOffset = val
        condContent:ClearAllPoints()
        condContent:SetPoint("TOPLEFT", condSF, "TOPLEFT", 0, val)
    end
    condSF:EnableMouseWheel(true)
    condSF:SetScript("OnMouseWheel", function()
        SetCondScroll(condScrollOffset - arg1 * 26 * 2)
    end)

    -- Save rule logic
    saveBtn:SetScript("OnClick", function()
        local db  = GetICDB()
        local pname = ruleEditData.profileName
        if not pname or not db.itemCheckProfiles[pname] then return end
        local prof = db.itemCheckProfiles[pname]
        if not prof.rules then prof.rules = {} end

        local newRule = {
            who        = { type=ruleEditData.who.type, value=ruleEditData.who.value },
            conditions = DeepCopyConditions(ruleEditData.conditions),
        }
        if ruleEditData.ruleIndex then
            prof.rules[ruleEditData.ruleIndex] = newRule
        else
            tinsert(prof.rules, newRule)
        end

        editorPanel:Hide()
        rulesPanel:Show()
        RefreshRuleList()
    end)

    -- Pre-allocated OR group blocks
    -- Each block: OR separator label, up to 3 AND rows (itemDD + countEB + removeBtn), AND labels, +AND btn
    local orBlocks = {}
    local COND_ROW_H = 26
    local COND_OR_H  = 20
    local COND_AND_H = 16

    local function BuildOrBlocks()
        -- Build all pre-allocated frames (once)
        for oi = 1, MAX_OR do
            local blk = {}
            blk.orSep = condContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            blk.orSep:SetText("── OR ──────────────────────────")
            blk.orSep:SetTextColor(0.5, 0.5, 0.55, 1)

            blk.andRows = {}
            for ai = 1, MAX_AND do
                local oi_c = oi   -- stable captures for all closures in this iteration
                local ai_c = ai
                local row = {}
                row.andLabel = condContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.andLabel:SetText("AND")
                row.andLabel:SetTextColor(0.5, 0.65, 1, 1)

                row.itemDD = MakeItemDropdown(condContent, 200)
                row.itemDD.onSelect = function(key, label)
                    if string.find(key, "^__HDR__") then return end
                    if ruleEditData.conditions[oi_c] then
                        if ruleEditData.conditions[oi_c][ai_c] then
                            ruleEditData.conditions[oi_c][ai_c].key = key
                        end
                    end
                end

                row.countEB = MakeEditBox(condContent, 45, 22)
                row.countEB:SetNumeric(true)
                row.countEB:SetMaxLetters(3)
                row.countEB:SetScript("OnTextChanged", function()
                    local val = tonumber(this:GetText()) or 1
                    if ruleEditData.conditions[oi_c] and ruleEditData.conditions[oi_c][ai_c] then
                        ruleEditData.conditions[oi_c][ai_c].count = val
                    end
                end)
                row.countEB:SetScript("OnEnterPressed", function() this:ClearFocus() end)

                row.removeBtn = MakeBtn(condContent, "x", 22, 22)
                row.removeBtn.label:SetTextColor(1, 0.4, 0.4, 1)
                row.removeBtn:SetScript("OnClick", function()
                    local grp = ruleEditData.conditions[oi_c]
                    if grp and getn(grp) > 1 then
                        table.remove(grp, ai_c)
                        if _ART_IC_RefreshEditor then _ART_IC_RefreshEditor() end
                    end
                end)

                tinsert(blk.andRows, row)
            end

            blk.addAndBtn = MakeBtn(condContent, "+ AND item", 90, 20)
            blk.addAndBtn.label:SetTextColor(0.5, 0.8, 1, 1)
            local oi2 = oi
            blk.addAndBtn:SetScript("OnClick", function()
                local grp = ruleEditData.conditions[oi2]
                if grp and getn(grp) < MAX_AND then
                    tinsert(grp, { key="FLASK_TITANS", count=1 })
                    if _ART_IC_RefreshEditor then _ART_IC_RefreshEditor() end
                end
            end)

            blk.removeGrpBtn = MakeBtn(condContent, "Remove OR", 80, 20)
            blk.removeGrpBtn.label:SetTextColor(1, 0.4, 0.4, 1)
            local oi3 = oi
            blk.removeGrpBtn:SetScript("OnClick", function()
                if getn(ruleEditData.conditions) > 1 then
                    table.remove(ruleEditData.conditions, oi3)
                    if _ART_IC_RefreshEditor then _ART_IC_RefreshEditor() end
                end
            end)

            tinsert(orBlocks, blk)
        end
    end
    BuildOrBlocks()

    local addOrBtn = MakeBtn(condContent, "+ OR group", 90, 20)
    addOrBtn.label:SetTextColor(1, 0.75, 0.3, 1)
    addOrBtn:SetScript("OnClick", function()
        if getn(ruleEditData.conditions) < MAX_OR then
            tinsert(ruleEditData.conditions, { { key="FLASK_TITANS", count=1 } })
            if _ART_IC_RefreshEditor then _ART_IC_RefreshEditor() end
        end
    end)

    -- Rebuild editor UI from ruleEditData
    local function RefreshEditor()
        edHdr:SetText(ruleEditData.ruleIndex and "Edit Rule" or "New Rule")

        -- Who
        whoTypeDd.SetValue(ruleEditData.who.type, "")
        for i = 1, getn(ART_IC_WHO_TYPES) do
            if ART_IC_WHO_TYPES[i].key == ruleEditData.who.type then
                whoTypeDd.SetValue(ruleEditData.who.type, ART_IC_WHO_TYPES[i].label)
                break
            end
        end
        PopulateWhoValues(ruleEditData.who.type)
        local vals = ART_IC_WHO_VALUES[ruleEditData.who.type] or ART_IC_WHO_VALUES.everyone
        for i = 1, getn(vals) do
            if vals[i].key == ruleEditData.who.value then
                whoValueDd.SetValue(vals[i].key, vals[i].label)
                break
            end
        end

        -- Hide all OR blocks
        for oi = 1, MAX_OR do
            local blk = orBlocks[oi]
            blk.orSep:Hide()
            blk.addAndBtn:Hide()
            blk.removeGrpBtn:Hide()
            for ai = 1, MAX_AND do
                blk.andRows[ai].andLabel:Hide()
                blk.andRows[ai].itemDD.btn:Hide()
                blk.andRows[ai].itemDD.list:Hide()
                blk.andRows[ai].countEB:Hide()
                blk.andRows[ai].removeBtn:Hide()
            end
        end
        addOrBtn:Hide()

        -- Layout conditions
        local curY = 0
        local numOr = getn(ruleEditData.conditions)
        for oi = 1, numOr do
            local blk = orBlocks[oi]
            local grp  = ruleEditData.conditions[oi]

            if oi > 1 then
                blk.orSep:ClearAllPoints()
                blk.orSep:SetPoint("TOPLEFT", condContent, "TOPLEFT", 0, -curY)
                blk.orSep:Show()
                curY = curY + COND_OR_H
            end

            local numAnd = getn(grp)
            for ai = 1, numAnd do
                local row = blk.andRows[ai]
                local cond = grp[ai]

                if ai > 1 then
                    row.andLabel:ClearAllPoints()
                    row.andLabel:SetPoint("TOPLEFT", condContent, "TOPLEFT", 4, -curY)
                    row.andLabel:Show()
                    curY = curY + COND_AND_H
                end

                -- item DD button
                row.itemDD.btn:ClearAllPoints()
                row.itemDD.btn:SetPoint("TOPLEFT", condContent, "TOPLEFT", 0, -curY)
                row.itemDD.btn:Show()

                -- set current item label
                local itemInfo = ART_IC_BY_KEY[cond.key]
                local itemLabel = itemInfo and itemInfo.name or cond.key
                row.itemDD.SetValue(cond.key, itemLabel)

                row.countEB:ClearAllPoints()
                row.countEB:SetPoint("LEFT", row.itemDD.btn, "RIGHT", 6, 0)
                row.countEB:SetText(tostring(cond.count or 1))
                row.countEB:Show()

                row.removeBtn:ClearAllPoints()
                row.removeBtn:SetPoint("LEFT", row.countEB, "RIGHT", 4, 0)
                row.removeBtn:Show()

                curY = curY + COND_ROW_H
            end

            -- +AND btn
            if numAnd < MAX_AND then
                blk.addAndBtn:ClearAllPoints()
                blk.addAndBtn:SetPoint("TOPLEFT", condContent, "TOPLEFT", 0, -curY)
                blk.addAndBtn:Show()
            end

            -- Remove group btn
            if numOr > 1 then
                blk.removeGrpBtn:ClearAllPoints()
                blk.removeGrpBtn:SetPoint("LEFT", blk.addAndBtn, "RIGHT", 6, 0)
                blk.removeGrpBtn:Show()
            end

            curY = curY + 24
        end

        -- +OR btn
        if numOr < MAX_OR then
            addOrBtn:ClearAllPoints()
            addOrBtn:SetPoint("TOPLEFT", condContent, "TOPLEFT", 0, -curY)
            addOrBtn:Show()
            curY = curY + 26
        end

        condContent:SetHeight(math.max(curY, 40))
        SetCondScroll(0)
    end
    _ART_IC_RefreshEditor = RefreshEditor

    -- Close all dropdowns when panel or editor hides (e.g. Escape key)
    local function HideAllDropdowns()
        for i = 1, getn(ART_IC_dropdownHiders) do
            ART_IC_dropdownHiders[i]()
        end
    end
    panel:SetScript("OnHide", function()
        HideAllDropdowns()
        shareModal:Hide()
        renameProfEdit:Hide()
        renameProfEdit:ClearFocus()
    end)
    editorPanel:SetScript("OnHide", HideAllDropdowns)

    -- ── Final init ──────────────────────────────────────────────
    GetICDB()  -- ensure defaults exist
    RefreshProfileList()
    RefreshRuleList()
end

-- ============================================================
-- Item Check Protocol
-- Prefix: "ART_IC"
-- Leader sends rules via addon messages; each player evaluates
-- their own inventory and responds with missing items.
-- ============================================================
local IC_PREFIX = "ART_IC"

-- Session state
local icCheckId      = nil   -- check ID currently active (as leader)
local icCheckResults = {}    -- [playerName] = { missing={key→have}, done=bool }
local icNotifyRefresh = nil  -- callback: called when results change

-- Receiver state (building rules from incoming messages)
local icRcvCheckId = nil
local icRcvRules   = {}

-- Sub-role → IC damagecat key
local IC_SUBROLE_TO_CAT = {
    ["Fire Damage"]    = "FIRE",
    ["Frost Damage"]   = "FROST",
    ["Nature Damage"]  = "NATURE",
    ["Shadow Damage"]  = "SHADOW",
    ["Arcane Damage"]  = "ARCANE",
    ["Holy Damage"]    = "ARCANE",
    ["Close-up Melee"] = "PHYSICAL_MELEE",
    ["Ranged Melee"]   = "PHYSICAL_RANGED",
    ["Hybrid Melee"]   = "HYBRID_MELEE",
    ["Tank"]           = "PHYSICAL_MELEE",
}

-- IC role key → broad role string
local IC_ROLE_KEY_TO_BROAD = {
    TANK   = "Tank",
    HEALER = "Healer",
    MELEE  = "Melee",
    CASTER = "Caster",
}

local function GetICMsgChannel()
    if GetNumRaidMembers() > 0 then return "RAID"  end
    if GetNumPartyMembers() > 0 then return "PARTY" end
    return nil
end

-- Count items in all bags by item ID
local function GetItemCountInBags(itemId)
    local count = 0
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, idStr = string.find(link, "item:(%d+):")
                if idStr and tonumber(idStr) == itemId then
                    local _, stackCount = GetContainerItemInfo(bag, slot)
                    count = count + math.abs(stackCount or 1)
                end
            end
        end
    end
    return count
end

-- Does the local player match a rule's who-filter?
local function PlayerMatchesWho(who)
    if not who or who.type == "everyone" then return true end
    local t = who.type
    local v = who.value
    if t == "class" then
        local _, cl = UnitClass("player")
        local myClass = cl and string.upper(cl) or ""
        return myClass == v
    elseif t == "role" then
        local mySpec = AmptieRaidTools_PlayerInfo and AmptieRaidTools_PlayerInfo.spec
        if not mySpec then return false end
        local myRole = ART_GetSpecRole and ART_GetSpecRole(mySpec)
        return myRole == IC_ROLE_KEY_TO_BROAD[v]
    elseif t == "damagecat" then
        local mySpec = AmptieRaidTools_PlayerInfo and AmptieRaidTools_PlayerInfo.spec
        if not mySpec then return false end
        local mySub = (ART_GetSpecSubRole and ART_GetSpecSubRole(mySpec)) or "Close-up Melee"
        return IC_SUBROLE_TO_CAT[mySub] == v
    elseif t == "spec" then
        local mySpec = AmptieRaidTools_PlayerInfo and AmptieRaidTools_PlayerInfo.spec
        if not mySpec then return false end
        local specVals = ART_IC_WHO_VALUES.spec
        for i = 1, getn(specVals) do
            if specVals[i].label == mySpec then
                return specVals[i].key == v
            end
        end
        return false
    end
    return false
end
-- Export for use by buffchecks.lua
ART_IC_PlayerMatchesWho = PlayerMatchesWho

-- Decode a serialized rule: "whoType^whoValue^condStr"
-- condStr = OR groups separated by ";", AND items by "+", each item "key:count"
local function DecodeRule(data)
    local s1 = string.find(data, "^", 1, true)
    if not s1 then return nil end
    local whoType = string.sub(data, 1, s1 - 1)
    local rest    = string.sub(data, s1 + 1)
    local s2      = string.find(rest, "^", 1, true)
    if not s2 then return nil end
    local whoValue = string.sub(rest, 1, s2 - 1)
    local condStr  = string.sub(rest, s2 + 1)
    local rule = { who = { type=whoType, value=whoValue }, conditions = {} }
    rule.conditions.n = 0
    for orStr in string.gfind(condStr, "[^;]+") do
        local grp = {}
        grp.n = 0
        for andStr in string.gfind(orStr, "[^+]+") do
            local cs = string.find(andStr, ":", 1, true)
            if cs then
                local key   = string.sub(andStr, 1, cs - 1)
                local count = tonumber(string.sub(andStr, cs + 1)) or 1
                tinsert(grp, { key=key, count=count })
            end
        end
        if getn(grp) > 0 then
            tinsert(rule.conditions, grp)
        end
    end
    return rule
end

-- Encode a rule to string for sending
local function EncodeRule(rule)
    local whoType  = (rule.who and rule.who.type)  or "everyone"
    local whoValue = (rule.who and rule.who.value) or ""
    local orParts  = {}
    local conds    = rule.conditions or {}
    for oi = 1, getn(conds) do
        local grp      = conds[oi]
        local andParts = {}
        for ai = 1, getn(grp) do
            tinsert(andParts, grp[ai].key .. ":" .. (grp[ai].count or 1))
        end
        local andStr = ""
        for i = 1, getn(andParts) do
            if i > 1 then andStr = andStr .. "+" end
            andStr = andStr .. andParts[i]
        end
        tinsert(orParts, andStr)
    end
    local condStr = ""
    for i = 1, getn(orParts) do
        if i > 1 then condStr = condStr .. ";" end
        condStr = condStr .. orParts[i]
    end
    return whoType .. "^" .. whoValue .. "^" .. condStr
end

-- Evaluate one rule against local player's inventory.
-- Returns: pass (bool), missing (table key→have) or nil if pass
local function EvaluateRule(rule)
    local conds = rule.conditions or {}
    if getn(conds) == 0 then return true, nil end
    local bestMissing = nil
    local bestCount   = 9999
    for oi = 1, getn(conds) do
        local grp     = conds[oi]
        local grpPass = true
        local grpMiss = {}
        local missCount = 0
        for ai = 1, getn(grp) do
            local cond = grp[ai]
            local item = ART_IC_BY_KEY[cond.key]
            if item then
                local have = 0
                if item.resistIndex then
                    local _, res = UnitResistance("player", item.resistIndex)
                    have = res or 0
                elseif item.anyOne then
                    for ii = 1, getn(item.ids) do
                        if GetItemCountInBags(item.ids[ii]) > 0 then
                            have = 1
                            break
                        end
                    end
                else
                    for ii = 1, getn(item.ids) do
                        have = have + GetItemCountInBags(item.ids[ii])
                    end
                end
                if have < cond.count then
                    grpPass = false
                    grpMiss[cond.key] = have
                    missCount = missCount + 1
                end
            end
        end
        if grpPass then return true, nil end
        if missCount < bestCount then
            bestCount   = missCount
            bestMissing = grpMiss
        end
    end
    return false, bestMissing
end

-- Evaluate all applicable rules and send response
local function EvaluateSelfAndRespond(checkId, rules)
    local ch = GetICMsgChannel()
    if not ch then return end
    local allMissing = {}
    local allPass    = true
    for ri = 1, getn(rules) do
        local rule = rules[ri]
        if PlayerMatchesWho(rule.who) then
            local pass, missing = EvaluateRule(rule)
            if not pass then
                allPass = false
                if missing then
                    for key, have in pairs(missing) do
                        if allMissing[key] == nil or allMissing[key] > have then
                            allMissing[key] = have
                        end
                    end
                end
            end
        end
    end
    if allPass then
        SendAddonMessage(IC_PREFIX, "CHK_OK^" .. checkId, ch)
    else
        local parts = {}
        for key, have in pairs(allMissing) do
            tinsert(parts, key .. ":" .. have)
        end
        local failStr = ""
        for i = 1, getn(parts) do
            if i > 1 then failStr = failStr .. "," end
            failStr = failStr .. parts[i]
        end
        local msg = "CHK_NG^" .. checkId .. "^" .. failStr
        if string.len(msg) > 250 then msg = string.sub(msg, 1, 250) end
        SendAddonMessage(IC_PREFIX, msg, ch)
    end
end

-- ── Addon message event handler ─────────────────────────────
local icEventFrame = CreateFrame("Frame", "ART_IC_EventFrame", UIParent)
icEventFrame:RegisterEvent("CHAT_MSG_ADDON")
icEventFrame:SetScript("OnEvent", function()
    local evt = event
    if evt ~= "CHAT_MSG_ADDON" then return end
    local a1, a2, a3, a4 = arg1, arg2, arg3, arg4
    if a1 ~= IC_PREFIX then return end
    local msg    = a2
    local sender = a4 or ""
    -- Strip realm suffix
    local nameOnly = sender
    local dash = string.find(sender, "-", 1, true)
    if dash then nameOnly = string.sub(sender, 1, dash - 1) end

    local sep = string.find(msg, "^", 1, true)
    if not sep then return end
    local kind = string.sub(msg, 1, sep - 1)
    local rest = string.sub(msg, sep + 1)

    if kind == "CHK_S" then
        -- rest: "checkId^numRules" — reset receiver state
        local p = string.find(rest, "^", 1, true)
        if p then
            icRcvCheckId = string.sub(rest, 1, p - 1)
            icRcvRules   = {}
            icRcvRules.n = 0
        end

    elseif kind == "CHK_R" then
        -- rest: "checkId^ruleIdx^whoType^whoValue^condStr"
        local p1 = string.find(rest, "^", 1, true)
        if not p1 then return end
        local cid   = string.sub(rest, 1, p1 - 1)
        if cid ~= icRcvCheckId then return end
        local rest2 = string.sub(rest, p1 + 1)
        local p2    = string.find(rest2, "^", 1, true)
        if not p2 then return end
        -- skip rule index, remaining is "whoType^whoValue^condStr"
        local ruleData = string.sub(rest2, p2 + 1)
        local rule     = DecodeRule(ruleData)
        if rule then tinsert(icRcvRules, rule) end

    elseif kind == "CHK_E" then
        -- rest: checkId — evaluate self
        if rest == icRcvCheckId then
            EvaluateSelfAndRespond(rest, icRcvRules)
        end

    elseif kind == "CHK_OK" then
        -- rest: checkId
        if rest == icCheckId then
            icCheckResults[nameOnly] = { missing = {}, done = true }
            if icNotifyRefresh then icNotifyRefresh() end
        end

    elseif kind == "CHK_NG" then
        -- rest: "checkId^failStr"
        local p = string.find(rest, "^", 1, true)
        if not p then return end
        local cid     = string.sub(rest, 1, p - 1)
        if cid ~= icCheckId then return end
        local failStr = string.sub(rest, p + 1)
        local missing = {}
        for item in string.gfind(failStr, "[^,]+") do
            local cs = string.find(item, ":", 1, true)
            if cs then
                local key  = string.sub(item, 1, cs - 1)
                local have = tonumber(string.sub(item, cs + 1)) or 0
                missing[key] = have
            end
        end
        icCheckResults[nameOnly] = { missing = missing, done = true }
        if icNotifyRefresh then icNotifyRefresh() end
    end
end)

-- ── Public API ───────────────────────────────────────────────

-- Start an item check using the named profile (called by leader)
function ART_IC_StartCheck(profileName)
    if not profileName then return end
    local db = GetICDB()
    local profile = db.itemCheckProfiles[profileName]
    if not profile or not profile.rules then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[Item Check]|r Profile not found: " .. profileName)
        return
    end
    local ch = GetICMsgChannel()
    if not ch then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[Item Check]|r Not in a group.")
        return
    end
    local checkId = tostring(math.floor(GetTime() * 1000))
    icCheckId = checkId
    for k in pairs(icCheckResults) do icCheckResults[k] = nil end
    local rules   = profile.rules
    local numRules = getn(rules)
    SendAddonMessage(IC_PREFIX, "CHK_S^" .. checkId .. "^" .. numRules, ch)
    for ri = 1, numRules do
        local encoded = EncodeRule(rules[ri])
        SendAddonMessage(IC_PREFIX, "CHK_R^" .. checkId .. "^" .. ri .. "^" .. encoded, ch)
    end
    SendAddonMessage(IC_PREFIX, "CHK_E^" .. checkId, ch)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00CCFF[Item Check]|r Check started: " .. profileName)
    if icNotifyRefresh then icNotifyRefresh() end
end

-- Returns the current check results table (read-only use)
function ART_IC_GetCheckResults()
    return icCheckResults
end

-- Returns sorted list of profile names
function ART_IC_GetProfileNames()
    local db    = GetICDB()
    local names = {}
    for name in pairs(db.itemCheckProfiles) do
        tinsert(names, name)
    end
    -- insertion sort
    for i = 2, getn(names) do
        local v = names[i]
        local j = i - 1
        while j >= 1 and names[j] > v do
            names[j + 1] = names[j]
            j = j - 1
        end
        names[j + 1] = v
    end
    return names
end

-- Register a function to call when check results change
function ART_IC_SetNotifyRefresh(fn)
    icNotifyRefresh = fn
end

-- Clear current results (e.g. when starting a new check)
function ART_IC_ClearResults()
    for k in pairs(icCheckResults) do icCheckResults[k] = nil end
    if icNotifyRefresh then icNotifyRefresh() end
end

-- Get display info for an item key: name (string), icon path (string or nil)
-- Uses hardcoded ART_IC_ICONS table; tries GetItemInfo for locale name if cached.
function ART_IC_GetItemDisplayInfo(key)
    local item = ART_IC_BY_KEY[key]
    if not item then return key, nil end
    local icon = ART_IC_ICONS[key]
    local name = item.name
    -- Only attempt GetItemInfo for actual items (resistances have no ids)
    if item.ids and item.ids[1] then
        local cachedName = GetItemInfo(item.ids[1])
        if cachedName then name = cachedName end
    end
    return name, icon
end
