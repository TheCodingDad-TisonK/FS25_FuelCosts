-- =========================================================
-- FS25 Realistic Fuel Costs - Settings Panel
-- =========================================================
-- Fully custom-drawn settings panel. No XML — pure overlay.
-- Open/close: SHIFT+F
-- Two tabs: FUEL (live dashboard) and SETTINGS (config).
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class FuelSettingsPanel
FuelSettingsPanel = {}
local FuelSettingsPanel_mt = Class(FuelSettingsPanel)

local FC_MOD_NAME = g_currentModName

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[FC_MOD_NAME]
    local i18n   = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and text and text ~= "" and text ~= ("$l10n_" .. key) then
            return text
        end
    end
    return fallback or key
end

-- ── Panel geometry (normalized, Y=0 at bottom) ────────────
local PW    = 0.60
local PH    = 0.70
local PX    = (1 - PW) / 2
local PY    = (1 - PH) / 2

local TB_H  = 0.052   -- title bar
local TAB_H = 0.038   -- tab bar
local IB_H  = 0.044   -- info bar
local PAD   = 0.012   -- inner horizontal padding

local CX    = PX + PAD
local CW    = PW - PAD * 2
local CY_BOT = PY + IB_H + PAD
local CY_TOP = PY + PH - TB_H - TAB_H - PAD
local CH    = CY_TOP - CY_BOT

-- Tab IDs
local TAB_FUEL     = "fuel"
local TAB_SETTINGS = "settings"

-- Row dimensions
local ROW_H     = 0.036
local SEC_H     = 0.026
local TOGGLE_W  = 0.048
local TOGGLE_H  = 0.026
local TOGGLE_GAP = 0.004
local MULTI_W   = 0.175

-- Text sizes
local TS_TITLE  = 0.018
local TS_BODY   = 0.015
local TS_SMALL  = 0.013
local TS_TINY   = 0.011
local TS_PRICE  = 0.032   -- large price display

-- ── Colors ────────────────────────────────────────────────
local C = {
    bg          = {0.05, 0.06, 0.09, 0.97},
    title_bg    = {0.07, 0.09, 0.13, 1.0},
    info_bg     = {0.04, 0.05, 0.08, 1.0},
    border      = {0.90, 0.68, 0.20, 0.45},
    shadow      = {0.00, 0.00, 0.00, 0.45},
    divider     = {0.20, 0.22, 0.28, 0.55},
    row_alt     = {1.00, 1.00, 1.00, 0.025},
    row_hover   = {0.90, 0.68, 0.20, 0.08},
    amber       = {0.95, 0.72, 0.20, 1.0},
    amber_dim   = {0.55, 0.40, 0.08, 1.0},
    white       = {1.00, 1.00, 1.00, 1.0},
    dim         = {0.55, 0.55, 0.60, 1.0},
    hint        = {0.38, 0.38, 0.46, 1.0},
    on_bg       = {0.22, 0.75, 0.33, 1.0},
    off_bg      = {0.15, 0.16, 0.20, 1.0},
    on_text     = {0.00, 0.00, 0.00, 1.0},
    off_text    = {0.45, 0.46, 0.52, 1.0},
    cheap       = {0.32, 0.88, 0.44, 1.0},
    normal      = {0.92, 0.92, 0.92, 1.0},
    expensive   = {0.95, 0.35, 0.30, 1.0},
    shock_bg    = {0.50, 0.10, 0.10, 0.70},
    shock_ok    = {0.10, 0.28, 0.12, 0.70},
    close_hover = {0.88, 0.25, 0.25, 0.80},
    back_hover  = {0.90, 0.68, 0.20, 0.15},
    tab_active  = {0.95, 0.72, 0.20, 0.20},
    tab_hover   = {1.00, 1.00, 1.00, 0.04},
    info_admin  = {0.32, 0.88, 0.44, 1.0},
    info_no_adm = {0.88, 0.60, 0.18, 1.0},
    info_mode   = {0.55, 0.55, 0.62, 1.0},
    lock_text   = {0.88, 0.60, 0.18, 1.0},
    card_bg     = {0.07, 0.08, 0.12, 1.0},
}

-- ── Settings sections for the Settings tab ────────────────
local SETTINGS_SECTIONS = {
    {
        header = "Simulation",
        items  = { "enabled", "baseFuelPrice", "difficulty", "priceVolatility", "seasonalEffects", "marketShocks" },
    },
    {
        header = "Display",
        items  = { "hudEnabled", "hudPosition", "showNotifications" },
    },
    {
        header = "Developer",
        items  = { "debugMode" },
    },
}

