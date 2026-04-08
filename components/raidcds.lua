-- amptieRaidTools – Component: Raid Cooldown Tracker (raidcds.lua)
-- Detection: SPELL_UPDATE_COOLDOWN (own) + CHAT_MSG_ADDON (others).
-- Display: one row per group member with tracked spells; icon buttons per spell.
-- Vanilla WoW 1.12 / Lua 5.0 / TurtleWoW

local GetTime  = GetTime
local floor    = math.floor
local getn     = table.getn
local tinsert  = table.insert
local sfind    = string.find
local pairs    = pairs

local ADDON_PREFIX = "ART_CD"

-- ── Layout constants ──────────────────────────────────────────
local MAX_ROWS          = 12
local MAX_ICONS         = 4
local ICON_GAP          = 3
local NAME_W            = 75
local HDR_H             = 20
local LEFT_PAD          = 6
local NAME_ICON_GAP     = 2
local RIGHT_PAD         = 8
-- Base values — scaled at runtime via ApplyScale()
local ICON_SZ_BASE      = 22
local ROW_H_BASE        = 28
local TIMER_FONT_BASE   = 13
local ICON_SZ           = ICON_SZ_BASE
local ROW_H             = ROW_H_BASE
-- Minimum width (1 icon slot); grows dynamically in RefreshDisplay
local OVERLAY_MIN_W  = LEFT_PAD + NAME_W + NAME_ICON_GAP + ICON_SZ_BASE + RIGHT_PAD

-- ── Spell table ───────────────────────────────────────────────
local ART_CD_SPELL_TABLE = {
	{ name = "Rebirth",             dur = 1800, class = "DRUID",   icon = "Interface\\Icons\\Spell_Nature_Reincarnation"    },
	{ name = "Innervate",           dur = 360,  class = "DRUID",   icon = "Interface\\Icons\\Spell_Nature_Lightning"        },
	{ name = "Tranquility",         dur = 1800, class = "DRUID",   icon = "Interface\\Icons\\Spell_Nature_Tranquility"      },
	{ name = "Challenging Roar",    dur = 600,  class = "DRUID",   icon = "Interface\\Icons\\Ability_Druid_ChallangingRoar" },
	{ name = "Hand of Protection",  dur = 300,  class = "PALADIN", icon = "Interface\\Icons\\Spell_Holy_SealOfProtection" },
	{ name = "Divine Intervention", dur = 3600, class = "PALADIN", icon = "Interface\\Icons\\Spell_Nature_TimeStop"       },
	{ name = "Shield Wall",         dur = 1800, class = "WARRIOR", icon = "Interface\\Icons\\Ability_Warrior_ShieldWall"  },
	{ name = "Challenging Shout",   dur = 600,  class = "WARRIOR", icon = "Interface\\Icons\\Ability_BullRush"            },
	{ name = "Reincarnation",       dur = 3600, class = "SHAMAN",  icon = "Interface\\Icons\\Spell_Nature_Reincarnation"  },
}

-- ── Status effect table (buff/debuff present on ANY raid member) ─
-- deadOnly = true → row only shown when the player is dead (like Reincarnation)
local ART_STATUS_TABLE = {
	{ name = "Soulstone Resurrection", type = "buff",   dur = 1800, deadOnly = true,  icon = "Interface\\Icons\\Spell_Shadow_SoulGem"  },
	{ name = "Scrambled Brain",        type = "debuff", dur = 600,  deadOnly = false, icon = "Interface\\Icons\\Spell_Shadow_MindRot"   },
}
local MAX_STATUS_ICONS = 2  -- must equal getn(ART_STATUS_TABLE)

-- Hidden tooltip for buff/debuff name lookup (SetUnitBuff / SetUnitDebuff)
local ART_ScanTip = CreateFrame("GameTooltip", "ART_CD_ScanTip", nil, "GameTooltipTemplate")
ART_ScanTip:SetOwner(UIParent, "ANCHOR_NONE")
local scanTipLeft1  -- resolved lazily after UI load

local function UnitHasEffect(unit, effectName, effectType)
	if not scanTipLeft1 then
		scanTipLeft1 = getglobal("ART_CD_ScanTipTextLeft1")
	end
	if effectType == "buff" then
		for i = 1, 64 do
			ART_ScanTip:ClearLines()
			ART_ScanTip:SetOwner(UIParent, "ANCHOR_NONE")
			ART_ScanTip:SetUnitBuff(unit, i)
			local text = scanTipLeft1:GetText()
			if not text or text == "" then break end
			if text == effectName then ART_ScanTip:Hide(); return true end
		end
	else
		for i = 1, 64 do
			ART_ScanTip:ClearLines()
			ART_ScanTip:SetOwner(UIParent, "ANCHOR_NONE")
			ART_ScanTip:SetUnitDebuff(unit, i)
			local text = scanTipLeft1:GetText()
			if not text or text == "" then break end
			if text == effectName then ART_ScanTip:Hide(); return true end
		end
	end
	ART_ScanTip:Hide()
	return false
end

-- Class display order (tab UI and overlay)
local CLASS_ORDER = { "DRUID", "PALADIN", "WARRIOR", "SHAMAN" }
local CLASS_LABEL = { DRUID = "Druid", PALADIN = "Paladin", WARRIOR = "Warrior", SHAMAN = "Shaman" }

-- Enabled spells only — rebuilt from DB settings on login and checkbox change
local SPELLS_BY_CLASS = {}
local function RebuildSpellsByClass()
	for k in pairs(SPELLS_BY_CLASS) do SPELLS_BY_CLASS[k] = nil end
	local enDB = amptieRaidToolsDB and amptieRaidToolsDB.raidCDsEnabled or {}
	for i = 1, getn(ART_CD_SPELL_TABLE) do
		local e = ART_CD_SPELL_TABLE[i]
		if enDB[e.name] ~= false then
			if not SPELLS_BY_CLASS[e.class] then SPELLS_BY_CLASS[e.class] = {} end
			tinsert(SPELLS_BY_CLASS[e.class], e)
		end
	end
end

-- ── Class colours ─────────────────────────────────────────────
local CLASS_COLORS = {
	WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
	PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
	HUNTER  = { r = 0.67, g = 0.83, b = 0.45 },
	ROGUE   = { r = 1.00, g = 0.96, b = 0.41 },
	PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
	SHAMAN  = { r = 0.00, g = 0.44, b = 0.87 },
	MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
	WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
	DRUID   = { r = 1.00, g = 0.49, b = 0.04 },
}

-- ── Runtime state ─────────────────────────────────────────────
-- key = playerName .. "\31" .. spellName
local activeCooldowns = {}

-- key = playerName .. "\31" .. effectName  → { player, effect, start, dur }
local activeStatusEffects = {}
-- own current aura state — for change detection on PLAYER_AURAS_CHANGED
local ownStatusEffects = {}  -- effectName → true/false

-- Persist a cooldown entry using Unix time so it survives reloads
local function PersistCD(key, player, spell, dur)
	if ART_RaidCDs then
		ART_RaidCDs[key] = { player=player, spell=spell, expiresAt=time()+dur, dur=dur }
	end
end

local function UnpersistCD(key)
	if ART_RaidCDs then ART_RaidCDs[key] = nil end
end

-- ownSlots[i] = { name, dur, slot, wasOnCD }  ownSlots.n = count
local ownSlots = {}
ownSlots.n = 0

-- playerClasses[name] = "WARRIOR" / "PALADIN" / …
local playerClasses = {}
-- playerUnits[name] = unit string ("player", "raid1", "party2" …)
local playerUnits = {}

local STATUS_PREFIX = "ART_ST"

local ownName               = nil
local overlayFrame          = nil
local RefreshDisplay        = nil  -- forward declaration
local RefreshTaunterListUI  = nil  -- forward declaration

