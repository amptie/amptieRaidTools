-- amptieRaidTools - Main Frame, Navbar, Minimap-Button (Vanilla 1.12 / Lua 5.0)

local getn    = table.getn
local tinsert = table.insert
local floor   = math.floor

amptieRaidToolsDB = amptieRaidToolsDB or {}
local DB = amptieRaidToolsDB

-- ============================================================
-- Global zone definitions (shared across all components)
-- ============================================================
ART_ZONES = {
    { key="mc",      label="Molten Core",        zone="Molten Core" },
    { key="ony",     label="Onyxia's Lair",      zone="Onyxia's Lair" },
    { key="bwl",     label="Blackwing Lair",      zone="Blackwing Lair" },
    { key="zg",      label="Zul'Gurub",           zone="Zul'Gurub" },
    { key="tmh",     label="Timbermaw Hold",      zone="Timbermaw Hold" },
    { key="aq20",    label="Ruins of AQ",         zone="Ruins of Ahn'Qiraj" },
    { key="aq40",    label="Temple of AQ",        zone="Temple of Ahn'Qiraj", zones={"Ahn'Qiraj"} },
    { key="naxx",    label="Naxxramas",           zone="Naxxramas", zones={"The Upper Necropolis"} },
    { key="esanc",   label="Emerald Sanctum",     zone="Emerald Sanctum" },
    { key="kara10",  label="Karazhan (10-man)",   zone="The Tower of Karazhan", zones={"Tower of Karazhan","The Rock of Desolation"}, maxRaid=14 },
    { key="kara40",  label="Karazhan (40-man)",   zone="The Tower of Karazhan", zones={"Tower of Karazhan","The Rock of Desolation"}, minRaid=15 },
}

ART_PVP_ZONES = {
    ["Arathi Basin"]           = true,
    ["Warsong Gulch"]          = true,
    ["Alterac Valley"]         = true,
    ["Thorn Gorge"]            = true,
    ["Bloodring Arena"]        = true,
}

-- Returns the zone key for the player's current location
-- "mc", "ony", ..., "dungeon", "pvp", "world"
function ART_GetCurrentZoneKey()
    local zone = GetRealZoneText()
    local n    = GetNumRaidMembers() or 0
    -- Check known raid zones
    if zone then
        for i = 1, getn(ART_ZONES) do
            local z = ART_ZONES[i]
            if z.zone then
                local match = (z.zone == zone)
                if not match and z.zones then
                    for j = 1, getn(z.zones) do
                        if z.zones[j] == zone then match = true; break end
                    end
                end
                if match then
                    if (not z.minRaid or n >= z.minRaid) and (not z.maxRaid or n <= z.maxRaid) then
                        return z.key
                    end
                end
            end
        end
    end
    -- Check PvP battlegrounds
    if zone and ART_PVP_ZONES[zone] then return "pvp" end
    -- Instance but not a known raid/pvp = dungeon
    if IsInInstance() == 1 then return "dungeon" end
    return "world"
end

if DB.point == nil then DB.point = "CENTER" end
if DB.x == nil then DB.x = 0 end
if DB.y == nil then DB.y = 0 end
-- minimapX/minimapY: CENTER offset from UIParent CENTER. nil = place near Minimap on first use.
if DB.minimapX == nil then DB.minimapX = nil end

local FRAME_WIDTH   = 780
local FRAME_HEIGHT  = 570
local NAV_WIDTH     = 140
local TITLE_HEIGHT  = 28
local NAV_ITEM_HEIGHT = 24
local NAV_PADDING   = 6