local MULTI_OPTS = {
    difficulty      = {"Simple", "Realistic", "Hardcore"},
    priceVolatility = {"None", "Low", "Medium", "High"},
    hudPosition     = {"Suite Home", "Top Right", "Bot Left", "Bot Right"},
}

local SETTING_LABELS = {
    enabled          = "Mod Enabled",
    baseFuelPrice    = "Base Fuel Price",
    difficulty       = "Difficulty",
    priceVolatility  = "Price Volatility",
    seasonalEffects  = "Seasonal Effects",
    marketShocks     = "Market Shocks",
    hudEnabled       = "Show HUD",
    hudPosition      = "HUD Position",
    showNotifications = "Fill Notifications",
    debugMode        = "Debug Mode",
}

local SETTING_DESCS = {
    enabled          = "Master on/off for fuel cost simulation",
    baseFuelPrice    = "Base price per litre in game currency (step 0.10)",
    difficulty       = "Price multiplier (Simple=0.6x, Realistic=1x, Hardcore=1.5x)",
    priceVolatility  = "Daily swing range for market fluctuation",
    seasonalEffects  = "Seasonal price curve (winter costs more)",
    marketShocks     = "Random supply shock events",
    hudEnabled       = "Show fuel price overlay on screen",
    hudPosition      = "Screen corner for the price HUD",
    showNotifications = "Show fill cost popup when fuelling",
    debugMode        = "Extra log output for troubleshooting",
}

local SEASON_NAMES  = { [0] = "Spring", [1] = "Summer", [2] = "Autumn", [3] = "Winter" }
local SEASON_COLORS = {
    [0] = {0.55, 0.90, 0.45, 1.0},
    [1] = {0.95, 0.82, 0.25, 1.0},
    [2] = {0.90, 0.55, 0.20, 1.0},
    [3] = {0.65, 0.80, 0.95, 1.0},
}

-- ── Constructor ───────────────────────────────────────────
function FuelSettingsPanel.new(manager)
    local self = setmetatable({}, FuelSettingsPanel_mt)
    self.manager      = manager
    self.fillOverlay  = nil
    self.isVisible    = false
    local mod = g_modManager and g_modManager:getModByName(g_currentModName)
    self.modVersion   = "v" .. (mod and mod.version or "?")
    self.activeTab    = TAB_FUEL
    self.mouseX       = 0
    self.mouseY       = 0
    self.initialized  = false
    self._clickRects  = {}
    self.savedCamRotX = nil
    self.savedCamRotY = nil
    self.savedCamRotZ = nil
    return self
end

function FuelSettingsPanel:initialize()
    if self.initialized then return end
    if createImageOverlay then
        self.fillOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end
    self.initialized = true
end

function FuelSettingsPanel:delete()
    if self.fillOverlay then
        delete(self.fillOverlay)
        self.fillOverlay = nil
    end
    self.initialized = false
end

-- ── Visibility ────────────────────────────────────────────
function FuelSettingsPanel:open()
    if not self.initialized then self:initialize() end
    self.isVisible = true
    self.activeTab = TAB_FUEL
    self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = nil, nil, nil
    if getCamera and getRotation then
        local ok, cam = pcall(getCamera)
        if ok and cam and cam ~= 0 then
            local ok2, rx, ry, rz = pcall(getRotation, cam)
            if ok2 then
                self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = rx, ry, rz
            end
        end
    end
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true, true)
    end
    FuelLogger.info("FuelSettingsPanel: opened")
end

function FuelSettingsPanel:close()
    self.isVisible = false
    self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = nil, nil, nil
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(false)
    end
    FuelLogger.info("FuelSettingsPanel: closed")
end

function FuelSettingsPanel:toggle()
    if self.isVisible then self:close() else self:open() end
end

function FuelSettingsPanel:isOpen()
    return self.isVisible
end

-- Called every frame from FuelCostsManager:update()
function FuelSettingsPanel:update()
    if not self.isVisible then return end
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true, true)
    end
    if self.savedCamRotX ~= nil and getCamera and setRotation then
        local ok, cam = pcall(getCamera)
        if ok and cam and cam ~= 0 then
            pcall(setRotation, cam, self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ)
        end
    end
    if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then
        self:close()
    end
end

-- ── Admin check ───────────────────────────────────────────
function FuelSettingsPanel:isAdmin()
    if not g_currentMission then return false end
    if not (g_currentMission.missionDynamicInfo and
            g_currentMission.missionDynamicInfo.isMultiplayer) then
        return true
    end
    if g_dedicatedServer then return true end
    local user = g_currentMission.userManager and
                 g_currentMission.userManager:getUserByUserId(g_currentMission.playerUserId)
    return user and user:getIsMasterUser() or false
