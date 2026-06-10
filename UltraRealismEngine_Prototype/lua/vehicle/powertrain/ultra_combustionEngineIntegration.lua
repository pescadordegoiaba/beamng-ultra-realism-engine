--[[
Ultra Realism integration layer for forked combustion engines.
Reads controller state via ultraRealismEngineBridge and applies torque + fuel + stall.
]]

local M = {}

local DEFAULT_FUEL_ENERGY_J_PER_KG = 43.5e6
local cachedBridge

local function getBridge()
  if cachedBridge then return cachedBridge end
  cachedBridge = rerequire("powertrain/ultraRealismEngineBridge")
  return cachedBridge
end

local function clamp(x, lo, hi)
  x = tonumber(x) or lo
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function readElectrics(name, default)
  if electrics and electrics.values and electrics.values[name] ~= nil then
    return electrics.values[name]
  end
  return default
end

local function getIntegratedState()
  local bridge = getBridge()
  local state = bridge.getState and bridge.getState() or {}
  if state.active then return state end

  if readElectrics("ure_enabled", 0) < 0.5 then return state end
  return {
    active = true,
    appliedTorqueFactor = readElectrics("ure_appliedTorqueFactor", readElectrics("ure_engineEffectTarget", 1)),
    engineEffectTarget = readElectrics("ure_engineEffectTarget", 1),
    engineDamageTorqueCoef = readElectrics("ure_engineDamageTorqueCoef", 1),
    fuelKgS = readElectrics("ure_fuel_gps", 0) / 1000,
    airKgS = readElectrics("ure_air_gps", 0) / 1000,
    lambda = readElectrics("ure_lambda", 1),
    afr = readElectrics("ure_afr", 14.7),
    mixtureEfficiency = readElectrics("ure_mixtureEfficiency", 1),
    fuelDensityKgM3 = readElectrics("ure_fuelDensityKgM3", 740),
    suppressFalseStall = readElectrics("ure_suppressFalseStallUI", 1) >= 0.5,
    severeFailure = math.max(readElectrics("ure_vaporLock", 0), readElectrics("ure_carbIce", 0), readElectrics("ure_misfire", 0)),
    effectiveThrottle = readElectrics("ure_effectiveThrottle", 0),
    integratedFuel = true,
    fuelIntegrationBlend = 1,
    respectNativeDamage = true,
  }
end

function M.resolveTorqueCoef(device)
  if not device or not device.ureUltraEngine then
    return device and device.outputTorqueState or 1
  end

  local state = getIntegratedState()
  if not state.active then
    return device.outputTorqueState or 1
  end

  local ureCoef = clamp(state.appliedTorqueFactor or 1, 0, 2)
    * clamp(state.engineDamageTorqueCoef or 1, 0, 2)
  local nativeCoef = clamp(device.outputTorqueState or 1, 0, 2)

  if nativeCoef < 0.55 and (state.respectNativeDamage ~= false) then
    return nativeCoef * ureCoef
  end
  return ureCoef
end

function M.computeSpentEnergy(device, burnEnergy, burnEnergyNitrousOxide, nativeInvBurn, dt)
  if not device or not device.ureUltraEngine then
    return burnEnergy * nativeInvBurn, burnEnergyNitrousOxide * nativeInvBurn
  end

  local state = getIntegratedState()
  local nativeSpent = burnEnergy * nativeInvBurn
  local nativeSpentN2O = burnEnergyNitrousOxide * nativeInvBurn

  if not state.active or not state.integratedFuel then
    local mix = clamp(state.mixtureEfficiency or 1, 0.05, 1.5)
    return nativeSpent * mix, nativeSpentN2O * mix
  end

  dt = math.max(tonumber(dt) or 0, 0)
  local fuelKgS = clamp(state.fuelKgS or 0, 0, 10)
  if fuelKgS <= 1e-9 or dt <= 0 then
    local mixOnly = clamp(state.mixtureEfficiency or 1, 0.05, 1.5)
    return nativeSpent * mixOnly, nativeSpentN2O * mixOnly
  end

  local fuelDensity = clamp(state.fuelDensityKgM3 or 740, 400, 900)
  local fuelEnergyJPerKg = clamp(state.fuelEnergyJPerKg or DEFAULT_FUEL_ENERGY_J_PER_KG, 20e6, 50e6)
  local fuelKg = fuelKgS * dt
  local ureFuelEnergy = fuelKg * fuelEnergyJPerKg

  local lambda = clamp(state.lambda or 1, 0.4, 2.0)
  local lambdaPenalty = clamp(1 - math.abs(lambda - 1) * 0.35, 0.25, 1)
  ureFuelEnergy = ureFuelEnergy * lambdaPenalty * clamp(state.mixtureEfficiency or 1, 0.05, 1.5)

  local blend = clamp(state.fuelIntegrationBlend or 1, 0, 1)
  local spent = nativeSpent * (1 - blend) + ureFuelEnergy * blend
  local spentN2O = nativeSpentN2O * (1 - blend) + ureFuelEnergy * 0.15 * blend
  return spent, spentN2O
end

function M.postStallGuard(device)
  if not device or not device.ureUltraEngine then return end
  local state = getIntegratedState()
  if not state.suppressFalseStall then return end
  if (device.starterEngagedCoef or 0) > 0 then return end

  local stallAV = (device.starterMaxAV or 0) * 0.8
  if stallAV <= 0 then return end

  local applied = clamp(state.appliedTorqueFactor or 1, 0, 2)
  local severe = clamp(state.severeFailure or 0, 0, 1)
  local throttle = clamp(state.effectiveThrottle or 0, 0, 1)

  if device.outputAV1 > stallAV * 0.95 and applied > 0.55 and severe < 0.82 and throttle < 0.72 then
    device.isStalled = false
    device.stallTimer = 1
  end
end

function M.onDeviceInit(device, jbeamData)
  if not device then return end
  device.ureUltraEngine = true
  local profile = "stock"
  if jbeamData and jbeamData.ureEngineProfile then
    profile = tostring(jbeamData.ureEngineProfile)
  elseif device.ureEngineProfile then
    profile = tostring(device.ureEngineProfile)
  end
  device.ureEngineProfile = profile
  local bridge = getBridge()
  if bridge.registerDevice then
    bridge.registerDevice(device.name, device, device.ureEngineProfile)
  end
end

return M