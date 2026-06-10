local controllerPath = "UltraRealismEngine_Prototype/lua/vehicle/controller/ultraRealismEngine.lua"

local function assertGreater(actual, expected, label)
  if not (actual > expected) then
    error(string.format("%s: expected %.6f > %.6f", label, actual or -1, expected or -1))
  end
end

local function assertNear(actual, expected, tolerance, label)
  if math.abs((actual or 0) - expected) > tolerance then
    error(string.format("%s: expected %.6f, got %.6f", label, expected, actual or -1))
  end
end

local function carbDefinition(count, partName)
  return {
    slotType = "test_carburetor",
    information = {name = string.format("%dx Weber 40 DCOE", count)},
    ultraRealismCarburetor = {
      modelId = 4000 + count,
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

local function runScenario(count, rpm, starterEngaged, duration, activePartName)
  activePartName = activePartName or string.format("ultra_realism_carb_test_%dx", count)
  local decoyPartName = count == 1 and "ultra_realism_carb_test_6x" or "ultra_realism_carb_test_1x"

  local engine = {
    displacementL = 5.7,
    idleRPM = 750,
    maxRPM = 7000,
    maxTorque = 520,
    requiredEnergyType = "gasoline",
    fundamentalFrequencyCylinderCount = 8,
    throttle = 1,
    requestedThrottle = 1,
    idleThrottle = 0.05,
    starterEngagedCoef = starterEngaged or 0,
    outputTorqueState = 1,
    intakeAirDensityCoef = 1,
    friction = 18,
    dynamicFriction = 0.02,
    thermals = {
      cylinderWallTemperature = 95,
      oilTemperature = 92,
      engineBlockTemperature = 90,
    },
  }

  electrics = {
    values = {
      rpm = rpm,
      throttle = 1,
      brake = 0,
      steering_input = 0,
      wheelspeed = 25,
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
  v = {
    data = {
      activeParts = {
        ["engine/topend/carburetor"] = activePartName,
      },
      activePartsData = {
        [activePartName] = carbDefinition(count, activePartName),
        [decoyPartName] = carbDefinition(count == 1 and 6 or 1, decoyPartName),
        ultra_realism_carb_test_1x = carbDefinition(1, "ultra_realism_carb_test_1x"),
        ultra_realism_carb_test_6x = carbDefinition(6, "ultra_realism_carb_test_6x"),
      },
      beams = {},
    },
  }
  partmgmt = {
    getConfig = function()
      return {parts = {["engine/topend/carburetor"] = activePartName}}
    end,
  }

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
    climatePreset = "game_environment",
    useBeamNGEnvironment = true,
  })

  local gfxStep = 0.05
  for _ = 1, math.max(math.floor(duration / gfxStep), 1) do
    controller.updateGFX(gfxStep)
    controller.update(0.0005)
  end

  return {
    engineCoef = engine.outputTorqueState or engine.intakeAirDensityCoef,
    outputTorqueApplied = electrics.values.ure_outputTorqueStateApplied,
    area = electrics.values.ure_activeVenturiAreaM2,
    maxArea = electrics.values.ure_maxVenturiAreaM2,
    maxFlow = electrics.values.ure_maxVenturiFlowM3s,
    demandRatio = electrics.values.ure_venturiDemandRatio,
    restriction = electrics.values.ure_carbRestriction,
    flowRatio = electrics.values.ure_inductionFlowRatio,
    inductionEfficiency = electrics.values.ure_inductionTorqueEfficiency,
    afr = electrics.values.ure_afr,
    mixtureEfficiency = electrics.values.ure_mixtureEfficiency,
    timingEfficiency = electrics.values.ure_timingEfficiency,
    pistonEfficiency = electrics.values.ure_pistonEfficiency,
    compressionEfficiency = electrics.values.ure_compressionEfficiency,
    valveTrainEfficiency = electrics.values.ure_valveTrainEfficiency,
    misfire = electrics.values.ure_misfire,
    climateShock = electrics.values.ure_climateShock,
    torqueFactor = electrics.values.ure_torqueFactor,
    applied = electrics.values.ure_engineEffectApplied,
    startProtection = electrics.values.ure_startProtection,
    carbCount = electrics.values.ure_carbCount,
    loadBlend = electrics.values.ure_engineEffectLoadBlend,
  }
end

local single = runScenario(1, 6000, 0, 8)
local six = runScenario(6, 6000, 0, 8)

print(string.format(
  "Diagnostic: 1x count %.0f restriction %.3f flow %.3f induction %.3f demand %.2f coef %.3f; 6x count %.0f restriction %.3f flow %.3f induction %.3f demand %.2f coef %.3f",
  single.carbCount,
  single.restriction,
  single.flowRatio,
  single.inductionEfficiency,
  single.demandRatio,
  single.engineCoef,
  six.carbCount,
  six.restriction,
  six.flowRatio,
  six.inductionEfficiency,
  six.demandRatio,
  six.engineCoef
))

assertNear(single.carbCount, 1, 0.001, "single-carb active count")
assertNear(six.carbCount, 6, 0.001, "six-carb active count")
assertNear(six.area / single.area, 6, 0.001, "six-carb Venturi area ratio")
assertNear(six.maxArea / single.maxArea, 6, 0.001, "six-carb max Venturi area ratio")
assertGreater(six.maxFlow, single.maxFlow * 4.5, "six-carb max venturi flow")
assertGreater(single.restriction, six.restriction + 0.08, "single-carb restriction")
assertGreater(six.flowRatio, single.flowRatio + 0.08, "six-carb airflow")
assertGreater(six.inductionEfficiency, single.inductionEfficiency + 0.08, "six-carb induction torque")
assertGreater(six.engineCoef, single.engineCoef + 0.08, "six-carb applied engine coefficient")
assertGreater(six.engineCoef - single.engineCoef, 0.10, "single vs six torque gap")
assertGreater(six.engineCoef, 0.88, "six-carb standard-condition coefficient")
assertNear(single.outputTorqueApplied, 1, 0.001, "outputTorqueState path active")
assertNear(single.engineCoef, single.torqueFactor, 0.000001, "single-carb applied factor")
assertNear(six.engineCoef, six.torqueFactor, 0.000001, "six-carb applied factor")

local decoyIgnored = runScenario(1, 6000, 0, 0.2, "ultra_realism_carb_test_1x")
assertNear(decoyIgnored.carbCount, 1, 0.001, "decoy catalog carb must not override active selection")

local function runPartsLibraryScenario(count, rpm)
  local activePartName = string.format("ultra_realism_carb_test_%dx", count)
  local engine = {
    displacementL = 5.7,
    idleRPM = 750,
    maxRPM = 7000,
    maxTorque = 520,
    requiredEnergyType = "gasoline",
    fundamentalFrequencyCylinderCount = 8,
    throttle = 1,
    requestedThrottle = 1,
    idleThrottle = 0.05,
    starterEngagedCoef = 0,
    outputTorqueState = 1,
    intakeAirDensityCoef = 1,
    friction = 18,
    dynamicFriction = 0.02,
    thermals = {cylinderWallTemperature = 95, oilTemperature = 92, engineBlockTemperature = 90},
  }
  electrics = {values = {rpm = rpm, throttle = 1, brake = 0, steering_input = 0, wheelspeed = 25}}
  powertrain = {getDevice = function() return engine end}
  obj = {getEnvTemperature = function() return 298.15 end, getEnvPressure = function() return 101325 end}
  log = function() end
  beamstate = nil
  damageTracker = nil
  local carbDef = carbDefinition(count, activePartName)
  v = {
    config = {
      parts = {["engine/topend/carburetor"] = activePartName},
      partsTree = {
        chosenPartName = "engine",
        children = {
          topend = {
            chosenPartName = "topend",
            children = {
              carburetor = {
                chosenPartName = activePartName,
                slotName = "carburetor",
                partPath = "/engine/topend/carburetor",
              },
            },
          },
        },
      },
    },
    data = {
      parts = {[activePartName] = carbDef},
      beams = {},
    },
  }
  partmgmt = nil
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
    climatePreset = "game_environment",
    useBeamNGEnvironment = true,
  })
  for _ = 1, 8 do
    controller.updateGFX(0.05)
    controller.update(0.0005)
  end
  return {
    carbCount = electrics.values.ure_carbCount,
    activePartsCount = electrics.values.ure_activePartsCount,
    engineCoef = engine.outputTorqueState,
  }
