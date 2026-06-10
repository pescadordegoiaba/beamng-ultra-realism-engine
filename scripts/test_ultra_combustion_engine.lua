local bridgePath = "UltraRealismEngine_Prototype/lua/vehicle/powertrain/ultraRealismEngineBridge.lua"
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
bridge.reset()

bridge.publishControllerState({
  active = true,
  appliedTorqueFactor = 0.62,
  engineEffectTarget = 0.62,
  engineDamageTorqueCoef = 1,
  suppressFalseStall = true,
  severeFailure = 0.1,
  effectiveThrottle = 0.2,
  integrationMode = "ceep",
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
  setOutputTorqueState = function(self, value) self.outputTorqueState = value end,
}

bridge.registerDevice(device.name, device, "ceep")
bridge.applyTorqueToDevice(device)
assertNear(device.outputTorqueState, 0.62, 0.0001, "bridge applies torque before native calc")

bridge.postUpdateGFXStallGuard(device)
assertTrue(not device.isStalled, "bridge clears false stall on ultra engine")

rerequire = rerequire or function(path)
  if path:find("ultraRealismEngineBridge", 1, true) then
    return dofile(bridgePath)
  end
  error("missing rerequire mock for " .. tostring(path))
end

local origRerequire = rerequire
local stockBackend = {
  new = function(jbeamData)
    return {
      name = "mainEngine",
      torqueUpdate = function() end,
      updateGFX = function() end,
      reset = function() end,
    }
  end,
}
local classicBackend = {
  new = function(jbeamData)
    return {
      name = "mainEngine",
      torqueUpdate = function() end,
      updateGFX = function() end,
      reset = function() end,
    }
  end,
}

local function mockRerequire(path)
  if path == "powertrain/combustionEngine" then return stockBackend end
  if path == "powertrain/classic_combustionEngine" then return classicBackend end
  if path == "powertrain/ultraRealismEngineBridge" then return bridge end
  return origRerequire(path)
end
rerequire = mockRerequire

FS = {
  fileExists = function(_self, path)
    return tostring(path):find("classic_combustionEngine", 1, true) ~= nil
  end,
}

electrics = {values = {}}
log = function() end
v = {vehicleDirectory = "/vehicles/barstow/", data = {parts = {ceep_engine_block = {}}}}

package.loaded[enginePath] = nil
local ultraEngine = assert(dofile(enginePath))
local ceepDevice = ultraEngine.new({ureEngineProfile = "ceep"})
assertTrue(ceepDevice.ureUltraEngine, "CEEP profile enables ultra engine hooks")

v.vehicleDirectory = "/vehicles/ford_engine_pack/"
local fordDevice = ultraEngine.new({ureEngineProfile = "ford"})
assertTrue(fordDevice.ureUltraEngine, "Ford profile enables ultra engine hooks")

v.vehicleDirectory = "/vehicles/common/"
local stockDevice = ultraEngine.new({ureEngineProfile = "stock"})
assertTrue(not stockDevice.ureUltraEngine, "stock profile keeps native backend only")

rerequire = origRerequire

print("Ultra combustion engine bridge tests passed")