-- Updated miner.lua: GPS-aware chunk-center navigation and straight shaft mining

-- miner.lua (with GPS chunk navigation, bedrock detection, chunk report, simplified shaft)

-- configuration
local STATE_FILE = "state.txt"
local FUEL_SLOT = 16
local CHEST_DISTANCE = 5
local BUILD_SURFACE_WALL = true  -- toggle surface perimeter wall

local label = os.getComputerLabel()
if not label or label == "" then
  print("ERROR: Turtle must have a label. Use 'label set <name>'")
  return
end

-- find modem side
local modemSide
for _, side in ipairs({"left","right","top","bottom","front","back"}) do
  if peripheral.getType(side) and peripheral.getType(side):match("modem") then
    modemSide = side
    break
  end
end
if not modemSide then
  print("ERROR: No modem attached")
  return
end
rednet.open(modemSide)

local haveTask = false
local task = nil
local orientation = nil  -- 0=+X,1=+Z,2=-X,3=-Z

local function sendEvent(event, extra)
  local payload = { event = event, sender = label }
  if extra then
    for k,v in pairs(extra) do payload[k] = v end
  end
  rednet.broadcast(textutils.serialize(payload))
end

local function saveState(state)
  local h = fs.open(STATE_FILE, "w")
  h.write(textutils.serialize(state))
  h.close()
end

local function loadState()
  if not fs.exists(STATE_FILE) then return nil end
  local h = fs.open(STATE_FILE, "r")
  local ok, data = pcall(textutils.unserialize, h.readAll())
  h.close()
  if ok and type(data) == "table" then
    return data
  end
  return nil
end

local function clearState()
  if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
end

local function refuelIfNeeded()
  if turtle.getFuelLevel() == "unlimited" then return end
  if turtle.getFuelLevel() < 100 then
    turtle.select(FUEL_SLOT)
    if not turtle.refuel() then
      sendEvent("error", { code = "F01", detail = "out of fuel" })
    end
  end
end

local function moveForwardN(n)
  for i = 1, n do
    local retries = 0
    while not turtle.forward() do
      turtle.dig()
      turtle.attack()
      retries = retries + 1
      if retries > 5 then
        sendEvent("error", { code = "T02", detail = "forward blocked" })
        sleep(1)
        retries = 0
      else
        sleep(0.2)
      end
    end
  end
end

local function digDown()
  local retries = 0
  while not turtle.down() do
    turtle.digDown()
    if turtle.attackDown then turtle.attackDown() end
    retries = retries + 1
    if retries > 5 then
      sendEvent("error", { code = "T03", detail = "down blocked" })
      sleep(1)
      retries = 0
    else
      sleep(0.2)
    end
  end
end

local function isInventoryFull()
  for i = 1, 15 do
    if turtle.getItemCount(i) == 0 then return false end
  end
  return true
end

local function tryDropAll()
  for i = 1, 15 do
    turtle.select(i)
    if not turtle.drop() then return false end
  end
  return true
end

local function isBedrockBelow()
  local ok, data = turtle.inspectDown()
  if ok and data and data.name:lower():find("bedrock") then
    return true
  end
  return false
end

local function dumpInventory(task)
  task.stage = "dumping"
  saveState(task)

  turtle.turnRight()
  moveForwardN(CHEST_DISTANCE)
  local chestFull = false

  if not tryDropAll() then
    if turtle.detectUp() then
      turtle.up()
      if not tryDropAll() then chestFull = true end
      turtle.down()
    else
      chestFull = true
    end
  end

  if chestFull then
    sendEvent("chest_full")
    print("Chest full. Waiting for resume...")
    while true do
      local _, msg = rednet.receive()
      if msg == "resume" then
        if tryDropAll() then break end
        if turtle.detectUp() then
          turtle.up()
          if tryDropAll() then turtle.down(); break end
          turtle.down()
        end
        sleep(1)
      end
    end
  end

  turtle.turnLeft()
  for i = 1, CHEST_DISTANCE do turtle.back() end
  turtle.turnLeft()
  task.stage = "mining"
  saveState(task)
end

local function detectOrientation()
  local x1,y1,z1 = gps.locate(5)
  if not x1 then return end
  -- try to move forward one block to infer facing
  local moved = false
  for i = 1, 3 do
    if turtle.forward() then
      moved = true
      break
    else
      turtle.dig()
      turtle.attack()
      sleep(0.2)
    end
  end
  if not moved then return end
  local x2,y2,z2 = gps.locate(5)
  -- return to original spot
  turtle.back()
  if not (x2 and x1) then return end
  local dx = x2 - x1
  local dz = z2 - z1
  if math.abs(dx) > math.abs(dz) then
    if dx > 0 then orientation = 0 else orientation = 2 end
  else
    if dz > 0 then orientation = 1 else orientation = 3 end
  end
end

