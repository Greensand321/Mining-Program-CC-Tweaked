os.loadAPI("flex.lua")
os.loadAPI("dig.lua")

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

local function refuelFromChest()
  -- try refueling from inventory first
  for i=1,16 do
    turtle.select(i)
    if turtle.refuel(1) then
      turtle.select(1)
      return true
    end
  end

  -- attempt to grab a full or partial stack into an empty slot and consume one
  for i=1,16 do
    turtle.select(i)
    if turtle.getItemCount(i) == 0 then
      if turtle.suck(64) then
        if turtle.refuel(1) then
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
    return true
  end

  turtle.select(1)
  return false
end

local function fuelNeededToReturn()
  local dx = math.abs(dig.getx())
  local dy = math.abs(dig.gety())
  local dz = math.abs(dig.getz())
  return dx + dy + dz + 5  -- buffer
end


local loc
local xdir, zdir = 1, 1
dig.gotox(0)
dig.gotoz(0)
dig.gotoy(dig.getYmin())

-- remember home location to return for unloading
local home = {
  x = dig.getx(),
  y = dig.gety(),
  z = dig.getz(),
  heading = 180,
}

local targetY = home.y - depth

-- descend initial levels if skip provided
if skip and skip > 0 then
  for i = 1, skip do
    if dig.gety() <= targetY then break end
    dig.down()
  end
end

local done = false

while not done and not dig.isStuck() do

 if dig.gety() <= targetY then
  break
 end

  local fuelLevel = turtle.getFuelLevel() - 1
  local required = fuelNeededToReturn()
  if fuelLevel <= required then
   loc = dig.location()
   flex.send("Fuel low; returning to base", colors.yellow)
   dig.gotoy(home.y)
   dig.goto(home.x, home.y, home.z, home.heading)
   dropNotFuel()
   refuelFromChest()
   flex.send("Waiting for fuel...", colors.orange)
   local timeout = 0
   local max_timeout = 10  -- seconds
   while turtle.getFuelLevel() - 1 <= required and timeout < max_timeout do
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

   flex.send("Thanks!", colors.lime)
   dig.goto(loc)
  end

 turtle.select(1)
 
 if zdir == 1 then
  dig.gotor(0)
  while dig.getz() < zmax-1 do
   dig.fwd()
   if dig.isStuck() then
    done = true
    break
   end --if
  end --while
 elseif zdir == -1 then
  dig.gotor(180)
  while dig.getz() > 0 do
   dig.fwd()
   if dig.isStuck() then
    done = true
    break
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
    xdir = 1
   end

  elseif dig.getx() == xmax-1 and xdir == 1 then
   if dig.gety() - 1 < targetY then
    done = true
   else
    dig.down()
    xdir = -1
   end

 else
   dig.gotox(dig.getx() + xdir)
  end --if/else

  if turtle.getItemCount(15) > 0 then
   loc = dig.location()
   dig.goto(home.x, home.y, home.z, home.heading)
   dropNotFuel()
   refuelFromChest()

   local timeout = 0
   local max_timeout = 10  -- seconds
   while not fillFuelStack() and timeout < max_timeout do
     sleep(1)
     timeout = timeout + 1
   end

   dig.goto(loc)
  end --if

end --while

 dig.goto(home.x, home.y, home.z, home.heading)
for x=1,16 do
 turtle.select(x)
 turtle.drop()
end

turtle.select(1)
dig.gotor(0)

if fs.exists("startup.lua") then
 shell.run("rm startup.lua")
end
os.unloadAPI("dig.lua")
os.unloadAPI("flex.lua")

