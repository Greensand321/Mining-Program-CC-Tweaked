-- This is an API for digging and
-- keeping track of motion
-- Flexico64@gmail.com

-- x is right, y is up, z is forward
-- r is clockwise rotation in degrees

os.loadAPI("flex.lua")

dist_x = 0
xmin = 0
xmax = 0

dist_y = 0
ymin = 0
ymax = 0

dist_z = 0
zmin = 0
zmax = 0

dist_r = 0
lastMove = "?"

function getx() return dist_x end
function gety() return dist_y end
function getz() return dist_z end
function getr() return dist_r end

function setx(x) dist_x = x end
function sety(y) dist_y = y end
function setz(z) dist_z = z end
function setr(r) dist_r = r end

function getLastMove()
 return lastMove
end
function setLastMove(lm)
 lastMove = lm
end

function getXmin() return xmin end
function getXmax() return xmax end
function getYmin() return ymin end
function getYmax() return ymax end
function getZmin() return zmin end
function getZmax() return zmax end

function setXmin(x) xmin = x end
function setXmax(x) xmax = x end
function setYmin(y) ymin = y end
function setYmax(y) ymax = y end
function setZmin(z) zmin = z end
function setZmax(z) zmax = z end


fuelSlot = {1,16}

function getFuelSlot()
 return fuelSlot[1],fuelSlot[2]
end

function setFuelSlot(a,b)
 b = b or a
 fuelSlot[1] = a
 fuelSlot[2] = b
end


function location()
 return
  { dist_x, dist_y, dist_z, dist_r,
    lastMove, xmin, xmax, ymin,
    ymax, zmin, zmax }
end

function saveCoords()
 local file,loc,x
 file = fs.open("dig_save.txt","w")
 loc = location()
 for x=1,#loc do
  file.writeLine(tostring(loc[x]))
 end --for
 file.close()
end --function

function loadCoords()
 local file
 file = fs.open("dig_save.txt","r")
 dist_x = tonumber(file.readLine())
 dist_y = tonumber(file.readLine())
 dist_z = tonumber(file.readLine())
 dist_r = tonumber(file.readLine())
 lastMove = file.readLine()
 xmin = tonumber(file.readLine())
 xmax = tonumber(file.readLine())
 ymin = tonumber(file.readLine())
 ymax = tonumber(file.readLine())
 zmin = tonumber(file.readLine())
 zmax = tonumber(file.readLine())
 file.close()
end


function makeStartup(command, args)
 command = tostring(command)
 local x
 for x=1,#args do
  command = command.." "..args[x]
 end --for
 local file = fs.open("startup.lua","w")
 file.writeLine("os.loadAPI(\"flex.lua\")")
 file.writeLine("flex.send(\"> "..command.."\")")
 file.writeLine("shell.run(\""..command.."\")")
 file.writeLine("os.unloadAPI(\"flex.lua\")")
 file.close()
end --function


stuck = false
function isStuck()
 return stuck
end


function update(n)
 
 if n=="fwd" then
  
  if dist_r == 0 then
   dist_z = dist_z + 1
   lastMove = "z+"
   
  elseif dist_r == 90 then
   dist_x = dist_x + 1
   lastMove = "x+"
   
  elseif dist_r == 180 then
   dist_z = dist_z - 1
   lastMove = "z-"
   
  elseif dist_r == 270 then
   dist_x = dist_x - 1
   lastMove = "x-"
   
  end
 
 elseif n=="up" then
  dist_y = dist_y + 1
  lastMove = "y+"
  
 elseif n=="down" then
  dist_y = dist_y - 1
  lastMove = "y-"
  
 elseif n=="right" then
  dist_r = dist_r + 90
  
 elseif n=="left" then
  dist_r = dist_r - 90
  
 end
 
 while dist_r >= 360 do
  dist_r = dist_r - 360
 end
 while dist_r < 0 do
  dist_r = dist_r + 360
 end
 
 if dist_x < xmin then
  xmin = dist_x
 elseif dist_x > xmax then
  xmax = dist_x
 end
 
 if dist_y < ymin then
  ymin = dist_y
 elseif dist_y > ymax then
  ymax = dist_y
 end
 
 if dist_z < zmin then
  zmin = dist_z
 elseif dist_z > zmax then
  zmax = dist_z
 end
 
 saveCoords()
 
end


-- MOVEMENT FUNCTIONS

