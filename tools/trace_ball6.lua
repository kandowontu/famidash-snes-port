-- Every writer of the ball's y and vel_y, by PC, across one bounce.
--
-- trace_ball5 showed bg_coll_return_D running only once every ~14 frames, and
-- the ball moving several pixels UP on the frame it does - which ball_eject
-- cannot do with eject_D = 0. So something else writes currplayer_y. This names
-- it. (The callback form is the one tools/probe_memcb.lua established fires:
-- the CPU bus at $7Exxxx, four arguments.)
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)

local WR = emu.memType.snesWorkRam
local START = 240
local FROM, LAST = 250, 258

local function rd(a) return emu.read(a, WR, false) end
local function u16(a) return rd(a) + 256 * rd(a + 1) end
local function u32(a) return u16(a) + 65536 * u16(a + 2) end
local function s16(a)
  local v = u16(a); if v >= 0x8000 then v = v - 0x10000 end; return v
end
local function wr16(a, v)
  emu.write(a, v & 0xFF, WR); emu.write(a + 1, (v >> 8) & 0xFF, WR)
end

local frame, rows, armed = 0, {}, false
local froze_x, froze_scroll

emu.addMemoryCallback(function()
  emu.write(A.cube_data, rd(A.cube_data) & 0xFE, WR)
  emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, WR)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

-- pc -> nearest preceding code symbol, so the report names a function.
local syms = {}
for name, addr in pairs(A.code) do syms[#syms + 1] = { name = name, addr = addr } end
table.sort(syms, function(a, b) return a.addr < b.addr end)
local function where(pc)
  local best
  for _, s in ipairs(syms) do
    if s.addr <= pc then best = s else break end
  end
  if not best then return string.format("%06X", pc) end
  return string.format("%s+%X", best.name, pc - best.addr)
end

local function watch(label, addr, width)
  emu.addMemoryCallback(function(a, v)
    if not armed then return end
    -- emu.getState() returns a FLAT table with dotted keys ("cpu.pc"), not a
    -- nested one. s.cpu.pc raises "index a nil value (field 'cpu')", and an
    -- error inside a memory callback kills that callback SILENTLY - which
    -- reads as "nothing ever writes this address". See tools/probe_memcb.lua.
    local s = emu.getState()
    rows[#rows + 1] = string.format("      %-6s [%04X]=%02X  from %s",
                                    label, a - 0x7E0000, v,
                                    where((s["cpu.k"] << 16) | s["cpu.pc"]))
  end, emu.callbackType.write, 0x7E0000 + addr, 0x7E0000 + addr + width - 1)
end

watch("y",   A.currplayer_y,     2)
watch("vel", A.currplayer_vel_y, 2)

emu.addEventCallback(function()
  if not menu.done() then return end
  frame = frame + 1
  if frame < START then return end
  emu.write(A.gamemode, 0x02, WR)
  if not froze_x then
    froze_x, froze_scroll = u16(A.currplayer_x), u32(A.scroll_x)
  end
  wr16(A.currplayer_x, froze_x)
  wr16(A.scroll_x, froze_scroll & 0xFFFF)
  wr16(A.scroll_x + 2, (froze_scroll >> 16) & 0xFFFF)
  armed = frame >= FROM
  if not armed then return end

  rows[#rows + 1] = string.format("f%4d y=%04X vel=%+6d ejD=%02X",
                                  frame, u16(A.currplayer_y),
                                  s16(A.currplayer_vel_y), rd(A.eject_D))
  if frame >= LAST then
    local f = io.open(OUT .. "ball_trace6.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end, emu.eventType.startFrame)