end

-- ── Settings access ───────────────────────────────────────
function FuelSettingsPanel:getValue(id)
    return self.manager and self.manager.settings and self.manager.settings[id]
end

function FuelSettingsPanel:requestChange(id, value)
    local def = FuelSettingsSchema.byId[id]
    if not def then return end

    if def.localOnly then
        self.manager.settings[id] = value
        if id == "hudPosition" and self.manager.hud then
            self.manager.hud:updatePosition()
        end
        self.manager:save()
        return
    end

    if not self:isAdmin() then
        if g_currentMission and g_currentMission.hud and
           g_currentMission.hud.showBlinkingWarning then
            g_currentMission.hud:showBlinkingWarning(
                "Only server admins can change this setting", 4000)
        end
        return
    end

    self.manager.settings[id] = value
    -- Handle price-affecting settings immediately
    if id == "enabled" then
        if not value and self.manager.priceEngine then
            self.manager.priceEngine:restoreOriginalPrices()
        end
    elseif id == "difficulty" or id == "baseFuelPrice" then
        if self.manager.priceEngine then
            local pe = self.manager.priceEngine
            local base = self.manager.settings.baseFuelPrice
            local diffMult = self.manager.settings:getDifficultyMultiplier()
            local effectiveBase = base * diffMult
            local C = FuelConstants.PRICE
            pe.currentPrice = math.max(effectiveBase * C.MIN_MULTIPLIER,
                                       math.min(effectiveBase * C.MAX_MULTIPLIER, effectiveBase))
            pe:applyToFillTypes()
        end
    end
    self.manager:save()
end

-- ── Drawing helpers ───────────────────────────────────────
function FuelSettingsPanel:drawRect(x, y, w, h, col, alpha)
    if not self.fillOverlay then return end
    local a = alpha or col[4] or 1.0
    setOverlayColor(self.fillOverlay, col[1], col[2], col[3], a)
    renderOverlay(self.fillOverlay, x, y, w, h)
end

function FuelSettingsPanel:drawText(x, y, size, text, col, align, bold)
    setTextColor(col[1], col[2], col[3], col[4] or 1.0)
    setTextBold(bold == true)
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    renderText(x, y, size, text)
end

function FuelSettingsPanel:registerClick(id, x, y, w, h, data)
    table.insert(self._clickRects, { id = id, x = x, y = y, w = w, h = h, data = data })
end

function FuelSettingsPanel:hitTest(rx, ry, rw, rh, mx, my)
    return mx >= rx and mx <= rx + rw and my >= ry and my <= ry + rh
end

-- ── Main draw entry ───────────────────────────────────────
function FuelSettingsPanel:draw()
    if not self.isVisible then return end
    if not self.initialized then return end
    if not g_currentMission then return end

    self._clickRects = {}

    -- Screen fade
    self:drawRect(0, 0, 1, 1, C.shadow, 0.40)

    -- Panel shadow
    self:drawRect(PX + 0.004, PY - 0.004, PW, PH, C.shadow, 0.55)

    -- Panel background
    self:drawRect(PX, PY, PW, PH, C.bg)

    -- Border
    local bw = 0.0015
    self:drawRect(PX,           PY,           PW, bw,  C.border)
    self:drawRect(PX,           PY + PH - bw, PW, bw,  C.border)
    self:drawRect(PX,           PY,           bw, PH,  C.border)
    self:drawRect(PX + PW - bw, PY,           bw, PH,  C.border)

    -- Title bar
    self:drawTitleBar()

    -- Tab bar
    self:drawTabBar()

    -- Info bar
    self:drawInfoBar()

    -- Content
    if self.activeTab == TAB_FUEL then
        self:drawFuelTab()
    else
        self:drawSettingsTab()
    end
end

