local controllerPath = "UltraRealismEngine_Prototype/lua/vehicle/controller/ultraRealismEngine.lua"

local function assertGreater(actual, expected, label)
  if not (actual > expected) then
    error(string.format("%s: expected %.6f > %.6f", label, actual or -1, expected or -1))
  end
end

local function carbDefinition(count)
  return {
    slotType = "test_carburetor",
    information = {name = string.format("%dx Weber 40 DCOE", count)},
    ultraRealismCarburetor = {
      modelId = 5000 + count,
      count = count,
      primaryBarrels = 2,
      secondaryBarrels = 0,
      primaryBoreMM = 40,
      secondaryBoreMM = 40,
      primaryVenturiMM = 32,
      secondaryVenturiMM = 32,
      mainJetMM = 1.35,
      ratedCFM = 420 * count,
      ratingPressureDropPa = 5079,
      dischargeCoef = 0.82,
      boosterSignalCoef = 1.0,
      accelPumpCoef = 1.0,
      secondaryType = "synchronous",
    },
  }
end

local function runScenario(opts)
  opts = opts or {}
  local count = opts.count or 1
  local rpm = opts.rpm or 6000
  local activePartName = opts.partName or string.format("ultra_realism_breath_test_%dx", count)

  local engine = {
    displacementL = opts.displacementL or 5.7,
    idleRPM = 750,
    maxRPM = 7000,
    maxTorque = 520,
    requiredEnergyType = "gasoline",
    fundamentalFrequencyCylinderCount = 8,
    throttle = opts.throttle or 1,
    requestedThrottle = opts.throttle or 1,
    idleThrottle = 0.05,
    starterEngagedCoef = 0,
    outputTorqueState = 1,
    intakeAirDensityCoef = 1,
    friction = 18,
    dynamicFriction = 0.02,
    thermals = {
      cylinderWallTemperature = opts.wallTempC or 95,
      oilTemperature = opts.oilTempC or 92,
      engineBlockTemperature = opts.blockTempC or 90,
    },
  }

  electrics = {
    values = {
      rpm = rpm,
      throttle = opts.throttle or 1,
      brake = 0,
      steering_input = 0,
      wheelspeed = opts.wheelspeed or 25,
      rain = opts.rain or 0,
      rainIntensity = opts.rain or 0,
    },
  }
  powertrain = {getDevice = function() return engine end}
  obj = {
    getEnvTemperature = function() return opts.envTempK or 298.15 end,
    getEnvPressure = function() return opts.pressurePa or 101325 end,
  }
  log = function() end
  beamstate = nil
  damageTracker = nil
  v = {
    data = {
      activeParts = {["engine/topend/carburetor"] = activePartName},
      activePartsData = {[activePartName] = carbDefinition(count)},
      beams = {},
    },
  }
  partmgmt = {
    getConfig = function()
      return {parts = {["engine/topend/carburetor"] = activePartName}}
    end,
  }

  package.loaded[controllerPath] = nil
  local controller = assert(dofile(controllerPath))
  controller.init({
    integrationMode = "ceep",
    autoDetectEngine = true,
    autoFuelingMode = true,
    autoTuneVECurve = true,
    fuelingMode = "auto",
    enableEngineEffect = true,
    enableFrictionFallback = false,
    enableSuspensionBeamEffects = false,
    climatePreset = opts.climatePreset or "game_environment",
    useBeamNGEnvironment = opts.useBeamNGEnvironment ~= false,
  })

  for _ = 1, (opts.steps or 10) do
    controller.updateGFX(0.05)
    controller.update(0.0005)
  end

  return {
    breathingScore = electrics.values.ure_breathingScore,
    breathingCapacity = electrics.values.ure_breathingCapacityScore,
    breathingIntake = electrics.values.ure_breathingIntakeScore,
    breathingTemp = electrics.values.ure_breathingTempEfficiency,
    effectiveVenturiCoef = electrics.values.ure_effectiveVenturiCoef,
    effectiveVenturiMM = electrics.values.ure_effectiveVenturiMM,
    venturiWear = electrics.values.ure_venturiWear,
    airDensity = electrics.values.ure_airDensity,
    engineCoef = engine.outputTorqueState,
    ve = electrics.values.ure_ve,
    rainIntensity = electrics.values.ure_rainIntensity,
    intakeTempC = electrics.values.ure_intakeTempC,
    carbIce = electrics.values.ure_carbIce,
  }
end

local warm = runScenario({count = 1, envTempK = 308.15})
local cold = runScenario({count = 1, envTempK = 268.15})
assertGreater(cold.airDensity, warm.airDensity, "cold ambient air is denser than warm")

local dry = runScenario({count = 6, rain = 0, wheelspeed = 5, steps = 20})
local wet = runScenario({count = 6, rain = 1.0, wheelspeed = 5, steps = 20})
assertGreater(dry.breathingScore, wet.breathingScore, "rain reduces breathing score")

local iced = runScenario({
  count = 6,
  envTempK = 275.15,
  throttle = 0.45,
  rpm = 2800,
  wheelspeed = 8,
  steps = 40,
})
local warmRun = runScenario({count = 6, envTempK = 303.15, throttle = 0.45, rpm = 2800, steps = 20})
assertGreater(warmRun.effectiveVenturiCoef, iced.effectiveVenturiCoef, "carb ice reduces effective venturi")

local fresh = runScenario({count = 6, steps = 8})
local worn = runScenario({
  count = 6,
  wallTempC = 55,
  oilTempC = 50,
  blockTempC = 55,
  rpm = 6200,
  throttle = 1,
  steps = 180,
})
assertGreater(worn.venturiWear or 0, fresh.venturiWear or 0, "long cold high-RPM run accumulates more venturi wear")
assertGreater(worn.venturiWear or 0, 0.002, "cold high-RPM run accumulates venturi wear")
assertGreater(fresh.effectiveVenturiCoef, worn.effectiveVenturiCoef, "wear reduces effective venturi coef")

local single = runScenario({count = 1})
local six = runScenario({count = 6})
assertGreater(six.breathingScore, single.breathingScore + 0.12, "six-carb breathing score well above single")
assertGreater(six.engineCoef - single.engineCoef, 0.28, "breathing system torque gap at WOT")

print(string.format(
  "Breathing air system passed: 1x breath=%.3f coef=%.3f; 6x breath=%.3f coef=%.3f; rain drop=%.3f; wear=%.4f",
  single.breathingScore,
  single.engineCoef,
  six.breathingScore,
  six.engineCoef,
  dry.breathingScore - wet.breathingScore,
  worn.venturiWear or 0
))