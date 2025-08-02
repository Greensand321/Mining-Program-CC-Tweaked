-- miner.lua: chunk miner without GPS

local STATE_FILE = "state.json"
local chestSlot = 1
local label = os.getComputerLabel() or tostring(os.getComputerID())

local modemSide
for _,s in ipairs({"left","right","top","bottom","front","back"}) do
  if peripheral.getType(s) and peripheral.getType(s):match("modem") then modemSide=s break end
end
if not modemSide then error("No modem attached") end
rednet.open(modemSide)

print("[miner.lua] Awaiting start command from controller…")
print("Type 'manual' and press Enter for manual override")

local function send(tbl)
  tbl.sender = label
  rednet.broadcast(textutils.serialize(tbl))
end

send({event="hello"})

local started=false
local job=nil
local mining=false
local controllerLog={}
local LOG_LIMIT=20

local function logMsg(msg)
  table.insert(controllerLog,msg)
  if #controllerLog>LOG_LIMIT then table.remove(controllerLog,1) end
end

local function netLoop()
  while true do
    local _,msg=rednet.receive()
    logMsg(msg)
    local ok,data=pcall(textutils.unserialize,msg)
    if msg=="start" or (ok and data and data.event=="start") then
      if not started then
        started=true
        send({event="ready"})
        print("Connection to controller established")
      end
    elseif ok and type(data)=="table" then
      if data.event=="job" and data.job then
        job=data.job
      elseif data.event=="start_mining" then
        mining=true
        send({event="ack_start_mining"})
      end
    end
  end
end

local manualCommands={
  forward=turtle.forward,
  back=turtle.back,
  up=turtle.up,
  down=turtle.down,
  turnLeft=turtle.turnLeft,
  turnRight=turtle.turnRight,
  dig=turtle.dig,
  digUp=turtle.digUp,
  digDown=turtle.digDown,
  place=turtle.place
}

local commandNames={}
for k,_ in pairs(manualCommands) do table.insert(commandNames,k) end
table.sort(commandNames)

local function manualMode()
  while true do
    term.clear()
    term.setCursorPos(1,1)
    print("Manual mode - type 'exit' to return")
    print("Commands: "..table.concat(commandNames,", "))
    print("\nController log:")
    for i=math.max(1,#controllerLog-9),#controllerLog do
      print(controllerLog[i])
    end
    write("> ")
    local cmd=read()
    if cmd=="exit" then term.clear() return end
    local f=manualCommands[cmd]
    if f then pcall(f) else print("Unknown command") sleep(1) end
  end
end

local function inputLoop()
  while true do
    local line=read()
    if line=="manual" then manualMode() end
  end
end

local function mineChunk()
  local chunkX = job.chunkX or 0
  local chunkZ = job.chunkZ or 0
  local maxDepth = job.startDepth or job.maxDepth or 20

-- helpers for movement
local facing=0 --0 east,1 south,2 west,3 north
local posX,posZ=0,0

local function face(dir)
  while facing~=dir do
    turtle.turnRight()
    facing=(facing+1)%4
  end
end

local function forward()
  while not turtle.forward() do
    turtle.dig()
    turtle.attack()
    sleep(0.2)
  end
  if facing==0 then posX=posX+1
  elseif facing==1 then posZ=posZ+1
  elseif facing==2 then posX=posX-1
  else posZ=posZ-1 end
end

local function goTo(x,z)
  while posX~=x do
    if posX<x then face(0) else face(2) end
    forward()
  end
  while posZ~=z do
    if posZ<z then face(1) else face(3) end
    forward()
  end
end

local function saveState(state)
  local h=fs.open(STATE_FILE,"w")
  h.write(textutils.serialize(state))
  h.close()
end

local function loadState()
  if not fs.exists(STATE_FILE) then return nil end
  local h=fs.open(STATE_FILE,"r")
  local ok,data=pcall(textutils.unserialize,h.readAll())
  h.close()
  if ok and type(data)=="table" then return data end
end

local state=loadState() or {chunkX=chunkX,chunkZ=chunkZ,x=1,z=1,depth=0}

local function isBedrockBelow()
  local ok,data=turtle.inspectDown()
  return ok and data.name and data.name:lower():find("bedrock")
end

local function isFull()
  for i=2,16 do
    if turtle.getItemCount(i)==0 then return false end
  end
  return true
end

local function sendProgress()
  send({event="progress",chunkX=chunkX,chunkZ=chunkZ,x=state.x,z=state.z,depth=state.depth})
end

local function dumpInventory()
  local savedX,savedZ,savedDepth=state.x,state.z,state.depth
  for i=1,state.depth do turtle.up() end
  goTo(0,0)
  turtle.select(chestSlot)
  if not turtle.detectDown() then turtle.placeDown() end
  for slot=2,16 do
    turtle.select(slot)
    turtle.dropUp()
  end
  while turtle.suckUp() do end
  goTo(savedX,savedZ)
  for i=1,savedDepth do turtle.down() end
  state.depth=savedDepth
  saveState(state)
end

local function digColumn()
  while not isBedrockBelow() and state.depth<maxDepth do
    turtle.digDown()
    turtle.down()
    state.depth=state.depth+1
    saveState(state)
    sendProgress()
    if isFull() then
      dumpInventory()
    end
  end
  for i=1,state.depth do turtle.up() end
  state.depth=0
end

-- move from start position to chunk origin
face(0) forward(); face(1) forward(); face(0)

-- resume position if saved
if state.x>1 or state.z>1 or state.depth>0 then
  goTo(state.x,state.z)
  for i=1,state.depth do turtle.down() end
end

for x=state.x,15 do
  for z=(x==state.x) and state.z or 1,15 do
    state.x=x
    state.z=z
    state.depth=0
    saveState(state)
    goTo(x,z)
    digColumn()
    sendProgress()
    if isFull() then dumpInventory() end
  end
end

dumpInventory()
fs.delete(STATE_FILE)
  send({event="done"})
  print("Chunk complete")
end

local function main()
  while not started do sleep(0.1) end
  while not (job and mining) do sleep(0.1) end
  mineChunk()
end

parallel.waitForAny(main, netLoop, inputLoop)
