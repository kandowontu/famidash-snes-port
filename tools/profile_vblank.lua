-- Split the vblank flush.
--
-- ppu_wait_nmi returns at scanline 225 and the game's next call (music_update)
-- is reached at scanline 1 of the following frame - so the flush is using all
-- 37 scanlines of vblank and spilling into active display, where VRAM writes
-- are silently dropped (docs/HANDOFF.md trap 35). This says which part.
--
-- pad_poll is the only sub-step with a linker symbol; the rest is bracketed by
-- watching the register writes each stage makes: CGADD for the palette,
-- VMADDL for VRAM/columns, OAMADDL for the sprite DMA.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
-- Gameplay, not the level select. main() opens the menu first now, and a
-- script that does not get past it measures a menu - or, worse, writes no
-- report at all and leaves the PREVIOUS run's file to be read as this one's
-- (docs/HANDOFF.md trap 89).
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
menu.start(tonumber(os.getenv("LEVEL")) or 0)
local FIRST, LAST = 1200, 1208

-- Gameplay input only AFTER the menu. A is also "select this level", so a
-- script that holds it from frame 1 races the level select - and whichever wins
-- depends on when the menu happens to appear, which a compiler flag can move.
-- That is how every scripted run silently played level 0 (docs/HANDOFF.md
-- trap 114).
emu.addEventCallback(function()
  if not menu.done() then return end
  emu.setInput({ a = true }, 0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  emu.write(A.cube_data, emu.read(A.cube_data, emu.memType.snesWorkRam) & 0xFE,
            emu.memType.snesWorkRam)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local frame, marks = 0, {}
local function mark(what)
  if frame >= FIRST and frame <= LAST then
    local n = #marks
    -- Collapse runs of the same stage; only the first and last matter.
    if n > 0 and marks[n].what == what and marks[n].frame == frame then
      marks[n].last = emu.getState()["ppu.scanline"]
      marks[n].count = marks[n].count + 1
    else
      local sl = emu.getState()["ppu.scanline"]
      marks[n + 1] = { frame = frame, what = what, first = sl, last = sl, count = 1 }
    end
  end
end

for _, r in ipairs({
  { 0x2121, "cgram_flush (CGADD)" },
  { 0x2116, "vram/column   (VMADDL)" },
  { 0x2102, "oam_flush     (OAMADDL)" },
  { 0x420B, "DMA start     (MDMAEN)" },
}) do
  emu.addMemoryCallback(function() mark(r[2]) end, emu.callbackType.write,
                        r[1], r[1], emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addMemoryCallback(function() mark("pad_poll") end, emu.callbackType.exec,
                      A.code.pad_poll, A.code.pad_poll)
emu.addMemoryCallback(function() mark("== game code resumes") end,
                      emu.callbackType.exec, A.code.music_update, A.code.music_update)
emu.addMemoryCallback(function() mark("-- ppu_wait_nmi entered") end,
                      emu.callbackType.exec, A.code.ppu_wait_nmi, A.code.ppu_wait_nmi)

emu.addEventCallback(function()
  frame = frame + 1
  if frame == LAST + 1 then
    local rows = { "vblank starts at scanline 225, frame ends at 262" }
    for _, m in ipairs(marks) do
      rows[#rows + 1] = string.format("  f%-5d sl%3d..%-3d  x%-4d %s",
        m.frame, m.first, m.last, m.count, m.what)
    end
    local f = io.open(OUT .. "vblank_profile.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end, emu.eventType.startFrame)
