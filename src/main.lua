-- =========================================================
-- FS25 Realistic Fuel Costs - Entry Point
-- =========================================================
-- Loads all modules in dependency order, hooks FS25 mission
-- lifecycle events, and drives the update/draw loops.
-- =========================================================
-- Author: TisonK
-- =========================================================

local modDirectory = g_currentModDirectory
local modName      = g_currentModName

-- -------------------------------------------------------
-- Phase 1 — Utilities & Config
-- -------------------------------------------------------
source(modDirectory .. "src/utils/Logger.lua")
source(modDirectory .. "src/config/Constants.lua")
source(modDirectory .. "src/config/SettingsSchema.lua")
source(modDirectory .. "src/integrations/OptionScalingResolver.lua")

-- -------------------------------------------------------
-- Phase 2 — Settings
-- -------------------------------------------------------
source(modDirectory .. "src/settings/Settings.lua")
source(modDirectory .. "src/settings/SettingsManager.lua")

-- -------------------------------------------------------
-- Phase 3 — Core Systems
-- -------------------------------------------------------
source(modDirectory .. "src/FuelPriceEngine.lua")
source(modDirectory .. "src/FuelHUD.lua")
source(modDirectory .. "src/ui/FuelSettingsPanel.lua")

-- -------------------------------------------------------
-- Phase 4 — Network
-- -------------------------------------------------------
source(modDirectory .. "src/network/NetworkEvents.lua")

-- -------------------------------------------------------
-- Phase 5 — Manager (depends on all of the above)
-- -------------------------------------------------------
source(modDirectory .. "src/FuelCostsManager.lua")

-- -------------------------------------------------------
-- Phase 6 — Bedrock bridges (optional, delegate-when-present)
-- -------------------------------------------------------
source(modDirectory .. "src/integrations/FuelStateLedgerBridge.lua")
source(modDirectory .. "src/integrations/FuelNetworkSyncBridge.lua")
source(modDirectory .. "src/integrations/FuelSettingsHubBridge.lua")
source(modDirectory .. "src/integrations/FuelMasterHUDBridge.lua")

-- -------------------------------------------------------
-- Lifecycle state
-- -------------------------------------------------------
local fcm = nil

local function isEnabled()
    return fcm ~= nil
end

-- -------------------------------------------------------
-- Mission00.load  (create manager)
-- -------------------------------------------------------
local function load(mission)
    if mission.cancelLoading then return end
    if fcm == nil then
        fcm = FuelCostsManager.new()
        getfenv(0)["g_FuelCostsManager"] = fcm
        mission.fuelCostsManager = fcm
    end
end

-- -------------------------------------------------------
-- Mission00.loadMission00Finished  (init + MP sync)
-- -------------------------------------------------------
local function loadedMission(mission, node)
    if not isEnabled() or mission.cancelLoading then return end
    fcm:init()

    -- Bedrock bridges (delegate-when-present; each no-ops if its bedrock mod is
    -- absent). Handles are published by the bedrock mods at Mission00.load. When
    -- StateLedger carries a price block it overrides the price just loaded from
    -- FS25_FuelCosts.xml; the own XML stays the safety copy.
    FuelStateLedgerBridge.register(fcm)
    if FuelStateLedgerBridge.hasLedgerState() then
        FuelStateLedgerBridge.applyState(fcm)
    end
    FuelSettingsHubBridge.register(fcm)
    FuelMasterHUDBridge.register(fcm)
    FuelNetworkSyncBridge.register(fcm)

    fcm:registerConsoleCommands()
    -- Client join sync: when NetworkSync is active it delivers the full price state
    -- to joining clients, so the own request event is only the fallback path.
    if g_client ~= nil and g_server == nil and not FuelNetworkSyncBridge.active then
        g_client:getServerConnection():sendEvent(FuelRequestSyncEvent.new())
    end
end

-- -------------------------------------------------------
-- FSBaseMission.delete  (cleanup)
-- -------------------------------------------------------
local function unload()
    if fcm ~= nil then
        fcm:delete()
        fcm = nil
        getfenv(0)["g_FuelCostsManager"] = nil
        if g_currentMission then
            g_currentMission.fuelCostsManager = nil
        end
    end
end

-- -------------------------------------------------------
-- Wire lifecycle hooks (SoilFertilizer direct-assign pattern)
-- -------------------------------------------------------
Mission00.load                  = Utils.prependedFunction(Mission00.load,                  load)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished,  loadedMission)
FSBaseMission.delete            = Utils.prependedFunction(FSBaseMission.delete,            unload)

FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function(mission, dt)
    if fcm then fcm:update(dt) end
end)

