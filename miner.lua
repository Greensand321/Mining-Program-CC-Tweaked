-- miner.lua (with set_depth support, structured messaging, label check, stage recovery, delayed retry on dump resume, manual-complete control)

local STATE_FILE = "state.txt"
local FUEL_SLOT = 16
local CHEST_DISTANCE = 5

local label = os.getComputerLabel()
if not label then
  print("ERROR: Turtle must have a label. Use os.setComputerLabel('minerX')")
  return
end

-- manual state clear: run with 'clear' to wipe stored state after completion
local args = { ... }
if args[1] == "clear" then
  if fs.exists(STATE_FILE) then
    fs.delete(STATE_FILE)
    print("State cleared manually.")
  else
    print("No state to clear.")
  end
  return
end

-- open modem (auto-detect)
local modemSideName
for _, side in ipairs({"left","right","top","bottom","front","back"}) do
  if peripheral.getType(side) == "modem" then
    modemSideName = side
    break
  end
end
if not modemSideName then
  print("ERROR: No modem found.")
  return
end
rednet.open(modemSideName)

local function saveState(state)
  local h = fs.open(STATE_FILE, "w")
  h.write(textutils.serialize(state))
  h.close()
end

local function loadState()
  if not fs.exists(STATE_FILE) then return nil end
  local h = fs.open(STATE_FILE, "r")
  local data = textutils.unserialize(h.readAll())
  h.close()
  return data
end

local function clearState()
  if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
end

local function refuelIfNeeded()
  if turtle.getFuelLevel() == "unlimited" then return end
  if turtle.getFuelLevel() < 100 then
    turtle.select(FUEL_SLOT)
    if not turtle.refuel() then
      print("WARNING: Unable to refuel; no fuel in slot " .. FUEL_SLOT .. ".")
    end
  end
end

local function moveForwardN(n)
  for i = 1, n do
    while not turtle.forward() do
      turtle.dig()
      turtle.attack()
      sleep(0.2)
    end
  end
end

local function digDown()
  while not turtle.down() do
    turtle.digDown()
    if turtle.attackDown then turtle.attackDown() end
    sleep(0.2)
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
        print("Dump still failing; waiting 1s before next resume attempt.")
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

local function mineShaft(task)
  local depth = task.depth or 0
  while true do
    -- respect maxDepth if provided
    if task.maxDepth and depth >= task.maxDepth then break end
    while turtle.detectDown() and not pcall(digDown) do
      -- if digDown fails, break
      break
    end
    -- clear surroundings
    turtle.dig()
    turtle.digUp()
    turtle.turnRight()
    turtle.dig()
    turtle.turnLeft()
    turtle.turnLeft()
    turtle.dig()
    turtle.turnRight()

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

local task = loadState()
if task and task.stage == "dumping" then
  print("Recovering from dump stage...")
  dumpInventory(task)
elseif not task then
  print("Waiting for task...")
  local _, msg = rednet.receive()
  local incoming = textutils.unserialize(msg)
  if type(incoming) == "table" and incoming.event == "set_depth" and type(incoming.maxDepth) == "number" then
    task = { x = 0, z = 0, depth = 0, stage = "mining", maxDepth = incoming.maxDepth }
  else
    task = incoming
    if not task or type(task) ~= "table" or not task.x or not task.z then
      print("ERROR: Invalid task received.")
      return
    end
    task.depth = 0
    task.stage = "mining"
  end
end

print("Starting shaft: X=" .. (task.x or 0) .. ", Z=" .. (task.z or 0) .. (task.maxDepth and (" maxDepth=" .. task.maxDepth) or ""))
refuelIfNeeded()

-- move to shaft start if needed
if task.x and task.z then
  turtle.turnRight()
  moveForwardN(task.x)
  turtle.turnLeft()
  moveForwardN(task.z)
end

mineShaft(task)

-- return to origin
if task.x and task.z then
  turtle.turnLeft()
  moveForwardN(task.x)
  turtle.turnLeft()
  moveForwardN(task.z)
end

-- mark complete (user must manually clear)
task.stage = "complete"
saveState(task)

dumpInventory(task)
rednet.send(0, "done")
