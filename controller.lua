-- miner.lua (with bedrock detection, automatic handshake retry, ping/pong, structured messaging, dumping/resume)

local STATE_FILE = "state.txt"
local FUEL_SLOT = 16
local CHEST_DISTANCE = 5

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

local function sendEvent(event, extra)
  local payload = { event = event, sender = label }
  if extra then
    for k,v in pairs(extra) do payload[k] = v end
  end
  rednet.send(0, textutils.serialize(payload))
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

local function mineShaft(task, maxDepth)
  local depth = task.depth or 0
  while true do
    if maxDepth and depth >= maxDepth then break end
    if isBedrockBelow() then break end

    turtle.dig()
    turtle.digUp()
    turtle.turnRight() turtle.dig() turtle.turnLeft()
    turtle.turnLeft() turtle.dig() turtle.turnRight()
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
if task.x and task.z then
  turtle.turnRight() moveForwardN(task.x)
  turtle.turnLeft() moveForwardN(task.z)
end
mineShaft(task, task.maxDepth)

-- return home
turtle.turnLeft() turtle.turnLeft()
if task.z then moveForwardN(task.z) end
turtle.turnRight()
if task.x then moveForwardN(task.x) end
turtle.turnLeft()

task.stage = "complete"
saveState(task)
dumpInventory(task)
clearState()
sendEvent("done")
