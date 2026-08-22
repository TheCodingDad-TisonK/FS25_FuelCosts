-- =========================================================
-- FS25 Realistic Fuel Costs - NetworkSync bridge
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Optional bridge to FS25_NetworkSync. Fuel Costs ships standalone, so this is
-- delegate-when-present:
--   * NetworkSync installed -> the daily price broadcast and the join-time full
--     sync route through NetworkSync's batched cycle instead of the own event
--     classes. The price is a small, once-a-day-changing value, so this is a pure
--     FULL-snapshot module (no deltas).
--   * NetworkSync absent    -> nothing changes; the own FuelPriceSyncEvent /
--     FuelRequestSyncEvent carry the price exactly as before.
--
-- onWriteState / onReadState mirror FuelPriceSyncEvent exactly (currentPrice,
-- shockActive, shockDaysLeft) so client behaviour is identical on either path.
-- NetworkSync is transport, not persistence, so the module id / channel are not a
-- save key: server and client always run the same registerModule call, so they
-- agree regardless. The names still want a lock for cross-mod consistency.
--
-- The cross-mod handle is g_currentMission.networkSync (g_networkSync is also a
-- real global here, kept as the fallback).
-- =========================================================

FuelNetworkSyncBridge = FuelNetworkSyncBridge or {}

-- registerModule id + wire channel. Follows the MarketDynamics precedent
-- (registerModule id FS25_<Mod>, channel <Mod>_Sync). Provisional pending the lock;
-- NOT a persistence key, so a rename cannot orphan saved data.
FuelNetworkSyncBridge.MODULE_ID = "FS25_FuelCosts"
FuelNetworkSyncBridge.CHANNEL   = "FuelCosts_Sync"

FuelNetworkSyncBridge.active = false
FuelNetworkSyncBridge._ns    = nil     -- cached handle for syncNow

-- Server: full price snapshot as a flat array. NetworkSync type-tags each value, so
-- the float price, the bool, and the int day count all round-trip exactly.
local function onWriteState()
    local mgr = g_FuelCostsManager
    local pe = mgr ~= nil and mgr.priceEngine or nil
    if pe == nil then return { 1.20, false, 0 } end
    return { pe.currentPrice, pe.shockActive, pe.shockDaysLeft }
end

-- Client: apply the snapshot. Twin of FuelPriceSyncEvent:run.
local function onReadState(arr)
    if type(arr) ~= "table" then return end
    local mgr = g_FuelCostsManager
    local pe = mgr ~= nil and mgr.priceEngine or nil
    if pe == nil then return end
    if arr[1] ~= nil then pe.currentPrice  = arr[1] end
    if arr[2] ~= nil then pe.shockActive   = arr[2] end
    if arr[3] ~= nil then pe.shockDaysLeft = arr[3] end
    pe:applyToFillTypes()
end

-- Server: push the current price immediately (called from _broadcastPrice on a day
-- change). No-op unless the bridge is active.
function FuelNetworkSyncBridge.syncNow()
    if not FuelNetworkSyncBridge.active or FuelNetworkSyncBridge._ns == nil then return false end
    FuelNetworkSyncBridge._ns:syncNow(FuelNetworkSyncBridge.MODULE_ID)
    return true
end

function FuelNetworkSyncBridge.register(mgr)
    FuelNetworkSyncBridge.active = false
    FuelNetworkSyncBridge._ns    = nil

    local ns = (g_currentMission ~= nil and g_currentMission.networkSync) or g_networkSync
    if ns == nil then
        FuelLogger.info("NetworkSync not detected; fuel price uses its own sync events")
        return
    end

    local ok, err = pcall(function()
        ns:registerModule(FuelNetworkSyncBridge.MODULE_ID, {
            channel      = FuelNetworkSyncBridge.CHANNEL,
            onWriteState = onWriteState,
            onReadState  = onReadState,
        })
    end)

    if ok then
        FuelNetworkSyncBridge.active = true
        FuelNetworkSyncBridge._ns    = ns
        FuelLogger.info("Registered fuel price with NetworkSync (channel %s)", FuelNetworkSyncBridge.CHANNEL)
    else
        FuelLogger.warning("NetworkSync registration failed: %s (using own sync events)", tostring(err))
    end
end
