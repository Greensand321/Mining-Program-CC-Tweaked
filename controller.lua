-- controller_with_handshake.lua (persistent, depth assignment, label handshake, and using numeric IDs)

local STATE_FILE = "controller_state.txt"
local shaftsWide = 4
local shaftsLong = 4
local shaftSpacing = 3

-- expected turtle labels (can expand or replace with dynamic discovery)
local turtleLabels = { "miner1", "miner2", "miner3", "miner4" }

-- mappings: label -> numeric rednet ID
local turtleIDs = {}
local activeTasks = {} -- label -> { job, status }
local pausedTurtles = {}
local finishedCount = 0
local totalJobs = shaftsWide * shaftsLong
local jobQueue = {}

-- load / save state
local function saveControllerState()
  local data = { jobQueue = jobQueue, activeTasks = activeTasks, finishedCount = finishedCount, pausedTurtles = pausedTurtles }
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

-- initialize job queue if fresh
local resumed = loadControllerState()
if not resumed then
  for z = 0, shaftsLong - 1 do
    for x = 0, shaftsWide - 1 do
      table.insert(jobQueue, { x = x * shaftSpacing, z = z * shaftSpacing })
    end
  end
end

-- networking setup (auto-detect modem)
local modemSide
for _, side in ipairs({"left","right","top","bottom","front","back"}) do
  if peripheral.getType(side) == "modem" then
    modemSide = side
    break
  end
end
if not modemSide then
  print("ERROR: No modem attached to controller.")
  return
end
rednet.open(modemSideName)
-- announce presence to controller
rednet.send(0, textutils.serialize({ event = "hello", sender = label }))

-- GUI
local function clearScreen()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1,1)
end
local function centerPrint(str)
  local w,_ = term.getSize()
  local x = math.floor((w - #str)/2)
  term.setCursorPos(x, select(2, term.getCursorPos()))
  print(str)
end
local function drawGUI()
  clearScreen()
  centerPrint("=== Mining Grid Controller ===")
  print(string.format("Total Shafts: %d", totalJobs))
  print(string.format("Completed: %d / %d", finishedCount, totalJobs))
  print(string.format("Progress: %d%%", math.floor((finishedCount/totalJobs)*100)))
  print("
Active Turtles:")
  for _, label in ipairs(turtleLabels) do
    local task = activeTasks[label]
    local status = "idle"
    if task then status = task.status end
    local line = "- " .. label .. ": " .. status
    if task and task.job then
      line = line .. string.format(" (X=%s,Z=%s", tostring(task.job.x or "?"), tostring(task.job.z or "?"))
      if task.job.maxDepth then line = line .. ", depthLimit=" .. task.job.maxDepth end
      line = line .. ")"
    end
    if pausedTurtles[label] then line = line .. " [PAUSED]" end
    print(line)
  end
  print("
Commands: resume | setdepth <turtleLabel> <maxDepth>")
end

-- assignment logic
local function assignJobToLabel(label)
  if not turtleIDs[label] then return end
  if activeTasks[label] then return end
  if #jobQueue == 0 then return end
  local job = table.remove(jobQueue,1)
  rednet.send(turtleIDs[label], textutils.serialize(job))
  activeTasks[label] = { job = job, status = "mining" }
  saveControllerState()
end

-- Event loop handlers
local function keyboardListener()
  while true do
    local input = read()
    local parts = {}
    for w in input:gmatch("%S+") do table.insert(parts, w) end
    if parts[1] == "resume" then
      for label,_ in pairs(pausedTurtles) do
        if turtleIDs[label] then
          rednet.send(turtleIDs[label], "resume")
          if activeTasks[label] then activeTasks[label].status = "resuming" end
        end
      end
      pausedTurtles = {}
      saveControllerState()
    elseif (parts[1] == "setdepth" or parts[1] == "depth") and parts[2] and parts[3] then
      local label = parts[2]
      local depth = tonumber(parts[3])
      if not depth then print("Invalid depth")
      elseif not turtleIDs[label] then print("Unknown turtle: "..label)
      else
        rednet.send(turtleIDs[label], textutils.serialize({ event = "set_depth", maxDepth = depth }))
        activeTasks[label] = { job = { x=0, z=0, maxDepth = depth }, status = "mining to depth "..depth }
        saveControllerState()
        print("Sent depth job to "..label)
      end
    end
  end
end

local function networkListener()
  while true do
    local senderId, msg = rednet.receive()
    local data = (type(msg) == "string" and pcall(textutils.unserialize, msg)) and textutils.unserialize(msg) or {}
    if type(data) == "table" and data.sender then
      local label = data.sender
      -- register if hello
      if data.event == "hello" then
        turtleIDs[label] = senderId
        -- assign initial job if any pending
        assignJobToLabel(label)
      elseif data.event == "done" then
        finishedCount = finishedCount + 1
        activeTasks[label] = nil
        assignJobToLabel(label)
        saveControllerState()
      elseif data.event == "chest_full" then
        pausedTurtles[label] = true
        if activeTasks[label] then activeTasks[label].status = "paused (waiting)" end
        saveControllerState()
      end
    elseif type(msg) == "string" and msg == "done" then
      -- fallback if turtle sent raw done: deduce label from known id mapping
      for lab,id in pairs(turtleIDs) do
        if id == senderId then
          finishedCount = finishedCount + 1
          activeTasks[lab] = nil
          assignJobToLabel(lab)
          saveControllerState()
          break
        end
      end
    end
  end
end

-- main
parallel.waitForAny(
  function()
    while finishedCount < totalJobs do
      drawGUI()
      sleep(1)
    end
    drawGUI()
    print("
✅ All mining shafts completed!")
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
  end,
  keyboardListener,
  networkListener
)
