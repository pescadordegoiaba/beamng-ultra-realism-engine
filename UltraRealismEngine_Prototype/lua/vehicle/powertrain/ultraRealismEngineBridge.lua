--[[
Shared bridge between ultraRealismEngine controller and ultra_combustionEngine powertrain.
Allows torque factors and stall suppression to reach the engine BEFORE native torque calc.
]]

local M = {}

local state = {
  active = false,
  appliedTorqueFactor = 1,
  engineEffectTarget = 1,
  engineDamageTorqueCoef = 1,
  suppressFalseStall = true,
  severeFailure = 0,
  effectiveThrottle = 0,
  integrationMode = "generic",
  ultraEngineBound = false,
  integratedFuel = true,
  fuelIntegrationBlend = 1,
  fuelKgS = 0,
  airKgS = 0,
  lambda = 1,
  afr = 14.7,
  mixtureEfficiency = 1,
  fuelDensityKgM3 = 740,
  fuelEnergyJPerKg = 43.5e6,
  respectNativeDamage = true,
  runtimeTorqueMult = 1,
  inductionFlowRatio = 1,
  manifoldPressurePa = 101325,
  forcedInductionBlend = 0,
  nativePartSyncActive = false,
}

local devices = {}

local function clamp(x, lo, hi)
  x = tonumber(x) or lo
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

function M.registerDevice(deviceName, device, profile)
  if not deviceName or not device then return end
  devices[deviceName] = {
    device = device,
    profile = profile or "stock",
  }
  state.ultraEngineBound = true
end

function M.unregisterDevice(deviceName)
  devices[deviceName] = nil
  state.ultraEngineBound = next(devices) ~= nil
end

function M.publishControllerState(payload)
  payload = payload or {}
  state.active = payload.active ~= false
  state.appliedTorqueFactor = clamp(payload.appliedTorqueFactor or 1, 0, 2)
  state.engineEffectTarget = clamp(payload.engineEffectTarget or 1, 0, 2)
  state.engineDamageTorqueCoef = clamp(payload.engineDamageTorqueCoef or 1, 0, 2)
  state.suppressFalseStall = payload.suppressFalseStall ~= false
  state.severeFailure = clamp(payload.severeFailure or 0, 0, 1)
  state.effectiveThrottle = clamp(payload.effectiveThrottle or 0, 0, 1)
  state.integrationMode = tostring(payload.integrationMode or "generic")
  state.integratedFuel = payload.integratedFuel ~= false
  state.fuelIntegrationBlend = clamp(payload.fuelIntegrationBlend or 1, 0, 1)
  state.fuelKgS = clamp(payload.fuelKgS or 0, 0, 10)
  state.airKgS = clamp(payload.airKgS or 0, 0, 10)
  state.lambda = clamp(payload.lambda or 1, 0.4, 2.5)
  state.afr = clamp(payload.afr or 14.7, 4, 35)
  state.mixtureEfficiency = clamp(payload.mixtureEfficiency or 1, 0.05, 1.5)
  state.fuelDensityKgM3 = clamp(payload.fuelDensityKgM3 or 740, 400, 900)
  state.fuelEnergyJPerKg = clamp(payload.fuelEnergyJPerKg or 43.5e6, 20e6, 50e6)
  state.respectNativeDamage = payload.respectNativeDamage ~= false
  state.runtimeTorqueMult = clamp(payload.runtimeTorqueMult or 1, 0.5, 1.5)
  state.inductionFlowRatio = clamp(payload.inductionFlowRatio or 1, 0.2, 1.5)
  state.manifoldPressurePa = clamp(payload.manifoldPressurePa or 101325, 20000, 400000)
  state.forcedInductionBlend = clamp(payload.forcedInductionBlend or 0, 0, 1)
  state.nativePartSyncActive = payload.nativePartSyncActive == true
end

function M.getState()
  return state
end

function M.applyTorqueToDevice(device)
  if not device or not device.ureUltraEngine or not state.active then return end
  if device.outputTorqueState == nil then return end
  local target = clamp(state.engineEffectTarget, 0, 2) * clamp(state.engineDamageTorqueCoef, 0, 2)
  device.outputTorqueState = target
  if type(device.setOutputTorqueState) == "function" then
    pcall(function() device:setOutputTorqueState(target) end)
  end
end

function M.postUpdateGFXStallGuard(device)
  if not device or not device.ureUltraEngine or not state.suppressFalseStall then return end
  if (device.starterEngagedCoef or 0) > 0 then return end
  local stallAV = (device.starterMaxAV or 0) * 0.8
  if stallAV <= 0 then return end
  if device.outputAV1 > stallAV * 0.95
      and state.appliedTorqueFactor > 0.55
      and state.severeFailure < 0.82
      and state.effectiveThrottle < 0.72 then
    device.isStalled = false
    device.stallTimer = 1
  end
end

function M.reset()
  state.active = false
  state.appliedTorqueFactor = 1
  state.engineEffectTarget = 1
  state.engineDamageTorqueCoef = 1
  state.severeFailure = 0
  state.effectiveThrottle = 0
  state.integrationMode = "generic"
  state.ultraEngineBound = false
  state.integratedFuel = true
  state.fuelIntegrationBlend = 1
  state.fuelKgS = 0
  state.airKgS = 0
  state.lambda = 1
  state.afr = 14.7
  state.mixtureEfficiency = 1
  state.runtimeTorqueMult = 1
  state.inductionFlowRatio = 1
  state.manifoldPressurePa = 101325
  state.forcedInductionBlend = 0
  state.nativePartSyncActive = false
  devices = {}
end

return M