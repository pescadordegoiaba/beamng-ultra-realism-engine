local bridgePath = "UltraRealismEngine_Prototype/lua/vehicle/powertrain/ultraRealismEngineBridge.lua"
local integrationPath = "UltraRealismEngine_Prototype/lua/vehicle/powertrain/ultra_combustionEngineIntegration.lua"
local hooksPath = "UltraRealismEngine_Prototype/lua/vehicle/powertrain/ultra_combustionEngineHooks.lua"

local function assertNear(actual, expected, tolerance, label)
  if math.abs((actual or 0) - expected) > tolerance then
    error(string.format("%s: expected %.6f, got %.6f", label, expected, actual or -1))
  end
end

local bridge = assert(dofile(bridgePath))
local integration = assert(dofile(integrationPath))
local hooks = assert(dofile(hooksPath))

rerequire = function(path)
  if path:find("ultraRealismEngineBridge", 1, true) then return bridge end
  if path:find("ultra_combustionEngineIntegration", 1, true) then return integration end
  if path:find("ultra_combustionEngineHooks", 1, true) then return hooks end
  error("missing rerequire mock for " .. tostring(path))
end

bridge.reset()

local device = {
  name = "mainEngine",
  ureUltraEngine = true,
  outputTorqueState = 1,
  forcedInductionCoef = 1.4,
  outputAV1 = 120,
}

bridge.publishControllerState({
  active = true,
  appliedTorqueFactor = 0.71,
  engineEffectTarget = 0.71,
  runtimeTorqueMult = 1.05,
  forcedInductionBlend = 0.6,
  inductionFlowRatio = 0.88,
  manifoldPressurePa = 155000,
  integratedFuel = true,
  fuelIntegrationBlend = 1,
  fuelKgS = 0.003,
  lambda = 0.98,
  mixtureEfficiency = 0.94,
})

local ctx = hooks.beforeTorqueCalc(device, {rpm = 4500})
assertNear(ctx.rpm, 4500, 1, "hook rpm")

local torqueCoef = integration.resolveTorqueCoef(device)
local fiCoef = integration.resolveForcedInductionCoef(device)
local chainTorque = 100 * fiCoef * torqueCoef
local after = hooks.afterTorqueCalc(device, ctx, chainTorque)
assertNear(after, chainTorque, 0.001, "hook passthrough torque")

local spent, spentN2O = integration.computeSpentEnergy(device, 900, 40, 0.82, 0.02)
assert(spent > 0, "fuel chain produces spent energy")
assert(spentN2O >= 0, "nitrous spent non-negative")

print("E2E torque chain tests passed (v0.21.0)")