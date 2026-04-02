-- amptieRaidTools - Komponente: NPC Trading
-- Einstellungen: Graue Items verkaufen, Time-Worn Rune nachkaufen, Klassenmaterialien. Lua 5.0.
-- Kauf-Logik angelehnt an TopMeOff (https://github.com/melbaa/TopMeOff).

local getn = table.getn
local tonum = tonumber
local ceil = math.ceil
local strfind = string.find

-- SavedVariables-Struktur: amptieRaidToolsDB.npctrading
local function GetDB()
	local db = amptieRaidToolsDB or {}
	db.npctrading = db.npctrading or {}
	local npc = db.npctrading
	if npc.autoSellGrey == nil then npc.autoSellGrey = false end
	if npc.autoRepair == nil then npc.autoRepair = false end
	if npc.autoBuyTimeWornRune == nil then npc.autoBuyTimeWornRune = false end
	if npc.materials == nil then npc.materials = {} end
	if npc.customItems == nil then npc.customItems = {} end
	if npc.roguePoisons == nil then npc.roguePoisons = {} end
	return npc
end

-- Item-IDs für Klassenmaterialien (Vanilla 1.12 / TurtleWoW)
local ITEM_IDS = {
	["Symbol of Kings"] = 21177,
	["Ankh"] = 17030,
	["Rune of Teleportation"] = 17031,
	["Rune of Portals"] = 17032,
	["Arcane Powder"] = 17020,
	["Sacred Candle"] = 17029,
	["Wild Thornroot"] = 17026,
	["Ironwood Seed"] = 17038,
	["Flash Powder"] = 5140,
	["Demonic Figurine"] = 16583,
	["Infernal Stone"] = 5565,
}

-- Item-ID aus Link extrahieren (|Hitem:12345:...|h)
local function GetItemIdFromLink(link)
	if not link or link == "" then return nil end
	local _, _, id = strfind(link, "|Hitem:(%d+):")
	return id and tonum(id) or nil
end

-- Anzeigename aus Link extrahieren (|h[Name]|h)
local function GetItemNameFromLink(link)
	if not link or link == "" then return nil end
	local _, _, name = strfind(link, "|h%[(.-)%]|h")
	return name
end

-- Zählt Items in Taschen. nameAliases: Anzeigename → logische Kennung (z. B. Time-Worn Rune → __TimeWornRune)
local function CountReagentsInBags(wantedById, wantedByName, nameAliases)
	local ownedById = {}
	local ownedByName = {}
	if wantedById then
		for id in pairs(wantedById) do
			ownedById[id] = 0
		end
	end
	if wantedByName then
		for key in pairs(wantedByName) do
			ownedByName[key] = 0
		end
	end

	for bag = 0, 4 do
		local numSlots = GetContainerNumSlots(bag)
		for slot = 1, numSlots do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local _, count = GetContainerItemInfo(bag, slot)
				if not count then count = 0 end
				local id = GetItemIdFromLink(link)
				local name = GetItemNameFromLink(link)
				if wantedById and id and ownedById[id] ~= nil then
					ownedById[id] = ownedById[id] + count
				end
				if wantedByName and name then
					local key = (nameAliases and nameAliases[name]) or name
					if ownedByName[key] ~= nil then
						ownedByName[key] = ownedByName[key] + count
					end
				end
			end
		end
	end
	return ownedById, ownedByName
end

-- Graue Items (Quality 0) an Händler verkaufen
local function SellGreyItems()
	for bag = 0, 4 do
		local numSlots = GetContainerNumSlots(bag)
		for slot = 1, numSlots do
			local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
			if quality == 0 and not locked then
				UseContainerItem(bag, slot)
			end
		end
	end
end

-- Wanted-Listen aus DB bauen: wantedById[id]=minCount, wantedByName[name]=minCount (nur Time-Worn Rune)
local function BuildWantedLists()
	local npc = GetDB()
	local wantedById = {}
	local wantedByName = {}

	for itemName, minCount in pairs(npc.materials) do
		local n = tonum(minCount)
		if n and n > 0 and ITEM_IDS[itemName] then
			wantedById[ITEM_IDS[itemName]] = n
		end
	end

	-- Individuelle Items (per ID oder per Name)
	for i = 1, getn(npc.customItems) do
		local entry = npc.customItems[i]
		if entry and entry.count and entry.count > 0 then
			if entry.id then
				local cur = wantedById[entry.id]
				local n = entry.count
				if not cur or n > cur then
					wantedById[entry.id] = n
				end
			elseif entry.name and entry.name ~= "" then
				wantedByName[entry.name] = entry.count
			end
		end
	end

	-- Time-Worn Rune: eine logische Kennung, Namen je nach Lokalisierung
	local nameAliases = {}
	if npc.autoBuyTimeWornRune then
		wantedByName["__TimeWornRune"] = 1
		nameAliases["Time-Worn Rune"] = "__TimeWornRune"
		nameAliases["Zeitabgenutzte Rune"] = "__TimeWornRune"  -- deDE
	end

	return wantedById, wantedByName, nameAliases
end

-- Kauf-Queue: BuyMerchantItem darf nicht in Masse im selben Frame aufgerufen werden,
-- sonst werden Käufe vom Client gedroppt. Wir verteilen sie über OnUpdate mit 0.15s Abstand.
local purchaseQueue = {}
local purchaseTimer = 0
local PURCHASE_DELAY = 0.15

local npcPurchaseFrame = CreateFrame("Frame", "ART_NPC_PurchaseFrame", UIParent)
npcPurchaseFrame:Hide()
npcPurchaseFrame:RegisterEvent("MERCHANT_CLOSED")
npcPurchaseFrame:SetScript("OnEvent", function()
	if event == "MERCHANT_CLOSED" then
		for k in pairs(purchaseQueue) do purchaseQueue[k] = nil end
		purchaseQueue.n = 0
		purchaseTimer = 0
		npcPurchaseFrame:Hide()
	end
end)
npcPurchaseFrame:SetScript("OnUpdate", function()
	local dt = arg1
	if not dt or dt < 0 then dt = 0 end
	purchaseTimer = purchaseTimer + dt
	if purchaseTimer < PURCHASE_DELAY then return end
	purchaseTimer = 0
	local n = getn(purchaseQueue)
	if n == 0 then
		npcPurchaseFrame:Hide()
		return
	end
	local entry = purchaseQueue[1]
	table.remove(purchaseQueue, 1)
	BuyMerchantItem(entry.slot, entry.times)
	if getn(purchaseQueue) == 0 then
		npcPurchaseFrame:Hide()
	end
end)

local function QueuePurchase(slot, times)
	tinsert(purchaseQueue, { slot = slot, times = times })
	npcPurchaseFrame:Show()
end

-- Beim Händler: Reagenzien nachkaufen (TopMeOff-Logik)
local function BuyReagents()
	local wantedById, wantedByName, nameAliases = BuildWantedLists()
	local hasWanted = false
	if wantedById then
		for _ in pairs(wantedById) do hasWanted = true break end
	end
	if wantedByName then
		for _ in pairs(wantedByName) do hasWanted = true break end
	end
	if not hasWanted then return end

	local ownedById, ownedByName = CountReagentsInBags(wantedById, wantedByName, nameAliases)

	local numItems = GetMerchantNumItems()
	for i = 1, numItems do
		local link = GetMerchantItemLink(i)
		if link then
			local name, texture, price, batchSize, numAvailable, isUsable, extendedCost = GetMerchantItemInfo(i)
			if not batchSize or batchSize < 1 then batchSize = 1 end

			local id = GetItemIdFromLink(link)
			local itemName = GetItemNameFromLink(link)

			-- Nach ID (Klassenmaterialien)
			if wantedById and id and wantedById[id] then
				local want = wantedById[id]
				local have = ownedById[id] or 0
				if have < want then
					local needed = want - have
					if needed > 0 then
						local times = ceil(needed / batchSize)
						QueuePurchase(i, times)
						ownedById[id] = (ownedById[id] or 0) + times * batchSize
					end
				end
			end

			-- Nach Name/Alias (z. B. Time-Worn Rune, in mehreren Sprachen)
			local key = (nameAliases and nameAliases[itemName]) or itemName
			if wantedByName and key and wantedByName[key] then
				local want = wantedByName[key]
				local have = ownedByName[key] or 0
				if have < want then
					local needed = want - have
					if needed > 0 then
						local times = ceil(needed / batchSize)
						QueuePurchase(i, times)
						ownedByName[key] = (ownedByName[key] or 0) + times * batchSize
					end
				end
			end
		end
	end
end

-- Lokalisierter Klassenname → Token (en: "Mage", de: "Magier" etc.)
local LOCALIZED_CLASS_TO_TOKEN = {
	["Paladin"] = "PALADIN", ["Shaman"] = "SHAMAN", ["Mage"] = "MAGE", ["Priest"] = "PRIEST", ["Druid"] = "DRUID",
	["Rogue"]   = "ROGUE",   ["Warrior"] = "WARRIOR", ["Warlock"] = "WARLOCK",
	["Schamane"] = "SHAMAN", ["Magier"] = "MAGE", ["Priester"] = "PRIEST", ["Druide"] = "DRUID",
	["Schurke"] = "ROGUE",   ["Krieger"] = "WARRIOR", ["Hexenmeister"] = "WARLOCK",
}

-- Klassenmaterialien pro Klasse (Token)
-- Paladin: Symbol of Kings (20er-Stacks), Shaman: Ankh, Mage: 3, Priest: 1, Druid: 2
local CLASS_MATERIALS = {
	PALADIN = { { name = "Symbol of Kings", note = " (20er-Stacks)" } },
	SHAMAN  = { { name = "Ankh" } },
	MAGE    = {
		{ name = "Rune of Teleportation" },
		{ name = "Rune of Portals" },
		{ name = "Arcane Powder" },
	},
	PRIEST  = { { name = "Sacred Candle" } },
	DRUID   = {
		{ name = "Wild Thornroot" },
		{ name = "Ironwood Seed" },
	},
	ROGUE    = {
		{ name = "Flash Powder" },
	},
	WARLOCK  = {
		{ name = "Demonic Figurine" },
		{ name = "Infernal Stone" },
	},
}

-- Rogue poison crafting data: each poison's item ID, crafted doses per batch, and material list
-- Material IDs: Crystal Vial=8925, Essence of Agony=8923, Dust of Deterioration=8924,
--               Deathweed=5173, Maiden's Anguish=2931, Leaded Vial=3372
local ROGUE_POISONS = {
	-- Instant Poison VI: TurtleWoW/vanilla 3x Dust of Deterioration + 1x Crystal Vial; 5 charges per craft (classic)
	{ id=8928,  name="Instant Poison VI",       doses=6, mats={ {id=8924,qty=4},{id=8925,qty=1} } },
	{ id=20844, name="Deadly Poison V",         doses=6, mats={ {id=5173,qty=7},{id=8925,qty=1} } },
	{ id=9186,  name="Mind-numbing Poison III", doses=6, mats={ {id=8924,qty=2},{id=8923,qty=2},{id=8925,qty=1} } },
	{ id=3776,  name="Crippling Poison II",     doses=6, mats={ {id=8923,qty=3},{id=8925,qty=1} } },
	{ id=10922, name="Wound Poison IV",         doses=6, mats={ {id=8923,qty=2},{id=5173,qty=2},{id=8925,qty=1} } },
	{ id=54010, name="Dissolvent Poison II",    doses=6, mats={ {id=2931,qty=4},{id=8924,qty=3},{id=8925,qty=1} } },
	{ id=47409, name="Corrosive Poison II",     doses=6, mats={ {id=8924,qty=3},{id=8923,qty=3},{id=8925,qty=1} } },
	{ id=65032, name="Agitating Poison",        doses=6, mats={ {id=2931,qty=2},{id=3372,qty=1} } },
}

-- Beim Händler: Rogue-Gift-Herstellungsmaterialien nachkaufen
-- Kauft nur dann, wenn ALLE Materialien für ein Gift beim selben Händler vorhanden sind.
local function BuyRoguePoisonMaterials()
	local pi = AmptieRaidTools_PlayerInfo or {}
	local classRaw = (pi and pi.class) and tostring(pi.class) or ""
	local classToken = LOCALIZED_CLASS_TO_TOKEN[classRaw] or (classRaw ~= "" and string.upper(classRaw) or "")
	if classToken ~= "ROGUE" then return end

	local npc = GetDB()
	if not npc.roguePoisons then return end

	-- Händler-Slots: id -> slot-Index
	local merchantSlots = {}
	local numItems = GetMerchantNumItems()
	for i = 1, numItems do
		local link = GetMerchantItemLink(i)
		if link then
			local id = GetItemIdFromLink(link)
			if id then merchantSlots[id] = i end
		end
	end

	-- Benötigte Materialien aggregieren (über alle Gifte)
	local matsToBuy = {}
	for pidx = 1, getn(ROGUE_POISONS) do
		local poison = ROGUE_POISONS[pidx]
		local target = tonum(npc.roguePoisons[poison.name]) or 0
		if target > 0 then
			-- Aktuelle Gift-Items in Taschen zählen (target = Anzahl herzustellender Items)
			local current = 0
			for bag = 0, 4 do
				local numSlots = GetContainerNumSlots(bag)
				for slot = 1, numSlots do
					local link = GetContainerItemLink(bag, slot)
					if link then
						local slotId = GetItemIdFromLink(link)
						if slotId == poison.id then
							local _, count = GetContainerItemInfo(bag, slot)
							current = current + (count or 0)
						end
					end
				end
			end

			if current < target then
				local craftsNeeded = target - current
				-- Nur kaufen wenn ALLE Materialien bei diesem Händler vorhanden
				local allPresent = true
				for j = 1, getn(poison.mats) do
					if not merchantSlots[poison.mats[j].id] then
						allPresent = false
						break
					end
				end
				if allPresent then
					for j = 1, getn(poison.mats) do
						local mat = poison.mats[j]
						matsToBuy[mat.id] = (matsToBuy[mat.id] or 0) + craftsNeeded * mat.qty
					end
				end
			end
		end
	end

	-- Bereits vorhandene Materialien in Taschen abziehen
	local matsInBags = {}
	for id in pairs(matsToBuy) do matsInBags[id] = 0 end
	for bag = 0, 4 do
		local numSlots = GetContainerNumSlots(bag)
		for slot = 1, numSlots do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local slotId = GetItemIdFromLink(link)
				if slotId and matsInBags[slotId] ~= nil then
					local _, count = GetContainerItemInfo(bag, slot)
					matsInBags[slotId] = matsInBags[slotId] + (count or 0)
				end
			end
		end
	end

	-- Einkaufen
	for id, needed in pairs(matsToBuy) do
		local slotIdx = merchantSlots[id]
		if slotIdx then
			local have = matsInBags[id] or 0
			local toBuy = needed - have
			if toBuy > 0 then
				local name, texture, price, batchSize, numAvailable = GetMerchantItemInfo(slotIdx)
				if not batchSize or batchSize < 1 then batchSize = 1 end
				local times = ceil(toBuy / batchSize)
				if numAvailable and numAvailable ~= -1 and numAvailable < times * batchSize then
					times = floor(numAvailable / batchSize)
				end
				if times > 0 then
					QueuePurchase(slotIdx, times)
				end
			end
		end
	end
end

local ROW_HEIGHT = 24
local ROW_PADDING = 4
local MAX_MATERIAL_ROWS = 8
local MAX_CUSTOM_ROWS = 20

function AmptieRaidTools_InitNPCTrading(body)
	local frame = CreateFrame("Frame", "AmptieRaidToolsNPCTradingPanel", body)
	frame:SetAllPoints(body)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
	title:SetText("NPC Trading")
	title:SetTextColor(1, 0.82, 0, 1)

	local db = GetDB()

	-- Checkbox: Graue Items automatisch verkaufen
	local cbGrey = ART_CreateCheckbox(frame, "Sell grey items automatically")
	cbGrey:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -22)
	cbGrey:SetChecked(db.autoSellGrey)
	cbGrey.userOnClick = function()
		local npc = GetDB()
		npc.autoSellGrey = cbGrey:GetChecked()
	end

	-- Checkbox: Automatic Repair
	local cbRepair = ART_CreateCheckbox(frame, "Automatic Repair")
	cbRepair:SetPoint("TOPLEFT", cbGrey, "BOTTOMLEFT", 0, -10)
	cbRepair:SetChecked(db.autoRepair)
	cbRepair.userOnClick = function()
		local npc = GetDB()
		npc.autoRepair = cbRepair:GetChecked()
	end

	-- Zwischenüberschrift "Auto Re-Buy"
	local autoRebuyTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	autoRebuyTitle:SetPoint("TOPLEFT", cbRepair, "BOTTOMLEFT", 0, -14)
	autoRebuyTitle:SetJustifyH("LEFT")
	autoRebuyTitle:SetTextColor(1, 0.82, 0, 1)
	autoRebuyTitle:SetText("Auto Re-Buy")
	frame.autoRebuyTitle = autoRebuyTitle

	-- Checkbox: Time-Worn Rune (thematisch bei Auto Re-Buy)
	local cbRune = ART_CreateCheckbox(frame, "Restock Time-Worn Rune when not in inventory")
	cbRune:SetPoint("TOPLEFT", autoRebuyTitle, "BOTTOMLEFT", 0, -10)
	cbRune:SetChecked(db.autoBuyTimeWornRune)
	cbRune.userOnClick = function()
		local npc = GetDB()
		npc.autoBuyTimeWornRune = cbRune:GetChecked()
	end

	-- ScrollFrame für scrollbaren Inhalt (alle Material-/Gift-/Custom-Zeilen)
	local npcSF = CreateFrame("ScrollFrame", "ART_NPC_ScrollFrame", frame)
	npcSF:SetPoint("TOPLEFT",     cbRune, "BOTTOMLEFT",  0, -8)
	npcSF:SetPoint("BOTTOMRIGHT", frame,  "BOTTOMRIGHT", -22, 4)

	local content = CreateFrame("Frame", "ART_NPC_Content", npcSF)
	content:SetWidth(580)
	content:SetHeight(1200)
	npcSF:SetScrollChild(content)
	content:SetPoint("TOPLEFT", npcSF, "TOPLEFT", 0, 0)

	local NPC_SF_H     = 340   -- initial estimate; updated from npcSF:GetHeight() in OnShow
	local npcScrollOff = 0

	local function SetNpcScroll(val)
		local maxScroll = math.max(content:GetHeight() - NPC_SF_H, 0)
		if val < 0        then val = 0        end
		if val > maxScroll then val = maxScroll end
		npcScrollOff = val
		content:ClearAllPoints()
		content:SetPoint("TOPLEFT", npcSF, "TOPLEFT", 0, val)
	end

	-- Überschrift Klassenmaterialien
	local matTitle = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	matTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -8)
	matTitle:SetJustifyH("LEFT")
	matTitle:SetText("Class materials (restock to minimum automatically)")
	frame.matTitle = matTitle

	local noClassLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	noClassLabel:SetPoint("TOPLEFT", matTitle, "BOTTOMLEFT", 0, -4)
	noClassLabel:SetJustifyH("LEFT")
	noClassLabel:SetTextColor(0.7, 0.7, 0.7, 1)
	noClassLabel:SetText("No class-specific materials for your class.")
	noClassLabel:Hide()
	frame.noClassLabel = noClassLabel

	-- Container für dynamische Material-Zeilen (Höhe wird in RefreshMaterialRows angepasst)
	local matContainer = CreateFrame("Frame", nil, content)
	matContainer:SetPoint("TOPLEFT", matTitle, "BOTTOMLEFT", 0, -8)
	matContainer:SetWidth(400)
	matContainer:SetHeight(0)
	frame.matContainer = matContainer

	-- Anker unterhalb des Klassenmaterial-Blocks (noClassLabel oder matContainer), damit Custom Items immer sichtbar darunter liegen
	local classMaterialsAnchor = CreateFrame("Frame", nil, content)
	classMaterialsAnchor:SetPoint("TOPLEFT", matContainer, "BOTTOMLEFT", 0, 0)
	classMaterialsAnchor:SetWidth(1)
	classMaterialsAnchor:SetHeight(1)
	frame.classMaterialsAnchor = classMaterialsAnchor

	local EB_BD = {
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 10,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	}
	local function StyleEB(eb)
		eb:SetFontObject(GameFontHighlight)
		eb:SetTextInsets(4, 4, 0, 0)
		eb:SetBackdrop(EB_BD)
		eb:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
		eb:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
		eb:SetScript("OnEditFocusGained", function()
			this:SetBackdropBorderColor(1, 0.82, 0, 0.8)
		end)
		eb:SetScript("OnEditFocusLost", function()
			this:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
		end)
		eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	end

	-- Zeilen-Pool: pro Zeile ein Frame mit Dropdown-Label/Liste + EditBox
	frame.materialRows = {}
	for i = 1, MAX_MATERIAL_ROWS do
		local row = CreateFrame("Frame", nil, matContainer)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", matContainer, "TOPLEFT", 0, -(i - 1) * (ROW_HEIGHT + ROW_PADDING))
		row:SetPoint("RIGHT", matContainer, "RIGHT", 0, 0)
		row:Hide()

		local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("LEFT", row, "LEFT", 0, 0)
		label:SetJustifyH("LEFT")
		label:SetWidth(200)
		row.label = label

		local eb = CreateFrame("EditBox", "AmptieRaidToolsMatEb" .. i, row)
		eb:SetWidth(56)
		eb:SetHeight(22)
		eb:SetPoint("LEFT", label, "RIGHT", 12, 0)
		eb:SetFrameLevel(row:GetFrameLevel() + 2)
		eb:SetAutoFocus(false)
		eb:SetNumeric(true)
		eb:SetMaxLetters(4)
		StyleEB(eb)
		row.editbox = eb
		row.index = i

		frame.materialRows[i] = row
	end

	local LayoutCustomSection  -- forward declaration; assigned after customContainer is created

	-- Aktualisiert die sichtbaren Material-Zeilen anhand der Spielerklasse
	local function RefreshMaterialRows()
		local pi = AmptieRaidTools_PlayerInfo or {}
		local classRaw = (pi and pi.class) and tostring(pi.class) or ""
		local classToken = LOCALIZED_CLASS_TO_TOKEN[classRaw] or (classRaw ~= "" and string.upper(classRaw) or "")
		local list = CLASS_MATERIALS[classToken]
		local npc = GetDB()
		local mats = npc.materials

		if not list or getn(list) == 0 then
			for i = 1, MAX_MATERIAL_ROWS do
				frame.materialRows[i]:Hide()
			end
			frame.matContainer:SetHeight(0)
			frame.noClassLabel:Show()
			frame.classMaterialsAnchor:ClearAllPoints()
			frame.classMaterialsAnchor:SetPoint("TOPLEFT", frame.noClassLabel, "BOTTOMLEFT", 0, 0)
			return
		end

		if frame.noClassLabel then frame.noClassLabel:Hide() end

		local numVisible = getn(list)
		frame.matContainer:SetHeight(numVisible * (ROW_HEIGHT + ROW_PADDING))
		frame.classMaterialsAnchor:ClearAllPoints()
		frame.classMaterialsAnchor:SetPoint("TOPLEFT", frame.matContainer, "BOTTOMLEFT", 0, 0)

		for i = 1, MAX_MATERIAL_ROWS do
			local row = frame.materialRows[i]
			local item = list[i]
			if item then
				row.label:SetText(item.name .. (item.note or ""))
				local val = mats[item.name]
				if val == nil or val == "" then val = 0 end
				row.editbox:SetText(tostring(val))
				row.editbox.itemName = item.name
				row.editbox:SetScript("OnEditFocusLost", function()
					this:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
					local npc = GetDB()
					local num = tonum(this:GetText())
					if not num or num < 0 then num = 0 end
					npc.materials[this.itemName] = num
					this:SetText(tostring(num))
				end)
				row.editbox:SetScript("OnEnterPressed", function()
					this:ClearFocus()
				end)
				row:Show()
			else
				row:Hide()
			end
		end
	end
	if LayoutCustomSection then LayoutCustomSection() end

	-- === Rogue Poisons (nur für Schurken sichtbar) ===
	local RP_TITLE_H = 16
	local roguePoisonSection = CreateFrame("Frame", nil, content)
	roguePoisonSection:SetPoint("TOPLEFT", classMaterialsAnchor, "BOTTOMLEFT", 0, 0)
	roguePoisonSection:SetWidth(400)
	roguePoisonSection:SetHeight(0)
	frame.roguePoisonSection = roguePoisonSection

	local rpTitle = roguePoisonSection:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	rpTitle:SetPoint("TOPLEFT", roguePoisonSection, "TOPLEFT", 0, -8)
	rpTitle:SetJustifyH("LEFT")
	rpTitle:SetText("Rogue Poisons (crafting materials, target item count)")
	rpTitle:Hide()
	frame.rpTitle = rpTitle

	frame.roguePoisonRows = {}
	local numRoguePoisons = getn(ROGUE_POISONS)
	for i = 1, numRoguePoisons do
		local row = CreateFrame("Frame", nil, roguePoisonSection)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", roguePoisonSection, "TOPLEFT", 0,
			-(8 + RP_TITLE_H + 4) - (i - 1) * (ROW_HEIGHT + ROW_PADDING))
		row:SetWidth(360)
		row:Hide()

		local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("LEFT", row, "LEFT", 0, 0)
		label:SetJustifyH("LEFT")
		label:SetWidth(200)
		label:SetText(ROGUE_POISONS[i].name)
		row.label = label

		local eb = CreateFrame("EditBox", "AmptieRaidToolsRPEb" .. i, row)
		eb:SetWidth(56)
		eb:SetHeight(22)
		eb:SetPoint("LEFT", label, "RIGHT", 12, 0)
		eb:SetFrameLevel(row:GetFrameLevel() + 2)
		eb:SetAutoFocus(false)
		eb:SetNumeric(true)
		eb:SetMaxLetters(4)
		StyleEB(eb)
		eb.poisonName = ROGUE_POISONS[i].name
		row.eb = eb

		frame.roguePoisonRows[i] = row
	end

	local roguePoisonAnchor = CreateFrame("Frame", nil, content)
	roguePoisonAnchor:SetPoint("TOPLEFT", roguePoisonSection, "BOTTOMLEFT", 0, 0)
	roguePoisonAnchor:SetWidth(1)
	roguePoisonAnchor:SetHeight(0)
	frame.roguePoisonAnchor = roguePoisonAnchor

	local function RefreshRoguePoisonRows()
		local pi2 = AmptieRaidTools_PlayerInfo or {}
		local classRaw2 = (pi2 and pi2.class) and tostring(pi2.class) or ""
		local classToken2 = LOCALIZED_CLASS_TO_TOKEN[classRaw2] or (classRaw2 ~= "" and string.upper(classRaw2) or "")
		local npc2 = GetDB()
		if classToken2 == "ROGUE" then
			local sectionH = 8 + RP_TITLE_H + 4 + numRoguePoisons * (ROW_HEIGHT + ROW_PADDING)
			roguePoisonSection:SetHeight(sectionH)
			rpTitle:Show()
			for i = 1, numRoguePoisons do
				local row = frame.roguePoisonRows[i]
				local poison = ROGUE_POISONS[i]
				local target = tonum(npc2.roguePoisons[poison.name]) or 0
				row.eb:SetText(tostring(target))
				row.eb:SetScript("OnEditFocusLost", function()
					this:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
					local npcInner = GetDB()
					local n = tonum(this:GetText()) or 0
					if n < 0 then n = 0 end
					npcInner.roguePoisons[this.poisonName] = n
					this:SetText(tostring(n))
				end)
				row.eb:SetScript("OnEnterPressed", function() this:ClearFocus() end)
				row:Show()
			end
		else
			roguePoisonSection:SetHeight(0)
			rpTitle:Hide()
			for i = 1, numRoguePoisons do
				frame.roguePoisonRows[i]:Hide()
			end
		end
	end
	if LayoutCustomSection then LayoutCustomSection() end
	frame.RefreshRoguePoisonRows = RefreshRoguePoisonRows

	-- === Custom Items (immer unter Klassenmaterial-Block, auch wenn keine Class Materials z. B. bei Krieger) ===
	local customTitle = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	customTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -100)  -- placeholder; corrected by LayoutCustomSection
	customTitle:SetJustifyH("LEFT")
	customTitle:SetText("Custom items (enter item name or link, minimum quantity)")
	frame.customTitle = customTitle

	local clearAllBtn = CreateFrame("Button", nil, content)
	clearAllBtn:SetHeight(20)
	clearAllBtn:SetPoint("LEFT", customTitle, "RIGHT", 12, 0)
	clearAllBtn:SetWidth(70)
	local clearAllLabel = clearAllBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	clearAllLabel:SetPoint("CENTER", clearAllBtn, "CENTER", 0, 0)
	clearAllLabel:SetTextColor(0.95, 0.45, 0.45, 1)
	clearAllLabel:SetText("Clear all")
	clearAllBtn:SetScript("OnClick", function()
		local npc = GetDB()
		for i = table.getn(npc.customItems), 1, -1 do
			table.remove(npc.customItems, i)
		end
		DeferRefreshCustomRows()
	end)
	clearAllBtn:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:SetText("Remove all custom entries")
		GameTooltip:Show()
	end)
	clearAllBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	frame.clearAllBtn = clearAllBtn

	local customContainer = CreateFrame("Frame", nil, content)
	customContainer:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -124)  -- placeholder; corrected by LayoutCustomSection
	customContainer:SetWidth(400)
	customContainer:SetHeight(MAX_CUSTOM_ROWS * (ROW_HEIGHT + ROW_PADDING) + 8)
	customContainer:SetFrameLevel(content:GetFrameLevel() + 1)
	frame.customContainer = customContainer

	-- Layout wie Klassenmaterialien: Label (oder EditBox für neue Zeile) + Anzahl-EditBox + X
	frame.customRows = {}
	for i = 1, MAX_CUSTOM_ROWS do
		local row = CreateFrame("Frame", nil, customContainer)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", customContainer, "TOPLEFT", 0, -(i - 1) * (ROW_HEIGHT + ROW_PADDING))
		row:SetPoint("RIGHT", customContainer, "RIGHT", 0, 0)
		row:SetFrameLevel(customContainer:GetFrameLevel() + i)
		row:Hide()

		-- Itemname als Text (gefüllte Zeilen) – wie Klassenmaterialien
		local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("LEFT", row, "LEFT", 0, 0)
		label:SetJustifyH("LEFT")
		label:SetWidth(220)
		row.label = label

		-- Nur für leere Zeile: EditBox zum Eintippen des neuen Itemnamens (gleiche Optik wie Anzahl-Feld)
		local linkEb = CreateFrame("EditBox", "AmptieRaidToolsCustomLinkEb" .. i, row)
		linkEb:SetWidth(220)
		linkEb:SetHeight(22)
		linkEb:SetPoint("LEFT", row, "LEFT", 0, 0)
		linkEb:SetAutoFocus(false)
		linkEb:SetMaxLetters(256)
		linkEb:SetFrameLevel(row:GetFrameLevel() + 1)
		StyleEB(linkEb)
		row.linkEb = linkEb

		-- Anzahl-EditBox – exakt wie bei Klassenmaterialien (gleicher Name, gleiche Größe/Abstand)
		local countEb = CreateFrame("EditBox", "AmptieRaidToolsCustomEb" .. i, row)
		countEb:SetWidth(56)
		countEb:SetHeight(22)
		countEb:SetPoint("LEFT", label, "RIGHT", 12, 0)
		countEb:SetFrameLevel(row:GetFrameLevel() + 2)
		countEb:SetAutoFocus(false)
		countEb:SetNumeric(true)
		countEb:SetMaxLetters(4)
		StyleEB(countEb)
		row.countEb = countEb

		local delBtn = CreateFrame("Button", nil, row)
		delBtn:SetWidth(18)
		delBtn:SetHeight(18)
		delBtn:SetPoint("LEFT", countEb, "RIGHT", 8, 0)
		local delTex = delBtn:CreateTexture(nil, "OVERLAY")
		delTex:SetAllPoints(delBtn)
		delTex:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
		delBtn:SetScript("OnClick", function()
			local idx = this.removeIndex
			if not idx then idx = this:GetParent().customIndex end
			if idx and frame.RemoveCustomItem then
				frame.RemoveCustomItem(idx)
			end
		end)
		delBtn:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_LEFT")
			GameTooltip:SetText("Remove")
			GameTooltip:Show()
		end)
		delBtn:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row.delBtn = delBtn
		row.index = i
		row.label:Show()
		row.linkEb:Hide()

		frame.customRows[i] = row
	end

	-- Positions the custom section (title + container) relative to content:TOPLEFT,
	-- bypassing the anchor chain so it always ends up below the visible class/poison rows.
	LayoutCustomSection = function()
		-- matTitle starts at content Y=-8, height ~16px
		local y = -(8 + 16)
		if frame.noClassLabel and frame.noClassLabel:IsShown() then
			-- noClassLabel is shown: gap(4) + label height(~16)
			y = y - (4 + 16)
		else
			-- matContainer follows with gap(8) + its height
			y = y - 8 - (frame.matContainer:GetHeight() or 0)
		end
		-- rogue poison section (height 0 for non-rogues)
		y = y - (frame.roguePoisonSection:GetHeight() or 0)
		-- gap before custom title
		y = y - 24
		frame.customTitle:ClearAllPoints()
		frame.customTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		-- customContainer: customTitle height(~16) + gap(4)
		frame.customContainer:ClearAllPoints()
		frame.customContainer:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y - 20)
	end

	-- Prüft, ob Text wie ein Item-Link aussieht
	local function IsItemLink(text)
		return text and strfind(text, "|Hitem:%d+:")
	end

	-- Speichert einen Eintrag (Link oder Itemname) und zeigt danach eine neue leere Zeile
	local function SaveCustomRow(itemText, countText)
		local trimmed = itemText and string.gsub(itemText, "^%s*(.-)%s*$", "%1") or ""
		if trimmed == "" then return false end
		local n = tonum(countText)
		if not n or n < 1 then n = 1 end
		local npc = GetDB()
		if IsItemLink(trimmed) then
			local id = GetItemIdFromLink(trimmed)
			local name = GetItemNameFromLink(trimmed)
			if id and name then
				table.insert(npc.customItems, { id = id, name = name, count = n })
				return true
			end
		end
		-- Nur Itemname (wird beim Händler per Namen abgeglichen)
		table.insert(npc.customItems, { name = trimmed, count = n })
		return true
	end

	function frame.RemoveCustomItem(index)
		local npc = GetDB()
		local list = npc.customItems
		if not list or index < 1 or index > table.getn(list) then return end
		table.remove(list, index)
		DeferRefreshCustomRows()
	end

	-- Einmalige Aktualisierung im nächsten Frame (vermeidet C-Stack-Overflow durch Fokus-Events)
	local deferFrame = CreateFrame("Frame", nil, frame)
	deferFrame:Hide()
	deferFrame:SetScript("OnUpdate", function()
		this:SetScript("OnUpdate", nil)
		this:Hide()
		RefreshCustomRows()
	end)
	function DeferRefreshCustomRows()
		deferFrame:Show()
		deferFrame:SetScript("OnUpdate", function()
			this:SetScript("OnUpdate", nil)
			this:Hide()
			RefreshCustomRows()
		end)
	end

	function RefreshCustomRows()
		local npc = GetDB()
		local list = npc.customItems
		local num = getn(list)
		for i = 1, MAX_CUSTOM_ROWS do
			local row = frame.customRows[i]
			if i <= num + 1 then
				if i <= num then
					local entry = list[i]
					-- Gefüllte Zeile: Itemname als Label (wie Klassenmaterialien), Schriftfarbe explizit hell
					row.label:SetText(entry.name or "")
					row.label:SetTextColor(1, 0.82, 0, 1)
					row.label:Show()
					row.linkEb:Hide()
					row.linkEb:SetScript("OnEditFocusLost", nil)
					row.linkEb:SetScript("OnTextChanged", nil)
					row.linkEb:SetText("")
					row.countEb:ClearAllPoints()
					row.countEb:SetPoint("LEFT", row.label, "RIGHT", 12, 0)
					row.countEb:SetScript("OnEditFocusLost", nil)
					row.countEb:SetText(tostring(entry.count or 1))
					row.countEb.entryIndex = i
					row.countEb:SetScript("OnEditFocusLost", function()
						this:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
						local idx = this.entryIndex
						if idx and list[idx] then
							local n = tonum(this:GetText())
							if n and n >= 0 then list[idx].count = n end
							this:SetText(tostring(list[idx].count))
						end
					end)
					row.countEb:SetScript("OnEnterPressed", function()
						this:ClearFocus()
					end)
					row.delBtn.removeIndex = i
					row.delBtn:Show()
					row.customIndex = i
				else
					-- Leere Zeile: EditBox für neuen Itemnamen (gleiche Optik wie Anzahl-Feld)
					row.label:Hide()
					row.linkEb:Show()
					row.linkEb:SetScript("OnEditFocusLost", nil)
					row.linkEb:SetText("")
					row.linkEb.entryIndex = nil
					row.countEb:ClearAllPoints()
					row.countEb:SetPoint("LEFT", row.linkEb, "RIGHT", 12, 0)
					row.countEb:SetScript("OnEditFocusLost", nil)
					row.countEb:SetText("5")
					row.countEb.entryIndex = nil
					row.linkEb:SetScript("OnEditFocusLost", function()
						this:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
						local txt = this:GetText()
						if not txt or txt == "" then return end
						local countTxt = row.countEb:GetText()
						if SaveCustomRow(txt, countTxt) then
							DeferRefreshCustomRows()
						end
					end)
					row.countEb:SetScript("OnEnterPressed", function()
						row.linkEb:ClearFocus()
					end)
					row.delBtn.removeIndex = nil
					row.delBtn:Hide()
					row.customIndex = nil
				end
				row:Show()
			else
				row:Hide()
			end
		end
	end

	-- Slider (same design as Auto-Buffs)
	local npcSlider = CreateFrame("Slider", "ART_NPC_Slider", frame)
	npcSlider:SetOrientation("VERTICAL")
	npcSlider:SetWidth(12)
	npcSlider:SetPoint("TOPRIGHT",    npcSF, "TOPRIGHT",    18, 0)
	npcSlider:SetPoint("BOTTOMRIGHT", npcSF, "BOTTOMRIGHT", 18, 0)
	local npcThumb = npcSlider:CreateTexture(nil, "OVERLAY")
	npcThumb:SetWidth(10)
	npcThumb:SetHeight(24)
	npcThumb:SetTexture(0.5, 0.5, 0.55, 0.9)
	npcSlider:SetThumbTexture(npcThumb)
	local npcTrack = npcSlider:CreateTexture(nil, "BACKGROUND")
	npcTrack:SetAllPoints(npcSlider)
	npcTrack:SetTexture(0.12, 0.12, 0.15, 0.8)
	npcSlider:SetMinMaxValues(0, math.max(content:GetHeight() - NPC_SF_H, 0))
	npcSlider:SetValueStep(20)
	npcSlider:SetValue(0)
	npcSlider:SetScript("OnValueChanged", function()
		SetNpcScroll(this:GetValue())
	end)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function()
		local delta = arg1
		local maxScroll = math.max(content:GetHeight() - NPC_SF_H, 0)
		local newVal = npcScrollOff - delta * 30
		if newVal < 0        then newVal = 0        end
		if newVal > maxScroll then newVal = maxScroll end
		npcSlider:SetValue(newVal)
	end)

	frame:SetScript("OnShow", function()
		-- Get actual SF height now that the frame is laid out
		local sfH = npcSF:GetHeight()
		if sfH and sfH > 50 then NPC_SF_H = sfH end
		RefreshMaterialRows()
		RefreshRoguePoisonRows()
		RefreshCustomRows()
		LayoutCustomSection()
		frame.customTitle:Show()
		frame.customContainer:Show()
		npcSlider:SetMinMaxValues(0, math.max(content:GetHeight() - NPC_SF_H, 0))
		npcSlider:SetValue(0)
		SetNpcScroll(0)
	end)

	RefreshMaterialRows()
	RefreshRoguePoisonRows()
	RefreshCustomRows()

	frame.contentHeight = 820
	frame.noOuterScroll = true
	AmptieRaidTools_RegisterComponent("npctrading", frame)
