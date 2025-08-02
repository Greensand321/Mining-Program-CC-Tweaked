os.loadAPI("flex.lua")
os.loadAPI("dig.lua")

local args = {...}
if #args == 0 then
 flex.send("Usage: quarry <x> [z] [depth]",colors.lightBlue)
 return
end

local xmax = tonumber(args[1])
local zmax = tonumber(args[2]) or xmax
local ymin = tonumber(args[3]) or 999

if xmax == nil or zmax == nil then
 flex.send("Invalid dimensions,",colors.red)
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


local a,b,c,x,y,z,r,loc
local xdir, zdir = 1, 1
dig.gotox(0)
dig.gotoz(0)
dig.gotoy(dig.getYmin())
local done = false

while not done and not dig.isStuck() do
 
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
 flex.send("Fuel low; returning to base",colors.yellow)
 dig.gotoy(0)
 dig.goto(0,0,0,180)
 dropNotFuel()
 refuelFromChest()
 flex.send("Waiting for fuel...",colors.orange)
 while turtle.getFuelLevel()-1 <= b do
  if not refuelFromChest() then
   sleep(1)
  end --if
 end --while
 flex.send("Thanks!",colors.lime)
 dig.goto(loc)
end --if
 
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
  dig.down()
  xdir = 1
  
 elseif dig.getx() == xmax-1 and xdir == 1 then
  dig.down()
  xdir = -1
  
 else
  dig.gotox(dig.getx()+xdir)
  
 end --if/else
 
 if turtle.getItemCount(15) > 0 then
  loc = dig.location()
 dig.goto(0,0,0,180)
 dropNotFuel()
 refuelFromChest()
 dig.goto(loc)
end --if
 
end --while


dig.goto(0,0,0,180)
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