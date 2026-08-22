-- =========================================================
-- FS25 Realistic Fuel Costs - Settings
-- =========================================================

---@class FuelSettings
FuelSettings = {}
FuelSettings.__index = FuelSettings

function FuelSettings.new()
    local self = setmetatable({}, FuelSettings)

    -- Auto-populate defaults from schema
    for _, def in ipairs(FuelSettingsSchema.definitions) do
        self[def.id] = def.default
    end

    return self
end

function FuelSettings:validate()
    local C = FuelConstants
    self.baseFuelPrice  = math.max(0.10, math.min(10.0, self.baseFuelPrice or C.PRICE.DEFAULT_BASE))
    self.difficulty     = math.max(1, math.min(3, self.difficulty or 2))
    self.priceVolatility = math.max(1, math.min(4, self.priceVolatility or 2))
    self.hudPosition    = math.max(1, math.min(4, self.hudPosition or 1))
end

FuelSettings.SPINE_PRICE_MULT = {
    id   = "fc_priceMultiplier",
    dial = "economy",
    base = 1.0,
}

function FuelSettings:getDifficultyMultiplier()
    if OptionScalingResolver ~= nil then
        local hub = (g_currentMission ~= nil and g_currentMission.settingsHub) or g_settingsHub
        local profile = OptionScalingResolver.readProfile(hub)
        if profile ~= nil then
            return OptionScalingResolver.resolve(FuelSettings.SPINE_PRICE_MULT, profile)
        end
    end
    local key = FuelSettingsSchema.DIFFICULTY_MAP[self.difficulty] or "REALISTIC"
    return FuelConstants.DIFFICULTY[key] or 1.0
end

function FuelSettings:getVolatilityRate()
    local key = FuelSettingsSchema.VOLATILITY_MAP[self.priceVolatility] or "MEDIUM"
    return FuelConstants.VOLATILITY[key] or 0.07
end