-- ── Taunt Tracker state ───────────────────────────────────────
local TAUNT_PREFIX = "ART_TN"
local TAUNT_CLASS_SPELL = {
	WARRIOR = { name = "Taunt",             dur = 10, icon = "Interface\\Icons\\Spell_Nature_Reincarnation" },
	PALADIN = { name = "Hand of Reckoning", dur = 10, icon = "Interface\\Icons\\Spell_Holy_Redemption"      },
	SHAMAN  = { name = "Earthshaker Slam",  dur = 10, icon = "Interface\\Icons\\earthshaker_slam_11"        },
	DRUID   = { name = "Growl",             dur = 10, icon = "Interface\\Icons\\Ability_Physical_Taunt"     },
}
local activeTauntCDs  = {}
local ownTauntSlot    = nil
local ownTauntDur     = 8
local ownTauntLastStart = 0   -- CD start timestamp from GetSpellCooldown
local tauntOverlay    = nil
local RefreshTauntDisplay = nil

-- ── Scale ─────────────────────────────────────────────────────
local function ApplyScale()
	local pct = (amptieRaidToolsDB and amptieRaidToolsDB.raidCDsIconScale) or 100
	ICON_SZ = floor(ICON_SZ_BASE * pct / 100 + 0.5)
	ROW_H   = floor(ROW_H_BASE   * pct / 100 + 0.5)
	local fontSize = floor(TIMER_FONT_BASE * pct / 100 + 0.5)
	if fontSize < 6 then fontSize = 6 end
	local iconYOff = -floor((ROW_H - ICON_SZ) / 2)
	local function scaleRows(f, nIcons)
		if not f then return end
		for i = 1, MAX_ROWS do
			local row = f.rows[i]
			row:SetHeight(ROW_H)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT_PAD, -(HDR_H + (i - 1) * ROW_H + 4))
			for j = 1, nIcons do
				local btn = row.icons[j]
				if btn then
					btn:SetWidth(ICON_SZ)
					btn:SetHeight(ICON_SZ)
					btn:ClearAllPoints()
					btn:SetPoint("TOPLEFT", row, "TOPLEFT",
					             NAME_W + NAME_ICON_GAP + (j - 1) * (ICON_SZ + ICON_GAP),
					             iconYOff)
					btn.timerFS:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "THICKOUTLINE")
				end
			end
		end
	end
	scaleRows(overlayFrame, MAX_ICONS)
	scaleRows(tauntOverlay, 1)
	if RefreshDisplay then RefreshDisplay() end
	if RefreshTauntDisplay then RefreshTauntDisplay() end
end

-- ── Group check + overlay visibility ──────────────────────────
local function IsInGroup()
	return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
end

local function HasTrackedPlayersInGroup()
	for name, class in pairs(playerClasses) do
		if SPELLS_BY_CLASS[class] then return true end
	end
	return false
end

local function UpdateOverlayVisibility()
	local inGroup = IsInGroup()
	local inRaid  = GetNumRaidMembers() > 0
	local DB = amptieRaidToolsDB
	if overlayFrame then
		if inGroup and DB and DB.raidCDsShown then
			overlayFrame:Show()
			if RefreshDisplay then RefreshDisplay() end
		else
			overlayFrame:Hide()
		end
	end
	if tauntOverlay then
		if inRaid and DB and DB.taunterShown then
			tauntOverlay:Show()
			if RefreshTauntDisplay then RefreshTauntDisplay() end
		else
			tauntOverlay:Hide()
		end
	end
end

-- ── Utility ───────────────────────────────────────────────────
-- >= 90s → "4m" ; < 90s → "47"
local function FmtTimer(secs)
	if secs <= 0 then return "" end
	if secs >= 90 then
		return floor(secs / 60) .. "m"
	else
		return tostring(floor(secs))
	end
end

local function FindSpellBookSlot(spellName)
	local i = 1
	while true do
		local n = GetSpellName(i, BOOKTYPE_SPELL)
		if not n then break end
		if n == spellName then return i end
		i = i + 1
	end
	return nil
end

-- ── Roster ────────────────────────────────────────────────────
local function RebuildRoster()
	for k in pairs(playerClasses) do playerClasses[k] = nil end
	for k in pairs(playerUnits)   do playerUnits[k]   = nil end

	local selfName  = ownName or UnitName("player")
	local _, selfCl = UnitClass("player")
	if selfName and selfCl then
		playerClasses[selfName] = string.upper(selfCl)
		playerUnits[selfName]   = "player"
	end

	local numRaid = GetNumRaidMembers()
	if numRaid > 0 then
		for i = 1, numRaid do
			local unit  = "raid" .. i
			local name  = UnitName(unit)
			local _, cl = UnitClass(unit)
			if name and cl then
				playerClasses[name] = string.upper(cl)
				playerUnits[name]   = unit
			end
		end
	else
		for i = 1, GetNumPartyMembers() do
			local unit  = "party" .. i
			local name  = UnitName(unit)
			local _, cl = UnitClass(unit)
			if name and cl then
				playerClasses[name] = string.upper(cl)
				playerUnits[name]   = unit
			end
		end
	end
end

-- ── Own-spell init ────────────────────────────────────────────
local function InitOwnSpells()
	ownName    = UnitName("player")
	ownSlots.n = 0
	for i = 1, getn(ART_CD_SPELL_TABLE) do
		local e    = ART_CD_SPELL_TABLE[i]
		local slot = FindSpellBookSlot(e.name)
		if slot then
			local idx = ownSlots.n + 1
			ownSlots[idx] = { name = e.name, dur = e.dur, slot = slot, wasOnCD = false }
			ownSlots.n = idx
		end
	end
	RebuildSpellsByClass()
	RebuildRoster()
	ApplyScale()
end

-- ── Taunt helpers ─────────────────────────────────────────────
local function GetTaunterConfig()
	local DB = amptieRaidToolsDB
	if not DB then return {} end
	if not DB.taunterConfig then DB.taunterConfig = {} end
	return DB.taunterConfig
end

local function SyncTauntersFromRoster()
	local cfg = GetTaunterConfig()
	-- Rebuild from scratch: only Tanks and Melees with tauntable class
	local keep = {}
	for i = 1, getn(cfg) do keep[cfg[i].name] = cfg[i] end
	-- Clear config
	for i = getn(cfg), 1, -1 do table.remove(cfg, i) end
	cfg.n = 0
	local specs = ART_RL_GetRosterSpecs and ART_RL_GetRosterSpecs() or {}
	for name, class in pairs(playerClasses) do
		if TAUNT_CLASS_SPELL[class] then
			local spec = specs[name]
			local role = spec and ART_GetSpecRole and ART_GetSpecRole(spec)
			-- Include if: role is Tank/Melee, OR spec not known yet (fallback)
			if role == "Tank" or role == "Melee" or not role then
				local prev = keep[name]
				tinsert(cfg, { name = name, selected = prev and prev.selected or false })
			end
		end
	end
	-- Sort: Maintanks by MT order → Tanks → Melees → alphabetical
	local mtNames = {}
	if amptieRaidToolsDB and amptieRaidToolsDB.raidAssists
	   and amptieRaidToolsDB.raidAssists.mainTanks then
		local mts = amptieRaidToolsDB.raidAssists.mainTanks
		for i = 1, 8 do
			if mts[i] and mts[i] ~= "" then mtNames[mts[i]] = i end
		end
	end
	local function sortOrd(entry)
		local mt = mtNames[entry.name]
		if mt then return mt end  -- 1-8 for maintanks
		local spec = specs[entry.name]
		local role = spec and ART_GetSpecRole and ART_GetSpecRole(spec)
		if role == "Tank"  then return 100 end
		if role == "Melee" then return 200 end
		return 300
	end
	-- Insertion sort (stable)
	for i = 2, getn(cfg) do
		local v  = cfg[i]
		local vo = sortOrd(v)
		local j  = i - 1
		while j >= 1 and sortOrd(cfg[j]) > vo do
			cfg[j+1] = cfg[j]
			j = j - 1
		end
		cfg[j+1] = v
	end
end

local function PruneTaunterConfig()
	local cfg = GetTaunterConfig()
	local i = 1
	while i <= getn(cfg) do
		if not playerUnits[cfg[i].name] then
			table.remove(cfg, i)
		else
			i = i + 1
		end
	end
end

