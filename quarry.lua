os.loadAPI("flex.lua")
os.loadAPI("dig.lua")

local fuelValues = {
  ["minecraft:coal"] = 80,
  ["minecraft:charcoal"] = 80,
  ["minecraft:blaze_rod"] = 120,
  ["minecraft:lava_bucket"] = 1000,
}

local function inventoryFuelUnits()
  local total = 0
  local slot = turtle.getSelectedSlot()
  for i = 1, 16 do
    turtle.select(i)
    local detail = turtle.getItemDetail()
    if detail and detail.name then
      local per = fuelValues[detail.name]
      if per then
        total = total + per * detail.count
      end
    end
  end
  turtle.select(slot)
  return total
end

local function totalAvailableFuel()
  return turtle.getFuelLevel() + inventoryFuelUnits()
end

-- argument parsing
local args = {...}
if #args == 0 then
  flex.send("Usage: quarry <x> [z] [depth] [skip]", colors.lightBlue)
  return
end

local xmax = tonumber(args[1])
local zmax = tonumber(args[2]) or xmax
local depth = tonumber(args[3]) or math.huge
local skip = nil
if args[4] and args[4] ~= "" then
  skip = tonumber(args[4])
  if not skip then
    flex.send("Warning: skip value invalid, ignoring.", colors.yellow)
    skip = nil
  end
end

if not xmax or not zmax then
  flex.send("Invalid dimensions.", colors.red)
  return
end


if fs.exists("startup.lua") and
   fs.exists("dig_save.txt") then
 dig.loadCoords()
 
end --if
dig.makeStartup("quarry",args)


-- networking setup
local modemSide
for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
  if peripheral.getType(side) == "modem" then
    modemSide = side
    break
  end
end
if modemSide then
  rednet.open(modemSide)
end

local globalCommand = ""
local function pollGlobal()
  local senderId, message = rednet.receive(0)
  if message then
    message = tostring(message):upper():gsub("%s+", "")
    if message == "RETURN" then
      globalCommand = "RETURN"
    end
  end
  return globalCommand
end

-- crash-safe run flag
local runFlag = "quarry_running.flag"
if fs.exists(runFlag) then
  globalCommand = "RETURN"
else
  local f = fs.open(runFlag, "w")
  f.write("running")
  f.close()
end


local function dropNotFuel()
 flex.condense()
 local a,x
 a = false
 for x=1,16 do
  turtle.select(x)
  if turtle.refuel(0) then
   if a then turtle.drop() end
   a = true
  else
   turtle.drop()
  end --if
 end --for
 turtle.select(1)
end --function

local function fillFuelStack()
  -- try existing fuel slot first
  for i=1,16 do
    turtle.select(i)
    if turtle.getItemCount(i) > 0 and turtle.refuel(0) then
      -- top up if possible but don’t block on full stack
      if turtle.getItemCount(i) < 64 then
        turtle.suck(64 - turtle.getItemCount(i))
      end
      turtle.select(1)
      return true
    end
  end

  -- no existing fuel: grab any available fuel from chest into empty slot
  for i=1,16 do
    turtle.select(i)
    if turtle.getItemCount(i) == 0 then
      turtle.suck(64)  -- will pull up to available amount
      if turtle.getItemCount(i) > 0 and turtle.refuel(0) then
        turtle.select(1)
        return true
      else
        if turtle.getItemCount(i) > 0 then turtle.drop() end
      end
    end
  end

  turtle.select(1)
  return false
end
local xdir, zdir = 1, 1
dig.gotox(0)
if dig.isStuck() and not recoverStuck() then return end
dig.gotoz(0)
if dig.isStuck() and not recoverStuck() then return end
dig.gotoy(dig.getYmin())
if dig.isStuck() and not recoverStuck() then return end

-- remember home location to return for unloading
local home = {
  x = dig.getx(),
  y = dig.gety(),
  z = dig.getz(),
  heading = 180,
}

local targetY = home.y - depth
local coalFuelValue = 80
local lowFuelThreshold = 3 * coalFuelValue

local function topUpInternalFuel()
  while turtle.getFuelLevel() < lowFuelThreshold and turtle.refuel(1) do
  end
end

local function refuelFromChest()
  -- try refueling from inventory first
  for i = 1, 16 do
    turtle.select(i)
    if turtle.refuel(1) then
      topUpInternalFuel()
      turtle.select(1)
      return true
    end
  end

  -- attempt to grab a full or partial stack into an empty slot and consume one
  for i = 1, 16 do
    turtle.select(i)
    if turtle.getItemCount(i) == 0 then
      if turtle.suck(64) then
        if turtle.refuel(1) then
          topUpInternalFuel()
          turtle.select(1)
          return true
        else
          turtle.drop()
        end
      end
    end
  end

  -- last resort: single item from chest
  turtle.select(1)
  if turtle.suck(1) and turtle.refuel(1) then
    topUpInternalFuel()
    return true
  end

  turtle.select(1)
  return false
end

