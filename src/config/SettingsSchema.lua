-- =========================================================
-- FS25 Realistic Fuel Costs - SettingsSchema
-- =========================================================
-- Single source of truth for all settings.
-- Drives Settings defaults, SettingsManager XML save/load,
-- and the in-game UI generation.
-- =========================================================

FuelSettingsSchema = {}

FuelSettingsSchema.definitions = {
    -- { id, type, default, uiId, localOnly }
    { id = "enabled",           type = "bool",   default = true,        uiId = "fc_enabled"           },
    { id = "baseFuelPrice",     type = "float",  default = 1.20,        uiId = "fc_basePrice"         },
    { id = "difficulty",        type = "int",    default = 2,           uiId = "fc_difficulty"        },
    { id = "priceVolatility",   type = "int",    default = 2,           uiId = "fc_volatility"        },
    { id = "seasonalEffects",   type = "bool",   default = true,        uiId = "fc_seasonal"          },
    { id = "marketShocks",      type = "bool",   default = true,        uiId = "fc_shocks"            },
    { id = "showNotifications", type = "bool",   default = true,        uiId = "fc_notifications",    localOnly = true },
    { id = "hudEnabled",        type = "bool",   default = true,        uiId = "fc_hud",              localOnly = true },
    { id = "hudPosition",       type = "int",    default = 1,           uiId = "fc_hudPosition",      localOnly = true },
    { id = "debugMode",         type = "bool",   default = false,       uiId = "fc_debug"             },
}

-- Fast lookup by id — used by FuelSettingsPanel
FuelSettingsSchema.byId = {}
for _, def in ipairs(FuelSettingsSchema.definitions) do
    FuelSettingsSchema.byId[def.id] = def
end

-- difficulty index → Constants key
FuelSettingsSchema.DIFFICULTY_MAP = { "SIMPLE", "REALISTIC", "HARDCORE" }

-- volatility index → Constants key
FuelSettingsSchema.VOLATILITY_MAP = { "NONE", "LOW", "MEDIUM", "HIGH" }

-- hudPosition index → anchor
-- Wizard 2026-08-21: index 1 is now the factory suite home (see FuelHUD.FACTORY_*),
-- not the old topLeft corner. Indices 2-4 stay the corner presets.
FuelSettingsSchema.HUD_POSITION_MAP = { "factory", "topRight", "bottomLeft", "bottomRight" }