local function InitOwnTaunt()
	local _, cls = UnitClass("player")
	if not cls then ownTauntSlot = nil; return end
	local spell = TAUNT_CLASS_SPELL[string.upper(cls)]
	if not spell then ownTauntSlot = nil; return end
	ownTauntSlot = FindSpellBookSlot(spell.name)
	ownTauntDur  = spell.dur
	-- Warrior: Improved Taunt (tree 3, talent 8) reduces CD by 1s per rank
	if string.upper(cls) == "WARRIOR" and GetTalentInfo then
		local _, _, _, _, rank = GetTalentInfo(3, 8)
		local r = tonumber(rank)
		if r and r > 0 then ownTauntDur = ownTauntDur - r end
	end
	ownTauntLastStart = 0
end

local function CheckOwnTaunt()
	if not ownTauntSlot or not ownName then return end
	local start, duration = GetSpellCooldown(ownTauntSlot, BOOKTYPE_SPELL)
	local isOnCD = (start and start > 0 and duration and duration > 1.5)
	if isOnCD and start ~= ownTauntLastStart then
		ownTauntLastStart = start
		activeTauntCDs[ownName] = { start = start, dur = ownTauntDur }
		local channel = nil
		if GetNumRaidMembers() > 0 then
			channel = "RAID"
		elseif GetNumPartyMembers() > 0 then
			channel = "PARTY"
		end
		if channel then
			SendAddonMessage(TAUNT_PREFIX, "TN^" .. ownTauntDur, channel)
		end
		if RefreshTauntDisplay then RefreshTauntDisplay() end
	end
end

-- ── Own status effect detection (PLAYER_AURAS_CHANGED) ───────
-- Scans own buffs/debuffs for ART_STATUS_TABLE entries.
-- On gain: records locally + broadcasts SS^name^dur to group.
-- On loss: removes locally + broadcasts SE^name to group.
local function CheckOwnStatusEffects()
	if not ownName then return end
	local enDB = amptieRaidToolsDB and amptieRaidToolsDB.raidStatusEnabled or {}
	for i = 1, getn(ART_STATUS_TABLE) do
		local e = ART_STATUS_TABLE[i]
		if enDB[e.name] then
			local hasIt = UnitHasEffect("player", e.name, e.type)
			local hadIt = ownStatusEffects[e.name] and true or false
			if hasIt and not hadIt then
				ownStatusEffects[e.name] = true
				local key = ownName .. "\31" .. e.name
				activeStatusEffects[key] = { player = ownName, effect = e.name, start = GetTime(), dur = e.dur }
				local channel = nil
				if GetNumRaidMembers() > 0 then
					channel = "RAID"
				elseif GetNumPartyMembers() > 0 then
					channel = "PARTY"
				end
				if channel then
					SendAddonMessage(STATUS_PREFIX, "SS^" .. e.name .. "^" .. e.dur, channel)
				end
				if RefreshDisplay then RefreshDisplay() end
			elseif not hasIt and hadIt then
				ownStatusEffects[e.name] = false
				local key = ownName .. "\31" .. e.name
				activeStatusEffects[key] = nil
				local channel = nil
				if GetNumRaidMembers() > 0 then
					channel = "RAID"
				elseif GetNumPartyMembers() > 0 then
					channel = "PARTY"
				end
				if channel then
					SendAddonMessage(STATUS_PREFIX, "SE^" .. e.name, channel)
				end
				if RefreshDisplay then RefreshDisplay() end
			end
		end
	end
end

-- ── Own cooldown detection ────────────────────────────────────
local function CheckOwnCooldowns()
	if not ownName then return end
	for i = 1, ownSlots.n do
		local s = ownSlots[i]
		local start, duration = GetSpellCooldown(s.slot, BOOKTYPE_SPELL)
		local isOnCD = (start and start > 0 and duration and duration > 1.5)
		if isOnCD and not s.wasOnCD then
			local key = ownName .. "\31" .. s.name
			activeCooldowns[key] = { player = ownName, spell = s.name, start = GetTime(), dur = s.dur }
			PersistCD(key, ownName, s.name, s.dur)
			local channel = nil
			if GetNumRaidMembers() > 0 then
				channel = "RAID"
			elseif GetNumPartyMembers() > 0 then
				channel = "PARTY"
			end
			if channel then
				SendAddonMessage(ADDON_PREFIX, "CD^" .. s.name .. "^" .. s.dur, channel)
			end
			if RefreshDisplay then RefreshDisplay() end
		end
		s.wasOnCD = isOnCD
	end
end

-- Dirty flags — set by events, consumed by cdPollFrame (always running)
local cdStatusDirty = false  -- PLAYER_AURAS_CHANGED: re-check own status effects
local cdRosterDirty = false  -- RAID_ROSTER_UPDATE: rebuild roster + refresh display

local cdPollTimer = 0
local CD_POLL_INTERVAL = 0.5
local cdPollFrame = CreateFrame("Frame", "ART_CD_PollFrame", UIParent)
cdPollFrame:SetScript("OnUpdate", function()
	local dt = arg1
	if not dt or dt <= 0 then return end
	cdPollTimer = cdPollTimer + dt
	if cdPollTimer < CD_POLL_INTERVAL then return end
	cdPollTimer = 0
	if cdStatusDirty then
		cdStatusDirty = false
		CheckOwnStatusEffects()
	end
	if cdRosterDirty then
		cdRosterDirty = false
		RebuildRoster()
		PruneTaunterConfig()
		UpdateOverlayVisibility()
		if RefreshDisplay       then RefreshDisplay()       end
		if RefreshTaunterListUI then RefreshTaunterListUI() end
	end
end)

-- ── Event frame ───────────────────────────────────────────────
local cdEvt = CreateFrame("Frame", "ART_CD_EventFrame", UIParent)
cdEvt:RegisterEvent("PLAYER_LOGIN")
cdEvt:RegisterEvent("SPELL_UPDATE_COOLDOWN")
cdEvt:RegisterEvent("CHAT_MSG_ADDON")
cdEvt:RegisterEvent("RAID_ROSTER_UPDATE")
cdEvt:RegisterEvent("PARTY_MEMBERS_CHANGED")
cdEvt:RegisterEvent("PLAYER_ENTERING_WORLD")
cdEvt:RegisterEvent("PLAYER_AURAS_CHANGED")
cdEvt:SetScript("OnEvent", function()
	local evt = event
	local a1, a2, a3, a4 = arg1, arg2, arg3, arg4

	if evt == "PLAYER_LOGIN" then
		-- Always start with overlays hidden — avoids carry-over from other characters
		local DB0 = amptieRaidToolsDB
		if DB0 then
			DB0.raidCDsShown = false
			DB0.taunterShown = false
		end
		-- Restore persisted cooldowns from previous session
		if ART_RaidCDs == nil then ART_RaidCDs = {} end
		local nowUnix = time()
		for key, v in pairs(ART_RaidCDs) do
			local remaining = v.expiresAt - nowUnix
			if remaining > 5 then
				activeCooldowns[key] = {
					player = v.player,
					spell  = v.spell,
					start  = GetTime() - (v.dur - remaining),
					dur    = v.dur,
				}
			else
				ART_RaidCDs[key] = nil
			end
		end
		InitOwnSpells()
		InitOwnTaunt()
		CheckOwnStatusEffects()
		UpdateOverlayVisibility()

	elseif evt == "PLAYER_AURAS_CHANGED" then
		cdStatusDirty = true

	elseif evt == "SPELL_UPDATE_COOLDOWN" then
		CheckOwnCooldowns()
		CheckOwnTaunt()

	elseif evt == "RAID_ROSTER_UPDATE" or evt == "PARTY_MEMBERS_CHANGED" then
		cdRosterDirty = true

	elseif evt == "PLAYER_ENTERING_WORLD" then
		RebuildRoster()
		PruneTaunterConfig()
		UpdateOverlayVisibility()
		if RefreshDisplay       then RefreshDisplay()       end
		if RefreshTaunterListUI then RefreshTaunterListUI() end

	elseif evt == "CHAT_MSG_ADDON" then
		if a1 == ADDON_PREFIX then
			local _, _, sName, sDur = sfind(a2, "^CD%^([^^]+)%^(%d+)$")
			if sName and sDur and a4 and a4 ~= ownName then
				local key  = a4 .. "\31" .. sName
				local sDurN = tonumber(sDur)
				activeCooldowns[key] = {
					player = a4, spell = sName, start = GetTime(), dur = sDurN,
				}
				PersistCD(key, a4, sName, sDurN)
				if RefreshDisplay then RefreshDisplay() end
			end
		elseif a1 == TAUNT_PREFIX then
			local _, _, sDur = sfind(a2, "^TN%^(%d+)$")
			if sDur and a4 and a4 ~= ownName then
				activeTauntCDs[a4] = { start = GetTime(), dur = tonumber(sDur) }
				if RefreshTauntDisplay then RefreshTauntDisplay() end
			end
		elseif a1 == STATUS_PREFIX then
			if a4 and a4 ~= ownName then
				local _, _, sName, sDur = sfind(a2, "^SS%^([^^]+)%^(%d+)$")
				if sName and sDur then
					local key = a4 .. "\31" .. sName
					activeStatusEffects[key] = { player = a4, effect = sName, start = GetTime(), dur = tonumber(sDur) }
					if RefreshDisplay then RefreshDisplay() end
				else
					local _, _, sName2 = sfind(a2, "^SE%^(.+)$")
					if sName2 then
						local key = a4 .. "\31" .. sName2
						activeStatusEffects[key] = nil
						if RefreshDisplay then RefreshDisplay() end
					end
				end
			end
		end
	end
end)

