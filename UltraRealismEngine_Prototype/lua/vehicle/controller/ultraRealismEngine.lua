--[[
UltraRealismEngine.lua
Auxiliary BeamNG.drive vehicle controller for combustion realism.

It models:
- ambient temperature, pressure, humidity and abrupt climate transitions
- moist-air density correction
- ignition timing versus estimated MBT timing
- carburetor Venturi / main jet / idle circuit / power valve / accelerator pump
- fuel injection with injector duty telemetry
- AFR, lambda, fuel flow and fuel used telemetry
- knock, misfire, vapor lock, carb icing, plug fouling and progressive damage
- damper heat, suspension fade and optional runtime damper/spring beam fade

This is intentionally defensive. BeamNG vehicles vary a lot, so missing fields are
guarded and the controller falls back to telemetry instead of crashing.
]]

local M = {}
M.type = "auxiliary"
M.defaultOrder = 6500
local MOD_VERSION = "0.21.1"

local cfg = {}
local st = {}
local installedPartsCache = nil
local activePartEntriesCache = nil
local partsScanCount = 0
local engine = nil
local lastLogT = 0
local inferCarbDefinitionFromPartName
local resolveIntegrationMode
local getIntegrationMode
local usesNativePartSync
local getActivePartsText
local refreshRuntimePartModules
local engineBridge = nil
local ureOwnership = nil
local urePartCurves = nil
local ureBus = nil
local ureEfi = nil
local ureDiesel = nil
pcall(function() engineBridge = rerequire("powertrain/ultraRealismEngineBridge") end)
pcall(function() ureOwnership = rerequire("controller/ultra_realism/ownership") end)
pcall(function() urePartCurves = rerequire("controller/ultra_realism/partCurves") end)
pcall(function() ureBus = rerequire("controller/ultra_realism/bus") end)
pcall(function() ureEfi = rerequire("controller/ultra_realism/induction_efi") end)
pcall(function() ureDiesel = rerequire("controller/ultra_realism/induction_diesel") end)

local function clamp(x, lo, hi)
  x = tonumber(x) or lo
  if x ~= x then return lo end
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function lerp(a, b, t)
  return a + (b - a) * clamp(t, 0, 1)
end

local function safeNumber(v, default)
  local n = tonumber(v)
  if n == nil then return default end
  return n
end

local function finiteNonNegative(v, default)
  local n = tonumber(v)
  if n == nil or n ~= n or n == math.huge or n == -math.huge or n < 0 then
    return default
  end
  return n
end

local function safeNested(root, ...)
  local cur = root
  for i = 1, select("#", ...) do
    if type(cur) ~= "table" then return nil end
    cur = cur[select(i, ...)]
    if cur == nil then return nil end
  end
  return cur
end

local function bool(v, default)
  if v == nil then return default end
  if v == true or v == 1 or v == "true" or v == "yes" then return true end
  if v == false or v == 0 or v == "false" or v == "no" then return false end
  return default
end

local function chancePerSecond(probPerSecond, dt)
  if probPerSecond <= 0 then return false end
  return math.random() < (1 - math.exp(-probPerSecond * math.max(dt, 0)))
end

local function lowerText(v)
  if type(v) == "table" then
    local out = ""
    for _, item in pairs(v) do
      out = out .. " " .. tostring(item)
    end
    return string.lower(out)
  end
  return string.lower(tostring(v or ""))
end

local function indexedTableSize(t)
  if not t then return 0 end
  if tableSizeC then
    local ok, n = pcall(tableSizeC, t)
    if ok and n then return n end
  end
  local maxIndex = -1
  for k, _ in pairs(t) do
    if type(k) == "number" and k > maxIndex then maxIndex = k end
  end
  return maxIndex + 1
end

local function getElectricsValue(name, default)
  if electrics and electrics.values and electrics.values[name] ~= nil then
    return electrics.values[name]
  end
  return default
end

local function setElectricsValue(name, value)
  if electrics and electrics.values then
    electrics.values[name] = value
  end
end

local function getMainEngine()
  if powertrain and powertrain.getDevice then
    local ok, dev = pcall(powertrain.getDevice, "mainEngine")
    if ok then return dev end
  end
  return nil
end

local function hasForcedInduction()
  if not engine then return false end
  return (engine.turbocharger and engine.turbocharger.isExisting)
      or (engine.supercharger and engine.supercharger.isExisting)
      or (engine.nitrousOxideInjection and engine.nitrousOxideInjection.isExisting)
      or false
end

local function getEngineCylinderCount()
  if not engine then return cfg.injectorCount or 4 end

  local candidates = {
    engine.fundamentalFrequencyCylinderCount,
    safeNested(engine, "soundConfiguration", "engine", "params", "fundamentalFrequencyCylinderCount"),
    safeNested(engine, "soundConfiguration", "exhaust", "params", "fundamentalFrequencyCylinderCount")
  }

  for _, value in ipairs(candidates) do
    local cyl = tonumber(value)
    if cyl and cyl >= 1 and cyl <= 24 then
      return math.floor(cyl + 0.5)
    end
  end

  local coef = tonumber(safeNested(engine, "soundConfiguration", "engine", "params", "fundamentalFrequencyRPMCoef"))
            or tonumber(safeNested(engine, "soundConfiguration", "exhaust", "params", "fundamentalFrequencyRPMCoef"))
  if coef and coef > 0 then
    local cyl = coef * 120
    if cyl >= 1 and cyl <= 24 then
      return math.floor(cyl + 0.5)
    end
  end

  return math.floor(clamp(cfg.injectorCount or 4, 1, 16) + 0.5)
end

local function getEngineMaxTorque()
  if not engine then return nil end
  return tonumber(engine.maxTorque)
      or tonumber(safeNested(engine, "torqueData", "maxTorque"))
      or tonumber(engine.maxTorqueLimit)
      or nil
end

local function getEffectiveThrottle(driverThrottle)
  local engineThrottle = engine and tonumber(engine.throttle) or nil
  local requestedThrottle = engine and tonumber(engine.requestedThrottle) or nil
  local idleThrottle = engine and tonumber(engine.idleThrottle) or nil
  return clamp(math.max(driverThrottle or 0, engineThrottle or 0, requestedThrottle or 0, idleThrottle or 0), 0, 1)
end

local function getEnginePhysicsRPM()
  if engine then
    local outputRPM = tonumber(engine.outputRPM)
    if outputRPM then return math.abs(outputRPM) end
    local outputAV = tonumber(engine.outputAV1)
    if outputAV then return math.abs(outputAV) * 9.5493 end
  end
  return getElectricsValue("rpm", getElectricsValue("engineRPM", cfg.idleRPM))
end

local function getNativeStallGuardRPM()
  if engine and tonumber(engine.starterMaxAV) then
    return math.abs(engine.starterMaxAV) * 9.5493 * 0.8
  end
  local idleRPM = tonumber(engine and engine.idleRPM) or cfg.idleRPM
  return idleRPM * 0.56
end

local function getStarterProtection(rpm)
  local starterCoef = engine and clamp(tonumber(engine.starterEngagedCoef) or 0, 0, 1) or 0
  local resetProtection = clamp((cfg.startupProtectionSeconds - (st.runTime or 0)) / math.max(cfg.startupProtectionSeconds, 0.001), 0, 1)
  local lowRpmProtection = clamp((cfg.idleRPM * 1.18 - rpm) / math.max(cfg.idleRPM * 0.70, 1), 0, 1)
  return clamp(math.max(starterCoef, lowRpmProtection, resetProtection * lowRpmProtection), 0, 1)
end

local function clearFalseStallState(physicsRPM, torqueFactor, throttle)
  if not engine or cfg.allowStall then return end
  local starterEngaged = clamp(tonumber(engine.starterEngagedCoef) or 0, 0, 1)
  if starterEngaged > 0 then return end
  local stallGuardRPM = getNativeStallGuardRPM()
  local severeFailure = math.max(st.vaporLock or 0, st.carbIce or 0, st.misfire or 0)
  if physicsRPM > stallGuardRPM * 0.95 and torqueFactor > 0.55 and severeFailure < 0.82 and throttle < 0.72 then
    pcall(function()
      engine.isStalled = false
      engine.stallTimer = 1
    end)
  end
end

local function applyIdleStallGuard(physicsRPM, torqueFactor, throttle)
  if not engine or cfg.allowStall then return torqueFactor end
  local starterEngaged = clamp(tonumber(engine.starterEngagedCoef) or 0, 0, 1)
  if starterEngaged > 0 then return torqueFactor end

  local stallGuardRPM = getNativeStallGuardRPM()
  local rpmMargin = physicsRPM / math.max(stallGuardRPM, 1)
  if throttle < 0.28 and rpmMargin < 1.12 then
    local boost = clamp((1.12 - rpmMargin) / 0.12, 0, 1)
    torqueFactor = math.max(torqueFactor, lerp(cfg.idleStallGuardMinTorque, cfg.startMinTorqueFactor, boost))
  end
  return torqueFactor
end

-- BeamNG applies powertrain.update() before controller.update() each physics step.
-- Carb restriction is irrelevant at idle (demand~0), so performance scaling is softened
-- there. Failure penalties (misfire/vapor/ice) always apply so faults remain noticeable.
local function resolveAppliedTorqueFactor(performanceFactor, failureFactor, inductionLoad, throttle, inductionFlowRatio)
  performanceFactor = finiteNonNegative(performanceFactor, 1)
  failureFactor = finiteNonNegative(failureFactor, 1)
  if not cfg.loadProportionalEngineEffect then
    return finiteNonNegative(performanceFactor * failureFactor, 1)
  end
  local flowDeficit = 1 - clamp(inductionFlowRatio or 1, 0, 1)
  local rpm = getElectricsValue("rpm", getElectricsValue("engineRPM", cfg.idleRPM))
  local rpmLoad = clamp(rpm / math.max(cfg.redlineRPM, cfg.idleRPM + 200), 0, 1.15)
  local midThrottleBlend = throttle * 0.55 + rpmLoad * throttle * 0.45
  local demandSignal = math.max(
    inductionLoad,
    flowDeficit,
    st.venturiDemandRatio or 0,
    throttle * 0.52,
    rpmLoad * throttle * 0.85,
    midThrottleBlend * 0.68,
    (1 - clamp(st.breathingScore or 1, 0.4, 1.25) / 1.25) * throttle
  )
  if throttle < 0.25 and rpm < cfg.idleRPM * 1.6 then
    demandSignal = demandSignal * clamp(throttle / 0.25, 0, 1)
  end
  local blend = clamp(demandSignal * cfg.loadProportionalEngineEffectGain, 0, 1)
  st.engineEffectLoadBlend = blend
  local blendedPerformance = finiteNonNegative(lerp(1.0, performanceFactor, blend), 1)
  return finiteNonNegative(blendedPerformance * failureFactor, 1)
end

local function publishEngineBridge(appliedTorqueFactor, throttle, fuelKgS, airKgS, lambda, afr, mixEff)
  if not engineBridge or not engineBridge.publishControllerState then return end
  local ultraActive = engine and engine.ureUltraEngine == true
  engineBridge.publishControllerState({
    active = cfg.enableEngineEffect and (ultraActive or usesNativePartSync()),
    appliedTorqueFactor = appliedTorqueFactor,
    engineEffectTarget = st.engineEffectTarget or 1,
    engineDamageTorqueCoef = st.engineDamageTorqueCoef or 1,
    suppressFalseStall = cfg.suppressFalseStallUI,
    severeFailure = math.max(st.vaporLock or 0, st.carbIce or 0, st.misfire or 0),
    effectiveThrottle = throttle,
    integrationMode = getIntegrationMode(),
    integratedFuel = ultraActive,
    fuelIntegrationBlend = ultraActive and 1 or 0,
    fuelKgS = fuelKgS or 0,
    airKgS = airKgS or 0,
    lambda = lambda or 1,
    afr = afr or cfg.stoichAFR,
    mixtureEfficiency = mixEff or 1,
    fuelDensityKgM3 = cfg.fuelDensityKgM3,
    runtimeTorqueMult = st.runtimeTorqueMult or 1,
    inductionFlowRatio = st.inductionFlowRatio or 1,
    manifoldPressurePa = st.manifoldPressurePa or cfg.pressurePa or 101325,
    forcedInductionBlend = st.forcedInductionBlend or 0,
    nativePartSyncActive = usesNativePartSync() and (st.nativeOwnershipActive or false),
  })
  setElectricsValue("ure_integratedFuel", ultraActive and 1 or 0)
  setElectricsValue("ure_suppressFalseStallUI", cfg.suppressFalseStallUI and 1 or 0)
  setElectricsValue("ure_fuelDensityKgM3", cfg.fuelDensityKgM3)
end

local function cacheBridgePayload(appliedTorqueFactor, throttle, fuelKgS, airKgS, lambda, afr, mixEff)
  st.bridgePayload = {
    appliedTorqueFactor = appliedTorqueFactor,
    throttle = throttle,
    fuelKgS = fuelKgS,
    airKgS = airKgS,
    lambda = lambda,
    afr = afr,
    mixEff = mixEff,
  }
end

local function publishCachedEngineBridge()
  local payload = st.bridgePayload
  if not payload then return end
  publishEngineBridge(
    payload.appliedTorqueFactor,
    payload.throttle,
    payload.fuelKgS,
    payload.airKgS,
    payload.lambda,
    payload.afr,
    payload.mixEff
  )
end

local function publishNativeRunningState(physicsRPM, appliedTorqueFactor, throttle)
  if not cfg.suppressFalseStallUI or not engine then return end
  local starterEngaged = clamp(tonumber(engine.starterEngagedCoef) or 0, 0, 1)
  if starterEngaged > 0 then return end
  local stallGuardRPM = getNativeStallGuardRPM()
  local severeFailure = math.max(st.vaporLock or 0, st.carbIce or 0, st.misfire or 0)
  if physicsRPM > stallGuardRPM * 0.90 and appliedTorqueFactor > 0.60 and severeFailure < 0.85 and throttle < 0.55 then
    setElectricsValue("engineRunning", 1)
    setElectricsValue("running", 1)
  end
end

function resolveIntegrationMode()
  local configured = string.lower(tostring(cfg.integrationMode or "generic"))
  if configured == "ceep" or configured == "ford" then return configured end
  if configured == "auto" or configured == "generic" then
    local text = getActivePartsText()
    if text:find("ceep", 1, true) or text:find("classic_engine", 1, true) then return "ceep" end
    if text:find("ford_engine", 1, true) or text:find("jitter", 1, true) then return "ford" end
  end
  return configured
end

function getIntegrationMode()
  return st.resolvedIntegrationMode or cfg.integrationMode or "generic"
end

function usesNativePartSync()
  local mode = getIntegrationMode()
  return mode == "ceep" or mode == "ford"
end

local function getPartData(partName)
  if not partName or not v or not v.data then return nil end
  local data = v.data.activePartsData and v.data.activePartsData[partName]
  if type(data) == "table" then return data end
  data = v.data.parts and v.data.parts[partName]
  if type(data) == "table" then return data end
  return nil
end

local function walkPartsTree(node, callback, parentSlot)
  if type(node) ~= "table" then return end
  local partName = node.chosenPartName
  local slotName = tostring(node.slotName or node.id or parentSlot or "")
  local partPath = node.partPath
  if partName and partName ~= "" then
    callback(slotName, tostring(partName), type(partPath) == "string" and partPath or nil)
  end
  local children = node.children
  if type(children) == "table" then
    for childSlot, child in pairs(children) do
      walkPartsTree(child, callback, tostring(childSlot))
    end
  end
end

local function registerInstalledPart(installed, slotName, partName, partPath)
  if not partName or partName == "" then return end
  local key = (partPath and partPath ~= "") and partPath or slotName
  if not key or key == "" then key = partName end
  installed[tostring(key)] = tostring(partName)
end

local function invalidateInstalledPartsCache()
  installedPartsCache = nil
  activePartEntriesCache = nil
end

local function buildInstalledParts()
  local installed = {}

  if v and v.config then
    if type(v.config.parts) == "table" then
      for slotName, partName in pairs(v.config.parts) do
        registerInstalledPart(installed, tostring(slotName), partName)
      end
    end
    if type(v.config.partsTree) == "table" then
      walkPartsTree(v.config.partsTree, function(slotName, partName, partPath)
        registerInstalledPart(installed, slotName, partName, partPath)
      end)
    end
  end

  if partmgmt and partmgmt.getConfig then
    local ok, config = pcall(partmgmt.getConfig)
    if ok and type(config) == "table" then
      if type(config.parts) == "table" then
        for slotName, partName in pairs(config.parts) do
          registerInstalledPart(installed, tostring(slotName), partName)
        end
      end
      if type(config.partsTree) == "table" then
        walkPartsTree(config.partsTree, function(slotName, partName, partPath)
          registerInstalledPart(installed, slotName, partName, partPath)
        end)
      end
    end
  end

  if v and v.data and type(v.data.activeParts) == "table" then
    for slotName, partName in pairs(v.data.activeParts) do
      registerInstalledPart(installed, tostring(slotName), partName)
    end
  end

  if beamstate and type(beamstate.activeParts) == "table" then
    for slotName, partName in pairs(beamstate.activeParts) do
      registerInstalledPart(installed, tostring(slotName), partName)
    end
  end

  return installed
end

local function getInstalledParts()
  if installedPartsCache then
    return installedPartsCache
  end
  partsScanCount = partsScanCount + 1
  installedPartsCache = buildInstalledParts()
  return installedPartsCache
end

local function computeActivePartsSignature()
  local chunks = {}
  for slotName, partName in pairs(buildInstalledParts()) do
    table.insert(chunks, slotName .. "=" .. partName)
  end
  table.sort(chunks)
  return table.concat(chunks, "|")
end

function getActivePartsText()
  local chunks = {}

  for slotName, partName in pairs(getInstalledParts()) do
    local partData = getPartData(partName)
    if not (partData and type(partData.ultraRealismNativeSync) == "table") then
      table.insert(chunks, tostring(slotName))
      table.insert(chunks, tostring(partName))
    end
    if partData and type(partData.ultraRealismNativeSync) ~= "table" then
      table.insert(chunks, tostring(partData.slotType or ""))
      if partData.information then
        table.insert(chunks, tostring(partData.information.name or ""))
      end
    end
  end

  return string.lower(table.concat(chunks, " "))
end

local function isUltraRealismPart(partName, partData)
  local name = string.lower(tostring(partName or ""))
  local slotType = string.lower(tostring(partData and partData.slotType or ""))
  return name:find("ultra_realism_", 1, true) == 1
      or slotType:find("ultra_realism_", 1, true) == 1
end

local nativeLegacyNeutralParts = {
  ultra_realism_intake_stock = true,
  ultra_realism_spacer_none = true,
  ultra_realism_fuel_delivery_stock = true,
  ultra_realism_rotating_stock = true,
  ultra_realism_short_block_stock = true,
  ultra_realism_stroker_stock = true,
  ultra_realism_pistons_cast = true,
  ultra_realism_rings_stock = true,
  ultra_realism_bearings_stock = true,
  ultra_realism_crank_rods_stock = true,
  ultra_realism_cam_stock = true,
  ultra_realism_valvetrain_stock = true,
  ultra_realism_heads_stock = true,
  ultra_realism_head_gasket_stock = true,
  ultra_realism_ignition_stock = true,
  ultra_realism_oil_stock = true,
}

local function activePartText(partName, partData)
  local infoName = partData and partData.information and partData.information.name or ""
  return string.lower(table.concat({
    tostring(partName or ""),
    tostring(partData and partData.slotType or ""),
    tostring(infoName),
  }, " "))
end

local function collectActivePartEntries()
  if activePartEntriesCache then
    return activePartEntriesCache
  end
  local entries = {}
  local seen = {}

  for slotKey, partName in pairs(getInstalledParts()) do
    if partName and not seen[slotKey] then
      seen[slotKey] = true
      local partData = getPartData(partName) or {
        information = {name = tostring(partName)},
        slotType = "",
      }
      table.insert(entries, {
        name = partName,
        data = partData,
        slot = slotKey,
      })
    end
  end

  activePartEntriesCache = entries
  return entries
end

local function getActiveCarbDefinition()
  local bestScore, bestDef, bestName = -1, nil, nil
  for _, entry in ipairs(collectActivePartEntries()) do
    local def = entry.data.ultraRealismCarburetor
    if type(def) == "table" then
      local score = 0
      local slot = lowerText(entry.slot)
      local slotType = lowerText(entry.data.slotType or "")
      local partName = lowerText(entry.name)
      if slot:find("carb", 1, true) then score = score + 30 end
      if slotType:find("carb", 1, true) then score = score + 24 end
      if partName:find("carb_", 1, true) then score = score + 18 end
      if type(entry.data.ultraRealismNativeSync) == "table" then score = score - 80 end
      if score > bestScore then
        bestScore, bestDef, bestName = score, def, entry.name
      end
    end
  end
  return bestDef, bestName
end

local function syncActivePartsState(dt)
  dt = dt or 0.016
  st.partsSyncTimer = (st.partsSyncTimer or 0) + dt
  local interval = cfg.partsSyncInterval or 0.5
  if st.partsSyncTimer < interval and st.activePartsSignature ~= "" then
    return false
  end
  st.partsSyncTimer = 0

  local signature = computeActivePartsSignature()
  if signature == st.activePartsSignature then return false end
  invalidateInstalledPartsCache()
  st.activePartsSignature = signature
  st.activePartsCount = #collectActivePartEntries()
  st.resolvedIntegrationMode = resolveIntegrationMode()
  st.carbSetupScanned = false
  st.enginePartsAnalyzed = false
  refreshRuntimePartModules()
  return true
end

function refreshRuntimePartModules()
  local entries = collectActivePartEntries()
  local nativeSync = usesNativePartSync()
  if ureOwnership and ureOwnership.refresh then
    ureOwnership.refresh(entries, nativeSync)
    st.nativeOwnershipActive = ureOwnership.anyOwned and ureOwnership.anyOwned() or false
  end
  if urePartCurves and urePartCurves.refresh then
    st.runtimeTorqueMult = urePartCurves.refresh(entries, ureOwnership) or 1
    st.partCurvesSignature = urePartCurves.getSignature and urePartCurves.getSignature() or ""
  end
  if ureBus and ureBus.publish then
    ureBus.publish("partsChanged", {entries = entries, nativeSync = nativeSync})
  end
end