end

local partsLibSingle = runPartsLibraryScenario(1, 6000)
local partsLibSix = runPartsLibraryScenario(6, 6000)
assertGreater(partsLibSingle.activePartsCount, 1, "partsTree + parts library entries")
assertNear(partsLibSingle.carbCount, 1, 0.001, "parts library single carb count")
assertNear(partsLibSix.carbCount, 6, 0.001, "parts library six carb count")
assertGreater(partsLibSix.engineCoef, partsLibSingle.engineCoef + 0.08, "parts library torque gap")

local highRpmDuringStartupWindow = runScenario(1, 6000, 0, 0.1)
if highRpmDuringStartupWindow.startProtection > 0.01 then
  error("startup protection must not mask carburetor restriction at high RPM")
end

local cranking = runScenario(1, 500, 1, 0.1)
assertGreater(cranking.startProtection, 0.99, "starter protection while cranking")
assertGreater(cranking.engineCoef, 0.90, "cranking torque protection")

local function runIdleAccelPumpScenario(accelPumpCoef)
  local activePartName = "ultra_realism_carb_test_idle_accel"
  local engine = {
    displacementL = 5.7,
    idleRPM = 750,
    maxRPM = 7000,
    maxTorque = 520,
    requiredEnergyType = "gasoline",
    fundamentalFrequencyCylinderCount = 8,
    throttle = 0.05,
    requestedThrottle = 0.05,
    idleThrottle = 0.05,
    starterEngagedCoef = 0,
    starterMaxAV = 750 * 0.7 / 9.5493,
    outputAV1 = 750 / 9.5493,
    outputRPM = 750,
    outputTorqueState = 1,
    intakeAirDensityCoef = 1,
    friction = 18,
    dynamicFriction = 0.02,
    thermals = {cylinderWallTemperature = 95, oilTemperature = 92, engineBlockTemperature = 90},
  }
  electrics = {values = {rpm = 750, throttle = 0, brake = 0, steering_input = 0, wheelspeed = 0}}
  powertrain = {getDevice = function() return engine end}
  obj = {getEnvTemperature = function() return 298.15 end, getEnvPressure = function() return 101325 end}
  log = function() end
  beamstate = nil
  damageTracker = nil
  local carbDef = carbDefinition(1, activePartName)
  carbDef.ultraRealismCarburetor.accelPumpCoef = accelPumpCoef
  v = {
    data = {
      activeParts = {["engine/topend/carburetor"] = activePartName},
      activePartsData = {[activePartName] = carbDef},
      beams = {},
    },
  }
  partmgmt = {
    getConfig = function()
      return {parts = {["engine/topend/carburetor"] = activePartName}}
    end,
  }
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
    climatePreset = "game_environment",
    useBeamNGEnvironment = true,
  })
  for _ = 1, 12 do
    electrics.values.throttle = 0.12
    engine.throttle = 0.12
    engine.requestedThrottle = 0.12
    controller.updateGFX(0.05)
    controller.update(0.0005)
  end
  return {
    afr = electrics.values.ure_afr,
    lambda = electrics.values.ure_lambda,
    torqueFactor = electrics.values.ure_torqueFactor,
  }