-- ── Overlay creation ──────────────────────────────────────────
local function CreateOverlay()
	local f = CreateFrame("Frame", "ART_CD_Overlay", UIParent)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetWidth(OVERLAY_MIN_W)
	f:SetHeight(HDR_H + ROW_H + 8)

	local DB = amptieRaidToolsDB
	if DB and DB.raidCDsX and DB.raidCDsY then
		f:SetPoint(DB.raidCDsPoint or "TOPLEFT", UIParent, DB.raidCDsPoint or "TOPLEFT",
		           DB.raidCDsX, DB.raidCDsY)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
	end

	f:SetBackdrop({
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetBackdropColor(0.05, 0.05, 0.08, 0.88)
	f:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)

	-- Title
	local titleFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	titleFS:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -5)
	titleFS:SetText("Raid CDs")
	titleFS:SetTextColor(1, 0.82, 0, 1)

	-- Empty-state label
	local noCD = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	noCD:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(HDR_H + 6))
	noCD:SetText("No tracked players in group.")
	noCD:SetTextColor(0.45, 0.45, 0.45, 1)
	f.noCD = noCD

	-- icon Y-offset to vertically centre inside ROW_H
	local iconYOff = -floor((ROW_H - ICON_SZ) / 2)

	-- Pre-allocated row pool
	f.rows = {}
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Frame", nil, f)
		row:SetWidth(OVERLAY_MIN_W - LEFT_PAD * 2)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -(HDR_H + (i - 1) * ROW_H + 4))

		-- Player name
		local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		nameFS:SetPoint("LEFT", row, "LEFT", 2, 0)
		nameFS:SetWidth(NAME_W)
		nameFS:SetJustifyH("LEFT")
		row.nameFS = nameFS

		-- Icon buttons
		row.icons = {}
		for j = 1, MAX_ICONS do
			local btn = CreateFrame("Button", nil, row)
			btn:SetWidth(ICON_SZ)
			btn:SetHeight(ICON_SZ)
			btn:SetPoint("TOPLEFT", row, "TOPLEFT",
			             NAME_W + NAME_ICON_GAP + (j - 1) * (ICON_SZ + ICON_GAP),
			             iconYOff)

			-- Spell icon texture
			local tex = btn:CreateTexture(nil, "BACKGROUND")
			tex:SetAllPoints(btn)
			tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			btn.tex = tex

			-- Cooldown timer (white, thick outline for readability on dark icon)
			local timerFS = btn:CreateFontString(nil, "OVERLAY")
			timerFS:SetFont("Fonts\\FRIZQT__.TTF", 13, "THICKOUTLINE")
			timerFS:SetPoint("CENTER", btn, "CENTER", 0, 0)
			timerFS:SetJustifyH("CENTER")
			timerFS:SetTextColor(1, 1, 1, 1)
			timerFS:Hide()
			btn.timerFS = timerFS

			btn:Hide()
			row.icons[j] = btn
		end

		row:Hide()
		f.rows[i] = row
	end

	-- Save position on drag
	f:SetScript("OnDragStart", function() this:StartMoving() end)
	f:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
		local pt, _, _, x, y = this:GetPoint()
		local DB2 = amptieRaidToolsDB
		if DB2 then
			DB2.raidCDsPoint = pt
			DB2.raidCDsX     = x
			DB2.raidCDsY     = y
		end
	end)

	-- 1-second refresh while visible (dirty flags handled by cdPollFrame)
	local refreshTimer = 0
	f:SetScript("OnUpdate", function()
		local dt = arg1
		if not dt or dt <= 0 then return end
		refreshTimer = refreshTimer + dt
		if refreshTimer >= 1.0 then
			refreshTimer = 0
			if RefreshDisplay then RefreshDisplay() end
		end
	end)

	f:Hide()
	overlayFrame = f
end

