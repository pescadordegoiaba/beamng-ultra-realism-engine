--[[
Minimal hook surface for URE combustion engine forks.
Integration layer may call these before/after native torque evaluation.
]]

local M = {}

function M.beforeTorqueCalc(device, ctx)
  ctx = ctx or {}
  if not device or not device.ureUltraEngine then return ctx end
  ctx.rpm = ctx.rpm or (device.outputAV1 and device.outputAV1 * 9.5493) or 0
  return ctx
end

function M.afterTorqueCalc(device, ctx, torque)
  if not device or not device.ureUltraEngine then return torque end
  return torque
end

function M.beforeFuelUsage(device, ctx)
  return ctx or {}
end

function M.afterFuelUsage(device, ctx, spentEnergy)
  return spentEnergy
end

return M