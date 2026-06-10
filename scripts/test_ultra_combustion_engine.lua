local bridgePath = "UltraRealismEngine_Prototype/lua/vehicle/powertrain/ultraRealismEngineBridge.lua"
local integrationPath = "UltraRealismEngine_Prototype/lua/vehicle/powertrain/ultra_combustionEngineIntegration.lua"
local enginePath = "UltraRealismEngine_Prototype/lua/vehicle/powertrain/ultra_combustionEngine.lua"

local function assertTrue(value, label)
  if not value then error(label) end
end

local function assertNear(actual, expected, tolerance, label)
  if math.abs((actual or 0) - expected) > tolerance then
    error(string.format("%s: expected %.6f, got %.6f", label, expected, actual or -1))
  end
end

local bridge = assert(dofile(bridgePath))
local integration = assert(dofile(integrationPath))

rerequire = function(path)
  if path:find("ultraRealismEngineBridge", 1, true) then return bridge end
  if path:find("ultra_combustionEngineIntegration", 1, true) then return integration end
  error("missing rerequire mock for " .. tostring(path))
end
bridge.reset()

bridge.publishControllerState({
  active = true,
  appliedTorqueFactor = 0.62,
  engineEffectTarget = 0.62,
  integratedFuel = true,
  fuelIntegrationBlend = 1,
  fuelKgS = 0.002,
  lambda = 0.95,
  mixtureEfficiency = 0.92,
  fuelDensityKgM3 = 740,
})

local device = {
  name = "mainEngine",
  ureUltraEngine = true,
  outputTorqueState = 1,
  outputAV1 = 90,
  starterMaxAV = 80,
  starterEngagedCoef = 0,
  isStalled = true,
  stallTimer = 0,
}

assertNear(integration.resolveTorqueCoef(device), 0.62, 0.0001, "integrated torque coef")

local spent, spentN2O = integration.computeSpentEnergy(device, 1000, 50, 0.8, 0.05)
assertGreater = function(a, b, label)
  if not (a > b) then error(string.format("%s: expected %.6f > %.6f", label, a or -1, b or -1)) end
end
assertGreater(spent, 500, "integrated fuel energy replaces native burn table")

integration.postStallGuard(device)
assertTrue(not device.isStalled, "integration clears false stall")

local classicBackend = {
  new = function(jbeamData)
    return {
      name = "mainEngine",
      ureUltraEngine = true,
      ureEngineProfile = jbeamData.ureEngineProfile,
    }
  end,
}
local stockBackend = {
  new = function(jbeamData)
    return {
      name = "mainEngine",
      ureUltraEngine = true,
      ureEngineProfile = jbeamData.ureEngineProfile,
    }
  end,
}

local origRerequire = rerequire
rerequire = function(path)
  if path == "powertrain/ultra_classic_combustionEngine" then return classicBackend end
  if path == "powertrain/ultra_stock_combustionEngine" then return stockBackend end
  if path:find("ultraRealismEngineBridge", 1, true) then return bridge end
  if path:find("ultra_combustionEngineIntegration", 1, true) then return integration end
  return origRerequire(path)
end

electrics = {values = {}}
log = function() end
v = {vehicleDirectory = "/vehicles/barstow/"}
package.loaded[enginePath] = nil
local ultraEngine = assert(dofile(enginePath))

local ceepDevice = ultraEngine.new({ureEngineProfile = "ceep"})
assertTrue(ceepDevice.ureUltraEngine, "CEEP uses URE classic fork")
assertTrue(ceepDevice.ureEngineProfile == "ceep", "CEEP profile preserved")

local fordDevice = ultraEngine.new({ureEngineProfile = "ford"})
assertTrue(fordDevice.ureUltraEngine, "Ford uses URE stock fork")

print("Ultra combustion engine integration tests passed (v0.15.0)")