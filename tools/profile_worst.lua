-- The slowest game frames in a window, with where their time went.
--
-- Sampling a fixed window profiles whatever happened to be there; the frames
-- that actually drop are rare and need finding. This times every game frame on
-- a monotonic scanline clock, keeps the worst, and prints the phase splits for
-- those only.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
-- Gameplay, not the level select. main() opens the menu first now, and a
-- script that does not get past it measures a menu - or, worse, writes no
-- report at all and leaves the PREVIOUS run's file to be read as this one's
-- (docs/HANDOFF.md trap 89).
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local FIRST, LAST = 1400, 1700
local KEEP = 8

local PHASES = {
  "music_update", "sprite_collide", "check_spr_objects", "oam_clear",
  "draw_screen", "draw_sprites", "trail_loop", "ppu_wait_nmi",
}

-- Gameplay input only AFTER the menu. A is also "select this level", so a
-- script that holds it from frame 1 races the level select - and whichever wins
-- depends on when the menu happens to appear, which a compiler flag can move.
-- That is how every scripted run silently played level 0 (docs/HANDOFF.md
-- trap 114).
emu.addEventCallback(function()
  if not menu.done() then return end
  emu.setInput({ a = true }, 0)
end, emu.eventType.inputPolled)
-- STRESS_SLOTS forces N active-sprite slots on (see tools/stress_sprites.lua),
-- so the phase splits can be read at a sprite load the level never reaches.
local STRESS = tonumber(os.getenv("STRESS_SLOTS") or "") or 0
emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
  emu.write(A.cube_data + 1, emu.read(A.cube_data + 1, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
  for i = 0, STRESS - 1 do
    emu.write(A.activesprites_active + i, 1, emu.memType.snesWorkRam)
    emu.write(A.activesprites_realx + i, 16 + (i * 14) % 224, emu.memType.snesWorkRam)
    emu.write(A.activesprites_realy + i, 24 + (i * 11) % 160, emu.memType.snesWorkRam)
  end
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local frames = 0
local function clock()   -- monotonic scanlines since boot
  return frames * 262 + emu.getState()["ppu.scanline"]
end

local cur, worst = nil, {}
for _, name in ipairs(PHASES) do
  local addr = A.code[name]
  if addr then
    emu.addMemoryCallback(function()
      if frames < FIRST or frames > LAST then return end
      local t = clock()
      if name == "music_update" then
        -- music_update is the first thing everything_else does: a new game frame.
        if cur then
          cur.total = t - cur.start
          worst[#worst + 1] = cur
        end
        cur = { start = t, marks = {}, frame = frames }
      end
      if cur then cur.marks[#cur.marks + 1] = { name, t - cur.start } end
    end, emu.callbackType.exec, addr, addr)
  end
end

emu.addEventCallback(function()
  frames = frames + 1
  if frames == LAST + 1 then
    table.sort(worst, function(a, b) return (a.total or 0) > (b.total or 0) end)
    local rows = { string.format(
      "slowest game frames in video frames %d-%d (262 scanlines = one frame):",
      FIRST, LAST) }
    for i = 1, math.min(KEEP, #worst) do
      local w = worst[i]
      local parts = {}
      for j = 1, #w.marks do
        local nxt = w.marks[j + 1]
        local dur = (nxt and nxt[2] or w.total) - w.marks[j][2]
        parts[#parts + 1] = string.format("%s %d", w.marks[j][1], dur)
      end
      rows[#rows + 1] = string.format("  frame %d: %d scanlines%s", w.frame,
        w.total, w.total > 262 and "  <-- DROPPED A FRAME" or "")
      rows[#rows + 1] = "      " .. table.concat(parts, " | ")
    end
    local f = io.open(OUT .. "worst_frames.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end, emu.eventType.startFrame)
