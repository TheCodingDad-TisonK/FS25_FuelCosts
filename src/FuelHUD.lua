-- =========================================================
-- FS25 Realistic Fuel Costs - FuelHUD
-- =========================================================
-- Small overlay showing the current fuel price per litre.
-- Colour-coded: green (cheap) / white (normal) / red (expensive).
-- Draggable via right-click.
-- =========================================================

---@class FuelHUD
-- BUILD 17:57 + ATTN 18:02 (Wizard hot-reload law, FS25-HotReload-Guide.md Part 1):
-- reuse the existing class table on Ctrl+R reload so updated methods land on the
-- table live metatables already reference, instead of orphaning it.
FuelHUD = FuelHUD or {}
FuelHUD.__index = FuelHUD

local COLOR = {
    cheap     = { 0.40, 0.85, 0.40, 1.0 },
    normal    = { 0.95, 0.95, 0.95, 1.0 },
    expensive = { 0.95, 0.35, 0.35, 1.0 },
    bg        = { 0.05, 0.05, 0.05, 0.75 },
    label     = { 0.70, 0.70, 0.70, 1.0 },
    notif_bg  = { 0.05, 0.06, 0.09, 0.90 },
    notif_def = { 0.95, 0.80, 0.25, 1.0 },
}

local NOTIF_W     = 0.220
local NOTIF_H     = 0.036
local NOTIF_X     = 0.390   -- centered-ish
local NOTIF_Y     = 0.060
local NOTIF_TS    = 0.014

local function getBaseGameRenderer()
    local hud = (g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD
    return hud ~= nil and hud.renderer or nil
end

-- Factory home (Wizard 2026-08-21): the suite layout Wizard arranged in-game -
-- first run and the "Suite Home" position preset both land the chip here.
FuelHUD.FACTORY_X         = 0.638125
FuelHUD.FACTORY_Y         = 0.925000
FuelHUD.FACTORY_WIDTHMULT = 0.764062

function FuelHUD.new(settings, priceEngine)
    local self = setmetatable({}, FuelHUD)
    self.settings    = settings
    self.priceEngine = priceEngine
    self.posX        = FuelHUD.FACTORY_X
    self.posY        = FuelHUD.FACTORY_Y
    self.overlay     = nil
    self.initialized = false
    self.isDragging  = false
    self.dragOffX    = 0
    self.dragOffY    = 0
    self.flashQueue  = {}
    self.activeFlash = nil
    -- BUILD 19:38 (Sam DESIGN 19:30): suite layout-edit membership. Entered and
    -- exited by the MasterHUD edit listener the bridge registers; drag via
    -- onMouseEvent below; layout persists to the savegame like Income/RWE.
    -- Wizard 2026-08-21 (overrides the earlier move-only ruling): the chip joins
    -- the NPCFavor/Workplace resize vocabulary - corners = uniform scale,
    -- left/right edges = width-only, both persisted with the position.
    self.editMode     = false
    self.layoutLoaded = false
    self.savedCamRotX = nil
    self.savedCamRotY = nil
    self.savedCamRotZ = nil

    -- Scale + width state (NPCFavor/Workplace pattern)
    self.scale              = 1.0
    self.widthMult          = FuelHUD.FACTORY_WIDTHMULT
    self.resizing           = false
    self.resizeStartX       = 0
    self.resizeStartY       = 0
    self.resizeStartScale   = 1.0
    self.edgeDragging       = nil   -- nil | "left" | "right"
    self.edgeDragStartX     = 0
    self.edgeDragStartWidth = 1.0
    return self
end

FuelHUD.MIN_SCALE          = 0.6
FuelHUD.MAX_SCALE          = 1.6
FuelHUD.MIN_WIDTH_MULT     = 0.7
FuelHUD.MAX_WIDTH_MULT     = 2.5
FuelHUD.RESIZE_HANDLE_SIZE = 0.006
FuelHUD.EDGE_BAND_W        = 0.008
FuelHUD.EDGE_SENS          = 3.0

-- ONE width/height source; every consumer (draw, hit tests, chrome, anchors)
-- reads these so scale and width drags reshape everything together.
function FuelHUD:getW()
    local C = FuelConstants.HUD
    return C.WIDTH * (self.widthMult or 1.0) * (self.scale or 1.0)
end

function FuelHUD:getH()
    local C = FuelConstants.HUD
    return C.HEIGHT * (self.scale or 1.0)
end

-- =========================================================
-- BUILD 19:38: suite layout-edit (+ Wizard 2026-08-21 scale/width)
-- =========================================================

function FuelHUD:enterEditMode()
    self.editMode     = true
    self.isDragging   = false
    self.resizing     = false
    self.edgeDragging = nil
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true)
    end
    -- Camera freeze on foot while dragging (Tax/Income pattern, guarded).
    if getCamera and getRotation then
        local ok, cam = pcall(getCamera)
        if ok and cam and cam ~= 0 then
            local ok2, rx, ry, rz = pcall(getRotation, cam)
            if ok2 then
                self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = rx, ry, rz
            end
        end
    end
