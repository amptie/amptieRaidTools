-- components/buffchecks.lua
-- Buff Checks: live buff verification with overlay (Lua 5.0 / WoW 1.12 / TurtleWoW)

local getn    = table.getn
local tinsert = table.insert
local floor   = math.floor
local sfind   = string.find

local _ART_BC_RefreshRules  = nil
local ART_BC_dropdownHiders = {}

-- Full-screen click-catcher to close dropdowns
local ART_BC_catchFrame = CreateFrame("Button", nil, UIParent)
ART_BC_catchFrame:SetFrameStrata("FULLSCREEN")
ART_BC_catchFrame:SetAllPoints(UIParent)
ART_BC_catchFrame:EnableMouse(true)
ART_BC_catchFrame:Hide()
ART_BC_catchFrame:SetScript("OnClick", function()
    for i = 1, getn(ART_BC_dropdownHiders) do ART_BC_dropdownHiders[i]() end
    this:Hide()
end)

-- ============================================================
-- Backdrop constants
-- ============================================================
local BD_PANEL = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left=3, right=3, top=3, bottom=3 },
}
local BD_EDIT = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 10,
    insets = { left=3, right=3, top=3, bottom=3 },
}

-- ============================================================
-- Buff table
-- sec = "flask"|"protection"|"defense"|"physical"|"caster"|"mana"|"drink"|"utility"|"weapon"|"food"
-- itemKey = corresponding ART_IC_ITEMS key (nil if no IC entry)
-- ============================================================
local ART_BC_BUFFS = {
    -- Flasks
    { key="FLASK_TITANS",        name="Flask of the Titans",              buffName="Flask of the Titans",              sec="flask",      icon="Interface\\Icons\\INV_Potion_62",                 itemKey="FLASK_TITANS"      },
    { key="FLASK_SUP_PWR",       name="Flask of Supreme Power",           buffName="Supreme Power",                    sec="flask",      icon="Interface\\Icons\\INV_Potion_41",                 itemKey="FLASK_SUP_PWR"     },
    { key="FLASK_DIST_WIS",      name="Flask of Distilled Wisdom",        buffName="Distilled Wisdom",                 sec="flask",      icon="Interface\\Icons\\inv_potion_120",                itemKey="FLASK_DIST_WIS"    },
    { key="FLASK_CHROM_RES",     name="Flask of Chromatic Resistance",    buffName="Chromatic Resistance",             sec="flask",      icon="Interface\\Icons\\INV_Potion_128",                itemKey="FLASK_CHROM_RES"   },
    -- Protection Potions
    { key="GR_ARCANE_PROT",      name="Greater Arcane Protection",        buffName="Arcane Protection",                sec="protection", icon="Interface\\Icons\\inv_potion_83",                 itemKey="GR_ARCANE_PROT"    },
    { key="GR_FIRE_PROT",        name="Greater Fire Protection",          buffName="Fire Protection",                  sec="protection", icon="Interface\\Icons\\INV_Potion_117",                itemKey="GR_FIRE_PROT"      },
    { key="GR_FROST_PROT",       name="Greater Frost Protection",         buffName="Frost Protection",                 sec="protection", icon="Interface\\Icons\\INV_Potion_20",                 itemKey="GR_FROST_PROT"     },
    { key="GR_SHADOW_PROT",      name="Greater Shadow Protection",        buffName="Shadow Protection",                sec="protection", icon="Interface\\Icons\\INV_Potion_23",                 itemKey="GR_SHADOW_PROT"    },
    { key="GR_HOLY_PROT",        name="Greater Holy Protection",          buffName="Holy Protection",                  sec="protection", icon="Interface\\Icons\\INV_Potion_09",                 itemKey="GR_HOLY_PROT"      },
    { key="GR_NATURE_PROT",      name="Greater Nature Protection",        buffName="Nature Protection",                sec="protection", icon="Interface\\Icons\\INV_Potion_22",                 itemKey="GR_NATURE_PROT"    },
    { key="NATURE_PROT",         name="Nature Protection Potion",         buffName="Nature Protection",                sec="protection", icon="Interface\\Icons\\INV_Potion_06",                 itemKey="NATURE_PROT"       },
    -- Defense / Zanza
    { key="SPIRIT_ZANZA",        name="Spirit of Zanza",                  buffName="Spirit of Zanza",                  sec="defense",    icon="Interface\\Icons\\INV_Potion_30",                 itemKey="SPIRIT_ZANZA"      },
    { key="ELX_FORTITUDE",       name="Elixir of Fortitude",              buffName="Health II",                        sec="defense",    icon="Interface\\Icons\\INV_Potion_43",                 itemKey="ELX_FORTITUDE"     },
    { key="ELX_SUP_DEFENSE",     name="Elixir of Superior Defense",       buffName="Greater Armor",                    sec="defense",    icon="Interface\\Icons\\INV_Potion_66",                 itemKey="ELX_SUP_DEFENSE"   },
    { key="GR_STONESHIELD",      name="Greater Stoneshield Potion",       buffName="Greater Stoneshield",              sec="defense",    icon="Interface\\Icons\\INV_Potion_69",                 itemKey="GR_STONESHIELD"    },
    -- Physical DPS
    { key="ELX_MONGOOSE",        name="Elixir of the Mongoose",           buffName="Elixir of the Mongoose",           sec="physical",   icon="Interface\\Icons\\INV_Potion_32",                 itemKey="ELX_MONGOOSE"      },
    { key="ELX_GIANTS",          name="Elixir of Giants",                 buffName="Elixir of the Giants",             sec="physical",   icon="Interface\\Icons\\INV_Potion_61",                 itemKey="ELX_GIANTS"        },
    { key="JUJU_POWER",          name="Juju Power",                       buffName="Juju Power",                       sec="physical",   icon="Interface\\Icons\\INV_Misc_MonsterScales_11",     itemKey="JUJU_POWER"        },
    { key="WINTERFALL_FW",       name="Winterfall Firewater",             buffName="Winterfall Firewater",             sec="physical",   icon="Interface\\Icons\\INV_Potion_92",                 itemKey="WINTERFALL_FW"     },
    { key="JUJU_MIGHT",          name="Juju Might",                       buffName="Juju Might",                       sec="physical",   icon="Interface\\Icons\\INV_Misc_MonsterScales_07",     itemKey="JUJU_MIGHT"        },
    { key="MIGHTY_RAGE",         name="Mighty Rage Potion",               buffName="Mighty Rage",                      sec="physical",   icon="Interface\\Icons\\inv_potion_125",                itemKey="MIGHTY_RAGE"       },
    { key="ROIDS",               name="R.O.I.D.S.",                       buffName="Rage of Ages",                     sec="physical",   icon="Interface\\Icons\\INV_Stone_15",                  itemKey="ROIDS"             },
    { key="GROUND_SCORPOK",      name="Ground Scorpok Assay",             buffName="Strike of the Scorpok",            sec="physical",   icon="Interface\\Icons\\INV_Misc_Dust_07",              itemKey="GROUND_SCORPOK"    },
    { key="CONCOCTION_ARCANE",   name="Concoction of the Arcane Giant",   buffName="Concoction of the Arcane Giant",   sec="physical",   icon="Interface\\Icons\\inv_yellow_purple_elixir_2",    itemKey="CONCOCTION_ARCANE" },
    { key="CONCOCTION_EMERALD",  name="Concoction of the Emerald Mongoose",buffName="Concoction of the Emerald Mongoose",sec="physical", icon="Interface\\Icons\\inv_blue_gold_elixir_2",        itemKey="CONCOCTION_EMERALD"},
    { key="CONCOCTION_DREAM",    name="Concoction of the Dreamwater",     buffName="Concoction of the Dreamwater",     sec="physical",   icon="Interface\\Icons\\inv_green_pink_elixir_1",       itemKey="CONCOCTION_DREAM"  },
    -- Caster DPS
    { key="GR_ARCANE_ELX",       name="Greater Arcane Elixir",            buffName="Greater Arcane Elixir",            sec="caster",     icon="Interface\\Icons\\INV_Potion_25",                 itemKey="GR_ARCANE_ELX"     },
    { key="DREAMSHARD_ELX",      name="Dreamshard Elixir",                buffName="Dreamshard Elixir",                sec="caster",     icon="Interface\\Icons\\INV_Potion_113",                itemKey="DREAMSHARD_ELX"    },
    { key="ELX_GR_FIRE_PWR",     name="Elixir of Greater Firepower",      buffName="Greater Firepower",                sec="caster",     icon="Interface\\Icons\\INV_Potion_60",                 itemKey="ELX_GR_FIRE_PWR"   },
    { key="ELX_SHADOW_PWR",      name="Elixir of Shadow Power",           buffName="Shadow Power",                     sec="caster",     icon="Interface\\Icons\\INV_Potion_46",                 itemKey="ELX_SHADOW_PWR"    },
    { key="ELX_GR_NATURE_PWR",   name="Elixir of Greater Nature Power",   buffName="Elixir of Greater Nature Power",   sec="caster",     icon="Interface\\Icons\\INV_Potion_106",                itemKey="ELX_GR_NATURE_PWR" },
    { key="ELX_GR_ARCANE_PWR",   name="Elixir of Greater Arcane Power",   buffName="Greater Arcane Power",             sec="caster",     icon="Interface\\Icons\\INV_Potion_81",                 itemKey="ELX_GR_ARCANE_PWR" },
    { key="ELX_GR_FROST_PWR",    name="Elixir of Greater Frost Power",    buffName="Greater Frost Power",              sec="caster",     icon="Interface\\Icons\\INV_Potion_13",                 itemKey="ELX_GR_FROST_PWR"  },
    { key="DREAMTONIC",          name="Dreamtonic",                       buffName="Dreamtonic",                       sec="caster",     icon="Interface\\Icons\\INV_Potion_114",                itemKey="DREAMTONIC"        },
    -- Mana
    { key="MAGEBLOOD",           name="Mageblood Potion",                 buffName="Mana Regeneration",                sec="mana",       icon="Interface\\Icons\\INV_Potion_45",                 itemKey="MAGEBLOOD"         },
    -- Drinks
    { key="RUMSEY_RUM",          name="Rumsey Rum Black Label",           buffName="Rumsey Rum Black Label",           sec="drink",      icon="Interface\\Icons\\INV_Drink_04",                  itemKey="RUMSEY_RUM"        },
    { key="MEDIVH_MERLOT",       name="Medivh's Merlot",                  buffName="Medivh's Merlot",                  sec="drink",      icon="Interface\\Icons\\INV_Drink_Waterskin_05",        itemKey="MEDIVH_MERLOT"     },
    { key="MEDIVH_MERLOT_BLUE",  name="Medivh's Merlot Blue",             buffName="Medivh's Merlot Blue",             sec="drink",      icon="Interface\\Icons\\INV_Drink_Waterskin_01",        itemKey="MEDIVH_MERLOT_BLUE"},
    -- Utility
    { key="FREE_ACTION",         name="Free Action Potion",               buffName="Free Action",                      sec="utility",    icon="Interface\\Icons\\INV_Potion_04",                 itemKey="FREE_ACTION"       },
    { key="LTD_INVULN",          name="Limited Invulnerability",          buffName="Invulnerability",                  sec="utility",    icon="Interface\\Icons\\INV_Potion_121",                itemKey="LTD_INVULN"        },
    { key="LESSER_INVIS",        name="Lesser Invisibility Potion",       buffName="Lesser Invisibility",              sec="utility",    icon="Interface\\Icons\\INV_Potion_18",                 itemKey="LESSER_INVIS"      },
    { key="INVIS_POTION",        name="Invisibility Potion",              buffName="Invisibility",                     sec="utility",    icon="Interface\\Icons\\INV_Potion_112",                itemKey="INVIS_POTION"      },
    { key="SWIFTNESS",           name="Swiftness Potion",                 buffName="Speed",                            sec="utility",    icon="Interface\\Icons\\INV_Potion_95",                 itemKey="SWIFTNESS_POT"     },
    { key="RESTORATIVE",         name="Restorative Potion",               buffName="Restoration",                      sec="utility",    icon="Interface\\Icons\\INV_Potion_118",                itemKey="RESTORATIVE"       },
    { key="MAGIC_RES",           name="Magic Resistance Potion",          buffName="Resistance",                       sec="utility",    icon="Interface\\Icons\\INV_Potion_16",                 itemKey="MAGIC_RES_POT"     },
    { key="SHEEN_ZANZA",         name="Sheen of Zanza",                   buffName="Sheen of Zanza",                   sec="utility",    icon="Interface\\Icons\\INV_Potion_29",                 itemKey="SHEEN_ZANZA"       },
    { key="SWIFTNESS_ZANZA",     name="Swiftness of Zanza",               buffName="Swiftness of Zanza",               sec="utility",    icon="Interface\\Icons\\INV_Potion_31",                 itemKey="SWIFTNESS_ZANZA"   },
    { key="ELX_POISON_RES",      name="Elixir of Poison Resistance",      buffName="Cure Poison",                      sec="utility",    icon="Interface\\Icons\\INV_Potion_12",                 itemKey="ELX_POISON_RES"    },
    -- Weapon Buffs
    { key="CONSECR_STONE",       name="Consecrated Sharpening Stone",     buffName="Consecrated Weapon",               sec="weapon",     icon="Interface\\Icons\\INV_Stone_SharpeningStone_02",  itemKey="CONSECR_STONE"     },
    { key="BLESSED_WIZ_OIL",     name="Blessed Wizard Oil",               buffName="Blessed Wizard Oil",               sec="weapon",     icon="Interface\\Icons\\INV_Potion_138",                itemKey="BLESSED_WIZ_OIL"   },
    { key="ELEM_SHARP_STONE",    name="Elemental Sharpening Stone",       buffName="Sharpen Weapon - Critical",        sec="weapon",     icon="Interface\\Icons\\INV_Stone_02",                  itemKey="ELEM_SHARP_STONE"  },
    { key="BRILL_MANA_OIL",      name="Brilliant Mana Oil",               buffName="Brilliant Mana Oil",               sec="weapon",     icon="Interface\\Icons\\INV_Potion_100",                itemKey="BRILL_MANA_OIL"    },
    { key="BRILL_WIZ_OIL",       name="Brilliant Wizard Oil",             buffName="Brilliant Wizard Oil",             sec="weapon",     icon="Interface\\Icons\\INV_Potion_105",                itemKey="BRILL_WIZ_OIL"     },
    -- Buff Foods
    { key="FOOD_ANY",            name="Buff Food (any)",                  buffName=nil,
      buffNames={"Well Fed","Increased Stamina","Increased Agility","Increased Intellect",
                 "Increased Healing Bonus","Mana Regeneration","Dragonbreath Chili"},
                                                                           sec="food",       icon="Interface\\Icons\\INV_Misc_Food_19",              itemKey=nil                 },
    { key="FOOD_STAMINA",        name="Food – Increased Stamina",         buffName="Increased Stamina",                sec="food",       icon="Interface\\Icons\\INV_Misc_Food_06",              itemKey=nil                 },
    { key="FOOD_WELL_FED",       name="Food – Well Fed",                  buffName="Well Fed",                         sec="food",       icon="Interface\\Icons\\INV_Misc_Food_19",              itemKey=nil                 },
    { key="FOOD_MANA_REGEN",     name="Food – Mana Regeneration",         buffName="Mana Regeneration",                sec="food",       icon="Interface\\Icons\\INV_Misc_Food_62",              itemKey=nil                 },
    { key="FOOD_AGILITY",        name="Food – Increased Agility",         buffName="Increased Agility",                sec="food",       icon="Interface\\Icons\\INV_Misc_Food_11",              itemKey=nil                 },
    { key="FOOD_HEALING",        name="Food – Increased Healing Bonus",   buffName="Increased Healing Bonus",          sec="food",       icon="Interface\\Icons\\INV_Misc_Food_52",              itemKey=nil                 },
    { key="FOOD_INTELLECT",      name="Food – Increased Intellect",       buffName="Increased Intellect",              sec="food",       icon="Interface\\Icons\\INV_Misc_Food_14",              itemKey=nil                 },
    { key="FOOD_DRAGON",         name="Dragonbreath Chili",               buffName="Dragonbreath Chili",               sec="food",       icon="Interface\\Icons\\INV_Misc_Food_77",              itemKey=nil                 },
}

