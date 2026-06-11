local controllerPath = "UltraRealismEngine_Prototype/lua/vehicle/controller/ultraRealismEngine.lua"

local activeParts = {
  ["engine/ultra_realism_carburetor"] = "ultra_realism_ceep_sync_carburetor",
  ["engine/c_lhead_stock_intk_i4_single"] = "c_lhead_stock_intk_i4_single_1brl",
}
local activePartsData = {
  ultra_realism_ceep_sync_carburetor = {
    slotType = "ultra_realism_carburetor",
    information = {name = "Automatic - Use CEEP Native Part"},
    ultraRealismNativeSync = {integration = "ceep", category = "ultra_realism_carburetor"},
  },
  c_lhead_stock_intk_i4_single_1brl = {
    slotType = "c_lhead_stock_intk_i4_single",
    information = {name = "Single 1-Barrel Carburetor"},
  },
}

electrics = {values = {}}
powertrain = {getDevice = function()
  return {
    displacementL = 2.2,
    idleRPM = 650,
    maxRPM = 5200,
    maxTorque = 180,
    requiredEnergyType = "gasoline",
    fundamentalFrequencyCylinderCount = 4,
    throttle = 0.4,
    requestedThrottle = 0.4,
    idleThrottle = 0.05,
    starterEngagedCoef = 0,
    friction = 12,
    dynamicFriction = 0.02,
    thermals = {cylinderWallTemperature = 90, oilTemperature = 88, engineBlockTemperature = 85},
  }
end}
obj = {
  getEnvTemperature = function() return 298.15 end,
  getEnvPressure = function() return 101325 end,
}
log = function() end
beamstate = nil
partmgmt = {
  getConfig = function()
    return {parts = activeParts}
  end,
}
v = {data = {activeParts = activeParts, activePartsData = activePartsData, beams = {}}}

local controller = assert(dofile(controllerPath))
controller.init({
  integrationMode = "ceep",
  autoDetectEngine = true,
  autoFuelingMode = true,
  preferCarburetor = true,
  fuelingMode = "auto",
  partsSyncInterval = 0.5,
  debugLog = false,
  diagnosticLog = false,
  enableEngineEffect = true,
  enableFrictionFallback = false,
  enableSuspensionBeamEffects = false,
  climatePreset = "game_environment",
  useBeamNGEnvironment = true,
})

local firstScan = electrics.values.ure_partsScanCount or 0
for _ = 1, 120 do
  controller.updateGFX(0.016)
end
local cachedScan = electrics.values.ure_partsScanCount or 0
if cachedScan > firstScan + 2 then
  error(string.format(
    "parts scan cache ineffective: first=%d after120=%d",
    firstScan,
    cachedScan
  ))
end

activeParts["engine/ultra_realism_camshaft"] = "ultra_realism_ceep_sync_camshaft"
activePartsData.ultra_realism_ceep_sync_camshaft = {
  slotType = "ultra_realism_camshaft",
  information = {name = "Automatic - Use CEEP Native Part"},
  ultraRealismNativeSync = {integration = "ceep", category = "ultra_realism_camshaft"},
}
for _ = 1, 8 do
  controller.updateGFX(0.6)
end
local afterChange = electrics.values.ure_partsScanCount or 0
if afterChange <= cachedScan then
  error(string.format(
    "parts scan did not refresh after swap: before=%d after=%d",
    cachedScan,
    afterChange
  ))
end

print("Parts scan cache tests passed (v0.21.1)")