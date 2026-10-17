-- Swivel Seat: aim a swivel seat with W A S D on a Linked Typewriter.
--
-- Three computers, one per sublevel, all running this same file:
--   SEAT   the one with the Linked Typewriter (reads the keys)
--   YAW    turns a Sequenced Gearshift for left / right (A / D)
--   PITCH  turns a Sequenced Gearshift for up / down   (W / S)
-- They talk over wireless or Ender Modems (wired cables can't cross
-- sublevels). First boot asks which job the computer has; run
-- `swivel seat`, `swivel yaw` or `swivel pitch` to change it.
--
-- Hold a key and the gearshift turns smoothly until you let go (or it hits
-- a limit). The yaw/pitch computers stop by themselves if the seat goes quiet.

SEAT = "seat1"            -- name shared by the 3 computers (use another for a 2nd seat)
KEYS = { up = "w", down = "s", left = "a", right = "d" }
SPEED = 1                 -- 1 = gearshift input speed, 2 = double speed
INVERT_YAW = false        -- true if A turns right
INVERT_PITCH = false      -- true if W points down
YAW_MIN = nil             -- limits in degrees from center (nil = no limit)
YAW_MAX = nil
PITCH_MIN = -60
PITCH_MAX = 60
TIMEOUT = 0.5             -- seconds of silence from the seat before stopping
AUTO_UPDATE = true

if fs and fs.exists("/config.lua") then
  local f, err = loadfile("/config.lua", nil, _ENV)
  if not f then error("/config.lua: " .. err, 0) end
  f()
end

-- ============================================================ setup

VERSION = "1.2.0"
local ROLE_FILE = "/swivel_role"
local PROTOCOL = "swivelseat-" .. SEAT
local SEND_EVERY = 0.2      -- heartbeat; key changes are sent at once
local moving = false
local ROLES = { seat = true, yaw = true, pitch = true }

local function now() return os.epoch("utc") / 1000 end

local function readFile(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  local s = h.readAll()
  h.close()
  return s
end

local function writeFile(path, text)
  local h = fs.open(path, "w")
  h.write(text)
  h.close()
end

local args = { ... }
local role = args[1] and args[1]:lower()
if role and ROLES[role] then
  writeFile(ROLE_FILE, role)
else
  role = readFile(ROLE_FILE)
  role = role and role:match("%a+")
end
while not (role and ROLES[role]) do
  term.clear()
  term.setCursorPos(1, 1)
  print("Swivel Seat " .. VERSION)
  print("What is this computer?")
  print("  S  Seat  (has the Linked Typewriter)")
  print("  Y  Yaw   (left/right gearshift)")
  print("  P  Pitch (up/down gearshift)")
  local _, ch = os.pullEvent("char")
  role = ({ s = "seat", y = "yaw", p = "pitch" })[ch:lower()]
  if role then writeFile(ROLE_FILE, role) end
end

-- Open every wireless modem (Ender Modems count).
local modemName = nil
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "modem" and peripheral.call(name, "isWireless") then
    if not rednet.isOpen(name) then rednet.open(name) end
    modemName = modemName or name
  end
end

local status = ""
local function screen(lines)
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.yellow)
  print("Swivel Seat " .. VERSION .. "  [" .. role:upper() .. "]  " .. SEAT)
  term.setTextColor(colors.white)
  if not modemName then
    term.setTextColor(colors.red)
    print("No wireless/Ender modem!")
    term.setTextColor(colors.white)
  end
  for _, l in ipairs(lines) do print(l) end
  if status ~= "" then
    term.setTextColor(colors.lightGray)
    print(status)
    term.setTextColor(colors.white)
  end
end

-- ============================================================ seat

