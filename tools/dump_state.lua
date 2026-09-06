-- Serialise emu.getState() so the real PPU configuration can be inspected
-- instead of inferred.

local OUT = "C:/famidash-snes-port/out/"
local AT_FRAME = 240
local frames = 0

local function dump(f, t, prefix, depth)
  if depth > 3 then return end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = t[k] ~= nil and t[k] or t[tonumber(k)]
    if type(v) == "table" then
      dump(f, v, prefix .. k .. ".", depth + 1)
    elseif type(v) ~= "function" then
      f:write(prefix .. k .. " = " .. tostring(v) .. "\n")
    end
  end
end

local function onFrame()
  frames = frames + 1
  if frames ~= AT_FRAME then return end
  local f = io.open(OUT .. "ppu_state.txt", "w")
  local ok, st = pcall(emu.getState)
  if ok and type(st) == "table" then
    dump(f, st, "", 0)
  else
    f:write("getState failed: " .. tostring(st) .. "\n")
  end
  f:close()
  emu.stop(0)
end

emu.addEventCallback(onFrame, emu.eventType.startFrame)
