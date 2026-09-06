-- Which addMemoryCallback form actually fires for a work-RAM write?
--
-- Three variants failed silently in a row while looking for the writer that
-- moves the ball, so establish the binding before trusting any trace built on
-- it. Writes a report naming the forms that fired.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(0)

local hits, gated = {}, false
local function form(name, ...)
  local ok, err = pcall(emu.addMemoryCallback, function()
    if not gated then return end
    hits[name] = (hits[name] or 0) + 1
  end, ...)
  if not ok then hits[name] = "ERROR: " .. tostring(err) end
end

local Y = A.currplayer_y
form("A: cpu bus 7E+addr, 4 args", emu.callbackType.write, 0x7E0000 + Y, 0x7E0000 + Y + 1)
form("B: workram, 6 args cpuType.snes", emu.callbackType.write, Y, Y + 1,
     emu.cpuType.snes, emu.memType.snesWorkRam)
form("C: workram, 6 args nil cpuType", emu.callbackType.write, Y, Y + 1,
     nil, emu.memType.snesWorkRam)
form("D: workram, 4 args", emu.callbackType.write, Y, Y + 1)

-- Does calling emu.getState() from inside a memory callback survive? Three
-- traces that needed the PC produced no rows at all, which is what a silently
-- killed callback looks like.
local st_err
emu.addMemoryCallback(function()
  if not gated then return end
  local ok, err = pcall(function()
    local s = emu.getState()
    local _ = (s.cpu.k << 16) | s.cpu.pc
  end)
  if ok then hits["E: getState inside callback"] = (hits["E: getState inside callback"] or 0) + 1
  else
    st_err = tostring(err)
    local keys = {}
    local st = emu.getState()
    if type(st) == "table" then
      for k, v in pairs(st) do keys[#keys + 1] = k .. "=" .. type(v) end
    else keys[1] = "getState returned " .. type(st) end
    hits["E: getState inside callback"] = "ERROR " .. tostring(err)
      .. "  || keys: " .. table.concat(keys, ",")
  end
end, emu.callbackType.write, 0x7E0000 + Y, 0x7E0000 + Y + 1)

local n = 0
emu.addEventCallback(function()
  if not menu.done() then return end
  n = n + 1
  gated = n >= 200          -- gameplay only, past the init memset
  if n ~= 300 then return end
  local rows = {
    "cpuType.snes = " .. tostring(emu.cpuType and emu.cpuType.snes),
    "memType.snesWorkRam = " .. tostring(emu.memType.snesWorkRam),
    "memType.snesMemory = " .. tostring(emu.memType.snesMemory),
  }
  for k, v in pairs(hits) do rows[#rows + 1] = string.format("%-34s %s", k, tostring(v)) end
  if #rows == 3 then rows[#rows + 1] = "NO FORM FIRED" end
  local f = io.open(OUT .. "memcb_probe.txt", "w")
  f:write(table.concat(rows, "\n") .. "\n"); f:close()
  emu.stop(0)
end, emu.eventType.startFrame)
