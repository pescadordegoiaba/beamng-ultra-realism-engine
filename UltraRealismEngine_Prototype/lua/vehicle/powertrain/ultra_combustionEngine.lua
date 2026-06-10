--[[
Ultra Realism powertrain entry point.

Routes to full URE forks (not vanilla engines):
  - CEEP  -> ultra_classic_combustionEngine (fork of classic_combustionEngine)
  - Ford  -> ultra_stock_combustionEngine (fork of combustionEngine)
  - stock -> ultra_stock_combustionEngine

Forks integrate torque, fuel consumption and stall via ultra_combustionEngineIntegration.
]]

local M = {}

M.outputPorts = {[1] = true}
M.deviceCategories = {engine = true}

local function lower(v)
  return string.lower(tostring(v or ""))
end

local function resolveProfile(jbeamData)
  local profile = lower(jbeamData.ureEngineProfile or jbeamData.urePackMode or "auto")
  if profile == "ceep" or profile == "ford" or profile == "stock" then
    return profile
  end

  local vehicleDir = lower(v and v.vehicleDirectory or "")
  if vehicleDir:find("ceep", 1, true) or vehicleDir:find("classic_engine", 1, true) then
    return "ceep"
  end
  if vehicleDir:find("ford_engine", 1, true) or vehicleDir:find("jitter", 1, true) then
    return "ford"
  end
  return "stock"
end

local function resolveBackendModule(profile)
  if profile == "ceep" then
    return "powertrain/ultra_classic_combustionEngine", "ceep"
  end
  return "powertrain/ultra_stock_combustionEngine", profile == "ford" and "ford" or "stock"
end

local function new(jbeamData)
  jbeamData = jbeamData or {}
  local profile = resolveProfile(jbeamData)
  jbeamData.ureEngineProfile = profile

  local backendPath, resolvedProfile = resolveBackendModule(profile)
  local ok, backend = pcall(rerequire, backendPath)
  if not ok or not backend or not backend.new then
    log("E", "ultra_combustionEngine", "URE fork missing at " .. tostring(backendPath))
    error("Ultra Realism engine fork unavailable: " .. tostring(backendPath))
  end

  local device = backend.new(jbeamData)
  device.ureUltraEngine = true
  device.ureEngineProfile = resolvedProfile

  if electrics and electrics.values then
    electrics.values.ure_ultraEngineActive = 1
    electrics.values.ure_engineProfile = resolvedProfile
    electrics.values.ure_integratedFuel = 1
  end

  log("I", "ultra_combustionEngine", string.format(
    "URE fork active profile=%s backend=%s device=%s",
    resolvedProfile,
    backendPath,
    tostring(device.name)
  ))

  return device
end

M.new = new

return M