end

function FuelHUD:exitEditMode()
    self.editMode     = false
    self.isDragging   = false
    self.resizing     = false
    self.edgeDragging = nil
    self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = nil, nil, nil
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(false)
    end
    self:clampPosition()
    self:saveLayout()
end

-- 2026-08-22 (Wizard "fix the bug so they save"): HUD layout now persists in
-- modSettings, not the savegame directory.
--
-- The old path wrote <savegameDirectory>/FS25_FuelCosts_hud.xml. That file is present in savegame0,
-- 5, 6 and 8 but never appeared in savegame1, so the write is not reliable in the
-- savegame directory. SoilFertilizer already persists its HUD under modSettings and
-- its hud.xml carried the live position, scale and width through every save and
-- restart, so that is the pattern that demonstrably survives and this now matches it.
--
-- modSettings is also global rather than per-savegame, which is the right scope for a
-- HUD layout: the player arranges their screen once, not once per save.
-- getUserProfileAppPath and createFolder are engine functions, both already used by
-- SoilFertilizer, FarmTablet and MarketDynamics in this suite.
function FuelHUD:getLayoutPath()
    local ok, profilePath = pcall(getUserProfileAppPath)
    if ok and profilePath ~= nil and profilePath ~= "" then
        if profilePath:sub(-1) ~= "/" and profilePath:sub(-1) ~= "\\" then
            profilePath = profilePath .. "/"
        end
        local base = profilePath .. "modSettings/FS25_FuelCosts"
        createFolder(profilePath .. "modSettings")
        createFolder(base)
        createFolder(base .. "/HUD")
        return base .. "/HUD/hud.xml"
    end
    -- Dedicated server or any environment with no user profile path: keep the old
    -- savegame-dir file rather than losing the layout entirely.
    if g_currentMission ~= nil and g_currentMission.missionInfo ~= nil
    and g_currentMission.missionInfo.savegameDirectory ~= nil then
        return g_currentMission.missionInfo.savegameDirectory .. "/FS25_FuelCosts_hud.xml"
    end
end

--- The pre-2026-08-22 location. Read once on load so an arrangement saved before the
--- move is migrated instead of lost; the next save writes it to the new path.
function FuelHUD:getLegacyLayoutPath()
    if g_currentMission ~= nil and g_currentMission.missionInfo ~= nil
    and g_currentMission.missionInfo.savegameDirectory ~= nil then
        return g_currentMission.missionInfo.savegameDirectory .. "/FS25_FuelCosts_hud.xml"
    end
end

function FuelHUD:saveLayout()
    local path = self:getLayoutPath()
    if not path then return end
    local xml = XMLFile.create("fc_hud", path, "hudLayout")
    if xml then
        xml:setFloat("hudLayout.posX", self.posX)
        xml:setFloat("hudLayout.posY", self.posY)
        xml:setFloat("hudLayout.scale", self.scale or 1.0)
        xml:setFloat("hudLayout.widthMult", self.widthMult or 1.0)
        xml:save()
        xml:delete()
    end
end

function FuelHUD:loadLayout()
    local path = self:getLayoutPath()
    if path == nil or not fileExists(path) then
        -- First run after the move: migrate the old savegame-dir sidecar.
        path = self:getLegacyLayoutPath()
        if path == nil or not fileExists(path) then return end
    end
    local xml = XMLFile.load("fc_hud", path)
    if xml then
        self.posX      = xml:getFloat("hudLayout.posX", self.posX)
        self.posY      = xml:getFloat("hudLayout.posY", self.posY)
        self.scale     = math.max(FuelHUD.MIN_SCALE, math.min(FuelHUD.MAX_SCALE,
                             xml:getFloat("hudLayout.scale", self.scale or 1.0)))
        self.widthMult = math.max(FuelHUD.MIN_WIDTH_MULT, math.min(FuelHUD.MAX_WIDTH_MULT,
                             xml:getFloat("hudLayout.widthMult", self.widthMult or 1.0)))
        xml:delete()
        self:clampPosition()
    end