local function getSelectedUltraOverrideText(slotType)
  local matches = {}
  for _, entry in ipairs(collectActivePartEntries()) do
    local partName, partData = entry.name, entry.data
    if (partData.slotType == slotType or partData.ultraRealismCategory == slotType)
      and type(partData.ultraRealismNativeSync) ~= "table"
      and not (usesNativePartSync() and nativeLegacyNeutralParts[partName]) then
      table.insert(matches, activePartText(partName, partData))
    end
  end
  table.sort(matches)
  return matches[1]
end

local function getBestNativePartEntry(category)
  local candidates = {}
  for _, entry in ipairs(collectActivePartEntries()) do
    local partName, partData = entry.name, entry.data
    if not isUltraRealismPart(partName, partData) then
      local text = activePartText(partName, partData)
      local score = 0

      if category == "carburetor" then
        if text:find("carburetor", 1, true) then score = score + 14 end
        if text:find(" carb", 1, true) then score = score + 8 end
        if text:find("barrel", 1, true) or text:find("bbl", 1, true) then score = score + 12 end
        if tostring(partData.slotType or ""):lower():find("carb", 1, true) then score = score + 10 end
        if text:find("manifold", 1, true) then score = score - 12 end
        if text:find("turbo", 1, true) or text:find("supercharger", 1, true)
          or text:find("twincharger", 1, true) or text:find("procharger", 1, true)
          or text:find("throttle body", 1, true) or text:find("ecoboost", 1, true) then
          score = score - 24
        end
      elseif category == "camshaft" then
        if text:find("camshaft", 1, true) then score = score + 18 end
        if tostring(partData.slotType or ""):lower():find("cam", 1, true) then score = score + 10 end
        if text:find("cam chop", 1, true) then score = score - 12 end
      end

      if score > 0 then
        table.insert(candidates, {score = score, text = text, name = partName})
      end
    end
  end

  table.sort(candidates, function(a, b)
    if a.score == b.score then return a.text < b.text end
    return a.score > b.score
  end)
  return candidates[1]
end

local function getBestNativePartText(category)
  local entry = getBestNativePartEntry(category)
  return entry and entry.text or nil
end

local function getActivePartTable(key)
  if not v or not v.data then return nil end

  if type(v.data[key]) == "table" then
    return v.data[key]
  end

  local bestScore, bestValue = -1, nil
  for _, entry in ipairs(collectActivePartEntries()) do
    local partName, partData = entry.name, entry.data
    local value = partData[key]
    if type(value) == "table" then
      local score = 0
      if isUltraRealismPart(partName, partData) then
        if type(partData.ultraRealismNativeSync) == "table" then
          score = score - 40
        else
          score = score + 30
        end
      end
      if key == "ultraRealismCarburetor" then
        local slot = lowerText(entry.slot or "")
        local slotType = lowerText(partData.slotType or "")
        if slot:find("carb", 1, true) then score = score + 30 end
        if slotType:find("carb", 1, true) then score = score + 24 end
        if slotType:find("intake", 1, true) then score = score + 8 end
      end
      if score > bestScore then
        bestScore, bestValue = score, value
      end
    end
  end

  return bestValue
end

local function applyStructuredCarbDefinition(def)
  if type(def) ~= "table" then return false end

  local count = math.floor(clamp(safeNumber(def.count, 1), 1, 12) + 0.5)
  local primaryBarrels = math.floor(clamp(safeNumber(def.primaryBarrels, 1), 1, 4) + 0.5)
  local secondaryBarrels = math.floor(clamp(safeNumber(def.secondaryBarrels, 0), 0, 4) + 0.5)
  local secondaryType = string.lower(tostring(def.secondaryType or "synchronous"))

  cfg.carbCount = count
  cfg.carbPrimaryBarrels = primaryBarrels
  cfg.carbSecondaryBarrels = secondaryBarrels
  cfg.carbBarrels = primaryBarrels + secondaryBarrels
  cfg.carbSecondaryType = secondaryType
  cfg.carbProgressive = secondaryBarrels > 0 and secondaryType ~= "synchronous"
  cfg.secondaryThrottleStart = clamp(safeNumber(def.secondaryStart, cfg.secondaryThrottleStart), 0.10, 0.92)

  cfg.carbPrimaryBoreMM = math.max(safeNumber(def.primaryBoreMM, cfg.carbThrottleBoreMM), 1)
  cfg.carbSecondaryBoreMM = math.max(safeNumber(def.secondaryBoreMM, cfg.carbPrimaryBoreMM), 1)
  cfg.carbPrimaryVenturiMM = math.max(safeNumber(def.primaryVenturiMM, cfg.carbVenturiMM), 1)
  cfg.carbSecondaryVenturiMM = math.max(safeNumber(def.secondaryVenturiMM, cfg.carbPrimaryVenturiMM), 1)

  local totalBarrels = math.max(primaryBarrels + secondaryBarrels, 1)
  cfg.carbThrottleBoreMM = math.sqrt(
    (primaryBarrels * cfg.carbPrimaryBoreMM * cfg.carbPrimaryBoreMM
      + secondaryBarrels * cfg.carbSecondaryBoreMM * cfg.carbSecondaryBoreMM)
    / totalBarrels
  )
  cfg.carbVenturiMM = math.sqrt(
    (primaryBarrels * cfg.carbPrimaryVenturiMM * cfg.carbPrimaryVenturiMM
      + secondaryBarrels * cfg.carbSecondaryVenturiMM * cfg.carbSecondaryVenturiMM)
    / totalBarrels
  )
  cfg.venturiDiameterRatio = cfg.carbThrottleBoreMM / math.max(cfg.carbVenturiMM, 0.1)
  cfg.mainJetMM = math.max(safeNumber(def.mainJetMM, cfg.mainJetMM), 0.05)
  cfg.carbRatedCFM = math.max(safeNumber(def.ratedCFM, 0), 0)
  cfg.carbRatingPressureDropPa = math.max(safeNumber(def.ratingPressureDropPa, 5079), 100)
  cfg.carbDischargeCoef = clamp(safeNumber(def.dischargeCoef, cfg.carbDischargeCoef), 0.45, 1.10)
  cfg.carbBoosterSignalCoef = clamp(safeNumber(def.boosterSignalCoef, 1), 0.55, 1.60)
  cfg.carbAccelPumpCoef = clamp(safeNumber(def.accelPumpCoef, 1), 0.50, 1.80)

  st.carbModelId = safeNumber(def.modelId, 0)
  st.carbStructuredDefinition = true
  st.carbNativeDefinition = false
  st.carbSetupDetected = true
  return true
end

local function textHasAny(text, needles)
  for _, needle in ipairs(needles) do
    if text:find(needle, 1, true) then return true end
  end
  return false
end

local function applyNativeCarbDefinition(text)
  if not text or text == "" then return false end

  local count, barrels
  local explicitCount, explicitBarrels = text:match("(%d+)%s*x%s*(%d+)[%s%-]*barrel")
  if explicitCount then
    count = tonumber(explicitCount)
    barrels = tonumber(explicitBarrels)
  else
    local bbl, bblCount = text:match("(%d+)%s*bbl%s*x%s*(%d+)")
    if bbl then
      count = tonumber(bblCount)
      barrels = tonumber(bbl)
    end
  end

  if textHasAny(text, {"six 1-barrel", "six 1 barrel"}) then count, barrels = 6, 1 end
  if textHasAny(text, {"quad 2-barrel", "quad 2 barrel"}) then count, barrels = 4, 2 end
  if textHasAny(text, {"6-pack", "6 pack", "sixpack", "six-pack"}) then count, barrels = 3, 2 end

  if not barrels then
    barrels = tonumber(text:match("(%d+)[%s%-]*barrel"))
      or tonumber(text:match("(%d+)%s*bbl"))
  end
  if not count then
    if textHasAny(text, {"quad "}) then
      count = 4
    elseif textHasAny(text, {"tripple ", "triple "}) then
      count = 3
    elseif textHasAny(text, {"twin ", "dual "}) then
      count = 2
    else
      count = 1
    end
  end

  count = math.floor(clamp(count or 1, 1, 12) + 0.5)
  barrels = math.floor(clamp(barrels or 4, 1, 4) + 0.5)

  local sizeCoef = 0.94
  if textHasAny(text, {"pro performance", "pro-performance"}) then
    sizeCoef = 1.20
  elseif textHasAny(text, {"race performance", "race carburetor", "race carb"}) then
    sizeCoef = 1.14
  elseif textHasAny(text, {"performance"}) then
    sizeCoef = 1.08
  elseif textHasAny(text, {"sport"}) then
    sizeCoef = 1.00
  end

  local baseBore = ({36, 38, 40, 43})[barrels]
  local baseVenturi = ({28, 30, 31.5, 32.5})[barrels]
  if textHasAny(text, {"dcoe"}) then
    baseBore, baseVenturi = 40, 32
  elseif textHasAny(text, {"bike carb"}) then
    baseBore, baseVenturi = 38, 30
  end

  local bore = baseBore * sizeCoef
  local venturi = math.min(baseVenturi * sizeCoef, bore * 0.86)
  local progressive = barrels >= 4 or textHasAny(text, {"progressive", "eco-sport", "eco sport"})
  local primaryBarrels = progressive and math.min(2, barrels) or barrels
  local secondaryBarrels = progressive and math.max(barrels - primaryBarrels, 0) or 0
  local ratingPressurePa = barrels <= 2 and 10158 or 5079
  local totalVenturiArea = math.pi * (venturi / 1000) * (venturi / 1000) * 0.25 * barrels * count
  local ratedM3s = 0.82 * totalVenturiArea
    * math.sqrt(2 * ratingPressurePa / math.max(cfg.referenceAirDensity, 0.1))

  cfg.carbCount = count
  cfg.carbBarrels = barrels
  cfg.carbPrimaryBarrels = primaryBarrels
  cfg.carbSecondaryBarrels = secondaryBarrels
  cfg.carbProgressive = progressive
  cfg.carbSecondaryType = progressive and (sizeCoef >= 1.08 and "mechanical" or "vacuum") or "synchronous"
  cfg.carbPrimaryBoreMM = bore
  cfg.carbSecondaryBoreMM = bore
  cfg.carbPrimaryVenturiMM = venturi
  cfg.carbSecondaryVenturiMM = venturi
  cfg.carbThrottleBoreMM = bore
  cfg.carbVenturiMM = venturi
  cfg.venturiDiameterRatio = bore / math.max(venturi, 0.1)
  cfg.mainJetMM = clamp(venturi / 24.5, 0.80, 2.30)
  cfg.carbRatedCFM = ratedM3s / 0.00047194745
  cfg.carbRatingPressureDropPa = ratingPressurePa
  cfg.carbBoosterSignalCoef = clamp(0.94 + (sizeCoef - 0.94) * 0.65, 0.90, 1.18)
  cfg.carbAccelPumpCoef = clamp(0.92 + (sizeCoef - 0.94) * 0.80, 0.88, 1.24)

  st.carbModel = string.upper(cfg.integrationMode) .. " native carburetor"
  st.carbModelId = 9000 + count * 10 + barrels
  st.carbStructuredDefinition = false
  st.carbNativeDefinition = true
  st.nativeCarbSynced = true
  st.carbSetupDetected = true
  return true
end

local function detectCarbSetupFromParts()
  local count = math.floor(clamp(cfg.carbCount, 1, 12) + 0.5)
  local barrels = math.floor(clamp(cfg.carbBarrels, 1, 4) + 0.5)
  local progressive = cfg.carbProgressive
  local detected = false
  local text = cfg.autoDetectCarbSetup and getActivePartsText() or ""
  local structured, structuredPartName = getActiveCarbDefinition()
  if not structured then
    structured = getActivePartTable("ultraRealismCarburetor")
  end
  if not structured then
    local bestScore, bestDef, bestName = -1, nil, nil
    for _, entry in ipairs(collectActivePartEntries()) do
      local partName = lowerText(entry.name)
      if partName:find("ultra_realism_carb", 1, true) or partName:find("ultra_realism_native_", 1, true) then
        local def = inferCarbDefinitionFromPartName(entry.name)
        if def then
          local score = 0
          if partName:find("carb_", 1, true) then score = score + 20 end
          if lowerText(entry.slot):find("carb", 1, true) then score = score + 12 end
          if score > bestScore then
            bestScore, bestDef, bestName = score, def, entry.name
          end
        end
      end
    end
    structured, structuredPartName = bestDef, bestName
  end

  if applyStructuredCarbDefinition(structured) then
    st.activeCarbPartName = structuredPartName or st.activeCarbPartName or ""
    st.partsDetectionSource = structuredPartName and 3 or 2
    st.activePartsTextAvailable = text ~= ""
    st.carbSetupScanned = true
    return
  end

  local nativeCarbEntry = usesNativePartSync() and getBestNativePartEntry("carburetor") or nil
  if nativeCarbEntry and applyNativeCarbDefinition(nativeCarbEntry.text) then
    st.activeCarbPartName = nativeCarbEntry.name or ""
    st.partsDetectionSource = 4
    st.activePartsTextAvailable = text ~= ""
    st.carbSetupScanned = true
    return
  end

  if text ~= "" then
    if text:find("1bblx6", 1, true) or text:find("6x1bbl", 1, true) or text:find("6x 1bbl", 1, true)
      or text:find("six 1-barrel", 1, true) or text:find("six 1 barrel", 1, true)
      or text:find("6 carburetor", 1, true) then
      count, barrels, progressive, detected = 6, 1, false, true
    elseif text:find("2bblx4", 1, true) or text:find("4x2bbl", 1, true) or text:find("4x 2bbl", 1, true)
      or text:find("4x 2-barrel", 1, true) or text:find("quad 2-barrel", 1, true)
      or text:find("quad 2 barrel", 1, true) then
      count, barrels, progressive, detected = 4, 2, false, true
    elseif text:find("sixpack", 1, true) or text:find("six-pack", 1, true) or text:find("six pack", 1, true)
      or text:find("3x2bbl", 1, true) or text:find("3x 2bbl", 1, true)
      or text:find("tripple-carb", 1, true) or text:find("triple-carb", 1, true) then
      count, barrels, progressive, detected = 3, 2, true, true
    elseif text:find("4bblx2", 1, true) or text:find("2x4bbl", 1, true) or text:find("2x 4bbl", 1, true)
      or text:find("2x4-barrel", 1, true) or text:find("twin 4-barrel", 1, true)
      or text:find("twin4bbl", 1, true) then
      count, barrels, progressive, detected = 2, 4, true, true
    elseif text:find("quadcarb", 1, true) or text:find("quad-carb", 1, true) or text:find("quad carb", 1, true) then
      count, barrels, progressive, detected = 4, 1, false, true
    elseif text:find("dualcarb", 1, true) or text:find("dual carb", 1, true) or text:find("twincarb", 1, true) or text:find("twin-carb", 1, true) or text:find("twin carb", 1, true) then
      count, barrels, progressive, detected = 2, 2, true, true
    elseif text:find("4bbl", 1, true) or text:find("4-barrel", 1, true) or text:find("4 barrel", 1, true) then
      count, barrels, progressive, detected = 1, 4, true, true
    elseif text:find("2bbl", 1, true) or text:find("2-barrel", 1, true) or text:find("2 barrel", 1, true) then
      count, barrels, progressive, detected = 1, 2, false, true
    elseif text:find("1bbl", 1, true) or text:find("1-barrel", 1, true) or text:find("1 barrel", 1, true) then
      count, barrels, progressive, detected = 1, 1, false, true
    end
  end

  cfg.carbCount = count
  cfg.carbPrimaryBarrels = progressive and math.min(barrels, 2) or barrels
  cfg.carbSecondaryBarrels = progressive and math.max(barrels - cfg.carbPrimaryBarrels, 0) or 0
  cfg.carbBarrels = barrels
  cfg.carbSecondaryType = progressive and "progressive" or "synchronous"
  cfg.carbProgressive = progressive
  st.carbSetupDetected = detected
  st.partsDetectionSource = detected and 5 or 1
  st.activePartsTextAvailable = text ~= ""
  st.carbSetupScanned = true
end

local function getCarbSecondaryOpening(throttle)
  if (cfg.carbSecondaryBarrels or 0) <= 0 then return 0 end

  local opening = clamp((throttle - cfg.secondaryThrottleStart) / math.max(1 - cfg.secondaryThrottleStart, 0.05), 0, 1)
  opening = opening * opening * (3 - 2 * opening)

  if cfg.carbSecondaryType == "vacuum" or cfg.carbSecondaryType == "airvalve" then
    local rpm = getElectricsValue("rpm", getElectricsValue("engineRPM", cfg.idleRPM))
    local rpmStart = cfg.idleRPM * 1.45
    local rpmEnd = math.max(cfg.vePeakRPM * 0.90, rpmStart + 600)
    local airflowDemand = clamp((rpm - rpmStart) / math.max(rpmEnd - rpmStart, 1), 0, 1)
    local response = cfg.carbSecondaryType == "airvalve" and 0.82 or 0.72
    opening = opening * lerp(response, 1.0, airflowDemand)
  end

  return opening
end

local function refreshEffectiveVenturiState(dt, rpm, throttle, tempC)
  local load = throttle * clamp(rpm / math.max(cfg.redlineRPM, 1), 0, 1)
  local iceCoef = 1 - clamp(st.carbIce or 0, 0, 1) * 0.22
  st.carbBodyTempC = lerp(st.carbBodyTempC or tempC, (st.intakeTempC or tempC) + 8 * load, clamp((dt or 0.016) * 0.4, 0, 1))
  local optimal = cfg.intakeOptimalTempC or 32
  local tempDev = math.abs((st.carbBodyTempC or tempC) - optimal)
  local spread = math.max(cfg.intakeTempSpreadC or 18, 4)
  local tempCoef = clamp(math.exp(-(tempDev * tempDev) / (2 * spread * spread)), 0.82, 1.0)
  local wearCoef = 1 - clamp(st.venturiWear or 0, 0, 0.15)
  st.effectiveVenturiCoef = clamp(wearCoef * iceCoef * tempCoef, 0.72, 1.0)
  local nominalVenturi = math.max(cfg.carbPrimaryVenturiMM or cfg.carbVenturiMM or 30, 1)
  st.effectiveVenturiMM = nominalVenturi * math.sqrt(st.effectiveVenturiCoef)
  st.breathingTempEfficiency = tempCoef
end

local function getActiveCarbGeometry(throttle)
  local count = math.max(cfg.carbCount, 1)
  local primaryBarrels = math.max(cfg.carbPrimaryBarrels or cfg.carbBarrels or 1, 1)
  local secondaryBarrels = math.max(cfg.carbSecondaryBarrels or 0, 0)
  local secondaryOpening = getCarbSecondaryOpening(throttle)
  local venturiScale = math.sqrt(math.max(st.effectiveVenturiCoef or 1, 0.72))
  local boreScale = lerp(1, venturiScale, 0.6)

  local primaryBoreD = math.max(cfg.carbPrimaryBoreMM or cfg.carbThrottleBoreMM, 1) / 1000.0 * boreScale
  local secondaryBoreD = math.max(cfg.carbSecondaryBoreMM or cfg.carbThrottleBoreMM, 1) / 1000.0 * boreScale
  local primaryVenturiD = math.max(cfg.carbPrimaryVenturiMM or cfg.carbVenturiMM, 1) / 1000.0 * venturiScale
  local secondaryVenturiD = math.max(cfg.carbSecondaryVenturiMM or cfg.carbVenturiMM, 1) / 1000.0 * venturiScale

  local primaryBoreArea = math.pi * primaryBoreD * primaryBoreD * 0.25 * primaryBarrels * count
  local secondaryBoreArea = math.pi * secondaryBoreD * secondaryBoreD * 0.25 * secondaryBarrels * count * secondaryOpening
  local primaryVenturiArea = math.pi * primaryVenturiD * primaryVenturiD * 0.25 * primaryBarrels * count
  local secondaryVenturiArea = math.pi * secondaryVenturiD * secondaryVenturiD * 0.25 * secondaryBarrels * count * secondaryOpening

  local activeBarrels = count * (primaryBarrels + secondaryBarrels * secondaryOpening)
  return primaryBoreArea + secondaryBoreArea,
    primaryVenturiArea + secondaryVenturiArea,
    activeBarrels,
    secondaryOpening
end

local function getActiveCarbBarrels(throttle)
  local _, _, activeBarrels = getActiveCarbGeometry(throttle)
  return activeBarrels
end

local function containsAny(text, needles)
  for _, needle in ipairs(needles) do
    if text:find(needle, 1, true) then return true end
  end
  return false
end

local function inferMaterialDensityKgM3(text, defaultDensity)
  if containsAny(text, {"magnesium", "mg alloy"}) then return 1740, "magnesium" end
  if containsAny(text, {"carbon", "composite", "fiberglass", "fibreglass", "plastic", "polymer"}) then return 1450, "composite" end
  if containsAny(text, {"aluminum", "aluminium", "alloy", "billet"}) then return 2700, "aluminum" end
  if containsAny(text, {"cast iron", "cast_iron", "iron"}) then return 7200, "cast iron" end
  if containsAny(text, {"stainless", "steel"}) then return 7850, "steel" end
  if containsAny(text, {"brass", "bronze", "copper"}) then return 8500, "brass" end
  return defaultDensity or 2700, "inferred aluminum"
end

local function inferSurfaceRoughnessFactor(text)
  local factor = 1.0
  if containsAny(text, {"cast", "rough", "stock"}) then factor = factor * 1.18 end
  if containsAny(text, {"ported", "polished", "smooth", "race", "velocity stack", "trumpet"}) then factor = factor * 0.82 end
  if containsAny(text, {"filter", "airbox"}) then factor = factor * 1.05 end
  return math.max(factor, 0.35)
end