-- Lookup tables
local ART_BC_BY_KEY  = {}  -- key  → buff entry
local ART_IC_TO_BC   = {}  -- IC item key → BC buff key
for i = 1, getn(ART_BC_BUFFS) do
    local b = ART_BC_BUFFS[i]
    ART_BC_BY_KEY[b.key] = b
    if b.itemKey then ART_IC_TO_BC[b.itemKey] = b.key end
end

local BC_SEC_LABELS = {
    flask      = "── Flasks ──",
    protection = "── Protection ──",
    defense    = "── Defense ──",
    physical   = "── Physical DPS ──",
    caster     = "── Caster DPS ──",
    mana       = "── Mana ──",
    drink      = "── Drinks ──",
    utility    = "── Utility ──",
    weapon     = "── Weapon Buffs ──",
    food       = "── Buff Foods ──",
}

-- ============================================================
-- WHO types / values  (same as IC, self-contained)
-- ============================================================
local ART_BC_WHO_TYPES = {
    { key="everyone",  label="Everyone"    },
    { key="class",     label="Class"       },
    { key="role",      label="Role"        },
    { key="damagecat", label="Damage Type" },
    { key="spec",      label="Spec"        },
}
local ART_BC_WHO_VALUES = {
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
    spec = {
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
local function GetBCDB()
    local db = amptieRaidToolsDB
    if not db.buffCheckProfiles then
        db.buffCheckProfiles = { ["Default"] = { rules={} } }
    end
    if not db.activeBCProfile or not db.buffCheckProfiles[db.activeBCProfile] then
        db.activeBCProfile = "Default"
        if not db.buffCheckProfiles["Default"] then
            db.buffCheckProfiles["Default"] = { rules={} }
        end
    end
    return db
end

local function GetActiveBCProfile()
    local db = GetBCDB()
    return db.buffCheckProfiles[db.activeBCProfile]
end

-- ============================================================
-- Format helpers
-- ============================================================
local function GetBuffName(key)
    local b = ART_BC_BY_KEY[key]
    return b and b.name or key
end

local function CondBCSummary(conditions)
    if not conditions or getn(conditions) == 0 then return "(no conditions)" end
    local orParts = {}
    for oi = 1, getn(conditions) do
        local grp = conditions[oi]
        local andParts = {}
        for ai = 1, getn(grp) do
            tinsert(andParts, GetBuffName(grp[ai].key))
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

local function BCWhoLabel(who)
    if not who or who.type == "everyone" then return "Everyone" end
    local vals = ART_BC_WHO_VALUES[who.type]
    if vals then
        for i = 1, getn(vals) do
            if vals[i].key == who.value then return vals[i].label end
        end
    end
    return who.value or "?"
end

-- ============================================================
-- UI factories
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
    eb:SetScript("OnEditFocusGained", function() this:SetBackdropBorderColor(1, 0.82, 0, 0.8) end)
    eb:SetScript("OnEditFocusLost",   function() this:SetBackdropBorderColor(0.35, 0.35, 0.4, 1) end)
    eb:SetScript("OnEscapePressed",   function() this:ClearFocus() end)
    return eb
end

local function MakeDropdown(parent, w, maxRows)
    maxRows = maxRows or 10
    local ROW_H = 20
    local dd = {}

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

    local listH = maxRows * ROW_H + 8
    local list = CreateFrame("Frame", nil, UIParent)
    list:SetFrameStrata("TOOLTIP")
    list:SetWidth(w)
    list:SetHeight(listH)
    list:SetBackdrop(BD_PANEL)
    list:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
    list:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    list:Hide()

    local sf = CreateFrame("ScrollFrame", nil, list)
    sf:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -4, 4)

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(w - 8)
    content:SetHeight(1)
    sf:SetScrollChild(content)

    local scrollOffset = 0

    local function SetScroll(val)
        local maxS = math.max(content:GetHeight() - (listH - 8), 0)
        if val < 0 then val = 0 end
        if val > maxS then val = maxS end
        scrollOffset = val
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, val)
    end

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function() SetScroll(scrollOffset - arg1 * ROW_H * 3) end)

    local rowFrames = {}
    dd.selectedKey   = nil
    dd.selectedLabel = nil
    dd.onSelect      = nil

    local function HideDD()
        list:Hide()
        scrollOffset = 0
        SetScroll(0)
        ART_BC_catchFrame:Hide()
    end

    local function Populate(items)
        for i = 1, getn(rowFrames) do rowFrames[i]:Hide() end
        content:SetHeight(math.max(getn(items) * ROW_H, 1))
        for i = 1, getn(items) do
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
                row:SetScript("OnClick", function() end)
                row:SetScript("OnEnter", function() end)
                row:SetScript("OnLeave", function() end)
            else
                row:EnableMouse(true)
                row.rfs:SetTextColor(1, 1, 1, 1)
                local k, l = it.key, it.label
                row:SetScript("OnClick", function()
                    dd.selectedKey   = k
                    dd.selectedLabel = l
                    btnLabel:SetText(l)
                    HideDD()
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
    end

    btn:SetScript("OnClick", function()
        if list:IsShown() then
            HideDD()
        else
            for i = 1, getn(ART_BC_dropdownHiders) do ART_BC_dropdownHiders[i]() end
            list:ClearAllPoints()
            list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            list:Show()
            SetScroll(0)
            ART_BC_catchFrame:Show()
        end
    end)

    tinsert(ART_BC_dropdownHiders, HideDD)

    dd.btn      = btn
    dd.list     = list
    dd.SetItems = Populate
    dd.SetValue = function(key, label)
        dd.selectedKey   = key
        dd.selectedLabel = label
        btnLabel:SetText(label or "")
    end
    dd.GetKey   = function() return dd.selectedKey end
    dd.Hide     = HideDD
    return dd
end

-- Buff picker dropdown: sections as headers
local function MakeBuffDropdown(parent, w)
    local items = {}
    local lastSec = nil
    for i = 1, getn(ART_BC_BUFFS) do
        local b = ART_BC_BUFFS[i]
        if b.sec ~= lastSec then
            lastSec = b.sec
            tinsert(items, { key="__HDR__"..b.sec, label=BC_SEC_LABELS[b.sec] or b.sec, header=true })
        end
        tinsert(items, { key=b.key, label=b.name })
    end
    local dd = MakeDropdown(parent, w, 14)
    dd.SetItems(items)
    return dd
end

-- ============================================================
-- Export / Import helpers
-- ============================================================
local function BCDeepCopy(src)
    local dst = {}
    for oi = 1, getn(src) do
        local grp = {}
        for ai = 1, getn(src[oi]) do
            tinsert(grp, { key=src[oi][ai].key })
        end
        tinsert(dst, grp)
    end
    return dst
end

local function BCSplit(s, sep)
    local result = {}
    local sepLen = string.len(sep)
    local i = 1
    while true do
        local j = string.find(s, sep, i, true)
        if not j then tinsert(result, string.sub(s, i)); break end
        tinsert(result, string.sub(s, i, j-1))
        i = j + sepLen
    end
    return result
end

local function BCExportProfile(prof)
    if not prof or not prof.rules then return "bc1" end
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
                tinsert(andParts, grp[ai].key)
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
    local str = "bc1"
    for pi = 1, getn(ruleParts) do str = str .. "~" .. ruleParts[pi] end
    return str
end

local function BCImportProfile(str)
    if not str or string.len(str) < 3 then return nil, "Empty string" end
    if string.sub(str, 1, 3) ~= "bc1" then return nil, "Unknown format (expected bc1...)" end
    local body = string.sub(str, 4)
    local rules = {}
    if body == "" then return { rules=rules } end
    if string.sub(body, 1, 1) ~= "~" then return nil, "Malformed string" end
    body = string.sub(body, 2)
    local ruleParts = BCSplit(body, "~")
    for ri = 1, getn(ruleParts) do
        local ruleStr = ruleParts[ri]
        if ruleStr ~= "" then
            local fields = BCSplit(ruleStr, "^")
            if getn(fields) < 2 then return nil, "Malformed rule " .. ri end
            local whoType  = fields[1]
            local whoValue = fields[2]
            local condStr  = fields[3] or ""
            local validType = false
            for wi = 1, getn(ART_BC_WHO_TYPES) do
                if ART_BC_WHO_TYPES[wi].key == whoType then validType = true; break end
            end
            if not validType then whoType = "everyone"; whoValue = "*" end
            local conditions = {}
            if condStr ~= "" then
                local orStrs = BCSplit(condStr, ";")
                for oi = 1, getn(orStrs) do
                    if orStrs[oi] ~= "" then
                        local grp = {}
                        local andStrs = BCSplit(orStrs[oi], "+")
                        for ai = 1, getn(andStrs) do
                            local key = andStrs[ai]
                            if key ~= "" and ART_BC_BY_KEY[key] then
                                tinsert(grp, { key=key })
                            end
                        end
                        if getn(grp) > 0 then tinsert(conditions, grp) end
                    end
                end
            end
            tinsert(rules, { who={ type=whoType, value=whoValue }, conditions=conditions })
        end
    end
    return { rules=rules }
end

-- ============================================================
-- IC → BC profile conversion
-- Converts an IC profile's item-based rules to buff-based rules.
-- Items with no matching buff are silently skipped.
-- ============================================================
local function ConvertICProfileToBC(icProfile)
    local newRules = {}
    if not icProfile or not icProfile.rules then return { rules=newRules } end
    for ri = 1, getn(icProfile.rules) do
        local icRule = icProfile.rules[ri]
        local newConds = {}
        for oi = 1, getn(icRule.conditions or {}) do
            local grp = icRule.conditions[oi]
            local newGrp = {}
            for ai = 1, getn(grp) do
                local bcKey = ART_IC_TO_BC[grp[ai].key]
                if bcKey then
                    tinsert(newGrp, { key=bcKey })
                end
            end
            if getn(newGrp) > 0 then tinsert(newConds, newGrp) end
        end
        if getn(newConds) > 0 then
            tinsert(newRules, {
                who        = { type = icRule.who and icRule.who.type or "everyone",
                               value = icRule.who and icRule.who.value or "*" },
                conditions = newConds,
            })
        end
    end
    return { rules=newRules }
end

-- ============================================================
-- Protocol
-- ============================================================
local BC_PREFIX     = "ART_BC"
local bcCheckId        = nil   -- current check ID (sender side)
local bcCheckResults   = {}    -- [playerName] = { done=bool, missing={key,...} }
local bcBuffTargetCount = {}   -- [buffKey] = number of players who should have it
local bcNotifyRefresh = nil  -- callback for overlay refresh
local bcRcvCheckId    = nil   -- check ID we're currently responding to
local bcRcvRules      = {}    -- rules received for current check
local bcRcvExpected   = 0     -- expected number of rules for current check

local function BCGetMsgChannel()
    if GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers() > 0 then return "PARTY" end
    return nil
end

-- SuperWoW: UnitBuff returns (texture, count, spellId).
-- SpellInfo(spellId) returns the buff name synchronously — no tooltip scan needed.
-- Tooltip scan kept as fallback for any buff whose spellId isn't resolved.
local ART_BC_ScanTip = CreateFrame("GameTooltip", "ART_BC_ScanTip", nil, "GameTooltipTemplate")
ART_BC_ScanTip:SetOwner(UIParent, "ANCHOR_NONE")

local function PlayerHasBuff(buffName)
    for i = 1, 32 do
        local tex, _, spellId = UnitBuff("player", i)
        if not tex then break end
        -- Primary: SpellInfo (SuperWoW, always synchronous)
        -- Guard with SpellInfo ~= nil: older TurtleWoW clients return spellId from
        -- UnitBuff but may not yet expose SpellInfo, so fall through to tooltip scan.
        if spellId and spellId > 0 and SpellInfo then
            local sname = SpellInfo(spellId)
            if sname and sname == buffName then return true end
        end
    end
    -- Fallback: tooltip scan
    for i = 0, 31 do
        if not UnitBuff("player", i + 1) then break end
        ART_BC_ScanTip:ClearLines()
        ART_BC_ScanTip:SetPlayerBuff(i)
        local tname = getglobal("ART_BC_ScanTipTextLeft1"):GetText()
        if tname and tname == buffName then return true end
    end
    return false
end

-- Role-key → broad role name (mirrors IC_ROLE_KEY_TO_BROAD in itemchecks.lua)
local BC_ROLE_BROAD = { TANK="Tank", HEALER="Healer", MELEE="Melee", CASTER="Caster" }

-- BC_SUBROLE_TO_DAMAGECAT: maps roleroster sub-role label → BC damagecat key
-- Must be declared before BCCountTargetedByWho which references it.
local BC_SUBROLE_TO_CAT = {
    ["Arcane"]          = "ARCANE",
    ["Fire"]            = "FIRE",
    ["Frost"]           = "FROST",
    ["Nature"]          = "NATURE",
    ["Shadow"]          = "SHADOW",
    ["Physical Melee"]  = "PHYSICAL_MELEE",
    ["Physical Ranged"] = "PHYSICAL_RANGED",
    ["Hybrid Melee"]    = "HYBRID_MELEE",
}

-- Count raid/party members targeted by a rule's "who" filter.
-- Returns nil when roster data is unavailable (caller falls back to totalResponded).
local function BCCountTargetedByWho(who)
    local numRaid  = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    local total    = numRaid > 0 and numRaid or (numParty + 1)

    if not who or who.type == "everyone" then return total end

    if who.type == "class" then
        local count = 0
        if numRaid > 0 then
            for i = 1, numRaid do
                local _, cl = UnitClass("raid" .. i)
                if cl and cl == who.value then count = count + 1 end
            end
        else
            local _, myClass = UnitClass("player")
            if myClass == who.value then count = count + 1 end
            for i = 1, numParty do
                local _, cl = UnitClass("party" .. i)
                if cl and cl == who.value then count = count + 1 end
            end
        end
        return count
    end

    if who.type == "role" or who.type == "damagecat" then
        local specs = ART_RL_GetRosterSpecs and ART_RL_GetRosterSpecs()
        if not specs then return nil end
        local count = 0
        if numRaid > 0 then
            for i = 1, numRaid do
                local name = UnitName("raid" .. i)
                local spec = name and specs[name]
                if spec then
                    if who.type == "role" then
                        local broad = BC_ROLE_BROAD[who.value]
                        if broad and ART_GetSpecRole and ART_GetSpecRole(spec) == broad then
                            count = count + 1
                        end
                    else  -- damagecat
                        if ART_GetSpecSubRole then
                            local sub = ART_GetSpecSubRole(spec) or "Close-up Melee"
                            if BC_SUBROLE_TO_CAT[sub] == who.value then count = count + 1 end
                        end
                    end
                end
            end
        else
            local mySpec = AmptieRaidTools_PlayerInfo and AmptieRaidTools_PlayerInfo.spec
            local function checkSpec(spec)
                if not spec then return false end
                if who.type == "role" then
                    local broad = BC_ROLE_BROAD[who.value]
                    return broad and ART_GetSpecRole and ART_GetSpecRole(spec) == broad
                else
                    if ART_GetSpecSubRole then
                        local sub = ART_GetSpecSubRole(spec) or "Close-up Melee"
                        return BC_SUBROLE_TO_CAT[sub] == who.value
                    end
                end
                return false
            end
            if checkSpec(mySpec) then count = count + 1 end
            for i = 1, numParty do
                local name = UnitName("party" .. i)
                if checkSpec(name and specs[name]) then count = count + 1 end
            end
        end
        return count
    end

    return nil  -- spec type or unknown: caller uses totalResponded
end

local function BCPlayerMatchesWho(who)
    if not who or who.type == "everyone" then return true end
    if who.type == "class" then
        local _, classToken = UnitClass("player")
        return classToken == who.value
    end
    if who.type == "role" then
        -- delegate to IC's matching function if available
        if ART_IC_PlayerMatchesWho then return ART_IC_PlayerMatchesWho(who) end
        return false
    end
    if who.type == "damagecat" then
        if ART_IC_PlayerMatchesWho then return ART_IC_PlayerMatchesWho(who) end
        return false
    end
    if who.type == "spec" then
        if ART_IC_PlayerMatchesWho then return ART_IC_PlayerMatchesWho(who) end
        return false
    end
    return false
end

-- Evaluate one rule: returns pass (bool), missing (table of keys)
-- If ANY OR group is fully satisfied the rule passes.
-- If none are satisfied, the first buff key from the first failing OR group is returned
-- so the overlay shows one representative row per rule (not one per OR alternative).
local function BCEvaluateRule(rule)
    if not BCPlayerMatchesWho(rule.who) then return true, {} end
    if not rule.conditions or getn(rule.conditions) == 0 then return true, {} end
    local firstMiss = nil
    for oi = 1, getn(rule.conditions) do
        local grp = rule.conditions[oi]
        local miss = {}
        for ai = 1, getn(grp) do
            local b = ART_BC_BY_KEY[grp[ai].key]
            if b then
                local hasBuff = false
                if b.buffNames then
                    for fi = 1, getn(b.buffNames) do
                        if PlayerHasBuff(b.buffNames[fi]) then hasBuff = true; break end
                    end
                else
                    hasBuff = PlayerHasBuff(b.buffName)
                end
                if not hasBuff then tinsert(miss, grp[ai].key) end
            end
        end
        if getn(miss) == 0 then return true, {} end  -- OR group satisfied → rule passes
        if firstMiss == nil then firstMiss = miss end
    end
    return false, firstMiss or {}
end

-- Evaluate all applicable rules and send response
local function BCEvaluateSelfAndRespond(checkId, rules)
    if not checkId then return end
    local ch = BCGetMsgChannel()
    local allMissing = {}
    local pass = true
    for ri = 1, getn(rules) do
        local ok, miss = BCEvaluateRule(rules[ri])
        if not ok then
            pass = false
            for mi = 1, getn(miss) do tinsert(allMissing, miss[mi]) end
        end
    end
    -- Deduplicate
    local seen = {}
    local deduped = {}
    for i = 1, getn(allMissing) do
        if not seen[allMissing[i]] then
            seen[allMissing[i]] = true
            tinsert(deduped, allMissing[i])
        end
    end
    if ch then
        if pass then
            SendAddonMessage(BC_PREFIX, "BCK_OK^" .. checkId, ch)
        else
            local failStr = "BCK_NG^" .. checkId
            for i = 1, getn(deduped) do
                failStr = failStr .. "^" .. deduped[i]
            end
            if string.len(failStr) > 250 then failStr = string.sub(failStr, 1, 250) end
            SendAddonMessage(BC_PREFIX, failStr, ch)
        end
    end
    -- Record own result
    local myName = UnitName("player")
    if pass then
        bcCheckResults[myName] = { done=true, missing={} }
    else
        bcCheckResults[myName] = { done=true, missing=deduped }
    end
    if bcNotifyRefresh then bcNotifyRefresh() end
end

-- Encode rule conditions for message: "whoType^whoValue^key+key;key+key"
local function BCEncodeRule(rule)
    local who = rule.who or { type="everyone", value="*" }
    local orParts = {}
    for oi = 1, getn(rule.conditions or {}) do
        local grp = rule.conditions[oi]
        local andParts = {}
        for ai = 1, getn(grp) do tinsert(andParts, grp[ai].key) end
        local s = ""
        for pi = 1, getn(andParts) do
            if pi > 1 then s = s .. "+" end
            s = s .. andParts[pi]
        end
        tinsert(orParts, s)
    end
    local cond = ""
    for pi = 1, getn(orParts) do
        if pi > 1 then cond = cond .. ";" end
        cond = cond .. orParts[pi]
    end
    return (who.type or "everyone") .. "^" .. (who.value or "*") .. "^" .. cond
end

-- Decode rule from message segment
local function BCDecodeRule(data)
    local fields = BCSplit(data, "^")
    if getn(fields) < 2 then return nil end
    local whoType  = fields[1]
    local whoValue = fields[2]
    local condStr  = fields[3] or ""
    local conditions = {}
    if condStr ~= "" then
        for _, orStr in ipairs(BCSplit(condStr, ";")) do
            if orStr ~= "" then
                local grp = {}
                for _, k in ipairs(BCSplit(orStr, "+")) do
                    if k ~= "" then tinsert(grp, { key=k }) end
                end
                if getn(grp) > 0 then tinsert(conditions, grp) end
            end
        end
    end
    return { who={ type=whoType, value=whoValue }, conditions=conditions }
end

-- ── 5-second poll replaces reactive debounce ──────────────────
-- Dirty flags are set on aura/roster events; the single poll timer acts on
-- them at most once per 5 s, collapsing burst events (flask drinks, zone-ins,
-- sub-group reassignments) into one network send instead of many.
local bcAurasDirty     = false
local bcRosterDirty    = false
local BC_POLL_INTERVAL = 5.0
local bcPollTimer      = 0

local bcDebounceFrame = CreateFrame("Frame", nil, UIParent)
bcDebounceFrame:SetScript("OnUpdate", function()
    local dt = arg1
    bcPollTimer = bcPollTimer + dt
    if bcPollTimer < BC_POLL_INTERVAL then return end
    bcPollTimer = 0
    if bcAurasDirty then
        bcAurasDirty = false
        -- Re-evaluate own buffs with stored rules and re-send result
        if bcRcvCheckId and getn(bcRcvRules) > 0 then
            BCEvaluateSelfAndRespond(bcRcvCheckId, bcRcvRules)
        end
    end
    if bcRosterDirty then
        bcRosterDirty = false
        -- Re-broadcast check definition so new members receive the rules
        local db2 = amptieRaidToolsDB
        if db2 and db2.bcOverlayShown and db2.activeBCProfile then
            ART_BC_StartCheck(db2.activeBCProfile)
        end
    end
end)

-- Receive addon messages
local bcEvt = CreateFrame("Frame", nil, UIParent)
bcEvt:RegisterEvent("CHAT_MSG_ADDON")
bcEvt:RegisterEvent("PLAYER_AURAS_CHANGED")
bcEvt:SetScript("OnEvent", function()
    local evt = event
    local a1, a2, a3, a4 = arg1, arg2, arg3, arg4

    if evt == "PLAYER_AURAS_CHANGED" then
        bcAurasDirty = true   -- handled by 5s poll timer
        return
    end

    if evt ~= "CHAT_MSG_ADDON" then return end
    if a1 ~= BC_PREFIX then return end

    local fields = BCSplit(a2, "^")
    local msgType = fields[1]

    if msgType == "BCK_S" then
        -- BCK_S^checkId^numRules  — new check starting
        local cid      = fields[2]
        bcRcvCheckId  = cid
        bcRcvRules    = {}
        bcRcvExpected = tonumber(fields[3]) or 0

    elseif msgType == "BCK_R" then
        -- BCK_R^checkId^whoType^whoValue^condStr
        -- BCEncodeRule produces "whoType^whoValue^condStr", so splitting the full
        -- message gives fields[3]=whoType, fields[4]=whoValue, fields[5]=condStr.
        -- Reconstruct the three-part ruleData string for BCDecodeRule.
        if fields[2] ~= bcRcvCheckId then return end
        local ruleData = (fields[3] or "") .. "^" .. (fields[4] or "") .. "^" .. (fields[5] or "")
        local rule = BCDecodeRule(ruleData)
        if rule then
            tinsert(bcRcvRules, rule)
        end
        -- If we have all expected rules, evaluate self
        if bcRcvExpected > 0 and getn(bcRcvRules) >= bcRcvExpected then
            BCEvaluateSelfAndRespond(bcRcvCheckId, bcRcvRules)
        end

    elseif msgType == "BCK_E" then
        -- BCK_E^checkId  — end of rule transmission
        if fields[2] ~= bcRcvCheckId then return end
        if getn(bcRcvRules) > 0 then
            BCEvaluateSelfAndRespond(bcRcvCheckId, bcRcvRules)
        end

    elseif msgType == "BCK_OK" then
        -- BCK_OK^checkId
        if fields[2] ~= bcCheckId then return end
        local name = a4
        if name then
            bcCheckResults[name] = { done=true, missing={} }
            if bcNotifyRefresh then bcNotifyRefresh() end
        end

    elseif msgType == "BCK_NG" then
        -- BCK_NG^checkId^key^key^...
        if fields[2] ~= bcCheckId then return end
        local name = a4
        if name then
            local missing = {}
            for fi = 3, getn(fields) do
                if fields[fi] ~= "" then tinsert(missing, fields[fi]) end
            end
            bcCheckResults[name] = { done=true, missing=missing }
            if bcNotifyRefresh then bcNotifyRefresh() end
        end
    end
end)

-- ============================================================
-- Public: Start a check (called from UI button)
-- ============================================================
function ART_BC_StartCheck(profileName)
    local db = GetBCDB()
    local prof = db.buffCheckProfiles[profileName]
    if not prof or not prof.rules then return end

    local rules    = prof.rules
    local numRules = getn(rules)
    if numRules == 0 then return end

    -- Generate a new check ID
    bcCheckId        = tostring(math.mod(floor(GetTime() * 1000), 99999))
    bcCheckResults   = {}
    bcBuffTargetCount = {}

    -- Compute how many players each buff should apply to (based on rule's who-filter)
    for ri = 1, numRules do
        local rule = rules[ri]
        local targetN = BCCountTargetedByWho(rule.who)
        if targetN then
            for oi = 1, getn(rule.conditions or {}) do
                local grp = rule.conditions[oi]
                for ai = 1, getn(grp) do
                    local bk = grp[ai].key
                    if not bcBuffTargetCount[bk] or targetN > bcBuffTargetCount[bk] then
                        bcBuffTargetCount[bk] = targetN
                    end
                end
            end
        end
    end

    -- WoW 1.12: SendAddonMessage to RAID/PARTY does NOT echo back to sender.
    -- Store rules locally so our own PLAYER_AURAS_CHANGED debounce can re-evaluate,
    -- and evaluate self immediately instead of waiting for the echo that never comes.
    bcRcvCheckId  = bcCheckId
    bcRcvRules    = {}
    bcRcvExpected = numRules
    for ri = 1, numRules do tinsert(bcRcvRules, rules[ri]) end

    -- Evaluate self directly (no echo-back in vanilla)
    BCEvaluateSelfAndRespond(bcCheckId, bcRcvRules)

    -- Broadcast to group members if in one
    local ch = BCGetMsgChannel()
    if ch then
        SendAddonMessage(BC_PREFIX, "BCK_S^" .. bcCheckId .. "^" .. numRules, ch)
        for ri = 1, numRules do
            local encoded = BCEncodeRule(rules[ri])
            SendAddonMessage(BC_PREFIX, "BCK_R^" .. bcCheckId .. "^" .. encoded, ch)
        end
        SendAddonMessage(BC_PREFIX, "BCK_E^" .. bcCheckId, ch)
    end

    if bcNotifyRefresh then bcNotifyRefresh() end
end

-- ============================================================
-- Public API
-- ============================================================
function ART_BC_GetCheckResults()   return bcCheckResults end
function ART_BC_ClearResults()      bcCheckResults = {}; if bcNotifyRefresh then bcNotifyRefresh() end end
function ART_BC_GetProfileNames()
    local db = GetBCDB()
    local names = {}
    for n in pairs(db.buffCheckProfiles) do tinsert(names, n) end
    table.sort(names)
    return names
end
function ART_BC_SetNotifyRefresh(fn) bcNotifyRefresh = fn end

-- ============================================================
-- Overlay  (per-buff view: "BuffName: Player1, Player2, ...")
-- ============================================================
local bcOverlayFrame = nil
local BC_OVL_W      = 260
local BC_OVL_HDR_H  = 24
local BC_OVL_ROW_H  = 18
local BC_OVL_MAX_VIS = 16

local function CreateBCOverlay()
    local db = GetBCDB()

    local f = CreateFrame("Frame", "ART_BC_Overlay", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetWidth(BC_OVL_W)
    f:SetHeight(BC_OVL_HDR_H + BC_OVL_ROW_H + 8)
    if db.bcOverlayX and db.bcOverlayY then
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.bcOverlayX, db.bcOverlayY)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
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
        local db2 = amptieRaidToolsDB
        if db2 then db2.bcOverlayX = this:GetLeft(); db2.bcOverlayY = this:GetBottom() end
    end)

    -- Header
    local hdrFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hdrFS:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
    hdrFS:SetJustifyH("LEFT")
    hdrFS:SetTextColor(1, 0.82, 0, 1)
    hdrFS:SetText("Buff Check")
    f.hdrFS = hdrFS

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetWidth(18); closeBtn:SetHeight(18)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function()
        local db2 = amptieRaidToolsDB
        if db2 then db2.bcOverlayShown = false end
        bcOverlayFrame:Hide()
    end)

    -- Scroll
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     5, -(BC_OVL_HDR_H + 2))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 5)
    f.sf = sf

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(BC_OVL_W - 10)
    content:SetHeight(1)
    sf:SetScrollChild(content)
    f.content = content

    local scrollOff = 0
    local function SetOvlScroll(val)
        local maxS = math.max(content:GetHeight() - sf:GetHeight(), 0)
        if val < 0 then val = 0 end
        if val > maxS then val = maxS end
        scrollOff = val
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, val)
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function() SetOvlScroll(scrollOff - arg1 * BC_OVL_ROW_H * 3) end)
    f.SetOvlScroll = SetOvlScroll

    f.rows = {}

    local emptyLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -4)
    emptyLabel:SetTextColor(0.5, 0.5, 0.5, 1)
    emptyLabel:SetText("No check performed yet.")
    f.emptyLabel = emptyLabel

    bcOverlayFrame = f
