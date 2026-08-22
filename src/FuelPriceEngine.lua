-- =========================================================
-- FS25 Realistic Fuel Costs - FuelPriceEngine
-- =========================================================
-- Owns the current fuel price state.
-- Handles daily fluctuation, seasonal modifiers, and
-- market shock events. Server-authoritative in MP.
--
-- HOW PAYMENT WORKS (verified from FS25 LUADOC):
--   FillTrigger:fillVehicle() already calls:
--     price = delta * economyManager:getPricePerLiter(fillType)
--     g_currentMission:addMoney(-price, farmId, ...)
--   economyManager:getPricePerLiter() reads fillType.pricePerLiter
--   directly from the FillTypeDesc object.
--
--   So we just modify g_fillTypeManager:getFillTypeByName("DIESEL")
--   .pricePerLiter each day — the game's own payment system does
--   the rest. No hook into the fill event needed at all.
-- =========================================================

---@class FuelPriceEngine
FuelPriceEngine = FuelPriceEngine or {}
FuelPriceEngine.__index = FuelPriceEngine

function FuelPriceEngine.new(settings)
    local self = setmetatable({}, FuelPriceEngine)
    self.settings            = settings
    self.currentPrice        = settings.baseFuelPrice
    self.previousPrice       = settings.baseFuelPrice
    self.lastDay             = -1
    self.shockActive         = false
    self.shockMagnitude      = 0.0
    self.shockDaysLeft       = 0
    self.originalDieselPrice = nil
    self.originalDefPrice    = nil
    return self
end

-- Called once per game day (server only in MP)
function FuelPriceEngine:onDayChanged(currentDay)
    if currentDay == self.lastDay then return end
    self.lastDay = currentDay
    self.previousPrice = self.currentPrice

    local base      = self.settings.baseFuelPrice
    local diffMult  = self.settings:getDifficultyMultiplier()
    local volRate   = self.settings:getVolatilityRate()

    -- Daily random walk
    local swing = (math.random() * 2 - 1) * volRate
    self.currentPrice = self.currentPrice * (1 + swing)

    -- Seasonal modifier (applied to base, not currentPrice, to prevent compounding)
    local seasonMod = 1.0
    if self.settings.seasonalEffects then
        local season = g_currentMission and g_currentMission.environment
            and g_currentMission.environment.currentSeason or 2
        seasonMod = FuelConstants.SEASONAL[season] or 1.0
    end

    -- Market shock
    if self.settings.marketShocks then
        if self.shockActive then
            self.shockDaysLeft = self.shockDaysLeft - 1
            if self.shockDaysLeft <= 0 then
                self.shockActive = false
                self.shockMagnitude = 0.0
                FuelLogger.info("Market shock ended — price normalising")
            end
        else
            if math.random() < FuelConstants.SHOCK.CHANCE_PER_DAY then
                local C = FuelConstants.SHOCK
                local mag = C.MIN_MAGNITUDE + math.random() * (C.MAX_MAGNITUDE - C.MIN_MAGNITUDE)
                self.shockMagnitude = (math.random() > 0.5) and mag or -mag
                self.shockDaysLeft  = C.MIN_DURATION + math.floor(math.random() * (C.MAX_DURATION - C.MIN_DURATION + 1))
                self.shockActive    = true
                FuelLogger.info("Market shock! %+.0f%% for %d days", self.shockMagnitude * 100, self.shockDaysLeft)
            end
        end
        if self.shockActive then
            self.currentPrice = self.currentPrice * (1 + self.shockMagnitude)
        end
    end

    -- Clamp to [effectiveBase * MIN, effectiveBase * MAX]
    -- Difficulty and season scale the center of the price band, not the rolling price,
    -- so neither compounds across days.
    local C = FuelConstants.PRICE
    local effectiveBase = base * diffMult * seasonMod
    self.currentPrice = math.max(effectiveBase * C.MIN_MULTIPLIER, math.min(effectiveBase * C.MAX_MULTIPLIER, self.currentPrice))

    FuelLogger.debug("Day %d — fuel price: $%.4f/L", currentDay, self.currentPrice)

    -- Push the new price into the game's fill type so FillTrigger:fillVehicle()
    -- picks it up automatically via economyManager:getPricePerLiter(fillType)
    self:applyToFillTypes()
end

