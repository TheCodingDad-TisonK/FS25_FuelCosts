-- =========================================================
-- FS25 Realistic Fuel Costs - SettingsManager
-- =========================================================
-- Handles XML save/load, auto-driven by SettingsSchema.
-- =========================================================

---@class FuelSettingsManager
FuelSettingsManager = FuelSettingsManager or {}
FuelSettingsManager.__index = FuelSettingsManager

function FuelSettingsManager.new(settings)
    local self = setmetatable({}, FuelSettingsManager)
    self.settings = settings
    return self
end

function FuelSettingsManager:saveToXML(xmlFile, baseKey)
    if not xmlFile or not self.settings then return end
    for _, def in ipairs(FuelSettingsSchema.definitions) do
        local key = baseKey .. "." .. def.id
        local val = self.settings[def.id]
        if def.type == "bool" then
            xmlFile:setBool(key, val)
        elseif def.type == "int" then
            xmlFile:setInt(key, val)
        elseif def.type == "float" then
            xmlFile:setFloat(key, val)
        end
    end
end

function FuelSettingsManager:loadFromXML(xmlFile, baseKey)
    if not xmlFile or not self.settings then return end
    for _, def in ipairs(FuelSettingsSchema.definitions) do
        local key = baseKey .. "." .. def.id
        local val
        if def.type == "bool" then
            val = xmlFile:getBool(key, def.default)
        elseif def.type == "int" then
            val = xmlFile:getInt(key, def.default)
        elseif def.type == "float" then
            val = xmlFile:getFloat(key, def.default)
        end
        if val ~= nil then
            self.settings[def.id] = val
        end
    end
    self.settings:validate()
end