end

local idleHolley = runIdleAccelPumpScenario(1.34)
assertGreater(idleHolley.afr, 10.0, "idle accel pump must not flood mixture")
assertGreater(idleHolley.lambda, 0.68, "idle lambda must stay above rich misfire band")
assertGreater(idleHolley.torqueFactor, 0.80, "idle stall guard keeps torque above native threshold")

local function runIdleLoadBlendScenario()
  local activePartName = "ultra_realism_carb_test_1x"
  local engine = {
    displacementL = 5.7,
    idleRPM = 750,
    maxRPM = 7000,
    maxTorque = 520,
    requiredEnergyType = "gasoline",
    fundamentalFrequencyCylinderCount = 8,
    throttle = 0.05,
    requestedThrottle = 0.05,
    idleThrottle = 0.05,
    starterEngagedCoef = 0,
    outputTorqueState = 1,
    intakeAirDensityCoef = 1,
    friction = 18,
    dynamicFriction = 0.02,
    thermals = {cylinderWallTemperature = 95, oilTemperature = 92, engineBlockTemperature = 90},
  }
  electrics = {values = {rpm = 750, throttle = 0, brake = 0, steering_input = 0, wheelspeed = 0}}
  powertrain = {getDevice = function() return engine end}
  obj = {getEnvTemperature = function() return 298.15 end, getEnvPressure = function() return 101325 end}
  log = function() end
  v = {
    data = {
      activeParts = {["engine/topend/carburetor"] = activePartName},
      activePartsData = {
        [activePartName] = carbDefinition(1, activePartName),
      },
      beams = {},
    },
  }
  partmgmt = {getConfig = function() return {parts = {["engine/topend/carburetor"] = activePartName}} end}
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
    climatePreset = "game_environment",
    useBeamNGEnvironment = true,
  })
  for _ = 1, 10 do
    controller.updateGFX(0.05)
    controller.update(0.0005)
  end
  return {
    rawTorque = electrics.values.ure_torqueFactor,
    appliedTorque = electrics.values.ure_appliedTorqueFactor,
    loadBlend = electrics.values.ure_engineEffectLoadBlend,
    engineCoef = engine.outputTorqueState,
  }