local function recoverStuck()
  flex.send(string.format("Stuck at %d,%d,%d; attempting recovery", dig.getx(), dig.gety(), dig.getz()), colors.red)
  local heading = dig.getr()
  local attempts = 0
  while dig.isStuck() and attempts < 3 do
    dig.dig()
    dig.gotor(heading + 180)
    dig.fwd()
    dig.gotor(heading)
    dig.fwd()
    attempts = attempts + 1
  end
  if dig.isStuck() then
    flex.send(string.format("Unrecoverable stuck at %d,%d,%d after %d attempts", dig.getx(), dig.gety(), dig.getz(), attempts), colors.red)
    return false
  end
  return true
end

local function isContainer(data)
  return data and data.name and (data.name:find("chest") or data.name:find("barrel"))
end

local function isNextToChest()
  local function check(inspectFunc)
    local ok, data = inspectFunc()
    return ok and isContainer(data)
  end
  if check(turtle.inspect) then return true end
  if check(turtle.inspectUp) then return true end
  if check(turtle.inspectDown) then return true end
  turtle.turnLeft()
  if check(turtle.inspect) then turtle.turnRight(); return true end
  turtle.turnRight()
  if check(turtle.inspect) then turtle.turnLeft(); return true end
  turtle.turnLeft()
  return false
end

local function waitForChest()
  local err = "ERROR: No chest detected at home. Staying put."
  if flex and colors then
    flex.send(err, colors.red)
  else
    print(err)
  end
  while not isNextToChest() do
    sleep(5)
  end
end

local function returnToBase(returnAfter)
  local loc
  if returnAfter ~= false then
    loc = dig.location()
  end
  dig.goto(home.x, home.y, home.z, home.heading)
  if dig.isStuck() and not recoverStuck() then return false end
  if not isNextToChest() then
    waitForChest()
  end
  dropNotFuel()
  local timeout = 0
  local max_timeout = 10  -- seconds
  while totalAvailableFuel() < lowFuelThreshold and timeout < max_timeout do
    if not refuelFromChest() then
      sleep(1)
    end
    timeout = timeout + 1
  end
  timeout = 0
  while not fillFuelStack() and timeout < max_timeout do
    sleep(1)
    timeout = timeout + 1
  end
  topUpInternalFuel()
  if returnAfter ~= false then
    dig.goto(loc)
    if dig.isStuck() and not recoverStuck() then return false end
  end
  turtle.select(1)
  globalCommand = ""
  return true
end

if globalCommand == "RETURN" then
  returnToBase()
end

-- descend initial levels if skip provided
if skip and skip > 0 then
  for i = 1, skip do
    if dig.gety() <= targetY then break end
    dig.down()
    if dig.isStuck() and not recoverStuck() then return end
  end
end

local done = false

while not done do

  pollGlobal()
  if globalCommand == "RETURN" then
    returnToBase()
  end

  local internal = turtle.getFuelLevel()
  local inventory = inventoryFuelUnits()
  local total = internal + inventory
  flex.send(string.format("Fuel: internal=%d inventory=%d total=%d", internal, inventory, total), colors.gray)
  if total < lowFuelThreshold then
    flex.send("Fuel low; returning to base", colors.yellow)
    returnToBase()
  end

  turtle.select(1)

 if zdir == 1 then
  dig.gotor(0)
  while dig.getz() < zmax-1 do
   dig.fwd()
   if dig.isStuck() then
    if not recoverStuck() then return end
   end --if
  end --while
 elseif zdir == -1 then
  dig.gotor(180)
  while dig.getz() > 0 do
   dig.fwd()
   if dig.isStuck() then
    if not recoverStuck() then return end
   end
  end --while
 end --if/else

 if done then break end
 
 zdir = -zdir
 
  if dig.getx() == 0 and xdir == -1 then
   if dig.gety() - 1 < targetY then
    done = true
   else
    dig.down()
    if dig.isStuck() and not recoverStuck() then return end
    xdir = 1
   end

  elseif dig.getx() == xmax-1 and xdir == 1 then
   if dig.gety() - 1 < targetY then
    done = true
   else
    dig.down()
    if dig.isStuck() and not recoverStuck() then return end
    xdir = -1
   end

 else
   dig.gotox(dig.getx() + xdir)
   if dig.isStuck() and not recoverStuck() then return end
  end --if/else

  if turtle.getItemCount(15) > 0 then
    returnToBase()
  end

end --while

 dig.goto(home.x, home.y, home.z, home.heading)
 if dig.isStuck() and not recoverStuck() then return end
 if not isNextToChest() then
  waitForChest()
 end
for x=1,16 do
 turtle.select(x)
 turtle.drop()
end

refuelFromChest()
local timeout = 0
local max_timeout = 10  -- seconds
while totalAvailableFuel() < lowFuelThreshold and timeout < max_timeout do
 if not refuelFromChest() then
  sleep(1)
 end
 timeout = timeout + 1
end

timeout = 0
while not fillFuelStack() and timeout < max_timeout do
 sleep(1)
 timeout = timeout + 1
end

topUpInternalFuel()

turtle.select(1)
dig.gotor(0)

if fs.exists(runFlag) then fs.delete(runFlag) end

if fs.exists("startup.lua") then
 shell.run("rm startup.lua")
end
os.unloadAPI("dig.lua")
os.unloadAPI("flex.lua")

