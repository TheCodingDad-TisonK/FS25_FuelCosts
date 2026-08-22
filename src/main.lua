-- =========================================================
-- FS25 Realistic Fuel Costs - Entry Point
-- =========================================================
-- Loads all modules in dependency order, hooks FS25 mission
-- lifecycle events, and drives the update/draw loops.
-- =========================================================
-- Author: TisonK
-- =========================================================

-- Hot-reload safety (proven live 2026-08-21 20:41 and 20:44: re-source died at
-- the first source() concat): g_currentModDirectory/g_currentModName are only
-- set during the initial mod load pass and are nil on a live re-source. Latch
-- into module globals on first load, and fall back to g_modsDirectory plus the
-- known loose-folder name for a live session whose boot predates the latch
-- (g_modsDirectory is engine-provided and already used live by CsRfPdaGuest).
FcModDirectory = FcModDirectory
    or g_currentModDirectory
    or (g_modsDirectory ~= nil and (g_modsDirectory .. "FS25_FuelCosts/") or nil)
FcModName      = FcModName or g_currentModName or "FS25_FuelCosts"
local modDirectory = FcModDirectory
local modName      = FcModName

-- -------------------------------------------------------
-- Phase 1 - Utilities & Config
-- -------------------------------------------------------
source(modDirectory .. "src/utils/Logger.lua")
source(modDirectory .. "src/config/Constants.lua")
source(modDirectory .. "src/config/SettingsSchema.lua")
source(modDirectory .. "src/integrations/OptionScalingResolver.lua")

-- -------------------------------------------------------
-- Phase 2 - Settings
-- -------------------------------------------------------
source(modDirectory .. "src/settings/Settings.lua")
source(modDirectory .. "src/settings/SettingsManager.lua")

-- -------------------------------------------------------
-- Phase 3 - Core Systems
-- -------------------------------------------------------
source(modDirectory .. "src/FuelPriceEngine.lua")
source(modDirectory .. "src/FuelHUD.lua")
source(modDirectory .. "src/ui/FuelSettingsPanel.lua")

-- -------------------------------------------------------
-- Phase 4 - Network
-- -------------------------------------------------------
source(modDirectory .. "src/network/NetworkEvents.lua")

-- -------------------------------------------------------
-- Phase 5 - Manager (depends on all of the above)
-- -------------------------------------------------------
source(modDirectory .. "src/FuelCostsManager.lua")

-- -------------------------------------------------------
-- Phase 6 - Bedrock bridges (optional, delegate-when-present)
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
    -- Reload safety: a re-sourced copy of this file stacks another prepended
    -- load hook whose local fcm is nil. Resolve the live manager first so a
    -- stacked copy adopts it instead of creating a second manager.
    fcm = g_FuelCostsManager or mission.fuelCostsManager or fcm
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
    -- Reload safety: stacked copies of this hook must not init/register twice
    -- for the same mission. The flag lives on the manager, which is discarded
    -- on mission delete, so the next real mission load initializes normally.
    if fcm.__missionInitDone then return end
    fcm.__missionInitDone = true
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
-- Mouse event handler - settings panel eats input when open
-- -------------------------------------------------------
-- Reload-safe (hot-reload law): the handler table is a module global so a
-- re-source rebinds mouseEvent on the SAME registered table, and the manager is
-- resolved live on every event instead of captured. The old shape captured the
-- local fcm as an upvalue - a re-sourced copy holds fcm = nil forever, which is
-- why the 19:38 suite-edit drag never reached FuelHUD (orange chrome, no move).
-- Registration runs once per game session, guarded by a module-global flag.
FcMouseHandler = FcMouseHandler or {}
function FcMouseHandler:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    local mgr = g_FuelCostsManager
        or (g_currentMission ~= nil and g_currentMission.fuelCostsManager or nil)
    if mgr == nil then return eventUsed end
    if mgr.settingsPanel and mgr.settingsPanel:isOpen() then
        local consumed = mgr.settingsPanel:onMouseEvent(posX, posY, isDown, isUp, button, eventUsed)
        return consumed or eventUsed
    end
    -- BUILD 19:38: route mouse to the HUD while suite layout edit is on (drag to
    -- move). The settings-panel path above keeps priority when it is open.
    if mgr.hud and mgr.hud.editMode and mgr.hud.onMouseEvent then
        local consumed = mgr.hud:onMouseEvent(posX, posY, isDown, isUp, button)
        return consumed or eventUsed
    end
    return eventUsed
end
if not FcMouseHandlerRegistered then
    FcMouseHandlerRegistered = true
    addModEventListener(FcMouseHandler)
end
FuelLogger.info("Mouse routing bound (reload-safe, live-resolved manager)")

-- -------------------------------------------------------
-- Input action registration - FC_OPEN_SETTINGS opens settings panel (player-assigned key)
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
            FuelLogger.info("Settings panel (FC_OPEN_SETTINGS) registered in PLAYER context")
        end

        g_inputBinding:endActionEventsModification()
    end
    FuelLogger.info("PlayerInputComponent hook installed for FC_OPEN_SETTINGS")
end

-- -------------------------------------------------------
-- Vehicle context - hook InputBinding.endActionEventsModification
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
            FuelLogger.info("Settings panel (FC_OPEN_SETTINGS) registered in VEHICLE context")
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