end

local function RefreshBCOverlay()
    if not bcOverlayFrame then return end
    local db  = GetBCDB()
    local db2 = amptieRaidToolsDB

    -- Count total players who responded
    local totalResponded = 0
    for _, res in pairs(bcCheckResults) do
        if res.done then totalResponded = totalResponded + 1 end
    end

    -- Build buffKey → missing player list
    local missingByBuff = {}
    local buffOrder     = {}
    for name, res in pairs(bcCheckResults) do
        if res.done and getn(res.missing) > 0 then
            for mi = 1, getn(res.missing) do
                local bk = res.missing[mi]
                if not missingByBuff[bk] then
                    missingByBuff[bk] = {}
                    tinsert(buffOrder, bk)
                end
                tinsert(missingByBuff[bk], name)
            end
        end
    end

    local hasMissing = getn(buffOrder) > 0

    -- ── Visibility logic ─────────────────────────────────────────
    if not hasMissing then
        if bcCheckId and totalResponded > 0 then
            -- All responded and all OK → auto-hide
            if bcOverlayFrame:IsShown() then bcOverlayFrame:Hide() end
        else
            -- Waiting for responses or no check yet → show status label if frame is visible
            if bcOverlayFrame:IsShown() then
                bcOverlayFrame.hdrFS:SetText("Buff Check: " .. (db.activeBCProfile or "--"))
                for i = 1, getn(bcOverlayFrame.rows) do bcOverlayFrame.rows[i]:Hide() end
                bcOverlayFrame.emptyLabel:SetText(bcCheckId and "Waiting for responses..." or "No check performed yet.")
                bcOverlayFrame.emptyLabel:Show()
                local visH = BC_OVL_ROW_H + 8
                bcOverlayFrame.content:SetHeight(visH)
                bcOverlayFrame:SetHeight(BC_OVL_HDR_H + visH + 8)
            end
        end
        return
    end

    -- There are missing buffs → auto-show if overlay is enabled but was auto-hidden
    local inGroup = GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
    if db2 and db2.bcOverlayShown and not bcOverlayFrame:IsShown() and inGroup then
        bcOverlayFrame:Show()
    end
    if not bcOverlayFrame:IsShown() then return end  -- user explicitly closed

    -- Sort buff order by position in ART_BC_BUFFS table
    local buffPos = {}
    for i = 1, getn(ART_BC_BUFFS) do buffPos[ART_BC_BUFFS[i].key] = i end
    table.sort(buffOrder, function(a, b)
        return (buffPos[a] or 999) < (buffPos[b] or 999)
    end)

    bcOverlayFrame.hdrFS:SetText("Buff Check: " .. (db.activeBCProfile or "--"))
    -- Hide all rows
    for i = 1, getn(bcOverlayFrame.rows) do bcOverlayFrame.rows[i]:Hide() end
    bcOverlayFrame.emptyLabel:Hide()

    local numRows  = getn(buffOrder)
    local visCount = math.min(numRows, BC_OVL_MAX_VIS)
    bcOverlayFrame.content:SetHeight(math.max(numRows * BC_OVL_ROW_H, 1))
    bcOverlayFrame:SetHeight(BC_OVL_HDR_H + visCount * BC_OVL_ROW_H + 10)
    bcOverlayFrame.sf:SetHeight(visCount * BC_OVL_ROW_H)

    for i = 1, numRows do
        local bk   = buffOrder[i]
        local buff = ART_BC_BY_KEY[bk]
        local row  = bcOverlayFrame.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, bcOverlayFrame.content)
            row:SetHeight(BC_OVL_ROW_H)
            row:EnableMouse(true)
            row:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", tile=true, tileSize=16, edgeSize=0, insets={left=0,right=0,top=0,bottom=0} })
            row.lineFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.lineFS:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.lineFS:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function()
                if not this.missingNames or getn(this.missingNames) == 0 then return end
                GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
                GameTooltip:AddLine(this.buffLabel, 1, 0.82, 0, 1)
                GameTooltip:AddLine("Missing (" .. getn(this.missingNames) .. "):", 0.7, 0.7, 0.7, 1)
                for ni = 1, getn(this.missingNames) do
                    GameTooltip:AddLine(this.missingNames[ni], 1, 0.4, 0.4, 1)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            tinsert(bcOverlayFrame.rows, row)
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", bcOverlayFrame.content, "TOPLEFT", 0, -(i-1)*BC_OVL_ROW_H)
        row:SetPoint("RIGHT",   bcOverlayFrame.content, "RIGHT",   0, 0)
        if math.mod(i, 2) == 0 then
            row:SetBackdropColor(0.10, 0.10, 0.12, 0.5)
        else
            row:SetBackdropColor(0.06, 0.06, 0.08, 0.3)
        end

        local buffLabel  = buff and buff.name or bk
        local missList   = missingByBuff[bk]
        table.sort(missList)
        local missCount  = getn(missList)
        -- Use per-buff target count if available; fall back to totalResponded
        local targetN    = bcBuffTargetCount[bk] or totalResponded
        local haveCount  = math.max(0, targetN - missCount)

        row.buffLabel    = buffLabel
        row.missingNames = missList

        row.lineFS:SetText(
            "|cFFFFCC00" .. buffLabel .. ":|r " ..
            "|cFFFF6644" .. haveCount .. "|r" ..
            "|cFF888888/|r" ..
            "|cFFAAAAAA" .. targetN .. "|r"
        )
        row:Show()
    end

    -- Resize overlay width to fit the widest row (+ frame padding)
    -- Padding: 5px sf-left + 4px lineFS-left + 4px lineFS-right + 5px sf-right = 18px
    local PAD = 18
    local minW = bcOverlayFrame.hdrFS:GetStringWidth() + 32  -- header + close button space
    local maxW = minW
    for i = 1, numRows do
        local row = bcOverlayFrame.rows[i]
        if row and row:IsShown() then
            local tw = row.lineFS:GetStringWidth() + PAD
            if tw > maxW then maxW = tw end
        end
    end
    bcOverlayFrame:SetWidth(maxW)
