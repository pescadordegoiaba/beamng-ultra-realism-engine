--[[
Tracks which torque/heuristic categories are owned by native-synced pack parts.
When a category is owned, the controller skips duplicate heuristic adjustments
because the forked engine already applies torqueModUltra* curves from JBeam.
]]

local M = {}

local CATEGORY_KEYS = {
  ultra_realism_intake_geometry = true,
  ultra_realism_carb_spacer = true,
  ultra_realism_short_block = true,
  ultra_realism_stroker_kit = true,
  ultra_realism_pistons = true,
  ultra_realism_piston_rings = true,
  ultra_realism_camshaft = true,
  ultra_realism_valvetrain = true,
  ultra_realism_cylinder_heads = true,
  ultra_realism_ignition = true,
  ultra_realism_carburetor = true,
}

local owned = {}

local function clamp(x, lo, hi)
  x = tonumber(x) or lo
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function categoryForEntry(entry)
  if type(entry) ~= "table" then return nil end
  local data = entry.data or entry
  local partData = type(data) == "table" and data or nil
  if not partData then return nil end
  if type(partData.ultraRealismCategory) == "string" then
    return partData.ultraRealismCategory
  end
  if type(partData.slotType) == "string" and CATEGORY_KEYS[partData.slotType] then
    return partData.slotType
  end
  return nil
end

function M.reset()
  owned = {}
end

function M.refresh(entries, usesNativeSync)
  owned = {}
  if not usesNativeSync or type(entries) ~= "table" then
    return owned
  end

  for _, entry in ipairs(entries) do
    local partData = entry.data
    if type(partData) == "table" and type(partData.ultraRealismNativeSync) == "table" then
      local category = categoryForEntry(entry)
      if category then
        owned[category] = true
      end
    end
  end
  return owned
end

function M.owns(category)
  return owned[category] == true
end

function M.anyOwned()
  return next(owned) ~= nil
end

function M.getOwned()
  return owned
end

function M.shouldSkipHeuristic(category, usesNativeSync)
  if not usesNativeSync then return false end
  return owned[category] == true
end

function M.heuristicWeight(category, usesNativeSync)
  if M.shouldSkipHeuristic(category, usesNativeSync) then
    return 0
  end
  return 1
end

return M