-- ── Title bar ─────────────────────────────────────────────
function FuelSettingsPanel:drawTitleBar()
    local ty = PY + PH - TB_H
    self:drawRect(PX, ty, PW, TB_H, C.title_bg)
    self:drawRect(PX, ty, 0.004, TB_H, C.amber)

    self:drawText(PX + 0.018, ty + TB_H * 0.32, TS_TITLE,
        "FUEL COSTS", C.white, RenderText.ALIGN_LEFT, true)

    self:drawText(PX + PW - 0.020, ty + TB_H * 0.32, TS_TINY,
        self.modVersion, C.hint, RenderText.ALIGN_RIGHT, false)

    -- [X] close button
    local cbW = 0.038
    local cbH = TB_H * 0.60
    local cbX = PX + PW - cbW - 0.010
    local cbY = ty + (TB_H - cbH) / 2
    local hover = self:hitTest(cbX, cbY, cbW, cbH, self.mouseX, self.mouseY)
    self:drawRect(cbX, cbY, cbW, cbH, hover and C.close_hover or C.off_bg)
    self:drawText(cbX + cbW * 0.5, cbY + cbH * 0.18, TS_SMALL,
        "X", C.white, RenderText.ALIGN_CENTER, true)
    self:registerClick("close", cbX, cbY, cbW, cbH)
end

-- ── Tab bar ───────────────────────────────────────────────
function FuelSettingsPanel:drawTabBar()
    local ty = PY + PH - TB_H - TAB_H
    self:drawRect(PX, ty, PW, TAB_H, C.title_bg, 0.85)
    -- Divider at bottom of tab bar
    self:drawRect(PX, ty, PW, 0.001, C.divider)

    local tabW = PW / 2
    local tabs = {
        { id = TAB_FUEL,     label = "⛽  FUEL" },
        { id = TAB_SETTINGS, label = "⚙  SETTINGS" },
    }

    for i, tab in ipairs(tabs) do
        local tx = PX + (i - 1) * tabW
        local isActive = (self.activeTab == tab.id)
        local hover = self:hitTest(tx, ty, tabW, TAB_H, self.mouseX, self.mouseY)

        if isActive then
            self:drawRect(tx, ty, tabW, TAB_H, C.tab_active)
            self:drawRect(tx, ty + TAB_H - 0.003, tabW, 0.003, C.amber)
        elseif hover then
            self:drawRect(tx, ty, tabW, TAB_H, C.tab_hover)
        end

        -- Vertical divider between tabs
        if i == 1 then
            self:drawRect(tx + tabW - 0.0008, ty + 0.006, 0.0008, TAB_H - 0.012, C.divider)
        end

        local col = isActive and C.amber or (hover and C.white or C.dim)
        self:drawText(tx + tabW * 0.5, ty + TAB_H * 0.28, TS_SMALL,
            tab.label, col, RenderText.ALIGN_CENTER, isActive)

        self:registerClick("tab_" .. tab.id, tx, ty, tabW, TAB_H)
    end
end

-- ── Info bar ──────────────────────────────────────────────
function FuelSettingsPanel:drawInfoBar()
    local iy = PY
    self:drawRect(PX, iy, PW, IB_H, C.info_bg)
    self:drawRect(PX, iy + IB_H - 0.001, PW, 0.001, C.divider)

    local isAdmin = self:isAdmin()
    local isMP    = g_currentMission and g_currentMission.missionDynamicInfo and
                    g_currentMission.missionDynamicInfo.isMultiplayer

    local adminText  = isAdmin and "Admin: YES" or "Admin: NO"
    local adminColor = isAdmin and C.info_admin or C.info_no_adm
    local modeText   = isMP and "Multiplayer" or "Single Player"

    local textY = iy + IB_H * 0.28
    self:drawText(PX + PAD,          textY, TS_SMALL, adminText,          adminColor,  RenderText.ALIGN_LEFT,  true)
    self:drawText(PX + PAD + 0.10,   textY, TS_SMALL, "·  " .. modeText,  C.info_mode, RenderText.ALIGN_LEFT,  false)
    local closeHint = "click X to close"
    if g_FuelCostsManager and g_FuelCostsManager.settingsPanelEventId and g_inputBinding then
        local ok, txt = pcall(function()
            return g_inputBinding:getActionEventDisplayName(g_FuelCostsManager.settingsPanelEventId)
        end)
        if ok and txt and txt ~= "" then closeHint = txt .. " to close" end
    end
    self:drawText(PX + PW - PAD,     textY, TS_SMALL, closeHint,         C.hint,      RenderText.ALIGN_RIGHT, false)
end

