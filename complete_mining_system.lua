-- complete_mining_system.lua
-- Contains both the Master Controller and Miner Turtle scripts in one file for reference.
-- Split and save as separate programs: controller.lua (master) and miner.lua (turtle).

-- =========================
-- MASTER CONTROLLER (controller.lua)
-- =========================

local function showSetupGuide()
  print("=== Setup Guide ===")
  print("1. Ensure you have CC: Tweaked installed with rednet-capable modems (wired or wireless) on the controller and each turtle.")
  print("2. Attach a modem to the controller computer; this script auto-detects its side.")
  print("3. Label each turtle to match the names in turtleNames (defaults: miner1, miner2, miner3, miner4) using: os.setComputerLabel('minerX')")
  print("4. Place and start each turtle with its miner.lua script; the turtles should be positioned at their assigned start of mining grid. Supply fuel in slot 16 and torches/chests as configured.")
  print("5. Turtles dump into a chest located 5 blocks to the right of the main computer; if that chest is full they check above it. On full, they pause and send a notification.")
  print("6. Run the controller (this program) first, then the turtles. Use 'resume' on the controller to resume paused turtles after clearing chests.")
  print("7. To clear a turtle's stored completed state manually, run miner.lua with argument 'clear' on that turtle.")
  print("8. Monitor progress here; errors are annotated per turtle.
")
end

showSetupGuide()

-- master_controller.lua (with persistent recovery and error/event code awareness)

local STATE_FILE = "controller_state.txt"
local shaftsWide = 4
local shaftsLong = 4
local shaftSpacing = 3
local turtleNames = { "miner1", "miner2", "miner3", "miner4" }

-- Standard error/event definitions (mirrors turtle codes)
local errorDefinitions = {
  T01 = { msg = "Invalid task received", severity = "High" },
  T02 = { msg = "Forward movement blocked after retries", severity = "High" },
  T03 = { msg = "Up/Down movement blocked after retries", severity = "High" },
  D01 = { msg = "Chest initially full", severity = "Medium" },
  D02 = { msg = "Dump retry failed after resume attempt", severity = "Medium" },
  F01 = { msg = "Unable to refuel", severity = "Medium" },
  R01 = { msg = "State file corrupted and backed up", severity = "Low" },
  C01 = { msg = "Communication issue / controller unreachable", severity = "High" },
}

-- auto-detect modem side for controller
local modemSideName
for _, side in ipairs({"left","right","top","bottom","front","back"}) do
  if peripheral.getType(side) == "modem" then
    modemSideName = side
    break
  end
end
if not modemSideName then
  print("ERROR: No modem found on controller.")
  return
end
rednet.open(modemSideName)

-- === STATE ===
local jobQueue = {}
local activeTasks = {}
local finishedCount = 0
local pausedTurtles = {}
local totalJobs = shaftsWide * shaftsLong

-- === PERSISTENCE ===
local function saveControllerState()
  local data = {
    jobQueue = jobQueue,
    activeTasks = activeTasks,
    finishedCount = finishedCount,
    pausedTurtles = pausedTurtles
  }
  local h = fs.open(STATE_FILE, "w")
  h.write(textutils.serialize(data))
  h.close()
end

local function loadControllerState()
  if not fs.exists(STATE_FILE) then return false end
  local h = fs.open(STATE_FILE, "r")
  local data = textutils.unserialize(h.readAll())
  h.close()
  jobQueue = data.jobQueue or {}
  activeTasks = data.activeTasks or {}
  finishedCount = data.finishedCount or 0
  pausedTurtles = data.pausedTurtles or {}
  return true
end

-- === INIT STATE ===
local resumed = loadControllerState()
if not resumed then
  for z = 0, shaftsLong - 1 do
    for x = 0, shaftsWide - 1 do
      table.insert(jobQueue, { x = x * shaftSpacing, z = z * shaftSpacing })
    end
  end
end

-- === GUI ===
local function clearScreen()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
end

local function centerPrint(str)
  local w, _ = term.getSize()
  local x = math.floor((w - #str) / 2)
  term.setCursorPos(x, select(2, term.getCursorPos()))
  print(str)
end

local function drawGUI()
  clearScreen()
  centerPrint("=== Mining Grid Controller ===")
  print("Total Shafts: " .. totalJobs)
  print("Completed: " .. finishedCount .. " / " .. totalJobs)
  print("Progress: " .. math.floor((finishedCount / totalJobs) * 100) .. "%")
  print("
Active Turtles:")
  for _, name in ipairs(turtleNames) do
    local task = activeTasks[name]
    if task then
      local status = task.status or "working"
      local line = "- " .. name .. ": " .. status .. " (X=" .. task.job.x .. ", Z=" .. task.job.z .. ")"
      if task.lastError then
        line = line .. "  [ERROR " .. task.lastError.code .. ": " .. (task.lastError.description or "") .. "]"
      end
      print(line)
    else
      print("- " .. name .. ": idle")
    end
  end

  if next(pausedTurtles) then
    print("
⚠️ Paused (chest full):")
    for name, _ in pairs(pausedTurtles) do
      print("  > " .. name)
    end
    print("Type 'resume' to continue paused turtles.")
  end
end
      print("")
    else
      print("- " .. name .. ": idle")
    end
  end

  if next(pausedTurtles) then
    print("\n⚠️ Paused (chest full):")
    for name, _ in pairs(pausedTurtles) do
      print("  > " .. name)
    end
    print("Type 'resume' to continue paused turtles.")
  end
end

local function assignNextJob(turtleName)
  if #jobQueue == 0 then return end
  local job = table.remove(jobQueue, 1)
  rednet.send(turtleName, textutils.serialize(job))
  activeTasks[turtleName] = { job = job, status = "mining" }
  saveControllerState()
end

-- === INPUT ===
local function keyboardListener()
  while true do
    -- respect explicit maxDepth if provided (stop when reached)
    if task and task.maxDepth and (task.depth or 0) >= task.maxDepth then break end
    if turtle.detectDown() and not safeDown() then break end
    -- clear immediate surroundings
    turtle.dig()
    turtle.digUp()
    turtle.turnRight()
    turtle.dig()
    turtle.turnLeft()
    turtle.turnLeft()
    turtle.dig()
    turtle.turnRight()

    if not digDown(task) then
      return
    end
    depth = depth + 1
    task.depth = depth
    task.stage = "mining"
    saveState(task)

    if isInventoryFull() then
      for i = 1, depth do
        if not safeUp() then break end
      end
      dumpInventory(task)
      for i = 1, depth do
        if not safeDown() then break end
      end
    end
  end
  for i = 1, depth do
    if not safeUp() then break end
  end
  print("Recovering from dump stage...")
  dumpInventory(task)
elseif not task then
  print("Waiting for task...")
  local _, msg = rednet.receive()
  task = textutils.unserialize(msg)
  if not task or type(task) ~= "table" or not task.x or not task.z then
    print("ERROR: Invalid task received, aborting.")
    sendError("T01", "received malformed task")
    return
  end
  task.depth = 0
  task.stage = "mining"
end

print("Starting shaft: X=" .. task.x .. ", Z=" .. task.z)
refuelIfNeeded()

turtle.turnRight()
if not moveForwardN(task.x) then return end
 turtle.turnLeft()
if not moveForwardN(task.z) then return end

mineShaft(task)

-- return to origin

turtle.turnLeft()
if not moveForwardN(task.x) then end
 turtle.turnLeft()
if not moveForwardN(task.z) then end

-- mark complete but do NOT auto-clear; user must manually clear
 task.stage = "complete"
 saveState(task)

dumpInventory(task)
sendEvent("done", {})
