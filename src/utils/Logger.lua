-- =========================================================
-- FS25 Realistic Fuel Costs - Logger
-- =========================================================

---@class FuelLogger
FuelLogger = FuelLogger or {}

local PREFIX = "[FuelCosts]"

function FuelLogger.debug(msg, ...)
    if g_FuelCostsManager and g_FuelCostsManager.settings and g_FuelCostsManager.settings.debugMode then
        local ok, out = pcall(string.format, PREFIX .. " DEBUG: " .. msg, ...)
        print(ok and out or PREFIX .. " DEBUG: " .. tostring(msg))
    end
end

function FuelLogger.info(msg, ...)
    local ok, out = pcall(string.format, PREFIX .. " " .. msg, ...)
    print(ok and out or PREFIX .. " " .. tostring(msg))
end

function FuelLogger.warning(msg, ...)
    local ok, out = pcall(string.format, PREFIX .. " WARNING: " .. msg, ...)
    print(ok and out or PREFIX .. " WARNING: " .. tostring(msg))
end

function FuelLogger.error(msg, ...)
    local ok, out = pcall(string.format, PREFIX .. " ERROR: " .. msg, ...)
    print(ok and out or PREFIX .. " ERROR: " .. tostring(msg))
end