-- ── Fuel dashboard tab ────────────────────────────────────
function FuelSettingsPanel:drawFuelTab()
    local pe       = self.manager and self.manager.priceEngine
    local settings = self.manager and self.manager.settings
    if not pe or not settings then
        self:drawText(PX + PW * 0.5, PY + PH * 0.5, TS_BODY, "Not initialized", C.dim, RenderText.ALIGN_CENTER, false)
        return
    end

    local price    = pe:getDisplayPrice()
    local status   = pe:getPriceStatus()
    local base     = settings.baseFuelPrice * settings:getDifficultyMultiplier()
    local pctChg   = base > 0 and ((price - base) / base * 100) or 0
    local priceCol = status == "cheap" and C.cheap or (status == "expensive" and C.expensive or C.normal)

    local topY     = CY_TOP
    local curY     = topY

    -- ── Price card ───────────────────────────────────────
    local cardH = 0.170
    local cardY = curY - cardH
    if cardY >= CY_BOT then
        self:drawRect(CX, cardY, CW, cardH, C.card_bg)
        -- Accent border on left
        self:drawRect(CX, cardY, 0.004, cardH, priceCol, 0.90)
        -- Top/bottom thin lines
        self:drawRect(CX, cardY + cardH - 0.001, CW, 0.001, priceCol, 0.30)
        self:drawRect(CX, cardY,                 CW, 0.001, priceCol, 0.15)

        -- "CURRENT PRICE" label
        self:drawText(CX + CW * 0.5, cardY + cardH - 0.030, TS_SMALL,
            "CURRENT DIESEL PRICE", C.dim, RenderText.ALIGN_CENTER, false)

        -- Big price number
        self:drawText(CX + CW * 0.5, cardY + cardH * 0.40, TS_PRICE,
            string.format("$%.4f / L", price), priceCol, RenderText.ALIGN_CENTER, true)

        -- Status badge
        local badgeLabel = status == "cheap" and "[ CHEAP ]"
                        or status == "expensive" and "[ EXPENSIVE ]"
                        or "[ NORMAL ]"
        self:drawText(CX + CW * 0.5, cardY + 0.012, TS_SMALL,
            badgeLabel, priceCol, RenderText.ALIGN_CENTER, true)

        -- Change % (right side)
        local chgSign = pctChg >= 0 and "+" or ""
        local chgText = string.format("%s%.1f%% vs base", chgSign, pctChg)
        local chgCol  = pctChg > 0 and C.expensive or (pctChg < 0 and C.cheap or C.dim)
        self:drawText(CX + CW - 0.010, cardY + cardH * 0.40, TS_SMALL,
            chgText, chgCol, RenderText.ALIGN_RIGHT, true)

        curY = cardY - 0.012
    end

    -- ── Market info rows ─────────────────────────────────
    local infoRowH = 0.036
    local rowIdx   = 0

    local function infoRow(label, value, valCol)
        local ry = curY - infoRowH
        if ry < CY_BOT then return false end
        rowIdx = rowIdx + 1
        if rowIdx % 2 == 0 then self:drawRect(CX, ry, CW, infoRowH, C.row_alt) end
        self:drawRect(CX, ry, CW, 0.0005, C.divider, 0.30)
        self:drawText(CX + 0.010, ry + infoRowH * 0.55, TS_BODY, label, C.dim,     RenderText.ALIGN_LEFT,  false)
        self:drawText(CX + CW - 0.010, ry + infoRowH * 0.55, TS_BODY, value, valCol or C.white, RenderText.ALIGN_RIGHT, true)
        curY = ry
        return true
    end

    -- Base price
    infoRow("Base Price",
        string.format("$%.4f / L", settings.baseFuelPrice),
        C.hint)

    -- Difficulty multiplier
    local diffNames = {"Simple", "Realistic", "Hardcore"}
    local diffMult  = settings:getDifficultyMultiplier()
    infoRow("Difficulty",
        string.format("%s  (%.0f%%)", diffNames[settings.difficulty] or "?", diffMult * 100),
        C.amber)

    -- Shock status
    local shockText, shockCol
    if pe.shockActive then
        local dir = pe.shockMagnitude >= 0 and "SURGE" or "SLUMP"
        shockText = string.format("ACTIVE — %s %+.0f%%  (%d days left)",
            dir, pe.shockMagnitude * 100, pe.shockDaysLeft)
        shockCol = pe.shockMagnitude >= 0 and C.expensive or C.cheap
    else
        shockText = "Inactive"
        shockCol  = C.dim
    end
    infoRow("Market Shock", shockText, shockCol)

    -- Season
    local env    = g_currentMission and g_currentMission.environment
    local season = env and env.currentSeason or 0
    local sName  = SEASON_NAMES[season] or "?"
    local sCol   = SEASON_COLORS[season] or C.white
    local sMod   = settings.seasonalEffects and FuelConstants.SEASONAL[season] or 1.0
    local sText  = string.format("%s  (%+.0f%%)", sName, (sMod - 1.0) * 100)
    infoRow("Season Effect", settings.seasonalEffects and sText or "Disabled", sCol)

    -- Volatility
    local volNames = {"None", "Low", "Medium", "High"}
    infoRow("Volatility",
        volNames[settings.priceVolatility] or "?",
        C.amber)

    -- Admin action: Force price tick
    if self:isAdmin() and g_server ~= nil then
        curY = curY - 0.010
        local btnW = 0.160
        local btnH = 0.030
        local btnX = CX + CW - btnW
        local btnY = curY - btnH
        if btnY >= CY_BOT then
            local hover = self:hitTest(btnX, btnY, btnW, btnH, self.mouseX, self.mouseY)
            self:drawRect(btnX, btnY, btnW, btnH,
                hover and {0.15, 0.35, 0.20, 0.95} or {0.08, 0.18, 0.10, 0.85})
            self:drawRect(btnX, btnY, 0.002, btnH, C.amber)
            self:drawText(btnX + btnW * 0.5, btnY + btnH * 0.22, TS_TINY,
                ">  Force Day Tick", hover and C.white or C.dim,
                RenderText.ALIGN_CENTER, false)
            self:registerClick("force_tick", btnX, btnY, btnW, btnH)
        end
    end