-- ── Refresh display ───────────────────────────────────────────
RefreshDisplay = function()
	if not overlayFrame then return end
	local now = GetTime()

	-- Expire finished cooldowns
	for key, cd in pairs(activeCooldowns) do
		if cd.dur - (now - cd.start) <= 0 then
			activeCooldowns[key] = nil
			UnpersistCD(key)
		end
	end

	local filter = (amptieRaidToolsDB and amptieRaidToolsDB.raidCDsFilter) or "all"

	local enDBst = amptieRaidToolsDB and amptieRaidToolsDB.raidStatusEnabled or {}

	-- Expire finished status effects
	for key, st in pairs(activeStatusEffects) do
		if now - st.start >= st.dur then
			activeStatusEffects[key] = nil
		end
	end

	-- Collect tracked CD players: skip offline; Shaman only when dead; apply filter
	local players = {}
	local np      = 0
	for name, class in pairs(playerClasses) do
		if SPELLS_BY_CLASS[class] then
			local unit    = playerUnits[name]
			local inGroup = (unit ~= nil)
			local online  = inGroup and UnitIsConnected(unit)
			if inGroup and online then
				local isDead = unit and (UnitIsDead(unit) or UnitIsGhost(unit))
				-- Shaman (Reincarnation): only visible when dead
				if class ~= "SHAMAN" or isDead then
					local spells = SPELLS_BY_CLASS[class]
					local addPlayer = true
					if filter ~= "all" then
						local hasAvail = false; local hasCDactive = false
						for j = 1, getn(spells) do
							local key = name .. "\31" .. spells[j].name
							local cd  = activeCooldowns[key]
							local rem = cd and (cd.dur - (now - cd.start)) or 0
							if cd and rem > 0 then hasCDactive = true else hasAvail = true end
						end
						if filter == "usable"    and not hasAvail    then addPlayer = false end
						if filter == "cooldowns" and not hasCDactive then addPlayer = false end
					end
					if addPlayer then
						np = np + 1; players[np] = name
					end
				end
			end
		end
	end
	local function classRank(class)
		for i = 1, getn(CLASS_ORDER) do
			if CLASS_ORDER[i] == class then return i end
		end
		return 99
	end
	for i = 1, np - 1 do
		for j = i + 1, np do
			local ri = classRank(playerClasses[players[i]])
			local rj = classRank(playerClasses[players[j]])
			if rj < ri or (rj == ri and players[j] < players[i]) then
				local tmp = players[i]; players[i] = players[j]; players[j] = tmp
			end
		end
	end
	local showCD = np < MAX_ROWS and np or MAX_ROWS

	-- Collect status effect rows (any enabled, active effect; deadOnly respected)
	-- statusRows[i] = { name, class, effects[effectIdx] = remaining_sec }
	local statusRows = {}
	local ns = 0
	for key, st in pairs(activeStatusEffects) do
		local ei = nil
		for k = 1, getn(ART_STATUS_TABLE) do
			if ART_STATUS_TABLE[k].name == st.effect then ei = k; break end
		end
		if ei and enDBst[st.effect] then
			local e    = ART_STATUS_TABLE[ei]
			local unit = playerUnits[st.player]
			local isDead = unit and (UnitIsDead(unit) or UnitIsGhost(unit))
			if not e.deadOnly or isDead then
				local rem = st.dur - (now - st.start)
				if rem > 0 then
					local found = false
					for ri = 1, ns do
						if statusRows[ri].name == st.player then
							statusRows[ri].effects[ei] = rem
							found = true; break
						end
					end
					if not found then
						ns = ns + 1
						local pClass = playerClasses[st.player] or "UNKNOWN"
						statusRows[ns] = { name = st.player, class = pClass, effects = {} }
						statusRows[ns].effects[ei] = rem
					end
				end
			end
		end
	end
	for i = 1, ns - 1 do
		for j = i + 1, ns do
			local ri = classRank(statusRows[i].class)
			local rj = classRank(statusRows[j].class)
			if rj < ri or (rj == ri and statusRows[j].name < statusRows[i].name) then
				local tmp = statusRows[i]; statusRows[i] = statusRows[j]; statusRows[j] = tmp
			end
		end
	end
	local showST = math.min(ns, MAX_ROWS - showCD)

	local show = showCD + showST

	-- Width: enough for the widest row (CD icons or status icons)
	local maxIcons = 1
	for i = 1, showCD do
		local spells = SPELLS_BY_CLASS[playerClasses[players[i]]]
		if spells then
			local n = getn(spells)
			if n > maxIcons then maxIcons = n end
		end
	end
	if showST > 0 and MAX_STATUS_ICONS > maxIcons then
		maxIcons = MAX_STATUS_ICONS
	end
	local dynW = LEFT_PAD + NAME_W + NAME_ICON_GAP + maxIcons * ICON_SZ + (maxIcons - 1) * ICON_GAP + RIGHT_PAD
	overlayFrame:SetWidth(dynW)
	for i = 1, show do
		overlayFrame.rows[i]:SetWidth(dynW - LEFT_PAD * 2)
	end

	for i = 1, MAX_ROWS do
		local row = overlayFrame.rows[i]
		if i <= showCD then
			-- ── CD row ──────────────────────────────────────────────
			local playerName = players[i]
			local class      = playerClasses[playerName]
			local spells     = SPELLS_BY_CLASS[class]
			local numSpells  = getn(spells)
			local col        = CLASS_COLORS[class] or { r = 0.8, g = 0.8, b = 0.8 }
			local unit       = playerUnits[playerName]
			local isDead     = unit and (UnitIsDead(unit) or UnitIsGhost(unit))
			-- Shaman: shown while dead, no dead-coloring (Reincarnation is usable)
			local applyDead  = isDead and (class ~= "SHAMAN")

			row.nameFS:SetText(playerName)
			if applyDead then
				row.nameFS:SetTextColor(0.85, 0.15, 0.15, 1)
			else
				row.nameFS:SetTextColor(col.r, col.g, col.b, 1)
			end

			for j = 1, MAX_ICONS do
				local btn = row.icons[j]
				if j <= numSpells then
					local spell = spells[j]
					local key   = playerName .. "\31" .. spell.name
					local cd    = activeCooldowns[key]
					local rem   = cd and (cd.dur - (now - cd.start)) or 0
					local onCD  = cd and rem > 0

					local showBtn = true
					if filter == "usable"    and onCD     then showBtn = false end
					if filter == "cooldowns" and not onCD then showBtn = false end

					if showBtn then
						btn.tex:SetTexture(spell.icon)
						btn:Show()
						if onCD then
							btn.tex:SetVertexColor(applyDead and 0.45 or 0.25,
							                       applyDead and 0.10 or 0.25,
							                       applyDead and 0.10 or 0.25)
							btn.timerFS:SetText(FmtTimer(rem))
							btn.timerFS:Show()
						else
							btn.tex:SetVertexColor(applyDead and 0.80 or 1,
							                       applyDead and 0.22 or 1,
							                       applyDead and 0.22 or 1)
							btn.timerFS:Hide()
						end
					else
						btn:Hide()
					end
				else
					btn:Hide()
				end
			end
			row:Show()
		elseif i <= showCD + showST then
			-- ── Status effect row ───────────────────────────────────
			local r      = statusRows[i - showCD]
			local col    = CLASS_COLORS[r.class] or { r = 0.8, g = 0.8, b = 0.8 }
			local unit   = playerUnits[r.name]
			local isDead = unit and (UnitIsDead(unit) or UnitIsGhost(unit))
			row.nameFS:SetText(r.name)
			if isDead then
				row.nameFS:SetTextColor(0.85, 0.15, 0.15, 1)
			else
				row.nameFS:SetTextColor(col.r, col.g, col.b, 1)
			end
			for j = 1, MAX_ICONS do
				local btn = row.icons[j]
				local e   = ART_STATUS_TABLE[j]
				if e and r.effects[j] then
					btn.tex:SetTexture(e.icon)
					btn.tex:SetVertexColor(1, 1, 1)
					btn.timerFS:SetText(FmtTimer(r.effects[j]))
					btn.timerFS:Show()
					btn:Show()
				else
					btn:Hide()
				end
			end
			row:Show()
		else
			row:Hide()
		end
	end

	if show > 0 then
		overlayFrame.noCD:Hide()
		overlayFrame:SetHeight(HDR_H + show * ROW_H + 8)
		local DB2 = amptieRaidToolsDB
		if DB2 and DB2.raidCDsShown then
			overlayFrame:Show()
		end
	else
		overlayFrame:Hide()
	end
end

-- ── Taunt overlay ─────────────────────────────────────────────
local function CreateTauntOverlay()
	local f = CreateFrame("Frame", "ART_TN_Overlay", UIParent)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetWidth(LEFT_PAD + NAME_W + NAME_ICON_GAP + ICON_SZ + RIGHT_PAD)
	f:SetHeight(HDR_H + ROW_H + 8)

	local DB = amptieRaidToolsDB
	if DB and DB.taunterX then
		f:SetPoint(DB.taunterPoint or "TOPLEFT", UIParent, DB.taunterPoint or "TOPLEFT",
		           DB.taunterX, DB.taunterY)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 200, 150)
	end

	f:SetBackdrop({
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetBackdropColor(0.05, 0.05, 0.08, 0.88)
	f:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)

	local titleFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	titleFS:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -5)
	titleFS:SetText("Taunts")
	titleFS:SetTextColor(1, 0.82, 0, 1)

	local noCD = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	noCD:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(HDR_H + 6))
	noCD:SetText("No taunters selected.")
	noCD:SetTextColor(0.45, 0.45, 0.45, 1)
	f.noCD = noCD

	local iconYOff = -floor((ROW_H - ICON_SZ) / 2)
	f.rows = {}
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Frame", nil, f)
		row:SetWidth(LEFT_PAD + NAME_W + NAME_ICON_GAP + ICON_SZ + RIGHT_PAD - LEFT_PAD * 2)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT_PAD, -(HDR_H + (i - 1) * ROW_H + 4))

		local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		nameFS:SetPoint("LEFT", row, "LEFT", 2, 0)
		nameFS:SetWidth(NAME_W)
		nameFS:SetJustifyH("LEFT")
		row.nameFS = nameFS

		-- single icon slot (icons[1])
		row.icons = {}
		local btn = CreateFrame("Button", nil, row)
		btn:SetWidth(ICON_SZ)
		btn:SetHeight(ICON_SZ)
		btn:SetPoint("TOPLEFT", row, "TOPLEFT", NAME_W + NAME_ICON_GAP, iconYOff)
		local tex = btn:CreateTexture(nil, "BACKGROUND")
		tex:SetAllPoints(btn)
		tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		btn.tex = tex
		local timerFS = btn:CreateFontString(nil, "OVERLAY")
		timerFS:SetFont("Fonts\\FRIZQT__.TTF", TIMER_FONT_BASE, "THICKOUTLINE")
		timerFS:SetPoint("CENTER", btn, "CENTER", 0, 0)
		timerFS:SetJustifyH("CENTER")
		timerFS:SetTextColor(1, 1, 1, 1)
		timerFS:Hide()
		btn.timerFS = timerFS
		btn:Hide()
		row.icons[1] = btn

		row:Hide()
		f.rows[i] = row
	end

	f:SetScript("OnDragStart", function() this:StartMoving() end)
	f:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
		local pt, _, _, x, y = this:GetPoint()
		local DB2 = amptieRaidToolsDB
		if DB2 then DB2.taunterPoint = pt; DB2.taunterX = x; DB2.taunterY = y end
	end)

	local refreshTimer = 0
	f:SetScript("OnUpdate", function()
		local dt = arg1
		if not dt or dt <= 0 then return end
		refreshTimer = refreshTimer + dt
		if refreshTimer >= 0.25 then
			refreshTimer = 0
			if RefreshTauntDisplay then RefreshTauntDisplay() end
		end
	end)

	f:Hide()
	tauntOverlay = f
