-- Where does a game frame actually go?
--
-- Hooks the entry of every per-frame function and logs the scanline it is
-- reached on. One SNES frame is 262 scanlines; vblank starts at 225. A game
-- frame that crosses 262 has overrun, and ppu_wait_nmi() then waits for the
-- NEXT vblank - which is the lag frame.
--
-- Entry hooks give a timeline, not a call-tree profile: the gap between two
-- consecutive marks is the time spent in whatever ran between them.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")

-- Order matters only for reading the output; the marks are timestamped.
local WATCH = {
  "ppu_wait_nmi", "music_update", "sprite_collide", "check_spr_objects",
  "oam_clear", "draw_screen", "draw_sprites", "drawplayerone",
  "oam_meta_spr", "oam_spr", "everything_else",
}

local FIRST, LAST = 300, 306      -- frames to log the timeline for

local marks, counts = {}, {}
local frame = 0

local function clock()
  local st = emu.getState()
  -- Flat table with dotted keys - st.ppu.scanline raises inside the callback
  -- and --testrunner swallows it (docs/HANDOFF.md trap 32).
  return st["ppu.scanline"], st["ppu.cycle"]
end

for _, name in ipairs(WATCH) do
  local addr = A.code[name]
  if addr then
    emu.addMemoryCallback(function()
      counts[name] = (counts[name] or 0) + 1
      if frame >= FIRST and frame <= LAST then
        local sl = clock()
        marks[#marks + 1] = string.format("  f%-4d sl%-4d %s", frame, sl, name)
      end
    end, emu.callbackType.exec, addr, addr)
  end
end

local rows = {}
local function onFrame()
  frame = frame + 1
  if frame == LAST + 1 then
    rows[#rows + 1] = "timeline (sl = scanline; vblank starts at 225, frame ends 262)"
    for _, m in ipairs(marks) do rows[#rows + 1] = m end
  end
  if frame == 900 then
    rows[#rows + 1] = ""
    rows[#rows + 1] = string.format("call counts over %d video frames:", frame)
    local names = {}
    for n in pairs(counts) do names[#names + 1] = n end
    table.sort(names, function(a, b) return counts[a] > counts[b] end)
    for _, n in ipairs(names) do
      rows[#rows + 1] = string.format("  %-20s %6d   (%.1f per video frame)",
        n, counts[n], counts[n] / frame)
    end
    local f = io.open(OUT .. "frame_profile.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end
emu.addEventCallback(onFrame, emu.eventType.startFrame)
