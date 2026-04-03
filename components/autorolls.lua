-- amptieRaidTools - Auto-Rolls: Roll-Logik + UI-Komponente. Lua 5.0.

local strfind = string.find
local tonum = tonumber

-- SavedVariables: amptieRaidToolsDB.autorolls (wird auch von main.lua genutzt)
local function GetDB()
	local db = amptieRaidToolsDB or {}
	db.autorolls = db.autorolls or {}
	local ar = db.autorolls
	if ar.sand == nil then ar.sand = "none" end
	if ar.scholo == nil then ar.scholo = "none" end
	if ar.zg == nil then ar.zg = "none" end
	if ar.aq == nil then ar.aq = "none" end
	if ar.mc == nil then ar.mc = "none" end
	if ar.naxx == nil then ar.naxx = "none" end
	if ar.kara10 == nil then ar.kara10 = "none" end
	if ar.kara40 == nil then ar.kara40 = "none" end
	return ar
end

local ROLL_VALUES = { need = 1, greed = 2, pass = 0 }
local BM_IDS = { [50203] = true }
local SCHOLO_IDS = { [12843] = true }
-- Kara: gleiche Zone "The Tower of Karazhan", Unterscheidung über Raidgröße (>= 15 = Kara40, wie CorruptedLootCouncil)
local KARA_ARCANE_ESSENCE_ID = 61673
local KARA40_ONLY_IDS = { [41485] = true, [61674] = true }
local ZG_IDS = {
	[19698]=true,[19699]=true,[19700]=true,[19701]=true,[19702]=true,[19703]=true,[19704]=true,[19705]=true,[19706]=true,
	[19707]=true,[19708]=true,[19709]=true,[19710]=true,[19711]=true,[19712]=true,[19713]=true,[19714]=true,[19715]=true,
}
local MC_IDS = { [11382]=true, [17010]=true, [17011]=true }
local AQ_IDS = {
	[20858]=true,[20859]=true,[20860]=true,[20861]=true,[20862]=true,[20863]=true,[20864]=true,[20865]=true,[20866]=true,
	[20867]=true,[20868]=true,[20869]=true,[20870]=true,[20871]=true,[20872]=true,[20873]=true,[20874]=true,[20875]=true,
	[20876]=true,[20877]=true,[20878]=true,[20879]=true,[20881]=true,[20882]=true,
}
local NAXX_IDS = { [22373]=true, [22374]=true, [22375]=true, [22376]=true }

-- Wardens of Time Exalted (ruf == 8): Sand ist nutzlos, immer Pass
local function IsWardensOfTimeExalted()
	for nummer = 1, 100 do
		local name, _, ruf = GetFactionInfo(nummer)
		if name == "Wardens of Time" and ruf == 8 then return true end
	end
	return false
end

-- Kara40 wenn Zone Karazhan und Raid >= 15 (Logik wie CorruptedLootCouncil)
local function IsKara40()
	local z = GetRealZoneText()
	if not z then return false end
	if z ~= "The Tower of Karazhan" and z ~= "Tower of Karazhan" then return false end
	local n = GetNumRaidMembers()
	if not n or n < 15 then return false end
	return true
end

local rollEventFrame = CreateFrame("Frame", "AmptieRaidToolsAutoRollsEventFrame", UIParent)
rollEventFrame:RegisterEvent("START_LOOT_ROLL")
rollEventFrame.pendingRollId = nil
rollEventFrame.pendingRollType = nil
rollEventFrame:SetScript("OnEvent", function()
	local evt = event
	local a1 = arg1
	if evt == "START_LOOT_ROLL" and a1 then
		if not GetLootRollItemLink then return end
		local rollId = a1
		local link = GetLootRollItemLink(rollId)
		if not link then return end
		local _, _, idStr = strfind(link, "item:(%d+):")
		local itemId = idStr and tonum(idStr) or nil
		if not itemId then return end
		local ar = GetDB()
		local rollVal = nil
		if BM_IDS[itemId] then
			if IsWardensOfTimeExalted() then
				rollVal = 0
			elseif ar.sand and ar.sand ~= "none" then
				rollVal = ROLL_VALUES[ar.sand]
			end
		elseif SCHOLO_IDS[itemId] and ar.scholo and ar.scholo ~= "none" then
				rollVal = ROLL_VALUES[ar.scholo]
			elseif ZG_IDS[itemId] and ar.zg and ar.zg ~= "none" then
			rollVal = ROLL_VALUES[ar.zg]
		elseif AQ_IDS[itemId] and ar.aq and ar.aq ~= "none" then
			rollVal = ROLL_VALUES[ar.aq]
		elseif MC_IDS[itemId] and ar.mc and ar.mc ~= "none" then
			rollVal = ROLL_VALUES[ar.mc]
		elseif NAXX_IDS[itemId] and ar.naxx and ar.naxx ~= "none" then
			rollVal = ROLL_VALUES[ar.naxx]
		elseif itemId == KARA_ARCANE_ESSENCE_ID then
			local z = GetRealZoneText()
			if z and (z == "The Tower of Karazhan" or z == "Tower of Karazhan") then
				if IsKara40() and ar.kara40 and ar.kara40 ~= "none" then
					rollVal = ROLL_VALUES[ar.kara40]
				elseif ar.kara10 and ar.kara10 ~= "none" then
					rollVal = ROLL_VALUES[ar.kara10]
				end
			end
		elseif KARA40_ONLY_IDS[itemId] and ar.kara40 and ar.kara40 ~= "none" then
			rollVal = ROLL_VALUES[ar.kara40]
		end
		if rollVal ~= nil then
			RollOnLoot(rollId, rollVal)
			rollEventFrame.pendingRollId = rollId
			rollEventFrame.pendingRollType = rollVal
		end
	end
end)
rollEventFrame:SetScript("OnUpdate", function()
	if rollEventFrame.pendingRollId == nil then return end
	for i = 1, STATICPOPUP_NUMDIALOGS do
		local popup = getglobal("StaticPopup" .. i)
		if popup and popup:IsShown() and popup.which == "CONFIRM_LOOT_ROLL" then
			if popup.data == rollEventFrame.pendingRollId and popup.data2 == rollEventFrame.pendingRollType then
				getglobal("StaticPopup" .. i .. "Button1"):Click()
				rollEventFrame.pendingRollId = nil
				rollEventFrame.pendingRollType = nil
				return
			end
		end
	end
end)

