-- controller.lua: simple mining controller with menu interface

local modemSide
for _,side in ipairs({"left","right","top","bottom","front","back"}) do
  if peripheral.getType(side) and peripheral.getType(side):match("modem") then
    modemSide = side
    break
  end
end
if not modemSide then error("No modem attached") end
rednet.open(modemSide)

local chunksWide, chunksHigh = 4, 4
local maxDepth = 20
local baseChunkX, baseChunkZ = 0, 0

local turtles = {} -- label -> {id=, started=bool, ready=bool, job=table, progress=table, error=string}
local jobQueue = {}
local miningActive = false
local paused = false

local function send(id, data)
  rednet.send(id, textutils.serialize(data))
end

local function buildJobs()
  jobQueue = {}
  for dz=0,chunksHigh-1 do
    for dx=0,chunksWide-1 do
      table.insert(jobQueue, {chunkX=baseChunkX+dx, chunkZ=baseChunkZ+dz, maxDepth=maxDepth})
    end
  end
end

local function assignJob(t)
  if paused or not miningActive then return end
  if t.job or not t.ready then return end
  if #jobQueue == 0 then return end
  local job = table.remove(jobQueue,1)
  t.job = job
  send(t.id, {event="job", job=job})
end

local function assignAll()
  for _,t in pairs(turtles) do assignJob(t) end
end

local function drawMenu(selected)
  term.clear()
  term.setCursorPos(1,1)
  print("Mining Controller")
  print(string.format("Grid: %d x %d", chunksWide, chunksHigh))
  print(string.format("Depth: %d", maxDepth))
  local items = {
    "Configure Grid Size",
    "Set Mining Depth",
    "Start Turtle",
    "Start Mining",
    "Pause Mining",
    "Resume Mining",
    "View Status"
  }
  for i,text in ipairs(items) do
    if i==selected then print("> "..text) else print("  "..text) end
  end
  print("\nUse arrow keys, Tab to select")
end

local function readNumber(prompt)
  term.clear()
  term.setCursorPos(1,1)
  print(prompt)
  write("> ")
  local v = tonumber(read())
  return v
end

local function configureGrid()
  local idx = 1
  while true do
    term.clear()
    term.setCursorPos(1,1)
    print("Configure Grid Size")
    local options = {"Width: "..chunksWide, "Height: "..chunksHigh}
    for i,opt in ipairs(options) do
      if i==idx then print("> "..opt) else print("  "..opt) end
    end
    print("Tab to edit, Esc to back")
    local _,key = os.pullEvent("key")
    if key==keys.up then idx=math.max(1,idx-1)
    elseif key==keys.down then idx=math.min(2,idx+1)
    elseif key==keys.tab then
      local val = readNumber("Enter number of chunks (e.g. 4):")
      if val then if idx==1 then chunksWide=val else chunksHigh=val end end
    elseif key==keys.escape then break end
  end
end

local function setDepth()
  local v = readNumber("Enter maximum shaft depth in blocks (e.g. 20):")
  if v then maxDepth = v end
end

local function listTurtles()
  local labels = {}
  for l,_ in pairs(turtles) do table.insert(labels,l) end
  table.sort(labels)
  return labels
end

local function startTurtle()
  local labels = listTurtles()
  if #labels==0 then return end
  local idx=1
  while true do
    term.clear()
    term.setCursorPos(1,1)
    print("Start Turtle")
    for i,lbl in ipairs(labels) do
      if i==idx then print("> "..lbl) else print("  "..lbl) end
    end
    print("Tab to start, Esc to back")
    local _,key = os.pullEvent("key")
    if key==keys.up then idx=math.max(1,idx-1)
    elseif key==keys.down then idx=math.min(#labels,idx+1)
    elseif key==keys.tab then
      local t = turtles[labels[idx]]
      if t then
        send(t.id,{event="start"})
        t.started=true
      end
      break
    elseif key==keys.escape then break end
  end
end

local function startMining()
  buildJobs()
  miningActive=true
  assignAll()
end

local function pauseMining()
  paused=true
end

local function resumeMining()
  paused=false
  assignAll()
end

local function viewStatus()
  term.clear()
  term.setCursorPos(1,1)
  print("Status:")
  for label,t in pairs(turtles) do
    local job = t.job and string.format("(%d,%d)", t.job.chunkX, t.job.chunkZ) or "-"
    local prog = t.progress and string.format("x=%d z=%d d=%d", t.progress.x, t.progress.z, t.progress.depth) or ""
    local err = t.error or ""
    print(string.format("%s : %s %s %s", label, job, prog, err))
  end
  print("\nPress any key")
  os.pullEvent("key")
end

local actions = {configureGrid,setDepth,startTurtle,startMining,pauseMining,resumeMining,viewStatus}

local function menuLoop()
  local selected=1
  while true do
    drawMenu(selected)
    local _,key=os.pullEvent("key")
    if key==keys.up then selected=math.max(1,selected-1)
    elseif key==keys.down then selected=math.min(7,selected+1)
    elseif key==keys.tab then actions[selected]()
    end
  end
end

local function netLoop()
  while true do
    local id,msg = rednet.receive()
    local ok,data = pcall(textutils.unserialize,msg)
    if ok and type(data)=="table" then
      local label = data.sender or tostring(id)
      if not turtles[label] then turtles[label]={id=id,label=label} end
      local t = turtles[label]
      t.id=id
      if data.event=="hello" then
        -- nothing extra
      elseif data.event=="ready" then
        t.ready=true
        assignJob(t)
      elseif data.event=="progress" then
        t.progress={x=data.x,z=data.z,depth=data.depth}
      elseif data.event=="done" then
        t.job=nil
        assignJob(t)
      elseif data.event=="error" then
        t.error=data.code
      end
    end
  end
end

parallel.waitForAny(menuLoop, netLoop)
