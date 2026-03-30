-- amptieRaidTools - Komponente: Übersicht (Home)
-- Zeigt u. a. Spielerinfos aus AmptieRaidTools_PlayerInfo (playerinfo.lua). Lua 5.0.

AmptieRaidTools_LastAnnouncedSpec = AmptieRaidTools_LastAnnouncedSpec or nil

-- Role lookup table (global so other components can use it)
-- Maps spec name → detailed sub-role
ART_SPEC_ROLE = {
	-- Tank
	["Protection"]       = "Tank",
	["Fury Protection"]  = "Tank",
	["Deep Protection"]  = "Tank",
	["Enhancement Tank"] = "Tank",
	["Feral Bear"]       = "Tank",
	-- Healer
	["Holy"]             = "Healer",
	["Discipline Holy"]  = "Healer",
	["Restoration"]      = "Healer",
	-- Ranged Melee
	["Beastmaster"]      = "Ranged Melee",
	["Marksman"]         = "Ranged Melee",
	-- Hybrid Melee
	["Retribution"]      = "Hybrid Melee",
	["Enhancer"]         = "Hybrid Melee",
	["Enhancement"]      = "Hybrid Melee",
	-- Fire Damage
	["Fire"]             = "Fire Damage",
	["Destruction Fire"] = "Fire Damage",
	["Spellhancer"]      = "Fire Damage",
	-- Nature Damage
	["Elemental"]        = "Nature Damage",
	-- Frost Damage
	["Frost"]            = "Frost Damage",
	-- Arcane Damage
	["Arcane"]           = "Arcane Damage",
	["Balance"]          = "Arcane Damage",
	-- Shadow Damage
	["Shadow"]           = "Shadow Damage",
	["Demonology"]       = "Shadow Damage",
	["SM/Ruin"]          = "Shadow Damage",
	["Affliction"]       = "Shadow Damage",
	-- Holy Damage
	["Discipline Smite"] = "Holy Damage",
	["Shockadin"]        = "Holy Damage",
	-- Close-up Melee: Arms, Fury, Fury Sweeping Strikes, Feral Cat,
	--   Assassination, Combat, Subtlety, Survival — via fallback
}

-- Maps sub-role → broad role (Tank/Healer/Melee/Caster) — for filter and badge letter
ART_ROLE_BROAD = {
	Tank                = "Tank",
	Healer              = "Healer",
	["Ranged Melee"]    = "Melee",
	["Hybrid Melee"]    = "Melee",
	["Close-up Melee"]  = "Melee",
	["Fire Damage"]     = "Caster",
	["Frost Damage"]    = "Caster",
	["Arcane Damage"]   = "Caster",
	["Nature Damage"]   = "Caster",
	["Shadow Damage"]   = "Caster",
	["Holy Damage"]     = "Caster",
}

ART_ROLE_COLORS = {
	-- Broad colors (used by filter dropdown)
	Tank               = { r = 0.41, g = 0.80, b = 0.94 },
	Healer             = { r = 0.49, g = 0.85, b = 0.49 },
	Melee              = { r = 0.95, g = 0.75, b = 0.30 },
	Caster             = { r = 0.80, g = 0.60, b = 0.95 },
	-- Melee sub-roles
	["Ranged Melee"]   = { r = 0.95, g = 0.60, b = 0.15 },
	["Hybrid Melee"]   = { r = 0.95, g = 0.75, b = 0.30 },
	["Close-up Melee"] = { r = 0.90, g = 0.40, b = 0.20 },
	-- Caster sub-roles
	["Fire Damage"]    = { r = 0.95, g = 0.38, b = 0.10 },
	["Frost Damage"]   = { r = 0.35, g = 0.78, b = 1.00 },
	["Arcane Damage"]  = { r = 0.75, g = 0.45, b = 0.95 },
	["Nature Damage"]  = { r = 0.30, g = 0.85, b = 0.30 },
	["Shadow Damage"]  = { r = 0.60, g = 0.20, b = 0.80 },
	["Holy Damage"]    = { r = 0.95, g = 0.85, b = 0.15 },
}