end

function FuelHUD:clampPosition()
    local w, h = self:getW(), self:getH()
    self.posX = math.max(0.0, math.min(math.max(0.0, 1.0 - w), self.posX))
    self.posY = math.max(0.0, math.min(math.max(0.0, 1.0 - h), self.posY))
end

function FuelHUD:isPointerOverHUD(posX, posY)
    return posX >= self.posX and posX <= self.posX + self:getW()
       and posY >= self.posY and posY <= self.posY + self:getH()
end

function FuelHUD:getResizeHandleRects()
    local w, h = self:getW(), self:getH()
    local hs = FuelHUD.RESIZE_HANDLE_SIZE
    return {
        bl = {x = self.posX,          y = self.posY,          w = hs, h = hs},
        br = {x = self.posX + w - hs, y = self.posY,          w = hs, h = hs},
        tl = {x = self.posX,          y = self.posY + h - hs, w = hs, h = hs},
        tr = {x = self.posX + w - hs, y = self.posY + h - hs, w = hs, h = hs},
    }
end

function FuelHUD:hitTestCorner(posX, posY)
    for key, rect in pairs(self:getResizeHandleRects()) do
        if posX >= rect.x and posX <= rect.x + rect.w
        and posY >= rect.y and posY <= rect.y + rect.h then
            return key
        end
    end
    return nil
end

function FuelHUD:hitTestEdge(posX, posY)
    local w, h = self:getW(), self:getH()
    local band = FuelHUD.EDGE_BAND_W
    if posY >= self.posY and posY <= self.posY + h then
        if posX >= self.posX - band / 2 and posX <= self.posX + band / 2 then return "left" end
        if posX >= self.posX + w - band / 2 and posX <= self.posX + w + band / 2 then return "right" end
    end
    return nil
end

--- Drag / corner-scale / edge-width while in suite edit mode.
--- Returns true when the event was consumed.
function FuelHUD:onMouseEvent(posX, posY, isDown, isUp, button)
    if not self.editMode then return false end

    if isDown and button == 1 then
        local corner = self:hitTestCorner(posX, posY)
        local edge   = self:hitTestEdge(posX, posY)
        if corner then
            self.resizing         = true
            self.isDragging       = false
            self.edgeDragging     = nil
            self.resizeStartX     = posX
            self.resizeStartY     = posY
            self.resizeStartScale = self.scale
            return true
        elseif edge then
            self.edgeDragging       = edge
            self.isDragging         = false
            self.resizing           = false
            self.edgeDragStartX     = posX
            self.edgeDragStartWidth = self.widthMult
            return true
        elseif self:isPointerOverHUD(posX, posY) then
            self.isDragging = true
            self.resizing   = false
            self.dragOffX   = posX - self.posX
            self.dragOffY   = posY - self.posY
            return true
        end
    end

    if self.isDragging then
        self.posX = math.max(0.0, math.min(1.0 - self:getW(), posX - self.dragOffX))
        self.posY = math.max(0.0, math.min(1.0 - self:getH(), posY - self.dragOffY))
        if isUp and button == 1 then
            self.isDragging = false
            self:saveLayout()
        end
        return true
    end

    if self.resizing then
        local w, h = self:getW(), self:getH()
        local cx = self.posX + w * 0.5
        local cy = self.posY + h * 0.5
        local startDist = math.sqrt((self.resizeStartX - cx)^2 + (self.resizeStartY - cy)^2)
        local currDist  = math.sqrt((posX - cx)^2 + (posY - cy)^2)
        local delta     = (currDist - startDist) * 2.5
        self.scale = math.max(FuelHUD.MIN_SCALE, math.min(FuelHUD.MAX_SCALE, self.resizeStartScale + delta))
        self:clampPosition()
        if isUp and button == 1 then
            self.resizing = false
            self:saveLayout()
        end
        return true
    end

    if self.edgeDragging then
        local dx = posX - self.edgeDragStartX
        if self.edgeDragging == "left" then dx = -dx end
        self.widthMult = math.max(FuelHUD.MIN_WIDTH_MULT, math.min(FuelHUD.MAX_WIDTH_MULT,
            self.edgeDragStartWidth + dx * FuelHUD.EDGE_SENS))
        self:clampPosition()
        if isUp and button == 1 then
            self.edgeDragging = nil
            self:saveLayout()
        end
        return true
    end

    return false