-- renderOverlay/renderText are ONLY valid inside a draw callback (not update)
FSBaseMission.draw = Utils.appendedFunction(FSBaseMission.draw, function(mission)
    -- When MasterHUD is present it owns the single draw loop (our draw was registered
    -- as a self-draw via the bridge); stand down so the HUD never draws twice.
    if FuelMasterHUDBridge ~= nil and FuelMasterHUDBridge.active then return end
    if FuelMasterHUDBridge ~= nil then
        FuelMasterHUDBridge.drawStack()
        return
    end
    if not mission.isRunning then return end
    if fcm and fcm.hud then
        fcm.hud:draw()
    end
    if fcm and fcm.settingsPanel then
        fcm.settingsPanel:draw()
    end
end)

-- -------------------------------------------------------
-- Save hook
-- -------------------------------------------------------
if FSCareerMissionInfo and FSCareerMissionInfo.saveToXMLFile then
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
        FSCareerMissionInfo.saveToXMLFile,
        function(missionInfo)
            if g_currentMission and g_currentMission.missionDynamicInfo
               and g_currentMission.missionDynamicInfo.isMultiplayer then
                if g_server == nil then return end
            end
            if fcm then fcm:save() end
        end
    )
end

-- -------------------------------------------------------
-- Mouse event handler — settings panel eats input when open
-- -------------------------------------------------------
local fcMouseHandler = {}
function fcMouseHandler:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if fcm and fcm.settingsPanel and fcm.settingsPanel:isOpen() then
        local consumed = fcm.settingsPanel:onMouseEvent(posX, posY, isDown, isUp, button, eventUsed)
        return consumed or eventUsed
    end
    return eventUsed
end
addModEventListener(fcMouseHandler)

-- -------------------------------------------------------
-- Input action registration — Shift+F opens settings panel
-- Hook PlayerInputComponent.registerActionEvents so our
-- action is registered whenever the player spawns/respawns.
-- -------------------------------------------------------
if PlayerInputComponent and PlayerInputComponent.registerActionEvents then
    local _originalRegister = PlayerInputComponent.registerActionEvents
    PlayerInputComponent.registerActionEvents = function(inputComponent, ...)
        _originalRegister(inputComponent, ...)

        if not (g_inputBinding and g_FuelCostsManager and g_FuelCostsManager.settingsPanel) then
            return
        end
        if g_FuelCostsManager.settingsPanelEventId then
            local ok, _ = pcall(function()
                return g_inputBinding:getActionEventDisplayName(g_FuelCostsManager.settingsPanelEventId)
            end)
            if ok then return end
            g_FuelCostsManager.settingsPanelEventId = nil
        end

        g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)

        local ok, evId = g_inputBinding:registerActionEvent(
            InputAction.FC_OPEN_SETTINGS,
            g_FuelCostsManager,
            g_FuelCostsManager.onOpenSettingsInput,
            false, true, false, true
        )
        if ok and evId then
            g_FuelCostsManager.settingsPanelEventId = evId
            g_inputBinding:setActionEventTextVisibility(evId, false)
            FuelLogger.info("Settings panel (Shift+F) registered in PLAYER context")
        end

        g_inputBinding:endActionEventsModification()
    end
    FuelLogger.info("PlayerInputComponent hook installed for FC_OPEN_SETTINGS")
end

-- -------------------------------------------------------
-- Vehicle context — hook InputBinding.endActionEventsModification
-- (Vehicle.registerActionEvents is already copied to each instance
--  at spawn time and can't be patched after vehicles exist.)
-- -------------------------------------------------------
if InputBinding and InputBinding.endActionEventsModification then
    local _fcVehicleHookActive = false
    local _originalEndMod = InputBinding.endActionEventsModification
    InputBinding.endActionEventsModification = function(binding, ignoreCheck)
        local contextName = ""
        if binding.registrationContext and
           binding.registrationContext ~= InputBinding.NO_REGISTRATION_CONTEXT then
            contextName = binding.registrationContext.name or ""
        end

        _originalEndMod(binding, ignoreCheck)

        if contextName ~= Vehicle.INPUT_CONTEXT_NAME then return end
        if _fcVehicleHookActive then return end
        if not (g_FuelCostsManager and g_FuelCostsManager.settingsPanel) then return end

        _fcVehicleHookActive = true
        binding:beginActionEventsModification(Vehicle.INPUT_CONTEXT_NAME)

        local ok, evId = binding:registerActionEvent(
            InputAction.FC_OPEN_SETTINGS,
            g_FuelCostsManager,
            g_FuelCostsManager.onOpenSettingsInput,
            false, true, false, true
        )
        if ok and evId then
            g_FuelCostsManager.vehicleSettingsPanelEventId = evId
            binding:setActionEventTextVisibility(evId, false)
            FuelLogger.info("Settings panel (Shift+F) registered in VEHICLE context")
        end

        binding:endActionEventsModification()
        _fcVehicleHookActive = false
    end
    FuelLogger.info("InputBinding hook installed for VEHICLE context")
end

print("========================================")
print("  FS25 Realistic Fuel Costs LOADED      ")
print("  Dynamic diesel price simulation       ")
print("  Type 'FuelCostsInfo' in console       ")
print("========================================")
