-- amptieRaidTools - Main Frame, Navbar, Minimap-Button (Vanilla 1.12 / Lua 5.0)

local getn    = table.getn
local tinsert = table.insert
local floor   = math.floor

amptieRaidToolsDB = amptieRaidToolsDB or {}
local DB = amptieRaidToolsDB

if DB.point == nil then DB.point = "CENTER" end
if DB.x == nil then DB.x = 0 end
if DB.y == nil then DB.y = 0 end
if DB.minimapAngle == nil then DB.minimapAngle = 90 end

local FRAME_WIDTH   = 780
local FRAME_HEIGHT  = 570
local NAV_WIDTH     = 140
local TITLE_HEIGHT  = 28
local NAV_ITEM_HEIGHT = 24
local NAV_PADDING   = 6

local BACKDROP_MAIN = {
	bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local BACKDROP_NAV = {
	bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
	tile = true, tileSize = 16, edgeSize = 0,
	insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

local NAV_ITEMS = {
	{ header=true,  label="Character"    },
	{ id="home",         label="Overview"     },
	{ id="barprofiles",  label="Bar Profiles" },
	{ id="autobuffs",    label="Auto-Buffs"   },
	{ id="autorolls",    label="Auto-Rolls"   },
	{ header=true,  label="Raids"        },
	{ id="roleroster",   label="Raid Roles"   },
	{ id="raidassists",  label="Raid Assist"  },
	{ id="raidcds",      label="Raid CDs"     },
	{ id="raidsetups",   label="Raid Setups"  },
	{ header=true,  label="Rules"        },
	{ id="itemchecks",   label="Item Checks"  },
	{ id="buffchecks",   label="Buff Checks"  },
	{ id="classbuffs",   label="Class Buffs"  },
	{ id="lootrules",    label="Loot Rules"   },
	{ header=true,  label="Others"       },
	{ id="npctrading",   label="NPC Trading"  },
	{ id="qolsettings",  label="QoL Settings" },
}

local mainFrame  = nil
local navFrame   = nil
local bodyFrame  = nil
local currentNavId = "home"
local registeredComponents = {}

-- ============================================================
-- Frame öffnen/schließen
-- ============================================================
local function MainFrame_Show()
	if mainFrame then mainFrame:Show() end
end
local function MainFrame_Hide()
	if mainFrame then mainFrame:Hide() end
end
local function MainFrame_Toggle()
	if mainFrame and mainFrame:IsShown() then
		MainFrame_Hide()
	else
		MainFrame_Show()
	end
end

-- ============================================================
-- Komponente anzeigen
-- ============================================================
function AmptieRaidTools_ShowComponent(componentId)
	currentNavId = componentId or "home"
	if not bodyFrame then return end
	for id, frame in pairs(registeredComponents) do
		if id == currentNavId then
			frame:SetFrameLevel(bodyFrame:GetFrameLevel() + 10)
			frame:Show()
		else
			frame:Hide()
		end
	end
	if navFrame and navFrame.buttons then
		for i = 1, getn(navFrame.buttons) do
			local btn = navFrame.buttons[i]
			if btn and btn.navId then
				if btn.navId == currentNavId then
					btn:SetBackdropColor(0.22, 0.22, 0.25, 0.9)
					if btn.label then btn.label:SetTextColor(1, 0.82, 0, 1) end
				else
					btn:SetBackdropColor(0.12, 0.12, 0.15, 0.85)
					if btn.label then btn.label:SetTextColor(0.85, 0.85, 0.85, 1) end
				end
			end
		end
	end
end

-- ============================================================
-- Komponente registrieren
-- Panel muss bereits als Kind von body erstellt worden sein.
-- Kein Re-Parenting, kein SetAllPoints hier.
-- ============================================================
function AmptieRaidTools_RegisterComponent(componentId, frame)
	frame.componentId = componentId
	registeredComponents[componentId] = frame
	if componentId ~= currentNavId then
		frame:Hide()
	end
end

-- ============================================================
-- Hauptfenster
-- ============================================================
local function CreateCloseButton(parent)
	local btn = CreateFrame("Button", "AmptieRaidToolsCloseButton", parent, "UIPanelCloseButton")
	btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -6)
	btn:SetScript("OnClick", function() MainFrame_Hide() end)
	return btn
end

local function CreateMainFrame()
	local f = CreateFrame("Frame", "AmptieRaidToolsMainFrame", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetWidth(FRAME_WIDTH)
	f:SetHeight(FRAME_HEIGHT)
	f:SetPoint(DB.point, UIParent, DB.point, DB.x, DB.y)
	f:SetBackdrop(BACKDROP_MAIN)
	f:SetBackdropColor(0.08, 0.08, 0.1, 0.92)
	f:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
	tinsert(UISpecialFrames, "AmptieRaidToolsMainFrame")

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
	title:SetText("amptieRaidTools")
	title:SetTextColor(1, 0.82, 0, 1)

	CreateCloseButton(f)

	-- Navbar
	local nav = CreateFrame("Frame", nil, f)
	nav:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -TITLE_HEIGHT - 4)
	nav:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 6)
	nav:SetWidth(NAV_WIDTH)
	nav:SetBackdrop(BACKDROP_NAV)
	nav:SetBackdropColor(0.1, 0.1, 0.12, 0.95)
	nav.buttons = {}

	local numItems = getn(NAV_ITEMS)
	local yOff = NAV_PADDING
	local firstHeader = true
	for i = 1, numItems do
		local item = NAV_ITEMS[i]
		if item.header then
			-- Extra gap before all but the first header
			if not firstHeader then
				yOff = yOff + 6
			end
			firstHeader = false
			local hdr = nav:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			hdr:SetPoint("TOPLEFT", nav, "TOPLEFT", NAV_PADDING + 2, -yOff)
			hdr:SetPoint("RIGHT", nav, "RIGHT", -NAV_PADDING, 0)
			hdr:SetJustifyH("LEFT")
			hdr:SetText(string.upper(item.label))
			hdr:SetTextColor(0.6, 0.5, 0.2, 1)
			yOff = yOff + 16 + 2
		else
			local btn = CreateFrame("Button", "AmptieRaidToolsNav" .. item.id, nav)
			btn:SetHeight(NAV_ITEM_HEIGHT)
			btn:SetPoint("TOPLEFT", nav, "TOPLEFT", NAV_PADDING, -yOff)
			btn:SetPoint("RIGHT", nav, "RIGHT", -NAV_PADDING, 0)
			btn:SetBackdrop(BACKDROP_NAV)
			btn.navId = item.id
			if item.id == currentNavId then
				btn:SetBackdropColor(0.22, 0.22, 0.25, 0.9)
			else
				btn:SetBackdropColor(0.12, 0.12, 0.15, 0.85)
			end
			btn:SetScript("OnClick", function()
				AmptieRaidTools_ShowComponent(this.navId)
			end)
			btn:SetScript("OnEnter", function()
				if this.navId ~= currentNavId then
					this:SetBackdropColor(0.18, 0.18, 0.22, 0.9)
				end
			end)
			btn:SetScript("OnLeave", function()
				if this.navId == currentNavId then
					this:SetBackdropColor(0.22, 0.22, 0.25, 0.9)
				else
					this:SetBackdropColor(0.12, 0.12, 0.15, 0.85)
				end
			end)
			local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			label:SetPoint("LEFT", btn, "LEFT", 10, 0)
			label:SetJustifyH("LEFT")
			label:SetText(item.label)
			if item.id == currentNavId then
				label:SetTextColor(1, 0.82, 0, 1)
			else
				label:SetTextColor(0.85, 0.85, 0.85, 1)
			end
			btn.label = label
			tinsert(nav.buttons, btn)
			yOff = yOff + NAV_ITEM_HEIGHT + 2
		end
	end

	-- Body
	local body = CreateFrame("Frame", "AmptieRaidToolsBody", f)
	body:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0)
	body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)

	-- bodyFrame jetzt setzen, damit RegisterComponent funktioniert
	bodyFrame = body

	-- Alle Komponenten initialisieren (body als direkter Parent)
	if AmptieRaidTools_InitHome      then AmptieRaidTools_InitHome(body)      end
	if AmptieRaidTools_InitNPCTrading then AmptieRaidTools_InitNPCTrading(body) end
	if AmptieRaidTools_InitAutoRolls  then AmptieRaidTools_InitAutoRolls(body)  end
	if AmptieRaidTools_InitAutoBuffs  then AmptieRaidTools_InitAutoBuffs(body)  end
	if AmptieRaidTools_InitBarProfiles then AmptieRaidTools_InitBarProfiles(body) end
	if AmptieRaidTools_InitRaidCDs    then AmptieRaidTools_InitRaidCDs(body)    end
	if AmptieRaidTools_InitRoleRoster  then AmptieRaidTools_InitRoleRoster(body)  end
	if AmptieRaidTools_InitRaidSetups   then AmptieRaidTools_InitRaidSetups(body)   end
	if AmptieRaidTools_InitRaidAssists  then AmptieRaidTools_InitRaidAssists(body)  end
	if AmptieRaidTools_InitMTOverlay    then AmptieRaidTools_InitMTOverlay()        end
	if AmptieRaidTools_InitItemChecks   then AmptieRaidTools_InitItemChecks(body)   end
	if AmptieRaidTools_InitBuffChecks   then AmptieRaidTools_InitBuffChecks(body)   end
	if AmptieRaidTools_InitClassBuffs   then AmptieRaidTools_InitClassBuffs(body)   end
	if AmptieRaidTools_InitLootRules    then AmptieRaidTools_InitLootRules(body)    end
	if AmptieRaidTools_InitQoLSettings  then AmptieRaidTools_InitQoLSettings(body)  end

	-- Drag
	f:SetScript("OnDragStart", function() this:StartMoving() end)
	f:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
		local point, _, rpoint, x, y = this:GetPoint()
		DB.point = point
		DB.x = x
		DB.y = y
	end)

	mainFrame = f
	navFrame  = nav
	f:Hide()
	return f