end

function FuelHUD:init()
    if createImageOverlay ~= nil then
        self.overlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    else
        FuelLogger.warning("HUD: createImageOverlay not available — background will not render")
    end
    self.initialized = true
    FuelLogger.info("HUD initialized")
end

function FuelHUD:updatePosition()
    local w, h = self:getW(), self:getH()
    local positions = {
        -- Wizard 2026-08-21: preset 1 is the factory suite home (the layout
        -- Wizard arranged in-game), replacing the old topLeft anchor. The three
        -- corner presets stay as player choices.
        factory     = { x = FuelHUD.FACTORY_X,  y = FuelHUD.FACTORY_Y },
        topRight    = { x = 1.0 - w - 0.01, y = 1.0 - h - 0.01 },
        bottomLeft  = { x = 0.01,           y = 0.01 },
        bottomRight = { x = 1.0 - w - 0.01, y = 0.01 },
    }
    local anchor = FuelSettingsSchema.HUD_POSITION_MAP[self.settings.hudPosition] or "factory"
    local pos = positions[anchor] or positions.factory
    self.posX = pos.x
    self.posY = pos.y
    self:clampPosition()
end

function FuelHUD:draw()
    if not self.initialized then return end
    if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then return end

    -- BUILD 19:38: a dragged layout from a previous session wins over the anchor
    -- preset; loaded lazily here because the savegame directory is not available
    -- at construction time (RWE pattern).
    if not self.layoutLoaded then
        self.layoutLoaded = true
        self:loadLayout()
    end

    self:drawFlash()

    -- BUILD 19:38: edit mode paints regardless of the enabled/hudEnabled gates -
    -- the escape hatch every suite panel has, so a hidden chip can be found and
    -- placed during suite layout edit.
    if (not self.settings.enabled or not self.settings.hudEnabled) and not self.editMode then return end

    local C      = FuelConstants.HUD
    local s      = self.scale or 1.0
    local w      = self:getW()
    local h      = self:getH()
    local pad    = C.PADDING * s
    local fs     = C.FONT_SIZE * s
    local price  = self.priceEngine:getDisplayPrice()
    local status = self.priceEngine:getPriceStatus()
    local col    = COLOR[status] or COLOR.normal

    -- Prefer the shared three-piece panel used by the base-game feed-mixer and
    -- implement HUDs; retain graph_pixel when MasterHUD is not installed.
    local renderer = getBaseGameRenderer()
    local usedNativePanel = renderer ~= nil and renderer.renderPanel ~= nil
        and renderer:renderPanel(self.posX, self.posY, w, h, COLOR.bg[4])
    if not usedNativePanel and self.overlay then
        setOverlayColor(self.overlay, COLOR.bg[1], COLOR.bg[2], COLOR.bg[3], COLOR.bg[4])
        renderOverlay(self.overlay, self.posX, self.posY, w, h)
    end

    -- BUILD 19:38: suite orange edit chrome (COLOR_EDIT_BORDER family) while the
    -- suite layout edit is on - pulsing border, same vocabulary as every panel.
    -- Wizard 2026-08-21: + corner scale handles and left/right edge width handles
    -- (NPCFavor/Workplace vocabulary).
    if self.editMode and self.overlay then
        local bw = 0.002
        setOverlayColor(self.overlay, 1.00, 0.60, 0.10, 0.90)
        renderOverlay(self.overlay, self.posX, self.posY + h - bw, w, bw)
        renderOverlay(self.overlay, self.posX, self.posY, w, bw)
        renderOverlay(self.overlay, self.posX, self.posY, bw, h)
        renderOverlay(self.overlay, self.posX + w - bw, self.posY, bw, h)

        for _, rect in pairs(self:getResizeHandleRects()) do
            setOverlayColor(self.overlay, 1.00, 0.60, 0.10, self.resizing and 0.95 or 0.65)
            renderOverlay(self.overlay, rect.x, rect.y, rect.w, rect.h)
        end

        local ehW   = 0.004
        local inset = h * 0.20
        setOverlayColor(self.overlay, 1.00, 0.60, 0.10, self.edgeDragging == "left" and 0.95 or 0.65)
        renderOverlay(self.overlay, self.posX - ehW / 2, self.posY + inset, ehW, h - inset * 2)
        setOverlayColor(self.overlay, 1.00, 0.60, 0.10, self.edgeDragging == "right" and 0.95 or 0.65)
        renderOverlay(self.overlay, self.posX + w - ehW / 2, self.posY + inset, ehW, h - inset * 2)
    end

    -- Label
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    renderText(self.posX + pad, self.posY + h * 0.60, fs * 0.75,
        g_i18n:getText("fc_hud_label") or "DIESEL")

    -- Price value
    setTextColor(col[1], col[2], col[3], col[4])
    setTextBold(true)
    renderText(self.posX + pad, self.posY + h * 0.15, fs,
        string.format("$%.4f/L", price))

    -- Trend indicator (ASCII — right-aligned in box)
    local trend = self.priceEngine:getTrend()
    local trendText = trend == "up" and "UP" or (trend == "down" and "DN" or "--")
    local trendCol  = trend == "up" and COLOR.expensive or (trend == "down" and COLOR.cheap or COLOR.label)
    setTextColor(trendCol[1], trendCol[2], trendCol[3], trendCol[4])
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_RIGHT)
    renderText(self.posX + w - pad, self.posY + h * 0.15, fs * 0.70, trendText)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