local BACKDROP_MAIN = {
	bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
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
	{ id="myconsumes",   label="My Consumes"  },
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

-- Scroll state (set in CreateMainFrame, used by ShowComponent)
local bodyScrollFrame = nil
local bodyScrollBar   = nil
local SCROLL_CHILD_H  = 900   -- tall enough for any settings panel
local SCROLLBAR_W     = 16

-- ============================================================
-- Frame öffnen/schließen
-- ============================================================
-- ============================================================
-- Global popup/dropdown registry
-- Components call ART_RegisterPopup(frame) to register any
-- floating frame (dropdown, popup) that should auto-close when
-- the main window is hidden.
-- ============================================================
local artPopupRegistry = {}
function ART_RegisterPopup(frame)
	if frame then
		tinsert(artPopupRegistry, frame)
	end
end

local function ART_CloseAllPopups()
	for i = 1, getn(artPopupRegistry) do
		local f = artPopupRegistry[i]
		if f and f:IsShown() then f:Hide() end
	end
	-- Loot Rules vote popups have their own manager
	if CloseVotePopup then CloseVotePopup() end
end

local function MainFrame_Show()
	if mainFrame then mainFrame:Show() end
end
local function MainFrame_Hide()
	ART_CloseAllPopups()
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
	-- Reset scroll to top on every tab switch
	if bodyScrollFrame then bodyScrollFrame:SetVerticalScroll(0) end
	if bodyScrollBar   then bodyScrollBar:SetValue(0) end
	for id, frame in pairs(registeredComponents) do
		if id == currentNavId then
			frame:SetFrameLevel(bodyFrame:GetFrameLevel() + 10)
			frame:Show()
			-- Hide outer scrollbar for panels that manage their own scrolling
			if bodyScrollBar then
				if frame.noOuterScroll then
					bodyScrollBar:Hide()
				else
					bodyScrollBar:Show()
				end
			end
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
	f:SetBackdropColor(0.03, 0.03, 0.04, 0.9)
	f:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
	tinsert(UISpecialFrames, "AmptieRaidToolsMainFrame")
	f:SetScript("OnHide", function()
		ART_CloseAllPopups()
	end)

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

	-- Body: ScrollFrame viewport
	local bodyScroll = CreateFrame("ScrollFrame", "AmptieRaidToolsBodyScroll", f)
	bodyScroll:SetPoint("TOPLEFT",     nav, "TOPRIGHT",        8, 0)
	bodyScroll:SetPoint("BOTTOMRIGHT", f,   "BOTTOMRIGHT", -(8 + SCROLLBAR_W + 4), 8)
	bodyScroll:EnableMouseWheel(true)

	-- Scrollable content frame (all component panels go here)
	local bodyW = FRAME_WIDTH - NAV_WIDTH - NAV_PADDING - 8 - (8 + SCROLLBAR_W + 4)
	local body = CreateFrame("Frame", "AmptieRaidToolsBody", bodyScroll)
	body:SetWidth(bodyW)
	body:SetHeight(SCROLL_CHILD_H)
	bodyScroll:SetScrollChild(body)

	-- Vertical scrollbar (modern style: solid track + solid thumb)
	local VIEWPORT_H = FRAME_HEIGHT - TITLE_HEIGHT - 4 - 8
	local MAX_SCROLL = SCROLL_CHILD_H - VIEWPORT_H

	local sb = CreateFrame("Slider", "AmptieRaidToolsScrollBar", f)
	sb:SetOrientation("VERTICAL")
	sb:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    -8, -(TITLE_HEIGHT + 4))
	sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
	sb:SetWidth(SCROLLBAR_W)
	local sbTrack = sb:CreateTexture(nil, "BACKGROUND")
	sbTrack:SetAllPoints(sb)
	sbTrack:SetTexture(0.12, 0.12, 0.15, 0.8)
	local sbThumb = sb:CreateTexture(nil, "OVERLAY")
	sbThumb:SetWidth(10)
	sbThumb:SetHeight(24)
	sbThumb:SetTexture(0.5, 0.5, 0.55, 0.9)
	sb:SetThumbTexture(sbThumb)
	sb:SetMinMaxValues(0, MAX_SCROLL)
	sb:SetValue(0)
	sb:SetScript("OnValueChanged", function()
		bodyScroll:SetVerticalScroll(this:GetValue())
	end)

	bodyScroll:SetScript("OnMouseWheel", function()
		local delta  = arg1
		local newVal = math.max(0, math.min(MAX_SCROLL,
		                bodyScroll:GetVerticalScroll() - delta * 40))
		bodyScroll:SetVerticalScroll(newVal)
		sb:SetValue(newVal)
	end)

	bodyScrollFrame = bodyScroll
	bodyScrollBar   = sb

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
	if AmptieRaidTools_InitMyConsumes   then AmptieRaidTools_InitMyConsumes(body)   end
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
-- Minimap-Button  (free-floating, drag anywhere on screen)
-- ============================================================
local function CreateGameMenuButton()
	if not GameMenuFrame then return end
	local btn = CreateFrame("Button", "GameMenuButtonAmptieRaidTools", GameMenuFrame, "GameMenuButtonTemplate")
	btn:SetText("amptieRaidTools")

	-- Style: match pfUI if installed
	if pfUI and pfUI.api and pfUI.api.SkinButton then
		pfUI.api.SkinButton(btn)
		btn:SetText("|cFFFFD100a|rmptie|cFFFFD100R|raid|cFFFFD100T|rools")
	end

	btn:SetScript("OnClick", function()
		MainFrame_Toggle()
		HideUIPanel(GameMenuFrame)
	end)

	if GameMenuButtonPFUI then
		-- pfUI + TurtleWoW: pfUI's turtle-wow.lua runs a one-shot OnUpdate (after
		-- PLAYER_LOGIN) that sets GameMenuButtonShop at TOP -66 for its 2 buttons.
		-- We hook GameMenuFrame OnShow so our repositioning always runs AFTER that,
		-- guaranteeing the correct final state whenever the ESC menu opens.
		GameMenuFrame:SetHeight(GameMenuFrame:GetHeight() + 22)

		local origOnShow = GameMenuFrame:GetScript("OnShow")
		GameMenuFrame:SetScript("OnShow", function()
			if origOnShow then origOnShow() end

			-- Rebuild top chain: aRT → pfUI Config → pfUI AddOns
			btn:ClearAllPoints()
			btn:SetPoint("TOP", GameMenuFrame, "TOP", 0, -10)

			GameMenuButtonPFUI:ClearAllPoints()
			GameMenuButtonPFUI:SetPoint("TOP", btn, "BOTTOM", 0, -1)

			if GameMenuButtonPFUIAddOns then
				GameMenuButtonPFUIAddOns:ClearAllPoints()
				GameMenuButtonPFUIAddOns:SetPoint("TOP", GameMenuButtonPFUI, "BOTTOM", 0, -1)
			end

			-- Push Shop (Donation Rewards) below the 3-button block.
			-- pfUI calculated it for 2 buttons; we now have 3, so move it down 22px.
			-- GameMenuButtonOptions is anchored to Shop by pfUI (turtle-wow.lua),
			-- so the entire lower block follows automatically.
			if GameMenuButtonShop then
				local lastBtn = GameMenuButtonPFUIAddOns or GameMenuButtonPFUI or btn
				GameMenuButtonShop:ClearAllPoints()
				GameMenuButtonShop:SetPoint("TOP", lastBtn, "BOTTOM", 0, -22)
			end
		end)
	else
		-- No pfUI: insert above Continue
		local p, r, rp, x, y = GameMenuButtonContinue:GetPoint()
		btn:SetPoint(p, r, rp, x, y)
		GameMenuButtonContinue:SetPoint(p, btn, "BOTTOM", 0, -1)
		GameMenuFrame:SetHeight(GameMenuFrame:GetHeight() + 22)
	end
