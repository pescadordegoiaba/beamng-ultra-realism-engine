--[[
Ultra Realism powertrain wrapper.

Detects CEEP / Ford engine profiles and delegates to the correct native backend:
  - CEEP  -> classic_combustionEngine (from CEEP pack)
  - Ford  -> combustionEngine (stock BeamNG)
  - other -> combustionEngine

When the profile is CEEP or Ford, hooks torque application and stall guard via
ultraRealismEngineBridge so the modified behaviour runs inside powertrain.update.
]]

local M = {}

M.outputPorts = {[1] = true}
M.deviceCategories = {engine = true}

local function getBridge()
  return rerequire("powertrain/ultraRealismEngineBridge")
end

local function lower(v)
  return string.lower(tostring(v or ""))
end

local function backendExists(name)
  if name == "combustionEngine" then return true end
  local path = "lua/vehicle/powertrain/" .. name .. ".lua"
  if not FS or not FS.fileExists then return false end
  local ok, exists = pcall(function() return FS:fileExists(path) end)
  if ok then return exists end
  ok, exists = pcall(function() return FS.fileExists(path) end)
  if ok then return exists end
  return false
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

  if backendExists("classic_combustionEngine") then
    local partsText = ""
    if v and v.data and type(v.data.parts) == "table" then
      for partName in pairs(v.data.parts) do
        partsText = partsText .. " " .. lower(partName)
      end
    end
    if partsText:find("ceep", 1, true) or partsText:find("classic_engine", 1, true) then
      return "ceep"
    end
  end

  return "stock"
end

local function resolveBackendModule(profile)
  if profile == "ceep" then
    if backendExists("classic_combustionEngine") then
      return "powertrain/classic_combustionEngine", "ceep"
    end
    log("W", "ultra_combustionEngine", "classic_combustionEngine missing; CEEP profile uses combustionEngine fallback")
    return "powertrain/combustionEngine", "ceep"
  end
  if profile == "ford" then
    return "powertrain/combustionEngine", "ford"
  end
  return "powertrain/combustionEngine", "stock"
end

local function wrapUltraDevice(device, profile)
  device.ureUltraEngine = true
  device.ureEngineProfile = profile
  getBridge().registerDevice(device.name, device, profile)

  local origTorqueUpdate = device.torqueUpdate
  if origTorqueUpdate then
    device.torqueUpdate = function(self, dt)
      getBridge().applyTorqueToDevice(self)
      return origTorqueUpdate(self, dt)
    end
  end

  local origUpdateGFX = device.updateGFX
  if origUpdateGFX then
    device.updateGFX = function(self, dt)
      origUpdateGFX(self, dt)
      getBridge().postUpdateGFXStallGuard(self)
    end
  end

  local origReset = device.reset
  device.reset = function(self, ...)
    if origReset then origReset(self, ...) end
    getBridge().registerDevice(self.name, self, profile)
  end

  return device
end

local function new(jbeamData)
  local profile = resolveProfile(jbeamData or {})
  local backendPath, resolvedProfile = resolveBackendModule(profile)
  local ok, backend = pcall(rerequire, backendPath)
  if not ok or not backend or not backend.new then
    log("W", "ultra_combustionEngine", "Backend unavailable at " .. tostring(backendPath) .. ", using combustionEngine")
    backend = rerequire("powertrain/combustionEngine")
    resolvedProfile = "stock"
  end

  local device = backend.new(jbeamData)
  if resolvedProfile == "ceep" or resolvedProfile == "ford" then
    device = wrapUltraDevice(device, resolvedProfile)
    log("I", "ultra_combustionEngine", string.format(
      "Ultra engine active profile=%s backend=%s device=%s",
      resolvedProfile,
      backendPath,
      tostring(device.name)
    ))
  else
    device.ureUltraEngine = false
    device.ureEngineProfile = "stock"
    log("I", "ultra_combustionEngine", "Stock combustion backend (no CEEP/Ford profile detected)")
  end

  if electrics and electrics.values then
    electrics.values.ure_ultraEngineActive = device.ureUltraEngine and 1 or 0
    electrics.values.ure_engineProfile = resolvedProfile
  end

  return device
end

M.new = new

return M