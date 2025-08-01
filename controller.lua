-- Updated controller.lua: GPS chunk-anchored job queue with fallback manual origin

local STATE_FILE = "controller_state.txt"
local chunksWide, chunksHigh = 4, 4  -- adjustable grid size in chunks

-- find modem
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

-- state containers
local jobQueue = {}
local activeTasks = {}    -- label -> { job=..., status=..., actualChunk=... }
local paused = {}         -- label -> true
local finishedCount = 0
local labelToID = {}      -- label -> rednet ID
local idToLabel = {}      -- rednet ID -> label
local suspendGUI = false
local connected = {}       -- label -> bool

local totalJobs = chunksWide * chunksHigh

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

local function verifyConnections()
  if next(labelToID) == nil then return end
  print("Verifying connected turtles...")
  local awaiting = {}
  for label, id in pairs(labelToID) do
    awaiting[label] = true
    rednet.send(id, textutils.serialize({ event = "ping" }))
  end
  local start = os.clock()
  while next(awaiting) and os.clock() - start < 4 do
    local sender, msg = rednet.receive(1)
    if sender then
      local ok, data = pcall(textutils.unserialize, msg)
      if ok and type(data) == "table" and data.event == "pong" and data.sender then
        connected[data.sender] = true
        awaiting[data.sender] = nil
      end
    end
  end
  for label,_ in pairs(awaiting) do
    connected[label] = false
  end
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

-- initialize job queue with GPS-based chunk origin or manual fallback
local resumed = loadState()
if not resumed then
  local baseChunkX, baseChunkZ
  local x,y,z = gps.locate(5)
  if x then
    baseChunkX = math.floor(x / 16)
    baseChunkZ = math.floor(z / 16)
    print(("Controller GPS located at chunk (%d, %d)"):format(baseChunkX, baseChunkZ))
  else
    print("WARNING: GPS locate failed. Please input base chunk coordinates manually.")
    write("Base chunk X: ")
    baseChunkX = tonumber(read())
    write("Base chunk Z: ")
    baseChunkZ = tonumber(read())
    if not baseChunkX or not baseChunkZ then
      error("Invalid manual chunk origin")
    end
  end
  for dz = 0, chunksHigh - 1 do
    for dx = 0, chunksWide - 1 do
      local chunkX = baseChunkX + dx
      local chunkZ = baseChunkZ + dz
      table.insert(jobQueue, { chunkX = chunkX, chunkZ = chunkZ })
    end
  end
  saveState()
end

verifyConnections()

local function clearScreen()
  term.clear()
  term.setCursorPos(1, 1)
end

local function drawGUI()
  clearScreen()
  print("=== GPS Chunk Mining Controller ===")
  print(("Total chunks: %d  Completed: %d  Progress: %d%%"):format(
    totalJobs, finishedCount, math.floor(finishedCount / totalJobs * 100)))
  print("\nTurtles:")
  for label, info in pairs(activeTasks) do
    local status = info.status or "unknown"
    if connected[label] == false then
      status = status .. " [OFFLINE]"
    end
    local job = info.job or {}
    local chunkDesc = "?"
    if job.chunkX then
      chunkDesc = ("C=(%d,%d)"):format(job.chunkX, job.chunkZ)
    elseif job.x and job.z then
      chunkDesc = ("legacy X=%d Z=%d"):format(job.x, job.z)
    end
    local actual = ""
    if info.actualChunk then
      actual = ("  actual C=(%d,%d)"):format(info.actualChunk.x, info.actualChunk.z)
    end
    print(('- %s: %s %s%s'):format(label, status, chunkDesc, actual))
  end
  for label,_ in pairs(labelToID) do
    if not activeTasks[label] and not paused[label] then
      local stat = connected[label] == false and "offline" or "idle"
      print(('- %s: %s'):format(label, stat))
    end
  end
  if next(paused) then
    print("\nPaused (chest full):")
    for label,_ in pairs(paused) do
      print("  * "..label)
    end
    print("Type 'resume' to continue paused turtles.")
  end
  print("\nCommands: resume | setdepth <label> <maxDepth> | ping <label> | list | help")
  print("Press ESC to enter command mode")
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

local function whoisBroadcaster()
  while finishedCount < totalJobs do
    rednet.broadcast(textutils.serialize({ event = "whois" }))
    sleep(3)
  end
end