end

-- ============================================================
-- Minimap-Button
-- ============================================================
local MINIMAP_RADIUS = 78

local function UpdateMinimapButtonPosition()
	if not AmptieRaidToolsMinimapButton then return end
	local angle = (DB.minimapAngle or 90) * 3.14159265358979 / 180
	local x = MINIMAP_RADIUS * math.cos(angle)
	local y = MINIMAP_RADIUS * math.sin(angle)
	AmptieRaidToolsMinimapButton:ClearAllPoints()
	AmptieRaidToolsMinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CreateMinimapButton()
	if AmptieRaidToolsMinimapButton then
		UpdateMinimapButtonPosition()
		AmptieRaidToolsMinimapButton:Show()
		return
	end
	local mb = CreateFrame("Button", "AmptieRaidToolsMinimapButton", Minimap)
	mb:SetWidth(31)
	mb:SetHeight(31)
	mb:SetFrameStrata("MEDIUM")
	mb:SetFrameLevel(8)
	mb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

	local border = mb:CreateTexture(nil, "OVERLAY")
	border:SetWidth(53)
	border:SetHeight(53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT", mb, "TOPLEFT", 0, 0)

	local icon = mb:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture("Interface\\AddOns\\amptieRaidTools\\Textures\\minimap_icon")
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	icon:SetWidth(20)
	icon:SetHeight(20)
	icon:SetPoint("TOPLEFT", mb, "TOPLEFT", 6, -5)

	mb._dragging = false

	mb:SetScript("OnMouseDown", function()
		if arg1 == "LeftButton" and IsShiftKeyDown() then
			this._dragging = true
		end
	end)
	mb:SetScript("OnMouseUp", function()
		if arg1 == "LeftButton" then
			this._dragging = false
		end
	end)
	mb:SetScript("OnUpdate", function()
		if not this._dragging then return end
		local scale = UIParent:GetEffectiveScale()
		local mx, my = GetCursorPosition()
		mx = mx / scale
		my = my / scale
		local mmx, mmy = Minimap:GetCenter()
		local dx = mx - mmx
		local dy = my - mmy
		local angle = math.atan2(dy, dx) * 180 / 3.14159265358979
		DB.minimapAngle = angle
		UpdateMinimapButtonPosition()
	end)
	mb:SetScript("OnClick", function()
		if arg1 == "LeftButton" and not IsShiftKeyDown() then
			MainFrame_Toggle()
		end
	end)
	mb:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:SetText("amptieRaidTools\nLeft-click: Open/Close\nShift+drag: Move")
		GameTooltip:Show()
	end)
	mb:SetScript("OnLeave", function() GameTooltip:Hide() end)

	UpdateMinimapButtonPosition()
	mb:Show()
