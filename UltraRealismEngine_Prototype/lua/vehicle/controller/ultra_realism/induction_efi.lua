--[[
EFI / throttle-body fuel model with injector duty and wall-wetting.
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
  st.efiFuelFilmKg = 0
  st.efiLastFuelKgS = 0
end

function M.calcFuel(airKgS, throttle, tempC, cfg, st)
  st = st or {}
  cfg = cfg or {}

  local targetAFR = cfg.stoichAFR or 14.7
  if throttle > 0.85 then
    targetAFR = cfg.powerAFR or targetAFR
  end
  if tempC < 5 then
    targetAFR = targetAFR * 0.92
  elseif tempC > 38 then
    targetAFR = targetAFR * 1.02
  end

  local mafTrim = clamp(1 + (throttle - 0.5) * 0.04, 0.94, 1.08)
  local targetFuelKgS = (airKgS * mafTrim) / math.max(targetAFR, 1e-6)

  local injectorMax = (cfg.injectorCCMin or 250) * (cfg.injectorCount or 4) / 60.0 / 1000000.0 * (cfg.fuelDensityKgM3 or 740)
  local commandedFuelKgS = math.min(targetFuelKgS, injectorMax)
  local duty = commandedFuelKgS / math.max(injectorMax, 1e-8)

  local film = st.efiFuelFilmKg or 0
  local filmTau = lerp(0.35, 0.12, clamp(throttle, 0, 1))
  local filmPickup = film / math.max(filmTau, 0.05)
  local wallDeposit = clamp(commandedFuelKgS - (st.efiLastFuelKgS or commandedFuelKgS), 0, commandedFuelKgS) * 0.18
  film = math.max(film + wallDeposit - filmPickup * 0.016, 0)
  local deliveredFuelKgS = math.max(commandedFuelKgS - wallDeposit * 0.35 + filmPickup * 0.012, 0)
  st.efiFuelFilmKg = film
  st.efiLastFuelKgS = commandedFuelKgS

  local afr = airKgS / math.max(deliveredFuelKgS, 1e-8)
  return deliveredFuelKgS, afr, duty
end

return M