end

local function CreateMinimapButton()
	if AmptieRaidToolsMinimapButton then
		AmptieRaidToolsMinimapButton:Show()
		return
	end
	-- Parent = Minimap so pfUI's addonbuttons scan (FindButtons(Minimap)) can detect it.
	-- Positioning still uses cross-parent UIParent anchors for free placement anywhere.
	local mb = CreateFrame("Button", "AmptieRaidToolsMinimapButton", Minimap)
	mb:SetWidth(31)
	mb:SetHeight(31)
	mb:SetFrameStrata("MEDIUM")
	mb:SetFrameLevel(8)
	mb:SetMovable(true)
	mb:SetClampedToScreen(true)
	mb:RegisterForDrag("LeftButton")
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

	-- Position: restore saved CENTER-from-UIParentCENTER, or default near Minimap.
	if DB.minimapX and DB.minimapY then
		mb:SetPoint("CENTER", UIParent, "CENTER", DB.minimapX, DB.minimapY)
	else
		-- First use: place near the Minimap (top-right area).
		local mmx, mmy = Minimap:GetCenter()
		local ucx, ucy = UIParent:GetCenter()
		if mmx and mmy and ucx and ucy then
			DB.minimapX = mmx - ucx
			DB.minimapY = mmy - ucy + 80
		else
			DB.minimapX = 390
			DB.minimapY = 270
		end
		mb:SetPoint("CENTER", UIParent, "CENTER", DB.minimapX, DB.minimapY)
	end

	mb:SetScript("OnDragStart", function() this:StartMoving() end)
	mb:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
		local cx, cy = this:GetCenter()
		local ucx, ucy = UIParent:GetCenter()
		DB.minimapX = cx - ucx
		DB.minimapY = cy - ucy
	end)
	-- ── Right-click dropdown ──────────────────────────────────
	local mmDD = CreateFrame("Frame", "ART_MinimapDropdown", UIParent)
	ART_RegisterPopup(mmDD)
	mmDD:SetFrameStrata("TOOLTIP")
	mmDD:SetWidth(160)
	mmDD:SetBackdrop({
		bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile=true, tileSize=16, edgeSize=10,
		insets={left=3,right=3,top=3,bottom=3},
	})
	mmDD:SetBackdropColor(0.08, 0.08, 0.11, 1.0)
	mmDD:SetBackdropBorderColor(0.5, 0.5, 0.6, 1)
	mmDD:EnableMouse(true)
	mmDD:Hide()

	-- Close when clicking outside
	local mmDDCatcher = CreateFrame("Button", nil, UIParent)
	mmDDCatcher:SetFrameStrata("FULLSCREEN")
	mmDDCatcher:SetAllPoints(UIParent)
	mmDDCatcher:EnableMouse(true)
	mmDDCatcher:Hide()
	mmDDCatcher:SetScript("OnClick", function() mmDD:Hide(); this:Hide() end)
	mmDD:SetScript("OnHide", function() mmDDCatcher:Hide() end)

	local DD_PAD    = 6
	local DD_ROW_H  = 20
	local DD_HDR_H  = 18
	local yOff = -DD_PAD

	-- Helper: section header
	local function DDHeader(label)
		local fs = mmDD:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("TOPLEFT", mmDD, "TOPLEFT", DD_PAD, yOff)
		fs:SetTextColor(1, 0.82, 0, 1)
		fs:SetText(label)
		yOff = yOff - DD_HDR_H
		-- thin separator line
		local sep = mmDD:CreateTexture(nil, "ARTWORK")
		sep:SetHeight(1)
		sep:SetTexture(0.5, 0.5, 0.6, 0.5)
		sep:SetPoint("TOPLEFT",  mmDD, "TOPLEFT",  DD_PAD,    yOff)
		sep:SetPoint("TOPRIGHT", mmDD, "TOPRIGHT", -DD_PAD,   yOff)
		yOff = yOff - 4
	end

	-- Helper: menu item row (Button)
	local function DDItem(label, salvKey)
		local row = CreateFrame("Button", nil, mmDD)
		row:SetHeight(DD_ROW_H)
		row:SetPoint("TOPLEFT",  mmDD, "TOPLEFT",  DD_PAD,    yOff)
		row:SetPoint("TOPRIGHT", mmDD, "TOPRIGHT", -DD_PAD,   yOff)
		row:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", tile=true, tileSize=16, edgeSize=0, insets={left=0,right=0,top=0,bottom=0} })
		row:SetBackdropColor(0,0,0,0)
		row:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

		local check = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		check:SetPoint("LEFT", row, "LEFT", 2, 0)
		check:SetText("")
		check:SetTextColor(0.2, 0.9, 0.2, 1)
		check:SetWidth(14)
		row.check = check

		local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		lbl:SetPoint("LEFT", row, "LEFT", 18, 0)
		lbl:SetText(label)
		lbl:SetTextColor(0.85, 0.85, 0.85, 1)

		row.salvKey = salvKey
		row:SetScript("OnClick", function()
			if ART_SetSalvationOverride then ART_SetSalvationOverride(this.salvKey) end
			mmDD:Hide()
		end)
		yOff = yOff - DD_ROW_H
		return row
	end

	-- Build menu items
	DDHeader("Salvation")
	local salvRows = {
		DDItem("as in Profile", "profile"),
		DDItem("Allow",         "allow"),
		DDItem("Remove",        "remove"),
	}

	-- Resize dropdown to fit content
	mmDD:SetHeight(-yOff + DD_PAD)

	-- Refresh checkmarks before showing
	local function RefreshMMDD()
		local cur = ART_SalvationOverride or "profile"
		for i = 1, getn(salvRows) do
			salvRows[i].check:SetText(salvRows[i].salvKey == cur and "|cFF44FF44>|r" or "")
		end
	end

	mb:SetScript("OnClick", function()
		local btn = arg1
		if btn == "LeftButton" then
			mmDD:Hide()
			MainFrame_Toggle()
		elseif btn == "RightButton" then
			RefreshMMDD()
			mmDD:ClearAllPoints()
			mmDD:SetPoint("TOPRIGHT", this, "BOTTOMRIGHT", 0, -2)
			mmDD:Show()
			mmDDCatcher:Show()
		end
	end)
	mb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mb:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:SetText("amptieRaidTools\nLeft-click: Open/Close\nRight-click: Quick Menu\nDrag: Move")
		GameTooltip:Show()
	end)
	mb:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
		if evt == "PLAYER_LOGIN" then CreateGameMenuButton() end
	end
end)