end

-- ============================================================
-- Hintergrund-Updater (Spec alle 5s)
-- ============================================================
local specRefreshInterval = 5
local specRefreshTimer    = 0
local updaterFrame = CreateFrame("Frame", "AmptieRaidToolsUpdaterFrame", UIParent)
updaterFrame:SetScript("OnUpdate", function()
	local dt = arg1
	if not dt or dt < 0 then dt = 0 end
	specRefreshTimer = specRefreshTimer + dt
	if specRefreshTimer >= specRefreshInterval then
		specRefreshTimer = 0
		if AmptieRaidTools_RefreshSpecInBackground then
			AmptieRaidTools_RefreshSpecInBackground()
		end
	end
end)

-- ============================================================
-- Shared UI helper: custom checkbox
-- ============================================================
-- Returns a 16×16 Button that behaves like a checkbox.
-- GetChecked()  → true/false
-- SetChecked(v) → accepts true/false/1/0/nil
-- Assign cb.userOnClick = function() … end for the click callback.
-- An optional label FontString is created to the right if labelText is given.
local ART_CB_BD = {
	bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 8, edgeSize = 8,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
}
function ART_CreateCheckbox(parent, labelText)
	local checked = false

	local cb = CreateFrame("Button", nil, parent)
	cb:SetWidth(16)
	cb:SetHeight(16)
	cb:SetBackdrop(ART_CB_BD)
	cb:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

	-- Checkmark texture (WoW built-in, shown when checked)
	local checkTex = cb:CreateTexture(nil, "OVERLAY")
	checkTex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	checkTex:SetPoint("TOPLEFT",     cb, "TOPLEFT",     1, -1)
	checkTex:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -1,  1)
	checkTex:Hide()

	-- Optional label to the right of the box
	if labelText and labelText ~= "" then
		local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		lbl:SetPoint("LEFT", cb, "RIGHT", 5, 0)
		lbl:SetText(labelText)
	end

	local function updateVisual()
		if checked then
			cb:SetBackdropColor(0.18, 0.14, 0.02, 0.95)
			cb:SetBackdropBorderColor(1, 0.82, 0, 1)
			checkTex:Show()
		else
			cb:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
			cb:SetBackdropBorderColor(0.28, 0.28, 0.33, 1)
			checkTex:Hide()
		end
	end
	updateVisual()

	cb.GetChecked = function() return checked end
	cb.SetChecked = function(_, val)
		checked = (val ~= nil and val ~= false and val ~= 0)
		updateVisual()
	end

	cb:SetScript("OnClick", function()
		checked = not checked
		updateVisual()
		if cb.userOnClick then cb.userOnClick() end
	end)

	return cb
