-- controller.lua
local STATE_FILE = "controller_state.txt"
local shaftsWide, shaftsLong, shaftSpacing = 4, 4, 3
local totalJobs = shaftsWide * shaftsLong

-- find modem side (wired or wireless)
local modemSide
for _, side in ipairs({"left","right","top","bottom","front","back"}) do
  local t = peripheral.getType(side)
  if t and t:match("modem") then
    modemSide = side
    break
  end
end
if not modemSide then error("No modem attached") end
rednet.open(modemSide)

-- persistent state
local jobQueue = {}
local activeTasks = {}    -- label -> { job=..., status=... }
local paused = {}         -- label -> true
local finishedCount = 0
local labelToID = {}      -- label -> rednet ID
local idToLabel = {}      -- rednet ID -> label

local function saveState()
  local h = fs.open(STATE_FILE, "w")
  h.write(textutils.serialize({
    jobQueue = jobQueue,
    activeTasks = activeTasks,
    paused = paused,
    finishedCount = finishedCount,
    labelToID = labelToID,
    idToLabel = idToLabel,
  }))
  h.close()
end

local function loadState()
  if not fs.exists(STATE_FILE) then return false end
  local h = fs.open(STATE_FILE, "r")
  local ok, data = pcall(textutils.unserialize, h.readAll())
  h.close()
  if not ok or type(data) ~= "table" then return false end
  jobQueue = data.jobQueue or {}
  activeTasks = data.activeTasks or {}
  paused = data.paused or {}
  finishedCount = data.finishedCount or 0
  labelToID = data.labelToID or {}
  idToLabel = data.idToLabel or {}
  return true
end

-- initialize job queue if fresh
local resumed = loadState()
if not resumed then
  for z = 0, shaftsLong - 1 do
    for x = 0, shaftsWide - 1 do
      table.insert(jobQueue, { x = x * shaftSpacing, z = z * shaftSpacing })
    end
  end
  saveState()
end

local function clearScreen()
  term.clear()
  term.setCursorPos(1, 1)
end

local function drawGUI()
  clearScreen()
  print("=== Mining Grid Controller ===")
  print(("Total shafts: %d  Completed: %d  Progress: %d%%"):format(
    totalJobs, finishedCount, math.floor(finishedCount / totalJobs * 100)))
  print("\nTurtles:")
  for label, info in pairs(activeTasks) do
    local status = info.status or "unknown"
    local job = info.job or {}
    print(("- %s: %s (X=%d Z=%d)"):format(label, status, job.x or -1, job.z or -1))
  end
  for label,_ in pairs(labelToID) do
    if not activeTasks[label] and not paused[label] then
      print(("- %s: idle"):format(label))
    end
  end
  if next(paused) then
    print("\nPaused (chest full):")
    for label,_ in pairs(paused) do
      print("  * "..label)
    end
    print("Type 'resume' to continue paused turtles.")
  end
  print("\nCommands: resume | setdepth <label> <maxDepth>")
end

local function assignNext(label)
  if #jobQueue == 0 then return end
  local job = table.remove(jobQueue, 1)
  local id = labelToID[label]
  if not id then return end
  rednet.send(id, textutils.serialize({ event = "job", job = job }))
  activeTasks[label] = { job = job, status = "mining" }
  saveState()
end

-- input loop
local function keyboardLoop()
  while true do
    local line = read()
    local cmd, rest = line:match("^(%S+)%s*(.*)$")
    if cmd == "resume" then
      for label,_ in pairs(paused) do
        local id = labelToID[label]
        if id then
          rednet.send(id, "resume")
          if activeTasks[label] then activeTasks[label].status = "resuming" end
        end
      end
      paused = {}
      saveState()
    elseif cmd == "setdepth" then
      local label, depth = rest:match("^(%S+)%s*(%d+)$")
      if label and depth then
        depth = tonumber(depth)
        if labelToID[label] then
          rednet.send(labelToID[label], textutils.serialize({ event = "set_depth", maxDepth = depth }))
          activeTasks[label] = { job = { type = "depth", maxDepth = depth }, status = "mining" }
          saveState()
        else
          print("Unknown turtle label: "..tostring(label))
        end
      else
        print("Usage: setdepth <label> <maxDepth>")
      end
    end
  end
end

-- network loop
local function networkLoop()
  while true do
    local senderId, msg = rednet.receive()
    local ok, data = pcall(textutils.unserialize, msg)
    if ok and type(data) == "table" then
      if data.event == "hello" and data.sender then
        labelToID[data.sender] = senderId
        idToLabel[senderId] = data.sender
        if not activeTasks[data.sender] and not paused[data.sender] then
          assignNext(data.sender)
        end
        saveState()
      elseif data.event == "done" and data.sender then
        local label = data.sender
        finishedCount = finishedCount + 1
        activeTasks[label] = nil
        assignNext(label)
        saveState()
      elseif data.event == "chest_full" and data.sender then
        paused[data.sender] = true
        if activeTasks[data.sender] then activeTasks[data.sender].status = "paused" end
        saveState()
      elseif data.event == "error" and data.sender then
        if activeTasks[data.sender] then
          activeTasks[data.sender].status = "error:" .. (data.code or "unknown")
        end
        saveState()
      end
    else
      -- fallback for raw done
      if msg == "done" then
        local label = idToLabel[senderId]
        if label then
          finishedCount = finishedCount + 1
          activeTasks[label] = nil
          assignNext(label)
          saveState()
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
    print("\nAll shafts completed.")
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
  end,
  keyboardLoop,
  networkLoop
)