local function inferCarbGeometry(text, dispL, totalBarrels)
  local perBarrelL = dispL / math.max(totalBarrels, 1)
  local bore = 26 + 9.0 * math.sqrt(math.max(perBarrelL, 0.05))
  local venturi = bore * clamp(0.68 + 0.06 * math.sqrt(math.max(perBarrelL, 0.05)), 0.62, 0.84)
  local jet = 0.82 + 0.24 * math.sqrt(math.max(perBarrelL, 0.05))
  local model = "displacement inferred"
  local modelId = 0

  if containsAny(text, {"32/36", "32-36", "dgv", "dgev", "2bbl", "2-barrel", "2 barrel"}) then
    bore = math.sqrt((32 * 32 + 36 * 36) * 0.5)
    venturi = math.sqrt((26 * 26 + 27 * 27) * 0.5)
    jet = 1.375
    model = "Weber 32/36 DGV equivalent"
    modelId = 3236
  end
  if containsAny(text, {
    "40 dcoe", "40dcoe", "dcoe40", "40_dcoe", "dcoe_40", "_dcoe_",
    "1bblx6", "6x1bbl", "six 1-barrel", "six_weber", "quadcarb", "quad-carb", "quad carb",
    "2bblx4", "4x2bbl", "4x 2bbl", "quad 2-barrel", "quad 2 barrel",
  }) then
    bore = 40
    venturi = 30
    if containsAny(text, {"_28", "28mm", "venturi 28", "venturi-28"}) then venturi = 28 end
    if containsAny(text, {"_30", "30mm", "venturi 30", "venturi-30"}) then venturi = 30 end
    if containsAny(text, {"_32", "32mm", "venturi 32", "venturi-32"}) then venturi = 32 end
    jet = clamp(venturi / 24.5, 0.95, 1.35)
    model = "Weber 40 DCOE equivalent"
    modelId = 40
  end
  if containsAny(text, {"45 dcoe", "45dcoe", "dcoe45", "sixpack", "six-pack", "six pack", "3x2bbl", "3x 2bbl", "4bbl", "4-barrel", "4 barrel", "twin4bbl", "2x4bbl", "race carb"}) then
    bore = 45
    venturi = 36
    jet = 1.45
    model = "Weber 45 DCOE equivalent"
    modelId = 45
  end
  if containsAny(text, {"48 dcoe", "48dcoe", "dcoe48", "ida", "48 ida", "race 4bbl"}) then
    bore = 48
    venturi = 40
    jet = 1.65
    model = "Weber 48/IDA equivalent"
    modelId = 48
  end

  return math.max(bore, 0.1), math.max(venturi, 0.1), math.max(jet, 0.01), model, modelId
end

inferCarbDefinitionFromPartName = function(partName)
  local name = lowerText(partName)
  if name == "" or not name:find("carb", 1, true) then return nil end
  if name:find("sync_carburetor", 1, true) or name:find("sync_carb", 1, true) then return nil end

  local count = 1
  if name:find("_six_", 1, true) or name:find("six_weber", 1, true) or name:find("sixpack", 1, true) then
    count = 6
  elseif name:find("_quad_", 1, true) or name:find("quad_weber", 1, true) or name:find("4x2", 1, true) then
    count = 4
  elseif name:find("_triple_", 1, true) or name:find("_tripple_", 1, true) then
    count = 3
  elseif name:find("_twin_", 1, true) or name:find("_dual_", 1, true) then
    count = 2
  end

  local barrels = 2
  local secondaryType = "synchronous"
  local progressive = false
  if name:find("1bbl", 1, true) or name:find("1_bbl", 1, true) or name:find("1904", 1, true) then
    barrels, secondaryType, progressive = 1, "synchronous", false
  elseif name:find("2300", 1, true) or name:find("2bbl", 1, true) or name:find("dgv", 1, true)
      or name:find("dgas", 1, true) or name:find("dgev", 1, true) or name:find("dcoe", 1, true)
      or name:find("idf", 1, true) then
    barrels, secondaryType, progressive = 2, "synchronous", false
  elseif name:find("4150", 1, true) or name:find("4160", 1, true) or name:find("4500", 1, true)
      or name:find("avs", 1, true) or name:find("afb", 1, true) or name:find("4bbl", 1, true)
      or name:find("annular", 1, true) or name:find("performer", 1, true) then
    barrels, secondaryType, progressive = 4, "mechanical", true
  end

  local bore, venturi, jet, _, modelId = inferCarbGeometry(name, cfg.displacementL or 5.0, count * barrels)
  local primaryBarrels = progressive and math.min(barrels, 2) or barrels
  local secondaryBarrels = progressive and math.max(barrels - primaryBarrels, 0) or 0
  local totalVenturiArea = math.pi * (venturi / 1000) * (venturi / 1000) * 0.25 * barrels * count
  local ratingPressurePa = barrels <= 2 and 10158 or 5079
  local ratedM3s = 0.82 * totalVenturiArea
    * math.sqrt(2 * ratingPressurePa / math.max(cfg.referenceAirDensity, 0.1))

  return {
    modelId = modelId,
    count = count,
    primaryBarrels = primaryBarrels,
    secondaryBarrels = secondaryBarrels,
    primaryBoreMM = bore,
    secondaryBoreMM = bore,
    primaryVenturiMM = venturi,
    secondaryVenturiMM = venturi,
    mainJetMM = jet,
    ratedCFM = ratedM3s / 0.00047194745,
    ratingPressureDropPa = ratingPressurePa,
    secondaryType = secondaryType,
    dischargeCoef = 0.82,
    boosterSignalCoef = 1.0,
    accelPumpCoef = 1.0,
  }
end

local function readEnvironmentScalar(names, default)
  for _, name in ipairs(names) do
    local v = getElectricsValue(name, nil)
    if v ~= nil then return clamp(v, 0, 1) end
  end
  if obj then
    for _, name in ipairs(names) do
      local getter = obj["get" .. name:sub(1, 1):upper() .. name:sub(2)]
      if getter then
        local ok, val = pcall(function() return getter(obj) end)
        if ok and tonumber(val) then return clamp(val, 0, 1) end
      end
    end
  end
  return default or 0
end

local function updateWeatherState(dt, speed, tempC, pressurePa, baseHumidity)
  local rain = readEnvironmentScalar({"rain", "rainIntensity", "precipitation", "wetness"}, 0)
  local speedMS = math.abs(speed or 0)
  local speedAerosol = clamp(speedMS / 55.0, 0, 1) * rain
  local targetHumidity = clamp(baseHumidity + rain * 0.22 + speedAerosol * 0.10, 0, 1)
  local response = clamp(dt * (0.10 + speedMS * 0.006), 0, 1)
  st.rainIntensity = lerp(st.rainIntensity or rain, rain, response)
  st.dynamicHumidity = lerp(st.dynamicHumidity or targetHumidity, targetHumidity, response)
  if st.airFilterActive then
    local exposure = rain * (0.10 + clamp(speedMS / 45.0, 0, 1) * 0.32)
    local shedding = clamp(speedMS / math.max(st.airFilterWaterSheddingSpeedMS or 18, 1), 0, 2)
    local drying = (1 - rain) * (0.025 + 0.040 * shedding)
    st.airFilterWetness = clamp((st.airFilterWetness or 0) + dt * (exposure - drying), 0, 1)
  else
    st.airFilterWetness = math.max((st.airFilterWetness or 0) - dt * 0.12, 0)
  end

  local dryAirDensity = pressurePa / (287.05 * math.max(tempC + 273.15, 1))
  st.ramAirPressurePa = 0.5 * dryAirDensity * speedMS * speedMS * 0.32 * (1 - st.rainIntensity * 0.08)
  return st.dynamicHumidity, st.rainIntensity, st.ramAirPressurePa
end

local function inferCamStage(text)
  text = text or ""
  local stageNumber = tonumber(text:match("stage%s*([1-4])"))

  if textHasAny(text, {"drag race camshaft", "drag race cam", "drag_cam"}) then
    return 3.6 + 0.20 * math.max((stageNumber or 1) - 1, 0)
  end
  if textHasAny(text, {"race camshaft", "race cam", "race_cam", "race valvetrain"}) then
    return 3.0 + 0.25 * math.max((stageNumber or 1) - 1, 0)
  end
  if textHasAny(text, {"sport camshaft", "sport cam", "sport_cam"}) then
    return clamp(stageNumber or 1, 1, 3)
  end
  if textHasAny(text, {"performance camshaft", "performance cam", "performance_cam"}) then
    return clamp(stageNumber or 2.5, 1, 3.5)
  end
  if stageNumber then return clamp(stageNumber, 1, 4) end
  if textHasAny(text, {"towing", "low rpm camshaft", "low-rpm camshaft"}) then return -0.5 end
  return 0
end

local function analyzeEngineParts()
  local text = getActivePartsText()
  local diesel = cfg.fuelingMode == "diesel"
  local forced = hasForcedInduction()

  local compressionRatio = diesel and 17.5 or (forced and 9.0 or 9.5)
  if containsAny(text, {"flathead", "side-valve", "side valve", "l-head", "lhead"}) then compressionRatio = diesel and 16.5 or 7.2 end
  if containsAny(text, {"low compression", "low_compression", "lowcomp"}) then compressionRatio = compressionRatio - 1.0 end
  if containsAny(text, {"high compression", "high_compression", "highcomp"}) then compressionRatio = compressionRatio + 1.6 end
  if containsAny(text, {"race piston", "race_piston", "race bottom", "race_bottom", "race internals"}) then compressionRatio = compressionRatio + 0.8 end
  local autoCompressionRatio = compressionRatio

  local ringSealCoef = 1.0
  local ringFrictionCoef = 1.0
  local ringDurabilityCoef = 1.0
  if containsAny(text, {"moly piston rings", "moly_piston_rings", "file-fit moly", "file_fit_moly"}) then
    ringSealCoef, ringFrictionCoef, ringDurabilityCoef = 1.02, 0.98, 1.12
  end
  if containsAny(text, {"low-tension drag piston rings", "low tension drag piston rings", "low_tension_drag"}) then
    ringSealCoef, ringFrictionCoef, ringDurabilityCoef = 0.99, 0.94, 0.94
  end
  if containsAny(text, {"worn piston rings", "worn_piston_rings"}) then
    ringSealCoef, ringFrictionCoef, ringDurabilityCoef = 0.78, 1.08, 0.55
  end
  if containsAny(text, {"broken piston rings", "broken_piston_rings"}) then
    ringSealCoef, ringFrictionCoef, ringDurabilityCoef = 0.42, 1.30, 0.20
  end

  local bearingFrictionCoef = 1.0
  local bearingOilDemand = 1.0
  local bearingDurabilityCoef = 1.0
  if containsAny(text, {"tri-metal rod bearings", "tri metal rod bearings", "trimetal rod bearings"}) then
    bearingFrictionCoef, bearingOilDemand, bearingDurabilityCoef = 0.98, 1.02, 1.12
  end
  if containsAny(text, {"coated race rod bearings", "coated_race_rod_bearings"}) then
    bearingFrictionCoef, bearingOilDemand, bearingDurabilityCoef = 0.94, 1.06, 1.35
  end
  if containsAny(text, {"high-clearance drag rod bearings", "high clearance drag rod bearings", "high_clearance_drag"}) then
    bearingFrictionCoef, bearingOilDemand, bearingDurabilityCoef = 0.93, 1.24, 1.22
  end
  if containsAny(text, {"worn rod bearings", "worn_rod_bearings"}) then
    bearingFrictionCoef, bearingOilDemand, bearingDurabilityCoef = 1.36, 1.55, 0.42
  end

  local oilCoolingCoef = 1.0
  local oilGControlCoef = 1.0
  local oilPressureReserveCoef = 1.0
  if containsAny(text, {"baffled wet sump", "baffled_wet_sump", "performance oil pan", "race oil pan"}) then
    oilGControlCoef = 1.35
  end
  if containsAny(text, {"high volume oil pump", "high_volume_oil_pump"}) then
    oilPressureReserveCoef, oilGControlCoef = 1.22, 1.45
  end
  if containsAny(text, {"performance oil cooler", "performance_oil_cooler"}) then
    oilCoolingCoef = 1.35
  end
  if containsAny(text, {"dry sump oil system", "dry_sump_oil_system", "dry sump oil pan", "dry_sump_oil_pan"}) then
    oilCoolingCoef, oilGControlCoef, oilPressureReserveCoef = 1.75, 2.65, 1.55
  end
  if containsAny(text, {"worn oil pump", "worn_oil_pump"}) then
    oilCoolingCoef, oilGControlCoef, oilPressureReserveCoef = 0.62, 0.55, 0.48
  end

  local headGasketStrengthCoef = 1.0
  if containsAny(text, {"mls head gasket", "mls_head_gasket"}) then headGasketStrengthCoef = 1.28 end
  if containsAny(text, {"copper head gasket", "copper_head_gasket"}) then headGasketStrengthCoef = 1.48 end
  if containsAny(text, {"fire-ring head gasket", "fire ring head gasket", "fire_ring_head_gasket"}) then headGasketStrengthCoef = 1.85 end
  if containsAny(text, {"weak head gasket", "weak_head_gasket"}) then headGasketStrengthCoef = 0.48 end

  local distributorQuality = 0.72
  if containsAny(text, {"high performance distributor", "high_performance_distributor", "electronic ignition", "ecu", "efi", "sefi", "mfi"}) then
    distributorQuality = 1.0
  elseif containsAny(text, {"performance distributor", "performance_distributor"}) then
    distributorQuality = 0.88
  elseif containsAny(text, {"stock distributor", "stock_distributor"}) then
    distributorQuality = 0.72
  end
  if containsAny(text, {"programmable cdi ignition", "programmable_cdi_ignition"}) then
    distributorQuality = 1.05
  end
  local distributorTimingOffsetDeg = (1 - distributorQuality) * -2.5
  if containsAny(text, {"worn distributor", "worn_distributor", "points ignition", "points_ignition"}) then
    distributorTimingOffsetDeg = distributorTimingOffsetDeg - 1.8
    distributorQuality = math.min(distributorQuality, 0.62)
  end

  local valveCount = tonumber(text:match("(%d+)[%s_%-]*valve")) or 2
  valveCount = clamp(valveCount, 2, 5)
  local valveFlowCoef = 0.90 + (valveCount - 2) * 0.055
  if containsAny(text, {"flathead", "side-valve", "side valve", "l-head", "lhead"}) then valveFlowCoef = valveFlowCoef * 0.82 end
  if containsAny(text, {"ported head", "ported_head", "ported iron cylinder heads", "race head", "race_head", "performance head"}) then valveFlowCoef = valveFlowCoef * 1.08 end
  if containsAny(text, {"aluminum performance heads", "race aluminum cylinder heads", "4-valve race cylinder heads", "4 valve race cylinder heads"}) then valveFlowCoef = valveFlowCoef * 1.14 end
  if containsAny(text, {"roller rockers", "roller_rockers"}) then valveFlowCoef = valveFlowCoef * 1.03 end
  if containsAny(text, {"titanium valves", "titanium_valves"}) then valveFlowCoef = valveFlowCoef * 1.05 end

  local camOverrideText = getSelectedUltraOverrideText("ultra_realism_camshaft")
  local nativeCamText = usesNativePartSync() and getBestNativePartText("camshaft") or nil
  local camOwnedByNative = ureOwnership
    and ureOwnership.shouldSkipHeuristic
    and ureOwnership.shouldSkipHeuristic("ultra_realism_camshaft", usesNativePartSync())
  local camStage = camOwnedByNative and 0 or inferCamStage(camOverrideText or nativeCamText or text)
  st.nativeCamSynced = camOwnedByNative or (camOverrideText == nil and nativeCamText ~= nil)

  local intakeValvesPerCylinder = math.max(math.floor(valveCount * 0.5), 1)
  local perCylinderL = cfg.displacementL / math.max(cfg.injectorCount, 1)
  local valveDiameterMM = clamp(24 + 18 * math.sqrt(math.max(perCylinderL, 0.1)) / math.sqrt(intakeValvesPerCylinder), 24, 54)
  local valveLiftMM = 8.0 + camStage * 0.85
  local valveCurtainAreaM2 = math.pi * (valveDiameterMM / 1000) * (valveLiftMM / 1000)
    * intakeValvesPerCylinder * math.max(cfg.injectorCount * 0.5, 1)

  local pistonMaterial = "cast"
  local pistonExpansionCoef = 1.0
  local pistonHotToleranceC = 205
  if containsAny(text, {"coated billet pistons", "billet piston", "billet_piston", "billet short block"}) then
    pistonMaterial, pistonExpansionCoef, pistonHotToleranceC = "coated billet", 1.08, 270
  elseif containsAny(text, {"forged piston", "forged_piston", "forged internals", "forged_internals", "forged short block"}) then
    pistonMaterial, pistonExpansionCoef, pistonHotToleranceC = "forged", 1.32, 245
  elseif containsAny(text, {"hypereutectic", "hyper piston", "hyper_piston"}) then
    pistonMaterial, pistonExpansionCoef, pistonHotToleranceC = "hypereutectic", 0.76, 220
  end
  local pistonDensityKgM3 = pistonMaterial == "coated billet" and 2810 or (pistonMaterial == "forged" and 2810 or (pistonMaterial == "hypereutectic" and 2680 or 2700))

  local cylinders = math.max(cfg.injectorCount, 1)
  local runnerDiameterMM = clamp(24 + 22 * math.sqrt(math.max(perCylinderL, 0.1)), 26, 58)
  local runnerLengthM = containsAny(text, {"flathead", "side-valve", "side valve"}) and 0.38 or 0.28
  local intakeHeatIsolationCoef = 1.0
  if containsAny(text, {"dual-plane street intake", "dual plane street intake"}) then
    runnerLengthM = 0.34
    runnerDiameterMM = runnerDiameterMM * 0.98
  end
  if containsAny(text, {"single-plane performance intake", "single plane performance intake"}) then
    runnerLengthM = 0.22
    runnerDiameterMM = runnerDiameterMM * 1.08
  end
  if containsAny(text, {"cross-ram long runner intake", "cross ram long runner intake"}) then
    runnerLengthM = 0.44
    runnerDiameterMM = runnerDiameterMM * 1.04
  end
  if containsAny(text, {"tunnel-ram high rpm intake", "tunnel ram high rpm intake"}) then
    runnerLengthM = 0.16
    runnerDiameterMM = runnerDiameterMM * 1.16
  end
  if containsAny(text, {"individual runner intake", "individual_runner_intake"}) then
    runnerLengthM = 0.13
    runnerDiameterMM = runnerDiameterMM * 1.12
  end
  if containsAny(text, {"long runner", "long_runner", "long intake", "long_intake"}) then runnerLengthM = 0.42 end
  if containsAny(text, {"short runner", "short_runner", "tunnel ram", "tunnel_ram", "race manifold", "race_manifold", "velocity stack"}) then runnerLengthM = 0.16 end
  if containsAny(text, {"performance manifold", "performance_manifold", "sport manifold", "sport_manifold"}) then
    runnerDiameterMM = runnerDiameterMM * 1.08
    runnerLengthM = runnerLengthM * 0.88
  end
  if containsAny(text, {"25 mm four-hole spacer", "25 mm four hole spacer"}) then runnerLengthM = runnerLengthM + 0.025 end
  if containsAny(text, {"25 mm open plenum spacer"}) then runnerLengthM = runnerLengthM + 0.018 end
  if containsAny(text, {"50 mm open plenum spacer"}) then runnerLengthM = runnerLengthM + 0.035 end
  if containsAny(text, {"tapered four-hole spacer", "tapered four hole spacer"}) then
    runnerLengthM = runnerLengthM + 0.020
    runnerDiameterMM = runnerDiameterMM * 1.02
  end
  if containsAny(text, {"phenolic heat-isolating spacer", "phenolic heat isolating spacer"}) then
    runnerLengthM = runnerLengthM + 0.025
    intakeHeatIsolationCoef = 0.72
  end

  local throttleBodyDiameterMM = clamp(34 + cfg.displacementL * 5.5, 38, 105)
  if forced then throttleBodyDiameterMM = throttleBodyDiameterMM * 1.08 end
  local throttleBodyPart = getActivePartTable("ultraRealismThrottleBody")
  if type(throttleBodyPart) == "table" then
    throttleBodyDiameterMM = clamp(safeNumber(throttleBodyPart.diameterMM, throttleBodyDiameterMM), 28, 120)
    cfg.throttleBodyCount = math.floor(clamp(safeNumber(throttleBodyPart.count, cfg.throttleBodyCount), 1, 8) + 0.5)
    cfg.throttleBodyDischargeCoef = clamp(safeNumber(throttleBodyPart.dischargeCoef, cfg.throttleBodyDischargeCoef), 0.45, 1.05)
  end
  local dieselInjection = getActivePartTable("ultraRealismDieselInjection")
  if cfg.fuelingMode == "diesel" and type(dieselInjection) == "table" then
    local nozzleFlow = safeNumber(dieselInjection.nozzleFlowMM3PerStroke, 0)
    if nozzleFlow > 0 then
      cfg.injectorCCMin = math.max(cfg.injectorCCMin, nozzleFlow * 0.06)
    end
    cfg.powerAFR = clamp(safeNumber(dieselInjection.targetPowerAFR, cfg.powerAFR), 14, 24)
  end
  local intakeMaterialDensityKgM3, intakeMaterial = inferMaterialDensityKgM3(text, 2700)
  local tunnel = getActivePartTable("ultraRealismTunnelVenturi")
  local tunnelActive = type(tunnel) == "table"
  local tunnelLengthM = tunnelActive and clamp(safeNumber(tunnel.lengthM, 0.12), 0.02, 0.50) or 0
  local tunnelInletDiameterMM = tunnelActive and math.max(safeNumber(tunnel.inletEquivalentDiameterMM, 50), 5) or 0
  local tunnelOutletDiameterMM = tunnelActive and math.max(safeNumber(tunnel.outletEquivalentDiameterMM, 45), 5) or 0
  local tunnelThroatDiameterMM = tunnelActive and math.max(safeNumber(tunnel.throatEquivalentDiameterMM, 40), 5) or 0
  local tunnelSurfaceRoughnessM = tunnelActive and clamp(safeNumber(tunnel.surfaceRoughnessM, 0.000015), 0.000001, 0.002) or 0
  local tunnelDischargeCoefficient = tunnelActive and clamp(safeNumber(tunnel.dischargeCoefficient, 0.94), 0.45, 1.10) or 1
  local tunnelLocalLossCoefficient = tunnelActive and clamp(safeNumber(tunnel.localLossCoefficient, 0.18), 0.01, 4.0) or 0
  local airFilter = getActivePartTable("ultraRealismIntakeFilter")
  local airFilterActive = type(airFilter) == "table"
  local airFilterFlowAreaM2 = airFilterActive and math.max(safeNumber(airFilter.flowAreaM2, 0.01), 0.0001) or 0
  local airFilterMediaAreaM2 = airFilterActive and math.max(safeNumber(airFilter.mediaAreaM2, 0.10), airFilterFlowAreaM2) or 0
  local airFilterDischargeCoefficient = airFilterActive and clamp(safeNumber(airFilter.dischargeCoefficient, 0.97), 0.45, 1.10) or 1
  local airFilterDryLossCoefficient = airFilterActive and clamp(safeNumber(airFilter.dryLossCoefficient, 0.30), 0.01, 4.0) or 0
  local airFilterWetSensitivity = airFilterActive and clamp(safeNumber(airFilter.wetSensitivity, 2.25), 0, 8.0) or 0
  local airFilterWaterSheddingSpeedMS = airFilterActive and clamp(safeNumber(airFilter.waterSheddingSpeedMS, 18.0), 1, 80) or 18

  st.activePartsText = text
  st.autoCompressionRatio = clamp(autoCompressionRatio, diesel and 12 or 5.5, diesel and 28 or 16)
  st.compressionRatio = clamp(compressionRatio, diesel and 12 or 5.5, diesel and 28 or 16)
  st.distributorQuality = distributorQuality
  st.distributorTimingOffsetDeg = distributorTimingOffsetDeg
  st.valveCount = valveCount
  st.valveFlowCoef = valveFlowCoef
  st.intakeValvesPerCylinder = intakeValvesPerCylinder
  st.valveDiameterMM = valveDiameterMM
  st.valveLiftMM = valveLiftMM
  st.valveCurtainAreaM2 = valveCurtainAreaM2
  st.camStage = camStage
  st.pistonMaterial = pistonMaterial
  st.pistonMaterialDensityKgM3 = pistonDensityKgM3
  st.pistonExpansionCoef = pistonExpansionCoef
  st.pistonHotToleranceC = pistonHotToleranceC
  st.ringSealCoef = ringSealCoef
  st.ringFrictionCoef = ringFrictionCoef
  st.ringDurabilityCoef = ringDurabilityCoef
  st.bearingFrictionCoef = bearingFrictionCoef
  st.bearingOilDemand = bearingOilDemand
  st.bearingDurabilityCoef = bearingDurabilityCoef
  st.oilCoolingCoef = oilCoolingCoef
  st.oilGControlCoef = oilGControlCoef
  st.oilPressureReserveCoef = oilPressureReserveCoef
  st.headGasketStrengthCoef = headGasketStrengthCoef
  st.runnerDiameterMM = runnerDiameterMM
  st.runnerLengthM = runnerLengthM
  st.intakeHeatIsolationCoef = intakeHeatIsolationCoef
  st.intakeMaterial = intakeMaterial
  st.intakeMaterialDensityKgM3 = intakeMaterialDensityKgM3
  st.runnerRoughnessFactor = inferSurfaceRoughnessFactor(text)
  st.throttleBodyDiameterMM = throttleBodyDiameterMM
  st.tunnelVenturiActive = tunnelActive
  st.tunnelVenturiLengthM = tunnelLengthM
  st.tunnelVenturiInletDiameterMM = tunnelInletDiameterMM
  st.tunnelVenturiOutletDiameterMM = tunnelOutletDiameterMM
  st.tunnelVenturiThroatDiameterMM = tunnelThroatDiameterMM
  st.tunnelVenturiSurfaceRoughnessM = tunnelSurfaceRoughnessM
  st.tunnelVenturiDischargeCoefficient = tunnelDischargeCoefficient
  st.tunnelVenturiLocalLossCoefficient = tunnelLocalLossCoefficient
  st.airFilterActive = airFilterActive
  st.airFilterFlowAreaM2 = airFilterFlowAreaM2
  st.airFilterMediaAreaM2 = airFilterMediaAreaM2
  st.airFilterDischargeCoefficient = airFilterDischargeCoefficient
  st.airFilterDryLossCoefficient = airFilterDryLossCoefficient
  st.airFilterWetSensitivity = airFilterWetSensitivity
  st.airFilterWaterSheddingSpeedMS = airFilterWaterSheddingSpeedMS
  st.enginePartsAnalyzed = true