local function drawSelectionMenu(selected, labels)
  clearScreen()
  print("Select Turtle (ESC for command)")
  for i,label in ipairs(labels) do
    local prefix = (i == selected) and "> " or "  "
    print(prefix .. label)
  end
  print("(Enter to open turtle menu, ESC for command)")
end

local function showTurtleMenu(label)
  local options = { "Ping", "Resume" }
  local idx = 1
  while true do
    clearScreen()
    print("["..label.."] Options (ESC to back)")
    for i,opt in ipairs(options) do
      local prefix = (i == idx) and "> " or "  "
      print(prefix .. opt)
    end
    local _, key = os.pullEvent("key")
    if key == keys.up then
      idx = math.max(1, idx-1)
    elseif key == keys.down then
      idx = math.min(#options, idx+1)
    elseif key == keys.enter then
      if options[idx] == "Ping" and labelToID[label] then
        rednet.send(labelToID[label], textutils.serialize({ event = "ping" }))
      elseif options[idx] == "Resume" and labelToID[label] then
        rednet.send(labelToID[label], "resume")
      end
      break
    elseif key == keys.escape then
      break
    end
  end
end

local function executeCommand(line)
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
  elseif cmd == "ping" then
    local label = rest:match("^(%S+)$")
    if label and labelToID[label] then
      rednet.send(labelToID[label], textutils.serialize({ event = "ping" }))
    else
      print("Unknown label; broadcasting ping.")
      rednet.broadcast(textutils.serialize({ event = "ping" }))
    end
  elseif cmd == "list" then
    print("Known turtles:")
    for label,id in pairs(labelToID) do
      local status = activeTasks[label] and activeTasks[label].status or (paused[label] and "paused" or "idle")
      print(('- %s -> ID %s : %s'):format(label, tostring(id), status))
    end
  elseif cmd == "help" then
    print("Commands: resume | setdepth <label> <maxDepth> | ping <label> | list | help")
  end
end

local function keyboardLoop()
  local mode = "menu"
  local selected = 1
  while true do
    if mode == "menu" then
      local labels = {}
      for l,_ in pairs(labelToID) do table.insert(labels, l) end
      table.sort(labels)
      if #labels == 0 then labels = {"<none>"} end
      if selected > #labels then selected = #labels end
      if selected < 1 then selected = 1 end
      suspendGUI = true
      drawSelectionMenu(selected, labels)
      local _, key = os.pullEvent("key")
      suspendGUI = false
      if key == keys.up then
        selected = math.max(1, selected-1)
      elseif key == keys.down then
        selected = math.min(#labels, selected+1)
      elseif key == keys.enter and labels[selected] and labels[selected] ~= "<none>" then
        showTurtleMenu(labels[selected])
      elseif key == keys.escape then
        mode = "command"
      end
    else
      suspendGUI = true
      write("> ")
      local line = read()
      suspendGUI = false
      if line then executeCommand(line) end
      mode = "menu"
    end
  end
end

local function networkLoop()
  while true do
    local senderId, msg = rednet.receive()
    local ok, data = pcall(textutils.unserialize, msg)
    if ok and type(data) == "table" then
      if data.event == "hello" and data.sender then
        labelToID[data.sender] = senderId
        idToLabel[senderId] = data.sender
        connected[data.sender] = true
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
      elseif data.event == "pong" and data.sender then
        connected[data.sender] = true
        print(("Received pong from %s"):format(data.sender))
      elseif data.event == "chunk_report" and data.sender then
        local label = data.sender
        if activeTasks[label] and activeTasks[label].job then
          -- Store actual chunk
          activeTasks[label].actualChunk = { x = data.actualChunkX, z = data.actualChunkZ }
          -- Compare assigned vs actual
          local assigned = activeTasks[label].job
          if assigned.chunkX and assigned.chunkZ then
            if assigned.chunkX ~= data.actualChunkX or assigned.chunkZ ~= data.actualChunkZ then
              activeTasks[label].status = "misaligned"
              print(("[WARN] Turtle %s assigned chunk (%d,%d) but reports being at (%d,%d)"):format(
                label, assigned.chunkX, assigned.chunkZ, data.actualChunkX, data.actualChunkZ))
            else
              activeTasks[label].status = "on target"
            end
          end
          saveState()
        end
      end
    else
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

-- main loop
parallel.waitForAny(
  function()
    while finishedCount < totalJobs do
      if not suspendGUI then
        drawGUI()
      end
      sleep(0.5)
    end
    drawGUI()
    print("\nAll chunks completed.")
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
  end,
  keyboardLoop,
  networkLoop,
  whoisBroadcaster
)