local function seatMain()
  local typewriter = peripheral.find("linked_typewriter")
  local kbHeld = {}     -- this computer's own keyboard, as a backup
  local held = {}
  local twError = nil
  local hears = {}      -- "yaw"/"pitch" -> {angle, at}

  local function code(name) return keys[name] end

  local function poll()
    local h = {}
    if typewriter then
      local ok, codes = pcall(typewriter.getPressedKeyCodes)
      if ok and type(codes) == "table" then
        for _, c in ipairs(codes) do h[c] = true end
        twError = nil
      elseif not ok then
        twError = tostring(codes)
      end
    end
    -- typewriter key events land here too; drop them if no key_up comes
    for c, t in pairs(kbHeld) do
      if now() - t < 0.7 then h[c] = true else kbHeld[c] = nil end
    end
    held = h
  end

  local function axis(plus, minus)
    local p, m = held[code(plus)], held[code(minus)]
    if p and not m then return 1 elseif m and not p then return -1 end
    return 0
  end

  local function heldText()
    local names = {}
    for c in pairs(held) do names[#names + 1] = (keys.getName and keys.getName(c) or "?") .. "(" .. c .. ")" end
    table.sort(names)
    if #names == 0 then return "none" end
    return table.concat(names, " ")
  end

  local function draw()
    local yaw, pitch = axis(KEYS.right, KEYS.left), axis(KEYS.up, KEYS.down)
    local function arrow(v, neg, pos) if v > 0 then return pos elseif v < 0 then return neg end return "-" end
    local function seen(r)
      local h = hears[r]
      if not h or now() - h.at > 2 then return "no reply" end
      return string.format("%.0f deg", h.angle)
    end
    screen({
      "",
      "Typewriter: " .. (typewriter and "found" or "MISSING (wired modem or touching)"),
      twError and ("Typewriter error: " .. twError) or "",
      "Keys held: " .. heldText(),
      "Yaw:   " .. arrow(yaw, "LEFT", "RIGHT") .. "   at " .. seen("yaw"),
      "Pitch: " .. arrow(pitch, "DOWN", "UP") .. "   at " .. seen("pitch"),
      "",
      "Keys: " .. KEYS.up:upper() .. KEYS.left:upper() .. KEYS.down:upper() .. KEYS.right:upper()
        .. " on the typewriter",
      "This keyboard: H = back to center",
      "               Z = set here as center",
    })
  end

  local function sendLoop()
    local lastYaw, lastPitch, lastSend, lastDraw = nil, nil, 0, 0
    while true do
      if not typewriter then typewriter = peripheral.find("linked_typewriter") end
      poll()
      local yaw, pitch = axis(KEYS.right, KEYS.left), axis(KEYS.up, KEYS.down)
      if yaw ~= lastYaw or pitch ~= lastPitch or now() - lastSend >= SEND_EVERY then
        pcall(rednet.broadcast, { t = "aim", yaw = yaw, pitch = pitch }, PROTOCOL)
        lastYaw, lastPitch, lastSend = yaw, pitch, now()
      end
      if now() - lastDraw >= 0.25 then
        draw()
        lastDraw = now()
      end
      sleep(0.05)
    end
  end

  local function eventLoop()
    while true do
      local ev, a = os.pullEvent()
      if ev == "key" then
        kbHeld[a] = now()
        if a == keys.h then
          pcall(rednet.broadcast, { t = "home" }, PROTOCOL)
          status = "Sent: back to center"
        elseif a == keys.z then
          pcall(rednet.broadcast, { t = "zero" }, PROTOCOL)
          status = "Sent: here is the new center"
        end
      elseif ev == "key_up" then
        kbHeld[a] = nil
      end
    end
  end

  local function replyLoop()
    while true do
      local _, msg = rednet.receive(PROTOCOL .. "-status")
      if type(msg) == "table" and ROLES[msg.role] and type(msg.angle) == "number" then
        hears[msg.role] = { angle = msg.angle, at = now() }
      end
    end
  end

  return { sendLoop, eventLoop, replyLoop }
end

-- ============================================================ yaw / pitch

-- One long gearshift turn starts when a key goes down and is cut off when
-- it comes up, so the seat moves without stopping between steps. The angle
-- is worked out from the gearshift's speed (degrees per tick = rpm * 0.3).
local CHUNK = 360   -- longest single turn; it starts again if you keep holding

local function axisMain()
  local STATE_FILE = "/swivel_angle"
  local invert = (role == "yaw" and INVERT_YAW) or (role == "pitch" and INVERT_PITCH)
  local lo, hi = PITCH_MIN, PITCH_MAX
  if role == "yaw" then lo, hi = YAW_MIN, YAW_MAX end
  local angle = tonumber(readFile(STATE_FILE) or "") or 0
  local want, lastHeard, home, test = 0, 0, false, 0
  local gear = nil
  local msgCount = 0
  local gearState = "idle"
  local rpm = nil

  -- the turn in progress
  local cur = 0          -- direction: 1, -1 or 0
  local goal = 0         -- degrees this turn was told to go
  local done = 0         -- degrees it has gone so far
  local lastClock, started = 0, 0
  local homing = false   -- runs to the end; keys are ignored meanwhile

  local function save() writeFile(STATE_FILE, tostring(angle)) end
  local function liveAngle() return angle + cur * done end

  local function running()
    local ok, r = pcall(gear.isRunning)
    return ok and r
  end

  local function readRpm()
    if gear.getSpeed then
      local ok, v = pcall(gear.getSpeed)
      if ok and type(v) == "number" then
        rpm = math.abs(v)
        return
      end
    end
    rpm = nil
  end

  local function command(deg, dir)
    if invert then dir = -dir end
    local ok, err = pcall(gear.rotate, deg, dir * SPEED)
    if not ok then
      status = "Gearshift error: " .. tostring(err)
      gear = nil
    end
    return ok
  end

  -- Bank what the current turn did; stopGear cuts it off.
  local function finish(stopGear)
    if cur == 0 then return end
    if stopGear and gear then command(0, 1) end
    angle = angle + cur * done
    save()
    cur, goal, done, homing, moving = 0, 0, 0, false, false
    gearState = "idle"
  end

  local function start(dir, deg)
    deg = math.floor(deg + 0.5)
    if deg < 1 then return end
    readRpm()
    if not command(deg, dir) then return end
    cur, goal, done = dir, deg, 0
    lastClock, started = os.clock(), now()
    moving = true
    gearState = "turning"
  end

  -- degrees left before the limit in direction `dir`
  local function room(dir)
    if dir > 0 then
      if hi then return hi - angle end
    elseif lo then
      return angle - lo
    end
    return CHUNK
  end

  local function update()
    if cur == 0 then return end
    readRpm()
    local c = os.clock()
    done = math.min(goal, done + (c - lastClock) * 20 * (rpm or 0) * 0.3 * math.abs(SPEED))
    lastClock = c
    if now() - started > 0.15 and not running() then
      done = goal
      finish(false)
    elseif rpm == 0 and now() - started > 2 then
      gearState = "STUCK: is its input shaft turning?"
    end
  end

  local function draw()
    local lim = (lo and string.format("%d", lo) or "none") .. " to " .. (hi and string.format("%d", hi) or "none")
    local dirText = "stopped"
    if homing then dirText = "going to center"
    elseif cur > 0 then dirText = "+"
    elseif cur < 0 then dirText = "-" end
    local link = (now() - lastHeard < TIMEOUT) and "OK" or "no signal"
    local lines = {
      "",
      "Gearshift: " .. (gear and gearState or "MISSING (Sequenced Gearshift)"),
      "Input speed: " .. (rpm and string.format("%.0f rpm", rpm) or "?"),
      "Seat link: " .. link .. "  (" .. msgCount .. " msgs)",
      "",
      string.format("Angle:  %.0f deg   (%s)", liveAngle(), dirText),
      "Limits: " .. lim,
      "",
      "T = test turn (no seat needed)",
      "Z = set center   H = go to center",
    }
    if not gear then
      local seen = {}
      for _, n in ipairs(peripheral.getNames()) do seen[#seen + 1] = n .. "=" .. tostring(peripheral.getType(n)) end
      lines[#lines + 1] = "Peripherals: " .. (#seen > 0 and table.concat(seen, ", ") or "none")
    end
    screen(lines)
  end

  local function controlLoop()
    while true do
      if not gear then gear = peripheral.find("Create_SequencedGearshift") end
      if not gear then
        cur, goal, done, homing, moving = 0, 0, 0, false, false
        sleep(1)
      else
        update()
        if test ~= 0 then
          finish(true)
          status = "Test: turning " .. test .. " deg"
          start(1, test)
          homing = cur ~= 0
          test = 0
        elseif home then
          home = false
          finish(true)
          if math.abs(angle) >= 1 then
            start(angle > 0 and -1 or 1, math.abs(angle))
            homing = cur ~= 0
          end
        elseif not homing then
          local desired = want
          if now() - lastHeard >= TIMEOUT then desired = 0 end
          if desired ~= cur then
            finish(true)
            if desired ~= 0 then start(desired, math.min(room(desired), CHUNK)) end
          end
        end
        sleep(0.05)
      end
    end
  end

  local function setCenter()
    if cur ~= 0 then return end
    angle = 0
    save()
    status = "Center set"
  end

  local function netLoop()
    while true do
      local _, msg = rednet.receive(PROTOCOL)
      if type(msg) == "table" then
        if msg.t == "aim" then
          local v = role == "yaw" and msg.yaw or msg.pitch
          if v == 1 or v == -1 or v == 0 then want = v end
          lastHeard = now()
          msgCount = msgCount + 1
        elseif msg.t == "home" then
          home = true
        elseif msg.t == "zero" then
          setCenter()
        end
      end
    end
  end

  local function statusLoop()
    while true do
      pcall(rednet.broadcast, { role = role, angle = liveAngle() }, PROTOCOL .. "-status")
      draw()
      sleep(0.25)
    end
  end

  local function keyLoop()
    while true do
      local _, k = os.pullEvent("key")
      if k == keys.z then
        setCenter()
      elseif k == keys.h then
        home = true
      elseif k == keys.t then
        test = 45
      end
    end
  end

  return { controlLoop, netLoop, statusLoop, keyLoop }
end

-- ============================================================ run

-- Updates wait until the gearshift is done.
function readyToUpdate() return not moving end

local loops
if role == "seat" then loops = seatMain() else loops = axisMain() end

-- ============================================================ auto-update

-- Every UPDATE_CHECK_MINUTES this checks GitHub for a newer version. A new
-- version is downloaded, checked that it loads, given your current settings
-- (the UPPERCASE lines at the top of this file), saved, and the computer
-- reboots into it. Set AUTO_UPDATE = false at the top to turn this off.
local UPDATE_REPO = "levisnakes/cc-swivel-seat"
local UPDATE_FILE = "swivel.lua"
local UPDATE_CHECK_MINUTES = 15
local PROGRAM_PATH = (shell and shell.getRunningProgram()) or "startup.lua"
local SHA_FILE = "/.version_" .. UPDATE_FILE

-- Settings are the top-of-file assignments to UPPERCASE names, before the
-- first "local" line or "-- ====" section. Tables can span several lines.
local function splitSettings(src)
  local settings, rest = {}, {}
  local inSettings = true
  for line in (src .. "\n"):gmatch("(.-)\n") do
    if inSettings and (line:match("^local ") or line:match("^%-%- ====")) then inSettings = false end
    table.insert(inSettings and settings or rest, line)
  end
  return settings, rest
end

local function braceDelta(line)
  local code = line:gsub('"[^"]*"', ""):gsub("%-%-.*$", "")
  local _, opens = code:gsub("{", "")
  local _, closes = code:gsub("}", "")
  return opens - closes
end

-- [NAME] = the full statement text, possibly several lines
local function statements(lines)
  local out = {}
  local i = 1
  while i <= #lines do
    local name = lines[i]:match("^([%u_][%u%d_]*)%s*=")
    if name then
      local block = { lines[i] }
      local depth = braceDelta(lines[i])
      while depth > 0 and i < #lines do
        i = i + 1
        table.insert(block, lines[i])
        depth = depth + braceDelta(lines[i])
      end
      out[name] = table.concat(block, "\n")
    end
    i = i + 1
  end
  return out
end

-- New file, with each setting that already exists replaced by your value.
local function mergeSettings(oldSrc, newSrc)
  local oldSettings = statements((splitSettings(oldSrc)))
  local newSettings, rest = splitSettings(newSrc)
  local out = {}
  local i = 1
  while i <= #newSettings do
    local line = newSettings[i]
    local name = line:match("^([%u_][%u%d_]*)%s*=")
    if name and oldSettings[name] then
      table.insert(out, oldSettings[name])
      local depth = braceDelta(line)
      while depth > 0 and i < #newSettings do
        i = i + 1
        depth = depth + braceDelta(newSettings[i])
      end
    else
      table.insert(out, line)
    end
    i = i + 1
  end
  for _, line in ipairs(rest) do table.insert(out, line) end
  local merged = table.concat(out, "\n")
  -- splitting added one trailing newline's worth of empty line; match the source
  if newSrc:sub(-1) == "\n" and merged:sub(-1) ~= "\n" then merged = merged .. "\n" end
  return (merged:gsub("\n\n$", "\n"))
end

local function fetch(url, headers)
  local ok, h = pcall(http.get, url, headers)
  if not ok or not h then return nil end
  local body = h.readAll()
  h.close()
  return body
end

local function readText(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  local t = f.readAll()
  f.close()
  return t
end

local function writeText(path, text)
  local f = fs.open(path, "w")
  f.write(text)
  f.close()
end

local function checkForUpdate(atBoot)
  if AUTO_UPDATE == false or not http then return end
  local sha = fetch("https://api.github.com/repos/" .. UPDATE_REPO .. "/commits/main",
    { ["Accept"] = "application/vnd.github.sha", ["User-Agent"] = "cc-auto-update" })
  if not sha then return end
  sha = sha:match("^%s*(%x+)%s*$")
  if not sha or #sha < 40 or readText(SHA_FILE) == sha then return end

  local newSrc = fetch("https://raw.githubusercontent.com/" .. UPDATE_REPO .. "/" .. sha .. "/" .. UPDATE_FILE)
  if not newSrc or not load(newSrc, UPDATE_FILE) then return end
  local oldSrc = readText(PROGRAM_PATH)
  if not oldSrc then return end
  local merged = mergeSettings(oldSrc, newSrc)
  if not load(merged, UPDATE_FILE) then return end
  if merged == oldSrc then
    writeText(SHA_FILE, sha)
    return
  end

  -- at boot nothing is running yet, so there is nothing to wait for
  while not atBoot and not readyToUpdate() do sleep(5) end
  writeText(PROGRAM_PATH .. ".old", oldSrc)
  writeText(PROGRAM_PATH, merged)
  writeText(SHA_FILE, sha)
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  print("Updated to " .. sha:sub(1, 7) .. ", restarting...")
  if not atBoot then sleep(1) end
  os.reboot()
end

local function updateLoop()
  while true do
    sleep(UPDATE_CHECK_MINUTES * 60)
    pcall(checkForUpdate)
  end
end

-- Check for a new version as soon as the computer starts, before the
-- program runs, so a restart always picks up the latest version.
local function bootUpdate()
  if AUTO_UPDATE == false or not http then return end
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  print("Checking for updates...")
  pcall(checkForUpdate, true)
end


table.insert(loops, updateLoop)
bootUpdate()
parallel.waitForAny(table.unpack(loops))