end

local function estimateEngineDisplacementL()
  if not engine then return cfg.displacementL end

  local candidates = {
    engine.displacementL,
    engine.engineDisplacementL,
    engine.displacement,
    engine.displacementCC,
    engine.engineDisplacementCC
  }

  for _, value in ipairs(candidates) do
    local disp = tonumber(value)
    if disp and disp > 0 then
      if disp > 100 then disp = disp / 1000.0 end
      if disp >= 0.2 and disp <= 30 then
        return clamp(disp, cfg.autoMinDisplacementL, cfg.autoMaxDisplacementL)
      end
    end
  end

  local maxTorque = getEngineMaxTorque()
  if maxTorque and maxTorque > 10 and maxTorque < 10000 then
    local tqPerL = cfg.autoTorquePerLiterNm
    if tqPerL <= 0 then
      if cfg.fuelingMode == "diesel" then
        tqPerL = hasForcedInduction() and 185 or 135
      elseif hasForcedInduction() then
        tqPerL = 140
      else
        tqPerL = 92
      end
    end
    return clamp(maxTorque / math.max(tqPerL, 1), cfg.autoMinDisplacementL, cfg.autoMaxDisplacementL)
  end

  return clamp(cfg.displacementL, cfg.autoMinDisplacementL, cfg.autoMaxDisplacementL)
end

local function recalibrateCarbFuelFromEngine()
  if cfg.fuelingMode ~= "carb" or not engine then return end

  local cylinders = getEngineCylinderCount()
  local dispL = cfg.displacementL
  local perCylinderL = dispL / math.max(cylinders, 1)
  local totalBarrels = math.max(cfg.carbCount * cfg.carbBarrels, 1)
  local partsText = st.activePartsText or getActivePartsText()
  local fallbackJet = cfg.mainJetMM
  local carbModel = st.carbModel or "structured carburetor"
  local carbModelId = st.carbModelId or 0
  if not st.carbStructuredDefinition and not st.carbNativeDefinition then
    local bore, venturi
    bore, venturi, fallbackJet, carbModel, carbModelId = inferCarbGeometry(partsText, dispL, totalBarrels)
    cfg.carbThrottleBoreMM = math.max(finiteNonNegative(bore, 38), 0.1)
    cfg.carbVenturiMM = math.max(finiteNonNegative(venturi, cfg.carbThrottleBoreMM * 0.74), 0.1)
    cfg.carbPrimaryBoreMM = cfg.carbThrottleBoreMM
    cfg.carbSecondaryBoreMM = cfg.carbThrottleBoreMM
    cfg.carbPrimaryVenturiMM = cfg.carbVenturiMM
    cfg.carbSecondaryVenturiMM = cfg.carbVenturiMM
    cfg.venturiDiameterRatio = cfg.carbThrottleBoreMM / math.max(cfg.carbVenturiMM, 0.1)
  end

  local designRPM = math.max(cfg.vePeakRPM, cfg.idleRPM + 500)
  local designVE = cfg.veBase + cfg.vePeakGain
  local designAirM3s = (dispL / 1000.0) * (designRPM / 60.0) * 0.5 * designVE
  local fullBoreArea, designThroatArea = getActiveCarbGeometry(1)
  local designVelocity = designAirM3s / math.max(designThroatArea, 1e-7)
  local designVenturiDP = 0.5 * cfg.referenceAirDensity * designVelocity * designVelocity
  local designSignal = clamp((designVenturiDP * (cfg.carbBoosterSignalCoef or 1) - cfg.carbMinSignalPa) / math.max(cfg.carbFullSignalPa - cfg.carbMinSignalPa, 1), 0.08, 1)
  local desiredFuelKgS = designAirM3s * cfg.referenceAirDensity / math.max(cfg.powerAFR * cfg.powerValveFuelMult, 0.1)
  local jetFlowDenominator = cfg.jetDischargeCoef * math.sqrt(math.max(2 * cfg.fuelDensityKgM3 * designVenturiDP, 0)) * designSignal
  local perJetArea = desiredFuelKgS / math.max(jetFlowDenominator * totalBarrels, 1e-9)
  local calculatedJet = math.sqrt(math.max(4 * perJetArea / math.pi, 0)) * 1000.0
  if calculatedJet ~= calculatedJet or calculatedJet <= 0 then calculatedJet = fallbackJet end
  if not st.carbStructuredDefinition and not st.carbNativeDefinition then
    cfg.mainJetMM = calculatedJet
  end
  cfg.mainJetMM = math.max(finiteNonNegative(cfg.mainJetMM, fallbackJet), 0.01)
  local selectedJetD = cfg.mainJetMM / 1000.0
  local selectedJetArea = math.pi * selectedJetD * selectedJetD * 0.25 * totalBarrels
  local uncalibratedDesignFuel = cfg.jetDischargeCoef * selectedJetArea
    * math.sqrt(math.max(2 * cfg.fuelDensityKgM3 * designVenturiDP, 0)) * designSignal
  cfg.carbFuelCalibrationCoef = clamp(desiredFuelKgS / math.max(uncalibratedDesignFuel, 1e-9), 0.20, 12.0)
  st.carbTotalDiameterMM = math.sqrt(math.max(4 * fullBoreArea / math.pi, 0)) * 1000
  st.venturiTotalDiameterMM = math.sqrt(math.max(4 * designThroatArea / math.pi, 0)) * 1000
  st.carbModel = carbModel
  st.carbModelId = carbModelId

  local fuelDelivery = getActivePartTable("ultraRealismFuelDelivery")
  if fuelDelivery and safeNumber(fuelDelivery.capacityLPH, 0) > 0 then
    cfg.fuelPumpKgS = fuelDelivery.capacityLPH / 3600.0 / 1000.0 * cfg.fuelDensityKgM3
    st.fuelDeliveryCapacityLPH = fuelDelivery.capacityLPH
  else
    cfg.fuelPumpKgS = math.max(cfg.fuelPumpKgS, desiredFuelKgS * 1.6)
    st.fuelDeliveryCapacityLPH = cfg.fuelPumpKgS / cfg.fuelDensityKgM3 * 1000 * 3600
  end
  cfg.idleFuelKgS = math.max(cfg.idleFuelKgS, dispL * 0.00012)
  cfg.accelPumpKgS = math.max(cfg.accelPumpKgS, dispL * 0.00100) * (cfg.carbAccelPumpCoef or 1)
  cfg.powerAFR = clamp(cfg.powerAFR, 12.0, 13.2)
end

local function autoTuneFromEngine()
  if not cfg.autoDetectEngine or not engine or st.autoDetected then return end

  cfg.idleRPM = safeNumber(engine.idleRPM, cfg.idleRPM)
  cfg.redlineRPM = safeNumber(engine.maxRPM or engine.maxAvailableRPM, cfg.redlineRPM)
  cfg.redlineRPM = clamp(cfg.redlineRPM, math.max(cfg.idleRPM + 500, 1200), 12000)

  local energyType = lowerText(engine.requiredEnergyType)
  if cfg.autoFuelingMode then
    local partsText = getActivePartsText()
    local nativeCarbDetected = usesNativePartSync()
      and getBestNativePartText("carburetor") ~= nil
    local carbDetected = getActivePartTable("ultraRealismCarburetor") ~= nil
      or nativeCarbDetected
      or (not usesNativePartSync()
        and containsAny(partsText, {"carb", "bbl", "sixpack", "six-pack", "venturi"}))
    local injectionDetected = containsAny(partsText, {"efi", "sefi", "mfi", "injection", "injector", "ecoboost", "coyote", "voodoo"})
    if energyType:find("diesel", 1, true) then
      cfg.fuelingMode = "diesel"
    elseif injectionDetected then
      cfg.fuelingMode = "injection"
    elseif carbDetected then
      cfg.fuelingMode = "carb"
    elseif cfg.preferCarburetor then
      cfg.fuelingMode = "carb"
    else
      cfg.fuelingMode = "injection"
    end
  end

  if cfg.fuelingMode == "diesel" then
    if cfg.fuelDensityKgM3 < 780 then cfg.fuelDensityKgM3 = 830 end
    if cfg.powerAFR < 15 then cfg.powerAFR = 18.2 end
    cfg.stoichAFR = 14.5
    cfg.fuelOctaneRON = 0
    cfg.referenceOctaneRON = 0
  end

  local cylinders = getEngineCylinderCount()
  local dispL = estimateEngineDisplacementL()
  cfg.displacementL = dispL
  cfg.injectorCount = cylinders
  if cfg.fuelingMode == "carb" then detectCarbSetupFromParts() end
  analyzeEngineParts()

  if cfg.autoTuneVECurve then
    local camShift = clamp(st.camStage or 0, -0.5, 4.0) * 0.035
    local peakRatio = cfg.fuelingMode == "diesel" and 0.52 or (cfg.fuelingMode == "carb" and 0.64 or 0.74)
    peakRatio = peakRatio + camShift
    cfg.vePeakRPM = cfg.redlineRPM * peakRatio
    cfg.veSpreadRPM = math.max((cfg.redlineRPM - cfg.idleRPM) * 0.34, 900)
    cfg.vePeakGain = cfg.baseVEPeakGain * (st.valveFlowCoef or 1)
  end
  cfg.vePeakRPM = clamp(cfg.vePeakRPM <= 0 and (cfg.redlineRPM * 0.72) or cfg.vePeakRPM, cfg.idleRPM + 200, cfg.redlineRPM)
  cfg.veSpreadRPM = clamp(cfg.veSpreadRPM, 700, math.max(cfg.redlineRPM * 0.65, 1200))

  local perCylinderL = dispL / math.max(cylinders, 1)
  if cfg.fuelingMode == "carb" then
    recalibrateCarbFuelFromEngine()
  elseif cfg.fuelingMode == "diesel" then
    cfg.injectorCCMin = math.max(cfg.injectorCCMin, 210 + perCylinderL * 210 + (hasForcedInduction() and 120 or 0))
    cfg.powerAFR = clamp(cfg.powerAFR, 16.5, 22.5)
  else
    cfg.injectorCCMin = math.max(cfg.injectorCCMin, 190 + perCylinderL * 260 + (hasForcedInduction() and 130 or 0))
    cfg.powerAFR = clamp(cfg.powerAFR, 11.6, 13.4)
  end

  cfg.frictionPenaltyNm = math.max(cfg.frictionPenaltyNm, 16 + dispL * 6.5)
  st.autoDetected = true
  st.autoDisplacementL = dispL
  st.autoCylinders = cylinders
  st.autoMaxTorqueNm = getEngineMaxTorque() or 0

  if cfg.debugLog then
    log("I", "UltraRealismEngine", string.format("automatic detection: %.2f L, %d cyl, %s, idle %.0f rpm, redline %.0f rpm", dispL, cylinders, cfg.fuelingMode, cfg.idleRPM, cfg.redlineRPM))
  end
end

local function getBeamNGEnvironment(defaultTempC, defaultPressurePa)
  local tempC = defaultTempC
  local pressurePa = defaultPressurePa

  if obj and obj.getEnvTemperature then
    local ok, tempK = pcall(function() return obj:getEnvTemperature() end)
    if ok and type(tempK) == "number" and tempK > 100 and tempK < 400 then
      tempC = tempK - 273.15
    end
  end
  if obj and obj.getEnvPressure then
    local ok, p = pcall(function() return obj:getEnvPressure() end)
    if ok and type(p) == "number" and p > 45000 and p < 125000 then
      pressurePa = p
    end
  end

  return tempC, pressurePa
end

local function detectClimateFromPreset(preset)
  local p = tostring(preset or "game_environment")
  local tempC, pressurePa, humidity

  if p == "cold_mountain" then
    tempC, pressurePa, humidity = -8, 79000, 0.35
  elseif p == "hot_desert" then
    tempC, pressurePa, humidity = 43, 94000, 0.12
  elseif p == "rain_forest" then
    tempC, pressurePa, humidity = 23, 100700, 0.95
  elseif p == "winter_humid" then
    tempC, pressurePa, humidity = 1, 99000, 0.85
  elseif p == "high_altitude" then
    tempC, pressurePa, humidity = 12, 72000, 0.30
  elseif p == "dyno_standard" then
    tempC, pressurePa, humidity = 25, 101325, 0.45
  else
    tempC, pressurePa, humidity = cfg.airTempC, cfg.pressurePa, cfg.humidity
  end

  if cfg.useBeamNGEnvironment and (p == "game_environment" or p == "auto") then
    tempC, pressurePa = getBeamNGEnvironment(tempC, pressurePa)
  end

  return tempC, pressurePa, clamp(humidity, 0, 1)
end

local function calcAirDensity(tempC, pressurePa, humidity)
  -- Approximate moist air density using Tetens saturation vapor pressure.
  local T = tempC + 273.15
  local h = clamp(humidity, 0, 1)
  local es = 610.94 * math.exp((17.625 * tempC) / (tempC + 243.04))
  local pv = clamp(h * es, 0, pressurePa * 0.95)
  local pd = pressurePa - pv
  local Rd = 287.05
  local Rv = 461.495
  return (pd / (Rd * T)) + (pv / (Rv * T))
end

local function calcBaseVE(rpm, throttle)
  local peak = cfg.vePeakRPM
  local spread = cfg.veSpreadRPM
  local ve = cfg.veBase + cfg.vePeakGain * math.exp(-((rpm - peak) * (rpm - peak)) / (2 * spread * spread))
  return finiteNonNegative(ve * lerp(cfg.closedThrottleVECoef, 1.0, throttle), 0)
end

local function calcBreathingTempEfficiency(intakeTempC)
  local optimal = cfg.intakeOptimalTempC or 32
  local spread = math.max(cfg.intakeTempSpreadC or 18, 4)
  local dev = (intakeTempC or optimal) - optimal
  return clamp(math.exp(-(dev * dev) / (2 * spread * spread)), 0.88, 1.0)
end

local function calcBreathingCapacityScore(sizingRatio, carbCount)
  sizingRatio = sizingRatio or 1
  carbCount = math.max(carbCount or 1, 1)
  if sizingRatio >= 1.0 then
    return clamp(1 / (sizingRatio ^ 1.1), cfg.minBreathingVECoef or 0.78, 1.0)
  end
  if sizingRatio < 0.60 and carbCount >= 2 then
    local bonus = clamp((0.60 - sizingRatio) / 0.40, 0, 1)
    return lerp(1.0, cfg.maxBreathingCapacityCoef or 1.14, bonus)
  end
  return lerp(0.90, 1.0, clamp((1.0 - sizingRatio) / 0.42, 0, 1))
end

local function calcBreathingIntakePartsScore()
  local filterLoss = 1
  if st.airFilterActive then
    local wetness = clamp(st.airFilterWetness or 0, 0, 1)
    local humidity = clamp(st.dynamicHumidity or cfg.humidity or 0, 0, 1)
    filterLoss = 1 - wetness * 0.28 - humidity * (st.rainIntensity or 0) * 0.12
  end
  local valveScore = clamp(st.valveFlowCoef or 1, 0.55, 1.15)
  local venturiScore = clamp(st.effectiveVenturiCoef or 1, 0.72, 1.0)
  return clamp(filterLoss * valveScore * venturiScore, 0.45, 1.18)
end

local function calcBreathingScore(rpm, throttle, rho, tempC)
  local baseVE = calcBaseVE(rpm, throttle)
  local dispM3 = cfg.displacementL / 1000.0
  local revPerSec = math.max(rpm, 0) / 60.0
  local engineDemandM3s = dispM3 * revPerSec * 0.5 * baseVE
  local ratedFlowM3s = math.max(cfg.carbRatedCFM or 0, 0) * 0.00047194745
  local effectiveRatedM3s = ratedFlowM3s * clamp(cfg.carbFlowCalibrationCoef or 0.80, 0.55, 1.15)
  local sizingRatio = effectiveRatedM3s > 0 and (engineDemandM3s / effectiveRatedM3s) or 1
  local capacityScore = calcBreathingCapacityScore(sizingRatio, cfg.carbCount)
  local intakeScore = calcBreathingIntakePartsScore()
  local tempScore = calcBreathingTempEfficiency(st.intakeTempC or tempC)
  local score = capacityScore * intakeScore * tempScore
  st.breathingSizingRatio = sizingRatio
  st.breathingCapacityScore = capacityScore
  st.breathingIntakeScore = intakeScore
  return clamp(score, cfg.minBreathingVECoef or 0.55, cfg.maxBreathingCapacityCoef or 1.18)
end

local function calcVE(rpm, throttle, tempC, breathingScore)
  local baseVE = calcBaseVE(rpm, throttle)
  local rpmLoad = clamp(rpm / math.max(cfg.vePeakRPM, cfg.idleRPM + 200), 0, 1.15)
  local throttleWeight = clamp(throttle * (0.5 + 0.5 * rpmLoad), 0, 1) * 0.82
  local breathingVE = lerp(1.0, breathingScore or 1, throttleWeight)
  local tempVE = calcBreathingTempEfficiency(st.intakeTempC or tempC)
  return finiteNonNegative(baseVE * breathingVE * tempVE, 0)
end

local function calcEngineAirMassFlow(rpm, throttle, rho, tempC, breathingScore)
  -- Four-stroke engine: one intake event each two crank rotations.
  local dispM3 = cfg.displacementL / 1000.0
  local revPerSec = math.max(rpm, 0) / 60.0
  local ve = calcVE(rpm, throttle, tempC, breathingScore)
  local intakeM3s = dispM3 * revPerSec * 0.5 * ve
  return intakeM3s * rho, ve, intakeM3s
end

