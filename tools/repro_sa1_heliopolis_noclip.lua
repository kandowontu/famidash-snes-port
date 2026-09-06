-- Exact Heliopolis noclip/ghosting reproduction requested by the user.
--
-- Enter level 165 through the normal SA-1 level menu, tap Select once after
-- gameplay starts, then record the complete active-object and displayed-OAM
-- state around gameplay frames 240-360.  Deliberately do not force health,
-- palette/disco state, movement, or jump input.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local B = emu.memType.snesSaveRam
local O = emu.memType.snesSpriteRam

local LEVEL = tonumber(os.getenv("LEVEL")) or 165
local WATCH_AFTER_SELECT = tonumber(os.getenv("FRAMES")) or 380
local SELECT_AT = tonumber(os.getenv("SELECT_AT")) or 10
local CAPTURE = {
  [220] = true, [240] = true, [260] = true, [280] = true,
  [300] = true, [320] = true, [340] = true, [360] = true,
  [380] = true,
}

local video_frame, gameplay, menu_frames = 0, 0, 0
local entered, menu_press = false, false
local select_requested, select_done = false, false
local select_gameplay
local flush_pending, expected_used = false, 0
local rows = {}
local prior_slots = {}
local window_flushes, short_flushes = 0, 0
local missed_pcs = {}
local sa1_state_keys

local function rd(addr, width)
  local value = 0
  for i = 0, (width or 1) - 1 do
    value = value + emu.read(addr + i, B, false) * (256 ^ i)
  end
  return value
end

local function signed8(value)
  return value >= 128 and value - 256 or value
end

emu.addEventCallback(function()
  if menu_press then
    emu.setInput({ a = true }, 0)
  elseif select_requested and not select_done then
    emu.setInput({ select = true }, 0)
  end
end, emu.eventType.inputPolled)

-- The S-CPU flush is the boundary at which shadow OAM becomes the next
-- displayed OAM.  This also lets the trace distinguish producer state from a
-- stale hardware tail.
emu.addMemoryCallback(function()
  if not entered then return end
  expected_used = rd(A.sprid, 2) // 4
  if expected_used > 128 then expected_used = 128 end
  flush_pending = true
end, emu.callbackType.exec, A.code.shim_scpu_flush, A.code.shim_scpu_flush)