end

RefreshTauntDisplay = function()
	if not tauntOverlay then return end
	local now = GetTime()
	for k, cd in pairs(activeTauntCDs) do
		if now - cd.start >= cd.dur then activeTauntCDs[k] = nil end
	end
	local cfg  = GetTaunterConfig()
	local np   = 0
	local players = {}
	for i = 1, getn(cfg) do
		if cfg[i].selected then
			local pName   = cfg[i].name
			local unit    = playerUnits[pName]
			-- nil unit = not in group; also skip if disconnected
			local inGroup = (unit ~= nil)
			local online  = inGroup and UnitIsConnected(unit)
			if inGroup and online then
				np = np + 1
				players[np] = pName
			end
		end
	end
	local show = np < MAX_ROWS and np or MAX_ROWS
	local dynW = LEFT_PAD + NAME_W + NAME_ICON_GAP + ICON_SZ + RIGHT_PAD
	tauntOverlay:SetWidth(dynW)
	for i = 1, show do
		tauntOverlay.rows[i]:SetWidth(dynW - LEFT_PAD * 2)
	end
	for i = 1, MAX_ROWS do
		local row = tauntOverlay.rows[i]
		if i <= show then
			local pName  = players[i]
			local class  = playerClasses[pName]
			local col    = (class and CLASS_COLORS[class]) or { r = 0.8, g = 0.8, b = 0.8 }
			local spell  = class and TAUNT_CLASS_SPELL[class]
			local unit   = playerUnits[pName]
			local isDead = unit and (UnitIsDead(unit) or UnitIsGhost(unit))
			row.nameFS:SetText(pName)
			if isDead then
				row.nameFS:SetTextColor(0.85, 0.15, 0.15, 1)
			else
				row.nameFS:SetTextColor(col.r, col.g, col.b, 1)
			end
			local btn = row.icons[1]
			if spell then
				btn.tex:SetTexture(spell.icon)
				btn:Show()
				local cd  = activeTauntCDs[pName]
				local rem = cd and (cd.dur - (now - cd.start)) or 0
				if cd and rem > 0 then
					btn.tex:SetVertexColor(isDead and 0.45 or 0.25,
					                       isDead and 0.10 or 0.25,
					                       isDead and 0.10 or 0.25)
					btn.timerFS:SetText(FmtTimer(rem))
					btn.timerFS:Show()
				else
					btn.tex:SetVertexColor(isDead and 0.80 or 1,
					                       isDead and 0.22 or 1,
					                       isDead and 0.22 or 1)
					btn.timerFS:Hide()
				end
			else
				btn:Hide()
			end
			row:Show()
		else
			row:Hide()
		end
	end
	if show > 0 then
		tauntOverlay.noCD:Hide()
		tauntOverlay:SetHeight(HDR_H + show * ROW_H + 8)
	else
		tauntOverlay.noCD:Show()
		tauntOverlay:SetHeight(HDR_H + ROW_H + 8)
	end
end

