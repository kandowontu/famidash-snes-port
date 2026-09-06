-- Does the level in $LEVEL load and stream, or does it only work for level 0?
--
-- Every other verifier plays stereomadness. 45 more levels went into the ROM at
-- once, each with its own height, its own LZ stream and its own sprite stream,
-- and the failure modes are per-level: a height the collision window cannot
-- hold, an LZ stream that decodes short, a metatile the tileset does not have.
-- None of those show up on level 0.
--
-- What counts as loaded:
--   * level_rle holds EXACTLY what the level's .lz inflates to,
--   * the streamed tilemap columns match the offline oracle, word for word,
--   * the game reaches STATE_GAME,
--   * rld_column advances, i.e. columns are actually being streamed,
--   * the player is on screen at the end of the window - a level that spawns
--     the player inside the ceiling resets forever and still "runs",
--   * the tilemap is not empty, which is what a level that decoded to nothing
--     would look like.
--
-- The first two are the point. This started as a LOADING test - does the level
-- draw something - and that is exactly the check that passed on all 46 levels
-- while the LZ decompressor was corrupting a few bytes of every one of them
-- (docs/HANDOFF.md trap 94). "It drew something" is not a correctness test.
-- The oracle comes from tools/gen_level_columns.py --all.
--
--   LEVEL=17 "C:/mesen2/Mesen.exe" --testrunner out/famidash-snes-full.sfc \
--            tools/verify_level_boot.lua
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
local LEVEL = tonumber(os.getenv("LEVEL") or "0")
menu.start(LEVEL)

local WR = emu.memType.snesWorkRam
local WINDOW = 360                      -- six seconds of play
local MAP_BASE = 0x6000
local ROWS = 64                         -- tile rows per column record
local HUD_ROW = 15                      -- the game's own "ATTEMPT n" overlay