local function faceDirection(targetDir)
  if orientation == nil then return end
  local diff = (targetDir - orientation) % 4
  if diff == 1 then
    turtle.turnRight()
  elseif diff == 2 then
    turtle.turnRight(); turtle.turnRight()
  elseif diff == 3 then
    turtle.turnLeft()
  end
  orientation = targetDir
end

local function moveDelta(dx, dz)
  -- X axis: +X = 0, -X = 2
  if dx ~= 0 then
    if dx > 0 then faceDirection(0) else faceDirection(2) end
    moveForwardN(math.abs(dx))
  end
  if dz ~= 0 then
    if dz > 0 then faceDirection(1) else faceDirection(3) end
    moveForwardN(math.abs(dz))
  end
end

local function round(n)
  return math.floor(n + 0.5)
end

local function goToChunkCenter(chunkX, chunkZ)
  local targetX = chunkX * 16 + 8
  local targetZ = chunkZ * 16 + 8
  local tx,ty,tz = gps.locate(5)
  if not tx then
    sendEvent("error", { code = "G01", detail = "GPS unavailable" })
    error("GPS needed for chunk navigation but unavailable")
  end
  if not orientation then detectOrientation() end
  local deltaX = round(targetX) - round(tx)
  local deltaZ = round(targetZ) - round(tz)
  moveDelta(deltaX, deltaZ)
  -- verify position, small correction if needed
  local cx,cy,cz = gps.locate(5)
  if cx then
    local fixX = round(targetX) - round(cx)
    local fixZ = round(targetZ) - round(cz)
    if fixX ~= 0 or fixZ ~= 0 then
      moveDelta(fixX, fixZ)
    end
  end
  -- report chunk alignment
  local finalX,fy,finalZ = gps.locate(5)
  if finalX then
    local actualChunkX = math.floor(finalX / 16)
    local actualChunkZ = math.floor(finalZ / 16)
    sendEvent("chunk_report", { assignedChunkX = chunkX, assignedChunkZ = chunkZ, actualChunkX = actualChunkX, actualChunkZ = actualChunkZ })
  end
end

local function mineShaft(task, maxDepth)
  local depth = task.depth or 0
  while true do
    if maxDepth and depth >= maxDepth then break end
    if isBedrockBelow() then break end
    digDown()
    depth = depth + 1
    task.depth = depth
    task.stage = "mining"
    saveState(task)
    if isInventoryFull() then
      for i = 1, depth do turtle.up() end
      dumpInventory(task)
      for i = 1, depth do turtle.down() end
    end
  end
  -- return to surface
  for i = 1, depth do turtle.up() end
end

-- recover if was mid-dump
local persisted = loadState()
if persisted and persisted.stage == "dumping" then
  task = persisted
  print("Recovering from dump stage...")
  dumpInventory(task)
end

-- handshake broadcaster
local function handshakeLoop()
  while not haveTask do
    sendEvent("hello")
    sleep(3)
  end
end

-- message receiver
local function receiveLoop()
  while true do
    local _, msg = rednet.receive()
    local ok, data = pcall(textutils.unserialize, msg)
    if ok and type(data) == "table" then
      if data.event == "job" then
        haveTask = true
        task = data.job
        task.depth = task.depth or 0
        task.stage = "mining"
      elseif data.event == "set_depth" then
        haveTask = true
        task = { x = 0, z = 0, depth = 0, stage = "mining", maxDepth = data.maxDepth }
      elseif data.event == "whois" then
        sendEvent("hello")
      elseif data.event == "resume" then
        -- will naturally continue if stalled
      elseif data.event == "ping" then
        sendEvent("pong")
      end
    end
    if haveTask then break end
  end
end

parallel.waitForAny(handshakeLoop, receiveLoop)

if not task then
  print("No task received, aborting.")
  return
end

print("Starting task:", textutils.serialize(task))
refuelIfNeeded()

-- Navigation: if chunk job provided, go to its center
if task.chunkX and task.chunkZ then
  -- move to chunk center
  goToChunkCenter(task.chunkX, task.chunkZ)
  -- build surface wall if desired
  if BUILD_SURFACE_WALL then
    -- requires a block in slot 1
    turtle.select(1)
    -- place perimeter around current position
    for i = 1, 4 do
      turtle.turnRight()
      if not turtle.detect() then
        turtle.place()
      end
    end
  end
else
  -- legacy movement using relative x,z
  if task.x and task.z then
    turtle.turnRight() moveForwardN(task.x)
    turtle.turnLeft() moveForwardN(task.z)
  end
end

mineShaft(task, task.maxDepth)

-- return to origin (best-effort)
if task.x and task.z then
  turtle.turnLeft() turtle.turnLeft()
  if task.z then moveForwardN(task.z) end
  turtle.turnRight()
  if task.x then moveForwardN(task.x) end
  turtle.turnLeft()
end

task.stage = "complete"
saveState(task)
clearState()
-- dump inventory before exit
dumpInventory(task)
sendEvent("done", { chunkX = task.chunkX, chunkZ = task.chunkZ })
