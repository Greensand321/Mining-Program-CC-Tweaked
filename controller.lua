-- controller.lua (with persistent recovery and manual depth assignment)

local STATE_FILE = "controller_state.txt"
local shaftsWide = 4
local shaftsLong = 4
local shaftSpacing = 3
local turtleNames = { "miner1", "miner2", "miner3", "miner4" }

rednet.open("left")

local jobQueue = {}
local activeTasks = {}
local finishedCount = 0
local pausedTurtles = {}
local totalJobs = shaftsWide * shaftsLong

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

local resumed = loadControllerState()
if not resumed then
  for z = 0, shaftsLong - 1 do
    for x = 0, shaftsWide - 1 do
      table.insert(jobQueue, { x = x * shaftSpacing, z = z * shaftSpacing })
    end
  end
end

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
  print("\nActive Turtles:")
  for _, name in ipairs(turtleNames) do
    local task = activeTasks[name]
    if task then
      print("- " .. name .. ": " .. (task.status or "working") .. (task.job and (" (X=" .. (task.job.x or 0) .. ", Z=" .. (task.job.z or 0) .. (task.job.maxDepth and ", depthLimit=" .. task.job.maxDepth or "") .. ")") or ""))
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
  print("\nCommands:")
  print("  resume")
  print("  setdepth <turtleLabel> <maxDepth>")
end

local function assignNextJob(turtleName)
  if #jobQueue == 0 then return end
  local job = table.remove(jobQueue, 1)
  rednet.send(turtleName, textutils.serialize(job))
  activeTasks[turtleName] = { job = job, status = "mining" }
  saveControllerState()
end

local function keyboardListener()
  while true do
    local input = read()
    local parts = {}
    for word in input:gmatch("%S+") do table.insert(parts, word) end
    if parts[1] == "resume" then
      for name, _ in pairs(pausedTurtles) do
        rednet.send(name, "resume")
        if activeTasks[name] then activeTasks[name].status = "resuming" end
      end
      pausedTurtles = {}
      saveControllerState()
    elseif (parts[1] == "setdepth" or parts[1] == "depth") and parts[2] and parts[3] then
      local turtleName = parts[2]
      local depth = tonumber(parts[3])
      if not depth then
        print("Invalid depth: " .. parts[3])
      else
        rednet.send(turtleName, textutils.serialize({ event = "set_depth", maxDepth = depth }))
        activeTasks[turtleName] = { job = { x = 0, z = 0, maxDepth = depth }, status = "mining to depth " .. depth }
        saveControllerState()
        print("Sent depth " .. depth .. " job to " .. turtleName)
      end
    end
  end
end

local function networkListener()
  while true do
    local _, msg = rednet.receive()
    local data = type(msg) == "string" and textutils.unserialize(msg) or {}
    if type(data) == "table" and data.sender then
      local sender = data.sender
      if data.event == "done" then
        finishedCount = finishedCount + 1
        activeTasks[sender] = nil
        assignNextJob(sender)
        saveControllerState()
      elseif data.event == "chest_full" then
        pausedTurtles[sender] = true
        if activeTasks[sender] then activeTasks[sender].status = "paused (waiting)" end
        saveControllerState()
      end
    end
  end
end

-- MAIN LOOP
parallel.waitForAny(
  function()
    if not resumed then
      for _, name in ipairs(turtleNames) do assignNextJob(name) end
    end
    while finishedCount < totalJobs do
      drawGUI()
      sleep(1)
    end
    drawGUI()
    print("\n✅ All mining shafts completed!")
    fs.delete(STATE_FILE)
  end,
  keyboardListener,
  networkListener
)
