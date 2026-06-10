local efiPath = "UltraRealismEngine_Prototype/lua/vehicle/controller/ultra_realism/induction_efi.lua"
local dieselPath = "UltraRealismEngine_Prototype/lua/vehicle/controller/ultra_realism/induction_diesel.lua"

local function assertNear(actual, expected, tolerance, label)
  if math.abs((actual or 0) - expected) > tolerance then
    error(string.format("%s: expected %.6f, got %.6f", label, expected, actual or -1))
  end
end

local efi = assert(dofile(efiPath))
local diesel = assert(dofile(dieselPath))

local cfg = {
  stoichAFR = 14.7,
  powerAFR = 12.8,
  injectorCCMin = 280,
  injectorCount = 8,
  fuelDensityKgM3 = 740,
  idleRPM = 750,
  redlineRPM = 6500,
  timingToleranceDeg = 6,
}

local st = {}
efi.reset(st)

local airKgS = 0.18
local fuelLow, afrLow, dutyLow = efi.calcFuel(airKgS, 0.25, 20, cfg, st)
local fuelWot, afrWot, dutyWot = efi.calcFuel(airKgS, 1.0, 20, cfg, st)

assert(dutyWot > dutyLow, "WOT duty exceeds part throttle")
assert(afrWot < afrLow + 0.5, "WOT runs richer than cruise")
assertNear(dutyWot, fuelWot / (cfg.injectorCCMin * cfg.injectorCount / 60 / 1e6 * cfg.fuelDensityKgM3), 0.05, "duty tracks injector cap")

diesel.reset(st)
local dieselFuel, dieselAfr, dieselDuty = diesel.calcFuel(airKgS, 1.0, 15, cfg, st)
local _, _, _, dieselEff, _ = diesel.calcIgnition(3200, 1.0, 15, dieselAfr / cfg.stoichAFR, cfg, st)
assert(dieselDuty > 0, "diesel WOT injects fuel")
assert(dieselEff > 0.5, "diesel CI timing efficiency reasonable at WOT")

print("EFI / diesel WOT tests passed (v0.21.0)")