end

-- ============================================================
-- Rule editor state
-- ============================================================
local bcRuleEditData = {
    profileName = nil,
    ruleIndex   = nil,
    who         = { type="everyone", value="*" },
    conditions  = {},
}
local BC_MAX_OR  = 4
local BC_MAX_AND = 4

-- ============================================================
-- Zone bindings (zone key → BC profile name)
-- ============================================================
local ART_BC_ZONES = {
    { key="MC",     label="Molten Core",          zone="Molten Core"            },
    { key="BWL",    label="Blackwing Lair",        zone="Blackwing Lair"         },
    { key="ONY",    label="Onyxia's Lair",         zone="Onyxia's Lair"          },
    { key="ZG",     label="Zul'Gurub",             zone="Zul'Gurub"              },
    { key="AQ20",   label="Ruins of Ahn'Qiraj",    zone="Ruins of Ahn'Qiraj"     },
    { key="AQ40",   label="Temple of Ahn'Qiraj",   zone="Temple of Ahn'Qiraj"    },
    { key="NAXX",   label="Naxxramas",             zone="Naxxramas"              },
    { key="ESANC",  label="Emerald Sanctum",       zone="Emerald Sanctum"        },
    { key="KARA10", label="Karazhan (10-man)",     zone="The Tower of Karazhan", maxRaid=14 },
    { key="KARA40", label="Karazhan (40-man)",     zone="The Tower of Karazhan", minRaid=15 },
}

