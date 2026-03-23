-- amptieRaidTools - Komponente: PlayerInfo (Hintergrund-Abfragen für den aktiven Spieler)
-- Erweiterbar für weitere Abfragen (Klasse, Spec, Level, etc.). Lua 5.0 / Vanilla 1.12.

-- Globale Tabelle für andere Komponenten (z. B. Home)
AmptieRaidTools_PlayerInfo = AmptieRaidTools_PlayerInfo or {}
local PI = AmptieRaidTools_PlayerInfo

-- Talentpunkte abfragen: 5. Rückgabewert von GetTalentInfo = gesetzte Punkte (als Zahl)
-- Hinweis: GetTalentInfo funktioniert hier nicht zuverlässig; Spec-Anzeige erfolgt in home.lua mit direkter Abfrage.
local function GetTalentRank(tree, talent)
	local _, _, _, _, x = GetTalentInfo(tree, talent)
	local n = tonumber(x)
	return (n and n >= 0) and n or 0
end

-- Warrior-Spec anhand Talente (Reihenfolge: spezifisch vor allgemein)
local function GetWarriorSpec()
	local r3_12 = GetTalentRank(3, 12)  -- Defiance (Prot)
	local r2_17 = GetTalentRank(2, 17)  -- Fury
	local r3_19 = GetTalentRank(3, 19)  -- Deep Prot
	local r1_11 = GetTalentRank(1, 11)  -- Fury
	local r2_15 = GetTalentRank(2, 15)
	local r1_13 = GetTalentRank(1, 13)
	local r1_18 = GetTalentRank(1, 18)  -- Mortal Strike

	if r3_12 == 5 and r2_17 == 1 then return "Fury Prot" end
	if r3_19 == 1 then return "Deep Prot" end
	if r2_17 == 1 and r1_11 == 2 then return "Fury" end
	if r2_15 == 5 and r1_13 == 1 then return "Fury + Sweeping Strikes" end
	if r1_18 == 1 then return "Mortal Strike" end
	if r3_12 == 5 then return "Tank" end
	return nil
end

local function UpdatePlayerInfo()
	local _, classname = UnitClass("player")
	PI.class = classname
	PI.spec = nil
	-- Klasse: Token ist z. B. "WARRIOR", lokalisierter Name z. B. "Krieger"
	local classUpper = classname and string.upper(tostring(classname)) or ""
	if classUpper == "WARRIOR" then
		PI.spec = GetWarriorSpec()
	end
end

-- Global: Talentpunkte (3,19) etc. für Anzeige/Debug
function AmptieRaidTools_GetTalentRank(tree, talent)
	return GetTalentRank(tree, talent)
end

-- Global aufrufbar, damit z. B. Home die Anzeige nach Respec aktualisieren kann
function AmptieRaidTools_UpdatePlayerInfo()
	UpdatePlayerInfo()
end

-- Spec beim Anzeigen direkt aus Talenten ermitteln (damit Anzeige immer aktuell ist)
function AmptieRaidTools_GetCurrentSpec()
	local _, classname = UnitClass("player")
	local classUpper = classname and string.upper(tostring(classname)) or ""
	if classUpper ~= "WARRIOR" then
		return nil
	end
	return GetWarriorSpec()
end

function AmptieRaidTools_InitPlayerInfo()
	UpdatePlayerInfo()
	local ef = CreateFrame("Frame", nil, UIParent)
	ef:RegisterEvent("PLAYER_LOGIN")
	ef:RegisterEvent("PLAYER_ENTERING_WORLD")
	ef:RegisterEvent("CHARACTER_POINTS_CHANGED")
	ef:SetScript("OnEvent", function()
		local evt = event
		if evt == "PLAYER_LOGIN" or evt == "PLAYER_ENTERING_WORLD" then
			UpdatePlayerInfo()
		elseif evt == "CHARACTER_POINTS_CHANGED" then
			if AmptieRaidTools_RefreshSpecInBackground then
				AmptieRaidTools_RefreshSpecInBackground()
			end
		end
	end)
end