end

local idleBlend = runIdleLoadBlendScenario()
assertGreater(idleBlend.appliedTorque, 0.94, "idle load blend keeps applied torque near 1")
assertGreater(idleBlend.loadBlend, 0, "load blend telemetry present")
assertGreater(1 - idleBlend.loadBlend, 0.55, "idle should keep most of the physics penalty inactive")
assertGreater(idleBlend.engineCoef, 0.94, "idle engine coef should stay near 1")

local wotBlend = runScenario(1, 6000, 0, 0.4)
assertGreater(wotBlend.engineCoef, 0.20, "WOT still applies carb restriction")
assertNear(wotBlend.engineCoef, wotBlend.torqueFactor, 0.000001, "WOT applied torque matches physics factor")
assertGreater(wotBlend.loadBlend, 0.85, "WOT load blend fully active")

local topGearRpmSingle = runScenario(1, 4500, 0, 0.4)
local topGearRpmSix = runScenario(6, 4500, 0, 0.4)
assertGreater(topGearRpmSix.engineCoef - topGearRpmSingle.engineCoef, 0.12, "top-gear RPM torque gap")

local function runNativePartNameScenario(count, partName, rpm)
  package.loaded[controllerPath] = nil
  local carbPartData = carbDefinition(count, partName)
  carbPartData.information.name = partName
  carbPartData.slotType = "ultra_realism_carburetor"
  local engine = {
    displacementL = 4.38,
    idleRPM = 1350,
    maxRPM = 6050,
    maxTorque = 520,
    requiredEnergyType = "gasoline",
    fundamentalFrequencyCylinderCount = 8,
    throttle = 1,
    requestedThrottle = 1,
    idleThrottle = 0.05,
    starterEngagedCoef = 0,
    outputTorqueState = 1,
    intakeAirDensityCoef = 1,
    friction = 18,
    dynamicFriction = 0.02,
    thermals = {cylinderWallTemperature = 95, oilTemperature = 92, engineBlockTemperature = 90},
  }
  electrics = {values = {rpm = rpm, throttle = 1, brake = 0, steering_input = 0, wheelspeed = 45}}
  powertrain = {getDevice = function() return engine end}
  obj = {getEnvTemperature = function() return 298.15 end, getEnvPressure = function() return 101325 end}
  log = function() end
  beamstate = nil
  damageTracker = nil
  v = {
    config = {
      parts = {["engine/topend/carburetor"] = partName},
      partsTree = {
        chosenPartName = "engine",
        children = {
          topend = {
            chosenPartName = "topend",
            children = {
              carburetor = {
                chosenPartName = partName,
                slotName = "carburetor",
                partPath = "/engine/topend/carburetor",
              },
            },
          },
        },
      },
    },
    data = {
      activeParts = {["engine/topend/carburetor"] = partName},
      activePartsData = {[partName] = carbPartData},
      beams = {},
    },
  }
  partmgmt = {
    getConfig = function()
      return {
        parts = {["engine/topend/carburetor"] = partName},
        partsTree = v.config.partsTree,
      }
    end,
  }
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
    climatePreset = "game_environment",
    useBeamNGEnvironment = true,
    displacementL = 4.38,
    idleRPM = 1350,
    redlineRPM = 6050,
  })
  for _ = 1, 8 do
    controller.updateGFX(0.05)
    controller.update(0.0005)
  end
  return {
    carbCount = electrics.values.ure_carbCount,
    venturiMM = electrics.values.ure_carbPrimaryVenturiMM,
    engineCoef = engine.outputTorqueState,
    loadBlend = electrics.values.ure_engineEffectLoadBlend,
  }
end

local nativeSingle = runNativePartNameScenario(1, "ultra_realism_carb_weber_40_dcoe_28", 6000)
local nativeSix = runNativePartNameScenario(
  6,
  "ultra_realism_native_ceep_eb707dbe32_carb_six_weber_40_dcoe_32",
  6000
)
assertNear(nativeSingle.carbCount, 1, 0.001, "native single carb count")
assertNear(nativeSix.carbCount, 6, 0.001, "native six carb count")
assertGreater(nativeSix.engineCoef - nativeSingle.engineCoef, 0.12, "native CEEP-style torque gap")

print(string.format(
  "Carb physics passed: 1x area %.6f m2 maxFlow %.4f restriction %.3f coef %.3f; 6x area %.6f m2 maxFlow %.4f restriction %.3f coef %.3f",
  single.area,
  single.maxFlow,
  single.restriction,
  single.engineCoef,
  six.area,
  six.maxFlow,
  six.restriction,
  six.engineCoef
))