-- Write currentPrice into the DIESEL (and DEF) FillTypeDesc objects.
-- FillTrigger:fillVehicle() reads fillType.pricePerLiter directly —
-- changing it here is all that's needed; no payment hook required.
function FuelPriceEngine:applyToFillTypes()
    if not g_fillTypeManager then return end

    local dieselFt = g_fillTypeManager:getFillTypeByName("DIESEL")
    if dieselFt then
        if self.originalDieselPrice == nil then
            self.originalDieselPrice = dieselFt.pricePerLiter
            FuelLogger.info("Original DIESEL price: $%.4f/L", self.originalDieselPrice)
        end
        dieselFt.pricePerLiter = self.currentPrice
    end

    -- DEF tracks diesel proportionally. Store original once and compute from
    -- it each time so the ratio never compounds across days.
    local defFt = g_fillTypeManager:getFillTypeByName("DEF")
    if defFt and self.originalDieselPrice and self.originalDieselPrice > 0 then
        if self.originalDefPrice == nil then
            self.originalDefPrice = defFt.pricePerLiter
            FuelLogger.info("Original DEF price: $%.4f/L", self.originalDefPrice)
        end
        defFt.pricePerLiter = self.originalDefPrice * (self.currentPrice / self.originalDieselPrice)
    end
end

-- Restore the original pricePerLiter on mod unload
function FuelPriceEngine:restoreOriginalPrices()
    if not g_fillTypeManager then return end
    if self.originalDieselPrice then
        local ft = g_fillTypeManager:getFillTypeByName("DIESEL")
        if ft then ft.pricePerLiter = self.originalDieselPrice end
        FuelLogger.info("Restored original DIESEL price: $%.4f/L", self.originalDieselPrice)
    end
    if self.originalDefPrice then
        local ft = g_fillTypeManager:getFillTypeByName("DEF")
        if ft then ft.pricePerLiter = self.originalDefPrice end
        FuelLogger.info("Restored original DEF price: $%.4f/L", self.originalDefPrice)
    end
end

-- Returns "up", "down", or "stable" based on last day-change delta
function FuelPriceEngine:getTrend()
    local threshold = self.previousPrice * 0.005
    if self.currentPrice - self.previousPrice > threshold then
        return "up"
    elseif self.previousPrice - self.currentPrice > threshold then
        return "down"
    end
    return "stable"
end

-- Returns the display price (rounded to 4dp)
function FuelPriceEngine:getDisplayPrice()
    local precision = 10 ^ FuelConstants.PRICE.PRICE_PRECISION
    return math.floor(self.currentPrice * precision + 0.5) / precision
end

-- Returns "cheap", "normal", or "expensive" for HUD colouring
function FuelPriceEngine:getPriceStatus()
    local base = self.settings.baseFuelPrice * self.settings:getDifficultyMultiplier()
    local ratio = self.currentPrice / base
    if ratio <= FuelConstants.HUD.COLOR_CHEAP then
        return "cheap"
    elseif ratio >= FuelConstants.HUD.COLOR_EXPENSIVE then
        return "expensive"
    end
    return "normal"
end


function FuelPriceEngine:saveToXML(xmlFile, baseKey)
    if not xmlFile then return end
    xmlFile:setFloat(baseKey .. ".currentPrice",   self.currentPrice)
    xmlFile:setInt  (baseKey .. ".lastDay",         self.lastDay)
    xmlFile:setBool (baseKey .. ".shockActive",     self.shockActive)
    xmlFile:setFloat(baseKey .. ".shockMagnitude",  self.shockMagnitude)
    xmlFile:setInt  (baseKey .. ".shockDaysLeft",   self.shockDaysLeft)
end

function FuelPriceEngine:loadFromXML(xmlFile, baseKey)
    if not xmlFile then return end
    self.currentPrice   = xmlFile:getFloat(baseKey .. ".currentPrice",  self.settings.baseFuelPrice)
    self.lastDay        = xmlFile:getInt  (baseKey .. ".lastDay",        -1)
    self.shockActive    = xmlFile:getBool (baseKey .. ".shockActive",    false)
    self.shockMagnitude = xmlFile:getFloat(baseKey .. ".shockMagnitude", 0.0)
    self.shockDaysLeft  = xmlFile:getInt  (baseKey .. ".shockDaysLeft",  0)
end