-- Returns broad role (Tank/Healer/Melee/Caster) — used by all existing displays
function ART_GetSpecRole(spec)
	if not spec or spec == "not specified" then return nil end
	local sub = ART_SPEC_ROLE[spec] or "Close-up Melee"
	return ART_ROLE_BROAD[sub] or "Melee"
end

-- Returns detailed sub-role (e.g. "Fire Damage", "Ranged Melee") — stored for future use
function ART_GetSpecSubRole(spec)
	if not spec or spec == "not specified" then return nil end
	return ART_SPEC_ROLE[spec] or "Close-up Melee"
end

function AmptieRaidTools_InitHome(body)
	local frame = CreateFrame("Frame", "AmptieRaidToolsHomePanel", body)
	frame:SetAllPoints(body)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
	title:SetText("Overview")
	title:SetTextColor(1, 0.82, 0, 1)

	local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	desc:SetJustifyH("LEFT")
	desc:SetJustifyV("TOP")
	desc:SetWidth(300)
	desc:SetNonSpaceWrap(true)
	desc:SetText("Welcome to amptieRaidTools.\n\nUse the left navigation to switch between sections. More components will follow.")

	-- Anzeige Spielerklasse (aus playerinfo, bei jedem Anzeigen aktualisiert)
	local classLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	classLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
	classLabel:SetJustifyH("LEFT")
	frame.classLabel = classLabel

	-- Skillung/Spec unter der Klasse (direkte GetTalentInfo-Abfrage in home.lua funktioniert zuverlässig)
	local specLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	specLabel:SetPoint("TOPLEFT", classLabel, "BOTTOMLEFT", 0, -4)
	specLabel:SetJustifyH("LEFT")
	frame.specLabel = specLabel

	local roleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	roleLabel:SetPoint("TOPLEFT", specLabel, "BOTTOMLEFT", 0, -4)
	roleLabel:SetJustifyH("LEFT")
	frame.roleLabel = roleLabel

	local function GetTalentRankHere(tree, talent)
		if not GetTalentInfo then return 0 end
		local _, _, _, _, x = GetTalentInfo(tree, talent)
		local n = tonumber(x)
		return (n and n >= 0) and n or 0
	end

	local function GetPaladinSpecHere()
		local r1_14 = GetTalentRankHere(1, 14)
		local r1_17 = GetTalentRankHere(1, 17)
		local r2_13 = GetTalentRankHere(2, 13)
		local r3_13 = GetTalentRankHere(3, 13)
		local r3_16 = GetTalentRankHere(3, 16)
		if r1_14 == 1 and r3_13 >= 4 then return "Shockadin" end
		if r3_16 == 1 then return "Retribution" end
		if r2_13 == 1 then return "Protection" end
		if r1_17 == 1 then return "Holy" end
		return "not specified"
	end

	local function GetRogueSpecHere()
		if GetTalentRankHere(1, 16) == 2 then return "Assassination" end
		if GetTalentRankHere(2, 16) == 2 then return "Combat" end
		if GetTalentRankHere(3, 17) == 2 then return "Subtlety" end
		return "not specified"
	end

	local function GetPriestSpecHere()
		if GetTalentRankHere(1, 17) == 5 then return "Discipline Smite" end
		if GetTalentRankHere(2, 17) == 1 then return "Holy" end
		if GetTalentRankHere(3, 17) == 1 then return "Shadow" end
		if GetTalentRankHere(1, 15) == 1 and GetTalentRankHere(2, 10) == 2 then return "Discipline Holy" end
		return "not specified"
	end

	local function GetHunterSpecHere()
		if GetTalentRankHere(1, 14) == 1 then return "Beastmaster" end
		if GetTalentRankHere(2, 15) == 5 then return "Marksman" end
		if GetTalentRankHere(3, 20) == 1 then return "Survival" end
		return "not specified"
	end

	local function GetShamanSpecHere()
		if GetTalentRankHere(3, 15) == 5 then return "Restoration" end
		if GetTalentRankHere(1, 17) == 1 then return "Elemental" end
		if GetTalentRankHere(2, 13) == 3 and GetTalentRankHere(1, 15) == 2 then return "Spellhancer" end
		if GetTalentRankHere(2, 15) == 5 then
			if GetTalentRankHere(2, 11) == 2 then return "Enhancement Tank" end
			if GetTalentRankHere(2, 11) == 0 then return "Enhancement" end
		end
		return "not specified"
	end

	local function GetDruidSpecHere()
		if GetTalentRankHere(1, 20) == 1 then return "Balance" end
		if GetTalentRankHere(3, 16) == 1 then return "Restoration" end
		if GetTalentRankHere(2, 18) == 1 then
			if GetTalentRankHere(2, 5) == 3 then return "Feral Bear" end
			if GetTalentRankHere(2, 5) == 0 then return "Feral Cat" end
		end
		return "not specified"
	end

	local function GetMageSpecHere()
		if GetTalentRankHere(1, 19) == 1 then return "Arcane" end
		if GetTalentRankHere(2, 17) == 1 then return "Fire" end
		if GetTalentRankHere(3, 19) == 1 then return "Frost" end
		return "not specified"
	end

	local function GetWarlockSpecHere()
		if GetTalentRankHere(1, 17) == 5 and GetTalentRankHere(3, 14) == 1 then return "SM/Ruin" end
		if GetTalentRankHere(1, 18) == 1 then return "Affliction" end
		if GetTalentRankHere(2, 16) == 5 then return "Demonology" end
		if GetTalentRankHere(3, 16) == 1 then return "Destruction Fire" end
		return "not specified"
	end

	local function GetWarriorSpecHere()
		local r3_12 = GetTalentRankHere(3, 12)
		local r2_17 = GetTalentRankHere(2, 17)
		local r3_19 = GetTalentRankHere(3, 19)
		local r1_11 = GetTalentRankHere(1, 11)
		local r1_10 = GetTalentRankHere(1, 10)
		local r2_15 = GetTalentRankHere(2, 15)
		local r1_13 = GetTalentRankHere(1, 13)
		local r1_18 = GetTalentRankHere(1, 18)
		if r3_12 == 5 and r2_17 == 1 then return "Fury Protection" end
		if r3_19 == 1 then return "Deep Protection" end
		if r2_17 == 1 and r1_10 == 3 then return "Fury Two-Handed" end
		if r2_17 == 1 and r1_11 == 2 then return "Fury" end
		if r2_15 == 5 and r1_13 == 1 then return "Fury Sweeping Strikes" end
		if r1_18 == 1 then return "Arms" end
		if r3_12 == 5 then return "Protection" end
		return "not specified"
	end

	local function RefreshClassDisplay()
		local info = AmptieRaidTools_PlayerInfo
		local classname = (info and info.class) and info.class or nil
		local classUpper = nil
		if not classname or classname == "" then
			local _, c = UnitClass("player")
			if c and c ~= "" then
				classname = c
				classUpper = string.upper(c)
				if info then info.class = c end
			end
		else
			classUpper = string.upper(classname)
		end
		if classname and classname ~= "" then
			local first = string.upper(string.sub(classname, 1, 1))
			local rest = string.lower(string.sub(classname, 2))
			classname = first .. rest
		else
			classname = "—"
		end
		frame.classLabel:SetText("Class: " .. classname)
		local cc = classUpper and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classUpper]
		if cc then
			frame.classLabel:SetTextColor(cc.r, cc.g, cc.b, 1)
		else
			frame.classLabel:SetTextColor(0.85, 0.85, 0.85, 1)
		end
	end

	-- Spec setzen und nur bei neu erkanntem Spec einmal Chat-Nachricht ausgeben
	local function SetSpecAndAnnounceIfNew(spec)
		if not spec or spec == "" then spec = "not specified" end
		if AmptieRaidTools_PlayerInfo then
			AmptieRaidTools_PlayerInfo.spec = spec
			AmptieRaidTools_PlayerInfo.role = ART_GetSpecRole(spec)
		end
		if spec ~= "not specified" and spec ~= AmptieRaidTools_LastAnnouncedSpec then
			DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[aRT]|r Activated Spec: " .. spec)
		end
		AmptieRaidTools_LastAnnouncedSpec = spec
	end

	local function RefreshSpecDisplay()
		local spec = nil
		local _, classname = UnitClass("player")
		local classUpper = classname and string.upper(tostring(classname)) or ""
		if classUpper == "WARRIOR" then
			spec = GetWarriorSpecHere()
		elseif classUpper == "PALADIN" then
			spec = GetPaladinSpecHere()
		elseif classUpper == "MAGE" then
			spec = GetMageSpecHere()
		elseif classUpper == "DRUID" then
			spec = GetDruidSpecHere()
		elseif classUpper == "ROGUE" then
			spec = GetRogueSpecHere()
		elseif classUpper == "SHAMAN" then
			spec = GetShamanSpecHere()
		elseif classUpper == "HUNTER" then
			spec = GetHunterSpecHere()
		elseif classUpper == "PRIEST" then
			spec = GetPriestSpecHere()
		elseif classUpper == "WARLOCK" then
			spec = GetWarlockSpecHere()
		end
		if not spec or spec == "" then spec = "not specified" end
		SetSpecAndAnnounceIfNew(spec)
		frame.specLabel:SetText("Spec: " .. spec)
		local role = ART_GetSpecRole(spec)
		if role then
			frame.roleLabel:SetText("Role: " .. role)
			frame.roleLabel:SetTextColor(0.85, 0.85, 0.85, 1)
		else
			frame.roleLabel:SetText("Role: —")
			frame.roleLabel:SetTextColor(0.55, 0.55, 0.55, 1)
		end
	end

	-- Global: Spec im Hintergrund aktualisieren (wird von main.lua periodisch aufgerufen)
	function AmptieRaidTools_RefreshSpecInBackground()
		local _, classname = UnitClass("player")
		local classUpper = classname and string.upper(tostring(classname)) or ""
		local spec = nil
		if classUpper == "WARRIOR" then
			spec = GetWarriorSpecHere()
		elseif classUpper == "PALADIN" then
			spec = GetPaladinSpecHere()
		elseif classUpper == "MAGE" then
			spec = GetMageSpecHere()
		elseif classUpper == "DRUID" then
			spec = GetDruidSpecHere()
		elseif classUpper == "ROGUE" then
			spec = GetRogueSpecHere()
		elseif classUpper == "SHAMAN" then
			spec = GetShamanSpecHere()
		elseif classUpper == "HUNTER" then
			spec = GetHunterSpecHere()
		elseif classUpper == "PRIEST" then
			spec = GetPriestSpecHere()
		elseif classUpper == "WARLOCK" then
			spec = GetWarlockSpecHere()
		end
		if not spec then spec = "not specified" end
		SetSpecAndAnnounceIfNew(spec)
		if ART_AB_OnSpecChanged  then ART_AB_OnSpecChanged(spec)  end
		if ART_BP_OnSpecChanged  then ART_BP_OnSpecChanged(spec)  end
		if ART_RL_OnOwnSpecChanged then ART_RL_OnOwnSpecChanged(spec) end
	end

	local function RefreshAll()
		RefreshClassDisplay()
		RefreshSpecDisplay()
	end

	-- ── Separator ────────────────────────────────────────────
	local homeSep1 = frame:CreateTexture(nil, "ARTWORK")
	homeSep1:SetHeight(1)
	homeSep1:SetTexture(0.35, 0.35, 0.4, 0.5)
	homeSep1:SetPoint("TOPLEFT",  frame.roleLabel, "BOTTOMLEFT", 0, -10)
	homeSep1:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, 0)

	-- ── Salvation Override ──────────────────────────────────
	local salvHdr = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	salvHdr:SetPoint("TOPLEFT", homeSep1, "BOTTOMLEFT", 0, -10)
	salvHdr:SetText("Salvation Override")
	salvHdr:SetTextColor(1, 0.82, 0, 1)

	local salvDesc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	salvDesc:SetPoint("TOPLEFT", salvHdr, "BOTTOMLEFT", 0, -6)
	salvDesc:SetWidth(420)
	salvDesc:SetJustifyH("LEFT")
	salvDesc:SetText("Override the Auto-Buffs profile for Blessing of Salvation and Greater Blessing of Salvation, independent of the active profile.")

	local SALV_BD = {
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	}

	local salvBtns  = {}
	local salvOpts  = {
		{ key = "profile", label = "as in Profile" },
		{ key = "allow",   label = "Allow"          },
		{ key = "remove",  label = "Remove"         },
	}

	local function RefreshSalvButtons()
		local cur = ART_SalvationOverride or "profile"
		for i = 1, getn(salvBtns) do
			local btn = salvBtns[i]
			if btn.salvKey == cur then
				btn:SetBackdropColor(0.22, 0.17, 0.03, 0.95)
				btn:SetBackdropBorderColor(1, 0.82, 0, 1)
				btn.fs:SetTextColor(1, 0.82, 0, 1)
			else
				btn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
				btn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
				btn.fs:SetTextColor(0.85, 0.85, 0.85, 1)
			end
		end
	end

	local prevSalvBtn = nil
	for i = 1, getn(salvOpts) do
		local opt = salvOpts[i]
		local btn = CreateFrame("Button", nil, frame)
		btn:SetWidth(110)
		btn:SetHeight(22)
		btn:SetBackdrop(SALV_BD)
		btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
		fs:SetJustifyH("CENTER")
		fs:SetText(opt.label)
		btn.fs = fs
		btn.salvKey = opt.key
		if prevSalvBtn then
			btn:SetPoint("LEFT", prevSalvBtn, "RIGHT", 4, 0)
		else
			btn:SetPoint("TOPLEFT", salvDesc, "BOTTOMLEFT", 0, -10)
		end
		btn:SetScript("OnClick", function()
			ART_SalvationOverride = this.salvKey
			RefreshSalvButtons()
		end)
		tinsert(salvBtns, btn)
		prevSalvBtn = btn
	end

	RefreshSalvButtons()

	-- ── Separator before Alternative Specs ──────────────────
	local homeSep2 = frame:CreateTexture(nil, "ARTWORK")
	homeSep2:SetHeight(1)
	homeSep2:SetTexture(0.35, 0.35, 0.4, 0.5)
	homeSep2:SetPoint("TOPLEFT",  salvBtns[1], "BOTTOMLEFT", 0, -14)
	homeSep2:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, 0)

	-- ── Alternative Specs (left-aligned with Salvation Override) ─
	local altHdr = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	altHdr:SetPoint("TOPLEFT", homeSep2, "BOTTOMLEFT", 0, -10)
	altHdr:SetText("Alternative Specs")
	altHdr:SetTextColor(1, 0.82, 0, 1)

	local altDesc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	altDesc:SetPoint("TOPLEFT", altHdr, "BOTTOMLEFT", 0, -4)
	altDesc:SetWidth(420)
	altDesc:SetJustifyH("LEFT")
	altDesc:SetText("Select roles you could fill as an alternative, and your gear level for each.")
	altDesc:SetTextColor(0.75, 0.75, 0.75, 1)

	-- Which roles each class may offer as alternatives
	local CLASS_ALT_ROLES = {
		WARRIOR = { "Tank", "PhysDPS" },
		PALADIN = { "Tank", "Healer", "PhysDPS" },
		DRUID   = { "Tank", "Healer", "Caster", "PhysDPS" },
		SHAMAN  = { "Tank", "Healer", "Caster", "PhysDPS" },
		PRIEST  = { "Healer", "Caster" },
		MAGE    = { "Caster" },
		WARLOCK = { "Caster" },
		ROGUE   = { "PhysDPS" },
		HUNTER  = { "PhysDPS" },
	}

	local ALT_ROLE_ICON = {
		Tank    = "Interface\\Icons\\INV_Shield_04",
		PhysDPS = "Interface\\Icons\\INV_Sword_20",
		Caster  = "Interface\\Icons\\Spell_Frost_FrostBolt02",
		Healer  = "Interface\\Icons\\Spell_Holy_HolyBolt",
	}
	local ALT_ROLE_LABEL = {
		Tank    = "Tank",
		PhysDPS = "Physical DPS",
		Caster  = "Caster",
		Healer  = "Healer",
	}
	local GEAR_TIERS = { "Dungeon", "MC", "BWL", "AQ40", "Naxx", "K40" }

	local ALT_BD = {
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile=true, tileSize=16, edgeSize=10,
		insets={left=3,right=3,top=3,bottom=3},
	}

	-- DB init
	local DB = amptieRaidToolsDB
	if DB and not DB.altSpecs then DB.altSpecs = {} end

	local altRoleWidgets = {}   -- key=roleKey, value={checkBtn, tierRow, tierLabel, tierDD}

	local function BroadcastAltSpecs()
		if ART_RL_OnAltSpecsChanged then
			local db = amptieRaidToolsDB
			ART_RL_OnAltSpecsChanged(db and db.altSpecs or {})
		end
	end

	local function BuildTierDropdown(parent, roleKey, anchorFrame)
		local dd = CreateFrame("Frame", nil, parent)
		dd:SetFrameStrata("TOOLTIP")
		dd:SetWidth(100)
		dd:SetHeight(getn(GEAR_TIERS) * 22 + 6)
		dd:SetBackdrop({
			bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
			tile=true, tileSize=16, edgeSize=10,
			insets={left=3,right=3,top=3,bottom=3},
		})
		dd:SetBackdropColor(0.08, 0.08, 0.11, 0.97)
		dd:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
		dd:Hide()

		for i = 1, getn(GEAR_TIERS) do
			local tier = GEAR_TIERS[i]
			local item = CreateFrame("Button", nil, dd)
			item:SetHeight(22)
			item:SetPoint("TOPLEFT",  dd, "TOPLEFT",  4, -3 - (i-1)*22)
			item:SetPoint("TOPRIGHT", dd, "TOPRIGHT", -4, -3 - (i-1)*22)
			item:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", tile=true, tileSize=16, edgeSize=0, insets={left=0,right=0,top=0,bottom=0} })
			item:SetBackdropColor(0, 0, 0, 0)
			local lbl = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			lbl:SetPoint("LEFT", item, "LEFT", 6, 0)
			lbl:SetText(tier)
			lbl:SetTextColor(0.85, 0.85, 0.85, 1)
			item:SetScript("OnEnter", function() this:SetBackdropColor(0.22, 0.22, 0.28, 0.9) end)
			item:SetScript("OnLeave", function() this:SetBackdropColor(0, 0, 0, 0) end)
			item:SetScript("OnClick", function()
				local db = amptieRaidToolsDB
				if db and db.altSpecs then db.altSpecs[roleKey] = tier end
				dd:Hide()
				local w = altRoleWidgets[roleKey]
				if w then w.tierLabel:SetText(tier .. " v") end
				BroadcastAltSpecs()
			end)
		end
		return dd
	end

	-- Build icons horizontally for the player's class
	local function BuildAltSpecsForClass()
		local _, classname = UnitClass("player")
		local classUpper2 = classname and string.upper(tostring(classname)) or ""
		local roles = CLASS_ALT_ROLES[classUpper2]
		if not roles then return end

		-- Single-role classes cannot fill an alternative role — show info text only
		if getn(roles) == 1 then
			local infoTxt = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			infoTxt:SetPoint("TOPLEFT", altDesc, "BOTTOMLEFT", 0, -12)
			infoTxt:SetText("This class cannot fill an alternative role.")
			infoTxt:SetTextColor(0.55, 0.55, 0.55, 1)
			return
		end

		local ICON_SIZE = 35
		local ICON_GAP  = 75   -- 110px step — dropdowns (100px wide) won't overlap

		for i = 1, getn(roles) do
			local rk = roles[i]
			local db2 = amptieRaidToolsDB
			local isChecked = db2 and db2.altSpecs and db2.altSpecs[rk] ~= nil
			local savedTier = (db2 and db2.altSpecs and db2.altSpecs[rk]) or "MC"
			local xOff = (i - 1) * (ICON_SIZE + ICON_GAP)

			-- Icon toggle button (35x35), horizontal
			local iconBtn = CreateFrame("Button", nil, frame)
			iconBtn:SetWidth(ICON_SIZE)
			iconBtn:SetHeight(ICON_SIZE)
			iconBtn:SetPoint("TOPLEFT", altDesc, "BOTTOMLEFT", xOff, -12)
			iconBtn:SetBackdrop(ALT_BD)
			iconBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
			iconBtn:SetBackdropBorderColor(isChecked and 1 or 0.35, isChecked and 0.82 or 0.35, isChecked and 0 or 0.4, 1)
			iconBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

			local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
			iconTex:SetAllPoints(iconBtn)
			iconTex:SetTexture(ALT_ROLE_ICON[rk])
			iconTex:SetVertexColor(isChecked and 1 or 0.4, isChecked and 1 or 0.4, isChecked and 1 or 0.4, 1)
			iconBtn.iconTex = iconTex

			-- Label centered below icon
			local roleLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			roleLbl:SetPoint("TOP", iconBtn, "BOTTOM", 0, -3)
			roleLbl:SetWidth(ICON_SIZE + 20)
			roleLbl:SetJustifyH("CENTER")
			roleLbl:SetText(ALT_ROLE_LABEL[rk])
			roleLbl:SetTextColor(isChecked and 0.85 or 0.45, isChecked and 0.85 or 0.45, isChecked and 0.85 or 0.45, 1)

			-- Tier button centered below label (only when checked)
			local tierBtn = CreateFrame("Button", nil, frame)
			tierBtn:SetWidth(ICON_SIZE + 20)
			tierBtn:SetHeight(20)
			tierBtn:SetPoint("TOP", roleLbl, "BOTTOM", 0, -3)
			tierBtn:SetBackdrop(ALT_BD)
			tierBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
			tierBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
			tierBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			local tierLabel = tierBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			tierLabel:SetPoint("CENTER", tierBtn, "CENTER", 0, 0)
			tierLabel:SetJustifyH("CENTER")
			tierLabel:SetText(savedTier .. " v")
			tierLabel:SetTextColor(1, 0.82, 0, 1)
			if not isChecked then tierBtn:Hide() end

			-- Tier dropdown (below the tier button, aligned to its left edge)
			local tierDD = BuildTierDropdown(frame, rk, tierBtn)

			tierBtn:SetScript("OnClick", function()
				if tierDD:IsShown() then
					tierDD:Hide()
				else
					tierDD:ClearAllPoints()
					tierDD:SetPoint("TOP", this, "BOTTOM", 0, -2)
					tierDD:Show()
				end
			end)

			local rowRk      = rk
			local rowRoleLbl = roleLbl
			local rowTierBtn = tierBtn
			local rowTierDD  = tierDD
			local rowTierLbl = tierLabel
			iconBtn:SetScript("OnClick", function()
				local db3 = amptieRaidToolsDB
				if not db3 or not db3.altSpecs then return end
				if db3.altSpecs[rowRk] then
					db3.altSpecs[rowRk] = nil
					this:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
					this.iconTex:SetVertexColor(0.4, 0.4, 0.4, 1)
					rowRoleLbl:SetTextColor(0.45, 0.45, 0.45, 1)
					rowTierBtn:Hide()
					rowTierDD:Hide()
				else
					db3.altSpecs[rowRk] = "MC"
					this:SetBackdropBorderColor(1, 0.82, 0, 1)
					this.iconTex:SetVertexColor(1, 1, 1, 1)
					rowRoleLbl:SetTextColor(0.85, 0.85, 0.85, 1)
					rowTierLbl:SetText("MC v")
					rowTierBtn:Show()
				end
				BroadcastAltSpecs()
			end)

			altRoleWidgets[rk] = { iconBtn=iconBtn, tierBtn=tierBtn, tierLabel=tierLabel, tierDD=tierDD }
		end
	end

	BuildAltSpecsForClass()

	frame:SetScript("OnShow", function()
		RefreshAll()
		RefreshSalvButtons()
		-- re-sync DB reference
		local db = amptieRaidToolsDB
		if db and not db.altSpecs then db.altSpecs = {} end
	end)
	RefreshAll()

	frame.contentHeight = 380
	AmptieRaidTools_RegisterComponent("home", frame)
end