end

-- ── Settings tab ──────────────────────────────────────────
function FuelSettingsPanel:drawSettingsTab()
    local curY   = CY_TOP
    local isAdmin = self:isAdmin()
    local rowIdx  = 0

    for _, sec in ipairs(SETTINGS_SECTIONS) do
        curY = curY - SEC_H
        if curY < CY_BOT then break end

        self:drawRect(CX, curY, CW, SEC_H, C.title_bg, 0.60)
        self:drawRect(CX, curY, 0.003, SEC_H, C.amber)
        self:drawText(CX + 0.012, curY + SEC_H * 0.25, TS_SMALL,
            string.upper(sec.header), C.amber, RenderText.ALIGN_LEFT, true)

        for _, settingId in ipairs(sec.items) do
            curY = curY - ROW_H
            if curY < CY_BOT then break end
            rowIdx = rowIdx + 1
            self:drawSettingRow(CX, curY, CW, settingId, rowIdx, isAdmin)
        end

        -- Reset button after Developer section
        if sec.header == "Developer" then
            curY = curY - 0.008
            local btnW = 0.140
            local btnH = 0.028
            local btnX = CX + CW - btnW
            local btnY = curY - btnH
            if btnY >= CY_BOT then
                local hover = self:hitTest(btnX, btnY, btnW, btnH, self.mouseX, self.mouseY)
                self:drawRect(btnX, btnY, btnW, btnH,
                    hover and {0.45, 0.10, 0.05, 0.95} or {0.20, 0.05, 0.03, 0.85})
                self:drawRect(btnX, btnY, 0.002, btnH, {0.88, 0.30, 0.25, 0.90})
                self:drawText(btnX + btnW * 0.5, btnY + btnH * 0.22, TS_TINY,
                    "!! Reset All Settings",
                    hover and {1,1,1,1} or {0.75,0.50,0.45,1},
                    RenderText.ALIGN_CENTER, true)
                self:registerClick("reset_all", btnX, btnY, btnW, btnH)
                curY = btnY
            end
        end

        curY = curY - 0.006
    end

    -- Thin divider under tab bar
    self:drawRect(CX, CY_TOP, CW, 0.001, C.divider)
end

-- ── Setting row ────────────────────────────────────────────
function FuelSettingsPanel:drawSettingRow(x, y, w, settingId, rowIdx, isAdmin)
    local def = FuelSettingsSchema.byId[settingId]
    if not def then return end

    if rowIdx % 2 == 0 then
        self:drawRect(x, y, w, ROW_H, C.row_alt)
    end

    if self:hitTest(x, y, w, ROW_H, self.mouseX, self.mouseY) then
        self:drawRect(x, y, w, ROW_H, C.row_hover)
    end

    local locked     = not def.localOnly and not isAdmin
    local labelColor = locked and C.lock_text or C.white
    local descColor  = locked and {C.lock_text[1]*0.7, C.lock_text[2]*0.7, C.lock_text[3]*0.7, 1} or C.dim

    if locked then
        self:drawRect(x, y, 0.003, ROW_H, {0.88, 0.60, 0.18, 0.45})
    end

    local labelX = x + (locked and 0.010 or 0.008)
    self:drawText(labelX, y + ROW_H * 0.55, TS_BODY,
        SETTING_LABELS[settingId] or settingId, labelColor, RenderText.ALIGN_LEFT, not locked)
    self:drawText(labelX, y + ROW_H * 0.15, TS_TINY,
        SETTING_DESCS[settingId] or "", descColor, RenderText.ALIGN_LEFT, false)

    local ctrlX = x + w - 0.012
    local ctrlY = y + (ROW_H - TOGGLE_H) / 2

    if def.type == "bool" or def.type == "boolean" then
        self:drawToggleControl(ctrlX, ctrlY, settingId, locked)
    elseif def.type == "int" or def.type == "number" then
        self:drawMultiControl(ctrlX, ctrlY, settingId, locked)
    elseif def.type == "float" then
        self:drawStepControl(ctrlX, ctrlY, settingId, locked)
    end

    self:drawRect(x, y, w, 0.0005, C.divider, 0.35)
