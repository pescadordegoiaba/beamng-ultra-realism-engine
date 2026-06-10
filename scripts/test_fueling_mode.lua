local controllerPath = "UltraRealismEngine_Prototype/lua/vehicle/controller/ultraRealismEngine.lua"

local function approx(actual, expected, tolerance, label)
  if math.abs((actual or 0) - expected) > tolerance then
    error(string.format("%s: expected %.3f, got %.3f", label, expected, actual or -1))
  end
end

local function runScenario(name, nativeParts, expected)
  local engine = {
    displacementL = 5.7,
    idleRPM = 750,
    maxRPM = 7000,
    maxTorque = 520,
    requiredEnergyType = expected.energyType or "gasoline",
    fundamentalFrequencyCylinderCount = 8,
    throttle = 0.4,
    requestedThrottle = 0.4,
    idleThrottle = 0.05,
    starterEngagedCoef = 0,
    friction = 18,
    dynamicFriction = 0.02,
    outputTorqueState = 1,
    thermals = {
      cylinderWallTemperature = 95,
      oilTemperature = 92,
      engineBlockTemperature = 90,
    },
  }

  electrics = {
    values = {
      rpm = 3200,
      throttle = 0.4,
      brake = 0,
      steering_input = 0,
      wheelspeed = 18,
    },
  }
  powertrain = {getDevice = function() return engine end}
  obj = {
    getEnvTemperature = function() return 298.15 end,
    getEnvPressure = function() return 101325 end,
  }
  log = function() end
  beamstate = nil
  damageTracker = nil

  local activePartsData = {}
  local activeParts = {}
  for partName, partData in pairs(nativeParts) do
    activePartsData[partName] = partData
    activeParts["engine/" .. tostring(partData.slotType or partName)] = partName
  end

  partmgmt = {
    getConfig = function()
      return {parts = activeParts}
    end,
  }
  v = {data = {activeParts = activeParts, activePartsData = activePartsData, beams = {}}}

  local controller = assert(dofile(controllerPath))
  controller.init({
    integrationMode = expected.integration or "ceep",
    autoDetectEngine = true,
    autoFuelingMode = true,
    autoTuneVECurve = true,
    preferCarburetor = false,
    fuelingMode = "auto",
    enableEngineEffect = true,
    enableFrictionFallback = false,
    enableSuspensionBeamEffects = false,
    climatePreset = "game_environment",
    useBeamNGEnvironment = true,
  })
  for _ = 1, 4 do controller.updateGFX(0.016) end

  approx(electrics.values.ure_fuelingModeId, expected.mode, 0.01, name .. " fueling mode")
  if expected.throttleBodyMM then
    approx(electrics.values.ure_throttleBodyDiameterMM, expected.throttleBodyMM, 0.5, name .. " throttle body")
  end
end

runScenario("EFI wins on turbo intake with throttle body", {
  turbo_intake = {
    slotType = "c_sb_v8_turbo_intake",
    information = {name = "Twin Turbo Intake Manifold"},
  },
  throttle_body = {
    slotType = "ultra_realism_throttle_body",
    information = {name = "70 mm Single Throttle Body"},
    ultraRealismThrottleBody = {diameterMM = 70, count = 1, dischargeCoef = 0.9},
  },
}, {mode = 2, throttleBodyMM = 70, integration = "ceep"})

runScenario("carb wins when explicit carb installed", {
  turbo_intake = {
    slotType = "c_sb_v8_turbo_intake",
    information = {name = "Twin Turbo Intake Manifold"},
  },
  carb = {
    slotType = "ultra_realism_carburetor",
    information = {name = "Holley 4-Barrel"},
    ultraRealismCarburetor = {
      count = 1,
      primaryBarrels = 4,
      secondaryBarrels = 0,
      primaryBoreMM = 48,
      primaryVenturiMM = 36,
      ratedCFM = 650,
      secondaryType = "synchronous",
      secondaryStart = 0,
    },
  },
}, {mode = 1, integration = "ceep"})

runScenario("diesel injection mode", {
  diesel_engine = {
    slotType = "ford_diesel_v8",
    information = {name = "6.7L Power Stroke Diesel"},
  },
  injection = {
    slotType = "ultra_realism_diesel_injection",
    information = {name = "Performance Diesel Injection Pump"},
    ultraRealismDieselInjection = {nozzleFlowMM3PerStroke = 58, targetPowerAFR = 17.8},
  },
}, {mode = 3, energyType = "diesel", integration = "ford"})

print("Fueling mode detection tests passed (v0.17.2)")