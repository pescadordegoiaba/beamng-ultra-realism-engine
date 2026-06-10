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
  devices = {}
end

return M