end

-- ── Toggle control [ON] [OFF] ─────────────────────────────
function FuelSettingsPanel:drawToggleControl(rightX, y, settingId, locked)
    local val  = self:getValue(settingId)
    local isOn = val == true

    local offX = rightX - TOGGLE_W * 2 - TOGGLE_GAP
    local onX  = rightX - TOGGLE_W

    local offBg = (not isOn) and C.dim or C.off_bg
    self:drawRect(offX, y, TOGGLE_W, TOGGLE_H, offBg, (not isOn) and 0.90 or 0.60)
    self:drawText(offX + TOGGLE_W * 0.5, y + TOGGLE_H * 0.20, TS_TINY,
        "OFF", (not isOn) and C.white or C.off_text, RenderText.ALIGN_CENTER, not isOn)

    local onBg = isOn and C.on_bg or C.off_bg
    self:drawRect(onX, y, TOGGLE_W, TOGGLE_H, onBg, isOn and 1.0 or 0.60)
    self:drawText(onX + TOGGLE_W * 0.5, y + TOGGLE_H * 0.20, TS_TINY,
        "ON", isOn and C.on_text or C.off_text, RenderText.ALIGN_CENTER, isOn)

    if not locked then
        self:registerClick("toggle_off_" .. settingId, offX, y, TOGGLE_W, TOGGLE_H,
            { id = settingId, value = false })
        self:registerClick("toggle_on_" .. settingId, onX, y, TOGGLE_W, TOGGLE_H,
            { id = settingId, value = true })
    end
end

-- ── Multi-select control [◄ Option ►] ────────────────────
function FuelSettingsPanel:drawMultiControl(rightX, y, settingId, locked)
    local opts    = MULTI_OPTS[settingId]
    if not opts then return end
    local val     = self:getValue(settingId) or 1
    local current = opts[val] or opts[1] or "?"

    local arrowW = 0.022
    local labelW = MULTI_W - arrowW * 2
    local totalX = rightX - MULTI_W
    local leftX  = totalX
    local midX   = totalX + arrowW
    local rightBX = totalX + arrowW + labelW

    local lHover = not locked and self:hitTest(leftX, y, arrowW, TOGGLE_H, self.mouseX, self.mouseY)
    self:drawRect(leftX, y, arrowW, TOGGLE_H, lHover and C.back_hover or C.off_bg)
    self:drawText(leftX + arrowW * 0.5, y + TOGGLE_H * 0.18, TS_TINY,
        "<", lHover and C.amber or C.dim, RenderText.ALIGN_CENTER, true)

    self:drawRect(midX, y, labelW, TOGGLE_H, {0.10, 0.11, 0.15, 0.90})
    self:drawText(midX + labelW * 0.5, y + TOGGLE_H * 0.18, TS_TINY,
        current, C.white, RenderText.ALIGN_CENTER, false)

    local rHover = not locked and self:hitTest(rightBX, y, arrowW, TOGGLE_H, self.mouseX, self.mouseY)
    self:drawRect(rightBX, y, arrowW, TOGGLE_H, rHover and C.back_hover or C.off_bg)
    self:drawText(rightBX + arrowW * 0.5, y + TOGGLE_H * 0.18, TS_TINY,
        ">", rHover and C.amber or C.dim, RenderText.ALIGN_CENTER, true)

    if not locked then
        self:registerClick("multi_prev_" .. settingId, leftX, y, arrowW, TOGGLE_H,
            { id = settingId, dir = -1, opts = opts })
        self:registerClick("multi_next_" .. settingId, rightBX, y, arrowW, TOGGLE_H,
            { id = settingId, dir = 1, opts = opts })
    end
end

