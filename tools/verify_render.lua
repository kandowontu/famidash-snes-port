-- Does the full ROM put the right level columns in VRAM?
--
-- VRAM reads are deterministic, unlike screenshots (docs/HANDOFF.md trap 1), so
-- this compares the BG1 tilemap against the same precomputed records the
-- renderer streams from.
--
-- It reads rld_column - the renderer's own cursor - rather than trying to infer
-- which column is where. Inferring does not work: the level opens on empty sky,
-- so column 0 matches dozens of others and the search locks onto the wrong one.
--
-- The 64x64 map is FOUR 32x32 screens at +0, +0x400, +0x800, +0xC00 words. A
-- column is 64 tiles tall, so rows 0-31 live in SC0/SC1 and rows 32-63 in
-- SC2/SC3, 0x800 words on. Within a screen the rows are 32 words apart.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local menu = dofile("C:/famidash-snes-port/tools/menu_skip.lua")
local LEVEL = tonumber(os.getenv("LEVEL")) or 0
menu.start(LEVEL)
local MAP_BASE = 0x6000
local HUD_ROW = 15   -- the game's "ATTEMPT n" overlay row
local ROWS = 64      -- tile rows per column record
local REC_BYTES = ROWS * 2
local CHECK_AT = { 60, 120, 240, 400, 600 }

-- The oracle for THIS level, from tools/gen_level_columns.py. It used to be the
-- precomputed ROM stream in out/level_columns*.bin, which only ever existed for
-- stereomadness - so this check, the only byte-exact one, ran on one level out
-- of forty-six. That is how a level whose decode desynced shipped.
local cols = {}
do
  local f = io.open(OUT .. "level_expect_" .. LEVEL .. ".bin", "rb")
  if not f then
    print(string.format("RESULT: FAIL - out/level_expect_%d.bin missing; run "
                        .. "python tools/gen_level_columns.py --level %d", LEVEL, LEVEL))
    emu.stop(1)
    return
  end
  local blob = f:read("*a"); f:close()
  for c = 0, math.floor(#blob / REC_BYTES) - 1 do
    local rec = {}
    for w = 0, ROWS - 1 do
      local o = c * REC_BYTES + w * 2 + 1
      rec[w] = blob:byte(o) + blob:byte(o + 1) * 256
    end
    cols[c] = rec
  end
end

local frames, idx, rows = 0, 1, {}
local checked, bad, overlaid = 0, 0, 0
local detail = {}

local function vram_word(word_addr)
  local a = word_addr * 2
  return emu.read(a, emu.memType.snesVideoRam)
       + emu.read(a + 1, emu.memType.snesVideoRam) * 256
end

local function onFrame()
  -- Gameplay only. main() now opens the level select first, so a script that
  -- counts from reset measures the menu - which reads as a game with nothing in
  -- it rather than as an error. See tools/menu_skip.lua.
  if not menu.done() then return end
  frames = frames + 1
  if idx > #CHECK_AT or frames ~= CHECK_AT[idx] then return end
  idx = idx + 1

  local rld = emu.read(A.rld_column, emu.memType.snesWorkRam)
            + emu.read(A.rld_column + 1, emu.memType.snesWorkRam) * 256

  -- The 64 map slots hold the most recent 64 columns written.
  --
  -- rld_column is incremented when a column is QUEUED, not when it reaches
  -- VRAM: the DMA happens in the next vblank. So the newest column may
  -- legitimately still be in flight, and checking it reports a renderer bug
  -- that is not there. Stop one short. (docs/HANDOFF.md trap 4: verify only
  -- what the code promises.)
  -- The window is rld-64 .. rld-2, which is 63 columns, not 64.
  --
  -- The map has 64 slots and column c lives in slot c%64, so column rld-65
  -- shares a slot with rld-1. Taking a full 64 columns therefore includes one
  -- whose slot has ALREADY been reused by the newest write - and whether that
  -- write has reached VRAM depends on the vblank, so the oldest column reads as
  -- itself or as its successor depending on timing. Reported as a renderer bug
  -- for a while; it is arithmetic.
  local newest = rld - 2
  local first = math.max(0, newest - 62)
  local slot_bad, slot_ok = 0, 0
  local wrong_list = {}
  for c = first, newest do
    local slot = c % 64
    local addr = MAP_BASE + (slot % 32) + (slot >= 32 and 0x400 or 0)
    local diff_rows = {}
    for w = 0, ROWS - 1 do
      checked = checked + 1
      -- rows 32-63 are in the lower pair of screens, 0x800 words on
      local a = addr + (w % 32) * 32 + (w >= 32 and 0x800 or 0)
      if vram_word(a) ~= cols[c][w] then diff_rows[#diff_rows+1] = w end
    end
    -- The game draws its own "ATTEMPT n" overlay into tilemap row 15
    -- (level_loading.h: NTADR_C(6,15) and NTADR_C(20,15)), exactly as it does
    -- on the NES. A column differing ONLY there is the game, not the renderer.
    if #diff_rows == 0 then
      slot_ok = slot_ok + 1
    elseif #diff_rows == 1 and diff_rows[1] == HUD_ROW then
      overlaid = overlaid + 1
    else
      slot_bad = slot_bad + 1; bad = bad + 1
      if #wrong_list < 24 then wrong_list[#wrong_list+1] = c end
      -- Which ROWS differ, and to what, for the first few. "column N is wrong"
      -- does not say whether the decode desynced, the clipping is off by a
      -- metatile row, or the whole column is a repeat of one tile.
      if #detail < 4 then
        local d = { string.format("  column %d differs in %d rows:", c, #diff_rows) }
        for i = 1, math.min(#diff_rows, 12) do
          local w = diff_rows[i]
          local a = addr + (w % 32) * 32 + (w >= 32 and 0x800 or 0)
          d[#d+1] = string.format("    row %2d: vram %04X  expected %04X",
                                  w, vram_word(a), cols[c][w])
        end
        detail[#detail+1] = table.concat(d, "\n")
      end
    end
  end

  rows[#rows + 1] = string.format(
    "frame %4d  rld_column=%5d   checked %d-%d   correct %d, HUD-overlaid %d, wrong %d",
    frames, rld, first, newest, slot_ok, overlaid, slot_bad)
  rows[#rows] = rows[#rows] .. "  wrong: " .. table.concat(wrong_list, ",")

  if idx > #CHECK_AT then
    local ok = (bad == 0) and (checked > 0)
    rows[#rows + 1] = string.format(
      "%d tilemap words checked, %d columns wrong, %d differing only in the "
      .. "game's own HUD row", checked, bad, overlaid)
    for _, d in ipairs(detail) do rows[#rows + 1] = d end
    rows[#rows + 1] = ok and "RESULT: LEVEL RENDERED" or "RESULT: FAIL"
    local f = io.open(OUT .. "render_verify.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(ok and 0 or 1)
  end
end
emu.addEventCallback(onFrame, emu.eventType.startFrame)