-- ── Tab component ─────────────────────────────────────────────
function AmptieRaidTools_InitRaidCDs(body)
	local frame = CreateFrame("Frame", "AmptieRaidToolsRaidCDsPanel", body)
	frame:SetAllPoints(body)

	if not overlayFrame then CreateOverlay() end

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
	title:SetText("Raid Cooldown Tracker")
	title:SetTextColor(1, 0.82, 0, 1)

	local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	desc:SetJustifyH("LEFT")
	desc:SetJustifyV("TOP")
	desc:SetWidth(280)
	desc:SetNonSpaceWrap(true)
	desc:SetText(
		"Detects when you use a tracked cooldown and broadcasts it to other " ..
		"amptieRaidTools users in your group via addon messages.\n\n" ..
		"Toggle the floating cooldown overlay with the button below."
	)

	local BD = {
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	}

	local toggleBtn = CreateFrame("Button", nil, frame)
	toggleBtn:SetWidth(120)
	toggleBtn:SetHeight(22)
	toggleBtn:SetBackdrop(BD)
	toggleBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
	toggleBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

	local toggleFS = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	toggleFS:SetPoint("CENTER", toggleBtn, "CENTER", 0, 0)
	toggleFS:SetJustifyH("CENTER")
	toggleBtn.fs = toggleFS

	local toggleGroupLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	toggleGroupLabel:SetPoint("LEFT", toggleBtn, "RIGHT", 6, 0)
	toggleGroupLabel:SetText("(group only)")
	toggleGroupLabel:SetTextColor(0.45, 0.45, 0.45, 1)
	toggleGroupLabel:Hide()

	local function UpdateToggle()
		if overlayFrame and overlayFrame:IsShown() then
			toggleBtn.fs:SetText("Hide Overlay")
			toggleBtn:SetBackdropColor(0.22, 0.17, 0.03, 0.95)
			toggleBtn:SetBackdropBorderColor(1, 0.82, 0, 1)
			toggleBtn.fs:SetTextColor(1, 0.82, 0, 1)
			toggleGroupLabel:Hide()
		elseif not IsInGroup() then
			toggleBtn.fs:SetText("Show Overlay")
			toggleBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
			toggleBtn:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
			toggleBtn.fs:SetTextColor(0.40, 0.40, 0.40, 1)
			toggleGroupLabel:Show()
		else
			toggleBtn.fs:SetText("Show Overlay")
			toggleBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
			toggleBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
			toggleBtn.fs:SetTextColor(0.85, 0.85, 0.85, 1)
			toggleGroupLabel:Hide()
		end
	end

	toggleBtn:SetScript("OnClick", function()
		if not overlayFrame then return end
		local DB2 = amptieRaidToolsDB
		if overlayFrame:IsShown() then
			if DB2 then DB2.raidCDsShown = false end
			overlayFrame:Hide()
		else
			if not IsInGroup() then return end   -- only activatable in group/raid
			if DB2 then DB2.raidCDsShown = true end
			UpdateOverlayVisibility()
		end
		UpdateToggle()
	end)

	-- Filter buttons (Show All / Only Usable / Only CDs)
	local filterOpts = {
		{ key = "all",       label = "Show All"    },
		{ key = "usable",    label = "Only Usable" },
		{ key = "cooldowns", label = "Only CDs"    },
	}
	local filterBtns  = {}
	local firstFBtn   = nil
	local prevFBtn    = nil
	local UpdateFilterBtns  -- forward declaration
	for fi = 1, getn(filterOpts) do
		local opt = filterOpts[fi]
		local fb = CreateFrame("Button", nil, frame)
		fb:SetWidth(88)
		fb:SetHeight(20)
		fb:SetBackdrop(BD)
		fb:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		if prevFBtn then
			fb:SetPoint("LEFT", prevFBtn, "RIGHT", 4, 0)
		else
			fb:SetPoint("TOPLEFT", toggleBtn, "BOTTOMLEFT", 0, -10)
		end
		local fbFS = fb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fbFS:SetPoint("CENTER", fb, "CENTER", 0, 0)
		fbFS:SetJustifyH("CENTER")
		fbFS:SetText(opt.label)
		fb.fs = fbFS
		fb.filterKey = opt.key
		fb:SetScript("OnClick", function()
			local DB2 = amptieRaidToolsDB
			if DB2 then DB2.raidCDsFilter = this.filterKey end
			if UpdateFilterBtns then UpdateFilterBtns() end
			if RefreshDisplay then RefreshDisplay() end
		end)
		tinsert(filterBtns, fb)
		if not firstFBtn then firstFBtn = fb end
		prevFBtn = fb
	end
	UpdateFilterBtns = function()
		local cur = (amptieRaidToolsDB and amptieRaidToolsDB.raidCDsFilter) or "all"
		for i = 1, getn(filterBtns) do
			local fb = filterBtns[i]
			if fb.filterKey == cur then
				fb:SetBackdropColor(0.22, 0.17, 0.03, 0.95)
				fb:SetBackdropBorderColor(1, 0.82, 0, 1)
				fb.fs:SetTextColor(1, 0.82, 0, 1)
			else
				fb:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
				fb:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
				fb.fs:SetTextColor(0.85, 0.85, 0.85, 1)
			end
		end
	end
	UpdateFilterBtns()

	-- Icon scale slider
	local slider = CreateFrame("Slider", "ART_CD_ScaleSlider", frame, "OptionsSliderTemplate")
	slider:SetWidth(180)
	slider:SetMinMaxValues(50, 200)
	slider:SetValueStep(5)
	slider:SetPoint("TOPLEFT", firstFBtn, "BOTTOMLEFT", 4, -18)
	getglobal("ART_CD_ScaleSliderLow"):SetText("50%")
	getglobal("ART_CD_ScaleSliderHigh"):SetText("200%")
	local sliderLabel = getglobal("ART_CD_ScaleSliderText")
	local sliderUpdating = false
	slider:SetScript("OnValueChanged", function()
		if sliderUpdating then return end
		local val = floor(this:GetValue() / 5 + 0.5) * 5
		local DB2 = amptieRaidToolsDB
		if DB2 then DB2.raidCDsIconScale = val end
		sliderLabel:SetText("Icon Size: " .. val .. "%")
		ApplyScale()
	end)

	-- Tracked cooldowns — checkboxes grouped by class
	local spellsHdr = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	spellsHdr:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -20)
	spellsHdr:SetText("Tracked cooldowns:")
	spellsHdr:SetTextColor(0.85, 0.85, 0.85, 1)

	local checkboxes = {}  -- { cb=frame, spell=name } for state refresh on show
	local prevAnchor = spellsHdr
	local prevIsSpell = false

	for ci = 1, getn(CLASS_ORDER) do
		local class = CLASS_ORDER[ci]
		-- collect spells for this class
		local classSpells = {}
		for si = 1, getn(ART_CD_SPELL_TABLE) do
			if ART_CD_SPELL_TABLE[si].class == class then
				tinsert(classSpells, ART_CD_SPELL_TABLE[si])
			end
		end
		if getn(classSpells) > 0 then
			local col = CLASS_COLORS[class] or { r = 0.85, g = 0.85, b = 0.85 }
			local clsHdr = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			clsHdr:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", prevIsSpell and -8 or 0, -10)
			clsHdr:SetText(CLASS_LABEL[class] or class)
			clsHdr:SetTextColor(col.r, col.g, col.b, 1)
			prevAnchor  = clsHdr
			prevIsSpell = false

			for sj = 1, getn(classSpells) do
				local e = classSpells[sj]
				local durStr = (e.dur >= 60) and (floor(e.dur / 60) .. "m") or (e.dur .. "s")
				local cb = ART_CreateCheckbox(frame, e.name .. "  |cFF888888" .. durStr .. "|r")
				cb:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT",
				            prevIsSpell and 0 or 8,
				            prevIsSpell and -3 or -6)
				local spellName = e.name
				cb.userOnClick = function()
					local DB2 = amptieRaidToolsDB
					if not DB2.raidCDsEnabled then DB2.raidCDsEnabled = {} end
					if cb:GetChecked() then
						DB2.raidCDsEnabled[spellName] = nil   -- nil = default (enabled)
					else
						DB2.raidCDsEnabled[spellName] = false
					end
					RebuildSpellsByClass()
					InitOwnSpells()
					if overlayFrame and overlayFrame:IsShown() and RefreshDisplay then
						RefreshDisplay()
					end
				end
				tinsert(checkboxes, { cb = cb, spell = spellName })
				prevAnchor  = cb
				prevIsSpell = true
			end
		end
	end

	-- ── Taunt Tracker (right column, x=320) ──────────────────
	if not tauntOverlay then CreateTauntOverlay() end

	local tTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	tTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 320, -12)
	tTitle:SetText("Taunt Tracker")
	tTitle:SetTextColor(1, 0.82, 0, 1)

	local tToggleBtn = CreateFrame("Button", nil, frame)
	tToggleBtn:SetWidth(120)
	tToggleBtn:SetHeight(22)
	tToggleBtn:SetBackdrop(BD)
	tToggleBtn:SetPoint("TOPLEFT", tTitle, "BOTTOMLEFT", 0, -8)
	tToggleBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	local tToggleFS = tToggleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	tToggleFS:SetPoint("CENTER", tToggleBtn, "CENTER", 0, 0)
	tToggleFS:SetJustifyH("CENTER")
	tToggleBtn.fs = tToggleFS

	local tGroupLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tGroupLabel:SetPoint("LEFT", tToggleBtn, "RIGHT", 6, 0)
	tGroupLabel:SetText("(group only)")
	tGroupLabel:SetTextColor(0.45, 0.45, 0.45, 1)
	tGroupLabel:Hide()

	local function UpdateTauntToggle()
		if tauntOverlay and tauntOverlay:IsShown() then
			tToggleBtn.fs:SetText("Hide Overlay")
			tToggleBtn:SetBackdropColor(0.22, 0.17, 0.03, 0.95)
			tToggleBtn:SetBackdropBorderColor(1, 0.82, 0, 1)
			tToggleBtn.fs:SetTextColor(1, 0.82, 0, 1)
			tGroupLabel:Hide()
		elseif not IsInGroup() then
			tToggleBtn.fs:SetText("Show Overlay")
			tToggleBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
			tToggleBtn:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
			tToggleBtn.fs:SetTextColor(0.40, 0.40, 0.40, 1)
			tGroupLabel:Show()
		else
			tToggleBtn.fs:SetText("Show Overlay")
			tToggleBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
			tToggleBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
			tToggleBtn.fs:SetTextColor(0.85, 0.85, 0.85, 1)
			tGroupLabel:Hide()
		end
	end

	tToggleBtn:SetScript("OnClick", function()
		if not tauntOverlay then return end
		local DB2 = amptieRaidToolsDB
		if tauntOverlay:IsShown() then
			if DB2 then DB2.taunterShown = false end
			tauntOverlay:Hide()
		else
			if not IsInGroup() then return end   -- only activatable in group/raid
			if DB2 then DB2.taunterShown = true end
			UpdateOverlayVisibility()
		end
		UpdateTauntToggle()
	end)

	local rotHdr = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	rotHdr:SetPoint("TOPLEFT", tToggleBtn, "BOTTOMLEFT", 0, -14)
	rotHdr:SetText("Taunt Rotation:")
	rotHdr:SetTextColor(0.85, 0.85, 0.85, 1)

	local syncBtn = CreateFrame("Button", nil, frame)
	syncBtn:SetWidth(120)
	syncBtn:SetHeight(18)
	syncBtn:SetBackdrop(BD)
	syncBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
	syncBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
	syncBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	syncBtn:SetPoint("LEFT", rotHdr, "RIGHT", 10, 0)
	local syncFS = syncBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	syncFS:SetPoint("CENTER", syncBtn, "CENTER", 0, 0)
	syncFS:SetText("Sync from Raid")

	-- Pre-allocated list rows
	local MAX_TLIST  = 12
	local tListRows  = {}
	local ROW_LIST_H = 22
	local tListScrollOff = 0
	local arrowBD = {
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	}
	for i = 1, MAX_TLIST do
		local row = CreateFrame("Frame", nil, frame)
		row:SetHeight(ROW_LIST_H)
		row:SetWidth(210)
		row:SetPoint("TOPLEFT", rotHdr, "BOTTOMLEFT", 0, -(4 + (i - 1) * (ROW_LIST_H + 2)))

		local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		nameFS:SetPoint("LEFT", row, "LEFT", 2, 0)
		nameFS:SetWidth(118)
		nameFS:SetJustifyH("LEFT")
		row.nameFS = nameFS

		local upBtn = CreateFrame("Button", nil, row)
		upBtn:SetWidth(18); upBtn:SetHeight(18)
		upBtn:SetPoint("LEFT", row, "LEFT", 124, 0)
		upBtn:SetBackdrop(arrowBD)
		upBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
		upBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 0.8)
		upBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		local upFS = upBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		upFS:SetPoint("CENTER", upBtn, "CENTER", 0, 1)
		upFS:SetText("^")
		row.upBtn = upBtn

		local dnBtn = CreateFrame("Button", nil, row)
		dnBtn:SetWidth(18); dnBtn:SetHeight(18)
		dnBtn:SetPoint("LEFT", row, "LEFT", 146, 0)
		dnBtn:SetBackdrop(arrowBD)
		dnBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
		dnBtn:SetBackdropBorderColor(0.35, 0.35, 0.4, 0.8)
		dnBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		local dnFS = dnBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		dnFS:SetPoint("CENTER", dnBtn, "CENTER", 0, 0)
		dnFS:SetText("v")
		row.dnBtn = dnBtn

		local cb = ART_CreateCheckbox(row, nil)
		cb:SetPoint("LEFT", row, "LEFT", 168, 0)
		row.cb = cb

		row:Hide()
		tListRows[i] = row
	end

	RefreshTaunterListUI = function()
		local cfg  = GetTaunterConfig()
		local n    = getn(cfg)
		-- Clamp scroll offset
		local maxOff = n > MAX_TLIST and (n - MAX_TLIST) or 0
		if tListScrollOff > maxOff then tListScrollOff = maxOff end
		if tListScrollOff < 0 then tListScrollOff = 0 end
		local visible = n - tListScrollOff
		if visible > MAX_TLIST then visible = MAX_TLIST end
		for i = 1, MAX_TLIST do
			local row = tListRows[i]
			if i <= visible then
				local ci = i + tListScrollOff
				local entry  = cfg[ci]
				local class  = playerClasses[entry.name]
				local unit   = playerUnits[entry.name]
				local online = unit and UnitIsConnected(unit)
				if class and online then
					local col = CLASS_COLORS[class] or { r = 0.8, g = 0.8, b = 0.8 }
					row.nameFS:SetText(entry.name)
					row.nameFS:SetTextColor(col.r, col.g, col.b, 1)
				else
					row.nameFS:SetText(entry.name .. " (offline)")
					row.nameFS:SetTextColor(0.45, 0.45, 0.45, 1)
				end
				row.cb:SetChecked(entry.selected)
				row.idx = ci
				row:Show()
			else
				row:Hide()
			end
		end
	end

	for i = 1, MAX_TLIST do
		local row = tListRows[i]
		row.upBtn:SetScript("OnClick", function()
			local cfg = GetTaunterConfig()
			local idx = this:GetParent().idx
			if idx <= 1 then return end
			local tmp = cfg[idx]; cfg[idx] = cfg[idx - 1]; cfg[idx - 1] = tmp
			RefreshTaunterListUI()
			if tauntOverlay and tauntOverlay:IsShown() and RefreshTauntDisplay then RefreshTauntDisplay() end
		end)
		row.dnBtn:SetScript("OnClick", function()
			local cfg = GetTaunterConfig()
			local idx = this:GetParent().idx
			if idx >= getn(cfg) then return end
			local tmp = cfg[idx]; cfg[idx] = cfg[idx + 1]; cfg[idx + 1] = tmp
			RefreshTaunterListUI()
			if tauntOverlay and tauntOverlay:IsShown() and RefreshTauntDisplay then RefreshTauntDisplay() end
		end)
		row.cb.userOnClick = function()
			local cfg = GetTaunterConfig()
			local idx = row.idx
			if cfg[idx] then
				cfg[idx].selected = row.cb:GetChecked()
			end
			if tauntOverlay and tauntOverlay:IsShown() and RefreshTauntDisplay then RefreshTauntDisplay() end
		end
	end

	syncBtn:SetScript("OnClick", function()
		RebuildRoster()
		SyncTauntersFromRoster()
		tListScrollOff = 0
		RefreshTaunterListUI()
	end)

	-- Mousewheel scrolling for taunt list
	local tListWheel = CreateFrame("Frame", nil, frame)
	tListWheel:SetPoint("TOPLEFT", rotHdr, "BOTTOMLEFT", 0, -4)
	tListWheel:SetWidth(210)
	tListWheel:SetHeight(MAX_TLIST * (ROW_LIST_H + 2))
	tListWheel:EnableMouseWheel(true)
	tListWheel:SetScript("OnMouseWheel", function()
		local delta = arg1
		tListScrollOff = tListScrollOff - delta
		if tListScrollOff < 0 then tListScrollOff = 0 end
		RefreshTaunterListUI()
	end)

	-- ── Raid Status Effects (right column, below taunt list) ───
	-- Y anchor: below the last possible taunt-list row
	local STATUS_Y_OFF = -(4 + MAX_TLIST * (ROW_LIST_H + 2) + 24)

	local stTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	stTitle:SetPoint("TOPLEFT", rotHdr, "BOTTOMLEFT", 0, STATUS_Y_OFF)
	stTitle:SetText("Raid Status Effects")
	stTitle:SetTextColor(1, 0.82, 0, 1)

	-- One checkbox per status effect (opt-in, default off)
	local statusCBs = {}
	local stPrevAnchor = stTitle
	for sei = 1, getn(ART_STATUS_TABLE) do
		local e      = ART_STATUS_TABLE[sei]
		local durStr = floor(e.dur / 60) .. "m"
		local cb = ART_CreateCheckbox(frame, e.name .. "  |cFF888888" .. durStr .. "|r")
		cb:SetPoint("TOPLEFT", stPrevAnchor, "BOTTOMLEFT", sei == 1 and 8 or 0, sei == 1 and -8 or -6)
		local effectName = e.name
		cb.userOnClick = function()
			local DB2 = amptieRaidToolsDB
			if not DB2.raidStatusEnabled then DB2.raidStatusEnabled = {} end
			DB2.raidStatusEnabled[effectName] = cb:GetChecked()
			-- Re-check own auras so existing effects are immediately added/cleared
			CheckOwnStatusEffects()
			if RefreshDisplay then RefreshDisplay() end
		end
		tinsert(statusCBs, { cb = cb, effect = effectName })
		stPrevAnchor = cb
	end

	-- ── Combined OnShow ────────────────────────────────────────
	frame:SetScript("OnShow", function()
		UpdateToggle()
		UpdateTauntToggle()
		UpdateFilterBtns()
		local enDB = amptieRaidToolsDB and amptieRaidToolsDB.raidCDsEnabled or {}
		for i = 1, getn(checkboxes) do
			checkboxes[i].cb:SetChecked(enDB[checkboxes[i].spell] ~= false)
		end
		local stEnDB = amptieRaidToolsDB and amptieRaidToolsDB.raidStatusEnabled or {}
		for i = 1, getn(statusCBs) do
			statusCBs[i].cb:SetChecked(stEnDB[statusCBs[i].effect] == true)
		end
		sliderUpdating = true
		local pct = (amptieRaidToolsDB and amptieRaidToolsDB.raidCDsIconScale) or 100
		slider:SetValue(pct)
		sliderLabel:SetText("Icon Size: " .. pct .. "%")
		sliderUpdating = false
		RefreshTaunterListUI()
	end)
	UpdateToggle()
	UpdateTauntToggle()

	frame.contentHeight = 200
	AmptieRaidTools_RegisterComponent("raidcds", frame)
end
