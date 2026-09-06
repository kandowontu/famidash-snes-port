-- How far does the real game get when it runs on the SA-1?
--
-- out/famidash-sa1-full.sfc is the full 168-level port relinked against the
-- SA-1 memory map: same ROM banks, but all ~38KB of state moved out of $7E/$7F
-- WRAM, which the SA-1 cannot see, and into I-RAM and BW-RAM. Nothing about the
-- PPU has been split yet, so this is not expected to draw anything. What it is
-- expected to do is boot, run the C runtime against BW-RAM, reach main(), and
-- then stop in ppu_wait_nmi() - which polls HVBJOY, a PPU register the SA-1
-- cannot read.
--
-- It does NOT stop there. ppu_wait_nmi polls HVBJOY, which for the SA-1 is open
-- bus, and open bus varies - so both its wait loops fall straight through and
-- the game runs free, unsynchronised and drawing nothing. That is the state
-- this checks for, and it is a better one than a park: the whole game loop is
-- executing on the SA-1.
--
-- Three things have to hold, because any one alone can pass on a dead ROM:
--   the SA-1's PC is spread across the game's own functions, not stuck in one;
--   BW-RAM holds initialised state, not one repeated byte;
--   drawing_frame is INCREMENTING, which is the only one that proves the loop
--   is going round rather than merely having started.
--
--   "C:/mesen2/Mesen.exe" --testrunner out/famidash-sa1-full.sfc tools/verify_sa1_game.lua

local OUT = "C:/famidash-snes-port/out/"

-- Code symbol addresses for THIS ROM. Generated, because they move whenever
-- anything is added: tools/gen_addrs.py --map out/game_sa1.map.
local addrs = dofile(OUT .. "addrs_sa1.lua")

-- Sorted symbol list, so a PC can be resolved to the function that contains it.
local syms = {}
for name, addr in pairs(addrs.code or addrs) do
  if type(addr) == "number" then syms[#syms + 1] = { name = name, addr = addr } end
end
table.sort(syms, function(a, b) return a.addr < b.addr end)

local function whereis(pc)
  local best
  for _, s in ipairs(syms) do
    if s.addr <= pc then best = s else break end
  end
  if not best then return string.format("$%06X (before any known symbol)", pc) end
  return string.format("%s+%d ($%06X)", best.name, pc - best.addr, pc)
end

-- drawing_frame is at the end of ppu_wait_nmi, so it advances once per game
-- frame and nowhere else.
-- gen_addrs.py puts the data symbols at the top level and the code symbols
-- under `code`, so this is addrs.drawing_frame, not addrs.wram.drawing_frame.
local FRAME_CTR = assert(addrs.drawing_frame, "no drawing_frame in addrs_sa1.lua")

local frames, seen = 0, {}
local SETTLE, TOTAL = 60, 180
local ctr_first, ctr_seen = nil, { n = 0, last = -1 }

emu.addEventCallback(function()
  frames = frames + 1
  local st = emu.getState()
  local pc = ((st["cart.coprocessor.cpu.k"] or 0) << 16)
             | (st["cart.coprocessor.cpu.pc"] or 0)
  seen[whereis(pc)] = (seen[whereis(pc)] or 0) + 1

  -- Count ADVANCES, not distinct values: the counter is a byte and wraps, so
  -- distinct-value counting saturates at 256 and undercounts a fast game.
  --
  -- And count them only after SETTLE. Boot - the level-select build and the
  -- first CHR uploads - completes very few frames, so a window that starts at
  -- power-on reports about a third of the steady-state rate. Measuring from
  -- frame 0 said 28% where the truth is 76%.
  local ctr = emu.read(FRAME_CTR, emu.memType.snesSaveRam, false)
  if frames > SETTLE then
    if ctr ~= ctr_seen.last then ctr_seen.n = ctr_seen.n + 1 end
  end
  ctr_seen.last = ctr

  if frames < TOTAL then return end

  local log = {}
  local function say(s) log[#log + 1] = s end

  say(string.format("S-CPU  $%02X:%04X", st["cpu.k"], st["cpu.pc"]))
  say("SA-1 sampled over " .. frames .. " frames:")
  local rows = {}
  for k, v in pairs(seen) do rows[#rows + 1] = { k = k, v = v } end
  table.sort(rows, function(a, b) return a.v > b.v end)
  for i = 1, math.min(#rows, 6) do
    say(string.format("  %4d  %s", rows[i].v, rows[i].k))
  end

  -- Sample actual linker-placed state symbols. The full build's live state now
  -- begins above $C000; the old fixed $2000-$9000 probe sampled only a cleared
  -- reserved region and falsely called a running ROM dead.
  local first, varied
  for name, addr in pairs(addrs) do
    if name ~= "code" and type(addr) == "number"
       and addr >= 0x2000 and addr < 0x10000 then
      local value = emu.read(addr, emu.memType.snesSaveRam, false)
      if first == nil then first = value
      elseif value ~= first then varied = true; break end
    end
  end
  say("BW-RAM holds initialised state: " .. tostring(varied))

  local nctr = ctr_seen.n
  say(string.format("drawing_frame advanced %d times in %d video frames after "
                    .. "boot settled (%.0f%% of 60Hz)",
                    nctr, TOTAL - SETTLE, 100 * nctr / (TOTAL - SETTLE)))

  -- "Spread" means more than a couple of distinct sites: a hung CPU samples to
  -- one or two, and a running game loop to many.
  local sites = 0
  for _ in pairs(seen) do sites = sites + 1 end
  say("SA-1 seen in " .. sites .. " distinct code sites")

  -- Three independent things, because any one alone passes on a broken ROM: the
  -- SA-1 is executing across the game rather than stuck; its state exists in
  -- BW-RAM; and frames COMPLETE, which only happens if the S-CPU is echoing the
  -- handshake. The third is the one the frame loop exists for - before it, the
  -- counter sat frozen while everything else looked healthy.
  local alive = sites > 3 and varied
  say("")
  if alive and nctr > 1 then
    say("RESULT OK - the game runs on the SA-1, its state is in BW-RAM, and the "
        .. "S-CPU handshake is pacing frames")
  elseif alive then
    say("RESULT FAIL - the SA-1 is running but no frame ever completes; it is "
        .. "spinning in ppu_wait_nmi waiting for an echo that is not coming")
  else
    say("RESULT FAIL - the game is not running on the SA-1 at all"
        .. " (sites=" .. sites .. " state=" .. tostring(varied) .. ")")
  end

  local f = io.open(OUT .. "sa1_game.txt", "w")
  f:write(table.concat(log, "\n") .. "\n")
  f:close()
  emu.stop(0)
end, emu.eventType.endFrame)
