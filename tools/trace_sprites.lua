-- What the sprite engine is actually doing, per frame.
--
-- Three questions, none of which a screenshot answers (docs/HANDOFF.md trap 1):
--   1. how many video frames pass per GAME frame  (kandoframecnt vs startFrame)
--   2. how many OAM entries are live, and which OBJ tiles they name
--   3. what check_spr_objects has in the 16 active-sprite slots
--
-- OAM and WRAM reads are deterministic, so this is a real measurement.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_full.lua")
local SLOTS = 16
local SAMPLE_AT = { 90, 150, 240, 400, 600, 900 }

local function wram(addr, n)
  local v = 0
  for i = 0, (n or 1) - 1 do
    v = v + emu.read(addr + i, emu.memType.snesWorkRam) * (256 ^ i)
  end
  return v
end

local frames, idx, rows = 0, 1, {}
local prev_gf, prev_vf = nil, nil

local function onFrame()
  frames = frames + 1

  local gf = wram(A.kandoframecnt)
  if prev_gf then
    -- kandoframecnt is a byte and wraps; a step of 1 means the game kept up.
    local step = (gf - prev_gf) % 256
    if step ~= 0 then
      local vstep = frames - prev_vf
      rows[#rows + 1] = string.format("  gameframe +%d over %d video frames%s",
        step, vstep, vstep > 1 and "   <-- LAG" or "")
      prev_gf, prev_vf = gf, frames
    end
  else
    prev_gf, prev_vf = gf, frames
  end

  if idx > #SAMPLE_AT or frames ~= SAMPLE_AT[idx] then return end
  idx = idx + 1

  -- OAM: 128 entries of 4 bytes, then the 32-byte high table.
  local live, tiles = 0, {}
  for s = 0, 127 do
    local y = emu.read(s * 4 + 1, emu.memType.snesSpriteRam)
    if y < 225 then
      live = live + 1
      local t = emu.read(s * 4 + 2, emu.memType.snesSpriteRam)
      local a = emu.read(s * 4 + 3, emu.memType.snesSpriteRam)
      local tile = t + (a % 2) * 256
      tiles[tile] = (tiles[tile] or 0) + 1
    end
  end
  local tlist = {}
  for t, n in pairs(tiles) do tlist[#tlist + 1] = string.format("%d x%d", t, n) end
  table.sort(tlist)

  local act = {}
  for i = 0, SLOTS - 1 do
    local ty = wram(A.activesprites_type + i)
    local ac = wram(A.activesprites_active + i)
    act[#act + 1] = string.format("%02X/%d", ty, ac)
  end

  rows[#rows + 1] = string.format(
    "frame %4d  gameframe=%3d  rld_column=%4d  scroll_x=%d  OAM live=%d",
    frames, wram(A.kandoframecnt), wram(A.rld_column, 2), wram(A.scroll_x, 3), live)
  rows[#rows + 1] = "    slots (type/active): " .. table.concat(act, " ")
  rows[#rows + 1] = "    OBJ tiles: " .. table.concat(tlist, ", ")

  if idx > #SAMPLE_AT then
    local f = io.open(OUT .. "sprite_trace.txt", "w")
    f:write(table.concat(rows, "\n") .. "\n"); f:close()
    emu.stop(0)
  end
end
emu.addEventCallback(onFrame, emu.eventType.startFrame)