end

-- Event-Frame: Beim Öffnen eines Händlers graue Items verkaufen und Reagenzien nachkaufen
local npcEventFrame = CreateFrame("Frame", "AmptieRaidToolsNPCTradingEventFrame", UIParent)
npcEventFrame:RegisterEvent("MERCHANT_SHOW")
npcEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
npcEventFrame:SetScript("OnEvent", function()
	local evt = event
	if evt == "PLAYER_ENTERING_WORLD" then
		-- Remove class material entries that don't belong to the current class
		local _, playerClass = UnitClass("player")
		playerClass = playerClass and string.upper(playerClass) or ""
		local npc = GetDB()

		-- Build set of all valid material names for this class
		local validMats = {}
		for cls, list in pairs(CLASS_MATERIALS) do
			if cls == playerClass then
				for i = 1, getn(list) do
					validMats[list[i].name] = true
				end
			end
		end
		-- Remove materials not belonging to this class
		for itemName in pairs(npc.materials) do
			if not validMats[itemName] then
				npc.materials[itemName] = nil
			end
		end
		-- Rogue poisons: wipe if not a Rogue
		if playerClass ~= "ROGUE" and npc.roguePoisons then
			for k in pairs(npc.roguePoisons) do
				npc.roguePoisons[k] = nil
			end
		end
		return
	end
	if evt == "MERCHANT_SHOW" then
		local npc = GetDB()
		if npc.autoSellGrey then
			SellGreyItems()
		end
		if npc.autoRepair and CanMerchantRepair and CanMerchantRepair() then
			RepairAllItems()
		end
		BuyReagents()
		BuyRoguePoisonMaterials()
	end
end)
