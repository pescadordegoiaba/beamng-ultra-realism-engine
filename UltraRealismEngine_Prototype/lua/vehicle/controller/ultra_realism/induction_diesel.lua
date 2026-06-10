--[[
Diesel injection pump / nozzle model with CI timing and smoke penalty.
]]

local M = {}

local function clamp(x, lo, hi)
  x = tonumber(x) or lo
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function lerp(a, b, t)
  return a + (b - a) * clamp(t, 0, 1)
end

function M.reset(st)
  if type(st) ~= "table" then return end
  st.dieselSmoke = 0
end

function M.calcFuel(airKgS, throttle, tempC, cfg, st)
  st = st or {}
  cfg = cfg or {}

  local targetAFR = (cfg.stoichAFR or 14.7) * lerp(2.75, 1.25, clamp(throttle, 0, 1))
  if throttle > 0.88 then
    targetAFR = cfg.powerAFR or targetAFR
  end
  if tempC < -5 then
    targetAFR = targetAFR * 0.96
  elseif tempC > 38 then
    targetAFR = targetAFR * 1.03
  end

  local coldEnrichment = tempC < 0 and lerp(0.88, 1, clamp((tempC + 10) / 10, 0, 1)) or 1
  local targetFuelKgS = (airKgS / math.max(targetAFR, 1e-6)) * coldEnrichment

  local injectorMax = (cfg.injectorCCMin or 280) * (cfg.injectorCount or 4) / 60.0 / 1000000.0 * (cfg.fuelDensityKgM3 or 832)
  local fuelKgS = math.min(targetFuelKgS, injectorMax)
  local duty = fuelKgS / math.max(injectorMax, 1e-8)

  local lambda = (airKgS / math.max(fuelKgS, 1e-8)) / math.max(cfg.stoichAFR or 14.7, 0.1)
  st.dieselSmoke = clamp((1.05 - lambda) * throttle, 0, 1)

  local afr = airKgS / math.max(fuelKgS, 1e-8)
  return fuelKgS, afr, duty
end

function M.calcIgnition(rpm, throttle, tempC, lambda, cfg, st)
  st = st or {}
  cfg = cfg or {}

  local idleRPM = cfg.idleRPM or 750
  local redlineRPM = cfg.redlineRPM or 4500
  local load = clamp(throttle, 0, 1)
  local rpmNorm = clamp((rpm - idleRPM) / math.max(redlineRPM - idleRPM, 1), 0, 1)

  local baseAdvance = lerp(-4, 18, rpmNorm) * load
  local coldRetard = tempC < 0 and lerp(6, 0, clamp((tempC + 15) / 15, 0, 1)) or 0
  local hotRetard = math.max(tempC - 40, 0) * 0.08
  local smokeRetard = (st.dieselSmoke or 0) * 5.0
  local actualTiming = baseAdvance - coldRetard - hotRetard - smokeRetard
  local mbt = baseAdvance - coldRetard - hotRetard

  if lambda < 0.95 then
    mbt = mbt - 1.5
  elseif lambda > 1.55 then
    mbt = mbt + 1.0
  end

  local timingError = actualTiming - mbt
  local tolerance = cfg.timingToleranceDeg or 6
  local timingEfficiency = math.exp(-(timingError * timingError) / (2 * tolerance * tolerance))
  local advanceRisk = clamp((timingError - 4) / 10, 0, 1)

  return actualTiming, mbt, timingError, timingEfficiency, advanceRisk
end

return M