function FuelHUD:update(dt)
    if self.activeFlash then
        self.activeFlash.timer = self.activeFlash.timer + dt / 1000
        if self.activeFlash.timer >= self.activeFlash.duration then
            self.activeFlash = nil
        end
    end
    if not self.activeFlash and #self.flashQueue > 0 then
        self.activeFlash = table.remove(self.flashQueue, 1)
    end
end

function FuelHUD:flash(message, color, duration)
    table.insert(self.flashQueue, {
        message  = message or "",
        color    = color or COLOR.notif_def,
        timer    = 0,
        duration = duration or 4,
    })
end

function FuelHUD:drawFlash()
    if not self.activeFlash or not self.overlay then return end

    local t = self.activeFlash.timer
    local d = self.activeFlash.duration
    local alpha = 1.0
    if t < 0.25 then
        alpha = t / 0.25
    elseif t > d - 0.80 then
        alpha = math.max(0, (d - t) / 0.80)
    end

    local pulse     = 0.75 + 0.25 * math.sin(t * 5)
    local textAlpha = alpha * pulse
    local c         = self.activeFlash.color

    -- background
    setOverlayColor(self.overlay,
        COLOR.notif_bg[1], COLOR.notif_bg[2], COLOR.notif_bg[3], COLOR.notif_bg[4] * alpha)
    renderOverlay(self.overlay, NOTIF_X, NOTIF_Y, NOTIF_W, NOTIF_H)

    -- left accent bar
    setOverlayColor(self.overlay, c[1], c[2], c[3], (c[4] or 1) * alpha)
    renderOverlay(self.overlay, NOTIF_X, NOTIF_Y, 0.003, NOTIF_H)

    -- message text
    setTextColor(c[1], c[2], c[3], textAlpha)
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(NOTIF_X + 0.010, NOTIF_Y + NOTIF_H * 0.28, NOTIF_TS, self.activeFlash.message)
end

function FuelHUD:delete()
    if self.overlay then
        delete(self.overlay)
        self.overlay = nil
    end
    self.initialized = false
end

-- =========================================================
-- BUILD 17:57 + ATTN 18:02 (hot-reload guide Part 2): force-patch the live
-- instance after a Ctrl+R reload - mission.fuelCostsManager published in src/main.lua; holds .hud.
if g_currentMission ~= nil and g_currentMission.fuelCostsManager ~= nil and g_currentMission.fuelCostsManager.hud ~= nil then
    local inst = g_currentMission.fuelCostsManager.hud
    for k, v in pairs(FuelHUD) do
        if type(v) == "function" then
            inst[k] = v
        end
    end
    -- Fields new in the width wave that a pre-wave live instance lacks.
    if inst.scale     == nil then inst.scale     = 1.0 end
    if inst.widthMult == nil then inst.widthMult = 1.0 end
    -- Delivery proof in log.txt (Wizard 2026-08-21).
    print("[FuelCosts] FuelHUD hot-patched onto live instance")
end
