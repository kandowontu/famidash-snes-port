-- Diagnose OBJ artifacts while the palette/disco effects are active.
--
-- The S-CPU flush callback captures the exact SA-1 shadow OAM which will be
-- displayed.  For every visible entry, the report records its position, tile
-- and palette beside the active level-object slots.  Screenshots at the same
-- points make it possible to identify an apparent "ghost" without relying on
-- execution callbacks (which Mesen does not expose for SA-1 code).
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local B = emu.memType.snesSaveRam
local O = emu.memType.snesSpriteRam

local LEVEL = tonumber(os.getenv("LEVEL")) or 0
local STOP_AT = tonumber(os.getenv("FRAMES")) or 900
local FORCE_SPRITE_DISCO = tonumber(os.getenv("SPRITE_DISCO")) or 0
local SAMPLE_STEP = tonumber(os.getenv("SAMPLE_STEP")) or 300
local SAMPLE = {}
for frame = SAMPLE_STEP, STOP_AT, SAMPLE_STEP do SAMPLE[frame] = true end

local frames, gameplay, menu_frames = 0, 0, 0
local entered, press, pending = false, false, false
local rows = {}

local function rd(addr, width)
  local value = 0
  for i = 0, (width or 1) - 1 do
    value = value + emu.read(addr + i, B, false) * (256 ^ i)
  end
  return value
end

emu.addEventCallback(function()
  if press or entered then emu.setInput({ a = true }, 0) end
end, emu.eventType.inputPolled)

emu.addMemoryCallback(function()
  pending = true
end, emu.callbackType.exec, A.code.shim_scpu_flush, A.code.shim_scpu_flush)

local function snapshot()
  rows[#rows + 1] = string.format(
    "gameplay=%d scroll=%d discomode=%02X disco_sprites=%d sprid=%d " ..
    "mode=%d trails=%d forced=%d orb=%d player=(%d,%d)",
    gameplay, rd(A.scroll_x, 2), rd(A.discomode), rd(A.disco_sprites),
    rd(A.sprid, 2), rd(A.gamemode), rd(A.trails), rd(A.forced_trails),
    rd(A.orbactive), rd(A.player_x + 1), rd(A.player_y + 1))
  local slots = {}
  for i = 0, 15 do
    if rd(A.activesprites_active + i) ~= 0 then
      local wx = rd(A.activesprites_x_lo + i)
               + rd(A.activesprites_x_hi + i) * 256
      local wy = rd(A.activesprites_y_lo + i)
               + rd(A.activesprites_y_hi + i) * 256
      slots[#slots + 1] = string.format(
        "%X:t%02X w(%d,%d) s(%d,%d) a%d",
        i, rd(A.activesprites_type + i), wx, wy,
        rd(A.activesprites_realx + i), rd(A.activesprites_realy + i),
        rd(A.activesprites_activated + i))
    end
  end
  rows[#rows + 1] = "  active: " .. table.concat(slots, " | ")

  local sprites = {}
  for i = 0, 127 do
    local y = emu.read(i * 4 + 1, O, false)
    if y < 225 then
      local x = emu.read(i * 4, O, false)
      local tile = emu.read(i * 4 + 2, O, false)
      local attr = emu.read(i * 4 + 3, O, false)
      sprites[#sprites + 1] = string.format(
        "%d:(%d,%d) t%03X p%d", i, x, y,
        tile + (attr & 1) * 256, (attr >> 1) & 7)
    end
  end
  rows[#rows + 1] = "  OAM: " .. table.concat(sprites, " | ")

  local ok, png = pcall(emu.takeScreenshot)
  if ok and png and #png > 0 then
    local name = string.format(
      "%ssa1_disco_L%03d_D%d_F%04d.png",
      OUT, LEVEL, FORCE_SPRITE_DISCO, gameplay)
    local f = assert(io.open(name, "wb"))
    f:write(png)
    f:close()
  end
end

emu.addEventCallback(function()
  frames = frames + 1
  if not entered then
    if rd(A.shim_menu_active) ~= 0 then
      menu_frames = menu_frames + 1
      emu.write(A.menu_sel, LEVEL, B)
      press = menu_frames >= 12 and menu_frames <= 20
    else
      press = false
      if menu_frames > 0 and rd(A.gameState) == 2 and rd(A.level) == LEVEL then
        entered = true
      end
    end
    if frames >= 1200 and not entered then emu.stop(1) end
    return
  end

  gameplay = gameplay + 1
  -- Exercise the fastest normal palette cadence and keep hazards from turning
  -- this into a death/restart trace.
  emu.write(A.discomode, 0x10, B)
  emu.write(A.discorefreshrate, 0x03, B)
  emu.write(A.disco_sprites, FORCE_SPRITE_DISCO, B)
  emu.write(A.invincible_counter, 0xFF, B)
  emu.write(A.DEBUG_MODE, 1, B)
  emu.write(A.kandodebugmode, 0, B)
  emu.write(A.cube_data, rd(A.cube_data) & 0xFE, B)
  emu.write(A.cube_data + 1, rd(A.cube_data + 1) & 0xFE, B)

  if SAMPLE[gameplay] and pending then snapshot() end
  pending = false

  if gameplay >= STOP_AT then
    local f = assert(io.open(OUT .. string.format(
      "sa1_disco_objects_L%03d_D%d.txt", LEVEL, FORCE_SPRITE_DISCO), "w"))
    f:write(table.concat(rows, "\n") .. "\n")
    f:close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)
