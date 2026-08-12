-- =========================================================
-- FS25 Realistic Fuel Costs - MasterHUD bridge
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Optional bridge to FS25_MasterHUD. Fuel Costs ships standalone, so this is
-- delegate-when-present:
--   * MasterHUD installed -> FC registers its HUD draw (price HUD + settings panel)
--     as a self-draw. MasterHUD then owns the single draw loop, the menu/dialog
--     suspend, and cross-mod ordering.
--   * MasterHUD absent -> FC's own FSBaseMission.draw hook runs the exact same draw.
--
-- MasterHUD owns draw ordering + suspend only, not layout and not input, so the
-- panel keeps positioning itself and the mouse/settings input stays on FC's own
-- handlers. drawStack() is the single source of the draw body, shared with the
-- fallback hook so the two paths can never diverge.
-- =========================================================

FuelMasterHUDBridge = {}

FuelMasterHUDBridge.HUD_ID = "FuelCosts_HUD"
FuelMasterHUDBridge.active = false   -- MasterHUD present and we registered

-- The FC HUD draw body. Same calls the standalone FSBaseMission.draw hook makes,
-- including the mission.isRunning guard (resolved from g_currentMission here).
function FuelMasterHUDBridge.drawStack()
    -- Suite hide: MasterHUD # key. No-op when MasterHUD absent.
    local mh = (g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD
    if mh ~= nil and mh.areHudsHidden ~= nil and mh:areHudsHidden() then return end
    local fcm = g_FuelCostsManager
    if fcm == nil then return end
    if g_currentMission == nil or not g_currentMission.isRunning then return end
    if fcm.hud then fcm.hud:draw() end
    if fcm.settingsPanel then fcm.settingsPanel:draw() end
end

-- Register with MasterHUD if present. Called at loadMission00Finished, after the
-- HUD has published its g_currentMission handle (Mission00.load).
function FuelMasterHUDBridge.register(mgr)
    FuelMasterHUDBridge.active = false

    local hud = (g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD
    if hud == nil then
        FuelLogger.info("MasterHUD not detected; fuel HUD uses its own draw hook")
        return
    end

    local ok, err = pcall(function()
        hud:subscribe(FuelMasterHUDBridge.HUD_ID, {
            draw = FuelMasterHUDBridge.drawStack,
        })
    end)

    if ok then
        FuelMasterHUDBridge.active = true
        FuelLogger.info("Registered fuel HUD with MasterHUD (single draw loop + menu-suspend)")
    else
        FuelLogger.warning("MasterHUD registration failed: %s (using own draw hook)", tostring(err))
    end
end