end

-- ============================================================
-- Event-Frame
-- ============================================================
local eventFrame = CreateFrame("Frame", "AmptieRaidToolsEventFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
	local evt = event
	local a1  = arg1
	if evt == "ADDON_LOADED" and a1 == "amptieRaidTools" then
		eventFrame:UnregisterEvent("ADDON_LOADED")
		CreateMainFrame()
		if AmptieRaidTools_InitPlayerInfo then AmptieRaidTools_InitPlayerInfo() end
		AmptieRaidTools_ShowComponent("home")
		SLASH_AMPTIERAIDTOOLS1 = "/art"
		SLASH_AMPTIERAIDTOOLS2 = "/amptieraidtools"
		SlashCmdList["AMPTIERAIDTOOLS"] = function(input)
			local cmd = input and string.lower(input) or ""
			-- trim leading/trailing whitespace
			local _, _, trimmed = string.find(cmd, "^%s*(.-)%s*$")
			cmd = trimmed or cmd
			if cmd == "council show" or cmd == "council" then
				if AmptieRaidTools_CouncilShow then AmptieRaidTools_CouncilShow() end
			else
				MainFrame_Toggle()
			end
		end
		DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[amptieRaidTools]|r Loaded. /art or Minimap icon to open.")
	elseif evt == "VARIABLES_LOADED" or evt == "PLAYER_LOGIN" then
		CreateMinimapButton()
	end
end)
