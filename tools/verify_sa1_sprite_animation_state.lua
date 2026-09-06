-- Verify that recycled level-object slots never carry an animation frame which
-- is outside the newly loaded object's animation table.
local OUT = "C:/famidash-snes-port/out/"
local A = dofile(OUT .. "addrs_sa1.lua")
local B = emu.memType.snesSaveRam
local M = emu.memType.snesMemory
local LEVEL = tonumber(os.getenv("LEVEL")) or 165
local STOP_AT = tonumber(os.getenv("FRAMES")) or 1800

local frames, gameplay, menu_frames = 0, 0, 0
local entered, press = false, false
local invalid, first = 0, nil

local function rd(addr, width)
  local value = 0
  for i = 0, (width or 1) - 1 do
    value = value + emu.read(addr + i, B, false) * (256 ^ i)
  end
  return value
end

emu.addEventCallback(function()
  emu.setInput((press or entered) and { a = true } or {}, 0)
end, emu.eventType.inputPolled)

local function finish()
  local rows = {
    string.format("level=%d gameplay=%d invalid-animation-frames=%d",
                  LEVEL, gameplay, invalid),
    first and ("first invalid: " .. first) or "first invalid: none",
    invalid == 0 and "RESULT: ANIMATION SLOT STATE IS BOUNDED"
                 or "RESULT: FAIL - RECYCLED SLOT FRAME IS OUT OF RANGE",
  }
  local file = assert(io.open(
    OUT .. string.format("sa1_sprite_animation_state_L%03d.txt", LEVEL), "w"))
  file:write(table.concat(rows, "\n") .. "\n")
  file:close()
  emu.stop(invalid == 0 and 0 or 1)
end

emu.addEventCallback(function()
  frames = frames + 1
  if not entered then
    if rd(A.shim_menu_active) ~= 0 then
      menu_frames = menu_frames + 1
      emu.write(A.menu_sel, LEVEL, B)
      press = menu_frames >= 30 and menu_frames <= 45
    else
      press = false
      if menu_frames > 0 and rd(A.gameState) == 2 and rd(A.level) == LEVEL then
        entered = true
      end
    end
    if frames >= 1200 and not entered then finish() end
    return
  end

  gameplay = gameplay + 1
  emu.write(A.invincible_counter, 0xFF, B)
  emu.write(A.DEBUG_MODE, 1, B)
  for slot = 0, 15 do
    local active = rd(A.activesprites_active + slot)
    local kind = rd(A.activesprites_type + slot)
    if active ~= 0 and kind < 0x80 then
      local length = emu.read(
        A.code.animation_frame_length + kind, M, false)
      local animation = rd(A.code.animation_frame_list + kind * 4, 4)
      if animation ~= 0 and length ~= 0 then
        local frame = rd(A.activesprites_anim_frame + slot)
        if frame >= length then
          invalid = invalid + 1
          if not first then
            first = string.format(
              "gameplay=%d slot=%d type=%02X frame=%d length=%d",
              gameplay, slot, kind, frame, length)
          end
        end
      end
    end
  end
  if gameplay >= STOP_AT then finish() end
end, emu.eventType.endFrame)
