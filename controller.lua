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

local CHUNK_GRID_SIZE = 16
local startDepth = 64
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
  for dz=0,CHUNK_GRID_SIZE-1 do
    for dx=0,CHUNK_GRID_SIZE-1 do
      table.insert(jobQueue, {chunkX=baseChunkX+dx, chunkZ=baseChunkZ+dz, startDepth=startDepth})
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
  print(string.format("Grid: %d x %d", CHUNK_GRID_SIZE, CHUNK_GRID_SIZE))
  print(string.format("Start Depth: %d", startDepth))
  local items = {
    "Change Mining Start Depth",
    "Start Turtle",
    "Start Mining",
    "Pause Mining",
    "Resume Mining",
    "View Status"
  }
  for i,text in ipairs(items) do
    if i==selected then print("> "..text) else print("  "..text) end
  end
  print("\nUse \226\x86\x91/\226\x86\x93 to navigate, Enter to select")
end

local function readNumber(prompt)
  term.clear()
  term.setCursorPos(1,1)
  print(prompt)
  write("> ")
  local v = tonumber(read())
  return v
end

local function changeStartDepth()
  local idx = 1
  while true do
    term.clear()
    term.setCursorPos(1,1)
    print("Change Mining Start Depth")
    local options = {"Enter New Start Depth (current: "..startDepth..")","Back"}
    for i,opt in ipairs(options) do
      if i==idx then print("> "..opt) else print("  "..opt) end
    end
    local _,key=os.pullEvent("key")
    if key==keys.up then idx=math.max(1,idx-1)
    elseif key==keys.down then idx=math.min(2,idx+1)
    elseif key==keys.enter then
      if idx==1 then
        local v=readNumber("Enter starting elevation (e.g. 64):")
        if v then startDepth=v end
      else
        return
      end
    elseif key==keys.backspace then return end
  end
end

local function listTurtles()
  local labels = {}
  for l,_ in pairs(turtles) do table.insert(labels,l) end
  table.sort(labels)
  return labels
end

local function startTurtle()
  local labels = listTurtles()
  local options = {"Back"}
  for _,l in ipairs(labels) do table.insert(options,l) end
  local idx=1
  while true do
    term.clear()
    term.setCursorPos(1,1)
    print("Start Turtle")
    for i,opt in ipairs(options) do
      if i==idx then print("> "..opt) else print("  "..opt) end
    end
    local _,key=os.pullEvent("key")
    if key==keys.up then idx=math.max(1,idx-1)
    elseif key==keys.down then idx=math.min(#options,idx+1)
    elseif key==keys.enter then
      if idx==1 then return end
      local t=turtles[options[idx]]
      if t then
        send(t.id,{event="start"})
        t.started=true
      end
      return
    elseif key==keys.backspace then return end
  end
end

local function startMining()
  local idx=1
  while true do
    term.clear()
    term.setCursorPos(1,1)
    print("Start Mining")
    local opts={"Back","Confirm Start Mining"}
    for i,opt in ipairs(opts) do
      if i==idx then print("> "..opt) else print("  "..opt) end
    end
    local _,key=os.pullEvent("key")
    if key==keys.up then idx=math.max(1,idx-1)
    elseif key==keys.down then idx=math.min(#opts,idx+1)
    elseif key==keys.enter then
      if idx==1 then return end
      buildJobs()
      miningActive=true
      for _,t in pairs(turtles) do
        if t.started then send(t.id,{event="start_mining"}) end
      end
      assignAll()
      viewStatus(true)
      return
    elseif key==keys.backspace then return end
  end
end

local function pauseMining()
  local idx=1
  while true do
    term.clear()
    term.setCursorPos(1,1)
    print("Pause Mining")
    local opts={"Back","Confirm Pause"}
    for i,opt in ipairs(opts) do
      if i==idx then print("> "..opt) else print("  "..opt) end
    end
    local _,key=os.pullEvent("key")
    if key==keys.up then idx=math.max(1,idx-1)
    elseif key==keys.down then idx=math.min(#opts,idx+1)
    elseif key==keys.enter then
      if idx==1 then return else paused=true return end
    elseif key==keys.backspace then return end
  end
end

local function resumeMining()
  local idx=1
  while true do
    term.clear()
    term.setCursorPos(1,1)
    print("Resume Mining")
    local opts={"Back","Confirm Resume"}
    for i,opt in ipairs(opts) do
      if i==idx then print("> "..opt) else print("  "..opt) end
    end
    local _,key=os.pullEvent("key")
    if key==keys.up then idx=math.max(1,idx-1)
    elseif key==keys.down then idx=math.min(#opts,idx+1)
    elseif key==keys.enter then
      if idx==1 then return else paused=false assignAll() return end
    elseif key==keys.backspace then return end
  end
end

local function viewStatus(loop)
  local idx=1
  while true do
    term.clear()
    term.setCursorPos(1,1)
    print("Status:")
    for label,t in pairs(turtles) do
      local job=t.job and string.format("(%d,%d)",t.job.chunkX,t.job.chunkZ) or "-"
      local prog=t.progress and string.format("x=%d z=%d d=%d",t.progress.x,t.progress.z,t.progress.depth) or ""
      local err=t.error or ""
      print(string.format("%s : %s %s %s",label,job,prog,err))
    end
    local opts={"Back","Refresh Status"}
    for i,opt in ipairs(opts) do
      if i==idx then print("> "..opt) else print("  "..opt) end
    end
    local _,key=os.pullEvent("key")
    if key==keys.up then idx=math.max(1,idx-1)
    elseif key==keys.down then idx=math.min(#opts,idx+1)
    elseif key==keys.enter then
      if idx==1 then return elseif idx==2 then -- refresh
      end
    elseif key==keys.backspace then return end
    if not loop then return end
  end
end

local actions = {changeStartDepth,startTurtle,startMining,pauseMining,resumeMining,viewStatus}

local function menuLoop()
  local selected=1
  while true do
    drawMenu(selected)
    local _,key=os.pullEvent("key")
    if key==keys.up then selected=math.max(1,selected-1)
    elseif key==keys.down then selected=math.min(6,selected+1)
    elseif key==keys.enter then actions[selected]() end
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
