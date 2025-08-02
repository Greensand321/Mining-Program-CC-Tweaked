distance = 2

function make_stairs(dist)
	for i=1, dist do
		if not turtle.forward() then
			turtle.dig()
			turtle.forward()
		end
		if turtle.detectUp() then
			turtle.digUp()
		end
		if not turtle.down() then
			turtle.digDown()
			turtle.down()
		end
		if turtle.detectDown() == false then
			turtle.placeDown()
		else
			local success, block_down = turtle.inspectDown()
			for key, value in pairs(block_down) do
				if value == "minecraft:bedrock" then
					return
				end
			end
		end
		os.run({},"em_refuel.lua","script")
	end
end

make_stairs(distance)