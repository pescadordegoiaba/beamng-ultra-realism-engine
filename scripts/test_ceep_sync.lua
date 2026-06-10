local controllerPath = "UltraRealismEngine_Prototype/lua/vehicle/controller/ultraRealismEngine.lua"

local function approx(actual, expected, tolerance, label)
  if math.abs((actual or 0) - expected) > tolerance then
    error(string.format("%s: expected %.3f, got %.3f", label, expected, actual or -1))
  end
end

local function syncPart(slotType)
  return {
    slotType = slotType,
    information = {name = "Automatic - Use CEEP Native Part"},
    ultraRealismNativeSync = {integration = "ceep", category = slotType},
  }
end

local function runScenario(name, nativeParts, expected, carbOverride)
  local integration = expected.integration or "ceep"
  local engine = {
    displacementL = 5.7,
    idleRPM = 750,
    maxRPM = 7000,
    maxTorque = 520,
    requiredEnergyType = "gasoline",
    fundamentalFrequencyCylinderCount = 8,
    throttle = 0.72,
    requestedThrottle = 0.72,
    idleThrottle = 0.05,
    starterEngagedCoef = 0,
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
      rpm = 4200,
      throttle = 0.72,
      brake = 0,
      steering_input = 0,
      wheelspeed = 22,
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

  local activePartsData = {
    ["ultra_realism_" .. integration .. "_sync_carburetor"] = syncPart("ultra_realism_carburetor"),
    ["ultra_realism_" .. integration .. "_sync_camshaft"] = syncPart("ultra_realism_camshaft"),
  }
  if expected.legacyCamStock then
    activePartsData["ultra_realism_" .. integration .. "_sync_camshaft"] = nil
    activePartsData.ultra_realism_cam_stock = {
      slotType = "ultra_realism_camshaft",
      information = {name = "Stock Camshaft"},
    }
  end
  local activeParts = {}
  for partName, partData in pairs(nativeParts) do
    activePartsData[partName] = partData
    activeParts["engine/" .. tostring(partData.slotType or partName)] = partName
  end
  activeParts["engine/ultra_realism_carburetor"] = "ultra_realism_" .. integration .. "_sync_carburetor"
  activeParts["engine/ultra_realism_camshaft"] = expected.legacyCamStock and "ultra_realism_cam_stock"
    or ("ultra_realism_" .. integration .. "_sync_camshaft")
  if carbOverride then
    activePartsData.ultra_realism_test_override = carbOverride
    activeParts["engine/ultra_realism_carburetor"] = "ultra_realism_test_override"
  end
  partmgmt = {
    getConfig = function()
      return {parts = activeParts}
    end,
  }
  v = {data = {activeParts = activeParts, activePartsData = activePartsData, beams = {}}}

  local controller = assert(dofile(controllerPath))
  controller.init({
    integrationMode = integration,
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
  approx(electrics.values.ure_nativeCarbSynced, expected.nativeCarb, 0.01, name .. " native carb sync")
  approx(electrics.values.ure_nativeCamSynced, expected.nativeCam, 0.01, name .. " native cam sync")
  approx(electrics.values.ure_carbCount, expected.count or 1, 0.01, name .. " carb count")
  approx(electrics.values.ure_carbBarrels, expected.barrels or 1, 0.01, name .. " barrel count")
  approx(electrics.values.ure_camStage, expected.camStage or 0, 0.01, name .. " cam stage")
  if expected.mode == 1 and (electrics.values.ure_carbRatedCFM or 0) <= 0 then
    error(name .. ": calculated carburetor CFM must be positive")
  end
end

runScenario("CEEP 1x4 performance + sport stage 1", {
  c_perf_carb = {
    slotType = "c_sb_v8_stockohv_singlecarb",
    information = {name = "1x4-Barrel Performance Carburetor"},
  },
  c_cam_stage1 = {
    slotType = "c_v8_camshaft_petrol",
    information = {name = "Sport Camshaft Stage 1"},
  },
}, {
  mode = 1,
  nativeCarb = 1,
  nativeCam = 1,
  count = 1,
  barrels = 4,
  camStage = 1,
  legacyCamStock = true,
})

runScenario("CEEP twin race + race stage 2", {
  c_twin_race_carb = {
    slotType = "c_sb_v8_stockohv_twincarb",
    information = {name = "Twin 4-Barrel Race Performance Carburetors"},
  },
  c_cam_race_stage2 = {
    slotType = "c_v8_camshaft_petrol",
    information = {name = "Race Camshaft Stage 2"},
  },
}, {mode = 1, nativeCarb = 1, nativeCam = 1, count = 2, barrels = 4, camStage = 3.25})

runScenario("CEEP six-pack + drag stage 3", {
  c_sixpack = {
    slotType = "c_v8_sixpack_carb",
    information = {name = "6-Pack Carburetors"},
  },
  c_cam_drag_stage3 = {
    slotType = "c_v8_camshaft_petrol",
    information = {name = "Drag Race Camshaft Stage 3"},
  },
}, {mode = 1, nativeCarb = 1, nativeCam = 1, count = 3, barrels = 2, camStage = 4.0})

runScenario("CEEP EFI remains EFI", {
  c_efi = {
    slotType = "c_v8_efi",
    information = {name = "Sequential Electronic Fuel Injection"},
  },
  c_cam_stock = {
    slotType = "c_v8_camshaft_petrol",
    information = {name = "Stock Camshaft"},
  },
}, {mode = 2, nativeCarb = 0, nativeCam = 1, count = 1, barrels = 1, camStage = 0})

runScenario("URE camshaft inside native CEEP slot wins", {
  c_native_carb = {
    slotType = "c_v8_carb",
    information = {name = "1-Barrel Carburetor"},
  },
  ultra_realism_native_ceep_cam_stage3 = {
    slotType = "c_v8_camshaft_petrol",
    ultraRealismCategory = "ultra_realism_camshaft",
    information = {name = "Ultra Realism - Race Camshaft Stage 3"},
  },
}, {mode = 1, nativeCarb = 1, nativeCam = 0, count = 1, barrels = 1, camStage = 3.5})

runScenario("Ultra Realism carb override wins", {
  c_native_carb = {
    slotType = "c_v8_carb",
    information = {name = "1-Barrel Carburetor"},
  },
  c_cam_stage3 = {
    slotType = "c_v8_camshaft_petrol",
    information = {name = "Sport Camshaft Stage 3"},
  },
}, {mode = 1, nativeCarb = 0, nativeCam = 1, count = 4, barrels = 2, camStage = 3}, {
  slotType = "ultra_realism_carburetor",
  information = {name = "Quad Weber 40 DCOE"},
  ultraRealismCarburetor = {
    modelId = 404,
    count = 4,
    primaryBarrels = 2,
    secondaryBarrels = 0,
    primaryBoreMM = 40,
    secondaryBoreMM = 40,
    primaryVenturiMM = 30,
    secondaryVenturiMM = 30,
    mainJetMM = 1.15,
    ratedCFM = 1280,
    ratingPressureDropPa = 5079,
    secondaryType = "synchronous",
  },
})

runScenario("Ford native carb and cam synchronize", {
  ford_holley = {
    slotType = "ford_v8_carburetor",
    information = {name = "Twin 4-Barrel Performance Carburetors"},
  },
  ford_cam = {
    slotType = "ford_v8_camshaft",
    information = {name = "Race Camshaft Stage 1"},
  },
}, {
  integration = "ford",
  mode = 1,
  nativeCarb = 1,
  nativeCam = 1,
  count = 2,
  barrels = 4,
  camStage = 3,
})

print("CEEP/Ford native tuning synchronization tests passed")
