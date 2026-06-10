--[[
Lightweight event bus for modular ultra realism subsystems.
]]

local M = {}

local listeners = {}

function M.reset()
  listeners = {}
end

function M.subscribe(event, callback)
  event = tostring(event or "")
  if event == "" or type(callback) ~= "function" then return end
  listeners[event] = listeners[event] or {}
  listeners[event][#listeners[event] + 1] = callback
end

function M.publish(event, payload)
  event = tostring(event or "")
  local subs = listeners[event]
  if not subs then return payload end
  for _, callback in ipairs(subs) do
    local ok, result = pcall(callback, payload)
    if ok and result ~= nil then
      payload = result
    end
  end
  return payload
end

return M