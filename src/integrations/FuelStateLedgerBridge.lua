-- =========================================================
-- FS25 Realistic Fuel Costs - StateLedger bridge
-- =========================================================
-- Author: TisonK
-- =========================================================
-- Optional bridge to FS25_StateLedger. Fuel Costs ships standalone, so this is
-- strictly delegate-when-present:
--   * StateLedger installed -> the master save file is the LOAD source of truth for
--     the fuel PRICE state (FS25_FuelCosts.xml is still written every save as a
--     safety copy, so removing the ledger later never loses data).
--   * StateLedger absent    -> nothing changes; FS25_FuelCosts.xml is primary.
--
-- Only the durable PRICE state lives here (currentPrice, lastDay, shock state),
-- mirroring exactly what FuelPriceEngine:saveToXML writes. The mod SETTINGS stay
-- with SettingsHub (FuelSettingsHubBridge), matching the state-to-StateLedger /
-- settings-to-SettingsHub split every ecosystem mod follows.
--
-- On the first load after installing the ledger onto an existing save the ledger
-- has no block yet (deserialize delivers nil), so init() keeps the price it loaded
-- from FS25_FuelCosts.xml. From then on the ledger carries the price.
--
-- The cross-mod handle is g_currentMission.stateLedger. We force an idempotent
-- parseFile() right after registering so deserialize delivers NOW, before we apply
-- the price below in the same phase (the hook-order timing gotcha).
-- =========================================================

FuelStateLedgerBridge = FuelStateLedgerBridge or {}

-- Provisional module id. This is the persistence KEY inside the master file, so it
-- must be locked with Claude(A) before any release (a later rename orphans saved
-- price state). This is the id the FuelCosts Point-4 doc specifies.
FuelStateLedgerBridge.MODULE_ID = "FuelCosts_Price"
FuelStateLedgerBridge.SCHEMA    = 1

FuelStateLedgerBridge.active       = false
FuelStateLedgerBridge.delivered    = false
FuelStateLedgerBridge.pendingState = nil

-- Build the price state. Mirrors exactly what FuelPriceEngine:saveToXML writes.
function FuelStateLedgerBridge.buildState(mgr)
    local out = { schema = FuelStateLedgerBridge.SCHEMA }
    local pe = mgr ~= nil and mgr.priceEngine or nil
    if pe ~= nil then
        out.currentPrice   = pe.currentPrice
        out.lastDay        = pe.lastDay
        out.shockActive    = pe.shockActive
        out.shockMagnitude = pe.shockMagnitude
        out.shockDaysLeft  = pe.shockDaysLeft
    end
    return out
end

-- Apply the cached ledger price into the engine, then push it to the DIESEL fill
-- type. Twin of FuelPriceEngine:loadFromXML reading from the table.
function FuelStateLedgerBridge.applyState(mgr)
    local data = FuelStateLedgerBridge.pendingState
    if type(data) ~= "table" or mgr == nil or mgr.priceEngine == nil then return false end
    local pe = mgr.priceEngine

    if data.currentPrice   ~= nil then pe.currentPrice   = data.currentPrice   end
    if data.lastDay        ~= nil then pe.lastDay        = data.lastDay        end
    if data.shockActive    ~= nil then pe.shockActive    = data.shockActive    end
    if data.shockMagnitude ~= nil then pe.shockMagnitude = data.shockMagnitude end
    if data.shockDaysLeft  ~= nil then pe.shockDaysLeft  = data.shockDaysLeft  end

    -- Re-push the loaded price onto the DIESEL fill type (init() already applied the
    -- XML price; this overrides it with the ledger's authoritative value).
    if pe.applyToFillTypes ~= nil then
        pe:applyToFillTypes()
    end
    return true
end

function FuelStateLedgerBridge.hasLedgerState()
    return FuelStateLedgerBridge.active
        and FuelStateLedgerBridge.delivered
        and FuelStateLedgerBridge.pendingState ~= nil
end

-- Register with StateLedger if present, then force an idempotent parseFile so
-- deserialize delivers now. No-op if StateLedger is absent.
function FuelStateLedgerBridge.register(mgr)
    FuelStateLedgerBridge.active       = false
    FuelStateLedgerBridge.delivered    = false
    FuelStateLedgerBridge.pendingState = nil

    local ledger = (g_currentMission ~= nil and g_currentMission.stateLedger) or g_stateLedger
    if ledger == nil then
        FuelLogger.info("StateLedger not detected; fuel price uses its own FS25_FuelCosts.xml")
        return
    end
    if mgr == nil then return end

    local ok, err = pcall(function()
        ledger:registerModule(FuelStateLedgerBridge.MODULE_ID, {
            serialize = function()
                return FuelStateLedgerBridge.buildState(mgr)
            end,
            deserialize = function(data)
                FuelStateLedgerBridge.delivered    = true
                FuelStateLedgerBridge.pendingState = data   -- nil on a brand-new save
            end,
        })
        if ledger.parseFile ~= nil then
            ledger:parseFile()
        end
    end)

    if ok then
        FuelStateLedgerBridge.active = true
        FuelLogger.info("Registered with StateLedger as '%s' (FS25_FuelCosts.xml kept as safety copy)",
            FuelStateLedgerBridge.MODULE_ID)
    else
        FuelLogger.warning("StateLedger registration failed: %s (falling back to own XML)", tostring(err))
    end
end
