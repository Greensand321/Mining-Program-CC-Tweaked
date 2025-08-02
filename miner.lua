-- miner.lua (NO GPS)
local CHUNK_SIZE = 16
local DEPTH = 64

local modem = peripheral.find("modem")
if not modem then error("No modem attached") end
rednet.open(peripheral.getName(modem))

local label = os.getComputerLabel()
if not label then error("Label not set. Use: label set <name>") end

local function moveForwardSafe()
  while not turtle.forward() do
    turtle.dig()
    sleep(0.2)
  end
end

local function digColumn()
  for _ = 1, DEPTH do
    if not turtle.detectDown() then turtle.digDown() end
    turtle.down()
  end
  for _ = 1, DEPTH do
    turtle.up()
  end
end

local function mineChunk()
  for row = 1, CHUNK_SIZE do
    for col = 1, CHUNK_SIZE do
      digColumn()
      if col < CHUNK_SIZE then moveForwardSafe() end
    end
    if row < CHUNK_SIZE then
      if row % 2 == 1 then
        turtle.turnRight()
        moveForwardSafe()
        turtle.turnRight()
      else
        turtle.turnLeft()
        moveForwardSafe()
        turtle.turnLeft()
      end
    end
  end
  rednet.broadcast(textutils.serialize({ event = "done", sender = label }))
end

-- Main loop
rednet.broadcast(textutils.serialize({ event = "hello", sender = label }))
while true do
  local _, msg = rednet.receive()
  local ok, data = pcall(textutils.unserialize, msg)
  if ok and type(data) == "table" then
    if data.event == "job" then
      mineChunk()
    elseif data.event == "set_depth" then
      DEPTH = tonumber(data.maxDepth) or DEPTH
    elseif data.event == "ping" then
      rednet.broadcast(textutils.serialize({ event = "pong", sender = label }))
    end
  elseif msg == "resume" then
    mineChunk()
  end
end