local function slurp(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local d = fh:read("*a"); fh:close()
  return d
end

local rle_expect = slurp(OUT .. "rle_expect_" .. LEVEL .. ".bin")
local col_expect = slurp(OUT .. "level_expect_" .. LEVEL .. ".bin")
-- Which BG tileset and which two colours this level is supposed to have. Only
-- stereomadness's tileset was ever in the ROM, and the header's bg/ground
-- colours were never applied, so 36 of the 46 levels drew the right shapes from
-- the wrong art in the wrong colours - and every check passed.
local bg = dofile(OUT .. "bg_level_expect.lua")
local chr_expect = slurp(OUT .. "bgchr" .. bg.tileset[LEVEL + 1] .. ".bin")
local chr_alt_expect =
  slurp(OUT .. "bgchr_alt" .. bg.tileset[LEVEL + 1] .. ".bin")
if not rle_expect or not col_expect or not chr_expect or not chr_alt_expect then
  print(string.format("level %2d: FAIL - no oracle; run "
                      .. "python tools/gen_level_columns.py --all", LEVEL))
  emu.stop(1)
  return
end

local function rd(a) return emu.read(a, WR, false) end
local function rd16(a) return rd(a) + 256 * rd(a + 1) end

-- Hold A, plus RIGHT for the platformer levels, and clear the death flag every
-- frame before the draw.
--
-- The tower levels (22-25) are platformer levels: the camera does not scroll on
-- its own, the player walks. Holding A there streams eleven columns and stops,
-- which looks exactly like a level whose data ran out. RIGHT is harmless in the
-- auto-scrolling levels, which ignore it.
--
-- This is a LOADING test, not a play test. Holding A is not a run: level 1 dies
-- about four seconds in, which says nothing about whether its data decoded. The
-- other verifiers clear cube_data bit 0 the same way.
-- Gameplay input only AFTER the menu. A is also "select this level", so a
-- script that holds it from frame 1 races the level select - and whichever wins
-- depends on when the menu happens to appear, which a compiler flag can move.
-- That is how every scripted run silently played level 0 (docs/HANDOFF.md
-- trap 114).
emu.addEventCallback(function()
  if not menu.done() then return end
  emu.setInput({ a = true, right = true }, 0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  emu.write(A.cube_data, rd(A.cube_data) & 0xFE, WR)
  emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, WR)
end, emu.callbackType.exec, A.code.oam_clear, A.code.oam_clear)

local frames, cols, last_col = 0, 0, nil
local chr_bad, chr_first = 0, nil
local chr_alt_bad, chr_alt_first = 0, nil
local pal_bad, pal_first = 0, nil

-- The tileset is the level's STARTING state, so it is sampled as soon as the
-- level has loaded rather than at the end of the window. Two reasons a fixed
-- frame number does not work: the initial 256-column fill takes 45-90 frames
-- depending on the level's height, and Famidash changes the background colour
-- mid-level from triggers in the sprite stream. Checking late reported the
-- game's own colour change as a wrong palette, and checking early caught the
-- level select still on screen.
local sampled = false

-- The two header colours are checked at a DETERMINISTIC point: inside the level
-- load, on the call that follows set_level_colors.
--
-- They cannot be checked from a frame callback at all. Famidash changes the
-- background colour during play, from triggers in the level's own sprite
-- stream, and it does so here - so by the time any frame-based sample fires,
-- how many colour updates have run depends on how long that level took to load.
-- The header colours are the STARTING state and load_ground() is the last thing
-- init_rld does, so this reads them exactly once, in the right place.
-- PAL_BUF is what cgram_flush copies to CGRAM verbatim, so reading it here is
-- reading the palette without having to wait for a vblank.
-- Re-read on EVERY call, not just the first: load_ground also runs during the
-- boot before any level is selected, and latching there recorded the default
-- palette for every level. The last call before the window ends is the one that
-- belongs to the level under test.
local pal_checked = false
emu.addMemoryCallback(function()
  pal_checked = true
  pal_bad, pal_first = 0, nil
  for idx, want in pairs(bg.pal[LEVEL]) do
    local got = emu.read(A.PAL_BUF + idx * 2, emu.memType.snesWorkRam, false)
              + emu.read(A.PAL_BUF + idx * 2 + 1, emu.memType.snesWorkRam, false) * 256
    if got ~= want then
      pal_bad = pal_bad + 1
      pal_first = pal_first or string.format("entry %d is %04X, expected %04X",
                                             idx, got, want)
    end
  end
end, emu.callbackType.exec, A.code.load_ground, A.code.load_ground)

local function sample_appearance()
  for i = 0, #chr_expect - 1 do
    if emu.read(i, emu.memType.snesVideoRam, false) ~= chr_expect:byte(i + 1) then
      chr_bad = chr_bad + 1
      chr_first = chr_first or i
    end
    if emu.read(0x2000 + i, emu.memType.snesVideoRam, false)
        ~= chr_alt_expect:byte(i + 1) then
      chr_alt_bad = chr_alt_bad + 1
      chr_alt_first = chr_alt_first or i
    end
  end
end


emu.addEventCallback(function()
  if not menu.done() then return end
  frames = frames + 1

  -- Loaded = the renderer has started streaming AND the level select's palette
  -- is gone. Either alone is reached while the other is still true.
  if not sampled and rd16(A.rld_column) > 0 and rd(A.shim_chr_pending) == 0 then
    local c0 = emu.read(0, emu.memType.snesCgRam, false)
             + emu.read(1, emu.memType.snesCgRam, false) * 256
    -- shim_chr_pending matters as much as the other two: a 4KB tileset is two
    -- vblanks at the normal budget, and sampling in between reads half of it -
    -- the mismatch starts at byte 2048 on the dot.
    if c0 ~= 0x2000 then sampled = true; sample_appearance() end
  end

  local c = rd16(A.rld_column)
  if last_col and c ~= last_col then
    -- The cursor wraps within the 64-column map, so count changes, not deltas.
    cols = cols + 1
  end
  last_col = c

  if frames < WINDOW then return end

  -- Is anything on screen? A level that decoded to nothing leaves the tilemap
  -- as the cleared sky it was initialised to.
  local nonzero = 0
  for row = 0, 63 do
    local base = MAP_BASE + (row % 32) * 32 + ((row >= 32) and 0x800 or 0)
    for col = 0, 31, 4 do
      if emu.read((base + col) * 2, emu.memType.snesVideoRam, false) ~= 0 then
        nonzero = nonzero + 1
      end
    end
  end

  -- The inflated level, byte for byte. Everything downstream is built from
  -- this, so a wrong byte here is a wrong level however good the renderer is.
  local rle_len = rd16(A.level_rle_len)
  local rle_bad, rle_first = 0, nil
  if rle_len ~= #rle_expect then
    rle_bad = -1
  else
    for i = 0, rle_len - 1 do
      if rd(A.level_rle + i) ~= rle_expect:byte(i + 1) then
        rle_bad = rle_bad + 1
        rle_first = rle_first or i
      end
    end
  end

  -- The tilemap columns actually streamed, against the same oracle.
  local rld = rd16(A.rld_column)
  -- The window is rld-64 .. rld-2, which is 63 columns, not 64.
  --
  -- The map has 64 slots and column c lives in slot c%64, so column rld-65
  -- shares a slot with rld-1. Taking a full 64 columns therefore includes one
  -- whose slot has ALREADY been reused by the newest write - and whether that
  -- write has reached VRAM depends on the vblank, so the oldest column reads as
  -- itself or as its successor depending on timing. Reported as a renderer bug
  -- for a while; it is arithmetic.
  local newest = rld - 2                -- the newest may still be in flight
  local first = math.max(0, newest - 62)
  local col_bad, col_first, col_detail = 0, nil, ""
  for c = first, newest do
    local slot = c % 64
    local addr = MAP_BASE + (slot % 32) + (slot >= 32 and 0x400 or 0)
    local diff = {}
    for w = 0, ROWS - 1 do
      local a = addr + (w % 32) * 32 + (w >= 32 and 0x800 or 0)
      local got = emu.read(a * 2, emu.memType.snesVideoRam, false)
                + emu.read(a * 2 + 1, emu.memType.snesVideoRam, false) * 256
      local o = c * ROWS * 2 + w * 2
      local want = (o + 2 <= #col_expect)
                   and (col_expect:byte(o + 1) + col_expect:byte(o + 2) * 256) or 0
      -- The offline oracle is the NES column. On parallax levels the SNES
      -- renderer deliberately replaces NES tile $00 with its transparent
      -- tile $FE so BG2 can show through without the old striped overlap.
      if rd(A.no_parallax) == 0 and (want & 0x03FF) == 0 then
        want = (want & 0xFC00) | 0x00FE
      end
      if got ~= want then diff[#diff + 1] = w end
    end
    -- A column differing ONLY in the game's own HUD row is the game, not us.
    if #diff > 0 and not (#diff == 1 and diff[1] == HUD_ROW) then
      col_bad = col_bad + 1
      if not col_first then
        col_first = c
        col_detail = string.format("rows %s", table.concat(diff, ","))
      end
    end
  end

  local state = rd(A.gameState)
  local py = rd16(A.player_y) // 256
  -- A platformer level does not scroll on its own, so how far the camera got is
  -- a measure of the harness's ability to play it, not of the level loading.
  -- The sewers puts the player in a pit that A + RIGHT cannot climb out of; it
  -- renders perfectly (out/level23.png). Those levels are held to the tilemap
  -- check and the state check only.
  local plat = rd(A.force_platformer) ~= 0
  local need = plat and 4 or 20
  local bad = {}
  if rle_bad < 0 then
    bad[#bad + 1] = string.format("level_rle is %d bytes, expected %d",
                                  rle_len, #rle_expect)
  elseif rle_bad > 0 then
    bad[#bad + 1] = string.format("level_rle wrong in %d of %d bytes, first at %d",
                                  rle_bad, rle_len, rle_first)
  end
  if col_bad > 0 then
    bad[#bad + 1] = string.format("%d streamed columns wrong, first is column %d (%s)",
                                  col_bad, col_first, col_detail)
  end
  if chr_bad > 0 then
    bad[#bad + 1] = string.format("even BG tileset wrong in %d of %d bytes, "
                                  .. "first at %d (expected set %d)",
                                  chr_bad, #chr_expect, chr_first,
                                  bg.tileset[LEVEL + 1])
  end
  if chr_alt_bad > 0 then
    bad[#bad + 1] = string.format("odd BG tileset wrong in %d of %d bytes, "
                                  .. "first at %d (expected set %d)",
                                  chr_alt_bad, #chr_alt_expect, chr_alt_first,
                                  bg.tileset[LEVEL + 1])
  end
  if not pal_checked then
    bad[#bad + 1] = "the level colours were never set (load_ground never ran)"
  elseif pal_bad > 0 then
    bad[#bad + 1] = string.format("%d level colours wrong: %s", pal_bad, pal_first)
  end
  if state ~= 0x02 then bad[#bad + 1] = string.format("gameState=%d", state) end
  if cols < need then
    bad[#bad + 1] = string.format("only %d column changes", cols)
  end
  if nonzero < 32 then bad[#bad + 1] = string.format("tilemap nearly empty (%d)", nonzero) end
  if py > 240 then bad[#bad + 1] = string.format("player off screen (y=%d)", py) end

  if #bad == 0 then
    print(string.format("level %2d: OK  (%d RLE bytes exact, columns %d-%d "
                        .. "correct, both phases of tileset %d + colours exact, "
                        .. "player y=%d%s)",
                        LEVEL, rle_len, first, newest, bg.tileset[LEVEL + 1], py,
                        plat and ", platformer" or ""))
    emu.stop(0)
  else
    print(string.format("level %2d: FAIL - %s", LEVEL, table.concat(bad, "; ")))
    emu.stop(1)
  end
end, emu.eventType.startFrame)