local function calcTunnelVenturiPressureDrop(airM3s, rhoAir)
  if not st.tunnelVenturiActive then
    st.tunnelVenturiVelocityMS = 0
    st.tunnelVenturiPressureDropPa = 0
    st.tunnelVenturiReynolds = 0
    return 0
  end

  local throatD = math.max(st.tunnelVenturiThroatDiameterMM or 40, 5) / 1000.0
  local inletD = math.max(st.tunnelVenturiInletDiameterMM or throatD * 1000, throatD * 1000) / 1000.0
  local throatArea = math.pi * throatD * throatD * 0.25
  local velocity = airM3s / math.max(throatArea, 1e-7)
  local tempK = math.max((cfg.airTempC or 20) + 273.15, 120)
  local viscosity = 1.716e-5 * (tempK / 273.15) ^ 1.5 * (273.15 + 111) / (tempK + 111)
  local reynolds = rhoAir * math.abs(velocity) * throatD / math.max(viscosity, 1e-9)
  local relativeRoughness = (st.tunnelVenturiSurfaceRoughnessM or 0.000015) / throatD
  local frictionFactor
  if reynolds > 4000 then
    local swameeJain = relativeRoughness / 3.7 + 5.74 / math.max(reynolds, 1) ^ 0.9
    frictionFactor = 0.25 / math.max((math.log(swameeJain) / math.log(10)) ^ 2, 1e-6)
  elseif reynolds > 1 then
    frictionFactor = 64 / reynolds
  else
    frictionFactor = 0
  end
  local areaRatio = clamp((throatD / math.max(inletD, throatD)) ^ 2, 0.01, 1)
  local contractionLoss = (1 - areaRatio) ^ 2
  local frictionLoss = frictionFactor * math.max(st.tunnelVenturiLengthM or 0.12, 0.01) / throatD
  local dischargeCoef = math.max(st.tunnelVenturiDischargeCoefficient or 0.94, 0.1)
  local lossCoefficient = (st.tunnelVenturiLocalLossCoefficient or 0.18)
    + contractionLoss + frictionLoss
  local pressureDrop = 0.5 * rhoAir * velocity * velocity * lossCoefficient
    / (dischargeCoef * dischargeCoef)

  st.tunnelVenturiVelocityMS = velocity
  st.tunnelVenturiPressureDropPa = pressureDrop
  st.tunnelVenturiReynolds = reynolds
  st.tunnelVenturiFrictionFactor = frictionFactor
  return pressureDrop
end

local function calcAirFilterPressureDrop(airM3s, rhoAir)
  if not st.airFilterActive then
    st.airFilterVelocityMS = 0
    st.airFilterPressureDropPa = 0
    return 0
  end

  local area = math.max(st.airFilterFlowAreaM2 or 0.01, 0.0001)
  local velocity = airM3s / area
  local mediaAreaRatio = area / math.max(st.airFilterMediaAreaM2 or area, area)
  local humidityLoading = 1 + math.max((st.dynamicHumidity or cfg.humidity or 0.45) - 0.55, 0) * 0.18
  local wetLoading = 1 + (st.airFilterWetness or 0) * (st.airFilterWetSensitivity or 2.25)
  local mediaLoss = (st.airFilterDryLossCoefficient or 0.30)
    * humidityLoading * wetLoading * clamp(mediaAreaRatio * 10, 0.45, 1.20)
  local dischargeCoef = math.max(st.airFilterDischargeCoefficient or 0.97, 0.1)
  local pressureDrop = 0.5 * rhoAir * velocity * velocity * mediaLoss
    / (dischargeCoef * dischargeCoef)

  st.airFilterVelocityMS = velocity
  st.airFilterPressureDropPa = pressureDrop
  return pressureDrop
end

local function calcIntakePressure(airM3s, rhoAir, pressurePa, throttle, inletArea, inletCd)
  local cylinders = math.max(cfg.injectorCount, 1)
  local runnerD = math.max(st.runnerDiameterMM or 35, 5) / 1000.0
  local runnerArea = math.pi * runnerD * runnerD * 0.25 * math.max(cylinders * 0.5, 1)
  local effectiveInletArea = math.max(inletArea * inletCd, 1e-6)
  local valveArea = math.max((st.valveCurtainAreaM2 or runnerArea) * cfg.valveDischargeCoef, 1e-6)
  local effectiveArea = math.max(math.min(effectiveInletArea, runnerArea * cfg.runnerDischargeCoef, valveArea), 1e-6)
  local inletVelocity = airM3s / effectiveArea
  local runnerVelocity = airM3s / math.max(runnerArea, 1e-6)
  local runnerLoss = cfg.runnerFrictionFactor * (st.runnerRoughnessFactor or 1) * math.max(st.runnerLengthM or 0.28, 0.02) / runnerD
  local dynamicPressure = 0.5 * rhoAir * inletVelocity * inletVelocity
  local runnerDynamicPressure = 0.5 * rhoAir * runnerVelocity * runnerVelocity
  local tunnelPressureDrop = calcTunnelVenturiPressureDrop(airM3s, rhoAir)
  local filterPressureDrop = calcAirFilterPressureDrop(airM3s, rhoAir)
  local pressureDrop = dynamicPressure * cfg.intakeLocalLossCoef
    + runnerDynamicPressure * runnerLoss + tunnelPressureDrop + filterPressureDrop
  local manifoldPressure = math.max(pressurePa - pressureDrop, 1000)
  if manifoldPressure > pressurePa then manifoldPressure = pressurePa end
  local pressureRatio = manifoldPressure / math.max(pressurePa, 1)
  local restriction = clamp(1 - pressureRatio, 0, 1)
  return manifoldPressure, pressureRatio, restriction, inletVelocity, pressureDrop, runnerVelocity
end

local function calcMaxVenturiCapacity(venturiArea, tempC, throttle)
  local tempK = math.max((tempC or cfg.airTempC or 20) + 273.15, 200)
  local sonicVelocity = math.sqrt(1.4 * 287.05 * tempK)
  local throttleGate = clamp(0.10 + 0.90 * math.sqrt(math.max(throttle, 0)), 0.08, 1)
  local dischargeCoef = math.max(cfg.carbDischargeCoef or 0.82, 0.45)
  local maxFlowM3s = venturiArea * dischargeCoef * sonicVelocity * throttleGate
  local maxVelocity = maxFlowM3s / math.max(venturiArea, 1e-7)
  return maxFlowM3s, maxVelocity, sonicVelocity
end

local function applyCarbAirRestriction(airM3s, airKgS, rhoAir, throttle, pressurePa, tempC)
  local boreArea, venturiArea, activeBarrels, secondaryOpening = getActiveCarbGeometry(throttle)
  local throttleArea = boreArea * clamp(0.08 + 0.92 * math.sqrt(math.max(throttle, 0)), 0.04, 1)
  local inletArea = math.max(math.min(throttleArea, venturiArea), 1e-7)
  local manifoldPressure, pressureRatio, restriction, velocity, pressureDrop, runnerVelocity =
    calcIntakePressure(airM3s, rhoAir, pressurePa, throttle, inletArea, cfg.carbDischargeCoef)

  local maxVenturiFlowM3s, maxVenturiVelocity, sonicVelocity = calcMaxVenturiCapacity(venturiArea, tempC, throttle)
  local venturiDemandRatio = airM3s / math.max(maxVenturiFlowM3s, 1e-9)
  local geometricChokeRatio = 1
  if venturiDemandRatio > 1 then
    geometricChokeRatio = 1 / (venturiDemandRatio * venturiDemandRatio)
  end

  local ratedFlowM3s = math.max(cfg.carbRatedCFM or 0, 0) * 0.00047194745
  local effectiveRatedM3s = ratedFlowM3s * clamp(cfg.carbFlowCalibrationCoef or 0.80, 0.55, 1.15)
  local cfmLoad = effectiveRatedM3s > 0 and (airM3s / effectiveRatedM3s) or 0
  local cfmRatio = 1
  local rpm = getElectricsValue("rpm", getElectricsValue("engineRPM", cfg.idleRPM))
  local _, _, engineDemandM3s = calcEngineAirMassFlow(rpm, throttle, rhoAir, tempC)
  local sizingRatio = engineDemandM3s / math.max(effectiveRatedM3s, 1e-9)
  st.carbSizingRatio = sizingRatio
  if ratedFlowM3s > 0 then
    local cfmPressureDrop = (cfg.carbRatingPressureDropPa or 5079) * cfmLoad * cfmLoad
    local cfmManifoldPressure = math.max(pressurePa - cfmPressureDrop, 1000)
    if cfmManifoldPressure < manifoldPressure then
      manifoldPressure = cfmManifoldPressure
      pressureRatio = manifoldPressure / math.max(pressurePa, 1)
      pressureDrop = pressurePa - manifoldPressure
    end
    local function applyDemandRatioPenalty(loadRatio)
      if loadRatio > 1 then
        return 1 / (loadRatio * loadRatio)
      end
      local startRatio = cfg.carbPartialRestrictionStart or 0.55
      if loadRatio > startRatio then
        local span = math.max(1 - startRatio, 0.05)
        local t = clamp((loadRatio - startRatio) / span, 0, 1)
        return lerp(1, 1 / (loadRatio * loadRatio), t * t)
      end
      return 1
    end
    if venturiDemandRatio > 1 then
      cfmRatio = math.min(cfmRatio, geometricChokeRatio)
    end
    cfmRatio = math.min(cfmRatio, applyDemandRatioPenalty(math.max(cfmLoad, sizingRatio)))
  elseif venturiDemandRatio > 1 then
    cfmRatio = geometricChokeRatio
  end

  local factor = math.min(pressureRatio, cfmRatio, geometricChokeRatio)
  if ratedFlowM3s > 0 and sizingRatio < 0.42 and (cfg.carbCount or 1) >= 2 then
    local bonus = clamp(cfg.multiCarbFlowBonus or 1.06, 1, 1.12)
    local bonusBlend = clamp((0.42 - sizingRatio) / 0.30, 0, 1)
    factor = factor * lerp(1, bonus, bonusBlend)
  end
  local deliveredAirM3s = math.min(airM3s * factor, maxVenturiFlowM3s)
  local deliveryRatio = deliveredAirM3s / math.max(airM3s, 1e-9)
  factor = deliveryRatio

  local sonicLimit = clamp((velocity - cfg.carbSonicStartMS) / math.max(cfg.carbSonicEndMS - cfg.carbSonicStartMS, 1), 0, 1)
  restriction = clamp(1 - factor, 0, 1)
  st.activeCarbBarrels = activeBarrels
  st.carbSecondaryOpening = secondaryOpening
  st.activeCarbBoreAreaM2 = boreArea
  st.activeVenturiAreaM2 = venturiArea
  st.maxVenturiAreaM2 = venturiArea
  st.maxVenturiFlowM3s = maxVenturiFlowM3s
  st.maxVenturiVelocityMS = maxVenturiVelocity
  st.venturiDemandRatio = venturiDemandRatio
  st.venturiSonicVelocityMS = sonicVelocity
  st.carbCFMLoad = cfmLoad
  st.manifoldPressurePa = manifoldPressure
  st.runnerAirMS = runnerVelocity
  st.sonicLimit = sonicLimit

  return deliveredAirM3s, airKgS * deliveryRatio, velocity, restriction, pressureDrop, manifoldPressure
end

local function applyInjectionAirRestriction(airM3s, airKgS, rhoAir, throttle, pressurePa)
  local throttleD = math.max(st.throttleBodyDiameterMM or cfg.throttleBodyDiameterMM, 1) / 1000.0
  local throttleArea = math.pi * throttleD * throttleD * 0.25 * math.max(cfg.throttleBodyCount, 1)
  throttleArea = throttleArea * clamp(0.06 + 0.94 * math.sqrt(math.max(throttle, 0)), 0.035, 1)
  local manifoldPressure, pressureRatio, restriction, velocity, pressureDrop, runnerVelocity =
    calcIntakePressure(airM3s, rhoAir, pressurePa, throttle, throttleArea, cfg.throttleBodyDischargeCoef)
  st.manifoldPressurePa = manifoldPressure
  st.runnerAirMS = runnerVelocity
  return airM3s * pressureRatio, airKgS * pressureRatio, velocity, restriction, pressureDrop, manifoldPressure
end

local function calcFuelCarb(airM3s, airKgS, rhoAir, throttle, throttleRate)
  local rpm = getElectricsValue("rpm", getElectricsValue("engineRPM", cfg.idleRPM))
  local jetD = math.max(cfg.mainJetMM, 0.05) / 1000.0
  local activeBarrels = st.activeCarbBarrels or getActiveCarbBarrels(throttle)
  local throatArea = st.activeVenturiAreaM2
  if not throatArea or throatArea <= 0 then
    local _, fallbackArea = getActiveCarbGeometry(throttle)
    throatArea = fallbackArea
  end
  local jetArea = math.pi * jetD * jetD * 0.25 * activeBarrels
  local airVelocity = airM3s / math.max(throatArea, 1e-7)
  local venturiDP = 0.5 * rhoAir * airVelocity * airVelocity

  local boostedVenturiDP = venturiDP * (cfg.carbBoosterSignalCoef or 1)
  local jetSignal = clamp((boostedVenturiDP - cfg.carbMinSignalPa) / math.max(cfg.carbFullSignalPa - cfg.carbMinSignalPa, 1), 0, 1)
  local fuelDensity = cfg.fuelDensityKgM3
  local mainFuelKgS = cfg.jetDischargeCoef * jetArea * math.sqrt(math.max(2 * fuelDensity * venturiDP, 0))
    * jetSignal * (cfg.carbFuelCalibrationCoef or 1)

  local targetAFR = cfg.stoichAFR
  if throttle < 0.14 then
    targetAFR = lerp(13.2, cfg.stoichAFR, throttle / 0.14)
  elseif throttle > cfg.powerValveThrottle then
    targetAFR = cfg.powerAFR
  end
  if st.choke > 0 then
    targetAFR = targetAFR * lerp(1, 0.82, st.choke)
  end
  local targetFuelKgS = airKgS / math.max(targetAFR, 0.1)

  local progression = clamp(1 - throttle / math.max(cfg.idleCircuitThrottle, 0.05), 0, 1)
  local rpmIdleFactor = clamp(cfg.idleRPM / math.max(rpm, 350), 0.75, 1.35)
  local idleFuelKgS = targetFuelKgS * progression * cfg.idleCircuitFuelMult * rpmIdleFactor
  local accelLoad = clamp(throttle / 0.18, 0, 1) * clamp((rpm - cfg.idleRPM * 0.72) / math.max(cfg.idleRPM * 0.45, 1), 0, 1)
  local accelFuelKgS = cfg.accelPumpKgS * clamp(throttleRate / 4.0, 0, 1) * accelLoad
  accelFuelKgS = math.min(accelFuelKgS, targetFuelKgS * lerp(0.30, 1.15, throttle))

  local rawFuelKgS = mainFuelKgS
  local rawCap = targetFuelKgS * lerp(1.35, 2.10, throttle)
  if rawFuelKgS > rawCap then rawFuelKgS = rawCap end

  local meteringBlend = lerp(0.90, 0.98, clamp((throttle - 0.02) / 0.22, 0, 1))
  local fuelKgS = targetFuelKgS + idleFuelKgS + accelFuelKgS
  if rawFuelKgS > targetFuelKgS and throttle > 0.30 then
    fuelKgS = fuelKgS + (rawFuelKgS - targetFuelKgS) * (1 - meteringBlend) * 0.30
  end

  if throttle < 0.35 then
    local minIdleAfr = lerp(10.8, 12.8, clamp(throttle / 0.20, 0, 1))
    local maxFuelForAir = airKgS / math.max(minIdleAfr, 0.1)
    if fuelKgS > maxFuelForAir then fuelKgS = maxFuelForAir end
  end

  local maxFuel = cfg.fuelPumpKgS
  if fuelKgS > maxFuel then fuelKgS = maxFuel end

  local afr = airKgS / math.max(fuelKgS, 1e-8)
  return fuelKgS, afr, venturiDP, airVelocity, jetSignal
end

local function calcFuelInjection(airKgS, throttle, tempC)
  local targetAFR = cfg.stoichAFR
  if cfg.fuelingMode == "diesel" then
    targetAFR = cfg.stoichAFR * lerp(2.75, 1.25, clamp(throttle, 0, 1))
    if throttle > 0.88 then targetAFR = cfg.powerAFR end
    if tempC < -5 then targetAFR = targetAFR * 0.96 end
    if tempC > 38 then targetAFR = targetAFR * 1.03 end
  else
    if throttle > 0.85 then targetAFR = cfg.powerAFR end
    if tempC < 5 then targetAFR = targetAFR * 0.92 end
    if tempC > 38 then targetAFR = targetAFR * 1.02 end
  end

  local targetFuelKgS = airKgS / math.max(targetAFR, 1e-6)
  local injectorMax = cfg.injectorCCMin * cfg.injectorCount / 60.0 / 1000000.0 * cfg.fuelDensityKgM3
  local fuelKgS = math.min(targetFuelKgS, injectorMax)
  local duty = fuelKgS / math.max(injectorMax, 1e-8)
  local afr = airKgS / math.max(fuelKgS, 1e-8)
  return fuelKgS, afr, duty
end

local function calcIgnition(rpm, throttle, tempC, lambda)
  if cfg.fuelingMode == "diesel" then
    return 0, 0, 0, 1.0, 0
  end

  local load = clamp(throttle, 0, 1)
  local rpmAdvance = cfg.rpmTimingGainDeg * clamp((rpm - cfg.idleRPM) / math.max(cfg.redlineRPM - cfg.idleRPM, 1), 0, 1)
  local loadRetard = cfg.loadTimingRetardDeg * load
  local hotRetard = math.max(tempC - 30, 0) * cfg.hotAirTimingRetardPerC
  local mbt = cfg.baseTimingDeg + rpmAdvance - loadRetard - hotRetard
  local distributorQuality = st.distributorQuality or 1
  local ignitionScatterDeg = (1 - distributorQuality) * (0.8 + 3.2 * clamp(rpm / math.max(cfg.redlineRPM, 1), 0, 1))
  local actualTiming = mbt + (st.distributorTimingOffsetDeg or 0)
  actualTiming = actualTiming + math.sin((st.runTime or 0) * (17 + rpm * 0.003)) * ignitionScatterDeg
  st.ignitionScatterDeg = ignitionScatterDeg

  if lambda < 0.88 then mbt = mbt - 2.0 end
  if lambda > 1.12 then mbt = mbt - 3.5 end

  local timingError = actualTiming - mbt
  local timingEfficiency = math.exp(-(timingError * timingError) / (2 * cfg.timingToleranceDeg * cfg.timingToleranceDeg))
  timingEfficiency = finiteNonNegative(timingEfficiency, 0)

  local advanceRisk = clamp((timingError - 3.5) / 12.0, 0, 1)
  return actualTiming, mbt, timingError, timingEfficiency, advanceRisk
end

local function mixtureEfficiency(lambda)
  if cfg.fuelingMode == "diesel" then
    if lambda < 1.0 then
      return finiteNonNegative(0.48 + 0.52 * lambda, 0)
    end
    local peakLambda = 1.45
    local eff = math.exp(-((lambda - peakLambda) * (lambda - peakLambda)) / (2 * 0.85 * 0.85))
    return finiteNonNegative(eff, 0)
  end

  local peakLambda = 0.92
  local width = lambda < peakLambda and 0.20 or 0.28
  local eff = math.exp(-((lambda - peakLambda) * (lambda - peakLambda)) / (2 * width * width))
  return finiteNonNegative(eff, 0)
end

local function idealOttoEfficiency(compressionRatio)
  local gamma = cfg.fuelingMode == "diesel" and 1.35 or 1.32
  return 1 - (1 / math.max(compressionRatio, 1.01) ^ (gamma - 1))
end

local function calcPistonAndCompressionEfficiency(rpm, throttle, tempC, dt)
  local thermals = engine and engine.thermals or nil
  local wallTempC = tonumber(thermals and thermals.cylinderWallTemperature) or st.combustionTempC * 0.12 or tempC
  local oilTempC = tonumber(thermals and thermals.oilTemperature) or wallTempC
  local blockTempC = tonumber(thermals and thermals.engineBlockTemperature) or wallTempC
  local load = throttle * clamp(rpm / math.max(cfg.redlineRPM, 1), 0, 1)
  local pistonThermalMass = math.max((st.pistonMaterialDensityKgM3 or 2700) / 2700, 0.35)
  -- Use bulk/skirt temperature for expansion and oil-film behavior. Piston crown
  -- temperature is substantially higher and must not be compared to skirt limits.
  local targetPistonTempC = wallTempC
    + clamp(st.combustionTempC - wallTempC, 0, 1100) * (0.035 + 0.055 * load)
  local thermalTimeConstant = 18 * pistonThermalMass
  local thermalResponse = 1 - math.exp(-math.max(dt or 0.016, 0) / math.max(thermalTimeConstant, 0.5))
  local pistonTempC = lerp(st.pistonTempC or wallTempC, targetPistonTempC, thermalResponse)

  local ringSealCoef = clamp(st.ringSealCoef or 1, 0.20, 1.08)
  local ringFrictionCoef = clamp(st.ringFrictionCoef or 1, 0.80, 1.50)
  local bearingFrictionCoef = clamp(st.bearingFrictionCoef or 1, 0.75, 1.60)
  local expansionCoef = st.pistonExpansionCoef or 1
  local coldClearance = clamp((cfg.pistonOptimalTempC - pistonTempC) / math.max(cfg.pistonOptimalTempC - tempC, 20), 0, 1)
  local coldSealingLoss = coldClearance * cfg.coldPistonLoss * expansionCoef * math.max(2 - ringSealCoef, 0.55)
  local coldOilLoss = clamp((cfg.oilOptimalTempC - oilTempC) / math.max(cfg.oilOptimalTempC - tempC, 20), 0, 1) * cfg.coldOilFrictionLoss * bearingFrictionCoef * ringFrictionCoef
  local hotTolerance = st.pistonHotToleranceC or 205
  local hotExpansion = clamp((pistonTempC - hotTolerance) / math.max(cfg.pistonSeizureTempC - hotTolerance, 10), 0, 1)
  local highRpmFriction = coldOilLoss * clamp(rpm / math.max(cfg.redlineRPM, 1), 0, 1) * 0.35 * bearingFrictionCoef
  local pistonEfficiency = math.max(1 - coldSealingLoss - coldOilLoss - highRpmFriction - hotExpansion * cfg.hotPistonLoss, 0) * ringSealCoef

  local detectedCR = st.autoCompressionRatio or st.compressionRatio or cfg.referenceCompressionRatio
  local actualCR = st.compressionRatio or detectedCR
  local compressionEfficiency = idealOttoEfficiency(actualCR) / math.max(idealOttoEfficiency(detectedCR), 0.05) * ringSealCoef

  st.cylinderWallTempC = wallTempC
  st.oilTempC = oilTempC
  st.blockTempC = blockTempC
  st.pistonTempC = pistonTempC
  st.pistonThermalMass = pistonThermalMass
  st.pistonEfficiency = pistonEfficiency
  st.compressionEfficiency = compressionEfficiency
  st.pistonSeizureRisk = hotExpansion
  st.coldRingSealLoss = coldSealingLoss
  st.bearingFrictionLoss = highRpmFriction
  return pistonEfficiency, compressionEfficiency
