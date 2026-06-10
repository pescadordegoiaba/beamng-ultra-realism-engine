--[[
Runtime aggregation of torqueModUltra* curves from active ultra_realism parts.
Supplements fork init curves when the player swaps parts without respawning.
]]

local M = {}

local MULT_KEYS = {
  "torqueModUltraIntakeMult",
  "torqueModUltraSpacerMult",
  "torqueModUltraStrokerMult",
  "torqueModUltraPistonsMult",
  "torqueModUltraRingsMult",
  "torqueModUltraCamshaftMult",
  "torqueModUltraValvetrainMult",
  "torqueModUltraHeadsMult",
}

local ADDITIVE_KEY = "torqueModUltraIgnition"

local curves = {}
local ignitionCurve = {}
local signature = ""

local function clamp(x, lo, hi)
  x = tonumber(x) or lo
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function parseCurveTable(raw)
  if type(raw) ~= "table" then return nil end
  local points = {}
  for _, row in pairs(raw) do
    if type(row) == "table" then
      local rpm = tonumber(row[1] or row.rpm)
      local value = tonumber(row[2] or row.torque)
      if rpm and value then
        points[#points + 1] = {rpm = rpm, value = value}
      end
    end
  end
  if #points == 0 then return nil end
  table.sort(points, function(a, b) return a.rpm < b.rpm end)
  return points
end

local function sampleCurve(points, rpm)
  if not points or #points == 0 then return 1 end
  rpm = clamp(rpm, 0, 20000)
  if rpm <= points[1].rpm then return points[1].value end
  if rpm >= points[#points].rpm then return points[#points].value end
  for i = 1, #points - 1 do
    local a, b = points[i], points[i + 1]
    if rpm >= a.rpm and rpm <= b.rpm then
      local t = (rpm - a.rpm) / math.max(b.rpm - a.rpm, 1)
      return a.value + (b.value - a.value) * t
    end
  end
  return points[#points].value
end

local function mergeMultiply(existing, incoming)
  if not incoming then return existing end
  if not existing then return incoming end
  local merged = {}
  local rpmSet = {}
  for _, pt in ipairs(existing) do rpmSet[pt.rpm] = true end
  for _, pt in ipairs(incoming) do rpmSet[pt.rpm] = true end
  local rpms = {}
  for rpm in pairs(rpmSet) do rpms[#rpms + 1] = rpm end
  table.sort(rpms)
  for _, rpm in ipairs(rpms) do
    merged[#merged + 1] = {
      rpm = rpm,
      value = sampleCurve(existing, rpm) * sampleCurve(incoming, rpm),
    }
  end
  return merged
end

local function mergeAdd(existing, incoming)
  if not incoming then return existing end
  if not existing then return incoming end
  local merged = {}
  local rpmSet = {}
  for _, pt in ipairs(existing) do rpmSet[pt.rpm] = true end
  for _, pt in ipairs(incoming) do rpmSet[pt.rpm] = true end
  local rpms = {}
  for rpm in pairs(rpmSet) do rpms[#rpms + 1] = rpm end
  table.sort(rpms)
  for _, rpm in ipairs(rpms) do
    merged[#merged + 1] = {
      rpm = rpm,
      value = sampleCurve(existing, rpm) + sampleCurve(incoming, rpm),
    }
  end
  return merged
end

local function shouldIncludePart(partData)
  if type(partData) ~= "table" then return false end
  return type(partData.ultraRealismNativeSync) ~= "table"
end

function M.reset()
  curves = {}
  ignitionCurve = {}
  signature = ""
end

function M.refresh(entries, _ownership)
  curves = {}
  ignitionCurve = {}
  local chunks = {}
  if type(entries) ~= "table" then
    signature = ""
    return 1
  end

  for _, entry in ipairs(entries) do
    local partName = entry.name
    local partData = entry.data
    if shouldIncludePart(partData) then
      local mainEngine = partData.mainEngine
      if type(mainEngine) == "table" then
        for _, key in ipairs(MULT_KEYS) do
          local parsed = parseCurveTable(mainEngine[key])
          if parsed then
            curves[key] = mergeMultiply(curves[key], parsed)
            chunks[#chunks + 1] = tostring(partName) .. ":" .. key
          end
        end
        local ignition = parseCurveTable(mainEngine[ADDITIVE_KEY])
        if ignition then
          ignitionCurve = mergeAdd(ignitionCurve, ignition)
          chunks[#chunks + 1] = tostring(partName) .. ":" .. ADDITIVE_KEY
        end
      end
    end
  end

  table.sort(chunks)
  signature = table.concat(chunks, "|")
  return M.multAtRPM(3000)
end

function M.multAtRPM(rpm)
  rpm = clamp(rpm or 3000, 0, 20000)
  local mult = 1
  for _, key in ipairs(MULT_KEYS) do
    local curve = curves[key]
    if curve then
      mult = mult * clamp(sampleCurve(curve, rpm), 0.5, 1.5)
    end
  end
  local add = 0
  if ignitionCurve and #ignitionCurve > 0 then
    add = sampleCurve(ignitionCurve, rpm)
  end
  if add ~= 0 and mult > 0 then
    mult = mult * clamp(1 + add / 1000, 0.85, 1.15)
  end
  return clamp(mult, 0.5, 1.5)
end

function M.getSignature()
  return signature
end

return M