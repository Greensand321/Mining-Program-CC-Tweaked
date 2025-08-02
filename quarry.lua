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
 local slot
 for i=1,16 do
  turtle.select(i)
  if turtle.getItemCount(i) > 0 and turtle.refuel(0) then
   slot = i
   break
  end --if
 end --for
 if not slot then
  turtle.select(1)
  if not turtle.suck(64) then
   turtle.select(1)
   return false
  end --if
  if not turtle.refuel(0) then
   turtle.drop()
   turtle.select(1)
   return false
  end --if
  slot = 1
 end --if
 turtle.select(slot)
 while turtle.getItemCount(slot) < 64 do
  if not turtle.suck(64 - turtle.getItemCount(slot)) then
   turtle.select(1)
   return false
  end --if
 end --while
 turtle.select(1)
 return true
end --function

local function refuelFromChest()
 for x=1,16 do
  turtle.select(x)
  if turtle.refuel(1) then
   turtle.select(1)
   return true
  end --if
 end --for
 turtle.select(1)
 if turtle.suck(1) then
  if turtle.refuel(1) then
   turtle.select(1)
   return true
  else
   turtle.drop()
  end --if
 end --if
 turtle.select(1)
 return false
end --function

local function fillFuelStack()
 for i=1,16 do
  turtle.select(i)
  if turtle.refuel(0) then
   local need = 64 - turtle.getItemCount(i)
   if need > 0 then
    turtle.suck(need)
   end --if
   turtle.select(1)
   return true
  end --if
 end --for
 turtle.select(1)
 return false
end --function


local a,b,c,x,y,z,r,loc
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

 a = turtle.getFuelLevel()-1
 b = math.abs(dig.getx())
   + math.abs(dig.gety())
   + math.abs(dig.getz())*2
 c = true
 while a <= b and c do
  for x=1,16 do
   turtle.select(x)
   if turtle.refuel(1) then
    break
   end --if
   if x == 16 then
    c = false
   end --if
  end --for
  a = turtle.getFuelLevel()-1
 end --while
 
  if a <= b then
   loc = dig.location()
   flex.send("Fuel low; returning to base", colors.yellow)
   dig.gotoy(home.y)
   dig.goto(home.x, home.y, home.z, home.heading)
   dropNotFuel()
   refuelFromChest()
   flex.send("Waiting for fuel...", colors.orange)
   while turtle.getFuelLevel() - 1 <= b do
     if not refuelFromChest() then
       sleep(1)
     end
   end

   while not fillFuelStack() do
     sleep(1)
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

   while not fillFuelStack() do
     sleep(1)
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