end

local function calcValveTrainEfficiency()
  local text = st.activePartsText or ""
  local hydraulic = containsAny(text, {"hydraulic lifter", "hydraulic_lifter", "hydraulic valvetrain", "hydraulic_valvetrain", "modern ecu"})
  local coldLashMM = hydraulic and 0.08 or 0.25
  local blockTempC = st.blockTempC or cfg.airTempC
  local effectiveLashMM = coldLashMM - math.max(blockTempC - 20, 0) * cfg.valveTrainExpansionMMPerC
  local tightLoss = clamp((cfg.minHotValveLashMM - effectiveLashMM) / math.max(cfg.minHotValveLashMM, 0.01), 0, 1)
  local looseLoss = clamp((effectiveLashMM - cfg.maxValveLashMM) / math.max(cfg.maxValveLashMM, 0.05), 0, 1)
  local efficiency = math.max(1 - tightLoss * 0.28 - looseLoss * 0.18, 0)
  st.coldValveLashMM = coldLashMM
  st.effectiveValveLashMM = effectiveLashMM
  st.valveTrainEfficiency = efficiency
  return efficiency
end

local function updateClimateShock(dt, tempC, pressurePa, humidity)
  if st.lastAirTempC ~= nil then
    local invDt = 1 / math.max(dt, 0.001)
    local tempRate = math.abs(tempC - st.lastAirTempC) * invDt
    local pressureRateKPa = math.abs(pressurePa - st.lastPressurePa) * invDt / 1000
    local humidityRate = math.abs(humidity - st.lastHumidity) * invDt
    local target = clamp(tempRate / 18 + pressureRateKPa / 14 + humidityRate * 1.4, 0, 1)
    st.climateShock = clamp(math.max(st.climateShock - dt * 0.18, target), 0, 1)
  end

  st.lastAirTempC = tempC
  st.lastPressurePa = pressurePa
  st.lastHumidity = humidity
end

local function markEngineDamage(kind)
  if not engine then return end

  if kind == "rings" and not st.ringsDamaged then
    st.ringsDamaged = true
    st.engineDamageTorqueCoef = finiteNonNegative((st.engineDamageTorqueCoef or 1) * 0.82, 1)
    pcall(function() if engine.thermals then engine.thermals.pistonRingsDamaged = true end end)
    pcall(function() if damageTracker then damageTracker.setDamage("engine", "pistonRingsDamaged", true, true) end end)
  elseif kind == "head" and not st.headGasketDamaged then
    st.headGasketDamaged = true
    st.engineDamageTorqueCoef = finiteNonNegative((st.engineDamageTorqueCoef or 1) * 0.78, 1)
    pcall(function() if engine.thermals then engine.thermals.headGasketBlown = true end end)
    pcall(function() if damageTracker then damageTracker.setDamage("engine", "headGasketDamaged", true, true) end end)
  elseif kind == "bearings" and not st.rodBearingDamaged then
    st.rodBearingDamaged = true
    st.engineFrictionDamageMult = finiteNonNegative((st.engineFrictionDamageMult or 1) * 2.6, 1)
    pcall(function() if engine.thermals then engine.thermals.connectingRodBearingsDamaged = true end end)
    pcall(function() if damageTracker then damageTracker.setDamage("engine", "rodBearingsDamaged", true, true) end end)
  end
end

local function updateThermalAndFailures(dt, rpm, throttle, tempC, pressurePa, humidity, lambda, advanceRisk, startProtection)
  local loadHeat = throttle * clamp(rpm / math.max(cfg.redlineRPM, 1), 0, 1)
  local leanHeat = clamp((lambda - 1.05) / 0.30, 0, 1)
  local richCool = clamp((0.88 - lambda) / 0.25, 0, 1)
  local hotAmbient = clamp((tempC - 25) / 35, 0, 1)
  local speed = math.abs(getElectricsValue("wheelspeed", getElectricsValue("airspeed", 0)))
  local speedCooling = clamp(speed / 70.0, 0, 1)
  local rainEvap = (st.rainIntensity or 0) * clamp(speed / 45.0, 0, 1)
  local intakeDensityRatio = math.max((st.intakeMaterialDensityKgM3 or 2700) / 2700, 0.35)
  local intakeHeatRate = clamp(dt * (0.18 / math.sqrt(intakeDensityRatio)), 0, 1)
  local intakeHeatIsolationCoef = clamp(st.intakeHeatIsolationCoef or 1, 0.45, 1.20)

  st.combustionTempC = lerp(st.combustionTempC, 550 + 720 * loadHeat + 260 * leanHeat - 90 * richCool + 75 * hotAmbient, clamp(dt * 1.8, 0, 1))
  st.intakeTempC = lerp(st.intakeTempC or tempC, tempC + 42 * loadHeat * intakeHeatIsolationCoef + 18 * hotAmbient - 12 * speedCooling - 14 * rainEvap, intakeHeatRate)
  st.fuelTempC = lerp(st.fuelTempC, st.intakeTempC + 7 * loadHeat, clamp(dt * 0.12, 0, 1))
  local oilCoolingCoef = clamp(st.oilCoolingCoef or 1, 0.40, 2.20)
  local oilPressureReserveCoef = clamp(st.oilPressureReserveCoef or 1, 0.30, 2.00)
  local bearingOilDemand = clamp(st.bearingOilDemand or 1, 0.80, 1.80)
  local gLoadPenalty = clamp((st.longitudinalG or 0) * (st.longitudinalG or 0) + (st.lateralG or 0) * (st.lateralG or 0), 0, 4)
  gLoadPenalty = gLoadPenalty / math.max(st.oilGControlCoef or 1, 0.25)
  local oilStressGain = loadHeat * (0.04 + 0.10 * leanHeat + 0.05 * hotAmbient + 0.16 * (st.pistonSeizureRisk or 0))
  oilStressGain = oilStressGain * bearingOilDemand + 0.012 * clamp(gLoadPenalty - 1.0, 0, 3) / math.max(oilPressureReserveCoef, 0.3)
  local oilStressRecovery = 0.018 * oilCoolingCoef * math.sqrt(oilPressureReserveCoef)
  st.oilStress = clamp(st.oilStress + dt * (oilStressGain - oilStressRecovery), 0, 1)

  local octanePenalty = clamp((cfg.referenceOctaneRON - cfg.fuelOctaneRON) / 14.0, 0, 1)
  local compressionPenalty = clamp(((st.compressionRatio or cfg.referenceCompressionRatio) - cfg.referenceCompressionRatio) / 5.0, 0, 1)
  local knock = 0
  knock = knock + 0.35 * advanceRisk
  knock = knock + 0.25 * clamp((tempC - 30) / 30, 0, 1)
  knock = knock + 0.25 * clamp((lambda - 1.03) / 0.23, 0, 1)
  knock = knock + 0.18 * throttle
  knock = knock + 0.12 * clamp((st.combustionTempC - 930) / 260, 0, 1)
  knock = knock + 0.22 * octanePenalty
  knock = knock + 0.20 * compressionPenalty
  st.knockRisk = clamp(knock, 0, 1)

  local icingTemp = st.intakeTempC or tempC
  local icingZone = (cfg.fuelingMode == "carb" and icingTemp > -8 and icingTemp < 14 and humidity > 0.56 and throttle > 0.08 and throttle < 0.75)
  local icingRate = icingZone and (0.030 + 0.075 * humidity + 0.045 * (st.rainIntensity or 0)) or -0.075
  st.carbIce = clamp(st.carbIce + dt * icingRate, 0, 1)

  local vaporRisk = clamp((st.fuelTempC - 54) / 32, 0, 1) * clamp((96000 - pressurePa) / 26000, 0, 1) * lerp(0.4, 1.0, throttle)
  st.vaporLock = clamp(st.vaporLock + dt * (vaporRisk * 0.08 - 0.025), 0, 1)

  local mixBad = math.max(clamp((lambda - 1.22) / 0.45, 0, 1), clamp((0.72 - lambda) / 0.30, 0, 1))
  st.fouling = clamp(st.fouling + dt * (clamp((0.82 - lambda) / 0.22, 0, 1) * 0.035 - 0.008 * throttle), 0, 1)
  st.misfire = clamp(0.50 * mixBad + 0.35 * st.carbIce + 0.45 * st.vaporLock + 0.20 * st.fouling + 0.18 * st.climateShock, 0, 1)
  st.misfire = st.misfire * (1 - clamp(startProtection, 0, 1) * cfg.startFailureSuppression)

  local ringKnockThreshold = clamp(0.82 + ((st.ringDurabilityCoef or 1) - 1) * 0.08, 0.68, 0.92)
  local headKnockThreshold = clamp(0.90 + ((st.headGasketStrengthCoef or 1) - 1) * 0.07, 0.72, 0.98)
  local bearingStressThreshold = clamp(0.92 + ((st.bearingDurabilityCoef or 1) - 1) * 0.10, 0.66, 0.98)

  if st.knockRisk > ringKnockThreshold and chancePerSecond((st.knockRisk - ringKnockThreshold) * cfg.failureAggression, dt) then
    markEngineDamage("rings")
  end
  if st.knockRisk > headKnockThreshold and chancePerSecond((st.knockRisk - headKnockThreshold) * cfg.failureAggression * 0.55, dt) then
    markEngineDamage("head")
  end
  if st.oilStress > bearingStressThreshold and chancePerSecond((st.oilStress - bearingStressThreshold) * cfg.failureAggression * 0.40, dt) then
    markEngineDamage("bearings")
  end
  if (st.pistonSeizureRisk or 0) > 0.94 and chancePerSecond(((st.pistonSeizureRisk or 0) - 0.94) * cfg.failureAggression * 0.80, dt) then
    markEngineDamage("rings")
  end

  local thermals = engine and engine.thermals or nil
  local wallTempC = tonumber(thermals and thermals.cylinderWallTemperature) or st.combustionTempC * 0.12 or tempC
  local pistonTempC = st.pistonTempC or wallTempC
  local coldHighRpm = pistonTempC < (cfg.pistonOptimalTempC - 12)
    and rpm > cfg.redlineRPM * 0.85
    and throttle > 0.7
  if coldHighRpm then
    st.coldHighRpmTimer = (st.coldHighRpmTimer or 0) + dt
    st.venturiWear = clamp((st.venturiWear or 0) + dt * (0.004 + 0.002 * (st.knockRisk or 0)), 0, 0.15)
    if st.coldHighRpmTimer > 3.0 and chancePerSecond(0.10 * cfg.failureAggression, dt) then
      markEngineDamage("rings")
    end
  else
    st.coldHighRpmTimer = math.max((st.coldHighRpmTimer or 0) - dt * 0.5, 0)
  end

  local overheatRisk = math.max(st.pistonSeizureRisk or 0, clamp((st.combustionTempC - 980) / 220, 0, 1))
  if overheatRisk > 0.55 then
    st.overheatTimer = (st.overheatTimer or 0) + dt
    st.venturiWear = clamp((st.venturiWear or 0) + dt * overheatRisk * 0.0015, 0, 0.15)
    if st.overheatTimer > 4.5 and overheatRisk > 0.82 and chancePerSecond((overheatRisk - 0.82) * cfg.failureAggression * 0.35, dt) then
      markEngineDamage("head")
    end
    if st.overheatTimer > 7.0 and overheatRisk > 0.92 and chancePerSecond((overheatRisk - 0.92) * cfg.failureAggression * 0.25, dt) then
      markEngineDamage("bearings")
    end
  else
    st.overheatTimer = math.max((st.overheatTimer or 0) - dt * 0.35, 0)
  end

  local loadWear = loadHeat * 0.00006 + (st.knockRisk or 0) * 0.00012
  st.venturiWear = clamp((st.venturiWear or 0) + dt * loadWear - dt * 0.000008, 0, 0.15)

  local severeFailure = math.max(st.vaporLock / 0.92, st.carbIce / 0.96, st.misfire / 0.96)
  if severeFailure > 1 and startProtection < 0.12 then
    st.severeFailureTimer = (st.severeFailureTimer or 0) + dt
  else
    st.severeFailureTimer = math.max((st.severeFailureTimer or 0) - dt * 2.0, 0)
  end

  if engine and cfg.allowStall and st.severeFailureTimer > cfg.stallDelaySeconds then
    pcall(function() engine.isStalled = true end)
  end

  if engine and cfg.allowLockup and st.oilStress > 0.995 and chancePerSecond(0.15 * cfg.failureAggression, dt) then
    pcall(function() engine:lockUp() end)
  end
end

local function captureEngineFrictionBaseline()
  if not engine or st.baselineCaptured then return end
  st.baseFriction = engine.friction
  st.baseDynamicFriction = engine.dynamicFriction
  st.baselineCaptured = true
end

local function restoreNativeEngineTorqueState()
  if not engine then engine = getMainEngine() end
  if not engine then return end
  if engine.outputTorqueState ~= nil then
    engine.outputTorqueState = 1
  end
  if type(engine.setOutputTorqueState) == "function" then
    pcall(function() engine:setOutputTorqueState(1) end)
  end
  st.lastAppliedEngineEffectFactor = 1
  st.appliedViaOutputTorqueState = engine.outputTorqueState ~= nil
end

local function restoreNativeEngineFriction()
  if not engine then engine = getMainEngine() end
  if not engine or not st.baselineCaptured then return end
  if st.baseFriction ~= nil and engine.friction ~= nil then
    engine.friction = st.baseFriction
  end
  if st.baseDynamicFriction ~= nil and engine.dynamicFriction ~= nil then
    engine.dynamicFriction = st.baseDynamicFriction
  end
end

local function applyEngineFrictionDamage()
  if not engine or not st.baselineCaptured then return end
  local mult = finiteNonNegative(st.engineFrictionDamageMult or 1, 1)
  if mult <= 1.001 then return end
  if st.baseFriction ~= nil and engine.friction ~= nil then
    engine.friction = st.baseFriction * mult
  end
  if st.baseDynamicFriction ~= nil and engine.dynamicFriction ~= nil then
    engine.dynamicFriction = st.baseDynamicFriction * mult
  end
end

local function engineSupportsTorqueScaling()
  if not engine then engine = getMainEngine() end
  return engine and engine.outputTorqueState ~= nil
end

local function applyTorqueAndFriction(torqueFactor)
  if not engine or not cfg.enableEngineEffect then return end

  torqueFactor = finiteNonNegative(torqueFactor, 1)
  st.lastCalculatedTorqueFactor = torqueFactor
  st.engineEffectTarget = torqueFactor

  captureEngineFrictionBaseline()

  if cfg.enableFrictionFallback then
    if st.baseFriction ~= nil and engine.friction ~= nil then
      local loss = clamp(1 - torqueFactor, 0, 1)
      pcall(function() engine.friction = st.baseFriction + cfg.frictionPenaltyNm * loss end)
    end
    if st.baseDynamicFriction ~= nil and engine.dynamicFriction ~= nil then
      local rpm = getElectricsValue("rpm", getElectricsValue("engineRPM", 1000))
      local loss = clamp(1 - torqueFactor, 0, 1)
      pcall(function() engine.dynamicFriction = st.baseDynamicFriction + cfg.dynamicFrictionPenalty * loss * clamp(rpm / 6000, 0.1, 1.4) end)
    end
  end

  applyEngineFrictionDamage()
end

local function applyEngineEffectCoef()
  if not engine then engine = getMainEngine() end
  if not engine then return end

  if not cfg.enableEngineEffect then
    restoreNativeEngineTorqueState()
    return
  end

  if not engineSupportsTorqueScaling() then
    if not st.warnedNoOutputTorqueState then
      st.warnedNoOutputTorqueState = true
      log("W", "UltraRealismEngine", "outputTorqueState missing on mainEngine; torque scaling disabled")
    end
    return
  end

  local target = finiteNonNegative(st.engineEffectTarget, 1) * finiteNonNegative(st.engineDamageTorqueCoef or 1, 1)
  -- BeamNG developers recommend outputTorqueState for real torque scaling.
  -- intakeAirDensityCoef is reset every GFX frame by combustionEngine and must not be used here.
  engine.outputTorqueState = target
  st.lastAppliedEngineEffectFactor = target
  st.appliedViaOutputTorqueState = true
  if type(engine.setOutputTorqueState) == "function" then
    pcall(function() engine:setOutputTorqueState(target) end)
  end
end

local function updatePhysics()
  -- Re-publish bridge + torque coef every physics substep so forked engines read fresh state.
  publishCachedEngineBridge()
  applyEngineEffectCoef()
  if not engine then engine = getMainEngine() end
  if engine then
    local physicsRPM = getEnginePhysicsRPM()
    local driverThrottle = clamp(getElectricsValue("throttle", getElectricsValue("throttle_input", 0)), 0, 1)
    local throttle = getEffectiveThrottle(driverThrottle)
    clearFalseStallState(physicsRPM, st.appliedTorqueFactor or st.engineEffectTarget or 1, throttle)
  end
end

local function updateWheelsIntermediate(_dt)
  publishCachedEngineBridge()
  applyEngineEffectCoef()
end

local function looksLikeSuspensionBeam(beam)
  if not beam or beam.cid == nil or beam.beamSpring == nil or beam.beamDamp == nil then return false end

  local text = lowerText(beam.name) .. " " .. lowerText(beam.beamName) .. " " .. lowerText(beam.group) .. " " .. lowerText(beam.partOrigin) .. " " .. lowerText(beam.partName)
  if text:find("shock", 1, true) or text:find("damper", 1, true) or text:find("strut", 1, true) or text:find("coilover", 1, true) or text:find("spring", 1, true) or text:find("leaf", 1, true) or text:find("airbump", 1, true) then
    return true
  end

  if beam.beamDampRebound ~= nil or beam.beamDampFast ~= nil or beam.beamDampVelocitySplit ~= nil then
    return true
  end

  return false
end

local function restoreSuspensionBeams()
  if not st.suspensionBeams or not obj or not obj.setBeamSpringDamp then return end
  for _, beam in ipairs(st.suspensionBeams) do
    if beam.cid and beam.spring and beam.damp then
      pcall(function() obj:setBeamSpringDamp(beam.cid, beam.spring, beam.damp, -1, -1) end)
    end
  end
end

local function refreshSuspensionBeams()
  st.suspensionBeams = {}
  if not cfg.enableSuspensionBeamEffects or not v or not v.data or not v.data.beams or not obj or not obj.setBeamSpringDamp then return end

  local beams = v.data.beams
  local count = indexedTableSize(beams)
  for i = 0, count - 1 do
    local beam = beams[i]
    if looksLikeSuspensionBeam(beam) then
      table.insert(st.suspensionBeams, {
        cid = beam.cid,
        spring = tonumber(beam.beamSpring) or 0,
        damp = tonumber(beam.beamDamp) or 0
      })
    end
  end
end

local function applySuspensionFade()
  if not cfg.enableSuspensionBeamEffects or not st.suspensionBeams or not obj or not obj.setBeamSpringDamp then return end
  local damperCoef = 1 - st.damperFade * (1 - cfg.damperMinCoef)
  local springCoef = 1 - st.springFatigue * (1 - cfg.springMinCoef)
  for _, beam in ipairs(st.suspensionBeams) do
    if beam.cid and beam.spring and beam.damp then
      pcall(function() obj:setBeamSpringDamp(beam.cid, beam.spring * springCoef, beam.damp * damperCoef, -1, -1) end)
    end
  end
end

local function updateSuspensionModel(dt, throttle, brake, steering, speed)
  local absSteer = math.abs(steering)
  local longDemand = math.abs(throttle - brake)
  local speedFactor = clamp(speed / 55.0, 0, 1.8)
  local lateralG = absSteer * speedFactor * speedFactor * cfg.steeringToLateralG
  local longG = (throttle * cfg.throttleToLongG) - (brake * cfg.brakeToLongG)
  local damperWork = (0.50 * lateralG + 0.30 * math.abs(longG) + 0.20 * speedFactor) * speedFactor

  st.damperTempC = lerp(st.damperTempC, cfg.airTempC + 20 + 120 * damperWork, clamp(dt * 0.10, 0, 1))
  st.damperFade = clamp((st.damperTempC - cfg.damperFadeStartC) / math.max(cfg.damperFadeEndC - cfg.damperFadeStartC, 1), 0, 1)
  st.springFatigue = clamp(st.springFatigue + dt * (st.damperFade * 0.010 + clamp(damperWork - 0.85, 0, 1) * 0.020 - 0.0015), 0, 1)
  st.bumpStopRisk = clamp((speedFactor * absSteer + brake * speedFactor * 0.45) - 0.8, 0, 1)
  st.lateralG = lateralG
  st.longG = longG
  st.rollLoadTransfer = clamp(lateralG * cfg.cgHeightM / math.max(cfg.trackWidthM, 0.1), 0, 1.5)
  st.pitchLoadTransfer = clamp(math.abs(longG) * cfg.cgHeightM / math.max(cfg.wheelbaseM, 0.1), 0, 1.5)

  st.suspensionApplyTimer = (st.suspensionApplyTimer or 0) + dt
  if st.suspensionApplyTimer > cfg.suspensionApplyInterval then
    st.suspensionApplyTimer = 0
    applySuspensionFade()
  end
end

