-- =========================================================
-- FS25 Realistic Fuel Costs - NetworkEvents
-- =========================================================
-- Events:
--   FuelPriceSyncEvent      Server → Clients   broadcast price on day change
--   FuelSettingSyncEvent    Server → Clients   broadcast setting changes
--   FuelSettingChangeEvent  Client → Server    request a setting change (admin validated)
--   FuelRequestSyncEvent    Client → Server    request full state on join
-- =========================================================

-- -------------------------------------------------------
-- FuelPriceSyncEvent  (Server → Clients)
-- -------------------------------------------------------
FuelPriceSyncEvent = FuelPriceSyncEvent or {}
local FuelPriceSyncEvent_mt = Class(FuelPriceSyncEvent, Event)
InitEventClass(FuelPriceSyncEvent, "FuelPriceSyncEvent")

function FuelPriceSyncEvent.emptyNew()
    return Event.new(FuelPriceSyncEvent_mt)
end

function FuelPriceSyncEvent.new(currentPrice, shockActive, shockDaysLeft)
    local self = FuelPriceSyncEvent.emptyNew()
    self.currentPrice  = currentPrice  or 1.20
    self.shockActive   = shockActive   or false
    self.shockDaysLeft = shockDaysLeft or 0
    return self
end

function FuelPriceSyncEvent:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self.currentPrice)
    streamWriteBool(streamId, self.shockActive)
    streamWriteInt8(streamId, self.shockDaysLeft)
end

function FuelPriceSyncEvent:readStream(streamId, connection)
    self.currentPrice  = streamReadFloat32(streamId)
    self.shockActive   = streamReadBool(streamId)
    self.shockDaysLeft = streamReadInt8(streamId)
    self:run(connection)
end

function FuelPriceSyncEvent:run(connection)
    if g_FuelCostsManager and g_FuelCostsManager.priceEngine then
        local pe = g_FuelCostsManager.priceEngine
        pe.currentPrice  = self.currentPrice
        pe.shockActive   = self.shockActive
        pe.shockDaysLeft = self.shockDaysLeft
        pe:applyToFillTypes()
        FuelLogger.debug("Price sync received: $%.4f/L", self.currentPrice)
    end
end

-- -------------------------------------------------------
-- FuelSettingChangeEvent  (Client → Server)
-- -------------------------------------------------------
FuelSettingChangeEvent = FuelSettingChangeEvent or {}
local FuelSettingChangeEvent_mt = Class(FuelSettingChangeEvent, Event)
InitEventClass(FuelSettingChangeEvent, "FuelSettingChangeEvent")

function FuelSettingChangeEvent.emptyNew()
    return Event.new(FuelSettingChangeEvent_mt)
end

function FuelSettingChangeEvent.new(settingId, value)
    local self = FuelSettingChangeEvent.emptyNew()
    self.settingId = settingId or ""
    self.value     = value
    return self
end

function FuelSettingChangeEvent.sendToServer(settingId, value)
    if g_server ~= nil then
        FuelSettingChangeEvent.execute(settingId, value)
    else
        g_client:getServerConnection():sendEvent(
            FuelSettingChangeEvent.new(settingId, value)
        )
    end
end

function FuelSettingChangeEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.settingId)
    streamWriteString(streamId, tostring(self.value))
end

function FuelSettingChangeEvent:readStream(streamId, connection)
    self.settingId = streamReadString(streamId)
    self.valueStr  = streamReadString(streamId)
    self:run(connection)
end

function FuelSettingChangeEvent.execute(settingId, valueStr)
    -- TODO: validate admin, apply setting, broadcast FuelSettingSyncEvent
end

function FuelSettingChangeEvent:run(connection)
    if not connection:getIsServer() then return end
    FuelSettingChangeEvent.execute(self.settingId, self.valueStr)
end

-- -------------------------------------------------------
-- FuelSettingSyncEvent  (Server → Clients)
-- -------------------------------------------------------
FuelSettingSyncEvent = FuelSettingSyncEvent or {}
local FuelSettingSyncEvent_mt = Class(FuelSettingSyncEvent, Event)
InitEventClass(FuelSettingSyncEvent, "FuelSettingSyncEvent")

function FuelSettingSyncEvent.emptyNew()
    return Event.new(FuelSettingSyncEvent_mt)
end

function FuelSettingSyncEvent.new(settingId, value)
    local self = FuelSettingSyncEvent.emptyNew()
    self.settingId = settingId or ""
    self.value     = value
    return self
end

function FuelSettingSyncEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.settingId)
    streamWriteString(streamId, tostring(self.value))
end

function FuelSettingSyncEvent:readStream(streamId, connection)
    self.settingId = streamReadString(streamId)
    self.valueStr  = streamReadString(streamId)
    self:run(connection)
end

function FuelSettingSyncEvent:run(connection)
    -- TODO: apply received setting to local FuelSettings instance
end

-- -------------------------------------------------------
-- FuelRequestSyncEvent  (Client → Server)
-- -------------------------------------------------------
FuelRequestSyncEvent = FuelRequestSyncEvent or {}
local FuelRequestSyncEvent_mt = Class(FuelRequestSyncEvent, Event)
InitEventClass(FuelRequestSyncEvent, "FuelRequestSyncEvent")

function FuelRequestSyncEvent.emptyNew()
    return Event.new(FuelRequestSyncEvent_mt)
end

function FuelRequestSyncEvent.new()
    return FuelRequestSyncEvent.emptyNew()
end

function FuelRequestSyncEvent:writeStream(streamId, connection) end

function FuelRequestSyncEvent:readStream(streamId, connection)
    self:run(connection)
end

function FuelRequestSyncEvent:run(connection)
    if not connection:getIsServer() then return end
    -- Server responds to joining client with full price snapshot
    if g_FuelCostsManager and g_FuelCostsManager.priceEngine then
        local pe = g_FuelCostsManager.priceEngine
        connection:sendEvent(
            FuelPriceSyncEvent.new(pe.currentPrice, pe.shockActive, pe.shockDaysLeft)
        )
    end
end

-- -------------------------------------------------------
-- Registration (called once after mission loads)
-- -------------------------------------------------------
function FuelNetworkEvents_Register()
    -- InitEventClass handles registration at file load time.
    -- This function remains as a load-confirmation signal.
    FuelLogger.info("Network events registered")
end
