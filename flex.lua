--Misc Useful Functions
--Flexico64@gmail.com


modem_channel = 6464

local x,sides, modem, hasModem
sides = { "top", "bottom", "left",
          "right", "front", "back" }
hasModem = false
for x=1,#sides do
 if peripheral.getType(sides[x]) == "modem" then
  modem = peripheral.wrap(sides[x])
  hasModem = true
  break
 end
end


local file
if fs.exists("log.txt") then
 file = fs.open("log.txt","a")
else
 file = fs.open("log.txt","w")
end --if/else
file.close()


function send(message,color)
 
 local x,y
 if type(message) == "table" then
  send("{",color)
  for x, y in pairs(message) do
   send(y,color)
  end --for
  send("}",color)
  return
 end --if
 
 if message == nil then
  message = "nil"
 end --if
 
 message = tostring(message)
 color = color or colors.white
 
 term.setTextColor(color)
 print(message)
 term.setTextColor(colors.white)
 
 file = fs.open("log.txt","a")
 file.writeLine(message)
 file.close()
 
 if hasModem then
  id = tostring(os.getComputerID())
  if os.getComputerLabel() ~= nil then
   id = id..":"..os.getComputerLabel()
  end --if
  modem.transmit(modem_channel,modem_channel,
    "#"..tonumber(color).."#"..id..": "..message)
  sleep(0.1)
 end --if
 
end --funtion


-- Inventory Condense
function condense()
 local x,y,slot
 slot = turtle.getSelectedSlot()
 for x=2,16 do
  turtle.select(x)
  for y=1,x-1 do
   if turtle.getItemCount(x) == 0 then
    break
   end --if
   turtle.transferTo(y)
  end --for
 end --for
 turtle.select(slot)
end --function


--Dump Inventory
function dump(a,b)
 a = a or 1
 b = b or 16
 local x,slot
 slot = turtle.getSelectedSlot()
 for x=a,b do
  turtle.select(x)
  turtle.drop()
 end --for
 turtle.select(slot)
end --function


--Round to Integer
function round(n)
 local m = n - math.floor(n)
 if m < 0.5 then return math.floor(n)
 else return -math.floor(-n)
 end --if/else
end --function


--Press any key
function keyPress()
 local event, key_code = os.pullEvent("key")
 return key_code
end --function


-- GET BLOCK ID
function getBlock(dir)
 dir = dir or "forward"
 local block,meta
 
 if dir=="forward" or dir=="fwd" then
  block,meta = turtle.inspect()
  
 elseif dir=="up" then
  block,meta = turtle.inspectUp()
  
 elseif dir=="down" then
  block,meta = turtle.inspectDown()
 end
 
 if block then
  block = meta["name"]
  meta = meta["metadata"]
  return block,meta
 else
  return "minecraft:air",nil
 end
 
end