local function ART_BC_GetCurrentZoneKey()
    local zone = GetRealZoneText()
    if not zone then return nil end
    local n = GetNumRaidMembers() or 0
    for i = 1, getn(ART_BC_ZONES) do
        local z = ART_BC_ZONES[i]
        if zone == z.zone then
            if (not z.minRaid or n >= z.minRaid) and (not z.maxRaid or n <= z.maxRaid) then
                return z.key
            end
        end
    end
    return nil
end

-- ============================================================
-- Main UI init
-- ============================================================
function AmptieRaidTools_InitBuffChecks(body)
    local panel = CreateFrame("Frame", "AmptieRaidToolsBuffChecksPanel", body)
    panel:SetAllPoints(body)

    AmptieRaidTools_RegisterComponent("buffchecks", panel)

    -- Trigger a fresh overlay check whenever the active profile changes.
    local function OnProfileChanged()
        if bcOverlayFrame and bcOverlayFrame:IsShown() then
            ART_BC_ClearResults()
            ART_BC_StartCheck(GetBCDB().activeBCProfile)
        end
    end

    -- Layout constants
    local LEFT_W    = 182
    local RIGHT_X   = LEFT_W + 20
    local RIGHT_W   = 380
    local PANEL_TOP_Y = -52

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    title:SetText("Buff Checks")
    title:SetTextColor(1, 0.82, 0, 1)

    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    sub:SetText("Define per-role buff requirements and verify them live in raid.")
    sub:SetTextColor(0.65, 0.65, 0.7, 1)

    local hdiv = panel:CreateTexture(nil, "ARTWORK")
    hdiv:SetHeight(1)
    hdiv:SetPoint("TOPLEFT",  sub, "BOTTOMLEFT",  0, -6)
    hdiv:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, 0)
    hdiv:SetTexture(0.25, 0.25, 0.28, 0.8)

    -- ── Left panel: profile management ───────────────────────────
    local profTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, PANEL_TOP_Y)
    profTitle:SetText("Profiles")
    profTitle:SetTextColor(0.9, 0.75, 0.2, 1)

    local activeProfLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    activeProfLabel:SetPoint("TOPLEFT", profTitle, "BOTTOMLEFT", 0, -4)
    activeProfLabel:SetWidth(LEFT_W)
    activeProfLabel:SetJustifyH("LEFT")
    activeProfLabel:SetTextColor(0.5, 0.8, 0.5, 1)

    -- Profile scroll list (bottom reserved for 5 rows of buttons = 138px)
    local profSF = CreateFrame("ScrollFrame", nil, panel)
    profSF:SetPoint("TOPLEFT",    activeProfLabel, "BOTTOMLEFT", 0, -4)
    profSF:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 138)
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
    profSF:SetScript("OnMouseWheel", function() SetProfScroll(profScrollOffset - arg1 * PROF_ROW_H * 2) end)

    local profRows = {}

    local function RefreshProfileList()
        local db = GetBCDB()
        activeProfLabel:SetText("Active: " .. (db.activeBCProfile or "--"))
        local names = ART_BC_GetProfileNames()
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
                    local db2 = GetBCDB()
                    if row.pname ~= db2.activeBCProfile then this:SetBackdropColor(0.18, 0.18, 0.22, 0.9) end
                end)
                row:SetScript("OnLeave", function()
                    local db2 = GetBCDB()
                    if row.pname ~= db2.activeBCProfile then this:SetBackdropColor(0, 0, 0, 0) end
                end)
                row:SetScript("OnClick", function()
                    local db2 = GetBCDB()
                    db2.activeBCProfile = row.pname
                    RefreshProfileList()
                    if _ART_BC_RefreshRules then _ART_BC_RefreshRules() end
                    OnProfileChanged()
                end)
                tinsert(profRows, row)
            end
            row:SetPoint("TOPLEFT", profContent, "TOPLEFT", 0, -(i-1)*PROF_ROW_H)
            row:SetPoint("RIGHT",   profContent, "RIGHT",   0, 0)
            row.pname = n
            row.rfs:SetText(n)
            local db2 = GetBCDB()
            if n == db2.activeBCProfile then
                row:SetBackdropColor(0.18, 0.22, 0.18, 0.9)
                row.rfs:SetTextColor(0.5, 1, 0.5, 1)
            else
                row:SetBackdropColor(0, 0, 0, 0)
                row.rfs:SetTextColor(0.85, 0.85, 0.85, 1)
            end
            row:Show()
        end
    end

    -- ── Buttons (5 rows × 26px = 130px total, bottom 8px pad) ────
    -- Row 1 (y=8):   New | Delete
    -- Row 2 (y=34):  Export | Import
    -- Row 3 (y=60):  Rename
    -- Row 4 (y=86):  From IC Profile
    -- Row 5 (y=112): Zone Bindings

    local newProfBtn = MakeBtn(panel, "New", 80, 22)
    newProfBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 86)

    local delProfBtn = MakeBtn(panel, "Delete", 80, 22)
    delProfBtn:SetPoint("LEFT", newProfBtn, "RIGHT", 4, 0)
    delProfBtn.label:SetTextColor(1, 0.4, 0.4, 1)

    local expBtn = MakeBtn(panel, "Export", 80, 22)
    expBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 60)

    local impBtn = MakeBtn(panel, "Import", 80, 22)
    impBtn:SetPoint("LEFT", expBtn, "RIGHT", 4, 0)

    local renameBtn = MakeBtn(panel, "Rename", 164, 22)
    renameBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 34)

    local fromICBtn = MakeBtn(panel, "From IC Profile", 164, 22)
    fromICBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)
    fromICBtn.label:SetTextColor(0.6, 0.85, 1, 1)

    local zoneBindBtn = MakeBtn(panel, "Zone Bindings", 164, 22)
    zoneBindBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 112)
    zoneBindBtn.label:SetTextColor(0.7, 1, 0.7, 1)

    -- Inline new-profile editbox
    local newProfEdit = MakeEditBox(UIParent, 164, 22)
    newProfEdit:SetFrameStrata("FULLSCREEN_DIALOG")
    newProfEdit:SetPoint("BOTTOM", newProfBtn, "TOP", 42, 4)
    newProfEdit:SetMaxLetters(40)
    newProfEdit:Hide()

    newProfBtn:SetScript("OnClick", function()
        newProfEdit:SetText("")
        newProfEdit:Show()
        newProfEdit:SetFocus()
    end)

    newProfEdit:SetScript("OnEnterPressed", function()
        local name = string.gsub(this:GetText(), "^%s*(.-)%s*$", "%1")
        if name == "" then this:Hide(); return end
        local db = GetBCDB()
        if not db.buffCheckProfiles[name] then
            db.buffCheckProfiles[name] = { rules={} }
        end
        db.activeBCProfile = name
        this:ClearFocus(); this:Hide()
        RefreshProfileList()
        if _ART_BC_RefreshRules then _ART_BC_RefreshRules() end
        OnProfileChanged()
    end)

    delProfBtn:SetScript("OnClick", function()
        local db = GetBCDB()
        local active = db.activeBCProfile
        if active == "Default" then return end
        db.buffCheckProfiles[active] = nil
        db.activeBCProfile = "Default"
        RefreshProfileList()
        if _ART_BC_RefreshRules then _ART_BC_RefreshRules() end
        OnProfileChanged()
    end)

    -- Rename editbox
    local renameProfEdit = MakeEditBox(UIParent, 164, 22)
    renameProfEdit:SetFrameStrata("FULLSCREEN_DIALOG")
    renameProfEdit:SetPoint("BOTTOM", renameBtn, "TOP", 0, 4)
    renameProfEdit:SetMaxLetters(40)
    renameProfEdit:Hide()

    renameBtn:SetScript("OnClick", function()
        local db = GetBCDB()
        renameProfEdit:SetText(db.activeBCProfile or "")
        renameProfEdit:Show()
        renameProfEdit:SetFocus()
        renameProfEdit:HighlightText()
    end)

    renameProfEdit:SetScript("OnEnterPressed", function()
        local newName = string.gsub(this:GetText(), "^%s*(.-)%s*$", "%1")
        local db = GetBCDB()
        local oldName = db.activeBCProfile
        if newName == "" or newName == oldName then this:ClearFocus(); this:Hide(); return end
        if db.buffCheckProfiles[newName] then this:ClearFocus(); this:Hide(); return end
        db.buffCheckProfiles[newName] = db.buffCheckProfiles[oldName]
        db.buffCheckProfiles[oldName] = nil
        db.activeBCProfile = newName
        this:ClearFocus(); this:Hide()
        RefreshProfileList()
        if _ART_BC_RefreshRules then _ART_BC_RefreshRules() end
        OnProfileChanged()
    end)

    -- ── Share modal (Export / Import) ─────────────────────────────
    local shareModal = CreateFrame("Frame", nil, UIParent)
    shareModal:SetAllPoints(UIParent)
    shareModal:SetFrameStrata("FULLSCREEN_DIALOG")
    shareModal:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", tile=true, tileSize=16, edgeSize=0, insets={left=0,right=0,top=0,bottom=0} })
    shareModal:SetBackdropColor(0, 0, 0, 0.60)
    shareModal:EnableMouse(true)
    shareModal:Hide()

    local smInner = CreateFrame("Frame", nil, shareModal)
    smInner:SetWidth(420); smInner:SetHeight(130)
    smInner:SetPoint("CENTER", shareModal, "CENTER", 0, 0)
    smInner:SetBackdrop(BD_PANEL)
    smInner:SetBackdropColor(0.10, 0.10, 0.13, 0.98)
    smInner:SetBackdropBorderColor(0.45, 0.45, 0.50, 1)

    local smTitle = smInner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    smTitle:SetPoint("TOPLEFT", smInner, "TOPLEFT", 10, -10)
    smTitle:SetTextColor(1, 0.82, 0, 1)

    local smEB = CreateFrame("EditBox", nil, smInner)
    smEB:SetWidth(400); smEB:SetHeight(50)
    smEB:SetPoint("TOPLEFT", smTitle, "BOTTOMLEFT", 0, -8)
    smEB:SetAutoFocus(false)
    smEB:SetMultiLine(false)
    smEB:SetMaxLetters(0)
    smEB:SetFontObject(GameFontHighlightSmall)
    smEB:SetTextInsets(4, 4, 0, 0)
    smEB:SetBackdrop(BD_EDIT)
    smEB:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    smEB:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    smEB:SetScript("OnEscapePressed", function() shareModal:Hide() end)

    local smClose = MakeBtn(smInner, "Close", 80, 22)
    smClose:SetPoint("BOTTOMRIGHT", smInner, "BOTTOMRIGHT", -10, 10)
    smClose:SetScript("OnClick", function() shareModal:Hide() end)

    local smImportBtn = MakeBtn(smInner, "Import", 80, 22)
    smImportBtn:SetPoint("RIGHT", smClose, "LEFT", -6, 0)
    smImportBtn:Hide()
    smInner.importBtn = smImportBtn

    expBtn:SetScript("OnClick", function()
        local prof = GetActiveBCProfile()
        local exportStr = BCExportProfile(prof)
        smTitle:SetText("Export Profile  (select all + Ctrl+C to copy)")
        smEB:SetText(exportStr)
        smInner.importBtn:Hide()
        shareModal:Show()
        smEB:SetFocus()
        smEB:HighlightText()
    end)

    impBtn:SetScript("OnClick", function()
        smTitle:SetText("Import Profile  (paste string + click Import)")
        smEB:SetText("")
        smInner.importBtn:Show()
        shareModal:Show()
        smEB:SetFocus()
    end)

    smImportBtn:SetScript("OnClick", function()
        local str = smEB:GetText()
        local prof, err = BCImportProfile(str)
        if not prof then
            smTitle:SetText("Error: " .. (err or "unknown"))
            return
        end
        local db = GetBCDB()
        local baseName = "Imported"
        local name = baseName
        local n = 1
        while db.buffCheckProfiles[name] do n = n+1; name = baseName .. " " .. n end
        db.buffCheckProfiles[name] = prof
        db.activeBCProfile = name
        shareModal:Hide()
        RefreshProfileList()
        if _ART_BC_RefreshRules then _ART_BC_RefreshRules() end
        OnProfileChanged()
    end)

    -- ── From IC Profile modal ─────────────────────────────────────
    local icModal = CreateFrame("Frame", nil, UIParent)
    icModal:SetAllPoints(UIParent)
    icModal:SetFrameStrata("FULLSCREEN_DIALOG")
    icModal:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", tile=true, tileSize=16, edgeSize=0, insets={left=0,right=0,top=0,bottom=0} })
    icModal:SetBackdropColor(0, 0, 0, 0.60)
    icModal:EnableMouse(true)
    icModal:Hide()

    local icInner = CreateFrame("Frame", nil, icModal)
    icInner:SetWidth(320); icInner:SetHeight(110)
    icInner:SetPoint("CENTER", icModal, "CENTER", 0, 0)
    icInner:SetBackdrop(BD_PANEL)
    icInner:SetBackdropColor(0.10, 0.10, 0.13, 0.98)
    icInner:SetBackdropBorderColor(0.45, 0.45, 0.50, 1)

    local icModalTitle = icInner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    icModalTitle:SetPoint("TOPLEFT", icInner, "TOPLEFT", 10, -10)
    icModalTitle:SetText("New Profile from IC Profile")
    icModalTitle:SetTextColor(0.6, 0.85, 1, 1)

    local icNameLabel = icInner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icNameLabel:SetPoint("TOPLEFT", icModalTitle, "BOTTOMLEFT", 0, -10)
    icNameLabel:SetText("New profile name:")
    icNameLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    local icNameEB = MakeEditBox(icInner, 190, 20)
    icNameEB:SetPoint("LEFT", icNameLabel, "RIGHT", 6, 0)
    icNameEB:SetMaxLetters(40)

    local icSrcLabel = icInner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icSrcLabel:SetPoint("TOPLEFT", icNameLabel, "BOTTOMLEFT", 0, -12)
    icSrcLabel:SetText("IC Profile:")
    icSrcLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    local icSrcDd = MakeDropdown(icInner, 190, 10)
    icSrcDd.btn:SetPoint("LEFT", icSrcLabel, "RIGHT", 6, 0)

    local icCreateBtn = MakeBtn(icInner, "Create", 80, 22)
    icCreateBtn:SetPoint("BOTTOMRIGHT", icInner, "BOTTOMRIGHT", -10, 10)

    local icCancelBtn = MakeBtn(icInner, "Cancel", 80, 22)
    icCancelBtn:SetPoint("RIGHT", icCreateBtn, "LEFT", -6, 0)
    icCancelBtn:SetScript("OnClick", function() icModal:Hide() end)

    fromICBtn:SetScript("OnClick", function()
        -- Populate IC profile dropdown
        local icNames = {}
        if ART_IC_GetProfileNames then
            icNames = ART_IC_GetProfileNames()
        end
        local ddItems = {}
        for i = 1, getn(icNames) do tinsert(ddItems, { key=icNames[i], label=icNames[i] }) end
        icSrcDd.SetItems(ddItems)
        if getn(icNames) > 0 then
            icSrcDd.SetValue(icNames[1], icNames[1])
        end
        local db = GetBCDB()
        icNameEB:SetText((db.activeBCProfile or "New") .. " (Buffs)")
        icModal:Show()
        icNameEB:SetFocus()
    end)

    icCreateBtn:SetScript("OnClick", function()
        local newName = string.gsub(icNameEB:GetText(), "^%s*(.-)%s*$", "%1")
        if newName == "" then return end
        local srcName = icSrcDd.GetKey()
        local db = GetBCDB()
        local newProf
        if srcName and amptieRaidToolsDB and amptieRaidToolsDB.itemCheckProfiles and amptieRaidToolsDB.itemCheckProfiles[srcName] then
            newProf = ConvertICProfileToBC(amptieRaidToolsDB.itemCheckProfiles[srcName])
        else
            newProf = { rules={} }
        end
        local finalName = newName
        local n = 1
        while db.buffCheckProfiles[finalName] do n = n+1; finalName = newName .. " " .. n end
        db.buffCheckProfiles[finalName] = newProf
        db.activeBCProfile = finalName
        icModal:Hide()
        RefreshProfileList()
        if _ART_BC_RefreshRules then _ART_BC_RefreshRules() end
        OnProfileChanged()
    end)

    -- ── Zone Bindings modal ───────────────────────────────────────
    local zoneModal = CreateFrame("Frame", nil, UIParent)
    zoneModal:SetAllPoints(UIParent)
    zoneModal:SetFrameStrata("FULLSCREEN_DIALOG")
    zoneModal:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", tile=true, tileSize=16, edgeSize=0, insets={left=0,right=0,top=0,bottom=0} })
    zoneModal:SetBackdropColor(0, 0, 0, 0.6)
    zoneModal:EnableMouse(true)
    zoneModal:Hide()

    local zoneInner = CreateFrame("Frame", nil, zoneModal)
    zoneInner:SetWidth(380)
    zoneInner:SetHeight(60 + getn(ART_BC_ZONES) * 28 + 16)
    zoneInner:SetPoint("CENTER", zoneModal, "CENTER", 0, 0)
    zoneInner:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4},
    })
    zoneInner:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
    zoneInner:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)

    local zoneTitleFS = zoneInner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    zoneTitleFS:SetPoint("TOPLEFT", zoneInner, "TOPLEFT", 14, -14)
    zoneTitleFS:SetText("Zone Bindings")
    zoneTitleFS:SetTextColor(1, 0.82, 0, 1)

    local zoneSubFS = zoneInner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneSubFS:SetPoint("TOPLEFT", zoneTitleFS, "BOTTOMLEFT", 0, -4)
    zoneSubFS:SetText("Automatically activate a profile when entering a raid zone.")
    zoneSubFS:SetTextColor(0.65, 0.65, 0.7, 1)

    local zoneCloseBtn = CreateFrame("Button", nil, zoneInner, "UIPanelCloseButton")
    zoneCloseBtn:SetWidth(24); zoneCloseBtn:SetHeight(24)
    zoneCloseBtn:SetPoint("TOPRIGHT", zoneInner, "TOPRIGHT", 2, 2)
    zoneCloseBtn:SetScript("OnClick", function() zoneModal:Hide() end)

    -- Column headers
    local zoneColZone = zoneInner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneColZone:SetPoint("TOPLEFT", zoneSubFS, "BOTTOMLEFT", 0, -10)
    zoneColZone:SetText("Zone")
    zoneColZone:SetTextColor(0.7, 0.7, 0.7, 1)

    local zoneColProf = zoneInner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneColProf:SetPoint("LEFT", zoneColZone, "LEFT", 200, 0)
    zoneColProf:SetText("Profile")
    zoneColProf:SetTextColor(0.7, 0.7, 0.7, 1)

    local ZN_BTN_BACKDROP = {
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=12,
        insets={left=3,right=3,top=3,bottom=3},
    }

    local zoneRowBtns = {}

    local function RefreshZoneModal()
        local db2 = amptieRaidToolsDB
        if not db2 then return end
        if not db2.bcZoneBindings then db2.bcZoneBindings = {} end
        for i = 1, getn(zoneRowBtns) do
            local rb = zoneRowBtns[i]
            local val = db2.bcZoneBindings[rb.zoneKey] or "none"
            rb.fs:SetText(val)
            if val == "none" then
                rb.fs:SetTextColor(0.5, 0.5, 0.5, 1)
            else
                rb.fs:SetTextColor(0.5, 1, 0.5, 1)
            end
        end
    end

    local function GetNextZoneProfile(cur)
        local db2 = amptieRaidToolsDB
        if not db2 or not db2.buffCheckProfiles then return "none" end
        local names = { "none" }
        for n in pairs(db2.buffCheckProfiles) do tinsert(names, n) end
        table.sort(names)
        for i = 1, getn(names) do
            if names[i] == cur then
                return names[i + 1] or names[1]
            end
        end
        return "none"
    end

    for i = 1, getn(ART_BC_ZONES) do
        local zinfo = ART_BC_ZONES[i]
        local yOff  = -10 - (i - 1) * 28

        local lbl = zoneInner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", zoneColZone, "BOTTOMLEFT", 0, yOff)
        lbl:SetWidth(190)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(zinfo.label)

        local btn = CreateFrame("Button", nil, zoneInner)
        btn:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
        btn:SetWidth(140)
        btn:SetHeight(22)
        btn:SetBackdrop(ZN_BTN_BACKDROP)
        btn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
        btn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
        btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        btn.zoneKey = zinfo.key

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn.fs = fs

        btn:SetScript("OnClick", function()
            local db2 = amptieRaidToolsDB
            if not db2 then return end
            if not db2.bcZoneBindings then db2.bcZoneBindings = {} end
            local cur = db2.bcZoneBindings[this.zoneKey] or "none"
            db2.bcZoneBindings[this.zoneKey] = GetNextZoneProfile(cur)
            RefreshZoneModal()
        end)

        tinsert(zoneRowBtns, btn)
    end

    zoneModal:SetScript("OnShow", function() RefreshZoneModal() end)

    zoneBindBtn:SetScript("OnClick", function()
        zoneModal:Show()
    end)

    -- ── Rules panel (right side) ──────────────────────────────────
    local rulesPanel = CreateFrame("Frame", nil, panel)
    rulesPanel:SetPoint("TOPLEFT",     panel, "TOPLEFT", RIGHT_X, PANEL_TOP_Y)
    rulesPanel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)

    local rulesHdr = rulesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rulesHdr:SetPoint("TOPLEFT", rulesPanel, "TOPLEFT", 0, 0)
    rulesHdr:SetTextColor(0.9, 0.75, 0.2, 1)

    local addRuleBtn = MakeBtn(rulesPanel, "+ Add Rule", 90, 22)
    addRuleBtn:SetPoint("TOPRIGHT", rulesPanel, "TOPRIGHT", 0, 0)

    -- Toggle overlay button
    local ovlBtn = MakeBtn(rulesPanel, "Show Overlay", 100, 22)
    ovlBtn:SetPoint("RIGHT", addRuleBtn, "LEFT", -6, 0)

    local function UpdateOvlBtn()
        if bcOverlayFrame and bcOverlayFrame:IsShown() then
            ovlBtn.label:SetText("Hide Overlay")
            ovlBtn:SetBackdropColor(0.22, 0.17, 0.03, 0.95)
            ovlBtn:SetBackdropBorderColor(1, 0.82, 0, 1)
            ovlBtn.label:SetTextColor(1, 0.82, 0, 1)
        else
            ovlBtn.label:SetText("Show Overlay")
            ovlBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
            ovlBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
            ovlBtn.label:SetTextColor(0.85, 0.85, 0.85, 1)
        end
    end

    ovlBtn:SetScript("OnClick", function()
        if not bcOverlayFrame then CreateBCOverlay() end
        if bcOverlayFrame:IsShown() then
            local db2 = amptieRaidToolsDB
            if db2 then db2.bcOverlayShown = false end
            bcOverlayFrame:Hide()
        else
            local db2 = amptieRaidToolsDB
            if db2 then db2.bcOverlayShown = true end
            bcOverlayFrame:Show()
            local activeProf = db2 and db2.activeBCProfile
            if activeProf then
                ART_BC_StartCheck(activeProf)
            else
                RefreshBCOverlay()
            end
        end
        UpdateOvlBtn()
    end)

    -- Rules scroll
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
    rulesSF:SetScript("OnMouseWheel", function() SetRulesScroll(rulesScrollOffset - arg1 * RULE_ROW_H * 2) end)

    local ruleRows = {}
    local editorPanel  -- forward ref

    local function RefreshRuleList()
        local db  = GetBCDB()
        rulesHdr:SetText("Rules  —  " .. (db.activeBCProfile or "--"))
        local prof  = GetActiveBCProfile()
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
                row.condFS:SetWidth(210)
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
            row.whoFS:SetText(BCWhoLabel(rule.who))
            row.condFS:SetText(CondBCSummary(rule.conditions))

            local ruleIdx = i
            row.editBtn:SetScript("OnClick", function()
                local prof2 = GetActiveBCProfile()
                if not prof2 then return end
                local r2 = prof2.rules[ruleIdx]
                if not r2 then return end
                bcRuleEditData.profileName = GetBCDB().activeBCProfile
                bcRuleEditData.ruleIndex   = ruleIdx
                bcRuleEditData.who         = { type=r2.who and r2.who.type or "everyone", value=r2.who and r2.who.value or "*" }
                bcRuleEditData.conditions  = BCDeepCopy(r2.conditions or {})
                editorPanel:Show()
                if _ART_BC_RefreshRules then _ART_BC_RefreshRules() end
            end)
            row.delBtn:SetScript("OnClick", function()
                local prof2 = GetActiveBCProfile()
                if not prof2 then return end
                table.remove(prof2.rules, ruleIdx)
                RefreshRuleList()
            end)
            row:Show()
        end
    end

    _ART_BC_RefreshRules = RefreshRuleList

    -- ── Rule editor overlay ───────────────────────────────────────
    editorPanel = CreateFrame("Frame", nil, UIParent)
    editorPanel:SetAllPoints(panel)
    editorPanel:SetFrameStrata("FULLSCREEN_DIALOG")
    editorPanel:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", tile=true, tileSize=16, edgeSize=0, insets={left=0,right=0,top=0,bottom=0} })
    editorPanel:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
    editorPanel:EnableMouse(true)
    editorPanel:Hide()
    panel:SetScript("OnHide", function()
        editorPanel:Hide()
        shareModal:Hide()
        icModal:Hide()
        renameProfEdit:Hide(); renameProfEdit:ClearFocus()
        newProfEdit:Hide(); newProfEdit:ClearFocus()
        for i = 1, getn(ART_BC_dropdownHiders) do ART_BC_dropdownHiders[i]() end
    end)

    local edHdr = editorPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    edHdr:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 10, -10)
    edHdr:SetTextColor(1, 0.82, 0, 1)

    local edSaveBtn   = MakeBtn(editorPanel, "Save",   80, 22)
    local edCancelBtn = MakeBtn(editorPanel, "Cancel", 80, 22)
    edSaveBtn:SetPoint("TOPRIGHT", editorPanel, "TOPRIGHT", -10, -8)
    edCancelBtn:SetPoint("RIGHT", edSaveBtn, "LEFT", -6, 0)

    edCancelBtn:SetScript("OnClick", function()
        editorPanel:Hide()
        RefreshRuleList()
    end)

    -- WHO section
    local edWhoLbl = editorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    edWhoLbl:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 10, -44)
    edWhoLbl:SetText("Who:")
    edWhoLbl:SetTextColor(0.7, 0.7, 0.7, 1)

    local whoTypeDd  = MakeDropdown(editorPanel, 110, 6)
    whoTypeDd.btn:SetPoint("LEFT", edWhoLbl, "RIGHT", 8, 0)

    local whoValueDd = MakeDropdown(editorPanel, 130, 10)
    whoValueDd.btn:SetPoint("LEFT", whoTypeDd.btn, "RIGHT", 6, 0)

    local function PopulateWhoValues(typeKey)
        local items = ART_BC_WHO_VALUES[typeKey] or ART_BC_WHO_VALUES.everyone
        local ddItems = {}
        for i = 1, getn(items) do tinsert(ddItems, { key=items[i].key, label=items[i].label }) end
        whoValueDd.SetItems(ddItems)
    end

    -- Populate WHO type dropdown
    local whoTypeItems = {}
    for i = 1, getn(ART_BC_WHO_TYPES) do tinsert(whoTypeItems, { key=ART_BC_WHO_TYPES[i].key, label=ART_BC_WHO_TYPES[i].label }) end
    whoTypeDd.SetItems(whoTypeItems)

    whoTypeDd.onSelect = function(key, label)
        PopulateWhoValues(key)
        local vals = ART_BC_WHO_VALUES[key] or ART_BC_WHO_VALUES.everyone
        bcRuleEditData.who.type  = key
        bcRuleEditData.who.value = vals[1].key
        whoValueDd.SetValue(vals[1].key, vals[1].label)
    end

    whoValueDd.onSelect = function(key, label)
        bcRuleEditData.who.value = key
    end

    -- Conditions section
    local edCondLbl = editorPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    edCondLbl:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 10, -76)
    edCondLbl:SetText("Conditions (OR groups):")
    edCondLbl:SetTextColor(0.7, 0.7, 0.7, 1)

    local addOrBtn = MakeBtn(editorPanel, "+ OR Group", 90, 20)
    addOrBtn:SetPoint("LEFT", edCondLbl, "RIGHT", 10, 0)

    -- OR group rows
    local orGroupFrames = {}

    local function RefreshEditor()
        edHdr:SetText(bcRuleEditData.ruleIndex and "Edit Rule" or "New Rule")

        -- Restore WHO dropdowns
        local whoType  = bcRuleEditData.who.type  or "everyone"
        local whoValue = bcRuleEditData.who.value or "*"
        for i = 1, getn(ART_BC_WHO_TYPES) do
            if ART_BC_WHO_TYPES[i].key == whoType then
                whoTypeDd.SetValue(whoType, ART_BC_WHO_TYPES[i].label); break
            end
        end
        PopulateWhoValues(whoType)
        local vals = ART_BC_WHO_VALUES[whoType] or ART_BC_WHO_VALUES.everyone
        for i = 1, getn(vals) do
            if vals[i].key == whoValue then
                whoValueDd.SetValue(whoValue, vals[i].label); break
            end
        end
        bcRuleEditData.who.type  = whoType
        bcRuleEditData.who.value = whoValue

        -- Hide old OR group frames
        for i = 1, getn(orGroupFrames) do orGroupFrames[i]:Hide() end

        local conds = bcRuleEditData.conditions
        local yBase = -96

        for oi = 1, getn(conds) do
            local grp = conds[oi]
            local gf  = orGroupFrames[oi]
            if not gf then
                gf = CreateFrame("Frame", nil, editorPanel)
                gf:SetHeight(28)
                gf.andDds  = {}
                gf.addAnd  = MakeBtn(gf, "+ AND", 52, 20)
                gf.orLabel = gf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                gf.orLabel:SetPoint("LEFT", gf, "LEFT", 4, 0)
                gf.orLabel:SetTextColor(0.6, 0.85, 1, 1)
                gf.delOrBtn = MakeBtn(gf, "×", 20, 20)
                gf.delOrBtn.label:SetTextColor(1, 0.4, 0.4, 1)
                tinsert(orGroupFrames, gf)
            end
            gf:ClearAllPoints()
            gf:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 10, yBase - (oi-1)*32)
            gf:SetPoint("RIGHT",   editorPanel, "RIGHT", -10, 0)
            gf.orLabel:SetText("OR " .. oi .. ":")

            -- Hide old AND dropdowns
            for k = 1, getn(gf.andDds) do gf.andDds[k].btn:Hide() end

            -- Create / refresh AND item dropdowns
            local xOff = 52
            for ai = 1, getn(grp) do
                local andDd = gf.andDds[ai]
                if not andDd then
                    andDd = MakeBuffDropdown(gf, 160)
                    tinsert(gf.andDds, andDd)
                end
                andDd.btn:ClearAllPoints()
                andDd.btn:SetPoint("LEFT", gf, "LEFT", xOff + (ai-1)*174, 0)
                andDd.btn:Show()
                -- Set current value
                local b = ART_BC_BY_KEY[grp[ai].key]
                if b then andDd.SetValue(grp[ai].key, b.name) end

                local captOi, captAi = oi, ai
                andDd.onSelect = function(k, l)
                    local conds2 = bcRuleEditData.conditions
                    if conds2[captOi] and conds2[captOi][captAi] then
                        conds2[captOi][captAi].key = k
                    end
                end
                xOff = xOff + 0  -- positions computed per-ai above
            end

            -- + AND button
            gf.addAnd:ClearAllPoints()
            gf.addAnd:SetPoint("LEFT", gf, "LEFT", 52 + getn(grp)*174, 0)
            if getn(grp) < BC_MAX_AND then
                gf.addAnd:Show()
            else
                gf.addAnd:Hide()
            end

            local captOi2 = oi
            gf.addAnd:SetScript("OnClick", function()
                local conds2 = bcRuleEditData.conditions
                if conds2[captOi2] and getn(conds2[captOi2]) < BC_MAX_AND then
                    local firstKey = ART_BC_BUFFS[1].key
                    tinsert(conds2[captOi2], { key=firstKey })
                    RefreshEditor()
                end
            end)

            -- Delete OR group button
            gf.delOrBtn:ClearAllPoints()
            gf.delOrBtn:SetPoint("RIGHT", gf, "RIGHT", 0, 0)
            gf.delOrBtn:Show()
            local captOi3 = oi
            gf.delOrBtn:SetScript("OnClick", function()
                table.remove(bcRuleEditData.conditions, captOi3)
                RefreshEditor()
            end)

            gf:Show()
        end

        -- + OR Group button
        addOrBtn:SetScript("OnClick", function()
            if getn(bcRuleEditData.conditions) < BC_MAX_OR then
                tinsert(bcRuleEditData.conditions, { { key=ART_BC_BUFFS[1].key } })
                RefreshEditor()
            end
        end)
    end

    addRuleBtn:SetScript("OnClick", function()
        bcRuleEditData.profileName = GetBCDB().activeBCProfile
        bcRuleEditData.ruleIndex   = nil
        bcRuleEditData.who         = { type="everyone", value="*" }
        bcRuleEditData.conditions  = {}
        editorPanel:Show()
        RefreshEditor()
    end)

    edSaveBtn:SetScript("OnClick", function()
        local prof = GetActiveBCProfile()
        if not prof then editorPanel:Hide(); return end
        local newRule = {
            who        = { type=bcRuleEditData.who.type, value=bcRuleEditData.who.value },
            conditions = BCDeepCopy(bcRuleEditData.conditions),
        }
        if bcRuleEditData.ruleIndex then
            prof.rules[bcRuleEditData.ruleIndex] = newRule
        else
            tinsert(prof.rules, newRule)
        end
        editorPanel:Hide()
        RefreshRuleList()
    end)

    -- ── Events (roster updates + login) ──────────────────────────
    local bcUiEvt = CreateFrame("Frame", nil, UIParent)
    bcUiEvt:RegisterEvent("RAID_ROSTER_UPDATE")
    bcUiEvt:RegisterEvent("PARTY_MEMBERS_CHANGED")
    bcUiEvt:RegisterEvent("PLAYER_ENTERING_WORLD")
    bcUiEvt:RegisterEvent("PLAYER_LOGIN")
    -- Apply zone binding: switch to the bound profile for the current raid zone
    local function ApplyZoneBinding()
        local db2 = amptieRaidToolsDB
        if not db2 then return end
        local bindings = db2.bcZoneBindings
        if not bindings then return end
        local zkey = ART_BC_GetCurrentZoneKey()
        if not zkey then return end
        local profName = bindings[zkey]
        if not profName or profName == "none" then return end
        if not db2.buffCheckProfiles or not db2.buffCheckProfiles[profName] then return end
        if db2.activeBCProfile == profName then return end
        db2.activeBCProfile = profName
        RefreshProfileList()
        if _ART_BC_RefreshRules then _ART_BC_RefreshRules() end
        OnProfileChanged()
    end

    bcUiEvt:SetScript("OnEvent", function()
        local ev = event
        if bcOverlayFrame then RefreshBCOverlay() end

        if ev == "PLAYER_ENTERING_WORLD" or ev == "PLAYER_LOGIN" then
            local db2 = amptieRaidToolsDB
            -- Apply zone binding first so the correct profile is active
            ApplyZoneBinding()
            -- Restore overlay and start initial check if it was active
            if db2 and db2.bcOverlayShown and db2.activeBCProfile then
                if not bcOverlayFrame then CreateBCOverlay() end
                bcOverlayFrame:Show()
                ART_BC_StartCheck(db2.activeBCProfile)
                UpdateOvlBtn()
            end
        elseif ev == "RAID_ROSTER_UPDATE" or ev == "PARTY_MEMBERS_CHANGED" then
            -- Re-check zone binding (raid size may have changed, e.g. Kara 10→40)
            ApplyZoneBinding()
            -- Re-broadcast rules with debounce so new members receive them
            local db2 = amptieRaidToolsDB
            if db2 and db2.bcOverlayShown then
                bcRosterDirty = true   -- handled by 5s poll timer
            end
            -- Close overlay when leaving group entirely
            if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then
                if bcOverlayFrame then bcOverlayFrame:Hide() end
                UpdateOvlBtn()
            end
        end
    end)

    -- Wire overlay refresh to result changes
    ART_BC_SetNotifyRefresh(function()
        if bcOverlayFrame then RefreshBCOverlay() end
        UpdateOvlBtn()
    end)

    -- Initial populate
    panel:SetScript("OnShow", function()
        RefreshProfileList()
        RefreshRuleList()
        UpdateOvlBtn()
    end)

    RefreshProfileList()
    RefreshRuleList()
end