local function update(dt)
  if not engine then engine = getMainEngine() end
  if engine and cfg.autoDetectEngine and not st.autoDetected then autoTuneFromEngine() end
  local partsChanged = syncActivePartsState(dt)
  if cfg.fuelingMode == "carb" and (partsChanged or not st.carbSetupScanned) then
    detectCarbSetupFromParts()
    if st.autoDetected then recalibrateCarbFuelFromEngine() end
  end
  if engine and (partsChanged or not st.enginePartsAnalyzed) then analyzeEngineParts() end
  if not dt or dt <= 0 then dt = 0.016 end
  st.runTime = (st.runTime or 0) + dt

  local rpm = getElectricsValue("rpm", getElectricsValue("engineRPM", cfg.idleRPM))
  local physicsRPM = getEnginePhysicsRPM()
  local driverThrottle = clamp(getElectricsValue("throttle", getElectricsValue("throttle_input", 0)), 0, 1)
  local throttle = getEffectiveThrottle(driverThrottle)
  local brake = clamp(getElectricsValue("brake", getElectricsValue("brake_input", 0)), 0, 1)
  local steering = clamp(getElectricsValue("steering_input", 0), -1, 1)
  local speed = math.abs(getElectricsValue("wheelspeed", getElectricsValue("airspeed", 0)))
  local throttleRate = math.max((throttle - (st.lastThrottle or throttle)) / math.max(dt, 0.001), 0)
  st.lastThrottle = throttle

  local tempC, pressurePa, humidity = detectClimateFromPreset(cfg.climatePreset)
  humidity = updateWeatherState(dt, speed, tempC, pressurePa, humidity)
  pressurePa = pressurePa + (st.ramAirPressurePa or 0)
  cfg.airTempC, cfg.pressurePa, cfg.humidity = tempC, pressurePa, humidity
  updateClimateShock(dt, tempC, pressurePa, humidity)

  refreshEffectiveVenturiState(dt, rpm, throttle, tempC)
  local rho = calcAirDensity(tempC, pressurePa, humidity)
  local breathingScore = cfg.fuelingMode == "carb" and calcBreathingScore(rpm, throttle, rho, tempC) or 1
  st.breathingScore = breathingScore
  local airKgS, ve, airM3s = calcEngineAirMassFlow(rpm, throttle, rho, tempC, breathingScore)
  local requestedAirKgS = airKgS

  local carbRestrictionVelocity, carbRestriction, throttlePlateDP = 0, 0, 0
  local manifoldPressurePa = pressurePa
  if cfg.fuelingMode == "carb" then
    airM3s, airKgS, carbRestrictionVelocity, carbRestriction, throttlePlateDP, manifoldPressurePa =
      applyCarbAirRestriction(airM3s, airKgS, rho, throttle, pressurePa, tempC)
  else
    airM3s, airKgS, carbRestrictionVelocity, carbRestriction, throttlePlateDP, manifoldPressurePa =
      applyInjectionAirRestriction(airM3s, airKgS, rho, throttle, pressurePa)
  end

  local targetChoke = 0
  if cfg.fuelingMode == "carb" and tempC < cfg.chokeBelowC and rpm < cfg.chokeDisableRPM then
    targetChoke = clamp((cfg.chokeBelowC - tempC) / math.max(cfg.chokeBelowC - cfg.fullChokeC, 1), 0, 1)
  end
  st.choke = lerp(st.choke, targetChoke, clamp(dt * 0.35, 0, 1))

  local fuelKgS, afr, venturiDP, airVelocity, injectorDuty, jetSignal
  if cfg.fuelingMode == "carb" then
    fuelKgS, afr, venturiDP, airVelocity, jetSignal = calcFuelCarb(airM3s, airKgS, rho, throttle, throttleRate)
    injectorDuty = 0
  elseif cfg.fuelingMode == "diesel" and ureDiesel and ureDiesel.calcFuel then
    fuelKgS, afr, injectorDuty = ureDiesel.calcFuel(airKgS, throttle, tempC, cfg, st)
    venturiDP, airVelocity, jetSignal = 0, 0, 0
  elseif ureEfi and ureEfi.calcFuel then
    fuelKgS, afr, injectorDuty = ureEfi.calcFuel(airKgS, throttle, tempC, cfg, st)
    venturiDP, airVelocity, jetSignal = 0, 0, 0
  else
    fuelKgS, afr, injectorDuty = calcFuelInjection(airKgS, throttle, tempC)
    venturiDP, airVelocity, jetSignal = 0, 0, 0
  end

  afr = clamp(afr, 4.0, 35.0)
  local lambda = afr / math.max(cfg.stoichAFR, 0.1)
  local userTiming, mbt, timingError, timingEff, advanceRisk
  if cfg.fuelingMode == "diesel" and ureDiesel and ureDiesel.calcIgnition then
    userTiming, mbt, timingError, timingEff, advanceRisk = ureDiesel.calcIgnition(rpm, throttle, tempC, lambda, cfg, st)
  else
    userTiming, mbt, timingError, timingEff, advanceRisk = calcIgnition(rpm, throttle, tempC, lambda)
  end
  local mixEff = mixtureEfficiency(lambda)
  local densityEff = finiteNonNegative(rho / math.max(cfg.referenceAirDensity, 0.001), 1)
  local pistonEff, compressionEff = calcPistonAndCompressionEfficiency(rpm, throttle, tempC, dt)
  local valveTrainEff = calcValveTrainEfficiency()
  local iceLoss = 1 - 0.45 * st.carbIce
  local vaporLoss = 1 - 0.60 * st.vaporLock
  local misfireLoss = 1 - 0.70 * st.misfire
  local inductionFlowRatio = 1
  if requestedAirKgS > 1e-6 then
    inductionFlowRatio = airKgS / requestedAirKgS
  end
  st.inductionFlowRatio = inductionFlowRatio
  local rpmLoad = clamp(rpm / math.max(cfg.vePeakRPM, cfg.idleRPM + 200), 0, 1.15)
  local inductionLoad = clamp(throttle * (0.35 + 0.65 * rpmLoad), 0, 1)
  st.forcedInductionBlend = (cfg.fuelingMode ~= "carb" or hasForcedInduction()) and inductionLoad or 0
  if urePartCurves and urePartCurves.multAtRPM then
    st.runtimeTorqueMult = urePartCurves.multAtRPM(rpm)
  end
  local inductionTorqueEff = lerp(1, inductionFlowRatio, inductionLoad)
  if cfg.fuelingMode == "carb" and inductionLoad > 0.55 then
    inductionTorqueEff = inductionTorqueEff * lerp(1, inductionFlowRatio, (inductionLoad - 0.55) / 0.45)
  end
  local climateShockLoss = 1 - st.climateShock * 0.16
  local densityTorqueBlend = lerp(1, densityEff, cfg.densityTorqueWeight or 0.35)
  local breathingTorqueBonus = 1
  if cfg.fuelingMode == "carb" then
    if (breathingScore or 1) > 1.02 then
      breathingTorqueBonus = lerp(1, clamp(breathingScore, 1, cfg.maxBreathingTorqueBonus or 1.12), inductionLoad)
    elseif (breathingScore or 1) < 0.90 then
      breathingTorqueBonus = lerp(clamp(breathingScore / 0.90, 0.78, 1), 1, 1 - inductionLoad * 0.25)
    end
  end

  -- Native combustionEngine already multiplies torque by intakeAirDensityCoef; partial density blend avoids double-counting.
  local performanceFactor = mixEff * timingEff * pistonEff * compressionEff * valveTrainEff
    * inductionTorqueEff * climateShockLoss * densityTorqueBlend * breathingTorqueBonus
  local failureFactor = iceLoss * vaporLoss * misfireLoss
  local rawTorqueFactor = performanceFactor * failureFactor
  local torqueFactor = finiteNonNegative(rawTorqueFactor, 1)
  local startProtection = getStarterProtection(rpm)
  local severeFailure = math.max(st.vaporLock, st.carbIce, st.misfire)
  local protectedMin = cfg.startMinTorqueFactor * startProtection
  protectedMin = lerp(protectedMin, 0, clamp((severeFailure - 0.78) / 0.22, 0, 1))
  performanceFactor = math.max(performanceFactor, protectedMin)
  rawTorqueFactor = performanceFactor * failureFactor
  torqueFactor = finiteNonNegative(rawTorqueFactor, 1)
  local appliedTorqueFactor = resolveAppliedTorqueFactor(performanceFactor, failureFactor, inductionLoad, throttle, inductionFlowRatio)
  appliedTorqueFactor = applyIdleStallGuard(physicsRPM, appliedTorqueFactor, throttle)
  st.appliedTorqueFactor = appliedTorqueFactor

  updateThermalAndFailures(dt, rpm, throttle, tempC, pressurePa, humidity, lambda, advanceRisk, startProtection)
  updateSuspensionModel(dt, driverThrottle, brake, steering, speed)
  applyTorqueAndFriction(appliedTorqueFactor)
  publishNativeRunningState(physicsRPM, appliedTorqueFactor, throttle)
  applyEngineEffectCoef()
  cacheBridgePayload(appliedTorqueFactor, throttle, fuelKgS, airKgS, lambda, afr, mixEff)
  publishCachedEngineBridge()
  clearFalseStallState(physicsRPM, appliedTorqueFactor, throttle)

  local fuelLps = fuelKgS / math.max(cfg.fuelDensityKgM3, 1) * 1000
  st.fuelUsedL = (st.fuelUsedL or 0) + fuelLps * dt

  st.telemetryTimer = (st.telemetryTimer or 0) + dt
  local publishSlowTelemetry = partsChanged
    or not st.initialTelemetryPublished
    or st.telemetryTimer >= (cfg.telemetryInterval or 0.1)
  if publishSlowTelemetry then
    st.telemetryTimer = 0
    st.initialTelemetryPublished = true
  end

  setElectricsValue("ure_enabled", 1)
  setElectricsValue("ure_driverThrottle", driverThrottle)
  setElectricsValue("ure_effectiveThrottle", throttle)
  setElectricsValue("ure_carbThrottleVisual", clamp(throttle, 0, 1))
  setElectricsValue("ure_carbSlideVisual", math.sqrt(clamp(throttle, 0, 1)))
  setElectricsValue("ure_carbLinkageVisual", clamp(driverThrottle, 0, 1))
  setElectricsValue("ure_startProtection", startProtection)
  setElectricsValue("ure_rawTorqueFactor", rawTorqueFactor)
  setElectricsValue("ure_torqueFactor", torqueFactor)
  setElectricsValue("ure_appliedTorqueFactor", appliedTorqueFactor or torqueFactor)
  setElectricsValue("ure_performanceTorqueFactor", performanceFactor)
  setElectricsValue("ure_failureTorqueFactor", failureFactor)
  setElectricsValue("ure_engineEffectTarget", st.engineEffectTarget or 1)
  setElectricsValue("ure_engineEffectApplied", st.lastAppliedEngineEffectFactor or 1)
  setElectricsValue("ure_afr", afr)
  setElectricsValue("ure_lambda", lambda)
  setElectricsValue("ure_fuel_gps", fuelKgS * 1000)
  setElectricsValue("ure_air_gps", airKgS * 1000)
  setElectricsValue("ure_misfire", st.misfire)
  setElectricsValue("ure_carbIce", st.carbIce)
  setElectricsValue("ure_vaporLock", st.vaporLock)
  setElectricsValue("ure_knockRisk", st.knockRisk)
  setElectricsValue("ure_carbCFMLoad", st.carbCFMLoad or 0)
  setElectricsValue("ure_venturiDemandRatio", st.venturiDemandRatio or 0)
  setElectricsValue("ure_choke", st.choke)
  setElectricsValue("ure_manifoldPressureKPa", manifoldPressurePa / 1000)
  setElectricsValue("ure_runtimeTorqueMult", st.runtimeTorqueMult or 1)
  setElectricsValue("ure_forcedInductionBlend", st.forcedInductionBlend or 0)
  setElectricsValue("ure_nativeOwnershipActive", st.nativeOwnershipActive and 1 or 0)
  setElectricsValue("ure_airTempC", tempC)

  if not publishSlowTelemetry then
    if cfg.debugLog or cfg.diagnosticLog then
      local t = st.runTime or 0
      if obj and obj.getSimTime then
        local ok, simT = pcall(function() return obj:getSimTime() end)
        if ok and type(simT) == "number" then t = simT end
      end
      local interval = cfg.diagnosticLog and 5.0 or 2.0
      if t - lastLogT > interval then
        lastLogT = t
        if cfg.diagnosticLog then
          log("I", "UltraRealismEngine", string.format(
            "diag parts=%d carb=%s count=%.0f barrels=%.0f native=%d detected=%d src=%d torque=%.3f physics=%.3f blend=%.2f applied=%.3f flow=%.3f demand=%.2f cfm=%.2f afr=%.2f lambda=%.2f misfire=%.2f stall=%d",
            st.activePartsCount or 0,
            st.activeCarbPartName ~= "" and st.activeCarbPartName or "-",
            cfg.carbCount or 0,
            cfg.carbBarrels or 0,
            st.nativeCarbSynced and 1 or 0,
            st.carbSetupDetected and 1 or 0,
            st.partsDetectionSource or 0,
            torqueFactor,
            st.appliedTorqueFactor or torqueFactor,
            st.engineEffectLoadBlend or 1,
            st.lastAppliedEngineEffectFactor or -1,
            inductionFlowRatio,
            st.venturiDemandRatio or 0,
            st.carbCFMLoad or 0,
            afr,
            lambda,
            st.misfire or 0,
            engine and engine.isStalled and 1 or 0
          ))
        elseif cfg.debugLog then
          log("I", "UltraRealismEngine", string.format(
            "AFR %.2f lambda %.2f torque %.2f knock %.2f ice %.2f vapor %.2f dampFade %.2f",
            afr, lambda, torqueFactor, st.knockRisk, st.carbIce, st.vaporLock, st.damperFade
          ))
        end
      end
    end
    return
  end

  setElectricsValue("ure_autoDetected", st.autoDetected and 1 or 0)
  setElectricsValue("ure_displacementL", cfg.displacementL)
  setElectricsValue("ure_cylinders", cfg.injectorCount)
  setElectricsValue("ure_fuelingModeId", cfg.fuelingMode == "carb" and 1 or (cfg.fuelingMode == "diesel" and 3 or 2))
  setElectricsValue("ure_engineMaxTorqueNm", st.autoMaxTorqueNm or getEngineMaxTorque() or 0)
  setElectricsValue("ure_activeCarbPartName", st.activeCarbPartName or "")
  setElectricsValue("ure_activePartsCount", st.activePartsCount or 0)
  setElectricsValue("ure_partsScanCount", partsScanCount)
  setElectricsValue("ure_activePartsSignature", st.activePartsSignature or "")
  setElectricsValue("ure_partsDetectionSource", st.partsDetectionSource or 0)
  setElectricsValue("ure_outputTorqueStateApplied", st.appliedViaOutputTorqueState and 1 or 0)
  setElectricsValue("ure_ultraEngineActive", (engine and engine.ureUltraEngine) and 1 or 0)
  setElectricsValue("ure_engineProfile", engine and (engine.ureEngineProfile or getIntegrationMode()) or getIntegrationMode())
  setElectricsValue("ure_carbCount", cfg.carbCount)
  setElectricsValue("ure_carbBarrels", cfg.carbBarrels)
  setElectricsValue("ure_activeCarbBarrels", st.activeCarbBarrels or 0)
  setElectricsValue("ure_carbPrimaryBoreMM", cfg.carbPrimaryBoreMM or cfg.carbThrottleBoreMM)
  setElectricsValue("ure_carbSecondaryBoreMM", cfg.carbSecondaryBoreMM or cfg.carbThrottleBoreMM)
  setElectricsValue("ure_carbPrimaryVenturiMM", cfg.carbPrimaryVenturiMM or cfg.carbVenturiMM)
  setElectricsValue("ure_carbSecondaryVenturiMM", cfg.carbSecondaryVenturiMM or cfg.carbVenturiMM)
  setElectricsValue("ure_carbRatedCFM", cfg.carbRatedCFM or 0)
  setElectricsValue("ure_carbCFMLoad", st.carbCFMLoad or 0)
  setElectricsValue("ure_carbSecondaryOpening", st.carbSecondaryOpening or 0)
  setElectricsValue("ure_activeCarbBoreAreaM2", st.activeCarbBoreAreaM2 or 0)
  setElectricsValue("ure_activeVenturiAreaM2", st.activeVenturiAreaM2 or 0)
  setElectricsValue("ure_maxVenturiAreaM2", st.maxVenturiAreaM2 or st.activeVenturiAreaM2 or 0)
  setElectricsValue("ure_maxVenturiFlowM3s", st.maxVenturiFlowM3s or 0)
  setElectricsValue("ure_maxVenturiVelocityMS", st.maxVenturiVelocityMS or 0)
  setElectricsValue("ure_venturiDemandRatio", st.venturiDemandRatio or 0)
  setElectricsValue("ure_venturiSonicVelocityMS", st.venturiSonicVelocityMS or 0)
  setElectricsValue("ure_carbStructuredDefinition", st.carbStructuredDefinition and 1 or 0)
  setElectricsValue("ure_nativeCarbSynced", st.nativeCarbSynced and 1 or 0)
  setElectricsValue("ure_carbTotalDiameterMM", st.carbTotalDiameterMM or 0)
  setElectricsValue("ure_venturiTotalDiameterMM", st.venturiTotalDiameterMM or 0)
  setElectricsValue("ure_venturiDiameterRatio", cfg.venturiDiameterRatio)
  setElectricsValue("ure_carbWeberEquivalentId", st.carbModelId or 0)
  setElectricsValue("ure_carbSetupDetected", st.carbSetupDetected and 1 or 0)
  setElectricsValue("ure_compressionRatio", st.compressionRatio or 0)
  setElectricsValue("ure_compressionEfficiency", st.compressionEfficiency or 1)
  setElectricsValue("ure_distributorQuality", st.distributorQuality or 0)
  setElectricsValue("ure_ignitionScatterDeg", st.ignitionScatterDeg or 0)
  setElectricsValue("ure_valveCount", st.valveCount or 0)
  setElectricsValue("ure_valveFlowCoef", st.valveFlowCoef or 1)
  setElectricsValue("ure_valveDiameterMM", st.valveDiameterMM or 0)
  setElectricsValue("ure_valveLiftMM", st.valveLiftMM or 0)
  setElectricsValue("ure_valveCurtainAreaCM2", (st.valveCurtainAreaM2 or 0) * 10000)
  setElectricsValue("ure_valveLashMM", st.effectiveValveLashMM or 0)
  setElectricsValue("ure_valveTrainEfficiency", st.valveTrainEfficiency or 1)
  setElectricsValue("ure_camStage", st.camStage or 0)
  setElectricsValue("ure_nativeCamSynced", st.nativeCamSynced and 1 or 0)
  setElectricsValue("ure_runnerDiameterMM", st.runnerDiameterMM or 0)
  setElectricsValue("ure_runnerLengthM", st.runnerLengthM or 0)
  setElectricsValue("ure_intakeMaterialDensityKgM3", st.intakeMaterialDensityKgM3 or 0)
  setElectricsValue("ure_intakeHeatIsolationCoef", st.intakeHeatIsolationCoef or 1)
  setElectricsValue("ure_pistonMaterialDensityKgM3", st.pistonMaterialDensityKgM3 or 0)
  setElectricsValue("ure_runnerRoughnessFactor", st.runnerRoughnessFactor or 1)
  setElectricsValue("ure_throttleBodyDiameterMM", st.throttleBodyDiameterMM or 0)
  setElectricsValue("ure_tunnelVenturiActive", st.tunnelVenturiActive and 1 or 0)
  setElectricsValue("ure_tunnelVenturiLengthM", st.tunnelVenturiLengthM or 0)
  setElectricsValue("ure_tunnelVenturiInletDiameterMM", st.tunnelVenturiInletDiameterMM or 0)
  setElectricsValue("ure_tunnelVenturiOutletDiameterMM", st.tunnelVenturiOutletDiameterMM or 0)
  setElectricsValue("ure_tunnelVenturiThroatDiameterMM", st.tunnelVenturiThroatDiameterMM or 0)
  setElectricsValue("ure_tunnelVenturiVelocityMS", st.tunnelVenturiVelocityMS or 0)
  setElectricsValue("ure_tunnelVenturiPressureDropPa", st.tunnelVenturiPressureDropPa or 0)
  setElectricsValue("ure_tunnelVenturiReynolds", st.tunnelVenturiReynolds or 0)
  setElectricsValue("ure_tunnelVenturiFrictionFactor", st.tunnelVenturiFrictionFactor or 0)
  setElectricsValue("ure_airFilterActive", st.airFilterActive and 1 or 0)
  setElectricsValue("ure_airFilterFlowAreaM2", st.airFilterFlowAreaM2 or 0)
  setElectricsValue("ure_airFilterMediaAreaM2", st.airFilterMediaAreaM2 or 0)
  setElectricsValue("ure_airFilterVelocityMS", st.airFilterVelocityMS or 0)
  setElectricsValue("ure_airFilterPressureDropPa", st.airFilterPressureDropPa or 0)
  setElectricsValue("ure_airFilterWetness", st.airFilterWetness or 0)
  setElectricsValue("ure_pistonTempC", st.pistonTempC or 0)
  setElectricsValue("ure_pistonEfficiency", st.pistonEfficiency or 1)
  setElectricsValue("ure_pistonSeizureRisk", st.pistonSeizureRisk or 0)
  setElectricsValue("ure_ringSealCoef", st.ringSealCoef or 1)
  setElectricsValue("ure_ringFrictionCoef", st.ringFrictionCoef or 1)
  setElectricsValue("ure_ringDurabilityCoef", st.ringDurabilityCoef or 1)
  setElectricsValue("ure_coldRingSealLoss", st.coldRingSealLoss or 0)
  setElectricsValue("ure_bearingFrictionCoef", st.bearingFrictionCoef or 1)
  setElectricsValue("ure_bearingOilDemand", st.bearingOilDemand or 1)
  setElectricsValue("ure_bearingDurabilityCoef", st.bearingDurabilityCoef or 1)
  setElectricsValue("ure_bearingFrictionLoss", st.bearingFrictionLoss or 0)
  setElectricsValue("ure_oilCoolingCoef", st.oilCoolingCoef or 1)
  setElectricsValue("ure_oilGControlCoef", st.oilGControlCoef or 1)
  setElectricsValue("ure_oilPressureReserveCoef", st.oilPressureReserveCoef or 1)
  setElectricsValue("ure_headGasketStrengthCoef", st.headGasketStrengthCoef or 1)
  setElectricsValue("ure_pressurePa", pressurePa)
  setElectricsValue("ure_manifoldPressurePa", manifoldPressurePa)
  setElectricsValue("ure_manifoldVacuumKPa", (pressurePa - manifoldPressurePa) / 1000)
  setElectricsValue("ure_humidity", humidity)
  setElectricsValue("ure_rainIntensity", st.rainIntensity or 0)
  setElectricsValue("ure_ramAirPressurePa", st.ramAirPressurePa or 0)
  setElectricsValue("ure_airDensity", rho)
  setElectricsValue("ure_fuel_lph", fuelLps * 3600)
  setElectricsValue("ure_fuelDeliveryCapacityLPH", st.fuelDeliveryCapacityLPH or 0)
  setElectricsValue("ure_fuelUsedL", st.fuelUsedL)
  setElectricsValue("ure_ve", ve)
  setElectricsValue("ure_breathingScore", st.breathingScore or 1)
  setElectricsValue("ure_breathingSizingRatio", st.breathingSizingRatio or 0)
  setElectricsValue("ure_breathingCapacityScore", st.breathingCapacityScore or 1)
  setElectricsValue("ure_breathingIntakeScore", st.breathingIntakeScore or 1)
  setElectricsValue("ure_breathingTempEfficiency", st.breathingTempEfficiency or 1)
  setElectricsValue("ure_effectiveVenturiMM", st.effectiveVenturiMM or cfg.carbVenturiMM or 0)
  setElectricsValue("ure_effectiveVenturiCoef", st.effectiveVenturiCoef or 1)
  setElectricsValue("ure_venturiWear", st.venturiWear or 0)
  setElectricsValue("ure_carbBodyTempC", st.carbBodyTempC or tempC)
  setElectricsValue("ure_densityFactor", densityEff)
  setElectricsValue("ure_mixtureEfficiency", mixEff)
  setElectricsValue("ure_timingEfficiency", timingEff)
  setElectricsValue("ure_inductionLoad", inductionLoad)
  setElectricsValue("ure_timingDeg", userTiming)
  setElectricsValue("ure_mbtDeg", mbt)
  setElectricsValue("ure_timingError", timingError)
  setElectricsValue("ure_engineDamageTorqueCoef", st.engineDamageTorqueCoef or 1)
  setElectricsValue("ure_engineEffectLoadBlend", st.engineEffectLoadBlend or 1)
  setElectricsValue("ure_climateShock", st.climateShock)
  setElectricsValue("ure_combustionTempC", st.combustionTempC)
  setElectricsValue("ure_intakeTempC", st.intakeTempC or tempC)
  setElectricsValue("ure_fuelTempC", st.fuelTempC)
  setElectricsValue("ure_oilStress", st.oilStress)
  setElectricsValue("ure_venturiDP", venturiDP)
  setElectricsValue("ure_throttlePlateDP", throttlePlateDP)
  setElectricsValue("ure_venturiAirMS", airVelocity)
  setElectricsValue("ure_carbRestrictionAirMS", carbRestrictionVelocity)
  setElectricsValue("ure_carbRestriction", carbRestriction)
  setElectricsValue("ure_inductionFlowRatio", inductionFlowRatio)
  setElectricsValue("ure_inductionTorqueEfficiency", inductionTorqueEff)
  setElectricsValue("ure_sonicLimit", st.sonicLimit or 0)
  setElectricsValue("ure_runnerAirMS", st.runnerAirMS or 0)
  setElectricsValue("ure_jetSignal", jetSignal or 0)
  setElectricsValue("ure_injectorDuty", injectorDuty or 0)
  setElectricsValue("ure_damperTempC", st.damperTempC)
  setElectricsValue("ure_damperFade", st.damperFade)
  setElectricsValue("ure_springFatigue", st.springFatigue)
  setElectricsValue("ure_bumpStopRisk", st.bumpStopRisk)
  setElectricsValue("ure_lateralG", st.lateralG or 0)
  setElectricsValue("ure_longG", st.longG or 0)
  setElectricsValue("ure_rollLoadTransfer", st.rollLoadTransfer or 0)
  setElectricsValue("ure_pitchLoadTransfer", st.pitchLoadTransfer or 0)
  setElectricsValue("ure_suspensionBeamCount", st.suspensionBeams and #st.suspensionBeams or 0)

  if cfg.debugLog or cfg.diagnosticLog then
    local t = st.runTime or 0
    if obj and obj.getSimTime then
      local ok, simT = pcall(function() return obj:getSimTime() end)
      if ok and type(simT) == "number" then t = simT end
    end
    local interval = cfg.diagnosticLog and 5.0 or 2.0
    if t - lastLogT > interval then
      lastLogT = t
      if cfg.diagnosticLog then
        log("I", "UltraRealismEngine", string.format(
          "diag parts=%d carb=%s count=%.0f barrels=%.0f native=%d detected=%d src=%d torque=%.3f physics=%.3f blend=%.2f applied=%.3f flow=%.3f demand=%.2f cfm=%.2f breath=%.3f ve=%.3f venturi=%.2f wear=%.3f afr=%.2f lambda=%.2f misfire=%.2f stall=%d",
          st.activePartsCount or 0,
          st.activeCarbPartName ~= "" and st.activeCarbPartName or "-",
          cfg.carbCount or 0,
          cfg.carbBarrels or 0,
          st.nativeCarbSynced and 1 or 0,
          st.carbSetupDetected and 1 or 0,
          st.partsDetectionSource or 0,
          torqueFactor,
          st.appliedTorqueFactor or torqueFactor,
          st.engineEffectLoadBlend or 1,
          st.lastAppliedEngineEffectFactor or -1,
          inductionFlowRatio,
          st.venturiDemandRatio or 0,
          st.carbCFMLoad or 0,
          st.breathingScore or 1,
          ve,
          st.effectiveVenturiCoef or 1,
          st.venturiWear or 0,
          afr,
          lambda,
          st.misfire or 0,
          engine and engine.isStalled and 1 or 0
        ))
      elseif cfg.debugLog then
        log("I", "UltraRealismEngine", string.format(
          "AFR %.2f lambda %.2f torque %.2f knock %.2f ice %.2f vapor %.2f dampFade %.2f",
          afr, lambda, torqueFactor, st.knockRisk, st.carbIce, st.vaporLock, st.damperFade
        ))
      end
    end
  end
end

local function reset()
  invalidateInstalledPartsCache()
  partsScanCount = 0
  restoreSuspensionBeams()
  engine = getMainEngine()
  restoreNativeEngineFriction()
  restoreNativeEngineTorqueState()
  if engineBridge and engineBridge.reset then engineBridge.reset() end
  if ureOwnership and ureOwnership.reset then ureOwnership.reset() end
  if urePartCurves and urePartCurves.reset then urePartCurves.reset() end
  if ureBus and ureBus.reset then ureBus.reset() end
  if ureEfi and ureEfi.reset then ureEfi.reset(st) end
  if ureDiesel and ureDiesel.reset then ureDiesel.reset(st) end
  st = {
    choke = 0,
    knockRisk = 0,
    misfire = 0,
    carbIce = 0,
    vaporLock = 0,
    fouling = 0,
    fuelTempC = cfg.airTempC or 25,
    combustionTempC = 450,
    oilStress = 0,
    climateShock = 0,
    fuelUsedL = 0,
    airFilterWetness = 0,
    venturiWear = 0,
    effectiveVenturiCoef = 1,
    carbBodyTempC = cfg.airTempC or 25,
    breathingScore = 1,
    activeCarbBarrels = 0,
    activeCarbBoreAreaM2 = 0,
    activeVenturiAreaM2 = 0,
    carbStructuredDefinition = false,
    carbNativeDefinition = false,
    nativeCarbSynced = false,
    nativeCamSynced = false,
    carbSetupDetected = false,
    carbSetupScanned = false,
    activePartsSignature = "",
    activePartsCount = 0,
    partsSyncTimer = 0,
    telemetryTimer = 0,
    initialTelemetryPublished = false,
    activeCarbPartName = "",
    appliedViaOutputTorqueState = false,
    enginePartsAnalyzed = false,
    damperTempC = cfg.airTempC or 25,
    damperFade = 0,
    springFatigue = 0,
    bumpStopRisk = 0,
    lateralG = 0,
    longG = 0,
    rollLoadTransfer = 0,
    pitchLoadTransfer = 0,
    baselineCaptured = false,
    engineEffectTarget = 1,
    engineDamageTorqueCoef = 1,
    engineFrictionDamageMult = 1,
    resolvedIntegrationMode = resolveIntegrationMode(),
    warnedNoOutputTorqueState = false,
    lastAppliedEngineEffectFactor = 1,
    runTime = 0,
    severeFailureTimer = 0,
    suspensionApplyTimer = 0,
    suspensionBeams = {}
  }
  refreshSuspensionBeams()
end

local function init(jbeamData)
  jbeamData = jbeamData or {}
  cfg = {}

  cfg.enableEngineEffect = bool(jbeamData.enableEngineEffect, true)
  cfg.enableFrictionFallback = bool(jbeamData.enableFrictionFallback, false)
  cfg.debugLog = bool(jbeamData.debugLog, false)
  cfg.diagnosticLog = bool(jbeamData.diagnosticLog, false)
  cfg.telemetryInterval = safeNumber(jbeamData.telemetryInterval, 0.1)
  cfg.partsSyncInterval = math.max(0.5, safeNumber(jbeamData.partsSyncInterval, 0.5))
  cfg.allowStall = bool(jbeamData.allowStall, false)
  cfg.allowLockup = bool(jbeamData.allowLockup, false)
  cfg.failureAggression = safeNumber(jbeamData.failureAggression, 0.45)

  cfg.autoDetectEngine = bool(jbeamData.autoDetectEngine, false)
  cfg.autoFuelingMode = bool(jbeamData.autoFuelingMode, false)
  cfg.preferCarburetor = bool(jbeamData.preferCarburetor, false)
  cfg.integrationMode = string.lower(tostring(jbeamData.integrationMode or "generic"))
  cfg.autoTuneVECurve = bool(jbeamData.autoTuneVECurve, cfg.autoDetectEngine)
  cfg.autoMinDisplacementL = safeNumber(jbeamData.autoMinDisplacementL, 0.6)
  cfg.autoMaxDisplacementL = safeNumber(jbeamData.autoMaxDisplacementL, 18.0)
  cfg.autoTorquePerLiterNm = safeNumber(jbeamData.autoTorquePerLiterNm, 0)

  cfg.fuelingMode = string.lower(tostring(jbeamData.fuelingMode or "carb"))
  if cfg.fuelingMode == "auto" then
    cfg.autoFuelingMode = true
    cfg.fuelingMode = cfg.preferCarburetor and "carb" or "injection"
  end
  cfg.displacementL = safeNumber(jbeamData.displacementL, 2.0)
  cfg.idleRPM = safeNumber(jbeamData.idleRPM, 850)
  cfg.redlineRPM = safeNumber(jbeamData.redlineRPM, 6500)
  cfg.veBase = safeNumber(jbeamData.veBase, 0.58)
  cfg.vePeakGain = safeNumber(jbeamData.vePeakGain, 0.34)
  cfg.baseVEPeakGain = cfg.vePeakGain
  cfg.vePeakRPM = safeNumber(jbeamData.vePeakRPM, 4200)
  cfg.veSpreadRPM = safeNumber(jbeamData.veSpreadRPM, 1800)

  cfg.climatePreset = tostring(jbeamData.climatePreset or "game_environment")
  cfg.useBeamNGEnvironment = bool(jbeamData.useBeamNGEnvironment, true)
  cfg.airTempC = safeNumber(jbeamData.airTempC, 25)
  cfg.pressurePa = safeNumber(jbeamData.pressurePa, 101325)
  cfg.humidity = safeNumber(jbeamData.humidity, 0.45)

  cfg.fuelDensityKgM3 = safeNumber(jbeamData.fuelDensityKgM3, 740)
  cfg.fuelOctaneRON = safeNumber(jbeamData.fuelOctaneRON, 95)
  cfg.referenceOctaneRON = safeNumber(jbeamData.referenceOctaneRON, 95)
  cfg.stoichAFR = safeNumber(jbeamData.stoichAFR, 14.7)
  cfg.powerAFR = safeNumber(jbeamData.powerAFR, 12.8)
  cfg.referenceAirDensity = 101325 / (287.05 * (25 + 273.15))

  cfg.carbThrottleBoreMM = safeNumber(jbeamData.carbThrottleBoreMM, 38)
  cfg.carbVenturiMM = safeNumber(jbeamData.carbVenturiMM, 27)
  cfg.mainJetMM = safeNumber(jbeamData.mainJetMM, 1.18)
  cfg.jetDischargeCoef = safeNumber(jbeamData.jetDischargeCoef, 0.74)
  cfg.carbMinSignalPa = safeNumber(jbeamData.carbMinSignalPa, 250)
  cfg.carbFullSignalPa = safeNumber(jbeamData.carbFullSignalPa, 4600)
  cfg.carbIdealAirMS = safeNumber(jbeamData.carbIdealAirMS, 82)
  cfg.carbChokeAirMS = safeNumber(jbeamData.carbChokeAirMS, 145)
  cfg.carbSonicStartMS = safeNumber(jbeamData.carbSonicStartMS, 230)
  cfg.carbSonicEndMS = safeNumber(jbeamData.carbSonicEndMS, 305)
  cfg.autoDetectCarbSetup = bool(jbeamData.autoDetectCarbSetup, true)
  cfg.carbCount = safeNumber(jbeamData.carbCount, 1)
  cfg.carbBarrels = safeNumber(jbeamData.carbBarrels, 1)
  cfg.carbPrimaryBarrels = safeNumber(jbeamData.carbPrimaryBarrels, cfg.carbBarrels)
  cfg.carbSecondaryBarrels = safeNumber(jbeamData.carbSecondaryBarrels, 0)
  cfg.carbPrimaryBoreMM = safeNumber(jbeamData.carbPrimaryBoreMM, cfg.carbThrottleBoreMM)
  cfg.carbSecondaryBoreMM = safeNumber(jbeamData.carbSecondaryBoreMM, cfg.carbThrottleBoreMM)
  cfg.carbPrimaryVenturiMM = safeNumber(jbeamData.carbPrimaryVenturiMM, cfg.carbVenturiMM)
  cfg.carbSecondaryVenturiMM = safeNumber(jbeamData.carbSecondaryVenturiMM, cfg.carbVenturiMM)
  cfg.carbSecondaryType = string.lower(tostring(jbeamData.carbSecondaryType or "synchronous"))
  cfg.carbRatedCFM = safeNumber(jbeamData.carbRatedCFM, 0)
  cfg.carbRatingPressureDropPa = safeNumber(jbeamData.carbRatingPressureDropPa, 5079)
  cfg.carbBoosterSignalCoef = safeNumber(jbeamData.carbBoosterSignalCoef, 1)
  cfg.carbAccelPumpCoef = safeNumber(jbeamData.carbAccelPumpCoef, 1)
  cfg.carbFuelCalibrationCoef = safeNumber(jbeamData.carbFuelCalibrationCoef, 1)
  cfg.carbProgressive = bool(jbeamData.carbProgressive, false)
  cfg.venturiDiameterRatio = cfg.carbThrottleBoreMM / math.max(cfg.carbVenturiMM, 0.1)
  cfg.secondaryThrottleStart = safeNumber(jbeamData.secondaryThrottleStart, 0.52)
  cfg.carbDischargeCoef = safeNumber(jbeamData.carbDischargeCoef, 0.82)
  cfg.throttleBodyDiameterMM = safeNumber(jbeamData.throttleBodyDiameterMM, 55)
  cfg.throttleBodyCount = safeNumber(jbeamData.throttleBodyCount, 1)
  cfg.throttleBodyDischargeCoef = safeNumber(jbeamData.throttleBodyDischargeCoef, 0.86)
  cfg.runnerDischargeCoef = safeNumber(jbeamData.runnerDischargeCoef, 0.88)
  cfg.valveDischargeCoef = safeNumber(jbeamData.valveDischargeCoef, 0.72)
  cfg.runnerFrictionFactor = safeNumber(jbeamData.runnerFrictionFactor, 0.028)
  cfg.intakeLocalLossCoef = safeNumber(jbeamData.intakeLocalLossCoef, 0.85)
  cfg.powerValveThrottle = safeNumber(jbeamData.powerValveThrottle, 0.72)
  cfg.powerValveFuelMult = safeNumber(jbeamData.powerValveFuelMult, 1.18)
  cfg.closedThrottleVECoef = safeNumber(jbeamData.closedThrottleVECoef, 0.18)
  cfg.idleCircuitThrottle = safeNumber(jbeamData.idleCircuitThrottle, 0.34)
  cfg.chokeFuelMult = safeNumber(jbeamData.chokeFuelMult, 0.82)
  cfg.fuelPumpKgS = safeNumber(jbeamData.fuelPumpKgS, 0.018)
  cfg.idleFuelKgS = safeNumber(jbeamData.idleFuelKgS, 0.00007 * cfg.displacementL)
  cfg.accelPumpKgS = safeNumber(jbeamData.accelPumpKgS, 0.0012 * cfg.displacementL)
  cfg.chokeBelowC = safeNumber(jbeamData.chokeBelowC, 8)
  cfg.fullChokeC = safeNumber(jbeamData.fullChokeC, -15)
  cfg.chokeDisableRPM = safeNumber(jbeamData.chokeDisableRPM, 2600)

  cfg.injectorCCMin = safeNumber(jbeamData.injectorCCMin, 240)
  cfg.injectorCount = safeNumber(jbeamData.injectorCount, 4)

  cfg.baseTimingDeg = safeNumber(jbeamData.baseTimingDeg, 12)
  cfg.rpmTimingGainDeg = safeNumber(jbeamData.rpmTimingGainDeg, 24)
  cfg.loadTimingRetardDeg = safeNumber(jbeamData.loadTimingRetardDeg, 10)
  cfg.hotAirTimingRetardPerC = safeNumber(jbeamData.hotAirTimingRetardPerC, 0.05)
  cfg.timingToleranceDeg = safeNumber(jbeamData.timingToleranceDeg, 8)

  cfg.valveTrainExpansionMMPerC = safeNumber(jbeamData.valveTrainExpansionMMPerC, 0.0012)
  cfg.minHotValveLashMM = safeNumber(jbeamData.minHotValveLashMM, 0.025)
  cfg.maxValveLashMM = safeNumber(jbeamData.maxValveLashMM, 0.55)
  cfg.referenceCompressionRatio = safeNumber(jbeamData.referenceCompressionRatio, cfg.fuelingMode == "diesel" and 17.5 or 9.5)
  cfg.pistonOptimalTempC = safeNumber(jbeamData.pistonOptimalTempC, 105)
  cfg.oilOptimalTempC = safeNumber(jbeamData.oilOptimalTempC, 90)
  cfg.pistonSeizureTempC = safeNumber(jbeamData.pistonSeizureTempC, 285)
  cfg.coldPistonLoss = safeNumber(jbeamData.coldPistonLoss, 0.075)
  cfg.coldOilFrictionLoss = safeNumber(jbeamData.coldOilFrictionLoss, 0.10)
  cfg.hotPistonLoss = safeNumber(jbeamData.hotPistonLoss, 0.48)

  cfg.startupProtectionSeconds = safeNumber(jbeamData.startupProtectionSeconds, 6.0)
  cfg.startMinTorqueFactor = safeNumber(jbeamData.startMinTorqueFactor, 0.94)
  cfg.idleStallGuardMinTorque = safeNumber(jbeamData.idleStallGuardMinTorque, 0.88)
  cfg.idleCircuitFuelMult = safeNumber(jbeamData.idleCircuitFuelMult, 0.12)
  cfg.loadProportionalEngineEffect = bool(jbeamData.loadProportionalEngineEffect, true)
  cfg.loadProportionalEngineEffectGain = safeNumber(jbeamData.loadProportionalEngineEffectGain, 1.42)
  cfg.carbPartialRestrictionStart = safeNumber(jbeamData.carbPartialRestrictionStart, 0.48)
  cfg.carbFlowCalibrationCoef = safeNumber(jbeamData.carbFlowCalibrationCoef, 0.80)
  cfg.multiCarbFlowBonus = safeNumber(jbeamData.multiCarbFlowBonus, 1.08)
  cfg.minBreathingVECoef = safeNumber(jbeamData.minBreathingVECoef, 0.78)
  cfg.maxBreathingCapacityCoef = safeNumber(jbeamData.maxBreathingCapacityCoef, 1.14)
  cfg.maxBreathingTorqueBonus = safeNumber(jbeamData.maxBreathingTorqueBonus, 1.08)
  cfg.densityTorqueWeight = safeNumber(jbeamData.densityTorqueWeight, 0.35)
  cfg.intakeOptimalTempC = safeNumber(jbeamData.intakeOptimalTempC, 32)
  cfg.intakeTempSpreadC = safeNumber(jbeamData.intakeTempSpreadC, 18)
  cfg.suppressFalseStallUI = bool(jbeamData.suppressFalseStallUI, true)
  cfg.startFailureSuppression = safeNumber(jbeamData.startFailureSuppression, 0.75)
  cfg.stallDelaySeconds = safeNumber(jbeamData.stallDelaySeconds, 2.5)
  cfg.frictionPenaltyNm = safeNumber(jbeamData.frictionPenaltyNm, 38)
  cfg.dynamicFrictionPenalty = safeNumber(jbeamData.dynamicFrictionPenalty, 0.010)

  cfg.suspensionAffectsGrip = bool(jbeamData.suspensionAffectsGrip, true)
  cfg.enableSuspensionBeamEffects = bool(jbeamData.enableSuspensionBeamEffects, false)
  cfg.damperFadeStartC = safeNumber(jbeamData.damperFadeStartC, 95)
  cfg.damperFadeEndC = safeNumber(jbeamData.damperFadeEndC, 175)
  cfg.damperMinCoef = safeNumber(jbeamData.damperMinCoef, 0.58)
  cfg.springMinCoef = safeNumber(jbeamData.springMinCoef, 0.92)
  cfg.suspensionApplyInterval = safeNumber(jbeamData.suspensionApplyInterval, 0.20)
  cfg.cgHeightM = safeNumber(jbeamData.cgHeightM, 0.55)
  cfg.trackWidthM = safeNumber(jbeamData.trackWidthM, 1.55)
  cfg.wheelbaseM = safeNumber(jbeamData.wheelbaseM, 2.60)
  cfg.steeringToLateralG = safeNumber(jbeamData.steeringToLateralG, 0.82)
  cfg.throttleToLongG = safeNumber(jbeamData.throttleToLongG, 0.42)
  cfg.brakeToLongG = safeNumber(jbeamData.brakeToLongG, 0.95)

  math.randomseed(os.time() % 2147483647)
  reset()
  log("I", "UltraRealismEngine", string.format(
    "controller initialized v%s (debugLog=%s diagnosticLog=%s integration=%s)",
    MOD_VERSION,
    cfg.debugLog and "on" or "off",
    cfg.diagnosticLog and "on" or "off",
    getIntegrationMode()
  ))
end

local function onReset()
  reset()
end

M.init = init
M.reset = reset
M.onReset = onReset
M.updateGFX = update
M.update = updatePhysics
M.updateWheelsIntermediate = updateWheelsIntermediate

return M
