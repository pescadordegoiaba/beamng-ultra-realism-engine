local bridgePath = "UltraRealismEngine_Prototype/lua/vehicle/powertrain/ultraRealismEngineBridge.lua"
local integrationPath = "UltraRealismEngine_Prototype/lua/vehicle/powertrain/ultra_combustionEngineIntegration.lua"
local ownershipPath = "UltraRealismEngine_Prototype/lua/vehicle/controller/ultra_realism/ownership.lua"
local partCurvesPath = "UltraRealismEngine_Prototype/lua/vehicle/controller/ultra_realism/partCurves.lua"

local function assertNear(actual, expected, tolerance, label)
  if math.abs((actual or 0) - expected) > tolerance then
    error(string.format("%s: expected %.6f, got %.6f", label, expected, actual or -1))
  end
end

local bridge = assert(dofile(bridgePath))
local integration = assert(dofile(integrationPath))
local ownership = assert(dofile(ownershipPath))
local partCurves = assert(dofile(partCurvesPath))

rerequire = function(path)
  if path:find("ultraRealismEngineBridge", 1, true) then return bridge end
  if path:find("ultra_combustionEngineIntegration", 1, true) then return integration end
  error("missing rerequire mock for " .. tostring(path))
end

bridge.reset()
ownership.reset()
partCurves.reset()

local nativeSyncedCam = {
  name = "ultra_realism_native_ceep_test_cam",
  data = {
    slotType = "ceep_camshaft",
    ultraRealismCategory = "ultra_realism_camshaft",
    ultraRealismNativeSync = {mode = "ceep"},
    mainEngine = {
      torqueModUltraCamshaftMult = {
        {0, 1.2},
        {6000, 1.2},
      },
    },
  },
}

local userCam = {
  name = "ultra_realism_cam_race",
  data = {
    slotType = "ultra_realism_camshaft",
    ultraRealismCategory = "ultra_realism_camshaft",
    mainEngine = {
      torqueModUltraCamshaftMult = {
        {0, 1.08},
        {6000, 1.08},
      },
    },
  },
}

ownership.refresh({nativeSyncedCam}, true)
assert(ownership.shouldSkipHeuristic("ultra_realism_camshaft", true), "native cam owned")

partCurves.refresh({nativeSyncedCam, userCam}, ownership)
assertNear(partCurves.multAtRPM(3000), 1.08, 0.001, "native-sync cam excluded from runtime mult")

bridge.publishControllerState({
  active = true,
  appliedTorqueFactor = 0.8,
  engineEffectTarget = 0.8,
  runtimeTorqueMult = 1.08,
  nativePartSyncActive = true,
  integratedFuel = true,
  fuelIntegrationBlend = 1,
})

local device = {
  ureUltraEngine = true,
  outputTorqueState = 1,
  forcedInductionCoef = 1.25,
}
assertNear(integration.resolveTorqueCoef(device), 0.8 * 1.08, 0.0001, "runtime mult applied")
assertNear(integration.resolveForcedInductionCoef(device), 1.25, 0.0001, "FI unchanged without blend")

bridge.publishControllerState({
  active = true,
  appliedTorqueFactor = 0.8,
  engineEffectTarget = 0.8,
  runtimeTorqueMult = 1,
  nativePartSyncActive = true,
  forcedInductionBlend = 0.75,
  inductionFlowRatio = 0.82,
  manifoldPressurePa = 140000,
  integratedFuel = true,
  fuelIntegrationBlend = 1,
})
local fiCoef = integration.resolveForcedInductionCoef(device)
assert(fiCoef < 1.25 and fiCoef > 0.9, "FI coef blends with induction flow")

print("Double-count torque tests passed (v0.21.0)")