local function trace_frame(noclip_age)
  local sx = rd(A.scroll_x, 2)
  local sy = rd(A.scroll_y, 2)
  local debug = rd(A.DEBUG_MODE)
  rows[#rows + 1] = string.format(
    "F%03d N%03d video=%d scroll=(%d,%d) player=(%d,%d) debug=%d " ..
    "kdebug=%d disco=%02X dspr=%d used=%d",
    gameplay, noclip_age, video_frame, sx, sy,
    rd(A.player_x + 1), rd(A.player_y + 1), debug,
    rd(A.kandodebugmode), rd(A.discomode),
    rd(A.disco_sprites), expected_used)

  local slots, seen = {}, {}
  for i = 0, 15 do
    if rd(A.activesprites_active + i) ~= 0 then
      local wx = rd(A.activesprites_x_lo + i)
               + rd(A.activesprites_x_hi + i) * 256
      local wy = rd(A.activesprites_y_lo + i)
               + rd(A.activesprites_y_hi + i) * 256
      local rx = rd(A.activesprites_realx + i)
      local ry = rd(A.activesprites_realy + i)
      local dx = prior_slots[i] and signed8(rx - prior_slots[i].rx) or 0
      local dy = prior_slots[i] and signed8(ry - prior_slots[i].ry) or 0
      seen[i] = { rx = rx, ry = ry }
      slots[#slots + 1] = string.format(
        "%X:t%02X w(%d,%d) r(%d,%d) d(%d,%d) a%d f%d",
        i, rd(A.activesprites_type + i), wx, wy, rx, ry, dx, dy,
        rd(A.activesprites_activated + i),
        rd(A.activesprites_anim_frame + i))
    end
  end
  prior_slots = seen
  rows[#rows + 1] = "  active: " .. table.concat(slots, " | ")

  local sprites = {}
  for i = 0, 127 do
    local y = emu.read(i * 4 + 1, O, false)
    if y < 225 then
      local x = emu.read(i * 4, O, false)
      local tile = emu.read(i * 4 + 2, O, false)
      local attr = emu.read(i * 4 + 3, O, false)
      sprites[#sprites + 1] = string.format(
        "%d:(%d,%d)t%03Xp%d", i, x, y,
        tile + (attr & 1) * 256, (attr >> 1) & 7)
    end
  end
  rows[#rows + 1] = "  OAM: " .. table.concat(sprites, " | ")
end

local function screenshot(noclip_age)
  local ok, png = pcall(emu.takeScreenshot)
  if not ok or not png or #png == 0 then return end
  local name = string.format("%ssa1_heliopolis_noclip_N%03d_F%03d.png",
                             OUT, noclip_age, gameplay)
  local file = assert(io.open(name, "wb"))
  file:write(png)
  file:close()
end

local function finish(code)
  local file = assert(io.open(OUT .. "sa1_heliopolis_noclip_trace.txt", "w"))
  file:write(table.concat(rows, "\n") .. "\n")
  file:close()
  emu.stop(code)
end

emu.addEventCallback(function()
  video_frame = video_frame + 1
  if not entered then
    if rd(A.shim_menu_active) ~= 0 then
      menu_frames = menu_frames + 1
      emu.write(A.menu_sel, LEVEL, B)
      -- Let the newly active menu complete a few producer handshakes before
      -- injecting A; very early video frames can be intentional repeats.
      menu_press = menu_frames >= 30 and menu_frames <= 45
    else
      menu_press = false
      if menu_frames > 0 and rd(A.gameState) == 2
         and rd(A.level) == LEVEL then
        entered = true
      end
    end
    if video_frame >= 1200 and not entered then
      rows[#rows + 1] = string.format(
        "RESULT: FAIL - did not enter level (menu_frames=%d active=%d state=%d level=%d)",
        menu_frames, rd(A.shim_menu_active), rd(A.gameState), rd(A.level))
      finish(1)
    end
    return
  end

  gameplay = gameplay + 1
  if gameplay >= SELECT_AT and not select_done then
    select_requested = true
  end
  if select_requested and rd(A.DEBUG_MODE) ~= 0 then
    select_requested = false
    select_done = true
    select_gameplay = gameplay
    rows[#rows + 1] = string.format(
      "SELECT toggled noclip at gameplay=%d video=%d", gameplay, video_frame)
  end

  local noclip_age = select_gameplay and (gameplay - select_gameplay) or -1
  if noclip_age >= 240 and noclip_age <= 360 and not flush_pending then
    local st = emu.getState()
    if not sa1_state_keys then
      local keys = {}
      for k, v in pairs(st) do
        if string.find(k, "coprocessor.cpu", 1, true) then
          keys[#keys + 1] = string.format("%s=%s", k, tostring(v))
        end
      end
      table.sort(keys)
      sa1_state_keys = table.concat(keys, ", ")
    end
    missed_pcs[#missed_pcs + 1] = string.format(
      "N%03d pc=$%06X", noclip_age,
      st["cart.coprocessor.cpu.pc"] or 0)
  end
  if noclip_age >= 160 and flush_pending then
    if noclip_age >= 240 and noclip_age <= 360 then
      window_flushes = window_flushes + 1
      if expected_used < 4 then short_flushes = short_flushes + 1 end
    end
    trace_frame(noclip_age)
  end
  flush_pending = false
  if CAPTURE[noclip_age] then screenshot(noclip_age) end

  if gameplay >= 1200 and not select_done then
    rows[#rows + 1] = "RESULT: FAIL - Select did not toggle DEBUG_MODE"
    finish(1)
  end
  if select_done and noclip_age >= WATCH_AFTER_SELECT then
    rows[#rows + 1] = string.format(
      "complete producer flushes at noclip N240-360: %d; repeated video frames: %d; short/empty: %d",
      window_flushes, 121 - window_flushes, short_flushes)
    rows[#rows + 1] = "missed-frame SA-1 PCs: " .. table.concat(missed_pcs, ", ")
    rows[#rows + 1] = "SA-1 state sample: " .. (sa1_state_keys or "none")
    local ok = select_done and window_flushes >= 120 and short_flushes == 0
    rows[#rows + 1] = ok
      and "RESULT: PASS - Heliopolis keeps pace and publishes only complete OAM"
       or "RESULT: FAIL - Heliopolis missed display deadlines or published incomplete OAM"
    finish(ok and 0 or 1)
  end
end, emu.eventType.endFrame)
