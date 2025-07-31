-- controller.lua
local STATE_FILE = "controller_state.txt"
local shaftsWide, shaftsLong, shaftSpacing = 4, 4, 3
local modemSide = peripheral.find("modem")
if not modemSide then error("No modem attached") end
rednet.open(modemSide)

-- persistent state load/save
local jobQueue, activeTasks, finishedCount, paused = {}, {}, 0, {}
local function save() 
  local h=fs.open(STATE_FILE,"w")
  h.write(textutils.serialize{jobQueue,activeTasks,finishedCount,paused})
  h.close()
end
local function load()
  if not fs.exists(STATE_FILE) then return false end
  local h=fs.open(STATE_FILE,"r")
  local t=textutils.unserialize(h.readAll()); h.close()
  jobQueue,activeTasks,finishedCount,paused = table.unpack(t)
  return true
end

local resumed = load()
if not resumed then
  for z=0,shaftsLong-1 do
    for x=0,shaftsWide-1 do
      table.insert(jobQueue,{x=x*shaftSpacing,z=z*shaftSpacing})
    end
  end
  save()
end

local function clearScreen()
  term.clear(); term.setCursorPos(1,1)
end

local function draw()
  clearScreen()
  print(("Shafts: %d  Done: %d  %%: %d"):format(
    shaftsWide*shaftsLong, finishedCount,
    math.floor(finishedCount/(shaftsWide*shaftsLong)*100)))
  print("\nActive:")
  for id,task in pairs(activeTasks) do
    print(("- %s: %s (%d,%d)"):format(id,task.status,task.job.x,task.job.z))
  end
  if next(paused) then
    print("\nPaused:")
    for id in pairs(paused) do print(" * "..id) end
    print("Type 'resume' to continue.")
  end
end

local function assign(id)
  if #jobQueue==0 then return end
  local job=table.remove(jobQueue,1)
  rednet.send(id,textutils.serialize{event="job",job=job})
  activeTasks[id]={job=job,status="mining"}
  save()
end

-- keyboard
parallel.waitForAny(function()
  while true do
    local cmd=read():match("%S+")
    if cmd=="resume" then
      for id in pairs(paused) do
        rednet.send(id,"resume")
        activeTasks[id].status="resuming"
      end
      paused={}
      save()
    end
  end
end,

-- network listener
function()
  while true do
    local sender,msg = rednet.receive()
    local ok,data = pcall(textutils.unserialize,msg)
    if ok and type(data)=="table" then
      if data.event=="hello" then
        assign(sender)
      elseif data.event=="done" then
        finishedCount=finishedCount+1
        activeTasks[sender]=nil
        assign(sender)
        save()
      elseif data.event=="chest_full" then
        paused[sender]=true
        activeTasks[sender].status="paused"
        save()
      end
    end
  end
end,

-- main GUI loop
function()
  while finishedCount<shaftsWide*shaftsLong do
    draw()
    sleep(1)
  end
  draw()
  print("\nAll shafts completed!")
  fs.delete(STATE_FILE)
end)