-- ── Step control [−] $1.20/L [+] (for float settings) ────
function FuelSettingsPanel:drawStepControl(rightX, y, settingId, locked)
    local val    = self:getValue(settingId) or 0
    local arrowW = 0.022
    local labelW = MULTI_W - arrowW * 2
    local totalX = rightX - MULTI_W
    local leftX  = totalX
    local midX   = totalX + arrowW
    local rightBX = totalX + arrowW + labelW

    local lHover = not locked and self:hitTest(leftX, y, arrowW, TOGGLE_H, self.mouseX, self.mouseY)
    self:drawRect(leftX, y, arrowW, TOGGLE_H, lHover and C.back_hover or C.off_bg)
    self:drawText(leftX + arrowW * 0.5, y + TOGGLE_H * 0.18, TS_TINY,
        "-", lHover and C.amber or C.dim, RenderText.ALIGN_CENTER, true)

    self:drawRect(midX, y, labelW, TOGGLE_H, {0.10, 0.11, 0.15, 0.90})
    self:drawText(midX + labelW * 0.5, y + TOGGLE_H * 0.18, TS_TINY,
        string.format("$%.2f / L", val), C.white, RenderText.ALIGN_CENTER, false)

    local rHover = not locked and self:hitTest(rightBX, y, arrowW, TOGGLE_H, self.mouseX, self.mouseY)
    self:drawRect(rightBX, y, arrowW, TOGGLE_H, rHover and C.back_hover or C.off_bg)
    self:drawText(rightBX + arrowW * 0.5, y + TOGGLE_H * 0.18, TS_TINY,
        "+", rHover and C.amber or C.dim, RenderText.ALIGN_CENTER, true)

    if not locked then
        self:registerClick("step_dec_" .. settingId, leftX, y, arrowW, TOGGLE_H,
            { id = settingId, dir = -1 })
        self:registerClick("step_inc_" .. settingId, rightBX, y, arrowW, TOGGLE_H,
            { id = settingId, dir = 1 })
    end
end

-- ── Mouse event ───────────────────────────────────────────
function FuelSettingsPanel:onMouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if not self.isVisible then return false end

    self.mouseX = posX
    self.mouseY = posY

    if not isDown then return true end
    if button ~= Input.MOUSE_BUTTON_LEFT then return true end

    for _, r in ipairs(self._clickRects) do
        if self:hitTest(r.x, r.y, r.w, r.h, posX, posY) then
            self:handleClick(r.id, r.data)
            return true
        end
    end

    -- Click outside panel = close
    if not self:hitTest(PX, PY, PW, PH, posX, posY) then
        self:close()
        return true
    end

    return true
end

function FuelSettingsPanel:handleClick(id, data)
    if id == "close" then
        self:close()

    elseif id:sub(1, 4) == "tab_" then
        self.activeTab = id:sub(5)

    elseif id:sub(1, 11) == "toggle_off_" then
        if data then self:requestChange(data.id, false) end

    elseif id:sub(1, 10) == "toggle_on_" then
        if data then self:requestChange(data.id, true) end

    elseif id:sub(1, 10) == "multi_prev" then
        if data then
            local cur = self:getValue(data.id) or 1
            local nxt = cur - 1
            if nxt < 1 then nxt = #data.opts end
            self:requestChange(data.id, nxt)
        end

    elseif id:sub(1, 10) == "multi_next" then
        if data then
            local cur = self:getValue(data.id) or 1
            local nxt = cur + 1
            if nxt > #data.opts then nxt = 1 end
            self:requestChange(data.id, nxt)
        end

    elseif id:sub(1, 9) == "step_dec_" or id:sub(1, 9) == "step_inc_" then
        if data then
            local cur = self:getValue(data.id) or 1.20
            local nxt = cur + data.dir * 0.10
            nxt = math.floor(nxt * 100 + 0.5) / 100  -- round to 2dp
            nxt = math.max(0.10, math.min(10.0, nxt))
            self:requestChange(data.id, nxt)
            if self.manager and self.manager.priceEngine then
                self.manager.priceEngine:applyToFillTypes()
            end
        end

    elseif id == "force_tick" then
        if self.manager then
            self.manager:debugForceTick()
        end

    elseif id == "reset_all" then
        if self:isAdmin() then
            for _, def in ipairs(FuelSettingsSchema.definitions) do
                if def.default ~= nil then
                    self.manager.settings[def.id] = def.default
                end
            end
            if self.manager.hud then self.manager.hud:updatePosition() end
            self.manager:save()
            FuelLogger.info("FuelSettingsPanel: reset all settings to defaults")
        end
    end
end