-- ============================================================
-- UI-Komponente
-- ============================================================
local AR_ROWS = {
	{ key = "sand",   label = "Black Morass (Sand)",
	  tooltip = "Hourglass Sand from Black Morass (item 50203).\n|cffaaaaааWhen Wardens of Time Exalted: only None / Pass available.|r" },
	{ key = "scholo", label = "Scholo/Strat (Corruptor's Scourgestones)",
	  tooltip = "Corruptor's Scourgestone from Scholomance / Stratholme (item 12843)." },
	{ key = "zg",     label = "Zul'Gurub (Coins + Bijous)",
	  tooltip = "Bijous and Coins from Zul'Gurub." },
	{ key = "aq",     label = "Ahn'Qiraj (Scarabs + Idols)",
	  tooltip = "Armor Tokens from Ahn'Qiraj." },
	{ key = "mc",     label = "Molten Core (Fiery/Lava Core)",
	  tooltip = "Rare crafting materials from Molten Core." },
	{ key = "naxx",   label = "Naxxramas (Scraps)",
	  tooltip = "Wartorn Scraps from Naxxramas." },
	{ key = "kara10", label = "Lower Karazhan (Arcane Essences)",
	  tooltip = "Arcane Essence from Karazhan 10-man." },
	{ key = "kara40", label = "Upper Karazhan (Arcane Essences + Energies)",
	  tooltip = "Exclusive items from Karazhan 40-man." },
}
local AR_OPTS = { "none", "need", "greed", "pass" }
local AR_OPTS_COLOR = {
	none  = { 0.6, 0.6, 0.6 },
	need  = { 0.2, 0.9, 0.2 },
	greed = { 0.2, 0.6, 1.0 },
	pass  = { 1.0, 0.4, 0.4 },
}

function AmptieRaidTools_InitAutoRolls(body)
	local panel = CreateFrame("Frame", "AmptieRaidToolsAutoRollsPanel", body)
	panel:SetAllPoints(body)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
	title:SetText("Auto-Rolls")
	title:SetTextColor(1, 0.82, 0, 1)

	local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	desc:SetJustifyH("LEFT")
	desc:SetWidth(500)
	desc:SetText("Automatically roll on set items when a loot roll starts. Click to cycle: none > need > greed > pass.")

	local colLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	colLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
	colLabel:SetText("Category")
	colLabel:SetTextColor(0.7, 0.7, 0.7, 1)

	local colRoll = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	colRoll:SetPoint("LEFT", colLabel, "LEFT", 220, 0)
	colRoll:SetText("Roll")
	colRoll:SetTextColor(0.7, 0.7, 0.7, 1)

	local rowButtons = {}

	local function GetNextOpt(cur)
		for i = 1, table.getn(AR_OPTS) do
			if AR_OPTS[i] == cur then
				return AR_OPTS[i + 1] or AR_OPTS[1]
			end
		end
		return AR_OPTS[1]
	end

	-- For Sand: restrict to none/pass when Wardens of Time Exalted
	local function GetNextOptForKey(key, cur)
		if key == "sand" and IsWardensOfTimeExalted() then
			return cur == "none" and "pass" or "none"
		end
		return GetNextOpt(cur)
	end

	local AR_BTN_BACKDROP = {
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	}

	local function RefreshButtons()
		local ar = GetDB()
		for i = 1, table.getn(rowButtons) do
			local rb = rowButtons[i]
			local val = ar[rb.rowKey] or "none"
			local col = AR_OPTS_COLOR[val] or AR_OPTS_COLOR["none"]
			rb.fs:SetText(val)
			rb.fs:SetTextColor(col[1], col[2], col[3], 1)
		end
	end

	for i = 1, table.getn(AR_ROWS) do
		local row = AR_ROWS[i]
		local yOff = -10 - (i - 1) * 28

		local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		lbl:SetPoint("TOPLEFT", colLabel, "BOTTOMLEFT", 0, yOff)
		lbl:SetJustifyH("LEFT")
		lbl:SetWidth(200)
		lbl:SetText(row.label)

		local btn = CreateFrame("Button", nil, panel)
		btn:SetPoint("LEFT", lbl, "RIGHT", 12, 0)
		btn:SetWidth(80)
		btn:SetHeight(22)
		btn:SetBackdrop(AR_BTN_BACKDROP)
		btn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
		btn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
		btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		btn.rowKey   = row.key
		btn.rowLabel = row.label

		local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
		btn.fs = fs

		btn:SetScript("OnClick", function()
			local ar = GetDB()
			ar[this.rowKey] = GetNextOptForKey(this.rowKey, ar[this.rowKey] or "none")
			RefreshButtons()
		end)

		local capTooltip = row.tooltip
		btn:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:AddLine(this.rowLabel, 1, 0.82, 0, 1)
			if capTooltip then
				GameTooltip:AddLine(capTooltip, 1, 1, 1, 1)
			end
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		table.insert(rowButtons, btn)
	end

	panel:SetScript("OnShow", function() RefreshButtons() end)
	RefreshButtons()

	AmptieRaidTools_RegisterComponent("autorolls", panel)
end