function refuel(b)
 b = b or 1
 local a,x,z,slot
 slot = turtle.getSelectedSlot()
 a = true
 while turtle.getFuelLevel() < b do
  for x=fuelSlot[1],fuelSlot[2] do
   turtle.select(x)
   if turtle.refuel(1) then break end
   if x == fuelSlot[2] and a then
    flex.send("Waiting for fuel...",colors.orange)
    a = false
   end --if
  end --for
 end --while
 if not a then
  flex.send("Thanks!",colors.lime)
 end --if
 turtle.select(slot)
end --function


function fwd(n)
 local x,a,b
 for x=1, n or 1 do
  refuel()
  if flex.getBlock() == "minecraft:tall_grass" or
     flex.getBlock() == "minecraft:tallgrass" or
     flex.getBlock() == "minecraft:grass" then
   turtle.dig()
  end
  stuck = false
  while not turtle.forward() do
   a,b = turtle.dig()
   if b == "Unbreakable block detected" then
    flex.send(b,colors.orange)
    stuck = true
    return
   end
   --turtle.attack()
  end
  update("fwd")
 end
end

function up(n)
 local x,a,b
 for x=1, n or 1 do
  refuel()
  stuck = false
  while not turtle.up() do
   a,b = turtle.digUp()
   if b == "Unbreakable block detected" then
    flex.send(b,colors.orange)
    stuck = true
    return
   end
   --turtle.attackUp()
  end
  update("up")
 end
 if (n or 1) < 0 then
  down(-n)
 end
end

function down(n)
 local x
 for x=1, n or 1 do
  refuel()
  stuck = false
  while not turtle.down() do
   a,b = turtle.digDown()
   if b == "Unbreakable block detected" then
    flex.send(b,colors.orange)
    stuck = true
    return
   end
   --turtle.attackDown()
  end
  update("down")
 end
 if (n or 1) < 0 then
  up(-n)
 end
end

function left(n)
 local x
 for x=1, n or 1 do
  turtle.turnLeft()
  update("left")
 end
 for x=n or 1, -1 do
  turtle.turnRight()
  update("right")
 end
end

function right(n)
 local x
 for x=1, n or 1 do
  turtle.turnRight()
  update("right")
 end
 for x=n or 1, -1 do
  turtle.turnLeft()
  update("left")
 end
end

function dig()
 while turtle.dig() do end
end


-- GOTO FUNCTIONS

function gotor(r)
 local r = math.floor(r/90)*90
 while r>=360 do r = r-360 end
 while r<0 do r = r+360 end
 
 local x = r-dist_r
 while x < 0 do x = x+360 end
 if x == 90 then right()
 elseif x == 180 then
  if r == 0 then right(2)
  else left(2) end
 elseif x == 270 then left()
 end
end

function gotoy(y)
 while dist_y < y do
  up()
 end
 while dist_y > y do
  down()
 end
end

function gotox(x)
 if dist_x < x then
  gotor(90)
 end
 if dist_x > x then
  gotor(270)
 end
 while dist_x ~= x do
  fwd()
 end
end

function gotoz(z)
 if dist_z < z then
  gotor(0)
 end
 if dist_z > z then
  gotor(180)
 end
 while dist_z ~= z do
  fwd()
 end
end

function goto(x,y,z,r,lm)
 if type(x) == "table" then
  if #x < 4 then
   flex.send("Invalid Goto Table",colors.red)
   return
  end
  y = x[2]
  z = x[3]
  r = x[4]
  lm = x[5]
  x = x[1]
 end
 gotoz(z or 0)
 gotox(x or 0)
 gotor(r or 0)
 gotoy(y or 0)
 setLastMove(lm or "?")
end

-------

function place()
 while not turtle.place() and (
    flex.getBlock()=="minecraft:air" or
    flex.getBlock()=="minecraft:water" or
    flex.getBlock()=="minecraft:lava" ) do
  turtle.attack()
  turtle.attackUp()
  turtle.attackDown()
 end
end

function placeUp()
 while not turtle.placeUp() and (
    flex.getBlock("up")=="minecraft:air" or
    flex.getBlock("up")=="minecraft:water" or
    flex.getBlock("up")=="minecraft:lava" ) do
  turtle.attack()
  turtle.attackUp()
 end
end

function placeDown()
 while not turtle.placeDown() and (
    flex.getBlock("down")=="minecraft:air" or
    flex.getBlock("down")=="minecraft:water" or
    flex.getBlock("down")=="minecraft:lava" ) do
  turtle.attack()
  turtle.attackDown()
 end
end